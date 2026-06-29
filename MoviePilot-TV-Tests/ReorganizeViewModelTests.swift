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

    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)

    viewModel.form.target_path = "/manual/library"
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertEqual(viewModel.form.transfer_type, "copy")
    XCTAssertEqual(viewModel.form.scrape, false)

    viewModel.form.target_path = ""
    try await waitForFormDebounce()

    XCTAssertEqual(viewModel.form.target_storage, "archive")
    XCTAssertNil(viewModel.form.transfer_type)
    XCTAssertNil(viewModel.form.scrape)
  }

  private func waitForFormDebounce() async throws {
    try await Task.sleep(nanoseconds: 250_000_000)
  }
}
