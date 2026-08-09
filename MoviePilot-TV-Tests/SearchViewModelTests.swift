import Foundation
import XCTest

@testable import MoviePilot_TV

private enum SearchViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor SearchAsyncGate {
  private var isOpen = false

  func wait() async {
    while !isOpen {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func open() {
    isOpen = true
  }
}

private func withTimeout<T: Sendable>(
  _ description: String,
  seconds: TimeInterval = 2,
  operation: @escaping @Sendable () async -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw SearchViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

@MainActor
final class SearchViewModelTests: XCTestCase {
  func testOlderUnifiedSearchCompletionDoesNotClearLoadingForNewerSearch() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    let oldSearchGate = SearchAsyncGate()
    let newSearchGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(oldSearchGate, forQuery: "old")
    await SearchViewModelURLProtocol.stub.setGate(newSearchGate, forQuery: "new")

    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "old"

    let oldSearchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { oldSearchTask.cancel() }

    try await withTimeout("old search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "old")
    }

    viewModel.query = "new"
    let newSearchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { newSearchTask.cancel() }

    try await withTimeout("new search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "new")
    }

    await oldSearchGate.open()
    try await withTimeout("old search to finish after new search starts") {
      await oldSearchTask.value
    }

    XCTAssertEqual(viewModel.submittedQuery, "new")
    XCTAssertTrue(
      viewModel.isLoading,
      "A stale unified search must not clear loading while a newer search is still running."
    )
    XCTAssertFalse(
      viewModel.hasSearched,
      "A stale unified search must not mark a newer in-flight search as completed."
    )

    await newSearchGate.open()
    try await withTimeout("new search to finish") {
      await newSearchTask.value
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertTrue(viewModel.hasSearched)
    let bestResultTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item {
        return media.title
      }
      return nil
    }
    XCTAssertEqual(bestResultTitles, ["New Result"])
    let shareRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/subscribe/shares"
    )
    XCTAssertEqual(
      shareRequestCount,
      0,
      "Unified search should not auto-load subscription shares for a user without subscribe permission."
    )
  }

  func testUnifiedSearchSessionChangeEndsLoading() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    let gate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(gate, forQuery: "session-change")
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "session-change"

    let searchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { searchTask.cancel() }

    try await withTimeout("unified search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "session-change")
    }

    configureChangedDiscoveryPermissionSession(service)
    await gate.open()
    try await withTimeout("unified search to stop after session change") {
      await searchTask.value
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertFalse(viewModel.hasSearched)
  }

  func testResourceSearchSessionChangeEndsLoading() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    let gate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(gate, forQuery: "resource-session-change")
    service.baseURLForTesting = "http://search-tests.local"
    configureSearchPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "resource-session-change"
    await viewModel.autoSearch()

    try await withTimeout("resource search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", query: "resource-session-change")
    }

