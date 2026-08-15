import XCTest

@testable import MoviePilot_TV

@MainActor
final class HomeViewModelMediaServerSnapshotTests: XCTestCase {
  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(HomeMediaServerSnapshotURLProtocol.self))
    HomeMediaServerSnapshotURLProtocol.stub.reset()
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(HomeMediaServerSnapshotURLProtocol.self)
    HomeMediaServerSnapshotURLProtocol.stub.reset()
    super.tearDown()
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://home-snapshot-tests.local"
    service.tokenForTesting = "snapshot-token"
    service.currentUserForTesting = Token(
      access_token: "snapshot-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "snapshot-admin",
      avatar: nil
    )
    return service
  }

  func testServerFailureKeepsPreviousSnapshotWhileOthersUpdate() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()
    XCTAssertEqual(viewModel.latestMediaServers, ["emby", "plex"])
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])

    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "emby", .httpStatus500)
    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "plex", .success(["Plex New"]))
    await viewModel.refreshData()

    // 失败服务器保留上一轮卡片
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])
    // 成功服务器正常更新为新结果
    viewModel.selectedLatestMediaServer = "plex"
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Plex New"])
  }

  func testServerNetworkErrorKeepsPreviousSnapshot() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])

    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "emby", .networkError)
    await viewModel.refreshData()

    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])
  }

  func testServerSuccessEmptyClearsOnlyThatServer() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])

    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "emby", .success([]))
    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "plex", .success(["Plex New"]))
    await viewModel.refreshData()

    // 成功空响应才清空该服务器
    XCTAssertTrue(viewModel.latestMedia.isEmpty)
    viewModel.selectedLatestMediaServer = "plex"
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Plex New"])
  }

  func testServerCancellationKeepsPreviousSnapshot() async throws {
    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])

    let latestRequestsBefore = HomeMediaServerSnapshotURLProtocol.stub.requestPaths().filter {
      $0 == "/api/v1/mediaserver/latest"
    }.count
    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "emby", .cancelled)
    await viewModel.refreshData()

    // 取消不发布，旧快照保持不变
    XCTAssertEqual(viewModel.latestMedia.map(\.title), ["Emby Latest"])
    XCTAssertGreaterThan(
      HomeMediaServerSnapshotURLProtocol.stub.requestPaths().filter {
        $0 == "/api/v1/mediaserver/latest"
      }.count,
      latestRequestsBefore
    )
  }

  func testFirstLoadFailureShowsNoCards() async throws {
    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "emby", .httpStatus500)
    HomeMediaServerSnapshotURLProtocol.stub.setLatestResult(server: "plex", .networkError)

    let service = makeService()
    let viewModel = HomeViewModel(apiService: service)

    await viewModel.refreshData()

    // 服务器列表成功，但没有可用卡片
    XCTAssertEqual(viewModel.latestMediaServers, ["emby", "plex"])
    XCTAssertTrue(viewModel.latestMedia.isEmpty)
  }
}

private enum HomeLatestResult: Equatable {
  case success([String])
  case httpStatus500
  case networkError
  case cancelled
}

private final class HomeMediaServerSnapshotURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []
  private var latestResults: [String: HomeLatestResult] = [:]

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    paths = []
    latestResults = [
      "emby": .success(["Emby Latest"]),
      "plex": .success(["Plex Latest"]),
    ]
  }

  func setLatestResult(server: String, _ result: HomeLatestResult) {
    lock.lock()
    defer { lock.unlock() }
    latestResults[server] = result
  }

  func requestPaths() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return paths
  }

  func latestResult(for server: String) -> HomeLatestResult? {
    lock.lock()
    defer { lock.unlock() }
    return latestResults[server]
  }

  func record(path: String) {
    lock.lock()
    defer { lock.unlock() }
    paths.append(path)
  }
}

private final class HomeMediaServerSnapshotURLProtocol: URLProtocol {
  static let stub = HomeMediaServerSnapshotURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "home-snapshot-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let path = url.path
    Self.stub.record(path: path)

    switch path {
    case "/api/v1/system/setting/MediaServers":
      respond(
        statusCode: 200,
        body:
          #"{"value":[{"name":"emby","type":"emby","enabled":true},{"name":"plex","type":"plex","enabled":true}]}"#
      )
    case "/api/v1/mediaserver/latest":
      let server = queryItem(named: "server", in: url) ?? ""
      switch Self.stub.latestResult(for: server) ?? .success([]) {
      case .success(let titles):
        let items = titles.enumerated().map { index, title in
          #"{"id":"\#(server)-\#(index)","title":"\#(title)","server_type":"\#(server)"}"#
        }
        respond(statusCode: 200, body: "[\(items.joined(separator: ","))]")
      case .httpStatus500:
        respond(statusCode: 500, body: #"{"message":"server unavailable"}"#)
      case .networkError:
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      case .cancelled:
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
      }
    case "/api/v1/subscribe", "/api/v1/subscribe/":
      respond(statusCode: 200, body: "[]")
    default:
      respond(statusCode: 200, body: "[]")
    }
  }

  override func stopLoading() {}

  private func queryItem(named name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .first { $0.name == name }?
      .value
  }

  private func respond(statusCode: Int, body: String) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
