import XCTest
import SwiftUI

@testable import MoviePilot_TV

@MainActor
final class DownloadTaskViewRefreshLoopTests: XCTestCase {
  func testAutoRefreshWaitsBeforeFirstPollingLoadAfterInitialLoad() async {
    var events: [String] = []
    var refreshCount = 0

    await DownloadTaskView.runAutoRefresh(
      initialLoad: {
        events.append("initialLoad")
      },
      loadDownloads: {
        events.append("loadDownloads")
        refreshCount += 1
      },
      sleep: { interval in
        XCTAssertEqual(interval, DownloadTaskView.autoRefreshIntervalNanoseconds)
        events.append("sleep")
      },
      isCancelled: {
        refreshCount >= 1
      }
    )

    XCTAssertEqual(events, ["initialLoad", "sleep", "loadDownloads"])
  }

  func testActiveDetailSubscriptionRefreshWaitsBeforeFirstRefresh() async {
    var events: [String] = []
    var refreshCount = 0

    await MediaDetailView.runActiveSubscriptionRefreshLoop(
      refreshIfNeeded: {
        events.append("refresh")
        refreshCount += 1
      },
      sleep: { interval in
        XCTAssertEqual(interval, MediaDetailView.activeSubscriptionRefreshIntervalNanoseconds)
        events.append("sleep")
      },
      isCancelled: {
        refreshCount >= 1
      }
    )

    XCTAssertEqual(events, ["sleep", "refresh"])
  }

  func testActiveDetailSubscriptionRefreshesWhenSceneBecomesActive() async {
    var didCheckState = false
    var refreshCount = 0

    await MediaDetailView.refreshActiveSubscriptionStatusOnSceneActivation(
      scenePhase: .active,
      shouldRefresh: {
        didCheckState = true
        return true
      },
      refresh: {
        refreshCount += 1
      }
    )

    XCTAssertTrue(didCheckState)
    XCTAssertEqual(refreshCount, 1)
  }

  func testActiveDetailSubscriptionSceneActivationSkipsWhenNoActiveSubscriptionState() async {
    var didCheckState = false
    var refreshCount = 0

    await MediaDetailView.refreshActiveSubscriptionStatusOnSceneActivation(
      scenePhase: .active,
      shouldRefresh: {
        didCheckState = true
        return false
      },
      refresh: {
        refreshCount += 1
      }
    )

    XCTAssertTrue(didCheckState)
    XCTAssertEqual(refreshCount, 0)
  }

  func testActiveDetailSubscriptionSceneActivationIgnoresInactivePhase() async {
    var didCheckState = false
    var refreshCount = 0

    await MediaDetailView.refreshActiveSubscriptionStatusOnSceneActivation(
      scenePhase: .inactive,
      shouldRefresh: {
        didCheckState = true
        return true
      },
      refresh: {
        refreshCount += 1
      }
    )

    XCTAssertFalse(didCheckState)
    XCTAssertEqual(refreshCount, 0)
  }
}
