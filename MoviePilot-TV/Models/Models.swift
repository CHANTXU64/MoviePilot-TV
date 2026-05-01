import Combine
import Foundation

/// 包装类型，用于处理 API 响应中多种格式的布尔值
/// 从 Bool、Int 或 String 解码，始终编码为 Bool
struct FlexibleBool: Codable, Hashable {
  let value: Bool

  init(_ value: Bool) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      throw DecodingError.valueNotFound(
        Bool.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "期望布尔值，但发现为 null。"
        )
      )
    } else if let boolValue = try? container.decode(Bool.self) {
      self.value = boolValue
    } else if let intValue = try? container.decode(Int.self) {
      self.value = intValue != 0
    } else if let stringValue = try? container.decode(String.self) {
      let lower = stringValue.lowercased().trimmingCharacters(in: .whitespaces)
      if lower == "true" || lower == "1" || lower == "yes" || lower == "on" {
        self.value = true
      } else if lower == "false" || lower == "0" || lower == "no" || lower == "off" {
        self.value = false
      } else if lower.isEmpty || lower == "null" || lower == "none" {
        self.value = false
      } else if let intValue = Int(lower) {
        self.value = intValue != 0
      } else {
        self.value = false
      }
    } else {
      self.value = false
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

/// 包装类型，用于处理 API 响应中可能是 String 或 Int 的字段，统一转为 String。
/// 常见于 Plex 服务器中 ID 可能为数字的情况。如果是 nil 则保持为 nil。
struct FlexibleString: Codable, Hashable, ExpressibleByStringLiteral {
  let value: String

  init(_ value: String) {
    self.value = value
  }

  init(stringLiteral value: String) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      throw DecodingError.valueNotFound(
        String.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "期望字符串值，但发现为 null。"
        )
      )
    } else if let stringValue = try? container.decode(String.self) {
      self.value = stringValue
    } else if let intValue = try? container.decode(Int.self) {
      self.value = String(intValue)
    } else if let doubleValue = try? container.decode(Double.self) {
      self.value = String(doubleValue)
    } else {
      self.value = ""
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

/// 登录认证令牌
struct Token: Codable {
  /// 用户令牌
  let access_token: String
  let token_type: String
  /// 是否属于超级管理员
  let super_user: FlexibleBool?
  /// 用户名
  let user_name: String
  /// 头像
  let avatar: String?
}

/// 媒体库统计概览
struct Statistic: Codable {
  /// 电影总数
  var movie_count: Int = 0
  /// 电视剧总数
  var tv_count: Int = 0
  /// 电视剧总集数
  var episode_count: Int?
}

/// 存储空间信息
struct Storage: Codable {
  /// 总空间
  let total_storage: Int
  /// 已使用空间
  let used_storage: Int

  var percent: Double {
    guard total_storage > 0 else { return 0.0 }
    return Double(used_storage) / Double(total_storage)
  }
}

/// 下载器全局速度状态
struct DownloaderInfo: Codable {
  /// 下载速度
  var download_speed: Int = 0
  /// 上传速度
  var upload_speed: Int = 0
  /// 下载量
  var download_size: Int = 0
  /// 上传量
  var upload_size: Int = 0
  /// 剩余空间
  var free_space: Int = 0
}

struct RecognizeResponse: Codable {
  let media_info: MediaInfo?

  enum CodingKeys: String, CodingKey {
    case media_info
  }

  init(media_info: MediaInfo?) {
    self.media_info = media_info
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try container.decodeIfPresent(MediaInfoJSON.self, forKey: .media_info)
    self.media_info = raw.map(MediaInfo.init(json:))
  }
}

/// MARK: - 媒体详情相关模型

/// TMDB 单季基础元数据
struct TmdbSeason: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let poster: URL?
  }

  /// 上映日期
  let air_date: String?
  /// 总集数
  let episode_count: Int?
  /// 季名称
  let name: String?
  /// 描述
  let overview: String?
  /// 海报
  let poster_path: String?
  /// 季号
  let season_number: Int?
  /// 评分
  let vote_average: Double?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  var id: Int { season_number ?? 0 }

  enum CodingKeys: String, CodingKey {
    case air_date, episode_count, name, overview, poster_path, season_number, vote_average
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    air_date = try container.decodeIfPresent(String.self, forKey: .air_date)
    episode_count = try container.decodeIfPresent(Int.self, forKey: .episode_count)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    poster_path = try container.decodeIfPresent(String.self, forKey: .poster_path)
    season_number = try container.decodeIfPresent(Int.self, forKey: .season_number)
    vote_average = try container.decodeIfPresent(Double.self, forKey: .vote_average)

    // 计算图片 URL
    self.imageURLs = ImageURLs(
      poster: APIService.shared.getSeasonPosterURL(
        posterPath: poster_path,
        mediaPosterPath: nil
      )
    )
  }
}

/// 媒体风格分类信息
struct MediaGenre: Codable, Hashable {
  /// ID: TMDB 通常为数字 (28), 豆瓣可能为字符串 ("剧情")
  let id: String?
  /// 名称
  let name: String?

  init(from decoder: Decoder) throws {
    // 纯字符串（如 "剧情"）
    if let container = try? decoder.singleValueContainer(),
      let stringValue = try? container.decode(String.self)
    {
      self.id = nil
      self.name = stringValue
      return
    }
    // 对象：豆瓣 {id: "剧情", name: "剧情"} 或 TMDB {id: 28, name: "Action"}
    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
      if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
        self.id = String(intId)
      } else {
        self.id = try? container.decodeIfPresent(String.self, forKey: .id)
      }
      self.name = try? container.decodeIfPresent(String.self, forKey: .name)
    } else {
      self.id = nil
      self.name = nil
    }
  }
}

/// 制片国家信息
struct ProductionCountry: Codable, Hashable {
  /// ISO 3166-1 代码（目前未使用，预留用于后续查表转换中文名）
  let iso_3166_1: String?
  /// 名称
  let name: String?

  init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let stringValue = try? container.decode(String.self)
    {
      self.iso_3166_1 = nil
      self.name = stringValue
      return
    }
    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
      self.iso_3166_1 = try? container.decodeIfPresent(String.self, forKey: .iso_3166_1)
      self.name = try? container.decodeIfPresent(String.self, forKey: .name)
    } else {
      self.iso_3166_1 = nil
      self.name = nil
    }
  }
}

/// 核心媒体详情模型：汇聚多源元数据
nonisolated struct MediaInfoJSON: Codable {
  let tmdb_id: Int?
  let douban_id: String?
  let bangumi_id: Int?
  let imdb_id: String?
  let tvdb_id: Int?
  let source: String?
  let mediaid_prefix: String?
  let media_id: String?
  let title: String?
  let original_title: String?
  let original_name: String?
  let names: [String]?
  let type: String?
  let year: String?
  let season: Int?
  let poster_path: String?
  let backdrop_path: String?
  let overview: String?
  let vote_average: Double?
  let popularity: Double?
  let season_info: [TmdbSeason]?
  let collection_id: Int?
  let directors: [Person]?
  let actors: [Person]?
  let episode_group: String?
  let runtime: Int?
  let release_date: String?
  let original_language: String?
  let production_countries: [ProductionCountry]?
  let genres: [MediaGenre]?
  let category: String?
  let subscribeShare: SubscribeShare?
}

