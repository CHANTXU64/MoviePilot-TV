import XCTest

@testable import MoviePilot_TV

/// 媒体库页「继续观看」的角标派生与进度解码。
@MainActor
final class ContinueWatchingDisplayTests: XCTestCase {
  func testProgressOnlyDrawsForPositiveFinitePercent() {
    XCTAssertNil(ContinueWatchingDisplay.progress(percent: nil))
    XCTAssertNil(ContinueWatchingDisplay.progress(percent: 0))
    XCTAssertNil(ContinueWatchingDisplay.progress(percent: -3))
    XCTAssertNil(ContinueWatchingDisplay.progress(percent: .nan))
    XCTAssertNil(ContinueWatchingDisplay.progress(percent: .infinity))
    XCTAssertEqual(ContinueWatchingDisplay.progress(percent: 45.5) ?? -1, 0.455, accuracy: 0.0001)
    XCTAssertEqual(ContinueWatchingDisplay.progress(percent: 100), 1)
    XCTAssertEqual(ContinueWatchingDisplay.progress(percent: 150), 1, "后端异常值不撑破进度条")
  }

  /// 聚焦时剧照向下长出，标题必须跟着下移让开（同 MediaCard）。间距取大了这个偏移会算成 0，
  /// 标题就钉在原地不动——这正是间距沿用单集卡 18pt 时出现的问题。
  func testFocusedTitleMovesDownWithTheEnlargedStill() {
    let offset = PosterCardFocus.focusedTextOffset(
      forImageSize: ContinueWatchingCard.stillSize, stackSpacing: ContinueWatchingCard.titleSpacing)
    XCTAssertGreaterThan(offset, 0, "聚焦时标题要跟着剧照下移")
    XCTAssertEqual(
      offset,
      PosterCardFocus.focusedVerticalGrowth(forImageSize: ContinueWatchingCard.stillSize) - 5,
      accuracy: 0.001, "聚焦后标题与放大后的剧照底边留 5pt，同 MediaCard")
  }

  func testEpisodeTextCoversEachServerSubtitleFormat() {
    // Emby、Jellyfin、极空间等：「S2:5 - 集名」
    XCTAssertEqual(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "S2:5 - 集名"), "第 2 季第 5 集")
    // Plex：「S2:E5 - 集名」
    XCTAssertEqual(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "S2:E5 - 集名"), "第 2 季第 5 集")
    XCTAssertEqual(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "S0:1 - 花絮"), "特别篇第 1 集")
    XCTAssertEqual(
      ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "  s10:e12 - 集名  "), "第 10 季第 12 集")
    XCTAssertEqual(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "S1:2"), "第 1 季第 2 集")
  }

  func testEpisodeTextAbsentWhenNumbersMissingOrNotSeries() {
    // 服务器没给季号集号时，后端拼出来的是「SNone:None」
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "SNone:None - 集名"))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "S2:None - 集名"))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: nil))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "   "))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电视剧", subtitle: "2024"))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: "电影", subtitle: "S2:5 - 集名"))
    XCTAssertNil(ContinueWatchingDisplay.episodeText(type: nil, subtitle: "S2:5 - 集名"))
  }

  func testOnlyMovieSubtitleIsUsedAsYear() {
    let movie = ContinueWatchingDisplay.mediaInfo(title: "某片", type: "电影", subtitle: "2024")
    XCTAssertEqual(movie.year, "2024")
    let episode = ContinueWatchingDisplay.mediaInfo(title: "某剧", type: "电视剧", subtitle: "S2:5 - 集名")
    XCTAssertEqual(episode.title, "某剧")
    XCTAssertNil(episode.year, "剧集副标题是季集和集名，不能当年份送去识别")
    // 绿联的剧集副标题是剧名，同样不当年份。
    XCTAssertNil(ContinueWatchingDisplay.mediaInfo(title: "某剧", type: "电视剧", subtitle: "某剧").year)
  }

  /// 飞牛和绿联的电影副标题是「电影」「视频」这类类型名，不是年份；当年份传会让严格匹配落空，
  /// 退回识别时还会把类型名拼进查询串。
  func testNonYearMovieSubtitleIsNotSentAsYear() {
    for subtitle in ["电影", "视频", "剧集", nil, "  ", "2024-01-01", "tt1234567"] {
      XCTAssertNil(
        ContinueWatchingDisplay.mediaInfo(title: "某片", type: "电影", subtitle: subtitle).year,
        subtitle ?? "nil")
    }
    XCTAssertEqual(ContinueWatchingDisplay.mediaInfo(title: "某片", type: "电影", subtitle: " 1998 ").year, "1998")
  }

  func testPercentDecodesWithoutBreakingSparseBatch() throws {
    let items = try JSONDecoder().decode(
      [MediaServerPlayItem].self,
      from: Data(
        """
        [
          {"id":"full","title":"某剧","type":"电视剧","subtitle":"S2:5 - 集名","percent":45.5,
           "item_id":"e1","server_type":"emby"},
          {"id":"null","title":"某片","percent":null},
          {"id":"missing","title":"另一片"},
          {"id":"bad","title":"坏值","percent":"45"}
        ]
        """.utf8))

    XCTAssertEqual(items.count, 4, "个别条目给不出进度数字时不拖垮整批")
    XCTAssertEqual(items[0].percent, 45.5)
    XCTAssertNil(items[1].percent)
    XCTAssertNil(items[2].percent)
    XCTAssertNil(items[3].percent)
    // 「最近添加」没有 percent 键，照常解码。
    XCTAssertEqual(items[2].title, "另一片")
  }
}

