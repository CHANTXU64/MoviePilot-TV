import XCTest

@testable import MoviePilot_TV

@MainActor
final class APIServiceCompatibilityEndpointTests: XCTestCase {
  func testFetchSettingsReadsPublicBackendVersion() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = nil

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.FRONTEND_VERSION, "v2.13.15")
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/system/global" }, ["/api/v1/system/global"])
    let queries = await CompatibilityEndpointURLProtocol.stub.requestQueries()
    XCTAssertEqual(
      queries.compactMap { $0 }.filter { $0 == "token=moviepilot" },
      ["token=moviepilot"]
    )
  }

  func testLoginSendsFormURLEncodedBodyWithEscapedSpecialCharacters() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = nil

    do {
      _ = try await service.login(
        username: "user+plus",
        password: "p%ss&C++ 密"
      )
      XCTFail("Expected stub token decoding to fail")
    } catch {
      // stub 默认响应无法解码为 Token，登录必然失败；重点是捕获实际请求体。
    }

    let capturedBody = await CompatibilityEndpointURLProtocol.stub.requestBody(
      suffix: "/login/access-token"
    )
    let body = try XCTUnwrap(capturedBody)
    let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
    XCTAssertTrue(bodyString.contains("username=user%2Bplus"))
    XCTAssertTrue(bodyString.contains("password=p%25ss%26C%2B%2B%20%E5%AF%86"))
    XCTAssertFalse(bodyString.contains("user+plus"))
    XCTAssertFalse(bodyString.contains("C++"))
  }

  func testSearchMediaEncodesQueryValuesLikeWebAxios() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = nil

    _ = try await service.searchMedia(query: "C++ 电影", page: 1)

    let queries = await CompatibilityEndpointURLProtocol.stub.matchingQueries(
      suffix: "/media/search"
    )
    let query = try XCTUnwrap(queries.compactMap { $0 }.last)
    XCTAssertTrue(query.contains("title=C%2B%2B%20%E7%94%B5%E5%BD%B1"))
    XCTAssertFalse(query.contains("title=C++"))
  }

  func testFetchSettingsRejectsExplicitFailureBeforeDecodingWrappedData() async {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = nil

    for wrappedData in ["{}", "[]"] {
      await CompatibilityEndpointURLProtocol.stub.reset()
      await CompatibilityEndpointURLProtocol.stub.setPublicSettingsResponse(
        Data(
          """
          {"success":false,"message":"raw failure","message_i18n":"读取设置失败","data":\(wrappedData)}
          """.utf8
        )
      )

      do {
        _ = try await service.fetchSettings()
        XCTFail("Expected an explicit failure response for data: \(wrappedData)")
      } catch {
        guard case APIError.serverMessage(let message) = error else {
          XCTFail("Expected serverMessage, got \(error)")
          continue
        }
        XCTAssertEqual(message, "读取设置失败")
      }
    }
  }

  func testFetchSettingsMergesLoggedInUserSettings() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "token"

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.RECOGNIZE_SOURCE, "douban")
    XCTAssertEqual(settings.USER_UNIQUE_ID, "compat-user")
    XCTAssertEqual(settings.AI_AGENT_ENABLE?.value, true)
    XCTAssertEqual(settings.SUBSCRIBE_SHARE_MANAGE?.value, true)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user"],
      in: paths
    )
  }

  func testFetchSettingsKeepsPublicSettingsWhenLoggedInUserSettingsFails() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsFailure(statusCode: 404)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "token"

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(settings.FRONTEND_VERSION, "v2.13.15")
    XCTAssertNil(settings.AI_AGENT_ENABLE)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user"],
      in: paths
    )
  }

  func testFetchSettingsKeepsSessionWhenUserSettingsForbiddenCannotProveTokenInvalid()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsFailure(statusCode: 403)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "token"
    service.currentUserForTesting = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_name: "limited-user",
      avatar: nil
    )
    setCredential(account: "username", value: "limited-user")
    setCredential(account: "password", value: "stale-password")

    let settings = try await service.fetchSettings()

    XCTAssertEqual(settings.BACKEND_VERSION, "v2.13.14")
    XCTAssertEqual(service.token, "token")
    XCTAssertEqual(service.currentUser?.user_name, "limited-user")
    XCTAssertNil(service.loginDraft)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user", "/api/v1/user/current"],
      in: paths
    )
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testPublicSystemConfigReadersUsePublicSettingEndpoints() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "token"
    service.currentUserForTesting = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["search": true],
      user_name: "search-user",
      avatar: nil
    )

    _ = try await service.fetchStorages()
    _ = try await service.fetchDirectories()
    _ = try await service.fetchIndexerSites()
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      [
        "/api/v1/system/setting/public/Storages",
        "/api/v1/system/setting/public/Directories",
        "/api/v1/system/setting/public/IndexerSites",
      ],
      in: paths
    )
  }

  func testSubscriptionActionsMatchBackendSuccessResponseContract() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(false)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let statusResult = try await service.updateSubscriptionStatus(id: 41, state: "S")
    let searchSucceeded = try await service.searchSubscription(id: 41)
    let resetResult = try await service.resetSubscription(id: 41)
    XCTAssertTrue(statusResult.success)
    XCTAssertNil(statusResult.message)
    XCTAssertTrue(searchSucceeded)
    XCTAssertTrue(resetResult.success)
    XCTAssertNil(resetResult.message)

    let methods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let queries = await CompatibilityEndpointURLProtocol.stub.requestQueries()
    let actionIndexes = paths.indices.filter { paths[$0].hasPrefix("/api/v1/subscribe/") }
    XCTAssertEqual(actionIndexes.map { methods[$0] }, ["PUT", "POST", "POST"])
    XCTAssertEqual(
      actionIndexes.map { paths[$0] },
      [
        "/api/v1/subscribe/status/41",
        "/api/v1/subscribe/search/41",
        "/api/v1/subscribe/reset/41",
      ]
    )
    XCTAssertEqual(actionIndexes.map { queries[$0] }, ["state=S", nil, nil])
  }

  func testSubscriptionActionsMatchBackendFailureResponseContract() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(true)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let statusResult = try await service.updateSubscriptionStatus(id: 41, state: "S")
    let searchSucceeded = try await service.searchSubscription(id: 41)
    let resetResult = try await service.resetSubscription(id: 41)
    XCTAssertFalse(statusResult.success)
    XCTAssertEqual(statusResult.message, "订阅不存在")
    XCTAssertFalse(searchSucceeded)
    XCTAssertFalse(resetResult.success)
    XCTAssertEqual(resetResult.message, "订阅不存在")
  }

  func testMediaDetailLibraryEndpointMatchesWebContract() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    // 这个用例钉住 v3 的 `success` 语义；未解析版本的 v2 兜底另有用例。
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.9")

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from:
        #"{"tmdb_id":42,"title":"电影","year":"2026","type":"电影"}"#
        .data(using: .utf8)!
    )

    let exists = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertNotNil(exists)

    let capturedExistsQuery =
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/mediaserver/exists")
    let existsQuery = try XCTUnwrap(capturedExistsQuery)
    XCTAssertEqual(
      Set(existsQuery.split(separator: "&").map(String.init)),
      Set([
        "media_source=themoviedb",
        "media_id=42",
        "title=%E7%94%B5%E5%BD%B1",
        "year=2026",
        "mtype=%E7%94%B5%E5%BD%B1",
      ])
    )
  }

  func testSubscriptionLookupMatchesV304CrossSourceMetadataContract() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionLookupResponse(
      #"{"id":701,"media_source":"themoviedb","media_id":"42"}"#.data(using: .utf8)!)
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from:
        #"{"media_source":"douban","media_id":"34943510","title":"跨来源电影","year":"2026","type":"电影"}"#
        .data(using: .utf8)!
    )

    let lookup = try await service.fetchSubscriptionLookup(media: media)
    XCTAssertEqual(lookup?.id, 701)

    _ = try await service.fetchSubscriptionLookup(
      media: media,
      includeVideoMetadataFallback: false
    )

    let queries = await CompatibilityEndpointURLProtocol.stub.matchingQueries(
      suffix: "/subscribe/media/34943510")
    XCTAssertEqual(queries.count, 2)
    XCTAssertEqual(
      Self.queryValues(queries[0]),
      [
        "media_source": "douban",
        "title": "跨来源电影",
        "year": "2026",
        "mtype": "电影",
      ]
    )
    XCTAssertEqual(
      Self.queryValues(queries[1]),
      [
        "media_source": "douban",
        "title": "跨来源电影",
      ]
    )
  }

  func testMediaDetailLibraryEndpointTreatsEmptyItemAsNotInLibrary() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    // 这个用例钉住 v3 的 `success` 语义；未解析版本的 v2 兜底另有用例。
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.9")

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from:
        #"{"tmdb_id":42,"title":"电影","year":"2026","type":"电影"}"#
        .data(using: .utf8)!
    )

    // v3.0.1 起 `success` 恒为 true，未入库时只有 `data.item` 为空对象。
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":true,"data":{"item":{}}}"#.data(using: .utf8)!)
    let missing = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertNil(missing, "v3 的 success=true + 空 item 必须判为未入库")

    // 命中时 `data.item.id` 非空。
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":true,"data":{"item":{"id":"library/42"}}}"#.data(using: .utf8)!)
    let itemRef = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertEqual(itemRef, MediaServerItemRef(itemID: "library/42", server: nil), "播放入口需要原样拿到条目 ID")

    // v3.2.6 起同一条记录还带条目所属服务器的配置名称；空白名称按没有处理。
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":true,"data":{"item":{"id":"7","server":"家里的 Emby"}}}"#.data(using: .utf8)!)
    let withServer = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertEqual(withServer, MediaServerItemRef(itemID: "7", server: "家里的 Emby"))
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":true,"data":{"item":{"id":"7","server":"  "}}}"#.data(using: .utf8)!)
    let blankServer = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertEqual(blankServer, MediaServerItemRef(itemID: "7", server: nil))

    // 已解析的 v3 把 `success:false` 当失败 envelope，严格解包必须抛错；
    // 未解析版本对实际 v2 的兜底见 `testUnresolvedMediaServerExistsTreatsV2SuccessFalseAsMissing`。
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":false,"data":{"item":{}}}"#.data(using: .utf8)!)
    do {
      _ = try await service.fetchMediaServerItemRef(media: media)
      XCTFail("success:false 必须按失败 envelope 抛错")
    } catch let error as APIError {
      guard case .serverMessage = error else {
        return XCTFail("应当是后端 envelope 报错，实际 \(error)")
      }
    } catch {
      XCTFail("应当是 APIError，实际 \(error)")
    }
  }

  func testAniListDetailAuxiliaryEndpointsMatchWebContract() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let media = MediaInfo(
      anilist_id: 154_587,
      source: "anilist",
      title: "葬送的芙莉莲",
      type: "电视剧"
    )

    let actors = try await service.fetchMediaActors(detail: media, page: 1)
    let recommendations = try await service.fetchMediaRecommendations(detail: media, page: 1)

    XCTAssertEqual(actors.first?.source, "anilist")
    XCTAssertEqual(actors.first?.raw_id, "95097")
    XCTAssertEqual(
      recommendations.first?.identity,
      MediaIdentity(source: "anilist", mediaId: "20954")
    )
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(
      paths,
      [
        "/api/v1/anilist/credits/154587",
        "/api/v1/anilist/recommend/154587",
      ]
    )
  }

  func testManualMediaSearchMatchesWebSelectorContractAndKeepsAniListNativeID()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let items = try await service.searchManualMedia(
      title: "葬送的芙莉莲",
      source: .anilist
    )

    let item = try XCTUnwrap(items.first)
    XCTAssertEqual(item.source, "anilist")
    XCTAssertEqual(ManualMediaSelection.mediaId(for: item, source: .anilist), "154587")
    let query = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/media/search")
    )
    XCTAssertEqual(
      query,
      [
        "title": "葬送的芙莉莲",
        "page": "1",
        "count": "20",
        "media_source": "anilist",
      ]
    )
    XCTAssertNil(query["type"])
  }

  func testTMDBRecognitionPinsSearchAndFallbackToTMDBSource() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "搜索未命中",
      data: Data("[]".utf8)
    )
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let tmdbID = try await service.recognizeTmdbId(
      title: "搜索未命中",
      year: "2026",
      type: "电视剧"
    )

    XCTAssertEqual(tmdbID, 209_867)
    let searchQuery = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/media/search")
    )
    XCTAssertEqual(searchQuery["media_source"], "themoviedb")
    let recognizeQuery = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/media/recognize")
    )
    XCTAssertEqual(recognizeQuery["media_source"], "themoviedb")
    XCTAssertEqual(recognizeQuery["title"], "搜索未命中 2026")
  }

  func testManualMediaSearchOlderSuccessCannotRestoreResultsAfterEmptySearch() async {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let oldGate = CompatibilityEndpointAsyncGate()
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "旧搜索",
      data: Data(#"[{"tmdb_id":100,"title":"旧结果","type":"电影"}]"#.utf8),
      waitFor: oldGate
    )
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let viewModel = ManualMediaSearchViewModel(source: .themoviedb, apiService: service)
    viewModel.keyword = "旧搜索"
    let oldSearch = Task { @MainActor in await viewModel.search() }
    await oldGate.waitForWaiter()

    viewModel.keyword = "  "
    await viewModel.search()
    await oldGate.open()
    await oldSearch.value

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
  }

  /// 搜索失败不能看起来像「没有结果」：失败、没结果、有结果分别给出不同状态；关闭后回到初始状态。
  func testManualMediaSearchReportsFailureAndNoResultsSeparately() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "失败搜索", statusCode: 500, data: Data(#"{"message":"failed"}"#.utf8), waitFor: nil)
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "没有的片", data: Data("[]".utf8), waitFor: nil)
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "有的片", data: Data(#"[{"tmdb_id":300,"title":"有的片","type":"电影"}]"#.utf8),
      waitFor: nil)
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let viewModel = ManualMediaSearchViewModel(source: .themoviedb, apiService: service)
    XCTAssertEqual(viewModel.outcome, .idle)

    viewModel.keyword = "失败搜索"
    await viewModel.search()
    XCTAssertEqual(viewModel.outcome, .failed)
    XCTAssertTrue(viewModel.items.isEmpty)

    viewModel.keyword = " 没有的片 "
    await viewModel.search()
    XCTAssertEqual(viewModel.outcome, .noResults(keyword: "没有的片"))

    viewModel.keyword = "有的片"
    await viewModel.search()
    XCTAssertEqual(viewModel.outcome, .idle)
    XCTAssertEqual(viewModel.items.map(\.title), ["有的片"])

    viewModel.keyword = "失败搜索"
    await viewModel.search()
    XCTAssertEqual(viewModel.outcome, .failed)
    viewModel.presentationDidDisappear(retention: .milliseconds(1))
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(viewModel.outcome, .idle)
  }

  func testManualMediaSearchOlderFailureCannotStopNewerLoading() async {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let oldGate = CompatibilityEndpointAsyncGate()
    let newGate = CompatibilityEndpointAsyncGate()
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "失败搜索",
      statusCode: 500,
      data: Data(#"{"message":"old failed"}"#.utf8),
      waitFor: oldGate
    )
    await CompatibilityEndpointURLProtocol.stub.setManualMediaResponse(
      title: "新搜索",
      data: Data(#"[{"tmdb_id":200,"title":"新结果","type":"电影"}]"#.utf8),
      waitFor: newGate
    )
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let viewModel = ManualMediaSearchViewModel(source: .themoviedb, apiService: service)
    viewModel.keyword = "失败搜索"
    let oldSearch = Task { @MainActor in await viewModel.search() }
    await oldGate.waitForWaiter()

    viewModel.keyword = "新搜索"
    let newSearch = Task { @MainActor in await viewModel.search() }
    await newGate.waitForWaiter()

    await oldGate.open()
    await oldSearch.value
    XCTAssertTrue(viewModel.isLoading)
    XCTAssertTrue(viewModel.items.isEmpty)

    await newGate.open()
    await newSearch.value
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertEqual(viewModel.items.map(\.title), ["新结果"])
  }

  func testSubscribeNavigationMediaInfoUsesCanonicalMediaDetailRequestID() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let media = Subscribe(
      name: "Canonical",
      type: "电影",
      tmdbid: 42,
      anilistid: 154_587,
      media_source: "custom",
      media_id: "native-9",
      mediaid: "legacy:7"
    ).navigationMediaInfo()

    _ = try await service.fetchMediaDetail(media: media)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0.hasPrefix("/api/v1/media/") }, [
      "/api/v1/media/native-9"
    ])
    let query = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/media/native-9")
    )
    XCTAssertEqual(query["media_source"], "custom")
    XCTAssertEqual(query["type_name"], "电影")
  }

  func testLookupSendsWebMetadataFallbackRegardlessOfBackendVersion() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    let media = MediaInfo(tmdb_id: 42, title: "缺年份电影", type: "电影")
    for version in ["v3.0.4", "v3.0.7", "v3.0.10-1", "v3.1.0", "v9.0.0"] {
      service.settings = GlobalSettings(BACKEND_VERSION: version)
      _ = try await service.fetchSubscriptionLookup(media: media)
    }
    let queries = await CompatibilityEndpointURLProtocol.stub.matchingQueries(suffix: "/subscribe/media/42")
    XCTAssertEqual(queries.count, 5)
    for query in queries {
      let values = Self.queryValues(query)
      XCTAssertEqual(values["media_source"], "themoviedb")
      XCTAssertEqual(values["title"], "缺年份电影")
      XCTAssertEqual(values["mtype"], "电影")
      XCTAssertNil(values["year"])
    }
  }

  func testHandlerStopsKnownForkBugBeforeSendingRequest() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    configureForkUser(service)
    let shares = try await service.fetchSubscriptionShares(path: "/subscribe/shares")
    let share = try XCTUnwrap(shares.first)
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.0.4")
    let handler = SubscriptionHandler(apiService: service)
    XCTAssertFalse(handler.forkCapability.isAvailable)
    let result = await handler.fork(share: share)
    XCTAssertNil(result)
    XCTAssertEqual(handler.forkErrorMessage, handler.forkCapability.unavailableReason)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/subscribe/fork"))
    XCTAssertFalse(paths.contains("/api/v1/system/global"))

    service.settings = GlobalSettings(BACKEND_VERSION: "v3.0.5")
    XCTAssertTrue(handler.forkCapability.isAvailable)
    let allowed = await handler.fork(share: share)
    XCTAssertEqual(allowed, 901)
  }

  func testCentralForkCapabilityKeepsAffectedRangeExactAndUnknownAllowed() {
    for version in ["v3.0.1", "v3.0.3", "v3.0.4", "3.0.4-1"] {
      XCTAssertFalse(
        BackendCapabilities.capability(for: .forkSubscription, backendVersion: version).isAvailable)
    }
    for version in [nil, "", "v3.0.0", "v3.0.5", "v3.1.0", "v3.0.4-beta", "v2.15.6", "v9.0.0"] {
      XCTAssertTrue(
        BackendCapabilities.capability(for: .forkSubscription, backendVersion: version).isAvailable)
    }
  }

  func testUnknownVersionForkDoesNotRefreshOrOverwriteSharedSettings() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    configureForkUser(service)
    let shares = try await service.fetchSubscriptionShares(path: "/subscribe/shares")
    let share = try XCTUnwrap(shares.first)
    for version in [nil, "v3.0.4-beta"] {
      service.settings = GlobalSettings(BACKEND_VERSION: version)
      let handler = SubscriptionHandler(apiService: service)
      let result = await handler.fork(share: share)
      XCTAssertEqual(result, 901)
      XCTAssertEqual(service.settings?.BACKEND_VERSION, version)
    }
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0.hasSuffix("/subscribe/fork") }.count, 2)
    XCTAssertFalse(paths.contains("/api/v1/system/global"))
    XCTAssertFalse(paths.contains("/api/v1/system/global/user"))
  }

  func testSaveSubscriptionSendsOnlyWritableFields() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    await CompatibilityEndpointURLProtocol.stub.reset()
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.1.0")
    var subscribe = try JSONDecoder().decode(
      Subscribe.self,
      from: Data(
        #"{"id":44,"name":"原订阅","type":"电视剧","media_source":"themoviedb","media_id":"42","media_category_id":"tv-drama","media_category":"剧集","search_interval":24,"quality":"原规则","state":"R","username":"owner","episode_priority":{"1":100}}"#
          .utf8))
    let original = subscribe
    subscribe.quality = nil
    let result = try await service.saveSubscription(original: original, draft: subscribe)
    XCTAssertTrue(result.success)
    let body = try Self.jsonObject(await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/subscribe"))
    XCTAssertEqual(body["id"] as? Int, 44)
    XCTAssertNil(body["media_category_id"])
    XCTAssertNil(body["media_category"])
    XCTAssertNil(body["search_interval"])
    XCTAssertTrue(body["quality"] is NSNull)
    XCTAssertNil(body["state"])
    XCTAssertNil(body["username"])
    XCTAssertNil(body["episode_priority"])
  }

  func testSubscribeSheetSavePreservesUnchangedCategoryAndAppliesPathEdits() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "category-test-token"
    service.currentUserForTesting = Token(
      access_token: "category-test-token", token_type: "bearer",
      super_user: FlexibleBool(false), permissions: ["subscribe": true],
      user_id: 42, user_name: "category-test", avatar: nil)
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.1.0")

    let cases: [(response: String, edit: String?, expectedID: String?, expectedPath: String?)] = [
      (#"{"id":44,"name":"有编号","type":"电视剧","media_category_id":"tv-drama","media_category":"原分类"}"#,
       nil, "tv-drama", "原分类"),
      (#"{"id":44,"name":"有编号","type":"电视剧","media_category_id":"tv-drama","media_category":"原分类"}"#,
       "新分类", nil, "新分类"),
      (#"{"id":44,"name":"有编号","type":"电视剧","media_category_id":"tv-drama","media_category":"原分类"}"#,
       "", nil, nil),
      (#"{"id":44,"name":"旧订阅","type":"电视剧","media_category_id":null,"media_category":"原分类"}"#,
       nil, nil, "原分类"),
      (#"{"id":44,"name":"旧订阅","type":"电视剧","media_category_id":null,"media_category":"原分类"}"#,
       "新分类", nil, "新分类"),
      (#"{"id":44,"name":"旧订阅","type":"电视剧","media_category_id":null,"media_category":"原分类"}"#,
       "", nil, nil),
    ]
    for (index, testCase) in cases.enumerated() {
      await CompatibilityEndpointURLProtocol.stub.reset()
      await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(false)
      let original = try JSONDecoder().decode(Subscribe.self, from: Data(testCase.response.utf8))
      let model = SubscribeSheetViewModel(subscribe: original, apiService: service)
      if let edit = testCase.edit { model.mediaCategoryText = edit }

      let saved = await model.save()
      XCTAssertTrue(saved, "case \(index)")
      let body = try Self.jsonObject(
        await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/subscribe"))
      if testCase.edit == nil {
        XCTAssertEqual(Set(body.keys), ["id"], "case \(index)：未编辑类别不重复提交")
        XCTAssertEqual(model.subscribe.media_category_id, testCase.expectedID)
        XCTAssertEqual(model.subscribe.media_category, testCase.expectedPath)
        continue
      }
      if let expectedID = testCase.expectedID {
        XCTAssertEqual(body["media_category_id"] as? String, expectedID, "case \(index)")
      } else {
        XCTAssertFalse(body.keys.contains("media_category_id"), "case \(index)：仅路径写入不能发旧或空编号")
      }
      if let expectedPath = testCase.expectedPath {
        XCTAssertEqual(body["media_category"] as? String, expectedPath, "case \(index)")
      } else {
        XCTAssertTrue(body["media_category"] is NSNull, "case \(index)")
      }
    }
  }

  func testSubscriptionShareGETThenForkPreservesCurrentIdentitySchema() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let shares = try await service.fetchSubscriptionShares(path: "/subscribe/shares")
    let share = try XCTUnwrap(shares.first)
    let stableId = share.id

    XCTAssertEqual(share.raw_id, 88)
    XCTAssertEqual(share.bangumiid, 404_804)
    XCTAssertEqual(share.anilistid, 154_587)
    XCTAssertEqual(share.media_source, "anilist")
    XCTAssertEqual(share.media_id, "154587")
    XCTAssertEqual(share.toMediaInfo().apiMediaId, "anilist:154587")

    service.settings = GlobalSettings(BACKEND_VERSION: "v3.0.10-1")
    let subscriptionId = try await service.forkSubscription(share: share)

    XCTAssertEqual(subscriptionId, 901)
    XCTAssertEqual(share.id, stableId)
    let body = try Self.jsonObject(
      await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/subscribe/fork")
    )
    XCTAssertEqual(body["id"] as? Int, 88)
    XCTAssertEqual(body["bangumiid"] as? Int, 404_804)
    XCTAssertEqual(body["anilistid"] as? Int, 154_587)
    XCTAssertEqual(body["media_source"] as? String, "anilist")
    XCTAssertEqual(body["media_id"] as? String, "154587")
  }

  func testManualTransferPreviewUsesBackgroundFalseAndPreservesAniListIdentity() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let form = ReorganizeForm(
      fileitem: FileItem(
        name: "episode.mkv",
        path: "/downloads/episode.mkv",
        type: "file",
        size: 1
      ),
      logid: 0,
      target_storage: "local",
      transfer_type: "copy",
      target_path: "/library",
      min_filesize: 0,
      scrape: true,
      from_history: false,
      type_name: "电视剧",
      anilistid: 154_587,
      media_source: "anilist",
      media_id: "154587",
      season: 1
    )

    let preview = try await service.previewManualTransfer(form: form)
    XCTAssertEqual(preview.summary, ManualTransferPreviewSummary(total: 1, success: 1, failed: 0))
    XCTAssertEqual(preview.items.first?.target, "/library/Show/S01E01.mkv")
    XCTAssertEqual(preview.message, "本地化预览完成")

    let previewQuery = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/transfer/manual")
    )
    let body = try Self.jsonObject(
      await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/transfer/manual")
    )
    XCTAssertEqual(previewQuery, ["background": "false"])
    XCTAssertEqual(body["preview"] as? Bool, true)
    XCTAssertEqual(body["media_source"] as? String, "anilist")
    XCTAssertEqual(body["media_id"] as? String, "154587")

    let queued = try await service.manualTransfer(form: form, background: true)
    let submittedImmediately = try await service.manualTransfer(form: form, background: false)
    XCTAssertTrue(queued.success)
    XCTAssertTrue(submittedImmediately.success)
    let queries =
      await CompatibilityEndpointURLProtocol.stub.matchingQueries(suffix: "/transfer/manual")
        .map(Self.queryValues)
    XCTAssertEqual(
      queries,
      [["background": "false"], ["background": "true"], ["background": "false"]]
    )
    let bodies =
      await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/transfer/manual")
    let submitBody = try Self.jsonObject(XCTUnwrap(bodies.dropFirst().first.flatMap { $0 }))
    XCTAssertFalse(submitBody.keys.contains("preview"))

    await CompatibilityEndpointURLProtocol.stub.setManualTransferOmitsSuccess(true)
    do {
      _ = try await service.previewManualTransfer(form: form)
      XCTFail("整理预览响应缺少 success 时必须按 Web 契约判定失败")
    } catch {}

    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true}"#.utf8),
      Data(#"{"success":true,"data":null}"#.utf8),
      Data(
        #"{"success":true,"data":{"summary":{"total":1,"success":1,"failed":0},"items":[{"source":"/downloads/episode.mkv","target":"/library/Show/S01E01.mkv"}]}}"#.utf8
      ),
    ])
    for diagnostic in ["缺少 data", "data 为 null", "条目缺少 success"] {
      do {
        _ = try await service.previewManualTransfer(form: form)
        XCTFail("整理预览响应\(diagnostic)时必须失败")
      } catch {}
    }
  }

  func testAddDownloadPreservesSiteTransportFieldsAcrossBothProductionEndpoints() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"

    let context = try JSONDecoder().decode(
      Context.self,
      from: Data(
        #"""
        {
          "media_info": {"tmdb_id": 42, "title": "测试媒体", "type": "电影"},
          "torrent_info": {
            "site": 1,
            "site_name": "测试站点",
            "site_cookie": "session=search-result",
            "site_ua": "MoviePilot-Site-UA",
            "site_proxy": true,
            "site_order": 1,
            "site_downloader": "site-downloader",
            "title": "测试资源",
            "enclosure": "https://example.test/resource.torrent",
            "size": 1024,
            "uploadvolumefactor": 1.0,
            "downloadvolumefactor": 0.0
          }
        }
        """#.utf8
      )
    )
    let torrent = try XCTUnwrap(context.torrent_info)
    let media = try XCTUnwrap(context.media_info)

    let withoutMedia = AddDownloadRequest(
      torrent_in: torrent,
      downloader: nil,
      save_path: nil,
      media_in: nil,
      tmdbid: nil,
      doubanid: nil,
      bangumiid: nil,
      anilistid: nil,
      media_source: nil,
      media_id: nil
    )
    let withMedia = AddDownloadRequest(
      torrent_in: torrent,
      downloader: "manual-downloader",
      save_path: nil,
      media_in: media,
      tmdbid: nil,
      doubanid: nil,
      bangumiid: nil,
      anilistid: nil,
      media_source: nil,
      media_id: nil
    )

    let withoutMediaResult = try await service.addDownload(payload: withoutMedia)
    let withMediaResult = try await service.addDownload(payload: withMedia)
    XCTAssertTrue(withoutMediaResult.success)
    XCTAssertTrue(withMediaResult.success)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let downloadPaths = paths.filter {
      $0 == "/api/v1/download/add" ||
        $0 == "/api/v1/download" ||
        $0 == "/api/v1/download/"
    }
    XCTAssertEqual(downloadPaths.first, "/api/v1/download/add")
    XCTAssertTrue(["/api/v1/download", "/api/v1/download/"].contains(downloadPaths.last ?? ""))
    XCTAssertEqual(downloadPaths.count, 2)
    let withoutMediaBodies =
      await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/download/add")
    let withMediaBodies =
      await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/download")
    let bodies = withoutMediaBodies + withMediaBodies
    XCTAssertEqual(bodies.count, 2)

    for bodyData in bodies {
      let body = try Self.jsonObject(bodyData)
      let torrentBody = try XCTUnwrap(body["torrent_in"] as? [String: Any])
      XCTAssertEqual(torrentBody["site_cookie"] as? String, "session=search-result")
      XCTAssertEqual(torrentBody["site_ua"] as? String, "MoviePilot-Site-UA")
      XCTAssertEqual(torrentBody["site_proxy"] as? Bool, true)
      XCTAssertEqual(torrentBody["site_downloader"] as? String, "site-downloader")
    }

    let withoutMediaBody = try Self.jsonObject(bodies[0])
    let withMediaBody = try Self.jsonObject(bodies[1])
    XCTAssertNil(withoutMediaBody["downloader"])
    XCTAssertEqual(withMediaBody["downloader"] as? String, "manual-downloader")
    XCTAssertNotEqual(
      withMediaBody["downloader"] as? String,
      (withMediaBody["torrent_in"] as? [String: Any])?["site_downloader"] as? String
    )
  }

  func testReorganizePreviewMergesHistoryResponsesAndDeduplicatesItems() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(
        """
        {
          "success": true,
          "message_i18n": "第一批预览完成",
          "data": {
            "summary": {"total": 2, "success": 2, "failed": 0},
            "items": [
              {"source": "/downloads/a.mkv", "target": "/library/a.mkv", "success": true},
              {"source": "/downloads/a.mkv", "target": "/library/a.mkv", "success": true}
            ]
          }
        }
        """.utf8
      ),
      Data(#"{"success":false,"message_i18n":"第二批预览失败"}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let previewOutcome = await viewModel.preview()
    XCTAssertEqual(previewOutcome, .generated(allSucceeded: false))

    let preview = try XCTUnwrap(viewModel.previewData)
    XCTAssertEqual(preview.summary, ManualTransferPreviewSummary(total: 2, success: 1, failed: 1))
    XCTAssertEqual(preview.items.map(\.source), ["/downloads/a.mkv", "历史记录 82"])
    XCTAssertEqual(preview.items.last?.message, "第二批预览失败")
    XCTAssertEqual(viewModel.errorMessage, "预览完成，其中 1 项无法整理。")

    let queries =
      await CompatibilityEndpointURLProtocol.stub.matchingQueries(suffix: "/transfer/manual")
        .map(Self.queryValues)
    XCTAssertEqual(queries, [["background": "false"], ["background": "false"]])
    let bodies =
      await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/transfer/manual")
    let previewLogIds = try bodies.map {
      try XCTUnwrap(Self.jsonObject($0)["logid"] as? Int)
    }
    XCTAssertEqual(previewLogIds, [81, 82])
    let allPreviewBodies = try bodies.allSatisfy {
      let body = try Self.jsonObject($0)
      return body["preview"] as? Bool == true
        && !body.keys.contains("media_source")
        && !body.keys.contains("media_id")
    }
    XCTAssertTrue(allPreviewBodies)
  }

  func testReorganizeSubmitUsesBackgroundRequestsForEveryHistory() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true,"message_i18n":"已开始整理"}"#.utf8),
      Data(#"{"success":true,"message_i18n":"已开始整理"}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)
    XCTAssertTrue(submitted)

    let queries =
      await CompatibilityEndpointURLProtocol.stub.matchingQueries(suffix: "/transfer/manual")
        .map(Self.queryValues)
    XCTAssertEqual(queries, [["background": "true"], ["background": "true"]])
    let bodies =
      await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/transfer/manual")
    let submittedLogIds = try bodies.map {
      try XCTUnwrap(Self.jsonObject($0)["logid"] as? Int)
    }
    XCTAssertEqual(submittedLogIds, [81, 82])
    let allBodiesOmitPreview = try bodies.allSatisfy {
      try !Self.jsonObject($0).keys.contains("preview")
    }
    XCTAssertTrue(allBodiesOmitPreview)
  }

  func testMusicTransferSupportsHistoryReuseAndFileRecognitionModesLocally() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true,"message_i18n":"历史音乐整理已开始"}"#.utf8),
      Data(#"{"success":true,"message_i18n":"文件音乐识别已开始"}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)

    let historyReuse = ReorganizeForm(
      fileitem: nil,
      logid: 901,
      target_storage: "local",
      transfer_type: "copy",
      target_path: "/music",
      min_filesize: 0,
      scrape: false,
      from_history: true,
      type_name: "音乐"
    )
    let fileRecognition = ReorganizeForm(
      fileitem: FileItem(
        name: "track.mp3",
        path: "/downloads/music/track.mp3",
        type: "file",
        size: 1
      ),
      logid: 902,
      target_storage: "local",
      transfer_type: "copy",
      target_path: "/music",
      min_filesize: 0,
      scrape: true,
      from_history: false,
      type_name: "音乐"
    )

    let historyResult = try await service.manualTransfer(form: historyReuse, background: true)
    let fileResult = try await service.manualTransfer(form: fileRecognition, background: true)
    XCTAssertTrue(historyResult.success)
    XCTAssertTrue(fileResult.success)

    let queries =
      await CompatibilityEndpointURLProtocol.stub.matchingQueries(suffix: "/transfer/manual")
        .map(Self.queryValues)
    XCTAssertEqual(queries, [["background": "true"], ["background": "true"]])

    let bodies = await CompatibilityEndpointURLProtocol.stub.matchingBodies(suffix: "/transfer/manual")
    XCTAssertEqual(bodies.count, 2)
    let encodedBodies = try bodies.map(Self.jsonObject)

    XCTAssertEqual(encodedBodies[0]["logid"] as? Int, 901)
    XCTAssertEqual(encodedBodies[0]["type_name"] as? String, "音乐")
    XCTAssertEqual(encodedBodies[0]["from_history"] as? Bool, true)
    XCTAssertNil(encodedBodies[0]["fileitem"])
    XCTAssertNil(encodedBodies[0]["media_source"])
    XCTAssertNil(encodedBodies[0]["media_id"])

    XCTAssertEqual(encodedBodies[1]["logid"] as? Int, 902)
    XCTAssertEqual(encodedBodies[1]["type_name"] as? String, "音乐")
    XCTAssertEqual(encodedBodies[1]["from_history"] as? Bool, false)
    XCTAssertEqual(
      (encodedBodies[1]["fileitem"] as? [String: Any])?["path"] as? String,
      "/downloads/music/track.mp3"
    )
    XCTAssertNil(encodedBodies[1]["media_source"])
    XCTAssertNil(encodedBodies[1]["media_id"])
  }

  func testReorganizeSubmitStopsBeforeFirstMutationWhenHistoryValidationRejects() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)

    var validationCount = 0
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      validateBeforeSubmit: {
        validationCount += 1
        return "服务器记录有未知变化，请重试。"
      },
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)

    XCTAssertFalse(submitted)
    XCTAssertEqual(validationCount, 1)
    XCTAssertEqual(
      viewModel.mutationRetryMessage,
      "服务器记录有未知变化，请重试。"
    )
    let bodies = await CompatibilityEndpointURLProtocol.stub.matchingBodies(
      suffix: "/transfer/manual"
    )
    XCTAssertTrue(bodies.isEmpty)
  }

  func testReorganizeSubmitReportsPartialAcceptanceMessage() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true,"message_i18n":"已开始整理"}"#.utf8),
      Data(#"{"success":false}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)

    XCTAssertFalse(submitted)
    // 部分受理时明确报告“已提交整理”，不再误导为“没有开始”。
    XCTAssertEqual(viewModel.errorMessage, "部分文件已提交整理，其余失败，请重试。")
  }

  func testReorganizeSubmitPartialAcceptanceKeepsBackendFailureReason() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true,"message_i18n":"已开始整理"}"#.utf8),
      Data(#"{"success":false,"message_i18n":"目标目录不可用"}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)

    XCTAssertFalse(submitted)
    // 部分受理 + 后端错误信息时，先报部分成功，再附后端原因。
    XCTAssertEqual(
      viewModel.errorMessage,
      "部分文件已提交整理，其余失败，请重试。失败原因：目标目录不可用"
    )
  }

  func testReorganizeSubmitAllFailedDoesNotClaimPartialAcceptance() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":false}"#.utf8),
      Data(#"{"success":false}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)

    XCTAssertFalse(submitted)
    // 全部失败时不得使用“部分已提交”措辞。
    XCTAssertEqual(viewModel.errorMessage, "整理没有开始，请检查设置后重试。")
  }

  func testApiResponseLocalizedMessageTrimsThenFallsBack() {
    // message_i18n 全空白时不得遮蔽有效 message。
    let blankI18n = ApiResponse<String>(
      success: false,
      data: nil,
      message: "真实原因",
      message_i18n: "   "
    )
    XCTAssertEqual(blankI18n.localizedMessage, "真实原因")

    let validI18n = ApiResponse<String>(
      success: false,
      data: nil,
      message: "raw",
      message_i18n: "读取失败"
    )
    XCTAssertEqual(validI18n.localizedMessage, "读取失败")

    let blankOnly = ApiResponse<String>(
      success: false,
      data: nil,
      message: nil,
      message_i18n: " \n "
    )
    XCTAssertNil(blankOnly.localizedMessage)
  }

  func testServerMessageErrorIgnoresBlankPreferredField() {
    let error = APIService.serverMessageError(
      statusCode: 422,
      data: Data(#"{"message_i18n":"   ","detail":"目标目录不可用"}"#.utf8)
    )
    guard case APIError.serverMessage(let message) = error else {
      return XCTFail("Expected serverMessage, got \(error)")
    }
    XCTAssertEqual(message, "422: 目标目录不可用")
  }

  func testGatewayStatusesStayDistinctFromFinishedServerMessages() {
    for status in [400, 422, 500] {
      let error = APIService.serverMessageError(
        statusCode: status,
        data: Data(#"{"detail":"业务拒绝"}"#.utf8)
      )
      guard case APIError.serverMessage(let message) = error else {
        return XCTFail("HTTP \(status) 仍是源站给出的结果，得到 \(error)")
      }
      XCTAssertEqual(message, "\(status): 业务拒绝")
    }
    for status in [502, 503, 504] {
      let error = APIService.serverMessageError(
        statusCode: status,
        data: Data(#"{"detail":"Gateway Timeout"}"#.utf8)
      )
      guard case APIError.gatewayStatus(let code, let message) = error else {
        return XCTFail("HTTP \(status) 不是业务终态，得到 \(error)")
      }
      XCTAssertEqual(code, status)
      XCTAssertEqual(message, "\(status): Gateway Timeout")
      XCTAssertEqual(error.localizedDescription, "\(status): Gateway Timeout")
    }
  }

  func testReorganizeSubmitFallsBackToMessageWhenMessageI18nIsBlank() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setManualTransferResponses([
      Data(#"{"success":true,"message_i18n":"已开始整理"}"#.utf8),
      Data(#"{"success":false,"message_i18n":"   ","message":"目标目录不可用"}"#.utf8),
    ])

    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    configureManageUser(service)
    let viewModel = ReorganizeViewModel(
      logIds: [81, 82],
      fileItem: nil,
      apiService: service
    )

    let submitted = await viewModel.submit(background: true)

    XCTAssertFalse(submitted)
    // 空白 message_i18n 不得遮蔽有效 message。
    XCTAssertEqual(
      viewModel.errorMessage,
      "部分文件已提交整理，其余失败，请重试。失败原因：目标目录不可用"
    )
  }

  private func assertContainsSubsequence(
    _ expected: [String],
    in actual: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var remaining = ArraySlice(expected)
    for path in actual where path == remaining.first {
      remaining.removeFirst()
      if remaining.isEmpty { return }
    }

    XCTFail(
      "Expected request paths to contain ordered subsequence \(expected), got \(actual)",
      file: file,
      line: line
    )
  }

  private func clearCredential(account: String) {
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    UserDefaults.standard.removeObject(forKey: account)
  }

  private func setCredential(account: String, value: String) {
    if !KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: account) {
      UserDefaults.standard.set(value, forKey: account)
    }
  }

  private func configureForkUser(_ service: APIService) {
    service.tokenForTesting = "fork-user-token"
    service.currentUserForTesting = Token(
      access_token: "fork-user-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["subscribe": true],
      user_id: 42,
      user_name: "fork-user",
      avatar: nil
    )
  }

  private func configureManageUser(_ service: APIService) {
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "manage-user"
    service.currentUserForTesting = Token(
      access_token: "manage-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "manage-user",
      avatar: nil
    )
  }

  private static func jsonObject(_ data: Data?) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any]
    )
  }

  private static func queryValues(_ query: String?) -> [String: String] {
    guard let query,
      let components = URLComponents(string: "https://query.local/?\(query)")
    else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
  }

  func testLegacyBackendSubscriptionUpdateSendsFullSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = GlobalSettings(BACKEND_VERSION: "v2.15.6")

    let original = try JSONDecoder().decode(
      Subscribe.self,
      from:
        #"{"id":7,"name":"示例","type":"电视剧","sites":[1,2],"save_path":"/media/tv"}"#
        .data(using: .utf8)!)
    var draft = original
    draft.keyword = "新关键词"
    _ = try await service.saveSubscription(original: original, draft: draft)

    let captured = await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/subscribe")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(captured)) as? [String: Any])
    // v2 的 PUT 是整条替换，只改关键词也必须带上站点和保存路径，否则会被默认值覆盖。
    XCTAssertEqual(body["sites"] as? [Int], [1, 2])
    XCTAssertEqual(body["save_path"] as? String, "/media/tv")
    XCTAssertEqual(body["keyword"] as? String, "新关键词")
  }

  func testUnknownBackendVersionRejectsSubscriptionUpdate() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    // 版本号损坏时无法确认后端是 v2 还是 v3；全量替换和稀疏变更都可能改坏数据，必须拒绝。
    service.settings = GlobalSettings(BACKEND_VERSION: "未知版本")

    let original = try JSONDecoder().decode(
      Subscribe.self,
      from:
        #"{"id":7,"name":"示例","type":"电视剧","sites":[1,2],"save_path":"/media/tv"}"#
        .data(using: .utf8)!)
    var draft = original
    draft.keyword = "新关键词"
    do {
      _ = try await service.saveSubscription(original: original, draft: draft)
      XCTFail("Expected backendVersionUnavailable")
    } catch APIError.backendVersionUnavailable {
      // Expected.
    }
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasSuffix("/subscribe") })
  }

  func testColdStartWithoutLoadedSettingsRejectsSubscriptionUpdate() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    // 模拟 /system/global 失败或超时：版本读不到，不能猜协议写回旧草稿。
    service.settings = nil

    let original = try JSONDecoder().decode(
      Subscribe.self,
      from: #"{"id":9,"name":"冷启动","type":"电视剧","sites":[3],"save_path":"/media/show"}"#
        .data(using: .utf8)!)
    var draft = original
    draft.keyword = "新关键词"
    do {
      _ = try await service.saveSubscription(original: original, draft: draft)
      XCTFail("Expected backendVersionUnavailable")
    } catch APIError.backendVersionUnavailable {
      // Expected.
    }
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasSuffix("/subscribe") })
  }

  /// v2 收到 v3 形状 `DELETE /subscribe/media/42?media_source=...` 会按原值 `mediaid == "42"` 匹配旧订阅、
  /// 不按季号过滤，没删到也返回成功；版本未知时两个媒体级入口都必须不发请求。
  func testUnknownBackendVersionRejectsMediaSubscriptionDelete() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    for backendVersion in [nil, "未知版本"] as [String?] {
      await CompatibilityEndpointURLProtocol.stub.reset()
      let service = APIService.isolatedTestingInstance()
      let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
      defer { snapshot.restore(to: service) }

      service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
      service.tokenForTesting = "compat-token"
      service.settings = backendVersion.map { GlobalSettings(BACKEND_VERSION: $0) }

      do {
        _ = try await service.deleteSubscriptionResult(
          media: MediaInfo(tmdb_id: 42, type: "电视剧"), season: 2)
        XCTFail("Expected backendVersionUnavailable for \(backendVersion ?? "nil")")
      } catch APIError.backendVersionUnavailable {
        // Expected.
      }
      do {
        _ = try await service.deleteSubscriptionResult(mediaId: "tmdb:42", season: 2)
        XCTFail("Expected backendVersionUnavailable for \(backendVersion ?? "nil")")
      } catch APIError.backendVersionUnavailable {
        // Expected.
      }
      let methods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
      XCTAssertFalse(methods.contains("DELETE"), "\(backendVersion ?? "nil")")

      // 按订阅 ID 删除两个版本同形，版本未知时照常执行。
      let deletedByID = try await service.deleteSubscription(id: 7)
      XCTAssertTrue(deletedByID)
      let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
      let allMethods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
      let deletes = zip(paths, allMethods).filter { $0.1 == "DELETE" }.map(\.0)
      XCTAssertEqual(deletes, ["/api/v1/subscribe/7"], "\(backendVersion ?? "nil")")
    }
  }

  func testMediaSubscriptionDeleteUsesResolvedProtocolShapeWithSeason() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    let cases: [(version: String, path: String, query: String)] = [
      ("v2.15.6", "/api/v1/subscribe/media/tmdb:42", "season=2"),
      ("v3.2.9", "/api/v1/subscribe/media/42", "media_source=themoviedb&season=2"),
    ]
    for testCase in cases {
      await CompatibilityEndpointURLProtocol.stub.reset()
      let service = APIService.isolatedTestingInstance()
      let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
      defer { snapshot.restore(to: service) }

      service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
      service.tokenForTesting = "compat-token"
      service.settings = GlobalSettings(BACKEND_VERSION: testCase.version)

      let result = try await service.deleteSubscriptionResult(
        media: MediaInfo(tmdb_id: 42, type: "电视剧"), season: 2)
      XCTAssertTrue(result.success, testCase.version)

      let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
      let methods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
      let queries = await CompatibilityEndpointURLProtocol.stub.requestQueries()
      let deletes = paths.indices.filter { methods[$0] == "DELETE" }
      XCTAssertEqual(deletes.map { paths[$0] }, [testCase.path], testCase.version)
      let query = deletes.first.flatMap { queries[$0] }
      XCTAssertEqual(
        query?.split(separator: "&").map(String.init).sorted(),
        testCase.query.split(separator: "&").map(String.init).sorted(),
        testCase.version)
    }
  }

  func testBaseSettingsApplyBackendVersionBeforeUserSettingsFinish() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(false)
    await CompatibilityEndpointURLProtocol.stub.setPublicSettingsResponse(
      #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"v2.15.6","FRONTEND_VERSION":"v2.15.6"}}"#
        .data(using: .utf8)!)
    let userGate = CompatibilityEndpointAsyncGate()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsGate(userGate)

    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"

    let fetch = Task { try await service.fetchSettings() }
    await userGate.waitForWaiter()
    // /system/global/user 还没返回，settings 尚未发布；但基础响应里的版本已经生效。
    XCTAssertNil(service.settings)
    let original = try JSONDecoder().decode(
      Subscribe.self,
      from: #"{"id":42,"name":"基础设置","type":"电视剧","sites":[3],"save_path":"/media/base"}"#
        .data(using: .utf8)!)
    _ = try await service.saveSubscription(original: original, draft: original)
    let capturedBody = await CompatibilityEndpointURLProtocol.stub.requestBody(suffix: "/subscribe")
    let bodyData = try XCTUnwrap(capturedBody)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    XCTAssertEqual(body["sites"] as? [Int], [3])
    XCTAssertEqual(body["save_path"] as? String, "/media/base")

    let success = try await service.searchSubscription(id: 41)
    XCTAssertTrue(success)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let methods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
    let index = try XCTUnwrap(paths.lastIndex(of: "/api/v1/subscribe/search/41"))
    XCTAssertEqual(methods[index], "GET")

    await userGate.open()
    let settings = try await fetch.value
    XCTAssertEqual(settings.BACKEND_VERSION, "v2.15.6")
    XCTAssertEqual(service.settings?.BACKEND_VERSION, "v2.15.6")
  }

  func testLegacyDetailRequestAddsTitleAndYearFallback() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = GlobalSettings(BACKEND_VERSION: "v2.15.6")

    let media = MediaInfo(
      source: "custom", media_id: "native-9", title: "示例片", type: "电影", year: "2024")
    _ = try await service.fetchMediaDetail(media: media)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let path = try XCTUnwrap(paths.last { $0.hasPrefix("/api/v1/media/") })
    let query = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: path))
    // v2 的媒体键识别失败后会按 title/year 走名称识别，Web 详情也一直带这两个参数。
    XCTAssertEqual(query["title"], "示例片")
    XCTAssertEqual(query["year"], "2024")
    XCTAssertEqual(query["type_name"], "电影")
    XCTAssertNil(query["media_source"])
  }

  func testUnresolvedDetailAddsTitleAndYearFallback() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = nil

    let media = MediaInfo(
      source: "custom", media_id: "native-9", title: "示例片", type: "电影", year: "2024")
    _ = try await service.fetchMediaDetail(media: media)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let path = try XCTUnwrap(paths.last { $0.hasPrefix("/api/v1/media/") })
    let query = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: path))
    // 未解析版本时仍按 v3 成对身份发；额外标题/年份让实际为 v2 的详情能走名称识别。
    XCTAssertEqual(query["media_source"], "custom")
    XCTAssertEqual(query["title"], "示例片")
    XCTAssertEqual(query["year"], "2024")
  }

  func testUnresolvedMediaServerExistsTreatsV2SuccessFalseAsMissing() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = nil

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from:
        #"{"tmdb_id":42,"title":"电影","year":"2026","type":"电影"}"#
        .data(using: .utf8)!
    )
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":false,"data":{"item":{}}}"#.data(using: .utf8)!)

    let missing = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertNil(missing, "未解析版本下 v2 的 success=false 必须按未入库处理")
  }

  func testModernDetailRequestKeepsV3QueryShape() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.9")

    let media = MediaInfo(
      source: "custom", media_id: "native-9", title: "示例片", type: "电影", year: "2024")
    _ = try await service.fetchMediaDetail(media: media)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    let path = try XCTUnwrap(paths.last { $0.hasPrefix("/api/v1/media/") })
    let query = Self.queryValues(
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: path))
    // v3 只按成对身份识别，不多发 title/year，保持现有请求形状。
    XCTAssertEqual(query["media_source"], "custom")
    XCTAssertEqual(query["type_name"], "电影")
    XCTAssertNil(query["title"])
    XCTAssertNil(query["year"])
  }

  func testLegacyBackendSkipsMediaSourceCatalogRequest() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = GlobalSettings(BACKEND_VERSION: "v2.15.6")

    let sources = try await service.fetchMediaSources()
    XCTAssertTrue(sources.isEmpty)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/media/source"))
  }

  func testLegacyBackendTreatsMediaServerExistsMissAsAbsent() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://compatibility-endpoint-tests.local"
    service.tokenForTesting = "compat-token"
    service.settings = GlobalSettings(BACKEND_VERSION: "v2.15.6")
    await CompatibilityEndpointURLProtocol.stub.setMediaServerExistsResponse(
      #"{"success":false,"message":"media not exists","data":{}}"#.data(using: .utf8)!)

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: #"{"tmdb_id":42,"title":"电影","year":"2026","type":"电影"}"#.data(using: .utf8)!)

    let exists = try await service.fetchMediaServerItemRef(media: media)
    XCTAssertNil(exists)
  }
}

@MainActor
private struct CompatibilityEndpointServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?
  let usernameKeychain: String?
  let usernameDefaults: String?
  let passwordKeychain: String?
  let passwordDefaults: String?
  let persistence: APIServicePersistenceSnapshot

  @MainActor
  static func capture(service: APIService) -> CompatibilityEndpointServiceSnapshot {
    CompatibilityEndpointServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      useImageCache: service.useImageCache,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser"),
      usernameKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username"),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password"),
      persistence: service.persistenceSnapshotForTesting()
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.replaceSessionForTesting(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser
    )
    service.settings = settings
    service.useImageCache = useImageCache
    service.restorePersistenceSnapshotForTesting(persistence)
    restoreDefaults(value: serverURLDefaults, forKey: "serverURL")
    restoreCredential(account: "accessToken", keychainValue: tokenKeychain, defaultsValue: tokenDefaults)
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
    restoreCredential(account: "username", keychainValue: usernameKeychain, defaultsValue: usernameDefaults)
    restoreCredential(account: "password", keychainValue: passwordKeychain, defaultsValue: passwordDefaults)
  }

  @MainActor
  private func restoreDefaults(value: String?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(keychainValue, service: "MoviePilot-TV", account: account)
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }
    restoreDefaults(value: defaultsValue, forKey: account)
  }

}

private actor CompatibilityEndpointURLProtocolStub {
  private var requests: [URLRequest] = []
  private var requestBodies: [Data?] = []
  private var publicSettingsResponse: Data?
  private var publicSettingsGate: CompatibilityEndpointAsyncGate?
  private var manualTransferResponses: [Data] = []
  private var userSettingsFailureStatusCode: Int?
  private var userSettingsGate: CompatibilityEndpointAsyncGate?
  private var manualTransferOmitsSuccess = false
  private var subscriptionActionsFail: Bool?
  private var subscriptionLookupResponse: Data?
  private var manualMediaResponses: [String: CompatibilityEndpointStubResponse] = [:]
  private var mediaServerExistsResponse: Data?
  private var detailLoadResponses: [String: Data] = [:]
  private var mediaMappingResponse: Data?
  private var mediaMappingMatchResponse: Data?
  private var mediaMappingMatchStatusCode: Int?
  private var mediaMappingMatchGate: CompatibilityEndpointAsyncGate?

  func reset() {
    requests.removeAll()
    requestBodies.removeAll()
    publicSettingsResponse = nil
    publicSettingsGate = nil
    manualTransferResponses.removeAll()
    userSettingsFailureStatusCode = nil
    userSettingsGate = nil
    manualTransferOmitsSuccess = false
    subscriptionActionsFail = nil
    subscriptionLookupResponse = nil
    manualMediaResponses.removeAll()
    mediaServerExistsResponse = nil
    detailLoadResponses.removeAll()
    mediaMappingResponse = nil
    mediaMappingMatchResponse = nil
    mediaMappingMatchStatusCode = nil
    mediaMappingMatchGate = nil
  }

  func setMediaMappingMatchResponse(
    _ response: Data?, statusCode: Int = 200, waitFor gate: CompatibilityEndpointAsyncGate? = nil
  ) {
    mediaMappingMatchResponse = response
    mediaMappingMatchStatusCode = statusCode
    mediaMappingMatchGate = gate
  }

  func setDetailLoadResponse(_ response: Data, path: String) {
    detailLoadResponses[path] = response
  }

  func setMediaMappingResponse(_ response: Data?) {
    mediaMappingResponse = response
  }

  func setMediaServerExistsResponse(_ response: Data?) {
    mediaServerExistsResponse = response
  }

  func setUserSettingsFailure(statusCode: Int?) {
    userSettingsFailureStatusCode = statusCode
  }

  func setUserSettingsGate(_ gate: CompatibilityEndpointAsyncGate?) {
    userSettingsGate = gate
  }

  func setPublicSettingsResponse(_ response: Data?, waitFor gate: CompatibilityEndpointAsyncGate? = nil) {
    publicSettingsResponse = response
    publicSettingsGate = gate
  }

  func setManualTransferOmitsSuccess(_ enabled: Bool) {
    manualTransferOmitsSuccess = enabled
  }

  func setManualTransferResponses(_ responses: [Data]) {
    manualTransferResponses = responses
  }

  func setSubscriptionActionsFail(_ fail: Bool) {
    subscriptionActionsFail = fail
  }

  func setSubscriptionLookupResponse(_ response: Data?) {
    subscriptionLookupResponse = response
  }

  func setManualMediaResponse(
    title: String,
    statusCode: Int = 200,
    data: Data,
    waitFor gate: CompatibilityEndpointAsyncGate? = nil
  ) {
    manualMediaResponses[title] = CompatibilityEndpointStubResponse(
      statusCode: statusCode,
      data: data,
      gate: gate
    )
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func requestMethods() -> [String] {
    requests.map { $0.httpMethod ?? "" }
  }

  func requestQueries() -> [String?] {
    requests.map { $0.url?.query }
  }

  func matchingQueries(suffix: String) -> [String?] {
    requests.indices.compactMap {
      requests[$0].url?.path.hasSuffix(suffix) == true
        ? .some(requests[$0].url?.query)
        : nil
    }
  }

  func matchingBodies(suffix: String) -> [Data?] {
    requests.indices.compactMap {
      requests[$0].url?.path.hasSuffix(suffix) == true
        ? .some(requestBodies[$0])
        : nil
    }
  }

  func requestBody(suffix: String) -> Data? {
    guard let index = requests.indices.last(where: {
      requests[$0].url?.path.hasSuffix(suffix) == true
    }) else { return nil }
    return requestBodies[index]
  }

  func requestQuery(suffix: String) -> String? {
    requests.last(where: { $0.url?.path.hasSuffix(suffix) == true })?.url?.query
  }

  private func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    requestBodies.append(bodyData(from: request))
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let data: Data
    let statusCode: Int
    if url.path == "/api/v1/system/global" {
      if let publicSettingsGate { await publicSettingsGate.wait() }
      statusCode = 200
      data = publicSettingsResponse
        ?? #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"v2.13.14","FRONTEND_VERSION":"v2.13.15"}}"#
          .data(using: .utf8)!
    } else if url.path == "/api/v1/system/global/user" {
      if let userSettingsGate { await userSettingsGate.wait() }
      if let userSettingsFailureStatusCode {
        statusCode = userSettingsFailureStatusCode
        data = #"{"success":false,"message":"not found"}"#.data(using: .utf8)!
      } else {
        statusCode = 200
        data =
          #"{"success":true,"data":{"AI_AGENT_ENABLE":true,"RECOGNIZE_SOURCE":"douban","USER_UNIQUE_ID":"compat-user","SUBSCRIBE_SHARE_MANAGE":true}}"#
          .data(using: .utf8)!
      }
    } else if url.path == "/api/v1/mediaserver/exists" {
      statusCode = 200
      data =
        mediaServerExistsResponse
        ?? #"{"success":true,"data":{"item":{"id":"library/42"}}}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/media/mapping" {
      statusCode = 200
      data = mediaMappingResponse ?? #"{"success":true,"data":null}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/media/mapping/match" {
      if let mediaMappingMatchGate { await mediaMappingMatchGate.wait() }
      statusCode = mediaMappingMatchStatusCode ?? 200
      data = mediaMappingMatchResponse ?? #"{"success":true,"data":null}"#.data(using: .utf8)!
    } else if let detailResponse = detailLoadResponses[url.path] {
      statusCode = 200
      data = detailResponse
    } else if url.path == "/api/v1/anilist/credits/154587" {
      statusCode = 200
      data = #"[{"source":"anilist","id":95097,"name":"种崎敦美"}]"#.data(using: .utf8)!
    } else if url.path == "/api/v1/anilist/recommend/154587" {
      statusCode = 200
      data = #"[{"source":"anilist","anilist_id":20954,"title":"声之形","type":"电影"}]"#.data(using: .utf8)!
    } else if url.path == "/api/v1/media/search" {
      let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == "title" })?
        .value
      if let title, let stubbed = manualMediaResponses[title] {
        if let gate = stubbed.gate {
          await gate.wait()
        }
        statusCode = stubbed.statusCode
        data = stubbed.data
      } else {
        statusCode = 200
        data =
          #"[{"source":"anilist","media_id":"154587","tmdb_id":42,"anilist_id":154587,"title":"葬送的芙莉莲","type":"电视剧","year":"2023"}]"#
          .data(using: .utf8)!
      }
    } else if url.path == "/api/v1/media/recognize" {
      statusCode = 200
      data =
        #"{"media_info":{"source":"themoviedb","tmdb_id":209867,"title":"搜索未命中","type":"电视剧","year":"2026"}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/subscribe/shares" && request.httpMethod == "GET" {
      statusCode = 200
      data =
        #"[{"id":88,"share_title":"官方分享","type":"电视剧","tmdbid":42,"bangumiid":404804,"anilistid":154587,"media_source":"anilist","media_id":"154587"}]"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/subscribe/fork" && request.httpMethod == "POST" {
      statusCode = 200
      data = #"{"success":true,"data":{"id":901}}"#.data(using: .utf8)!
    } else if url.path.hasPrefix("/api/v1/subscribe/media/") && request.httpMethod == "GET" {
      statusCode = 200
      data = subscriptionLookupResponse ?? #"{}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/transfer/manual" {
      statusCode = 200
      if manualTransferResponses.isEmpty {
        let successField = manualTransferOmitsSuccess ? "" : #""success":true,"#
        data = Data(
          """
          {\(successField)"message_i18n":"本地化预览完成","data":{"summary":{"total":1,"success":1,"failed":0},"items":[{"source":"/downloads/episode.mkv","target":"/library/Show/S01E01.mkv","success":true,"season":1,"episode":1}],"message":"预览完成"}}
          """.utf8
        )
      } else {
        data = manualTransferResponses.removeFirst()
      }
    } else if let subscriptionActionsFail,
      url.path.hasPrefix("/api/v1/subscribe/status/")
        || url.path.hasPrefix("/api/v1/subscribe/search/")
        || url.path.hasPrefix("/api/v1/subscribe/reset/")
    {
      statusCode = 200
      data =
        subscriptionActionsFail
        ? #"{"success":false,"message":"raw subscription error","message_i18n":"订阅不存在","data":{}}"#
          .data(using: .utf8)!
        : #"{"success":true,"message":null,"message_i18n":null,"data":{}}"#
          .data(using: .utf8)!
    } else {
      statusCode = 200
      data = #"{"success":true,"data":{"value":[]}}"#.data(using: .utf8)!
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

@MainActor
private final class CompatibilityEndpointReleaseFlag {
  var isReleased = false
}

private struct CompatibilityEndpointStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: CompatibilityEndpointAsyncGate?
}

private actor CompatibilityEndpointAsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func waitForWaiter() async {
    while waiters.isEmpty {
      await Task.yield()
    }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

private final class CompatibilityEndpointURLProtocol: URLProtocol {
  static let stub = CompatibilityEndpointURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "compatibility-endpoint-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = CompatibilityEndpointURLProtocolTaskContext(
      request: request,
      clientBox: CompatibilityEndpointURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = CompatibilityEndpointURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: CompatibilityEndpointURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let (response, data) = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: response, data: data)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class CompatibilityEndpointURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: CompatibilityEndpointURLProtocolClientBox

  init(request: URLRequest, clientBox: CompatibilityEndpointURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class CompatibilityEndpointURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(response: HTTPURLResponse, data: Data) {
    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}

@MainActor
final class MediaMappingTests: XCTestCase {
  private func configure(
    _ service: APIService, backendVersion: String, currentUser: Token? = nil
  ) throws {
    service.replaceSessionForTesting(
      baseURL: "https://compatibility-endpoint-tests.local", token: "token", currentUser: currentUser)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data("{\"BACKEND_VERSION\":\"\(backendVersion)\"}".utf8)
    )
  }

  private func installStub() {
    XCTAssertTrue(APIService.installURLProtocolForTesting(CompatibilityEndpointURLProtocol.self))
  }

  private func configureSubscriber(_ service: APIService, backendVersion: String) throws {
    let subscriber = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["subscribe": true],
      user_id: 42,
      user_name: "subscriber",
      avatar: nil
    )
    try configure(service, backendVersion: backendVersion, currentUser: subscriber)
  }

  func testFetchMediaMappingDecodesHitAndSendsContractQuery() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      )
    )

    let mapping = try await service.fetchMediaMapping(
      identity: MediaIdentity(source: "douban", mediaId: "123"),
      type: "电视剧",
      season: 2
    )

    XCTAssertEqual(mapping?.tmdb_id, 456)
    XCTAssertEqual(mapping?.tmdb_type, "tv")
    XCTAssertEqual(mapping?.tmdb_season, 3)
    let queries = await CompatibilityEndpointURLProtocol.stub.matchingQueries(
      suffix: "/media/mapping"
    ).compactMap { $0 }
    let query = try XCTUnwrap(queries.last)
    XCTAssertTrue(query.contains("media_source=douban"))
    XCTAssertTrue(query.contains("media_id=123"))
    XCTAssertTrue(query.contains("type=tv"))
    XCTAssertTrue(query.contains("season=2"))
  }

  func testFetchMediaMappingTreatsNullDataAsMiss() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null,"message":"未找到对应的 TMDB 关系"}"#.utf8)
    )

    let identity = MediaIdentity(source: "douban", mediaId: "123")
    let first = try await service.fetchMediaMapping(identity: identity, type: "电视剧", season: 2)
    let second = try await service.fetchMediaMapping(identity: identity, type: "电视剧", season: 2)

    XCTAssertNil(first)
    XCTAssertNil(second)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
  }

  func testFetchMediaMappingRejectsExplicitFailure() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":false,"message":"mapping failed"}"#.utf8)
    )

    do {
      _ = try await service.fetchMediaMapping(
        identity: MediaIdentity(source: "douban", mediaId: "123"),
        type: "电视剧",
        season: 2
      )
      XCTFail("Expected an explicit failure")
    } catch {
      guard case APIError.serverMessage(let message) = error else {
        XCTFail("Expected serverMessage, got \(error)")
        return
      }
      XCTAssertEqual(message, "mapping failed")
    }
  }

  func testFetchMediaMappingIsGatedBeforeV327() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.6")

    let mapping = try await service.fetchMediaMapping(
      identity: MediaIdentity(source: "douban", mediaId: "123"),
      type: "电视剧",
      season: 2
    )

    XCTAssertNil(mapping)
    XCTAssertFalse(service.supportsSharedMediaMapping)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.isEmpty)
  }

  func testActionHandlerPrefersSharedMappingAndKeepsTargetSeason() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let first = await handler.getTMDBJumpTarget(for: item)
    let second = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(first?.tmdb_id, 456)
    XCTAssertEqual(first?.type, "电视剧")
    XCTAssertEqual(first?.season, 3)
    XCTAssertEqual(first?.source, "tmdb")
    XCTAssertEqual(second?.tmdb_id, 456)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testActionHandlerCanSkipSharedMappingForSearch() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    let item = MediaInfo(douban_id: "123", source: "douban", type: "电视剧")
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(
      for: item,
      notifyWhenUnrecognized: false,
      useSharedMapping: false
    )

    XCTAssertNil(target)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.isEmpty)
  }

  func testActionHandlerTreatsZeroTmdbIdAsMissing() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"movie","tmdb_id":456,"tmdb_type":"movie"}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      tmdb_id: 0, douban_id: "123", source: "douban", title: "测试电影", type: "电影")
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 456)
    XCTAssertEqual(target?.source, "tmdb")
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testActionHandlerBeforeV329FallsBackToNameRecognitionAfterSharedMiss() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.8")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 209867)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/media/mapping/match"))
    XCTAssertTrue(paths.contains("/api/v1/media/search"))
    XCTAssertTrue(paths.contains("/api/v1/media/recognize"))
  }

  func testActionHandlerV329WithoutSharedMappingStillNameRecognizesTitledItem() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(
      for: item,
      notifyWhenUnrecognized: false,
      useSharedMapping: false
    )

    XCTAssertEqual(target?.tmdb_id, 209867)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/media/mapping") })
    XCTAssertTrue(paths.contains("/api/v1/media/search"))
    XCTAssertTrue(paths.contains("/api/v1/media/recognize"))
  }

  func testFetchMediaMappingMatchIsGatedBeforeV329() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let oldService = APIService.isolatedTestingInstance()
    try configure(oldService, backendVersion: "v3.2.8")
    XCTAssertFalse(oldService.supportsMediaMappingMatch)

    let oldMapping = try await oldService.fetchMediaMappingMatch(
      identity: MediaIdentity(source: "douban", mediaId: "123"),
      type: "电视剧",
      season: 2
    )
    XCTAssertNil(oldMapping)
    let oldPaths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertTrue(oldPaths.isEmpty)

    let newService = APIService.isolatedTestingInstance()
    try configure(newService, backendVersion: "v3.2.9")
    XCTAssertTrue(newService.supportsMediaMappingMatch)
  }

  func testFetchMediaMappingMatchPostsContractBodyAndDecodesHit() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      )
    )

    let mapping = try await service.fetchMediaMappingMatch(
      identity: MediaIdentity(source: "douban", mediaId: "123"),
      type: "电视剧",
      season: 2
    )

    XCTAssertEqual(mapping?.tmdb_id, 456)
    XCTAssertEqual(mapping?.tmdb_type, "tv")
    XCTAssertEqual(mapping?.tmdb_season, 3)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths, ["/api/v1/media/mapping/match"])
    let methods = await CompatibilityEndpointURLProtocol.stub.requestMethods()
    XCTAssertEqual(methods, ["POST"])

    let bodies = await CompatibilityEndpointURLProtocol.stub.matchingBodies(
      suffix: "/media/mapping/match"
    )
    let body = try XCTUnwrap(bodies.compactMap { $0 }.last)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    XCTAssertEqual(json["media_source"] as? String, "douban")
    XCTAssertEqual(json["media_id"] as? String, "123")
    XCTAssertEqual(json["type"] as? String, "tv")
    XCTAssertEqual(json["season"] as? Int, 2)
  }

  func testFetchMediaMappingMatchTreatsNullAsMissAndCachesIt() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )

    let identity = MediaIdentity(source: "douban", mediaId: "123")
    let first = try await service.fetchMediaMappingMatch(
      identity: identity, type: "电视剧", season: 2)
    let second = try await service.fetchMediaMappingMatch(
      identity: identity, type: "电视剧", season: 2)

    XCTAssertNil(first)
    XCTAssertNil(second)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping/match" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/media/mapping"))
  }

  func testActionHandlerSharedHitDoesNotRunOnDemandMatch() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 456)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths, ["/api/v1/media/mapping"])
  }

  func testActionHandlerFallsBackToMatchAfterSharedMiss() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"movie","tmdb_id":789,"tmdb_type":"movie"}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试电影", type: "电影")
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 789)
    XCTAssertEqual(target?.type, "电影")
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(
      paths,
      ["/api/v1/media/mapping", "/api/v1/media/mapping/match"]
    )
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
    let bodies = await CompatibilityEndpointURLProtocol.stub.matchingBodies(
      suffix: "/media/mapping/match"
    )
    let body = try XCTUnwrap(bodies.compactMap { $0 }.last)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    XCTAssertEqual(json["media_source"] as? String, "douban")
    XCTAssertEqual(json["media_id"] as? String, "123")
    XCTAssertEqual(json["type"] as? String, "movie")
    XCTAssertNil(json["season"])
  }

  func testActionHandlerStillMatchesWhenSharedMappingFails() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":false,"message":"mapping failed"}"#.utf8)
    )
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","tmdb_id":456,"tmdb_type":"tv"}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧")
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 456)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(
      paths,
      ["/api/v1/media/mapping", "/api/v1/media/mapping/match"]
    )
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testActionHandlerMatchMissFallsBackToNameRecognition() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    // 豆瓣第 2 季不在 TMDB 默认剧集组时，后端查找返回 null，名称识别仍能找到整剧。
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", year: "2024", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 209867)
    XCTAssertEqual(target?.season, 2)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths, [
      "/api/v1/media/mapping", "/api/v1/media/mapping/match",
      "/api/v1/media/search", "/api/v1/media/recognize",
    ])
  }

  func testActionHandlerMatchFailureFallsBackToNameRecognition() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", year: "2024")
    let failures: [(Data, Int)] = [
      (Data(#"{"detail":"查找 TMDB 链接失败，请稍后重试"}"#.utf8), 502),
      (Data(#"{"detail":"同时查找的条目过多，请稍后重试"}"#.utf8), 429),
      (Data(#"{"detail":"TMDB 链接查找服务暂不可用"}"#.utf8), 503),
      (Data(#"{"success":false,"message":"match failed"}"#.utf8), 200),
    ]

    for (body, statusCode) in failures {
      await stub.reset()
      let service = APIService.isolatedTestingInstance()
      try configure(service, backendVersion: "v3.2.9")
      await stub.setMediaMappingMatchResponse(body, statusCode: statusCode)
      let handler = MediaActionHandler(apiService: service)

      let target = await handler.getTMDBJumpTarget(for: item)

      XCTAssertEqual(target?.tmdb_id, 209867, "HTTP \(statusCode)")
      XCTAssertFalse(handler.showTMDBNotFoundAlert, "HTTP \(statusCode)")
      XCTAssertFalse(handler.isRecognizingTmdb, "HTTP \(statusCode)")
      let paths = await stub.requestPaths()
      XCTAssertEqual(paths, [
        "/api/v1/media/mapping", "/api/v1/media/mapping/match",
        "/api/v1/media/search", "/api/v1/media/recognize",
      ], "HTTP \(statusCode)")
    }
  }

  func testActionHandlerMatchEchoMismatchFallsBackToNameRecognition() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"999","type":"tv","tmdb_id":456,"tmdb_type":"tv"}}"#
          .utf8))
    let item = MediaInfo(douban_id: "123", source: "douban", title: "测试剧", type: "电视剧")

    let target = await MediaActionHandler(apiService: service).getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 209867)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/media/recognize"))
  }

  func testOnlyBuiltInConversionSourcesRunMatch() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    let cases: [(MediaInfo, Bool)] = [
      (MediaInfo(douban_id: "123", source: "douban", title: "测试剧", type: "电视剧"), true),
      (MediaInfo(bangumi_id: 404804, source: "bangumi", title: "测试剧", type: "电视剧"), true),
      (MediaInfo(mediaid_prefix: "anilist", media_id: "154587", title: "测试剧", type: "电视剧"), true),
      (MediaInfo(mediaid_prefix: "bangumi", media_id: "abc", title: "测试剧", type: "电视剧"), false),
      (MediaInfo(mediaid_prefix: "myplugin", media_id: "x-1", title: "测试剧", type: "电视剧"), false),
      (MediaInfo(mediaid_prefix: "imdb", media_id: "tt0111161", title: "测试剧", type: "电视剧"), false),
    ]

    for (item, expectsMatch) in cases {
      await stub.reset()
      let service = APIService.isolatedTestingInstance()
      try configure(service, backendVersion: "v3.2.9")
      let label = item.identity?.mediaKey ?? "nil"
      XCTAssertEqual(MediaActionHandler.canMatchTMDB(for: item, apiService: service), expectsMatch, label)

      let handler = MediaActionHandler(apiService: service)
      let target = await handler.getTMDBJumpTarget(for: item)

      XCTAssertEqual(target?.tmdb_id, 209867, label)
      XCTAssertFalse(handler.showTMDBNotFoundAlert, label)
      let paths = await stub.requestPaths()
      XCTAssertEqual(paths.contains("/api/v1/media/mapping/match"), expectsMatch, label)
      XCTAssertTrue(paths.contains("/api/v1/media/recognize"), label)
    }
  }

  func testMatchHTTP429UsesNameRecognitionForJumpAndOpenedDetail() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await stub.setMediaMappingMatchResponse(
      Data(#"{"detail":"同时查找的条目过多，请稍后重试"}"#.utf8), statusCode: 429)
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", year: "2024")
    let handler = MediaActionHandler(apiService: service)
    let target = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(target?.tmdb_id, 209867)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let jumpPaths = await stub.requestPaths()
    XCTAssertEqual(jumpPaths, [
      "/api/v1/media/mapping", "/api/v1/media/mapping/match",
      "/api/v1/media/search", "/api/v1/media/recognize",
    ])

    let preloadTask = MediaPreloadTask(partialMedia: item, apiService: service)
    preloadTask.start()
    defer { preloadTask.cancel() }
    await waitUntil(timeout: 3) { preloadTask.isTmdbRecognitionFinished }
    XCTAssertTrue(preloadTask.isOpenedDetailTMDBPending)
    XCTAssertNil(preloadTask.tmdbId)
    await preloadTask.matchTMDBForOpenedDetail(item)
    XCTAssertFalse(preloadTask.isOpenedDetailTMDBPending)
    XCTAssertEqual(preloadTask.tmdbTarget?.tmdb_id, target?.tmdb_id)
    XCTAssertEqual(preloadTask.tmdbId, target?.tmdb_id)
  }

  func testActionHandlerMatchFailureIsNotCachedAndRepostsOnRetry() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingMatchResponse(
      Data(#"{"success":false,"message":"match failed"}"#.utf8),
      statusCode: 502
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    let first = await handler.getTMDBJumpTarget(for: item)
    let second = await handler.getTMDBJumpTarget(for: item)

    XCTAssertEqual(first?.tmdb_id, 209867)
    XCTAssertEqual(second?.tmdb_id, 209867)
    XCTAssertFalse(handler.showTMDBNotFoundAlert)
    XCTAssertFalse(handler.isRecognizingTmdb)
    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping/match" }.count, 2)
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/recognize" }.count, 2)
  }

  func testPreloadUsesSharedMappingBeforeNameRecognition() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    await CompatibilityEndpointURLProtocol.stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.7")
    await CompatibilityEndpointURLProtocol.stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      )
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let task = MediaPreloadTask(partialMedia: item, apiService: service)
    task.start()
    defer { task.cancel() }

    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished }

    XCTAssertTrue(task.isTmdbRecognitionFinished)
    XCTAssertNil(task.tmdbId)
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 456)
    XCTAssertEqual(task.tmdbTarget?.type, "电视剧")
    XCTAssertEqual(task.tmdbTarget?.season, 3)

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    XCTAssertEqual(paths.filter { $0 == "/api/v1/media/mapping" }.count, 1)
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testCrossTypeMappingDoesNotBecomeSubscriptionOrDeletionIdentity() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.9")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"123","title":"来源电影","type":"电影"}"#.utf8),
      path: "/api/v1/media/123")
    await stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"movie","tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8))
    // 电影与电视剧可能有同一个数字 ID。命中这条订阅会指向另一部影片。
    await stub.setDetailLoadResponse(
      Data(#"{"id":902,"type":"电影","tmdbid":456,"media_source":"themoviedb","media_id":"456"}"#.utf8),
      path: "/api/v1/subscribe/media/456")
    let item = MediaInfo(douban_id: "123", source: "douban", title: "来源电影", type: "电影")
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))

    await waitUntil(timeout: 3) { task.isSubscribed != nil }
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 456)
    XCTAssertEqual(task.tmdbTarget?.type, "电视剧")
    XCTAssertEqual(task.isSubscribed, false)
    XCTAssertNil(preloader.findTask(byMediaId: "tmdb:456"))

    let viewModel = MediaDetailViewModel(detail: try XCTUnwrap(task.fullDetail), apiService: service)
    viewModel.preloadTask = task
    let request = viewModel.buildSubscribeRequest()
    XCTAssertNil(request.tmdbid)
    XCTAssertEqual(request.media_source, "douban")
    _ = await viewModel.cancelSubscription()
    let paths = await stub.requestPaths()
    let methods = await stub.requestMethods()
    XCTAssertTrue(paths.contains("/api/v1/subscribe/media/123"))
    XCTAssertFalse(paths.contains("/api/v1/subscribe/media/456"))
    XCTAssertFalse(methods.contains("DELETE"))
  }

  func testSharedMovieMappingRestoresSubscriptionAndMenuCancelsByRecordID() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()
    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.7")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"123","title":"来源电影","type":"电影"}"#.utf8),
      path: "/api/v1/media/123")
    await stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"movie","tmdb_id":456,"tmdb_type":"movie"}}"#
          .utf8))
    await stub.setDetailLoadResponse(
      Data(#"{"id":902,"type":"电影","tmdbid":456,"media_source":"themoviedb","media_id":"456"}"#.utf8),
      path: "/api/v1/subscribe/media/456")
    await stub.setDetailLoadResponse(
      Data(#"{"success":true}"#.utf8), path: "/api/v1/subscribe/902")
    let item = MediaInfo(douban_id: "123", source: "douban", title: "来源电影", type: "电影")
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))

    await waitUntil(timeout: 3) { task.isSubscribed == true }
    XCTAssertEqual(task.isSubscribed, true)
    XCTAssertNil(task.tmdbId)
    let viewModel = MediaDetailViewModel(detail: try XCTUnwrap(task.fullDetail), apiService: service)
    viewModel.preloadTask = task
    let request = viewModel.buildSubscribeRequest()
    XCTAssertEqual(request.tmdbid, 456)
    XCTAssertEqual(request.media_source, "douban")
    XCTAssertEqual(request.media_id, "123")

    let menu = SubscriptionHandler(apiService: service)
    menu.handleSubscribe(item, expectedSubscribed: true)
    await waitUntil(timeout: 3) { menu.unsubscribeConfirmationMessage != nil }
    XCTAssertNotNil(menu.unsubscribeConfirmationMessage)
    await stub.setDetailLoadResponse(Data("{}".utf8), path: "/api/v1/subscribe/media/456")
    menu.confirmUnsubscribe()
    await waitUntil(timeout: 3) { task.isSubscribed == false }
    XCTAssertEqual(task.isSubscribed, false)

    let paths = await stub.requestPaths()
    let methods = await stub.requestMethods()
    let queries = await stub.requestQueries()
    XCTAssertEqual(zip(paths, methods).filter { $0.1 == "DELETE" }.map { $0.0 }, [
      "/api/v1/subscribe/902"
    ])
    let mappedLookups = paths.indices.filter { paths[$0] == "/api/v1/subscribe/media/456" }
    XCTAssertFalse(mappedLookups.isEmpty)
    for index in mappedLookups {
      let query = try XCTUnwrap(queries[index]?.removingPercentEncoding)
      XCTAssertTrue(query.contains("mtype=电影"))
      XCTAssertFalse(query.contains("title="))
    }
    XCTAssertFalse(paths.contains("/api/v1/media/mapping/match"))
  }

  func testOpenedMovieMatchRefreshesSubscriptionAndHeaderKeepsConfirmedRecordID() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()
    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.9")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"123","title":"来源电影","type":"电影"}"#.utf8),
      path: "/api/v1/media/123")
    let matchGate = CompatibilityEndpointAsyncGate()
    await stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"movie","tmdb_id":456,"tmdb_type":"movie"}}"#
          .utf8),
      waitFor: matchGate)
    let lookupPath = "/api/v1/subscribe/media/456"
    await stub.setDetailLoadResponse(
      Data(#"{"id":902,"type":"电影","tmdbid":456}"#.utf8), path: lookupPath)
    let item = MediaInfo(douban_id: "123", source: "douban", title: "来源电影", type: "电影")
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))
    await waitUntil(timeout: 3) { task.isSubscribed != nil }
    XCTAssertEqual(task.isSubscribed, false)
    let detail = try XCTUnwrap(task.fullDetail)
    let match = Task { await task.matchTMDBForOpenedDetail(detail) }
    await waitUntil(timeout: 3) { await stub.requestPaths().contains("/api/v1/media/mapping/match") }
    XCTAssertEqual(task.isSubscribed, false)
    await matchGate.open()
    await match.value
    XCTAssertEqual(task.isSubscribed, true)

    let viewModel = MediaDetailViewModel(detail: detail, apiService: service)
    viewModel.preloadTask = task
    await stub.setDetailLoadResponse(
      Data(#"{"id":903,"type":"电视剧","tmdbid":456,"season":2}"#.utf8), path: lookupPath)
    await stub.setDetailLoadResponse(
      Data(#"[{"id":903,"name":"同号剧集","type":"电视剧","tmdbid":456,"season":2}]"#.utf8),
      path: "/api/v1/subscribe")
    let didRefresh = await viewModel.refreshSubscriptionStatus()
    XCTAssertTrue(didRefresh)
    XCTAssertFalse(viewModel.isSubscribed)
    let wrongTypeConfirmation = try await viewModel.prepareHeaderUnsubscribeConfirmation()
    XCTAssertNil(wrongTypeConfirmation)

    await stub.setDetailLoadResponse(
      Data(#"{"id":903,"type":"电影","tmdbid":456,"media_source":"themoviedb","media_id":"789"}"#.utf8),
      path: lookupPath)
    let wrongIdentityConfirmation = try await viewModel.prepareHeaderUnsubscribeConfirmation()
    XCTAssertNil(wrongIdentityConfirmation)

    await stub.setDetailLoadResponse(
      Data(#"{"id":902,"type":"电影","tmdbid":456}"#.utf8), path: lookupPath)
    let resolvedConfirmation = try await viewModel.prepareHeaderUnsubscribeConfirmation()
    let confirmation = try XCTUnwrap(resolvedConfirmation)
    XCTAssertEqual(confirmation.subscriptionID, 902)
    await stub.setDetailLoadResponse(
      Data(#"{"id":904,"type":"电影","tmdbid":456}"#.utf8), path: lookupPath)
    await stub.setDetailLoadResponse(
      Data(#"{"success":true}"#.utf8), path: "/api/v1/subscribe/902")
    let didCancel = await viewModel.cancelSubscription(confirmation: confirmation)
    XCTAssertTrue(didCancel)
    XCTAssertTrue(viewModel.isSubscribed)
    let paths = await stub.requestPaths()
    let methods = await stub.requestMethods()
    XCTAssertEqual(zip(paths, methods).filter { $0.1 == "DELETE" }.map { $0.0 }, [
      "/api/v1/subscribe/902"
    ])
  }

  func testMappedTMDBSeasonSurvivesWholeSeriesDetailAndWarmsThatSeason() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    let item = MediaInfo(douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    await stub.setMediaMappingResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8))
    await stub.setDetailLoadResponse(
      Data(
        #"{"tmdb_id":456,"source":"themoviedb","title":"整剧详情","type":"电视剧","season_info":[{"season_number":1},{"season_number":3}]}"#
          .utf8),
      path: "/api/v1/media/456")
    await stub.setDetailLoadResponse(Data("[]".utf8), path: "/api/v1/tmdb/456/3")
    let jumpTarget = await MediaActionHandler(apiService: service).getTMDBJumpTarget(for: item)
    let target = try XCTUnwrap(jumpTarget)
    let preloadedTarget = MediaDetailContainerView.tmdbPreloadTarget(
      for: item, fullDetail: item, recognizedTmdbId: nil, jumpTarget: target, isEnabled: true)
    XCTAssertEqual(preloadedTarget?.tmdbSeasonHint, 3)
    XCTAssertEqual(preloadedTarget?.id, target.id)
    let navigation = ImageNavigationCoordinator(apiService: service)
    defer { navigation.retire() }
    let entry = navigation.push(target)
    let task = try XCTUnwrap(navigation.preloadTask(for: entry))
    await waitUntil(timeout: 3) { await stub.requestPaths().contains("/api/v1/tmdb/456/3") }

    let detail = try XCTUnwrap(task.fullDetail)
    XCTAssertNil(detail.season)
    XCTAssertEqual(MediaDetailEpisodeSeasons.navigationSeason(for: detail, routeMedia: target), 3)
    let episodePaths = await stub.requestPaths().filter { $0.hasPrefix("/api/v1/tmdb/456/") }
    XCTAssertEqual(episodePaths, ["/api/v1/tmdb/456/3"])
  }

  func testMappingTargetSeasonPreservesSpecialsAndUnknown() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    let item = MediaInfo(douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let detail = MediaInfo(tmdb_id: 456, type: "电视剧")

    for season in [0, nil] as [Int?] {
      await stub.reset()
      let service = APIService.isolatedTestingInstance()
      try configure(service, backendVersion: "v3.2.9")
      let jsonSeason = season.map(String.init) ?? "null"
      await stub.setMediaMappingResponse(
        Data("""
          {"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":\(jsonSeason)}}
          """.utf8))
      let jumpTarget = await MediaActionHandler(apiService: service).getTMDBJumpTarget(for: item)
      let target = try XCTUnwrap(jumpTarget)
      XCTAssertEqual(target.season, season)
      XCTAssertEqual(MediaDetailEpisodeSeasons.navigationSeason(for: detail, routeMedia: target), season)
    }
  }

  func testFocusPreloadDefersMatchUntilOpeningDetailAndSeasonsDoNotWaitForMatch() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.9")
    await stub.setDetailLoadResponse(
      Data(
        #"{"douban_id":"123","source":"douban","title":"测试剧","type":"电视剧","season_info":[{"season_number":2,"episode_count":12}]}"#
          .utf8
      ),
      path: "/api/v1/media/123"
    )
    await stub.setDetailLoadResponse(Data("[]".utf8), path: "/api/v1/mediaserver/notexists")
    await stub.setDetailLoadResponse(Data("[]".utf8), path: "/api/v1/subscribe/")
    await stub.setMediaMappingResponse(
      Data(#"{"success":true,"data":null}"#.utf8)
    )
    let matchGate = CompatibilityEndpointAsyncGate()
    await stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","season":2,"tmdb_id":456,"tmdb_type":"tv","tmdb_season":3}}"#
          .utf8
      ),
      waitFor: matchGate
    )
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let navigation = ImageNavigationCoordinator(apiService: service)
    navigation.setStackForeground(true)
    defer { navigation.retire() }
    let task = try XCTUnwrap(
      service.mediaPreloader.preloadFocusedCandidateIfNeeded(for: item, stackID: navigation.id)
    )

    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished && task.fullDetail != nil }
    XCTAssertTrue(task.isTmdbRecognitionFinished)
    XCTAssertTrue(task.isOpenedDetailTMDBPending)
    XCTAssertNil(task.tmdbTarget)
    let warmedPaths = await stub.requestPaths()
    XCTAssertEqual(warmedPaths.filter { $0.hasPrefix("/api/v1/media/mapping") }, [
      "/api/v1/media/mapping"
    ])

    let entry = navigation.push(item)
    XCTAssertTrue(navigation.preloadTask(for: entry) === task)
    let detail = try XCTUnwrap(task.fullDetail)
    let match = Task { await task.matchTMDBForOpenedDetail(detail) }
    await waitUntil(timeout: 3) { await stub.requestPaths().contains("/api/v1/media/mapping/match") }
    let pendingPaths = await stub.requestPaths()
    XCTAssertTrue(pendingPaths.contains("/api/v1/media/mapping/match"))

    await waitUntil(timeout: 3) { task.isDetailReady && task.isSeasonDataLoaded }
    XCTAssertTrue(task.isDetailReady)
    XCTAssertTrue(task.isSeasonDataLoaded)
    XCTAssertEqual(task.seasonViewModel?.seasonInfos.compactMap(\.season_number), [2])
    XCTAssertEqual(task.seasonViewModel?.hasSeasonLoadError, false)
    XCTAssertNil(task.tmdbTarget)

    XCTAssertTrue(task.isOpenedDetailTMDBPending)
    await matchGate.open()
    await match.value
    XCTAssertFalse(task.isOpenedDetailTMDBPending)
    XCTAssertNil(task.tmdbId)
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 456)
    XCTAssertEqual(task.tmdbTarget?.type, "电视剧")
    XCTAssertEqual(task.tmdbTarget?.season, 3)

    let paths = await stub.requestPaths()
    let mappingPaths = paths.filter { $0.hasPrefix("/api/v1/media/mapping") }
    XCTAssertEqual(
      mappingPaths,
      ["/api/v1/media/mapping", "/api/v1/media/mapping/match"]
    )
    let matchBody = await stub.requestBody(suffix: "/media/mapping/match")
    let body = try XCTUnwrap(matchBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["season"] as? Int, 2)
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testOpenedDetailMatchMissNameRecognizesAndReleasesWaitingJump() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.9")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"123","title":"来源电影","type":"电影","year":"2024"}"#.utf8),
      path: "/api/v1/media/123")
    let matchGate = CompatibilityEndpointAsyncGate()
    await stub.setMediaMappingMatchResponse(
      Data(#"{"success":true,"data":null}"#.utf8), waitFor: matchGate)
    await stub.setManualMediaResponse(
      title: "来源电影",
      data: Data(
        #"[{"source":"themoviedb","tmdb_id":209867,"title":"来源电影","type":"电影","year":"2024"}]"#.utf8))
    await stub.setDetailLoadResponse(
      Data(#"{"id":905,"type":"电影","tmdbid":209867}"#.utf8),
      path: "/api/v1/subscribe/media/209867")
    let item = MediaInfo(douban_id: "123", source: "douban", title: "来源电影", type: "电影")
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))

    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished && task.isSubscribed != nil }
    XCTAssertTrue(task.isOpenedDetailTMDBPending)
    XCTAssertEqual(task.isSubscribed, false)
    XCTAssertNil(task.tmdbId)
    let preloadPaths = await stub.requestPaths()
    XCTAssertFalse(preloadPaths.contains("/api/v1/media/recognize"))

    let jump = CompatibilityEndpointReleaseFlag()
    let waitingJump = Task {
      await task.waitForTMDBIdentification()
      jump.isReleased = true
    }
    let detail = try XCTUnwrap(task.fullDetail)
    let match = Task { await task.matchTMDBForOpenedDetail(detail) }
    await waitUntil(timeout: 3) { await stub.requestPaths().contains("/api/v1/media/mapping/match") }
    XCTAssertFalse(jump.isReleased)

    await matchGate.open()
    await match.value
    await waitingJump.value

    XCTAssertTrue(jump.isReleased)
    XCTAssertFalse(task.isOpenedDetailTMDBPending)
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 209867)
    XCTAssertEqual(task.tmdbTarget?.type, "电影")
    XCTAssertEqual(task.tmdbId, 209867)
    // 名称识别结果只用于跳转，不按猜出的编号补查订阅。
    XCTAssertEqual(task.isSubscribed, false)
    let paths = await stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/subscribe/media/209867"))
  }

  /// 分季卡片用简称、完整详情给出正式片名：名称识别用正式片名，只从卡片沿用季号。
  func testOpenedDetailRecognitionUsesFullDetailTitleAndKeepsCardSeason() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.9")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"123","title":"作品 A：特别篇","type":"电视剧","year":"2024"}"#.utf8),
      path: "/api/v1/media/123")
    await stub.setMediaMappingMatchResponse(Data(#"{"success":true,"data":null}"#.utf8))
    await stub.setManualMediaResponse(
      title: "作品 A",
      data: Data(#"[{"source":"themoviedb","tmdb_id":111,"title":"作品 A","type":"电视剧","year":"2019"}]"#.utf8))
    await stub.setManualMediaResponse(
      title: "作品 A：特别篇",
      data: Data(
        #"[{"source":"themoviedb","tmdb_id":222,"title":"作品 A：特别篇","type":"电视剧","year":"2024"}]"#.utf8))
    let item = MediaInfo(douban_id: "123", source: "douban", title: "作品 A", type: "电视剧", season: 2)
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))

    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished && task.fullDetail != nil }
    XCTAssertTrue(task.isOpenedDetailTMDBPending)
    let detail = try XCTUnwrap(task.fullDetail)
    XCTAssertNil(detail.season)
    await task.matchTMDBForOpenedDetail(detail)

    XCTAssertFalse(task.isOpenedDetailTMDBPending)
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 222)
    XCTAssertEqual(task.tmdbTarget?.tmdbSeasonHint, 2)
    // 卡片用卡片季号查映射，识别不再用卡片简称。
    let matchBody = await stub.requestBody(suffix: "/media/mapping/match")
    let body = try XCTUnwrap(matchBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["season"] as? Int, 2)
  }

  func testCancelledOpenedDetailMatchStaysPendingAndRerunsWhenShownAgain() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.9")
    let matchGate = CompatibilityEndpointAsyncGate()
    await stub.setMediaMappingMatchResponse(
      Data(
        #"{"success":true,"data":{"media_source":"douban","media_id":"123","type":"tv","tmdb_id":456,"tmdb_type":"tv"}}"#
          .utf8),
      waitFor: matchGate)
    let item = MediaInfo(douban_id: "123", source: "douban", title: "测试剧", type: "电视剧")
    let task = MediaPreloadTask(partialMedia: item, apiService: service)
    task.start()
    defer { task.cancel() }
    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished }
    XCTAssertTrue(task.isOpenedDetailTMDBPending)

    let firstMatch = Task { await task.matchTMDBForOpenedDetail(item) }
    await waitUntil(timeout: 3) { await stub.requestPaths().contains("/api/v1/media/mapping/match") }
    firstMatch.cancel()
    await firstMatch.value
    XCTAssertTrue(task.isOpenedDetailTMDBPending)
    XCTAssertNil(task.tmdbTarget)
    XCTAssertNil(task.tmdbId)

    await matchGate.open()
    await task.matchTMDBForOpenedDetail(item)
    XCTAssertFalse(task.isOpenedDetailTMDBPending)
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 456)
    let paths = await stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/media/recognize"))
  }

  func testPluginSourcePreloadNeverNameRecognizesButJumpDoes() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    // 主来源是插件、但带着豆瓣 ID 的条目会显示 TMDB 按钮。
    let item = MediaInfo(
      douban_id: "123", mediaid_prefix: "myplugin", media_id: "x-1", title: "测试剧", type: "电视剧")
    XCTAssertTrue(item.canJumpToTMDB)

    for version in ["v3.2.8", "v3.2.9"] {
      await stub.reset()
      let service = APIService.isolatedTestingInstance()
      try configure(service, backendVersion: version)
      let task = MediaPreloadTask(partialMedia: item, apiService: service)
      task.start()
      await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished }
      await task.matchTMDBForOpenedDetail(item)

      XCTAssertTrue(task.isTmdbRecognitionFinished, version)
      XCTAssertFalse(task.isOpenedDetailTMDBPending, version)
      XCTAssertNil(task.tmdbId, version)
      XCTAssertNil(task.tmdbTarget, version)
      let preloadPaths = await stub.requestPaths()
      XCTAssertFalse(preloadPaths.contains("/api/v1/media/search"), version)
      XCTAssertFalse(preloadPaths.contains("/api/v1/media/recognize"), version)
      XCTAssertFalse(preloadPaths.contains("/api/v1/media/mapping/match"), version)
      task.cancel()

      // 用户按下 TMDB 时才按名称识别。
      let target = await MediaActionHandler(apiService: service).getTMDBJumpTarget(for: item)
      XCTAssertEqual(target?.tmdb_id, 209867, version)
      let jumpPaths = await stub.requestPaths()
      XCTAssertTrue(jumpPaths.contains("/api/v1/media/recognize"), version)
      XCTAssertFalse(jumpPaths.contains("/api/v1/media/mapping/match"), version)
    }
  }

  func testOldBackendPreloadStillNameRecognizesBuiltInSourceAndKeepsCardSeason() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.8")
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let task = MediaPreloadTask(partialMedia: item, apiService: service)
    task.start()
    defer { task.cancel() }
    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished }

    XCTAssertFalse(task.isOpenedDetailTMDBPending)
    XCTAssertEqual(task.tmdbId, 209867)
    let target = try XCTUnwrap(task.tmdbTarget)
    XCTAssertEqual(target.tmdb_id, 209867)
    XCTAssertEqual(target.type, "电视剧")
    XCTAssertEqual(target.tmdbSeasonHint, 2)
    // 目标页只有整剧详情时仍按分季卡片的季号选季；没有这一季时由选季逻辑回到默认季。
    let wholeSeries = MediaInfo(tmdb_id: 209867, type: "电视剧")
    XCTAssertEqual(MediaDetailEpisodeSeasons.navigationSeason(for: wholeSeries, routeMedia: target), 2)
    XCTAssertEqual(MediaDetailEpisodeSeasons.current(selected: 2, preferred: nil, available: [1]), 1)
    let paths = await stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/media/mapping/match"))
  }

  func testOldBackendUnmatchedRecognitionIsRecordedForWaitingJump() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.8")
    // 识别桩只给出剧集，电影类型不匹配，识别确认没有结果。
    let item = MediaInfo(douban_id: "123", source: "douban", title: "未知电影", type: "电影")
    let task = MediaPreloadTask(partialMedia: item, apiService: service)
    task.start()
    defer { task.cancel() }
    await waitUntil(timeout: 3) { task.isTmdbRecognitionFinished }

    XCTAssertTrue(task.isTMDBUnrecognized(for: item))
    // 完整详情换了正式片名时，卡片的结论不适用，按钮还要再识别一次。
    let fullDetail = MediaInfo(douban_id: "123", source: "douban", title: "未知电影 导演剪辑版", type: "电影")
    XCTAssertFalse(task.isTMDBUnrecognized(for: fullDetail))
    let otherYear = MediaInfo(douban_id: "123", source: "douban", title: "未知电影", type: "电影", year: "2020")
    XCTAssertFalse(task.isTMDBUnrecognized(for: otherYear))
    XCTAssertNil(task.tmdbId)
    XCTAssertNil(task.tmdbTarget)
  }

  func testLiveRecognitionJumpKeepsSeasonCardHint() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configure(service, backendVersion: "v3.2.8")
    let item = MediaInfo(
      douban_id: "123", source: "douban", title: "测试剧", type: "电视剧", season: 2)
    let handler = MediaActionHandler(apiService: service)

    // 预载还没结果时长按「TMDB详情页」：实时识别的目标与预载结果一样带选季提示。
    let liveTarget = await handler.getTMDBJumpTarget(for: item)
    let live = try XCTUnwrap(liveTarget)
    XCTAssertEqual(live.tmdb_id, 209867)
    XCTAssertEqual(live.season, 2)
    XCTAssertEqual(live.tmdbSeasonHint, 2)
    let wholeSeries = MediaInfo(tmdb_id: 209867, type: "电视剧")
    XCTAssertEqual(MediaDetailEpisodeSeasons.navigationSeason(for: wholeSeries, routeMedia: live), 2)

    // 传入预载识别出的编号时同样带上。
    let preloaded = await handler.getTMDBJumpTarget(for: item, targetTmdbId: 209867)
    XCTAssertEqual(preloaded?.tmdbSeasonHint, 2)
  }

  /// 名称识别可能猜中同名同年的另一部：猜出的编号只用于 TMDB 跳转，
  /// 不决定原影片的订阅状态，也不进入新建或取消订阅。
  func testRecognizedMovieIDStaysOutOfSubscriptionChain() async throws {
    installStub()
    defer { APIService.removeURLProtocolForTesting(CompatibilityEndpointURLProtocol.self) }
    let stub = CompatibilityEndpointURLProtocol.stub
    await stub.reset()

    let service = APIService.isolatedTestingInstance()
    try configureSubscriber(service, backendVersion: "v3.2.8")
    await stub.setDetailLoadResponse(
      Data(#"{"source":"douban","douban_id":"27601044","title":"小美人鱼","type":"电影","year":"2023"}"#.utf8),
      path: "/api/v1/media/27601044")
    await stub.setManualMediaResponse(
      title: "小美人鱼",
      data: Data(
        #"[{"source":"themoviedb","tmdb_id":1136767,"title":"小美人鱼","type":"电影","year":"2023"}]"#.utf8))
    // 猜中的另一部已有订阅，原影片自己没有。
    await stub.setDetailLoadResponse(
      Data(#"{"id":902,"name":"小美人鱼","year":"2023","type":"电影","tmdbid":1136767}"#.utf8),
      path: "/api/v1/subscribe/media/1136767")
    let item = MediaInfo(douban_id: "27601044", source: "douban", title: "小美人鱼", type: "电影")
    let preloader = service.mediaPreloader
    defer { preloader.tearDown() }
    let task = try XCTUnwrap(preloader.acquireNavigation(for: item, owner: UUID()))

    await waitUntil(timeout: 3) { task.isSubscribed != nil }
    XCTAssertEqual(task.tmdbTarget?.tmdb_id, 1136767)
    XCTAssertEqual(task.isSubscribed, false)

    let viewModel = MediaDetailViewModel(detail: try XCTUnwrap(task.fullDetail), apiService: service)
    viewModel.preloadTask = task
    XCTAssertNil(viewModel.buildSubscribeRequest().tmdbid)
    let didRefresh = await viewModel.refreshSubscriptionStatus()
    XCTAssertTrue(didRefresh)
    XCTAssertEqual(task.isSubscribed, false)

    let menu = SubscriptionHandler(apiService: service)
    menu.handleSubscribe(item, expectedSubscribed: false)
    await waitUntil(timeout: 3) { menu.sheetSubscribe != nil || !menu.notificationMessage.isEmpty }
    XCTAssertEqual(menu.notificationMessage, "")
    XCTAssertNil(menu.sheetSubscribe?.tmdbid)
    XCTAssertEqual(menu.sheetSubscribe?.doubanid, "27601044")
    XCTAssertEqual(task.isSubscribed, false)

    let paths = await stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/subscribe/media/1136767"))
    let methods = await stub.requestMethods()
    XCTAssertFalse(methods.contains("DELETE"))
  }

  private func waitUntil(
    timeout: TimeInterval,
    condition: @MainActor () async -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}