struct MediaInfo: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let poster: URL?
    let backdrop: URL?
  }

  /// TMDB ID
  let tmdb_id: Int?
  /// 豆瓣ID
  let douban_id: String?
  /// Bangumi ID
  let bangumi_id: Int?
  /// IMDB ID
  let imdb_id: String?
  /// TVDB ID
  let tvdb_id: Int?
  /// 来源：themoviedb、douban、bangumi
  let source: String?
  /// 其它媒体ID前缀
  let mediaid_prefix: String?
  /// 其它媒体ID值
  let media_id: String?
  /// 媒体标题
  let title: String?
  /// 媒体原发行标题
  let original_title: String?
  /// 原名
  let original_name: String?
  /// 别名
  let names: [String]?
  /// 类型 电影、电视剧、合集
  let type: String?
  /// 年份
  let year: String?
  /// 季号
  let season: Int?
  /// 海报图片
  let poster_path: String?
  /// 背景图片
  let backdrop_path: String?
  /// 描述
  let overview: String?
  /// 评分
  let vote_average: Double?
  /// 流行度
  let popularity: Double?
  /// 季详情
  let season_info: [TmdbSeason]?
  /// 合集ID
  let collection_id: Int?
  /// 导演
  let directors: [Person]?
  /// 演员
  let actors: [Person]?
  /// 剧集组
  let episode_group: String?
  /// 时长
  let runtime: Int?
  /// 媒体发行日期
  let release_date: String?
  /// 媒体原语种
  let original_language: String?
  /// 出品国
  let production_countries: [ProductionCountry]?
  /// 风格
  let genres: [MediaGenre]?
  /// 二级分类
  let category: String?
  /// 关联的原始订阅分享对象（如果适用）
  let subscribeShare: SubscribeShare?

  /// 稳定的内部标识符，在初始化时生成
  let id: String

  /// 预处理的无后缀标题
  let cleanedTitle: String?
  let cleanedOriginalTitle: String?
  let cleanedOriginalName: String?
  let cleanedNames: [String]?

  /// 标识当前媒体项是否为合集/系列
  let isCollection: Bool

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  /// 预编译的合集后缀正则表达式，避免重复创建提升性能
  nonisolated private static let collectionSuffixRegex = try? NSRegularExpression(
    pattern: "(（系列）|\\(系列\\)|\\s+collection)$", options: .caseInsensitive)

  enum CodingKeys: String, CodingKey {
    case tmdb_id, douban_id, bangumi_id, imdb_id, tvdb_id, source, mediaid_prefix, media_id, title,
      original_title, original_name, names,
      type, year, season, poster_path, backdrop_path,
      overview, vote_average, popularity, season_info, collection_id, directors, actors,
      episode_group, runtime, release_date, original_language, production_countries, genres,
      category, subscribeShare
  }

  init(
    tmdb_id: Int? = nil, douban_id: String? = nil, bangumi_id: Int? = nil, imdb_id: String? = nil,
    tvdb_id: Int? = nil, source: String? = nil, mediaid_prefix: String? = nil,
    media_id: String? = nil,
    title: String? = nil, original_title: String? = nil, original_name: String? = nil,
    names: [String]? = nil,
    type: String? = nil, year: String? = nil, season: Int? = nil, poster_path: String? = nil,
    backdrop_path: String? = nil,
    overview: String? = nil, vote_average: Double? = nil, popularity: Double? = nil,
    season_info: [TmdbSeason]? = nil,
    collection_id: Int? = nil, directors: [Person]? = nil, actors: [Person]? = nil,
    episode_group: String? = nil, runtime: Int? = nil, release_date: String? = nil,
    original_language: String? = nil,
    production_countries: [ProductionCountry]? = nil, genres: [MediaGenre]? = nil,
    category: String? = nil,
    subscribeShare: SubscribeShare? = nil
  ) {
    self.tmdb_id = tmdb_id
    self.douban_id = douban_id
    self.bangumi_id = bangumi_id
    self.imdb_id = imdb_id
    self.tvdb_id = tvdb_id
    self.source = source
    self.mediaid_prefix = mediaid_prefix
    self.media_id = media_id
    self.title = title
    self.original_title = original_title
    self.original_name = original_name
    self.names = names
    self.type = type
    self.year = year
    self.season = season
    self.poster_path = poster_path
    self.backdrop_path = backdrop_path
    self.overview = overview
    self.vote_average = vote_average
    self.popularity = popularity
    self.season_info = season_info
    self.collection_id = collection_id
    self.directors = directors
    self.actors = actors
    self.episode_group = episode_group
    self.runtime = runtime
    self.release_date = release_date
    self.original_language = original_language
    self.production_countries = production_countries
    self.genres = genres
    self.category = category
    self.subscribeShare = subscribeShare

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      mediaid_prefix: mediaid_prefix, media_id: media_id)

    self.isCollection = Self.checkIsCollection(type: type, collection_id: collection_id)

    let cleaned = Self.parseCleanedNames(
      isCollection: self.isCollection, title: title,
      original_title: original_title, original_name: original_name, names: names)
    self.cleanedTitle = cleaned.title
    self.cleanedOriginalTitle = cleaned.originalTitle
    self.cleanedOriginalName = cleaned.originalName
    self.cleanedNames = cleaned.names

    // 计算图片 URL
    self.imageURLs = ImageURLs(
      poster: APIService.shared.getPosterImageUrl(posterPath: poster_path),
      backdrop: APIService.shared.getBackdropImageUrl(backdropPath: backdrop_path)
    )
  }

  init(json: MediaInfoJSON) {
    self.init(
      tmdb_id: json.tmdb_id,
      douban_id: json.douban_id,
      bangumi_id: json.bangumi_id,
      imdb_id: json.imdb_id,
      tvdb_id: json.tvdb_id,
      source: json.source,
      mediaid_prefix: json.mediaid_prefix,
      media_id: json.media_id,
      title: json.title,
      original_title: json.original_title,
      original_name: json.original_name,
      names: json.names,
      type: json.type,
      year: json.year,
      season: json.season,
      poster_path: json.poster_path,
      backdrop_path: json.backdrop_path,
      overview: json.overview,
      vote_average: json.vote_average,
      popularity: json.popularity,
      season_info: json.season_info,
      collection_id: json.collection_id,
      directors: json.directors,
      actors: json.actors,
      episode_group: json.episode_group,
      runtime: json.runtime,
      release_date: json.release_date,
      original_language: json.original_language,
      production_countries: json.production_countries,
      genres: json.genres,
      category: json.category,
      subscribeShare: json.subscribeShare
    )
  }

  nonisolated init(json: MediaInfoJSON, precomputedImageURLs: ImageURLs) {
    self.tmdb_id = json.tmdb_id
    self.douban_id = json.douban_id
    self.bangumi_id = json.bangumi_id
    self.imdb_id = json.imdb_id
    self.tvdb_id = json.tvdb_id
    self.source = json.source
    self.mediaid_prefix = json.mediaid_prefix
    self.media_id = json.media_id
    self.title = json.title
    self.original_title = json.original_title
    self.original_name = json.original_name
    self.names = json.names
    self.type = json.type
    self.year = json.year
    self.season = json.season
    self.poster_path = json.poster_path
    self.backdrop_path = json.backdrop_path
    self.overview = json.overview
    self.vote_average = json.vote_average
    self.popularity = json.popularity
    self.season_info = json.season_info
    self.collection_id = json.collection_id
    self.directors = json.directors
    self.actors = json.actors
    self.episode_group = json.episode_group
    self.runtime = json.runtime
    self.release_date = json.release_date
    self.original_language = json.original_language
    self.production_countries = json.production_countries
    self.genres = json.genres
    self.category = json.category
    self.subscribeShare = json.subscribeShare

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      mediaid_prefix: mediaid_prefix, media_id: media_id)

    self.isCollection = Self.checkIsCollection(type: type, collection_id: collection_id)

    let cleaned = Self.parseCleanedNames(
      isCollection: self.isCollection, title: title,
      original_title: original_title, original_name: original_name, names: names)
    self.cleanedTitle = cleaned.title
    self.cleanedOriginalTitle = cleaned.originalTitle
    self.cleanedOriginalName = cleaned.originalName
    self.cleanedNames = cleaned.names

    self.imageURLs = precomputedImageURLs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    tmdb_id = try container.decodeIfPresent(Int.self, forKey: .tmdb_id)
    douban_id = try container.decodeIfPresent(String.self, forKey: .douban_id)
    bangumi_id = try container.decodeIfPresent(Int.self, forKey: .bangumi_id)
    imdb_id = try container.decodeIfPresent(String.self, forKey: .imdb_id)
    tvdb_id = try container.decodeIfPresent(Int.self, forKey: .tvdb_id)
    source = try container.decodeIfPresent(String.self, forKey: .source)
    mediaid_prefix = try container.decodeIfPresent(String.self, forKey: .mediaid_prefix)
    media_id = try container.decodeIfPresent(String.self, forKey: .media_id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    original_title = try container.decodeIfPresent(String.self, forKey: .original_title)
    original_name = try container.decodeIfPresent(String.self, forKey: .original_name)
    names = try container.decodeIfPresent([String].self, forKey: .names)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    year = try container.decodeIfPresent(String.self, forKey: .year)
    season = try container.decodeIfPresent(Int.self, forKey: .season)
    poster_path = try container.decodeIfPresent(String.self, forKey: .poster_path)
    backdrop_path = try container.decodeIfPresent(String.self, forKey: .backdrop_path)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    vote_average = try container.decodeIfPresent(Double.self, forKey: .vote_average)
    popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
    season_info = try container.decodeIfPresent([TmdbSeason].self, forKey: .season_info)
    collection_id = try container.decodeIfPresent(Int.self, forKey: .collection_id)
    directors = try container.decodeIfPresent([Person].self, forKey: .directors)
    actors = try container.decodeIfPresent([Person].self, forKey: .actors)
    episode_group = try container.decodeIfPresent(String.self, forKey: .episode_group)
    runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
    release_date = try container.decodeIfPresent(String.self, forKey: .release_date)
    original_language = try container.decodeIfPresent(String.self, forKey: .original_language)
    production_countries = try container.decodeIfPresent(
      [ProductionCountry].self, forKey: .production_countries)
    genres = try container.decodeIfPresent([MediaGenre].self, forKey: .genres)
    category = try container.decodeIfPresent(String.self, forKey: .category)
    subscribeShare = try container.decodeIfPresent(SubscribeShare.self, forKey: .subscribeShare)

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      mediaid_prefix: mediaid_prefix, media_id: media_id)

    self.isCollection = Self.checkIsCollection(type: type, collection_id: collection_id)

    let cleaned = Self.parseCleanedNames(
      isCollection: self.isCollection, title: title,
      original_title: original_title, original_name: original_name, names: names)
    self.cleanedTitle = cleaned.title
    self.cleanedOriginalTitle = cleaned.originalTitle
    self.cleanedOriginalName = cleaned.originalName
    self.cleanedNames = cleaned.names

    // 计算图片 URL
    self.imageURLs = ImageURLs(
      poster: APIService.shared.getPosterImageUrl(posterPath: poster_path),
      backdrop: APIService.shared.getBackdropImageUrl(backdropPath: backdrop_path)
    )
  }

  nonisolated private static func parseCleanedNames(
    isCollection: Bool, title: String?, original_title: String?,
    original_name: String?, names: [String]?
  ) -> (title: String?, originalTitle: String?, originalName: String?, names: [String]?) {
    if isCollection, let regex = collectionSuffixRegex {
      let cleanTitle =
        title.map {
          regex.stringByReplacingMatches(
            in: $0, options: [], range: NSRange($0.startIndex..., in: $0), withTemplate: ""
          ).trimmingCharacters(in: .whitespaces)
        } ?? title
      let cleanOriginalTitle =
        original_title.map {
          regex.stringByReplacingMatches(
            in: $0, options: [], range: NSRange($0.startIndex..., in: $0), withTemplate: ""
          ).trimmingCharacters(in: .whitespaces)
        } ?? original_title
      let cleanOriginalName =
        original_name.map {
          regex.stringByReplacingMatches(
            in: $0, options: [], range: NSRange($0.startIndex..., in: $0), withTemplate: ""
          ).trimmingCharacters(in: .whitespaces)
        } ?? original_name
      let cleanNames = names?.map {
        regex.stringByReplacingMatches(
          in: $0, options: [], range: NSRange($0.startIndex..., in: $0), withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)
      }
      return (cleanTitle, cleanOriginalTitle, cleanOriginalName, cleanNames)
    } else {
      return (title, original_title, original_name, names)
    }
  }

  /// 参考 Vue 前端 dedupFields 去重 key
  /// 通过拼接多个核心 ID 字段生成唯一标识
  /// 用于在 UI 渲染前过滤重复项与生成 ID
  nonisolated private static func generateUniqueKey(
    source: String?, type: String?, season: Int?, tmdb_id: Int?,
    imdb_id: String?, tvdb_id: Int?, douban_id: String?, bangumi_id: Int?,
    mediaid_prefix: String?, media_id: String?
  ) -> String {
    let parts: [String] = [
      source ?? "",
      type ?? "",
      season.map { String($0) } ?? "",
      tmdb_id.map { String($0) } ?? "",
      imdb_id ?? "",
      tvdb_id.map { String($0) } ?? "",
      douban_id ?? "",
      bangumi_id.map { String($0) } ?? "",
      mediaid_prefix ?? "",
      media_id ?? "",
    ]
    return parts.joined(separator: "~")
  }

  /// 判断当前媒体项是否为合集/系列
  nonisolated static func checkIsCollection(type: String?, collection_id: Int?) -> Bool {
    return type == "合集" || type == "collection" || type == "系列" || collection_id != nil
  }

  /// 生成用于 API 请求的媒体 ID 字符串，严格遵循前端拼接逻辑。
  /// - 对应前端: `getMediaId()` in `MediaDetailView.vue` & `SubscribeSeasonDialog.vue`
  /// - 拼接规则: 优先使用 `tmdb_id`, `douban_id`, `bangumi_id`。如果都没有，则使用 `mediaid_prefix` 和 `media_id` 作为备用。
  var apiMediaId: String? {
    if let tmdbId = tmdb_id {
      return "tmdb:\(tmdbId)"
    } else if let doubanId = douban_id {
      return "douban:\(doubanId)"
    } else if let bangumiId = bangumi_id {
      return "bangumi:\(bangumiId)"
    } else if let prefix = mediaid_prefix, let id = media_id {
      return "\(prefix):\(id)"
    }
    return nil
  }

  /// 对 MediaInfo 数组去重，保留首次出现的元素
  /// 使用传入的 existingKeys 集合记录已存在的 key，实现跨分页或跨类别的去重
  static func deduplicate(_ items: [MediaInfo], existingKeys: inout Set<String>) -> [MediaInfo] {
    return items.filter { item in
      let key = item.id
      if existingKeys.contains(key) {
        return false  // 如果 key 已存在，则过滤掉
      }
      existingKeys.insert(key)  // 否则记录该 key 并保留元素
      return true
    }
  }

  /// 判断媒体是否可以直接订阅，无需选择季。
  /// - 对应前端: `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue`
  /// - 应用场景: 在前端详情页中，此逻辑用于决定是否在页面主操作区显示一个全局的“订阅”按钮。如果一个媒体项目是“电影”，或者它拥有 `douban_id` / `bangumi_id`（通常意味着它是单季动画或有明确的整季订阅单元），则会显示该按钮，允许用户一键订阅整个媒体项目，从而跳过繁琐的季选择环节。
  var canDirectlySubscribe: Bool {
    type == "电影" || douban_id != nil || bangumi_id != nil
  }

  static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

