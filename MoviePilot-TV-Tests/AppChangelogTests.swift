import XCTest

@testable import MoviePilot_TV

final class AppChangelogTests: XCTestCase {
  func testHistoryContainsEveryPublishedVersionAndCompatibilityBaseline() {
    let expectedVersions = [
      "v0.3.8", "v0.3.7", "v0.3.6", "v0.3.5", "v0.3.4", "v0.3.3",
      "v0.3.2", "v0.3.1", "v0.3.0", "v0.2.0", "v0.1.2", "v0.1.1", "v0.1.0",
    ]
    let expectedCompatibility = [
      "v2.15.6", "v2.15.6", "v2.15.6", "v2.14.6", "v2.14.4", "v2.14.0",
      "v2.13.14", "v2.13.2", "v2.10.9", "v2.9.13", "v2.9.13", "v2.9.13", "v2.9.7",
    ]

    XCTAssertEqual(AppChangelog.entries.map(\.version), expectedVersions)
    XCTAssertEqual(
      AppChangelog.entries.map(\.compatibleMoviePilotVersion),
      expectedCompatibility
    )
    XCTAssertTrue(AppChangelog.entries[1].highlights.contains(
      "降低 77% 内存占用，减少 MoviePilot-TV 或其他 App 因内存压力被系统终止的情况。"
    ))
    XCTAssertFalse(AppChangelog.entries[0].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertFalse(AppChangelog.entries[1].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertTrue(AppChangelog.entries[2].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertTrue(AppChangelog.entries[2].highlights.contains("探索页兼容 MoviePilot 探索来源插件。"))
    XCTAssertTrue(AppChangelog.entries[2].highlights.contains("支持 AniList 媒体来源。"))
    XCTAssertTrue(AppChangelog.entries[3].highlights.contains("兼容 MoviePilot 后端 v2.14.6。"))
    XCTAssertTrue(AppChangelog.entries[4].highlights.contains("兼容 MoviePilot 后端 v2.14.4。"))
    XCTAssertFalse(AppChangelog.entries[9].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[10].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertTrue(AppChangelog.entries[11].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[12].highlights.contains("兼容 MoviePilot 后端 v2.9.7。"))
  }

  func testLatestReleaseMatchesApprovedEmergencyFixNotes() throws {
    let entry = try XCTUnwrap(AppChangelog.entries.first)

    XCTAssertEqual(entry.version, "v0.3.8")
    XCTAssertEqual(entry.releaseDate, "2026-08-27")
    XCTAssertEqual(entry.compatibleMoviePilotVersion, "v2.15.6")
    XCTAssertEqual(entry.highlights, [
      "紧急修复详情页焦点卡死、无法操作且只能重启 App 恢复的严重问题。",
    ])
    XCTAssertEqual(entry.fixes, [
      "修复 App 从后台返回后，详情页焦点卡在顶部 Tab 栏、无法下移到内容区的问题。",
      "修复详情页上移到顶部 Tab 栏后无法再次下移的问题，恢复正常浏览操作。",
    ])
    XCTAssertTrue(entry.updates.isEmpty)
    XCTAssertTrue(entry.optimizations.isEmpty)
  }

  func testUpdateNoticeIsShownOnceAndOnlyForANewerVersion() throws {
    let suiteName = "AppChangelogTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstNotice = try XCTUnwrap(
      AppChangelog.pendingUpdate(appVersion: "v0.3.7", defaults: defaults)
    )
    XCTAssertEqual(firstNotice.version, "v0.3.7")

    AppChangelog.markPresented(firstNotice, defaults: defaults)
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.7", defaults: defaults))
    XCTAssertEqual(
      AppChangelog.pendingUpdate(appVersion: "v0.3.8", defaults: defaults)?.version,
      "v0.3.8"
    )

    defaults.set("v0.3.8", forKey: AppChangelog.presentedVersionKey)
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.8", defaults: defaults))
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.7", defaults: defaults))
  }

  func testUpdateNoticeOnlyUsesHighlightsAndPointsToFullHistory() throws {
    let entry = try XCTUnwrap(AppChangelog.entry(for: "0.3.8"))
    let message = AppChangelog.updateNoticeMessage(for: entry)

    XCTAssertTrue(entry.highlights.allSatisfy { message.contains($0) })
    XCTAssertTrue(message.contains("设置 > 版本更新历史"))
    XCTAssertTrue(entry.fixes.allSatisfy { !message.contains($0) })
  }
}
