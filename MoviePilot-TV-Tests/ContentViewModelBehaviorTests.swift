import XCTest

@testable import MoviePilot_TV

@MainActor
final class ContentViewModelBehaviorTests: XCTestCase {
  func testAccountPermissionWarningUsesPersistedUserOnInitialization() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
    }

    service.baseURLForTesting = "https://permission-warning.content-view-model-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = token(
      "limited-token",
      userName: "limited-user",
      permissions: ["discovery": false, "search": false, "subscribe": false, "manage": true]
    )

    viewModel = ContentViewModel(apiService: service)

    XCTAssertNotNil(viewModel?.accountPermissionWarning)
  }

  func testPrepareStartupRefreshesPersistedPermissionsOnSameAppVersion() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    let markerKey = APIService.sessionRefreshAppVersionKey
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    clearCredential(account: "username")
    clearCredential(account: "password")
    UserDefaults.standard.set(AppVersionInfo.currentAppVersion(), forKey: markerKey)
    service.baseURLForTesting = "https://startup-permission.content-view-model-tests.local"
    service.tokenForTesting = "persisted-token"
    service.currentUserForTesting = token(
      "persisted-token",
      userName: "stale-user",
      permissions: ["discovery": true, "search": false, "subscribe": false, "manage": false]
    )

    viewModel = ContentViewModel(apiService: service)
    await viewModel?.prepareStartupIfNeeded()

    XCTAssertEqual(service.currentUser?.user_name, "refreshed-user")
    XCTAssertFalse(service.canAccess(.discovery))
    XCTAssertTrue(service.canAccess(.search))
    let paths = await ContentViewModelURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/user/current" }.count, 1)
  }

  func testStartupReloginFinishesBeforeAuthenticatedSettingsLoad() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    await ContentViewModelURLProtocol.stub.rejectSettingsToken("expired-token")
    await ContentViewModelURLProtocol.stub.setHoldLoginResponses(true)
    let service = APIService.testingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    let markerKey = APIService.sessionRefreshAppVersionKey
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    clearCredential(account: "username")
    clearCredential(account: "password")
    _ = KeychainHelper.shared.save(
      "startup-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save(
      "startup-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.removeObject(forKey: markerKey)
    let expiredUser = token("expired-token", userName: "expired-user")
    service.replaceSessionForTesting(
      baseURL: "https://startup-order.content-view-model-tests.local",
      token: expiredUser.access_token,
      currentUser: expiredUser
    )
    service.setStoredCredentialsForTesting(
      username: "startup-user", password: "startup-password")

    viewModel = ContentViewModel(apiService: service)
    NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    for _ in 0..<50 { await Task.yield() }

    var paths = await ContentViewModelURLProtocol.stub.requestPaths()
    let expiredSettingsCount = await ContentViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/system/global",
      authorization: "Bearer expired-token"
    )
    XCTAssertEqual(expiredSettingsCount, 0)
    XCTAssertEqual(service.token, "expired-token")

    let prepareTask = Task { @MainActor in
      await viewModel?.prepareStartupIfNeeded()
    }
    await ContentViewModelURLProtocol.stub.waitForLoginRequest()
    NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    for _ in 0..<50 { await Task.yield() }
    let preparingExpiredSettingsCount = await ContentViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/system/global",
      authorization: "Bearer expired-token"
    )
    XCTAssertEqual(preparingExpiredSettingsCount, 0)
    await ContentViewModelURLProtocol.stub.releaseLoginResponses()
    await prepareTask.value

    XCTAssertEqual(service.token, "fresh-startup-token")
    XCTAssertEqual(service.currentUser?.user_name, "startup-user")
    paths = await ContentViewModelURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/login/access-token" }.count, 1)
    let freshSettingsCount = await ContentViewModelURLProtocol.stub.requestCount(
      path: "/api/v1/system/global",
      authorization: "Bearer fresh-startup-token"
    )
    XCTAssertEqual(freshSettingsCount, 1)
  }

  func testPrepareStartupLogsOutUnauthorizedTokenOnlySession() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    await ContentViewModelURLProtocol.stub.setCurrentUserStatusCode(401)
    let service = APIService.isolatedTestingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    let markerKey = APIService.sessionRefreshAppVersionKey
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    clearCredential(account: "username")
    clearCredential(account: "password")
    UserDefaults.standard.set(AppVersionInfo.currentAppVersion(), forKey: markerKey)
    service.baseURLForTesting = "https://startup-token-only.content-view-model-tests.local"
    service.tokenForTesting = "expired-token"
    service.currentUserForTesting = nil

    viewModel = ContentViewModel(apiService: service)
    await viewModel?.prepareStartupIfNeeded()

    XCTAssertNil(service.token)
    XCTAssertNil(service.currentUser)
    XCTAssertFalse(viewModel?.isLoggedIn == true)
  }

  func testAccountPermissionWarningClearsWhenCurrentUserRegainsRecommendedPermissions() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
    }

    service.baseURLForTesting = "https://permission-warning.content-view-model-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = nil

    viewModel = ContentViewModel(apiService: service)
    service.currentUserForTesting = token(
      "limited-token",
      userName: "limited-user",
      permissions: ["discovery": false, "search": false, "subscribe": false, "manage": true]
    )

    try await waitUntil("expected limited user to show account permission warning") {
      viewModel?.accountPermissionWarning != nil
    }

    service.currentUserForTesting = token(
      "full-token",
      userName: "full-user",
      permissions: ["discovery": true, "search": true, "subscribe": true, "manage": false]
    )

    try await waitUntil("expected full permission user to clear account permission warning") {
      viewModel?.accountPermissionWarning == nil
    }
  }

  func testAccountPermissionWarningReappearsForDifferentStableUserID() async throws {
    let service = APIService.testingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
    }
    let permissions = [
      "discovery": false,
      "search": false,
      "subscribe": false,
      "manage": true,
    ]
    let accountA = token(
      "limited-a",
      userID: 1,
      userName: "same-name",
      permissions: permissions
    )
    service.replaceSessionForTesting(
      baseURL: "https://permission-profile.content-view-model-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    viewModel = ContentViewModel(apiService: service)
    let accountAWarningID = try XCTUnwrap(viewModel?.accountPermissionWarning?.id)

    viewModel?.accountPermissionWarning = nil
    let accountB = token(
      "limited-b",
      userID: 2,
      userName: "same-name",
      permissions: permissions
    )
    service.replaceSessionForTesting(
      baseURL: "https://permission-profile.content-view-model-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )

    let accountBWarning = try XCTUnwrap(viewModel?.accountPermissionWarning)
    XCTAssertNotEqual(accountBWarning.id, accountAWarningID)
  }

  func testBackendVersionWarningRechecksAfterServerAndTokenChange() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ContentViewModelURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = ContentViewModelServiceSnapshot.capture(service: service)
    let markerKey = APIService.sessionRefreshAppVersionKey
    let originalMarker = UserDefaults.standard.string(forKey: markerKey)
    var viewModel: ContentViewModel?
    defer {
      viewModel = nil
      snapshot.restore(to: service)
      restoreUserDefaultsString(originalMarker, forKey: markerKey)
    }

    clearCredential(account: "username")
    clearCredential(account: "password")
    UserDefaults.standard.set(AppVersionInfo.currentAppVersion(), forKey: markerKey)
    service.baseURLForTesting = "https://compatible.content-view-model-tests.local"
    service.tokenForTesting = "token-a"
    service.currentUserForTesting = token("token-a", userName: "first-user")
    service.settings = nil

    viewModel = ContentViewModel(apiService: service)

    await viewModel?.prepareStartupIfNeeded()

    XCTAssertEqual(service.settings?.BACKEND_VERSION, "v2.15.6")
    XCTAssertNil(viewModel?.backendVersionWarning)

    service.baseURLForTesting = "https://old.content-view-model-tests.local"
    service.tokenForTesting = "token-b"
    service.currentUserForTesting = token("token-b", userName: "second-user")

    try await waitUntil("expected backend warning to reload from old backend") {
      service.settings?.BACKEND_VERSION == "v2.14.9"
        && viewModel?.backendVersionWarning?.backendVersion == "v2.14.9"
    }

    XCTAssertEqual(viewModel?.backendVersionWarning?.backendVersion, "v2.14.9")
    XCTAssertEqual(
      viewModel?.backendVersionWarning?.requiredVersion,
      AppVersionInfo.compatibleMoviePilotVersion
    )
  }

  func testMalformedBackendVersionBuildsUnconfirmedWarning() {
    let warning = ContentViewModel.backendVersionWarning(for: "v2.beta.14")

    XCTAssertEqual(warning?.title, "无法确认 MoviePilot 后端版本")
    XCTAssertTrue(warning?.message.contains("无法解析该版本号") == true)
    XCTAssertFalse(warning?.message.contains("低版本后端") == true)
  }

  private func token(
    _ value: String,
    userID: Int? = nil,
    userName: String,
    permissions: [String: Bool] = ["discovery": true]
  ) -> Token {
    Token(
      access_token: value,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: permissions,
      user_id: userID,
      user_name: userName,
      avatar: nil
    )
  }

  private func clearCredential(account: String) {
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    UserDefaults.standard.removeObject(forKey: account)
  }

  private func restoreUserDefaultsString(_ value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private func waitUntil(
    _ failureMessage: String,
    timeout: TimeInterval = 2,
    condition: @MainActor @escaping () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail(failureMessage)
  }
}

