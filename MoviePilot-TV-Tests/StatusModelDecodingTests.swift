import XCTest

@testable import MoviePilot_TV

/// F-005 回归：`Statistic`/`DownloaderInfo` 的非可选字段不能靠属性默认值兜底，
/// 缺键/null 须在模型边界按 0 解出，而不是让合成 Decodable 抛错。
@MainActor
final class StatusModelDecodingTests: XCTestCase {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  func testStatisticToleratesMissingAndNullFields() throws {
    let missing = try decode(Statistic.self, #"{"movie_count":2}"#)
    XCTAssertEqual(missing.movie_count, 2)
    XCTAssertEqual(missing.tv_count, 0)
    XCTAssertNil(missing.episode_count)

    let nulls = try decode(
      Statistic.self, #"{"movie_count":null,"tv_count":null,"episode_count":null}"#)
    XCTAssertEqual(nulls.movie_count, 0)
    XCTAssertEqual(nulls.tv_count, 0)
    XCTAssertNil(nulls.episode_count)

    let empty = try decode(Statistic.self, "{}")
    XCTAssertEqual(empty.movie_count, 0)
    XCTAssertEqual(empty.tv_count, 0)
    XCTAssertNil(empty.episode_count)

    // 字段齐全时行为不变。
    let full = try decode(Statistic.self, #"{"movie_count":2,"tv_count":3,"episode_count":4}"#)
    XCTAssertEqual(full.movie_count, 2)
    XCTAssertEqual(full.tv_count, 3)
    XCTAssertEqual(full.episode_count, 4)
  }

  func testDownloaderInfoToleratesMissingAndNullFields() throws {
    let missing = try decode(DownloaderInfo.self, #"{"download_speed":7}"#)
    XCTAssertEqual(missing.download_speed, 7)
    XCTAssertEqual(missing.upload_speed, 0)
    XCTAssertEqual(missing.download_size, 0)
    XCTAssertEqual(missing.upload_size, 0)
    XCTAssertEqual(missing.free_space, 0)

    let nulls = try decode(
      DownloaderInfo.self,
      #"{"download_speed":null,"upload_speed":null,"download_size":null,"upload_size":null,"free_space":null}"#
    )
    XCTAssertEqual(nulls.download_speed, 0)
    XCTAssertEqual(nulls.upload_speed, 0)
    XCTAssertEqual(nulls.free_space, 0)

    let empty = try decode(DownloaderInfo.self, "{}")
    XCTAssertEqual(empty.download_speed, 0)
    XCTAssertEqual(empty.free_space, 0)

    // 字段齐全时行为不变。
    let full = try decode(
      DownloaderInfo.self,
      #"{"download_speed":7,"upload_speed":1,"download_size":20,"upload_size":2,"free_space":60}"#)
    XCTAssertEqual(full.download_speed, 7)
    XCTAssertEqual(full.upload_speed, 1)
    XCTAssertEqual(full.download_size, 20)
    XCTAssertEqual(full.upload_size, 2)
    XCTAssertEqual(full.free_space, 60)
  }
}
