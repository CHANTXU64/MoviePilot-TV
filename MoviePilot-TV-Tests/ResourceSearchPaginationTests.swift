import Foundation
import Combine
import Darwin
import SwiftUI
import XCTest
@testable import MoviePilot_TV

@MainActor
final class ResourceSearchPaginationTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(PaginationURLProtocol.self))
    PaginationURLProtocol.reset()
  }
  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(PaginationURLProtocol.self)
  }

  private func service(version: String = "v3.1.2-1", admin: Bool = false) throws -> APIService {
    let api = APIService.isolatedTestingInstance()
    api.replaceSessionForTesting(baseURL: "https://pagination-tests.local", token: "test",
      currentUser: Token(access_token: "test", token_type: "bearer", super_user: FlexibleBool(admin),
        permissions: ["search": true], user_id: 929, user_name: "pagination-test", avatar: nil))
    api.settings = try JSONDecoder().decode(GlobalSettings.self, from: json(["BACKEND_VERSION": version]))
    return api
  }

  private func settled(_ session: ResourceSearchSession) async throws {
    try await until { !session.isBusy }
  }
  private func until(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(2)) }
    XCTAssertTrue(condition(), "状态应在有限时间内收敛", file: file, line: line)
  }

  func testVersionGateIncludesHotfixBoundaryAndFutureStableVersions() {
    for version in ["v3.1.2-1", "v3.1.2-2", "v3.1.3", "v4.0.0"] {
      XCTAssertTrue(ResourceSearchQuery.supportsPaging(backendVersion: version))
    }
    for version: String? in [nil, "unknown", "v3.1.2", "v3.1.1", "v3.1.2-beta"] {
      XCTAssertFalse(ResourceSearchQuery.supportsPaging(backendVersion: version))
    }
  }

  func testCompleteFinalChunksCommitAllItemsWithoutPreviewDuplicates() throws {
    var page = ResourceSearchPage(source: "opaque", page: 1)
    try page.receive(event("append", items: [item("preview")]))
    try page.receive(event("replace", items: (0..<48).map { item("r\($0)") },
      sources: [fact("opaque", page: 1)], batch: (0, 2), total: 49))
    XCTAssertFalse(page.isComplete)
    XCTAssertEqual(page.finalItems.count, 48)
    try page.receive(event("append", items: [item("last")], sources: [fact("opaque", page: 1)], batch: (1, 2), total: 49))
    XCTAssertTrue(page.isComplete)
    XCTAssertEqual(page.finalItems.count, 49)
    XCTAssertEqual(page.finalItems.last?.torrent_info?.title, "last")
  }

  func testLegacyCollectorKeepsPreviewUntilFinalBatchIsComplete() throws {
    let values = legacyBatchItems()
    var collector = ResourceSearchResultCollector()
    try collector.receive(event("append", items: [item("preview")]))
    try collector.receive(event("replace", items: Array(values.prefix(48)), batch: (0, 2), total: 60))
    XCTAssertEqual(collector.items.compactMap { $0.torrent_info?.title }, ["preview"])
    try collector.receive(event("heartbeat", items: []))
    try collector.receive(event("append", items: Array(values.suffix(12)), batch: (1, 2), total: 60))
    try collector.receive(event("append", items: [item("late preview")]))
    try collector.receive(event("done", items: [item("stale done")]))
    XCTAssertEqual(collector.items.compactMap { $0.torrent_info?.title }, (0..<60).map { "r\($0)" })
  }

  private func legacySearch(_ body: String, version: String, media: Bool,
    fallbackSucceeds: Bool = true
  ) async throws -> (items: [Context], error: String?) {
    PaginationURLProtocol.reset()
    let api = try service(version: version)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: body)
    PaginationURLProtocol.enqueue(source: nil, page: 0,
      body: String(data: try json([item("fallback")]), encoding: .utf8)!,
      status: fallbackSucceeds ? 200 : 500)
    let result: ([Context], String?)
    if media {
      let vm = ResourceResultViewModel(keyword: "tmdb:123", type: "电影", sites: "1", apiService: api)
      await vm.search()
      try await until { !vm.isLoading }
      XCTAssertNil(vm.pagedSearch)
      result = (vm.results, vm.errorMessage)
    } else {
      let vm = SearchViewModel(apiService: api)
      vm.searchType = .resource; vm.query = "legacy"
      await vm.autoSearch()
      try await until { !vm.isLoading }
      XCTAssertNil(vm.pagedSearch)
      result = (vm.resourceResults, vm.resourceErrorMessage)
    }
    XCTAssertEqual(PaginationURLProtocol.requests.first?.path,
      media ? "/api/v1/search/media/123/stream" : "/api/v1/search/title/stream")
    XCTAssertNil(PaginationURLProtocol.requests.first?.manual)
    return result
  }

  private func legacyBatchItems() -> [[String: Any]] {
    (0..<60).map { index in
      var value = item("r\(index)")
      var torrent = value["torrent_info"] as! [String: Any]
      torrent["site"] = 1
      value["torrent_info"] = torrent
      return value
    }
  }

  func testLegacyVersionsCommitAllFinalBatchesThroughBothSearchEntries() async throws {
    let values = legacyBatchItems()
    let body = frame("append", items: [item("preview")])
      + frame("replace", items: Array(values.prefix(48)), batch: (0, 2), total: 60)
      + frame("append", items: Array(values.suffix(12)), batch: (1, 2), total: 60)
      + "data: {\"type\":\"done\"}\n\n"
    for version in ["v3.1.1", "v3.1.2"] {
      for media in [false, true] {
        let result = try await legacySearch(body, version: version, media: media)
        XCTAssertEqual(result.items.compactMap { $0.torrent_info?.title }, (0..<60).map { "r\($0)" })
        XCTAssertNil(result.error)
        XCTAssertEqual(PaginationURLProtocol.requests.count, 1, "完整分块不能触发 HTTP 回退或缺站补偿")
      }
    }
  }

  func testLegacyIncompleteFinalBatchesUseFallbackWithoutPublishingPartialResults() async throws {
    let values = legacyBatchItems()
    let first = frame("replace", items: Array(values.prefix(48)), batch: (0, 2), total: 60)
    let done = "data: {\"type\":\"done\"}\n\n"
    let malformed = [
      first + done,
      first,
      first + frame("append", items: Array(values.suffix(12)), batch: (2, 3), total: 60) + done,
      first + first + done,
      first + frame("append", items: Array(values.suffix(11)), batch: (1, 2), total: 60) + done,
      first + frame("append", items: Array(values.suffix(12)), batch: (1, 3), total: 60) + done,
      first + frame("append", items: [item("preview mixed into final")]) + done,
      first + frame("done", items: values),
    ]
    for version in ["v3.1.1", "v3.1.2"] {
      for media in [false, true] {
        for body in malformed {
          let result = try await legacySearch(body, version: version, media: media)
          XCTAssertEqual(result.items.compactMap { $0.torrent_info?.title }, ["fallback"])
          XCTAssertNil(result.error)
          XCTAssertEqual(PaginationURLProtocol.requests.count, 2)
          XCTAssertEqual(PaginationURLProtocol.requests.last?.path,
            media ? "/api/v1/search/media/123" : "/api/v1/search/title")
        }
        let failed = try await legacySearch(first + done, version: version, media: media, fallbackSucceeds: false)
        XCTAssertTrue(failed.items.isEmpty)
        XCTAssertNotNil(failed.error)
      }
    }
  }

  func testProductionFinalChunksPublishAllRowsWithDuplicateBackendIDs() async throws {
    let api = try service()
    let facts = [fact("opaque", page: 0, more: false)]
    let body = frame("append", items: [item("preview")])
      + frame("replace", items: (0..<48).map { item("r\($0)") }, sources: facts, batch: (0, 2), total: 60)
      + frame("append", items: (48..<60).map { item("r\($0)") }, sources: facts, batch: (1, 2), total: 60)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: body)
    let vm = ResourceResultViewModel(keyword: "test", apiService: api)
    await vm.search()
    let session = try XCTUnwrap(vm.pagedSearch)
    try await settled(session)
    XCTAssertEqual(session.rows.count, 60)
    XCTAssertEqual(Set(session.rows.map(\.id)).count, 60)
    XCTAssertEqual(session.rows.last?.context.torrent_info?.title, "r59")
    XCTAssertTrue(session.initialComplete)
  }

  func testSecondStopWhileRetryingKeepsOriginalPausedPageAndSelections() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("base")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    session.filterForm = ["resolution": ["4K"]]
    session.sortField = .seeders; session.sortType = .desc
    session.updateProjection()
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("append", items: [item("P")]), finish: false)
    session.continueSearch(); try await until { session.retainedCount == 2 }
    session.stop(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("append", items: [item("Q1"), item("Q2")]), finish: false)
    session.continueSearch()
    try await until { PaginationURLProtocol.requests.count == 3 }
    // 让完整 Q 预览经过传输交付，仍然不能替换已经保留的 P。
    try await Task.sleep(for: .milliseconds(50))
    session.stop(); try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["base", "P"])
    XCTAssertEqual(session.filterForm, ["resolution": ["4K"]])
    XCTAssertEqual(session.sortType, .desc)
    XCTAssertEqual(session.sortField, .seeders)
  }

  func testCandidateDoesNotInheritDownloadTarget() throws {
    let original = try context(item("candidate"))
    let target = try JSONDecoder().decode(MediaInfo.self, from: json(["title": "target", "tmdb_id": 123]))
    let row = ResourceSearchRow(id: "row", context: original, isCandidate: true)
    XCTAssertNil(row.downloadMedia(override: target))
    let card = TorrentCard(context: original, overrideMediaInfo: target, isCandidate: true)
    XCTAssertNil(card.media)
  }

  func testDownloadMediaBindingThroughResultCard() throws {
    let target = try JSONDecoder().decode(MediaInfo.self, from: json(["title": "详情目标", "tmdb_id": 123]))
    for (candidate, recognized, useOverride, expected) in [
      (true, true, true, nil as String?),
      (false, false, true, nil),
      (false, true, true, "详情目标"),
      (false, true, false, "识别结果"),
    ] {
      var data = item("resource")
      if recognized { data["media_info"] = ["title": "识别结果", "tmdb_id": 456] }
      let original = try context(data)
      let row = ResourceSearchRow(id: "row", context: original, isCandidate: candidate)
      let card = TorrentCard(context: original,
        overrideMediaInfo: row.downloadMedia(override: useOverride ? target : nil), isCandidate: row.isCandidate)
      XCTAssertEqual(card.media?.title, expected)
      let download = AddDownloadViewModel(torrent: try XCTUnwrap(card.torrent), media: card.media, apiService: try service())
      XCTAssertEqual(download.media?.title, expected)
    }
  }

  func testMusicMediaUsesLegacyStreamButMusicKeywordStillUsesPaging() async throws {
    let api = try service()
    var music = item("album")
    var torrent = try XCTUnwrap(music["torrent_info"] as? [String: Any])
    torrent["site"] = 1
    music["torrent_info"] = torrent
    PaginationURLProtocol.enqueue(source: nil, page: 0,
      body: frame("replace", items: [music]) + "data: {\"type\":\"done\"}\n\n")
    let media = ResourceResultViewModel(keyword: "douban:123", type: "音乐", sites: "1", apiService: api)
    await media.search()
    try await until { !media.isLoading }
    XCTAssertNil(media.pagedSearch)
    XCTAssertNil(media.errorMessage)
    XCTAssertEqual(media.results.first?.torrent_info?.title, "album")
    XCTAssertNil(PaginationURLProtocol.requests.first?.manual)
    XCTAssertEqual(PaginationURLProtocol.requests.first?.path, "/api/v1/search/media/123/stream")

    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [music], sources: []))
    let title = ResourceResultViewModel(keyword: "音乐", type: "音乐", apiService: api)
    await title.search()
    let search = try XCTUnwrap(title.pagedSearch)
    try await settled(search)
    XCTAssertEqual(search.rows.count, 1)
    XCTAssertEqual(PaginationURLProtocol.requests.last?.manual, "true")
    XCTAssertEqual(PaginationURLProtocol.requests.count, 2)
  }

  func testIncompleteOrConflictingPageNeverCommits() throws {
    let invalid: [[String: Any]] = [
      ["type": "done"],
      ["type": "replace", "items": [], "total_items": 0, "sources": []],
      ["type": "replace", "items": [], "total_items": 0, "sources": [fact("other", page: 1)]],
      ["type": "replace", "items": [], "total_items": 0, "sources": [fact("opaque", page: 2)]],
      ["type": "replace", "items": [], "total_items": 0, "sources": [fact("opaque", page: 1, error: "failed")]],
    ]
    for payload in invalid {
      var page = ResourceSearchPage(source: "opaque", page: 1)
      let decoded = try JSONDecoder().decode(SearchStreamEvent.self, from: json(payload))
      XCTAssertThrowsError(try page.receive(decoded))
      XCTAssertFalse(page.isComplete)
    }
    var page = ResourceSearchPage(source: nil, page: 0)
    try page.receive(event("replace", items: [], sources: []))
    XCTAssertTrue(page.isComplete, "首轮允许没有来源，不能与续页缺来源混淆")
  }

  func testInitialPartialSourceFailureKeepsSuccessAndFailedCursor() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("ok")],
      sources: [fact("a", page: 0), fact("b", page: 0, error: "timeout")]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertTrue(session.canContinue)
    XCTAssertEqual(session.resultErrorMessage, "部分搜索来源失败，已保留成功结果。")
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1, "首批不自动续页")
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("replace", items: [], sources: [fact("a", page: 1, more: false)]))
    PaginationURLProtocol.enqueue(source: "b", page: 0, body: frame("replace", items: [item("retry")], sources: [fact("b", page: 0, more: false)]))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1])
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertTrue(session.canContinue)
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(session.rows.count, 2)
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1, 0])
    XCTAssertFalse(session.canContinue)
    XCTAssertNil(session.resultErrorMessage)
  }

  func testBothProductionEntriesUseVersionGatedManualParameters() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("title")], sources: []))
    let keyword = SearchViewModel(apiService: api)
    keyword.searchType = .resource; keyword.query = "a&b"
    await keyword.autoSearch()
    let titleSession = try XCTUnwrap(keyword.pagedSearch)
    try await settled(titleSession)
    XCTAssertEqual(titleSession.rows.count, 1)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("media")], sources: []))
    let detail = ResourceResultViewModel(keyword: "tmdb:123", type: "电视剧", season: 0, sites: "1,2", apiService: api)
    await detail.search()
    let mediaSession = try XCTUnwrap(detail.pagedSearch)
    try await settled(mediaSession)
    let requests = PaginationURLProtocol.requests
    XCTAssertEqual(requests.map(\.manual), ["true", "true"])
    XCTAssertEqual(requests[0].keyword, "a&b")
    XCTAssertEqual(requests[1].path, "/api/v1/search/media/123/stream")
    XCTAssertEqual(requests[1].season, "0")
    XCTAssertEqual(requests[1].sites, "1,2")
    XCTAssertTrue(requests.allSatisfy { $0.source == nil && $0.page == 0 })
  }

  func testLoadingButtonKeepsNativeFocusWhileSearchBecomesProcessing() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: stageFrame("searching"), finish: false)
    let model = SearchViewModel(apiService: api)
    model.searchType = .resource; model.query = "test"
    await model.autoSearch()
    let session = try XCTUnwrap(model.pagedSearch)
    let results = PagedResourceResultsView(search: session, onCancel: { model.cancelPagedSearch() }) {
      Text("资源搜索")
    }
    let host = UIHostingController(rootView: NavigationStack { results }.environment(\.scenePhase, .active))
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { session.cancel(); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
    try await until { UIFocusSystem(for: window)?.focusedItem != nil && !PaginationURLProtocol.requests.isEmpty }
    let button = try XCTUnwrap(UIFocusSystem(for: window)?.focusedItem)
    XCTAssertTrue(resourceNavigationControllers(in: host).contains { $0.topViewController?.contains(button) == true })
    XCTAssertEqual(results.loadingAction.title, "取消")
    for (body, title) in [(frame("append", items: [item("preview")]), "停止并查看"),
      (stageFrame("filtering"), "取消")]
    {
      XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(body))
      try await until { results.loadingAction.title == title }
      // 跨过 SwiftUI 更新和 Focus Engine 的帧，检查原生焦点对象没有被替换。
      for _ in 0..<10 {
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(UIFocusSystem(for: window)?.focusedItem === button)
      }
    }
    results.loadingAction.perform()
    XCTAssertNil(model.pagedSearch)
    XCTAssertFalse(model.hasSearched)
    XCTAssertFalse(session.isBusy)
  }

  func testOldBackendKeepsExistingStreamWithoutManualParameters() async throws {
    let api = try service(version: "v3.1.2")
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: "data: {\"type\":\"error\",\"message\":\"fixture\"}\n\n")
    let vm = ResourceResultViewModel(keyword: "old", apiService: api)
    await vm.search()
    try await until { !vm.isLoading }
    XCTAssertNil(vm.pagedSearch)
    XCTAssertNil(PaginationURLProtocol.requests.first?.manual)
  }

  func testStopInitialKeepsMoreThan24CandidatesAndRequiresRestart() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0,
      body: frame("append", items: (0..<60).map { item("p\($0)") }), finish: false)
    let vm = ResourceResultViewModel(keyword: "tmdb:123", apiService: api)
    await vm.search()
    let session = try XCTUnwrap(vm.pagedSearch)
    try await until { session.retainedCount == 60 }
    session.stop(); try await settled(session)
    XCTAssertEqual(session.rows.count, 60)
    XCTAssertEqual(Set(session.rows.map(\.id)).count, 60)
    XCTAssertTrue(session.rows.allSatisfy(\.isCandidate))
    XCTAssertTrue(session.canRestart)
    XCTAssertFalse(session.canContinue)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
    await vm.search()
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1, "页面再次出现不能自动续搜")
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("replacement")], sources: []))
    session.restart()
    XCTAssertEqual(session.rows.count, 60, "重搜期间保留旧展示快照")
    try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["replacement"])
  }

  func testContinuationStopsRetriesSamePageAndPreservesOldPausedSnapshotOnFailure() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("initial")], sources: [fact("opaque", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "opaque", page: 1, body: frame("append", items: [item("P")]), finish: false)
    session.continueSearch(); try await until { session.retainedCount == 2 }
    session.stop(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "opaque", page: 1, body:
      frame("append", items: [item("Q")]) + frame("replace", items: [], sources: [fact("opaque", page: 1, error: "failed")]))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["initial", "P"])
    PaginationURLProtocol.enqueue(source: "opaque", page: 1, body: frame("replace", items: [item("final")], sources: [fact("opaque", page: 1, more: false)]))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["initial", "final"])
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1, 1, 1])
  }

  func testStopRotatesSlowSourceAndEmptyFilteredPageKeepsContinuationAvailable() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [], sources: [fact("a", page: 0), fact("b", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("append", items: [item("partial")]), finish: false)
    session.continueSearch(); try await until { session.retainedCount == 1 }
    session.stop(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "b", page: 1, body: frame("replace", items: [], sources: [fact("b", page: 1)]))
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("replace", items: [], sources: [fact("a", page: 1, more: false)]))
    PaginationURLProtocol.enqueue(source: "b", page: 2, body: frame("replace", items: [item("last")], sources: [fact("b", page: 2, more: false)]))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.compactMap(\.source), ["a", "b"])
    XCTAssertTrue(session.canContinue)
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.compactMap(\.source), ["a", "b", "a"])
    XCTAssertTrue(session.canContinue)
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.compactMap(\.source), ["a", "b", "a", "b"])
    XCTAssertEqual(session.rows.count, 1)
  }

  func testMissingSourceParksWithoutHTTPFallbackOrRetryLoop() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("old")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("replace", items: [], sources: []))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 2)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertTrue(session.canContinue)
    XCTAssertNotNil(session.errorMessage)
  }

  func testEmptyFailedPreviewDoesNotSuppressNextRetryPreview() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("base")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body:
      frame("append", items: []) + frame("replace", items: [], sources: [fact("a", page: 1, error: "failed")]))
    session.continueSearch(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("append", items: [item("new preview")]), finish: false)
    session.continueSearch(); try await until { session.retainedCount == 2 }
    session.stop(); try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["base", "new preview"])
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1, 1])
  }

  func testEmptyContinuationCanStopAndRetainPageProgress() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("replace", items: [], sources: [fact("a", page: 1)]))
    PaginationURLProtocol.enqueue(source: "a", page: 2, body: frame("append", items: []), finish: false)
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 2)
    XCTAssertTrue(session.canContinue)
    session.continueSearch(); try await until { PaginationURLProtocol.requests.count == 3 }
    XCTAssertTrue(session.canStopAndView)
    session.deactivate(); try await settled(session)
    XCTAssertTrue(session.canContinue)
    PaginationURLProtocol.enqueue(source: "a", page: 2, body: frame("replace", items: [], sources: [fact("a", page: 2, more: false)]))
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1, 2, 2])
  }

  func testContinueLoadsOnlyOnePageUntilTheNextExplicitAction() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("first")], sources: [fact("a", page: 0)]))
    PaginationURLProtocol.enqueue(source: "a", page: 1, body: frame("replace", items: [item("second")], sources: [fact("a", page: 1)]))
    PaginationURLProtocol.enqueue(source: "a", page: 2, body: frame("replace", items: [item("third")], sources: [fact("a", page: 2, more: false)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    session.continueSearch()
    session.continueSearch()
    try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1])
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["first", "second"])
    XCTAssertTrue(session.canContinue)
    session.continueSearch(); try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.page), [0, 1, 2])
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["first", "second", "third"])
    XCTAssertFalse(session.canContinue)
  }

  func testBackendFilteringRemovesStopUntilActualSearchingResumes() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("preview")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    defer { session.cancel() }
    session.start(); try await until { session.retainedCount == 1 }
    XCTAssertTrue(session.canStopAndView)
    XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(stageFrame("filtering")))
    try await until { !session.isSearching }
    XCTAssertTrue(session.isCollecting)
    XCTAssertTrue(session.isBusy)
    XCTAssertFalse(session.canStopAndView)
    session.stop()
    XCTAssertTrue(session.isCollecting, "已进入过滤时，迟到的停止操作也不应取消结果处理")
    XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(stageFrame("searching")))
    try await until { session.isSearching }
    XCTAssertTrue(session.canStopAndView, "后端重新搜索别名时仍沿用真实搜索阶段")
    XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(
      stageFrame("filtering") + frame("replace", items: [item("final")], sources: []), finish: true))
    try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["final"])
    XCTAssertFalse(session.canStopAndView)
  }

  func testFinalChunksRemoveStopBeforeLocalFilteringAndSorting() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("preview")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    var stopDuringFinalIngest: Bool?
    var stopDuringProjection: Bool?
    let finalObservation = session.$initialComplete.sink { complete in
      if complete { stopDuringFinalIngest = session.canStopAndView }
    }
    let projectionObservation = session.$isPreparing.sink { preparing in
      if preparing { stopDuringProjection = session.canStopAndView }
    }
    defer { finalObservation.cancel(); projectionObservation.cancel(); session.cancel() }
    session.start(); try await until { session.retainedCount == 1 }
    XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(
      frame("replace", items: [item("one")], sources: [], batch: (0, 2), total: 2)))
    try await until { !session.isSearching }
    XCTAssertTrue(session.isBusy)
    XCTAssertFalse(session.canStopAndView)
    XCTAssertFalse(session.initialComplete)
    session.stop()
    XCTAssertTrue(PaginationURLProtocol.sendHeldSearch(
      frame("append", items: [item("two")], sources: [], batch: (1, 2), total: 2), finish: true))
    try await settled(session)
    XCTAssertEqual(stopDuringFinalIngest, false)
    XCTAssertEqual(stopDuringProjection, false)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["one", "two"])
  }

  func testLeavingDuringFilteringStillCancelsThePage() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0,
      body: frame("append", items: [item("preview")]) + stageFrame("filtering"), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 1 && !session.isSearching }
    XCTAssertFalse(session.canStopAndView)
    session.deactivate(); try await settled(session)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["preview"])
    XCTAssertTrue(session.canRestart)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
  }

  func testSiteSelectionOnlyRestartsAtApplyBoundary() async throws {
    let api = try service()
    let navigation = ImageNavigationCoordinator(apiService: api)
    navigation.setStackPresentation(isSelected: true, scenePhase: .active)
    let source = navigation.sourceToken()
    let vm = SearchViewModel(apiService: api)
    vm.searchType = .resource; vm.query = "test"; vm.siteFilter.selectedSites = [2]
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [], sources: [fact("old-source", page: 0)]))
    await vm.autoSearch(); try await settled(XCTUnwrap(vm.pagedSearch))
    vm.siteFilter.selectedSites = [1]
    vm.query = ""
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("new")], sources: []))
    await vm.applyPagedSearchSites(from: source, in: navigation)
    try await settled(XCTUnwrap(vm.pagedSearch))
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.sites), ["2", "1"])
    XCTAssertEqual(PaginationURLProtocol.requests.map(\.keyword), ["test", "test"], "只应用站点范围，不提交尚未确认的搜索框草稿")
    XCTAssertTrue(PaginationURLProtocol.requests.allSatisfy { $0.source == nil })
    await vm.applyPagedSearchSites(from: source, in: navigation)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 2)
  }

  func testExternalNavigationOrTabDeparturePreventsDismissedSiteSheetFromRestartingSearch() async throws {
    let api = try service()
    let navigation = ImageNavigationCoordinator(apiService: api)
    navigation.setStackPresentation(isSelected: true, scenePhase: .active)
    let vm = SearchViewModel(apiService: api)
    vm.searchType = .resource; vm.query = "test"; vm.siteFilter.selectedSites = [2]
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [], sources: [fact("old", page: 0)]))
    await vm.autoSearch()
    let original = try XCTUnwrap(vm.pagedSearch)
    try await settled(original)
    let externalSource = navigation.sourceToken()
    vm.siteFilter.selectedSites = [1]
    original.deactivate()
    NotificationCenter.default.post(name: .imageNavigationPresentationWillReset, object: api)
    await vm.applyPagedSearchSites(from: externalSource, in: navigation)
    XCTAssertTrue(vm.pagedSearch === original)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)

    let tabSource = navigation.sourceToken()
    navigation.setStackPresentation(isSelected: false, scenePhase: .active)
    navigation.setStackPresentation(isSelected: true, scenePhase: .active)
    await vm.applyPagedSearchSites(from: tabSource, in: navigation)
    XCTAssertTrue(vm.pagedSearch === original)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
  }

  func testReapplyingRulesCancelsOlderProjectionWithoutEndingRulePreparation() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.rulesBody = #"{"value":[{"id":"hard","name":"h","include":"keep"}]}"#
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("keep"), item("other")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    PaginationURLProtocol.holdRules = true
    session.sortField = .seeders
    session.updateProjection()
    session.reapplyRules()
    try await until { PaginationURLProtocol.hasHeldRule }
    _ = await session.processor.staticEvaluations
    await Task.yield()
    XCTAssertTrue(session.rulePending)
    XCTAssertTrue(session.isPreparing)
    XCTAssertFalse(session.canContinue)
    PaginationURLProtocol.finishHeldRules()
    try await settled(session)
    XCTAssertFalse(session.rulePending)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["keep"])
    XCTAssertTrue(session.canContinue)
  }

  func testEmptyRegexHasSameHardAndSoftMeaningInBothSearchPaths() async throws {
    let api = try service(admin: true)
    let profile = try XCTUnwrap(api.profileKey)
    let hardKey = "selectedCustomFilterRuleId_\(profile)"
    let softKey = "selectedSoftFilterRuleId_\(profile)"
    UserDefaults.standard.set("hard", forKey: hardKey)
    UserDefaults.standard.set("soft", forKey: softKey)
    defer {
      UserDefaults.standard.removeObject(forKey: hardKey)
      UserDefaults.standard.removeObject(forKey: softKey)
    }
    PaginationURLProtocol.rulesBody = #"{"value":[{"id":"hard","name":"h","include":["", "["]},{"id":"soft","name":"s","exclude":["", "["]}]}"#
    let payloads = [item("first"), item("second")]
    let legacy = try await CustomFilterService.applyHardAndSoftFilter(to: payloads.map(context), using: api)
    XCTAssertEqual(legacy.map { $0.torrent_info?.title }, ["first", "second"])
    XCTAssertTrue(legacy.allSatisfy(\.isFilteredOut))
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: payloads, sources: []))
    let vm = ResourceResultViewModel(keyword: "test", apiService: api)
    await vm.search()
    let session = try XCTUnwrap(vm.pagedSearch)
    try await settled(session)
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["first", "second"])
    XCTAssertTrue(session.rows.allSatisfy { $0.context.isFilteredOut })
  }

  func testClearingOrFailingRulesExplicitlyRestoresRawResults() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.rulesBody = #"{"value":[{"id":"hard","name":"h","include":"keep"}]}"#
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("keep"), item("other")], sources: []))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await settled(session)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertTrue(session.canReapplyRules)
    UserDefaults.standard.removeObject(forKey: key)
    session.reapplyRules(); try await settled(session)
    XCTAssertEqual(session.rows.count, 2)
    UserDefaults.standard.set("hard", forKey: key)
    session.reapplyRules(); try await settled(session)
    XCTAssertEqual(session.rows.count, 1)
    PaginationURLProtocol.rulesBody = "invalid-response"
    session.reapplyRules(); try await settled(session)
    XCTAssertTrue(session.rulesBypassed)
    XCTAssertEqual(session.rows.count, 2)
    XCTAssertNotNil(session.ruleNotice)
  }

  func testDeactivationKeepsPendingRuleRequestRecoverable() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.rulesBody = #"{"value":[{"id":"hard","name":"h","include":"keep"}]}"#
    PaginationURLProtocol.holdRules = true
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("keep")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 1 && PaginationURLProtocol.hasHeldRule }
    session.deactivate()
    XCTAssertTrue(session.rulePending)
    PaginationURLProtocol.finishHeldRules()
    try await settled(session)
    XCTAssertFalse(session.rulePending)
    XCTAssertFalse(session.rulesBypassed)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
  }

  func testSparseItemCountIsBoundedBeforeContextMaterialization() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body:
      frame("append", items: [item("accepted")]) + frame("append", items: Array(repeating: [:], count: 20)))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api, capacityBytes: 64 * 1024)
    session.start(); try await settled(session)
    XCTAssertTrue(session.reachedCapacity)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertFalse(session.initialComplete)
  }

  func testRetainedBudgetBoundsEachDecodeAndCannotBeBypassed() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body:
      (0..<15).map { frame("append", items: [item("keep\($0)")]) }.joined() + frame("append", items: [item("too much")]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api, capacityBytes: 64 * 1024)
    session.start(); try await settled(session)
    XCTAssertTrue(session.reachedCapacity)
    XCTAssertEqual(session.rows.count, 15)
    session.continueSearch(); session.restart()
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
    let capacityMessage = try XCTUnwrap(session.resultErrorMessage)
    XCTAssertTrue(capacityMessage.contains("容量"))
    session.reapplyRules(); try await settled(session)
    XCTAssertEqual(session.resultErrorMessage, capacityMessage, "重新应用过滤不能隐藏仍然生效的容量终态")
  }

  func testDefaultBudgetAcceptsLargeUnsplitPreviewFinalChunksAndFurtherPages() async throws {
    let api = try service()
    let values = (0..<600).map { index -> [String: Any] in
      var value = item("Resource \(index)")
      var torrent = value["torrent_info"] as! [String: Any]
      torrent["description"] = String(repeating: "x", count: 3900)
      value["torrent_info"] = torrent
      return value
    }
    XCTAssertGreaterThan(try json(values[0]).count, 4000)
    let chunks = stride(from: 0, to: values.count, by: 48).map { Array(values[$0..<min($0 + 48, values.count)]) }
    let preview = frame("append", items: values)
    XCTAssertGreaterThan(preview.utf8.count, 2 * 1024 * 1024)
    let final = chunks.enumerated().map { index, chunk in
      frame(index == 0 ? "replace" : "append", items: chunk,
        sources: [fact("a", page: 0)], batch: (index, chunks.count), total: values.count)
    }.joined()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: preview + final)
    let session = ResourceSearchSession(query: .init(keyword: "large"), apiService: api)
    session.start(); try await settled(session)
    XCTAssertTrue(session.initialComplete)
    XCTAssertEqual(session.rows.count, 600)
    XCTAssertFalse(session.reachedCapacity)
    XCTAssertTrue(session.canContinue)
    // 发布后的数据仍由原页持有，后续页不能再把整份展示按完整载荷重复计费。
    for page in 1...3 {
      let items = Array(values.prefix(100))
      PaginationURLProtocol.enqueue(source: "a", page: page, body:
        frame("append", items: items) + frame("replace", items: items, sources: [fact("a", page: page)]))
      session.continueSearch(); try await settled(session)
      XCTAssertFalse(session.reachedCapacity)
      XCTAssertEqual(session.rows.count, 600 + page * 100)
    }
    XCTAssertEqual(PaginationURLProtocol.requests.count, 4)
  }

  func testRestartBudgetIncludesOldVisibleSnapshotUntilReplacementPublishes() async throws {
    let api = try service()
    let preview = (0..<7).map { frame("append", items: [item("old\($0)")]) }.joined()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: preview, finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "restart"), apiService: api, capacityBytes: 64 * 1024)
    session.start(); try await until { session.retainedCount == 7 }
    session.stop(); try await settled(session)
    XCTAssertEqual(session.rows.count, 7)
    PaginationURLProtocol.enqueue(source: nil, page: 0,
      body: (0..<9).map { frame("append", items: [item("new\($0)")]) }.joined())
    session.restart(); try await settled(session)
    XCTAssertTrue(session.reachedCapacity, "旧展示与新预览是两份数据，仍需计入容量")
    XCTAssertEqual(session.rows.count, 8)
    XCTAssertEqual(session.rows.first?.context.torrent_info?.title, "new0")
  }

  func testRestartBudgetOnlyRetainsTheFilteredVisibleSnapshot() async throws {
    let api = try service()
    let preview = (0..<11).map {
      frame("append", items: [item("old\($0)", resolution: $0 == 0 ? "4K" : "1080p")])
    }.joined()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: preview, finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "restart"), apiService: api, capacityBytes: 64 * 1024)
    session.filterForm = ["resolution": ["4K"]]
    session.start(); try await until { session.retainedCount == 11 }
    session.stop(); try await settled(session)
    XCTAssertEqual(session.rows.count, 1)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body:
      (0..<7).map { frame("append", items: [item("new\($0)")]) }.joined()
        + frame("replace", items: [item("final")], sources: []))
    session.restart(); try await settled(session)
    XCTAssertFalse(session.reachedCapacity, "清掉的原页不再占旧展示预算，只有可见的一条仍被引用")
    XCTAssertTrue(session.initialComplete)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["final"])
  }

  func testDiscardedRetryPreviewsDoNotAccumulateCapacity() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("base")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "retry"), apiService: api, capacityBytes: 64 * 1024)
    session.start(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1,
      body: (0..<10).map { frame("append", items: [item("kept\($0)")]) }.joined(), finish: false)
    session.continueSearch(); try await until { session.retainedCount == 11 }
    session.stop(); try await settled(session)
    PaginationURLProtocol.enqueue(source: "a", page: 1, body:
      (0..<40).map { frame("append", items: [item("ignored\($0)"), item("other\($0)")]) }.joined()
        + frame("replace", items: [item("final")], sources: [fact("a", page: 1, more: false)]))
    session.continueSearch(); try await settled(session)
    XCTAssertFalse(session.reachedCapacity)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["base", "final"])
    XCTAssertFalse(session.canContinue)
  }

  func testKeywordEntryKeepsColonQueryOnTitleEndpoint() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("title")], sources: []))
    let vm = SearchViewModel(apiService: api)
    vm.searchType = .resource; vm.query = "Star:Trek"
    await vm.autoSearch()
    let session = try XCTUnwrap(vm.pagedSearch)
    try await settled(session)
    XCTAssertEqual(PaginationURLProtocol.requests.first?.path, "/api/v1/search/title/stream")
    XCTAssertEqual(PaginationURLProtocol.requests.first?.keyword, "Star:Trek")
    XCTAssertEqual(session.rows.count, 1)
  }

  func testRestartAfterExplicitBypassReappliesSelectedRules() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.rulesBody = #"{"value":[{"id":"hard","name":"h","include":"keep"}]}"#
    PaginationURLProtocol.holdRules = true
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("keep"), item("other")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 2 && PaginationURLProtocol.hasHeldRule }
    session.stop(); session.bypassPendingRules(); try await settled(session)
    XCTAssertEqual(session.rows.count, 2)
    PaginationURLProtocol.holdRules = false
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("keep"), item("other")], sources: []))
    session.restart(); try await settled(session)
    XCTAssertFalse(session.rulesBypassed)
    XCTAssertEqual(session.rows.map { $0.context.torrent_info?.title }, ["keep"])
  }

  func testRulesPendingStopRequiresExplicitWholeSearchBypass() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.holdRules = true
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("partial")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 1 }
    session.stop()
    XCTAssertTrue(session.rulePending)
    XCTAssertTrue(session.isPreparing)
    XCTAssertTrue(session.rows.isEmpty)
    session.bypassPendingRules(); try await settled(session)
    XCTAssertTrue(session.rulesBypassed)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertEqual(UserDefaults.standard.string(forKey: key), "hard")
  }

  func testCapacityStopsBeforeOversizedFrameAndRetainsAcceptedPreview() async throws {
    let api = try service()
    let huge = String(repeating: "x", count: 50_000)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body:
      frame("append", items: [item("small")]) + frame("append", items: [item(huge)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api, capacityBytes: 64 * 1024)
    session.start(); try await settled(session)
    XCTAssertTrue(session.reachedCapacity)
    XCTAssertEqual(session.rows.count, 1)
    XCTAssertFalse(session.canContinue)
    XCTAssertFalse(session.canRestart)
    XCTAssertFalse(session.initialComplete)
  }

  func testSessionChangeCannotPublishNewAccountResults() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("old")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 1 }
    api.replaceSessionForTesting(baseURL: "https://other.local", token: "other", currentUser: nil)
    XCTAssertFalse(session.isBusy)
    XCTAssertFalse(session.rulePending)
    XCTAssertTrue(session.rows.isEmpty)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
  }

  func testSameAccountTokenRefreshFinishesCollectionWithoutPublishingPreview() async throws {
    let api = try service()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("append", items: [item("old")]), finish: false)
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.retainedCount == 1 }
    let identity = api.uiIdentity
    api.replaceSessionForTesting(baseURL: api.baseURL, token: "refreshed", currentUser: api.currentUser)
    XCTAssertEqual(api.uiIdentity, identity, "此路径不会依靠根视图重建收尾")
    XCTAssertFalse(session.isBusy)
    XCTAssertFalse(session.rulePending)
    XCTAssertFalse(session.canContinue)
    XCTAssertFalse(session.canRestart)
    XCTAssertNotNil(session.errorMessage)
    session.continueSearch(); session.restart(); session.updateProjection()
    await Task.yield()
    XCTAssertTrue(session.rows.isEmpty)
    XCTAssertEqual(PaginationURLProtocol.requests.count, 1)
  }

  func testPermissionRevocationFinishesPendingRulesAndRejectsLatePublication() async throws {
    let api = try service(admin: true)
    let key = "selectedCustomFilterRuleId_\(try XCTUnwrap(api.profileKey))"
    UserDefaults.standard.set("hard", forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }
    PaginationURLProtocol.holdRules = true
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [item("old")], sources: [fact("a", page: 0)]))
    let session = ResourceSearchSession(query: .init(keyword: "test"), apiService: api)
    session.start(); try await until { session.isPreparing && PaginationURLProtocol.hasHeldRule }
    api.replaceSessionForTesting(baseURL: api.baseURL, token: "test",
      currentUser: Token(access_token: "test", token_type: "bearer", super_user: FlexibleBool(false),
        permissions: ["search": false], user_id: 929, user_name: "pagination-test", avatar: nil))
    XCTAssertFalse(session.isBusy)
    XCTAssertFalse(session.rulePending)
    XCTAssertFalse(session.canReapplyRules)
    XCTAssertFalse(session.canContinue)
    PaginationURLProtocol.finishHeldRules()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertTrue(session.rows.isEmpty)
    XCTAssertFalse(session.isBusy)
  }

  func testBothSSEReadersSharePrefixHeadersCookiesAndHTTPFailures() async throws {
    let api = try service()
    let cookie = try XCTUnwrap(HTTPCookie(properties: [
      .domain: "pagination-tests.local", .path: "/mp/api/v1", .name: "resource_token", .value: "first", .secure: "TRUE",
    ]))
    api.replaceSessionForTesting(baseURL: "https://pagination-tests.local/mp", token: "test", currentUser: api.currentUser, cookies: [cookie])
    let query = ResourceSearchQuery(keyword: "a&b + 中文", sites: "1,2")
    for paged in [false, true] {
      PaginationURLProtocol.enqueue(source: nil, page: 0, body: frame("replace", items: [], sources: []),
        headers: ["Set-Cookie": "resource_token=updated; Path=/mp/api/v1; Secure"])
      if paged {
        try await api.readResourceSearchPage(query: query, source: nil, page: 0, maximumEventBytes: { 8192 }) { _, _ in }
      } else {
        for try await _ in api.searchTitleStream(keyword: query.keyword, sites: query.sites) {}
      }
      let request = try XCTUnwrap(PaginationURLProtocol.requests.last)
      XCTAssertEqual(request.path, "/mp/api/v1/search/title/stream")
      XCTAssertEqual(request.keyword, query.keyword)
      XCTAssertEqual(request.sites, "1,2")
      XCTAssertEqual(request.raw.value(forHTTPHeaderField: "Authorization"), "Bearer test")
      XCTAssertEqual(request.raw.value(forHTTPHeaderField: "Cookie"), "resource_token=\(paged ? "updated" : "first")")
      XCTAssertEqual(request.raw.value(forHTTPHeaderField: "Accept"), "text/event-stream")
      XCTAssertEqual(request.raw.value(forHTTPHeaderField: "X-MoviePilot-Locale"), "zh-CN")
      XCTAssertEqual(request.raw.value(forHTTPHeaderField: "Accept-Language"), "zh-CN")
      for status in [401, 403, 500] {
        PaginationURLProtocol.enqueue(source: nil, page: 0, body: "", status: status)
        do {
          if paged {
            try await api.readResourceSearchPage(query: query, source: nil, page: 0, maximumEventBytes: { 8192 }) { _, _ in XCTFail("错误响应不能交付事件") }
          } else {
            for try await _ in api.searchTitleStream(keyword: query.keyword, sites: nil) { XCTFail("错误响应不能交付事件") }
          }
          XCTFail("HTTP \(status) 应失败")
        } catch {
          if status == 500 {
            guard case APIError.serverMessage(let message) = error else { XCTFail("\(error)"); continue }
            XCTAssertEqual(message, "HTTP Error 500")
          } else {
            guard case APIError.unauthorized = error else { XCTFail("\(error)"); continue }
          }
        }
      }
    }
    XCTAssertEqual(PaginationURLProtocol.requests.count, 8, "资源搜索错误不能自动重连")
  }

  func testPageReaderRechecksByteAndItemLimitsAfterEachEvent() async throws {
    let api = try service()
    let firstTitle = String(repeating: "a", count: 1200)
    let first = item(firstTitle)
    for second in [[item(String(repeating: "b", count: 600))], [item("b"), item("c")]] {
      PaginationURLProtocol.enqueue(source: nil, page: 0, body:
        frame("append", items: [first]) + frame("append", items: second))
      var received = 0
      do {
        try await api.readResourceSearchPage(query: .init(keyword: "limits"), source: nil, page: 0,
          maximumEventBytes: { received == 0 ? 8192 : 512 }
        ) { event, _ in
          received += 1
          XCTAssertEqual(event.items?.first?.torrent_info?.title, firstTitle)
        }
        XCTFail("下一帧必须使用收紧后的字节和对象数量预算")
      } catch {
        guard case ResourceSearchFailure.capacity = error else { XCTFail("\(error)"); continue }
      }
      XCTAssertEqual(received, 1)
    }
  }

  func testBoundedPageReaderPreservesBOMLineEndingsMultilineAndTail() async throws {
    let api = try service()
    for newline in ["\n", "\r\n", "\r"] {
      let body = "\u{FEFF}data: {\"type\":\"progress\",\(newline)data: \"text\":\"中文\"}\(newline)\(newline)"
        + "data: {\"type\":\"progress\",\"text\":\"second\"}\(newline)\(newline)"
        + "data: {\"type\":\"done\",\"text\":\"tail\"}"
      PaginationURLProtocol.enqueue(source: nil, page: 0, body: body)
      var texts: [String] = []
      try await api.readResourceSearchPage(query: .init(keyword: "framing"), source: nil, page: 0,
        maximumEventBytes: { 8192 }
      ) { event, _ in
        if let text = event.text { texts.append(text) }
      }
      XCTAssertEqual(texts, ["中文", "second", "tail"])
    }
  }

  func testProductionPageReaderBackpressureAndCompleteEventCount() async throws {
    let api = try service()
    let body = (0..<200).map { frame("append", items: [item("item\($0)")]) }.joined()
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: body)
    let baselineStart = ContinuousClock.now
    var baselineCount = 0
    for try await _ in api.searchTitleStream(keyword: "throughput", sites: nil) { baselineCount += 1 }
    let baselineTime = baselineStart.duration(to: .now)
    PaginationURLProtocol.enqueue(source: nil, page: 0, body: body)
    var received = 0
    let start = ContinuousClock.now
    try await api.readResourceSearchPage(query: .init(keyword: "throughput"), source: nil, page: 0, maximumEventBytes: { 8192 }) { _, _ in
      received += 1
      await Task.yield()
    }
    XCTAssertEqual(received, 200)
    XCTAssertEqual(baselineCount, received)
    XCTAssertLessThan(start.duration(to: .now), max(.seconds(1), baselineTime * 20))
    print("Resource page SSE: events=\(received), baseline=\(baselineTime), backpressure=\(start.duration(to: .now))")
  }
}

