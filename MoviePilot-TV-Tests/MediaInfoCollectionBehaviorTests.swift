import XCTest

@testable import MoviePilot_TV

@MainActor
final class MediaInfoCollectionBehaviorTests: XCTestCase {
  func testKnownMediaTypesUseSpecificPlaceholderIcons() {
    XCTAssertEqual(MediaTypePresentation.placeholderIconName(for: "电影"), "film")
    XCTAssertEqual(MediaTypePresentation.placeholderIconName(for: "电视剧"), "tv")
    XCTAssertEqual(MediaTypePresentation.placeholderIconName(for: "合集"), "rectangle.stack")
    XCTAssertEqual(MediaTypePresentation.placeholderIconName(for: "人物"), "person.fill")
  }

  func testUnknownMediaTypesUseGenericPhotoPlaceholder() {
    for typeText in [nil, "", "新", "阅", "待", "停", "未知类型"] as [String?] {
      XCTAssertEqual(
        MediaTypePresentation.placeholderIconName(for: typeText),
        "photo",
        typeText ?? "nil"
      )
    }
  }

  func testBadgeIconsPreserveExistingTypeBoundary() {
    XCTAssertEqual(MediaTypePresentation.badgeIconName(for: "电影"), "film")
    XCTAssertEqual(MediaTypePresentation.badgeIconName(for: "电视剧"), "tv")
    XCTAssertEqual(MediaTypePresentation.badgeIconName(for: "合集"), "rectangle.stack")
    XCTAssertNil(MediaTypePresentation.badgeIconName(for: "人物"))
    XCTAssertNil(MediaTypePresentation.badgeIconName(for: "新"))
    XCTAssertNil(MediaTypePresentation.badgeIconName(for: nil))
  }

  func testCollectionDisplayTypeUsesCollectionPlaceholderIcon() {
    for media in [
      MediaInfo(type: "collection"),
      MediaInfo(type: "系列"),
      MediaInfo(type: nil, collection_id: 42),
    ] {
      XCTAssertEqual(media.displayTypeText, "合集")
      XCTAssertEqual(
        MediaTypePresentation.placeholderIconName(for: media.displayTypeText),
        "rectangle.stack"
      )
    }
  }

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

