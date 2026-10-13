import SwiftUI

struct SubtitleDownloadSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: SubtitleDownloadViewModel
  @State private var showMediaSearch = false
  @State private var showAdvanced: Bool

  init(viewModel: SubtitleDownloadViewModel) {
    self.viewModel = viewModel
    _showAdvanced = State(initialValue: viewModel.selectedIdentity == nil)
  }

  var body: some View {
    VStack {
      Text("下载字幕")
        .font(.headline)
        .foregroundColor(.secondary)
        .padding(.top, 28)

      ScrollView {
        VStack(spacing: 24) {
          LabeledContent("标题") {
            Text(viewModel.subtitle.displayTitle)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let description = MediaIdentifier.normalizedString(viewModel.subtitle.description) {
            LabeledContent("描述") {
              Text(description)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          if let site = MediaIdentifier.normalizedString(viewModel.subtitle.site_name) {
            LabeledContent("站点", value: site)
          }
          if let language = MediaIdentifier.normalizedString(viewModel.subtitle.language) {
            LabeledContent("字幕语言", value: language)
          }
          if let size = viewModel.subtitle.sizeInBytes, size > 0 {
            LabeledContent("文件大小", value: size.formattedBytes())
          }
          directorySection.disabled(!viewModel.canEdit)
          Button {
            showAdvanced.toggle()
          } label: {
            LabeledContent("高级配置") {
              Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
            }
          }
          .disabled(!viewModel.canEdit)
          if showAdvanced { identitySection.disabled(!viewModel.canEdit) }

          SheetActionButton(
            title: viewModel.submitTitle,
            loadingTitle: "下载中",
            isLoading: viewModel.isSubmitting,
            isDisabled: !viewModel.canSubmit && !viewModel.isSubmitting,
            feedbackMessage: viewModel.failure
              ?? (viewModel.canEdit && viewModel.selectedIdentity == nil
                ? "请先按名称查询并选择字幕对应的电影或电视剧，才能下载字幕。" : nil)
          ) {
            viewModel.submit()
          }
          Button(action: close) {
            Text("关闭").frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .applySheetStyles()
      }
    }
    .frame(width: 1200)
    .task { await viewModel.loadDirectories() }
    .onChange(of: viewModel.state) { _, state in
      if state == .completed { close() }
      if state == .invalidated { showMediaSearch = false }
    }
    .sheet(isPresented: $showMediaSearch) {
      ManualMediaSearchSheet(source: viewModel.mediaSource, keyword: viewModel.mediaSearchKeyword) { mediaId, media in
        showMediaSearch = false
        viewModel.selectMedia(id: mediaId, media: media)
      }
    }
    .cancelOnExternalNavigation()
  }

  private var identitySection: some View {
    VStack(spacing: 24) {
      SheetPicker(
        title: "识别数据源",
        selection: Binding(get: { viewModel.mediaSource }, set: viewModel.selectSource),
        options: MediaSearchSource.allowed(for: .media).map {
          PickerOption(title: $0.title, value: $0)
        }
      )
      Button {
        showMediaSearch = true
      } label: {
        LabeledContent("按名称查询媒体编号") {
          Text(viewModel.selectedTitle ?? "未选择")
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
        }
      }
      .accessibilityHint("查找字幕对应的电影或电视剧，选中后填写媒体编号")
    }
  }

  private var directorySection: some View {
    VStack(spacing: 16) {
      if viewModel.isLoadingDirectories {
        ProgressView("加载保存目录…")
          .frame(maxWidth: .infinity)
      }
      if let error = viewModel.directoryError {
        SheetFeedbackView(message: error, actionTitle: "重新加载") {
          Task { await viewModel.loadDirectories() }
        }
      }
      SheetPicker(
        title: "保存目录",
        selection: Binding(get: { viewModel.selectedSavePath }, set: viewModel.selectSavePath),
        options: [PickerOption<String?>(title: "自动匹配", value: nil)]
          + viewModel.savePathChoices.map {
            PickerOption(title: $0, value: Optional($0))
          },
        ignoresInteractionWhileDisabled: viewModel.isLoadingDirectories
      )
      if viewModel.selectedSavePath == nil {
        Text("按所选电影或电视剧，自动匹配 MoviePilot 的媒体下载目录。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func close() {
    viewModel.close()
    dismiss()
  }
}
