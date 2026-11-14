import Combine
import XCTest

@testable import MoviePilot_TV

// MARK: - 版本门禁、集列表与服务器条目（纯逻辑）

final class EpisodePlaybackModelTests: XCTestCase {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  func testInAppPlaybackStartsFromBackend326() {
    XCTAssertFalse(InAppPlaybackAvailability.supports(backendVersion: "v3.2.5"))
    XCTAssertFalse(InAppPlaybackAvailability.supports(backendVersion: "v3.1.9"))
    XCTAssertTrue(InAppPlaybackAvailability.supports(backendVersion: "v3.2.6"))
    XCTAssertTrue(InAppPlaybackAvailability.supports(backendVersion: "3.2.6"))
    XCTAssertTrue(InAppPlaybackAvailability.supports(backendVersion: "v3.2.6-1"), "热修复版本照常提供")
    XCTAssertTrue(InAppPlaybackAvailability.supports(backendVersion: "v3.3.0"), "未登记的更新版本照常提供")
    XCTAssertFalse(InAppPlaybackAvailability.supports(backendVersion: nil), "读不出版本时不提供")
    XCTAssertFalse(InAppPlaybackAvailability.supports(backendVersion: "dev"), "无法解析的版本不提供")
    XCTAssertTrue(
      InAppPlaybackAvailability.offers(mediaType: "电视剧", canRequestSuperUserEndpoints: true, backendVersion: "v3.2.6"))
    XCTAssertFalse(
      InAppPlaybackAvailability.offers(mediaType: "电视剧", canRequestSuperUserEndpoints: true, backendVersion: "v3.2.5"))
    XCTAssertFalse(
      InAppPlaybackAvailability.offers(mediaType: "电影", canRequestSuperUserEndpoints: false, backendVersion: "v3.2.6"))
    XCTAssertFalse(
      InAppPlaybackAvailability.offers(
        mediaType: "电影", canRequestSuperUserEndpoints: true, backendVersion: "v3.2.6", userEnabled: false),
      "设置里关掉后不提供")
    XCTAssertFalse(
      InAppPlaybackAvailability.isEnabled(backendVersion: "v3.2.5", userEnabled: true), "旧后端设置里打开也不提供")
  }

