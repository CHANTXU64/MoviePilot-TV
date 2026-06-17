import XCTest

@testable import MoviePilot_TV

final class MediaDetailViewHeaderActionTests: XCTestCase {
  @MainActor
  func testHeaderUnsubscribeConfirmationUsesSharedFormatWithoutSeasonOrEpisodeGroup() {
    let detail = MediaInfo(title: "孤独摇滚", type: "电视剧", season: 1)

    XCTAssertEqual(
      SubscriptionCancelConfirmation.headerMessage(for: detail),
      "是否取消《孤独摇滚》订阅？"
    )
  }

  @MainActor
  func testCancelSubscriptionDeletesResolvedFallbackMediaWithoutSeason() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    await DetailHeaderSubscriptionURLProtocol.stub.setMinimalSubscriptionPayload(tmdbId: 998_877)
    service.baseURL = "http://detail-header-subscription-tests.local"

    let detail = MediaInfo(
      douban_id: "detail-header-douban",
      title: "详情页取消订阅",
      type: "电视剧",
      season: 1
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.tmdbId = 998_877
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [])
    XCTAssertEqual(deletedMediaRequests.map(\.path), ["/api/v1/subscribe/media/tmdb:998877"])
    XCTAssertEqual(deletedMediaRequests.map(\.query), [nil])
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCancelSubscriptionUsesSubscriptionMediaIdFromOriginalLookupFallback() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let detail = MediaInfo(
      douban_id: "detail-header-title-fallback-douban",
      title: "标题兜底订阅",
      type: "电视剧"
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [])
    XCTAssertEqual(deletedMediaRequests.map(\.path), ["/api/v1/subscribe/media/tmdb:998877"])
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCancelSubscriptionContinuesFallbackAfterUnresolvedOriginalLookup() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let detail = MediaInfo(
      douban_id: "detail-header-minimal-alias-douban",
      title: "原始 ID 最小响应",
      type: "电视剧"
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.tmdbId = 998_877
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [])
    XCTAssertEqual(deletedMediaRequests.map(\.path), ["/api/v1/subscribe/media/tmdb:998877"])
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCancelSubscriptionContinuesFallbackWhenBangumiLookupReturnsUnsupportedMediaId()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let detail = MediaInfo(
      bangumi_id: 12_345,
      title: "Bangumi 详情页取消订阅",
      type: "电视剧"
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.tmdbId = 998_877
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [])
    XCTAssertEqual(deletedMediaRequests.map(\.path), ["/api/v1/subscribe/media/tmdb:998877"])
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCancelSubscriptionDeletesBangumiLookupBySubscriptionIDWhenNoTMDBFallback() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let detail = MediaInfo(
      bangumi_id: 12_345,
      title: "Bangumi 详情页取消订阅",
      type: "电视剧"
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [7001])
    XCTAssertTrue(deletedMediaRequests.isEmpty)
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCancelSubscriptionBypassesStaleFallbackStatusCacheWhenAlreadyRemoved() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let tmdbMedia = MediaInfo(tmdb_id: 776_655, type: "电视剧")
    let cachedSubscriptionStatus = try await service.checkSubscription(media: tmdbMedia)
    XCTAssertTrue(cachedSubscriptionStatus)
    await DetailHeaderSubscriptionURLProtocol.stub.setResolvedSubscription(tmdbId: 776_655, id: nil)

    let detail = MediaInfo(
      douban_id: "detail-header-stale-douban",
      title: "详情页远端取消",
      type: "电视剧",
      season: 1
    )
    let preloadTask = MediaPreloadTask(partialMedia: detail)
    preloadTask.tmdbId = 776_655
    preloadTask.isSubscribed = true

    let viewModel = MediaDetailViewModel(detail: detail)
    viewModel.preloadTask = preloadTask

    await viewModel.cancelSubscription()

    let deletedSubscriptionIDs = await DetailHeaderSubscriptionURLProtocol.stub.deletedSubscriptionIDs()
    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()

