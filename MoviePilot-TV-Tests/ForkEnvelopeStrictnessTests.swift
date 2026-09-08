import XCTest

@testable import MoviePilot_TV

/// F-245 回归：Fork 响应解码必须失败关闭（fail-closed）。
/// 与 decodeStrictActionResponseSync 的 `success ?? false`、Web 端
/// ForkSubscribeDialog `if (result.success)` 对齐：只有显式 `success == true`
/// 且 `data.id > 0` 才算成功；`success` 缺失/null/false、ID 缺失/0/负数一律抛错，
/// 不再把含糊 2xx 当成"已创建订阅"继续走 GET→编辑器链。
@MainActor
final class ForkEnvelopeStrictnessTests: XCTestCase {
  func testForkEnvelopeMatrix() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ForkEnvelopeURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ForkEnvelopeURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = ForkEnvelopeServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://fork-envelope-f245.local"
    service.tokenForTesting = "fork-envelope-token"
    service.currentUserForTesting = Token(
      access_token: "fork-envelope-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["subscribe": true],
      user_id: 1,
      user_name: "fork-envelope",
      avatar: nil
    )

    let share = try ForkEnvelopeFixtures.share(id: 88)

    // 1) 规范成功：success == true 且正 ID → 原样返回 ID。
    let success = await tryFork(
      service, share: share,
      envelope: #"{"success":true,"data":{"id":7001}}"#
    )
    XCTAssertEqual(success.id, 7001)
    XCTAssertNil(success.error)

    // 以下全部必须失败关闭：
    // 2) success 缺失（历史后端/插件可能不发 success）→ 抛"复用订阅失败"。
    let missingSuccess = await tryFork(
      service, share: share,
      envelope: #"{"data":{"id":7001}}"#
    )
    assertServerMessage(missingSuccess.error, equals: "复用订阅失败", for: "success 缺失")

    // 3) success == null → 抛"复用订阅失败"。
    let nullSuccess = await tryFork(
      service, share: share,
      envelope: #"{"success":null,"data":{"id":7001}}"#
    )
    assertServerMessage(nullSuccess.error, equals: "复用订阅失败", for: "success 为 null")

    // 4) success == false → 透传服务端文案。
    let falseSuccess = await tryFork(
      service, share: share,
      envelope: #"{"success":false,"message":"数据库约束失败"}"#
    )
    assertServerMessage(falseSuccess.error, equals: "数据库约束失败", for: "success 为 false")

    // 5) success == false 但 data.id 却是正的（自相矛盾）→ 以 success 为准，失败。
    let contradictory = await tryFork(
      service, share: share,
      envelope: #"{"success":false,"data":{"id":7001}}"#
    )
    assertServerMessage(contradictory.error, equals: "复用订阅失败", for: "success=false 却带正 ID")

    // 6) success == true 但 data 缺 id → 抛"缺少 ID"。
    let noId = await tryFork(
      service, share: share,
      envelope: #"{"success":true,"data":{}}"#
    )
    assertServerMessage(noId.error, equals: "复用订阅响应缺少 ID", for: "缺 id")

    // 7) success == true 但 data 为 null → 抛"缺少 ID"。
    let nullData = await tryFork(
      service, share: share,
      envelope: #"{"success":true,"data":null}"#
    )
    assertServerMessage(nullData.error, equals: "复用订阅响应缺少 ID", for: "data 为 null")

    // 8) success == true 但 id == 0（后端从未落库成功）→ 抛"缺少 ID"。
    let zeroId = await tryFork(
      service, share: share,
      envelope: #"{"success":true,"data":{"id":0}}"#
    )
    assertServerMessage(zeroId.error, equals: "复用订阅响应缺少 ID", for: "id 为 0")

    // 9) success == true 但 id < 0 → 抛"缺少 ID"。
    let negativeId = await tryFork(
      service, share: share,
      envelope: #"{"success":true,"data":{"id":-3}}"#
    )
    assertServerMessage(negativeId.error, equals: "复用订阅响应缺少 ID", for: "id 为负数")

    // 10) 空对象：success 与 data 全缺 → 抛"复用订阅失败"。
    let empty = await tryFork(service, share: share, envelope: #"{}"#)
    assertServerMessage(empty.error, equals: "复用订阅失败", for: "空响应")

    // 只有成功路径返回；全部失败路径都应已把响应当作失败，无一次返回。
    XCTAssertEqual(success.id, 7001)
  }

  // MARK: - 断言与工具

  @MainActor
  private func tryFork(
    _ service: APIService,
    share: SubscribeShare,
    envelope: String
  ) async -> (id: Int?, error: Error?) {
    await ForkEnvelopeURLProtocol.stub.setBody(envelope)
    do {
      let id = try await service.forkSubscription(share: share)
      return (id, nil)
    } catch {
      return (nil, error)
    }
  }

  private func assertServerMessage(
    _ error: Error?,
    equals expected: String,
    for label: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let error else {
      XCTFail("\(label)：应失败关闭抛错，却成功返回", file: file, line: line)
      return
    }
    guard let apiError = error as? APIError else {
      XCTFail("\(label)：应抛 APIError，实际 \(error)", file: file, line: line)
      return
    }
    guard case .serverMessage(let message) = apiError else {
      XCTFail("\(label)：应抛 serverMessage，实际 \(apiError)", file: file, line: line)
      return
    }
    XCTAssertEqual(message, expected, "\(label)：服务端文案透传不符", file: file, line: line)
  }
}

// MARK: - 测试基建

private enum ForkEnvelopeFixtures {
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

private actor ForkEnvelopeURLProtocolStub {
  private var body = #"{"success":true,"data":{"id":7001}}"#

  func setBody(_ body: String) {
    self.body = body
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
  }
}

private final class ForkEnvelopeURLProtocol: URLProtocol {
  static let stub = ForkEnvelopeURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "fork-envelope-f245.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = ForkEnvelopeURLProtocolTaskContext(
      request: request,
      clientBox: ForkEnvelopeURLProtocolClientBox(
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

  private static func makeLoadingTask(for context: ForkEnvelopeURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let result = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: result.0, data: result.1)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }
}

private final class ForkEnvelopeURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: ForkEnvelopeURLProtocolClientBox

  init(request: URLRequest, clientBox: ForkEnvelopeURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class ForkEnvelopeURLProtocolClientBox: @unchecked Sendable {
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

@MainActor
private struct ForkEnvelopeServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?

  static func capture(service: APIService) -> ForkEnvelopeServiceSnapshot {
    ForkEnvelopeServiceSnapshot(
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
