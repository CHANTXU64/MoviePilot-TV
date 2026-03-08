import Combine
import SwiftUI

struct ExploreView: View {
  @StateObject private var viewModel = ExploreViewModel()
  @State private var path = NavigationPath()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let paginator = viewModel.paginator {
          // 主内容区：媒体网格
          MediaGridView(
            items: paginator.items,
            isLoading: paginator.isFirstLoading,
            isLoadingMore: paginator.isLoadingMore,
            onLoadMore: { itemId in
              Task { await paginator.loadMore(itemId) }
            },
            navigationPath: $path,
            header: {
              VStack(alignment: .leading, spacing: 20) {
                // 第一行：数据源选择器
                SourcePickerView(selectedSource: $viewModel.selectedSource)
                  .onChange(of: viewModel.selectedSource) { _, _ in
                    viewModel.onSourceChanged()
                  }

                // 第二行：筛选器（根据数据源动态显示）
                FilterPickersView(viewModel: viewModel)
                  .onChange(of: viewModel.selectedType) { _, _ in
                    viewModel.onTypeChanged()
                  }
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
        } else {
          // 在 Paginator 初始化完成前显示加载指示器
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $path)
  }
}

// MARK: - 数据源选择器
struct SourcePickerView: View {
  @Binding var selectedSource: DiscoverSource

  var body: some View {
    Picker("数据源", selection: $selectedSource) {
      ForEach(DiscoverSource.allCases) { source in
        Text(source.rawValue).tag(source)
      }
    }
    .pickerStyle(.segmented)
  }
}

// MARK: - 筛选器视图
struct FilterPickersView: View {
  @ObservedObject var viewModel: ExploreViewModel

  // 记录上次聚焦的 Picker 索引（每个数据源独立）
  @State private var tmdbFocusedIndex: Int = 0
  @State private var doubanFocusedIndex: Int = 0
  @State private var bangumiFocusedIndex: Int = 0

  // Focus redirectors
  @FocusState private var focusedPickerIndex: Int?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

  private var currentFocusIndex: Int {
    switch viewModel.selectedSource {
    case .themoviedb: tmdbFocusedIndex
    case .douban: doubanFocusedIndex
    case .bangumi: bangumiFocusedIndex
    }
  }

  private func setCurrentFocusIndex(_ index: Int) {
    switch viewModel.selectedSource {
    case .themoviedb: tmdbFocusedIndex = index
    case .douban: doubanFocusedIndex = index
    case .bangumi: bangumiFocusedIndex = index
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 顶部焦点重定向器 - 捕获来自上方数据源选择器的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedPickerIndex == nil)
        .focused($isTopRedirectorFocused)
        .onChange(of: isTopRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedPickerIndex = currentFocusIndex
            isTopRedirectorFocused = false
          }
        }

      HStack(spacing: 20) {
        switch viewModel.selectedSource {
        case .themoviedb:
          tmdbFilters
            .foregroundColor(.primary)
        case .douban:
          doubanFilters
            .foregroundColor(.primary)
        case .bangumi:
          bangumiFilters
            .foregroundColor(.primary)
        }
      }

      // 底部焦点重定向器 - 捕获来自下方媒体网格的焦点
      Color.clear
        .frame(height: 1)
        .focusable(focusedPickerIndex == nil)
        .focused($isBottomRedirectorFocused)
        .onChange(of: isBottomRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedPickerIndex = currentFocusIndex
            isBottomRedirectorFocused = false
          }
        }
    }
    .onChange(of: focusedPickerIndex) { _, newIndex in
      if let newIndex {
        setCurrentFocusIndex(newIndex)
      }
    }
  }

  // MARK: - TheMovieDb 筛选器
  @ViewBuilder
  private var tmdbFilters: some View {
    // 类型
    Picker("类型", selection: $viewModel.selectedType) {
      ForEach(DiscoverMediaType.allCases) { type in
        Text("类型：" + type.rawValue).tag(type)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    // 排序
    Picker("排序", selection: $viewModel.tmdbSortBy) {
      // Text("排序：全部").tag("popularity.desc")
      ForEach(viewModel.currentSortDict, id: \.key) { item in
        Text("排序：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    // 风格
    Picker("风格", selection: $viewModel.tmdbGenre) {
      Text("风格：全部").tag("")
      ForEach(viewModel.currentGenreDict, id: \.key) { item in
        Text("风格：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)

    // 语言
    Picker("语言", selection: $viewModel.tmdbLanguage) {
      Text("语言：全部").tag("")
      ForEach(ExploreViewModel.tmdbLanguageDict, id: \.key) { item in
        Text("语言：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 3)

    // 评分
    Picker("评分", selection: $viewModel.tmdbVoteAverage) {
      Text("评分：不限").tag(0)
      ForEach([5, 6, 7, 8, 9], id: \.self) { rating in
        Text("评分：\(rating)分以上").tag(rating)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 4)
  }

  // MARK: - 豆瓣筛选器
  @ViewBuilder
  private var doubanFilters: some View {
    // 类型
    Picker("类型", selection: $viewModel.selectedType) {
      ForEach(DiscoverMediaType.allCases) { type in
        Text("类型：" + type.rawValue).tag(type)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    // 排序
    Picker("排序", selection: $viewModel.doubanSort) {
      ForEach(ExploreViewModel.doubanSortDict, id: \.key) { item in
        Text("排序：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    // 风格
    Picker("风格", selection: $viewModel.doubanCategory) {
      Text("风格：全部").tag("")
      ForEach(ExploreViewModel.doubanCategoryDict, id: \.key) { item in
        Text("风格：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)

    // 地区
    Picker("地区", selection: $viewModel.doubanZone) {
      Text("地区：全部").tag("")
      ForEach(ExploreViewModel.doubanZoneDict, id: \.key) { item in
        Text("地区：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 3)

    // 年代
    Picker("年代", selection: $viewModel.doubanYear) {
      Text("年代：全部").tag("")
      ForEach(ExploreViewModel.doubanYearDict, id: \.key) { item in
        Text("年代：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 4)
  }

  // MARK: - Bangumi 筛选器
  @ViewBuilder
  private var bangumiFilters: some View {
    // 分类
    Picker("分类", selection: $viewModel.bangumiCat) {
      Text("分类：全部").tag("")
      ForEach(ExploreViewModel.bangumiCatDict, id: \.key) { item in
        Text("分类：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    // 排序
    Picker("排序", selection: $viewModel.bangumiSort) {
      ForEach(ExploreViewModel.bangumiSortDict, id: \.key) { item in
        Text("排序：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    // 年份
    Picker("年份", selection: $viewModel.bangumiYear) {
      Text("年份：全部").tag("")
      ForEach(ExploreViewModel.bangumiYearDict, id: \.key) { item in
        Text("年份：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)
  }
}
