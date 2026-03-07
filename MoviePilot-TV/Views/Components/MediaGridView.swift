import SwiftUI

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
  let autoFocusFirstItem: Bool

  @FocusState private var focusedItemId: MediaInfo.ID?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool
  /// 预加载防抖任务：避免快速滚动时触发过多无效请求
  @State private var preloadDebounceTask: Task<Void, Never>?

  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    autoFocusFirstItem: Bool = false,
    @ViewBuilder header: () -> Header,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu
  ) {
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self._navigationPath = navigationPath
    self.autoFocusFirstItem = autoFocusFirstItem
    self.header = header()
    self.contextMenu = contextMenu
  }

  // 无上下文菜单的初始化方法
  init(
    items: [MediaInfo],
    isLoading: Bool,
    isLoadingMore: Bool,
    onLoadMore: @escaping (MediaInfo.ID?) -> Void,
    navigationPath: Binding<NavigationPath>,
    autoFocusFirstItem: Bool = false,
    @ViewBuilder header: () -> Header
  ) where ContextMenu == EmptyView {
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.onLoadMore = onLoadMore
    self._navigationPath = navigationPath
    self.autoFocusFirstItem = autoFocusFirstItem
    self.header = header()
    self.contextMenu = nil
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
          // 顶部焦点重定向器：捕获从页眉向下导航时的焦点
          Color.clear
            .frame(height: 1)
            .focusable(focusedItemId == nil)
            .focused($isTopRedirectorFocused)
            .onChange(of: isTopRedirectorFocused) { _, isFocused in
              if isFocused {
                // 将焦点重定向到第一个项目
                focusedItemId = items.first?.id
                isTopRedirectorFocused = false
              }
            }

          LazyVGrid(columns: MediaCard.defaultGridColumns, spacing: 40) {
            ForEach(items) { item in
              let card = MediaCard(
                title: item.title ?? "",
                posterUrl: APIService.shared.getPosterImageUrl(item),
                subtitle: item.year,
                typeText: item.collection_id != nil ? "合集" : item.type,
                ratingText: item.vote_average.map { String(format: "%.1f", $0) },
                bottomLeftText: nil,
                bottomLeftSecondaryText: nil,
                source: MediaSource.from(mediaInfo: item),
                action: {
                  // 点击时立即触发预加载（取消延迟）
                  preloadDebounceTask?.cancel()
                  MediaPreloader.shared.preload(for: item)
                  navigationPath.append(item)
                }
              )
              .focused($focusedItemId, equals: item.id)

              if let contextMenu = contextMenu {
                card
                  .compositingGroup()
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
          .onChange(of: focusedItemId) { _, newId in
            // 预加载触发：聚焦后延迟 ~300ms，防止快速滚动时浪费请求
            preloadDebounceTask?.cancel()
            if let newId = newId, let item = items.first(where: { $0.id == newId }) {
              // 合集无需预加载（无详情页）
              if item.collection_id == nil {
                preloadDebounceTask = Task {
                  try? await Task.sleep(for: .milliseconds(300))
                  guard !Task.isCancelled else { return }
                  MediaPreloader.shared.preload(for: item)
                }
              }
            }
            // 分页加载
            if let newId = newId {
              onLoadMore(newId)
            }
          }

          // 焦点重定向器：捕获从不完整行向下导航时的焦点
          Color.clear
            .frame(height: 1)
            .focusable()
            .focused($isBottomRedirectorFocused)
            .onChange(of: isBottomRedirectorFocused) { _, isFocused in
              if isFocused {
                // 将焦点重定向到最后一个项目
                focusedItemId = items.last?.id
                isBottomRedirectorFocused = false
              }
            }

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
    .onAppear {
      if autoFocusFirstItem && focusedItemId == nil {
        focusedItemId = items.first?.id
      }
    }
    .onChange(of: items) { _, newItems in
      if autoFocusFirstItem && focusedItemId == nil {
        focusedItemId = newItems.first?.id
      }
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
    autoFocusFirstItem: Bool = false,
    @ViewBuilder contextMenu: @escaping (MediaInfo) -> ContextMenu
  ) {
    self.init(
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      navigationPath: navigationPath,
      autoFocusFirstItem: autoFocusFirstItem,
      header: { EmptyView() },
      contextMenu: contextMenu
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
    autoFocusFirstItem: Bool = false
  ) {
    self.init(
      items: items,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      navigationPath: navigationPath,
      autoFocusFirstItem: autoFocusFirstItem,
      header: { EmptyView() }
    )
  }
}
