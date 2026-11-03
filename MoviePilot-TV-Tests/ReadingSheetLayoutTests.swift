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

  /// 字段行按扣掉标签列后的宽度拆分：续片保留字段样式但不重复标签，分隔线原样保留。
  func testFieldValueSplitsWithinValueColumn() {
    let perLine = 40
    let valueWidth = ReadingSheetLayout.valueCharactersPerLine(perLine)
    XCTAssertLessThan(valueWidth, perLine)
    let longPath = String(repeating: "a", count: valueWidth * 3 * 2)
    let chunks = ReadingSheetLayout.chunks(
      [.field("源文件", longPath), .divider, .field("状态", "成功")],
      charactersPerLine: perLine, maxLines: 3)
    let pieces = chunks.flatMap { $0 }
    let pathPieces = pieces.filter { $0.style == .field(label: "源文件") }
    XCTAssertEqual(pathPieces.count, 2)
    XCTAssertTrue(pathPieces.allSatisfy { $0.text.characters.count <= valueWidth * 3 })
    XCTAssertEqual(pathPieces.map(\.startsParagraph), [true, false])
    XCTAssertEqual(pieces.filter { $0.style == .divider }.count, 1)
    XCTAssertEqual(pieces.last?.style, .field(label: "状态"))
  }

  /// 行数估算计入显式换行：多行短文本按行数算，不按总字数除以列宽算。
  func testLineCountCountsExplicitNewlines() {
    XCTAssertEqual(ReadingSheetLayout.lineCount(AttributedString("a\nb\nc"), charactersPerLine: 40), 3)
    XCTAssertEqual(ReadingSheetLayout.lineCount(AttributedString("a\n\nb"), charactersPerLine: 40), 3)
    XCTAssertEqual(
      ReadingSheetLayout.lineCount(
        AttributedString(String(repeating: "x", count: 81) + "\nend"), charactersPerLine: 40),
      4)
  }

  /// 整段传入的 40 行失败原因拆成多个停靠块，每块不超过行数预算；
  /// 在换行处断开，行首缩进与全部内容都保留。
  func testMultilineFieldValueSplitsAtNewlines() {
    let lines = (1...40).map { "  第\($0)行 Traceback" }
    let reason = lines.joined(separator: "\n")
    let perLine = 60
    let valueWidth = ReadingSheetLayout.valueCharactersPerLine(perLine)
    let chunks = ReadingSheetLayout.chunks(
      [.field("失败原因", reason)], charactersPerLine: perLine, maxLines: 9)

    XCTAssertGreaterThan(chunks.count, 1, "40 行不能挤在一个停靠块里")
    for chunk in chunks {
      let chunkLines = chunk.reduce(0) {
        $0 + ReadingSheetLayout.lineCount($1.text, charactersPerLine: valueWidth)
      }
      XCTAssertLessThanOrEqual(chunkLines, 9)
    }
    let pieces = chunks.flatMap { $0 }
    XCTAssertEqual(pieces.map(\.startsParagraph), [true] + Array(repeating: false, count: pieces.count - 1))
    XCTAssertTrue(pieces.allSatisfy { String($0.text.characters).hasPrefix("  第") }, "断开处保留行首缩进")
    XCTAssertEqual(pieces.map { String($0.text.characters) }.joined(separator: "\n"), reason)
  }

  /// 多行文本里单独一行就超出预算时，那一行再按字数拆，其余行仍按换行分组。
  func testOverlongLineInsideMultilineTextIsSplitByCharacters() {
    let long = String(repeating: "z", count: 100)
    let text = "head\n" + long + "\ntail"
    let pieces = ReadingSheetLayout.splitLines(AttributedString(text), charactersPerLine: 10, maxLines: 3)
    XCTAssertEqual(pieces.map { String($0.characters) }, ["head", String(repeating: "z", count: 30), String(repeating: "z", count: 30), String(repeating: "z", count: 30), String(repeating: "z", count: 10), "tail"])
  }

  /// 超长的单行日志拆开后，第一片保留行首缩进；后续片段只去掉断点处的空白。
  func testSplitKeepsLeadingIndentation() {
    // 4 个空格缩进 + 36 个 x 正好 40 字，在第 40 字处硬切，断点后面是一串空格。
    let line = "    " + String(repeating: "x", count: 36) + "    " + String(repeating: "y", count: 20)
    let pieces = ReadingSheetLayout.split(AttributedString(line), maxCharacters: 40)
    XCTAssertEqual(pieces.count, 2)
    XCTAssertEqual(String(pieces[0].characters), "    " + String(repeating: "x", count: 36))
    XCTAssertEqual(String(pieces[1].characters), String(repeating: "y", count: 20))
    XCTAssertEqual(
      pieces.map { String($0.characters) }.joined().filter { !$0.isWhitespace },
      line.filter { !$0.isWhitespace }
    )
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
