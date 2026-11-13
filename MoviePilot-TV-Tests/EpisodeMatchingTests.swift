import XCTest

@testable import MoviePilot_TV

/// 单集对应模块：服务器文件 ↔ TMDB 单集。读取流程用替身数据源。
final class EpisodeMatchingTests: XCTestCase {
  // MARK: 替身

  /// 没有 TMDB 单集编号的文件（比如只用 TVDB 刮削的 Emby）。
  private func file(
    _ id: String, season: Int? = 1, episode: Int?, end: Int? = nil, tmdb: Int? = nil, path: String? = nil,
    premiere: String? = nil
  ) -> ServerMediaItem {
    ServerMediaItem(
      id: id, kind: .episode, seasonNumber: season, episodeNumber: episode, episodeNumberEnd: end,
      externalIDs: tmdb.map { ["tmdb": String($0)] } ?? ["tvdb": "9\(id)"], path: path, premiereDate: premiere)
  }

  /// 默认顺序第 1 季：第 1–6 集是 TMDB 101–106，第 n 集 2025-01-0n 播出。
  private let defaultSeason1: [TmdbEpisode] = (1...6).map {
    TmdbEpisode(id: 100 + $0, episodeNumber: $0, seasonNumber: 1, airDate: "2025-01-0\($0)")
  }

  /// 剧集组 g1 第 1 季：组内第 1、2 集是默认顺序的第 4、5 集（104、105）。
  private let groupSeason1: [TmdbEpisode] = [
    TmdbEpisode(id: 104, episodeNumber: 1, seasonNumber: 1, airDate: "2025-01-04"),
    TmdbEpisode(id: 105, episodeNumber: 2, seasonNumber: 1, airDate: "2025-01-05"),
  ]

  private var lists: [EpisodeListKey: [TmdbEpisode]] {
    [
      EpisodeListKey(episodeGroup: nil, season: 1): defaultSeason1,
      EpisodeListKey(episodeGroup: "g1", season: 1): groupSeason1,
    ]
  }

  private func record(
    _ path: String, season: String = "S01", episodes: String, group: String? = nil, date: String? = nil
  ) -> EpisodeTransferRecord {
    EpisodeTransferRecord(
      mediaID: "100", seasons: season, episodes: episodes, episodeGroup: group, path: path, date: date)
  }

  private func index(_ files: [ServerMediaItem], records: [EpisodeTransferRecord] = []) -> ServerEpisodeIndex {
    ServerEpisodeIndex(serverName: "emby", hasSeries: true, episodes: files, lists: lists, records: records)
  }

  // MARK: 整理记录