@MainActor
final class ResourceSearchProcessorTests: XCTestCase {
  private func contexts(_ count: Int) throws -> [Context] {
    try (0..<count).map { i in try context(item("Resource \(i)", resolution: i % 2 == 0 ? "4K" : "1080p", seeders: i)) }
  }
  private func inputs(_ values: [Context], prefix: String = "a", offset: Int = 0) -> [ResourceFilterInput] {
    values.enumerated().map { .init(context: $0.element, id: "\(prefix)\($0.offset)", order: offset + $0.offset) }
  }

  func testNewPageAndSortReuseStaticRulesWhileReplacementReprocessesOnlyThatPage() async throws {
    let worker = ResourceSearchProcessor()
    let rule = ResourceRule(CustomRule(id: "hard", name: "h", include: ["Resource"]))
    await worker.configure(.init(hard: rule))
    try await worker.ingest(key: "a", inputs: inputs(contexts(200)), replacing: true, now: Date())
    _ = try await worker.project(settings: .init(), evaluationTime: Date())
    try await worker.ingest(key: "b", inputs: inputs(contexts(20), prefix: "b", offset: 200), replacing: true, now: Date())
    let settings = ResourceProjectionSettings(filters: ["resolution": ["4K"]], sortField: "做种", sortType: "降序")
    let projection = try await worker.project(settings: settings, evaluationTime: Date())
    XCTAssertEqual(projection.rows.count, 110)
    let evaluated = await worker.staticEvaluations
    XCTAssertEqual(evaluated, 220)
    _ = try await worker.project(settings: .init(sortField: "大小", sortType: "升序"), evaluationTime: nil)
    let afterSort = await worker.staticEvaluations
    XCTAssertEqual(afterSort, 220)
    try await worker.ingest(key: "b", inputs: inputs(contexts(2), prefix: "b", offset: 200), replacing: true, now: Date())
    let final = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertEqual(final.rows.count, 202)
    let afterReplace = await worker.staticEvaluations
    XCTAssertEqual(afterReplace, 222)
    let compiled = await worker.compiledPatterns
    XCTAssertEqual(compiled, 1)
  }

