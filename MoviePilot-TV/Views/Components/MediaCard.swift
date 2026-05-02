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

private struct BadgeOverlay: View, Equatable {
  let typeText: String?
  let ratingText: String?
  let bottomLeftText: String?
  let bottomLeftSecondaryText: String?
  let source: MediaSource?

  static let typeIconMap: [String: String] = [
    "电影": "film",
    "电视剧": "tv",
    "合集": "rectangle.stack",
  ]

  var body: some View {
    Canvas { context, size in
      let badgeBg = Color.black.opacity(0.4)
      let cornerRadius: CGFloat = 8
      let padding: CGFloat = 10
      // 注意：UIFont 属于 UIKit，不直接用于 SwiftUI Canvas 的文本绘制。
      // Canvas 中的文本绘制使用 SwiftUI 的 Text 或 context.draw(Text(...))。
      // 这里的字体变量仅用于说明，并未直接应用在下方的 Canvas 绘制逻辑中。
      // 对于实际的文本样式，由 symbols 块中的 Text 视图处理。
      // let font = UIFont.systemFont(ofSize: 14, weight: .bold)
      // let smallFont = UIFont.systemFont(ofSize: 14, weight: .medium)

      // 左上：媒体类型徽章
      // 媒体类型图标从 symbols 中解析，symbols 已经配置了正确的字体和前景色。
      if let symbol = context.resolveSymbol(id: "typeIcon") {
        // 根据 symbol 大小和所需边距计算徽章大小
        let badgeContentWidth = symbol.size.width
        let badgeContentHeight = symbol.size.height
        let horizontalPadding: CGFloat = 16  // 每侧 8px
        let verticalPadding: CGFloat = 16  // 每侧 8px
        let badgeSize = CGSize(
          width: badgeContentWidth + horizontalPadding,
          height: badgeContentHeight + verticalPadding
        )
        let badgeRect = CGRect(
          origin: CGPoint(x: padding, y: padding), size: badgeSize)
        context.fill(
          Path(roundedRect: badgeRect, cornerRadius: cornerRadius),
          with: .color(badgeBg))
        context.draw(
          symbol,
          at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
      }

      // 右上：评分徽章
      if let rating = ratingText, !rating.isEmpty, let score = Double(rating), score > 0,
        let starSymbol = context.resolveSymbol(id: "ratingStar"),
        let ratingLabel = context.resolveSymbol(id: "ratingText")
      {
        let starWidth = starSymbol.size.width
        let ratingTextWidth = ratingLabel.size.width
        let contentSpacing: CGFloat = 4
        let horizontalPadding: CGFloat = 20  // 每侧 10px
        let verticalPadding: CGFloat = 12  // 每侧 6px

        let contentWidth = starWidth + contentSpacing + ratingTextWidth
        let contentHeight = max(starSymbol.size.height, ratingLabel.size.height)

        let badgeSize = CGSize(
          width: contentWidth + horizontalPadding, height: contentHeight + verticalPadding)
        let badgeRect = CGRect(
          origin: CGPoint(x: size.width - padding - badgeSize.width, y: padding),
          size: badgeSize)
        context.fill(
          Path(roundedRect: badgeRect, cornerRadius: cornerRadius),
          with: .color(badgeBg))

        // 在徽章内居中绘制星星和文本
        let startX = badgeRect.minX + horizontalPadding / 2
        context.draw(
          starSymbol,
          at: CGPoint(
            x: startX + starWidth / 2,
            y: badgeRect.midY))
        context.draw(
          ratingLabel,
          at: CGPoint(
            x: startX + starWidth + contentSpacing + ratingTextWidth / 2,
            y: badgeRect.midY))
      }

      // 底部区域
      if bottomLeftText != nil || bottomLeftSecondaryText != nil || source != nil {
        var xOffset: CGFloat = padding

        // 左下：状态徽章
        if let statusLabel = context.resolveSymbol(id: "statusText") {
          let horizontalPadding: CGFloat = 20  // 每侧 10px
          let verticalPadding: CGFloat = 12  // 每侧 6px
          let badgeSize = CGSize(
            width: statusLabel.size.width + horizontalPadding,
            height: statusLabel.size.height + verticalPadding
          )
          let badgeRect = CGRect(
            origin: CGPoint(x: xOffset, y: size.height - padding - badgeSize.height),
            size: badgeSize)
          context.fill(
            Path(roundedRect: badgeRect, cornerRadius: cornerRadius),
            with: .color(badgeBg))
          context.draw(statusLabel, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
          xOffset = badgeRect.maxX + 6
        }

        // 左下次要状态
        if let secondaryLabel = context.resolveSymbol(id: "secondaryText") {
          let horizontalPadding: CGFloat = 20  // 每侧 10px
          let verticalPadding: CGFloat = 12  // 每侧 6px
          let badgeSize = CGSize(
            width: secondaryLabel.size.width + horizontalPadding,
            height: secondaryLabel.size.height + verticalPadding
          )
          let badgeRect = CGRect(
            origin: CGPoint(x: xOffset, y: size.height - padding - badgeSize.height),
            size: badgeSize)
          context.fill(
            Path(roundedRect: badgeRect, cornerRadius: cornerRadius),
            with: .color(badgeBg))
          context.draw(secondaryLabel, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
        }

        // 右下：来源图标
        if let sourceIcon = context.resolveSymbol(id: "sourceIcon") {
          // 绘制图标前应用阴影
          context.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1))
          context.draw(
            sourceIcon,
            at: CGPoint(
              x: size.width - padding - sourceIcon.size.width / 2 - 6,  // 考虑了边距和图标自身的内部间距
              y: size.height - padding - sourceIcon.size.height / 2 - 2))  // 考虑了边距和图标自身的内部间距
        }
      }
    } symbols: {
      // 通过 symbols 提供需要的 SwiftUI 内容（仅创建一次，不参与 view tree diffing）
      let typeIcon = Self.typeIconMap[typeText ?? ""] ?? "film"
      Group {
        if let type = typeText, !type.isEmpty {
          if Self.typeIconMap[type] != nil {  // 检查是否为图标类型
            Image(systemName: typeIcon)
          } else {
            Text(type)
          }
        }
      }
      .font(.caption2.bold())
      .foregroundStyle(.white)
      .tag("typeIcon")

      if let rating = ratingText, !rating.isEmpty, let score = Double(rating), score > 0 {
        Image(systemName: "star.fill")
          .font(.caption2)
          .foregroundStyle(.yellow)
          .tag("ratingStar")

        Text(rating)
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .tag("ratingText")
      }

      if let status = bottomLeftText, !status.isEmpty {
        Text(status)
          .font(.caption2)
          .foregroundStyle(.white)
          .tag("statusText")
      }

      if let secondary = bottomLeftSecondaryText, !secondary.isEmpty {
        Text(secondary)
          .font(.caption2)
          .foregroundStyle(.white)
          .tag("secondaryText")
      }

      if let source = source {
        Image(source.iconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 36, height: 36)
          .padding(.horizontal, 6)  // 重新应用原始 SwiftUI 视图中的内边距
          .padding(.vertical, 2)
          .tag("sourceIcon")
      }
    }
  }

  static func == (lhs: BadgeOverlay, rhs: BadgeOverlay) -> Bool {
    lhs.typeText == rhs.typeText && lhs.ratingText == rhs.ratingText
      && lhs.bottomLeftText == rhs.bottomLeftText
      && lhs.bottomLeftSecondaryText == rhs.bottomLeftSecondaryText
      && lhs.source == rhs.source
  }
}

struct MediaCard: View {
  static let defaultGridColumns = Array(
    repeating: GridItem(.fixed(256), spacing: 44, alignment: .top),
    count: 6
  )