struct DownloaderConf: Codable {
  /// 名称
  let name: String
  /// 类型 qbittorrent/transmission
  let type: String
  /// 是否启用
  let enabled: FlexibleBool?
}

/// 下载任务中关联的轻量级媒体信息
struct DownloadingMediaInfo: Codable, Equatable {
  struct ImageURLs: Hashable {
    let image: URL?
  }

  let image: String?
  let title: String?
  let episode: String?
  let season: String?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case image, title, episode, season
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    image = try container.decodeIfPresent(String.self, forKey: .image)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    episode = try container.decodeIfPresent(String.self, forKey: .episode)
    season = try container.decodeIfPresent(String.self, forKey: .season)

    // 计算图片 URL
    self.imageURLs = ImageURLs(image: APIService.shared.getBackdropImageUrl(backdropPath: image))
  }
}

/// 实时下载任务详细信息
@MainActor
class DownloadingInfo: Codable, Identifiable, ObservableObject, Equatable {
  static func == (lhs: DownloadingInfo, rhs: DownloadingInfo) -> Bool {
    lhs.id == rhs.id
  }

  // --- 不可变属性 ---
  let id: String
  /// 哈希值
  let hash: String?
  /// 种子名称
  let title: String?
  /// 识别后的名称
  let name: String?
  /// 大小
  let size: Int64?
  /// 关联的媒体信息
  let media: DownloadingMediaInfo?
  // 季集格式 (如 S01E01)
  let season_episode: String?
  // 下载用户名称
  let username: String?

