import Foundation

// 按集播放：集列表来自 MoviePilot（TMDB 数据），到媒体服务器上找这一集的文件。
// 集以 TMDB 单集 ID 为身份（MoviePilot 的集列表从 v3.2.6 起带这个 ID）；服务器文件怎么对应到它见 `EpisodeMatching.swift`。

// MARK: - MoviePilot 集列表

/// MoviePilot `GET /api/v1/tmdb/{tmdbid}/{season}` 返回的一集（后端 `TmdbEpisode`）。单个字段坏掉不影响整集。
nonisolated struct TmdbEpisode: Decodable, Equatable, Sendable {
  /// TMDB 单集 ID（v3.2.6 起返回）。选了剧集组时 `episodeNumber` 被重排为组内序号，这个 ID 仍指向原来那一集。
  let id: Int?
  let episodeNumber: Int?
  /// TMDB 原季号。选了剧集组时不是详情页显示的季号，显示和定位都不能用它。
  let seasonNumber: Int?
  let name: String?
  let overview: String?
  let stillPath: String?
  let airDate: String?
  /// 单集时长（分钟）
  let runtime: Int?
  /// TMDB 评分（0–10），没人打分时是 0。
  let voteAverage: Double?

  init(
    id: Int?, episodeNumber: Int?, seasonNumber: Int? = nil, name: String? = nil, overview: String? = nil,
    stillPath: String? = nil, airDate: String? = nil, runtime: Int? = nil, voteAverage: Double? = nil
  ) {
    self.id = id
    self.episodeNumber = episodeNumber
    self.seasonNumber = seasonNumber
    self.name = name
    self.overview = overview
    self.stillPath = stillPath
    self.airDate = airDate
    self.runtime = runtime
    self.voteAverage = voteAverage
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case episodeNumber = "episode_number"
    case seasonNumber = "season_number"
    case name, overview
    case stillPath = "still_path"
    case airDate = "air_date"
    case runtime
    case voteAverage = "vote_average"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // 0、负数不是有效的 TMDB ID，按没有处理。
    id = MediaIdentifier.validNumericIdentifier(try? container.decodeIfPresent(Int.self, forKey: .id))
    episodeNumber = try? container.decodeIfPresent(Int.self, forKey: .episodeNumber)
    seasonNumber = try? container.decodeIfPresent(Int.self, forKey: .seasonNumber)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    overview = try? container.decodeIfPresent(String.self, forKey: .overview)
    stillPath = try? container.decodeIfPresent(String.self, forKey: .stillPath)
    airDate = try? container.decodeIfPresent(String.self, forKey: .airDate)
    runtime = try? container.decodeIfPresent(Int.self, forKey: .runtime)
    voteAverage = try? container.decodeIfPresent(Double.self, forKey: .voteAverage)
  }
}

/// 详情页集列表里的一集，编号按详情页显示的来。
nonisolated struct MoviePilotEpisode: Equatable, Sendable, Identifiable {
  /// 显示用的季号：默认顺序是 TMDB 季号；剧集组是请求时用的组内季号，不是返回里的 `season_number`。
  let seasonNumber: Int
  /// 显示用的集号；剧集组下是组内序号。
  let episodeNumber: Int?
  /// TMDB 单集 ID。缺失时无法在媒体服务器上确认是哪一集，不提供单集播放。
  let tmdbEpisodeID: Int?
  let name: String?
  let overview: String?
  let stillPath: String?
  let airDate: String?
  /// 时长（分钟）：TMDB 给的；详情页显示时 TMDB 没有，会用服务器上文件的时长补上（见 `fillingRuntime`）。
  private(set) var runtimeMinutes: Int?
  let voteAverage: Double?
  /// 在本季列表里的位置
  let index: Int

  var id: String { "\(seasonNumber)-\(index)" }

  /// `season` 是请求集列表时用的季号（剧集组下是组内季号）。
  init(_ episode: TmdbEpisode, season: Int, index: Int) {
    seasonNumber = season
    episodeNumber = episode.episodeNumber
    tmdbEpisodeID = episode.id
    name = episode.name
    overview = episode.overview
    stillPath = episode.stillPath
    airDate = episode.airDate
    runtimeMinutes = episode.runtime
    voteAverage = episode.voteAverage
    self.index = index
  }

  /// 详情页显示用：TMDB 没给时长（新番、长篇动画后面的集常这样）时，用服务器上这一集文件的时长补上。
  /// TMDB 有时长时以 TMDB 为准。
  func fillingRuntime(serverSeconds: Double?) -> MoviePilotEpisode {
    guard (runtimeMinutes ?? 0) <= 0, let serverSeconds, serverSeconds >= 30 else { return self }
    var episode = self
    episode.runtimeMinutes = max(1, Int((serverSeconds / 60).rounded()))
    return episode
  }

  static func list(_ episodes: [TmdbEpisode], season: Int) -> [MoviePilotEpisode] {
    episodes.enumerated().map { MoviePilotEpisode($1, season: season, index: $0) }
  }

  /// 播放界面显示的这一集：编号与详情页一致。剧照地址依赖当前图片设置，由调用方换算好传入。
  func playbackMetadata(seriesName: String?, stillURL: URL?) -> PlaybackMetadata {
    PlaybackMetadata(
      title: name, seriesName: seriesName, seasonNumber: seasonNumber, episodeNumber: episodeNumber,
      overview: overview, premiereDate: airDate, communityRating: voteAverage, thumbnailURL: stillURL)
  }
}

// MARK: - 按集播放的上下文

/// MoviePilot 入库查询给的整剧条目。条目 ID 只在所属服务器内唯一；旧缓存可能没有服务器名。
nonisolated struct MediaServerItemRef: Hashable, Codable, Sendable {
  let itemID: String
  let server: String?
}

/// 详情页集列表的按集播放和试看：电视剧在应用内播放可用（管理员、后端版本支持、设置里没关、有能播放的服务器）时才有。
/// `libraryItem` 是 MoviePilot 入库查询给的整剧条目，这部剧不在媒体库里时为 nil（每集都不在，可以试看）。
nonisolated struct EpisodePlaybackSource: Hashable, Codable, Sendable {
  let libraryItem: MediaServerItemRef?

  /// `episodeGroup` 是详情页当前的剧集组（nil 为默认顺序），`seasons` 是详情页的季顺序（剧集组下是组内季号）。
  func context(media: MediaInfo, episodeGroup: String?, seasons: [Int]) -> EpisodePlaybackContext? {
    EpisodePlaybackContext(media: media, episodeGroup: episodeGroup, seasons: seasons, libraryItem: libraryItem)
  }
}