  let title: String
  let posterUrl: URL?

  // 角落文本
  let typeText: String?  // 左上角 (例如 "电影", "电视剧")
  let ratingText: String?  // 右上角 (例如 "8.5")
  let bottomLeftText: String?  // 左下角：主要状态 (例如 "已订阅")
  let bottomLeftSecondaryText: String?  // 左下角：次要状态 (例如 "更新至 10 集")
  let source: MediaSource?  // 右下角：数据源图标

  var showBadges: Bool = true

  @FocusState private var isFocused: Bool

  var width: CGFloat = 256
  var height: CGFloat = 384

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

  private static let typeIconMap: [String: String] = [
    "电影": "film",
    "电视剧": "tv",
    "合集": "rectangle.stack",
  ]

  init(
    title: String = "",
    posterUrl: URL? = nil,
    typeText: String? = nil,
    ratingText: String? = nil,
    bottomLeftText: String? = nil,
    bottomLeftSecondaryText: String? = nil,
    source: MediaSource? = nil,
    showBadges: Bool = true,
    width: CGFloat = 256,
    height: CGFloat = 384,
    subTitleBelow: String? = nil,
    isBackgroundBlurred: Bool = false,
    footerLabel: (icon: String, text: String)? = nil,
    action: (() -> Void)? = nil,
    onFocus: ((Bool) -> Void)? = nil
  ) {
    self.title = title
    self.posterUrl = posterUrl
    self.typeText = typeText
    self.ratingText = ratingText
    self.bottomLeftText = bottomLeftText
    self.bottomLeftSecondaryText = bottomLeftSecondaryText
    self.source = source
    self.showBadges = showBadges
    self.width = width
    self.height = height
    self.subTitleBelow = subTitleBelow
    self.isBackgroundBlurred = isBackgroundBlurred
    self.footerLabel = footerLabel
    self.action = action
    self.onFocus = onFocus
  }

