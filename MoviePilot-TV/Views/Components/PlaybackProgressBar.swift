import SwiftUI

/// 已播放进度条（与 Apple TV App 一样的短横条）：放在播放图标后面，表示这一集或这部片看到了哪里。
///
/// 长度是当前字体下两个汉字宽，跟着所在位置的字号变（单集卡片角上是 caption2，详情页按钮里是按钮字号），
/// 粗细是一行字高的约五分之一。颜色跟随前景色：已看部分用前景色，没看的部分是同色半透明，
/// 放在聚焦后变白底的按钮里也会跟着变深。
struct PlaybackProgressBar: View {
  /// 看到了哪里（0…1），超出范围的按边界画。
  let fraction: Double

  var body: some View {
    // 用两个汉字占位量出长度和行高，自身不显示。
    Text(verbatim: "进度")
      .hidden()
      .overlay {
        GeometryReader { proxy in
          let height = max(3, (proxy.size.height * 0.2).rounded())
          let clamped = min(1, max(0, fraction))
          ZStack(alignment: .leading) {
            Capsule()
              .fill(.foreground.opacity(0.35))
            Capsule()
              .fill(.foreground)
              .frame(width: max(height, proxy.size.width * clamped))
          }
          .frame(height: height)
          .frame(maxHeight: .infinity)
        }
      }
      .accessibilityElement()
      .accessibilityLabel("已播放")
      .accessibilityValue(Text(clampedPercent))
  }

  private var clampedPercent: String {
    "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
  }
}
