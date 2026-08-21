import XCTest

@testable import MoviePilot_TV

@MainActor
final class ExploreViewModelYearDictTests: XCTestCase {
  private var gregorianCurrentYear: Int {
    Calendar(identifier: .gregorian).component(.year, from: Date())
  }

  func testDoubanYearDictUsesGregorianCurrentYear() {
    let years = ExploreViewModel.doubanYearDict
    let currentYear = gregorianCurrentYear

    XCTAssertEqual(years.count, 13)
    XCTAssertEqual(years.prefix(6).map { Int($0.key) }, (0..<6).map { currentYear - $0 })
    XCTAssertEqual(years.prefix(6).map(\.key), years.prefix(6).map(\.value))
    XCTAssertTrue(years.contains { $0.key == "2020年代" })
    XCTAssertTrue(years.contains { $0.key == "70年代" })
  }

  func testBangumiYearDictUsesGregorianCurrentYear() {
    let years = ExploreViewModel.bangumiYearDict
    let currentYear = gregorianCurrentYear

    XCTAssertEqual(years.count, 10)
    XCTAssertEqual(years.map { Int($0.key) }, (0..<10).map { currentYear - $0 })
    XCTAssertEqual(years.map(\.key), years.map(\.value))
  }

  func testAnilistYearDictUsesGregorianCurrentYear() {
    let years = ExploreViewModel.anilistYearDict
    let currentYear = gregorianCurrentYear

    XCTAssertEqual(years.count, 15)
    XCTAssertEqual(years.map(\.key), (0..<15).map { currentYear - $0 })
    XCTAssertEqual(years.map { String($0.key) }, years.map(\.value))
    XCTAssertTrue(years.allSatisfy { $0.key > 0 })
  }

  func testYearDictsNeverUseSystemCalendar() throws {
    let sourceURL = try XCTUnwrap(
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MoviePilot-TV/ViewModels/ExploreViewModel.swift"))
    let source = try String(contentsOf: sourceURL)

    XCTAssertFalse(source.contains("Calendar.current.component(.year"))
    XCTAssertEqual(
      source.components(separatedBy: "Calendar(identifier: .gregorian).component(.year").count - 1,
      3)
  }
}
