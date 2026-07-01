import XCTest

@testable import MoviePilot_TV

@MainActor
final class SystemSessionBehaviorTests: XCTestCase {
  func testRefreshStoredSessionAfterAppUpdateClearsTokenAndReloginsOnce() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stale-token"
    service.currentUser = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")

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
    XCTAssertEqual(effectiveCredential(account: "username"), "test-user")
    XCTAssertEqual(effectiveCredential(account: "password"), "test-password")
    XCTAssertEqual(UserDefaults.standard.string(forKey: markerKey), "v0.4.0")

    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(
      paths.filter { $0 == "/api/v1/login/access-token" },
      ["/api/v1/login/access-token"]
    )
  }

  func testRefreshStoredSessionKeepsExistingSessionAndRetryMarkerWhenReloginFails() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stale-token"
    service.currentUser = Token(
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
    XCTAssertEqual(service.token, "stale-token")
    XCTAssertEqual(service.currentUser?.user_name, "stale-user")
    let logoutNotificationCount = logoutNotifications.count()
    XCTAssertEqual(logoutNotificationCount, 0)
    XCTAssertNil(UserDefaults.standard.string(forKey: markerKey))
    XCTAssertEqual(effectiveCredential(account: "username"), "test-user")
    XCTAssertEqual(effectiveCredential(account: "password"), "test-password")
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

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "existing-token"
    service.currentUser = Token(
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

  func testRefreshStoredSessionClearsActiveUserWithoutAccessibleFeature() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = noFeatureToken(accessToken: "stored-token")
    UserDefaults.standard.removeObject(forKey: markerKey)
    clearCredential(account: "username")
    clearCredential(account: "password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.3"
    )

    XCTAssertEqual(result, .noStoredSession)
    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertNil(effectiveCredential(account: "accessToken"))
    XCTAssertNil(effectiveCredential(account: "currentUser"))
  }

  func testRefreshStoredSessionClearsStoredUserWithoutAccessibleFeatureWhenVersionAlreadyRefreshed()
    async throws
  {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = nil
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)
    persistStoredCurrentUserJSON(noFeatureUserJSON(accessToken: "stored-token"))

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.0"
    )

    XCTAssertEqual(result, .noStoredSession)
    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertNil(effectiveCredential(account: "accessToken"))
    XCTAssertNil(effectiveCredential(account: "currentUser"))
  }

  func testRefreshStoredSessionReloginsStoredLegacyUserWithoutPermissions() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    persistStoredCurrentUserJSON(legacyUserJSON(accessToken: "stored-token"))
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.5"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertEqual(effectiveCredential(account: "username"), "test-user")
    XCTAssertEqual(effectiveCredential(account: "password"), "test-password")
  }

  func testRefreshStoredSessionReloginsActiveLegacyUserWithoutPermissions() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = legacyToken(accessToken: "stored-token")
    UserDefaults.standard.removeObject(forKey: markerKey)
    _ = KeychainHelper.shared.save("test-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("test-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("test-user", forKey: "username")
    UserDefaults.standard.set("test-password", forKey: "password")

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.6"
    )

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertEqual(effectiveCredential(account: "username"), "test-user")
    XCTAssertEqual(effectiveCredential(account: "password"), "test-password")
  }

  func testRefreshStoredSessionClearsExistingSessionWhenReloginReturnsNoAccessibleFeature()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginNoAccessibleFeatureResponse(true)
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stale-token"
    service.currentUser = Token(
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

    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "v0.4.4"
    )

    XCTAssertEqual(result, .noStoredSession)
    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertNil(effectiveCredential(account: "accessToken"))
    XCTAssertNil(effectiveCredential(account: "currentUser"))
  }

  func testRefreshStoredSessionRestoresUserContextWhenVersionAlreadyRefreshed() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = nil
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)
    persistStoredCurrentUserJSON(
      #"{"access_token":"stored-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}"#
    )

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

  func testRefreshStoredSessionRestoresUserContextFromTokenlessDefaultsFallback() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "stored-token"
    service.currentUser = nil
    UserDefaults.standard.set("v0.4.0", forKey: markerKey)
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "currentUser")
    UserDefaults.standard.set(
      #"{"access_token":"","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":false,"subscribe":false,"manage":false},"user_name":"limited","avatar":null}"#,
      forKey: "currentUser"
    )

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
    XCTAssertTrue(URLProtocol.registerClass(SessionRefreshURLProtocol.self))
    defer { URLProtocol.unregisterClass(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = "lastSessionRefreshAppVersion"
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    service.baseURL = "https://session-refresh-tests.local"
    service.token = "token-only"
    service.currentUser = nil
    UserDefaults.standard.removeObject(forKey: markerKey)
    clearCredential(account: "currentUser")
    clearCredential(account: "username")
    clearCredential(account: "password")

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

    service.currentUser = Token(
      access_token: "sensitive-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "fallback-user",
      avatar: nil
    )

    XCTAssertFalse(UserDefaults.standard.string(forKey: "currentUser")?.contains("sensitive-token") ?? false)
  }

  private func persistStoredCurrentUserJSON(_ json: String) {
    if !KeychainHelper.shared.save(json, service: "MoviePilot-TV", account: "currentUser") {
      UserDefaults.standard.set(json, forKey: "currentUser")
    }
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

  func testLoadSystemInfoUsesPublicSettingsForNonManageUserWithoutRequestingSystemEnv()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(SystemInfoURLProtocol.self))
    defer { URLProtocol.unregisterClass(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://system-info-tests.local"
    service.token = "limited-token"
    service.currentUser = nonManageToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )
    clearCredential(account: "username")
    clearCredential(account: "password")

    let logoutNotifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .sessionDidLogout,
      object: nil,
      queue: nil
    ) { _ in
      logoutNotifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SystemViewModel()
    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    XCTAssertEqual(service.token, "limited-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
    XCTAssertEqual(logoutNotifications.count(), 0)
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
  }

  func testLoadSystemInfoFetchesPublicBackendVersionForNonManageUserWhenCacheIsEmpty()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(SystemInfoURLProtocol.self))
    defer { URLProtocol.unregisterClass(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://system-info-tests.local"
    service.token = "limited-token"
    service.currentUser = nonManageToken()
    service.settings = nil
    clearCredential(account: "username")
    clearCredential(account: "password")

    let viewModel = SystemViewModel()
    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
  }

  func testLoadSystemInfoUsesPublicBackendVersionForManageNonSuperuser() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SystemInfoURLProtocol.self))
    defer { URLProtocol.unregisterClass(SystemInfoURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://system-info-tests.local"
    service.token = "manage-token"
    service.currentUser = manageToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )

    let viewModel = SystemViewModel()
    await SystemInfoURLProtocol.stub.reset()

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
    XCTAssertTrue(paths.contains("/api/v1/system/global/user"))
  }

  func testLoadSystemInfoUsesSystemEnvBackendVersionForSuperUser() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SystemInfoURLProtocol.self))
    defer { URLProtocol.unregisterClass(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://system-info-tests.local"
    service.token = "super-token"
    service.currentUser = superUserToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )

    let viewModel = SystemViewModel()
    await SystemInfoURLProtocol.stub.reset()

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v2.13.14")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/system/env"))
  }

  private func nonManageToken() -> Token {
    Token(
      access_token: "limited-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true,
        "search": false,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "limited",
      avatar: nil
    )
  }

  private func manageToken() -> Token {
    Token(
      access_token: "manage-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": true,
      ],
      user_name: "manager",
      avatar: nil
    )
  }

  private func superUserToken() -> Token {
    Token(
      access_token: "super-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [
        "discovery": true,
        "search": true,
        "subscribe": true,
        "manage": true,
      ],
      user_name: "admin",
      avatar: nil
    )
  }

  private func waitUntil(
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

  private func restoreUserDefaultsString(_ value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private func effectiveCredential(account: String) -> String? {
    KeychainHelper.shared.read(service: "MoviePilot-TV", account: account)
      ?? UserDefaults.standard.string(forKey: account)
  }

  private func clearCredential(account: String) {
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    UserDefaults.standard.removeObject(forKey: account)
  }
}

private final class NotificationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func count() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func increment() {
    lock.lock()
    defer { lock.unlock() }
    value += 1
  }
}

