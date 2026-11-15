import XCTest

@testable import MoviePilot_TV

/// 详情页剧的「继续播放」决策表（`SeriesContinuation.choose`）：每种观看记录 × 文件在集索引里的对应，按下做什么。
/// 集索引用真实的对应规则建（整理记录、剧集组、单集编号、季号集号加播出日期），不手写对应结果。
final class SeriesContinuationTests: XCTestCase {
  // MARK: 替身

  /// 默认顺序第 1 季：第 1–6 集是 TMDB 101–106，第 n 集 2025-01-0n 播出。
  private let season1: [TmdbEpisode] = (1...6).map {
    TmdbEpisode(id: 100 + $0, episodeNumber: $0, seasonNumber: 1, airDate: "2025-01-0\($0)")
  }
  /// 默认顺序第 2 季：第 1、2 集是 201、202，2025-02-0n 播出。
  private let season2: [TmdbEpisode] = (1...2).map {
    TmdbEpisode(id: 200 + $0, episodeNumber: $0, seasonNumber: 2, airDate: "2025-02-0\($0)")
  }
  /// 特别篇第 1、2 集是 901、902。
  private let specials = [
    TmdbEpisode(id: 901, episodeNumber: 1, seasonNumber: 0, airDate: "2024-12-01"),
    TmdbEpisode(id: 902, episodeNumber: 2, seasonNumber: 0, airDate: "2024-12-02"),
  ]
  /// 剧集组 g1 第 1 季：组内第 1、2 集是默认顺序的第 4、5 集（104、105）。
  private let groupSeason1: [TmdbEpisode] = [
    TmdbEpisode(id: 104, episodeNumber: 1, seasonNumber: 1, airDate: "2025-01-04"),
    TmdbEpisode(id: 105, episodeNumber: 2, seasonNumber: 1, airDate: "2025-01-05"),
  ]

  private var seasons: [SeriesContinuation.Season] {
    [
      .init(number: 1, episodes: MoviePilotEpisode.list(season1, season: 1)),
      .init(number: 2, episodes: MoviePilotEpisode.list(season2, season: 2)),
      .init(number: 0, episodes: MoviePilotEpisode.list(specials, season: 0)),
    ]
  }

  private func episode(_ season: Int, _ number: Int) -> MoviePilotEpisode {
    seasons.first { $0.number == season }!.episodes.first { $0.episodeNumber == number }!
  }

  private func seasonList(_ season: Int) -> [MoviePilotEpisode] {
    seasons.first { $0.number == season }!.episodes
  }

  private func file(
    _ id: String, season: Int? = 1, episode: Int?, end: Int? = nil, tmdb: Int? = nil, path: String? = nil,
    premiere: String? = nil
  ) -> ServerMediaItem {
    ServerMediaItem(
      id: id, kind: .episode, seasonNumber: season, episodeNumber: episode, episodeNumberEnd: end,
      externalIDs: tmdb.map { ["tmdb": String($0)] } ?? [:], path: path, premiereDate: premiere)
  }

  private func index(
    _ files: [ServerMediaItem], records: [EpisodeTransferRecord] = [], evidence: EpisodeEvidence = EpisodeEvidence()
  ) -> ServerEpisodeLookup {
    .loaded(
      ServerEpisodeIndex(
        serverName: "emby", hasSeries: true, episodes: files,
        lists: [
          EpisodeListKey(episodeGroup: nil, season: 1): season1,
          EpisodeListKey(episodeGroup: nil, season: 2): season2,
          EpisodeListKey(episodeGroup: nil, season: 0): specials,
          EpisodeListKey(episodeGroup: "g1", season: 1): groupSeason1,
        ],
        records: records, evidence: evidence))
  }

  /// 这些文件的外部编号在 TMDB 指向别的剧。
  private func pointingElsewhere(_ ids: String...) -> EpisodeEvidence {
    EpisodeEvidence(
      independentFiles: Set(ids), lookups: Dictionary(uniqueKeysWithValues: ids.map { ($0, .conflicting) }))
  }

  /// `unread` 是应有、但这次没读到的季（季 3 不在替身里，用来表示「后面还有一季没读到」）；
  /// `catalogComplete` 为 false 时 MoviePilot 的季列表本身没读到。
  private func choose(
    _ files: [ServerMediaItem], resuming: ServerMediaItem? = nil, next: ServerMediaItem? = nil,
    watched: ServerMediaItem? = nil, records: [EpisodeTransferRecord] = [], lookups: [ServerEpisodeLookup]? = nil,
    unread: [Int] = [], catalogComplete: Bool = true
  ) -> SeriesContinuation.Choice? {
    let upNext =
      resuming.map { PlaybackEpisodeProgress.UpNext(episode: $0, resumes: true) }
      ?? next.map { PlaybackEpisodeProgress.UpNext(episode: $0, resumes: false) }
    let loaded = seasons.filter { !unread.contains($0.number) }
    return SeriesContinuation.choose(
      upNext: upNext, lastWatched: watched, serverName: "emby", lookups: lookups ?? [index(files, records: records)],
      seasons: loaded, knownSeasons: Array(Set(seasons.map(\.number) + unread)).sorted(),
      catalogComplete: catalogComplete)
  }

