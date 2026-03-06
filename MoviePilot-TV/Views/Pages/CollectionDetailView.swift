import SwiftUI

struct CollectionDetailView: View {
  let title: String
  let collectionId: Int
  @Binding var navigationPath: NavigationPath

  @State private var items: [MediaInfo] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  var body: some View {
    VStack {
      if isLoading {
        ProgressView()
      } else if let error = errorMessage {
        Text(error).foregroundColor(.secondary)
      } else if items.isEmpty {
        EmptyDataView(
          title: "合集内容为空",
          systemImage: "rectangle.stack",
          actionTitle: "返回",
          action: {
            if !navigationPath.isEmpty {
              navigationPath.removeLast()
            }
          }
        )
      } else {
        MediaGridView(
          items: items,
          isLoading: false,
          isLoadingMore: false,
          onLoadMore: {},
          navigationPath: $navigationPath,
          autoFocusFirstItem: true,
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
      }
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $navigationPath)
    .task {
      await loadCollection()
    }
  }

  private func loadCollection() async {
    isLoading = true
    errorMessage = nil
    do {
      items = try await APIService.shared.fetchCollection(collectionId: collectionId)
    } catch {
      errorMessage = "加载合集失败: \(error.localizedDescription)"
    }
    isLoading = false
  }
}
