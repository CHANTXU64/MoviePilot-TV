import XCTest

@testable import MoviePilot_TV

/// 横排页头随聚焦卡片上移的判断：卡片挪进可见宽度、覆盖哪几块页头、空按钮区不参与。
final class FocusLiftRowHeaderTests: XCTestCase {
  private let rowWidth: CGFloat = 1920
  private let title = UUID()
  private let buttons = UUID()

  /// 左边标题 89…400，右边按钮组 1500…1831。
  private var headerParts: [FocusLiftHeaderPartFrame] {
    [
      FocusLiftHeaderPartFrame(id: title, span: FocusLiftSpan(minX: 89, maxX: 400)),
      FocusLiftHeaderPartFrame(id: buttons, span: FocusLiftSpan(minX: 1500, maxX: 1831)),
    ]
  }

  private func lifted(cardFrom minX: CGFloat, width: CGFloat = 410) -> Set<UUID> {
    FocusLiftSpan.liftedParts(
      cardSpan: FocusLiftSpan(minX: minX, maxX: minX + width),
      rowWidth: rowWidth,
      headerParts: headerParts
    )
  }

  func testOnlyThePartAboveTheFocusedCardLifts() {
    XCTAssertEqual(lifted(cardFrom: 81), [title])
    XCTAssertEqual(lifted(cardFrom: 1421), [buttons])
    XCTAssertEqual(lifted(cardFrom: 900), [], "卡片在两块之间时都不上移")
  }

  func testCardOffscreenToTheRightIsJudgedWhereScrollingWillSettleIt() {
    // 焦点移到屏幕外右侧的卡片，横排还没滚过来：按贴右边后的位置判断，按钮组保持顶起。
    XCTAssertEqual(lifted(cardFrom: 2300), [buttons])
  }

  func testCardOffscreenToTheLeftIsJudgedWhereScrollingWillSettleIt() {
    XCTAssertEqual(lifted(cardFrom: -900), [title])
  }

  func testEmptyHeaderPartNeverLifts() {
    let empty = UUID()
    let parts = headerParts + [FocusLiftHeaderPartFrame(id: empty, span: FocusLiftSpan(minX: 1000, maxX: 1000.5))]
    let result = FocusLiftSpan.liftedParts(
      cardSpan: FocusLiftSpan(minX: 900, maxX: 1310), rowWidth: rowWidth, headerParts: parts
    )
    XCTAssertEqual(result, [], "宽度不到 1pt 的空按钮区不算页头内容")
  }

  func testShiftKeepsSpansAlreadyInsideTheRowAndIgnoresUnknownWidth() {
    let span = FocusLiftSpan(minX: 300, maxX: 710)
    XCTAssertEqual(span.shifted(into: rowWidth), span)
    XCTAssertEqual(FocusLiftSpan(minX: 2300, maxX: 2710).shifted(into: 0), FocusLiftSpan(minX: 2300, maxX: 2710))
  }

  func testTouchingEdgesDoNotCountAsOverlap() {
    XCTAssertFalse(FocusLiftSpan(minX: 0, maxX: 89).overlaps(FocusLiftSpan(minX: 89, maxX: 400)))
    XCTAssertTrue(FocusLiftSpan(minX: 0, maxX: 90).overlaps(FocusLiftSpan(minX: 89, maxX: 400)))
  }
}
