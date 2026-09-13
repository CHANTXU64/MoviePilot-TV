import Combine
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

/// 资源搜索流的终止形态：done（成功收尾）/ error（业务失败）/ eof（无终止断开）。
private enum SearchStreamTermination {
  case done
  case error
  case eof
}

@MainActor
private func drainSearchDefaultsNotifications() async {
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async {
      continuation.resume()
    }
  }
}

private func restoreSearchDefaultsArray(_ value: [Any]?, forKey key: String) {
  if let value {
    UserDefaults.standard.set(value, forKey: key)
  } else {
    UserDefaults.standard.removeObject(forKey: key)
  }
}

private func restoreSearchDefaultsString(_ value: String?, forKey key: String) {
  if let value {
    UserDefaults.standard.set(value, forKey: key)
  } else {
    UserDefaults.standard.removeObject(forKey: key)
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
  @MainActor
  func testSearchViewModelForwardsSiteFilterChangesToParent() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }

    let viewModel = SearchViewModel()
    let changeReceived = expectation(description: "父 VM 收到 siteFilter 变化")
    let cancellable = viewModel.objectWillChange.sink { _ in
      changeReceived.fulfill()
    }
    defer { cancellable.cancel() }

    viewModel.siteFilter.selectedSites = [1]

    wait(for: [changeReceived], timeout: 1)
  }

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

  func testNewUnifiedSearchClearsPreviousBestResultsWhileInFlight() async throws {
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
    viewModel.query = "old"
    await viewModel.autoSearch()

    XCTAssertFalse(viewModel.isLoading)
    let oldResultTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item {
        return media.title
      }
      return nil
    }
    XCTAssertEqual(oldResultTitles, ["Old Result"])

    let newSearchGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(newSearchGate, forQuery: "new")
    viewModel.query = "new"
    let newSearchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { newSearchTask.cancel() }

    try await withTimeout("new unified search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "new")
    }

    XCTAssertTrue(
      viewModel.bestResults.isEmpty,
      "A new unified search must clear previous best results while it is in flight."
    )

    await newSearchGate.open()
    try await withTimeout("new unified search to finish") {
      await newSearchTask.value
    }

    XCTAssertFalse(viewModel.isLoading)
    let newResultTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item {
        return media.title
      }
      return nil
    }
    XCTAssertEqual(newResultTitles, ["New Result"])
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
      path: "/api/v1/search/media/154587/stream"
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

  func testPersonPaginatorRefreshClearsSeenIdentitySet() async throws {
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
    viewModel.query = "person-reset"
    await viewModel.autoSearch()

    let paginator = try XCTUnwrap(viewModel.personPaginator)
    XCTAssertEqual(paginator.items.map(\.id), ["douban-7", "themoviedb-7"])

    await paginator.refresh()

    XCTAssertEqual(paginator.items.map(\.id), ["douban-7", "themoviedb-7"])
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

  func testSettingsHotUpdateSearchDefaultsWithoutOverwritingPageOverrides() async throws {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "http://search-defaults.local"
    configureSearchPermissionSession(service)
    let profileKey = try XCTUnwrap(service.profileKey)
    let sitesKey = "defaultSearchSites_\(profileKey)"
    let sourceKey = "defaultMediaSearchSource_\(profileKey)"
    let previousSites = UserDefaults.standard.array(forKey: sitesKey)
    let previousSource = UserDefaults.standard.string(forKey: sourceKey)
    defer {
      restoreSearchDefaultsArray(previousSites, forKey: sitesKey)
      restoreSearchDefaultsString(previousSource, forKey: sourceKey)
    }

    UserDefaults.standard.set([1], forKey: sitesKey)
    UserDefaults.standard.set(MediaSearchSource.douban.rawValue, forKey: sourceKey)
    let viewModel = SearchViewModel(apiService: service)
    let settings = SystemViewModel(apiService: service)

    XCTAssertEqual(viewModel.siteFilter.selectedSites, [1])
    XCTAssertEqual(viewModel.mediaSearchSource, .douban)

    settings.defaultSearchSites = [2]
    settings.defaultMediaSearchSource = .anilist
    await drainSearchDefaultsNotifications()

    XCTAssertEqual(viewModel.siteFilter.selectedSites, [2])
    XCTAssertEqual(viewModel.mediaSearchSource, .anilist)

    NotificationCenter.default.post(
      name: .searchDefaultsDidChange,
      object: SearchDefaultsChange(
        profileKey: "another-profile",
        defaultSearchSites: [8],
        defaultMediaSearchSource: .bangumi
      )
    )
    await drainSearchDefaultsNotifications()

    XCTAssertEqual(viewModel.siteFilter.selectedSites, [2])
    XCTAssertEqual(viewModel.mediaSearchSource, .anilist)

    viewModel.siteFilter.selectedSites = [9]
    viewModel.mediaSearchSource = .themoviedb
    settings.defaultSearchSites = [9]
    settings.defaultMediaSearchSource = .themoviedb
    await drainSearchDefaultsNotifications()

    settings.defaultSearchSites = [3]
    settings.defaultMediaSearchSource = .bangumi
    await drainSearchDefaultsNotifications()

    XCTAssertEqual(viewModel.siteFilter.selectedSites, [9])
    XCTAssertEqual(viewModel.mediaSearchSource, .themoviedb)
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
    // old 搜索以 done 成功收尾，确保进入过滤阶段后验证其取消。
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "old")

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

  func testNewResourceSearchClearsPreviousResultsImmediately() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // 第一次搜索以 done 成功收尾，确保发布旧结果。
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "old")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "old"

    await viewModel.autoSearch()
    let firstDeadline = Date().addingTimeInterval(2)
    while viewModel.resourceResults.isEmpty && Date() < firstDeadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(
      viewModel.resourceResults.isEmpty,
      "First search must publish results before the second search starts."
    )

    // 第二次搜索：响应被 gate 卡住期间，旧结果必须已被立即清空。
    let gate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(gate, forQuery: "new")
    // 第二次搜索以 done 成功收尾，确保 gate 打开后发布自己的结果。
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "new")
    viewModel.query = "new"
    await viewModel.autoSearch()

    XCTAssertTrue(
      viewModel.resourceResults.isEmpty,
      "A new resource search must clear previous results before its own response arrives."
    )

    await gate.open()
    let secondDeadline = Date().addingTimeInterval(2)
    while viewModel.resourceResults.isEmpty && Date() < secondDeadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(
      viewModel.resourceResults.isEmpty,
      "Second search must publish its own results after the gate opens."
    )
  }

  func testResourceSearchErrorEventDoesNotPublishPartialResults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // error 事件 = 整次搜索失败，不得发布已积累的部分结果。
    await SearchViewModelURLProtocol.stub.setStreamTermination(.error, forQuery: "broken")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "broken"

    await viewModel.autoSearch()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.resourceErrorMessage, "站点搜索失败")
    XCTAssertTrue(
      viewModel.resourceResults.isEmpty,
      "An error event must not publish partially accumulated results as a successful search."
    )
  }

  func testResourceSearchEOFWithoutDoneUsesFallbackInsteadOfPartialResults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // EOF 无 done = 连接异常；丢弃流中部分结果，改走普通搜索端点。
    await SearchViewModelURLProtocol.stub.setStreamTermination(.eof, forQuery: "cut")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "cut"

    await viewModel.autoSearch()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.resourceErrorMessage)
    XCTAssertEqual(viewModel.resourceResults.first?.torrent_info?.title, "Fallback Resource")
    let fallbackRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/search/title")
    XCTAssertEqual(fallbackRequestCount, 1)
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

  func testCustomFilterMissingRuleIdExcludesAllLikeBackend() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // 所选规则 ID 不存在（后端 rule_set.get 为空返回 False）→ 全部排除。
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectHardRule(
      "missing-id", apiService: service)
    defer { filterSnapshot.restore() }

    let contexts = [
      Context(
        torrent_info: TorrentInfo(
          site: 1,
          site_name: "Test Site",
          site_order: 1,
          title: "Any Result",
          description: "",
          enclosure: "https://example.test/any",
          page_url: "https://example.test/any",
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
      caller: "missing-rule-test"
    )

    XCTAssertTrue(
      filtered.isEmpty,
      "与后端 __match_rule 一致：所选规则 ID 不存在时全部排除，而非静默放行。"
    )
  }

  func testCustomFilterInvalidRuleShowsErrorAndDoesNotPublishResults() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // 规则内容非法（include 是无法编译的正则）→ 显式报错，不发布已积累的结果。
    await SearchViewModelURLProtocol.stub.setCustomFilterRulesJSON(
      #"{"data":{"value":[{"id":"bad-regex","name":"Bad","include":["["]}]}}"#)
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "invalid")
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectHardRule(
      "bad-regex", apiService: service)
    defer { filterSnapshot.restore() }

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "invalid"

    await viewModel.autoSearch()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertTrue(
      viewModel.resourceResults.isEmpty,
      "规则内容非法时不得发布未过滤的结果。"
    )
    XCTAssertEqual(
      viewModel.resourceErrorMessage,
      "自定义过滤规则无效：正则表达式「[」无法编译"
    )
  }

  func testCustomFilterFetchNetworkFailurePassesThroughUnfiltered() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // 拉取规则网络失败 → 与旧行为一致放行不过滤，不阻断结果。
    await SearchViewModelURLProtocol.stub.setCustomFilterRulesFailure()
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "netdown")
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectHardRule(
      "allow-all", apiService: service)
    defer { filterSnapshot.restore() }

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "netdown"

    await viewModel.autoSearch()
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isLoading && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.resourceResults.count, 1)
    XCTAssertNil(viewModel.resourceErrorMessage)
  }

  func testCustomFilterMissingSoftRuleIdGreysAllLikeBackend() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    // 所选软规则 ID 不存在（后端 rule_set.get 为空返回 False）→ 全部置灰。
    let filterSnapshot = SearchViewModelFilterSelectionSnapshot.selectSoftRule(
      "missing-id", apiService: service)
    defer { filterSnapshot.restore() }

    let contexts = [
      Context(
        torrent_info: TorrentInfo(
          site: 1,
          site_name: "Test Site",
          site_order: 1,
          title: "First Result",
          description: "",
          enclosure: "https://example.test/first",
          page_url: "https://example.test/first",
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
      ),
      Context(
        torrent_info: TorrentInfo(
          site: 1,
          site_name: "Test Site",
          site_order: 1,
          title: "Second Result",
          description: "",
          enclosure: "https://example.test/second",
          page_url: "https://example.test/second",
          size: 2048,
          seeders: 20,
          peers: 2,
          pubdate: "2026-06-16 10:00:00",
          uploadvolumefactor: 1.0,
          downloadvolumefactor: 1.0,
          pri_order: 2,
          labels: [],
          volume_factor: "1x"
        )
      ),
    ]

    let filtered = try await CustomFilterService.applyHardAndSoftFilter(
      to: contexts,
      using: service,
      caller: "missing-soft-rule-test"
    )

    XCTAssertEqual(filtered.count, 2)
    XCTAssertTrue(
      filtered.allSatisfy(\.isFilteredOut),
      "与后端 __match_rule 一致：所选软规则 ID 不存在时全部置灰。"
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

  // MARK: - F-225：可选订阅分享慢请求不得阻塞核心结果揭示

  @MainActor
  func testSlowSubscriptionShareRevealsCoreThenOnlyAddsShareRowWhenItLateArrives() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryAndSubscribePermissionSession(service)

    let shareGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(shareGate, forPath: "/api/v1/subscribe/shares")
    await SearchViewModelURLProtocol.stub.setShareResults(shareRowsJSON(), forQuery: "old")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "old"
    // 把超时窗口调短，稳定覆盖"分享慢于超时、核心先收口"的路径。
    viewModel.subscriptionShareTimeoutNanoseconds = 100_000_000

    let searchTask = Task { @MainActor in await viewModel.autoSearch() }
    defer { searchTask.cancel() }

    try await withTimeout("subscription-share request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(path: "/api/v1/subscribe/shares")
    }

    // 分享请求被 gate 卡住；核心分类已返回，超时窗口一到搜索应先行收口。
    try await withTimeout("core reveal despite slow share", seconds: 3) {
      await searchTask.value
    }
    XCTAssertFalse(
      viewModel.isLoading,
      "Core results must end the full-page loader even when the optional share request exceeds the timeout."
    )

    let revealTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertTrue(
      revealTitles.contains("Old Result"),
      "Core media results should be revealed while the optional share row is still pending."
    )
    XCTAssertFalse(
      revealTitles.contains("Shared Old Pick"),
      "A share that has not returned must not be folded into the best-results row."
    )
    XCTAssertTrue(
      viewModel.subscriptionSharePaginator?.items.isEmpty ?? true,
      "The pending subscription-share row should stay empty until the request actually returns."
    )

    // 迟到分享放行：只补"订阅分享"行，不重开已算好的最佳行。
    await shareGate.open()
    let shareArrivalDeadline = Date().addingTimeInterval(3)
    while (viewModel.subscriptionSharePaginator?.items.isEmpty ?? true)
      && Date() < shareArrivalDeadline
    {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    let shareRowTitles = viewModel.subscriptionSharePaginator?.items.compactMap { $0.title } ?? []
    XCTAssertTrue(
      shareRowTitles.contains("Shared Old Pick"),
      "A late subscription share should appear as its own row once it arrives."
    )

    let settledTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertFalse(
      settledTitles.contains("Shared Old Pick"),
      "A late-arriving share must not re-open the already-computed best-results row."
    )
  }

  @MainActor
  func testSubscriptionShareReturningWithinTimeoutStillPopulatesItsRow() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryAndSubscribePermissionSession(service)

    await SearchViewModelURLProtocol.stub.setShareResults(shareRowsJSON(), forQuery: "old")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "old"

    let searchTask = Task { @MainActor in await viewModel.autoSearch() }
    defer { searchTask.cancel() }
    try await withTimeout("search to finish with a fast share", seconds: 3) {
      await searchTask.value
    }

    XCTAssertFalse(viewModel.isLoading)
    let shareRowTitles = viewModel.subscriptionSharePaginator?.items.compactMap { $0.title } ?? []
    XCTAssertTrue(
      shareRowTitles.contains("Shared Old Pick"),
      "A share returning within the timeout window keeps its existing row behavior."
    )
  }

  @MainActor
  func testStaleSubscriptionShareCanceledByNewSearchCannotLeakOldItems() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryAndSubscribePermissionSession(service)

    let shareGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(shareGate, forPath: "/api/v1/subscribe/shares")
    await SearchViewModelURLProtocol.stub.setShareResults(shareRowsJSON(), forQuery: "old")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "old"
    viewModel.subscriptionShareTimeoutNanoseconds = 100_000_000

    let firstTask = Task { @MainActor in await viewModel.autoSearch() }
    defer { firstTask.cancel() }
    try await withTimeout("first subscription-share request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(path: "/api/v1/subscribe/shares")
    }
    try await withTimeout("first search core reveal", seconds: 3) {
      await firstTask.value
    }

    // 分享仍在途：发起换词搜索，旧 paginator 会被 reset 取消，迟到旧分享不得泄漏。
    viewModel.query = "new"
    let secondTask = Task { @MainActor in await viewModel.autoSearch() }
    defer { secondTask.cancel() }
    try await withTimeout("second search to finish", seconds: 3) {
      await secondTask.value
    }
    XCTAssertFalse(viewModel.isLoading)

    // 旧的"订阅分享"请求应在新搜索 reset 时被取消。
    try await withTimeout("stale old-share request to be cancelled", seconds: 3) {
      await SearchViewModelURLProtocol.stub.waitForCancellation(
        path: "/api/v1/subscribe/shares",
        query: "old"
      )
    }

    // 放行旧分享也无济于事：当前搜索的分享行不得出现旧标题。
    await shareGate.open()
    let currentShareTitles = viewModel.subscriptionSharePaginator?.items.compactMap { $0.title } ?? []
    XCTAssertFalse(
      currentShareTitles.contains("Shared Old Pick"),
      "A share cancelled by a newer search must not leak its items into the current result."
    )
  }
}

