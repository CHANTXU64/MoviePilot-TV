import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSheetViewModelTests: XCTestCase {
  private let autoSearchKey = "autoSearchNewSubscriptions"

  func testAutoSearchNewSubscriptionsDefaultsToEnabled() {
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    UserDefaults.standard.removeObject(forKey: autoSearchKey)
    defer { restoreUserDefaultsValue(originalValue, forKey: autoSearchKey) }

    let viewModel = SystemViewModel()

    XCTAssertTrue(viewModel.autoSearchNewSubscriptions)
    XCTAssertTrue(SystemViewModel.shouldAutoSearchNewSubscriptions)
  }

  func testSubscriptionHandlerDistinguishesNewAndExistingEditors() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/subscribe/media/tmdb:998901",
      json: "{}"
    )
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/subscribe/998902",
      json: #"{"id":998902,"name":"已有订阅","type":"电影","tmdbid":998902}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let handler = SubscriptionHandler(apiService: service)
    handler.handleSubscribe(
      MediaInfo(tmdb_id: 998_901, title: "新增订阅", type: "电影")
    )
    try await waitUntil("new subscription editor opens") {
      handler.sheetSubscribe != nil
    }
    XCTAssertTrue(handler.sheetIsNewSubscription)
    XCTAssertEqual(handler.sheetSubscribe?.apiMediaId, "tmdb:998901")

    await handler.fetchSubscriptionAndShowEditor(subId: 998_902)
    XCTAssertFalse(handler.sheetIsNewSubscription)
    XCTAssertEqual(handler.sheetSubscribe?.id, 998_902)
  }

  func testSubscriptionHandlerDeletesResolvedFallbackSubscription() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let preloader = MediaPreloader(apiService: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/media/douban:fallback-douban",
      json: #"{"douban_id":"fallback-douban","title":"回退取消订阅","type":"电影"}"#
    )
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/subscribe/media/douban:fallback-douban",
      json: "{}"
    )
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/subscribe/media/tmdb:998903",
      json: #"{"id":998903,"name":"回退取消订阅","type":"电影","tmdbid":998903}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let media = MediaInfo(
      douban_id: "fallback-douban",
      title: "回退取消订阅",
      type: "电影"
    )
    let preloadTask = preloader.preload(for: media)
    preloadTask.tmdbId = 998_903
    try await waitUntil("preloaded fallback subscription state is ready") {
      preloadTask.isSubscribed == true
    }

    let handler = SubscriptionHandler(apiService: service, mediaPreloader: preloader)
    handler.handleSubscribe(media)
    try await waitUntil("subscription state updates after deletion") {
      preloadTask.isSubscribed == false
    }

    let tmdbDeleteCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE",
      path: "/api/v1/subscribe/media/tmdb:998903"
    )
    let doubanDeleteCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE",
      path: "/api/v1/subscribe/media/douban:fallback-douban"
    )
    XCTAssertEqual(tmdbDeleteCount, 1)
    XCTAssertEqual(doubanDeleteCount, 0)
  }

  func testSubscriptionHandlerKeepsCachedStateWhenDeleteFails() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let preloader = MediaPreloader(apiService: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/media/tmdb:998904",
      json: #"{"tmdb_id":998904,"title":"取消失败","type":"电影"}"#
    )
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/subscribe/media/tmdb:998904",
      json: #"{"id":998904,"name":"取消失败","type":"电影","tmdbid":998904}"#
    )
    await SubscribeSheetURLProtocol.stub.respond(
      method: "DELETE",
      path: "/api/v1/subscribe/media/tmdb:998904",
      json: #"{"success":false,"message":"后端拒绝取消"}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let media = MediaInfo(
      tmdb_id: 998_904,
      title: "取消失败",
      type: "电影"
    )
    let preloadTask = preloader.preload(for: media)
    preloadTask.isSubscribed = true

    let handler = SubscriptionHandler(apiService: service, mediaPreloader: preloader)
    handler.handleSubscribe(media)
    try await waitUntil("unsubscribe failure appears") {
      handler.notificationType == .error
        && handler.notificationMessage == "《取消失败》取消订阅失败：后端拒绝取消"
    }

    XCTAssertEqual(preloadTask.isSubscribed, true)
  }

  func testSavePathOptionsRemoveEmptyAndDuplicatePaths() {
    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 1, name: "目录测试", type: "电影")
    )
    viewModel.directories = [
      TransferDirectoryConf(
        name: "目录 A",
        storage: "local",
        download_path: "/downloads",
        library_path: nil,
        library_storage: nil,
        transfer_type: "copy",
        scraping: nil,
        library_category_folder: nil,
        library_type_folder: nil
      ),
      TransferDirectoryConf(
        name: "目录 A 重复",
        storage: "local",
        download_path: "/downloads",
        library_path: nil,
        library_storage: nil,
        transfer_type: "copy",
        scraping: nil,
        library_category_folder: nil,
        library_type_folder: nil
      ),
      TransferDirectoryConf(
        name: "空目录",
        storage: "local",
        download_path: "",
        library_path: nil,
        library_storage: nil,
        transfer_type: "copy",
        scraping: nil,
        library_category_folder: nil,
        library_type_folder: nil
      ),
      TransferDirectoryConf(
        name: "目录 B",
        storage: "local",
        download_path: "/media",
        library_path: nil,
        library_storage: nil,
        transfer_type: "copy",
        scraping: nil,
        library_category_folder: nil,
        library_type_folder: nil
      ),
    ]

    XCTAssertEqual(viewModel.savePathOptions, ["/downloads", "/media"])
  }

  func testSavedSubscriptionUpdatesMatchingPreloadedTask() {
    let preloader = MediaPreloader.shared
    preloader.clearAll()
    defer { preloader.clearAll() }

    let media = MediaInfo(
      tmdb_id: 991_001,
      title: "预加载同步",
      type: "电影",
      collection_id: 1
    )
    let task = preloader.preload(for: media)

    XCTAssertNil(task.isSubscribed)
    XCTAssertTrue(
      MediaSubscriptionModifier.updatePreloadedSubscription(
        afterSaving: Subscribe(
          name: "预加载同步",
          type: "电影",
          tmdbid: 991_001,
          mediaid: "tmdb:991001"
        )
      )
    )
    XCTAssertEqual(task.isSubscribed, true)
  }

  func testSaveNewSubscriptionSkipsSearchWhenAutoSearchSettingIsDisabled() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.set(false, forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 777, name: "关闭自动搜索", type: "电影", tmdbid: 123456),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/777")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/777")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 0)
  }

  func testSaveNewSubscriptionSearchesByDefault() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.removeObject(forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 778, name: "默认自动搜索", type: "电影", tmdbid: 123457),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/778")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/778")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 1)
  }

  func testSaveExistingSubscriptionSearchesWhenNewSubscriptionAutoSearchIsDisabled() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.set(false, forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 779, name: "已有订阅", type: "电影", tmdbid: 123458),
      isNewSubscription: false
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/779")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/779")
    XCTAssertEqual(statusRequestCount, 0)
    XCTAssertEqual(searchRequestCount, 1)
  }

  func testSavePublishesSubscriptionUpdateOnceAfterFollowUpSearchFinishes() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.suspend(path: "/api/v1/subscribe/search/780")
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let notifications = SubscribeSheetNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 780, name: "等待搜索完成", type: "电影", tmdbid: 123_459),
      apiService: service
    )
    let saveTask = Task { await viewModel.save() }
    try await waitUntil("follow-up search starts") {
      await SubscribeSheetURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/subscribe/search/780") == 1
    }

    XCTAssertEqual(notifications.count(), 0)

    await SubscribeSheetURLProtocol.stub.release(path: "/api/v1/subscribe/search/780")
    let didSave = await saveTask.value
    XCTAssertTrue(didSave)
    XCTAssertEqual(notifications.count(), 1)
  }

  func testCancelNewSubscriptionPublishesOnlyAfterRollbackDeleteSucceeds() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let notifications = SubscribeSheetNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 781, name: "取消新订阅", type: "电影", tmdbid: 123_460),
      isNewSubscription: true,
      apiService: service
    )

    await viewModel.cancel()

    let deleteRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE", path: "/api/v1/subscribe/781")
    XCTAssertEqual(deleteRequestCount, 1)
    XCTAssertEqual(notifications.count(), 1)
  }

  func testCancelNewSubscriptionDoesNotRollbackAfterAccountSwitch() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.suspend(path: "/api/v1/subscribe/status/801")
    let accountA = subscriberToken(userID: 1, accessToken: "account-a")
    service.replaceSessionForTesting(
      baseURL: "http://subscribe-sheet-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(
        id: nil,
        name: "跨账号取消",
        type: "电影",
        tmdbid: 123_461
      ),
      isNewSubscription: true,
      apiService: service
    )
    let loadTask = Task { await viewModel.loadData() }
    try await waitUntil("new subscription pause request starts") {
      await SubscribeSheetURLProtocol.stub.requestCount(
        method: "PUT", path: "/api/v1/subscribe/status/801") == 1
    }

    let accountB = subscriberToken(userID: 2, accessToken: "account-b")
    service.replaceSessionForTesting(
      baseURL: "http://subscribe-sheet-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    await SubscribeSheetURLProtocol.stub.release(path: "/api/v1/subscribe/status/801")
    await loadTask.value
    await viewModel.cancel()

    let deleteRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE", path: "/api/v1/subscribe/801")
    XCTAssertEqual(deleteRequestCount, 0)
  }

  func testLoadDataSkipsFilterGroupsForStandardUserWithSubscribePermission() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    service.tokenForTesting = "standard-user"
    service.currentUserForTesting = Token(
      access_token: "standard-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "standard",
      avatar: nil)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 780, name: "普通订阅账号", type: "电影", tmdbid: 123459),
      isNewSubscription: false
    )

    await viewModel.loadData()

    XCTAssertTrue(viewModel.filterGroups.isEmpty)
    let filterGroupsRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/system/setting/UserFilterRuleGroups")
    XCTAssertEqual(filterGroupsRequestCount, 0)
  }

  func testLoadDataLoadsFilterGroupsForSuperUserWithSubscribePermission() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSuperSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 783, name: "超管订阅账号", type: "电影", tmdbid: 123462),
      isNewSubscription: false
    )

    await viewModel.loadData()

    XCTAssertEqual(viewModel.filterGroups.map(\.name), ["普通规则组"])
    let filterGroupsRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/system/setting/UserFilterRuleGroups")
    XCTAssertEqual(filterGroupsRequestCount, 1)
  }

  func testLoadDataShowsOnlyActiveSites() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "GET",
      path: "/api/v1/site/rss",
      json:
        #"[{"id":1,"name":"启用站点","is_active":true},{"id":2,"name":"停用站点","is_active":false}]"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 780, name: "站点过滤", type: "电影", tmdbid: 123459)
    )
    await viewModel.loadData()

    XCTAssertEqual(viewModel.sites.map(\.name), ["启用站点"])
  }

  func testLoadDataForNewSubscriptionDoesNotForceUnsetBestVersionToZero() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(
        id: nil,
        name: "默认配置新订阅",
        type: "电视剧",
        season: 1,
        doubanid: "douban-new",
        mediaid: "douban:douban-new"
      ),
      isNewSubscription: true
    )

    await viewModel.loadData()

    var capturedBody = await SubscribeSheetURLProtocol.stub.requestBody(
      method: "POST",
      path: "/api/v1/subscribe/"
    )
    if capturedBody == nil {
      capturedBody = await SubscribeSheetURLProtocol.stub.requestBody(
        method: "POST",
        path: "/api/v1/subscribe"
      )
    }
    let body = try XCTUnwrap(capturedBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let postCountWithSlash = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "POST",
      path: "/api/v1/subscribe/"
    )
    let postCountWithoutSlash = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "POST",
      path: "/api/v1/subscribe"
    )
    XCTAssertEqual(postCountWithSlash + postCountWithoutSlash, 1)
    XCTAssertFalse(json.keys.contains("best_version"))
    XCTAssertFalse(json.keys.contains("best_version_full"))
    XCTAssertEqual(json["mediaid"] as? String, "douban:douban-new")
  }

  func testNewSubscriptionLoadStopsWhenPauseFails() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "PUT",
      path: "/api/v1/subscribe/status/801",
      json: #"{"success":false,"message":"暂停订阅失败"}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(name: "暂停失败", type: "电影", tmdbid: 8801),
      isNewSubscription: true
    )
    await viewModel.loadData()

    XCTAssertEqual(viewModel.subscribe.id, 801)
    XCTAssertEqual(viewModel.loadErrorMessage, "暂停订阅失败")
    let detailRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/801")
    let siteRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/site/rss")
    XCTAssertEqual(detailRequestCount, 0)
    XCTAssertEqual(siteRequestCount, 0)
  }

  func testPendingLoadDataDoesNotPublishOptionsAfterSubscribePermissionIsRestricted()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.suspend(path: "/api/v1/system/setting/UserFilterRuleGroups")
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSuperSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 782, name: "权限降级", type: "电影", tmdbid: 123461),
      isNewSubscription: false
    )

    let loadTask = Task { await viewModel.loadData() }
    try await waitUntil("filter groups request started") {
      await SubscribeSheetURLProtocol.stub.requestCount(
        method: "GET", path: "/api/v1/system/setting/UserFilterRuleGroups") == 1
    }

    configureNoSubscribeUser(service)
    await SubscribeSheetURLProtocol.stub.release(path: "/api/v1/system/setting/UserFilterRuleGroups")
    await loadTask.value

    XCTAssertTrue(viewModel.sites.isEmpty)
    XCTAssertTrue(viewModel.downloaders.isEmpty)
    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertTrue(viewModel.filterGroups.isEmpty)
  }

  func testSubscribeSheetLoadDoesNotRequestOptionsWithoutPermission() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureNoSubscribeUser(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 781, name: "无订阅权限", type: "电影", tmdbid: 123460),
      isNewSubscription: false
    )
    await viewModel.loadData()

    XCTAssertTrue(viewModel.sites.isEmpty)
    XCTAssertTrue(viewModel.downloaders.isEmpty)
    XCTAssertTrue(viewModel.directories.isEmpty)
    XCTAssertTrue(viewModel.filterGroups.isEmpty)

    let requestCount = await SubscribeSheetURLProtocol.stub.totalRequestCount()
    XCTAssertEqual(requestCount, 0)
  }

  func testSaveFailurePublishesErrorMessage() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.fail(path: "/api/v1/subscribe")
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 784, name: "保存失败", type: "电影", tmdbid: 123463),
      isNewSubscription: false
    )

    let didSave = await viewModel.save()

    XCTAssertFalse(didSave)
    XCTAssertFalse(viewModel.isSaved)
    XCTAssertEqual(viewModel.errorMessage, "暂时无法保存订阅，请稍后重试。")
  }

  func testSaveBusinessFailurePublishesBackendMessage() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "PUT",
      path: "/api/v1/subscribe",
      json: #"{"success":false,"message":"订阅参数冲突"}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 779, name: "保存业务失败", type: "电影", tmdbid: 123458)
    )

    let didSave = await viewModel.save()
    XCTAssertFalse(didSave)
    XCTAssertFalse(viewModel.isSaved)
    XCTAssertEqual(viewModel.errorMessage, "订阅参数冲突")
  }

  func testLoadDataFailurePublishesErrorMessage() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer {
      snapshot.restore(to: service)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.fail(path: "/api/v1/site/rss")
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 785, name: "配置失败", type: "电影", tmdbid: 123464),
      isNewSubscription: false
    )

    await viewModel.loadData()

    XCTAssertEqual(viewModel.loadErrorMessage, "订阅设置没有加载完整，请重试。")
    XCTAssertTrue(viewModel.canRetryLoad)
  }

  func testSavedSubscriptionIsNotRolledBackWhenResumeReturnsFalse() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.respond(
      method: "PUT",
      path: "/api/v1/subscribe/status/786",
      json: #"{"success":false}"#
    )
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 786, name: "启用失败", type: "电影", tmdbid: 123465),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()
    XCTAssertTrue(didSave)
    XCTAssertTrue(viewModel.isSaved)
    XCTAssertEqual(
      viewModel.errorMessage,
      "订阅已保存，但暂时未能启用。你可以稍后在订阅页面重试。"
    )
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/786")
    XCTAssertEqual(searchRequestCount, 0)

    await viewModel.cancel()

    let deleteRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE", path: "/api/v1/subscribe/786")
    XCTAssertEqual(deleteRequestCount, 0)
  }

  func testSavedSubscriptionIsNotRolledBackWhenSearchThrows() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscribeSheetURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscribeSheetURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    await SubscribeSheetURLProtocol.stub.fail(path: "/api/v1/subscribe/search/787")
    service.baseURLForTesting = "http://subscribe-sheet-tests.local"
    configureSubscriber(service)
    UserDefaults.standard.set(true, forKey: autoSearchKey)

    let notifications = SubscribeSheetNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 787, name: "搜索失败", type: "电影", tmdbid: 123466),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()
    XCTAssertTrue(didSave)
    XCTAssertTrue(viewModel.isSaved)
    XCTAssertEqual(
      viewModel.errorMessage,
      "订阅已保存，但没有开始搜索。你可以稍后手动搜索。"
    )
    XCTAssertEqual(notifications.count(), 1)

    await viewModel.cancel()

    let deleteRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "DELETE", path: "/api/v1/subscribe/787")
    XCTAssertEqual(deleteRequestCount, 0)
  }

  private func restoreUserDefaultsValue(_ value: Any?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(description)")
  }

  private func configureSubscriber(_ service: APIService) {
    service.tokenForTesting = "subscribe-sheet-user"
    service.currentUserForTesting = Token(
      access_token: "subscribe-sheet-user",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_id: 1,
      user_name: "subscribe-sheet",
      avatar: nil
    )
  }

  private func configureSuperSubscriber(_ service: APIService) {
    service.tokenForTesting = "subscribe-sheet-super-user"
    service.currentUserForTesting = Token(
      access_token: "subscribe-sheet-super-user",
      token_type: "Bearer",
      super_user: FlexibleBool(true),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "subscribe-sheet-admin",
      avatar: nil
    )
  }

  private func configureNoSubscribeUser(_ service: APIService) {
    service.tokenForTesting = "subscribe-sheet-no-subscribe"
    service.currentUserForTesting = Token(
      access_token: "subscribe-sheet-no-subscribe",
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "subscribe-sheet-no-subscribe",
      avatar: nil
    )
  }

  private func subscriberToken(userID: Int, accessToken: String) -> Token {
    Token(
      access_token: accessToken,
      token_type: "Bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.subscribe.rawValue: true],
      user_id: userID,
      user_name: "subscriber-\(userID)",
      avatar: nil
    )
  }
}

