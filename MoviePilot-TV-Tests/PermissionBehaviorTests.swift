import XCTest

@testable import MoviePilot_TV

@MainActor
final class PermissionVisibleEntryTests: XCTestCase {
  func testVisibleTabsExposeEntryForEachGrantedPermission() {
    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: permissionBehaviorToken(granted: [.discovery])),
      [.home, .recommend, .explore, .system]
    )
    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: permissionBehaviorToken(granted: [.search])),
      [.home, .search, .system]
    )
    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: permissionBehaviorToken(granted: [.subscribe])),
      [.home, .system]
    )
    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: permissionBehaviorToken(granted: [.manage])),
      [.home, .status, .system]
    )
  }

  func testMediaContextMenuSubscribeAndSearchEntriesArePermissionGuardedInSource() throws {
    let source = try permissionBehaviorSource("MoviePilot-TV/Views/Components/MediaContextMenu.swift")

    XCTAssertTrue(
      source.contains("if canSubscribeMedia, let share = item.subscribeShare"),
      "长按菜单“复用订阅”必须在 subscribe 权限门之后。"
    )
    XCTAssertTrue(
      source.contains("if canSubscribeMedia {\n        Button"),
      "长按菜单“订阅/分季订阅”必须在 subscribe 权限门之后。"
    )
    XCTAssertTrue(
      source.contains("if canSearchResources {\n        Button"),
      "长按菜单“搜索资源”必须在 search 权限门之后。"
    )
  }

  func testHomeRecentMediaSearchEntryRequiresSearchPermissionInSource() throws {
    let source = try permissionBehaviorSource("MoviePilot-TV/Views/Pages/HomeView.swift")
    let contextMenuRange = try XCTUnwrap(source.range(of: ".contextMenu {"))
    let searchResourceRange = try XCTUnwrap(source.range(of: "Label(\"搜索资源\"", range: contextMenuRange.upperBound..<source.endIndex))
    let guardedSearchRange = source.range(
      of: "canAccess(.search)",
      range: contextMenuRange.upperBound..<searchResourceRange.lowerBound
    )

    XCTAssertNotNil(guardedSearchRange, "首页最近添加长按菜单显示“搜索资源”前应检查 search 权限。")
  }

  func testMediaDetailHeaderSubscribeAndSearchEntriesArePermissionGuardedInSource() throws {
    let source = try permissionBehaviorSource("MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(
      source.contains("if canSubscribeMedia {"),
      "详情页 Header 的订阅/分季订阅按钮必须在 subscribe 权限门之后。"
    )
    XCTAssertTrue(
      source.contains("if canSearchResources {"),
      "详情页 Header 的搜索资源按钮必须在 search 权限门之后。"
    )
    XCTAssertTrue(
      source.contains("if canSearchResources && shouldShowSiteFilter"),
      "详情页站点筛选按钮必须跟随 search 权限。"
    )
  }

  func testTvSeasonSubscriptionEntryDoesNotRequireTMDBInSource() throws {
    let detailSource = try permissionBehaviorSource("MoviePilot-TV/Views/Pages/MediaDetailView.swift")
    let preloaderSource = try permissionBehaviorSource("MoviePilot-TV/ViewModels/MediaPreloader.swift")
    let viewModelSource = try permissionBehaviorSource("MoviePilot-TV/ViewModels/MediaDetailViewModel.swift")

    XCTAssertFalse(
      detailSource.contains(#"type == "电视剧" && viewModel.detail.tmdb_id != nil"#),
      "电视剧分季订阅入口不应只对 TMDB 详情开放。"
    )
    XCTAssertFalse(
      detailSource.contains(#"detail.type == "电视剧" && detail.tmdb_id != nil"#),
      "详情页 Header 的分季订阅动作不应只对 TMDB 详情开放。"
    )
    XCTAssertFalse(
      preloaderSource.contains(#"guard detail.tmdb_id != nil else { return }"#),
      "预加载分季订阅数据不应只对 TMDB 详情开放。"
    )
    XCTAssertFalse(
      viewModelSource.contains(#"fullDetail.type == "电视剧" && fullDetail.tmdb_id != nil"#),
      "详情页首行就绪判断不应只对 TMDB 详情开放。"
    )
  }

  func testTorrentDownloadEntryRequiresSearchPermissionInSource() throws {
    let source = try permissionBehaviorSource("MoviePilot-TV/Views/Components/TorrentCard.swift")

    XCTAssertTrue(
      source.contains("apiService.canAccess(.search)"),
      "种子下载入口必须基于 search 权限计算可用状态。"
    )
    XCTAssertTrue(
      source.contains(".contextMenu {\n        if canAddDownload {"),
      "种子卡片长按菜单“下载”必须在 search 权限门之后。"
    )
    XCTAssertTrue(
      source.contains(".onTapGesture {\n        guard canAddDownload else { return }"),
      "种子卡片点击打开下载弹窗前必须再次检查 search 权限。"
    )
  }
}

@MainActor
final class PermissionGrantedBehaviorTests: XCTestCase {
  func testSubscriptionHandlerOpensMovieSheetAndTVSeasonFlowWithSubscribePermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.subscribe])

      let handler = SubscriptionHandler()

      handler.handleSubscribe(MediaInfo(tmdb_id: 901, title: "可订阅电影", type: "电影"))
      try await permissionBehaviorWaitUntil("movie subscribe sheet opens") {
        handler.sheetSubscribe != nil
      }

      XCTAssertEqual(handler.sheetSubscribe?.name, "可订阅电影")
      XCTAssertEqual(handler.sheetSubscribe?.type, "电影")
      let subscriptionLookupCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/media/tmdb:901"
      )
      XCTAssertEqual(subscriptionLookupCount, 1)

      handler.handleSubscribe(MediaInfo(tmdb_id: 902, title: "可分季订阅剧集", type: "电视剧"))

      XCTAssertEqual(handler.tvSubscribeRequest?.mediaInfo.title, "可分季订阅剧集")
    }
  }

  func testSubscriptionHandlerForksAndFetchesEditorWithSubscribePermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.subscribe])

      let handler = SubscriptionHandler()
      let forkedId = await handler.fork(share: try PermissionBehaviorFixtures.subscribeShare())
      await handler.fetchSubscriptionAndShowEditor(subId: 7001)

      XCTAssertEqual(forkedId, 7001)
      XCTAssertEqual(handler.sheetSubscribe?.id, 7001)
      XCTAssertEqual(handler.sheetSubscribe?.name, "订阅")
      let forkRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "POST",
        path: "/api/v1/subscribe/fork"
      )
      let fetchRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/7001"
      )
      XCTAssertEqual(forkRequestCount, 1)
      XCTAssertEqual(fetchRequestCount, 1)
    }
  }

  func testSubscribeSeasonActionPreparesSubscriptionWithSubscribePermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.subscribe])

      let viewModel = SubscribeSeasonViewModel(
        mediaInfo: MediaInfo(tmdb_id: 7003, title: "可分季订阅", type: "电视剧")
      )

      await SubscribeSeasonContentView.performSeasonPrimaryAction(
        season: try permissionBehaviorSeason(number: 1),
        isSubscribed: false,
        refreshSubscribedState: { _ in false },
        showUnsubscribeConfirm: { _ in XCTFail("Unsubscribed an unsubscribed season") },
        prepareSubscription: { viewModel.prepareSubscription(seasonNumber: $0) }
      )

      XCTAssertEqual(viewModel.sheetSubscribe?.name, "可分季订阅")
      XCTAssertEqual(viewModel.sheetSubscribe?.type, "电视剧")
      XCTAssertEqual(viewModel.sheetSubscribe?.season, 1)
    }
  }

  func testRecommendAndExploreLoadWithDiscoveryPermission() async throws {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.discovery])

      let recommend = RecommendViewModel()
      let explore = ExploreViewModel()

      try await permissionBehaviorWaitUntil("recommend request starts") {
        await PermissionBehaviorURLProtocol.stub.requestCount(
          method: "GET",
          pathPrefix: "/api/v1/recommend/"
        ) > 0
      }
      try await permissionBehaviorWaitUntil("discover request starts") {
        await PermissionBehaviorURLProtocol.stub.requestCount(
          method: "GET",
          pathPrefix: "/api/v1/discover/"
        ) > 0
      }

      XCTAssertNotNil(recommend.paginator)
      XCTAssertNotNil(explore.paginator)
      XCTAssertEqual(
        explore.availableSources,
        DiscoverSource.allCases.filter { $0 != .subscriptionShare }
      )
    }
  }

  func testExploreSubscriptionShareLoadsWithDiscoveryAndSubscribePermissions()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.discovery, .subscribe])

      let explore = ExploreViewModel()
      XCTAssertTrue(explore.availableSources.contains(.subscriptionShare))

      explore.selectedSource = .subscriptionShare

      try await permissionBehaviorWaitUntil("subscription share request starts") {
        await PermissionBehaviorURLProtocol.stub.requestCount(
          method: "GET",
          path: "/api/v1/subscribe/shares"
        ) > 0
      }

      XCTAssertNotNil(explore.paginator)
    }
  }

  func testResourceSearchPublishesResultsWithSearchPermission() async throws {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.search])

      let resourceViewModel = ResourceResultViewModel(keyword: "有搜索权限", sites: "1")
      await resourceViewModel.search()

      try await permissionBehaviorWaitUntil("resource search result publishes") {
        !resourceViewModel.isLoading && resourceViewModel.results.count == 1
      }

      XCTAssertEqual(resourceViewModel.results.first?.torrent_info?.title, "有搜索权限结果")
      let streamRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/search/title/stream"
      )
      XCTAssertEqual(streamRequestCount, 1)
    }
  }
}

