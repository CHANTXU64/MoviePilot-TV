import Foundation
import XCTest

@testable import MoviePilot_TV

// MARK: - URLProtocol stub（按路径配置响应序列）

private struct SuccessEmptyHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private actor SuccessEmptyURLProtocolStub {
  private var plansByPath: [String: [String]] = [:]
  private var requestCountsByPath: [String: Int] = [:]
  private var defaultBody = "[]"

  func reset() {
    plansByPath.removeAll()
    requestCountsByPath.removeAll()
    defaultBody = "[]"
  }

  /// 按路径配置响应序列：第 N 次请求返回第 N 个 body，超出后用最后一个。
  func setResponses(_ bodies: [String], forPath path: String) {
    plansByPath[path] = bodies
  }

  func requestCount(path: String) -> Int {
    requestCountsByPath[path, default: 0]
  }

  func response(for request: URLRequest) async throws -> SuccessEmptyHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }
    let path = components.path
    let count = requestCountsByPath[path, default: 0]
    requestCountsByPath[path] = count + 1
    let plan = plansByPath[path] ?? []
    let body = plan.isEmpty ? defaultBody : (count < plan.count ? plan[count] : plan[plan.count - 1])
    return SuccessEmptyHTTPStubResponse(statusCode: 200, data: Data(body.utf8))
  }
}

private final class SuccessEmptyURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = SuccessEmptyURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "success-empty.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let box = SuccessEmptyURLProtocolClientBox(protocolInstance: self, client: client)
    loadingTask = Task {
      do {
        let stubResponse = try await SuccessEmptyURLProtocol.stub.response(for: box.request)
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

private final class SuccessEmptyURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?
  let request: URLRequest

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
    self.request = protocolInstance.request
  }

  func succeed(_ stubResponse: SuccessEmptyHTTPStubResponse) {
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

private func mediaJSON(id: Int, title: String) -> String {
  """
  [
    {"tmdb_id": \(id), "source": "themoviedb", "title": "\(title)", "type": "电影", "year": "2026", "poster_path": "/p\(id).jpg", "popularity": 10}
  ]
  """
}

private func personJSON() -> String {
  """
  [
    {"source": "themoviedb", "id": 7, "name": "演员A", "profile_path": "/a.jpg"}
  ]
  """
}

private func decodeMedia(json: String) throws -> MediaInfo {
  let parsed = try JSONDecoder().decode(MediaInfoJSON.self, from: Data(json.utf8))
  return MediaInfo(json: parsed)
}

@MainActor
private func configureSuccessEmptySession(_ service: APIService) {
  service.baseURLForTesting = "http://success-empty.local"
  service.tokenForTesting = "success-empty-token"
  service.currentUserForTesting = Token(
    access_token: "success-empty-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: [
      "discovery": true,
      "search": true,
      "subscribe": false,
      "manage": false,
      "admin": false,
    ],
    user_id: 401,
    user_name: "success-empty-user",
    avatar: nil
  )
}

@MainActor
private func waitUntil(
  _ condition: () -> Bool,
  timeout: TimeInterval = 5,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    try? await Task.sleep(for: .milliseconds(50))
  }
  if !condition() {
    XCTFail("等待条件超时", file: file, line: line)
  }
}

// MARK: - 测试

