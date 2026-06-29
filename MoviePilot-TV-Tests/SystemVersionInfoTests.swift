import XCTest

@testable import MoviePilot_TV

final class SystemVersionInfoTests: XCTestCase {
  func testVersionInfoFormatsAppAndCompatibleMoviePilotVersions() {
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "1.0"), "v1.0")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "v0.3.1"), "v0.3.1")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: ""), "未知")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: "   "), "未知")
    XCTAssertEqual(AppVersionInfo.displayAppVersion(shortVersion: nil), "未知")
    XCTAssertEqual(AppVersionInfo.compatibleMoviePilotVersion, "v2.13.14")
  }

  func testMoviePilotVersionComparisonIgnoresPrefixAndReleaseSuffix() {
    XCTAssertEqual(
      AppVersionInfo.compareMoviePilotVersion("v2.13.14", to: "v2.13.14"),
      .orderedSame
    )
    XCTAssertEqual(
      AppVersionInfo.compareMoviePilotVersion("2.13.14-1", to: "v2.13.14"),
      .orderedSame
    )
    XCTAssertEqual(
      AppVersionInfo.compareMoviePilotVersion("v2.13.15", to: "v2.13.14"),
      .orderedDescending
    )
    XCTAssertEqual(
      AppVersionInfo.compareMoviePilotVersion("v2.13.13", to: "v2.13.14"),
      .orderedAscending
    )
  }

  func testMoviePilotVersionComparisonRejectsMalformedVersions() {
    XCTAssertNil(AppVersionInfo.compareMoviePilotVersion("v2.beta.14", to: "v2.13.14"))
    XCTAssertNil(AppVersionInfo.compareMoviePilotVersion("v2.13beta.14", to: "v2.13.14"))
    XCTAssertNil(AppVersionInfo.compareMoviePilotVersion("release-2.13.14", to: "v2.13.14"))
  }

  func testUnsupportedMoviePilotVersionBuildsWarningMessage() {
    let warning = BackendVersionWarning(
      backendVersion: "v2.13.13",
      requiredVersion: "v2.13.14"
    )

    XCTAssertEqual(warning.title, "MoviePilot 后端版本过低")
    XCTAssertTrue(warning.message.contains("当前后端版本：v2.13.13"))
    XCTAssertTrue(warning.message.contains("需要 v2.13.14 或更高版本"))
    XCTAssertTrue(warning.message.contains("严重功能异常或数据丢失"))
    XCTAssertTrue(warning.message.contains("仍可继续使用"))
  }

  func testUnknownMoviePilotVersionBuildsUnconfirmedWarningMessage() {
    let warning = BackendVersionWarning(
      backendVersion: "未知",
      requiredVersion: "v2.13.14"
    )

    XCTAssertEqual(warning.id, "unknown|v2.13.14")
    XCTAssertEqual(warning.title, "无法确认 MoviePilot 后端版本")
    XCTAssertTrue(warning.message.contains("当前后端版本：无法确认"))
    XCTAssertFalse(warning.title.contains("版本过低"))
  }
}