@MainActor
private struct ContentViewModelServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?
  let usernameKeychain: String?
  let usernameDefaults: String?
  let passwordKeychain: String?
  let passwordDefaults: String?
  let persistence: APIServicePersistenceSnapshot

  @MainActor
  static func capture(service: APIService) -> ContentViewModelServiceSnapshot {
    ContentViewModelServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser"),
      usernameKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username"),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password"),
      persistence: service.persistenceSnapshotForTesting()
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.replaceSessionForTesting(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser
    )
    service.settings = settings
    service.restorePersistenceSnapshotForTesting(persistence)
    restoreDefaults(value: serverURLDefaults, forKey: "serverURL")
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
  private func restoreDefaults(value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(keychainValue, service: "MoviePilot-TV", account: account)
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }
    restoreDefaults(value: defaultsValue, forKey: account)
  }
}

private actor ContentViewModelURLProtocolStub {
  private var requests: [URLRequest] = []
  private var currentUserStatusCode = 200
  private var rejectedSettingsToken: String?
  private var holdLoginResponses = false
  private var loginWaiters: [CheckedContinuation<Void, Never>] = []

  func reset() {
    requests.removeAll()
    currentUserStatusCode = 200
    rejectedSettingsToken = nil
    holdLoginResponses = false
    loginWaiters.forEach { $0.resume() }
    loginWaiters.removeAll()
  }

  func setCurrentUserStatusCode(_ statusCode: Int) {
    currentUserStatusCode = statusCode
  }

  func rejectSettingsToken(_ token: String?) {
    rejectedSettingsToken = token
  }

  func setHoldLoginResponses(_ enabled: Bool) {
    holdLoginResponses = enabled
  }

  func waitForLoginRequest() async {
    while !requests.contains(where: { $0.url?.path == "/api/v1/login/access-token" }) {
      await Task.yield()
    }
  }

  func releaseLoginResponses() {
    holdLoginResponses = false
    loginWaiters.forEach { $0.resume() }
    loginWaiters.removeAll()
  }

  func requestPaths() -> [String] {
    requests.compactMap { $0.url?.path }
  }

  func requestCount(path: String, authorization: String?) -> Int {
    requests.filter {
      $0.url?.path == path
        && $0.value(forHTTPHeaderField: "Authorization") == authorization
    }.count
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }
    if url.path == "/api/v1/login/access-token", holdLoginResponses {
      await withCheckedContinuation { continuation in
        loginWaiters.append(continuation)
      }
    }

    let backendVersion: String
    switch url.host {
    case "old.content-view-model-tests.local":
      backendVersion = "v2.14.9"
    default:
      backendVersion = "v2.15.6"
    }

    let rejectsSettings = url.path == "/api/v1/system/global"
      && request.value(forHTTPHeaderField: "Authorization") == rejectedSettingsToken.map {
        "Bearer \($0)"
      }
    let statusCode = if url.path == "/api/v1/user/current" {
      currentUserStatusCode
    } else if rejectsSettings {
      403
    } else {
      200
    }

    let data: Data
    if statusCode == 403 {
      data = #"{"success":false,"message":"forbidden"}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/login/access-token" {
      data =
        #"{"access_token":"fresh-startup-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":true,"subscribe":true,"manage":false},"user_id":1,"user_name":"startup-user","avatar":null}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/user/current" {
      data =
        #"{"id":1,"name":"refreshed-user","email":null,"is_active":true,"is_superuser":false,"avatar":null,"is_otp":false,"permissions":{"discovery":false,"search":true,"subscribe":false,"manage":false},"settings":{}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/system/global" {
      data =
        #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"\#(backendVersion)","FRONTEND_VERSION":"v2.15.6"}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/system/global/user" {
      data =
        #"{"success":true,"data":{"USER_UNIQUE_ID":"content-user","SUBSCRIBE_SHARE_MANAGE":true}}"#
        .data(using: .utf8)!
    } else {
      data = #"{"success":true,"data":{"value":[]}}"#.data(using: .utf8)!
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

private final class ContentViewModelURLProtocol: URLProtocol {
  static let stub = ContentViewModelURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host?.hasSuffix(".content-view-model-tests.local") == true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = ContentViewModelURLProtocolTaskContext(
      request: request,
      clientBox: ContentViewModelURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = ContentViewModelURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: ContentViewModelURLProtocolTaskContext)
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

private final class ContentViewModelURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: ContentViewModelURLProtocolClientBox

  init(request: URLRequest, clientBox: ContentViewModelURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class ContentViewModelURLProtocolClientBox: @unchecked Sendable {
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