/// 按集播放的冻结上下文：开播时确定，之后详情页切换剧集组、刷新季列表都不影响正在播的队列。
nonisolated struct EpisodePlaybackContext: Equatable, Sendable {
  let tmdbID: Int
  /// 剧集组 ID；nil 是 TMDB 默认顺序。
  let episodeGroup: String?
  /// 详情页的季顺序（剧集组下是组内季号），上一集、下一集跨季时按它走。
  let seasons: [Int]
  /// 整剧在服务器上应有的样子：剧集类型和详情里的外部编号。
  let expected: LibraryItemExpectation
  /// MoviePilot 入库查询给的整剧条目；按外部编号搜不到时，在它所属的服务器上按这个 ID 再找。
  let libraryItem: MediaServerItemRef?
  let seriesName: String?
  /// MoviePilot 详情里剧的海报（原样的路径或地址），播放界面的信息面板用。
  let seriesPosterPath: String?

  /// 没有有效 TMDB 编号或不是电视剧时为 nil：集列表接口只认 TMDB。
  init?(media: MediaInfo, episodeGroup: String?, seasons: [Int], libraryItem: MediaServerItemRef?) {
    guard media.type == "电视剧", let tmdbID = MediaIdentifier.validNumericIdentifier(media.tmdb_id) else {
      return nil
    }
    self.tmdbID = tmdbID
    self.episodeGroup = trimmedNonEmpty([episodeGroup])
    self.seasons = seasons
    expected = LibraryItemExpectation(media: media)
    self.libraryItem = libraryItem
    seriesName = trimmedNonEmpty([media.title])
    seriesPosterPath = trimmedNonEmpty([media.poster_path])
  }

  /// 服务器上这部剧的集索引的缓存键：同样的外部编号和入库条目找到的是同一批整剧条目。
  var seriesLookupKey: String {
    let ids = expected.externalIDs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    return "\(ids)|\(libraryItem?.server ?? "")|\(libraryItem?.itemID ?? "")"
  }
}

/// 按集播放时正在播（或要播）的一集：开播时冻结的上下文，加上这一集所在那一季的集列表（选中或找到这一集时的那份）。
/// 播完一集重新读到的集列表可能不可信（MoviePilot 读 TMDB 失败时返回空列表），这时按这份找上一集、下一集。
nonisolated struct QueuedEpisode: Equatable, Sendable {
  let context: EpisodePlaybackContext
  let episode: MoviePilotEpisode
  /// `episode` 所在季的 MoviePilot 集列表
  let seasonEpisodes: [MoviePilotEpisode]
  /// 先试的文件：「继续播放」接着看到一半的那一份（同一集在几个媒体库各有一份时，续播点只在那一份上）。
  /// 它不在这一集确定的文件里时照常按顺序试别的。
  var preferredFile: ServerFileRef? = nil
}

/// 某台服务器上的一个文件（条目）。
nonisolated struct ServerFileRef: Equatable, Sendable {
  let server: String
  let itemID: String
}

// MARK: - 每集的情况（对应规则见 EpisodeMatching.swift）

/// 一台服务器上读取这部剧的集的结果。
nonisolated enum ServerEpisodeLookup: Equatable, Sendable {
  case loaded(ServerEpisodeIndex)
  /// `message` 是给用户看的说明，已写明是哪台服务器。
  case failed(server: String, message: String)

  var serverName: String {
    switch self {
    case .loaded(let index): index.serverName
    case .failed(let server, _): server
    }
  }

  /// 这一集在这台服务器上的情况。
  func availability(of episode: MoviePilotEpisode) -> EpisodeAvailability {
    guard let tmdbEpisodeID = episode.tmdbEpisodeID else { return .unidentifiable(.missingEpisodeID) }
    switch self {
    case .loaded(let index): return index.availability(of: tmdbEpisodeID)
    case .failed(_, let message): return .failed(message)
    }
  }
}

/// 给用户的说明分两层：一句结论（先说结果），和原因或下一步。单集面板分两层显示，只能显示一句话的地方拼成一句。
nonisolated struct StatusText: Equatable, Sendable {
  let headline: String
  let detail: String?

  init(headline: String, detail: String? = nil) {
    self.headline = headline
    self.detail = detail
  }

  var joined: String { detail.map { "\(headline)。\($0)" } ?? headline }
}