  func testRegexPreparationPreservesShortCircuitAndDeferredSoftErrors() async throws {
    let worker = ResourceSearchProcessor()
    await worker.configure(.init(hard: ResourceRule(CustomRule(id: "h", name: "h", include: [".*", "["]))))
    try await worker.ingest(key: "a", inputs: inputs(contexts(1)), replacing: true, now: Date())
    let result = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertEqual(result.rows.count, 1)
    await worker.configure(.init(
      hard: ResourceRule(CustomRule(id: "h", name: "h", include: ["NEVER"])),
      soft: ResourceRule(CustomRule(id: "s", name: "s", include: ["["]))))
    let excluded = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertTrue(excluded.rows.isEmpty, "硬规则排除后不可执行错误软规则")
    await worker.configure(.init(soft: ResourceRule(CustomRule(id: "s", name: "s", include: ["["]))))
    do { _ = try await worker.project(settings: .init(), evaluationTime: Date()); XCTFail("放宽硬规则后应首次执行软规则") }
    catch { XCTAssertTrue(error is CustomFilterService.FilterError) }
    await worker.configure(.none)
    let recovered = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertEqual(recovered.rows.count, 1)
  }

  func testReplacedPreviewErrorDoesNotPoisonFinalOrEmptyPage() async throws {
    for finalCount in [0, 1] {
      let worker = ResourceSearchProcessor()
      await worker.configure(.init(hard: ResourceRule(CustomRule(id: "h", name: "h", include: ["^Good", "["]))))
      try await worker.ingest(key: "a", inputs: inputs([context(item("Bad"))]), replacing: true, now: Date())
      let final = finalCount == 0 ? [] : try [context(item("Good"))]
      try await worker.ingest(key: "a", inputs: inputs(final), replacing: true, now: Date())
      let projected = try await worker.project(settings: .init(), evaluationTime: Date())
      XCTAssertEqual(projected.rows.count, finalCount)
    }
  }