@MainActor
final class PermissionDirectGuardTests: XCTestCase {
  func testSubscriptionHandlerDoesNotOpenSheetNavigateOrRequestWithoutSubscribePermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.search])

      let handler = SubscriptionHandler()

      handler.handleSubscribe(MediaInfo(tmdb_id: 901, title: "电影", type: "电影"))
      handler.handleSubscribe(MediaInfo(tmdb_id: 902, title: "剧集", type: "电视剧"))
      try await Task.sleep(nanoseconds: 100_000_000)

      XCTAssertNil(handler.sheetSubscribe)
      XCTAssertNil(handler.tvSubscribeRequest)
      let subscriptionLookupCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        pathPrefix: "/api/v1/subscribe/media/"
      )
      XCTAssertEqual(subscriptionLookupCount, 0)
    }
  }

  func testSubscriptionHandlerDoesNotForkOrFetchEditorWithoutSubscribePermission() async throws {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.search])

      let handler = SubscriptionHandler()
      let forkedId = await handler.fork(share: try PermissionBehaviorFixtures.subscribeShare())
      await handler.fetchSubscriptionAndShowEditor(subId: 7001)

      XCTAssertNil(forkedId)
      XCTAssertNil(handler.sheetSubscribe)
      let forkRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "POST",
        path: "/api/v1/subscribe/fork"
      )
      let fetchRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/7001"
      )
      XCTAssertEqual(forkRequestCount, 0)
      XCTAssertEqual(fetchRequestCount, 0)
    }
  }

  func testSubscribeSeasonActionDoesNotOpenSheetWithoutSubscribePermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.search])

      let viewModel = SubscribeSeasonViewModel(
        mediaInfo: MediaInfo(tmdb_id: 7003, title: "无权限分季", type: "电视剧")
      )
      viewModel.seasonSubscriptions = [
        1: SeasonSubscriptionSummary(id: 7101, season: 1, episodeGroup: nil)
      ]
      viewModel.subscribedSeasons = [1]

      await SubscribeSeasonContentView.performSeasonPrimaryAction(
        season: try permissionBehaviorSeason(number: 1),
        isSubscribed: false,
        refreshSubscribedState: { seasonNumber in
          let didRefresh = await viewModel.checkSubscriptionStatus(forceRefresh: true)
          guard didRefresh else { return nil }
          return viewModel.isSeasonSubscribed(seasonNumber)
        },
        showUnsubscribeConfirm: { _ in XCTFail("Should not show unsubscribe confirmation") },
        prepareSubscription: { viewModel.prepareSubscription(seasonNumber: $0) }
      )

      XCTAssertNil(viewModel.sheetSubscribe)
      XCTAssertTrue(viewModel.subscribedSeasons.isEmpty)
      let subscriptionListCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/"
      )
      XCTAssertEqual(subscriptionListCount, 0)
    }
  }

  func testRecommendAndExploreDoNotLoadWhenDirectlyCreatedWithoutDiscoveryPermission()
    async throws
  {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.subscribe])

      let recommend = RecommendViewModel()
      let explore = ExploreViewModel()
      try await Task.sleep(nanoseconds: 300_000_000)

      XCTAssertNil(recommend.paginator)
      XCTAssertNil(explore.paginator)
      let recommendRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        pathPrefix: "/api/v1/recommend/"
      )
      let discoverRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        pathPrefix: "/api/v1/discover/"
      )
      let popularRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/popular"
      )
      let shareRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/shares"
      )
      XCTAssertEqual(recommendRequestCount, 0)
      XCTAssertEqual(discoverRequestCount, 0)
      XCTAssertEqual(popularRequestCount, 0)
      XCTAssertEqual(shareRequestCount, 0)
    }
  }

  func testExploreHidesSubscriptionShareSourceWithoutSubscribePermission() async throws {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.discovery])

      let explore = ExploreViewModel()
      XCTAssertFalse(explore.availableSources.contains(.subscriptionShare))

      explore.selectedSource = .subscriptionShare
      try await Task.sleep(nanoseconds: 300_000_000)

      XCTAssertNil(explore.paginator)
      let shareRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        path: "/api/v1/subscribe/shares"
      )
      XCTAssertEqual(shareRequestCount, 0)
    }
  }

  func testResourceSearchDoesNotStartWithoutSearchPermission() async throws {
    try await withPermissionBehaviorBackend { service in
      configurePermissionBehaviorUser(service, granted: [.discovery])

      let resourceViewModel = ResourceResultViewModel(keyword: "无搜索权限")
      await resourceViewModel.search()

      XCTAssertFalse(resourceViewModel.isLoading)
      XCTAssertTrue(resourceViewModel.results.isEmpty)
      let searchRequestCount = await PermissionBehaviorURLProtocol.stub.requestCount(
        method: "GET",
        pathPrefix: "/api/v1/search/"
      )
      XCTAssertEqual(searchRequestCount, 0)
    }
  }
}

