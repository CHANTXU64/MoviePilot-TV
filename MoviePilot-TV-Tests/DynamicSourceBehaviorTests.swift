import XCTest

@testable import MoviePilot_TV

@MainActor
final class DynamicSourceBehaviorTests: XCTestCase {
  func testPluginFilterParserKeepsSupportedControlsAndSkipsUnknownControls() {
    let parsed = PluginFilterControlParser.parse([
      .object([
        "component": .string("VChipGroup"),
        "props": .object([
          "model": .string("mtype"),
          "label": .string("类型"),
        ]),
        "content": .array([
          .object([
            "component": .string("VChip"),
            "props": .object(["value": .string("movies")]),
            "text": .string("电影"),
          ])
        ]),
      ]),
      .object([
        "component": .string("FutureRange"),
        "props": .object([
          "model": .string("score"),
          "label": .string("评分"),
        ]),
      ]),
    ])

    XCTAssertEqual(parsed.map(\.field), ["mtype"])
    XCTAssertEqual(parsed.first?.options.map(\.title), ["电影"])
  }

  func testPluginFilterDependencyClearsDependentField() {
    let values = ExploreViewModel.applyingPluginFilter(
      field: "country",
      value: .string("jpn"),
      to: [
        "country": .string("usa"),
        "company": .int(12),
      ],
      depends: ["company": ["country"]]
    )

    XCTAssertEqual(values["country"], .string("jpn"))
    XCTAssertEqual(values["company"], .null)
  }

  func testDynamicPathKeepsQueryAndRejectsExternalPaths() throws {
    let path = ExploreViewModel.appendingQuery(
      to: "plugin/TvdbDiscover/tvdb_discover?apikey=signed%23token",
      values: [
        "mtype": .string("series"),
        "year": .int(2026),
      ]
    )
    let endpoint = try relativeBackendEndpoint(path: path, params: ["page": "3"])
    let components = try XCTUnwrap(URLComponents(string: endpoint))
    let items = try XCTUnwrap(components.queryItems)

    XCTAssertEqual(components.path, "/plugin/TvdbDiscover/tvdb_discover")
    XCTAssertEqual(items.first(where: { $0.name == "apikey" })?.value, "signed#token")
    XCTAssertEqual(items.first(where: { $0.name == "mtype" })?.value, "series")
    XCTAssertEqual(items.first(where: { $0.name == "year" })?.value, "2026")
    XCTAssertEqual(items.first(where: { $0.name == "page" })?.value, "3")
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "https://example.com/media"))
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "../system/global"))
    XCTAssertThrowsError(try relativeBackendEndpoint(path: "//example.com/media"))
    XCTAssertEqual(
      redactedEndpointForLogging(
        "/plugin/TvdbDiscover/tvdb_discover?apikey=secret-token#signed"
      ),
      "/plugin/TvdbDiscover/tvdb_discover"
    )
  }

  func testDiscoverSourceSnapshotDeduplicatesBuiltInsAndPluginPrefixes() {
    let sources = ExploreViewModel.updatedExtraSourceSnapshot(
      previous: [],
      response: [
        descriptor(name: "伪装内置", prefix: "anilist", path: "plugin/fake"),
        descriptor(name: "TheTVDB", prefix: "tvdb", path: "plugin/tvdb"),
        descriptor(name: "重复 TheTVDB", prefix: "tvdb", path: "plugin/duplicate"),
      ]
    )

    XCTAssertEqual(sources.map(\.name), ["TheTVDB"])
    XCTAssertEqual(
      ExploreViewModel.updatedExtraSourceSnapshot(previous: sources, response: nil),
      sources
    )
  }

  func testRecommendSourcesKeepBuiltInOrderAndDeduplicatePaths() {
    let shelves = RecommendViewModel.mergedShelves(extras: [
      RecommendSourceDescriptor(
        name: "重复 AniList",
        api_path: "anilist/trending",
        type: "动画"
      ),
      RecommendSourceDescriptor(
        name: "插件电影",
        api_path: "plugin/example/movies?mode=hot",
        type: "电影"
      ),
      RecommendSourceDescriptor(
        name: "重复插件",
        api_path: "plugin/example/movies?mode=hot",
        type: "电影"
      ),
    ])

    XCTAssertEqual(shelves.filter { $0.id == "anilist/trending" }.count, 1)
    XCTAssertEqual(shelves.filter { $0.id == "plugin/example/movies?mode=hot" }.count, 1)
    XCTAssertEqual(
      shelves.first(where: { $0.id == "plugin/example/movies?mode=hot" })?.category,
      .movie
    )
  }

  func testCustomFocusAndSourceRefreshGuardsRemainInViewCode() throws {
    let exploreView = try source("MoviePilot-TV/Views/Pages/ExploreView.swift")
    XCTAssertFalse(exploreView.contains("customFocusedIndex"))
    XCTAssertTrue(exploreView.contains("case .custom: 0"))
    XCTAssertTrue(
      exploreView.contains(".focusable(hasFocusableFilters && focusedPickerIndex == nil)")
    )

    try assertDiscoveryGuardPrecedesFetch(
      in: source("MoviePilot-TV/ViewModels/ExploreViewModel.swift"),
      fetchCall: "fetchDiscoverSources()"
    )
    try assertDiscoveryGuardPrecedesFetch(
      in: source("MoviePilot-TV/ViewModels/RecommendViewModel.swift"),
      fetchCall: "fetchRecommendSources()"
    )
  }

  private func descriptor(name: String, prefix: String, path: String)
    -> DiscoverSourceDescriptor
  {
    DiscoverSourceDescriptor(
      name: name,
      mediaid_prefix: prefix,
      api_path: path,
      filter_params: [:],
      filter_ui: [],
      depends: nil
    )
  }

  private func assertDiscoveryGuardPrecedesFetch(
    in source: String,
    fetchCall: String
  ) throws {
    let refresh = try XCTUnwrap(source.range(of: "func refreshSources"))
    let fetch = try XCTUnwrap(
      source.range(of: fetchCall, range: refresh.upperBound..<source.endIndex)
    )
    XCTAssertNotNil(
      source.range(
        of: "guard apiService.canAccess(.discovery)",
        range: refresh.upperBound..<fetch.lowerBound
      )
    )
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }
}
