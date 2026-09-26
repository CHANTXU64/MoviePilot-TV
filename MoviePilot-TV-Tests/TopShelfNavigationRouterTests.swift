import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfNavigationRouterTests: XCTestCase {
  func testRoutePayloadMapsEveryPreservedIdentityFieldToMediaInfo() throws {
    let payload = routePayload(sessionID: "session-a")

    let media = try XCTUnwrap(TopShelfNavigationRouter.media(from: payload))

    XCTAssertEqual(media.source, payload.source)
    XCTAssertEqual(media.media_id, payload.mediaID)
    XCTAssertEqual(media.mediaid_prefix, payload.mediaIDPrefix)
    XCTAssertEqual(media.tmdb_id, payload.tmdbID)
    XCTAssertEqual(media.douban_id, payload.doubanID)
    XCTAssertEqual(media.bangumi_id, payload.bangumiID)
    XCTAssertEqual(media.anilist_id, payload.anilistID)
    XCTAssertEqual(media.imdb_id, payload.imdbID)
    XCTAssertEqual(media.tvdb_id, payload.tvdbID)
    XCTAssertEqual(media.title, payload.title)
    XCTAssertEqual(media.type, payload.type)
    XCTAssertEqual(media.year, payload.year)
    XCTAssertEqual(media.season, payload.season)
    XCTAssertEqual(media.poster_path, payload.posterPath)
    XCTAssertEqual(media.overview, payload.overview)
    XCTAssertEqual(media.vote_average, payload.voteAverage)
    XCTAssertEqual(media.collection_id, payload.collectionID)
  }

  func testDeepLinkCannotSupplyLocalFilePoster() throws {
    let original = try TopShelfDeepLink.url(for: routePayload(sessionID: "session-a"))
    let encoded = try JSONEncoder().encode(routePayload(sessionID: "session-a"))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json["posterPath"] = "file:///private/example.jpg"
    let payload = try JSONDecoder().decode(
      TopShelfRoutePayload.self, from: JSONSerialization.data(withJSONObject: json)
    )
    let router = TopShelfNavigationRouter(store: nil)
    XCTAssertTrue(router.handle(original))
    XCTAssertTrue(router.handle(try TopShelfDeepLink.url(for: payload)))
    XCTAssertNil(router.pendingRoute?.media.poster_path)
    XCTAssertNil(router.pendingRoute?.localPosterURL)
  }

  func testSameURLCanBeHandledAgainAfterItsEventIsConsumed() throws {
    let router = TopShelfNavigationRouter()
    let url = try TopShelfDeepLink.url(for: routePayload(sessionID: "session-a"))

    XCTAssertTrue(router.handle(url))
    let first = try XCTUnwrap(router.pendingRoute)
    router.consume(id: first.id)
    XCTAssertNil(router.pendingRoute)

    XCTAssertTrue(router.handle(url))
    let second = try XCTUnwrap(router.pendingRoute)
    XCTAssertNotEqual(second.id, first.id)
  }

  func testConsumingOlderEventDoesNotClearNewerEvent() throws {
    let router = TopShelfNavigationRouter()
    XCTAssertTrue(
      router.handle(try TopShelfDeepLink.url(for: routePayload(sessionID: "session-a"))))
    let firstID = try XCTUnwrap(router.pendingRoute?.id)
    XCTAssertTrue(
      router.handle(try TopShelfDeepLink.url(for: routePayload(sessionID: "session-b"))))
    let secondID = try XCTUnwrap(router.pendingRoute?.id)

    router.consume(id: firstID)

    XCTAssertEqual(router.pendingRoute?.id, secondID)
  }

  func testInvalidURLDoesNotReplacePendingEvent() throws {
    let router = TopShelfNavigationRouter()
    XCTAssertTrue(
      router.handle(try TopShelfDeepLink.url(for: routePayload(sessionID: "session-a"))))
    let event = router.pendingRoute

    XCTAssertFalse(router.handle(try XCTUnwrap(URL(string: "moviepilot-tv://other/media"))))
    XCTAssertEqual(router.pendingRoute?.id, event?.id)
  }

  func testNavigationPolicyPreviewsMatchingSavedSessionWhileStartupIsPending() {
    let route = PendingTopShelfRoute(payload: routePayload(sessionID: "session-a"))!

    XCTAssertEqual(
      TopShelfNavigationPolicy.disposition(
        for: route,
        isPreparingStartupSession: true,
        isLoggedIn: true,
        currentSessionID: "session-a",
        visibleTabs: [.home, .recommend, .system]
      ),
      .preview
    )
    XCTAssertEqual(
      TopShelfNavigationPolicy.disposition(
        for: route,
        isPreparingStartupSession: false,
        isLoggedIn: true,
        currentSessionID: "session-a",
        visibleTabs: [.home, .recommend, .system]
      ),
      .open
    )
    XCTAssertEqual(
      TopShelfNavigationPolicy.disposition(
        for: route,
        isPreparingStartupSession: false,
        isLoggedIn: true,
        currentSessionID: "session-b",
        visibleTabs: [.home, .recommend, .system]
      ),
      .discard
    )
    XCTAssertEqual(
      TopShelfNavigationPolicy.disposition(
        for: route,
        isPreparingStartupSession: false,
        isLoggedIn: true,
        currentSessionID: "session-a",
        visibleTabs: [.home, .system]
      ),
      .discard
    )
    XCTAssertEqual(
      TopShelfNavigationPolicy.disposition(
        for: route,
        isPreparingStartupSession: false,
        isLoggedIn: false,
        currentSessionID: "session-a",
        visibleTabs: [.home, .system]
      ),
      .discard
    )
  }

  private func routePayload(sessionID: String) -> TopShelfRoutePayload {
    TopShelfRoutePayload(
      sessionID: sessionID,
      source: "plugin-source",
      mediaID: "plugin:42",
      mediaIDPrefix: "plugin",
      tmdbID: 42,
      doubanID: "db-42",
      bangumiID: 142,
      anilistID: 242,
      imdbID: "tt0000042",
      tvdbID: 342,
      title: "测试媒体",
      type: "电影",
      year: "2026",
      season: 2,
      posterPath: "/poster.jpg",
      collectionID: 442,
      overview: "缓存简介",
      voteAverage: 8.5
    )
  }
}
