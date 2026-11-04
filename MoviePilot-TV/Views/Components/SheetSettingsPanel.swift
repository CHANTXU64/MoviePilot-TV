import Flow
import SwiftUI

/// 三栏设置大面板（订阅、整理共用）。
///
/// 左栏从上到下：固定信息、居中的当前项说明、出错提示和主按钮（固定在底部）；
/// 右边设置不分组，按顺序平铺成两列，前一半放左列，一次全部显示、不滚动。
/// 以后加新设置项只是多一行，两列自动重新平分。
struct SheetSettingsPanel<Field: Hashable, Info: View, Actions: View, Row: View>: View {
  let fields: [Field]
  let focusedField: FocusState<Field?>.Binding
  /// 左栏居中的说明：一般是当前设置项的说明，焦点在主按钮上时也可以给按钮的说明。
  let helpText: String?
  @ViewBuilder let info: () -> Info
  @ViewBuilder let actions: () -> Actions
  @ViewBuilder let row: (Field) -> Row

  static var width: CGFloat { 1640 }
  static var sidebarWidth: CGFloat { 440 }

  var body: some View {
    let half = (fields.count + 1) / 2
    let columns = [Array(fields.prefix(half)), Array(fields.dropFirst(half))]

    HStack(alignment: .top, spacing: 56) {
      VStack(alignment: .leading, spacing: 0) {
        info()

        // 说明放在信息和主按钮之间的空白正中、文字居中，和上面的信息区分开；
        // 固定占两行，焦点换到说明更短的项时左栏高度不变。
        Spacer(minLength: 48)
        Text(helpText ?? " ")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2, reservesSpace: true)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
          .animation(.easeOut(duration: 0.2), value: helpText)
        Spacer(minLength: 48)

        actions()
      }
      .frame(width: Self.sidebarWidth, alignment: .topLeading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
      .focusSection()

      ForEach(columns.indices, id: \.self) { index in
        VStack(alignment: .leading, spacing: 18) {
          ForEach(columns[index], id: \.self) { field in
            row(field)
              .focused(focusedField, equals: field)
          }
        }
        // 撑满整个面板高度：设置项少、列比左栏矮时，从左栏底部的按钮往右也能进到这一列。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 56)
    .padding(.vertical, 52)
    .frame(width: Self.width, alignment: .topLeading)
    .applySheetStyles()
    // 打开大面板就是要改，焦点落在第一项设置。
    .defaultFocus(focusedField, fields.first)
  }
}

/// 出错原因：居中的一行小字，只有图标用橙色提醒；能重试时下面放整行宽的「重试」。
/// 所有出错情况都用这一种样子，不替换、不隐藏其他按钮。
///
/// 重试期间「重试」显示加载中但仍可聚焦（按了不响应）：tvOS 上聚焦的按钮变成禁用或消失，
/// 焦点会被系统挪到别处。所以调用方在重试期间要继续显示这条提示，结束后再决定焦点去向。
struct SheetMessageBlock: View {
  let message: String
  var retry: (() -> Void)? = nil
  var isRetrying = false
  var retryFocus: FocusState<Bool>.Binding? = nil

  var body: some View {
    VStack(spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(.orange)
        // 后端的长错误最多三行，放不下时略缩小字号，和其他 Sheet 的提示一致。
        Text(message)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .minimumScaleFactor(0.75)
      }
      .font(.caption)
      .frame(maxWidth: .infinity)

      if let retry {
        SheetActionButton(
          title: "重试", systemImage: "arrow.clockwise", loadingTitle: "重试中",
          isLoading: isRetrying, focus: retryFocus, action: retry)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// 一项带图标的小字信息，例如「🌐 默认站点」「✓ 整理成功」。
/// 颜色跟随外层（见 `SheetInfoTags`）；需要提醒时（如做种数少）传入 `tint`。
struct SheetInfoTag: View {
  let systemImage: String
  let text: String
  var tint: Color? = nil

  var body: some View {
    let label = HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(text)
    }
    if let tint {
      label.foregroundStyle(tint)
    } else {
      label
    }
  }
}

/// 一排信息标签：小字、灰色，放不下时换行，单项不折行。
struct SheetInfoTags<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    HFlow(itemSpacing: 24, rowSpacing: 8) {
      content()
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }
}

/// 快速确认面板（添加下载、下载字幕共用）：宽 1400，左栏是这条资源的信息（不可聚焦），
/// 右栏 600 宽放少量设置和主按钮。
struct SheetQuickPanel<Info: View, Controls: View>: View {
  @ViewBuilder let info: () -> Info
  @ViewBuilder let controls: () -> Controls

  static var width: CGFloat { 1400 }
  /// 设置项和主按钮只占右边，不随 Sheet 拉成整行。
  static var controlsWidth: CGFloat { 600 }

  var body: some View {
    HStack(alignment: .top, spacing: 56) {
      info()
        .frame(maxWidth: .infinity, alignment: .topLeading)

      VStack(alignment: .leading, spacing: 0) {
        controls()
      }
      .frame(width: Self.controlsWidth)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 56)
    .padding(.vertical, 52)
    .frame(width: Self.width, alignment: .topLeading)
    .applySheetStyles()
  }
}

/// 快速确认面板左栏：标题（加粗，最多 3 行）、副标题（最多 8 行）和一排信息标签。
struct SheetItemHeader<Tags: View>: View {
  let title: String
  let subtitle: String?
  @ViewBuilder let tags: () -> Tags

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.callout.bold())
          .lineLimit(3)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(8)
        }
      }
      SheetInfoTags(content: tags)
        .padding(.top, 16)
    }
  }
}