  func testProjectionFailureCannotLeaveLaterBatchesWithOldFilterSelection() async throws {
    let worker = ResourceSearchProcessor()
    try await worker.ingest(key: "a", inputs: inputs([context(item("A", resolution: "4K"))]), replacing: true, now: Date())
    try await worker.ingest(key: "b", inputs: inputs([context(item("B", resolution: "1080p"))], prefix: "b", offset: 1), replacing: true, now: Date())
    _ = try await worker.project(settings: .init(), evaluationTime: Date())
    await worker.configure(.init(hard: ResourceRule(CustomRule(id: "h", name: "h", include: ["A", "["]))))
    let selected = ResourceProjectionSettings(filters: ["resolution": ["4K"]])
    do { _ = try await worker.project(settings: selected, evaluationTime: Date()); XCTFail("应报告非法规则") }
    catch { XCTAssertTrue(error is CustomFilterService.FilterError) }
    await worker.configure(.none)
    let recovered = try await worker.project(settings: selected, evaluationTime: Date())
    XCTAssertEqual(recovered.rows.map(\.id), ["a0"])
  }

  func testTimeSnapshotRefreshesOnlyTimeChecksAndSoftRuleWhenFirstAdmitted() async throws {
    let worker = ResourceSearchProcessor()
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let date = try XCTUnwrap(formatter.date(from: "2026-01-01 12:00:00"))
    let value = try context(item("match", date: "2026-01-01 12:00:00"))
    await worker.configure(.init(
      hard: ResourceRule(CustomRule(id: "h", name: "h", publish_time: "10")),
      soft: ResourceRule(CustomRule(id: "s", name: "s", include: ["nomatch"])) ))
    try await worker.ingest(key: "a", inputs: inputs([value]), replacing: true, now: date)
    let early = try await worker.project(settings: .init(), evaluationTime: date)
    XCTAssertTrue(early.rows.isEmpty)
    let frozen = try await worker.project(settings: .init(sortField: "做种", sortType: "降序"), evaluationTime: nil)
    XCTAssertTrue(frozen.rows.isEmpty)
    let later = try await worker.project(settings: .init(), evaluationTime: date.addingTimeInterval(660))
    XCTAssertEqual(later.rows.count, 1)
    XCTAssertEqual(later.rows.first?.softRejected, true)
    let count = await worker.staticEvaluations
    XCTAssertEqual(count, 2)
  }