@MainActor
private func withPermissionBehaviorBackend(
  operation: (APIService) async throws -> Void
) async throws {
  XCTAssertTrue(URLProtocol.registerClass(PermissionBehaviorURLProtocol.self))
  defer { URLProtocol.unregisterClass(PermissionBehaviorURLProtocol.self) }

  let service = APIService.shared
  let snapshot = PermissionBehaviorServiceSnapshot.capture(service: service)
  defer { snapshot.restore(to: service) }

  await PermissionBehaviorURLProtocol.stub.reset()
  service.baseURL = "http://permission-behavior-tests.local"
  try await operation(service)
}

private func permissionBehaviorSource(_ relativePath: String) throws -> String {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = repoRoot.appendingPathComponent(relativePath)
  return try String(contentsOf: url)
}

@MainActor
private func permissionBehaviorSeason(number: Int) throws -> TmdbSeason {
  let data = """
    {
      "episode_count": 12,
      "name": "Season \(number)",
      "overview": "",
      "season_number": \(number),
      "vote_average": 0
    }
    """.data(using: .utf8)!
  return try JSONDecoder().decode(TmdbSeason.self, from: data)
}

@MainActor
private func configurePermissionBehaviorUser(
  _ service: APIService,
  granted permissions: Set<UserPermissionKey>
) {
  service.token = "permission-behavior-token"
  service.currentUser = Token(
    access_token: "permission-behavior-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: permissionBehaviorPermissions(permissions),
    user_name: "permission-behavior",
    avatar: nil
  )
}

