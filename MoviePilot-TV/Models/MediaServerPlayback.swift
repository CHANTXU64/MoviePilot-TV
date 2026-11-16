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
  /// 反代路径和默认端口的写法不影响 TLS 连接所用的地址。
  struct Origin: Hashable, Sendable {
    let scheme: String?
    let host: String?
    let port: Int

    init(_ url: URL) {
      scheme = url.scheme?.lowercased()
      host = url.host?.lowercased()
      port = url.port ?? (scheme == "https" ? 443 : 80)
    }
  }

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

  static func isEnabledForSession(
    canRequestSuperUserEndpoints: Bool, backendVersion: String?, userEnabled: Bool
  ) -> Bool {
    canRequestSuperUserEndpoints && isEnabled(backendVersion: backendVersion, userEnabled: userEnabled)
  }

  /// 只有管理员能读取媒体服务器地址和密钥；支持电影和剧集。
  static func offers(
    mediaType: String?, canRequestSuperUserEndpoints: Bool, backendVersion: String?,
    userEnabled: Bool = PlaybackPreferences.isInAppPlaybackEnabled
  ) -> Bool {
    isEnabledForSession(
      canRequestSuperUserEndpoints: canRequestSuperUserEndpoints,
      backendVersion: backendVersion,
      userEnabled: userEnabled
    ) && (mediaType == "电影" || mediaType == "电视剧")
  }
}

/// 播放相关的本机设置（只影响 TV 端），设置页「播放」和播放界面共用。
nonisolated enum PlaybackPreferences {
  static let inAppPlaybackKey = "inAppPlaybackEnabled"
  static let defaultInAppPlaybackEnabled = true
  /// 应用内播放开关变化后发出，已打开的页面据此收起或补回播放入口。
  static let inAppPlaybackDidChangeNotification = Notification.Name("InAppPlaybackPreferenceDidChange")
  /// 自动播放变化后发出：播放界面工具栏也能改，设置页据此同步。
  static let autoPlayDidChangeNotification = Notification.Name("AutoPlayNextEpisodePreferenceDidChange")
  /// 播放界面工具栏的“自动播放”按钮读写同一个键（沿用移植 Swiftfin 时的键名）。
  static let autoPlayNextEpisodeKey = "swiftfin.enableNextEpisodeAutoPlay"

  /// 应用内播放开关，默认开。后端低于 `InAppPlaybackAvailability.minimumBackendVersion` 时不管它是什么都不提供。
  static var isInAppPlaybackEnabled: Bool {
    bool(forKey: inAppPlaybackKey, default: defaultInAppPlaybackEnabled)
  }

  static func setInAppPlaybackEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: inAppPlaybackKey)
    NotificationCenter.default.post(name: inAppPlaybackDidChangeNotification, object: nil)
  }

  /// 播完自动播下一集，默认开（与 Jellyfin/Emby 用户默认值相同）。
  static var autoPlaysNextEpisode: Bool { bool(forKey: autoPlayNextEpisodeKey, default: true) }

  static func setAutoPlaysNextEpisode(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: autoPlayNextEpisodeKey)
    NotificationCenter.default.post(name: autoPlayDidChangeNotification, object: nil)
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
  /// 服务器上这个用户已看完（标记为已播放）。详情页「继续播放」据此找接着看的那一集，见 `PlaybackEpisodeProgress.upNext`。
  let played: Bool
  /// 服务器上只有元数据、没有文件（缺失的集）时为 false。
  let hasFile: Bool
  /// 外部编号：规范来源（见 `ExternalMediaID.normalizedSource`）→ 有效编号。
  /// 剧集的单集条目上，`tmdb` 是 TMDB 单集 ID，不是剧的 ID。
  let externalIDs: [String: String]
  /// 服务器看到的文件路径；服务器没给（或这个用户看不到）时为 nil。单集对应拿它和 MoviePilot 的整理记录比。
  let path: String?
  /// 首播日期，服务器给的原样（如 `2025-01-05T00:00:00.0000000Z`）；单集对应按季号集号对上时用来核对。
  let premiereDate: String?
  /// 单集所属剧在这台服务器上的条目 ID；按剧的外部编号去 MoviePilot 取信息时用。
  let seriesID: String?
  /// 以下是服务器自己的展示信息。播放界面以 MoviePilot 的为准，MoviePilot 没有这个条目（如手动下载、认不出的资源）
  /// 或缺某一项时才用这里的（见 `PlaybackMetadata`）。
  let overview: String?
  /// 评分（0–10）
  let communityRating: Double?
  /// 分级（如 `PG-13`）
  let officialRating: String?
  /// 竖版海报；单集是所属剧的海报。图片地址不带密钥。
  let posterURL: URL?
  /// 横版图；单集是这一集的截图。
  let thumbnailURL: URL?

  init(
    id: String, kind: Kind, name: String? = nil, seriesName: String? = nil, seasonNumber: Int? = nil,
    episodeNumber: Int? = nil, episodeNumberEnd: Int? = nil, runtimeSeconds: Double? = nil,
    resumePositionSeconds: Double = 0, played: Bool = false, hasFile: Bool = true,
    externalIDs: [String: String] = [:],
    path: String? = nil, premiereDate: String? = nil, seriesID: String? = nil, overview: String? = nil,
    communityRating: Double? = nil, officialRating: String? = nil, posterURL: URL? = nil, thumbnailURL: URL? = nil
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
    self.played = played
    self.hasFile = hasFile
    self.externalIDs = externalIDs
    self.path = trimmedNonEmpty([path])
    self.premiereDate = trimmedNonEmpty([premiereDate])
    self.seriesID = trimmedNonEmpty([seriesID])
    self.overview = trimmedNonEmpty([overview])
    self.communityRating = communityRating.flatMap(PlaybackMetadata.validRating)
    self.officialRating = trimmedNonEmpty([officialRating])
    self.posterURL = posterURL
    self.thumbnailURL = thumbnailURL
  }

  /// 服务器上的展示信息，MoviePilot 没有的项用它补（见 `PlaybackMetadata.filling(_:)`）。
  var metadata: PlaybackMetadata {
    PlaybackMetadata(
      title: name, seriesName: seriesName, seasonNumber: seasonNumber, episodeNumber: episodeNumber,
      overview: overview, premiereDate: premiereDate, communityRating: communityRating, officialRating: officialRating,
      posterURL: posterURL, thumbnailURL: thumbnailURL)
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
}

