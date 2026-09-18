import XCTest

@testable import MoviePilot_TV

@MainActor
final class ReorganizeViewModelTests: XCTestCase {
  func testHistoryTargetStorageSurvivesEmptyTargetPathUpdates() {
    let viewModel = ReorganizeViewModel(
      logIds: [42],
      fileItem: nil,
      targetStorage: "archive"
    )
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)

    viewModel.selectTargetPath("/media/movie")
    XCTAssertEqual(viewModel.form.target_storage, "local")
    XCTAssertEqual(viewModel.form.transfer_type, "move")
    XCTAssertEqual(viewModel.form.scrape, false)

    viewModel.selectTargetPath("")
    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)
  }

  func testDirectoryInferredTargetStorageClearsWhenReturningToAutomaticPath() {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    viewModel.selectTargetPath("/media/movie")
    XCTAssertEqual(viewModel.form.target_storage, "local")
    XCTAssertEqual(viewModel.form.transfer_type, "move")

    viewModel.selectTargetPath("")
    XCTAssertNil(viewModel.form.target_storage)
    XCTAssertNil(viewModel.form.transfer_type)
  }

  func testDirectoryInferredTargetStorageClearsWhenSwitchingToManualPath() {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]

    viewModel.selectTargetPath("/media/movie")
    XCTAssertEqual(viewModel.form.target_storage, "local")

    viewModel.selectTargetPath("/manual/library")
    XCTAssertNil(viewModel.form.target_storage)
    XCTAssertEqual(viewModel.form.transfer_type, "move")
  }

  func testSelectingCurrentTargetPathKeepsManualOverrides() {
    let viewModel = ReorganizeViewModel(fileItem: nil)
    viewModel.directories = [directory(path: "/media/movie", storage: "local")]
    viewModel.selectTargetPath("/media/movie")
    viewModel.form.target_storage = "archive"
    viewModel.form.transfer_type = "copy"

    viewModel.selectTargetPath("/media/movie")

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertEqual(viewModel.form.transfer_type, "copy")
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
    XCTAssertNil(submitted.media_source)
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

  func testManualSelectionFallsBackToMediaIDWhenNativeIDIsZero() {
    let media = MediaInfo(
      tmdb_id: 0,
      source: "themoviedb",
      media_id: "tmdb:999",
      title: "测试电影",
      type: "movie"
    )

    let selectedID = ManualMediaSelection.mediaId(for: media, source: .themoviedb)

    XCTAssertEqual(selectedID, "tmdb:999")
  }

  func testManualSelectionFallsBackToMediaIDWhenNativeIDIsNegative() {
    let media = MediaInfo(
      anilist_id: -1,
      source: "anilist",
      media_id: "anilist:7",
      title: "测试番剧",
      type: "tv"
    )

    let selectedID = ManualMediaSelection.mediaId(for: media, source: .anilist)

    XCTAssertEqual(selectedID, "anilist:7")
  }

  func testManualSelectionKeepsZeroNativeIDWithNoFallbackAsUnselectable() {
    let media = MediaInfo(
      tmdb_id: 0,
      source: "themoviedb",
      media_id: nil,
      title: "测试电影",
      type: "movie"
    )

    XCTAssertNil(ManualMediaSelection.mediaId(for: media, source: .themoviedb))
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

  func testRejectedDuplicatePreviewDoesNotPresentStaleResult() async {
    let service = APIService.isolatedTestingInstance()
    service.tokenForTesting = "reorganize-preview-token"
    service.currentUserForTesting = Token(
      access_token: "reorganize-preview-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: nil,
      user_id: 901,
      user_name: "reorganize-preview-user",
      avatar: nil
    )

    var previousPreview = ManualTransferPreviewData.empty
    previousPreview.message = "previous-preview"
    var refreshedPreview = ManualTransferPreviewData.empty
    refreshedPreview.message = "refreshed-preview"
    let gate = ReorganizePreviewRequestGate()
    let viewModel = ReorganizeViewModel(
      logIds: [42],
      fileItem: nil,
      previewRequest: { _ in
        await gate.run()
        return refreshedPreview
      },
      apiService: service
    )
    viewModel.previewData = previousPreview

    let firstPreview = Task { await viewModel.preview() }
    await gate.waitUntilStarted()

    let duplicateOutcome = await viewModel.preview()
    XCTAssertEqual(duplicateOutcome, .notGenerated)
    XCTAssertFalse(duplicateOutcome.shouldPresent)
    XCTAssertEqual(viewModel.previewData?.message, "previous-preview")

    await gate.open()
    let firstOutcome = await firstPreview.value
    XCTAssertEqual(firstOutcome, .generated(allSucceeded: true))
    XCTAssertTrue(firstOutcome.shouldPresent)
    XCTAssertEqual(viewModel.previewData?.message, "refreshed-preview")
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

private actor ReorganizePreviewRequestGate {
  private var isStarted = false
  private var isOpen = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []

  func run() async {
    isStarted = true
    let pendingStartWaiters = startWaiters
    startWaiters.removeAll()
    pendingStartWaiters.forEach { $0.resume() }

    if !isOpen {
      await withCheckedContinuation { continuation in
        requestWaiters.append(continuation)
      }
    }
  }

  func waitUntilStarted() async {
    guard !isStarted else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pendingRequestWaiters = requestWaiters
    requestWaiters.removeAll()
    pendingRequestWaiters.forEach { $0.resume() }
  }
}
