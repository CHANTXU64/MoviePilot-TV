import XCTest

@testable import MoviePilot_TV

@MainActor
final class RecommendShelfOrderTests: XCTestCase {
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.localConfigKey)
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.orderConfigKey)
    RecommendOrderURLProtocol.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(RecommendOrderURLProtocol.self))
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(RecommendOrderURLProtocol.self)
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.localConfigKey)
    UserDefaults.standard.removeObject(forKey: RecommendViewModel.orderConfigKey)
    super.tearDown()
  }

  func testSavedOrderDrivesFilteredShelvesAndSurvivesReopen() async throws {
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)
    let reordered = ["recommend/douban_movie_hot", "recommend/tmdb_trending"]
    viewModel.saveShelfOrder(reordered)
    XCTAssertEqual(viewModel.filteredShelves.prefix(2).map(\.id), reordered)
    XCTAssertEqual(RecommendViewModel.storedShelfOrder().prefix(2).map { $0 }, reordered)

    let reopened = RecommendViewModel(selectShelf: false, apiService: makeService())
    await reopened.refreshSources(selectShelf: false)
    XCTAssertEqual(reopened.filteredShelves.prefix(2).map(\.id), reordered)
  }

  func testPluginUninstallDuringReorderKeepsGhostSlotAndNewSourcesAppend() async throws {
    RecommendOrderURLProtocol.setSources("""
      [
        {"name":"插件A","api_path":"plugin/a","type":"Movies"},
        {"name":"插件B","api_path":"plugin/b","type":"Movies"}
      ]
      """)
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)
    // 用户把两个插件提到最前。
    viewModel.saveShelfOrder(["plugin/a", "plugin/b"] + RecommendViewModel.allShelves.map(\.id))
    XCTAssertEqual(viewModel.orderedShelves.prefix(2).map(\.id), ["plugin/a", "plugin/b"])

    // A 卸载期间把 B 移到内置货架之后；A 的槽位必须保留。
    RecommendOrderURLProtocol.setSources("""
      [{"name":"插件B","api_path":"plugin/b","type":"Movies"}]
      """)
    await viewModel.refreshSources(selectShelf: false)
    var visible = viewModel.orderedShelves.map(\.id)
    visible.removeAll { $0 == "plugin/b" }
    visible.insert("plugin/b", at: 2)
    viewModel.saveShelfOrder(visible)
    XCTAssertEqual(RecommendViewModel.storedShelfOrder().first, "plugin/a")
    XCTAssertEqual(RecommendViewModel.storedShelfOrder()[3], "plugin/b")

    // A 重装后回到原槽位；新插件 C 追加末尾且默认开启。
    RecommendOrderURLProtocol.setSources("""
      [
        {"name":"插件A","api_path":"plugin/a","type":"Movies"},
        {"name":"插件B","api_path":"plugin/b","type":"Movies"},
        {"name":"插件C","api_path":"plugin/c","type":"Movies"}
      ]
      """)
    await viewModel.refreshSources(selectShelf: false)
    XCTAssertEqual(viewModel.orderedShelves.first?.id, "plugin/a")
    XCTAssertEqual(viewModel.orderedShelves[3].id, "plugin/b")
    XCTAssertEqual(viewModel.orderedShelves.last?.id, "plugin/c")
    XCTAssertEqual(viewModel.enableConfig["plugin/c"], true)
  }

  func testResetOrderRestoresDefaultAndKeepsVisibility() async throws {
    let viewModel = RecommendViewModel(selectShelf: false, apiService: makeService())
    await viewModel.refreshSources(selectShelf: false)
    viewModel.saveEnableConfig(["recommend/tmdb_trending": false])
    viewModel.saveShelfOrder(["recommend/douban_movie_hot", "recommend/tmdb_trending"])
    viewModel.resetShelfOrder()
    XCTAssertTrue(RecommendViewModel.storedShelfOrder().isEmpty)
    XCTAssertEqual(viewModel.orderedShelves.map(\.id), RecommendViewModel.allShelves.map(\.id))
    XCTAssertEqual(viewModel.enableConfig["recommend/tmdb_trending"], false)
  }

  func testReenablingShelfAfterHideAllRecreatesPaginator() async throws {
    let trending = "recommend/tmdb_trending"
    let viewModel = RecommendViewModel(selectShelf: true, apiService: makeService())
    await viewModel.refreshSources()
    try await waitForItems(in: viewModel)
    XCTAssertEqual(viewModel.selectedShelf?.id, trending)

    // 全部隐藏：选中清空、分页器取消。
    viewModel.saveEnableConfig(Dictionary(uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, false) }))
    viewModel.reloadLocalConfig()
    XCTAssertNil(viewModel.selectedShelf)
    XCTAssertNil(viewModel.paginator)

    // 重新启用同一货架：X→nil→X 被去重管道吞掉，必须显式重建分页器。
    viewModel.saveEnableConfig([trending: true])
    viewModel.reloadLocalConfig()
    XCTAssertEqual(viewModel.selectedShelf?.id, trending)
    try await waitForItems(in: viewModel)
    XCTAssertEqual(viewModel.paginator?.items.first?.title, "顺序测试电影")
  }

  func testReenablingDifferentShelfAfterHideAllCreatesSinglePaginator() async throws {
    let viewModel = RecommendViewModel(selectShelf: true, apiService: makeService())
    await viewModel.refreshSources()
    try await waitForItems(in: viewModel)

    viewModel.saveEnableConfig(Dictionary(uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, false) }))
    viewModel.reloadLocalConfig()
    XCTAssertNil(viewModel.paginator)

    // 重开一个不同的货架（A→nil→B）：管道单一负责，不得与补偿路径重复创建。
    viewModel.saveEnableConfig(["recommend/douban_showing": true])
    viewModel.reloadLocalConfig()
    XCTAssertEqual(viewModel.selectedShelf?.id, "recommend/douban_showing")
    try await waitForItems(in: viewModel)
    try await Task.sleep(for: .milliseconds(300))
    let requests = RecommendOrderURLProtocol.requests.filter {
      $0.url?.path.contains("recommend/douban_showing") == true
    }
    XCTAssertEqual(requests.count, 1, "A→nil→B 不得重复创建分页器")
  }

  func testStaleDebouncedShelfDoesNotCreatePaginatorAfterHideAll() async throws {
    let viewModel = RecommendViewModel(selectShelf: true, apiService: makeService())
    await viewModel.refreshSources()
    try await waitForItems(in: viewModel)

    // 切换货架触发 100ms debounce，在触发前全部隐藏。
    let next = try XCTUnwrap(viewModel.filteredShelves.dropFirst().first)
    viewModel.selectedShelf = next
    viewModel.saveEnableConfig(Dictionary(uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, false) }))
    viewModel.reloadLocalConfig()
    XCTAssertNil(viewModel.paginator)

    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(viewModel.paginator, "debounce 陈旧触发不得为已隐藏货架重建分页器")
    XCTAssertFalse(
      RecommendOrderURLProtocol.requests.contains { $0.url?.path.contains(next.id) == true },
      "已隐藏货架不得发起媒体请求")
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "recommend-order-test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true], user_id: 502, user_name: "recommend-order-test", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://recommend-order.local", token: user.access_token, currentUser: user
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
}

private final class RecommendOrderURLProtocol: URLProtocol {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var sources = "[]"
  nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

  static var requests: [URLRequest] { lock.withLock { capturedRequests } }

  static func reset() {
    lock.withLock {
      sources = "[]"
      capturedRequests = []
    }
  }

  static func setSources(_ json: String) {
    lock.withLock { sources = json }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "recommend-order.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let body = Self.lock.withLock { () -> String in
      Self.capturedRequests.append(request)
      if url.path == "/api/v1/recommend/source" {
        return Self.sources
      }
      return #"[{"tmdb_id":601,"title":"顺序测试电影","type":"电影"}]"#
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}