  func testMissingDateStaysZeroAndRemovedSelectedOptionRemainsClearable() async throws {
    let worker = ResourceSearchProcessor()
    await worker.configure(.init(hard: ResourceRule(CustomRule(id: "h", name: "h", publish_time: "1"))))
    try await worker.ingest(key: "a", inputs: inputs([context(item("nodate", resolution: "4K", date: "bad"))]), replacing: true, now: Date())
    let later = try await worker.project(settings: .init(), evaluationTime: Date().addingTimeInterval(5000))
    XCTAssertTrue(later.rows.isEmpty)
    await worker.configure(.none)
    _ = try await worker.project(settings: .init(), evaluationTime: Date())
    try await worker.ingest(key: "a", inputs: inputs([context(item("changed", resolution: "1080p"))]), replacing: true, now: Date())
    let selected = ResourceProjectionSettings(filters: ["resolution": ["4K"]])
    let replaced = try await worker.project(settings: selected, evaluationTime: Date())
    XCTAssertTrue(replaced.rows.isEmpty)
    XCTAssertEqual(Set(replaced.options["resolution"] ?? []), ["4K", "1080p"])
    let disabled = await worker.disabledOptions(for: "resolution", filters: selected.filters)
    XCTAssertFalse(disabled.contains("4K"))
  }

