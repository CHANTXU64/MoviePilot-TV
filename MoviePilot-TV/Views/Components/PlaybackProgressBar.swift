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

/// 剧照左下角的角标：可选图标、可选的已播放进度条和一行短字（单集是时长，「继续观看」是季集）。
/// 直接压在剧照上，不垫底座；托底的浅渐变由卡片自己铺（见 `ImageBadgeScrim`）。
struct StillCornerBadge: View {
  /// 没有图标时只画进度和短字（「继续观看」按下打开详情页的那种就不带图标）。
  let symbol: String?
  var tint: Color = .white
  /// 看过一部分时的已播放进度（0…1），画在图标和短字中间。
  var progress: Double? = nil
  var text: String? = nil
  var isFocused = false

  var body: some View {
    HStack(spacing: 10) {
      if let symbol {
        Image(systemName: symbol)
          .imageScale(.small)
          .foregroundStyle(tint)
      }
      if let progress {
        PlaybackProgressBar(fraction: progress)
          .foregroundStyle(.white)
      }
      if let text {
        Text(text)
          .foregroundStyle(.white)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
    // 和海报四角徽标同一级（caption2，tvOS 最小字号），比卡片下面的标题（caption）小一级。
    .font(.caption2.bold())
    // 只改透明度：没聚焦时次一级，聚焦时全亮，跟着卡片的聚焦动画变化。
    .opacity(isFocused ? 1 : 0.65)
    .padding(ImageBadgeScrim.inset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
}
