import XCTest

@testable import MoviePilot_TV

/// 单集对应在文件和 MoviePilot 数据之外的依据：媒体库的单集来源、TMDB 反查和其他语言的标题，
/// 以及直接请求 TMDB 的缓存和限速。
final class EpisodeEvidenceTests: XCTestCase {
  // MARK: 替身

  private func file(
    _ id: String, season: Int? = 1, episode: Int?, end: Int? = nil, ids: [String: String] = [:], path: String? = nil,
    premiere: String? = nil, name: String? = nil, seriesID: String? = "s1"
  ) -> ServerMediaItem {
    ServerMediaItem(
      id: id, kind: .episode, name: name, seasonNumber: season, episodeNumber: episode, episodeNumberEnd: end,
      externalIDs: ids, path: path, premiereDate: premiere, seriesID: seriesID)
  }

  private let key = EpisodeListKey(episodeGroup: nil, season: 1)

  /// MoviePilot 的中文集列表：第 1–4 集是 TMDB 101–104。
  private let chineseSeason: [TmdbEpisode] = ["雨天", "晴天", "雪天", "阴天"].enumerated().map {
    TmdbEpisode(id: 101 + $0.offset, episodeNumber: 1 + $0.offset, seasonNumber: 1, name: $0.element)
  }

  private func index(_ files: [ServerMediaItem], evidence: EpisodeEvidence) -> ServerEpisodeIndex {
    ServerEpisodeIndex(serverName: "emby", hasSeries: true, episodes: files, lists: [key: chineseSeason], evidence: evidence)
  }

  // MARK: 媒体库的单集来源

  func testOnlyLibrariesWhoseEpisodeSourcesExcludeTmdbGiveIndependentEvidence() {
    let tvdbOnly = MediaLibraryProfile(paths: ["/media/tv"], episodeFetchers: ["TheTVDB"])
    let withTmdb = MediaLibraryProfile(paths: ["/media/anime"], episodeFetchers: ["TheTVDB", "TheMovieDb"])
    let defaults = MediaLibraryProfile(paths: ["/media/docs"], episodeFetchers: nil)
    let nfoOnly = MediaLibraryProfile(paths: ["D:\\Shows"], episodeFetchers: [])
    let sharedFolder = MediaLibraryProfile(paths: ["/media/tv/shared"], episodeFetchers: ["TheMovieDb"])
    let files = [
      file("tv", episode: 1, path: "/media/tv/A/Season 1/a.mkv"),
      file("anime", episode: 1, path: "/media/anime/B/b.mkv"),
      file("docs", episode: 1, path: "/media/docs/C/c.mkv"),
      file("nfo", episode: 1, path: "D:\\Shows\\D\\d.mkv"),
      file("shared", episode: 1, path: "/media/tv/shared/E/e.mkv"),
      file("outside", episode: 1, path: "/elsewhere/f.mkv"),
      file("prefixOnly", episode: 1, path: "/media/tvshows/g.mkv"),
      file("noPath", episode: 1),
    ]
    let independent = MediaLibraryProfile.independentFiles(
      files, in: [tvdbOnly, withTmdb, defaults, nfoOnly, sharedFolder])
    XCTAssertEqual(independent, ["tv", "nfo"])
    XCTAssertTrue(MediaLibraryProfile(paths: [], episodeFetchers: ["TMDb"]).mayUseTmdbForEpisodes)
  }

  func testEmbyVirtualFoldersKeepPathsAndEpisodeSources() throws {
    let json = """
      [
        {"Name": "电视节目", "Locations": ["/media/tv"],
         "LibraryOptions": {"PathInfos": [{"Path": "/media/tv"}, {"Path": "/media/tv2"}],
           "TypeOptions": [{"Type": "Series", "MetadataFetchers": ["TheTVDB", "TheMovieDb"]},
                           {"Type": "Episode", "MetadataFetchers": ["TheTVDB"]}]}},
        {"Name": "旧库", "Locations": ["/media/old"], "LibraryOptions": {"TypeOptions": []}},
        {"Name": "坏的", "Locations": 3}
      ]
      """
    let profiles = try JSONDecoder().decode(EmbyVirtualFolderList.self, from: Data(json.utf8)).profiles
    XCTAssertEqual(profiles.count, 3)
    XCTAssertEqual(profiles[0], MediaLibraryProfile(paths: ["/media/tv", "/media/tv2"], episodeFetchers: ["TheTVDB"]))
    XCTAssertNil(profiles[1].episodeFetchers, "没有单集这一项：服务器用默认来源")
    XCTAssertTrue(profiles[1].mayUseTmdbForEpisodes)
    XCTAssertEqual(profiles[2].paths, [], "坏字段只丢它自己")
  }

  // MARK: 对应规则

