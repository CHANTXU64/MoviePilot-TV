import SwiftUI

struct RecommendView: View {
  @StateObject private var viewModel = RecommendViewModel()
  @State private var path = NavigationPath()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  var body: some View {
    NavigationStack(path: $path) {
      // 主内容槽（网格布局）
      MediaGridView(
        items: viewModel.items,
        isLoading: viewModel.isLoading,
        isLoadingMore: viewModel.isLoadingMore,
        onLoadMore: {
          Task {
            await viewModel.loadMoreData()
          }
        },
        navigationPath: $path,
        header: {
          VStack(spacing: 20) {
            // 分类选择器 - 使用 Picker，带 Icon
            CategoryPickerView(selectedCategory: $viewModel.selectedCategory)
              .onChange(of: viewModel.selectedCategory) { _, _ in
                viewModel.onCategoryChanged()
              }

            // 货架选择器 - 横向滚动 chips
            ShelfPicker(
              shelves: viewModel.filteredShelves,
              selectedShelf: $viewModel.selectedShelf
            )
          }
        },
        contextMenu: { item in
          MediaContextMenuItems(
            item: item,
            navigationPath: $path,
            subscriptionHandler: subscriptionHandler
          )
        }
      )
      .onChange(of: viewModel.selectedShelf) { _, _ in
        Task {
          await viewModel.loadShelfData()
        }
      }
      .task {
        if viewModel.items.isEmpty {
          await viewModel.loadShelfData()
        }
      }
      .navigationDestination(for: MediaInfo.self) { media in
        MediaDetailContainerView(media: media, navigationPath: $path)
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(person: person, navigationPath: $path)
      }
      .navigationDestination(for: ResourceSearchRequest.self) { request in
        ResourceResultView(request: request)
      }
      .navigationDestination(for: SubscribeSeasonRequest.self) { request in
        SubscribeSeasonView(mediaInfo: request.mediaInfo, initialSeason: request.initialSeason)
      }
      .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $path)
    }
  }
}

// MARK: - 分类选择器（使用 Picker，带 Icon）
struct CategoryPickerView: View {
  @Binding var selectedCategory: RecommendCategory

  var body: some View {
    Picker("分类", selection: $selectedCategory) {
      ForEach(RecommendCategory.allCases) { category in
        Label(category.rawValue, systemImage: category.icon)
          .tag(category)
      }
    }
    .pickerStyle(.segmented)
  }
}
