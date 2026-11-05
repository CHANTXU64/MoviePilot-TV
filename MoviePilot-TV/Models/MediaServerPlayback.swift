import Foundation

/// MoviePilot `MediaServers` 配置里的连接信息，只有超管读取 `/system/setting/MediaServers` 时才有。
///
/// Emby/Jellyfin 的键是 `host`、`play_host`、`apikey`、`username`（MoviePilot v3.0.4 至 v3.2.4 一致）。
/// 其他类型字段不同，缺失或类型不符的字段按未配置处理，不影响整条配置解码。
nonisolated struct MediaServerConnectionConfig: Decodable, Equatable, Sendable {
  /// 内网地址
  let host: String?
  /// 外网（反代）播放地址
  let playHost: String?
  let apiKey: String?
  /// MoviePilot 用来匹配媒体服务器用户的用户名
  let username: String?

  init(host: String?, playHost: String?, apiKey: String?, username: String?) {
    self.host = host
    self.playHost = playHost
    self.apiKey = apiKey
    self.username = username
  }

  private enum CodingKeys: String, CodingKey {
    case host, play_host, apikey, api_key, token, username
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func text(_ key: CodingKeys) -> String? {
      guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    host = text(.host)
    playHost = text(.play_host)
    apiKey = text(.apikey) ?? text(.api_key) ?? text(.token)
    username = text(.username)
  }

  /// 按「内网优先、外网其次」排列的候选地址，已规范化并去重。
  var candidateBaseURLs: [URL] {
    var result: [URL] = []
    for raw in [host, playHost] {
      guard let url = EmbyBaseURL.normalized(raw), !result.contains(url) else { continue }
      result.append(url)
    }
    return result
  }
}

extension MediaServerConnectionConfig: CustomStringConvertible, CustomDebugStringConvertible {
  /// 日志和调试输出不能带出密钥。
  var description: String {
    "MediaServerConnectionConfig(host: \(host ?? "nil"), playHost: \(playHost ?? "nil"), apiKey: \(apiKey == nil ? "nil" : "<redacted>"), username: \(username ?? "nil"))"
  }

  var debugDescription: String { description }
}

/// Emby 服务器根地址：补全协议、去掉结尾斜杠，保留反代路径前缀（与 MoviePilot `standardize_base_url` 一致，缺协议按 http）。
nonisolated enum EmbyBaseURL {
  static func normalized(_ raw: String?) -> URL? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    let lowercased = value.lowercased()
    if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
      value = "http://" + value
    }
    guard var components = URLComponents(string: value),
      let host = components.host, !host.isEmpty
    else { return nil }
    components.query = nil
    components.fragment = nil
    var path = components.percentEncodedPath
    while path.hasSuffix("/") { path.removeLast() }
    components.percentEncodedPath = path
    return components.url
  }
}

// MARK: - Emby 接口数据

nonisolated struct EmbyPublicSystemInfo: Decodable, Sendable {
  let id: String?
  let serverName: String?
  let version: String?

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case serverName = "ServerName"
    case version = "Version"
  }
}

nonisolated struct EmbyUser: Decodable, Sendable {
  let id: String
  let name: String?
  let isAdministrator: Bool

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case policy = "Policy"
  }

  private struct Policy: Decodable {
    let isAdministrator: Bool?
    private enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator" }
  }

  init(id: String, name: String?, isAdministrator: Bool) {
    self.id = id
    self.name = name
    self.isAdministrator = isAdministrator
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    let policy = try? container.decodeIfPresent(Policy.self, forKey: .policy)
    isAdministrator = policy?.isAdministrator ?? false
  }

  /// 与 MoviePilot `Emby.get_user` 相同的选择顺序：依次匹配候选用户名，都不匹配时取第一个管理员。
  static func select(from users: [EmbyUser], preferredNames: [String?]) -> EmbyUser? {
    for name in preferredNames {
      guard let name, !name.isEmpty else { continue }
      if let user = users.first(where: { $0.name == name }) { return user }
    }
    return users.first { $0.isAdministrator }
  }
}

