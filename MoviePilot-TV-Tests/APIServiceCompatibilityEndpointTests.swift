import XCTest

@testable import MoviePilot_TV

@MainActor
final class APIServiceCompatibilityEndpointTests: XCTestCase {
  func testFetchSettingsReadsPublicBackendVersion() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = nil

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

  func testFetchSettingsMergesLoggedInUserSettings() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"

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
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsFailure(statusCode: 404)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"

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

  func testFetchSettingsKeepsSessionWhenOptionalUserSettingsIsForbidden() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setUserSettingsFailure(statusCode: 403)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"
    service.currentUser = Token(
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
    XCTAssertEqual(settings.FRONTEND_VERSION, "v2.13.15")
    XCTAssertNil(settings.AI_AGENT_ENABLE)
    XCTAssertEqual(service.token, "token")
    XCTAssertEqual(service.currentUser?.user_name, "limited-user")

    let paths = await CompatibilityEndpointURLProtocol.stub.requestPaths()
    assertContainsSubsequence(
      ["/api/v1/system/global", "/api/v1/system/global/user"],
      in: paths
    )
    XCTAssertFalse(paths.contains("/api/v1/login/access-token"))
  }

  func testPublicSystemConfigReadersUsePublicSettingEndpoints() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "token"
    service.currentUser = Token(
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
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(false)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURL = "https://compatibility-endpoint-tests.local"

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
    XCTAssertEqual(actionIndexes.map { methods[$0] }, ["PUT", "GET", "GET"])
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
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    await CompatibilityEndpointURLProtocol.stub.setSubscriptionActionsFail(true)
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURL = "https://compatibility-endpoint-tests.local"

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
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURL = "https://compatibility-endpoint-tests.local"

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from:
        #"{"tmdb_id":42,"title":"电影","year":"2026","type":"电影"}"#
        .data(using: .utf8)!
    )

    let exists = try await service.fetchMediaServerExists(media: media)
    XCTAssertTrue(exists)

    let capturedExistsQuery =
      await CompatibilityEndpointURLProtocol.stub.requestQuery(suffix: "/mediaserver/exists")
    let existsQuery = try XCTUnwrap(capturedExistsQuery)
    XCTAssertEqual(
      Set(existsQuery.split(separator: "&").map(String.init)),
      Set(["tmdbid=42", "title=%E7%94%B5%E5%BD%B1", "year=2026", "mtype=%E7%94%B5%E5%BD%B1"])
    )
  }

  func testManualMediaSearchMatchesWebSelectorContractAndKeepsAniListNativeID()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURL = "https://compatibility-endpoint-tests.local"

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
        "source": "anilist",
      ]
    )
    XCTAssertNil(query["type"])
  }

  func testManualTransferPreviewUsesBackgroundFalseAndPreservesAniListIdentity() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

    await CompatibilityEndpointURLProtocol.stub.reset()
    let service = APIService.testingInstance()
    let snapshot = CompatibilityEndpointServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURL = "https://compatibility-endpoint-tests.local"

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
  }

  func testReorganizePreviewMergesHistoryResponsesAndDeduplicatesItems() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

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

    let previewSucceeded = await viewModel.preview()
    XCTAssertFalse(previewSucceeded)

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
      try Self.jsonObject($0)["preview"] as? Bool == true
    }
    XCTAssertTrue(allPreviewBodies)
  }

  func testReorganizeSubmitUsesBackgroundRequestsForEveryHistory() async throws {
    XCTAssertTrue(URLProtocol.registerClass(CompatibilityEndpointURLProtocol.self))
    defer { URLProtocol.unregisterClass(CompatibilityEndpointURLProtocol.self) }

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

  private func configureManageUser(_ service: APIService) {
    service.baseURL = "https://compatibility-endpoint-tests.local"
    service.token = "manage-user"
    service.currentUser = Token(
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
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.currentUser = currentUser
    service.settings = settings
    service.useImageCache = useImageCache
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
  private var manualTransferResponses: [Data] = []
  private var userSettingsFailureStatusCode: Int?
  private var manualTransferOmitsSuccess = false
  private var subscriptionActionsFail: Bool?

  func reset() {
    requests.removeAll()
    requestBodies.removeAll()
    manualTransferResponses.removeAll()
    userSettingsFailureStatusCode = nil
    manualTransferOmitsSuccess = false
    subscriptionActionsFail = nil
  }

  func setUserSettingsFailure(statusCode: Int?) {
    userSettingsFailureStatusCode = statusCode
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

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    requestBodies.append(bodyData(from: request))
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let data: Data
    let statusCode: Int
    if url.path == "/api/v1/system/global" {
      statusCode = 200
      data =
        #"{"success":true,"data":{"TMDB_IMAGE_DOMAIN":"image.tmdb.org","GLOBAL_IMAGE_CACHE":true,"BACKEND_VERSION":"v2.13.14","FRONTEND_VERSION":"v2.13.15"}}"#
        .data(using: .utf8)!
    } else if url.path == "/api/v1/system/global/user" {
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
      data = #"{"success":true,"data":{"item":{"id":"library/42"}}}"#.data(using: .utf8)!
    } else if url.path == "/api/v1/media/search" {
      statusCode = 200
      data =
        #"[{"source":"anilist","media_id":"154587","tmdb_id":42,"anilist_id":154587,"title":"葬送的芙莉莲","type":"电视剧","year":"2023"}]"#
        .data(using: .utf8)!
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