/// 播放界面显示的条目信息：标题、季集号、简介、日期、评分和图片。
/// 以 MoviePilot 的为准（详情页、集列表，或按服务器条目的外部编号查到的 MoviePilot 详情）；MoviePilot 没有这个条目，
/// 或缺某一项时，用媒体服务器适配器给的（`ServerMediaItem.metadata`），不限于哪一类服务器。
nonisolated struct PlaybackMetadata: Equatable, Sendable {
  /// 电影是片名，单集是集名。
  var title: String?
  var seriesName: String?
  var seasonNumber: Int?
  var episodeNumber: Int?
  var overview: String?
  /// 电影的上映日期或单集的播出日期，以 `yyyy-MM-dd` 开头。
  var premiereDate: String?
  /// 评分（0–10）。
  var communityRating: Double?
  /// 分级，只有媒体服务器有。
  var officialRating: String?
  /// 竖版海报；单集是剧的海报。
  var posterURL: URL?
  /// 横版图；单集是这一集的剧照或截图。
  var thumbnailURL: URL?

  init(
    title: String? = nil, seriesName: String? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil,
    overview: String? = nil, premiereDate: String? = nil, communityRating: Double? = nil,
    officialRating: String? = nil, posterURL: URL? = nil, thumbnailURL: URL? = nil
  ) {
    self.title = trimmedNonEmpty([title])
    self.seriesName = trimmedNonEmpty([seriesName])
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.overview = trimmedNonEmpty([overview])
    self.premiereDate = trimmedNonEmpty([premiereDate])
    self.communityRating = communityRating.flatMap(Self.validRating)
    self.officialRating = trimmedNonEmpty([officialRating])
    self.posterURL = posterURL
    self.thumbnailURL = thumbnailURL
  }

  /// 0 分是“没有评分”（TMDB 没人打分时就是 0），不显示。
  static func validRating(_ value: Double) -> Double? {
    value.isFinite && value > 0 && value <= 10 ? value : nil
  }

  /// 逐项补齐：自己没有的项用 `fallback` 的。
  func filling(_ fallback: PlaybackMetadata) -> PlaybackMetadata {
    PlaybackMetadata(
      title: title ?? fallback.title, seriesName: seriesName ?? fallback.seriesName,
      seasonNumber: seasonNumber ?? fallback.seasonNumber, episodeNumber: episodeNumber ?? fallback.episodeNumber,
      overview: overview ?? fallback.overview, premiereDate: premiereDate ?? fallback.premiereDate,
      communityRating: communityRating ?? fallback.communityRating,
      officialRating: officialRating ?? fallback.officialRating, posterURL: posterURL ?? fallback.posterURL,
      thumbnailURL: thumbnailURL ?? fallback.thumbnailURL)
  }

  /// 播放器标题：电影只有片名；剧集主标题是「第 N 季 第 M 集 · 集名」，副标题是剧名。
  func playerTitles(isEpisode: Bool) -> (primary: String, secondary: String?) {
    guard isEpisode else { return (title ?? "", nil) }
    return PlaybackTitles.episode(
      name: title, seasonNumber: seasonNumber, episodeNumber: episodeNumber, seriesName: seriesName)
  }
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
  /// 文件里音视频和字幕轨的条数（不含外挂字幕），取自起播时已经读到的片源信息；数不准时为 nil。
  /// 播放失败时据此判断 mpv 跳过的 zlib 压缩轨道是不是包括了全部画面和声音（见 `PlaybackSession.failureMessage`）。
  let embeddedTrackCount: Int?
  /// 这个版本的片长（秒）；服务器没给时为 nil。同一条目的各版本可能长短不一（如加长版）。
  let runtimeSeconds: Double?
  /// 这个版本的章节，服务器没有时为空。播放界面怎么用见 `PlaybackChapters`。
  let chapters: [ServerChapter]

  init(
    id: String, name: String? = nil, container: String? = nil, unsupportedReason: PlaybackUnsupported? = nil,
    displayModeHint: DisplayModeHint? = nil, embeddedTrackCount: Int? = nil, runtimeSeconds: Double? = nil,
    chapters: [ServerChapter] = []
  ) {
    self.id = id
    self.name = name
    self.container = container
    self.unsupportedReason = unsupportedReason
    self.displayModeHint = displayModeHint
    self.embeddedTrackCount = embeddedTrackCount
    self.runtimeSeconds = runtimeSeconds
    self.chapters = chapters
  }

  var isDirectlyPlayable: Bool { unsupportedReason == nil }
}

