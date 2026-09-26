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

  nonisolated static let localConfigKey = "MP_RECOMMEND"

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
    let enabledShelves = Self.enabledShelves(shelves, enableConfig: enableConfig)
    if selectedCategory == .all {
      return enabledShelves
    }
    return enabledShelves.filter { $0.category == selectedCategory }
  }

  /// 按稳定 `shelf.id`（API 路径）过滤已启用的货架。
  /// 渲染/ForEach/焦点/取数都以 `id` 区分货架，开关配置也以 `id` 为键，否则两条
  /// 同名不同路径的货架会渲染成两行却共享一个开关值，无法表达“启用 A、停用 B”。
  nonisolated static func enabledShelves(
    _ shelves: [RecommendShelf],
    enableConfig: [String: Bool]
  ) -> [RecommendShelf] {
    shelves.filter { enableConfig[$0.id] == true }
  }

  var visibleCategories: [RecommendCategory] {
    Self.visibleCategories(shelves: shelves, enableConfig: enableConfig)
  }

  nonisolated static func visibleCategories(
    shelves: [RecommendShelf],
    enableConfig: [String: Bool]
  ) -> [RecommendCategory] {
    let categories = Set(
      shelves.lazy.filter { enableConfig[$0.id] == true }.map(\.category)
    )
    guard !categories.isEmpty else { return [] }
    return RecommendCategory.allCases.filter { $0 == .all || categories.contains($0) }
  }

  init(selectShelf: Bool = true, apiService: APIService = .shared) {
    self.apiService = apiService
    shelves = Self.allShelves
    enableConfig = Dictionary(uniqueKeysWithValues: Self.allShelves.map { ($0.id, true) })
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
      imageWarmer: apiService.imageWarmer,
      imageWarmURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
      },
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
    var loadedExtraSourcesSuccessfully = false
    do {
      extraSourceSnapshot = try await apiService.fetchRecommendSources()
      loadedExtraSourcesSuccessfully = true
    } catch {
      // 保留最近成功快照。
      Logger.error("动态推荐来源加载失败: \(error)")
    }
    shelves = Self.mergedShelves(extras: extraSourceSnapshot)
    if loadedExtraSourcesSuccessfully {
      // 只有完整来源请求成功后才消费旧 title 键：把旧“共享开关”值平铺到本轮全部
      // 同名货架，再切换为稳定 id 持久化。失败时保留 title，供下次刷新继续迁移。
      let migrated = Self.migrateTitleKeys(in: enableConfig, shelves: shelves)
      if migrated != enableConfig {
        saveEnableConfig(migrated)
      }
    }
    // 配置早于新版内置货架创建时默认开启（与旧 title 键逻辑等价）。
    for id in ["anilist/trending", "anilist/popular-this-season"] where enableConfig[id] == nil {
      enableConfig[id] = true
    }
    guard selectShelf else { return }
    reconcileSelection()
    // 重新激活（非首次）时，若当前 shelf 处于成功空终态则自动重试一次，
    // 避免页面一直空白直到手动切换 shelf。
    if hasHandledFirstActivation {
      await refreshIfSuccessEmpty()
    }
    hasHandledFirstActivation = true
  }

  private var hasHandledFirstActivation = false

  /// 当前 shelf 处于“成功空终态”（空、无加载、无错误、无更多页）时重试一次。
  private func refreshIfSuccessEmpty() async {
    guard let paginator,
      paginator.items.isEmpty,
      !paginator.isLoading,
      !paginator.hasError,
      !paginator.hasMore
    else { return }
    await paginator.refresh()
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

  /// 把旧版本以可重复 `shelf.title` 为键的本地配置迁移到稳定 `shelf.id`：
  /// - 键已是当前货架的 id → 原样保留；
  /// - 键是某货架的 title 且唯一 → 改写为该货架的 id（保留原开关值）；
  /// - 键是多个同名货架共用的 title → 把旧共享值平铺到每个同名 id 后删除 title 键
  ///   （还原旧“一键控全部”行为，用户之后可独立拆分）；
  /// - 其余未知键（暂无法解析的旧 title / 已消失货架的 id）→ 原样保留，不做破坏性删除。
  /// - `consumeMatchedTitles == false` → 只复制到当前已知 id，保留 title 供稍后加载的动态来源继承。
  nonisolated static func migrateTitleKeys(
    in raw: [String: Bool],
    shelves: [RecommendShelf],
    consumeMatchedTitles: Bool = true
  ) -> [String: Bool] {
    var idsByTitle: [String: [String]] = [:]
    let presentIDs = Set(shelves.map(\.id))
    for shelf in shelves {
      idsByTitle[shelf.title, default: []].append(shelf.id)
    }
    var out = raw
    for (key, value) in raw {
      guard !presentIDs.contains(key), let ids = idsByTitle[key], !ids.isEmpty else { continue }
      for id in ids where out[id] == nil {
        out[id] = value
      }
      if consumeMatchedTitles {
        out.removeValue(forKey: key)
      }
    }
    return out
  }

  nonisolated static func storedEnableConfig(
    defaults: UserDefaults = .standard
  ) -> [String: Bool]? {
    guard let data = defaults.data(forKey: localConfigKey) else { return nil }
    return try? JSONDecoder().decode([String: Bool].self, from: data)
  }

  private func loadConfig() {
    if UserDefaults.standard.data(forKey: Self.localConfigKey) != nil {
      if let config = Self.storedEnableConfig() {
        // 初始化时只有内置货架：先让已知 id 继承旧值，但保留且不回写 title 键。
        // 动态来源成功加载后再统一消费，避免同名来源错过旧版共享配置。
        enableConfig = Self.migrateTitleKeys(
          in: config,
          shelves: shelves,
          consumeMatchedTitles: false
        )
        return
      }
      UserDefaults.standard.removeObject(forKey: Self.localConfigKey)
    }
    enableConfig = Dictionary(uniqueKeysWithValues: Self.allShelves.map { ($0.id, true) })
  }
}
