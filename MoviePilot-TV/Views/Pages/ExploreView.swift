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
            header: { headerView },
            contextMenu: { item in
              MediaContextMenuItems(
                item: item,
                navigationPath: $path,
                subscriptionHandler: subscriptionHandler
              )
            },
            onShareTapped: { share in
              guard APIService.shared.canAccess(.subscribe) else { return }
              subscriptionHandler.forkSheetRequest = share
            }
          )
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
    .sheet(item: $subscriptionHandler.forkSheetRequest) { share in
      ForkSubscribeSheet(
        share: share,
        onFork: { newSubId in
          Task {
            await subscriptionHandler.fetchSubscriptionAndShowEditor(subId: newSubId)
          }
        },
        subscriptionHandler: subscriptionHandler
      )
    }
    .task {
      await viewModel.refreshSources()
    }
  }

  private var headerView: some View {
    VStack(alignment: .leading, spacing: 20) {
      // 第一行：数据源选择器
      SourcePickerView(
        selectedSource: $viewModel.selectedSource,
        sources: viewModel.availableSources
      )
      .onChange(of: viewModel.selectedSource) { previousSource, _ in
        viewModel.onSourceChanged(from: previousSource)
      }

      // 第二行：筛选器（根据数据源动态显示）
      FilterPickersView(viewModel: viewModel)
        .onChange(of: viewModel.selectedType) { _, _ in
          viewModel.onTypeChanged()
        }
    }
  }
}

// MARK: - 数据源选择器
struct SourcePickerView: View {
  @Binding var selectedSource: DiscoverSource
  let sources: [DiscoverSource]

