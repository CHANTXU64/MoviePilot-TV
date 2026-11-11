import XCTest

@testable import MoviePilot_TV

/// F-122：`getTMDBJumpTarget` 在「真正无匹配」时是否弹「未识别到此媒体的TMDB信息」，
/// 必须按调用方区分 —— 以 TMDB 为目标动作用默认（弹），识别失败可自愈的「搜索资源」不弹。
@MainActor
final class TMDBJumpAlertPolicyTests: XCTestCase {

  /// 走「清洗后标题为空」这条**不发网络请求**的早退路径抵达 no-match 分支：
  /// 「第二季」会被季数清洗规则整条剥掉，`recognizeTmdbId` 随即返回 nil。
  private func unrecognizableItem() -> MediaInfo {
    MediaInfo(title: "第二季", type: "电视剧")
  }

  func testUnrecognizedMediaNotifiesByDefault() async throws {
    let handler = MediaActionHandler()
    XCTAssertFalse(handler.showTMDBNotFoundAlert)

    let target = await handler.getTMDBJumpTarget(for: unrecognizableItem())

    XCTAssertNil(target)
    XCTAssertTrue(handler.showTMDBNotFoundAlert, "「TMDB详情页」这类调用方默认应弹提示")
  }

  func testUnrecognizedMediaCanSkipNotification() async throws {
    let handler = MediaActionHandler()
    XCTAssertFalse(handler.showTMDBNotFoundAlert)

    let target = await handler.getTMDBJumpTarget(
      for: unrecognizableItem(), notifyWhenUnrecognized: false)

    // 返回值必须与默认路径一致（否则调用方的标题兜底分支不会触发），只是不弹窗。
    XCTAssertNil(target)
    XCTAssertFalse(handler.showTMDBNotFoundAlert, "「搜索资源」自愈为标题搜索，不应弹提示")
  }

  /// 已知 TMDB ID 时根本不走识别，两条路径都不该弹。
  func testResolvedIdNeverNotifies() async throws {
    let handler = MediaActionHandler()

    let target = await handler.getTMDBJumpTarget(
      for: MediaInfo(title: "这个杀手不太冷", type: "电影"), targetTmdbId: 101)

    XCTAssertEqual(target?.tmdb_id, 101)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
  }
}

/// 调用点守卫：弹窗策略是「按调用方」区分的，行为测试覆盖不到具体传参，
/// 故按本仓库既有做法直接断言源码中两个按钮的传参差异。
final class TMDBJumpAlertCallSiteTests: XCTestCase {

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }

  func testHomeSearchResourcesSkipsNotificationWhileDetailJumpKeepsIt() throws {
    let homeView = try source("MoviePilot-TV/Views/Pages/HomeView.swift")

    XCTAssertTrue(
      homeView.contains("for: info, notifyWhenUnrecognized: false)"),
      "Home「搜索资源」识别失败会自愈为标题搜索，必须显式不弹提示"
    )
    XCTAssertTrue(
      homeView.contains("getTMDBJumpTarget(for: info)"),
      "Home「TMDB详情页」找不到就该告知用户，必须保持默认弹提示"
    )
  }

  func testOtherTMDBJumpEntryPointsKeepDefaultNotification() throws {
    let contextMenu = try source("MoviePilot-TV/Views/Components/MediaContextMenu.swift")
    let detailView = try source("MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    for (name, source) in [("MediaContextMenu", contextMenu), ("MediaDetailView", detailView)] {
      XCTAssertTrue(source.contains("getTMDBJumpTarget("), "\(name) 应仍调用该方法")
      XCTAssertFalse(
        source.contains("notifyWhenUnrecognized: false"),
        "\(name) 是「TMDB详情页」动作，不得关闭无匹配提示"
      )
    }
  }
}

/// F-183：TMDB 详情入口保留预识别门禁，并在动作层同步防重入。
final class TMDBJumpReentrancyCallSiteTests: XCTestCase {

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }

  func testDetailJumpKeepsPreloadDisableAndGuardsReentrancy() throws {
    let detailView = try source("MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(detailView.contains("@State private var isTMDBJumpInFlight = false"))
    XCTAssertTrue(
      detailView.contains("guard !isButtonLoading, !isTMDBJumpInFlight else { return }")
    )
    XCTAssertTrue(detailView.contains("isTMDBJumpInFlight = true"))
    XCTAssertTrue(detailView.contains("defer { isTMDBJumpInFlight = false }"))
    XCTAssertTrue(detailView.contains(".disabled(isButtonLoading)"))
    XCTAssertFalse(detailView.contains(".disabled(isTMDBJumpInFlight)"))
  }
}
