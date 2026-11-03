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

  /// 换行处拆块时片内空行原样保留，各片用换行拼回去就是原文。
  func testSplitLinesKeepsBlankLines() {
    let text = "请求失败\n\nTraceback:\n  at foo()\n\n  at bar()\n  at baz()"
    let pieces = ReadingSheetLayout.splitLines(AttributedString(text), charactersPerLine: 40, maxLines: 3)
    XCTAssertGreaterThan(pieces.count, 1)
    XCTAssertEqual(pieces.map { String($0.characters) }.joined(separator: "\n"), text)
  }

  /// 断点后有一长串空白时，空白留在上一片末尾但不计入行数：每块仍在行数预算内，原文不丢。
  func testLongWhitespaceRunStaysWithinLineBudget() {
    let text = String(repeating: "a", count: 40) + String(repeating: " ", count: 600)
      + String(repeating: "b", count: 20)
    let chunks = ReadingSheetLayout.chunks([ReadingBlock(text)], charactersPerLine: 10, maxLines: 4)
    for chunk in chunks {
      let lines = chunk.reduce(0) { $0 + ReadingSheetLayout.lineCount($1.text, charactersPerLine: 10) }
      XCTAssertLessThanOrEqual(lines, 4)
    }
    XCTAssertEqual(chunks.flatMap { $0 }.map { String($0.text.characters) }.joined(), text)
  }

  /// 文本以换行结尾时拆块后末尾换行不丢：各片用换行拼回去与原文一致。
  func testSplitLinesKeepsTrailingNewline() {
    let text = "a\nb\n"
    let pieces = ReadingSheetLayout.splitLines(AttributedString(text), charactersPerLine: 10, maxLines: 2)
    XCTAssertEqual(pieces.map { String($0.characters) }, ["a\nb", ""])
    XCTAssertEqual(pieces.map { String($0.characters) }.joined(separator: "\n"), text)
  }

  /// 行尾空白不计入行数，行首缩进照常计入。
  func testLineCountIgnoresTrailingWhitespace() {
    XCTAssertEqual(
      ReadingSheetLayout.lineCount(AttributedString("abc" + String(repeating: " ", count: 50)), charactersPerLine: 10), 1)
    XCTAssertEqual(
      ReadingSheetLayout.lineCount(AttributedString(String(repeating: " ", count: 15) + "x"), charactersPerLine: 10), 2)
  }

  /// 多行文本里单独一行就超出预算时，那一行再按字数拆，其余行仍按换行分组。
  func testOverlongLineInsideMultilineTextIsSplitByCharacters() {
    let long = String(repeating: "z", count: 100)
    let text = "head\n" + long + "\ntail"
    let pieces = ReadingSheetLayout.splitLines(AttributedString(text), charactersPerLine: 10, maxLines: 3)
    XCTAssertEqual(pieces.map { String($0.characters) }, ["head", String(repeating: "z", count: 30), String(repeating: "z", count: 30), String(repeating: "z", count: 30), String(repeating: "z", count: 10), "tail"])
  }

  /// 超长的单行日志拆开后不删任何字符：第一片保留行首缩进，断点处的空白留在上一片末尾，
  /// 下一片从非空白字符开始，拼起来与原文逐字相同。
  func testSplitKeepsEveryCharacter() {
    // 4 个空格缩进 + 36 个 x 正好 40 字，在第 40 字处硬切，断点后面是一串空格。
    let line = "    " + String(repeating: "x", count: 36) + "    " + String(repeating: "y", count: 20)
    let pieces = ReadingSheetLayout.split(AttributedString(line), maxCharacters: 40)
    XCTAssertEqual(pieces.count, 2)
    XCTAssertEqual(String(pieces[0].characters), "    " + String(repeating: "x", count: 36) + "    ")
    XCTAssertEqual(String(pieces[1].characters), String(repeating: "y", count: 20))
    XCTAssertEqual(pieces.map { String($0.characters) }.joined(), line)
  }

  /// 在两个单词之间断开时，单词间的空格不丢（路径、日志要能逐字核对）。
  func testSplitBetweenWordsKeepsSpace() {
    let text = "/volume1/Movies/Some Title (2024)/Some Title (2024) - 2160p.mkv"
    let pieces = ReadingSheetLayout.split(AttributedString(text), maxCharacters: 20)
    XCTAssertGreaterThan(pieces.count, 1)
    XCTAssertEqual(pieces.map { String($0.characters) }.joined(), text)
    XCTAssertTrue(pieces.dropFirst().allSatisfy { $0.characters.first?.isWhitespace == false })
  }

  /// 富文本按换行拆段时保留属性（AniList 简介是 Markdown）。
  func testAttributedParagraphsKeepAttributes() throws {
    let text = try AttributedString(markdown: "**粗体**开头\n\n  第二段  ", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    let paragraphs = ReadingSheetLayout.paragraphs(text)
    XCTAssertEqual(paragraphs.map { String($0.characters) }, ["粗体开头", "第二段"])
    let bold = paragraphs[0].runs.first?.inlinePresentationIntent
    XCTAssertEqual(bold, .stronglyEmphasized)
  }

  /// 纯文本拆段：只在空行处分段，单个换行留在段内；统一换行符，去掉每段首尾空白。
  func testPlainParagraphs() {
    XCTAssertEqual(ReadingSheetLayout.paragraphs("一\r\n\r\n  二 \r三\n"), ["一", "二 \n三"])
    XCTAssertEqual(ReadingSheetLayout.paragraphs("   \n"), [])
    XCTAssertEqual(ReadingSheetLayout.paragraphs("A\nB"), ["A\nB"])
    XCTAssertEqual(ReadingSheetLayout.paragraphs("A\n\nB"), ["A", "B"])
    XCTAssertEqual(ReadingSheetLayout.paragraphs("A\n \n\n\nB"), ["A", "B"])
    XCTAssertEqual(ReadingSheetLayout.chunks([], charactersPerLine: 10), [])
  }

  /// 日志详情：时间在前，消息整段原样（空行、缩进都保留），metadata 按键排序。
  func testLogDetailBlocksKeepMessageVerbatim() {
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
    XCTAssertEqual(bodies.map { String($0.text.characters) }, ["请求失败\n  at foo()\n\n  at bar()"])
    XCTAssertEqual(blocks.first?.style, .secondary)
    XCTAssertEqual(blocks.suffix(3).map { String($0.text.characters) }, ["metadata", "a: 1", "b: 2"])
  }
}
