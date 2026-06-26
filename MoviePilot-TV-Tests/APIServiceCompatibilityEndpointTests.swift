import XCTest

@testable import MoviePilot_TV

@MainActor
final class APIServiceCompatibilityEndpointTests: XCTestCase {
  func testFetchSettingsReadsPublicBackendVersion() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = nil

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.FRONTEND_VERSION, "v2.13.15")
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/system/global" }, ["/api/v1/system/global"])
    let queries = await CompatibilityEndpointURLProtocol.stub.requestQueries()
    XCTAssertEqual(
      queries.compactMap { $0 }.filter { $0 == "token=moviepilot" },
      ["token=moviepilot"]
    )
  }

  func testFetchSettingsMergesLoggedInUserSettings() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.RECOGNIZE_SOURCE, "douban")
    XCTAssertEqual(settings.USER_UNIQUE_ID, "compat-user")
    XCTAssertEqual(settings.AI_AGENT_ENABLE?.value, true)
    XCTAssertEqual(settings.SUBSCRIBE_SHARE_MANAGE?.value, true)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user"],
      in: paths
    )
  }

  func testFetchSettingsKeepsPublicSettingsWhenLoggedInUserSettingsFails() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsFailure(statusCode: 404)
    let service = APIService.shared
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.FRONTEND_VERSION, "v2.13.15")
    XCTAssertNil(settings.AI_AGENT_ENABLE)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user"],
      in: paths
    )
  }

  func testSystemConfigReadersUsePublicSettingEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.shared
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"

    _ = try await service.fetchStorages()
    _ = try await service.fetchDirectories()
    _ = try await service.fetchIndexerSites()
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      [
        "/api/v1/system/setting/public/Storages",
        "/api/v1/system/setting/public/Directories",
        "/api/v1/system/setting/public/IndexerSites",
      ],
      in: paths
    )
  }

  private func assertContainsSubsequence(
    _ expected: [String],
    in actual: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var remaining = ArraySlice(expected)
    for path in actual where path == remaining.first {
      remaining.removeFirst()
      if remaining.isEmpty { return }
    }

    XCTFail(
      "Expected request paths to contain ordered subsequence \(expected), got \(actual)",
      file: file,
      line: line
    )
  }
}

@MainActor
private struct CompatibilityEndpointServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?

  static func capture(service: APIService) -> CompatibilityEndpointServiceSnapshot {
    CompatibilityEndpointServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    service.settings = settings
  }
}

private actor CompatibilityEndpointURLProtocolStub {
  private var requests: [URLRequest] = []
  private var userSettingsFailureStatusCode: Int?

  func reset() {
    requests.removeAll()
    userSettingsFailureStatusCode = nil
  }

  func setUserSettingsFailure(statusCode: Int?) {
    userSettingsFailureStatusCode = statusCode
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func requestQueries() -> [String?] {
    requests.map { $0.url?.query }
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let data: Data
    let statusCode: Int
    if url.path == "/api/v1/system/global" {
      statusCode = 200
      data =
        #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"v2.13.14","FRONTEND_VERSION":"v2.13.15"}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/system/global/user" {
      if let userSettingsFailureStatusCode {
        statusCode = userSettingsFailureStatusCode
        data = #"{"success":false,"message":"not found"}"#.data(using: .utf8)!
      } else {
        statusCode = 200
        data =
          #"{"success":true,"data":{"AI_AGENT_ENABLE":true,"RECOGNIZE_SOURCE":"douban","USER_UNIQUE_ID":"compat-user","SUBSCRIBE_SHARE_MANAGE":true}}"#
          .data(using: .utf8)!
      }
    } else {
      statusCode = 200
      data = #"{"success":true,"data":{"value":[]}}"#.data(using: .utf8)!
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class CompatibilityEndpointURLProtocol: URLProtocol {
  static let stub = CompatibilityEndpointURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "compatibility-endpoint-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = CompatibilityEndpointURLProtocolTaskContext(
      request: request,
      clientBox: CompatibilityEndpointURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = CompatibilityEndpointURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: CompatibilityEndpointURLProtocolTaskContext)
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

private final class CompatibilityEndpointURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: CompatibilityEndpointURLProtocolClientBox

  init(request: URLRequest, clientBox: CompatibilityEndpointURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class CompatibilityEndpointURLProtocolClientBox: @unchecked Sendable {
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