  func testSoftPartitionStableTieAndRawRestorationAfterRuleChange() async throws {
    let worker = ResourceSearchProcessor()
    let values = try [context(item("bad", seeders: 99)), context(item("good1", seeders: 1)), context(item("good2", seeders: 1))]
    await worker.configure(.init(soft: ResourceRule(CustomRule(id: "s", name: "s", include: ["good"]))))
    try await worker.ingest(key: "a", inputs: inputs(values), replacing: true, now: Date())
    let sorted = try await worker.project(settings: .init(sortField: "做种", sortType: "降序"), evaluationTime: Date())
    XCTAssertEqual(sorted.rows.map(\.id), ["a1", "a2", "a0"])
    await worker.configure(.init(hard: ResourceRule(CustomRule(id: "h", name: "h", include: ["nothing"]))))
    let none = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertTrue(none.rows.isEmpty)
    await worker.configure(.none)
    let restored = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertEqual(restored.rows.count, 3)
    XCTAssertTrue(restored.rows.allSatisfy { !$0.softRejected })
  }

  func testRuleContractAcrossBatchAndIncrementalFiltering() async throws {
    let value = try context([
      "torrent_info": ["title": "RESOURCE", "description": "desc", "labels": ["tag"],
        "size": 8 * 1024 * 1024, "seeders": 5, "pubdate": "invalid"],
      "meta_info": ["total_episode": 2],
    ])
    let cases: [(CustomRule, Bool?)] = [
      (.init(id: "r", name: "r", include: [""]), true),
      (.init(id: "r", name: "r", exclude: [""]), false),
      (.init(id: "r", name: "r", include: ["", "["]), true),
      (.init(id: "r", name: "r", include: ["[", ""]), nil),
      (.init(id: "r", name: "r", include: ["resource.*desc.*tag"]), true),
      (.init(id: "r", name: "r", include: ["NEVER"], seeders: "invalid"), false),
      (.init(id: "r", name: "r", exclude: ["", "["]), false),
      (.init(id: "r", name: "r", exclude: ["[", ""]), nil),
      (.init(id: "r", name: "r", size_range: "4-4"), true),
      (.init(id: "r", name: "r", size_range: "> 4"), true),
      (.init(id: "r", name: "r", size_range: "< 4"), true),
      (.init(id: "r", name: "r", size_range: "> 5"), false),
      (.init(id: "r", name: "r", size_range: "1024"), false),
      (.init(id: "r", name: "r", size_range: "1-2-3"), nil),
      (.init(id: "r", name: "r", seeders: " 5 "), true),
      (.init(id: "r", name: "r", seeders: "6"), false),
      (.init(id: "r", name: "r", seeders: "5-6"), nil),
      (.init(id: "r", name: "r", publish_time: "0-1-2"), true),
      (.init(id: "r", name: "r", publish_time: "1"), false),
      (.init(id: "r", name: "r", publish_time: "-1"), nil),
    ]
    for (index, test) in cases.enumerated() {
      let (rule, expected) = test
      let worker = ResourceSearchProcessor()
      await worker.configure(.init(hard: ResourceRule(rule)))
      try await worker.ingest(key: "page", inputs: inputs([value]), replacing: true, now: Date())
      if let expected {
        XCTAssertEqual(try CustomFilterService.matchRule(context: value, rule: rule), expected, "case \(index)")
        XCTAssertEqual(try CustomFilterService.filter(contexts: [value], with: rule).count, expected ? 1 : 0)
        let result = try await worker.project(settings: .init(), evaluationTime: Date())
        XCTAssertEqual(result.rows.count, expected ? 1 : 0, "case \(index)")
      } else {
        XCTAssertThrowsError(try CustomFilterService.filter(contexts: [value], with: rule)) {
          XCTAssertTrue($0 is CustomFilterService.FilterError)
        }
        do { _ = try await worker.project(settings: .init(), evaluationTime: Date()); XCTFail("case \(index)") }
        catch { XCTAssertTrue(error is CustomFilterService.FilterError) }
      }
    }
    let sparse = try context([:])
    let skipped = CustomRule(id: "r", name: "r", size_range: "invalid-size", publish_time: "invalid-time")
    XCTAssertTrue(try CustomFilterService.matchRule(context: sparse, rule: skipped))
    let worker = ResourceSearchProcessor()
    await worker.configure(.init(hard: ResourceRule(skipped)))
    try await worker.ingest(key: "sparse", inputs: inputs([sparse]), replacing: true, now: Date())
    let projected = try await worker.project(settings: .init(), evaluationTime: Date())
    XCTAssertEqual(projected.rows.count, 1)
  }

