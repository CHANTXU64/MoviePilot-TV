import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSeasonContentViewTests: XCTestCase {
  func testHomeDeleteReturnsBusinessFailureWhenSubscriptionStillExists() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    await SubscriptionSnapshotURLProtocol.stub.setSubscriptionDeleteResponse(
      #"{"success":false,"message":"delete rejected"}"#
    )
    let subscription = Subscribe(id: 501, name: "取消失败", type: "电影")
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([subscription])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([subscription])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    let didDelete = try await viewModel.deleteSubscribe(subscribe: subscription)
    let deleteRequestCount =
      await SubscriptionSnapshotURLProtocol.stub.requestCount(path: "/api/v1/subscribe/501")
    let subscriptionRefreshCount =
      await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()

    XCTAssertFalse(didDelete)
    XCTAssertEqual(viewModel.movieSubscriptions.map(\.id), [501])
    XCTAssertEqual(deleteRequestCount, 1)
    XCTAssertEqual(subscriptionRefreshCount, 2)
  }

  func testHomeDeleteTreatsMissingSubscriptionAfterRefreshAsConverged() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    await SubscriptionSnapshotURLProtocol.stub.setSubscriptionDeleteResponse(
      #"{"success":false,"message":"already deleted"}"#
    )
    let subscription = Subscribe(id: 502, name: "远端已删除", type: "电影")
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([subscription])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let notifications = SubscribeSeasonNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    let didDelete = try await viewModel.deleteSubscribe(subscribe: subscription)

    XCTAssertTrue(didDelete)
    XCTAssertTrue(viewModel.movieSubscriptions.isEmpty)
    XCTAssertEqual(notifications.count(), 1)
    let deleteRequestCount =
      await SubscriptionSnapshotURLProtocol.stub.requestCount(path: "/api/v1/subscribe/502")
    let subscriptionRefreshCount =
      await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(deleteRequestCount, 1)
    XCTAssertGreaterThanOrEqual(subscriptionRefreshCount, 2)
  }

  func testHomeSubscriptionRefreshCanBypassCachedSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 101, name: "航海王", type: "电视剧", season: 1, tmdbid: 12345)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [101])

    await viewModel.refreshSubscriptions()
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [101])

    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions, [])
  }

  func testHomeSubscriptionUpdateNotificationBypassesCachedSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 102, name: "航海王", type: "电视剧", season: 1, tmdbid: 12345)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = HomeViewModel(apiService: service)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [102])

    NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    try await waitUntil(timeout: 2) {
      viewModel.tvSubscriptions.isEmpty
    }
  }

  func testHomeSubscriptionRefreshIgnoresStaleSnapshotReturnedAfterMutation() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleGate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(
      [Subscribe(id: 301, name: "旧订阅", type: "电视剧", season: 1, tmdbid: 811001)],
      waitFor: staleGate
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 302, name: "新订阅", type: "电视剧", season: 2, tmdbid: 811001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = HomeViewModel(apiService: service)
    let staleRefresh = Task {
      await viewModel.refreshSubscriptions(forceRefresh: true)
    }
    await staleGate.waitForWaiter()

    _ = try await service.deleteSubscription(id: 301)
    await viewModel.refreshSubscriptions(forceRefresh: true)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [302])

    await staleGate.open()
    _ = await staleRefresh.value

    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [302])
  }

  func testSeasonSubscriptionStatusIgnoresStaleSnapshotReturnedAfterMutation() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleGate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(
      [Subscribe(id: 401, name: "旧分季", type: "电视剧", season: 1, tmdbid: 812001)],
      waitFor: staleGate
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 402, name: "新分季", type: "电视剧", season: 2, tmdbid: 812001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 812001, title: "分季状态", type: "电视剧"),
      apiService: service
    )
    let staleRefresh = Task {
      await viewModel.checkSubscriptionStatus(forceRefresh: true)
    }
    await staleGate.waitForWaiter()

    _ = try await service.deleteSubscription(id: 401)
    await viewModel.checkSubscriptionStatus(forceRefresh: true)
    XCTAssertEqual(viewModel.subscribedSeasons, [2])

    await staleGate.open()
    await staleRefresh.value

    XCTAssertEqual(viewModel.subscribedSeasons, [2])
    XCTAssertEqual(viewModel.seasonSubscriptions[2]?.id, 402)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testChangingCurrentUserClearsCachedSubscriptionSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 601, name: "旧账号订阅", type: "电视剧", season: 1, tmdbid: 814001)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 602, name: "新账号订阅", type: "电视剧", season: 2, tmdbid: 814001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "first-user")

    let cachedSubscriptions = try await service.fetchSubscriptions(forceRefresh: true)
    XCTAssertEqual(cachedSubscriptions.map(\.id), [601])

    configureSubscriptionSnapshotAccess(service, userName: "second-user")
    let refreshedSubscriptions = try await service.fetchSubscriptions()

    XCTAssertEqual(refreshedSubscriptions.map(\.id), [602])
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testSearchSubscriptionClearsCachedSubscriptionSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 901, name: "搜索前订阅", type: "电视剧", season: 1, tmdbid: 817001)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 902, name: "搜索后订阅", type: "电视剧", season: 2, tmdbid: 817001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let notifications = SubscribeSeasonNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let cachedSubscriptions = try await service.fetchSubscriptions(forceRefresh: true)
    XCTAssertEqual(cachedSubscriptions.map(\.id), [901])

    let searchSuccess = try await service.searchSubscription(id: 901)
    XCTAssertTrue(searchSuccess)
    XCTAssertEqual(notifications.count(), 0)
    let subscriptions = try await service.fetchSubscriptions()

    XCTAssertEqual(subscriptions.map(\.id), [902])
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testHomeSearchRefreshesItsListAndPublishesOneSubscriptionUpdate() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let refreshedSubscriptions = [
      Subscribe(id: 902, name: "搜索后订阅", type: "电视剧", season: 2, tmdbid: 817_001)
    ]
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(refreshedSubscriptions)
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions(refreshedSubscriptions)
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let notifications = SubscribeSeasonNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = HomeViewModel(apiService: service)
    let success = try await viewModel.searchSubscribe(
      subscribe: Subscribe(id: 901, name: "搜索前订阅", type: "电视剧")
    )

    XCTAssertTrue(success)
    XCTAssertEqual(viewModel.tvSubscriptions.map(\.id), [902])
    XCTAssertEqual(notifications.count(), 1)
    let searchRequestCount = await SubscriptionSnapshotURLProtocol.stub.requestCount(
      path: "/api/v1/subscribe/search/901")
    XCTAssertEqual(searchRequestCount, 1)
    await SubscriptionSnapshotURLProtocol.stub.waitForSubscribeRequestCount(2)
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testHomeStatusAndResetEachPublishOneSubscriptionUpdate() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let subscriptions = [
      Subscribe(id: 903, name: "状态订阅", type: "电视剧", season: 1, state: "R", tmdbid: 817_002)
    ]
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions(subscriptions)
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let notifications = SubscribeSeasonNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = HomeViewModel(apiService: service)
    let statusResult = try await viewModel.toggleSubscribeStatus(subscribe: subscriptions[0])
    XCTAssertTrue(statusResult.success)
    XCTAssertEqual(notifications.count(), 1)
    await SubscriptionSnapshotURLProtocol.stub.waitForSubscribeRequestCount(2)
    let statusRefreshCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(statusRefreshCount, 2)

    let resetResult = try await viewModel.resetSubscribe(subscribe: subscriptions[0])
    XCTAssertTrue(resetResult.success)
    XCTAssertEqual(notifications.count(), 2)
    await SubscriptionSnapshotURLProtocol.stub.waitForSubscribeRequestCount(4)
    let resetRefreshCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(resetRefreshCount, 4)
  }

  func testConcurrentForcedSubscriptionRefreshStartsNewSnapshotRequest() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(
      [Subscribe(id: 701, name: "旧强刷", type: "电视剧", season: 1, tmdbid: 815001)],
      waitFor: gate
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 702, name: "新强刷", type: "电视剧", season: 2, tmdbid: 815001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let firstRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    await gate.waitForWaiter()

    let secondRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    let secondSubscriptions = try await secondRefresh.value
    await gate.open()

    let firstSubscriptions = try await firstRefresh.value

    XCTAssertEqual(firstSubscriptions.map(\.id), [702])
    XCTAssertEqual(secondSubscriptions.map(\.id), [702])
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testForcedSubscriptionRefreshDoesNotReuseInFlightSnapshotAfterOutOfBandRemoteChange()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleGate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(
      [Subscribe(id: 704, name: "远端完成前", type: "电视剧", season: 1, tmdbid: 815003)],
      waitFor: staleGate
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let staleRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    await staleGate.waitForWaiter()

    let latestRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    await Task.yield()
    await staleGate.open()

    let staleSubscriptions = try await staleRefresh.value
    let latestSubscriptions = try await latestRefresh.value

    XCTAssertEqual(staleSubscriptions.map(\.id), [])
    XCTAssertEqual(latestSubscriptions.map(\.id), [])
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testOlderForcedSubscriptionRefreshErrorDoesNotOverrideNewerSnapshot()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleErrorGate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueServerError(waitFor: staleErrorGate)
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let staleRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    await staleErrorGate.waitForWaiter()

    let latestRefresh = Task {
      try await service.fetchSubscriptions(forceRefresh: true)
    }
    let latestSubscriptions = try await latestRefresh.value
    await staleErrorGate.open()

    let staleSubscriptions = try await staleRefresh.value

    XCTAssertEqual(staleSubscriptions.map(\.id), [])
    XCTAssertEqual(latestSubscriptions.map(\.id), [])
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testLatestForcedSubscriptionRefreshPropagatesErrorWithoutRetry() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueServerError()
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    do {
      _ = try await service.fetchSubscriptions(forceRefresh: true)
      XCTFail("The latest subscription snapshot failure must reach the caller.")
    } catch is CancellationError {
      XCTFail("A server failure must not be converted into cancellation.")
    } catch {
      // Expected.
    }

    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 1)
  }

  func testSharedSubscriptionSnapshotFailureReachesAllWaitersWithoutRetry() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let responseGate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueServerError(waitFor: responseGate)
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let firstWaiter = Task {
      do {
        _ = try await service.fetchSubscriptions()
        return false
      } catch {
        return !(error is CancellationError)
      }
    }
    await responseGate.waitForWaiter()

    let secondWaiter = Task {
      do {
        _ = try await service.fetchSubscriptions()
        return false
      } catch {
        return !(error is CancellationError)
      }
    }
    await Task.yield()
    await responseGate.open()

    let firstFailed = await firstWaiter.value
    let secondFailed = await secondWaiter.value
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()

    XCTAssertTrue(firstFailed)
    XCTAssertTrue(secondFailed)
    XCTAssertEqual(subscribeRequestCount, 1)
  }

  func testMultiSeasonDetailCanRefreshAfterSeasonSubscriptionFailure() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueServerError()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 901, name: "分季刷新重试", type: "电视剧", season: 1, tmdbid: 817_001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let detail = MediaInfo(tmdb_id: 817_001, title: "分季刷新重试", type: "电视剧")
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.fullDetail = detail

    let viewModel = MediaDetailViewModel(
      detail: MediaInfo(title: "占位详情", type: "电视剧"),
      apiService: service
    )
    viewModel.preloadTask = preloadTask

    let refreshedBeforeSeasonData = await MediaDetailView.applyReadyPreloadedDetail(
      from: preloadTask,
      to: viewModel,
      hasRefreshedSubscription: false
    )
    XCTAssertFalse(refreshedBeforeSeasonData)
    let requestCountBeforeSeasonData =
      await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(requestCountBeforeSeasonData, 0)

    preloadTask.seasonViewModel = SubscribeSeasonViewModel(
      mediaInfo: detail,
      apiService: service
    )
    let firstSeasonRefresh = await viewModel.refreshSubscriptionStatus()
    let secondSeasonRefresh = await viewModel.refreshSubscriptionStatus()

    XCTAssertFalse(firstSeasonRefresh)
    XCTAssertTrue(secondSeasonRefresh)
    XCTAssertEqual(preloadTask.seasonViewModel?.subscribedSeasons, Set([1]))
    let requestCountAfterSeasonRefreshes =
      await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(requestCountAfterSeasonRefreshes, 2)
  }

  func testInitialEpisodeGroupSeedsSeasonSelection() {
    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 817_002, title: "剧集组导航", type: "电视剧"),
      initialEpisodeGroup: "group-a"
    )

    XCTAssertEqual(viewModel.selectedGroupId, "group-a")
  }

  func testAniListPrimaryIdentityRejectsAuxiliaryTMDBEpisodeGroup() throws {
    let media = MediaInfo(
      tmdb_id: 817_002,
      anilist_id: 154_587,
      source: "anilist",
      mediaid_prefix: "anilist",
      media_id: "154587",
      title: "葬送的芙莉莲",
      type: "电视剧"
    )
    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: media,
      initialEpisodeGroup: "group-a"
    )

    XCTAssertEqual(media.identity?.source, "anilist")
    XCTAssertEqual(viewModel.selectedGroupId, "")
    viewModel.selectedGroupId = "group-b"
    viewModel.prepareSubscription(seasonNumber: 1)
    XCTAssertNil(viewModel.sheetSubscribe?.episode_group)
    XCTAssertEqual(try viewModel.seasonAvailabilityMedia().episode_group, "")
  }

  func testEpisodeGroupFailureDoesNotBlockSeasonManagementData() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    await SubscriptionSnapshotURLProtocol.stub.setEpisodeGroupsStatusCode(500)
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "episode-group-failure")

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(
        tmdb_id: 987_654,
        source: "themoviedb",
        media_id: "987654",
        title: "剧集组失败",
        type: "电视剧"
      ),
      apiService: service
    )

    await viewModel.loadSeasonManagementData()

    XCTAssertFalse(viewModel.hasSeasonLoadError)
    XCTAssertFalse(viewModel.seasonInfos.isEmpty)
    XCTAssertTrue(viewModel.episodeGroups.isEmpty)
  }

  func testSeasonManagementLoadStopsAfterAccountSwitchDuringEpisodeGroups() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setEpisodeGroupsGate(gate)
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "season-account-a", userId: 1)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 987_655, title: "分季切号", type: "电视剧"),
      apiService: service
    )
    let loadTask = Task { @MainActor in await viewModel.loadSeasonManagementData() }
    await gate.waitForWaiter()

    configureSubscriptionSnapshotAccess(service, userName: "season-account-b", userId: 2)
    await gate.open()
    await loadTask.value

    let seasonsRequestCount = await SubscriptionSnapshotURLProtocol.stub.requestCount(
      path: "/api/v1/media/seasons"
    )
    let availabilityRequestCount = await SubscriptionSnapshotURLProtocol.stub.requestCount(
      path: "/api/v1/mediaserver/notexists"
    )
    XCTAssertEqual(seasonsRequestCount, 0)
    XCTAssertEqual(availabilityRequestCount, 0)
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 0)
    XCTAssertFalse(viewModel.hasSeasonLoadError)
  }

  func testSeasonAvailabilityKeepsLoadedStateWhenSameAccountTokenRefreshCancelsRequest()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setSeasonAvailabilityGate(gate)
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "season-account", userId: 1)
    let originalUIIdentity = service.uiIdentity

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 987_657, title: "分季凭据刷新", type: "电视剧"),
      apiService: service
    )
    viewModel.seasonsNotExisted = [1: 0]
    viewModel.isSeasonAvailabilityLoaded = true
    let loadTask = Task { @MainActor in await viewModel.checkSeasonsStatus() }
    await gate.waitForWaiter()

    let refreshedUser = subscriptionSnapshotToken(
      userName: "season-account",
      userId: 1,
      accessToken: "subscription-snapshot-token-refreshed"
    )
    service.replaceSessionForTesting(
      baseURL: service.baseURL,
      token: refreshedUser.access_token,
      currentUser: refreshedUser
    )
    XCTAssertEqual(service.uiIdentity, originalUIIdentity)
    await gate.open()
    await loadTask.value

    XCTAssertTrue(viewModel.isSeasonAvailabilityLoaded)
    XCTAssertEqual(viewModel.seasonsNotExisted[1], 0)
  }

  func testSeasonLoadKeepsLoadedAvailabilityWhenSameAccountTokenRefreshCancelsRequest()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setSeasonAvailabilityGate(gate)
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "season-load-account", userId: 1)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(
        tmdb_id: 987_660,
        title: "完整分季凭据刷新",
        type: "电视剧",
        season_info: [try makeSeason(number: 0)]
      ),
      apiService: service
    )
    viewModel.seasonsNotExisted = [1: 0]
    viewModel.isSeasonAvailabilityLoaded = true
    let loadTask = Task { @MainActor in
      await viewModel.fetchSeasons()
    }
    await gate.waitForWaiter()

    let refreshedUser = subscriptionSnapshotToken(
      userName: "season-load-account",
      userId: 1,
      accessToken: "season-load-token-refreshed"
    )
    service.replaceSessionForTesting(
      baseURL: service.baseURL,
      token: refreshedUser.access_token,
      currentUser: refreshedUser
    )
    await gate.open()
    await loadTask.value

    XCTAssertTrue(viewModel.isSeasonAvailabilityLoaded)
    XCTAssertEqual(viewModel.seasonsNotExisted[1], 0)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testSeasonLoadClearsLoadedAvailabilityWhenAccountChanges() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setSeasonAvailabilityGate(gate)
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "old-account", userId: 1)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(
        tmdb_id: 987_661,
        title: "分季切换账号",
        type: "电视剧",
        season_info: [try makeSeason(number: 0)]
      ),
      apiService: service
    )
    viewModel.seasonsNotExisted = [1: 0]
    viewModel.isSeasonAvailabilityLoaded = true
    let loadTask = Task { @MainActor in
      await viewModel.fetchSeasons()
    }
    await gate.waitForWaiter()

    let newUser = subscriptionSnapshotToken(
      userName: "new-account",
      userId: 2,
      accessToken: "new-account-token"
    )
    service.replaceSessionForTesting(
      baseURL: service.baseURL,
      token: newUser.access_token,
      currentUser: newUser
    )
    await gate.open()
    await loadTask.value

    XCTAssertFalse(viewModel.isSeasonAvailabilityLoaded)
    XCTAssertTrue(viewModel.seasonsNotExisted.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testChangingEpisodeGroupPreventsOlderSeasonLoadFromOverwritingNewSelection()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleGate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setGroupSeasons(
      groupId: "group-a",
      seasonNumber: 1,
      waitFor: staleGate
    )
    await SubscriptionSnapshotURLProtocol.stub.setGroupSeasons(
      groupId: "group-b",
      seasonNumber: 2
    )
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 987_658, title: "剧集组切换", type: "电视剧"),
      apiService: service
    )
    viewModel.selectedGroupId = "group-a"
    let staleLoad = Task { @MainActor in
      await viewModel.fetchSeasons()
    }
    await staleGate.waitForWaiter()

    viewModel.selectedGroupId = "group-b"
    await viewModel.fetchSeasons()

    let availabilityCountAfterCurrentLoad =
      await SubscriptionSnapshotURLProtocol.stub.requestCount(
        path: "/api/v1/mediaserver/notexists"
      )
    XCTAssertEqual(viewModel.seasonInfos.map(\.season_number), [2])
    XCTAssertEqual(availabilityCountAfterCurrentLoad, 1)

    await staleGate.open()
    await staleLoad.value

    let finalAvailabilityCount = await SubscriptionSnapshotURLProtocol.stub.requestCount(
      path: "/api/v1/mediaserver/notexists"
    )
    XCTAssertEqual(viewModel.seasonInfos.map(\.season_number), [2])
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertFalse(viewModel.hasSeasonLoadError)
    XCTAssertEqual(finalAvailabilityCount, 1)
  }

  func testChangingEpisodeGroupPreventsOlderSubscriptionRefreshFromPublishing()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let staleGate = SubscriptionSnapshotAsyncGate()
    await SubscriptionSnapshotURLProtocol.stub.setGroupSeasons(
      groupId: "group-a",
      seasonNumber: 1
    )
    await SubscriptionSnapshotURLProtocol.stub.setGroupSeasons(
      groupId: "group-b",
      seasonNumber: 2
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions(
      [Subscribe(id: 801, name: "旧剧集组", type: "电视剧", season: 1, tmdbid: 987_659)],
      waitFor: staleGate
    )
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 802, name: "新剧集组", type: "电视剧", season: 2, tmdbid: 987_659)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 987_659, title: "订阅阶段切组", type: "电视剧"),
      apiService: service
    )
    viewModel.selectedGroupId = "group-a"
    let staleLoad = Task { @MainActor in
      await viewModel.loadData(forceRefreshSubscriptions: true)
    }
    await staleGate.waitForWaiter()

    viewModel.selectedGroupId = "group-b"
    await viewModel.retryLoadData(forceRefreshSubscriptions: true)

    XCTAssertEqual(viewModel.seasonInfos.map(\.season_number), [2])
    XCTAssertEqual(viewModel.subscribedSeasons, [2])
    XCTAssertEqual(viewModel.seasonSubscriptions[2]?.id, 802)

    await staleGate.open()
    await staleLoad.value

    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
    XCTAssertEqual(viewModel.seasonInfos.map(\.season_number), [2])
    XCTAssertEqual(viewModel.subscribedSeasons, [2])
    XCTAssertEqual(viewModel.seasonSubscriptions[2]?.id, 802)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testSubscriptionNotificationRefreshStopsWhenAccountChanges() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    await SubscriptionSnapshotURLProtocol.stub.reset()
    let gate = SubscriptionSnapshotAsyncGate()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([], waitFor: gate)
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service, userName: "preloader-account-a", userId: 1)

    let preloader = MediaPreloader(apiService: service)
    defer { preloader.clearAll() }
    let media = MediaInfo(
      tmdb_id: 987_656,
      title: "通知切号",
      type: "电视剧",
      collection_id: 987_656
    )
    let preloadTask = preloader.preload(for: media)
    preloadTask.seasonViewModel = SubscribeSeasonViewModel(mediaInfo: media, apiService: service)
    preloader.pin(key: media.id)

    NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    await gate.waitForWaiter()
    configureSubscriptionSnapshotAccess(service, userName: "preloader-account-b", userId: 2)
    await gate.open()
    try await Task.sleep(nanoseconds: 50_000_000)

    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 1)
  }

  func testPreloadedSeasonDataReusesCachedSubscriptionSnapshot() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let preloader = MediaPreloader(apiService: service)
    preloader.clearAll()
    defer { preloader.clearAll() }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.setDefaultSubscriptions([
      Subscribe(id: 201, name: "预加载剧集", type: "电视剧", season: 1, tmdbid: 810001)
    ])
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let firstTask = preloader.preload(
      for: MediaInfo(tmdb_id: 810001, title: "预加载剧集 A", type: "电视剧"))
    try await waitUntil {
      firstTask.isSeasonDataLoaded
    }
    let firstSubscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(firstSubscribeRequestCount, 1)

    let secondTask = preloader.preload(
      for: MediaInfo(tmdb_id: 810002, title: "预加载剧集 B", type: "电视剧"))
    try await waitUntil {
      secondTask.isSeasonDataLoaded
    }

    let secondSubscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(secondSubscribeRequestCount, 1)
  }

  func testSeasonSubscriptionSummaryIndexesMatchingMediaBySeason() {
    let media = MediaInfo(tmdb_id: 12345, type: "电视剧")
    let subscriptions = [
      Subscribe(
        id: 11,
        name: "Target",
        type: "电视剧",
        season: 1,
        tmdbid: 12345,
        episode_group: "group-a"
      ),
      Subscribe(id: 12, name: "Other Season", type: "电视剧", season: 2, tmdbid: 12345),
      Subscribe(id: 13, name: "Other Media", type: "电视剧", season: 3, tmdbid: 54321, episode_group: "group-b"),
      Subscribe(id: 14, name: "Movie", type: "电影", season: 4, tmdbid: 12345),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 11)
    XCTAssertEqual(summaries[1]?.episodeGroup, "group-a")
    XCTAssertEqual(summaries[2]?.id, 12)
    XCTAssertNil(summaries[3])
    XCTAssertNil(summaries[4])
  }

  func testSeasonSubscriptionSummaryUsesWebIdentityFallbackOrder() {
    let media = MediaInfo(
      tmdb_id: 12_345,
      douban_id: "douban-target",
      bangumi_id: 13_579,
      anilist_id: 24_680,
      mediaid_prefix: "douban",
      media_id: "douban-target",
      type: "电视剧"
    )
    let subscriptions = [
      Subscribe(id: 15, name: "Raw TMDB", type: "电视剧", season: 1, tmdbid: 12_345),
      Subscribe(
        id: 16,
        name: "Canonical mismatch",
        type: "电视剧",
        season: 2,
        tmdbid: 12_345,
        media_source: "douban",
        media_id: "douban-other"
      ),
      Subscribe(
        id: 17,
        name: "Legacy mismatch",
        type: "电视剧",
        season: 3,
        tmdbid: 12_345,
        mediaid: "tmdb:54321"
      ),
      Subscribe(
        id: 18,
        name: "Earlier raw mismatch",
        type: "电视剧",
        season: 4,
        tmdbid: 54_321,
        doubanid: "douban-target"
      ),
      Subscribe(
        id: 19,
        name: "Raw AniList",
        type: "电视剧",
        season: 5,
        anilistid: 24_680
      ),
      Subscribe(
        id: 20,
        name: "Canonical match",
        type: "电视剧",
        season: 6,
        media_source: "douban",
        media_id: "douban-target"
      ),
      Subscribe(
        id: 21,
        name: "Raw Douban",
        type: "电视剧",
        season: 7,
        doubanid: "douban-target"
      ),
      Subscribe(
        id: 22,
        name: "Raw Bangumi",
        type: "电视剧",
        season: 8,
        bangumiid: 13_579
      ),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 15)
    XCTAssertNil(summaries[2])
    XCTAssertNil(summaries[3])
    XCTAssertNil(summaries[4])
    XCTAssertEqual(summaries[5]?.id, 19)
    XCTAssertEqual(summaries[6]?.id, 20)
    XCTAssertEqual(summaries[7]?.id, 21)
    XCTAssertEqual(summaries[8]?.id, 22)
  }

  func testSeasonSubscriptionSummaryDisplaysRealEpisodeGroup() throws {
    let groups = [try makeEpisodeGroup(id: "group-a", name: "司法岛篇")]
    let defaultSummary = SeasonSubscriptionSummary(id: 1, season: 1, episodeGroup: nil)
    let namedSummary = SeasonSubscriptionSummary(id: 2, season: 2, episodeGroup: "group-a")
    let unknownSummary = SeasonSubscriptionSummary(id: 3, season: 3, episodeGroup: "group-x")

    XCTAssertEqual(defaultSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 默认剧集组")
    XCTAssertEqual(namedSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 司法岛篇")
    XCTAssertEqual(unknownSummary.statusDisplayText(episodeGroups: groups), "已订阅 · 剧集组：group-x")
  }

  func testSeasonSubscriptionSummaryTreatsEpisodeGroupAsConfigurationNotIdentity() {
    let media = MediaInfo(tmdb_id: 12345, type: "电视剧", episode_group: "group-b")
    let subscriptions = [
      Subscribe(id: 21, name: "Target", type: "电视剧", season: 1, tmdbid: 12345, episode_group: "group-a")
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 21)
    XCTAssertEqual(summaries[1]?.episodeGroup, "group-a")
  }

  func testSeasonSubscriptionSummaryMatchesMediaIdFallbackFromBackendSnapshot() {
    let media = MediaInfo(mediaid_prefix: "tmdb", media_id: "12345", type: "电视剧")
    let subscriptions = [
      Subscribe(id: 31, name: "Target", type: "电视剧", season: 1, mediaid: "tmdb:12345"),
      Subscribe(id: 32, name: "Other", type: "电视剧", season: 1, mediaid: "douban:12345"),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 31)
  }

  func testSeasonSubscriptionSummaryFallsBackToMediaIdWhenSnapshotIdentifiersAreInvalid() {
    let media = MediaInfo(mediaid_prefix: "tmdb", media_id: "12345", type: "电视剧")
    let subscriptions = [
      Subscribe(id: 33, name: "Zero TMDB", type: "电视剧", season: 1, tmdbid: 0, mediaid: "tmdb:12345"),
      Subscribe(id: 34, name: "Zero Bangumi", type: "电视剧", season: 2, bangumiid: 0, mediaid: "tmdb:12345"),
      Subscribe(id: 35, name: "Blank Douban", type: "电视剧", season: 3, doubanid: "  ", mediaid: "tmdb:12345"),
      Subscribe(id: 36, name: "Invalid Fallback", type: "电视剧", season: 4, tmdbid: 0, mediaid: "tmdb:0"),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 33)
    XCTAssertEqual(summaries[2]?.id, 34)
    XCTAssertEqual(summaries[3]?.id, 35)
    XCTAssertNil(summaries[4])
  }

  func testSeasonSubscriptionSummaryFallsBackToMediaIdWhenMediaIdentifiersAreInvalid() {
    let media = MediaInfo(
      tmdb_id: 0,
      douban_id: "  ",
      bangumi_id: 0,
      mediaid_prefix: "tmdb",
      media_id: "12345",
      type: "电视剧"
    )
    let subscriptions = [
      Subscribe(id: 37, name: "Target", type: "电视剧", season: 1, mediaid: "tmdb:12345")
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries[1]?.id, 37)
  }

  func testSubscribeApiMediaIdFallsBackWhenPrimaryIdentifiersAreInvalid() {
    let subscribe = Subscribe(
      id: 38,
      name: "Target",
      type: "电视剧",
      season: 1,
      tmdbid: 0,
      doubanid: "  ",
      bangumiid: 0,
      mediaid: "tmdb:12345"
    )

    XCTAssertEqual(subscribe.apiMediaId, "tmdb:12345")
  }

  func testSubscribeApiMediaIdKeepsOpaqueLegacyIdentifiersLikeWeb() {
    let mediaIds = ["tmdb:-1", "tmdb:abc", "bangumi:-1", "bangumi:abc"]

    for (offset, mediaId) in mediaIds.enumerated() {
      let subscribe = Subscribe(
        id: 90 + offset,
        name: "Invalid",
        type: "电视剧",
        season: 1,
        mediaid: mediaId
      )

      XCTAssertEqual(subscribe.apiMediaId, mediaId)
    }
  }

  func testSubscribeNavigationMediaInfoPreservesFallbackMediaIdWhenPrimaryIdentifiersAreInvalid() {
    let subscribe = Subscribe(
      id: 39,
      name: "Target",
      year: "2024",
      type: "电视剧",
      season: 1,
      tmdbid: 0,
      doubanid: "  ",
      bangumiid: 0,
      episode_group: "group-a",
      description: "简介",
      mediaid: "tmdb:12345"
    )

    let media = subscribe.navigationMediaInfo()

    XCTAssertEqual(media.apiMediaId, "tmdb:12345")
    XCTAssertEqual(media.title, "Target")
    XCTAssertEqual(media.year, "2024")
    XCTAssertEqual(media.season, 1)
    XCTAssertEqual(media.episode_group, "group-a")
    XCTAssertEqual(media.overview, "简介")
  }

  func testSeasonSubscriptionSummaryMatchesLegacyZeroButSkipsRawZeroIdentifiers() {
    let media = MediaInfo(
      tmdb_id: 0,
      douban_id: "  ",
      bangumi_id: 0,
      mediaid_prefix: "tmdb",
      media_id: "0",
      type: "电视剧"
    )
    let subscriptions = [
      Subscribe(id: 41, name: "Zero TMDB", type: "电视剧", season: 1, tmdbid: 0),
      Subscribe(id: 42, name: "Blank Douban", type: "电视剧", season: 2, doubanid: ""),
      Subscribe(id: 43, name: "Zero Bangumi", type: "电视剧", season: 3, bangumiid: 0),
      Subscribe(id: 44, name: "Empty MediaID", type: "电视剧", season: 4, mediaid: "tmdb:0"),
    ]

    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: subscriptions,
      matching: media
    )

    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries[4]?.id, 44)
  }

  func testSeasonSubscriptionSummaryKeepsNegativeRawIdentifiersLikeWeb() {
    let summaries = SeasonSubscriptionSummary.indexBySeason(
      from: [
        Subscribe(id: 45, name: "Negative TMDB", type: "电视剧", season: 1, tmdbid: -1)
      ],
      matching: MediaInfo(tmdb_id: -1, type: "电视剧")
    )

    XCTAssertEqual(summaries[1]?.id, 45)
  }

  func testSeasonSubscriptionSummaryTreatsBlankEpisodeGroupAsDefault() {
    let summary = SeasonSubscriptionSummary(id: 51, season: 1, episodeGroup: "  \n ")

    XCTAssertNil(summary.episodeGroup)
    XCTAssertEqual(summary.statusDisplayText(episodeGroups: []), "已订阅 · 默认剧集组")
  }

  func testUnsubscribeConfirmationMessageUsesCurrentSubscriptionGroup() throws {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.episodeGroups = [try makeEpisodeGroup(id: "group-a", name: "司法岛篇")]
    viewModel.seasonSubscriptions = [
      3: SeasonSubscriptionSummary(id: 61, season: 3, episodeGroup: "group-a")
    ]

    XCTAssertEqual(
      viewModel.unsubscribeConfirmationMessage(for: 3),
      "是否取消《航海王》第 3 季订阅？\n当前订阅使用：司法岛篇"
    )
  }

  func testSingleSeasonUnsubscribeKeepsBusinessFailureMessage() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 61, name: "航海王", type: "电视剧", season: 3, tmdbid: 12_345)
    ])
    await SubscriptionSnapshotURLProtocol.stub.setMediaDeleteResponse(
      #"{"success":false,"message":"该季订阅正在处理"}"#
    )
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 12_345, title: "航海王", type: "电视剧"),
      apiService: service
    )
    viewModel.seasonSubscriptions = [
      3: SeasonSubscriptionSummary(id: 61, season: 3, episodeGroup: nil)
    ]
    viewModel.subscribedSeasons = [3]

    await viewModel.unsubscribeSeason(3)

    XCTAssertEqual(viewModel.errorMessage, "该季订阅正在处理")
    XCTAssertNotNil(viewModel.seasonSubscriptions[3])
    XCTAssertTrue(viewModel.subscribedSeasons.contains(3))
  }

  func testSingleSeasonDeletePublishesBeforeFollowUpRefreshFails() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SubscriptionSnapshotURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = SubscriptionSnapshotServiceSnapshot.capture(service: service)
    let preloader = MediaPreloader.shared
    preloader.clearAll()
    defer {
      preloader.clearAll()
      snapshot.restore(to: service)
    }

    await SubscriptionSnapshotURLProtocol.stub.reset()
    try await SubscriptionSnapshotURLProtocol.stub.enqueueSubscriptions([
      Subscribe(id: 62, name: "航海王", type: "电视剧", season: 3, tmdbid: 12_345)
    ])
    try await SubscriptionSnapshotURLProtocol.stub.enqueueServerError()
    await SubscriptionSnapshotURLProtocol.stub.setMediaDeleteResponse(
      #"{"success":true}"#
    )
    service.baseURLForTesting = "http://subscription-snapshot-tests.local"
    configureSubscriptionSnapshotAccess(service)

    let notifications = SubscribeSeasonNotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .subscriptionDidUpdate,
      object: nil,
      queue: nil
    ) { _ in
      notifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 12_345, title: "航海王", type: "电视剧"),
      apiService: service
    )
    viewModel.seasonSubscriptions = [
      3: SeasonSubscriptionSummary(id: 62, season: 3, episodeGroup: nil)
    ]
    viewModel.subscribedSeasons = [3]

    await viewModel.unsubscribeSeason(3)

    XCTAssertEqual(notifications.count(), 1)
    XCTAssertNotNil(viewModel.errorMessage)
    let subscribeRequestCount = await SubscriptionSnapshotURLProtocol.stub.subscribeRequestCount()
    XCTAssertEqual(subscribeRequestCount, 2)
  }

  func testHomeSubscriptionUnsubscribeConfirmationUsesSubscribeEpisodeGroup() {
    let subscribe = Subscribe(
      id: 81,
      name: "葬送的芙莉莲",
      type: "电视剧",
      season: 1,
      episode_group: "group-a"
    )

    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(for: subscribe),
      "是否取消《葬送的芙莉莲》第 1 季订阅？\n当前订阅使用：剧集组：group-a"
    )
  }

  func testHomeSubscriptionUnsubscribeConfirmationUsesDefaultEpisodeGroup() {
    let subscribe = Subscribe(
      id: 82,
      name: "迷宫饭",
      type: "电视剧",
      season: 1
    )

    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(for: subscribe),
      "是否取消《迷宫饭》第 1 季订阅？\n当前订阅使用：默认剧集组"
    )
  }

  func testUnsubscribeConfirmationMessageUsesSpecialsNameForSeasonZero() {
    XCTAssertEqual(
      SubscriptionCancelConfirmation.message(
        title: "夏日重现",
        season: 0,
        episodeGroupText: "默认剧集组"
      ),
      "是否取消《夏日重现》特别篇订阅？\n当前订阅使用：默认剧集组"
    )
  }

  func testPrepareSubscriptionUsesSelectedPickerGroupForNewSubscriptionOnly() {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.selectedGroupId = "group-a"
    viewModel.seasonSubscriptions = [
      1: SeasonSubscriptionSummary(id: 71, season: 1, episodeGroup: "group-b")
    ]

    viewModel.prepareSubscription(seasonNumber: 2)

    XCTAssertEqual(viewModel.sheetSubscribe?.season, 2)
    XCTAssertEqual(viewModel.sheetSubscribe?.episode_group, "group-a")
    XCTAssertEqual(viewModel.subscriptionGroupText(for: 1), "剧集组：group-b")
  }

  func testUnknownSeasonAvailabilityDoesNotDisplayBadgeOrDefaultToBestVersion() {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)

    XCTAssertNil(viewModel.getStatusText(season: 2))
    XCTAssertEqual(viewModel.getStatusColor(season: 2), "gray")

    viewModel.prepareSubscription(seasonNumber: 2)

    XCTAssertNil(viewModel.sheetSubscribe?.best_version)
    XCTAssertNil(viewModel.sheetSubscribe?.best_version_full)
  }

  func testLoadedEmptySeasonAvailabilityStillDisplaysAsAvailableAndDefaultsToFullBestVersion() {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.isSeasonAvailabilityLoaded = true

    XCTAssertEqual(viewModel.getStatusText(season: 2), "已入库")
    XCTAssertEqual(viewModel.getStatusColor(season: 2), "green")

    viewModel.prepareSubscription(seasonNumber: 2)

    XCTAssertEqual(viewModel.sheetSubscribe?.best_version, 1)
    XCTAssertEqual(viewModel.sheetSubscribe?.best_version_full, 1)
  }

  func testPartialSeasonAvailabilityUsesBackendDefaultSubscribeMode() {
    let media = MediaInfo(tmdb_id: 12345, title: "航海王", type: "电视剧")
    let viewModel = SubscribeSeasonViewModel(mediaInfo: media)
    viewModel.isSeasonAvailabilityLoaded = true
    viewModel.seasonsNotExisted[2] = 1

    viewModel.prepareSubscription(seasonNumber: 2)

    XCTAssertNil(viewModel.sheetSubscribe?.best_version)
    XCTAssertNil(viewModel.sheetSubscribe?.best_version_full)
  }

  func testOnlyTVUsesSeasonSubscriptionAndCollectionsCannotSubscribe() {
    XCTAssertTrue(MediaInfo(tmdb_id: 1, title: "电影", type: "电影").canDirectlySubscribe)
    XCTAssertFalse(MediaInfo(tmdb_id: 2, title: "TMDB 剧", type: "电视剧").canDirectlySubscribe)
    XCTAssertFalse(MediaInfo(douban_id: "douban-1", title: "豆瓣剧", type: "电视剧").canDirectlySubscribe)
    XCTAssertFalse(MediaInfo(bangumi_id: 3, title: "Bangumi 剧", type: "电视剧").canDirectlySubscribe)
    XCTAssertFalse(
      MediaInfo(tmdb_id: 4, title: "合集", type: "系列", collection_id: 40)
        .canDirectlySubscribe
    )
    XCTAssertTrue(MediaInfo(tmdb_id: 5, title: "未知", type: "未知").canDirectlySubscribe)
    XCTAssertTrue(MediaInfo(tmdb_id: 6, title: "无合集 ID 的系列", type: "系列").canDirectlySubscribe)
  }

  func testSeasonPrimaryActionSubscribesSeasonWhenNavigationHandlerIsProvided() throws {
    let season = try makeSeason(number: 2)
    var tappedSeason: TmdbSeason?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      onSeasonTap: { tappedSeason = $0 },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertNil(tappedSeason)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertEqual(preparedSeason, 2)
  }

  func testSeasonPrimaryActionUnsubscribesSeasonWhenNavigationHandlerIsProvided() throws {
    let season = try makeSeason(number: 4)
    var tappedSeason: TmdbSeason?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: true,
      onSeasonTap: { tappedSeason = $0 },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertNil(tappedSeason)
    XCTAssertEqual(unsubscribedSeason, 4)
    XCTAssertNil(preparedSeason)
  }

  func testSubscribedSeasonPrimaryActionShowsUnsubscribeConfirmationAfterRefreshConfirmsSubscription()
    async throws
  {
    let season = try makeSeason(number: 4)
    var refreshedSeason: Int?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    await SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: true,
      refreshSubscribedState: { seasonNumber in
        refreshedSeason = seasonNumber
        return true
      },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(refreshedSeason, 4)
    XCTAssertEqual(unsubscribedSeason, 4)
    XCTAssertNil(preparedSeason)
  }

  func testSubscribedSeasonPrimaryActionSkipsUnsubscribeWhenRefreshFindsMissingSubscription()
    async throws
  {
    let season = try makeSeason(number: 4)
    var refreshedSeason: Int?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    await SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: true,
      refreshSubscribedState: { seasonNumber in
        refreshedSeason = seasonNumber
        return false
      },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(refreshedSeason, 4)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertNil(preparedSeason)
  }

  func testUnsubscribedSeasonPrimaryActionSkipsActionWhenRefreshFindsExistingSubscription()
    async throws
  {
    let season = try makeSeason(number: 5)
    var refreshedSeason: Int?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    await SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      refreshSubscribedState: { seasonNumber in
        refreshedSeason = seasonNumber
        return true
      },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(refreshedSeason, 5)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertNil(preparedSeason)
  }

  func testUnsubscribedSeasonPrimaryActionPreparesSubscribeAfterRefreshConfirmsMissingSubscription()
    async throws
  {
    let season = try makeSeason(number: 5)
    var refreshedSeason: Int?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    await SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      refreshSubscribedState: { seasonNumber in
        refreshedSeason = seasonNumber
        return false
      },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(refreshedSeason, 5)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertEqual(preparedSeason, 5)
  }

  func testSeasonPrimaryActionSkipsActionWhenRefreshFails() async throws {
    let season = try makeSeason(number: 6)
    var refreshedSeason: Int?
    var unsubscribedSeason: Int?
    var preparedSeason: Int?

    await SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      refreshSubscribedState: { seasonNumber in
        refreshedSeason = seasonNumber
        return nil
      },
      showUnsubscribeConfirm: { unsubscribedSeason = $0 },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(refreshedSeason, 6)
    XCTAssertNil(unsubscribedSeason)
    XCTAssertNil(preparedSeason)
  }

  func testSeasonPrimaryActionKeepsSubscribeFallbackWithoutNavigationHandler() throws {
    let season = try makeSeason(number: 3)
    var preparedSeason: Int?

    SubscribeSeasonContentView.performSeasonPrimaryAction(
      season: season,
      isSubscribed: false,
      onSeasonTap: nil,
      showUnsubscribeConfirm: { _ in XCTFail("Unsubscribed an unsubscribed season") },
      prepareSubscription: { preparedSeason = $0 }
    )

    XCTAssertEqual(preparedSeason, 3)
  }

  func testSeasonAvailabilityPayloadPreservesRawMediaFieldsWhenOverridingEpisodeGroup()
    throws
  {
    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        """
        {
          "tmdb_id": 12345,
          "source": "themoviedb",
          "title": "插件扩展媒体",
          "type": "电视剧",
          "episode_group": "old-group",
          "plugin_context": {
            "provider": "custom",
            "opaque_id": "keep-me"
          }
        }
        """.utf8
      )
    )
    let viewModel = SubscribeSeasonViewModel(
      mediaInfo: media,
      initialEpisodeGroup: "new-group"
    )

    let payload = try JSONDecoder().decode(
      [String: JSONValue].self,
      from: JSONEncoder().encode(viewModel.seasonAvailabilityMedia())
    )

    XCTAssertEqual(payload["episode_group"], .string("new-group"))
    XCTAssertEqual(
      payload["plugin_context"],
      .object([
        "provider": .string("custom"),
        "opaque_id": .string("keep-me"),
      ])
    )
  }

  func testSeasonPosterUsesAbsoluteURLAndFallsBackToMainPoster() {
    let service = APIService.shared
    let previous = service.useImageCache
    service.useImageCache = false
    defer { service.useImageCache = previous }

    XCTAssertEqual(
      service.getSeasonPosterURL(
        posterPath: "https://images.example/season.jpg",
        mediaPosterPath: "https://images.example/main.jpg"
      )?.absoluteString,
      "https://images.example/season.jpg"
    )
    XCTAssertEqual(
      service.getSeasonPosterURL(
        posterPath: " ",
        mediaPosterPath: "https://images.example/main.jpg"
      )?.absoluteString,
      "https://images.example/main.jpg"
    )
  }

  private func makeSeason(number: Int) throws -> TmdbSeason {
    let data = """
      {
        "air_date": "2024-01-01",
        "episode_count": 8,
        "name": "Season \(number)",
        "overview": "",
        "poster_path": "/season\(number).jpg",
        "season_number": \(number),
        "vote_average": 8.0
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(TmdbSeason.self, from: data)
  }

  private func makeEpisodeGroup(id: String, name: String) throws -> EpisodeGroup {
    let data = """
      {
        "id": "\(id)",
        "name": "\(name)",
        "group_count": 1,
        "episode_count": 12
      }
      """.data(using: .utf8)!

    return try JSONDecoder().decode(EpisodeGroup.self, from: data)
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Condition was not satisfied before timeout")
  }

  @MainActor
  private func configureSubscriptionSnapshotAccess(
    _ service: APIService,
    userName: String = "subscription-snapshot",
    userId: Int = 1
  ) {
    let user = subscriptionSnapshotToken(userName: userName, userId: userId)
    service.replaceSessionForTesting(
      baseURL: service.baseURL,
      token: user.access_token,
      currentUser: user
    )
  }

  private func subscriptionSnapshotToken(
    userName: String,
    userId: Int,
    accessToken: String = "subscription-snapshot-token"
  ) -> Token {
    Token(
      access_token: accessToken,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: true,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_id: userId,
      user_name: userName,
      avatar: nil
    )
  }
}

private struct SubscriptionSnapshotServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let serverURLDefaults: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SubscriptionSnapshotServiceSnapshot {
    SubscriptionSnapshotServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
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

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }
    restoreCredential(account: "accessToken", keychainValue: tokenKeychain, defaultsValue: tokenDefaults)
    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(
        keychainValue,
        service: "MoviePilot-TV",
        account: account
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }
    if let defaultsValue {
      UserDefaults.standard.set(defaultsValue, forKey: account)
    } else {
      UserDefaults.standard.removeObject(forKey: account)
    }
  }
}

private final class APICacheTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var currentDate: Date

  init(start: Date) {
    self.currentDate = start
  }

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return currentDate
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    currentDate = currentDate.addingTimeInterval(interval)
    lock.unlock()
  }
}

private struct SubscriptionSnapshotStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: SubscriptionSnapshotAsyncGate?

  init(statusCode: Int, data: Data, gate: SubscriptionSnapshotAsyncGate? = nil) {
    self.statusCode = statusCode
    self.data = data
    self.gate = gate
  }
}

private final class SubscribeSeasonNotificationCounter: @unchecked Sendable {
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

private actor SubscriptionSnapshotAsyncGate {
  private var isOpen = false
  private var waiterCount = 0
  private var waitContinuations: [CheckedContinuation<Void, Never>] = []
  private var waiterContinuations: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    waiterCount += 1
    waiterContinuations.forEach { $0.resume() }
    waiterContinuations.removeAll()

    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waitContinuations.append(continuation)
    }
  }

  func waitForWaiter() async {
    guard waiterCount == 0 else { return }
    await withCheckedContinuation { continuation in
      waiterContinuations.append(continuation)
    }
  }

  func waitForWaiterCount(_ count: Int) async {
    while waiterCount < count {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func open() {
    isOpen = true
    waitContinuations.forEach { $0.resume() }
    waitContinuations.removeAll()
    waiterContinuations.forEach { $0.resume() }
    waiterContinuations.removeAll()
  }
}

private actor SubscriptionSnapshotURLProtocolStub {
  private var queuedResponses: [SubscriptionSnapshotStubResponse] = []
  private var defaultSubscriptionsData: Data?
  private var mediaDeleteResponseData: Data?
  private var subscriptionDeleteResponseData: Data?
  private var requestCounts: [String: Int] = [:]
  private var episodeGroupsStatusCode = 200
  private var episodeGroupsGate: SubscriptionSnapshotAsyncGate?
  private var seasonAvailabilityGate: SubscriptionSnapshotAsyncGate?
  private var groupSeasonResponses: [String: SubscriptionSnapshotStubResponse] = [:]

  func reset() {
    queuedResponses.removeAll()
    defaultSubscriptionsData = nil
    mediaDeleteResponseData = nil
    subscriptionDeleteResponseData = nil
    requestCounts.removeAll()
    episodeGroupsStatusCode = 200
    episodeGroupsGate = nil
    seasonAvailabilityGate = nil
    groupSeasonResponses.removeAll()
  }

  func enqueueSubscriptions(
    _ subscriptions: [Subscribe],
    waitFor gate: SubscriptionSnapshotAsyncGate? = nil
  ) throws {
    let data = try JSONEncoder().encode(subscriptions)
    queuedResponses.append(SubscriptionSnapshotStubResponse(statusCode: 200, data: data, gate: gate))
  }

  func enqueueServerError(
    waitFor gate: SubscriptionSnapshotAsyncGate? = nil
  ) throws {
    guard let data = #"{"detail":"stale subscription snapshot"}"#.data(using: .utf8) else {
      throw URLError(.badServerResponse)
    }
    queuedResponses.append(SubscriptionSnapshotStubResponse(statusCode: 500, data: data, gate: gate))
  }

  func setDefaultSubscriptions(_ subscriptions: [Subscribe]) throws {
    defaultSubscriptionsData = try JSONEncoder().encode(subscriptions)
  }

  func setMediaDeleteResponse(_ json: String) {
    mediaDeleteResponseData = Data(json.utf8)
  }

  func setSubscriptionDeleteResponse(_ json: String) {
    subscriptionDeleteResponseData = Data(json.utf8)
  }

  func setEpisodeGroupsStatusCode(_ statusCode: Int) {
    episodeGroupsStatusCode = statusCode
  }

  func setEpisodeGroupsGate(_ gate: SubscriptionSnapshotAsyncGate?) {
    episodeGroupsGate = gate
  }

  func setSeasonAvailabilityGate(_ gate: SubscriptionSnapshotAsyncGate?) {
    seasonAvailabilityGate = gate
  }

  func setGroupSeasons(
    groupId: String,
    seasonNumber: Int,
    waitFor gate: SubscriptionSnapshotAsyncGate? = nil
  ) {
    let data = Data(
      """
      [
        {
          "air_date": "2024-01-01",
          "episode_count": 8,
          "name": "Season \(seasonNumber)",
          "overview": "",
          "poster_path": null,
          "season_number": \(seasonNumber),
          "vote_average": 8.0
        }
      ]
      """.utf8
    )
    groupSeasonResponses[groupId] = SubscriptionSnapshotStubResponse(
      statusCode: 200,
      data: data,
      gate: gate
    )
  }

  func subscribeRequestCount() -> Int {
    requestCounts["/api/v1/subscribe", default: 0] + requestCounts["/api/v1/subscribe/", default: 0]
  }

  func waitForSubscribeRequestCount(_ expectedCount: Int) async {
    for _ in 0..<2_000 {
      if subscribeRequestCount() >= expectedCount { return }
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func requestCount(path: String) -> Int {
    requestCounts[path, default: 0]
  }

  func response(for request: URLRequest) async throws -> SubscriptionSnapshotStubResponse {
    let path = request.url?.path ?? ""
    requestCounts[path, default: 0] += 1

    if request.httpMethod == "DELETE", path.hasPrefix("/api/v1/subscribe/media/"),
      let mediaDeleteResponseData
    {
      return SubscriptionSnapshotStubResponse(statusCode: 200, data: mediaDeleteResponseData)
    }

    if request.httpMethod == "DELETE", path.hasPrefix("/api/v1/subscribe/") {
      if let subscriptionDeleteResponseData {
        return SubscriptionSnapshotStubResponse(statusCode: 200, data: subscriptionDeleteResponseData)
      }
      return try jsonResponse(#"{"success":true}"#)
    }

    if request.httpMethod == "GET", path.hasPrefix("/api/v1/subscribe/search/") {
      return try jsonResponse(#"{"success":true}"#)
    }

    if request.httpMethod == "PUT", path.hasPrefix("/api/v1/subscribe/status/") {
      return try jsonResponse(#"{"success":true}"#)
    }

    if request.httpMethod == "GET", path.hasPrefix("/api/v1/subscribe/reset/") {
      return try jsonResponse(#"{"success":true}"#)
    }

    if path == "/api/v1/subscribe" || path == "/api/v1/subscribe/" {
      if !queuedResponses.isEmpty {
        let response = queuedResponses.removeFirst()
        if let gate = response.gate {
          await gate.wait()
        }
        return response
      }
      if let defaultSubscriptionsData {
        return SubscriptionSnapshotStubResponse(statusCode: 200, data: defaultSubscriptionsData)
      }
      throw URLError(.badServerResponse)
    }

    if path.hasPrefix("/api/v1/media/groups/") {
      if let episodeGroupsGate {
        await episodeGroupsGate.wait()
      }
      return SubscriptionSnapshotStubResponse(
        statusCode: episodeGroupsStatusCode,
        data: Data("[]".utf8)
      )
    }

    if path == "/api/v1/media/seasons" {
      return try jsonResponse(Self.seasonsJSON)
    }

    if path.hasPrefix("/api/v1/media/group/seasons/"),
      let groupId = request.url?.lastPathComponent,
      let response = groupSeasonResponses[groupId]
    {
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    }

    if path == "/api/v1/mediaserver/notexists" {
      if let seasonAvailabilityGate {
        await seasonAvailabilityGate.wait()
      }
      return try jsonResponse("[]")
    }

    if path.hasPrefix("/api/v1/media/tmdb:") {
      let tmdbId = request.url?.lastPathComponent.split(separator: ":").last.flatMap { Int($0) }
      return try mediaDetailResponse(tmdbId: tmdbId)
    }

    throw URLError(.badServerResponse)
  }

  private func jsonResponse(_ json: String) throws -> SubscriptionSnapshotStubResponse {
    guard let data = json.data(using: .utf8) else {
      throw URLError(.badServerResponse)
    }
    return SubscriptionSnapshotStubResponse(statusCode: 200, data: data)
  }

  private func mediaDetailResponse(tmdbId: Int?) throws -> SubscriptionSnapshotStubResponse {
    try jsonResponse(
      """
      {
        "tmdb_id": \(tmdbId ?? 0),
        "title": "预加载剧集 \(tmdbId ?? 0)",
        "type": "电视剧"
      }
      """
    )
  }

  private static let seasonsJSON = """
    [
      {
        "air_date": "2024-01-01",
        "episode_count": 8,
        "name": "Season 1",
        "overview": "",
        "poster_path": null,
        "season_number": 1,
        "vote_average": 8.0
      }
    ]
    """
}

private final class SubscriptionSnapshotURLProtocol: URLProtocol {
  static let stub = SubscriptionSnapshotURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscription-snapshot-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscriptionSnapshotURLProtocolTaskContext(
      request: request,
      clientBox: SubscriptionSnapshotURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = SubscriptionSnapshotURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscriptionSnapshotURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await SubscriptionSnapshotURLProtocol.stub.response(
          for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
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

private final class SubscriptionSnapshotURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscriptionSnapshotURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscriptionSnapshotURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscriptionSnapshotURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: SubscriptionSnapshotStubResponse) {
    guard let url = request.url else {
      fail(URLError(.badURL))
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      fail(URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: stubResponse.data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
