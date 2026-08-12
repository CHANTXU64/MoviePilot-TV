import SwiftUI

struct RecommendView: View {
  @StateObject private var viewModel = RecommendViewModel()
  @State private var path = NavigationPath()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let paginator = viewModel.paginator {
          // 主内容槽（网格布局）
          MediaGridView(
            items: paginator.items,
            isLoading: paginator.isFirstLoading,
            isLoadingMore: paginator.isLoadingMore,
            onLoadMore: { newId in
              Task {
                await paginator.loadMore(newId)
              }
            },
            navigationPath: $path,
            header: {
              VStack(spacing: 20) {
                // 分类选择器 - 使用 Picker，带 Icon
                CategoryPickerView(
                  categories: viewModel.visibleCategories,
                  selectedCategory: $viewModel.selectedCategory
                )
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
        } else if viewModel.filteredShelves.isEmpty {
          VStack(spacing: 24) {
            if !viewModel.visibleCategories.isEmpty {
              CategoryPickerView(
                categories: viewModel.visibleCategories,
                selectedCategory: $viewModel.selectedCategory
              )
              .onChange(of: viewModel.selectedCategory) { _, _ in
                viewModel.onCategoryChanged()
              }
            }
            Text("没有已启用的推荐货架")
              .font(.headline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // 在 Paginator 初始化完成前显示加载指示器
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationDestination(for: MediaInfo.self) { media in
        if let collectionId = media.collection_id {
          CollectionDetailView(
            title: media.title ?? "合集详情",
            collectionId: collectionId,
            navigationPath: $path
          )
        } else {
          MediaDetailContainerView(media: media, navigationPath: $path)
        }
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(person: person, navigationPath: $path)
      }
      .navigationDestination(for: ResourceSearchRequest.self) { request in
        ResourceResultView(request: request)
      }
      .navigationDestination(for: SubscribeSeasonRequest.self) { request in
        SubscribeSeasonView(
          mediaInfo: request.mediaInfo,
          initialSeason: request.initialSeason,
          initialEpisodeGroup: request.initialEpisodeGroup
        )
      }
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $path)
    .onAppear {
      viewModel.reloadLocalConfig()
    }
    .task {
      await viewModel.refreshSources()
    }
  }
}

// MARK: - 分类选择器（使用 Picker，带 Icon）
struct CategoryPickerView: View {
  let categories: [RecommendCategory]
  @Binding var selectedCategory: RecommendCategory

  var body: some View {
    Picker("分类", selection: $selectedCategory) {
      ForEach(categories) { category in
        Label(category.rawValue, systemImage: category.icon)
          .tag(category)
      }
    }
    .pickerStyle(.segmented)
  }
}
