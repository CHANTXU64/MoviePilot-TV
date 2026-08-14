import Kingfisher
import SwiftUI

struct BestResultCard: View {
  let title: String
  let type: String?
  let posterUrl: URL?
  /// 降尺寸海报加载失败时回退的原始海报 URL。
  let posterFallbackUrl: URL?
  let subtitle: String?
  let action: () -> Void

  @FocusState private var isFocused: Bool
  @State private var isImageFailed: Bool = false
  @State private var isUsingFallback: Bool = false

  init(
    title: String,
    type: String? = nil,
    posterUrl: URL? = nil,
    posterFallbackUrl: URL? = nil,
    subtitle: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.type = type
    self.posterUrl = posterUrl
    self.posterFallbackUrl = posterFallbackUrl
    self.subtitle = subtitle
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 20) {
        // 海报
        posterContent
          .frame(width: 100, height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 16))

        // 详情
        VStack(alignment: .leading, spacing: 8) {
          Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .lineLimit(3)
            .foregroundStyle(isFocused ? .primary : .secondary)
          if let subtitle = subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(20)
      .frame(width: 500, alignment: .leading)
    }
    .buttonStyle(.card)
    .focused($isFocused)
    .frame(width: 500, height: 190)
    .animation(.easeInOut(duration: 0.2), value: isFocused)
  }

  private func typeIcon(_ type: String?) -> String {
    switch type {
    case "电影": return "film"
    case "电视剧": return "tv"
    case "合集": return "rectangle.stack"
    case "人物": return "person.fill"
    default: return "film"
    }
  }

  private var posterContent: some View {
    ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          Image(systemName: typeIcon(type))
            .font(.largeTitle)
            .foregroundColor(.gray)
        )

      if !isImageFailed, let url = isUsingFallback ? posterFallbackUrl : posterUrl {
        KFImage.sessionImage(url)
          .onFailure { _ in
            // 降尺寸海报加载失败时回退到原始 URL 重试一次，仍失败才隐藏。
            if !isUsingFallback, posterFallbackUrl != nil {
              isUsingFallback = true
            } else {
              isImageFailed = true
            }
          }
          .placeholder {
            Rectangle()
              .fill(Color(white: 0.12))
              .overlay(ProgressView().tint(.gray))
          }
          .resizing(referenceSize: CGSize(width: 100, height: 150), mode: .aspectFill)
          .resizable()
          .fade(duration: 0.25)
          .aspectRatio(contentMode: .fill)
      }
    }
    .onChange(of: posterUrl) { _, _ in
      isImageFailed = false
      isUsingFallback = false
    }
  }
}
