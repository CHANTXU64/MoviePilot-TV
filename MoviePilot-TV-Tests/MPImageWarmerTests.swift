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
