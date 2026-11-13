import Foundation

// 单集对应：媒体服务器上的文件 ↔ MoviePilot 集列表里的集（TMDB 单集）。
// 各类媒体服务器的条目先转成 `ServerMediaItem`，这里不关心是哪一类服务器；要用的 MoviePilot 集列表和整理记录由
// `EpisodeMatchLoader` 按需读好再交给 `ServerEpisodeIndex`。
//
// 服务器上的季号集号来自整理时写进的文件名或 NFO：按默认顺序，或按订阅时选的剧集组，和详情页现在选的剧集组无关。
// 按可信程度依次对应：
// 1. 文件带 TMDB 单集编号：确定。一个文件包含多集、只记了第一集的编号时，按默认顺序核对后覆盖后几集。
// 2. 文件对上 MoviePilot 的整理记录：比较完整路径或共同路径尾部，再按记录换算成 TMDB 单集。
// 3. 按整理时使用的编号找同季同集。单集资料不是从 TMDB 取的文件（见 `MediaLibraryProfile.independentFiles`），
//    外部编号在 TMDB 反查到这部剧的一集，或标题和 TMDB 某种语言里同季唯一的具体标题一致，就算确定；
//    其余候选在面板里说明日期等依据。
// 以编号为准：某一集有确定的文件时只用确定的；带 TMDB 单集编号的文件只按编号对应。
// 哪一步都没对上的文件分两种：有季号集号、只是集列表里没有那一集的，按它自己的编号不会是别的集，不影响别的集；
// 季号集号缺失或认不出的，不知道是哪一集，这部剧没找到的集可能就是它。

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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mediaSource = try? container.decodeIfPresent(String.self, forKey: .mediaSource)
    let numericID = try? container.decodeIfPresent(Int.self, forKey: .mediaID)
    mediaID = (try? container.decodeIfPresent(String.self, forKey: .mediaID)) ?? numericID.map { String($0) }
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    seasons = try? container.decodeIfPresent(String.self, forKey: .seasons)
    episodes = try? container.decodeIfPresent(String.self, forKey: .episodes)
    episodeGroup = try? container.decodeIfPresent(String.self, forKey: .episodeGroup)
    let fileItem = try? container.decodeIfPresent(MoviePilotFileItem.self, forKey: .destFileItem)
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

