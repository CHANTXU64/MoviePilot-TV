import Combine
import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfLaunchBehaviorTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(TopShelfLaunchURLProtocol.self))
    TopShelfLaunchURLProtocol.reset()
  }

  override func tearDown() async throws {
    TopShelfLaunchURLProtocol.reset()
    APIService.removeURLProtocolForTesting(TopShelfLaunchURLProtocol.self)
    try await super.tearDown()
  }

  func testColdLinkBuildsDetailBeforeSlowSessionCheckWithoutStartingMediaRequests() async throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let currentUserRequested = expectation(description: "启动校验已挂起")
    let prematureDetail = expectation(description: "会话校验前不得加载详情")
    prematureDetail.isInverted = true
    TopShelfLaunchURLProtocol.observe(
      currentUser: { currentUserRequested.fulfill() },
      detail: {
        prematureDetail.fulfill()
      })
    let startup = Task { await viewModel.prepareStartupIfNeeded() }
    await fulfillment(of: [currentUserRequested], timeout: 3)

    let router = TopShelfNavigationRouter(store: nil)
    XCTAssertTrue(router.handle(try TopShelfDeepLink.url(for: payload(service: service))))
    let route = try XCTUnwrap(router.pendingRoute)
    XCTAssertEqual(viewModel.acceptTopShelfRoute(route), .preview)
    router.consume(id: route.id)
    let coordinator = ImageNavigationCoordinator(
      apiService: service,
      initialEntry: route.navigationEntry,
      startsInitialMediaLoad: !viewModel.isPreparingStartupSession
    )
    XCTAssertTrue(viewModel.canPresentContent)
    XCTAssertTrue(viewModel.isPreparingStartupSession)
    XCTAssertEqual(coordinator.path.count, 1, "第一棵导航树已经包含详情，无需页面出现后 push")
    let preload = try XCTUnwrap(coordinator.preloadTask(for: route.navigationEntry))
    XCTAssertNil(preload.fullDetail)
    await fulfillment(of: [prematureDetail], timeout: 0.15)

    let detailRequested = expectation(description: "验证完成后加载目标详情")
    TopShelfLaunchURLProtocol.observe(currentUser: {}, detail: { detailRequested.fulfill() })
    TopShelfLaunchURLProtocol.releaseCurrentUser()
    await startup.value
    XCTAssertFalse(viewModel.isPreparingStartupSession)
    XCTAssertEqual(viewModel.topShelfRoute?.id, route.id)
    coordinator.startDeferredMediaLoads()
    await fulfillment(of: [detailRequested], timeout: 3)
    XCTAssertEqual(TopShelfLaunchURLProtocol.detailRequestCount, 1)
    coordinator.path.removeLast()
    XCTAssertTrue(coordinator.lifecycle(for: route.navigationEntry).isRemoved)
  }

  func testDirectDetailAppliesCoreResponseBeforeBackgroundOrFirstRowIsReady() async throws {
    let service = makeService()
    let partial = MediaInfo(tmdb_id: 42, title: "本地标题", type: "电影")
    let full = MediaInfo(tmdb_id: 42, title: "完整标题", type: "电影", overview: "已经取得的简介")
    let preload = MediaPreloadTask(partialMedia: partial, apiService: service)
    preload.fullDetail = full
    let viewModel = MediaDetailViewModel(detail: partial, apiService: service)
    viewModel.preloadTask = preload
    defer {
      viewModel.cancelForPop()
      preload.cancel()
    }

    _ = await MediaDetailView.applyReadyPreloadedDetail(
      from: preload, to: viewModel, hasRefreshedSubscription: true
    )
    XCTAssertEqual(viewModel.detail.title, partial.title, "普通入口保留等待背景的规则")
    _ = await MediaDetailView.applyReadyPreloadedDetail(
      from: preload, to: viewModel, hasRefreshedSubscription: true,
      requiresBackgroundReady: false
    )
    XCTAssertFalse(preload.isDetailReady)
    XCTAssertFalse(viewModel.isFirstRowReady)
    XCTAssertEqual(viewModel.detail.title, full.title)
    XCTAssertEqual(viewModel.detail.overview, full.overview)
    XCTAssertFalse(MediaDetailPresentationStyle.direct.usesLoadingTransition)
    XCTAssertTrue(MediaDetailPresentationStyle.standard.usesLoadingTransition)
  }

  func testColdNavigationRendersDetailBeforeAnyNetworkResponse() async throws {
    let service = makeService()
    let imageURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("top-shelf-preview-\(UUID()).jpg")
    let poster = UIGraphicsImageRenderer(size: CGSize(width: 608, height: 900)).image { context in
      UIColor(red: 0.08, green: 0.22, blue: 0.42, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 608, height: 900))
      UIColor(red: 0.25, green: 0.55, blue: 0.7, alpha: 1).setFill()
      context.fill(CGRect(x: 150, y: 160, width: 300, height: 580))
    }
    try XCTUnwrap(poster.jpegData(compressionQuality: 0.9)).write(to: imageURL)
    defer { try? FileManager.default.removeItem(at: imageURL) }
    let route = try XCTUnwrap(
      PendingTopShelfRoute(
        payload: payload(service: service), localPosterURL: imageURL,
        cachedContent: TopShelfCachedContent(
          detail: MediaInfo(
            tmdb_id: 42, title: "提前缓存的完整详情", type: "电影", year: "2026",
            overview: "首屏直接使用已准备的详情和背景", vote_average: 8.5
          ), backgroundURL: imageURL, backgroundIsPoster: false
        )
      ))
    let presentation = TabView(selection: .constant(1)) {
      Text("媒体库根页").tabItem { Text("媒体库") }.tag(0)
      RecommendView(isSelected: true, initialTopShelfRoute: route, allowsRequests: false)
        .tabItem { Text("推荐") }.tag(1)
    }
    .environmentObject(MediaActionHandler())
    .environment(\.scenePhase, .active)
    let host = UIHostingController(rootView: presentation)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKey()
    }
    try await Task.sleep(for: .milliseconds(500))
    host.view.layoutIfNeeded()
    let navigation = try XCTUnwrap(navigationControllers(in: host).first)
    XCTAssertEqual(navigation.viewControllers.count, 2, "正式导航首屏已包含推荐根页和目标详情")
    XCTAssertEqual(TopShelfLaunchURLProtocol.detailRequestCount, 0)
    let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: screenshot)
    attachment.name = "TopShelf-cold-detail-awaiting-session"
    attachment.lifetime = .keepAlways
    add(attachment)
    let pixel = try samplePixel(of: screenshot, at: CGPoint(x: 1500, y: 250))
    XCTAssertGreaterThan(Int(pixel[2]), Int(pixel[0]) + 15, "蓝色本地海报应替代空灰背景")
  }

  private func navigationControllers(in controller: UIViewController) -> [UINavigationController] {
    (controller as? UINavigationController).map { [$0] }
      ?? controller.children.flatMap {
        navigationControllers(in: $0)
      }
  }

  private func samplePixel(of image: UIImage, at point: CGPoint) throws -> [UInt8] {
    let pixel = try XCTUnwrap(
      image.cgImage?.cropping(
        to: CGRect(
          x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1
        )))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      ))
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes
  }

  func testPublishedCardRestoresDetailAndBackdropFromDiskWithoutDownloadingOnOpen() async throws {
    let service = makeService()
    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "TopShelfPrepared-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suite)
    }
    let store = TopShelfSharedStore(containerURL: directory)
    let summary = MediaInfo(
      tmdb_id: 42, title: "摘要标题", type: "电影", poster_path: "https://images.local/poster.jpg"
    )
    let detail = MediaInfo(
      tmdb_id: 42, title: "完整标题", type: "电影", poster_path: summary.poster_path,
      backdrop_path: "https://images.local/backdrop.jpg", overview: "完整简介", runtime: 123
    )
    let imageData = TopShelfTestArtwork.landscapeData()
    var downloads: [URL] = []
    var manager: TopShelfManager? = TopShelfManager(
      apiService: service, store: store, defaults: defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in [summary] }, fetchDetail: { _ in detail },
      fetchImage: { url in
        downloads.append(url)
        return TopShelfImageResource(data: imageData, fileExtension: "jpg")
      },
      fetchBackgroundImage: { url in
        downloads.append(url)
        return TopShelfImageResource(data: imageData, fileExtension: "jpg")
      }, notifyChange: {}
    )
    await manager?.refreshNow()
    let item = try XCTUnwrap(try store.loadState()?.snapshot?.items.first)
    manager = nil
    service.mediaPreloader.clearAll()

    let coldRouter = TopShelfNavigationRouter(store: TopShelfSharedStore(containerURL: directory))
    XCTAssertTrue(coldRouter.handle(item.displayURL))
    let route = try XCTUnwrap(coldRouter.pendingRoute)
    XCTAssertEqual(route.cachedContent?.detail.overview, "完整简介")
    XCTAssertEqual(route.cachedContent?.detail.runtime, 123)
    let backgroundURL = try XCTUnwrap(route.cachedContent?.backgroundURL)
    let background = try XCTUnwrap(UIImage(contentsOfFile: backgroundURL.path)?.cgImage)
    XCTAssertEqual(background.width, 2560)
    XCTAssertEqual(background.height, 1440)
    XCTAssertEqual(route.cachedContent?.backgroundIsPoster, false)
    let coordinator = ImageNavigationCoordinator(
      apiService: service, initialEntry: route.navigationEntry, startsInitialMediaLoad: false
    )
    let task = try XCTUnwrap(coordinator.preloadTask(for: route.navigationEntry))
    XCTAssertEqual(task.fullDetail?.title, "完整标题")
    XCTAssertTrue(task.isDetailReady, "认证等待期间基础详情已从磁盘准备好")
    let unexpectedRequest = expectation(description: "打开已准备卡片不再次请求基础详情")
    unexpectedRequest.isInverted = true
    TopShelfLaunchURLProtocol.observe(currentUser: {}, detail: { unexpectedRequest.fulfill() })
    coordinator.startDeferredMediaLoads()
    await fulfillment(of: [unexpectedRequest], timeout: 0.15)
    XCTAssertEqual(downloads.count, 1)
    coordinator.path.removeLast()

    let foreign = payload(service: makeService())
    XCTAssertNil(store.cachedContent(for: foreign, at: Date()))
    let storedPayload = try XCTUnwrap(TopShelfDeepLink.payload(from: item.displayURL))
    XCTAssertNotNil(
      store.cachedContent(
        for: storedPayload, at: Date().addingTimeInterval(30 * 24 * 60 * 60)
      ))
    try FileManager.default.removeItem(at: XCTUnwrap(route.cachedContent?.backgroundURL))
    XCTAssertNil(store.cachedContent(for: storedPayload, at: Date()))
    XCTAssertTrue(coldRouter.handle(item.displayURL))
    XCTAssertNil(coldRouter.pendingRoute?.cachedContent, "被系统清理后正常降级，不使用失效的图片路径")
  }

  func testPreparedCollectionFirstPageDoesNotFetchAgainOnEntry() async throws {
    let service = makeService()
    let cached = MediaInfo(tmdb_id: 42, title: "已准备的合集成员", type: "电影")
    let viewModel = CollectionDetailViewModel(
      collectionId: 7, title: "合集", apiService: service, preparedItems: [cached]
    )
    let unexpected = expectation(description: "合集第一页已在 Top Shelf 发布前加载")
    unexpected.isInverted = true
    TopShelfLaunchURLProtocol.observe(currentUser: {}, detail: { unexpected.fulfill() })
    XCTAssertEqual(viewModel.paginator.items.first?.title, cached.title, "认证及加载任务之前已显示第一页")
    await viewModel.loadInitialData()
    XCTAssertEqual(viewModel.paginator.items.first?.title, cached.title)
    await fulfillment(of: [unexpected], timeout: 0.1)
    viewModel.paginator.cancel()
  }

  func testExternalPreparedOpenCancelsOldFocusPreloadBeforeLateResponse() async throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let root = ImageNavigationCoordinator(apiService: service)
    root.setStackForeground(true)
    let summary = try XCTUnwrap(TopShelfNavigationRouter.media(from: payload(service: service)))
    TopShelfLaunchURLProtocol.holdDetailResponses()
    let requested = expectation(description: "旧推荐页焦点详情请求挂起")
    TopShelfLaunchURLProtocol.observe(currentUser: {}, detail: { requested.fulfill() })
    let oldTask = try XCTUnwrap(
      service.mediaPreloader.preloadFocusedCandidateIfNeeded(
        for: summary, stackID: root.id
      ))
    await fulfillment(of: [requested], timeout: 3)
    let prepared = TopShelfCachedContent(
      detail: MediaInfo(tmdb_id: 42, title: "磁盘完整详情", type: "电影"),
      backgroundURL: URL(fileURLWithPath: "/fixture/background.jpg"), backgroundIsPoster: false
    )
    let route = try XCTUnwrap(
      PendingTopShelfRoute(
        payload: payload(service: service), cachedContent: prepared
      ))
    XCTAssertEqual(viewModel.acceptTopShelfRoute(route), .preview)
    root.openExternal(route.navigationEntry, startsMediaLoad: false)
    let next = root
    let task = try XCTUnwrap(next.preloadTask(for: route.navigationEntry))
    XCTAssertFalse(task === oldTask)
    next.startDeferredMediaLoads()
    TopShelfLaunchURLProtocol.releaseDetailResponse()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(task.fullDetail?.title, "磁盘完整详情")
    XCTAssertEqual(task.preparedContent?.backgroundURL, prepared.backgroundURL)
    XCTAssertEqual(TopShelfLaunchURLProtocol.detailRequestCount, 1)
    XCTAssertEqual(TopShelfLaunchURLProtocol.imageRequestCount, 0, "旧响应不得再启动背景下载")
    next.path.removeLast()
  }

  func testOrdinaryPushOfSamePreparedMediaSharesItsLocalBackground() throws {
    let service = makeService()
    let prepared = TopShelfCachedContent(
      detail: MediaInfo(tmdb_id: 42, title: "磁盘完整详情", type: "电影"),
      backgroundURL: URL(fileURLWithPath: "/fixture/background.jpg"), backgroundIsPoster: false
    )
    let route = try XCTUnwrap(
      PendingTopShelfRoute(
        payload: payload(service: service), cachedContent: prepared
      ))
    let stack = ImageNavigationCoordinator(
      apiService: service, initialEntry: route.navigationEntry, startsInitialMediaLoad: false
    )
    let firstTask = try XCTUnwrap(stack.preloadTask(for: route.navigationEntry))
    let child = stack.push(route.media)
    let childTask = try XCTUnwrap(stack.preloadTask(for: child))
    XCTAssertEqual(child.presentationStyle, .standard)
    XCTAssertNil(child.cachedContent, "普通 entry 无需重复携带磁盘结果")
    XCTAssertTrue(firstTask === childTask)
    XCTAssertEqual(childTask.preparedContent?.backgroundURL, prepared.backgroundURL)
    XCTAssertTrue(childTask.isDetailReady)
    stack.path.removeLast()
    XCTAssertNotNil(firstTask.preparedContent)
    stack.path.removeLast()
  }

  func testExternalOpenClearsDeepStackButSubsequentDetailPushKeepsNormalBackOrder() throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let first = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let oldStack = ImageNavigationCoordinator(
      apiService: service, initialEntry: first.navigationEntry, startsInitialMediaLoad: false
    )
    oldStack.push(MediaInfo(tmdb_id: 43, title: "旧第二层", type: "电影"))
    oldStack.push(MediaInfo(tmdb_id: 44, title: "旧第三层", type: "电影"))
    XCTAssertEqual(oldStack.path.count, 3)
    let latest = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    XCTAssertEqual(viewModel.acceptTopShelfRoute(latest), .preview)
    XCTAssertEqual(oldStack.path.count, 3)
    let root = oldStack.rootLifecycle
    oldStack.openExternal(latest.navigationEntry, startsMediaLoad: false)
    let stack = oldStack
    XCTAssertTrue(stack.rootLifecycle === root)
    XCTAssertFalse(root.isRemoved)
    XCTAssertEqual(stack.path.count, 1)
    let child = stack.push(MediaInfo(tmdb_id: 45, title: "新第二层", type: "电影"))
    XCTAssertEqual(child.presentationStyle, .standard)
    XCTAssertNil(child.cachedContent)
    XCTAssertEqual(stack.path.count, 2)
    stack.path.removeLast()
    XCTAssertEqual(stack.path.count, 1)
    XCTAssertFalse(stack.lifecycle(for: latest.navigationEntry).isRemoved)
    stack.path.removeLast()
    XCTAssertEqual(stack.path.count, 0, "Top Shelf 目标只需再返回一次即到推荐根页")
  }

  func testExternalOpenPreservesOtherTabStackAndReplacesRecommendationWithoutEmptyPath() throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let route = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let recommend = ImageNavigationCoordinator(
      apiService: service, initialEntry: route.navigationEntry, startsInitialMediaLoad: false)
    let search = ImageNavigationCoordinator(
      apiService: service, initialEntry: route.navigationEntry, startsInitialMediaLoad: false)
    _ = recommend.push(route.media)
    _ = search.push(route.media)
    let searchCount = search.path.count
    var observed: [Int] = []
    let subscription = recommend.$path.dropFirst().sink { observed.append($0.count) }
    defer { subscription.cancel() }
    let next = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    _ = viewModel.acceptTopShelfRoute(next)
    XCTAssertEqual(search.path.count, searchCount)
    XCTAssertEqual(recommend.path.count, 2)
    recommend.openExternal(next.navigationEntry, startsMediaLoad: false)
    XCTAssertEqual(observed, [1], "替换时不发布空栈中间态")
    XCTAssertEqual(search.path.count, searchCount)
    recommend.path.removeLast()
    XCTAssertEqual(recommend.path.count, 0)
  }

  func testNewExternalEventReplacesPresentationAndLogoutRevokesCachedPreview() throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let first = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let second = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    XCTAssertEqual(viewModel.acceptTopShelfRoute(first), .preview)
    XCTAssertEqual(viewModel.acceptTopShelfRoute(second), .preview)
    XCTAssertEqual(viewModel.topShelfRoute?.id, second.id)
    viewModel.finishTopShelfOpening(id: first.id)
    XCTAssertTrue(viewModel.isOpeningTopShelf, "旧页面完成不能解除新目标的优先级")
    viewModel.finishTopShelfOpening(id: second.id)
    XCTAssertFalse(viewModel.isOpeningTopShelf)

    service.logout()
    XCTAssertNil(viewModel.topShelfRoute)
    XCTAssertFalse(viewModel.canPresentContent)
    XCTAssertEqual(viewModel.acceptTopShelfRoute(second), .discard)
  }

  func testForeignOwnerDoesNotCreateAColdPreview() throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let other = makeService()
    let route = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: other)))
    XCTAssertNotEqual(service.session.imageNamespace, other.session.imageNamespace)
    XCTAssertEqual(viewModel.acceptTopShelfRoute(route), .discard)
    XCTAssertNil(viewModel.topShelfRoute)
    XCTAssertFalse(viewModel.canPresentContent)
  }

  func testRootNavigationPopRetiresDeferredTaskAndKeepsOrdinaryPushStyle() throws {
    let service = makeService()
    let route = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let coordinator = ImageNavigationCoordinator(
      apiService: service,
      initialEntry: route.navigationEntry,
      startsInitialMediaLoad: false
    )
    let lifecycle = coordinator.lifecycle(for: route.navigationEntry)
    coordinator.path.removeLast()
    XCTAssertEqual(coordinator.path.count, 0)
    XCTAssertTrue(lifecycle.isRemoved)
    coordinator.startDeferredMediaLoads()
    XCTAssertEqual(TopShelfLaunchURLProtocol.detailRequestCount, 0)
    let ordinary = coordinator.push(
      ResourceSearchRequest(
        keyword: "普通入口", type: nil, area: nil, title: nil,
        year: nil, season: nil, mediaInfo: nil, sites: nil
      ))
    XCTAssertEqual(ordinary.presentationStyle, .standard)
    coordinator.path.removeLast()
  }

  func testReplacingWholeNavigationTreeReleasesOldOwnersWithoutCancellingNewOwner() throws {
    let service = makeService()
    let oldRoute = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let newRoute = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    var oldStack: ImageNavigationCoordinator? = ImageNavigationCoordinator(
      apiService: service, initialEntry: oldRoute.navigationEntry, startsInitialMediaLoad: false
    )
    let oldLifecycle = try XCTUnwrap(oldStack?.lifecycle(for: oldRoute.navigationEntry))
    weak var task = oldStack?.preloadTask(for: oldRoute.navigationEntry)
    var newStack: ImageNavigationCoordinator? = ImageNavigationCoordinator(
      apiService: service, initialEntry: newRoute.navigationEntry, startsInitialMediaLoad: false
    )
    let newLifecycle = try XCTUnwrap(newStack?.lifecycle(for: newRoute.navigationEntry))
    XCTAssertNotNil(task)
    XCTAssertTrue(newStack?.preloadTask(for: newRoute.navigationEntry) === task)

    oldStack = nil
    XCTAssertTrue(oldLifecycle.isRemoved)
    XCTAssertFalse(oldLifecycle.keepsActivePageImages)
    XCTAssertFalse(newLifecycle.isRemoved)
    XCTAssertTrue(service.mediaPreloader.peekTask(for: newRoute.media) === task)

    newStack = nil
    XCTAssertTrue(newLifecycle.isRemoved)
    XCTAssertNil(service.mediaPreloader.peekTask(for: newRoute.media))
    XCTAssertNil(task)
  }

  func testAcceptedExternalEventImmediatelyRejectsLateActionsFromRetainedOldStack() throws {
    let service = makeService()
    let viewModel = ContentViewModel(apiService: service)
    let oldRoute = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))
    let oldStack = ImageNavigationCoordinator(
      apiService: service, initialEntry: oldRoute.navigationEntry, startsInitialMediaLoad: false
    )
    oldStack.setStackForeground(true)
    let source = oldStack.sourceToken()
    let lifecycle = oldStack.lifecycle(for: oldRoute.navigationEntry)
    let nextRoute = try XCTUnwrap(PendingTopShelfRoute(payload: payload(service: service)))

    XCTAssertEqual(viewModel.acceptTopShelfRoute(nextRoute), .preview)
    XCTAssertEqual(oldStack.path.count, 1, "广播不清除其他 Tab 的导航路径")
    XCTAssertFalse(lifecycle.isRemoved)
    XCTAssertNil(oldStack.push(nextRoute.media, ifCurrent: source))
    oldStack.resetDetailHistory()
    XCTAssertTrue(lifecycle.isRemoved)
    XCTAssertEqual(oldStack.path.count, 0)
    XCTAssertNil(service.mediaPreloader.peekTask(for: oldRoute.media))
    oldStack.setStackPresentation(isSelected: true, scenePhase: .active)
    XCTAssertTrue(oldStack.isStackInteractive, "根页可继续交互，但旧详情动作不能复用")
    XCTAssertFalse(oldStack.rootLifecycle.isRemoved)
    XCTAssertNil(oldStack.push(nextRoute.media, ifCurrent: source))
    oldStack.startDeferredMediaLoads()
    XCTAssertEqual(TopShelfLaunchURLProtocol.detailRequestCount, 0)

    let newStack = ImageNavigationCoordinator(
      apiService: service, initialEntry: nextRoute.navigationEntry, startsInitialMediaLoad: false
    )
    XCTAssertEqual(newStack.path.count, 1)
    XCTAssertFalse(newStack.lifecycle(for: nextRoute.navigationEntry).isRemoved)
    XCTAssertNotNil(service.mediaPreloader.peekTask(for: nextRoute.media))
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "launch-token", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true, "search": false, "subscribe": false, "manage": false],
      user_id: 901, user_name: "launch-user", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://top-shelf-launch.local", token: user.access_token, currentUser: user
    )
    return service
  }

  private func payload(service: APIService) -> TopShelfRoutePayload {
    TopShelfRoutePayload(
      sessionID: service.session.imageNamespace, source: "themoviedb",
      mediaID: nil, mediaIDPrefix: nil, tmdbID: 42, doubanID: nil, bangumiID: nil,
      anilistID: nil, imdbID: nil, tvdbID: nil, title: "本地标题", type: "电影",
      year: "2026", season: nil, posterPath: nil, collectionID: nil,
      overview: "本地简介", voteAverage: 8.5
    )
  }
}

