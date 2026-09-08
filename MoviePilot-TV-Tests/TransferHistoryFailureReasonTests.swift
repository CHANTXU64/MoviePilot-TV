import XCTest

@testable import MoviePilot_TV

/// F-201：失败历史的后端失败原因在 TV 内不可达。
/// 投影仅失败记录且 trim 后非空白的 errmsg：列表行截取 maxLength=20，详情页返回完整原因；成功/空白一律不显示。
@MainActor
final class TransferHistoryFailureReasonTests: XCTestCase {
  private func history(status: Bool, errmsg: String?) throws -> TransferHistory {
    let errmsgPart = errmsg.map { #""errmsg":\#(String(reflecting: $0))"# } ?? ""
    let separator = errmsg == nil ? "" : ","
    let json = #"{"id":1,"title":"测试","type":"电影","status":\#(status)\#(separator)\#(errmsgPart)}"#
    return try JSONDecoder().decode(TransferHistory.self, from: Data(json.utf8))
  }

  func testRowSummaryTruncatesToTwentyCharacters() throws {
    let item = try history(status: false, errmsg: "目标磁盘空间不足，无法完成文件转移，请检查存储配置")
    XCTAssertEqual(item.failureReason(maxLength: 20), "目标磁盘空间不足，无法完成文件转移，请检")
    XCTAssertEqual(item.failureReason(maxLength: 20)?.count, 20)
  }

  func testDetailPageReturnsFullUntruncatedReason() throws {
    let item = try history(status: false, errmsg: "目标磁盘空间不足，无法完成文件转移，请检查存储配置")
    XCTAssertEqual(item.failureReason(), "目标磁盘空间不足，无法完成文件转移，请检查存储配置")
  }

  func testDetailPageShortReasonUntouched() throws {
    let item = try history(status: false, errmsg: "磁盘已满")
    XCTAssertEqual(item.failureReason(), "磁盘已满")
  }

  func testFailedRecordWhitespaceOnlyReasonIsNil() throws {
    let item = try history(status: false, errmsg: "   \n  ")
    XCTAssertNil(item.failureReason())
  }

  func testFailedRecordNilReasonIsNil() throws {
    let item = try history(status: false, errmsg: nil)
    XCTAssertNil(item.failureReason())
  }

  func testSuccessRecordNeverShowsReason() throws {
    let item = try history(status: true, errmsg: "磁盘已满")
    XCTAssertNil(item.failureReason())
  }

  func testReasonIsTrimmedBeforeTruncation() throws {
    let item = try history(status: false, errmsg: "  权限不足  ")
    XCTAssertEqual(item.failureReason(), "权限不足")
  }

  func testCustomMaxLengthIsRespected() throws {
    let item = try history(status: false, errmsg: "目标磁盘空间不足")
    XCTAssertEqual(item.failureReason(maxLength: 4), "目标磁盘")
  }
}