/// 出错提示的保留规则（`SheetRetryingMessage` 用；纯逻辑，便于直接测试）。
///
/// 重试、保存时 ViewModel 往往先清掉出错原因再开始；忙的这段时间继续显示上一条。
/// 不在忙时出错原因变空（用户自己改好了，或重试没有真正开始），就同时忘掉，
/// 下次再忙时不会把已经解决的旧提示翻出来。
struct SheetMessageRetention: Equatable {
  private(set) var retainedMessage: String?
  private(set) var retainedHasRetry = false

  /// 当前要显示的提示。
  func shownMessage(current: String?, isBusy: Bool) -> String? {
    current ?? (isBusy ? retainedMessage : nil)
  }

  /// 显示的是保留下来的提示时，按当时有没有「重试」决定。
  func showsRetry(current: String?, currentHasRetry: Bool) -> Bool {
    current == nil ? retainedHasRetry : currentHasRetry
  }

  mutating func update(current: String?, hasRetry: Bool, isBusy: Bool) {
    if let current {
      retainedMessage = current
      retainedHasRetry = hasRetry
    } else if !isBusy {
      retainedMessage = nil
      retainedHasRetry = false
    }
  }
}

/// 面板里的出错提示（各 Sheet 共用）：显示 `SheetMessageBlock`，并处理重试期间的焦点。
///
/// 保留规则见 `SheetMessageRetention`。提示消失时焦点还在「重试」上，就调用 `onRecovered`，
/// 由面板把焦点移到主按钮，不让系统随便挪。
struct SheetRetryingMessage: View {
  /// ViewModel 当前的出错原因。
  let message: String?
  /// 加载、保存或提交进行中。
  let isBusy: Bool
  /// 当前出错能重试时传入；整理失败这类直接再按主按钮的情况传 nil。
  let retry: (() -> Void)?
  /// 显示提示时与相邻按钮的间距；不显示时不占位，面板高度不跟着忙闲变化。
  var spacingEdges: Edge.Set = .bottom
  var spacing: CGFloat = 20
  var onRecovered: () -> Void = {}

  @State private var retention = SheetMessageRetention()
  @FocusState private var isRetryFocused: Bool

  private struct Input: Equatable {
    let message: String?
    let hasRetry: Bool
    let isBusy: Bool
  }

  private var shownMessage: String? {
    retention.shownMessage(current: message, isBusy: isBusy)
  }

  var body: some View {
    VStack(spacing: 0) {
      if let shownMessage {
        let showsRetry = retention.showsRetry(current: message, currentHasRetry: retry != nil)
        SheetMessageBlock(
          message: shownMessage,
          // 显示的是保留下来的提示时，「重试」照样留着（忙的时候按了不响应）。
          retry: showsRetry ? (message == nil ? {} : retry) : nil,
          isRetrying: isBusy,
          retryFocus: $isRetryFocused
        )
        .padding(spacingEdges, spacing)
      }
    }
    .onChange(of: Input(message: message, hasRetry: retry != nil, isBusy: isBusy), initial: true) {
      _, input in
      retention.update(current: input.message, hasRetry: input.hasRetry, isBusy: input.isBusy)
    }
    .onChange(of: shownMessage) { old, new in
      if old != nil, new == nil, isRetryFocused { onRecovered() }
    }
  }
}
