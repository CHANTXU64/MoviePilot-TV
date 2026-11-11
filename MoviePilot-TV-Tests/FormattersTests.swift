import XCTest

@testable import MoviePilot_TV

@MainActor
final class FormattersTests: XCTestCase {
  func testFormattedSeasonEpisodePreservesSupportedOutputAndFallback() {
    let cases = [
      ("S01", "1季"),
      ("S01E01", "1季 1集"),
      ("S01 E28-E32", "1季 28-32集"),
      ("S01-02 E03-04", "1-2季 3-4集"),
      ("E01-E05", "1-5集"),
      ("s02e03", "2季 3集"),
      ("Season 1", "Season 1"),
    ]

    for (input, expected) in cases {
      XCTAssertEqual(input.formattedSeasonEpisode(), expected)
    }
  }
}
