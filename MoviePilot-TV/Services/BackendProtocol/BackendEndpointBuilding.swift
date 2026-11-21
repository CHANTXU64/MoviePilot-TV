import Foundation

/// 一次请求的 path 与 query 参数，由 `APIService.buildEndpoint` 统一做百分号编码。
nonisolated struct BackendEndpointSpec: Equatable {
  let path: String
  let params: [String: String?]

  init(path: String, params: [String: String?] = [:]) {
    self.path = path
    self.params = params
  }
}

/// 后端请求协议形状。MoviePilot v3.0.0 起媒体身份从单值 `tmdb:123` 改为
/// `media_source` + `media_id` 成对参数，订阅维护动作也从 GET 改为 POST。
/// v2 的旧形状只由 `BackendProtocol/MoviePilotV2` 下的实现提供；删除该目录即可退出 v2 兼容。
nonisolated protocol BackendEndpointBuilding: Sendable {
  /// 媒体身份在 path/query 中的写法。`identity` 必须是已归一化的主身份。
  func mediaIdentityEndpoint(
    pathPrefix: String,
    identity: MediaIdentity,
    extraParams: [String: String?],
    suffix: String
  ) throws -> BackendEndpointSpec

  /// `GET /media/seasons` 的查询参数。
  func mediaSeasonsEndpoint(
    identity: MediaIdentity,
    title: String?,
    year: String?,
    season: String?
  ) -> BackendEndpointSpec

  /// `GET /mediaserver/exists` 的查询参数。
  func mediaServerExistsEndpoint(identity: MediaIdentity?, media: MediaInfo) -> BackendEndpointSpec

  /// `/media/search` 与 `/media/recognize` 的数据源参数名。
  var mediaSourceQueryKey: String { get }

  /// `/subscribe/search/{id}` 与 `/subscribe/reset/{id}` 的 HTTP 方法。
  var subscriptionMaintenanceMethod: String { get }

  /// `GET /media/source` 是否存在。v2 没有来源目录，选择器保留内置来源。
  var supportsMediaSourceCatalog: Bool { get }

  /// `GET /mediaserver/exists` 是否用 `success` 表示命中结果。
  /// v2 命中与未命中都返回 200，`success=false` 表示未入库；v3 起 `success` 恒为 `true`。
  var mediaServerExistsHitIsSuccessFlag: Bool { get }

  /// `PUT /subscribe/` 的请求体。
  /// v3 只发变化字段；v2 的更新是整条替换，必须提交完整快照，否则未提交字段会被默认值覆盖。
  /// 调用方传入的 `draft` 必须是原订阅的完整副本，`original` 只用来计算变化。
  func subscriptionUpdateBody(original: Subscribe, draft: Subscribe) throws -> Data
}

/// v3 及以上的请求形状，与 2026-09 迁移后的现有实现一致。
nonisolated struct V3BackendEndpoints: BackendEndpointBuilding {
  func mediaIdentityEndpoint(
    pathPrefix: String,
    identity: MediaIdentity,
    extraParams: [String: String?],
    suffix: String
  ) throws -> BackendEndpointSpec {
    guard let encodedMediaId = encodeMediaIDPathSegment(identity.mediaId), !encodedMediaId.isEmpty
    else { throw APIError.invalidURL }
    var params = extraParams
    params["media_source"] = identity.source
    return BackendEndpointSpec(path: "\(pathPrefix)/\(encodedMediaId)\(suffix)", params: params)
  }

  func mediaSeasonsEndpoint(
    identity: MediaIdentity,
    title: String?,
    year: String?,
    season: String?
  ) -> BackendEndpointSpec {
    BackendEndpointSpec(
      path: "/media/seasons",
      params: [
        "media_source": identity.source,
        "media_id": identity.mediaId,
        "title": title,
        "year": year,
        "season": season,
      ])
  }

  func mediaServerExistsEndpoint(identity: MediaIdentity?, media: MediaInfo) -> BackendEndpointSpec {
    BackendEndpointSpec(
      path: "/mediaserver/exists",
      params: [
        "media_source": identity?.source,
        "media_id": identity?.mediaId,
        "title": media.title,
        "year": media.year,
        "season": media.season.map(String.init),
        "mtype": media.type,
      ])
  }

  var mediaSourceQueryKey: String { "media_source" }
  var subscriptionMaintenanceMethod: String { "POST" }
  var supportsMediaSourceCatalog: Bool { true }
  var mediaServerExistsHitIsSuccessFlag: Bool { false }

  func subscriptionUpdateBody(original: Subscribe, draft: Subscribe) throws -> Data {
    try JSONEncoder().encode(SubscriptionWriteDTO(original: original, draft: draft))
  }
}

nonisolated enum BackendEndpoints {
  /// 按后端版本选请求形状。读请求默认按 v3 发；只有版本解析不了时改用
  /// `UnresolvedBackendEndpoints`，让订阅写回走完整快照，避免误判成 v3 后整条覆盖 v2 的配置。
  /// 删除 `Services/BackendProtocol/MoviePilotV2` 后，把函数体固定为 `V3BackendEndpoints()`。
  static func resolve(backendVersion: String?) -> any BackendEndpointBuilding {
    guard let version = MoviePilotVersion(backendVersion) else {
      return UnresolvedBackendEndpoints()
    }
    return version < MoviePilotV2Support.pairedIdentityMinimumVersion
      ? MoviePilotV2Endpoints() : V3BackendEndpoints()
  }
}
