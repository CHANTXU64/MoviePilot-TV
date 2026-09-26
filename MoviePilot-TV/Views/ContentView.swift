import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @EnvironmentObject private var topShelfNavigationRouter: TopShelfNavigationRouter
  @EnvironmentObject private var topShelfManager: TopShelfManager

  var body: some View {
    Group {
      if viewModel.canPresentContent {
        MainContentView(viewModel: viewModel, initialTopShelfRoute: viewModel.topShelfRoute)
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

private struct MainContentView: View {
  @ObservedObject var viewModel: ContentViewModel
  let initialTopShelfRoute: PendingTopShelfRoute?
  @State private var mediaActionHandler = MediaActionHandler()
  @State private var selectedTab: ContentViewModel.Tab
  @State private var checkTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase

  init(viewModel: ContentViewModel, initialTopShelfRoute: PendingTopShelfRoute?) {
    self.viewModel = viewModel
    self.initialTopShelfRoute = initialTopShelfRoute
    _selectedTab = State(initialValue: initialTopShelfRoute == nil ? .home : .recommend)
  }

  private var allowsRequests: Bool { !viewModel.isPreparingStartupSession }

  var body: some View {
    TabView(selection: $selectedTab) {
      Group {
        if allowsRequests { HomeView(isSelected: selectedTab == .home) }
      }
      .tabItem { Label("媒体库", systemImage: "play.tv") }
      .tag(ContentViewModel.Tab.home)

      if viewModel.visibleTabs.contains(.recommend) {
        RecommendView(
          isSelected: selectedTab == .recommend,
          initialTopShelfRoute: initialTopShelfRoute,
          allowsRequests: allowsRequests,
          onInitialContentReady: {
            if let id = initialTopShelfRoute?.id { viewModel.finishTopShelfOpening(id: id) }
          }
        )
        .tabItem { Label("推荐", systemImage: "sparkles.tv") }
        .tag(ContentViewModel.Tab.recommend)
      }
      if viewModel.visibleTabs.contains(.explore) {
        Group { if allowsRequests { ExploreView(isSelected: selectedTab == .explore) } }
          .tabItem { Label("探索", systemImage: "safari") }
          .tag(ContentViewModel.Tab.explore)
      }
      if viewModel.visibleTabs.contains(.search) {
        Group { if allowsRequests { SearchView(isSelected: selectedTab == .search) } }
          .tabItem { Label("搜索", systemImage: "magnifyingglass") }
          .tag(ContentViewModel.Tab.search)
      }
      if viewModel.visibleTabs.contains(.status) {
        Group { if allowsRequests { StatusView(isSelected: selectedTab == .status) } }
          .tabItem { Label("状态", systemImage: "slider.horizontal.3") }
          .tag(ContentViewModel.Tab.status)
      }
      Group {
        if allowsRequests { SystemView(isSelected: selectedTab == .system) }
      }
      .tabItem { Label("设置", systemImage: "gear") }
      .tag(ContentViewModel.Tab.system)
    }
    .foregroundColor(.primary)
    .onAppear {
      selectedTab = ContentViewModel.resolvedSelectedTab(selectedTab, visibleTabs: viewModel.visibleTabs)
    }
    .onChange(of: initialTopShelfRoute?.id) { _, id in
      if id != nil {
        mediaActionHandler = MediaActionHandler()
        selectedTab = .recommend
      }
    }
    .onChange(of: viewModel.visibleTabs) { _, tabs in
      selectedTab = ContentViewModel.resolvedSelectedTab(selectedTab, visibleTabs: tabs)
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
