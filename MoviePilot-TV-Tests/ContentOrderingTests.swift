import XCTest

@testable import MoviePilot_TV

final class ContentOrderingTests: XCTestCase {
  // MARK: - 渲染合并

  func testRenderOrderFollowsStoredOrderAndAppendsNewIDs() {
    let stored = ["c", "a", "b"]
    let current = ["a", "b", "c", "d"]
    XCTAssertEqual(ContentOrdering.orderedVisibleIDs(stored: stored, current: current), ["c", "a", "b", "d"])
  }

  func testRenderOrderIgnoresDisappearedIDsAndEmptyStorage() {
    XCTAssertEqual(
      ContentOrdering.orderedVisibleIDs(stored: ["ghost", "a"], current: ["a", "b"]), ["a", "b"])
    XCTAssertEqual(ContentOrdering.orderedVisibleIDs(stored: [], current: ["a", "b"]), ["a", "b"])
    XCTAssertEqual(ContentOrdering.orderedVisibleIDs(stored: ["a"], current: []), [])
  }

  func testRenderOrderDeduplicatesStoredIDs() {
    XCTAssertEqual(
      ContentOrdering.orderedVisibleIDs(stored: ["a", "a", "b"], current: ["a", "b", "c"]),
      ["a", "b", "c"])
  }

  // MARK: - 保存合并（槽位保留）

  func testPersistKeepsGhostSlotWhileVisibleItemsReorder() {
    // A B C D 中 B 卸载，可见项重排为 D A C → B 钉在原槽位 1。
    XCTAssertEqual(
      ContentOrdering.persistOrder(stored: ["A", "B", "C", "D"], reorderedVisible: ["D", "A", "C"]),
      ["D", "B", "A", "C"])
  }

  func testPersistPinsMultipleGhostsAtHeadMiddleAndTail() {
    XCTAssertEqual(
      ContentOrdering.persistOrder(
        stored: ["G1", "A", "G2", "B", "G3"], reorderedVisible: ["B", "A"]),
      ["G1", "B", "G2", "A", "G3"])
  }

  func testPersistAppendsNewIDsAfterStoredSlots() {
    XCTAssertEqual(
      ContentOrdering.persistOrder(stored: ["A", "B"], reorderedVisible: ["A", "B", "C"]),
      ["A", "B", "C"])
    XCTAssertEqual(
      ContentOrdering.persistOrder(stored: ["A", "B"], reorderedVisible: ["C", "A", "B"]),
      ["C", "A", "B"])
  }

  func testPersistWithoutGhostsEqualsReorderedVisible() {
    XCTAssertEqual(
      ContentOrdering.persistOrder(stored: ["A", "B", "C"], reorderedVisible: ["C", "A", "B"]),
      ["C", "A", "B"])
  }

  func testPersistEmptyInputs() {
    XCTAssertEqual(ContentOrdering.persistOrder(stored: [], reorderedVisible: ["A"]), ["A"])
    XCTAssertEqual(
      ContentOrdering.persistOrder(stored: ["G1", "G2"], reorderedVisible: []), ["G1", "G2"])
  }

  func testPersistThenRestoreReturnsGhostToOriginalSlot() {
    // 卸载期间重排保存，重装后渲染合并应把来源放回原槽位。
    let saved = ContentOrdering.persistOrder(
      stored: ["A", "B", "C", "D"], reorderedVisible: ["D", "A", "C"])
    XCTAssertEqual(
      ContentOrdering.orderedVisibleIDs(stored: saved, current: ["A", "B", "C", "D"]),
      ["D", "B", "A", "C"])
  }
}