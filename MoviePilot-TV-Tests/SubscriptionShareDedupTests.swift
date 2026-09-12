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
    XCTAssertEqual(
      uniqueItems.map { $0.subscribeShare?.id },
      ["Share-电视剧-9001-s1-alice-sub200", "Share-电视剧-9002-s1-alice-sub200"])
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

  // MARK: - 兜底身份回归（外部审查点名的三组反例）

  /// 反例一：**无效数字媒体 ID 不得挡住后面的有效标识**。
  ///
  /// 后端用 `tmdbid: 0` 表示「没有」。原先 `tmdbid.map(String.init)` 会把它变成非空的
  /// `"0"` 就此选中，排在后面的 `doubanid` 再没机会被看到，两条分享于是共用
  /// `Share-0-...` 而丢掉一条。
  func testZeroTmdbIdFallsThroughToDoubanId() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(rawId: nil, tmdbid: 0, user: "alice", doubanid: "35087580")),
      try makeMediaInfo(
        json: Self.shareJSON(rawId: nil, tmdbid: 0, user: "alice", doubanid: "35087581")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "0 不是有效媒体 ID，必须让位给 doubanid")
    let ids = uniqueItems.compactMap { $0.subscribeShare?.id }
    XCTAssertTrue(ids.allSatisfy { $0.contains("35087580") || $0.contains("35087581") })
    XCTAssertFalse(ids.contains { $0.contains("Share-0-") || $0.contains("-0-") })
  }

  /// 负数的 `tmdbid` 同样不是有效标识。
  func testNegativeTmdbIdIsNotUsedAsMediaIdentity() throws {
    let item = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: -1, user: "alice", doubanid: "35087580"))

    XCTAssertTrue(try XCTUnwrap(item.subscribeShare?.id).contains("35087580"))
  }

  /// 字符串形态的哨兵值（`"0"` / `"-1"`）也不算媒体标识 —— 后端 `doubanid` / `media_id`
  /// 都是字符串，同款判断不能只在数字字段上做。
  func testNumericSentinelStringsAreNotUsedAsMediaIdentity() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          doubanid: "-1", mediaId: "0")),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          doubanid: "0", mediaId: "-1")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "哨兵值不能充当媒体标识，两条记录必须各自成卡")
    XCTAssertFalse(
      uniqueItems.map(\.id).contains { $0.contains("Share-") },
      "媒体标识全无效时必须退回随机身份，而不是拿哨兵值拼一个 `Share-0-...`")
  }

  /// 反例二：**跨来源同号**。不同站点的原生 `media_id` 各自从 1 开始编号，
  /// `"42"` 在两个站点是两部毫不相干的片子，光看数字会撞成一条。
  func testSameMediaIdFromDifferentSourcesDoNotCollide() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          mediaId: "42", mediaSource: "mteam")),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          mediaId: "42", mediaSource: "prowlarr")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "来源不同的同号媒体不是同一条分享")
    XCTAssertEqual(Set(uniqueItems.map(\.id)).count, 2)
  }

  /// 反例三：**同剧不同季**。同一部剧的第 1 季与第 2 季是两条独立分享，
  /// 只用 `tmdbid` 拼身份会合并掉一条。
  func testSameShowDifferentSeasonsDoNotCollide() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", season: 1)),
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", season: 2)),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "同一部剧的不同季是两条分享")
    let ids = uniqueItems.compactMap { $0.subscribeShare?.id }
    XCTAssertTrue(ids.contains { $0.contains("s1") })
    XCTAssertTrue(ids.contains { $0.contains("s2") })
  }

  /// 补上季号之后的边界：同一用户、同一媒体、同一季，但**分享自不同订阅**仍是两条记录。
  func testSameMediaAndSeasonFromDifferentSubscribesDoNotCollide() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", subscribeId: 200)),
      try makeMediaInfo(
        json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", subscribeId: 201)),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2)
  }

  /// 分享人唯一 ID 优先于可改名的 `share_user`：改名不该换身份，换人则必须换身份。
  func testShareUidIsPreferredOverMutableShareUserName() throws {
    let renamed = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: "alice-renamed", shareUid: "uid-alice"))
    let original = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", shareUid: "uid-alice"))
    let otherPerson = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", shareUid: "uid-bob"))

    XCTAssertEqual(renamed.id, original.id, "改显示名不该换身份")
    XCTAssertNotEqual(otherPerson.id, original.id, "换分享人是另一条记录")
  }

  // MARK: - 阴性对照

  /// **关键阴性对照**：身份不是随机的。同一条记录（字段逐字相同）跨页出现时仍必须去重，
  /// 否则分页会把同一张卡重复堆进列表 —— 这是"补字段"不能走向的另一个极端。
  func testIdenticalRecordsStillDeduplicateAcrossPages() throws {
    let json = Self.shareJSON(
      rawId: nil, tmdbid: 9001, user: "alice",
      doubanid: "35087580", mediaId: "42", mediaSource: "mteam", season: 1)
    let firstPage = [try makeMediaInfo(json: json)]
    let secondPage = [try makeMediaInfo(json: json)]

    XCTAssertEqual(firstPage[0].id, secondPage[0].id)

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).count, 1)
    XCTAssertTrue(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).isEmpty)
  }

  /// **关键阴性对照**：补字段没有把身份拆得过散 —— 同一分享的 `share_title` 改一次，
  /// 身份不该跟着变（这是 F-078 的原始口径，不能因为补 season/source 而被推翻）。
  func testFallbackIdentityStillIgnoresMutableDisplayFields() throws {
    let before = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show"))
    let after = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", title: "Renamed"))
    let commented = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show", comment: "hello"))

    XCTAssertEqual(before.id, after.id, "share_title 仍不得进入身份")
    XCTAssertEqual(before.id, commented.id, "share_comment 同样不得进入身份")
  }

  /// 阴性对照：`season` 缺失与 `season: 0` 是两种输入，但都不得把身份压成空 —— 0 是合法季号
  /// （特典/电影），故 0 要参与身份而不是被当成"没给"。
  func testZeroSeasonIsAValidSeasonAndStillProducesIdentity() throws {
    let zero = try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", season: 0))
    let special = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", season: 1))

    XCTAssertNotEqual(zero.id, special.id)
    XCTAssertTrue(try XCTUnwrap(zero.subscribeShare?.id).contains("s0"))
  }

  // MARK: - 夹具

  /// 按字段拼一份分享 JSON。`rawId` 传 nil 表示**不出现** `id` 键（后端 `id` 为 Optional）。
  private static func shareJSON(
    rawId: String?,
    tmdbid: Int?,
    user: String?,
    title: String = "Shared Show",
    includeMediaName: Bool = true,
    doubanid: String? = nil,
    mediaId: String? = nil,
    mediaSource: String? = nil,
    season: Int? = 1,
    subscribeId: Int? = 200,
    shareUid: String? = nil,
    comment: String? = nil
  ) -> String {
    var fields: [String] = []
    if let rawId { fields.append("\"id\": \(rawId)") }
    if let subscribeId { fields.append("\"subscribe_id\": \(subscribeId)") }
    fields.append("\"share_title\": \"\(title)\"")
    if let comment { fields.append("\"share_comment\": \"\(comment)\"") }
    if let user { fields.append("\"share_user\": \"\(user)\"") }
    if let shareUid { fields.append("\"share_uid\": \"\(shareUid)\"") }
    if includeMediaName { fields.append("\"name\": \"\(title)\"") }
    fields.append("\"year\": \"2024\"")
    fields.append("\"type\": \"电视剧\"")
    fields.append("\"keyword\": \"\(title)\"")
    if let tmdbid { fields.append("\"tmdbid\": \(tmdbid)") }
    if let doubanid { fields.append("\"doubanid\": \"\(doubanid)\"") }
    if let mediaId { fields.append("\"media_id\": \"\(mediaId)\"") }
    if let mediaSource { fields.append("\"media_source\": \"\(mediaSource)\"") }
    if let season { fields.append("\"season\": \(season)") }
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
