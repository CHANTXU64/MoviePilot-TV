import Kingfisher
import SwiftUI

// 媒体数据源
enum MediaSource: String {
  case tmdb = "themoviedb"
  case douban = "douban"
  case bangumi = "bangumi"

  var iconName: String {
    switch self {
    case .tmdb: return "tmdb"
    case .douban: return "douban"
    case .bangumi: return "bangumi"
    }
  }

  /// 根据存在的 ID 从 MediaInfo 推断来源
  static func from(mediaInfo: MediaInfo) -> MediaSource? {
    if mediaInfo.tmdb_id != nil { return .tmdb }
    if mediaInfo.douban_id != nil { return .douban }
    if mediaInfo.bangumi_id != nil { return .bangumi }
    return nil
  }

  /// 根据存在的 ID 从订阅信息推断来源
  static func from(subscribe: Subscribe) -> MediaSource? {
    if subscribe.tmdbid != nil { return .tmdb }
    if subscribe.doubanid != nil { return .douban }
    if subscribe.bangumiid != nil { return .bangumi }
    return nil
  }
}

struct MediaCard: View {
  static let defaultGridColumns = [
    GridItem(.adaptive(minimum: 256, maximum: 384), spacing: 20, alignment: .top)
  ]

  let title: String
  let posterUrl: URL?
  let subtitle: String?

  // 角落文本
  let typeText: String?  // 左上角 (例如 "电影", "电视剧")
  let ratingText: String?  // 右上角 (例如 "8.5")
  let bottomLeftText: String?  // 左下角：主要状态 (例如 "已订阅")
  let bottomLeftSecondaryText: String?  // 左下角：次要状态 (例如 "更新至 10 集")
  let source: MediaSource?  // 右下角：数据源图标
  let overlayTitle: String?

  var showTopBadges: Bool = true

  @FocusState private var isFocused: Bool
  @State private var isImageFailed: Bool = false

  var width: CGFloat = 256
  var height: CGFloat = 384

  /// 在主标题下方显示的可选副标题。
  /// 注意：主 `subtitle` 属性现在主要用于聚焦时的覆盖层展示。
  var subTitleBelow: String? = nil

  /// 是否对背景图片应用模糊效果。主要用于类似“查看全部”等特殊展示。
  var isBackgroundBlurred: Bool = false

  /// 聚焦时显示的标签，通常用于“点击订阅”等操作。
  /// 如果提供，则始终保留空间以防止布局抖动。
  var footerLabel: (icon: String, text: String)? = nil

  // 卡片被点击时的操作
  var action: (() -> Void)? = nil

  init(
    title: String = "",
    posterUrl: URL? = nil,
    subtitle: String? = nil,
    typeText: String? = nil,
    ratingText: String? = nil,
    bottomLeftText: String? = nil,
    bottomLeftSecondaryText: String? = nil,
    source: MediaSource? = nil,
    overlayTitle: String? = nil,
    showTopBadges: Bool = true,
    width: CGFloat = 256,
    height: CGFloat = 384,
    subTitleBelow: String? = nil,
    isBackgroundBlurred: Bool = false,
    footerLabel: (icon: String, text: String)? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.posterUrl = posterUrl
    self.subtitle = subtitle
    self.typeText = typeText
    self.ratingText = ratingText
    self.bottomLeftText = bottomLeftText
    self.bottomLeftSecondaryText = bottomLeftSecondaryText
    self.source = source
    self.overlayTitle = overlayTitle
    self.showTopBadges = showTopBadges
    self.width = width
    self.height = height
    self.subTitleBelow = subTitleBelow
    self.isBackgroundBlurred = isBackgroundBlurred
    self.footerLabel = footerLabel
    self.action = action
  }

  var body: some View {
    VStack(spacing: 10) {
      // 海报图片 - 仅在提供操作时才包装在按钮中
      if let action = action {
        Button(action: action) {
          posterContent
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
          color: .black.opacity(isFocused ? 0.5 : 0),
          radius: isFocused ? 20 : 0,
          y: isFocused ? 10 : 0
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
      } else {
        posterContent
      }

      // 标题和副标题 - 在按钮外部，清晰分离
      textInfoView
    }
  }

  // 提取文本内容以实现统一动画
  private var textInfoView: some View {
    VStack(spacing: 4) {
      VStack {
        Text(title)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(isFocused ? .primary : .secondary)

        // 仅在明确提供 subTitleBelow 时显示
        if let subTitleBelow = subTitleBelow, !subTitleBelow.isEmpty {
          Text(subTitleBelow)
            .font(.caption2)
            .foregroundStyle(isFocused ? .secondary : .tertiary)
        }

        // 页脚标签 (保留空间以避免布局抖动)
        if let footer = footerLabel {
          HStack(spacing: 4) {
            Image(systemName: footer.icon)
            Text(footer.text)
          }
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.primary)
          .opacity(isFocused ? 1 : 0)
        }
      }
      .lineLimit(1)
      .compositingGroup()
      .frame(maxWidth: isFocused ? width + 30 : width, alignment: .center)
    }
    .frame(width: width + 30)
    .padding(.horizontal, -15)
    .offset(y: isFocused ? 18 : 0)
    .animation(.easeInOut(duration: 0.2), value: isFocused)
  }