  func testExternalIDLookupConfirmsEvenWhenNumberingDiffers() {
    let shifted = file("e1", episode: 1, ids: ["tvdb": "9001"], name: "Rainy Day")
    let found = ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "9001")
    let confirmed = index([shifted], evidence: EpisodeEvidence(independentFiles: ["e1"], lookups: ["e1": .found(found)]))
    XCTAssertEqual(confirmed.confirmedEpisodes(tmdbEpisodeID: 103).map(\.id), ["e1"])
    XCTAssertTrue(confirmed.uncertainEpisodes(tmdbEpisodeID: 101).isEmpty, "反查到的以 TMDB 的对应为准，不再按季号集号算第 1 集")
    XCTAssertEqual(confirmed.confirmedBy["e1"], .externalID(source: "tvdb", value: "9001"))
    XCTAssertEqual(confirmed.summary.byLookup, 1)

    let fromTmdb = index([shifted], evidence: EpisodeEvidence(lookups: ["e1": .found(found)]))
    XCTAssertTrue(fromTmdb.confirmedEpisodes(tmdbEpisodeID: 103).isEmpty, "外部编号可能是 TMDB 按季号集号给的")
    XCTAssertEqual(fromTmdb.uncertainEpisodes(tmdbEpisodeID: 101).map(\.item.id), ["e1"])
  }

  func testTitleConfirmsOnlyAfterTheIDWasExplicitlyNotFound() throws {
    let english: [TmdbEpisode] = ["Rainy Day", "Sunny Day", "Snowy Day", "Cloudy Day"].enumerated().map {
      TmdbEpisode(id: 101 + $0.offset, episodeNumber: 1 + $0.offset, name: $0.element)
    }
    let files = [
      file("e1", episode: 1, ids: ["tvdb": "1"], name: "Rainy  Day"),
      file("e2", episode: 2, ids: ["tvdb": "2"], name: "Something Else"),
    ]
    func built(_ outcome: EpisodeLookupOutcome?, files: [ServerMediaItem], lists: [TmdbEpisode]? = nil)
      -> ServerEpisodeIndex
    {
      let lookups = outcome.map { outcome in ["e1": outcome, "e2": outcome] } ?? [:]
      return index(
        files,
        evidence: EpisodeEvidence(
          independentFiles: ["e1", "e2"], lookups: lookups, translatedSeasons: [1: [lists ?? english]]))
    }
    let notFound = built(.notFound, files: files)
    XCTAssertEqual(notFound.confirmedEpisodes(tmdbEpisodeID: 101).map(\.id), ["e1"])
    XCTAssertEqual(notFound.confirmedBy["e1"], .title)
    XCTAssertEqual(notFound.uncertainEpisodes(tmdbEpisodeID: 102).map(\.item.id), ["e2"])

    for outcome: EpisodeLookupOutcome? in [nil, .unresolved, .ambiguous] {
      let held = built(outcome, files: files)
      XCTAssertTrue(held.confirmedEpisodes(tmdbEpisodeID: 101).isEmpty, "编号没明确查空（\(String(describing: outcome))）不用标题确认")
      let match = try XCTUnwrap(held.uncertainEpisodes(tmdbEpisodeID: 101).first?.match)
      XCTAssertTrue(match.titleMatches)
      XCTAssertTrue(match.message(server: "emby").contains("只能作参考"), "集名相同放在面板里供参考")
    }

    let mismatchedIDs = english.map { TmdbEpisode(id: ($0.id ?? 0) + 50, episodeNumber: $0.episodeNumber, name: $0.name) }
    XCTAssertTrue(
      built(.notFound, files: files, lists: mismatchedIDs).confirmedEpisodes(tmdbEpisodeID: 101).isEmpty,
      "另一份列表的同号集不是同一集时不算")

    let unscraped = [file("e1", episode: 1, name: "Rainy Day")]
    XCTAssertTrue(
      built(.notFound, files: unscraped).confirmedEpisodes(tmdbEpisodeID: 101).isEmpty,
      "没有 TVDB 单集编号：标题可能是旧刮削或第三方 NFO 按 TMDB 写的")
  }

  func testFileWithoutAnyMetadataSuggestsRefreshingIt() throws {
    let bare = index([file("e1", episode: 1, name: "剧名 - S01E01 - 第 1 集 - 1080p")], evidence: EpisodeEvidence())
    let match = try XCTUnwrap(bare.uncertainEpisodes(tmdbEpisodeID: 101).first?.match)
    XCTAssertTrue(match.serverHasNoMetadata)
    XCTAssertTrue(match.message(server: "emby").contains("刷新这部剧的元数据"))
    let scraped = index([file("e1", episode: 1, ids: ["tvdb": "1"])], evidence: EpisodeEvidence())
    XCTAssertFalse(try XCTUnwrap(scraped.uncertainEpisodes(tmdbEpisodeID: 101).first?.match).serverHasNoMetadata)
  }

  func testRecheckKeepsTheExternalIDThatConfirmedTheFile() {
    let recorded = file("e1", episode: 1, ids: ["tvdb": "9001"], path: "/tv/a.mkv")
    let basis = EpisodeConfirmationBasis.externalID(source: "tvdb", value: "9001")
    XCTAssertEqual(ServerEpisodeIndex.recheck(recorded, recorded: recorded, tmdbEpisodeID: 103, basis: basis), .same)
    let rescraped = file("e1", episode: 1, ids: ["tvdb": "9002"], path: "/tv/a.mkv")
    XCTAssertEqual(ServerEpisodeIndex.recheck(rescraped, recorded: recorded, tmdbEpisodeID: 103, basis: basis), .changed)
  }

  func testRequestCoversEveryUnconfirmedSingleEpisodeFileWithAnID() throws {
    let files = [
      file("both", episode: 1, ids: ["tvdb": "1", "imdb": "tt1"], name: "Rainy Day"),
      file("noIDs", episode: 2, name: "Sunny Day"),
      file("imdbOnly", episode: 3, ids: ["imdb": "tt3"], name: "Snowy Day"),
      file("farOff", episode: 38, ids: ["tvdb": "38"]),
      file("noNumbers", season: nil, episode: nil, ids: ["tvdb": "77"]),
      file("double", episode: 3, end: 4, ids: ["tvdb": "4"]),
      file("fromTmdb", episode: 4, ids: ["tvdb": "5"]),
      file("hasTmdb", episode: 4, ids: ["tmdb": "104", "tvdb": "6"]),
    ]
    let local = index(files, evidence: EpisodeEvidence())
    let independent: Set<String> = ["both", "noIDs", "imdbOnly", "farOff", "noNumbers", "double", "hasTmdb"]
    let request = try XCTUnwrap(
      ExternalEvidenceRequest(tmdbID: 100, episodes: files, local: local, independentFiles: independent))
    XCTAssertEqual(
      request.candidates.map(\.itemID), ["both", "imdbOnly", "farOff", "noNumbers"],
      "季号集号对不上任何一集、认不出的也反查；没有编号的、多集文件、已带 TMDB 编号的不查")
    XCTAssertEqual(request.candidates[0].externalIDs.map(\.source), ["tvdb", "imdb"])
    XCTAssertEqual(request.candidates[0].titleSeason, 1)
    XCTAssertNil(request.candidates[1].titleSeason, "没有 TVDB 单集编号不比标题")
    XCTAssertNil(request.candidates[2].titleSeason, "季号集号没对上一集，不按标题比")
    let unknownLibrary = try XCTUnwrap(
      ExternalEvidenceRequest(tmdbID: 100, episodes: files, local: local, independentFiles: nil))
    XCTAssertTrue(unknownLibrary.candidates.map(\.itemID).contains("fromTmdb"), "还没读到媒体库配置时都算可能要查")
    XCTAssertNil(ExternalEvidenceRequest(tmdbID: 100, episodes: files, local: local, independentFiles: []))
  }

  func testLookupConfirmsFilesThatNumbersCannotPlace() {
    let farOff = file("farOff", episode: 38, ids: ["tvdb": "38"])
    let noNumbers = file("noNumbers", season: nil, episode: nil, ids: ["tvdb": "77"])
    let evidence = EpisodeEvidence(
      independentFiles: ["farOff", "noNumbers"],
      lookups: [
        "farOff": .found(ExternalEpisodeMatch(tmdbEpisodeID: 102, source: "tvdb", value: "38")),
        "noNumbers": .found(ExternalEpisodeMatch(tmdbEpisodeID: 104, source: "tvdb", value: "77")),
      ])
    let built = index([farOff, noNumbers], evidence: evidence)
    XCTAssertEqual(built.confirmedEpisodes(tmdbEpisodeID: 102).map(\.id), ["farOff"])
    XCTAssertEqual(built.confirmedEpisodes(tmdbEpisodeID: 104).map(\.id), ["noNumbers"])
    XCTAssertEqual(built.unidentifiedFileCount, 0, "反查到了就不再算认不出")
  }

  func testMissingEpisodeIsNotDeclaredMissingWhileAFileIsStillBeingLookedUp() {
    // 服务器把一集编成第 1 季第 38 集（TMDB 第 1 季只有 4 集），它可能就是第 4 集：没查清之前，第 4 集不能直接说没有。
    let farOff = file("farOff", episode: 38, ids: ["tvdb": "38"])
    func availability(_ outcome: EpisodeLookupOutcome?, inProgress: Bool) -> EpisodeAvailability {
      let lookups = outcome.map { ["farOff": $0] } ?? [:]
      return index(
        [farOff],
        evidence: EpisodeEvidence(independentFiles: ["farOff"], lookups: lookups, lookupInProgress: inProgress)
      ).availability(of: 104)
    }
    let checking = availability(.unresolved, inProgress: true)
    XCTAssertEqual(checking, .checking(server: "emby", files: 1), "第一次核对时不下结论")
    XCTAssertFalse(checking.allowsTrial, "核对完之前不能试看")
    let afterRound = availability(.unresolved, inProgress: false)
    XCTAssertEqual(
      afterRound, .unverified(server: "emby", reason: .lookupIncomplete), "没查成：可以试看，但先说明媒体库里可能已有")
    XCTAssertTrue(afterRound.allowsTrial)
    XCTAssertEqual(availability(.ambiguous, inProgress: false), .unverified(server: "emby", reason: .lookupIncomplete))
    let unreadable = index(
      [farOff],
      evidence: EpisodeEvidence(lookups: ["farOff": .unresolved], librarySettingsUnknown: true)
    ).availability(of: 104)
    XCTAssertEqual(unreadable, .unverified(server: "emby", reason: .librarySettingsUnreadable))
    XCTAssertEqual(availability(.notFound, inProgress: false), .notOnServer, "编号明确查空：按它自己的编号不会是别的集")
    XCTAssertEqual(availability(nil, inProgress: true), .notOnServer, "没有要查的文件时补查不影响")
  }

  // MARK: 读取

  @MainActor
  func testLoaderUsesOnlyEvidenceThatIsAlreadyAtHand() async throws {
    var asked: [[String]] = []
    func load(_ evidence: EpisodeEvidence) async throws -> ServerEpisodeIndex {
      try await EpisodeMatchLoader.index(
        serverName: "emby", hasSeries: true,
        episodes: [file("e1", episode: 1, ids: ["tvdb": "9001"], path: "/tv/a.mkv")], incompleteReason: nil,
        sources: EpisodeMatchingSources(
          seasonList: { _ in self.chineseSeason }, seasons: { _ in [1] }, transferRecords: { [] },
          evidence: { episodes, local in
            asked.append(episodes.map(\.id))
            XCTAssertTrue(local.confirmed.isEmpty, "给提供方的是只用本地数据建的表")
            return evidence
          }),
        describe: { _ in "超时" })
    }
    let found = ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "9001")
    let confirmed = try await load(EpisodeEvidence(independentFiles: ["e1"], lookups: ["e1": .found(found)]))
    XCTAssertEqual(confirmed.availability(of: 103), .playable(server: "emby"))
    XCTAssertEqual(asked, [["e1"]])
    let none = try await load(EpisodeEvidence())
    guard case .uncertain = none.availability(of: 101) else { return XCTFail("没有依据时只按季号集号") }

    asked = []
    _ = try await EpisodeMatchLoader.index(
      serverName: "emby", hasSeries: true, episodes: [file("n", episode: 1, ids: ["tmdb": "101"])],
      incompleteReason: nil,
      sources: EpisodeMatchingSources(
        seasonList: { _ in [] }, seasons: { _ in [] }, transferRecords: { [] },
        evidence: { episodes, _ in
          asked.append(episodes.map(\.id))
          return EpisodeEvidence()
        }),
      describe: { _ in "超时" })
    XCTAssertTrue(asked.isEmpty, "文件都带 TMDB 单集编号时不要依据")
  }

  // MARK: 去 TMDB 补查

  private actor FakeDirectory: TmdbEpisodeDirectory {
    var found: [String: [TmdbFoundEpisode]] = [:]
    var seasons: [String: [TmdbEpisode]] = [:]
    var language: String? = "ja"
    var coolingDownOnFind = false
    var failing: Set<String> = []
    private(set) var calls: [String] = []
    var cached: Set<String> = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    var delay: Duration = .zero

    func set(
      found: [String: [TmdbFoundEpisode]], seasons: [String: [TmdbEpisode]], coolingDown: Bool = false,
      failing: Set<String> = []
    ) {
      self.found = found
      self.seasons = seasons
      coolingDownOnFind = coolingDown
      self.failing = failing
    }

    func setDelay(_ delay: Duration) { self.delay = delay }
    func setCached(_ keys: Set<String>) { cached = keys }

    func findEpisodes(source: String, value: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?)
      async throws -> [TmdbFoundEpisode]
    {
      let cachedOnly = access == nil
      let key = "\(source) \(value)"
      if cachedOnly, !cached.contains(key) { throw TmdbDirectError.notCached }
      calls.append("find \(key)")
      inFlight += 1
      maxInFlight = max(maxInFlight, inFlight)
      defer { inFlight -= 1 }
      if delay > .zero { try await Task.sleep(for: delay) }
      if coolingDownOnFind { throw TmdbDirectError.coolingDown }
      if failing.contains(key) { throw TmdbDirectError.status(500) }
      return found[key] ?? []
    }

    func seasonEpisodes(
      tvID: Int, season: Int, language: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?
    ) async throws -> [TmdbEpisode] {
      if access == nil { throw TmdbDirectError.notCached }
      calls.append("season \(season) \(language)")
      return seasons["\(season) \(language)"] ?? []
    }

    func originalLanguage(tvID: Int, access: TmdbAccess?, deadline: ContinuousClock.Instant?) async throws -> String? {
      if access == nil { throw TmdbDirectError.notCached }
      calls.append("language")
      return language
    }
  }

  private let access = TmdbAccess(apiKey: "k", domain: "api.themoviedb.org", locale: "zh")

  func testCollectSortsEveryFileIntoFoundNotFoundAmbiguousOrUnresolved() async {
    let directory = FakeDirectory()
    await directory.set(
      found: [
        "tvdb 1": [TmdbFoundEpisode(id: 103, showID: 100), TmdbFoundEpisode(id: 900, showID: 999)],
        "tvdb 2": [TmdbFoundEpisode(id: 104, showID: 100), TmdbFoundEpisode(id: 105, showID: 100)],
        "tvdb 3": [], "imdb tt3": [TmdbFoundEpisode(id: 106, showID: 100)],
        "tvdb 4": [], "imdb tt4": [],
        "tvdb 6": [TmdbFoundEpisode(id: 700, showID: 999)],
      ],
      seasons: ["1 ja": [TmdbEpisode(id: 101, episodeNumber: 1, name: "雨の日")], "1 en-US": []],
      failing: ["imdb tt5"])
    let request = ExternalEvidenceRequest(
      tmdbID: 100,
      candidates: [
        .init(itemID: "a", externalIDs: [("tvdb", "1")], titleSeason: nil),
        .init(itemID: "b", externalIDs: [("tvdb", "2"), ("imdb", "tt2")], titleSeason: 1),
        .init(itemID: "c", externalIDs: [("tvdb", "3"), ("imdb", "tt3")], titleSeason: nil),
        .init(itemID: "d", externalIDs: [("tvdb", "4"), ("imdb", "tt4")], titleSeason: 1),
        .init(itemID: "e", externalIDs: [("tvdb", "5"), ("imdb", "tt5")], titleSeason: 2),
        .init(itemID: "f", externalIDs: [("tvdb", "6")], titleSeason: 1),
      ])
    let result = await TmdbEpisodeEvidence.collect(request, access: access, directory: directory)
    XCTAssertEqual(result.lookups["a"], .found(ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "1")))
    XCTAssertEqual(result.lookups["b"], .ambiguous, "这部剧有两集：关联有歧义")
    XCTAssertEqual(result.lookups["c"], .found(ExternalEpisodeMatch(tmdbEpisodeID: 106, source: "imdb", value: "tt3")))
    XCTAssertEqual(result.lookups["d"], .notFound, "每个编号都明确查空")
    XCTAssertEqual(result.lookups["e"], .unresolved, "有一个编号没查成就不算查空")
    XCTAssertEqual(result.lookups["f"], .ambiguous, "编号指向别的剧是身份冲突，不算查空")
    XCTAssertFalse(result.isComplete)
    XCTAssertEqual(result.translatedSeasons[1]?.count, 1, "只给编号明确查空的文件取季列表，空列表不要")
    XCTAssertNil(result.translatedSeasons[2], "没查成的不比标题")
    let calls = await directory.calls
    XCTAssertFalse(calls.contains("find imdb tt2"), "有歧义时不再用别的编号")
    XCTAssertTrue(calls.contains("season 1 ja") && calls.contains("season 1 en-US"))
  }

  func testCollectStopsWhenTmdbIsRateLimited() async {
    let directory = FakeDirectory()
    await directory.set(found: [:], seasons: [:], coolingDown: true)
    let request = ExternalEvidenceRequest(
      tmdbID: 100, candidates: [.init(itemID: "a", externalIDs: [("tvdb", "1")], titleSeason: 1)])
    let result = await TmdbEpisodeEvidence.collect(request, access: access, directory: directory)
    XCTAssertEqual(result.lookups["a"], .unresolved)
    XCTAssertFalse(result.isComplete)
    let calls = await directory.calls
    XCTAssertFalse(calls.contains("language"), "限流后这一轮不再发请求")
  }

  func testCachedPassNeverWaitsForTheNetwork() async {
    let directory = FakeDirectory()
    await directory.set(found: ["tvdb 1": [TmdbFoundEpisode(id: 103, showID: 100)]], seasons: [:])
    await directory.setCached(["tvdb 1"])
    let request = ExternalEvidenceRequest(
      tmdbID: 100,
      candidates: [
        .init(itemID: "a", externalIDs: [("tvdb", "1")], titleSeason: nil),
        .init(itemID: "b", externalIDs: [("tvdb", "2")], titleSeason: 1),
      ])
    let result = await TmdbEpisodeEvidence.collect(request, access: nil, directory: directory)
    XCTAssertEqual(result.lookups["a"], .found(ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "1")))
    XCTAssertEqual(result.lookups["b"], .unresolved, "没查过的交给后台")
    XCTAssertFalse(result.isComplete)
    let calls = await directory.calls
    XCTAssertEqual(calls, ["find tvdb 1"], "只读缓存时不发请求")
  }

  func testRoundKeepsTwoRequestsInFlightAndStopsStartingAtTheDeadline() async {
    let directory = FakeDirectory()
    await directory.setDelay(.milliseconds(80))
    let request = ExternalEvidenceRequest(
      tmdbID: 100,
      candidates: (0..<12).map { .init(itemID: "f\($0)", externalIDs: [("tvdb", "\($0)")], titleSeason: nil) })
    let result = await TmdbEpisodeEvidence.collect(
      request, access: access, directory: directory, deadline: .now.advanced(by: .milliseconds(200)))
    let calls = await directory.calls
    let peak = await directory.maxInFlight
    XCTAssertEqual(peak, 2, "同时最多两个，不往限速队列里堆")
    XCTAssertLessThan(calls.count, 12, "到时间不再发新的")
    XCTAssertFalse(result.isComplete)
    XCTAssertEqual(result.lookups.count, 12, "没轮到的也记为没查成")
  }

  func testOtherLanguagesSkipTheOneMoviePilotAlreadyUses() {
    XCTAssertEqual(TmdbEpisodeEvidence.otherLanguages(original: "ja", locale: "zh"), ["ja", "en-US"])
    XCTAssertEqual(TmdbEpisodeEvidence.otherLanguages(original: "zh", locale: "zh-CN"), ["en-US"])
    XCTAssertEqual(TmdbEpisodeEvidence.otherLanguages(original: "en", locale: "zh"), ["en"])
    XCTAssertEqual(TmdbEpisodeEvidence.otherLanguages(original: nil, locale: "en"), [])
  }

  // MARK: TMDB 访问配置

  func testAccessComesFromMoviePilotSettingsAndRejectsProxiesTheTVCannotReach() throws {
    let plain = try TmdbAccessSettings(apiKey: " k ", domain: "api.tmdb.org", locale: "zh").access.get()
    XCTAssertEqual(plain, TmdbAccess(apiKey: "k", domain: "api.tmdb.org", locale: "zh"))
    let socks = try TmdbAccessSettings(apiKey: "k", domain: "d", proxyHost: "socks5://u%40x:p@192.168.1.2:7891").access.get()
    XCTAssertEqual(socks.proxy, TmdbProxy(kind: .socks5, host: "192.168.1.2", port: 7891, username: "u@x", password: "p"))
    let http = try TmdbAccessSettings(apiKey: "k", domain: "d", proxyHost: "http://nas.lan").access.get()
    XCTAssertEqual(http.proxy?.port, 80)
    for unusable in ["http://127.0.0.1:7890", "http://localhost:7890", "ftp://1.2.3.4", "not a url"] {
      guard case .failure(.notConfigured) = TmdbAccessSettings(apiKey: "k", domain: "d", proxyHost: unusable).access else {
        return XCTFail(unusable)
      }
    }
    guard case .failure(.notConfigured) = TmdbAccessSettings(apiKey: nil, domain: "d").access else {
      return XCTFail("没有 key")
    }
    let decoded = try JSONDecoder().decode(
      TmdbAccessSettings.self,
      from: Data(#"{"TMDB_API_KEY":"k","TMDB_API_DOMAIN":"api.themoviedb.org","PROXY_HOST":null,"OTHER_PASSWORD":"x"}"#.utf8))
    XCTAssertEqual(try decoded.access.get(), TmdbAccess(apiKey: "k", domain: "api.themoviedb.org"))
  }

  // MARK: 缓存和限速

  private final class FakeTransport: TmdbTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (Int, String, [String: String])] = [:]
    private(set) var requested: [URL] = []
    private(set) var proxies: [TmdbProxy?] = []

    func respond(_ pathSuffix: String, status: Int = 200, body: String, headers: [String: String] = [:]) {
      lock.withLock { responses[pathSuffix] = (status, body, headers) }
    }

    var count: Int { lock.withLock { requested.count } }

    func data(for request: URLRequest, proxy: TmdbProxy?) async throws -> (Data, HTTPURLResponse) {
      let url = try XCTUnwrap(request.url)
      let match: (Int, String, [String: String])? = lock.withLock {
        requested.append(url)
        proxies.append(proxy)
        return responses.first { url.path.hasSuffix($0.key) }?.value
      }
      guard let (status, body, headers) = match else { throw URLError(.cannotConnectToHost) }
      let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
      return (Data(body.utf8), response)
    }
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("tmdb-\(UUID().uuidString).json")
  }

  func testLookupsAreCachedOnDiskAndTheKeyStaysOutOfIt() async throws {
    let transport = FakeTransport()
    transport.respond(
      "/find/81189", body: #"{"tv_episode_results":[{"id":103,"show_id":100,"name":"x"}]}"#)
    let fileURL = temporaryFile()
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let proxy = TmdbProxy(kind: .http(tls: false), host: "192.168.1.2", port: 7890, username: nil, password: nil)
    let secret = TmdbAccess(apiKey: "secret-key", domain: "api.example.org/prefix", proxy: proxy)
    let store = TmdbLookupStore(fileURL: fileURL, transport: transport)
    let found = try await store.findEpisodes(source: "tvdb", value: "81189", access: secret, deadline: nil)
    XCTAssertEqual(found, [TmdbFoundEpisode(id: 103, showID: 100)])
    _ = try await store.findEpisodes(source: "tvdb", value: "81189", access: secret, deadline: nil)
    XCTAssertEqual(transport.count, 1, "第二次用缓存")
    let url = try XCTUnwrap(transport.requested.first)
    XCTAssertEqual(url.host, "api.example.org")
    XCTAssertEqual(url.path, "/prefix/3/find/81189")
    let query = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
    XCTAssertEqual(query["external_source"], "tvdb_id")
    XCTAssertEqual(query["api_key"], "secret-key")
    XCTAssertEqual(transport.proxies.first, proxy, "走 MoviePilot 的代理")

    await store.flush()
    let saved = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertFalse(saved.contains("secret-key"), "缓存里不存 key")
    let reloaded = TmdbLookupStore(fileURL: fileURL, transport: transport)
    _ = try await reloaded.findEpisodes(source: "tvdb", value: "81189", access: nil, deadline: nil)
    XCTAssertEqual(transport.count, 1, "重启后从磁盘读")
    do {
      _ = try await reloaded.findEpisodes(source: "tvdb", value: "1", access: nil, deadline: nil)
      XCTFail("只读缓存时没有就报没查过")
    } catch {
      XCTAssertEqual(error as? TmdbDirectError, .notCached)
    }
    XCTAssertEqual(transport.count, 1)
  }

  func testMissesExpireSoonerAndRateLimitPausesRequests() async throws {
    let transport = FakeTransport()
    transport.respond("/find/1", body: #"{"tv_episode_results":[]}"#)
    transport.respond("/find/2", status: 429, body: "{}", headers: ["Retry-After": "30"])
    nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 1_000_000)
    let store = TmdbLookupStore(fileURL: nil, transport: transport, now: { clock })
    let empty = try await store.findEpisodes(source: "tvdb", value: "1", access: access, deadline: nil)
    XCTAssertEqual(empty, [])
    clock += TmdbLookupStore.missLife - 60
    _ = try await store.findEpisodes(source: "tvdb", value: "1", access: access, deadline: nil)
    XCTAssertEqual(transport.count, 1)
    clock += 120
    _ = try await store.findEpisodes(source: "tvdb", value: "1", access: access, deadline: nil)
    XCTAssertEqual(transport.count, 2, "查不到的过一周再查")

    do {
      _ = try await store.findEpisodes(source: "tvdb", value: "2", access: access, deadline: nil)
      XCTFail("429 要报限流")
    } catch {
      XCTAssertEqual(error as? TmdbDirectError, .coolingDown)
    }
    do {
      _ = try await store.findEpisodes(source: "tvdb", value: "3", access: access, deadline: nil)
      XCTFail("暂停期间不发请求")
    } catch {
      XCTAssertEqual(error as? TmdbDirectError, .coolingDown)
    }
    XCTAssertEqual(transport.count, 3)
    clock += 31
    _ = try? await store.findEpisodes(source: "tvdb", value: "3", access: access, deadline: nil)
    XCTAssertEqual(transport.count, 4, "过了 Retry-After 再查")
  }

  func testRecentSeasonsAreCachedOnlyBriefly() async throws {
    let transport = FakeTransport()
    transport.respond(
      "/tv/100/season/1",
      body: #"{"episodes":[{"id":101,"episode_number":1,"name":"Rainy Day","air_date":"2026-11-10"}]}"#)
    nonisolated(unsafe) var clock = ISO8601DateFormatter().date(from: "2026-11-13T00:00:00Z")!
    let store = TmdbLookupStore(fileURL: nil, transport: transport, now: { clock })
    let list = try await store.seasonEpisodes(tvID: 100, season: 1, language: "en-US", access: access, deadline: nil)
    XCTAssertEqual(list.first?.name, "Rainy Day")
    clock += TmdbLookupStore.freshLife + 60
    _ = try await store.seasonEpisodes(tvID: 100, season: 1, language: "en-US", access: access, deadline: nil)
    XCTAssertEqual(transport.count, 2, "刚播出的季几天后重新取")
  }

  func testOnlyAWellFormedEmptyResultCountsAsNotFound() async throws {
    let transport = FakeTransport()
    transport.respond("/find/1", body: #"{"movie_results":[]}"#)
    transport.respond("/find/2", status: 404, body: "<html>not found</html>")
    transport.respond("/find/3", body: #"{"tv_episode_results":[{"id":5,"show_id":100},{"id":0,"show_id":100}]}"#)
    transport.respond("/find/4", body: #"{"tv_episode_results":[]}"#)
    let store = TmdbLookupStore(fileURL: nil, transport: transport)
    for value in ["1", "2", "3"] {
      do {
        _ = try await store.findEpisodes(source: "tvdb", value: value, access: access, deadline: nil)
        XCTFail("\(value) 不能当作查不到")
      } catch {
        XCTAssertNotNil(error as? TmdbDirectError)
      }
      do {
        _ = try await store.findEpisodes(source: "tvdb", value: value, access: nil, deadline: nil)
        XCTFail("\(value) 不缓存")
      } catch {
        XCTAssertEqual(error as? TmdbDirectError, .notCached)
      }
    }
    let empty = try await store.findEpisodes(source: "tvdb", value: "4", access: access, deadline: nil)
    XCTAssertEqual(empty, [])
    let cachedEmpty = try await store.findEpisodes(source: "tvdb", value: "4", access: nil, deadline: nil)
    XCTAssertEqual(cachedEmpty, [], "合法的空数组才缓存成查不到")
  }

  func testRequestsStillQueuedAtTheDeadlineAreNotSent() async throws {
    let transport = FakeTransport()
    for value in 1...4 { transport.respond("/find/\(value)", body: #"{"tv_episode_results":[]}"#) }
    let store = TmdbLookupStore(fileURL: nil, transport: transport, maxConcurrent: 1)
    let past = ContinuousClock.now.advanced(by: .milliseconds(-1))
    do {
      _ = try await store.findEpisodes(source: "tvdb", value: "1", access: access, deadline: past)
      XCTFail("过了截止时间不发")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(transport.count, 0)
  }

  // MARK: 说明要对得上原因

  func testCheckingAndUnverifiedStatesExplainTheirOwnCause() throws {
    let checking = EpisodeEntry(availability: .checking(server: "emby", files: 2), trialBlock: nil)
    XCTAssertEqual(checking.panel.buttons, [], "核对完会自动更新，不给试看也不用重试")
    XCTAssertTrue(try XCTUnwrap(checking.panel.message).contains("正在向 TMDB 核对"))
    XCTAssertNil(checking.cardStatus, "核对中不是读取失败，不在卡片上警告")
    XCTAssertFalse(try XCTUnwrap(checking.notPlayableMessage).contains("读取失败"))

    let failedLookup = EpisodeEntry(availability: .unverified(server: "emby", reason: .lookupIncomplete), trialBlock: nil)
    let message = try XCTUnwrap(failedLookup.panel.message)
    XCTAssertTrue(message.contains("没能在 TMDB 核对"), "说清是 TMDB 没查成")
    XCTAssertFalse(message.contains("刷新元数据"), "不是刷新元数据能解决的")
    XCTAssertEqual(failedLookup.panel.buttons, [.startTrial(isRetry: false), .recheck], "可以选择仍要试看")
    XCTAssertEqual(failedLookup.cardStatus, .attention)
    XCTAssertEqual(failedLookup.menuActions, [.details], "要先看面板里的说明")

    let unreadable = EpisodeAvailability.unverified(server: "emby", reason: .librarySettingsUnreadable)
    XCTAssertTrue(try XCTUnwrap(unreadable.message).contains("媒体库配置"))
  }

  func testQueueDoesNotSkipAnEpisodeThatIsStillBeingChecked() {
    let episode = MoviePilotEpisode(TmdbEpisode(id: 104, episodeNumber: 4), season: 1, index: 3)
    let farOff = file("farOff", episode: 38, ids: ["tvdb": "38"])
    func lookup(_ inProgress: Bool) -> ServerEpisodeLookup {
      .loaded(
        index(
          [farOff],
          evidence: EpisodeEvidence(
            independentFiles: ["farOff"], lookups: ["farOff": .unresolved], lookupInProgress: inProgress)))
    }
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode, current: lookup(true), others: []),
      .unknown(EpisodeAvailability.checkingQueueMessage(server: "emby")), "核对中不能当作没有而跳过")
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode, current: lookup(false), others: []),
      .unmatched(server: "emby", unverified: .lookupIncomplete))
  }
}
