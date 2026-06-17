import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSeasonContentViewTests: XCTestCase {
  func testHomeSubscriptionRefreshCanBypassCachedSnapshot() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscriptionSnapshotURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 101, name: "航海王", type: "电视剧", season: 1, tmdbid: 12345)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    service.baseURL = "http://subscription-snapshot-tests.local"

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [101])

    await viewModel.refreshSubscriptions()
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [101])

    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions, [])
  }

  func testHomeSubscriptionUpdateNotificationBypassesCachedSnapshot() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscriptionSnapshotURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 102, name: "航海王", type: "电视剧", season: 1, tmdbid: 12345)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    service.baseURL = "http://subscription-snapshot-tests.local"

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [102])

    NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    try await waitUntil {
      viewModel.tvSubscriptions.isEmpty
    }
  }

  func testPreloadedSeasonDataReusesCachedSubscriptionSnapshot() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscriptionSnapshotURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let preloader = MediaPreloader.shared
    preloader.clearAll()
    defer { preloader.clearAll() }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([
      Subscribe(id: 201, name: "预加载剧集", type: "电视剧", season: 1, tmdbid: 810001)
    ])
    service.baseURL = "http://subscription-snapshot-tests.local"

    let firstTask = preloader.preload(
      for: MediaInfo(tmdb_id: 810001, title: "预加载剧集 A", type: "电视剧"))
    try await waitUntil {
      firstTask.isSeasonDataLoaded
    }
    let firstSubscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(firstSubscribeRequestCount, 1)

    let secondTask = preloader.preload(
      for: MediaInfo(tmdb_id: 810002, title: "预加载剧集 B", type: "电视剧"))
    try await waitUntil {
      secondTask.isSeasonDataLoaded
    }

    let secondSubscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(secondSubscribeRequestCount, 1)
  }

  func testSubscriptionSnapshotCacheCanExpireWithoutRenewingOnRead() async {
    let clock = APICacheTestClock(start: Date(timeIntervalSince1970: 0))
    let cache = APICache<String, Int>(
      defaultTTL: 10,
      size: 1,
      renewsTTLOnAccess: false,
      now: clock.now
    )

    await cache.set("subscriptions", value: 1)

    clock.advance(by: 9)
    let cachedValueBeforeOriginalExpiry = await cache.get("subscriptions")
    XCTAssertEqual(cachedValueBeforeOriginalExpiry, 1)

    clock.advance(by: 2)
    let cachedValueAfterOriginalExpiry = await cache.get("subscriptions")
    XCTAssertNil(cachedValueAfterOriginalExpiry)
  }

  func testAPICacheRenewsTTLOnReadByDefault() async {
    let clock = APICacheTestClock(start: Date(timeIntervalSince1970: 0))
    let cache = APICache<String, Int>(
      defaultTTL: 10,
      size: 1,
      now: clock.now
    )

    await cache.set("media-seasons", value: 1)

    clock.advance(by: 9)
    let cachedValueBeforeOriginalExpiry = await cache.get("media-seasons")
    XCTAssertEqual(cachedValueBeforeOriginalExpiry, 1)

    clock.advance(by: 2)
    let cachedValueAfterOriginalExpiry = await cache.get("media-seasons")
    XCTAssertEqual(cachedValueAfterOriginalExpiry, 1)
  }

  func testSeasonSubscriptionSummaryIndexesMatchingMediaBySeason() {
    let media = MediaInfo(tmdb_id: 12345, type: "电视剧")
    let subscriptions = [
      Subscribe(id: 11, name: "Target", type: "电视剧", season: 1, tmdbid: 12345, episode_group: "group-a"),
      Subscribe(id: 12, name: "Other Season", type: "电视剧", season: 2, tmdbid: 12345),
      Subscribe(id: 13, name: "Other Media", type: "电视剧", season: 3, tmdbid: 54321, episode_group: "group-b"),
      Subscribe(id: 14, name: "Movie", type: "电影", season: 4, tmdbid: 12345),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 11)
    XCTAssertEqual(summaries[1]?.episodeGroup, "group-a")
    XCTAssertEqual(summaries[2]?.id, 12)
    XCTAssertNil(summaries[3])
    XCTAssertNil(summaries[4])
  }

  func testSeasonSubscriptionSummaryDisplaysRealEpisodeGroup() throws {
    let groups = [try makeEpisodeGroup(id: "group-a", name: "司法岛篇")]
    let defaultSummary = SeasonSubscriptionSummary(id: 1, season: 1, episodeGroup: nil)
    let namedSummary = SeasonSubscriptionSummary(id: 2, season: 2, episodeGroup: "group-a")
    let unknownSummary = SeasonSubscriptionSummary(id: 3, season: 3, episodeGroup: "group-x")

    XCTAssertEqual(defaultSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 默认剧集组")
    XCTAssertEqual(namedSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 司法岛篇")
    XCTAssertEqual(unknownSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 剧集组：group-x")
  }

  func testSeasonSubscriptionSummaryTreatsEpisodeGroupAsConfigurationNotIdentity() {
    let media = MediaInfo(tmdb_id: 12345, type: "电视剧", episode_group: "group-b")
    let subscriptions = [
      Subscribe(id: 21, name: "Target", type: "电视剧", season: 1, tmdbid: 12345, episode_group: "group-a")
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 21)
    XCTAssertEqual(summaries[1]?.episodeGroup, "group-a")
  }

  func testSeasonSubscriptionSummaryMatchesMediaIdFallbackFromBackendSnapshot() {
    let media = MediaInfo(mediaid_prefix: "tmdb", media_id: "12345", type: "电视剧")
    let subscriptions = [
      Subscribe(id: 31, name: "Target", type: "电视剧", season: 1, mediaid: "tmdb:12345"),
      Subscribe(id: 32, name: "Other", type: "电视剧", season: 1, mediaid: "douban:12345"),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 31)
  }

  func testSeasonSubscriptionSummaryIgnoresBlankAndZeroIdentifiers() {
    let media = MediaInfo(
      tmdb_id: 0,
      douban_id: "  ",
      bangumi_id: 0,
      mediaid_prefix: "tmdb",
      media_id: "0",
      type: "电视剧"
    )
    let subscriptions = [
      Subscribe(id: 41, name: "Zero TMDB", type: "电视剧", season: 1, tmdbid: 0),
      Subscribe(id: 42, name: "Blank Douban", type: "电视剧", season: 2, doubanid: ""),
      Subscribe(id: 43, name: "Zero Bangumi", type: "电视剧", season: 3, bangumiid: 0),
      Subscribe(id: 44, name: "Empty MediaID", type: "电视剧", season: 4, mediaid: "tmdb:0"),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertTrue(summaries.isEmpty)
  }

  func testSeasonSubscriptionSummaryTreatsBlankEpisodeGroupAsDefault() {
    let summary = SeasonSubscriptionSummary(id: 51, season: 1, episodeGroup: "  \n ")

    XCTAssertNil(summary.episodeGroup)
    XCTAssertEqual(summary.statusDisplayText(episodeGroups: []), "已订阅 · 默认剧集组")
  }

  func testUnsubscribeConfirmationMessageUsesCurrentSubscriptionGroup() throws {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.episodeGroups = [try makeEpisodeGroup(id: "group-a", name: "司法岛篇")]
    viewModel.seasonSubscriptions = [
      3: SeasonSubscriptionSummary(id: 61, season: 3, episodeGroup: "group-a")
    ]

    XCTAssertEqual(
      viewModel.unsubscribeConfirmationMessage(for: 3),
      "是否取消《航海王》第 3 季订阅？\n当前订阅使用：司法岛篇"
    )
  }

  func testHomeSubscriptionUnsubscribeConfirmationUsesSubscribeEpisodeGroup() {
    let subscribe = Subscribe(
      id: 81,
      name: "葬送的芙莉莲",
      type: "电视剧",
      season: 1,
      episode_group: "group-a"
    )

    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(for: subscribe),
      "是否取消《葬送的芙莉莲》第 1 季订阅？\n当前订阅使用：剧集组：group-a"
    )
  }

  func testHomeSubscriptionUnsubscribeConfirmationUsesDefaultEpisodeGroup() {
    let subscribe = Subscribe(
      id: 82,
      name: "迷宫饭",
      type: "电视剧",
      season: 1
    )

    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(for: subscribe),
      "是否取消《迷宫饭》第 1 季订阅？\n当前订阅使用：默认剧集组"
    )
  }

  func testUnsubscribeConfirmationMessageUsesSpecialsNameForSeasonZero() {
    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(
        title: "夏日重现",
        season: 0,
        episodeGroupText: "默认剧集组"
      ),
      "是否取消《夏日重现》特别篇订阅？\n当前订阅使用：默认剧集组"
    )
  }

  func testPrepareSubscriptionUsesSelectedPickerGroupForNewSubscriptionOnly() {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.selectedGroupId = "group-a"
    viewModel.seasonSubscriptions = [
      1: SeasonSubscriptionSummary(id: 71, season: 1, episodeGroup: "group-b")
    ]

    viewModel.prepareSubscription(seasonNumber: 2)

    XCTAssertEqual(viewModel.sheetSubscribe?.season, 2)
    XCTAssertEqual(viewModel.sheetSubscribe?.episode_group, "group-a")
    XCTAssertEqual(viewModel.subscriptionGroupText(for: 1), "剧集组：group-b")
  }

  func testSeasonPrimaryActionSubscribesSeasonWhenNavigationHandlerIsProvided() throws {
    let season = try makeSeason(number: 2)
    var tappedSeason: TmdbSeason?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      onSeasonTap: { tappedSeason = $0 },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertNil(tappedSeason)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertEqual(preparedSeason, 2)
  }

  func testSeasonPrimaryActionUnsubscribesSeasonWhenNavigationHandlerIsProvided() throws {
    let season = try makeSeason(number: 4)
    var tappedSeason: TmdbSeason?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: true,
      onSeasonTap: { tappedSeason = $0 },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertNil(tappedSeason)
    XCTAssertEqual(unsubscribedSeason, 4)
    XCTAssertNil(preparedSeason)
  }

  func testSeasonPrimaryActionKeepsSubscribeFallbackWithoutNavigationHandler() throws {
    let season = try makeSeason(number: 3)
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      onSeasonTap: nil,
      showUnsubscribeConfirm: { _ in XCTFail("Unsubscribed an unsubscribed season") },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(preparedSeason, 3)
  }

  private func makeSeason(number: Int) throws -> TmdbSeason {
    let data = """
      {
        "air_date": "2024-01-01",
        "episode_count": 8,
        "name": "Season \(number)",
        "overview": "",
        "poster_path": "/season\(number).jpg",
        "season_number": \(number),
        "vote_average": 8.0
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(TmdbSeason.self, from: data)
  }

  private func makeEpisodeGroup(id: String, name: String) throws -> EpisodeGroup {
    let data = """
      {
        "id": "\(id)",
        "name": "\(name)",
        "group_count": 1,
        "episode_count": 12
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(EpisodeGroup.self, from: data)
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Condition was not satisfied before timeout")
  }
}

private struct SubscriptionSnapshotServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SubscriptionSnapshotServiceSnapshot {
    SubscriptionSnapshotServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }
  }
}