  func testPreloadIfNeededSkipsCollectionsAcrossMediaSources() {
    let service = APIService.isolatedTestingInstance()
    let preloader = MediaPreloader(apiService: service)

    for source in ["themoviedb", "douban", "bangumi", "anilist", "plugin"] {
      let media = MediaInfo(
        source: source,
        media_id: "collection-\(source)",
        title: "合集 \(source)",
        type: "合集",
        collection_id: 42
      )

      XCTAssertNil(preloader.preloadIfNeeded(for: media), source)
      XCTAssertNil(
        preloader.preloadAuxiliary(for: media, owner: UUID()),
        source
      )
      XCTAssertNil(preloader.peekTask(for: media), source)
    }

    preloader.clearAll()
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

  func testMediaInfoIdentityTreatsRawZeroAsMissingAndDeclaredBlankFallsBackByBuiltInOrder() {
    // raw 数值 ID 的 0 按 Web 的 JavaScript truthy 语义视为缺失，不再拼出 `themoviedb:0`。
    XCTAssertNil(MediaInfo(tmdb_id: 0).identity)
    XCTAssertNil(MediaInfo(bangumi_id: 0, anilist_id: 0).identity)
    XCTAssertNil(MediaInfo(douban_id: "0").identity)

    XCTAssertEqual(
      MediaInfo(
        tmdb_id: 42,
        anilist_id: 154_587,
        source: "anilist",
        media_id: ""
      ).identity,
      MediaIdentity(source: "themoviedb", mediaId: "42")
    )
    // 响应里显式给出的 `media_id: "0"` 仍按遗留哨兵参与匹配（见 SubscribeSeasonContentViewTests），
    // 与“raw 数值 0 视为缺失”是两条规则；它只在编码请求时被省略。
    XCTAssertEqual(
      MediaInfo(mediaid_prefix: "tmdb", media_id: "0").identity,
      MediaIdentity(source: "themoviedb", mediaId: "0")
    )
  }

  func testMediaInfoEncodingOmitsHalfAndIllegalMediaIdentityPairs() throws {
    func encodedJSON(_ media: MediaInfo) throws -> [String: Any] {
      let data = try JSONEncoder().encode(media)
      return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // 只有 source、没有 media_id：不能编出半对身份（v3 会 422）。
    let halfPair = try encodedJSON(
      MediaInfo(source: "tmdb", media_id: nil, title: "无 ID", type: "电视剧"))
    XCTAssertNil(halfPair["media_source"])
    XCTAssertNil(halfPair["media_id"])

    // 只有 media_id、没有 source：同样不能编出半对身份。
    let missingSource = try encodedJSON(
      MediaInfo(source: nil, mediaid_prefix: "tmdb", media_id: "42", title: "无来源", type: "电视剧"))
    XCTAssertNil(missingSource["media_source"])
    XCTAssertNil(missingSource["media_id"])

    // `media_id: "0"` 在 v3 校验中非法，不能外发。
    let zeroId = try encodedJSON(
      MediaInfo(source: "themoviedb", media_id: "0", title: "零值", type: "电视剧"))
    XCTAssertNil(zeroId["media_source"])
    XCTAssertNil(zeroId["media_id"])

    // 成对且合法时照常写出（来源按调用方给的值原样透传，后端接受 `tmdb` 别名）。
    let complete = try encodedJSON(
      MediaInfo(source: "tmdb", media_id: "42", title: "完整", type: "电视剧"))
    XCTAssertEqual(complete["media_source"] as? String, "tmdb")
    XCTAssertEqual(complete["media_id"] as? String, "42")
  }

  func testExplicitSourceIdentityWinsOverAuxiliaryTMDB() {
    let media = MediaInfo(
      tmdb_id: 42,
      anilist_id: 154_587,
      source: "anilist",
      title: "AniList",
      type: "电视剧"
    )

    XCTAssertEqual(media.identity, MediaIdentity(source: "anilist", mediaId: "154587"))
    XCTAssertEqual(media.apiMediaId, "anilist:154587")
  }

  func testDetailAuxiliaryContentUsesWebBuiltInFieldOrderWithoutChangingPrimaryIdentity() {
    let media = MediaInfo(
      tmdb_id: 42,
      anilist_id: 154_587,
      source: "anilist",
      mediaid_prefix: "anilist",
      media_id: "154587"
    )

    XCTAssertEqual(media.identity, MediaIdentity(source: "anilist", mediaId: "154587"))
    XCTAssertEqual(
      media.auxiliaryContentIdentity,
      MediaIdentity(source: "themoviedb", mediaId: "42")
    )
  }

  func testDetailAuxiliaryContentFallsBackToAniListAfterInvalidEarlierIdentifiers() {
    let media = MediaInfo(
      tmdb_id: 0,
      douban_id: "  ",
      bangumi_id: 0,
      anilist_id: 154_587
    )

    XCTAssertEqual(
      media.auxiliaryContentIdentity,
      MediaIdentity(source: "anilist", mediaId: "154587")
    )
  }

  func testPopularSubscriptionKeyKeepsAniListPrimaryIdentity() {
    let anilistWithAuxiliaryTMDB = MediaInfo(
      tmdb_id: 42,
      source: "anilist",
      mediaid_prefix: "anilist",
      media_id: "154587",
      title: "作品",
      season: 1
    )
    let sameAniListSeason = MediaInfo(
      source: "anilist",
      mediaid_prefix: "anilist",
      media_id: "154587",
      title: "另一标题",
      season: 1
    )
    let otherSeason = MediaInfo(
      source: "anilist",
      mediaid_prefix: "anilist",
      media_id: "154587",
      season: 2
    )

    XCTAssertEqual(
      ExploreViewModel.popularSubscriptionKey(anilistWithAuxiliaryTMDB),
      ExploreViewModel.popularSubscriptionKey(sameAniListSeason)
    )
    XCTAssertNotEqual(
      ExploreViewModel.popularSubscriptionKey(anilistWithAuxiliaryTMDB),
      ExploreViewModel.popularSubscriptionKey(otherSeason)
    )
  }

  func testTmdbSeasonDecodesOffMainActor() async throws {
    let seasonNumber = try await Task.detached {
      try JSONDecoder().decode(
        TmdbSeason.self,
        from: Data(
          #"{"season_number":1,"poster_path":"/season.jpg"}"#.utf8
        )
      ).season_number
    }.value

    XCTAssertEqual(seasonNumber, 1)
  }

  func testMediaIdPrefixWinsOverSourceAndNormalizesTMDBAlias() {
    let custom = MediaInfo(
      tmdb_id: 42,
      source: "themoviedb",
      mediaid_prefix: "tvdb",
      media_id: "series-9"
    )
    let tmdb = MediaInfo(source: "tmdb", media_id: "42")

    XCTAssertEqual(custom.apiMediaId, "tvdb:series-9")
    XCTAssertEqual(custom.identity?.source, "tvdb")
    XCTAssertEqual(tmdb.identity?.source, "themoviedb")
    XCTAssertEqual(tmdb.apiMediaId, "tmdb:42")
  }

  func testV3MediaSourceFieldPopulatesIdentityWithoutLegacySourceKey() throws {
    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        #"{"media_source":"douban","media_id":"34943510","tmdb_id":550,"title":"搏击俱乐部","type":"电影"}"#
          .utf8
      )
    )

    XCTAssertEqual(media.source, "douban")
    XCTAssertEqual(media.identity, MediaIdentity(source: "douban", mediaId: "34943510"))
    XCTAssertEqual(media.apiMediaId, "douban:34943510")
    XCTAssertEqual(media.tmdb_id, 550)
  }

