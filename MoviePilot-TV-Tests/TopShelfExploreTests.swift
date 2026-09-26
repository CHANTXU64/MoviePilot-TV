import Combine
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfExploreTests: XCTestCase {
  private var directory: URL!
  private var defaults: UserDefaults!
  private var suite: String!
  private var service: APIService!
  private var store: TopShelfSharedStore!
  private var transport: URLSession!

  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TopShelfExploreURLProtocol.self))
    TopShelfExploreURLProtocol.reset()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    suite = "TopShelfExploreTests-\(UUID())"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    store = TopShelfSharedStore(containerURL: directory)
    service = APIService.isolatedTestingInstance()
    service.replaceSessionForTesting(
      baseURL: "http://explore.local/mp", token: "test", currentUser: token())
    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TopShelfExploreURLProtocol.self]
    transport = URLSession(configuration: config)
  }

  override func tearDown() async throws {
    transport.invalidateAndCancel()
    APIService.removeURLProtocolForTesting(TopShelfExploreURLProtocol.self)
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }

  private func token(subscribe: Bool = true) -> Token {
    Token(
      access_token: "test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true, "subscribe": subscribe], user_id: 851,
      user_name: "explore", avatar: nil)
  }

  private func manager() -> TopShelfManager {
    TopShelfManager(
      apiService: service, store: store, defaults: defaults,
      storeToken: { _, _ in true }, notifyChange: {})
  }

  private var custom: DiscoverSource {
    .custom(
      DiscoverSourceDescriptor(
        name: "自定义片单", mediaid_prefix: "catalog",
        api_path: "plugin/catalog?base=A%2BB", filter_params: ["category": .string("all")],
        filter_ui: [], depends: nil))
  }

  func testLegacyRecommendationAndExploreConfigurationsRoundTripWithoutChangingSelection() throws {
    let legacy = try JSONDecoder().decode(
      TopShelfSelection.self,
      from: Data(#"{"shelfID":"recommend/custom","title":"旧推荐"}"#.utf8))
    XCTAssertNil(legacy.exploration)
    XCTAssertEqual(legacy.requestPath, "recommend/custom")
    for source in DiscoverSource.allCases + [custom] {
      var config = ExploreConfiguration(source: source)
      config.tmdbGenre = "18"
      config.tmdbSortBy = "vote_average.desc"
      config.pluginFilterValues["unknown"] = .array([.string("A+B & 中文"), .int(2)])
      let selection = TopShelfSelection(exploration: config)
      let restored = try JSONDecoder().decode(
        TopShelfSelection.self, from: JSONEncoder().encode(selection))
      XCTAssertEqual(restored, selection)
      XCTAssertEqual(restored.requestPath, config.apiPath)
      XCTAssertEqual(TopShelfSelectionPolicy.resolve(saved: restored, shelves: []), selection)
      XCTAssertFalse(
        TopShelfSelectionPolicy.options(saved: restored, shelves: []).contains(restored))
    }
  }

  func testDraftUsesActualFieldBindingsWithoutLoadingResultsOrChangingSavedShelf() async throws {
    let manager = manager()
    var saved = ExploreConfiguration()
    saved.tmdbGenre = "18"
    saved.tmdbSortBy = "vote_average.desc"
    manager.select(TopShelfSelection(exploration: saved))
    let draft = ExploreViewModel(apiService: service, configuration: saved, loadsResults: false)
    let genre = try XCTUnwrap(draft.settingsFields.first { $0.id == "genre" })
    genre.value.wrappedValue = .string("35")
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(TopShelfExploreURLProtocol.requests.isEmpty)
    XCTAssertNil(draft.paginator)
    XCTAssertEqual(manager.selection?.exploration, saved, "离开编辑页前未保存，主屏条件保持原值")
    draft.restoreConfiguration(saved)
    XCTAssertEqual(draft.tmdbGenre, "18")
    try XCTUnwrap(draft.settingsFields.first { $0.id == "sort" }).value.wrappedValue = .string(
      "release_date.desc")
    try XCTUnwrap(draft.settingsFields.first { $0.id == "type" }).value.wrappedValue = .string(
      "电视剧")
    XCTAssertEqual(draft.tmdbSortBy, "popularity.desc", "类型变化不能提交已隐藏的电影排序")
    manager.select(TopShelfSelection(exploration: draft.configuration))
    let restoredManager = self.manager()
    XCTAssertEqual(restoredManager.selection?.exploration, draft.configuration)
    draft.tmdbGenre = "16"
    XCTAssertNotEqual(manager.selection?.exploration, draft.configuration)
    let committed = try XCTUnwrap(manager.selection?.exploration)
    manager.select(TopShelfSelection(shelfID: "recommend/tmdb_trending", title: "流行趋势"))
    XCTAssertEqual(self.manager().savedExploration, committed, "切换模式不丢失已保存的筛选")
    manager.select(nil)
    XCTAssertNil(self.manager().selection)
    XCTAssertEqual(self.manager().savedExploration, committed, "关闭主屏展示也保留探索设置")
  }

  func testSavedMissingPluginRetainsItsFieldsAndDoesNotSwitchSource() async throws {
    var saved = ExploreConfiguration(source: custom)
    saved.pluginFilterValues = ["opaque": .string("不在当前选项内"), "rating": .int(7)]
    let draft = ExploreViewModel(apiService: service, configuration: saved, loadsResults: false)
    await draft.refreshSources()
    XCTAssertEqual(draft.configuration, saved)
    XCTAssertTrue(draft.availableSources.contains { $0.id == custom.id })
    XCTAssertEqual(TopShelfExploreURLProtocol.requests.count, 1)
    XCTAssertTrue(TopShelfExploreURLProtocol.requests[0].url!.path.hasSuffix("discover/source"))
  }

  func testNormalExploreReloadsFromFieldChangesWithoutChangingSavedShelf() async throws {
    let manager = manager()
    let saved = TopShelfSelection(exploration: ExploreConfiguration(source: .douban))
    manager.select(saved)
    let browse = ExploreViewModel(apiService: service)
    for _ in 0..<60 {
      if browse.paginator?.items.isEmpty == false { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(browse.paginator?.items.count, 1)
    browse.tmdbSortBy = "vote_average.desc"
    for _ in 0..<60 {
      if TopShelfExploreURLProtocol.requests.contains(where: {
        query($0)["sort_by"] == ["vote_average.desc"]
      }) {
        break
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertTrue(
      TopShelfExploreURLProtocol.requests.contains { query($0)["sort_by"] == ["vote_average.desc"] }
    )
    XCTAssertEqual(manager.selection, saved)
  }

  func testPluginSettingsReuseDependenciesAndKeepClearedMultiSelectionOnReopen() throws {
    let ui = try JSONDecoder().decode(
      [JSONValue].self,
      from: Data(
        #"""
        [
          {"component":"VSelect","props":{"model":"country","label":"地区","items":["usa","jpn"]}},
          {"component":"VSelect","props":{"model":"company","label":"公司","items":[12,13]}},
          {"component":"VSelect","props":{"model":"genres","label":"风格","multiple":true,"items":["动作","剧情"]}}
        ]
        """#.utf8))
    let source = DiscoverSource.custom(
      DiscoverSourceDescriptor(
        name: "插件", mediaid_prefix: "catalog", api_path: "plugin/catalog",
        filter_params: [
          "country": .string("usa"), "company": .int(12), "genres": .array([.string("动作")]),
        ],
        filter_ui: ui, depends: ["company": ["country"]]))
    let draft = ExploreViewModel(
      apiService: service, configuration: ExploreConfiguration(source: source), loadsResults: false)
    try XCTUnwrap(draft.settingsFields.first { $0.id == "country" }).value.wrappedValue = .string(
      "jpn")
    XCTAssertEqual(draft.pluginFilterValues["company"], .null)
    let genre = try XCTUnwrap(draft.settingsFields.first { $0.id == "genres" })
    XCTAssertEqual(genre.kind, .multiChoice)
    genre.value.wrappedValue = .array([])
    let saved = try JSONDecoder().decode(
      ExploreConfiguration.self, from: JSONEncoder().encode(draft.configuration))
    let reopened = ExploreViewModel(apiService: service, configuration: saved, loadsResults: false)
    XCTAssertEqual(reopened.pluginFilterValues["genres"], .array([]))
    XCTAssertEqual(reopened.pluginFilterValues["company"], .null)
    XCTAssertFalse(reopened.buildApiPath().contains("company="))
    XCTAssertFalse(reopened.buildApiPath().contains("genres"))
  }

  func testEachExploreSourceUsesSameQueryInAppAndExtension() async throws {
    for source in DiscoverSource.allCases + [custom] {
      TopShelfExploreURLProtocol.reset()
      var config = ExploreConfiguration(source: source)
      config.tmdbGenre = "18"
      config.tmdbSortBy = "vote_average.desc"
      config.doubanCategory = "科幻"
      config.doubanZone = "华语"
      config.anilistGenre = "Science Fiction"
      config.pluginFilterValues["tags"] = .array([.string("A+B"), .string("中文 & x=y")])
      let manager = manager()
      manager.select(TopShelfSelection(exploration: config))
      await manager.refreshNow()
      let appState = try XCTUnwrap(store.loadState())
      XCTAssertEqual(appState.snapshot?.items.count, 1, source.title)
      let appList = try XCTUnwrap(TopShelfExploreURLProtocol.requests.first)
      let previousCount = TopShelfExploreURLProtocol.requests.count
      try await TopShelfRefreshClient(
        store: store, transport: transport, readToken: { _ in "test" }
      ).refresh()
      let extensionList = try XCTUnwrap(
        TopShelfExploreURLProtocol.requests.dropFirst(previousCount).first)
      XCTAssertEqual(appList.url?.path, extensionList.url?.path, source.title)
      XCTAssertEqual(query(appList), query(extensionList), source.title)
      XCTAssertEqual(
        try store.loadState()?.snapshot?.items.map(\.identifier),
        appState.snapshot?.items.map(\.identifier))
      XCTAssertFalse(
        TopShelfExploreURLProtocol.requests.contains {
          $0.url?.path.hasSuffix("recommend/source") == true
        })
      if case .custom = source {
        XCTAssertEqual(query(appList)["base"], ["A+B"])
        XCTAssertEqual(query(appList)["tags[]"], ["A+B", "中文 & x=y"])
      }
    }
  }

  func testSubscriptionSharesPublishMediaDetailsAndDeduplicateMediaAcrossAuthors() async throws {
    TopShelfExploreURLProtocol.duplicates = true
    let manager = manager()
    manager.select(TopShelfSelection(exploration: ExploreConfiguration(source: .subscriptionShare)))
    await manager.refreshNow()
    let app = try XCTUnwrap(store.loadState()?.snapshot)
    XCTAssertEqual(app.items.count, 2, "同影片同季的不同分享人只占一张，不同季保留")
    for item in app.items {
      let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: item.displayURL))
      XCTAssertEqual(payload.tmdbID, 42)
      XCTAssertEqual(payload.title, "影片名称")
      XCTAssertTrue([1, 2].contains(payload.season))
      let cached = try XCTUnwrap(store.cachedContent(for: payload, at: Date()))
      XCTAssertNil(cached.detail.subscribeShare)
    }
    try await TopShelfRefreshClient(store: store, transport: transport, readToken: { _ in "test" })
      .refresh()
    let updated = try XCTUnwrap(store.loadState()?.snapshot)
    XCTAssertEqual(updated.items.map(\.identifier), app.items.map(\.identifier))
    XCTAssertTrue(
      TopShelfExploreURLProtocol.requests.filter {
        $0.url?.path.hasSuffix("subscribe/shares") == true
      }
      .allSatisfy { query($0)["count"] == ["30"] })
  }

  func testSharePermissionRevocationWithdrawsExtensionConfigurationAndCards() async throws {
    let manager = manager()
    manager.select(TopShelfSelection(exploration: ExploreConfiguration(source: .subscriptionShare)))
    manager.start(refreshImmediately: false)
    await manager.refreshNow()
    XCTAssertNotNil(store.presentation(at: Date()))
    service.replaceSessionForTesting(
      baseURL: "http://explore.local/mp", token: "test", currentUser: token(subscribe: false))
    XCTAssertNil(store.presentation(at: Date()))
    XCTAssertNil(try store.loadState()?.refreshConfiguration)
    let count = TopShelfExploreURLProtocol.requests.count
    await manager.refreshNow()
    XCTAssertEqual(TopShelfExploreURLProtocol.requests.count, count)
  }

  func testShareConversionMatchesExtensionIncludingCanonicalAndLegacyIdentity() throws {
    for object: [String: Any] in [
      ["name": "原名", "share_title": "分享标题", "tmdbid": 42, "type": "电影"],
      ["name": "原名", "tmdbid": 0, "doubanid": "123", "media_source": "0", "media_id": "0"],
      ["name": "原名", "media_source": "custom", "media_id": "A+B/中文", "season": 2],
    ] {
      let share = try JSONDecoder().decode(
        SubscribeShare.self, from: JSONSerialization.data(withJSONObject: object))
      let app = share.toMediaInfo(includeShareMetadata: false)
      let ext = try JSONDecoder().decode(
        MediaInfo.self,
        from: JSONSerialization.data(
          withJSONObject:
            TopShelfRefreshClient.subscriptionShareMedia(object)))
      XCTAssertEqual(app.identity, ext.identity)
      XCTAssertEqual(app.title, ext.title)
      XCTAssertEqual(app.season, ext.season)
      XCTAssertNil(app.subscribeShare)
      XCTAssertNotNil(share.toMediaInfo().subscribeShare, "原探索页的分享交互保持不变")
    }
  }

  private func query(_ request: URLRequest) -> [String: [String]] {
    Dictionary(
      grouping: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? [],
      by: \.name
    )
    .mapValues { $0.compactMap(\.value) }
  }
}

private final class TopShelfExploreURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var recorded: [URLRequest] = []
  nonisolated(unsafe) static var duplicates = false
  static var requests: [URLRequest] { lock.withLock { recorded } }
  static func reset() {
    lock.withLock {
      recorded = []
      duplicates = false
    }
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.withLock { Self.recorded.append(request) }
    let url = request.url!
    let path = url.path
    let object: Any
    if path.hasSuffix("/source") {
      object = [] as [String]
    } else if path.hasSuffix("/subscribe/shares") {
      var share: [String: Any] = [
        "name": "影片名称", "share_title": "分享标题", "tmdbid": 42,
        "type": "电视剧", "season": 1, "poster": "http://image.local/a.gif",
      ]
      if Self.duplicates {
        let second = share.merging(["share_title": "另一个分享人"]) { _, new in new }
        share["season"] = 2
        object = [second, second, share]
      } else {
        object = [share]
      }
    } else if path.contains("/media/") {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      var media: [String: Any] = [
        "tmdb_id": 42, "title": "影片名称", "type": "电视剧",
        "poster_path": "http://image.local/a.gif", "overview": "已准备的详情",
      ]
      if let value = query.first(where: { $0.name == "season" })?.value, let season = Int(value) {
        media["season"] = season
      }
      object = media
    } else {
      object = [
        ["tmdb_id": 42, "title": "影片名称", "type": "电视剧", "poster_path": "http://image.local/a.gif"]
      ]
    }
    do {
      let image = url.host == "image.local"
      let data =
        image ? TopShelfTestArtwork.data : try JSONSerialization.data(withJSONObject: object)
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": image ? "image/gif" : "application/json"])!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
