import Combine
import Foundation

// MARK: - 通知名常量

extension Notification.Name {
  /// 订阅状态变更通知（新增/删除/编辑订阅后发送，首页和预加载缓存监听刷新）
  static let subscriptionDidUpdate = Notification.Name("subscriptionDidUpdate")
  /// 用户在保存订阅期间返回，保存最终成功后显示一次成功提示
  static let subscriptionSaveDidComplete = Notification.Name("subscriptionSaveDidComplete")
  /// 会话登出通知（主动登出或自动重连失败后发送，用于清理会话相关缓存）
  static let sessionDidLogout = Notification.Name("sessionDidLogout")
  /// 分页连续失败达到上限，交由全局通知提示用户自行重试
  static let paginatorDidReachErrorLimit = Notification.Name("paginatorDidReachErrorLimit")
}

nonisolated struct MediaIdentity: Hashable {
  let source: String
  let mediaId: String

  var mediaKey: String {
    "\(source == "themoviedb" ? "tmdb" : source):\(mediaId)"
  }
}

nonisolated enum MediaIdentifier {
  private static let builtInSources = ["themoviedb", "douban", "bangumi", "anilist"]

  static func normalizeSource(_ source: String?) -> String? {
    guard let source = normalizedString(source)?.lowercased() else { return nil }
    return source == "tmdb" ? "themoviedb" : source
  }

  static func resolve(
    mediaIdPrefix: String? = nil,
    source: String? = nil,
    mediaId: String? = nil,
    tmdbId: Int? = nil,
    doubanId: String? = nil,
    bangumiId: Int? = nil,
    anilistId: Int? = nil,
    legacyMediaId: String? = nil
  ) -> MediaIdentity? {
    var sourceIds: [String: String] = [:]
    sourceIds["themoviedb"] = tmdbId.map(String.init)
    sourceIds["douban"] = normalizedString(doubanId)
    sourceIds["bangumi"] = bangumiId.map(String.init)
    sourceIds["anilist"] = anilistId.map(String.init)

    var declaredSources: [String] = []
    for value in [mediaIdPrefix, source] {
      if let normalized = normalizeSource(value), !declaredSources.contains(normalized) {
        declaredSources.append(normalized)
      }
    }
    for declaredSource in declaredSources {
      let declaredId = mediaId == nil ? sourceIds[declaredSource] : normalizedString(mediaId)
      if let sourceId = declaredId {
        return MediaIdentity(source: declaredSource, mediaId: sourceId)
      }
    }
    for fallbackSource in builtInSources {
      if let fallbackId = sourceIds[fallbackSource] {
        return MediaIdentity(source: fallbackSource, mediaId: fallbackId)
      }
    }
    return identity(from: legacyMediaId)
  }

  static func resolveAuxiliaryContent(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int?
  ) -> MediaIdentity? {
    if let id = truthyNumericIdentifier(tmdbId) {
      return MediaIdentity(source: "themoviedb", mediaId: String(id))
    }
    if let id = normalizedString(doubanId) {
      return MediaIdentity(source: "douban", mediaId: id)
    }
    if let id = truthyNumericIdentifier(bangumiId) {
      return MediaIdentity(source: "bangumi", mediaId: String(id))
    }
    if let id = truthyNumericIdentifier(anilistId) {
      return MediaIdentity(source: "anilist", mediaId: String(id))
    }
    return nil
  }

  static func identity(from mediaKey: String?) -> MediaIdentity? {
    guard let components = mediaIdComponents(mediaKey),
      let source = normalizeSource(components.prefix)
    else {
      return nil
    }
    return MediaIdentity(source: source, mediaId: components.id)
  }

  static func apiMediaId(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int? = nil,
    source: String? = nil,
    mediaIdPrefix: String?,
    mediaId: String?
  ) -> String? {
    resolve(
      mediaIdPrefix: mediaIdPrefix,
      source: source,
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      bangumiId: bangumiId,
      anilistId: anilistId
    )?.mediaKey
  }

  static func apiMediaId(
    tmdbId: Int?,
    doubanId: String?,
    bangumiId: Int?,
    anilistId: Int? = nil,
    mediaSource: String? = nil,
    mediaId: String? = nil,
    fallbackMediaId: String?
  ) -> String? {
    resolve(
      source: mediaSource,
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      bangumiId: bangumiId,
      anilistId: anilistId,
      legacyMediaId: fallbackMediaId
    )?.mediaKey
  }

  static func validNumericIdentifier(_ id: Int?) -> Int? {
    guard let id, id > 0 else { return nil }
    return id
  }

  static func truthyNumericIdentifier(_ id: Int?) -> Int? {
    guard let id, id != 0 else { return nil }
    return id
  }

  static func normalizedString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func isValidManualMediaId(_ mediaId: String?) -> Bool {
    guard let mediaId = normalizedString(mediaId) else { return true }
    return mediaId.unicodeScalars.allSatisfy { (48...57).contains(Int($0.value)) }
  }

  static func normalizedMediaIdentifier(_ mediaId: String?) -> String? {
    guard let mediaId = normalizedString(mediaId), !mediaId.hasSuffix(":") else { return nil }

    return mediaId
  }

  static func mediaIdComponents(_ mediaId: String?) -> (prefix: String, id: String)? {
    guard let mediaId = normalizedMediaIdentifier(mediaId) else { return nil }
    let parts = mediaId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (String(parts[0]), String(parts[1]))
  }

}

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

nonisolated enum JSONValue: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  var queryString: String? {
    switch self {
    case .null:
      return nil
    case .bool(let value):
      return value ? "true" : "false"
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .string(let value):
      return value
    case .array, .object:
      guard let data = try? JSONEncoder().encode(self) else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }

  var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var isTruthy: Bool {
    switch self {
    case .null:
      return false
    case .bool(let value):
      return value
    case .int(let value):
      return value != 0
    case .double(let value):
      return value != 0 && !value.isNaN
    case .string(let value):
      return !value.isEmpty
    case .array, .object:
      return true
    }
  }
}

nonisolated private struct JSONCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
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

