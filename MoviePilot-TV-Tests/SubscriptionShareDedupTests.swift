import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscriptionShareDedupTests: XCTestCase {
  func testLocalSubscriptionIdWithoutOwnerDoesNotMergeDistinctShares() throws {
    try assertMissingShareUidKeepsDistinctShares(user: nil, shareUid: nil)
  }

  func testDuplicateDisplayNamesCannotScopeLocalSubscriptionIds() throws {
    try assertMissingShareUidKeepsDistinctShares(user: "MoviePilot", shareUid: nil)
  }

  func testWhitespaceShareUidCannotScopeLocalSubscriptionIds() throws {
    try assertMissingShareUidKeepsDistinctShares(user: "MoviePilot", shareUid: " \n ")
  }

  func testStableUidAndSubscriptionIdDeduplicateWithoutDisplayName() throws {
    let json = Self.shareJSON(rawId: nil, tmdbid: 42, user: nil, shareUid: "instance-a")
    let first = try makeMediaInfo(json: json)
    let second = try makeMediaInfo(json: json)
    var keys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia([first, second], existingKeys: &keys).count, 1)
    XCTAssertTrue(try XCTUnwrap(first.subscribeShare?.id).hasPrefix("Share|"))
  }

  func testNumericLookingShareUidsRemainStableAndDistinct() throws {
    let records = try ["0", "-1"].map { uid in
      let json = Self.shareJSON(rawId: nil, tmdbid: 42, user: nil, shareUid: uid)
      let first = try makeMediaInfo(json: json)
      XCTAssertEqual(first.id, try makeMediaInfo(json: json).id)
      return first
    }
    XCTAssertNotEqual(records[0].id, records[1].id)
  }

  private func assertMissingShareUidKeepsDistinctShares(user: String?, shareUid: String?) throws {
    let items = try ["4K", "1080p"].map { quality in
      var payload: [String: Any] = [
        "subscribe_id": 1, "share_title": quality, "quality": quality,
        "name": "Same Show", "type": "电视剧", "tmdbid": 42, "season": 1,
      ]
      if let user { payload["share_user"] = user }
      if let shareUid { payload["share_uid"] = shareUid }
      return try JSONDecoder().decode(
        SubscribeShare.self, from: JSONSerialization.data(withJSONObject: payload)).toMediaInfo()
    }
    var seenKeys = Set<String>()
    let unique = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)
    XCTAssertEqual(unique.count, 2, "本地订阅编号和可重复的显示名不足以识别同一分享")
    for item in unique {
      XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(item.subscribeShare?.id)))
    }
  }

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
    XCTAssertEqual(Set(uniqueItems.compactMap { $0.subscribeShare?.id }).count, 2)
    // 身份必须真的落在被搜到的那部媒体上，而不是两条都退回随机身份。
    XCTAssertEqual(
      uniqueItems.compactMap { $0.subscribeShare?.id }.filter { $0.contains("tmdbid:") }.count, 2)
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
    let degenerate = Self.shareJSON(
      rawId: nil, tmdbid: nil, user: nil, includeMediaName: false, shareUid: nil)
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
    XCTAssertTrue(ids.allSatisfy { $0.contains("doubanid:3508758") })
    XCTAssertFalse(ids.contains { $0.contains("tmdbid:") }, "无效 tmdbid 不得进入身份")
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
    let firstJSON = Self.shareJSON(
      rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
      doubanid: "-1", mediaId: "0")
    let items = [
      try makeMediaInfo(json: firstJSON),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          doubanid: "0", mediaId: "-1")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(uniqueItems.count, 2, "哨兵值不能充当媒体标识，两条记录必须各自成卡")

    // 三审反例 C：这里原先断言「`id` 不含 `Share-`」，但确定性兜底 key 早已改成 `Share|n|…`，
    // 该断言对「是否真的退回了随机身份」毫无判别力 —— 实测把 `normalizedTextIdentifier` 里的
    // 哨兵判据**整条删掉**，本用例与相邻两条「哨兵」用例依然全绿。改为直接验证身份是 UUID。
    for shareID in uniqueItems.compactMap({ $0.subscribeShare?.id }) {
      XCTAssertNotNil(
        UUID(uuidString: shareID),
        "媒体标识全无效时必须退回随机身份，实际得到 `\(shareID)`")
    }

    // 「随机」不能只是名义上的：同一份退化输入再解码一次必须得到**不同**身份。
    let again = try makeMediaInfo(json: firstJSON)
    var repeatKeys = Set<String>()
    let reparsed = MediaInfo.deduplicateSubscriptionShareMedia([again], existingKeys: &repeatKeys)

    XCTAssertNotEqual(
      reparsed.first?.subscribeShare?.id, uniqueItems.first?.subscribeShare?.id,
      "同一份退化输入两次解析必须各自成卡，否则一旦拼出确定 key 就会跨页去重、漏卡")
  }

  /// 三审反例 C 的**判别力对照**：守着「文本型哨兵值不算媒体标识」的其实是这一条。
  ///
  /// 两条记录其实是同一部豆瓣片子，只是其中一条多带了个 `media_id: "0"` 哨兵。
  /// 哨兵判据在位 → `media_id` 让位给有效的 `doubanid` → 两条拼出同一身份 → 并成一条；
  /// 判据被删 → `media_id:"0"` 会被当成真标识 → 两条分道扬镳。
  func testTextSentinelMediaIdYieldsToValidDoubanId() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          doubanid: "12345", mediaId: "0")),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false,
          doubanid: "12345")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(
      uniqueItems.count, 1,
      "`media_id` 的 \"0\" 是哨兵，必须让位给有效的 `doubanid` —— 这两条是同一部片子")
  }

  /// **阴性对照（本轮降级）**：`share_user` 已整体退出身份构造，本用例对身份**没有判别力** ——
  /// 两条记录各自成卡的唯一原因是**缺实例 `share_uid`**（退回随机身份），与显示名长什么样无关：
  /// 把 `"0"` / `"-1"` 换成任意别的名字，结果一模一样。留着只为守住一条：
  /// 显示名在模型上原样保留，不被任何规范化/哨兵规则改写。
  func testNumericLookingShareUserNamesAreNotTreatedAsSentinels() throws {
    let items = [
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "0", shareUid: nil)),
      try makeMediaInfo(json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "-1", shareUid: nil)),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(
      uniqueItems.count, 2,
      "分享人叫「0」和叫「-1」是两个人，不能因为名字长得像数字就当成同一条分享")
    XCTAssertEqual(uniqueItems.compactMap { $0.subscribeShare?.share_user }, ["0", "-1"])
  }

  /// 三审反例 B①：只知道「谁分享的」、不知道「分享自哪条订阅」时，当前实现照样生成确定身份。
  ///
  /// 同一个人的两条分享（2160p / 1080p，标题也不同）会被并成一条。
  func testSameSharerWithoutSubscribeIdDoesNotMergeDistinctShares() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show 2160p",
          subscribeId: nil, shareUid: "uid-alice")),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: 9001, user: "alice", title: "Shared Show 1080p",
          subscribeId: nil, shareUid: "uid-alice")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(
      uniqueItems.count, 2,
      "缺 subscribe_id 时仅凭「同一分享人 + 同一媒体」不足以断定是同一条分享")
  }

  /// 三审反例 B②：媒体 ID 全缺、只剩订阅名称兜底时，同名不同年的两部片子会撞成一条。
  func testSameNameDifferentYearsDoNotCollideWhenOnlyNameIsAvailable() throws {
    let items = [
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", title: "同名电影",
          subscribeId: nil, shareUid: "uid-alice", year: "1984")),
      try makeMediaInfo(
        json: Self.shareJSON(
          rawId: nil, tmdbid: nil, user: "alice", title: "同名电影",
          subscribeId: nil, shareUid: "uid-alice", year: "2021")),
    ]

    var seenKeys = Set<String>()
    let uniqueItems = MediaInfo.deduplicateSubscriptionShareMedia(items, existingKeys: &seenKeys)

    XCTAssertEqual(
      uniqueItems.count, 2,
      "同名电影 1984 与 2021 是两部片子，光凭名称相同不能认定是同一条分享")
  }

  /// **代价固化（三审裁决的已知取舍，不是缺陷）**：收紧为「必须有 `subscribe_id`」之后，
  /// 缺 `subscribe_id` 的记录不再有确定身份 —— 同一份分享在两页各出现一次时**不会**被并掉，
  /// 用户会看到两张重复卡。
  ///
  /// 这是刻意选的：可见的重复卡好过看不见的漏卡。写在这里是为了让它显式存在，
  /// 将来若有人想「顺手把跨页重复也合掉」，会先看到这条再决定要不要推翻该取舍。
  func testRecordsWithoutSubscribeIdAreKnowinglyNotDeduplicatedAcrossPages() throws {
    let json = Self.shareJSON(
      rawId: nil, tmdbid: 9001, user: "alice", subscribeId: nil, shareUid: "uid-alice")
    let firstPage = [try makeMediaInfo(json: json)]
    let secondPage = [try makeMediaInfo(json: json)]

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).count,
      1)
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).count,
      1,
      "缺 subscribe_id 时信息不足以断定是同一条分享，跨页不再合并 —— 已裁决接受的代价")
  }

  /// **代价固化（四审 P2 的已知取舍，不是缺陷）**：门槛收紧为「必须有安装实例 `share_uid`」之后，
  /// 缺 `share_uid` 的记录同样只剩随机身份 —— 同一份分享在两页各出现一次时**不会**被并掉。
  ///
  /// 与上一条同源：`share_uid` 是后端 `generate_user_unique_id()` 对根文件系统 inode/MAC
  /// 取的 SHA-256（`helper/server.py:111` 自述「当前安装实例…稳定用户 ID」），是唯一可靠的
  /// 跨实例身份；缺它就等于不知道这条分享从哪台机器来。宁可多一张看得见的重复卡。
  func testRecordsWithoutShareUidAreKnowinglyNotDeduplicatedAcrossPages() throws {
    let json = Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", shareUid: nil)
    let firstPage = [try makeMediaInfo(json: json)]
    let secondPage = [try makeMediaInfo(json: json)]

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(firstPage, existingKeys: &seenKeys).count,
      1)
    XCTAssertEqual(
      MediaInfo.deduplicateSubscriptionShareMedia(secondPage, existingKeys: &seenKeys).count,
      1,
      "缺 share_uid 时信息不足以断定是同一条分享，跨页不再合并 —— 已裁决接受的代价")
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
    XCTAssertEqual(Set(uniqueItems.compactMap { $0.subscribeShare?.id }).count, 2)
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
  }

  // MARK: - 兜底身份的编码必须是可逆的（外部审查第二轮点名的撞键）

  /// `media_id` 与 `tmdbid` 是两个字段，值相同也不得合成同一个分量。
  /// 修复前媒体标识那一槽是「第一个有效值」且不带字段名，站点原生 ID `"9001"`
  /// 与 `tmdbid: 9001` 会拼出完全一样的分量，两条本不相干的分享撞成一条。
  func testSiteNativeIdAndTmdbIdDoNotCollide() throws {
    let byNativeId = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false, mediaId: "9001"))
    let byTmdbId = try makeMediaInfo(
      json: Self.shareJSON(rawId: nil, tmdbid: 9001, user: "alice", includeMediaName: false))

    XCTAssertNotEqual(byNativeId.id, byTmdbId.id, "media_id=9001 与 tmdbid=9001 是两条记录")
  }

  /// `media_source` 是独立槽位，不参与拼串。修复前 `joined(separator: "-")` 让
  /// 「`media_source=mteam` + `media_id=42`」与光秃秃的 `media_id="mteam-42"` 撞在一起
  /// （须无 `type` 时成立，故此处显式省掉该字段）。
  func testSourceFieldAndDashedMediaIdDoNotCollide() throws {
    let withSource = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false, includeType: false,
        mediaId: "42", mediaSource: "mteam"))
    let dashedMediaId = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: nil, user: "alice", includeMediaName: false, includeType: false,
        mediaId: "mteam-42"))

    XCTAssertNotEqual(withSource.id, dashedMediaId.id)
  }

  /// 季号与实例 UID 使用独立槽位，UID 中的分隔符不能冒充季号。
  func testSeasonFieldAndDashedShareUidDoNotCollide() throws {
    let withSeason = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: nil, includeMediaName: false, season: 1, shareUid: "alice"))
    let dashedUser = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: nil, includeMediaName: false, season: nil, shareUid: "s1-alice"))

    XCTAssertNotEqual(withSeason.id, dashedUser.id)
  }

  /// 身份只认安装实例 `share_uid`：它同值也好、跟显示名撞名也好，都不影响判定；
  /// 反过来，缺了它就只有随机身份，显示名写什么都不足以顶替。
  ///
  /// 本轮之前 `share_user` 还占一个 `n:` 槽，本用例守的是「`u:`/`n:` 不互撞」；
  /// 现在该槽已整体删除，判别力落到第二条断言（缺 UID ⇒ 随机身份）上。
  func testShareUidAndShareUserWithSameValueDoNotCollide() throws {
    let byUid = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: nil, includeMediaName: false, shareUid: "alice"))
    let byUserName = try makeMediaInfo(
      json: Self.shareJSON(
        rawId: nil, tmdbid: 9001, user: "alice", includeMediaName: false, shareUid: nil))

    XCTAssertNotEqual(byUid.id, byUserName.id)
    XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(byUserName.subscribeShare?.id)))
  }

  // MARK: - 夹具

  /// 按字段拼一份分享 JSON。`rawId` 传 nil 表示**不出现** `id` 键（后端 `id` 为 Optional）。
  /// 确定性身份用例默认带有效实例 UID；测试缺 UID 的退化输入时必须显式传 nil。
  private static func shareJSON(
    rawId: String?,
    tmdbid: Int?,
    user: String?,
    title: String = "Shared Show",
    includeMediaName: Bool = true,
    includeType: Bool = true,
    doubanid: String? = nil,
    mediaId: String? = nil,
    mediaSource: String? = nil,
    season: Int? = 1,
    subscribeId: Int? = 200,
    shareUid: String? = "uid-alice",
    comment: String? = nil,
    year: String = "2024"
  ) -> String {
    var fields: [String] = []
    if let rawId { fields.append("\"id\": \(rawId)") }
    if let subscribeId { fields.append("\"subscribe_id\": \(subscribeId)") }
    fields.append("\"share_title\": \"\(title)\"")
    if let comment { fields.append("\"share_comment\": \"\(comment)\"") }
    if let user { fields.append("\"share_user\": \"\(user)\"") }
    if let shareUid { fields.append("\"share_uid\": \"\(shareUid)\"") }
    if includeMediaName { fields.append("\"name\": \"\(title)\"") }
    fields.append("\"year\": \"\(year)\"")
    if includeType { fields.append("\"type\": \"电视剧\"") }
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
