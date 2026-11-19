import XCTest

@testable import MoviePilot_TV

@MainActor
final class ExploreSourceVisibilityTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Self.clearDefaults()
    ExploreVisibilityURLProtocol.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(ExploreVisibilityURLProtocol.self))
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(ExploreVisibilityURLProtocol.self)
    Self.clearDefaults()
    super.tearDown()
  }

  nonisolated private static func clearDefaults() {
    for key in [
      ExploreViewModel.visibilityDefaultsKey, ExploreViewModel.orderDefaultsKey,
      ExploreViewModel.defaultConfigurationKey, ExploreViewModel.defaultPendingKey,
    ] {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  func testHidePersistsAcrossReopenAndPluginsDefaultOn() async throws {
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/plug","filter_params":{},"filter_ui":[]}]
      """)
    let service = makeService()
    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    await settings.refreshSources()
    XCTAssertTrue(settings.availableSources.contains { $0.id == "custom:plug" })

    var visibility = settings.sourceVisibility
    visibility["douban"] = false
    settings.saveSourceVisibility(visibility)

    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    XCTAssertFalse(browse.availableSources.contains { $0.id == "douban" })
    XCTAssertTrue(browse.availableSources.contains { $0.id == "custom:plug" })
    XCTAssertEqual(browse.availableSources.first?.id, "themoviedb")
  }

  func testSavedOrderDrivesBrowseSourcesAndKeepsGhostSlot() async throws {
    ExploreVisibilityURLProtocol.setSources("""
      [
        {"name":"插件A","mediaid_prefix":"a","api_path":"plugin/discover/a","filter_params":{},"filter_ui":[]},
        {"name":"插件B","mediaid_prefix":"b","api_path":"plugin/discover/b","filter_params":{},"filter_ui":[]}
      ]
      """)
    let service = makeService()
    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    await settings.refreshSources()
    settings.saveSourceOrder(["custom:b", "custom:a"] + DiscoverSource.allCases.map(\.id))

    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    XCTAssertEqual(browse.availableSources.prefix(2).map(\.id), ["custom:b", "custom:a"])

    // A 卸载期间重排：B 提到首内置之后，A 的槽位保留。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件B","mediaid_prefix":"b","api_path":"plugin/discover/b","filter_params":{},"filter_ui":[]}]
      """)
    await settings.refreshSources()
    var visible = settings.availableSources.map(\.id)
    visible.removeAll { $0 == "custom:b" }
    visible.insert("custom:b", at: 1)
    settings.saveSourceOrder(visible)
    XCTAssertEqual(ExploreViewModel.storedOrder()[1], "custom:a")

    // A 重装回到原槽位。
    ExploreVisibilityURLProtocol.setSources("""
      [
        {"name":"插件A","mediaid_prefix":"a","api_path":"plugin/discover/a","filter_params":{},"filter_ui":[]},
        {"name":"插件B","mediaid_prefix":"b","api_path":"plugin/discover/b","filter_params":{},"filter_ui":[]}
      ]
      """)
    await browse.refreshSources()
    XCTAssertEqual(browse.availableSources[1].id, "custom:a")
    XCTAssertEqual(browse.availableSources[2].id, "custom:b")
  }

  func testSaveOrderImmediatelyReordersContentList() async throws {
    let settings = ExploreViewModel(apiService: makeService(), loadsResults: false, sourcePolicy: .contentSettings)
    await settings.refreshSources()
    var moved = settings.availableSources.map(\.id)
    let last = moved.removeLast()
    moved.insert(last, at: 0)
    settings.saveSourceOrder(moved)
    XCTAssertEqual(settings.availableSources.map(\.id), moved, "保存顺序后内容页列表应立即重排")
  }

  func testHidingCurrentSourceFallsBackToFirstAvailable() async throws {
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    try await waitForItems(in: browse)
    XCTAssertEqual(browse.selectedSource.id, "themoviedb")

    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    settings.saveSourceVisibility(["themoviedb": false])
    browse.reloadLocalConfig()
    XCTAssertEqual(browse.selectedSource.id, "douban")
    try await waitForItems(in: browse)
  }

  func testReenablingSourceAfterHideAllRecreatesPaginator() async throws {
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    try await waitForItems(in: browse)

    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    let allHidden = Dictionary(uniqueKeysWithValues: DiscoverSource.allCases.map { ($0.id, false) })
    settings.saveSourceVisibility(allHidden)
    browse.reloadLocalConfig()
    XCTAssertTrue(browse.availableSources.isEmpty)
    XCTAssertNil(browse.paginator)

    // 重新启用同一来源：配置未变、去重键不变，必须显式重建分页器。
    settings.saveSourceVisibility(["themoviedb": true])
    browse.reloadLocalConfig()
    XCTAssertEqual(browse.selectedSource.id, "themoviedb")
    try await waitForItems(in: browse)
    XCTAssertEqual(browse.paginator?.items.first?.title, "探索测试电影")
  }

  func testOfflineColdStartReenableRecreatesPaginator() async throws {
    ExploreVisibilityURLProtocol.setSources("[]", statusCode: 503)
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    try await waitForItems(in: browse)

    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    settings.saveSourceVisibility(Dictionary(uniqueKeysWithValues: DiscoverSource.allCases.map { ($0.id, false) }))
    browse.reloadLocalConfig()
    XCTAssertNil(browse.paginator)

    // 离线冷启动（来源请求从未成功）后重开同一来源：本地首次激活标志应驱动重建。
    settings.saveSourceVisibility(["themoviedb": true])
    browse.reloadLocalConfig()
    try await waitForItems(in: browse)
    XCTAssertEqual(browse.paginator?.items.first?.title, "探索测试电影")
  }

  func testStaleDebouncedSourceDoesNotCreatePaginatorAfterHideAll() async throws {
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    try await waitForItems(in: browse)

    // 切换来源触发 100ms debounce，在触发前全部隐藏。
    browse.selectedSource = .douban
    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    settings.saveSourceVisibility(Dictionary(uniqueKeysWithValues: DiscoverSource.allCases.map { ($0.id, false) }))
    browse.reloadLocalConfig()
    XCTAssertNil(browse.paginator)

    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(browse.paginator, "debounce 陈旧触发不得为已隐藏来源重建分页器")
    XCTAssertFalse(
      ExploreVisibilityURLProtocol.requests.contains { $0.url?.path.contains("discover/douban") == true },
      "已隐藏来源不得发起媒体请求")
  }

  func testSourceRequestFailureRetainsSnapshotAndVisibility() async throws {
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/plug","filter_params":{},"filter_ui":[]}]
      """)
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    XCTAssertTrue(browse.availableSources.contains { $0.id == "custom:plug" })

    ExploreVisibilityURLProtocol.setSources("[]", statusCode: 503)
    await browse.refreshSources()
    XCTAssertTrue(browse.availableSources.contains { $0.id == "custom:plug" })
    XCTAssertEqual(browse.selectedSource.id, "themoviedb")
  }

  func testSubscriptionShareRequiresSubscribePermission() async throws {
    let withoutSubscribe = ExploreViewModel(apiService: makeService())
    await withoutSubscribe.refreshSources()
    XCTAssertFalse(withoutSubscribe.availableSources.contains { $0.id == "subscriptionShare" })

    let withSubscribe = ExploreViewModel(apiService: makeService(subscribe: true))
    await withSubscribe.refreshSources()
    XCTAssertTrue(withSubscribe.availableSources.contains { $0.id == "subscriptionShare" })
  }

  func testSourcePoliciesScopeVisibilityAndOrder() async throws {
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/plug","filter_params":{},"filter_ui":[]}]
      """)
    let service = makeService(subscribe: true)
    let settings = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    await settings.refreshSources()
    settings.saveSourceVisibility(["douban": false])
    let rest = DiscoverSource.allCases.filter { $0.id != "anilist" && $0.id != "themoviedb" }.map(\.id)
    settings.saveSourceOrder(["anilist", "themoviedb"] + rest + ["custom:plug"])

    // 主屏配置：不应用探索显隐与排序。
    let topShelf = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .topShelf)
    await topShelf.refreshSources()
    XCTAssertEqual(topShelf.availableSources.map(\.id), DiscoverSource.allCases.map(\.id) + ["custom:plug"])

    // 内容与顺序：全部来源（含隐藏）按用户排序。
    let content = ExploreViewModel(apiService: service, loadsResults: false, sourcePolicy: .contentSettings)
    await content.refreshSources()
    XCTAssertEqual(content.availableSources.prefix(2).map(\.id), ["anilist", "themoviedb"])
    XCTAssertTrue(content.availableSources.contains { $0.id == "douban" })

    // 默认配置：已启用来源按序，当前配置的隐藏来源保留在列表中。
    let draft = ExploreViewModel(
      apiService: service, configuration: ExploreConfiguration(source: .douban),
      loadsResults: false, sourcePolicy: .defaultSettings
    )
    await draft.refreshSources()
    XCTAssertEqual(draft.availableSources.first?.id, "douban")
    XCTAssertEqual(draft.availableSources.dropFirst().prefix(2).map(\.id), ["anilist", "themoviedb"])
    XCTAssertFalse(draft.availableSources.dropFirst().contains { $0.id == "douban" })
  }

  private func makeService(subscribe: Bool = false) -> APIService {
    let service = APIService.isolatedTestingInstance()
    var permissions = ["discovery": true]
    if subscribe { permissions["subscribe"] = true }
    let user = Token(
      access_token: "explore-visibility-test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: permissions, user_id: 503, user_name: "explore-visibility-test", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://explore-visibility.local", token: user.access_token, currentUser: user
    )
    return service
  }

  private func waitForItems(in viewModel: ExploreViewModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while viewModel.paginator?.items.isEmpty != false, Date() < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(viewModel.paginator?.items.isEmpty ?? true)
  }
}

final class ExploreVisibilityURLProtocol: URLProtocol {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var sources = "[]"
  nonisolated(unsafe) private static var sourceStatusCode = 200
  nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

  static var requests: [URLRequest] { lock.withLock { capturedRequests } }

  static func reset() {
    lock.withLock {
      sources = "[]"
      sourceStatusCode = 200
      capturedRequests = []
    }
  }

  static func setSources(_ json: String, statusCode: Int = 200) {
    lock.withLock {
      sources = json
      sourceStatusCode = statusCode
    }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "explore-visibility.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let (status, body) = Self.lock.withLock { () -> (Int, String) in
      Self.capturedRequests.append(request)
      if url.path == "/api/v1/discover/source" {
        return (Self.sourceStatusCode, Self.sources)
      }
      return (200, #"[{"tmdb_id":701,"title":"探索测试电影","type":"电影"}]"#)
    }
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}