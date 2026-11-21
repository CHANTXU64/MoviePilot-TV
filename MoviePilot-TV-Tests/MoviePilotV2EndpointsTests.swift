import XCTest

@testable import MoviePilot_TV

final class MoviePilotV2EndpointsTests: XCTestCase {
  private func makeMedia(json: String) throws -> MediaInfo {
    let data = Data(json.utf8)
    let raw = try JSONDecoder().decode(MediaInfoJSON.self, from: data)
    return MediaInfo(json: raw)
  }

  func testLegacySupportOnlyCoversParsedBackendsBelowV3() {
    XCTAssertTrue(MoviePilotV2Support.isLegacy(backendVersion: "v2.15.6"))
    XCTAssertTrue(MoviePilotV2Support.isLegacy(backendVersion: " v2.14.0 "))
    XCTAssertFalse(MoviePilotV2Support.isLegacy(backendVersion: "v3.0.0"))
    XCTAssertFalse(MoviePilotV2Support.isLegacy(backendVersion: "v3.2.9"))
    // 读不出版本或无法解析时保持 v3，不能让旧会话误走 v2 形状。
    XCTAssertFalse(MoviePilotV2Support.isLegacy(backendVersion: nil))
    XCTAssertFalse(MoviePilotV2Support.isLegacy(backendVersion: "未知"))
    XCTAssertFalse(MoviePilotV2Support.isLegacy(backendVersion: "v3.0.0-beta"))
  }

  func testResolveSelectsImplementationByParsedVersion() {
    XCTAssertTrue(
      BackendEndpoints.resolve(backendVersion: "v2.15.6") is MoviePilotV2Endpoints
    )
    XCTAssertTrue(
      BackendEndpoints.resolve(backendVersion: "v3.2.9") is V3BackendEndpoints
    )
    // 版本读不出或解析不了时读请求带 v2 兜底，订阅写回直接拒绝。
    XCTAssertTrue(BackendEndpoints.resolve(backendVersion: nil) is UnresolvedBackendEndpoints)
    XCTAssertTrue(
      BackendEndpoints.resolve(backendVersion: "v3.0.0-beta") is UnresolvedBackendEndpoints)
  }

  func testV2IdentityEndpointKeepsSingleMediaKeyInPath() throws {
    let spec = try MoviePilotV2Endpoints().mediaIdentityEndpoint(
      pathPrefix: "/media",
      identity: MediaIdentity(source: "themoviedb", mediaId: "12345"),
      extraParams: ["type_name": "电影"],
      suffix: ""
    )
    XCTAssertEqual(spec.path, "/media/tmdb:12345")
    XCTAssertEqual(spec.params["type_name"], "电影")
    XCTAssertNil(spec.params["media_source"])
    XCTAssertNil(spec.params["media_id"])
  }

  func testV3IdentityEndpointUsesPairedParameters() throws {
    let spec = try V3BackendEndpoints().mediaIdentityEndpoint(
      pathPrefix: "/media",
      identity: MediaIdentity(source: "themoviedb", mediaId: "12345"),
      extraParams: ["type_name": "电影"],
      suffix: ""
    )
    XCTAssertEqual(spec.path, "/media/12345")
    XCTAssertEqual(spec.params["media_source"], "themoviedb")
  }

  func testV2SeasonsAndExistsUseLegacyParameters() throws {
    let identity = MediaIdentity(source: "douban", mediaId: "35593344")
    let seasons = MoviePilotV2Endpoints().mediaSeasonsEndpoint(
      identity: identity, title: "示例", year: "2024", season: "1")
    XCTAssertEqual(seasons.path, "/media/seasons")
    XCTAssertEqual(seasons.params["mediaid"], "douban:35593344")
    XCTAssertEqual(seasons.params["season"], "1")

    let exists = MoviePilotV2Endpoints().mediaServerExistsEndpoint(
      identity: identity,
      media: try makeMedia(
        json: #"{"douban_id": "35593344", "title": "示例", "year": "2024", "type": "电影", "season": 2}"#
      )
    )
    XCTAssertEqual(exists.path, "/mediaserver/exists")
    XCTAssertNil(exists.params["media_source"])
    XCTAssertEqual(exists.params["title"], "示例")
    XCTAssertEqual(exists.params["season"], "2")
  }

