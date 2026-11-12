import SwiftUI

/// 阅读型 Sheet 的一段内容。
nonisolated struct ReadingBlock: Hashable, Sendable {
  nonisolated enum Style: Hashable, Sendable {
    /// 正文。
    case body
    /// 次要说明（日期、元数据、列表条目等）。
    case secondary
    /// 小节标题。
    case heading
    /// 「标签 + 值」一行：左列是加粗标签，右列是次要色的值；拆开的续片不重复标签。
    case field(label: String)
    /// 分组之间的分隔线（`text` 为空）。
    case divider
  }

  var text: AttributedString
  var style: Style
  /// false 表示上一段被拆开后的续段：前面不留段落间距。
  var startsParagraph: Bool

  init(_ text: AttributedString, style: Style = .body, startsParagraph: Bool = true) {
    self.text = text
    self.style = style
    self.startsParagraph = startsParagraph
  }

  init(_ text: String, style: Style = .body) {
    self.init(AttributedString(text), style: style)
  }

  static func field(_ label: String, _ value: String) -> ReadingBlock {
    ReadingBlock(value, style: .field(label: label))
  }

  static let divider = ReadingBlock(AttributedString(), style: .divider)
}

/// 阅读型 Sheet 的分段与焦点停靠块计算。
///
/// tvOS 的 `ScrollView` 只在焦点移到屏幕外的元素时滚动，长文必须有焦点停靠点才能往下翻；
/// 但一段一个停靠点时，「一行一段」的内容要按很多次。这里把相邻段落合成每块约 `maxLines`
/// 行的停靠块，超长段落先在句末拆成不超过一块的片段，保证每块都不会高过一屏。
nonisolated enum ReadingSheetLayout {
  static let sheetWidth: CGFloat = 1500
  static let sheetHeight: CGFloat = 900
  static let horizontalPadding: CGFloat = 72
  static let verticalPadding: CGFloat = 64
  static let sidebarWidth: CGFloat = 340
  static let columnSpacing: CGFloat = 64
  /// 每块约 9 行（`.body` 29pt 默认行距），按一下大约翻半屏。
  static let maxLinesPerChunk = 9
  /// `.body` 中文字宽约等于字号。
  static let bodyCharacterWidth: CGFloat = 29

  static func charactersPerLine(hasSidebar: Bool) -> Int {
    var width = sheetWidth - horizontalPadding * 2 - scrollTrailingPadding
    if hasSidebar { width -= sidebarWidth + columnSpacing }
    return max(1, Int(width / bodyCharacterWidth))
  }

  static let scrollTrailingPadding: CGFloat = 24
  /// 字段行左列（标签）的宽度与列间距。
  static let fieldLabelWidth: CGFloat = 170
  static let fieldSpacing: CGFloat = 24

  /// 字段行右列能放的字数：扣掉标签列。
  static func valueCharactersPerLine(_ charactersPerLine: Int) -> Int {
    let labelCharacters = Int(((fieldLabelWidth + fieldSpacing) / bodyCharacterWidth).rounded(.up))
    return max(1, charactersPerLine - labelCharacters)
  }

  /// 按空行拆段：空行（含只有空白的行）是段落边界，单个换行留在段内作为换行，
  /// 与 Web 评论正文的 `white-space: pre-line` 一致，`A\nB` 与 `A\n\nB` 显示不同。
  /// 每段去掉首尾空白；连续多个空行按一个段落间距显示。
  static func paragraphs(_ text: String) -> [String] {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return paragraphs(AttributedString(normalized)).map { String($0.characters) }
  }

  /// 富文本版本：保留 AniList Markdown 等富文本属性。
  static func paragraphs(_ text: AttributedString) -> [AttributedString] {
    let characters = text.characters
    var result: [AttributedString] = []
    var paragraphStart: AttributedString.Index?
    var paragraphEnd = characters.startIndex

    func flush() {
      if let start = paragraphStart, let paragraph = trimmed(text[start..<paragraphEnd]) {
        result.append(paragraph)
      }
      paragraphStart = nil
    }

    var lineStart = characters.startIndex
    while true {
      let lineEnd = characters[lineStart...].firstIndex(where: \.isNewline) ?? characters.endIndex
      if characters[lineStart..<lineEnd].contains(where: { !$0.isWhitespace }) {
        if paragraphStart == nil { paragraphStart = lineStart }
        paragraphEnd = lineEnd
      } else {
        flush()
      }
      guard lineEnd < characters.endIndex else { break }
      lineStart = characters.index(after: lineEnd)
    }
    flush()
    return result
  }

  /// 把内容分成焦点停靠块：先拆超长段落，再把相邻段落按行数预算合并。
  static func chunks(
    _ blocks: [ReadingBlock],
    charactersPerLine: Int,
    maxLines: Int = maxLinesPerChunk
  ) -> [[ReadingBlock]] {
    let perLine = max(1, charactersPerLine)
    let lineBudget = max(1, maxLines)
    func lineWidth(_ style: ReadingBlock.Style) -> Int {
      if case .field = style { return valueCharactersPerLine(perLine) }
      return perLine
    }
    let pieces = blocks.flatMap { block -> [ReadingBlock] in
      if block.style == .divider { return [block] }
      return splitLines(block.text, charactersPerLine: lineWidth(block.style), maxLines: lineBudget)
        .enumerated().map { index, text in
        ReadingBlock(
          text,
          style: block.style,
          startsParagraph: index == 0 ? block.startsParagraph : false
        )
      }
    }

    var chunks: [[ReadingBlock]] = []
    var current: [ReadingBlock] = []
    var currentLines = 0
    for piece in pieces {
      let lines = lineCount(piece.text, charactersPerLine: lineWidth(piece.style))
      if !current.isEmpty, currentLines + lines > lineBudget {
        chunks.append(current)
        current = []
        currentLines = 0
      }
      current.append(piece)
      currentLines += lines
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }

  /// 估算文本显示的行数：显式换行各起一行，每行再按列宽折行；空行也算一行。
  ///
  /// 行尾空白在折行处悬挂、不占显示宽度，不计入（`split` 会把断点后的空白留在片尾）；
  /// 行首缩进照常计入。
  static func lineCount(_ text: AttributedString, charactersPerLine: Int) -> Int {
    let width = max(1, charactersPerLine)
    func wrapped(_ count: Int) -> Int { max(1, (count + width - 1) / width) }
    var lines = 0
    var visible = 0
    var pendingWhitespace = 0
    for character in text.characters {
      if character.isNewline {
        lines += wrapped(visible)
        visible = 0
        pendingWhitespace = 0
      } else if character.isWhitespace {
        pendingWhitespace += 1
      } else {
        visible += pendingWhitespace + 1
        pendingWhitespace = 0
      }
    }
    return lines + wrapped(visible)
  }

  /// 把超过行数预算的文本拆成多片，每片不超过 `maxLines` 行。
  ///
  /// 先在显式换行处断开（整段传入的失败原因、日志 metadata 常是多行短文本），
  /// 断开处保留下一行的行首缩进，片内的空行原样保留；单独一行就超出预算时，再交给
  /// `split(_:maxCharacters:)` 按字数拆。各片用换行拼回去就是原文。
  static func splitLines(
    _ text: AttributedString,
    charactersPerLine: Int,
    maxLines: Int
  ) -> [AttributedString] {
    let width = max(1, charactersPerLine)
    let budget = max(1, maxLines)
    guard lineCount(text, charactersPerLine: width) > budget else { return [text] }

    let characters = text.characters
    var pieces: [AttributedString] = []
    var pieceStart: AttributedString.Index?
    var pieceEnd = characters.startIndex
    var pieceLines = 0

    func flush() {
      if let start = pieceStart {
        pieces.append(AttributedString(text[start..<pieceEnd]))
      }
      pieceStart = nil
      pieceLines = 0
    }

    // 逐行处理到最后一行为止，包括末尾换行之后的空行，各片用换行拼回去才与原文一致。
    var lineStart = characters.startIndex
    while true {
      let lineEnd = characters[lineStart...].firstIndex(where: \.isNewline) ?? characters.endIndex
      let lines = lineCount(AttributedString(text[lineStart..<lineEnd]), charactersPerLine: width)
      if lines > budget {
        flush()
        pieces.append(
          contentsOf: split(AttributedString(text[lineStart..<lineEnd]), maxCharacters: width * budget))
      } else {
        if pieceStart != nil, pieceLines + lines > budget { flush() }
        if pieceStart == nil { pieceStart = lineStart }
        pieceEnd = lineEnd
        pieceLines += lines
      }
      guard lineEnd < characters.endIndex else { break }
      lineStart = characters.index(after: lineEnd)
    }
    flush()
    return pieces
  }

  /// 把超长文本拆成不超过 `maxCharacters` 的片段，优先在句末断开；找不到句末时硬切。
  ///
  /// 不删任何字符：各片按顺序拼起来就是原文（日志、路径要能逐字核对）。断点后紧跟的空白
  /// 留在上一片末尾，下一片从非空白字符开始；片尾空白不占显示宽度。
  static func split(_ text: AttributedString, maxCharacters: Int) -> [AttributedString] {
    let limit = max(1, maxCharacters)
    let characters = text.characters
    guard characters.count > limit else { return [text] }

    var pieces: [AttributedString] = []
    var start = characters.startIndex
    while start < characters.endIndex {
      let remaining = characters.distance(from: start, to: characters.endIndex)
      if remaining <= limit {
        pieces.append(AttributedString(text[start..<characters.endIndex]))
        break
      }
      let hardEnd = characters.index(start, offsetBy: limit)
      let searchFloor = characters.index(start, offsetBy: limit / 2)
      var cut = hardEnd
      var index = hardEnd
      while index > searchFloor {
        let previous = characters.index(before: index)
        if sentenceTerminators.contains(characters[previous]) {
          cut = index
          break
        }
        index = previous
      }
      while cut < characters.endIndex, characters[cut].isWhitespace {
        cut = characters.index(after: cut)
      }
      pieces.append(AttributedString(text[start..<cut]))
      start = cut
    }
    return pieces
  }

  private static let sentenceTerminators: Set<Character> = [
    "。", "！", "？", "；", "…", ".", "!", "?", ";",
  ]

  private static func trimmed(_ substring: AttributedSubstring) -> AttributedString? {
    let characters = substring.characters
    guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
      let last = characters.lastIndex(where: { !$0.isWhitespace })
    else { return nil }
    return AttributedString(substring[first...last])
  }
}

/// 统一的阅读型 Sheet：1500×900，内边距 72/64，标题 `.title3` 不限行数，正文 `.body` 默认行距。
///
/// 单栏是「标题 + 正文」；传入左栏时变成两栏，标题与正文在右栏。正文按
/// `ReadingSheetLayout.chunks` 分成焦点停靠块（关闭焦点高亮），默认焦点在第一块；左栏有主操作按钮时
/// 传 `focusesBodyByDefault: false`，由左栏自己指定默认焦点。遥控器返回键关闭。
struct ReadingSheet<Sidebar: View>: View {
  let title: String?
  var titleColor: Color = .primary
  /// 正文焦点块。只在初始化时拆一次：焦点在块之间移动会重算 body，不能每次都对全文重新拆块。
  private let chunks: [[ReadingBlock]]
  let sidebar: Sidebar?
  private var focusesBodyByDefault = true

  @FocusState private var focusedChunkIndex: Int?

  init(
    title: String?,
    titleColor: Color = .primary,
    blocks: [ReadingBlock],
    focusesBodyByDefault: Bool = true,
    @ViewBuilder sidebar: () -> Sidebar
  ) {
    self.title = title
    self.titleColor = titleColor
    self.chunks = Self.chunks(for: blocks, hasSidebar: true)
    self.focusesBodyByDefault = focusesBodyByDefault
    self.sidebar = sidebar()
  }

  var body: some View {
    HStack(alignment: .top, spacing: ReadingSheetLayout.columnSpacing) {
      if let sidebar {
        sidebar
          .frame(width: ReadingSheetLayout.sidebarWidth, alignment: .topLeading)
          .frame(maxHeight: .infinity, alignment: .topLeading)
      }

      reading
    }
    .padding(.horizontal, ReadingSheetLayout.horizontalPadding)
    .padding(.vertical, ReadingSheetLayout.verticalPadding)
    .frame(
      width: ReadingSheetLayout.sheetWidth,
      height: ReadingSheetLayout.sheetHeight,
      alignment: .topLeading
    )
    .if(focusesBodyByDefault) { $0.defaultFocus($focusedChunkIndex, 0) }
  }

  private var reading: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
          Text(title)
            .font(.title3.bold())
            .foregroundStyle(titleColor)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 24)
        }

        ForEach(Array(chunks.enumerated()), id: \.offset) { chunkIndex, chunk in
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunk.enumerated()), id: \.offset) { blockIndex, block in
              blockView(block)
                .padding(
                  .top,
                  chunkIndex == 0 && blockIndex == 0 ? 0 : spacing(before: block)
                )
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .focusable()
          .focusEffectDisabled()
          .focused($focusedChunkIndex, equals: chunkIndex)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.vertical, 8)
      .padding(.trailing, ReadingSheetLayout.scrollTrailingPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private static func chunks(for blocks: [ReadingBlock], hasSidebar: Bool) -> [[ReadingBlock]] {
    ReadingSheetLayout.chunks(
      blocks.isEmpty ? [ReadingBlock("（暂无内容）", style: .secondary)] : blocks,
      charactersPerLine: ReadingSheetLayout.charactersPerLine(hasSidebar: hasSidebar)
    )
  }

  /// 空片（拆块时落单的空行）显示为一行空白，与 `lineCount` 把空行算一行一致。
  private static func displayText(_ text: AttributedString) -> AttributedString {
    text.characters.isEmpty ? AttributedString(" ") : text
  }

  @ViewBuilder
  private func blockView(_ block: ReadingBlock) -> some View {
    switch block.style {
    case .body:
      Text(Self.displayText(block.text))
        .font(.body)
        .modifier(ReadingTextLayout())
    case .secondary:
      Text(Self.displayText(block.text))
        .font(.body)
        .foregroundStyle(.secondary)
        .modifier(ReadingTextLayout())
    case .heading:
      Text(Self.displayText(block.text))
        .font(.headline)
        .modifier(ReadingTextLayout())
    case .field(let label):
      HStack(alignment: .firstTextBaseline, spacing: ReadingSheetLayout.fieldSpacing) {
        Text(block.startsParagraph ? label : "")
          .font(.body.bold())
          .frame(width: ReadingSheetLayout.fieldLabelWidth, alignment: .leading)
        Text(Self.displayText(block.text))
          .font(.body)
          .foregroundStyle(.secondary)
          .modifier(ReadingTextLayout())
      }
    case .divider:
      Divider()
    }
  }

  private func spacing(before block: ReadingBlock) -> CGFloat {
    guard block.startsParagraph else { return 0 }
    switch block.style {
    case .heading: return 36
    case .divider: return 24
    default: return 18
    }
  }
}

extension ReadingSheet where Sidebar == EmptyView {
  /// 单栏：标题 + 正文。
  init(title: String?, titleColor: Color = .primary, blocks: [ReadingBlock]) {
    self.title = title
    self.titleColor = titleColor
    self.chunks = Self.chunks(for: blocks, hasSidebar: false)
    self.sidebar = nil
  }
}

private struct ReadingTextLayout: ViewModifier {
  func body(content: Content) -> some View {
    content
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
