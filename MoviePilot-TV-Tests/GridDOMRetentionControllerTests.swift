import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class GridDOMRetentionControllerTests: XCTestCase {
  private let columnCount = 6

  func testInitialWindowAndPaginatorAppendKeepFourRowsWithoutOverrunningItems() {
    let controller = makeController(itemCount: 10)

    XCTAssertEqual(controller.retainedItemLimit, 24)
    XCTAssertEqual(controller.retainedItemCount(for: 10), 10)

    controller.reconcile(itemIDs: itemIDs(30))

    XCTAssertEqual(controller.retainedItemLimit, 24)
    XCTAssertEqual(controller.retainedItemCount(for: 30), 24)
  }

  func testEveryFocusedRowKeepsThreeFollowingRowsMounted() {
    let controller = makeActiveController(itemCount: 120)

    for (itemIndex, expectedLimit) in [(0, 24), (6, 30), (12, 36), (18, 42), (24, 48)] {
      controller.cardFocusChanged(itemID: "item-\(itemIndex)", isFocused: true)
      XCTAssertEqual(controller.retainedItemLimit, expectedLimit, "焦点索引 \(itemIndex)")
      XCTAssertEqual(controller.retainedItemCount(for: 120), expectedLimit)
    }
  }

  func testExpansionDoesNotWaitForStackInteractionSignal() {
    let controller = makeController(itemCount: 120)

    controller.cardFocusChanged(itemID: "item-18", isFocused: true)

    XCTAssertEqual(controller.retainedItemLimit, 42)
  }

  func testPaginatorAppendCanExpandFromStableCardIndex() {
    let controller = makeActiveController(itemCount: 30)
    controller.cardFocusChanged(itemID: "item-6", itemIndex: 6, isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 30)

    controller.reconcile(itemIDs: itemIDs(60))
    controller.cardFocusChanged(itemID: "item-12", itemIndex: 12, isFocused: true)

    XCTAssertEqual(controller.retainedItemLimit, 36)
    XCTAssertEqual(controller.retainedItemCount(for: 60), 36)
  }

  func testStaleCardIndexCanExpandButCannotTrimCurrentData() async {
    let controller = makeActiveController(itemCount: 60)
    controller.cardFocusChanged(itemID: "item-42", itemIndex: 42, isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 66)

    controller.cardFocusChanged(itemID: "item-6", itemIndex: 12, isFocused: true)
    await settleTrimWindow()

    XCTAssertEqual(controller.retainedItemLimit, 66)
  }

  func testFocusExpandsImmediatelyAndTrimsToThreeRowsAfterFocusWhenStable() async {
    let controller = makeActiveController(itemCount: 120)

    controller.cardFocusChanged(itemID: "item-59", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 78)

    controller.cardFocusChanged(itemID: "item-59", isFocused: false)
    controller.cardFocusChanged(itemID: "item-24", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 78, "向上移动不能在稳定期之前裁剪")

    await waitForRetainedItemLimit(48, in: controller)
    XCTAssertEqual(controller.retainedItemLimit, 48)
  }

  func testScrollingDefersFocusTrimUntilIdle() async {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-59", isFocused: true)

    controller.scrollPhaseChanged(.animating)
    controller.cardFocusChanged(itemID: "item-59", isFocused: false)
    controller.cardFocusChanged(itemID: "item-24", isFocused: true)
    await settleTrimWindow()
    XCTAssertEqual(controller.retainedItemLimit, 78)

    controller.scrollPhaseChanged(.idle)
    await waitForRetainedItemLimit(48, in: controller)
    XCTAssertEqual(controller.retainedItemLimit, 48)
  }

  func testLosingCardFocusCancelsPendingTrimForContextMenuOrSheet() async {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-59", isFocused: true)
    controller.cardFocusChanged(itemID: "item-24", isFocused: true)
    controller.cardFocusChanged(itemID: "item-24", isFocused: false)

    await settleTrimWindow()
    XCTAssertEqual(controller.retainedItemLimit, 78)
  }

  func testReturnToTopWaitsForRealScrollCompletionThenTrimsToFourRows() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 84)

    controller.scrollPhaseChanged(.animating)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    XCTAssertEqual(controller.retainedItemLimit, 84)

    controller.scrollPhaseChanged(.idle)
    await waitForRetainedItemLimit(24, in: controller)
    XCTAssertEqual(controller.retainedItemLimit, 24)
  }

  func testFocusEngineGeometryOnlyReturnToTopTrimsToFourRows() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 84)

    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    await waitForRetainedItemLimit(24, in: controller)

    XCTAssertEqual(controller.retainedItemLimit, 24)
  }

  func testFocusEngineReturnToTopDoesNotRequireIdleCallback() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)

    controller.scrollPhaseChanged(.animating)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    await waitForRetainedItemLimit(24, in: controller)

    XCTAssertEqual(controller.retainedItemLimit, 24)
  }

  func testGeometryOnlyReturnToTopStillTrimsDuringTabTransition() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)

    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    controller.setStackInteractive(false)
    await waitForRetainedItemLimit(24, in: controller)

    XCTAssertEqual(controller.retainedItemLimit, 24, "切 Tab 不能丢弃已经确认的回顶裁剪")
  }

  func testTabTransitionKeepsConfirmedReturnToTopTrim() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    controller.scrollPhaseChanged(.animating)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    controller.scrollPhaseChanged(.idle)

    controller.setStackInteractive(false)
    await waitForRetainedItemLimit(24, in: controller)
    controller.setStackInteractive(true)
    await settleTrimWindow()

    XCTAssertEqual(controller.retainedItemLimit, 24, "切 Tab 本身不裁 DOM，但已确认回顶必须完成")
  }

  func testViewDisappearDoesNotCancelConfirmedReturnToTopTrim() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.scrollPositionChanged(adjustedOffsetY: 0)

    controller.setStackInteractive(false)
    controller.setViewActive(false)
    await waitForRetainedItemLimit(24, in: controller)

    XCTAssertEqual(controller.retainedItemLimit, 24, "onDisappear 不能丢掉已确认的回顶裁剪")
  }

  func testTabRoundTripDuringAnimationCannotAdoptOldScrollSession() async {
    let controller = makeActiveController(itemCount: 120)
    controller.scrollPositionChanged(adjustedOffsetY: 900)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    controller.scrollPhaseChanged(.animating)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)

    controller.setStackInteractive(false)
    controller.setStackInteractive(true)
    controller.scrollPositionChanged(adjustedOffsetY: 0)
    controller.scrollPhaseChanged(.idle)
    await settleTrimWindow()

    XCTAssertEqual(controller.retainedItemLimit, 84, "切回后不能接管切走前开始的动画")
  }

  func testFirstRestoredFocusAfterTabRoundTripCannotShrinkDOM() async {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 84)

    controller.setStackInteractive(false)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.setStackInteractive(true)
    controller.cardFocusChanged(itemID: "item-0", isFocused: true)
    await settleTrimWindow()
    XCTAssertEqual(controller.retainedItemLimit, 84, "系统恢复焦点不能被当成用户向上滚动")

    controller.cardFocusChanged(itemID: "item-1", isFocused: true)
    await waitForRetainedItemLimit(24, in: controller)
    XCTAssertEqual(controller.retainedItemLimit, 24, "恢复完成后的真实焦点移动应继续正常裁剪")
  }

  func testFirstRestoredFocusAfterDetailRoundTripCannotShrinkDOM() async {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-65", isFocused: true)

    controller.setViewActive(false)
    controller.cardFocusChanged(itemID: "item-65", isFocused: false)
    controller.setViewActive(true)
    controller.cardFocusChanged(itemID: "item-0", isFocused: true)
    await settleTrimWindow()

    XCTAssertEqual(controller.retainedItemLimit, 84, "详情页返回时的系统焦点恢复不能裁剪父页")
  }

  func testNewFocusInvalidatesOlderDelayedTrim() async {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-59", isFocused: true)
    controller.cardFocusChanged(itemID: "item-24", isFocused: true)
    controller.cardFocusChanged(itemID: "item-83", isFocused: true)

    await settleTrimWindow()
    XCTAssertEqual(controller.retainedItemLimit, 102)
  }

  func testReplacingPaginatorDataResetsDOMWindowButAppendingDoesNot() {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-59", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 78)

    controller.reconcile(itemIDs: itemIDs(140))
    XCTAssertEqual(controller.retainedItemLimit, 78)

    let replacementIDs = (0..<80).map { "replacement-\($0)" }
    controller.reconcile(itemIDs: replacementIDs)
    XCTAssertEqual(controller.retainedItemLimit, 24)
  }

  func testNewListIDResetsDOMEvenWhenItemsAreIdenticalAndRejectsStaleFocus() {
    let controller = makeActiveController(itemCount: 120)
    controller.cardFocusChanged(itemID: "item-59", isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 78)

    let oldListIdentity = controller.listIdentity
    let newListIdentity = GridListIdentity.make()
    controller.reconcile(listIdentity: newListIdentity, itemIDs: itemIDs(120))
    XCTAssertEqual(controller.retainedItemLimit, 24)

    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: oldListIdentity,
        itemID: "item-59",
        itemIndex: 59,
        isFocused: true
      )
    )
    XCTAssertEqual(controller.retainedItemLimit, 24)
  }

  func testEventSnapshotCannotRestorePreRefreshDOMOrReplaceCurrentGeneration() {
    let controller = makeActiveController(itemCount: 120)
    let oldIdentity = controller.listIdentity
    controller.cardFocusChanged(itemID: "item-65", itemIndex: 65, isFocused: true)
    XCTAssertEqual(controller.retainedItemLimit, 84)

    let refreshedIdentity = oldIdentity.advanced()
    controller.reconcile(listIdentity: refreshedIdentity, itemIDs: [])
    XCTAssertFalse(
      controller.reconcileEventSnapshot(
        listIdentity: oldIdentity,
        itemIDs: itemIDs(120)
      )
    )
    XCTAssertEqual(controller.listIdentity, refreshedIdentity)
    XCTAssertEqual(controller.retainedItemLimit, 24)

    let replacementIDs = (0..<60).map { "replacement-\($0)" }
    controller.reconcile(listIdentity: refreshedIdentity, itemIDs: replacementIDs)
    XCTAssertFalse(
      controller.reconcileEventSnapshot(
        listIdentity: refreshedIdentity,
        itemIDs: itemIDs(60)
      )
    )
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: refreshedIdentity,
        itemID: "item-42",
        itemIndex: 42,
        isFocused: true
      )
    )
  }

  private func makeController(itemCount: Int) -> GridDOMRetentionController {
    GridDOMRetentionController(
      listIdentity: GridListIdentity.make(),
      itemIDs: itemIDs(itemCount),
      columnCount: columnCount,
      stabilizationDelay: .milliseconds(15)
    )
  }

  private func makeActiveController(itemCount: Int) -> GridDOMRetentionController {
    let controller = makeController(itemCount: itemCount)
    controller.setViewActive(true)
    controller.setStackInteractive(true)
    return controller
  }

  private func itemIDs(_ count: Int) -> [MediaInfo.ID] {
    (0..<count).map { "item-\($0)" }
  }

  private func waitForRetainedItemLimit(
    _ expectedLimit: Int,
    in controller: GridDOMRetentionController,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    await waitUntil(
      "retained item limit to become \(expectedLimit)",
      file: file,
      line: line
    ) {
      controller.retainedItemLimit == expectedLimit
    }
  }

  private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(1),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      if clock.now >= deadline {
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
        return
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private func settleTrimWindow() async {
    try? await Task.sleep(for: .milliseconds(75))
  }
}

private extension GridDOMRetentionController {
  @discardableResult
  func cardFocusChanged(
    itemID: MediaInfo.ID,
    itemIndex: Int? = nil,
    isFocused: Bool
  ) -> Bool {
    cardFocusChanged(
      listIdentity: listIdentity,
      itemID: itemID,
      itemIndex: itemIndex,
      isFocused: isFocused
    )
  }

  func reconcile(itemIDs: [MediaInfo.ID]) {
    reconcile(listIdentity: listIdentity, itemIDs: itemIDs)
  }
}