/// 详情页每一集能不能播。
nonisolated enum EpisodeAvailability: Equatable, Sendable {
  /// 确定能播（文件带 TMDB 单集编号，或对上了整理记录）；`server` 是第一台有这一集的服务器。
  case playable(server: String)
  /// 只按季号集号找到了文件，可能不是这一集：可以播，但播放前要说明。没有服务器确定有这一集时才是这个结果。
  case uncertain(server: String, match: UncertainEpisodeMatch)
  /// 确认服务器上没有这一集：整部剧不在任何可播放的服务器上，或这部剧认得出的文件里没有这一集
  /// （有季号集号、只是集列表里没有那一集的文件，按它自己的编号不会是这一集）。
  case notOnServer
  /// 没找到这一集，但 `server` 上有文件认不出是哪一集（季号集号缺失或认不出，也对不上整理记录），这一集可能就是其中之一，
  /// 刷新元数据后可能就认得出。队列照常往后找；详情页照样可以试看，但要先在面板里说明。
  case unmatched(server: String)
  /// 没找到这一集，但 `server` 上有带外部编号的文件没能在 TMDB 核对是哪一集，这一集可能就是其中之一。
  /// 和 `unmatched` 一样可以试看（先在面板里说明），原因和后续操作不同：不是刷新元数据能解决的。
  case unverified(server: String, reason: UnverifiedReason)
  /// 这部剧第一次去 TMDB 核对，`server` 上还有 `files` 个带编号的文件没查完：先不下结论，不能试看，核对完自动更新。
  case checking(server: String, files: Int)
  /// 无法确认是哪一集，不提供单集播放。
  case unidentifiable(UnidentifiableReason)
  /// 有服务器读取失败或没读全，无法确认。说明里写明是哪台服务器、哪一步。
  case failed(String)

  /// 带编号的文件为什么没核对成。
  enum UnverifiedReason: Equatable, Sendable {
    /// 连不上 TMDB、被限流、到时间没查完。稍后会再查。
    case lookupIncomplete
    /// 编号在 TMDB 查到了，但对应这部剧的不止一集，或属于另一部剧：再查也一样，不承诺重试。
    case idsDisagree
    /// 没能读取媒体服务器的媒体库配置，不知道单集资料从哪来，没法核对。
    case librarySettingsUnreadable
  }

  enum UnidentifiableReason: Equatable, Sendable {
    /// MoviePilot 没有给出这一集的 TMDB 单集 ID。
    case missingEpisodeID

    var message: String {
      switch self {
      case .missingEpisodeID:
        return "MoviePilot 没有提供这一集的 TMDB 编号，无法确认媒体服务器上对应哪一集"
      }
    }

    /// 单集面板里结论下面的原因。
    var detail: String {
      switch self {
      case .missingEpisodeID: "MoviePilot 没有提供这一集的 TMDB 编号"
      }
    }
  }

  static let notOnServerMessage = "服务器上没有这一集"

  /// 没找到 `noun`（“这一集”“下一集”）、服务器上又有认不出是哪一集的文件时的说明。
  static func unmatchedText(server: String, noun: String = "这一集") -> StatusText {
    StatusText(headline: "\(noun)可能已经入库", detail: "有文件认不出是哪一集，刷新元数据后再检查")
  }

  static func unmatchedMessage(server: String, noun: String = "这一集") -> String {
    unmatchedText(server: server, noun: noun).joined
  }

  /// 没找到 `noun`、服务器上又有带编号的文件没核对成时的说明。
  static func unverifiedText(server: String, reason: UnverifiedReason, noun: String = "这一集") -> StatusText {
    let detail =
      switch reason {
      case .lookupIncomplete: "有文件还没和 TMDB 核对上，稍后自动重试"
      case .idsDisagree: "有文件的编号和 TMDB 对不上，无法确定是哪一集"
      case .librarySettingsUnreadable: "读不到服务器的媒体库设置，无法核对"
      }
    return StatusText(headline: "\(noun)可能已经入库", detail: detail)
  }

  static func unverifiedMessage(server: String, reason: UnverifiedReason, noun: String = "这一集") -> String {
    unverifiedText(server: server, reason: reason, noun: noun).joined
  }

  static func checkingText(server: String, files: Int) -> StatusText {
    StatusText(headline: "正在和 TMDB 核对", detail: "完成后自动更新")
  }

  /// 播放器里找上一集、下一集时：不会自动更新，请用户稍后再试。
  static func checkingQueueMessage(server: String) -> String {
    "还有文件在和 TMDB 核对，稍后再试"
  }

  /// 只按季号集号找到的文件编号在 TMDB 指向别的剧。
  var hasIdentityConflict: Bool {
    if case .uncertain(_, let match) = self { return match.identityConflict }
    return false
  }

  /// 编号指向别的剧时，播放器里停下来的说明（写明是哪台服务器）。
  static func identityConflictMessage(server: String) -> String {
    "很可能不是这一集：“\(server)”上这一集的文件编号在 TMDB 属于另一部剧"
  }

  /// 确定能播。
  var isPlayable: Bool {
    if case .playable = self { return true }
    return false
  }

  /// 可以为这一集发起试看：服务器上确认没有，或没找到、只是有认不出是哪一集的文件（要先在面板里说明）。
  var allowsTrial: Bool {
    switch self {
    case .notOnServer, .unmatched, .unverified: true
    default: false
    }
  }

  /// 不能确定能播时给用户的说明：一句结论和原因或下一步（单集面板分两层显示）；确定能播时为 nil。
  var statusText: StatusText? {
    switch self {
    case .playable: return nil
    case .uncertain(let server, let match): return match.statusText(server: server)
    case .notOnServer: return StatusText(headline: Self.notOnServerMessage)
    case .unmatched(let server): return Self.unmatchedText(server: server)
    case .unverified(let server, let reason): return Self.unverifiedText(server: server, reason: reason)
    case .checking(let server, let files): return Self.checkingText(server: server, files: files)
    case .unidentifiable(let reason): return StatusText(headline: "无法确认是哪一集", detail: reason.detail)
    case .failed(let message): return StatusText(headline: "检查失败", detail: message)
    }
  }

  /// 只能显示一句话的地方（播放键提示、读屏、播放器、试看）用的说明，由 `statusText` 两层拼成；
  /// 读取失败和缺编号本来就是一句完整的话，原样用。
  var message: String? {
    switch self {
    case .unidentifiable(let reason): reason.message
    case .failed(let message): message
    default: statusText?.joined
    }
  }

  /// 按服务器顺序看：第一台确定有这一集的服务器为准，排在前面的服务器上只按季号集号对上也让给它（以编号为准）。
  /// 没有确定的，第一台按季号集号对上的为准；都没有时，读取失败（没读全）在前，其次正在核对、这一集缺编号、
  /// 服务器上有认不出或没核对成的文件，都不是才算确认没有。
  static func resolve(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> EpisodeAvailability {
    guard episode.tmdbEpisodeID != nil else { return .unidentifiable(.missingEpisodeID) }
    var uncertain: EpisodeAvailability?
    var failure: EpisodeAvailability?
    var unidentifiable: EpisodeAvailability?
    var unmatched: EpisodeAvailability?
    var checking: EpisodeAvailability?
    for lookup in lookups {
      let result = lookup.availability(of: episode)
      switch result {
      case .playable: return result
      case .uncertain(_, let match):
        // 编号指向别的剧的副本排最后，有迹象是别的集（播出日期对不上）的其次：别的副本（这台或别的服务器上）更可信时
        // 以它为准，和起播时实际先试的一致。
        if case .uncertain(_, let current)? = uncertain {
          if match.credibilityRank < current.credibilityRank { uncertain = result }
        } else {
          uncertain = result
        }
      case .failed: if failure == nil { failure = result }
      case .checking: if checking == nil { checking = result }
      case .unidentifiable: if unidentifiable == nil { unidentifiable = result }
      case .unmatched, .unverified: if unmatched == nil { unmatched = result }
      case .notOnServer: break
      }
    }
    return uncertain ?? failure ?? checking ?? unidentifiable ?? unmatched ?? .notOnServer
  }

  /// 能播的这一集在服务器上的文件，和 `resolve` 的选择一致：先找确定有这一集的服务器，
  /// 都没有时用按季号集号对上的文件（编号指向别的剧的不用）。没有文件时为 nil。
  static func serverFile(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> ServerMediaItem? {
    guard let tmdbEpisodeID = episode.tmdbEpisodeID else { return nil }
    let indexes = lookups.compactMap { lookup -> ServerEpisodeIndex? in
      if case .loaded(let index) = lookup { return index }
      return nil
    }
    let confirmed = indexes.lazy.compactMap { $0.confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID).first }.first
    if let confirmed { return confirmed }
    // 没有确定的：各台服务器上按季号集号对上、编号不冲突的文件里取最可信的（同档按服务器顺序），
    // 和 `resolve` 选面板代表、起播时先试的一致。
    let candidates = indexes.enumerated().flatMap { server, index in
      index.uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).filter { !$0.match.identityConflict }.map { (server, $0) }
    }
    return candidates.min { lhs, rhs in
      (lhs.1.match.credibilityRank, lhs.0) < (rhs.1.match.credibilityRank, rhs.0)
    }?.1.item
  }

  /// 能播的这一集在服务器上的文件时长（秒），文件见 `serverFile`。没有文件或服务器没给时长时为 nil。
  static func serverRuntimeSeconds(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> Double? {
    serverFile(episode, lookups: lookups)?.runtimeSeconds.flatMap { $0 > 0 ? $0 : nil }
  }

  /// 这一集看到了哪里（0…1），卡片上的已播放进度条用。文件见 `serverFile`，规则见 `PlaybackResumePolicy.progressFraction`：
  /// 没看、看完了、或服务器没给时长时为 nil。
  static func watchProgress(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> Double? {
    guard let file = serverFile(episode, lookups: lookups) else { return nil }
    return PlaybackResumePolicy.progressFraction(
      positionSeconds: file.resumePositionSeconds, durationSeconds: file.runtimeSeconds)
  }
}

/// 详情页一季的查询结果，都与查询的集一一对应：每集能不能播、能播的集在服务器上的文件时长（秒），
/// 和看到了哪里（0…1，没看或看完了为 nil）。
nonisolated struct EpisodePlaybackLookup: Equatable, Sendable {
  let availability: [EpisodeAvailability]
  let serverRuntimeSeconds: [Double?]
  var watchProgress: [Double?] = []
}

/// 播放队列里一集相对当前服务器的状态。上一集、下一集只在当前服务器上找。
nonisolated enum EpisodeQueueStatus: Equatable, Sendable {
  /// 当前服务器上能播（含只按季号集号对上的，接着播时不打断）
  case playable(ServerMediaItem)
  /// 当前服务器上确认没有，第一台有的是 `server`
  case elsewhere(server: String)
  /// 确认哪台服务器上都没有，可以跳过
  case absent
  /// 没找到，`server` 上有认不出（`unverified` 为 nil）或没核对成的文件。继续找，找不到能播的集时再说明。
  case unmatched(server: String, unverified: EpisodeAvailability.UnverifiedReason? = nil)
  /// 无法确认（读取失败、没读全、缺少编号等），不能当作没有而跳过。说明里写明是哪台服务器。
  case unknown(String)

  /// 只看当前服务器就能定下的结果：能播，或当前服务器就无法确认（读取失败时这一集可能就在它上面，别的服务器有也不能说“只在别处”）。
  /// 当前服务器上没有（含有认不出是哪一集的文件）时返回 nil，要再看其他服务器才分得清“在别处”和“哪里都没有”。
  static func onCurrentServer(_ episode: MoviePilotEpisode, lookup: ServerEpisodeLookup) -> EpisodeQueueStatus? {
    if case .loaded(let index) = lookup, let tmdbEpisodeID = episode.tmdbEpisodeID,
      let item = index.playableEpisode(tmdbEpisodeID: tmdbEpisodeID)
    {
      return .playable(item)
    }
    switch lookup.availability(of: episode) {
    case .playable, .uncertain, .notOnServer, .unmatched, .unverified: return nil
    case .checking(let server, _): return .unknown(EpisodeAvailability.checkingQueueMessage(server: server))
    case .unidentifiable(let reason): return .unknown(reason.message)
    case .failed(let message): return .unknown(message)
    }
  }

  /// `others` 是其他可播放的服务器，按服务器顺序。
  static func resolve(
    _ episode: MoviePilotEpisode, current: ServerEpisodeLookup, others: [ServerEpisodeLookup]
  ) -> EpisodeQueueStatus {
    if let status = onCurrentServer(episode, lookup: current) { return status }
    switch EpisodeAvailability.resolve(episode, lookups: [current] + others) {
    case .uncertain(let server, let match) where match.identityConflict:
      // 只找到编号指向别的剧的文件：不当作没有跳过，也不自动播它，停下来说明。
      return .unknown(EpisodeAvailability.identityConflictMessage(server: server))
    case .playable(let server), .uncertain(let server, _): return .elsewhere(server: server)
    case .notOnServer: return .absent
    case .unmatched(let server): return .unmatched(server: server)
    case .unverified(let server, let reason): return .unmatched(server: server, unverified: reason)
    case .checking(let server, _): return .unknown(EpisodeAvailability.checkingQueueMessage(server: server))
    case .unidentifiable(let reason): return .unknown(reason.message)
    case .failed(let message): return .unknown(message)
    }
  }
}

/// 队列里一集和它在当前服务器上的条目，以及找到它的那一季的集列表（换到这一集后，再往前后找以它为准）。
nonisolated struct EpisodeQueueEntry: Equatable, Sendable {
  let episode: MoviePilotEpisode
  let item: ServerMediaItem
  let seasonEpisodes: [MoviePilotEpisode]
}

// MARK: - 上一集、下一集

/// 按 MoviePilot 集列表的顺序找上一集、下一集，不用服务器自己的相邻集顺序。
nonisolated enum EpisodeNavigator {
  enum Direction: Sendable {
    case next, previous

    var step: Int { self == .next ? 1 : -1 }
    var noun: String { self == .next ? "下一集" : "上一集" }
  }

  enum Outcome: Equatable, Sendable {
    /// `skippedMissing`：中间跳过了还不在服务器上的集。播完时要重新确认，那几集可能已经入库，该按顺序先播它们。
    case play(EpisodeQueueEntry, skippedMissing: Bool)
    /// 无法确认这一方向的集能不能播（在别的服务器上、读取失败、缺少编号），停下并说明原因。
    case stop(String)
    /// 集列表里还有集，但都还不在媒体服务器上（比如订阅还在下载）。
    case missing
    /// 这一方向已经没有集了。
    case end
  }

  /// 一次最多跨几季：后面几季在服务器上都没有时，不为了找一集把所有季的集列表都读一遍。
  static let maximumSeasonsToScan = 3

  /// 跨季顺序：特别篇（第 0 季）只在季内前后走；正片季按详情页顺序，跳过特别篇。
  static func seasonOrder(_ seasons: [Int], current: Int) -> [Int] {
    guard current != 0 else { return [0] }
    var seen = Set<Int>()
    let order = seasons.filter { $0 != 0 && seen.insert($0).inserted }
    return order.contains(current) ? order : [current]
  }

  /// 一集在列表里的位置：按 TMDB 单集 ID 找，列表在开播后可能变过（前面插入了集）。没有 ID 时只认原来的位置。
  static func position(of episode: MoviePilotEpisode, in list: [MoviePilotEpisode]) -> Int? {
    guard let id = episode.tmdbEpisodeID else {
      return list.indices.contains(episode.index) && list[episode.index] == episode ? episode.index : nil
    }
    return list.firstIndex { $0.tmdbEpisodeID == id }
  }

  /// 正在播的那一季用哪份集列表：重新读到的 `loaded` 里有这一集就用它；没读到（nil），或读到的列表里没有这一集
  /// （MoviePilot 读 TMDB 失败时返回空列表），就用这一集所在的那份——这一集是从那份里选的，前后是哪几集已经知道。
  /// 两份里都没有这一集时返回 nil。
  static func currentSeasonList(_ queued: QueuedEpisode, loaded: [MoviePilotEpisode]?) -> [MoviePilotEpisode]? {
    if let loaded, position(of: queued.episode, in: loaded) != nil { return loaded }
    if position(of: queued.episode, in: queued.seasonEpisodes) != nil { return queued.seasonEpisodes }
    return nil
  }

  /// 从正在播的这一集往前或往后找第一集能在当前服务器上播的（只按季号集号对上的也算）。
  /// - 没有的集跳过，没找到但服务器上有认不出是哪一集的文件的也跳过；和正在播的是同一个文件的（一个文件包含多集）也跳过。
  ///   往后找不到能播的集、又跳过了后一种时，提示在哪台服务器上刷新元数据。
  /// - 只在别的服务器上有、无法确认、集列表读不到或是空的时停下，返回原因，不当作没有而跳过。
  /// - 正在播的那一季重新读不到、或读到的列表里没有这一集时，按这一集所在的那份找（见 `currentSeasonList`）；
  ///   其他季读到空列表时，`loadSeason` 有可信的旧列表就给旧列表，没有就停下。
  /// - `episodeIDsOnServer` 是当前服务器上有文件的集的 TMDB 单集 ID（见 `ServerEpisodeIndex.episodeIDs`）。往前找时，没读过的季里已经不可能有当前服务器上的集，
  ///   就不再读：上一集只决定能不能往回播，停下的原因不显示。往后找不用它，停下时要告诉用户下一集在哪、为什么没接着播。
  static func adjacent(
    _ direction: Direction,
    from queued: QueuedEpisode,
    currentItemID: String,
    episodeIDsOnServer: Set<Int>? = nil,
    loadSeason: (Int) async throws -> [MoviePilotEpisode],
    status: (MoviePilotEpisode) async throws -> EpisodeQueueStatus
  ) async throws -> Outcome {
    let current = queued.episode
    let order = seasonOrder(queued.context.seasons, current: current.seasonNumber)
    guard var seasonPosition = order.firstIndex(of: current.seasonNumber) else { return .end }
    let loaded: Result<[MoviePilotEpisode], Error>
    do {
      loaded = .success(try await loadSeason(current.seasonNumber))
    } catch let error as CancellationError {
      throw error
    } catch {
      loaded = .failure(error)
    }
    guard var list = currentSeasonList(queued, loaded: try? loaded.get()),
      let currentIndex = position(of: current, in: list)
    else {
      switch loaded {
      case .failure(let error): return .stop(seasonLoadFailure(current.seasonNumber, error))
      case .success(let list) where list.isEmpty: return .stop(seasonUnavailable(current.seasonNumber))
      case .success:
        return .stop(
          "MoviePilot 返回的第 \(current.seasonNumber) 季集列表里没有正在播的这一集，无法确认\(direction.noun)，请重试")
      }
    }
    var seenEpisodeIDs = Set(list.compactMap(\.tmdbEpisodeID))
    var index = currentIndex + direction.step
    var scannedSeasons = 0
    var skippedMissing = false
    var unmatchedServer: (server: String, unverified: EpisodeAvailability.UnverifiedReason?)?
    while true {
      while list.indices.contains(index) {
        let episode = list[index]
        switch try await status(episode) {
        case .playable(let item) where item.id == currentItemID:
          break
        case .playable(let item):
          return .play(
            EpisodeQueueEntry(episode: episode, item: item, seasonEpisodes: list), skippedMissing: skippedMissing)
        case .absent:
          skippedMissing = true
        case .unmatched(let server, let unverified):
          skippedMissing = true
          if unmatchedServer == nil { unmatchedServer = (server, unverified) }
        case .elsewhere(let server):
          return .stop("\(direction.noun)在另一台媒体服务器“\(server)”上，请回到详情页选择")
        case .unknown(let message):
          return .stop("无法确认\(direction.noun)：\(message)")
        }
        index += direction.step
      }
      seasonPosition += direction.step
      scannedSeasons += 1
      guard order.indices.contains(seasonPosition), scannedSeasons <= maximumSeasonsToScan else {
        if direction == .next, let unmatchedServer {
          let message =
            unmatchedServer.unverified.map {
              EpisodeAvailability.unverifiedMessage(server: unmatchedServer.server, reason: $0, noun: direction.noun)
            } ?? EpisodeAvailability.unmatchedMessage(server: unmatchedServer.server, noun: direction.noun)
          return .stop(message)
        }
        return skippedMissing ? .missing : .end
      }
      if direction == .previous, let episodeIDsOnServer, episodeIDsOnServer.isSubset(of: seenEpisodeIDs) {
        return skippedMissing ? .missing : .end
      }
      let season = order[seasonPosition]
      do {
        list = try await loadSeason(season)
      } catch let error where !(error is CancellationError) {
        return .stop(seasonLoadFailure(season, error))
      }
      // MoviePilot 在这一季确实没有集和读 TMDB 失败时都返回空列表，分不清；当作没有这一季接着往后找，可能把整季跳过。
      // 有可信的旧列表时 `loadSeason` 已经换成了它，到这里就是没有，停下请用户重试。
      guard !list.isEmpty else { return .stop(seasonUnavailable(season)) }
      seenEpisodeIDs.formUnion(list.compactMap(\.tmdbEpisodeID))
      index = direction == .next ? 0 : list.count - 1
    }
  }

  /// 一季里能在当前服务器上播的集（播放界面的队列面板）。一个文件包含多集时只列第一集。
  static func playableEntries(
    in list: [MoviePilotEpisode], status: (MoviePilotEpisode) async throws -> EpisodeQueueStatus
  ) async throws -> [EpisodeQueueEntry] {
    var entries: [EpisodeQueueEntry] = []
    var seenItems = Set<String>()
    for episode in list {
      guard case .playable(let item) = try await status(episode), seenItems.insert(item.id).inserted else { continue }
      entries.append(EpisodeQueueEntry(episode: episode, item: item, seasonEpisodes: list))
    }
    return entries
  }

  /// 下一集还不在服务器上时告诉用户的话。
  static let nextMissingMessage = "下一集还不在媒体服务器上"

  /// 读 MoviePilot 的集列表失败（连不上、会话过期等），附上原因。
  private static func seasonLoadFailure(_ season: Int, _ error: Error) -> String {
    let reason = (error as? LocalizedError)?.errorDescription ?? "请稍后重试"
    return "没能从 MoviePilot 读取第 \(season) 季的集列表：\(reason)"
  }

  /// MoviePilot 返回了空的集列表，又没有可信的旧列表。
  static func seasonUnavailable(_ season: Int) -> String {
    "第 \(season) 季集列表暂不可用，请重试"
  }
}

// MARK: - 剧的「继续播放」

/// 详情页剧的「继续播放」按下做什么：服务器上的观看记录（`PlaybackEpisodeProgress`）按集索引对到 MoviePilot 集列表
/// （默认顺序）里的哪一集。「这份文件是哪一集」只认集索引（`ServerEpisodeIndex`，整理记录、剧集组编号、外部编号反查都在里面），
/// 和集卡片、起播是同一套对应，不另写规则。规则：
/// - 播哪一集以 MoviePilot 集列表为准：能播就直接播（含只按季号集号对上、没有反证的），有反证或还不能播时打开那一集的面板。
/// - 看完的那一集对得上时，下一集按集列表走，不跳集：只有确定不在服务器上的集可以略过（没看过时从最早能播的一集开始），
///   读不到、正在核对、认不出、有反证的集停在那一集；有季的集列表没读到时不跨过那一季。
/// - 对不上集列表（认不出、读不到）但没有反证时继续播：接着看到一半的那份照常接着播；看完的那一集对不上时播服务器上的下一份。
///   对不到集列表的文件，按钮不写集号，不以集列表里某一集的名义播。确定前一集不在服务器上时停在那一集，不跳过去。
/// - 有反证（播出日期对不上、单集编号指向同号以外的集、外部编号指向别的剧）的文件绝不原样播。
/// - 集列表一集都没读到时同样：没有反证就按服务器上接着看的那份播。
nonisolated enum SeriesContinuation {
  /// MoviePilot 一季的集列表（默认顺序）。
  struct Season: Equatable, Sendable {
    let number: Int
    let episodes: [MoviePilotEpisode]
  }

  enum Choice: Equatable, Sendable {
    /// 按集起播 `episode`（`season` 是它那一季的列表，播放器里能接着播）。`resumeFile`：接着看到一半的那份，起播先试它。
    case play(MoviePilotEpisode, season: [MoviePilotEpisode], resumeFile: ServerMediaItem?)
    /// 没看过或全看完：从集列表里最早能播的一集开始。
    case start(MoviePilotEpisode, season: [MoviePilotEpisode])
    /// 打开那一集的面板：还不能播，或有迹象服务器上那份不是这一集。
    case openPanel(MoviePilotEpisode)
    /// 播服务器上的这份（没有反证）。`episode` 是它对上的集列表里的那一集，按钮写那一集的集号；对不到集列表时为 nil，按钮不写集号。
    case playServerFile(ServerMediaItem, resumes: Bool, episode: MoviePilotEpisode?)
    /// 没法确定播哪一集，说明原因。
    case explain(Reason)
  }

  enum Reason: Equatable, Sendable {
    /// 这份文件有反证（播出日期对不上、单集编号指向别处、外部编号指向别的剧），又对不到集列表里能播的一集。
    case fileContradicted(ServerMediaItem)
    /// 接下来那一季的集列表没读到，服务器上也没有接着看的那份：不跨过它。
    case seasonListUnreadable
    /// 看完的那一集对不上集列表，服务器上也没有接着看的那份：没法确定下一集。
    case nextUnknown
    /// 读不到读到观看记录的那台服务器上这部剧的集（集索引），服务器上也没有接着看的那份：没法确定下一集。
    case episodesUnreadable
  }

  /// `lookups` 是各台服务器的集索引，`serverName` 是读到观看记录的那台。`seasons` 是读到的集列表；
  /// `knownSeasons` 是应有的、有集的季号（MoviePilot 给的季列表并上详情里的），没读到的季不在 `seasons` 里；
  /// `catalogComplete` 为 false 时 MoviePilot 的季列表没读到，最后一个已知季后面可能还有季。
  /// 集列表一集都没有、服务器上也没有接着看的那份时为 nil。
  static func choose(
    upNext: PlaybackEpisodeProgress.UpNext?, lastWatched: ServerMediaItem?, serverName: String,
    lookups: [ServerEpisodeLookup], seasons: [Season], knownSeasons: [Int], catalogComplete: Bool
  ) -> Choice? {
    // 正片季按季号排，特别篇放最后；接着看的下一集只在正片季之间、或特别篇里面往后走。
    let ordered = seasons.filter { $0.number > 0 }.sorted { $0.number < $1.number } + seasons.filter { $0.number == 0 }
    let entries = ordered.flatMap { season in season.episodes.map { (episode: $0, season: season.episodes) } }
    // 集列表一集都没读到：服务器上有接着看的那份时照常按它走（没有反证就继续播，有反证的说明原因），否则没法决定。
    guard !entries.isEmpty || upNext != nil else { return nil }
    let loadedSeasons = Set(seasons.map(\.number))
    let missingRegular = Set(knownSeasons.filter { $0 > 0 && !loadedSeasons.contains($0) })
    let listsComplete = catalogComplete && knownSeasons.allSatisfy(loadedSeasons.contains)
    var positions: [Int: Int] = [:]
    for (position, entry) in entries.enumerated() {
      if let id = entry.episode.tmdbEpisodeID, positions[id] == nil { positions[id] = position }
    }
    let index = lookups.lazy.compactMap { lookup -> ServerEpisodeIndex? in
      if case .loaded(let index) = lookup, index.serverName == serverName { return index }
      return nil
    }.first

    func availability(_ position: Int) -> EpisodeAvailability {
      EpisodeAvailability.resolve(entries[position].episode, lookups: lookups)
    }
    /// 集卡片会说能播：有确定的文件，或只按季号集号对上、没有反证。
    func plays(_ position: Int) -> Bool {
      switch availability(position) {
      case .playable: true
      case .uncertain(_, let match): match.hasNoContraryEvidence
      default: false
      }
    }
    func playOrPanel(_ position: Int, resumeFile: ServerMediaItem? = nil) -> Choice {
      let entry = entries[position]
      return plays(position) ? .play(entry.episode, season: entry.season, resumeFile: resumeFile) : .openPanel(entry.episode)
    }
    /// 正片季 `from` 之后、`to` 之前（`from` 为 nil 表示从头，`to` 为 nil 表示到最后）有没有没读到的季。
    func skipsUnreadSeason(after from: Int?, before to: Int?) -> Bool {
      // 季列表没读到：最后一个已知季后面可能还有季。
      if to == nil, !catalogComplete { return true }
      return missingRegular.contains { season in (from.map { season > $0 } ?? true) && (to.map { season < $0 } ?? true) }
    }

    /// 一份文件在集索引里对到集列表的哪一集。
    enum Placement {
      /// 对上了这些集（确定的，或按季号集号对上、没有反证的；多集文件几集），`candidate`：起播会试这份。
      case placed([Int], candidate: Bool)
      /// 有反证；`position` 是按季号集号或同号对到的那一集（能从别的文件播就播它），对不到时为 nil。
      case contradicted(Int?)
      /// 对不到集列表，也没有反证（认不出、集列表还没有那一集或没读到、集索引读不到）。
      case unplaced
    }
    func place(_ file: ServerMediaItem) -> Placement {
      guard let index else { return .unplaced }
      /// 它标着的那一集，按集索引认定的那套编号找（和起播、集卡片一样）：按剧集组整理的用组内编号对到的那一集，
      /// 否则在默认顺序的集列表里按季号集号找。
      func sameNumber(_ file: ServerMediaItem) -> Int? {
        if index.numberingGroup != nil { return index.numberedEpisodeIDs[file.id].flatMap { positions[$0] } }
        guard let season = file.seasonNumber, let number = file.episodeNumber else { return nil }
        return entries.firstIndex { $0.episode.seasonNumber == season && $0.episode.episodeNumber == number }
      }
      let confirmedIDs = index.confirmed.compactMap { id, files in files.contains { $0.id == file.id } ? id : nil }
      let confirmed = confirmedIDs.compactMap { positions[$0] }
      if !confirmed.isEmpty { return .placed(confirmed.sorted(), candidate: true) }
      if index.conflictingFileIDs.contains(file.id) { return .contradicted(sameNumber(file)) }
      if !confirmedIDs.isEmpty {
        // 单集编号指向集列表里没有的集。集列表读全了、又有同号的集：编号和那一集的对不上，是反证（播同号那一集，见用户决定
        // 「直接就播 B 上那份第 2 集」）。没有同号的集、或集列表没读全（编号可能在没读到的那一季）：没有反证。
        if listsComplete, let same = sameNumber(file) { return .contradicted(same) }
        return .unplaced
      }
      let matches = index.numberMatches[file.id] ?? [:]
      if matches.values.contains(where: { !$0.hasNoContraryEvidence }) {
        return .contradicted(matches.keys.compactMap { positions[$0] }.min())
      }
      let matched = matches.keys.compactMap { positions[$0] }.sorted()
      guard let first = matched.first, let id = entries[first].episode.tmdbEpisodeID else { return .unplaced }
      return .placed(matched, candidate: index.uncertain[id]?.contains { $0.item.id == file.id } == true)
    }
    /// 有反证的文件：对到的那一集能从别的文件播就播它，否则打开面板；对不到集列表时说明原因。
    func contradicted(_ file: ServerMediaItem, _ position: Int?) -> Choice {
      position.map { playOrPanel($0) } ?? .explain(.fileContradicted(file))
    }
    /// 接着看服务器上对到集列表第 `position` 集的那份：确定前一集不在服务器上时停在那一集，不跳过去。
    func follow(_ position: Int) -> Choice {
      let current = entries[position].episode.seasonNumber
      if position > 0, (entries[position - 1].episode.seasonNumber > 0) == (current > 0),
        availability(position - 1) == .notOnServer
      {
        return .openPanel(entries[position - 1].episode)
      }
      return playOrPanel(position)
    }
    /// 没看过或全看完：从最早能播的一集开始。只略过确定不在服务器上的集，其他还不能播的停在那一集；不跨过没读到的季。
    func start() -> Choice {
      let regular = entries.indices.filter { entries[$0].episode.seasonNumber > 0 }
      // 正片季一季都没读到（只读到特别篇）：不当成只有特别篇的剧。
      if regular.isEmpty, !missingRegular.isEmpty || !catalogComplete { return .explain(.seasonListUnreadable) }
      let pool = regular.isEmpty ? Array(entries.indices) : regular
      var previousSeason: Int?
      for position in pool {
        let season = entries[position].episode.seasonNumber
        if season > 0, season != previousSeason, skipsUnreadSeason(after: previousSeason, before: season) {
          return .explain(.seasonListUnreadable)
        }
        previousSeason = season
        if plays(position) { return .start(entries[position].episode, season: entries[position].season) }
        if availability(position) != .notOnServer { return .openPanel(entries[position].episode) }
      }
      if !regular.isEmpty, skipsUnreadSeason(after: previousSeason, before: nil) { return .explain(.seasonListUnreadable) }
      return .openPanel(entries[pool[0]].episode)
    }

    /// 接着看到一半的那份。
    if let upNext, upNext.resumes {
      let file = upNext.episode
      switch place(file) {
      case .placed(let covered, let candidate):
        let entry = entries[covered[0]]
        // 那一集另有确定的文件时起播不会试这份；这份没有反证，照常接着播它。
        return candidate
          ? .play(entry.episode, season: entry.season, resumeFile: file)
          : .playServerFile(file, resumes: true, episode: entry.episode)
      case .contradicted(let position): return contradicted(file, position)
      case .unplaced: return .playServerFile(file, resumes: true, episode: nil)
      }
    }

    // 接下来播什么由两件独立的事决定，先各自算出来，再按决策表（下面的 switch，每一格都写明）合起来：
    // 集列表说下一集是哪一集（`ListNext`），服务器上接着看的那份对到集列表的哪一集（`ServerNext`）。
    enum ListNext {
      /// 看完的那一集（正片）对上了，集列表里的下一集是这个位置。
      case episode(Int)
      /// 看完的是特别篇（不是最后一集），集列表里的下一集特别篇是这个位置。
      case special(Int)
      /// 看完了集列表里正片的最后一集，后面没有没读到的季。
      case finished
      /// 看完了特别篇的最后一集。
      case finishedSpecials
      /// 看完的那一集是第 `season` 季的，接下来那一季的集列表没读到。
      case blockedByUnreadSeason(after: Int)
      /// 看完的那一集对不上集列表（`reason` 是没有接着看的那份时的说明）。
      case unknown(Reason)
      /// 没有看完的记录。
      case notWatched
    }
    enum ServerNext {
      case none
      /// 对上了集列表的这个位置（多集文件取第一集）。
      case placed(Int)
      /// 对不到集列表，也没有反证。
      case unplaced(ServerMediaItem)
      /// 有反证；`position` 是按季号集号或同号对到的那一集。
      case contradicted(ServerMediaItem, Int?)
    }

    let listNext: ListNext
    if let watched = lastWatched {
      switch place(watched) {
      case .placed(let covered, _):
        // 看完的那份最后包含到集列表的哪一集，下一集按集列表走。
        let last = covered[covered.count - 1]
        let current = entries[last].episode.seasonNumber
        let following = last + 1
        if entries.indices.contains(following), (current > 0) == (entries[following].episode.seasonNumber > 0) {
          let season = entries[following].episode.seasonNumber
          if current == 0 {
            listNext = .special(following)
          } else {
            listNext =
              season == current || !skipsUnreadSeason(after: current, before: season)
              ? .episode(following) : .blockedByUnreadSeason(after: current)
          }
        } else if current == 0 {
          listNext = .finishedSpecials
        } else {
          listNext = skipsUnreadSeason(after: current, before: nil) ? .blockedByUnreadSeason(after: current) : .finished
        }
      case .contradicted: listNext = .unknown(.fileContradicted(watched))
      case .unplaced: listNext = .unknown(index == nil ? .episodesUnreadable : .nextUnknown)
      }
    } else {
      listNext = .notWatched
    }

    let serverNext: ServerNext
    if let next = upNext?.episode {
      switch place(next) {
      case .placed(let covered, _): serverNext = .placed(covered[0])
      case .contradicted(let position): serverNext = .contradicted(next, position)
      case .unplaced: serverNext = .unplaced(next)
      }
    } else {
      serverNext = .none
    }

    /// 服务器上接着看的那份对到的是正片。
    func isRegular(_ position: Int) -> Bool { entries[position].episode.seasonNumber > 0 }
    /// 下一季没读到时，第 `season` 季在没读到的那一季后面（跨过了它）。
    func crossesUnreadSeason(after current: Int, toSeason season: Int?) -> Bool {
      guard let season else { return false }
      return season > 0 && season != current && skipsUnreadSeason(after: current, before: season)
    }
    func crossesUnreadSeason(after current: Int, to position: Int?) -> Bool {
      crossesUnreadSeason(after: current, toSeason: position.map { entries[$0].episode.seasonNumber })
    }

    // 决策表：每一格单独写，不用通配，加了情况编译器会要求补上。
    switch (listNext, serverNext) {
    // 集列表说了下一集：以集列表为准。
    case (.episode(let position), .none): return playOrPanel(position)
    case (.episode(let position), .placed): return playOrPanel(position)
    case (.episode(let position), .unplaced): return playOrPanel(position)
    case (.episode(let position), .contradicted): return playOrPanel(position)
    // 正片看完：服务器上已有集列表还没更新到的下一集（对不到、没有反证）就播它；否则从头。
    case (.finished, .none): return start()
    case (.finished, .placed): return start()
    case (.finished, .unplaced(let file)): return .playServerFile(file, resumes: false, episode: nil)
    case (.finished, .contradicted): return start()
    // 看完特别篇：服务器上接着看的那份对上了正片就按它走（按 TVDB 编号的动漫，正片里的一集可能对到特别篇）；
    // 否则按集列表播下一集特别篇，最后一集特别篇看完从头。
    case (.special(let position), .none): return playOrPanel(position)
    case (.special(let position), .placed(let next)): return isRegular(next) ? follow(next) : playOrPanel(position)
    case (.special(let position), .unplaced): return playOrPanel(position)
    case (.special(let position), .contradicted): return playOrPanel(position)
    case (.finishedSpecials, .none): return start()
    case (.finishedSpecials, .placed(let next)): return isRegular(next) ? follow(next) : start()
    case (.finishedSpecials, .unplaced): return start()
    case (.finishedSpecials, .contradicted): return start()
    // 下一季没读到：服务器上的那份对不到集列表（可能就在没读到的那一季）就播它；对到的集跨过了没读到的季就说明原因。
    case (.blockedByUnreadSeason, .none): return .explain(.seasonListUnreadable)
    case (.blockedByUnreadSeason(let current), .placed(let position)):
      return crossesUnreadSeason(after: current, to: position) ? .explain(.seasonListUnreadable) : follow(position)
    case (.blockedByUnreadSeason(let current), .unplaced(let file)):
      // 对不到集列表时按服务器上的季号看：标着更后面的季就是跨过了没读到的那一季。
      return crossesUnreadSeason(after: current, toSeason: file.seasonNumber)
        ? .explain(.seasonListUnreadable) : .playServerFile(file, resumes: false, episode: nil)
    case (.blockedByUnreadSeason(let current), .contradicted(let file, let position)):
      return crossesUnreadSeason(after: current, to: position)
        ? .explain(.seasonListUnreadable) : contradicted(file, position)
    // 看完的那一集对不上：没有反证就按服务器上接着看的那份走。
    case (.unknown(let reason), .none): return .explain(reason)
    case (.unknown, .placed(let position)): return follow(position)
    case (.unknown, .unplaced(let file)): return .playServerFile(file, resumes: false, episode: nil)
    case (.unknown, .contradicted(let file, let position)): return contradicted(file, position)
    // 没有看完的记录：服务器上有接着看的那份就按它走，否则从头。
    case (.notWatched, .none): return start()
    case (.notWatched, .placed(let position)): return follow(position)
    case (.notWatched, .unplaced(let file)): return .playServerFile(file, resumes: false, episode: nil)
    case (.notWatched, .contradicted(let file, let position)): return contradicted(file, position)
    }
  }
}