private final class APICacheTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var currentDate: Date

  init(start: Date) {
    self.currentDate = start
  }

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return currentDate
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    currentDate = currentDate.addingTimeInterval(interval)
    lock.unlock()
  }
}

private struct SubscriptionSnapshotStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private actor SubscriptionSnapshotURLProtocolStub {
  private var queuedResponses: [Data] = []
  private var defaultSubscriptionsData: Data?
  private var requestCounts: [String: Int] = [:]

  func reset() {
    queuedResponses.removeAll()
    defaultSubscriptionsData = nil
    requestCounts.removeAll()
  }

  func enqueueSubscriptions(_ subscriptions: [Subscribe]) throws {
    let data = try JSONEncoder().encode(subscriptions)
    queuedResponses.append(data)
  }

  func setDefaultSubscriptions(_ subscriptions: [Subscribe]) throws {
    defaultSubscriptionsData = try JSONEncoder().encode(subscriptions)
  }

  func subscribeRequestCount() -> Int {
    requestCounts["/api/v1/subscribe", default: 0] + requestCounts["/api/v1/subscribe/", default: 0]
  }

  func response(for request: URLRequest) throws -> SubscriptionSnapshotStubResponse {
    let path = request.url?.path ?? ""
    requestCounts[path, default: 0] += 1

    if path == "/api/v1/subscribe" || path == "/api/v1/subscribe/" {
      if !queuedResponses.isEmpty {
        return SubscriptionSnapshotStubResponse(statusCode: 200, data: queuedResponses.removeFirst())
      }
      if let defaultSubscriptionsData {
        return SubscriptionSnapshotStubResponse(statusCode: 200, data: defaultSubscriptionsData)
      }
      throw URLError(.badServerResponse)
    }

    if path.hasPrefix("/api/v1/media/groups/") {
      return try jsonResponse("[]")
    }

    if path == "/api/v1/media/seasons" {
      return try jsonResponse(Self.seasonsJSON)
    }

    if path == "/api/v1/mediaserver/notexists" {
      return try jsonResponse("[]")
    }

    if path.hasPrefix("/api/v1/media/tmdb:") {
      let tmdbId = request.url?.lastPathComponent.split(separator: ":").last.flatMap { Int($0) }
      return try mediaDetailResponse(tmdbId: tmdbId)
    }

    throw URLError(.badServerResponse)
  }

