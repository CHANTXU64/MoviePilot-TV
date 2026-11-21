import Foundation

/// 后端版本读不出或解析不了时使用：读请求沿用 v3 形状，订阅写回改成完整快照。
///
/// v2 的 `PUT /subscribe/` 是整条替换，v3 的稀疏变更会把未提交的站点、保存路径等清空；
/// 而 v3 只写请求里出现的字段，提交与库中相同的值不会改变任何东西，所以全量快照对两种协议
/// 都安全。这样即使版本号损坏的 v2 后端被误判成 v3，编辑订阅也不会丢配置。
///
/// 删除 v2 支持时把这个类型一起删掉：步骤见 `MoviePilotV2Endpoints.swift` 顶部注释。
nonisolated struct UnresolvedBackendEndpoints: BackendEndpointBuilding {
  private let modern = V3BackendEndpoints()

  var mediaSourceQueryKey: String { modern.mediaSourceQueryKey }
  var subscriptionMaintenanceMethod: String { modern.subscriptionMaintenanceMethod }
  var supportsMediaSourceCatalog: Bool { modern.supportsMediaSourceCatalog }
  var mediaServerExistsHitIsSuccessFlag: Bool { modern.mediaServerExistsHitIsSuccessFlag }
  var includesDetailTitleFallback: Bool { modern.includesDetailTitleFallback }

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
    try JSONEncoder().encode(
      V2SubscriptionUpdateBody(draft: draft, includesStableClassificationID: true))
  }
}
