import Combine
import Foundation
import Kingfisher

/// 预取器 completion 独立持有的轻量批次状态，不反向持有 Paginator 或 ViewModel。
@MainActor
final class PaginatorImagePrefetchBatch {
  let urls: Set<URL>
  private var isComplete = false
  private var cleanupAfterPop: (@MainActor @Sendable (Set<URL>) -> Void)?

  init(urls: Set<URL>) {
    self.urls = urls
  }

  func retire(cleanup: @escaping @MainActor @Sendable (Set<URL>) -> Void) {
    guard !isComplete else { return }
    cleanupAfterPop = cleanup
  }

  func complete() {
    guard !isComplete else { return }
    isComplete = true
    let cleanup = cleanupAfterPop
    cleanupAfterPop = nil
    cleanup?(urls)
  }
}

@MainActor
private final class PaginatorImagePrefetchRegistry {
  private var batches: [UUID: PaginatorImagePrefetchBatch] = [:]

  func insert(_ batch: PaginatorImagePrefetchBatch) -> UUID {
    let id = UUID()
    batches[id] = batch
    return id
  }

  func retireAll(cleanup: @escaping @MainActor @Sendable (Set<URL>) -> Void) {
    batches.values.forEach { $0.retire(cleanup: cleanup) }
  }

  func complete(_ batch: PaginatorImagePrefetchBatch, id: UUID) {
    batch.complete()
    batches.removeValue(forKey: id)
  }
}

@MainActor
public class Paginator<ItemType: Identifiable>: ObservableObject {
  deinit {
    // 保留显式 deinit，维持既有 SIL 生成路径；同时清理未完成的加载和预取任务。
    inFlightLoadTask?.cancel()
    activePrefetchers.forEach { $0.stop() }
  }

  // MARK: - 公开状态

  /// 分页器加载的项目数组。可被 UI 观察。
  @Published public private(set) var items: [ItemType] = []

  /// 一个布尔值，指示加载操作是否正在进行中。
  @Published public private(set) var isLoading: Bool = false

  /// 一个布尔值，指示是否是首次加载。
  @Published public private(set) var isFirstLoading: Bool = false

  /// 一个布尔值，指示是否正在加载更多内容。
  @Published public private(set) var isLoadingMore: Bool = false

  /// 一个布尔值，指示是否还有更多内容要加载。
  @Published public private(set) var hasMore: Bool = true

  /// 一个布尔值，指示当前是否处于加载出错状态。
  @Published public private(set) var hasError: Bool = false

  /// 记录最后一次发生的错误，用于向用户展示或日志排查。
  @Published public private(set) var lastError: Error?

  // MARK: - 私有状态

  private var page: Int = 1
  private var consecutiveErrorCount: Int = 0
  private let maxConsecutiveErrors: Int = 3
  private var generation: Int = 0
  private var inFlightLoadTask: Task<Void, Never>?
  private var inFlightLoadTaskToken: Int = 0
  private var pendingRestartLoadTaskToken: Int?
  private let maxRestartRoundsPerSequence: Int = 5

  /// 获取一页项目的函数。
  private let fetcher: @MainActor (Int) async throws -> [ItemType]

  /// 预取图片 URL 的函数。
  private let imageURLsProvider: (@MainActor (ItemType) -> [URL])?

  /// 与实际卡片显示一致的图片处理器，避免预取额外缓存默认处理器的大图。
  private let imagePrefetchProcessor: (any ImageProcessor)?

  /// 处理新项目并将其合并到现有项目数组的函数。
  /// 如果添加了新的、唯一的内容，它应该返回 `true`。
  private let processor: @MainActor (inout [ItemType], [ItemType]) -> Bool

  /// 一个可选的闭包，用于在重置分页器时执行自定义逻辑。
  private var onReset: (() -> Void)?

  /// 从列表末尾开始触发加载更多的项目数。
  private let threshold: Int

  /// 提前触发图片预取的项数。如果未设定，默认为 threshold 的一半（向上取整）。
  private let prefetchThreshold: Int

  /// 已经最高触发过预取的项目索引，用于进行分批预取并防抖、跳过不可见区。
  private var maxPrefetchedIndex: Int = -1

  /// 当前正在执行的图片预取器实例，持有以便在 reset 或新批次时取消旧任务。
  private var activePrefetchers: [ImagePrefetcher] = []
  /// 所有尚未 completion 的批次只保留 URL 状态，用于真正 Pop 后补删晚到写回。
  private let imagePrefetchRegistry = PaginatorImagePrefetchRegistry()

  // MARK: - 初始化