  func testMusicTypeIsNotDirectlySubscribableOnTV() {
    XCTAssertFalse(
      MediaInfo(
        source: "musicbrainz",
        media_id: "abc",
        title: "Album",
        type: "音乐"
      ).canDirectlySubscribe
    )
  }

  func testManualMediaIdAllowsEmptyAndPositiveASCIIDigitsOnly() {
    XCTAssertTrue(MediaIdentifier.isValidManualMediaId(nil))
    XCTAssertTrue(MediaIdentifier.isValidManualMediaId("  "))
    XCTAssertTrue(MediaIdentifier.isValidManualMediaId(" 33674 "))
    XCTAssertFalse(MediaIdentifier.isValidManualMediaId("0"))
    XCTAssertFalse(MediaIdentifier.isValidManualMediaId("000"))
    XCTAssertFalse(MediaIdentifier.isValidManualMediaId("-5"))
    XCTAssertFalse(MediaIdentifier.isValidManualMediaId("33x"))
    XCTAssertFalse(MediaIdentifier.isValidManualMediaId("１２３"))
  }

  func testDeclaredSourceWithoutOwnIdentityFallsBackLikeWeb() {
    let media = MediaInfo(tmdb_id: 42, source: "anilist")

    XCTAssertEqual(media.identity, MediaIdentity(source: "themoviedb", mediaId: "42"))
    XCTAssertEqual(media.apiMediaId, "tmdb:42")
  }

  func testStructuredFallbacksPrecedeLegacyMediaIdWithoutDeclaredSource() {
    XCTAssertEqual(
      MediaIdentifier.resolve(
        tmdbId: 42,
        anilistId: 154_587,
        legacyMediaId: "custom:9"
      ),
      MediaIdentity(source: "themoviedb", mediaId: "42")
    )
    XCTAssertEqual(
      MediaIdentifier.resolve(
        anilistId: 154_587,
        legacyMediaId: "custom:9"
      ),
      MediaIdentity(source: "anilist", mediaId: "154587")
    )
    XCTAssertEqual(
      MediaIdentifier.resolve(legacyMediaId: "custom:9"),
      MediaIdentity(source: "custom", mediaId: "9")
    )
  }

