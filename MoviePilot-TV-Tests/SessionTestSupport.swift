import Foundation

@testable import MoviePilot_TV

struct APIServicePersistenceSnapshot {
  private static let legacyAccounts = ["accessToken", "currentUser", "username", "password"]

  let marker: Data?
  let keychainRecord: String?
  let defaultsRecord: String?
  let loginDraftMarker: Data?
  let loginDraftKeychainRecord: String?
  let loginDraftDefaultsRecord: String?
  let username: String?
  let password: String?
  let legacyKeychainValues: [String: String]
  let legacyDefaultsValues: [String: String]

  @MainActor
  static func capture() -> APIServicePersistenceSnapshot {
    let keychainRecord = KeychainHelper.shared.read(
      service: "MoviePilot-TV",
      account: "sessionRecord.v2"
    )
    let defaultsRecord = UserDefaults.standard.string(forKey: "sessionRecord.v2")
    let credentials = (keychainRecord ?? defaultsRecord)
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder().decode(StoredSessionCredentials.self, from: $0) }
    return APIServicePersistenceSnapshot(
      marker: UserDefaults.standard.data(forKey: "sessionMarker.v2"),
      keychainRecord: keychainRecord,
      defaultsRecord: defaultsRecord,
      loginDraftMarker: UserDefaults.standard.data(forKey: "loginDraftMarker.v1"),
      loginDraftKeychainRecord: KeychainHelper.shared.read(
        service: "MoviePilot-TV",
        account: "loginDraft.v1"
      ),
      loginDraftDefaultsRecord: UserDefaults.standard.string(forKey: "loginDraft.v1"),
      username: credentials?.username,
      password: credentials?.password,
      legacyKeychainValues: Dictionary(
        uniqueKeysWithValues: legacyAccounts.compactMap { account in
          KeychainHelper.shared.read(service: "MoviePilot-TV", account: account)
            .map { (account, $0) }
        }
      ),
      legacyDefaultsValues: Dictionary(
        uniqueKeysWithValues: legacyAccounts.compactMap { account in
          UserDefaults.standard.string(forKey: account).map { (account, $0) }
        }
      )
    )
  }

  @MainActor
  func restore() {
    if let marker {
      UserDefaults.standard.set(marker, forKey: "sessionMarker.v2")
    } else {
      UserDefaults.standard.removeObject(forKey: "sessionMarker.v2")
    }

    if let keychainRecord {
      _ = KeychainHelper.shared.save(
        keychainRecord,
        service: "MoviePilot-TV",
        account: "sessionRecord.v2"
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "sessionRecord.v2")
    }

    if let defaultsRecord {
      UserDefaults.standard.set(defaultsRecord, forKey: "sessionRecord.v2")
    } else {
      UserDefaults.standard.removeObject(forKey: "sessionRecord.v2")
    }

    if let loginDraftMarker {
      UserDefaults.standard.set(loginDraftMarker, forKey: "loginDraftMarker.v1")
    } else {
      UserDefaults.standard.removeObject(forKey: "loginDraftMarker.v1")
    }

    if let loginDraftKeychainRecord {
      _ = KeychainHelper.shared.save(
        loginDraftKeychainRecord,
        service: "MoviePilot-TV",
        account: "loginDraft.v1"
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "loginDraft.v1")
    }

    if let loginDraftDefaultsRecord {
      UserDefaults.standard.set(loginDraftDefaultsRecord, forKey: "loginDraft.v1")
    } else {
      UserDefaults.standard.removeObject(forKey: "loginDraft.v1")
    }

    for account in Self.legacyAccounts {
      if let value = legacyKeychainValues[account] {
        _ = KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: account)
      } else {
        _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
      }
      if let value = legacyDefaultsValues[account] {
        UserDefaults.standard.set(value, forKey: account)
      } else {
        UserDefaults.standard.removeObject(forKey: account)
      }
    }
  }
}

private struct StoredSessionCredentials: Decodable {
  let username: String?
  let password: String?
}

@MainActor
private var apiServiceProtocolClasses: [AnyClass] = []

@MainActor
extension APIService {
  var baseURLForTesting: String {
    get { baseURL }
    set {
      replaceSessionForTesting(baseURL: newValue, token: token, currentUser: currentUser)
    }
  }

