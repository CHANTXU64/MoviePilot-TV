import XCTest

/// 推荐货架和探索筛选行的焦点光晕要画在上下相邻行之上。
/// 行距和焦点重定向条的位置必须保持原样。这些断言只钉住接线，读不到聚焦后的像素。
final class SecondRowFocusClipTests: XCTestCase {
  func testSecondRowFocusHaloDrawsAboveNeighborsWithoutMovingGuidesInSource() throws {
    let shelf = try source("MoviePilot-TV/Views/Components/ShelfPicker.swift")
    let recommend = try source("MoviePilot-TV/Views/Pages/RecommendView.swift")
    let explore = try source("MoviePilot-TV/Views/Pages/ExploreView.swift")
    let grid = try source("MoviePilot-TV/Views/Components/MediaGridView.swift")

    let recommendHeader = try slice(recommend, from: "header: {", to: "contextMenu:")
    let exploreHeader = try slice(explore, from: "private var headerView", to: "// MARK: - 数据源选择器")
    let filters = try slice(explore, from: "struct FilterPickersView", to: ".sheet(item:")

    for row in [shelf, filters] {
      XCTAssertTrue(
        containsTokensInOrder(
          row,
          [
            ".frame(height: 1)",
            "ScrollView(.horizontal, showsIndicators: false)",
            ".scrollClipDisabled()",
            ".frame(height: 1)",
            ".zIndex(1)",
          ]
        )
      )
      let scrollStart = try XCTUnwrap(row.range(of: "ScrollView(.horizontal, showsIndicators: false)"))
      let clip = try XCTUnwrap(row.range(of: ".scrollClipDisabled()"))
      XCTAssertFalse(row[scrollStart.upperBound..<clip.lowerBound].contains(".padding("))
      XCTAssertEqual(row.components(separatedBy: ".frame(height: 1)").count - 1, 2)
      XCTAssertEqual(row.components(separatedBy: ".zIndex(1)").count - 1, 1)
    }

    XCTAssertTrue(filters.contains(".lineLimit(1)"))
    let lineLimit = try XCTUnwrap(filters.range(of: ".lineLimit(1)"))
    let filterClip = try XCTUnwrap(filters.range(of: ".scrollClipDisabled()"))
    XCTAssertLessThan(lineLimit.lowerBound, filterClip.lowerBound)

    XCTAssertTrue(
      containsTokensInOrder(recommendHeader, ["VStack(spacing: 20)", "ShelfPicker(", ".zIndex(1)"])
    )
    XCTAssertFalse(recommendHeader.contains("spacing: 0"))
    XCTAssertFalse(recommend.contains("headerSpacing"))

    XCTAssertTrue(
      containsTokensInOrder(
        exploreHeader,
        ["VStack(alignment: .leading, spacing: 20)", "FilterPickersView(", ".zIndex(1)"]
      )
    )
    XCTAssertFalse(exploreHeader.contains("spacing: 0"))
    XCTAssertFalse(explore.contains("headerSpacing"))

    XCTAssertTrue(grid.contains("VStack(spacing: 20)"))
    XCTAssertFalse(grid.contains("headerSpacing"))
    XCTAssertFalse(grid.contains(".zIndex("))
  }

  private func slice(_ source: String, from start: String, to end: String) throws -> String {
    let startRange = try XCTUnwrap(source.range(of: start))
    let endRange = try XCTUnwrap(
      source.range(of: end, range: startRange.upperBound..<source.endIndex)
    )
    return String(source[startRange.lowerBound..<endRange.lowerBound])
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }
}
