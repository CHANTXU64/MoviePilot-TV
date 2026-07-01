import XCTest

@testable import MoviePilot_TV

@MainActor
final class PermissionScopedLoadViewModelTests: XCTestCase {
  func testAddDownloadPendingLoadDoesNotPublishOptionsAfterSearchPermissionIsRestricted()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(PermissionScopedLoadURLProtocol.self))
    defer { URLProtocol.unregisterClass(PermissionScopedLoadURLProtocol.self) }

    let service = APIService.shared
    let snapshot = PermissionScopedServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await PermissionScopedLoadURLProtocol.stub.reset()
    await PermissionScopedLoadURLProtocol.stub.suspend(
      path: "/api/v1/system/setting/Directories")
    service.baseURL = "http://permission-scoped-load.local"
    configureSearchUser(service)

    let viewModel = AddDownloadViewModel(torrent: Self.torrentFixture())
    let loadTask = Task { await viewModel.loadData() }
    try await waitUntil("directories request started") {
      await PermissionScopedLoadURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/system/setting/Directories") == 1
    }

    configureNoSearchUser(service)
    await PermissionScopedLoadURLProtocol.stub.release(
      path: "/api/v1/system/setting/Directories")
    await loadTask.value

    XCTAssertTrue(viewModel.downloaders.isEmpty)
    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertNil(viewModel.selectedDownloader)
    XCTAssertNil(viewModel.selectedDirectory)
  }

  func testSiteFilterPendingLoadDoesNotPublishSitesAfterSearchPermissionIsRestricted()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(PermissionScopedLoadURLProtocol.self))
    defer { URLProtocol.unregisterClass(PermissionScopedLoadURLProtocol.self) }

    let service = APIService.shared
    let snapshot = PermissionScopedServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await PermissionScopedLoadURLProtocol.stub.reset()
    await PermissionScopedLoadURLProtocol.stub.suspend(path: "/api/v1/site/rss")
    service.baseURL = "http://permission-scoped-load.local"
    configureSearchUser(service)

    let viewModel = SiteFilterViewModel()
    viewModel.selectedSites = [1]
    let loadTask = Task { await viewModel.loadSites() }
    try await waitUntil("sites request started") {
      await PermissionScopedLoadURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/site/rss") == 1
    }

    configureNoSearchUser(service)
    await PermissionScopedLoadURLProtocol.stub.release(path: "/api/v1/site/rss")
    await loadTask.value

    XCTAssertTrue(viewModel.availableSites.isEmpty)
    XCTAssertTrue(viewModel.selectedSites.isEmpty)
  }

  func testReorganizePendingLoadDoesNotPublishConfigAfterManagePermissionIsRestricted()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(PermissionScopedLoadURLProtocol.self))
    defer { URLProtocol.unregisterClass(PermissionScopedLoadURLProtocol.self) }

    let service = APIService.shared
    let snapshot = PermissionScopedServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await PermissionScopedLoadURLProtocol.stub.reset()
    await PermissionScopedLoadURLProtocol.stub.suspend(
      path: "/api/v1/system/setting/Storages")
    service.baseURL = "http://permission-scoped-load.local"
    configureManageUser(service)

    let viewModel = ReorganizeViewModel(logIds: [], fileItem: nil)
    let loadTask = Task { await viewModel.loadConfig() }
    try await waitUntil("storages request started") {
      await PermissionScopedLoadURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/system/setting/Storages") == 1
    }

    configureSearchUser(service)
    await PermissionScopedLoadURLProtocol.stub.release(
      path: "/api/v1/system/setting/Storages")
    await loadTask.value

    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertTrue(viewModel.storages.isEmpty)
    XCTAssertEqual(viewModel.targetDirectoryOptions.map(\.value), [""])
  }

  private func configureSearchUser(_ service: APIService) {
    service.token = "search-user"
    service.currentUser = Token(
      access_token: "search-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "search-user",
      avatar: nil
    )
  }

  private func configureNoSearchUser(_ service: APIService) {
    service.token = "no-search-user"
    service.currentUser = Token(
      access_token: "no-search-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "no-search-user",
      avatar: nil
    )
  }

  private func configureManageUser(_ service: APIService) {
    service.token = "manage-user"
    service.currentUser = Token(
      access_token: "manage-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "manage-user",
      avatar: nil
    )
  }

  private static func torrentFixture() -> TorrentInfo {
    TorrentInfo(
      site: 1,
      site_name: "站点",
      site_order: nil,
      title: "测试资源",
      description: nil,
      enclosure: "https://example.com/test.torrent",
      page_url: nil,
      size: 1024,
      seeders: nil,
      peers: nil,
      pubdate: nil,
      uploadvolumefactor: 1,
      downloadvolumefactor: 1,
      pri_order: nil,
      labels: nil,
      volume_factor: nil
    )
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
}

private struct PermissionScopedServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let token: String?
  let currentUser: Token?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> PermissionScopedServiceSnapshot {
    PermissionScopedServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      token: service.token,
      currentUser: service.currentUser,
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

private actor PermissionScopedLoadURLProtocolStub {
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
      data = #"[{"id":1,"name":"站点A","domain":null,"url":null,"downloader":null,"is_active":true}]"#
        .data(using: .utf8)!
    case ("GET", "/api/v1/download/clients"):
      data = #"[{"name":"qbittorrent","type":"qbittorrent","enabled":true}]"#
        .data(using: .utf8)!
    case ("GET", "/api/v1/system/setting/Directories"):
      data = #"{"value":[{"name":"电影","storage":"local","download_path":"/downloads","library_path":"/media/movie","library_storage":"local","transfer_type":"move","scraping":true,"library_category_folder":false,"library_type_folder":false}]}"#
        .data(using: .utf8)!
    case ("GET", "/api/v1/system/setting/Storages"):
      data = #"{"value":[{"name":"local","type":"local"}]}"#.data(using: .utf8)!
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

private final class PermissionScopedLoadURLProtocol: URLProtocol {
  static let stub = PermissionScopedLoadURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "permission-scoped-load.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = PermissionScopedURLProtocolTaskContext(
      request: request,
      clientBox: PermissionScopedURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = Self.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: PermissionScopedURLProtocolTaskContext)
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

private final class PermissionScopedURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: PermissionScopedURLProtocolClientBox

  init(request: URLRequest, clientBox: PermissionScopedURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class PermissionScopedURLProtocolClientBox: @unchecked Sendable {
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