  var body: some View {
    Picker("数据源", selection: $selectedSource) {
      ForEach(sources) { source in
        Text(source.title).tag(source)
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
  @State private var anilistFocusedIndex: Int = 0
  @State private var popularFocusedIndex: Int = 0
  @State private var shareFocusedIndex: Int = 0

  // Focus redirectors
  @FocusState private var focusedPickerIndex: Int?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

  private var hasFocusableFilters: Bool {
    if case .custom = viewModel.selectedSource {
      return !viewModel.pluginFilterControls.isEmpty
    }
    return true
  }

  private var currentFocusIndex: Int {
    switch viewModel.selectedSource {
    case .themoviedb: tmdbFocusedIndex
    case .douban: doubanFocusedIndex
    case .bangumi: bangumiFocusedIndex
    case .anilist: anilistFocusedIndex
    case .popular: popularFocusedIndex
    case .subscriptionShare: shareFocusedIndex
    case .custom: 0
    }
  }

  private func setCurrentFocusIndex(_ index: Int) {
    switch viewModel.selectedSource {
    case .themoviedb: tmdbFocusedIndex = index
    case .douban: doubanFocusedIndex = index
    case .bangumi: bangumiFocusedIndex = index
    case .anilist: anilistFocusedIndex = index
    case .popular: popularFocusedIndex = index
    case .subscriptionShare: shareFocusedIndex = index
    case .custom: break
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 顶部焦点重定向器 - 捕获来自上方数据源选择器的焦点
      Color.clear
        .frame(height: 1)
        .focusable(hasFocusableFilters && focusedPickerIndex == nil)
        .focused($isTopRedirectorFocused)
        .onChange(of: isTopRedirectorFocused) { _, isFocused in
          if isFocused {
            focusedPickerIndex = currentFocusIndex
            isTopRedirectorFocused = false
          }
        }

      ScrollView(.horizontal, showsIndicators: false) {
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
          case .anilist:
            anilistFilters
              .foregroundColor(.primary)
          case .popular:
            popularFilters
              .foregroundColor(.primary)
          case .subscriptionShare:
            shareFilters
              .foregroundColor(.primary)
          case .custom:
            pluginFilters
              .foregroundColor(.primary)
          }
        }
      }
      .lineLimit(1)

      // 底部焦点重定向器 - 捕获来自下方媒体网格的焦点
      Color.clear
        .frame(height: 1)
        .focusable(hasFocusableFilters && focusedPickerIndex == nil)
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
      ForEach(5...10, id: \.self) { rating in
        Text("评分：\(rating)分以上").tag(rating)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 4)

    Picker("评分人数", selection: $viewModel.tmdbVoteCount) {
      ForEach([10, 100, 500, 1_000, 5_000, 10_000], id: \.self) { count in
        Text("评分人数：\(count)人以上").tag(count)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 5)
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
    // 类别
    Picker("类别", selection: $viewModel.bangumiCat) {
      Text("类别：全部").tag("")
      ForEach(ExploreViewModel.bangumiCatDict, id: \.key) { item in
        Text("类别：" + item.value).tag(item.key)
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

  // MARK: - AniList 筛选器
  @ViewBuilder
  private var anilistFilters: some View {
    Picker("排序", selection: $viewModel.anilistSort) {
      ForEach(ExploreViewModel.anilistSortDict, id: \.key) {
        Text("排序：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    Picker("形式", selection: $viewModel.anilistFormat) {
      Text("形式：全部").tag("")
      ForEach(ExploreViewModel.anilistFormatDict, id: \.key) {
        Text("形式：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    Picker("风格", selection: $viewModel.anilistGenre) {
      Text("风格：全部").tag("")
      ForEach(ExploreViewModel.anilistGenreDict, id: \.key) {
        Text("风格：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)

    Picker("季度", selection: $viewModel.anilistSeason) {
      Text("季度：全部").tag("")
      ForEach(ExploreViewModel.anilistSeasonDict, id: \.key) {
        Text("季度：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 3)

    Picker("年份", selection: $viewModel.anilistYear) {
      Text("年份：全部").tag(0)
      ForEach(ExploreViewModel.anilistYearDict, id: \.key) {
        Text("年份：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 4)

    Picker("状态", selection: $viewModel.anilistStatus) {
      Text("状态：全部").tag("")
      ForEach(ExploreViewModel.anilistStatusDict, id: \.key) {
        Text("状态：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 5)

    Picker("地区", selection: $viewModel.anilistCountry) {
      Text("地区：全部").tag("")
      ForEach(ExploreViewModel.anilistCountryDict, id: \.key) {
        Text("地区：" + $0.value).tag($0.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 6)
  }

  // MARK: - 插件筛选器
  @ViewBuilder
  private var pluginFilters: some View {
    ForEach(Array(viewModel.pluginFilterControls.enumerated()), id: \.element.id) {
      index, control in
      switch control.kind {
      case .choice:
        Picker(
          control.label,
          selection: pluginBinding(for: control.field)
        ) {
          if !control.options.contains(where: { $0.value == pluginBindingValue(control.field) }) {
            Text("\(control.label)：默认").tag(pluginBindingValue(control.field))
          }
          ForEach(control.options) { option in
            Text("\(control.label)：\(option.title)").tag(option.value)
          }
        }
        .pickerStyle(.menu)
        .focused($focusedPickerIndex, equals: index)
      case .text:
        TextField(control.label, text: pluginTextBinding(for: control.field))
          .frame(width: 260)
          .focused($focusedPickerIndex, equals: index)
      case .number:
        TextField(control.label, text: pluginNumberBinding(for: control.field))
          .frame(width: 180)
          .focused($focusedPickerIndex, equals: index)
      }
    }
  }

  private func pluginBindingValue(_ field: String) -> JSONValue {
    viewModel.pluginFilterValues[field] ?? .null
  }

  private func pluginBinding(for field: String) -> Binding<JSONValue> {
    Binding(
      get: { pluginBindingValue(field) },
      set: { viewModel.setPluginFilter(field, value: $0) }
    )
  }

  private func pluginTextBinding(for field: String) -> Binding<String> {
    Binding(
      get: { pluginBindingValue(field).queryString ?? "" },
      set: { viewModel.setPluginFilter(field, value: $0.isEmpty ? .null : .string($0)) }
    )
  }

  private func pluginNumberBinding(for field: String) -> Binding<String> {
    Binding(
      get: { pluginBindingValue(field).queryString ?? "" },
      set: {
        viewModel.setPluginFilter(
          field,
          value: $0.isEmpty ? .null : Int($0).map(JSONValue.int) ?? .string($0)
        )
      }
    )
  }

  // MARK: - Popular 筛选器
  @ViewBuilder
  private var popularFilters: some View {
    // 类型
    Picker("类型", selection: $viewModel.selectedType) {
      ForEach(DiscoverMediaType.allCases) { type in
        Text("类型：" + type.rawValue).tag(type)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    // 排序
    Picker("排序", selection: $viewModel.popularSortBy) {
      ForEach(viewModel.currentSortDict, id: \.key) { item in
        Text("排序：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    // 风格
    Picker("风格", selection: $viewModel.popularGenre) {
      Text("风格：全部").tag("")
      ForEach(viewModel.currentGenreDict, id: \.key) { item in
        Text("风格：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)

    // 评分
    Picker("评分", selection: $viewModel.popularMinRating) {
      Text("评分：不限").tag(0)
      ForEach(5...10, id: \.self) { rating in
        Text("评分：\(rating)分以上").tag(rating)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 3)
  }

  // MARK: - Share 筛选器
  @ViewBuilder
  private var shareFilters: some View {
    // 排序
    Picker("排序", selection: $viewModel.shareSortBy) {
      ForEach(viewModel.currentSortDict, id: \.key) { item in
        Text("排序：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 0)

    // 风格
    Picker("风格", selection: $viewModel.shareGenre) {
      Text("风格：全部").tag("")
      ForEach(viewModel.currentGenreDict, id: \.key) { item in
        Text("风格：" + item.value).tag(item.key)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 1)

    // 评分
    Picker("评分", selection: $viewModel.shareMinRating) {
      Text("评分：不限").tag(0)
      ForEach(5...10, id: \.self) { rating in
        Text("评分：\(rating)分以上").tag(rating)
      }
    }
    .pickerStyle(.menu)
    .focused($focusedPickerIndex, equals: 2)
  }
}