@MainActor
final class SuccessEmptyReactivationTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SuccessEmptyURLProtocol.self))
    await SuccessEmptyURLProtocol.stub.reset()
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(SuccessEmptyURLProtocol.self)
  }

  // MARK: 推荐 shelf：成功空后重新激活自动重试

  func testRecommendSuccessEmptyShelfRetriesOnReactivation() async throws {
    UserDefaults.standard.removeObject(forKey: "MP_RECOMMEND")
    defer { UserDefaults.standard.removeObject(forKey: "MP_RECOMMEND") }

    let service = APIService.isolatedTestingInstance()
    configureSuccessEmptySession(service)

    await SuccessEmptyURLProtocol.stub.setResponses(
      ["[]", mediaJSON(id: 11, title: "回归片")],
      forPath: "/api/v1/recommend/tmdb_trending"
    )

    let viewModel = RecommendViewModel(apiService: service)

    // 等待 init 的 debounce 创建分页器并完成首次加载（成功空终态）
    await waitUntil {
      guard let paginator = viewModel.paginator else { return false }
      return paginator.items.isEmpty && !paginator.isLoading && !paginator.hasMore
    }
    let initialRequestCount = await SuccessEmptyURLProtocol.stub.requestCount(
      path: "/api/v1/recommend/tmdb_trending")
    XCTAssertEqual(initialRequestCount, 1)

    // 首次激活：只刷新来源，不额外重试
    await viewModel.refreshSources()
    let firstRequestCount = await SuccessEmptyURLProtocol.stub.requestCount(
      path: "/api/v1/recommend/tmdb_trending")
    XCTAssertEqual(firstRequestCount, 1)

    // 重新激活：成功空终态自动重试一次并恢复数据
    await viewModel.refreshSources()
    await waitUntil { viewModel.paginator?.items.count == 1 }
    XCTAssertEqual(viewModel.paginator?.items.first?.title, "回归片")
  }

  // MARK: 合集页：成功空后重新进入自动重试

  func testCollectionSuccessEmptyReloadsOnReentry() async throws {
    let service = APIService.isolatedTestingInstance()
    configureSuccessEmptySession(service)

    await SuccessEmptyURLProtocol.stub.setResponses(
      ["[]", mediaJSON(id: 21, title: "合集影片")],
      forPath: "/api/v1/tmdb/collection/912"
    )

    let viewModel = CollectionDetailViewModel(collectionId: 912, title: "测试合集", apiService: service)
    await viewModel.loadInitialData()
    await waitUntil { !viewModel.paginator.isLoading }
    XCTAssertTrue(viewModel.paginator.items.isEmpty)
    XCTAssertFalse(viewModel.paginator.hasMore)

    // 模拟重新进入页面：成功空终态自动重试
    await viewModel.loadInitialData()
    await waitUntil { viewModel.paginator.items.count == 1 }
    XCTAssertEqual(viewModel.paginator.items.first?.title, "合集影片")
  }

  // MARK: 详情页：推荐/相似/演员成功空后重新激活自动重试

  func testMediaDetailSuccessEmptySectionsReloadOnReactivation() async throws {
    let service = APIService.isolatedTestingInstance()
    configureSuccessEmptySession(service)

    await SuccessEmptyURLProtocol.stub.setResponses(
      ["[]", mediaJSON(id: 31, title: "推荐片")],
      forPath: "/api/v1/tmdb/recommend/603/电影"
    )
    await SuccessEmptyURLProtocol.stub.setResponses(
      ["[]", mediaJSON(id: 32, title: "相似片")],
      forPath: "/api/v1/tmdb/similar/603/电影"
    )
    await SuccessEmptyURLProtocol.stub.setResponses(
      ["[]", personJSON()],
      forPath: "/api/v1/tmdb/credits/603/电影"
    )

    let media = try decodeMedia(
      json: #"{"tmdb_id": 603, "source": "themoviedb", "title": "测试片", "type": "电影", "year": "2026", "poster_path": "/p.jpg", "popularity": 40}"#
    )
    let viewModel = MediaDetailViewModel(detail: media, apiService: service)
    viewModel.applyFullDetail(media)

    await waitUntil {
      !viewModel.recommendPaginator.isLoading && !viewModel.recommendPaginator.hasMore
        && !viewModel.similarPaginator.isLoading && !viewModel.similarPaginator.hasMore
        && !viewModel.actorsPaginator.isLoading && !viewModel.actorsPaginator.hasMore
    }
    XCTAssertTrue(viewModel.recommendPaginator.items.isEmpty)
    XCTAssertTrue(viewModel.similarPaginator.items.isEmpty)
    XCTAssertTrue(viewModel.actorsPaginator.items.isEmpty)

    // 重新激活：三个成功空区域各自动重试一次
    await viewModel.refreshSuccessEmptySections()
    await waitUntil {
      viewModel.recommendPaginator.items.count == 1
        && viewModel.similarPaginator.items.count == 1
        && viewModel.actorsPaginator.items.count == 1
    }
    XCTAssertEqual(viewModel.recommendPaginator.items.first?.title, "推荐片")
    XCTAssertEqual(viewModel.similarPaginator.items.first?.title, "相似片")
    XCTAssertEqual(viewModel.actorsPaginator.items.first?.name, "演员A")
  }
}
