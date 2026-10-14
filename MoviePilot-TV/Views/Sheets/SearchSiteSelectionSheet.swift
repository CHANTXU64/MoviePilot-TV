import SwiftUI

struct SearchSiteSelectionSheet: View {
  @ObservedObject var viewModel: SiteFilterViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack {
          Text("搜索站点")
            .font(.headline)
            .padding(.bottom, 12)
          Button {
            viewModel.selectedSites = nil
          } label: {
            choiceLabel("默认", selected: viewModel.selectedSites == nil)
          }
          Button {
            viewModel.selectedSites = []
          } label: {
            choiceLabel("全部站点", selected: viewModel.selectedSites?.isEmpty == true)
          }

          if viewModel.isLoadingSites {
            ProgressView("加载站点中…").padding()
          } else if let error = viewModel.siteLoadError {
            SheetFeedbackView(message: error, actionTitle: "重新加载") {
              Task { await viewModel.loadSites() }
            }
          } else if viewModel.availableSites.isEmpty {
            Text("暂无可选站点").foregroundStyle(.secondary).padding()
          }

          MultiSelectionRows(
            options: viewModel.availableSites, id: \.id,
            selected: Binding(
              get: { viewModel.selectedSites ?? [] },
              set: { viewModel.selectedSites = $0 }
            ), label: { $0.name }
          )

          if let selectedSites = viewModel.selectedSites {
            let unavailable = MultiSelectionSheet.unavailableSelections(
              in: selectedSites, options: viewModel.availableSites, id: \.id
            )
            if !unavailable.isEmpty {
              Button {
                viewModel.selectedSites = selectedSites.subtracting(unavailable)
              } label: {
                Text("清除不可用选择（\(unavailable.count)）")
                  .frame(maxWidth: .infinity)
                  .foregroundColor(.red)
              }
            }
          }

          Button("完成") { dismiss() }
        }
        .applySheetStyles()
        .padding(28)
      }
    }
    .task {
      if !viewModel.hasLoadedSites { await viewModel.loadSites() }
    }
    .cancelOnExternalNavigation()
  }

  private func choiceLabel(_ title: String, selected: Bool) -> some View {
    HStack {
      Text(title)
      Spacer()
      if selected { Image(systemName: "checkmark") }
    }
  }
}
