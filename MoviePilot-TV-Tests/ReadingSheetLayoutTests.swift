import XCTest

@testable import MoviePilot_TV

/// 统一阅读 Sheet 的分段与焦点停靠块。
///
/// tvOS 的 ScrollView 只靠焦点移动滚动：停靠块太碎要按很多次，太大会高过一屏翻不下去。
@MainActor
final class ReadingSheetLayoutTests: XCTestCase {
  private func texts(_ chunks: [[ReadingBlock]]) -> [[String]] {
    chunks.map { $0.map { String($0.text.characters) } }
  }

  /// 「一行一段」的正文合并成少量停靠块，顺序与内容不变。
  func testShortParagraphsAreGroupedIntoChunks() {
    let lines = (1...20).map { "第\($0)行" }
    let chunks = ReadingSheetLayout.chunks(
      lines.map { ReadingBlock($0) }, charactersPerLine: 28, maxLines: 8)
    XCTAssertEqual(chunks.map(\.count), [8, 8, 4])
    XCTAssertEqual(texts(chunks).flatMap { $0 }, lines)
  }

  /// 超过一块的长段落在句末拆开：每片不超过一块，续片不留段落间距，拼回去内容不丢。
  func testLongParagraphSplitsAtSentenceEnds() {
    let sentence = String(repeating: "字", count: 19) + "。"
    let paragraph = String(repeating: sentence, count: 10)  // 200 字
    let chunks = ReadingSheetLayout.chunks(
      [ReadingBlock(paragraph)], charactersPerLine: 10, maxLines: 5)
    let pieces = chunks.flatMap { $0 }
    XCTAssertGreaterThan(pieces.count, 1)
    XCTAssertTrue(pieces.allSatisfy { $0.text.characters.count <= 50 })
    XCTAssertTrue(pieces.dropLast().allSatisfy { String($0.text.characters).hasSuffix("。") })
    XCTAssertEqual(pieces.map(\.startsParagraph), [true] + Array(repeating: false, count: pieces.count - 1))
    XCTAssertEqual(pieces.map { String($0.text.characters) }.joined(), paragraph)
  }

  /// 没有句末标点（日志里的长串）时按上限硬切，同样不超过一块。
  func testLongTextWithoutSentenceEndIsHardSplit() {
    let text = String(repeating: "a", count: 120)
    let pieces = ReadingSheetLayout.split(AttributedString(text), maxCharacters: 50)
    XCTAssertEqual(pieces.map { $0.characters.count }, [50, 50, 20])
  }

  /// 富文本按换行拆段时保留属性（AniList 简介是 Markdown）。
  func testAttributedParagraphsKeepAttributes() throws {
    let text = try AttributedString(markdown: "**粗体**开头\n\n  第二段  ", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    let paragraphs = ReadingSheetLayout.paragraphs(text)
    XCTAssertEqual(paragraphs.map { String($0.characters) }, ["粗体开头", "第二段"])
    let bold = paragraphs[0].runs.first?.inlinePresentationIntent
    XCTAssertEqual(bold, .stronglyEmphasized)
  }

  /// 纯文本拆段：统一换行符，去掉空段与首尾空白。
  func testPlainParagraphs() {
    XCTAssertEqual(ReadingSheetLayout.paragraphs("一\r\n\r\n  二 \r三\n"), ["一", "二", "三"])
    XCTAssertEqual(ReadingSheetLayout.paragraphs("   \n"), [])
    XCTAssertEqual(ReadingSheetLayout.chunks([], charactersPerLine: 10), [])
  }

  /// 日志详情：时间在前，消息按行成为连续续段并保留缩进，metadata 按键排序。
  func testLogDetailBlocksKeepMessageLines() {
    let record = LogRecord(
      id: UUID(),
      timestamp: Date(timeIntervalSince1970: 0),
      level: .error,
      message: "请求失败\n  at foo()\n\n  at bar()",
      fileName: "A.swift",
      function: "f()",
      line: 1,
      metadata: ["b": "2", "a": "1"]
    )
    let blocks = LogRecordDetailSheet.blocks(for: record)
    let bodies = blocks.filter { $0.style == .body }
    XCTAssertEqual(bodies.map { String($0.text.characters) }, ["请求失败", "  at foo()", "  at bar()"])
    XCTAssertEqual(bodies.map(\.startsParagraph), [true, false, false])
    XCTAssertEqual(blocks.first?.style, .secondary)
    XCTAssertEqual(blocks.suffix(3).map { String($0.text.characters) }, ["metadata", "a: 1", "b: 2"])
  }
}