  // --- 易变属性，为 UI 更新发布 ---
  /// 状态
  @Published var state: String?
  /// 下载进度
  @Published var progress: Double?
  /// 下载速度
  @Published var dlspeed: String?
  /// 上传速度
  @Published var upspeed: String?
  /// 剩余时间
  @Published var left_time: String?

  enum CodingKeys: String, CodingKey {
    case hash, title, name, state, progress, dlspeed, upspeed, size, left_time, media,
      season_episode, username
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    // 解码不可变属性
    hash = try container.decodeIfPresent(String.self, forKey: .hash)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    size = try container.decodeIfPresent(Int64.self, forKey: .size)
    media = try container.decodeIfPresent(DownloadingMediaInfo.self, forKey: .media)
    season_episode = try container.decodeIfPresent(String.self, forKey: .season_episode)
    username = try container.decodeIfPresent(String.self, forKey: .username)

    // 解码可变的、@Published 的属性
    state = try container.decodeIfPresent(String.self, forKey: .state)
    progress = try container.decodeIfPresent(Double.self, forKey: .progress)
    dlspeed = try container.decodeIfPresent(String.self, forKey: .dlspeed)
    upspeed = try container.decodeIfPresent(String.self, forKey: .upspeed)
    left_time = try container.decodeIfPresent(String.self, forKey: .left_time)

    // 优先使用 hash 作为稳定标识符
    if let _hash = hash, !_hash.isEmpty {
      id = "DownloadingInfo-\(_hash)-\(username ?? "")"
    } else {
      // 备用方案：组合其他信息，确保稳定性
      let fallbackId =
        (name ?? "") + (title ?? "") + (username ?? "") + (size.map { String($0) } ?? "")
      if !fallbackId.isEmpty {
        id = "DownloadingInfo-\(fallbackId)"
      } else {
        // 最终备用，理论上不应发生
        id = "DownloadingInfo-\(UUID().uuidString)"
      }
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(hash, forKey: .hash)
    try container.encode(title, forKey: .title)
    try container.encode(name, forKey: .name)
    try container.encode(state, forKey: .state)
    try container.encode(progress, forKey: .progress)
    try container.encode(dlspeed, forKey: .dlspeed)
    try container.encode(upspeed, forKey: .upspeed)
    try container.encode(size, forKey: .size)
    try container.encode(left_time, forKey: .left_time)
    try container.encode(media, forKey: .media)
    try container.encode(season_episode, forKey: .season_episode)
    try container.encode(username, forKey: .username)
  }

  /// 仅更新下载任务的易变属性。
  func update(with other: DownloadingInfo) {
    if state != other.state { state = other.state }
    if progress != other.progress { progress = other.progress }
    if dlspeed != other.dlspeed { dlspeed = other.dlspeed }
    if upspeed != other.upspeed { upspeed = other.upspeed }
    if left_time != other.left_time { left_time = other.left_time }
  }
}

/// 种子/资源搜索结果详情
struct TorrentInfo: Codable {
  /// 站点ID
  let site: Int?
  /// 站点名称
  let site_name: String?
  /// 站点优先级
  let site_order: Int?
  /// 种子名称
  let title: String?
  /// 种子副标题
  let description: String?
  /// 种子链接
  let enclosure: String?
  // 详情页面
  let page_url: String?
  /// 种子大小
  let size: Int64
  /// 做种者
  let seeders: Int?
  /// 下载者
  let peers: Int?
  /// 发布时间
  let pubdate: String?
  /// 上传因子
  let uploadvolumefactor: Double
  /// 下载因子
  let downloadvolumefactor: Double
  /// 种子优先级
  let pri_order: Int?
  /// 种子标签
  let labels: [String]?
  /// 促销描述
  let volume_factor: String?
}

/// 媒体元数据解析结果
struct MetaInfo: Codable {
  /// 原标题（未经识别词转换）
  let title: String?
  /// 年份
  let year: String?
  /// 识别的制作组/字幕组
  let resource_team: String?
  /// 视频编码
  let video_encode: String?
  /// 识别的分辨率
  let resource_pix: String?
  /// 名称（自动中英文）
  let name: String
  /// 季集格式 (如 S01E01)
  let season_episode: String
  /// 副标题
  let subtitle: String?
  /// 流媒体平台
  let web_source: String?
  /// 资源类型+特效
  let edition: String?
  /// 总季数
  let total_season: Int?
  /// 总集数
  let total_episode: Int?
}

/// 站点配置信息
struct Site: Codable, Identifiable, Hashable {
  /// ID
  let id: Int
  /// 站点名称
  let name: String
  /// 站点主域名Key
  let domain: String?
  /// 站点地址
  let url: String?
  /// 下载器
  let downloader: String?
  /// 是否启用
  let is_active: FlexibleBool?
}

/// 搜索结果上下文：结合了媒体、种子、和元数据信息
struct Context: Codable, Identifiable {
  /// 媒体信息
  let media_info: MediaInfo?
  /// 种子信息
  let torrent_info: TorrentInfo?
  /// 元信息
  let meta_info: MetaInfo?

