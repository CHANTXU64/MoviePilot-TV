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
          id: "app.permissionWarningMissingSubscribe",
          title: "账号权限告警 · 仅缺订阅",
          note:
            "账号已有探索、搜索权限，只缺订阅权限：告警文案只列出“订阅”，用于验证缺失权限列表按账号实际权限拼接。",
          environment: .limited(permissions: Set([.discovery, .search]))
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
        .page(
          id: "app.backendVersionUnregistered",
          title: "后端版本告警 · 未登记",
          note:
            "后端 v3.0.6 落在兼容表缺口，启动后弹出“兼容性尚未验证”告警；使用独立预览地址，避免与 v3.0.0 / v3.2.6 场景共用“已确认”记录。",
          environment: UIPreviewEnvironment(
            token: UIPreviewFixtures.userToken(),
            baseURL: "http://moviepilot-ui-preview.local:3002",
            backendVersion: "v3.0.6"
          )
        ) {
          RealAppContentView()
        },
        .page(
          id: "app.startupSettingsFailure",
          title: "启动 · 后端设置读取失败",
          note:
            "启动准备阶段读取全局设置网络超时：版本号无法确认，主界面仍会显示，并弹出“无法确认 MoviePilot 后端版本”告警。使用独立预览地址，避免与已确认记录串用。",
          environment: startupSettingsFailureEnvironment
        ) {
          RealAppContentView()
        },
        .page(
          id: "app.loginTimeout",
          title: "启动登录 · 请求超时",
          note:
            "未登录环境进入真实 LoginView，预填表单后自动提交；login 接口网络超时，顶部错误通知显示“登录失败: The request timed out.”（系统本地化文案，随系统语言变化），约 5 秒后消失，表单恢复可再次提交。",
          environment: appLoginEnvironment(behavior: .error(.networkTimeout))
        ) {
          UIPreviewAppLoginForm(
            draft: LoginDraft(
              serverURL: "http://192.168.1.5:3000",
              username: "preview-user",
              password: "preview-password",
              reason: .missingCredentials
            )
          )
        },
        .page(
          id: "app.loginCredentialsRejected",
          title: "启动登录 · 用户名或密码错误",
          note:
            "登录接口返回 credentialsRejected：错误通知只有“用户名或密码错误”，不带“登录失败:”前缀；登录草稿会记录该原因，供下次打开登录页预填。",
          environment: appLoginEnvironment(behavior: .error(.credentialsRejected))
        ) {
          UIPreviewAppLoginForm(
            draft: LoginDraft(
              serverURL: "http://192.168.1.5:3000",
              username: "preview-user",
              password: "wrong-password",
              reason: .missingCredentials
            )
          )
        },
      ]
    )
  }

  private static var startupSettingsFailureEnvironment: UIPreviewEnvironment {
    var environment = UIPreviewEnvironment(
      token: UIPreviewFixtures.userToken(),
      baseURL: "http://moviepilot-ui-preview.local:3003",
      backendVersion: "v3.2.5"
    )
    environment.behaviors[UIPreviewBehaviorKey.systemSettings] = .error(.networkTimeout)
    return environment
  }

  private static func appLoginEnvironment(
    behavior: UIPreviewBackend.Behavior
  ) -> UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.loggedOut
    environment.context[UIPreviewContextKey.loginAutoSubmit] = "1"
    environment.behaviors[UIPreviewBehaviorKey.loginAccessToken] = behavior
    return environment
  }
}

/// 登录表单：用 `LoginDraft` 预填真实 `LoginViewModel` 的初始值。
/// `LoginView` 的 ViewModel 不可注入，因此沿用 APIService 的内存草稿。
private struct UIPreviewAppLoginForm: View {
  init(draft: LoginDraft) {
    APIService.shared.loginDraft = draft
  }

  var body: some View {
    LoginView()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(white: 0.1))
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
