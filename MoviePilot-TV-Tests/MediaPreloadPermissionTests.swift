import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaPreloadPermissionTests: XCTestCase {
  func testRestrictedUserTvDetailDoesNotWaitForHiddenSeasonRow() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureLimitedUser(service)

    let preloadTask = MediaPreloadTask(
      partialMedia: MediaInfo(tmdb_id: 123, title: "Limited Show", type: "电视剧")
    )
    let viewModel = MediaDetailViewModel(
      detail: MediaInfo(tmdb_id: 123, title: "Limited Show", type: "电视剧")
    )
    viewModel.preloadTask = preloadTask

    viewModel.applyFullDetail(
      MediaInfo(tmdb_id: 123, title: "Limited Show", type: "电视剧")
    )

    try await waitUntil("first row ready without hidden season row") {
      viewModel.isFirstRowReady
    }
  }

  func testRestrictedUserTvPreloadDoesNotRequestSeasonSubscriptionState() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureLimitedUser(service)

    let task = MediaPreloadTask(
      partialMedia: MediaInfo(tmdb_id: 123, title: "Limited Show", type: "电视剧")
    )
    task.start()

    try await waitUntil("detail ready") {
      task.isDetailReady
    }
    try await Task.sleep(nanoseconds: 300_000_000)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/mediaserver/notexists"))
    XCTAssertFalse(paths.containsSubscribeListPath)
    XCTAssertNil(task.seasonViewModel)
    XCTAssertFalse(task.isSeasonDataLoaded)
  }

  func testRestrictedSeasonStatusRefreshDoesNotRequestSubscribeSnapshot() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureLimitedUser(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 123, title: "Limited Show", type: "电视剧")
    )

    let didRefresh = await viewModel.checkSubscriptionStatus(forceRefresh: true)

    XCTAssertFalse(didRefresh)
    XCTAssertTrue(viewModel.seasonSubscriptions.isEmpty)
    XCTAssertTrue(viewModel.subscribedSeasons.isEmpty)
    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.containsSubscribeListPath)
  }

  func testRestrictedUserMoviePreloadDoesNotRequestSubscriptionLookup() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureLimitedUser(service)

    let task = MediaPreloadTask(
      partialMedia: MediaInfo(tmdb_id: 456, title: "Limited Movie", type: "电影")
    )
    task.start()

    try await waitUntil("detail ready") {
      task.isDetailReady
    }
    try await Task.sleep(nanoseconds: 300_000_000)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/subscribe/media/") })
  }

  func testSubscriptionStatusPermissionFailureSurfacesAndDoesNotLogoutOrRetryLogin() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    MediaPreloadPermissionURLProtocol.stub.setSubscriptionLookupStatusCode(403)
    configureStandardSubscriber(service)
    setStoredCredential(account: "username", value: "subscriber")
    setStoredCredential(account: "password", value: "stale-password")

    do {
      _ = try await service.checkSubscription(
        media: MediaInfo(tmdb_id: 456, title: "Subscriber Movie", type: "电影")
      )
      XCTFail("Expected subscription status permission failure to be surfaced.")
    } catch APIError.serverMessage(let message) {
      XCTAssertTrue(message.contains("403"))
    }

    XCTAssertEqual(service.token, "subscriber-token")
    XCTAssertEqual(service.currentUser?.user_name, "subscriber")

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains { $0.hasPrefix("/api/v1/subscribe/media/") })
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testStandardSubscriberTvPreloadRequestsSeasonAvailabilityWithoutSuperUser() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureStandardSubscriber(service)

    let task = MediaPreloadTask(
      partialMedia: MediaInfo(tmdb_id: 123, title: "Subscriber Show", type: "电视剧")
    )
    task.start()

    try await waitUntil("season data ready") {
      task.isSeasonDataLoaded
    }
    try await Task.sleep(nanoseconds: 300_000_000)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/mediaserver/notexists"))
    XCTAssertTrue(paths.containsSubscribeListPath)
    XCTAssertNotNil(task.seasonViewModel)
  }

  func testSeasonAvailabilityPermissionFailureDoesNotLogoutSubscriber() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    MediaPreloadPermissionURLProtocol.stub.setSeasonAvailabilityStatusCode(403)
    configureStandardSubscriber(service)

    do {
      _ = try await service.checkSeasonsNotExists(
        mediaInfo: MediaInfo(tmdb_id: 123, title: "Subscriber Show", type: "电视剧")
      )
      XCTFail("Expected season availability permission failure to surface as unauthorized")
    } catch APIError.serverMessage(let message) {
      XCTAssertTrue(message.contains("403"))
      // Expected: optional status probe must not trigger logout.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(service.token, "subscriber-token")
    XCTAssertEqual(service.currentUser?.user_name, "subscriber")

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/mediaserver/notexists"))
  }

  func testSeasonAvailabilityPermissionFailureKeepsStatusUnknownAndDoesNotDefaultBestVersion()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    MediaPreloadPermissionURLProtocol.stub.setSeasonAvailabilityStatusCode(403)
    configureStandardSubscriber(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 123, title: "Subscriber Show", type: "电视剧")
    )

    await viewModel.checkSeasonsStatus()
    viewModel.prepareSubscription(seasonNumber: 1)

    XCTAssertFalse(viewModel.isSeasonAvailabilityLoaded)
    XCTAssertTrue(viewModel.seasonsNotExisted.isEmpty)
    XCTAssertNil(viewModel.getStatusText(season: 1))
    XCTAssertEqual(viewModel.sheetSubscribe?.best_version, 0)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/mediaserver/notexists"))
  }

  func testSuperUserActionAPIsDoNotApplyLocalPermissionGate() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureStandardSubscriber(service)

    let history = TransferHistory(
      id: 77,
      title: "Subscriber History",
      type: "电影",
      seasons: nil,
      episodes: nil,
      category: nil,
      src: "/downloads/movie.mkv",
      dest: nil,
      src_storage: "local",
      dest_storage: nil,
      mode: "move",
      status: FlexibleBool(false),
      errmsg: nil,
      src_fileitem: FileItem(name: "movie.mkv", path: "/downloads/movie.mkv", type: "file", size: nil),
      date: nil
    )
    let form = ReorganizeForm(
      fileitem: nil,
      logid: history.id,
      target_storage: nil,
      transfer_type: nil,
      target_path: "",
      min_filesize: 0,
      scrape: nil,
      from_history: true
    )

    _ = try? await service.deleteTransferHistory(
      item: history,
      deleteSource: false,
      deleteDest: false
    )
    _ = try? await service.aiRedoTransferHistory(ids: [history.id])
    _ = try? await service.manualTransfer(
      form: form,
      background: false
    )

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/history/transfer"))
    XCTAssertTrue(paths.contains("/api/v1/history/transfer/ai-redo"))
    XCTAssertTrue(paths.contains("/api/v1/transfer/manual"))
  }

  func testStandardUserHiddenAdminSurfacesDoNotRequestSuperUserEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureStandardSubscriber(service)

    let statusViewModel = StatusViewModel()
    await statusViewModel.refreshAllData()

    let homeViewModel = HomeViewModel(apiService: service)
    await homeViewModel.refreshData()

    let downloadViewModel = DownloadTaskViewModel()
    await downloadViewModel.initialLoad()

    let transferViewModel = TransferHistoryViewModel()
    await transferViewModel.refresh()

    XCTAssertNil(statusViewModel.statistic)
    XCTAssertNil(statusViewModel.storage)
    XCTAssertNil(statusViewModel.downloader)
    XCTAssertTrue(homeViewModel.latestMedia.isEmpty)
    XCTAssertTrue(homeViewModel.latestMediaServers.isEmpty)
    XCTAssertTrue(downloadViewModel.clients.isEmpty)
    XCTAssertTrue(downloadViewModel.downloads.isEmpty)
    XCTAssertTrue(transferViewModel.items.isEmpty)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/dashboard/") })
    XCTAssertFalse(paths.contains("/api/v1/system/setting/MediaServers"))
    XCTAssertFalse(paths.contains("/api/v1/mediaserver/latest"))
    XCTAssertFalse(paths.contains("/api/v1/history/transfer"))
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/download/") })
  }

  func testManageUserEntrypointsRequestDashboardDownloadAndLatestMediaEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureManageUser(service)

    let statusViewModel = StatusViewModel()
    await statusViewModel.refreshAllData()

    let homeViewModel = HomeViewModel(apiService: service)
    await homeViewModel.refreshData()

    let downloadViewModel = DownloadTaskViewModel()
    await downloadViewModel.initialLoad()

    XCTAssertEqual(statusViewModel.statistic?.movie_count, 2)
    XCTAssertEqual(statusViewModel.statistic?.tv_count, 3)
    XCTAssertEqual(statusViewModel.storage?.total_storage, 100)
    XCTAssertEqual(statusViewModel.storage?.used_storage, 40)
    XCTAssertEqual(statusViewModel.downloader?.download_speed, 7)
    XCTAssertEqual(homeViewModel.latestMediaServers, ["emby"])
    XCTAssertEqual(homeViewModel.latestMedia.map(\.title), ["Latest Movie"])
    XCTAssertEqual(downloadViewModel.clients.map(\.name), ["qbittorrent"])
    XCTAssertEqual(downloadViewModel.selectedClient, "qbittorrent")

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/dashboard/statistic"))
    XCTAssertTrue(paths.contains("/api/v1/dashboard/storage"))
    XCTAssertTrue(paths.contains("/api/v1/dashboard/downloader"))
    XCTAssertTrue(paths.contains("/api/v1/system/setting/MediaServers"))
    XCTAssertTrue(paths.contains("/api/v1/mediaserver/latest"))
    XCTAssertTrue(paths.contains("/api/v1/download/clients"))
    XCTAssertTrue(paths.contains { $0 == "/api/v1/download" || $0 == "/api/v1/download/" })
  }

  func testNoSearchUserResourceActionsDoNotRequestSearchOrDownloadEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureNoSearchUser(service)

    let settingsViewModel = SystemViewModel()
    settingsViewModel.defaultSearchSites = [1, 2]
    defer { settingsViewModel.defaultSearchSites = [] }

    let resourceViewModel = ResourceResultViewModel(keyword: "Blocked")
    await resourceViewModel.search()

    let addDownloadViewModel = AddDownloadViewModel(
      torrent: TorrentInfo(
        site: nil,
        site_name: nil,
        site_order: nil,
        title: "blocked.torrent",
        description: nil,
        enclosure: nil,
        page_url: nil,
        size: 1,
        seeders: nil,
        peers: nil,
        pubdate: nil,
        uploadvolumefactor: 1,
        downloadvolumefactor: 1,
        pri_order: nil,
        labels: nil,
        volume_factor: nil
      )
    )
    await addDownloadViewModel.loadData()

    let siteFilterViewModel = SiteFilterViewModel()
    await siteFilterViewModel.loadSites()

    let normalizedSites = await SystemViewModel.normalizedDefaultSearchSitesString()

    XCTAssertTrue(resourceViewModel.results.isEmpty)
    XCTAssertTrue(addDownloadViewModel.downloaders.isEmpty)
    XCTAssertTrue(addDownloadViewModel.directories.isEmpty)
    XCTAssertTrue(siteFilterViewModel.availableSites.isEmpty)
    XCTAssertNil(normalizedSites)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/search/") })
    XCTAssertFalse(paths.contains("/api/v1/system/setting/IndexerSites"))
    XCTAssertFalse(paths.contains("/api/v1/site/rss"))
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/download") })
  }

  private func configureLimitedUser(_ service: APIService) {
    service.baseURL = "https://preload-permission-tests.local"
    service.token = "limited-token"
    service.currentUser = Token(
      access_token: "limited-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "limited",
      avatar: nil
    )
  }

  private func configureStandardSubscriber(_ service: APIService) {
    service.baseURL = "https://preload-permission-tests.local"
    service.token = "subscriber-token"
    service.currentUser = Token(
      access_token: "subscriber-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "subscriber",
      avatar: nil
    )
  }

  private func configureManageUser(_ service: APIService) {
    service.baseURL = "https://preload-permission-tests.local"
    service.token = "manage-token"
    service.currentUser = Token(
      access_token: "manage-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "manager",
      avatar: nil
    )
  }

  private func configureNoSearchUser(_ service: APIService) {
    service.baseURL = "https://preload-permission-tests.local"
    service.token = "no-search-token"
    service.currentUser = Token(
      access_token: "no-search-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "no-search",
      avatar: nil
    )
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    predicate: @escaping @MainActor () -> Bool
  ) async throws {
    let start = ContinuousClock.now
    while !predicate() {
      if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
        XCTFail("Timed out waiting for \(description)")
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }

  private func setStoredCredential(account: String, value: String) {
    if KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: account) {
      UserDefaults.standard.removeObject(forKey: account)
    } else {
      UserDefaults.standard.set(value, forKey: account)
    }
  }
}

