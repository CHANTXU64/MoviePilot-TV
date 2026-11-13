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

/// 一个文件按单集外部编号在 TMDB 反查的结果。
nonisolated enum EpisodeLookupOutcome: Equatable, Sendable {
  /// 反查到这部剧唯一的一集：以它为准。
  case found(ExternalEpisodeMatch)
  /// 每个编号都明确查空：TMDB 没收录对应关系，这时才考虑用标题核实。
  case notFound
  /// 反查到这部剧的不止一集，或编号指向别的剧：对应关系有歧义或身份冲突，不能确定是哪一集。
  case ambiguous
  /// 还没查过、请求失败、限流或到时间没查：不知道是哪一集。
  case unresolved

  /// 没能确定这个文件是哪一集：没找到的集可能就是它。
  var leavesFileUnplaced: Bool { self == .ambiguous || self == .unresolved }
}

/// 文件和 MoviePilot 数据之外的单集依据，建对应表时按服务器条目 ID 查。只来自本机已有的数据（缓存的媒体库配置和 TMDB 补查结果），
/// 建表不等任何外部请求；缺的由后台一轮补查补上，补完重建。
nonisolated struct EpisodeEvidence: Equatable, Sendable {
  /// 单集资料不是从 TMDB 取的文件（见 `MediaLibraryProfile.independentFiles`）。只有这些文件的外部编号和标题
  /// 能拿来和 TMDB 核对；来源含 TMDB 或还没读到媒体库配置时，只按季号集号对应，播放前说明。
  var independentFiles: Set<String> = []
  /// 补查过的文件：服务器条目 ID → 反查结果。没列出的文件没有可反查的编号，或不在补查范围内。
  var lookups: [String: EpisodeLookupOutcome] = [:]
  /// TMDB 其他语言的季列表：默认顺序的季号 → 各语言的集列表。服务器上的标题常是英文或原语言的，MoviePilot 的是中文。
  var translatedSeasons: [Int: [[TmdbEpisode]]] = [:]
  /// 这部剧在这台服务器上正第一次去 TMDB 核对：还没确定是哪一集的文件可能就是没找到的那些集，先别下结论。
  /// 之后的重查在后台进行，不挡试看（没查成的按“可能已有”说明）。
  var lookupInProgress = false
  /// 没能读到这台服务器的媒体库配置：`lookups` 里的 `unresolved` 是因为没法核对，不是 TMDB 没查成。
  var librarySettingsUnknown = false

  init(
    independentFiles: Set<String> = [], lookups: [String: EpisodeLookupOutcome] = [:],
    translatedSeasons: [Int: [[TmdbEpisode]]] = [:], lookupInProgress: Bool = false,
    librarySettingsUnknown: Bool = false
  ) {
    self.independentFiles = independentFiles
    self.lookups = lookups
    self.translatedSeasons = translatedSeasons
    self.lookupInProgress = lookupInProgress
    self.librarySettingsUnknown = librarySettingsUnknown
  }

  var isEmpty: Bool { independentFiles.isEmpty && lookups.isEmpty && translatedSeasons.isEmpty && !lookupInProgress }

  /// 反查到的这部剧的一集；单集资料可能来自 TMDB 的文件不算（编号可能是 TMDB 按季号集号给的）。
  func lookedUp(_ file: ServerMediaItem) -> ExternalEpisodeMatch? {
    guard independentFiles.contains(file.id), case .found(let match)? = lookups[file.id] else { return nil }
    return match
  }

  /// 这个文件的标题能拿来核实：单集资料不是从 TMDB 取的、条目带着 TVDB 单集编号，而且编号在 TMDB 明确查空。
  /// 编号优先于标题：标题可能来自以前开着 TMDB 刮的旧条目或第三方工具按 TMDB 写的 NFO，编号能查到就以编号为准；
  /// 超时、限流、查出多集时都不用标题确认。
  func titleCanVerify(_ file: ServerMediaItem) -> Bool {
    independentFiles.contains(file.id) && file.externalIDs["tvdb"] != nil && lookups[file.id] == .notFound
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

/// 建好本地对应表后，哪些文件要去 TMDB 补查。
nonisolated struct ExternalEvidenceRequest: Equatable, Sendable {
  struct Candidate: Equatable, Sendable {
    let itemID: String
    /// 能反查的单集外部编号，按优先顺序：(规范来源, 编号)
    let externalIDs: [(source: String, value: String)]
    /// 编号查空后要核对其他语言标题时的默认顺序季号；文件没有具体标题、没有 TVDB 单集编号或按剧集组编号时为 nil。
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

  /// 带着单集外部编号、还没靠文件编号或整理记录确定的文件都查，包括季号集号对不上任何一集、认不出是哪一集的
  /// （季号集号差得越远越要靠编号）。`independentFiles` 为 nil 时还不知道媒体库配置，先按都可能要查挑出来（用于判断
  /// 一轮补查进行中哪些文件还没确定）。只挑只含一集的文件。没有可补查的时为 nil。
  /// `local` 是不带任何补查依据建的对应表：按标题确认过的也要查，编号能纠正标题。
  init?(tmdbID: Int, episodes: [ServerMediaItem], local: ServerEpisodeIndex, independentFiles: Set<String>?) {
    let settled = Set(local.confirmed.values.flatMap { $0.map(\.id) })
    var titleSeasons: [String: Int] = [:]
    for files in local.uncertain.values {
      for uncertain in files where uncertain.match.episodeGroup == nil {
        titleSeasons[uncertain.item.id] = uncertain.match.season
      }
    }
    var seen: Set<String> = []
    var candidates: [Candidate] = []
    for file in episodes {
      guard file.hasFile, file.tmdbEpisodeID == nil, !settled.contains(file.id),
        independentFiles?.contains(file.id) ?? true, seen.insert(file.id).inserted,
        file.episodeNumberEnd == nil || file.episodeNumberEnd == file.episodeNumber
      else { continue }
      let ids = Self.lookupSources.compactMap { source in file.externalIDs[source].map { (source, $0) } }
      guard !ids.isEmpty else { continue }
      let titled = file.externalIDs["tvdb"] != nil && EpisodeTitle.normalized(file.name) != nil
      candidates.append(Candidate(itemID: file.id, externalIDs: ids, titleSeason: titled ? titleSeasons[file.id] : nil))
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
  /// 每个候选文件的反查结果
  var lookups: [String: EpisodeLookupOutcome] = [:]
  var translatedSeasons: [Int: [[TmdbEpisode]]] = [:]
  /// 该查的都有了答案：每个文件都查到或明确查空（有歧义也算有答案），编号查空要比标题的季列表也取到了。
  /// 只读缓存时没查过的、请求失败、限流或到时间没查的都算没查全。
  var isComplete = true
}
