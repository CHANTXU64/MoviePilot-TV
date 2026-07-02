import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeModelCompatibilityTests: XCTestCase {
  func testSubscribeRequestOmitsUnsetBestVersionFieldsAndPreservesExplicitZero() throws {
    let unset = SubscribeRequest(
      name: "默认配置订阅",
      type: "电视剧",
      year: "2026",
      tmdbid: nil,
      doubanid: "douban-1",
      bangumiid: nil,
      mediaid: "douban:douban-1",
      season: 1,
      best_version: nil,
      best_version_full: nil,
      episode_group: nil
    )

    let unsetJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(unset)) as? [String: Any])
    XCTAssertFalse(unsetJSON.keys.contains("best_version"))
    XCTAssertFalse(unsetJSON.keys.contains("best_version_full"))
    XCTAssertEqual(unsetJSON["mediaid"] as? String, "douban:douban-1")

    let explicitNormal = SubscribeRequest(
      name: "显式普通订阅",
      type: "电视剧",
      year: "2026",
      tmdbid: 123,
      doubanid: nil,
      bangumiid: nil,
      mediaid: nil,
      season: 1,
      best_version: 0,
      best_version_full: 0,
      episode_group: nil
    )

    let explicitJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(explicitNormal)) as? [String: Any])
    XCTAssertEqual(explicitJSON["best_version"] as? Int, 0)
    XCTAssertEqual(explicitJSON["best_version_full"] as? Int, 0)
  }

  func testSavePayloadPreservesBackendMaintainedStateFields() throws {
    let payload = """
      {
        "id": 42,
        "name": "状态字段订阅",
        "type": "电视剧",
        "season": 1,
        "vote": 8.7,
        "filter": "站点过滤",
        "username": "alice",
        "current_priority": 80,
        "date": "2026-07-02 10:00:00",
        "note": [1, 2, {"source": "history"}],
        "episode_priority": {"1": 100, "2": 80},
        "completed_episode": 1
      }
      """.data(using: .utf8)!

    let subscribe = try JSONDecoder().decode(Subscribe.self, from: payload)
    let encoded = try JSONEncoder().encode(subscribe)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    let note = try XCTUnwrap(json["note"] as? [Any])
    XCTAssertEqual(note[0] as? Int, 1)
    XCTAssertEqual(note[1] as? Int, 2)
    XCTAssertEqual((note[2] as? [String: Any])?["source"] as? String, "history")

    let episodePriority = try XCTUnwrap(json["episode_priority"] as? [String: Int])
    XCTAssertEqual(episodePriority, ["1": 100, "2": 80])
    XCTAssertEqual(json["vote"] as? Double, 8.7)
    XCTAssertEqual(json["filter"] as? String, "站点过滤")
    XCTAssertEqual(json["username"] as? String, "alice")
    XCTAssertEqual(json["current_priority"] as? Int, 80)
    XCTAssertEqual(json["date"] as? String, "2026-07-02 10:00:00")
    XCTAssertFalse(json.keys.contains("completed_episode"))
  }

  func testExplicitNullNoteIsPreservedWhenSavingSubscription() throws {
    let payload = """
      {
        "id": 43,
        "name": "空 note 订阅",
        "type": "电视剧",
        "season": 1,
        "note": null
      }
      """.data(using: .utf8)!

    let subscribe = try JSONDecoder().decode(Subscribe.self, from: payload)
    let encoded = try JSONEncoder().encode(subscribe)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertTrue(json.keys.contains("note"))
    XCTAssertTrue(json["note"] is NSNull)
  }
}
