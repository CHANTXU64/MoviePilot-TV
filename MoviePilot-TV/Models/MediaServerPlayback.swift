import Foundation

// 应用内播放与具体媒体服务器无关的部分：连接配置、入口条件，以及协调器、播放会话和播放界面使用的条目、片源模型。
// 各类服务器（目前是 Emby）在各自的适配器里把接口数据转换成这里的类型，见 `MediaServerConnection`。

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
      guard let url = MediaServerBaseURL.normalized(raw), !result.contains(url) else { continue }
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

/// 媒体服务器根地址：补全协议、去掉结尾斜杠，保留反代路径前缀（与 MoviePilot `standardize_base_url` 一致，缺协议按 http）。
nonisolated enum MediaServerBaseURL {
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

/// 直连媒体服务器共用的网络会话：不缓存、不存 Cookie，单个请求最多等 15 秒。
nonisolated enum MediaServerHTTP {
  /// 探测地址、用缓存连接发出的第一个请求所用的超时：地址失效时尽快改用其他地址，不等普通请求的 15 秒。
  static let quickTimeout: TimeInterval = 3
  /// 内网、外网地址都连通时，排在前面的（内网）可以晚到这么久仍被选中（见 `PreferredReachability`）。
  static let preferredAddressGrace: Duration = .milliseconds(500)

  static let sharedSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = 15
    return URLSession(configuration: configuration)
  }()
}

/// 播放相关日志去掉地址和密钥：mpv 等组件的错误信息可能带出含密钥的流地址。
nonisolated enum PlaybackLog {
  static func redacted(_ text: String) -> String {
    text
      .replacingOccurrences(
        of: #"(?i)\b(?:https?|rtsp|rtmp|ftp|file)://[^\s]+"#, with: "<URL>", options: .regularExpression)
      .replacingOccurrences(
        of: #"api_key=[^&\s"']*"#, with: "api_key=<redacted>", options: .regularExpression)
  }
}

/// 应用内播放入口的统一判断，首页和详情页共用；单台服务器能否播放见 `MediaServerConf.supportsInAppPlayback`。
nonisolated enum InAppPlaybackAvailability {
  /// 应用内播放从 MoviePilot v3.2.6 起开放：按集播放依赖这个版本起季集列表返回的 TMDB 单集 ID，
  /// 入库查询返回条目所属服务器也从这个版本起才有。
  /// 极性属于「新行为版本限制」：低于该版本、读不出或无法解析时不提供，设置里也打不开；可解析且不低于该版本（含热修复）时
  /// 默认提供，用户可以在设置里关掉（`PlaybackPreferences.isInAppPlaybackEnabled`）。
  static let minimumBackendVersion = "v3.2.6"

  static func supports(backendVersion: String?) -> Bool {
    BackendVersionGate.isAvailable(since: minimumBackendVersion, backendVersion: backendVersion)
  }

  /// 后端支持且用户没在设置里关掉。
  static func isEnabled(backendVersion: String?, userEnabled: Bool) -> Bool {
    userEnabled && supports(backendVersion: backendVersion)
  }

  /// 只有管理员能读取媒体服务器地址和密钥；支持电影和剧集。
  static func offers(
    mediaType: String?, canRequestSuperUserEndpoints: Bool, backendVersion: String?,
    userEnabled: Bool = PlaybackPreferences.isInAppPlaybackEnabled
  ) -> Bool {
    canRequestSuperUserEndpoints && isEnabled(backendVersion: backendVersion, userEnabled: userEnabled)
      && (mediaType == "电影" || mediaType == "电视剧")
  }
}

/// 播放相关的本机设置（只影响 TV 端），设置页「播放」和播放界面共用。
nonisolated enum PlaybackPreferences {
  static let inAppPlaybackKey = "inAppPlaybackEnabled"
  /// 应用内播放开关变化后发出，已打开的页面据此收起或补回播放入口。
  static let didChangeNotification = Notification.Name("PlaybackPreferencesDidChange")
  /// 播放界面工具栏的“自动播放”按钮读写同一个键（沿用移植 Swiftfin 时的键名）。
  static let autoPlayNextEpisodeKey = "swiftfin.enableNextEpisodeAutoPlay"

  /// 应用内播放开关，默认开。后端低于 `InAppPlaybackAvailability.minimumBackendVersion` 时不管它是什么都不提供。
  static var isInAppPlaybackEnabled: Bool { bool(forKey: inAppPlaybackKey, default: true) }

  static func setInAppPlaybackEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: inAppPlaybackKey)
    NotificationCenter.default.post(name: didChangeNotification, object: nil)
  }

  /// 播完自动播下一集，默认开（与 Jellyfin/Emby 用户默认值相同）。
  static var autoPlaysNextEpisode: Bool { bool(forKey: autoPlayNextEpisodeKey, default: true) }

  static func setAutoPlaysNextEpisode(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: autoPlayNextEpisodeKey)
  }

  private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
  }
}

