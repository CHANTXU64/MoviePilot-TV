import Combine
import Foundation
import SwiftUI

// MARK: - 数据源
nonisolated enum DiscoverSource: Hashable, Identifiable, Sendable {
  case themoviedb
  case douban
  case bangumi
  case anilist
  case popular
  case subscriptionShare
  case custom(DiscoverSourceDescriptor)

  static let allCases: [DiscoverSource] = [
    .themoviedb, .douban, .bangumi, .anilist, .popular, .subscriptionShare,
  ]

  var id: String {
    switch self {
    case .themoviedb: "themoviedb"
    case .douban: "douban"
    case .bangumi: "bangumi"
    case .anilist: "anilist"
    case .popular: "popular"
    case .subscriptionShare: "subscriptionShare"
    case .custom(let source): "custom:\(source.mediaid_prefix)"
    }
  }

  var title: String {
    switch self {
    case .themoviedb: "TheMovieDb"
    case .douban: "豆瓣"
    case .bangumi: "Bangumi"
    case .anilist: "AniList"
    case .popular: "热门订阅"
    case .subscriptionShare: "订阅分享"
    case .custom(let source): source.name
    }
  }

  var descriptor: DiscoverSourceDescriptor? {
    guard case .custom(let source) = self else { return nil }
    return source
  }
}

nonisolated struct PluginFilterOption: Hashable, Identifiable {
  let value: JSONValue
  let title: String

  var id: JSONValue { value }
}

nonisolated struct PluginFilterControl: Hashable, Identifiable {
  enum Kind: Hashable {
    case choice
    case text
    case number
  }

  let field: String
  let label: String
  let kind: Kind
  let options: [PluginFilterOption]

  var id: String { field }
}

nonisolated enum PluginFilterControlParser {
  static func parse(_ nodes: [JSONValue]) -> [PluginFilterControl] {
    var controls: [PluginFilterControl] = []
    nodes.forEach {
      collect($0, inheritedLabel: nil, controls: &controls)
    }
    var seenFields = Set<String>()
    return controls.filter { seenFields.insert($0.field).inserted }
  }

  private static func collect(
    _ node: JSONValue,
    inheritedLabel: String?,
    controls: inout [PluginFilterControl]
  ) {
    guard let object = node.objectValue else { return }
    let component = object["component"]?.stringValue ?? ""
    let props = object["props"]?.objectValue ?? [:]
    let children = object["content"]?.arrayValue ?? []
    let prop: ([String]) -> JSONValue? = { names in
      names.lazy.compactMap { name in
        props.first(where: { $0.key.lowercased() == name.lowercased() })?.value
      }.first
    }
    let localLabel = prop(["label"])?.stringValue ?? inheritedLabel
    let field =
      prop(["model", "v-model", "modelvalue", "modelValue"])?.stringValue
      ?? prop(["name"])?.stringValue
      ?? object["model"]?.stringValue

    if let field {
      let lower = component.lowercased()
      let options = collectOptions(
        from: children + (prop(["items"])?.arrayValue ?? [])
      )
      let kind: PluginFilterControl.Kind
      switch lower {
      case "vchipgroup", "vradiogroup", "vselect", "vcombobox":
        kind = options.isEmpty ? .text : .choice
      case "vtextfield":
        kind = props["type"]?.stringValue?.lowercased() == "number" ? .number : .text
      case "vnumberinput":
        kind = .number
      default:
        return
      }
      controls.append(
        PluginFilterControl(
          field: field,
          label: localLabel ?? field,
          kind: kind,
          options: options
        ))
      return
    }

    var siblingLabel = localLabel
    children.forEach {
      if let label = firstLabel(in: $0) {
        siblingLabel = label
      }
      collect($0, inheritedLabel: siblingLabel, controls: &controls)
    }
  }

  private static func firstLabel(in node: JSONValue) -> String? {
    guard let object = node.objectValue else { return nil }
    if object["component"]?.stringValue?.lowercased() == "vlabel" {
      return object["text"]?.stringValue
    }
    return (object["content"]?.arrayValue ?? []).lazy.compactMap { firstLabel(in: $0) }.first
  }

  private static func collectOptions(from nodes: [JSONValue]) -> [PluginFilterOption] {
    nodes.flatMap { node -> [PluginFilterOption] in
      guard let object = node.objectValue else {
        switch node {
        case .string, .int, .double, .bool:
          return [PluginFilterOption(value: node, title: node.queryString ?? "")]
        case .null, .array, .object:
          return []
        }
      }
      let component = object["component"]?.stringValue?.lowercased()
      let props = object["props"]?.objectValue ?? [:]
      if ["vchip", "vradio"].contains(component), let value = props["value"] {
        return [
          PluginFilterOption(
            value: value,
            title: object["text"]?.queryString
              ?? props["label"]?.queryString
              ?? value.queryString ?? ""
          )
        ]
      }
      if let value = object["value"] ?? props["value"] {
        let title =
          object["title"]?.queryString
          ?? object["text"]?.queryString
          ?? object["label"]?.queryString
          ?? props["title"]?.queryString
          ?? props["label"]?.queryString
          ?? value.queryString ?? ""
        return [PluginFilterOption(value: value, title: title)]
      }
      return collectOptions(from: object["content"]?.arrayValue ?? [])
    }
  }
}

