import XCTest

@testable import MoviePilot_TV

final class TMDBDetailPreloadTests: XCTestCase {
  private let settingKey = "preloadTMDBDetails"

  @MainActor
  func testPreloadSettingDefaultsOnAndPersistsChanges() {
    let originalValue = UserDefaults.standard.object(forKey: settingKey)
    defer {
      if let originalValue {
        UserDefaults.standard.set(originalValue, forKey: settingKey)
      } else {
        UserDefaults.standard.removeObject(forKey: settingKey)
      }
    }

    UserDefaults.standard.removeObject(forKey: settingKey)
    let viewModel = SystemViewModel()

    XCTAssertTrue(viewModel.preloadTMDBDetails)
    XCTAssertTrue(SystemViewModel.shouldPreloadTMDBDetails)

    viewModel.preloadTMDBDetails = false
    XCTAssertFalse(SystemViewModel.shouldPreloadTMDBDetails)
  }

  @MainActor
  func testTMDBJumpTargetKeepsImagesOutOfPartialObjectAndPassesPosterToTransition() async {
    let source = MediaInfo(
      douban_id: "1295644",
      title: "这个杀手不太冷",
      type: "电影",
      poster_path: "https://example.com/douban-poster.jpg",
      backdrop_path: "https://example.com/douban-backdrop.jpg"
    )

    MediaCardTransition.loadingPosterURL = nil
    defer { MediaCardTransition.loadingPosterURL = nil }

    let target = await MediaActionHandler().getTMDBJumpTarget(for: source, targetTmdbId: 101)

    XCTAssertEqual(target?.tmdb_id, 101)
    XCTAssertNil(target?.poster_path)
    XCTAssertNil(target?.backdrop_path)
    XCTAssertEqual(MediaCardTransition.loadingPosterURL, source.imageURLs.poster)
  }

  @MainActor
  func testTMDBPreloadTargetRequiresSettingSourceAndRecognizedID() {
    let douban = MediaInfo(
      douban_id: "1295644",
      title: "这个杀手不太冷",
      type: "电影",
      poster_path: "https://example.com/douban-poster.jpg"
    )

    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: douban,
        tmdbId: 101,
        isEnabled: false
      )
    )
    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: douban,
        tmdbId: nil,
        isEnabled: true
      )
    )
    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: MediaInfo(tmdb_id: 101, title: "TMDB", type: "电影"),
        tmdbId: 101,
        isEnabled: true
      )
    )

    let target = MediaDetailContainerView.tmdbPreloadTarget(
      for: douban,
      tmdbId: 101,
      isEnabled: true
    )
    XCTAssertEqual(target?.tmdb_id, 101)
    XCTAssertNil(target?.poster_path)

    let bangumi = MediaInfo(
      bangumi_id: 265,
      title: "新世纪福音战士",
      type: "电视剧",
      poster_path: "https://example.com/bangumi-poster.jpg"
    )
    let bangumiTarget = MediaDetailContainerView.tmdbPreloadTarget(
      for: bangumi,
      tmdbId: 890,
      isEnabled: true
    )
    XCTAssertEqual(bangumiTarget?.tmdb_id, 890)
    XCTAssertNil(bangumiTarget?.poster_path)
  }

  func testSystemViewExposesTMDBPreloadToggleAndDescription() throws {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
      contentsOf: repositoryRoot.appendingPathComponent("MoviePilot-TV/Views/Pages/SystemView.swift")
    )

    XCTAssertTrue(source.contains("预加载 TMDB 详情"))
    XCTAssertTrue(source.contains("viewModel.preloadTMDBDetails"))
    XCTAssertTrue(source.contains("case .preloadTMDBDetails:"))
  }
}