    configureChangedSearchPermissionSession(service)
    await gate.open()

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertFalse(viewModel.hasSearched)
  }

  func testResourceSearchTreatsMediaKeyAsTitleText() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSearchPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "anilist:154587"
    await viewModel.autoSearch()

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    let mediaStreamRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/media/anilist:154587/stream"
    )
    let titleStreamRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title/stream"
    )
    XCTAssertEqual(mediaStreamRequestCount, 0)
    XCTAssertEqual(titleStreamRequestCount, 1)
  }

  func testSearchTypesAndExecutionUseWebPermissionSplit() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    XCTAssertEqual(viewModel.availableSearchTypes, [.unified])

    viewModel.searchType = .resource
    viewModel.query = "forbidden-resource"
    await viewModel.autoSearch()
    let forbiddenResourceRequestCount =
      await SearchViewModelURLProtocol.stub.requestCount(path: "/api/v1/search/title/stream")
    XCTAssertEqual(forbiddenResourceRequestCount, 0)

    configureSearchPermissionSession(service)
    XCTAssertEqual(viewModel.availableSearchTypes, [.resource])
    viewModel.normalizeSearchTypeForPermissions()
    XCTAssertEqual(viewModel.searchType, .resource)

    viewModel.searchType = .unified
    viewModel.query = "forbidden-metadata"
    await viewModel.autoSearch()
    let forbiddenMetadataRequestCount =
      await SearchViewModelURLProtocol.stub.requestCount(path: "/api/v1/media/search")
    XCTAssertEqual(forbiddenMetadataRequestCount, 0)

    await SearchViewModelURLProtocol.stub.reset()
    configureSubscribePermissionSession(service)
    let shareViewModel = SearchViewModel(apiService: service)
    XCTAssertEqual(shareViewModel.availableSearchTypes, [])
    shareViewModel.normalizeSearchTypeForPermissions()
    XCTAssertEqual(shareViewModel.searchType, .unified)

    shareViewModel.query = "科幻"
    await shareViewModel.autoSearch()
    let mediaRequestCount =
      await SearchViewModelURLProtocol.stub.requestCount(path: "/api/v1/media/search")
    let resourceRequestCount =
      await SearchViewModelURLProtocol.stub.requestCount(path: "/api/v1/search/title/stream")
    XCTAssertEqual(
      mediaRequestCount,
      0,
      "只有 subscribe 权限时不应暴露搜索模式或启动媒体搜索。"
    )
    XCTAssertEqual(resourceRequestCount, 0)
  }

  func testMediaSourceSelectionOnlyAffectsNextUnifiedSearch() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = .douban
    await Task.yield()

    let requestsBeforeSearch =
      await SearchViewModelURLProtocol.stub.requestCount(path: "/api/v1/media/search")
    XCTAssertEqual(requestsBeforeSearch, 0)

    viewModel.query = "source-selection"
    await viewModel.autoSearch()

    let mediaSources = await SearchViewModelURLProtocol.stub.sourceValues(
      path: "/api/v1/media/search",
      type: "media"
    )
    let collectionRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/media/search",
      type: "collection"
    )
    let personSources = await SearchViewModelURLProtocol.stub.sourceValues(
      path: "/api/v1/media/search",
      type: "person"
    )

    XCTAssertEqual(Set(mediaSources.compactMap { $0 }), ["douban"])
    XCTAssertEqual(collectionRequestCount, 0)
    XCTAssertEqual(Set(personSources.compactMap { $0 }), ["douban"])
  }

  func testDefaultMediaSourceSelectionUsesBackendDefaults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "backend-default"
    await viewModel.autoSearch()

    let sourceValues = await SearchViewModelURLProtocol.stub.sourceValues(
      path: "/api/v1/media/search"
    )
    XCTAssertFalse(sourceValues.isEmpty)
    XCTAssertTrue(sourceValues.allSatisfy { $0 == nil })
  }

  func testTVMediaSourceDefaultsAreLoadedBySearchViewModel() {
    let service = APIService.shared
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://search-tests.local"
    configureSearchPermissionSession(service)
    let settingsViewModel = SystemViewModel()
    let originalSource = settingsViewModel.defaultMediaSearchSource
    defer { settingsViewModel.defaultMediaSearchSource = originalSource }

    settingsViewModel.defaultMediaSearchSource = .douban
    XCTAssertEqual(SearchViewModel().mediaSearchSource, .douban)

    settingsViewModel.defaultMediaSearchSource = nil
    XCTAssertNil(SearchViewModel().mediaSearchSource)
  }

  func testCancelledResourceSearchFilteringDoesNotPublishOldResultsOrClearNewLoading()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    let oldFilterGate = SearchAsyncGate()
    let newStreamGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setCustomFilterGate(oldFilterGate)
    await SearchViewModelURLProtocol.stub.setGate(newStreamGate, forQuery: "new")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "old"

    await viewModel.autoSearch()

    try await withTimeout("old resource stream request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", query: "old")
    }
    try await withTimeout("old resource search to enter async filtering") {
      await SearchViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/system/setting/CustomFilterRules")
    }

    viewModel.query = "new"
    await viewModel.autoSearch()

    try await withTimeout("new resource stream request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", query: "new")
    }
    try await withTimeout("old resource filtering request cancellation") {
      await SearchViewModelURLProtocol.stub.waitForCancellation(
        path: "/api/v1/system/setting/CustomFilterRules")
    }
    await Task.yield()

    XCTAssertEqual(viewModel.submittedQuery, "new")
    XCTAssertTrue(
      viewModel.isLoading,
      "A cancelled older resource search must not clear the loading state for the newer search."
    )
    XCTAssertTrue(
      viewModel.resourceResults.isEmpty,
      "A cancelled older resource search must not publish stale resource results while a newer search is in flight."
    )

    await oldFilterGate.open()
    await newStreamGate.open()
  }

  func testCustomFilterSkipsRulesForNonSuperuserSearchUserWithPersistedRuleSelection()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = Token(
      access_token: "limited-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["search": true],
      user_id: 305,
      user_name: "limited",
      avatar: nil
    )
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    let contexts = [
      Context(
        torrent_info: TorrentInfo(
          site: 1,
          site_name: "Test Site",
          site_order: 1,
          title: "Limited Result",
          description: "",
          enclosure: "https://example.test/limited",
          page_url: "https://example.test/limited",
          size: 1024,
          seeders: 10,
          peers: 1,
          pubdate: "2026-06-16 10:00:00",
          uploadvolumefactor: 1.0,
          downloadvolumefactor: 1.0,
          pri_order: 1,
          labels: [],
          volume_factor: "1x"
        )
      )
    ]

    let filtered = try await CustomFilterService.applyHardAndSoftFilter(
      to: contexts,
      using: service,
      caller: "limited-user-test"
    )

    XCTAssertEqual(filtered.count, 1)
    XCTAssertEqual(filtered.first?.torrent_info?.title, "Limited Result")
    let customFilterRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/system/setting/CustomFilterRules"
    )
    XCTAssertEqual(
      customFilterRequestCount,
      0,
      "Search users may keep using search results, but CustomFilterRules is a superuser-only setting."
    )
  }

  func testMapMediaToSubscribePreservesUnifiedIdentity() {
    let subscribe = SearchViewModel().mapMediaToSubscribe(
      MediaInfo(
        tmdb_id: 42,
        anilist_id: 154_587,
        source: "anilist",
        mediaid_prefix: "anilist",
        media_id: "154587",
        title: "搜索结果",
        type: "电影"
      )
    )

    XCTAssertEqual(subscribe.anilistid, 154_587)
    XCTAssertEqual(subscribe.media_source, "anilist")
    XCTAssertEqual(subscribe.media_id, "154587")
    XCTAssertEqual(subscribe.mediaid, "anilist:154587")
  }
}

