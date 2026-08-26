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
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
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
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
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

  func testBusinessForbiddenKeepsSessionWhenCurrentUserProbeSucceeds() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath(
      "/api/v1/dashboard/storage",
      statusCode: 403
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = Token(
      access_token: "valid-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true, "search": true, "subscribe": false, "manage": false],
      user_id: 1,
      user_name: "token-only-user",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "password")

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected the original forbidden response")
    } catch APIError.authenticationChallenge(let statusCode, _) {
      XCTAssertEqual(statusCode, 403)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(service.token, "valid-token")
    XCTAssertNil(service.loginDraft)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/user/current" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testAutomaticReloginNetworkFailureKeepsSessionAndCredentials() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
    await SessionRefreshURLProtocol.stub.setLoginTransportError(.notConnectedToInternet)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "saved-password")

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected the network failure")
    } catch APIError.networkError(let error) {
      XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(service.token, "expired-token")
    XCTAssertEqual(service.currentUser?.user_name, "account-a")
    XCTAssertNil(service.loginDraft)
  }

  func testAutomaticReloginRecognizesCredentialRejectionAcrossBackendLanguagesAndFields()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    let fixtures: [(label: String, json: String)] = [
      ("简体中文", #"{"detail":"用户名或密码错误"}"#),
      ("English", #"{"message":"Incorrect username or password"}"#),
      ("繁體中文", #"{"detail_i18n":"使用者名稱或密碼錯誤"}"#),
      (
        "未知翻译字段不遮蔽原始字段",
        #"{"message_i18n":"Unrecognized localized response","message":"用户名或密码错误"}"#
      ),
    ]

    for fixture in fixtures {
      await SessionRefreshURLProtocol.stub.reset()
      await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
      await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
      await SessionRefreshURLProtocol.stub.setLoginFailure(
        statusCode: 401,
        json: fixture.json
      )

      let service = APIService.isolatedTestingInstance()
      let snapshot = SystemSessionServiceSnapshot.capture(service: service)
      do {
        defer { snapshot.restore(to: service) }
        let user = sessionToken(
          userId: 1,
          accessToken: "expired-token",
          userName: "account-a"
        )
        service.replaceSessionForTesting(
          baseURL: "https://session-refresh-tests.local",
          token: user.access_token,
          currentUser: user
        )
        service.setStoredCredentialsForTesting(
          username: "account-a",
          password: "saved-password"
        )

        do {
          _ = try await service.fetchStorage()
          XCTFail("Expected reauthentication for fixture: \(fixture.label)")
        } catch is CancellationError {}

        XCTAssertNil(service.token, fixture.label)
        XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected, fixture.label)
        XCTAssertEqual(service.loginDraft?.username, "account-a", fixture.label)
        XCTAssertEqual(service.loginDraft?.password, "saved-password", fixture.label)
      }
    }
  }

  func testRepeatedAmbiguousCurrentUserChallengesNotifyOnceAndResetAfterRecovery()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(
      statusCode: 403,
      json: #"{"detail":"无法识别的认证响应"}"#
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = Token(
      access_token: "active-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true, "search": true, "subscribe": false, "manage": false],
      user_id: 1,
      user_name: "token-only-user",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )

    let notifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .authenticationNeedsAttention,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let notificationManager = NotificationManager()

    for attempt in 1...5 {
      await service.refreshCurrentUserForStartup()
      XCTAssertEqual(notifications.count(), attempt < 3 ? 0 : 1)
    }

    try await waitUntil { notificationManager.isShowing }
    XCTAssertEqual(
      notificationManager.message,
      "登录状态反复验证失败，请前往设置的连接信息，选择“刷新登录凭据”。"
    )
    XCTAssertEqual(service.token, "active-token")
    XCTAssertNil(service.loginDraft)

    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: nil)
    await service.refreshCurrentUserForStartup()
    XCTAssertEqual(service.currentUser?.user_name, "token-only-user")

    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(
      statusCode: 403,
      json: #"{"detail":"无法识别的认证响应"}"#
    )
    await service.refreshCurrentUserForStartup()
    await service.refreshCurrentUserForStartup()
    XCTAssertEqual(notifications.count(), 1)
    await service.refreshCurrentUserForStartup()
    XCTAssertEqual(notifications.count(), 2)
  }

  func testRepeatedUnrecognizedLogin401WarnsWithoutClearingExistingSession() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(
      statusCode: 401,
      json: #"{"detail":"Unknown authentication response"}"#
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "active-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account-a.local",
      token: user.access_token,
      currentUser: user
    )

    let notifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .authenticationNeedsAttention,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    for attempt in 1...5 {
      do {
        _ = try await service.login(
          username: "candidate",
          password: "password",
          serverURL: "https://session-refresh-tests.local"
        )
        XCTFail("Expected an unrecognized login challenge")
      } catch APIError.serverMessage {}
      XCTAssertEqual(notifications.count(), attempt < 3 ? 0 : 1)
    }

    XCTAssertEqual(service.baseURL, "https://account-a.local")
    XCTAssertEqual(service.token, "active-token")
    XCTAssertEqual(service.currentUser?.user_name, "account-a")
    XCTAssertNil(service.loginDraft)
  }

  func testRepeatedAutomaticReloginUnknown401WarnsWithoutClearingExistingSession()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
    await SessionRefreshURLProtocol.stub.setLoginFailure(
      statusCode: 401,
      json: #"{"detail":"Unknown authentication response"}"#
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "saved-password")

    let notifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .authenticationNeedsAttention,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    for attempt in 1...5 {
      do {
        _ = try await service.fetchStorage()
        XCTFail("Expected an unrecognized automatic relogin challenge")
      } catch APIError.serverMessage {}
      XCTAssertEqual(notifications.count(), attempt < 3 ? 0 : 1)
    }

    XCTAssertEqual(service.token, "expired-token")
    XCTAssertEqual(service.currentUser?.user_name, "account-a")
    XCTAssertNil(service.loginDraft)
  }

  func testStaleCredentialRejectionCannotResetNewSessionAuthenticationWarningState()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(
      statusCode: 403,
      json: #"{"detail":"无法识别的认证响应"}"#
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let accountA = sessionToken(userId: 1, accessToken: "account-a-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )

    await service.refreshCurrentUserForStartup()
    await service.refreshCurrentUserForStartup()

    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    await SessionRefreshURLProtocol.stub.setHoldLoginResponses(true)
    let staleLogin = Task {
      try await service.login(
        username: "candidate",
        password: "wrong-password",
        serverURL: "https://session-refresh-tests.local"
      )
    }
    await SessionRefreshURLProtocol.stub.waitForLoginRequest()

    let accountB = sessionToken(userId: 2, accessToken: "account-b-token", userName: "account-b")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )

    let notifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .authenticationNeedsAttention,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    await service.refreshCurrentUserForStartup()
    await service.refreshCurrentUserForStartup()

    await SessionRefreshURLProtocol.stub.releaseLoginResponses()
    do {
      _ = try await staleLogin.value
      XCTFail("Expected stale candidate credentials to be rejected")
    } catch APIError.credentialsRejected {}

    await service.refreshCurrentUserForStartup()
    XCTAssertEqual(notifications.count(), 1)
    XCTAssertEqual(service.token, "account-b-token")
    XCTAssertEqual(service.currentUser?.user_name, "account-b")
    XCTAssertNil(service.loginDraft)
  }

  func testAutomaticReloginCredentialRejectionPreservesLoginDraft() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "old-password")

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected reauthentication to end the old request")
    } catch is CancellationError {}

    XCTAssertNil(service.token)
    XCTAssertEqual(service.baseURL, "https://session-refresh-tests.local")
    XCTAssertEqual(service.loginDraft?.username, "account-a")
    XCTAssertEqual(service.loginDraft?.password, "old-password")
    XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected)
    let loginViewModel = LoginViewModel(apiService: service)
    XCTAssertEqual(loginViewModel.serverURL, "https://session-refresh-tests.local")
    XCTAssertEqual(loginViewModel.username, "account-a")
    XCTAssertEqual(loginViewModel.password, "old-password")
    XCTAssertFalse(loginViewModel.showsMFAUnsupportedNotice)
  }

  func testAutomaticReloginMFARequirementExitsWithUnsupportedNotice() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
    await SessionRefreshURLProtocol.stub.setLoginFailure(
      statusCode: 401,
      json: #"{"detail":"需要二次验证","mfa_methods":["otp"]}"#,
      headers: ["X-MFA-Required": "true"]
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let user = sessionToken(userId: 1, accessToken: "expired-token", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: user.access_token,
      currentUser: user
    )
    service.setStoredCredentialsForTesting(username: "account-a", password: "saved-password")

    do {
      _ = try await service.fetchStorage()
      XCTFail("Expected MFA reauthentication")
    } catch is CancellationError {}

    XCTAssertNil(service.token)
    XCTAssertEqual(service.loginDraft?.username, "account-a")
    XCTAssertEqual(service.loginDraft?.password, "saved-password")
    XCTAssertEqual(service.loginDraft?.reason, .mfaUnsupported)
    let loginViewModel = LoginViewModel(apiService: service)
    XCTAssertTrue(loginViewModel.showsMFAUnsupportedNotice)

    let didLogin = await loginViewModel.login()
    XCTAssertFalse(didLogin)
    XCTAssertTrue(loginViewModel.showsMFAUnsupportedNotice)
    XCTAssertEqual(
      loginViewModel.errorMessage,
      "当前账号已开启 MFA，TV 端暂不支持，请关闭 MFA 后重试"
    )

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(statusCode: 401)
    let rejectedRetry = await loginViewModel.login()

    XCTAssertFalse(rejectedRetry)
    XCTAssertFalse(loginViewModel.showsMFAUnsupportedNotice)
    XCTAssertEqual(loginViewModel.errorMessage, "用户名或密码错误")
    XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected)
  }

  func testSuccessfulPasswordLoginAcceptsAuthenticatedUserWithoutFeaturePermissions()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginNoAccessibleFeatureResponse(true)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let token = try await service.login(
      username: "limited",
      password: "password",
      serverURL: "https://session-refresh-tests.local"
    )

    XCTAssertEqual(token.user_name, "locked")
    XCTAssertEqual(service.currentUser?.user_name, "locked")
    XCTAssertNotNil(service.token)
    XCTAssertFalse(service.currentUser?.hasLoginAccessibleFeature == true)
  }

  func testFailedAutomaticReloginRequiresPrefilledReauthentication() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath(
      "/api/v1/system/global/user",
      statusCode: 403
    )
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
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
    XCTAssertEqual(service.loginDraft?.serverURL, "https://session-refresh-tests.local")
    XCTAssertEqual(service.loginDraft?.username, "account-a")
    XCTAssertEqual(service.loginDraft?.password, "wrong-password")
    XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/system/global/user" }.count, 1)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testUnauthorizedWithoutStoredCredentialsRequiresReauthentication() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setUnauthorizedPath("/api/v1/dashboard/storage")
    await SessionRefreshURLProtocol.stub.setCurrentUserFailure(statusCode: 403)
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
    } catch is CancellationError {}

    XCTAssertNil(service.token)
    XCTAssertEqual(service.loginDraft?.serverURL, "https://session-refresh-tests.local")
    XCTAssertEqual(service.loginDraft?.username, "account-a")
    XCTAssertNil(service.loginDraft?.password)
    XCTAssertEqual(service.loginDraft?.reason, .missingCredentials)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/dashboard/storage" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testManualReloginKeepsAuthenticatedAccountWithoutAccessibleFeature() async throws {
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

    XCTAssertEqual(service.token, "fresh-token")
    XCTAssertEqual(service.currentUser?.user_name, "locked")
    XCTAssertEqual(viewModel.refreshMessage, "刷新成功")
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testManualReloginRequiresReauthenticationWhenCredentialsAreRejected() async throws {
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

    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertEqual(service.loginDraft?.serverURL, "https://session-refresh-tests.local")
    XCTAssertEqual(service.loginDraft?.username, "test-user")
    XCTAssertEqual(service.loginDraft?.password, "wrong-password")
    XCTAssertEqual(service.loginDraft?.reason, .credentialsRejected)
    XCTAssertTrue(viewModel.refreshMessage?.contains("刷新失败") == true)
    let paths = await SessionRefreshURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
  }

  func testManualReloginRequiresReauthenticationWhenMFAIsRequired() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    await SessionRefreshURLProtocol.stub.setLoginFailure(
      statusCode: 401,
      json: #"{"detail":"需要二次验证","mfa_methods":["otp"]}"#,
      headers: ["X-MFA-Required": "true"]
    )
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
    service.setStoredCredentialsForTesting(username: "test-user", password: "saved-password")

    let viewModel = SystemViewModel(apiService: service)
    await viewModel.relogin()

    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertEqual(service.loginDraft?.username, "test-user")
    XCTAssertEqual(service.loginDraft?.password, "saved-password")
    XCTAssertEqual(service.loginDraft?.reason, .mfaUnsupported)
    XCTAssertTrue(viewModel.refreshMessage?.contains("TV 端暂不支持") == true)
  }

  func testSystemStorageDescriptionTracksSessionLogoutWithoutManualRefresh() {
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let currentUser = sessionToken(
      userId: 1,
      accessToken: "stored-token",
      userName: "test-user"
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local",
      token: currentUser.access_token,
      currentUser: currentUser
    )

    let viewModel = SystemViewModel(apiService: service)
    XCTAssertNotEqual(viewModel.storageDescription, "未登录")

    service.logout()

    XCTAssertEqual(viewModel.storageDescription, "未登录")
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
