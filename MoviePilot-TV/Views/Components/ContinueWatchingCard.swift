import Kingfisher
import SwiftUI

/// 媒体库页「继续观看」的剧照卡：16:9 剧照，左下角图标、已播放进度条和季集（电影没有季集），
/// 剧照下面只有一行居中标题，不垫聚焦底板。标题的居中、聚焦加宽和下移与海报卡共用 `posterCardTitleLayout`。
/// 剧照尺寸、间距和聚焦外观与详情页单集卡共用。
struct ContinueWatchingCard: View {
  static let stillSize = EpisodeCardLayout.stillSize
  /// 剧照与标题的间距，同 `MediaCard` 的 10pt；取大了聚焦时标题就不跟着下移，见 `posterCardTitleLayout`。
  static let titleSpacing: CGFloat = 10

  let title: String
  let stillURL: URL?
  /// 左下角图标：按下接着播是播放图标，跳媒体服务器 App 是跳转图标，打开详情页时不显示（同 `MediaCard`）。
  var icon: String? = nil
  /// 角标上的季集，如「第 2 季第 5 集」；电影或服务器没给编号时为 nil。
  var episodeText: String? = nil
  /// 已播放进度（0…1）；没有进度时为 nil。
  var progress: Double? = nil
  var loadsImage = true
  let action: () -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    Button(action: action) {
      // 间距同 `MediaCard`：剧照聚焦向下长出的部分由标题下移让开，聚焦后留 5pt。
      VStack(spacing: Self.titleSpacing) {
        still
          .posterCardFocusLift(
            isFocused: isFocused, width: Self.stillSize.width,
            cornerRadius: EpisodeCardLayout.stillCornerRadius)
        titleView
      }
      .frame(width: Self.stillSize.width)
      .contentShape(.rect)
    }
    .buttonStyle(PosterCardButtonStyle())
    .focusEffectDisabled()
    .focused($isFocused)
    .posterCardFocusAnimation(isFocused: isFocused)
    // 放进页头上移的横排时自动参与，见 `FocusLiftRowHeader`。
    .focusLiftCard(isFocused: isFocused)
    .accessibilityLabel(title)
    .accessibilityValue(
      [episodeText, progress.map { "已播放 \(Int(($0 * 100).rounded()))%" }]
        .compactMap { $0 }.joined(separator: "，"))
  }

  private var titleView: some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(isFocused ? .primary : .secondary)
      .lineLimit(1)
      .compositingGroup()
      .posterCardTitleLayout(
        isFocused: isFocused, width: Self.stillSize.width, imageSize: Self.stillSize,
        stackSpacing: Self.titleSpacing)
  }

  private var still: some View {
    ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
      Image(systemName: AppSymbol.imagePlaceholder)
        .font(.title3)
        .foregroundStyle(.secondary)
      PageManagedImage(
        url: stillURL,
        processor: DownsamplingImageProcessor(size: Self.stillSize),
        isEnabled: loadsImage,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true
      )
      // 下沿浅渐变每张都铺，亮剧照上的角标也看得清。
      ImageBadgeScrim.bottomLayer(imageHeight: Self.stillSize.height)
      StillCornerBadge(
        symbol: icon, progress: progress, text: episodeText, isFocused: isFocused)
    }
    .frame(width: Self.stillSize.width, height: Self.stillSize.height)
    .accessibilityHidden(true)
  }
}