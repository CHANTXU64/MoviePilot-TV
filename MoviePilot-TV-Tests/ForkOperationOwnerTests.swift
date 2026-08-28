import XCTest

@testable import MoviePilot_TV

/// F-193 回归：同一 profile 内 Fork POST→GET→编辑器呈现的 operation owner。
/// 覆盖：A 慢/B 快与 A 快/B 慢的交错（错误/呈现不串）、迟到失败不污染错误槽、
/// GET 单独失败后同一分享只重试 GET（POST 总数保持 1）、不同分享退休旧收据。
@MainActor
final class ForkOperationOwnerTests: XCTestCase {
  func testLateForkSuccessDoesNotReplaceNewerEditorInSameProfile() async throws {
    try await withForkOperationOwnerBackend { service in
      configureForkOwnerUser(service)
      let gateA = ForkOperationOwnerAsyncGate()
      await ForkOperationOwnerURLProtocol.stub.setForkResponses([
        .success(id: 7001, gate: gateA),
        .success(id: 7002, gate: nil),
      ])
      let handler = SubscriptionHandler(apiService: service)

      let lateFork = ForkOperationOwnerResultBox()
      Task {
        lateFork.value = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 88))
        lateFork.isSettled = true
      }
      try await forkOperationOwnerWaitUntil("第一个 Fork POST 到达并挂起") {
        await ForkOperationOwnerURLProtocol.stub.requestCount(
          method: "POST", path: "/api/v1/subscribe/fork") == 1
      }

      let secondId = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 99))
      XCTAssertEqual(secondId, 7002)
      await handler.fetchSubscriptionAndShowEditor(subId: 7002)
      XCTAssertEqual(handler.sheetSubscribe?.id, 7002)

      await gateA.open()
      try await forkOperationOwnerWaitUntil("慢的 A Fork 返回") { lateFork.isSettled }

      XCTAssertNil(lateFork.value, "晚到的 A 成功结果不得发布")
      XCTAssertEqual(handler.sheetSubscribe?.id, 7002, "A 晚到不得覆盖已呈现的 B 编辑器")
      let fetch7001 = await ForkOperationOwnerURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/subscribe/7001")
      let fetch7002 = await ForkOperationOwnerURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/subscribe/7002")
      XCTAssertEqual(fetch7001, 0)
      XCTAssertEqual(fetch7002, 1)
    }
  }

  func testLateForkFailureDoesNotPolluteNewerOperationErrorSlot() async throws {
    try await withForkOperationOwnerBackend { service in
      configureForkOwnerUser(service)
      let gateA = ForkOperationOwnerAsyncGate()
      await ForkOperationOwnerURLProtocol.stub.setForkResponses([
        .failure(gate: gateA),
        .success(id: 7002, gate: nil),
      ])
      let handler = SubscriptionHandler(apiService: service)

      let lateFork = ForkOperationOwnerResultBox()
      Task {
        lateFork.value = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 88))
        lateFork.isSettled = true
      }
      try await forkOperationOwnerWaitUntil("第一个 Fork POST 到达并挂起") {
        await ForkOperationOwnerURLProtocol.stub.requestCount(
          method: "POST", path: "/api/v1/subscribe/fork") == 1
      }

      let secondId = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 99))
      XCTAssertEqual(secondId, 7002)
      XCTAssertNil(handler.forkErrorMessage)

      await gateA.open()
      try await forkOperationOwnerWaitUntil("慢的 A Fork 失败返回") { lateFork.isSettled }

      XCTAssertNil(lateFork.value)
      XCTAssertNil(handler.forkErrorMessage, "A 晚到失败不得写入错误槽")
    }
  }

  func testForkGetFailureRetriesGetOnlyWithoutDuplicatePost() async throws {
    try await withForkOperationOwnerBackend { service in
      configureForkOwnerUser(service)
      await ForkOperationOwnerURLProtocol.stub.setForkResponses([
        .success(id: 7001, gate: nil),
        .success(id: 7002, gate: nil),
      ])
      let handler = SubscriptionHandler(apiService: service)
      let share = try ForkOperationOwnerFixtures.share(id: 88)

      let firstId = await handler.fork(share: share)
      XCTAssertEqual(firstId, 7001)

      // 编辑器 GET 失败：收据保留，通知一次。
      await ForkOperationOwnerURLProtocol.stub.setSubscribeFailure(id: 7001)
      await handler.fetchSubscriptionAndShowEditor(subId: 7001)
      XCTAssertNil(handler.sheetSubscribe)
      XCTAssertEqual(handler.notificationSerial, 1)

      // 同一分享再次点击：不再 POST，直接重试 GET。
      let retriedId = await handler.fork(share: share)
      XCTAssertEqual(retriedId, 7001)
      let postCountAfterRetry = await ForkOperationOwnerURLProtocol.stub.totalForkPostCount()
      XCTAssertEqual(postCountAfterRetry, 1, "GET-only 重试不得重复创建订阅")

      await ForkOperationOwnerURLProtocol.stub.clearSubscribeFailure()
      await handler.fetchSubscriptionAndShowEditor(subId: 7001)
      XCTAssertEqual(handler.sheetSubscribe?.id, 7001)

      // 编辑器成功打开后收据清除，再次点击同一分享是新的合法 Fork。
      let secondId = await handler.fork(share: share)
      XCTAssertEqual(secondId, 7002)
      let postCountAfterNewFork = await ForkOperationOwnerURLProtocol.stub.totalForkPostCount()
      XCTAssertEqual(postCountAfterNewFork, 2)
    }
  }

  func testDifferentShareRetiresPreviousReceiptWithoutRestartingOldGet() async throws {
    try await withForkOperationOwnerBackend { service in
      configureForkOwnerUser(service)
      await ForkOperationOwnerURLProtocol.stub.setForkResponses([
        .success(id: 7001, gate: nil),
        .success(id: 7002, gate: nil),
      ])
      let handler = SubscriptionHandler(apiService: service)

      let firstId = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 88))
      XCTAssertEqual(firstId, 7001)
      await ForkOperationOwnerURLProtocol.stub.setSubscribeFailure(id: 7001)
      await handler.fetchSubscriptionAndShowEditor(subId: 7001)
      XCTAssertNil(handler.sheetSubscribe)

      // 不同分享开始新操作：替换旧收据并重新 POST。
      let secondId = await handler.fork(share: try ForkOperationOwnerFixtures.share(id: 99))
      XCTAssertEqual(secondId, 7002)
      await handler.fetchSubscriptionAndShowEditor(subId: 7002)
      XCTAssertEqual(handler.sheetSubscribe?.id, 7002)

      let get7001 = await ForkOperationOwnerURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/subscribe/7001")
      XCTAssertEqual(get7001, 1, "A 的收据被新操作替换后不应再被恢复")
    }
  }
}

