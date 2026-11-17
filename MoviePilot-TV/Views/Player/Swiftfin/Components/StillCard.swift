//
// 播放器「章节」「选集」面板的剧照卡。
// 16:9 剧照、圆角 20、聚焦放大并投影（同 App 的图片卡，`posterCardFocusLift`）；
// 剧照左下角一行小字（章节的起点或第几季第几集），剧照下面一行粗体标题，聚焦时标题变亮。卡片和标题下面都不垫底。
// 没有图（还没加载出来、没有图或加载失败）时，剧照的位置是一块玻璃加图标，与播放界面其他玻璃同一种。
// 画面不压暗，文字加一层投影，亮画面上也看得清；剧照上的小字另在剧照底部加一层渐变，没图时不加。
//

import Kingfisher
import SwiftUI

enum StillCardLayout {
  /// 卡片行左右的留白，与播放界面其他控件对齐（见 `ViewLayout.horizontalSafeInset`）。五张卡正好铺满：5×326 + 4×32 + 2×81 = 1920。
  static let rowInset: CGFloat = ViewLayout.horizontalSafeInset
  static let size = CGSize(width: 326, height: 183)
  /// 卡片之间的距离。比 20 大是为了聚焦时左右各放大 16 后仍留 16pt 空隙。
  static let spacing: CGFloat = 32
}

struct StillCard<Item: Poster>: View {

  @Environment(\.self)
  private var environment

  let item: Item
  /// 剧照左下角的小字：章节的起点，或「第几季第几集」；没有时不显示。
  let badge: String?
  let title: String
  /// 焦点由所在的卡片行管理（行要把默认焦点放在正在播的那一项上）。
  let isFocused: Bool
  var stillSize = StillCardLayout.size
  let action: () -> Void

  /// 已经加载出来的图片地址：按比例完整显示时，图出来以后才铺黑底，盖住下面的玻璃和图标（同 `PosterImage`）。
  @State
  private var loadedURL: URL?

  private var imageURL: URL? {
    item.imageSources(
      for: .landscape,
      size: .custom(width: stillSize.width),
      environment: item.resolveEnvironment(environment)
    )
    .lazy
    .compactMap(\.url)
    .first
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: EpisodeCardLayout.textGap) {
        still
          .posterCardFocusLift(
            isFocused: isFocused, width: stillSize.width, cornerRadius: EpisodeCardLayout.stillCornerRadius)
        StillCardTitle(title: title, focusProgress: isFocused ? 1 : 0, stillSize: stillSize)
      }
      .frame(width: stillSize.width, alignment: .leading)
      .contentShape(.rect)
    }
    .buttonStyle(PosterCardButtonStyle())
    .focusEffectDisabled()
    .posterCardFocusAnimation(isFocused: isFocused)
    .posterAccessibility(for: item)
  }

  private var hasLoadedImage: Bool {
    imageURL != nil && loadedURL == imageURL
  }

  private var still: some View {
    ZStack(alignment: .bottomLeading) {
      // 图片盖在玻璃和图标上面：加载出来之前、没有图或加载失败时露出玻璃和图标。
      PlayerGlassBackground(shape: RoundedRectangle(cornerRadius: EpisodeCardLayout.stillCornerRadius))
      Image(systemName: item.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      if let imageURL {
        if item.fitsPosterImage, loadedURL == imageURL {
          Color.black
        }

        PageManagedImage(
          url: imageURL,
          processor: DownsamplingImageProcessor(size: stillSize),
          isEnabled: true,
          participatesInPageLifecycle: false,
          skipsMemoryCache: false,
          fitsWholeImage: item.fitsPosterImage,
          onSuccess: { loadedURL = imageURL }
        )
      }

      if let badge {
        if hasLoadedImage {
          // 只铺剧照下半截，越往下越深：亮的剧照上小字也看得清。
          LinearGradient(
            stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.5), location: 1)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

        Text(badge)
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
          .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
      }
    }
    .frame(width: stillSize.width, height: stillSize.height)
    // 无障碍朗读由 `posterAccessibility` 给出（含章节起点、季集）。
    .accessibilityHidden(true)
  }
}

/// 剧照下面的标题，字号、颜色同详情页选集卡（`EpisodeCardText`）的标题，不加聚焦底板。
private struct StillCardTitle: View, Animatable {
  let title: String
  nonisolated var focusProgress: CGFloat
  let stillSize: CGSize

  nonisolated var animatableData: CGFloat {
    get { focusProgress }
    set { focusProgress = newValue }
  }

  /// 弹簧动画会略冲过 0…1，颜色混合只取这个范围。
  private var clampedProgress: Double { Double(min(max(focusProgress, 0), 1)) }

  var body: some View {
    Text(title)
      .font(.caption.bold())
      .foregroundStyle(Color.secondary.mix(with: .primary, by: clampedProgress))
      .lineLimit(1, reservesSpace: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
      // 跟着放大后的剧照底边往下让，不压到剧照上。
      .offset(
        y: PosterCardFocus.focusedTextOffset(forImageSize: stillSize, stackSpacing: EpisodeCardLayout.textGap)
          * focusProgress)
  }
}