  // MARK: 接着看到一半的那份是哪一集

  func testResumedFileWithTheEpisodeIDResumesThatEpisode() {
    let half = file("f", episode: 2, tmdb: 102)
    XCTAssertEqual(choose([half], resuming: half), .play(episode(1, 2), season: seasonList(1), resumeFile: half))
  }

  func testResumedFileWhoseIDIsInAnotherSeasonResumesThatEpisode() {
    // 服务器按别的顺序分季：标着第 1 季第 5 集，编号是默认顺序第 2 季第 2 集。
    let half = file("f", episode: 5, tmdb: 202)
    XCTAssertEqual(choose([half], resuming: half), .play(episode(2, 2), season: seasonList(2), resumeFile: half))
  }

  func testResumedFilePlacedByAnEpisodeGroupTransferRecordResumesTheRecordedEpisode() {
    // 按剧集组整理：服务器上标着第 2 季第 1 集、没有单集编号，播出日期恰好和默认顺序的第 2 季第 1 集一样；
    // 整理记录说它是剧集组 g1 第 1 季第 2 集，也就是默认顺序第 1 季第 5 集（105）。以集索引为准，接着看第 1 季第 5 集。
    let path = "/media/tv/某剧/Season 2/某剧 - S02E01.mkv"
    let half = file("f", season: 2, episode: 1, path: path, premiere: "2025-02-01")
    let record = EpisodeTransferRecord(
      mediaID: "100", seasons: "S01", episodes: "E02", episodeGroup: "g1", path: path, date: nil)
    XCTAssertEqual(
      choose([half], resuming: half, records: [record]), .play(episode(1, 5), season: seasonList(1), resumeFile: half))
  }

  func testResumedMultiEpisodeFileResumesItsFirstEpisode() {
    let half = file("f", episode: 1, end: 2, tmdb: 101)
    XCTAssertEqual(choose([half], resuming: half), .play(episode(1, 1), season: seasonList(1), resumeFile: half))
  }

  func testResumedFileMatchedOnlyByNumberWithoutContraryEvidenceResumesThatEpisode() {
    let half = file("f", episode: 3, premiere: "2025-01-03")
    XCTAssertEqual(choose([half], resuming: half), .play(episode(1, 3), season: seasonList(1), resumeFile: half))
  }

  func testResumedFileWithAnotherAirDateOpensThePanel() {
    let half = file("f", episode: 3, premiere: "2024-06-01")
    XCTAssertEqual(choose([half], resuming: half), .openPanel(episode(1, 3)))
  }

  func testResumedFileWithAnotherAirDatePlaysTheEpisodeFromACredibleCopyInstead() {
    // 同一集另有一份没有反证的：播这一集（那份），不从日期对不上的这份接着看。
    let half = file("f", episode: 3, premiere: "2024-06-01")
    let other = file("g", episode: 3)
    XCTAssertEqual(choose([half, other], resuming: half), .play(episode(1, 3), season: seasonList(1), resumeFile: nil))
  }

  func testResumedFileWhoseIDMatchesNoEpisodePlaysTheSameNumberFromItsOwnCopy() {
    let half = file("f", episode: 2, tmdb: 999)
    let copy = file("g", episode: 2, tmdb: 102)
    XCTAssertEqual(choose([half, copy], resuming: half), .play(episode(1, 2), season: seasonList(1), resumeFile: nil))
  }

  func testResumedFileWhoseIDMatchesNoEpisodeOpensTheSameNumberPanel() {
    let half = file("f", episode: 2, tmdb: 999)
    XCTAssertEqual(choose([half], resuming: half), .openPanel(episode(1, 2)))
  }

  func testResumedFileWhoseIDMatchesNoEpisodeAndHasNoSameNumberIsResumedWithoutAnEpisodeNumber() {
    // 编号不在集列表里、也没有同号的集（TMDB 集列表还没更新到）：没有反证，接着播这份，按钮不写集号。
    let half = file("f", episode: 20, tmdb: 999)
    XCTAssertEqual(choose([half], resuming: half), .playServerFile(half, resumes: true, episode: nil))
  }