  let id: String

  enum CodingKeys: String, CodingKey {
    case media_info, torrent_info, meta_info
  }

  init(media_info: MediaInfo? = nil, torrent_info: TorrentInfo? = nil, meta_info: MetaInfo? = nil) {
    self.media_info = media_info
    self.torrent_info = torrent_info
    self.meta_info = meta_info
    self.id = UUID().uuidString
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    media_info = try container.decodeIfPresent(MediaInfo.self, forKey: .media_info)
    torrent_info = try container.decodeIfPresent(TorrentInfo.self, forKey: .torrent_info)
    meta_info = try container.decodeIfPresent(MetaInfo.self, forKey: .meta_info)

    // 优先使用 page_url, pubdate, enclosure 组合作为稳定标识符
    let pageUrl = torrent_info?.page_url ?? ""
    let pubdate = torrent_info?.pubdate ?? ""
    let enclosure = torrent_info?.enclosure ?? ""
    if !pageUrl.isEmpty || !pubdate.isEmpty || !enclosure.isEmpty {
      self.id = "Context-\(pageUrl)-\(pubdate)-\(enclosure)"
    } else {
      self.id = UUID().uuidString
    }
  }
}

struct MediaServerConf: Codable {
  /// 名称
  let name: String
  /// 类型 emby/jellyfin/plex
  let type: String
  /// 是否启用
  let enabled: FlexibleBool?
}

/// 媒体服务器类型（采用结构体模拟枚举，以保证向后兼容性）
struct MediaServerType: RawRepresentable, Codable, Hashable, Equatable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }

  static let emby = MediaServerType(rawValue: "emby")
  static let jellyfin = MediaServerType(rawValue: "jellyfin")
  static let plex = MediaServerType(rawValue: "plex")
  static let trimemedia = MediaServerType(rawValue: "trimemedia")
  static let ugreen = MediaServerType(rawValue: "ugreen")
}

/// 媒体服务器最近播放/新增项
struct MediaServerPlayItem: Codable, Identifiable, Equatable {
  struct ImageURLs: Hashable {
    let image: URL?
  }

  /// 真实接口返回的原始 ID（保留，以便未来跳转或 API 请求使用）
  let raw_id: FlexibleString?
  /// SwiftUI 需要的稳定唯一表示符（组合原始 id 和 link）
  let id: String
  /// 标题
  let title: String
  /// 副标题
  let subtitle: String?
  /// 类型
  let type: String?
  /// 海报
  let image: String?
  /// 链接
  let link: String?
  /// 图片是否需要Cookies
  let use_cookies: FlexibleBool?
  /// 媒体服务器类型
  let server_type: MediaServerType?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case raw_id = "id"
    case title, subtitle, type, image, link, use_cookies, server_type
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    raw_id = try container.decodeIfPresent(FlexibleString.self, forKey: .raw_id)
    title = try container.decode(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    image = try container.decodeIfPresent(String.self, forKey: .image)
    link = try container.decodeIfPresent(String.self, forKey: .link)
    use_cookies = try container.decodeIfPresent(FlexibleBool.self, forKey: .use_cookies)
    server_type = try container.decodeIfPresent(MediaServerType.self, forKey: .server_type)

    // 组合原始ID和Link生成唯一的稳定标识符，防止 tvOS 焦点异常
    let baseId = raw_id?.value ?? ""
    let baseLink = link ?? ""
    if !baseId.isEmpty || !baseLink.isEmpty {
      self.id = "playitem-\(baseId)-\(baseLink)"
    } else {
      self.id = UUID().uuidString
    }

    // 计算图片 URL
    self.imageURLs = ImageURLs(
      image: APIService.shared.getMediaServerPosterImageURL(
        image: image, useCookies: use_cookies?.value))
  }

  /// 供手动构造使用的 init (常用于 Preview 或 Mock)
  init(
    id: String, title: String, subtitle: String? = nil, type: String? = nil, image: String? = nil,
    link: String? = nil, use_cookies: FlexibleBool? = nil, server_type: MediaServerType? = nil
  ) {
    self.raw_id = FlexibleString(id)
    self.id = "playitem-\(id)-\(link ?? "")"
    self.title = title
    self.subtitle = subtitle
    self.type = type
    self.image = image
    self.link = link
    self.use_cookies = use_cookies
    self.server_type = server_type

    // 计算图片 URL
    self.imageURLs = ImageURLs(
      image: APIService.shared.getMediaServerPosterImageURL(
        image: image, useCookies: use_cookies?.value))
  }
}

/// 数据转移/保存路径配置
struct TransferDirectoryConf: Codable, Hashable {
  /// 名称
  let name: String
  /// 存储
  let storage: String
  /// 下载目录
  let download_path: String?
  /// 整理到媒体库目录
  let library_path: String?
  /// 存储
  let library_storage: String?
  /// 转移方式
  let transfer_type: String
  /// 是否刮削
  let scraping: FlexibleBool?
  /// 分类目录
  let library_category_folder: FlexibleBool?
  /// 类型目录
  let library_type_folder: FlexibleBool?
}

struct FilterRuleGroup: Codable, Hashable {
  /// 名称
  let name: String
}

struct SubscribeRequest: Codable {
  /// 名称
  let name: String
  /// 类型
  let type: String
  /// 年份
  let year: String?
  /// TMDB ID
  let tmdbid: Int?
  /// 豆瓣ID
  let doubanid: String?
  /// Bangumi ID
  let bangumiid: Int?
  /// 季号
  let season: Int?
  /// 是否洗版，数字或者boolean
  let best_version: Int
  /// 剧集组
  let episode_group: String?
}

