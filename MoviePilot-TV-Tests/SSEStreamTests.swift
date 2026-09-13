import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class SSEStreamTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SSEStreamURLProtocol.self))
    SSEStreamURLProtocol.cancellation.reset()
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

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let keyword = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "keyword" }?.value
    let body: String
    switch keyword {
    case "buffered":
      let line = "data: {\"type\":\"append\",\"text\":\"" + String(repeating: "x", count: 1024) + "\"}\n\n"
      body = String(repeating: line, count: 512)
    case "framing":
      body = "\u{FEFF}data: {\"type\":\"append\",\r\ndata: \"text\":\"中文\"}\r\n\r\ndata: {\"type\":\"done\",\"text\":\"tail\"}"
    default:
      body = "data: {\"type\":\"append\",\"text\":\"first\"}\n\n"
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "text/event-stream"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    if keyword != "hold" { client?.urlProtocolDidFinishLoading(self) }
  }

  override func stopLoading() {
    let keyword = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "keyword" }?.value
    if keyword == "hold" { Self.cancellation.markStopped() }
  }
}