/// 「继续观看」行按服务器加载、快照保留和按下目标。走真实 `refreshData()` 入口。
@MainActor
final class HomeContinueWatchingRowTests: XCTestCase {
  private var persistedSelectionKey: String?

  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(HomeContinueWatchingURLProtocol.self))
    HomeContinueWatchingURLProtocol.stub.reset()
    UserDefaults.standard.removeObject(forKey: PlaybackPreferences.inAppPlaybackKey)
    UserDefaults.standard.removeObject(forKey: "homeMediaTapPlaysInApp")
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(HomeContinueWatchingURLProtocol.self)
    HomeContinueWatchingURLProtocol.stub.reset()
    UserDefaults.standard.removeObject(forKey: PlaybackPreferences.inAppPlaybackKey)
    UserDefaults.standard.removeObject(forKey: "homeMediaTapPlaysInApp")
    if let persistedSelectionKey {
      UserDefaults.standard.removeObject(forKey: persistedSelectionKey)
    }
    super.tearDown()
  }

  private func makeService(backendVersion: String = "v3.2.6", admin: Bool = true) -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://home-continue-watching-tests.local"
    service.tokenForTesting = "cw-token"
    service.currentUserForTesting = Token(
      access_token: "cw-token",
      token_type: "bearer",
      super_user: FlexibleBool(admin),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_id: 7,
      user_name: "cw-admin",
      avatar: nil
    )
    service.settings = GlobalSettings(BACKEND_VERSION: backendVersion)
    persistedSelectionKey = service.profileKey.map { "home.continueWatching.selectedServer.v1_\($0)" }
    if let persistedSelectionKey {
      UserDefaults.standard.removeObject(forKey: persistedSelectionKey)
    }
    return service
  }

  func testRowReadsPlayingEndpointPerServerAndSwitchesSelection() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()

    XCTAssertEqual(viewModel.continueWatchingServers, ["emby", "jellyfin"])
    XCTAssertEqual(viewModel.selectedContinueWatchingServer, "emby")
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"])
    XCTAssertFalse(viewModel.continueWatchingLoadFailed)

    let playingRequests = HomeContinueWatchingURLProtocol.stub.requestQueries().filter {
      $0.path == "/api/v1/mediaserver/playing"
    }
    XCTAssertEqual(Set(playingRequests.map { $0.server }), ["emby", "jellyfin"])
    XCTAssertTrue(playingRequests.allSatisfy { $0.count == "20" })

    viewModel.selectedContinueWatchingServer = "jellyfin"
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某片"])
  }

  func testServerFailureKeepsPreviousSnapshotAndOnlyFlagsThisRow() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"])

    HomeContinueWatchingURLProtocol.stub.setPlayingResult(server: "emby", .httpStatus500)
    HomeContinueWatchingURLProtocol.stub.setLatestResult(server: "emby", .success)
    await viewModel.refreshData()

    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"], "失败服务器保留上一轮卡片")
    XCTAssertTrue(viewModel.continueWatchingLoadFailed)
    XCTAssertFalse(viewModel.latestLoadFailed, "另一行读成功，不跟着报失败")
  }

  func testSuccessEmptyClearsOnlyThatServer() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    HomeContinueWatchingURLProtocol.stub.setPlayingResult(server: "emby", .successEmpty)
    await viewModel.refreshData()

    XCTAssertTrue(viewModel.continueWatching.isEmpty, "成功空响应才清空该服务器")
    XCTAssertFalse(viewModel.continueWatchingLoadFailed)
    viewModel.selectedContinueWatchingServer = "jellyfin"
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某片"])
  }

  func testCancellationKeepsSnapshotAndDoesNotFlagFailure() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    HomeContinueWatchingURLProtocol.stub.setPlayingResult(server: "emby", .cancelled)
    await viewModel.refreshData()

    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"])
    XCTAssertFalse(viewModel.continueWatchingLoadFailed)
  }

  func testPlayingRowFailureDoesNotAffectLatestRow() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    HomeContinueWatchingURLProtocol.stub.setPlayingResult(server: "emby", .httpStatus500)
    HomeContinueWatchingURLProtocol.stub.setPlayingResult(server: "jellyfin", .networkError)
    HomeContinueWatchingURLProtocol.stub.setLatestResult(server: "emby", .success)

    await viewModel.refreshData()

    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])
    XCTAssertFalse(viewModel.latestLoadFailed)
    XCTAssertTrue(viewModel.continueWatchingLoadFailed)
    XCTAssertTrue(viewModel.continueWatching.isEmpty)
  }

  func testPressPlaysInAppOnPlayableServer() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(
      viewModel.continueWatchingAction(for: item, server: "emby"),
      .play(.serverEpisode(serverName: "emby", itemID: "e1")))
  }

  /// 电影没有剧集上下文可补，直接播这份文件。
  func testMovieResumePlaysServerItemWithoutEpisodeContext() async throws {
    HomeContinueWatchingURLProtocol.stub.setPlayingBody(
      server: "emby",
      #"[{"id":"m1","item_id":"m1","title":"某片","type":"电影","subtitle":"2024","percent":30,"server_type":"emby"}]"#)
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(item.type, "电影")
    XCTAssertEqual(
      viewModel.continueWatchingAction(for: item, server: "emby"),
      .play(.serverItem(serverName: "emby", itemID: "m1")))
  }

  /// 角标图标必须标出按下真正会做什么，不能一律画播放图标。
  func testBadgeIconMatchesWhatPressDoes() {
    XCTAssertEqual(
      HomeViewModel.ContinueWatchingAction.play(.serverItem(serverName: "emby", itemID: "x")).badgeIcon,
      AppSymbol.play)
    XCTAssertEqual(
      HomeViewModel.ContinueWatchingAction.openInServerApp.badgeIcon, AppSymbol.openInLibrary)
    XCTAssertNil(HomeViewModel.ContinueWatchingAction.detail.badgeIcon, "打开详情页不带图标，同 MediaCard")
  }

  /// 两行各有自己的服务器选择：继续观看的按下目标必须用条目所在的那台，不能跟着「最近添加」的选择。
  func testResumeActionUsesItsOwnServerNotLatestSelection() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    viewModel.selectedLatestMediaServer = "jellyfin"

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(viewModel.selectedContinueWatchingServer, "emby")
    XCTAssertEqual(
      viewModel.continueWatchingAction(for: item, server: viewModel.selectedContinueWatchingServer),
      .play(.serverEpisode(serverName: "emby", itemID: "e1")))
  }

  /// 定时轮询不重读「继续观看」：Jellyfin 后端会为每条续播条目向媒体服务器探测一次封面。
  func testPeriodicRefreshSkipsContinueWatching() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    let playingBefore = requestCount(path: "/api/v1/mediaserver/playing")
    let latestBefore = requestCount(path: "/api/v1/mediaserver/latest")

    await viewModel.refreshData(includeContinueWatching: false)

    XCTAssertEqual(requestCount(path: "/api/v1/mediaserver/playing"), playingBefore, "轮询不得重读继续观看")
    XCTAssertGreaterThan(requestCount(path: "/api/v1/mediaserver/latest"), latestBefore, "最近添加照常轮询")
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"], "快照保持不变")
  }

  private func requestCount(path: String) -> Int {
    HomeContinueWatchingURLProtocol.stub.requestQueries().filter { $0.path == path }.count
  }

  func testPressFallsBackToServerAppWhenInAppPlaybackUnavailable() async throws {
    // v3.2.6 以前没有应用内播放：Emby 支持深链，按下跳它自己的 App（同 Web）。
    let service = makeService(backendVersion: "v3.2.5")
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(viewModel.continueWatchingAction(for: item, server: "emby"), .openInServerApp)
  }

  func testPressOpensDetailWhenServerHasNoDeepLink() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    viewModel.selectedContinueWatchingServer = "jellyfin"

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(viewModel.continueWatchingAction(for: item, server: "jellyfin"), .detail)
  }

  func testNonAdminHidesBothMediaServerRows() async throws {
    let service = makeService(admin: false)
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    XCTAssertTrue(viewModel.continueWatchingServers.isEmpty, "读不到服务器配置就不显示这一行")
    XCTAssertTrue(viewModel.continueWatching.isEmpty)
    XCTAssertFalse(viewModel.continueWatchingLoadFailed)
  }

  /// 「首页媒体在应用内打开」只管「最近添加」，而且默认关闭；「继续观看」不受它影响，按下始终接着看。
  func testHomeTapPreferenceDoesNotChangeContinueWatchingPress() async throws {
    UserDefaults.standard.set(false, forKey: "homeMediaTapPlaysInApp")
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()

    let item = try XCTUnwrap(viewModel.continueWatching.first)
    XCTAssertEqual(
      viewModel.continueWatchingAction(for: item, server: "emby"),
      .play(.serverEpisode(serverName: "emby", itemID: "e1")))
    XCTAssertTrue(viewModel.opensMediaServerApp(item, server: "emby"), "同一开关下「最近添加」仍然跳转")
  }

  func testSelectionPersistsAcrossViewModels() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    viewModel.selectedContinueWatchingServer = "jellyfin"

    let restored = HomeViewModel(apiService: service)
    XCTAssertEqual(restored.selectedContinueWatchingServer, "jellyfin")
    await restored.refreshData()
    XCTAssertEqual(restored.continueWatching.map(\.title), ["某片"])
  }

  /// 再次进入媒体库页要重读「继续观看」：在别的设备上看了一集再回来，这一行不能一直是旧的。
  /// 它不跟轮询，所以页面重新激活是唯一的纠正时机之一。
  func testReactivatingPageRereadsContinueWatching() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.loadData()
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧"])
    let before = requestCount(path: "/api/v1/mediaserver/playing")

    HomeContinueWatchingURLProtocol.stub.setPlayingBody(
      server: "emby",
      #"[{"id":"e2","item_id":"e2","title":"某剧 下一集","type":"电视剧","subtitle":"S2:6 - 集名","percent":10,"server_type":"emby"}]"#)
    await viewModel.loadData()

    XCTAssertGreaterThan(requestCount(path: "/api/v1/mediaserver/playing"), before, "再次进入页面要重读")
    XCTAssertEqual(viewModel.continueWatching.map(\.title), ["某剧 下一集"])
  }

  /// 进度写回完成后的重读只碰「继续观看」和服务器配置，不重读「最近添加」和订阅（它们由轮询负责）。
  func testWatchStateRefreshOnlyReadsContinueWatching() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    let before = HomeContinueWatchingURLProtocol.stub.requestQueries().count

    await viewModel.refreshContinueWatching()

    let added = HomeContinueWatchingURLProtocol.stub.requestQueries().dropFirst(before)
    XCTAssertFalse(added.isEmpty, "要真的重读一次")
    XCTAssertTrue(
      added.allSatisfy {
        $0.path == "/api/v1/mediaserver/playing" || $0.path == "/api/v1/system/setting/MediaServers"
      },
      "多读了别的接口：\(added.map(\.path))")
  }

  /// 服务器读不到条目身份时退回按标题、年份识别（电影的四位数字副标题仍是年份）。
  func testDetailIdentityFallsBackToTitleWhenServerUnreadable() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshData()
    viewModel.selectedContinueWatchingServer = "jellyfin"
    let item = try XCTUnwrap(viewModel.continueWatching.first)

    // 这台服务器没有配置，读不到条目。
    let info = await viewModel.continueWatchingMediaInfo(for: item, server: "jellyfin")
    XCTAssertNil(info.tmdb_id)
    XCTAssertEqual(info.title, "某片")
    XCTAssertEqual(info.year, "2024")
  }

  /// 刷新信号的接线（源码守卫，不代表真机验收）：数据刷新等进度写回完成，焦点恢复仍用播放器刚关那个信号。
  func testContinueWatchingRefreshWaitsForProgressWriteBack() throws {
    let source = try Self.homeViewSource()
    let rowStart = try XCTUnwrap(source.range(of: "private struct MediaSectionView"))
    let page = String(source[..<rowStart.lowerBound])
    let row = String(source[rowStart.lowerBound...])

    XCTAssertTrue(page.contains(".task(id: isSelected)"), "页面重新激活时要重跑加载，切走时停掉轮询")
    XCTAssertTrue(
      page.contains(".onReceive(apiService.sessionScope.playbackCoordinator.watchStateUpdates)"),
      "数据刷新要等停止上报和进度写回发完")
    XCTAssertTrue(page.contains("await viewModel.refreshContinueWatching()"))
    XCTAssertFalse(
      page.contains(".onChange(of: playbackEndedGeneration)"),
      "播放器刚关时进度还没写回媒体服务器，那时读会拿到旧进度，而这一行不跟轮询")
    XCTAssertTrue(row.contains(".onChange(of: playbackEndedGeneration)"), "焦点恢复仍用原来的信号")
  }

  private static func homeViewSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(
      contentsOf: root.appendingPathComponent("MoviePilot-TV/Views/Pages/HomeView.swift"), encoding: .utf8)
  }
}

