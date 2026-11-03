import XCTest

@testable import MoviePilot_TV

final class MultiSelectionUnavailableTests: XCTestCase {
  private struct Option: Equatable {
    let id: Int
    let name: String
  }

  private let options = [
    Option(id: 1, name: "站点A"),
    Option(id: 2, name: "站点B"),
  ]

  func testUnavailableSelectionsEmptyWhenAllSelectedInOptions() {
    let unavailable = MultiSelection.unavailableSelections(
      in: [1, 2],
      options: options,
      id: \.id
    )
    XCTAssertTrue(unavailable.isEmpty)
  }

  func testUnavailableSelectionsOnlyContainsOutsideOptionIDs() {
    let unavailable = MultiSelection.unavailableSelections(
      in: [1, 3, 4],
      options: options,
      id: \.id
    )
    XCTAssertEqual(unavailable, [3, 4])
  }

  func testUnavailableSelectionsKeepsStaleValueWhenOptionsEmpty() {
    let unavailable = MultiSelection.unavailableSelections(
      in: [7],
      options: [Option](),
      id: \.id
    )
    XCTAssertEqual(unavailable, [7])
  }

  func testUnavailableSelectionsEmptySelection() {
    let unavailable = MultiSelection.unavailableSelections(
      in: [],
      options: options,
      id: \.id
    )
    XCTAssertTrue(unavailable.isEmpty)
  }
}