  func testResumedFileWhoseIDIsNotInIncompleteListsIsResumedWithoutAnEpisodeNumber() {
    // 集列表没读全：编号可能在没读到的那一季，不算反证。接着播这份，不当成同号那一集，也不改播同号那一集的别的文件。
    let half = file("f", episode: 2, tmdb: 999)
    let copy = file("g", episode: 2, tmdb: 102)
    XCTAssertEqual(
      choose([half, copy], resuming: half, unread: [3]), .playServerFile(half, resumes: true, episode: nil))
    XCTAssertEqual(
      choose([half, copy], resuming: half, catalogComplete: false), .playServerFile(half, resumes: true, episode: nil))
  }

  func testResumedFileWhoseExternalIDPointsToAnotherSeriesIsNeverPlayed() {
    // 外部编号指向别的剧：同号那一集有别的文件就播那份，没有就打开面板；对不到集列表的说明原因。
    // （Emby 的单集不带 TMDB 编号，按别的外部编号反查。）
    let half = file("f", episode: 2)
    let copy = file("g", episode: 2, tmdb: 102)
    XCTAssertEqual(
      choose([half, copy], resuming: half, lookups: [index([half, copy], evidence: pointingElsewhere("f"))]),
      .play(episode(1, 2), season: seasonList(1), resumeFile: nil))
    let numbered = file("f", episode: 3)
    XCTAssertEqual(
      choose([numbered], resuming: numbered, lookups: [index([numbered], evidence: pointingElsewhere("f"))]),
      .openPanel(episode(1, 3)))
    let far = file("f", episode: 20)
    XCTAssertEqual(
      choose([far], resuming: far, lookups: [index([far], evidence: pointingElsewhere("f"))]),
      .explain(.fileContradicted(far)))
  }

  func testResumedFileTheIndexCannotPlaceIsResumedWithoutInterruption() {
    // 没有单集编号、集号不在集列表里（TMDB 还没更新到这一集）：没有反证，接着播这份。
    let half = file("f", episode: 9)
    XCTAssertEqual(choose([half], resuming: half), .playServerFile(half, resumes: true, episode: nil))
    // 读不到这台服务器的集索引：同样没有反证。
    XCTAssertEqual(
      choose([], resuming: half, lookups: [.failed(server: "emby", message: "读取失败")]),
      .playServerFile(half, resumes: true, episode: nil))
  }

  // MARK: 看完的下一集以集列表为准

  func testNextEpisodeAfterTheWatchedOneIsPlayed() {
    let watched = file("w", episode: 2, tmdb: 102)
    let next = file("n", episode: 3, tmdb: 103)
    XCTAssertEqual(
      choose([watched, next], next: next, watched: watched), .play(episode(1, 3), season: seasonList(1), resumeFile: nil))
  }

  func testMissingNextEpisodeIsNotSkippedForALaterServerFile() {
    // 服务器缺第 3 集、有第 4 集：打开第 3 集的面板，不跳过去播第 4 集。
    let watched = file("w", episode: 2, tmdb: 102)
    let later = file("n", episode: 4, tmdb: 104)
    XCTAssertEqual(choose([watched, later], next: later, watched: watched), .openPanel(episode(1, 3)))
  }

  func testNextEpisodeCrossesIntoTheNextRegularSeasonButNotIntoSpecials() {
    let watched = file("w", episode: 6, tmdb: 106)
    XCTAssertEqual(choose([watched], watched: watched), .openPanel(episode(2, 1)))
    let special = file("s", season: 0, episode: 2, tmdb: 902)
    let first = file("e1", episode: 1, tmdb: 101)
    XCTAssertEqual(
      choose([special, first], watched: special), .start(episode(1, 1), season: seasonList(1)),
      "最后一集特别篇看完，服务器上也没有接着看的正片：从头")
  }

  func testNextEpisodeAfterAMultiEpisodeFileSkipsTheEpisodesItContains() {
    let watched = file("w", episode: 1, end: 2, tmdb: 101)
    let next = file("n", episode: 3, tmdb: 103)
    XCTAssertEqual(
      choose([watched, next], watched: watched), .play(episode(1, 3), season: seasonList(1), resumeFile: nil))
  }

  func testNextEpisodeAfterAFilePlacedByATransferRecordFollowsTheRecordedEpisode() {
    // 看完的那份按整理记录是第 1 季第 5 集：下一集是第 1 季第 6 集，不是按它自己的「第 2 季第 1 集」算的第 2 季第 2 集。
    let path = "/media/tv/某剧/Season 2/某剧 - S02E01.mkv"
    let watched = file("w", season: 2, episode: 1, path: path, premiere: "2025-02-01")
    let record = EpisodeTransferRecord(
      mediaID: "100", seasons: "S01", episodes: "E02", episodeGroup: "g1", path: path, date: nil)
    XCTAssertEqual(choose([watched], watched: watched, records: [record]), .openPanel(episode(1, 6)))
  }

