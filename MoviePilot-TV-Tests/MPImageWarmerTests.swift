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

  func testDefaultKingfisherMemoryCachePolicyUses250MiBForFiveMinutes() {
    let cache = ImageCache(name: "memory-cache-policy-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

    KingfisherCachePolicy.apply(to: cache)

    XCTAssertEqual(cache.memoryStorage.config.totalCostLimit, 250 * 1024 * 1024)
    guard case .seconds(let seconds) = cache.memoryStorage.config.expiration else {
      XCTFail("Expected a seconds-based memory cache expiration")
      return
    }
    XCTAssertEqual(seconds, 300)
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
    let stackID = UUID()
    preloader.acquireNavigation(for: media, owner: owner)
    preloader.releaseNavigation(
      for: media,
      owner: owner,
      stackID: stackID,
      size: size,
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
    let preparedAsCandidate = task.shouldWarmBackgroundImage()

    XCTAssertTrue(preparedAsCandidate)
    XCTAssertTrue(
      task.shouldReleasePreparedBackgroundFromMemory(preparedAsCandidate: preparedAsCandidate)
    )
    task.markPreparedBackgroundForReleaseAfterCompletion()
    XCTAssertTrue(task.shouldRemoveRetrievedBackgroundAfterCompletion)

    task.cancelImageWarm()

    XCTAssertFalse(task.shouldWarmBackgroundImage())
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
    let stackID = UUID()

    preloader.preload(for: media)
    preloader.pin(key: media.id, owner: firstOwner)
    preloader.pin(key: media.id, owner: secondOwner)

    preloader.releaseNavigation(
      for: media,
      owner: firstOwner,
      stackID: stackID,
      size: .zero
    )
    XCTAssertNotNil(preloader.peekTask(for: media))

    preloader.releaseNavigation(
      for: media,
      owner: secondOwner,
      stackID: stackID,
      size: .zero
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

  func testLoadingPosterReleaseKeepsDiskAndCardProcessor() async throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let cache = ImageCache(name: "loading-poster-pop-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }

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

    preloader.removeLoadingPosterFromMemory(url: loadingURL, imageCache: cache)

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
    let stackID = UUID()

    preloader.preload(for: douban)
    preloader.pin(key: douban.id, owner: owner)
    XCTAssertNotNil(preloader.preloadAuxiliary(for: tmdb, owner: owner))
    XCTAssertFalse(preloader.isFocusCandidate(tmdb.id))
    XCTAssertNotNil(preloader.peekTask(for: tmdb))

    XCTAssertNotNil(preloader.preloadIfNeeded(for: focused))
    XCTAssertTrue(preloader.isFocusCandidate(focused.id))
    XCTAssertNotNil(preloader.peekTask(for: tmdb), "焦点候选替换不应清掉附带预载")
    XCTAssertNotNil(preloader.peekTask(for: douban))

    preloader.releaseNavigation(
      for: douban,
      owner: owner,
      stackID: stackID,
      size: .zero
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
    let stackID = UUID()

    preloader.preload(for: parent)
    preloader.pin(key: parent.id, owner: parentOwner)
    XCTAssertNotNil(preloader.preloadAuxiliary(for: tmdb, owner: parentOwner))
    preloader.pin(key: tmdb.id, owner: childOwner)

    preloader.releaseNavigation(
      for: parent,
      owner: parentOwner,
      stackID: stackID,
      size: .zero
    )

    XCTAssertNil(preloader.peekTask(for: parent))
    XCTAssertNotNil(preloader.peekTask(for: tmdb))

    preloader.releaseNavigation(
      for: tmdb,
      owner: childOwner,
      stackID: stackID,
      size: .zero
    )
    XCTAssertNil(preloader.peekTask(for: tmdb))
  }

  func testAuxiliaryPreloadKeepsSharedTaskUntilAllOwnersAndCandidateRelease() throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let firstParent = MediaInfo(douban_id: "760501", title: "父详情一", type: "电影")
    let secondParent = MediaInfo(douban_id: "760502", title: "父详情二", type: "电影")
    let shared = MediaInfo(tmdb_id: 760_503, title: "共享 TMDB 预载", type: "电影")
    let replacement = MediaInfo(tmdb_id: 760_504, title: "替换预载", type: "电影")
    let nextFocused = MediaInfo(tmdb_id: 760_505, title: "新焦点", type: "电影")
    let firstOwner = UUID()
    let secondOwner = UUID()
    let stackID = UUID()

    preloader.preload(for: firstParent)
    preloader.pin(key: firstParent.id, owner: firstOwner)
    preloader.preload(for: secondParent)
    preloader.pin(key: secondParent.id, owner: secondOwner)

    let sharedTask = try XCTUnwrap(
      preloader.preloadAuxiliary(for: shared, owner: firstOwner)
    )
    XCTAssertTrue(preloader.preloadAuxiliary(for: shared, owner: secondOwner) === sharedTask)
    XCTAssertTrue(preloader.preloadIfNeeded(for: shared) === sharedTask)

    XCTAssertNotNil(preloader.preloadAuxiliary(for: replacement, owner: firstOwner))
    XCTAssertTrue(preloader.peekTask(for: shared) === sharedTask)

    preloader.releaseNavigation(
      for: firstParent,
      owner: firstOwner,
      stackID: stackID,
      size: .zero
    )
    XCTAssertTrue(preloader.peekTask(for: shared) === sharedTask)
    XCTAssertNil(preloader.peekTask(for: replacement))

    preloader.releaseNavigation(
      for: secondParent,
      owner: secondOwner,
      stackID: stackID,
      size: .zero
    )
    XCTAssertTrue(preloader.peekTask(for: shared) === sharedTask)
    XCTAssertTrue(preloader.isFocusCandidate(shared.id))

    XCTAssertNotNil(preloader.preloadIfNeeded(for: nextFocused))
    XCTAssertNil(preloader.peekTask(for: shared))
    XCTAssertTrue(preloader.isFocusCandidate(nextFocused.id))
  }

  func testPoppedFocusedItemIsSuppressedUntilFocusMoves() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let popped = MediaInfo(tmdb_id: 740_001, title: "刚退出的 A", type: "合集")
    let next = MediaInfo(tmdb_id: 740_002, title: "移动到 B", type: "合集")
    let owner = UUID()
    let stackID = UUID()

    preloader.preload(for: popped)
    preloader.pin(key: popped.id, owner: owner)
    preloader.releaseNavigation(
      for: popped,
      owner: owner,
      stackID: stackID,
      size: .zero
    )

    XCTAssertTrue(preloader.isFocusPreloadSuppressed(for: popped.id, stackID: stackID))
    XCTAssertNil(preloader.preloadFocusedCandidateIfNeeded(for: popped, stackID: stackID))
    XCTAssertNotNil(preloader.preloadIfNeeded(for: popped), "显式点击 A 不应被焦点抑制拦截")

    preloader.focusDidMove(to: next.id, stackID: stackID)
    XCTAssertFalse(preloader.isFocusPreloadSuppressed(for: popped.id, stackID: stackID))
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
