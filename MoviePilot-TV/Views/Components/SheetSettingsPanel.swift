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
struct SheetInfoTag: View {
  let systemImage: String
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(text)
    }
  }
}
