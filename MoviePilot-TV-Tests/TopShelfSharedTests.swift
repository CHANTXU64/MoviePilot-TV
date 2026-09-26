import Foundation
import XCTest

@testable import MoviePilot_TV

final class TopShelfSharedTests: XCTestCase {
  func testOlderSnapshotWithTwelveCardsStillPresentsOnlySix() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let image = try store.writeImage(
      TopShelfImageResource(data: Data([1]), fileExtension: "jpg"), cacheKey: "limit"
    )
    let original = sharedState()
    let payload = routePayload()
    let selection = try XCTUnwrap(original.selection)
    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: payload.sessionID, selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: payload.sessionID, selection: selection, generatedAt: Date(),
          items: try (1...12).map {
            TopShelfSnapshotItem(
              identifier: "card-\($0)", title: "卡片\($0)", imageRelativePath: image,
              displayURL: try TopShelfDeepLink.url(for: payload)
            )
          }
        )
      ))
    XCTAssertEqual(store.presentation(at: Date())?.items.count, 6)
  }

  func testPreparedDataUsesImmutableFilesAndIsPrunedWithItsImages() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let old = try store.writeDetailData(Data("old".utf8), cacheKey: "same-owner-media")
    let new = try store.writeDetailData(Data("new".utf8), cacheKey: "same-owner-media")
    XCTAssertNotEqual(old, new, "新一轮准备不能覆写仍被旧快照引用的数据")
    XCTAssertEqual(try store.detailData(relativePath: old), Data("old".utf8))
    XCTAssertNil(try store.detailData(relativePath: "details/../../outside.json"))
    try store.pruneResources(
      keepingRelativePaths: [new], now: Date().addingTimeInterval(10), gracePeriod: 0
    )
    XCTAssertNil(try store.detailData(relativePath: old))
    XCTAssertEqual(try store.detailData(relativePath: new), Data("new".utf8))
  }

  func testDeepLinkRoundTripsUnicodeAndReservedCharactersExactlyOnce() throws {
    let payload = routePayload(
      source: "插件/豆瓣+bangumi&x=y%25",
      mediaID: "媒体/42?part=1&name=空 格+号",
      title: "葬送的芙莉莲 / 100% + 特别篇"
    )

    let url = try TopShelfDeepLink.url(for: payload)

    XCTAssertEqual(url.scheme, "moviepilot-tv")
    XCTAssertEqual(url.host, "top-shelf")
    XCTAssertEqual(url.path, "/media")
    XCTAssertEqual(TopShelfDeepLink.payload(from: url), payload)
    XCTAssertFalse(url.absoluteString.contains("空 格"))
  }

  func testDeepLinkRejectsUnknownBoundaryAndMalformedPayload() throws {
    let valid = try TopShelfDeepLink.url(for: routePayload())
    var components = try XCTUnwrap(URLComponents(url: valid, resolvingAgainstBaseURL: false))

    components.scheme = "https"
    XCTAssertNil(TopShelfDeepLink.payload(from: try XCTUnwrap(components.url)))

    components.scheme = "moviepilot-tv"
    components.host = "other"
    XCTAssertNil(TopShelfDeepLink.payload(from: try XCTUnwrap(components.url)))

    components.host = "top-shelf"
    components.path = "/play"
    XCTAssertNil(TopShelfDeepLink.payload(from: try XCTUnwrap(components.url)))

    components.path = "/media"
    components.queryItems = [URLQueryItem(name: "payload", value: "%%%not-base64%%%")]
    XCTAssertNil(TopShelfDeepLink.payload(from: try XCTUnwrap(components.url)))
  }

  func testStoreAtomicallyRoundTripsSharedState() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let state = sharedState()

    try store.saveState(state)

    XCTAssertEqual(try store.loadState(), state)
  }

  func testStoreRejectsUnsupportedSchemaAndCorruptJSON() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)

    var unsupported = sharedState()
    unsupported.schemaVersion = TopShelfSharedState.currentSchemaVersion + 1
    try store.saveState(unsupported)
    XCTAssertThrowsError(try store.loadState()) { error in
      XCTAssertEqual(error as? TopShelfSharedStoreError, .unsupportedSchema)
    }

    try Data("{not-json".utf8).write(to: store.stateFileURL, options: .atomic)
    XCTAssertThrowsError(try store.loadState())
  }

  func testStrongInvalidationPublishesNoOldSnapshotWhenDisabledWriteFails() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let goodStore = TopShelfSharedStore(containerURL: fixture.containerURL)
    let path = try goodStore.writeImage(
      TopShelfImageResource(data: Data([1]), fileExtension: "jpg"), cacheKey: "old-valid"
    )
    try goodStore.saveState(sharedState(sessionID: "session-a", imagePath: path))
    XCTAssertNotNil(goodStore.presentation(at: Date()))

    let failingStore = TopShelfSharedStore(
      containerURL: fixture.containerURL,
      writeData: { _, _ in throw TestFailure.injectedWriteFailure }
    )
    let disabled = TopShelfSharedState.disabled(selection: nil)

    XCTAssertThrowsError(try failingStore.invalidatePublishedState(disabled))

    let independentReader = TopShelfSharedStore(containerURL: fixture.containerURL)
    XCTAssertNil(try independentReader.loadState())
    XCTAssertFalse(FileManager.default.fileExists(atPath: independentReader.stateFileURL.path))
  }

  func testFailedCacheWriteDuringRevocationCannotRecoverPreviousOwnerFromPreferences() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let suite = "top-shelf-revoke-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TopShelfSharedStore(
      containerURL: fixture.containerURL, persistentDefaults: defaults)
    try store.saveState(sharedState())
    let failing = TopShelfSharedStore(
      containerURL: fixture.containerURL, persistentDefaults: defaults,
      writeData: { _, _ in throw TestFailure.injectedWriteFailure })
    XCTAssertThrowsError(try failing.invalidatePublishedState(.disabled(selection: nil)))
    try FileManager.default.removeItem(
      at: fixture.containerURL.appendingPathComponent("Library/Caches"))
    let reopened = TopShelfSharedStore(
      containerURL: fixture.containerURL,
      persistentDefaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    XCTAssertNil(try reopened.loadState()?.activeSessionID)
    XCTAssertNil(reopened.presentation(at: Date()))
  }

  func testImageURLRejectsTraversalOutsideSharedImageDirectory() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)

    XCTAssertNil(store.imageURL(relativePath: "../state.json"))
    XCTAssertNil(store.imageURL(relativePath: "/tmp/foreign.jpg"))
    XCTAssertNotNil(store.imageURL(relativePath: "images/session-a/poster.jpg"))
  }

  func testPruneImagesKeepsCurrentPreviousAndRecentOrphans() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let resource = TopShelfImageResource(data: Data([1, 2, 3]), fileExtension: "jpg")
    let current = try store.writeImage(resource, cacheKey: "current")
    let previous = try store.writeImage(resource, cacheKey: "previous")
    let oldOrphan = try store.writeImage(resource, cacheKey: "old-orphan")
    let recentOrphan = try store.writeImage(resource, cacheKey: "recent-orphan")
    let now = Date()
    let oldURL = try XCTUnwrap(store.imageURL(relativePath: oldOrphan))
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-7_200)],
      ofItemAtPath: oldURL.path
    )

    try store.pruneResources(
      keepingRelativePaths: [current, previous],
      now: now,
      gracePeriod: 3_600
    )

    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: try XCTUnwrap(store.imageURL(relativePath: current)).path
      ))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: try XCTUnwrap(store.imageURL(relativePath: previous)).path
      ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: try XCTUnwrap(store.imageURL(relativePath: recentOrphan)).path
      ))
  }

  func testPresentationResolvesOnlyCompleteCurrentSnapshot() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let now = Date(timeIntervalSince1970: 1_700_000_100)
    let selection = TopShelfSelection(shelfID: "recommend/tmdb_trending", title: "流行趋势")
    let imagePath = try store.writeImage(
      TopShelfImageResource(data: Data([1, 2, 3]), fileExtension: "jpg"),
      cacheKey: "presentation"
    )
    let displayURL = try TopShelfDeepLink.url(
      for: routePayload(sessionID: "session-a")
    )
    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-a",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: selection,
          generatedAt: now.addingTimeInterval(-60),
          items: [
            TopShelfSnapshotItem(
              identifier: "themoviedb:550",
              title: "Fight Club",
              imageRelativePath: imagePath,
              displayURL: displayURL
            )
          ]
        )
      )
    )

    let presentation = try XCTUnwrap(store.presentation(at: now))

    XCTAssertEqual(presentation.title, selection.title)
    XCTAssertEqual(presentation.items.first?.identifier, "themoviedb:550")
    XCTAssertEqual(presentation.items.first?.displayURL, displayURL)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: try XCTUnwrap(presentation.items.first?.imageURL).path
      ))
  }

  func testPresentationRejectsForeignOwnerAndEmptyBatches() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let selection = TopShelfSelection(shelfID: "recommend/tmdb_trending", title: "流行趋势")

    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-b",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: selection,
          generatedAt: now,
          items: []
        )
      )
    )
    XCTAssertNil(store.presentation(at: now))

    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-a",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: TopShelfSelection(shelfID: "other", title: "其它"),
          generatedAt: now,
          items: []
        )
      )
    )
    XCTAssertNil(store.presentation(at: now))

    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-a",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: selection,
          generatedAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
          items: []
        )
      )
    )
    XCTAssertNil(store.presentation(at: now))
  }

  func testPresentationRejectsMissingImageAndForeignDeepLinkSession() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let selection = TopShelfSelection(shelfID: "recommend/tmdb_trending", title: "流行趋势")
    let foreignURL = try TopShelfDeepLink.url(for: routePayload(sessionID: "session-b"))
    let missingImageItem = TopShelfSnapshotItem(
      identifier: "themoviedb:550",
      title: "Fight Club",
      imageRelativePath: "images/missing.jpg",
      displayURL: foreignURL
    )
    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-a",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: selection,
          generatedAt: now,
          items: [missingImageItem]
        )
      )
    )

    XCTAssertNil(store.presentation(at: now))

    let imagePath = try store.writeImage(
      TopShelfImageResource(data: Data([1]), fileExtension: "jpg"),
      cacheKey: "foreign-session"
    )
    try store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: "session-a",
        selection: selection,
        snapshot: TopShelfSnapshot(
          sessionID: "session-a",
          selection: selection,
          generatedAt: now,
          items: [
            TopShelfSnapshotItem(
              identifier: missingImageItem.identifier,
              title: missingImageItem.title,
              imageRelativePath: imagePath,
              displayURL: foreignURL
            )
          ]
        )
      )
    )
    XCTAssertNil(store.presentation(at: now))
  }

  func testSharedStateAndImagesLiveUnderSharedCachesAndPreviewChecksOwner() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = TopShelfSharedStore(containerURL: fixture.containerURL)
    let path = try store.writeImage(
      TopShelfImageResource(data: Data([1]), fileExtension: "jpg"), cacheKey: "preview"
    )
    let state = sharedState(sessionID: "session-a", imagePath: path)
    try store.saveState(state)
    let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: state.snapshot!.items[0].displayURL))
    XCTAssertEqual(
      store.stateFileURL,
      fixture.containerURL.appendingPathComponent("Library/Caches/TopShelf/state.json"))
    XCTAssertEqual(
      store.previewImageURL(for: payload, at: Date()), store.imageURL(relativePath: path))
    XCTAssertNil(store.previewImageURL(for: routePayload(sessionID: "session-b"), at: Date()))
    XCTAssertNotNil(
      store.previewImageURL(for: payload, at: Date().addingTimeInterval(30 * 24 * 60 * 60)))
    try FileManager.default.removeItem(at: store.imageURL(relativePath: path)!)
    XCTAssertNil(store.previewImageURL(for: payload, at: Date()))
  }

  private func routePayload(
    sessionID: String = "session-一号/+&=%",
    source: String? = "themoviedb",
    mediaID: String? = "550",
    title: String? = "Fight Club"
  ) -> TopShelfRoutePayload {
    TopShelfRoutePayload(
      sessionID: sessionID,
      source: source,
      mediaID: mediaID,
      mediaIDPrefix: "tmdb",
      tmdbID: 550,
      doubanID: "1292001",
      bangumiID: nil,
      anilistID: nil,
      imdbID: "tt0137523",
      tvdbID: nil,
      title: title,
      type: "电影",
      year: "1999",
      season: nil,
      posterPath: "https://images.example/poster?x=1&y=2",
      collectionID: nil
    )
  }

  private func sharedState(
    sessionID: String = "session-a", imagePath: String = "images/session-a/poster.jpg"
  ) -> TopShelfSharedState {
    let selection = TopShelfSelection(shelfID: "recommend/tmdb_trending", title: "流行趋势")
    let item = TopShelfSnapshotItem(
      identifier: "themoviedb:550",
      title: "Fight Club",
      imageRelativePath: imagePath,
      displayURL: try! TopShelfDeepLink.url(for: routePayload(sessionID: sessionID))
    )
    return TopShelfSharedState(
      schemaVersion: TopShelfSharedState.currentSchemaVersion,
      activeSessionID: sessionID,
      selection: selection,
      snapshot: TopShelfSnapshot(
        sessionID: sessionID,
        selection: selection,
        generatedAt: Date(),
        items: [item]
      )
    )
  }
}

private enum TestFailure: Error {
  case injectedWriteFailure
}

private struct StoreFixture {
  let containerURL: URL

  init() throws {
    containerURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TopShelfSharedTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: containerURL,
      withIntermediateDirectories: true
    )
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: containerURL)
  }
}