nonisolated struct RecommendSourceDescriptor: Codable, Hashable, Sendable {
  let name: String
  let api_path: String
  let type: String
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
nonisolated struct TmdbSeason: Codable, Identifiable, Hashable {
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

  /// 图片 URL 在主线程按当前图片设置计算，避免后台 JSON 解码访问主线程 APIService。
  @MainActor var imageURLs: ImageURLs {
    ImageURLs(
      poster: APIService.shared.getSeasonPosterURL(
        posterPath: poster_path,
        mediaPosterPath: nil
      )
    )
  }

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
nonisolated struct MediaInfoJSON: Decodable {
  let tmdb_id: Int?
  let douban_id: String?
  let bangumi_id: Int?
  let anilist_id: Int?
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
  let rawPayload: [String: JSONValue]

  init(from decoder: Decoder) throws {
    rawPayload =
      (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
    let container = try decoder.container(keyedBy: MediaInfo.CodingKeys.self)
    tmdb_id = try container.decodeIfPresent(Int.self, forKey: .tmdb_id)
    douban_id = try container.decodeIfPresent(String.self, forKey: .douban_id)
    bangumi_id = try container.decodeIfPresent(Int.self, forKey: .bangumi_id)
    anilist_id = try container.decodeIfPresent(Int.self, forKey: .anilist_id)
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
  }
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
  /// AniList ID
  let anilist_id: Int?
  /// IMDB ID
  let imdb_id: String?
  /// TVDB ID
  let tvdb_id: Int?
  /// 来源：themoviedb、douban、bangumi、anilist 或插件来源
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
  /// Web 会把插件媒体对象直接作为 `media_in` 回传；保留未建模字段以免丢失插件契约。
  private let rawPayload: [String: JSONValue]?

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

  var displayTypeText: String? {
    isCollection || Self.checkDisplaysAsCollection(type: type) ? "合集" : type
  }

  var shouldPreloadDetail: Bool {
    !isCollection
  }

  /// 兼容旧后端内嵌人物未携带 source 的载荷；只继承父媒体已明确声明的来源。
  var resolvedDirectors: [Person] {
    (directors ?? []).map { $0.resolvingRouteSource(fallback: source) }
  }

  enum CodingKeys: String, CodingKey {
    case tmdb_id, douban_id, bangumi_id, anilist_id, imdb_id, tvdb_id, source,
      mediaid_prefix, media_id, title,
      original_title, original_name, names,
      type, year, season, poster_path, backdrop_path,
      overview, vote_average, popularity, season_info, collection_id, directors, actors,
      episode_group, runtime, release_date, original_language, production_countries, genres,
      category, subscribeShare
  }

  init(
    tmdb_id: Int? = nil, douban_id: String? = nil, bangumi_id: Int? = nil,
    anilist_id: Int? = nil, imdb_id: String? = nil,
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
    subscribeShare: SubscribeShare? = nil,
    rawPayload: [String: JSONValue]? = nil
  ) {
    self.tmdb_id = tmdb_id
    self.douban_id = douban_id
    self.bangumi_id = bangumi_id
    self.anilist_id = anilist_id
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
    self.rawPayload = rawPayload

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      anilist_id: anilist_id, mediaid_prefix: mediaid_prefix, media_id: media_id,
      title: title,
      subscribeShare: subscribeShare)

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
      anilist_id: json.anilist_id,
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
      subscribeShare: json.subscribeShare,
      rawPayload: json.rawPayload
    )
  }

  nonisolated init(json: MediaInfoJSON, precomputedImageURLs: ImageURLs) {
    self.tmdb_id = json.tmdb_id
    self.douban_id = json.douban_id
    self.bangumi_id = json.bangumi_id
    self.anilist_id = json.anilist_id
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
    self.rawPayload = json.rawPayload

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      anilist_id: anilist_id, mediaid_prefix: mediaid_prefix, media_id: media_id,
      title: title,
      subscribeShare: subscribeShare)

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
    anilist_id = try container.decodeIfPresent(Int.self, forKey: .anilist_id)
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
    rawPayload =
      (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]

    self.id = Self.generateUniqueKey(
      source: source, type: type, season: season, tmdb_id: tmdb_id, imdb_id: imdb_id,
      tvdb_id: tvdb_id, douban_id: douban_id, bangumi_id: bangumi_id,
      anilist_id: anilist_id, mediaid_prefix: mediaid_prefix, media_id: media_id,
      title: title,
      subscribeShare: subscribeShare)

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

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: JSONCodingKey.self)
    for (key, value) in rawPayload ?? [:] {
      try container.encode(value, forKey: JSONCodingKey(key))
    }

    func encode<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
      guard let value else { return }
      try container.encode(value, forKey: JSONCodingKey(key.stringValue))
    }

    try encode(tmdb_id, .tmdb_id)
    try encode(douban_id, .douban_id)
    try encode(bangumi_id, .bangumi_id)
    try encode(anilist_id, .anilist_id)
    try encode(imdb_id, .imdb_id)
    try encode(tvdb_id, .tvdb_id)
    try encode(source, .source)
    try encode(mediaid_prefix, .mediaid_prefix)
    try encode(media_id, .media_id)
    try encode(title, .title)
    try encode(original_title, .original_title)
    try encode(original_name, .original_name)
    try encode(names, .names)
    try encode(type, .type)
    try encode(year, .year)
    try encode(season, .season)
    try encode(poster_path, .poster_path)
    try encode(backdrop_path, .backdrop_path)
    try encode(overview, .overview)
    try encode(vote_average, .vote_average)
    try encode(popularity, .popularity)
    try encode(season_info, .season_info)
    try encode(collection_id, .collection_id)
    try encode(directors, .directors)
    try encode(actors, .actors)
    try encode(episode_group, .episode_group)
    try encode(runtime, .runtime)
    try encode(release_date, .release_date)
    try encode(original_language, .original_language)
    try encode(production_countries, .production_countries)
    try encode(genres, .genres)
    try encode(category, .category)
    try encode(subscribeShare, .subscribeShare)
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
  /// 通过拼接多个核心 ID 字段生成唯一标识；没有任何 ID 时使用标题区分不同媒体
  /// 长度前缀用于区分 nil、空字符串与字段边界
  /// 用于在 UI 渲染前过滤重复项与生成 ID
  nonisolated private static func generateUniqueKey(
    source: String?, type: String?, season: Int?, tmdb_id: Int?,
    imdb_id: String?, tvdb_id: Int?, douban_id: String?, bangumi_id: Int?,
    anilist_id: Int?, mediaid_prefix: String?, media_id: String?,
    title: String?,
    subscribeShare: SubscribeShare? = nil
  ) -> String {
    if let subscribeShare {
      let shareId = subscribeShare.raw_id.map(String.init) ?? subscribeShare.id
      return "share:\(shareId)"
    }

    var parts: [String?] = [
      source,
      type,
      season.map { String($0) },
      tmdb_id.map { String($0) },
      imdb_id,
      tvdb_id.map { String($0) },
      douban_id,
      bangumi_id.map { String($0) },
      anilist_id.map { String($0) },
      mediaid_prefix,
      media_id,
    ]

    let hasIdentifier = tmdb_id != nil || imdb_id != nil || tvdb_id != nil
      || douban_id != nil || bangumi_id != nil || anilist_id != nil || media_id != nil
    if !hasIdentifier, let title = MediaIdentifier.normalizedString(title) {
      parts.append(title)
    }

    return parts.map { value in
      guard let value else { return "n" }
      return "s\(value.utf8.count):\(value)"
    }.joined(separator: "|")
  }

  /// 判断当前媒体项是否具备合集行为。
  /// 官方 Web 也以 collection_id 作为跳转合集页的依据；type 只参与展示文案。
  nonisolated static func checkIsCollection(type: String?, collection_id: Int?) -> Bool {
    return collection_id != nil
  }

  nonisolated private static func checkDisplaysAsCollection(type: String?) -> Bool {
    type == "合集" || type == "collection" || type == "系列"
  }

  /// 解析用于 API 请求的主媒体身份，严格遵循 Web 的来源优先级。
  /// - 对应前端: `getMediaSubscribeIdentity()` / `getMediaSubscribeId()` in `useMediaSubscribe.ts`
  /// - 选择规则: 优先匹配声明来源，未匹配时依次回退 TMDB、豆瓣、Bangumi、AniList。
  var identity: MediaIdentity? {
    MediaIdentifier.resolve(
      mediaIdPrefix: mediaid_prefix,
      source: source,
      mediaId: media_id,
      tmdbId: tmdb_id,
      doubanId: douban_id,
      bangumiId: bangumi_id,
      anilistId: anilist_id
    )
  }

  /// Web 详情页的演职员和推荐按 TMDB、豆瓣、Bangumi、AniList 字段顺序选择接口，
  /// 与订阅使用的主身份是两条独立规则。
  var auxiliaryContentIdentity: MediaIdentity? {
    MediaIdentifier.resolveAuxiliaryContent(
      tmdbId: tmdb_id,
      doubanId: douban_id,
      bangumiId: bangumi_id,
      anilistId: anilist_id
    )
  }

  /// 生成用于 API 请求的统一媒体键。
  var apiMediaId: String? {
    identity?.mediaKey
  }

  nonisolated var canJumpToTMDB: Bool {
    if douban_id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      || (bangumi_id ?? 0) > 0
      || (anilist_id ?? 0) > 0
    {
      return true
    }

    let fallbackSource = (mediaid_prefix ?? source)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let fallbackId = media_id?.trimmingCharacters(in: .whitespacesAndNewlines)
    return fallbackId?.isEmpty == false
      && (fallbackSource == "douban"
        || fallbackSource == "bangumi"
        || fallbackSource == "anilist")
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

  static func deduplicateSubscriptionShareMedia(
    _ items: [MediaInfo],
    existingKeys: inout Set<String>
  ) -> [MediaInfo] {
    return items.filter { item in
      let key = item.id
      if existingKeys.contains(key) {
        return false
      }
      existingKeys.insert(key)
      return true
    }
  }

  /// 判断媒体是否可以直接订阅，无需选择季。
  /// Web 只将明确的电视剧放入分季流程，合集不提供订阅入口。
  var canDirectlySubscribe: Bool {
    !isCollection && type != "电视剧"
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

  // --- 身份属性 ---
  let id: String
  /// 哈希值
  let hash: String?
  // 下载用户 ID（Web 兼容字段，部分历史记录以用户名写入）
  let userid: String?
  // 下载用户名称
  let username: String?

  // --- 接口快照字段，为 UI 更新发布 ---
  /// 种子名称
  @Published var title: String?
  /// 识别后的名称
  @Published var name: String?
  /// 大小
  @Published var size: Int64?
  /// 关联的媒体信息
  @Published var media: DownloadingMediaInfo?
  // 季集格式 (如 S01E01)
  @Published var season_episode: String?

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
      season_episode, userid, username
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let decodedHash = try container.decodeIfPresent(String.self, forKey: .hash)
    let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
    let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
    let decodedSize = try container.decodeIfPresent(Int64.self, forKey: .size)
    let decodedMedia = try container.decodeIfPresent(DownloadingMediaInfo.self, forKey: .media)
    let decodedSeasonEpisode = try container.decodeIfPresent(String.self, forKey: .season_episode)
    let decodedUserId = try container.decodeIfPresent(String.self, forKey: .userid)
    let decodedUsername = try container.decodeIfPresent(String.self, forKey: .username)

    // 解码身份和接口快照属性
    hash = decodedHash
    title = decodedTitle
    name = decodedName
    size = decodedSize
    media = decodedMedia
    season_episode = decodedSeasonEpisode
    userid = decodedUserId
    username = decodedUsername

    // 解码可变的、@Published 的属性
    state = try container.decodeIfPresent(String.self, forKey: .state)
    progress = try container.decodeIfPresent(Double.self, forKey: .progress)
    dlspeed = try container.decodeIfPresent(String.self, forKey: .dlspeed)
    upspeed = try container.decodeIfPresent(String.self, forKey: .upspeed)
    left_time = try container.decodeIfPresent(String.self, forKey: .left_time)

    // 优先使用 hash 作为稳定标识符
    if let _hash = decodedHash, !_hash.isEmpty {
      id = "DownloadingInfo-\(_hash)-\(decodedUsername ?? "")"
    } else {
      // 备用方案：组合其他信息，确保稳定性
      let fallbackId =
        (decodedName ?? "") + (decodedTitle ?? "") + (decodedUsername ?? "")
        + (decodedSize.map { String($0) } ?? "")
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
    try container.encode(userid, forKey: .userid)
    try container.encode(username, forKey: .username)
  }

  /// 更新同一下载任务的最新接口快照。
  func update(with other: DownloadingInfo) {
    if title != other.title { title = other.title }
    if name != other.name { name = other.name }
    if size != other.size { size = other.size }
    if media != other.media { media = other.media }
    if season_episode != other.season_episode { season_episode = other.season_episode }
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
  /// 站点 Cookie
  var site_cookie: String? = nil
  /// 站点 User-Agent
  var site_ua: String? = nil
  /// 站点是否使用代理
  var site_proxy: Bool? = nil
  /// 站点优先级
  let site_order: Int?
  /// 站点指定的下载器
  var site_downloader: String? = nil
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

/// 后端资源结果允许部分字段缺失或为 null；只在输入边界为本地非可空字段提供中性默认值。
extension TorrentInfo {
  private enum CodingKeys: String, CodingKey {
    case site, site_name, site_cookie, site_ua, site_proxy, site_order, site_downloader
    case title, description, enclosure, page_url, size, seeders, peers, pubdate
    case uploadvolumefactor, downloadvolumefactor, pri_order, labels, volume_factor
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    site = try container.decodeIfPresent(Int.self, forKey: .site)
    site_name = try container.decodeIfPresent(String.self, forKey: .site_name)
    site_cookie = try container.decodeIfPresent(String.self, forKey: .site_cookie)
    site_ua = try container.decodeIfPresent(String.self, forKey: .site_ua)
    site_proxy = try container.decodeIfPresent(FlexibleBool.self, forKey: .site_proxy)?.value
    site_order = try container.decodeIfPresent(Int.self, forKey: .site_order)
    site_downloader = try container.decodeIfPresent(String.self, forKey: .site_downloader)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    enclosure = try container.decodeIfPresent(String.self, forKey: .enclosure)
    page_url = try container.decodeIfPresent(String.self, forKey: .page_url)
    // 后端大小字段是浮点数；仅保留能精确表示为字节整数的值，异常或超范围时回落为 0。
    if let decodedSize = try? container.decode(Int64.self, forKey: .size) {
      size = decodedSize
    } else if let decodedSize = try? container.decode(Double.self, forKey: .size),
      let exactSize = Int64(exactly: decodedSize)
    {
      size = exactSize
    } else {
      size = 0
    }
    seeders = try container.decodeIfPresent(Int.self, forKey: .seeders)
    peers = try container.decodeIfPresent(Int.self, forKey: .peers)
    pubdate = try container.decodeIfPresent(String.self, forKey: .pubdate)
    // 缺失或异常的促销因子按无促销处理。
    uploadvolumefactor =
      (try? container.decodeIfPresent(Double.self, forKey: .uploadvolumefactor)) ?? 1
    downloadvolumefactor =
      (try? container.decodeIfPresent(Double.self, forKey: .downloadvolumefactor)) ?? 1
    pri_order = try container.decodeIfPresent(Int.self, forKey: .pri_order)
    labels = try container.decodeIfPresent([String].self, forKey: .labels)
    volume_factor = try container.decodeIfPresent(String.self, forKey: .volume_factor)
  }
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

/// 保持现有调用方的非可空文本合同；缺失或异常文本在输入边界归一为空串。
extension MetaInfo {
  private enum CodingKeys: String, CodingKey {
    case title, year, resource_team, video_encode, resource_pix, name, season_episode
    case subtitle, web_source, edition, total_season, total_episode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    year = try container.decodeIfPresent(String.self, forKey: .year)
    resource_team = try container.decodeIfPresent(String.self, forKey: .resource_team)
    video_encode = try container.decodeIfPresent(String.self, forKey: .video_encode)
    resource_pix = try container.decodeIfPresent(String.self, forKey: .resource_pix)
    name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    season_episode =
      (try? container.decodeIfPresent(String.self, forKey: .season_episode)) ?? ""
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    web_source = try container.decodeIfPresent(String.self, forKey: .web_source)
    edition = try container.decodeIfPresent(String.self, forKey: .edition)
    total_season = try container.decodeIfPresent(Int.self, forKey: .total_season)
    total_episode = try container.decodeIfPresent(Int.self, forKey: .total_episode)
  }
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
  /// 是否被软筛选过滤掉
  var isFilteredOut: Bool = false

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
  static let zspace = MediaServerType(rawValue: "zspace")
}

/// 媒体服务器最近播放/新增项
struct MediaServerPlayItem: Codable, Identifiable, Equatable {
  struct ImageURLs: Hashable {
    let image: URL?
  }

  /// 真实接口返回的原始 ID（保留，以便未来跳转或 API 请求使用）
  let raw_id: FlexibleString?
  /// 媒体服务器项目 ID
  let item_id: FlexibleString?
  /// 媒体服务器 ID
  let server_id: FlexibleString?
  /// SwiftUI 需要的稳定唯一表示符（按服务器类型和业务 ID 生成）
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
    case item_id, server_id, title, subtitle, type, image, link, use_cookies, server_type
  }

  private static func stableID(
    rawID: String?, itemID: String?, serverID: String?, link: String?,
    serverType: MediaServerType?
  ) -> String {
    func normalized(_ value: String?) -> String? {
      guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
      else { return nil }
      return value
    }

    func encoded(_ value: String) -> String {
      "\(value.utf8.count):\(value)"
    }

    let prefix = "playitem-\(encoded(normalized(serverType?.rawValue) ?? ""))"
    if let rawID = normalized(rawID) {
      return "\(prefix)-raw-\(encoded(rawID))"
    }
    if let serverID = normalized(serverID), let itemID = normalized(itemID) {
      return "\(prefix)-pair-\(encoded(serverID))-\(encoded(itemID))"
    }
    if let link = normalized(link) {
      return "\(prefix)-link-\(encoded(link))"
    }
    return "\(prefix)-uuid-\(UUID().uuidString)"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    raw_id = try container.decodeIfPresent(FlexibleString.self, forKey: .raw_id)
    item_id = try container.decodeIfPresent(FlexibleString.self, forKey: .item_id)
    server_id = try container.decodeIfPresent(FlexibleString.self, forKey: .server_id)
    // 后端允许最近媒体没有标题；单项缺值不应让整个服务器列表解码失败。
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    image = try container.decodeIfPresent(String.self, forKey: .image)
    link = try container.decodeIfPresent(String.self, forKey: .link)
    use_cookies = try container.decodeIfPresent(FlexibleBool.self, forKey: .use_cookies)
    server_type = try container.decodeIfPresent(MediaServerType.self, forKey: .server_type)

    self.id = Self.stableID(
      rawID: raw_id?.value,
      itemID: item_id?.value,
      serverID: server_id?.value,
      link: link,
      serverType: server_type
    )

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
    self.item_id = nil
    self.server_id = nil
    self.id = Self.stableID(
      rawID: id, itemID: nil, serverID: nil, link: link, serverType: server_type)
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
  /// AniList ID
  let anilistid: Int?
  /// 统一媒体来源
  let media_source: String?
  /// 来源原生 ID
  let media_id: String?
  /// 媒体 ID fallback
  let mediaid: String?
  /// 季号
  let season: Int?
  /// 是否洗版，数字或者boolean
  let best_version: Int?
  /// 是否仅洗全集，数字或者boolean
  let best_version_full: Int?
  /// 剧集组
  let episode_group: String?

  init(
    name: String,
    type: String,
    year: String? = nil,
    tmdbid: Int? = nil,
    doubanid: String? = nil,
    bangumiid: Int? = nil,
    anilistid: Int? = nil,
    media_source: String? = nil,
    media_id: String? = nil,
    mediaid: String? = nil,
    season: Int? = nil,
    best_version: Int? = nil,
    best_version_full: Int? = nil,
    episode_group: String? = nil
  ) {
    self.name = name
    self.type = type
    self.year = year
    self.tmdbid = tmdbid
    self.doubanid = doubanid
    self.bangumiid = bangumiid
    self.anilistid = anilistid
    self.media_source = media_source
    self.media_id = media_id
    self.mediaid = mediaid
    self.season = season
    self.best_version = best_version
    self.best_version_full = best_version_full
    self.episode_group = episode_group
  }
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
  /// 评分
  var vote: Double?
  /// 状态：N-新建 R-订阅中 P-待定 S-暂停
  var state: String?
  // 最后更新时间
  var last_update: String?
  /// 订阅用户
  var username: String?
  /// 创建时间
  var date: String?
  /// 总集数
  var total_episode: Int?
  /// 开始集数
  var start_episode: Int?
  /// 缺失集数
  var lack_episode: Int?
  /// 已完成集数，后端响应派生字段，保存订阅时不写回。
  var completed_episode: Int?
  /// 后端维护的已下载/状态附加信息，保存原详情时需要原样保留。
  var note: JSONValue?
  /// TMDB ID
  var tmdbid: Int?
  /// 豆瓣ID
  var doubanid: String?
  /// Bangumi ID
  var bangumiid: Int?
  /// AniList ID
  var anilistid: Int?
  /// 统一媒体来源
  var media_source: String?
  /// 来源原生 ID
  var media_id: String?
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
  /// 是否仅洗全集 (后端返回 0/1 整数作为布尔值使用)
  var best_version_full: Int?
  /// 当前洗版优先级，后端维护，保存订阅时需要原样保留。
  var current_priority: Int?
  /// 过滤规则组
  var filter_groups: [String]?
  /// 自定义识别词
  var custom_words: String?
  /// 描述
  var description: String?
  /// 用户可编辑的过滤规则配置；编辑保存时保留或更新。
  var filter: String?
  /// 自定义剧集组
  var episode_group: String?
  /// 使用 imdbid 搜索
  var search_imdbid: Int?
  /// 自定义媒体类别
  var media_category: String?

  /// 媒体ID标识 (如 tmdb:1234)
  var mediaid: String?
  /// 洗版订阅的剧集优先级状态，保存原详情时需要原样保留。
  var episode_priority: [String: Int]?

  /// 预计算的图片 URL
  let imageURLs: ImageURLs

  enum CodingKeys: String, CodingKey {
    case id, name, year, type, keyword, season, poster, backdrop, state, last_update,
      vote, total_episode, start_episode, lack_episode, completed_episode, note, tmdbid, doubanid,
      bangumiid, anilistid, media_source, media_id,
      quality, resolution, effect, include, exclude, sites, downloader, save_path, best_version,
      best_version_full, current_priority, filter_groups, custom_words, description, filter,
      episode_group, search_imdbid, media_category, mediaid, episode_priority, username, date
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
    vote = try container.decodeIfPresent(Double.self, forKey: .vote)
    state = try container.decodeIfPresent(String.self, forKey: .state)
    last_update = try container.decodeIfPresent(String.self, forKey: .last_update)
    username = try container.decodeIfPresent(String.self, forKey: .username)
    date = try container.decodeIfPresent(String.self, forKey: .date)
    total_episode = try container.decodeIfPresent(Int.self, forKey: .total_episode)
    start_episode = try container.decodeIfPresent(Int.self, forKey: .start_episode)
    lack_episode = try container.decodeIfPresent(Int.self, forKey: .lack_episode)
    completed_episode = try container.decodeIfPresent(Int.self, forKey: .completed_episode)
    if container.contains(.note) {
      note =
        try container.decodeNil(forKey: .note)
        ? .null
        : container.decode(JSONValue.self, forKey: .note)
    } else {
      note = nil
    }
    tmdbid = try container.decodeIfPresent(Int.self, forKey: .tmdbid)
    doubanid = try container.decodeIfPresent(String.self, forKey: .doubanid)
    bangumiid = try container.decodeIfPresent(Int.self, forKey: .bangumiid)
    anilistid = try container.decodeIfPresent(Int.self, forKey: .anilistid)
    media_source = try container.decodeIfPresent(String.self, forKey: .media_source)
    media_id = try container.decodeIfPresent(String.self, forKey: .media_id)
    quality = try container.decodeIfPresent(String.self, forKey: .quality)
    resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
    effect = try container.decodeIfPresent(String.self, forKey: .effect)
    include = try container.decodeIfPresent(String.self, forKey: .include)
    exclude = try container.decodeIfPresent(String.self, forKey: .exclude)
    sites = try container.decodeIfPresent([Int].self, forKey: .sites)
    downloader = try container.decodeIfPresent(String.self, forKey: .downloader)
    save_path = try container.decodeIfPresent(String.self, forKey: .save_path)
    best_version = try container.decodeIfPresent(Int.self, forKey: .best_version)
    best_version_full = try container.decodeIfPresent(Int.self, forKey: .best_version_full)
    current_priority = try container.decodeIfPresent(Int.self, forKey: .current_priority)
    filter_groups = try container.decodeIfPresent([String].self, forKey: .filter_groups)
    custom_words = try container.decodeIfPresent(String.self, forKey: .custom_words)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    filter = try container.decodeIfPresent(String.self, forKey: .filter)
    episode_group = try container.decodeIfPresent(String.self, forKey: .episode_group)
    search_imdbid = try container.decodeIfPresent(Int.self, forKey: .search_imdbid)
    media_category = try container.decodeIfPresent(String.self, forKey: .media_category)
    mediaid = try container.decodeIfPresent(String.self, forKey: .mediaid)
    episode_priority = try container.decodeIfPresent([String: Int].self, forKey: .episode_priority)

    // 计算图片 URL
    self.imageURLs = ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(year, forKey: .year)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(keyword, forKey: .keyword)
    try container.encodeIfPresent(season, forKey: .season)
    try container.encodeIfPresent(poster, forKey: .poster)
    try container.encodeIfPresent(backdrop, forKey: .backdrop)
    try container.encodeIfPresent(vote, forKey: .vote)
    try container.encodeIfPresent(state, forKey: .state)
    try container.encodeIfPresent(last_update, forKey: .last_update)
    try container.encodeIfPresent(username, forKey: .username)
    try container.encodeIfPresent(date, forKey: .date)
    if let totalEpisode = total_episode {
      try container.encode(totalEpisode, forKey: .total_episode)
    } else if (id ?? 0) > 0 {
      // 现有订阅的 nil 必须显式写为 null；省略会被后端默认成 0 并误置人工集数。
      try container.encodeNil(forKey: .total_episode)
    }
    try container.encodeIfPresent(start_episode, forKey: .start_episode)
    try container.encodeIfPresent(lack_episode, forKey: .lack_episode)
    try container.encodeIfPresent(note, forKey: .note)
    try container.encodeIfPresent(tmdbid, forKey: .tmdbid)
    try container.encodeIfPresent(doubanid, forKey: .doubanid)
    try container.encodeIfPresent(bangumiid, forKey: .bangumiid)
    try container.encodeIfPresent(anilistid, forKey: .anilistid)
    try container.encodeIfPresent(media_source, forKey: .media_source)
    try container.encodeIfPresent(media_id, forKey: .media_id)
    try container.encodeIfPresent(quality, forKey: .quality)
    try container.encodeIfPresent(resolution, forKey: .resolution)
    try container.encodeIfPresent(effect, forKey: .effect)
    try container.encodeIfPresent(include, forKey: .include)
    try container.encodeIfPresent(exclude, forKey: .exclude)
    try container.encodeIfPresent(sites, forKey: .sites)
    try container.encodeIfPresent(downloader, forKey: .downloader)
    try container.encodeIfPresent(save_path, forKey: .save_path)
    try container.encodeIfPresent(best_version, forKey: .best_version)
    try container.encodeIfPresent(best_version_full, forKey: .best_version_full)
    try container.encodeIfPresent(current_priority, forKey: .current_priority)
    try container.encodeIfPresent(filter_groups, forKey: .filter_groups)
    try container.encodeIfPresent(custom_words, forKey: .custom_words)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(filter, forKey: .filter)
    try container.encodeIfPresent(episode_group, forKey: .episode_group)
    try container.encodeIfPresent(search_imdbid, forKey: .search_imdbid)
    try container.encodeIfPresent(media_category, forKey: .media_category)
    try container.encodeIfPresent(mediaid, forKey: .mediaid)
    try container.encodeIfPresent(episode_priority, forKey: .episode_priority)
  }

  /// 成员初始化器，用于手动创建订阅。
  init(
    id: Int? = nil, name: String, year: String? = nil, type: String, season: Int? = nil,
    poster: String? = nil, vote: Double? = nil, state: String? = nil, last_update: String? = nil,
    username: String? = nil, date: String? = nil,
    completed_episode: Int? = nil, note: JSONValue? = nil,
    tmdbid: Int? = nil, doubanid: String? = nil, bangumiid: Int? = nil,
    anilistid: Int? = nil, media_source: String? = nil, media_id: String? = nil,
    best_version: Int? = nil, best_version_full: Int? = nil, episode_group: String? = nil,
    backdrop: String? = nil, keyword: String? = nil, total_episode: Int? = nil,
    start_episode: Int? = nil, lack_episode: Int? = nil, quality: String? = nil,
    resolution: String? = nil, effect: String? = nil, include: String? = nil,
    exclude: String? = nil, sites: [Int]? = nil, downloader: String? = nil,
    save_path: String? = nil, filter_groups: [String]? = nil,
    custom_words: String? = nil, description: String? = nil,
    search_imdbid: Int? = nil, media_category: String? = nil, mediaid: String? = nil,
    episode_priority: [String: Int]? = nil, current_priority: Int? = nil, filter: String? = nil
  ) {
    self.id = id
    self.name = name
    self.year = year
    self.type = type
    self.season = season
    self.poster = poster
    self.vote = vote
    self.state = state
    self.last_update = last_update
    self.username = username
    self.date = date
    self.completed_episode = completed_episode
    self.note = note
    self.tmdbid = tmdbid
    self.doubanid = doubanid
    self.bangumiid = bangumiid
    self.anilistid = anilistid
    self.media_source = media_source
    self.media_id = media_id
    self.best_version = best_version
    self.best_version_full = best_version_full
    self.current_priority = current_priority
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
    self.filter = filter
    self.search_imdbid = search_imdbid
    self.media_category = media_category
    self.mediaid = mediaid
    self.episode_priority = episode_priority

    // 计算图片 URL
    self.imageURLs = ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  /// 解析订阅记录的主媒体身份，严格遵循 Web 订阅卡片的来源优先级。
  /// - 对应前端: `getMediaId()` in `SubscribeCard.vue`
  /// - 选择规则: 优先 `media_source`/`media_id`，其次 TMDB、豆瓣、Bangumi、AniList，最后回退 `mediaid`。
  var identity: MediaIdentity? {
    MediaIdentifier.resolve(
      source: media_source,
      mediaId: media_id,
      tmdbId: MediaIdentifier.truthyNumericIdentifier(tmdbid),
      doubanId: doubanid,
      bangumiId: MediaIdentifier.truthyNumericIdentifier(bangumiid),
      anilistId: MediaIdentifier.truthyNumericIdentifier(anilistid),
      legacyMediaId: mediaid
    )
  }

  /// 生成用于订阅查询、取消和详情跳转的统一媒体键。
  var apiMediaId: String? {
    identity?.mediaKey
  }

  /// 生成新增订阅请求，完整保留当前订阅的来源身份与洗版设置。
  var addRequest: SubscribeRequest {
    SubscribeRequest(
      name: name,
      type: type,
      year: year,
      tmdbid: tmdbid,
      doubanid: doubanid,
      bangumiid: bangumiid,
      anilistid: anilistid,
      media_source: media_source,
      media_id: media_id,
      mediaid: mediaid,
      season: season,
      best_version: best_version,
      best_version_full: best_version_full,
      episode_group: episode_group
    )
  }

  func navigationMediaInfo() -> MediaInfo {
    let tmdbId = MediaIdentifier.validNumericIdentifier(tmdbid)
    let doubanId = MediaIdentifier.normalizedString(doubanid)
    let bangumiId = MediaIdentifier.validNumericIdentifier(bangumiid)
    let anilistId = MediaIdentifier.validNumericIdentifier(anilistid)
    let canonicalSource = MediaIdentifier.normalizeSource(media_source).flatMap {
      $0 == "0" ? nil : $0
    }
    let canonicalMediaId = MediaIdentifier.normalizedString(media_id).flatMap { id -> String? in
      guard Int(id).map({ $0 > 0 }) ?? true else { return nil }
      return id
    }
    let hasCanonicalIdentity = canonicalSource != nil && canonicalMediaId != nil
    let resolvedIdentity = MediaIdentifier.resolve(
      source: hasCanonicalIdentity ? canonicalSource : nil,
      mediaId: hasCanonicalIdentity ? canonicalMediaId : nil,
      tmdbId: tmdbId,
      doubanId: doubanId,
      bangumiId: bangumiId,
      anilistId: anilistId,
      legacyMediaId: mediaid
    )
    return MediaInfo(
      tmdb_id: tmdbId,
      douban_id: doubanId,
      bangumi_id: bangumiId,
      anilist_id: anilistId,
      imdb_id: nil,
      tvdb_id: nil,
      source: resolvedIdentity?.source,
      mediaid_prefix: nil,
      media_id: resolvedIdentity?.mediaId,
      title: name,
      original_title: nil,
      original_name: nil,
      names: nil,
      type: type,
      year: year,
      season: season,
      poster_path: nil,
      backdrop_path: nil,
      overview: description,
      vote_average: nil,
      popularity: nil,
      season_info: nil,
      collection_id: nil,
      directors: nil,
      actors: nil,
      episode_group: episode_group,
      runtime: nil,
      release_date: nil,
      original_language: nil,
      production_countries: nil,
      genres: nil,
      category: nil
    )
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
  let bangumiid: Int?
  let anilistid: Int?
  let media_source: String?
  let media_id: String?
}

/// 演职人员模型
nonisolated struct Person: Codable, Identifiable, Hashable {
  struct ImageURLs: Hashable {
    let profile: URL?
  }

  /// 来源：themoviedb、douban、bangumi、anilist
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

  /// 图片 URL 在主线程按当前图片设置计算，避免后台 JSON 解码访问主线程 APIService。
  @MainActor var imageURLs: ImageURLs {
    ImageURLs(
      profile: APIService.shared.getPersonImageURL(
        source: source,
        profilePath: profile_path,
        avatar: avatar,
        images: images
      )
    )
  }

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
    // 头像只是展示信息；无法识别的可选头像不能拖垮整个人物或媒体数组。
    self.avatar = try? keyedContainer.decodeIfPresent(PersonAvatar.self, forKey: .avatar)
    self.images = try keyedContainer.decodeIfPresent(BangumiImages.self, forKey: .images)

    // 恢复稳定的内部标识符逻辑
    if let pid = parsedId {
      self.id = "\(self.source ?? "unknown")-\(pid)"
    } else {
      self.id = "name-\(self.name ?? UUID().uuidString)"
    }

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

  }

  /// 按最终人物身份去重；`id` 已包含来源与原始 ID，可保留跨来源同号人物。
  static func deduplicate(_ items: [Person], existingIDs: inout Set<String>) -> [Person] {
    items.filter { existingIDs.insert($0.id).inserted }
  }

  /// 规范化人物详情路由来源；显式但不受支持的来源不会被父媒体覆盖。
  func resolvingRouteSource(fallback: String?) -> Person {
    let declaredSource = MediaIdentifier.normalizedString(source)
    let candidateSource = declaredSource == nil ? fallback : source
    guard let resolvedSource = Self.supportedRouteSource(candidateSource), source != resolvedSource
    else {
      return self
    }

    return Person(
      source: resolvedSource,
      raw_id: raw_id,
      name: name,
      latin_name: latin_name,
      character: character,
      job: job,
      roles: roles,
      profile_path: profile_path,
      original_name: original_name,
      known_for_department: known_for_department,
      place_of_birth: place_of_birth,
      popularity: popularity,
      biography: biography,
      birthday: birthday,
      also_known_as: also_known_as,
      avatar: avatar,
      images: images,
      id: raw_id.map { "\(resolvedSource)-\($0)" } ?? id
    )
  }

  /// 用人物详情补充展示字段，但始终保留入口人物的路由身份和已有数据。
  func mergingDetails(from detail: Person) -> Person {
    func nonEmpty(_ value: String?, fallback: String?) -> String? {
      guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return fallback
      }
      return value
    }

    func nonEmpty(_ value: [String]?, fallback: [String]?) -> [String]? {
      guard let value, !value.isEmpty else { return fallback }
      return value
    }

    func usable(_ avatar: PersonAvatar?) -> PersonAvatar? {
      guard let avatar,
        !avatar.urlValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return nil
      }
      return avatar
    }

    func usable(_ images: BangumiImages?) -> BangumiImages? {
      guard let images else { return nil }
      let values = [images.large, images.common, images.medium, images.small, images.grid]
      guard values.contains(where: { value in
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) else {
        return nil
      }
      return images
    }

    let mergedAvatar = usable(avatar) ?? usable(detail.avatar)

    let mergedImages = usable(images) ?? usable(detail.images)

    return Person(
      source: source,
      raw_id: raw_id,
      name: nonEmpty(detail.name, fallback: name),
      latin_name: nonEmpty(detail.latin_name, fallback: latin_name),
      character: nonEmpty(detail.character, fallback: character),
      job: nonEmpty(detail.job, fallback: job),
      roles: nonEmpty(detail.roles, fallback: roles),
      profile_path: nonEmpty(detail.profile_path, fallback: profile_path),
      original_name: nonEmpty(detail.original_name, fallback: original_name),
      known_for_department: nonEmpty(
        detail.known_for_department, fallback: known_for_department),
      place_of_birth: nonEmpty(detail.place_of_birth, fallback: place_of_birth),
      popularity: detail.popularity ?? popularity,
      biography: nonEmpty(detail.biography, fallback: biography),
      birthday: nonEmpty(detail.birthday, fallback: birthday),
      also_known_as: nonEmpty(detail.also_known_as, fallback: also_known_as),
      avatar: mergedAvatar,
      images: mergedImages,
      id: id
    )
  }

  private static func supportedRouteSource(_ source: String?) -> String? {
    guard let source = MediaIdentifier.normalizeSource(source) else { return nil }
    switch source {
    case "themoviedb", "douban", "bangumi", "anilist":
      return source
    default:
      return nil
    }
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

  enum CodingKeys: String, CodingKey {
    case large
    case common
    case medium
    case small
    case grid
  }

  init(large: String?, common: String?, medium: String?, small: String?, grid: String?) {
    self.large = large
    self.common = common
    self.medium = medium
    self.small = small
    self.grid = grid
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.large = try Self.decodeImageURL(from: container, forKey: .large)
    self.common = try Self.decodeImageURL(from: container, forKey: .common)
    self.medium = try Self.decodeImageURL(from: container, forKey: .medium)
    self.small = try Self.decodeImageURL(from: container, forKey: .small)
    self.grid = try Self.decodeImageURL(from: container, forKey: .grid)
  }

  private static func decodeImageURL(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> String? {
    if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
      return stringValue
    }
    if let objectValue = try? container.decodeIfPresent(ImageObject.self, forKey: key) {
      return objectValue.url
    }
    return nil
  }

  private struct ImageObject: Codable, Hashable {
    let url: String?
  }
}

/// 演职人员头像数据源
nonisolated enum PersonAvatar: Codable, Hashable {
  case url(String)
  case object(normal: String)

  var urlValue: String {
    switch self {
    case .url(let url), .object(let url):
      return url
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let urlString = try? container.decode(String.self) {
      self = .url(urlString)
    } else if let dict = try? container.decode([String: JSONValue].self),
      let url = ["normal", "large", "medium", "small", "url"]
        .compactMap({ dict[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) })
        .first(where: { !$0.isEmpty })
    {
      // 豆瓣等来源可能在图片对象中混入 width/height；这里只读取已知 URL 字段。
      self = .object(normal: url)
    } else {
      throw DecodingError.typeMismatch(
        PersonAvatar.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "期望字符串或带有图片 URL 的对象"))
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

/// 系统环境变量
struct SystemEnv: Codable {
  let VERSION: String?
}

/// 全局应用设置
struct GlobalSettings: Codable {
  var TMDB_IMAGE_DOMAIN: String?
  var BACKEND_VERSION: String?
  var FRONTEND_VERSION: String?
  var BACKEND_DEV: Bool?
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
    case BACKEND_VERSION
    case FRONTEND_VERSION
    case BACKEND_DEV
    case GLOBAL_IMAGE_CACHE
    case RECOGNIZE_SOURCE
    case USER_UNIQUE_ID
    case SUBSCRIBE_SHARE_MANAGE
    case AI_AGENT_ENABLE
  }

  mutating func mergeUserSettings(_ userSettings: GlobalSettings) {
    RECOGNIZE_SOURCE = userSettings.RECOGNIZE_SOURCE ?? RECOGNIZE_SOURCE
    USER_UNIQUE_ID = userSettings.USER_UNIQUE_ID ?? USER_UNIQUE_ID
    SUBSCRIBE_SHARE_MANAGE = userSettings.SUBSCRIBE_SHARE_MANAGE ?? SUBSCRIBE_SHARE_MANAGE
    AI_AGENT_ENABLE = userSettings.AI_AGENT_ENABLE ?? AI_AGENT_ENABLE
  }
}

/// 分季订阅请求参数
struct SubscribeSeasonRequest: Hashable, Codable {
  let mediaInfo: MediaInfo
  let initialSeason: Int?
  let initialEpisodeGroup: String?
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
  // 目标文件项
  let dest_fileitem: FileItem?
  // 日期
  let date: String?

  enum CodingKeys: String, CodingKey {
    case id, title, type, seasons, episodes, category, src, dest
    case src_storage, dest_storage, mode, status, errmsg, src_fileitem, dest_fileitem, date
  }
}

extension TransferHistory {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    seasons = try container.decodeIfPresent(String.self, forKey: .seasons)
    episodes = try container.decodeIfPresent(String.self, forKey: .episodes)
    category = try container.decodeIfPresent(String.self, forKey: .category)
    src = try container.decodeIfPresent(String.self, forKey: .src)
    dest = try container.decodeIfPresent(String.self, forKey: .dest)
    src_storage = try container.decodeIfPresent(String.self, forKey: .src_storage)
    dest_storage = try container.decodeIfPresent(String.self, forKey: .dest_storage)
    mode = try container.decodeIfPresent(String.self, forKey: .mode)
    status = try container.decode(FlexibleBool.self, forKey: .status)
    errmsg = try container.decodeIfPresent(String.self, forKey: .errmsg)
    // Web 会保留稀疏历史行；嵌套文件项不可用时只降级该字段，不能拖垮整页。
    src_fileitem = try? container.decodeIfPresent(FileItem.self, forKey: .src_fileitem)
    dest_fileitem = try? container.decodeIfPresent(FileItem.self, forKey: .dest_fileitem)
    date = try container.decodeIfPresent(String.self, forKey: .date)
  }

  /// ID 可能被 SQLite 复用；执行破坏性操作前用稳定记录字段确认仍是同一条历史。
  func hasSameMutationFingerprint(as other: TransferHistory) -> Bool {
    id == other.id
      && title == other.title
      && type == other.type
      && seasons == other.seasons
      && episodes == other.episodes
      && category == other.category
      && src == other.src
      && dest == other.dest
      && src_storage == other.src_storage
      && dest_storage == other.dest_storage
      && mode == other.mode
      && status == other.status
      && errmsg == other.errmsg
      && src_fileitem == other.src_fileitem
      && dest_fileitem == other.dest_fileitem
      && date == other.date
  }
}

struct FileItem: Codable, Equatable {
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
nonisolated struct SubscribeShare: Codable, Identifiable, Hashable {
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
  // Bangumi ID
  let bangumiid: Int?
  // AniList ID
  let anilistid: Int?
  // 统一媒体来源
  let media_source: String?
  // 来源原生 ID
  let media_id: String?
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

  /// 图片 URL 在主线程按当前图片设置计算，避免后台 JSON 解码访问主线程 APIService。
  @MainActor var imageURLs: ImageURLs {
    ImageURLs(poster: APIService.shared.getSubscribePosterImageUrl(poster: poster))
  }

  enum CodingKeys: String, CodingKey {
    case raw_id = "id"
    case subscribe_id, share_title, share_comment, share_user, share_uid, name, year, type, keyword,
      tmdbid,
      doubanid, bangumiid, anilistid, media_source, media_id, season, poster, backdrop, vote,
      description, filter, include, exclude,
      quality,
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
    bangumiid = try container.decodeIfPresent(Int.self, forKey: .bangumiid)
    anilistid = try container.decodeIfPresent(Int.self, forKey: .anilistid)
    media_source = try container.decodeIfPresent(String.self, forKey: .media_source)
    media_id = try container.decodeIfPresent(String.self, forKey: .media_id)
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

  }

  /// 转换为 MediaInfo 以便在通用视图中复用
  @MainActor
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

    let canonicalSource = MediaIdentifier.normalizeSource(media_source).flatMap {
      $0 == "0" ? nil : $0
    }
    let canonicalMediaId = MediaIdentifier.normalizedString(media_id).flatMap { id -> String? in
      guard Int(id).map({ $0 > 0 }) ?? true else { return nil }
      return id
    }
    let hasCanonicalIdentity = canonicalSource != nil && canonicalMediaId != nil

    return MediaInfo(
      tmdb_id: tmdbid,
      douban_id: doubanid,
      bangumi_id: bangumiid,
      anilist_id: anilistid,
      source: hasCanonicalIdentity ? canonicalSource : nil,
      media_id: hasCanonicalIdentity ? canonicalMediaId : nil,
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
  var fileitem: FileItem?
  // 批量文件项；仅在调用方实际提供多文件上下文时编码，并优先于 fileitem。
  var fileitems: [FileItem]?
  // 历史ID
  var logid: Int
  // 目标存储；nil 表示由后端自动决定。
  var target_storage: String?
  // 整理方式；nil 表示由后端自动决定。
  var transfer_type: String?
  // 目标路径；空白值编码为 null，以匹配 v2.13.2 手动整理接口语义。
  var target_path: String
  // 最小文件大小
  var min_filesize: Int
  // 刮削；nil 表示由后端自动决定。
  var scrape: Bool?
  // 复用历史识别信息
  var from_history: Bool
  // 类型
  var type_name: String?
  // TMDB ID
  var tmdbid: Int?
  // 豆瓣 ID
  var doubanid: String?
  // Bangumi ID
  var bangumiid: Int? = nil
  // AniList ID
  var anilistid: Int? = nil
  // 统一媒体来源
  var media_source: String? = nil
  // 来源原生 ID
  var media_id: String? = nil
  // 剧集组编号；空白值编码为 null。
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
  // 仅预览整理结果，不执行文件写入。
  var preview: Bool = false

  enum CodingKeys: String, CodingKey {
    case fileitem, fileitems, logid, target_storage, transfer_type, target_path, min_filesize, scrape, from_history,
      type_name, tmdbid, doubanid, bangumiid, anilistid, media_source, media_id, episode_group,
      season, episode_detail, episode_format, episode_offset,
      episode_part, library_type_folder, library_category_folder, preview
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    if let fileitems, !fileitems.isEmpty {
      try container.encode(fileitems, forKey: .fileitems)
    } else if let fileitem {
      try container.encode(fileitem, forKey: .fileitem)
    }

    try container.encode(logid, forKey: .logid)
    if let targetStorage = target_storage?.trimmingCharacters(in: .whitespacesAndNewlines),
      !targetStorage.isEmpty
    {
      try container.encode(targetStorage, forKey: .target_storage)
    } else {
      try container.encodeNil(forKey: .target_storage)
    }

    if let transferType = transfer_type?.trimmingCharacters(in: .whitespacesAndNewlines),
      !transferType.isEmpty
    {
      try container.encode(transferType, forKey: .transfer_type)
    } else {
      try container.encodeNil(forKey: .transfer_type)
    }

    if target_path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try container.encodeNil(forKey: .target_path)
    } else {
      try container.encode(target_path, forKey: .target_path)
    }

    try container.encode(min_filesize, forKey: .min_filesize)
    if let scrape {
      try container.encode(scrape, forKey: .scrape)
    } else {
      try container.encodeNil(forKey: .scrape)
    }
    try container.encode(from_history, forKey: .from_history)
    try container.encodeIfPresent(type_name, forKey: .type_name)
    try container.encodeIfPresent(tmdbid, forKey: .tmdbid)
    try container.encodeIfPresent(doubanid, forKey: .doubanid)
    try container.encodeIfPresent(bangumiid, forKey: .bangumiid)
    try container.encodeIfPresent(anilistid, forKey: .anilistid)
    try container.encodeIfPresent(media_source, forKey: .media_source)
    try container.encodeIfPresent(media_id, forKey: .media_id)

    if let episodeGroup = episode_group?.trimmingCharacters(in: .whitespacesAndNewlines), !episodeGroup.isEmpty {
      try container.encode(episodeGroup, forKey: .episode_group)
    } else {
      try container.encodeNil(forKey: .episode_group)
    }

    try container.encodeIfPresent(season, forKey: .season)
    try container.encodeIfPresent(episode_detail, forKey: .episode_detail)
    try container.encodeIfPresent(episode_format, forKey: .episode_format)
    try container.encodeIfPresent(episode_offset, forKey: .episode_offset)
    try container.encodeIfPresent(episode_part, forKey: .episode_part)
    try container.encodeIfPresent(library_type_folder, forKey: .library_type_folder)
    try container.encodeIfPresent(library_category_folder, forKey: .library_category_folder)
    if preview {
      try container.encode(true, forKey: .preview)
    }
  }
}

nonisolated struct ManualTransferPreviewSummary: Codable, Hashable {
  let total: Int
  let success: Int
  let failed: Int
}

nonisolated struct ManualTransferPreviewItem: Codable, Hashable {
  let source: String?
  let target: String?
  let target_dir: String?
  let success: Bool
  let message: String?
  let type: String?
  let title: String?
  let season: JSONValue?
  let episode: JSONValue?
  let episode_end: JSONValue?
  let part: String?
  let org_string: String?
  let apply_words: [String]?
  let resource_team: String?
  let customization: String?
}

nonisolated struct ManualTransferPreviewData: Codable, Hashable {
  var summary: ManualTransferPreviewSummary
  var items: [ManualTransferPreviewItem]
  var message: String?

  static let empty = ManualTransferPreviewData(
    summary: ManualTransferPreviewSummary(total: 0, success: 0, failed: 0),
    items: [],
    message: nil
  )
}

nonisolated func isResourceMediaSearchKeyword(_ keyword: String) -> Bool {
  keyword.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil
}

/// 资源搜索的流式响应事件 (SSE)
nonisolated struct SearchStreamEvent: Codable, @unchecked Sendable {
  let type: String? // "append", "replace", "done", "error"
  let text: String?
  let text_i18n: String?
  let value: Double?
  let enable: Bool?
  let total_items: Int?
  let items: [Context]?
  let message: String?
  let message_i18n: String?
  
  // AI 重新整理进度使用的结构也类似，可以在需要时复用
  struct AiRedoData: Codable {
    let success: Bool?
    let error: String?
    let error_i18n: String?
  }
  let data: AiRedoData?

  func applyResourceItems(
    to results: inout [Context],
    finalResultApplied: inout Bool
  ) {
    guard let items else { return }
    switch type {
    case "append" where !finalResultApplied:
      results.insert(contentsOf: items, at: 0)
    case "replace":
      results = items
      finalResultApplied = true
    case "done" where !items.isEmpty && !finalResultApplied:
      results = items
      finalResultApplied = true
    default:
      break
    }
  }
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
private struct LossyCustomRule: Decodable {
  let value: CustomRule?

  init(from decoder: Decoder) throws {
    value = try? CustomRule(from: decoder)
  }
}

struct CustomFilterRulesResponse: Codable {
  let value: [CustomRule]

  enum CodingKeys: String, CodingKey {
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedRules = try container.decodeIfPresent([LossyCustomRule].self, forKey: .value) ?? []
    var ids = Set<String>()
    var names = Set<String>()

    // 官方 Web 保存时拒绝空或重复身份；读取旧配置时静默忽略坏项。
    value = decodedRules.compactMap(\.value).filter { rule in
      let id = rule.id.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty, !name.isEmpty, !ids.contains(id), !names.contains(name) else {
        return false
      }
      ids.insert(id)
      names.insert(name)
      return true
    }
  }
}
