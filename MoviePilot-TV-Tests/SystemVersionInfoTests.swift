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
    XCTAssertEqual(AppVersionInfo.compatibleMoviePilotVersion, "v2.13.6")
  }
}
