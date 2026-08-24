import Kingfisher
import SwiftUI

struct ResourceResultView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var apiService = APIService.shared
  @StateObject private var viewModel: ResourceResultViewModel
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let title: String
  let mediaInfo: MediaInfo?

  init(request: ResourceSearchRequest, imageLifecycle: PageImageLifecycle) {
    self.title = request.title ?? "资源搜索"
    self.mediaInfo = request.mediaInfo
    self.imageLifecycle = imageLifecycle
    _viewModel = StateObject(
      wrappedValue: ResourceResultViewModel(
        keyword: request.keyword,
        type: request.type,
        area: request.area,
        title: request.title,
        year: request.year,
        season: request.season,
        sites: request.sites
      )
    )
  }

  var body: some View {
    Group {
      if viewModel.isLoading {
        VStack(spacing: 20) {
          ProgressView(viewModel.searchProgressText)
          if viewModel.searchProgress > 0 {
            ProgressView(value: viewModel.searchProgress, total: 100)
              .progressViewStyle(.linear)
              .frame(width: 300)
          }
          Button("取消") {
            viewModel.cancelSearch()
            dismiss()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        TorrentsResultView(
          result: viewModel.results,
          overrideMediaInfo: mediaInfo,
          emptyDescription: viewModel.errorMessage,
          header: {
            if mediaInfo != nil {
              Text(title)
                .font(.largeTitle.bold())
                .foregroundColor(.secondary)
            }
          }
        )
      }
    }
    .background {
      PageManagedImage(
        url: mediaInfo?.imageURLs.backdrop,
        processor: BlurImageProcessor(blurRadius: 60)
          |> ResizingImageProcessor(
            referenceSize: UIScreen.main.bounds.size,
            mode: .aspectFill
          ),
        isEnabled: true,
        role: .activePage,
        participatesInPageLifecycle: true,
        skipsMemoryCache: true,
        fadeDuration: 0
      )
      .opacity(0.3)
      .ignoresSafeArea()
    }
    .task {
      await viewModel.search()
    }
    .onDisappear {
      viewModel.cancelInFlightSearch()
    }
  }
}