// MARK: - 内容包装
enum ExploreContent {
  case media(Paginator<MediaInfo>)
  case shares(Paginator<SubscribeShare>)
}

// MARK: - 类型枚举
enum DiscoverMediaType: String, CaseIterable, Identifiable {
  case movies = "电影"
  case tvs = "电视剧"

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
  @Published private(set) var availableSources: [DiscoverSource] = []

  // TheMovieDb 筛选参数
  @Published var tmdbSortBy: String = "popularity.desc"
  @Published var tmdbGenre: String = ""
  @Published var tmdbLanguage: String = ""
  @Published var tmdbVoteAverage: Int = 0
  @Published var tmdbVoteCount: Int = 10

  // 豆瓣筛选参数
  @Published var doubanSort: String = "U"
  @Published var doubanCategory: String = ""
  @Published var doubanZone: String = ""
  @Published var doubanYear: String = ""

  // Bangumi 筛选参数
  @Published var bangumiCat: String = ""
  @Published var bangumiSort: String = "rank"
  @Published var bangumiYear: String = ""

  // AniList 筛选参数
  @Published var anilistSort: String = "POPULARITY_DESC"
  @Published var anilistGenre: String = ""
  @Published var anilistFormat: String = ""
  @Published var anilistSeason: String = ""
  @Published var anilistYear: Int = 0
  @Published var anilistStatus: String = ""
  @Published var anilistCountry: String = ""

  // 插件筛选参数
  @Published var pluginFilterValues: [String: JSONValue] = [:]
  @Published private(set) var pluginFilterControls: [PluginFilterControl] = []

  // 热门订阅筛选参数
  @Published var popularSortBy: String = "count"
  @Published var popularGenre: String = ""
  @Published var popularMinRating: Int = 0

  // 订阅分享筛选参数
  @Published var shareSortBy: String = "count"
  @Published var shareGenre: String = ""
  @Published var shareMinRating: Int = 0

  // 数据状态
  @Published private(set) var paginator: Paginator<MediaInfo>?
  @Published var selectedShare: SubscribeShare?
  @Published var forkToShow: Int?

  private let apiService: APIService

