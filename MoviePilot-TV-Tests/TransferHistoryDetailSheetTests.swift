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

  /// 电视剧标题附季集；电影或季集为空时只显示片名。
  func testTitleAppendsSeasonEpisodeForTV() throws {
    let tv = try history(#"{"id":1,"title":"某剧","type":"电视剧","seasons":"S01","episodes":"E02","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: tv), "某剧 S01 E02")
    let tvWithoutEpisode = try history(#"{"id":2,"title":"某剧","type":"电视剧","seasons":" ","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: tvWithoutEpisode), "某剧")
    let movie = try history(#"{"id":3,"title":"某片","type":"电影","seasons":"S01","status":true}"#)
    XCTAssertEqual(TransferHistoryDetailSheet.title(for: movie), "某片")
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
