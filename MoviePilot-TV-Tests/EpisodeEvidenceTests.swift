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
    let confirmed = index([shifted], evidence: EpisodeEvidence(independentFiles: ["e1"], lookedUp: ["e1": found]))
    XCTAssertEqual(confirmed.confirmedEpisodes(tmdbEpisodeID: 103).map(\.id), ["e1"])
    XCTAssertTrue(confirmed.uncertainEpisodes(tmdbEpisodeID: 101).isEmpty, "反查到的以 TMDB 的对应为准，不再按季号集号算第 1 集")
    XCTAssertEqual(confirmed.confirmedBy["e1"], .externalID(source: "tvdb", value: "9001"))
    XCTAssertEqual(confirmed.summary.byLookup, 1)

    let fromTmdb = index([shifted], evidence: EpisodeEvidence(lookedUp: ["e1": found]))
    XCTAssertTrue(fromTmdb.confirmedEpisodes(tmdbEpisodeID: 103).isEmpty, "外部编号可能是 TMDB 按季号集号给的")
    XCTAssertEqual(fromTmdb.uncertainEpisodes(tmdbEpisodeID: 101).map(\.item.id), ["e1"])
  }

  func testTitleInAnotherLanguageConfirmsOnlyTheSameTmdbEpisode() {
    let english: [TmdbEpisode] = ["Rainy Day", "Sunny Day", "Snowy Day", "Cloudy Day"].enumerated().map {
      TmdbEpisode(id: 101 + $0.offset, episodeNumber: 1 + $0.offset, name: $0.element)
    }
    let files = [
      file("e1", episode: 1, ids: ["tvdb": "1"], name: "Rainy  Day"),
      file("e2", episode: 2, ids: ["tvdb": "2"], name: "Something Else"),
    ]
    let evidence = EpisodeEvidence(independentFiles: ["e1", "e2"], translatedSeasons: [1: [english]])
    let built = index(files, evidence: evidence)
    XCTAssertEqual(built.confirmedEpisodes(tmdbEpisodeID: 101).map(\.id), ["e1"])
    XCTAssertEqual(built.confirmedBy["e1"], .title)
    XCTAssertEqual(built.uncertainEpisodes(tmdbEpisodeID: 102).map(\.item.id), ["e2"])

    let mismatchedIDs = english.map { TmdbEpisode(id: ($0.id ?? 0) + 50, episodeNumber: $0.episodeNumber, name: $0.name) }
    let other = index(files, evidence: EpisodeEvidence(independentFiles: ["e1"], translatedSeasons: [1: [mismatchedIDs]]))
    XCTAssertTrue(other.confirmedEpisodes(tmdbEpisodeID: 101).isEmpty, "另一份列表的同号集不是同一集时不算")

    let unscraped = [file("e1", episode: 1, name: "Rainy Day")]
    let noTVDB = index(unscraped, evidence: EpisodeEvidence(independentFiles: ["e1"], translatedSeasons: [1: [english]]))
    XCTAssertTrue(
      noTVDB.confirmedEpisodes(tmdbEpisodeID: 101).isEmpty,
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

  func testRequestCoversEveryUnconfirmedIndependentSingleEpisodeFile() throws {
    let files = [
      file("both", episode: 1, ids: ["tvdb": "1", "imdb": "tt1"], name: "Rainy Day"),
      file("titleNoTVDB", episode: 2, name: "Sunny Day"),
      file("placeholder", episode: 3, ids: ["imdb": "tt3"], name: "第 3 集"),
      file("farOff", episode: 38, ids: ["tvdb": "38"]),
      file("noNumbers", season: nil, episode: nil, ids: ["tvdb": "77"]),
      file("double", episode: 3, end: 4, ids: ["tvdb": "4"]),
      file("fromTmdb", episode: 4, ids: ["tvdb": "5"]),
      file("hasTmdb", episode: 4, ids: ["tmdb": "104", "tvdb": "6"]),
    ]
    let evidence = EpisodeEvidence(
      independentFiles: ["both", "titleNoTVDB", "placeholder", "farOff", "noNumbers", "double", "hasTmdb"])
    let request = try XCTUnwrap(
      ExternalEvidenceRequest(tmdbID: 100, episodes: files, index: index(files, evidence: evidence), evidence: evidence))
    XCTAssertEqual(
      request.candidates.map(\.itemID), ["both", "placeholder", "farOff", "noNumbers"],
      "季号集号对不上任何一集、认不出的也反查；没有编号又不能比标题的不查；多集文件、已带 TMDB 编号的不查")
    XCTAssertEqual(request.candidates[0].externalIDs.map(\.source), ["tvdb", "imdb"])
    XCTAssertEqual(request.candidates[0].titleSeason, 1)
    XCTAssertNil(request.candidates[1].titleSeason, "占位标题不比")
    XCTAssertNil(request.candidates[2].titleSeason, "季号集号没对上一集，不按标题比")
    XCTAssertNil(
      ExternalEvidenceRequest(
        tmdbID: 100, episodes: files, index: index(files, evidence: EpisodeEvidence()), evidence: EpisodeEvidence()))
  }

  func testLookupConfirmsFilesThatNumbersCannotPlace() {
    let farOff = file("farOff", episode: 38, ids: ["tvdb": "38"])
    let noNumbers = file("noNumbers", season: nil, episode: nil, ids: ["tvdb": "77"])
    let evidence = EpisodeEvidence(
      independentFiles: ["farOff", "noNumbers"],
      lookedUp: [
        "farOff": ExternalEpisodeMatch(tmdbEpisodeID: 102, source: "tvdb", value: "38"),
        "noNumbers": ExternalEpisodeMatch(tmdbEpisodeID: 104, source: "tvdb", value: "77"),
      ])
    let built = index([farOff, noNumbers], evidence: evidence)
    XCTAssertEqual(built.confirmedEpisodes(tmdbEpisodeID: 102).map(\.id), ["farOff"])
    XCTAssertEqual(built.confirmedEpisodes(tmdbEpisodeID: 104).map(\.id), ["noNumbers"])
    XCTAssertEqual(built.unidentifiedFileCount, 0, "反查到了就不再算认不出")
  }

  // MARK: 读取

  @MainActor
  func testLoaderLooksUpOnlyWhenTheLibraryDoesNotScrapeEpisodesFromTmdb() async throws {
    var requests: [ExternalEvidenceRequest] = []
    func load(_ fetchers: [String]?, profilesFail: Bool = false) async throws -> ServerEpisodeIndex {
      try await EpisodeMatchLoader.index(
        serverName: "emby", hasSeries: true,
        episodes: [file("e1", episode: 1, ids: ["tvdb": "9001"], path: "/tv/a.mkv")], incompleteReason: nil,
        sources: EpisodeMatchingSources(
          seasonList: { _ in self.chineseSeason }, seasons: { _ in [1] }, transferRecords: { [] },
          libraryProfiles: {
            if profilesFail { throw URLError(.timedOut) }
            return [MediaLibraryProfile(paths: ["/tv"], episodeFetchers: fetchers)]
          },
          externalEvidence: { request in
            requests.append(request)
            return ExternalEvidenceResult(
              lookedUp: ["e1": ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "9001")])
          }, tmdbID: 100),
        describe: { _ in "超时" })
    }
    let independent = try await load(["TheTVDB"])
    XCTAssertEqual(independent.availability(of: 103), .playable(server: "emby"))
    XCTAssertEqual(requests.map(\.tmdbID), [100])
    requests = []
    let fromTmdb = try await load(["TheTVDB", "TheMovieDb"])
    guard case .uncertain = fromTmdb.availability(of: 101) else { return XCTFail("来源含 TMDB 时只按季号集号") }
    XCTAssertTrue(requests.isEmpty, "不去补查")
    let unknown = try await load(nil, profilesFail: true)
    guard case .uncertain = unknown.availability(of: 101) else { return XCTFail("读不到配置按来源不明处理") }
    XCTAssertTrue(requests.isEmpty)
  }

  // MARK: 去 TMDB 补查

  private actor FakeDirectory: TmdbEpisodeDirectory {
    var found: [String: [TmdbFoundEpisode]] = [:]
    var seasons: [String: [TmdbEpisode]] = [:]
    var language: String? = "ja"
    var coolingDownOnFind = false
    private(set) var calls: [String] = []

    func set(found: [String: [TmdbFoundEpisode]], seasons: [String: [TmdbEpisode]], coolingDown: Bool = false) {
      self.found = found
      self.seasons = seasons
      coolingDownOnFind = coolingDown
    }

    var cached: Set<String> = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    var delay: Duration = .zero

    func setDelay(_ delay: Duration) { self.delay = delay }
    func setCached(_ keys: Set<String>) { cached = keys }

    func findEpisodes(source: String, value: String, access: TmdbAccess, cachedOnly: Bool) async throws
      -> [TmdbFoundEpisode]
    {
      if cachedOnly, !cached.contains("\(source) \(value)") { throw TmdbDirectError.notCached }
      calls.append("find \(source) \(value)")
      inFlight += 1
      maxInFlight = max(maxInFlight, inFlight)
      defer { inFlight -= 1 }
      if delay > .zero { try await Task.sleep(for: delay) }
      if coolingDownOnFind { throw TmdbDirectError.coolingDown }
      return found["\(source) \(value)"] ?? []
    }

    func seasonEpisodes(tvID: Int, season: Int, language: String, access: TmdbAccess, cachedOnly: Bool) async throws
      -> [TmdbEpisode]
    {
      if cachedOnly { throw TmdbDirectError.notCached }
      calls.append("season \(season) \(language)")
      return seasons["\(season) \(language)"] ?? []
    }

    func originalLanguage(tvID: Int, access: TmdbAccess, cachedOnly: Bool) async throws -> String? {
      if cachedOnly { throw TmdbDirectError.notCached }
      calls.append("language")
      return language
    }
  }

  private let access = TmdbAccess(apiKey: "k", domain: "api.themoviedb.org", locale: "zh")

  func testCollectKeepsOnlyAnUnambiguousEpisodeOfThisSeries() async {
    let directory = FakeDirectory()
    await directory.set(
      found: [
        "tvdb 1": [TmdbFoundEpisode(id: 103, showID: 100), TmdbFoundEpisode(id: 900, showID: 999)],
        "tvdb 2": [TmdbFoundEpisode(id: 104, showID: 100), TmdbFoundEpisode(id: 105, showID: 100)],
        "tvdb 3": [], "imdb tt3": [TmdbFoundEpisode(id: 106, showID: 100)],
      ],
      seasons: ["1 ja": [TmdbEpisode(id: 101, episodeNumber: 1, name: "雨の日")], "1 en-US": []])
    let request = ExternalEvidenceRequest(
      tmdbID: 100,
      candidates: [
        .init(itemID: "a", externalIDs: [("tvdb", "1")], titleSeason: nil),
        .init(itemID: "b", externalIDs: [("tvdb", "2"), ("imdb", "tt2")], titleSeason: 1),
        .init(itemID: "c", externalIDs: [("tvdb", "3"), ("imdb", "tt3")], titleSeason: nil),
      ])
    let result = await TmdbEpisodeEvidence.collect(request, access: access, directory: directory, cachedOnly: false)
    XCTAssertTrue(result.isComplete)
    XCTAssertEqual(result.lookedUp["a"], ExternalEpisodeMatch(tmdbEpisodeID: 103, source: "tvdb", value: "1"))
    XCTAssertNil(result.lookedUp["b"], "这部剧有两集：关联有歧义")
    XCTAssertEqual(result.lookedUp["c"]?.tmdbEpisodeID, 106, "TVDB 查不到再用 IMDb")
    XCTAssertEqual(result.translatedSeasons[1]?.count, 1, "没反查到的文件再取原语言和英文季列表，空列表不要")
    let calls = await directory.calls
    XCTAssertFalse(calls.contains("find imdb tt2"), "有歧义时不再用别的编号")
    XCTAssertTrue(calls.contains("season 1 ja") && calls.contains("season 1 en-US"))
  }

  func testCollectStopsWhenTmdbIsRateLimited() async {
    let directory = FakeDirectory()
    await directory.set(found: [:], seasons: [:], coolingDown: true)
    let request = ExternalEvidenceRequest(
      tmdbID: 100, candidates: [.init(itemID: "a", externalIDs: [("tvdb", "1")], titleSeason: 1)])
    let result = await TmdbEpisodeEvidence.collect(request, access: access, directory: directory, cachedOnly: false)
    XCTAssertTrue(result.isEmpty)
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
    let result = await TmdbEpisodeEvidence.collect(request, access: access, directory: directory, cachedOnly: true)
    XCTAssertEqual(result.lookedUp["a"]?.tmdbEpisodeID, 103, "缓存里有的马上用")
    XCTAssertFalse(result.isComplete, "没查过的交给后台")
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
      request, access: access, directory: directory, cachedOnly: false, budget: .milliseconds(200))
    let calls = await directory.calls
    let peak = await directory.maxInFlight
    XCTAssertEqual(peak, 2, "同时最多两个，不往限速队列里堆")
    XCTAssertLessThan(calls.count, 12, "到时间不再发新的")
    XCTAssertFalse(result.isComplete)
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
      "/find/81189", body: #"{"tv_episode_results":[{"id":103,"show_id":100},{"id":0,"show_id":100}]}"#)
    let fileURL = temporaryFile()
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let proxy = TmdbProxy(kind: .http(tls: false), host: "192.168.1.2", port: 7890, username: nil, password: nil)
    let secret = TmdbAccess(apiKey: "secret-key", domain: "api.example.org/prefix", proxy: proxy)
    let store = TmdbLookupStore(fileURL: fileURL, transport: transport)
    let found = try await store.findEpisodes(source: "tvdb", value: "81189", access: secret, cachedOnly: false)
    XCTAssertEqual(found, [TmdbFoundEpisode(id: 103, showID: 100)])
    _ = try await store.findEpisodes(source: "tvdb", value: "81189", access: secret, cachedOnly: false)
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
    _ = try await reloaded.findEpisodes(source: "tvdb", value: "81189", access: secret, cachedOnly: true)
    XCTAssertEqual(transport.count, 1, "重启后从磁盘读")
    do {
      _ = try await reloaded.findEpisodes(source: "tvdb", value: "1", access: secret, cachedOnly: true)
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
    let empty = try await store.findEpisodes(source: "tvdb", value: "1", access: access, cachedOnly: false)
    XCTAssertEqual(empty, [])
    clock += TmdbLookupStore.missLife - 60
    _ = try await store.findEpisodes(source: "tvdb", value: "1", access: access, cachedOnly: false)
    XCTAssertEqual(transport.count, 1)
    clock += 120
    _ = try await store.findEpisodes(source: "tvdb", value: "1", access: access, cachedOnly: false)
    XCTAssertEqual(transport.count, 2, "查不到的过一周再查")

    do {
      _ = try await store.findEpisodes(source: "tvdb", value: "2", access: access, cachedOnly: false)
      XCTFail("429 要报限流")
    } catch {
      XCTAssertEqual(error as? TmdbDirectError, .coolingDown)
    }
    do {
      _ = try await store.findEpisodes(source: "tvdb", value: "3", access: access, cachedOnly: false)
      XCTFail("暂停期间不发请求")
    } catch {
      XCTAssertEqual(error as? TmdbDirectError, .coolingDown)
    }
    XCTAssertEqual(transport.count, 3)
    clock += 31
    _ = try? await store.findEpisodes(source: "tvdb", value: "3", access: access, cachedOnly: false)
    XCTAssertEqual(transport.count, 4, "过了 Retry-After 再查")
  }

  func testRecentSeasonsAreCachedOnlyBriefly() async throws {
    let transport = FakeTransport()
    transport.respond(
      "/tv/100/season/1",
      body: #"{"episodes":[{"id":101,"episode_number":1,"name":"Rainy Day","air_date":"2026-11-10"}]}"#)
    nonisolated(unsafe) var clock = ISO8601DateFormatter().date(from: "2026-11-13T00:00:00Z")!
    let store = TmdbLookupStore(fileURL: nil, transport: transport, now: { clock })
    let list = try await store.seasonEpisodes(tvID: 100, season: 1, language: "en-US", access: access, cachedOnly: false)
    XCTAssertEqual(list.first?.name, "Rainy Day")
    clock += TmdbLookupStore.freshLife + 60
    _ = try await store.seasonEpisodes(tvID: 100, season: 1, language: "en-US", access: access, cachedOnly: false)
    XCTAssertEqual(transport.count, 2, "刚播出的季几天后重新取")
  }
}
