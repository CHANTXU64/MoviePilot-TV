import Kingfisher
import SwiftUI

/// 豆瓣短评/影评卡片。
///
/// 一种模板覆盖两类内容：影评标题（仅影评）→ 星级与日期 → 正文 → 作者与「有用」数。
/// 用原生 `Button` 承载选择键与无障碍语义，焦点外观由 `DoubanDiscussionCardButtonStyle` 自绘。
struct DoubanDiscussionCard: View {
  let entry: DoubanDiscussionEntry
  /// 已经过图片代理包装的头像地址（豆瓣头像不能直连，会 418）。
  let avatarURL: URL?
  let onTap: () -> Void

  static let cardWidth: CGFloat = 560
  static let cardHeight: CGFloat = 340

  var body: some View {
    Button(action: onTap) {
      DoubanDiscussionCardContent(entry: entry, avatarURL: avatarURL)
    }
    .buttonStyle(DoubanDiscussionCardButtonStyle())
    .accessibilityLabel(entry.accessibilityLabel)
  }
}

/// 卡片内容，单独拆出便于离屏渲染检查排版。
struct DoubanDiscussionCardContent: View {
  let entry: DoubanDiscussionEntry
  let avatarURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title = entry.title {
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          // 标题先拿够自己的行数（一行或两行），正文再分剩下的高度。
          .layoutPriority(1)
          .padding(.bottom, 10)
      }

      if entry.starFills != nil || entry.timeText != nil {
        HStack(spacing: 12) {
          if let fills = entry.starFills {
            DoubanRatingStars(fills: fills, size: 18)
          }
          if let timeText = entry.timeText {
            Text(timeText)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
        .padding(.bottom, 14)
      }

      Text(bodyText)
        .font(.caption)
        .foregroundStyle(.primary.opacity(0.82))
        .lineSpacing(4)
        .multilineTextAlignment(.leading)
        // 不写死行数：正文占满标题、星级与底栏之外的高度，能放几行放几行，放不下的整行截断加省略号。
        // 卡片高度按「一行标题 + 四行正文」定，两行标题时正文三行，没有标题时正文自动多放。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.bottom, 10)

      HStack(spacing: 12) {
        DoubanDiscussionAvatar(url: avatarURL, initial: entry.authorInitial, size: 36)

        Text(entry.displayAuthorName)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 12)

        // 纯文字「N 有用」，不用点赞图标：图标会让人以为能点。
        if let usefulText = entry.usefulText {
          Text(usefulText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
      }
    }
    .padding(28)
    .frame(
      width: DoubanDiscussionCard.cardWidth,
      height: DoubanDiscussionCard.cardHeight,
      alignment: .topLeading
    )
  }

  private var bodyText: String {
    let text = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "（暂无正文）" : text
  }
}

/// 区块里没有可展示条目时的状态卡：加载中、加载失败（可重试）、暂无内容。
///
/// 三种状态是同一个可聚焦按钮，状态切换时视图身份不变，焦点留在原地；
/// 只有失败状态响应选择键。尺寸与普通卡片一致，避免行高跳动。
struct DoubanDiscussionStatusCard: View {
  enum Status: Equatable {
    case loading
    case failed
    case empty
  }

  let kind: DoubanDiscussionEntry.Kind
  let status: Status
  let onRetry: () -> Void

  var body: some View {
    Button {
      guard status == .failed else { return }
      onRetry()
    } label: {
      VStack(spacing: 14) {
        switch status {
        case .loading:
          ProgressView()
          Text("正在加载\(kind.title)")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed:
          Image(systemName: "arrow.clockwise")
            .font(.title3)
            .foregroundStyle(.secondary)
          Text(kind.failureText)
            .font(.caption.weight(.semibold))
          Text("按下重新加载")
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .empty:
          Image(systemName: "text.bubble")
            .font(.title3)
            .foregroundStyle(.secondary)
          Text(kind.emptyText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: DoubanDiscussionCard.cardWidth, height: DoubanDiscussionCard.cardHeight)
    }
    .buttonStyle(DoubanDiscussionCardButtonStyle())
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    switch status {
    case .loading: return "正在加载\(kind.title)"
    case .failed: return "\(kind.failureText)，按下重新加载"
    case .empty: return kind.emptyText
    }
  }
}

/// 卡片的焦点外观：未聚焦是贴近背景的深色面板，聚焦时提亮、放大并投影。
/// 不画描边——描边在虚化剧照上会显得廉价。
struct DoubanDiscussionCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    CardBody(configuration: configuration)
  }

  private struct CardBody: View {
    let configuration: Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .background(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(isFocused ? 0.2 : 0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(isFocused ? (configuration.isPressed ? 1.02 : 1.06) : 1)
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 14)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
  }
}

/// 五星评分。星色用豆瓣评分的橙色，空星用半透明白，不画任何数字。
struct DoubanRatingStars: View {
  let fills: [DoubanDiscussionEntry.StarFill]
  let size: CGFloat

  var body: some View {
    HStack(spacing: size * 0.18) {
      ForEach(Array(fills.enumerated()), id: \.offset) { _, fill in
        Image(systemName: symbol(for: fill))
          .font(.system(size: size, weight: .semibold))
          .foregroundStyle(fill == .empty ? Color.white.opacity(0.25) : Self.starColor)
      }
    }
    .accessibilityHidden(true)
  }

  static let starColor = Color(red: 1.0, green: 0.68, blue: 0.18)

  private func symbol(for fill: DoubanDiscussionEntry.StarFill) -> String {
    switch fill {
    case .full: return "star.fill"
    case .half: return "star.leadinghalf.filled"
    case .empty: return "star.fill"
    }
  }
}

/// 评论作者头像；加载失败或没有头像时回退为作者名首字。
struct DoubanDiscussionAvatar: View {
  /// 已经过图片代理包装的头像地址。
  let url: URL?
  let initial: String
  let size: CGFloat

  @State private var failedURL: URL?

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white.opacity(0.14))

      if let url, failedURL != url {
        KFImage.sessionImage(url)
          .placeholder { initialText }
          .onFailure { _ in failedURL = url }
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        initialText
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }

  private var initialText: some View {
    Text(initial)
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(.secondary)
  }
}
