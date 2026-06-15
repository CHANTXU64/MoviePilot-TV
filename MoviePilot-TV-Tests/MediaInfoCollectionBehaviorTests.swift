import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaInfoCollectionBehaviorTests: XCTestCase {
  func testCollectionDisplayTypeUsesIsCollectionWithoutCollectionId() {
    let media = MediaInfo(type: "collection", collection_id: nil)

    XCTAssertTrue(media.isCollection)
    XCTAssertEqual(media.displayTypeText, "合集")
  }

  func testCollectionMediaDoesNotPreloadDetailWithoutCollectionId() {
    let media = MediaInfo(type: "合集", collection_id: nil)

    XCTAssertTrue(media.isCollection)
    XCTAssertFalse(media.shouldPreloadDetail)
  }
}