  private func jsonResponse(_ json: String) throws -> SubscriptionSnapshotStubResponse {
    guard let data = json.data(using: .utf8) else {
      throw URLError(.badServerResponse)
    }
    return SubscriptionSnapshotStubResponse(statusCode: 200, data: data)
  }

  private func mediaDetailResponse(tmdbId: Int?) throws -> SubscriptionSnapshotStubResponse {
    try jsonResponse(
      """
      {
        "tmdb_id": \(tmdbId ?? 0),
        "title": "预加载剧集 \(tmdbId ?? 0)",
        "type": "电视剧"
      }
      """
    )
  }

  private static let seasonsJSON = """
    [
      {
        "air_date": "2024-01-01",
        "episode_count": 8,
        "name": "Season 1",
        "overview": "",
        "poster_path": null,
        "season_number": 1,
        "vote_average": 8.0
      }
    ]
    """
}

private final class SubscriptionSnapshotURLProtocol: URLProtocol {
  static let stub = SubscriptionSnapshotURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscription-snapshot-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscriptionSnapshotURLProtocolTaskContext(
      request: request,
      clientBox: SubscriptionSnapshotURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = SubscriptionSnapshotURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscriptionSnapshotURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await SubscriptionSnapshotURLProtocol.stub.response(
          for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class SubscriptionSnapshotURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscriptionSnapshotURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscriptionSnapshotURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscriptionSnapshotURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: SubscriptionSnapshotStubResponse) {
    guard let url = request.url else {
      fail(URLError(.badURL))
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      fail(URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: stubResponse.data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
