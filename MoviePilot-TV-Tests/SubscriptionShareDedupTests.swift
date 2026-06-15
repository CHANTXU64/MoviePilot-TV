import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscriptionShareDedupTests: XCTestCase {
  func testSubscriptionShareDedupKeepsDifferentShareRecordsForSameMedia() throws {
    let mediaItems = try [
      makeShare(rawId: 101, user: "alice"),
      makeShare(rawId: 102, user: "bob"),
    ].map { $0.toMediaInfo() }

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(
      mediaItems,
      existingKeys: &seenKeys
    )

    XCTAssertEqual(uniqueItems.compactMap { $0.subscribeShare?.raw_id }, [101, 102])
  }

  func testSubscriptionShareDedupFiltersSameShareAcrossPages() throws {
    let firstPage = try [makeShare(rawId: 101, user: "alice")].map { $0.toMediaInfo() }
    let secondPage = try [makeShare(rawId: 101, user: "alice")].map { $0.toMediaInfo() }

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).count,
      1
    )
    XCTAssertTrue(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).isEmpty
    )
  }

  private func makeShare(rawId: Int, user: String) throws -> SubscribeShare {
    let data = """
      {
        "id": \(rawId),
        "subscribe_id": 200,
        "share_title": "Shared Show",
        "share_user": "\(user)",
        "name": "Shared Show",
        "year": "2024",
        "type": "电视剧",
        "keyword": "Shared Show",
        "tmdbid": 9001,
        "season": 1,
        "poster": "/shared-show.jpg",
        "vote": 8.5,
        "count": 5
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(SubscribeShare.self, from: data)
  }
}
