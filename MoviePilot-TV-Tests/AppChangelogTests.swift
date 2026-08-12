import XCTest

@testable import MoviePilot_TV

final class AppChangelogTests: XCTestCase {
  func testHistoryContainsEveryPublishedVersionAndCompatibilityBaseline() {
    let expectedVersions = [
      "v0.3.6", "v0.3.5", "v0.3.4", "v0.3.3", "v0.3.2", "v0.3.1",
      "v0.3.0", "v0.2.0", "v0.1.2", "v0.1.1", "v0.1.0",
    ]
    let expectedCompatibility = [
      "v2.15.6", "v2.14.6", "v2.14.4", "v2.14.0", "v2.13.14", "v2.13.2",
      "v2.10.9", "v2.9.13", "v2.9.13", "v2.9.13", "v2.9.7",
    ]

    XCTAssertEqual(AppChangelog.entries.map(\.version), expectedVersions)
    XCTAssertEqual(
      AppChangelog.entries.map(\.compatibleMoviePilotVersion),
      expectedCompatibility
    )
    XCTAssertTrue(AppChangelog.entries[0].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertTrue(AppChangelog.entries[0].highlights.contains("探索页兼容 MoviePilot 探索来源插件。"))
    XCTAssertTrue(AppChangelog.entries[0].highlights.contains("支持 AniList 媒体来源。"))
    XCTAssertTrue(AppChangelog.entries[1].highlights.contains("兼容 MoviePilot 后端 v2.14.6。"))
    XCTAssertTrue(AppChangelog.entries[2].highlights.contains("兼容 MoviePilot 后端 v2.14.4。"))
    XCTAssertFalse(AppChangelog.entries[7].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[8].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertTrue(AppChangelog.entries[9].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[10].highlights.contains("兼容 MoviePilot 后端 v2.9.7。"))
  }

  func testUpdateNoticeIsShownOnceAndOnlyForANewerVersion() throws {
    let suiteName = "AppChangelogTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstNotice = try XCTUnwrap(
      AppChangelog.pendingUpdate(appVersion: "v0.3.4", defaults: defaults)
    )
    XCTAssertEqual(firstNotice.version, "v0.3.4")

    AppChangelog.markPresented(firstNotice, defaults: defaults)
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.4", defaults: defaults))
    XCTAssertEqual(
      AppChangelog.pendingUpdate(appVersion: "v0.3.5", defaults: defaults)?.version,
      "v0.3.5"
    )

    defaults.set("v0.3.5", forKey: AppChangelog.presentedVersionKey)
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.4", defaults: defaults))
  }

  func testUpdateNoticeOnlyUsesHighlightsAndPointsToFullHistory() throws {
    let entry = try XCTUnwrap(AppChangelog.entry(for: "0.3.6"))
    let message = AppChangelog.updateNoticeMessage(for: entry)

    XCTAssertTrue(entry.highlights.allSatisfy { message.contains($0) })
    XCTAssertTrue(message.contains("设置 > 版本更新历史"))
    XCTAssertFalse(message.contains("修复多来源订阅身份、状态刷新、菜单操作及保存返回流程中的异常。"))
  }
}