  func testTransferRecordKeepsWhatMatchingNeedsAndToleratesBadFields() throws {
    let records = try JSONDecoder().decode(
      [EpisodeTransferRecord].self,
      from: Data(
        #"""
        [
          {"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S01","episodes":"E05-E06",
           "episode_group":"g1","dest":"/media/a.mkv","dest_fileitem":{"path":"/media/tv/a.mkv","size":"x"},
           "status":true,"date":"2026-01-01 10:00:00"},
          {"media_source":"tmdb","media_id":100,"seasons":"S01","episodes":"E07","dest":"/media/b.mkv","status":1,
           "dest_fileitem":"坏掉的文件项"},
          {"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S01","episodes":"E08","status":false},
          {"media_source":"douban","media_id":"100","type":"电视剧","seasons":"S01","episodes":"E09","status":true},
          {"media_source":"themoviedb","media_id":"100","type":"电影","status":true}
        ]
        """#.utf8))
    XCTAssertEqual(records.count, 5, "单个字段坏掉只丢它")
    XCTAssertEqual(records[0].path, "/media/tv/a.mkv", "整理后的文件项路径优先")
    XCTAssertEqual(
      records[0].placement,
      EpisodePlacement(list: EpisodeListKey(episodeGroup: "g1", season: 1), episodes: [5, 6]))
    XCTAssertEqual(records[1].path, "/media/b.mkv", "文件项坏掉时用 dest")
    XCTAssertEqual(records.map { $0.belongs(toSeries: 100) }, [true, true, false, false, false], "只要这部剧成功整理的电视剧记录")
    XCTAssertFalse(records[0].belongs(toSeries: 200))
  }

  func testRecordPlacementNeedsOneSeasonAndReadableEpisodes() {
    XCTAssertEqual(record("/a/b.mkv", episodes: "E01,E03").placement?.episodes, [1, 3])
    XCTAssertNil(record("/a/b.mkv", season: "S01-S02", episodes: "E01").placement, "一个文件不会跨季")
    XCTAssertNil(record("/a/b.mkv", episodes: "第一集").placement)
    XCTAssertNil(record("/a/b.mkv", episodes: "E1-E999").placement, "范围大得不像一个文件")
    XCTAssertEqual(
      record("/a/b.mkv", season: "S00", episodes: "E02").placement?.list, EpisodeListKey(episodeGroup: nil, season: 0),
      "特别篇是第 0 季")
  }

  func testTransferPathMatchingIgnoresMountPointsCaseAndExtension() {
    let record = record("/media/电视剧/长风渡 (2023)/Season 1/长风渡 - S01E05.mkv", episodes: "E05")
    for path in [
      "/data/tv/长风渡 (2023)/Season 1/长风渡 - S01E05.mkv",
      #"\\nas\video\season 1\长风渡 - s01e05.MKV"#,
      "/strm/长风渡/Season 1/长风渡 - S01E05.strm",
    ] {
      XCTAssertEqual(index([file("e5", episode: 5, path: path)], records: [record]).availability(of: 105), .playable(server: "emby"))
    }
    for path in ["/data/Season 2/长风渡 - S01E05.mkv", "长风渡 - S01E05.mkv", nil] {
      XCTAssertTrue(index([file("e5", episode: 5, path: path)], records: [record]).confirmedEpisodes(tmdbEpisodeID: 105).isEmpty)
    }
  }

  // MARK: 播出日期

  func testAirDatesWithinADayMatch() {
    XCTAssertEqual(AirDateCheck.compare(server: "2025-01-05T00:00:00.0000000Z", moviePilot: "2025-01-05"), .matches)
    XCTAssertEqual(
      AirDateCheck.compare(server: "2025-01-04T16:00:00Z", moviePilot: "2025-01-05"), .matches, "按 UTC 存会早一天")
    XCTAssertEqual(AirDateCheck.compare(server: "2025-02-28", moviePilot: "2025-03-01"), .matches, "跨月也按天算")
    XCTAssertEqual(
      AirDateCheck.compare(server: "2025-01-03T00:00:00Z", moviePilot: "2025-01-05"),
      .differs(server: "2025-01-03", moviePilot: "2025-01-05"))
    XCTAssertEqual(AirDateCheck.compare(server: nil, moviePilot: "2025-01-05"), .unknown)
    XCTAssertEqual(AirDateCheck.compare(server: "2025-13-01", moviePilot: "2025-01-05"), .unknown, "格式不对不比")
    XCTAssertEqual(AirDateCheck.compare(server: "2025-01-05", moviePilot: ""), .unknown)
  }

  // MARK: 三步对应

  func testFileMatchedByTransferRecordIsConfirmedEvenWithoutNumbers() {
    // Emby 没解析出季号集号；整理记录说它是剧集组 g1 的第 1 季第 2 集，也就是 TMDB 105。
    let unnumbered = file(
      "e1", season: nil, episode: nil, path: "/data/tv/长风渡/Season 1/长风渡 - S01E02.mkv")
    let index = index(
      [unnumbered], records: [record("/media/长风渡/Season 1/长风渡 - S01E02.mkv", episodes: "E02", group: "g1")])
    XCTAssertEqual(index.availability(of: 105), .playable(server: "emby"))
    XCTAssertEqual(index.confirmedEpisodes(tmdbEpisodeID: 105).map(\.id), ["e1"])
    XCTAssertEqual(index.summary.byTransferRecord, 1)
    XCTAssertEqual(
      ServerEpisodeIndex.requiredLists(
        for: [unnumbered], records: [record("/media/长风渡/Season 1/长风渡 - S01E02.mkv", episodes: "E02", group: "g1")]),
      [EpisodeListKey(episodeGroup: "g1", season: 1)], "只读记录用的那份集列表")
  }

  func testConflictingRecordsForOneFileFallBackToNumbers() {
    // 同一个文件被整理过两次、记录说法不一：不知道哪条对，改按季号集号（不确定）。
    let path = "/data/Season 1/长风渡 - S01E02.mkv"
    let index = index(
      [file("e1", episode: 2, path: path)],
      records: [record(path, episodes: "E02"), record(path, episodes: "E03")])
    XCTAssertEqual(index.confirmedEpisodes(tmdbEpisodeID: 102), [])
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 102).map(\.item.id), ["e1"])
  }

  func testLongerPathSuffixSeparatesCopiesWithTheSameFilenameAndSeasonFolder() {
    let files = [
      file("a", episode: 1, path: "/emby/A剧/Season 1/E01.mkv"),
      file("b", episode: 1, path: "/emby/A剧第一季/Season 1/E01.mkv"),
    ]
    let records = [
      record("/mp/A剧/Season 1/E01.mkv", episodes: "E01"),
      record("/mp/A剧第一季/Season 1/E01.mkv", episodes: "E02"),
    ]
    let matched = index(files, records: records)
    XCTAssertEqual(matched.confirmedEpisodes(tmdbEpisodeID: 101).map(\.id), ["a"])
    XCTAssertEqual(matched.confirmedEpisodes(tmdbEpisodeID: 102).map(\.id), ["b"])
    let oneRecord = index(files, records: [records[0]])
    XCTAssertEqual(oneRecord.confirmedEpisodes(tmdbEpisodeID: 101).map(\.id), ["a"])
    XCTAssertEqual(oneRecord.summary.byTransferRecord, 1)
  }

  func testFullPathWinsButEquallyStrongCompetingCopiesNeedConfirmation() {
    let files = [
      file("a", episode: 1, path: "/a/Show/Season 1/E01.mkv"),
      file("b", episode: 1, path: "/b/Show/Season 1/E01.mkv"),
    ]
    let exact = record("/b/Show/Season 1/E01.mkv", episodes: "E02")
    let tied = record("/mp/Show/Season 1/E01.mkv", episodes: "E01")
    let matched = index(files, records: [tied, exact])
    XCTAssertEqual(matched.confirmedEpisodes(tmdbEpisodeID: 102).map(\.id), ["b"])
    XCTAssertEqual(matched.uncertainEpisodes(tmdbEpisodeID: 101).map(\.item.id), ["a"])
    let ambiguous = index(files, records: [tied])
    XCTAssertEqual(ambiguous.uncertainEpisodes(tmdbEpisodeID: 101).map(\.item.id), ["a", "b"])
  }

  func testDirectoryMappingNeedsTwoDistinctEpisodeIDsAndRejectsConflictingEvidence() {
    let first = file("a", episode: 1, tmdb: 101, path: "/emby/Season One/01.mkv")
    let second = file("b", episode: 2, tmdb: 102, path: "/emby/Season One/02.mkv")
    let third = file("c", episode: 3, path: "/emby/Season One/03.mkv")
    let records = [
      record("/mp/S01/01.mkv", episodes: "E01"),
      record("/mp/S01/02.mkv", episodes: "E02"),
      record("/mp/S01/03.mkv", episodes: "E03"),
    ]
    XCTAssertEqual(index([first, second, third], records: records).confirmedEpisodes(tmdbEpisodeID: 103).map(\.id), ["c"])
    XCTAssertTrue(index([first, third], records: records + [records[0]]).confirmedEpisodes(tmdbEpisodeID: 103).isEmpty)
    let conflict = record("/mp/S01/02.mkv", episodes: "E04")
    XCTAssertTrue(index([first, second, third], records: records + [conflict]).confirmedEpisodes(tmdbEpisodeID: 103).isEmpty)
    let secondCopy = [
      file("a2", episode: 1, tmdb: 101, path: "/emby/另一份/01.mkv"),
      file("b2", episode: 2, tmdb: 102, path: "/emby/另一份/02.mkv"),
    ]
    XCTAssertTrue(index([first, second, third] + secondCopy, records: records).confirmedEpisodes(tmdbEpisodeID: 103).isEmpty)
  }

  func testNumbersFollowTheEpisodeGroupTheSeriesWasOrganizedWith() {
    // 这部剧最近一次按剧集组 g1 整理；没有记录的文件 S01E01 也按 g1 的编号比，是 TMDB 104，不是默认顺序的 101。
    let index = index(
      [file("e1", episode: 1, premiere: "2025-01-04")],
      records: [
        record("/other/Season 1/a.mkv", episodes: "E09", date: "2025-01-01 00:00:00"),
        record("/other/Season 1/b.mkv", episodes: "E10", group: "g1", date: "2026-01-01 00:00:00"),
      ])
    XCTAssertEqual(
      index.availability(of: 104),
      .uncertain(server: "emby", match: UncertainEpisodeMatch(season: 1, episode: 1, episodeGroup: "g1", airDate: .matches)))
    XCTAssertEqual(index.availability(of: 101), .notOnServer)
    XCTAssertNil(ServerEpisodeIndex.numberingGroup([]), "没有记录按默认顺序")
  }

  func testNumberMatchIsCheckedAgainstTheAirDate() {
    let index = index([
      file("same-day", episode: 1, premiere: "2025-01-01T00:00:00Z"),
      file("wrong-day", episode: 2, premiere: "2025-03-01T00:00:00Z"),
      file("no-date", episode: 3),
    ])
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 101).first?.match.airDate, .matches)
    XCTAssertEqual(
      index.uncertainEpisodes(tmdbEpisodeID: 102).first?.match.airDate,
      .differs(server: "2025-03-01", moviePilot: "2025-01-02"))
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 103).first?.match.airDate, .unknown)
    XCTAssertEqual(index.summary.airDateMatches, 1)
    XCTAssertEqual(index.summary.airDateDiffers, 1)
    XCTAssertEqual(
      index.availability(of: 102).message,
      "“emby”上的文件没有 TMDB 编号，也对不上 MoviePilot 的整理记录，是按季号集号找到的第 1 季第 2 集，"
        + "但播出日期对不上（服务器上是 2025-03-01，这一集是 2025-01-02），很可能不是这一集")
    XCTAssertEqual(
      index.summary.logText,
      "按 TMDB 单集编号对上 0 个文件，按整理记录对上 0 个，按季号集号对上 3 个（播出日期对上 1 个、对不上 1 个），"
        + "有季号集号但集列表里没有那一集 0 个，认不出是哪一集 0 个")
  }

  func testMultiEpisodeFileWithoutIDsCoversItsRange() {
    let index = index([file("e3-4", episode: 3, end: 4)])
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 103).map(\.item.id), ["e3-4"])
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 104).first?.match.episode, 4)
  }

  func testEpisodeIDWinsOverNumbers() {
    // 第 2 集有带编号的文件，另一个没编号的文件季号集号也是第 2 集：只用带编号的。
    // 带编号的文件只按编号对应：编号 999 不在列表里，它的 S01E05 不拿来算第 5 集。
    let index = index([
      file("with-id", episode: 2, tmdb: 102),
      file("numbered", episode: 2),
      file("other-id", episode: 5, tmdb: 999),
    ])
    XCTAssertEqual(index.availability(of: 102), .playable(server: "emby"))
    XCTAssertEqual(index.playableEpisodes(tmdbEpisodeID: 102).map(\.id), ["with-id"])
    XCTAssertEqual(index.uncertainEpisodes(tmdbEpisodeID: 102), [])
    XCTAssertEqual(index.availability(of: 105), .notOnServer)
  }

  func testFileWithoutSeasonOrEpisodeNumberMayBeAnyMissingEpisode() {
    // 没有季号或集号、也对不上整理记录：不知道是哪一集，没找到的集可能就是它。
    for bare in [
      file("bare", season: nil, episode: nil), file("no-episode", season: 1, episode: nil),
      file("no-season", season: nil, episode: 3), file("huge-range", episode: 1, end: 999),
    ] {
      let index = index([file("e1", episode: 1), bare])
      XCTAssertEqual(index.unidentifiedFileCount, 1, bare.id)
      XCTAssertEqual(index.availability(of: 102), .unmatched(server: "emby"), bare.id)
      XCTAssertEqual(index.summary.unidentified, 1, bare.id)
    }
  }

  func testNumberedFileThatIsNotInTheListDoesNotHideOtherEpisodes() {
    // S01E09 不在集列表里（只有 6 集）、S02E01 那一季的列表没有：它们按自己的编号不会是第 2 集，第 2 集照常是没有。
    let index = index([
      file("e1", episode: 1), file("e9", episode: 9), file("s2e1", season: 2, episode: 1),
      file("recorded", season: nil, episode: nil, path: "/data/Season 1/a - S01E40.mkv"),
    ], records: [record("/media/Season 1/a - S01E40.mkv", episodes: "E40")])
    XCTAssertEqual(index.unidentifiedFileCount, 0)
    XCTAssertEqual(index.summary.unplaced, 3, "整理记录给了位置、集列表里没有那一集的也算有编号")
    XCTAssertEqual(index.availability(of: 102), .notOnServer)
    let episode = MoviePilotEpisode(TmdbEpisode(id: 102, episodeNumber: 2), season: 1, index: 1)
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode, current: .loaded(index), others: []), .absent, "队列照常当作没有、跳过")
  }

  func testRecheckOfAFileMatchedWithoutAnID() {
    let recorded = file("e1", episode: 2, path: "/data/Season 1/a.mkv")
    XCTAssertEqual(ServerEpisodeIndex.recheck(recorded, recorded: recorded, tmdbEpisodeID: 102), .same)
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(file("e1", episode: 2, path: "/data/Season 1/b.mkv"), recorded: recorded, tmdbEpisodeID: 102),
      .changed, "换了文件")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(file("e1", episode: 3, path: "/data/Season 1/a.mkv"), recorded: recorded, tmdbEpisodeID: 102),
      .changed, "季号集号变了")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(file("e1", episode: 2, tmdb: 107), recorded: recorded, tmdbEpisodeID: 102), .changed,
      "刷新元数据后成了另一集")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(file("e1", episode: 2, tmdb: 102), recorded: recorded, tmdbEpisodeID: 102), .same,
      "刷新元数据后有了这一集的编号")
    XCTAssertEqual(ServerEpisodeIndex.recheck(recorded, recorded: nil, tmdbEpisodeID: 102), .needsIndex)
  }

  // MARK: 多台服务器

  func testConfirmedServerWinsOverAnEarlierUncertainOne() {
    let uncertain = ServerEpisodeLookup.loaded(index([file("a1", episode: 1)]))
    let confirmed = ServerEpisodeLookup.loaded(
      ServerEpisodeIndex(serverName: "emby2", hasSeries: true, episodes: [file("b1", episode: 1, tmdb: 101)]))
    let failed = ServerEpisodeLookup.failed(server: "emby3", message: "连不上“emby3”")
    let episode = MoviePilotEpisode(TmdbEpisode(id: 101, episodeNumber: 1), season: 1, index: 0)
    XCTAssertEqual(EpisodeAvailability.resolve(episode, lookups: [uncertain, confirmed]), .playable(server: "emby2"))
    guard case .uncertain(let server, _) = EpisodeAvailability.resolve(episode, lookups: [failed, uncertain]) else {
      return XCTFail("只有按季号集号对上的，也比读取失败更有用")
    }
    XCTAssertEqual(server, "emby")
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode, current: failed, others: [uncertain]), .unknown("连不上“emby3”"),
      "当前服务器读取失败时不说“在别处”")
  }

  // MARK: 读取

  @MainActor
  func testLoaderReadsRecordsAndListsOnlyWhenNeeded() async throws {
    var recordReads = 0
    var listReads: [EpisodeListKey] = []
    var seasonReads: [String?] = []
    let sources = EpisodeMatchingSources(
      seasonList: { key in
        listReads.append(key)
        return key.season == 1 ? self.defaultSeason1 : []
      },
      seasons: { group in
        seasonReads.append(group)
        return [1, 2]
      },
      transferRecords: {
        recordReads += 1
        throw URLError(.timedOut)
      })
    let identified = try await EpisodeMatchLoader.index(
      serverName: "emby", hasSeries: true, episodes: [file("e1", episode: 1, tmdb: 101)], incompleteReason: nil,
      sources: sources, describe: { _ in "超时" })
    XCTAssertEqual(identified.availability(of: 101), .playable(server: "emby"))
    XCTAssertEqual(recordReads, 0, "文件都带编号时不读整理记录")
    XCTAssertEqual(listReads, [])
    XCTAssertEqual(seasonReads, [], "没遇到空集列表时不读季列表")

    let unidentified = try await EpisodeMatchLoader.index(
      serverName: "emby", hasSeries: true,
      episodes: [file("e1", episode: 1), file("s2", season: 2, episode: 1)], incompleteReason: nil,
      sources: sources, describe: { _ in "超时" })
    XCTAssertEqual(recordReads, 1)
    XCTAssertEqual(
      listReads, [EpisodeListKey(episodeGroup: nil, season: 1), EpisodeListKey(episodeGroup: nil, season: 2)])
    guard case .uncertain = unidentified.availability(of: 101) else {
      return XCTFail("整理记录读不到也照常按季号集号对应")
    }
    XCTAssertEqual(
      unidentified.availability(of: 102), .failed("MoviePilot 返回的第 2 季集列表是空的，无法对应这一季的文件"),
      "第 2 季的列表是空的、季列表里却有第 2 季：多半是没读到，那一季的文件无法对应，不能说没有")
    XCTAssertEqual(seasonReads, [nil], "遇到空集列表才读默认顺序的季列表")
  }

  @MainActor
  func testPathBatchSkipsExternalLookupForConfirmedFiles() async throws {
    var files: [ServerMediaItem] = []
    var records: [EpisodeTransferRecord] = []
    var seasonLists: [Int: [TmdbEpisode]] = [:]
    for season in 1...10 {
      for episode in 1...100 {
        let id = season * 1_000 + episode
        let suffix = "剧名/Season \(season)/E\(episode).mkv"
        files.append(file(String(id), season: season, episode: episode, path: "/emby/\(suffix)"))
        records.append(record("/moviepilot/\(suffix)", season: "S\(season)", episodes: "E\(episode)"))
        seasonLists[season, default: []].append(TmdbEpisode(id: id, episodeNumber: episode, seasonNumber: season))
      }
    }
    let lists = seasonLists
    let index = try await EpisodeMatchLoader.index(
      serverName: "路径批量测试", hasSeries: true, episodes: files, incompleteReason: nil,
      sources: EpisodeMatchingSources(
        seasonList: { lists[$0.season] ?? [] }, seasons: { _ in [] }, transferRecords: { records },
        externalPlacements: {
          XCTFail("已由整理路径确认的文件不应触发外部查询")
          return [:]
        }),
      describe: { $0.localizedDescription })
    XCTAssertEqual(index.summary.byTransferRecord, 1_000)
  }

  @MainActor
  func testExternalLookupTimeoutKeepsTheNumberedFallback() async throws {
    let index = try await EpisodeMatchLoader.index(
      serverName: "外部查询超时测试", hasSeries: true, episodes: [file("1", episode: 1)], incompleteReason: nil,
      sources: EpisodeMatchingSources(
        seasonList: { _ in self.defaultSeason1 }, seasons: { _ in [1] }, transferRecords: { [] },
        externalPlacements: {
          try await Task.sleep(for: .seconds(3))
          return [91: ExternalEpisodePlacement(season: 1, episode: 1, airDate: "2025-01-01")]
        }),
      describe: { $0.localizedDescription })
    guard case .uncertain = index.availability(of: 101) else {
      return XCTFail("外部查询超时后应保留已有的季集号候选")
    }
  }

  // MARK: 集列表是空的

  /// 没有 TMDB 单集编号的文件：第 1 季第 1 集，和第 0 季（特别篇）第 1 集。
  private var specialsAndSeason1: [ServerMediaItem] {
    [file("e1", episode: 1), file("sp1", season: 0, episode: 1)]
  }

  @MainActor
  private func loadIndex(
    _ files: [ServerMediaItem], seasons: @escaping (String?) async throws -> [Int],
    records: [EpisodeTransferRecord] = [], lists extra: [EpisodeListKey: [TmdbEpisode]] = [:]
  ) async throws -> ServerEpisodeIndex {
    let available = lists.merging(extra) { _, new in new }
    return try await EpisodeMatchLoader.index(
      serverName: "emby", hasSeries: true, episodes: files, incompleteReason: nil,
      sources: EpisodeMatchingSources(
        seasonList: { available[$0] ?? [] }, seasons: seasons, transferRecords: { records }),
      describe: { _ in "超时" })
  }

  @MainActor
  func testSeasonThatTheNumberingDoesNotHaveDoesNotBlockOtherEpisodes() async throws {
    // TMDB 没有第 0 季，服务器上有特别篇：第 0 季的集列表是空的，季列表里也没有第 0 季。
    // 这些文件按自己的编号不会是正片的哪一集，第 2 集照常是没有（可以试看），不是“没读全”。
    let index = try await loadIndex(specialsAndSeason1, seasons: { _ in [1, 2] })
    XCTAssertNil(index.incompleteReason)
    XCTAssertEqual(index.availability(of: 102), .notOnServer)
    XCTAssertEqual(index.summary.unplaced, 1)
    guard case .uncertain = index.availability(of: 101) else { return XCTFail("第 1 季的文件照常按季号集号对应") }
  }

  @MainActor
  func testEmptyListOfASeasonThatExistsIsStillAReadFailure() async throws {
    let cases: [(String, (String?) async throws -> [Int])] = [
      ("季列表里有这一季", { _ in [0, 1, 2] }),
      ("季列表也是空的", { _ in [] }),
      ("季列表读不到", { _ in throw URLError(.timedOut) }),
    ]
    for (name, seasons) in cases {
      let index = try await loadIndex(specialsAndSeason1, seasons: seasons)
      XCTAssertEqual(
        index.availability(of: 102), .failed("MoviePilot 返回的第 0 季集列表是空的，无法对应这一季的文件"), name)
    }
  }

  @MainActor
  func testSeasonListIsReadOncePerNumberingAndFromTheEpisodeGroup() async throws {
    // 这部剧按剧集组 g1 整理过：没有记录的文件按 g1 的编号比，g1 没有第 3、4 季，读一次 g1 的季列表就够了。
    var reads: [String?] = []
    let index = try await loadIndex(
      [file("g3", season: 3, episode: 1), file("g4", season: 4, episode: 1)],
      seasons: { group in
        reads.append(group)
        return [1, 2]
      },
      records: [record("/other/Season 1/b.mkv", episodes: "E10", group: "g1", date: "2026-01-01 00:00:00")])
    XCTAssertEqual(reads, ["g1"])
    XCTAssertNil(index.incompleteReason)
    XCTAssertEqual(index.availability(of: 104), .notOnServer)
  }
}
