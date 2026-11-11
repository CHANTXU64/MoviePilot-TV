import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class ResourceSearchDecodingTests: XCTestCase {
  func testSiteProxyAcceptsBackendBooleanRepresentations() throws {
    let cases: [(json: String, expected: Bool)] = [
      ("true", true),
      ("false", false),
      ("1", true),
      ("0", false),
      (#""true""#, true),
      (#""false""#, false),
      (#""1""#, true),
      (#""0""#, false),
    ]

    for item in cases {
      let torrent = try JSONDecoder().decode(
        TorrentInfo.self,
        from: Data(#"{"site_proxy":\#(item.json)}"#.utf8)
      )

      XCTAssertEqual(torrent.site_proxy, item.expected, item.json)
      let encoded = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(torrent)) as? [String: Any]
      )
      XCTAssertEqual(encoded["site_proxy"] as? Bool, item.expected, item.json)
    }
  }

  func testSparseResourceFieldsDoNotRejectSearchBatch() throws {
    let itemsJSON =
      """
      [
        {
          "torrent_info": {
            "title": "完整资源",
            "size": 1024.0,
            "uploadvolumefactor": 2,
            "downloadvolumefactor": 0
          },
          "meta_info": {
            "name": "完整名称",
            "season_episode": "S01E01"
          }
        },
        {
          "torrent_info": {
            "title": "稀疏资源",
            "size": null,
            "uploadvolumefactor": "invalid",
            "downloadvolumefactor": null
          },
          "meta_info": {
            "name": 123,
            "season_episode": null
          }
        },
        {
          "torrent_info": {
            "title": "超大资源",
            "size": 1e100,
            "uploadvolumefactor": 1,
            "downloadvolumefactor": 1
          }
        }
      ]
      """

    let fallbackItems = try JSONDecoder().decode([Context].self, from: Data(itemsJSON.utf8))
    let streamEvent = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data("{\"type\":\"replace\",\"items\":\(itemsJSON)}".utf8)
    )

    XCTAssertEqual(fallbackItems.count, 3)
    XCTAssertEqual(streamEvent.items?.count, 3)
    XCTAssertEqual(fallbackItems[0].torrent_info?.size, 1024)
    XCTAssertEqual(fallbackItems[0].torrent_info?.uploadvolumefactor, 2)
    XCTAssertEqual(fallbackItems[0].torrent_info?.downloadvolumefactor, 0)
    XCTAssertEqual(fallbackItems[0].meta_info?.name, "完整名称")
    XCTAssertEqual(fallbackItems[0].meta_info?.season_episode, "S01E01")
    XCTAssertEqual(fallbackItems[1].torrent_info?.size, 0)
    XCTAssertEqual(fallbackItems[1].torrent_info?.uploadvolumefactor, 1)
    XCTAssertEqual(fallbackItems[1].torrent_info?.downloadvolumefactor, 1)
    XCTAssertEqual(fallbackItems[1].meta_info?.name, "")
    XCTAssertEqual(fallbackItems[1].meta_info?.season_episode, "")
    XCTAssertEqual(fallbackItems[2].torrent_info?.size, 0)
  }

  func testSearchStreamEventLocalizedMessageTrimsThenFallsBack() throws {
    // message_i18n 全空白时不得遮蔽有效 message。
    let blankI18n = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data(#"{"type":"error","message_i18n":"   ","message":"站点搜索失败"}"#.utf8)
    )
    XCTAssertEqual(blankI18n.localizedMessage, "站点搜索失败")

    let validI18n = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data(#"{"type":"error","message_i18n":"读取失败","message":"raw"}"#.utf8)
    )
    XCTAssertEqual(validI18n.localizedMessage, "读取失败")

    let blankOnly = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data(#"{"type":"error","message_i18n":" \n "}"#.utf8)
    )
    XCTAssertNil(blankOnly.localizedMessage)
  }

  func testAiRedoDataLocalizedErrorTrimsThenFallsBack() throws {
    let blankI18n = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data(#"{"data":{"success":false,"error_i18n":"   ","error":"目标目录不可用"}}"#.utf8)
    )
    XCTAssertEqual(blankI18n.data?.localizedError, "目标目录不可用")

    let validI18n = try JSONDecoder().decode(
      SearchStreamEvent.self,
      from: Data(#"{"data":{"success":false,"error_i18n":"AI 整理失败","error":"raw"}}"#.utf8)
    )
    XCTAssertEqual(validI18n.data?.localizedError, "AI 整理失败")
  }
}