  private var cancellables = Set<AnyCancellable>()
  private var paginatorCancellable: AnyCancellable?
  private var extraSourceSnapshot: [DiscoverSourceDescriptor] = []

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    applySources()
    // 将所有筛选器的 Publisher 转换为 AnyPublisher<Void, Never>
    let filterPublishers: [AnyPublisher<Void, Never>] = [
      $selectedSource.map { _ in }.eraseToAnyPublisher(),
      $selectedType.map { _ in }.eraseToAnyPublisher(),
      $tmdbSortBy.map { _ in }.eraseToAnyPublisher(),
      $tmdbGenre.map { _ in }.eraseToAnyPublisher(),
      $tmdbLanguage.map { _ in }.eraseToAnyPublisher(),
      $tmdbVoteAverage.map { _ in }.eraseToAnyPublisher(),
      $tmdbVoteCount.map { _ in }.eraseToAnyPublisher(),
      $doubanSort.map { _ in }.eraseToAnyPublisher(),
      $doubanCategory.map { _ in }.eraseToAnyPublisher(),
      $doubanZone.map { _ in }.eraseToAnyPublisher(),
      $doubanYear.map { _ in }.eraseToAnyPublisher(),
      $bangumiCat.map { _ in }.eraseToAnyPublisher(),
      $bangumiSort.map { _ in }.eraseToAnyPublisher(),
      $bangumiYear.map { _ in }.eraseToAnyPublisher(),
      $anilistSort.map { _ in }.eraseToAnyPublisher(),
      $anilistGenre.map { _ in }.eraseToAnyPublisher(),
      $anilistFormat.map { _ in }.eraseToAnyPublisher(),
      $anilistSeason.map { _ in }.eraseToAnyPublisher(),
      $anilistYear.map { _ in }.eraseToAnyPublisher(),
      $anilistStatus.map { _ in }.eraseToAnyPublisher(),
      $anilistCountry.map { _ in }.eraseToAnyPublisher(),
      $pluginFilterValues.map { _ in }.eraseToAnyPublisher(),
      $popularSortBy.map { _ in }.eraseToAnyPublisher(),
      $popularGenre.map { _ in }.eraseToAnyPublisher(),
      $popularMinRating.map { _ in }.eraseToAnyPublisher(),
      $shareSortBy.map { _ in }.eraseToAnyPublisher(),
      $shareGenre.map { _ in }.eraseToAnyPublisher(),
      $shareMinRating.map { _ in }.eraseToAnyPublisher(),
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
    ("popularity.desc", "热度降序"),
    ("popularity.asc", "热度升序"),
    ("release_date.desc", "上映日期降序"),
    ("release_date.asc", "上映日期升序"),
    ("vote_average.desc", "评分降序"),
    ("vote_average.asc", "评分升序"),
  ]

  static let tmdbTvSortDict: [(key: String, value: String)] = [
    ("popularity.desc", "热度降序"),
    ("popularity.asc", "热度升序"),
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
    ("U", "综合排序"),
    ("R", "首播时间"),
    ("T", "近期热度"),
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
    let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
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
    let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
    return (0..<10).map { i in
      let year = String(currentYear - i)
      return (key: year, value: year)
    }
  }

  // MARK: - AniList 字典

  static let anilistSortDict: [(key: String, value: String)] = [
    ("POPULARITY_DESC", "热门优先"),
    ("TRENDING_DESC", "趋势优先"),
    ("SCORE_DESC", "评分优先"),
    ("START_DATE_DESC", "最新开播"),
  ]

  static let anilistGenreDict: [(key: String, value: String)] = [
    ("Action", "动作"),
    ("Adventure", "冒险"),
    ("Comedy", "喜剧"),
    ("Drama", "剧情"),
    ("Fantasy", "奇幻"),
    ("Horror", "恐怖"),
    ("Mahou Shoujo", "魔法少女"),
    ("Mecha", "机甲"),
    ("Music", "音乐"),
    ("Mystery", "悬疑"),
    ("Psychological", "心理"),
    ("Romance", "爱情"),
    ("Sci-Fi", "科幻"),
    ("Slice of Life", "日常"),
    ("Sports", "运动"),
    ("Supernatural", "超自然"),
    ("Thriller", "惊悚"),
  ]

