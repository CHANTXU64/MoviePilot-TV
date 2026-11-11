import XCTest

@testable import MoviePilot_TV

/// F-059（部分修复）回归：畸形季集字符串不得被**归类**成整季。
///
/// `ParsedSeason` 的初始化器没有「解析成功」标志位，失败字段一律留 0，
/// 于是一个带 `E` 标记但集号解析失败的输入，会掉进「没有 E 标记」的那个
/// `else` 分支被标成整季 —— 具体集冒充整季混进整季组，这是三条季集
/// finding 里唯一的**归类错误**（F-057 范围终点丢失、F-058 两套语法
/// 都只影响排序位置，经用户决定跳过）。
///
/// 本次只收紧该分支：整季当且仅当**压根没有 E 标记**。畸形输入与「无」
/// 一样留在全 0 的无效组，既有排序位置不变。
@MainActor
final class ParsedSeasonTests: XCTestCase {

  private func parsed(_ original: String) -> ParsedSeason {
    ParsedSeason(original: original, index: 0)
  }

  // MARK: - 归类：整季 vs 具体集

  func testOverflowEpisodeIsNotClassifiedAsWholeSeason() {
    // 正则能匹配，但集号超出 Int 范围，`Int(_:)` 返回 nil。
    // 修复前这里走 else 分支被标成整季。
    let subject = parsed("S01E99999999999999999999")

    XCTAssertFalse(subject.isWholeSeason, "带 E 标记的畸形输入不得冒充整季")
  }

  /// 阴性对照：真正没有 E 标记的输入仍然是整季。
  func testPlainSeasonIsStillWholeSeason() {
    XCTAssertTrue(parsed("S01").isWholeSeason)
    XCTAssertTrue(parsed("S12").isWholeSeason)
  }

  /// 阴性对照：正常集号仍然不是整季。
  func testNormalEpisodeIsNotWholeSeason() {
    XCTAssertFalse(parsed("S01E01").isWholeSeason)
    XCTAssertFalse(parsed("S01E01-E05").isWholeSeason)
  }

  /// 阴性对照：完全解析不了的输入（正则不匹配）沿用默认值，行为不变。
  func testUnparseableInputStaysOutOfWholeSeasonGroup() {
    XCTAssertFalse(parsed("无").isWholeSeason)
    XCTAssertFalse(parsed("").isWholeSeason)
  }

  // MARK: - 排序出口

  /// 畸形输入不得被排到真实集号前面（修复前它作为「整季」排在整季组，而整季组整体靠前）。
  func testOverflowEpisodeIsSortedAfterRealEpisodes() {
    let sorted = ParsedSeason.sortSeasonOptions(["S01E05", "S01E99999999999999999999"])

    XCTAssertEqual(sorted, ["S01E05", "S01E99999999999999999999"])
  }

  /// 阴性对照：正常整季排序不受影响（大季号在前）。
  func testWholeSeasonOrderingUnchanged() {
    XCTAssertEqual(ParsedSeason.sortSeasonOptions(["S01", "S03", "S02"]), ["S03", "S02", "S01"])
  }

  /// 阴性对照：正常集号排序不受影响（同季按结束集号降序）。
  func testEpisodeOrderingUnchanged() {
    XCTAssertEqual(
      ParsedSeason.sortSeasonOptions(["S01E01", "S01E05", "S01E03"]),
      ["S01E05", "S01E03", "S01E01"])

    // F-057 决定跳过，此处锁定既有行为：集范围按**终点**排序。
    XCTAssertEqual(
      ParsedSeason.sortSeasonOptions(["S01E01-E05", "S01E03"]),
      ["S01E01-E05", "S01E03"])
  }

  /// 阴性对照：整季组整体排在具体集之前（既有业务约定）。
  func testWholeSeasonsStillPrecedeEpisodes() {
    XCTAssertEqual(ParsedSeason.sortSeasonOptions(["S01E01", "S02"]), ["S02", "S01E01"])
  }

  /// 边界：单选项与空输入原样返回。
  func testShortInputsAreReturnedUnchanged() {
    XCTAssertEqual(ParsedSeason.sortSeasonOptions(["S01"]), ["S01"])
    XCTAssertEqual(ParsedSeason.sortSeasonOptions([]), [])
  }
}