private final class SubscribeSheetNotificationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func count() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func increment() {
    lock.lock()
    defer { lock.unlock() }
    value += 1
  }
}

private struct SubscribeSheetServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SubscribeSheetServiceSnapshot {
    SubscribeSheetServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      useImageCache: service.useImageCache,
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.tokenForTesting = token
    service.currentUserForTesting = currentUser
    service.settings = settings
    service.useImageCache = useImageCache

    restoreDefaults(value: serverURLDefaults, forKey: "serverURL")
    restoreCredential(account: "accessToken", keychainValue: tokenKeychain, defaultsValue: tokenDefaults)
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
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

private actor SubscribeSheetURLProtocolStub {
  private var requestCounts: [String: Int] = [:]
  private var requestBodies: [String: Data] = [:]
  private var responseOverrides: [String: Data] = [:]
  private var suspendedPaths: Set<String> = []
  private var failedPaths: Set<String> = []
  private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

  func reset() {
    requestCounts.removeAll()
    requestBodies.removeAll()
    responseOverrides.removeAll()
    suspendedPaths.removeAll()
    failedPaths.removeAll()
    let pendingWaiters = waiters.values.flatMap { $0 }
    waiters.removeAll()
    pendingWaiters.forEach { $0.resume() }
  }

  func suspend(path: String) {
    suspendedPaths.insert(path)
  }

  func release(path: String) {
    suspendedPaths.remove(path)
    let pendingWaiters = waiters.removeValue(forKey: path) ?? []
    pendingWaiters.forEach { $0.resume() }
  }

  func fail(path: String) {
    failedPaths.insert(path)
  }

  func respond(method: String, path: String, json: String) {
    responseOverrides["\(method) \(path)"] = Data(json.utf8)
  }

  func requestCount(method: String, path: String) -> Int {
    requestCounts["\(method) \(path)", default: 0]
  }

  func totalRequestCount() -> Int {
    requestCounts.values.reduce(0, +)
  }

  func requestBody(method: String, path: String) -> Data? {
    requestBodies["\(method) \(path)"]
  }

  func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""
    requestCounts["\(method) \(path)", default: 0] += 1
    if let body = requestBodyData(from: request) {
      requestBodies["\(method) \(path)"] = body
    }
    if failedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
      throw APIError.serverMessage("请求失败")
    }
    if suspendedPaths.contains(path) {
      await withCheckedContinuation { continuation in
        waiters[path, default: []].append(continuation)
      }
    }