/// 片源里的一个章节。
nonisolated struct ServerChapter: Equatable, Sendable {
  let name: String?
  /// 起点（秒）
  let startSeconds: Double
  /// 章节截图；服务器没生成时为 nil，播放界面显示占位图标。图片地址不带密钥。
  let imageURL: URL?

  init(name: String?, startSeconds: Double, imageURL: URL? = nil) {
    self.name = trimmedNonEmpty([name])
    self.startSeconds = startSeconds
    self.imageURL = imageURL
  }
}

/// 首页「最近添加」的卡片按下做什么（见 `PlaybackCoordinator.libraryItemLinks`）。
nonisolated enum LibraryItemLink: Equatable, Sendable {
  /// 刮到了 TMDB 编号：打开这部片的详情页。`mediaType` 是「电影」或「电视剧」。
  case detail(tmdbID: Int, mediaType: String)
  /// 没有 TMDB 编号，MoviePilot 没有它的详情：直接在应用内播放，播放界面用媒体服务器的信息。
  case libraryOnly

  /// 不是电影或整部剧时为 nil。
  init?(item: ServerMediaItem) {
    let mediaType: String
    switch item.kind {
    case .movie: mediaType = "电影"
    case .series: mediaType = "电视剧"
    case .episode, .other: return nil
    }
    if let id = MediaIdentifier.validNumericIdentifier(item.externalID(for: "tmdb").flatMap { Int($0) }) {
      self = .detail(tmdbID: id, mediaType: mediaType)
    } else {
      self = .libraryOnly
    }
  }

  var tmdbID: Int? {
    guard case .detail(let id, _) = self else { return nil }
    return id
  }
}

