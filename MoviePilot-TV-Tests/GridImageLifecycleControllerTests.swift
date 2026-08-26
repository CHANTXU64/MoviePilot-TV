import Kingfisher
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class GridImageLifecycleControllerTests: XCTestCase {
  private let columnCount = 6

  func testVisibleGridStartsWithTopRowsAndFirstValidFocusOpensCurrentWindow() {
    let listIdentity = GridListIdentity.make()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listIdentity: listIdentity, itemCount: 60, lifecycle: lifecycle)

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertTrue(controller.allowsImages(listIdentity: listIdentity, itemIndex: 0))
    XCTAssertFalse(controller.allowsImages(listIdentity: listIdentity, itemIndex: 12))

    XCTAssertTrue(
      controller.cardFocusChanged(
        listIdentity: listIdentity,
        itemID: "item-36",
        itemIndex: 36,
        isFocused: true
      )
    )

    let allowed = Set(
      (0..<60).filter { controller.allowsImages(listIdentity: listIdentity, itemIndex: $0) }
    )
    XCTAssertEqual(allowed, Set(0...11).union(24...53))
  }

  func testNewListRestoresOnlyTopRowsEvenWithIdenticalItemsAndRejectsOldFocus() {
    let oldListIdentity = GridListIdentity.make()
    let newListIdentity = GridListIdentity.make()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listIdentity: oldListIdentity, itemCount: 60, lifecycle: lifecycle)
    XCTAssertTrue(
      controller.cardFocusChanged(
        listIdentity: oldListIdentity,
        itemID: "item-18",
        itemIndex: 18,
        isFocused: true
      )
    )

    controller.reconcile(listIdentity: newListIdentity, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: oldListIdentity,
        itemID: "item-18",
        itemIndex: 18,
        isFocused: true
      )
    )
    XCTAssertFalse(controller.allowsImages(listIdentity: oldListIdentity, itemIndex: 18))
    XCTAssertTrue(controller.allowsImages(listIdentity: newListIdentity, itemIndex: 0))
  }

  func testNewListSlotRegistrationSynchronouslyAdoptsGenerationAndOldSlotCannotRollBack() {
    let sharedID = UUID()
    let oldListIdentity = GridListIdentity.make(id: sharedID)
    let newListIdentity = GridListIdentity.make(id: sharedID)
    let lifecycle = PageImageLifecycle()
    let controller = makeController(
      listIdentity: oldListIdentity,
      itemCount: 60,
      lifecycle: lifecycle
    )
    let newSlot = makeSlot(key: "new-generation", lifecycle: lifecycle)
    let oldSlot = makeSlot(key: "old-generation", lifecycle: lifecycle)

    newSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: newListIdentity,
        itemIDs: itemIDs(60),
        itemID: "item-0",
        itemIndex: 0
      )
    )
    let newDemand = UUID()
    newSlot.setDemand(id: newDemand, isEnabled: true)

    XCTAssertEqual(controller.listIdentity, newListIdentity)
    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertEqual(newSlot.retrievalStartCount, 1)

    oldSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: oldListIdentity,
        itemIDs: itemIDs(60),
        itemID: "item-0",
        itemIndex: 0
      )
    )
    let oldDemand = UUID()
    oldSlot.setDemand(id: oldDemand, isEnabled: true)

    XCTAssertEqual(controller.listIdentity, newListIdentity)
    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertEqual(oldSlot.retrievalStartCount, 0)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: oldListIdentity,
        itemID: "item-0",
        itemIndex: 0,
        isFocused: true
      )
    )

    newSlot.removeDemand(id: newDemand)
    oldSlot.removeDemand(id: oldDemand)
  }

  func testPaginatorAppendKeepsArmedWindow() {
    let listIdentity = GridListIdentity.make()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listIdentity: listIdentity, itemCount: 30, lifecycle: lifecycle)
    controller.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    controller.reconcile(listIdentity: listIdentity, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertTrue(controller.allowsImages(listIdentity: listIdentity, itemIndex: 30))
  }

  func testFirstPaginatorPageRestoresVisibleTopWithoutFocus() {
    let listIdentity = GridListIdentity.make()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(listIdentity: listIdentity, itemCount: 0, lifecycle: lifecycle)
    XCTAssertEqual(controller.activation, .disarmed)

    controller.reconcileEventSnapshot(listIdentity: listIdentity, itemIDs: itemIDs(60))

    XCTAssertEqual(controller.activation, .visibleTop)
    XCTAssertTrue(controller.allowsImages(listIdentity: listIdentity, itemIndex: 0))
    XCTAssertTrue(controller.allowsImages(listIdentity: listIdentity, itemIndex: 11))
    XCTAssertFalse(controller.allowsImages(listIdentity: listIdentity, itemIndex: 12))
  }

  func testEventSnapshotCannotRestorePreRefreshItemsOrReplaceCurrentGeneration() {
    let oldIdentity = GridListIdentity.make()
    let lifecycle = PageImageLifecycle()
    let controller = makeController(
      listIdentity: oldIdentity,
      itemCount: 60,
      lifecycle: lifecycle
    )
    let refreshedIdentity = oldIdentity.advanced()

    controller.reconcile(listIdentity: refreshedIdentity, itemIDs: [])
    XCTAssertFalse(
      controller.reconcileEventSnapshot(
        listIdentity: oldIdentity,
        itemIDs: itemIDs(60)
      )
    )
    XCTAssertEqual(controller.listIdentity, refreshedIdentity)
    XCTAssertEqual(controller.activation, .disarmed)

    let replacementIDs = (0..<60).map { "replacement-\($0)" }
    controller.reconcile(listIdentity: refreshedIdentity, itemIDs: replacementIDs)
    XCTAssertFalse(
      controller.reconcileEventSnapshot(
        listIdentity: refreshedIdentity,
        itemIDs: itemIDs(60)
      )
    )
    XCTAssertTrue(controller.allowsImages(listIdentity: refreshedIdentity, itemIndex: 0))
  }

  func testNavigationDepthDoesNotDisarmButActualStackReleaseDoes() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listIdentity: listIdentity,
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
        listIdentity: listIdentity,
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
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listIdentity: listIdentity,
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

  func testSelectedSceneBackgroundKeepsArmedWindowWithoutAcceptingFocus() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackPresentation(isSelected: true, scenePhase: .inactive)

    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertEqual(controller.observedStackReleaseEpoch, 0)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: listIdentity,
        itemID: "item-24",
        itemIndex: 24,
        isFocused: true
      ),
      "App 非 Active 时不能接受新的焦点窗口"
    )

    coordinator.setStackPresentation(isSelected: true, scenePhase: .active)

    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))
    XCTAssertEqual(controller.observedStackReleaseEpoch, 0)
  }

  func testTabInteractionGateUpdatesSynchronouslyWithoutViewOnChange() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackPresentation(isSelected: false, scenePhase: .active)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: listIdentity,
        itemID: "item-24",
        itemIndex: 24,
        isFocused: true
      )
    )
    XCTAssertEqual(controller.activation, .armed(itemID: "item-18", itemIndex: 18))

    coordinator.setStackPresentation(isSelected: true, scenePhase: .active)
    XCTAssertTrue(
      controller.cardFocusChanged(
        listIdentity: listIdentity,
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
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    controller.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: "item-18",
      itemIndex: 18,
      isFocused: true
    )

    coordinator.setStackForeground(false)
    XCTAssertEqual(controller.activation, .disarmed)
    XCTAssertFalse(
      controller.cardFocusChanged(
        listIdentity: listIdentity,
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
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    let topSlot = makeSlot(key: "top", lifecycle: coordinator.rootLifecycle)
    let deepSlot = makeSlot(key: "deep", lifecycle: coordinator.rootLifecycle)
    topSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: listIdentity,
        itemID: "item-0",
        itemIndex: 0
      )
    )
    deepSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: listIdentity,
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
      listIdentity: listIdentity,
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
      listIdentity: listIdentity,
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
    let listIdentity = GridListIdentity.make()
    let controller = makeController(
      listIdentity: listIdentity,
      itemCount: 60,
      lifecycle: coordinator.rootLifecycle
    )
    let topSlot = makeSlot(key: "top", lifecycle: coordinator.rootLifecycle)
    let deepSlot = makeSlot(key: "deep", lifecycle: coordinator.rootLifecycle)
    topSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: listIdentity,
        itemID: "item-0",
        itemIndex: 0
      )
    )
    deepSlot.setGridImageDemandContext(
      GridImageDemandContext(
        controller: controller,
        listIdentity: listIdentity,
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
      listIdentity: listIdentity,
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
    listIdentity: GridListIdentity,
    itemCount: Int,
    lifecycle: PageImageLifecycle
  ) -> GridImageLifecycleController {
    let controller = GridImageLifecycleController(
      listIdentity: listIdentity,
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
