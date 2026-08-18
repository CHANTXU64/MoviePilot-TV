import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class ImageProxyEncodingTests: XCTestCase {
  func testImageConfigurationIdentityTracksURLInputs() throws {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "http://images-a.local"
    service.useImageCache = false
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"TMDB_IMAGE_DOMAIN":"images-a.example"}"#.utf8)
    )
    let initial = service.imageConfigurationIdentity

    service.useImageCache = true
    let cacheEnabled = service.imageConfigurationIdentity
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"TMDB_IMAGE_DOMAIN":"images-b.example","GLOBAL_IMAGE_CACHE":true}"#.utf8)
    )
    let domainChanged = service.imageConfigurationIdentity

    XCTAssertNotEqual(initial, cacheEnabled)
    XCTAssertNotEqual(cacheEnabled, domainChanged)
  }

  func testExistingMediaRecomputesPosterAfterImageConfigurationChanges() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false
    let media = MediaInfo(
      title: "Dynamic Image",
      poster_path: "https://image.tmdb.org/t/p/original/poster.jpg"
    )

    let uncached = try XCTUnwrap(media.imageURLs.poster)
    service.useImageCache = true
    let cached = try XCTUnwrap(media.imageURLs.poster)

    XCTAssertNotEqual(uncached, cached)
    XCTAssertEqual(cached.path, "/api/v1/system/cache/image")
  }

  func testMediaServerPosterProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"

    let rawImage =
      "http://emby.local/Items/abc/Images/Primary?tag=main&quality=90#poster"
    let url = try XCTUnwrap(
      service.getMediaServerPosterImageURL(image: rawImage, useCookies: true)
    )

    let queryItems = try assertProxyURL(
      url,
      path: "/api/v1/system/img/0",
      queryName: "imgurl",
      rawImage: rawImage,
      leakedKeys: ["quality"],
      encodedTail: "%26quality%3D90%23poster"
    )
    XCTAssertEqual(queryItems["use_cookies"], "true")
  }

  func testDoubanPosterProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false

    let rawImage =
      "https://img1.doubanio.com/view/photo/s_ratio_poster/public/p123.jpg?size=w500&token=abc#cover"
    let url = try XCTUnwrap(service.getPosterImageUrl(posterPath: rawImage))

    _ = try assertProxyURL(
      url,
      path: "/api/v1/system/img/0",
      queryName: "imgurl",
      rawImage: rawImage,
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dabc%23cover"
    )
  }

  func testDoubanPosterUsesCacheWhenGlobalImageCacheIsEnabled() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://img1.doubanio.com/view/photo/s_ratio_poster/public/p123.jpg?size=w500&token=abc#cover"
    let url = try XCTUnwrap(service.getPosterImageUrl(posterPath: rawImage))

    _ = try assertProxyURL(
      url,
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawImage,
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dabc%23cover"
    )
  }

  func testImageCacheProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://image.tmdb.org/t/p/original/backdrop.jpg?token=abc&width=1280#still"
    let url = try XCTUnwrap(service.getBackdropImageUrl(backdropPath: rawImage))

    _ = try assertProxyURL(
      url,
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawImage,
      leakedKeys: ["width"],
      encodedTail: "%26width%3D1280%23still"
    )
  }

  func testSubscriptionPosterProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://poster.local/subscription.jpg?season=1&revision=2#main"
    let url = try XCTUnwrap(service.getSubscribePosterImageUrl(poster: rawImage))

    _ = try assertProxyURL(
      url,
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawImage,
      leakedKeys: ["revision"],
      encodedTail: "%26revision%3D2%23main"
    )
  }

  func testPersonImageProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://people.local/avatar.jpg?size=large&token=person#headshot"
    let url = try XCTUnwrap(
      service.getPersonImageURL(
        source: "anilist",
        profilePath: nil,
        avatar: nil,
        images: BangumiImages(
          large: rawImage,
          common: nil,
          medium: nil,
          small: nil,
          grid: nil
        )
      )
    )

    _ = try assertProxyURL(
      url,
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawImage,
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dperson%23headshot"
    )
  }

  func testBangumiPersonImageUsesBangumiProxyBeforeGlobalCache() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://lain.bgm.tv/pic/crt/m/person.jpg?size=medium&token=person#headshot"
    let url = try XCTUnwrap(
      service.getPersonImageURL(
        source: "bangumi",
        profilePath: nil,
        avatar: nil,
        images: BangumiImages(
          large: nil,
          common: nil,
          medium: rawImage,
          small: nil,
          grid: nil
        )
      )
    )

    let queryItems = try assertProxyURL(
      url,
      path: "/api/v1/system/img/1",
      queryName: "imgurl",
      rawImage: rawImage,
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dperson%23headshot"
    )
    XCTAssertEqual(queryItems["cache"], "true")
  }

  func testModelComputedImageURLsPreserveNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    let rawPoster = "https://poster.local/movie.jpg?lang=zh&token=poster#cover"
    let rawBackdrop = "https://poster.local/backdrop.jpg?size=wide&token=backdrop#still"
    let media = MediaInfo(title: "Regression", poster_path: rawPoster, backdrop_path: rawBackdrop)

    _ = try assertProxyURL(
      try XCTUnwrap(media.imageURLs.poster),
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawPoster.replacingOccurrences(of: "original", with: "w500"),
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dposter%23cover"
    )

    _ = try assertProxyURL(
      try XCTUnwrap(media.imageURLs.backdrop),
      path: "/api/v1/system/cache/image",
      queryName: "url",
      rawImage: rawBackdrop,
      leakedKeys: ["token"],
      encodedTail: "%26token%3Dbackdrop%23still"
    )
  }

  func testPosterFallbackKeepsOriginalURLWhenDownsizedVersionIsRewritten() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = true

    // TMDB 标准路径：降尺寸为 w500，fallback 保留 original 原始图。
    let tmdbMedia = MediaInfo(
      title: "TMDB",
      poster_path: "https://image.tmdb.org/t/p/original/poster.jpg",
      backdrop_path: nil
    )
    let tmdbPoster = try XCTUnwrap(tmdbMedia.imageURLs.poster)
    let tmdbFallback = try XCTUnwrap(tmdbMedia.imageURLs.posterFallback)
    XCTAssertEqual(
      try queryItemMap(
        from: try XCTUnwrap(
          URLComponents(url: tmdbPoster, resolvingAgainstBaseURL: false)))["url"],
      "https://image.tmdb.org/t/p/w500/poster.jpg"
    )
    XCTAssertEqual(
      try queryItemMap(
        from: try XCTUnwrap(
          URLComponents(url: tmdbFallback, resolvingAgainstBaseURL: false)))["url"],
      "https://image.tmdb.org/t/p/original/poster.jpg"
    )

    // 第三方 URL 的 host 含 original：降尺寸会被误改写，fallback 必须保留原始 URL。
    let thirdPartyMedia = MediaInfo(
      title: "Third",
      poster_path: "https://original-media.cdn.com/poster.jpg",
      backdrop_path: nil
    )
    let thirdPoster = try XCTUnwrap(thirdPartyMedia.imageURLs.poster)
    let thirdFallback = try XCTUnwrap(thirdPartyMedia.imageURLs.posterFallback)
    XCTAssertTrue(thirdPoster.absoluteString.contains("w500-media.cdn.com"))
    XCTAssertEqual(
      try queryItemMap(
        from: try XCTUnwrap(
          URLComponents(url: thirdFallback, resolvingAgainstBaseURL: false)))["url"],
      "https://original-media.cdn.com/poster.jpg"
    )

    // 豆瓣默认图：降尺寸与 fallback 都按同一规则拦截。
    let doubanMedia = MediaInfo(
      title: "Douban",
      poster_path: "https://img9.doubanio.com/view/photo/m/public/movie_default.jpg",
      backdrop_path: nil
    )
    XCTAssertNil(doubanMedia.imageURLs.poster)
    XCTAssertNil(doubanMedia.imageURLs.posterFallback)
  }

  private func assertProxyURL(
    _ url: URL,
    path: String,
    queryName: String,
    rawImage: String,
    leakedKeys: [String],
    encodedTail: String
  ) throws -> [String: String] {
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = queryItemMap(from: components)

    XCTAssertEqual(components.scheme, "http")
    XCTAssertEqual(components.host, "moviepilot.local")
    XCTAssertEqual(components.path, path)
    XCTAssertNil(components.fragment)
    XCTAssertEqual(queryItems[queryName], rawImage)
    for key in leakedKeys {
      XCTAssertNil(queryItems[key])
    }
    XCTAssertTrue(url.absoluteString.contains(encodedTail))

    return queryItems
  }

  private func queryItemMap(from components: URLComponents) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
  }
}

@MainActor
private struct ImageProxyServiceSnapshot {
  let baseURL: String
  let useImageCache: Bool

  static func capture(service: APIService) -> ImageProxyServiceSnapshot {
    ImageProxyServiceSnapshot(baseURL: service.baseURL, useImageCache: service.useImageCache)
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.useImageCache = useImageCache
  }
}
