import Combine
import Foundation

/// 下一次请求的位置：页码，以及此前各批实际返回的条数之和（去重前）。
///
/// 偏移分页（`start` / `count`）的接口用 `offset`：某一批返回不足请求条数时，
/// 按「页码 × 每页条数」推算会跳过条目，按实际返回条数推进才不会漏。
struct PageCursor: Equatable {
  let page: Int
  let offset: Int
}

/// 一页分页结果：条目，以及后端声明的总条数（可选）。
struct PaginatedBatch<Item> {
  let items: [Item]
  let total: Int?

  init(items: [Item], total: Int? = nil) {
    self.items = items
    self.total = total
  }
}

@MainActor
public class Paginator<ItemType: Identifiable>: ObservableObject {
  /// Paginator 实例保持稳定 UUID；reset/refresh 推进内容代际，普通尾部追加保持不变。
  @Published private(set) var listIdentity: GridListIdentity
  public var listID: UUID { listIdentity.id }

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

  /// 后端最近一次声明、且不少于累计已返回条数的总条数；接口不提供或尚未加载时为 nil，刷新时清空。
  @Published private(set) var total: Int?

  // MARK: - 私有状态

  private var page: Int = 1
  /// 此前各批实际返回的条数之和（去重前）；与 `total` 一起判断是否到底。
  private var sourceOffset: Int = 0
  /// 有 total 时连续只拿到已知条目的批次数，跨多次加载累计；取到新内容或刷新时清零。
  private var duplicateBatchesInARow: Int = 0
  private let maxDuplicateBatchesTowardTotal: Int = 3
  private var consecutiveErrorCount: Int = 0
  private let maxConsecutiveErrors: Int = 3
  private var generation: Int = 0
  private var inFlightLoadTask: Task<Void, Never>?
  private var inFlightLoadTaskToken: Int = 0
  private var pendingRestartLoadTaskToken: Int?
  private let maxRestartRoundsPerSequence: Int = 5

  /// 获取一页项目的函数。
  private let fetcher: @MainActor (PageCursor) async throws -> PaginatedBatch<ItemType>

  /// 提前触发服务端缓存的图片 URL 函数；不会在 Apple TV 下载或解码图片。
  private let imageWarmURLsProvider: (@MainActor (ItemType) -> [URL])?

  /// 所属会话的图片预热器；未注入时不做预热。
  private let imageWarmer: MPImageWarmer?

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
  /// 参数含内部类型，本 App 单模块使用，初始化器保持内部访问级别。
  convenience init(
    listID: UUID = UUID(),
    threshold: Int,
    fetcher: @escaping @MainActor (Int) async throws -> [ItemType],
    processor: @escaping @MainActor (inout [ItemType], [ItemType]) -> Bool,
    imageWarmer: MPImageWarmer? = nil,
    imageWarmURLsProvider: (@MainActor (ItemType) -> [URL])? = nil,
    imageWarmThreshold: Int? = nil,
    preparedFirstPage: [ItemType]? = nil,
    onReset: (() -> Void)? = nil
  ) {
    self.init(
      listID: listID,
      threshold: threshold,
      cursorFetcher: { cursor in PaginatedBatch(items: try await fetcher(cursor.page)) },
      processor: processor,
      imageWarmer: imageWarmer,
      imageWarmURLsProvider: imageWarmURLsProvider,
      imageWarmThreshold: imageWarmThreshold,
      preparedFirstPage: preparedFirstPage,
      onReset: onReset
    )
  }

  /// 偏移分页或接口返回总条数时使用：`fetcher` 拿到页码与偏移，偏移按此前各批实际返回的
  /// 条数推进。批次带 `total` 时，累计返回条数达到 total 即到底，不再多发一次空请求；
  /// `total` 缺失时仍按空批次判终。
  /// 注意：`advancePageCursor` / `rewindPageCursor` 只调整页码，不调整偏移，偏移分页不要使用。
  init(
    listID: UUID = UUID(),
    threshold: Int,
    cursorFetcher: @escaping @MainActor (PageCursor) async throws -> PaginatedBatch<ItemType>,
    processor: @escaping @MainActor (inout [ItemType], [ItemType]) -> Bool,
    imageWarmer: MPImageWarmer? = nil,
    imageWarmURLsProvider: (@MainActor (ItemType) -> [URL])? = nil,
    imageWarmThreshold: Int? = nil,
    preparedFirstPage: [ItemType]? = nil,
    onReset: (() -> Void)? = nil
  ) {
    self.listIdentity = GridListIdentity.make(id: listID)
    self.threshold = threshold
    self.fetcher = cursorFetcher
    self.processor = processor
    self.imageWarmURLsProvider = imageWarmURLsProvider
    self.imageWarmer = imageWarmer
    self.imageWarmThreshold = imageWarmThreshold ?? ((threshold + 1) / 2)
    self.onReset = onReset
    if let preparedFirstPage {
      _ = processor(&items, preparedFirstPage)
      page = 2
      sourceOffset = preparedFirstPage.count
      hasMore = !preparedFirstPage.isEmpty
    }
  }

