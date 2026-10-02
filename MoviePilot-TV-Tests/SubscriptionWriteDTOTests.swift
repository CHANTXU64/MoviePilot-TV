import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscriptionWriteDTOTests: XCTestCase {
  func testCompleteAndSparseResponsesDecodeTogetherWithoutLosingWritableValues() throws {
    let source = try fixtureObject()
    let sparse: [String: Any] = ["id": 43]
    let data = try JSONSerialization.data(withJSONObject: [source, sparse])
    let subscriptions = try JSONDecoder().decode([Subscribe].self, from: data)

    XCTAssertEqual(subscriptions.count, 2)
    XCTAssertEqual(subscriptions[0].search_interval, 24)
    XCTAssertEqual(subscriptions[0].audio_quality, "lossless")
    XCTAssertEqual(subscriptions[0].audio_format, "FLAC")
    XCTAssertEqual(subscriptions[0].min_bitrate, 320_000)
    XCTAssertEqual(subscriptions[0].min_bit_depth, 24)
    XCTAssertEqual(subscriptions[0].min_sample_rate, 96_000)
    XCTAssertEqual(subscriptions[0].media_category_id, "stable-category")
    XCTAssertEqual(subscriptions[1].name, "")
    XCTAssertEqual(subscriptions[1].type, "")
    assertEqual(try payload(subscriptions[0]), writableProjection(source))
    assertEqual(try payload(subscriptions[1]), sparse)
  }

  func testUnmodifiedFullResponseMatchesCanonicalWritableProjection() throws {
    let source = try fixtureObject()
    let result = try payload(decode(source))

    assertEqual(result, writableProjection(source))
    XCTAssertEqual(Set(result.keys), Self.writableKeys)
    XCTAssertEqual(result["id"] as? Int, 42)
    XCTAssertEqual(result["media_source"] as? String, "themoviedb")
    XCTAssertEqual(result["media_id"] as? String, "100")
    XCTAssertTrue(result["keyword"] is NSNull)
    XCTAssertTrue(result["best_version_full"] is NSNull)
    XCTAssertEqual(result["best_version"] as? Int, 0)
    XCTAssertEqual(result["search_imdbid"] as? Int, 0)
  }

  func testMusicFieldsRemainTypedAndSurviveAnUnmodifiedSave() throws {
    var source = try fixtureObject()
    source["type"] = "音乐"
    source["media_source"] = "musicbrainz"
    source["media_id"] = "d6f1dcd0-ff9d-4b9b-91b9-e3bb18f37c29"
    source["music_type"] = "album"
    source["total_tracks"] = 12
    source["season"] = NSNull()
    let subscription = try decode(source)

    XCTAssertEqual(subscription.music_type, "album")
    XCTAssertEqual(subscription.total_tracks, 12)
    assertEqual(try payload(subscription), writableProjection(source))
  }

  func testOnlyEditingOneFieldPreservesAllOtherWritableValues() throws {
    let source = try fixtureObject()
    var subscription = try decode(source)
    subscription.keyword = "2160p"
    var expected = writableProjection(source)
    expected["keyword"] = "2160p"

    assertEqual(try payload(subscription), expected)
    XCTAssertEqual(try payload(subscription)["media_category_id"] as? String, "stable-category")
  }

  func testExplicitClearsPreserveNullEmptyArrayAndZeroSemantics() throws {
    var source = try fixtureObject()
    source["include"] = " WEB-DL "
    source["exclude"] = " CAM "
    source["quality"] = "BluRay"
    source["downloader"] = "downloader-a"
    source["save_path"] = "/downloads"
    source["custom_words"] = " old => new "
    var subscription = try decode(source)
    subscription.include = nil
    subscription.exclude = ""
    subscription.quality = ""
    subscription.downloader = ""
    subscription.save_path = nil
    subscription.custom_words = nil
    subscription.search_interval = nil
    subscription.total_episode = nil
    subscription.episode_group = nil
    subscription.sites = nil
    subscription.filter_groups = []
    subscription.start_episode = 0
    subscription.best_version_full = 0

    var expected = writableProjection(source)
    for key in [
      "include", "exclude", "quality", "downloader", "save_path", "custom_words",
      "search_interval", "total_episode", "episode_group",
    ] {
      expected[key] = NSNull()
    }
    expected["sites"] = [Int]()
    expected["filter_groups"] = [String]()
    expected["start_episode"] = 0
    expected["best_version_full"] = 0
    assertEqual(try payload(subscription), expected)
  }

  func testSparseMissingFieldsStayOmittedAndExplicitNilAssignmentsClearThem() throws {
    var subscription = try decode(["id": 43])
    assertEqual(try payload(subscription), ["id": 43])

    subscription.search_interval = nil
    subscription.total_episode = nil
    subscription.include = nil
    subscription.sites = nil
    subscription.filter_groups = nil
    assertEqual(
      try payload(subscription),
      [
        "id": 43, "search_interval": NSNull(), "total_episode": NSNull(),
        "include": NSNull(), "sites": [Int](), "filter_groups": [String](),
      ]
    )
  }

  func testSparseNullsAndZeroAreNotInventedDefaults() throws {
    let source: [String: Any] = [
      "id": 44, "name": NSNull(), "type": NSNull(), "year": NSNull(),
      "total_episode": NSNull(), "season": 0, "start_episode": 0,
      "sites": NSNull(), "filter_groups": NSNull(), "search_imdbid": 0,
      "media_source": NSNull(), "media_id": NSNull(),
    ]
    var subscription = try decode(source)
    assertEqual(try payload(subscription), source)

    subscription.name = "新名称"
    subscription.type = "电视剧"
    subscription.sites = []
    subscription.filter_groups = nil
    let result = try payload(subscription)
    XCTAssertEqual(result["name"] as? String, "新名称")
    XCTAssertEqual(result["type"] as? String, "电视剧")
    XCTAssertEqual(result["sites"] as? [Int], [])
    XCTAssertEqual(result["filter_groups"] as? [String], [])
    XCTAssertTrue(result["total_episode"] is NSNull)
  }

  func testManualInitializerOmitsDefaultNilButRetainsExplicitValuesAndLaterClears() throws {
    var subscription = Subscribe(
      id: 45, name: "手动构造", type: "电视剧", season: 0, sites: [],
      search_interval: 12, music_type: "album", total_tracks: 0
    )
    let initial = try payload(subscription)
    XCTAssertFalse(initial.keys.contains("total_episode"))
    XCTAssertFalse(initial.keys.contains("filter_groups"))
    XCTAssertEqual(initial["sites"] as? [Int], [])
    XCTAssertEqual(initial["season"] as? Int, 0)
    XCTAssertEqual(initial["total_tracks"] as? Int, 0)
    XCTAssertEqual(initial["search_interval"] as? Int, 12)

    subscription.search_interval = nil
    subscription.total_episode = nil
    let cleared = try payload(subscription)
    XCTAssertTrue(cleared["search_interval"] is NSNull)
    XCTAssertTrue(cleared["total_episode"] is NSNull)
  }

  func testOtherEditsDoNotTrimPatternsPathsOrCustomWords() throws {
    var source = try fixtureObject()
    for key in ["include", "exclude", "quality", "audio_format", "custom_words", "save_path"] {
      source[key] = "  keep whitespace  "
    }
    var subscription = try decode(source)
    subscription.keyword = "new-keyword"
    var expected = writableProjection(source)
    expected["keyword"] = "new-keyword"

    assertEqual(try payload(subscription), expected)
  }

  func testChangingCategoryPathOmitsOldStableIDInsteadOfSendingNullID() throws {
    var subscription = try decode(fixtureObject())
    subscription.media_category = "电视剧/新分类"
    let result = try payload(subscription)

    XCTAssertFalse(result.keys.contains("media_category_id"))
    XCTAssertEqual(result["media_category"] as? String, "电视剧/新分类")
  }

  func testClearingCategoryPathDoesNotSendOldStableID() throws {
    let clearedPaths: [String?] = [nil, ""]
    for clearedPath in clearedPaths {
      var subscription = try decode(fixtureObject())
      subscription.media_category = clearedPath
      let result = try payload(subscription)

      XCTAssertFalse(result.keys.contains("media_category_id"))
      XCTAssertTrue(result["media_category"] is NSNull)
    }
  }

  func testExplicitPathClearAlsoClearsAStableIDWithoutAPathSnapshot() throws {
    var subscription = try decode(["id": 47, "media_category_id": "stable-category"])
    subscription.media_category = nil
    let result = try payload(subscription)

    XCTAssertFalse(result.keys.contains("media_category_id"))
    XCTAssertTrue(result["media_category"] is NSNull)
  }

  func testRestoringOriginalCategoryPathPreservesStableID() throws {
    var subscription = try decode(fixtureObject())
    let originalPath = subscription.media_category
    subscription.media_category = "电视剧/临时分类"
    subscription.media_category = originalPath

    XCTAssertEqual(try payload(subscription)["media_category_id"] as? String, "stable-category")
    XCTAssertEqual(try payload(subscription)["media_category"] as? String, originalPath)
  }

  func testLegacyCategoryPathWithNullIDIsNotAccidentallyCleared() throws {
    let subscription = try decode([
      "id": 46, "media_category_id": NSNull(), "media_category": "电影/旧目录",
    ])
    let result = try payload(subscription)

    XCTAssertFalse(result.keys.contains("media_category_id"))
    XCTAssertEqual(result["media_category"] as? String, "电影/旧目录")
  }

  func testExplicitlyClearingCategoryIDClearsThePair() throws {
    var subscription = try decode(fixtureObject())
    subscription.media_category_id = nil
    let result = try payload(subscription)

    XCTAssertTrue(result["media_category_id"] is NSNull)
    XCTAssertTrue(result["media_category"] is NSNull)
  }

  func testIdentityCanBeClearedWithoutLegacyIDsBeingWrittenBack() throws {
    var source = try fixtureObject()
    source["tmdbid"] = 100
    source["doubanid"] = "12345"
    source["bangumiid"] = 42
    source["anilistid"] = 43
    source["mediaid"] = "tmdb:100"
    var subscription = try decode(source)
    subscription.media_source = nil
    subscription.media_id = nil
    let result = try payload(subscription)

    XCTAssertTrue(result["media_source"] is NSNull)
    XCTAssertTrue(result["media_id"] is NSNull)
    for key in ["tmdbid", "doubanid", "bangumiid", "anilistid", "mediaid"] {
      XCTAssertFalse(result.keys.contains(key), key)
    }
  }

  func testSystemAndUnknownFieldsNeverReachTheWriteBody() throws {
    var source = try fixtureObject()
    source["last_search"] = "2026-10-01T12:00:00Z"
    source["completed_tracks"] = 4
    source["current_audio_format"] = "FLAC"
    source["current_bitrate"] = 1_411_000
    source["current_bit_depth"] = 24
    source["current_sample_rate"] = 96_000
    source["classification_rule_id"] = "rule-a"
    source["classification_policy_revision"] = 7
    source["classification_source"] = "subscription"
    source["execution_status"] = ["state": "running", "phase": "searching"]
    source["downloaded_tracks"] = ["private-track-key"]
    source["future_server_field"] = "must-not-pass-through"
    var subscription = try decode(source)
    subscription.state = "S"
    subscription.note = .array([.int(999)])
    subscription.current_priority = 100
    let result = try payload(subscription)

    XCTAssertEqual(Set(result.keys), Self.writableKeys)
    assertEqual(result, writableProjection(source))
  }

  private func decode(_ object: [String: Any]) throws -> Subscribe {
    try JSONDecoder().decode(
      Subscribe.self, from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private func payload(_ subscription: Subscribe) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(SubscriptionWriteDTO(subscription)))
        as? [String: Any]
    )
  }

  private func fixtureObject() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.fullFixture.utf8)) as? [String: Any])
  }

  private func writableProjection(_ object: [String: Any]) -> [String: Any] {
    object.filter { Self.writableKeys.contains($0.key) }
  }

  private func assertEqual(
    _ actual: [String: Any], _ expected: [String: Any],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      NSDictionary(dictionary: actual).isEqual(to: expected),
      "实际写体：\(actual)，预期：\(expected)", file: file, line: line
    )
  }

  // app/schemas/subscribe.py 的全部声明字段减 PUBLIC_WRITE_EXCLUDED_FIELDS，再加入 PUT 定位 id。
  // 不读取生产 DTO 白名单作为断言来源，避免测试与实现共享同一处遗漏。
  private static let writableKeys: Set<String> = [
    "id", "name", "year", "type", "search_interval", "keyword", "media_source", "media_id",
    "music_type", "total_tracks", "season", "filter", "include", "exclude", "quality",
    "resolution", "effect", "audio_quality", "audio_format", "min_bitrate", "min_bit_depth",
    "min_sample_rate", "total_episode", "start_episode", "sites", "downloader", "best_version",
    "best_version_full", "save_path", "search_imdbid", "custom_words", "media_category_id",
    "media_category", "filter_groups", "episode_group",
  ]

  // 由官方 v3.0.4 Subscribe schema 在隔离 Python 环境 model_validate/model_dump 生成。
  // v3.0.10-1 与 v3.1.0 的 Subscribe schema blob 同为 d1269dae08f61d91db29f73c1686873c099eb394。
  // 来源固定 commit：e195cc164fc8ff869ffee0ea44a49c7ec475310c；可用 scripts/compatibility/probe_contracts.py 重建。
  // 完整 provenance 见 docs/compatibility-evidence/v3.0.4.json。
  // 这是源码派生 fixture，不是实际部署后端响应；稀疏和编辑案例是上方手工补充的边界输入。
  private static let fullFixture = """
    {
      "id": 42,
      "name": "契约样本",
      "year": "2026",
      "type": "电视剧",
      "search_interval": 24,
      "last_search": null,
      "keyword": null,
      "media_source": "themoviedb",
      "media_id": "100",
      "music_type": null,
      "total_tracks": null,
      "completed_tracks": null,
      "season": 1,
      "poster": null,
      "backdrop": null,
      "vote": 0.0,
      "description": null,
      "filter": null,
      "include": null,
      "exclude": null,
      "quality": null,
      "resolution": null,
      "effect": null,
      "audio_quality": "lossless",
      "audio_format": "FLAC",
      "min_bitrate": 320000,
      "min_bit_depth": 24,
      "min_sample_rate": 96000,
      "total_episode": 12,
      "start_episode": 1,
      "lack_episode": 7,
      "completed_episode": 5,
      "note": [
        1,
        2
      ],
      "state": "R",
      "last_update": null,
      "username": "fixture-owner",
      "sites": [
        1,
        2
      ],
      "downloader": null,
      "best_version": 0,
      "best_version_full": null,
      "current_priority": 50,
      "current_audio_format": null,
      "current_bitrate": null,
      "current_bit_depth": null,
      "current_sample_rate": null,
      "episode_priority": null,
      "save_path": null,
      "search_imdbid": 0,
      "date": null,
      "custom_words": null,
      "media_category_id": "stable-category",
      "media_category": "电视剧/契约",
      "classification_rule_id": null,
      "classification_policy_revision": null,
      "classification_source": null,
      "filter_groups": [
        "保留规则"
      ],
      "episode_group": "group-1",
      "execution_status": null
    }
    """
}
