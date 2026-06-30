import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSheetViewModelTests: XCTestCase {
  private let autoSearchKey = "autoSearchNewSubscriptions"

  func testAutoSearchNewSubscriptionsDefaultsToEnabled() {
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    UserDefaults.standard.removeObject(forKey: autoSearchKey)
    defer { restoreUserDefaultsValue(originalValue, forKey: autoSearchKey) }

    let viewModel = SystemViewModel()

    XCTAssertTrue(viewModel.autoSearchNewSubscriptions)
    XCTAssertTrue(SystemViewModel.shouldAutoSearchNewSubscriptions)
  }

  func testSaveNewSubscriptionSkipsSearchWhenAutoSearchSettingIsDisabled() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.set(false, forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 777, name: "关闭自动搜索", type: "电影", tmdbid: 123456),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/777")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/777")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 0)
  }

  func testSaveNewSubscriptionSearchesByDefault() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.removeObject(forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 778, name: "默认自动搜索", type: "电影", tmdbid: 123457),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/778")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/778")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 1)
  }

  func testSaveExistingSubscriptionSearchesWhenNewSubscriptionAutoSearchIsDisabled() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.set(false, forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 779, name: "已有订阅", type: "电影", tmdbid: 123458),
      isNewSubscription: false
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/779")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/779")
    XCTAssertEqual(statusRequestCount, 0)
    XCTAssertEqual(searchRequestCount, 1)
  }

  func testLoadDataLoadsFilterGroupsForStandardUserWithSubscribePermission() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    service.token = "standard-user"
    service.currentUser = Token(
      access_token: "standard-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "standard",
      avatar: nil)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 780, name: "普通订阅账号", type: "电影", tmdbid: 123459),
      isNewSubscription: false
    )

    await viewModel.loadData()

    XCTAssertEqual(viewModel.filterGroups.map(\.name), ["普通规则组"])
    let filterGroupsRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/system/setting/UserFilterRuleGroups")
    XCTAssertEqual(filterGroupsRequestCount, 1)
  }

  func testPendingLoadDataDoesNotPublishOptionsAfterSubscribePermissionIsRestricted()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.suspend(path: "/api/v1/system/setting/UserFilterRuleGroups")
    service.baseURL = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 782, name: "权限降级", type: "电影", tmdbid: 123461),
      isNewSubscription: false
    )

    let loadTask = Task { await viewModel.loadData() }
    try await waitUntil("filter groups request started") {
      await SubscribeSheetURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/system/setting/UserFilterRuleGroups") == 1
    }

    configureNoSubscribeUser(service)
    await SubscribeSheetURLProtocol.stub.release(path: "/api/v1/system/setting/UserFilterRuleGroups")
    await loadTask.value

    XCTAssertTrue(viewModel.sites.isEmpty)
    XCTAssertTrue(viewModel.downloaders.isEmpty)
    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertTrue(viewModel.filterGroups.isEmpty)
  }

  func testSubscribeSheetAndHandlerDoNotRequestSubscribeEndpointsWithoutPermission() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    configureNoSubscribeUser(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 781, name: "无订阅权限", type: "电影", tmdbid: 123460),
      isNewSubscription: false
    )
    await viewModel.loadData()
    let didSave = await viewModel.save()
    await viewModel.cancel()

    XCTAssertTrue(viewModel.sites.isEmpty)
    XCTAssertTrue(viewModel.downloaders.isEmpty)
    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertTrue(viewModel.filterGroups.isEmpty)
    XCTAssertFalse(didSave)

    let handler = SubscriptionHandler()
    handler.handleSubscribe(MediaInfo(tmdb_id: 123460, title: "无订阅权限", type: "电影"))
    let share = try JSONDecoder().decode(
      SubscribeShare.self,
      from: Data(#"{"id":88,"share_title":"No Permission Share"}"#.utf8)
    )
    let forkedId = await handler.fork(share: share)
    await handler.fetchSubscriptionAndShowEditor(subId: 781)

    XCTAssertNil(handler.sheetSubscribe)
    XCTAssertNil(handler.tvSubscribeRequest)
    XCTAssertNil(handler.forkSheetRequest)
    XCTAssertNil(forkedId)
    XCTAssertFalse(handler.showAlert)

    let requestCount = await SubscribeSheetURLProtocol.stub.totalRequestCount()
    XCTAssertEqual(requestCount, 0)
  }

  private func restoreUserDefaultsValue(_ value: Any?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(description)")
  }

  private func configureSubscriber(_ service: APIService) {
    service.token = "subscribe-sheet-user"
    service.currentUser = Token(
      access_token: "subscribe-sheet-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "subscribe-sheet",
      avatar: nil
    )
  }

  private func configureNoSubscribeUser(_ service: APIService) {
    service.token = "subscribe-sheet-no-subscribe"
    service.currentUser = Token(
      access_token: "subscribe-sheet-no-subscribe",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "subscribe-sheet-no-subscribe",
      avatar: nil
    )
  }
}

private struct SubscribeSheetServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SubscribeSheetServiceSnapshot {
    SubscribeSheetServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      useImageCache: service.useImageCache,
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

private actor SubscribeSheetURLProtocolStub {
  private var requestCounts: [String: Int] = [:]
  private var suspendedPaths: Set<String> = []
  private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

  func reset() {
    requestCounts.removeAll()
    suspendedPaths.removeAll()
    let pendingWaiters = waiters.values.flatMap { $0 }
    waiters.removeAll()
    pendingWaiters.forEach { $0.resume() }
  }

  func suspend(path: String) {
    suspendedPaths.insert(path)
  }

  func release(path: String) {
    suspendedPaths.remove(path)
    let pendingWaiters = waiters.removeValue(forKey: path) ?? []
    pendingWaiters.forEach { $0.resume() }
  }

  func requestCount(method: String, path: String) -> Int {
    requestCounts["\(method) \(path)", default: 0]
  }

  func totalRequestCount() -> Int {
    requestCounts.values.reduce(0, +)
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""
    requestCounts["\(method) \(path)", default: 0] += 1
    if suspendedPaths.contains(path) {
      await withCheckedContinuation { continuation in
        waiters[path, default: []].append(continuation)
      }
    }

    let data: Data
    switch (method, path) {
    case ("GET", "/api/v1/site/rss"):
      data = #"[]"#.data(using: .utf8)!
    case ("GET", "/api/v1/download/clients"):
      data = #"[]"#.data(using: .utf8)!
    case ("GET", "/api/v1/system/setting/Directories"):
      data = #"{"value":[]}"#.data(using: .utf8)!
    case ("GET", "/api/v1/system/setting/UserFilterRuleGroups"):
      data = #"{"value":[{"name":"普通规则组"}]}"#.data(using: .utf8)!
    case let (_, path) where path.hasPrefix("/api/v1/subscribe"):
      data = #"{"success":true}"#.data(using: .utf8)!
    default:
      throw URLError(.badServerResponse)
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class SubscribeSheetURLProtocol: URLProtocol {
  static let stub = SubscribeSheetURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscribe-sheet-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscribeSheetURLProtocolTaskContext(
      request: request,
      clientBox: SubscribeSheetURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SubscribeSheetURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscribeSheetURLProtocolTaskContext)
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

private final class SubscribeSheetURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscribeSheetURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscribeSheetURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscribeSheetURLProtocolClientBox: @unchecked Sendable {
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
