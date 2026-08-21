import XCTest

@testable import MoviePilot_TV

final class MultiSelectionSheetUnavailableTests: XCTestCase {
  private struct Option: Equatable {
    let id: Int
    let name: String
  }

  private let options = [
    Option(id: 1, name: "站点A"),
    Option(id: 2, name: "站点B"),
  ]

  func testUnavailableSelectionsEmptyWhenAllSelectedInOptions() {
    let unavailable = MultiSelectionSheet<Option, Int>.unavailableSelections(
      in: [1, 2],
      options: options,
      id: \.id
    )
    XCTAssertTrue(unavailable.isEmpty)
  }

  func testUnavailableSelectionsOnlyContainsOutsideOptionIDs() {
    let unavailable = MultiSelectionSheet<Option, Int>.unavailableSelections(
      in: [1, 3, 4],
      options: options,
      id: \.id
    )
    XCTAssertEqual(unavailable, [3, 4])
  }

  func testUnavailableSelectionsKeepsStaleValueWhenOptionsEmpty() {
    let unavailable = MultiSelectionSheet<Option, Int>.unavailableSelections(
      in: [7],
      options: [],
      id: \.id
    )
    XCTAssertEqual(unavailable, [7])
  }

  func testUnavailableSelectionsEmptySelection() {
    let unavailable = MultiSelectionSheet<Option, Int>.unavailableSelections(
      in: [],
      options: options,
      id: \.id
    )
    XCTAssertTrue(unavailable.isEmpty)
  }
}
