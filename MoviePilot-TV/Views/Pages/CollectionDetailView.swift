import SwiftUI

struct CollectionDetailView: View {
  let title: String
  let collectionId: Int
  @ObservedObject var imageLifecycle: PageImageLifecycle

  @StateObject private var viewModel: CollectionDetailViewModel
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  init(title: String, collectionId: Int, imageLifecycle: PageImageLifecycle) {
    self.title = title
    self.collectionId = collectionId
    self.imageLifecycle = imageLifecycle
    self._viewModel = StateObject(
      wrappedValue: CollectionDetailViewModel(collectionId: collectionId, title: title))
  }

  var body: some View {
    MediaGridView(
      imageLifecycle: imageLifecycle,
      items: viewModel.paginator.items,
      isLoading: viewModel.paginator.isFirstLoading,
      isLoadingMore: viewModel.paginator.isLoadingMore,
      onLoadMore: { currentItem in
        Task {
          await viewModel.paginator.loadMore(currentItem)
        }
      },
      header: {
        Text(title)
          .font(.largeTitle.bold())
          .foregroundColor(.secondary)
      },
      contextMenu: { item in
        MediaContextMenuItems(
          item: item,
          subscriptionHandler: subscriptionHandler
        )
      }
    )
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .task {
      await viewModel.loadInitialData()
    }
  }
}
