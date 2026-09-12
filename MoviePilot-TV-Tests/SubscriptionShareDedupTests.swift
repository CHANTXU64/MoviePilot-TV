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

  // MARK: - F-078：非法分享业务 ID 不得破坏稳定身份

  /// `raw_id == 0` 与缺失同义（Web 卡片 key 的 `item.id || ...` 同样把 0 当假值）。
  /// 修复前两条 0 号分享共用 `share:0`，第二条会被静默吞掉。
  func testZeroRawIdSharesDoNotCollapseIntoOneRecord() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: "0", tmdbid: 9001, user: "alice")),
      try makeMediaInfo(json: Self.shareJSON(rawId: "0", tmdbid: 9002, user: "alice")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "0 号分享不再与彼此撞成 share:0，不能丢卡")
    XCTAssertEqual(Set(uniqueItems.map(\.id)).count, 2)
    XCTAssertFalse(uniqueItems.contains { $0.id == "share:0" })
  }

  /// 负数业务 ID 不是有效分享号，与 0/缺失同款处理。
  func testNegativeRawIdSharesDoNotCollapseIntoOneRecord() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: "-1", tmdbid: 9001, user: "alice")),
      try makeMediaInfo(json: Self.shareJSON(rawId: "-2", tmdbid: 9002, user: "alice")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2)
    XCTAssertFalse(uniqueItems.contains { $0.id == "share:-1" || $0.id == "share:-2" })
  }

  /// 缺业务 ID 时身份改用媒体标识，两条不同媒体的分享都存活。
  func testMissingRawIdSharesFallBackToMediaIdentity() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice")),
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9002, user: "alice")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2)
    XCTAssertEqual(uniqueItems.map { $0.subscribeShare?.id }, ["Share-9001-alice", "Share-9002-alice"])
  }

  /// 身份不再依赖可变的 `share_title`：分享人改标题后同一条分享仍被跨页去重，
  /// 不会多出一张重复卡，也不会让 SwiftUI 重建卡片（焦点跳走）。
  func testMissingRawIdIdentitySurvivesShareTitleChange() throws {
    let firstPage = [
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show"))
    ]
    let secondPage = [
      try makeMediaInfo(
        json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show Renamed"))
    ]

    XCTAssertEqual(firstPage[0].id, secondPage[0].id)

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).count, 1)
    XCTAssertTrue(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).isEmpty)
  }

  /// 正业务 ID 时身份只由业务 ID 决定，标题与分享人变化都不影响它。
  func testPositiveRawIdIdentityIgnoresTitleAndUser() throws {
    let renamed = try makeShare(
      json: Self.shareJSON(rawId: "101", tmdbid: 9001, user: "bob", title: "Renamed"))
    let original = try makeShare(rawId: 101, user: "alice")

    XCTAssertEqual(renamed.id, "Share-101")
    XCTAssertEqual(original.id, "Share-101")
  }

  /// 退化输入（连媒体标识都没有）退回随机身份 —— 宁可这条记录每次解码都算作新项
  /// （去重不生效、最多多出一张重复卡），也不能让它被别人撞掉。
  func testShareWithoutAnyIdentityFieldIsNeverDeduplicatedAway() throws {
    let degenerate = Self.shareJSON(rawId: nil, tmdbid: nil, user: nil, includeMediaName: false)
    let first = try makeMediaInfo(json: degenerate)
    let second = try makeMediaInfo(json: degenerate)

    XCTAssertNotEqual(first.id, second.id)

    var seenKeys = Set<String>()
    XCTAssertEqual(MediaInfo.deduplicateSubscriptionShareMedia([first], existingKeys: &seenKeys).count, 1)
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia([second], existingKeys: &seenKeys).count, 1)
  }

  /// 已知残留：后端若给出**重复的正**业务 ID，两条记录仍会被当成同一条而去重掉一条。
  /// 这是"保留去重"的固有代价（Web 靠完全不去重规避），本用例固化现状以免静默漂移。
  func testDuplicatePositiveRawIdsStillCollapseToOneRecord() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: "101", tmdbid: 9001, user: "alice")),
      try makeMediaInfo(json: Self.shareJSON(rawId: "101", tmdbid: 9002, user: "bob")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 1)
    XCTAssertEqual(uniqueItems.map(\.id), ["share:101"])
  }

  // MARK: - 夹具

  /// 按字段拼一份分享 JSON。`rawId` 传 nil 表示**不出现** `id` 键（后端 `id` 为 Optional）。
  private static func shareJSON(
    rawId: String?,
    tmdbid: Int?,
    user: String?,
    title: String = "Shared Show",
    includeMediaName: Bool = true
  ) -> String {
    var fields: [String] = []
    if let rawId { fields.append("\"id\": \(rawId)") }
    fields.append("\"subscribe_id\": 200")
    fields.append("\"share_title\": \"\(title)\"")
    if let user { fields.append("\"share_user\": \"\(user)\"") }
    if includeMediaName { fields.append("\"name\": \"\(title)\"") }
    fields.append("\"year\": \"2024\"")
    fields.append("\"type\": \"电视剧\"")
    fields.append("\"keyword\": \"\(title)\"")
    if let tmdbid { fields.append("\"tmdbid\": \(tmdbid)") }
    fields.append("\"season\": 1")
    fields.append("\"count\": 5")

    return "{\(fields.joined(separator: ","))}"
  }

  private func makeShare(json: String) throws -> SubscribeShare {
    try JSONDecoder().decode(SubscribeShare.self, from: Data(json.utf8))
  }

  private func makeMediaInfo(json: String) throws -> MediaInfo {
    try makeShare(json: json).toMediaInfo()
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
