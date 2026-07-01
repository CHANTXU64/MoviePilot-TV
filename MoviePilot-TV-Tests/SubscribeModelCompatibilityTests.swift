import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeModelCompatibilityTests: XCTestCase {
  func testSavePayloadPreservesBackendMaintainedStateFields() throws {
    let payload = """
      {
        "id": 42,
        "name": "状态字段订阅",
        "type": "电视剧",
        "season": 1,
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