    let data: Data
    if let responseOverride = responseOverrides["\(method) \(path)"] {
      data = responseOverride
    } else {
      switch (method, path) {
      case ("GET", "/api/v1/site/rss"):
        data = #"[]"#.data(using: .utf8)!
      case ("GET", "/api/v1/download/clients"):
        data = #"[]"#.data(using: .utf8)!
      case ("GET", "/api/v1/system/setting/public/Directories"):
        data = #"{"value":[]}"#.data(using: .utf8)!
      case ("GET", "/api/v1/system/setting/UserFilterRuleGroups"):
        data = #"{"value":[{"name":"普通规则组"}]}"#.data(using: .utf8)!
      case ("GET", "/api/v1/subscribe/"), ("GET", "/api/v1/subscribe"):
        data = #"[]"#.data(using: .utf8)!
      case ("POST", "/api/v1/subscribe/"), ("POST", "/api/v1/subscribe"):
        data = #"{"success":true,"data":{"id":801}}"#.data(using: .utf8)!
      case ("GET", "/api/v1/subscribe/801"):
        data = #"{"id":801,"name":"默认配置新订阅","type":"电视剧","season":1,"doubanid":"douban-new","mediaid":"douban:douban-new","state":"S"}"#.data(using: .utf8)!
      case let (_, path) where path.hasPrefix("/api/v1/subscribe"):
        data = #"{"success":true}"#.data(using: .utf8)!
      default:
        throw URLError(.badServerResponse)
      }
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }

  private func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }

    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while true {
      let count = stream.read(buffer, maxLength: bufferSize)
      if count > 0 {
        data.append(buffer, count: count)
      } else {
        break
      }
    }
    return data.isEmpty ? nil : data
  }
}

private final class SubscribeSheetURLProtocol: URLProtocol {
  static let stub = SubscribeSheetURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscribe-sheet-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscribeSheetURLProtocolTaskContext(
      request: request,
      clientBox: SubscribeSheetURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SubscribeSheetURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscribeSheetURLProtocolTaskContext)
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

private final class SubscribeSheetURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscribeSheetURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscribeSheetURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscribeSheetURLProtocolClientBox: @unchecked Sendable {
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