/// 订阅详细配置数据
struct Subscribe: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let poster: URL?
  }

  /// 订阅ID
  var id: Int?
  /// 订阅名称
  var name: String
  /// 订阅年份
  var year: String?
  /// 订阅类型 电影/电视剧
  var type: String
  /// 搜索关键字
  var keyword: String?
  /// 季号
  var season: Int?
  /// 海报
  var poster: String?
  // 背景图
  var backdrop: String?
  /// 状态：N-新建 R-订阅中 P-待定 S-暂停
  var state: String?
  // 最后更新时间
  var last_update: String?
  /// 总集数
  var total_episode: Int?
  /// 开始集数
  var start_episode: Int?
  /// 缺失集数
  var lack_episode: Int?
  /// TMDB ID
  var tmdbid: Int?
  /// 豆瓣ID
  var doubanid: String?
  /// Bangumi ID
  var bangumiid: Int?
  /// 质量
  var quality: String?
  /// 分辨率
  var resolution: String?
  /// 特效
  var effect: String?
  /// 包含
  var include: String?
  /// 排除
  var exclude: String?
  /// 订阅站点
  var sites: [Int]?
  /// 下载器
  var downloader: String?
  /// 保存目录
  var save_path: String?
  /// 是否洗版 (后端返回 0/1 整数作为布尔值使用)
  var best_version: Int?
  /// 过滤规则组
  var filter_groups: [String]?
  /// 自定义识别词
  var custom_words: String?
  /// 描述
  var description: String?
  /// 自定义剧集组
  var episode_group: String?
  /// 使用 imdbid 搜索
  var search_imdbid: Int?
  /// 自定义媒体类别
  var media_category: String?

  /// 媒体ID标识 (如 tmdb:1234)
  var mediaid: String?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case id, name, year, type, keyword, season, poster, backdrop, state, last_update,
      total_episode, start_episode, lack_episode, tmdbid, doubanid, bangumiid, quality, resolution,
      effect, include, exclude, sites, downloader, save_path, best_version, filter_groups,
      custom_words, description, episode_group, search_imdbid, media_category, mediaid
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    year = try container.decodeIfPresent(String.self, forKey: .year)
    type = try container.decode(String.self, forKey: .type)
    keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
    season = try container.decodeIfPresent(Int.self, forKey: .season)
    poster = try container.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop)
    state = try container.decodeIfPresent(String.self, forKey: .state)
    last_update = try container.decodeIfPresent(String.self, forKey: .last_update)
    total_episode = try container.decodeIfPresent(Int.self, forKey: .total_episode)
    start_episode = try container.decodeIfPresent(Int.self, forKey: .start_episode)
    lack_episode = try container.decodeIfPresent(Int.self, forKey: .lack_episode)
    tmdbid = try container.decodeIfPresent(Int.self, forKey: .tmdbid)
    doubanid = try container.decodeIfPresent(String.self, forKey: .doubanid)
    bangumiid = try container.decodeIfPresent(Int.self, forKey: .bangumiid)
    quality = try container.decodeIfPresent(String.self, forKey: .quality)
    resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
    effect = try container.decodeIfPresent(String.self, forKey: .effect)
    include = try container.decodeIfPresent(String.self, forKey: .include)
    exclude = try container.decodeIfPresent(String.self, forKey: .exclude)
    sites = try container.decodeIfPresent([Int].self, forKey: .sites)
    downloader = try container.decodeIfPresent(String.self, forKey: .downloader)
    save_path = try container.decodeIfPresent(String.self, forKey: .save_path)
    best_version = try container.decodeIfPresent(Int.self, forKey: .best_version)
    filter_groups = try container.decodeIfPresent([String].self, forKey: .filter_groups)
    custom_words = try container.decodeIfPresent(String.self, forKey: .custom_words)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    episode_group = try container.decodeIfPresent(String.self, forKey: .episode_group)
    search_imdbid = try container.decodeIfPresent(Int.self, forKey: .search_imdbid)
    media_category = try container.decodeIfPresent(String.self, forKey: .media_category)
    mediaid = try container.decodeIfPresent(String.self, forKey: .mediaid)

    // 计算图片 URL
    self.imageURLs = ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  /// 成员初始化器，用于手动创建订阅。
  init(
    id: Int? = nil, name: String, year: String? = nil, type: String, season: Int? = nil,
    poster: String? = nil, state: String? = nil, last_update: String? = nil,
    tmdbid: Int? = nil, doubanid: String? = nil, bangumiid: Int? = nil,
    best_version: Int? = nil, episode_group: String? = nil,
    backdrop: String? = nil, keyword: String? = nil, total_episode: Int? = nil,
    start_episode: Int? = nil, lack_episode: Int? = nil, quality: String? = nil,
    resolution: String? = nil, effect: String? = nil, include: String? = nil,
    exclude: String? = nil, sites: [Int]? = nil, downloader: String? = nil,
    save_path: String? = nil, filter_groups: [String]? = nil,
    custom_words: String? = nil, description: String? = nil,
    search_imdbid: Int? = nil, media_category: String? = nil, mediaid: String? = nil
  ) {
    self.id = id
    self.name = name
    self.year = year
    self.type = type
    self.season = season
    self.poster = poster
    self.state = state
    self.last_update = last_update
    self.tmdbid = tmdbid
    self.doubanid = doubanid
    self.bangumiid = bangumiid
    self.best_version = best_version
    self.episode_group = episode_group
    self.backdrop = backdrop
    self.keyword = keyword
    self.total_episode = total_episode
    self.start_episode = start_episode
    self.lack_episode = lack_episode
    self.quality = quality
    self.resolution = resolution
    self.effect = effect
    self.include = include
    self.exclude = exclude
    self.sites = sites
    self.downloader = downloader
    self.save_path = save_path
    self.filter_groups = filter_groups
    self.custom_words = custom_words
    self.description = description
    self.search_imdbid = search_imdbid
    self.media_category = media_category
    self.mediaid = mediaid

    // 计算图片 URL
    self.imageURLs = ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  /// 动态计算媒体ID，确保与前端逻辑一致
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue (getMediaId)
  /// - 拼接规则: 优先使用原始ID（tmdbid, doubanid, bangumiid）拼接，如果都没有，则直接使用接口返回的 `mediaid` 字段作为备用。
  var apiMediaId: String? {
    if let tmdbid = self.tmdbid { return "tmdb:\(tmdbid)" }
    if let doubanid = self.doubanid { return "douban:\(doubanid)" }
    if let bangumiid = self.bangumiid { return "bangumi:\(bangumiid)" }
    return mediaid
  }
}

/// 剧集分组信息（分季订阅逻辑）
struct EpisodeGroup: Codable, Identifiable, Hashable {
  let id: String
  let name: String
  let group_count: Int
  let episode_count: Int

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let idInt = try? container.decode(Int.self, forKey: .id) {
      self.id = String(idInt)
    } else {
      self.id = try container.decode(String.self, forKey: .id)
    }
    self.name = try container.decode(String.self, forKey: .name)
    self.group_count = try container.decode(Int.self, forKey: .group_count)
    self.episode_count = try container.decode(Int.self, forKey: .episode_count)
  }

  enum CodingKeys: String, CodingKey {
    case id, name, group_count, episode_count
  }
}

struct AddDownloadRequest: Codable {
  let torrent_in: TorrentInfo
  let downloader: String?
  let save_path: String?
  let media_in: MediaInfo?
  let tmdbid: Int?
  let doubanid: String?
}

