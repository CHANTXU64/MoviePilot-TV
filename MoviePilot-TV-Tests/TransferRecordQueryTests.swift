import XCTest

@testable import MoviePilot_TV

final class TransferRecordQueryTests: XCTestCase {
  private func record(_ id: Int?, show: String = "100", episode: Int = 1) -> EpisodeTransferRecord {
    EpisodeTransferRecord(
      id: id, mediaID: show, seasons: "S01", episodes: String(format: "E%02d", episode),
      path: "/tv/show/S01E\(episode).mkv")
  }

  /// 按页回记录：第 n 页是 `pages[n-1]`，超出的是空页。记下读了哪些页。
  private final class Pages {
    var pages: [[EpisodeTransferRecord]]
    var total: Int?
    var reads: [Int] = []

    init(_ pages: [[EpisodeTransferRecord]], total: Int?) {
      self.pages = pages
      self.total = total
    }

    func fetch(_ query: String, _ page: Int) -> TransferRecordQuery.Page {
      reads.append(page)
      return (page <= pages.count ? pages[page - 1] : [], total)
    }
  }

  private func read(_ pages: Pages, after previous: TransferRecordQuery?, pageSize: Int = 2, pageLimit: Int = 5)
    async throws -> TransferRecordQuery
  {
    try await TransferRecordQuery.read(
      query: "show*", tmdbID: 100, previous: previous, pageSize: pageSize, pageLimit: pageLimit,
      fetch: { pages.fetch($0, $1) })
  }

  func testIncrementalReadStopsAtTheFirstPageWithASeenRecord() async throws {
    let first = Pages([[record(3, episode: 3), record(2, show: "200")], [record(1, episode: 1)]], total: 3)
    let initial = try await read(first, after: nil)
    XCTAssertEqual(first.reads, [1, 2])
    XCTAssertEqual(initial.records.map(\.id), [3, 1], "只留这部剧的，从新到旧")

    let second = Pages(
      [[record(5, episode: 5), record(4, episode: 4)], [record(3, episode: 3), record(2, show: "200")]], total: 5)
    let updated = try await read(second, after: initial)
    XCTAssertEqual(second.reads, [1, 2], "第 2 页才遇到读过的")
    XCTAssertEqual(updated.records.map(\.id), [5, 4, 3, 1])
    XCTAssertEqual(updated.total, 5)
  }

  func testRecordReorganizedInPlaceIsReplacedByTheNewerVersion() async throws {
    // 重新整理过的记录（同一编号）排到最前面，集号改了：用新读到的，不留旧的。
    let initial = try await read(Pages([[record(1, episode: 1)]], total: 1), after: nil)
    let updated = try await read(Pages([[record(1, episode: 2)]], total: 1), after: initial)
    XCTAssertEqual(updated.records, [record(1, episode: 2)])
  }

  func testRecordsWithoutIDsAreAlwaysReadFromTheStart() async throws {
    let pages = Pages([[record(nil), record(nil, episode: 2)], [record(nil, episode: 3)]], total: 3)
    let initial = try await read(pages, after: nil)
    XCTAssertNil(initial.seenIDs)
    pages.reads = []
    let again = try await read(pages, after: initial)
    XCTAssertEqual(pages.reads, [1, 2], "认不出读过的记录，只能从头读")
    XCTAssertEqual(again.records.count, 3)
  }

  func testMissingTotalMeansStartingOver() async throws {
    let pages = Pages([[record(2, episode: 2), record(1, episode: 1)]], total: nil)
    let initial = try await read(pages, after: nil, pageSize: 10)
    pages.pages = [[record(3, episode: 3), record(2, episode: 2), record(1, episode: 1)]]
    pages.reads = []
    let again = try await read(pages, after: initial, pageSize: 10)
    XCTAssertEqual(pages.reads, [1])
    XCTAssertEqual(again.records.map(\.id), [3, 2, 1], "没有总数没法核对，按从头读的结果")
  }

  func testRemovedRecordIsDroppedWhenTheTotalDoesNotAddUp() async throws {
    let initial = try await read(Pages([[record(2, episode: 2), record(1, episode: 1)]], total: 2), after: nil)
    // 第 2 条被删、新整理了第 3 条：总数还是 2。
    let pages = Pages([[record(3, episode: 3), record(1, episode: 1)]], total: 2)
    let again = try await read(pages, after: initial)
    XCTAssertEqual(pages.reads, [1, 1], "增量读一页，对不上，从头再读")
    XCTAssertEqual(again.records.map(\.id), [3, 1])
  }
}