private extension Array where Element == String {
  var containsSubscribeListPath: Bool {
    contains { $0 == "/api/v1/subscribe" || $0 == "/api/v1/subscribe/" }
  }
}

private struct MediaPreloadPermissionServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?
  let usernameKeychain: String?
  let usernameDefaults: String?
  let passwordKeychain: String?
  let passwordDefaults: String?

  @MainActor
  static func capture(service: APIService) -> MediaPreloadPermissionServiceSnapshot {
    MediaPreloadPermissionServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser"),
      usernameKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username"),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    restoreUserDefaultsString(serverURLDefaults, forKey: "serverURL")
    restoreCredential(account: "accessToken", keychainValue: tokenKeychain, defaultsValue: tokenDefaults)
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
    restoreCredential(account: "username", keychainValue: usernameKeychain, defaultsValue: usernameDefaults)
    restoreCredential(account: "password", keychainValue: passwordKeychain, defaultsValue: passwordDefaults)
  }

  @MainActor
  private func restoreUserDefaultsString(_ value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(
        keychainValue,
        service: "MoviePilot-TV",
        account: account
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }
    restoreUserDefaultsString(defaultsValue, forKey: account)
  }
}

private final class MediaPreloadPermissionURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []
  private var seasonAvailabilityStatusCode = 200
  private var subscriptionLookupStatusCode = 200

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    paths = []
    seasonAvailabilityStatusCode = 200
    subscriptionLookupStatusCode = 200
  }

  func setSeasonAvailabilityStatusCode(_ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    seasonAvailabilityStatusCode = statusCode
  }

  func setSubscriptionLookupStatusCode(_ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    subscriptionLookupStatusCode = statusCode
  }

  func requestPaths() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return paths
  }

  func response(for request: URLRequest) -> (Int, Data) {
    let path = request.url?.path ?? ""
    lock.lock()
    paths.append(path)
    lock.unlock()

    switch path {
    case "/api/v1/media/tmdb:123":
      return (200, jsonData(#"{"tmdb_id":123,"title":"Limited Show","type":"电视剧"}"#))
    case "/api/v1/media/tmdb:456":
      return (200, jsonData(#"{"tmdb_id":456,"title":"Limited Movie","type":"电影"}"#))
    case "/api/v1/media/groups/123",
      "/api/v1/media/seasons",
      "/api/v1/subscribe/":
      return (200, jsonData("[]"))
    case "/api/v1/mediaserver/notexists":
      lock.lock()
      let statusCode = seasonAvailabilityStatusCode
      lock.unlock()
      return (statusCode, jsonData("[]"))
    case "/api/v1/system/env":
      return (200, jsonData(#"{"VERSION":"v2.13.14"}"#))
    case "/api/v1/dashboard/statistic":
      return (200, jsonData(#"{"movie_count":2,"tv_count":3,"episode_count":4}"#))
    case "/api/v1/dashboard/storage":
      return (200, jsonData(#"{"total_storage":100,"used_storage":40}"#))
    case "/api/v1/dashboard/downloader":
      return (
        200,
        jsonData(
          #"{"download_speed":7,"upload_speed":1,"download_size":20,"upload_size":2,"free_space":60}"#)
      )
    case "/api/v1/system/setting/MediaServers":
      return (200, jsonData(#"{"value":[{"name":"emby","type":"emby","enabled":true}]}"#))
    case "/api/v1/mediaserver/latest":
      return (
        200,
        jsonData(
          #"""
          [
            {"id":"latest-1","item_id":"latest-1","server_id":"server-1","title":"Latest Movie","subtitle":null,"type":"电影","image":null,"link":null,"use_cookies":false,"server_type":"emby"}
          ]
          """#)
      )
    case "/api/v1/download/clients":
      return (
        200,
        jsonData(#"[{"name":"qbittorrent","type":"qbittorrent","enabled":true}]"#)
      )
    case "/api/v1/download", "/api/v1/download/":
      return (
        200,
        jsonData(
          #"""
          [
            {"hash":"hash","title":"Download Task","state":"downloading","progress":10,"username":"manager"}
          ]
          """#)
      )
    case "/api/v1/download/stop/hash",
      "/api/v1/download/start/hash",
      "/api/v1/download/hash":
      return (200, jsonData(#"{"success":true,"message":"ok"}"#))
    case "/api/v1/system/setting/UserFilterRuleGroups":
      return (200, jsonData(#"{"value":[{"name":"普通规则组"}]}"#))
    case "/api/v1/system/setting/CustomFilterRules":
      return (200, jsonData(#"{"value":[{"id":"allow-all","name":"Allow All"}]}"#))
    default:
      if path.hasPrefix("/api/v1/tmdb/credits/")
        || path.hasPrefix("/api/v1/tmdb/recommend/")
        || path.hasPrefix("/api/v1/tmdb/similar/")
      {
        return (200, jsonData("[]"))
      }
      if path.hasPrefix("/api/v1/subscribe/media/") {
        lock.lock()
        let statusCode = subscriptionLookupStatusCode
        lock.unlock()
        return (statusCode, jsonData(#"{"id":null}"#))
      }
      return (200, jsonData("[]"))
    }
  }

  private func jsonData(_ body: String) -> Data {
    Data(body.utf8)
  }
}

private final class MediaPreloadPermissionURLProtocol: URLProtocol {
  static let stub = MediaPreloadPermissionURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "preload-permission-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let (status, data) = Self.stub.response(for: request)
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: APIError.invalidURL)
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
