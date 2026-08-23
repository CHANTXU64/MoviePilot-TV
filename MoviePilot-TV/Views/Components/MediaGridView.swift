import SwiftUI

private final class PreloadDebouncer {
  private var tasks: [String: Task<Void, Never>] = [:]

  func schedule(for item: MediaInfo, stackID: UUID, delayMs: Int = 300) {
    let id = item.id
    // 取消该 ID 已有的计时任务
    tasks[id]?.cancel()

    tasks[id] = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled else { return }

      MediaPreloader.shared.preloadFocusedCandidateIfNeeded(for: item, stackID: stackID)
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
// `.equatable()` 通过稳定列表位置和图片配置短路，跳过 MediaCard 子树的 body 求值。
// 注意：不在 grid 层使用 @FocusState，避免每次焦点移动触发整个 grid body 重新求值。
// 焦点处理保留在 per-card 的 onFocus 回调中（由 MediaCard 内部的 @FocusState 驱动）。

private struct GridCardView: View, Equatable {
  let listID: UUID
  let item: MediaInfo
  let itemIndex: Int
  let itemCount: Int
  let imageConfigurationIdentity: String
  let onTap: () -> Void
  let onFocus: (Bool) -> Void

  static func == (lhs: GridCardView, rhs: GridCardView) -> Bool {
    lhs.listID == rhs.listID
      && lhs.item.id == rhs.item.id
      && lhs.itemIndex == rhs.itemIndex
      && lhs.itemCount == rhs.itemCount
      && lhs.imageConfigurationIdentity == rhs.imageConfigurationIdentity
  }

  var body: some View {
    MediaCard(
      title: item.title ?? "",
      posterUrl: item.imageURLs.poster,
      posterFallbackUrl: item.imageURLs.posterFallback,
      typeText: item.displayTypeText,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      loadsImage: true,
      action: onTap,
      onFocus: onFocus
    )
  }
}

private struct GridCardViewWithMenu<MenuContent: View>: View, Equatable {
  let listID: UUID
  let item: MediaInfo
  let itemIndex: Int
  let itemCount: Int
  let imageConfigurationIdentity: String
  let onTap: () -> Void
  let onFocus: (Bool) -> Void
  let menuBuilder: (MediaInfo) -> MenuContent

  static func == (lhs: GridCardViewWithMenu, rhs: GridCardViewWithMenu) -> Bool {
    lhs.listID == rhs.listID
      && lhs.item.id == rhs.item.id
      && lhs.itemIndex == rhs.itemIndex
      && lhs.itemCount == rhs.itemCount
      && lhs.imageConfigurationIdentity == rhs.imageConfigurationIdentity
  }

  var body: some View {
    MediaCard(
      title: item.title ?? "",
      posterUrl: item.imageURLs.poster,
      posterFallbackUrl: item.imageURLs.posterFallback,
      typeText: item.displayTypeText,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      loadsImage: true,
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
  @ObservedObject private var apiService = APIService.shared
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let listID: UUID
  let items: [MediaInfo]
  let isLoading: Bool
  let isLoadingMore: Bool
  let onLoadMore: (MediaInfo.ID?) -> Void
  let header: Header
  let contextMenu: ((MediaInfo) -> ContextMenu)?
  let onShareTapped: ((SubscribeShare) -> Void)?
  let loadMoreThreshold: Int
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator

  /// 预加载防抖器：引用类型，内部状态变化不会触发 View 刷新
  @State private var preloadDebouncer = PreloadDebouncer()
  @StateObject private var domRetention: GridDOMRetentionController
  @StateObject private var imageRetention: GridImageLifecycleController

  init(
    imageLifecycle: PageImageLifecycle,
    listID: UUID,
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    loadMoreThreshold: Int = 24,
    @ViewBuilder header: () -> Header,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.imageLifecycle = imageLifecycle
    self.listID = listID
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self.loadMoreThreshold = loadMoreThreshold
    self.header = header()
    self.contextMenu = contextMenu
    self.onShareTapped = onShareTapped
    _domRetention = StateObject(
      wrappedValue: GridDOMRetentionController(
        listID: listID,
        itemIDs: items.map(\.id),
        columnCount: MediaCard.defaultGridColumns.count
      )
    )
    _imageRetention = StateObject(
      wrappedValue: GridImageLifecycleController(
        listID: listID,
        itemIDs: items.map(\.id),
        columnCount: MediaCard.defaultGridColumns.count,
        imageLifecycle: imageLifecycle
      )
    )
  }

  // 无上下文菜单的初始化方法
  init(
    imageLifecycle: PageImageLifecycle,
    listID: UUID,
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    loadMoreThreshold: Int = 24,
    @ViewBuilder header: () -> Header,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) where ContextMenu == EmptyView {
    self.imageLifecycle = imageLifecycle
    self.listID = listID
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self.loadMoreThreshold = loadMoreThreshold
    self.header = header()
    self.contextMenu = nil
    self.onShareTapped = onShareTapped
    _domRetention = StateObject(
      wrappedValue: GridDOMRetentionController(
        listID: listID,
        itemIDs: items.map(\.id),
        columnCount: MediaCard.defaultGridColumns.count
      )
    )
    _imageRetention = StateObject(
      wrappedValue: GridImageLifecycleController(
        listID: listID,
        itemIDs: items.map(\.id),
        columnCount: MediaCard.defaultGridColumns.count,
        imageLifecycle: imageLifecycle
      )
    )
  }

  var body: some View {
    let currentItemIDs = items.map(\.id)
    let retainedItemCount = domRetention.retainedItemCount(for: items.count, listID: listID)

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
            ForEach(Array(items.prefix(retainedItemCount).enumerated()), id: \.element.id) {
              entry in
              let index = entry.offset
              let item = entry.element
              if let contextMenu = contextMenu {
                GridCardViewWithMenu(
                  listID: listID,
                  item: item,
                  itemIndex: index,
                  itemCount: items.count,
                  imageConfigurationIdentity: apiService.imageConfigurationIdentity,
                  onTap: { handleItemTap(item) },
                  onFocus: { isFocused in
                    handleFocus(
                      listID: listID,
                      item: item,
                      index: index,
                      itemCount: items.count,
                      isFocused: isFocused
                    )
                  },
                  menuBuilder: contextMenu
                )
                .equatable()
                .environment(
                  \.gridImageDemandContext,
                  GridImageDemandContext(
                    controller: imageRetention,
                    listID: listID,
                    itemID: item.id,
                    itemIndex: index
                  )
                )
              } else {
                GridCardView(
                  listID: listID,
                  item: item,
                  itemIndex: index,
                  itemCount: items.count,
                  imageConfigurationIdentity: apiService.imageConfigurationIdentity,
                  onTap: { handleItemTap(item) },
                  onFocus: { isFocused in
                    handleFocus(
                      listID: listID,
                      item: item,
                      index: index,
                      itemCount: items.count,
                      isFocused: isFocused
                    )
                  }
                )
                .equatable()
                .environment(
                  \.gridImageDemandContext,
                  GridImageDemandContext(
                    controller: imageRetention,
                    listID: listID,
                    itemID: item.id,
                    itemIndex: index
                  )
                )
              }
            }
          }
          .id(listID)
          .padding(.horizontal, -12)
          .padding(.bottom, 20)

          // 加载更多指示器
          if isLoadingMore && retainedItemCount == items.count {
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
    .onScrollGeometryChange(
      for: CGFloat.self,
      of: { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      },
      action: { _, adjustedOffsetY in
        domRetention.scrollPositionChanged(adjustedOffsetY: adjustedOffsetY)
      }
    )
    .onScrollPhaseChange { _, newPhase in
      domRetention.scrollPhaseChanged(newPhase)
    }
    .onAppear {
      domRetention.reconcile(listID: listID, itemIDs: items.map(\.id))
      imageRetention.reconcile(listID: listID, itemIDs: items.map(\.id))
      domRetention.setViewActive(true)
      domRetention.setStackInteractive(navigationCoordinator.isStackInteractive)
    }
    .onChange(of: currentItemIDs) { _, newItemIDs in
      domRetention.reconcile(listID: listID, itemIDs: newItemIDs)
      imageRetention.reconcile(listID: listID, itemIDs: newItemIDs)
    }
    .onChange(of: listID) { _, newListID in
      let itemIDs = items.map(\.id)
      domRetention.reconcile(listID: newListID, itemIDs: itemIDs)
      imageRetention.reconcile(listID: newListID, itemIDs: itemIDs)
    }
    .onChange(of: navigationCoordinator.isStackInteractive) { _, isInteractive in
      domRetention.setStackInteractive(isInteractive)
    }
    .onDisappear {
      preloadDebouncer.cancel()
      domRetention.setViewActive(false)
    }
  }

  /// 集中处理卡片点击逻辑
  private func handleItemTap(_ item: MediaInfo) {
    if let share = item.subscribeShare {
      onShareTapped?(share)
    } else {
      preloadDebouncer.cancel(id: item.id)
      navigationCoordinator.push(item)
    }
  }

  /// 集中处理焦点变化逻辑（由 per-card @FocusState 驱动，不触发 grid body 重新求值）
  private func handleFocus(
    listID eventListID: UUID,
    item: MediaInfo,
    index: Int,
    itemCount: Int,
    isFocused: Bool
  ) {
    // 图片控制器同时验证页面是否可见/可交互；先过这道门，避免隐藏页面的迟到焦点扩张 DOM。
    guard imageRetention.cardFocusChanged(
      listID: eventListID,
      itemID: item.id,
      itemIndex: index,
      isFocused: isFocused
    ) else {
      return
    }
    guard domRetention.cardFocusChanged(
      listID: eventListID,
      itemID: item.id,
      itemIndex: index,
      isFocused: isFocused
    ) else {
      return
    }

    guard isFocused else {
      preloadDebouncer.cancel(id: item.id)
      return
    }

    MediaPreloader.shared.focusDidMove(to: item.id, stackID: navigationCoordinator.id)
    preloadDebouncer.cancel(id: item.id)
    if item.shouldPreloadDetail {
      preloadDebouncer.schedule(for: item, stackID: navigationCoordinator.id)
    }

    if index >= itemCount - loadMoreThreshold {
      onLoadMore(item.id)
    }
  }
}

extension MediaGridView where Header == EmptyView {
  init(
    imageLifecycle: PageImageLifecycle,
    listID: UUID,
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    loadMoreThreshold: Int = 24,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.init(
      imageLifecycle: imageLifecycle,
      listID: listID,
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      loadMoreThreshold: loadMoreThreshold,
      header: { EmptyView() },
      contextMenu: contextMenu,
      onShareTapped: onShareTapped
    )
  }
}

extension MediaGridView where Header == EmptyView, ContextMenu == EmptyView {
  init(
    imageLifecycle: PageImageLifecycle,
    listID: UUID,
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    loadMoreThreshold: Int = 24,
    onShareTapped: ((SubscribeShare) -> Void)? = nil
  ) {
    self.init(
      imageLifecycle: imageLifecycle,
      listID: listID,
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      loadMoreThreshold: loadMoreThreshold,
      header: { EmptyView() },
      onShareTapped: onShareTapped
    )
  }
}
