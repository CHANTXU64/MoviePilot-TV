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

  func testToggleActionFreezesTargetStateAndGatesDuplicateSubmission() throws {
    let viewSource = try source("MoviePilot-TV/Views/Pages/DownloadTaskView.swift")

    XCTAssertTrue(viewSource.contains("guard !isToggling else { return }"))
    XCTAssertTrue(viewSource.contains("let shouldStop = isDownloading"))
    XCTAssertTrue(viewSource.contains("let targetState = !shouldStop"))
    XCTAssertTrue(viewSource.contains("isDownloading = targetState"))
    XCTAssertFalse(
      viewSource.contains("isDownloading.toggle()"),
      "Successful toggle actions must assign the frozen target state instead of flipping the current value."
    )
    XCTAssertTrue(viewSource.contains("isEnabled: !isToggling"))
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }

  func testTransferHistoryRefreshesOnceForEachStatusTabEntry() async {
    var refreshCount = 0

    for _ in 0..<2 {
      var didRefresh = false
      await TransferHistoryView.runAutoRefresh(
        isSelected: true,
        refresh: {
          refreshCount += 1
          didRefresh = true
          return true
        },
        fetchLatest: { XCTFail("A cancelled entry task must not begin polling.") },
        isCancelled: { didRefresh }
      )
    }

    XCTAssertEqual(refreshCount, 2)
  }

  func testTransferHistoryEntryWaitsForMutationBeforeAuthoritativeRefresh() async {
    var canRefresh = false
    var didRefresh = false
    var waitCount = 0

    await TransferHistoryView.runAutoRefresh(
      isSelected: true,
      canRefresh: { canRefresh },
      refresh: {
        didRefresh = true
        return true
      },
      fetchLatest: { XCTFail("Polling must not start after the entry task is cancelled.") },
      sleep: { interval in
        XCTAssertEqual(interval, TransferHistoryView.mutationRefreshRetryNanoseconds)
        waitCount += 1
        canRefresh = true
      },
      isCancelled: { didRefresh }
    )

    XCTAssertEqual(waitCount, 1)
    XCTAssertTrue(didRefresh)
  }

  func testTransferHistoryEntryRetriesWhenMutationStartsBeforeRefresh() async {
    var canRefresh = true
    var refreshAttempts = 0
    var waitCount = 0
    var didRefresh = false

    await TransferHistoryView.runAutoRefresh(
      isSelected: true,
      canRefresh: { canRefresh },
      refresh: {
        refreshAttempts += 1
        if refreshAttempts == 1 {
          canRefresh = false
          return false
        }
        didRefresh = true
        return true
      },
      fetchLatest: { XCTFail("Polling must wait for the authoritative refresh to succeed.") },
      sleep: { interval in
        XCTAssertEqual(interval, TransferHistoryView.mutationRefreshRetryNanoseconds)
        waitCount += 1
        canRefresh = true
      },
      isCancelled: { didRefresh }
    )

    XCTAssertEqual(refreshAttempts, 2)
    XCTAssertEqual(waitCount, 1)
    XCTAssertTrue(didRefresh)
  }

  func testTransferHistoryDoesNotRefreshWhileStatusTabIsNotSelected() async {
    var refreshCount = 0
    var cancelCount = 0

    await TransferHistoryView.runAutoRefresh(
      isSelected: false,
      cancelRefresh: { cancelCount += 1 },
      refresh: {
        refreshCount += 1
        return true
      },
      fetchLatest: { XCTFail("An inactive tab must not poll transfer history.") }
    )

    XCTAssertEqual(refreshCount, 0)
    XCTAssertEqual(cancelCount, 1)
  }

  func testTransferHistoryMountsOnlyThreeRowsUntilItsSectionIsActivated() {
    XCTAssertEqual(
      TransferHistoryView.mountedRowCount(
        totalCount: 20,
        hasActivatedHistoryRows: false
      ),
      3
    )
    XCTAssertEqual(
      TransferHistoryView.mountedRowCount(
        totalCount: 2,
        hasActivatedHistoryRows: false
      ),
      2
    )
    XCTAssertEqual(
      TransferHistoryView.mountedRowCount(
        totalCount: 20,
        hasActivatedHistoryRows: true
      ),
      20
    )
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
