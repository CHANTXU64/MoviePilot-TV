import XCTest

@testable import MoviePilot_TV

@MainActor
final class SheetPickerDisplayTitleTests: XCTestCase {
  private let options = [
    PickerOption(title: "自动", value: ""),
    PickerOption(title: "qBittorrent", value: "qb"),
  ]

  func testShowsOptionTitleForSelectedValue() {
    XCTAssertEqual(SheetPicker<String>.displayTitle(for: "qb", in: options), "qBittorrent")
    XCTAssertEqual(SheetPicker<String>.displayTitle(for: "", in: options), "自动")
  }

  func testKeepsStaleValueVisibleWhenNotInOptions() {
    XCTAssertEqual(SheetPicker<String>.displayTitle(for: "/old/path", in: options), "/old/path")
  }

  func testEmptyValueOutsideOptionsShowsUnselected() {
    XCTAssertEqual(SheetPicker<String>.displayTitle(for: "", in: []), "未选择")
  }

  func testOptionalNilMatchesAutoOption() {
    let optionalOptions = [
      PickerOption<String?>(title: "自动", value: nil),
      PickerOption<String?>(title: "/media", value: "/media"),
    ]
    XCTAssertEqual(SheetPicker<String?>.displayTitle(for: nil, in: optionalOptions), "自动")
    XCTAssertEqual(SheetPicker<String?>.displayTitle(for: "/media", in: optionalOptions), "/media")
  }
}
