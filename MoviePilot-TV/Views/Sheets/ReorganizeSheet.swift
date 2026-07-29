import SwiftUI

nonisolated func manualTransferPreviewFileName(from path: String?) -> String? {
  guard let path else { return nil }
  let normalized = path
    .replacingOccurrences(of: "\\", with: "/")
    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  return normalized.split(separator: "/").last.map(String.init)
}

struct ReorganizeSheet: View {
  @Environment(\.dismiss) var dismiss
  let onDone: () -> Void

  @StateObject private var viewModel: ReorganizeViewModel
  @State private var showAdvanced = false
  @State private var showMediaSearch = false
  @State private var showPreview = false
  @FocusState private var isAdvancedButtonFocused: Bool

  init(
    logIds: [Int] = [],
    fileItem: FileItem? = nil,
    targetStorage: String? = nil,
    onDone: @escaping () -> Void
  ) {
    _viewModel = StateObject(
      wrappedValue: ReorganizeViewModel(
        logIds: logIds,
        fileItem: fileItem,
        targetStorage: targetStorage
      )
    )
    self.onDone = onDone
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isLoading {
          ProgressView("加载配置中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          manualFormView
        }
      }
      .task {
        await viewModel.loadConfig()
      }
    }
  }

  private var manualFormView: some View {
    VStack {
      Text(viewModel.isFromHistory ? "重新整理" : "手动整理")
        .font(.headline)
        .foregroundColor(.secondary)
        .padding(.top, 28)
        .padding(.bottom, 0)

      ScrollView {
        VStack {
          if let message = viewModel.loadErrorMessage {
            SheetFeedbackView(message: message, actionTitle: "重新加载") {
              Task {
                await viewModel.loadConfig()
              }
            }
          }

          basicSettings
          recognitionInfo
          if viewModel.form.type_name == "电视剧" {
            seriesInfo
          }
          advancedSection
          actionButtons
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .applySheetStyles()
      }
    }
    .sheet(isPresented: $showPreview) {
      if let preview = viewModel.previewData {
        ReorganizePreviewSheet(preview: preview)
      }
    }
  }

  private var basicSettings: some View {
    Group {
      SheetPicker(
        title: "目的存储",
        selection: Binding(
          get: { viewModel.form.target_storage ?? "" },
          set: { viewModel.form.target_storage = $0.isEmpty ? nil : $0 }
        ),
        options: [PickerOption(title: "自动", value: "")]
          + viewModel.storages.map { PickerOption(title: $0.name, value: $0.type) }
      )

      SheetPicker(
        title: "整理方式",
        selection: Binding(
          get: { viewModel.form.transfer_type ?? "" },
          set: { viewModel.form.transfer_type = $0.isEmpty ? nil : $0 }
        ),
        options: [
          PickerOption(title: "自动", value: ""),
          PickerOption(title: "复制", value: "copy"),
          PickerOption(title: "移动", value: "move"),
          PickerOption(title: "硬链接", value: "link"),
          PickerOption(title: "软链接", value: "softlink"),
        ]
      )

      SheetPicker(
        title: "目的目录",
        selection: Binding(
          get: { viewModel.form.target_path },
          set: { viewModel.form.target_path = $0 }
        ),
        options: viewModel.targetDirectoryOptions
      )
    }
  }

  private var recognitionInfo: some View {
    Group {
      SheetPicker(
        title: "媒体类型",
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

      SheetPicker(
        title: "媒体来源",
        selection: Binding(
          get: { viewModel.mediaSource },
          set: { viewModel.selectMediaSource($0) }
        ),
        options: MediaSearchSource.allowed(for: .media).map {
          PickerOption(title: $0.title, value: $0)
        }
      )

      HStack(spacing: 20) {
        SheetTextField(
          title: "\(viewModel.mediaSource.title) ID",
          placeholder: "自动判断",
          text: $viewModel.mediaId,
          keyboardType: .numberPad
        )

        Button {
          showMediaSearch = true
        } label: {
          Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("搜索媒体")
      }
      if !viewModel.isMediaIdValid {
        Text("媒体 ID 只能包含数字")
          .foregroundStyle(.red)
      }
    }
    .sheet(isPresented: $showMediaSearch) {
      ManualMediaSearchSheet(source: viewModel.mediaSource) { mediaId, media in
        viewModel.selectManualMedia(media, mediaId: mediaId)
        showMediaSearch = false
      }
    }
  }

  private var seriesInfo: some View {
    Group {
      if viewModel.mediaSource == .themoviedb {
        SheetPicker(
          title: "指定剧集",
          selection: Binding(
            get: { viewModel.form.episode_group ?? "" },
            set: { viewModel.form.episode_group = $0.isEmpty ? nil : $0 }
          ),
          options: viewModel.episodeGroupOptions
        )
        .disabled(
          viewModel.mediaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.isEpisodeGroupsLoading
        )
        .task(id: viewModel.episodeGroupQueryKey) {
          try? await Task.sleep(nanoseconds: 400_000_000)
          guard !Task.isCancelled else { return }
          await viewModel.loadEpisodeGroups()
        }
        if viewModel.isEpisodeGroupsLoading {
          ProgressView("正在加载剧集组")
        }
      }

      SheetTextField(
        title: "指定季数",
        placeholder: "第几季",
        text: Binding(
          get: {
            if let season = viewModel.form.season { return String(season) }
            return ""
          },
          set: { viewModel.form.season = Int($0) }
        ),
        keyboardType: .numberPad
      )

      SheetTextField(
        title: "指定集数",
        placeholder: "集数或范围，如 1 或 1,10",
        text: Binding(
          get: { viewModel.form.episode_detail ?? "" },
          set: { viewModel.form.episode_detail = $0.isEmpty ? nil : $0 }
        )
      )
      .disabled(viewModel.isEpisodeDetailDisabled)

      SheetTextField(
        title: "集数定位",
        placeholder: "辅助识别集数部分",
        text: Binding(
          get: { viewModel.form.episode_format ?? "" },
          set: { viewModel.form.episode_format = $0.isEmpty ? nil : $0 }
        )
      )

      SheetTextField(
        title: "集数偏移",
        placeholder: "如 -10 或 EP*2",
        text: Binding(
          get: { viewModel.form.episode_offset ?? "" },
          set: { viewModel.form.episode_offset = $0.isEmpty ? nil : $0 }
        ),
        keyboardType: .numbersAndPunctuation
      )
    }
  }

  private var advancedSection: some View {
    Group {
      Button {
        withAnimation {
          showAdvanced.toggle()
        }
      } label: {
        HStack {
          Text("高级配置")
          Spacer()
          Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
        }
        .foregroundColor(isAdvancedButtonFocused ? .black : .secondary)
        .if(SheetStyleFix.shouldApply) { view in
          view.padding(.horizontal)
        }
      }
      .focused($isAdvancedButtonFocused)

      if showAdvanced {
        SheetTextField(
          title: "指定Part",
          placeholder: "如 part1",
          text: Binding(
            get: { viewModel.form.episode_part ?? "" },
            set: { viewModel.form.episode_part = $0.isEmpty ? nil : $0 }
          )
        )

        SheetTextField(
          title: "最小大小(MB)",
          placeholder: "只整理大于此的",
          text: Binding(
            get: {
              if viewModel.form.min_filesize == 0 {
                return ""
              }
              return String(viewModel.form.min_filesize)
            },
            set: { viewModel.form.min_filesize = Int($0) ?? 0 }
          ),
          keyboardType: .numberPad
        )

        Toggle(
          "刮削元数据",
          isOn: Binding(
            get: { viewModel.form.scrape ?? false },
            set: { viewModel.form.scrape = $0 }
          )
        )

        if !viewModel.form.target_path.isEmpty {
          Toggle(
            "层级目录 (电影/电视剧)",
            isOn: Binding(
              get: { viewModel.form.library_type_folder ?? false },
              set: { viewModel.form.library_type_folder = $0 }
            )
          )
          Toggle(
            "分类目录 (类型/产地)",
            isOn: Binding(
              get: { viewModel.form.library_category_folder ?? false },
              set: { viewModel.form.library_category_folder = $0 }
            )
          )
        }

        if viewModel.isFromHistory {
          Toggle(
            "复用历史识别记录",
            isOn: Binding(
              get: { viewModel.form.from_history },
              set: { viewModel.form.from_history = $0 }
            )
          )
        }
      }
    }
  }

  private var actionButtons: some View {
    Group {
      SheetActionButton(
        title: "预览整理结果",
        loadingTitle: "预览中",
        isLoading: viewModel.isPreviewing,
        isDisabled: viewModel.loadErrorMessage != nil || !viewModel.isMediaIdValid,
        feedbackMessage: nil
      ) {
        Task {
          await viewModel.preview()
          if viewModel.previewData != nil {
            showPreview = true
          }
        }
      }

      SheetActionButton(
        title: "开始整理",
        loadingTitle: "整理中",
        isLoading: viewModel.isSubmitting,
        isDisabled: viewModel.loadErrorMessage != nil || !viewModel.isMediaIdValid,
        feedbackMessage: nil
      ) {
        Task {
          if await viewModel.submit(background: true) {
            onDone()
            dismiss()
          }
        }
      }

      Button {
        dismiss()
      } label: {
        Text("取消")
          .frame(maxWidth: .infinity)
      }

      if let message = viewModel.errorMessage {
        SheetFeedbackView(message: message)
      }
    }
  }
}

private struct ReorganizePreviewSheet: View {
  let preview: ManualTransferPreviewData

  var body: some View {
    VStack(spacing: 24) {
      Text("整理预览")
        .font(.headline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)

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
      .padding(.horizontal, 28)

      if let message = preview.message, !message.isEmpty {
        Label(message, systemImage: "info.circle")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 28)
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
              .buttonStyle(.card)
            }
          }
        }
        .contentMargins(28, for: .scrollContent)
        .focusSection()
      }
    }
    .padding(.top, 28)
    .frame(width: 1400, height: 820)
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
