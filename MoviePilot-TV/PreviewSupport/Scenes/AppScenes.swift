#if DEBUG
import SwiftUI

/// App 入口 / Tab 页面场景。
@MainActor
enum UIPreviewScenesApp {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "app",
      title: "App 入口 / Tab 页面",
      scenes: [
        .page(
          id: "app.startupPreparing",
          title: "启动准备中",
          note: "登录态冷启动时的“正在准备会话...”占位。"
        ) {
          UIPreviewStartupPreparingScene()
        },
        .page(
          id: "app.loggedIn",
          title: "已登录 · 全部权限",
          note: "真实根视图：媒体库 / 推荐 / 探索 / 搜索 / 状态 / 设置。"
        ) {
          RealAppContentView()
        },
        .page(
          id: "app.limitedTabs",
          title: "已登录 · 仅发现权限",
          note: "只有发现权限时：推荐/探索/搜索仍显示，管理入口（状态）被隐藏，首页无管理员数据。",
          environment: .limited(permissions: Set([.discovery]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "app.accountPermissionWarning",
          title: "账号权限告警",
          note: "缺少探索/搜索/订阅权限时的“账号权限不足”弹窗。",
          environment: .limited(permissions: Set([.discovery]))
        ) {
          RealAppContentView()
        },
        .page(
          id: "app.backendVersionWarning",
          title: "后端版本告警",
          note: "后端版本高于已登记兼容版本时的版本提示弹窗。",
          environment: .playback
        ) {
          RealAppContentView()
        },
      ]
    )
  }
}

private struct UIPreviewStartupPreparingScene: View {
  @FocusState private var isReturnAnchorFocused: Bool

  var body: some View {
    ZStack {
      ProgressView("正在准备会话...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Color.clear
        .frame(width: 1, height: 1)
        .focusable()
        .focused($isReturnAnchorFocused)
        .accessibilityHidden(true)
    }
    .onAppear {
      isReturnAnchorFocused = true
    }
  }
}
#endif
