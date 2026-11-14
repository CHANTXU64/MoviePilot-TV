import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaDetailEpisodeShelfTests: XCTestCase {
  private func season(_ number: Int?, episodeCount: Int? = nil) -> TmdbSeason {
    var fields = [String: Int]()
    fields["season_number"] = number
    fields["episode_count"] = episodeCount
    return try! JSONDecoder().decode(
      TmdbSeason.self,
      from: JSONSerialization.data(withJSONObject: fields))
  }

  func testSelectableSeasonsKeepSpecialsFirstAndDropInvalidOrDuplicate() {
    let result = MediaDetailEpisodeSeasons.selectable(
      [season(2), season(0), season(nil), season(-1), season(1), season(2)])
    XCTAssertEqual(result.compactMap(\.season_number), [0, 1, 2])
  }

  func testCurrentSeasonPrefersUserChoiceThenDetailSeasonThenFirstRegularSeason() {
    XCTAssertEqual(MediaDetailEpisodeSeasons.current(selected: 2, preferred: 3, available: [0, 1, 2, 3]), 2)
    XCTAssertEqual(MediaDetailEpisodeSeasons.current(selected: 9, preferred: 3, available: [0, 1, 2, 3]), 3)
    XCTAssertEqual(MediaDetailEpisodeSeasons.current(selected: nil, preferred: nil, available: [0, 1, 2]), 1)
    XCTAssertEqual(MediaDetailEpisodeSeasons.current(selected: nil, preferred: nil, available: [0]), 0)
    XCTAssertNil(MediaDetailEpisodeSeasons.current(selected: nil, preferred: 1, available: []))
  }

  func testExpandIsAvailableForMultipleSeasonsOrMoreThanTenEpisodes() {
    XCTAssertFalse(MediaDetailEpisodeSeasons.canExpand(seasons: [season(1, episodeCount: 10)], loadedEpisodeCount: 10))
    XCTAssertTrue(MediaDetailEpisodeSeasons.canExpand(seasons: [season(1, episodeCount: 11)], loadedEpisodeCount: 0))
    XCTAssertTrue(MediaDetailEpisodeSeasons.canExpand(seasons: [season(1)], loadedEpisodeCount: 11))
    XCTAssertTrue(MediaDetailEpisodeSeasons.canExpand(seasons: [season(1), season(2)], loadedEpisodeCount: 0))
  }

  func testManySeasonsOrLongGroupSeasonNamesUseMenuInsteadOfChips() {
    let few = (1...8).map { "第 \($0) 季" }
    XCTAssertTrue(MediaDetailEpisodeSeasons.fitsChips(titles: few))
    XCTAssertFalse(MediaDetailEpisodeSeasons.fitsChips(titles: few + ["第 9 季"]))
    let longNames = Array(repeating: "东海篇 · 罗格镇与颠倒山之前的故事", count: 3)
    XCTAssertFalse(MediaDetailEpisodeSeasons.fitsChips(titles: longNames))
  }

  func testLargeSeasonMenuGroupsKeepSpecialsAndEverySeasonReachable() {
    let special = PickerOption(title: "特别篇", value: 0)
    let regular = (1...1_003).map { PickerOption(title: "第 \($0) 季", value: $0) }
    XCTAssertTrue(MediaDetailEpisodeSeasons.menuGroups([special] + regular.prefix(49)).isEmpty)
    XCTAssertEqual(MediaDetailEpisodeSeasons.menuGroups([special] + regular.prefix(50)).count, 2)

    let groups = MediaDetailEpisodeSeasons.menuGroups([special] + regular)
    XCTAssertNil(groups.first?.title)
    XCTAssertEqual(groups.dropFirst().first?.title, "第 1–50 季")
    XCTAssertEqual(groups.last?.title, "第 1001–1003 季")
    XCTAssertTrue(groups.allSatisfy { $0.options.count <= 50 })
    XCTAssertEqual(groups.flatMap(\.options).map(\.value), Array(0...1_003))
  }

  func testEpisodePagesCoverAllEpisodesAndExpansionOpensTheContainingRange() {
    let count = 226
    let shelfPages = DetailPageRanges.ranges(count: count, size: 50)
    let gridPages = DetailPageRanges.ranges(count: count, size: 100)

    XCTAssertEqual(shelfPages.flatMap { $0 }, Array(0..<count))
    XCTAssertEqual(gridPages.flatMap { $0 }, Array(0..<count))
    XCTAssertEqual(shelfPages[3], 150..<200)
    XCTAssertEqual(
      DetailPageRanges.current(count: count, size: 100, offset: shelfPages[3].lowerBound),
      100..<200
    )
    XCTAssertEqual(DetailPageRanges.current(count: 51, size: 50, offset: 150), 50..<51)
  }

  func testPageTitleMatchesOriginalEpisodeNumbersOrUsesPositionsWhenUnordered() {
    let episodes = [101, 102, 103, 105, 104].enumerated().map { index, number in
      MoviePilotEpisode(TmdbEpisode(id: nil, episodeNumber: number), season: 1, index: index)
    }
    XCTAssertEqual(DetailPageRanges.title(for: 0..<3, numbers: episodes[0..<3].map(\.episodeNumber), unit: "集"), "101–103 集")
    XCTAssertEqual(DetailPageRanges.title(for: 3..<5, numbers: episodes[3..<5].map(\.episodeNumber), unit: "集"), "第 4–5 项")
  }

  func testCardTextFallsBackWithoutNameOrMetadata() {
    let full = MoviePilotEpisode(
      TmdbEpisode(id: 1, episodeNumber: 3, name: " 暗流 ", airDate: "2024-03-02", runtime: 46),
      season: 1, index: 2)
    XCTAssertEqual(full.eyebrow(includesRuntime: true), "第 3 集 · 46 分钟 · 2024-03-02")
    XCTAssertEqual(full.eyebrow(includesRuntime: false), "第 3 集 · 2024-03-02")
    XCTAssertEqual(full.runtimeText, "46 分钟")
    XCTAssertEqual(full.metadata, ["46 分钟", "2024-03-02"])
    XCTAssertEqual(full.displayTitle, "暗流")
    XCTAssertEqual(full.cardTitle, "第 3 集 · 暗流")

    let bare = MoviePilotEpisode(
      TmdbEpisode(id: nil, episodeNumber: 5, name: "  ", runtime: 0), season: 1, index: 4)
    XCTAssertEqual(bare.eyebrow(includesRuntime: true), "第 5 集")
    XCTAssertNil(bare.runtimeText)
    XCTAssertEqual(bare.displayTitle, "第 5 集")
  }

  func testFocusedPlatterLinesUpWithScaledStill() {
    for width in [EpisodeCardLayout.stillSize.width, EpisodeCardLayout.gridStillSize.width] {
      XCTAssertEqual(
        width + 2 * EpisodeCardLayout.platterHorizontalInset,
        width * PosterCardFocus.focusedScale(forWidth: width),
        accuracy: 0.001)
    }
  }

  func testEpisodeGroupMenuStartsWithDefaultOrderAndShowsGroupCounts() throws {
    let group = try JSONDecoder().decode(
      EpisodeGroup.self,
      from: Data(#"{"id":"group-a","name":"播出顺序","group_count":3,"episode_count":22}"#.utf8))
    let options = EpisodeGroupPickerOptions.make(
      [group], defaultSeasons: [season(0, episodeCount: 2), season(1, episodeCount: 12)])

    XCTAssertEqual(options.map(\.value), ["", "group-a"])
    XCTAssertEqual(options.map(\.detail), ["2 季 · 14 集", "3 季 · 22 集"])
  }

  func testDefaultGroupMenuOmitsUnknownCounts() {
    XCTAssertNil(EpisodeGroupPickerOptions.make([], defaultSeasons: nil).first?.detail)
    XCTAssertNil(EpisodeGroupPickerOptions.make([], defaultSeasons: []).first?.detail)
    XCTAssertEqual(
      EpisodeGroupPickerOptions.make([], defaultSeasons: [season(1), season(2, episodeCount: 8)]).first?.detail,
      "2 季")
  }

  func testGroupsWithZeroSeasonsOrEpisodesMoveBehindPopulatedGroupsInOriginalOrder() throws {
    let groups = try JSONDecoder().decode([EpisodeGroup].self, from: Data("""
      [
        {"id":"zero-seasons","name":"season4","group_count":0,"episode_count":8},
        {"id":"full-a","name":"Story Arc","group_count":5,"episode_count":66},
        {"id":"zero-episodes","name":"Director's Cut Seasons","group_count":1,"episode_count":0},
        {"id":"full-b","name":"Seasons","group_count":5,"episode_count":170}
      ]
      """.utf8))
    let mixed = EpisodeGroupPickerOptions.make(groups, defaultSeasons: [season(1, episodeCount: 0)])
    XCTAssertEqual(mixed.map(\.value), ["full-a", "full-b", "", "zero-seasons", "zero-episodes"])
    XCTAssertEqual(mixed.map(\.title), ["故事线", "季", "默认", "第 4 季", "导演剪辑版"])

    let emptyGroups = [groups[0], groups[2]]
    let allEmpty = EpisodeGroupPickerOptions.make(emptyGroups, defaultSeasons: [season(1, episodeCount: 0)])
    XCTAssertEqual(allEmpty.map(\.value), ["", "zero-seasons", "zero-episodes"])
  }

  func testEpisodeGroupTitlesOnlyShowOrderWhenTheOriginalNameIncludesIt() {
    for name in ["Digital", "DVD", "Blu-ray", "Bluray", "Production", "TV"] {
      XCTAssertFalse(EpisodeGroupDisplayFormatter.name(name).contains("顺序"), name)
      let orderName = "\(name) Order"
      XCTAssertTrue(EpisodeGroupDisplayFormatter.name(orderName).contains("顺序"), orderName)
    }
  }

  func testLongGroupMenuTitleUsesTheTitleLineAndKeepsCountsSeparate() {
    let option = PickerOption(title: "Director's Cut Seasons\nSpecial Edition", value: "cut", detail: "1 季 · 0 集")
    let title = option.singleLineMenuTitle
    XCTAssertTrue(title.hasSuffix("…"))
    XCTAssertFalse(title.contains("\n"))
    XCTAssertFalse(title.contains("1 季 · 0 集"))
    XCTAssertEqual(option.detail, "1 季 · 0 集")
    XCTAssertEqual(option.title, "Director's Cut Seasons\nSpecial Edition")
  }
}
