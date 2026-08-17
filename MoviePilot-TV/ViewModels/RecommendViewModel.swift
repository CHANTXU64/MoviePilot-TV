import Combine
import Foundation
import SwiftUI

// MARK: - 分类枚举
nonisolated enum RecommendCategory: String, CaseIterable, Identifiable, Sendable {
  case all = "全部"
  case movie = "电影"
  case tv = "电视剧"
  case anime = "动画"
  case chart = "榜单"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .all: return "square.grid.2x2"
    case .movie: return "film"
    case .tv: return "tv"
    case .anime: return "sparkles"
    case .chart: return "chart.bar"
    }
  }
}

// MARK: - 货架定义
nonisolated struct RecommendShelf: Identifiable, Hashable, Sendable {
  let id: String  // API 路径
  let title: String
  let category: RecommendCategory

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: RecommendShelf, rhs: RecommendShelf) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - ViewModel
@MainActor
class RecommendViewModel: ObservableObject {
  @Published var selectedCategory: RecommendCategory = .all
  @Published var selectedShelf: RecommendShelf?
  @Published private(set) var paginator: Paginator<MediaInfo>?
  @Published private(set) var shelves: [RecommendShelf] = []
  @Published private(set) var enableConfig: [String: Bool] = [:]

  private let apiService: APIService

  private var cancellables = Set<AnyCancellable>()
  private var paginatorCancellable: AnyCancellable?
  private var extraSourceSnapshot: [RecommendSourceDescriptor] = []

  private static let localConfigKey = "MP_RECOMMEND"

  // 所有货架配置
  nonisolated static let allShelves: [RecommendShelf] = [
    // 全部分类（流行趋势作为默认）
    RecommendShelf(id: "recommend/tmdb_trending", title: "流行趋势", category: .chart),

    // 电影分类
    RecommendShelf(id: "recommend/douban_showing", title: "正在热映", category: .movie),
    RecommendShelf(id: "recommend/tmdb_movies", title: "TMDB热门电影", category: .movie),
    RecommendShelf(id: "recommend/douban_movie_hot", title: "豆瓣热门电影", category: .movie),
    RecommendShelf(id: "recommend/douban_movies", title: "豆瓣最新电影", category: .movie),

    // 电视剧分类
    RecommendShelf(
      id: "recommend/tmdb_tvs?with_original_language=zh|en|ja|ko", title: "TMDB热门剧集",
      category: .tv),
    RecommendShelf(id: "recommend/douban_tv_hot", title: "豆瓣热门剧集", category: .tv),
    RecommendShelf(id: "recommend/douban_tvs", title: "豆瓣最新剧集", category: .tv),

    // 动画分类
    RecommendShelf(id: "recommend/bangumi_calendar", title: "每日番剧", category: .anime),
    RecommendShelf(id: "anilist/trending", title: "AniList 当前趋势", category: .anime),
    RecommendShelf(
      id: "anilist/popular-this-season", title: "AniList 本季热门", category: .anime),
    RecommendShelf(id: "recommend/douban_tv_animation", title: "豆瓣热门动画", category: .anime),

    // 榜单分类
    RecommendShelf(id: "recommend/douban_movie_top250", title: "豆瓣Top250", category: .chart),
    RecommendShelf(
      id: "recommend/douban_tv_weekly_chinese", title: "豆瓣华语口碑周榜", category: .chart),
    RecommendShelf(
      id: "recommend/douban_tv_weekly_global", title: "豆瓣全球口碑周榜", category: .chart),
  ]

  // 根据当前分类过滤的货架列表
  var filteredShelves: [RecommendShelf] {
    let enabledShelves = shelves.filter { enableConfig[$0.title] == true }
    if selectedCategory == .all {
      return enabledShelves
    }
    return enabledShelves.filter { $0.category == selectedCategory }
  }

  var visibleCategories: [RecommendCategory] {
    Self.visibleCategories(shelves: shelves, enableConfig: enableConfig)
  }

  nonisolated static func visibleCategories(
    shelves: [RecommendShelf],
    enableConfig: [String: Bool]
  ) -> [RecommendCategory] {
    let categories = Set(
      shelves.lazy.filter { enableConfig[$0.title] == true }.map(\.category)
    )
    guard !categories.isEmpty else { return [] }
    return RecommendCategory.allCases.filter { $0 == .all || categories.contains($0) }
  }

