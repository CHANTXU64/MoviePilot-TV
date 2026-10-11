import XCTest

@testable import MoviePilot_TV

@MainActor
final class RecommendCategoryVisibilityTests: XCTestCase {
  func testPluginCategoryNamesMatchChineseAndEnglishIgnoringCase() {
    let groups = [
      ("电影", ["电影", "電影", "Movies"]),
      ("电视剧", ["电视剧", "電視劇", "TV Shows"]),
      ("动画", ["动画", "動漫", "动漫", "動畫", "Anime"]),
      ("榜单", ["榜单", "榜單", "Rankings"]),
    ]
    for (expected, names) in groups {
      for name in names {
        for variant in Set([name, name.lowercased(), name.uppercased()]) {
          XCTAssertEqual(RecommendViewModel.category(for: variant).rawValue, expected, variant)
        }
      }
    }
  }

  func testUnrecognizedPluginCategoriesUseOther() {
    for name in ["", " ", "自定义分类", "Documentary", "MoviesExtra", "全部", "All"] {
      XCTAssertEqual(RecommendViewModel.category(for: name).rawValue, "其他", name)
    }
  }

  func testVisibleCategoriesHidesEmptyCategoryAndKeepsAll() {
    var config = Dictionary(
      uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, true) }
    )
    for shelf in RecommendViewModel.allShelves where shelf.category == .anime {
      config[shelf.id] = false
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
