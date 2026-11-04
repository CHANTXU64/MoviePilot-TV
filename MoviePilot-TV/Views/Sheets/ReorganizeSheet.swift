import Flow
import SwiftUI

nonisolated func manualTransferPreviewFileName(from path: String?) -> String? {
  guard let path else { return nil }
  let normalized = path
    .replacingOccurrences(of: "\\", with: "/")
    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  return normalized.split(separator: "/").last.map(String.init)
}

/// 重新整理面板：一打开就是三栏大面板，和编辑订阅一致。
///
/// 左栏是要整理的记录（单条是文件名、识别结果和整理状态；多条是记录数量与成功失败数），
/// 中间是当前项说明，底部是「开始整理」「预览整理结果」。右边设置不分组、平铺两列。
/// 设置顺序与 Web 整理对话框一致，见 `ReorganizeSettingField`。
struct ReorganizeSheet: View {
  @Environment(\.dismiss) var dismiss
  let records: [TransferHistory]
  let onDone: () -> Void

  @StateObject private var viewModel: ReorganizeViewModel
  @StateObject private var sources = MediaSourceOptionsModel()
  @State private var showPreview = false
  @FocusState private var focusedField: ReorganizeSettingField?
  @FocusState private var isStartFocused: Bool
  @FocusState private var isRetryFocused: Bool
  /// 重新加载期间 ViewModel 会先清掉加载失败的原因；这段时间继续显示，提示和「重试」不消失。
  @State private var retainedLoadError: String?

  init(
    records: [TransferHistory],
    fileItem: FileItem? = nil,
    targetStorage: String? = nil,
    sourceSession: APIServiceSessionSnapshot,
    validateBeforeSubmit: @escaping () async throws -> String?,
    onDone: @escaping () -> Void
  ) {
    self.records = records
    _viewModel = StateObject(
      wrappedValue: ReorganizeViewModel(
        logIds: records.map(\.id),
        fileItem: fileItem,
        targetStorage: targetStorage,
        validateBeforeSubmit: validateBeforeSubmit,
        sourceSession: sourceSession
      )
    )
    self.onDone = onDone
  }

  var body: some View {
    // 不单独显示加载页：系统 sheet 换尺寸没有动画，加载页和面板来回切会闪。
    // 一打开就是最终尺寸的面板，加载中只让主按钮显示「加载中」。
    SheetSettingsPanel(
      fields: visibleFields,
      focusedField: $focusedField,
      helpText: helpText
    ) {
      header
    } actions: {
      actions
    } row: { field in
      row(field)
    }
    .task {
      await viewModel.loadConfig()
    }
    .onChange(of: viewModel.loadErrorMessage) { _, message in
      if let message { retainedLoadError = message }
    }
    .onChange(of: viewModel.isLoading) { _, isLoading in
      guard !isLoading, viewModel.loadErrorMessage == nil else { return }
      // 重试成功：提示要消失了，焦点还在「重试」上时移到「开始整理」，不让系统随便挪。
      if retainedLoadError != nil, isRetryFocused { isStartFocused = true }
      retainedLoadError = nil
    }
    .task { await sources.load() }
    .cancelOnExternalNavigation()
    .sheet(isPresented: $showPreview) {
      if let preview = viewModel.previewData {
        ReorganizePreviewSheet(preview: preview)
      }
    }
    .alert(
      "操作未执行",
      isPresented: Binding(
        get: { viewModel.mutationRetryMessage != nil },
        set: { if !$0 { viewModel.mutationRetryMessage = nil } }
      ),
      actions: {
        Button("好") {
          viewModel.mutationRetryMessage = nil
          dismiss()
        }
      },
      message: {
        Text(viewModel.mutationRetryMessage ?? "")
      }
    )
  }

  private var visibleFields: [ReorganizeSettingField] {
    ReorganizeSettingField.allCases.filter { field in
      switch field {
      case .fromHistory:
        viewModel.isFromHistory
      case .episodeGroup:
        isTV && viewModel.mediaSource == .themoviedb
      case .season, .episodeDetail, .episodeFormat, .episodeOffset:
        isTV
      default:
        true
      }
    }
  }

  private var isTV: Bool { viewModel.form.type_name == "电视剧" }

  /// 左栏居中的说明，只说明当前设置项；焦点在按钮上时留空。
  private var helpText: String? {
    focusedField?.help(isBatch: records.count > 1)
  }

