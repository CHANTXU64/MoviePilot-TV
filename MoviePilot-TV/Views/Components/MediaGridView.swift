import SwiftUI

private final class PreloadDebouncer {
  private var tasks: [String: Task<Void, Never>] = [:]

  func schedule(for item: MediaInfo, delayMs: Int = 300) {
    let id = item.id
    // 取消该 ID 已有的计时任务
    tasks[id]?.cancel()

    tasks[id] = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled else { return }

      MediaPreloader.shared.preload(for: item)
      // 执行完后清理
      tasks.removeValue(forKey: id)
    }
  }

  func cancel(id: String? = nil) {
    if let id = id {
      tasks[id]?.cancel()
      tasks.removeValue(forKey: id)
    } else {
      // 取消所有（用于 onDisappear 或全局重置）
      tasks.values.forEach { $0.cancel() }
      tasks.removeAll()
    }
  }
}

// MARK: - EquatableView 包装器
// 当父视图 body 重新求值（如 Paginator 状态变化）时，
// `.equatable()` 通过 `==`（仅比较 item.id）短路，跳过 MediaCard 子树的 body 求值。
// 注意：不在 grid 层使用 @FocusState，避免每次焦点移动触发整个 grid body 重新求值。
// 焦点处理保留在 per-card 的 onFocus 回调中（由 MediaCard 内部的 @FocusState 驱动）。

private struct GridCardView: View, Equatable {
  let item: MediaInfo
  let onTap: () -> Void
  let onFocus: (Bool) -> Void

  static func == (lhs: GridCardView, rhs: GridCardView) -> Bool {
    lhs.item.id == rhs.item.id
  }

  var body: some View {
    MediaCard(
      title: item.title ?? "",
      posterUrl: item.imageURLs.poster,
      typeText: item.collection_id != nil ? "合集" : item.type,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      action: onTap,
      onFocus: onFocus
    )
  }
}

private struct GridCardViewWithMenu<MenuContent: View>: View, Equatable {
  let item: MediaInfo
  let onTap: () -> Void
  let onFocus: (Bool) -> Void
  let menuBuilder: (MediaInfo) -> MenuContent

  static func == (lhs: GridCardViewWithMenu, rhs: GridCardViewWithMenu) -> Bool {
    lhs.item.id == rhs.item.id
  }

  var body: some View {
    MediaCard(
      title: item.title ?? "",
      posterUrl: item.imageURLs.poster,
      typeText: item.collection_id != nil ? "合集" : item.type,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      action: onTap,
      onFocus: onFocus
    )
    .contextMenu {
      menuBuilder(item)
    }
  }
}

// MARK: - MediaGridView

/// 通用媒体网格视图组件
/// 用于展示媒体海报卡片的网格布局，支持分页加载
struct MediaGridView<Header: View, ContextMenu: View>: View {
  let items: [MediaInfo]
  let isLoading: Bool
  let isLoadingMore: Bool
  let onLoadMore: (MediaInfo.ID?) -> Void
  @Binding var navigationPath: NavigationPath
  let header: Header
  let contextMenu: ((MediaInfo) -> ContextMenu)?
  let onShareTapped: ((SubscribeShare) -> Void)?
  let loadMoreThreshold: Int

  /// 预加载防抖器：引用类型，内部状态变化不会触发 View 刷新
  @State private var preloadDebouncer = PreloadDebouncer()

  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    loadMoreThreshold: Int = 24,
    @ViewBuilder header: () -> Header,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self._navigationPath = navigationPath
    self.loadMoreThreshold = loadMoreThreshold
    self.header = header()
    self.contextMenu = contextMenu
    self.onShareTapped = onShareTapped
  }

  // 无上下文菜单的初始化方法
  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    loadMoreThreshold: Int = 24,
    @ViewBuilder header: () -> Header,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) where ContextMenu == EmptyView {
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self._navigationPath = navigationPath
    self.loadMoreThreshold = loadMoreThreshold
    self.header = header()
    self.contextMenu = nil
    self.onShareTapped = onShareTapped
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        header

        if isLoading {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else if items.isEmpty {
          HStack {
            Spacer()
            Text("暂无数据")
              .foregroundColor(.secondary)
              .padding()
              .focusable()
            Spacer()
          }
        } else {

          LazyVGrid(columns: MediaCard.defaultGridColumns, spacing: 40) {
            ForEach(items) { item in
              if let contextMenu = contextMenu {
                GridCardViewWithMenu(
                  item: item,
                  onTap: { handleItemTap(item) },
                  onFocus: { isFocused in handleFocus(item: item, isFocused: isFocused) },
                  menuBuilder: contextMenu
                )
                .equatable()
              } else {
                GridCardView(
                  item: item,
                  onTap: { handleItemTap(item) },
                  onFocus: { isFocused in handleFocus(item: item, isFocused: isFocused) }
                )
                .equatable()
              }
            }
          }
          .padding(.horizontal, -12)
          .padding(.bottom, 20)

          // 加载更多指示器
          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
                .padding()
              Spacer()
            }
          }
        }
      }
    }
    .focusSection()
    .onDisappear {
      preloadDebouncer.cancel()
    }
  }

  /// 集中处理卡片点击逻辑
  private func handleItemTap(_ item: MediaInfo) {
    if let share = item.subscribeShare {
      onShareTapped?(share)
    } else {
      preloadDebouncer.cancel(id: item.id)
      MediaPreloader.shared.preload(for: item)
      navigationPath.append(item)
    }
  }

  /// 集中处理焦点变化逻辑（由 per-card @FocusState 驱动，不触发 grid body 重新求值）
  private func handleFocus(item: MediaInfo, isFocused: Bool) {
    guard isFocused else {
      preloadDebouncer.cancel(id: item.id)
      return
    }

    preloadDebouncer.cancel(id: item.id)
    if item.collection_id == nil {
      preloadDebouncer.schedule(for: item)
    }

    // 用 index 判断是否接近末尾，避免创建 Set
    if let index = items.firstIndex(where: { $0.id == item.id }),
      index >= items.count - loadMoreThreshold
    {
      onLoadMore(item.id)
    }
  }
}

extension MediaGridView where Header == EmptyView {
  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    loadMoreThreshold: Int = 24,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.init(
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      navigationPath: navigationPath,
      loadMoreThreshold: loadMoreThreshold,
      header: { EmptyView() },
      contextMenu: contextMenu,
      onShareTapped: onShareTapped
    )
  }
}

extension MediaGridView where Header == EmptyView, ContextMenu == EmptyView {
  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    loadMoreThreshold: Int = 24,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.init(
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      navigationPath: navigationPath,
      loadMoreThreshold: loadMoreThreshold,
      header: { EmptyView() },
      onShareTapped: onShareTapped
    )
  }
}
