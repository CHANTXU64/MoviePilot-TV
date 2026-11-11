import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeModelCompatibilityTests: XCTestCase {
  func testSubscribeShareRoundTripPreservesBangumiID() throws {
    let payload = #"{"id":88,"name":"Bangumi 分享","type":"电视剧","bangumiid":12345}"#.data(
      using: .utf8)!

    let share = try JSONDecoder().decode(SubscribeShare.self, from: payload)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(share)) as? [String: Any])

    XCTAssertEqual(json["bangumiid"] as? Int, 12345)
  }

  func testSubscribeShareForkRoundTripPreservesV3WritableFields() throws {
    let payload = """
      {
        "id": 91,
        "name": "V3 分享",
        "type": "电视剧",
        "media_source": "themoviedb",
        "media_id": "1396",
        "music_type": "album",
        "total_tracks": 12,
        "audio_quality": "lossless",
        "audio_format": "flac",
        "min_bitrate": 1411000,
        "min_bit_depth": 16,
        "min_sample_rate": 44100,
        "media_category": "剧集",
        "media_category_id": "tv-drama"
      }
      """.data(using: .utf8)!

    let share = try JSONDecoder().decode(SubscribeShare.self, from: payload)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(share)) as? [String: Any])

    XCTAssertEqual(json["id"] as? Int, 91)
    XCTAssertEqual(json["media_source"] as? String, "themoviedb")
    XCTAssertEqual(json["media_id"] as? String, "1396")
    XCTAssertEqual(json["music_type"] as? String, "album")
    XCTAssertEqual(json["total_tracks"] as? Int, 12)
    XCTAssertEqual(json["audio_quality"] as? String, "lossless")
    XCTAssertEqual(json["audio_format"] as? String, "flac")
    XCTAssertEqual(json["min_bitrate"] as? Int, 1_411_000)
    XCTAssertEqual(json["min_bit_depth"] as? Int, 16)
    XCTAssertEqual(json["min_sample_rate"] as? Int, 44100)
    XCTAssertEqual(json["media_category"] as? String, "剧集")
    XCTAssertEqual(json["media_category_id"] as? String, "tv-drama")
  }

  func testNavigationMediaInfoUsesWebIdentityPriorityAndPreservesValidRawIDs() {
    let subscribe = Subscribe(
      name: "Canonical",
      type: "电视剧",
      tmdbid: 42,
      doubanid: " 34943510 ",
      bangumiid: 404_804,
      anilistid: 154_587,
      media_source: "custom",
      media_id: " native-9 ",
      mediaid: "legacy:7"
    )

    let media = subscribe.navigationMediaInfo()

    XCTAssertEqual(media.identity, MediaIdentity(source: "custom", mediaId: "native-9"))
    XCTAssertEqual(media.apiMediaId, "custom:native-9")
    XCTAssertEqual(media.tmdb_id, 42)
    XCTAssertEqual(media.douban_id, "34943510")
    XCTAssertEqual(media.bangumi_id, 404_804)
    XCTAssertEqual(media.anilist_id, 154_587)
    XCTAssertNil(media.mediaid_prefix)
  }

  func testNavigationMediaInfoFallsBackThroughRawAniListAndLegacyWithoutNegativeIDs() {
    let rawBeforeLegacy = Subscribe(
      name: "Raw",
      type: "电视剧",
      tmdbid: 42,
      mediaid: "legacy:7"
    ).navigationMediaInfo()
    let anilistOnly = Subscribe(
      name: "AniList",
      type: "电视剧",
      anilistid: 154_587
    ).navigationMediaInfo()
    let canonicalOnly = Subscribe(
      name: "Custom",
      type: "电影",
      media_source: "custom",
      media_id: "native-9"
    ).navigationMediaInfo()
    let legacyAfterInvalidRaw = Subscribe(
      name: "Legacy",
      type: "电视剧",
      tmdbid: -1,
      bangumiid: 0,
      anilistid: -2,
      mediaid: "tmdb:12345"
    ).navigationMediaInfo()

    XCTAssertEqual(rawBeforeLegacy.apiMediaId, "tmdb:42")
    XCTAssertEqual(anilistOnly.apiMediaId, "anilist:154587")
    XCTAssertEqual(canonicalOnly.apiMediaId, "custom:native-9")
    XCTAssertEqual(legacyAfterInvalidRaw.apiMediaId, "tmdb:12345")
    XCTAssertNil(legacyAfterInvalidRaw.tmdb_id)
    XCTAssertNil(legacyAfterInvalidRaw.bangumi_id)
    XCTAssertNil(legacyAfterInvalidRaw.anilist_id)
  }

  func testNavigationMediaInfoIgnoresIncompleteOrZeroCanonicalPair() {
    let missingId = Subscribe(
      name: "Missing",
      type: "电视剧",
      tmdbid: 42,
      anilistid: 154_587,
      media_source: "anilist",
      media_id: nil
    ).navigationMediaInfo()
    let blankId = Subscribe(
      name: "Blank",
      type: "电视剧",
      tmdbid: 42,
      anilistid: 154_587,
      media_source: " anilist ",
      media_id: " \n "
    ).navigationMediaInfo()
    let zeroId = Subscribe(
      name: "Zero",
      type: "电视剧",
      tmdbid: 42,
      anilistid: 154_587,
      media_source: "anilist",
      media_id: "0"
    ).navigationMediaInfo()
    let zeroSource = Subscribe(
      name: "Zero source",
      type: "电视剧",
      tmdbid: 42,
      anilistid: 154_587,
      media_source: "0",
      media_id: "154587"
    ).navigationMediaInfo()

    XCTAssertEqual(missingId.apiMediaId, "tmdb:42")
    XCTAssertEqual(blankId.identity, missingId.identity)
    XCTAssertEqual(zeroId.identity, missingId.identity)
    XCTAssertEqual(zeroSource.identity, missingId.identity)
        XCTAssertEqual(missingId.source, "themoviedb")
        XCTAssertEqual(missingId.media_id, "42")
  }

  func testSubscribeShareToMediaInfoPreservesAllCurrentIdentityVariants() throws {
    let cases: [(String, MediaIdentity)] = [
      (
        #"{"id":1,"share_title":"Bangumi","type":"电视剧","bangumiid":404804}"#,
        MediaIdentity(source: "bangumi", mediaId: "404804")
      ),
      (
        #"{"id":2,"share_title":"AniList","type":"电视剧","anilistid":154587}"#,
        MediaIdentity(source: "anilist", mediaId: "154587")
      ),
      (
        #"{"id":3,"share_title":"Canonical","type":"电视剧","tmdbid":42,"media_source":"anilist","media_id":"154587"}"#,
        MediaIdentity(source: "anilist", mediaId: "154587")
      ),
      (
        #"{"id":4,"share_title":"Custom","type":"电影","tmdbid":42,"media_source":"custom","media_id":"native-9"}"#,
        MediaIdentity(source: "custom", mediaId: "native-9")
      ),
    ]

    for (payload, expectedIdentity) in cases {
      let share = try JSONDecoder().decode(SubscribeShare.self, from: Data(payload.utf8))
      let media = share.toMediaInfo()

      XCTAssertEqual(media.identity, expectedIdentity)
      XCTAssertEqual(media.id, "share:\(share.raw_id!)")
    }
  }

  func testSubscribeShareToMediaInfoIgnoresIncompleteCanonicalPair() throws {
    let missingId = try JSONDecoder().decode(
      SubscribeShare.self,
      from: Data(
        #"{"id":5,"tmdbid":42,"anilistid":154587,"media_source":"anilist"}"#.utf8
      )
    ).toMediaInfo()
    let blankId = try JSONDecoder().decode(
      SubscribeShare.self,
      from: Data(
        #"{"id":6,"tmdbid":42,"anilistid":154587,"media_source":" anilist ","media_id":"  "}"#.utf8
      )
    ).toMediaInfo()

    XCTAssertEqual(missingId.apiMediaId, "tmdb:42")
    XCTAssertEqual(blankId.identity, missingId.identity)
    XCTAssertNil(missingId.source)
    XCTAssertNil(missingId.media_id)
  }

  func testAddRequestUsesWebSubscriptionFields() throws {
    let subscribe = Subscribe(
      name: "AniList 新订阅",
      type: "电视剧",
      season: 2,
      anilistid: 154_587,
      media_source: "anilist",
      media_id: "154587",
      best_version: 1,
      best_version_full: 1,
      mediaid: "anilist:154587"
    )

    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(subscribe.addRequest))
        as? [String: Any]
    )

    XCTAssertEqual(json["anilistid"] as? Int, 154_587)
    XCTAssertEqual(json["media_source"] as? String, "anilist")
    XCTAssertEqual(json["media_id"] as? String, "154587")
    XCTAssertEqual(json["mediaid"] as? String, "anilist:154587")
    XCTAssertEqual(json["best_version"] as? Int, 1)
    XCTAssertEqual(json["best_version_full"] as? Int, 1)
  }

  func testSubscribeRequestOmitsUnsetBestVersionFieldsAndPreservesExplicitZero() throws {
    let unset = SubscribeRequest(
      name: "默认配置订阅",
      type: "电视剧",
      year: "2026",
      tmdbid: nil,
      doubanid: "douban-1",
      bangumiid: nil,
      mediaid: "douban:douban-1",
      season: 1,
      best_version: nil,
      best_version_full: nil,
      episode_group: nil
    )

    let unsetJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(unset)) as? [String: Any])
    XCTAssertFalse(unsetJSON.keys.contains("best_version"))
    XCTAssertFalse(unsetJSON.keys.contains("best_version_full"))
    XCTAssertEqual(unsetJSON["mediaid"] as? String, "douban:douban-1")

    let explicitNormal = SubscribeRequest(
      name: "显式普通订阅",
      type: "电视剧",
      year: "2026",
      tmdbid: 123,
      doubanid: nil,
      bangumiid: nil,
      mediaid: nil,
      season: 1,
      best_version: 0,
      best_version_full: 0,
      episode_group: nil
    )

    let explicitJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(explicitNormal)) as? [String: Any])
    XCTAssertEqual(explicitJSON["best_version"] as? Int, 0)
    XCTAssertEqual(explicitJSON["best_version_full"] as? Int, 0)
  }
}
