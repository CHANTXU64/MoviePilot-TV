import SwiftUI

struct SubtitleDownloadSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: SubtitleDownloadViewModel
  @StateObject private var sources = MediaSourceOptionsModel()
  @State private var showAdvanced: Bool
  @FocusState private var isAdvancedButtonFocused: Bool

  init(viewModel: SubtitleDownloadViewModel) {
    self.viewModel = viewModel
    _showAdvanced = State(initialValue: viewModel.mediaId.isEmpty)
  }

  var body: some View {
    VStack {
      Text("下载字幕")
        .font(.headline)
        .lineLimit(1)
        .foregroundColor(.secondary)
        .padding(.top, 28)

      ScrollView {
        VStack {
          if let error = viewModel.directoryError {
            SheetFeedbackView(message: error, actionTitle: "重新加载") {
              Task { await viewModel.loadDirectories() }
            }
          }

          LabeledContent("标题") {
            Text(viewModel.subtitle.displayTitle)
              .foregroundColor(.secondary)
              .lineLimit(5)
              .fixedSize(horizontal: false, vertical: true)
          }

          if let description = MediaIdentifier.normalizedString(viewModel.subtitle.description) {
            LabeledContent("描述") {
              Text(description)
                .foregroundColor(.secondary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          if let size = viewModel.subtitle.sizeInBytes, size > 0 {
            LabeledContent("大小") {
              Text(size.formattedBytes())
                .foregroundColor(.secondary)
            }
          }

          if let language = MediaIdentifier.normalizedString(viewModel.subtitle.language) {
            LabeledContent("语言") {
              Text(language)
                .foregroundColor(.secondary)
            }
          }

          if let site = MediaIdentifier.normalizedString(viewModel.subtitle.site_name) {
            LabeledContent("站点") {
              Text(site)
                .foregroundColor(.secondary)
            }
          }

          SheetPicker(
            title: "保存路径",
            selection: Binding(get: { viewModel.selectedSavePath }, set: viewModel.selectSavePath),
            options: [PickerOption<String?>(title: "自动", value: nil)]
              + viewModel.savePathChoices.map { PickerOption(title: $0, value: Optional($0)) },
            ignoresInteractionWhileDisabled: viewModel.isLoadingDirectories
          )
          .disabled(!viewModel.canEdit)

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
            Group {
              SheetPicker(
                title: "媒体来源",
                selection: Binding(get: { viewModel.mediaSource }, set: viewModel.selectSource),
                options: sources.options(including: viewModel.mediaSource).map {
                  PickerOption(title: $0.title, value: $0.source)
                }
              )
              ManualMediaIdField(
                source: viewModel.mediaSource, sourceTitle: sources.title(for: viewModel.mediaSource),
                mediaId: $viewModel.mediaId, placeholder: ""
              ) { mediaId, _ in
                viewModel.mediaId = mediaId
              }
            }
            .disabled(!viewModel.canEdit)
          }

          SheetActionButton(
            title: "确定",
            loadingTitle: "下载中",
            isLoading: viewModel.isSubmitting,
            isDisabled: !viewModel.canSubmit && !viewModel.isSubmitting,
            feedbackMessage: viewModel.failure
              ?? (viewModel.canEdit && viewModel.mediaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请填写字幕对应的媒体 ID，可点击放大镜按名称查询。" : nil)
          ) {
            viewModel.submit()
          }

          Button(action: close) {
            Text("取消")
              .frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .applySheetStyles()
      }
    }
    .task { await viewModel.loadDirectories() }
    .task { await sources.load() }
    .onChange(of: viewModel.state) { _, state in
      if state == .completed { close() }
    }
    .cancelOnExternalNavigation()
    .frame(width: 1200)
  }

  private func close() {
    viewModel.close()
    dismiss()
  }
}
