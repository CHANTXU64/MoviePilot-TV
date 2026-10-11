import XCTest

@testable import MoviePilot_TV

final class SystemVersionInfoTests: XCTestCase {
  func testVersionInfoShowsMinimumAndLatestCompatibleVersions() {
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "v0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "   "), "未知")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: nil), "未知")
    XCTAssertEqual(AppVersionInfo.minimumCompatibleMoviePilotVersion, "v3.0.4")
    XCTAssertEqual(AppVersionInfo.latestCompatibleMoviePilotVersion, "v3.1.4")
  }

  func testProductionRegistryListsSourceReviewedVersions() {
    XCTAssertEqual(
      BackendCompatibilityRegistry.current.versions.map(\.description),
      [
        "v3.0.4", "v3.0.5", "v3.0.7", "v3.0.10", "v3.0.10-1", "v3.1.0", "v3.1.1", "v3.1.2", "v3.1.2-1",
        "v3.1.4",
      ]
    )
    for version in BackendCompatibilityRegistry.current.versions {
      XCTAssertNil(BackendVersionWarning(backendVersion: version.description), "\(version) 已登记，不应提示")
    }
    XCTAssertNil(BackendVersionWarning(backendVersion: " 3.0.10-1 \n"))
  }

  func testStableHotfixVersionIsPreservedAndOrdersAfterBaseRelease() throws {
    XCTAssertEqual(MoviePilotVersion(" V3.0.10-1 \n")?.description, "v3.0.10-1")
    XCTAssertEqual(MoviePilotVersion("3.0.10-1"), MoviePilotVersion("v3.0.10-1"))
    XCTAssertNotEqual(MoviePilotVersion("v3.0.10-1"), MoviePilotVersion("v3.0.10"))
    for (older, newer) in [
      ("v3.0.4", "v3.0.10"), ("v3.0.10", "v3.0.10-1"),
      ("v3.0.10-1", "v3.0.10-2"), ("v3.0.10-2", "v3.0.10-10"),
      ("v3.0.10-100", "v3.0.11"), ("v3.0.99-1", "v3.1.0"),
      ("v3.99.99-1", "v4.0.0"),
    ] {
      XCTAssertLessThan(try XCTUnwrap(MoviePilotVersion(older)), try XCTUnwrap(MoviePilotVersion(newer)))
    }
  }

  func testVersionParserRejectsUnrecognizedSuffixesAndMalformedNumbers() {
    let malformed: [String?] = [
      nil, "", "未知", "v3.0", "v3.0.10.1", "v3..10", "release-3.0.10",
      "v3.0.10-beta", "v3.0.10-rc.1", "v3.0.10+build.1", "v3.0.10-1+build",
      "v3.0.10 custom", "v3.0.10-", "v3.0.10-0", "v3.0.10-01", "v3.0.10--1",
      "v03.0.10", "v3.0.10-1-2", "v3.beta.10", "v 3.0.10", "+3.0.10",
      "v３.0.10", "v3.0.10-١", "v999999999999999999999.0.10", "v3.0.10-99999999999999999999",
    ]
    for version in malformed {
      XCTAssertNil(MoviePilotVersion(version), "Unexpected parsed version: \(version ?? "nil")")
      XCTAssertEqual(BackendCompatibilityRegistry.current.status(for: version), .unparseable)
    }
  }

  func testRegistryOnlyTreatsExactVersionsAsCompatible() {
    let registry = BackendCompatibilityRegistry.current
    let cases: [(String, BackendCompatibilityStatus)] = [
      ("v2.15.6", .belowMinimum), ("v3.0.3", .belowMinimum),
      ("v3.0.4", .registered), ("v3.0.4-1", .unregistered),
      ("v3.0.5", .registered), ("v3.0.6", .unregistered),
      ("v3.0.7", .registered), ("v3.0.8", .unregistered), ("v3.0.9", .unregistered),
      ("v3.0.10", .registered), ("3.0.10-1", .registered), ("v3.0.10-2", .unregistered),
      ("v3.0.11", .unregistered), ("v3.1.0", .registered),
      ("v3.1.0-1", .unregistered), ("v3.1.1", .registered),
      ("v3.1.1-1", .unregistered), ("v3.1.2", .registered),
      ("v3.1.2-1", .registered), ("3.1.2-1", .registered),
      ("v3.1.2-2", .unregistered), ("v3.1.3", .unregistered),
      ("v3.1.4", .registered), ("3.1.4", .registered),
      ("v3.1.4-1", .newerThanRegistry), ("v3.1.5", .newerThanRegistry),
      ("v4.0.0", .newerThanRegistry),
    ]
    for (version, status) in cases {
      XCTAssertEqual(registry.status(for: version), status, version)
    }
  }

