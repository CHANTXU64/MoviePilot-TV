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
    XCTAssertEqual(uniqueItems.map(\.id), ["share:101", "share:102"])
    XCTAssertNotEqual(uniqueItems[0].id, uniqueItems[1].id)
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

  func testSubscriptionShareDedupUsesRawShareIdWhenTitleOrUserChanges() throws {
    let firstPage = try [
      makeShare(rawId: 101, title: "Shared Show", user: "alice")
    ].map { $0.toMediaInfo() }
    let secondPage = try [
      makeShare(rawId: 101, title: "Shared Show Renamed", user: "alice-renamed")
    ].map { $0.toMediaInfo() }

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).map(\.id),
      ["share:101"]
    )
    XCTAssertTrue(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).isEmpty,
      "Subscription share pagination should deduplicate by the backend raw share id used by Web."
    )
  }

  private func makeShare(rawId: Int, title: String = "Shared Show", user: String) throws -> SubscribeShare {
    let data = """
      {
        "id": \(rawId),
        "subscribe_id": 200,
        "share_title": "\(title)",
        "share_user": "\(user)",
        "name": "\(title)",
        "year": "2024",
        "type": "电视剧",
        "keyword": "\(title)",
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
