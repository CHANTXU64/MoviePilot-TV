import XCTest

@testable import MoviePilot_TV

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

  func testAutomaticLatencyMustBeBelowTenMilliseconds() {
    XCTAssertTrue(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.009_999))
    XCTAssertFalse(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.010))
    XCTAssertFalse(MemoryOptimizationPolicy.isAutomaticLatencyAcceptable(0.011))
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
}
