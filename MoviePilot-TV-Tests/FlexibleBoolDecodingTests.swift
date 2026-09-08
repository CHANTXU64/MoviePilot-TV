import XCTest

@testable import MoviePilot_TV

/// F-001 回归：`FlexibleBool` 字符串分支需清理换行，带行尾的真值字符串不得静默解为 `false`。
@MainActor
final class FlexibleBoolDecodingTests: XCTestCase {
  private struct Wrapper: Decodable {
    let flag: FlexibleBool?
  }

  /// 用 JSONSerialization 构造 payload，确保换行以合法的 `\n` 转义传输（真实传输形态）。
  private func decodeFlag(_ value: String) throws -> Bool {
    let data = try JSONSerialization.data(withJSONObject: ["flag": value])
    let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
    return try XCTUnwrap(wrapper.flag).value
  }

  func testTruthyStringWithTrailingNewlineDecodesTrue() throws {
    XCTAssertTrue(try decodeFlag("true\n"))
    XCTAssertTrue(try decodeFlag("1\n"))
    XCTAssertTrue(try decodeFlag("yes\r\n"))
    XCTAssertTrue(try decodeFlag("on\n"))
  }

  func testFalsyStringWithTrailingNewlineDecodesFalse() throws {
    XCTAssertFalse(try decodeFlag("false\n"))
    XCTAssertFalse(try decodeFlag("0\r\n"))
    XCTAssertFalse(try decodeFlag("no\n"))
    XCTAssertFalse(try decodeFlag("off\n"))
  }
}
