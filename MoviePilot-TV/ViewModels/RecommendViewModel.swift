import Combine
import Foundation
import SwiftUI

// MARK: - 分类枚举
enum RecommendCategory: String, CaseIterable, Identifiable {
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
struct RecommendShelf: Identifiable, Hashable {
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

  private let apiService = APIService.shared

  private var cancellables = Set<AnyCancellable>()
  private var paginatorCancellable: AnyCancellable?

  // 所有货架配置
  static let allShelves: [RecommendShelf] = [
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
    if selectedCategory == .all {
      return Self.allShelves
    }
    return Self.allShelves.filter { $0.category == selectedCategory }
  }

  init() {
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
    onCategoryChanged()
  }

  private func setupPaginator(for shelf: RecommendShelf) {
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
    selectedShelf = filteredShelves.first
  }
}
