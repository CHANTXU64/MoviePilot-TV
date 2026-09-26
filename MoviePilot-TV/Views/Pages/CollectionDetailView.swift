import Kingfisher
import SwiftUI

struct CollectionDetailView: View {
  let title: String
  let collectionId: Int
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let allowsRequests: Bool
  let previewPosterURL: URL?
  let onInitialContentReady: () -> Void

  @StateObject private var viewModel: CollectionDetailViewModel
  @State private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  init(
    title: String, collectionId: Int, imageLifecycle: PageImageLifecycle,
    allowsRequests: Bool = true, previewPosterURL: URL? = nil,
    preparedItems: [MediaInfo]? = nil,
    onInitialContentReady: @escaping () -> Void = {}
  ) {
    self.title = title
    self.collectionId = collectionId
    self.imageLifecycle = imageLifecycle
    self.allowsRequests = allowsRequests
    self.previewPosterURL = previewPosterURL
    self.onInitialContentReady = onInitialContentReady
    self._viewModel = StateObject(
      wrappedValue: CollectionDetailViewModel(
        collectionId: collectionId, title: title, preparedItems: preparedItems
      ))
  }

  var body: some View {
    MediaGridView(
      imageLifecycle: imageLifecycle,
      listIdentity: viewModel.paginator.listIdentity,
      items: viewModel.paginator.items,
      isLoading: viewModel.paginator.isFirstLoading,
      isLoadingMore: viewModel.paginator.isLoadingMore,
      onLoadMore: { currentItem in
        guard allowsRequests else { return }
        Task {
          await viewModel.paginator.loadMore(currentItem)
        }
      },
      loadsImages: allowsRequests,
      header: {
        HStack(spacing: 32) {
          if let previewPosterURL {
            PageManagedImage(
              url: previewPosterURL,
              processor: DownsamplingImageProcessor(size: CGSize(width: 120, height: 180)),
              isEnabled: true,
              participatesInPageLifecycle: true,
              skipsMemoryCache: true,
              loadsDiskFileSynchronously: true
            )
              .frame(width: 120, height: 180)
          }
          Text(title)
            .font(.largeTitle.bold())
            .foregroundColor(.secondary)
        }
      },
      contextMenu: { item in
        MediaContextMenuItems(
          item: item,
          subscriptionHandler: subscriptionHandler
        )
      }
    )
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      subscriptionHandler = SubscriptionHandler()
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .disabled(!allowsRequests)
    .task(id: allowsRequests) {
      guard allowsRequests else { return }
      await viewModel.loadInitialData()
      guard !Task.isCancelled else { return }
      onInitialContentReady()
    }
  }
}
