import SwiftUI

/// 下载字幕：快速确认面板，版式与「添加下载」一致。
///
/// 左栏是这条字幕的信息（标题、描述，季集 / 大小 / 发布时间 / 下载次数 / 语言 / 站点），
/// 右栏是保存路径、媒体来源、媒体 ID 和「下载」。字幕必须对应到一部媒体才能下载，
/// 所以来源和 ID 一直显示；从媒体页搜索时已带入，打开时焦点默认在「下载」上。
/// 关闭交给 Menu 键，不放「取消」按钮；关闭时由打开它的页面收尾（见 `SubtitleResultView`）。
struct SubtitleDownloadSheet: View {
  @ObservedObject var viewModel: SubtitleDownloadViewModel
  @StateObject private var sources = MediaSourceOptionsModel()
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isConfirmFocused: Bool

  var body: some View {
    // 左栏是字幕信息（不可聚焦），右栏是设置和「下载」。
    SheetQuickPanel {
      header
    } controls: {
      // 行与行留出间距：聚焦的行会放大，贴在一起会压住相邻行。
      VStack(spacing: 18) {
        SheetPicker(
          title: "保存路径",
          selection: Binding(get: { viewModel.selectedSavePath }, set: viewModel.selectSavePath),
          options: [PickerOption<String?>(title: "自动", value: nil)]
            + viewModel.savePathChoices.map { PickerOption(title: $0, value: Optional($0)) },
          unavailableMessage: viewModel.isLoadingDirectories ? "正在加载…" : nil
        )

        SheetPicker(
          title: "媒体来源",
          selection: Binding(get: { viewModel.mediaSource }, set: viewModel.selectSource),
          options: sources.options(including: viewModel.mediaSource).map {
            PickerOption(title: $0.title, value: $0.source)
          }
        )

        ManualMediaIdField(
          source: viewModel.mediaSource, sourceTitle: sources.title(for: viewModel.mediaSource),
          isInline: true, mediaId: $viewModel.mediaId
        ) { mediaId, _ in
          viewModel.mediaId = mediaId
        }
      }
      .disabled(!viewModel.canEdit)

      // 出错提示和其他面板一样放在主按钮上方。
      SheetRetryingMessage(
        message: viewModel.statusMessage,
        isBusy: viewModel.isLoadingDirectories || viewModel.isSubmitting,
        retry: viewModel.canRetryDirectories
          ? { Task { await viewModel.loadDirectories() } } : nil,
        spacingEdges: .top, spacing: 28
      ) {
        isConfirmFocused = true
      }

      SheetActionButton(
        title: "下载",
        systemImage: AppSymbol.download,
        loadingTitle: "下载中",
        isLoading: viewModel.isSubmitting,
        isDisabled: !viewModel.canSubmit && !viewModel.isSubmitting,
        focus: $isConfirmFocused
      ) {
        viewModel.submit()
      }
      .padding(.top, 28)
    }
    // 已带入媒体 ID 时直接确认；没带入时「下载」不可用，焦点落在第一项设置上。
    .defaultFocus($isConfirmFocused, true)
    .task { await viewModel.loadDirectories() }
    .task { await sources.load() }
    .onChange(of: viewModel.state) { _, state in
      if state == .completed {
        viewModel.close()
        dismiss()
      }
    }
    .cancelOnExternalNavigation()
  }

  // MARK: - 字幕信息

  /// 取值和字幕卡一致，比卡片多显示几行。
  private var header: some View {
    let subtitle = viewModel.subtitle
    let seasonEpisode = MediaIdentifier.normalizedString(subtitle.season_episode)
    let published =
      MediaIdentifier.normalizedString(subtitle.date_elapsed)
      ?? MediaIdentifier.normalizedString(subtitle.pubdate)

    return SheetItemHeader(
      title: subtitle.displayTitle,
      subtitle: MediaIdentifier.normalizedString(subtitle.description)
    ) {
      if let seasonEpisode {
        SheetInfoTag(systemImage: AppSymbol.season, text: seasonEpisode.formattedSeasonEpisode())
      }
      if let size = subtitle.sizeInBytes, size > 0 {
        SheetInfoTag(systemImage: AppSymbol.size, text: size.formattedBytes())
      }
      if let published {
        SheetInfoTag(systemImage: AppSymbol.time, text: published.toRelativeDateString())
      }
      if let grabs = subtitle.grabs {
        SheetInfoTag(systemImage: AppSymbol.downloads, text: "\(grabs) 次下载")
      }
      if let language = MediaIdentifier.normalizedString(subtitle.language) {
        SheetInfoTag(systemImage: AppSymbol.language, text: language)
      }
      if let site = MediaIdentifier.normalizedString(subtitle.site_name) {
        SheetInfoTag(systemImage: AppSymbol.site, text: site)
      }
    }
  }
}
