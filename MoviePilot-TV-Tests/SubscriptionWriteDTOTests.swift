import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscriptionWriteDTOTests: XCTestCase {
  func testCompleteAndSparseResponsesDecodeTogether() throws {
    let source = try fixtureObject()
    let data = try JSONSerialization.data(withJSONObject: [source, ["id": 43]])
    let values = try JSONDecoder().decode([Subscribe].self, from: data)
    XCTAssertEqual(values[0].audio_quality, "lossless")
    XCTAssertEqual(values[0].min_sample_rate, 96_000)
    XCTAssertEqual(values[0].media_category_id, "stable-category")
    XCTAssertEqual(values[1].name, "")
    XCTAssertEqual(values[1].type, "")
    for value in values { assertEqual(try payload(value, value), ["id": value.id!]) }
  }

  func testUnmodifiedSaveOmitsEveryWritableFieldAndKeepsServerValues() throws {
    let source = try fixtureObject()
    let original = try decode(source)
    let update = try payload(original, original)
    assertEqual(update, ["id": 42])
    assertEqual(source.merging(update) { _, new in new }, source)
  }

  func testReadModelEqualityAndHashIgnoreMissingVersusNullKeys() throws {
    let missing = try decode(["id": 42])
    let null = try decode(["id": 42, "keyword": NSNull(), "media_category": NSNull()])
    XCTAssertEqual(missing, null)
    XCTAssertEqual(Set([missing, null]).count, 1)
    XCTAssertEqual(missing, Subscribe(id: 42, name: "", type: ""))
    var draft = null
    draft.media_category = "临时分类"
    draft.media_category = nil
    XCTAssertEqual(draft, missing)
  }

  func testOnlyEditingOneFieldDoesNotResubmitCategoryOrOtherFields() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.keyword = "2160p"
    let update = try payload(original, draft)
    assertEqual(update, ["id": 42, "keyword": "2160p"])
    XCTAssertFalse(update.keys.contains("media_category_id"))
    XCTAssertEqual(original.keyword, nil)
  }

  func testClearsSendNullEmptyArrayZeroAndLiteralEmptyStrings() throws {
    var source = try fixtureObject()
    source["include"] = " WEB-DL "
    source["exclude"] = " CAM "
    source["quality"] = "BluRay"
    source["downloader"] = "downloader-a"
    source["save_path"] = "/downloads"
    source["custom_words"] = " old => new "
    let original = try decode(source)
    var draft = original
    draft.include = nil
    draft.exclude = ""
    draft.quality = ""
    draft.downloader = nil
    draft.save_path = nil
    draft.custom_words = nil
    draft.search_interval = nil
    draft.total_episode = nil
    draft.episode_group = nil
    draft.sites = []
    draft.filter_groups = []
    draft.start_episode = 0
    draft.best_version_full = 0
    var expected: [String: Any] = [
      "id": 42, "exclude": "", "quality": "", "sites": [Int](),
      "filter_groups": [String](), "start_episode": 0, "best_version_full": 0,
    ]
    for key in [
      "include", "downloader", "save_path", "custom_words", "search_interval",
      "total_episode", "episode_group",
    ] { expected[key] = NSNull() }
    assertEqual(try payload(original, draft), expected)
  }

  func testSparseAndManuallyConstructedValuesUseTheSameDifferenceRules() throws {
    for original in [try decode(["id": 43]), Subscribe(id: 43, name: "", type: "")] {
      var draft = original
      draft.search_interval = nil
      draft.sites = []
      draft.keyword = "4K"
      assertEqual(try payload(original, draft), ["id": 43, "sites": [Int](), "keyword": "4K"])
    }
  }

  func testRestoringOriginalCategoryOmitsCategoryChanges() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.media_category = "电视剧/临时分类"
    draft.media_category = original.media_category
    assertEqual(try payload(original, draft), ["id": 42])
  }

  func testEditingCategoryPathOmitsOldIDAndClearingSendsNull() throws {
    let original = try decode(fixtureObject())
    let paths: [String?] = ["电视剧/新分类", nil, ""]
    for path in paths {
      var draft = original
      draft.media_category = path
      let expectedPath: Any = path == nil || path == "" ? NSNull() : path!
      assertEqual(try payload(original, draft), ["id": 42, "media_category": expectedPath])
    }
  }

  func testChangingOnlyStableCategoryIDUsesBackendIDResolution() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.media_category_id = "new-category"
    assertEqual(try payload(original, draft), ["id": 42, "media_category_id": "new-category"])
  }

  func testExplicitlyClearingSparseCategoryIDClearsCategory() throws {
    let original = try decode(["id": 47, "media_category_id": "stable-category"])
    var draft = original
    draft.media_category_id = nil
    assertEqual(try payload(original, draft), ["id": 47, "media_category_id": NSNull()])
  }

  func testPatternsPathsAndCustomWordsKeepWhitespaceWhenEdited() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.include = "  ^WEB.*$  "
    draft.audio_format = "  FLAC|AAC  "
    draft.save_path = "  /downloads/路径  "
    draft.custom_words = "  old => new  "
    assertEqual(
      try payload(original, draft),
      [
        "id": 42, "include": draft.include!,
        "audio_format": draft.audio_format!, "save_path": draft.save_path!,
        "custom_words": draft.custom_words!,
      ])
  }

  func testMediaIdentityChangesSendBothKeysAndExcludeLegacyIDs() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.media_source = "musicbrainz"
    assertEqual(
      try payload(original, draft), ["id": 42, "media_source": "musicbrainz", "media_id": "100"])
    draft.media_source = nil
    draft.media_id = nil
    draft.tmdbid = 999
    assertEqual(
      try payload(original, draft), ["id": 42, "media_source": NSNull(), "media_id": NSNull()])
  }

  func testBackendMaintainedFieldsNeverReachWriteBody() throws {
    let original = try decode(fixtureObject())
    var draft = original
    draft.state = "S"
    draft.note = .array([.int(999)])
    draft.current_priority = 100
    draft.completed_episode = 99
    assertEqual(try payload(original, draft), ["id": 42])
  }

  func testEveryPublicWritableFieldCanBeChanged() throws {
    let original = Subscribe(id: 42, name: "", type: "")
    var source = try fixtureObject()
    for key in [
      "keyword", "music_type", "filter", "include", "exclude", "quality", "resolution",
      "effect", "custom_words", "save_path",
    ] { source[key] = "changed" }
    source["downloader"] = "downloader-b"
    source["total_tracks"] = 0
    source["best_version_full"] = 0
    let draft = try decode(source)
    let update = try payload(original, draft)
    let expected = Self.writableKeys.subtracting(["media_category_id"])
    XCTAssertEqual(Set(update.keys), expected)
  }

  func testChangedOrMissingTargetFailsEncoding() throws {
    let original = Subscribe(id: 42, name: "测试", type: "电影")
    var draft = original
    draft.id = 43
    XCTAssertThrowsError(
      try JSONEncoder().encode(SubscriptionWriteDTO(original: original, draft: draft)))
    let missing = Subscribe(name: "测试", type: "电影")
    XCTAssertThrowsError(
      try JSONEncoder().encode(SubscriptionWriteDTO(original: missing, draft: missing)))
  }

  private func decode(_ object: [String: Any]) throws -> Subscribe {
    try JSONDecoder().decode(
      Subscribe.self, from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private func payload(_ original: Subscribe, _ draft: Subscribe) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
          SubscriptionWriteDTO(original: original, draft: draft))) as? [String: Any])
  }

  private func fixtureObject() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.fullFixture.utf8)) as? [String: Any])
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

  // 来源为官方公共写入 schema，独立于生产 DTO 的实现。
  private static let writableKeys: Set<String> = [
    "id", "name", "year", "type", "search_interval", "keyword", "media_source", "media_id",
    "music_type", "total_tracks", "season", "filter", "include", "exclude", "quality",
    "resolution", "effect", "audio_quality", "audio_format", "min_bitrate", "min_bit_depth",
    "min_sample_rate", "total_episode", "start_episode", "sites", "downloader", "best_version",
    "best_version_full", "save_path", "search_imdbid", "custom_words", "media_category_id",
    "media_category", "filter_groups", "episode_group",
  ]

  // 按官方 app/schemas/subscribe.py（v3.0.4 至 v3.1.0 内容一致）的完整字段整理的订阅详情响应。
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