  func testNextServerFileIsPlacedWhenTheWatchedOneCannotBe() {
    // 看完的那份对不到集列表：按服务器上接着看的那份对；它前一集在服务器上，没有跳集，播它。
    let watched = file("w", episode: 9)
    let previous = file("p", episode: 2, tmdb: 102)
    let next = file("n", episode: 3, tmdb: 103)
    XCTAssertEqual(
      choose([watched, previous, next], next: next, watched: watched),
      .play(episode(1, 3), season: seasonList(1), resumeFile: nil))
    // 前一集不在服务器上：打开前一集的面板，不跳过去。
    XCTAssertEqual(choose([watched, next], next: next, watched: watched), .openPanel(episode(1, 2)))
    let unplaced = file("n", episode: 10)
    XCTAssertEqual(
      choose([watched, unplaced], next: unplaced, watched: watched), .playServerFile(unplaced, resumes: false, episode: nil))
    // 服务器上也没有接着看的那份：没法确定下一集，说明原因，不从头。
    XCTAssertEqual(choose([watched], watched: watched), .explain(.nextUnknown))
  }

  func testNextServerFileIsFollowedWhenTheNextSeasonListIsUnread() {
    // 看完第 1 季最后一集，第 2 季的集列表没读到：服务器上接着看的那份对不到集列表，没有反证，播它（不写集号）。
    let watched = file("w", episode: 6, tmdb: 106)
    let next = file("n", season: 2, episode: 1, tmdb: 201)
    XCTAssertEqual(
      choose([watched, next], next: next, watched: watched, unread: [2]),
      .playServerFile(next, resumes: false, episode: nil))
  }

  // MARK: 同一集另有确定的文件

  func testResumedFileMatchedByNumberIsResumedEvenWhenAnotherCopyIsConfirmed() {
    // 4K 库那份带编号（确定），看到一半的这份没有编号、按季号集号对上、没有反证：起播不会试它，照常接着播它。
    let half = file("x", episode: 3, premiere: "2025-01-03")
    let confirmed = file("y", episode: 3, tmdb: 103)
    XCTAssertEqual(choose([half, confirmed], resuming: half), .playServerFile(half, resumes: true, episode: episode(1, 3)))
  }

  func testResumedFileWithContraryEvidenceIsNotPlayedWhenAnotherCopyIsConfirmed() {
    // 同上，但这份播出日期对不上：播第 3 集确定的那份，不原样播这份。
    let half = file("x", episode: 3, premiere: "2024-06-01")
    let confirmed = file("y", episode: 3, tmdb: 103)
    XCTAssertEqual(choose([half, confirmed], resuming: half), .play(episode(1, 3), season: seasonList(1), resumeFile: nil))
  }

  func testWatchedFileMatchedByNumberIsPlacedEvenWhenAnotherCopyIsConfirmed() {
    // 看完的是没有编号的那份：仍对到第 3 集，下一集第 4 集不在服务器上，打开它的面板（不从头、不跳集）。
    let watched = file("x", episode: 3, premiere: "2025-01-03")
    let confirmed = file("y", episode: 3, tmdb: 103)
    let later = file("z", episode: 5, tmdb: 105)
    XCTAssertEqual(choose([watched, confirmed, later], next: later, watched: watched), .openPanel(episode(1, 4)))
  }

  func testMultiEpisodeFileMatchedByNumberIsPlacedByAllItsEpisodes() {
    // 没有编号的 E05–E06：接着看从第 5 集，看完后下一集是第 2 季第 1 集（不随遍历顺序变，也不混用剧集组编号）。
    let half = file("x", episode: 5, end: 6)
    XCTAssertEqual(choose([half], resuming: half), .play(episode(1, 5), season: seasonList(1), resumeFile: half))
    XCTAssertEqual(choose([half], watched: half), .openPanel(episode(2, 1)))
  }

  // MARK: 读不全时不跨季、不跳集

  func testNextEpisodeDoesNotSkipASeasonWhoseListIsUnread() {
    // 第 2 季的集列表没读到：看完第 1 季最后一集，不跨过去（也不从头）。
    let watched = file("w", episode: 6, tmdb: 106)
    XCTAssertEqual(choose([watched], watched: watched, unread: [2]), .explain(.seasonListUnreadable))
    // 最后一个读到的季看完、后面还有没读到的季，或季列表本身没读到：不说看完了。
    let last = file("l", season: 2, episode: 2, tmdb: 202)
    XCTAssertEqual(choose([last], watched: last, unread: [3]), .explain(.seasonListUnreadable))
    XCTAssertEqual(choose([last], watched: last, catalogComplete: false), .explain(.seasonListUnreadable))
  }

