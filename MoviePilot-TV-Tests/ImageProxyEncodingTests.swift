import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class ImageProxyEncodingTests: XCTestCase {
  func testMediaServerPosterProxyPreservesNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"

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

    service.baseURL = "http://moviepilot.local"
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

    service.baseURL = "http://moviepilot.local"
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

    service.baseURL = "http://moviepilot.local"
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

    service.baseURL = "http://moviepilot.local"
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

    service.baseURL = "http://moviepilot.local"
    service.useImageCache = true

    let rawImage =
      "https://people.local/avatar.jpg?size=large&token=person#headshot"
    let url = try XCTUnwrap(
      service.getPersonImageURL(
        source: nil,
        profilePath: rawImage,
        avatar: nil,
        images: nil
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

  func testModelComputedImageURLsPreserveNestedQueryAndFragment() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"
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
    service.baseURL = baseURL
    service.useImageCache = useImageCache
  }
}