// MARK: - 测试基建

@MainActor
private func withForkOperationOwnerBackend(
  operation: (APIService) async throws -> Void
) async throws {
  XCTAssertTrue(APIService.installURLProtocolForTesting(ForkOperationOwnerURLProtocol.self))
  defer { APIService.removeURLProtocolForTesting(ForkOperationOwnerURLProtocol.self) }

  let service = APIService.isolatedTestingInstance()
  let snapshot = ForkOperationOwnerServiceSnapshot.capture(service: service)
  defer { snapshot.restore(to: service) }

  await ForkOperationOwnerURLProtocol.stub.reset()
  service.baseURLForTesting = "http://fork-owner-tests.local"
  try await operation(service)
}

@MainActor
private func configureForkOwnerUser(_ service: APIService) {
  service.tokenForTesting = "fork-owner-token"
  service.currentUserForTesting = Token(
    access_token: "fork-owner-token",
    token_type: "bearer",
    super_user: FlexibleBool(false),
    permissions: ["subscribe": true],
    user_id: 1,
    user_name: "fork-owner",
    avatar: nil
  )
}

@MainActor
private func forkOperationOwnerWaitUntil(
  _ description: String,
  timeout: TimeInterval = 2,
  condition: @escaping () async -> Bool
) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() {
      return
    }
    try await Task.sleep(nanoseconds: 20_000_000)
  }
  XCTFail("Timed out waiting for \(description)")
}

@MainActor
private final class ForkOperationOwnerResultBox {
  var isSettled = false
  var value: Int?
}