  func testNextServerFileBeyondAnUnreadSeasonIsNotPlayed() {
    // 看完第 1 季最后一集，第 2 季的集列表没读到，服务器上没有第 2 季、接着看的那份是第 3 季第 1 集：不跨过第 2 季。
    let season3 = [301, 302].map { TmdbEpisode(id: $0, episodeNumber: $0 - 300, seasonNumber: 3, airDate: "2025-03-0\($0 - 300)") }
    let watched = file("w", episode: 6, tmdb: 106)
    let next = file("n", season: 3, episode: 1, tmdb: 301)
    let lookup = ServerEpisodeLookup.loaded(
      ServerEpisodeIndex(
        serverName: "emby", hasSeries: true, episodes: [watched, next],
        lists: [
          EpisodeListKey(episodeGroup: nil, season: 1): season1, EpisodeListKey(episodeGroup: nil, season: 3): season3,
        ]))
    let choice = SeriesContinuation.choose(
      upNext: .init(episode: next, resumes: false), lastWatched: watched, serverName: "emby", lookups: [lookup],
      seasons: [
        .init(number: 1, episodes: MoviePilotEpisode.list(season1, season: 1)),
        .init(number: 3, episodes: MoviePilotEpisode.list(season3, season: 3)),
      ],
      knownSeasons: [1, 2, 3], catalogComplete: true)
    XCTAssertEqual(choice, .explain(.seasonListUnreadable))
  }

  func testEmptyEpisodeListsStillFollowTheServerWithoutContraryEvidence() {
    // MoviePilot 的集列表一集都没读到（比如读 TMDB 失败）：没有反证就按服务器上接着看的那份播，按钮不写集号。
    func choose(_ files: [ServerMediaItem], upNext: PlaybackEpisodeProgress.UpNext?, watched: ServerMediaItem?,
      evidence: EpisodeEvidence = EpisodeEvidence()) -> SeriesContinuation.Choice? {
      SeriesContinuation.choose(
        upNext: upNext, lastWatched: watched, serverName: "emby", lookups: [index(files, evidence: evidence)],
        seasons: [], knownSeasons: [1, 2], catalogComplete: false)
    }
    let half = file("h", episode: 3, tmdb: 103)
    XCTAssertEqual(
      choose([half], upNext: .init(episode: half, resumes: true), watched: nil),
      .playServerFile(half, resumes: true, episode: nil))
    let watched = file("w", episode: 2, tmdb: 102)
    let next = file("n", episode: 3, tmdb: 103)
    XCTAssertEqual(
      choose([watched, next], upNext: .init(episode: next, resumes: false), watched: watched),
      .playServerFile(next, resumes: false, episode: nil))
    // 外部编号指向别的剧（补查结果不靠集列表）：不原样播，说明原因。
    let elsewhere = file("x", episode: 3)
    XCTAssertEqual(
      choose([elsewhere], upNext: .init(episode: elsewhere, resumes: true), watched: nil,
        evidence: pointingElsewhere("x")),
      .explain(.fileContradicted(elsewhere)))
    // 服务器上也没有接着看的那份：没法决定。
    XCTAssertNil(choose([watched], upNext: nil, watched: watched))
  }

  func testUnwatchedSeriesDoesNotSkipAnUnreadFirstSeason() {
    let s2e1 = file("a", season: 2, episode: 1, tmdb: 201)
    XCTAssertEqual(choose([s2e1], unread: [1]), .explain(.seasonListUnreadable))
    // 正片季一季都没读到、只读到特别篇：不从特别篇开始播。
    let special = file("s", season: 0, episode: 2, tmdb: 902)
    XCTAssertEqual(choose([special], unread: [1, 2]), .explain(.seasonListUnreadable))
    XCTAssertEqual(choose([special, s2e1], watched: special, unread: [1, 2]), .explain(.seasonListUnreadable))
  }

  func testUnplacedServerFileBeyondAnUnreadSeasonIsNotPlayed() {
    // 第 2、3 季的集列表都没读到，服务器上接着看的那份标着第 3 季第 1 集（对不到集列表）：按服务器季号跨过了第 2 季，说明原因。
    let watched = file("w", episode: 6, tmdb: 106)
    let next = file("n", season: 3, episode: 1)
    XCTAssertEqual(
      choose([watched, next], next: next, watched: watched, unread: [2, 3]), .explain(.seasonListUnreadable))
  }

