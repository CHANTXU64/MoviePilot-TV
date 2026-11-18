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

  /// 订阅补齐缺失集时后端 `format_ranges` 会产出顿号并列的多区间，须整串中文化。
  func testFormattedSeasonEpisodeLocalizesDiscontinuousEpisodeRanges() {
    let cases = [
      ("S01 E01、E03", "1季 1、3集"),
      ("S01 E01-E03、E05", "1季 1-3、5集"),
      ("S01E01、E03-E05、E09", "1季 1、3-5、9集"),
      ("E02、E04", "2、4集"),
      // 逗号并列同样认，输出统一用顿号。
      ("S01 E01,E03", "1季 1、3集"),
      ("S01 E01-E03, E05", "1季 1-3、5集"),
      // 段内空白不影响。
      ("S01 E01 、 E03", "1季 1、3集"),
    ]

    for (input, expected) in cases {
      XCTAssertEqual(input.formattedSeasonEpisode(), expected, input)
    }
  }

  /// 并列多区间里任一段畸形时整串原样返回，不能只翻译认得的部分。
  func testFormattedSeasonEpisodeKeepsMalformedListsVerbatim() {
    let cases = [
      "S01 E01、",
      "S01 、E03",
      "S01 E01、、E03",
      "S01 E01、abc",
      "E01、E03extra",
    ]

    for input in cases {
      XCTAssertEqual(input.formattedSeasonEpisode(), input, input)
    }
  }
}
