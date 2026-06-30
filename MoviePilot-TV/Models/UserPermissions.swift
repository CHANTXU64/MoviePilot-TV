import Foundation

enum UserPermissionKey: String, Codable, CaseIterable {
  case discovery
  case search
  case subscribe
  case manage
}

/// 登录认证令牌
struct Token: Codable {
  /// 用户令牌
  let access_token: String
  let token_type: String
  /// 是否属于超级管理员
  let super_user: FlexibleBool?
  /// 普通用户功能权限；非超级用户只在后端明确返回 true 时获得对应功能。
  let permissions: [String: Bool]?
  /// 用户名
  let user_name: String
  /// 头像
  let avatar: String?

  var canRequestSuperUserEndpoints: Bool {
    super_user?.value == true
  }

  var hasKnownFeaturePermissions: Bool {
    super_user?.value == true || permissions != nil
  }

  func canAccess(_ permission: UserPermissionKey) -> Bool {
    if super_user?.value == true { return true }
    guard let permissions else { return false }
    return permissions[permission.rawValue] == true
  }

  var hasLoginAccessibleFeature: Bool {
    if super_user?.value == true { return true }
    return [
      UserPermissionKey.discovery,
      .search,
      .subscribe,
      .manage,
    ].contains { canAccess($0) }
  }

  func withoutPersistedAccessToken() -> Token {
    Token(
      access_token: "",
      token_type: token_type,
      super_user: super_user,
      permissions: permissions,
      user_name: user_name,
      avatar: avatar
    )
  }

  func withRestoredAccessToken(_ storedToken: String) -> Token? {
    guard access_token == storedToken || access_token.isEmpty else { return nil }
    guard access_token.isEmpty else { return self }
    return Token(
      access_token: storedToken,
      token_type: token_type,
      super_user: super_user,
      permissions: permissions,
      user_name: user_name,
      avatar: avatar
    )
  }
}
