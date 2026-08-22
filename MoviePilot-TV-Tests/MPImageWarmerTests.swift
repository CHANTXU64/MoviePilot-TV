import Kingfisher
import UIKit
import XCTest

@testable import MoviePilot_TV

@MainActor
final class MPImageWarmerTests: XCTestCase {
  func testOnlyMoviePilotDiskCacheRoutesCanBeWarmed() throws {
    let baseURL = "http://192.168.1.10:3000/mp"

    XCTAssertTrue(
      MPImageWarmer.isWarmable(
        try XCTUnwrap(
          URL(
            string:
              "http://192.168.1.10:3000/mp/api/v1/system/cache/image?url=https%3A%2F%2Fimage.tmdb.org%2Fposter.jpg"
          )
        ),
        baseURL: baseURL,
        imageCacheEnabled: true
      )
    )
    XCTAssertTrue(
      MPImageWarmer.isWarmable(
        try XCTUnwrap(
          URL(
            string:
              "http://192.168.1.10:3000/mp/api/v1/system/img/1?imgurl=https%3A%2F%2Flain.bgm.tv%2Fpic.jpg&cache=true"
          )
        ),
        baseURL: baseURL,
        imageCacheEnabled: true
      )
    )

    let rejectedURLs = [
      "https://image.tmdb.org/poster.jpg",
      "http://192.168.1.10:3001/mp/api/v1/system/cache/image?url=https%3A%2F%2Fimage.tmdb.org%2Fposter.jpg",
      "http://192.168.1.10:3000/mp/api/v1/system/img/1?imgurl=https%3A%2F%2Flain.bgm.tv%2Fpic.jpg",
      "http://192.168.1.10:3000/mp/api/v1/system/img/0?imgurl=https%3A%2F%2Fexample.com%2Fpic.jpg",
    ]
    for value in rejectedURLs {
      XCTAssertFalse(
        MPImageWarmer.isWarmable(
          try XCTUnwrap(URL(string: value)),
          baseURL: baseURL,
          imageCacheEnabled: true
        ),
        value
      )
    }
    XCTAssertFalse(
      MPImageWarmer.isWarmable(
        try XCTUnwrap(
          URL(
            string:
              "http://192.168.1.10:3000/mp/api/v1/system/cache/image?url=https%3A%2F%2Fimage.tmdb.org%2Fposter.jpg"
          )
        ),
        baseURL: baseURL,
        imageCacheEnabled: false
      )
    )
  }

  func testWarmSessionAvoidsAppleTVURLCacheWithoutChangingConnectionLimit() {
    let defaults = URLSessionConfiguration.ephemeral
    let configuration = MPImageWarmer.makeConfiguration()

    XCTAssertNil(configuration.urlCache)
    XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(
      configuration.httpMaximumConnectionsPerHost,
      defaults.httpMaximumConnectionsPerHost
    )
  }

  func testWarmKeyIgnoresMoviePilotBaseURL() throws {
    let imageURL = "https%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw500%2Fposter.jpg"
    let first = try XCTUnwrap(
      URL(string: "http://192.168.1.10:3000/api/v1/system/cache/image?url=\(imageURL)")
    )
    let second = try XCTUnwrap(
      URL(string: "https://moviepilot.example.com/api/v1/system/cache/image?url=\(imageURL)")
    )

    XCTAssertEqual(MPImageWarmer.warmKey(for: first), MPImageWarmer.warmKey(for: second))
  }