  init(selectShelf: Bool = true, apiService: APIService = .shared) {
    self.apiService = apiService
    shelves = Self.allShelves
    enableConfig = Dictionary(uniqueKeysWithValues: Self.allShelves.map { ($0.title, true) })
    loadConfig()
    // 默认选中流行趋势
    // 当 selectedShelf 改变时，自动创建一个新的 Paginator 实例
    // sink 会因为 selectedShelf 的初始值而立即触发，所以无需手动调用 setupPaginator
    $selectedShelf
      .compactMap { $0 }
      .removeDuplicates()
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      .sink { [weak self] shelf in
        self?.setupPaginator(for: shelf)
      }
      .store(in: &cancellables)

    // 设置初始货架，这将触发上面的 sink
    guard selectShelf else { return }
    onCategoryChanged()
  }

  private func setupPaginator(for shelf: RecommendShelf) {
    paginator?.cancel()
    paginatorCancellable?.cancel()
    guard apiService.canAccess(.discovery) else {
      paginator = nil
      return
    }

    var seenKeys = Set<String>()

    let newPaginator = Paginator<MediaInfo>(
      threshold: 24,
      fetcher: { @MainActor [apiService] page in
        try await apiService.fetchRecommend(path: shelf.id, page: page)
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        if uniqueNewItems.isEmpty {
          return false
        }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      imageURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
      },
      imagePrefetchProcessor: MediaCard.posterProcessor(for: MediaCard.defaultPosterSize),
      onReset: { @MainActor in
        seenKeys.removeAll()
      }
    )
    self.paginator = newPaginator

    // 桥接：paginator 内部变化 → ViewModel.objectWillChange
    paginatorCancellable = newPaginator.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }

    Task {
      await newPaginator.refresh()
    }
  }

  // 分类变更时自动选中第一个货架
  func onCategoryChanged() {
    // 这将触发 sink pipeline 来设置一个新的 Paginator
    selectFirstVisibleShelf()
  }

  private func selectFirstVisibleShelf() {
    selectedShelf = filteredShelves.first
    if selectedShelf == nil {
      paginator?.cancel()
      paginatorCancellable?.cancel()
      paginator = nil
    }
  }

  func saveEnableConfig(_ config: [String: Bool]) {
    enableConfig = config
    if let data = try? JSONEncoder().encode(enableConfig) {
      UserDefaults.standard.set(data, forKey: Self.localConfigKey)
    }
  }

  func refreshSources(selectShelf: Bool = true) async {
    loadConfig()
    guard apiService.canAccess(.discovery) else { return }
    do {
      extraSourceSnapshot = try await apiService.fetchRecommendSources()
    } catch {
      // 保留最近成功快照。
      Logger.error("动态推荐来源加载失败: \(error)")
    }
    shelves = Self.mergedShelves(extras: extraSourceSnapshot)
    for title in ["AniList 当前趋势", "AniList 本季热门"] where enableConfig[title] == nil {
      enableConfig[title] = true
    }
    if selectShelf { reconcileSelection() }
  }

  func reloadLocalConfig() {
    loadConfig()
    reconcileSelection()
  }

  private func reconcileSelection() {
    if !visibleCategories.contains(selectedCategory) {
      selectedCategory = visibleCategories.first ?? .all
    }
    if selectedShelf == nil || !filteredShelves.contains(where: { $0.id == selectedShelf?.id }) {
      selectFirstVisibleShelf()
    }
  }

  nonisolated static func mergedShelves(
    extras: [RecommendSourceDescriptor]
  ) -> [RecommendShelf] {
    var result = allShelves
    var paths = Set(result.map(\.id))
    for source in extras where paths.insert(source.api_path).inserted {
      result.append(
        RecommendShelf(
          id: source.api_path,
          title: source.name,
          category: category(for: source.type)
        ))
    }
    return result
  }

  nonisolated static func category(for type: String) -> RecommendCategory {
    switch type {
    case RecommendCategory.movie.rawValue: .movie
    case RecommendCategory.tv.rawValue: .tv
    case RecommendCategory.anime.rawValue: .anime
    case RecommendCategory.chart.rawValue: .chart
    default: .all
    }
  }

  private func loadConfig() {
    if let data = UserDefaults.standard.data(forKey: Self.localConfigKey) {
      if let config = try? JSONDecoder().decode([String: Bool].self, from: data) {
        enableConfig = config
        return
      }
      UserDefaults.standard.removeObject(forKey: Self.localConfigKey)
    }
    enableConfig = Dictionary(uniqueKeysWithValues: Self.allShelves.map { ($0.title, true) })
  }
}
