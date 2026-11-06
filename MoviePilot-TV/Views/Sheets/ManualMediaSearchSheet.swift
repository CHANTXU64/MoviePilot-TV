import Combine
import SwiftUI

enum ManualMediaSelection {
  static func mediaId(for media: MediaInfo, source: MediaSearchSource) -> String? {
    let nativeId: String?
    switch source {
    case .themoviedb: nativeId = MediaIdentifier.validNumericIdentifier(media.tmdb_id).map(String.init)
    case .douban: nativeId = media.douban_id
    case .bangumi: nativeId = MediaIdentifier.validNumericIdentifier(media.bangumi_id).map(String.init)
    case .anilist: nativeId = MediaIdentifier.validNumericIdentifier(media.anilist_id).map(String.init)
    default:
      // 其余来源与 Web MediaIdSelector 一致：只认该来源返回的条目及其 media_id。
      guard media.source.flatMap(MediaSearchSource.init(rawValue:)) == source else { return nil }
      nativeId = nil
    }
    for candidate in [nativeId, media.media_id] {
      let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
      if normalized?.isEmpty == false {
        return normalized
      }
    }
    return nil
  }

  static func typeName(for media: MediaInfo) -> String? {
    switch media.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "电影", "movie": "电影"
    case "电视剧", "tv", "series": "电视剧"
    default: nil
    }
  }
}

@MainActor
final class ManualMediaSearchViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 最近一次搜索的结果状态，面板据此显示提示；有结果时直接显示结果。
  enum Outcome: Equatable {
    /// 还没搜索，或输入为空。
    case idle
    case noResults(keyword: String)
    case failed
  }

  @Published var keyword = ""
  @Published var items: [MediaInfo] = []
  @Published var isLoading = false
  @Published private(set) var outcome: Outcome = .idle

  let source: MediaSearchSource
  private let apiService: APIService
  private var searchRevision = 0
  private let dismissalReleaseScheduler = PresentationReleaseScheduler()

  init(source: MediaSearchSource, apiService: APIService = .shared) {
    self.source = source
    self.apiService = apiService
  }

  func search() async {
    searchRevision &+= 1
    let revision = searchRevision
    let title = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    items = []
    outcome = .idle
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
      outcome = results.isEmpty ? .noResults(keyword: title) : .idle
    } catch is CancellationError {
      return
    } catch {
      guard searchRevision == revision else { return }
      Logger.error("Failed to search manual media ID: \(error)")
      // 失败不能看起来像「没有结果」，面板会显示原因和「重试」。
      outcome = .failed
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
      outcome = .idle
    }
  }
}

struct ManualMediaSearchSheet: View {
  @ObservedObject private var apiService = APIService.shared
  @StateObject private var viewModel: ManualMediaSearchViewModel
  @State private var searchTask: Task<Void, Never>?
  /// 上一次搜索失败、正在重试：继续显示失败提示（「重试中」），不切到「正在搜索…」。
  @State private var isRetryingAfterFailure = false
  @FocusState private var isSearchFocused: Bool

  let onSelect: (String, MediaInfo) -> Void

  init(
    source: MediaSearchSource,
    onSelect: @escaping (String, MediaInfo) -> Void
  ) {
    _viewModel = StateObject(wrappedValue: ManualMediaSearchViewModel(source: source))
    self.onSelect = onSelect
  }

  /// 查询媒体 ID：只在添加下载、重新整理、下载字幕的媒体 ID 旁按🔍打开，选中结果后自动填入。
  ///
  /// 不放大标题：顶部一行是整行的「片名」输入框和「搜索」，下面是结果；还没搜、搜索中、
  /// 没有结果时在结果区居中显示一行说明，搜索失败用统一的出错提示和「重试」。尺寸固定，状态切换时不跳。
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        HStack(spacing: 20) {
          SheetInlineTextField(title: "片名", text: $viewModel.keyword)

          SheetActionButton(
            title: "搜索", systemImage: AppSymbol.search, loadingTitle: "搜索中",
            isLoading: viewModel.isLoading, focus: $isSearchFocused, action: startSearch
          )
          .frame(width: 240)
        }
        .focusSection()
        .padding(.horizontal, 56)

