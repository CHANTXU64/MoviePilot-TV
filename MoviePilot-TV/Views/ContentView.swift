import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel: ContentViewModel
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var topShelfNavigationRouter: TopShelfNavigationRouter
  @EnvironmentObject private var topShelfManager: TopShelfManager

  init(viewModel: @autoclosure @escaping () -> ContentViewModel = ContentViewModel()) {
    _viewModel = StateObject(wrappedValue: viewModel())
  }

  var body: some View {
    ZStack {
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
    .disabled(viewModel.isOpeningTopShelf)
    .accessibilityHidden(viewModel.isOpeningTopShelf)
    .environment(\.topShelfPresentation, TopShelfOpeningContext(
      routeID: viewModel.topShelfRoute?.id,
      blocksInteraction: viewModel.isOpeningTopShelf,
      didPresent: { viewModel.finishTopShelfOpening(id: $0) }
    ))
    .overlay {
      if viewModel.isOpeningTopShelf {
        ZStack {
          Color(white: 0.1).ignoresSafeArea()
          VStack(spacing: 32) {
            ProgressView("正在打开详情…")
            Button("取消", action: cancelTopShelfOpening)
          }
        }
        .accessibilityIdentifier("top-shelf-opening")
        .onExitCommand(perform: cancelTopShelfOpening)
      }
    }
    .task {
      updateTopShelfPriority()
      topShelfManager.start()
      await viewModel.prepareStartupIfNeeded()
    }
    .onOpenURL { url in
      if topShelfNavigationRouter.handle(url), let route = topShelfNavigationRouter.pendingRoute {
        viewModel.prepareTopShelfRoute(route)
      }
    }
    .onChange(of: topShelfNavigationRouter.pendingRoute?.id, initial: true) { _, _ in
      if let route = topShelfNavigationRouter.pendingRoute { viewModel.prepareTopShelfRoute(route) }
      updateTopShelfPriority()
    }
    .onChange(of: viewModel.isPreparingStartupSession) { _, _ in
      updateTopShelfPriority()
    }
    .onChange(of: viewModel.isOpeningTopShelf) { _, _ in updateTopShelfPriority() }
    .onChange(of: scenePhase) { _, _ in updateTopShelfPriority() }
    .background(PresentationReadyAction(
      isEnabled: scenePhase == .active && topShelfNavigationRouter.pendingRoute != nil,
      cancelsEditing: true,
      action: reconcileTopShelfRoute
    ))
    .alert(
      viewModel.backendVersionWarning?.title ?? "版本提示",
      isPresented: Binding(
        get: { viewModel.backendVersionWarning != nil },
        set: { if !$0 { viewModel.dismissBackendVersionWarning() } }),
      presenting: viewModel.backendVersionWarning
    ) { _ in
      Button("继续使用", role: .cancel) { viewModel.dismissBackendVersionWarning() }
    } message: { warning in
      Text(warning.message)
    }
    .alert(
      viewModel.accountPermissionWarning?.title ?? "权限提示",
      isPresented: Binding(
        get: { viewModel.accountPermissionWarning != nil },
        set: { if !$0, viewModel.accountPermissionWarning != nil { viewModel.accountPermissionWarning = nil } }),
      presenting: viewModel.accountPermissionWarning
    ) { _ in
      Button("继续使用", role: .cancel) { viewModel.accountPermissionWarning = nil }
    } message: { warning in
      Text(warning.message)
    }
    .withNotification()
  }

  private func updateTopShelfPriority() {
    topShelfManager.setSynchronizationDeferred(
      scenePhase != .active || viewModel.isPreparingStartupSession || viewModel.isOpeningTopShelf
        || topShelfNavigationRouter.pendingRoute != nil
    )
  }

  private func cancelTopShelfOpening() {
    if let route = topShelfNavigationRouter.pendingRoute {
      topShelfNavigationRouter.consume(id: route.id)
    }
    viewModel.cancelTopShelfOpening()
    updateTopShelfPriority()
  }

  private func reconcileTopShelfRoute() {
    // 后台的 Tab 容器仍会恢复上次选择；等前台激活后再交接外部导航。
    guard scenePhase == .active else { return }
    guard let route = topShelfNavigationRouter.pendingRoute else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    let disposition = withTransaction(transaction) { viewModel.acceptTopShelfRoute(route) }
    switch disposition {
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
            navigationCoordinator: viewModel.recommendNavigation,
            allowsRequests: allowsRequests,
            onReturnToRoot: { viewModel.endTopShelfPresentation(id: $0) }
          )
        }
      }
      if viewModel.visibleTabs.contains(.explore) {
        Tab("探索", systemImage: "safari", value: ContentViewModel.Tab.explore) {
          ExploreView(
            isSelected: selectedTab == .explore,
            navigationCoordinator: viewModel.exploreNavigation,
            allowsRequests: allowsRequests,
            onReturnToRoot: { viewModel.endTopShelfPresentation(id: $0) })
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
        mediaActionHandler.cancelPresentation()
        mediaActionHandler = MediaActionHandler()
      }
    }
    .onChange(of: selectedTab) { _, tab in
      if let route = initialTopShelfRoute, tab != route.targetTab {
        viewModel.endTopShelfPresentation()
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
