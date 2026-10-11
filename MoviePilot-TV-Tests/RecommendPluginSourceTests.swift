import XCTest

@testable import MoviePilot_TV

@MainActor
final class RecommendPluginSourceTests: XCTestCase {
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.localConfigKey)
    RecommendPluginURLProtocol.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(RecommendPluginURLProtocol.self))
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(RecommendPluginURLProtocol.self)
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.localConfigKey)
    super.tearDown()
  }

  func testPluginSourcesAppearByDefaultInTheirCategoriesAndLoadSelectedShelf() async throws {
    RecommendPluginURLProtocol.setSources("""
      [
        {"name":"IMDb Trending","api_path":"plugin/ImdbSource/imdb-trending","type":"Rankings"},
        {"name":"IMDb Top 250 Movies","api_path":"plugin/ImdbSource/imdb-top-250?mode=top","type":"movies"},
        {"name":"Trending Anime on IMDb","api_path":"plugin/ImdbSource/trending?interest=Anime","type":"ANIME"},
        {"name":"Trending Sitcom on IMDb","api_path":"plugin/ImdbSource/trending?interest=Sitcom","type":"tv shows"}
      ]
      """)
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)

    let plugins = viewModel.filteredShelves.filter { $0.id.hasPrefix("plugin/") }
    XCTAssertEqual(plugins.map(\.title), [
      "IMDb Trending", "IMDb Top 250 Movies", "Trending Anime on IMDb", "Trending Sitcom on IMDb",
    ])
    XCTAssertEqual(plugins.map(\.category), [.chart, .movie, .anime, .tv])
    XCTAssertFalse(viewModel.visibleCategories.contains { $0.rawValue == "其他" })

    viewModel.selectedCategory = .movie
    let movie = try XCTUnwrap(viewModel.filteredShelves.first { $0.id.hasPrefix("plugin/") })
    viewModel.selectedShelf = movie
    try await waitForItems(in: viewModel)
    XCTAssertEqual(viewModel.paginator?.items.first?.title, "插件电影结果")

    // 页面重新显示会重读本机配置；未保存过开关的动态来源仍应保持默认开启。
    viewModel.reloadLocalConfig()
    XCTAssertEqual(viewModel.enableConfig[movie.id], true)
    XCTAssertEqual(viewModel.selectedShelf?.id, movie.id)
    XCTAssertEqual(viewModel.filteredShelves.filter { $0.id.hasPrefix("plugin/") }.map(\.id), [movie.id])

    let request = try XCTUnwrap(RecommendPluginURLProtocol.requests.first {
      $0.url?.path == "/api/v1/plugin/ImdbSource/imdb-top-250"
    })
    let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertEqual(query.first { $0.name == "mode" }?.value, "top")
    XCTAssertEqual(query.first { $0.name == "page" }?.value, "1")
    assertNoWebConfigRequests()
  }

  func testPluginSwitchesPersistLocallyAcrossRefreshRemovalAndNewSources() async throws {
    let sources = """
      [
        {"name":"同名榜","api_path":"plugin/a","type":"Movies"},
        {"name":"同名榜","api_path":"plugin/b","type":"Movies"}
      ]
      """
    // 已有配置缺少插件键时也默认显示，同时保留内置榜单的原有选择。
    seedConfig(["recommend/tmdb_trending": false])
    RecommendPluginURLProtocol.setSources(sources)
    let service = makeService()
    let viewModel = RecommendViewModel(selectShelf: false, apiService: service)
    await viewModel.refreshSources(selectShelf: false)
    XCTAssertEqual(viewModel.enableConfig["plugin/a"], true)
    XCTAssertEqual(viewModel.enableConfig["plugin/b"], true)
    XCTAssertEqual(viewModel.enableConfig["recommend/tmdb_trending"], false)
    XCTAssertFalse(viewModel.filteredShelves.contains { $0.id == "recommend/douban_showing" })

    var config = viewModel.enableConfig
    config["plugin/a"] = false
    viewModel.saveEnableConfig(config)
    XCTAssertEqual(RecommendViewModel.storedEnableConfig()?["plugin/a"], false)
    XCTAssertEqual(RecommendViewModel.storedEnableConfig()?["plugin/b"], true)

    let reopened = RecommendViewModel(selectShelf: false, apiService: service)
    await reopened.refreshSources(selectShelf: false)
    XCTAssertFalse(reopened.filteredShelves.contains { $0.id == "plugin/a" })
    XCTAssertTrue(reopened.filteredShelves.contains { $0.id == "plugin/b" })

    RecommendPluginURLProtocol.setSources("[]", statusCode: 503)
    await reopened.refreshSources(selectShelf: false)
    XCTAssertFalse(reopened.filteredShelves.contains { $0.id == "plugin/a" })
    XCTAssertTrue(reopened.filteredShelves.contains { $0.id == "plugin/b" })

    RecommendPluginURLProtocol.setSources("[]")
    await reopened.refreshSources(selectShelf: false)
    XCTAssertFalse(reopened.shelves.contains { $0.id.hasPrefix("plugin/") })
    RecommendPluginURLProtocol.setSources(sources.dropLast().description + """
      ,{"name":"新增来源","api_path":"plugin/c","type":"Movies"}]
      """)
    await reopened.refreshSources(selectShelf: false)
    XCTAssertEqual(reopened.enableConfig["plugin/a"], false)
    XCTAssertEqual(reopened.enableConfig["plugin/b"], true)
    XCTAssertEqual(reopened.enableConfig["plugin/c"], true)
    XCTAssertTrue(reopened.filteredShelves.contains { $0.id == "plugin/c" })
    assertNoWebConfigRequests()
  }

  func testOtherCategoryShowsUnknownSourcesAndDisappearsWhenDisabled() async throws {
    seedConfig(Dictionary(uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, false) }))
    RecommendPluginURLProtocol.setSources("""
      [{"name":"自定义榜单","api_path":"plugin/custom","type":"Custom Category"}]
      """)
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)
    XCTAssertEqual(viewModel.visibleCategories.map(\.rawValue), ["全部", "其他"])
    XCTAssertEqual(viewModel.filteredShelves.map(\.id), ["plugin/custom"])

    viewModel.selectedCategory = try XCTUnwrap(viewModel.visibleCategories.first { $0.rawValue == "其他" })
    viewModel.onCategoryChanged()
    try await waitForItems(in: viewModel)
    XCTAssertEqual(viewModel.selectedShelf?.id, "plugin/custom")
    XCTAssertEqual(viewModel.paginator?.items.count, 1)

    var config = viewModel.enableConfig
    config["plugin/custom"] = false
    viewModel.saveEnableConfig(config)
    viewModel.reloadLocalConfig()
    XCTAssertTrue(viewModel.visibleCategories.isEmpty)
    XCTAssertTrue(viewModel.filteredShelves.isEmpty)
    XCTAssertEqual(viewModel.selectedCategory, .all)
    XCTAssertNil(viewModel.selectedShelf)
    XCTAssertNil(viewModel.paginator)
    assertNoWebConfigRequests()
  }

  func testLegacyDisabledTitleWinsOverPluginDefaultAndPreservesExplicitID() async {
    seedConfig(["IMDb榜单": false, "plugin/b": true])
    RecommendPluginURLProtocol.setSources("""
      [
        {"name":"IMDb榜单","api_path":"plugin/a","type":"Rankings"},
        {"name":"IMDb榜单","api_path":"plugin/b","type":"Rankings"},
        {"name":"新榜单","api_path":"plugin/c","type":"Rankings"}
      ]
      """)
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)
    XCTAssertEqual(viewModel.enableConfig["plugin/a"], false)
    XCTAssertEqual(viewModel.enableConfig["plugin/b"], true)
    XCTAssertEqual(viewModel.enableConfig["plugin/c"], true)
    XCTAssertNil(RecommendViewModel.storedEnableConfig()?["IMDb榜单"])
    XCTAssertEqual(RecommendViewModel.storedEnableConfig()?["plugin/a"], false)
    XCTAssertEqual(viewModel.filteredShelves.filter { $0.id.hasPrefix("plugin/") }.map(\.id), ["plugin/b", "plugin/c"])
    assertNoWebConfigRequests()
  }

  private func seedConfig(_ config: [String: Bool]) {
    UserDefaults.standard.set(try! JSONEncoder().encode(config), forKey: RecommendViewModel.localConfigKey)
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "recommend-plugin-test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true], user_id: 501, user_name: "recommend-plugin-test", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://recommend-plugin.local", token: user.access_token, currentUser: user
    )
    return service
  }

  private func waitForItems(in viewModel: RecommendViewModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while viewModel.paginator?.items.isEmpty != false, Date() < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(viewModel.paginator?.items.isEmpty ?? true)
  }

  private func assertNoWebConfigRequests(file: StaticString = #filePath, line: UInt = #line) {
    let requests = RecommendPluginURLProtocol.requests
    XCTAssertFalse(requests.isEmpty, file: file, line: line)
    XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" }, file: file, line: line)
    XCTAssertFalse(requests.contains { $0.url?.path.contains("/user/config/") == true }, file: file, line: line)
  }
}

private final class RecommendPluginURLProtocol: URLProtocol {
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
    request.url?.host == "recommend-plugin.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let (status, body) = Self.lock.withLock {
      Self.capturedRequests.append(request)
      if url.path == "/api/v1/recommend/source" { return (Self.sourceStatusCode, Self.sources) }
      return (200, #"[{"tmdb_id":501,"title":"插件电影结果","type":"电影"}]"#)
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
