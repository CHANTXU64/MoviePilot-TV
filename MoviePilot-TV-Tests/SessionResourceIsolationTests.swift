import XCTest
import Kingfisher

@testable import MoviePilot_TV

@MainActor
extension SystemSessionBehaviorTests {
  func testNotificationAutoHideSurvivesSameAccountTokenRefresh() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let account = sessionToken(userId: 1, accessToken: "a-1", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: account.access_token,
      currentUser: account
    )
    let notification = NotificationManager()
    notification.show(message: "保存成功", duration: 0.02)
    let originalUIIdentity = service.uiIdentity

    let refreshed = sessionToken(userId: 1, accessToken: "a-2", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: refreshed.access_token,
      currentUser: refreshed
    )

    XCTAssertEqual(service.uiIdentity, originalUIIdentity)
    try await waitUntil { !notification.isShowing }
  }

  func testNotificationHidesImmediatelyWhenAccountChanges() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let accountA = sessionToken(userId: 1, accessToken: "a-1", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let notification = NotificationManager()
    notification.show(message: "账号 A 的提示", duration: 60)

    let accountB = sessionToken(userId: 2, accessToken: "b-1", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountB.access_token,
      currentUser: accountB
    )

    XCTAssertFalse(notification.isShowing)
  }

  func testProtectedImageCacheAndCookieAreSessionScopedWhilePublicImagesStayShared() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setResourceCookie("resource_cookie=account-a")
    let service = APIService.testingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    _ = try await service.login(
      username: "account-a",
      password: "password",
      serverURL: "https://session-refresh-tests.local"
    )
    _ = try await service.fetchSettings()

    let cookieHeader = await SessionRefreshURLProtocol.stub.header(
      named: "Cookie",
      forPath: "/api/v1/system/global"
    )
    XCTAssertEqual(cookieHeader, "resource_cookie=account-a")
    let protectedURL = try XCTUnwrap(
      URL(string: "https://session-refresh-tests.local/api/v1/system/img/poster")
    )
    let publicURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))
    let protectedKeyA = service.imageSource(for: protectedURL).cacheKey
    let publicKeyA = service.imageSource(for: publicURL).cacheKey
    let modifiedRequest = service.imageRequestModifier(for: protectedURL)?.modified(
      for: URLRequest(url: protectedURL)
    )
    XCTAssertEqual(modifiedRequest?.value(forHTTPHeaderField: "Cookie"), "resource_cookie=account-a")

    let accountB = sessionToken(userId: 2, accessToken: "account-b-token", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    XCTAssertNotEqual(service.imageSource(for: protectedURL).cacheKey, protectedKeyA)
    XCTAssertEqual(service.imageSource(for: publicURL).cacheKey, publicKeyA)
    XCTAssertNil(
      service.imageRequestModifier(for: protectedURL)?.modified(
        for: URLRequest(url: protectedURL)
      )?.value(forHTTPHeaderField: "Cookie")
    )
  }

  func testProtectedImageRecognitionIncludesConfiguredServerPath() throws {
    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()
    service.replaceSessionForTesting(
      baseURL: "https://account.local/moviepilot",
      token: nil,
      currentUser: nil
    )

    let protectedURL = try XCTUnwrap(
      URL(string: "https://account.local/moviepilot/api/v1/system/img/poster")
    )
    let wrongRootURL = try XCTUnwrap(
      URL(string: "https://account.local/api/v1/system/img/poster")
    )

    XCTAssertTrue(service.isProtectedImageURL(protectedURL))
    XCTAssertNotNil(service.imageDownloader(for: protectedURL))
    XCTAssertTrue(service.imageSource(for: protectedURL).cacheKey.hasPrefix("moviepilot-protected:"))
    XCTAssertFalse(service.isProtectedImageURL(wrongRootURL))
  }

  func testMediaPreloaderPreservesSameAccountRefreshAndClearsAccountSwitchSynchronously() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let accountA = sessionToken(userId: 1, accessToken: "a-1", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let preloader = service.mediaPreloader
    defer { preloader.clearAll() }
    let media = MediaInfo(title: "账号缓存边界", type: "collection", collection_id: 9_002)
    let cachedTask = preloader.preload(for: media)

    let refreshedAccountA = sessionToken(userId: 1, accessToken: "a-2", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: refreshedAccountA.access_token,
      currentUser: refreshedAccountA
    )
    XCTAssertTrue(service.mediaPreloader === preloader)
    XCTAssertTrue(preloader.peekTask(for: media) === cachedTask)

    let accountB = sessionToken(userId: 2, accessToken: "b-1", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    // 换账号时旧作用域同步拆除，新作用域是另一个空缓存的实例。
    XCTAssertNil(preloader.peekTask(for: media))
    XCTAssertFalse(service.mediaPreloader === preloader)
    XCTAssertNil(service.mediaPreloader.peekTask(for: media))
  }

  func testNavigationCoordinatorPinsIntoCurrentSessionPreloader() {
    // replaceSessionForTesting 即使不持久化会话，也会写全局 serverURL，退出前必须恢复。
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }

    let service = APIService.testingInstance()
    let coordinator = ImageNavigationCoordinator(apiService: service)

    let accountA = sessionToken(userId: 11, accessToken: "nav-a", userName: "nav-account-a")
    service.replaceSessionForTesting(
      baseURL: "https://navigation.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let preloaderA = service.mediaPreloader
    let mediaA = MediaInfo(tmdb_id: 51_001, title: "旧会话导航", type: "电影")
    coordinator.push(mediaA)
    XCTAssertNotNil(preloaderA.peekTask(for: mediaA))

    let accountB = sessionToken(userId: 12, accessToken: "nav-b", userName: "nav-account-b")
    service.replaceSessionForTesting(
      baseURL: "https://navigation.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    let preloaderB = service.mediaPreloader
    defer { preloaderB.clearAll() }
    XCTAssertFalse(preloaderA === preloaderB)

    // 协调器在调用时解析预载器：换账号后 Push 必须落在新作用域，而不是已拆除的旧实例。
    let mediaB = MediaInfo(tmdb_id: 51_002, title: "新会话导航", type: "电影")
    coordinator.push(mediaB)
    XCTAssertNotNil(preloaderB.peekTask(for: mediaB))
    XCTAssertNil(preloaderA.peekTask(for: mediaB))
  }
}
