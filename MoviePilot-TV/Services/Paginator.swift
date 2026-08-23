import Combine
import Foundation

@MainActor
public class Paginator<ItemType: Identifiable>: ObservableObject {
  /// Paginator 实例的稳定列表代际；refresh/尾部追加不变，新子 Tab 会创建新实例和新 ID。
  public let listID: UUID

  deinit {
    // 保留显式 deinit，维持既有 SIL 生成路径；同时清理未完成的数据加载任务。
    inFlightLoadTask?.cancel()
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

  /// 提前触发服务端缓存的图片 URL 函数；不会在 Apple TV 下载或解码图片。
  private let imageWarmURLsProvider: (@MainActor (ItemType) -> [URL])?

  /// 处理新项目并将其合并到现有项目数组的函数。
  /// 如果添加了新的、唯一的内容，它应该返回 `true`。
  private let processor: @MainActor (inout [ItemType], [ItemType]) -> Bool

  /// 一个可选的闭包，用于在重置分页器时执行自定义逻辑。
  private var onReset: (() -> Void)?

  /// 从列表末尾开始触发加载更多的项目数。
  private let threshold: Int

  /// 提前触发服务端图片缓存的项数。如果未设定，默认为 threshold 的一半（向上取整）。
  private let imageWarmThreshold: Int

  /// 已经最高触发过 Warm 的项目索引，用于分批防抖并跳过不可见区。
  private var maxWarmedIndex: Int = -1

  // MARK: - 初始化

  /// 初始化一个新的分页器实例。
  /// - 参数:
  ///   - threshold: 触发加载更多的阈值。
  ///   - fetcher: 一个异步闭包，接收页码并返回一个 `ItemType` 数组。
  ///   - processor: 一个闭包，接收现有项目（`inout`）和新项目，
  ///                处理它们，并在添加了新内容时返回 `true`。
  ///   - onReset: 一个可选的闭包，用于在“重置”期间运行自定义的状态清除逻辑。
  public init(
    listID: UUID = UUID(),
    threshold: Int,
    fetcher: @escaping @MainActor (Int) async throws -> [ItemType],
    processor: @escaping @MainActor (inout [ItemType], [ItemType]) -> Bool,
    imageWarmURLsProvider: (@MainActor (ItemType) -> [URL])? = nil,
    imageWarmThreshold: Int? = nil,
    onReset: (() -> Void)? = nil
  ) {
    self.listID = listID
    self.threshold = threshold
    self.fetcher = fetcher
    self.processor = processor
    self.imageWarmURLsProvider = imageWarmURLsProvider
    self.imageWarmThreshold = imageWarmThreshold ?? ((threshold + 1) / 2)
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

      if let provider = imageWarmURLsProvider {
        // 当滚动到达之前的 Warm 边界前一点时（预留 margin），才分批触发下一次请求。
        let warmMargin = max(1, imageWarmThreshold / 2)
        if itemIndex + warmMargin >= maxWarmedIndex {
          let start = max(itemIndex + 1, maxWarmedIndex + 1)
          let end = min(start + imageWarmThreshold, items.count)

          if start < end {
            let urlsToWarm = items[start..<end].flatMap { provider($0) }
            if !urlsToWarm.isEmpty {
              _ = await MPImageWarmer.shared.warm(urlsToWarm)
            }
            maxWarmedIndex = end - 1
          }
        }
      }

      let thresholdIndex = max(0, items.count - threshold)
      guard itemIndex >= thresholdIndex else { return }
    }
    await runLoadSequence()
  }

  /// 取消当前数据加载，并让已恢复的旧请求结果失效。
  public func cancel() {
    generation += 1
    pendingRestartLoadTaskToken = nil
    inFlightLoadTask?.cancel()
    inFlightLoadTask = nil
    isLoading = false
    isFirstLoading = false
    isLoadingMore = false
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
    maxWarmedIndex = -1
    onReset?()
  }
}
