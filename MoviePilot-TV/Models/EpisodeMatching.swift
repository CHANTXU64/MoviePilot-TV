import Foundation

// 单集对应：媒体服务器上的文件 ↔ MoviePilot 集列表里的集（TMDB 单集）。
// 各类媒体服务器的条目先转成 `ServerMediaItem`，这里不关心是哪一类服务器；要用的 MoviePilot 集列表和整理记录由
// `EpisodeMatchLoader` 按需读好再交给 `ServerEpisodeIndex`。
//
// 服务器上的季号集号来自整理时写进的文件名或 NFO：按默认顺序，或按订阅时选的剧集组，和详情页现在选的剧集组无关。
// 按可信程度依次对应：
// 1. 文件带 TMDB 单集编号：确定。一个文件包含多集、只记了第一集的编号时，按默认顺序核对后覆盖后几集。
// 2. 文件对上 MoviePilot 的整理记录：按记录里的剧集组、季、集换算成 TMDB 单集，确定。
// 3. 都没有：按文件的季号集号，在这部剧整理记录用过的剧集组（没有记录就是默认顺序）里找同季同集，再比播出日期。
//    不确定，播放前要说明可能不是这一集。MoviePilot 自己判断入库也只看季号集号，这一步和它的判断一致。
// 以编号为准：某一集有确定的文件时只用确定的；带 TMDB 单集编号的文件只按编号对应。

// MARK: - MoviePilot 集列表与整理记录

/// 一份 MoviePilot 集列表：剧集组（nil 为默认顺序，季号就是 TMDB 季号）和组内季号。
nonisolated struct EpisodeListKey: Hashable, Comparable, Sendable {
  let episodeGroup: String?
  let season: Int

  init(episodeGroup: String?, season: Int) {
    self.episodeGroup = trimmedNonEmpty([episodeGroup])
    self.season = season
  }

  /// 失败说明里的称呼，如「第 2 季」「剧集组第 2 季」。
  var title: String { episodeGroup == nil ? "第 \(season) 季" : "剧集组第 \(season) 季" }

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.episodeGroup ?? "", lhs.season) < (rhs.episodeGroup ?? "", rhs.season)
  }
}

/// 一个文件在 MoviePilot 编号里的位置：哪份集列表、哪几集。
nonisolated struct EpisodePlacement: Equatable, Sendable {
  let list: EpisodeListKey
  let episodes: [Int]
}

/// MoviePilot 记录里的季集文字：`S01`、`E05`、`E05-E06`、`E01,E03`。下载、整理记录共用。
nonisolated enum EpisodeNumberText {
  /// 每段一个区间；`single` 时只能有一段、一个数。格式不对时为 nil。
  static func ranges(in value: String, prefix: String, single: Bool) -> [ClosedRange<Int>]? {
    let parts = value.uppercased().split(
      omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "、" })
    if single && parts.count != 1 { return nil }
    var ranges: [ClosedRange<Int>] = []
    for part in parts {
      let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
      let numbers = bounds.compactMap { component -> Int? in
        let token = component.trimmingCharacters(in: .whitespaces)
        let digits = token.hasPrefix(prefix) ? String(token.dropFirst()) : token
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(digits)
      }
      guard numbers.count == bounds.count, let first = numbers.first, let last = numbers.last,
        first <= last, (1...2).contains(numbers.count), !single || numbers.count == 1
      else { return nil }
      ranges.append(first...last)
    }
    return ranges
  }
}