private struct SystemSessionServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let usernameKeychain: String?
  let passwordKeychain: String?
  let usernameDefaults: String?
  let passwordDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SystemSessionServiceSnapshot {
    SystemSessionServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserKeychain: KeychainHelper.shared.read(
        service: "MoviePilot-TV",
        account: "currentUser"
      ),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser"),
      settings: service.settings,
      useImageCache: service.useImageCache,
      usernameKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username"),
      passwordKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password"),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    service.settings = settings
    service.useImageCache = useImageCache
    restoreCredential(
      account: "accessToken",
      keychainValue: tokenKeychain,
      defaultsValue: tokenDefaults
    )
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
    restoreCredential(
      account: "username",
      keychainValue: usernameKeychain,
      defaultsValue: usernameDefaults
    )
    restoreCredential(
      account: "password",
      keychainValue: passwordKeychain,
      defaultsValue: passwordDefaults
    )
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(keychainValue, service: "MoviePilot-TV", account: account)
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }

    if let defaultsValue {
      UserDefaults.standard.set(defaultsValue, forKey: account)
    } else {
      UserDefaults.standard.removeObject(forKey: account)
    }
  }
}

private actor SessionRefreshURLProtocolStub {
  private var requests: [URLRequest] = []
  private var loginFailureStatusCode: Int?
  private var loginNoAccessibleFeatureResponse = false

  func reset() {
    requests.removeAll()
    loginFailureStatusCode = nil
    loginNoAccessibleFeatureResponse = false
  }

  func setLoginFailure(statusCode: Int?) {
    loginFailureStatusCode = statusCode
  }

  func setLoginNoAccessibleFeatureResponse(_ enabled: Bool) {
    loginNoAccessibleFeatureResponse = enabled
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let statusCode = loginFailureStatusCode ?? 200
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let data: Data
    if url.path == "/api/v1/user/current" {
      data =
        #"{"id":1,"name":"token-only-user","email":null,"is_active":true,"is_superuser":false,"avatar":null,"is_otp":false,"permissions":{"discovery":true,"search":true,"subscribe":false,"manage":false},"settings":{}}"#
        .data(using: .utf8)!
    } else if let loginFailureStatusCode {
      data = #"{"success":false,"message":"login failed","status":\#(loginFailureStatusCode)}"#
        .data(using: .utf8)!
    } else if loginNoAccessibleFeatureResponse {
      data =
        #"{"access_token":"fresh-token","token_type":"bearer","super_user":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":false},"user_name":"locked","avatar":null}"#
        .data(using: .utf8)!
    } else {
      data =
        #"{"access_token":"fresh-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":true,"subscribe":true,"manage":true},"user_name":"test-user","avatar":null}"#
        .data(using: .utf8)!
    }
    return (response, data)
  }
}

