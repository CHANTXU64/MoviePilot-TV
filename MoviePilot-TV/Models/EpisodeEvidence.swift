import Foundation

// 单集对应在文件和 MoviePilot 数据之外用到的依据：服务器单集资料的来源、TMDB 反查和其他语言的标题、用户的确认。
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
  var independentFiles: Set<String> = []
  /// 按单集外部编号在 TMDB 反查到的：服务器条目 ID → 这部剧的一集。
  var lookedUp: [String: ExternalEpisodeMatch] = [:]
  /// TMDB 其他语言的季列表：默认顺序的季号 → 各语言的集列表。服务器上的标题常是英文或原语言的，MoviePilot 的是中文。
  var translatedSeasons: [Int: [[TmdbEpisode]]] = [:]
  /// 用户在单集面板里确认过的文件：服务器条目 ID → TMDB 单集 ID（路径已核对过没变）。
  var userConfirmed: [String: Int] = [:]

  init(
    independentFiles: Set<String> = [], lookedUp: [String: ExternalEpisodeMatch] = [:],
    translatedSeasons: [Int: [[TmdbEpisode]]] = [:], userConfirmed: [String: Int] = [:]
  ) {
    self.independentFiles = independentFiles
    self.lookedUp = lookedUp
    self.translatedSeasons = translatedSeasons
    self.userConfirmed = userConfirmed
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

  /// 只挑单集资料不是从 TMDB 取的、只含一集的文件。没有可补查的时为 nil。
  init?(tmdbID: Int, index: ServerEpisodeIndex, evidence: EpisodeEvidence) {
    var seen: Set<String> = []
    var candidates: [Candidate] = []
    for (_, files) in index.uncertain.sorted(by: { $0.key < $1.key }) {
      for uncertain in files {
        let file = uncertain.item
        guard evidence.independentFiles.contains(file.id), seen.insert(file.id).inserted,
          file.episodeNumberEnd == nil || file.episodeNumberEnd == file.episodeNumber
        else { continue }
        let ids = Self.lookupSources.compactMap { source in file.externalIDs[source].map { (source, $0) } }
        let titleSeason =
          uncertain.match.episodeGroup == nil && EpisodeTitle.normalized(file.name) != nil ? uncertain.match.season : nil
        guard !ids.isEmpty || titleSeason != nil else { continue }
        candidates.append(Candidate(itemID: file.id, externalIDs: ids, titleSeason: titleSeason))
      }
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

  var isEmpty: Bool { lookedUp.isEmpty && translatedSeasons.isEmpty }
}

// MARK: - 用户的确认

/// 用户在单集面板里确认过的一个文件。
nonisolated struct EpisodeUserConfirmation: Codable, Equatable, Sendable {
  let tmdbEpisodeID: Int
  /// 确认时服务器看到的文件路径；换了文件（洗版、重新整理）路径就变了，确认随之失效。
  let path: String?
  let confirmedAt: Date
}
