import Kingfisher
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class GridImageLifecycleControllerTests: XCTestCase {
  private let columnCount = 6

  func testVisibleGridStartsWithTopRowsAndFirstValidFocusOpensCurrentWindow() {
    let listID = UUID()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listID: listID, itemCount: 60, lifecycle: lifecycle)

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertTrue(controller.allowsImages(listID: listID, itemIndex: 0))
    XCTAssertFalse(controller.allowsImages(listID: listID, itemIndex: 12))

    XCTAssertTrue(
      controller.cardFocusChanged(
        listID: listID,
        itemID: "item-36",
        itemIndex: 36,
        isFocused: true
      )
    )

    let allowed = Set(
      (0..<60).filter { controller.allowsImages(listID: listID, itemIndex: $0) }
    )
    XCTAssertEqual(allowed, Set(0...11).union(24...53))
  }

  func testNewListRestoresOnlyTopRowsEvenWithIdenticalItemsAndRejectsOldFocus() {
    let oldListID = UUID()
    let newListID = UUID()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listID: oldListID, itemCount: 60, lifecycle: lifecycle)
    XCTAssertTrue(
      controller.cardFocusChanged(
        listID: oldListID,
        itemID: "item-18",
        itemIndex: 18,
        isFocused: true
      )
    )

    controller.reconcile(listID: newListID, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listID: oldListID,
        itemID: "item-18",
        itemIndex: 18,
        isFocused: true
      )
    )
    XCTAssertFalse(controller.allowsImages(listID: oldListID, itemIndex: 18))
    XCTAssertTrue(controller.allowsImages(listID: newListID, itemIndex: 0))
  }

  func testPaginatorAppendKeepsArmedWindow() {
    let listID = UUID()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listID: listID, itemCount: 30, lifecycle: lifecycle)
    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    controller.reconcile(listID: listID, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertTrue(controller.allowsImages(listID: listID, itemIndex: 30))
  }

  func testFirstPaginatorPageRestoresVisibleTopWithoutFocus() {
    let listID = UUID()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listID: listID, itemCount: 0, lifecycle: lifecycle)
    XCTAssertEqual(controller.activation, .disarmed)

    controller.reconcile(listID: listID, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertTrue(controller.allowsImages(listID: listID, itemIndex: 0))
    XCTAssertTrue(controller.allowsImages(listID: listID, itemIndex: 11))
    XCTAssertFalse(controller.allowsImages(listID: listID, itemIndex: 12))
  }

  func testNavigationDepthDoesNotDisarmButActualStackReleaseDoes() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    _ = coordinator.push(resourceRequest("B"))
    _ = coordinator.push(resourceRequest("C"))
    XCTAssertEqual(coordinator.rootLifecycle.phase, .released)
    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertEqual(controller.observedStackReleaseEpoch, 0)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listID: listID,
        itemID: "item-24",
        itemIndex: 24,
        isFocused: true
      ),
      "隐藏父页的迟到焦点不能改变已保存窗口"
    )

    coordinator.setStackForeground(false)
    XCTAssertEqual(controller.activation, .disarmed)
    XCTAssertEqual(controller.observedStackReleaseEpoch, 1)
  }

  func testRapidTabRoundTripWithoutActualReleaseKeepsArmedWindow() async throws {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance()),
      tabTransitionImageRetention: .milliseconds(20)
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackPresentation(isSelected: false, scenePhase: .active)
    coordinator.setStackPresentation(isSelected: true, scenePhase: .active)
    try await Task.sleep(for: .milliseconds(40))

    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertEqual(controller.observedStackReleaseEpoch, 0)
  }

  func testTabInteractionGateUpdatesSynchronouslyWithoutViewOnChange() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackPresentation(isSelected: false, scenePhase: .active)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listID: listID,
        itemID: "item-24",
        itemIndex: 24,
        isFocused: true
      )
    )
    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))

    coordinator.setStackPresentation(isSelected: true, scenePhase: .active)
    XCTAssertTrue(
      controller.cardFocusChanged(
        listID: listID,
        itemID: "item-24",
        itemIndex: 24,
        isFocused: true
      )
    )
    XCTAssertEqual(controller.activation, .armed(itemID: "item-24", itemIndex: 24))
  }

  func testLateFocusCannotRearmReleasedGrid() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackForeground(false)
    XCTAssertEqual(controller.activation, .disarmed)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listID: listID,
        itemID: "item-18",
        itemIndex: 18,
        isFocused: true
      )
    )
    XCTAssertEqual(controller.activation, .disarmed)

    coordinator.setStackForeground(true)
    XCTAssertEqual(controller.activation, .visibleTop)
  }

  func testReleasedStackReturnRestoresOnlyTopRowsBeforeCardFocus() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    let topSlot = makeSlot(key: "top", lifecycle: coordinator.rootLifecycle)
    let deepSlot = makeSlot(key: "deep", lifecycle: coordinator.rootLifecycle)
    topSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listID: listID,
        itemID: "item-0",
        itemIndex: 0
      )
    )
    deepSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listID: listID,
        itemID: "item-36",
        itemIndex: 36
      )
    )
    let topDemand = UUID()
    let deepDemand = UUID()
    topSlot.setDemand(id: topDemand, isEnabled: true)
    deepSlot.setDemand(id: deepDemand, isEnabled: true)
    XCTAssertEqual(topSlot.retrievalStartCount, 1)
    XCTAssertEqual(deepSlot.retrievalStartCount, 0)

    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-36",
      itemIndex: 36,
      isFocused: true
    )
    XCTAssertEqual(deepSlot.retrievalStartCount, 1)

    coordinator.setStackForeground(false)
    coordinator.setStackForeground(true)
    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertEqual(topSlot.retrievalStartCount, 2, "切回 Tab 后顶部两行应立即恢复")
    XCTAssertEqual(deepSlot.retrievalStartCount, 1, "停在 Tab 栏时不能恢复旧深处需求")

    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-36",
      itemIndex: 36,
      isFocused: true
    )
    XCTAssertEqual(deepSlot.retrievalStartCount, 2)
    topSlot.removeDemand(id: topDemand)
    deepSlot.removeDemand(id: deepDemand)
  }

  func testSlotGateStartsTopRowsButNeverOldDeepWindowBeforeNewFocus() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listID = UUID()
    let controller = makeController(
      listID: listID,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    let topSlot = makeSlot(key: "top", lifecycle: coordinator.rootLifecycle)
    let deepSlot = makeSlot(key: "deep", lifecycle: coordinator.rootLifecycle)
    topSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listID: listID,
        itemID: "item-0",
        itemIndex: 0
      )
    )
    deepSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listID: listID,
        itemID: "item-36",
        itemIndex: 36
      )
    )
    let topDemand = UUID()
    let deepDemand = UUID()
    topSlot.setDemand(id: topDemand, isEnabled: true)
    deepSlot.setDemand(id: deepDemand, isEnabled: true)
    XCTAssertEqual(topSlot.retrievalStartCount, 1)
    XCTAssertEqual(deepSlot.retrievalStartCount, 0)

    controller.cardFocusChanged(
      listID: listID,
      itemID: "item-36",
      itemIndex: 36,
      isFocused: true
    )

    XCTAssertEqual(topSlot.retrievalStartCount, 1)
    XCTAssertEqual(deepSlot.retrievalStartCount, 1, "深处 demand 只能由真实焦点开启")

    topSlot.setDemand(id: topDemand, isEnabled: false)
    deepSlot.setDemand(id: deepDemand, isEnabled: false)
  }

  private func makeController(
    listID: UUID,
    itemCount: Int,
    lifecycle: PageImageLifecycle
  ) -> GridImageLifecycleController {
    let controller = GridImageLifecycleController(
      listID: listID,
      itemIDs: itemIDs(itemCount),
      columnCount: columnCount,
      imageLifecycle: lifecycle
    )
    controller.pageImageStackStateDidChange(
      PageImageStackState(
        isInteractive: true,
        isForeground: true,
        releaseEpoch: lifecycle.stackReleaseEpoch
      )
    )
    return controller
  }

  private func makeSlot(key: String, lifecycle: PageImageLifecycle) -> PageImageSlot {
    PageImageSlot(
      key: key,
      url: URL(string: "https://example.invalid/\(key).jpg")!,
      processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
      role: .content,
      skipsMemoryCache: true,
      loadsDiskFileSynchronously: false,
      fadeDuration: 0,
      performsImageRetrieval: false,
      lifecycle: lifecycle
    )
  }

  private func itemIDs(_ count: Int) -> [MediaInfo.ID] {
    (0..<count).map { "item-\($0)" }
  }

  private func resourceRequest(_ keyword: String) -> ResourceSearchRequest {
    ResourceSearchRequest(
      keyword: keyword,
      type: nil,
      area: nil,
      title: nil,
      year: nil,
      season: nil,
      mediaInfo: nil,
      sites: nil
    )
  }
}
