import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class SSEStreamTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SSEStreamURLProtocol.self))
    SSEStreamURLProtocol.cancellation.reset()
    SSEStreamURLProtocol.requestCounts.reset()
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(SSEStreamURLProtocol.self)
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://sse-stream-tests.local"
    service.tokenForTesting = "sse-test-token"
    return service
  }

  func testBufferedStreamDoesNotPayMainActorSchedulingCostPerByte() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SSEStreamURLProtocol.self]
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    let url = try XCTUnwrap(URL(string: "https://sse-stream-tests.local/?keyword=buffered"))

    // 同一份已缓冲数据，用逐行解码校准机器负载；生产 API 仍须保留多行事件支持。
    let baselineStart = ContinuousClock.now
    let (bytes, _) = try await transport.bytes(from: url)
    var baselineCount = 0
    for try await line in bytes.lines where line.hasPrefix("data:") {
      _ = try JSONDecoder().decode(
        SearchStreamEvent.self, from: Data(line.dropFirst(5).utf8))
      baselineCount += 1
    }
    let baselineDuration = baselineStart.duration(to: .now)

    let service = makeService()
    let start = ContinuousClock.now
    var eventCount = 0
    for try await _ in service.searchTitleStream(keyword: "buffered", sites: nil) {
      eventCount += 1
    }
    let duration = start.duration(to: .now)
    XCTAssertEqual(baselineCount, 512)
    XCTAssertEqual(eventCount, 512)
    // 预留 20 倍相对预算和 1 秒绝对余量；回归版本在此约需 11 秒。
    XCTAssertLessThan(duration, max(.seconds(1), baselineDuration * 20))
    print("SSE throughput: baseline=\(baselineDuration), production=\(duration), events=\(eventCount)")
  }

  func testProductionStreamPreservesMultilineBOMAndUnterminatedTail() async throws {
    let service = makeService()
    var texts: [String] = []
    for try await event in service.searchTitleStream(keyword: "framing", sites: nil) {
      if let text = event.text { texts.append(text) }
    }
    XCTAssertEqual(texts, ["中文", "tail"])
    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "framing"), 1)
  }

  func testProgressStreamReconnectsAfterUnexpectedEOF() async throws {
    let service = makeService()
    var events: [SearchStreamEvent] = []

    do {
      for try await event in service.progressStream(progressKey: "progress-reconnect") {
        events.append(event)
      }
    } catch {
      XCTFail("进度 SSE 在可重连的 EOF 后不应失败：\(error)")
    }

    XCTAssertEqual(events.compactMap(\.text), ["first", "finished"])
    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "progress-reconnect"), 2)
  }

  func testProgressStreamSendsSessionResourceCookie() async throws {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    let savedServerURL = "https://user-server.local/mp"
    UserDefaults.standard.set(savedServerURL, forKey: "serverURL")
    let service = APIService.isolatedTestingInstance()
    let cookie = try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: "sse-stream-tests.local",
        .path: "/api/v1",
        .name: "resource_token",
        .value: "progress-resource-cookie",
        .secure: "TRUE",
      ])
    )
    service.replaceSessionForTesting(
      baseURL: "https://sse-stream-tests.local",
      token: "sse-test-token",
      currentUser: nil,
      cookies: [cookie]
    )
    XCTAssertEqual(UserDefaults.standard.string(forKey: "serverURL"), savedServerURL)

    var events: [SearchStreamEvent] = []
    for try await event in service.progressStream(progressKey: "progress-cookie") {
      events.append(event)
    }

    XCTAssertEqual(events.compactMap(\.text), ["cookie-authorized"])
    XCTAssertEqual(
      SSEStreamURLProtocol.cookieHeader(for: "progress-cookie"),
      "resource_token=progress-resource-cookie"
    )
  }

  func testProgressStreamReconnectsAfterTransportFailure() async throws {
    let service = makeService()
    var events: [SearchStreamEvent] = []

    do {
      for try await event in service.progressStream(progressKey: "progress-retry-error") {
        events.append(event)
      }
    } catch {
      XCTFail("进度 SSE 在临时网络断开后不应失败：\(error)")
    }

    XCTAssertEqual(events.compactMap(\.text).last, "finished")
    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "progress-retry-error"), 2)
  }

  func testProgressStreamStopsAfterFiveReconnects() async throws {
    let service = makeService()
    var eventCount = 0

    do {
      for try await _ in service.progressStream(progressKey: "progress-always-fails") {
        eventCount += 1
      }
    } catch {
      XCTFail("达到重连上限后应正常结束进度流：\(error)")
    }

    XCTAssertEqual(eventCount, 0)
    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "progress-always-fails"), 6)
  }

  func testProgressStreamCancellationDoesNotReconnect() async throws {
    let service = makeService()
    let reader = Task { @MainActor in
      do {
        for try await _ in service.progressStream(progressKey: "hold-progress") {}
      } catch {}
    }
    defer { reader.cancel() }

    try await waitUntil {
      SSEStreamURLProtocol.requestCount(for: "hold-progress") == 1
    }

    reader.cancel()
    try await waitUntil {
      SSEStreamURLProtocol.cancellation.wasStopped
    }

    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "hold-progress"), 1)
  }

  func testProgressStreamSessionSwitchDoesNotReconnect() async throws {
    let service = makeService()
    let reader = Task { @MainActor in
      do {
        for try await _ in service.progressStream(progressKey: "hold-progress") {}
      } catch {}
    }
    defer { reader.cancel() }

    try await waitUntil {
      SSEStreamURLProtocol.requestCount(for: "hold-progress") == 1
    }

    service.baseURLForTesting = "https://sse-next-session.local"
    try await waitUntil {
      SSEStreamURLProtocol.cancellation.wasStopped
    }

    XCTAssertEqual(SSEStreamURLProtocol.requestCount(for: "hold-progress"), 1)
  }

  func testConsumerCancellationStopsTransport() async throws {
    try await assertInterruptedStream(switchSession: false)
  }

  func testSessionSwitchStopsOldStream() async throws {
    try await assertInterruptedStream(switchSession: true)
  }

  private func assertInterruptedStream(switchSession: Bool) async throws {
    let service = makeService()
    var texts: [String] = []
    var finished = false
    var caughtCancellation = false
    let reader = Task {
      defer { finished = true }
      do {
        for try await event in service.searchTitleStream(keyword: "hold", sites: nil) {
          if let text = event.text { texts.append(text) }
        }
      } catch is CancellationError {
        caughtCancellation = true
      } catch {
        XCTFail("Unexpected stream error: \(error)")
      }
    }
    defer { reader.cancel() }

    try await waitUntil { texts == ["first"] }
    if switchSession {
      service.baseURLForTesting = "https://sse-next-session.local"
    } else {
      reader.cancel()
    }
    try await waitUntil { finished && SSEStreamURLProtocol.cancellation.wasStopped }
    XCTAssertEqual(texts, ["first"])
    if switchSession { XCTAssertTrue(caughtCancellation) }
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !condition() {
      guard ContinuousClock.now < deadline else {
        XCTFail("Stream lifecycle did not complete within 3 seconds")
        throw URLError(.timedOut)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private final class SSEStreamCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  var wasStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    stopped = false
  }

  func markStopped() {
    lock.lock()
    defer { lock.unlock() }
    stopped = true
  }
}

private final class SSEStreamURLProtocol: URLProtocol {
  static let cancellation = SSEStreamCancellation()
  static let requestCounts = SSEStreamRequestCounts()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let scenario = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "keyword" }?.value
      ?? request.url?.path.split(separator: "/").last.map(String.init)
    let body: String
    var shouldFail = false
    let attempt = Self.requestCounts.record(
      for: scenario,
      cookieHeader: request.value(forHTTPHeaderField: "Cookie")
    )
    switch scenario {
    case "buffered":
      let line = "data: {\"type\":\"append\",\"text\":\"" + String(repeating: "x", count: 1024) + "\"}\n\n"
      body = String(repeating: line, count: 512)
    case "framing":
      body = "\u{FEFF}data: {\"type\":\"append\",\r\ndata: \"text\":\"中文\"}\r\n\r\ndata: {\"type\":\"done\",\"text\":\"tail\"}"
    case "progress-reconnect":
      body = attempt == 1
        ? "data: {\"type\":\"append\",\"text\":\"first\"}\n\n"
        : "data: {\"type\":\"done\",\"enable\":false,\"text\":\"finished\"}\n\n"
    case "progress-retry-error":
      if attempt == 1 {
        body = "data: {\"type\":\"append\",\"text\":\"first\"}\n\n"
        shouldFail = true
      } else {
        body = "data: {\"type\":\"done\",\"enable\":false,\"text\":\"finished\"}\n\n"
      }
    case "progress-always-fails":
      body = ""
      shouldFail = true
    case "progress-cookie":
      body =
        "data: {\"enable\":false,\"text\":\"cookie-authorized\",\"data\":{\"success\":true}}\n\n"
    default:
      body = "data: {\"type\":\"append\",\"text\":\"first\"}\n\n"
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "text/event-stream"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    if shouldFail {
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    } else if scenario != "hold" && scenario != "hold-progress" {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {
    let scenario = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "keyword" }?.value
      ?? request.url?.path.split(separator: "/").last.map(String.init)
    if scenario == "hold" || scenario == "hold-progress" {
      Self.cancellation.markStopped()
    }
  }

  static func requestCount(for scenario: String) -> Int {
    requestCounts.count(for: scenario)
  }

  static func cookieHeader(for scenario: String) -> String? {
    requestCounts.cookieHeader(for: scenario)
  }
}

private final class SSEStreamRequestCounts: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]
  private var cookieHeaders: [String: String] = [:]

  func reset() {
    lock.lock()
    counts.removeAll()
    cookieHeaders.removeAll()
    lock.unlock()
  }

  func record(for scenario: String?, cookieHeader: String?) -> Int {
    guard let scenario else { return 0 }
    lock.lock()
    defer { lock.unlock() }
    if let cookieHeader {
      cookieHeaders[scenario] = cookieHeader
    }
    let next = (counts[scenario] ?? 0) + 1
    counts[scenario] = next
    return next
  }

  func count(for scenario: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return counts[scenario] ?? 0
  }

  func cookieHeader(for scenario: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return cookieHeaders[scenario]
  }
}
