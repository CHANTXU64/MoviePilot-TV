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
  func testTMDBJumpTargetKeepsImagesOutOfPartialObjectAndEntryCarriesPoster() async throws {
    let source = MediaInfo(
      douban_id: "1295644",
      title: "这个杀手不太冷",
      type: "电影",
      poster_path: "https://example.com/douban-poster.jpg",
      backdrop_path: "https://example.com/douban-backdrop.jpg"
    )

    let target = await MediaActionHandler().getTMDBJumpTarget(for: source, targetTmdbId: 101)
    let resolvedTarget = try XCTUnwrap(target)
    let entry = ImageNavigationEntry(
      route: .media(resolvedTarget),
      loadingPosterURL: source.imageURLs.poster
    )

    XCTAssertEqual(resolvedTarget.tmdb_id, 101)
    XCTAssertNil(resolvedTarget.poster_path)
    XCTAssertNil(resolvedTarget.backdrop_path)
    XCTAssertEqual(entry.loadingPosterURL, source.imageURLs.poster)
  }

  @MainActor
  func testTMDBPreloadTargetRequiresSettingSourceAndSettledDetail() {
    let douban = MediaInfo(
      douban_id: "1295644",
      title: "这个杀手不太冷",
      type: "电影",
      poster_path: "https://example.com/douban-poster.jpg"
    )

    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: douban,
        fullDetail: douban,
        recognizedTmdbId: 101,
        didFailToLoadDetail: false,
        isEnabled: false
      )
    )
    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: douban,
        fullDetail: nil,
        recognizedTmdbId: 101,
        didFailToLoadDetail: false,
        isEnabled: true
      )
    )
    XCTAssertNil(
      MediaDetailContainerView.tmdbPreloadTarget(
        for: MediaInfo(tmdb_id: 101, title: "TMDB", type: "电影"),
        fullDetail: MediaInfo(tmdb_id: 101, title: "TMDB", type: "电影"),
        recognizedTmdbId: 101,
        didFailToLoadDetail: false,
        isEnabled: true
      )
    )

    let bangumi = MediaInfo(
      bangumi_id: 265,
      title: "新世纪福音战士",
      type: "电视剧",
      poster_path: "https://example.com/bangumi-poster.jpg"
    )
    let bangumiTarget = MediaDetailContainerView.tmdbPreloadTarget(
      for: bangumi,
      fullDetail: nil,
      recognizedTmdbId: 890,
      didFailToLoadDetail: true,
      isEnabled: true
    )
    XCTAssertEqual(bangumiTarget?.tmdb_id, 890)
    XCTAssertNil(bangumiTarget?.poster_path)
  }

  @MainActor
  func testAniListUsesSameTMDBRecognitionFlowAsDoubanAndBangumi() async throws {
    let anilist = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        """
        {
          "anilist_id": 154587,
          "source": "anilist",
          "title": "葬送的芙莉莲",
          "type": "电视剧",
          "year": "2023"
        }
        """.utf8
      )
    )

    XCTAssertEqual(anilist.apiMediaId, "anilist:154587")
    XCTAssertTrue(anilist.canJumpToTMDB)

    let preloadTarget = MediaDetailContainerView.tmdbPreloadTarget(
      for: anilist,
      fullDetail: nil,
      recognizedTmdbId: 209_867,
      didFailToLoadDetail: true,
      isEnabled: true
    )
    let jumpTarget = await MediaActionHandler().getTMDBJumpTarget(
      for: anilist,
      targetTmdbId: 209_867
    )

    XCTAssertEqual(preloadTarget?.tmdb_id, 209_867)
    XCTAssertEqual(jumpTarget?.tmdb_id, 209_867)
    XCTAssertEqual(preloadTarget?.id, jumpTarget?.id)
  }

  @MainActor
  func testTMDBPreloadUsesFullDetailIDAndMatchesJumpTarget() {
    let source = MediaInfo(
      douban_id: "1295644",
      title: "旧标题",
      year: "2023"
    )
    let fullDetail = MediaInfo(
      tmdb_id: 101,
      douban_id: "1295644",
      title: "完整标题",
      type: "电视剧",
      year: "2024",
      season: 1
    )

    let preloadTarget = MediaDetailContainerView.tmdbPreloadTarget(
      for: source,
      fullDetail: fullDetail,
      recognizedTmdbId: nil,
      didFailToLoadDetail: false,
      isEnabled: true
    )
    let jumpTarget = MediaActionHandler.tmdbJumpTarget(for: fullDetail, tmdbId: 101)

    XCTAssertEqual(preloadTarget?.id, jumpTarget.id)
    XCTAssertEqual(preloadTarget?.title, jumpTarget.title)
    XCTAssertEqual(preloadTarget?.type, jumpTarget.type)
    XCTAssertEqual(preloadTarget?.year, jumpTarget.year)
    XCTAssertEqual(preloadTarget?.season, jumpTarget.season)
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
