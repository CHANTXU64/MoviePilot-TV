import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @StateObject private var mediaActionHandler = MediaActionHandler()

  var body: some View {
    Group {
      if viewModel.isLoggedIn {
        TabView {
          HomeView()
            .tabItem {
              Label("媒体库", systemImage: "play.tv")
            }

          RecommendView()
            .tabItem {
              Label("推荐", systemImage: "sparkles.tv")
            }

          ExploreView()
            .tabItem {
              Label("探索", systemImage: "safari")
            }

          SearchView()
            .tabItem {
              Label("搜索", systemImage: "magnifyingglass")
            }

          StatusView()
            .tabItem {
              Label("状态", systemImage: "slider.horizontal.3")
            }

          SystemView()
            .tabItem {
              Label("系统", systemImage: "gear")
            }
        }
        .foregroundColor(.primary)
      } else {
        LoginView()
      }
    }
    .mediaActionAlerts()
    .environmentObject(mediaActionHandler)
    .withNotification()
  }
}