  func testContradictedFileFindsItsEpisodeByTheNumberingTheIndexUses() {
    // 按剧集组 g1 整理：服务器上标着第 1 季第 2 集的文件，在 g1 里是默认顺序的第 1 季第 5 集（105）。
    // 它的外部编号指向别的剧：能从别的副本播的是第 5 集，不是默认顺序的第 2 集。
    let doubtful = file("f", episode: 2)
    let e2 = file("e2", episode: 2, tmdb: 102)
    let e5 = file("e5", episode: 5, tmdb: 105)
    let record = EpisodeTransferRecord(
      mediaID: "100", seasons: "S01", episodes: "E01", episodeGroup: "g1", path: "/media/tv/某剧/其他.mkv", date: nil)
    let lookup = index([doubtful, e2, e5], records: [record], evidence: pointingElsewhere("f"))
    XCTAssertEqual(
      choose([], resuming: doubtful, lookups: [lookup]), .play(episode(1, 5), season: seasonList(1), resumeFile: nil))
  }

  func testWatchedFileWithContraryEvidenceFollowsACleanNextFileWithoutSkipping() {
    // 看完的那份播出日期对不上（不确定是哪一集）：服务器上接着看的那份没有反证就按它走。
    let watched = file("w", episode: 2, premiere: "2024-06-01")
    let previous = file("p", episode: 3, tmdb: 103)
    let next = file("n", episode: 4, tmdb: 104)
    XCTAssertEqual(
      choose([watched, previous, next], next: next, watched: watched),
      .play(episode(1, 4), season: seasonList(1), resumeFile: nil))
    // 服务器缺第 3 集、有第 4 集：打开第 3 集的面板，不跳去第 4 集。
    XCTAssertEqual(choose([watched, next], next: next, watched: watched), .openPanel(episode(1, 3)))
    // 没有接着看的那份：说明原因。
    XCTAssertEqual(choose([watched], watched: watched), .explain(.fileContradicted(watched)))
    // 外部编号指向别的剧、没有接着看的那份：同样说明原因。
    let elsewhere = file("w", episode: 2)
    XCTAssertEqual(
      choose([elsewhere], watched: elsewhere, lookups: [index([elsewhere], evidence: pointingElsewhere("w"))]),
      .explain(.fileContradicted(elsewhere)))
  }

  func testWatchedSeriesWithAnUnreadableIndexFollowsTheServer() {
    // 读不到集索引，看完的那份对不到集列表、也没有反证：播服务器上的下一份（不写集号）；没有下一份时说明原因。
    let watched = file("w", episode: 2, tmdb: 102)
    let next = file("n", episode: 4, tmdb: 104)
    let failed: [ServerEpisodeLookup] = [.failed(server: "emby", message: "读取失败")]
    XCTAssertEqual(
      choose([], next: next, watched: watched, lookups: failed), .playServerFile(next, resumes: false, episode: nil))
    XCTAssertEqual(choose([], watched: watched, lookups: failed), .explain(.episodesUnreadable))
  }

  func testUnwatchedSeriesStopsAtAnEpisodeThatIsNotKnownToBeAbsent() {
    // 第 1 集只有日期对不上的文件，第 2 集确定能播：停在第 1 集打开面板，不跳到第 2 集。
    let doubtful = file("x", episode: 1, premiere: "2020-01-01")
    let second = file("y", episode: 2, tmdb: 102)
    XCTAssertEqual(choose([doubtful, second]), .openPanel(episode(1, 1)))
    // 读不到集索引：同样停在第 1 集（面板里说明读取失败）。
    XCTAssertEqual(choose([], lookups: [.failed(server: "emby", message: "读取失败")]), .openPanel(episode(1, 1)))
  }

  // MARK: 没看过、全看完

  func testUnwatchedSeriesStartsFromTheEarliestPlayableEpisode() {
    // 只下了第 2 季：从第 2 季第 1 集开始，不打开没有的第 1 季第 1 集。
    let s2e1 = file("a", season: 2, episode: 1, tmdb: 201)
    XCTAssertEqual(choose([s2e1]), .start(episode(2, 1), season: seasonList(2)))
  }

  func testUnwatchedSeriesWithNothingPlayableOpensTheFirstEpisode() {
    XCTAssertEqual(choose([]), .openPanel(episode(1, 1)))
    // 只有日期对不上的文件：不当作能播。
    XCTAssertEqual(choose([file("x", episode: 1, premiere: "2020-01-01")]), .openPanel(episode(1, 1)))
  }