@MainActor
private struct SearchViewModelServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let accessTokenDefaults: String?

  static func capture(service: APIService) -> SearchViewModelServiceSnapshot {
    SearchViewModelServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      accessTokenDefaults: UserDefaults.standard.string(forKey: "accessToken")
    )
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.tokenForTesting = token
    service.currentUserForTesting = currentUser

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }

    if let accessTokenDefaults {
      UserDefaults.standard.set(accessTokenDefaults, forKey: "accessToken")
    } else {
      UserDefaults.standard.removeObject(forKey: "accessToken")
    }
  }
}

private struct SearchViewModelHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private actor SearchViewModelURLProtocolStub {
  private var gatesByQuery: [String: SearchAsyncGate] = [:]
  private var customFilterGate: SearchAsyncGate?
  private var requestedRequests: [SearchRecordedRequest] = []
  private var cancelledRequests: [SearchRecordedRequest] = []

  func reset() {
    gatesByQuery.removeAll()
    customFilterGate = nil
    requestedRequests.removeAll()
    cancelledRequests.removeAll()
  }

  func setGate(_ gate: SearchAsyncGate, forQuery query: String) {
    gatesByQuery[query] = gate
  }

  func setCustomFilterGate(_ gate: SearchAsyncGate) {
    customFilterGate = gate
  }

  func response(for request: URLRequest) async throws -> SearchViewModelHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    let queryItems = components.queryItems ?? []
    let query = queryItems.first(where: { $0.name == "title" })?.value
      ?? queryItems.first(where: { $0.name == "name" })?.value
      ?? queryItems.first(where: { $0.name == "keyword" })?.value
      ?? ""
    recordRequest(
      path: components.path,
      query: query,
      type: queryItems.first(where: { $0.name == "type" })?.value,
      source: queryItems.first(where: { $0.name == "source" })?.value
    )