  /// 海报在屏幕上的布局 frame（用于过渡动画）。
  /// 通过 UIViewRepresentable 持有底层 UIView 弱引用，tap 时才读取实时 frame，
  /// 避免滚动期间 GeometryReader + onChange 的高频 CGRect diff 导致 CPU 飙升。
  @State private var posterFrameBox = PosterFrameBox()

  var body: some View {
    VStack(spacing: 10) {
      // 海报图片
      posterContent
        .frame(width: width, height: height)
        .background(FrameAnchorView(box: posterFrameBox))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
          color: .black.opacity(isFocused ? 0.5 : 0),
          radius: 20,
          y: 10
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .focusable(true)
        .focused($isFocused)
        .onTapGesture {
          // 记录点击时卡片的视觉 frame（含焦点缩放），供详情页加载动画使用
          let posterFrame = posterFrameBox.frame
          let scale: CGFloat = isFocused ? 1.1 : 1.0
          let scaledW = posterFrame.width * scale
          let scaledH = posterFrame.height * scale
          MediaCardTransition.sourceFrame = CGRect(
            x: posterFrame.midX - scaledW / 2,
            y: posterFrame.midY - scaledH / 2,
            width: scaledW,
            height: scaledH
          )
          action?()
        }

      // 标题和副标题 - 在按钮外部，清晰分离
      textInfoView
    }
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
      .frame(maxWidth: width, alignment: .center)
      // .frame(maxWidth: isFocused ? width + 30 : width, alignment: .center)
    }
    .frame(width: width + 30)
    .padding(.horizontal, -15)
    .offset(y: isFocused ? 18 : 0)
    .animation(.easeInOut(duration: 0.2), value: isFocused)
  }

  // 提取的海报内容 - Apple TV 风格设计
  private var posterContent: some View {
    let resolvedTypeIcon = Self.typeIconMap[typeText ?? ""] ?? "film"
    return KFImage(posterUrl)
      .requestModifier(AnyModifier.cookieModifier)
      .placeholder {
        Rectangle()
          .fill(Color(white: 0.12))
          .overlay(
            Image(systemName: resolvedTypeIcon)
              .font(.title2)
              .foregroundStyle(.gray)
          )
      }
      .downsampling(size: CGSize(width: width, height: height))
      .resizing(referenceSize: CGSize(width: 256, height: 384), mode: .aspectFill)
      .resizable()
      .fade(duration: 0.25)
      .aspectRatio(contentMode: .fill)
      .frame(width: width, height: height)
      .overlay {
        if showBadges {
          // 覆盖徽章 - 纯色浅黑风格
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

/// 海报 frame 的引用盒子。通过 UIView 弱引用实时读取屏幕坐标，
/// 不产生任何滚动期间的 SwiftUI 值追踪开销。
private final class PosterFrameBox: @unchecked Sendable {
  weak var anchorView: UIView?

  /// 从 UIKit 读取实时屏幕 frame（tap/长按时调用）
  var frame: CGRect {
    guard let view = anchorView else { return .zero }
    return view.convert(view.bounds, to: nil)
  }
}

/// 零开销的 UIView 锚点，用于在需要时读取屏幕坐标。
private struct FrameAnchorView: UIViewRepresentable {
  typealias UIViewType = UIView
  let box: PosterFrameBox

  func makeUIView(context: UIViewRepresentableContext<FrameAnchorView>) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    box.anchorView = view
    return view
  }

  func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<FrameAnchorView>) {
    // anchorView 可能因 LazyVGrid 复用而变化，保持引用最新
    box.anchorView = uiView
  }
}

// MARK: - EquatableView 包装器（用于详情页推荐/类似横向列表）

/// 将 MediaCard 包装在 Equatable 视图中，用于详情页的推荐/类似区域。
/// 配合 `.equatable()` 修饰符，仅当 item.id 或 showBadges 变化时才重新求值 body。
struct DetailCardView: View, Equatable {
  let item: MediaInfo
  let showBadges: Bool
  let onTap: () -> Void

  static func == (lhs: DetailCardView, rhs: DetailCardView) -> Bool {
    lhs.item.id == rhs.item.id && lhs.showBadges == rhs.showBadges
  }

  var body: some View {
    MediaCard(
      title: item.cleanedTitle ?? "",
      posterUrl: item.imageURLs.poster,
      typeText: item.type,
      ratingText: item.vote_average.map { String(format: "%.1f", $0) },
      bottomLeftText: nil,
      bottomLeftSecondaryText: nil,
      source: MediaSource.from(mediaInfo: item),
      showBadges: showBadges,
      action: onTap
    )
  }
}

// MARK: - 卡片过渡动画状态（详情页加载动画的数据源）

/// 存储最后一次点击的 MediaCard 海报在屏幕上的 frame，
/// 供 MediaDetailContainerView 的加载动画作为起始位置使用。
@MainActor
enum MediaCardTransition {
  /// 最后一次点击的卡片海报在屏幕坐标系中的 frame（已包含焦点缩放）
  static var sourceFrame: CGRect = .zero
}
