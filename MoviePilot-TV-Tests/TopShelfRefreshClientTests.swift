import Combine
import Kingfisher
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfRefreshClientTests: XCTestCase {
  private var directory: URL!
  private var store: TopShelfSharedStore!
  private var transport: URLSession!
  private var originalImageData = Data()
  private let selection = TopShelfSelection(
    shelfID: "recommend/custom?sort=hot&filter=A%2BB", title: "我的榜单")

  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    store = TopShelfSharedStore(containerURL: directory)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TopShelfRefreshURLProtocol.self]
    transport = URLSession(configuration: config)
    try store.saveState(
      TopShelfSharedState(
        schemaVersion: 1, activeSessionID: "owner", selection: selection, snapshot: nil,
        refreshConfiguration: TopShelfRefreshConfiguration(
          sessionID: "owner", baseURL: "http://shelf.local/mp",
          useImageCache: false, bangumiProxyEnabled: false, bangumiImageDomain: nil)))
    originalImageData = TopShelfTestArtwork.landscapeData()
    TopShelfRefreshURLProtocol.configure(image: originalImageData)
  }

  override func tearDown() async throws {
    transport.invalidateAndCancel()
    TopShelfRefreshURLProtocol.reset()
    try? FileManager.default.removeItem(at: directory)
  }

  private func refresh() async throws {
    try await TopShelfRefreshClient(
      store: store, transport: transport, readToken: { _ in "test-token" }
    ).refresh()
  }

  func testExtensionPreparesSixCardsAndAppReadsTheirDetailsWithoutManager() async throws {
    try await refresh()
    let state = try XCTUnwrap(store.loadState())
    XCTAssertEqual(state.selection, selection)
    let items = try XCTUnwrap(state.snapshot?.items)
    XCTAssertEqual(items.count, 6)
    for item in items {
      let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: item.displayURL))
      let content = try XCTUnwrap(store.cachedContent(for: payload, at: Date()))
      XCTAssertEqual(content.detail.source, "custom")
      XCTAssertEqual(content.detail.title, "完整详情")
      XCTAssertFalse(content.backgroundIsPoster)
      let background = try XCTUnwrap(UIImage(contentsOfFile: content.backgroundURL.path)?.cgImage)
      XCTAssertEqual(background.width, 2560)
      XCTAssertEqual(background.height, 1440)
      let thumbnailURL = try XCTUnwrap(store.imageURL(relativePath: item.imageRelativePath))
      XCTAssertNotEqual(thumbnailURL, content.backgroundURL)
      let thumbnail = try XCTUnwrap(UIImage(contentsOfFile: thumbnailURL.path))
      XCTAssertLessThanOrEqual(
        try XCTUnwrap(thumbnail.cgImage).width, Int(ceil(TopShelfImageLoader.cardSize.width * 2)))
      XCTAssertGreaterThan(thumbnail.size.width, thumbnail.size.height)
      XCTAssertTrue(FileManager.default.fileExists(atPath: content.backgroundURL.path))
    }
    let imageDirectory = directory.appendingPathComponent("Library/Caches/TopShelf/images")
    let cachedFiles = try FileManager.default.contentsOfDirectory(
      at: imageDirectory, includingPropertiesForKeys: nil)
    XCTAssertEqual(cachedFiles.count, 12, "六张卡片各保存两份处理结果")
    for file in cachedFiles {
      XCTAssertNotEqual(try Data(contentsOf: file), originalImageData)
    }
    let requests = TopShelfRefreshURLProtocol.requests
    let recommendation = try XCTUnwrap(
      requests.first { $0.url?.path == "/mp/api/v1/recommend/custom" })
    XCTAssertTrue(
      URLComponents(url: recommendation.url!, resolvingAgainstBaseURL: false)!.percentEncodedQuery!
        .contains("filter=A%2BB"))
    let request = try XCTUnwrap(
      requests.first { $0.url?.path.hasPrefix("/mp/api/v1/media/") == true })
    XCTAssertEqual(
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath,
      "/mp/api/v1/media/id%2B0%2F%E4%B8%AD%E6%96%87")
    XCTAssertTrue(
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedQuery!
        .contains("%2B"))
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first(where: { $0.name == "media_source" })?.value, "custom")
    XCTAssertTrue(
      requests.filter { $0.url?.host == "image.local" }.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == nil
      })
  }

  func testExtensionRecoversAfterEntireCachePurgeWithoutOpeningAppAndLogoutStaysRevoked()
    async throws
  {
    let suite = "top-shelf-recovery-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let initial = try XCTUnwrap(store.loadState())
    store = TopShelfSharedStore(containerURL: directory, persistentDefaults: defaults)
    try store.saveState(initial)
    try await refresh()
    try FileManager.default.removeItem(at: directory.appendingPathComponent("Library/Caches"))
    store = TopShelfSharedStore(
      containerURL: directory, persistentDefaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    let recovered = try XCTUnwrap(store.loadState())
    XCTAssertEqual(recovered.activeSessionID, "owner")
    XCTAssertEqual(recovered.selection, selection)
    XCTAssertNil(recovered.snapshot)
    try await refresh()
    XCTAssertEqual(store.presentation(at: Date())?.items.count, 6)
    try store.invalidatePublishedState(.disabled(selection: nil))
    try FileManager.default.removeItem(at: directory.appendingPathComponent("Library/Caches"))
    store = TopShelfSharedStore(
      containerURL: directory, persistentDefaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    let requestCount = TopShelfRefreshURLProtocol.requests.count
    try await refresh()
    XCTAssertEqual(TopShelfRefreshURLProtocol.requests.count, requestCount)
    XCTAssertNil(try store.loadState()?.activeSessionID)
    XCTAssertNil(store.presentation(at: Date()))
  }

  func testSameOriginAPIHierarchyRedirectRetainsAuthorizationAndPublishes() async throws {
    let destination = URL(string: "http://shelf.local/mp/api/v1/recommend/custom/")!
    TopShelfRefreshURLProtocol.redirectTarget = destination
    try await refresh()
    let request = try XCTUnwrap(TopShelfRefreshURLProtocol.requests.first { $0.url == destination })
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    XCTAssertEqual(store.presentation(at: Date())?.items.count, 6)
  }

  func testRedirectCannotLeaveOriginOrAPIPathAndKeepsOldContent() async throws {
    try await refresh()
    let old = try store.loadState()
    for destination in [
      "http://other.local/mp/api/v1/recommend/custom/",
      "http://shelf.local:81/mp/api/v1/recommend/custom/",
      "http://shelf.local/mp/api/v1evil/recommend/custom/",
      "https://shelf.local/mp/api/v1/recommend/custom/",
    ] {
      let url = try XCTUnwrap(URL(string: destination))
      TopShelfRefreshURLProtocol.redirectTarget = url
      do {
        try await refresh()
        XCTFail("不允许跨出鉴权范围")
      } catch {}
      XCTAssertFalse(TopShelfRefreshURLProtocol.requests.contains { $0.url == url })
      XCTAssertEqual(try store.loadState(), old)
    }
  }

  func testAppAndExtensionUseSameSystemCardIdentifier() async throws {
    try await refresh()
    let extensionItem = try XCTUnwrap(store.loadState()?.snapshot?.items.first)
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true], user_id: 802, user_name: "test", avatar: nil)
    service.replaceSessionForTesting(
      baseURL: "http://shelf.local/mp", token: "test", currentUser: user)
    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    let suiteName = "top-shelf-identity-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let media = MediaInfo(
      tmdb_id: 1, source: "custom", media_id: "id+0/中文", title: "卡片0",
      type: "电影+原声", poster_path: "http://image.local/0.jpg")
    let manager = TopShelfManager(
      apiService: service, store: store, defaults: defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in [media] }, fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {})
    await manager.refreshNow()
    let appItem = try XCTUnwrap(store.loadState()?.snapshot?.items.first)
    XCTAssertEqual(appItem.identifier, extensionItem.identifier)
  }

  func testRefreshFailureRetainsOldContentWithoutExpiryOrChangingSelection() async throws {
    try await refresh()
    let previous = try XCTUnwrap(store.loadState())
    TopShelfRefreshURLProtocol.failRequests = true
    do {
      try await refresh()
      XCTFail("应报告请求失败")
    } catch {}
    XCTAssertEqual(try store.loadState(), previous)
    XCTAssertEqual(store.presentation(at: Date().addingTimeInterval(40 * 86400))?.items.count, 6)
  }

  func testCardsStillOnHomeScreenUsePreparedDataAfterNewBatchAndSkipMissingPoster() async throws {
    try await refresh()
    let first = try XCTUnwrap(store.loadState()?.snapshot?.items.first)
    let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: first.displayURL))
    let cards = directory.appendingPathComponent("Library/Caches/TopShelf/cards")
    for file in try FileManager.default.contentsOfDirectory(
      at: cards, includingPropertiesForKeys: nil)
    {
      try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-2 * 86400)], ofItemAtPath: file.path)
    }
    TopShelfRefreshURLProtocol.offset = 100
    try await refresh()
    XCTAssertNotNil(store.cachedContent(for: payload, at: Date()))
    XCTAssertNotNil(store.previewImageURL(for: payload, at: Date()))
    let current = try XCTUnwrap(store.loadState()?.snapshot?.items.first)
    try FileManager.default.removeItem(
      at: XCTUnwrap(store.imageURL(relativePath: current.imageRelativePath)))
    XCTAssertEqual(store.presentation(at: Date())?.items.count, 5)
    try store.invalidatePublishedState(.disabled(selection: selection))
    XCTAssertNil(store.cachedContent(for: payload, at: Date()))
  }

  func testExtensionCannotPublishAfterLogoutDuringRequest() async throws {
    let store = try XCTUnwrap(store)
    TopShelfRefreshURLProtocol.onRecommendation = {
      try? store.invalidatePublishedState(.disabled(selection: nil))
    }
    do {
      try await refresh()
      XCTFail("旧请求应取消")
    } catch is CancellationError {}
    XCTAssertNil(try store.loadState()?.activeSessionID)
    XCTAssertNil(try store.loadState()?.snapshot)
  }

  func testStalePublisherCannotOverwriteAnotherPublishedBatch() async throws {
    let previous = try XCTUnwrap(store.loadState())
    try await refresh()
    let updated = try XCTUnwrap(store.loadState())
    XCTAssertThrowsError(try store.publish(XCTUnwrap(updated.snapshot), replacing: previous))
    XCTAssertEqual(try store.loadState(), updated)
  }

  func testForkSheetObservesHandlerAndRetiredHandlerCannotPresentAgain() async throws {
    let owner = TopShelfSheetOwner()
    let coordinator = ImageNavigationCoordinator(apiService: APIService.isolatedTestingInstance())
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(
      rootView: TopShelfSheetHost(owner: owner)
        .environmentObject(coordinator).environmentObject(NotificationManager()))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKey()
    }
    try await Task.sleep(for: .milliseconds(200))
    let share = try JSONDecoder().decode(
      SubscribeShare.self, from: Data(#"{"id":88,"share_title":"复用订阅回归"}"#.utf8))
    let previousHandler = owner.handler
    previousHandler.forkSheetRequest = share
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNotNil(host.presentedViewController, "handler 的变化必须驱动正式 Fork Sheet 呈现")
    owner.handler = SubscriptionHandler(apiService: APIService.isolatedTestingInstance())
    try await Task.sleep(for: .milliseconds(700))
    XCTAssertNil(host.presentedViewController, "外部打开更换呈现 owner 后旧 Sheet 应关闭")
    previousHandler.forkSheetRequest = nil
    previousHandler.forkSheetRequest = share
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertNil(host.presentedViewController, "旧异步回调只写旧 owner，不能覆盖新详情")
    owner.handler.forkSheetRequest = share
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNotNil(host.presentedViewController, "更换 owner 后正常复用订阅入口仍可用")
    owner.handler.forkSheetRequest = nil
    try await Task.sleep(for: .milliseconds(700))
  }

  func testColdCollectionShowsPreparedMembersButDefersRemoteImagesUntilRequestsAllowed()
    async throws
  {
    let oldConfiguration = ImageDownloader.default.sessionConfiguration
    let oldCacheSetting = APIService.shared.useImageCache
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TopShelfMemberImageURLProtocol.self]
    ImageDownloader.default.sessionConfiguration = configuration
    APIService.shared.useImageCache = false
    defer {
      ImageDownloader.default.sessionConfiguration = oldConfiguration
      APIService.shared.useImageCache = oldCacheSetting
      TopShelfMemberImageURLProtocol.onRequest = nil
    }
    let gate = TopShelfCollectionGate()
    let coordinator = ImageNavigationCoordinator(apiService: APIService.isolatedTestingInstance())
    coordinator.setStackForeground(true)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    let media = MediaInfo(
      tmdb_id: 42, title: "已缓存的合集成员", type: "电影",
      poster_path: "https://shelf-member.local/\(UUID()).gif")
    let host = UIHostingController(
      rootView:
        TopShelfCollectionHost(gate: gate, coordinator: coordinator, media: media)
        .environmentObject(coordinator).environmentObject(NotificationManager())
        .environmentObject(MediaActionHandler()))
    window.rootViewController = host
    let premature = expectation(description: "认证前不能请求成员海报")
    premature.isInverted = true
    TopShelfMemberImageURLProtocol.onRequest = { premature.fulfill() }
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKey()
      coordinator.retire()
    }
    await fulfillment(of: [premature], timeout: 0.3)
    let loaded = expectation(description: "认证后开始请求成员海报")
    TopShelfMemberImageURLProtocol.onRequest = { loaded.fulfill() }
    gate.allowsRequests = true
    await fulfillment(of: [loaded], timeout: 3)
  }

  func testRetainedSeasonDetailDismissesItsSubscriptionSheetOnExternalOpen() async throws {
    let service = APIService.isolatedTestingInstance()
    let model = SubscribeSeasonViewModel(
      mediaInfo: MediaInfo(tmdb_id: 42, title: "保留的分季页", type: "电视剧"), apiService: service)
    let coordinator = ImageNavigationCoordinator(apiService: service)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(
      rootView: SubscribeSeasonContentView(viewModel: model)
        .environmentObject(coordinator).environmentObject(NotificationManager()))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKey()
    }
    try await Task.sleep(for: .milliseconds(150))
    model.prepareSubscription(seasonNumber: 1)
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNotNil(host.presentedViewController)
    NotificationCenter.default.post(
      name: .imageNavigationPresentationWillReset, object: APIService.shared)
    for _ in 0..<60 {
      if host.presentedViewController == nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertNil(model.sheetSubscribe)
    XCTAssertNil(model.showUnsubscribeConfirm)
    XCTAssertNil(host.presentedViewController)
    XCTAssertEqual(model.mediaInfo.title, "保留的分季页")
  }

  func testSettingsRootAndSingleChoicePageRenderWithExistingRowStyle() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TopShelfRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TopShelfRefreshURLProtocol.self) }
    let service = APIService.isolatedTestingInstance()
    let token = Token(
      access_token: "test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true, "subscribe": true], user_id: 801, user_name: "preview",
      avatar: nil)
    service.replaceSessionForTesting(
      baseURL: "http://shelf.local/mp", token: "test", currentUser: token)
    let defaults = UserDefaults(suiteName: "top-shelf-ui-\(UUID())")!
    let manager = TopShelfManager(apiService: service, store: store, defaults: defaults)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    for page: SystemSettingsPage in [
      .root, .topShelfSelection, .topShelfRecommendations, .topShelfExplore,
      .topShelfExploreSources, .topShelfExploreField("sort"),
    ] {
      let window = UIWindow(windowScene: scene)
      let host = UIHostingController(
        rootView:
          SystemView(isSelected: false, apiService: service, initialPage: page)
          .environmentObject(manager).background(Color(white: 0.1))
      )
      window.rootViewController = host
      window.makeKeyAndVisible()
      try await Task.sleep(for: .milliseconds(500))
      host.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = "TopShelf-settings-\(page)"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertEqual(host.view.bounds.width, 1920, accuracy: 1)
      window.isHidden = true
      window.rootViewController = nil
    }
    previous?.makeKey()
  }
}

