import XCTest

@testable import MoviePilot_TV

@MainActor
final class RecommendCategoryVisibilityTests: XCTestCase {
  func testVisibleCategoriesHidesEmptyCategoryAndKeepsAll() {
    var config = Dictionary(
      uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.title, true) }
    )
    for shelf in RecommendViewModel.allShelves where shelf.category == .anime {
      config[shelf.title] = false
    }

    let categories = RecommendViewModel.visibleCategories(
      shelves: RecommendViewModel.allShelves,
      enableConfig: config
    )

    XCTAssertEqual(categories.first, .all)
    XCTAssertFalse(categories.contains(.anime))
  }

  func testCategoryPickerUsesOnlyVisibleCategories() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/RecommendView.swift")

    XCTAssertEqual(
      source.components(separatedBy: "categories: viewModel.visibleCategories").count - 1,
      2
    )
    XCTAssertTrue(source.contains("let categories: [RecommendCategory]"))
    XCTAssertTrue(source.contains("ForEach(categories)"))
    XCTAssertFalse(source.contains("ForEach(RecommendCategory.allCases)"))
  }

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
  }
}
