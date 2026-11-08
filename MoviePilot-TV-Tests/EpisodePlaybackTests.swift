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
    XCTAssertEqual(list[0].playerTitles(seriesName: "长风渡").primary, "第 1 季 第 10 集 · 重逢")
    XCTAssertEqual(list[0].playerTitles(seriesName: "长风渡").secondary, "长风渡")
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

  func testServerEpisodesWithoutTMDBIDsAreNotMatchedByNumbers() {
    // 服务器上第 1 季第 1 集就在那里，但没有 TMDB 单集 ID：不能按季集号认，可能是另一套编号的另一集。
    let noIDs = ServerMediaItem(id: "x", kind: .episode, seasonNumber: 1, episodeNumber: 1, externalIDs: ["tvdb": "9"])
    XCTAssertEqual(
      EpisodeAvailability.resolve(episode(1, number: 1), lookups: [index("a", [noIDs])]),
      .unidentifiable(.serverHasNoEpisodeIDs))
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
    let lookups = [
      index("a", [serverEpisode("a1", tmdb: 1)]),
      index("b", [serverEpisode("b2", tmdb: 2)]),
    ]
    XCTAssertEqual(
      EpisodeQueueStatus.resolve(episode(1), currentServer: "a", lookups: lookups), .playable(serverEpisode("a1", tmdb: 1)))
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(2), currentServer: "a", lookups: lookups), .elsewhere)
    XCTAssertEqual(EpisodeQueueStatus.resolve(episode(3), currentServer: "a", lookups: lookups), .absent)
    guard case .unknown = EpisodeQueueStatus.resolve(episode(nil), currentServer: "a", lookups: lookups) else {
      return XCTFail("缺少编号不能当作没有")
    }
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

  /// `statuses`：TMDB 单集 ID → 状态；没写的按确认没有。
  private func navigate(
    _ direction: EpisodeNavigator.Direction, from current: MoviePilotEpisode, currentItemID: String = "current",
    seasons: [Int], lists: [Int: [MoviePilotEpisode]], statuses: [Int: EpisodeQueueStatus],
    failingSeasons: Set<Int> = [], loads: SeasonLoads? = nil
  ) async throws -> EpisodeNavigator.Outcome {
    try await EpisodeNavigator.adjacent(
      direction, from: current, currentItemID: currentItemID, seasons: seasons,
      loadSeason: { season in
        loads?.seasons.append(season)
        if failingSeasons.contains(season) { throw LoadFailure() }
        return lists[season] ?? []
      },
      status: { episode in episode.tmdbEpisodeID.flatMap { statuses[$0] } ?? .absent })
  }

  func testNextSkipsMissingEpisodesAndTheSameFile() async throws {
    let season1 = list(season: 1, ids: [10, 11, 12, 13])
    let outcome = try await navigate(
      .next, from: season1[0], currentItemID: "file-1", seasons: [1],
      lists: [1: season1],
      statuses: [10: .playable(item("file-1")), 11: .playable(item("file-1")), 13: .playable(item("file-3"))])
    XCTAssertEqual(
      outcome, .play(EpisodeQueueEntry(episode: season1[3], item: item("file-3")), skippedMissing: true),
      "第 11 集和当前是同一个文件，第 12 集确认没有，都跳过；跳过了缺集，播完时要复查")
  }

  func testNextStopsWhenItCannotBeConfirmed() async throws {
    let season1 = list(season: 1, ids: [10, 11, 12])
    let elsewhere = try await navigate(
      .next, from: season1[0], seasons: [1], lists: [1: season1],
      statuses: [11: .elsewhere, 12: .playable(item("e12"))])
    guard case .stop(let reason) = elsewhere else { return XCTFail("在别的服务器上要停下，实际 \(elsewhere)") }
    XCTAssertTrue(reason.contains("另一台媒体服务器"), reason)

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
    XCTAssertEqual(
      outcome, .play(EpisodeQueueEntry(episode: season2[1], item: item("e21")), skippedMissing: true), "特别篇不参与跨季")

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
    XCTAssertEqual(
      outcome, .play(EpisodeQueueEntry(episode: season1[0], item: item("e10")), skippedMissing: true),
      "第 11 集确认没有，跳到第 10 集")
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
    XCTAssertEqual(outcome, .stop("没能读取第 2 季的集列表"))
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
    let opened = list(season: 1, ids: [10, 11])[0]
    let refreshed = list(season: 1, ids: [9, 10, 11])
    let outcome = try await navigate(
      .next, from: opened, seasons: [1], lists: [1: refreshed],
      statuses: [9: .playable(item("e9")), 11: .playable(item("e11"))])
    XCTAssertEqual(outcome, .play(EpisodeQueueEntry(episode: refreshed[2], item: item("e11")), skippedMissing: false))
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
