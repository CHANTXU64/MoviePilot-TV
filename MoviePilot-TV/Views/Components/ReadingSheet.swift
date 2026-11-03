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

  /// 按换行拆段，去掉首尾空白与空段。
  static func paragraphs(_ text: String) -> [String] {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// 富文本版本：保留 AniList Markdown 等富文本属性。
  static func paragraphs(_ text: AttributedString) -> [AttributedString] {
    text.characters
      .split(whereSeparator: \.isNewline)
      .compactMap { slice in trimmed(text[slice.startIndex..<slice.endIndex]) }
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
      return split(block.text, maxCharacters: lineWidth(block.style) * lineBudget).enumerated().map { index, text in
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
      let count = piece.text.characters.count
      let width = lineWidth(piece.style)
      let lines = max(1, (count + width - 1) / width)
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

  /// 把超长文本拆成不超过 `maxCharacters` 的片段，优先在句末断开；找不到句末时硬切。
  ///
  /// 只去掉断点处的空白：第一片保留原有行首缩进（日志里的 JSON、堆栈），
  /// 后续片段去掉断点后的前导空白，片尾空白不影响显示。
  static func split(_ text: AttributedString, maxCharacters: Int) -> [AttributedString] {
    let limit = max(1, maxCharacters)
    let characters = text.characters
    guard characters.count > limit else { return [text] }

    var pieces: [AttributedString] = []
    var start = characters.startIndex
    while start < characters.endIndex {
      if !pieces.isEmpty {
        guard let next = characters[start...].firstIndex(where: { !$0.isWhitespace }) else { break }
        start = next
      }
      let remaining = characters.distance(from: start, to: characters.endIndex)
      if remaining <= limit {
        if let piece = nonBlank(text[start..<characters.endIndex]) { pieces.append(piece) }
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
      if let piece = nonBlank(text[start..<cut]) { pieces.append(piece) }
      start = cut
    }
    return pieces
  }

  private static let sentenceTerminators: Set<Character> = [
    "。", "！", "？", "；", "…", ".", "!", "?", ";",
  ]

  /// 原样保留片段（含空白），整段都是空白时丢弃。
  private static func nonBlank(_ substring: AttributedSubstring) -> AttributedString? {
    guard substring.characters.contains(where: { !$0.isWhitespace }) else { return nil }
    return AttributedString(substring)
  }

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
/// `ReadingSheetLayout.chunks` 分成焦点停靠块（关闭焦点高亮），默认焦点在第一块，
/// 遥控器返回键关闭。
struct ReadingSheet<Sidebar: View>: View {
  let title: String?
  var titleColor: Color = .primary
  let blocks: [ReadingBlock]
  let sidebar: Sidebar?

  @FocusState private var focusedChunkIndex: Int?

  init(
    title: String?,
    titleColor: Color = .primary,
    blocks: [ReadingBlock],
    @ViewBuilder sidebar: () -> Sidebar
  ) {
    self.title = title
    self.titleColor = titleColor
    self.blocks = blocks
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
    .defaultFocus($focusedChunkIndex, 0)
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

  private var chunks: [[ReadingBlock]] {
    ReadingSheetLayout.chunks(
      blocks.isEmpty ? [ReadingBlock("（暂无内容）", style: .secondary)] : blocks,
      charactersPerLine: ReadingSheetLayout.charactersPerLine(hasSidebar: sidebar != nil)
    )
  }

  @ViewBuilder
  private func blockView(_ block: ReadingBlock) -> some View {
    switch block.style {
    case .body:
      Text(block.text)
        .font(.body)
        .modifier(ReadingTextLayout())
    case .secondary:
      Text(block.text)
        .font(.body)
        .foregroundStyle(.secondary)
        .modifier(ReadingTextLayout())
    case .heading:
      Text(block.text)
        .font(.headline)
        .modifier(ReadingTextLayout())
    case .field(let label):
      HStack(alignment: .firstTextBaseline, spacing: ReadingSheetLayout.fieldSpacing) {
        Text(block.startsParagraph ? label : "")
          .font(.body.bold())
          .frame(width: ReadingSheetLayout.fieldLabelWidth, alignment: .leading)
        Text(block.text)
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
    self.blocks = blocks
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
