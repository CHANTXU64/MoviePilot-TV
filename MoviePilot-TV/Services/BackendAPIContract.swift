import Foundation

nonisolated enum BackendCapabilityError: LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): return reason
    }
  }
}

/// 只封装已有合同的差异点；共享端点与业务模型不随版本复制。
nonisolated struct BackendAPIContract {
  let profile: BackendContractProfile?
  var version: MoviePilotVersion? = nil

  var subscriptionForkUnavailableReason: String? {
    guard let version, let fixedVersion = MoviePilotVersion("v3.0.5"),
      version < fixedVersion
    else { return nil }
    return "当前旧版 MoviePilot 的复用订阅接口（v3.0.4 已确认）存在响应合同缺陷，可能创建成功却返回失败。为避免重复创建，此版本暂不可复用；请升级后端后再试。普通订阅与编辑仍可使用。"
  }

  func subscriptionLookupParameters(
    media: MediaInfo,
    season: Int?,
    includeVideoMetadataFallback: Bool
  ) -> [String: String?] {
    let isVideo = media.type == "电影" || media.type == "电视剧"
    let usesFallback: Bool
    switch profile {
    case .v304:
      // v3.0.4 的回退只覆盖非 TMDB、带标题与年份的影视。
      usesFallback = includeVideoMetadataFallback && isVideo
        && media.identity?.source != "themoviedb"
        && trimmedNonEmpty([media.title]) != nil
        && trimmedNonEmpty([media.year]) != nil
    case .v30101, nil:
      // 未登记版本保留共享请求行为，但不据此认定它实现了最新回退能力。
      usesFallback = includeVideoMetadataFallback && isVideo
    }
    return [
      "season": season.map(String.init),
      "title": media.title,
      "year": usesFallback ? media.year : nil,
      "mtype": usesFallback ? media.type : nil,
    ]
  }
}
