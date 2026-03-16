import SwiftUI

struct CollectionDetailView: View {
  let title: String
  let collectionId: Int
  @Binding var navigationPath: NavigationPath

  @StateObject private var viewModel: CollectionDetailViewModel
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  init(title: String, collectionId: Int, navigationPath: Binding<NavigationPath>) {
    self.title = title
    self.collectionId = collectionId
    self._navigationPath = navigationPath
    self._viewModel = StateObject(
      wrappedValue: CollectionDetailViewModel(collectionId: collectionId, title: title))
  }

  var body: some View {
    MediaGridView(
      items: viewModel.paginator.items,
      isLoading: viewModel.paginator.isFirstLoading,
      isLoadingMore: viewModel.paginator.isLoadingMore,
      onLoadMore: { currentItem in
        Task {
          await viewModel.paginator.loadMore(currentItem)
        }
      },
      navigationPath: $navigationPath,
      header: {
        Text(title)
          .font(.largeTitle.bold())
          .foregroundColor(.secondary)
      },
      contextMenu: { item in
        MediaContextMenuItems(
          item: item,
          navigationPath: $navigationPath,
          subscriptionHandler: subscriptionHandler
        )
      }
    )
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $navigationPath)
    .task {
      await viewModel.loadInitialData()
    }
  }
}
