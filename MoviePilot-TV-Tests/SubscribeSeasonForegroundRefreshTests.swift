import XCTest

@testable import MoviePilot_TV

/// F-243 回归：分季页从前台恢复（scenePhase active）时，除了刷新订阅状态，
/// 也必须重查"每季入库状态"。陈旧 availability 不只是角标过时，还会作为
/// `best_version`/`best_version_full` 默认进入新建订阅（create→pause mutation）。
@MainActor
final class SubscribeSeasonForegroundRefreshTests: XCTestCase {
  func testForegroundReactivationRefreshesAvailabilityBeforeSubscription() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift")

    guard let onChangeRange = source.range(of: "onChange(of: scenePhase)") else {
      return XCTFail("找不到 scenePhase 前台恢复处理")
    }
    guard
      let subEnd = source.range(
        of: "checkSubscriptionStatus(forceRefresh: true)",
        range: onChangeRange.upperBound..<source.endIndex
      )
    else {
      return XCTFail("scenePhase 处理内缺少订阅刷新")
    }

    let activeBlock = source[onChangeRange.lowerBound..<subEnd.upperBound]
    XCTAssertTrue(activeBlock.contains("guard phase == .active"))
    XCTAssertNotNil(
      activeBlock.range(of: "checkSeasonsStatus()"),
      "前台恢复必须重查每季入库状态，陈旧 availability 会作为 best_version 默认进入新建订阅"
    )
    // 入库状态应先于订阅状态刷新。
    XCTAssertLessThan(
      activeBlock.range(of: "checkSeasonsStatus()")!.lowerBound,
      activeBlock.range(of: "checkSubscriptionStatus(forceRefresh: true)")!.lowerBound
    )
  }

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
  }
}