private final class TopShelfRefreshURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var image = Data()
  nonisolated(unsafe) private static var recorded: [URLRequest] = []
  nonisolated(unsafe) static var failRequests = false
  nonisolated(unsafe) static var redirectTarget: URL?
  nonisolated(unsafe) static var offset = 0
  nonisolated(unsafe) static var onRecommendation: (@Sendable () -> Void)?
  static var requests: [URLRequest] { lock.withLock { recorded } }
  static func configure(image: Data) {
    lock.withLock {
      self.image = image
      recorded = []
      failRequests = false
      offset = 0
      redirectTarget = nil
      onRecommendation = nil
    }
  }
  static func reset() { configure(image: Data()) }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (image, failure, offset, callback, redirectTarget) = Self.lock.withLock {
      Self.recorded.append(request)
      return (
        Self.image, Self.failRequests, Self.offset, Self.onRecommendation, Self.redirectTarget
      )
    }
    let path = request.url!.path
    if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.path
      == "/mp/api/v1/recommend/custom", let redirectTarget
    {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 307, httpVersion: nil,
        headerFields: ["Location": redirectTarget.absoluteString])!
      client?.urlProtocol(
        self, wasRedirectedTo: URLRequest(url: redirectTarget), redirectResponse: response)
      return
    }
    let data: Data
    if request.url!.host == "image.local" {
      data = image
    } else if path.contains("/recommend/custom") {
      callback?()
      let items: [[String: Any]] = (offset..<(offset + 10)).map { index in
        [
          "tmdb_id": index + 1, "media_source": "custom", "media_id": "id+\(index)/中文",
          "title": "卡片\(index)",
          "type": "电影+原声", "poster_path": "http://image.local/\(index).jpg",
        ]
      }
      data = try! JSONSerialization.data(withJSONObject: ["success": true, "data": items])
    } else if path.contains("/media/") {
      let imagePath = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        .percentEncodedPath
      data = try! JSONSerialization.data(withJSONObject: [
        "success": true,
        "data": [
          "title": "完整详情", "media_source": "custom", "media_id": "详情",
          "backdrop_path": "http://image.local" + imagePath + ".jpg",
        ],
      ])
    } else {
      data = Data("{}".utf8)
    }
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: failure ? 503 : 200,
        httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor
private final class TopShelfSheetOwner: ObservableObject {
  @Published var handler = SubscriptionHandler(apiService: APIService.isolatedTestingInstance())
}

private struct TopShelfSheetHost: View {
  @ObservedObject var owner: TopShelfSheetOwner
  var body: some View { Text("根页保持不变").mediaSubscriptionAlerts(using: owner.handler) }
}

@MainActor
private final class TopShelfCollectionGate: ObservableObject {
  @Published var allowsRequests = false
}

private struct TopShelfCollectionHost: View {
  @ObservedObject var gate: TopShelfCollectionGate
  let coordinator: ImageNavigationCoordinator
  let media: MediaInfo
  var body: some View {
    CollectionDetailView(
      title: "缓存合集", collectionId: 7,
      imageLifecycle: coordinator.rootLifecycle, allowsRequests: gate.allowsRequests,
      preparedItems: [media]
    )
    .disabled(true)
  }
}

private final class TopShelfMemberImageURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var callback: (@Sendable () -> Void)?
  static var onRequest: (@Sendable () -> Void)? {
    get { lock.withLock { callback } }
    set { lock.withLock { callback = newValue } }
  }
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "shelf-member.local"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.onRequest?()
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: 200,
        httpVersion: nil, headerFields: ["Content-Type": "image/gif"])!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: TopShelfTestArtwork.data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
