import Flow
import SwiftUI

/// 添加下载：快速确认面板。
///
/// 左栏是这条资源的信息（种子标题、副标题，季集 / 大小 / 发布时间 / 做种 / 站点），
/// 右栏是少量设置和「下载」，打开时焦点默认在「下载」上，确认一下就走。设置项都是系统菜单，不再弹第二个 Sheet；
/// 关闭交给 Menu 键，不放「取消」按钮。
/// 不放导航栈：tvOS 26 起 sheet 按内容宽高显示；tvOS 18 的 sheet 是全屏，内容居中。
struct AddDownloadSheet: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject private var apiService = APIService.shared
  @StateObject private var viewModel: AddDownloadViewModel
  @StateObject private var sources = MediaSourceOptionsModel()
  @FocusState private var isConfirmFocused: Bool
  /// 资源识别结果，只用于展示副标题和季集，与资源卡取值一致。
  private let meta: MetaInfo?

  static let width: CGFloat = 1400

  init(
    torrent: TorrentInfo, media: MediaInfo? = nil, meta: MetaInfo? = nil,
    onSuccess: (() -> Void)? = nil
  ) {
    self.meta = meta
    _viewModel = StateObject(
      wrappedValue: AddDownloadViewModel(torrent: torrent, media: media, onSuccess: onSuccess)
    )
  }

  var body: some View {
    Group {
      if viewModel.isLoading {
        ProgressView("加载配置中...")
          .frame(maxWidth: .infinity, minHeight: 480)
      } else {
        panel
      }
    }
    .task {
      await viewModel.loadData()
    }
    .task { await sources.load() }
    .cancelOnExternalNavigation()
    .frame(width: Self.width)
  }

  /// 右栏宽度：设置项和「下载」只占右边，不随 Sheet 拉成整行。
  static let controlsWidth: CGFloat = 600

  private var panel: some View {
    // 左栏是资源信息（不可聚焦），右栏是设置和「下载」。
    HStack(alignment: .top, spacing: 56) {
      header
        .frame(maxWidth: .infinity, alignment: .topLeading)

      VStack(alignment: .leading, spacing: 0) {
        if let message = viewModel.loadErrorMessage {
          SheetFeedbackView(message: message, actionTitle: "重新加载") {
            Task {
              await viewModel.loadData()
            }
          }
          .padding(.bottom, 24)
        }

        // 行与行留出间距：聚焦的行会放大，贴在一起会压住相邻行。
        VStack(spacing: 18) {
          SheetPicker(
            title: "下载器",
            selection: Binding(
              get: { viewModel.selectedDownloader ?? "" },
              set: { viewModel.selectedDownloader = $0.isEmpty ? nil : $0 }
            ),
            options: [PickerOption(title: "自动", value: "")]
              + viewModel.downloaders.map {
                PickerOption(title: $0.name, value: $0.name)
              }
          )

          SheetPicker(
            title: "保存路径",
            selection: Binding(
              get: { viewModel.selectedDirectory ?? "" },
              set: { viewModel.selectedDirectory = $0.isEmpty ? nil : $0 }
            ),
            options: [PickerOption(title: "自动", value: "")]
              + viewModel.targetDirectories.map {
                PickerOption(title: $0, value: $0)
              }
          )

          SheetPicker(
            title: "媒体类型",
            selection: $viewModel.mediaType,
            options: [
              PickerOption(title: "自动", value: ""),
              PickerOption(title: "电影", value: "电影"),
              PickerOption(title: "电视剧", value: "电视剧"),
            ]
          )

          // 平时面板保持短：类型为「自动」时不需要来源和 ID。
          // 已带入 ID 时照样显示，提交的值不能藏起来。
          if showsManualMediaFields {
            SheetPicker(
              title: "媒体来源",
              selection: Binding(get: { viewModel.mediaSource }, set: viewModel.selectMediaSource),
              options: sources.options(including: viewModel.mediaSource).map {
                PickerOption(title: $0.title, value: $0.source)
              }
            )

            ManualMediaIdField(
              source: viewModel.mediaSource, sourceTitle: sources.title(for: viewModel.mediaSource),
              mediaId: $viewModel.mediaId
            ) { mediaId, media in
              viewModel.selectManualMedia(media, mediaId: mediaId)
            }
            .disabled(viewModel.mediaType.isEmpty)
          }
        }

        SheetActionButton(
          title: "下载",
          systemImage: "arrow.down.circle.fill",
          loadingTitle: "添加中",
          isLoading: viewModel.isSubmitting,
          isDisabled: viewModel.loadErrorMessage != nil || !apiService.canAccess(.search)
            || !viewModel.isMediaIdValid,
          feedbackMessage: viewModel.errorMessage,
          focus: $isConfirmFocused
        ) {
          guard apiService.canAccess(.search) else { return }
          Task {
            await viewModel.addDownload()
          }
        }
        .padding(.top, 28)
      }
      .frame(width: Self.controlsWidth)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 56)
    .padding(.vertical, 52)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .applySheetStyles()
    .defaultFocus($isConfirmFocused, true)
  }

  private var showsManualMediaFields: Bool {
    !viewModel.mediaType.isEmpty || !viewModel.mediaId.trimmingCharacters(in: .whitespaces).isEmpty
  }

  // MARK: - 资源信息

  private var header: some View {
    let torrent = viewModel.torrent
    let title = MediaIdentifier.normalizedString(torrent.title) ?? "未知"
    // 副标题取值和资源卡一致：识别副标题 → 种子描述。
    let description = TorrentCard.descriptionText(meta: meta, torrent: torrent)
    let seasonEpisode = MediaIdentifier.normalizedString(meta?.season_episode)

    return VStack(alignment: .leading, spacing: 0) {
      // 标题是种子标题，下面是副标题；比卡片多显示几行，设上限避免 Sheet 过高。
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.callout.bold())
          .lineLimit(3)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(8)
        }
      }

      // 放不下时换行，不截断。
      HFlow(itemSpacing: 24, rowSpacing: 8) {
        if let seasonEpisode {
          DownloadMetaItem(systemImage: "tv", text: seasonEpisode.formattedSeasonEpisode())
        }
        DownloadMetaItem(systemImage: "internaldrive", text: torrent.size.formattedBytes())
        if let pubdate = MediaIdentifier.normalizedString(torrent.pubdate) {
          DownloadMetaItem(systemImage: "clock", text: pubdate.toRelativeDateString())
        }
        if let seeders = torrent.seeders {
          DownloadMetaItem(
            systemImage: "arrow.up", text: "\(seeders) 做种",
            tint: seeders <= 5 ? .orange : .green)
        }
        if let peers = torrent.peers {
          DownloadMetaItem(systemImage: "arrow.down", text: "\(peers) 下载")
        }
        if let site = MediaIdentifier.normalizedString(torrent.site_name) {
          DownloadMetaItem(systemImage: "globe", text: site)
        }
      }
      .font(.caption2)
      .lineLimit(1)
      .padding(.top, 16)
    }
  }
}

/// 一项带图标的资源信息，例如「⬇ 7.83 GB」。
private struct DownloadMetaItem: View {
  let systemImage: String
  let text: String
  var tint: Color = .secondary

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(text)
    }
    .foregroundStyle(tint)
  }
}