        if viewModel.items.isEmpty {
          statusArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 56)
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
                  // 与搜索页「最佳结果」同一张卡片、同一种写法：片名，下面是类型 · 年份 · 来源。
                  BestResultCard(
                    title: item.title ?? "",
                    type: item.displayTypeText,
                    posterUrl: item.imageURLs.poster,
                    posterFallbackUrl: item.imageURLs.posterFallback,
                    subtitle: BestResultCard.mediaSubtitle(for: item)
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
      // 边距与其他面板一致（左右 56、上 52）；两列 500 宽的结果卡片加间距 36 正好放下。
      .padding(.top, 52)
    }
    .frame(width: 1148, height: 820)
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

  /// 搜索中按钮保持可聚焦、按了不响应（tvOS 上聚焦元素变禁用会让焦点跳走），防重入由 guard 完成。
  private func startSearch() {
    guard !viewModel.isLoading else { return }
    isRetryingAfterFailure = viewModel.outcome == .failed
    searchTask?.cancel()
    searchTask = Task { await viewModel.search() }
  }

  /// 没有结果可显示时的说明：还没搜、搜索中、没找到用一行居中小字；搜索失败用统一的出错提示。
  private var statusArea: some View {
    VStack(spacing: 0) {
      // 重试期间保留提示和「重试」（显示「重试中」）；成功后焦点回到「搜索」。
      SheetRetryingMessage(
        message: viewModel.outcome == .failed ? "搜索失败，请稍后重试。" : nil,
        isBusy: viewModel.isLoading,
        retry: startSearch,
        spacingEdges: [], spacing: 0
      ) {
        isSearchFocused = true
      }
      .frame(maxWidth: 600)

      if viewModel.outcome != .failed, !(viewModel.isLoading && isRetryingAfterFailure) {
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .onChange(of: viewModel.isLoading) { _, isLoading in
      if !isLoading { isRetryingAfterFailure = false }
    }
  }

  private var statusText: String {
    if viewModel.isLoading { return "正在搜索…" }
    if case .noResults(let keyword) = viewModel.outcome {
      return "没有找到「\(keyword)」，请换个片名再试。"
    }
    return "输入片名后搜索，选择结果即可填入 \(viewModel.source.title) ID。"
  }

}

/// 手动填写所选来源的媒体 ID；放大镜按标题查询后回填。整理、添加下载与字幕下载共用。
struct ManualMediaIdField: View {
  let source: MediaSearchSource
  var sourceTitle: String? = nil
  /// 放在设置面板里时用整行输入框，项名在框内；格式错误由面板统一提示。
  var isInline = false
  @Binding var mediaId: String
  var placeholder = "自动判断"
  var onSelect: (String, MediaInfo) -> Void
  @State private var showMediaSearch = false

  var body: some View {
    Group {
      HStack(spacing: 20) {
        if isInline {
          SheetInlineTextField(title: "\(sourceTitle ?? source.title) ID", text: $mediaId)
        } else {
          SheetTextField(
            title: "\(sourceTitle ?? source.title) ID",
            placeholder: placeholder,
            text: $mediaId
          )
        }

        Button {
          showMediaSearch = true
        } label: {
          Image(systemName: AppSymbol.search)
        }
        // 只有图标的按钮用正圆，系统默认是胶囊。
        .buttonBorderShape(.circle)
        .accessibilityLabel("搜索媒体")
      }
      // 设置面板里由面板统一显示出错原因，不在设置列里插行。
      if !isInline, !source.isValidManualId(mediaId) {
        Text(MediaSearchSource.invalidManualIdMessage)
          .foregroundStyle(.red)
      }
    }
    .sheet(isPresented: $showMediaSearch) {
      ManualMediaSearchSheet(source: source) { mediaId, media in
        showMediaSearch = false
        onSelect(mediaId, media)
      }
    }
  }
}
