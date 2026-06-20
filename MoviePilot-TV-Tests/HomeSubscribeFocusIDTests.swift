import XCTest

@testable import MoviePilot_TV

@MainActor
final class HomeSubscribeFocusIDTests: XCTestCase {
  func testSubscribeFocusIDMatchesBetweenRedirectorAndCardBinding() {
    let id: Int? = 123

    XCTAssertEqual(HomeSubscribeFocusID.value(for: id), "123")
    XCTAssertNotEqual(HomeSubscribeFocusID.value(for: id), String(describing: id))
  }

  func testSubscribeFocusIDIsNilWhenSubscribeIDIsMissing() {
    XCTAssertNil(HomeSubscribeFocusID.value(for: Optional<Int>.none))
  }
}
