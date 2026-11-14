import Kingfisher
import SwiftUI

// 媒体数据源
enum MediaSource: String {
  case tmdb = "themoviedb"
  case douban = "douban"
  case bangumi = "bangumi"
  case anilist = "anilist"

  var assetName: String {
    switch self {
    case .tmdb: return "tmdb"
    case .douban: return "douban"
    case .bangumi: return "bangumi"
    case .anilist: return "anilist"
    }
  }

  static func from(source: String?) -> MediaSource? {
    source.flatMap(MediaSource.init(rawValue:))
  }

  /// Web MediaCard 严格按 media.source 显示角标，不根据辅助 ID 猜测。
  static func from(mediaInfo: MediaInfo) -> MediaSource? {
    guard mediaInfo.subscribeShare == nil else { return nil }
    return from(source: mediaInfo.source)
  }

}

/// 统一卡片媒体类型图标，未知类型只用于缺图占位，不冒充电影。
enum MediaTypePresentation {
  private static let iconMap: [String: String] = [
    "电影": AppSymbol.movie,
    "电视剧": AppSymbol.tv,
    "合集": AppSymbol.collection,
    "人物": AppSymbol.person,
  ]

  static func iconName(for typeText: String?) -> String? {
    guard let typeText else { return nil }
    return iconMap[typeText]
  }

  /// 左上角徽章维持既有边界：人物仍显示文字，仅三种媒体类型显示图标。
  static func badgeIconName(for typeText: String?) -> String? {
    guard typeText == "电影" || typeText == "电视剧" || typeText == "合集" else {
      return nil
    }
    return iconName(for: typeText)
  }

  static func placeholderIconName(for typeText: String?) -> String {
    iconName(for: typeText) ?? AppSymbol.imagePlaceholder
  }
}

/// 图片上徽标的托底：有徽标的上沿或下沿铺一条由深到透明的浅渐变，不给每个徽标单独垫底座。
/// 只轻轻压一点，白色粗体徽标在亮图上也能分出来，不让图片边缘发黑。海报和单集剧照共用。
enum ImageBadgeScrim {
  /// 徽标离图片边缘的距离；卡片圆角 20pt，内容内收后与圆角协调。
  static let inset: CGFloat = 14
  /// 由边缘向内的渐变，`location` 0 在图片边缘。
  static let gradient = Gradient(stops: [
    .init(color: .black.opacity(0.35), location: 0),
    .init(color: .black.opacity(0.15), location: 0.45),
    .init(color: .black.opacity(0), location: 1),
  ])

  /// 渐变的高度：80pt，最多占图片高度的三成。
  static func height(forImageHeight imageHeight: CGFloat) -> CGFloat {
    min(80, imageHeight * 0.3)
  }

  /// 下沿有状态文字（还差几集、已订阅等）时用的深一档渐变：只压文字后面那一窄条。
  /// 文字是要读清楚的整句，在颜色杂的海报上浅渐变压不住；图标类徽标仍用浅的。
  static let textGradient = Gradient(stops: [
    .init(color: .black.opacity(0.65), location: 0),
    .init(color: .black.opacity(0.5), location: 0.55),
    .init(color: .black.opacity(0), location: 1),
  ])

  /// 深一档渐变的高度：70pt，盖住一行状态文字后很快淡完，最多占图片高度的三成。
  static func textHeight(forImageHeight imageHeight: CGFloat) -> CGFloat {
    min(70, imageHeight * 0.3)
  }

