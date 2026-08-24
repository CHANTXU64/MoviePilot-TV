import Kingfisher
import SwiftUI
import UIKit
import XCTest

@testable import MoviePilot_TV

@MainActor
final class ImageLoadWindowTests: XCTestCase {
  func testMediaHorizontalWindowMovesInBothDirections() {
    let initial = Set(
      (0..<20).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 20, anchorIndex: 5, cardKind: .media)
      }
    )
    let forward = Set(
      (0..<20).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 20, anchorIndex: 8, cardKind: .media)
      }
    )
    let backward = Set(
      (0..<20).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 20, anchorIndex: 4, cardKind: .media)
      }
    )

    XCTAssertEqual(initial, Set(0...11))
    XCTAssertEqual(forward.subtracting(initial), Set(12...14))
    XCTAssertEqual(initial.subtracting(forward), Set(0...1))
    XCTAssertEqual(backward, Set(0...10))
    XCTAssertEqual(forward.count, 13)
  }

  func testPersonHorizontalWindowKeepsSeventeenItems() {
    let loaded = Set(
      (0..<30).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 30, anchorIndex: 12, cardKind: .person)
      }
    )

    XCTAssertEqual(loaded, Set(4...20))
    XCTAssertEqual(loaded.count, 17)
  }

  func testGridWindowKeepsWholeRowsAroundFocus() {
    let loaded = Set(
      (0..<60).filter {
        ImageLoadWindow.containsGridItem(
          at: $0,
          itemCount: 60,
          anchorIndex: 36,
          columnCount: 6
        )
      }
    )

    XCTAssertEqual(loaded, Set(0...11).union(24...53))
    XCTAssertEqual(loaded.count, 7 * 6)
  }

  func testGridWithoutFocusedCardLoadsAnchorRowAndTwoRowsAfterIt() {
    let loaded = Set(
      (0..<60).filter {
        ImageLoadWindow.containsGridItem(
          at: $0,
          itemCount: 60,
          anchorIndex: nil,
          columnCount: 6
        )
      }
    )

    XCTAssertEqual(loaded, Set(0..<18))
  }

  func testImageWindowsDoNotCompensatePastListBoundaries() {
    let media = Set(
      (0..<20).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 20, anchorIndex: 19, cardKind: .media)
      }
    )
    let people = Set(
      (0..<30).filter {
        ImageLoadWindow.containsHorizontalItem(
          at: $0, itemCount: 30, anchorIndex: 29, cardKind: .person)
      }
    )
    let grid = Set(
      (0..<60).filter {
        ImageLoadWindow.containsGridItem(
          at: $0, itemCount: 60, anchorIndex: 59, columnCount: 6)
      }
    )

    XCTAssertEqual(media, Set(13...19))
    XCTAssertEqual(people, Set(21...29))
    XCTAssertEqual(grid, Set(0...11).union(42...59))
  }

  func testNavigationLifecycleUsesOneReversibleStateMachine() async throws {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance()),
      removedLifecycleRetention: .milliseconds(1)
    )
    coordinator.setStackForeground(true)

    let first = coordinator.push(resourceRequest("A"))
    let firstLifecycle = coordinator.lifecycle(for: first)
    let second = coordinator.push(resourceRequest("B"))
    let secondLifecycle = coordinator.lifecycle(for: second)
    let third = coordinator.push(resourceRequest("C"))
    let thirdLifecycle = coordinator.lifecycle(for: third)

    XCTAssertEqual(coordinator.rootLifecycle.phase, .released)
    XCTAssertEqual(firstLifecycle.phase, .released)
    XCTAssertEqual(secondLifecycle.phase, .adjacent)
    XCTAssertEqual(thirdLifecycle.phase, .active)
    XCTAssertFalse(firstLifecycle.keepsContentImages)

    coordinator.path.removeLast()

    XCTAssertTrue(thirdLifecycle.isRemoved)
    XCTAssertTrue(thirdLifecycle.keepsContentImages, "出栈转场期间不应把 outgoing 页面改成空占位")
    XCTAssertEqual(firstLifecycle.phase, .adjacent)
    XCTAssertEqual(secondLifecycle.phase, .active)
    XCTAssertTrue(firstLifecycle.keepsContentImages)

    await waitUntil("removed route lifecycle to release") {
      thirdLifecycle.phase == .released
    }
    XCTAssertEqual(thirdLifecycle.phase, .released)
    XCTAssertFalse(thirdLifecycle.keepsContentImages)
  }

  func testLifecycleSynchronouslyReleasesAndRewarmsRegisteredContentResources() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)

    let first = coordinator.push(resourceRequest("A"))
    let firstLifecycle = coordinator.lifecycle(for: first)
    let resource = ImageResourceProbe(role: .content)
    let activePageResource = ImageResourceProbe(role: .activePage)
    firstLifecycle.register(resource)
    firstLifecycle.register(activePageResource)

    _ = coordinator.push(resourceRequest("B"))
    XCTAssertTrue(resource.isLoaded)
    XCTAssertFalse(activePageResource.isLoaded, "相邻页只能预热内容窗口，不能恢复 active-only 图片")

    _ = coordinator.push(resourceRequest("C"))
    XCTAssertFalse(resource.isLoaded)
    XCTAssertEqual(firstLifecycle.loadedImageResourceCount, 0)

    coordinator.path.removeLast()
    XCTAssertTrue(resource.isLoaded, "C→B 后 A 进入 adjacent，内容图片应立即重新解码预热")
    XCTAssertFalse(activePageResource.isLoaded)
    XCTAssertEqual(firstLifecycle.loadedImageResourceCount, 1)
  }

  func testManagedImageSurfaceClearsUIImageAndLayerWhenPermissionIsRevoked() {
    let imageView = PageManagedImageView()
    let demandLease = PageImageDemandLease()
    let slot = PageImageSlot(
      key: "surface-test",
      url: URL(string: "https://example.com/poster.jpg")!,
      processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
      role: .content,
      skipsMemoryCache: true,
      loadsDiskFileSynchronously: false,
      fadeDuration: 0,
      performsImageRetrieval: false
    )
    demandLease.bind(to: slot, isEnabled: false)
    slot.attach(imageView, demandID: demandLease.id)
    imageView.image = UIImage(systemName: "film")
    imageView.layer.contents = imageView.image?.cgImage
    imageView.layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "fade")

    XCTAssertNotNil(imageView.image)
    slot.setPageImagePermissions(contentAllowed: false, activePageAllowed: false)

    XCTAssertNil(imageView.image)
    XCTAssertNil(imageView.layer.contents)
    XCTAssertNil(imageView.layer.animationKeys())
    slot.detach(imageView)
    demandLease.cancel()
  }

  func testLogicalDemandSurvivesSurfaceDismantleUntilTheViewLeaseEnds() {
    let lifecycle = PageImageLifecycle(phase: .released)
    let slot = lifecycle.retainedImageResource(for: "lease") {
      PageImageSlot(
        key: "lease",
        url: URL(string: "https://example.invalid/lease.jpg")!,
        processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
        role: .content,
        skipsMemoryCache: true,
        loadsDiskFileSynchronously: false,
        fadeDuration: 0,
        performsImageRetrieval: false,
        lifecycle: lifecycle
      )
    }
    let demandLease = PageImageDemandLease()
    let imageView = PageManagedImageView()

    demandLease.bind(to: slot, isEnabled: true)
    slot.attach(imageView, demandID: demandLease.id)
    slot.detach(imageView)

    XCTAssertEqual(lifecycle.retainedImageResourceCount, 1)
    demandLease.cancel()
    XCTAssertEqual(lifecycle.retainedImageResourceCount, 0)
  }

  func testLogicalNodeRemovalDiscardsManifestEvenWhilePageIsHidden() {
    let lifecycle = PageImageLifecycle(phase: .adjacent)
    let slot = makeSlot(key: "hidden-node", lifecycle: lifecycle)
    var demandLease: PageImageDemandLease? = PageImageDemandLease()

    demandLease?.bind(to: slot, isEnabled: true)
    demandLease = nil

    XCTAssertEqual(
      lifecycle.retainedImageResourceCount,
      0,
      "隐藏页删除的数据项不能变成永久 orphan manifest"
    )
    XCTAssertEqual(slot.retrievalStartCount, 0)
  }

  func testMovingLogicalDemandToANewURLDiscardsTheOldManifestSlot() {
    let lifecycle = PageImageLifecycle(phase: .released)
    let oldSlot = makeSlot(key: "old", lifecycle: lifecycle)
    let newSlot = makeSlot(key: "new", lifecycle: lifecycle)
    let demandLease = PageImageDemandLease()

    demandLease.bind(to: oldSlot, isEnabled: true)
    XCTAssertEqual(lifecycle.retainedImageResourceCount, 2)

    demandLease.bind(to: newSlot, isEnabled: true)
    XCTAssertEqual(lifecycle.retainedImageResourceCount, 1)

    demandLease.cancel()
    XCTAssertEqual(lifecycle.retainedImageResourceCount, 0)
  }

  func testSharedSlotOnlyClearsTheSurfaceWhoseDemandWasDisabled() {
    let slot = PageImageSlot(
      key: "shared",
      url: URL(string: "https://example.invalid/shared.jpg")!,
      processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
      role: .content,
      skipsMemoryCache: true,
      loadsDiskFileSynchronously: false,
      fadeDuration: 0,
      performsImageRetrieval: false
    )
    let firstLease = PageImageDemandLease()
    let secondLease = PageImageDemandLease()
    let firstSurface = PageManagedImageView()
    let secondSurface = PageManagedImageView()
    let placeholder = UIImage(systemName: "film")

    firstLease.bind(to: slot, isEnabled: true)
    secondLease.bind(to: slot, isEnabled: true)
    slot.attach(firstSurface, demandID: firstLease.id)
    slot.attach(secondSurface, demandID: secondLease.id)
    firstSurface.image = placeholder
    secondSurface.image = placeholder

    secondLease.bind(to: slot, isEnabled: false)

    XCTAssertNotNil(firstSurface.image)
    XCTAssertNil(secondSurface.image)

    slot.detach(firstSurface)
    slot.detach(secondSurface)
    firstLease.cancel()
    secondLease.cancel()
  }

  func testSharedSlotRestoresDecodedImageWhenDisabledDemandIsReenabled() throws {
    let slot = PageImageSlot(
      key: "shared-restore",
      url: URL(string: "https://example.invalid/shared-restore.jpg")!,
      processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
      role: .content,
      skipsMemoryCache: true,
      loadsDiskFileSynchronously: false,
      fadeDuration: 0.25,
      performsImageRetrieval: false
    )
    let firstLease = PageImageDemandLease()
    let secondLease = PageImageDemandLease()
    let firstSurface = PageManagedImageView()
    let secondSurface = PageManagedImageView()
    let decodedImage = try XCTUnwrap(UIImage(systemName: "film.fill"))

    firstLease.bind(to: slot, isEnabled: true)
    secondLease.bind(to: slot, isEnabled: true)
    slot.attach(firstSurface, demandID: firstLease.id)
    slot.attach(secondSurface, demandID: secondLease.id)
    slot.acceptRetrievedImage(decodedImage)

    XCTAssertTrue(firstSurface.image === decodedImage)
    XCTAssertTrue(secondSurface.image === decodedImage)
    XCTAssertEqual(slot.retrievalStartCount, 1)

    firstLease.bind(to: slot, isEnabled: false)
    XCTAssertNil(firstSurface.image)
    XCTAssertTrue(secondSurface.image === decodedImage)

    firstLease.bind(to: slot, isEnabled: true)
    XCTAssertTrue(firstSurface.image === decodedImage)
    XCTAssertTrue(secondSurface.image === decodedImage)
    XCTAssertEqual(slot.retrievalStartCount, 1)

    slot.detach(firstSurface)
    slot.detach(secondSurface)
    firstLease.cancel()
    secondLease.cancel()
  }

  func testRepeatedEnabledUpdatesDoNotStartDuplicateRetrievals() {
    let slot = PageImageSlot(
      key: "single-retrieval",
      url: URL(string: "https://example.invalid/\(UUID().uuidString).jpg")!,
      processor: DownsamplingImageProcessor(size: CGSize(width: 100, height: 150)),
      role: .content,
      skipsMemoryCache: true,
      loadsDiskFileSynchronously: false,
      fadeDuration: 0,
      performsImageRetrieval: false
    )
    let demandLease = PageImageDemandLease()

    demandLease.bind(to: slot, isEnabled: true)
    demandLease.bind(to: slot, isEnabled: true)
    demandLease.bind(to: slot, isEnabled: true)

    XCTAssertEqual(slot.retrievalStartCount, 1)
    slot.setPageImagePermissions(contentAllowed: false, activePageAllowed: false)
    demandLease.cancel()
  }

  func testLifecycleRetainsImageManifestWithoutAUIViewOwner() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let first = coordinator.push(resourceRequest("A"))
    let lifecycle = coordinator.lifecycle(for: first)

    var resource: ImageResourceProbe? = ImageResourceProbe(role: .content)
    weak var retainedResource = resource
    _ = lifecycle.retainedImageResource(for: "manifest") {
      resource!
    }
    resource = nil

    XCTAssertNotNil(retainedResource)
    _ = coordinator.push(resourceRequest("B"))
    XCTAssertTrue(retainedResource?.isLoaded == true)
    _ = coordinator.push(resourceRequest("C"))
    XCTAssertTrue(retainedResource?.isLoaded == false)

    coordinator.path.removeLast()
    XCTAssertTrue(
      retainedResource?.isLoaded == true,
      "即使 UIView 已销毁，C→B 后 lifecycle 仍应通过 manifest 恢复 A 的内容预热"
    )
  }

  func testBackgroundIsActiveOnlyAndTabsGateAllImages() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let entry = coordinator.push(resourceRequest("detail"))
    let lifecycle = coordinator.lifecycle(for: entry)

    XCTAssertTrue(lifecycle.keepsActivePageImages)
    XCTAssertTrue(coordinator.rootLifecycle.keepsContentImages)
    XCTAssertFalse(coordinator.rootLifecycle.keepsActivePageImages)

    coordinator.setStackForeground(false)

    XCTAssertFalse(lifecycle.keepsActivePageImages)
    XCTAssertFalse(lifecycle.keepsContentImages)
    XCTAssertFalse(coordinator.rootLifecycle.keepsContentImages)
  }

  func testTabTransitionRetainsImagesButInvalidatesNavigationImmediately() async throws {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance()),
      tabTransitionImageRetention: .milliseconds(20)
    )
    coordinator.setStackForeground(true)
    let entry = coordinator.push(resourceRequest("detail"))
    let lifecycle = coordinator.lifecycle(for: entry)
    let source = coordinator.sourceToken()

    coordinator.setStackPresentation(isSelected: false, scenePhase: .active)

    XCTAssertTrue(lifecycle.keepsContentImages, "Tab 转场期间不能先把画面清空")
    XCTAssertTrue(
      TransferHistoryView.shouldMountRows(
        isSelected: false,
        isStackForeground: coordinator.rootLifecycle.isStackForeground
      ),
      "Tab 转场期间整理行 DOM 应复用同一 Stack 前台保留"
    )
    XCTAssertNil(
      coordinator.push(resourceRequest("late"), ifCurrent: source),
      "离开 Tab 后应立即拒绝迟到的异步导航"
    )

    await waitUntil("Tab transition image retention to expire") {
      !lifecycle.keepsContentImages
    }
    XCTAssertFalse(lifecycle.keepsContentImages)
    XCTAssertFalse(
      TransferHistoryView.shouldMountRows(
        isSelected: false,
        isStackForeground: coordinator.rootLifecycle.isStackForeground
      )
    )
  }

  func testReturningToTabCancelsPendingImageReleaseAndBackgroundingDoesNotDelay() async throws {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance()),
      tabTransitionImageRetention: .milliseconds(20)
    )
    coordinator.setStackForeground(true)

    coordinator.setStackPresentation(isSelected: false, scenePhase: .active)
    coordinator.setStackPresentation(isSelected: true, scenePhase: .active)
    await settleAsyncWindow()
    XCTAssertTrue(coordinator.rootLifecycle.keepsContentImages)
    XCTAssertTrue(
      TransferHistoryView.shouldMountRows(
        isSelected: true,
        isStackForeground: coordinator.rootLifecycle.isStackForeground
      )
    )

    coordinator.setStackPresentation(isSelected: true, scenePhase: .background)
    XCTAssertFalse(coordinator.rootLifecycle.keepsContentImages)
  }

  func testSharedPresentationReleaseSchedulerWaitsAndSupportsCancellation() async throws {
    let scheduler = PresentationReleaseScheduler()
    var releaseCount = 0

    scheduler.schedule(after: .milliseconds(20)) {
      releaseCount += 1
    }
    XCTAssertTrue(scheduler.isPending)
    XCTAssertEqual(releaseCount, 0)

    await waitUntil("shared presentation release to execute") {
      !scheduler.isPending && releaseCount == 1
    }
    XCTAssertFalse(scheduler.isPending)
    XCTAssertEqual(releaseCount, 1)

    scheduler.schedule(after: .milliseconds(20)) {
      releaseCount += 1
    }
    scheduler.cancel()
    await settleAsyncWindow()
    XCTAssertEqual(releaseCount, 1)
  }

  func testGridPreloadDebouncerCancelsOldGenerationWithoutCancellingNewSameItem() async throws {
    let oldIdentity = GridListIdentity.make()
    let newIdentity = oldIdentity.advanced()
    let media = MediaInfo(tmdb_id: 990_001, title: "同一媒体", type: "电影")
    let stackID = UUID()
    var preloadCount = 0
    let debouncer = GridPreloadDebouncer { _, _ in
      preloadCount += 1
    }

    debouncer.schedule(
      for: media,
      listIdentity: oldIdentity,
      stackID: stackID,
      delayMs: 60
    )
    debouncer.schedule(
      for: media,
      listIdentity: newIdentity,
      stackID: stackID,
      delayMs: 20
    )

    debouncer.cancelTasks(olderThan: newIdentity)
    debouncer.cancelTasks(olderThan: oldIdentity)
    debouncer.cancel(itemID: media.id, listIdentity: oldIdentity)
    await waitUntil("new grid preload generation to execute") {
      preloadCount == 1
    }
    await settleAsyncWindow(for: .milliseconds(100))

    XCTAssertEqual(preloadCount, 1)
  }

  func testGridPreloadDebouncerListAdvanceCancelsPendingTaskWithoutFocusLoss() async throws {
    let oldIdentity = GridListIdentity.make()
    let newIdentity = oldIdentity.advanced()
    let media = MediaInfo(tmdb_id: 990_002, title: "旧列表媒体", type: "电影")
    var preloadCount = 0
    let debouncer = GridPreloadDebouncer { _, _ in
      preloadCount += 1
    }

    debouncer.schedule(
      for: media,
      listIdentity: oldIdentity,
      stackID: UUID(),
      delayMs: 20
    )
    debouncer.cancelTasks(olderThan: newIdentity)
    await settleAsyncWindow()

    XCTAssertEqual(preloadCount, 0)
  }

  func testBackgroundingStackImmediatelyFinishesRetiringPage() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance()),
      removedLifecycleRetention: .seconds(10)
    )
    coordinator.setStackForeground(true)
    let entry = coordinator.push(resourceRequest("retiring"))
    let lifecycle = coordinator.lifecycle(for: entry)

    coordinator.path.removeLast()
    XCTAssertTrue(lifecycle.keepsContentImages)

    coordinator.setStackForeground(false)
    XCTAssertEqual(lifecycle.phase, .released)
    XCTAssertFalse(lifecycle.keepsContentImages)
  }

  func testSameMediaUsesIndependentRouteOwnersAcrossStacks() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let firstStack = ImageNavigationCoordinator(mediaPreloader: preloader)
    let secondStack = ImageNavigationCoordinator(mediaPreloader: preloader)
    let media = MediaInfo(tmdb_id: 880_001, title: "跨栈同媒体", type: "电影")

    let firstEntry = firstStack.push(media)
    let secondEntry = secondStack.push(media)

    XCTAssertNotEqual(firstEntry.id, secondEntry.id)
    XCTAssertNotNil(preloader.peekTask(for: media))

    firstStack.path.removeLast()
    XCTAssertNotNil(preloader.peekTask(for: media))

    secondStack.path.removeLast()
    XCTAssertNil(preloader.peekTask(for: media))
  }

  func testDestinationOnlyUsesTaskAcquiredByNavigationEntry() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: preloader,
      removedLifecycleRetention: .milliseconds(1)
    )
    let media = MediaInfo(tmdb_id: 880_002, title: "entry task", type: "电影")

    let entry = coordinator.push(media)
    let entryTask = try XCTUnwrap(coordinator.preloadTask(for: entry))
    XCTAssertTrue(entryTask === preloader.peekTask(for: media))

    coordinator.path.removeLast()
    XCTAssertNil(preloader.peekTask(for: media))
    XCTAssertTrue(entryTask === coordinator.preloadTask(for: entry), "Pop 转场只能复用原 task")

    await waitUntil("retiring route task to release") {
      coordinator.preloadTask(for: entry) == nil
    }
    XCTAssertNil(coordinator.preloadTask(for: entry))
  }

  func testAsyncNavigationRejectsStaleSourceToken() {
    let coordinator = ImageNavigationCoordinator(
      mediaPreloader: MediaPreloader(apiService: .testingInstance())
    )
    coordinator.setStackForeground(true)
    let staleSource = coordinator.sourceToken()

    _ = coordinator.push(resourceRequest("new top"))
    let media = MediaInfo(tmdb_id: 880_003, title: "late result", type: "电影")

    XCTAssertNil(coordinator.push(media, ifCurrent: staleSource))
    XCTAssertEqual(coordinator.path.count, 1)
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

  private func settleAsyncWindow(for duration: Duration = .milliseconds(75)) async {
    try? await Task.sleep(for: duration)
  }

  private func makeSlot(key: String, lifecycle: PageImageLifecycle) -> PageImageSlot {
    lifecycle.retainedImageResource(for: key) {
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
  }
}

@MainActor
private final class ImageResourceProbe: PageImageResource {
  private let role: PageImageRole
  private(set) var isLoaded = false

  init(role: PageImageRole) {
    self.role = role
  }

  var hasLoadedPageImage: Bool {
    isLoaded
  }

  func setPageImagePermissions(contentAllowed: Bool, activePageAllowed: Bool) {
    switch role {
    case .content:
      isLoaded = contentAllowed
    case .activePage:
      isLoaded = activePageAllowed
    }
  }
}