  var tokenForTesting: String? {
    get { token }
    set {
      replaceSessionForTesting(baseURL: baseURL, token: newValue, currentUser: currentUser)
    }
  }

  var currentUserForTesting: Token? {
    get { currentUser }
    set {
      replaceSessionForTesting(baseURL: baseURL, token: token, currentUser: newValue)
    }
  }

  static func testingInstance() -> APIService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = apiServiceProtocolClasses
    return APIService(sessionConfiguration: configuration)
  }

  static func isolatedTestingInstance() -> APIService {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    return testingInstance()
  }

  static func installURLProtocolForTesting(_ protocolClass: URLProtocol.Type) -> Bool {
    guard !apiServiceProtocolClasses.contains(where: { $0 == protocolClass }) else {
      return true
    }
    apiServiceProtocolClasses.append(protocolClass)
    return true
  }

  static func removeURLProtocolForTesting(_ protocolClass: URLProtocol.Type) {
    apiServiceProtocolClasses.removeAll { $0 == protocolClass }
  }

  func replaceSessionForTesting(
    baseURL: String,
    token: String?,
    currentUser: Token?
  ) {
    replaceSession(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser,
      username: nil,
      password: nil,
      persist: false
    )
  }

  func setStoredCredentialsForTesting(username: String?, password: String?) {
    replaceSession(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser,
      username: username,
      password: password,
      persist: false
    )
  }

  func persistenceSnapshotForTesting() -> APIServicePersistenceSnapshot {
    APIServicePersistenceSnapshot.capture()
  }

  func restorePersistenceSnapshotForTesting(_ snapshot: APIServicePersistenceSnapshot) {
    snapshot.restore()
  }
}

final class NotificationCounter: @unchecked Sendable {
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

struct SystemSessionServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let loginDraft: LoginDraft?
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
  let persistence: APIServicePersistenceSnapshot

