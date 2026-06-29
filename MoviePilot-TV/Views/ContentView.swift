import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var selectedTab = ContentViewModel.Tab.home
  @State private var checkTask: Task<Void, Never>? = nil
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if viewModel.isPreparingStartupSession {
        ProgressView("正在准备会话...")
      } else if viewModel.isLoggedIn {
        TabView(selection: $selectedTab) {
          HomeView()
            .tabItem {
              Label("媒体库", systemImage: "play.tv")
            }
            .tag(ContentViewModel.Tab.home)

          if viewModel.visibleTabs.contains(.recommend) {
            RecommendView()
              .tabItem {
                Label("推荐", systemImage: "sparkles.tv")
              }
              .tag(ContentViewModel.Tab.recommend)
          }

          if viewModel.visibleTabs.contains(.explore) {
            ExploreView()
              .tabItem {
                Label("探索", systemImage: "safari")
              }
              .tag(ContentViewModel.Tab.explore)
          }

          if viewModel.visibleTabs.contains(.search) {
            SearchView()
              .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
              }
              .tag(ContentViewModel.Tab.search)
          }

          if viewModel.visibleTabs.contains(.status) {
            StatusView()
              .tabItem {
                Label("状态", systemImage: "slider.horizontal.3")
              }
              .tag(ContentViewModel.Tab.status)
          }

          SystemView(isSelected: selectedTab == .system)
            .tabItem {
              Label("设置", systemImage: "gear")
            }
            .tag(ContentViewModel.Tab.system)
        }
        .foregroundColor(.primary)
        .onChange(of: viewModel.visibleTabs) { _, visibleTabs in
          selectedTab = ContentViewModel.resolvedSelectedTab(selectedTab, visibleTabs: visibleTabs)
        }
        .onChange(of: selectedTab) { _, _ in
          // 防抖逻辑：取消之前的任务，重新计时
          checkTask?.cancel()
          checkTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 秒
            if !Task.isCancelled {
              APIService.shared.validateTokenSilently()
            }
          }
        }
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .active {
            // App 回到前台时立即尝试一次静默检测
            APIService.shared.validateTokenSilently()
          }
        }
      } else {
        LoginView()
      }
    }
    .task {
      await viewModel.prepareStartupIfNeeded()
    }
    .alert(item: $viewModel.backendVersionWarning) { warning in
      Alert(
        title: Text(warning.title),
        message: Text(warning.message),
        dismissButton: .default(Text("继续使用"))
      )
    }
    .mediaActionAlerts()
    .environmentObject(mediaActionHandler)
    .withNotification()
  }
}
