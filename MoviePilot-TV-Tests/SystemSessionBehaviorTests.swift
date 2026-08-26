import XCTest
import Kingfisher

@testable import MoviePilot_TV

@MainActor
final class SystemSessionBehaviorTests: XCTestCase {
  func testRefreshStoredSessionAfterAppUpdateClearsTokenAndReloginsOnce() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stale-token"
    service.currentUserForTesting = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let firstResult = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )
    let secondResult = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )

    XCTAssertEqual(firstResult, .refreshed)
    XCTAssertEqual(secondResult, .alreadyRefreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertNil(effectiveCredential(account: "username"))
    XCTAssertNil(effectiveCredential(account: "password"))
    let persistence = service.persistenceSnapshotForTesting()
    XCTAssertEqual(persistence.username, "test-user")
    XCTAssertEqual(persistence.password, "test-password")
    XCTAssertEqual(UserDefaults.standard.string(forKey: markerKey), "v0.4.0")

    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(
      paths.filter { $0 == "/api/v1/login/access-token" },
      ["/api/v1/login/access-token"]
    )
  }

  func testRefreshStoredSessionRequiresReauthenticationWhenCredentialsAreRejected() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stale-token"
    service.currentUserForTesting = Token(
      access_token: "stale-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "stale-user",
      avatar: nil
    )
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let logoutNotifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .sessionDidLogout,
      object: nil,
      queue: nil
    ) { _ in
      logoutNotifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.1"
    )

    XCTAssertEqual(result, .refreshFailed)
    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertEqual(service.loginDraft?.serverURL, "https://session-refresh-tests.local")
    XCTAssertEqual(service.loginDraft?.username, "test-user")
    XCTAssertEqual(service.loginDraft?.password, "test-password")
    XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected)
    let logoutNotificationCount = logoutNotifications.count()
    XCTAssertEqual(logoutNotificationCount, 0)
    XCTAssertNil(UserDefaults.standard.string(forKey: markerKey))
    XCTAssertNil(effectiveCredential(account: "username"))
    XCTAssertNil(effectiveCredential(account: "password"))
  }

  func testRefreshStoredSessionKeepsExistingSessionWhenStoredCredentialsAreMissing() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "existing-token"
    service.currentUserForTesting = Token(
      access_token: "existing-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "existing-user",
      avatar: nil
    )
    UserDefaults.standard.removeObject(forKey: markerKey)
    clearCredential(account: "username")
    clearCredential(account: "password")
    service.setStoredCredentialsForTesting(username: nil, password: nil)

    let logoutNotifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .sessionDidLogout,
      object: nil,
      queue: nil
    ) { _ in
      logoutNotifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.2"
    )

    XCTAssertEqual(result, .skippedWithoutCredentials)
    XCTAssertEqual(service.token, "existing-token")
    XCTAssertEqual(service.currentUser?.user_name, "existing-user")
    XCTAssertEqual(logoutNotifications.count(), 0)
    XCTAssertEqual(UserDefaults.standard.string(forKey: markerKey), "v0.4.2")
  }

  func testRefreshStoredSessionKeepsActiveUserWithoutAccessibleFeature() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stored-token"
    service.currentUserForTesting = noFeatureToken(accessToken: "stored-token")
    UserDefaults.standard.removeObject(forKey: markerKey)
    clearCredential(account: "username")
    clearCredential(account: "password")
    service.setStoredCredentialsForTesting(username: nil, password: nil)

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.3"
    )

    XCTAssertEqual(result, .skippedWithoutCredentials)
    XCTAssertEqual(service.token, "stored-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
  }

  func testRefreshStoredSessionKeepsStoredUserWithoutAccessibleFeatureWhenVersionAlreadyRefreshed()
    async throws
  {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: sharedService)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    let service = makeStoredSessionService(
      currentUserJSON:
        #"{"access_token":"","token_type":"bearer","super_user":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}"#
    )
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )

    XCTAssertEqual(result, .alreadyRefreshed)
    XCTAssertEqual(service.token, "stored-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
  }

  func testRefreshStoredSessionReloginsStoredLegacyUserWithoutPermissions() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stored-token"
    service.currentUserForTesting = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    persistStoredCurrentUserJSON(legacyUserJSON(accessToken: "stored-token"))
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.5"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertNil(effectiveCredential(account: "username"))
    XCTAssertNil(effectiveCredential(account: "password"))
    let persistence = service.persistenceSnapshotForTesting()
    XCTAssertEqual(persistence.username, "test-user")
    XCTAssertEqual(persistence.password, "test-password")
  }

  func testRefreshStoredSessionReloginsActiveLegacyUserWithoutPermissions() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stored-token"
    service.currentUserForTesting = legacyToken(accessToken: "stored-token")
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.6"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertNil(effectiveCredential(account: "username"))
    XCTAssertNil(effectiveCredential(account: "password"))
    let persistence = service.persistenceSnapshotForTesting()
    XCTAssertEqual(persistence.username, "test-user")
    XCTAssertEqual(persistence.password, "test-password")
  }

  func testRefreshStoredSessionAcceptsReloginWithoutAccessibleFeature()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginNoAccessibleFeatureResponse(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "stale-token"
    service.currentUserForTesting = Token(
      access_token: "stale-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "stale-user",
      avatar: nil
    )
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.4"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "locked")
  }

  func testRefreshStoredSessionRestoresUserContextWhenVersionAlreadyRefreshed() async throws {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: sharedService)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    let service = makeStoredSessionService(
      currentUserJSON:
        #"{"access_token":"stored-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}"#
    )
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )

    XCTAssertEqual(result, .alreadyRefreshed)
    XCTAssertEqual(service.token, "stored-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
    XCTAssertTrue(service.canAccess(.discovery))
    XCTAssertFalse(service.canAccess(.search))
    XCTAssertFalse(service.canAccess(.subscribe))
    XCTAssertFalse(service.canAccess(.manage))
    XCTAssertFalse(service.currentUser?.canRequestSuperUserEndpoints ?? false)
  }

  func testRefreshStoredSessionRestoresUserContextFromTokenlessUnifiedRecord() async throws {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: sharedService)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    let service = makeStoredSessionService(
      currentUserJSON:
        #"{"access_token":"","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}"#
    )
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )

    XCTAssertEqual(result, .alreadyRefreshed)
    XCTAssertEqual(service.currentUser?.access_token, "stored-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
    XCTAssertTrue(service.canAccess(.discovery))
    XCTAssertFalse(service.canAccess(.subscribe))
  }

  func testRefreshStoredSessionRecoversTokenOnlySessionFromCurrentUserEndpoint() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURLForTesting = "https://session-refresh-tests.local"
    service.tokenForTesting = "token-only"
    service.currentUserForTesting = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    clearCredential(account: "currentUser")
    clearCredential(account: "username")
    clearCredential(account: "password")
    service.setStoredCredentialsForTesting(username: nil, password: nil)

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.7"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "token-only")
    XCTAssertEqual(service.currentUser?.access_token, "token-only")
    XCTAssertEqual(service.currentUser?.user_name, "token-only-user")
    XCTAssertTrue(service.canAccess(.discovery))
    XCTAssertTrue(service.canAccess(.search))
    XCTAssertFalse(service.canAccess(.subscribe))
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/user/current" }, ["/api/v1/user/current"])
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
    XCTAssertEqual(UserDefaults.standard.string(forKey: markerKey), "v0.4.7")
  }

  func testPersistedCurrentUserDefaultsFallbackDoesNotDuplicateAccessToken() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.currentUserForTesting = Token(
      access_token: "sensitive-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "fallback-user",
      avatar: nil
    )

    XCTAssertFalse(UserDefaults.standard.string(forKey: "currentUser")?.contains("sensitive-token") ?? false)
  }

  func persistStoredCurrentUserJSON(_ json: String) {
    if !KeychainHelper.shared.save(json, service: "MoviePilot-TV", account: "currentUser") {
      UserDefaults.standard.set(json, forKey: "currentUser")
    }
  }

  func makeStoredSessionService(currentUserJSON: String) -> APIService {
    UserDefaults.standard.set(
      Data(#"{"revision":7,"storage":"userDefaults"}"#.utf8),
      forKey: "sessionMarker.v2"
    )
    UserDefaults.standard.set(
      """
      {"revision":7,"baseURL":"https://session-refresh-tests.local","token":"stored-token","currentUser":\(currentUserJSON),"username":null,"password":null,"imageNamespace":"stored-test"}
      """,
      forKey: "sessionRecord.v2"
    )
    return APIService.testingInstance()
  }

  func sessionToken(userId: Int, accessToken: String, userName: String) -> Token {
    Token(
      access_token: accessToken,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true, "search": true, "subscribe": true, "manage": true],
      user_id: userId,
      user_name: userName,
      avatar: nil
    )
  }

  private func noFeatureToken(accessToken: String) -> Token {
    Token(
      access_token: accessToken,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "limited",
      avatar: nil
    )
  }

  private func noFeatureUserJSON(accessToken: String) -> String {
    """
    {"access_token":"\(accessToken)","token_type":"bearer","super_user":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}
    """
  }

  private func legacyToken(accessToken: String) -> Token {
    Token(
      access_token: accessToken,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: nil,
      user_name: "legacy",
      avatar: nil
    )
  }

  private func legacyUserJSON(accessToken: String) -> String {
    """
    {"access_token":"\(accessToken)","token_type":"bearer","super_user":false,"user_name":"legacy","avatar":null}
    """
  }

  func testAPIServiceLogoutClearsMediaPreloaderCache() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let preloader = MediaPreloader.shared
    preloader.clearAll()
    defer { preloader.clearAll() }

    let media = MediaInfo(title: "登出缓存清理", type: "collection", collection_id: 9_001)
    _ = preloader.preload(for: media)

    XCTAssertNotNil(preloader.peekTask(for: media))

    service.logout()

    try await waitUntil {
      preloader.peekTask(for: media) == nil
    }
  }

  func testReloginReturnsWithoutMutatingStateWhenRefreshIsAlreadyRunning() async {
    let viewModel = SystemViewModel()
    viewModel.isRefreshing = true
    viewModel.refreshMessage = "保持现有状态"

    await viewModel.relogin()

    XCTAssertTrue(viewModel.isRefreshing)
    XCTAssertEqual(viewModel.refreshMessage, "保持现有状态")
  }

  func waitUntil(
    timeout: TimeInterval = 1,
    pollInterval: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: pollInterval)
    }

    XCTAssertTrue(condition())
  }

  func restoreUserDefaultsString(_ value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  func restoreUserDefaultsArray(_ value: [Any]?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  func effectiveCredential(account: String) -> String? {
    KeychainHelper.shared.read(service: "MoviePilot-TV", account: account)
      ?? UserDefaults.standard.string(forKey: account)
  }

  func clearCredential(account: String) {
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    UserDefaults.standard.removeObject(forKey: account)
  }
}
