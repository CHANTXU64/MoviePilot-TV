import SwiftUI

/// 单集面板：统一阅读 Sheet 的两栏形式。左栏是剧名、时长和播出日期，下面先用一句醒目的结论说这一集能不能播、
/// 试看到了哪一步，再用一两行小字说原因或下一步，最下面是能做的操作；右栏是简介。
/// 没有应用内播放时左栏只有信息，和原来的单集详情一样。
///
/// 内容随集列表的状态实时变化（打开期间刷新试看进度），操作交给集列表执行：播放要先关掉面板再起播，
/// 按「试看」后面板也关掉，进度看卡片正中。
struct EpisodeActionSheet: View {
  let episode: MoviePilotEpisode
  let seriesTitle: String?
  let entry: EpisodeEntry
  /// 按下「取消试看」到服务给出结果之间。
  let isCancellingTrial: Bool
  /// 正在重新检查能不能播。
  let isRechecking: Bool
  let onAction: (EpisodeEntry.PanelButton) -> Void

  @FocusState private var focusedButton: Int?

  var body: some View {
    let panel = entry.panel
    ReadingSheet(
      title: episode.cardTitle, blocks: Self.blocks(for: episode), focusesBodyByDefault: panel.buttons.isEmpty,
      size: .compact
    ) {
      sidebar(panel)
    }
    // 挂在整个面板上：只挂在左栏时，打开面板的默认焦点仍会落到右上的正文。
    .defaultFocus($focusedButton, panel.buttons.isEmpty ? nil : 0)
  }

  static func blocks(for episode: MoviePilotEpisode) -> [ReadingBlock] {
    let overview = episode.displayOverview.map(ReadingSheetLayout.paragraphs) ?? []
    return overview.isEmpty ? [ReadingBlock("暂无简介", style: .secondary)] : overview.map { ReadingBlock($0) }
  }

  private func sidebar(_ panel: EpisodeEntry.Panel) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        if let seriesTitle = trimmedNonEmpty([seriesTitle]) {
          Text(seriesTitle)
            .font(.headline)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 24)
        }
        info
        if let headline = panel.headline {
          status(panel, headline: headline)
            .padding(.top, 32)
        }
      }
      .accessibilityElement(children: .combine)

      Spacer(minLength: 24)

      VStack(spacing: 20) {
        // 按位置标识按钮：状态变化时（试看 → 取消试看）第一个按钮还是同一个位置，焦点不跳走。
        ForEach(Array(panel.buttons.enumerated()), id: \.offset) { index, button in
          actionButton(button, index: index)
        }
      }
    }
  }

  /// 结论（图标加粗体）和下面的原因（次要颜色的小字）。
  private func status(_ panel: EpisodeEntry.Panel, headline: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text(headline)
      } icon: {
        Self.icon(for: panel.tone)
      }
      .font(.body.bold())
      .fixedSize(horizontal: false, vertical: true)
      if let detail = panel.detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private static func icon(for tone: EpisodeEntry.Panel.Tone) -> some View {
    switch tone {
    case .ready: Image(systemName: AppSymbol.success).foregroundStyle(.green)
    case .caution: Image(systemName: AppSymbol.warning).foregroundStyle(.yellow)
    case .working: Image(systemName: AppSymbol.checking).foregroundStyle(.secondary)
    case .info: Image(systemName: AppSymbol.info).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var info: some View {
    let runtime = episode.runtimeText
    let airDate = trimmedNonEmpty([episode.airDate])
    if runtime != nil || airDate != nil {
      VStack(alignment: .leading, spacing: 14) {
        if let airDate { SheetInfoTag(systemImage: AppSymbol.time, text: airDate) }
        if let runtime { SheetInfoTag(systemImage: AppSymbol.duration, text: runtime) }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
  }

  private func actionButton(_ button: EpisodeEntry.PanelButton, index: Int) -> some View {
    let title: String
    let systemImage: String
    var loadingTitle = ""
    var isLoading = false
    let cautious = entry.panel.proceedsDespiteWarning
    switch button {
    case .play:
      title = cautious ? "仍要播放" : "播放"
      systemImage = AppSymbol.play
    case .startTrial(let isRetry):
      title = cautious ? "仍要试看" : isRetry ? "重新试看" : "试看"
      systemImage = AppSymbol.subscriptionTrial
      loadingTitle = "正在发起试看"
      isLoading = entry.trial.isStarting
    case .cancelTrial:
      title = EpisodeTrialHoldNotice.cancelTitle
      systemImage = AppSymbol.unsubscribe
      loadingTitle = "正在取消试看"
      isLoading = isCancellingTrial
    case .recheck:
      title = "重新检查"
      systemImage = AppSymbol.retry
      loadingTitle = "正在检查"
      isLoading = isRechecking
    }
    return SheetActionButton(
      title: title, systemImage: systemImage, loadingTitle: loadingTitle, isLoading: isLoading
    ) {
      onAction(button)
    }
    .focused($focusedButton, equals: index)
  }
}
