import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaDetailEpisodeShelfTests: XCTestCase {
  private func season(_ number: Int?) -> TmdbSeason {
    try! JSONDecoder().decode(
      TmdbSeason.self,
      from: JSONSerialization.data(withJSONObject: number.map { ["season_number": $0] } ?? [:]))
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

  func testManySeasonsOrLongGroupSeasonNamesUseMenuInsteadOfChips() {
    let few = (1...8).map { "第 \($0) 季" }
    XCTAssertTrue(MediaDetailEpisodeSeasons.fitsChips(titles: few))
    XCTAssertFalse(MediaDetailEpisodeSeasons.fitsChips(titles: few + ["第 9 季"]))
    let longNames = Array(repeating: "东海篇 · 罗格镇与颠倒山之前的故事", count: 3)
    XCTAssertFalse(MediaDetailEpisodeSeasons.fitsChips(titles: longNames))
  }

  func testCardTextFallsBackWithoutNameOrMetadata() {
    let full = MoviePilotEpisode(
      TmdbEpisode(id: 1, episodeNumber: 3, name: " 暗流 ", airDate: "2024-03-02", runtime: 46),
      season: 1, index: 2)
    XCTAssertEqual(full.eyebrow, "第 3 集 · 46 分钟 · 2024-03-02")
    XCTAssertEqual(full.displayTitle, "暗流")
    XCTAssertEqual(full.cardTitle, "第 3 集 · 暗流")

    let bare = MoviePilotEpisode(
      TmdbEpisode(id: nil, episodeNumber: 5, name: "  ", runtime: 0), season: 1, index: 4)
    XCTAssertEqual(bare.eyebrow, "第 5 集")
    XCTAssertEqual(bare.displayTitle, "第 5 集")
  }

  func testFocusedPlatterLinesUpWithScaledStill() {
    let scaledWidth = EpisodeCardLayout.stillSize.width * EpisodeCardLayout.focusedScale
    XCTAssertEqual(
      EpisodeCardLayout.stillSize.width + 2 * EpisodeCardLayout.platterHorizontalInset, scaledWidth,
      accuracy: 0.001)
  }

  func testEpisodeGroupMenuStartsWithDefaultOrder() {
    XCTAssertEqual(EpisodeGroup.menuOptions([]).map(\.value), [""])
  }
}
