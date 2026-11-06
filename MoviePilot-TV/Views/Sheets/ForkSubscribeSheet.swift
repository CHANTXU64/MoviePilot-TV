import SwiftUI

/// 复用订阅：只看的快速面板，版式与新增订阅的快速面板一致（宽 860，单列）。
///
/// 不放海报：只会从订阅分享卡片或它的长按菜单进来，进来前已经看过海报。
/// 内容与 Web 复用订阅对话框对齐：分享标题、分享说明，下面一排是分享人、时间、复用次数，
/// 以及这份订阅自带的关键词、识别词（与 Web 一样写明标签、列出原文）。按「复用订阅」直接提交，打开时焦点默认在这个按钮上。
/// 后端不支持复用、或复用失败时，原因统一显示在按钮上方。
/// 分享说明、关键词、识别词在面板里限定行数；有放不下的内容时下面多一个「查看完整说明」，用阅读 Sheet 看全文。
struct ForkSubscribeSheet: View {
  let share: SubscribeShare
  var onFork: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @State private var isForking = false
  @State private var hasTruncatedText = false
  @State private var showsFullText = false
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
        systemImage: AppSymbol.forkSubscription,
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

      if hasTruncatedText {
        Button {
          showsFullText = true
        } label: {
          Text("查看完整说明")
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 18)
      }
    }
    .defaultFocus($isConfirmFocused, true)
    .sheet(isPresented: $showsFullText) {
      ReadingSheet(title: share.displayTitle ?? "复用订阅", blocks: Self.fullTextBlocks(for: share))
    }
    .cancelOnExternalNavigation()
  }

  /// 「查看完整说明」的正文：分享说明全文，下面是关键词、识别词原文。
  static func fullTextBlocks(for share: SubscribeShare) -> [ReadingBlock] {
    var blocks: [ReadingBlock] = []
    if let comment = share.displayComment {
      blocks += ReadingSheetLayout.paragraphs(comment).map { ReadingBlock($0) }
    }
    let keyword = share.displayKeyword
    let customWords = share.displayCustomWords
    if !blocks.isEmpty, keyword != nil || customWords != nil {
      blocks.append(.divider)
    }
    if let keyword {
      blocks.append(.field("关键词", keyword))
    }
    if let customWords {
      blocks.append(.field("识别词", customWords))
    }
    return blocks
  }

  // MARK: - 分享信息

  private var header: some View {
    // 分享说明里连续的空行压成一个换行，避免说明被撑得很高。
    let comment = share.displayComment?
      .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
    let keyword = share.displayKeyword
    let customWords = share.displayCustomWords

    return VStack(alignment: .leading, spacing: 0) {
      SheetMediaTitle(
        title: share.displayTitle ?? "复用订阅", type: share.type, year: share.year, lineLimit: 6)

      if let comment {
        ClampedText(text: comment, lineLimit: 4)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 16)
      }

      SheetInfoTags {
        SheetInfoTag(
          systemImage: AppSymbol.person,
          text: MediaIdentifier.normalizedString(share.share_user) ?? "未知分享人")
        if let date = MediaIdentifier.normalizedString(share.date) {
          SheetInfoTag(systemImage: AppSymbol.time, text: date.toRelativeDateString())
        }
        if let count = share.count, count > 0 {
          SheetInfoTag(systemImage: AppSymbol.popularity, text: "\(count.formatted()) 次复用")
        }
        if share.type == "电视剧", let season = share.season {
          SheetInfoTag(systemImage: AppSymbol.season, text: "第 \(season) 季")
        }
      }
      .padding(.top, 16)

      // 关键词、识别词与 Web 一样写明标签：关键词常是较长的正则，放不下时省略中间；
      // 识别词按行列出原文，最多 4 行。放不下的部分在「查看完整说明」里看。
      VStack(alignment: .leading, spacing: 8) {
        if let keyword {
          ClampedText(text: "关键词：\(keyword)", lineLimit: 2, truncationMode: .middle)
        }
        if let customWords {
          ClampedText(text: "识别词：\n\(customWords)", lineLimit: 5)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .padding(.top, keyword == nil && customWords == nil ? 0 : 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onPreferenceChange(TextTruncatedKey.self) { hasTruncatedText = $0 }
  }
}

/// 面板里有没有文字被截断：任一段被截断即为 true。
private struct TextTruncatedKey: PreferenceKey {
  static let defaultValue = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

/// 限定行数显示的文字，并通过 `TextTruncatedKey` 报告有没有被截断：背后放一份不限行数、
/// 看不见的同样文字，两者高度不同就是放不下。字体、颜色跟随外层。
private struct ClampedText: View {
  let text: String
  let lineLimit: Int
  var truncationMode: Text.TruncationMode = .tail

  @State private var shownHeight: CGFloat = 0
  @State private var fullHeight: CGFloat = 0

  var body: some View {
    Text(text)
      .lineLimit(lineLimit)
      .truncationMode(truncationMode)
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
      .background(alignment: .topLeading) {
        Text(text)
          .fixedSize(horizontal: false, vertical: true)
          .hidden()
          .accessibilityHidden(true)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
      }
      // 两份都量出来以后才比较，免得只量到一份时误报。
      .preference(key: TextTruncatedKey.self, value: shownHeight > 0 && fullHeight > shownHeight + 1)
  }
}