    if components.path == "/api/v1/system/setting/CustomFilterRules",
      let gate = customFilterGate
    {
      await gate.wait()
    } else if let gate = gatesByQuery[query] {
      await gate.wait()
    }

    return SearchViewModelHTTPStubResponse(
      statusCode: 200,
      data: responseData(path: components.path, queryItems: queryItems, query: query)
    )
  }

  func waitForRequest(query: String) async {
    while !requestedRequests.contains(where: { $0.query == query }) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForRequest(path: String, query: String? = nil) async {
    while !requestedRequests.contains(where: { request in
      request.path == path && (query == nil || request.query == query)
    }) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func recordCancellation(for request: URLRequest) {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return }
    let queryItems = components.queryItems ?? []
    let query = queryItems.first(where: { $0.name == "title" })?.value
      ?? queryItems.first(where: { $0.name == "name" })?.value
      ?? queryItems.first(where: { $0.name == "keyword" })?.value
      ?? ""
    cancelledRequests.append(
      SearchRecordedRequest(
        path: components.path,
        query: query,
        type: queryItems.first(where: { $0.name == "type" })?.value,
        source: queryItems.first(where: { $0.name == "source" })?.value
      )
    )
  }

  func waitForCancellation(path: String, query: String? = nil) async {
    while !cancelledRequests.contains(where: { request in
      request.path == path && (query == nil || request.query == query)
    }) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func requestCount(path: String) -> Int {
    requestedRequests.filter { $0.path == path }.count
  }

  func requestCount(path: String, type: String) -> Int {
    requestedRequests.filter { $0.path == path && $0.type == type }.count
  }

  func sourceValues(path: String, type: String? = nil) -> [String?] {
    requestedRequests
      .filter { $0.path == path && (type == nil || $0.type == type) }
      .map(\.source)
  }

  private func recordRequest(path: String, query: String, type: String?, source: String?) {
    requestedRequests.append(
      SearchRecordedRequest(path: path, query: query, type: type, source: source)
    )
  }

  private func responseData(path: String, queryItems: [URLQueryItem], query: String) -> Data {
    if path == "/api/v1/search/title/stream" {
      return resourceSearchStreamData(title: query == "new" ? "New Resource" : "Old Resource")
    }
    if path == "/api/v1/system/setting/CustomFilterRules" {
      return Data(
        """
        {"data":{"value":[{"id":"allow-all","name":"Allow All"}]}}
        """.utf8)
    }

    if path == "/api/v1/subscribe/shares" {
      return Data("[]".utf8)
    }

    let type = queryItems.first(where: { $0.name == "type" })?.value
    guard type == nil || type == "media" else {
      return Data("[]".utf8)
    }

    let page = queryItems.first(where: { $0.name == "page" })?.value ?? "1"
    guard page == "1" else {
      return Data("[]".utf8)
    }

    let id = query == "new" ? 1002 : 1001
    let title = query == "new" ? "New Result" : "Old Result"
    return Data(
      """
      [
        {
          "tmdb_id": \(id),
          "title": "\(title)",
          "type": "电影",
          "year": "2026",
          "poster_path": "/poster-\(id).jpg",
          "popularity": 100
        }
      ]
      """.utf8)
  }

  private func resourceSearchStreamData(title: String) -> Data {
    let event =
      "data: {\"type\":\"append\",\"text\":\"Searching\",\"value\":50,\"items\":["
      + resourceContextJSON(title: title)
      + "]}\n\n"
    return Data(event.utf8)
  }

  private func resourceContextJSON(title: String) -> String {
    let slug = title.replacingOccurrences(of: " ", with: "-")
    return #"{"torrent_info":{"site":1,"site_name":"Test Site","site_order":1,"title":"\#(title)","description":"","enclosure":"https://example.test/\#(slug)","page_url":"https://example.test/\#(slug)","size":1024,"seeders":10,"peers":1,"pubdate":"2026-06-16 10:00:00","uploadvolumefactor":1.0,"downloadvolumefactor":1.0,"pri_order":1,"labels":[],"volume_factor":"1x"}}"#
  }
}

private struct SearchRecordedRequest: Equatable {
  let path: String
  let query: String
  let type: String?
  let source: String?
}

@MainActor
private func configureSearchPermissionSession(_ service: APIService) {
  service.tokenForTesting = "search-permission-token"
  service.currentUserForTesting = Token(
    access_token: "search-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": false,
      "search": true,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 301,
    user_name: "search-user",
    avatar: nil
  )
}

@MainActor
private func configureDiscoveryPermissionSession(_ service: APIService) {
  service.tokenForTesting = "discovery-permission-token"
  service.currentUserForTesting = Token(
    access_token: "discovery-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": true,
      "search": false,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 302,
    user_name: "discovery-user",
    avatar: nil
  )
}

@MainActor
private func configureSubscribePermissionSession(_ service: APIService) {
  service.tokenForTesting = "subscribe-permission-token"
  service.currentUserForTesting = Token(
    access_token: "subscribe-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": false,
      "search": false,
      "subscribe": true,
      "manage": false,
      "admin": false,
    ],
    user_id: 303,
    user_name: "subscribe-user",
    avatar: nil
  )
}

