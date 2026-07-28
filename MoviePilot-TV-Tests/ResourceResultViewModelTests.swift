import Foundation
import XCTest

@testable import MoviePilot_TV

private enum ResourceResultViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
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
      throw ResourceResultViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

private func completesWithin(
  seconds: TimeInterval = 2,
  operation: @escaping @Sendable () async -> Void
) async -> Bool {
  await withTaskGroup(of: Bool.self) { group in
    group.addTask {
      await operation()
      return true
    }
    group.addTask {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      return false
    }

    let result = await group.next()!
    group.cancelAll()
    return result
  }
}

private final class WeakBox<T: AnyObject> {
  weak var value: T?

  init(_ value: T?) {
    self.value = value
  }
}

private actor ResourceResultAsyncGate {
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

@MainActor
final class ResourceResultViewModelTests: XCTestCase {
  func testSearchStreamAggregationMatchesWebOrderingAndFinalResultRules() throws {
    func event(_ type: String, title: String?) throws -> SearchStreamEvent {
      let items = title.map { "[\(resourceContextJSON(title: $0))]" } ?? "[]"
      let batchMetadata =
        type == "replace"
        ? #","replace_batch":true,"batch_index":0,"batch_count":2"#
        : ""
      return try JSONDecoder().decode(
        SearchStreamEvent.self,
        from: Data(#"{"type":"\#(type)","items":\#(items)\#(batchMetadata)}"#.utf8)
      )
    }

    var preview: [Context] = []
    var previewFinalApplied = false
    try event("append", title: "Older").applyResourceItems(
      to: &preview, finalResultApplied: &previewFinalApplied)
    try event("append", title: "Newer").applyResourceItems(
      to: &preview, finalResultApplied: &previewFinalApplied)
    try event("done", title: nil).applyResourceItems(
      to: &preview, finalResultApplied: &previewFinalApplied)
    XCTAssertEqual(preview.compactMap(\.torrent_info?.title), ["Newer", "Older"])

    var final: [Context] = []
    var finalApplied = false
    try event("replace", title: "Final").applyResourceItems(
      to: &final, finalResultApplied: &finalApplied)
    try event("append", title: "Post Replace").applyResourceItems(
      to: &final, finalResultApplied: &finalApplied)
    try event("heartbeat", title: nil).applyResourceItems(
      to: &final, finalResultApplied: &finalApplied)
    try event("done", title: "Stale Done").applyResourceItems(
      to: &final, finalResultApplied: &finalApplied)
    XCTAssertEqual(final.compactMap(\.torrent_info?.title), ["Final"])
  }

  func testDeinitCancelsInFlightSearchStream() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    var viewModel: ResourceResultViewModel? = ResourceResultViewModel(keyword: "stale")
    let releasedViewModel = WeakBox(viewModel)

    await viewModel?.search()

    try await withTimeout("resource search stream request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest()
    }

    viewModel = nil

    XCTAssertNil(
      releasedViewModel.value,
      "The in-flight resource stream task must not keep the view model alive after the view is gone."
    )
    try await withTimeout("resource search stream cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation()
    }
  }

  func testCancelSearchCancelsInFlightSearchStream() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "stale")
    await viewModel.search()

    try await withTimeout("resource search stream request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest()
    }

    viewModel.cancelSearch()

    try await withTimeout("resource search stream cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation()
    }
    XCTAssertFalse(viewModel.isLoading)
  }

  func testCancelledFallbackDoesNotPublishResultsAsCompletedSearch() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSuperUserSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", baseURL: service.baseURL)
    defer { filterSnapshot.restore() }

    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "fallback")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Fallback Result")],
      forKeyword: "fallback"
    )
    await ResourceResultViewModelURLProtocol.stub.setCustomFilterGate(ResourceResultAsyncGate())

    let viewModel = ResourceResultViewModel(keyword: "fallback")
    await viewModel.search()

    try await withTimeout("resource stream request to fail into fallback") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "fallback")
    }
    try await withTimeout("fallback resource request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "fallback")
    }
    try await withTimeout("fallback result to enter async filtering") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/system/setting/CustomFilterRules")
    }

    viewModel.cancelSearch()

    try await withTimeout("fallback filtering request cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation(
        path: "/api/v1/system/setting/CustomFilterRules")
    }
    await Task.yield()

    XCTAssertTrue(
      viewModel.results.isEmpty,
      "Cancelling during fallback must not let stale fallback results appear as completed search results."
    )
  }

  func testSearchCanRestartAfterDisappearCancellation() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "repeat")
    await viewModel.search()

    try await withTimeout("first resource search request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "repeat")
    }

    viewModel.cancelSearch()

    try await withTimeout("first resource search cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation(
        path: "/api/v1/search/title/stream", keyword: "repeat")
    }

    await viewModel.search()

    let didStartSecondSearch = await completesWithin {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "repeat", count: 2)
    }
    XCTAssertTrue(
      didStartSecondSearch,
      "After onDisappear cancellation, appearing again and calling search() should start a new resource stream request."
    )
  }

  func testInFlightDisappearCancellationAllowsSearchToRestart() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "tab-switch")
    await viewModel.search()

    try await withTimeout("first resource search request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "tab-switch")
    }

    viewModel.cancelInFlightSearch()

    try await withTimeout("first resource search cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation(
        path: "/api/v1/search/title/stream", keyword: "tab-switch")
    }

    await viewModel.search()

    let didStartSecondSearch = await completesWithin {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "tab-switch", count: 2)
    }
    XCTAssertTrue(
      didStartSecondSearch,
      "An in-flight search cancelled by view disappearance should restart when the view appears again."
    )
  }

  func testSessionChangeEndsLoadingAndAllowsSearchToRestart() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let fallbackGate = ResourceResultAsyncGate()
    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "session-change")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Stale Result")],
      forKeyword: "session-change"
    )
    await ResourceResultViewModelURLProtocol.stub.setFallbackGate(
      fallbackGate, forKeyword: "session-change")

    let viewModel = ResourceResultViewModel(keyword: "session-change")
    defer { viewModel.cancelSearch() }
    await viewModel.search()

    try await withTimeout("resource search to enter fallback request") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "session-change")
    }

    service.currentUser = Token(
      access_token: service.token ?? "resource-result-search-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": true,
        "subscribe": false,
        "manage": false,
        "admin": false,
      ],
      user_name: "changed-resource-user",
      avatar: nil
    )
    await fallbackGate.open()

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertTrue(viewModel.results.isEmpty)

    await viewModel.search()
    let didRestart = await completesWithin {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "session-change", count: 2)
    }
    XCTAssertTrue(didRestart)
  }

  func testSessionChangeDoesNotPublishStaleFallbackError() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let fallbackGate = ResourceResultAsyncGate()
    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "stale-error")
    await ResourceResultViewModelURLProtocol.stub.setFallbackFailure(forKeyword: "stale-error")
    await ResourceResultViewModelURLProtocol.stub.setFallbackGate(
      fallbackGate, forKeyword: "stale-error")

    let viewModel = ResourceResultViewModel(keyword: "stale-error")
    defer { viewModel.cancelSearch() }
    await viewModel.search()

    try await withTimeout("resource search to enter failing fallback request") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "stale-error")
    }

    service.currentUser = Token(
      access_token: service.token ?? "resource-result-search-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": true,
        "subscribe": false,
        "manage": false,
        "admin": false,
      ],
      user_name: "changed-resource-user",
      avatar: nil
    )
    await fallbackGate.open()

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(
      viewModel.errorMessage,
      "A fallback failure from an obsolete session must not overwrite the current error state."
    )
  }

  func testCompletedSearchDoesNotRestartAfterInFlightDisappearCancellation() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", baseURL: service.baseURL)
    defer { filterSnapshot.restore() }

    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "finished")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Finished Result")],
      forKeyword: "finished"
    )

    let viewModel = ResourceResultViewModel(keyword: "finished")
    await viewModel.search()

    try await withTimeout("fallback resource search to complete") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "finished")
    }

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.results.count, 1)

    viewModel.cancelInFlightSearch()
    await viewModel.search()

    let didStartSecondSearch = await completesWithin(seconds: 0.2) {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", keyword: "finished", count: 2)
    }
    XCTAssertFalse(
      didStartSecondSearch,
      "A completed resource search should keep hasSearched true when the view only cancels in-flight work on disappear."
    )
  }

  func testMalformedStreamFallsBackToRequestSearch() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: not-json\n\n",
      forKeyword: "malformed"
    )
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Fallback Result")],
      forKeyword: "malformed"
    )
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "malformed")
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.results.count, 1)
    let fallbackRequestCount = await ResourceResultViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title",
      keyword: "malformed"
    )
    XCTAssertEqual(fallbackRequestCount, 1)
  }

  func testBusinessStreamErrorShowsLocalizedReasonWithoutRequestFallback() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"error\",\"message\":\"Search failed\",\"message_i18n\":\"搜索失败\"}\n\n",
      forKeyword: "business-error"
    )
    service.baseURL = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "business-error")
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.errorMessage, "搜索失败")
    let fallbackRequestCount = await ResourceResultViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title",
      keyword: "business-error"
    )
    XCTAssertEqual(fallbackRequestCount, 0)
  }
}

