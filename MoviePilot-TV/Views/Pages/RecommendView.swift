import SwiftUI

struct RecommendView: View {
  private let isSelected: Bool
  @StateObject private var viewModel = RecommendViewModel()
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  init(isSelected: Bool) {
    self.isSelected = isSelected
  }

  var body: some View {
    NavigationStack(path: $navigationCoordinator.path) {
      Group {
        if let paginator = viewModel.paginator {
          // 主内容槽（网格布局）
          MediaGridView(
            imageLifecycle: navigationCoordinator.rootLifecycle,
            listIdentity: paginator.listIdentity,
            items: paginator.items,
            isLoading: paginator.isFirstLoading,
            isLoadingMore: paginator.isLoadingMore,
            onLoadMore: { newId in
              Task {
                await paginator.loadMore(newId)
              }
            },
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
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .onAppear {
      updateStackForeground()
      viewModel.reloadLocalConfig()
    }
    .onChange(of: isSelected) { _, _ in updateStackForeground() }
    .onChange(of: scenePhase) { _, _ in updateStackForeground() }
    .task(id: isSelected) {
      guard isSelected else { return }
      await viewModel.refreshSources()
    }
  }

  private func updateStackForeground() {
    navigationCoordinator.setStackPresentation(isSelected: isSelected, scenePhase: scenePhase)
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
