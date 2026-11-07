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

/// 应用内播放入口的统一判断，首页和详情页共用；单台服务器能否播放见 `MediaServerConf.supportsInAppPlayback`。
nonisolated enum InAppPlaybackAvailability {
  /// 只有管理员能读取 Emby 地址和密钥；目前支持电影和剧集（剧集从第一集开始）。
  static func offers(mediaType: String?, canRequestSuperUserEndpoints: Bool) -> Bool {
    canRequestSuperUserEndpoints && (mediaType == "电影" || mediaType == "电视剧")
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
  /// 原样保留的用户数据（续播位置等）。剧集列表里的 `PlayCount` 恒为 0，停播写回以重新读取的单条条目为准
  /// （见 `PlaybackSession.finishItem`）。
  let userData: [String: JSONValue]?
  /// 剧集：集号、季号、剧名
  let indexNumber: Int?
  let parentIndexNumber: Int?
  let seriesName: String?
  /// `Virtual` 表示 Emby 只有元数据、没有文件（缺失的集）。
  let locationType: String?
  /// 外部编号，如 `{"Tmdb": "12345", "Imdb": "tt…"}`。MoviePilot 同步媒体库时读的就是它。
  let providerIDs: [String: String]?

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
    case providerIDs = "ProviderIds"
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
    providerIDs = try? container.decodeIfPresent([String: String].self, forKey: .providerIDs)
  }

  /// 指定来源（MoviePilot 的 `tmdb`、`douban` 等）的外部编号；键名不区分大小写，也认 `tmdb_id` 这种写法
  /// （与 MoviePilot `MediaServerIdentityHelper` 读取 ProviderIds 的规则一致）。没有或无效时返回 nil，
  /// 有效值的规则见 `ExternalMediaID.valid`。
  func providerID(for source: String) -> String? {
    let source = ExternalMediaID.normalizedSource(source)
    let value = providerIDs?.first { key, _ in
      let key = key.lowercased()
      return key == source || key == source + "_id"
    }?.value
    return ExternalMediaID.valid(value, source: source)
  }

  /// 播放器标题：电影只有片名；剧集主标题是「第 N 季 第 M 集 · 集名」，副标题是剧名。
  /// 集名只是「第 M 集」「Episode M」这类占位时省略，避免重复。
  var playerTitles: (primary: String, secondary: String?) {
    guard type == "Episode" else { return (name ?? "", nil) }
    var parts: [String] = []
    if let season = parentIndexNumber, let episode = indexNumber {
      parts.append("第 \(season) 季 第 \(episode) 集")
    } else if let episode = indexNumber {
      parts.append("第 \(episode) 集")
    }
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
      parts.isEmpty || !Self.isPlaceholderEpisodeName(name, episodeNumber: indexNumber)
    {
      parts.append(name)
    }
    return (parts.joined(separator: " · "), trimmedNonEmpty([seriesName]))
  }

  /// 续播询问等单行场景用的完整标题。
  var displayTitle: String {
    let titles = playerTitles
    return [titles.secondary, titles.primary]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  /// 「第1集」「第一集」「第 1 话」「Episode 1」「EP01」「E1」这类没有信息量的集名。
  /// 纯数字只在等于本集集号时算占位（如第 3 集叫「3」「03」），「1984」这类真实集名保留。
  static func isPlaceholderEpisodeName(_ name: String, episodeNumber: Int?) -> Bool {
    let compact = name.replacingOccurrences(of: " ", with: "")
    if compact.allSatisfy(\.isASCII), compact.allSatisfy(\.isNumber), !compact.isEmpty {
      return episodeNumber != nil && Int(compact) == episodeNumber
    }
    let patterns = [
      #"^第[0-9一二三四五六七八九十百零〇两]+[集话話]$"#,
      #"^(?i)(episode|ep|e)\.?0*[0-9]+$"#,
    ]
    return patterns.contains { compact.range(of: $0, options: .regularExpression) != nil }
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
  /// 以下只有视频流有，开播前向电视申请显示模式用（见 `DisplayModeHint`）。
  var width: Int?
  var height: Int?
  /// Emby 读到的帧率，如 23.976025。
  var frameRate: Double?
  /// `SDR`、`HDR 10`、`HLG`、`DolbyVision` 等。
  var videoRange: String?
  /// `Hdr10`、`Hdr10Plus`、`HyperLogGamma`、`DolbyVision` 等。
  var extendedVideoType: String?
  /// 杜比视界的配置，如 `DoviProfile50`、`DoviProfile81`。
  var extendedVideoSubType: String?

  init(type: String?, codec: String?, isDefault: Bool? = nil) {
    self.type = type
    self.codec = codec
    self.isDefault = isDefault
  }

  private enum CodingKeys: String, CodingKey {
    case type = "Type"
    case codec = "Codec"
    case isDefault = "IsDefault"
    case width = "Width"
    case height = "Height"
    case realFrameRate = "RealFrameRate"
    case averageFrameRate = "AverageFrameRate"
    case videoRange = "VideoRange"
    case extendedVideoType = "ExtendedVideoType"
    case extendedVideoSubType = "ExtendedVideoSubType"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    codec = try? container.decodeIfPresent(String.self, forKey: .codec)
    isDefault = try? container.decodeIfPresent(Bool.self, forKey: .isDefault)
    width = try? container.decodeIfPresent(Int.self, forKey: .width)
    height = try? container.decodeIfPresent(Int.self, forKey: .height)
    frameRate =
      (try? container.decodeIfPresent(Double.self, forKey: .realFrameRate))
      ?? (try? container.decodeIfPresent(Double.self, forKey: .averageFrameRate))
    videoRange = try? container.decodeIfPresent(String.self, forKey: .videoRange)
    extendedVideoType = try? container.decodeIfPresent(String.self, forKey: .extendedVideoType)
    extendedVideoSubType = try? container.decodeIfPresent(String.self, forKey: .extendedVideoSubType)
  }
}

nonisolated struct EmbyMediaSource: Decodable, Sendable, Equatable {
  let id: String
  /// 版本名（如「4K HDR」「1080p」），播放设置里的版本选择用它。
  let name: String?
  let container: String?
  let `protocol`: String?
  let mediaStreams: [EmbyMediaStream]
  init(
    id: String, name: String? = nil, container: String?, protocol: String? = "File", mediaStreams: [EmbyMediaStream]
  ) {
    self.id = id
    self.name = name
    self.container = container
    self.protocol = `protocol`
    self.mediaStreams = mediaStreams
  }

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case container = "Container"
    case `protocol` = "Protocol"
    case mediaStreams = "MediaStreams"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
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

/// 外部编号（TMDB、IMDb、TVDB、豆瓣、Bangumi）的来源名与有效值，详情页和 Emby 条目两边按同一规则读取。
nonisolated enum ExternalMediaID {
  /// 来源名小写，`themoviedb` 记作 `tmdb`。
  static func normalizedSource(_ source: String) -> String {
    let source = source.lowercased()
    return source == "themoviedb" ? "tmdb" : source
  }

  /// `source` 须已经过 `normalizedSource`。去掉首尾空白；空值和 `0` 无效，数字来源只认正整数
  /// （同 `MediaIdentifier.validNumericIdentifier`）。无效时返回 nil，按没有这个编号处理，不拿去比对或搜索。
  static func valid(_ value: String?, source: String) -> String? {
    guard let value = MediaIdentifier.truthySourceIdentifier(value) else { return nil }
    guard numericSources.contains(source) else { return value }
    return MediaIdentifier.validNumericIdentifier(Int(value)).map(String.init)
  }

  private static let numericSources: Set<String> = ["tmdb", "tvdb", "bangumi", "anilist"]
}

/// 详情页条目在服务器上应有的样子：Emby 条目类型，以及详情里已知的外部编号（TMDB、IMDb、TVDB、豆瓣、Bangumi）。
/// 详情页只拿到 MoviePilot 入库表里不带服务器名的条目 ID，它可能来自别的服务器，不同服务器的数字 ID 还会撞号。
nonisolated struct LibraryItemExpectation: Equatable, Sendable {
  /// Emby 条目类型（`Movie` / `Series`）；MoviePilot 媒体类型无法对应时为 nil，不比类型。
  let type: String?
  /// 来源（小写，`themoviedb` 记作 `tmdb`）→ 编号；0、负数等无效编号不收（见 `ExternalMediaID.valid`）。
  let externalIDs: [String: String]

  init(mediaType: String?, externalIDs: [String: String]) {
    switch mediaType {
    case "电影": type = "Movie"
    case "电视剧": type = "Series"
    default: type = nil
    }
    var normalized: [String: String] = [:]
    for (source, value) in externalIDs {
      let source = ExternalMediaID.normalizedSource(source)
      guard let value = ExternalMediaID.valid(value, source: source) else { continue }
      normalized[source] = value
    }
    self.externalIDs = normalized
  }

  /// 详情页：详情里的各个外部编号，加上入库查询所用的主身份（两者不一致时以有效的主身份为准）。
  init(media: MediaInfo) {
    var ids: [String: String] = [:]
    ids["tmdb"] = media.tmdb_id.map(String.init)
    ids["imdb"] = media.imdb_id
    ids["tvdb"] = media.tvdb_id.map(String.init)
    ids["douban"] = media.douban_id
    ids["bangumi"] = media.bangumi_id.map(String.init)
    if let identity = media.identity {
      let source = ExternalMediaID.normalizedSource(identity.source)
      if ExternalMediaID.valid(identity.mediaId, source: source) != nil { ids[source] = identity.mediaId }
    }
    self.init(mediaType: media.type, externalIDs: ids)
  }

  /// 条目是不是要播的那一个。类型不符，或带着同来源编号却对不上的，都不是。
  /// `strict`（启用了多台服务器）时还须至少有一个外部编号对得上：别的服务器上同号的条目常常没刮削、没有编号，
  /// 只看类型会播错片。详情页本来就没有外部编号时只能比类型。
  func accepts(_ item: EmbyItem, strict: Bool) -> Bool {
    if let type, item.type != type { return false }
    var matched = false
    for (source, value) in externalIDs {
      guard let id = item.providerID(for: source) else { continue }
      guard id.caseInsensitiveCompare(value) == .orderedSame else { return false }
      matched = true
    }
    return matched || !strict || externalIDs.isEmpty
  }

  /// 按外部编号搜索用的参数（Emby `AnyProviderIdEquals`，如 `tmdb.12345`），只取 Emby 自带刮削器会写的来源。
  var providerSearchKeys: [String] {
    ["tmdb", "imdb", "tvdb"].compactMap { source in externalIDs[source].map { "\(source).\($0)" } }
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

/// 应用内播放都直连原文件，Emby 不转码、不重新封装，统一由 mpv 播放。
nonisolated enum EmbyDirectPlay {
  struct Selection: Equatable, Sendable {
    let source: EmbyMediaSource
    /// 流地址扩展名，帮助播放器识别容器
    let fileExtension: String
  }

  enum Unsupported: Error, Equatable, Sendable {
    case noSource
    case remoteSource

    var message: String {
      switch self {
      case .noSource:
        return "媒体服务器没有返回可播放的文件"
      case .remoteSource:
        return "该影片是远程链接（如 strm），暂不支持应用内播放"
      }
    }
  }

  /// 取第一个本地文件版本。
  static func select(from sources: [EmbyMediaSource]) -> Result<Selection, Unsupported> {
    var firstReason: Unsupported?
    for source in sources {
      switch evaluate(source) {
      case .success(let selection):
        return .success(selection)
      case .failure(let reason):
        if firstReason == nil { firstReason = reason }
      }
    }
    return .failure(firstReason ?? .noSource)
  }

  static func evaluate(_ source: EmbyMediaSource) -> Result<Selection, Unsupported> {
    if let sourceProtocol = source.protocol, sourceProtocol.lowercased() != "file" {
      return .failure(.remoteSource)
    }
    // Emby 可能返回 ffprobe 的格式名，例如 `mov,mp4,m4a,3gp,3g2,mj2`、`matroska,webm`。
    let containerNames = (source.container ?? "")
      .lowercased()
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return .success(Selection(source: source, fileExtension: fileExtension(containerNames)))
  }

  private static func fileExtension(_ containerNames: [String]) -> String {
    if containerNames.contains(where: { $0 == "matroska" || $0 == "mkv" }) { return "mkv" }
    if containerNames.contains("mp4") { return "mp4" }
    let candidate = containerNames.first ?? ""
    let allowed = CharacterSet.alphanumerics
    guard !candidate.isEmpty, candidate.unicodeScalars.allSatisfy(allowed.contains) else {
      return "mkv"
    }
    return candidate
  }
}

/// Emby 的时间单位 tick 为 100 纳秒。
nonisolated enum EmbyTicks {
  static let perSecond: Double = 10_000_000

  static func from(seconds: Double) -> Int { Int(seconds * perSecond) }
  static func seconds(_ ticks: Int64) -> Double { Double(ticks) / perSecond }
}

/// 续播点：太靠前或接近片尾时直接从头播放。
nonisolated enum PlaybackResumePolicy {
  static let minimumSeconds: Double = 60
  static let maximumProgress: Double = 0.9

  static func resumePosition(positionTicks: Int64, runTimeTicks: Int64?) -> Double? {
    let seconds = EmbyTicks.seconds(positionTicks)
    guard seconds >= minimumSeconds else { return nil }
    if let runTimeTicks, runTimeTicks > 0, Double(positionTicks) / Double(runTimeTicks) >= maximumProgress {
      return nil
    }
    return seconds
  }

  /// 播放结束位置达到时长的 90% 视为看完。
  static func isCompleted(positionSeconds: Double, runTimeTicks: Int64?) -> Bool {
    guard let runTimeTicks, runTimeTicks > 0 else { return false }
    return positionSeconds / EmbyTicks.seconds(runTimeTicks) >= maximumProgress
  }
}