  func testWarningsExplainEachReason() throws {
    let below = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.3"))
    XCTAssertEqual(below.title, "MoviePilot 后端版本过低")
    XCTAssertTrue(below.message.contains("当前后端版本：v3.0.3"))
    XCTAssertTrue(below.message.contains("最早兼容 v3.0.4"))

    let unregistered = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.8"))
    XCTAssertEqual(unregistered.title, "MoviePilot 后端版本尚未核对")
    XCTAssertTrue(
      unregistered.message.contains(
        "v3.0.4、v3.0.5、v3.0.7、v3.0.10、v3.0.10-1、v3.1.0、v3.1.1、v3.1.2、v3.1.2-1、v3.1.4"))

    let newer = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.1.4-1"))
    XCTAssertEqual(newer.title, "MoviePilot 后端版本较新")
    XCTAssertTrue(newer.message.contains("最新版本 v3.1.4"))

    let unparseable = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10-1-beta"))
    XCTAssertEqual(unparseable.title, "无法确认 MoviePilot 后端版本")
    XCTAssertTrue(unparseable.message.contains("当前后端版本：v3.0.10-1-beta"))
    XCTAssertTrue(unparseable.message.contains("无法识别该版本号"))
    let missing = try XCTUnwrap(BackendVersionWarning(backendVersion: nil))
    XCTAssertTrue(missing.message.contains("当前后端版本：无法确认"))
    XCTAssertTrue(missing.message.contains("未取得后端版本号"))

    for warning in [below, unregistered, newer, unparseable, missing] {
      XCTAssertTrue(warning.message.contains("仍可继续使用"))
      XCTAssertFalse(warning.message.contains("实测"))
    }
  }

  func testAcknowledgementIdentityOnlyDependsOnBackendVersion() throws {
    let small = BackendCompatibilityTestFixtures.registry()
    let grown = BackendCompatibilityTestFixtures.registry(extraVersions: ["v3.0.7", "v3.1.0"])
    let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.9", registry: small))
    // 新增其他兼容版本或修改提示文字，不能让同一后端版本的已确认提示重新出现。
    XCTAssertEqual(warning.id, BackendVersionWarning(backendVersion: "v3.0.9", registry: grown)?.id)
    XCTAssertEqual(warning.id, BackendVersionWarning(backendVersion: " 3.0.9 ", registry: small)?.id)
    XCTAssertNotEqual(warning.id, BackendVersionWarning(backendVersion: "v3.0.8", registry: small)?.id)
    XCTAssertEqual(
      BackendVersionWarning(backendVersion: "v3.0.10-1-beta", registry: small)?.id, "v3.0.10-1-beta")
    XCTAssertEqual(BackendVersionWarning(backendVersion: nil, registry: small)?.id, "unknown")
  }

  func testAppVersionComparisonAcceptsTwoComponentVersions() {
    XCTAssertEqual(AppVersionInfo.compareAppVersion("v0.9.9", to: "v1.0"), .orderedAscending)
    XCTAssertEqual(AppVersionInfo.compareAppVersion("1.0", to: "v1.0.0"), .orderedSame)
    XCTAssertEqual(AppVersionInfo.compareAppVersion("v1.0.1", to: "1.0"), .orderedDescending)
    XCTAssertEqual(AppVersionInfo.compareAppVersion("v0.3.10", to: "v0.3.9"), .orderedDescending)
    XCTAssertEqual(AppVersionInfo.compareAppVersion("v1.2.0-beta", to: "v1.2"), .orderedSame)
    XCTAssertNil(AppVersionInfo.compareAppVersion(nil, to: "v1.0"))
    XCTAssertNil(AppVersionInfo.compareAppVersion("未知", to: "v1.0"))
    XCTAssertNil(AppVersionInfo.compareAppVersion("v1.x", to: "v1.0"))
  }
}

/// 只用于提示生命周期测试，固定登记表，避免生产登记表增加版本后影响测试。
nonisolated enum BackendCompatibilityTestFixtures {
  static func registry(extraVersions: [String] = []) -> BackendCompatibilityRegistry {
    BackendCompatibilityRegistry(
      versions: (["v3.0.4", "v3.0.10-1"] + extraVersions).map { MoviePilotVersion($0)! }
    )
  }
}