nonisolated struct EmbyItem: Decodable, Sendable {
  let id: String
  let name: String?
  let type: String?
  let overview: String?
  let productionYear: Int?
  let runTimeTicks: Int64?
  /// 原样保留用户数据，回写进度时只改进度相关字段，不丢收藏等其他字段。
  let userData: [String: JSONValue]?
  /// 剧集：集号、季号、剧名
  let indexNumber: Int?
  let parentIndexNumber: Int?
  let seriesName: String?
  /// `Virtual` 表示 Emby 只有元数据、没有文件（缺失的集）。
  let locationType: String?

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case type = "Type"
    case overview = "Overview"
    case productionYear = "ProductionYear"
    case runTimeTicks = "RunTimeTicks"
    case userData = "UserData"
    case indexNumber = "IndexNumber"
    case parentIndexNumber = "ParentIndexNumber"
    case seriesName = "SeriesName"
    case locationType = "LocationType"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    overview = try? container.decodeIfPresent(String.self, forKey: .overview)
    productionYear = try? container.decodeIfPresent(Int.self, forKey: .productionYear)
    runTimeTicks = try? container.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
    userData = try? container.decodeIfPresent([String: JSONValue].self, forKey: .userData)
    indexNumber = try? container.decodeIfPresent(Int.self, forKey: .indexNumber)
    parentIndexNumber = try? container.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
    seriesName = try? container.decodeIfPresent(String.self, forKey: .seriesName)
    locationType = try? container.decodeIfPresent(String.self, forKey: .locationType)
  }

  /// 播放器和续播询问里显示的标题；剧集带上剧名和季集号。
  var displayTitle: String {
    guard type == "Episode" else { return name ?? "" }
    var parts: [String] = []
    if let seriesName, !seriesName.isEmpty { parts.append(seriesName) }
    if let season = parentIndexNumber, let episode = indexNumber {
      parts.append("第 \(season) 季 第 \(episode) 集")
    } else if let episode = indexNumber {
      parts.append("第 \(episode) 集")
    }
    if let name, !name.isEmpty { parts.append(name) }
    return parts.joined(separator: " · ")
  }

  var playbackPositionTicks: Int64 {
    switch userData?["PlaybackPositionTicks"] {
    case .int(let value): return Int64(value)
    case .double(let value): return Int64(value)
    default: return 0
    }
  }
}

nonisolated struct EmbyMediaStream: Decodable, Sendable, Equatable {
  let type: String?
  let codec: String?
  let isDefault: Bool?

  init(type: String?, codec: String?, isDefault: Bool? = nil) {
    self.type = type
    self.codec = codec
    self.isDefault = isDefault
  }

  private enum CodingKeys: String, CodingKey {
    case type = "Type"
    case codec = "Codec"
    case isDefault = "IsDefault"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    codec = try? container.decodeIfPresent(String.self, forKey: .codec)
    isDefault = try? container.decodeIfPresent(Bool.self, forKey: .isDefault)
  }
}

nonisolated struct EmbyMediaSource: Decodable, Sendable, Equatable {
  let id: String
  let container: String?
  let `protocol`: String?
  let mediaStreams: [EmbyMediaStream]

  init(id: String, container: String?, protocol: String? = "File", mediaStreams: [EmbyMediaStream]) {
    self.id = id
    self.container = container
    self.protocol = `protocol`
    self.mediaStreams = mediaStreams
  }

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case container = "Container"
    case `protocol` = "Protocol"
    case mediaStreams = "MediaStreams"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    self.container = try? container.decodeIfPresent(String.self, forKey: .container)
    self.protocol = try? container.decodeIfPresent(String.self, forKey: .protocol)
    mediaStreams =
      (try? container.decodeIfPresent([LossyDecodable<EmbyMediaStream>].self, forKey: .mediaStreams))?
      .compactMap(\.value) ?? []
  }
}

nonisolated struct EmbyPlaybackInfo: Decodable, Sendable {
  let mediaSources: [EmbyMediaSource]
  let playSessionID: String?
  let errorCode: String?

  private enum CodingKeys: String, CodingKey {
    case mediaSources = "MediaSources"
    case playSessionID = "PlaySessionId"
    case errorCode = "ErrorCode"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mediaSources =
      (try? container.decodeIfPresent([LossyDecodable<EmbyMediaSource>].self, forKey: .mediaSources))?
      .compactMap(\.value) ?? []
    playSessionID = try? container.decodeIfPresent(String.self, forKey: .playSessionID)
    errorCode = try? container.decodeIfPresent(String.self, forKey: .errorCode)
  }
}

/// Emby 列表接口的分页结构（`/Shows/{id}/Episodes` 等）。
nonisolated struct EmbyItemsPage: Decodable, Sendable {
  let items: [EmbyItem]

  private enum CodingKeys: String, CodingKey { case items = "Items" }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    items =
      (try? container.decodeIfPresent([LossyDecodable<EmbyItem>].self, forKey: .items))?
      .compactMap(\.value) ?? []
  }
}

/// 剧集“从头播放”选哪一集：跳过特别篇（第 0 季）和没有文件的缺失集，取季号、集号最小的一集。
nonisolated enum EmbyEpisodeOrder {
  static func firstEpisode(in items: [EmbyItem]) -> EmbyItem? {
    let available = items.filter {
      ($0.type == nil || $0.type == "Episode") && $0.locationType?.lowercased() != "virtual"
    }
    let regular = available.filter { ($0.parentIndexNumber ?? 1) > 0 }
    let pool = regular.isEmpty ? available : regular
    return pool.enumerated().min { lhs, rhs in
      let left = (lhs.element.parentIndexNumber ?? Int.max, lhs.element.indexNumber ?? Int.max, lhs.offset)
      let right = (rhs.element.parentIndexNumber ?? Int.max, rhs.element.indexNumber ?? Int.max, rhs.offset)
      return left < right
    }?.element
  }
}

