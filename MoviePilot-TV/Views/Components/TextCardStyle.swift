import SwiftUI

/// 文字类卡片的统一外观：圆角底板，未聚焦时贴近背景（8% 白），
/// 聚焦时提亮到 20% 白、放大到 1.06 倍并投影，按下时略回缩。
/// 不画描边，也不用系统 `.card`：后者在深色 Sheet 上只看得到大小变化。
struct TextCardFocusAppearance: ViewModifier {
  let isFocused: Bool
  var isPressed = false

  static let cornerRadius: CGFloat = 24
  static let focusedScale: CGFloat = 1.06
  static let pressedScale: CGFloat = 1.03

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    content
      .background(shape.fill(Color.white.opacity(isFocused ? 0.2 : 0.08)))
      .clipShape(shape)
      .scaleEffect(isFocused ? (isPressed ? Self.pressedScale : Self.focusedScale) : 1)
      .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 14)
      .animation(.easeOut(duration: 0.18), value: isFocused)
      .animation(.easeInOut(duration: 0.1), value: isPressed)
  }
}

/// 按钮形式的文字卡片。
struct TextCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    CardBody(configuration: configuration)
  }

  private struct CardBody: View {
    let configuration: Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .modifier(TextCardFocusAppearance(isFocused: isFocused, isPressed: configuration.isPressed))
    }
  }
}

extension View {
  /// 自己管理焦点（`focusable` + `@FocusState`）的文字卡片使用的同一外观。
  func textCardFocusAppearance(isFocused: Bool) -> some View {
    modifier(TextCardFocusAppearance(isFocused: isFocused))
  }
}
