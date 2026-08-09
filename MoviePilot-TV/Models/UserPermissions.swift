import Foundation

enum UserPermissionKey: String, Codable, CaseIterable {
  case discovery
  case search
  case subscribe
  case manage
}

/// 登录认证令牌
struct Token: Codable, Equatable {
  /// 用户令牌
  let access_token: String
  let token_type: String
  /// 是否属于超级管理员
  let super_user: FlexibleBool?
  /// 普通用户功能权限；非超级用户只在后端明确返回 true 时获得对应功能。
  let permissions: [String: Bool]?
  /// 后端稳定用户 ID；账号级缓存与偏好必须使用它，而不是可修改的用户名。
  let user_id: Int?
  /// 用户名
  let user_name: String
  /// 头像
  let avatar: String?

  init(
    access_token: String,
    token_type: String,
    super_user: FlexibleBool?,
    permissions: [String: Bool]?,
    user_id: Int? = nil,
    user_name: String,
    avatar: String?
  ) {
    self.access_token = access_token
    self.token_type = token_type
    self.super_user = super_user
    self.permissions = permissions
    self.user_id = user_id
    self.user_name = user_name
    self.avatar = avatar
  }

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

  var missingRecommendedContentPermissions: [UserPermissionKey] {
    [
      UserPermissionKey.discovery,
      .search,
      .subscribe,
    ].filter { !canAccess($0) }
  }

  func withoutPersistedAccessToken() -> Token {
    Token(
      access_token: "",
      token_type: token_type,
      super_user: super_user,
      permissions: permissions,
      user_id: user_id,
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
      user_id: user_id,
      user_name: user_name,
      avatar: avatar
    )
  }
}
