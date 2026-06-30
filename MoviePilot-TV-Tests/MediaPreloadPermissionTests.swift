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

    let result = try await service.checkSeasonsNotExists(
      mediaInfo: MediaInfo(tmdb_id: 123, title: "Subscriber Show", type: "电视剧")
    )

    XCTAssertTrue(result.isEmpty)
    XCTAssertEqual(service.token, "subscriber-token")
    XCTAssertEqual(service.currentUser?.user_name, "subscriber")

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/mediaserver/notexists"))
  }

  func testRestrictedUserSubscriptionActionsDoNotRequestSubscribeEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureLimitedUser(service)

    let subscribe = Subscribe(id: 901, name: "Limited Movie", type: "电影", tmdbid: 456)
    let request = SubscribeRequest(
      name: "Limited Movie",
      type: "电影",
      year: nil,
      tmdbid: 456,
      doubanid: nil,
      bangumiid: nil,
      season: nil,
      best_version: 0,
      best_version_full: nil,
      episode_group: nil
    )
    let share = try JSONDecoder().decode(
      SubscribeShare.self,
      from: Data(#"{"id":88,"share_title":"Limited Share"}"#.utf8)
    )

    let didSave = (try? await service.saveSubscription(subscribe)) ?? false
    let addedId = try? await service.addSubscription(request: request, subscribe: subscribe)
    let didDeleteById = (try? await service.deleteSubscription(id: 901)) ?? false
    let didDeleteByMedia = (try? await service.deleteSubscription(mediaId: "tmdb:456", season: nil)) ?? false
    let forkedId = try? await service.forkSubscription(share: share)
    let didUpdate = (try? await service.updateSubscriptionStatus(id: 901, state: "S")) ?? false
    let didSearch = (try? await service.searchSubscription(id: 901)) ?? false
    let didReset = (try? await service.resetSubscription(id: 901)) ?? false
    let shares = try await service.fetchSubscriptionShares(path: "/subscribe/shares")
    let searchedShares = try await service.searchSubscriptionShares(query: "Limited")

    XCTAssertFalse(didSave)
    XCTAssertNil(addedId)
    XCTAssertFalse(didDeleteById)
    XCTAssertFalse(didDeleteByMedia)
    XCTAssertNil(forkedId)
    XCTAssertFalse(didUpdate)
    XCTAssertFalse(didSearch)
    XCTAssertFalse(didReset)
    XCTAssertTrue(shares.isEmpty)
    XCTAssertTrue(searchedShares.isEmpty)

    do {
      _ = try await service.fetchSubscription(id: 901)
      XCTFail("Restricted user should not fetch subscription detail")
    } catch {
      // Local permission failure is expected; the important part is that no request is sent.
    }

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/subscribe") })
  }

  func testStandardUserReorganizeActionsDoNotRequestSuperUserEndpoints() async throws {
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

    let didDelete = (try? await service.deleteTransferHistory(
      item: history,
      deleteSource: false,
      deleteDest: false
    )) ?? false
    let aiRedo = try? await service.aiRedoTransferHistory(ids: [history.id])
    let didManualTransfer = (try? await service.manualTransfer(
      form: form,
      background: false
    )) ?? false

    XCTAssertFalse(didDelete)
    XCTAssertNil(aiRedo)
    XCTAssertFalse(didManualTransfer)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/history/transfer"))
    XCTAssertFalse(paths.contains("/api/v1/history/transfer/ai-redo"))
    XCTAssertFalse(paths.contains("/api/v1/transfer/manual"))
  }

  func testStandardUserHiddenAdminSurfacesDoNotRequestSuperUserEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(MediaPreloadPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(MediaPreloadPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = MediaPreloadPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    MediaPreloadPermissionURLProtocol.stub.reset()
    configureStandardSubscriber(service)

    let statistic = try await service.fetchStatistic()
    let storage = try await service.fetchStorage()
    let downloader = try await service.fetchDownloaderInfo()
    let env = try await service.fetchSystemEnv()
    let mediaServers = try await service.fetchMediaServers()
    let latest = try await service.fetchMediaServerLatest(server: "emby")
    let filterGroups = try await service.fetchFilterRuleGroups()
    let customRules = try await service.fetchCustomFilterRules()
    let history = try await service.fetchTransferHistory(page: 1, count: 20, title: nil)
    let downloading = try await service.fetchDownloading(clientName: "qbittorrent")
    let stopped = try await service.stopDownload(clientName: "qbittorrent", hash: "hash")
    let started = try await service.startDownload(clientName: "qbittorrent", hash: "hash")
    let deleted = try await service.deleteDownload(clientName: "qbittorrent", hash: "hash")

    XCTAssertEqual(statistic.movie_count, 0)
    XCTAssertEqual(statistic.tv_count, 0)
    XCTAssertEqual(storage.total_storage, 0)
    XCTAssertEqual(storage.used_storage, 0)
    XCTAssertEqual(downloader.download_speed, 0)
    XCTAssertEqual(env.VERSION, "v2.13.14")
    XCTAssertTrue(mediaServers.isEmpty)
    XCTAssertTrue(latest.isEmpty)
    XCTAssertEqual(filterGroups.map(\.name), ["普通规则组"])
    XCTAssertTrue(customRules.isEmpty)
    XCTAssertTrue(history.list.isEmpty)
    XCTAssertEqual(history.total, 0)
    XCTAssertTrue(downloading.isEmpty)
    XCTAssertFalse(stopped.success)
    XCTAssertFalse(started.success)
    XCTAssertFalse(deleted.success)

    let paths = MediaPreloadPermissionURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/dashboard/") })
    XCTAssertTrue(paths.contains("/api/v1/system/env"))
    XCTAssertFalse(paths.contains("/api/v1/system/setting/MediaServers"))
    XCTAssertFalse(paths.contains("/api/v1/mediaserver/latest"))
    XCTAssertTrue(paths.contains("/api/v1/system/setting/UserFilterRuleGroups"))
    XCTAssertFalse(paths.contains("/api/v1/system/setting/CustomFilterRules"))
    XCTAssertFalse(paths.contains("/api/v1/history/transfer"))
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/download/") })
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

    do {
      for try await _ in service.searchTitleStream(keyword: "Blocked", sites: nil) {}
    } catch {
    }
    do {
      for try await _ in service.searchMediaStream(
        keyword: "tmdb:123",
        type: "电影",
        area: "title",
        title: "Blocked",
        year: "2026",
        season: nil,
        sites: nil
      ) {}
    } catch {
    }

    let resources = (try? await service.searchResources(keyword: "Blocked")) ?? []
    let indexerSites = (try? await service.fetchIndexerSites()) ?? []
    let normalizedSites = await SystemViewModel.normalizedDefaultSearchSitesString()
    let addDownloadResult = (try? await service.addDownload(
      payload: AddDownloadRequest(
        torrent_in: TorrentInfo(
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
        ),
        downloader: nil,
        save_path: nil,
        media_in: nil,
        tmdbid: nil,
        doubanid: nil
      ),
      endpoint: "/download/add"
    )) ?? (success: false, message: nil)

    XCTAssertTrue(resources.isEmpty)
    XCTAssertTrue(indexerSites.isEmpty)
    XCTAssertNil(normalizedSites)
    XCTAssertFalse(addDownloadResult.success)

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
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
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

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    paths = []
    seasonAvailabilityStatusCode = 200
  }

  func setSeasonAvailabilityStatusCode(_ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    seasonAvailabilityStatusCode = statusCode
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
    case "/api/v1/system/setting/UserFilterRuleGroups":
      return (200, jsonData(#"{"value":[{"name":"普通规则组"}]}"#))
    default:
      if path.hasPrefix("/api/v1/tmdb/credits/")
        || path.hasPrefix("/api/v1/tmdb/recommend/")
        || path.hasPrefix("/api/v1/tmdb/similar/")
      {
        return (200, jsonData("[]"))
      }
      if path.hasPrefix("/api/v1/subscribe/media/") {
        return (200, jsonData(#"{"id":null}"#))
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