/// MoviePilot 整理记录（`GET /api/v1/history/transfer`）里单集对应用到的字段。只解码这些，单个字段坏掉只丢它。
nonisolated struct EpisodeTransferRecord: Decodable, Equatable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let type: String?
  /// `S01`
  let seasons: String?
  /// `E05`；一个文件包含多集时 `E05-E06`
  let episodes: String?
  /// 整理时用的剧集组；默认顺序为 nil。
  let episodeGroup: String?
  /// 整理后的文件路径（MoviePilot 看到的路径）：`dest_fileitem.path`，没有时用 `dest`。
  let path: String?
  let succeeded: Bool
  let date: String?

  /// 一个文件最多覆盖这么多集，超出的按格式不对处理。
  static let maximumEpisodesPerFile = 50

  init(
    mediaSource: String? = "themoviedb", mediaID: String?, type: String? = "电视剧", seasons: String?,
    episodes: String?, episodeGroup: String? = nil, path: String?, succeeded: Bool = true, date: String? = nil
  ) {
    self.mediaSource = mediaSource
    self.mediaID = mediaID
    self.type = type
    self.seasons = seasons
    self.episodes = episodes
    self.episodeGroup = episodeGroup
    self.path = path
    self.succeeded = succeeded
    self.date = date
  }

  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case type, seasons, episodes
    case episodeGroup = "episode_group"
    case dest
    case destFileItem = "dest_fileitem"
    case status, date
  }

  private struct FileItem: Decodable {
    let path: String?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try? container.decodeIfPresent(String.self, forKey: .path)
    }

    private enum CodingKeys: String, CodingKey { case path }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mediaSource = try? container.decodeIfPresent(String.self, forKey: .mediaSource)
    let numericID = try? container.decodeIfPresent(Int.self, forKey: .mediaID)
    mediaID = (try? container.decodeIfPresent(String.self, forKey: .mediaID)) ?? numericID.map { String($0) }
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    seasons = try? container.decodeIfPresent(String.self, forKey: .seasons)
    episodes = try? container.decodeIfPresent(String.self, forKey: .episodes)
    episodeGroup = try? container.decodeIfPresent(String.self, forKey: .episodeGroup)
    let fileItem = try? container.decodeIfPresent(FileItem.self, forKey: .destFileItem)
    let dest = try? container.decodeIfPresent(String.self, forKey: .dest)
    path = trimmedNonEmpty([fileItem?.path, dest])
    let status = try? container.decodeIfPresent(FlexibleBool.self, forKey: .status)
    succeeded = status?.value == true
    date = try? container.decodeIfPresent(String.self, forKey: .date)
  }

  /// 这部剧（TMDB 编号）成功整理的电视剧记录。
  func belongs(toSeries tmdbID: Int) -> Bool {
    guard succeeded, type == nil || type == "电视剧",
      let identity = MediaIdentifier.resolve(source: mediaSource, mediaId: mediaID)
    else { return false }
    return identity == MediaIdentity(source: "themoviedb", mediaId: String(tmdbID))
  }

  /// 记录里这个文件的位置。季不是一个、集号认不出时为 nil。
  var placement: EpisodePlacement? {
    guard let seasonRanges = seasons.flatMap({ EpisodeNumberText.ranges(in: $0, prefix: "S", single: true) }),
      let season = seasonRanges.first?.lowerBound,
      let episodeRanges = episodes.flatMap({ EpisodeNumberText.ranges(in: $0, prefix: "E", single: false) }),
      episodeRanges.reduce(0, { $0 + $1.count }) <= Self.maximumEpisodesPerFile
    else { return nil }
    let numbers = Array(Set(episodeRanges.flatMap { Array($0) })).sorted()
    guard !numbers.isEmpty else { return nil }
    return EpisodePlacement(list: EpisodeListKey(episodeGroup: episodeGroup, season: season), episodes: numbers)
  }
}

/// 比对文件用的路径尾部：上一级目录名和文件名（不含扩展名），不分大小写。
/// MoviePilot 和媒体服务器常跑在不同容器里，挂载点不同，完整路径对不上；网盘 STRM 的扩展名也和原文件不同。
nonisolated struct FilePathKey: Hashable, Sendable {
  let parent: String
  let name: String

  init?(path: String?) {
    guard let path else { return nil }
    let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
    guard components.count >= 2 else { return nil }
    let file = components[components.count - 1]
    var name = file
    if let dot = file.lastIndex(of: "."), dot != file.startIndex, file.distance(from: dot, to: file.endIndex) <= 6 {
      name = String(file[..<dot])
    }
    guard !name.isEmpty else { return nil }
    parent = Self.normalized(components[components.count - 2])
    self.name = Self.normalized(name)
  }

  private static func normalized(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.lowercased()
  }
}

