import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @StateObject private var mediaActionHandler = MediaActionHandler()

  var body: some View {
    Group {
      if viewModel.isLoggedIn {
        TabView {
          HomeView()
            .compositingGroup()
            .tabItem {
              Label("媒体库", systemImage: "play.tv")
            }

          RecommendView()
            .compositingGroup()
            .tabItem {
              Label("推荐", systemImage: "sparkles.tv")
            }

          ExploreView()
            .compositingGroup()
            .tabItem {
              Label("探索", systemImage: "safari")
            }

          SearchView()
            .compositingGroup()
            .tabItem {
              Label("搜索", systemImage: "magnifyingglass")
            }

          StatusView()
            .compositingGroup()
            .tabItem {
              Label("状态", systemImage: "slider.horizontal.3")
            }

          SystemView()
            .compositingGroup()
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

