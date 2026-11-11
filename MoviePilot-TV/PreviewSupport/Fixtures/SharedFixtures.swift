#if DEBUG
import Foundation

/// UI 预览共享 fixture 与状态清理。
///
/// 各业务域在 `Fixtures/` 下用 extension 追加自己的数据构造器；
/// 所有 fixture 都只构造 Model 值，不发起真实网络请求。
enum UIPreviewFixtures {
  static let allPermissions: Set<UserPermissionKey> = [.discovery, .search, .subscribe, .manage]

  /// 预览登录用户。`superUser == true` 时拥有全部权限（与真实超级管理员一致）。
  static func userToken(
    permissions: Set<UserPermissionKey> = allPermissions,
    superUser: Bool = true,
    userName: String = "预览用户"
  ) -> Token {
    Token(
      access_token: "ui-preview-access-token",
      token_type: "bearer",
      super_user: FlexibleBool(superUser),
      permissions: Dictionary(
        uniqueKeysWithValues: UserPermissionKey.allCases.map {
          ($0.rawValue, permissions.contains($0))
        }),
      user_id: 1,
      user_name: userName,
      avatar: nil
    )
  }

  /// 预览全局设置。默认返回已登记兼容版本，不触发版本告警。
  static func globalSettings(backendVersion: String?) -> GlobalSettings {
    GlobalSettings(
      TMDB_IMAGE_DOMAIN: "https://image.tmdb.org/t/p/",
      BANGUMI_PROXY_ENABLE: FlexibleBool(false),
      BANGUMI_IMAGE_DOMAIN: nil,
      BACKEND_VERSION: backendVersion,
      FRONTEND_VERSION: backendVersion,
      BACKEND_DEV: false,
      GLOBAL_IMAGE_CACHE: FlexibleBool(false),
      RECOGNIZE_SOURCE: "themoviedb",
      USER_UNIQUE_ID: "ui-preview-user",
      SUBSCRIBE_SHARE_MANAGE: FlexibleBool(true),
      AI_AGENT_ENABLE: FlexibleBool(true)
    )
  }

  /// 切换预览场景前后清掉页面级缓存，避免上一个场景的预载数据串到下一个场景。
  static func resetPreviewState() {
    APIService.shared.mediaPreloader.clearAll()
  }
}

extension UIPreviewBehaviorKey {
  static let systemSettings = "system.settings"
  static let loginAccessToken = "login.accessToken"
}

extension UIPreviewBackend {
  func globalSettings() -> GlobalSettings {
    UIPreviewFixtures.globalSettings(backendVersion: environment.backendVersion)
  }
}
#endif
