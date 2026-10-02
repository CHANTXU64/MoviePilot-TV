import SwiftUI

@main
struct MoviePilot_TVApp: App {
  /// 全局通知管理器，负责应用顶层的消息提示弹出
  @StateObject private var notificationManager = NotificationManager()
  @StateObject private var topShelfManager = TopShelfManager()
  @StateObject private var topShelfNavigationRouter = TopShelfNavigationRouter()

  init() {
    KingfisherCachePolicy.apply()
    Self.bootstrapLogging()
  }

  private static func bootstrapLogging() {
    guard NSClassFromString("XCTestCase") == nil else { return }
    Logger.bootstrap(
      handler: MultiplexLogHandler(handlers: [
        PrintLogHandler(),
        PersistentLogHandler(store: .shared),
      ]))
    PersistentLogStore.shared.pruneExpired()
  }

  /// 应用程序主入口，挂载全局根视图
  var body: some Scene {
    WindowGroup {
      // Hosted unit tests replace shared session state. Keep their host from
      // publishing those fixtures to the user's Home Screen or starting requests.
      if NSClassFromString("XCTestCase") == nil {
        ContentView()
          .environmentObject(notificationManager)
          .environmentObject(topShelfManager)
          .environmentObject(topShelfNavigationRouter)
      }
    }
  }
}