private enum HomePlayingResult {
  case success
  case successEmpty
  case httpStatus500
  case networkError
  case cancelled
}

private enum HomeLatestRowResult {
  case success
  case empty
}

private struct HomePlayingRequest: Equatable {
  let path: String
  let server: String?
  let count: String?
}

private final class HomeContinueWatchingURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [HomePlayingRequest] = []
  private var playingResults: [String: HomePlayingResult] = [:]
  private var playingBodies: [String: String] = [:]
  private var latestResults: [String: HomeLatestRowResult] = [:]

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    requests = []
    playingResults = ["emby": .success, "jellyfin": .success]
    playingBodies = [:]
    latestResults = [:]
  }

  func setPlayingBody(server: String, _ json: String) {
    lock.lock()
    defer { lock.unlock() }
    playingBodies[server] = json
  }

  func playingBody(for server: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return playingBodies[server]
  }

  func setPlayingResult(server: String, _ result: HomePlayingResult) {
    lock.lock()
    defer { lock.unlock() }
    playingResults[server] = result
  }

  func setLatestResult(server: String, _ result: HomeLatestRowResult) {
    lock.lock()
    defer { lock.unlock() }
    latestResults[server] = result
  }

  func playingResult(for server: String) -> HomePlayingResult {
    lock.lock()
    defer { lock.unlock() }
    return playingResults[server] ?? .successEmpty
  }

  func latestResult(for server: String) -> HomeLatestRowResult {
    lock.lock()
    defer { lock.unlock() }
    return latestResults[server] ?? .empty
  }

  func record(_ request: HomePlayingRequest) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(request)
  }

  func requestQueries() -> [HomePlayingRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }
}

