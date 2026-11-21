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
      if let search = viewModel.pagedSearch {
        PagedResourceResultsView(search: search, overrideMediaInfo: mediaInfo, onCancel: {
          viewModel.cancelSearch()
          dismiss()
        }) {
          if mediaInfo != nil { Text(title).font(.title2.bold()).foregroundColor(.secondary) }
        }
      } else if viewModel.isLoading {
        VStack(spacing: 20) {
          ProgressView(viewModel.searchProgressText)
          if viewModel.searchProgress > 0 {
            ProgressView(value: viewModel.searchProgress, total: 100)
              .progressViewStyle(.linear)
              .frame(width: 360)
          }
          Button("取消") {
            viewModel.cancelSearch()
            dismiss()
          }
          .claimsInitialFocus()
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
                .font(.title2.bold())
                .foregroundColor(.secondary)
            }
          }
        )
      }
    }
    .background {
      SearchResultBackdrop(url: mediaInfo?.imageURLs.backdrop)
    }
    // 详情页搜索菜单直接打开本页时，焦点不能留在 Tab 栏上：由当前显示的「取消」「重新搜索」等认领首个焦点。
    .providesInitialFocusClaim()
    .task {
      await viewModel.search()
    }
    .onDisappear {
      viewModel.cancelInFlightSearch()
    }
  }
}
