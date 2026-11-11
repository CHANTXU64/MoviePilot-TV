import Kingfisher
import SwiftUI

/// 媒体结果卡片（搜索页「最佳结果」、查询媒体 ID 共用）：第一行片名，第二行「类型 · 年份 · 来源」。
struct BestResultCard: View {
  /// 第二行信息的统一写法，两处结果列表都用它。
  static func mediaSubtitle(for media: MediaInfo) -> String {
    let type = media.subscribeShare != nil ? "订阅分享" : media.type
    return [type, media.year, sourceTitle(for: media.source)]
      .compactMap { MediaIdentifier.normalizedString($0) }
      .joined(separator: " · ")
  }

  static func sourceTitle(for source: String?) -> String? {
    switch source {
    case "themoviedb": "TMDB"
    case "douban": "豆瓣"
    case "bangumi": "Bangumi"
    case "anilist": "AniList"
    default: source
    }
  }

  let title: String
  let type: String?
  let posterUrl: URL?
  /// 降尺寸海报加载失败时回退的原始海报 URL。
  let posterFallbackUrl: URL?
  let subtitle: String?
  let loadsImage: Bool
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
    loadsImage: Bool = true,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.type = type
    self.posterUrl = posterUrl
    self.posterFallbackUrl = posterFallbackUrl
    self.subtitle = subtitle
    self.loadsImage = loadsImage
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
            .bold()
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
    .buttonStyle(TextCardButtonStyle())
    .focused($isFocused)
    .frame(width: 500, height: 190)
    .animation(.easeInOut(duration: 0.2), value: isFocused)
  }

  private var posterContent: some View {
    ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          // 缺图占位只是提示类型，图标不宜比海报里的内容还显眼。
          Image(systemName: MediaTypePresentation.placeholderIconName(for: type))
            .font(.body)
            .foregroundColor(.gray)
        )

      PageManagedImage(
        url: isUsingFallback ? posterFallbackUrl : posterUrl,
        processor: ResizingImageProcessor(
          referenceSize: CGSize(width: 100, height: 150),
          mode: .aspectFill
        ),
        isEnabled: loadsImage && !isImageFailed,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true,
        onFailure: {
          // 降尺寸海报加载失败时回退到原始 URL 重试一次，仍失败才隐藏。
          if !isUsingFallback, posterFallbackUrl != nil {
            isUsingFallback = true
          } else {
            isImageFailed = true
          }
        }
      )
    }
    .onChange(of: posterUrl) { _, _ in
      isImageFailed = false
      isUsingFallback = false
    }
  }
}
