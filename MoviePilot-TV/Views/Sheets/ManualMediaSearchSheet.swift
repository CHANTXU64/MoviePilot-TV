import Combine
import SwiftUI

@MainActor
final class ManualMediaSearchViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var keyword = ""
  @Published var items: [MediaInfo] = []
  @Published var isLoading = false
  @Published private(set) var searchedKeyword: String?
  @Published private(set) var errorMessage: String?

  let source: MediaSearchSource
  private let apiService: APIService
  private var searchRevision = 0
  private let dismissalReleaseScheduler = PresentationReleaseScheduler()

  init(source: MediaSearchSource, keyword: String = "", apiService: APIService = .shared) {
    self.source = source
    self.keyword = keyword
    self.apiService = apiService
  }

  func search() async {
    searchRevision &+= 1
    let revision = searchRevision
    let title = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    searchedKeyword = title.isEmpty ? nil : title
    errorMessage = nil
    items = []
    guard !title.isEmpty else {
      isLoading = false
      return
    }

    isLoading = true
    defer {
      if searchRevision == revision {
        isLoading = false
      }
    }
    do {
      let results = try await apiService.searchManualMedia(title: title, source: source)
        .filter { ManualMediaSelection.mediaId(for: $0, source: source) != nil }
      guard searchRevision == revision else { return }
      items = results
    } catch {
      guard searchRevision == revision else { return }
      errorMessage = error.localizedDescription
      Logger.error("Failed to search manual media ID: \(error)")
    }
  }

  func presentationDidAppear() {
    let wasAwaitingDismissalCleanup = dismissalReleaseScheduler.isPending
    dismissalReleaseScheduler.cancel()
    if wasAwaitingDismissalCleanup {
      isLoading = false
    }
  }

  func presentationDidDisappear(
    retention: Duration = PresentationTransitionRetention.duration
  ) {
    searchRevision &+= 1
    let revision = searchRevision
    dismissalReleaseScheduler.schedule(after: retention) { [self] in
      guard searchRevision == revision else { return }
      items = []
      isLoading = false
    }
  }
}

struct ManualMediaSearchSheet: View {
  @ObservedObject private var apiService = APIService.shared
  @StateObject private var viewModel: ManualMediaSearchViewModel
  @State private var searchTask: Task<Void, Never>?

  let onSelect: (String, MediaInfo) -> Void

  init(
    source: MediaSearchSource,
    keyword: String = "",
    onSelect: @escaping (String, MediaInfo) -> Void
  ) {
    _viewModel = StateObject(wrappedValue: ManualMediaSearchViewModel(source: source, keyword: keyword))
    self.onSelect = onSelect
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text("按名称查询 \(viewModel.source.title) 媒体编号")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 28)

        HStack(spacing: 20) {
          SheetTextField(
            title: "电影或电视剧名称",
            placeholder: "输入电影或电视剧名称后搜索",
            text: $viewModel.keyword
          )
          .labelsHidden()

          Button {
            // 搜索中保持可聚焦：tvOS 上聚焦元素变 disabled 会导致焦点跳走；
            // 点击在加载中被忽略，防重入由 guard 完成。
            guard !viewModel.isLoading else { return }
            searchTask?.cancel()
            searchTask = Task { await viewModel.search() }
          } label: {
            Label("搜索", systemImage: "magnifyingglass")
          }
        }
        .focusSection()
        .padding(.horizontal, 28)

        if viewModel.isLoading {
          ProgressView("搜索中…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
          EmptyDataView(title: "媒体查询失败", description: "\(error)\n请使用上方搜索按钮重试。")
        } else if viewModel.items.isEmpty {
          EmptyDataView(
            title: viewModel.searchedKeyword == nil ? "输入名称查询媒体编号" : "未找到匹配的电影或电视剧",
            description: viewModel.searchedKeyword == nil
              ? "选中搜索结果后，会自动填写对应的媒体编号。" : "请更换名称后重新搜索。"
          )
        } else {
          ScrollView {
            LazyVGrid(
              columns: [
                GridItem(.fixed(500), spacing: 36),
                GridItem(.fixed(500)),
              ],
              spacing: 36
            ) {
              ForEach(viewModel.items) { item in
                if let mediaId = ManualMediaSelection.mediaId(
                  for: item, source: viewModel.source
                ) {
                  BestResultCard(
                    title: ManualMediaSelection.displayTitle(for: item),
                    type: item.displayTypeText,
                    posterUrl: item.imageURLs.poster,
                    posterFallbackUrl: item.imageURLs.posterFallback,
                    subtitle: [item.type, item.overview]
                      .compactMap { $0?.isEmpty == false ? $0 : nil }
                      .joined(separator: " · ")
                  ) {
                    onSelect(mediaId, item)
                  }
                }
              }
            }
          }
          .contentMargins(.vertical, 28, for: .scrollContent)
        }
      }
      .padding(.top, 40)
    }
    .frame(width: 1092, height: 820)
    .onAppear {
      viewModel.presentationDidAppear()
    }
    .cancelOnExternalNavigation()
    .onDisappear {
      searchTask?.cancel()
      searchTask = nil
      viewModel.presentationDidDisappear()
    }
  }

}
