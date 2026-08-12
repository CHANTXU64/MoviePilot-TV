import XCTest

@testable import MoviePilot_TV

@MainActor
extension SystemSessionBehaviorTests {
  func testFailedServerCandidateLoginKeepsExistingSessionUntouched() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "account-a-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account-a.local",
      token: user.access_token,
      currentUser: user
    )

    do {
      _ = try await service.login(
        username: "account-b",
        password: "wrong",
        serverURL: "https://session-refresh-tests.local"
      )
      XCTFail("Expected candidate login to fail")
    } catch {}

    XCTAssertEqual(service.baseURL, "https://account-a.local")
    XCTAssertEqual(service.token, "account-a-token")
    XCTAssertEqual(service.currentUser?.user_id, 1)
    XCTAssertEqual(service.currentUser?.user_name, "account-a")
  }

  func testDelayedCandidateLoginCannotOverwriteNewerSession() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setHoldLoginResponses(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let accountA = sessionToken(userId: 1, accessToken: "account-a-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account-a.local",
      token: accountA.access_token,
      currentUser: accountA
    )

    let loginTask = Task {
      try await service.login(
        username: "candidate",
        password: "password",
        serverURL: "https://session-refresh-tests.local"
      )
    }
    await SessionRefreshURLProtocol.stub.waitForLoginRequest()

    let accountB = sessionToken(userId: 2, accessToken: "account-b-token", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://account-b.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    await SessionRefreshURLProtocol.stub.releaseLoginResponses()

    do {
      _ = try await loginTask.value
      XCTFail("Expected the stale candidate login to be cancelled")
    } catch is CancellationError {}

    XCTAssertEqual(service.baseURL, "https://account-b.local")
    XCTAssertEqual(service.token, "account-b-token")
    XCTAssertEqual(service.currentUser?.user_id, 2)
  }

  func testDelayedStartupRefreshCannotLogoutNewerSessionWhenCandidateHasNoFeatures()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setHoldLoginResponses(true)
    await SessionRefreshURLProtocol.stub.setLoginNoAccessibleFeatureResponse(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    let markerKey = APIService.sessionRefreshAppVersionKey
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    let accountA = sessionToken(userId: 1, accessToken: "account-a-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "password")
    UserDefaults.standard.removeObject(forKey: markerKey)

    let refreshTask = Task {
      await service.refreshStoredSessionAfterAppUpdateIfNeeded(appVersion: "v-switch-test")
    }
    await SessionRefreshURLProtocol.stub.waitForLoginRequest()

    let accountB = sessionToken(userId: 2, accessToken: "account-b-token", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://account-b.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    await SessionRefreshURLProtocol.stub.releaseLoginResponses()

    let refreshResult = await refreshTask.value
    XCTAssertEqual(refreshResult, .refreshFailed)
    XCTAssertEqual(service.baseURL, "https://account-b.local")
    XCTAssertEqual(service.token, "account-b-token")
    XCTAssertEqual(service.currentUser?.user_id, 2)
    XCTAssertNil(UserDefaults.standard.string(forKey: markerKey))
  }

  func testSessionEpochRejectsABAWhileUIIdentityTracksAccountAndPermissions() {
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let accountA = sessionToken(userId: 1, accessToken: "a-1", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let originalSnapshot = service.sessionSnapshot()
    let originalUIIdentity = service.uiIdentity

    let accountB = sessionToken(userId: 2, accessToken: "b-1", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    XCTAssertNotEqual(service.uiIdentity, originalUIIdentity)

    let refreshedAccountA = sessionToken(userId: 1, accessToken: "a-2", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: refreshedAccountA.access_token,
      currentUser: refreshedAccountA
    )
    XCTAssertEqual(service.uiIdentity, originalUIIdentity)
    XCTAssertFalse(service.isSessionUnchanged(from: originalSnapshot))
  }

  func testUnauthorizedMutationReloginsWithoutReplaying() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/subscribe")
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "account-a-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "password")

    do {
      _ = try await service.saveSubscription(Subscribe(name: "测试", type: "电影"))
      XCTFail("Expected an unauthorized response")
    } catch is CancellationError {
      // Expected: the old request ends after the session is replaced.
    }

    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0.hasPrefix("/api/v1/subscribe") }.count, 1)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
    XCTAssertEqual(service.token, "fresh-token")
  }

  func testUnauthorizedReadReloginsWithoutReplaying() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "password")

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected the old request to end after restoring the session")
    } catch is CancellationError {}

    XCTAssertEqual(service.token, "fresh-token")
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/dashboard/storage" }.count, 1)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testFailedAutomaticReloginLogsOutCurrentSession() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath(
      "/api/v1/system/global/user",
      statusCode: 403
    )
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "forbidden-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "wrong-password")

    do {
      _ = try await service.fetchSettings()
      XCTFail("Expected logout to cancel the stale settings load")
    } catch is CancellationError {
      // Expected: failed automatic login logs out and invalidates the old request.
    }

    XCTAssertNil(service.token)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/system/global/user" }.count, 1)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testUnauthorizedWithoutStoredCredentialsLogsOut() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: nil, password: nil)

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected an unauthorized response")
    } catch APIError.unauthorized {}

    XCTAssertNil(service.token)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/dashboard/storage" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testManualReloginLogsOutWhenCurrentAccountHasNoAccessibleFeature() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginNoAccessibleFeatureResponse(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: "stale-token",
      currentUser: sessionToken(
        userId: 1,
        accessToken: "stale-token",
        userName: "test-user"
      )
    )
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    let viewModel = SystemViewModel(apiService: service)
    await viewModel.relogin()

    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertTrue(viewModel.refreshMessage?.contains("刷新失败") == true)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testManualReloginKeepsCurrentSessionWhenCandidateLoginIsRejected() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let currentUser = sessionToken(
      userId: 1,
      accessToken: "stale-token",
      userName: "test-user"
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: currentUser.access_token,
      currentUser: currentUser
    )
    service.setStoredCredentialsForTesting(username: "test-user", password: "wrong-password")

    let viewModel = SystemViewModel(apiService: service)
    await viewModel.relogin()

    XCTAssertEqual(service.token, "stale-token")
    XCTAssertEqual(service.currentUser?.user_name, "test-user")
    XCTAssertTrue(viewModel.refreshMessage?.contains("刷新失败") == true)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testSilentValidationCannotInvalidateHeldCandidateRelogin() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/user/current")
    await SessionRefreshURLProtocol.stub.setHoldUnauthorizedResponses(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let currentUser = sessionToken(
      userId: 1,
      accessToken: "stale-token",
      userName: "test-user"
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: currentUser.access_token,
      currentUser: currentUser
    )
    service.setStoredCredentialsForTesting(username: "test-user", password: "test-password")

    service.validateTokenSilently()
    await SessionRefreshURLProtocol.stub.waitForRequest(path: "/api/v1/user/current")

    await SessionRefreshURLProtocol.stub.setHoldLoginResponses(true)
    let reloginTask = Task { try await service.reloginStoredSession() }
    await SessionRefreshURLProtocol.stub.waitForLoginRequest()

    await SessionRefreshURLProtocol.stub.releaseUnauthorizedResponses()
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(service.token, "stale-token")
    XCTAssertEqual(service.currentUser?.user_id, 1)

    service.validateTokenSilently()
    try await Task.sleep(nanoseconds: 20_000_000)
    let heldPaths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(heldPaths.filter { $0 == "/api/v1/user/current" }.count, 1)

    await SessionRefreshURLProtocol.stub.releaseLoginResponses()
    let refreshed = try await reloginTask.value
    XCTAssertEqual(refreshed.access_token, "fresh-token")
    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_id, 1)
  }

  func testSystemInfoDoesNotFallBackUnderANewerAccount() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/system/env")
    await SessionRefreshURLProtocol.stub.setHoldUnauthorizedResponses(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let accountA = Token(
      access_token: "account-a-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: nil,
      user_id: 1,
      user_name: "account-a",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )

    let viewModel = SystemViewModel(apiService: service)
    let loadTask = Task { await viewModel.loadSystemInfo() }
    await SessionRefreshURLProtocol.stub.waitForRequest(path: "/api/v1/system/env")

    let accountB = sessionToken(
      userId: 2,
      accessToken: "account-b-token",
      userName: "account-b"
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    await SessionRefreshURLProtocol.stub.releaseUnauthorizedResponses()
    await loadTask.value

    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/system/env" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/system/global"))
    XCTAssertEqual(service.currentUser?.user_id, 2)
  }

}
