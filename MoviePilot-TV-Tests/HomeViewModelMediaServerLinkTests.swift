import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class HomeViewModelMediaServerLinkTests: XCTestCase {
  func testLatestBatchKeepsItemsWithMissingOrNullTitles() throws {
    let data = Data(
      """
      [
        {"id":"normal", "title":"正常标题"},
        {"id":"null", "title":null},
        {"id":"missing"}
      ]
      """.utf8
    )

    let items = try JSONDecoder().decode([MediaServerPlayItem].self, from: data)

    XCTAssertEqual(items.map(\.title), ["正常标题", "", ""])
  }

  func testLatestItemIdentityUsesStableServerScopedFields() throws {
    let items = try JSONDecoder().decode(
      [MediaServerPlayItem].self,
      from: Data(
        """
        [
          {"id":"item-1","title":"Emby","link":"https://emby/item-1?token=old","server_type":"emby"},
          {"id":"item-1","title":"Emby","link":"https://emby/item-1?token=new","server_type":"emby"},
          {"id":"item-1","title":"Plex","server_type":"plex"},
          {"item_id":"item-1","server_id":"server-1","title":"Emby","server_type":"emby"},
          {"item_id":"item-1","server_id":"server-1","title":"Emby","server_type":"emby"},
          {"item_id":"item-2","server_id":"server-1","title":"Emby 2","server_type":"emby"},
          {"item_id":"item-1","server_id":"server-2","title":"Other server","server_type":"emby"},
          {"id":"server-1-item-1","title":"Raw collision case","server_type":"emby"}
        ]
        """.utf8
      )
    )

    XCTAssertEqual(items[0].id, "playitem-4:emby-raw-6:item-1")
    XCTAssertEqual(items[1].id, items[0].id)
    XCTAssertNotEqual(items[2].id, items[0].id)
    XCTAssertEqual(items[3].id, "playitem-4:emby-pair-8:server-1-6:item-1")
    XCTAssertEqual(items[4].id, items[3].id)
    XCTAssertNotEqual(items[5].id, items[3].id)
    XCTAssertNotEqual(items[6].id, items[3].id)
    XCTAssertNotEqual(items[7].id, items[3].id)
  }

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

    let openedURL = openMediaItemURL(item)
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

    let openedURL = openMediaItemURL(item)
    let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(openedURL), resolvingAgainstBaseURL: false))
    let queryItems = queryItemMap(from: components)

    XCTAssertEqual(components.scheme, "emby")
    XCTAssertEqual(components.host, "items")
    XCTAssertEqual(queryItems["serverId"], "emby-server-2")
    XCTAssertEqual(queryItems["itemId"], "emby-item-2")
  }

  func testPlexInvalidLinkReportsFailureWithoutFallback() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "plex-raw-1",
        "title": "Plex Item",
        "link": "none",
        "server_type": "plex"
      }
      """)

    XCTAssertEqual(openMediaItemFailure(item), "无法打开媒体库：链接无效")
  }

  func testOpenMediaItemReportsInvalidLinkForUnknownServerType() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "unknown-1",
        "title": "Unknown Item",
        "link": "none",
        "server_type": "future-type"
      }
      """)

    XCTAssertEqual(openMediaItemFailure(item), "无法打开媒体库：链接无效")
  }

  func testOpenMediaItemReportsKnownUnsupportedServerType() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "jellyfin-1",
        "title": "Jellyfin Item",
        "link": "https://jellyfin.local/web/index.html#!/item?id=1",
        "server_type": "jellyfin"
      }
      """)

    XCTAssertEqual(openMediaItemFailure(item), "Jellyfin 暂不支持在 tvOS 打开媒体")
  }

  func testOpenMediaItemReportsUnknownServerType() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "future-1",
        "title": "Future Item",
        "link": "https://future.local/item",
        "server_type": "future-type"
      }
      """)

    XCTAssertEqual(
      openMediaItemFailure(item),
      "未知的媒体服务器类型（future-type）暂不支持在 tvOS 打开媒体")
  }

  func testEmbyValidLinkWithoutIdentifiersReportsGeneratedLinkFailure() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "emby-no-ids",
        "title": "Emby Item",
        "link": "https://emby.local/web/index.html",
        "server_type": "emby"
      }
      """)

    XCTAssertEqual(
      openMediaItemFailure(item),
      "未能生成 emby 的有效媒体库链接")
  }

  func testNilServerTypeWithValidLinkReportsUnsupported() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "no-type",
        "title": "No Type Item",
        "link": "https://media.local/item"
      }
      """)

    XCTAssertEqual(
      openMediaItemFailure(item),
      "未知的媒体服务器类型暂不支持在 tvOS 打开媒体")
  }

  func testOpenMediaItemReportsRejectedOpenURL() throws {
    let item = try decodePlayItem(
      """
      {
        "id": "emby-rejected",
        "item_id": "emby-item-1",
        "server_id": "emby-server-1",
        "title": "Emby Item",
        "link": "https://emby.local/web/index.html#!/item?id=emby-item-1&serverId=emby-server-1",
        "server_type": "emby"
      }
      """)

    XCTAssertEqual(
      openMediaItemFailure(item, handlerResult: .discarded),
      "无法打开媒体库 App，请确认已安装后重试")
  }

  func testSupportsMediaLibraryDeepLinkKnownCapabilities() {
    XCTAssertTrue(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .emby))
    XCTAssertTrue(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .plex))
    XCTAssertTrue(HomeViewModel.supportsMediaLibraryDeepLink(serverType: nil))
    XCTAssertTrue(
      HomeViewModel.supportsMediaLibraryDeepLink(serverType: MediaServerType(rawValue: "future-type")))
    XCTAssertFalse(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .jellyfin))
    XCTAssertFalse(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .trimemedia))
    XCTAssertFalse(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .ugreen))
    XCTAssertFalse(HomeViewModel.supportsMediaLibraryDeepLink(serverType: .zspace))
  }

  private func openMediaItemURL(_ item: MediaServerPlayItem) -> URL? {
    var openedURL: URL?
    let action = OpenURLAction { url in
      openedURL = url
      return .handled
    }
    HomeViewModel(apiService: APIService.shared).openMediaItem(item, using: action) { _ in }
    return openedURL
  }

  private func openMediaItemFailure(
    _ item: MediaServerPlayItem,
    handlerResult: OpenURLAction.Result = .handled
  ) -> String? {
    var failureMessage: String?
    let completion = expectation(description: "openMediaItem 失败出口")
    let action = OpenURLAction { _ in handlerResult }
    HomeViewModel(apiService: APIService.shared).openMediaItem(item, using: action) { message in
      failureMessage = message
      completion.fulfill()
    }
    wait(for: [completion], timeout: 1)
    return failureMessage
  }

  private func decodePlayItem(_ json: String) throws -> MediaServerPlayItem {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(MediaServerPlayItem.self, from: data)
  }

  private func queryItemMap(from components: URLComponents) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
  }
}
