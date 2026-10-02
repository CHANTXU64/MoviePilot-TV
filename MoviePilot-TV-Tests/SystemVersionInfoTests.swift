import XCTest

@testable import MoviePilot_TV

final class SystemVersionInfoTests: XCTestCase {
  func testVersionInfoSeparatesMaintenanceFloorFromLatestRecord() {
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "v0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "   "), "未知")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: nil), "未知")
    XCTAssertEqual(AppVersionInfo.minimumMaintainedMoviePilotVersion, "v3.0.4")
    XCTAssertEqual(AppVersionInfo.latestRegisteredMoviePilotVersion, "v3.1.0")
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
      XCTAssertEqual(AppVersionInfo.compareMoviePilotVersion(older, to: newer), .orderedAscending)
      XCTAssertEqual(AppVersionInfo.compareMoviePilotVersion(newer, to: older), .orderedDescending)
    }
    XCTAssertEqual(AppVersionInfo.compareMoviePilotVersion("3.0.10-1", to: "v3.0.10-1"), .orderedSame)
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
      XCTAssertNil(AppVersionInfo.compareMoviePilotVersion(version, to: "v3.0.10-1"))
      XCTAssertEqual(BackendCompatibilityRegistry.current.assessment(for: version).status, .unparseable)
      XCTAssertNil(BackendCompatibilityRegistry.current.assessment(for: version).profile)
    }
    XCTAssertNil(AppVersionInfo.compareMoviePilotVersion("v3.0.10-1", to: "v3.0.10-beta"))
  }

  func testSparseRegistrySeparatesExactRegistrationFromKnownContractBoundaries() {
    let registry = BackendCompatibilityRegistry.current
    let cases: [(String, BackendCompatibilityStatus, BackendContractProfile?)] = [
      ("v2.15.6", .belowMinimum, nil), ("v3.0.3", .belowMinimum, nil),
      ("v3.0.4", .registered, .v304), ("v3.0.4-1", .unregistered, .v304),
      ("v3.0.5", .registered, .v304), ("v3.0.6", .unregistered, .v304),
      ("v3.0.10", .unregistered, .v304),
      ("3.0.10-1", .registered, .v30101), ("v3.0.10-2", .unregistered, .v30101),
      ("v3.0.11", .unregistered, .v30101), ("v3.1.0", .registered, .v30101),
      ("v3.1.0-1", .newerThanRegistry, nil), ("v4.0.0", .newerThanRegistry, nil),
    ]
    for (version, status, profile) in cases {
      let assessment = registry.assessment(for: version)
      XCTAssertEqual(assessment.status, status, version)
      XCTAssertEqual(assessment.profile, profile, version)
    }
    XCTAssertEqual(registry.assessment(for: "v3.0.3").newerRecords.map(\.version.description), ["v3.0.4", "v3.0.5", "v3.0.10-1", "v3.1.0"])
    XCTAssertEqual(registry.assessment(for: "v3.0.10").newerRecords.map(\.version.description), ["v3.0.10-1", "v3.1.0"])
    XCTAssertTrue(registry.assessment(for: "v3.1.0-1").newerRecords.isEmpty)
  }

  func testProductionRegistryDoesNotInventExecutionOrLiveEvidence() throws {
    XCTAssertNil(BackendCompatibilityRegistry.current.latestValidatedVersion)
    for record in BackendCompatibilityRegistry.current.records {
      XCTAssertTrue(record.sourceReview.isVerified)
      XCTAssertFalse(record.fixtureValidation.isVerified)
      XCTAssertFalse(record.liveValidation.isVerified)
      XCTAssertFalse(record.isFullyValidated)
      let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: record.version.description))
      XCTAssertEqual(warning.title, "MoviePilot 后端兼容性待验证")
      XCTAssertTrue(warning.message.contains("合同 fixture 待执行"))
      XCTAssertTrue(warning.message.contains("真实后端未实测"))
      XCTAssertTrue(warning.message.contains("暂无已验证升级目标"))
      XCTAssertFalse(warning.message.contains("不支持"))
    }
  }

  func testEachEvidenceLayerIsRequiredForVerifiedStatus() {
    let verified = BackendCompatibilityEvidence.verified(reference: "synthetic test evidence")
    for pendingIndex in 0..<3 {
      let evidence: [BackendCompatibilityEvidence] = (0..<3).map { $0 == pendingIndex ? .pending : verified }
      let record = BackendCompatibilityRecord(version: MoviePilotVersion("v3.0.4")!, profile: .v304,
        sourceReview: evidence[0], fixtureValidation: evidence[1], liveValidation: evidence[2], limitations: [])
      XCTAssertFalse(record.isFullyValidated)
    }
    XCTAssertFalse(BackendCompatibilityEvidence.verified(reference: " ").isVerified)
    XCTAssertFalse(BackendCompatibilityEvidence.failed(reference: "failed run").isVerified)
  }

  func testUnknownWarningListsAllNewerRecordsAndTheirLimits() throws {
    let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.3"))
    XCTAssertEqual(warning.title, "MoviePilot 后端版本低于维护下限")
    XCTAssertTrue(warning.message.contains("最早维护版本 v3.0.4"))
    for record in BackendCompatibilityRegistry.current.records {
      XCTAssertTrue(warning.message.contains(record.summary))
    }
    XCTAssertTrue(warning.message.contains("仍可继续使用"))
    XCTAssertFalse(warning.message.contains("或更高版本"))
    XCTAssertFalse(warning.message.contains("数据丢失"))
    XCTAssertTrue(warning.message.contains("建议选择较新的源码已审查登记版本 v3.1.0"))
    XCTAssertTrue(warning.message.contains("源码审查不能替代真实后端实测"))
  }

  func testUnknownAndNewerVersionWarningsHaveDistinctReasons() throws {
    let unknown = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10"))
    XCTAssertEqual(unknown.title, "MoviePilot 后端版本尚未登记")
    XCTAssertTrue(unknown.message.contains("v3.0.10-1："))
    XCTAssertFalse(unknown.message.contains("v3.0.4："))
    let newer = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.1.0-1"))
    XCTAssertEqual(newer.title, "MoviePilot 后端版本高于最新登记")
    XCTAssertTrue(newer.message.contains("尚无该版本的兼容记录"))
    XCTAssertFalse(newer.message.contains("建议升级到"))
    XCTAssertTrue(newer.message.contains("请更新 MoviePilot-TV 客户端后重新检查兼容记录"))
  }

  func testUnparseableWarningRetainsUnknownSuffixInsteadOfUsingStableProfile() throws {
    let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10-1-beta"))
    XCTAssertEqual(warning.title, "无法确认 MoviePilot 后端版本")
    XCTAssertTrue(warning.message.contains("当前后端版本：v3.0.10-1-beta"))
    XCTAssertTrue(warning.message.contains("无法解析该版本号"))
    XCTAssertNil(warning.assessment.profile)
    XCTAssertTrue(try XCTUnwrap(BackendVersionWarning(backendVersion: nil)).message.contains("当前后端版本：无法确认"))
  }

  func testUpgradeRecommendationOnlyUsesFullyValidatedNewerVersion() throws {
    let validated = BackendCompatibilityTestFixtures.validatedRegistry()
    XCTAssertNil(BackendVersionWarning(backendVersion: "v3.0.10-1", registry: validated))
    let older = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10", registry: validated))
    XCTAssertTrue(older.message.contains("建议升级到已完成源码审查、合同 fixture 和真实后端实测的 v3.0.10-1"))
    let newer = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.11", registry: validated))
    XCTAssertFalse(newer.message.contains("建议升级到"))
    let pending = BackendCompatibilityTestFixtures.validatedRegistry(latestLiveValidation: .pending)
    let pendingWarning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10", registry: pending))
    XCTAssertFalse(pendingWarning.message.contains("建议升级到"), "不能建议升级到尚未实测的新版本")
    XCTAssertTrue(pendingWarning.message.contains("最新登记版本：v3.0.4"))
  }

  func testValidatedRecordWithKnownLimitationsStillExplainsThem() throws {
    let registry = BackendCompatibilityTestFixtures.validatedRegistry(latestLimitations: ["测试中的已知限制"])
    let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10-1", registry: registry))
    XCTAssertEqual(warning.title, "MoviePilot 后端兼容性提示")
    XCTAssertTrue(warning.message.contains("测试中的已知限制"))
  }

  func testAcknowledgementIdentityChangesWithRevisionEvidenceAndLimitations() throws {
    let initial = BackendCompatibilityTestFixtures.validatedRegistry(latestLiveValidation: .pending)
    let warning = try XCTUnwrap(BackendVersionWarning(backendVersion: "v3.0.10", registry: initial))
    for registry in [
      BackendCompatibilityTestFixtures.validatedRegistry(revision: "test.2", latestLiveValidation: .pending),
      BackendCompatibilityTestFixtures.validatedRegistry(latestSourceReview: .verified(reference: "revised source"), latestLiveValidation: .pending),
      BackendCompatibilityTestFixtures.validatedRegistry(latestFixtureValidation: .verified(reference: "revised fixture run"), latestLiveValidation: .pending),
      BackendCompatibilityTestFixtures.validatedRegistry(latestLiveValidation: .failed(reference: "test failure")),
      BackendCompatibilityTestFixtures.validatedRegistry(latestLiveValidation: .verified(reference: "test run 2")),
      BackendCompatibilityTestFixtures.validatedRegistry(latestLiveValidation: .pending, latestLimitations: ["changed limitation"]),
    ] {
      XCTAssertNotEqual(warning.id, BackendVersionWarning(backendVersion: "v3.0.10", registry: registry)?.id)
    }
    XCTAssertEqual(warning.id, BackendVersionWarning(backendVersion: " 3.0.10 ", registry: initial)?.id)
    let reordered = BackendCompatibilityRegistry(revision: initial.revision,
      minimumMaintainedVersion: initial.minimumMaintainedVersion, records: Array(initial.records.reversed()))
    XCTAssertEqual(initial.acknowledgementIdentity, reordered.acknowledgementIdentity)
  }
}

