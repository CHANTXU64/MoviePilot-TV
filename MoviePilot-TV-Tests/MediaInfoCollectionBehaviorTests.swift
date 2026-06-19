import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaInfoCollectionBehaviorTests: XCTestCase {
  func testCollectionDisplayTypeUsesIsCollectionWithoutCollectionId() {
    let media = MediaInfo(type: "collection", collection_id: nil)

    XCTAssertFalse(media.isCollection)
    XCTAssertEqual(media.displayTypeText, "合集")
  }

  func testCollectionLikeMediaPreloadsDetailWithoutCollectionId() {
    let media = MediaInfo(type: "合集", collection_id: nil)

    XCTAssertFalse(media.isCollection)
    XCTAssertEqual(media.displayTypeText, "合集")
    XCTAssertTrue(media.shouldPreloadDetail)
  }

  func testCollectionMediaDoesNotPreloadDetailWhenCollectionIdExists() {
    let media = MediaInfo(type: "系列", collection_id: 123)

    XCTAssertTrue(media.isCollection)
    XCTAssertEqual(media.displayTypeText, "合集")
    XCTAssertFalse(media.shouldPreloadDetail)
  }

  func testMediaInfoApiMediaIdFallsBackWhenPrimaryIdentifiersAreInvalid() {
    let media = MediaInfo(
      tmdb_id: 0,
      douban_id: "  ",
      bangumi_id: 0,
      mediaid_prefix: "tmdb",
      media_id: "12345",
      type: "电视剧"
    )

    XCTAssertEqual(media.apiMediaId, "tmdb:12345")
  }

  func testMediaInfoApiMediaIdRejectsMalformedNumericFallbackIdentifiers() {
    let invalidFallbacks = [
      ("tmdb", "-1"),
      ("tmdb", "abc"),
      ("bangumi", "-1"),
      ("bangumi", "abc"),
    ]

    for (prefix, id) in invalidFallbacks {
      let media = MediaInfo(mediaid_prefix: prefix, media_id: id, type: "电视剧")

      XCTAssertNil(media.apiMediaId, "Expected \(prefix):\(id) to be rejected")
    }
  }
}
