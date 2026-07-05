import Kingfisher
import SwiftUI

struct ResourceResultView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ResourceResultViewModel
  let title: String
  let mediaInfo: MediaInfo?

  #if DEBUG
  private let searchesOnAppear: Bool
  private let torrentsPresentation: TorrentsResultUIPreviewPresentation?
  #endif

  init(request: ResourceSearchRequest) {
    self.title = request.title ?? "资源搜索"
    self.mediaInfo = request.mediaInfo
    #if DEBUG
    self.searchesOnAppear = true
    self.torrentsPresentation = nil
    #endif
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

  #if DEBUG
  init(
    title: String,
    mediaInfo: MediaInfo?,
    previewViewModel: ResourceResultViewModel,
    torrentsPresentation: TorrentsResultUIPreviewPresentation? = nil
  ) {
    self.title = title
    self.mediaInfo = mediaInfo
    self.searchesOnAppear = false
    self.torrentsPresentation = torrentsPresentation
    _viewModel = StateObject(wrappedValue: previewViewModel)
  }
  #endif

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
        #if DEBUG
        TorrentsResultView(
          result: viewModel.results,
          overrideMediaInfo: mediaInfo,
          uiPreviewPresentation: torrentsPresentation,
          header: { resultHeader }
        )
        #else
        TorrentsResultView(
          result: viewModel.results,
          overrideMediaInfo: mediaInfo,
          header: { resultHeader }
        )
        #endif
      }
    }
    .background {
      if let mediaInfo = mediaInfo, let url = mediaInfo.imageURLs.backdrop {
        KFImage(url)
          .requestModifier(AnyModifier.cookieModifier)
          .placeholder {
            EmptyView()
          }
          .setProcessor(BlurImageProcessor(blurRadius: 60))
          .resizing(
            referenceSize: UIScreen.main.bounds.size,
            mode: .aspectFill
          )
          .resizable()
          .aspectRatio(contentMode: .fill)
          .opacity(0.3)
          .ignoresSafeArea()
      }
    }
    .task {
      #if DEBUG
      guard searchesOnAppear else { return }
      #endif
      await viewModel.search()
    }
    .onDisappear {
      #if DEBUG
      guard searchesOnAppear else { return }
      #endif
      viewModel.cancelInFlightSearch()
    }
  }

  @ViewBuilder
  private var resultHeader: some View {
    if mediaInfo != nil {
      Text(title)
        .font(.largeTitle.bold())
        .foregroundColor(.secondary)
    }
  }
}
