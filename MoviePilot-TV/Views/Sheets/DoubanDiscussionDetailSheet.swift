import SwiftUI

/// 豆瓣短评/影评详情 Sheet：统一阅读 Sheet 的两栏形式。
///
/// 左栏是作者、分类、星级、发帖日期、发帖时刻与「有用」数；右栏是影评标题（短评没有）和正文。
struct DoubanDiscussionDetailSheet: View {
  let entry: DoubanDiscussionEntry
  /// 已经过图片代理包装的头像地址。
  let avatarURL: URL?

  var body: some View {
    ReadingSheet(
      title: entry.title,
      blocks: entry.paragraphs.map { ReadingBlock($0) }
    ) {
      sidebar
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      DoubanDiscussionAvatar(url: avatarURL, initial: entry.authorInitial, size: 112)
        .padding(.bottom, 24)

      Text(entry.displayAuthorName)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)

      Text("豆瓣\(entry.kind.title)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 28)

      VStack(alignment: .leading, spacing: 14) {
        if let fills = entry.starFills {
          DoubanRatingStars(fills: fills, size: 24)
        }
        if let posted = entry.postedDateAndTime {
          Text(posted.date)
            .monospacedDigit()
          if let time = posted.time {
            Text(time)
              .monospacedDigit()
          }
        }
        if let usefulText = entry.usefulText {
          Text(usefulText)
            .monospacedDigit()
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
