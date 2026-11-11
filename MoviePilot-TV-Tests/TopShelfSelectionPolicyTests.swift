import XCTest

@testable import MoviePilot_TV

final class TopShelfSelectionPolicyTests: XCTestCase {
  private let trending = RecommendShelf(
    id: "recommend/tmdb_trending", title: "流行趋势", category: .chart)
  private let movies = RecommendShelf(
    id: "recommend/tmdb_movies", title: "TMDB热门电影", category: .movie)

  func testDefaultPrefersTrendingRegardlessOfCatalogOrder() {
    let value = TopShelfSelectionPolicy.resolve(
      saved: nil, shelves: [movies, trending]
    )
    XCTAssertEqual(value?.shelfID, trending.id)
  }

  func testFallbackUsesFirstShelfWhenTrendingIsAbsent() {
    let value = TopShelfSelectionPolicy.resolve(
      saved: nil, shelves: [movies]
    )
    XCTAssertEqual(value?.shelfID, movies.id)
  }

  func testEmptyCatalogPreservesSelection() {
    let value = TopShelfSelectionPolicy.resolve(
      saved: TopShelfSelection(shelfID: movies.id, title: movies.title),
      shelves: []
    )
    XCTAssertEqual(value?.shelfID, movies.id)
  }

  func testMissingDynamicShelfPreservesSavedSelection() {
    let saved = TopShelfSelection(shelfID: "plugin/custom", title: "私人榜单")
    XCTAssertEqual(
      TopShelfSelectionPolicy.resolve(
        saved: saved, shelves: [trending, movies]
      ), saved)
  }

  func testSameTitleShelvesRemainDistinctByStablePath() {
    let a = RecommendShelf(id: "plugin/a", title: "同名", category: .chart)
    let b = RecommendShelf(id: "plugin/b", title: "同名", category: .chart)
    XCTAssertEqual(
      TopShelfSelectionPolicy.resolve(
        saved: TopShelfSelection(shelfID: b.id, title: b.title),
        shelves: [a, b]
      )?.shelfID, b.id)
  }

  func testOptionsIncludeAllCatalogShelvesAndPreserveUnavailableSavedChoice() {
    let saved = TopShelfSelection(shelfID: "plugin/custom", title: "私人榜单")
    let options = TopShelfSelectionPolicy.options(
      saved: saved, shelves: [trending, movies]
    )
    XCTAssertEqual(options.map(\.shelfID), [saved.shelfID, trending.id, movies.id])
  }
}