private final class TopShelfLaunchURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var pendingUser: TopShelfLaunchURLProtocol?
  nonisolated(unsafe) private static var detailCount = 0
  nonisolated(unsafe) private static var onCurrentUser: (@Sendable () -> Void)?
  nonisolated(unsafe) private static var onDetail: (@Sendable () -> Void)?
  nonisolated(unsafe) private static var pendingDetail: TopShelfLaunchURLProtocol?
  nonisolated(unsafe) private static var holdsDetails = false
  nonisolated(unsafe) private static var imageCount = 0

  static var imageRequestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return imageCount
  }

  static func holdDetailResponses() {
    lock.lock()
    defer { lock.unlock() }
    holdsDetails = true
  }

  static func releaseDetailResponse() {
    lock.lock()
    let request = pendingDetail
    pendingDetail = nil
    holdsDetails = false
    lock.unlock()
    request?.respond(
      """
      {"tmdb_id":42,"title":"晚到的旧详情","type":"电影","backdrop_path":"https://top-shelf-launch.local/hero.jpg"}
      """)
  }

  static var detailRequestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return detailCount
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    pendingUser = nil
    detailCount = 0
    onCurrentUser = nil
    onDetail = nil
    pendingDetail = nil
    holdsDetails = false
    imageCount = 0
  }

  static func observe(
    currentUser: @escaping @Sendable () -> Void, detail: @escaping @Sendable () -> Void
  ) {
    lock.lock()
    defer { lock.unlock() }
    onCurrentUser = currentUser
    onDetail = detail
  }

  static func releaseCurrentUser() {
    lock.lock()
    let request = pendingUser
    pendingUser = nil
    lock.unlock()
    request?.respond(
      """
      {"id":901,"name":"launch-user","is_superuser":false,"permissions":{"discovery":true,"search":false,"subscribe":false,"manage":false}}
      """)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "top-shelf-launch.local"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url!.path
    Self.lock.lock()
    if path == "/api/v1/user/current" {
      Self.pendingUser = self
      let callback = Self.onCurrentUser
      Self.lock.unlock()
      callback?()
      return
    }
    let isDetail = path.hasPrefix("/api/v1/media/")
    if isDetail { Self.detailCount += 1 }
    if path == "/hero.jpg" { Self.imageCount += 1 }
    let callback = isDetail ? Self.onDetail : nil
    if isDetail && Self.holdsDetails {
      Self.pendingDetail = self
      Self.lock.unlock()
      callback?()
      return
    }
    Self.lock.unlock()
    callback?()
    if isDetail {
      respond("{\"tmdb_id\":42,\"title\":\"远端详情\",\"type\":\"电影\",\"source\":\"themoviedb\"}")
    } else if path.hasPrefix("/api/v1/system/global") {
      respond("{}")
    } else {
      respond("[]")
    }
  }

  override func stopLoading() {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    if Self.pendingUser === self { Self.pendingUser = nil }
    if Self.pendingDetail === self { Self.pendingDetail = nil }
  }

  private func respond(_ text: String) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(text.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