@MainActor
private struct ResourceResultViewModelServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let accessTokenDefaults: String?

  static func capture(service: APIService) -> ResourceResultViewModelServiceSnapshot {
    ResourceResultViewModelServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      accessTokenDefaults: UserDefaults.standard.string(forKey: "accessToken")
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser

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

private actor ResourceResultViewModelURLProtocolStub {
  private var requestedRequests: [ResourceResultRecordedRequest] = []
  private var cancelledRequests: [ResourceResultRecordedRequest] = []
  private var streamFailureKeywords: Set<String> = []
  private var streamBodiesByKeyword: [String: Data] = [:]
  private var fallbackResultsByKeyword: [String: [String]] = [:]
  private var fallbackFailureKeywords: Set<String> = []
  private var fallbackGatesByKeyword: [String: ResourceResultAsyncGate] = [:]
  private var customFilterGate: ResourceResultAsyncGate?

  func reset() {
    requestedRequests.removeAll()
    cancelledRequests.removeAll()
    streamFailureKeywords.removeAll()
    streamBodiesByKeyword.removeAll()
    fallbackResultsByKeyword.removeAll()
    fallbackFailureKeywords.removeAll()
    fallbackGatesByKeyword.removeAll()
    customFilterGate = nil
  }

  func setStreamFailure(forKeyword keyword: String) {
    streamFailureKeywords.insert(keyword)
  }

  func setStreamBody(_ body: String, forKeyword keyword: String) {
    streamBodiesByKeyword[keyword] = Data(body.utf8)
  }

  func setFallbackResults(_ results: [String], forKeyword keyword: String) {
    fallbackResultsByKeyword[keyword] = results
  }

  func setFallbackFailure(forKeyword keyword: String) {
    fallbackFailureKeywords.insert(keyword)
  }

  func setFallbackGate(_ gate: ResourceResultAsyncGate, forKeyword keyword: String) {
    fallbackGatesByKeyword[keyword] = gate
  }

  func setCustomFilterGate(_ gate: ResourceResultAsyncGate) {
    customFilterGate = gate
  }

  func response(for request: URLRequest) async throws -> ResourceResultHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    let queryItems = components.queryItems ?? []
    let keyword = queryItems.first(where: { $0.name == "keyword" })?.value ?? ""
    recordRequest(path: components.path, keyword: keyword)

    if components.path == "/api/v1/search/title/stream" {
      if streamFailureKeywords.contains(keyword) {
        return ResourceResultHTTPStubResponse(statusCode: 500, data: Data())
      }
      if let body = streamBodiesByKeyword[keyword] {
        return ResourceResultHTTPStubResponse(statusCode: 200, data: body)
      }
      try await waitUntilCancelled()
    }

    if components.path == "/api/v1/search/title" {
      if let gate = fallbackGatesByKeyword[keyword] {
        await gate.wait()
      }
      if fallbackFailureKeywords.contains(keyword) {
        return ResourceResultHTTPStubResponse(
          statusCode: 500,
          data: Data(#"{"detail":"Fallback failed"}"#.utf8)
        )
      }
      return ResourceResultHTTPStubResponse(
        statusCode: 200,
        data: Data("[\((fallbackResultsByKeyword[keyword] ?? []).joined(separator: ","))]".utf8)
      )
    }

    if components.path == "/api/v1/system/setting/CustomFilterRules" {
      if let customFilterGate {
        await customFilterGate.wait()
      }
      return ResourceResultHTTPStubResponse(
        statusCode: 200,
        data: Data(#"{"data":{"value":[{"id":"allow-all","name":"Allow All"}]}}"#.utf8)
      )
    }

    return ResourceResultHTTPStubResponse(statusCode: 200, data: Data("[]".utf8))
  }

  func recordCancellation(for request: URLRequest) {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return }
    let keyword = (components.queryItems ?? []).first(where: { $0.name == "keyword" })?.value ?? ""
    cancelledRequests.append(ResourceResultRecordedRequest(path: components.path, keyword: keyword))
  }

  func waitForRequest() async {
    while requestedRequests.isEmpty {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForRequest(path: String, keyword: String? = nil, count: Int = 1) async {
    while requestedRequests.filter({ request in
      request.path == path && (keyword == nil || request.keyword == keyword)
    }).count < count {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func requestCount(path: String, keyword: String? = nil) -> Int {
    requestedRequests.filter { request in
      request.path == path && (keyword == nil || request.keyword == keyword)
    }.count
  }

  func waitForCancellation() async {
    while cancelledRequests.isEmpty {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForCancellation(path: String, keyword: String? = nil, count: Int = 1) async {
    while cancelledRequests.filter({ request in
      request.path == path && (keyword == nil || request.keyword == keyword)
    }).count < count {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  private func recordRequest(path: String, keyword: String) {
    requestedRequests.append(ResourceResultRecordedRequest(path: path, keyword: keyword))
  }

  private func waitUntilCancelled() async throws -> Never {
    while !Task.isCancelled {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw CancellationError()
  }
}

private final class ResourceResultViewModelURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = ResourceResultViewModelURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "resource-result-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = ResourceResultURLProtocolTaskContext(
      request: request,
      clientBox: ResourceResultURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = ResourceResultViewModelURLProtocol.makeLoadingTask(for: context)
  }

  override func stopLoading() {
    let requestToCancel = request
    Task {
      await ResourceResultViewModelURLProtocol.stub.recordCancellation(for: requestToCancel)
    }
    loadingTask?.cancel()
    loadingTask = nil
  }

  private static func makeLoadingTask(for context: ResourceResultURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await ResourceResultViewModelURLProtocol.stub.response(
          for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }
}

private struct ResourceResultHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private struct ResourceResultRecordedRequest: Equatable {
  let path: String
  let keyword: String
}

@MainActor
private func configureResourceResultSearchSession(_ service: APIService) {
  service.token = "resource-result-search-token"
  service.currentUser = Token(
    access_token: "resource-result-search-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": false,
      "search": true,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_name: "search-user",
    avatar: nil
  )
}

@MainActor
private func configureResourceResultSuperUserSearchSession(_ service: APIService) {
  service.token = "resource-result-super-search-token"
  service.currentUser = Token(
    access_token: "resource-result-super-search-token",
    token_type: "bearer",
    super_user: FlexibleBool(true),
    permissions: [
      "discovery": true,
      "search": true,
      "subscribe": true,
      "manage": true,
    ],
    user_name: "admin",
    avatar: nil
  )
}

@MainActor
private struct ResourceResultViewModelFilterSelectionSnapshot {
  let hardKey: String
  let softKey: String
  let hardValue: String?
  let softValue: String?

  static func selectHardRule(_ ruleId: String, baseURL: String)
    -> ResourceResultViewModelFilterSelectionSnapshot
  {
    let username =
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
      ?? UserDefaults.standard.string(forKey: "username")
      ?? "default"
    let hardKey = "selectedCustomFilterRuleId_\(baseURL)_\(username)"
    let softKey = "selectedSoftFilterRuleId_\(baseURL)_\(username)"
    let snapshot = ResourceResultViewModelFilterSelectionSnapshot(
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

private func resourceContextJSON(title: String) -> String {
  """
  {
    "torrent_info": {
      "site": 1,
      "site_name": "Test Site",
      "site_order": 1,
      "title": "\(title)",
      "description": "",
      "enclosure": "https://example.test/\(title)",
      "page_url": "https://example.test/\(title)",
      "size": 1024,
      "seeders": 10,
      "peers": 1,
      "pubdate": "2026-06-16 10:00:00",
      "uploadvolumefactor": 1.0,
      "downloadvolumefactor": 1.0,
      "pri_order": 1,
      "labels": [],
      "volume_factor": "1x"
    }
  }
  """
}

private final class ResourceResultURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: ResourceResultURLProtocolClientBox

  init(request: URLRequest, clientBox: ResourceResultURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class ResourceResultURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: ResourceResultHTTPStubResponse) {
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
