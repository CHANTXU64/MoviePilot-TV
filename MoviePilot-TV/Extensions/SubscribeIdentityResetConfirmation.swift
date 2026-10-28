import Foundation

/// 编辑已有订阅并修改媒体身份时的确认文案。
/// 清空进度从 MoviePilot v3.2.0 起才和身份字段写在同一事务里；更早的已解析版本不会发生这件事。
enum SubscribeIdentityResetConfirmation {
  static let minimumBackendVersion = "v3.2.0"

  /// 已解析且低于 v3.2.0 时返回 false。版本缺失或无法解析时返回 true，
  /// 避免实际跑在 v3.2.0 及以上的会话在没有警告时清掉进度。
  static func backendResetsProgress(backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion),
      let minimum = MoviePilotVersion(minimumBackendVersion)
    else { return true }
    return version >= minimum
  }

  static let title = "修改季或剧集组会重置进度"
  static let message =
    "保存后，MoviePilot 会清空该订阅已有的下载进度、优先级和搜索状态，并按新的媒体身份重新搜索。此操作不可撤销。"
  static let cancelButtonTitle = "取消"
  static let confirmButtonTitle = "继续保存"
}
