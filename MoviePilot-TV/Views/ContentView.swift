import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var selectedTab = 0
  @State private var checkTask: Task<Void, Never>? = nil
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if viewModel.isLoggedIn {
        TabView(selection: $selectedTab) {
          HomeView()
            .tabItem {
              Label("媒体库", systemImage: "play.tv")
            }
            .tag(0)

          RecommendView()
            .tabItem {
              Label("推荐", systemImage: "sparkles.tv")
            }
            .tag(1)

          ExploreView()
            .tabItem {
              Label("探索", systemImage: "safari")
            }
            .tag(2)

          SearchView()
            .tabItem {
              Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(3)

          StatusView()
            .tabItem {
              Label("状态", systemImage: "slider.horizontal.3")
            }
            .tag(4)

          SystemView()
            .tabItem {
              Label("系统", systemImage: "gear")
            }
            .tag(5)
        }
        .foregroundColor(.primary)
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
    .mediaActionAlerts()
    .environmentObject(mediaActionHandler)
    .withNotification()
  }
}
