import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class PersonDecodingTests: XCTestCase {
  func testDecodesDoubanPersonSearchImagesWithObjectEntries() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"
    service.useImageCache = false

    let people = try JSONDecoder().decode(
      [Person].self,
      from: Data(
        """
        [
          {
            "source": "themoviedb",
            "id": 4936045,
            "name": "易中天",
            "profile_path": null,
            "avatar": null,
            "images": {}
          },
          {
            "source": "themoviedb",
            "id": 2134697,
            "name": "易中天",
            "profile_path": "/njXheWJQA5PmYPvoRHXF2Yp9PrB.jpg",
            "avatar": null,
            "images": {}
          },
          {
            "source": "douban",
            "id": 27557670,
            "name": "易中天",
            "profile_path": null,
            "avatar": "https://img1.doubanio.com/view/personage/s/public/711926d2a5ec146221bea858987bab19.jpg",
            "images": {
              "large": {
                "url": "https://img1.doubanio.com/view/personage/l/public/711926d2a5ec146221bea858987bab19.jpg",
                "width": 0,
                "height": 0
              },
              "normal": {
                "url": "https://img1.doubanio.com/view/personage/m/public/711926d2a5ec146221bea858987bab19.jpg",
                "width": 0,
                "height": 0
              }
            }
          }
        ]
        """.utf8
      )
    )

    XCTAssertEqual(people.count, 3)
    let doubanPerson = try XCTUnwrap(people.first { $0.source == "douban" })
    XCTAssertEqual(doubanPerson.raw_id, "27557670")
    XCTAssertEqual(doubanPerson.name, "易中天")
    XCTAssertEqual(
      doubanPerson.images?.large,
      "https://img1.doubanio.com/view/personage/l/public/711926d2a5ec146221bea858987bab19.jpg"
    )

    let imageURL = try XCTUnwrap(doubanPerson.imageURLs.profile)
    let components = try XCTUnwrap(URLComponents(url: imageURL, resolvingAgainstBaseURL: false))
    let queryItems = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )

    XCTAssertEqual(components.host, "moviepilot.local")
    XCTAssertEqual(components.path, "/api/v1/system/img/0")
    XCTAssertEqual(
      queryItems["imgurl"],
      "https://img1.doubanio.com/view/personage/s/public/711926d2a5ec146221bea858987bab19.jpg"
    )
  }

  func testDecodesAniListPersonDetailsAndUsesLargeImage() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"
    service.useImageCache = false

    let person = try JSONDecoder().decode(
      Person.self,
      from: Data(
        """
        {
          "source": "anilist",
          "id": 95012,
          "name": "声优",
          "biography": "**主要作品**\\n\\n- 动画 A",
          "birthday": "1980-03-04",
          "images": {
            "large": "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg",
            "medium": "https://s4.anilist.co/file/anilistcdn/staff/medium/95012.jpg"
          }
        }
        """.utf8
      )
    )

    XCTAssertEqual(person.raw_id, "95012")
    XCTAssertEqual(
      person.imageURLs.profile?.absoluteString,
      "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg"
    )
    let renderedBiography = String(
      PersonDetailView.biographyText(person.biography ?? "", source: person.source).characters
    )
    XCTAssertTrue(renderedBiography.contains("主要作品"))
    XCTAssertTrue(renderedBiography.contains("动画 A"))
    XCTAssertFalse(renderedBiography.contains("**"))
  }

  func testDecodesAniListMediaCreditImageObjects() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"
    service.useImageCache = false

    let person = try JSONDecoder().decode(
      Person.self,
      from: Data(
        """
        {
          "source": "anilist",
          "id": 95012,
          "name": "声优",
          "images": {
            "large": "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg",
            "medium": "https://s4.anilist.co/file/anilistcdn/staff/medium/95012.jpg"
          },
          "avatar": {
            "large": "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg",
            "medium": "https://s4.anilist.co/file/anilistcdn/staff/medium/95012.jpg"
          }
        }
        """.utf8
      )
    )

    XCTAssertEqual(
      person.imageURLs.profile?.absoluteString,
      "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg"
    )
    XCTAssertEqual(
      person.avatar?.urlValue,
      "https://s4.anilist.co/file/anilistcdn/staff/large/95012.jpg"
    )
  }

  func testPersonImageSelectionMatchesWebForEverySourceAndFallback() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURL = "http://moviepilot.local"
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"TMDB_IMAGE_DOMAIN":"tmdb-images.local"}"#.utf8)
    )
    service.useImageCache = false

    func images(large: String? = nil, medium: String? = nil) -> BangumiImages {
      BangumiImages(
        large: large,
        common: nil,
        medium: medium,
        small: nil,
        grid: nil
      )
    }

    let doubanObject = try JSONDecoder().decode(
      PersonAvatar.self,
      from: Data(
        """
        {
          "large": "https://douban.local/large.jpg",
          "normal": "https://douban.local/normal.jpg"
        }
        """.utf8
      )
    )
    XCTAssertEqual(doubanObject.urlValue, "https://douban.local/normal.jpg")

    let cases:
      [(
        label: String, source: String?, profilePath: String?, avatar: PersonAvatar?,
        images: BangumiImages?, expected: String?
      )] = [
        (
          "TMDB profile", "themoviedb", "/tmdb.jpg", nil, nil,
          "https://tmdb-images.local/t/p/w600_and_h900_bestv2/tmdb.jpg"
        ),
        ("TMDB missing profile", "themoviedb", nil, nil, nil, nil),
        (
          "Douban string avatar", "douban", nil, .url("https://douban.local/string.jpg"),
          nil, "https://douban.local/string.jpg"
        ),
        (
          "Douban object normal", "douban", nil, doubanObject, nil,
          "https://douban.local/normal.jpg"
        ),
        (
          "Douban default person icon", "douban", nil,
          .url("https://img1.doubanio.com/personage-default.jpg"), nil, nil
        ),
        (
          "Bangumi medium", "bangumi", nil, nil,
          images(
            large: "https://lain.bgm.tv/pic/crt/l/large.jpg",
            medium: "https://lain.bgm.tv/pic/crt/m/medium.jpg"
          ),
          "http://moviepilot.local/api/v1/system/img/1?imgurl=https%3A%2F%2Flain.bgm.tv%2Fpic%2Fcrt%2Fm%2Fmedium.jpg"
        ),
        (
          "Bangumi does not fall back to large", "bangumi", nil, nil,
          images(large: "https://lain.bgm.tv/pic/crt/l/large.jpg"), nil
        ),
        (
          "AniList large", "anilist", nil, nil,
          images(
            large: "https://anilist.local/large.jpg",
            medium: "https://anilist.local/medium.jpg"
          ),
          "https://anilist.local/large.jpg"
        ),
        (
          "AniList medium fallback", "anilist", nil, nil,
          images(medium: "https://anilist.local/medium.jpg"),
          "https://anilist.local/medium.jpg"
        ),
        (
          "AniList ignores avatar", "anilist", nil,
          .url("https://anilist.local/avatar.jpg"), nil, nil
        ),
        (
          "Missing source", nil, "/tmdb.jpg", .url("https://douban.local/avatar.jpg"),
          images(medium: "https://anilist.local/medium.jpg"), nil
        ),
        (
          "Unsupported source", "tvdb", "/tmdb.jpg", .url("https://douban.local/avatar.jpg"),
          images(medium: "https://anilist.local/medium.jpg"), nil
        ),
      ]

    for item in cases {
      XCTAssertEqual(
        service.getPersonImageURL(
          source: item.source,
          profilePath: item.profilePath,
          avatar: item.avatar,
          images: item.images
        )?.absoluteString,
        item.expected,
        item.label
      )
    }
  }

  func testPersonCreditsRejectsMissingOrUnsupportedSource() async {
    let service = APIService.shared
    let invalidSources: [String?] = [nil, "tvdb"]

    for source in invalidSources {
      do {
        _ = try await service.fetchPersonCredits(personId: "95012", source: source)
        XCTFail("人物作品请求应在发起网络请求前拒绝无效来源")
      } catch APIError.invalidURL {
      } catch {
        XCTFail("预期 invalidURL，实际为 \(error)")
      }
    }
  }

}

@MainActor
private struct PersonDecodingServiceSnapshot {
  let baseURL: String
  let settings: GlobalSettings?
  let useImageCache: Bool

  static func capture(service: APIService) -> PersonDecodingServiceSnapshot {
    PersonDecodingServiceSnapshot(
      baseURL: service.baseURL,
      settings: service.settings,
      useImageCache: service.useImageCache
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.settings = settings
    service.useImageCache = useImageCache
  }
}
