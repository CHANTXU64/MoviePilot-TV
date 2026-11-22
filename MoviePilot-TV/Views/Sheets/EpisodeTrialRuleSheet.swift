import SwiftUI

/// 设置页「试看订阅规则」：和订阅大面板同样的版式，右边是搜索和下载规则，左栏是说明和「保存」。
struct EpisodeTrialRuleSheet: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: EpisodeTrialRuleViewModel
  @FocusState private var focusedField: SubscribeSettingField?
  @FocusState private var isSaveFocused: Bool

  init(service: EpisodeTrialService, apiService: APIService) {
    _viewModel = StateObject(wrappedValue: EpisodeTrialRuleViewModel(service: service, apiService: apiService))
  }

  var body: some View {
    SheetSettingsPanel(
      fields: EpisodeTrialRuleViewModel.fields,
      focusedField: $focusedField,
      helpText: focusedField?.help
    ) {
      VStack(alignment: .leading, spacing: 16) {
        Text("试看订阅规则")
          .font(.headline.bold())
        Text("试看一集时，临时订阅按这里的规则搜索和下载。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } actions: {
      SheetRetryingMessage(
        message: viewModel.loadErrorMessage ?? viewModel.saveErrorMessage,
        isBusy: viewModel.isLoading,
        retry: viewModel.loadErrorMessage == nil ? nil : { Task { await viewModel.load() } }
      ) {
        isSaveFocused = true
      }
      SheetActionButton(
        title: "保存", systemImage: AppSymbol.save, loadingTitle: "加载中", isLoading: viewModel.isLoading,
        focus: $isSaveFocused
      ) {
        if viewModel.save() { dismiss() }
      }
    } row: { field in
      SubscribeRuleFieldRow(
        field: field, subscribe: $viewModel.draft, options: viewModel.options,
        unspecifiedChoiceTitle: EpisodeTrialRuleViewModel.unspecifiedChoiceTitle)
    }
    .task { await viewModel.load() }
  }
}
