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
}