/// 演职人员模型
struct Person: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let profile: URL?
  }

  /// 来源：themoviedb、douban、bangumi
  let source: String?
  /// ID
  let raw_id: String?
  /// 名称
  let name: String?
  /// 别名
  let latin_name: String?
  /// 角色
  var character: String?
  /// TMDB job
  var job: String?
  // douban
  // 角色
  let roles: [String]?
  /// themoviedb图片
  let profile_path: String?
  /// 原名
  let original_name: String?
  /// 部门
  let known_for_department: String?
  /// 出生地
  let place_of_birth: String?
  /// 热度
  let popularity: Double?
  /// 详情
  let biography: String?
  /// 生日
  let birthday: String?
  /// 别名
  let also_known_as: [String]?
  /// 图片
  let avatar: PersonAvatar?
  /// 图片资源（大图/常规），适用于豆瓣、Bangumi 平台
  let images: BangumiImages?

  // 计算属性作为 Identifiable 的 ID，保证稳定性
  let id: String

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case source
    case raw_id = "id"
    case name
    case latin_name
    case character
    case job
    case roles
    case profile_path
    case original_name
    case known_for_department
    case place_of_birth
    case popularity
    case biography
    case birthday
    case also_known_as
    case avatar
    case images
  }

  init(from decoder: Decoder) throws {
    // 性能优化：首先检查容器类型
    if let container = try? decoder.singleValueContainer(),
      let nameString = try? container.decode(String.self)
    {
      self.source = nil
      self.raw_id = nil
      self.name = nameString
      self.latin_name = nil
      self.character = nil
      self.job = nil
      self.roles = nil
      self.profile_path = nil
      self.original_name = nil
      self.known_for_department = nil
      self.place_of_birth = nil
      self.popularity = nil
      self.biography = nil
      self.birthday = nil
      self.also_known_as = nil
      self.avatar = nil
      self.images = nil
      self.id = "name-\(nameString)"
      self.imageURLs = ImageURLs(profile: nil)
      return
    }

    let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
    self.source = try keyedContainer.decodeIfPresent(String.self, forKey: .source)

    // raw_id 兼容处理
    var parsedId: String? = nil
    if let idInt = try? keyedContainer.decode(Int.self, forKey: .raw_id) {
      parsedId = String(idInt)
    } else {
      parsedId = try keyedContainer.decodeIfPresent(String.self, forKey: .raw_id)
    }
    self.raw_id = parsedId

    self.name = try keyedContainer.decodeIfPresent(String.self, forKey: .name)
    self.latin_name = try keyedContainer.decodeIfPresent(String.self, forKey: .latin_name)
    self.character = try keyedContainer.decodeIfPresent(String.self, forKey: .character)
    self.job = try keyedContainer.decodeIfPresent(String.self, forKey: .job)
    self.roles = try keyedContainer.decodeIfPresent([String].self, forKey: .roles)
    self.profile_path = try keyedContainer.decodeIfPresent(String.self, forKey: .profile_path)
    self.original_name = try keyedContainer.decodeIfPresent(String.self, forKey: .original_name)
    self.known_for_department = try keyedContainer.decodeIfPresent(
      String.self, forKey: .known_for_department)
    self.place_of_birth = try keyedContainer.decodeIfPresent(String.self, forKey: .place_of_birth)
    self.popularity = try keyedContainer.decodeIfPresent(Double.self, forKey: .popularity)
    self.biography = try keyedContainer.decodeIfPresent(String.self, forKey: .biography)
    self.birthday = try keyedContainer.decodeIfPresent(String.self, forKey: .birthday)
    self.also_known_as = try keyedContainer.decodeIfPresent([String].self, forKey: .also_known_as)
    self.avatar = try keyedContainer.decodeIfPresent(PersonAvatar.self, forKey: .avatar)
    self.images = try keyedContainer.decodeIfPresent(BangumiImages.self, forKey: .images)

    // 恢复稳定的内部标识符逻辑
    if let pid = parsedId {
      self.id = "\(self.source ?? "unknown")-\(pid)"
    } else {
      self.id = "name-\(self.name ?? UUID().uuidString)"
    }

    self.imageURLs = ImageURLs(
      profile: APIService.shared.getPersonImageURL(
        source: self.source,
        profilePath: self.profile_path,
        avatar: self.avatar,
        images: self.images
      )
    )
  }

  /// 成员初始化器，用于创建或修改演职人员实例。
  init(
    source: String?, raw_id: String?, name: String?, latin_name: String?,
    character: String?, job: String?, roles: [String]?, profile_path: String?,
    original_name: String?, known_for_department: String?, place_of_birth: String?,
    popularity: Double?, biography: String?, birthday: String?, also_known_as: [String]?,
    avatar: PersonAvatar?, images: BangumiImages?, id: String
  ) {
    self.source = source
    self.raw_id = raw_id
    self.name = name
    self.latin_name = latin_name
    self.character = character
    self.job = job
    self.roles = roles
    self.profile_path = profile_path
    self.original_name = original_name
    self.known_for_department = known_for_department
    self.place_of_birth = place_of_birth
    self.popularity = popularity
    self.biography = biography
    self.birthday = birthday
    self.also_known_as = also_known_as
    self.avatar = avatar
    self.images = images
    self.id = id

    self.imageURLs = ImageURLs(
      profile: APIService.shared.getPersonImageURL(
        source: self.source,
        profilePath: self.profile_path,
        avatar: self.avatar,
        images: self.images
      )
    )
  }

  static func == (lhs: Person, rhs: Person) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

struct BangumiImages: Codable, Hashable {
  let large: String?
  let common: String?
  let medium: String?
  let small: String?
  let grid: String?
}

/// 演职人员头像数据源
enum PersonAvatar: Codable, Hashable {
  case url(String)
  case object(normal: String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let urlString = try? container.decode(String.self) {
      self = .url(urlString)
    } else if let dict = try? container.decode([String: String].self),
      let normal = dict["normal"]
    {
      self = .object(normal: normal)
    } else {
      throw DecodingError.typeMismatch(
        PersonAvatar.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "期望字符串或带有 normal 键的对象"))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .url(let url):
      try container.encode(url)
    case .object(let normal):
      try container.encode(["normal": normal])
    }
  }
}

/// 资源搜索请求参数
struct ResourceSearchRequest: Hashable, Codable {
  let keyword: String
  let type: String?
  let area: String?
  let title: String?
  let year: String?
  let season: Int?
  let mediaInfo: MediaInfo?
  let sites: String?
}

/// 缺少的媒体库信息（检查分季状态时返回）
struct NotExistMediaInfo: Codable {
  /// 季
  let season: Int
  /// 剧集列表
  let episodes: [Int]
  /// 总集数
  let total_episode: Int
  /// 开始集
  let start_episode: Int
}

/// 全局应用设置
struct GlobalSettings: Codable {
  var TMDB_IMAGE_DOMAIN: String?
  /// ⚠️ **注意：请勿直接使用此值！**
  /// 由于 tvOS 17.x 及更早版本存在 WEBP 图片解码的兼容性问题，
  /// 关于图片缓存是否真实启用，应始终通过 `APIService.shared.useImageCache` 获取。
  /// 该属性已集成了版本判断逻辑，可确保在旧版系统上自动禁用缓存。
  var GLOBAL_IMAGE_CACHE: FlexibleBool?
  var RECOGNIZE_SOURCE: String?
  var USER_UNIQUE_ID: String?
  var SUBSCRIBE_SHARE_MANAGE: FlexibleBool?
  var AI_AGENT_ENABLE: FlexibleBool?

  enum CodingKeys: String, CodingKey {
    case TMDB_IMAGE_DOMAIN
    case GLOBAL_IMAGE_CACHE
    case RECOGNIZE_SOURCE
    case USER_UNIQUE_ID
    case SUBSCRIBE_SHARE_MANAGE
    case AI_AGENT_ENABLE
  }
}

/// 分季订阅请求参数
struct SubscribeSeasonRequest: Hashable, Codable {
  let mediaInfo: MediaInfo
  let initialSeason: Int?
}

// MARK: - Transfer History Models

struct TransferHistoryResponse: Codable {
  let list: [TransferHistory]
  let total: Int
}

struct TransferHistory: Codable, Identifiable {
  // ID
  let id: Int
  // 标题
  let title: String?
  // 类型：电影、电视剧
  let type: String?
  // 季Sxx
  let seasons: String?
  // 集Exx
  let episodes: String?
  // 二级分类
  let category: String?
  // 源目录
  let src: String?
  // 目的目录
  let dest: String?
  // 源存储
  let src_storage: String?
  // 目标存储
  let dest_storage: String?
  // 转移模式link/copy/move/softlink/rclone_copy/rclone_move
  let mode: String?
  // 状态 1-成功，0-失败
  let status: FlexibleBool
  // 失败原因
  let errmsg: String?
  // 源文件项
  let src_fileitem: FileItem?
  // 日期
  let date: String?
}