    XCTAssertEqual(deletedSubscriptionIDs, [])
    XCTAssertTrue(deletedMediaRequests.isEmpty)
    XCTAssertEqual(preloadTask.isSubscribed, false)
  }

  @MainActor
  func testCheckSubscriptionAcceptsMinimalSubscriptionPayload() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    await DetailHeaderSubscriptionURLProtocol.stub.setMinimalSubscriptionPayload(tmdbId: 554_433)
    service.baseURL = "http://detail-header-subscription-tests.local"

    let status = try await service.checkSubscription(
      media: MediaInfo(tmdb_id: 554_433, type: "电视剧")
    )

    XCTAssertTrue(status)
  }

  @MainActor
  func testCheckSubscriptionRetriesWhenGenerationChangesBeforeResponseReturns() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    let gate = DetailHeaderSubscriptionAsyncGate()
    await DetailHeaderSubscriptionURLProtocol.stub.enqueueResolvedSubscription(
      tmdbId: 665_544,
      id: 9101,
      waitFor: gate
    )
    await DetailHeaderSubscriptionURLProtocol.stub.setResolvedSubscription(
      tmdbId: 665_544,
      id: nil
    )
    service.baseURL = "http://detail-header-subscription-tests.local"

    let media = MediaInfo(tmdb_id: 665_544, type: "电影")
    let staleCheck = Task {
      try await service.checkSubscription(media: media)
    }
    await gate.waitForWaiter()

    _ = try await service.deleteSubscription(id: 9101)
    await gate.open()

    let status = try await staleCheck.value
    let lookupCount = await DetailHeaderSubscriptionURLProtocol.stub.lookupRequestCount(
      tmdbId: 665_544
    )

    XCTAssertFalse(status)
    XCTAssertEqual(lookupCount, 2)
  }

  @MainActor
  func testCheckSubscriptionRetriesWhenGenerationChangesAfterStatusCacheStore() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    await DetailHeaderSubscriptionURLProtocol.stub.enqueueResolvedSubscription(
      tmdbId: 775_544,
      id: 9201
    )
    await DetailHeaderSubscriptionURLProtocol.stub.setResolvedSubscription(
      tmdbId: 775_544,
      id: nil
    )
    service.baseURL = "http://detail-header-subscription-tests.local"

    var didInvalidate = false
    service.subscriptionCacheTestHooks.afterSubscriptionStatusCacheStore = {
      guard !didInvalidate else { return }
      didInvalidate = true
      _ = try? await service.deleteSubscription(id: 9201)
    }
    defer { service.subscriptionCacheTestHooks = .init() }

    let status = try await service.checkSubscription(
      media: MediaInfo(tmdb_id: 775_544, type: "电影")
    )
    let lookupCount = await DetailHeaderSubscriptionURLProtocol.stub.lookupRequestCount(
      tmdbId: 775_544
    )

    XCTAssertTrue(didInvalidate)
    XCTAssertFalse(status)
    XCTAssertEqual(lookupCount, 2)
  }

  @MainActor
  func testCheckSubscriptionThrowsWhenCancelledAfterStatusCacheHit() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let media = MediaInfo(tmdb_id: 776_655, type: "电影")
    let cachedStatus = try await service.checkSubscription(media: media)
    XCTAssertTrue(cachedStatus)

    let gate = DetailHeaderSubscriptionAsyncGate()
    service.subscriptionCacheTestHooks.afterSubscriptionStatusCacheHit = {
      await gate.wait()
    }
    defer { service.subscriptionCacheTestHooks = .init() }

    let cancelledCheck = Task {
      try await service.checkSubscription(media: media)
    }
    await gate.waitForWaiter()

    cancelledCheck.cancel()
    await gate.open()

    do {
      _ = try await cancelledCheck.value
      XCTFail("A caller cancelled after reading cached subscription status must not receive it.")
    } catch is CancellationError {
      // Expected.
    }
  }

  @MainActor
  func testCheckSubscriptionThrowsWhenCancelledAfterStatusCacheStore() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    await DetailHeaderSubscriptionURLProtocol.stub.setResolvedSubscription(
      tmdbId: 885_544,
      id: 9301
    )
    service.baseURL = "http://detail-header-subscription-tests.local"

    let gate = DetailHeaderSubscriptionAsyncGate()
    service.subscriptionCacheTestHooks.afterSubscriptionStatusCacheStore = {
      await gate.wait()
    }
    defer { service.subscriptionCacheTestHooks = .init() }

    let cancelledCheck = Task {
      try await service.checkSubscription(media: MediaInfo(tmdb_id: 885_544, type: "电影"))
    }
    await gate.waitForWaiter()

    cancelledCheck.cancel()
    await gate.open()

    do {
      _ = try await cancelledCheck.value
      XCTFail("A caller cancelled after storing subscription status must not receive it.")
    } catch is CancellationError {
      // Expected.
    }

    let lookupCount = await DetailHeaderSubscriptionURLProtocol.stub.lookupRequestCount(
      tmdbId: 885_544
    )
    XCTAssertEqual(lookupCount, 1)
  }

  @MainActor
  func testDeleteSubscriptionEncodesMediaIdAsSinglePathSegment() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DetailHeaderSubscriptionURLProtocol.self))
    defer { URLProtocol.unregisterClass(DetailHeaderSubscriptionURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DetailHeaderSubscriptionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DetailHeaderSubscriptionURLProtocol.stub.reset()
    service.baseURL = "http://detail-header-subscription-tests.local"

    let success = try await service.deleteSubscription(
      mediaId: "custom:abc/def value",
      season: nil
    )

    let deletedMediaRequests = await DetailHeaderSubscriptionURLProtocol.stub.deletedMediaRequests()
    XCTAssertTrue(success)
    XCTAssertEqual(deletedMediaRequests.map(\.absoluteString), [
      "http://detail-header-subscription-tests.local/api/v1/subscribe/media/custom:abc%2Fdef%20value"
    ])
  }

  @MainActor
  func testSubscribedHeaderActionShowsUnsubscribeConfirmation() {
    var didShowUnsubscribeConfirm = false
    var didStartSubscribe = false

    MediaDetailView.performHeaderSubscribeAction(
      isSubscribed: true,
      showUnsubscribeConfirm: {
        didShowUnsubscribeConfirm = true
      },
      startSubscribe: {
        didStartSubscribe = true
      }
    )

    XCTAssertTrue(didShowUnsubscribeConfirm)
    XCTAssertFalse(didStartSubscribe)
  }

  @MainActor
  func testUnsubscribedHeaderActionStartsSubscribeFlow() {
    var didShowUnsubscribeConfirm = false
    var didStartSubscribe = false

    MediaDetailView.performHeaderSubscribeAction(
      isSubscribed: false,
      showUnsubscribeConfirm: {
        didShowUnsubscribeConfirm = true
      },
      startSubscribe: {
        didStartSubscribe = true
      }
    )

    XCTAssertFalse(didShowUnsubscribeConfirm)
    XCTAssertTrue(didStartSubscribe)
  }
}

private struct DetailHeaderSubscriptionServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?

  @MainActor
  static func capture(service: APIService) -> DetailHeaderSubscriptionServiceSnapshot {
    DetailHeaderSubscriptionServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }
  }
}

private struct DetailHeaderSubscriptionQueuedStatus: Sendable {
  let tmdbId: Int
  let id: Int?
  let gate: DetailHeaderSubscriptionAsyncGate?
}

private actor DetailHeaderSubscriptionAsyncGate {
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

  func open() {
    isOpen = true
    waitContinuations.forEach { $0.resume() }
    waitContinuations.removeAll()
    waiterContinuations.forEach { $0.resume() }
    waiterContinuations.removeAll()
  }
}

private actor DetailHeaderSubscriptionURLProtocolStub {
  private var resolvedSubscriptionsByTMDBID: [Int: Int?] = [:]
  private var queuedStatusesByTMDBID: [Int: [DetailHeaderSubscriptionQueuedStatus]] = [:]
  private var lookupCountsByTMDBID: [Int: Int] = [:]
  private var minimalPayloadTMDBIDs: Set<Int> = []
  private var deletedIDs: [Int] = []
  private var mediaDeleteRequests: [DetailHeaderSubscriptionMediaDeleteRequest] = []

  func reset() {
    resolvedSubscriptionsByTMDBID = [
      776_655: 7002,
      998_877: 7001,
    ]
    queuedStatusesByTMDBID.removeAll()
    lookupCountsByTMDBID.removeAll()
    minimalPayloadTMDBIDs.removeAll()
    deletedIDs.removeAll()
    mediaDeleteRequests.removeAll()
  }

  func setMinimalSubscriptionPayload(tmdbId: Int) {
    resolvedSubscriptionsByTMDBID[tmdbId] = 7003
    minimalPayloadTMDBIDs.insert(tmdbId)
  }

  func setResolvedSubscription(tmdbId: Int, id: Int?) {
    resolvedSubscriptionsByTMDBID[tmdbId] = id
  }

  func enqueueResolvedSubscription(
    tmdbId: Int,
    id: Int?,
    waitFor gate: DetailHeaderSubscriptionAsyncGate? = nil
  ) {
    queuedStatusesByTMDBID[tmdbId, default: []].append(
      DetailHeaderSubscriptionQueuedStatus(tmdbId: tmdbId, id: id, gate: gate)
    )
  }

  func lookupRequestCount(tmdbId: Int) -> Int {
    lookupCountsByTMDBID[tmdbId, default: 0]
  }

  func deletedSubscriptionIDs() -> [Int] {
    deletedIDs
  }

  func deletedMediaRequests() -> [DetailHeaderSubscriptionMediaDeleteRequest] {
    mediaDeleteRequests
  }

  func response(for request: URLRequest) async throws -> DetailHeaderSubscriptionStubResponse {
    guard let url = request.url else { throw URLError(.badURL) }
    let path = url.path
    let method = request.httpMethod ?? "GET"

    if method == "GET",
      path.hasPrefix("/api/v1/subscribe/media/douban:")
    {
      if path.contains("detail-header-title-fallback-douban"),
        let id = resolvedSubscriptionsByTMDBID[998_877] ?? nil
      {
        return try jsonResponse(#"{"id":\#(id),"name":"标题兜底订阅","type":"电视剧","season":1,"tmdbid":998877}"#)
      }
      if path.contains("detail-header-minimal-alias-douban"),
        let id = resolvedSubscriptionsByTMDBID[998_877] ?? nil
      {
        return try jsonResponse(#"{"id":\#(id)}"#)
      }
      return try jsonResponse("{}")
    }

    if method == "GET",
      path.hasPrefix("/api/v1/subscribe/media/bangumi:")
    {
      if path.contains("bangumi:12345"),
        let id = resolvedSubscriptionsByTMDBID[998_877] ?? nil
      {
        return try jsonResponse(#"{"id":\#(id),"name":"Bangumi 订阅","type":"电视剧","season":1,"bangumiid":12345}"#)
      }
      return try jsonResponse("{}")
    }

    if method == "GET", path.hasPrefix("/api/v1/subscribe/media/tmdb:") {
      let tmdbId = path.split(separator: ":").last.flatMap { Int($0) }
      if let tmdbId {
        lookupCountsByTMDBID[tmdbId, default: 0] += 1
        if var queuedStatuses = queuedStatusesByTMDBID[tmdbId],
          !queuedStatuses.isEmpty
        {
          let queuedStatus = queuedStatuses.removeFirst()
          queuedStatusesByTMDBID[tmdbId] = queuedStatuses
          if let gate = queuedStatus.gate {
            await gate.wait()
          }
          if let id = queuedStatus.id {
            return try jsonResponse(#"{"id":\#(id),"name":"详情页取消订阅","type":"电视剧","season":1,"tmdbid":\#(queuedStatus.tmdbId)}"#)
          }
          return try jsonResponse("{}")
        }
      }
      if let tmdbId, let id = resolvedSubscriptionsByTMDBID[tmdbId] ?? nil {
        if minimalPayloadTMDBIDs.contains(tmdbId) {
          return try jsonResponse(#"{"id":\#(id)}"#)
        }
        return try jsonResponse(#"{"id":\#(id),"name":"详情页取消订阅","type":"电视剧","season":1,"tmdbid":\#(tmdbId)}"#)
      }
      return try jsonResponse("{}")
    }

    if method == "DELETE",
      path.hasPrefix("/api/v1/subscribe/"),
      let id = path.split(separator: "/").last.flatMap({ Int($0) })
    {
      if let tmdbId = resolvedSubscriptionsByTMDBID.first(where: { $0.value == id })?.key {
        resolvedSubscriptionsByTMDBID[tmdbId] = nil
      }
      deletedIDs.append(id)
      return try jsonResponse(#"{"success":true}"#)
    }

    if method == "DELETE", path.hasPrefix("/api/v1/subscribe/media/") {
      if let tmdbId = path.split(separator: ":").last.flatMap({ Int($0) }) {
        resolvedSubscriptionsByTMDBID[tmdbId] = nil
      }
      mediaDeleteRequests.append(
        DetailHeaderSubscriptionMediaDeleteRequest(
          path: path,
          query: url.query,
          absoluteString: url.absoluteString
        )
      )
      return try jsonResponse(#"{"success":true}"#)
    }

    throw URLError(.badServerResponse)
  }

  private func jsonResponse(_ json: String) throws -> DetailHeaderSubscriptionStubResponse {
    guard let data = json.data(using: .utf8) else {
      throw URLError(.badServerResponse)
    }
    return DetailHeaderSubscriptionStubResponse(statusCode: 200, data: data)
  }
}

private struct DetailHeaderSubscriptionStubResponse {
  let statusCode: Int
  let data: Data
}

private struct DetailHeaderSubscriptionMediaDeleteRequest: Equatable {
  let path: String
  let query: String?
  let absoluteString: String
}

private final class DetailHeaderSubscriptionURLProtocol: URLProtocol {
  static let stub = DetailHeaderSubscriptionURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "detail-header-subscription-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = DetailHeaderSubscriptionURLProtocolTaskContext(
      request: request,
      clientBox: DetailHeaderSubscriptionURLProtocolClientBox(
        protocolInstance: self,
        client: client
      )
    )

    loadingTask = DetailHeaderSubscriptionURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: DetailHeaderSubscriptionURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await DetailHeaderSubscriptionURLProtocol.stub.response(
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

private final class DetailHeaderSubscriptionURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: DetailHeaderSubscriptionURLProtocolClientBox

  init(request: URLRequest, clientBox: DetailHeaderSubscriptionURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class DetailHeaderSubscriptionURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: DetailHeaderSubscriptionStubResponse) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
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
