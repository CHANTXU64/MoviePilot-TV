import Foundation

// 单集对应在文件和 MoviePilot 数据之外用到的依据：服务器单集资料的来源、TMDB 反查和其他语言的标题。
// 对应规则见 `EpisodeMatching.swift`。

// MARK: - 服务器单集资料的来源

/// 一个媒体库的文件夹和单集元数据来源，用来判断服务器上的单集资料是不是从 TMDB 来的。
nonisolated struct MediaLibraryProfile: Equatable, Sendable {
  /// 服务器看到的文件夹路径
  let paths: [String]
  /// 单集启用的在线元数据来源（Emby `LibraryOptions.TypeOptions` 里 `Episode` 的 `MetadataFetchers`）。
  /// 配置里没有单集这一项时为 nil：服务器按默认来源刮削，默认来源里有 TMDB。
  let episodeFetchers: [String]?

  init(paths: [String], episodeFetchers: [String]?) {
    self.paths = paths
    self.episodeFetchers = episodeFetchers
  }

  /// 单集资料可能来自 TMDB：没有单集配置，或启用的来源里有 TheMovieDb。
  var mayUseTmdbForEpisodes: Bool {
    guard let episodeFetchers else { return true }
    return episodeFetchers.contains { name in
      let key = name.lowercased().filter { $0.isLetter }
      return key.contains("moviedb") || key == "tmdb"
    }
  }

  /// 单集资料不是从 TMDB 取的文件（服务器条目 ID）。服务器在线刮削单集时按季号集号去问来源，来源是 TMDB 时，
  /// 服务器上的标题和外部编号就是 TMDB 按同一组季号集号给的，拿来和 TMDB 核对证明不了什么。
  /// 文件要落在至少一个媒体库的文件夹里；同一个文件夹可以加进几个媒体库，这时每个库的单集来源都不能含 TMDB。
  /// 路径缺失或哪个库都不在时按来源不明处理，不放进来。
  static func independentFiles(_ files: [ServerMediaItem], in libraries: [MediaLibraryProfile]) -> Set<String> {
    let roots = libraries.map { library in
      (prefixes: library.paths.map(components).filter { !$0.isEmpty }, usesTmdb: library.mayUseTmdbForEpisodes)
    }
    var result: Set<String> = []
    for file in files {
      guard let path = file.path else { continue }
      let target = components(path)
      let owners = roots.filter { root in root.prefixes.contains { target.count > $0.count && target.starts(with: $0) } }
      if !owners.isEmpty, owners.allSatisfy({ !$0.usesTmdb }) { result.insert(file.id) }
    }
    return result
  }

  private static func components(_ path: String) -> [Substring] {
    path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
  }
}

// MARK: - 文件以外的依据

/// 按单集外部编号在 TMDB 反查到的这部剧的一集。
nonisolated struct ExternalEpisodeMatch: Equatable, Sendable {
  let tmdbEpisodeID: Int
  /// 用来反查的编号：规范来源（`tvdb`、`imdb`）和编号。起播前核对条目上的这个编号没变。
  let source: String
  let value: String
}

/// 文件和 MoviePilot 数据之外的单集依据，建对应表时按服务器条目 ID 查。
nonisolated struct EpisodeEvidence: Equatable, Sendable {
  /// 单集资料不是从 TMDB 取的文件（见 `MediaLibraryProfile.independentFiles`）。只有这些文件的标题和外部编号
  /// 能拿来和 TMDB 核对；来源含 TMDB 或读不到媒体库配置时，只按季号集号对应，播放前说明。
  /// 按标题核实还要条目带着 TVDB 单集编号（见 `titleCanVerify`）。
  var independentFiles: Set<String> = []
  /// 按单集外部编号在 TMDB 反查到的：服务器条目 ID → 这部剧的一集。
  var lookedUp: [String: ExternalEpisodeMatch] = [:]
  /// TMDB 其他语言的季列表：默认顺序的季号 → 各语言的集列表。服务器上的标题常是英文或原语言的，MoviePilot 的是中文。
  var translatedSeasons: [Int: [[TmdbEpisode]]] = [:]

  init(
    independentFiles: Set<String> = [], lookedUp: [String: ExternalEpisodeMatch] = [:],
    translatedSeasons: [Int: [[TmdbEpisode]]] = [:]
  ) {
    self.independentFiles = independentFiles
    self.lookedUp = lookedUp
    self.translatedSeasons = translatedSeasons
  }

  /// 这个文件的标题能拿来核实：单集资料不是从 TMDB 取的，而且条目带着 TVDB 单集编号。媒体库现在的设置只说明
  /// 现在不从 TMDB 刮；以前开着 TMDB 刮的旧条目、第三方工具按 TMDB 写的 NFO，标题仍可能是 TMDB 按同一组季号集号给的。
  /// 带着 TVDB 单集编号说明这个条目确实经过 TVDB 刮削。
  func titleCanVerify(_ file: ServerMediaItem) -> Bool {
    independentFiles.contains(file.id) && file.externalIDs["tvdb"] != nil
  }
}