/// 详情页条目在服务器上应有的样子：条目类型，以及详情里已知的外部编号（TMDB、IMDb、TVDB、豆瓣、Bangumi）。
/// 详情页只拿到 MoviePilot 入库表里的条目 ID，它可能来自别的服务器，不同服务器的数字 ID 还会撞号。
nonisolated struct LibraryItemExpectation: Equatable, Sendable {
  /// 条目类型（电影 / 剧集）；MoviePilot 媒体类型无法对应时为 nil，不比类型。
  let kind: ServerMediaItem.Kind?
  /// 来源（小写，`themoviedb` 记作 `tmdb`）→ 编号；0、负数等无效编号不收（见 `ExternalMediaID.valid`）。
  let externalIDs: [String: String]
  /// 详情页的主身份来源（规范写法，如 `tmdb`），`externalIDs` 里有它的有效编号时才有。
  let primarySource: String?

  init(mediaType: String?, externalIDs: [String: String], primarySource: String? = nil) {
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
    let primary = primarySource.map(ExternalMediaID.normalizedSource)
    self.primarySource = primary.flatMap { normalized[$0] == nil ? nil : $0 }
  }

  /// 详情页：详情里的各个外部编号，加上入库查询所用的主身份（两者不一致时以有效的主身份为准）。
  init(media: MediaInfo) {
    var ids: [String: String] = [:]
    ids["tmdb"] = media.tmdb_id.map(String.init)
    ids["imdb"] = media.imdb_id
    ids["tvdb"] = media.tvdb_id.map(String.init)
    ids["douban"] = media.douban_id
    ids["bangumi"] = media.bangumi_id.map(String.init)
    var primary: String?
    if let identity = media.identity {
      let source = ExternalMediaID.normalizedSource(identity.source)
      if ExternalMediaID.valid(identity.mediaId, source: source) != nil {
        ids[source] = identity.mediaId
        primary = source
      }
    }
    self.init(mediaType: media.type, externalIDs: ids, primarySource: primary)
  }

  /// 条目是不是要播的那一个。类型不符的不是。条目带着主身份来源的编号时只看它：服务器常把次要来源刮错
  /// （比如 TVDB 匹配到了别的条目，TMDB 和 IMDb 却是对的），MoviePilot 判断入库也只比主身份。
  /// 没带主身份时，带着同来源编号却对不上的都不是；`strict`（启用了多台服务器）时还须至少有一个外部编号对得上：
  /// 别的服务器上同号的条目常常没刮削、没有编号，只看类型会播错片。详情页本来就没有外部编号时只能比类型。
  func accepts(_ item: ServerMediaItem, strict: Bool) -> Bool {
    if let kind, item.kind != kind { return false }
    if let primarySource, let expected = externalIDs[primarySource], let id = item.externalID(for: primarySource) {
      return id.caseInsensitiveCompare(expected) == .orderedSame
    }
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

/// 一部剧接着看哪一集（详情页的「继续播放」和集列表默认停的位置）。
/// 只看有文件的正片集（全是特别篇时才看特别篇），按季号、集号排：
/// 最靠后的一集看过或看了一部分的为准：看了一部分（续播点有效，见 `PlaybackResumePolicy`）就接着看它，
/// 看完了就看它后面的一集。前面集上留着的续播点不算（比如整季看完后又回头看了几分钟）。
/// 一集都没看过、或最后一集已经看完时为 nil。
nonisolated enum PlaybackEpisodeProgress {
  struct UpNext: Equatable, Sendable {
    let episode: ServerMediaItem
    /// 接着看到一半的这一集（有续播点）；false 表示上一集看完了，这一集从头看。
    let resumes: Bool
  }

  static func upNext(in items: [ServerMediaItem]) -> UpNext? {
    let slots = orderedSlots(items)
    guard let last = slots.lastIndex(where: \.isReached) else { return nil }
    if slots[last].resumable { return UpNext(episode: slots[last].item, resumes: true) }
    let next = slots.index(after: last)
    return slots.indices.contains(next) ? UpNext(episode: slots[next].item, resumes: false) : nil
  }

  /// 看完了的最靠后一集（详情页按 MoviePilot 集列表找它紧接着的下一集，核对服务器上的 `upNext` 是不是它）。
  /// 它后面还有看过一部分的集时为 nil（那时 `upNext` 接着看那一集）。
  /// 只在真正看完的文件里取：几份看完的文件范围重叠时（E01–E05 和 E02–E03）取看完范围到得最远的那一份；
  /// 没看过、只是起始集被看完的合集覆盖的文件（看完 E01–E05 后的 E02–E07）不算，免得把看完的位置推远。
  static func lastWatched(in items: [ServerMediaItem]) -> ServerMediaItem? {
    let slots = orderedSlots(items)
    guard let last = slots.lastIndex(where: \.isReached), !slots[last].resumable else { return nil }
    let reached = position(slots[last].item)
    return episodePool(items).filter { isWatched($0) && position($0) <= reached }.max { lhs, rhs in
      (lhs.seasonNumber ?? 0, lastEpisode(lhs) ?? 0) < (rhs.seasonNumber ?? 0, lastEpisode(rhs) ?? 0)
    }
  }

  /// 文件在剧里的位置（季号、起始集号），缺编号的排最后。
  private static func position(_ item: ServerMediaItem) -> (Int, Int) {
    (item.seasonNumber ?? Int.max, item.episodeNumber ?? Int.max)
  }

  private static func resumePosition(_ item: ServerMediaItem) -> Double? {
    PlaybackResumePolicy.resumePosition(positionSeconds: item.resumePositionSeconds, durationSeconds: item.runtimeSeconds)
  }

  private static func isWatched(_ item: ServerMediaItem) -> Bool {
    item.played
      || PlaybackResumePolicy.isCompleted(positionSeconds: item.resumePositionSeconds, durationSeconds: item.runtimeSeconds)
  }

  /// 文件最后包含到第几集（一个文件含多集时是 `episodeNumberEnd`）。
  private static func lastEpisode(_ item: ServerMediaItem) -> Int? {
    item.episodeNumberEnd ?? item.episodeNumber
  }

  /// 服务器上有文件的正片集里最新的一季，集列表没看过时默认显示它。
  static func latestSeason(in items: [ServerMediaItem]) -> Int? {
    items.filter { $0.kind == .episode && $0.hasFile }.compactMap(\.seasonNumber).filter { $0 > 0 }.max()
  }

  /// 一集（同一季同一个起始集号的几份文件合成一份）。
  private struct Slot {
    /// 代表这一集的文件：看完了用看完的那份（含的集最多的）；没看完用有续播点、看得最远的那份；都没看过用第一份。
    let item: ServerMediaItem
    /// 有一份文件真正看完了。
    let watched: Bool
    /// 没有哪份看完，但起始集包含在别的看完的文件里（看完 E01–E02 后单独的 E02）：接着看时跳过它，
    /// 但它自己没看过，不能拿它的结束集号算看到了哪里（见 `lastWatched`）。
    let covered: Bool
    let resumable: Bool

    /// 已经看到这里（看完、被覆盖，或看到一半）。
    var isReached: Bool { watched || covered || resumable }
  }

  /// 有文件的正片集；有季号集号齐全的正片时只用这些：缺编号的排不进顺序，混进来会被当成最后一集，
  /// 看过它就以为整部看完了，没看过又会被当成最后一集的下一集。没有编号齐全的正片时退回不排除缺编号的，
  /// 再没有时用全部（只有特别篇）。
  private static func episodePool(_ items: [ServerMediaItem]) -> [ServerMediaItem] {
    let available = items.filter { $0.kind == .episode && $0.hasFile }
    let numbered = available.filter { ($0.seasonNumber ?? 0) > 0 && $0.episodeNumber != nil }
    if !numbered.isEmpty { return numbered }
    let regular = available.filter { ($0.seasonNumber ?? 1) > 0 }
    return regular.isEmpty ? available : regular
  }

  /// 有文件的正片集按季号集号排好。先把看完的文件包含的集都记下来，再逐集判断看完、看到一半，
  /// 不让同一集的另一份文件（单独的 E02 带着旧续播点、单独的 E01 排在合集前面）盖掉合集已看完的范围。
  private static func orderedSlots(_ items: [ServerMediaItem]) -> [Slot] {
    let pool = episodePool(items)
    // 按季记看完的集号区间，不逐集展开：服务器给的结束集号异常大时也不会卡住。
    var covered: [Int: [ClosedRange<Int>]] = [:]
    for item in pool where isWatched(item) {
      guard let season = item.seasonNumber, let first = item.episodeNumber, let last = lastEpisode(item), last >= first
      else { continue }
      covered[season, default: []].append(first...last)
    }
    var keys: [String: Int] = [:]
    var groups: [[ServerMediaItem]] = []
    for item in pool {
      guard let season = item.seasonNumber, let episode = item.episodeNumber else {
        groups.append([item])
        continue
      }
      if let index = keys["\(season)|\(episode)"] {
        groups[index].append(item)
      } else {
        keys["\(season)|\(episode)"] = groups.count
        groups.append([item])
      }
    }
    let slots = groups.map { copies -> Slot in
      let first = copies[0]
      let isCovered = first.seasonNumber.flatMap { season in
        first.episodeNumber.map { episode in covered[season]?.contains { $0.contains(episode) } ?? false }
      } ?? false
      if let watched = copies.filter(isWatched).max(by: { (lastEpisode($0) ?? 0) < (lastEpisode($1) ?? 0) }) {
        return Slot(item: watched, watched: true, covered: false, resumable: false)
      }
      if isCovered { return Slot(item: first, watched: false, covered: true, resumable: false) }
      let resumable = copies.filter { resumePosition($0) != nil }
      if let resumed = resumable.max(by: { $0.resumePositionSeconds < $1.resumePositionSeconds }) {
        return Slot(item: resumed, watched: false, covered: false, resumable: true)
      }
      return Slot(item: first, watched: false, covered: false, resumable: false)
    }
    return slots.enumerated().sorted { lhs, rhs in
      let left = (lhs.element.item.seasonNumber ?? Int.max, lhs.element.item.episodeNumber ?? Int.max, lhs.offset)
      let right = (rhs.element.item.seasonNumber ?? Int.max, rhs.element.item.episodeNumber ?? Int.max, rhs.offset)
      return left < right
    }.map(\.element)
  }
}

/// 正在播放的那个文件有多长。续播点、进度条、跳转上限、跳过片头片尾、信息面板和看完判定都用它，不各取各的。
nonisolated enum PlaybackDuration {
  /// 依次取播放器读到的时长、所选片源的时长、条目的时长，跳过 nil、0、负数和非有限值；都没有时为 nil。
  /// 起播后 mpv 读到的就是正在播的文件，最准：服务器的记录可能过时（文件被洗版换成更长的版本、还没重新分析）。
  /// 起播前（算续播点时）还没有实测值，用片源的；条目的时长只对应其中一个版本，选了长短不同的版本时不准，排最后。
  static func seconds(player: Double?, source: Double?, item: Double?) -> Double? {
    [player, source, item].lazy.compactMap { $0 }.first { $0.isFinite && $0 > 0 }
  }
}

/// 播放界面的章节，依次取：
/// 1. 媒体服务器给所播片源的章节；
/// 2. 文件里内嵌、mpv 读到的章节（服务器还没分析出章节时）。要等 mpv 读完文件，之前界面先显示「正在读取」；
/// 3. 都没有时按片长每 10 分钟分一段，名字和 Emby 自动分段的一样（「章节 N」），没有截图。几个小时的片子只靠进度条很难定位。
/// 片长取 `PlaybackDuration`：起播后以 mpv 读到的为准，章节随之重算。
nonisolated enum PlaybackChapters {
  enum Resolution: Equatable {
    /// 服务器没有章节，mpv 还没读完文件。
    case waitingForPlayer
    /// 空表示不显示章节。
    case chapters([ServerChapter])
  }

  static let generatedInterval: Double = 600
  /// 最后一段不足这么长时并进前一段，免得片尾多出一个只有几秒的章节。
  static let minimumGeneratedLength: Double = 60
  /// 片长异常（文件损坏）时分出的段数没有意义，超过就不分。500 段对应 83 小时。
  static let maximumGeneratedCount = 500
  /// 起点超过这个值（约 3 年）的章节当作坏数据，片长未知时也能挡住。
  static let maximumStartSeconds: Double = 100_000_000

  /// `embedded` 为 nil 表示 mpv 还没读完文件。
  static func resolve(
    server: [ServerChapter], embedded: [ServerChapter]?, durationSeconds: Double?
  ) -> Resolution {
    let duration = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    if let chapters = usable(server, duration: duration) { return .chapters(chapters) }
    guard let embedded else { return .waitingForPlayer }
    if let chapters = usable(embedded, duration: duration) { return .chapters(chapters) }
    return .chapters(generated(duration: duration))
  }

  /// 按起点排序，去掉片尾之后的（文件换了更短的版本、服务器还没重新分析时会有）和起点重复的。
  /// 不足两个时没有可跳的位置，当作没有章节。没有名字的章节按位置叫「章节 N」。
  private static func usable(_ chapters: [ServerChapter], duration: Double?) -> [ServerChapter]? {
    let limit = min(duration ?? maximumStartSeconds, maximumStartSeconds)
    var result: [ServerChapter] = []
    for chapter in chapters.sorted(by: { $0.startSeconds < $1.startSeconds })
    where chapter.startSeconds.isFinite && chapter.startSeconds >= 0 && chapter.startSeconds < limit
      && chapter.startSeconds != result.last?.startSeconds
    {
      result.append(chapter)
    }
    guard result.count > 1 else { return nil }
    return result.enumerated().map { index, chapter in
      chapter.name == nil
        ? ServerChapter(name: name(at: index), startSeconds: chapter.startSeconds, imageURL: chapter.imageURL)
        : chapter
    }
  }

  private static func generated(duration: Double?) -> [ServerChapter] {
    guard let duration else { return [] }
    // 起点离片尾至少还有 `minimumGeneratedLength` 才成段。
    let lastStart = duration - minimumGeneratedLength
    guard lastStart >= 0 else { return [] }
    // 先按浮点数算段数：片长大到离谱时再逐段生成会卡住主线程。
    let count = (lastStart / generatedInterval).rounded(.down) + 1
    guard count > 1, count <= Double(maximumGeneratedCount) else { return [] }
    return stride(from: 0, through: lastStart, by: generatedInterval).enumerated().map {
      ServerChapter(name: name(at: $0.offset), startSeconds: $0.element)
    }
  }

  private static func name(at index: Int) -> String { "章节 \(index + 1)" }
}

/// 续播点：太靠前或接近片尾时直接从头播放。时长见 `PlaybackDuration`。
nonisolated enum PlaybackResumePolicy {
  static let minimumSeconds: Double = 60
  static let maximumProgress: Double = 0.9

  static func resumePosition(positionSeconds: Double, durationSeconds: Double?) -> Double? {
    guard positionSeconds >= minimumSeconds else { return nil }
    if let durationSeconds, durationSeconds > 0, positionSeconds / durationSeconds >= maximumProgress {
      return nil
    }
    return positionSeconds
  }

  /// 看到了哪里（0…1），画已播放进度条用：只在有有效续播点（见 `resumePosition`）且知道时长时给出，
  /// 和起播时接着播的条件一致——画了进度条的，按下就从这里接着播。
  static func progressFraction(positionSeconds: Double, durationSeconds: Double?) -> Double? {
    guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0,
      let position = resumePosition(positionSeconds: positionSeconds, durationSeconds: durationSeconds)
    else { return nil }
    return min(1, max(0, position / durationSeconds))
  }

  /// 播放结束位置达到时长的 90% 视为看完；没有时长就不算看完。
  static func isCompleted(positionSeconds: Double, durationSeconds: Double?) -> Bool {
    guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return false }
    return positionSeconds / durationSeconds >= maximumProgress
  }
}