struct FileItem: Codable {
  // 文件名
  let name: String
  // 文件路径
  let path: String
  // 类型 dir/file
  let type: String
  // 文件大小
  let size: Int64?
}

struct StorageConf: Codable, Hashable {
  let name: String
  let type: String
}

/// 订阅分享
struct SubscribeShare: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let poster: URL?
  }

  // 分享ID
  var id: String
  // 内部使用的分享ID
  let raw_id: Int?
  // 订阅ID
  let subscribe_id: Int?
  // 分享标题
  let share_title: String?
  // 分享说明
  let share_comment: String?
  // 分享人
  let share_user: String?
  // 分享人唯一ID
  let share_uid: String?
  // 订阅名称
  let name: String?
  // 订阅年份
  let year: String?
  // 订阅类型 电影/电视剧
  let type: String?
  // 搜索关键字
  let keyword: String?
  // TMDB ID
  let tmdbid: Int?
  // 豆瓣ID
  let doubanid: String?
  // 季号
  let season: Int?
  // 海报
  let poster: String?
  // 背景图
  let backdrop: String?
  // 评分
  let vote: Double?
  // 描述
  let description: String?
  // 过滤规则
  let filter: String?
  // 包含
  let include: String?
  // 排除
  let exclude: String?
  // 质量
  let quality: String?
  // 分辨率
  let resolution: String?
  // 特效
  let effect: String?
  // 总集数
  let total_episode: Int?
  // 时间
  let date: String?
  // 自定义识别词
  let custom_words: String?
  // 自定义媒体类别
  let media_category: String?
  // 复用次数
  let count: Int?
  // 自定义剧集组
  let episode_group: String?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case raw_id = "id"
    case subscribe_id, share_title, share_comment, share_user, share_uid, name, year, type, keyword,
      tmdbid,
      doubanid, season, poster, backdrop, vote, description, filter, include, exclude, quality,
      resolution, effect, total_episode, date, custom_words, media_category, count,
      episode_group
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    raw_id = try container.decodeIfPresent(Int.self, forKey: .raw_id)
    subscribe_id = try container.decodeIfPresent(Int.self, forKey: .subscribe_id)
    share_title = try container.decodeIfPresent(String.self, forKey: .share_title)
    share_comment = try container.decodeIfPresent(String.self, forKey: .share_comment)
    share_user = try container.decodeIfPresent(String.self, forKey: .share_user)
    share_uid = try container.decodeIfPresent(String.self, forKey: .share_uid)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    year = try container.decodeIfPresent(String.self, forKey: .year)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
    tmdbid = try container.decodeIfPresent(Int.self, forKey: .tmdbid)
    doubanid = try container.decodeIfPresent(String.self, forKey: .doubanid)
    season = try container.decodeIfPresent(Int.self, forKey: .season)
    poster = try container.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop)
    vote = try container.decodeIfPresent(Double.self, forKey: .vote)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    filter = try container.decodeIfPresent(String.self, forKey: .filter)
    include = try container.decodeIfPresent(String.self, forKey: .include)
    exclude = try container.decodeIfPresent(String.self, forKey: .exclude)
    quality = try container.decodeIfPresent(String.self, forKey: .quality)
    resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
    effect = try container.decodeIfPresent(String.self, forKey: .effect)
    total_episode = try container.decodeIfPresent(Int.self, forKey: .total_episode)
    date = try container.decodeIfPresent(String.self, forKey: .date)
    custom_words = try container.decodeIfPresent(String.self, forKey: .custom_words)
    media_category = try container.decodeIfPresent(String.self, forKey: .media_category)
    count = try container.decodeIfPresent(Int.self, forKey: .count)
    episode_group = try container.decodeIfPresent(String.self, forKey: .episode_group)

    // 组合生成唯一的稳定标识符，防止 tvOS 焦点异常
    let baseId = raw_id.map { String($0) } ?? ""
    let baseTitle = share_title ?? ""
    let baseUser = share_user ?? ""
    if !baseId.isEmpty || !baseTitle.isEmpty || !baseUser.isEmpty {
      self.id = "Share-\(baseId)-\(baseTitle)-\(baseUser)"
    } else {
      self.id = UUID().uuidString
    }

    // 计算图片 URL
    self.imageURLs = ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  /// 转换为 MediaInfo 以便在通用视图中复用
  func toMediaInfo() -> MediaInfo {
    var combinedOverview = ""
    if let comment = share_comment, !comment.isEmpty {
      combinedOverview += "💬 \(comment)"
    }
    if let user = share_user, !user.isEmpty {
      if !combinedOverview.isEmpty {
        combinedOverview += "\n"
      }
      combinedOverview += "👤 @\(user)"
    }

    return MediaInfo(
      tmdb_id: tmdbid,
      douban_id: doubanid,
      title: share_title ?? name,
      type: type,
      year: year,
      season: season,
      poster_path: poster,
      backdrop_path: backdrop,
      overview: combinedOverview,
      vote_average: vote,
      popularity: Double(count ?? 0),  // 复用次数映射到 popularity
      subscribeShare: self
    )
  }
}

struct ReorganizeForm: Codable {
  // 文件项
  var fileitem: FileItem
  // 历史ID
  var logid: Int
  // 目标存储
  var target_storage: String
  // 整理方式
  var transfer_type: String
  // 目标路径
  var target_path: String
  // 最小文件大小
  var min_filesize: Int
  // 刮削
  var scrape: Bool
  // 复用历史识别信息
  var from_history: Bool
  // 类型
  var type_name: String?
  // TMDB ID
  var tmdbid: Int?
  // 豆瓣 ID
  var doubanid: String?
  // 剧集组编号
  var episode_group: String?
  // 季号
  var season: Int?
  // 指定集数
  var episode_detail: String?
  // 自定义格式
  var episode_format: String?
  // 集数偏移
  var episode_offset: String?
  // 指定PART
  var episode_part: String?
  // 媒体库类型子目录
  var library_type_folder: Bool?
  // 媒体库类别子目录
  var library_category_folder: Bool?
}

/// 资源搜索的流式响应事件 (SSE)
struct SearchStreamEvent: Codable {
  let type: String? // "append", "replace", "done", "error"
  let text: String?
  let value: Double?
  let enable: Bool?
  let total_items: Int?
  let items: [Context]?
  let message: String?
  
  // AI 重新整理进度使用的结构也类似，可以在需要时复用
  struct AiRedoData: Codable {
    let success: Bool?
    let error: String?
  }
  let data: AiRedoData?
}

// MARK: - 自定义过滤规则

/// 自定义过滤规则
/// - 对应后端: CustomFilterRules 配置项
/// - 应用场景: 在搜索资源后，根据用户在设置中选择的规则对结果进行前端过滤。
struct CustomRule: Codable, Identifiable, Hashable {
  /// 规则ID
  let id: String
  /// 名称
  var name: String
  /// 包含 (正则表达式)
  var include: String?
  /// 排除 (正则表达式)
  var exclude: String?
  /// 大小 (MB)，格式: "min" 或 "min-max"
  var size_range: String?
  /// 做种人数，格式: "min" 或 "min-max"
  var seeders: String?
  /// 发布时间 (分钟)，格式: "min" 或 "min-max"
  var publish_time: String?
}

/// 对应 API 的返回格式：{ "data": { "value": [...] } }
struct CustomFilterRulesResponse: Codable {
  let value: [CustomRule]
}
