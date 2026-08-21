import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TorrentsResultOrderingTests: XCTestCase {
  func testDefaultKeepsBackendOrderWithinGlobalSoftFilterPartition() {
    let results = [
      makeContext(title: "灰色高优先级", size: 400, priority: 400, isFilteredOut: true),
      makeContext(title: "正常低优先级", size: 100, priority: 1),
      makeContext(title: "灰色低优先级", size: 50, priority: 1, isFilteredOut: true),
      makeContext(title: "正常高优先级", size: 300, priority: 300),
    ]

    let ordered = TorrentsResultView<EmptyView>.orderResults(
      results,
      by: .default,
      type: .default
    )

    XCTAssertEqual(
      ordered.compactMap { $0.torrent_info?.title },
      ["正常低优先级", "正常高优先级", "灰色高优先级", "灰色低优先级"]
    )
  }

  func testExplicitSortAppliesWithinGlobalSoftFilterPartitions() {
    let results = [
      makeContext(title: "灰色最大", size: 400, priority: 1, isFilteredOut: true),
      makeContext(title: "正常较小", size: 100, priority: 1),
      makeContext(title: "灰色最小", size: 50, priority: 1, isFilteredOut: true),
      makeContext(title: "正常较大", size: 300, priority: 1),
    ]

    let ordered = TorrentsResultView<EmptyView>.orderResults(
      results,
      by: .size,
      type: .desc
    )

    XCTAssertEqual(
      ordered.compactMap { $0.torrent_info?.title },
      ["正常较大", "正常较小", "灰色最大", "灰色最小"]
    )
  }

  func testDefaultFieldWithExplicitDirectionSortsByPriorityWithinPartitions() {
    let results = [
      makeContext(title: "灰色低优先级", size: 1, priority: 1, isFilteredOut: true),
      makeContext(title: "正常低优先级", size: 1, priority: 1),
      makeContext(title: "灰色高优先级", size: 1, priority: 300, isFilteredOut: true),
      makeContext(title: "正常高优先级", size: 1, priority: 300),
    ]

    let ascending = TorrentsResultView<EmptyView>.orderResults(
      results,
      by: .default,
      type: .asc
    )

    XCTAssertEqual(
      ascending.compactMap { $0.torrent_info?.title },
      ["正常低优先级", "正常高优先级", "灰色低优先级", "灰色高优先级"]
    )

    let descending = TorrentsResultView<EmptyView>.orderResults(
      results,
      by: .default,
      type: .desc
    )

    XCTAssertEqual(
      descending.compactMap { $0.torrent_info?.title },
      ["正常高优先级", "正常低优先级", "灰色高优先级", "灰色低优先级"]
    )
  }

  func testDefaultTypeKeepsBackendOrderRegardlessOfField() {
    let results = [
      makeContext(title: "正常低优先级", size: 400, priority: 1),
      makeContext(title: "正常高优先级", size: 100, priority: 300),
    ]

    let ordered = TorrentsResultView<EmptyView>.orderResults(
      results,
      by: .size,
      type: .default
    )

    XCTAssertEqual(
      ordered.compactMap { $0.torrent_info?.title },
      ["正常低优先级", "正常高优先级"]
    )
  }

  private func makeContext(
    title: String,
    size: Int64,
    priority: Int,
    isFilteredOut: Bool = false
  ) -> Context {
    var context = Context(
      torrent_info: TorrentInfo(
        site: 1,
        site_name: "测试站点",
        site_order: 1,
        title: title,
        description: nil,
        enclosure: "https://example.test/\(title)",
        page_url: "https://example.test/\(title)",
        size: size,
        seeders: 1,
        peers: 1,
        pubdate: "2026-08-13 00:00:00",
        uploadvolumefactor: 1,
        downloadvolumefactor: 1,
        pri_order: priority,
        labels: [],
        volume_factor: "1x"
      )
    )
    context.isFilteredOut = isFilteredOut
    return context
  }
}
