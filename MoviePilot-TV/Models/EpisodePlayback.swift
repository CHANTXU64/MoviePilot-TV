import Foundation

// 按集播放：集列表来自 MoviePilot（TMDB 数据），只到媒体服务器上找这一集的文件。
//
// 媒体服务器上的季集号来自文件名或 NFO，取决于当初怎么整理（默认顺序还是某个剧集组），和详情页选的剧集组无关，
// 只比季集号无法知道服务器用的是哪套编号。所以只按 TMDB 单集 ID 对应：MoviePilot 的集列表从 v3.2.6 起带这个 ID，
// 服务器上的单集条目也存着它（MoviePilot 写的 NFO，或服务器自己刮削 TMDB）。对不上就不播，不拿季集号去猜。

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

  init(
    id: Int?, episodeNumber: Int?, seasonNumber: Int? = nil, name: String? = nil, overview: String? = nil,
    stillPath: String? = nil, airDate: String? = nil, runtime: Int? = nil
  ) {
    self.id = id
    self.episodeNumber = episodeNumber
    self.seasonNumber = seasonNumber
    self.name = name
    self.overview = overview
    self.stillPath = stillPath
    self.airDate = airDate
    self.runtime = runtime
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case episodeNumber = "episode_number"
    case seasonNumber = "season_number"
    case name, overview
    case stillPath = "still_path"
    case airDate = "air_date"
    case runtime
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
    self.index = index
  }

  static func list(_ episodes: [TmdbEpisode], season: Int) -> [MoviePilotEpisode] {
    episodes.enumerated().map { MoviePilotEpisode($1, season: season, index: $0) }
  }

  /// 播放器标题，编号与详情页一致。
  func playerTitles(seriesName: String?) -> (primary: String, secondary: String?) {
    PlaybackTitles.episode(
      name: name, seasonNumber: seasonNumber, episodeNumber: episodeNumber, seriesName: seriesName)
  }
}

// MARK: - 按集播放的上下文

/// MoviePilot 入库查询给的整剧条目。条目 ID 只在所属服务器内唯一；旧缓存可能没有服务器名。
nonisolated struct MediaServerItemRef: Equatable, Sendable {
  let itemID: String
  let server: String?
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
  }

  /// 服务器上这部剧的集索引的缓存键：同样的外部编号和入库条目找到的是同一批整剧条目。
  var seriesLookupKey: String {
    let ids = expected.externalIDs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    return "\(ids)|\(libraryItem?.server ?? "")|\(libraryItem?.itemID ?? "")"
  }
}

// MARK: - 在服务器上对应

/// 一台服务器上这部剧的全部集，按 TMDB 单集 ID 索引。
nonisolated struct ServerEpisodeIndex: Equatable, Sendable {
  let serverName: String
  /// 这台服务器上找到了这部剧
  let hasSeries: Bool
  /// 这部剧至少有一集带 TMDB 单集 ID
  let hasEpisodeIDs: Bool
  /// TMDB 单集 ID → 有文件的单集条目，保持服务器返回的顺序（同一集在多个媒体库里各有一条）。
  let episodesByTMDBID: [Int: [ServerMediaItem]]

  init(serverName: String, hasSeries: Bool, episodes: [ServerMediaItem]) {
    self.serverName = serverName
    self.hasSeries = hasSeries
    var byID: [Int: [ServerMediaItem]] = [:]
    var hasEpisodeIDs = false
    for episode in episodes {
      guard let id = episode.tmdbEpisodeID else { continue }
      hasEpisodeIDs = true
      if episode.hasFile { byID[id, default: []].append(episode) }
    }
    self.hasEpisodeIDs = hasEpisodeIDs
    episodesByTMDBID = byID
  }

  /// 有文件的全部条目，服务器返回的顺序。起播时逐个试，第一条不能直连（比如 strm）时换下一条。
  func playableEpisodes(tmdbEpisodeID: Int) -> [ServerMediaItem] {
    episodesByTMDBID[tmdbEpisodeID] ?? []
  }

  /// 队列和每集状态用的代表条目：服务器返回的第一条。
  func playableEpisode(tmdbEpisodeID: Int) -> ServerMediaItem? {
    episodesByTMDBID[tmdbEpisodeID]?.first
  }
}

/// 一台服务器上读取这部剧的集的结果。
nonisolated enum ServerEpisodeLookup: Equatable, Sendable {
  case loaded(ServerEpisodeIndex)
  case failed(server: String, message: String)

  var serverName: String {
    switch self {
    case .loaded(let index): index.serverName
    case .failed(let server, _): server
    }
  }
}