  func testFinishedSeriesStartsOverFromTheEarliestPlayableEpisode() {
    let first = file("e1", episode: 1, tmdb: 101)
    let last = file("last", season: 2, episode: 2, tmdb: 202)
    XCTAssertEqual(choose([first, last], watched: last), .start(episode(1, 1), season: seasonList(1)))
  }

  func testNewServerEpisodeAfterTheLastListedOneIsPlayedInsteadOfStartingOver() {
    // 看完集列表里正片的最后一集，服务器上已经有下一集、TMDB 还没更新到：播服务器上的那份（不写集号），不从头。
    let first = file("e1", episode: 1, tmdb: 101)
    let last = file("last", season: 2, episode: 2, tmdb: 202)
    let unnumbered = file("new", season: 2, episode: 3)
    XCTAssertEqual(
      choose([first, last, unnumbered], next: unnumbered, watched: last),
      .playServerFile(unnumbered, resumes: false, episode: nil))
    // 带着集列表里还没有的单集编号：同样没有反证。
    let numbered = file("new", season: 2, episode: 3, tmdb: 203)
    XCTAssertEqual(
      choose([first, last, numbered], next: numbered, watched: last),
      .playServerFile(numbered, resumes: false, episode: nil))
    // 服务器上接着看的那份对到集列表里前面的集（跳着看过）：按全看完从头。
    XCTAssertEqual(
      choose([first, last], next: first, watched: last), .start(episode(1, 1), season: seasonList(1)))
    // 看完的是最后一集特别篇、服务器上的下一份对不到集列表：不接到它，从头。
    let special = file("s", season: 0, episode: 2, tmdb: 902)
    XCTAssertEqual(
      choose([special, first, unnumbered], next: unnumbered, watched: special),
      .start(episode(1, 1), season: seasonList(1)))
  }

  // MARK: 决策表：集列表说的下一集 × 服务器上接着看的那份，每一格一条

