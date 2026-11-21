import Foundation

/// 后端版本读不出或解析不了时使用：读请求沿用 v3 形状，订阅写回直接拒绝。
///
/// v2 的 `PUT /subscribe/` 是整条替换，v3 只写请求里出现的字段；版本未知时无法判断
/// 该用哪种形状。猜 v2 会把旧草稿整条写回，猜 v3 会把 v2 的站点、保存路径清空，
/// 因此写入交给调用方提示重试，等 `/system/global` 返回后再保存。
///
/// 删除 v2 支持时把这个类型一起删掉：步骤见 `MoviePilotV2Endpoints.swift` 顶部注释。
nonisolated struct UnresolvedBackendEndpoints: BackendEndpointBuilding {
  private let modern = V3BackendEndpoints()

  var mediaSourceQueryKey: String { modern.mediaSourceQueryKey }
  var subscriptionMaintenanceMethod: String { modern.subscriptionMaintenanceMethod }
  var supportsMediaSourceCatalog: Bool { modern.supportsMediaSourceCatalog }
  var mediaServerExistsHitIsSuccessFlag: Bool { modern.mediaServerExistsHitIsSuccessFlag }
  var includesDetailTitleFallback: Bool { modern.includesDetailTitleFallback }
  var isResolved: Bool { false }

  func mediaIdentityEndpoint(
    pathPrefix: String,
    identity: MediaIdentity,
    extraParams: [String: String?],
    suffix: String
  ) throws -> BackendEndpointSpec {
    try modern.mediaIdentityEndpoint(
      pathPrefix: pathPrefix, identity: identity, extraParams: extraParams, suffix: suffix)
  }

  func mediaSeasonsEndpoint(
    identity: MediaIdentity,
    title: String?,
    year: String?,
    season: String?
  ) -> BackendEndpointSpec {
    modern.mediaSeasonsEndpoint(identity: identity, title: title, year: year, season: season)
  }

  func mediaServerExistsEndpoint(identity: MediaIdentity?, media: MediaInfo) -> BackendEndpointSpec {
    modern.mediaServerExistsEndpoint(identity: identity, media: media)
  }

  func subscriptionUpdateBody(original: Subscribe, draft: Subscribe) throws -> Data {
    throw APIError.backendVersionUnavailable
  }
}
