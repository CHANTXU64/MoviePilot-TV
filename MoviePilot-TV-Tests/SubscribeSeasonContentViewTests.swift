import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSeasonContentViewTests: XCTestCase {
  func testSeasonPrimaryActionPrefersNavigationHandlerWhenProvided() throws {
    let season = try makeSeason(number: 2)
    var tappedSeason: TmdbSeason?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: true,
      onSeasonTap: { tappedSeason = $0 },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(tappedSeason?.season_number, 2)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertNil(preparedSeason)
  }

  func testSeasonPrimaryActionKeepsSubscribeFallbackWithoutNavigationHandler() throws {
    let season = try makeSeason(number: 3)
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      onSeasonTap: nil,
      showUnsubscribeConfirm: { _ in XCTFail("Unsubscribed an unsubscribed season") },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(preparedSeason, 3)
  }

  private func makeSeason(number: Int) throws -> TmdbSeason {
    let data = """
      {
        "air_date": "2024-01-01",
        "episode_count": 8,
        "name": "Season \(number)",
        "overview": "",
        "poster_path": "/season\(number).jpg",
        "season_number": \(number),
        "vote_average": 8.0
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(TmdbSeason.self, from: data)
  }
}
