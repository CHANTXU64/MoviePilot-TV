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
}

@MainActor
private struct PersonDecodingServiceSnapshot {
  let baseURL: String
  let useImageCache: Bool

  static func capture(service: APIService) -> PersonDecodingServiceSnapshot {
    PersonDecodingServiceSnapshot(baseURL: service.baseURL, useImageCache: service.useImageCache)
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.useImageCache = useImageCache
  }
}
