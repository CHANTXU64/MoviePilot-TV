import Foundation
import XCTest

@testable import MoviePilot_TV

// MARK: - 可释放的异步门

private actor SharedFetcherAsyncGate {
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation = $0 }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

// MARK: - URLProtocol stub（按 page 返回响应序列）

private struct SharedFetcherHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private actor SharedFetcherURLProtocolStub {
  static let shared = SharedFetcherURLProtocolStub()

  private var mediaJSONByPage: [Int: String] = [:]
  private var pageRequestCounts: [Int: Int] = [:]
  private var gateForPage1: SharedFetcherAsyncGate?

  func reset() {
    mediaJSONByPage.removeAll()
    pageRequestCounts.removeAll()
    gateForPage1 = nil
  }

  func setMedia(_ json: String, forPage page: Int) {
    mediaJSONByPage[page] = json
  }

  func setPage1Gate(_ gate: SharedFetcherAsyncGate) {
    gateForPage1 = gate
  }

  func requestCount(page: Int) -> Int {
    pageRequestCounts[page, default: 0]
  }

  func response(for request: URLRequest) async throws -> SharedFetcherHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }
    let page =
      Int(components.queryItems?.first(where: { $0.name == "page" })?.value ?? "") ?? 0
    pageRequestCounts[page, default: 0] += 1
    if page == 1, let gate = gateForPage1 {
      await gate.wait()
    }
    let body = mediaJSONByPage[page] ?? "[]"
    return SharedFetcherHTTPStubResponse(statusCode: 200, data: Data(body.utf8))
  }
}

private final class SharedMediaFetcherURLProtocol: URLProtocol {
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "shared-fetcher.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let box = SharedMediaFetcherURLProtocolClientBox(protocolInstance: self, client: client)
    loadingTask = Task {
      do {
        let stubResponse = try await SharedFetcherURLProtocolStub.shared.response(
          for: box.request)
        guard !Task.isCancelled else { return }
        box.succeed(stubResponse)
      } catch {
        guard !Task.isCancelled else { return }
        box.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class SharedMediaFetcherURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?
  let request: URLRequest

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
    self.request = protocolInstance.request
  }

  func succeed(_ stubResponse: SharedFetcherHTTPStubResponse) {
    guard let url = request.url else { return }
    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: stubResponse.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(protocolInstance, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: stubResponse.data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}

// MARK: - Fixtures

private func mediaJSON(type: String, count: Int, startId: Int) -> String {
  let items = (0..<count).map { i in
    let id = startId + i
    return #"{"tmdb_id": \#(id), "source": "themoviedb", "title": "片\#(id)", "type": "\#(type)", "year": "2026", "poster_path": "/p\#(id).jpg", "popularity": 1}"#
  }
  return "[" + items.joined(separator: ",") + "]"
}

@MainActor
private func configureSharedFetcherSession(_ service: APIService) {
  service.baseURLForTesting = "http://shared-fetcher.local"
  service.tokenForTesting = "shared-fetcher-token"
  service.currentUserForTesting = Token(
    access_token: "shared-fetcher-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": true,
      "search": true,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 501,
    user_name: "shared-fetcher-user",
    avatar: nil
  )
}

// MARK: - 测试

@MainActor
final class SharedMediaFetcherTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(
      APIService.installURLProtocolForTesting(SharedMediaFetcherURLProtocol.self))
    await SharedFetcherURLProtocolStub.shared.reset()
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(SharedMediaFetcherURLProtocol.self)
  }

  func testSharedTaskRetiresBeforeWaitersRecoverSoPage3IsFetched() async throws {
    let service = APIService.isolatedTestingInstance()
    configureSharedFetcherSession(service)

    let gate = SharedFetcherAsyncGate()
    await SharedFetcherURLProtocolStub.shared.setPage1Gate(gate)
    await SharedFetcherURLProtocolStub.shared.setMedia(
      mediaJSON(type: "电影", count: 4, startId: 1), forPage: 1)
    await SharedFetcherURLProtocolStub.shared.setMedia(
      mediaJSON(type: "电影", count: 4, startId: 100), forPage: 2)
    // 页 3 才出现电视剧：只有共享 task 及时退休，电视剧 waiter 才会继续抓页 3
    await SharedFetcherURLProtocolStub.shared.setMedia(
      mediaJSON(type: "电视剧", count: 8, startId: 200), forPage: 3)

    let fetcher = SharedMediaFetcher(query: "测试", source: nil, apiService: service)

    // 电影 waiter 先创建共享 task（页 1 被 gate 卡住，task 未完成）
    let movieTask = Task { try await fetcher.fetchMovies() }
    let deadline = Date().addingTimeInterval(5)
    while await SharedFetcherURLProtocolStub.shared.requestCount(page: 1) == 0,
      Date() < deadline
    {
      try? await Task.sleep(for: .milliseconds(20))
    }
    let page1Started = await SharedFetcherURLProtocolStub.shared.requestCount(page: 1)
    XCTAssertGreaterThan(page1Started, 0)

    // 电视剧 waiter 合流到同一个 task，两者都挂起等待
    let tvTask = Task { try await fetcher.fetchTVShows() }
    try? await Task.sleep(for: .milliseconds(200))

    // 放行页 1，共享 task 完成；两个 waiter 同时恢复，顺序不受控制
    await gate.release()

    let movies = try await movieTask.value
    let tvs = try await tvTask.value

    XCTAssertEqual(movies.count, 8, "电影应拿到页 1+2 共 8 条")
    XCTAssertEqual(tvs.count, 8, "电视剧应在共享 task 退休后继续抓页 3，拿到 8 条")
    let page1Count = await SharedFetcherURLProtocolStub.shared.requestCount(page: 1)
    let page2Count = await SharedFetcherURLProtocolStub.shared.requestCount(page: 2)
    let page3Count = await SharedFetcherURLProtocolStub.shared.requestCount(page: 3)
    XCTAssertEqual(page1Count, 1)
    XCTAssertEqual(page2Count, 1)
    XCTAssertEqual(page3Count, 1)
  }
}
