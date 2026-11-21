import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel: ContentViewModel
  private var memoryOptimization = MemoryOptimizationSettings()
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var topShelfNavigationRouter: TopShelfNavigationRouter
  @EnvironmentObject private var topShelfManager: TopShelfManager

  init(viewModel: @autoclosure @escaping () -> ContentViewModel = ContentViewModel()) {
    _viewModel = StateObject(wrappedValue: viewModel())
  }

  var body: some View {
    let presentedBackendWarning = viewModel.backendVersionWarningPresentation
    return ZStack {
      if viewModel.canPresentContent {
        MainContentView(viewModel: viewModel)
          .id(viewModel.sessionUIIdentity)
      } else if viewModel.isPreparingStartupSession {
        ProgressView("正在准备会话…")
      } else {
        LoginView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.1).ignoresSafeArea())
    .environment(\.topShelfPresentation, TopShelfOpeningContext(
      routeID: viewModel.topShelfRoute?.id,
      blocksInteraction: viewModel.isOpeningTopShelf,
      didPresent: { viewModel.finishTopShelfOpening(id: $0) }
    ))
    .task {
      updateTopShelfPriority()
      topShelfManager.start()
      await viewModel.prepareStartupIfNeeded()
    }
    .onChange(of: memoryOptimization.isEnabled, initial: true) { _, enabled in
      KingfisherCachePolicy.apply(memoryOptimizationEnabled: enabled)
      DetailBackdropReturnPolicy.waitsForRemovedPageBackdrop = enabled
    }
    .onOpenURL { url in
      // 深链常在 App 尚未激活时到达；立即交接，让 TabView 首次挂载即停在目标 Tab，避免弹回媒体库。
      viewModel.handleTopShelfURL(url, router: topShelfNavigationRouter)
      updateTopShelfPriority()
    }
    .onChange(of: topShelfNavigationRouter.pendingRoute?.id, initial: true) { _, _ in
      if let route = topShelfNavigationRouter.pendingRoute { viewModel.prepareTopShelfRoute(route) }
      updateTopShelfPriority()
    }
    .onChange(of: viewModel.isPreparingStartupSession) { _, newValue in
      updateTopShelfPriority()
      if !newValue {
        // 启动准备期间只能 preview/wait；准备结束后补一次交接，避免先露出首页。
        reconcileTopShelfRoute()
      }
    }
    .onChange(of: viewModel.isOpeningTopShelf) { _, _ in updateTopShelfPriority() }
    .onChange(of: scenePhase) { _, _ in updateTopShelfPriority() }
    .background(PresentationReadyAction(
      isEnabled: scenePhase == .active && (
        topShelfNavigationRouter.pendingRoute != nil
          || viewModel.pendingBackendVersionWarning != nil
      ),
      cancelsEditing: true,
      action: {
        if topShelfNavigationRouter.pendingRoute != nil {
          reconcileTopShelfRoute()
        } else {
          viewModel.presentPendingBackendVersionWarning()
        }
      }
    ))
    .alert(
      presentedBackendWarning?.warning.title ?? "版本提示",
      isPresented: Binding(
        get: { viewModel.backendVersionWarning != nil },
        set: {
          if !$0, let presentation = presentedBackendWarning {
            viewModel.acknowledgeBackendVersionWarning(presentation)
          }
        }),
      presenting: presentedBackendWarning
    ) { presentation in
      Button("继续使用", role: .cancel) {
        viewModel.acknowledgeBackendVersionWarning(presentation)
      }
    } message: { presentation in
      Text(presentation.warning.message)
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

  private func reconcileTopShelfRoute() {
    // 深链可能未激活时到达；此时就交接，让 TabView 首次挂载即停在目标 Tab，避免弹回媒体库。
    viewModel.reconcileTopShelfRoute(router: topShelfNavigationRouter)
    updateTopShelfPriority()
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
      Tab("媒体库", systemImage: AppSymbol.tabHome, value: ContentViewModel.Tab.home) {
        if allowsRequests { HomeView(isSelected: selectedTab == .home) }
      }

      if viewModel.visibleTabs.contains(.recommend) {
        Tab("推荐", systemImage: AppSymbol.tabRecommend, value: ContentViewModel.Tab.recommend) {
          RecommendView(
            isSelected: selectedTab == .recommend,
            navigationCoordinator: viewModel.recommendNavigation,
            allowsRequests: allowsRequests,
            onReturnToRoot: { viewModel.endTopShelfPresentation(id: $0) }
          )
        }
      }
      if viewModel.visibleTabs.contains(.explore) {
        Tab("探索", systemImage: AppSymbol.tabExplore, value: ContentViewModel.Tab.explore) {
          ExploreView(
            isSelected: selectedTab == .explore,
            navigationCoordinator: viewModel.exploreNavigation,
            allowsRequests: allowsRequests,
            onReturnToRoot: { viewModel.endTopShelfPresentation(id: $0) })
        }
      }
      if viewModel.visibleTabs.contains(.search) {
        Tab("搜索", systemImage: AppSymbol.search, value: ContentViewModel.Tab.search) {
          if allowsRequests { SearchView(isSelected: selectedTab == .search) }
        }
      }
      if viewModel.visibleTabs.contains(.status) {
        Tab("状态", systemImage: AppSymbol.tabStatus, value: ContentViewModel.Tab.status) {
          if allowsRequests { StatusView(isSelected: selectedTab == .status) }
        }
      }
      Tab("设置", systemImage: AppSymbol.tabSettings, value: ContentViewModel.Tab.system) {
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
        // 交接尚未完成时 TabView 可能自行回写 selection，不能当成用户切走，
        // 否则会清掉正在打开的详情路由。交接完成或超时后会校正一次 Tab。
        if !viewModel.isOpeningTopShelf {
          viewModel.endTopShelfPresentation()
        }
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
    .playbackPresentation(APIService.shared.sessionScope.playbackCoordinator)
    .environmentObject(mediaActionHandler)
  }

}
