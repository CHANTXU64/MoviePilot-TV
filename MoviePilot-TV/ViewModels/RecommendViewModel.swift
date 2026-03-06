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
  @Published var items: [MediaInfo] = []
  @Published var isLoading = false
  @Published var currentPage = 1
  @Published var hasMoreData = true
  @Published var isLoadingMore = false

  private let apiService = APIService.shared
  private var seenKeys = Set<String>()

  // 所有货架配置
  static let allShelves: [RecommendShelf] = [
    // 全部分类（流行趋势作为默认）
    RecommendShelf(id: "recommend/tmdb_trending", title: "流行趋势", category: .all),

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
    selectedShelf = Self.allShelves.first
  }

  // 分类变更时自动选中第一个货架
  func onCategoryChanged() {
    let shelves = filteredShelves
    if let first = shelves.first {
      selectedShelf = first
    }
  }

  // 加载货架数据（首次加载）
  func loadShelfData() async {
    guard let shelf = selectedShelf else { return }

    currentPage = 1
    hasMoreData = true
    isLoading = true
    do {
      let fetched = try await apiService.fetchRecommend(path: shelf.id, page: 1)
      seenKeys.removeAll()
      items = MediaInfo.deduplicate(fetched, existingKeys: &seenKeys)
    } catch {
      print("Failed to load shelf \(shelf.title): \(error)")
      items = []
    }
    isLoading = false
  }

  // 加载更多数据（分页加载）
  func loadMoreData() async {
    guard hasMoreData, !isLoadingMore, let shelf = selectedShelf else { return }

    isLoadingMore = true
    currentPage += 1
    do {
      let newItems = try await apiService.fetchRecommend(path: shelf.id, page: currentPage)
      if newItems.isEmpty {
        hasMoreData = false
      } else {
        let unique = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        items.append(contentsOf: unique)
      }
    } catch {
      print("Failed to load more for shelf \(shelf.title): \(error)")
      currentPage -= 1  // 恢复页码
    }
    isLoadingMore = false
  }
}