  func testStableMediaKeyUsesWebDedupFields() {
    let anilistWithAuxiliaryIDs = MediaInfo(
      tmdb_id: 42,
      tvdb_id: 99,
      source: "anilist",
      media_id: "154587",
      type: "电视剧",
      season: 1
    )
    let sameAniListSeason = MediaInfo(
      source: "anilist",
      media_id: "154587",
      type: "电视剧",
      season: 1
    )
    let otherSeason = MediaInfo(
      source: "anilist",
      media_id: "154587",
      type: "电视剧",
      season: 2
    )
    let tmdb = MediaInfo(
      source: "themoviedb",
      media_id: "42",
      type: "电视剧",
      season: 1
    )

    XCTAssertNotEqual(anilistWithAuxiliaryIDs.id, sameAniListSeason.id)
    XCTAssertNotEqual(anilistWithAuxiliaryIDs.id, otherSeason.id)
    XCTAssertNotEqual(anilistWithAuxiliaryIDs.id, tmdb.id)

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicate(
        [anilistWithAuxiliaryIDs, sameAniListSeason, otherSeason, tmdb],
        existingKeys: &seenKeys
      ).count,
      4
    )
  }

  func testStableMediaKeyKeepsWebNullAndFieldBoundaries() {
    XCTAssertNotEqual(
      MediaInfo(title: "nil").id,
      MediaInfo(title: "empty", type: "").id
    )
    XCTAssertNotEqual(
      MediaInfo(source: "alpha~beta", type: "gamma").id,
      MediaInfo(source: "alpha", type: "beta~gamma").id
    )
  }

  func testStableMediaKeyUsesTitleOnlyWhenIdentifiersAreMissing() {
    let first = MediaInfo(title: "媒体甲", type: "电影")
    let second = MediaInfo(title: "媒体乙", type: "电影")

    XCTAssertNotEqual(first.id, second.id)
    XCTAssertEqual(
      MediaInfo(title: "  媒体甲\n", type: "电影").id,
      first.id
    )
    XCTAssertEqual(
      MediaInfo(tmdb_id: 42, title: "媒体甲", type: "电影").id,
      MediaInfo(tmdb_id: 42, title: "媒体乙", type: "电影").id
    )

    var seenKeys = Set<String>()
    XCTAssertEqual(
      MediaInfo.deduplicate([first, second], existingKeys: &seenKeys).count,
      2
    )
  }

  func testMediaInfoEncodingPreservesBackendRequestContract() throws {
    let media = MediaInfo(
      json: try JSONDecoder().decode(
        MediaInfoJSON.self,
        from: Data(
          #"{"tmdb_id":42,"douban_id":"34943510","bangumi_id":404804,"anilist_id":154587,"source":"anilist","mediaid_prefix":"anilist","media_id":"154587","title":"测试媒体","type":"电视剧","year":"2026","season":1,"episode_group":"group-a","category":"动画"}"#
            .utf8
        )
      )
    )

    XCTAssertEqual(media.identity, MediaIdentity(source: "anilist", mediaId: "154587"))

    let payload = try JSONDecoder().decode(
      [String: JSONValue].self,
      from: JSONEncoder().encode(media)
    )

    XCTAssertEqual(payload["tmdb_id"], .int(42))
    XCTAssertEqual(payload["douban_id"], .string("34943510"))
    XCTAssertEqual(payload["bangumi_id"], .int(404_804))
    XCTAssertEqual(payload["anilist_id"], .int(154_587))
    XCTAssertEqual(payload["source"], .string("anilist"))
    XCTAssertEqual(payload["mediaid_prefix"], .string("anilist"))
    XCTAssertEqual(payload["media_id"], .string("154587"))
    XCTAssertEqual(payload["title"], .string("测试媒体"))
    XCTAssertEqual(payload["type"], .string("电视剧"))
    XCTAssertEqual(payload["year"], .string("2026"))
    XCTAssertEqual(payload["season"], .int(1))
    XCTAssertEqual(payload["episode_group"], .string("group-a"))
    XCTAssertEqual(payload["category"], .string("动画"))
  }

  func testMediaInfoEncodingPreservesLocallyConstructedSubscribeShare() throws {
    let share = try JSONDecoder().decode(
      SubscribeShare.self,
      from: Data(
        #"{"id":7,"name":"AniList 分享","type":"电视剧","media_source":"anilist","media_id":"154587"}"#
          .utf8
      )
    )
    let media = MediaInfo(title: "测试媒体", subscribeShare: share)

    let decoded = try JSONDecoder().decode(
      MediaInfo.self,
      from: JSONEncoder().encode(media)
    )

    XCTAssertEqual(decoded.subscribeShare, share)
  }

  func testMediaCardSourceUsesSourceOnly() throws {
    let anilist = MediaInfo(tmdb_id: 42, source: "anilist")
    let tvdb = MediaInfo(tmdb_id: 42, mediaid_prefix: "tvdb", media_id: "99")
    let share = try JSONDecoder().decode(
      SubscribeShare.self,
      from:
        #"{"id":7,"name":"AniList 分享","type":"电视剧","media_source":"anilist","media_id":"154587"}"#
        .data(using: .utf8)!
    )
    XCTAssertEqual(MediaSource.from(mediaInfo: anilist), .anilist)
    XCTAssertNil(MediaSource.from(mediaInfo: tvdb))
    XCTAssertNil(MediaSource.from(mediaInfo: share.toMediaInfo()))
    XCTAssertNil(MediaSource.from(source: "tmdb"))
    XCTAssertEqual(MediaSource.from(source: "themoviedb"), .tmdb)
    XCTAssertEqual(MediaSource.from(source: "douban"), .douban)
    XCTAssertEqual(MediaSource.from(source: "bangumi"), .bangumi)
    XCTAssertEqual(MediaSource.anilist.assetName, "anilist")
    XCTAssertEqual(MediaSource.tmdb.assetName, "tmdb")
    XCTAssertEqual(MediaSource.douban.assetName, "douban")
    XCTAssertEqual(MediaSource.bangumi.assetName, "bangumi")
  }
}
