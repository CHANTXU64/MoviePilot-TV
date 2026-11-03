import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaDetailCreditKindTests: XCTestCase {
  func testAvailableKindsKeepCastBeforeCrew() {
    XCTAssertEqual(MediaDetailCreditKind.available(hasCast: true, hasCrew: true), [.cast, .crew])
    XCTAssertEqual(MediaDetailCreditKind.available(hasCast: true, hasCrew: false), [.cast])
    XCTAssertEqual(MediaDetailCreditKind.available(hasCast: false, hasCrew: true), [.crew])
    XCTAssertEqual(MediaDetailCreditKind.available(hasCast: false, hasCrew: false), [])
  }

  func testResolvedKeepsSelectionWhenItHasContent() {
    for settled in [true, false] {
      XCTAssertEqual(
        MediaDetailCreditKind.resolved(
          selected: .cast, hasCast: true, hasCrew: true, isCastSettled: settled), .cast)
      XCTAssertEqual(
        MediaDetailCreditKind.resolved(
          selected: .crew, hasCast: true, hasCrew: true, isCastSettled: settled), .crew)
    }
  }

  func testCastStillLoadingDoesNotFallBackToCrew() {
    // 职员随详情同步到达、演员还在请求：不先渲染职员行，避免白白请求职员头像。
    XCTAssertNil(
      MediaDetailCreditKind.resolved(
        selected: .cast, hasCast: false, hasCrew: true, isCastSettled: false))
  }

  func testSettledEmptyCastFallsBackToCrew() {
    XCTAssertEqual(
      MediaDetailCreditKind.resolved(
        selected: .cast, hasCast: false, hasCrew: true, isCastSettled: true), .crew)
  }

  func testCrewSelectionStaysWhileCastReloads() {
    // 已经退到职员并记住后，演员重新加载期间这一行不消失。
    XCTAssertEqual(
      MediaDetailCreditKind.resolved(
        selected: .crew, hasCast: false, hasCrew: true, isCastSettled: false), .crew)
  }

  func testEmptyCrewSelectionFallsBackToCast() {
    XCTAssertEqual(
      MediaDetailCreditKind.resolved(
        selected: .crew, hasCast: true, hasCrew: false, isCastSettled: true), .cast)
  }

  func testResolvedIsNilWhenBothKindsAreEmpty() {
    for selected in MediaDetailCreditKind.allCases {
      for settled in [true, false] {
        XCTAssertNil(
          MediaDetailCreditKind.resolved(
            selected: selected, hasCast: false, hasCrew: false, isCastSettled: settled))
      }
    }
  }

  func testTitles() {
    XCTAssertEqual(MediaDetailCreditKind.cast.title, "演员")
    XCTAssertEqual(MediaDetailCreditKind.crew.title, "职员")
  }
}