  /// 初始化一个新的分页器实例。
  /// - 参数:
  ///   - threshold: 触发加载更多的阈值。
  ///   - fetcher: 一个异步闭包，接收页码并返回一个 `ItemType` 数组。
  ///   - processor: 一个闭包，接收现有项目（`inout`）和新项目，
  ///                处理它们，并在添加了新内容时返回 `true`。
  ///   - onReset: 一个可选的闭包，用于在“重置”期间运行自定义的状态清除逻辑。
  public init(
    threshold: Int,
    fetcher: @escaping @MainActor (Int) async throws -> [ItemType],
    processor: @escaping @MainActor (inout [ItemType], [ItemType]) -> Bool,
    imageURLsProvider: (@MainActor (ItemType) -> [URL])? = nil,
    imagePrefetchProcessor: (any ImageProcessor)? = nil,
    prefetchThreshold: Int? = nil,
    onReset: (() -> Void)? = nil
  ) {
    self.threshold = threshold
    self.fetcher = fetcher
    self.processor = processor
    self.imageURLsProvider = imageURLsProvider
    self.imagePrefetchProcessor = imagePrefetchProcessor
    self.prefetchThreshold = prefetchThreshold ?? ((threshold + 1) / 2)
    self.onReset = onReset
  }

  // MARK: - 公开接口

  /// 将分页器重置到其初始状态并加载第一页内容。
  /// 适用于初始加载或“下拉刷新”操作。
  public func refresh() async {
    reset()
    await runLoadSequence()
  }

  /// 加载下一页内容。
  /// 适用于“加载更多”按钮或无限滚动功能。
  /// - 参数:
  ///   - currentItemId: 当前显示或聚焦的项目的 ID。如果提供，将根据 threshold 判断是否需要加载。
  public func loadMore(_ currentItemId: ItemType.ID? = nil) async {
    if let currentItemId = currentItemId {
      guard let itemIndex = items.firstIndex(where: { $0.id == currentItemId }) else { return }

      if let provider = imageURLsProvider {
        // 当滚动到达之前的预取边界前一点时（预留 margin），才分批触发下一次请求
        let prefetchMargin = max(1, prefetchThreshold / 2)
        if itemIndex + prefetchMargin >= maxPrefetchedIndex {
          let start = max(itemIndex + 1, maxPrefetchedIndex + 1)
          let end = min(start + prefetchThreshold, items.count)

          if start < end {
            let urlsToPrefetch = items[start..<end].flatMap { provider($0) }
            if !urlsToPrefetch.isEmpty {
              // 批量预取。由于只在跨越边界时触发，极大降低了 ImagePrefetcher() 实例的创建频率
              activePrefetchers.forEach { $0.stop() }
              let service = APIService.shared
              let grouped = Dictionary(grouping: urlsToPrefetch) {
                service.isProtectedImageURL($0)
              }
              activePrefetchers = grouped.compactMap { protected, urls in
                makeImagePrefetcher(
                  urls: urls,
                  protected: protected,
                  service: service
                )
              }
              activePrefetchers.forEach { $0.start() }
            }
            maxPrefetchedIndex = end - 1
          }
        }
      }

      let thresholdIndex = max(0, items.count - threshold)
      guard itemIndex >= thresholdIndex else { return }
    }
    await runLoadSequence()
  }

  /// 取消当前加载和图片预取，并让已恢复的旧请求结果失效。
  public func cancel() {
    generation += 1
    pendingRestartLoadTaskToken = nil
    inFlightLoadTask?.cancel()
    inFlightLoadTask = nil
    isLoading = false
    isFirstLoading = false
    isLoadingMore = false
    activePrefetchers.forEach { $0.stop() }
    activePrefetchers.removeAll()
  }

  /// 真正 Pop 专用：普通取消后，仅给尚未 completion 的 URL 批次登记补删回调。
  public func cancelForPop(
    onLateImagePrefetch: @escaping @MainActor @Sendable (Set<URL>) -> Void
  ) {
    cancel()
    imagePrefetchRegistry.retireAll(cleanup: onLateImagePrefetch)
  }

  /// 将下一次加载的页游标向后推进指定页数。
  /// 适用于外部已通过其它方式消费了最新若干页的场景（如增量轮询）。
  /// 仅调整游标，不触发实际请求。
  /// 注意：调用方若基于本方法改游标并取消/重启加载任务，需自行管理 UI 层的 isLoading 状态。
  public func advancePageCursor(by pages: Int) {
    guard pages > 0 else { return }
    if isLoading {
      requestRestartAfterInFlightCancellation()
    }
    page += pages
  }

  /// 将下一次加载的页游标向前回退指定页数。
  /// 适用于外部删除大量项目后，后续页整体前移的场景。
  /// 同时重置 hasMore，允许继续向后尝试加载。
  /// 注意：调用方若基于本方法改游标并取消/重启加载任务，需自行管理 UI 层的 isLoading 状态。
  public func rewindPageCursor(by pages: Int) {
    guard pages > 0 else { return }
    if isLoading {
      requestRestartAfterInFlightCancellation()
    }
    page = max(1, page - pages)
    hasMore = true
  }

  private func requestRestartAfterInFlightCancellation() {
    guard let runningTask = inFlightLoadTask else { return }
    pendingRestartLoadTaskToken = inFlightLoadTaskToken
    runningTask.cancel()
  }