/// 确定对应里不靠文件编号和整理记录的那些，起播前按各自的依据复核（见 `ServerEpisodeIndex.recheck`）。
nonisolated enum EpisodeConfirmationBasis: Equatable, Sendable {
  /// 服务器上的标题和 TMDB 同季唯一的标题一致：起播前标题不能变。
  case title
  /// 外部编号在 TMDB 反查到了这一集：起播前这个编号不能变。
  case externalID(source: String, value: String)
}

// MARK: - 去 TMDB 补查

/// 建好本地对应表后，还只按季号集号对上的文件里，哪些值得去 TMDB 补查。
nonisolated struct ExternalEvidenceRequest: Equatable, Sendable {
  struct Candidate: Equatable, Sendable {
    let itemID: String
    /// 能反查的单集外部编号，按优先顺序：(规范来源, 编号)
    let externalIDs: [(source: String, value: String)]
    /// 要核对其他语言标题时的默认顺序季号；文件没有具体标题或按剧集组编号时为 nil。
    let titleSeason: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.itemID == rhs.itemID && lhs.titleSeason == rhs.titleSeason
        && lhs.externalIDs.map(\.source) == rhs.externalIDs.map(\.source)
        && lhs.externalIDs.map(\.value) == rhs.externalIDs.map(\.value)
    }
  }

  /// 这部剧的 TMDB 编号
  let tmdbID: Int
  let candidates: [Candidate]

  /// 能反查的外部编号来源，按优先顺序。TVDB 的单集编号最常见；IMDb 的少，TMDB 也常没收录。
  static let lookupSources = ["tvdb", "imdb"]

  /// 还没确定对应的文件都挑，包括季号集号对不上任何一集、认不出是哪一集的：季号集号差得越远越要靠编号反查。
  /// 只挑单集资料不是从 TMDB 取的、只含一集的文件。按标题核对只给按季号集号对上了一集（默认顺序）的文件。
  /// 没有可补查的时为 nil。
  init?(tmdbID: Int, episodes: [ServerMediaItem], index: ServerEpisodeIndex, evidence: EpisodeEvidence) {
    let confirmedFiles = Set(index.confirmed.values.flatMap { $0.map(\.id) })
    var titleSeasons: [String: Int] = [:]
    for files in index.uncertain.values {
      for uncertain in files where uncertain.match.episodeGroup == nil {
        titleSeasons[uncertain.item.id] = uncertain.match.season
      }
    }
    var seen: Set<String> = []
    var candidates: [Candidate] = []
    for file in episodes {
      guard file.hasFile, file.tmdbEpisodeID == nil, !confirmedFiles.contains(file.id),
        evidence.independentFiles.contains(file.id), seen.insert(file.id).inserted,
        file.episodeNumberEnd == nil || file.episodeNumberEnd == file.episodeNumber
      else { continue }
      let ids = Self.lookupSources.compactMap { source in file.externalIDs[source].map { (source, $0) } }
      let titleSeason =
        evidence.titleCanVerify(file) && EpisodeTitle.normalized(file.name) != nil ? titleSeasons[file.id] : nil
      guard !ids.isEmpty || titleSeason != nil else { continue }
      candidates.append(Candidate(itemID: file.id, externalIDs: ids, titleSeason: titleSeason))
    }
    guard !candidates.isEmpty else { return nil }
    self.tmdbID = tmdbID
    self.candidates = candidates
  }

  init(tmdbID: Int, candidates: [Candidate]) {
    self.tmdbID = tmdbID
    self.candidates = candidates
  }
}

/// 去 TMDB 补查的结果，合进 `EpisodeEvidence`。
nonisolated struct ExternalEvidenceResult: Equatable, Sendable {
  var lookedUp: [String: ExternalEpisodeMatch] = [:]
  var translatedSeasons: [Int: [[TmdbEpisode]]] = [:]
  /// 该查的都有了答案（查到或确定查不到）。只读缓存时没查过的、请求失败、限流或到时间没查的都算没查全。
  var isComplete = true

  var isEmpty: Bool { lookedUp.isEmpty && translatedSeasons.isEmpty }

  /// 比 `other` 多查到了东西：多反查到文件，或多取到了季列表。
  func adds(to other: Self) -> Bool {
    func lists(_ result: Self) -> Int { result.translatedSeasons.values.reduce(0) { $0 + $1.count } }
    return lookedUp.count > other.lookedUp.count || lists(self) > lists(other)
  }
}
