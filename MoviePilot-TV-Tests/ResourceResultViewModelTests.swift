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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    var viewModel: ResourceResultViewModel? = ResourceResultViewModel(keyword: "stale", apiService: service)
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "stale", apiService: service)
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSuperUserSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "fallback")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Fallback Result")],
      forKeyword: "fallback"
    )
    await ResourceResultViewModelURLProtocol.stub.setCustomFilterGate(ResourceResultAsyncGate())

    let viewModel = ResourceResultViewModel(keyword: "fallback", apiService: service)
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

  func testCustomFilterInvalidRuleShowsErrorAndDoesNotPublishResults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    let itemJSON = resourceContextJSON(title: "Filtered Result")
      .replacingOccurrences(of: "\n", with: "")
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"append\",\"items\":[\(itemJSON)]}\n\n"
        + "data: {\"type\":\"done\",\"text\":\"搜索完成\",\"items\":[]}\n\n",
      forKeyword: "invalid-rule"
    )
    // 规则内容非法（include 是无法编译的正则）→ 显式报错，不发布已积累的结果。
    await ResourceResultViewModelURLProtocol.stub.setCustomFilterRulesJSON(
      #"{"data":{"value":[{"id":"bad-regex","name":"Bad","include":["["]}]}}"#)
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSuperUserSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "bad-regex", apiService: service)
    defer { filterSnapshot.restore() }

    let viewModel = ResourceResultViewModel(keyword: "invalid-rule", apiService: service)
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertTrue(
      viewModel.results.isEmpty,
      "规则内容非法时不得发布未过滤的结果。"
    )
    XCTAssertEqual(viewModel.errorMessage, "自定义过滤规则无效：正则表达式「[」无法编译")
  }

  func testCustomFilterFetchNetworkFailurePassesThroughUnfiltered() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    let itemJSON = resourceContextJSON(title: "Unfiltered Result")
      .replacingOccurrences(of: "\n", with: "")
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"append\",\"items\":[\(itemJSON)]}\n\n"
        + "data: {\"type\":\"done\",\"text\":\"搜索完成\",\"items\":[]}\n\n",
      forKeyword: "netdown"
    )
    // 拉取规则网络失败 → 与旧行为一致放行不过滤，不阻断结果。
    await ResourceResultViewModelURLProtocol.stub.setCustomFilterRulesFailure()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSuperUserSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    let viewModel = ResourceResultViewModel(keyword: "netdown", apiService: service)
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.results.count, 1)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testSearchCanRestartAfterDisappearCancellation() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "repeat", apiService: service)
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "tab-switch", apiService: service)
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
    XCTAssertTrue(
      viewModel.isLoading,
      "页面退场只应取消请求，Pop 动画期间必须保留原来的加载画面"
    )

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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let fallbackGate = ResourceResultAsyncGate()
    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "session-change")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Stale Result")],
      forKeyword: "session-change"
    )
    await ResourceResultViewModelURLProtocol.stub.setFallbackGate(
      fallbackGate, forKeyword: "session-change")

    let viewModel = ResourceResultViewModel(keyword: "session-change", apiService: service)
    defer { viewModel.cancelSearch() }
    await viewModel.search()

    try await withTimeout("resource search to enter fallback request") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "session-change")
    }

    service.currentUserForTesting = Token(
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

  func testScheduledSearchDoesNotStartAfterAccountSwitch() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    let accountA = Token(
      access_token: "resource-account-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.search.rawValue: true],
      user_id: 301,
      user_name: "resource-account-a",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://resource-result-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let viewModel = ResourceResultViewModel(keyword: "scheduled-switch", apiService: service)

    await viewModel.search()
    let accountB = Token(
      access_token: "resource-account-b",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.search.rawValue: true],
      user_id: 302,
      user_name: "resource-account-b",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://resource-result-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    for _ in 0..<50 { await Task.yield() }

    let streamCount = await ResourceResultViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title/stream",
      keyword: "scheduled-switch"
    )
    let fallbackCount = await ResourceResultViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title",
      keyword: "scheduled-switch"
    )
    XCTAssertEqual(streamCount, 0)
    XCTAssertEqual(fallbackCount, 0)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testSessionChangeDoesNotPublishStaleFallbackError() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let fallbackGate = ResourceResultAsyncGate()
    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "stale-error")
    await ResourceResultViewModelURLProtocol.stub.setFallbackFailure(forKeyword: "stale-error")
    await ResourceResultViewModelURLProtocol.stub.setFallbackGate(
      fallbackGate, forKeyword: "stale-error")

    let viewModel = ResourceResultViewModel(keyword: "stale-error", apiService: service)
    defer { viewModel.cancelSearch() }
    await viewModel.search()

    try await withTimeout("resource search to enter failing fallback request") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title", keyword: "stale-error")
    }

    service.currentUserForTesting = Token(
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)
    let filterSnapshot = ResourceResultViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    await ResourceResultViewModelURLProtocol.stub.setStreamFailure(forKeyword: "finished")
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Finished Result")],
      forKeyword: "finished"
    )

    let viewModel = ResourceResultViewModel(keyword: "finished", apiService: service)
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
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
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "malformed", apiService: service)
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
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"error\",\"message\":\"Search failed\",\"message_i18n\":\"搜索失败\"}\n\n",
      forKeyword: "business-error"
    )
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "business-error", apiService: service)
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

  func testResourceSearchErrorEventDoesNotPublishAccumulatedResults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    let itemJSON = resourceContextJSON(title: "Partial Result")
      .replacingOccurrences(of: "\n", with: "")
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"append\",\"items\":[\(itemJSON)]}\n\n"
        + "data: {\"type\":\"error\",\"success\":false,\"message\":\"站点搜索失败\"}\n\n",
      forKeyword: "error-after-partial"
    )
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "error-after-partial", apiService: service)
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.errorMessage, "站点搜索失败")
    XCTAssertTrue(
      viewModel.results.isEmpty,
      "An error event must not publish partially accumulated results as a successful search."
    )
  }

  func testResourceSearchEOFWithoutDoneUsesFallbackWithoutPublishingPartialResult() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ResourceResultViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    let itemJSON = resourceContextJSON(title: "Partial Result")
      .replacingOccurrences(of: "\n", with: "")
    await ResourceResultViewModelURLProtocol.stub.setStreamBody(
      "data: {\"type\":\"append\",\"items\":[\(itemJSON)]}\n\n",
      forKeyword: "cut"
    )
    await ResourceResultViewModelURLProtocol.stub.setFallbackResults(
      [resourceContextJSON(title: "Fallback Result")],
      forKeyword: "cut"
    )
    service.baseURLForTesting = "http://resource-result-tests.local"
    configureResourceResultSearchSession(service)

    let viewModel = ResourceResultViewModel(keyword: "cut", apiService: service)
    await viewModel.search()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.results.first?.torrent_info?.title, "Fallback Result")
    let fallbackRequestCount = await ResourceResultViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title",
      keyword: "cut"
    )
    XCTAssertEqual(fallbackRequestCount, 1)
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
    service.replaceSessionForTesting(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser
    )

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
  private var customFilterRulesJSON: String?
  private var customFilterRulesFailure = false

  func reset() {
    requestedRequests.removeAll()
    cancelledRequests.removeAll()
    streamFailureKeywords.removeAll()
    streamBodiesByKeyword.removeAll()
    fallbackResultsByKeyword.removeAll()
    fallbackFailureKeywords.removeAll()
    fallbackGatesByKeyword.removeAll()
    customFilterGate = nil
    customFilterRulesJSON = nil
    customFilterRulesFailure = false
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

  /// 覆盖 CustomFilterRules 返回的规则列表 JSON。
  func setCustomFilterRulesJSON(_ json: String) {
    customFilterRulesJSON = json
  }

  /// 让 CustomFilterRules 拉取以网络错误失败。
  func setCustomFilterRulesFailure() {
    customFilterRulesFailure = true
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
      if customFilterRulesFailure {
        throw URLError(.notConnectedToInternet)
      }
      return ResourceResultHTTPStubResponse(
        statusCode: 200,
        data: Data((customFilterRulesJSON ?? #"{"data":{"value":[{"id":"allow-all","name":"Allow All"}]}}"#).utf8)
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
  service.tokenForTesting = "resource-result-search-token"
  service.currentUserForTesting = Token(
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
    user_id: 201,
    user_name: "search-user",
    avatar: nil
  )
}

@MainActor
private func configureResourceResultSuperUserSearchSession(_ service: APIService) {
  service.tokenForTesting = "resource-result-super-search-token"
  service.currentUserForTesting = Token(
    access_token: "resource-result-super-search-token",
    token_type: "bearer",
    super_user: FlexibleBool(true),
    permissions: [
      "discovery": true,
      "search": true,
      "subscribe": true,
      "manage": true,
    ],
    user_id: 202,
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

  static func selectHardRule(_ ruleId: String, apiService: APIService)
    -> ResourceResultViewModelFilterSelectionSnapshot
  {
    let profileKey = apiService.profileKey ?? "missing-profile"
    let hardKey = "selectedCustomFilterRuleId_\(profileKey)"
    let softKey = "selectedSoftFilterRuleId_\(profileKey)"
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
