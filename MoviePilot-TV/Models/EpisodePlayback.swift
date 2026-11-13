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
  let runtimeMinutes: Int?
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
  /// 无法确认是哪一集，不提供单集播放。
  case unidentifiable(UnidentifiableReason)
  /// 有服务器读取失败或没读全，无法确认。说明里写明是哪台服务器、哪一步。
  case failed(String)

  enum UnidentifiableReason: Equatable, Sendable {
    /// MoviePilot 没有给出这一集的 TMDB 单集 ID。
    case missingEpisodeID

    var message: String {
      switch self {
      case .missingEpisodeID:
        return "MoviePilot 没有提供这一集的 TMDB 编号，无法确认媒体服务器上对应哪一集"
      }
    }
  }

  static let notOnServerMessage = "没有在媒体服务器上找到这一集"

  /// 没找到 `noun`（“这一集”“下一集”）、服务器上又有认不出是哪一集的文件时的提示。
  static func unmatchedMessage(server: String, noun: String = "这一集") -> String {
    "没有找到\(noun)，但媒体服务器“\(server)”上有文件认不出是哪一集（没有 TMDB 编号，季号集号缺失或认不出，"
      + "也对不上 MoviePilot 的整理记录），\(noun)可能就在其中。可以在媒体服务器上刷新元数据后重试"
  }

  /// 单集面板里提供试看前的一句说明。
  static func unidentifiedFilesNote(server: String) -> String {
    "媒体服务器“\(server)”上有文件认不出是哪一集，这一集可能已经在里面"
  }

  /// 确定能播。
  var isPlayable: Bool {
    if case .playable = self { return true }
    return false
  }

  /// 可以为这一集发起试看：服务器上确认没有，或没找到、只是有认不出是哪一集的文件（要先在面板里说明）。
  var allowsTrial: Bool {
    switch self {
    case .notOnServer, .unmatched: true
    default: false
    }
  }

  /// 不能确定能播时给用户的说明（不确定时说明为什么可能不是这一集）；确定能播时为 nil。
  var message: String? {
    switch self {
    case .playable: return nil
    case .uncertain(let server, let match): return match.message(server: server)
    case .notOnServer: return Self.notOnServerMessage
    case .unmatched(let server): return Self.unmatchedMessage(server: server)
    case .unidentifiable(let reason): return reason.message
    case .failed(let message): return message
    }
  }

  /// 按服务器顺序看：第一台确定有这一集的服务器为准，排在前面的服务器上只按季号集号对上也让给它（以编号为准）。
  /// 没有确定的，第一台按季号集号对上的为准；都没有时，读取失败（没读全）在前，其次这一集缺编号、服务器上有认不出是哪一集的文件，
  /// 都不是才算确认没有。
  static func resolve(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> EpisodeAvailability {
    guard episode.tmdbEpisodeID != nil else { return .unidentifiable(.missingEpisodeID) }
    var uncertain: EpisodeAvailability?
    var failure: EpisodeAvailability?
    var unidentifiable: EpisodeAvailability?
    var unmatched: EpisodeAvailability?
    for lookup in lookups {
      let result = lookup.availability(of: episode)
      switch result {
      case .playable: return result
      case .uncertain: if uncertain == nil { uncertain = result }
      case .failed: if failure == nil { failure = result }
      case .unidentifiable: if unidentifiable == nil { unidentifiable = result }
      case .unmatched: if unmatched == nil { unmatched = result }
      case .notOnServer: break
      }
    }
    return uncertain ?? failure ?? unidentifiable ?? unmatched ?? .notOnServer
  }
}

/// 播放队列里一集相对当前服务器的状态。上一集、下一集只在当前服务器上找。
nonisolated enum EpisodeQueueStatus: Equatable, Sendable {
  /// 当前服务器上能播（含只按季号集号对上的，接着播时不打断）
  case playable(ServerMediaItem)
  /// 当前服务器上确认没有，第一台有的是 `server`
  case elsewhere(server: String)
  /// 确认哪台服务器上都没有，可以跳过
  case absent
  /// 没找到，`server` 上有认不出是哪一集的文件。继续找，找不到能播的集时再说明。
  case unmatched(server: String)
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
    case .playable, .uncertain, .notOnServer, .unmatched: return nil
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
    case .playable(let server), .uncertain(let server, _): return .elsewhere(server: server)
    case .notOnServer: return .absent
    case .unmatched(let server): return .unmatched(server: server)
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
    var unmatchedServer: String?
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
        case .unmatched(let server):
          skippedMissing = true
          if unmatchedServer == nil { unmatchedServer = server }
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
          return .stop(EpisodeAvailability.unmatchedMessage(server: unmatchedServer, noun: direction.noun))
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