private func shareRowsJSON() -> String {
  """
  [
    {"id":501,"share_title":"Shared Old Pick","name":"Shared Old Pick","poster":"/shared-old.jpg","type":"电影","year":"2026"}
  ]
  """
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
  private var customFilterRulesJSON: String?
  private var customFilterRulesFailure = false
  private var mediaResultsByQuery: [String: String] = [:]
  private var gatesByPath: [String: SearchAsyncGate] = [:]
  private var shareResultsByQuery: [String: String] = [:]
  private var personResultsByQuery: [String: String] = [:]
  private var requestedRequests: [SearchRecordedRequest] = []
  private var cancelledRequests: [SearchRecordedRequest] = []
  private var streamTerminations: [String: SearchStreamTermination] = [:]

  func reset() {
    gatesByQuery.removeAll()
    customFilterGate = nil
    customFilterRulesJSON = nil
    customFilterRulesFailure = false
    mediaResultsByQuery.removeAll()
    gatesByPath.removeAll()
    shareResultsByQuery.removeAll()
    personResultsByQuery.removeAll()
    requestedRequests.removeAll()
    cancelledRequests.removeAll()
    streamTerminations.removeAll()
  }

  func setGate(_ gate: SearchAsyncGate, forQuery query: String) {
    gatesByQuery[query] = gate
  }

  /// 只卡住指定 path 的请求（如仅卡"订阅分享"，不波及同 query 的核心分类请求）。
  func setGate(_ gate: SearchAsyncGate, forPath path: String) {
    gatesByPath[path] = gate
  }

  func setCustomFilterGate(_ gate: SearchAsyncGate) {
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

  /// 覆盖 /media/search 返回的媒体 JSON 数组（按 title 参数匹配）。
  func setMediaResults(_ json: String, forQuery query: String) {
    mediaResultsByQuery[query] = json
  }

  /// 覆盖“订阅分享”接口返回的分享 JSON 数组（按名称参数匹配）。
  func setShareResults(_ json: String, forQuery query: String) {
    shareResultsByQuery[query] = json
  }

  /// 覆盖 `/media/search?type=person` 返回的人物 JSON 数组（按 title 参数匹配）。
  func setPersonResults(_ json: String, forQuery query: String) {
    personResultsByQuery[query] = json
  }

  /// 配置资源搜索流的终止形态：done（成功收尾）/ error（业务失败）/ eof（无终止断开）。
  func setStreamTermination(_ termination: SearchStreamTermination, forQuery query: String) {
    streamTerminations[query] = termination
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
      source: queryItems.first(where: { $0.name == "media_source" })?.value
        ?? queryItems.first(where: { $0.name == "source" })?.value
    )

    if components.path == "/api/v1/system/setting/CustomFilterRules",
      let gate = customFilterGate
    {
      await gate.wait()
    } else if let gate = gatesByPath[components.path] {
      await gate.wait()
    } else if let gate = gatesByQuery[query] {
      await gate.wait()
    }

    if components.path == "/api/v1/system/setting/CustomFilterRules",
      customFilterRulesFailure
    {
      throw URLError(.notConnectedToInternet)
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
        source: queryItems.first(where: { $0.name == "media_source" })?.value
        ?? queryItems.first(where: { $0.name == "source" })?.value
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
      return resourceSearchStreamData(
        title: query == "new" ? "New Resource" : "Old Resource",
        termination: streamTerminations[query] ?? .eof
      )
    }
    if path == "/api/v1/search/title" {
      return Data("[\(resourceContextJSON(title: "Fallback Resource"))]".utf8)
    }
    if path == "/api/v1/system/setting/CustomFilterRules" {
      if let customFilterRulesJSON {
        return Data(customFilterRulesJSON.utf8)
      }
      return Data(
        """
        {"data":{"value":[{"id":"allow-all","name":"Allow All"}]}}
        """.utf8)
    }

    if path == "/api/v1/subscribe/shares" {
      if let shareResults = shareResultsByQuery[query] {
        return Data(shareResults.utf8)
      }
      return Data("[]".utf8)
    }

    let type = queryItems.first(where: { $0.name == "type" })?.value
    let page = queryItems.first(where: { $0.name == "page" })?.value ?? "1"
    if query == "person-reset", type == "person", page == "1" {
      return Data(
        """
        [
          {"source":"douban","id":7,"name":"豆瓣人物"},
          {"source":"douban","id":7,"name":"豆瓣重复人物"},
          {"source":"themoviedb","id":7,"name":"TMDB人物"}
        ]
        """.utf8)
    }
    if type == "person", let personResults = personResultsByQuery[query] {
      return Data(personResults.utf8)
    }
    guard type == nil || type == "media" else {
      return Data("[]".utf8)
    }

    guard page == "1" else {
      return Data("[]".utf8)
    }

    let id = query == "new" ? 1002 : 1001
    let title = query == "new" ? "New Result" : "Old Result"
    if let custom = mediaResultsByQuery[query] {
      return Data(custom.utf8)
    }
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

  private func resourceSearchStreamData(
    title: String,
    termination: SearchStreamTermination
  ) -> Data {
    let append =
      "data: {\"type\":\"append\",\"text\":\"Searching\",\"value\":50,\"items\":["
      + resourceContextJSON(title: title)
      + "]}\n\n"
    switch termination {
    case .done:
      return Data(
        (append + "data: {\"type\":\"done\",\"text\":\"搜索完成\",\"items\":[]}\n\n").utf8
      )
    case .error:
      return Data(
        (
          append
            + "data: {\"type\":\"error\",\"success\":false,\"message\":\"站点搜索失败\"}\n\n"
        ).utf8
      )
    case .eof:
      return Data(append.utf8)
    }
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
private func configureDiscoveryAndSubscribePermissionSession(_ service: APIService) {
  service.tokenForTesting = "discovery-subscribe-permission-token"
  service.currentUserForTesting = Token(
    access_token: "discovery-subscribe-permission-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": true,
      "search": false,
      "subscribe": true,
      "manage": false,
      "admin": false,
    ],
    user_id: 304,
    user_name: "discovery-subscribe-user",
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

  static func selectSoftRule(_ ruleId: String, apiService: APIService)
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
    UserDefaults.standard.removeObject(forKey: hardKey)
    UserDefaults.standard.set(ruleId, forKey: softKey)
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

// MARK: - 模糊匹配分档（最佳结果排序）

extension SearchViewModelTests {
  func testFuzzyMatchScoreBandsNeverOverlapAcrossTitles() {
    // 完全相等高于一切
    XCTAssertEqual(fuzzyMatchScore(text: "The Movie", query: "the movie"), 1000)

    // 超长标题的前缀匹配仍高于短标题的包含匹配（长度罚分不再打穿类别）
    let longPrefixTitle = "The Target " + String(repeating: "x", count: 600)
    XCTAssertEqual(fuzzyMatchScore(text: longPrefixTitle, query: "the target"), 600)
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: longPrefixTitle, query: "the target"),
      fuzzyMatchScore(text: "A short target", query: "target")
    )

    // 超长标题的包含匹配仍高于任意顺序匹配
    let longContainTitle = String(repeating: "x", count: 200) + "target"
    XCTAssertEqual(fuzzyMatchScore(text: longContainTitle, query: "target"), 300)
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: longContainTitle, query: "target"),
      fuzzyMatchScore(text: "Hamilton", query: "hml")
    )

    // 顺序匹配不低于档位下限，不匹配固定为 -1
    XCTAssertGreaterThanOrEqual(fuzzyMatchScore(text: "Hamilton", query: "hml"), 100)
    XCTAssertEqual(fuzzyMatchScore(text: "Nobody", query: "zzz"), -1)
  }

  func testFuzzyMatchScoreSubsequencePrefersWordStartAndConsecutive() {
    // 词首匹配高于非词首匹配（query 非连续子串，走顺序匹配档）
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: "the lord", query: "lrd"),
      fuzzyMatchScore(text: "belorded", query: "lrd")
    )
    // 部分连续匹配高于全程分散（"ab" 紧邻 vs 每字符间隔）
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: "xabxc", query: "abc"),
      fuzzyMatchScore(text: "xaxbxc", query: "abc")
    )
  }

  func testFuzzyMatchScoreChineseTitles() {
    // 完全相等最高
    XCTAssertEqual(fuzzyMatchScore(text: "流浪地球", query: "流浪地球"), 1000)
    // 前缀匹配高于包含匹配
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: "流浪地球 2", query: "流浪地球"),
      fuzzyMatchScore(text: "我喜欢的流浪地球", query: "流浪地球")
    )
    // 中文标题无词首加分时，紧邻匹配仍高于间隔更远的匹配
    XCTAssertGreaterThan(
      fuzzyMatchScore(text: "流浪地球", query: "流地球"),
      fuzzyMatchScore(text: "流啊浪啊地球", query: "流地球")
    )
    // 不匹配固定为 -1
    XCTAssertEqual(fuzzyMatchScore(text: "三体", query: "流浪地球"), -1)
  }

  func testPopularityBoostNormalizesPerSource() {
    // TMDB 热度指数：log10 基数 3，封顶 149
    XCTAssertEqual(popularityBoost(source: "themoviedb", popularity: 0.6), 10)
    XCTAssertEqual(popularityBoost(source: "themoviedb", popularity: 3), 30)
    XCTAssertEqual(popularityBoost(source: "themoviedb", popularity: 1900), 149)
    XCTAssertEqual(popularityBoost(source: "themoviedb", popularity: 0), 0)
    // AniList 收藏数：log10 基数 6，避免数十万收藏数全部顶满
    XCTAssertEqual(popularityBoost(source: "anilist", popularity: 4732), 91)
    XCTAssertEqual(popularityBoost(source: "anilist", popularity: 742091), 146)
    // 无热度来源与非法值不加分
    XCTAssertEqual(popularityBoost(source: "douban", popularity: 8), 0)
    XCTAssertEqual(popularityBoost(source: "bangumi", popularity: 8), 0)
    XCTAssertEqual(popularityBoost(source: nil, popularity: 8), 0)
  }

  func testBestResultsBoostedByPopularityWithinSingleSource() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    // 同来源（TMDB）：B 是长标题包含匹配（分低但超热），A 是短标题包含匹配（分高但冷门）。
    // 加权后 B 的热度加分应使其反超 A。
    let longTitle = String(repeating: "x", count: 250) + "abc"
    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 2001, "source": "themoviedb", "title": "xxabcxxxx", "type": "电影", "year": "2026", "poster_path": "/a.jpg", "popularity": 0.5},
        {"tmdb_id": 2002, "source": "themoviedb", "title": "\(longTitle)", "type": "电影", "year": "2026", "poster_path": "/b.jpg", "popularity": 500}
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "abc"
    await viewModel.autoSearch()

    XCTAssertFalse(viewModel.isLoading)
    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, [longTitle, "xxabcxxxx"])
  }

  /// F-055：人物最佳结果的准入必须与卡片渲染使用同一套图片判据。
  ///
  /// 这里刻意构造「三个条件同时成立」的最坏情形：查询词 `abc` 与人物名 `zzz` 完全不匹配
  /// （`maxS == -1 < 50`）且 douban 热度不加分（`pop < 1`）。旧准入读的是 TMDB 专属
  /// `profile_path`，会把「有可渲染豆瓣头像但无 profile_path」的人物当成无图低质结果排除出
  /// 最佳结果，而同一人仍出现在下方人物行（卡片用 source-aware 判定能渲染出图）。
  /// 生产环境实际触发较弱（豆瓣来源通常标题匹配分很高，`maxS < 50` 不成立），
  /// 此例固化的是判据本身而非频率。
  func testBestResultsAdmitPersonWithSourceAwareAvatarButNoTMDBProfilePath() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    service.useImageCache = false
    configureDiscoveryPermissionSession(service)

    // 媒体/合集侧清空，确保最佳结果只由人物决定。
    await SearchViewModelURLProtocol.stub.setMediaResults("[]", forQuery: "abc")
    await SearchViewModelURLProtocol.stub.setPersonResults(
      """
      [
        {
          "source": "douban",
          "id": 7,
          "name": "zzz",
          "profile_path": null,
          "avatar": "https://img1.doubanio.com/view/personage/s/public/abc123.jpg"
        }
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "abc"
    await viewModel.autoSearch()

    XCTAssertFalse(viewModel.isLoading)
    let personNames = viewModel.bestResults.compactMap { item -> String? in
      if case .person(let person) = item { return person.name }
      return nil
    }
    XCTAssertEqual(personNames, ["zzz"], "有可渲染头像的人物不应因缺少 TMDB profile_path 被排除")
  }

  // MARK: - F-044 搜索人物职位翻译

  /// 中文界面下，人物行副标题不得显示 canonical 英文 `job`。
  func testSearchPersonJobIsTranslatedForPersonRow() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let savedLanguage = TranslationHelper.currentLanguage
    TranslationHelper.currentLanguage = .zhHans
    defer { TranslationHelper.currentLanguage = savedLanguage }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setPersonResults(
      """
      [{ "source": "themoviedb", "id": 11, "name": "张三", "job": "Director" }]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "abc"
    await viewModel.autoSearch()

    // 详情页的同一个人经 `StaffManager.processCrew` 后就是「导演」，
    // 两个界面对同一职位必须给出一致文案。
    XCTAssertEqual(viewModel.personPaginator?.items.map(\.job), ["导演"])
  }

  /// 最佳结果卡片副标题与人物行同源，同样不得漏翻。
  func testSearchPersonJobIsTranslatedForBestResultSubtitle() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let savedLanguage = TranslationHelper.currentLanguage
    TranslationHelper.currentLanguage = .zhHans
    defer { TranslationHelper.currentLanguage = savedLanguage }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    service.useImageCache = false
    configureDiscoveryPermissionSession(service)

    // 媒体侧清空，确保最佳结果只由人物决定。头像用于通过最佳结果准入（F-055 的判据）。
    await SearchViewModelURLProtocol.stub.setMediaResults("[]", forQuery: "abc")
    await SearchViewModelURLProtocol.stub.setPersonResults(
      """
      [
        {
          "source": "douban", "id": 12, "name": "zzz", "job": "Director",
          "profile_path": null,
          "avatar": "https://img1.doubanio.com/view/personage/s/public/abc123.jpg"
        }
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "abc"
    await viewModel.autoSearch()

    let bestPersonJobs = viewModel.bestResults.compactMap { item -> String? in
      if case .person(let person) = item { return person.job }
      return nil
    }
    XCTAssertEqual(bestPersonJobs, ["导演"])
  }

  /// 阴性对照：已翻译值再次经过投影必须原样保留，不能叠加成「导演/导演」。
  func testSearchPersonJobProjectionIsIdempotentForTranslatedValue() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let savedLanguage = TranslationHelper.currentLanguage
    TranslationHelper.currentLanguage = .zhHans
    defer { TranslationHelper.currentLanguage = savedLanguage }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setPersonResults(
      """
      [{ "source": "douban", "id": 13, "name": "李四", "job": "导演", "character": "Neo" }]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "abc"
    await viewModel.autoSearch()

    XCTAssertEqual(viewModel.personPaginator?.items.map(\.job), ["导演"])
  }

  /// 阴性对照：多职位按 "/" 逐项翻译，且没有 job 的人物不被凭空造出职位、character 原样保留。
  func testSearchPersonJobProjectionHandlesMultiJobAndMissingJob() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let savedLanguage = TranslationHelper.currentLanguage
    TranslationHelper.currentLanguage = .zhHans
    defer { TranslationHelper.currentLanguage = savedLanguage }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setPersonResults(
      """
      [
        { "source": "themoviedb", "id": 14, "name": "王五", "job": "Director/Writer" },
        { "source": "themoviedb", "id": 15, "name": "赵六", "character": "Neo" }
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.mediaSearchSource = nil
    viewModel.query = "abc"
    await viewModel.autoSearch()

    let items = try XCTUnwrap(viewModel.personPaginator?.items)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].job, "导演/编剧")
    XCTAssertNil(items[1].job, "没有 job 的人物不应被投影出职位")
    XCTAssertEqual(items[1].character, "Neo", "character 不应被职位投影影响")
  }

  func testBestResultsDisablePopularityBoostForMixedSources() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    // 混合来源（TMDB + 豆瓣）：热度口径不可比，全部不计算热度，纯按匹配分排序。
    let longTitle = String(repeating: "x", count: 250) + "abc"
    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 2003, "source": "themoviedb", "title": "\(longTitle)", "type": "电影", "year": "2026", "poster_path": "/a.jpg", "popularity": 500},
        {"douban_id": "2004", "source": "douban", "title": "xxabcxxxx", "type": "电影", "year": "2026", "poster_path": "/b.jpg", "popularity": null}
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "abc"
    await viewModel.autoSearch()

    XCTAssertFalse(viewModel.isLoading)
    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, ["xxabcxxxx", longTitle])
  }

  func testBestResultsFilteredOutItemDoesNotCountAsMixedSource() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    // 豆瓣项因无海报且完全不匹配被过滤掉，不构成可见混池：TMDB 热度加权仍应生效。
    let longTitle = String(repeating: "x", count: 250) + "abc"
    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 2005, "source": "themoviedb", "title": "\(longTitle)", "type": "电影", "year": "2026", "poster_path": "/a.jpg", "popularity": 500},
        {"tmdb_id": 2006, "source": "themoviedb", "title": "xxabcxxxx", "type": "电影", "year": "2026", "poster_path": "/b.jpg", "popularity": 0.5},
        {"douban_id": "2007", "source": "douban", "title": "zzzzzz", "type": "电影", "year": "2026", "poster_path": null, "popularity": null}
      ]
      """,
      forQuery: "abc"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "abc"
    await viewModel.autoSearch()

    XCTAssertFalse(viewModel.isLoading)
    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, [longTitle, "xxabcxxxx"])
  }
}