  // MARK: - 左栏

  /// 要整理的记录。单条：文件名、识别结果（片名 · 类型 · 季集）、整理状态和方式、失败原因。
  /// 多条：记录数量、涉及的片名、成功与失败各几条。
  @ViewBuilder
  private var header: some View {
    if records.count > 1 {
      batchHeader
    } else if let record = records.first {
      recordHeader(record)
    }
  }

  private func recordHeader(_ record: TransferHistory) -> some View {
    let fileName =
      manualTransferPreviewFileName(from: record.src ?? record.src_fileitem?.path)
      ?? MediaIdentifier.normalizedString(record.title) ?? "整理记录"
    let seasonEpisode = [record.seasons, record.episodes]
      .compactMap { MediaIdentifier.normalizedString($0) }
      .joined(separator: " ")
      .formattedSeasonEpisode()
    let mediaLine = [
      MediaIdentifier.normalizedString(record.title),
      MediaIdentifier.normalizedString(record.type),
      record.type == "电视剧" && !seasonEpisode.isEmpty ? seasonEpisode : nil,
    ].compactMap { $0 }.joined(separator: " · ")

    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        // 只是文件名，用和「添加下载」种子标题一样的字号。
        Text(fileName)
          .font(.callout.bold())
          .lineLimit(8)
          .fixedSize(horizontal: false, vertical: true)
        if !mediaLine.isEmpty {
          Text(mediaLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      HFlow(itemSpacing: 24, rowSpacing: 8) {
        statusTag(isSuccess: record.status.value, text: record.status.value ? "整理成功" : "整理失败")
        if let mode = MediaIdentifier.normalizedString(record.mode) {
          SheetInfoTag(systemImage: "arrow.right.doc.on.clipboard", text: transferModeDisplayName(for: mode))
        }
        if let size = record.src_fileitem?.size {
          SheetInfoTag(systemImage: "internaldrive", text: size.formattedBytes())
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.top, 16)

      // 失败原因和上面的标签同样是小字，属于记录信息，不和居中的说明混淆。
      if let reason = record.failureReason() {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var batchHeader: some View {
    var seen = Set<String>()
    let titles = records.compactMap { MediaIdentifier.normalizedString($0.title) }
      .filter { seen.insert($0).inserted }
    let successCount = records.filter(\.status.value).count
    let failureCount = records.count - successCount

    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text("\(records.count) 条整理记录")
          .font(.callout.bold())
        if !titles.isEmpty {
          Text(titles.joined(separator: "、"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
      }

      HFlow(itemSpacing: 24, rowSpacing: 8) {
        if successCount > 0 {
          statusTag(isSuccess: true, text: "\(successCount) 条成功")
        }
        if failureCount > 0 {
          statusTag(isSuccess: false, text: "\(failureCount) 条失败")
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.top, 16)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func statusTag(isSuccess: Bool, text: String) -> some View {
    SheetInfoTag(
      systemImage: isSuccess ? "checkmark.circle" : "xmark.circle", text: text)
  }

  /// 出错原因：加载失败优先，其次是当前整理方式不受支持，最后是整理或预览的结果。
  /// 加载失败（重新加载期间继续显示）、整理方式不受支持、媒体 ID 格式不对，最后是整理或预览的结果。
  /// 媒体 ID 的问题也放在这里，不在设置列里插一行红字，免得后面的行跟着跳。
  private var statusMessage: String? {
    viewModel.loadErrorMessage
      ?? (viewModel.isLoading ? retainedLoadError : nil)
      ?? viewModel.transferTypeGateMessage
      ?? (viewModel.isMediaIdValid ? nil : "媒体 ID 格式无效。")
      ?? viewModel.errorMessage
  }

  private var isTransferActionDisabled: Bool {
    viewModel.loadErrorMessage != nil
      || !viewModel.isMediaIdValid
      || viewModel.transferTypeGateMessage != nil
  }

  /// 只有加载失败时提供「重试」。整理失败时直接再按「开始整理」，不另设按钮重复提交。
  private var retryAction: (() -> Void)? {
    guard viewModel.loadErrorMessage != nil || (viewModel.isLoading && retainedLoadError != nil)
    else { return nil }
    return {
      guard !viewModel.isLoading else { return }
      Task { await viewModel.loadConfig() }
    }
  }

  @ViewBuilder
  private var actions: some View {
    if let message = statusMessage {
      SheetMessageBlock(
        message: message, retry: retryAction, isRetrying: viewModel.isLoading,
        retryFocus: $isRetryFocused
      )
      .padding(.bottom, 20)
    }

    VStack(spacing: 18) {
      SheetActionButton(
        title: "开始整理",
        systemImage: "arrow.triangle.2.circlepath",
        loadingTitle: viewModel.isLoading ? "加载中" : "整理中",
        isLoading: viewModel.isSubmitting || viewModel.isLoading,
        isDisabled: isTransferActionDisabled,
        focus: $isStartFocused
      ) {
        Task {
          if await viewModel.submit(background: true) {
            onDone()
            dismiss()
          }
        }
      }

      SheetActionButton(
        title: "预览整理结果",
        loadingTitle: "预览中",
        isLoading: viewModel.isPreviewing,
        isDisabled: isTransferActionDisabled || viewModel.isLoading || viewModel.isSubmitting
      ) {
        Task {
          if (await viewModel.preview()).shouldPresent {
            showPreview = true
          }
        }
      }
    }
  }

  // MARK: - 设置行

  /// 选项随后端版本变化；目录方式不可用时不再提供「自动」。
  private var transferTypeOptions: [PickerOption<String>] {
    viewModel.selectableTransferTypes.map { value in
      PickerOption(title: ReorganizeTransferCapability.title(for: value), value: value)
    }
  }

  @ViewBuilder
  private func row(_ field: ReorganizeSettingField) -> some View {
    switch field {
    case .mediaType:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.form.type_name ?? "" },
          set: { viewModel.selectMediaType($0.isEmpty ? nil : $0) }
        ),
        options: [
          PickerOption(title: "自动", value: ""),
          PickerOption(title: "电影", value: "电影"),
          PickerOption(title: "电视剧", value: "电视剧"),
        ]
      )
    case .mediaSource:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.mediaSource },
          set: { viewModel.selectMediaSource($0) }
        ),
        options: sources.options(including: viewModel.mediaSource).map {
          PickerOption(title: $0.title, value: $0.source)
        }
      )
    case .mediaId:
      ManualMediaIdField(
        source: viewModel.mediaSource, sourceTitle: sources.title(for: viewModel.mediaSource),
        isInline: true, mediaId: $viewModel.mediaId
      ) { mediaId, media in
        viewModel.selectManualMedia(media, mediaId: mediaId)
      }
    case .targetPath:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.form.target_path },
          set: { viewModel.selectTargetPath($0) }
        ),
        options: viewModel.targetDirectoryOptions,
        // 目录还没加载出来时只能是「自动」，菜单里提示正在加载。
        unavailableMessage: viewModel.isLoading ? "正在加载…" : nil
      )
    case .targetStorage:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.form.target_storage ?? "" },
          set: { viewModel.form.target_storage = $0.isEmpty ? nil : $0 }
        ),
        options: [PickerOption(title: "自动", value: "")]
          + viewModel.storages.map { PickerOption(title: $0.name, value: $0.type) },
        unavailableMessage: viewModel.isLoading ? "正在加载…" : nil
      )
    case .transferType:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.form.transfer_type ?? "" },
          set: { viewModel.form.transfer_type = $0.isEmpty ? nil : $0 }
        ),
        options: transferTypeOptions
      )
    case .typeFolder:
      Toggle(
        field.title,
        isOn: Binding(
          get: { viewModel.form.library_type_folder ?? false },
          set: { viewModel.form.library_type_folder = $0 }
        )
      )
    case .categoryFolder:
      Toggle(
        field.title,
        isOn: Binding(
          get: { viewModel.form.library_category_folder ?? false },
          set: { viewModel.form.library_category_folder = $0 }
        )
      )
    case .scrape:
      Toggle(
        field.title,
        isOn: Binding(
          get: { viewModel.form.scrape ?? false },
          set: { viewModel.form.scrape = $0 }
        )
      )
    case .fromHistory:
      Toggle(
        field.title,
        isOn: Binding(
          get: { viewModel.form.from_history },
          set: { viewModel.form.from_history = $0 }
        )
      )
    case .episodeGroup:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.form.episode_group ?? "" },
          set: { viewModel.form.episode_group = $0.isEmpty ? nil : $0 }
        ),
        options: viewModel.episodeGroupOptions,
        // 加载剧集组期间保持可聚焦但忽略点击，避免焦点跳走
        // 没填 ID 时也能移上去看说明，菜单里提示先填 ID；加载剧集组期间提示正在加载。
        unavailableMessage: viewModel.mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty ? "请先填写 TMDB ID" : viewModel.isEpisodeGroupsLoading ? "正在加载…" : nil
      )
      .task(id: viewModel.episodeGroupQueryKey) {
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        await viewModel.loadEpisodeGroups()
      }
    case .season:
      SheetInlineTextField(
        title: field.title,
        text: Binding(
          get: { viewModel.form.season.map(String.init) ?? "" },
          set: { viewModel.form.season = Int($0) }
        ),
        keyboardType: .numberPad
      )
    case .episodeDetail:
      SheetInlineTextField(
        title: field.title,
        text: optionalText(\.episode_detail)
      )
      .disabled(viewModel.isEpisodeDetailDisabled)
    case .episodeFormat:
      SheetInlineTextField(
        title: field.title,
        text: optionalText(\.episode_format)
      )
    case .episodeOffset:
      SheetInlineTextField(
        title: field.title,
        text: optionalText(\.episode_offset),
        keyboardType: .numbersAndPunctuation
      )
    case .part:
      SheetInlineTextField(
        title: field.title,
        text: optionalText(\.episode_part)
      )
    case .minFileSize:
      SheetInlineTextField(
        title: field.title,
        text: Binding(
          get: { viewModel.form.min_filesize == 0 ? "" : String(viewModel.form.min_filesize) },
          set: { viewModel.form.min_filesize = Int($0) ?? 0 }
        ),
        keyboardType: .numberPad
      )
    }
  }

  /// 可选文字字段：清空即不传。
  private func optionalText(_ keyPath: WritableKeyPath<ReorganizeForm, String?>) -> Binding<String> {
    Binding(
      get: { viewModel.form[keyPath: keyPath] ?? "" },
      set: { viewModel.form[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
    )
  }
}

/// 整理大面板里的一项设置：标题、说明和出现顺序。
///
/// 顺序与 Web 整理对话框一致：目的存储、整理方式、目的目录，媒体类型、来源、ID，
/// 剧集相关项（只在电视剧时出现），Part、最小文件大小，最后是几个开关。
/// 设置最少时也有十二项、第一列六项，所以会让其他项增减的媒体类型、媒体来源
/// 和带搜索的媒体 ID 始终在第一列原位，两列重排时焦点不跳。
/// 刮削和两个分目录开关一直显示（与 Web 一致）；目的目录为自动时不改动就按目录设置。
enum ReorganizeSettingField: Hashable, CaseIterable {
  case targetStorage, transferType, targetPath
  case mediaType, mediaSource, mediaId
  case episodeGroup, season, episodeDetail, episodeFormat, episodeOffset
  case part, minFileSize
  case typeFolder, categoryFolder, scrape, fromHistory

  var title: String {
    switch self {
    case .mediaType: "媒体类型"
    case .mediaSource: "媒体来源"
    case .mediaId: "媒体 ID"
    case .targetPath: "目的目录"
    case .targetStorage: "目的存储"
    case .transferType: "整理方式"
    case .typeFolder: "按类型分目录"
    case .categoryFolder: "按类别分目录"
    case .scrape: "刮削元数据"
    case .fromHistory: "复用历史识别信息"
    case .episodeGroup: "剧集组"
    case .season: "指定季"
    case .episodeDetail: "指定集数"
    case .episodeFormat: "集数定位"
    case .episodeOffset: "集数偏移"
    case .part: "指定 Part"
    case .minFileSize: "最小文件大小"
    }
  }

  /// 当前项的说明，最多两行（左栏宽度下约 34 个字）。
  /// 写给家里所有人看，不提后台设置里的概念；含义已对照 MoviePilot 后端与 Web。
  func help(isBatch: Bool) -> String {
    switch self {
    case .targetStorage: "整理后文件存放的存储；自动表示按默认规则。"
    case .transferType: "文件的整理方式，如复制、移动、硬链接；自动表示按默认规则。"
    case .targetPath: "整理后文件存放的媒体库目录；自动表示按默认规则匹配。"
    case .mediaType: "文件的媒体类型；自动表示按文件名识别。选择电视剧后可指定季与集。"
    case .mediaSource: "媒体 ID 所属的数据源；填写 ID 后，识别与刮削均使用此来源。"
    case .mediaId: "正确的媒体编号，可通过搜索查找；留空则自动识别。"
    case .episodeGroup: "按指定剧集组划分季与集；须先填写 TMDB ID。"
    case .season: "文件所属的季；留空则自动识别。"
    case .episodeDetail: "文件对应的集数，如 3；1,10 表示第 1 至 10 集。留空则自动识别。"
    case .episodeFormat: "用 {ep} 标出文件名中集数的位置，不符合的文件将被跳过。"
    case .episodeOffset: "对识别出的集数进行调整，如 -10 或 EP*2。"
    case .part: "分段文件的标记，如 part1，将加入整理后的文件名。"
    case .minFileSize: "仅整理大于此大小的视频文件，单位 MB；字幕不受限制。"
    case .typeFolder: "在目的目录下按电影、电视剧建立子目录；未调整时按默认规则。"
    case .categoryFolder: "在目的目录下按类别建立子目录，如华语电影；未调整时按默认规则。"
    case .scrape: "整理后生成海报、简介等媒体信息文件；未调整时按默认规则。"
    case .fromHistory:
      isBatch
        ? "使用各条记录已识别的媒体、季与集，替代手动填写的识别信息。"
        : "使用这条记录已识别的媒体、季与集，替代手动填写的识别信息。"
    }
  }

}

private struct ReorganizePreviewSheet: View {
  let preview: ManualTransferPreviewData

  /// 与统一阅读 Sheet 同规格：1500×900，左右边距 72、顶部 64，标题 `.title3` 加粗。
  /// 列表卡片的左右边距放在滚动内容上，卡片与标题对齐，聚焦放大时也不会被裁掉。
  private static let horizontalPadding = ReadingSheetLayout.horizontalPadding

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("整理预览")
        .font(.title3.bold())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.horizontalPadding)

      HStack(spacing: 12) {
        summaryCard(
          title: "全部",
          value: preview.summary.total,
          icon: "doc.on.doc",
          color: .blue
        )
        summaryCard(
          title: "可整理",
          value: preview.summary.success,
          icon: "checkmark.circle.fill",
          color: .green
        )
        summaryCard(
          title: "失败",
          value: preview.summary.failed,
          icon: "exclamationmark.triangle.fill",
          color: .red
        )
      }
      .padding(.horizontal, Self.horizontalPadding)

      if let message = preview.message, !message.isEmpty {
        Label(message, systemImage: "info.circle")
          .font(.body)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Self.horizontalPadding)
      }

      if preview.items.isEmpty {
        EmptyDataView(title: "暂无预览结果")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 16) {
            ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
              Button(action: {}) {
                previewRow(item)
              }
              .buttonStyle(TextCardButtonStyle())
            }
          }
        }
        .contentMargins(.horizontal, Self.horizontalPadding, for: .scrollContent)
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, ReadingSheetLayout.verticalPadding, for: .scrollContent)
        .focusSection()
      }
    }
    .padding(.top, ReadingSheetLayout.verticalPadding)
    .frame(
      width: ReadingSheetLayout.sheetWidth,
      height: ReadingSheetLayout.sheetHeight,
      alignment: .topLeading
    )
  }

  private func summaryCard(
    title: String,
    value: Int,
    icon: String,
    color: Color
  ) -> some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .foregroundStyle(color)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value.formatted())
      }
      Spacer()
    }
    .padding(14)
    .padding(.leading, 10)
    .frame(maxWidth: .infinity)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func previewRow(_ item: ManualTransferPreviewItem) -> some View {
    HStack(spacing: 20) {
      pathCard(
        title: "整理前",
        name: manualTransferPreviewFileName(from: item.source) ?? item.title ?? "未知文件",
        path: item.source ?? "未提供来源路径",
        color: .primary
      )

      Image(systemName: "arrow.right")
        .foregroundStyle(item.success == false ? .red : .secondary)

      pathCard(
        title: item.success == false ? "无法整理" : "整理后",
        name: manualTransferPreviewFileName(from: item.target)
          ?? (item.success == false ? "无法生成目标文件" : item.title ?? "未生成目标文件"),
        path: item.target ?? "未生成目标路径",
        color: item.success == false ? .red : .primary,
        message: item.success == false ? item.message : nil
      )
    }
    .padding(24)
  }

  private func pathCard(
    title: String,
    name: String,
    path: String,
    color: Color,
    message: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Text(name)
        .foregroundStyle(color)
        .lineLimit(2)
      Text(path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let message, !message.isEmpty {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

}
