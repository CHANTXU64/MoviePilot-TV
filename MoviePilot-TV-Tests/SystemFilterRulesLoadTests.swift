import XCTest

@testable import MoviePilot_TV

@MainActor
final class SystemFilterRulesLoadTests: XCTestCase {
  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemFilterRulesURLProtocol.self))
    SystemFilterRulesURLProtocol.stub.reset()
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(SystemFilterRulesURLProtocol.self)
    SystemFilterRulesURLProtocol.stub.reset()
    super.tearDown()
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://filter-rules-tests.local"
    service.tokenForTesting = "rules-token"
    service.currentUserForTesting = Token(
      access_token: "rules-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "rules-admin",
      avatar: nil
    )
    return service
  }

  func testRulesFailureSetsLoadFailedAndKeepsPreviousRules() async throws {
    let service = makeService()
    let viewModel = SystemViewModel(apiService: service)

    SystemFilterRulesURLProtocol.stub.setResult(
      #"{"value":[{"id":"hard-1","name":"硬规则A"}]}"#
    )
    await viewModel.loadCustomFilterRules()
    XCTAssertFalse(viewModel.rulesLoadFailed)
    XCTAssertEqual(viewModel.customFilterRules.map(\.id), ["hard-1"])

    SystemFilterRulesURLProtocol.stub.setResult(.httpStatus500)
    await viewModel.loadCustomFilterRules()

    XCTAssertTrue(viewModel.rulesLoadFailed)
    XCTAssertEqual(viewModel.customFilterRules.map(\.id), ["hard-1"])
  }

  func testRulesSuccessClearsLoadFailedFlag() async throws {
    let service = makeService()
    let viewModel = SystemViewModel(apiService: service)

    SystemFilterRulesURLProtocol.stub.setResult(.httpStatus500)
    await viewModel.loadCustomFilterRules()
    XCTAssertTrue(viewModel.rulesLoadFailed)

    SystemFilterRulesURLProtocol.stub.setResult(#"{"value":[]}"#)
    await viewModel.loadCustomFilterRules()

    XCTAssertFalse(viewModel.rulesLoadFailed)
    XCTAssertTrue(viewModel.customFilterRules.isEmpty)
  }

  func testRulesCancellationKeepsPreviousRulesAndFlag() async throws {
    let service = makeService()
    let viewModel = SystemViewModel(apiService: service)

    SystemFilterRulesURLProtocol.stub.setResult(
      #"{"value":[{"id":"soft-1","name":"软规则B"}]}"#
    )
    await viewModel.loadCustomFilterRules()
    XCTAssertFalse(viewModel.rulesLoadFailed)

    SystemFilterRulesURLProtocol.stub.setResult(.cancelled)
    await viewModel.loadCustomFilterRules()

    XCTAssertFalse(viewModel.rulesLoadFailed)
    XCTAssertEqual(viewModel.customFilterRules.map(\.id), ["soft-1"])
  }
}

private enum SystemFilterRulesStubResult {
  case json(String)
  case httpStatus500
  case cancelled
}

private final class SystemFilterRulesURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var result: SystemFilterRulesStubResult = .json(#"{"value":[]}"#)

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    result = .json(#"{"value":[]}"#)
  }

  func setResult(_ result: SystemFilterRulesStubResult) {
    lock.lock()
    defer { lock.unlock() }
    self.result = result
  }

  func setResult(_ json: String) {
    setResult(.json(json))
  }

  func resultValue() -> SystemFilterRulesStubResult {
    lock.lock()
    defer { lock.unlock() }
    return result
  }
}

private final class SystemFilterRulesURLProtocol: URLProtocol {
  static let stub = SystemFilterRulesURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "filter-rules-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    switch url.path {
    case "/api/v1/system/setting/CustomFilterRules":
      switch Self.stub.resultValue() {
      case .json(let body):
        respond(statusCode: 200, body: body)
      case .httpStatus500:
        respond(statusCode: 500, body: #"{"message":"server unavailable"}"#)
      case .cancelled:
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
      }
    default:
      respond(statusCode: 200, body: "[]")
    }
  }

  override func stopLoading() {}

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