  func testEveryCellOfTheNextEpisodeTable() {
    let rows = ["下一集在集列表里", "正片看完", "特别篇看完", "下一季没读到", "看完的对不上", "没看过", "看完特别篇中间一集"]
    let columns = ["没有", "对上集列表", "对不到、无反证", "有反证"]
    let e1 = file("e1", episode: 1, tmdb: 101)
    let e2 = file("e2", episode: 2, tmdb: 102)
    let e3 = file("e3", episode: 3, tmdb: 103)
    let unplaced = file("u", season: 3, episode: 1)
    let doubtful = file("c", episode: 3, premiere: "2024-06-01")
    let play3 = SeriesContinuation.Choice.play(episode(1, 3), season: seasonList(1), resumeFile: nil)
    let fromStart = SeriesContinuation.Choice.start(episode(1, 1), season: seasonList(1))
    let playUnplaced = SeriesContinuation.Choice.playServerFile(unplaced, resumes: false, episode: nil)

    struct Cell {
      let row: String, column: String
      let files: [ServerMediaItem], watched: ServerMediaItem?, next: ServerMediaItem?
      var unread: [Int] = []
      let expected: SeriesContinuation.Choice
    }
    let watchedE2 = e2, last = file("last", season: 2, episode: 2, tmdb: 202)
    let special = file("s", season: 0, episode: 2, tmdb: 902), e6 = file("e6", episode: 6, tmdb: 106)
    let midSpecial = file("m", season: 0, episode: 1, tmdb: 901), special2 = file("s2", season: 0, episode: 2, tmdb: 902)
    let playSpecial2 = SeriesContinuation.Choice.play(episode(0, 2), season: seasonList(0), resumeFile: nil)
    let unknown = file("w", episode: 9)
    let inUnreadSeason = file("u2", season: 2, episode: 1)
    let cells: [Cell] = [
      // 集列表说了下一集（第 3 集）：以集列表为准，服务器上的那份是什么都一样。
      Cell(row: rows[0], column: columns[0], files: [watchedE2, e3], watched: watchedE2, next: nil, expected: play3),
      Cell(row: rows[0], column: columns[1], files: [watchedE2, e3, e1], watched: watchedE2, next: e1, expected: play3),
      Cell(row: rows[0], column: columns[2], files: [watchedE2, e3, unplaced], watched: watchedE2, next: unplaced, expected: play3),
      Cell(row: rows[0], column: columns[3], files: [watchedE2, e3, doubtful], watched: watchedE2, next: doubtful, expected: play3),
      // 正片看完：只有集列表还没更新到的下一份（对不到、无反证）接着播，其余从头。
      Cell(row: rows[1], column: columns[0], files: [e1, last], watched: last, next: nil, expected: fromStart),
      Cell(row: rows[1], column: columns[1], files: [e1, last], watched: last, next: e1, expected: fromStart),
      Cell(row: rows[1], column: columns[2], files: [e1, last, unplaced], watched: last, next: unplaced, expected: playUnplaced),
      Cell(row: rows[1], column: columns[3], files: [e1, last, doubtful], watched: last, next: doubtful, expected: fromStart),
      // 最后一集特别篇看完：服务器上接着看的那份对上了正片就按它走（前一集不在服务器上时停在前一集），否则从头。
      Cell(row: rows[2], column: columns[0], files: [e1, special], watched: special, next: nil, expected: fromStart),
      Cell(row: rows[2], column: columns[1], files: [e2, special, e3], watched: special, next: e3, expected: play3),
      Cell(row: rows[2], column: columns[2], files: [e1, special, unplaced], watched: special, next: unplaced, expected: fromStart),
      Cell(row: rows[2], column: columns[3], files: [e1, special, doubtful], watched: special, next: doubtful, expected: fromStart),
      // 下一季（第 2 季）没读到：对不到集列表的那份接着播；对到的集按它走（没跨过没读到的季时），有反证的按反证处理。
      Cell(
        row: rows[3], column: columns[0], files: [e6], watched: e6, next: nil, unread: [2],
        expected: .explain(.seasonListUnreadable)),
      Cell(
        row: rows[3], column: columns[1], files: [e6, e2, e3], watched: e6, next: e3, unread: [2], expected: play3),
      Cell(
        row: rows[3], column: columns[2], files: [e6, inUnreadSeason], watched: e6, next: inUnreadSeason, unread: [2],
        expected: .playServerFile(inUnreadSeason, resumes: false, episode: nil)),
      Cell(
        row: rows[3], column: columns[3], files: [e6, doubtful], watched: e6, next: doubtful, unread: [2],
        expected: .openPanel(episode(1, 3))),
      // 看完的那一集对不上：没有反证就按服务器上接着看的那份走。
      Cell(row: rows[4], column: columns[0], files: [unknown], watched: unknown, next: nil, expected: .explain(.nextUnknown)),
      Cell(row: rows[4], column: columns[1], files: [unknown, e2, e3], watched: unknown, next: e3, expected: play3),
      Cell(row: rows[4], column: columns[2], files: [unknown, unplaced], watched: unknown, next: unplaced, expected: playUnplaced),
      Cell(
        row: rows[4], column: columns[3], files: [unknown, doubtful], watched: unknown, next: doubtful,
        expected: .openPanel(episode(1, 3))),
      // 没有看完的记录：服务器上有接着看的那份就按它走，否则从头。
      Cell(row: rows[5], column: columns[0], files: [e1], watched: nil, next: nil, expected: fromStart),
      Cell(row: rows[5], column: columns[1], files: [e2, e3], watched: nil, next: e3, expected: play3),
      Cell(row: rows[5], column: columns[2], files: [e1, unplaced], watched: nil, next: unplaced, expected: playUnplaced),
      Cell(row: rows[5], column: columns[3], files: [doubtful], watched: nil, next: doubtful, expected: .openPanel(episode(1, 3))),
      // 看完特别篇中间一集：服务器上接着看的那份对上了正片就按它走，否则播下一集特别篇。
      Cell(
        row: rows[6], column: columns[0], files: [midSpecial, special2], watched: midSpecial, next: nil,
        expected: playSpecial2),
      Cell(
        row: rows[6], column: columns[1], files: [midSpecial, special2, e2, e3], watched: midSpecial, next: e3,
        expected: play3),
      Cell(
        row: rows[6], column: columns[2], files: [midSpecial, special2, unplaced], watched: midSpecial, next: unplaced,
        expected: playSpecial2),
      Cell(
        row: rows[6], column: columns[3], files: [midSpecial, special2, doubtful], watched: midSpecial, next: doubtful,
        expected: playSpecial2),
    ]

    let covered = Set(cells.map { "\($0.row)｜\($0.column)" })
    let all = Set(rows.flatMap { row in columns.map { "\(row)｜\($0)" } })
    XCTAssertEqual(covered, all, "决策表每一格都要有")
    XCTAssertEqual(cells.count, all.count, "每一格只写一次")
    for cell in cells {
      XCTAssertEqual(
        choose(cell.files, next: cell.next, watched: cell.watched, unread: cell.unread), cell.expected,
        "\(cell.row)｜\(cell.column)")
    }
  }

  func testNoEpisodeListMeansNoDecision() {
    XCTAssertNil(
      SeriesContinuation.choose(
        upNext: nil, lastWatched: nil, serverName: "emby", lookups: [], seasons: [], knownSeasons: [1],
        catalogComplete: false))
  }
}
