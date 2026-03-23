import Combine
import Foundation
import Kingfisher

@MainActor
public class Paginator<ItemType: Identifiable>: ObservableObject {
  deinit {
    // 显式声明 deinit，改变 SIL 生成路径以避开优化器 Bug
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

  // MARK: - 私有状态

  private var page: Int = 1
  private var consecutiveErrorCount: Int = 0
  private let maxConsecutiveErrors: Int = 3
  private var generation: Int = 0
  private var inFlightLoadTask: Task<Void, Never>?
  private var inFlightLoadTaskToken: Int = 0
  private var shouldRestartAfterCancellation: Bool = false
  private let maxRestartRoundsPerSequence: Int = 5

  /// 获取一页项目的函数。
  private let fetcher: @MainActor (Int) async throws -> [ItemType]

  /// 预取图片 URL 的函数。
  private let imageURLsProvider: (@MainActor (ItemType) -> [URL])?

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
  private var activePrefetcher: ImagePrefetcher?

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
    prefetchThreshold: Int? = nil,
    onReset: (() -> Void)? = nil
  ) {
    self.threshold = threshold
    self.fetcher = fetcher
    self.processor = processor
    self.imageURLsProvider = imageURLsProvider
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
              activePrefetcher?.stop()
              let prefetcher = ImagePrefetcher(urls: urlsToPrefetch)
              activePrefetcher = prefetcher
              prefetcher.start()
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

  /// 将下一次加载的页游标向后推进指定页数。
  /// 适用于外部已通过其它方式消费了最新若干页的场景（如增量轮询）。
  /// 仅调整游标，不触发实际请求。
  /// 注意：调用方若基于本方法改游标并取消/重启加载任务，需自行管理 UI 层的 isLoading 状态。
  public func advancePageCursor(by pages: Int) {
    guard pages > 0 else { return }
    if isLoading {
      shouldRestartAfterCancellation = true
      inFlightLoadTask?.cancel()
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
      shouldRestartAfterCancellation = true
      inFlightLoadTask?.cancel()
    }
    page = max(1, page - pages)
    hasMore = true
  }

  private func startLoadTask() -> Task<Void, Never> {
    if let runningTask = inFlightLoadTask {
      if runningTask.isCancelled {
        inFlightLoadTask = nil
      } else {
        return runningTask
      }
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
    return task
  }

  private func runLoadSequence() async {
    var restartRounds = 0

    while hasMore {
      let task = startLoadTask()
      await task.value

      let shouldRestart = consumeRestartAfterCancellationIfNeeded()
      guard shouldRestart else { break }

      restartRounds += 1
      if restartRounds >= maxRestartRoundsPerSequence {
        print(
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

    let maxAttempts = 2
    var attempts = 0
    var hasNewContent = false
    var hasError = false

    while attempts < maxAttempts, hasMore, !hasNewContent {
      attempts += 1

      do {
        let newItems = try await fetcher(page)

        // 挂起恢复后检查：generation 变化说明已被 reset，丢弃结果
        guard currentGeneration == generation, !Task.isCancelled else { return }

        if newItems.isEmpty {
          hasMore = false
          break
        }

        if processor(&self.items, newItems) {
          hasNewContent = true
        }

        page += 1
        consecutiveErrorCount = 0  // 重置错误计数
      } catch {
        if Task.isCancelled || error is CancellationError {
          return
        }
        guard currentGeneration == generation, !Task.isCancelled else { return }
        print("[Paginator] Failed to load page \(page): \(error)")
        hasError = true
        consecutiveErrorCount += 1
        break
      }
    }

    if !hasNewContent && !hasError {
      hasMore = false
    } else if hasError && consecutiveErrorCount >= maxConsecutiveErrors {
      print("[Paginator] 连续发生 \(consecutiveErrorCount) 次错误，停止后续加载")
      hasMore = false
    }

  }

  private func consumeRestartAfterCancellationIfNeeded() -> Bool {
    defer { shouldRestartAfterCancellation = false }
    return shouldRestartAfterCancellation && hasMore
  }

  /// 重置分页器的状态，清除所有项目并重置标志。
  private func reset() {
    generation += 1
    shouldRestartAfterCancellation = false
    inFlightLoadTask?.cancel()
    inFlightLoadTask = nil
    items = []
    isLoading = false
    isFirstLoading = false
    isLoadingMore = false
    hasMore = true
    page = 1
    consecutiveErrorCount = 0
    maxPrefetchedIndex = -1
    activePrefetcher?.stop()
    activePrefetcher = nil
    onReset?()
  }
}
