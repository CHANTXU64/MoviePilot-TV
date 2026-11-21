import Foundation

/// MoviePilot v2 后端（最后一条 v2 支持线是 v2.15.6）的请求形状。
/// 只放 v2 与 v3 的协议差异，业务代码不感知版本。
///
/// 删除 v2 支持的步骤（完整清单见 `docs/backend-version-compatibility.md` 的「删除 v2 支持」）：
/// 1. 删除目录 `MoviePilot-TV/Services/BackendProtocol/MoviePilotV2/`；
/// 2. 把 `BackendEndpoints.resolve` 的函数体改成 `return V3BackendEndpoints()`；
/// 3. 删除 `TopShelfManager` 的 v2 可用性门禁、登记表里的 `v2.15.6` 和 README/文档/测试中的 v2 内容。
/// `APIService` 只调用协议能力位，不需要逐处清理。
nonisolated enum MoviePilotV2Support {
  /// 媒体身份从单值键改成成对参数的版本。
  static let pairedIdentityMinimumVersion = MoviePilotVersion("v3.0.0")!

  /// 版本解析不出时按 v3 处理，避免旧会话误走 v2 形状。
  static func isLegacy(backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion) else { return false }
    return version < pairedIdentityMinimumVersion
  }
}

nonisolated struct MoviePilotV2Endpoints: BackendEndpointBuilding {
  /// v2 把来源与原生 ID 拼成单个 `tmdb:123` 键（`parse_media_key` 接受 tmdb/themoviedb 前缀），
  /// 放在 path 或 `mediaid` 参数里；`MediaIdentity.mediaKey` 已经是这个形状。
  func mediaIdentityEndpoint(
    pathPrefix: String,
    identity: MediaIdentity,
    extraParams: [String: String?],
    suffix: String
  ) throws -> BackendEndpointSpec {
    guard let encodedMediaKey = encodeMediaIDPathSegment(identity.mediaKey), !encodedMediaKey.isEmpty
    else { throw APIError.invalidURL }
    return BackendEndpointSpec(path: "\(pathPrefix)/\(encodedMediaKey)\(suffix)", params: extraParams)
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
        "mediaid": identity.mediaKey,
        "title": title,
        "year": year,
        "season": season,
      ])
  }

  /// v2 只按标题/年份/TMDB ID 查库，没有成对身份参数。
  func mediaServerExistsEndpoint(identity: MediaIdentity?, media: MediaInfo) -> BackendEndpointSpec {
    BackendEndpointSpec(
      path: "/mediaserver/exists",
      params: [
        "tmdbid": MediaIdentifier.validNumericIdentifier(media.tmdb_id).map(String.init),
        "title": media.title,
        "year": media.year,
        "season": media.season.map(String.init),
        "mtype": media.type,
      ])
  }

  /// v2 的请求级搜索/识别数据源参数叫 `source`。
  var mediaSourceQueryKey: String { "source" }

  /// v2 的订阅搜索与重置是 GET。
  var subscriptionMaintenanceMethod: String { "GET" }

  /// v2 没有 `GET /media/source`，来源选择器保留内置来源。
  var supportsMediaSourceCatalog: Bool { false }

  /// v2 把命中结果放在 `success` 上，未入库也是 200。
  var mediaServerExistsHitIsSuccessFlag: Bool { true }

  /// v2 的 PUT /subscribe/ 会整条替换，必须提交完整快照。
  func subscriptionUpdateBody(original: Subscribe, draft: Subscribe) throws -> Data {
    try JSONEncoder().encode(V2SubscriptionUpdateBody(draft: draft))
  }
}
