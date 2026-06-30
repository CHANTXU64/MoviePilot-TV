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

  func testStandardSubscriberTvPreloadDoesNotRequestSuperUserSeasonAvailability() async throws {
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
    XCTAssertFalse(paths.contains("/api/v1/mediaserver/notexists"))
    XCTAssertTrue(paths.containsSubscribeListPath)
    XCTAssertNotNil(task.seasonViewModel)
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

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    paths = []
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
      "/api/v1/mediaserver/notexists",
      "/api/v1/subscribe/":
      return (200, jsonData("[]"))
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
