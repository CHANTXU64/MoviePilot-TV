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