// MARK: - 按季号集号对应的依据

/// 服务器和 MoviePilot 的播出日期比对结果。
nonisolated enum AirDateCheck: Equatable, Sendable {
  /// 相差不超过一天：服务器的日期多来自 TVDB 或按 UTC 存，和 TMDB 可能差一天。
  case matches
  case differs(server: String, moviePilot: String)
  /// 有一边没有日期，或格式认不出。
  case unknown

  /// 两边都以 `yyyy-MM-dd` 开头时才比（服务器的日期带时间，只取日期部分）。
  static func compare(server: String?, moviePilot: String?) -> AirDateCheck {
    guard let serverDay = day(server), let moviePilotDay = day(moviePilot) else { return .unknown }
    if abs(serverDay.number - moviePilotDay.number) <= 1 { return .matches }
    return .differs(server: serverDay.text, moviePilot: moviePilotDay.text)
  }

  /// 日期部分和它对应的天数，格式不对时为 nil。
  private static func day(_ value: String?) -> (text: String, number: Int)? {
    guard let value else { return nil }
    let bytes = Array(value.utf8.prefix(10))
    guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
      bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) })
    else { return nil }
    let digits = bytes.map { Int($0) - 48 }
    let year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
    let month = digits[5] * 10 + digits[6]
    let day = digits[8] * 10 + digits[9]
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    return (String(decoding: bytes, as: UTF8.self), daysFromCivil(year: year, month: month, day: day))
  }

  /// 公历日期到 1970-01-01 的天数（Howard Hinnant 的算法），只用来算两个日期相差几天。
  private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }
}

/// 按季号集号对应（第 3 步）的依据，单集面板据此说明为什么可能不是这一集。
nonisolated struct UncertainEpisodeMatch: Equatable, Sendable {
  /// 服务器文件上的季号和这一集对上的集号
  let season: Int
  let episode: Int
  /// 按哪个剧集组的编号比的（这部剧整理记录里用过的）；默认顺序为 nil。
  let episodeGroup: String?
  let airDate: AirDateCheck

  /// 给用户的说明，`server` 是这个文件所在的服务器。
  func message(server: String) -> String {
    let numbering = episodeGroup == nil ? "季号集号" : "整理时所用剧集组的季号集号"
    let base = "“\(server)”上的文件没有 TMDB 编号，也对不上 MoviePilot 的整理记录，是按\(numbering)找到的第 \(season) 季第 \(episode) 集"
    switch airDate {
    case .matches:
      return base + "，播出日期也对得上，但仍可能不是这一集"
    case .differs(let serverDate, let moviePilotDate):
      return base + "，但播出日期对不上（服务器上是 \(serverDate)，这一集是 \(moviePilotDate)），很可能不是这一集"
    case .unknown:
      return base + "，没有播出日期可以核对，可能不是这一集"
    }
  }
}

// MARK: - 一台服务器上的对应表

