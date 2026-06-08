import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class HomeViewModelMediaServerLinkTests: XCTestCase {
  func testEmbyDeepLinkUsesStructuredIdsWhenLinkIsInvalid() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "legacy-id",
        "item_id": "emby-item-1",
        "server_id": "emby-server-1",
        "title": "Emby Item",
        "link": "none",
        "server_type": "emby"
      }
      """)

    let openedURL = openMediaItem(item)
    let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(openedURL), resolvingAgainstBaseURL: false))
    let queryItems = queryItemMap(from: components)

    XCTAssertEqual(components.scheme, "emby")
    XCTAssertEqual(components.host, "items")
    XCTAssertEqual(queryItems["serverId"], "emby-server-1")
    XCTAssertEqual(queryItems["itemId"], "emby-item-1")
  }

  func testEmbyDeepLinkFallsBackToLinkFragmentWhenStructuredIdsAreMissing() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "legacy-id",
        "title": "Emby Item",
        "link": "https://emby.local/web/index.html#!/item?id=emby-item-2&context=home&serverId=emby-server-2",
        "server_type": "emby"
      }
      """)

    let openedURL = openMediaItem(item)
    let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(openedURL), resolvingAgainstBaseURL: false))
    let queryItems = queryItemMap(from: components)

    XCTAssertEqual(components.scheme, "emby")
    XCTAssertEqual(components.host, "items")
    XCTAssertEqual(queryItems["serverId"], "emby-server-2")
    XCTAssertEqual(queryItems["itemId"], "emby-item-2")
  }

  func testPlexDoesNotOpenFallbackWhenLinkIsInvalid() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "plex-raw-1",
        "title": "Plex Item",
        "link": "none",
        "server_type": "plex"
      }
      """)

    XCTAssertNil(openMediaItem(item))
  }

  private func openMediaItem(_ item: MediaServerPlayItem) -> URL? {
    var openedURL: URL?
    let action = OpenURLAction { url in
      openedURL = url
      return .handled
    }
    HomeViewModel(apiService: APIService.shared).openMediaItem(item, using: action)
    return openedURL
  }

  private func decodePlayItem(_ json: String) throws -> MediaServerPlayItem {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(MediaServerPlayItem.self, from: data)
  }

  private func queryItemMap(from components: URLComponents) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
  }
}