  @MainActor
  static func capture(service: APIService) -> SystemSessionServiceSnapshot {
    SystemSessionServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      loginDraft: service.loginDraft,
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
    service.loginDraft = loginDraft
    service.settings = settings
    service.useImageCache = useImageCache
    service.restorePersistenceSnapshotForTesting(persistence)
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

actor SessionRefreshURLProtocolStub {
  private var requests: [URLRequest] = []
  private var loginFailureStatusCode: Int?
  private var loginFailureJSON = #"{"detail":"用户名或密码错误"}"#
  private var loginFailureHeaders: [String: String] = [:]
  private var loginTransportErrorCode: URLError.Code?
  private var loginNoAccessibleFeatureResponse = false
  private var holdLoginResponses = false
  private var loginWaiters: [CheckedContinuation<Void, Never>] = []
  private var holdUnauthorizedResponses = false
  private var unauthorizedWaiters: [CheckedContinuation<Void, Never>] = []
  private var resourceCookie: String?
  private var unauthorizedPath: String?
  private var unauthorizedStatusCode = 401
  private var currentUserFailureStatusCode: Int?
  private var currentUserFailureJSON = #"{"detail":"token校验不通过"}"#

  func reset() {
    requests.removeAll()
    loginFailureStatusCode = nil
    loginFailureJSON = #"{"detail":"用户名或密码错误"}"#
    loginFailureHeaders = [:]
    loginTransportErrorCode = nil
    loginNoAccessibleFeatureResponse = false
    holdLoginResponses = false
    loginWaiters.forEach { $0.resume() }
    loginWaiters.removeAll()
    holdUnauthorizedResponses = false
    unauthorizedWaiters.forEach { $0.resume() }
    unauthorizedWaiters.removeAll()
    resourceCookie = nil
    unauthorizedPath = nil
    unauthorizedStatusCode = 401
    currentUserFailureStatusCode = nil
    currentUserFailureJSON = #"{"detail":"token校验不通过"}"#
  }

  func setLoginFailure(
    statusCode: Int?,
    json: String = #"{"detail":"用户名或密码错误"}"#,
    headers: [String: String] = [:]
  ) {
    loginFailureStatusCode = statusCode
    loginFailureJSON = json
    loginFailureHeaders = headers
  }

  func setLoginTransportError(_ code: URLError.Code?) {
    loginTransportErrorCode = code
  }

  func setCurrentUserFailure(
    statusCode: Int?,
    json: String = #"{"detail":"token校验不通过"}"#
  ) {
    currentUserFailureStatusCode = statusCode
    currentUserFailureJSON = json
  }

  func setLoginNoAccessibleFeatureResponse(_ enabled: Bool) {
    loginNoAccessibleFeatureResponse = enabled
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

  func setHoldUnauthorizedResponses(_ enabled: Bool) {
    holdUnauthorizedResponses = enabled
  }

  func releaseUnauthorizedResponses() {
    holdUnauthorizedResponses = false
    unauthorizedWaiters.forEach { $0.resume() }
    unauthorizedWaiters.removeAll()
  }

  func waitForRequest(path: String) async {
    while !requests.contains(where: { $0.url?.path == path }) {
      await Task.yield()
    }
  }

  func setResourceCookie(_ cookie: String?) {
    resourceCookie = cookie
  }

  func setUnauthorizedPath(_ path: String?, statusCode: Int = 401) {
    unauthorizedPath = path
    unauthorizedStatusCode = statusCode
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func header(named name: String, forPath path: String) -> String? {
    requests.last(where: { $0.url?.path == path })?.value(forHTTPHeaderField: name)
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let isLogin = url.path == "/api/v1/login/access-token"
    if isLogin, holdLoginResponses {
      await withCheckedContinuation { continuation in
        loginWaiters.append(continuation)
      }
    }
    if !isLogin, unauthorizedPath.map({ url.path.hasPrefix($0) }) == true,
      holdUnauthorizedResponses
    {
      await withCheckedContinuation { continuation in
        unauthorizedWaiters.append(continuation)
      }
    }
    if isLogin, let loginTransportErrorCode {
      throw URLError(loginTransportErrorCode)
    }

    let rejectsCurrentToken = unauthorizedPath.map({ url.path.hasPrefix($0) }) == true
      && request.value(forHTTPHeaderField: "Authorization") != "Bearer fresh-token"
    let statusCode = if url.path == "/api/v1/user/current", let currentUserFailureStatusCode {
      currentUserFailureStatusCode
    } else if rejectsCurrentToken {
      unauthorizedStatusCode
    } else if isLogin {
      loginFailureStatusCode ?? 200
    } else {
      200
    }
    var headers = ["Content-Type": "application/json"]
    if isLogin, statusCode != 200 {
      headers.merge(loginFailureHeaders) { _, new in new }
    }
    if isLogin, statusCode == 200, let resourceCookie {
      headers["Set-Cookie"] = "\(resourceCookie); Path=/api/v1; HttpOnly"
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: headers
    )!
    let data: Data
    if url.path == "/api/v1/user/current", currentUserFailureStatusCode != nil {
      data = currentUserFailureJSON.data(using: .utf8)!
    } else if isLogin, loginFailureStatusCode != nil {
      data = loginFailureJSON.data(using: .utf8)!
    } else if url.path == "/api/v1/user/current" {
      data =
        #"{"id":1,"name":"token-only-user","email":null,"is_active":true,"is_superuser":false,"avatar":null,"is_otp":false,"permissions":{"discovery":true,"search":true,"subscribe":false,"manage":false},"settings":{}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/dashboard/storage" {
      data = #"{"total_storage":100,"used_storage":40}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/system/global" {
      data = #"{"success":true,"data":{"BACKEND_VERSION":"v2.15.5"}}"#.data(using: .utf8)!
    } else if statusCode == 401 || statusCode == 403 {
      data = #"{"success":false,"message":"unauthorized"}"#.data(using: .utf8)!
    } else if loginNoAccessibleFeatureResponse {
      data =
        #"{"access_token":"fresh-token","token_type":"bearer","super_user":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":false},"user_id":2,"user_name":"locked","avatar":null}"#
        .data(using: .utf8)!
    } else {
      data =
        #"{"access_token":"fresh-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true,"search":true,"subscribe":true,"manage":true},"user_id":1,"user_name":"test-user","avatar":null}"#
        .data(using: .utf8)!
    }
    return (response, data)
  }
}

final class SessionRefreshURLProtocol: URLProtocol {
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