  static let anilistFormatDict: [(key: String, value: String)] = [
    ("TV", "TV"),
    ("TV_SHORT", "短篇 TV"),
    ("MOVIE", "剧场版"),
    ("OVA", "OVA"),
    ("ONA", "ONA"),
    ("SPECIAL", "特别篇"),
    ("MUSIC", "音乐"),
  ]

  static let anilistSeasonDict: [(key: String, value: String)] = [
    ("WINTER", "冬季"), ("SPRING", "春季"), ("SUMMER", "夏季"), ("FALL", "秋季"),
  ]

  static var anilistYearDict: [(key: Int, value: String)] {
    let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
    return (0..<15).map { (currentYear - $0, String(currentYear - $0)) }
  }

  static let anilistStatusDict: [(key: String, value: String)] = [
    ("RELEASING", "连载中"), ("FINISHED", "已完结"), ("NOT_YET_RELEASED", "未播出"),
  ]

  static let anilistCountryDict: [(key: String, value: String)] = [
    ("JP", "日本"), ("CN", "中国大陆"), ("KR", "韩国"), ("TW", "中国台湾"),
  ]

  // MARK: - Popular & Share 字典
  static let popularSortDict: [(key: String, value: String)] = [
    ("count", "热度"),
    ("time", "时间"),
    ("rating", "评分"),
  ]

  static let shareSortDict: [(key: String, value: String)] = [
    ("count", "热度"),
    ("time", "时间"),
    ("rating", "评分"),
  ]

  // MARK: - 计算属性

  var currentSortDict: [(key: String, value: String)] {
    switch selectedSource {
    case .themoviedb:
      return selectedType == .movies ? Self.tmdbMovieSortDict : Self.tmdbTvSortDict
    case .douban:
      return Self.doubanSortDict
    case .bangumi:
      return Self.bangumiSortDict
    case .anilist:
      return Self.anilistSortDict
    case .popular:
      return Self.popularSortDict
    case .subscriptionShare:
      return Self.shareSortDict
    case .custom:
      return []
    }
  }

  var currentGenreDict: [(key: String, value: String)] {
    switch selectedSource {
    case .themoviedb, .popular:
      return selectedType == .movies ? Self.tmdbMovieGenreDict : Self.tmdbTvGenreDict
    case .subscriptionShare:
      var seen = Set<String>()
      return (Self.tmdbMovieGenreDict + Self.tmdbTvGenreDict).filter {
        seen.insert($0.key).inserted
      }
    case .douban:
      return Self.doubanCategoryDict
    case .bangumi:
      return Self.bangumiCatDict
    case .anilist:
      return Self.anilistGenreDict
    case .custom:
      return []
    }
  }

  // MARK: - API 路径构建

