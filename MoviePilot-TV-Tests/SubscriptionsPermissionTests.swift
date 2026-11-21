import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscriptionsPermissionTests: XCTestCase {
  func testSubscriptionsPageDoesNotRequestSubscribeForStandardUserWithEmptyPermissions()
    async throws
  {
    try await withSubscriptionPermissionService(permissions: [:]) { service in
      let viewModel = SubscriptionsViewModel(apiService: service)
      await viewModel.loadData()

      XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.tvSubscriptions.isEmpty)
      XCTAssertFalse(viewModel.subscriptionsLoadFailed)
      let paths = await SubscriptionPermissionURLProtocol.stub.requestPaths()
      XCTAssertFalse(paths.containsSubscribeListPath)
    }
  }

  func testSubscriptionsPageRequestsSubscribeWhenPermissionIsGranted()
    async throws
  {
    try await withSubscriptionPermissionService(
      permissions: [UserPermissionKey.subscribe.rawValue: true]
    ) { service in
      let viewModel = SubscriptionsViewModel(apiService: service)
      await viewModel.loadData()

      XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.tvSubscriptions.isEmpty)
      XCTAssertFalse(viewModel.showsLoadingPlaceholder, "读成功空列表后显示空态，不再转圈")
      let paths = await SubscriptionPermissionURLProtocol.stub.requestPaths()
      XCTAssertTrue(paths.containsSubscribeListPath)
    }
  }

  func testSubscriptionsPageDoesNotRequestSubscribeWhenPermissionIsExplicitlyDenied()
    async throws
  {
    try await withSubscriptionPermissionService(
      permissions: [UserPermissionKey.subscribe.rawValue: false]
    ) { service in
      let viewModel = SubscriptionsViewModel(apiService: service)
      await viewModel.loadData()

      XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
      XCTAssertTrue(viewModel.tvSubscriptions.isEmpty)
      let paths = await SubscriptionPermissionURLProtocol.stub.requestPaths()
      XCTAssertFalse(paths.containsSubscribeListPath)
    }
  }

  /// 订阅移到了自己的 Tab：媒体库页即使有订阅权限也不再读订阅列表，也不轮询它。
  func testHomeNoLongerRequestsSubscribeEvenWhenPermissionIsGranted()
    async throws
  {
    try await withSubscriptionPermissionService(
      permissions: [UserPermissionKey.subscribe.rawValue: true]
    ) { service in
      let viewModel = HomeViewModel(apiService: service)
      await viewModel.refreshData()
      await viewModel.refreshData(includeContinueWatching: false)

      let paths = await SubscriptionPermissionURLProtocol.stub.requestPaths()
      XCTAssertFalse(paths.containsSubscribeListPath)
    }
  }

  private func withSubscriptionPermissionService(
    permissions: [String: Bool],
    operation: (APIService) async throws -> Void
  ) async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionPermissionURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionPermissionURLProtocol.self) }

    await SubscriptionPermissionURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionPermissionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://subscription-permission-tests.local"
    service.tokenForTesting = "token"
    service.currentUserForTesting = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: permissions,
      user_name: "test",
      avatar: nil
    )

    try await operation(service)
  }

  func testSubscribeFocusIDMatchesBetweenRedirectorAndCardBinding() {
    let id: Int? = 123

    XCTAssertEqual(SubscribeFocusID.value(for: id), "123")
    XCTAssertNotEqual(SubscribeFocusID.value(for: id), String(describing: id))
  }

  func testSubscribeFocusIDIsNilWhenSubscribeIDIsMissing() {
    XCTAssertNil(SubscribeFocusID.value(for: Optional<Int>.none))
  }
}

private extension Array where Element == String {
  var containsSubscribeListPath: Bool {
    contains { $0 == "/api/v1/subscribe" || $0 == "/api/v1/subscribe/" }
  }
}

private struct SubscriptionPermissionServiceSnapshot {
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
  static func capture(service: APIService) -> SubscriptionPermissionServiceSnapshot {
    SubscriptionPermissionServiceSnapshot(
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
    service.baseURLForTesting = baseURL
    service.tokenForTesting = token
    service.currentUserForTesting = currentUser
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

private actor SubscriptionPermissionURLProtocolStub {
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

private final class SubscriptionPermissionURLProtocol: URLProtocol {
  static let stub = SubscriptionPermissionURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscription-permission-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscriptionPermissionURLProtocolTaskContext(
      request: request,
      clientBox: SubscriptionPermissionURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SubscriptionPermissionURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscriptionPermissionURLProtocolTaskContext)
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

private final class SubscriptionPermissionURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscriptionPermissionURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscriptionPermissionURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscriptionPermissionURLProtocolClientBox: @unchecked Sendable {
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