@MainActor
private func permissionBehaviorToken(granted permissions: Set<UserPermissionKey>) -> Token {
  Token(
    access_token: "permission-behavior-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: permissionBehaviorPermissions(permissions),
    user_name: "permission-behavior",
    avatar: nil
  )
}

private func permissionBehaviorPermissions(_ granted: Set<UserPermissionKey>) -> [String: Bool] {
  Dictionary(
    uniqueKeysWithValues: UserPermissionKey.allCases.map {
      ($0.rawValue, granted.contains($0))
    }
  )
}

@MainActor
private func permissionBehaviorWaitUntil(
  _ description: String,
  timeout: TimeInterval = 2,
  condition: @escaping () async -> Bool
) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() {
      return
    }
    try await Task.sleep(nanoseconds: 20_000_000)
  }
  XCTFail("Timed out waiting for \(description)")
}

@MainActor
private struct PermissionBehaviorServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let accessTokenDefaults: String?
  let currentUserDefaults: String?

  static func capture(service: APIService) -> PermissionBehaviorServiceSnapshot {
    PermissionBehaviorServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      accessTokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    restoreDefaults(value: serverURLDefaults, forKey: "serverURL")
    restoreDefaults(value: accessTokenDefaults, forKey: "accessToken")
    restoreDefaults(value: currentUserDefaults, forKey: "currentUser")
  }

  private func restoreDefaults(value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

private enum PermissionBehaviorFixtures {
  @MainActor
  static func subscribeShare() throws -> SubscribeShare {
    let data = Data(
      """
      {
        "id": 88,
        "subscribe_id": 7008,
        "share_title": "复用分享",
        "share_user": "tester",
        "name": "复用分享",
        "year": "2026",
        "type": "电影",
        "tmdbid": 7008
      }
      """.utf8
    )
    return try JSONDecoder().decode(SubscribeShare.self, from: data)
  }

  static func subscriptionSharesData() -> Data {
    Data(
      """
      [
        {
          "id": 88,
          "subscribe_id": 7008,
          "share_title": "可见订阅分享",
          "share_user": "tester",
          "name": "可见订阅分享",
          "year": "2026",
          "type": "电视剧",
          "tmdbid": 7008,
          "count": 3
        }
      ]
      """.utf8
    )
  }

  static func resourceSearchStreamData(title: String) -> Data {
    let event =
      "data: {\"type\":\"append\",\"text\":\"Searching\",\"value\":50,\"items\":["
      + resourceContextJSON(title: title)
      + "]}\n\n"
    return Data(event.utf8)
  }

  static func resourceSearchData(title: String) -> Data {
    Data("[\(resourceContextJSON(title: title))]".utf8)
  }

  private static func resourceContextJSON(title: String) -> String {
    #"{"torrent_info":{"site":1,"site_name":"Test Site","site_order":1,"title":"\#(title)","description":"","enclosure":"https://example.test/search-result.torrent","page_url":"https://example.test/search-result","size":1024,"seeders":10,"peers":1,"pubdate":"2026-06-16 10:00:00","uploadvolumefactor":1.0,"downloadvolumefactor":1.0,"pri_order":1,"labels":[],"volume_factor":"1x"}}"#
  }
}

private actor PermissionBehaviorURLProtocolStub {
  private var requestCounts: [String: Int] = [:]

  func reset() {
    requestCounts.removeAll()
  }

  func totalRequestCount() -> Int {
    requestCounts.values.reduce(0, +)
  }

  func requestCount(method: String, path: String) -> Int {
    requestCounts["\(method) \(path)", default: 0]
  }

  func requestCount(method: String, pathPrefix: String) -> Int {
    requestCounts.reduce(into: 0) { count, entry in
      let prefix = "\(method) \(pathPrefix)"
      if entry.key.hasPrefix(prefix) {
        count += entry.value
      }
    }
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""
    requestCounts["\(method) \(path)", default: 0] += 1

    let data: Data
    switch (method, path) {
    case ("GET", "/api/v1/subscribe/7001"):
      data = #"{"id":7001,"name":"订阅","type":"电影","tmdbid":7001}"#.data(using: .utf8)!
    case ("GET", "/api/v1/subscribe/"):
      data = #"[]"#.data(using: .utf8)!
    case ("GET", "/api/v1/subscribe/shares"):
      data = PermissionBehaviorFixtures.subscriptionSharesData()
    case ("POST", "/api/v1/subscribe/fork"):
      data = #"{"success":true,"data":{"id":7001}}"#.data(using: .utf8)!
    case ("GET", "/api/v1/search/title/stream"):
      data = PermissionBehaviorFixtures.resourceSearchStreamData(title: "有搜索权限结果")
    case ("GET", "/api/v1/search/title"):
      data = PermissionBehaviorFixtures.resourceSearchData(title: "有搜索权限结果")
    case ("GET", "/api/v1/system/setting/CustomFilterRules"):
      data = #"{"data":{"value":[{"id":"allow-all","name":"Allow All"}]}}"#.data(using: .utf8)!
    case ("GET", "/api/v1/system/global"), ("GET", "/api/v1/system/global/user"):
      data = #"{"TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#.data(using: .utf8)!
    case let (_, path) where path.hasPrefix("/api/v1/subscribe"):
      data = #"{"success":true}"#.data(using: .utf8)!
    case let (_, path) where path.hasPrefix("/api/v1/download"):
      data = #"{"success":true}"#.data(using: .utf8)!
    case let (_, path) where path.hasPrefix("/api/v1/recommend"):
      data = #"[]"#.data(using: .utf8)!
    case let (_, path) where path.hasPrefix("/api/v1/discover"):
      data = #"[]"#.data(using: .utf8)!
    default:
      data = #"[]"#.data(using: .utf8)!
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class PermissionBehaviorURLProtocol: URLProtocol {
  static let stub = PermissionBehaviorURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "permission-behavior-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = PermissionBehaviorURLProtocolTaskContext(
      request: request,
      clientBox: PermissionBehaviorURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = Self.makeLoadingTask(for: context)
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }

  private static func makeLoadingTask(for context: PermissionBehaviorURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let (response, data) = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: response, data: data)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }
}

private final class PermissionBehaviorURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: PermissionBehaviorURLProtocolClientBox

  init(request: URLRequest, clientBox: PermissionBehaviorURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class PermissionBehaviorURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(response: HTTPURLResponse, data: Data) {
    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
