import Combine
import SwiftUI

enum ManualMediaSelection {
  static func mediaId(for media: MediaInfo, source: MediaSearchSource) -> String? {
    let nativeId: String? =
      switch source {
      case .themoviedb: media.tmdb_id.map(String.init)
      case .douban: media.douban_id
      case .bangumi: media.bangumi_id.map(String.init)
      case .anilist: media.anilist_id.map(String.init)
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
  @Published var keyword = ""
  @Published var items: [MediaInfo] = []
  @Published var isLoading = false

  let source: MediaSearchSource
  private let apiService: APIService
  private var searchRevision = 0

  init(source: MediaSearchSource, apiService: APIService = .shared) {
    self.source = source
    self.apiService = apiService
  }

  func search() async {
    searchRevision &+= 1
    let revision = searchRevision
    let title = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
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
      Logger.error("Failed to search manual media ID: \(error)")
    }
  }
}

struct ManualMediaSearchSheet: View {
  @StateObject private var viewModel: ManualMediaSearchViewModel

  let onSelect: (String, MediaInfo) -> Void

  init(
    source: MediaSearchSource,
    onSelect: @escaping (String, MediaInfo) -> Void
  ) {
    _viewModel = StateObject(wrappedValue: ManualMediaSearchViewModel(source: source))
    self.onSelect = onSelect
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text("查询 \(viewModel.source.title) ID")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 28)

        HStack(spacing: 20) {
          SheetTextField(
            title: "媒体标题",
            placeholder: "输入媒体标题后搜索",
            text: $viewModel.keyword
          )
          .labelsHidden()

          Button {
            Task { await viewModel.search() }
          } label: {
            Label("搜索", systemImage: "magnifyingglass")
          }
          .disabled(viewModel.isLoading)
        }
        .focusSection()
        .padding(.horizontal, 28)

        if viewModel.isLoading {
          ProgressView("搜索中…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
          EmptyDataView(title: "输入标题搜索媒体")
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
                    title: displayTitle(for: item),
                    type: item.type,
                    posterUrl: item.imageURLs.poster,
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
  }

  private func displayTitle(for item: MediaInfo) -> String {
    guard let year = item.year, !year.isEmpty else { return item.title ?? "" }
    return "\(item.title ?? "")（\(year)）"
  }
}