/// 一台服务器上这部剧的文件和 TMDB 单集的对应。
nonisolated struct ServerEpisodeIndex: Equatable, Sendable {
  /// 按季号集号对上的一个文件。
  struct UncertainFile: Equatable, Sendable {
    let item: ServerMediaItem
    let match: UncertainEpisodeMatch
  }

  /// 各步对上的文件数，写日志用。
  struct Summary: Equatable, Sendable {
    var byEpisodeID = 0
    var byTransferRecord = 0
    var bySeasonEpisode = 0
    var airDateMatches = 0
    var airDateDiffers = 0
    var unresolved = 0

    /// 有文件没带 TMDB 单集编号时的日志说明；都带编号时为 nil。不写路径和编号本身。
    var logText: String? {
      guard byTransferRecord + bySeasonEpisode + unresolved > 0 else { return nil }
      return "按 TMDB 单集编号对上 \(byEpisodeID) 个文件，按整理记录对上 \(byTransferRecord) 个，"
        + "按季号集号对上 \(bySeasonEpisode) 个（播出日期对上 \(airDateMatches) 个、对不上 \(airDateDiffers) 个），"
        + "没对上 \(unresolved) 个"
    }
  }

  let serverName: String
  /// 这台服务器上找到了这部剧
  let hasSeries: Bool
  /// 确定的对应：TMDB 单集 ID → 有文件的单集条目。带编号的按服务器返回的顺序在前（同一集在多个媒体库里各有一条），
  /// 多集文件覆盖的、按整理记录对上的排在后面。
  let confirmed: [Int: [ServerMediaItem]]
  /// 按季号集号的对应，只留没有确定文件的集。
  let uncertain: [Int: [UncertainFile]]
  /// 有文件、哪一步都没对上的文件数：没有编号又没有季号集号，或整理记录、集列表里找不到它的位置。
  /// 找不到某一集时提示用户刷新元数据，判断照常按没有处理（见 `availability(of:)`）。
  let unresolvedFileCount: Int
  /// 没有读全时的失败说明（已写明服务器和操作）：这部剧在这台服务器上有几份（不同媒体库），有的读取失败；
  /// 或按外部编号查找、按 ID 补查、读 MoviePilot 集列表有一步失败。读到的照常用，找不到某一集时不能说这台上没有。
  let incompleteReason: String?
  let summary: Summary

  /// `lists` 是按 `requiredLists(for:records:)` 读到的 MoviePilot 集列表（读不到的不放），
  /// `records` 是这部剧成功的整理记录（已按 TMDB 编号筛过）。
  init(
    serverName: String, hasSeries: Bool, episodes: [ServerMediaItem], incompleteReason: String? = nil,
    lists: [EpisodeListKey: [TmdbEpisode]] = [:], records: [EpisodeTransferRecord] = []
  ) {
    self.serverName = serverName
    self.hasSeries = hasSeries
    self.incompleteReason = incompleteReason
    let plan = Plan(episodes: episodes, records: records)
    var confirmed: [Int: [ServerMediaItem]] = [:]
    var uncertain: [Int: [UncertainFile]] = [:]
    var summary = Summary()
    func confirm(_ file: ServerMediaItem, as id: Int) {
      guard confirmed[id]?.contains(where: { $0.id == file.id }) != true else { return }
      confirmed[id, default: []].append(file)
    }

    for file in plan.files {
      guard let id = file.tmdbEpisodeID else { continue }
      confirm(file, as: id)
      summary.byEpisodeID += 1
    }
    // 包含多集的文件：在默认顺序列表里按文件自己的 TMDB 单集 ID 找到那一集，季号、集号都和文件一致时，
    // 后几集也记到这个文件上。对不上时不推算，不知道文件按哪套编号。
    for file in plan.files {
      guard let range = Self.coveredRange(of: file), let id = file.tmdbEpisodeID, let season = file.seasonNumber,
        let list = lists[EpisodeListKey(episodeGroup: nil, season: season)],
        let own = list.first(where: { $0.id == id }), own.episodeNumber == range.lowerBound,
        own.seasonNumber == nil || own.seasonNumber == season
      else { continue }
      for covered in list {
        guard let number = covered.episodeNumber, number != range.lowerBound, range.contains(number),
          let coveredID = covered.id, coveredID != id
        else { continue }
        confirm(file, as: coveredID)
      }
    }
    for file in plan.files where file.tmdbEpisodeID == nil {
      switch plan.step(for: file) {
      case .recorded(let placement):
        let ids = placement.episodes.compactMap { Self.episodeID(number: $0, in: lists[placement.list]) }
        if ids.isEmpty {
          summary.unresolved += 1
        } else {
          ids.forEach { confirm(file, as: $0) }
          summary.byTransferRecord += 1
        }
      case .numbered(let key, let range):
        guard let list = lists[key] else {
          summary.unresolved += 1
          continue
        }
        // 文件的播出日期是它第一集的。
        let airDate = AirDateCheck.compare(
          server: file.premiereDate, moviePilot: list.first { $0.episodeNumber == range.lowerBound }?.airDate)
        var matched = false
        for number in range {
          guard let id = Self.episodeID(number: number, in: list) else { continue }
          let match = UncertainEpisodeMatch(
            season: key.season, episode: number, episodeGroup: key.episodeGroup, airDate: airDate)
          uncertain[id, default: []].append(UncertainFile(item: file, match: match))
          matched = true
        }
        guard matched else {
          summary.unresolved += 1
          continue
        }
        summary.bySeasonEpisode += 1
        switch airDate {
        case .matches: summary.airDateMatches += 1
        case .differs: summary.airDateDiffers += 1
        case .unknown: break
        }
      case .unresolved:
        summary.unresolved += 1
      }
    }
    self.confirmed = confirmed
    self.uncertain = uncertain.filter { confirmed[$0.key] == nil }
    unresolvedFileCount = summary.unresolved
    self.summary = summary
  }

  /// 建对应表要读的 MoviePilot 集列表：包含多集的带编号文件所在季的默认顺序列表，没有编号的文件按整理记录或季号集号要用的列表。
  static func requiredLists(for episodes: [ServerMediaItem], records: [EpisodeTransferRecord]) -> Set<EpisodeListKey> {
    let plan = Plan(episodes: episodes, records: records)
    var keys = Set(
      plan.files.filter { coveredRange(of: $0) != nil }.compactMap(\.seasonNumber).map {
        EpisodeListKey(episodeGroup: nil, season: $0)
      })
    for file in plan.files where file.tmdbEpisodeID == nil {
      switch plan.step(for: file) {
      case .recorded(let placement): keys.insert(placement.list)
      case .numbered(let key, _): keys.insert(key)
      case .unresolved: break
      }
    }
    return keys
  }

  /// 没有对上整理记录的文件按哪套编号比季号集号：这部剧最近一条整理记录用的剧集组；没有记录时按默认顺序。
  static func numberingGroup(_ records: [EpisodeTransferRecord]) -> String? {
    // 日期相同时取排在前面的（MoviePilot 按日期倒序返回）。
    let latest = records.enumerated().max { lhs, rhs in
      (lhs.element.date ?? "", -lhs.offset) < (rhs.element.date ?? "", -rhs.offset)
    }
    return latest.flatMap { trimmedNonEmpty([$0.element.episodeGroup]) }
  }

  private enum Step {
    case recorded(EpisodePlacement)
    case numbered(EpisodeListKey, ClosedRange<Int>)
    case unresolved
  }

  /// 每个没有编号的文件走哪一步。`requiredLists` 和建表共用，读的列表和用的列表一致。
  private struct Plan {
    let files: [ServerMediaItem]
    /// 文件 → 整理记录里的位置。同一个文件有几条记录且位置不同时不用（不知道哪条对）。
    let placements: [FilePathKey: EpisodePlacement]
    let numberingGroup: String?

    init(episodes: [ServerMediaItem], records: [EpisodeTransferRecord]) {
      files = episodes.filter(\.hasFile)
      var found: [FilePathKey: EpisodePlacement?] = [:]
      for record in records {
        guard let key = FilePathKey(path: record.path), let placement = record.placement else { continue }
        if let existing = found[key] {
          if existing != placement { found[key] = .some(nil) }
        } else {
          found[key] = placement
        }
      }
      placements = found.compactMapValues { $0 }
      numberingGroup = ServerEpisodeIndex.numberingGroup(records)
    }

    func step(for file: ServerMediaItem) -> Step {
      if let key = FilePathKey(path: file.path), let placement = placements[key] { return .recorded(placement) }
      guard let season = file.seasonNumber, let first = file.episodeNumber else { return .unresolved }
      let last = max(file.episodeNumberEnd ?? first, first)
      guard last - first < EpisodeTransferRecord.maximumEpisodesPerFile else { return .unresolved }
      return .numbered(EpisodeListKey(episodeGroup: numberingGroup, season: season), first...last)
    }
  }

  private static func episodeID(number: Int, in list: [TmdbEpisode]?) -> Int? {
    list?.first { $0.episodeNumber == number }?.id
  }

  /// 带 TMDB 单集编号的文件包含的集号范围；只含一集、缺编号、季号或集号时为 nil。
  private static func coveredRange(of file: ServerMediaItem) -> ClosedRange<Int>? {
    guard file.tmdbEpisodeID != nil, file.seasonNumber != nil, let first = file.episodeNumber,
      let last = file.episodeNumberEnd, last > first
    else { return nil }
    return first...last
  }

  // MARK: 起播前核对

  enum Recheck: Equatable, Sendable {
    /// 还是对应表里记的那一集
    case same
    /// 条目变了（编号、季号集号或文件路径不同），对应表要重读
    case changed
    /// 对应时带着 TMDB 单集编号，重新读取却没有了
    case lostEpisodeID
    /// 只知道条目 ID（播放中换集），条目上又没有编号，要按对应表核对
    case needsIndex
  }

  /// 起播前重新读到的条目还是不是要播的这一集。`recorded` 是对应表里记的条目，只知道条目 ID 时为 nil。
  static func recheck(_ fresh: ServerMediaItem, recorded: ServerMediaItem?, tmdbEpisodeID: Int) -> Recheck {
    if fresh.tmdbEpisodeID == tmdbEpisodeID { return .same }
    guard let recorded else { return fresh.tmdbEpisodeID == nil ? .needsIndex : .changed }
    if let recordedID = recorded.tmdbEpisodeID {
      guard let freshID = fresh.tmdbEpisodeID else { return .lostEpisodeID }
      // 包含多集的文件：编号和集号范围都和对应表里记的一样（对应表按这些确认过它包含要播的这一集）。
      guard let range = coveredRange(of: recorded), recordedID == freshID,
        fresh.seasonNumber == recorded.seasonNumber, coveredRange(of: fresh) == range
      else { return .changed }
      return .same
    }
    // 按整理记录或季号集号对应的：仍然没有编号，季号集号和文件路径都没变。
    guard fresh.tmdbEpisodeID == nil, fresh.seasonNumber == recorded.seasonNumber,
      fresh.episodeNumber == recorded.episodeNumber, fresh.episodeNumberEnd == recorded.episodeNumberEnd,
      fresh.path == nil || recorded.path == nil || fresh.path == recorded.path
    else { return .changed }
    return .same
  }

  // MARK: 查询

  /// 这一集确定的文件，服务器返回的顺序。
  func confirmedEpisodes(tmdbEpisodeID: Int) -> [ServerMediaItem] {
    confirmed[tmdbEpisodeID] ?? []
  }

  /// 这一集按季号集号对上的文件；有确定的文件时为空。
  func uncertainEpisodes(tmdbEpisodeID: Int) -> [UncertainFile] {
    uncertain[tmdbEpisodeID] ?? []
  }

  /// 起播时逐个试的条目（第一条不能直连，比如 strm，就换下一条）：有确定的文件只用确定的，否则用按季号集号对上的。
  func playableEpisodes(tmdbEpisodeID: Int) -> [ServerMediaItem] {
    let confirmed = confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID)
    return confirmed.isEmpty ? uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).map(\.item) : confirmed
  }

  /// 队列和每集状态用的代表条目。上一集、下一集也用按季号集号对上的，不打断连续播放。
  func playableEpisode(tmdbEpisodeID: Int) -> ServerMediaItem? {
    playableEpisodes(tmdbEpisodeID: tmdbEpisodeID).first
  }

  /// 这台服务器上有文件的集（确定的和按季号集号对上的）。
  var episodeIDs: Set<Int> { Set(confirmed.keys).union(uncertain.keys) }

  /// 这一集在这台服务器上的情况。确定的文件 → 能播；按季号集号对上 → 不确定；都没有时按原因分：
  /// - 没读全：有一步读取失败，不能说这台上没有（`failed`，说明是哪一步）。
  /// - 有文件哪一步都没对上：按没有处理，提示可以刷新元数据（`unmatched`）。
  /// - 其他：确认没有（`notOnServer`）。
  func availability(of tmdbEpisodeID: Int) -> EpisodeAvailability {
    if !confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID).isEmpty { return .playable(server: serverName) }
    if let file = uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).first {
      return .uncertain(server: serverName, match: file.match)
    }
    if let incompleteReason { return .failed(incompleteReason) }
    if unresolvedFileCount > 0 { return .unmatched(server: serverName) }
    return .notOnServer
  }
}

