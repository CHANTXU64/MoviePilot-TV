import Foundation
import XCTest

@testable import MoviePilot_TV

/// F-051 / F-055 回归：人物「有没有可显示头像」只有一套判据。
///
/// 此前有三份实现互不一致：`StaffManager.hasAvatar` 看「任意原始字段是否存在」
/// （`profile_path`/`avatar`/`images` 任一非空）、搜索最佳结果准入看 TMDB 专属 `profile_path`、
/// 而卡片渲染只看 `Person.imageURLs.profile`（按 source 严格挑选真正能渲染的 URL）。
/// 三者对同一个 Person 会得出不同结论，于是出现「只有占位图的人排在真有头像的人前面」
/// 与「有头像的人被排除出最佳结果」。本次收敛为 `Person.hasUsableProfileImage`。
///
/// 注意二者的**不对称性**：旧判据为真时新判据可能为假（占位图/字段白有），
/// 但反过来不会 —— 原始字段全空时 source-aware 解析必然为 nil。因此本次修复只会
/// 把人员从「有头像」移到「无头像」，不会凭空造出头像。
@MainActor
final class PersonProfileImageAvailabilityTests: XCTestCase {
  private var snapshot: PersonImageServiceSnapshot!

  override func setUp() {
    super.setUp()
    let service = APIService.shared
    snapshot = PersonImageServiceSnapshot.capture(service: service)
    service.baseURLForTesting = "http://person-image-tests.local"
    // 关闭图片缓存，让解析结果只由 source 判定决定，便于断言绝对 URL。
    service.useImageCache = false
  }

  override func tearDown() {
    snapshot.restore(to: APIService.shared)
    super.tearDown()
  }

  private func person(_ json: String) throws -> Person {
    try JSONDecoder().decode(Person.self, from: Data(json.utf8))
  }

  // MARK: - 叶子判据与 source-aware 解析同源

  func testBangumiOnlyLargeIsNotUsableEvenWithProfilePath() throws {
    // Bangumi 解析只认 `images.medium`；同时带一个 TMDB 风格的 `profile_path`，
    // 旧判据（profile_path 非空）会判为有头像，实际渲染只能是占位图。
    let subject = try person(
      """
      {
        "source": "bangumi", "id": 321, "name": "只有大图的人",
        "profile_path": "/only-large.jpg",
        "images": { "large": "https://lain.bgm.tv/pic/crt/l/ab/cd/321.jpg" }
      }
      """)

    XCTAssertNil(subject.imageURLs.profile, "只有 large 时不应解析出可渲染头像")
    XCTAssertFalse(subject.hasUsableProfileImage)
  }

  func testDoubanDefaultAvatarIsNotUsableEvenWithProfilePath() throws {
    // 豆瓣默认头像由 `isDefaultPlaceholderImageURL` 拦下，属于「字段有值但渲染是占位图」。
    let subject = try person(
      """
      {
        "source": "douban", "id": 7, "name": "豆瓣默认头像",
        "profile_path": "/default.jpg",
        "avatar": "https://img1.doubanio.com/icon/personage-default.jpg"
      }
      """)

    XCTAssertNil(subject.imageURLs.profile)
    XCTAssertFalse(subject.hasUsableProfileImage)
  }

  func testTMDBEmptyImagesIsNotUsable() throws {
    // `images` 存在但 TMDB 解析根本不读它；旧判据 `images != nil` 会误判为有头像。
    let subject = try person(
      """
      {
        "source": "themoviedb", "id": 550, "name": "空 images",
        "profile_path": null,
        "images": {}
      }
      """)

    XCTAssertNil(subject.imageURLs.profile)
    XCTAssertFalse(subject.hasUsableProfileImage)
  }

  func testUnsupportedSourceIsNotUsableEvenWithAllRawFields() throws {
    for source in ["tvdb", "unknown-vendor"] {
      let subject = try person(
        """
        {
          "source": "\(source)", "id": 1, "name": "未支持来源",
          "profile_path": "/x.jpg",
          "avatar": "https://img1.doubanio.com/view/personage/s/public/x.jpg"
        }
        """)
      XCTAssertFalse(subject.hasUsableProfileImage, "未支持来源不应解析出头像：\(source)")
    }
  }

  func testDoubanAvatarIsUsableWithoutProfilePath() throws {
    // 正向：F-055 里被错误排除的那类人物。
    let subject = try person(
      """
      {
        "source": "douban", "id": 7, "name": "豆瓣头像",
        "profile_path": null,
        "avatar": "https://img1.doubanio.com/view/personage/s/public/abc123.jpg"
      }
      """)

    XCTAssertNotNil(subject.imageURLs.profile)
    XCTAssertTrue(subject.hasUsableProfileImage)
  }

  func testAnilistAvatarOnlyIsUsable() throws {
    let subject = try person(
      """
      {
        "source": "anilist", "id": 95012, "name": "AniList 头像",
        "profile_path": null,
        "avatar": "https://s4.anilist.co/file/anilistcdn/character/large/b95012-abc.jpg"
      }
      """)

    XCTAssertTrue(subject.hasUsableProfileImage)
  }

  // MARK: - F-051 出口：职员排序

  /// 同职位（同优先级）的新增职员里，只有占位图的人不得排在真有头像的人前面。
  func testCrewSortPrefersRenderableAvatarOverRawFieldPresence() throws {
    let placeholderOnly = try person(
      """
      {
        "source": "bangumi", "id": 1, "name": "占位图导演", "job": "Director",
        "profile_path": "/only-large.jpg",
        "images": { "large": "https://lain.bgm.tv/pic/crt/l/ab/cd/1.jpg" }
      }
      """)
    let renderable = try person(
      """
      {
        "source": "douban", "id": 2, "name": "有头像导演", "job": "Director",
        "profile_path": null,
        "avatar": "https://img1.doubanio.com/view/personage/s/public/abc123.jpg"
      }
      """)

    // 占位图的人先进入批次，旧实现会因「原始字段存在」把他判为有头像并保留在前。
    let crew = StaffManager.processCrew(persons: [placeholderOnly, renderable])

    XCTAssertEqual(crew.map(\.name), ["有头像导演", "占位图导演"])
  }

  /// 阴性对照：头像排序不得越过职位优先级。
  func testCrewSortKeepsJobPriorityDominantOverAvatar() throws {
    let lowerPriorityWithAvatar = try person(
      """
      {
        "source": "douban", "id": 3, "name": "有头像的次要职位", "job": "Producer",
        "avatar": "https://img1.doubanio.com/view/personage/s/public/def456.jpg"
      }
      """)
    let higherPriorityPlaceholder = try person(
      """
      {
        "source": "bangumi", "id": 4, "name": "占位图导演", "job": "Director",
        "images": { "large": "https://lain.bgm.tv/pic/crt/l/ab/cd/4.jpg" }
      }
      """)

    let crew = StaffManager.processCrew(persons: [lowerPriorityWithAvatar, higherPriorityPlaceholder])

    XCTAssertEqual(crew.map(\.name), ["占位图导演", "有头像的次要职位"])
  }
}

/// 保存/恢复 `APIService.shared` 的图片相关配置，避免测试间互相污染。
@MainActor
private struct PersonImageServiceSnapshot {
  let baseURL: String
  let settings: GlobalSettings?
  let useImageCache: Bool

  static func capture(service: APIService) -> PersonImageServiceSnapshot {
    PersonImageServiceSnapshot(
      baseURL: service.baseURL,
      settings: service.settings,
      useImageCache: service.useImageCache
    )
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.settings = settings
    service.useImageCache = useImageCache
  }
}
