import Foundation
import Combine

@MainActor
public class Paginator<ItemType: Identifiable>: ObservableObject {
  // MARK: - 公开状态

  /// 分页器加载的项目数组。可被 UI 观察。
  @Published public private(set) var items: [ItemType] = []

  /// 一个布尔值，指示加载操作是否正在进行中。
  @Published public private(set) var isLoading: Bool = false

  /// 一个布尔值，指示是否还有更多内容要加载。
  @Published public private(set) var hasMore: Bool = true

  // MARK: - 私有状态

  private var page: Int = 1

  /// 获取一页项目的函数。
  private let fetcher: (Int) async throws -> [ItemType]

  /// 处理新项目并将其合并到现有项目数组的函数。
  /// 如果添加了新的、唯一的内容，它应该返回 `true`。
  private let processor: (inout [ItemType], [ItemType]) -> Bool

  /// 一个可选的闭包，用于在重置分页器时执行自定义逻辑。
  private var onReset: (() -> Void)?

  /// 从列表末尾开始触发加载更多的项目数。
  private let threshold: Int

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
    fetcher: @escaping (Int) async throws -> [ItemType],
    processor: @escaping (inout [ItemType], [ItemType]) -> Bool,
    onReset: (() -> Void)? = nil
  ) {
    self.threshold = threshold
    self.fetcher = fetcher
    self.processor = processor
    self.onReset = onReset
  }

  // MARK: - 公开接口

  /// 将分页器重置到其初始状态并加载第一页内容。
  /// 适用于初始加载或“下拉刷新”操作。
  public func refresh() async {
    reset()
    await loadNextPage()
  }

  /// 加载下一页内容。
  /// 适用于“加载更多”按钮或无限滚动功能。
  /// - 参数:
  ///   - currentItemId: 当前显示或聚焦的项目的 ID。如果提供，将根据 threshold 判断是否需要加载。
  public func loadMore(_ currentItemId: ItemType.ID? = nil) async {
    if let currentItemId = currentItemId {
      guard let itemIndex = items.firstIndex(where: { $0.id == currentItemId }) else { return }
      let thresholdIndex = max(0, items.count - threshold)
      guard itemIndex >= thresholdIndex else { return }
    }
    await loadNextPage()
  }

  // MARK: - 私有核心逻辑

  /// 核心加载逻辑。如果可能，获取并处理下一页。
  private func loadNextPage() async {
    guard hasMore, !isLoading else { return }

    isLoading = true

    let maxAttempts = 2
    var attempts = 0
    var hasNewContent = false

    while attempts < maxAttempts, hasMore, !hasNewContent {
      attempts += 1

      do {
        let newItems = try await fetcher(page)

        if newItems.isEmpty {
          hasMore = false
          break
        }

        if processor(&self.items, newItems) {
          hasNewContent = true
        }

        page += 1
      } catch {
        print("[Paginator] Failed to load page \(page): \(error)")
        hasMore = false
        break
      }
    }

    if !hasNewContent {
      hasMore = false
    }

    isLoading = false
  }

  /// 重置分页器的状态，清除所有项目并重置标志。
  private func reset() {
    items = []
    isLoading = false
    hasMore = true
    page = 1
    onReset?()
  }
}
