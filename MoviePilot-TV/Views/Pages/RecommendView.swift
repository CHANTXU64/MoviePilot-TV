import SwiftUI

struct RecommendView: View {
  private let isSelected: Bool
  private let allowsRequests: Bool
  private let initialTopShelfRoute: PendingTopShelfRoute?
  private let onInitialContentReady: () -> Void
  @StateObject private var navigationCoordinator: ImageNavigationCoordinator
  @Environment(\.scenePhase) private var scenePhase

  init(
    isSelected: Bool,
    initialTopShelfRoute: PendingTopShelfRoute? = nil,
    allowsRequests: Bool = true,
    onInitialContentReady: @escaping () -> Void = {}
  ) {
    self.isSelected = isSelected
    self.allowsRequests = allowsRequests
    self.initialTopShelfRoute = initialTopShelfRoute
    self.onInitialContentReady = onInitialContentReady
    _navigationCoordinator = StateObject(wrappedValue: ImageNavigationCoordinator(
      initialEntry: initialTopShelfRoute?.navigationEntry,
      startsInitialMediaLoad: allowsRequests
    ))
  }

  var body: some View {
    NavigationStack(path: $navigationCoordinator.path) {
      Group {
        if allowsRequests {
          RecommendRootContent(isSelected: isSelected)
        } else {
          Color(white: 0.1).ignoresSafeArea()
        }
      }
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(
          entry: entry,
          allowsRequests: allowsRequests,
          onInitialContentReady: {
            if entry.id == initialTopShelfRoute?.id { onInitialContentReady() }
          }
        )
      }
    }
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .onAppear { updateStackForeground() }
    .onChange(of: initialTopShelfRoute?.id) { _, _ in
      guard let route = initialTopShelfRoute else { return }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        navigationCoordinator.openExternal(route.navigationEntry, startsMediaLoad: allowsRequests)
      }
    }
    .onChange(of: isSelected) { _, _ in updateStackForeground() }
    .onChange(of: scenePhase) { _, _ in updateStackForeground() }
    .onChange(of: navigationCoordinator.path.count) { _, count in
      if count == 0 {
        onInitialContentReady()
      }
    }
    .task(id: allowsRequests) {
      guard allowsRequests else { return }
      navigationCoordinator.startDeferredMediaLoads()
    }
  }

  private func updateStackForeground() {
    navigationCoordinator.setStackPresentation(isSelected: isSelected, scenePhase: scenePhase)
  }
}

/// 推荐根页独立于详情历史，外部打开也保留列表和滚动状态。
private struct RecommendRootContent: View {
  let isSelected: Bool
  @StateObject private var viewModel = RecommendViewModel()
  @State private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator

  var body: some View {
    Group {
      if let paginator = viewModel.paginator {
        // 主内容槽（网格布局）
        MediaGridView(
          imageLifecycle: navigationCoordinator.rootLifecycle,
          listIdentity: paginator.listIdentity,
          items: paginator.items,
          isLoading: paginator.isFirstLoading,
          isLoadingMore: paginator.isLoadingMore,
          onLoadMore: { newId in
            Task {
              await paginator.loadMore(newId)
            }
          },
          header: {
            VStack(spacing: 20) {
              // 分类选择器 - 使用 Picker，带 Icon
              CategoryPickerView(
                categories: viewModel.visibleCategories,
                selectedCategory: $viewModel.selectedCategory
              )
                .onChange(of: viewModel.selectedCategory) { _, _ in
                  viewModel.onCategoryChanged()
                }

              // 货架选择器 - 横向滚动 chips
              ShelfPicker(
                shelves: viewModel.filteredShelves,
                selectedShelf: $viewModel.selectedShelf
              )
            }
          },
          contextMenu: { item in
            MediaContextMenuItems(
              item: item,
              subscriptionHandler: subscriptionHandler
            )
          }
        )
      } else if viewModel.filteredShelves.isEmpty {
        VStack(spacing: 24) {
          if !viewModel.visibleCategories.isEmpty {
            CategoryPickerView(
              categories: viewModel.visibleCategories,
              selectedCategory: $viewModel.selectedCategory
            )
            .onChange(of: viewModel.selectedCategory) { _, _ in
              viewModel.onCategoryChanged()
            }
          }
          Text("没有已启用的推荐货架")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // 在 Paginator 初始化完成前显示加载指示器
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      subscriptionHandler = SubscriptionHandler()
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .onAppear { viewModel.reloadLocalConfig() }
    .task(id: isSelected) {
      guard isSelected else { return }
      await viewModel.refreshSources()
    }
  }
}

// MARK: - 分类选择器（使用 Picker，带 Icon）
struct CategoryPickerView: View {
  let categories: [RecommendCategory]
  @Binding var selectedCategory: RecommendCategory

  var body: some View {
    Picker("分类", selection: $selectedCategory) {
      ForEach(categories) { category in
        Label(category.rawValue, systemImage: category.icon)
          .tag(category)
      }
    }
    .pickerStyle(.segmented)
  }
}