  func testSharedFieldSelectionAndOrderingAcrossIncrementalPages() async throws {
    let values = try [context(item("other", resolution: " 4K ", seeders: 9)),
      context(item("keep-low", resolution: "", seeders: 1)),
      context(item("keep-high", resolution: "4K", seeders: 5))]
    let worker = ResourceSearchProcessor()
    await worker.configure(.init(soft: ResourceRule(.init(id: "soft", name: "s", include: ["keep"]))))
    try await worker.ingest(key: "a", inputs: inputs(Array(values.prefix(2))), replacing: true, now: Date())
    try await worker.ingest(key: "b", inputs: inputs([values[2]], prefix: "b", offset: 2), replacing: true, now: Date())
    let originals = Dictionary(uniqueKeysWithValues: zip(["a0", "a1", "b0"], values))
    for field in SortField.allCases {
      for type in SortType.allCases {
        let projected = try await worker.project(
          settings: .init(sortField: field.rawValue, sortType: type.rawValue), evaluationTime: Date())
        var legacy = values
        legacy[0].isFilteredOut = true
        let expected = TorrentsResultView<EmptyView>.orderResults(legacy, by: field, type: type)
        XCTAssertEqual(projected.rows.map { originals[$0.id]?.torrent_info?.title }, expected.map { $0.torrent_info?.title })
        XCTAssertEqual(projected.rows.last?.id, "a0")
      }
    }
    let filtered = try await worker.project(settings: .init(filters: ["resolution": ["4K"]], sortField: "做种", sortType: "降序"), evaluationTime: nil)
    XCTAssertEqual(filtered.rows.map(\.id), ["b0", "a0"])
    XCTAssertEqual(ResourceResultSemantics.sortedOptions(filtered.options)["resolution"], ["4K", "无"])
    let empty = try await worker.project(settings: .init(filters: ["freeState": ["FREE"]]), evaluationTime: nil)
    XCTAssertTrue(empty.rows.isEmpty, "缺失促销字段不生成或匹配促销选项")
    let cleared = try await worker.project(settings: .init(sortField: "做种", sortType: "降序"), evaluationTime: nil)
    XCTAssertEqual(cleared.rows.map(\.id), ["b0", "a1", "a0"])
  }

