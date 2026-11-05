import SwiftUI

/// 复用订阅：只看的快速面板，版式与新增订阅的快速面板一致（宽 860，单列）。
///
/// 不放海报：只会从订阅分享卡片或它的长按菜单进来，进来前已经看过海报。
/// 内容与 Web 复用订阅对话框对齐：分享标题、分享说明，下面一排是分享人、时间、复用次数，
/// 以及这份订阅自带的关键词、识别词（与 Web 一样写明标签、列出原文）。按「复用订阅」直接提交，打开时焦点默认在这个按钮上。
/// 后端不支持复用、或复用失败时，原因统一显示在按钮上方。
struct ForkSubscribeSheet: View {
  let share: SubscribeShare
  var onFork: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @State private var isForking = false
  @FocusState private var isConfirmFocused: Bool

  var body: some View {
    SheetCompactPanel {
      header

      SheetRetryingMessage(
        message: subscriptionHandler.forkErrorMessage
          ?? subscriptionHandler.forkCapability.unavailableReason,
        isBusy: isForking,
        retry: nil,
        spacingEdges: .top, spacing: 24
      )

      // 后端不支持复用时也不禁用：禁用后面板里没有能聚焦的东西。按下时会被拦下，原因已显示在上方。
      SheetActionButton(
        title: "复用订阅",
        systemImage: "heart.fill",
        loadingTitle: "复用中",
        isLoading: isForking,
        focus: $isConfirmFocused
      ) {
        Task {
          guard !isForking else { return }
          isForking = true
          defer { isForking = false }
          if let newSubId = await subscriptionHandler.fork(share: share) {
            onFork(newSubId)
            dismiss()
          }
        }
      }
      .padding(.top, 32)
    }
    .defaultFocus($isConfirmFocused, true)
    .cancelOnExternalNavigation()
  }

  // MARK: - 分享信息

  private var header: some View {
    // 分享说明里连续的空行压成一个换行，避免说明被撑得很高。
    let comment = MediaIdentifier.normalizedString(share.share_comment)?
      .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
    let keyword = MediaIdentifier.normalizedString(share.keyword)
    let customWords = share.displayCustomWords

    return VStack(alignment: .leading, spacing: 0) {
      SheetMediaTitle(
        title: share.displayTitle ?? "复用订阅", type: share.type, year: share.year, lineLimit: 6)

      if let comment {
        Text(comment)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(4)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 16)
      }

      SheetInfoTags {
        SheetInfoTag(
          systemImage: "person",
          text: MediaIdentifier.normalizedString(share.share_user) ?? "未知分享人")
        if let date = MediaIdentifier.normalizedString(share.date) {
          SheetInfoTag(systemImage: "clock", text: date.toRelativeDateString())
        }
        if let count = share.count, count > 0 {
          SheetInfoTag(systemImage: "flame", text: "\(count.formatted()) 次复用")
        }
        if share.type == "电视剧", let season = share.season {
          SheetInfoTag(systemImage: "tv", text: "第 \(season) 季")
        }
      }
      .padding(.top, 16)

      // 关键词、识别词与 Web 一样写明标签：关键词常是较长的正则，放不下时省略中间；
      // 识别词按行列出原文，最多 4 行。
      VStack(alignment: .leading, spacing: 8) {
        if let keyword {
          Text("关键词：\(keyword)")
            .lineLimit(2)
            .truncationMode(.middle)
        }
        if let customWords {
          Text("识别词：\n\(customWords)")
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .padding(.top, keyword == nil && customWords == nil ? 0 : 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
