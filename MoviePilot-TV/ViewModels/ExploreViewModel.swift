import Combine
import Foundation
import SwiftUI

// MARK: - 数据源枚举
enum DiscoverSource: String, CaseIterable, Identifiable {
  case themoviedb = "TheMovieDb"
  case douban = "豆瓣"
  case bangumi = "Bangumi"

  var id: String { rawValue }
}

// MARK: - 类型枚举
enum DiscoverMediaType: String, CaseIterable, Identifiable {
  case movies = "电影"
  case tvs = "剧集"

  var id: String { rawValue }

  var apiValue: String {
    switch self {
    case .movies: return "movies"
    case .tvs: return "tvs"
    }
  }
}

// MARK: - ViewModel
@MainActor
class ExploreViewModel: ObservableObject {
  @Published var selectedSource: DiscoverSource = .themoviedb
  @Published var selectedType: DiscoverMediaType = .movies

  // TheMovieDb 筛选参数
  @Published var tmdbSortBy: String = "popularity.desc"
  @Published var tmdbGenre: String = ""
  @Published var tmdbLanguage: String = ""
  @Published var tmdbVoteAverage: Int = 0

  // 豆瓣筛选参数
  @Published var doubanSort: String = "U"
  @Published var doubanCategory: String = ""
  @Published var doubanZone: String = ""
  @Published var doubanYear: String = ""

  // Bangumi 筛选参数
  @Published var bangumiCat: String = ""
  @Published var bangumiSort: String = "rank"
  @Published var bangumiYear: String = ""

  // 数据状态
  @Published private(set) var paginator: Paginator<MediaInfo>?

  private let apiService = APIService.shared

  private var cancellables = Set<AnyCancellable>()
  private var paginatorCancellable: AnyCancellable?

  init() {
    // 将所有筛选器的 Publisher 转换为 AnyPublisher<Void, Never>
    let filterPublishers: [AnyPublisher<Void, Never>] = [
      $selectedSource.map { _ in }.eraseToAnyPublisher(),
      $selectedType.map { _ in }.eraseToAnyPublisher(),
      $tmdbSortBy.map { _ in }.eraseToAnyPublisher(),
      $tmdbGenre.map { _ in }.eraseToAnyPublisher(),
      $tmdbLanguage.map { _ in }.eraseToAnyPublisher(),
      $tmdbVoteAverage.map { _ in }.eraseToAnyPublisher(),
      $doubanSort.map { _ in }.eraseToAnyPublisher(),
      $doubanCategory.map { _ in }.eraseToAnyPublisher(),
      $doubanZone.map { _ in }.eraseToAnyPublisher(),
      $doubanYear.map { _ in }.eraseToAnyPublisher(),
      $bangumiCat.map { _ in }.eraseToAnyPublisher(),
      $bangumiSort.map { _ in }.eraseToAnyPublisher(),
      $bangumiYear.map { _ in }.eraseToAnyPublisher(),
    ]

    // 合并所有筛选器 Publisher
    Publishers.MergeMany(filterPublishers)
      // 使用 debounce 来防止快速连续的 UI 更新导致多次加载
      // 例如，当 onSourceChanged 重置多个属性时
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      // 映射到 API 路径
      .map { [unowned self] in self.buildApiPath() }
      // 只有当路径变化时才继续
      .removeDuplicates()
      // 订阅路径变化，并创建新的 Paginator
      .sink { [unowned self] path in
        self.setupPaginator(for: path)
      }
      .store(in: &cancellables)
  }

  // MARK: - TheMovieDb 字典

  static let tmdbMovieSortDict: [(key: String, value: String)] = [
    ("popularity.desc", "热门降序"),
    ("popularity.asc", "热门升序"),
    ("release_date.desc", "上映日期降序"),
    ("release_date.asc", "上映日期升序"),
    ("vote_average.desc", "评分降序"),
    ("vote_average.asc", "评分升序"),
  ]

  static let tmdbTvSortDict: [(key: String, value: String)] = [
    ("popularity.desc", "热门降序"),
    ("popularity.asc", "热门升序"),
    ("first_air_date.desc", "首播日期降序"),
    ("first_air_date.asc", "首播日期升序"),
    ("vote_average.desc", "评分降序"),
    ("vote_average.asc", "评分升序"),
  ]

