import SwiftUI

/// 图片类卡片（媒体海报、人物、查看全部、单集剧照）共用的聚焦与按下外观。
///
/// - 聚焦：图片放大、阴影浮起、左上高光淡入，弹簧动画。
/// - 按下：缩回接近原尺寸、阴影变淡、压暗一点，和聚焦区分开。
/// - 卡片容器挂 `posterCardFocusAnimation`，图片、高光、阴影在同一次弹簧动画里变化。
/// - 标题聚焦时加宽，用 `posterCardTitleAnimation` 单独走不回弹的 easeOut（和图片同时起步、慢慢停）：
///   宽度每变一点，单行标题就重新截断、居中位置跳半个字宽，弹簧冲过头再回来会让标题来回抖。
///
/// 放大按「左右各多出固定点数」换算倍数，宽窄不同的卡片浮起的距离一致，
/// 也不会挤到 40–44pt 间距外的相邻卡片。
///
/// 只动 transform 和 opacity，不用 blur、material 或会变化的阴影半径。
/// 不用系统 `.card`：真机上它每帧的 GPU 时间约是这套的两倍，整页重建也更慢。
enum PosterCardFocus {
  /// 聚焦时卡片左右各多出的点数。
  static let focusedGrowth: CGFloat = 16
  /// 按下时左右各多出的点数：接近原尺寸。
  static let pressedGrowth: CGFloat = 4

  static let shadowOpacity = 0.62
  static let pressedShadowOpacity = 0.3
  static let shadowRadius: CGFloat = 20
  static let shadowY: CGFloat = 10
  static let pressedBrightness = -0.1
  static let cornerRadius: CGFloat = 20

  /// 聚焦时标题可用宽度比卡片多出的部分，与图片左右多出的宽度一致。
  static let focusedTextExtraWidth: CGFloat = focusedGrowth * 2
  /// 聚焦时标题与放大后图片底边之间保留的距离（卡片 VStack 间距为 10）。
  private static let focusedTextSpacing: CGFloat = 5

  static let animation = Animation.spring(response: 0.3, dampingFraction: 0.82)
  static let pressAnimation = Animation.easeInOut(duration: 0.1)
  static let titleAnimation = Animation.easeOut(duration: 0.2)

  static func focusedScale(forWidth width: CGFloat) -> CGFloat {
    scale(forWidth: width, growth: focusedGrowth)
  }

  static func pressedScale(forWidth width: CGFloat) -> CGFloat {
    scale(forWidth: width, growth: pressedGrowth)
  }

  /// 竖排卡片聚焦时标题下移多少：跟着放大后的图片底边，保留 `focusedTextSpacing`。
  static func focusedTextOffset(forImageSize size: CGSize, stackSpacing: CGFloat = 10) -> CGFloat {
    let bottomGrowth = size.height * (focusedScale(forWidth: size.width) - 1) / 2
    return max(0, bottomGrowth - (stackSpacing - focusedTextSpacing))
  }

  private static func scale(forWidth width: CGFloat, growth: CGFloat) -> CGFloat {
    guard width > 0 else { return 1 }
    return 1 + growth * 2 / width
  }
}

/// 图片类卡片的按钮样式：只把按下状态交给卡片内的 `posterCardFocusLift`。
struct PosterCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressBody(configuration: configuration)
  }

  private struct PressBody: View {
    let configuration: Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .environment(\.posterCardIsPressed, configuration.isPressed)
        .animation(reduceMotion ? nil : PosterCardFocus.pressAnimation, value: configuration.isPressed)
    }
  }
}

private struct PosterCardIsPressedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  fileprivate var posterCardIsPressed: Bool {
    get { self[PosterCardIsPressedKey.self] }
    set { self[PosterCardIsPressedKey.self] = newValue }
  }
}

private struct PosterCardFocusLift: ViewModifier {
  let isFocused: Bool
  let width: CGFloat
  let cornerRadius: CGFloat
  @Environment(\.posterCardIsPressed) private var environmentPressed

  func body(content: Content) -> some View {
    // 长按弹出菜单后按钮可能不复位，只在聚焦时显示按下态。
    let isPressed = isFocused && environmentPressed
    content
      .overlay {
        // 高光每张卡都挂着、只改透明度，焦点移动时不插入或删除视图。
        LinearGradient(
          colors: [.white.opacity(0.24), .white.opacity(0.05), .clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .opacity(isFocused ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .brightness(isPressed ? PosterCardFocus.pressedBrightness : 0)
      .shadow(
        color: .black.opacity(
          isFocused ? (isPressed ? PosterCardFocus.pressedShadowOpacity : PosterCardFocus.shadowOpacity) : 0
        ),
        radius: PosterCardFocus.shadowRadius,
        y: PosterCardFocus.shadowY
      )
      .scaleEffect(
        isFocused
          ? (isPressed ? PosterCardFocus.pressedScale(forWidth: width) : PosterCardFocus.focusedScale(forWidth: width))
          : 1
      )
  }
}

private struct PosterCardFocusAnimation: ViewModifier {
  let isFocused: Bool
  let animation: Animation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(reduceMotion ? nil : animation, value: isFocused)
  }
}

extension View {
  /// 卡片图片的聚焦与按下外观：高光、圆角裁切、压暗、阴影、放大。
  /// 挂在未裁切、已定尺寸的图片上（裁切由这里完成），并放在 `PosterCardButtonStyle` 按钮的 label 里，才能拿到按下状态。
  func posterCardFocusLift(
    isFocused: Bool,
    width: CGFloat,
    cornerRadius: CGFloat = PosterCardFocus.cornerRadius
  ) -> some View {
    modifier(PosterCardFocusLift(isFocused: isFocused, width: width, cornerRadius: cornerRadius))
  }

  /// 卡片容器统一的聚焦动画；开启「减弱动态效果」时直接切换。
  func posterCardFocusAnimation(isFocused: Bool) -> some View {
    modifier(PosterCardFocusAnimation(isFocused: isFocused, animation: PosterCardFocus.animation))
  }

  /// 卡片标题的聚焦动画：覆盖容器的弹簧动画，加宽过程单调不回弹。
  func posterCardTitleAnimation(isFocused: Bool) -> some View {
    modifier(PosterCardFocusAnimation(isFocused: isFocused, animation: PosterCardFocus.titleAnimation))
  }
}