@MainActor
private func configureChangedSearchPermissionSession(_ service: APIService) {
  service.currentUserForTesting = Token(
    access_token: service.token ?? "search-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": false,
      "search": true,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 301,
    user_name: "changed-search-user",
    avatar: nil
  )
}

@MainActor
private func configureChangedDiscoveryPermissionSession(_ service: APIService) {
  service.currentUserForTesting = Token(
    access_token: service.token ?? "discovery-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": true,
      "search": false,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 302,
    user_name: "changed-discovery-user",
    avatar: nil
  )
}

@MainActor
private func configureSuperUserSearchSession(_ service: APIService) {
  service.tokenForTesting = "super-user-search-token"
  service.currentUserForTesting = Token(
    access_token: "super-user-search-token",
    token_type: "bearer",
    super_user: FlexibleBool(true),
    permissions: [
      "discovery": true,
      "search": true,
      "subscribe": true,
      "manage": true,
    ],
    user_id: 304,
    user_name: "admin",
    avatar: nil
  )
}

@MainActor
private struct SearchViewModelFilterSelectionSnapshot {
  let hardKey: String
  let softKey: String
  let hardValue: String?
  let softValue: String?

  static func selectHardRule(_ ruleId: String, apiService: APIService)
    -> SearchViewModelFilterSelectionSnapshot
  {
    let profileKey = apiService.profileKey ?? "missing-profile"
    let hardKey = "selectedCustomFilterRuleId_\(profileKey)"
    let softKey = "selectedSoftFilterRuleId_\(profileKey)"
    let snapshot = SearchViewModelFilterSelectionSnapshot(
      hardKey: hardKey,
      softKey: softKey,
      hardValue: UserDefaults.standard.string(forKey: hardKey),
      softValue: UserDefaults.standard.string(forKey: softKey)
    )
    UserDefaults.standard.set(ruleId, forKey: hardKey)
    UserDefaults.standard.removeObject(forKey: softKey)
    return snapshot
  }

  func restore() {
    if let hardValue {
      UserDefaults.standard.set(hardValue, forKey: hardKey)
    } else {
      UserDefaults.standard.removeObject(forKey: hardKey)
    }

    if let softValue {
      UserDefaults.standard.set(softValue, forKey: softKey)
    } else {
      UserDefaults.standard.removeObject(forKey: softKey)
    }
  }
}

private final class SearchViewModelURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = SearchViewModelURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "search-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SearchViewModelURLProtocolTaskContext(
      request: request,
      clientBox: SearchViewModelURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = SearchViewModelURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SearchViewModelURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await SearchViewModelURLProtocol.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    let requestToCancel = request
    Task {
      await SearchViewModelURLProtocol.stub.recordCancellation(for: requestToCancel)
    }
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class SearchViewModelURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SearchViewModelURLProtocolClientBox

  init(request: URLRequest, clientBox: SearchViewModelURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SearchViewModelURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: SearchViewModelHTTPStubResponse) {
    guard let url = request.url else {
      fail(URLError(.badURL))
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
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