/// 整理路径和媒体库路径可能有不同挂载前缀，STRM 也可能改了扩展名。
nonisolated struct EpisodeFilePath: Sendable {
  private let fullPath: String
  private let tail: [String]
  let stemPath: String

  var filename: String { tail[tail.count - 1] }

  init?(path: String?) {
    guard let path else { return nil }
    let fullPath = path.replacingOccurrences(of: "\\", with: "/")
    var components = fullPath.split(separator: "/").map(String.init)
    guard components.count >= 2 else { return nil }
    let file = components.removeLast()
    if let dot = file.lastIndex(of: "."), dot != file.startIndex, file.distance(from: dot, to: file.endIndex) <= 6 {
      components.append(String(file[..<dot]))
    } else {
      components.append(file)
    }
    self.fullPath = fullPath
    stemPath = (fullPath.hasPrefix("/") ? "/" : "") + components.joined(separator: "/")
    tail = components.map { $0.precomposedStringWithCanonicalMapping.lowercased() }
  }

  /// 完整路径优先，其余按从文件名往上连续对上的段数排序。
  func commonSuffixRank(with other: Self) -> Int {
    if fullPath == other.fullPath { return .max }
    return zip(tail.reversed(), other.tail.reversed()).prefix(while: { $0.0 == $0.1 }).count
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
  fileprivate static func day(_ value: String?) -> (text: String, number: Int)? {
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

nonisolated enum EpisodeTitle {
  // 常见占位名不提供身份信息，包括纯集号、数字与常见语言的「第 N 集」。
  private static let placeholder = #"^(?:(?:(?:season|s)\s*[0-9]+[\s:.-]*)?(?:episode|ep|e|part|chapter)\s*[. #:-]*[0-9]+(?:\s*[-–]\s*[0-9]+)?|[0-9零〇一二三四五六七八九十百]+\s*[集話话回章]|[0-9]+\s*(?:화|회))$"#
  private static let generic: Set<String> = ["tba", "tbd", "untitled", "special", "未命名", "特别篇", "特別編"]

  static func normalized(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let title = raw.precomposedStringWithCompatibilityMapping.lowercased()
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: .punctuationCharacters)
    guard title.contains(where: \.isLetter), !generic.contains(title),
      !PlaybackTitles.isPlaceholderEpisodeName(title, episodeNumber: nil),
      title.range(of: placeholder, options: .regularExpression) == nil
    else { return nil }
    return title
  }

  /// 不同文字的译名可能正确；文字相同时，两个具体标题相异就保留日期提示。
  static func conflicts(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs = normalized(lhs), let rhs = normalized(rhs), lhs != rhs else { return false }
    func scripts(_ title: String) -> Set<Int> {
      Set(title.unicodeScalars.compactMap { scalar in
        switch scalar.value {
        case 0x61...0x7A, 0xC0...0x024F: 1
        case 0x3040...0x30FF, 0x31F0...0x31FF: 2
        case 0x3400...0x9FFF, 0x20000...0x323AF: 3
        case 0x1100...0x11FF, 0xAC00...0xD7AF: 4
        case 0x0400...0x052F: 5
        default: nil
        }
      })
    }
    let left = scripts(lhs), right = scripts(rhs)
    return left.isEmpty || right.isEmpty || !left.isDisjoint(with: right)
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
  var hasConsistentSeasonOffset = false
  /// 服务器上这个文件没有资料：没有任何外部编号，也没有首播日期。多半没刮削到，标题就是文件名。
  var serverHasNoMetadata = false
  /// 服务器上的集名和这一集同季唯一的具体标题相同，但不够确认（集名来源不清楚，或编号还没在 TMDB 查空），在面板里供参考。
  var titleMatches = false

  /// 给用户的说明，`server` 是这个文件所在的服务器。
  func message(server: String, allowsSeasonDateOffset: Bool = false) -> String {
    let numbering = episodeGroup == nil ? "季号集号" : "整理时所用剧集组的季号集号"
    let base = "“\(server)”上的文件没有 TMDB 编号，也对不上 MoviePilot 的整理记录，是按\(numbering)找到的第 \(season) 季第 \(episode) 集"
    let titleNote = titleMatches ? "。服务器上的集名和这一集相同，但集名也可能是按季号集号填的，只能作参考" : ""
    return main(base, allowsSeasonDateOffset: allowsSeasonDateOffset) + titleNote
  }

  private func main(_ base: String, allowsSeasonDateOffset: Bool) -> String {
    if allowsSeasonDateOffset && hasConsistentSeasonOffset { return base + "，仍可能不是这一集" }
    switch airDate {
    case .matches:
      return base + "，播出日期也对得上，但仍可能不是这一集"
    case .differs(let serverDate, let moviePilotDate):
      return base + "，但播出日期对不上（服务器上是 \(serverDate)，这一集是 \(moviePilotDate)），很可能不是这一集"
    case .unknown where serverHasNoMetadata:
      return base + "，可能不是这一集。服务器上这个文件没有刮削到资料（没有外部编号和播出日期），"
        + "在媒体服务器上刷新这部剧的元数据后可能就能确认"
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
    var byLookup = 0
    var byTitle = 0
    var bySeasonEpisode = 0
    var airDateMatches = 0
    var airDateDiffers = 0
    /// 有季号集号（或整理记录给了位置），但 MoviePilot 的集列表里没有那一集：这一季不在那套编号里，或集号超出了列表。
    var unplaced = 0
    /// 季号集号缺失或认不出，也没对上整理记录：不知道是哪一集。
    var unidentified = 0

    /// 有文件没带 TMDB 单集编号时的日志说明；都带编号时为 nil。不写路径和编号本身。
    var logText: String? {
      guard byTransferRecord + byLookup + byTitle + bySeasonEpisode + unplaced + unidentified > 0 else { return nil }
      let lookupMatches = byLookup > 0 ? "按外部编号在 TMDB 反查到 \(byLookup) 个，" : ""
      let titleMatches = byTitle > 0 ? "按单集标题核实 \(byTitle) 个，" : ""
      return "按 TMDB 单集编号对上 \(byEpisodeID) 个文件，按整理记录对上 \(byTransferRecord) 个，"
        + lookupMatches + titleMatches
        + "按季号集号对上 \(bySeasonEpisode) 个（播出日期对上 \(airDateMatches) 个、对不上 \(airDateDiffers) 个），"
        + "有季号集号但集列表里没有那一集 \(unplaced) 个，认不出是哪一集 \(unidentified) 个"
    }
  }

  let serverName: String
  /// 这台服务器上找到了这部剧
  let hasSeries: Bool
  /// 确定的对应：TMDB 单集 ID → 有文件的单集条目。带编号的按服务器返回的顺序在前（同一集在多个媒体库里各有一条），
  /// 接着是多集文件覆盖的、按整理记录对上的、按外部编号反查到的和按标题核实的。
  let confirmed: [Int: [ServerMediaItem]]
  /// 按外部编号反查或按标题核实的文件（服务器条目 ID → 依据），起播前按依据复核。
  let confirmedBy: [String: EpisodeConfirmationBasis]
  /// 按季号集号的对应，只留没有确定文件的集。
  let uncertain: [Int: [UncertainFile]]
  /// 认不出是哪一集的文件数：没有 TMDB 单集编号，季号集号缺失或认不出，也没对上整理记录。这部剧没找到的集可能就是其中之一
  /// （见 `availability(of:)`）。有季号集号、只是集列表里没有那一集的文件不算在内：按它自己的编号不会是别的集。
  let unidentifiedFileCount: Int
  /// 带着外部编号、还没能在 TMDB 确定是哪一集的文件数（没查、没查完或查出多集）。这部剧没找到的集可能就是其中之一：
  /// 补查进行中时先不下结论，查完仍没确定的按有认不出的文件处理（见 `availability(of:)`）。
  let unresolvedFileCount: Int
  /// 这部剧在这台服务器上正第一次去 TMDB 核对。
  let lookupInProgress: Bool
  /// 没查清的文件为什么没查清。
  let unverifiedReason: EpisodeAvailability.UnverifiedReason
  /// 没有读全时的失败说明（已写明服务器和操作）：这部剧在这台服务器上有几份（不同媒体库），有的读取失败；
  /// 或按外部编号查找、按 ID 补查、读 MoviePilot 集列表有一步失败。读到的照常用，找不到某一集时不能说这台上没有。
  let incompleteReason: String?
  let summary: Summary

  /// `lists` 是按 `requiredLists(for:records:)` 读到的 MoviePilot 集列表（读不到的不放），
  /// `records` 是这部剧成功的整理记录（已按 TMDB 编号筛过），`evidence` 是文件以外的依据。
  init(
    serverName: String, hasSeries: Bool, episodes: [ServerMediaItem], incompleteReason: String? = nil,
    lists: [EpisodeListKey: [TmdbEpisode]] = [:], records: [EpisodeTransferRecord] = [],
    evidence: EpisodeEvidence = EpisodeEvidence()
  ) {
    self.serverName = serverName
    self.hasSeries = hasSeries
    self.incompleteReason = incompleteReason
    let plan = Plan(episodes: episodes, records: records)
    var confirmed: [Int: [ServerMediaItem]] = [:]
    var uncertain: [Int: [UncertainFile]] = [:]
    var lateMatches: [(file: ServerMediaItem, id: Int, basis: EpisodeConfirmationBasis)] = []
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
    let seasonEvidence = lists.mapValues(SeasonEvidence.init)
    let translated = evidence.translatedSeasons.mapValues { $0.map(SeasonEvidence.init) }
    let filesBySeason = Dictionary(grouping: plan.files, by: SeasonCopy.init)
    let offsets = plan.seasonOffsets(using: seasonEvidence, filesBySeason: filesBySeason)
    let titlesBySeason = filesBySeason.mapValues { files in
      Dictionary(grouping: files.compactMap { file in
        EpisodeTitle.normalized(file.name).map { ($0, file.episodeNumber) }
      }, by: \.0).mapValues { Set($0.map(\.1)) }
    }
    for file in plan.files where file.tmdbEpisodeID == nil {
      switch plan.step(for: file) {
      case .recorded(let placement):
        let ids = placement.episodes.compactMap { Self.episodeID(number: $0, in: lists[placement.list]) }
        if ids.isEmpty {
          summary.unplaced += 1
        } else {
          ids.forEach { confirm(file, as: $0) }
          summary.byTransferRecord += 1
        }
      case .numbered(let key, let range):
        // 外部编号反查到的是 TMDB 自己的对应，两边季号集号不同也以它为准。
        if let found = evidence.lookedUp(file) {
          lateMatches.append((file, found.tmdbEpisodeID, .externalID(source: found.source, value: found.value)))
          summary.byLookup += 1
          continue
        }
        // 没有这份列表：读取失败（记在 `incompleteReason`），或这一季不在那套编号里。
        guard let season = seasonEvidence[key] else {
          summary.unplaced += 1
          continue
        }
        let first = season.episodes[range.lowerBound]
        let copy = SeasonCopy(file)
        // 集名和 MoviePilot 的列表，或 TMDB 其他语言的列表（只有默认顺序）里这一集同季唯一的具体标题相同。
        var titleMatches = false
        if range.count == 1, let first, let id = first.id,
          let title = EpisodeTitle.normalized(file.name), title != EpisodeTitle.normalized(file.seriesName),
          titlesBySeason[copy]?[title] == [file.episodeNumber]
        {
          let others = key.episodeGroup == nil ? translated[key.season] ?? [] : []
          titleMatches = ([season] + others).contains { list in
            guard let candidate = list.episodes[range.lowerBound], candidate.id == id else { return false }
            return list.uniqueTitle(of: candidate) == title
          }
          if titleMatches, evidence.titleCanVerify(file) {
            lateMatches.append((file, id, .title))
            summary.byTitle += 1
            continue
          }
        }
        // 文件的播出日期是它第一集的。
        let airDate = AirDateCheck.compare(server: file.premiereDate, moviePilot: first?.airDate)
        let hasOffset: Bool
        if case .differs = airDate, key.episodeGroup == nil, range.count == 1 {
          hasOffset = offsets.contains(copy)
        } else {
          hasOffset = false
        }
        let hasNoMetadata = file.externalIDs.isEmpty && AirDateCheck.day(file.premiereDate) == nil
        var matched = false
        for number in range {
          guard let id = season.episodes[number]?.id else { continue }
          let match = UncertainEpisodeMatch(
            season: key.season, episode: number, episodeGroup: key.episodeGroup, airDate: airDate,
            hasConsistentSeasonOffset: hasOffset, serverHasNoMetadata: hasNoMetadata, titleMatches: titleMatches)
          uncertain[id, default: []].append(UncertainFile(item: file, match: match))
          matched = true
        }
        guard matched else {
          summary.unplaced += 1
          continue
        }
        summary.bySeasonEpisode += 1
        switch airDate {
        case .matches: summary.airDateMatches += 1
        case .differs: summary.airDateDiffers += 1
        case .unknown: break
        }
      case .unidentified:
        // 认不出季号集号，但编号在 TMDB 反查到了这部剧的一集。
        if let found = evidence.lookedUp(file) {
          lateMatches.append((file, found.tmdbEpisodeID, .externalID(source: found.source, value: found.value)))
          summary.byLookup += 1
        } else {
          summary.unidentified += 1
        }
      }
    }
    for (file, id, _) in lateMatches { confirm(file, as: id) }
    confirmedBy = Dictionary(lateMatches.map { ($0.file.id, $0.basis) }, uniquingKeysWith: { first, _ in first })
    self.confirmed = confirmed
    self.uncertain = uncertain.filter { confirmed[$0.key] == nil }
    unidentifiedFileCount = summary.unidentified
    let placed = Set(confirmed.values.flatMap { $0.map(\.id) })
    unresolvedFileCount = plan.files.filter { file in
      !placed.contains(file.id) && evidence.lookups[file.id]?.leavesFileUnplaced == true
    }.count
    lookupInProgress = evidence.lookupInProgress
    unverifiedReason = evidence.librarySettingsUnknown ? .librarySettingsUnreadable : .lookupIncomplete
    self.summary = summary
  }

  /// 建对应表要读的 MoviePilot 集列表：多集文件、整理记录和季集号兜底需要的列表。
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
      case .unidentified: break
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
    /// 季号或集号缺失，或集号范围大得不像一个文件：不知道是哪一集。
    case unidentified
  }

  private struct SeasonEvidence {
    let episodes: [Int: TmdbEpisode]
    let titleCounts: [String: Int]
    let minimumDateGap: Int?

    init(_ list: [TmdbEpisode]) {
      let numbered = list.compactMap { episode in episode.episodeNumber.map { ($0, episode) } }
      let groups = Dictionary(grouping: numbered, by: \.0)
      episodes = groups.compactMapValues { entries in entries.count == 1 ? entries.first?.1 : nil }
      titleCounts = Dictionary(grouping: list.compactMap { EpisodeTitle.normalized($0.name) }, by: { $0 }).mapValues(\.count)
      let dates = list.compactMap { AirDateCheck.day($0.airDate)?.number }.sorted()
      minimumDateGap = zip(dates, dates.dropFirst()).map { $1 - $0 }.min()
    }

    func uniqueTitle(of episode: TmdbEpisode) -> String? {
      guard let title = EpisodeTitle.normalized(episode.name), titleCounts[title] == 1 else { return nil }
      return title
    }
  }

  private struct SeasonCopy: Hashable {
    let seriesID: String?
    let season: Int?

    init(_ file: ServerMediaItem) {
      seriesID = trimmedNonEmpty([file.seriesID])
      season = file.seasonNumber
    }
  }

  /// 每个没有编号的文件走哪一步。`requiredLists` 和建表共用，读的列表和用的列表一致。
  private struct Plan {
    let files: [ServerMediaItem]
    /// 服务器条目 ID → 整理记录里的位置。
    let placements: [String: EpisodePlacement]
    let numberingGroup: String?

    init(episodes: [ServerMediaItem], records: [EpisodeTransferRecord]) {
      files = episodes.filter(\.hasFile)
      numberingGroup = ServerEpisodeIndex.numberingGroup(records)
      let recordsWithPaths = records.compactMap { record -> Record? in
        guard let path = EpisodeFilePath(path: record.path), let placement = record.placement else { return nil }
        return Record(path: path, placement: placement)
      }
      guard !recordsWithPaths.isEmpty else {
        placements = [:]
        return
      }
      let paths = files.compactMap { file in
        EpisodeFilePath(path: file.path).map { File(item: file, path: $0) }
      }
      let byFilename = Dictionary(grouping: paths, by: \.path.filename).mapValues {
        Dictionary(grouping: $0, by: \.path.stemPath)
      }
      placements = Self.matchRecords(recordsWithPaths, byFilename: byFilename)
    }

    private struct File {
      let item: ServerMediaItem
      let path: EpisodeFilePath
    }

    private struct Record {
      let path: EpisodeFilePath
      let placement: EpisodePlacement
    }

    private struct RecordMatch {
      let rank: Int
      let placement: EpisodePlacement?
    }

    /// 同一目录的同名版本共享整理记录；不同目录的候选要能分出强弱。
    /// 强匹配有冲突时不退回更短的路径；同一位置的重复历史可以一起印证。
    private static func matchRecords(_ records: [Record], byFilename: [String: [String: [File]]]) -> [String: EpisodePlacement] {
      var bestByFile: [String: RecordMatch] = [:]
      for record in records {
        guard let copies = byFilename[record.path.filename] else { continue }
        let ranks = copies.compactMapValues { files -> Int? in
          guard let rank = files.map({ $0.path.commonSuffixRank(with: record.path) }).max(), rank >= 2 else { return nil }
          return rank
        }
        guard let strongest = ranks.values.max() else { continue }
        let unique = ranks.values.filter { $0 == strongest }.count == 1
        for (stem, rank) in ranks {
          let proposed = rank == strongest && unique ? record.placement : nil
          for file in copies[stem] ?? [] {
            let id = file.item.id
            if let current = bestByFile[id], current.rank >= rank {
              if current.rank == rank, current.placement != proposed {
                bestByFile[id] = RecordMatch(rank: rank, placement: nil)
              }
            } else {
              bestByFile[id] = RecordMatch(rank: rank, placement: proposed)
            }
          }
        }
      }
      return bestByFile.compactMapValues(\.placement)
    }

    func step(for file: ServerMediaItem) -> Step {
      if let placement = placements[file.id] { return .recorded(placement) }
      guard let season = file.seasonNumber, let first = file.episodeNumber else { return .unidentified }
      let last = max(file.episodeNumberEnd ?? first, first)
      guard last - first < EpisodeTransferRecord.maximumEpisodesPerFile else { return .unidentified }
      return .numbered(EpisodeListKey(episodeGroup: numberingGroup, season: season), first...last)
    }

    func seasonOffsets(
      using seasons: [EpisodeListKey: SeasonEvidence], filesBySeason: [SeasonCopy: [ServerMediaItem]]
    ) -> Set<SeasonCopy> {
      guard numberingGroup == nil else { return [] }
      return Set(filesBySeason.compactMap { copy, entries in
        guard copy.seriesID != nil, let season = copy.season, season > 0 else { return nil }
        let key = EpisodeListKey(episodeGroup: nil, season: season)
        guard let evidence = seasons[key], let gap = evidence.minimumDateGap, gap > 4 else { return nil }
        var datedEpisodes: Set<Int> = []
        var offsets: Set<Int> = []
        for file in entries {
          let date = AirDateCheck.day(file.premiereDate)
          guard let number = file.episodeNumber, let episode = evidence.episodes[number], let id = episode.id,
            file.episodeNumberEnd == nil || file.episodeNumberEnd == number
          else {
            if date != nil { return nil }
            continue
          }
          if let idOnFile = file.tmdbEpisodeID, idOnFile != id { return nil }
          if let placement = placements[file.id], placement.list != key || placement.episodes != [number] { return nil }
          if EpisodeTitle.conflicts(file.name, episode.name) { return nil }
          guard let date else { continue }
          guard let tmdbDate = AirDateCheck.day(episode.airDate) else { return nil }
          let delta = date.number - tmdbDate.number
          guard (2...3).contains(abs(delta)), 2 * abs(delta) < gap else { return nil }
          offsets.insert(delta)
          datedEpisodes.insert(number)
        }
        return offsets.count == 1 && datedEpisodes.count >= 3 ? copy : nil
      })
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
  /// `basis` 是对应表按外部编号反查或按标题核实时的依据（见 `confirmedBy`），复核时它也不能变。
  static func recheck(
    _ fresh: ServerMediaItem, recorded: ServerMediaItem?, tmdbEpisodeID: Int, basis: EpisodeConfirmationBasis? = nil
  ) -> Recheck {
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
    switch basis {
    case .title:
      guard fresh.hasFile, fresh.seriesID == recorded.seriesID,
        let title = EpisodeTitle.normalized(fresh.name), title == EpisodeTitle.normalized(recorded.name)
      else { return .changed }
    case .externalID(let source, let value):
      guard fresh.hasFile, fresh.seriesID == recorded.seriesID, fresh.externalIDs[source] == value else { return .changed }
    case nil:
      break
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
  /// - 有带编号的文件第一次在向 TMDB 核对：这一集可能就是其中之一，先不下结论（`checking`，不能试看），核对完自动更新。
  /// - 有带编号的文件没核对成：这一集可能就是其中之一（`unverified`），试看前在面板里说明原因。
  /// - 有认不出是哪一集的文件：这一集可能就是其中之一（`unmatched`），试看前在面板里说明，可以刷新元数据。
  /// - 其他：确认没有（`notOnServer`）。有季号集号、只是集列表里没有那一集、编号在 TMDB 也明确查空的文件不影响别的集。
  func availability(of tmdbEpisodeID: Int) -> EpisodeAvailability {
    if !confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID).isEmpty { return .playable(server: serverName) }
    if let file = uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).first {
      return .uncertain(server: serverName, match: file.match)
    }
    if let incompleteReason { return .failed(incompleteReason) }
    if unresolvedFileCount > 0 {
      if lookupInProgress { return .checking(server: serverName, files: unresolvedFileCount) }
      return .unverified(server: serverName, reason: unverifiedReason)
    }
    if unidentifiedFileCount > 0 { return .unmatched(server: serverName) }
    return .notOnServer
  }
}

// MARK: - 读取

/// 建对应表要用的 MoviePilot 数据，按需读取。
struct EpisodeMatchingSources {
  /// 一份 MoviePilot 集列表
  let seasonList: @MainActor (EpisodeListKey) async throws -> [TmdbEpisode]
  /// 一套编号有哪几季：`episodeGroup` 为 nil 是默认顺序（TMDB 季号），否则是那个剧集组（组内季号）。
  /// MoviePilot 读 TMDB 失败时返回空列表。
  let seasons: (_ episodeGroup: String?) async throws -> [Int]
  /// 这部剧成功的整理记录（已按 TMDB 编号筛过）
  let transferRecords: () async throws -> [EpisodeTransferRecord]
  /// 文件以外的依据（见 `EpisodeEvidence`）：`local` 是只用本地数据建的对应表。只给本机已有的，马上返回，不等任何外部请求；
  /// 缺的由提供方在后台补，补完自己通知刷新。
  var evidence: ((_ episodes: [ServerMediaItem], _ local: ServerEpisodeIndex) async -> EpisodeEvidence)?

  init(
    seasonList: @escaping @MainActor (EpisodeListKey) async throws -> [TmdbEpisode],
    seasons: @escaping (_ episodeGroup: String?) async throws -> [Int],
    transferRecords: @escaping () async throws -> [EpisodeTransferRecord],
    evidence: ((_ episodes: [ServerMediaItem], _ local: ServerEpisodeIndex) async -> EpisodeEvidence)? = nil
  ) {
    self.seasonList = seasonList
    self.seasons = seasons
    self.transferRecords = transferRecords
    self.evidence = evidence
  }
}

enum EpisodeMatchLoader {
  /// 一台服务器上这部剧的对应表。`episodes` 是从服务器读到的这部剧的全部集，`incompleteReason` 是读服务器时没读全的说明。
  /// 有文件没带 TMDB 单集编号时才读整理记录。未确认的文件按季集号查找，用日期核对；再合上文件以外的依据（本机已有的
  /// 媒体库配置和 TMDB 补查结果，不等网络）重新建表。
  /// 集列表读不到时那一季的文件无法对应，记为没读全。集列表是空的有两种可能：MoviePilot 读 TMDB 失败（过一会儿可能就好），
  /// 或那套编号里根本没有这一季（比如 TMDB 没有第 0 季而服务器上有特别篇，或服务器按 TVDB 分季）。这时再读那套编号的季列表：
  /// 季列表里确实没有这一季，这一季的文件按集列表里没有那一集处理，不影响别的集；季列表里有这一季或也读不到，才算没读全。
  /// `describe` 把错误转成给用户看的说明。
  static func index(
    serverName: String, hasSeries: Bool, episodes: [ServerMediaItem], incompleteReason: String?,
    sources: EpisodeMatchingSources, describe: (Error) -> String
  ) async throws -> ServerEpisodeIndex {
    var records: [EpisodeTransferRecord] = []
    let hasUnnumberedFiles = episodes.contains { $0.hasFile && $0.tmdbEpisodeID == nil }
    if hasUnnumberedFiles {
      do {
        records = try await sources.transferRecords()
      } catch let error where !(error is CancellationError) {
        Logger.warning("[Playback] 没能读取 MoviePilot 的整理记录，将尝试其他单集匹配依据: \(describe(error))")
      }
    }
    var lists: [EpisodeListKey: [TmdbEpisode]] = [:]
    var listFailure: String?
    var absentSeasons: [EpisodeListKey] = []
    /// 每套编号的季列表只读一次（键是剧集组，默认顺序为空串）；读不到记为空集合。
    var seasonCatalogs: [String: Set<Int>] = [:]
    let required = await requiredLists(episodes: episodes, records: records)
    for key in required.sorted() {
      let list: [TmdbEpisode]
      do {
        list = try await sources.seasonList(key)
      } catch let error where !(error is CancellationError) {
        listFailure = listFailure ?? "没能从 MoviePilot 读取\(key.title)的集列表，无法对应这一季的文件：\(describe(error))"
        continue
      }
      guard list.isEmpty else {
        lists[key] = list
        continue
      }
      let numbering = key.episodeGroup ?? ""
      if seasonCatalogs[numbering] == nil {
        do {
          seasonCatalogs[numbering] = Set(try await sources.seasons(key.episodeGroup))
        } catch let error where !(error is CancellationError) {
          Logger.warning("[Playback] 没能从 MoviePilot 读取季列表，分不清\(key.title)是不存在还是没读到: \(describe(error))")
          seasonCatalogs[numbering] = []
        }
      }
      if let seasons = seasonCatalogs[numbering], !seasons.isEmpty, !seasons.contains(key.season) {
        absentSeasons.append(key)
      } else {
        listFailure = listFailure ?? "MoviePilot 返回的\(key.title)集列表是空的，无法对应这一季的文件"
      }
    }
    if !absentSeasons.isEmpty {
      Logger.info(
        "[Playback] “\(serverName)”上有文件所在的季在 MoviePilot 的编号里没有（\(absentSeasons.map(\.title).joined(separator: "、"))），"
          + "这些文件按集列表里没有那一集处理")
    }
    if let listFailure {
      Logger.warning("[Playback] “\(serverName)”上这部剧没有读全: \(listFailure)")
    }
    try Task.checkCancellation()
    var index = await buildIndex(
      serverName: serverName, hasSeries: hasSeries, episodes: episodes,
      incompleteReason: incompleteReason ?? listFailure, lists: lists, records: records, evidence: EpisodeEvidence())
    if hasUnnumberedFiles, let provide = sources.evidence {
      let evidence = await provide(episodes, index)
      try Task.checkCancellation()
      if !evidence.isEmpty {
        index = await buildIndex(
          serverName: serverName, hasSeries: hasSeries, episodes: episodes,
          incompleteReason: incompleteReason ?? listFailure, lists: lists, records: records, evidence: evidence)
      }
    }
    if let summary = index.summary.logText {
      Logger.info("[Playback] “\(serverName)”上这部剧（整理记录 \(records.count) 条）：\(summary)")
    }
    return index
  }

  @concurrent
  private static func requiredLists(episodes: [ServerMediaItem], records: [EpisodeTransferRecord]) async -> Set<EpisodeListKey> {
    ServerEpisodeIndex.requiredLists(for: episodes, records: records)
  }

  @concurrent
  private static func buildIndex(
    serverName: String, hasSeries: Bool, episodes: [ServerMediaItem], incompleteReason: String?,
    lists: [EpisodeListKey: [TmdbEpisode]], records: [EpisodeTransferRecord], evidence: EpisodeEvidence
  ) async -> ServerEpisodeIndex {
    ServerEpisodeIndex(
      serverName: serverName, hasSeries: hasSeries, episodes: episodes, incompleteReason: incompleteReason,
      lists: lists, records: records, evidence: evidence)
  }
}

/// MoviePilot 记录里的文件（`dest_fileitem` 等），只取路径。路径读不出时为 nil，不影响记录的其他字段。
nonisolated struct MoviePilotFileItem: Decodable, Sendable {
  let path: String?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try? container.decodeIfPresent(String.self, forKey: .path)
  }

  private enum CodingKeys: String, CodingKey { case path }
}
