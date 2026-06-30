import XCTest

@testable import MoviePilot_TV

@MainActor
final class TokenPermissionCompatibilityTests: XCTestCase {
  func testKnownStandardUserCannotRequestSuperUserEndpoints() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["manage": true],
      user_name: "ordinary",
      avatar: nil
    )

    XCTAssertFalse(token.canRequestSuperUserEndpoints)
  }

  func testStandardUserOnlyAccessesExplicitlyGrantedPermissions() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true,
        "search": true,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "limited",
      avatar: nil
    )

    XCTAssertTrue(token.canAccess(.discovery))
    XCTAssertTrue(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
  }

  func testStandardUserWithEmptyPermissionsHasNoFeatureAccess() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [:],
      user_name: "test",
      avatar: nil
    )

    XCTAssertFalse(token.canAccess(.discovery))
    XCTAssertFalse(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
    XCTAssertFalse(token.hasLoginAccessibleFeature)
  }

  func testStandardUserWithPartialPermissionsDoesNotFallbackForMissingKeys() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": false],
      user_name: "partial",
      avatar: nil
    )

    XCTAssertFalse(token.canAccess(.discovery))
    XCTAssertFalse(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
    XCTAssertFalse(token.hasLoginAccessibleFeature)
  }

  func testUnknownPermissionWithoutVisibleTVFeatureDoesNotAllowLogin() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "admin": true,
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "admin-only",
      avatar: nil
    )

    XCTAssertFalse(token.hasLoginAccessibleFeature)
  }

  func testManageOnlyPermissionAllowsLogin() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": true,
      ],
      user_name: "manage-only",
      avatar: nil
    )

    XCTAssertTrue(token.canAccess(.manage))
    XCTAssertTrue(token.hasLoginAccessibleFeature)
  }

  func testSuperUserCanRequestSuperUserEndpoints() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [:],
      user_name: "admin",
      avatar: nil
    )

    XCTAssertTrue(token.canRequestSuperUserEndpoints)
    XCTAssertTrue(token.canAccess(.discovery))
    XCTAssertTrue(token.canAccess(.search))
    XCTAssertTrue(token.canAccess(.subscribe))
    XCTAssertTrue(token.canAccess(.manage))
    XCTAssertTrue(token.hasLoginAccessibleFeature)
  }

  func testMissingPermissionPayloadHasNoFeatureAccess() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: nil,
      permissions: nil,
      user_name: "legacy",
      avatar: nil
    )

    XCTAssertFalse(token.canRequestSuperUserEndpoints)
    XCTAssertFalse(token.canAccess(.discovery))
    XCTAssertFalse(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
    XCTAssertFalse(token.hasLoginAccessibleFeature)
  }

  func testMissingCurrentUserShowsOnlyUngatedTabs() {
    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: nil),
      [.home, .system]
    )
  }

  func testLoggedOutServiceDoesNotDefaultAllowProtectedFeatures() {
    let service = APIService.shared
    let snapshot = LoginPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.token = nil
    service.currentUser = nil

    XCTAssertFalse(service.canAccess(.subscribe))
    XCTAssertFalse(service.canAccess(.manage))
  }

  func testStoredUserWithoutAccessibleFeatureDoesNotDefaultAllowBeforeSessionRefresh() {
    let service = APIService.shared
    let snapshot = LoginPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.currentUser = nil
    service.token = "stored-token"
    persistLoginPermissionStoredCurrentUser(
      """
      {"access_token":"stored-token","token_type":"bearer","super_user":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":false},"user_name":"locked","avatar":null}
      """
    )

    XCTAssertFalse(service.canAccess(.discovery))
    XCTAssertFalse(service.canAccess(.search))
    XCTAssertFalse(service.canAccess(.subscribe))
    XCTAssertFalse(service.canAccess(.manage))
  }

  func testContentTabsFollowGrantedPermissions() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": false, "search": true],
      user_name: "searcher",
      avatar: nil
    )

    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: token),
      [.home, .search, .system]
    )
  }

  func testManagePermissionShowsStatusTab() {
    let token = Token(
      access_token: "token",
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

    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: token),
      [.home, .status, .system]
    )
  }

  func testLoginRejectsStandardUserWithoutAnyFunctionalPermission() async throws {
    XCTAssertTrue(URLProtocol.registerClass(LoginPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(LoginPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = LoginPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    LoginPermissionURLProtocol.stub.reset()
    service.baseURL = "https://login-permission-tests.local"
    service.token = nil
    service.currentUser = nil

    do {
      _ = try await service.login(username: "locked", password: "password")
      XCTFail("Expected login to reject a user without any functional permission")
    } catch {
      XCTAssertNil(service.token)
      XCTAssertNil(service.currentUser)
    }
  }

  func testLoginRejectsStandardUserWithEmptyPermissionsPayload() async throws {
    XCTAssertTrue(URLProtocol.registerClass(LoginPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(LoginPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = LoginPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    LoginPermissionURLProtocol.stub.reset()
    LoginPermissionURLProtocol.stub.permissionsPayload = "{}"
    service.baseURL = "https://login-permission-tests.local"
    service.token = nil
    service.currentUser = nil

    do {
      _ = try await service.login(username: "default-user", password: "password")
      XCTFail("Expected empty permissions to be rejected like the Web login menu filter.")
    } catch {
      XCTAssertNil(service.token)
      XCTAssertNil(service.currentUser)
    }
  }

  func testLoginAcceptsManageOnlyUser() async throws {
    XCTAssertTrue(URLProtocol.registerClass(LoginPermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(LoginPermissionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = LoginPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    LoginPermissionURLProtocol.stub.reset()
    LoginPermissionURLProtocol.stub.permissionsPayload = """
      {
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": true
      }
      """
    service.baseURL = "https://login-permission-tests.local"
    service.token = nil
    service.currentUser = nil

    let token = try await service.login(username: "manage-user", password: "password")

    XCTAssertEqual(token.access_token, "limited-token")
    XCTAssertFalse(token.canAccess(.discovery))
    XCTAssertFalse(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertTrue(token.canAccess(.manage))
    XCTAssertNotNil(service.token)
    XCTAssertNotNil(service.currentUser)
  }

  func testSuperUserSeesAllContentTabs() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [:],
      user_name: "admin",
      avatar: nil
    )

    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: token),
      [.home, .recommend, .explore, .search, .status, .system]
    )
  }

  func testSelectedTabFallsBackWhenCurrentTabBecomesHidden() {
    XCTAssertEqual(
      ContentViewModel.resolvedSelectedTab(
        .status,
        visibleTabs: [.home, .search, .system]
      ),
      .home
    )

    XCTAssertEqual(
      ContentViewModel.resolvedSelectedTab(
        .system,
        visibleTabs: [.home, .search, .system]
      ),
      .system
    )
  }
}

@MainActor
private func persistLoginPermissionStoredCurrentUser(_ json: String) {
  _ = KeychainHelper.shared.save(
    json,
    service: "MoviePilot-TV",
    account: "currentUser"
  )
  UserDefaults.standard.set(json, forKey: "currentUser")
}

private struct LoginPermissionServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> LoginPermissionServiceSnapshot {
    LoginPermissionServiceSnapshot(
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

private final class LoginPermissionURLProtocolStub: @unchecked Sendable {
  var permissionsPayload = """
    {
      "discovery": false,
      "search": false,
      "subscribe": false,
      "manage": false
    }
    """

  func reset() {
    permissionsPayload = """
      {
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": false
      }
      """
  }

  func response(for request: URLRequest) -> (Int, Data) {
    guard request.url?.path == "/api/v1/login/access-token" else {
      return (404, Data())
    }

    let body = """
      {
        "access_token": "limited-token",
        "token_type": "bearer",
        "super_user": false,
        "permissions": \(permissionsPayload),
        "user_name": "locked",
        "avatar": null
      }
      """
    return (200, Data(body.utf8))
  }
}

private final class LoginPermissionURLProtocol: URLProtocol {
  static let stub = LoginPermissionURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "login-permission-tests.local"
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
