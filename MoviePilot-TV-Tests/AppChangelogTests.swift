import XCTest

@testable import MoviePilot_TV

final class AppChangelogTests: XCTestCase {
  func testHistoryContainsEveryPublishedVersionAndCompatibilityBaseline() {
    let expectedVersions = [
      "v0.3.9", "v0.3.8", "v0.3.7", "v0.3.6", "v0.3.5", "v0.3.4", "v0.3.3",
      "v0.3.2", "v0.3.1", "v0.3.0", "v0.2.0", "v0.1.2", "v0.1.1", "v0.1.0",
    ]
    let expectedCompatibility = [
      "v3.0.4", "v2.15.6", "v2.15.6", "v2.15.6", "v2.14.6", "v2.14.4", "v2.14.0",
      "v2.13.14", "v2.13.2", "v2.10.9", "v2.9.13", "v2.9.13", "v2.9.13", "v2.9.7",
    ]

    XCTAssertEqual(AppChangelog.entries.map(\.version), expectedVersions)
    XCTAssertEqual(
      AppChangelog.entries.map(\.compatibleMoviePilotVersion),
      expectedCompatibility
    )
    XCTAssertEqual(AppChangelog.entries[0].highlights, ["兼容 MoviePilot 后端 v3.0.4。"])
    XCTAssertTrue(AppChangelog.entries[2].highlights.contains(
      "降低 77% 内存占用，减少 MoviePilot-TV 或其他 App 因内存压力被系统终止的情况。"
    ))
    XCTAssertFalse(AppChangelog.entries[1].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertFalse(AppChangelog.entries[2].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertTrue(AppChangelog.entries[3].highlights.contains("兼容 MoviePilot 后端 v2.15.6。"))
    XCTAssertTrue(AppChangelog.entries[3].highlights.contains("探索页兼容 MoviePilot 探索来源插件。"))
    XCTAssertTrue(AppChangelog.entries[3].highlights.contains("支持 AniList 媒体来源。"))
    XCTAssertTrue(AppChangelog.entries[4].highlights.contains("兼容 MoviePilot 后端 v2.14.6。"))
    XCTAssertTrue(AppChangelog.entries[5].highlights.contains("兼容 MoviePilot 后端 v2.14.4。"))
    XCTAssertFalse(AppChangelog.entries[10].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[11].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertTrue(AppChangelog.entries[12].highlights.contains("兼容 MoviePilot 后端 v2.9.13。"))
    XCTAssertFalse(AppChangelog.entries[13].highlights.contains("兼容 MoviePilot 后端 v2.9.7。"))
  }

  func testLatestReleaseMatchesApprovedV039Notes() throws {
    let entry = try XCTUnwrap(AppChangelog.entries.first)

    XCTAssertEqual(entry.version, "v0.3.9")
    XCTAssertEqual(entry.releaseDate, "2026-09-18")
    XCTAssertEqual(entry.compatibleMoviePilotVersion, "v3.0.4")
    XCTAssertEqual(entry.highlights, [
      "兼容 MoviePilot 后端 v3.0.4。",
    ])
    XCTAssertEqual(entry.fixes, [
      "对齐 MoviePilot v3.0.4 的媒体数据、订阅编辑、站点与规则组保存等接口行为。",
      "修复搜索词空白和年份识别导致的最佳匹配排序异常。",
      "修复重复发起整理预览时可能展示旧结果的问题，并增强 SSE 进度连接恢复能力。",
      "修复状态页遇到后端可选字段缺失时整页无法刷新的问题。",
    ])
    XCTAssertEqual(entry.optimizations, [
      "订阅设置支持折叠基础选项，减少配置页面的滚动负担。",
      "人物图片按实际显示尺寸下采样，改善详情页内存占用。",
      "完善缺图占位、国家/季信息与转移失败原因的显示。",
    ])
    XCTAssertTrue(entry.updates.isEmpty)
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

    defaults.set("v0.3.9", forKey: AppChangelog.presentedVersionKey)
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.9", defaults: defaults))
    XCTAssertNil(AppChangelog.pendingUpdate(appVersion: "v0.3.8", defaults: defaults))
  }

  func testUpdateNoticeOnlyUsesHighlightsAndPointsToFullHistory() throws {
    let entry = try XCTUnwrap(AppChangelog.entry(for: "0.3.9"))
    let message = AppChangelog.updateNoticeMessage(for: entry)

    XCTAssertTrue(entry.highlights.allSatisfy { message.contains($0) })
    XCTAssertTrue(message.contains("设置 > 版本更新历史"))
    XCTAssertTrue(entry.fixes.allSatisfy { !message.contains($0) })
  }
}