  /// 铺在图片下沿的渐变，作为图片上的一层放进 ZStack。
  static func bottomLayer(imageHeight: CGFloat) -> some View {
    LinearGradient(gradient: gradient, startPoint: .bottom, endPoint: .top)
      .frame(height: height(forImageHeight: imageHeight))
      .frame(maxHeight: .infinity, alignment: .bottom)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// 海报四角的徽标：图标和文字直接压在图上，有徽标的那一边铺 `ImageBadgeScrim` 托底。
/// 全部画在一个 Canvas 里，不依赖聚焦状态，滚动和聚焦时不重画，也不用模糊、材质或阴影。
private struct BadgeOverlay: View, Equatable {
  let typeText: String?
  let ratingText: String?
  let bottomLeftText: String?
  let bottomLeftSecondaryText: String?
  let source: MediaSource?

  private var hasRating: Bool {
    guard let ratingText, !ratingText.isEmpty, let score = Double(ratingText) else { return false }
    return score > 0
  }

  var body: some View {
    Canvas { context, size in
      let inset = ImageBadgeScrim.inset
      let scrimHeight = ImageBadgeScrim.height(forImageHeight: size.height)

      let typeSymbol = context.resolveSymbol(id: "typeIcon")
      let starSymbol = context.resolveSymbol(id: "ratingStar")
      let ratingLabel = context.resolveSymbol(id: "ratingText")
      let statusLabel = context.resolveSymbol(id: "statusText")
      let secondaryLabel = context.resolveSymbol(id: "secondaryText")
      let sourceIcon = context.resolveSymbol(id: "sourceIcon")

      let hasTop = typeSymbol != nil || (starSymbol != nil && ratingLabel != nil)
      let hasBottom = statusLabel != nil || secondaryLabel != nil || sourceIcon != nil

      // 渐变托底：只画有徽标的那一边。
      if hasTop {
        context.fill(
          Path(CGRect(x: 0, y: 0, width: size.width, height: scrimHeight)),
          with: .linearGradient(
            ImageBadgeScrim.gradient,
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: scrimHeight)
          )
        )
      }
      if hasBottom {
        // 有状态文字时压深一档，只有来源图标时用浅的。
        let hasBottomText = statusLabel != nil || secondaryLabel != nil
        let bottomHeight = hasBottomText ? ImageBadgeScrim.textHeight(forImageHeight: size.height) : scrimHeight
        context.fill(
          Path(CGRect(x: 0, y: size.height - bottomHeight, width: size.width, height: bottomHeight)),
          with: .linearGradient(
            hasBottomText ? ImageBadgeScrim.textGradient : ImageBadgeScrim.gradient,
            startPoint: CGPoint(x: 0, y: size.height),
            endPoint: CGPoint(x: 0, y: size.height - bottomHeight)
          )
        )
      }

      // 左上：媒体类型（图标或文字）。
      if let typeSymbol {
        context.draw(typeSymbol, at: CGPoint(x: inset, y: inset), anchor: .topLeading)
      }

      // 右上：评分，星星在左、分数在右。
      if let starSymbol, let ratingLabel {
        let spacing: CGFloat = 6
        let rowHeight = max(starSymbol.size.height, ratingLabel.size.height)
        let midY = inset + rowHeight / 2
        let labelMaxX = size.width - inset
        context.draw(ratingLabel, at: CGPoint(x: labelMaxX, y: midY), anchor: .trailing)
        context.draw(
          starSymbol,
          at: CGPoint(x: labelMaxX - ratingLabel.size.width - spacing, y: midY),
          anchor: .trailing
        )
      }

      // 底部一行：左边主要、次要状态，右边来源图标，按同一条中线对齐。
      if hasBottom {
        let rowHeight = max(
          statusLabel?.size.height ?? 0,
          secondaryLabel?.size.height ?? 0,
          sourceIcon?.size.height ?? 0
        )
        let midY = size.height - inset - rowHeight / 2
        var x = inset

        if let statusLabel {
          context.draw(statusLabel, at: CGPoint(x: x, y: midY), anchor: .leading)
          x += statusLabel.size.width + 12
        }
        if let secondaryLabel {
          context.draw(secondaryLabel, at: CGPoint(x: x, y: midY), anchor: .leading)
        }
        if let sourceIcon {
          context.draw(sourceIcon, at: CGPoint(x: size.width - inset, y: midY), anchor: .trailing)
        }
      }
    } symbols: {
      // 徽标内容直接压在渐变上，统一用粗体提高可读性。
      if let type = typeText, !type.isEmpty {
        Group {
          if let typeIcon = MediaTypePresentation.badgeIconName(for: type) {
            Image(systemName: typeIcon)
          } else {
            Text(type)
          }
        }
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .tag("typeIcon")
      }

      if hasRating, let rating = ratingText {
        Image(systemName: AppSymbol.rating)
          .font(.caption2.bold())
          .foregroundStyle(.yellow)
          .tag("ratingStar")

        Text(rating)
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .tag("ratingText")
      }

      if let status = bottomLeftText, !status.isEmpty {
        Text(status)
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .lineLimit(1)
          .tag("statusText")
      }

      if let secondary = bottomLeftSecondaryText, !secondary.isEmpty {
        Text(secondary)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white.opacity(0.8))
          .lineLimit(1)
          .tag("secondaryText")
      }

      if let source {
        Image(source.assetName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 36, height: 36)
          .tag("sourceIcon")
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  static func == (lhs: BadgeOverlay, rhs: BadgeOverlay) -> Bool {
    lhs.typeText == rhs.typeText && lhs.ratingText == rhs.ratingText
      && lhs.bottomLeftText == rhs.bottomLeftText
      && lhs.bottomLeftSecondaryText == rhs.bottomLeftSecondaryText
      && lhs.source == rhs.source
  }
}

struct MediaCard: View {
  static let defaultPosterSize = CGSize(width: 256, height: 384)

  static func posterProcessor(for downsamplingSize: CGSize) -> any ImageProcessor {
    DownsamplingImageProcessor(size: downsamplingSize)
      |> ResizingImageProcessor(referenceSize: defaultPosterSize, mode: .aspectFill)
  }

  static let defaultGridColumns = DetailExpansionGridLayout.columns(width: defaultPosterSize.width, count: 6)

  let title: String
  let posterUrl: URL?
  /// 降尺寸海报加载失败时回退的原始海报 URL。
  let posterFallbackUrl: URL?

  // 角落文本
  let typeText: String?  // 左上角 (例如 "电影", "电视剧")
  let ratingText: String?  // 右上角 (例如 "8.5")
  let bottomLeftText: String?  // 左下角：主要状态 (例如 "已订阅")
  let bottomLeftSecondaryText: String?  // 左下角：次要状态 (例如 "更新至 10 集")
  let source: MediaSource?  // 右下角：数据源图标

  var showBadges: Bool = true
  var loadsImage: Bool = true

  @FocusState private var isFocused: Bool
  /// 降尺寸海报加载失败后切换到原始 URL 重试。
  @State private var posterLoadFailed = false

  var width: CGFloat = defaultPosterSize.width
  var height: CGFloat = defaultPosterSize.height

  /// 在主标题下方显示的可选副标题。
  var subTitleBelow: String? = nil

  /// 是否对背景图片应用模糊效果。主要用于类似“查看全部”等特殊展示。
  var isBackgroundBlurred: Bool = false

  /// 聚焦时显示的标签，通常用于“点击订阅”等操作。
  /// 如果提供，则始终保留空间以防止布局抖动。
  var footerLabel: (icon: String, text: String)? = nil

  // 卡片被点击时的操作
  var action: (() -> Void)? = nil
  var onFocus: ((Bool) -> Void)? = nil

  init(
    title: String = "",
    posterUrl: URL? = nil,
    posterFallbackUrl: URL? = nil,
    typeText: String? = nil,
    ratingText: String? = nil,
    bottomLeftText: String? = nil,
    bottomLeftSecondaryText: String? = nil,
    source: MediaSource? = nil,
    showBadges: Bool = true,
    loadsImage: Bool = true,
    width: CGFloat = defaultPosterSize.width,
    height: CGFloat = defaultPosterSize.height,
    subTitleBelow: String? = nil,
    isBackgroundBlurred: Bool = false,
    footerLabel: (icon: String, text: String)? = nil,
    action: (() -> Void)? = nil,
    onFocus: ((Bool) -> Void)? = nil
  ) {
    self.title = title
    self.posterUrl = posterUrl
    self.posterFallbackUrl = posterFallbackUrl
    self.typeText = typeText
    self.ratingText = ratingText
    self.bottomLeftText = bottomLeftText
    self.bottomLeftSecondaryText = bottomLeftSecondaryText
    self.source = source
    self.showBadges = showBadges
    self.loadsImage = loadsImage
    self.width = width
    self.height = height
    self.subTitleBelow = subTitleBelow
    self.isBackgroundBlurred = isBackgroundBlurred
    self.footerLabel = footerLabel
    self.action = action
    self.onFocus = onFocus
  }

  var body: some View {
    VStack(spacing: 10) {
      Button {
        action?()
      } label: {
        posterContent
          .frame(width: width, height: height)
          .posterCardFocusLift(isFocused: isFocused, width: width)
      }
      .buttonStyle(PosterCardButtonStyle())
      .focusEffectDisabled()
      .focused($isFocused)
      .accessibilityLabel(title)

      // 标题和副标题 - 在按钮外部，清晰分离
      textInfoView
    }
    .posterCardFocusAnimation(isFocused: isFocused)
    // 放进页头上移的横排时自动参与，见 `FocusLiftRowHeader`。
    .focusLiftCard(isFocused: isFocused)
    .onChange(of: isFocused) { _, newValue in
      onFocus?(newValue)
    }
  }

  // 提取文本内容以实现统一动画
  private var textInfoView: some View {
    VStack(spacing: 4) {
      VStack {
        Text(title)
          .font(.caption)
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
          .foregroundStyle(.primary)
          .opacity(isFocused ? 1 : 0)
        }
      }
      .lineLimit(1)
      .compositingGroup()
      .frame(maxWidth: isFocused ? width + PosterCardFocus.focusedTextExtraWidth : width, alignment: .center)
    }
    .frame(width: width + PosterCardFocus.focusedTextExtraWidth)
    .padding(.horizontal, -PosterCardFocus.focusedTextExtraWidth / 2)
    .offset(y: isFocused ? PosterCardFocus.focusedTextOffset(forImageSize: CGSize(width: width, height: height)) : 0)
    .posterCardTitleAnimation(isFocused: isFocused)
  }

  // 提取的海报内容 - Apple TV 风格设计
  @ViewBuilder
  private var posterContent: some View {
    let resolvedTypeIcon = MediaTypePresentation.placeholderIconName(for: typeText)
    ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
        .overlay(
          Image(systemName: resolvedTypeIcon)
            .font(.title2)
            .foregroundStyle(.gray)
        )

      PageManagedImage(
        url: posterLoadFailed ? posterFallbackUrl : posterUrl,
        processor: Self.posterProcessor(for: CGSize(width: width, height: height)),
        isEnabled: loadsImage,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true,
        onFailure: {
          // 降尺寸海报加载失败（如第三方 URL 被改写）时，回退到原始 URL 重试一次。
          posterLoadFailed = true
        }
      )
    }
    .frame(width: width, height: height)
    .onChange(of: posterUrl) { _, _ in
      posterLoadFailed = false
    }
    .overlay {
      if showBadges {
        // 四角徽标：渐变托底，不垫底座
        BadgeOverlay(
          typeText: typeText,
          ratingText: ratingText,
          bottomLeftText: bottomLeftText,
          bottomLeftSecondaryText: bottomLeftSecondaryText,
          source: source
        )
        .equatable()
      }
    }
  }

}

// MARK: - EquatableView 包装器（用于详情页推荐/类似横向列表）

/// 将 MediaCard 包装在 Equatable 视图中，用于详情页的推荐/类似区域。
/// 配合 `.equatable()` 修饰符，仅当 item.id、showBadges、图片窗口或图片配置变化时才重新求值 body。
struct DetailCardView: View, Equatable {
  let item: MediaInfo
  let showBadges: Bool
  let loadsImage: Bool
  let imageConfigurationIdentity: String
  let onTap: () -> Void

  static func == (lhs: DetailCardView, rhs: DetailCardView) -> Bool {
    lhs.item.id == rhs.item.id && lhs.showBadges == rhs.showBadges
      && lhs.loadsImage == rhs.loadsImage
      && lhs.imageConfigurationIdentity == rhs.imageConfigurationIdentity
  }

  var body: some View {
    MediaCard(
      title: item.cleanedTitle ?? "",
      posterUrl: item.imageURLs.poster,
      posterFallbackUrl: item.imageURLs.posterFallback,
      typeText: item.displayTypeText,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      showBadges: showBadges,
      loadsImage: loadsImage,
      action: onTap
    )
  }
}