  func testV2UsesLegacySourceParameterAndGetActions() {
    XCTAssertEqual(MoviePilotV2Endpoints().mediaSourceQueryKey, "source")
    XCTAssertEqual(MoviePilotV2Endpoints().subscriptionMaintenanceMethod, "GET")
    XCTAssertFalse(MoviePilotV2Endpoints().supportsMediaSourceCatalog)
    XCTAssertTrue(MoviePilotV2Endpoints().mediaServerExistsHitIsSuccessFlag)
    XCTAssertTrue(MoviePilotV2Endpoints().includesDetailTitleFallback)
    XCTAssertEqual(V3BackendEndpoints().mediaSourceQueryKey, "media_source")
    XCTAssertEqual(V3BackendEndpoints().subscriptionMaintenanceMethod, "POST")
    XCTAssertTrue(V3BackendEndpoints().supportsMediaSourceCatalog)
    XCTAssertFalse(V3BackendEndpoints().mediaServerExistsHitIsSuccessFlag)
    XCTAssertFalse(V3BackendEndpoints().includesDetailTitleFallback)
  }

  private func makeSubscribe(_ json: String) throws -> Subscribe {
    try JSONDecoder().decode(Subscribe.self, from: Data(json.utf8))
  }

  func testV3SubscriptionUpdateOnlySendsChangedFields() throws {
    let original = try makeSubscribe(
      #"{"id": 7, "name": "示例", "type": "电视剧", "sites": [1, 2], "quality": "4K"}"#)
    var draft = original
    draft.keyword = "新关键词"
    let data = try V3BackendEndpoints().subscriptionUpdateBody(original: original, draft: draft)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(body.keys), ["id", "keyword"])
  }

  func testV2SubscriptionUpdateSendsFullSnapshot() throws {
    let original = try makeSubscribe(
      #"{"id": 7, "name": "示例", "type": "电视剧", "sites": [1, 2], "quality": "4K", "save_path": "/media/tv", "media_category": "日番", "media_category_id": "cat-1"}"#
    )
    var draft = original
    draft.keyword = "新关键词"
    let data = try MoviePilotV2Endpoints().subscriptionUpdateBody(
      original: original, draft: draft)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    // v2 的 PUT 是整条替换，未提交的站点、画质和保存路径会被清空，所以必须带全量字段。
    XCTAssertEqual(body["name"] as? String, "示例")
    XCTAssertEqual(body["sites"] as? [Int], [1, 2])
    XCTAssertEqual(body["quality"] as? String, "4K")
    XCTAssertEqual(body["save_path"] as? String, "/media/tv")
    XCTAssertEqual(body["keyword"] as? String, "新关键词")
    // 字段集必须与 v2 公共写入字段一一对应：漏一个就会被 v2 的默认值覆盖。
    XCTAssertEqual(
      Set(body.keys),
      Set([
        "id", "name", "year", "type", "keyword", "tmdbid", "doubanid", "bangumiid", "anilistid",
        "mediaid", "media_source", "media_id", "season", "filter", "include", "exclude", "quality",
        "resolution", "effect", "total_episode", "start_episode", "sites", "downloader",
        "best_version", "best_version_full", "save_path", "search_imdbid", "custom_words",
        "media_category", "filter_groups", "episode_group",
      ]))
    // v2 不认识稳定分类 ID，不能把 v3 的键发给它。
    XCTAssertNil(body["media_category_id"])
  }

  func testUnresolvedVersionUsesReadFallbacksButRejectsSubscriptionWrite() throws {
    let endpoints = BackendEndpoints.resolve(backendVersion: "v3.0.0-beta")
    let identity = MediaIdentity(source: "themoviedb", mediaId: "12345")
    let spec = try endpoints.mediaIdentityEndpoint(
      pathPrefix: "/media", identity: identity, extraParams: [:], suffix: "")
    XCTAssertEqual(spec.path, "/media/12345")
    XCTAssertEqual(spec.params["media_source"], "themoviedb")
    XCTAssertEqual(endpoints.subscriptionMaintenanceMethod, "POST")
    XCTAssertTrue(endpoints.supportsMediaSourceCatalog)
    XCTAssertTrue(endpoints.includesDetailTitleFallback)
    XCTAssertTrue(endpoints.mediaServerExistsHitIsSuccessFlag)

    let original = try makeSubscribe(
      #"{"id": 7, "name": "示例", "type": "电视剧", "sites": [1, 2]}"#)
    XCTAssertThrowsError(
      try endpoints.subscriptionUpdateBody(original: original, draft: original)
    ) { error in
      guard case APIError.backendVersionUnavailable = error else {
        return XCTFail("Expected backendVersionUnavailable, got \(error)")
      }
    }
  }
}
