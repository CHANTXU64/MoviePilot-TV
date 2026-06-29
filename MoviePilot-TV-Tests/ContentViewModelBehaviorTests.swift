import XCTest

@testable import MoviePilot_TV

@MainActor
final class ContentViewModelBehaviorTests: XCTestCase {
  func testBackendVersionWarningRechecksAfterServerAndTokenChange() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ContentViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ContentViewModelURLProtocol.self) }

    await ContentViewModelURLProtocol.stub.reset()
    let service = APIService.shared
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
    service.baseURL = "https://compatible.content-view-model-tests.local"
    service.token = "token-a"
    service.currentUser = token("token-a", userName: "first-user")
    service.settings = nil

    viewModel = ContentViewModel()

    await viewModel?.prepareStartupIfNeeded()

    XCTAssertEqual(service.settings?.BACKEND_VERSION, "v2.13.14")
    XCTAssertNil(viewModel?.backendVersionWarning)

    service.baseURL = "https://old.content-view-model-tests.local"
    service.token = "token-b"
    service.currentUser = token("token-b", userName: "second-user")

    try await waitUntil("expected settings to reload from old backend") {
      service.settings?.BACKEND_VERSION == "v2.13.13"
    }

    XCTAssertEqual(viewModel?.backendVersionWarning?.backendVersion, "v2.13.13")
    XCTAssertEqual(
      viewModel?.backendVersionWarning?.requiredVersion,
      AppVersionInfo.compatibleMoviePilotVersion
    )
  }

  private func token(_ value: String, userName: String) -> Token {
    Token(
      access_token: value,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
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
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    service.settings = settings
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

  func reset() {
    requests.removeAll()
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let backendVersion: String
    switch url.host {
    case "old.content-view-model-tests.local":
      backendVersion = "v2.13.13"
    default:
      backendVersion = "v2.13.14"
    }

    let data: Data
    if url.path == "/api/v1/system/global" {
      data =
        #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"\#(backendVersion)","FRONTEND_VERSION":"v2.13.15"}}"#
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
      statusCode: 200,
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