/// 外部编号（TMDB、IMDb、TVDB、豆瓣、Bangumi）的来源名与有效值，详情页和服务器条目两边按同一规则读取。
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

  /// 服务器条目的外部编号表（如 Emby 的 `ProviderIds`）转成「规范来源 → 有效编号」。键名不区分大小写，
  /// 也认 `tmdb_id` 这种写法（与 MoviePilot `MediaServerIdentityHelper` 读取 ProviderIds 的规则一致）；
  /// 同一来源两种写法都有时以不带 `_id` 的为准。无效编号不收。
  static func normalizedTable(_ raw: [String: String]?) -> [String: String] {
    var exact: [String: String] = [:]
    var suffixed: [String: String] = [:]
    for (key, value) in raw ?? [:] {
      let key = key.lowercased()
      if key.hasSuffix("_id") {
        let source = normalizedSource(String(key.dropLast(3)))
        if let value = valid(value, source: source) { suffixed[source] = value }
      } else {
        let source = normalizedSource(key)
        if let value = valid(value, source: source) { exact[source] = value }
      }
    }
    return suffixed.merging(exact) { _, exact in exact }
  }

  private static let numericSources: Set<String> = ["tmdb", "tvdb", "bangumi", "anilist"]
}

// MARK: - 服务器条目与片源

/// 媒体服务器上的一个条目。各类服务器的接口数据都转换成它，协调器和播放界面只认这个类型。
nonisolated struct ServerMediaItem: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case movie, series, episode, other
  }

  /// 服务器自己的条目 ID
  let id: String
  let kind: Kind
  let name: String?
  /// 剧集所属剧名
  let seriesName: String?
  /// 服务器上的季号、集号（来自文件名或 NFO，不一定是 MoviePilot 详情页显示的编号）。
  /// 一个文件包含多集时，`episodeNumberEnd` 是其中最后一集。
  let seasonNumber: Int?
  let episodeNumber: Int?
  let episodeNumberEnd: Int?
  /// 片长（秒）；服务器还没分析出时为 nil。
  let runtimeSeconds: Double?
  /// 服务器记录的续播位置（秒），没有时为 0。
  let resumePositionSeconds: Double
  /// 服务器上只有元数据、没有文件（缺失的集）时为 false。
  let hasFile: Bool
  /// 外部编号：规范来源（见 `ExternalMediaID.normalizedSource`）→ 有效编号。
  /// 剧集的单集条目上，`tmdb` 是 TMDB 单集 ID，不是剧的 ID。
  let externalIDs: [String: String]

  init(
    id: String, kind: Kind, name: String? = nil, seriesName: String? = nil, seasonNumber: Int? = nil,
    episodeNumber: Int? = nil, episodeNumberEnd: Int? = nil, runtimeSeconds: Double? = nil,
    resumePositionSeconds: Double = 0, hasFile: Bool = true, externalIDs: [String: String] = [:]
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.seriesName = seriesName
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.episodeNumberEnd = episodeNumberEnd
    self.runtimeSeconds = runtimeSeconds
    self.resumePositionSeconds = resumePositionSeconds
    self.hasFile = hasFile
    self.externalIDs = externalIDs
  }

  /// 指定来源的外部编号，没有或无效时为 nil。
  func externalID(for source: String) -> String? {
    externalIDs[ExternalMediaID.normalizedSource(source)]
  }

  /// 单集条目上的 TMDB 单集 ID。
  var tmdbEpisodeID: Int? {
    guard kind == .episode else { return nil }
    return externalIDs["tmdb"].flatMap(Int.init)
  }

  /// 播放器标题：电影只有片名；剧集主标题是「第 N 季 第 M 集 · 集名」，副标题是剧名。
  var playerTitles: (primary: String, secondary: String?) {
    guard kind == .episode else { return (name ?? "", nil) }
    return PlaybackTitles.episode(
      name: name, seasonNumber: seasonNumber, episodeNumber: episodeNumber, seriesName: seriesName)
  }

  /// 续播询问等单行场景用的完整标题。
  var displayTitle: String { PlaybackTitles.singleLine(playerTitles) }
}