/// 详情页每一集能不能播。
nonisolated enum EpisodeAvailability: Equatable, Sendable {
  /// 可以播放；`server` 是第一台有这一集的服务器。
  case playable(server: String)
  /// 确认服务器上没有这一集：整部剧不在任何可播放的服务器上，或按 TMDB 单集 ID 对不上这一集。
  case notOnServer
  /// 无法确认是哪一集，不提供单集播放。
  case unidentifiable(UnidentifiableReason)
  /// 有服务器读取失败，无法确认。
  case failed(String)

  enum UnidentifiableReason: Equatable, Sendable {
    /// MoviePilot 没有给出这一集的 TMDB 单集 ID。
    case missingEpisodeID
    /// 服务器上这部剧的集都没有 TMDB 单集 ID（比如只用 TVDB 刮削）。按季集号对应可能播错，不提供。
    case serverHasNoEpisodeIDs

    var message: String {
      switch self {
      case .missingEpisodeID:
        return "MoviePilot 没有提供这一集的 TMDB 编号，无法确认媒体服务器上对应哪一集"
      case .serverHasNoEpisodeIDs:
        return "媒体服务器上这部剧的集没有 TMDB 编号，无法确认对应哪一集"
      }
    }
  }

  var isPlayable: Bool {
    if case .playable = self { return true }
    return false
  }

  /// 按服务器顺序看：第一台有这一集的服务器为准；都没有时，有读取失败或无法确认的就说明原因，否则算确认没有。
  static func resolve(_ episode: MoviePilotEpisode, lookups: [ServerEpisodeLookup]) -> EpisodeAvailability {
    guard let tmdbEpisodeID = episode.tmdbEpisodeID else { return .unidentifiable(.missingEpisodeID) }
    var failure: String?
    var lacksEpisodeIDs = false
    for lookup in lookups {
      switch lookup {
      case .loaded(let index):
        if index.playableEpisode(tmdbEpisodeID: tmdbEpisodeID) != nil {
          return .playable(server: index.serverName)
        }
        if index.hasSeries && !index.hasEpisodeIDs { lacksEpisodeIDs = true }
      case .failed(_, let message):
        if failure == nil { failure = message }
      }
    }
    if let failure { return .failed(failure) }
    if lacksEpisodeIDs { return .unidentifiable(.serverHasNoEpisodeIDs) }
    return .notOnServer
  }
}

/// 播放队列里一集相对当前服务器的状态。上一集、下一集只在当前服务器上找。
nonisolated enum EpisodeQueueStatus: Equatable, Sendable {
  /// 当前服务器上能播
  case playable(ServerMediaItem)
  /// 只在别的服务器上有
  case elsewhere
  /// 确认哪台服务器上都没有，可以跳过
  case absent
  /// 无法确认（读取失败、缺少编号等），不能当作没有而跳过
  case unknown(String)

  static func resolve(
    _ episode: MoviePilotEpisode, currentServer: String, lookups: [ServerEpisodeLookup]
  ) -> EpisodeQueueStatus {
    if let tmdbEpisodeID = episode.tmdbEpisodeID,
      case .loaded(let index)? = lookups.first(where: { $0.serverName == currentServer }),
      let item = index.playableEpisode(tmdbEpisodeID: tmdbEpisodeID)
    {
      return .playable(item)
    }
    switch EpisodeAvailability.resolve(episode, lookups: lookups) {
    case .playable: return .elsewhere
    case .notOnServer: return .absent
    case .unidentifiable(let reason): return .unknown(reason.message)
    case .failed(let message): return .unknown(message)
    }
  }
}

/// 队列里一集和它在当前服务器上的条目。
nonisolated struct EpisodeQueueEntry: Equatable, Sendable {
  let episode: MoviePilotEpisode
  let item: ServerMediaItem
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

  /// 从正在播的这一集往前或往后找第一集能在当前服务器上播的。
  /// - 当前服务器上确认没有的集跳过；和正在播的是同一个文件的（一个文件包含多集）也跳过。
  /// - 只在别的服务器上有、无法确认、集列表读不到时停下，返回原因，不当作没有而跳过。
  static func adjacent(
    _ direction: Direction,
    from current: MoviePilotEpisode,
    currentItemID: String,
    seasons: [Int],
    loadSeason: (Int) async throws -> [MoviePilotEpisode],
    status: (MoviePilotEpisode) async throws -> EpisodeQueueStatus
  ) async throws -> Outcome {
    let order = seasonOrder(seasons, current: current.seasonNumber)
    guard var seasonPosition = order.firstIndex(of: current.seasonNumber) else { return .end }
    var list: [MoviePilotEpisode]
    do {
      list = try await loadSeason(current.seasonNumber)
    } catch let error where !(error is CancellationError) {
      return .stop(seasonLoadFailure(current.seasonNumber))
    }
    // 集列表可能在开播后刷新过，按 TMDB 单集 ID 重新定位，找不到再用开播时的位置。
    let currentIndex =
      current.tmdbEpisodeID.flatMap { id in list.firstIndex { $0.tmdbEpisodeID == id } } ?? current.index
    var index = currentIndex + direction.step
    var scannedSeasons = 0
    var skippedMissing = false
    while true {
      while list.indices.contains(index) {
        let episode = list[index]
        switch try await status(episode) {
        case .playable(let item) where item.id == currentItemID:
          break
        case .playable(let item):
          return .play(EpisodeQueueEntry(episode: episode, item: item), skippedMissing: skippedMissing)
        case .absent:
          skippedMissing = true
        case .elsewhere:
          return .stop("\(direction.noun)在另一台媒体服务器上，请回到详情页选择")
        case .unknown(let message):
          return .stop("无法确认\(direction.noun)：\(message)")
        }
        index += direction.step
      }
      seasonPosition += direction.step
      scannedSeasons += 1
      guard order.indices.contains(seasonPosition), scannedSeasons <= maximumSeasonsToScan else {
        return skippedMissing ? .missing : .end
      }
      let season = order[seasonPosition]
      do {
        list = try await loadSeason(season)
      } catch let error where !(error is CancellationError) {
        return .stop(seasonLoadFailure(season))
      }
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
      entries.append(EpisodeQueueEntry(episode: episode, item: item))
    }
    return entries
  }

  /// 下一集还不在服务器上时告诉用户的话。
  static let nextMissingMessage = "下一集还不在媒体服务器上"

  private static func seasonLoadFailure(_ season: Int) -> String {
    "没能读取第 \(season) 季的集列表"
  }
}