private final class HomeContinueWatchingURLProtocol: URLProtocol {
  static let stub = HomeContinueWatchingURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "home-continue-watching-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let server = queryItem(named: "server", in: url)
    Self.stub.record(
      HomePlayingRequest(path: url.path, server: server, count: queryItem(named: "count", in: url)))

    switch url.path {
    case "/api/v1/system/setting/MediaServers":
      respond(
        statusCode: 200,
        body:
          #"{"value":[{"name":"emby","type":"emby","enabled":true,"config":{"host":"http://emby.local","apikey":"k"}},{"name":"jellyfin","type":"jellyfin","enabled":true}]}"#
      )
    case "/api/v1/mediaserver/playing":
      switch Self.stub.playingResult(for: server ?? "") {
      case .success:
        respond(
          statusCode: 200,
          body: Self.stub.playingBody(for: server ?? "") ?? Self.playingItems(server: server ?? ""))
      case .successEmpty:
        respond(statusCode: 200, body: "[]")
      case .httpStatus500:
        respond(statusCode: 500, body: #"{"message":"server unavailable"}"#)
      case .networkError:
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      case .cancelled:
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
      }
    case "/api/v1/mediaserver/latest":
      switch Self.stub.latestResult(for: server ?? "") {
      case .success:
        respond(
          statusCode: 200,
          body: #"[{"id":"\#(server ?? "")-latest","title":"Emby Latest","server_type":"\#(server ?? "")"}]"#)
      case .empty:
        respond(statusCode: 200, body: "[]")
      }
    default:
      respond(statusCode: 200, body: "[]")
    }
  }

  override func stopLoading() {}

  private static func playingItems(server: String) -> String {
    if server == "emby" {
      return
        #"[{"id":"e1","item_id":"e1","title":"某剧","type":"电视剧","subtitle":"S2:5 - 集名","percent":45.5,"server_type":"emby"}]"#
    }
    return
      #"[{"id":"j1","item_id":"j1","title":"某片","type":"电影","subtitle":"2024","percent":10,"server_type":"jellyfin"}]"#
  }

  private func queryItem(named name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .first { $0.name == name }?
      .value
  }

  private func respond(statusCode: Int, body: String) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}