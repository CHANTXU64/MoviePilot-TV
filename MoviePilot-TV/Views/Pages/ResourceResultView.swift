import Kingfisher
import SwiftUI

struct ResourceResultView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ResourceResultViewModel
  let title: String
  let mediaInfo: MediaInfo?

  init(request: ResourceSearchRequest) {
    self.title = request.title ?? "资源搜索"
    self.mediaInfo = request.mediaInfo
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
    ZStack {
      // 背景图片
      if mediaInfo != nil {
        if let url = mediaInfo!.imageURLs.backdrop {
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

      // 内容
      VStack(spacing: 0) {
        if viewModel.isLoading {
          VStack(spacing: 20) {
            ProgressView(viewModel.searchProgressText)
            
            if viewModel.searchProgress > 0 {
              ProgressView(value: viewModel.searchProgress, total: 100)
                .progressViewStyle(.linear)
                .frame(width: 300)
            }
            
            Button("取消") {
              dismiss()
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          TorrentsResultView(
            result: viewModel.results,
            overrideMediaInfo: mediaInfo,
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
      .padding(.top, 63)
    }
    .task {
      await viewModel.search()
    }
  }
}