/// 数组里单个元素坏掉时只丢弃该元素。
nonisolated private struct LossyDecodable<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
  init(from decoder: Decoder) throws {
    value = try? Value(from: decoder)
  }
}

// MARK: - 直接播放判定

/// 应用内播放只做 AVPlayer 原生直连：Emby 不转码、不重新封装。
nonisolated enum EmbyDirectPlay {
  static let containers: Set<String> = ["mp4", "m4v", "mov"]
  static let videoCodecs: Set<String> = ["h264", "avc", "hevc", "h265"]
  static let audioCodecs: Set<String> = ["aac", "ac3", "eac3", "mp3", "alac", "flac"]

  struct Selection: Equatable, Sendable {
    let source: EmbyMediaSource
    /// 流地址扩展名，帮助 AVPlayer 识别容器
    let fileExtension: String
  }

  enum Unsupported: Error, Equatable, Sendable {
    case noSource
    case remoteSource
    case container(String?)
    case videoCodec(String?)
    case audioCodec(String?)

    var message: String {
      switch self {
      case .noSource:
        return "媒体服务器没有返回可播放的文件"
      case .remoteSource:
        return "该影片是远程链接（如 strm），暂不支持应用内播放"
      case .container(let container):
        let name = container.map { $0.uppercased() } ?? "未知格式"
        return "应用内播放暂只支持 MP4/MOV，该影片为 \(name)"
      case .videoCodec(let codec):
        return "视频编码 \(codec?.uppercased() ?? "未知") 暂不支持应用内播放"
      case .audioCodec(let codec):
        return "音频编码 \(codec?.uppercased() ?? "未知") 暂不支持应用内播放"
      }
    }
  }

  /// 按服务器返回顺序选第一个能直接交给 AVPlayer 的版本；都不行时返回第一个版本的原因。
  static func select(from sources: [EmbyMediaSource]) -> Result<Selection, Unsupported> {
    var firstReason: Unsupported?
    for source in sources {
      switch evaluate(source) {
      case .success(let selection): return .success(selection)
      case .failure(let reason): if firstReason == nil { firstReason = reason }
      }
    }
    return .failure(firstReason ?? .noSource)
  }

  static func evaluate(_ source: EmbyMediaSource) -> Result<Selection, Unsupported> {
    if let sourceProtocol = source.protocol, sourceProtocol.lowercased() != "file" {
      return .failure(.remoteSource)
    }
    // Emby 可能返回 ffprobe 的格式名，例如 `mov,mp4,m4a,3gp,3g2,mj2`。
    let containerNames = (source.container ?? "")
      .lowercased()
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard containerNames.contains(where: containers.contains) else {
      return .failure(.container(source.container))
    }
    let fileExtension = containerNames.contains("mov") && !containerNames.contains("mp4") ? "mov" : "mp4"

    let videoStreams = source.mediaStreams.filter { $0.type?.lowercased() == "video" }
    guard let video = videoStreams.first(where: { $0.isDefault == true }) ?? videoStreams.first else {
      return .failure(.videoCodec(nil))
    }
    guard let videoCodec = video.codec?.lowercased(), videoCodecs.contains(videoCodec) else {
      return .failure(.videoCodec(video.codec))
    }

    let audioStreams = source.mediaStreams.filter { $0.type?.lowercased() == "audio" }
    if !audioStreams.isEmpty,
      !audioStreams.contains(where: { audioCodecs.contains($0.codec?.lowercased() ?? "") })
    {
      let preferred = audioStreams.first(where: { $0.isDefault == true }) ?? audioStreams[0]
      return .failure(.audioCodec(preferred.codec))
    }
    return .success(Selection(source: source, fileExtension: fileExtension))
  }
}

/// 续播点：太靠前或接近片尾时直接从头播放。
nonisolated enum PlaybackResumePolicy {
  static let minimumSeconds: Double = 60
  static let maximumProgress: Double = 0.9

  static func resumePosition(positionTicks: Int64, runTimeTicks: Int64?) -> Double? {
    let seconds = Double(positionTicks) / 10_000_000
    guard seconds >= minimumSeconds else { return nil }
    if let runTimeTicks, runTimeTicks > 0, Double(positionTicks) / Double(runTimeTicks) >= maximumProgress {
      return nil
    }
    return seconds
  }

  /// 播放结束位置达到时长的 90% 视为看完。
  static func isCompleted(positionSeconds: Double, runTimeTicks: Int64?) -> Bool {
    guard let runTimeTicks, runTimeTicks > 0 else { return false }
    return positionSeconds * 10_000_000 / Double(runTimeTicks) >= maximumProgress
  }

  static func formatted(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs)
      : String(format: "%d:%02d", minutes, secs)
  }
}