/// 仅用于警告生命周期测试；这些合成证据不进入生产登记表。
nonisolated enum BackendCompatibilityTestFixtures {
  static func validatedRegistry(
    revision: String = "test.1",
    latestSourceReview: BackendCompatibilityEvidence = .verified(reference: "synthetic source fixture"),
    latestFixtureValidation: BackendCompatibilityEvidence = .verified(reference: "synthetic contract fixture"),
    latestLiveValidation: BackendCompatibilityEvidence = .verified(reference: "synthetic live fixture"),
    latestLimitations: [String] = []
  ) -> BackendCompatibilityRegistry {
    BackendCompatibilityRegistry(revision: revision, minimumMaintainedVersion: MoviePilotVersion("v3.0.4")!, records: [
      BackendCompatibilityRecord(version: MoviePilotVersion("v3.0.4")!, profile: .v304,
        sourceReview: .verified(reference: "synthetic source fixture"),
        fixtureValidation: .verified(reference: "synthetic contract fixture"),
        liveValidation: .verified(reference: "synthetic live fixture"), limitations: []),
      BackendCompatibilityRecord(version: MoviePilotVersion("v3.0.10-1")!, profile: .v30101,
        sourceReview: latestSourceReview,
        fixtureValidation: latestFixtureValidation,
        liveValidation: latestLiveValidation, limitations: latestLimitations),
    ])
  }
}
