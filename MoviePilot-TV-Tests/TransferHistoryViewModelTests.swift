import XCTest

@testable import MoviePilot_TV

private enum TransferHistoryViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor TransferHistoryAsyncGate {
  private var isOpen = false

  func wait() async {
    while !isOpen {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func open() {
    isOpen = true
  }
}

private func withTransferHistoryTimeout<T: Sendable>(
  _ description: String,
  seconds: TimeInterval = 2,
  operation: @escaping @Sendable () async -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw TransferHistoryViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

@MainActor
final class TransferHistoryViewModelTests: XCTestCase {
  func testPendingRefreshDoesNotPublishAfterPermissionIsRestricted() async throws {
    XCTAssertTrue(URLProtocol.registerClass(TransferHistoryURLProtocol.self))
    defer { URLProtocol.unregisterClass(TransferHistoryURLProtocol.self) }

    let service = APIService.shared
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let historyGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setHistoryGate(historyGate)

    service.baseURL = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel()
    let refreshTask = Task { @MainActor in
      await viewModel.refresh()
    }
    defer { refreshTask.cancel() }

    try await withTransferHistoryTimeout("history request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(path: "/api/v1/history/transfer")
    }

    configureRestrictedUser(service)
    await viewModel.refresh()

    XCTAssertTrue(viewModel.items.isEmpty)

    await historyGate.open()
    try await withTransferHistoryTimeout("old history refresh to finish") {
      await refreshTask.value
    }

    XCTAssertTrue(
      viewModel.items.isEmpty,
      "Late transfer-history responses must not repopulate state after the user loses manage access."
    )
  }

  func testManageUserCanRefreshTransferHistory() async throws {
    XCTAssertTrue(URLProtocol.registerClass(TransferHistoryURLProtocol.self))
    defer { URLProtocol.unregisterClass(TransferHistoryURLProtocol.self) }

    let service = APIService.shared
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()

    service.baseURL = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel()
    await viewModel.refresh()

    XCTAssertEqual(viewModel.items.map(\.id), [10])
    XCTAssertEqual(viewModel.storageDict["local"], "本地")
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/history/transfer"))
    XCTAssertTrue(paths.contains("/api/v1/system/setting/public/Storages"))
  }

  private func configureManageUser(_ service: APIService) {
    service.currentUser = Token(
      access_token: "transfer-history-manager-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "transfer-manager",
      avatar: nil
    )
  }

  private func configureRestrictedUser(_ service: APIService) {
    service.currentUser = Token(
      access_token: "transfer-history-restricted-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "transfer-restricted",
      avatar: nil
    )
  }
}

@MainActor
private struct TransferHistoryServiceSnapshot {
  let baseURL: String
  let currentUser: Token?
  let serverURLDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  static func capture(service: APIService) -> TransferHistoryServiceSnapshot {
    TransferHistoryServiceSnapshot(
      baseURL: service.baseURL,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.currentUser = currentUser

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }

    if let currentUserKeychain {
      _ = KeychainHelper.shared.save(
        currentUserKeychain,
        service: "MoviePilot-TV",
        account: "currentUser"
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "currentUser")
    }

    if let currentUserDefaults {
      UserDefaults.standard.set(currentUserDefaults, forKey: "currentUser")
    } else {
      UserDefaults.standard.removeObject(forKey: "currentUser")
    }
  }
}

private struct TransferHistoryHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: TransferHistoryAsyncGate?
}

private actor TransferHistoryURLProtocolStub {
  private var paths: [String] = []
  private var historyGate: TransferHistoryAsyncGate?

  func reset() {
    paths.removeAll()
    historyGate = nil
  }

  func setHistoryGate(_ gate: TransferHistoryAsyncGate?) {
    historyGate = gate
  }

  func response(for request: URLRequest) async throws -> TransferHistoryHTTPStubResponse {
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    paths.append(url.path)

    switch url.path {
    case "/api/v1/system/setting/public/Storages":
      return TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(#"{"value":[{"name":"本地","type":"local"}]}"#.utf8),
        gate: nil
      )
    case "/api/v1/history/transfer":
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(
          #"{"list":[{"id":10,"title":"Late History","type":"电影","status":true}],"total":1}"#
            .utf8
        ),
        gate: historyGate
      )
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    default:
      throw URLError(.unsupportedURL)
    }
  }

  func waitForRequest(path: String) async {
    while !paths.contains(path) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func requestPaths() -> [String] {
    paths
  }
}

private final class TransferHistoryURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = TransferHistoryURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "transfer-history-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = TransferHistoryURLProtocolTaskContext(
      request: request,
      clientBox: TransferHistoryURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = TransferHistoryURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: TransferHistoryURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await TransferHistoryURLProtocol.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
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

private final class TransferHistoryURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: TransferHistoryURLProtocolClientBox

  init(request: URLRequest, clientBox: TransferHistoryURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class TransferHistoryURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: TransferHistoryHTTPStubResponse) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      fail(URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: stubResponse.data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
