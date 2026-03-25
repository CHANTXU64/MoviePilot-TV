import Kingfisher
import SwiftUI

/// 专门用于列表末尾“查看全部”或“更多”操作的卡片组件，去除了 MediaCard 复杂的徽章层级，仅保留背景毛玻璃和居中文字。
struct MoreCard: View {
  let titleText: String
  let posterUrl: URL?
  let action: () -> Void

  @FocusState private var isFocused: Bool
  private let width: CGFloat = 256
  private let height: CGFloat = 384

  var body: some View {
    VStack(spacing: 10) {
      // 海报图片及模糊背景
      Button(action: action) {
        ZStack {
          if let url = posterUrl {
            KFImage(url)
              .requestModifier(AnyModifier.cookieModifier)
              .placeholder {
                Color(white: 0.12)
              }
              .downsampling(size: CGSize(width: width, height: height))
              .resizing(referenceSize: CGSize(width: 256, height: 384), mode: .aspectFill)
              .resizable()
              .fade(duration: 0.25)
              .aspectRatio(contentMode: .fill)
              .frame(width: width, height: height)
              .blur(radius: 20)
              .clipped()
          } else {
            Color(white: 0.12)
              .frame(width: width, height: height)
          }

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
        .clipShape(RoundedRectangle(cornerRadius: 20))
      }
      .buttonStyle(.plain)
      .focused($isFocused)
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .shadow(
        color: .black.opacity(isFocused ? 0.5 : 0),
        radius: 20,
        y: 10
      )
      .scaleEffect(isFocused ? 1.1 : 1.0)
      .animation(.easeInOut(duration: 0.2), value: isFocused)

      // 文本占位区 (与 MediaCard 保持一致的高度)
      VStack(spacing: 4) {
        VStack {
          // 对齐 title
          Text(" ")
            .font(.caption)
            .fontWeight(.medium)

          // 固定占位对齐 footerLabel
          HStack(spacing: 4) {
            Image(systemName: "plus.circle")
            Text(" ")
          }
          .font(.caption)
          .fontWeight(.medium)
          .opacity(0)
        }
        .lineLimit(1)
        .compositingGroup()
        .frame(maxWidth: width, alignment: .center)
      }
    }
  }
}