  func testGroupEpisodeKeepsDetailNumberingAndTMDBEpisodeID() throws {
    // 剧集组：原来的第 2 季第 3 集在组内显示为第 1 季第 10 集。返回里的 season_number 仍是原季号 2。
    let episodes = try decode(
      [TmdbEpisode].self,
      #"""
      [
        {"id":4533239,"season_number":2,"episode_number":10,"name":"重逢","still_path":"/a.jpg","air_date":"2023-06-21","runtime":45},
        {"id":0,"season_number":2,"episode_number":11,"name":"占位编号"},
        {"season_number":2,"episode_number":12,"name":123,"overview":"名称类型不对也只丢这个字段"}
      ]
      """#)
    let list = MoviePilotEpisode.list(episodes, season: 1)
    XCTAssertEqual(list.map(\.seasonNumber), [1, 1, 1], "显示用请求时的组内季号，不用返回的原季号")
    XCTAssertEqual(list.map(\.episodeNumber), [10, 11, 12])
    XCTAssertEqual(list.map(\.tmdbEpisodeID), [4_533_239, nil, nil], "0 和缺失都不是有效的 TMDB 单集 ID")
    XCTAssertEqual(list.map(\.index), [0, 1, 2])
    XCTAssertNil(list[2].name)
    XCTAssertEqual(list[2].overview, "名称类型不对也只丢这个字段")
    let titles = list[0].playbackMetadata(seriesName: "长风渡", stillURL: nil).playerTitles(isEpisode: true)
    XCTAssertEqual(titles.primary, "第 1 季 第 10 集 · 重逢")
    XCTAssertEqual(titles.secondary, "长风渡")
  }

  func testEmbyEpisodeKeepsTMDBEpisodeIDAndFileRange() throws {
    let page = try decode(
      EmbyItemsPage.self,
      #"""
      {"Items":[
        {"Id":"e1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":2,"ProviderIds":{"Tmdb":"555"}},
        {"Id":"e2","ParentIndexNumber":1,"IndexNumber":3,"ProviderIds":{"tmdb_id":"556"},"LocationType":"Virtual"},
        {"Id":"e3","Type":"Episode","ProviderIds":{"Tmdb":"0","Tvdb":"9"}}
      ]}
      """#)
    let items = page.items.map { $0.serverItem(defaultKind: .episode) }
    XCTAssertEqual(items.map(\.tmdbEpisodeID), [555, 556, nil])
    XCTAssertEqual(items[0].episodeNumberEnd, 2, "一个文件包含多集时记下最后一集")
    XCTAssertEqual(items[1].kind, .episode, "剧集列表里没写类型的按单集")
    XCTAssertFalse(items[1].hasFile, "Virtual 是没有文件的缺失集")
    XCTAssertEqual(items[2].externalID(for: "tvdb"), "9")
  }

  func testEmbyListWithoutItemsIsNotAnEmptyList() throws {
    // 只有确实读到 Items: [] 才是空列表；缺字段、类型不对是回包无法识别，不能当作“这部剧没有集”。
    XCTAssertEqual(try decode(EmbyItemsPage.self, #"{"Items":[]}"#).items.count, 0)
    XCTAssertThrowsError(try decode(EmbyItemsPage.self, #"{}"#))
    XCTAssertThrowsError(try decode(EmbyItemsPage.self, #"{"Items":"x"}"#))
    XCTAssertThrowsError(try decode(EmbyItemsPage.self, #"{"Items":[{}]}"#))
    XCTAssertEqual(
      try decode(EmbyItemsPage.self, #"{"Items":[{"Id":"e1"},{"Name":"没有 Id"}]}"#).items.map(\.id), ["e1"],
      "单个条目坏掉只丢它")

    XCTAssertThrowsError(try decode(EmbyPlaybackInfo.self, #"{"PlaySessionId":"p"}"#), "缺少片源列表不当作没有可播放的文件")
    XCTAssertEqual(
      try decode(EmbyPlaybackInfo.self, #"{"ErrorCode":"NotAllowed"}"#).errorCode, "NotAllowed", "带错误码时可以没有片源列表")
  }

  func testEmbyPlaybackInfoDistinguishesEmptySourcesFromMalformedEntries() throws {
    XCTAssertTrue(try decode(EmbyPlaybackInfo.self, #"{"MediaSources":[]}"#).mediaSources.isEmpty)
    XCTAssertThrowsError(try decode(EmbyPlaybackInfo.self, #"{"MediaSources":[{}]}"#))
    XCTAssertEqual(
      try decode(EmbyPlaybackInfo.self, #"{"MediaSources":[{},{"Id":"valid"}]}"#).mediaSources.map(\.id), ["valid"])
    XCTAssertEqual(
      try decode(EmbyPlaybackInfo.self, #"{"MediaSources":[{}],"ErrorCode":"NotAllowed"}"#).errorCode, "NotAllowed")
  }

  func testEmbyErrorsAreClassifiedByWhatToDoNext() {
    XCTAssertEqual(EmbyClientError.unreachable(transportSecurity: false).reason, .unreachable)
    XCTAssertEqual(EmbyClientError.unreachable(transportSecurity: true).reason, .transportSecurity)
    XCTAssertEqual(EmbyClientError.certificate.reason, .certificate)
    XCTAssertEqual(EmbyClientError.http(400).reason, .badRequest)
    XCTAssertEqual(EmbyClientError.http(401).reason, .unauthorized)
    XCTAssertEqual(EmbyClientError.http(403).reason, .forbidden)
    XCTAssertEqual(EmbyClientError.http(404).reason, .notFound)
    XCTAssertEqual(EmbyClientError.http(502).reason, .serverError(502))
    XCTAssertEqual(EmbyClientError.http(409).reason, .status(409))
    XCTAssertEqual(EmbyClientError.invalidResponse.reason, .invalidResponse)
    XCTAssertTrue(MediaServerError.Reason.unauthorized.isServerWide, "密钥无效：换一份副本也没用")
    XCTAssertFalse(MediaServerError.Reason.serverError(500).isServerWide, "服务器出错：先试其他副本")
    XCTAssertEqual(
      MediaServerError(server: "家里", operation: .readEpisodes, reason: .serverError(500)).errorDescription,
      "媒体服务器“家里”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试")
  }

  func testEpisodeContextNeedsTMDBSeries() {
    let series = MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: " 长风渡 ", type: "电视剧")
    let context = EpisodePlaybackContext(
      media: series, episodeGroup: "  ", seasons: [1, 2], libraryItem: MediaServerItemRef(itemID: "9", server: "emby"))
    XCTAssertEqual(context?.tmdbID, 100)
    XCTAssertNil(context?.episodeGroup, "空白剧集组按默认顺序")
    XCTAssertEqual(context?.seriesName, "长风渡")
    XCTAssertEqual(context?.expected.kind, .series)
    XCTAssertNil(
      EpisodePlaybackContext(
        media: MediaInfo(tmdb_id: 100, type: "电影"), episodeGroup: nil, seasons: [], libraryItem: nil))
    XCTAssertNil(
      EpisodePlaybackContext(
        media: MediaInfo(tmdb_id: 0, douban_id: "35", type: "电视剧"), episodeGroup: nil, seasons: [], libraryItem: nil),
      "没有 TMDB 编号的剧没有集列表接口")
  }

  // MARK: 每集能不能播

  private func episode(_ id: Int?, season: Int = 1, number: Int? = nil, index: Int = 0) -> MoviePilotEpisode {
    MoviePilotEpisode(TmdbEpisode(id: id, episodeNumber: number ?? index + 1), season: season, index: index)
  }

  private func serverEpisode(_ id: String, tmdb: Int?, hasFile: Bool = true) -> ServerMediaItem {
    ServerMediaItem(
      id: id, kind: .episode, hasFile: hasFile, externalIDs: tmdb.map { ["tmdb": String($0)] } ?? [:])
  }

  private func index(_ server: String, hasSeries: Bool = true, _ episodes: [ServerMediaItem]) -> ServerEpisodeLookup {
    .loaded(ServerEpisodeIndex(serverName: server, hasSeries: hasSeries, episodes: episodes))
  }

  private func multiFile(_ id: String, tmdb: Int, season: Int = 1, from first: Int, to last: Int) -> ServerMediaItem {
    ServerMediaItem(
      id: id, kind: .episode, seasonNumber: season, episodeNumber: first, episodeNumberEnd: last,
      externalIDs: ["tmdb": String(tmdb)])
  }

  /// MoviePilot 默认顺序的一季：TMDB 单集 ID 从 `firstID` 起连续，集号从 1 起。
  private func defaultSeason(_ season: Int = 1, count: Int, firstID: Int) -> [TmdbEpisode] {
    (0..<count).map { TmdbEpisode(id: firstID + $0, episodeNumber: $0 + 1, seasonNumber: season) }
  }

  /// 第 1 季默认顺序列表：第 1–12 集是 TMDB 101–112。
  private var defaultLists: [EpisodeListKey: [TmdbEpisode]] {
    [EpisodeListKey(episodeGroup: nil, season: 1): defaultSeason(count: 12, firstID: 101)]
  }

  func testMultiEpisodeFileCoversTheLaterEpisodesWhenNumberingMatches() {
    // S01E09-E10 只记了 E09 的 TMDB 单集 ID（109）；按默认顺序列表核对后，E10（110）也在这个文件里。
    let file = multiFile("e9-10", tmdb: 109, from: 9, to: 10)
    let index = ServerEpisodeIndex(
      serverName: "emby", hasSeries: true, episodes: [serverEpisode("e8", tmdb: 108), file], lists: defaultLists)
    XCTAssertEqual(index.availability(of: 110), .playable(server: "emby"))
    XCTAssertEqual(index.playableEpisode(tmdbEpisodeID: 110)?.id, "e9-10")
    XCTAssertEqual(index.availability(of: 111), .notOnServer, "文件之外的集照常按没有")
    XCTAssertEqual(index.summary.byEpisodeID, 2, "一个文件只算一次")
    XCTAssertEqual(
      ServerEpisodeIndex.requiredLists(for: [serverEpisode("e8", tmdb: 108), file], records: []),
      [EpisodeListKey(episodeGroup: nil, season: 1)])
  }

  func testMultiEpisodeFileIsNotStretchedWhenNumberingDisagrees() {
    // 文件的 TMDB 单集 ID 在默认顺序里是第 8 集，和文件名的 E09 对不上：不知道文件按哪套编号，不推算。
    let file = multiFile("e9-10", tmdb: 108, from: 9, to: 10)
    let index = ServerEpisodeIndex(serverName: "emby", hasSeries: true, episodes: [file], lists: defaultLists)
    XCTAssertEqual(index.availability(of: 110), .notOnServer)
    XCTAssertEqual(index.availability(of: 109), .notOnServer)
    let unread = ServerEpisodeIndex(serverName: "emby", hasSeries: true, episodes: [multiFile("f", tmdb: 109, from: 9, to: 10)])
    XCTAssertEqual(unread.availability(of: 110), .notOnServer, "没给默认顺序列表时不推算")
  }

  func testRereadMultiEpisodeFileIsAcceptedOnlyIfItIsUnchanged() {
    let recorded = multiFile("e9-10", tmdb: 109, from: 9, to: 10)
    XCTAssertEqual(ServerEpisodeIndex.recheck(recorded, recorded: recorded, tmdbEpisodeID: 110), .same)
    XCTAssertEqual(ServerEpisodeIndex.recheck(recorded, recorded: recorded, tmdbEpisodeID: 109), .same)
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(multiFile("e9-10", tmdb: 109, from: 9, to: 9), recorded: recorded, tmdbEpisodeID: 110),
      .changed, "重新刮削后不再包含第 10 集")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(multiFile("e9-10", tmdb: 120, from: 9, to: 10), recorded: recorded, tmdbEpisodeID: 110),
      .changed, "编号变了")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(recorded, recorded: serverEpisode("e9-10", tmdb: 109), tmdbEpisodeID: 110),
      .changed, "集索引没记它包含多集")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(recorded, recorded: nil, tmdbEpisodeID: 110), .changed,
      "播放中换集时只知道条目 ID：编号不是要的这一集，要重读集索引")
    XCTAssertEqual(
      ServerEpisodeIndex.recheck(serverEpisode("e9-10", tmdb: nil), recorded: recorded, tmdbEpisodeID: 110),
      .lostEpisodeID)
  }

  func testEpisodeWithItsOwnFileKeepsItBeforeTheMultiEpisodeFile() {
    let index = ServerEpisodeIndex(
      serverName: "emby", hasSeries: true,
      episodes: [multiFile("e9-10", tmdb: 109, from: 9, to: 10), serverEpisode("e10", tmdb: 110)], lists: defaultLists)
    XCTAssertEqual(index.playableEpisodes(tmdbEpisodeID: 110).map(\.id), ["e10", "e9-10"], "先播这一集自己的文件")
  }

  func testAvailabilityMatchesOnlyByTMDBEpisodeID() {
    let lookups = [
      index("a", [serverEpisode("a1", tmdb: 1), serverEpisode("a3", tmdb: 3, hasFile: false)]),
      index("b", [serverEpisode("b2", tmdb: 2), serverEpisode("b1", tmdb: 1)]),
    ]
    XCTAssertEqual(EpisodeAvailability.resolve(episode(1), lookups: lookups), .playable(server: "a"), "第一台有的为准")
    XCTAssertEqual(EpisodeAvailability.resolve(episode(2), lookups: lookups), .playable(server: "b"))
    XCTAssertEqual(EpisodeAvailability.resolve(episode(3), lookups: lookups), .notOnServer, "只有元数据没有文件不算有")
    XCTAssertEqual(EpisodeAvailability.resolve(episode(4), lookups: lookups), .notOnServer)
    XCTAssertEqual(EpisodeAvailability.resolve(episode(nil), lookups: lookups), .unidentifiable(.missingEpisodeID))
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(4), lookups: [index("a", hasSeries: false, [])]), .notOnServer,
      "整部剧不在服务器上")
  }

  @MainActor
  func testPlaybackSettingRowsFollowBackendVersionAndToggle() {
    XCTAssertEqual(
      SystemViewModel.playbackSettingRows(backendVersion: "v3.2.5", inAppPlaybackEnabled: true), [.versionRequirement],
      "旧后端只有版本说明，开关打不开")
    XCTAssertEqual(
      SystemViewModel.playbackSettingRows(backendVersion: nil, inAppPlaybackEnabled: true), [.versionRequirement])
    XCTAssertEqual(
      SystemViewModel.playbackSettingRows(backendVersion: "v3.2.6", inAppPlaybackEnabled: true),
      [.inAppPlayback, .homeMediaTap, .autoPlayNextEpisode])
    XCTAssertEqual(
      SystemViewModel.playbackSettingRows(backendVersion: "v3.2.6", inAppPlaybackEnabled: false), [.inAppPlayback],
      "关掉后只在应用内播放才有意义的两项不显示")
  }

  func testBackendVersionGatePolarities() {
    XCTAssertTrue(BackendVersionGate.isAvailable(since: "v3.2.6", backendVersion: "v3.2.6-1"))
    XCTAssertFalse(BackendVersionGate.isAvailable(since: "v3.2.6", backendVersion: "v3.2.5"))
    XCTAssertFalse(BackendVersionGate.isAvailable(since: "v3.2.6", backendVersion: nil), "新行为：读不出版本时不开放")
    XCTAssertTrue(BackendVersionGate.mayHaveSideEffect(since: "v3.2.0", backendVersion: nil), "副作用：读不出版本时照常提示")
    XCTAssertTrue(BackendVersionGate.mayHaveSideEffect(since: "v3.2.0", backendVersion: "garbage"))
    XCTAssertFalse(BackendVersionGate.mayHaveSideEffect(since: "v3.2.0", backendVersion: "v3.1.9"))
    XCTAssertTrue(BackendVersionGate.mayHaveSideEffect(since: "v3.2.0", backendVersion: "v3.2.0"))
  }

  func testServerEpisodeWithoutTMDBIDIsMatchedByNumbersAsUncertain() {
    // 服务器上第 1 季第 1 集没有 TMDB 单集 ID（只用 TVDB 刮削）：按季号集号对上默认顺序的第 1 集，可以播，但不确定。
    let noIDs = ServerMediaItem(id: "x", kind: .episode, seasonNumber: 1, episodeNumber: 1, externalIDs: ["tvdb": "9"])
    let lookup = ServerEpisodeLookup.loaded(
      ServerEpisodeIndex(serverName: "a", hasSeries: true, episodes: [noIDs], lists: defaultLists))
    let availability = EpisodeAvailability.resolve(episode(101, number: 1), lookups: [lookup])
    let match = UncertainEpisodeMatch(season: 1, episode: 1, episodeGroup: nil, airDate: .unknown)
    XCTAssertEqual(availability, .uncertain(server: "a", match: match))
    XCTAssertFalse(availability.isPlayable, "不确定的不算确定能播")
    XCTAssertEqual(
      availability.message,
      "可能不是这一集。按第 1 季第 1 集找到，无法核对播出日期")
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode(101, number: 1), current: lookup, others: []), .playable(noIDs),
      "接着播时照样用，不打断")
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(102, number: 2), lookups: [lookup]), .notOnServer,
      "文件都对上了，没有第 2 集")
  }

  func testAFileWithoutTMDBIDIsTreatedAsUnmatchedAndExplained() {
    // 第 1、3 集有 TMDB 单集 ID，第 2 集的文件刚入库还没刮削到（也没有季号集号）：第 2 集按没有处理，队列照常往后找；
    // 说明里提示这一集可能就在认不出的文件里，可以刷新元数据。
    let lookup = index(
      "a",
      [
        serverEpisode("a1", tmdb: 1), serverEpisode("a2", tmdb: nil), serverEpisode("a3", tmdb: 3),
        serverEpisode("virtual", tmdb: nil, hasFile: false),
      ])
    XCTAssertEqual(EpisodeAvailability.resolve(episode(1), lookups: [lookup]), .playable(server: "a"))
    let unmatched = EpisodeAvailability.resolve(episode(2), lookups: [lookup])
    XCTAssertEqual(unmatched, .unmatched(server: "a"))
    XCTAssertEqual(unmatched.message, "这一集可能已经入库。有文件认不出是哪一集，刷新元数据后再检查")
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(2), current: lookup, others: []), .unmatched(server: "a"))
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(4), lookups: [index("a", [serverEpisode("a1", tmdb: 1)])]), .notOnServer,
      "文件都带编号：确认没有")
    let onlyVirtualWithoutID = index("a", [serverEpisode("a1", tmdb: 1), serverEpisode("v", tmdb: nil, hasFile: false)])
    XCTAssertEqual(EpisodeAvailability.resolve(episode(2), lookups: [onlyVirtualWithoutID]), .notOnServer, "没有文件的缺集不算")
  }

  func testEachKindOfFailureHasItsOwnExplanation() {
    // 目标集本身缺 TMDB 编号、服务器读取失败、个别文件没编号，三种原因各说各的。
    let unmatched = index("a", [serverEpisode("a1", tmdb: 1), serverEpisode("a2", tmdb: nil)])
    let failed = ServerEpisodeLookup.failed(
      server: "b", message: "媒体服务器“b”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试")
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(nil), lookups: [unmatched]).message,
      "MoviePilot 没有提供这一集的 TMDB 编号，无法确认媒体服务器上对应哪一集")
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(2), lookups: [unmatched, failed]).message,
      "媒体服务器“b”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试", "读取失败在前：稍后重试可能就有")
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(2), lookups: [unmatched]).message,
      "这一集可能已经入库。有文件认不出是哪一集，刷新元数据后再检查")
  }

  func testIncompleteServerIndexIsNotTreatedAsMissing() {
    // 同一部剧在两个媒体库各有一份，其中一份读取失败：读到的那份里没有这一集，也不能说服务器上没有。
    let reason = "媒体服务器“a”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试"
    let partial = ServerEpisodeLookup.loaded(
      ServerEpisodeIndex(
        serverName: "a", hasSeries: true, episodes: [serverEpisode("a1", tmdb: 1)], incompleteReason: reason))
    XCTAssertEqual(EpisodeAvailability.resolve(episode(1), lookups: [partial]), .playable(server: "a"))
    XCTAssertEqual(EpisodeAvailability.resolve(episode(2), lookups: [partial]), .failed(reason))
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(2), current: partial, others: []), .unknown(reason))
  }

  func testReadFailureIsNotTreatedAsMissing() {
    let lookups: [ServerEpisodeLookup] = [
      .failed(server: "a", message: "无法连接“a”"),
      index("b", [serverEpisode("b1", tmdb: 1)]),
    ]
    XCTAssertEqual(EpisodeAvailability.resolve(episode(1), lookups: lookups), .playable(server: "b"))
    XCTAssertEqual(EpisodeAvailability.resolve(episode(2), lookups: lookups), .failed("无法连接“a”"))
  }

  func testQueueStatusIsRelativeToCurrentServer() {
    let current = index("a", [serverEpisode("a1", tmdb: 1)])
    let others = [index("b", [serverEpisode("b2", tmdb: 2)])]
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode(1), current: current, others: others), .playable(serverEpisode("a1", tmdb: 1)))
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(2), current: current, others: others), .elsewhere(server: "b"))
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(3), current: current, others: others), .absent)
    guard case .unknown = EpisodeQueueStatus.resolve(episode(nil), current: current, others: others) else {
      return XCTFail("缺少编号不能当作没有")
    }
  }

  func testQueueStatusIsUnknownWhenTheCurrentServerFailedToLoad() {
    // 当前服务器读取超时、另一台有这一集：可能当前服务器上也有，不能说“只在另一台上”。
    let current = ServerEpisodeLookup.failed(server: "a", message: "无法连接“a”")
    XCTAssertEqual(EpisodeQueueStatus.onCurrentServer(episode(2), lookup: current), .unknown("无法连接“a”"))
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode(2), current: current, others: [index("b", [serverEpisode("b2", tmdb: 2)])]),
      .unknown("无法连接“a”"))
  }

  func testQueueStatusOnlyNeedsOtherServersWhenTheCurrentOneHasNoMatch() {
    let identified = index("a", [serverEpisode("a1", tmdb: 1)])
    XCTAssertNil(EpisodeQueueStatus.onCurrentServer(episode(2), lookup: identified), "当前服务器上没有：要看其他服务器")
    let unidentified = index("a", [serverEpisode("a1", tmdb: 1), serverEpisode("a2", tmdb: nil)])
    XCTAssertNil(EpisodeQueueStatus.onCurrentServer(episode(2), lookup: unidentified), "个别文件没编号也按没有，再看其他服务器")
    XCTAssertEqual(
      EpisodeQueueStatus.onCurrentServer(episode(nil), lookup: identified),
      .unknown(EpisodeAvailability.UnidentifiableReason.missingEpisodeID.message))
  }

  @MainActor
  func testLibraryItemIDIsOnlyTriedOnTheServerThatOwnsIt() {
    XCTAssertEqual(PlaybackCoordinator.idFallbackStrictness(on: "a", owner: "a", strict: true), false, "所属服务器上不要求外部编号")
    XCTAssertNil(PlaybackCoordinator.idFallbackStrictness(on: "b", owner: "a", strict: true), "别的服务器上同号的是另一部")
    XCTAssertNil(PlaybackCoordinator.idFallbackStrictness(on: "b", owner: "a", strict: false), "只启用一台也不拿别处的 ID 找")
    XCTAssertEqual(PlaybackCoordinator.idFallbackStrictness(on: "a", owner: nil, strict: true), true)
    XCTAssertEqual(PlaybackCoordinator.idFallbackStrictness(on: "a", owner: nil, strict: false), false)
  }

  @MainActor
  func testFailedSwitchExitsOnlyAfterTheEpisodeEnded() {
    XCTAssertEqual(
      MediaSession.afterFailedSwitch(message: "没有找到", currentItemEnded: false), .stay(error: "没有找到"),
      "还在播：留在原处提示")
    XCTAssertEqual(
      MediaSession.afterFailedSwitch(message: "没有找到", currentItemEnded: true), .exit(notice: "没有找到"),
      "片尾自动接下一集失败：退出并说明，不停在加载中")
    XCTAssertEqual(MediaSession.afterFailedSwitch(message: nil, currentItemEnded: true), .exit(notice: nil))
  }
}

// MARK: - 上一集、下一集

final class EpisodeNavigatorTests: XCTestCase {
  private struct LoadFailure: Error {}

  /// 记下读过哪些季的集列表。
  private final class SeasonLoads {
    var seasons: [Int] = []
  }

  private func list(season: Int, ids: [Int?]) -> [MoviePilotEpisode] {
    MoviePilotEpisode.list(ids.map { TmdbEpisode(id: $0, episodeNumber: nil) }, season: season)
  }

  private func item(_ id: String) -> ServerMediaItem { ServerMediaItem(id: id, kind: .episode) }

  /// 正在播的一集。`known` 是它所在那一季的列表（选中这一集时的那份），默认取 `lists` 里的那一季。
  private func queued(
    _ episode: MoviePilotEpisode, seasons: [Int], known: [MoviePilotEpisode]
  ) -> QueuedEpisode {
    let context = EpisodePlaybackContext(
      media: MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧"),
      episodeGroup: nil, seasons: seasons, libraryItem: nil)!
    return QueuedEpisode(context: context, episode: episode, seasonEpisodes: known)
  }

  /// `statuses`：TMDB 单集 ID → 状态；没写的按确认没有。`lists` 是重新读到的各季集列表。
  private func navigate(
    _ direction: EpisodeNavigator.Direction, from current: MoviePilotEpisode, currentItemID: String = "current",
    seasons: [Int], lists: [Int: [MoviePilotEpisode]], known: [MoviePilotEpisode]? = nil,
    statuses: [Int: EpisodeQueueStatus], failingSeasons: Set<Int> = [], episodeIDsOnServer: Set<Int>? = nil,
    loads: SeasonLoads? = nil
  ) async throws -> EpisodeNavigator.Outcome {
    try await EpisodeNavigator.adjacent(
      direction, from: queued(current, seasons: seasons, known: known ?? lists[current.seasonNumber] ?? []),
      currentItemID: currentItemID, episodeIDsOnServer: episodeIDsOnServer,
      loadSeason: { season in
        loads?.seasons.append(season)
        if failingSeasons.contains(season) { throw LoadFailure() }
        return lists[season] ?? []
      },
      status: { episode in episode.tmdbEpisodeID.flatMap { statuses[$0] } ?? .absent })
  }

  private func entry(_ episode: MoviePilotEpisode, _ itemID: String, in list: [MoviePilotEpisode]) -> EpisodeQueueEntry {
    EpisodeQueueEntry(episode: episode, item: item(itemID), seasonEpisodes: list)
  }

  func testNextSkipsMissingEpisodesAndTheSameFile() async throws {
    let season1 = list(season: 1, ids: [10, 11, 12, 13])
    let outcome = try await navigate(
      .next, from: season1[0], currentItemID: "file-1", seasons: [1],
      lists: [1: season1],
      statuses: [10: .playable(item("file-1")), 11: .playable(item("file-1")), 13: .playable(item("file-3"))])
    XCTAssertEqual(
      outcome, .play(entry(season1[3], "file-3", in: season1), skippedMissing: true),
      "第 11 集和当前是同一个文件，第 12 集确认没有，都跳过；跳过了缺集，播完时要复查")
  }

  func testNextStopsWhenItCannotBeConfirmed() async throws {
    let season1 = list(season: 1, ids: [10, 11, 12])
    let elsewhere = try await navigate(
      .next, from: season1[0], seasons: [1], lists: [1: season1],
      statuses: [11: .elsewhere(server: "b"), 12: .playable(item("e12"))])
    XCTAssertEqual(elsewhere, .stop("下一集在另一台媒体服务器“b”上，请回到详情页选择"))

    let unknown = try await navigate(
      .next, from: season1[0], seasons: [1], lists: [1: season1],
      statuses: [11: .unknown("无法连接“b”"), 12: .playable(item("e12"))])
    XCTAssertEqual(unknown, .stop("无法确认下一集：无法连接“b”"), "读取失败不能当作没有而跳过")
  }

  func testNextCrossesIntoTheNextSeasonInDetailOrder() async throws {
    let season1 = list(season: 1, ids: [10, 11])
    let season2 = list(season: 2, ids: [20, 21])
    let outcome = try await navigate(
      .next, from: season1[1], seasons: [0, 1, 2], lists: [1: season1, 2: season2],
      statuses: [21: .playable(item("e21"))])
    XCTAssertEqual(outcome, .play(entry(season2[1], "e21", in: season2), skippedMissing: true), "特别篇不参与跨季")

    let end = try await navigate(.next, from: season2[1], seasons: [0, 1, 2], lists: [1: season1, 2: season2], statuses: [:])
    XCTAssertEqual(end, .end)
  }

  func testNextEpisodesNotOnServerYetAreReportedAsMissing() async throws {
    // 订阅还在下载：第 11、12 集在集列表里，但服务器上还没有。
    let season1 = list(season: 1, ids: [10, 11, 12])
    let outcome = try await navigate(.next, from: season1[0], seasons: [1], lists: [1: season1], statuses: [:])
    XCTAssertEqual(outcome, .missing)
    let last = try await navigate(.next, from: season1[2], seasons: [1], lists: [1: season1], statuses: [:])
    XCTAssertEqual(last, .end, "最后一集之后什么都没有")
  }

  func testPreviousWalksBackwardsAcrossSeasons() async throws {
    let season1 = list(season: 1, ids: [10, 11])
    let season2 = list(season: 2, ids: [20, 21])
    let outcome = try await navigate(
      .previous, from: season2[0], seasons: [1, 2], lists: [1: season1, 2: season2],
      statuses: [10: .playable(item("e10"))])
    XCTAssertEqual(outcome, .play(entry(season1[0], "e10", in: season1), skippedMissing: true), "第 11 集确认没有，跳到第 10 集")
  }

  func testPreviousStopsReadingSeasonsOnceNothingEarlierIsOnTheServer() async throws {
    // 服务器上只有第 5 季：往前找不再为前面几季逐季读 MoviePilot 的集列表。
    let seasons = Array(1...5)
    var lists: [Int: [MoviePilotEpisode]] = [:]
    for season in seasons { lists[season] = list(season: season, ids: [season * 100, season * 100 + 1]) }
    let loads = SeasonLoads()
    let outcome = try await navigate(
      .previous, from: lists[5]![0], seasons: seasons, lists: lists, statuses: [501: .playable(item("e501"))],
      episodeIDsOnServer: [500, 501], loads: loads)
    XCTAssertEqual(outcome, .end)
    XCTAssertEqual(loads.seasons, [5])

    // 第 3 季也在服务器上：照常读到第 3 季为止。
    let earlier = SeasonLoads()
    let found = try await navigate(
      .previous, from: lists[5]![0], seasons: seasons, lists: lists, statuses: [301: .playable(item("e301"))],
      episodeIDsOnServer: [301, 500], loads: earlier)
    XCTAssertEqual(found, .play(entry(lists[3]![1], "e301", in: lists[3]!), skippedMissing: true))
    XCTAssertEqual(earlier.seasons, [5, 4, 3])
  }

  func testSpecialsOnlyMoveWithinSeasonZero() async throws {
    let specials = list(season: 0, ids: [1, 2])
    let season1 = list(season: 1, ids: [10])
    let outcome = try await navigate(
      .next, from: specials[1], seasons: [0, 1], lists: [0: specials, 1: season1], statuses: [10: .playable(item("e10"))])
    XCTAssertEqual(outcome, .end)
  }

  func testSeasonListFailureStops() async throws {
    let season1 = list(season: 1, ids: [10])
    let outcome = try await navigate(
      .next, from: season1[0], seasons: [1, 2], lists: [1: season1], statuses: [:], failingSeasons: [2])
    XCTAssertEqual(outcome, .stop("没能从 MoviePilot 读取第 2 季的集列表：请稍后重试"))
  }

  func testEmptySeasonListStopsInsteadOfSkippingTheSeason() async throws {
    // MoviePilot 读 TMDB 失败时返回空列表：当作没有第 2 季、接着找第 3 季，就会把第 2 季整季跳过。
    let season1 = list(season: 1, ids: [10])
    let season3 = list(season: 3, ids: [30])
    let outcome = try await navigate(
      .next, from: season1[0], seasons: [1, 2, 3], lists: [1: season1, 2: [], 3: season3],
      statuses: [30: .playable(item("e30"))])
    XCTAssertEqual(outcome, .stop("第 2 季集列表暂不可用，请重试"))

    // 前面跳过了还不在服务器上的第 11 集：空列表也不能说成“下一集还不在”，照样请用户重试。
    let season1WithGap = list(season: 1, ids: [10, 11])
    let afterGap = try await navigate(
      .next, from: season1WithGap[0], seasons: [1, 2, 3], lists: [1: season1WithGap, 2: [], 3: season3],
      statuses: [30: .playable(item("e30"))])
    XCTAssertEqual(afterGap, .stop("第 2 季集列表暂不可用，请重试"))
  }

  func testScanningStopsAfterAFewEmptySeasons() async throws {
    let seasons = Array(1...10)
    var lists: [Int: [MoviePilotEpisode]] = [:]
    for season in seasons { lists[season] = list(season: season, ids: [season * 100]) }
    let loads = SeasonLoads()
    let outcome = try await navigate(
      .next, from: lists[1]![0], seasons: seasons, lists: lists, statuses: [1000: .playable(item("e"))], loads: loads)
    XCTAssertEqual(outcome, .missing, "后面还有集，只是都不在服务器上")
    XCTAssertEqual(loads.seasons, [1, 2, 3, 4], "后面几季都没有时不把所有季的集列表都读一遍")
  }

  func testCurrentEpisodeIsRelocatedByTMDBIDAfterTheListChanges() async throws {
    // 开播时这一集在第 0 位，之后列表前面插入了一集。
    let opened = list(season: 1, ids: [10, 11])
    let refreshed = list(season: 1, ids: [9, 10, 11])
    let outcome = try await navigate(
      .next, from: opened[0], seasons: [1], lists: [1: refreshed], known: opened,
      statuses: [9: .playable(item("e9")), 11: .playable(item("e11"))])
    XCTAssertEqual(outcome, .play(entry(refreshed[2], "e11", in: refreshed), skippedMissing: false))
  }

  func testUnreliableCurrentSeasonListFallsBackToTheKnownOne() async throws {
    // 播完重新读到的本季列表是空的（MoviePilot 读 TMDB 失败）、读不到、或里面没有正在播的这一集：
    // 下一集是谁开播时就知道，服务器上有就接着播，不跳到下一季，也不停下。
    let opened = list(season: 1, ids: [10, 11, 12])
    let season2 = list(season: 2, ids: [20])
    let statuses: [Int: EpisodeQueueStatus] = [11: .playable(item("e11")), 20: .playable(item("e20"))]
    let expected = EpisodeNavigator.Outcome.play(entry(opened[1], "e11", in: opened), skippedMissing: false)

    let empty = try await navigate(
      .next, from: opened[0], seasons: [1, 2], lists: [1: [], 2: season2], known: opened, statuses: statuses)
    XCTAssertEqual(empty, expected)
    let failed = try await navigate(
      .next, from: opened[0], seasons: [1, 2], lists: [2: season2], known: opened, statuses: statuses,
      failingSeasons: [1])
    XCTAssertEqual(failed, expected)
    let other = try await navigate(
      .next, from: opened[0], seasons: [1, 2], lists: [1: list(season: 1, ids: [70, 71]), 2: season2], known: opened,
      statuses: statuses)
    XCTAssertEqual(other, expected)
  }

  func testCurrentEpisodeMissingFromBothListsStops() async throws {
    let opened = list(season: 1, ids: [10, 11])
    let outcome = try await navigate(
      .next, from: opened[0], seasons: [1], lists: [1: []], known: [], statuses: [11: .playable(item("e11"))])
    XCTAssertEqual(outcome, .stop("第 1 季集列表暂不可用，请重试"))
    let other = try await navigate(
      .next, from: opened[0], seasons: [1], lists: [1: list(season: 1, ids: [70])], known: [], statuses: [:])
    XCTAssertEqual(other, .stop("MoviePilot 返回的第 1 季集列表里没有正在播的这一集，无法确认下一集，请重试"))
    let failed = try await navigate(
      .next, from: opened[0], seasons: [1], lists: [:], known: [], statuses: [:], failingSeasons: [1])
    XCTAssertEqual(failed, .stop("没能从 MoviePilot 读取第 1 季的集列表：请稍后重试"))
  }

  func testQueuePanelListsEachFileOnce() async throws {
    let season1 = list(season: 1, ids: [10, 11, 12, 13])
    let entries = try await EpisodeNavigator.playableEntries(in: season1) { episode in
      switch episode.tmdbEpisodeID {
      case 10, 11: .playable(self.item("file-1"))
      case 13: .playable(self.item("file-3"))
      default: .absent
      }
    }
    XCTAssertEqual(entries.map(\.item.id), ["file-1", "file-3"])
    XCTAssertEqual(entries.map(\.episode.tmdbEpisodeID), [10, 13])
  }
}

// MARK: - 播放器里的按集队列（查询时序）

/// 每个查询都挂起，由测试决定什么时候、以什么结果返回。
@MainActor
private final class QueueSourceStub: EpisodeQueueSource {
  nonisolated deinit {}

  struct Request: Hashable {
    let direction: EpisodeNavigator.Direction
    let itemID: String
    var refresh = false

    static func next(_ itemID: String, refresh: Bool = false) -> Request {
      Request(direction: .next, itemID: itemID, refresh: refresh)
    }

    static func previous(_ itemID: String) -> Request {
      Request(direction: .previous, itemID: itemID)
    }
  }

  private var waiting: [Request: [CheckedContinuation<AdjacentEpisode, Error>]] = [:]

  func seasonEpisodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto] { [] }

  func adjacentEpisode(
    _ direction: EpisodeNavigator.Direction, itemID: String, refresh: Bool
  ) async throws -> AdjacentEpisode {
    let request = Request(direction: direction, itemID: itemID, refresh: refresh)
    return try await withCheckedThrowingContinuation { waiting[request, default: []].append($0) }
  }

  func isWaiting(_ request: Request) -> Bool {
    waiting[request]?.isEmpty == false
  }

  func answer(_ request: Request, with result: AdjacentEpisode) {
    waiting.removeValue(forKey: request)?.forEach { $0.resume(returning: result) }
  }

  /// 测试结束时放行还挂着的查询。
  func answerRemaining() {
    let remaining = waiting
    waiting = [:]
    remaining.values.joined().forEach { $0.resume(returning: .none) }
  }
}

/// 代替 `MediaSession`：测试直接改当前条目来模拟换集。
@MainActor
@Observable
private final class QueueHostStub: EpisodeQueueHost {
  nonisolated deinit {}

  var currentItem: BaseItemDto?
  @ObservationIgnored let source = QueueSourceStub()

  var playbackBitrate: PlaybackBitrate { VideoPlayerDefaults.appMaximumBitrate }
  var episodeSource: any EpisodeQueueSource { source }

  func playNewItem(intent: PlaybackIntent) {}
}

@MainActor
final class EpisodeQueueTimingTests: XCTestCase {
  private func episode(_ id: String) -> BaseItemDto {
    var item = BaseItemDto(id: id)
    item.type = .episode
    item.seriesID = "100"
    item.seasonID = UserSession.queueSeasonID(1)
    return item
  }

  /// 最多等 2 秒。
  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "等待超时")
  }

  /// 让已经放行的查询把结果处理完。
  private func settle() async throws {
    try await Task.sleep(for: .milliseconds(50))
  }

  func testNextIsShownWhilePreviousIsStillLoading() async throws {
    let host = QueueHostStub()
    defer { host.source.answerRemaining() }
    host.currentItem = episode("e2")
    let queue = MoviePilotEpisodeQueue()
    let token = queue.follow(host)
    try await waitUntil { host.source.isWaiting(.next("e2")) && host.source.isWaiting(.previous("e2")) }

    host.source.answer(.next("e2"), with: .episode(episode("e3"), skippedMissing: false))
    try await waitUntil { queue.nextItem != nil }
    XCTAssertEqual(queue.nextItem?.item.id, "e3")
    XCTAssertNil(queue.previousItem, "上一集还在查，不耽误下一集")

    host.source.answer(.previous("e2"), with: .episode(episode("e1"), skippedMissing: false))
    try await waitUntil { queue.previousItem != nil }
    XCTAssertEqual(queue.previousItem?.item.id, "e1")
    XCTAssertEqual(queue.nextItem?.item.id, "e3")
    token.cancel()
  }

  func testManualSwitchDropsLateResultsForTheOldEpisode() async throws {
    let host = QueueHostStub()
    defer { host.source.answerRemaining() }
    host.currentItem = episode("e2")
    let queue = MoviePilotEpisodeQueue()
    let token = queue.follow(host)
    try await waitUntil { host.source.isWaiting(.next("e2")) && host.source.isWaiting(.previous("e2")) }

    host.currentItem = episode("e5")
    try await waitUntil { host.source.isWaiting(.next("e5")) && host.source.isWaiting(.previous("e5")) }
    host.source.answer(.next("e5"), with: .episode(episode("e6"), skippedMissing: false))
    host.source.answer(.previous("e5"), with: .episode(episode("e4"), skippedMissing: false))
    try await waitUntil { queue.nextItem != nil && queue.previousItem != nil }

    // 第 2 集的查询这时才回来。
    host.source.answer(.next("e2"), with: .episode(episode("e3"), skippedMissing: true))
    host.source.answer(.previous("e2"), with: .episode(episode("e1"), skippedMissing: false))
    try await settle()
    XCTAssertEqual(queue.nextItem?.item.id, "e6")
    XCTAssertEqual(queue.previousItem?.item.id, "e4")
    XCTAssertFalse(queue.nextNeedsRecheck)
    token.cancel()
  }

  func testLookUpNextAtTheEndFindsAnEpisodeThatJustArrived() async throws {
    let host = QueueHostStub()
    defer { host.source.answerRemaining() }
    host.currentItem = episode("e2")
    let queue = MoviePilotEpisodeQueue()
    let token = queue.follow(host)
    try await waitUntil { host.source.isWaiting(.next("e2")) }
    host.source.answer(.next("e2"), with: .unavailable(EpisodeNavigator.nextMissingMessage))
    try await settle()
    XCTAssertNil(queue.nextItem)
    XCTAssertTrue(queue.canLookUpNext)

    let lookup = Task { await queue.lookUpNext() }
    try await waitUntil { host.source.isWaiting(.next("e2", refresh: true)) }
    host.source.answer(.next("e2", refresh: true), with: .episode(episode("e3"), skippedMissing: false))
    guard case .play(let intent) = await lookup.value else { return XCTFail("播完时应接上刚入库的第 3 集") }
    XCTAssertEqual(intent.item.id, "e3")
    token.cancel()
  }

  func testLookUpNextResultDoesNotOverwriteTheQueueAfterManualSwitch() async throws {
    let host = QueueHostStub()
    defer { host.source.answerRemaining() }
    host.currentItem = episode("e2")
    let queue = MoviePilotEpisodeQueue()
    let token = queue.follow(host)
    try await waitUntil { host.source.isWaiting(.next("e2")) }
    host.source.answer(.next("e2"), with: .episode(episode("e4"), skippedMissing: true))
    try await waitUntil { queue.nextNeedsRecheck }

    // 播完后正在重新查下一集，用户在队列里手动选了第 5 集。
    let lookup = Task { await queue.lookUpNext() }
    try await waitUntil { host.source.isWaiting(.next("e2", refresh: true)) }
    host.currentItem = episode("e5")
    try await waitUntil { host.source.isWaiting(.next("e5")) }
    host.source.answer(.next("e5"), with: .episode(episode("e6"), skippedMissing: false))
    try await waitUntil { queue.nextItem?.item.id == "e6" }

    host.source.answer(.next("e2", refresh: true), with: .episode(episode("e3"), skippedMissing: false))
    guard case .play(let late) = await lookup.value else { return XCTFail("查询本身照常返回第 2 集的下一集") }
    XCTAssertEqual(late.item.id, "e3", "由 MediaSession 发现已换集后丢弃")
    XCTAssertEqual(queue.nextItem?.item.id, "e6", "旧查询不能改第 5 集的下一集")
    XCTAssertFalse(queue.nextNeedsRecheck)
    token.cancel()
  }

  func testExitClearsTheQueueAndLateResultsStayOut() async throws {
    let host = QueueHostStub()
    defer { host.source.answerRemaining() }
    host.currentItem = episode("e2")
    let queue = MoviePilotEpisodeQueue()
    let token = queue.follow(host)
    try await waitUntil { host.source.isWaiting(.next("e2")) && host.source.isWaiting(.previous("e2")) }

    token.cancel()
    host.source.answer(.next("e2"), with: .episode(episode("e3"), skippedMissing: false))
    host.source.answer(.previous("e2"), with: .episode(episode("e1"), skippedMissing: false))
    try await settle()
    XCTAssertNil(queue.nextItem)
    XCTAssertNil(queue.previousItem)
    XCTAssertTrue(queue.items.isEmpty)
    XCTAssertFalse(queue.canLookUpNext)
    guard case .unavailable(nil) = await queue.lookUpNext() else { return XCTFail("退出后不再查下一集") }
  }
}
