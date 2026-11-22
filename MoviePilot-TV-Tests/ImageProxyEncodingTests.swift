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
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"TMDB_IMAGE_DOMAIN":"images-b.example","GLOBAL_IMAGE_CACHE":true,"BANGUMI_PROXY_ENABLE":true,"BANGUMI_IMAGE_DOMAIN":"https://bangumi-proxy.example/?url="}"#.utf8
      )
    )
    let bangumiProxyChanged = service.imageConfigurationIdentity

    XCTAssertNotEqual(initial, cacheEnabled)
    XCTAssertNotEqual(cacheEnabled, domainChanged)
    XCTAssertNotEqual(domainChanged, bangumiProxyChanged)
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
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"BANGUMI_PROXY_ENABLE":true,"BANGUMI_IMAGE_DOMAIN":""}"#.utf8)
    )
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

  func testBangumiQueryProxyMatchesWebContract() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"BANGUMI_PROXY_ENABLE":true,"BANGUMI_IMAGE_DOMAIN":"https://image-proxy.example/?url="}"#.utf8
      )
    )

    let rawImage = "https://img.bangumi.tv/pic/cover.jpg?size=large"
    let encodedSource = try XCTUnwrap(encodeURIComponent(rawImage))
    let rewrittenImage = "https://image-proxy.example/?url=\(encodedSource)"
    let url = try XCTUnwrap(service.getPosterImageUrl(posterPath: rawImage))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

    XCTAssertEqual(components.path, "/api/v1/system/img/1")
    XCTAssertEqual(queryItemMap(from: components)["imgurl"], rewrittenImage)
  }

  func testBangumiHostAndPathProxyModesMatchWebContract() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false
    let rawImage = "https://img.bangumi.tv/pic/cover.jpg?size=large"

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"BANGUMI_PROXY_ENABLE":true,"BANGUMI_IMAGE_DOMAIN":"https://image-proxy.example/"}"#.utf8
      )
    )
    var url = try XCTUnwrap(service.getPosterImageUrl(posterPath: rawImage))
    var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(
      queryItemMap(from: components)["imgurl"],
      "https://image-proxy.example/pic/cover.jpg?size=large"
    )

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"BANGUMI_PROXY_ENABLE":true,"BANGUMI_IMAGE_DOMAIN":"https://image-proxy.example/passthrough"}"#.utf8
      )
    )
    url = try XCTUnwrap(service.getPosterImageUrl(posterPath: rawImage))
    components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(
      queryItemMap(from: components)["imgurl"],
      "https://image-proxy.example/passthrough/\(rawImage)"
    )
  }

  func testDisabledBangumiProxyKeepsExpandedOfficialHostDirect() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"BANGUMI_PROXY_ENABLE":false,"BANGUMI_IMAGE_DOMAIN":"https://image-proxy.example/"}"#.utf8
      )
    )

    let rawImage = "https://img.bangumi.tv/pic/cover.jpg"
    XCTAssertEqual(service.getPosterImageUrl(posterPath: rawImage)?.absoluteString, rawImage)
    XCTAssertNil(
      service.getPosterImageUrl(
        posterPath: "https://img.bangumi.tv/img/no_icon_subject.png"
      )
    )
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

    // Bangumi 官方无封面占位图：降尺寸与 fallback 都按同一规则拦截。
    let bangumiMedia = MediaInfo(
      title: "Bangumi",
      poster_path: "https://lain.bgm.tv/img/no_icon_subject.png",
      backdrop_path: nil
    )
    XCTAssertNil(bangumiMedia.imageURLs.poster)
    XCTAssertNil(bangumiMedia.imageURLs.posterFallback)

    // 订阅和订阅分享复用同一入口，不能让原始占位图重新出现在首页或加载遮罩。
    XCTAssertNil(
      service.getSubscribePosterImageUrl(
        poster: "https://lain.bgm.tv/img/no_icon_subject.png"
      )
    )
    XCTAssertNil(
      service.getSubscribePosterImageUrl(
        poster: "https://s4.anilist.co/file/anilistcdn/staff/large/default.jpg"
      )
    )
    XCTAssertNil(
      service.getSubscribePosterImageUrl(
        poster: "https://img9.doubanio.com/view/photo/s_ratio_poster/public/movie_default_large.png"
      )
    )
    XCTAssertNotNil(
      service.getSubscribePosterImageUrl(
        poster: "https://lain.bgm.tv/pic/cover/l/valid.jpg"
      )
    )
  }

  // MARK: - 媒体服务器图片缩略（>= v3.2.6）

  func testMediaServerCardPosterThumbnailFollowsBackendVersionGate() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://moviepilot.local"

    let item = MediaServerPlayItem(
      id: "abc", title: "剧集", image: "http://emby.local/Items/abc/Images/Primary?tag=main",
      server_type: .emby)
    // 请求宽度与卡片降采样后保留的像素一致，不下载会被 Kingfisher 扔掉的像素。
    let cardWidth = MediaCard.posterThumbnailMaxWidth(for: MediaCard.defaultPosterSize)
    XCTAssertEqual(cardWidth, 384)

    // 新行为版本限制：低于起始版本、读不出或无法解析时不追加参数，继续取原图。
    for version in [nil, "custom", "v3.2.5", "v3.2.5-1", "v3.0.10"] as [String?] {
      service.settings = GlobalSettings(BACKEND_VERSION: version)
      let url = try XCTUnwrap(item.imageURLs(cardPosterPixelWidth: cardWidth).image)
      XCTAssertNil(thumbnailQuery(url)["maxWidth"], "\(version ?? "nil") 不该请求缩略图")
    }

    for version in ["v3.2.6", "v3.2.6-1", "v3.2.7", "v4.0.0"] {
      service.settings = GlobalSettings(BACKEND_VERSION: version)
      let url = try XCTUnwrap(item.imageURLs(cardPosterPixelWidth: cardWidth).image)
      let query = thumbnailQuery(url)
      XCTAssertEqual(query["maxWidth"], "384", version)
      XCTAssertEqual(query["imgurl"], item.image, "缩略参数不能改写原始地址")
    }
  }

  func testMediaServerCardPosterClampsThumbnailWidthToBackendRange() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://moviepilot.local"
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")
    let rawImage = "http://emby.local/Items/abc/Images/Primary"

    for (pixelWidth, expected) in [(5000, "2048"), (2048, "2048"), (1, "1")] {
      let url = try XCTUnwrap(
        service.getMediaServerPosterImageURL(
          image: rawImage, useCookies: true, cardPosterPixelWidth: pixelWidth))
      let query = thumbnailQuery(url)
      XCTAssertEqual(query["maxWidth"], expected)
      XCTAssertEqual(query["use_cookies"], "true", "缩略参数不能挤掉媒体服务器 cookie 标记")
    }

    for pixelWidth in [0, -1] {
      let url = try XCTUnwrap(
        service.getMediaServerPosterImageURL(
          image: rawImage, useCookies: nil, cardPosterPixelWidth: pixelWidth))
      XCTAssertNil(thumbnailQuery(url)["maxWidth"])
    }
  }

  func testMediaServerDetailEntryPosterKeepsOriginalAndDistinctCacheKey() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://moviepilot.local"
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")

    let item = MediaServerPlayItem(
      id: "abc", title: "剧集", image: "http://emby.local/Items/abc/Images/Primary",
      server_type: .emby)
    // 详情入口把同一个 URL 当冷加载全屏背景兜底，默认不传像素宽度就必须是原图。
    let entry = try XCTUnwrap(item.imageURLs().image)
    let card = try XCTUnwrap(item.imageURLs(cardPosterPixelWidth: 384).image)

    XCTAssertNil(thumbnailQuery(entry)["maxWidth"])
    XCTAssertEqual(thumbnailQuery(card)["maxWidth"], "384")
    XCTAssertNotEqual(entry, card, "原图与缩略图必须是不同缓存键，避免旧原图被当成缩略图复用")
  }

  func testImageConfigurationIdentityTracksThumbnailGate() throws {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "http://images.local"
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.5")
    let unsupported = service.imageConfigurationIdentity

    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")
    let supported = service.imageConfigurationIdentity
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.7")
    let newer = service.imageConfigurationIdentity

    XCTAssertNotEqual(unsupported, supported, "跨过缩略门禁要让已建卡片重算图片 URL")
    XCTAssertEqual(supported, newer, "同样支持缩略的版本之间不该无谓刷新图片")
  }

  func testThumbnailParametersNeverReachNonMediaServerImagePaths() throws {
    let service = APIService.shared
    let snapshot = ImageProxyServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")

    // 缩略参数只作用于经代理的 Emby/Jellyfin 图片；豆瓣、TMDB 外链不该被追加。
    let douban = try XCTUnwrap(
      service.getPosterImageUrl(posterPath: "https://img1.doubanio.com/view/photo/p123.jpg"))
    let tmdb = try XCTUnwrap(
      service.getPosterImageUrl(posterPath: "https://image.tmdb.org/t/p/original/poster.jpg"))
    XCTAssertNil(thumbnailQuery(douban)["maxWidth"])
    XCTAssertNil(thumbnailQuery(tmdb)["maxWidth"])
  }

  private func thumbnailQuery(_ url: URL) -> [String: String] {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
    return queryItemMap(from: components)
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
  let settings: GlobalSettings?

  static func capture(service: APIService) -> ImageProxyServiceSnapshot {
    ImageProxyServiceSnapshot(
      baseURL: service.baseURL,
      useImageCache: service.useImageCache,
      settings: service.settings
    )
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.settings = settings
    service.useImageCache = useImageCache
  }
}