  static let tmdbMovieGenreDict: [(key: String, value: String)] = [
    ("12", "冒险"),
    ("14", "奇幻"),
    ("16", "动画"),
    ("18", "剧情"),
    ("27", "恐怖"),
    ("28", "动作"),
    ("35", "喜剧"),
    ("36", "历史"),
    ("37", "西部"),
    ("53", "惊悚"),
    ("80", "犯罪"),
    ("99", "纪录片"),
    ("878", "科幻"),
    ("9648", "悬疑"),
    ("10402", "音乐"),
    ("10749", "爱情"),
    ("10751", "家庭"),
    ("10752", "战争"),
    ("10770", "电视电影"),
  ]

  static let tmdbTvGenreDict: [(key: String, value: String)] = [
    ("16", "动画"),
    ("18", "剧情"),
    ("35", "喜剧"),
    ("37", "西部"),
    ("80", "犯罪"),
    ("99", "纪录片"),
    ("9648", "悬疑"),
    ("10751", "家庭"),
    ("10759", "动作冒险"),
    ("10762", "儿童"),
    ("10763", "新闻"),
    ("10764", "真人秀"),
    ("10765", "科幻/奇幻"),
    ("10766", "肥皂剧"),
    ("10767", "脱口秀"),
    ("10768", "战争/政治"),
  ]

  static let tmdbLanguageDict: [(key: String, value: String)] = [
    ("zh", "中文"),
    ("en", "英语"),
    ("ja", "日语"),
    ("ko", "韩语"),
    ("fr", "法语"),
    ("de", "德语"),
    ("es", "西班牙语"),
    ("it", "意大利语"),
    ("ru", "俄语"),
    ("pt", "葡萄牙语"),
    ("ar", "阿拉伯语"),
    ("hi", "印地语"),
    ("th", "泰语"),
  ]

  // MARK: - 豆瓣字典

  static let doubanSortDict: [(key: String, value: String)] = [
    ("U", "综合"),
    ("R", "上映日期"),
    ("T", "近期热门"),
    ("S", "高分优先"),
  ]

  static let doubanCategoryDict: [(key: String, value: String)] = [
    ("喜剧", "喜剧"),
    ("爱情", "爱情"),
    ("动作", "动作"),
    ("科幻", "科幻"),
    ("动画", "动画"),
    ("悬疑", "悬疑"),
    ("犯罪", "犯罪"),
    ("惊悚", "惊悚"),
    ("冒险", "冒险"),
    ("音乐", "音乐"),
    ("历史", "历史"),
    ("奇幻", "奇幻"),
    ("恐怖", "恐怖"),
    ("战争", "战争"),
    ("传记", "传记"),
    ("歌舞", "歌舞"),
    ("武侠", "武侠"),
    ("情色", "情色"),
    ("灾难", "灾难"),
    ("西部", "西部"),
    ("纪录片", "纪录片"),
    ("短片", "短片"),
  ]

  static let doubanZoneDict: [(key: String, value: String)] = [
    ("华语", "华语"),
    ("欧美", "欧美"),
    ("韩国", "韩国"),
    ("日本", "日本"),
    ("中国大陆", "中国大陆"),
    ("美国", "美国"),
    ("中国香港", "中国香港"),
    ("中国台湾", "中国台湾"),
    ("英国", "英国"),
    ("法国", "法国"),
    ("德国", "德国"),
    ("意大利", "意大利"),
    ("西班牙", "西班牙"),
    ("印度", "印度"),
    ("泰国", "泰国"),
    ("俄罗斯", "俄罗斯"),
    ("加拿大", "加拿大"),
    ("澳大利亚", "澳大利亚"),
    ("爱尔兰", "爱尔兰"),
    ("瑞典", "瑞典"),
    ("巴西", "巴西"),
    ("丹麦", "丹麦"),
  ]

  static var doubanYearDict: [(key: String, value: String)] {
    var years: [(key: String, value: String)] = []
    let currentYear = Calendar.current.component(.year, from: Date())
    // 近6年
    for i in 0..<6 {
      let year = String(currentYear - i)
      years.append((key: year, value: year))
    }
    // 年代
    years.append(contentsOf: [
      (key: "2020年代", value: "2020年代"),
      (key: "2010年代", value: "2010年代"),
      (key: "2000年代", value: "2000年代"),
      (key: "90年代", value: "90年代"),
      (key: "80年代", value: "80年代"),
      (key: "70年代", value: "70年代"),
      (key: "60年代", value: "60年代"),
    ])
    return years
  }