  func testResponseBodyIsCancelledImmediately() throws {
    let delegate = MPImageWarmSessionDelegate()
    let session = URLSession(configuration: .ephemeral)
    let url = try XCTUnwrap(URL(string: "https://example.com/image.jpg"))
    let task = session.dataTask(with: url)
    let response = try XCTUnwrap(
      HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "image/jpeg"]
      )
    )
    var disposition: URLSession.ResponseDisposition?

    delegate.urlSession(session, dataTask: task, didReceive: response) {
      disposition = $0
    }

    XCTAssertEqual(disposition, .cancel)
  }

  func testInFlightWarmIsSharedUntilEveryOwnerCancels() async throws {
    MPImageWarmURLProtocol.reset(finishesImmediately: false)
    let configuration = MPImageWarmer.makeConfiguration()
    configuration.protocolClasses = [MPImageWarmURLProtocol.self]
    let warmer = MPImageWarmer(configuration: configuration)
    let url = try XCTUnwrap(
      URL(
        string:
          "http://192.168.1.10:3000/api/v1/system/cache/image?url=https%3A%2F%2Fimage.tmdb.org%2Fin-flight.jpg"
      )
    )

    let firstHandle = await warmer.warm(
      url,
      baseURL: "http://192.168.1.10:3000",
      imageCacheEnabled: true
    )
    let secondHandle = await warmer.warm(
      url,
      baseURL: "http://192.168.1.10:3000",
      imageCacheEnabled: true
    )
    let first = try XCTUnwrap(firstHandle)
    let second = try XCTUnwrap(secondHandle)

    XCTAssertEqual(first.requestID, second.requestID)
    XCTAssertNotEqual(first.ownerID, second.ownerID)
    XCTAssertEqual(warmer.activeRequestCount, 1)

    warmer.cancel(first)
    XCTAssertEqual(warmer.activeRequestCount, 1)
    warmer.cancel(second)
    XCTAssertEqual(warmer.activeRequestCount, 0)
  }

  func testSuccessfulWarmURLIsSkippedUntilCacheExpires() async throws {
    MPImageWarmURLProtocol.reset(finishesImmediately: true)
    let configuration = MPImageWarmer.makeConfiguration()
    configuration.protocolClasses = [MPImageWarmURLProtocol.self]
    let clock = MPImageWarmTestClock()
    let warmer = MPImageWarmer(
      configuration: configuration,
      recentWarmTTL: 60,
      now: { clock.now }
    )
    let url = try XCTUnwrap(
      URL(
        string:
          "http://192.168.1.10:3000/api/v1/system/cache/image?url=https%3A%2F%2Fimage.tmdb.org%2Fcached.jpg"
      )
    )

    let firstHandle = await warmer.warm(
      url,
      baseURL: "http://192.168.1.10:3000",
      imageCacheEnabled: true
    )
    XCTAssertNotNil(firstHandle)
    try await waitUntil("warm completes") {
      warmer.cachedURLCount == 1
    }

    let repeatedHandle = await warmer.warm(
      url,
      baseURL: "http://192.168.1.10:3000",
      imageCacheEnabled: true
    )
    XCTAssertNil(repeatedHandle)
    XCTAssertEqual(MPImageWarmURLProtocol.requestCount(for: url), 1)

    clock.advance(by: 61)
    let expiredHandle = await warmer.warm(
      url,
      baseURL: "http://192.168.1.10:3000",
      imageCacheEnabled: true
    )
    XCTAssertNotNil(expiredHandle)
    try await waitUntil("expired URL warms again") {
      MPImageWarmURLProtocol.requestCount(for: url) == 2
    }
  }

  func testPosterFallbackBlurDoesNotChangeBackdropHeroProcessor() {
    let size = CGSize(width: 1920, height: 1080)
    let screenScale: CGFloat = 1
    let firstPage = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: false,
      screenScale: screenScale
    )
    let posterFallback = MediaDetailBackgroundImage.posterFallbackProcessor(
      for: size,
      screenScale: screenScale
    )
    let posterHero = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: true,
      screenScale: screenScale
    )

    XCTAssertTrue(firstPage.identifier.contains("com.moviepilot.hero-downsample"))
    XCTAssertFalse(firstPage.identifier.contains("DownsamplingImageProcessor"))
    XCTAssertFalse(firstPage.identifier.contains("BlurImageProcessor"))
    XCTAssertNotEqual(firstPage.identifier, posterFallback.identifier)
    XCTAssertEqual(posterHero.identifier, posterFallback.identifier)

    let downsamplingRange = try? XCTUnwrap(
      posterFallback.identifier.range(of: "com.moviepilot.hero-downsample")
    )
    let blurRange = try? XCTUnwrap(posterFallback.identifier.range(of: "BlurImageProcessor"))
    XCTAssertNotNil(downsamplingRange)
    XCTAssertNotNil(blurRange)
    if let downsamplingRange, let blurRange {
      XCTAssertLessThan(downsamplingRange.lowerBound, blurRange.lowerBound)
    }

    let heroOptions = KingfisherParsedOptionsInfo(
      MediaDetailBackgroundImage.heroOptions(
        for: size,
        scaleFactor: 1,
        usingPosterAsBackdrop: false
      )
    )
    XCTAssertEqual(heroOptions.processor.identifier, firstPage.identifier)
    XCTAssertFalse(heroOptions.cacheMemoryOnly)
    XCTAssertFalse(heroOptions.cacheOriginalImage)
    XCTAssertFalse(heroOptions.cacheSerializer.originalDataUsed)
    XCTAssertTrue(Self.skipsMemoryCache(heroOptions.memoryCacheExpiration))
    let posterOptions = KingfisherParsedOptionsInfo(
      MediaDetailBackgroundImage.heroOptions(
        for: size,
        scaleFactor: 1,
        usingPosterAsBackdrop: true
      )
    )
    XCTAssertFalse(posterOptions.cacheSerializer.originalDataUsed)
    XCTAssertTrue(Self.skipsMemoryCache(posterOptions.memoryCacheExpiration))
  }

  func testTransientDecodedImageSkipsMemoryCache() {
    let parsed = KingfisherParsedOptionsInfo([TransientDecodedImage.skipMemoryCache])
    XCTAssertTrue(Self.skipsMemoryCache(parsed.memoryCacheExpiration))
  }

  func testBackgroundAppearanceRefreshesOnlyUnmountedHeroPage() {
    XCTAssertTrue(
      MediaDetailView.shouldRefreshBackground(isMounted: false, showingContentPage: false)
    )
    XCTAssertFalse(
      MediaDetailView.shouldRefreshBackground(isMounted: true, showingContentPage: false)
    )
    XCTAssertFalse(
      MediaDetailView.shouldRefreshBackground(isMounted: false, showingContentPage: true)
    )
    XCTAssertFalse(
      MediaDetailView.shouldRefreshBackground(isMounted: true, showingContentPage: true)
    )
  }

  func testContentPageKeepsBackgroundUntilFadeCompletes() {
    XCTAssertEqual(MediaDetailView.contentPageBackgroundFadeDuration, 0.4)
    XCTAssertFalse(
      MediaDetailView.shouldUnmountContentPageBackground(
        fadeElapsed: false,
        showingContentPage: true
      )
    )
    XCTAssertTrue(
      MediaDetailView.shouldUnmountContentPageBackground(
        fadeElapsed: true,
        showingContentPage: true
      )
    )
    XCTAssertFalse(
      MediaDetailView.shouldUnmountContentPageBackground(
        fadeElapsed: true,
        showingContentPage: false
      )
    )
  }

  func testDetailHeroDownsamplesToTwoKLongEdge() {
    let size = CGSize(width: 1920, height: 1080)
    XCTAssertEqual(MediaDetailBackgroundImage.targetLongEdgePixels, 2560)
    XCTAssertEqual(
      MediaDetailBackgroundImage.downsampleScale(for: size, screenScale: 2),
      2560 / 1920,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      MediaDetailBackgroundImage.downsampleScale(for: size, screenScale: 1),
      1
    )

    let processor = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: false,
      screenScale: 2
    )
    XCTAssertTrue(processor.identifier.contains("com.moviepilot.hero-downsample"))
    XCTAssertTrue(processor.identifier.contains(",2560)"))
    XCTAssertFalse(processor.identifier.contains("DownsamplingImageProcessor"))

    let options = KingfisherParsedOptionsInfo(
      MediaDetailBackgroundImage.heroOptions(
        for: size,
        scaleFactor: 2,
        usingPosterAsBackdrop: false
      )
    )
    XCTAssertEqual(options.scaleFactor, 2560 / 1920, accuracy: 0.0001)
    XCTAssertEqual(options.processor.identifier, processor.identifier)
    XCTAssertTrue(Self.skipsMemoryCache(options.memoryCacheExpiration))
  }

  func testReleasingDetailBackgroundsKeepsBothOnDisk() async throws {
    let cache = ImageCache(name: "released-detail-backgrounds-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/released-backdrop.jpg"))
    let size = CGSize(width: 32, height: 18)
    let screenScale: CGFloat = 2
    let processors = [
      MediaDetailBackgroundImage.heroProcessor(
        for: size,
        usingPosterAsBackdrop: false,
        screenScale: screenScale
      ),
      MediaDetailBackgroundImage.posterFallbackProcessor(
        for: size,
        screenScale: screenScale
      ),
    ]
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.blue.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }

    for processor in processors {
      try await cache.store(
        image,
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      )
      XCTAssertEqual(
        cache.imageCachedType(
          forKey: url.cacheKey,
          processorIdentifier: processor.identifier
        ),
        .memory
      )
    }

    MediaDetailBackgroundImage.removeFirstPageBackgroundFromMemory(
      for: url,
      size: size,
      screenScale: screenScale,
      cache: cache
    )
    MediaDetailBackgroundImage.removePosterFallbackBackgroundFromMemory(
      for: url,
      size: size,
      screenScale: screenScale,
      cache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processors[0].identifier
      ),
      .disk
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processors[1].identifier
      ),
      .disk
    )
  }

  func testPopReleasesPosterFallbackHeroFromMemoryAndKeepsDisk() async throws {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    sharedService.baseURLForTesting = "http://moviepilot.local"
    sharedService.useImageCache = true

    let apiService = APIService.testingInstance()
    apiService.baseURLForTesting = "http://moviepilot.local"
    apiService.useImageCache = true
    let preloader = MediaPreloader(apiService: apiService)
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "poster-fallback-hero-pop-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

    let media = MediaInfo(
      tmdb_id: 750_001,
      title: "海报原图回退",
      poster_path: "https://image.tmdb.org/t/p/original/poster.jpg",
      backdrop_path: nil
    )
    let target = media.imageURLs.backgroundTarget
    let primary = try XCTUnwrap(target.url)
    let fallback = try XCTUnwrap(target.fallbackURL)
    XCTAssertNotEqual(primary, fallback)
    XCTAssertTrue(target.isPoster)

    let size = CGSize(width: 32, height: 18)
    let processor = MediaDetailBackgroundImage.posterFallbackProcessor(
      for: size,
      screenScale: UIScreen.main.scale
    )
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.purple.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }

    for url in [primary, fallback] {
      let cacheKey = apiService.imageSource(for: url).cacheKey
      try await cache.store(
        image,
        forKey: cacheKey,
        processorIdentifier: processor.identifier
      )
      XCTAssertEqual(
        cache.imageCachedType(
          forKey: cacheKey,
          processorIdentifier: processor.identifier
        ),
        .memory
      )
    }

    let owner = UUID()
    preloader.preload(for: media)
    preloader.pin(key: media.id, owner: owner)
    preloader.releaseAfterPop(
      media: media,
      owner: owner,
      size: size,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil,
      imageCache: cache
    )

    XCTAssertNil(preloader.peekTask(for: media))
    for url in [primary, fallback] {
      XCTAssertEqual(
        cache.imageCachedType(
          forKey: apiService.imageSource(for: url).cacheKey,
          processorIdentifier: processor.identifier
        ),
        .disk,
        url.absoluteString
      )
    }
  }

  func testOpeningDetailDisablesFutureBackgroundWarm() {
    let task = MediaPreloadTask(partialMedia: MediaInfo(tmdb_id: 1, type: "电影"))
    let preparedAsCandidate = task.shouldWarmBackgroundImage(memoryOptimizationEnabled: true)

    XCTAssertTrue(preparedAsCandidate)
    XCTAssertTrue(
      task.shouldReleasePreparedBackgroundFromMemory(preparedAsCandidate: preparedAsCandidate)
    )
    task.markPreparedBackgroundForReleaseAfterCompletion()
    XCTAssertTrue(task.shouldRemoveRetrievedBackgroundAfterCompletion)
    XCTAssertFalse(task.shouldWarmBackgroundImage(memoryOptimizationEnabled: false))

    task.cancelImageWarm()

    XCTAssertFalse(task.shouldWarmBackgroundImage(memoryOptimizationEnabled: true))
    XCTAssertFalse(task.shouldRemoveRetrievedBackgroundAfterCompletion)
    XCTAssertFalse(
      task.shouldReleasePreparedBackgroundFromMemory(preparedAsCandidate: preparedAsCandidate)
    )
  }

  func testCancelledPreloadRemovesLateBackgroundResultAfterCompletion() {
    let task = MediaPreloadTask(partialMedia: MediaInfo(tmdb_id: 2, type: "电影"))
    let generation = task.imageRetrieveGeneration

    XCTAssertFalse(task.shouldDiscardRetrievedBackground(generation: generation))
    task.cancelImageWarm()
    XCTAssertFalse(task.shouldDiscardRetrievedBackground(generation: generation))

    task.cancel()

    XCTAssertTrue(task.shouldRemoveRetrievedBackgroundAfterCompletion)
    XCTAssertTrue(task.shouldDiscardRetrievedBackground(generation: generation))
    XCTAssertNotEqual(task.imageRetrieveGeneration, generation)
  }

  func testShouldDiscardLoadedBackgroundWhenPoppedOrUnmounted() {
    XCTAssertFalse(
      MediaDetailView.shouldDiscardLoadedBackground(
        didReleaseAfterPop: false,
        isBackgroundMounted: true
      )
    )
    XCTAssertTrue(
      MediaDetailView.shouldDiscardLoadedBackground(
        didReleaseAfterPop: true,
        isBackgroundMounted: true
      )
    )
    XCTAssertTrue(
      MediaDetailView.shouldDiscardLoadedBackground(
        didReleaseAfterPop: false,
        isBackgroundMounted: false
      )
    )
  }

  func testLoadingPosterProcessorIsDistinctFromCardPoster() {
    let loading = MediaDetailLoadingPoster.processor
    let card = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)

    XCTAssertEqual(MediaDetailLoadingPoster.size, CGSize(width: 460, height: 690))
    XCTAssertTrue(loading.identifier.contains("DownsamplingImageProcessor"))
    XCTAssertFalse(loading.identifier.contains("ResizingImageProcessor"))
    XCTAssertNotEqual(loading.identifier, card.identifier)
  }

  func testOnlyReducedNavigationDepthMeansDetailWasPopped() {
    XCTAssertFalse(MediaDetailView.wasPopped(navigationDepth: 3, currentPathCount: 4))
    XCTAssertFalse(MediaDetailView.wasPopped(navigationDepth: 3, currentPathCount: 3))
    XCTAssertTrue(MediaDetailView.wasPopped(navigationDepth: 3, currentPathCount: 2))
  }

  func testNewCandidateImmediatelyReleasesPreviousCandidate() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let first = MediaInfo(tmdb_id: 710_001, title: "候选一", type: "合集")
    let second = MediaInfo(tmdb_id: 710_002, title: "候选二", type: "合集")

    XCTAssertNotNil(preloader.preloadIfNeeded(for: first))
    XCTAssertNotNil(preloader.peekTask(for: first))

    XCTAssertNotNil(preloader.preloadIfNeeded(for: second))

    XCTAssertNil(preloader.peekTask(for: first))
    XCTAssertNotNil(preloader.peekTask(for: second))
  }

  func testPopReleasesTaskOnlyAfterLastNavigationOwnerLeaves() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let media = MediaInfo(
      tmdb_id: 720_001,
      title: "重复导航详情",
      type: "合集",
      collection_id: 1
    )
    let firstOwner = UUID()
    let secondOwner = UUID()
    let firstPageTarget = PageImageCleanupTarget()
    let secondPageTarget = PageImageCleanupTarget()

    preloader.preload(for: media)
    preloader.pin(key: media.id, owner: firstOwner)
    preloader.pin(key: media.id, owner: secondOwner)

    preloader.releaseAfterPop(
      media: media,
      owner: firstOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: firstPageTarget,
      returnTargetImageCleanupTarget: nil
    )
    XCTAssertNotNil(preloader.peekTask(for: media))

    preloader.releaseAfterPop(
      media: media,
      owner: secondOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: secondPageTarget,
      returnTargetImageCleanupTarget: nil
    )
    XCTAssertNil(preloader.peekTask(for: media))
  }

  func testCandidateReplacementDoesNotReleaseNavigationOwnedTask() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let navigationMedia = MediaInfo(tmdb_id: 730_001, title: "栈内详情", type: "合集")
    let candidateMedia = MediaInfo(tmdb_id: 730_002, title: "新候选", type: "合集")
    let owner = UUID()

    preloader.preloadIfNeeded(for: navigationMedia)
    preloader.pin(key: navigationMedia.id, owner: owner)
    preloader.preloadIfNeeded(for: candidateMedia)

    XCTAssertNotNil(preloader.peekTask(for: navigationMedia))
    XCTAssertNotNil(preloader.peekTask(for: candidateMedia))
  }

  func testPendingMediaNavigationProtectsTaskUntilDestinationAppears() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let stackID = UUID()
    let media = MediaInfo(tmdb_id: 730_101, title: "交接详情", type: "电影")
    let nextCandidate = MediaInfo(tmdb_id: 730_102, title: "交接后的候选", type: "电影")
    let destinationOwner = UUID()

    let token = preloader.beginMediaNavigation(
      for: media,
      pathDepth: 0,
      stackID: stackID
    )
    XCTAssertNotNil(token)

    preloader.preloadIfNeeded(for: nextCandidate)
    XCTAssertNotNil(preloader.peekTask(for: media))

    XCTAssertTrue(
      preloader.transferPendingMediaNavigation(
        for: media.id,
        pathDepth: 1,
        stackID: stackID,
        to: destinationOwner
      )
    )
    preloader.releaseAfterPop(
      media: media,
      owner: destinationOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil
    )
    XCTAssertNil(preloader.peekTask(for: media))
  }

  func testPendingMediaNavigationIsReleasedWhenPathRollsBack() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let stackID = UUID()
    let media = MediaInfo(tmdb_id: 730_111, title: "取消交接", type: "电影")

    XCTAssertNotNil(
      preloader.beginMediaNavigation(for: media, pathDepth: 2, stackID: stackID)
    )
    preloader.reconcilePendingMediaNavigations(currentPathDepth: 2, stackID: stackID)

    XCTAssertNil(preloader.peekTask(for: media))
  }

  func testPendingMediaNavigationRollbackIsIsolatedByStack() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let firstStack = UUID()
    let secondStack = UUID()
    let media = MediaInfo(tmdb_id: 730_121, title: "跨栈交接", type: "电影")

    XCTAssertNotNil(
      preloader.beginMediaNavigation(for: media, pathDepth: 0, stackID: firstStack)
    )
    preloader.reconcilePendingMediaNavigations(currentPathDepth: 0, stackID: secondStack)
    XCTAssertNotNil(preloader.peekTask(for: media))

    preloader.reconcilePendingMediaNavigations(currentPathDepth: 0, stackID: firstStack)
    XCTAssertNil(preloader.peekTask(for: media))
  }

  func testHiddenPageReferenceKeepsUpdatingWithoutReplacingActivePage() throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let parentOwner = UUID()
    let childOwner = UUID()
    let parentTarget = PageImageCleanupTarget()
    let childTarget = PageImageCleanupTarget()
    let childURL = try XCTUnwrap(URL(string: "https://example.com/child.jpg"))
    let updatedURL = try XCTUnwrap(URL(string: "https://example.com/updated.jpg"))

    preloader.activatePageImageSnapshot(
      PageImageSnapshot(isComplete: false),
      owner: parentOwner,
      target: parentTarget
    )
    preloader.activatePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [childURL]),
      owner: childOwner,
      target: childTarget
    )

    preloader.updatePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [updatedURL]),
      target: parentTarget
    )

    XCTAssertEqual(parentTarget.currentSnapshot?.mediaPosterURLs, [updatedURL])
    XCTAssertEqual(
      preloader.captureActivePageImageSnapshot()?.mediaPosterURLs,
      [childURL]
    )
  }

  func testPopReleasesLoadingPosterFromMemoryAndKeepsDiskAndCardProcessor() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "loading-poster-pop-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

    let media = MediaInfo(tmdb_id: 760_001, title: "加载海报", type: "电影")
    let loadingURL = try XCTUnwrap(URL(string: "https://example.com/loading-overlay.jpg"))
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.cyan.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 8, height: 8)))
    }
    let loadingProcessor = MediaDetailLoadingPoster.processor
    let cardProcessor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)

    for processor in [loadingProcessor, cardProcessor] {
      try await cache.store(
        image,
        forKey: loadingURL.cacheKey,
        processorIdentifier: processor.identifier
      )
      XCTAssertEqual(
        cache.imageCachedType(
          forKey: loadingURL.cacheKey,
          processorIdentifier: processor.identifier
        ),
        .memory
      )
    }

    let owner = UUID()
    preloader.preload(for: media)
    preloader.pin(key: media.id, owner: owner)
    preloader.releaseAfterPop(
      media: media,
      owner: owner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil,
      loadingPosterURL: loadingURL,
      imageCache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: loadingURL.cacheKey,
        processorIdentifier: loadingProcessor.identifier
      ),
      .disk
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: loadingURL.cacheKey,
        processorIdentifier: cardProcessor.identifier
      ),
      .memory,
      "同一张海报的卡片尺寸应保留，只清加载遮罩那一档"
    )
  }

  func testPageImageSnapshotIncludesSeasonPosters() throws {
    let service = APIService.testingInstance()
    let season = try JSONDecoder().decode(
      TmdbSeason.self,
      from: Data(
        """
        {
          "poster_path": "https://example.com/season-1.jpg",
          "season_number": 1
        }
        """.utf8
      )
    )
    let media = MediaInfo(
      tmdb_id: 760_101,
      title: "分季剧",
      type: "电视剧",
      poster_path: "https://example.com/show.jpg",
      season_info: [season]
    )
    let viewModel = MediaDetailViewModel(detail: media, apiService: service)
    let expected = try XCTUnwrap(
      service.getSeasonPosterURL(
        posterPath: "https://example.com/season-1.jpg",
        mediaPosterPath: "https://example.com/show.jpg"
      )
    )

    XCTAssertTrue(viewModel.pageImageSnapshot.mediaPosterURLs.contains(expected))
  }

  func testPopReleasesSeasonPosterFromMemoryAndKeepsReturnPageCards() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "season-poster-pop-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

    let seasonURL = try XCTUnwrap(URL(string: "https://example.com/season-poster.jpg"))
    let keptURL = try XCTUnwrap(URL(string: "https://example.com/recommend-poster.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.magenta.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 8, height: 8)))
    }

    for url in [seasonURL, keptURL] {
      try await cache.store(
        image,
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      )
    }

    let returnTarget = PageImageCleanupTarget()
    preloader.updatePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [keptURL]),
      target: returnTarget
    )
    preloader.releaseAfterPop(
      media: MediaInfo(tmdb_id: 760_102, title: "分季清理", type: "电视剧"),
      owner: UUID(),
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(mediaPosterURLs: [seasonURL, keptURL]),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: returnTarget,
      imageCache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: seasonURL.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .disk
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: keptURL.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )
  }

  func testAbandonedForegroundHeroIsRemovedOnLateCompletion() async throws {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    sharedService.useImageCache = false

    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "abandoned-hero-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

    let media = MediaInfo(
      tmdb_id: 760_201,
      title: "晚到背景",
      poster_path: nil,
      backdrop_path: "https://example.com/late-hero.jpg"
    )
    let url = try XCTUnwrap(media.imageURLs.backdrop)
    let size = CGSize(width: 32, height: 18)
    let processor = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: false,
      screenScale: UIScreen.main.scale
    )
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.red.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }
    try await cache.store(
      image,
      forKey: url.cacheKey,
      processorIdentifier: processor.identifier
    )

    preloader.discardLoadedBackgroundIfAbandoned(
      url: url,
      detail: media,
      usingPosterAsBackdrop: false,
      isAbandoned: false,
      size: size,
      imageCache: cache
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )

    preloader.discardLoadedBackgroundIfAbandoned(
      url: url,
      detail: media,
      usingPosterAsBackdrop: false,
      isAbandoned: true,
      size: size,
      imageCache: cache
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .disk
    )
  }

  func testAuxiliaryPreloadDoesNotReplaceFocusCandidateAndReleasesOnPop() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let focused = MediaInfo(tmdb_id: 760_301, title: "推荐焦点", type: "电影")
    let douban = MediaInfo(douban_id: "760302", title: "豆瓣详情", type: "电影")
    let tmdb = MediaInfo(tmdb_id: 760_303, title: "TMDB跳转", type: "电影")
    let owner = UUID()

    preloader.preload(for: douban)
    preloader.pin(key: douban.id, owner: owner)
    XCTAssertNotNil(preloader.preloadAuxiliary(for: tmdb, owner: owner))
    XCTAssertFalse(preloader.isFocusCandidate(tmdb.id))
    XCTAssertNotNil(preloader.peekTask(for: tmdb))

    XCTAssertNotNil(preloader.preloadIfNeeded(for: focused))
    XCTAssertTrue(preloader.isFocusCandidate(focused.id))
    XCTAssertNotNil(preloader.peekTask(for: tmdb), "焦点候选替换不应清掉附带预载")
    XCTAssertNotNil(preloader.peekTask(for: douban))

    preloader.releaseAfterPop(
      media: douban,
      owner: owner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil
    )

    XCTAssertNil(preloader.peekTask(for: douban))
    XCTAssertNil(preloader.peekTask(for: tmdb))
    XCTAssertNotNil(preloader.peekTask(for: focused))
    XCTAssertTrue(preloader.isFocusCandidate(focused.id))
  }

  func testAuxiliaryPreloadKeepsTaskWhenAnotherPageOwnsIt() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let parent = MediaInfo(douban_id: "760401", title: "父详情", type: "电影")
    let tmdb = MediaInfo(tmdb_id: 760_402, title: "TMDB子页", type: "电影")
    let parentOwner = UUID()
    let childOwner = UUID()

    preloader.preload(for: parent)
    preloader.pin(key: parent.id, owner: parentOwner)
    XCTAssertNotNil(preloader.preloadAuxiliary(for: tmdb, owner: parentOwner))
    preloader.pin(key: tmdb.id, owner: childOwner)

    preloader.releaseAfterPop(
      media: parent,
      owner: parentOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil
    )

    XCTAssertNil(preloader.peekTask(for: parent))
    XCTAssertNotNil(preloader.peekTask(for: tmdb))

    preloader.releaseAfterPop(
      media: tmdb,
      owner: childOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: nil
    )
    XCTAssertNil(preloader.peekTask(for: tmdb))
  }

  func testPoppedFocusedItemIsSuppressedUntilFocusMoves() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let popped = MediaInfo(tmdb_id: 740_001, title: "刚退出的 A", type: "合集")
    let next = MediaInfo(tmdb_id: 740_002, title: "移动到 B", type: "合集")
    let owner = UUID()
    let returnTarget = PageImageCleanupTarget()
    preloader.updatePageImageSnapshot(PageImageSnapshot(), target: returnTarget)

    preloader.preload(for: popped)
    preloader.pin(key: popped.id, owner: owner)
    preloader.releaseAfterPop(
      media: popped,
      owner: owner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      pageImageCleanupTarget: PageImageCleanupTarget(),
      returnTargetImageCleanupTarget: returnTarget
    )

    XCTAssertTrue(preloader.isFocusPreloadSuppressed(for: popped.id))
    XCTAssertNil(preloader.preloadFocusedCandidateIfNeeded(for: popped))
    XCTAssertNotNil(preloader.preloadIfNeeded(for: popped), "显式点击 A 不应被焦点抑制拦截")

    preloader.focusDidMove(to: next.id)
    XCTAssertFalse(preloader.isFocusPreloadSuppressed(for: popped.id))
  }

  func testCardImageDiffRemovesOnlyUnsharedMemoryEntriesAndKeepsDisk() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "detail-card-diff-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let removedPoster = try XCTUnwrap(URL(string: "https://example.com/removed-poster.jpg"))
    let keptPoster = try XCTUnwrap(URL(string: "https://example.com/kept-poster.jpg"))
    let removedPerson = try XCTUnwrap(URL(string: "https://example.com/removed-person.jpg"))
    let keptPerson = try XCTUnwrap(URL(string: "https://example.com/kept-person.jpg"))
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.orange.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    let mediaProcessor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let personProcessor = PersonCard.imageProcessor()

    for url in [removedPoster, keptPoster] {
      try await cache.store(
        image,
        forKey: url.cacheKey,
        processorIdentifier: mediaProcessor.identifier
      )
    }
    for url in [removedPerson, keptPerson] {
      try await cache.store(
        image,
        forKey: url.cacheKey,
        processorIdentifier: personProcessor.identifier
      )
    }

    preloader.releaseCardImagesAfterPop(
      leaving: PageImageSnapshot(
        mediaPosterURLs: [removedPoster, keptPoster],
        personImageURLs: [removedPerson, keptPerson]
      ),
      returningTo: PageImageSnapshot(
        mediaPosterURLs: [keptPoster],
        personImageURLs: [keptPerson]
      ),
      cache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: removedPoster.cacheKey,
        processorIdentifier: mediaProcessor.identifier
      ),
      .disk
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: keptPoster.cacheKey,
        processorIdentifier: mediaProcessor.identifier
      ),
      .memory
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: removedPerson.cacheKey,
        processorIdentifier: personProcessor.identifier
      ),
      .disk
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: keptPerson.cacheKey,
        processorIdentifier: personProcessor.identifier
      ),
      .memory
    )
  }

  func testUnknownReturnTargetDoesNotRemoveCardImages() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "unknown-return-target-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/unknown-target.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.purple.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    try await cache.store(
      image,
      forKey: url.cacheKey,
      processorIdentifier: processor.identifier
    )

    preloader.releaseCardImagesAfterPop(
      leaving: PageImageSnapshot(mediaPosterURLs: [url]),
      returningTo: nil,
      cache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )
  }

  func testIncompleteReturnTargetDoesNotRemoveCardImages() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "incomplete-return-target-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/incomplete-target.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.green.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    try await cache.store(
      image,
      forKey: url.cacheKey,
      processorIdentifier: processor.identifier
    )

    preloader.releaseCardImagesAfterPop(
      leaving: PageImageSnapshot(mediaPosterURLs: [url]),
      returningTo: PageImageSnapshot(isComplete: false),
      cache: cache
    )

    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )
  }

  func testIncompleteReturnTargetCleansPendingImagesAfterItCompletes() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "completed-return-target-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/deferred-cleanup.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.cyan.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    try await cache.store(
      image,
      forKey: url.cacheKey,
      processorIdentifier: processor.identifier
    )
    let leavingTarget = PageImageCleanupTarget()
    let returnTarget = PageImageCleanupTarget()
    preloader.activatePageImageSnapshot(
      PageImageSnapshot(isComplete: false),
      owner: UUID(),
      target: returnTarget,
      cache: cache
    )

    preloader.forwardCardImageCleanup(
      leaving: PageImageSnapshot(mediaPosterURLs: [url]),
      from: leavingTarget,
      to: returnTarget,
      cache: cache
    )
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )

    preloader.updatePageImageSnapshot(PageImageSnapshot(), target: returnTarget, cache: cache)
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .disk
    )
  }

  func testRapidMultiLevelPopForwardsPendingImagesAndKeepsSharedTargetImage() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "rapid-pop-forwarding-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let childOnly = try XCTUnwrap(URL(string: "https://example.com/child-only.jpg"))
    let parentOnly = try XCTUnwrap(URL(string: "https://example.com/parent-only.jpg"))
    let shared = try XCTUnwrap(URL(string: "https://example.com/shared.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.magenta.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    for url in [childOnly, parentOnly, shared] {
      try await cache.store(
        image,
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      )
    }

    let childTarget = PageImageCleanupTarget()
    let parentTarget = PageImageCleanupTarget()
    let rootTarget = PageImageCleanupTarget()
    preloader.activatePageImageSnapshot(
      PageImageSnapshot(isComplete: false),
      owner: UUID(),
      target: parentTarget,
      cache: cache
    )
    preloader.activatePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [shared]),
      owner: UUID(),
      target: rootTarget,
      cache: cache
    )

    preloader.forwardCardImageCleanup(
      leaving: PageImageSnapshot(mediaPosterURLs: [childOnly, shared]),
      from: childTarget,
      to: parentTarget,
      cache: cache
    )
    preloader.forwardCardImageCleanup(
      leaving: PageImageSnapshot(mediaPosterURLs: [parentOnly, shared]),
      from: parentTarget,
      to: rootTarget,
      cache: cache
    )

    for url in [childOnly, parentOnly] {
      XCTAssertEqual(
        cache.imageCachedType(
          forKey: url.cacheKey,
          processorIdentifier: processor.identifier
        ),
        .disk
      )
    }
    XCTAssertEqual(
      cache.imageCachedType(
        forKey: shared.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )
  }

  func testRetiredPrefetchBatchRemovesWriteBackAfterStoppedStoreCompletes() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = BlockingStoreImageCache(name: "late-prefetch-cleanup-\(UUID().uuidString)")
    defer {
      cache.resumeStore()
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/late-prefetch.jpg"))
    let processor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.red.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    let data = try XCTUnwrap(image.pngData())
    let source = Source.provider(RawImageDataProvider(data: data, cacheKey: url.cacheKey))
    let returnTarget = PageImageCleanupTarget()
    preloader.activatePageImageSnapshot(
      PageImageSnapshot(),
      owner: UUID(),
      target: returnTarget,
      cache: cache
    )
    let batch = PaginatorImagePrefetchBatch(urls: [url])
    var didRunCleanup = false
    batch.retire { urls in
      preloader.enqueuePrefetchedCardImages(
        PageImageSnapshot(mediaPosterURLs: urls),
        returningTo: returnTarget,
        cache: cache
      )
      didRunCleanup = true
    }
    let prefetcher = ImagePrefetcher(
      sources: [source],
      options: [.targetCache(cache), .cacheMemoryOnly, .processor(processor)],
      completionHandler: { _, _, _ in
        Task { @MainActor in batch.complete() }
      }
    )

    prefetcher.start()
    let storeStarted = await Task.detached {
      cache.waitForStoreToStart(timeout: .now() + 2)
    }.value
    XCTAssertTrue(storeStarted, "预取应先进入 Kingfisher 缓存写入阶段")

    prefetcher.stop()
    cache.removeImage(
      forKey: url.cacheKey,
      processorIdentifier: processor.identifier,
      fromMemory: true,
      fromDisk: false,
      completionHandler: nil
    )
    cache.resumeStore()

    try await waitUntil("retired prefetch cleanup") { didRunCleanup }
    XCTAssertNotEqual(
      cache.imageCachedType(
        forKey: url.cacheKey,
        processorIdentifier: processor.identifier
      ),
      .memory
    )
  }

  private static func skipsMemoryCache(_ expiration: StorageExpiration?) -> Bool {
    if case .expired = expiration {
      return true
    }
    return false
  }

  private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(2),
    condition: @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      if clock.now >= deadline {
        XCTFail("Timed out waiting for \(description)")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private final class BlockingStoreImageCache: ImageCache, @unchecked Sendable {
  private let storeStarted = DispatchSemaphore(value: 0)
  private let storeMayContinue = DispatchSemaphore(value: 0)

  override func store(
    _ image: KFCrossPlatformImage,
    original: Data? = nil,
    forKey key: String,
    options: KingfisherParsedOptionsInfo,
    toDisk: Bool = true,
    completionHandler: (@Sendable (CacheStoreResult) -> Void)? = nil
  ) {
    storeStarted.signal()
    storeMayContinue.wait()
    super.store(
      image,
      original: original,
      forKey: key,
      options: options,
      toDisk: toDisk,
      completionHandler: completionHandler
    )
  }

  func waitForStoreToStart(timeout: DispatchTime) -> Bool {
    storeStarted.wait(timeout: timeout) == .success
  }

  func resumeStore() {
    storeMayContinue.signal()
  }
}

private final class MPImageWarmURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var storedRequestCounts: [String: Int] = [:]
  nonisolated(unsafe) private static var finishesImmediately = true

  static func requestCount(for url: URL) -> Int {
    lock.withLock { storedRequestCounts[url.absoluteString, default: 0] }
  }

  static func reset(finishesImmediately: Bool) {
    lock.withLock {
      storedRequestCounts.removeAll()
      Self.finishesImmediately = finishesImmediately
    }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let shouldFinish = Self.lock.withLock {
      if let url = request.url {
        Self.storedRequestCounts[url.absoluteString, default: 0] += 1
      }
      return Self.finishesImmediately
    }
    guard shouldFinish else { return }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "image/jpeg"]
      )
    else {
      return
    }

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data([0xFF]))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class MPImageWarmTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_000)

  var now: Date {
    lock.withLock { value }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock { value = value.addingTimeInterval(interval) }
  }
}
