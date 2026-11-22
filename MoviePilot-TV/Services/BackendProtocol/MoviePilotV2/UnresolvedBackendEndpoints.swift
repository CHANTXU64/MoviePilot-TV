import Foundation

/// 后端版本读不出或解析不了时使用：读请求以 v3 形状为主，并带上 v2 的读兜底；
/// 订阅写回和按媒体删除订阅直接拒绝。
///
/// 读兜底只影响参数：详情补 `title`/`year`，入库检查按 v2 的 `success=false` 语义解释。
/// v3 会忽略多余的标题参数、`success` 正常恒为 true，因此两种后端都能读。
/// 搜索/识别仍使用 v3 的 `media_source` 参数，实际为 v2 时这两项要等版本到达后恢复。
///
/// v2 的 `PUT /subscribe/` 是整条替换，v3 只写请求里出现的字段；版本未知时无法判断
/// 该用哪种形状。猜 v2 会把旧草稿整条写回，猜 v3 会把 v2 的站点、保存路径清空，
/// 因此写入交给调用方提示重试，等 `/system/global` 返回后再保存。
///
/// 按媒体删除订阅同理：v2 收到 v3 形状的 `DELETE /subscribe/media/42?media_source=...`
/// 会按原值 `mediaid == "42"` 匹配旧订阅、不按季号过滤，没删到也返回成功。
/// 按订阅 ID 删除（`DELETE /subscribe/{id}`）两个版本同形，不受影响。
///
/// 删除 v2 支持时把这个类型一起删掉：步骤见 `MoviePilotV2Endpoints.swift` 顶部注释。
nonisolated struct UnresolvedBackendEndpoints: BackendEndpointBuilding {
  private let modern = V3BackendEndpoints()

  var mediaSourceQueryKey: String { modern.mediaSourceQueryKey }
  var subscriptionMaintenanceMethod: String { modern.subscriptionMaintenanceMethod }
  var supportsMediaSourceCatalog: Bool { modern.supportsMediaSourceCatalog }
  var mediaServerExistsHitIsSuccessFlag: Bool { true }
  var includesDetailTitleFallback: Bool { true }

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

  func mediaSubscriptionDeleteEndpoint(identity: MediaIdentity, season: Int?) throws
    -> BackendEndpointSpec
  {
    throw APIError.backendVersionUnavailable
  }

  func subscriptionUpdateBody(original: Subscribe, draft: Subscribe) throws -> Data {
    throw APIError.backendVersionUnavailable
  }
}