  // MARK: - 公开接口

  /// 将分页器重置到其初始状态并加载第一页内容。
  /// 适用于初始加载或“下拉刷新”操作。
  public func refresh() async {
    beginRefresh()
    await runLoadSequence()
  }

  /// 同步重置并进入首屏加载中，再在后台加载第一页；返回的任务结束即本轮加载结束。
  ///
  /// 调用返回时 `isFirstLoading` 已经是 true，界面不会在「已发起、任务还没跑起来」的间隙
  /// 看到既不在加载、也没有结果的状态。任务开始前被 `cancel()` 或再次刷新取代时不再加载。
  @discardableResult
  func startRefresh() -> Task<Void, Never> {
    beginRefresh()
    let startGeneration = generation
    return Task { @MainActor [weak self] in
      guard let self, self.generation == startGeneration else { return }
      await self.runLoadSequence()
    }
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
              _ = await imageWarmer?.warm(urlsToWarm)
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

  /// 加载更多失败后由用户手动重试：清零连续失败计数，重新允许向后加载。
  ///
  /// 连续失败达到上限后 `hasMore` 会变成 false，移动焦点不再触发请求；网络恢复后需要这个入口。
  /// 只在当前处于错误状态时生效，成功到底时不会多发请求。
  public func retryAfterError() async {
    guard hasError, !isLoading else { return }
    consecutiveErrorCount = 0
    hasMore = true
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
    // 没有 total 时本轮连续两批都是已知项目就当作到底（无法判断后面还有没有）；
    // 有 total 时偏移每批都在前进，继续向后找，直到取到新内容、累计达到 total，
    // 或连续 `maxDuplicateBatchesTowardTotal` 批都是已知项目（上游异常地重复返回）才判到底，
    // 请求总量有界。
    let maxPagesToScanForNewContent = 2
    var pagesScannedForNewContent = 0
    var hasNewContent = false
    var currentError: Error? = nil

    while (total == nil
      ? pagesScannedForNewContent < maxPagesToScanForNewContent
      : duplicateBatchesInARow < maxDuplicateBatchesTowardTotal),
      hasMore, !hasNewContent
    {
      pagesScannedForNewContent += 1

      do {
        let batch = try await fetcher(PageCursor(page: page, offset: sourceOffset))
        let newItems = batch.items

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
          duplicateBatchesInARow = 0
        } else {
          duplicateBatchesInARow += 1
        }

        page += 1
        // 按实际返回条数推进偏移；去重丢掉的条目在服务端仍占位，照样计入。
        sourceOffset += newItems.count
        currentError = nil

        // 声明的总数比累计已返回的条数还少，说明这一批的 total 不可信（例如后端缺 total 时
        // 回填成本批条数），不能据此提前判到底，沿用此前的 total；真到底时由空批次判终。
        if let batchTotal = batch.total, batchTotal >= sourceOffset, total != batchTotal {
          total = batchTotal
        }

        // 累计返回条数达到后端声明的总数：到底了，不再多发一次空请求。
        if let total, sourceOffset >= total {
          hasMore = false
        }
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
      // 有 total 时累计条数与空批次已在循环内判终；这里只剩连续重复达到上限一种情况。
      if total == nil {
        hasMore = false
      } else if duplicateBatchesInARow >= maxDuplicateBatchesTowardTotal {
        Logger.warning(
          "[Paginator] 连续 \(duplicateBatchesInARow) 批都是已加载的条目，累计 \(sourceOffset) 条未达 total，按到底处理"
        )
        hasMore = false
      }
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

  private func beginRefresh() {
    reset()
    isFirstLoading = true
  }

  /// 重置分页器的状态，清除所有项目并重置标志。
  private func reset() {
    generation += 1
    listIdentity = listIdentity.advanced()
    pendingRestartLoadTaskToken = nil
    inFlightLoadTask?.cancel()
    inFlightLoadTask = nil
    items = []
    isLoading = false
    isFirstLoading = false
    isLoadingMore = false
    hasMore = true
    if total != nil {
      total = nil
    }
    clearErrorState()
    page = 1
    sourceOffset = 0
    duplicateBatchesInARow = 0
    consecutiveErrorCount = 0
    maxWarmedIndex = -1
    onReset?()
  }
}
