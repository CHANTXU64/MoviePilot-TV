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
    let loadMoreCandidateIds = Set(items.suffix(loadMoreThreshold).map(\.id))

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
              let card = MediaCard(
                title: item.title ?? "",
                posterUrl: APIService.shared.getPosterImageUrl(item),
                typeText: item.collection_id != nil ? "合集" : item.type,
                ratingText: item.vote_average.map { String(format: "%.1f", $0) },
                bottomLeftText: nil,
                bottomLeftSecondaryText: nil,
                source: MediaSource.from(mediaInfo: item),
                action: {
                  if let share = item.subscribeShare {
                    onShareTapped?(share)
                  } else {
                    // 点击时立即触发预加载（取消延迟）
                    preloadDebouncer.cancel(id: item.id)
                    MediaPreloader.shared.preload(for: item)
                    navigationPath.append(item)
                  }
                },
                onFocus: { isFocused in
                  guard isFocused else {
                    preloadDebouncer.cancel(id: item.id)
                    return
                  }

                  // 预加载触发：聚焦后延迟 ~300ms，防止快速滚动时浪费请求
                  // 这里的 cancel 也要传入 ID，否则会把别人刚开启的给取消了
                  preloadDebouncer.cancel(id: item.id)
                  if item.collection_id == nil {
                    preloadDebouncer.schedule(for: item)
                  }

                  if loadMoreCandidateIds.contains(item.id) {
                    onLoadMore(item.id)
                  }
                }
              )

              if let contextMenu = contextMenu {
                card
                  .contextMenu {
                    contextMenu(item)
                  }
              } else {
                card
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
