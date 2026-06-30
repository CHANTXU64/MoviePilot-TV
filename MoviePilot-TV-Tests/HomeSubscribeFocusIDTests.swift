import XCTest

@testable import MoviePilot_TV

@MainActor
final class HomeSubscribeFocusIDTests: XCTestCase {
  func testRefreshDataRequestsSubscribeForStandardUserWithEmptyPermissions()
    async throws
  {
    try await withHomePermissionViewModel(permissions: [:]) { viewModel in
      await viewModel.refreshData()

      XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.tvSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.latestMedia.isEmpty)
      let paths = await HomePermissionURLProtocol.stub.requestPaths()
      XCTAssertTrue(paths.containsSubscribeListPath)
      XCTAssertFalse(paths.contains("/api/v1/system/setting/MediaServers"))
    }
  }

  func testRefreshDataDoesNotRequestSubscribeWhenPermissionIsExplicitlyDenied()
    async throws
  {
    try await withHomePermissionViewModel(
      permissions: [UserPermissionKey.subscribe.rawValue: false]
    ) { viewModel in
      await viewModel.refreshData()

      XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.tvSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.latestMedia.isEmpty)
      let paths = await HomePermissionURLProtocol.stub.requestPaths()
      XCTAssertFalse(paths.containsSubscribeListPath)
      XCTAssertFalse(paths.contains("/api/v1/system/setting/MediaServers"))
    }
  }

  private func withHomePermissionViewModel(
    permissions: [String: Bool],
    operation: (HomeViewModel) async throws -> Void
  ) async throws {
    XCTAssertTrue(URLProtocol.registerClass(HomePermissionURLProtocol.self))
    defer { URLProtocol.unregisterClass(HomePermissionURLProtocol.self) }

    await HomePermissionURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = HomePermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://home-permission-tests.local"
    service.token = "token"
    service.currentUser = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: permissions,
      user_name: "test",
      avatar: nil
    )

    try await operation(HomeViewModel(apiService: service))
  }

  func testSubscribeFocusIDMatchesBetweenRedirectorAndCardBinding() {
    let id: Int? = 123

    XCTAssertEqual(HomeSubscribeFocusID.value(for: id), "123")
    XCTAssertNotEqual(HomeSubscribeFocusID.value(for: id), String(describing: id))
  }

  func testSubscribeFocusIDIsNilWhenSubscribeIDIsMissing() {
    XCTAssertNil(HomeSubscribeFocusID.value(for: Optional<Int>.none))
  }
}

private extension Array where Element == String {
  var containsSubscribeListPath: Bool {
    contains { $0 == "/api/v1/subscribe" || $0 == "/api/v1/subscribe/" }
  }
}

private struct HomePermissionServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> HomePermissionServiceSnapshot {
    HomePermissionServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      useImageCache: service.useImageCache,
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
    service.settings = settings
    service.useImageCache = useImageCache
    restoreDefaults(value: serverURLDefaults, forKey: "serverURL")
    restoreCredential(account: "accessToken", keychainValue: tokenKeychain, defaultsValue: tokenDefaults)
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
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

private actor HomePermissionURLProtocolStub {
  private var requests: [URLRequest] = []

  func reset() {
    requests.removeAll()
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let data = #"{"success":true,"data":[]}"#.data(using: .utf8)!
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class HomePermissionURLProtocol: URLProtocol {
  static let stub = HomePermissionURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "home-permission-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = HomePermissionURLProtocolTaskContext(
      request: request,
      clientBox: HomePermissionURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = HomePermissionURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: HomePermissionURLProtocolTaskContext)
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

private final class HomePermissionURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: HomePermissionURLProtocolClientBox

  init(request: URLRequest, clientBox: HomePermissionURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class HomePermissionURLProtocolClientBox: @unchecked Sendable {
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