  func testBatchAndIncrementalProcessingFor2002000And10000() async throws {
    let rule = CustomRule(id: "bench", name: "bench", include: ["Resource.*"], exclude: ["NEVER"], publish_time: "0")
    for count in [200, 2000, 10000] {
      let values = try contexts(count)
      let baselineStart = ContinuousClock.now
      let baseline = try CustomFilterService.filter(contexts: values, with: rule)
      let baselineTime = baselineStart.duration(to: .now)
      let worker = ResourceSearchProcessor()
      let start = ContinuousClock.now
      await worker.configure(.init(hard: ResourceRule(rule)))
      for offset in stride(from: 0, to: count, by: 200) {
        try await worker.ingest(key: "\(offset)", inputs: inputs(Array(values[offset..<min(offset + 200, count)]), prefix: "\(offset)-", offset: offset), replacing: true, now: Date())
      }
      let processed = start.duration(to: .now)
      let publishStart = ContinuousClock.now
      let result = try await worker.project(settings: .init(sortField: "做种", sortType: "降序"), evaluationTime: Date())
      let publishTime = publishStart.duration(to: .now)
      XCTAssertEqual(result.rows.count, baseline.count)
      let actual = await worker.staticEvaluations
      let compiled = await worker.compiledPatterns
      XCTAssertEqual(actual, count)
      XCTAssertEqual(compiled, 2)
      var usage = rusage()
      getrusage(0, &usage)
      print("Resource benchmark process high-water RSS bytes=\(usage.ru_maxrss)")
      print("Resource benchmark n=\(count): shared-batch=\(baselineTime), incremental=\(processed), background-sort/projection=\(publishTime), matches=\(actual), regex=\(compiled)")
    }
  }
}

private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
private func item(_ title: String, resolution: String = "4K", seeders: Int = 1, date: String = "2026-01-01 12:00:00") -> [String: Any] {
  ["torrent_info": ["title": title, "site_name": "site", "size": 1024, "seeders": seeders,
    "page_url": "same-id", "pubdate": date], "meta_info": ["resource_pix": resolution]]
}
@MainActor private func context(_ item: [String: Any]) throws -> Context { try JSONDecoder().decode(Context.self, from: json(item)) }
private func fact(_ source: String, page: Int, more: Bool = true, error: String? = nil) -> [String: Any] {
  var result: [String: Any] = ["source": source, "page": page, "can_continue": more, "site_name": source]
  if let error { result["error"] = error }
  return result
}
private func payload(_ type: String, items: [[String: Any]], sources: [[String: Any]]?, batch: (Int, Int)?, total: Int?) -> [String: Any] {
  var p: [String: Any] = ["type": type, "items": items, "total_items": total ?? items.count]
  if let sources { p["sources"] = sources }
  if let batch { p["replace_batch"] = true; p["batch_index"] = batch.0; p["batch_count"] = batch.1 }
  return p
}
private func event(_ type: String, items: [[String: Any]], sources: [[String: Any]]? = nil, batch: (Int, Int)? = nil, total: Int? = nil) throws -> SearchStreamEvent {
  try JSONDecoder().decode(SearchStreamEvent.self, from: json(payload(type, items: items, sources: sources, batch: batch, total: total)))
}
private func frame(_ type: String, items: [[String: Any]], sources: [[String: Any]]? = nil, batch: (Int, Int)? = nil, total: Int? = nil) -> String {
  "data: \(String(data: try! json(payload(type, items: items, sources: sources, batch: batch, total: total)), encoding: .utf8)!)\n\n"
}
private func stageFrame(_ stage: String) -> String {
  "data: \(String(data: try! json(["type": "progress", "stage": stage]), encoding: .utf8)!)\n\n"
}

nonisolated private final class PaginationURLProtocol: URLProtocol, @unchecked Sendable {
  struct Request: Sendable {
    let raw: URLRequest
    let path: String; let source: String?; let page: Int; let keyword: String?
    let manual: String?; let season: String?; let sites: String?
  }
  struct Stub: Sendable { let body: String; let finish: Bool; var status = 200; var headers: [String: String] = [:] }
  private static let lock = NSLock()
  nonisolated(unsafe) private static var plans: [String: [Stub]] = [:]
  nonisolated(unsafe) private static var recorded: [Request] = []
  nonisolated(unsafe) private static var holdingRules = false
  nonisolated(unsafe) private static var ruleBody = #"{"value":[]}"#
  nonisolated(unsafe) private static var heldRules: [PaginationURLProtocol] = []
  nonisolated(unsafe) private static var heldSearches: [PaginationURLProtocol] = []
  private let deliveryLock = NSRecursiveLock()
  private var stopped = false
  static var rulesBody: String {
    get { lock.withLock { ruleBody } }
    set { lock.withLock { ruleBody = newValue } }
  }
  static var hasHeldRule: Bool { lock.withLock { !heldRules.isEmpty } }
  static func finishHeldRules() {
    let held = lock.withLock { let result = heldRules; heldRules = []; return result }
    for entry in held {
      entry.deliveryLock.withLock { if !entry.stopped { entry.client?.urlProtocolDidFinishLoading(entry) } }
    }
  }
  static var requests: [Request] { lock.withLock { recorded } }
  static var holdRules: Bool {
    get { lock.withLock { holdingRules } }
    set { lock.withLock { holdingRules = newValue } }
  }
  static func reset() { lock.withLock { plans = [:]; recorded = []; holdingRules = false; heldRules = []; heldSearches = []; ruleBody = #"{"value":[]}"# } }
  static func sendHeldSearch(_ body: String, finish: Bool = false) -> Bool {
    guard let entry = lock.withLock({ heldSearches.last }) else { return false }
    return entry.deliveryLock.withLock {
      guard !entry.stopped else { return false }
      entry.client?.urlProtocol(entry, didLoad: Data(body.utf8))
      if finish { entry.client?.urlProtocolDidFinishLoading(entry) }
      return true
    }
  }
  static func enqueue(source: String?, page: Int, body: String, finish: Bool = true, status: Int = 200, headers: [String: String] = [:]) {
    lock.withLock { plans["\(source ?? "initial"):\(page)", default: []].append(.init(body: body, finish: finish, status: status, headers: headers)) }
  }
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "pagination-tests.local" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ key: String) -> String? { params.first { $0.name == key }?.value }
    let source = value("source"), page = Int(value("page") ?? "0") ?? 0
    let stub: Stub = Self.lock.withLock {
      if !url.path.contains("/search/") {
        if Self.holdingRules { Self.heldRules.append(self) }
        return .init(body: Self.ruleBody, finish: !Self.holdingRules)
      }
      Self.recorded.append(.init(raw: request, path: url.path, source: source, page: page, keyword: value("keyword"), manual: value("manual_paging"), season: value("season"), sites: value("sites")))
      let key = "\(source ?? "initial"):\(page)"
      if var entries = Self.plans[key], !entries.isEmpty {
        let first = entries.removeFirst(); Self.plans[key] = entries
        if !first.finish { Self.heldSearches.append(self) }
        return first
      }
      return .init(body: "data: {\"type\":\"error\",\"message\":\"unexpected request\"}\n\n", finish: true)
    }
    let headers = ["Content-Type": url.path.contains("/search/") ? "text/event-stream" : "application/json"].merging(stub.headers) { _, value in value }
    let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
    if stub.finish { client?.urlProtocolDidFinishLoading(self) }
  }
  override func stopLoading() { deliveryLock.withLock { stopped = true } }
}

@MainActor private func resourceNavigationControllers(in controller: UIViewController) -> [UINavigationController] {
  (controller as? UINavigationController).map { [$0] } ?? controller.children.flatMap { resourceNavigationControllers(in: $0) }
}
