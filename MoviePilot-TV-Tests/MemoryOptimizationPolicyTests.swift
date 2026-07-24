import XCTest

@testable import MoviePilot_TV

@MainActor
final class MemoryOptimizationPolicyTests: XCTestCase {
  func testRecognizesLocalAndPublicAddresses() {
    let localAddresses = [
      "10.0.0.1",
      "100.64.0.1",
      "127.0.0.1",
      "169.254.1.1",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.1.1",
      "::1",
      "fc00::1",
      "fd12:3456::1",
      "fe80::1%en0",
      "::ffff:192.168.1.1",
    ]
    let publicAddresses = [
      "8.8.8.8",
      "100.128.0.1",
      "172.32.0.1",
      "192.169.0.1",
      "2001:4860:4860::8888",
    ]

    for address in localAddresses {
      XCTAssertTrue(MemoryOptimizationPolicy.isLocalAddress(address), address)
    }
    for address in publicAddresses {
      XCTAssertFalse(MemoryOptimizationPolicy.isLocalAddress(address), address)
    }
  }

  func testAutomaticLatencyMustBeBelowThirtyMilliseconds() {
    XCTAssertTrue(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.029_999))
    XCTAssertFalse(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.030))
    XCTAssertFalse(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.031))
  }

  func testOnlyLatestAutomaticEvaluationCanPublish() {
    XCTAssertTrue(
      MemoryOptimizationPolicy.canPublishAutomaticResult(
        mode: .automatic,
        generation: 2,
        currentGeneration: 2,
        sessionIsCurrent: true
      )
    )
    XCTAssertFalse(
      MemoryOptimizationPolicy.canPublishAutomaticResult(
        mode: .automatic,
        generation: 1,
        currentGeneration: 2,
        sessionIsCurrent: true
      )
    )
    XCTAssertFalse(
      MemoryOptimizationPolicy.canPublishAutomaticResult(
        mode: .automatic,
        generation: 2,
        currentGeneration: 2,
        sessionIsCurrent: false
      )
    )
  }

  func testModeResolvesFinalEnabledState() {
    XCTAssertTrue(
      MemoryOptimizationPolicy.resolvedEnabledState(mode: .automatic, automaticEnabled: true)
    )
    XCTAssertFalse(
      MemoryOptimizationPolicy.resolvedEnabledState(mode: .automatic, automaticEnabled: false)
    )
    XCTAssertTrue(
      MemoryOptimizationPolicy.resolvedEnabledState(mode: .enabled, automaticEnabled: false)
    )
    XCTAssertFalse(
      MemoryOptimizationPolicy.resolvedEnabledState(mode: .disabled, automaticEnabled: true)
    )
  }

  func testOlderEvaluationCannotOverwriteNewSession() async throws {
    let firstSession = session("http://192.168.1.10:3000", token: "first")
    let secondSession = session("http://192.168.1.20:3000", token: "second")
    var currentSession = firstSession
    let probe = ControlledMemoryOptimizationProbe()
    let policy = MemoryOptimizationPolicy(
      testingMode: .automatic,
      latencyProbe: { await probe.call(baseURL: $0) },
      sessionIsCurrent: { $0 == currentSession }
    )

    policy.evaluateAutomatically(
      sessionSnapshot: firstSession,
      settingsLoaded: true,
      imageCacheAvailable: true
    )
    try await waitUntil("第一轮探测未开始") {
      await probe.pendingCount(baseURL: firstSession.baseURL) == 1
    }

    currentSession = secondSession
    policy.evaluateAutomatically(
      sessionSnapshot: secondSession,
      settingsLoaded: true,
      imageCacheAvailable: true
    )
    for _ in 0..<3 {
      try await waitUntil("第二轮探测未继续") {
        await probe.pendingCount(baseURL: secondSession.baseURL) == 1
      }
      await probe.resumeNext(
        baseURL: secondSession.baseURL,
        result: (0.005, "192.168.1.20")
      )
    }
    try await waitUntil("第二轮结果未发布") {
      policy.automaticEnabled
    }

    await probe.resumeNext(
      baseURL: firstSession.baseURL,
      result: (0.050, "8.8.8.8")
    )
    await Task.yield()

    XCTAssertTrue(policy.automaticEnabled)
    XCTAssertTrue(policy.isEnabled)
  }

  func testInvalidationDisablesOldDecisionAndAllowsOneFailedProbe() async throws {
    let currentSession = session("http://192.168.1.30:3000", token: "current")
    let probe = MemoryOptimizationProbeSequence([
      nil,
      (0.040, "192.168.1.30"),
      (0.029, "192.168.1.30"),
    ])
    let policy = MemoryOptimizationPolicy(
      testingMode: .disabled,
      automaticEnabled: true,
      latencyProbe: { _ in await probe.next() },
      sessionIsCurrent: { $0 == currentSession }
    )

    policy.mode = .automatic
    XCTAssertFalse(policy.automaticEnabled)
    XCTAssertFalse(policy.isEnabled)

    policy.invalidateAutomaticDecision()
    XCTAssertFalse(policy.automaticEnabled)
    XCTAssertFalse(policy.isEnabled)

    policy.evaluateAutomatically(
      sessionSnapshot: currentSession,
      settingsLoaded: true,
      imageCacheAvailable: true
    )
    try await waitUntil("两个有效探测结果未启用自动优化") {
      policy.automaticEnabled
    }

    XCTAssertTrue(policy.isEnabled)
  }

  private func session(_ baseURL: String, token: String) -> APIServiceSessionSnapshot {
    APIServiceSessionSnapshot(
      baseURL: baseURL,
      token: token,
      userName: "tester",
      superUser: false,
      permissions: ["discovery": true]
    )
  }

  private func waitUntil(
    _ failureMessage: String,
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail(failureMessage)
  }
}

private actor ControlledMemoryOptimizationProbe {
  typealias Result = (latency: TimeInterval, remoteAddress: String)

  private var continuations: [String: [CheckedContinuation<Result?, Never>]] = [:]

  func call(baseURL: String) async -> Result? {
    await withCheckedContinuation { continuation in
      continuations[baseURL, default: []].append(continuation)
    }
  }

  func pendingCount(baseURL: String) -> Int {
    continuations[baseURL]?.count ?? 0
  }

  func resumeNext(baseURL: String, result: Result?) {
    guard var pending = continuations[baseURL], !pending.isEmpty else { return }
    let continuation = pending.removeFirst()
    continuations[baseURL] = pending
    continuation.resume(returning: result)
  }
}

private actor MemoryOptimizationProbeSequence {
  typealias Result = (latency: TimeInterval, remoteAddress: String)

  private var results: [Result?]

  init(_ results: [Result?]) {
    self.results = results
  }

  func next() -> Result? {
    results.isEmpty ? nil : results.removeFirst()
  }
}
