import XCTest

@testable import MoviePilot_TV

@MainActor
final class ReorganizeViewModelTests: XCTestCase {
  func testHistoryTargetStorageSurvivesEmptyTargetPathUpdates() async throws {
    let viewModel = ReorganizeViewModel(
      logIds: [42],
      fileItem: nil,
      targetStorage: "archive"
    )
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)

    viewModel.form.target_path = "/media/movie"
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "local")
    XCTAssertEqual(viewModel.form.transfer_type, "move")
    XCTAssertEqual(viewModel.form.scrape, false)

    viewModel.form.target_path = ""
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)
  }

  func testDirectoryInferredTargetStorageClearsWhenReturningToAutomaticPath() async throws {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    viewModel.form.target_path = "/media/movie"
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "local")
    XCTAssertEqual(viewModel.form.transfer_type, "move")

    viewModel.form.target_path = ""
    try await waitForFormDebounce()

    XCTAssertNil(viewModel.form.target_storage)
    XCTAssertNil(viewModel.form.transfer_type)
  }

  func testDirectoryInferredTargetStorageClearsWhenSwitchingToManualPath() async throws {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    viewModel.form.target_path = "/media/movie"
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "local")

    viewModel.form.target_path = "/manual/library"
    try await waitForFormDebounce()

    XCTAssertNil(viewModel.form.target_storage)
    XCTAssertEqual(viewModel.form.transfer_type, "move")
  }

  func testHistoryRedoKeepsManualIdentityEmptyUntilSubmission() {
    let viewModel = ReorganizeViewModel(logIds: [81], fileItem: nil)

    XCTAssertEqual(viewModel.form.logid, 81)
    XCTAssertFalse(viewModel.form.from_history)
    XCTAssertEqual(viewModel.mediaId, "")
    XCTAssertNil(viewModel.form.media_id)
    XCTAssertNil(viewModel.form.tmdbid)
    XCTAssertNil(viewModel.form.doubanid)
    XCTAssertNil(viewModel.form.bangumiid)
    XCTAssertNil(viewModel.form.anilistid)

    viewModel.form.from_history = true
    let submitted = viewModel.preparedSingleSubmissionForm()

    XCTAssertTrue(submitted.from_history)
    XCTAssertNil(submitted.media_id)
  }

  func testChangingSourceClearsOldIdentityAndEpisodeGroup() {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.mediaId = "42"
    viewModel.form.tmdbid = 42
    viewModel.form.media_source = "themoviedb"
    viewModel.form.media_id = "42"
    viewModel.form.episode_group = "group-a"

    viewModel.selectMediaSource(.anilist)

    XCTAssertEqual(viewModel.mediaSource, .anilist)
    XCTAssertEqual(viewModel.mediaId, "")
    XCTAssertNil(viewModel.form.tmdbid)
    XCTAssertNil(viewModel.form.doubanid)
    XCTAssertNil(viewModel.form.bangumiid)
    XCTAssertNil(viewModel.form.anilistid)
    XCTAssertEqual(viewModel.form.media_source, "anilist")
    XCTAssertNil(viewModel.form.media_id)
    XCTAssertNil(viewModel.form.episode_group)
  }

  func testChangingAwayFromTVClearsEpisodeGroupBeforeSubmission() {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.selectMediaSource(.themoviedb)
    viewModel.selectMediaType("电视剧")
    viewModel.mediaId = "42"
    viewModel.form.episode_group = "group-a"

    viewModel.selectMediaType("电影")

    XCTAssertNil(viewModel.form.episode_group)
    XCTAssertNil(viewModel.preparedSingleSubmissionForm().episode_group)
  }

  func testManualAniListSelectionUsesNativeIDAndUpdatesRecognizedType() {
    let media = MediaInfo(
      tmdb_id: 42,
      anilist_id: 154_587,
      source: "anilist",
      media_id: "154587",
      title: "葬送的芙莉莲",
      type: "tv"
    )
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.selectMediaSource(.anilist)

    let selectedID = ManualMediaSelection.mediaId(for: media, source: .anilist)
    viewModel.selectManualMedia(media, mediaId: selectedID ?? "")

    XCTAssertEqual(selectedID, "154587")
    XCTAssertEqual(viewModel.mediaId, "154587")
    XCTAssertEqual(viewModel.form.type_name, "电视剧")
    let submitted = viewModel.preparedSingleSubmissionForm()
    XCTAssertEqual(submitted.media_source, "anilist")
    XCTAssertEqual(submitted.media_id, "154587")
    XCTAssertNil(submitted.episode_group)
  }

  func testManualTMDBSelectionPrefersNativeIDOverPrefixedMediaID() {
    let media = MediaInfo(
      tmdb_id: 42,
      source: "themoviedb",
      media_id: "tmdb:999",
      title: "测试电影",
      type: "movie"
    )
    let viewModel = ReorganizeViewModel(fileItem: nil)

    let selectedID = ManualMediaSelection.mediaId(for: media, source: .themoviedb)
    viewModel.selectManualMedia(media, mediaId: selectedID ?? "")

    XCTAssertEqual(selectedID, "42")
    XCTAssertEqual(viewModel.mediaId, "42")
  }

  func testPreviewFileNameMatchesWebPathPresentation() {
    XCTAssertEqual(
      manualTransferPreviewFileName(from: "/media/电影名称.2025.2160p.mkv"),
      "电影名称.2025.2160p.mkv"
    )
    XCTAssertEqual(
      manualTransferPreviewFileName(from: #"D:\Media\Movie.2025.1080p.mkv"#),
      "Movie.2025.1080p.mkv"
    )
    XCTAssertNil(manualTransferPreviewFileName(from: nil))
  }

  private func waitForFormDebounce() async throws {
    try await Task.sleep(nanoseconds: 250_000_000)
  }

  private func directory(path: String, storage: String) -> TransferDirectoryConf {
    TransferDirectoryConf(
      name: "电影",
      storage: "download",
      download_path: "/downloads",
      library_path: path,
      library_storage: storage,
      transfer_type: "move",
      scraping: FlexibleBool(false),
      library_category_folder: FlexibleBool(false),
      library_type_folder: FlexibleBool(false)
    )
  }
}