// MARK: - 读取

/// 建对应表要用的 MoviePilot 数据，按需读取。
struct EpisodeMatchingSources {
  /// 一份 MoviePilot 集列表
  let seasonList: (EpisodeListKey) async throws -> [TmdbEpisode]
  /// 这部剧成功的整理记录（已按 TMDB 编号筛过）
  let transferRecords: () async throws -> [EpisodeTransferRecord]
}

enum EpisodeMatchLoader {
  /// 一台服务器上这部剧的对应表。`episodes` 是从服务器读到的这部剧的全部集，`incompleteReason` 是读服务器时没读全的说明。
  /// 有文件没带 TMDB 单集编号时才读整理记录；读不到只记日志，这些文件照常按季号集号对应。
  /// 集列表读不到或是空的（MoviePilot 读 TMDB 失败时返回空列表）时，那一季的文件无法对应，记为没读全。
  /// `describe` 把错误转成给用户看的说明。
  static func index(
    serverName: String, hasSeries: Bool, episodes: [ServerMediaItem], incompleteReason: String?,
    sources: EpisodeMatchingSources, describe: (Error) -> String
  ) async throws -> ServerEpisodeIndex {
    var records: [EpisodeTransferRecord] = []
    if episodes.contains(where: { $0.hasFile && $0.tmdbEpisodeID == nil }) {
      do {
        records = try await sources.transferRecords()
      } catch let error where !(error is CancellationError) {
        Logger.warning("[Playback] 没能读取 MoviePilot 的整理记录，没有编号的文件只按季号集号对应: \(describe(error))")
      }
    }
    var lists: [EpisodeListKey: [TmdbEpisode]] = [:]
    var listFailure: String?
    for key in ServerEpisodeIndex.requiredLists(for: episodes, records: records).sorted() {
      do {
        let list = try await sources.seasonList(key)
        if list.isEmpty {
          listFailure = listFailure ?? "MoviePilot 返回的\(key.title)集列表是空的，无法对应这一季的文件"
        } else {
          lists[key] = list
        }
      } catch let error where !(error is CancellationError) {
        listFailure = listFailure ?? "没能从 MoviePilot 读取\(key.title)的集列表，无法对应这一季的文件：\(describe(error))"
      }
    }
    if let listFailure {
      Logger.warning("[Playback] “\(serverName)”上这部剧没有读全: \(listFailure)")
    }
    let index = ServerEpisodeIndex(
      serverName: serverName, hasSeries: hasSeries, episodes: episodes,
      incompleteReason: incompleteReason ?? listFailure, lists: lists, records: records)
    if let summary = index.summary.logText {
      Logger.info("[Playback] “\(serverName)”上这部剧（整理记录 \(records.count) 条）：\(summary)")
    }
    return index
  }
}
