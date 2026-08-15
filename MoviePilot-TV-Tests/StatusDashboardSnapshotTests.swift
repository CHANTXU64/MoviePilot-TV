import XCTest

@testable import MoviePilot_TV

@MainActor
final class StatusDashboardSnapshotTests: XCTestCase {
  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(StatusDashboardURLProtocol.self))
    StatusDashboardURLProtocol.stub.reset()
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(StatusDashboardURLProtocol.self)
    StatusDashboardURLProtocol.stub.reset()
    super.tearDown()
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://status-dashboard-tests.local"
    service.tokenForTesting = "dashboard-token"
    service.currentUserForTesting = Token(
      access_token: "dashboard-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: nil,
      user_name: "dashboard-admin",
      avatar: nil
    )
    return service
  }

  func testPartialFailureKeepsPreviousCompleteSnapshot() async throws {
    let service = makeService()
    let viewModel = StatusViewModel(apiService: service)

    await viewModel.refreshAllData()
    XCTAssertEqual(viewModel.statistic?.movie_count, 2)
    XCTAssertEqual(viewModel.storage?.total_storage, 100)
    XCTAssertEqual(viewModel.downloader?.download_speed, 7)

    StatusDashboardURLProtocol.stub.setStatusCode(
      for: "/api/v1/dashboard/storage", 500)
    await viewModel.refreshAllData()

    // 任一失败整组不发布：三个值都保留上一完整快照，不形成混合快照
    XCTAssertEqual(viewModel.statistic?.movie_count, 2)
    XCTAssertEqual(viewModel.storage?.total_storage, 100)
    XCTAssertEqual(viewModel.downloader?.download_speed, 7)
  }

  func testFirstLoadPartialFailurePublishesNothing() async throws {
    StatusDashboardURLProtocol.stub.setStatusCode(
      for: "/api/v1/dashboard/storage", 500)

    let service = makeService()
    let viewModel = StatusViewModel(apiService: service)

    await viewModel.refreshAllData()

    XCTAssertNil(viewModel.statistic)
    XCTAssertNil(viewModel.storage)
    XCTAssertNil(viewModel.downloader)
  }

  func testSessionChangeDoesNotPublishResults() async throws {
    StatusDashboardURLProtocol.stub.setDownloaderDelay(nanoseconds: 500_000_000)

    let service = makeService()
    let viewModel = StatusViewModel(apiService: service)

    let task = Task { await viewModel.refreshAllData() }
    try await waitUntil("downloader request in flight") {
      StatusDashboardURLProtocol.stub.requestPaths().contains("/api/v1/dashboard/downloader")
    }

    // 请求在途时切换会话：结果不得发布到新会话
    service.tokenForTesting = "other-token"
    await task.value

    XCTAssertNil(viewModel.statistic)
    XCTAssertNil(viewModel.storage)
    XCTAssertNil(viewModel.downloader)
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    predicate: @escaping @MainActor () -> Bool
  ) async throws {
    let start = ContinuousClock.now
    while !predicate() {
      if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
        XCTFail("Timed out waiting for \(description)")
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}

private final class StatusDashboardURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []
  private var statusCodes: [String: Int] = [:]
  private var downloaderDelayNanoseconds: UInt64 = 0

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    paths = []
    statusCodes = [:]
    downloaderDelayNanoseconds = 0
  }

  func setStatusCode(for path: String, _ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    statusCodes[path] = statusCode
  }

  func setDownloaderDelay(nanoseconds: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    downloaderDelayNanoseconds = nanoseconds
  }

  func requestPaths() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return paths
  }

  func statusCode(for path: String) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    return statusCodes[path]
  }

  func downloaderDelayNanosecondsValue() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return downloaderDelayNanoseconds
  }

  func record(path: String) {
    lock.lock()
    defer { lock.unlock() }
    paths.append(path)
  }
}

private final class StatusDashboardURLProtocol: URLProtocol {
  static let stub = StatusDashboardURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "status-dashboard-tests.local"
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

    if path == "/api/v1/dashboard/downloader" {
      let delay = Self.stub.downloaderDelayNanosecondsValue()
      if delay > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) {
          self.respond(statusCode: 200, body: Self.downloaderJSON)
        }
        return
      }
    }

    switch path {
    case "/api/v1/dashboard/statistic":
      respond(statusCode: Self.stub.statusCode(for: path) ?? 200, body: Self.statisticJSON)
    case "/api/v1/dashboard/storage":
      respond(statusCode: Self.stub.statusCode(for: path) ?? 200, body: Self.storageJSON)
    case "/api/v1/dashboard/downloader":
      respond(statusCode: Self.stub.statusCode(for: path) ?? 200, body: Self.downloaderJSON)
    default:
      respond(statusCode: 200, body: "{}")
    }
  }

  override func stopLoading() {}

  private static let statisticJSON = #"{"movie_count":2,"tv_count":3,"episode_count":4}"#
  private static let storageJSON = #"{"total_storage":100,"used_storage":40}"#
  private static let downloaderJSON =
    #"{"download_speed":7,"upload_speed":1,"download_size":20,"upload_size":2,"free_space":60}"#

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