/// 剧集标题的拼法，服务器条目和 MoviePilot 集列表共用。
nonisolated enum PlaybackTitles {
  /// 主标题是「第 N 季 第 M 集 · 集名」，副标题是剧名。集名只是「第 M 集」「Episode M」这类占位时省略，避免重复。
  static func episode(
    name: String?, seasonNumber: Int?, episodeNumber: Int?, seriesName: String?
  ) -> (primary: String, secondary: String?) {
    var parts: [String] = []
    if let season = seasonNumber, let episode = episodeNumber {
      parts.append("第 \(season) 季 第 \(episode) 集")
    } else if let episode = episodeNumber {
      parts.append("第 \(episode) 集")
    }
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
      parts.isEmpty || !isPlaceholderEpisodeName(name, episodeNumber: episodeNumber)
    {
      parts.append(name)
    }
    return (parts.joined(separator: " · "), trimmedNonEmpty([seriesName]))
  }

  static func singleLine(_ titles: (primary: String, secondary: String?)) -> String {
    [titles.secondary, titles.primary]
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
}

/// 不能直连原文件的原因。
nonisolated enum PlaybackUnsupported: Error, Equatable, Sendable {
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

/// 条目的一个版本（片源）。
nonisolated struct ServerMediaSource: Equatable, Sendable, Identifiable {
  let id: String
  /// 版本名（如「4K HDR」「1080p」），播放设置里的版本选择用它。
  let name: String?
  let container: String?
  /// 不能直连原文件的原因；nil 表示可以直连。
  let unsupportedReason: PlaybackUnsupported?
  /// 开了「匹配内容」时开播前向电视申请的显示模式；读不准片源格式时为 nil，交给 MPVUI 开播后自己申请。
  let displayModeHint: DisplayModeHint?

  init(
    id: String, name: String? = nil, container: String? = nil, unsupportedReason: PlaybackUnsupported? = nil,
    displayModeHint: DisplayModeHint? = nil
  ) {
    self.id = id
    self.name = name
    self.container = container
    self.unsupportedReason = unsupportedReason
    self.displayModeHint = displayModeHint
  }

  var isDirectlyPlayable: Bool { unsupportedReason == nil }
}

/// 详情页条目在服务器上应有的样子：条目类型，以及详情里已知的外部编号（TMDB、IMDb、TVDB、豆瓣、Bangumi）。
/// 详情页只拿到 MoviePilot 入库表里的条目 ID，它可能来自别的服务器，不同服务器的数字 ID 还会撞号。
nonisolated struct LibraryItemExpectation: Equatable, Sendable {
  /// 条目类型（电影 / 剧集）；MoviePilot 媒体类型无法对应时为 nil，不比类型。
  let kind: ServerMediaItem.Kind?
  /// 来源（小写，`themoviedb` 记作 `tmdb`）→ 编号；0、负数等无效编号不收（见 `ExternalMediaID.valid`）。
  let externalIDs: [String: String]

  init(mediaType: String?, externalIDs: [String: String]) {
    switch mediaType {
    case "电影": kind = .movie
    case "电视剧": kind = .series
    default: kind = nil
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
  func accepts(_ item: ServerMediaItem, strict: Bool) -> Bool {
    if let kind, item.kind != kind { return false }
    var matched = false
    for (source, value) in externalIDs {
      guard let id = item.externalID(for: source) else { continue }
      guard id.caseInsensitiveCompare(value) == .orderedSame else { return false }
      matched = true
    }
    return matched || !strict || externalIDs.isEmpty
  }
}

/// 剧集“从头播放”选哪一集：跳过特别篇（第 0 季）和没有文件的缺失集，取季号、集号最小的一集。
nonisolated enum PlaybackEpisodeOrder {
  static func firstEpisode(in items: [ServerMediaItem]) -> ServerMediaItem? {
    let available = items.filter { $0.kind == .episode && $0.hasFile }
    let regular = available.filter { ($0.seasonNumber ?? 1) > 0 }
    let pool = regular.isEmpty ? available : regular
    return pool.enumerated().min { lhs, rhs in
      let left = (lhs.element.seasonNumber ?? Int.max, lhs.element.episodeNumber ?? Int.max, lhs.offset)
      let right = (rhs.element.seasonNumber ?? Int.max, rhs.element.episodeNumber ?? Int.max, rhs.offset)
      return left < right
    }?.element
  }
}

/// 续播点：太靠前或接近片尾时直接从头播放。
nonisolated enum PlaybackResumePolicy {
  static let minimumSeconds: Double = 60
  static let maximumProgress: Double = 0.9

  static func resumePosition(positionSeconds: Double, runtimeSeconds: Double?) -> Double? {
    guard positionSeconds >= minimumSeconds else { return nil }
    if let runtimeSeconds, runtimeSeconds > 0, positionSeconds / runtimeSeconds >= maximumProgress {
      return nil
    }
    return positionSeconds
  }

  /// 播放结束位置达到时长的 90% 视为看完。时长以服务器记录为准；服务器还没有（刚入库、未分析完）时用播放器读到的时长，
  /// 两者都没有就不算看完。
  static func isCompleted(positionSeconds: Double, runtimeSeconds: Double?, playerDurationSeconds: Double?) -> Bool {
    let duration: Double
    if let runtimeSeconds, runtimeSeconds > 0 {
      duration = runtimeSeconds
    } else if let playerDurationSeconds, playerDurationSeconds.isFinite, playerDurationSeconds > 0 {
      duration = playerDurationSeconds
    } else {
      return false
    }
    return positionSeconds / duration >= maximumProgress
  }
}
