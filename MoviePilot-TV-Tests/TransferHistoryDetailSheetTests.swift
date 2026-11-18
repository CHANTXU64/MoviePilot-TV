import XCTest

@testable import MoviePilot_TV

/// 转移历史详情改用统一阅读 Sheet 后的正文内容与顺序。
@MainActor
final class TransferHistoryDetailSheetTests: XCTestCase {
  private func history(_ json: String) throws -> TransferHistory {
    try JSONDecoder().decode(TransferHistory.self, from: Data(json.utf8))
  }

  private func texts(_ blocks: [ReadingBlock]) -> [String] {
    blocks.map { String($0.text.characters) }
  }

  /// 电视剧标题附中文季集；电影或季集为空时只显示片名。
  func testTitleAppendsSeasonEpisodeForTV() throws {
    let tv = try history(#"{"id":1,"title":"某剧","type":"电视剧","seasons":"S01","episodes":"E02","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: tv), "某剧 1季 2集")
    let tvWithoutEpisode = try history(#"{"id":2,"title":"某剧","type":"电视剧","seasons":" ","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: tvWithoutEpisode), "某剧")
    let movie = try history(#"{"id":3,"title":"某片","type":"电影","seasons":"S01","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: movie), "某片")
  }

  /// 列表卡片、详情标题和重新整理面板读同一个季集显示：一律中文，空白段丢弃，读不出时整段不显示。
  func testSeasonEpisodeDisplayIsChineseAndSharedByCards() throws {
    let cases: [(json: String, expected: String?)] = [
      (#"{"id":1,"type":"电视剧","seasons":"S01","episodes":"E02","status":true}"#, "1季 2集"),
      // 一个文件多集：后端给的是集号区间。
      (#"{"id":2,"type":"电视剧","seasons":"S01","episodes":"E02-E05","status":true}"#, "1季 2-5集"),
      // 不连续多集：顿号并列多区间同样中文化。
      (#"{"id":10,"type":"电视剧","seasons":"S01","episodes":"E01-E03、E05","status":true}"#, "1季 1-3、5集"),
      // 跨季合集。
      (#"{"id":3,"type":"电视剧","seasons":"S01-S02","episodes":"E03-04","status":true}"#, "1-2季 3-4集"),
      // 只有季、只有集，以及季集都是空白。
      (#"{"id":4,"type":"电视剧","seasons":"S02","status":true}"#, "2季"),
      (#"{"id":5,"type":"电视剧","seasons":" ","episodes":"E07","status":true}"#, "7集"),
      (#"{"id":6,"type":"电视剧","seasons":" ","episodes":"  ","status":true}"#, nil),
      (#"{"id":7,"type":"电视剧","status":true}"#, nil),
      // 电影即使带着季集也不显示。
      (#"{"id":8,"type":"电影","seasons":"S01","episodes":"E02","status":true}"#, nil),
      // 认不出的原文不改写。
      (#"{"id":9,"type":"电视剧","seasons":"Season 1","status":true}"#, "Season 1"),
    ]

    for (json, expected) in cases {
      let item = try history(json)
      XCTAssertEqual(item.seasonEpisodeDisplay, expected, json)
      let name = item.title ?? "详情"
      XCTAssertEqual(
        TransferHistoryDetailSheet.title(for: item),
        expected.map { "\(name) \($0)" } ?? name,
        json
      )
    }
  }

  private func fields(_ blocks: [ReadingBlock]) -> [String] {
    blocks.map { block in
      switch block.style {
      case .field(let label): return "\(label)=\(String(block.text.characters))"
      case .divider: return "---"
      default: return String(block.text.characters)
      }
    }
  }

  /// 失败记录：源文件、目标文件、失败原因一组，分隔线后是状态等信息；存储显示名优先用字典。
  func testFailedRecordBlocks() throws {
    let item = try history(
      #"{"id":1,"title":"某片","type":"电影","status":false,"errmsg":"磁盘已满","src":"/a/b.mkv","dest":"/c/d.mkv","src_storage":"local","dest_storage":"alipan","category":"电影","mode":"copy","date":"2026-11-03 10:00:00"}"#
    )
    let blocks = TransferHistoryDetailSheet.blocks(for: item, storageDict: ["local": "本地"])
    XCTAssertEqual(
      fields(blocks),
      [
        "源文件=[本地] /a/b.mkv", "目标文件=[alipan] /c/d.mkv", "失败原因=磁盘已满", "---",
        "状态=失败", "分类=电影", "转移方式=拷贝", "日期=2026-11-03 10:00:00",
      ]
    )
  }

  /// 成功记录没有失败原因一行。
  func testSuccessfulRecordHasNoFailureField() throws {
    let item = try history(#"{"id":1,"title":"某片","type":"电影","status":true,"errmsg":"旧错误"}"#)
    let rows = fields(TransferHistoryDetailSheet.blocks(for: item, storageDict: [:]))
    XCTAssertFalse(rows.contains { $0.hasPrefix("失败原因=") })
    XCTAssertEqual(rows.first, "源文件=[未知] N/A")
  }
}
