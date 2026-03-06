import SwiftUI

@main
struct MoviePilot_TVApp: App {
  /// 全局通知管理器，负责应用顶层的消息提示弹出
  @StateObject private var notificationManager = NotificationManager()
  /// 应用程序主入口，挂载全局根视图
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(notificationManager)
    }
  }
}