private final class SessionRefreshURLProtocol: URLProtocol {
  static let stub = SessionRefreshURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "session-refresh-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SessionRefreshURLProtocolTaskContext(
      request: request,
      clientBox: SessionRefreshURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SessionRefreshURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SessionRefreshURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let (response, data) = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: response, data: data)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class SessionRefreshURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SessionRefreshURLProtocolClientBox

  init(request: URLRequest, clientBox: SessionRefreshURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SessionRefreshURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(response: HTTPURLResponse, data: Data) {
    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}

private actor SystemInfoURLProtocolStub {
  private var requests: [URLRequest] = []
  private var systemEnvStatusCode = 200

  func reset() {
    requests.removeAll()
    systemEnvStatusCode = 200
  }

  func setSystemEnvStatusCode(_ statusCode: Int) {
    systemEnvStatusCode = statusCode
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let statusCode: Int
    let data: Data
    switch url.path {
    case "/api/v1/system/global":
      statusCode = 200
      data =
        #"{"success":true,"data":{"BACKEND_VERSION":"v9.9.9","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}}"#
        .data(using: .utf8)!
    case "/api/v1/system/global/user":
      statusCode = 200
      data = #"{"success":true,"data":{}}"#.data(using: .utf8)!
    case "/api/v1/system/env":
      statusCode = systemEnvStatusCode
      if systemEnvStatusCode == 200 {
        data = #"{"success":true,"data":{"VERSION":"v2.13.14"}}"#.data(using: .utf8)!
      } else {
        data = #"{"success":false,"message":"forbidden"}"#.data(using: .utf8)!
      }
    default:
      statusCode = 404
      data = #"{"success":false,"message":"not found"}"#.data(using: .utf8)!
    }

    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class SystemInfoURLProtocol: URLProtocol {
  static let stub = SystemInfoURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "system-info-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SystemInfoURLProtocolTaskContext(
      request: request,
      clientBox: SystemInfoURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SystemInfoURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SystemInfoURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let (response, data) = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: response, data: data)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class SystemInfoURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SystemInfoURLProtocolClientBox

  init(request: URLRequest, clientBox: SystemInfoURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SystemInfoURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(response: HTTPURLResponse, data: Data) {
    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