  func buildApiPath() -> String {
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
      params.append("vote_average=\(tmdbVoteAverage)")
      params.append("vote_count=\(tmdbVoteCount)")

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

    case .anilist:
      return Self.appendingQuery(
        to: "anilist/discover",
        values: [
          "sort": .string(anilistSort),
          "genre": anilistGenre.isEmpty ? .null : .string(anilistGenre),
          "format": anilistFormat.isEmpty ? .null : .string(anilistFormat),
          "season": anilistSeason.isEmpty ? .null : .string(anilistSeason),
          "season_year": anilistYear == 0 ? .null : .int(anilistYear),
          "status": anilistStatus.isEmpty ? .null : .string(anilistStatus),
          "country": anilistCountry.isEmpty ? .null : .string(anilistCountry),
        ])

    case .popular:
      var path = "subscribe/popular"
      var params: [String] = ["count=30"]
      params.append("stype=\(selectedType == .movies ? "电影" : "电视剧")")
      if !popularSortBy.isEmpty {
        params.append("sort_type=\(popularSortBy)")
      }
      if !popularGenre.isEmpty {
        params.append("genre_id=\(popularGenre)")
      }
      if popularMinRating > 0 {
        params.append("min_rating=\(popularMinRating)")
      }

      if !params.isEmpty {
        path += "?" + params.joined(separator: "&")
      }
      return path
    case .subscriptionShare:
      var path = "subscribe/shares"
      var params: [String] = []
      if !shareSortBy.isEmpty {
        params.append("sort_type=\(shareSortBy)")
      }
      if !shareGenre.isEmpty {
        params.append("genre_id=\(shareGenre)")
      }
      if shareMinRating > 0 {
        params.append("min_rating=\(shareMinRating)")
      }
      if !params.isEmpty {
        path += "?" + params.joined(separator: "&")
      }
      return path
    case .custom(let source):
      return Self.appendingQuery(to: source.api_path, values: pluginFilterValues)
    }
  }

  nonisolated static func appendingQuery(
    to path: String,
    values: [String: JSONValue]
  ) -> String {
    guard var components = URLComponents(string: path) else { return path }
    var params: [String: String?] = [:]
    for (key, value) in values {
      params[key] = value.queryString
    }
    appendPercentEncodedQueryParams(to: &components, params: params)
    return components.string ?? path
  }

  nonisolated static func popularSubscriptionKey(_ item: MediaInfo) -> String {
    let structuredPrefix =
      item.mediaid_prefix.flatMap { $0.isEmpty ? nil : $0 }
      ?? item.source.flatMap { $0.isEmpty ? nil : $0 }

    let mediaID: String
    if let id = item.media_id, !id.isEmpty, let prefix = structuredPrefix {
      mediaID = "\(prefix == "themoviedb" ? "tmdb" : prefix):\(id)"
    } else if let id = item.tmdb_id, id != 0 {
      mediaID = "tmdb:\(id)"
    } else if let id = item.douban_id, !id.isEmpty {
      mediaID = "douban:\(id)"
    } else if let id = item.bangumi_id, id != 0 {
      mediaID = "bangumi:\(id)"
    } else if let id = item.anilist_id, id != 0 {
      mediaID = "anilist:\(id)"
    } else {
      mediaID = "\(item.mediaid_prefix ?? "media"):\(item.title ?? "")"
    }

    return "\(item.source ?? "unknown"):\(mediaID):season:\(item.season.map(String.init) ?? "all")"
  }

  // MARK: - 数据加载

  private func setupPaginator(for path: String) {
    paginator?.cancel()
    paginatorCancellable?.cancel()
    guard apiService.canAccess(.discovery) else {
      paginator = nil
      return
    }

    var seenKeys = Set<String>()
    let source = selectedSource
    guard source != .subscriptionShare || apiService.canAccess(.subscribe) else {
      paginator = nil
      return
    }

    let newPaginator = Paginator<MediaInfo>(
      threshold: 24,
      fetcher: { @MainActor [apiService, source, path] page in
        switch source {
        case .subscriptionShare:
          let shares = try await apiService.fetchSubscriptionShares(path: path, page: page)
          return shares.map { $0.toMediaInfo() }
        case .themoviedb, .douban, .bangumi, .anilist, .popular, .custom:
          return try await apiService.fetchRecommend(path: path, page: page)
        }
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems: [MediaInfo]
        if source == .popular {
          uniqueNewItems = newItems.filter {
            seenKeys.insert(Self.popularSubscriptionKey($0)).inserted
          }
        } else if source == .subscriptionShare {
          uniqueNewItems = MediaInfo.deduplicateSubscriptionShareMedia(
            newItems,
            existingKeys: &seenKeys
          )
        } else {
          uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        }
        if uniqueNewItems.isEmpty {
          return false
        }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      imageURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
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

  func onSourceChanged(from previousSource: DiscoverSource? = nil) {
    let preservesPluginValues =
      previousSource?.id == selectedSource.id
      && previousSource?.descriptor?.filter_params == selectedSource.descriptor?.filter_params

    // 重置所有筛选参数
    selectedType = .movies
    tmdbSortBy = "popularity.desc"
    tmdbGenre = ""
    tmdbLanguage = ""
    tmdbVoteAverage = 0
    tmdbVoteCount = 10
    doubanSort = "U"
    doubanCategory = ""
    doubanZone = ""
    doubanYear = ""
    bangumiCat = ""
    bangumiSort = "rank"
    bangumiYear = ""
    anilistSort = "POPULARITY_DESC"
    anilistGenre = ""
    anilistFormat = ""
    anilistSeason = ""
    anilistYear = 0
    anilistStatus = ""
    anilistCountry = ""
    popularSortBy = "count"
    popularGenre = ""
    popularMinRating = 0
    shareSortBy = "count"
    shareGenre = ""
    shareMinRating = 0
    if let descriptor = selectedSource.descriptor {
      if !preservesPluginValues {
        pluginFilterValues = descriptor.filter_params
      }
      pluginFilterControls = PluginFilterControlParser.parse(descriptor.filter_ui)
    } else {
      pluginFilterValues = [:]
      pluginFilterControls = []
    }
  }

  func onTypeChanged() {
    // 类型变化时重置风格（因为电影和剧集的风格不同）
    tmdbGenre = ""
    doubanCategory = ""
    popularGenre = ""
  }

  func setPluginFilter(_ field: String, value: JSONValue) {
    guard let source = selectedSource.descriptor else { return }
    pluginFilterValues = Self.applyingPluginFilter(
      field: field,
      value: value,
      to: pluginFilterValues,
      defaults: source.filter_params,
      depends: source.depends
    )
  }

  nonisolated static func applyingPluginFilter(
    field: String,
    value: JSONValue,
    to values: [String: JSONValue],
    defaults: [String: JSONValue] = [:],
    depends: [String: [String]]?
  ) -> [String: JSONValue] {
    var result = values
    let oldValue = result[field]
    let defaultValue = defaults[field]
    let normalizedValue =
      !value.isTruthy && defaultValue?.isTruthy == true
      ? defaultValue ?? value
      : value
    result[field] = normalizedValue
    guard oldValue != normalizedValue, let depends else { return result }
    for (dependentField, prerequisites) in depends
    where dependentField != field && prerequisites.contains(field) {
      result[dependentField] = .null
    }
    return result
  }

  func refreshSources() async {
    guard apiService.canAccess(.discovery) else {
      applySources()
      return
    }
    do {
      let sources = try await apiService.fetchDiscoverSources()
      extraSourceSnapshot = Self.updatedExtraSourceSnapshot(
        previous: extraSourceSnapshot,
        response: sources
      )
    } catch {
      Logger.error("动态发现来源加载失败: \(error)")
      extraSourceSnapshot = Self.updatedExtraSourceSnapshot(
        previous: extraSourceSnapshot,
        response: nil
      )
    }
    applySources()
  }

  nonisolated static func updatedExtraSourceSnapshot(
    previous: [DiscoverSourceDescriptor],
    response sources: [DiscoverSourceDescriptor]?
  ) -> [DiscoverSourceDescriptor] {
    guard let sources else { return previous }
    var prefixes = Set(["themoviedb", "douban", "bangumi", "anilist"])
    return sources.filter {
      !$0.mediaid_prefix.isEmpty && prefixes.insert($0.mediaid_prefix).inserted
    }
  }

  private func applySources() {
    guard apiService.canAccess(.discovery) else {
      availableSources = []
      return
    }
    var sources = DiscoverSource.allCases.filter {
      $0 != .subscriptionShare || apiService.canAccess(.subscribe)
    }
    sources.append(contentsOf: extraSourceSnapshot.map(DiscoverSource.custom))
    availableSources = sources
    let previousSource = selectedSource
    if let source = sources.first(where: { $0.id == previousSource.id }) ?? sources.first,
      source != previousSource
    {
      selectedSource = source
      onSourceChanged(from: previousSource)
    }
  }
}
