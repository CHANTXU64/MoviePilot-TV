import Kingfisher
import SwiftUI

struct BestResultCard: View {
  let title: String
  let type: String?
  let posterUrl: URL?
  let subtitle: String?
  let action: () -> Void

  @FocusState private var isFocused: Bool
  @State private var isImageFailed: Bool = false

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

      if !isImageFailed, let url = posterUrl {
        KFImage(url)
          .requestModifier(AnyModifier.cookieModifier)
          .onFailure { _ in
            isImageFailed = true
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
    }
  }
}