  private func makeImagePrefetcher(
    urls: [URL],
    protected: Bool,
    service: APIService
  ) -> ImagePrefetcher {
    let sources = urls.map { service.imageSource(for: $0) }
    var options = protected ? service.imageOptions(for: urls[0]) : []
    if let imagePrefetchProcessor {
      options.append(.processor(imagePrefetchProcessor))
    }

    let batch = PaginatorImagePrefetchBatch(urls: Set(urls))
    let batchID = imagePrefetchRegistry.insert(batch)
    let registry = imagePrefetchRegistry
    return ImagePrefetcher(
      sources: sources,
      options: options,
      completionHandler: { [registry, batch] _, _, _ in
        Task { @MainActor [registry, batch] in
          registry.complete(batch, id: batchID)
        }
      }
    )
  }

  private func startLoadTask() -> (task: Task<Void, Never>, token: Int) {
    if let runningTask = inFlightLoadTask {
      return (runningTask, inFlightLoadTaskToken)
    }

    inFlightLoadTaskToken += 1
    let token = inFlightLoadTaskToken
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.loadNextPage()
      if self.inFlightLoadTaskToken == token {
        self.inFlightLoadTask = nil
      }
    }
    inFlightLoadTask = task
    return (task, token)
  }

  private func runLoadSequence() async {
    var restartRounds = 0

    while hasMore {
      let (task, token) = startLoadTask()
      await task.value

      let shouldRestart = consumeRestartAfterCancellationIfNeeded(for: token)
      guard shouldRestart else { break }

      restartRounds += 1
      if restartRounds >= maxRestartRoundsPerSequence {
        Logger.warning(
          "[Paginator] 达到单次加载序列最大重启次数 (\(maxRestartRoundsPerSequence))，停止继续重启"
        )
        break
      }
    }
  }

  // MARK: - 私有核心逻辑

  /// 核心加载逻辑。如果可能，获取并处理下一页。
  private func loadNextPage() async {
    guard hasMore, !isLoading else { return }

    let currentGeneration = generation

    isLoading = true
    if page == 1 {
      isFirstLoading = true
    } else {
      isLoadingMore = true
    }

    // 仅在 generation 未变时清理（generation 变了说明 reset() 已清理）
    defer {
      if currentGeneration == generation {
        isFirstLoading = false
        isLoadingMore = false
        isLoading = false
      }
    }

    // 不是错误重试次数；用于跳过少量只包含已知项目的页面，继续向后寻找新内容。
    let maxPagesToScanForNewContent = 2
    var pagesScannedForNewContent = 0
    var hasNewContent = false
    var currentError: Error? = nil

    while pagesScannedForNewContent < maxPagesToScanForNewContent, hasMore, !hasNewContent {
      pagesScannedForNewContent += 1

      do {
        let newItems = try await fetcher(page)

        // 挂起恢复后检查：generation 变化说明已被 reset，丢弃结果
        guard currentGeneration == generation, !Task.isCancelled else { return }

        consecutiveErrorCount = 0
        clearErrorState()

        if newItems.isEmpty {
          hasMore = false
          break
        }

        if processor(&self.items, newItems) {
          hasNewContent = true
        }

        page += 1
        currentError = nil
      } catch {
        if Task.isCancelled || error is CancellationError {
          return
        }
        guard currentGeneration == generation, !Task.isCancelled else { return }
        Logger.error("Failed to load page \(page): \(error)")
        currentError = error
        consecutiveErrorCount += 1
        break
      }
    }

    if !hasNewContent && currentError == nil {
      hasMore = false
    } else if let error = currentError {
      if !hasError {
        hasError = true
      }
      lastError = error
      if consecutiveErrorCount >= maxConsecutiveErrors {
        Logger.error("连续发生 \(consecutiveErrorCount) 次错误，停止后续加载")
        hasMore = false
        NotificationCenter.default.post(name: .paginatorDidReachErrorLimit, object: nil)
      }
    }
  }

  private func clearErrorState() {
    if hasError {
      hasError = false
    }
    if lastError != nil {
      lastError = nil
    }
  }

  private func consumeRestartAfterCancellationIfNeeded(for completedTaskToken: Int) -> Bool {
    guard pendingRestartLoadTaskToken == completedTaskToken else { return false }
    pendingRestartLoadTaskToken = nil
    return hasMore
  }

  /// 重置分页器的状态，清除所有项目并重置标志。
  private func reset() {
    generation += 1
    pendingRestartLoadTaskToken = nil
    inFlightLoadTask?.cancel()
    inFlightLoadTask = nil
    items = []
    isLoading = false
    isFirstLoading = false
    isLoadingMore = false
    hasMore = true
    clearErrorState()
    page = 1
    consecutiveErrorCount = 0
    maxPrefetchedIndex = -1
    activePrefetchers.forEach { $0.stop() }
    activePrefetchers.removeAll()
    onReset?()
  }
}
