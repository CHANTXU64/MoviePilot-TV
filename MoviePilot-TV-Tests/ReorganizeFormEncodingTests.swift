import XCTest

@testable import MoviePilot_TV

@MainActor
final class ReorganizeFormEncodingTests: XCTestCase {
  func testFileItemsTakePrecedenceAndEmptyFieldsEncodeAsNull() throws {
    let fileitem = FileItem(name: "single.mkv", path: "/downloads/single.mkv", type: "file", size: 1)
    let fileitems = [
      FileItem(name: "episode1.mkv", path: "/downloads/episode1.mkv", type: "file", size: 1),
      FileItem(name: "episode2.mkv", path: "/downloads/episode2.mkv", type: "file", size: 2),
    ]

    let form = ReorganizeForm(
      fileitem: fileitem,
      fileitems: fileitems,
      logid: 0,
      target_storage: "local",
      transfer_type: "",
      target_path: " ",
      min_filesize: 0,
      scrape: false,
      from_history: false,
      episode_group: " "
    )

    let json = try encodedJSONObject(form)
    let encodedFileitems = try XCTUnwrap(json["fileitems"] as? [[String: Any]])

    XCTAssertFalse(json.keys.contains("fileitem"))
    XCTAssertEqual(encodedFileitems.count, 2)
    XCTAssertEqual(encodedFileitems[0]["name"] as? String, "episode1.mkv")
    XCTAssertTrue(json["target_path"] is NSNull)
    XCTAssertTrue(json["episode_group"] is NSNull)
  }

  func testHistoryRedoOmitsFileItemsInsteadOfEncodingPlaceholder() throws {
    let form = ReorganizeForm(
      fileitem: nil,
      fileitems: nil,
      logid: 42,
      target_storage: "local",
      transfer_type: "",
      target_path: "",
      min_filesize: 0,
      scrape: false,
      from_history: true
    )

    let json = try encodedJSONObject(form)

    XCTAssertFalse(json.keys.contains("fileitem"))
    XCTAssertFalse(json.keys.contains("fileitems"))
    XCTAssertEqual(json["logid"] as? Int, 42)
    XCTAssertTrue(json["target_path"] is NSNull)
  }

  func testAutomaticOptionsEncodeAsNull() throws {
    let form = ReorganizeForm(
      fileitem: nil,
      fileitems: nil,
      logid: 42,
      target_storage: nil,
      transfer_type: nil,
      target_path: "",
      min_filesize: 0,
      scrape: nil,
      from_history: true
    )

    let json = try encodedJSONObject(form)

    XCTAssertTrue(json["target_storage"] is NSNull)
    XCTAssertTrue(json["transfer_type"] is NSNull)
    XCTAssertTrue(json["target_path"] is NSNull)
    XCTAssertTrue(json["scrape"] is NSNull)
  }

  private func encodedJSONObject(_ form: ReorganizeForm) throws -> [String: Any] {
    let data = try JSONEncoder().encode(form)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
