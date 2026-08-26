import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class PersonDecodingTests: XCTestCase {
  func testPersonDedupUsesSourceScopedIdentityAndFiltersCurrentBatchDuplicates() throws {
    let people = try JSONDecoder().decode(
      [Person].self,
      from: Data(
        """
        [
          {"source":"douban","id":7,"name":"豆瓣人物"},
          {"source":"douban","id":7,"name":"豆瓣重复人物"},
          {"source":"themoviedb","id":7,"name":"TMDB人物"}
        ]
        """.utf8
      )
    )
    var seenIDs = Set<String>()

    let uniquePeople = Person.deduplicate(people, existingIDs: &seenIDs)

    XCTAssertEqual(uniquePeople.map(\.id), ["douban-7", "themoviedb-7"])
    XCTAssertEqual(uniquePeople.map(\.name), ["豆瓣人物", "TMDB人物"])
    XCTAssertTrue(Person.deduplicate(people, existingIDs: &seenIDs).isEmpty)
  }

  func testDecodesDoubanPersonSearchImagesWithObjectEntries() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
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

    service.baseURLForTesting = "http://moviepilot.local"
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

    service.baseURLForTesting = "http://moviepilot.local"
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

  func testMixedAvatarMetadataDoesNotDiscardPeople() throws {
    let people = try JSONDecoder().decode(
      [Person].self,
      from: Data(
        """
        [
          {
            "source": "douban",
            "id": 1,
            "name": "有后备头像",
            "avatar": {
              "normal": "  ",
              "large": "https://douban.local/large.jpg",
              "width": 100,
              "height": null
            }
          },
          {
            "source": "douban",
            "id": 2,
            "name": "无可用头像",
            "avatar": {
              "width": 100,
              "height": null
            }
          }
        ]
        """.utf8
      )
    )

    XCTAssertEqual(people.count, 2)
    XCTAssertEqual(people[0].avatar?.urlValue, "https://douban.local/large.jpg")
    XCTAssertNil(people[1].avatar)
  }

  func testMixedAvatarMetadataDecodesOffMainActor() async throws {
    let data = Data(
      """
      {
        "normal": "  ",
        "large": "https://douban.local/large.jpg",
        "width": 100,
        "height": null
      }
      """.utf8
    )

    let avatarURL = try await Task.detached {
      try JSONDecoder().decode(PersonAvatar.self, from: data).urlValue
    }.value

    XCTAssertEqual(avatarURL, "https://douban.local/large.jpg")
  }

  func testNestedMediaInfoDecodesOffMainActorWithoutImageServiceAccess() async throws {
    let data = Data(
      """
      {
        "source": "themoviedb",
        "title": "后台详情",
        "directors": [
          {
            "source": "themoviedb",
            "id": 123,
            "name": "后台导演",
            "profile_path": "/director.jpg"
          }
        ],
        "actors": [
          {
            "source": "themoviedb",
            "id": 456,
            "name": "后台演员",
            "profile_path": "/actor.jpg"
          }
        ],
        "subscribeShare": {
          "id": 7,
          "name": "后台分享",
          "type": "电影",
          "poster": "/poster.jpg"
        }
      }
      """.utf8
    )

    let decoded = try await Task.detached {
      let media = try JSONDecoder().decode(MediaInfoJSON.self, from: data)
      return (
        media.directors?.count,
        media.actors?.count,
        media.subscribeShare != nil
      )
    }.value

    XCTAssertEqual(decoded.0, 1)
    XCTAssertEqual(decoded.1, 1)
    XCTAssertTrue(decoded.2)
  }

  func testSparsePersonDetailsPreserveSeedDisplayFields() throws {
    let seed = try JSONDecoder().decode(
      Person.self,
      from: Data(
        """
        {
          "source": "douban",
          "id": 123,
          "name": "种子演员",
          "avatar": "https://douban.local/seed.jpg",
          "original_name": "Seed Actor",
          "birthday": "1980-01-01"
        }
        """.utf8
      )
    )
    let sparseDetail = try JSONDecoder().decode(
      Person.self,
      from: Data(
        #"{"biography":"详情简介","avatar":"https://douban.local/detail.jpg"}"#.utf8
      )
    )

    let merged = seed.mergingDetails(from: sparseDetail)

    XCTAssertEqual(merged.source, "douban")
    XCTAssertEqual(merged.raw_id, "123")
    XCTAssertEqual(merged.id, seed.id)
    XCTAssertEqual(merged.name, "种子演员")
    XCTAssertEqual(merged.avatar?.urlValue, "https://douban.local/seed.jpg")
    XCTAssertEqual(merged.original_name, "Seed Actor")
    XCTAssertEqual(merged.birthday, "1980-01-01")
    XCTAssertEqual(merged.biography, "详情简介")
  }

  func testPersonImageSelectionMatchesWebForEverySourceAndFallback() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
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
          "AniList avatar fallback", "anilist", nil,
          .url("https://anilist.local/avatar.jpg"), nil,
          "https://anilist.local/avatar.jpg"
        ),
        (
          "AniList staff default avatar filtered", "anilist", nil, nil,
          images(large: "https://s4.anilist.co/file/anilistcdn/staff/large/default.jpg"), nil
        ),
        (
          "AniList character default avatar filtered", "anilist", nil, nil,
          images(large: "https://s4.anilist.co/file/anilistcdn/character/large/default.jpg"),
          nil
        ),
        (
          "AniList object default avatar filtered", "anilist", nil,
          .url("https://s4.anilist.co/file/anilistcdn/staff/large/default.jpg"), nil,
          nil
        ),
        (
          "Bangumi no_icon person filtered", "bangumi", nil, nil,
          images(medium: "https://lain.bgm.tv/img/no_icon_person.png"), nil
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

  func testEmbeddedDirectorInheritsDeclaredMediaSourceForImageAndRoute() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"TMDB_IMAGE_DOMAIN":"tmdb-images.local"}"#.utf8)
    )
    service.useImageCache = false

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        """
        {
          "source": "themoviedb",
          "title": "测试电影",
          "directors": [
            {
              "id": 123,
              "name": "测试导演",
              "job": "Director",
              "profile_path": "/director.jpg"
            }
          ]
        }
        """.utf8
      )
    )

    let embeddedDirector = try XCTUnwrap(media.directors?.first)
    XCTAssertNil(embeddedDirector.source)
    XCTAssertNil(embeddedDirector.imageURLs.profile)

    let resolvedDirector = try XCTUnwrap(media.resolvedDirectors.first)
    XCTAssertEqual(resolvedDirector.source, "themoviedb")
    XCTAssertEqual(resolvedDirector.id, "themoviedb-123")
    XCTAssertEqual(
      resolvedDirector.imageURLs.profile?.absoluteString,
      "https://tmdb-images.local/t/p/w600_and_h900_bestv2/director.jpg"
    )
  }

  func testEmbeddedDirectorDoesNotInventMissingOrUnsupportedMediaSource() throws {
    let director = try JSONDecoder().decode(
      Person.self,
      from: Data(#"{"id":123,"name":"测试导演","profile_path":"/director.jpg"}"#.utf8)
    )

    for fallback in [nil, "tvdb"] as [String?] {
      let resolvedDirector = director.resolvingRouteSource(fallback: fallback)
      XCTAssertNil(resolvedDirector.source)
      XCTAssertNil(resolvedDirector.imageURLs.profile)
    }
  }

  func testMediaDetailViewModelPublishesResolvedEmbeddedDirectors() throws {
    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        """
        {
          "source": "themoviedb",
          "title": "测试电影",
          "directors": [
            {
              "id": 123,
              "name": "测试导演",
              "job": "Director",
              "profile_path": "/director.jpg"
            }
          ]
        }
        """.utf8
      )
    )
    let viewModel = MediaDetailViewModel(
      detail: media,
      apiService: APIService.isolatedTestingInstance()
    )

    viewModel.applyFullDetail(media)

    let director = try XCTUnwrap(viewModel.uniqueDirectors.first)
    XCTAssertEqual(director.source, "themoviedb")
    XCTAssertEqual(director.id, "themoviedb-123")
  }

  func testAniListEmbeddedDirectorSupportsNestedAvatarAfterSourceResolution() throws {
    let service = APIService.shared
    let snapshot = PersonDecodingServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://moviepilot.local"
    service.useImageCache = false

    let media = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        """
        {
          "source": "anilist",
          "anilist_id": 154587,
          "directors": [
            {
              "id": 95012,
              "name": "Atsumi Tanezaki",
              "job": "Director",
              "avatar": {"large": "https://anilist.local/staff/large.jpg"}
            }
          ]
        }
        """.utf8
      )
    )

    let director = try XCTUnwrap(media.resolvedDirectors.first)
    XCTAssertEqual(director.source, "anilist")
    XCTAssertEqual(director.name, "Atsumi Tanezaki")
    XCTAssertEqual(
      director.imageURLs.profile?.absoluteString,
      "https://anilist.local/staff/large.jpg"
    )
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
    service.baseURLForTesting = baseURL
    service.settings = settings
    service.useImageCache = useImageCache
  }
}