  // MARK: - Bangumi 字典

  static let bangumiCatDict: [(key: String, value: String)] = [
    ("0", "其他"),
    ("1", "TV"),
    ("2", "OVA"),
    ("3", "电影"),
    ("5", "WEB"),
  ]

  static let bangumiSortDict: [(key: String, value: String)] = [
    ("rank", "排名"),
    ("date", "日期"),
  ]

  static var bangumiYearDict: [(key: String, value: String)] {
    let currentYear = Calendar.current.component(.year, from: Date())
    return (0..<10).map { i in
      let year = String(currentYear - i)
      return (key: year, value: year)
    }
  }

  // MARK: - 计算属性

  var currentSortDict: [(key: String, value: String)] {
    switch selectedSource {
    case .themoviedb:
      return selectedType == .movies ? Self.tmdbMovieSortDict : Self.tmdbTvSortDict
    case .douban:
      return Self.doubanSortDict
    case .bangumi:
      return Self.bangumiSortDict
    }
  }

  var currentGenreDict: [(key: String, value: String)] {
    switch selectedSource {
    case .themoviedb:
      return selectedType == .movies ? Self.tmdbMovieGenreDict : Self.tmdbTvGenreDict
    case .douban:
      return Self.doubanCategoryDict
    case .bangumi:
      return Self.bangumiCatDict
    }
  }

  // MARK: - API 路径构建

  private func buildApiPath() -> String {
    switch selectedSource {
    case .themoviedb:
      var path = "discover/tmdb_\(selectedType.apiValue)"
      var params: [String] = []

      if !tmdbSortBy.isEmpty {
        params.append("sort_by=\(tmdbSortBy)")
      }
      if !tmdbGenre.isEmpty {
        params.append("with_genres=\(tmdbGenre)")
      }
      if !tmdbLanguage.isEmpty {
        params.append("with_original_language=\(tmdbLanguage)")
      }
      if tmdbVoteAverage > 0 {
        params.append("vote_average=\(tmdbVoteAverage)")
        params.append("vote_count=10")
      }

      if !params.isEmpty {
        path += "?" + params.joined(separator: "&")
      }
      return path

    case .douban:
      var path = "discover/douban_\(selectedType.apiValue)"
      var params: [String] = []

      if !doubanSort.isEmpty {
        params.append("sort=\(doubanSort)")
      }
      // 拼接 tags: 风格,地区,年代
      let tags = [doubanCategory, doubanZone, doubanYear].filter { !$0.isEmpty }.joined(
        separator: ",")
      if !tags.isEmpty {
        if let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
          params.append("tags=\(encoded)")
        }
      }

      if !params.isEmpty {
        path += "?" + params.joined(separator: "&")
      }
      return path

    case .bangumi:
      var path = "discover/bangumi"
      var params: [String] = ["type=2"]  // 固定 type=2 表示动画

      if !bangumiCat.isEmpty {
        params.append("cat=\(bangumiCat)")
      }
      if !bangumiSort.isEmpty {
        params.append("sort=\(bangumiSort)")
      }
      if !bangumiYear.isEmpty {
        params.append("year=\(bangumiYear)")
      }

      path += "?" + params.joined(separator: "&")
      return path
    }
  }

  // MARK: - 数据加载

  private func setupPaginator(for path: String) {
    var seenKeys = Set<String>()

    let newPaginator = Paginator<MediaInfo>(
      threshold: 24,
      fetcher: { @MainActor [apiService] page in
        try await apiService.fetchRecommend(path: path, page: page)
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
    paginator = newPaginator

    paginatorCancellable = newPaginator.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }

    Task {
      await newPaginator.refresh()
    }
  }

  // MARK: - 重置筛选器

  func onSourceChanged() {
    // 重置所有筛选参数
    selectedType = .movies
    tmdbSortBy = "popularity.desc"
    tmdbGenre = ""
    tmdbLanguage = ""
    tmdbVoteAverage = 0
    doubanSort = "U"
    doubanCategory = ""
    doubanZone = ""
    doubanYear = ""
    bangumiCat = ""
    bangumiSort = "rank"
    bangumiYear = ""
  }

  func onTypeChanged() {
    // 类型变化时重置风格（因为电影和剧集的风格不同）
    tmdbGenre = ""
    doubanCategory = ""
  }
}
