import Combine
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubtitleSearchTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubtitleSearchURLProtocol.self))
    SubtitleSearchURLProtocol.reset()
  }

  override func tearDown() async throws {
    SubtitleSearchURLProtocol.reset()
    APIService.removeURLProtocolForTesting(SubtitleSearchURLProtocol.self)
  }

  func testPreviewPrependsAndCapsDisplayWhileBufferKeepsNewest() throws {
    var collector = SubtitleSearchCollector()
    for index in 0..<100 {
      XCTAssertTrue(try collector.receive(event(type: "append", items: [item(title: "\(index)")])))
    }
    XCTAssertFalse(collector.finalApplied)
    XCTAssertEqual(collector.bufferedPreviewCount, SubtitleSearchCollector.previewBufferLimit)
    XCTAssertEqual(collector.publishedItems.count, SubtitleSearchCollector.previewDisplayLimit)
    XCTAssertEqual(
      collector.publishedItems.map(\.title),
      (76...99).reversed().map(String.init)
    )
  }

  func testReplaceBecomesFinalAndLaterDoneDoesNotDuplicate() throws {
    var collector = SubtitleSearchCollector()
    _ = try collector.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertTrue(try collector.receive(event(type: "replace", items: [item(title: "最终")])))
    XCTAssertTrue(collector.finalApplied)
    XCTAssertEqual(collector.bufferedPreviewCount, 0)
    XCTAssertFalse(try collector.receive(event(type: "done", items: [item(title: "重复")])))
    XCTAssertEqual(collector.publishedItems.map(\.title), ["最终"])
  }

  func testDoneWithoutReplaceReplacesPreview() throws {
    var collector = SubtitleSearchCollector()
    _ = try collector.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertTrue(try collector.receive(event(type: "done", items: [item(title: "最终")])))
    XCTAssertEqual(collector.publishedItems.map(\.title), ["最终"])
  }

  func testEmptyDoneKeepsPreviewAndEmptyReplaceIgnoresLaterDone() throws {
    var kept = SubtitleSearchCollector()
    _ = try kept.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertFalse(try kept.receive(event(type: "done", items: [])))
    XCTAssertFalse(kept.finalApplied)
    XCTAssertEqual(kept.publishedItems.map(\.title), ["预览"])

    var replaced = SubtitleSearchCollector()
    _ = try replaced.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertTrue(try replaced.receive(event(type: "replace", items: [])))
    XCTAssertFalse(try replaced.receive(event(type: "done", items: [item(title: "迟到")])))
    XCTAssertTrue(replaced.publishedItems.isEmpty)
  }

  func testReplaceBatchesApplyOnlyWhenContiguousAndAppendBatchIsNotPreview() throws {
    var collector = SubtitleSearchCollector()
    _ = try collector.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertFalse(try collector.receive(batch(type: "replace", titles: ["甲"], index: 0, count: 2, total: 2)))
    XCTAssertFalse(collector.finalApplied)
    XCTAssertEqual(collector.publishedItems.map(\.title), ["预览"])
    XCTAssertTrue(try collector.receive(batch(type: "append", titles: ["乙"], index: 1, count: 2, total: 2)))
    XCTAssertEqual(collector.publishedItems.map(\.title), ["甲", "乙"])
  }

  func testOutOfOrderOrShortBatchThrowsIncompletePage() throws {
    var skipped = SubtitleSearchCollector()
    let skippedBatch = try batch(type: "append", titles: ["乙"], index: 1, count: 2, total: 2)
    XCTAssertThrowsError(try skipped.receive(skippedBatch)) { error in
      guard case ResourceSearchFailure.incompletePage = error else {
        return XCTFail("乱序分块应视为本页不完整：\(error)")
      }
    }

    var short = SubtitleSearchCollector()
    let first = try batch(type: "replace", titles: ["甲"], index: 0, count: 2, total: 2)
    XCTAssertFalse(try short.receive(first))
    let mismatched = try batch(type: "append", titles: ["乙"], index: 1, count: 2, total: 3)
    XCTAssertThrowsError(try short.receive(mismatched)) { error in
      guard case ResourceSearchFailure.incompletePage = error else {
        return XCTFail("数量不一致应视为本页不完整：\(error)")
      }
    }
  }

  func testHeartbeatDoesNotChangeTheList() throws {
    var collector = SubtitleSearchCollector()
    _ = try collector.receive(event(type: "append", items: [item(title: "预览")]))
    XCTAssertFalse(try collector.receive(event(type: "heartbeat")))
    XCTAssertEqual(collector.publishedItems.map(\.title), ["预览"])
    XCTAssertFalse(collector.finalApplied)
  }

  func testIntegerSizeAndEnclosureFragmentSurviveDecoding() throws {
    let enclosure = "https://sub.example/a.zip#mp_sig=abc&mp_purpose=subtitle_download:9"
    let info = try decodeSubtitle(
      #"{"title":"中字","size":2048,"enclosure":"\#(enclosure)","site_name":"站点"}"#
    )
    XCTAssertEqual(info.size, 2048)
    XCTAssertEqual(info.enclosure, enclosure)
    XCTAssertEqual(info.listIdentity, .enclosure(enclosure))

    let textual = try decodeSubtitle(#"{"size":12.5,"subtitle_id":"7"}"#)
    XCTAssertEqual(textual.size, 12.5)
    XCTAssertEqual(textual.subtitle_id, "7")
  }

  func testDownloadBodyKeepsFragmentAndEncodesNullSavePath() throws {
    let enclosure = "https://sub.example/a.zip#mp_sig=abc&mp_purpose=subtitle_download:9"
    let info = try decodeSubtitle(#"{"title":"中字","enclosure":"\#(enclosure)","site_cookie":"secret"}"#)
    let data = try JSONEncoder().encode(
      SubtitleDownloadRequest(
        subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: nil)
    )
    let json = try jsonObject(data)
    XCTAssertTrue(json["save_path"] is NSNull)
    XCTAssertEqual(json["media_source"] as? String, "themoviedb")
    XCTAssertEqual(json["media_id"] as? String, "550")
    let subtitle = try XCTUnwrap(json["subtitle_in"] as? [String: Any])
    XCTAssertEqual(subtitle["enclosure"] as? String, enclosure)
    XCTAssertEqual(subtitle["site_cookie"] as? String, "secret")
  }

  func testEmptySavePathThrowsInsteadOfBecomingNull() {
    let info = SubtitleInfo(title: "中字", enclosure: "https://sub.example/a.zip")
    XCTAssertThrowsError(
      try JSONEncoder().encode(
        SubtitleDownloadRequest(
          subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: " \n ")
      )
    ) { error in
      guard case SubtitleSearchFailure.emptySavePath = error else {
        return XCTFail("空白目录必须失败，不能编成 null：\(error)")
      }
    }
  }

  func testNonEmptySavePathIsSentUnchanged() throws {
    let info = SubtitleInfo(title: "中字")
    let data = try JSONEncoder().encode(
      SubtitleDownloadRequest(
        subtitle: info, mediaSource: "douban", mediaId: "42", savePath: " /media/电影 ")
    )
    let json = try jsonObject(data)
    XCTAssertEqual(json["save_path"] as? String, " /media/电影 ")
  }

  func testSubtitleEndpointsKeepSeasonZeroAndOmitPaging() throws {
    let api = service()
    let seasonZero = SubtitleSearchRequest(
      kind: .media(source: "themoviedb", mediaId: "550", type: "电影", season: 0, episode: 0),
      sites: "1,2",
      displayTitle: "电影",
      mediaInfo: nil
    )
    let streaming = try api.subtitleSearchEndpoint(for: seasonZero, streaming: true)
    let streamQuery = queryItems(in: streaming)
    XCTAssertTrue(streaming.hasPrefix("/search/subtitle/media/550/stream"))
    XCTAssertEqual(streamQuery["media_source"], "themoviedb")
    XCTAssertEqual(streamQuery["mtype"], "电影")
    XCTAssertEqual(streamQuery["season"], "0")
    XCTAssertEqual(streamQuery["episode"], "0")
    XCTAssertEqual(streamQuery["sites"], "1,2")
    XCTAssertNil(streamQuery["page"])
    XCTAssertNil(streamQuery["count"])
    XCTAssertNil(streamQuery["title"])
    XCTAssertNil(streamQuery["year"])
    XCTAssertNil(streamQuery["manual_paging"])
    XCTAssertNil(streamQuery["source"])

    let omitted = SubtitleSearchRequest(
      kind: .media(source: "themoviedb", mediaId: "550", type: nil, season: nil, episode: -1),
      sites: nil,
      displayTitle: nil,
      mediaInfo: nil
    )
    let omittedQuery = queryItems(in: try api.subtitleSearchEndpoint(for: omitted, streaming: false))
    XCTAssertEqual(omittedQuery["media_source"], "themoviedb")
    XCTAssertNil(omittedQuery["season"])
    XCTAssertNil(omittedQuery["episode"])
    XCTAssertNil(omittedQuery["mtype"])
    XCTAssertFalse(try api.subtitleSearchEndpoint(for: omitted, streaming: false).contains("/stream"))

    let negative = SubtitleSearchRequest(
      kind: .media(source: "themoviedb", mediaId: "550", type: "电视剧", season: -1, episode: nil),
      sites: nil,
      displayTitle: nil,
      mediaInfo: nil
    )
    XCTAssertNil(queryItems(in: try api.subtitleSearchEndpoint(for: negative, streaming: true))["season"])

    let title = SubtitleSearchRequest(
      kind: .title(keyword: "星际"),
      sites: "8",
      displayTitle: "星际",
      mediaInfo: nil
    )
    let titleStream = try api.subtitleSearchEndpoint(for: title, streaming: true)
    let titleQuery = queryItems(in: titleStream)
    XCTAssertEqual(String(titleStream.split(separator: "?").first ?? ""), "/search/subtitle/title/stream")
    XCTAssertEqual(titleQuery["keyword"], "星际")
    XCTAssertEqual(titleQuery["sites"], "8")
    XCTAssertNil(titleQuery["page"])
    XCTAssertNil(titleQuery["manual_paging"])
    XCTAssertEqual(
      String(try api.subtitleSearchEndpoint(for: title, streaming: false).split(separator: "?").first ?? ""),
      "/search/subtitle/title"
    )
  }

  func testRecognizedMediaKeepsSeasonZeroAndDropsMusic() {
    let handler = MediaActionHandler()
    let movie = MediaInfo(tmdb_id: 550, title: "搏击俱乐部", type: "电影", season: 0)
    let request = handler.subtitleSearchRequest(for: movie, sites: "3")
    XCTAssertEqual(request?.initialMediaIdentity?.source, "themoviedb")
    XCTAssertEqual(request?.initialMediaIdentity?.mediaId, "550")
    if case .media(_, _, _, let season, let episode) = request?.kind {
      XCTAssertEqual(season, 0)
      XCTAssertNil(episode)
    } else {
      XCTFail("有身份的电影应走媒体字幕搜索")
    }
    XCTAssertNil(handler.subtitleSearchRequest(for: MediaInfo(title: "只有标题", type: "电影"), sites: nil))
    XCTAssertNil(handler.subtitleSearchRequest(for: MediaInfo(tmdb_id: 0, title: "零", type: "电影"), sites: nil))
    XCTAssertNil(handler.subtitleSearchRequest(for: MediaInfo(tmdb_id: 1, title: "歌", type: "音乐"), sites: nil))
    XCTAssertNil(MediaActionHandler.titleSubtitleSearchRequest(keyword: "  ", sites: "1"))
    XCTAssertFalse(SubtitleSearchRequest.supportsSubtitleSearch(type: "合集"))
    XCTAssertFalse(SubtitleSearchRequest.supportsSubtitleSearch(type: "电影", isCollection: true))
  }

  func testEmptyDoneKeepsAlreadyShownRows() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"append","items":[{"title":"预览","enclosure":"https://sub.example/preview"}]}"#,
      #"data: {"type":"done","items":[]}"#
    )
    let session = session(api: api, keyword: "保留预览")
    session.start()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["预览"])
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(
      SubtitleSearchURLProtocol.requests.map(\.path),
      ["/api/v1/search/subtitle/title/stream"]
    )
  }

  func testBusinessErrorAfterFinalReplaceKeepsRows() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"replace","items":[{"title":"最终","enclosure":"https://sub.example/final"}]}"#,
      #"data: {"type":"error","message":"搜索失败，请稍后重试"}"#
    )
    let session = session(api: api, keyword: "保留最终")
    session.start()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["最终"])
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(
      SubtitleSearchURLProtocol.requests.map(\.path),
      ["/api/v1/search/subtitle/title/stream"]
    )
  }

  func testBusinessErrorDoesNotUseHTTPFallback() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"append","items":[{"title":"预览"}]}"#,
      #"data: {"type":"error","message":"plain","message_i18n":"没有可用字幕站点"}"#
    )
    let session = session(api: api, keyword: "错误")
    session.start()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["预览"])
    XCTAssertTrue(session.canRestart)
    XCTAssertEqual(session.errorMessage, "没有可用字幕站点")
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.map(\.path), ["/api/v1/search/subtitle/title/stream"])
  }

  func testSSEIntegerProxyFlagsMatchResourceDecodingWithoutHTTPFallback() async throws {
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"append","items":[{"site":1,"site_proxy":0,"title":"不使用代理","enclosure":"https://sub.example/0#signed"},{"site":2,"site_proxy":1,"title":"使用代理","enclosure":"https://sub.example/1#signed"}]}"#,
      #"data: {"type":"done"}"#
    )
    let search = session(api: service(), keyword: "代理字段")
    search.start()
    try await until { search.didFinish }
    XCTAssertEqual(search.state, .completed)
    XCTAssertEqual(search.rows.map { $0.subtitle.site_proxy?.value }, [false, true])
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.count, 1)
    XCTAssertTrue(SubtitleSearchURLProtocol.requests[0].path.hasSuffix("/stream"))
    struct EncodedProxy: Decodable {
      let site_proxy: Bool
    }
    for row in search.rows {
      let encoded = try JSONEncoder().encode(row.subtitle)
      let payload = try jsonObject(encoded)
      XCTAssertEqual(
        try JSONDecoder().decode(EncodedProxy.self, from: encoded).site_proxy,
        row.subtitle.site_proxy?.value
      )
      XCTAssertEqual(payload["enclosure"] as? String, row.subtitle.enclosure)
    }
  }

  func testTransportFailureBeforeFinalReplacesPreviewWithHTTPResult() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"append","items":[{"title":"预览","enclosure":"https://sub.example/preview"}]}"#
    )
    SubtitleSearchURLProtocol.fallbackBody = Data(
      #"{"success":true,"message":"","data":[{"title":"最终","enclosure":"https://sub.example/final#mp_sig=abc"}]}"#
        .utf8
    )
    let session = session(api: api, keyword: "回退")
    session.start()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["最终"])
    XCTAssertEqual(session.rows.first?.subtitle.enclosure, "https://sub.example/final#mp_sig=abc")
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(
      SubtitleSearchURLProtocol.requests.map(\.path),
      ["/api/v1/search/subtitle/title/stream", "/api/v1/search/subtitle/title"]
    )
  }

  func testFinalReplaceSurvivesCleanCloseBeforeDone() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"replace","items":[{"title":"最终"}]}"#
    )
    let session = session(api: api, keyword: "收尾")
    session.start()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["最终"])
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(
      SubtitleSearchURLProtocol.requests.map(\.path),
      ["/api/v1/search/subtitle/title/stream"]
    )
  }

  func testFinalReplaceSurvivesDisconnectBeforeDone() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"replace","items":[{"title":"最终"}]}"#
    )
    // 同一轮里先 didLoad 再 didFail 时，URLSession 会丢掉还没被读走的事件。
    // 先等最终列表发布，再断开，才能覆盖“最终列表之后的传输失败不再回退”。
    SubtitleSearchURLProtocol.holdStreamAfterBody = true
    let session = session(api: api, keyword: "断开")
    session.start()
    try await until { session.rows.map(\.subtitle.title) == ["最终"] }
    SubtitleSearchURLProtocol.failHeldStreams()
    try await until { session.didFinish }
    XCTAssertEqual(session.rows.map(\.subtitle.title), ["最终"])
    XCTAssertNil(session.errorMessage)
    XCTAssertEqual(
      SubtitleSearchURLProtocol.requests.map(\.path),
      ["/api/v1/search/subtitle/title/stream"]
    )
  }

  func testCancelledOrStaleFallbackDoesNotPublish() async throws {
    let api = service()
    SubtitleSearchURLProtocol.holdFallback = true
    SubtitleSearchURLProtocol.streamBody = sse(
      #"data: {"type":"append","items":[{"title":"预览"}]}"#
    )
    SubtitleSearchURLProtocol.fallbackBody = Data(
      #"{"success":true,"message":"","data":[{"title":"过期"}]}"#.utf8
    )
    let cancelled = session(api: api, keyword: "取消")
    cancelled.start()
    try await until {
      SubtitleSearchURLProtocol.requests.contains { $0.path == "/api/v1/search/subtitle/title" }
    }
    cancelled.cancel()
    SubtitleSearchURLProtocol.releaseHeldFallback()
    try await until { !cancelled.isSearching }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(cancelled.rows.isEmpty)
    XCTAssertFalse(cancelled.didFinish)
    XCTAssertNil(cancelled.errorMessage)

    SubtitleSearchURLProtocol.reset()
    SubtitleSearchURLProtocol.holdFallback = true
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"append","items":[]}"#)
    let stale = session(api: api, keyword: "过期")
    stale.start()
    try await until {
      SubtitleSearchURLProtocol.requests.contains { $0.path == "/api/v1/search/subtitle/title" }
    }
    api.replaceSessionForTesting(
      baseURL: "https://subtitle-tests.local",
      token: "next-token",
      currentUser: searchUser(enabled: true, token: "next-token", userID: 881)
    )
    SubtitleSearchURLProtocol.releaseHeldFallback()
    try await until { !stale.isSearching }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(stale.rows.isEmpty)
    XCTAssertEqual(stale.errorMessage, "登录状态已更新，请返回后重新搜索。")
  }

  func testSearchPageSubtitleModeUsesTitleStreamWithoutPaging() async throws {
    let api = service()
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"done","items":[]}"#)
    let viewModel = SearchViewModel(apiService: api)
    viewModel.searchType = .subtitle
    viewModel.query = "星际穿越"
    await viewModel.autoSearch()
    try await until {
      SubtitleSearchURLProtocol.requests.contains { $0.path == "/api/v1/search/subtitle/title/stream" }
    }
    let request = try XCTUnwrap(
      SubtitleSearchURLProtocol.requests.first { $0.path == "/api/v1/search/subtitle/title/stream" }
    )
    XCTAssertEqual(request.query["keyword"], "星际穿越")
    XCTAssertNil(request.query["page"])
    XCTAssertNil(request.query["manual_paging"])
    XCTAssertNil(request.query["source"])
    viewModel.cancelSubtitleSearch()
  }

  func testSessionWithoutSearchPermissionDoesNotStart() {
    let session = session(api: service(search: false), keyword: "无权限")
    session.start()
    XCTAssertFalse(session.isSearching)
    XCTAssertFalse(session.didFinish)
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.isEmpty)
  }

  func testBothSearchModesResolveDefaultsAndShareExplicitSiteSelection() async throws {
    let api = service()
    let settings = try configureSiteDefaults(api: api)
    let viewModel = SearchViewModel(apiService: api)
    configureAvailableSites(viewModel.siteFilter)
    viewModel.query = "共同筛选"
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"done","items":[]}"#)
    defer { viewModel.cancelSubtitleSearch() }

    let choices: [(Set<Int>?, String, String, String)] = [
      (nil, "默认", "1,2", "2"),
      ([1], "站点1", "1", "1"),
      ([1, 2], "2 个站点", "1,2", "1,2"),
      ([], "全部站点", "1,2", "1,2"),
      (nil, "默认", "1,2", "2"),
    ]
    var requestCount = 0
    for (selection, label, resourceSites, subtitleSites) in choices {
      viewModel.siteFilter.selectedSites = selection
      let modes: [(SearchType, String, String)] = [
        (.resource, "/api/v1/search/title/stream", resourceSites),
        (.subtitle, "/api/v1/search/subtitle/title/stream", subtitleSites),
      ]
      for (type, path, sites) in modes {
        viewModel.searchType = type
        await viewModel.autoSearch()
        requestCount += 1
        try await until { SubtitleSearchURLProtocol.requests.count == requestCount }
        let request = try XCTUnwrap(SubtitleSearchURLProtocol.requests.last)
        XCTAssertEqual(request.path, path)
        XCTAssertEqual(request.query["sites"], sites)
        XCTAssertEqual(request.query["keyword"], "共同筛选")
        XCTAssertEqual(viewModel.siteFilter.siteButtonLabel, label)
        XCTAssertEqual(viewModel.siteFilter.selectedSites, selection)
      }
    }
    XCTAssertEqual(settings.defaultSearchSites, [])
    XCTAssertEqual(settings.defaultSubtitleSearchSites, [2])
  }

  func testApplyingSubtitleSiteSelectionCanRestoreItsOwnDefault() async throws {
    let api = service()
    _ = try configureSiteDefaults(api: api)
    let navigation = ImageNavigationCoordinator(apiService: api)
    navigation.setStackPresentation(isSelected: true, scenePhase: .active)
    let source = navigation.sourceToken()
    let viewModel = SearchViewModel(apiService: api)
    configureAvailableSites(viewModel.siteFilter)
    viewModel.searchType = .subtitle
    viewModel.query = "已提交的字幕搜索"
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"done","items":[]}"#)
    defer { viewModel.cancelSubtitleSearch() }
    await viewModel.autoSearch()
    try await until { SubtitleSearchURLProtocol.requests.count == 1 }

    viewModel.query = "尚未提交的草稿"
    viewModel.siteFilter.selectedSites = [1]
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.count, 1)
    await viewModel.applyPagedSearchSites(from: source, in: navigation)
    try await until { SubtitleSearchURLProtocol.requests.count == 2 }

    viewModel.siteFilter.selectedSites = nil
    await viewModel.applyPagedSearchSites(from: source, in: navigation)
    try await until { SubtitleSearchURLProtocol.requests.count == 3 }
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.map { $0.query["sites"] }, ["2", "1", "2"])
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.allSatisfy {
      $0.query["keyword"] == "已提交的字幕搜索"
    })
    XCTAssertEqual(viewModel.siteFilter.siteButtonLabel, "默认")
    await viewModel.applyPagedSearchSites(from: source, in: navigation)
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.count, 3)
  }

  private func configureSiteDefaults(api: APIService) throws -> SystemViewModel {
    let profile = try XCTUnwrap(api.profileKey)
    for prefix in ["defaultSearchSites", "defaultSubtitleSearchSites"] {
      let key = "\(prefix)_\(profile)"
      let previous = UserDefaults.standard.array(forKey: key) as? [Int]
      addTeardownBlock {
        if let previous { UserDefaults.standard.set(previous, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
    }
    let settings = SystemViewModel(apiService: api)
    settings.defaultSearchSites = []
    settings.defaultSubtitleSearchSites = [2]
    return settings
  }

  private func configureAvailableSites(_ viewModel: SiteFilterViewModel) {
    viewModel.availableSites = [1, 2].map {
      Site(
        id: $0, name: "站点\($0)", domain: nil, url: nil, downloader: nil,
        is_active: FlexibleBool(true)
      )
    }
    viewModel.hasLoadedSites = true
    viewModel.loadedSitesAuthoritative = true
  }

  func testDownloadSuccessRequiresExplicitFilesAndKeepsSignedEnclosure() async throws {
    let api = service()
    let enclosure = "https://sub.example/a.zip#mp_sig=abc&mp_purpose=subtitle_download:9"
    let info = try decodeSubtitle(#"{"title":"中字","enclosure":"\#(enclosure)"}"#)
    SubtitleSearchURLProtocol.downloadBody = Data(
      #"{"success":true,"message":"","data":{"files":["/media/a.srt","/media/b.srt"]}}"#.utf8
    )
    let files = try await api.downloadSubtitle(
      subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: nil)
    XCTAssertEqual(files, ["/media/a.srt", "/media/b.srt"])
    let body = try XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body)
    let json = try jsonObject(body)
    XCTAssertTrue(json["save_path"] is NSNull)
    XCTAssertEqual((json["subtitle_in"] as? [String: Any])?["enclosure"] as? String, enclosure)

    SubtitleSearchURLProtocol.reset()
    SubtitleSearchURLProtocol.downloadBody = Data(
      #"{"success":true,"message":"","data":{"files":["/media/kept.srt"]}}"#.utf8
    )
    let saved = try await api.downloadSubtitle(
      subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: "/downloads/movie")
    XCTAssertEqual(saved, ["/media/kept.srt"])
    let savedBody = try jsonObject(try XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body))
    XCTAssertEqual(savedBody["save_path"] as? String, "/downloads/movie")
  }

  func testDownloadFailsClosedForRejectedEmptyOrIncompleteResponses() async throws {
    let api = service()
    let info = SubtitleInfo(title: "中字", enclosure: "https://sub.example/a.zip")
    do {
      _ = try await api.downloadSubtitle(
        subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: " ")
      XCTFail("空白目录不应发出请求")
    } catch SubtitleSearchFailure.emptySavePath {
    }
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.isEmpty)

    for (body, expected) in [
      (#"{"success":false,"message":"字幕下载链接签名无效","data":null}"#, "字幕下载链接签名无效"),
      ("", "字幕下载失败"),
      (#"{"success":true,"message":"","data":{}}"#, "字幕下载失败"),
      (#"{"success":true,"message":"","data":null}"#, "字幕下载失败"),
    ] {
      SubtitleSearchURLProtocol.reset()
      SubtitleSearchURLProtocol.downloadBody = Data(body.utf8)
      do {
        _ = try await api.downloadSubtitle(
          subtitle: info, mediaSource: "themoviedb", mediaId: "550", savePath: nil)
        XCTFail("不完整响应不应当成下载成功：\(body)")
      } catch let error as APIError {
        XCTAssertEqual(error.localizedDescription, expected)
      }
    }
  }

  func testSparseSubtitleContractAndRawNumericSizeRoundTrip() throws {
    let input = #"[{"site":1,"site_order":2,"site_proxy":true,"size":12.5,"grabs":3,"subtitle_id":"7","meta_info":{"season":0},"episode_list":[1,2]}, {"title":"稀疏","size":null}]"#
    let items = try JSONDecoder().decode([SubtitleInfo].self, from: Data(input.utf8))
    XCTAssertEqual(items.count, 2)
    XCTAssertNil(items[1].site)
    XCTAssertNil(items[1].size)
    XCTAssertEqual(items[0].size, 12.5)
    XCTAssertEqual(try JSONDecoder().decode([SubtitleInfo].self, from: JSONEncoder().encode(items)), items)
    for json in [#"{"site":"1"}"#, #"{"site":1e100}"#, #"{"grabs":2.5}"#] {
      XCTAssertThrowsError(try decodeSubtitle(json))
    }
    let large = try decodeSubtitle(#"{"size":1e100}"#)
    XCTAssertEqual(large.size, 1e100)
    XCTAssertNil(large.sizeInBytes)
    XCTAssertNil(items[0].sizeInBytes)
  }

  func testRowsKeepIdentityWhenPreviewPrependsAndFinalReorders() throws {
    let first = try decodeSubtitle(#"{"site":1,"title":"甲","enclosure":"https://sub.example/a"}"#)
    let second = try decodeSubtitle(#"{"site":2,"title":"乙","enclosure":"https://sub.example/b"}"#)
    let before = SubtitleSearchRow.makeRows(from: [first, first])
    let prepended = SubtitleSearchRow.makeRows(from: [second, first, first])
    let final = SubtitleSearchRow.makeRows(from: [first, first, second])
    XCTAssertEqual(before.map(\.id), Array(prepended.dropFirst()).map(\.id))
    XCTAssertEqual(before.map(\.id), Array(final.prefix(2)).map(\.id))
    XCTAssertEqual(Set(prepended.map(\.id)).count, 3)
    let ambiguous = [SubtitleInfo(site_name: "a-b", title: "c"), SubtitleInfo(site_name: "a", title: "b-c")]
    XCTAssertNotEqual(ambiguous[0].listIdentity, ambiguous[1].listIdentity)
  }

  func testInterruptedSearchKeepsPreviewAndRestartsOnlyOnRequest() async throws {
    SubtitleSearchURLProtocol.holdStreamAfterBody = true
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"append","items":[{"title":"已有预览","enclosure":"a"}]}"#)
    let search = session(api: service(), keyword: "中断")
    search.start()
    try await until { !search.rows.isEmpty }
    let originalID = search.rows[0].id
    search.pageImageStackStateDidChange(.init(isInteractive: false, isForeground: false, releaseEpoch: 0))
    XCTAssertEqual(search.state, .interrupted)
    XCTAssertTrue(search.canRestart)
    XCTAssertFalse(search.didFinish)
    search.start()
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.count, 1)
    XCTAssertEqual(search.rows[0].id, originalID)

    SubtitleSearchURLProtocol.holdStreamAfterBody = false
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"done","items":[{"title":"最终","enclosure":"a"}]}"#)
    search.restart()
    try await until { search.state == .completed }
    XCTAssertEqual(search.rows.map(\.subtitle.title), ["最终"])
    XCTAssertEqual(search.rows[0].id, originalID)
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.filter { $0.path.hasSuffix("/stream") }.count, 2)
    XCTAssertFalse(search.canRestart)
    search.deactivate()
    XCTAssertEqual(search.state, .completed)
  }

  func testInterruptedEmptySearchCanRestartAndFailureCanRetry() async throws {
    SubtitleSearchURLProtocol.holdStreamAfterBody = true
    let search = session(api: service(), keyword: "无预览")
    search.start()
    try await until { !SubtitleSearchURLProtocol.requests.isEmpty }
    search.deactivate()
    XCTAssertEqual(search.state, .interrupted)
    XCTAssertTrue(search.rows.isEmpty)
    XCTAssertTrue(search.canRestart)
    SubtitleSearchURLProtocol.holdStreamAfterBody = false
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"error","message":"站点失败"}"#)
    search.restart()
    try await until { search.didFinish }
    XCTAssertEqual(search.state, .failed("站点失败"))
    XCTAssertTrue(search.canRestart)
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"done","items":[]}"#)
    search.restart()
    try await until { search.state == .completed }
    XCTAssertNil(search.errorMessage)
    XCTAssertTrue(search.rows.isEmpty)
  }

  func testSessionRefreshPreventsRestartOfOldSearch() async throws {
    let api = service()
    SubtitleSearchURLProtocol.holdStreamAfterBody = true
    let search = session(api: api, keyword: "旧会话")
    search.start()
    try await until { !SubtitleSearchURLProtocol.requests.isEmpty }
    search.deactivate()
    api.replaceSessionForTesting(baseURL: "https://subtitle-tests.local", token: "new", currentUser: searchUser(enabled: true, token: "new", userID: 881))
    search.restart()
    XCTAssertEqual(search.state, .invalidated)
    XCTAssertFalse(search.canRestart)
    XCTAssertFalse(search.canDownload)
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.count, 1)
  }

  func testSearchCanBeReleasedOffMainExecutor() async {
    let api = service()
    let box = SubtitleSessionReleaseBox(session(api: api, keyword: "后台释放"))
    weak let released = box.value
    await Task.detached { box.release() }.value
    withExtendedLifetime(api) { XCTAssertNil(released) }
  }

  func testRunningStreamDoesNotRetainSearchOwner() async throws {
    SubtitleSearchURLProtocol.holdStreamAfterBody = true
    SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"append","items":[{"title":"预览"}]}"#)
    var search: SubtitleSearchSession? = session(api: service(), keyword: "释放运行会话")
    weak let released = search
    search?.start()
    try await until { search?.rows.isEmpty == false }
    search = nil
    try await until { released == nil }
  }

  func testDownloadFreezesTargetAndSuccessStopsRepeatSubmission() async throws {
    SubtitleSearchURLProtocol.holdDownload = true
    let model = downloadModel(api: service())
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    model.selectSavePath(" /media/A ")
    let task = try XCTUnwrap(model.submit())
    XCTAssertTrue(model.isSubmitting)
    XCTAssertFalse(model.canEdit)
    XCTAssertNil(model.submit())
    model.selectMedia(id: "42", media: MediaInfo(title: "B", type: "电影"))
    model.selectSource(.douban)
    model.selectSavePath("/media/B")
    XCTAssertEqual(model.selectedIdentity?.mediaId, "550")
    XCTAssertEqual(model.selectedSavePath, " /media/A ")
    try await until { SubtitleSearchURLProtocol.requests.contains { $0.path.hasSuffix("/download/subtitle") } }
    let record = try XCTUnwrap(SubtitleSearchURLProtocol.requests.last)
    let body = try jsonObject(XCTUnwrap(record.body))
    XCTAssertEqual(body["media_id"] as? String, "550")
    XCTAssertEqual(body["media_source"] as? String, "themoviedb")
    XCTAssertEqual(body["save_path"] as? String, " /media/A ")
    SubtitleSearchURLProtocol.downloadBody = Data(#"{"success":true,"data":{"files":["/media/A/a.srt"]}}"#.utf8)
    SubtitleSearchURLProtocol.releaseHeldDownloads()
    await task.value
    XCTAssertEqual(model.state, .completed)
    XCTAssertEqual(model.submitTitle, "已下载")
    XCTAssertFalse(model.canSubmit)
    XCTAssertFalse(model.canEdit)
    XCTAssertNil(model.submit())
  }

  func testSelectingCurrentSubtitleSourceKeepsChosenMedia() {
    let model = downloadModel(api: service())
    model.selectMedia(id: "550", media: MediaInfo(title: "已选电影", type: "电影"))
    model.selectSavePath(" /media/A ")
    let identity = model.selectedIdentity
    model.selectSource(model.mediaSource)
    XCTAssertEqual(model.selectedIdentity, identity)
    XCTAssertEqual(model.selectedTitle, "已选电影")
    XCTAssertEqual(model.selectedSavePath, " /media/A ")
    XCTAssertTrue(model.canSubmit)

    model.selectSource(.douban)
    XCTAssertEqual(model.mediaSource, .douban)
    XCTAssertNil(model.selectedIdentity)
    XCTAssertNil(model.selectedTitle)
    XCTAssertFalse(model.canSubmit)
  }

  func testSubtitleMediaSelectionKeepsSearchKeywordAndDisambiguatesYear() async throws {
    let api = service()
    let model = downloadModel(api: api)
    let lookup = ManualMediaSearchViewModel(
      source: model.mediaSource, keyword: model.mediaSearchKeyword, apiService: api
    )
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.isEmpty)
    SubtitleSearchURLProtocol.recognitionBody = Data(
      #"[{"tmdb_id":550,"title":"同名电影","year":"2026","type":"电影"}]"#.utf8
    )
    await lookup.search()
    let result = try XCTUnwrap(lookup.items.first)
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.first?.query["title"], model.mediaSearchKeyword)
    let identity = try XCTUnwrap(ManualMediaSelection.mediaId(for: result, source: lookup.source))
    model.selectMedia(id: identity, media: result)
    XCTAssertEqual(model.selectedTitle, "同名电影（2026）")
    XCTAssertEqual(model.mediaSearchKeyword, "同名电影（2026）")
    XCTAssertEqual(model.selectedTitle, ManualMediaSelection.displayTitle(for: result))
    await model.submit()?.value
    let body = try jsonObject(XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body))
    XCTAssertEqual(body["media_id"] as? String, "550")

    let request = try XCTUnwrap(MediaActionHandler(apiService: api).subtitleSearchRequest(for: result, sites: nil))
    let prefilled = SubtitleDownloadViewModel(subtitle: SubtitleInfo(title: "字幕"), request: request, apiService: api)
    XCTAssertEqual(prefilled.selectedTitle, "同名电影（2026）")
    XCTAssertEqual(prefilled.selectedIdentity?.mediaId, "550")
  }

  func testSiteFilterFailureAndRetryKeepExplicitSelection() async {
    let model = SiteFilterViewModel(apiService: service())
    model.selectedSites = [2]
    var loading: [Bool] = []
    let observation = model.$isLoadingSites.sink { loading.append($0) }
    SubtitleSearchURLProtocol.siteBody = Data(#"{"success":false,"message":"暂不可用"}"#.utf8)
    await model.loadSites()
    XCTAssertNotNil(model.siteLoadError)
    XCTAssertEqual(model.selectedSites, [2])
    XCTAssertFalse(model.hasLoadedSites)

    SubtitleSearchURLProtocol.siteBody = Data(#"[{"id":2,"name":"站点2","is_active":true}]"#.utf8)
    await model.loadSites()
    XCTAssertNil(model.siteLoadError)
    XCTAssertTrue(model.hasLoadedSites)
    XCTAssertEqual(model.availableSites.map(\.id), [2])
    XCTAssertEqual(model.sitesString(for: .resource), "2")
    XCTAssertEqual(model.sitesString(for: .subtitle), "2")
    XCTAssertEqual(loading, [false, true, false, true, false])
    withExtendedLifetime(observation) {}
  }

  func testSubtitleDirectoryFailureCanReloadWithoutChangingAutomaticChoice() async throws {
    let model = downloadModel(api: service())
    var loadingStates: [Bool] = []
    let observation = model.$isLoadingDirectories.sink { loadingStates.append($0) }
    defer { observation.cancel() }
    SubtitleSearchURLProtocol.directoryBody = Data(#"{"success":false,"message":"目录暂时不可用"}"#.utf8)
    await model.loadDirectories()
    XCTAssertNotNil(model.directoryError)
    XCTAssertEqual(loadingStates, [false, true, false])
    XCTAssertNil(model.selectedSavePath)

    SubtitleSearchURLProtocol.directoryBody = Data(#"[{"name":"电影","save_path":" /media/A "}]"#.utf8)
    await model.loadDirectories()
    XCTAssertNil(model.directoryError)
    XCTAssertEqual(model.savePathChoices, [" /media/A "])
    XCTAssertEqual(loadingStates, [false, true, false, true, false])
    XCTAssertNil(model.selectedSavePath)
    XCTAssertEqual(SubtitleSearchURLProtocol.requests.filter { $0.path.hasSuffix("/download/paths") }.count, 2)
  }

  func testIdleSubtitleDownloadPublishesInvalidationOnSameAccountRefresh() {
    let api = service()
    let model = downloadModel(api: api)
    model.selectMedia(id: "550", media: MediaInfo(title: "已选电影", type: "电影"))
    let uiIdentity = api.uiIdentity
    var states: [SubtitleDownloadViewModel.State] = []
    let observation = model.$state.sink { states.append($0) }
    defer { observation.cancel() }

    api.replaceSessionForTesting(baseURL: api.baseURL, token: "refreshed", currentUser: api.currentUser)
    XCTAssertEqual(api.uiIdentity, uiIdentity)
    XCTAssertEqual(states, [.editing, .invalidated])
    XCTAssertEqual(model.failure, "登录状态已更新，请关闭后重新搜索字幕。")
    XCTAssertFalse(model.canEdit)
    XCTAssertNil(model.submit())
    model.selectSource(.douban)
    XCTAssertEqual(model.selectedIdentity?.mediaId, "550")
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.isEmpty)
  }

  func testSubtitleDownloadWithExpiredSnapshotImmediatelyShowsInvalidation() {
    let api = service()
    let search = session(api: api, keyword: "旧字幕")
    api.replaceSessionForTesting(baseURL: api.baseURL, token: "refreshed", currentUser: api.currentUser)
    let model = search.downloadModel(for: SubtitleInfo(title: "旧结果"))
    XCTAssertEqual(model.state, .invalidated)
    XCTAssertNotNil(model.failure)
    XCTAssertFalse(model.canSubmit)
  }

  func testSubtitleResultsObserveRootAndDetailLifecycleAfterReplacingSearch() async throws {
    let api = service()
    let navigation = ImageNavigationCoordinator(apiService: api)
    navigation.setStackPresentation(isSelected: true, scenePhase: .active)
    let detail = navigation.push(SubtitleSearchRequest(
      kind: .title(keyword: "详情字幕"), sites: nil, displayTitle: nil, mediaInfo: nil
    ))
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }

    for lifecycle in [navigation.rootLifecycle, navigation.lifecycle(for: detail)] {
      navigation.setStackPresentation(isSelected: true, scenePhase: .active)
      let first = session(api: api, keyword: "首次")
      let host = UIHostingController(rootView: SubtitleResultsBody(search: first, imageLifecycle: lifecycle) { EmptyView() })
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.layoutIfNeeded()

      SubtitleSearchURLProtocol.holdStreamAfterBody = true
      SubtitleSearchURLProtocol.streamBody = sse(#"data: {"type":"append","items":[{"title":"保留预览"}]}"#)
      first.start()
      try await until { !first.rows.isEmpty }
      navigation.setStackPresentation(isSelected: true, scenePhase: .background)
      XCTAssertEqual(first.state, .interrupted)
      XCTAssertEqual(first.rows.first?.subtitle.title, "保留预览")
      navigation.setStackPresentation(isSelected: true, scenePhase: .active)
      XCTAssertEqual(first.state, .interrupted, "返回前台不自动重搜")

      let replacement = session(api: api, keyword: "替换搜索")
      host.rootView = SubtitleResultsBody(search: replacement, imageLifecycle: lifecycle) { EmptyView() }
      host.view.layoutIfNeeded()
      replacement.start()
      try await until { !replacement.rows.isEmpty }
      navigation.setStackPresentation(isSelected: false, scenePhase: .active)
      XCTAssertEqual(replacement.state, .interrupted, "替换 owner 后仍须观察同一页面的生命周期")
      XCTAssertEqual(replacement.rows.first?.subtitle.title, "保留预览")
      window.isHidden = true
      window.rootViewController = nil
    }
  }

  func testFailedDownloadCanEditAndRetryWithNewFrozenTarget() async throws {
    let model = downloadModel(api: service())
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    SubtitleSearchURLProtocol.downloadBody = Data(#"{"success":false,"message":"保存失败"}"#.utf8)
    await model.submit()?.value
    XCTAssertEqual(model.failure, "保存失败")
    XCTAssertEqual(model.submitTitle, "重试下载")
    XCTAssertTrue(model.canEdit)
    model.selectSource(.douban)
    XCTAssertFalse(model.canSubmit)
    model.selectMedia(id: "42", media: MediaInfo(title: "B", type: "电影"))
    model.selectSavePath(nil)
    SubtitleSearchURLProtocol.downloadBody = Data(#"{"success":true,"data":{"files":[]}}"#.utf8)
    await model.submit()?.value
    let body = try jsonObject(XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body))
    XCTAssertEqual(body["media_id"] as? String, "42")
    XCTAssertEqual(body["media_source"] as? String, "douban")
    XCTAssertTrue(body["save_path"] is NSNull)
    XCTAssertEqual(model.state, .completed)
  }

  func testClosedDownloadCancelsAndCannotPublishOrSubmitAgain() async throws {
    SubtitleSearchURLProtocol.holdDownload = true
    let model = downloadModel(api: service())
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    let task = try XCTUnwrap(model.submit())
    try await until { SubtitleSearchURLProtocol.requests.contains { $0.path.hasSuffix("/download/subtitle") } }
    model.close()
    SubtitleSearchURLProtocol.releaseHeldDownloads()
    await task.value
    XCTAssertEqual(model.state, .closed)
    XCTAssertNotEqual(model.state, .completed)
    XCTAssertNil(model.submit())
  }

  func testSessionChangeDuringDownloadCannotPublishSuccess() async throws {
    let api = service()
    SubtitleSearchURLProtocol.holdDownload = true
    let model = downloadModel(api: api)
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    let task = try XCTUnwrap(model.submit())
    try await until { SubtitleSearchURLProtocol.requests.contains { $0.path.hasSuffix("/download/subtitle") } }
    api.replaceSessionForTesting(baseURL: "https://subtitle-tests.local", token: "new", currentUser: searchUser(enabled: true, token: "new", userID: 881))
    SubtitleSearchURLProtocol.releaseHeldDownloads()
    await task.value
    XCTAssertNotEqual(model.state, .completed)
    XCTAssertFalse(model.canSubmit)
    XCTAssertFalse(model.canEdit)
  }

  func testPrefilledMediaCanBeChangedAndDownloadDirectoriesKeepOriginalPathValues() async throws {
    let api = service()
    let request = MediaActionHandler(apiService: api).subtitleSearchRequest(for: MediaInfo(tmdb_id: 550, title: "预填媒体", type: "电影"), sites: nil)!
    let model = SubtitleDownloadViewModel(subtitle: SubtitleInfo(title: "字幕"), request: request, apiService: api)
    XCTAssertEqual(model.selectedIdentity, request.initialMediaIdentity)
    model.selectSource(.douban)
    model.selectMedia(id: "42", media: MediaInfo(title: "B", type: "电影"))
    XCTAssertEqual(model.selectedIdentity, MediaIdentity(source: "douban", mediaId: "42"))
    SubtitleSearchURLProtocol.directoryBody = Data(#"[{"name":"电影","save_path":" /media/A "},{"save_path":""},{"save_path":" /media/A "}]"#.utf8)
    await model.loadDirectories()
    XCTAssertEqual(model.savePathChoices, [" /media/A "])
    model.selectSavePath(" /media/A ")
    await model.submit()?.value
    let payload = try jsonObject(XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body))
    XCTAssertEqual(payload["save_path"] as? String, " /media/A ")
    XCTAssertEqual(payload["media_source"] as? String, "douban")
    XCTAssertEqual(payload["media_id"] as? String, "42")
  }

  func testPrefilledSourceAndIdentityAreSubmittedWithoutReselectingMedia() async throws {
    let api = service()
    let request = SubtitleSearchRequest(
      kind: .media(source: "douban", mediaId: "1291843", type: "电影", season: nil, episode: nil),
      sites: nil, displayTitle: "预填电影", mediaInfo: nil
    )
    let model = SubtitleDownloadViewModel(subtitle: SubtitleInfo(title: "字幕"), request: request, apiService: api)
    XCTAssertEqual(model.mediaSource, .douban)
    model.selectSource(.douban)
    XCTAssertEqual(model.selectedIdentity, request.initialMediaIdentity)
    XCTAssertEqual(model.selectedTitle, "预填电影")
    await model.submit()?.value
    let payload = try jsonObject(XCTUnwrap(SubtitleSearchURLProtocol.requests.last?.body))
    XCTAssertEqual(payload["media_source"] as? String, "douban")
    XCTAssertEqual(payload["media_id"] as? String, "1291843")
    XCTAssertTrue(payload["save_path"] is NSNull)
    XCTAssertEqual(model.state, .completed)
  }

  func testShortcutAndPageResolveSameDefaultSites() async throws {
    let api = service()
    api.currentUserForTesting = Token(access_token: "subtitle-token", token_type: "bearer", super_user: FlexibleBool(true), permissions: nil, user_id: 880, user_name: "admin", avatar: nil)
    let settings = try configureSiteDefaults(api: api)
    let filter = SiteFilterViewModel(apiService: api)
    await filter.loadSites()
    XCTAssertEqual(filter.availableSites.map(\.id), [1, 2, 3])
    XCTAssertTrue(filter.loadedSitesAuthoritative)
    let handler = MediaActionHandler(apiService: api)
    let media = MediaInfo(tmdb_id: 550, title: "A", type: "电影", season: 0)
    let selections: [Set<Int>] = [[], [2], [1, 2], [2, 99]]
    for selected in selections {
      settings.defaultSubtitleSearchSites = selected
      let resolved = await handler.subtitleSearchRequestUsingDefaultSites(for: media)
      let request = try XCTUnwrap(resolved)
      XCTAssertEqual(request.sites, filter.sitesString(for: .subtitle))
      XCTAssertEqual(request.sites, selected.isEmpty ? "1,2" : selected.intersection([1, 2]).sorted().map(String.init).joined(separator: ","))
      _ = try await api.searchSubtitles(request)
      XCTAssertEqual(SubtitleSearchURLProtocol.requests.last?.query["sites"], request.sites)
      XCTAssertEqual(SubtitleSearchURLProtocol.requests.last?.query["season"], "0")
      XCTAssertEqual(settings.defaultSubtitleSearchSites, selected)
    }
    settings.defaultSearchSites = []
    let resource = await handler.searchResourcesTargetUsingDefaultSites(for: media)
    XCTAssertEqual(resource?.sites, filter.sitesString(for: .resource))
  }

  func testShortcutTitleFallbackAndRecognitionUseSameAction() async throws {
    let api = service()
    let settings = try configureSiteDefaults(api: api)
    settings.defaultSubtitleSearchSites = [2]
    let handler = MediaActionHandler(apiService: api)
    let media = MediaInfo(title: "找不到身份", type: "电影")
    let menuRequest = await handler.subtitleSearchRequestUsingDefaultSites(for: media)
    let homeRequest = await handler.subtitleSearchRequestUsingDefaultSites(for: media, recognizeIfNeeded: true)
    XCTAssertEqual(menuRequest?.titleKeyword, "找不到身份")
    XCTAssertEqual(homeRequest?.titleKeyword, "找不到身份")
    XCTAssertEqual(menuRequest?.sites, "2")
    XCTAssertEqual(homeRequest?.sites, "2")
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    SubtitleSearchURLProtocol.recognitionBody = Data(#"[{"tmdb_id":550,"title":"找到身份","type":"电影"}]"#.utf8)
    let recognized = await handler.subtitleSearchRequestUsingDefaultSites(for: MediaInfo(title: "找到身份", type: "电影"), recognizeIfNeeded: true)
    XCTAssertEqual(recognized?.initialMediaIdentity?.mediaId, "550")
    XCTAssertNil(recognized?.titleKeyword)
  }

  func testCancelledShortcutRecognitionDoesNotContinueIntoDefaultSitesOrTitleFallback() async throws {
    let api = service()
    SubtitleSearchURLProtocol.holdRecognition = true
    let handler = MediaActionHandler(apiService: api)
    let task = Task {
      await handler.subtitleSearchRequestUsingDefaultSites(
        for: MediaInfo(title: "取消识别", type: "电影"), recognizeIfNeeded: true
      )
    }
    try await until { SubtitleSearchURLProtocol.requests.contains { $0.path.contains("/media/search") } }
    task.cancel()
    let request = await task.value
    XCTAssertNil(request)
    XCTAssertFalse(SubtitleSearchURLProtocol.requests.contains { $0.path.contains("/site") })
    XCTAssertFalse(handler.isRecognizingTmdb)
  }

  func testCancelledBeforeTaskStartsDoesNotOpenSubtitleStream() async {
    let search = session(api: service(), keyword: "取消未开始任务")
    search.start()
    search.cancel()
    await Task.yield()
    XCTAssertEqual(search.state, .cancelled)
    XCTAssertTrue(SubtitleSearchURLProtocol.requests.isEmpty)
  }

  func testSuccessfulDownloadNotifiesSearchOwnerBeforeSheetCloses() async throws {
    let api = service()
    let search = session(api: api, keyword: "成功与关闭")
    let subtitle = SubtitleInfo(title: "字幕", enclosure: "https://sub.example/a#signature")
    let model = search.downloadModel(for: subtitle)
    var downloadedAtCompletion: Set<String>?
    let observation = model.$state.sink { state in
      if state == .completed { downloadedAtCompletion = search.downloadedEnclosures }
    }
    defer { observation.cancel() }
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    await model.submit()?.value
    XCTAssertEqual(model.state, .completed)
    XCTAssertEqual(downloadedAtCompletion, ["https://sub.example/a#signature"])
    model.close()
    XCTAssertEqual(model.state, .closed)
    XCTAssertEqual(search.downloadedEnclosures, ["https://sub.example/a#signature"])
  }

  func testDownloadCompletionCallbackDoesNotRetainSearchOwner() async {
    let api = service()
    var search: SubtitleSearchSession? = session(api: api, keyword: "弱回调")
    weak let released = search
    let model = search!.downloadModel(for: SubtitleInfo(title: "字幕", enclosure: "a"))
    search = nil
    XCTAssertNil(released)
    model.selectMedia(id: "550", media: MediaInfo(title: "A", type: "电影"))
    await model.submit()?.value
    XCTAssertEqual(model.state, .completed)
  }

  private func downloadModel(api: APIService) -> SubtitleDownloadViewModel {
    SubtitleDownloadViewModel(
      subtitle: SubtitleInfo(title: "字幕", enclosure: "https://sub.example/a#mp_sig=signature"),
      request: SubtitleSearchRequest(kind: .title(keyword: "搜索"), sites: nil, displayTitle: "搜索", mediaInfo: nil),
      apiService: api
    )
  }

  private func service(search: Bool = true) -> APIService {
    let api = APIService.isolatedTestingInstance()
    api.replaceSessionForTesting(
      baseURL: "https://subtitle-tests.local",
      token: "subtitle-token",
      currentUser: searchUser(enabled: search, token: "subtitle-token", userID: 880)
    )
    return api
  }

  private func searchUser(enabled: Bool, token: String, userID: Int) -> Token {
    Token(
      access_token: token,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": enabled,
        "subscribe": false,
        "manage": false,
        "admin": false,
      ],
      user_id: userID,
      user_name: "subtitle-test",
      avatar: nil
    )
  }

  private func session(api: APIService, keyword: String) -> SubtitleSearchSession {
    SubtitleSearchSession(
      request: SubtitleSearchRequest(
        kind: .title(keyword: keyword),
        sites: "1,2",
        displayTitle: keyword,
        mediaInfo: nil
      ),
      apiService: api,
      doneCloseDelayNanoseconds: 0
    )
  }

  private func until(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "状态应在有限时间内收敛", file: file, line: line)
  }

  private func item(title: String) -> [String: Any] {
    ["title": title, "enclosure": "https://sub.example/\(title)"]
  }

  private func event(type: String, items: [[String: Any]] = []) throws -> SubtitleSearchEvent {
    try decodeEvent(["type": type, "items": items])
  }

  private func batch(
    type: String, titles: [String], index: Int, count: Int, total: Int
  ) throws -> SubtitleSearchEvent {
    try decodeEvent([
      "type": type,
      "items": titles.map { item(title: $0) },
      "replace_batch": true,
      "batch_index": index,
      "batch_count": count,
      "total_items": total,
    ])
  }

  private func decodeEvent(_ object: [String: Any]) throws -> SubtitleSearchEvent {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(SubtitleSearchEvent.self, from: data)
  }

  private func decodeSubtitle(_ json: String) throws -> SubtitleInfo {
    try JSONDecoder().decode(SubtitleInfo.self, from: Data(json.utf8))
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func sse(_ frames: String...) -> Data {
    var text = ""
    for frame in frames {
      text += frame
      text += "\n\n"
    }
    return Data(text.utf8)
  }

  private func queryItems(in endpoint: String) -> [String: String] {
    var items: [String: String] = [:]
    for item in URLComponents(string: "https://subtitle-tests.local\(endpoint)")?.queryItems ?? [] {
      items[item.name] = item.value ?? ""
    }
    return items
  }
}

nonisolated private final class SubtitleSessionReleaseBox: @unchecked Sendable {
  var value: SubtitleSearchSession?
  init(_ value: SubtitleSearchSession) { self.value = value }
  func release() { value = nil }
}

nonisolated private final class SubtitleSearchURLProtocol: URLProtocol, @unchecked Sendable {
  struct Record: Sendable {
    let path: String
    let query: [String: String]
    let body: Data?
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var recorded: [Record] = []
  nonisolated(unsafe) private static var streamData = Data()
  nonisolated(unsafe) private static var streamFailsAfterBody = false
  nonisolated(unsafe) private static var heldStreams: [SubtitleSearchURLProtocol] = []
  nonisolated(unsafe) private static var fallbackData = Data(#"{"success":true,"message":"","data":[]}"#.utf8)
  nonisolated(unsafe) private static var downloadData = Data(#"{"success":true,"message":"","data":{"files":[]}}"#.utf8)
  nonisolated(unsafe) private static var holdingFallback = false
  nonisolated(unsafe) private static var held: [SubtitleSearchURLProtocol] = []

  nonisolated(unsafe) private static var holdingRecognition = false
  nonisolated(unsafe) private static var holdingDownload = false
  nonisolated(unsafe) private static var heldDownloads: [SubtitleSearchURLProtocol] = []
  nonisolated(unsafe) private static var directoryData = Data("[]".utf8)
  nonisolated(unsafe) private static var recognitionData = Data("[]".utf8)
  private static let defaultSites = Data(#"[{"id":1,"name":"站点1","is_active":true},{"id":2,"name":"站点2","is_active":true},{"id":3,"name":"停用","is_active":false}]"#.utf8)
  nonisolated(unsafe) private static var siteData = defaultSites

  static var siteBody: Data {
    get { lock.withLock { siteData } }
    set { lock.withLock { siteData = newValue } }
  }

  static var holdRecognition: Bool {
    get { lock.withLock { holdingRecognition } }
    set { lock.withLock { holdingRecognition = newValue } }
  }
  static var holdDownload: Bool {
    get { lock.withLock { holdingDownload } }
    set { lock.withLock { holdingDownload = newValue } }
  }
  static var directoryBody: Data {
    get { lock.withLock { directoryData } }
    set { lock.withLock { directoryData = newValue } }
  }
  static var recognitionBody: Data {
    get { lock.withLock { recognitionData } }
    set { lock.withLock { recognitionData = newValue } }
  }
  static func releaseHeldDownloads() {
    let pending = lock.withLock { let value = heldDownloads; heldDownloads = []; return value }
    for entry in pending {
      entry.respond(status: 200, data: downloadBody, failAfter: false, contentType: "application/json")
    }
  }

  private let deliveryLock = NSLock()
  private var stopped = false

  static var requests: [Record] { lock.withLock { recorded } }

  static var streamBody: Data {
    get { lock.withLock { streamData } }
    set { lock.withLock { streamData = newValue } }
  }

  static var failStreamAfterBody: Bool {
    get { lock.withLock { streamFailsAfterBody } }
    set { lock.withLock { streamFailsAfterBody = newValue } }
  }

  static var holdStreamAfterBody: Bool {
    get { lock.withLock { streamFailsAfterBody } }
    set { lock.withLock { streamFailsAfterBody = newValue } }
  }

  static func failHeldStreams() {
    let pending = lock.withLock { let value = heldStreams; heldStreams = []; return value }
    for entry in pending {
      entry.client?.urlProtocol(entry, didFailWithError: URLError(.networkConnectionLost))
    }
  }

  static var fallbackBody: Data {
    get { lock.withLock { fallbackData } }
    set { lock.withLock { fallbackData = newValue } }
  }

  static var downloadBody: Data {
    get { lock.withLock { downloadData } }
    set { lock.withLock { downloadData = newValue } }
  }

  static var holdFallback: Bool {
    get { lock.withLock { holdingFallback } }
    set { lock.withLock { holdingFallback = newValue } }
  }

  static func reset() {
    lock.withLock {
      recorded = []
      streamData = Data()
      streamFailsAfterBody = false
      heldStreams = []
      fallbackData = Data(#"{"success":true,"message":"","data":[]}"#.utf8)
      downloadData = Data(#"{"success":true,"message":"","data":{"files":[]}}"#.utf8)
      holdingFallback = false
      held = []
      holdingDownload = false
      holdingRecognition = false
      heldDownloads = []
      directoryData = Data("[]".utf8)
      recognitionData = Data("[]".utf8)
      siteData = defaultSites
    }
  }

  static func releaseHeldFallback() {
    let pending = lock.withLock { let value = held; held = []; return value }
    let body = fallbackBody
    for entry in pending {
      entry.respond(status: 200, data: body, failAfter: false, contentType: "application/json")
    }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subtitle-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var query: [String: String] = [:]
    for item in components?.queryItems ?? [] {
      query[item.name] = item.value ?? ""
    }
    let path = url.path
    let body = Self.requestBody(from: request)
    let plan: Plan = Self.lock.withLock {
      Self.recorded.append(Record(path: path, query: query, body: body))
      if path.contains("/stream") { return .stream }
      if path.hasSuffix("/download/subtitle") {
        if Self.holdingDownload { Self.heldDownloads.append(self); return .hold }
        return .download
      }
      if path.hasSuffix("/download/paths") { return .directories }
      if path.hasSuffix("/site") || path.contains("/site/") { return .sites }
      if path.contains("/media/search") { return Self.holdingRecognition ? .hold : .recognition }
      if path.hasSuffix("/media/recognize") { return .unrecognized }
      if Self.holdingFallback && path.contains("/search/subtitle/") {
        Self.held.append(self)
        return .hold
      }
      return .fallback
    }
    switch plan {
    case .hold:
      return
    case .stream:
      respond(
        status: 200,
        data: Self.streamBody,
        failAfter: Self.failStreamAfterBody,
        contentType: "text/event-stream"
      )
    case .download:
      respond(status: 200, data: Self.downloadBody, failAfter: false, contentType: "application/json")
    case .directories:
      respond(status: 200, data: Self.directoryBody, failAfter: false, contentType: "application/json")
    case .sites:
      respond(status: 200, data: Self.siteBody, failAfter: false, contentType: "application/json")
    case .unrecognized:
      respond(status: 200, data: Data(#"{"media_info":null,"meta_info":null}"#.utf8), failAfter: false, contentType: "application/json")
    case .recognition:
      respond(status: 200, data: Self.recognitionBody, failAfter: false, contentType: "application/json")
    case .fallback:
      respond(status: 200, data: Self.fallbackBody, failAfter: false, contentType: "application/json")
    }
  }

  override func stopLoading() {
    deliveryLock.withLock { stopped = true }
  }

  private enum Plan { case stream, download, fallback, hold, directories, sites, recognition, unrecognized }

  private func respond(status: Int, data: Data, failAfter: Bool, contentType: String) {
    deliveryLock.lock()
    defer { deliveryLock.unlock() }
    guard !stopped else { return }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: ["Content-Type": contentType]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !data.isEmpty {
      client?.urlProtocol(self, didLoad: data)
    }
    if failAfter {
      Self.lock.withLock { Self.heldStreams.append(self) }
      return
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 1024)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
