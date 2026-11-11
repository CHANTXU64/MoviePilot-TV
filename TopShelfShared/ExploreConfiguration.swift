import Foundation

nonisolated enum DiscoverSource: Codable, Hashable, Identifiable, Sendable {
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

nonisolated enum DiscoverMediaType: String, Codable, CaseIterable, Identifiable, Sendable {
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

nonisolated struct DiscoverSourceDescriptor: Codable, Hashable, Identifiable, Sendable {
  let name: String
  let mediaid_prefix: String
  let api_path: String
  let filter_params: [String: JSONValue]
  let filter_ui: [JSONValue]
  let depends: [String: [String]]?

  var id: String { mediaid_prefix }

  init(
    name: String,
    mediaid_prefix: String,
    api_path: String,
    filter_params: [String: JSONValue],
    filter_ui: [JSONValue],
    depends: [String: [String]]?
  ) {
    self.name = name
    self.mediaid_prefix = mediaid_prefix
    self.api_path = api_path
    self.filter_params = filter_params
    self.filter_ui = filter_ui
    self.depends = depends
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    mediaid_prefix = try container.decode(String.self, forKey: .mediaid_prefix)
    api_path = try container.decode(String.self, forKey: .api_path)
    filter_params =
      try container.decodeIfPresent([String: JSONValue].self, forKey: .filter_params) ?? [:]
    filter_ui = try container.decodeIfPresent([JSONValue].self, forKey: .filter_ui) ?? []
    depends = try container.decodeIfPresent([String: [String]].self, forKey: .depends)
  }
}

/// 探索页与主屏共用的筛选条件；保存条件后按同一请求重新获取内容。
nonisolated struct ExploreConfiguration: Codable, Hashable, Sendable {
  var selectedSource: DiscoverSource = .themoviedb
  var selectedType: DiscoverMediaType = .movies
  var tmdbSortBy: String = "popularity.desc"
  var tmdbGenre: String = ""
  var tmdbLanguage: String = ""
  var tmdbVoteAverage: Int = 0
  var tmdbVoteCount: Int = 10
  var doubanSort: String = "U"
  var doubanCategory: String = ""
  var doubanZone: String = ""
  var doubanYear: String = ""
  var bangumiCat: String = ""
  var bangumiSort: String = "rank"
  var bangumiYear: String = ""
  var anilistSort: String = "POPULARITY_DESC"
  var anilistGenre: String = ""
  var anilistFormat: String = ""
  var anilistSeason: String = ""
  var anilistYear: Int = 0
  var anilistStatus: String = ""
  var anilistCountry: String = ""
  var pluginFilterValues: [String: JSONValue] = [:]
  var popularSortBy: String = "count"
  var popularGenre: String = ""
  var popularMinRating: Int = 0
  var shareSortBy: String = "count"
  var shareGenre: String = ""
  var shareMinRating: Int = 0

  init(source: DiscoverSource = .themoviedb) {
    selectedSource = source
    pluginFilterValues = source.descriptor?.filter_params ?? [:]
  }

  var apiPath: String {
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
    var additions: [String] = []
    for key in values.keys.sorted() {
      let value = values[key]!
      flattenQueryValue(key, value, into: &additions)
    }
    guard !additions.isEmpty else { return components.string ?? path }
    let suffix = additions.joined(separator: "&")
    if let existing = components.percentEncodedQuery, !existing.isEmpty {
      components.percentEncodedQuery = existing + "&" + suffix
    } else {
      components.percentEncodedQuery = suffix
    }
    return components.string ?? path
  }

  private nonisolated static func flattenQueryValue(
    _ key: String,
    _ value: JSONValue,
    into additions: inout [String]
  ) {
    switch value {
    case .null:
      return
    case .array(let items):
      guard !items.isEmpty else { return }
      let isFlat = items.allSatisfy {
        if case .object = $0 { return false }
        if case .array = $0 { return false }
        return true
      }
      if isFlat {
        for item in items {
          flattenQueryValue(key + "[]", item, into: &additions)
        }
      } else {
        for (index, item) in items.enumerated() {
          flattenQueryValue("\(key)[\(index)]", item, into: &additions)
        }
      }
    case .object(let dictionary):
      guard !dictionary.isEmpty else { return }
      for subKey in dictionary.keys.sorted() {
        let subValue = dictionary[subKey]!
        flattenQueryValue("\(key)[\(subKey)]", subValue, into: &additions)
      }
    default:
      guard let text = value.queryString,
        let encodedName = encodeURIComponent(key),
        let encodedValue = encodeURIComponent(text)
      else { return }
      additions.append("\(encodedName)=\(encodedValue)")
    }
  }

}