// MARK: - F-140 / F-141 搜索提交词的规范化与年份词法

extension SearchViewModelTests {
  /// F-140：尾随空格必须在下发请求与本地评分之前被去掉，两者共用同一个串。
  ///
  /// 后端 `StringUtils.get_keyword` 自己会 `.strip()`，所以旧实现发出去的请求本来就干净；
  /// 但「最佳匹配」评分读的是用户原串，`fuzzyMatchScore(text: "Hamilton", query: "Hamilton ")`
  /// 走到顺序匹配档、文本先被消耗完而返回 `-1` —— 精确标题反而被 `Hamilton Musical`
  /// 这类带后缀的标题（包含匹配，684 分）反超。
  ///
  /// 这里同时断言两件事：请求确实按 `Hamilton` 发出（stub 按 title 值取响应，
  /// 若发的是带空格的串会取到空结果），以及精确标题排第一。
  func testTrailingWhitespaceIsStrippedBeforeRequestAndScoring() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 3001, "source": "themoviedb", "title": "Hamilton Musical", "type": "电影", "year": "2020", "poster_path": "/b.jpg", "popularity": 10},
        {"tmdb_id": 3002, "source": "themoviedb", "title": "Hamilton", "type": "电影", "year": "2020", "poster_path": "/a.jpg", "popularity": 10}
      ]
      """,
      forQuery: "Hamilton"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "Hamilton "
    await viewModel.autoSearch()

    XCTAssertEqual(viewModel.submittedQuery, "Hamilton", "提交词必须是规范化后的串")
    // 刻意**不**用 `waitForRequest` 断言请求串：stub 按 `title` 值取响应，若发出的是带空格的
    // 串就取不到上面这份数据，下面的标题断言会连带失败 —— 这同时覆盖了「请求规范化」与
    // 「评分用同一个串」两半。而 `waitForRequest` 无超时，一旦请求串不符会死等而不是失败，
    // 反向验证时会挂住整个测试进程。

    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, ["Hamilton", "Hamilton Musical"], "精确标题不得被带后缀标题反超")
  }

  /// F-140：纯空白搜索词不得启动搜索。
  ///
  /// `"   ".isEmpty == false`，所以旧守卫 `guard !query.isEmpty` 拦不住 ——
  /// 会带着一串空格走完整个聚合搜索（四个分页器 + 订阅分享）并置 `hasSearched = true`，
  /// 结果必然为空，用户看到的是一个搜过、但没有结果的页面。
  /// F-140：纯空白提交不发请求。从**全新** ViewModel 起步只保留这一条真正有判别力的断言 ——
  /// `hasSearched` / `isLoading` / `bestResults` 在全新实例上本来就是初始值，怎么实现都过，
  /// 「上一轮结果不被清空」这类语义由下面两条从「已有结果 / 在途搜索」起步的用例负责。
  func testWhitespaceOnlyQueryDoesNotStartSearch() async throws {
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
    viewModel.query = " \n\t "
    await viewModel.autoSearch()

    XCTAssertEqual(viewModel.submittedQuery, "", "空白串不该被记成一次提交")
    let mediaRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/media/search")
    let shareRequestCount = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/subscribe/shares")
    XCTAssertEqual(mediaRequestCount, 0, "纯空白不得触发任何搜索请求")
    XCTAssertEqual(shareRequestCount, 0)
  }

  /// F-140：**现状固化（本轮未改生产代码）**。上一条只从**全新** ViewModel 起步，
  /// `hasSearched == false`、`bestResults.isEmpty` 本来就都是初始值，
  /// 无论实现有没有清过状态都成立 —— 它钉不住「上一轮的搜索结果还留在屏幕上」。
  /// 本条从「已经搜出结果」的状态起步，如实固化纯空白提交的现状：**完全 no-op**，
  /// 既不清旧结果、也不改已提交的检索词。这是刻意的取舍（敲几个空格不该被当成一次搜索，
  /// 更不该把屏幕清空），代价一并写在这里备查。它守的是将来别有人「顺手补一个清空」。
  func testWhitespaceOnlySubmitKeepsPreviousResultsAndStaysNoop() async throws {
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
    viewModel.query = "old"
    await viewModel.autoSearch()

    XCTAssertTrue(viewModel.hasSearched)
    XCTAssertEqual(Self.mediaTitles(of: viewModel), ["Old Result"])

    let mediaRequestCountBefore = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/media/search")

    viewModel.query = " \n\t "
    await viewModel.autoSearch()

    XCTAssertEqual(viewModel.submittedQuery, "old", "空白提交不改动已提交的检索词")
    XCTAssertTrue(viewModel.hasSearched, "上一轮的搜索状态保持不变")
    XCTAssertEqual(
      Self.mediaTitles(of: viewModel), ["Old Result"],
      "空白提交是 no-op，上一轮结果仍在屏幕上（不清空）")
    XCTAssertFalse(viewModel.isLoading)
    let mediaRequestCountAfter = await SearchViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/media/search")
    XCTAssertEqual(mediaRequestCountAfter, mediaRequestCountBefore, "空白提交不得再发一次请求")
  }

  /// F-140：与上一条配对 —— 空白提交发生在**在途资源搜索**期间时不会把它取消掉
  /// （**现状固化**，本轮未改生产代码）。
  ///
  /// 这里刻意走 `.resource` 而不是 `.unified`：只有资源分支把在途任务存进 `searchStreamTask`
  /// （`.unified` 用的是几个局部 Task），所以「顺手补一个 `searchStreamTask?.cancel()`
  /// 再 return」这种改法只在资源分支上真的会打断搜索 —— 在 `.unified` 下它是空操作，
  /// 拿 `.unified` 写这条用例会得到一个测不出东西的假绿。
  ///
  /// 也正因如此，这条用例是**反悔保护**：将来若有人按「空白提交应先取消在途请求」的直觉去改，
  /// 这里会红。真要改也得连带处理 `isLoading` —— `finishSearchIfCurrent` 是清它的唯一出口
  /// 且带 generation 守卫，随手 cancel + 递增 generation 会把 `isLoading` 永久卡在 true。
  func testWhitespaceOnlySubmitDoesNotCancelInFlightSearch() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureSuperUserSearchSession(service)
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "old")
    await SearchViewModelURLProtocol.stub.setStreamTermination(.done, forQuery: "new")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .resource
    viewModel.query = "old"
    await viewModel.autoSearch()

    // 流式搜索在 autoSearch 返回后才收尾（done 后还有一段收尾等待），轮询等同邻近用例。
    let firstDeadline = Date().addingTimeInterval(2)
    while viewModel.resourceResults.isEmpty && Date() < firstDeadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(viewModel.hasSearched)
    XCTAssertEqual(viewModel.resourceResults.first?.torrent_info?.title, "Old Resource")

    // 卡住「new」这一轮的资源搜索流，让它停在在途状态。
    let inFlightGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(
      inFlightGate, forPath: "/api/v1/search/title/stream")
    viewModel.query = "new"
    let inFlightTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { inFlightTask.cancel() }

    try await withTimeout("in-flight resource search to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(
        path: "/api/v1/search/title/stream", query: "new")
    }

    viewModel.query = "   "
    await viewModel.autoSearch()

    XCTAssertTrue(viewModel.isLoading, "空白提交不得取消在途搜索")

    await inFlightGate.open()
    // 注意：`inFlightTask` 只包住 `autoSearch()`，而资源分支在 `autoSearch()` 返回后才真正开始
    // 跑流（任务挂在 `searchStreamTask` 上）。所以这里必须轮询状态，不能 await 那个包装任务 ——
    // 它早就返回了，await 它等于什么都没等。
    // 收到 done 后实现里还有 1.5s 的收尾等待（`searchStreamDoneCloseDelay`），
    // 所以这里的上限比邻近用例宽一些，免得贴着边界偶然超时。
    let secondDeadline = Date().addingTimeInterval(5)
    while viewModel.isLoading && Date() < secondDeadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(
      viewModel.resourceResults.first?.torrent_info?.title, "New Resource",
      "在途搜索照常跑完并发布结果，没有被空白提交打断")
  }

  private static func mediaTitles(of viewModel: SearchViewModel) -> [String] {
    viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item {
        return media.title
      }
      return nil
    }
  }

  /// F-140 的**阴性对照**：规范化只去首尾，不压缩内部空白。
  ///
  /// 内部空白的匹配质量属于评分层分档问题，不属于「提交词身份」问题；
  /// 一旦顺手压缩，就会改变 `hasPrefix`/`contains` 既有分档的输入，超出本条范围。
  func testInternalWhitespaceIsDeliberatelyPreserved() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setMediaResults(
      "[]", forQuery: "流浪地球  2")

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "流浪地球  2"
    await viewModel.autoSearch()

    XCTAssertEqual(viewModel.submittedQuery, "流浪地球  2", "内部空白必须原样保留")
  }

  /// F-141：`1917` 这类数字片名不得被当成年份。
  ///
  /// 查询 `"1917 2019"` 时，旧词法 `(19|20)\d{2}` 扫到的是片名里的 1917：
  /// 于是《1917》（year = 2019）被判为年份不符，回退匹配被关掉，
  /// 而 `fuzzyMatchScore(text: "1917", query: "1917 2019")` 在顺序匹配档文本先耗尽 → `-1`。
  /// 该片若又无海报且热度 < 1，会被 `hasNoPoster && maxS < 50 && pop < 1` 整条淘汰，
  /// 搜索「1917 2019」反而找不到《1917》。
  ///
  /// 与后端 `[\s(]+(\d{4})[\s)]*` 同构后，年份取到 2019、纯标题回退词是 1917，精确标题得 1000。
  func testNumericTitleIsNotMistakenForSearchYear() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 1917, "source": "themoviedb", "title": "1917", "type": "电影", "year": "2019", "poster_path": null, "popularity": 0.5}
      ]
      """,
      forQuery: "1917 2019"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "1917 2019"
    await viewModel.autoSearch()

    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, ["1917"], "精确标题不得因年份误判被评分 -1 后淘汰")
  }

  /// F-141：剥年份必须连括号一起剥，不得留下 `()` 空壳。
  ///
  /// 旧实现只删数字：`"流浪地球 (2019)"` → 回退词变成 `"流浪地球 ()"`，与「流浪地球」
  /// 既非全等、非前缀、也非包含，顺序匹配又因括号对不上而失败 → 精确标题只得 `-1`，
  /// 而 `流浪地球特辑`（含「流浪地球」作为前缀）在旧实现里同样只得 `-1`，
  /// 两者同分后精确标题因无海报被淘汰，反而只剩特辑。
  func testParenthesizedYearIsRemovedTogetherWithItsBrackets() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SearchViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SearchViewModelURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    service.baseURLForTesting = "http://search-tests.local"
    configureDiscoveryPermissionSession(service)

    await SearchViewModelURLProtocol.stub.setMediaResults(
      """
      [
        {"tmdb_id": 4001, "source": "themoviedb", "title": "流浪地球特辑", "type": "电影", "year": "2019", "poster_path": "/b.jpg", "popularity": 5},
        {"tmdb_id": 4002, "source": "themoviedb", "title": "流浪地球", "type": "电影", "year": "2019", "poster_path": null, "popularity": 0.5}
      ]
      """,
      forQuery: "流浪地球 (2019)"
    )

    let viewModel = SearchViewModel(apiService: service)
    viewModel.searchType = .unified
    viewModel.query = "流浪地球 (2019)"
    await viewModel.autoSearch()

    let titles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item { return media.title }
      return nil
    }
    XCTAssertEqual(titles, ["流浪地球", "流浪地球特辑"], "精确标题应回退到纯标题匹配并排在首位")
  }
}
