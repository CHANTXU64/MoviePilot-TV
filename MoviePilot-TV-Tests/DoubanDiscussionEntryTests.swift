import XCTest

@testable import MoviePilot_TV

/// 卡片/Sheet 展示模型的文案规则。
///
/// 重点盯住与 Web `MediaCommentView` 对齐的元信息：
/// - 日期只到「天」（豆瓣 `create_time` 可能带时分秒）；
/// - 有用数文案是「N 有用」，不出现回应数。
@MainActor
final class DoubanDiscussionEntryTests: XCTestCase {
  private func decodeComment(_ json: String) throws -> DoubanComment {
    try JSONDecoder().decode(DoubanComment.self, from: Data(json.utf8))
  }

  private func decodeReview(_ json: String) throws -> DoubanReview {
    try JSONDecoder().decode(DoubanReview.self, from: Data(json.utf8))
  }

  // MARK: - 日期只显示到天

  /// 豆瓣原始时间是「日期 + 时分秒」，卡片和 Sheet 只展示日期部分。
  func testTimeTextKeepsDateOnly() throws {
    let withTime = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c1","comment":"正文","create_time":"2021-10-29 12:00:00"}"#)
    )
    XCTAssertEqual(withTime.timeText, "2021-10-29")

    let iso = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c2","comment":"正文","create_time":"2024-01-01T10:00:00"}"#)
    )
    XCTAssertEqual(iso.timeText, "2024-01-01")

    let dateOnly = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c3","comment":"正文","create_time":"2024-01-01"}"#)
    )
    XCTAssertEqual(dateOnly.timeText, "2024-01-01")
  }

  /// 读不出日期或格式意外时保留原值；缺失或纯空白就是没有这一项。
  func testTimeTextFallbacks() throws {
    let unexpected = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c1","comment":"正文","create_time":"昨天"}"#)
    )
    XCTAssertEqual(unexpected.timeText, "昨天")

    let missing = DoubanDiscussionEntry(comment: try decodeComment(#"{"id":"c2","comment":"正文"}"#))
    XCTAssertNil(missing.timeText)

    let blank = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c3","comment":"正文","create_time":"   "}"#)
    )
    XCTAssertNil(blank.timeText)
  }

  // MARK: - 有用数文案

  /// Web 的文案是「{count} 有用」，0 与缺失都不展示。
  func testUsefulText() throws {
    let comment = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c1","comment":"正文","vote_count":12}"#)
    )
    XCTAssertEqual(comment.usefulText, "12 有用")

    let review = DoubanDiscussionEntry(
      review: try decodeReview(#"{"id":"r1","title":"标题","useful_count":7}"#)
    )
    XCTAssertEqual(review.usefulText, "7 有用")

    let zero = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c2","comment":"正文","vote_count":0}"#)
    )
    XCTAssertNil(zero.usefulText)
  }

  /// 影评标题归一化：纯空白视同没有标题，短评不展示标题。
  func testReviewTitleAndKind() throws {
    let review = DoubanDiscussionEntry(
      review: try decodeReview(#"{"id":"r1","title":"  标题  ","abstract":"摘要"}"#)
    )
    XCTAssertEqual(review.kind, .review)
    XCTAssertEqual(review.title, "标题")
    XCTAssertEqual(review.body, "摘要")

    let untitled = DoubanDiscussionEntry(
      review: try decodeReview(#"{"id":"r2","title":"   ","abstract":"摘要"}"#)
    )
    XCTAssertNil(untitled.title)

    let comment = DoubanDiscussionEntry(
      comment: try decodeComment(#"{"id":"c1","comment":"短评正文"}"#)
    )
    XCTAssertEqual(comment.kind, .comment)
    XCTAssertNil(comment.title)
  }

  // MARK: - 星级

  /// 五星制按半星取整；没有评分或评分为 0 时不画星，避免误读成 0 分。
  func testStarFillsRoundToHalfStars() throws {
    func fills(_ rating: String) throws -> [DoubanDiscussionEntry.StarFill]? {
      DoubanDiscussionEntry(
        comment: try decodeComment(#"{"id":"c","comment":"正文","rating":\#(rating)}"#)
      ).starFills
    }
    XCTAssertEqual(try fills("4"), [.full, .full, .full, .full, .empty])
    XCTAssertEqual(try fills("3.5"), [.full, .full, .full, .half, .empty])
    XCTAssertEqual(try fills("5"), [.full, .full, .full, .full, .full])
    // 超出五星制时按满星截断。
    XCTAssertEqual(try fills("7"), [.full, .full, .full, .full, .full])
    XCTAssertEqual(try fills("0.2"), [.empty, .empty, .empty, .empty, .empty])
    XCTAssertNil(try fills("0"))
    XCTAssertNil(try fills("null"))
  }

  // MARK: - 发帖时间

  /// 详情 Sheet 的发帖日期与时刻分两行，时刻精确到分钟；只有日期时没有时刻，格式意外时保留原值。
  func testPostedDateAndTimeAreSeparated() throws {
    func posted(_ time: String) throws -> [String?]? {
      DoubanDiscussionEntry(
        comment: try decodeComment(#"{"id":"c","comment":"正文","create_time":"\#(time)"}"#)
      ).postedDateAndTime.map { [$0.date, $0.time] }
    }
    XCTAssertEqual(try posted("2021-10-29 12:34:56"), ["2021-10-29", "12:34"])
    XCTAssertEqual(try posted("2024-01-01T10:00:00"), ["2024-01-01", "10:00"])
    XCTAssertEqual(try posted("2024-01-01"), ["2024-01-01", nil])
    XCTAssertEqual(try posted("昨天"), ["昨天", nil])
    XCTAssertNil(try posted("  "))
  }
}