  // 提取的海报内容 - Apple TV 风格设计
  private var posterContent: some View {
    let _ = APIService.shared.token
    return ZStack {
      // 1. 背景 / 失败状态
      // 如果图片加载失败或 URL 为空，则显示此内容
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          Image(systemName: typeIcon(typeText ?? "") ?? "film")
            .font(.title2)
            .foregroundColor(.gray)
        )

      // 2. 网络图片
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
          .resizing(referenceSize: CGSize(width: 256, height: 384), mode: .aspectFill)
          .resizable()
          .fade(duration: 0.25)
          .aspectRatio(contentMode: .fill)
          .frame(width: width, height: height)
          // TODO: 如果未来有大量需要模糊的卡片，应考虑切换回 Kingfisher 的 BlurImageProcessor，并结合图片预缓存机制（例如 Kingfisher 的 ImagePrefetcher）来优化性能，避免实时模糊带来的卡顿。
          .blur(radius: isBackgroundBlurred ? 20 : 0)
      }

      // 覆盖标题
      if let overlayTitle = overlayTitle, !overlayTitle.isEmpty {
        Color.black.opacity(0.3)
        Text(overlayTitle)
          .font(.headline.bold())
          .foregroundStyle(isFocused ? .white : .secondary)
          .multilineTextAlignment(.center)
          .padding()
      }

      // 聚焦副标题覆盖层 - 带有副标题的底部渐变
      if isFocused, let subtitle = subtitle, !subtitle.isEmpty {
        VStack {
          Spacer()
          ZStack(alignment: .bottom) {
            Rectangle()
              .fill(.black)
              .frame(height: 30)
              .blur(radius: 10)
              .offset(y: 10)
              .opacity(0.8)

            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.8))
              .lineLimit(1)
              .padding(.horizontal, 6)
              .padding(.bottom, 6)
          }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
      }

      // 覆盖徽章 - 毛玻璃风格
      VStack {
        if showTopBadges {
          // 顶行徽章
          HStack(alignment: .top, spacing: 8) {
            // 左上：媒体类型徽章
            Group {
              if let type = typeText, !type.isEmpty {
                if let iconName = typeIcon(type) {
                  // 匹配到图标，显示图标徽章
                  Image(systemName: iconName)
                } else {
                  // 未匹配到图标，直接显示文字徽章
                  Text(type)
                    .font(.caption2.weight(.medium))
                }
              } else {
                // 如果 typeText 为空或 nil，显示默认的 film 图标
                Image(systemName: "film")
              }
            }
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)

            Spacer(minLength: 0)

            // 右上：评分徽章
            if let rating = ratingText, !rating.isEmpty, let score = Double(rating), score > 0 {
              HStack(spacing: 4) {
                Image(systemName: "star.fill")
                  .font(.caption2)
                  .foregroundStyle(.yellow)
                Text(rating)
                  .font(.caption2.bold())
                  .foregroundStyle(.white)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(.ultraThinMaterial)
              .cornerRadius(8)
            }
          }
          .padding(10)
        }

        Spacer()

        let showOverlay = isFocused && subtitle != nil && !(subtitle?.isEmpty ?? true)
        if (bottomLeftText != nil || bottomLeftSecondaryText != nil || source != nil)
          && !showOverlay
        {
          HStack(alignment: .bottom, spacing: 6) {
            // 左下：状态徽章 (如果两者都存在则堆叠)
            if bottomLeftText != nil || bottomLeftSecondaryText != nil {
              HStack(spacing: 6) {
                if let status = bottomLeftText, !status.isEmpty {
                  Text(status)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
                if let secondary = bottomLeftSecondaryText, !secondary.isEmpty {
                  Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
              }
            }

            Spacer(minLength: 0)

            // 右下：来源图标
            if let source = source {
              Image(source.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
          }
          .padding(10)
        }
      }
    }
    .onChange(of: posterUrl) { _, _ in
      isImageFailed = false
    }
  }

  // 类型到 SF Symbol 图标的映射 - 如果不匹配则返回 nil
  private func typeIcon(_ type: String) -> String? {
    switch type {
    case "电影": return "film"
    case "电视剧": return "tv"
    case "合集": return "rectangle.stack"
    default: return nil
    }
  }
}