@MainActor
private struct ForkOperationOwnerServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?

  static func capture(service: APIService) -> ForkOperationOwnerServiceSnapshot {
    ForkOperationOwnerServiceSnapshot(
      baseURL: service.baseURLForTesting,
      token: service.tokenForTesting,
      currentUser: service.currentUserForTesting
    )
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.tokenForTesting = token
    service.currentUserForTesting = currentUser
  }
}

private enum ForkOperationOwnerFixtures {
  @MainActor
  static func share(id: Int) throws -> SubscribeShare {
    let data = Data(
      """
      {
        "id": \(id),
        "subscribe_id": \(id),
        "share_title": "分享\(id)",
        "share_user": "tester",
        "name": "分享\(id)",
        "year": "2026",
        "type": "电影",
        "tmdbid": \(id)
      }
      """.utf8
    )
    return try JSONDecoder().decode(SubscribeShare.self, from: data)
  }
}

private enum ForkOperationOwnerForkResponse {
  case success(id: Int, gate: ForkOperationOwnerAsyncGate?)
  case failure(gate: ForkOperationOwnerAsyncGate?)
}

/// 让某个请求挂起，测试显式放行以模拟慢/迟到响应。
actor ForkOperationOwnerAsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

private actor ForkOperationOwnerURLProtocolStub {
  private var requestCounts: [String: Int] = [:]
  private var forkQueue: [ForkOperationOwnerForkResponse] = []
  private var subscribeFailureIDs: Set<Int> = []

  func reset() {
    requestCounts.removeAll()
    forkQueue.removeAll()
    subscribeFailureIDs.removeAll()
  }

  func setForkResponses(_ responses: [ForkOperationOwnerForkResponse]) {
    forkQueue = responses
  }

  func setSubscribeFailure(id: Int) {
    subscribeFailureIDs.insert(id)
  }

  func clearSubscribeFailure() {
    subscribeFailureIDs.removeAll()
  }

  func requestCount(method: String, path: String) -> Int {
    requestCounts["\(method) \(path)", default: 0]
  }

  func totalForkPostCount() -> Int {
    requestCounts.reduce(into: 0) { count, entry in
      if entry.key.hasPrefix("POST /api/v1/subscribe/fork") {
        count += entry.value
      }
    }
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""
    requestCounts["\(method) \(path)", default: 0] += 1

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!

    switch (method, path) {
    case ("POST", "/api/v1/subscribe/fork"):
      let next: ForkOperationOwnerForkResponse =
        forkQueue.isEmpty ? .success(id: 7001, gate: nil) : forkQueue.removeFirst()
      switch next {
      case .success(let id, let gate):
        if let gate { await gate.wait() }
        return (
          response,
          Data(#"{"success":true,"data":{"id":\#(id)}}"#.utf8)
        )
      case .failure(let gate):
        if let gate { await gate.wait() }
        return (
          response,
          Data(#"{"success":false,"message":"数据库约束失败"}"#.utf8)
        )
      }
    case let (_, path) where path.hasPrefix("/api/v1/subscribe/"):
      let idString = String(path.dropFirst("/api/v1/subscribe/".count))
      let id = Int(idString) ?? 0
      if subscribeFailureIDs.contains(id) {
        let failure = HTTPURLResponse(
          url: request.url!,
          statusCode: 500,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (failure, Data())
      }
      return (
        response,
        Data(#"{"id":\#(id),"name":"订阅\#(id)","type":"电影","tmdbid":\#(id)}"#.utf8)
      )
    default:
      return (response, Data(#"[]"#.utf8))
    }
  }
}

private final class ForkOperationOwnerURLProtocol: URLProtocol {
  static let stub = ForkOperationOwnerURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "fork-owner-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = ForkOperationOwnerURLProtocolTaskContext(
      request: request,
      clientBox: ForkOperationOwnerURLProtocolClientBox(
        protocolInstance: self,
        client: client
      )
    )
    loadingTask = Self.makeLoadingTask(for: context)
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }

  private static func makeLoadingTask(for context: ForkOperationOwnerURLProtocolTaskContext)
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
}

private final class ForkOperationOwnerURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: ForkOperationOwnerURLProtocolClientBox

  init(request: URLRequest, clientBox: ForkOperationOwnerURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class ForkOperationOwnerURLProtocolClientBox: @unchecked Sendable {
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