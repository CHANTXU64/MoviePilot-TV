import Kingfisher
import SwiftUI

/// 专门用于列表末尾“查看全部”或“更多”操作的卡片组件，去除了 MediaCard 复杂的徽章层级，仅保留背景毛玻璃和居中文字。
struct MoreCard: View {
  let titleText: String
  let posterUrl: URL?
  var loadsImage: Bool = true
  let action: () -> Void

  @FocusState private var isFocused: Bool
  private let width: CGFloat = 256
  private let height: CGFloat = 384
  /// 背景图解码尺寸：卡片的四分之一，模糊半径相应缩成 5（相当于原尺寸上的 20）。
  private static let blurredBackdropSize = CGSize(width: 64, height: 96)

  var body: some View {
    VStack(spacing: 10) {
      // 海报图片及模糊背景
      Button(action: action) {
        posterContent
      }
      .buttonStyle(PosterCardButtonStyle())
      .focusEffectDisabled()
      .focused($isFocused)

      // 文本占位区 (与 MediaCard 保持一致的高度)
      VStack(spacing: 4) {
        VStack {
          // 对齐 title
          Text(" ")
            .font(.caption)

          // 固定占位对齐 footerLabel
          HStack(spacing: 4) {
            Image(systemName: AppSymbol.subscribe)
            Text(" ")
          }
          .font(.caption)
          .opacity(0)
        }
        .lineLimit(1)
        .compositingGroup()
        .frame(maxWidth: width, alignment: .center)
      }
    }
    .posterCardFocusAnimation(isFocused: isFocused)
  }

  private var posterContent: some View {
    ZStack {
      Color(white: 0.12)

      // 解码时缩到四分之一再模糊一次，显示时拉伸回卡片大小：看起来同样是糊的背景，
      // 但不用 `.blur` 在聚焦放大的每一帧重新模糊。
      PageManagedImage(
        url: posterUrl,
        processor: DownsamplingImageProcessor(size: Self.blurredBackdropSize)
          |> BlurImageProcessor(blurRadius: 5),
        isEnabled: loadsImage,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true
      )
      .frame(width: width, height: height)
      .clipped()

      // 半透明遮罩层
      Color.black.opacity(0.3)

      // 中间文字
      Text(titleText)
        .font(.headline.bold())
        .foregroundStyle(isFocused ? .white : .secondary)
        .multilineTextAlignment(.center)
        .padding()
    }
    .frame(width: width, height: height)
    .posterCardFocusLift(isFocused: isFocused, width: width)
  }
}
