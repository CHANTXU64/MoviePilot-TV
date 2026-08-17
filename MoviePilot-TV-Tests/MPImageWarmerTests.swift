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

  func testBackgroundProcessorsKeepFocusPreloadOutOfSecondPageBlur() {
    let size = CGSize(width: 1920, height: 1080)
    let firstPage = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: false
    )
    let secondPage = MediaDetailBackgroundImage.secondPageProcessor(for: size)
    let posterFallback = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: true
    )

    XCTAssertTrue(firstPage.identifier.contains("DownsamplingImageProcessor"))
    XCTAssertFalse(firstPage.identifier.contains("BlurImageProcessor"))
    XCTAssertNotEqual(firstPage.identifier, secondPage.identifier)
    XCTAssertEqual(posterFallback.identifier, secondPage.identifier)

    let downsamplingRange = try? XCTUnwrap(
      secondPage.identifier.range(of: "DownsamplingImageProcessor")
    )
    let blurRange = try? XCTUnwrap(secondPage.identifier.range(of: "BlurImageProcessor"))
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
    XCTAssertFalse(heroOptions.cacheOriginalImage)
  }

  func testOnlyPreparedSecondPageBackgroundIsEligibleForNavigationRelease() {
    let cases: [(Bool, Bool, Bool, Bool)] = [
      (true, false, true, true),
      (false, false, true, false),
      (true, true, true, false),
      (true, false, false, false),
    ]

    for (enabled, usesPoster, prepared, expected) in cases {
      XCTAssertEqual(
        MediaDetailBackgroundImage.shouldReleaseForNavigation(
          memoryOptimizationEnabled: enabled,
          usingPosterAsBackdrop: usesPoster,
          secondPageBackgroundPrepared: prepared
        ),
        expected
      )
    }
  }

  func testBackgroundAppearanceRefreshesUnmountedOrCancelledPreparation() {
    let cases = [
      (isMounted: false, wasCancelled: false, expected: true),
      (isMounted: false, wasCancelled: true, expected: true),
      (isMounted: true, wasCancelled: true, expected: true),
      (isMounted: true, wasCancelled: false, expected: false),
    ]

    for item in cases {
      XCTAssertEqual(
        MediaDetailView.shouldRefreshBackground(
          isMounted: item.isMounted,
          preparationWasCancelled: item.wasCancelled
        ),
        item.expected
      )
    }
  }

  func testReleasingDetailBackgroundsKeepsBothOnDisk() async throws {
    let cache = ImageCache(name: "released-detail-backgrounds-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/released-backdrop.jpg"))
    let size = CGSize(width: 32, height: 18)
    let processors = [
      MediaDetailBackgroundImage.heroProcessor(
        for: size,
        usingPosterAsBackdrop: false
      ),
      MediaDetailBackgroundImage.secondPageProcessor(for: size),
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
      cache: cache
    )
    MediaDetailBackgroundImage.removeSecondPageBackgroundFromMemory(
      for: url,
      size: size,
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

  func testSecondPageBlurReusesDownsampledHeroWithoutOriginalCache() throws {
    let cache = ImageCache(name: "second-page-background-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/backdrop.jpg"))
    let size = CGSize(width: 32, height: 18)
    let firstPageProcessor = MediaDetailBackgroundImage.heroProcessor(
      for: size,
      usingPosterAsBackdrop: false
    )
    let secondPageProcessor = MediaDetailBackgroundImage.secondPageProcessor(for: size)
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.blue.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }
    cache.store(
      image,
      forKey: url.cacheKey,
      processorIdentifier: firstPageProcessor.identifier,
      toDisk: false
    )

    XCTAssertTrue(
      MediaDetailBackgroundImage.cacheSecondPageImage(
        from: image,
        for: url,
        size: size,
        scaleFactor: 1,
        cache: cache
      )
    )

    XCTAssertTrue(
      cache.isCached(
        forKey: url.cacheKey,
        processorIdentifier: firstPageProcessor.identifier
      )
    )
    XCTAssertTrue(
      cache.isCached(
        forKey: url.cacheKey,
        processorIdentifier: secondPageProcessor.identifier
      )
    )
    XCTAssertFalse(
      cache.isCached(
        forKey: url.cacheKey,
        processorIdentifier: DefaultImageProcessor.default.identifier
      )
    )
  }

  func testCancelledSecondPageBlurIsNotCached() async throws {
    let cache = ImageCache(name: "cancelled-second-page-background-\(UUID().uuidString)")
    defer {
      cache.clearMemoryCache()
      cache.clearDiskCache()
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/cancelled-backdrop.jpg"))
    let size = CGSize(width: 32, height: 18)
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.blue.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }

    let task = Task.detached {
      try? await Task.sleep(for: .seconds(1))
      return MediaDetailBackgroundImage.cacheSecondPageImage(
        from: image,
        for: url,
        size: size,
        scaleFactor: 1,
        cache: cache
      )
    }
    task.cancel()

    let didCache = await task.value
    XCTAssertFalse(didCache)
    XCTAssertFalse(
      cache.isCached(
        forKey: url.cacheKey,
        processorIdentifier: MediaDetailBackgroundImage.secondPageProcessor(for: size).identifier
      )
    )
  }

  func testOpeningDetailDisablesFutureBackgroundWarm() {
    let task = MediaPreloadTask(partialMedia: MediaInfo(tmdb_id: 1, type: "电影"))

    XCTAssertTrue(task.shouldWarmBackgroundImage(memoryOptimizationEnabled: true))
    XCTAssertFalse(task.shouldWarmBackgroundImage(memoryOptimizationEnabled: false))

    task.cancelImageWarm()

    XCTAssertFalse(task.shouldWarmBackgroundImage(memoryOptimizationEnabled: true))
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

    preloader.preload(for: media)
    preloader.pin(key: media.id, owner: firstOwner)
    preloader.pin(key: media.id, owner: secondOwner)

    preloader.releaseAfterPop(
      media: media,
      owner: firstOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      returnTargetImageSnapshot: nil
    )
    XCTAssertNotNil(preloader.peekTask(for: media))

    preloader.releaseAfterPop(
      media: media,
      owner: secondOwner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      returnTargetImageSnapshot: nil
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
      returnTargetImageSnapshot: nil
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

  func testOnlyActivePageCanUpdateReturnImageSnapshot() throws {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let activeOwner = UUID()
    let hiddenOwner = UUID()
    let firstURL = try XCTUnwrap(URL(string: "https://example.com/active.jpg"))
    let hiddenURL = try XCTUnwrap(URL(string: "https://example.com/hidden.jpg"))
    let updatedURL = try XCTUnwrap(URL(string: "https://example.com/updated.jpg"))

    preloader.activatePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [firstURL]),
      owner: activeOwner
    )
    preloader.updateActivePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [hiddenURL]),
      owner: hiddenOwner
    )
    XCTAssertEqual(
      preloader.captureActivePageImageSnapshot()?.mediaPosterURLs,
      [firstURL]
    )

    preloader.updateActivePageImageSnapshot(
      PageImageSnapshot(mediaPosterURLs: [updatedURL]),
      owner: activeOwner
    )
    XCTAssertEqual(
      preloader.captureActivePageImageSnapshot()?.mediaPosterURLs,
      [updatedURL]
    )
  }

  func testPoppedFocusedItemIsSuppressedUntilFocusMoves() {
    let preloader = MediaPreloader(apiService: .testingInstance())
    defer { preloader.clearAll() }
    let popped = MediaInfo(tmdb_id: 740_001, title: "刚退出的 A", type: "合集")
    let next = MediaInfo(tmdb_id: 740_002, title: "移动到 B", type: "合集")
    let owner = UUID()

    preloader.preload(for: popped)
    preloader.pin(key: popped.id, owner: owner)
    preloader.releaseAfterPop(
      media: popped,
      owner: owner,
      size: .zero,
      leavingImageSnapshot: PageImageSnapshot(),
      returnTargetImageSnapshot: PageImageSnapshot()
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
