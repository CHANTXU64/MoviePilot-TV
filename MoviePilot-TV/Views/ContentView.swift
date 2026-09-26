import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @EnvironmentObject private var topShelfNavigationRouter: TopShelfNavigationRouter
  @EnvironmentObject private var topShelfManager: TopShelfManager

  var body: some View {
    Group {
      if viewModel.canPresentContent {
        MainContentView(viewModel: viewModel)
          .id(viewModel.sessionUIIdentity)
      } else if viewModel.isPreparingStartupSession {
        ProgressView("正在准备会话...")
      } else {
        LoginView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.1).ignoresSafeArea())
    .task {
      updateTopShelfPriority()
      topShelfManager.start()
      await viewModel.prepareStartupIfNeeded()
      reconcileTopShelfRoute()
    }
    .onOpenURL { url in
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        if topShelfNavigationRouter.handle(url) { reconcileTopShelfRoute() }
      }
    }
    .onChange(of: topShelfNavigationRouter.pendingRoute?.id) { _, _ in
      reconcileTopShelfRoute()
    }
    .onChange(of: viewModel.isPreparingStartupSession) { _, _ in
      reconcileTopShelfRoute()
      updateTopShelfPriority()
    }
    .onChange(of: viewModel.isOpeningTopShelf) { _, _ in updateTopShelfPriority() }
    .onChange(of: viewModel.isLoggedIn) { _, _ in reconcileTopShelfRoute() }
    .onChange(of: viewModel.sessionUIIdentity) { _, _ in reconcileTopShelfRoute() }
    .alert(item: $viewModel.backendVersionWarning) { warning in
      Alert(
        title: Text(warning.title),
        message: Text(warning.message),
        dismissButton: .default(Text("继续使用"))
      )
    }
    .alert(item: $viewModel.accountPermissionWarning) { warning in
      Alert(
        title: Text(warning.title),
        message: Text(warning.message),
        dismissButton: .default(Text("继续使用"))
      )
    }
    .withNotification()
  }

  private func updateTopShelfPriority() {
    topShelfManager.setSynchronizationDeferred(
      viewModel.isPreparingStartupSession || viewModel.isOpeningTopShelf
    )
  }

  private func reconcileTopShelfRoute() {
    guard let route = topShelfNavigationRouter.pendingRoute else { return }
    switch viewModel.acceptTopShelfRoute(route) {
    case .wait:
      break
    case .preview, .open, .discard:
      topShelfNavigationRouter.consume(id: route.id)
      updateTopShelfPriority()
    }
  }
}

struct MainContentView: View {
  @ObservedObject var viewModel: ContentViewModel
  private var initialTopShelfRoute: PendingTopShelfRoute? { viewModel.topShelfRoute }
  @State private var mediaActionHandler = MediaActionHandler()
  @State private var checkTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase

  private var selectedTab: ContentViewModel.Tab { viewModel.selectedTab }
  private var allowsRequests: Bool { !viewModel.isPreparingStartupSession }

  var body: some View {
    TabView(selection: $viewModel.selectedTab) {
      Tab("媒体库", systemImage: "play.tv", value: ContentViewModel.Tab.home) {
        if allowsRequests { HomeView(isSelected: selectedTab == .home) }
      }

      if viewModel.visibleTabs.contains(.recommend) {
        Tab("推荐", systemImage: "sparkles.tv", value: ContentViewModel.Tab.recommend) {
          RecommendView(
            isSelected: selectedTab == .recommend,
            initialTopShelfRoute: initialTopShelfRoute,
            allowsRequests: allowsRequests,
            onInitialContentReady: {
              if let id = initialTopShelfRoute?.id { viewModel.finishTopShelfOpening(id: id) }
            }
          )
        }
      }
      if viewModel.visibleTabs.contains(.explore) {
        Tab("探索", systemImage: "safari", value: ContentViewModel.Tab.explore) {
          if allowsRequests { ExploreView(isSelected: selectedTab == .explore) }
        }
      }
      if viewModel.visibleTabs.contains(.search) {
        Tab("搜索", systemImage: "magnifyingglass", value: ContentViewModel.Tab.search) {
          if allowsRequests { SearchView(isSelected: selectedTab == .search) }
        }
      }
      if viewModel.visibleTabs.contains(.status) {
        Tab("状态", systemImage: "slider.horizontal.3", value: ContentViewModel.Tab.status) {
          if allowsRequests { StatusView(isSelected: selectedTab == .status) }
        }
      }
      Tab("设置", systemImage: "gear", value: ContentViewModel.Tab.system) {
        if allowsRequests { SystemView(isSelected: selectedTab == .system) }
      }
    }
    .foregroundColor(.primary)
    .onChange(of: initialTopShelfRoute?.id) { _, id in
      if id != nil {
        mediaActionHandler = MediaActionHandler()
      }
    }
    .onChange(of: selectedTab) { _, tab in
      if tab != .recommend, let id = initialTopShelfRoute?.id {
        viewModel.finishTopShelfOpening(id: id)
      }
      checkTask?.cancel()
      checkTask = Task {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, allowsRequests else { return }
        APIService.shared.validateTokenSilently()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active, allowsRequests { APIService.shared.validateTokenSilently() }
    }
    .onDisappear { checkTask?.cancel() }
    .mediaActionAlerts()
    .environmentObject(mediaActionHandler)
  }
}
