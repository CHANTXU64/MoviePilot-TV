import Combine
import CryptoKit
import Foundation

enum APIError: Error {
  case invalidURL
  case networkError(Error)
  case decodingError(Error)
  case unauthorized
  case unknown
}

/// 泛型轻量级接口缓存，带过期及淘汰策略
actor APICache<Key: Hashable, Value> {
  private struct CacheEntry {
    let value: Value
    var expiresAt: Date
  }

  private var cache: [Key: CacheEntry] = [:]
  private let defaultTTL: TimeInterval
  private let size: Int

  init(defaultTTL: TimeInterval = 60, size: Int = 50) {
    self.defaultTTL = defaultTTL
    self.size = size
  }

  func get(_ key: Key) -> Value? {
    guard var entry = cache[key] else { return nil }

    if Date() > entry.expiresAt {
      cache.removeValue(forKey: key)
      return nil
    }

    // 访问时“续期”，变相实现了 LRU
    entry.expiresAt = Date().addingTimeInterval(defaultTTL)
    cache[key] = entry

    return entry.value
  }

  func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
    // 如果缓存已满且要添加的是新 Key，则执行淘汰策略
    if cache.count >= size, cache[key] == nil {
      // 淘汰掉最接近过期的项
      if let keyToEvict = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
        cache.removeValue(forKey: keyToEvict)
      }
    }

    let expiresAt = Date().addingTimeInterval(ttl ?? defaultTTL)
    let newEntry = CacheEntry(value: value, expiresAt: expiresAt)
    cache[key] = newEntry
  }

  func remove(_ key: Key) {
    cache.removeValue(forKey: key)
  }

  func clear() {
    cache.removeAll()
  }
}

@MainActor
class APIService: ObservableObject {
  static let shared = APIService()

  private var loginTask: Task<Void, Error>?

  @Published var baseURL: String =
    UserDefaults.standard.string(forKey: "serverURL") ?? "http://192.168.1.1:3000"
  {
    didSet {
      UserDefaults.standard.set(baseURL, forKey: "serverURL")
    }
  }

  @Published var token: String? =
    KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken")
    ?? UserDefaults.standard.string(forKey: "accessToken")
  {
    didSet {
      if let token = token {
        if !KeychainHelper.shared.save(token, service: "MoviePilot-TV", account: "accessToken") {
          UserDefaults.standard.set(token, forKey: "accessToken")
        }
      } else {
        if !KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "accessToken") {
          print("Failed to delete keychain item for account: accessToken")
        }
        UserDefaults.standard.removeObject(forKey: "accessToken")
      }
    }
  }

  @Published var settings: GlobalSettings? {
    didSet {
      let useCacheSetting = settings?.GLOBAL_IMAGE_CACHE?.value == true
      if #available(tvOS 18.0, *) {
        self.useImageCache = useCacheSetting
      } else {
        // 对于 tvOS 17.x 及更早版本，禁用图像缓存以避免 WEBP 解码问题。
        if useCacheSetting {
          print(
            "ℹ️ Detected tvOS version older than 18.0. Disabling image cache as a workaround for WEBP."
          )
        }
        self.useImageCache = false
      }
    }
  }
  @Published var useImageCache: Bool = false

  // MARK: - 短暂内存缓存 (提升二级页面和分季组件流畅度)
  private let episodeGroupsCache = APICache<String, [EpisodeGroup]>(defaultTTL: 120, size: 20)
  private let mediaSeasonsCache = APICache<String, [TmdbSeason]>(defaultTTL: 120, size: 20)
  private let groupSeasonsCache = APICache<String, [TmdbSeason]>(defaultTTL: 120, size: 20)
  private let seasonsNotExistsCache = APICache<String, [NotExistMediaInfo]>(
    defaultTTL: 120, size: 20)
  private let subscriptionStatusCache = APICache<String, Bool>(defaultTTL: 120, size: 100)

  // MARK: - 用于自动登录的凭据
  private var storedUsername: String? {
    get {
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
        ?? UserDefaults.standard.string(forKey: "username")
    }
    set {
      if let value = newValue {
        if !KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: "username") {
          UserDefaults.standard.set(value, forKey: "username")
        }
      } else {
        if !KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "username") {
          print("Failed to delete keychain item for account: username")
        }
        UserDefaults.standard.removeObject(forKey: "username")
      }
    }
  }

  private var storedPassword: String? {
    get {
      KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password")
        ?? UserDefaults.standard.string(forKey: "password")
    }
    set {
      if let value = newValue {
        if !KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: "password") {
          UserDefaults.standard.set(value, forKey: "password")
        }
      } else {
        if !KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "password") {
          print("Failed to delete keychain item for account: password")
        }
        UserDefaults.standard.removeObject(forKey: "password")
      }
    }
  }

  private init() {}

  var isLoggedIn: Bool {
    return token != nil
  }

  func logout() {
    token = nil
    storedUsername = nil
    storedPassword = nil
  }

  private func makeRequest(
    endpoint: String, method: String = "GET", body: Data? = nil, isForm: Bool = false,
    retryOn401: Bool = true
  ) async throws -> Data {
    guard let url = URL(string: "\(baseURL)/api/v1\(endpoint)") else {
      throw APIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let token = token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if isForm {
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    } else {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse {
      if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        // 如果允许重试，则尝试自动登录
        if retryOn401, let u = storedUsername, let p = storedPassword, !u.isEmpty, !p.isEmpty {
          print("Token expired. Attempting auto-login for user: \(u)")
          let task: Task<Void, Error>
          if let existingTask = loginTask {
            task = existingTask
          } else {
            task = Task { [weak self] in
              guard let self = self else { return }
              defer { self.loginTask = nil }
              _ = try await self.login(username: u, password: p)
            }
            self.loginTask = task
          }
          do {
            try await task.value
            // 使用新令牌递归调用
            return try await makeRequest(
              endpoint: endpoint, method: method, body: body, isForm: isForm, retryOn401: false)
          } catch {
            print("Auto-login failed: \(error)")
            self.logout()
            throw APIError.unauthorized
          }
        }
        self.logout()
        throw APIError.unauthorized
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        print("DEBUG: [makeRequest] HTTP Error: \(httpResponse.statusCode) for \(endpoint)")
        throw APIError.unknown
      }
    }
    return data
  }

  private func buildEndpoint(path: String, params: [String: String?] = [:]) throws -> String {
    guard var components = URLComponents(string: path) else {
      throw APIError.invalidURL
    }
    // 保留 path 中可能已存在的查询参数
    var queryItems = components.queryItems ?? []
    // 添加新的参数
    for (name, value) in params {
      if let value = value {
        queryItems.append(URLQueryItem(name: name, value: value))
      }
    }
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    guard let endpoint = components.string else {
      throw APIError.invalidURL
    }
    return endpoint
  }

  // MARK: - Helpers

  struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let message: String?
  }

  private func decodeOrUnwrap<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    // 1. 尝试解码为 ApiResponse<T>
    do {
      let response = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
      if let wrappedData = response.data {
        return wrappedData
      }
    } catch let error as DecodingError {
      switch error {
      case .typeMismatch(_, let context):
        if context.codingPath.isEmpty {
          // 期望字典 (ApiResponse) 但找到了数组 (T)。直接解码 T。
          break
        } else {
          print(
            "DEBUG: [decodeOrUnwrap] typeMismatch in ApiResponse<\(T.self)> at path \(context.codingPath): \(error)"
          )
          throw APIError.decodingError(error)
        }
      case .keyNotFound(let key, let context):
        print(
          "DEBUG: [decodeOrUnwrap] keyNotFound '\(key.stringValue)' in ApiResponse<\(T.self)> at path \(context.codingPath)"
        )
        throw APIError.decodingError(error)
      case .valueNotFound(let type, let context):
        print(
          "DEBUG: [decodeOrUnwrap] valueNotFound for type \(type) in ApiResponse<\(T.self)> at path \(context.codingPath)"
        )
        throw APIError.decodingError(error)
      default:
        print(
          "DEBUG: [decodeOrUnwrap] dataCorrupted for ApiResponse<\(T.self)> at path \(context(from: error)?.codingPath ?? []): \(error)"
        )
        break
      }
    } catch {
      print("DEBUG: [decodeOrUnwrap] unknown error: \(error)")
    }

    // 2. 尝试直接解码为 T
    return try JSONDecoder().decode(T.self, from: data)
  }

  // 安全提取上下文的辅助函数
  private func context(from error: DecodingError) -> DecodingError.Context? {
    switch error {
    case .typeMismatch(_, let context), .valueNotFound(_, let context),
      .keyNotFound(_, let context), .dataCorrupted(let context):
      return context
    @unknown default:
      return nil
    }
  }

  /// 登录获取 Token
  /// - 对应前端: MoviePilot-Frontend/src/pages/login.vue
  /// - 应用场景: 用户登录验证并获取访问令牌。
  func login(username: String, password: String) async throws -> Token {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "username", value: username),
      URLQueryItem(name: "password", value: password),
    ]
    guard let bodyData = components.query?.data(using: .utf8) else {
      throw APIError.unknown
    }

    // 传递 retryOn401: false 以防止凭据错误时出现无限循环
    let data = try await makeRequest(
      endpoint: "/login/access-token", method: "POST", body: bodyData, isForm: true,
      retryOn401: false)
    let tokenResponse = try JSONDecoder().decode(Token.self, from: data)

    self.token = tokenResponse.access_token
    // 成功时保存凭据
    self.storedUsername = username
    self.storedPassword = password

    return tokenResponse
  }

  /// 获取媒体统计数据
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/AnalyticsMediaStatistic.vue
  /// - 应用场景: 首页仪表盘展示各类媒体的数量统计。
  func fetchStatistic() async throws -> Statistic {
    let data = try await makeRequest(endpoint: "/dashboard/statistic")
    return try decodeOrUnwrap(Statistic.self, from: data)
  }

  /// 获取存储空间信息
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/AnalyticsStorage.vue
  /// - 应用场景: 首页仪表盘展示磁盘/网盘的存储使用情况。
  func fetchStorage() async throws -> Storage {
    let data = try await makeRequest(endpoint: "/dashboard/storage")
    return try decodeOrUnwrap(Storage.self, from: data)
  }

  /// 获取下载器实时信息
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/AnalyticsSpeed.vue
  /// - 应用场景: 首页仪表盘展示当前下载速度与任务信息。
  func fetchDownloaderInfo() async throws -> DownloaderInfo {
    let data = try await makeRequest(endpoint: "/dashboard/downloader")
    return try decodeOrUnwrap(DownloaderInfo.self, from: data)
  }

  /// 获取全局设置
  /// - 对应前端: MoviePilot-Frontend/src/utils/globalSetting.ts (fetchGlobalSettings)
  /// - 应用场景: 初始化系统基础配置（如 TMDB 图片域名、是否启用图片缓存等）。
  func fetchSettings() async throws -> GlobalSettings {
    do {
      let data = try await makeRequest(endpoint: "/system/global?token=moviepilot")
      let response = try decodeOrUnwrap(GlobalSettings.self, from: data)
      self.settings = response
      return response
    } catch {
      print("DEBUG: [fetchSettings] Failed to fetch settings: \(error)")
      throw error
    }
  }

  /// 搜索通用媒体信息
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (path: '/browse/media/search')
  /// - 应用场景: 聚合搜索页面的“电影”和“电视剧”分类结果展示。前端路由 /browse/ 后接的部分即为 API 路径。
  func searchMedia(query: String, page: Int = 1) async throws -> [MediaInfo] {
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: [
        "title": query,
        "page": String(page),
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 搜索合集
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (searchMedia('collection'))
  /// - 应用场景: 聚合搜索页面的“合集”分类。用户在搜索框输入关键词并选择“合集”时调用，用于搜索 TMDB 系列电影。
  func searchCollection(query: String, page: Int = 1) async throws -> [MediaInfo] {
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: [
        "type": "collection",
        "title": query,
        "page": String(page),
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 搜索人物
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (searchMedia('person'))
  /// - 应用场景: 聚合搜索页面的“演职员”分类。用户在搜索框输入关键词并选择“人物”时调用，用于搜索导演、演员等资料。
  func searchPerson(query: String, page: Int = 1) async throws -> [Person] {
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: [
        "type": "person",
        "title": query,
        "page": String(page),
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([Person].self, from: data)
  }

  /// 通用推荐/发现列表获取接口（底层支撑）
  /// - 对应前端:
  ///   1. MoviePilot-Frontend/src/pages/recommend.vue (apipath: recommend/* 系列)
  ///   2. MoviePilot-Frontend/src/views/discover/TheMovieDbView.vue (apipath: discover/tmdb_*)
  ///   3. MoviePilot-Frontend/src/views/discover/DoubanView.vue (apipath: discover/douban_*)
  ///   4. MoviePilot-Frontend/src/views/discover/BangumiView.vue (apipath: discover/bangumi)
  ///   5. MoviePilot-Frontend/src/components/workflow/FetchMediasAction.vue (apipath: recommend/*)
  /// - 应用场景:
  ///   1. 推荐页面 (RecommendViewModel)：加载流行、热门、榜单等货架。
  ///   2. 发现页面 (ExploreViewModel)：按数据源分类加载列表。
  ///   3. 详情页面逻辑支撑：作为 fetchMediaRecommendations 和 fetchMediaSimilar 的底层实现，详情页不能直接调用。
  func fetchRecommend(path: String, page: Int = 1) async throws -> [MediaInfo] {
    let absolutePath = path.hasPrefix("/") ? path : "/\(path)"
    let endpoint = try buildEndpoint(path: absolutePath, params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 获取推荐媒体
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (构造 tmdb|douban|bangumi/recommend/* 系列路径)
  /// - 应用场景: 在媒体详情页底部，根据当前的 tmdb/douban/bangumi ID 获取“推荐”列表。
  /// - ⚠️ 注意: Bangumi 的推荐接口不需要传 type。
  func fetchMediaRecommendations(detail: MediaInfo, page: Int = 1) async throws -> [MediaInfo] {
    var path: String?

    if let tmdbId = detail.tmdb_id {
      guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      else { return [] }
      path = "tmdb/recommend/\(tmdbId)/\(type)"
    } else if let doubanId = detail.douban_id {
      guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      else { return [] }
      path = "douban/recommend/\(doubanId)/\(type)"
    } else if let bangumiId = detail.bangumi_id {
      path = "bangumi/recommend/\(bangumiId)"
    }

    guard let finalPath = path else { return [] }
    return try await fetchRecommend(path: finalPath, page: page)
  }

  /// 获取类似媒体
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (构造 tmdb/similar/* 系列路径)
  /// - 应用场景: 媒体详情页获取相似推荐内容。
  /// - ⚠️ 注意: 仅有 TMDB_ID 的才支持获取相似媒体。
  func fetchMediaSimilar(detail: MediaInfo, page: Int = 1) async throws -> [MediaInfo] {
    guard let tmdbId = detail.tmdb_id else { return [] }
    guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else { return [] }
    let path = "tmdb/similar/\(tmdbId)/\(type)"
    return try await fetchRecommend(path: path, page: page)
  }

  /// 获取合集信息
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/MediaCard.vue (触发跳转), MoviePilot-Frontend/src/views/discover/MediaCardListView.vue (分页加载)
  /// - 应用场景: 用户点击合集卡片后，在合集详情页分页浏览影片列表。
  func fetchCollection(collectionId: Int, page: Int, title: String) async throws -> [MediaInfo] {
    let endpoint = try buildEndpoint(
      path: "/tmdb/collection/\(collectionId)",
      params: [
        "page": String(page),
        "title": title,
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 获取下载客户端列表
  /// - 对应前端: MoviePilot-Frontend/src/pages/downloading.vue, src/components/dialog/SiteAddEditDialog.vue, src/components/dialog/AddDownloadDialog.vue, src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 获取系统配置的所有下载器实例，用于切换下载器视图或在站点/订阅配置中选择下载目标
  func fetchDownloadClients() async throws -> [DownloaderConf] {
    let data = try await makeRequest(endpoint: "/download/clients")
    return try decodeOrUnwrap([DownloaderConf].self, from: data)
  }

  /// 获取下载中任务
  /// - 对应前端: MoviePilot-Frontend/src/views/reorganize/DownloadingListView.vue (通过 apipath)
  /// - 应用场景: 获取特定下载器当前的下载任务列表
  func fetchDownloading(clientName: String) async throws -> [DownloadingInfo] {
    let endpoint = try buildEndpoint(path: "/download/", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([DownloadingInfo].self, from: data)
  }

  /// 暂停下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (toggleDownload)
  /// - 应用场景: 在下载任务列表页暂停指定的下载任务。
  func stopDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/download/stop/\(hash)", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint, method: "GET")
    return try decodeActionResponse(from: data)
  }

  /// 继续下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (toggleDownload)
  /// - 应用场景: 在下载任务列表页恢复指定的已暂停任务。
  func startDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/download/start/\(hash)", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint, method: "GET")
    return try decodeActionResponse(from: data)
  }

  /// 删除下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (deleteDownload)
  /// - 应用场景: 在下载任务列表页删除指定的任务。
  func deleteDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(
      path: "/download/\(hash)",
      params: ["name": clientName]
    )
    let data = try await makeRequest(endpoint: endpoint, method: "DELETE")
    return try decodeActionResponse(from: data)
  }

  /// 辅助方法：解码通用操作响应
  private func decodeActionResponse(from data: Data) throws -> (success: Bool, message: String?) {
    struct ActionResponse: Decodable { let success: Bool?, message: String? }
    if let resp = try? JSONDecoder().decode(ActionResponse.self, from: data) {
      return (resp.success ?? false, resp.message)
    }
    if let apiResp = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return (apiResp.success ?? false, apiResp.message)
    }
    // 默认返回成功，因为某些API成功时可能不返回body
    return (true, nil)
  }

  // MARK: - Media Server

  /// 获取媒体服务器配置
  /// - 对应前端: MoviePilot-Frontend/src/views/setting/AccountSettingSystem.vue, src/views/dashboard/MediaServerLatest.vue 等
  /// - 应用场景: 获取已配置的媒体服务器（Emby/Jellyfin/Plex）列表。该接口是首页仪表盘展示“最新入库”、“正在播放”及“媒体库统计”的基础数据源。
  func fetchMediaServers() async throws -> [MediaServerConf] {
    // API returns { data: { value: [...] } }
    struct ConfigValue: Decodable {
      let value: [MediaServerConf]
    }
    let data = try await makeRequest(endpoint: "/system/setting/MediaServers")
    let config = try decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取媒体服务器最新入库
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/MediaServerLatest.vue
  /// - 应用场景: 首页仪表盘展示最近添加的影片
  func fetchMediaServerLatest(server: String) async throws -> [MediaServerPlayItem] {
    let endpoint = try buildEndpoint(path: "/mediaserver/latest", params: ["server": server])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaServerPlayItem].self, from: data)
  }

  // MARK: - 资源搜索

  /// 搜索资源
  /// - 对应前端: MoviePilot-Frontend/src/pages/resource.vue
  /// - 应用场景: 资源搜索页面的核心接口。
  ///   1. ID 搜索 (正则 ^[a-zA-Z]+:): 调用 /search/media/xx，支持类型、区域、年份、季等聚合过滤。
  ///   2. 标题搜索: 调用 /search/title，支持模糊匹配。
  ///   注：Vue 端若 keyword 为空会调用 /search/last 获取上次结果（TV 端暂未实现）。
  func searchResources(
    keyword: String, type: String? = nil, area: String? = nil, title: String? = nil,
    year: String? = nil, season: Int? = nil, sites: String? = nil
  ) async throws -> [Context] {
    // 匹配 Vue 端逻辑：如果 keyword 的格式是 xxxx:xxxxx 且 : 前面的 xxxx 为字符，则按照媒体 ID 格式搜索
    let isIdSearch = keyword.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil

    let endpoint: String
    if isIdSearch {
      // ID 搜索时，ID 作为路径的一部分，不需要对包含 “:” 的 mediaId 进行编码
      endpoint = try buildEndpoint(
        path: "/search/media/\(keyword)",
        params: [
          "mtype": type,
          "area": area,
          "title": title,
          "year": year,
          "season": season.map(String.init),
          "sites": sites,
        ])
    } else {
      endpoint = try buildEndpoint(
        path: "/search/title",
        params: [
          "keyword": keyword,
          "sites": sites,
        ])
    }
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([Context].self, from: data)
  }

  // MARK: - 详情与订阅

  /// 识别媒体标题（自动识别/猜测）
  /// - 重要区别: 此 API (`/media/recognize`) 用于根据输入的原始标题字符串（如文件名）**自动解析**出结构化信息，类似“猜谜”。
  /// - 对应前端: `MoviePilot-Frontend/src/views/system/NameTestView.vue`
  /// - 应用场景: 名称识别测试页面，用于测试后端的标题识别规则。
  /// - 对比组件: 前端的手动搜索功能由 `MediaIdSelector.vue` UI组件实现，该组件调用 `/media/search` API 来让用户**手动搜索并确认**影视信息。
  /// - tvOS现状: 当前 tvOS 端仅使用了此“自动识别”逻辑，后续审查时需关注其识别准确率是否满足业务场景。
  func recognizeMedia(title: String) async throws -> RecognizeResponse {
    let endpoint = try buildEndpoint(path: "/media/recognize", params: ["title": title])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap(RecognizeResponse.self, from: data)
  }

  /// 获取媒体详情
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue
  /// - 应用场景: 影视剧详情页的主接口，获取最全的媒体信息。
  func fetchMediaDetail(media: MediaInfo) async throws -> MediaInfo {
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，并可能导致上层视图显示“无数据”。
      // 这里直接抛出错误以便上层捕获并处理UI状态。
      throw APIError.invalidURL
    }
    let params: [String: String?] = [
      "type_name": media.type,
      "title": media.title,
      "year": media.year,
    ]
    let endpoint = try buildEndpoint(path: "/media/\(mediaId)", params: params)
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap(MediaInfo.self, from: data)
  }

  /// 获取人物详情
  /// - 对应前端: `MoviePilot-Frontend/src/views/discover/PersonDetailView.vue`
  /// - 应用场景: 导演、演员的人物详情页。
  /// - ⚠️ 参数说明:
  ///   - `source`: **数据源，决定API的路由**。前端直接将其作为路径的一部分。
  func fetchPersonDetail(personId: String, source: String?) async throws -> Person {
    var sourcePath = source ?? "tmdb"
    if sourcePath == "themoviedb" { sourcePath = "tmdb" }
    let endpoint = "/\(sourcePath)/person/\(personId)"
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap(Person.self, from: data)
  }

  /// 获取人物参演作品
  /// - 对应前端: `MoviePilot-Frontend/src/views/discover/PersonCardListView.vue` (通过路由拼装 apipath)
  /// - 应用场景: 人物详情页下方展示的其参演/导演作品列表。
  /// - ⚠️ 参数说明:
  ///   - `source`: **数据源，决定API的路由**。
  func fetchPersonCredits(personId: String, source: String?, page: Int = 1) async throws
    -> [MediaInfo]
  {
    var sourcePath = source ?? "tmdb"
    if sourcePath == "themoviedb" { sourcePath = "tmdb" }
    let endpoint = try buildEndpoint(
      path: "/\(sourcePath)/person/credits/\(personId)",
      params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 获取媒体演员
  /// - 对应前端: `MoviePilot-Frontend/src/pages/credits.vue` (调用 `PersonCardListView.vue` 进行分页加载)
  /// - 应用场景: 影视详情页展示的演员横向列表，支持 TMDB/豆瓣/Bangumi 来源。支持分页加载。
  func fetchMediaActors(detail: MediaInfo, page: Int) async throws -> [Person] {
    var path = ""
    if let tmdbId = detail.tmdb_id {
      let type = detail.type ?? ""
      path = "tmdb/credits/\(tmdbId)/\(type)"
    } else if let doubanId = detail.douban_id {
      let type = detail.type ?? ""
      path = "douban/credits/\(doubanId)/\(type)"
    } else if let bangumiId = detail.bangumi_id {
      path = "bangumi/credits/\(bangumiId)"
    } else {
      return []
    }

    let endpoint = try buildEndpoint(path: "/\(path)", params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeOrUnwrap([Person].self, from: data)
  }

  /// 获取 RSS 站点列表
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 在 **订阅编辑对话框** 中，作为“订阅站点”下拉菜单的数据源。
  func fetchSites() async throws -> [Site] {
    let data = try await makeRequest(endpoint: "/site/rss")
    return try decodeOrUnwrap([Site].self, from: data)
  }

  /// 获取目录配置
  /// - 对应前端: MoviePilot-Frontend/src/views/setting/AccountSettingDirectory.vue
  /// - 应用场景: 添加下载时选择目标存储目录
  func fetchDirectories() async throws -> [TransferDirectoryConf] {
    struct ConfigValue: Decodable {
      let value: [TransferDirectoryConf]
    }
    let data = try await makeRequest(endpoint: "/system/setting/Directories")
    let config = try decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取用户定义的搜索过滤规则组
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 这是一个通用接口，Vue在多个场景中被调用以获取过滤规则组下拉选项：1. **订阅编辑对话框**中的“过滤规则组”。
  func fetchFilterRuleGroups() async throws -> [FilterRuleGroup] {
    struct ConfigValue: Decodable {
      let value: [FilterRuleGroup]
    }
    let data = try await makeRequest(endpoint: "/system/setting/UserFilterRuleGroups")
    let config = try decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取剧集分组信息（针对部分长篇动漫）
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue, MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 在前端，有两个地方会用到：1. **季订阅弹窗**中，用于展示所有可供选择的剧集组（如“司法岛篇”）。 2. **订阅配置编辑弹窗**中，当编辑一个电视剧订阅时，作为“剧集组”下拉框的数据源，允许用户修改该订阅所属的剧集组。
  func fetchEpisodeGroups(tmdbId: Int) async throws -> [EpisodeGroup] {
    let endpoint = "/media/groups/\(tmdbId)"
    if let cached = await episodeGroupsCache.get(endpoint) { return cached }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try decodeOrUnwrap([EpisodeGroup].self, from: data)
    await episodeGroupsCache.set(endpoint, value: result)
    return result
  }

  /// 获取标准电视剧的各季基础信息
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue (getMediaSeasons)
  /// - 应用场景: 在前端的季订阅弹窗中，当用户**未**选择任何特殊的“剧集组”时，调用此 API 获取并展示该剧集在 TMDB 上定义的标准分季信息（S01, S02 等）。
  func getMediaSeasons(media: MediaInfo) async throws -> [TmdbSeason] {
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，返回空数组
      return []
    }
    let params: [String: String?] = [
      "mediaid": mediaId,
      "title": media.title,
      "year": media.year,
      "season": media.season.map(String.init),
    ]
    let endpoint = try buildEndpoint(path: "/media/seasons", params: params)
    if let cached = await mediaSeasonsCache.get(endpoint) { return cached }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try decodeOrUnwrap([TmdbSeason].self, from: data)
    await mediaSeasonsCache.set(endpoint, value: result)
    return result
  }

  /// 获取特定剧集组（如长篇连载划分的部/篇）下的季信息
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue (getGroupSeasons)
  /// - 应用场景: 在前端的季订阅弹窗中，当用户从下拉列表中**选择**了某个“剧集组”（如“司法岛篇”）后，调用此 API 以获取该组专属的分季信息。
  func getGroupSeasons(groupId: String) async throws -> [TmdbSeason] {
    let endpoint = "/media/group/seasons/\(groupId)"
    if let cached = await groupSeasonsCache.get(endpoint) { return cached }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try decodeOrUnwrap([TmdbSeason].self, from: data)
    await groupSeasonsCache.set(endpoint, value: result)
    return result
  }

  /// 批量检查媒体服务器中已入库的季、集状态
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue
  /// - 应用场景: 在前端的 **分季订阅弹窗** 中，实时标记哪些季“已入库”、“部分缺失”或“完全缺失”。
  func checkSeasonsNotExists(mediaInfo: MediaInfo) async throws -> [NotExistMediaInfo] {
    let body = try JSONEncoder().encode(mediaInfo)
    let hash = SHA256.hash(data: body)
    let cacheKey = hash.compactMap { String(format: "%02x", $0) }.joined()
    if let cached = await seasonsNotExistsCache.get(cacheKey) { return cached }
    let data = try await makeRequest(endpoint: "/mediaserver/notexists", method: "POST", body: body)
    let result = try decodeOrUnwrap([NotExistMediaInfo].self, from: data)
    await seasonsNotExistsCache.set(cacheKey, value: result)
    return result
  }

  /// 保存（更新）订阅配置
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue` (更新) 2. `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (新增)
  /// - 应用场景: 1. 在订阅编辑弹窗中点击“保存”，对现有订阅进行修改 (PUT)。 2. 在媒体卡片或详情页上点击订阅，创建新的订阅记录 (POST)。
  func saveSubscription(_ subscribe: Subscribe) async throws -> Bool {
    let body = try JSONEncoder().encode(subscribe)
    let endpoint = "/subscribe/"
    // 如果存在 ID，则很可能是更新 (PUT)，但 API 可能同时处理 POST 或有其他逻辑。
    // 基于 Vue：更新是 PUT /subscribe/，创建是 POST /subscribe/ (或默认配置)
    // 由于 Subscribe 结构体有 ID，如果它 > 0 或不为 nil，则使用 PUT。
    let method = (subscribe.id != nil && subscribe.id != 0) ? "PUT" : "POST"

    let data = try await makeRequest(endpoint: endpoint, method: method, body: body)
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    struct SimpleResp: Decodable {
      let success: Bool?
      let message: String?
    }
    if let resp = try? JSONDecoder().decode(SimpleResp.self, from: data) {
      return resp.success ?? true
    }
    return true
  }

  /// 新增订阅（简单模式）
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue`
  /// - 应用场景: 在媒体卡片或详情页点击“订阅”图标进行快速订阅。
  ///   - **订阅电影时**: 直接调用此 API，请求中的 `season` 参数为 null。
  ///   - **订阅电视剧分季时**: 会先弹出 `SubscribeSeasonDialog.vue` 分季选择框。用户确认后，前端遍历所选的每一季，并为每一季都单独调用一次此 API，每次传入对应的 `season` 编号。
  /// - 备注：Subscribe 参数用于更新订阅状态缓存
  func addSubscription(request: SubscribeRequest, subscribe: Subscribe) async throws -> Int? {
    let body = try JSONEncoder().encode(request)
    let data = try await makeRequest(endpoint: "/subscribe/", method: "POST", body: body)

    struct SubscribeAddResp: Decodable {
      let id: Int?
    }

    if let response = try? JSONDecoder().decode(ApiResponse<SubscribeAddResp>.self, from: data),
      let id = response.data?.id
    {
      if let mediaId = subscribe.apiMediaId {
        let cacheKey = "\(mediaId):\(subscribe.season.map(String.init) ?? "")"
        await subscriptionStatusCache.remove(cacheKey)
      }
      return id
    }
    return nil
  }

  /// 通过订阅 ID 删除订阅
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue` 2. `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`
  /// - 应用场景: 1. 在订阅编辑弹窗中点击“取消订阅”按钮。 2. 在订阅列表页进行批量删除操作时并发调用。
  func deleteSubscription(id: Int) async throws -> Bool {
    let data = try await makeRequest(endpoint: "/subscribe/\(id)", method: "DELETE")
    await subscriptionStatusCache.clear()
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    return true
  }

  /// 通过媒体 ID 和季数删除订阅
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue`
  /// - 应用场景: 在详情页或媒体卡片上，取消对该媒体的订阅（点击已激活的心形图标）。
  func deleteSubscription(media: MediaInfo, season: Int?) async throws -> Bool {
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，返回失败
      return false
    }
    let endpoint = try buildEndpoint(
      path: "/subscribe/media/\(mediaId)",
      params: ["season": season.map(String.init)])
    let data = try await makeRequest(endpoint: endpoint, method: "DELETE")
    let cacheKey = "\(mediaId):\(season.map(String.init) ?? "")"
    await subscriptionStatusCache.remove(cacheKey)
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    return true
  }

  /// 暂停或恢复订阅状态
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/cards/SubscribeCard.vue` 2. `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`
  /// - 应用场景: 1. 在订阅列表页对单个卡片进行“暂停/恢复”切换。 2. 在订阅列表页进行批量暂停/恢复操作时并发调用。
  func updateSubscriptionStatus(id: Int, state: String) async throws -> Bool {
    let endpoint = try buildEndpoint(path: "/subscribe/status/\(id)", params: ["state": state])
    let data = try await makeRequest(endpoint: endpoint, method: "PUT")
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    return true
  }

  /// 立即触发订阅搜索
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue (searchSubscribe)
  /// - 应用场景: 用户在订阅列表手动点击“搜索”按钮，强制后端立即针对该条目执行一次资源检索。
  func searchSubscription(id: Int) async throws -> Bool {
    let data = try await makeRequest(endpoint: "/subscribe/search/\(id)")
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    return true
  }

  /// 重置订阅状态（重新开始）
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue (resetSubscribe)
  /// - 应用场景: 清除该条目的已下载/已入库记录，使其状态回到初始，通常用于重新洗版或出错后重试。
  func resetSubscription(id: Int) async throws -> Bool {
    let data = try await makeRequest(endpoint: "/subscribe/reset/\(id)")
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return response.success ?? false
    }
    return true
  }

  /// 获取单条订阅详情
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 编辑订阅前获取完整订阅配置
  func fetchSubscription(id: Int) async throws -> Subscribe {
    let data = try await makeRequest(endpoint: "/subscribe/\(id)")
    return try decodeOrUnwrap(Subscribe.self, from: data)
  }

  /// 检查特定媒体（及特定季）是否已在用户的订阅列表中
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue`
  /// - 应用场景: 进入详情页或媒体卡片进入视窗时懒加载调用，用于实时检查并更新“心形”订阅按钮的状态。
  /// - 备注: 创建订阅使用的是原始 ID，请勿混淆。
  func checkSubscription(media: MediaInfo, season: Int? = nil) async throws -> Bool {
    struct SubscribeResp: Codable {
      let id: Int?
    }
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，返回 false
      return false
    }
    do {
      let cacheKey = "\(mediaId):\(season.map(String.init) ?? "")"
      if let cached = await subscriptionStatusCache.get(cacheKey) {
        return cached
      }
      let endpoint = try buildEndpoint(
        path: "/subscribe/media/\(mediaId)",
        params: [
          "season": season.map(String.init),
          "title": media.title,
        ])
      let data = try await makeRequest(endpoint: endpoint)
      let resp = try decodeOrUnwrap(SubscribeResp.self, from: data)
      let isSubscribed = resp.id != nil
      await subscriptionStatusCache.set(cacheKey, value: isSubscribed)
      return isSubscribed
    } catch {
      return false
    }
  }

  /// 拉取当前用户的所有订阅列表
  /// - 对应前端: `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`, `MoviePilot-Frontend/src/views/subscribe/FullCalendarView.vue`
  /// - 应用场景: 1. **订阅列表页面** (`SubscribeListView`) 的核心数据源。 2. **日历视图** (`FullCalendarView`) 的数据源。 (注: 全局搜索栏不直接调用此API)
  func fetchSubscriptions() async throws -> [Subscribe] {
    let data = try await makeRequest(endpoint: "/subscribe/")
    return try decodeOrUnwrap([Subscribe].self, from: data)
  }

  /// 添加下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/AddDownloadDialog.vue
  /// - 应用场景: 在资源搜索结果中选择特定条目后，将其推送到后端下载器执行下载。
  func addDownload(payload: AddDownloadRequest, endpoint: String) async throws -> (
    success: Bool, message: String?
  ) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let body = try encoder.encode(payload)

    let data = try await makeRequest(endpoint: endpoint, method: "POST", body: body)

    struct DownloadResp: Decodable {
      let success: Bool?
      let message: String?
    }

    // 尝试解码简单的成功/消息响应
    if let resp = try? JSONDecoder().decode(DownloadResp.self, from: data) {
      return (resp.success ?? false, resp.message)
    }

    // 尝试解码标准的 ApiResponse 包装器
    if let response = try? JSONDecoder().decode(ApiResponse<String>.self, from: data) {
      return (response.success ?? false, response.message)
    }

    return (true, nil)
  }

  /// 获取订阅的海报图片 URL
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue
  /// - 应用场景: 在订阅卡片中展示海报，并处理全局缓存代理。
  func getSubscribePosterImageUrl(_ subscribe: Subscribe) -> URL? {
    guard let url = subscribe.poster, !url.isEmpty else { return nil }

    if useImageCache {
      guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    return URL(string: url)
  }

  /// 获取媒体海报图片 URL
  /// - 对应前端:
  ///   1. MoviePilot-Frontend/src/components/cards/MediaCard.vue (getImgUrl)
  ///   2. MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (getPosterUrl)
  /// - 应用场景: 自动处理 original 替换为 w500，并针对豆瓣图片进行反盗链代理中转，同时处理系统全局图片缓存。用于通用媒体卡片（电影/电视剧）的海报展示以及详情页的海报展示。
  func getPosterImageUrl(_ media: MediaInfo) -> URL? {
    let url = media.poster_path?.replacingOccurrences(of: "original", with: "w500")

    // 1. 如果地址中包含 douban 则使用中转代理 (豆瓣必须中转)
    if let currentUrl = url, currentUrl.contains("doubanio.com") {
      guard
        let encodedUrl = currentUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)")
    }

    // 2. 否则根据设置判断是否使用图片缓存
    if useImageCache, let currentUrl = url {
      guard
        let encodedUrl = currentUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    if let finalUrl = url {
      return URL(string: finalUrl)
    }
    return nil
  }

  /// 获取媒体背景图片 URL
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (getBackdropUrl)
  /// - 应用场景: 详情页大图背景展示，处理系统全局图片缓存中转。
  func getBackdropImageUrl(_ media: MediaInfo) -> URL? {
    guard let url = media.backdrop_path, !url.isEmpty else { return nil }

    // 使用图片缓存
    if useImageCache {
      guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    return URL(string: url)
  }

  /// 获取下载 Card 中的背景图片
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue
  /// - 应用场景: 下载任务卡的背景图片
  /// 备注：前端是直接访问没有使用缓存，经过测试走缓存没有问题，这是抓包的 Image: https://image.tmdb.org/t/p/w500/zJJQCD9xMhDD4MlQ6haaP3IBCHk.jpg
  func getDownloadItemBackdropImageUrl(_ media: DownloadingMediaInfo) -> URL? {
    guard let url = media.image, !url.isEmpty else { return nil }
    // 使用图片缓存
    if useImageCache {
      guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    return URL(string: url)
  }

  /// 获取媒体服务器播放项的海报
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/PosterCard.vue (getImgUrl)
  /// - 应用场景: 首页的媒体服务器最近播放或最新入库图片代理。通过 system/img/0 代理图片并携带 use_cookies 参数。
  func getMediaServerPosterImageURL(_ item: MediaServerPlayItem) -> URL? {
    guard let path = item.image, !path.isEmpty else { return nil }
    guard let encodedUrl = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return nil
    }

    var urlString = "\(baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)"

    // use_cookies 现在是 FlexibleBool?
    if item.use_cookies?.value == true {
      urlString += "&use_cookies=true"
    }

    return URL(string: urlString)
  }

  /// 获取季海报 URL，严格参照 Vue 逻辑
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue (getSeasonPoster)
  /// - 应用场景: 电视剧订阅页面展示具体季的海报，缺失时平滑降级为剧集总海报。
  func getSeasonPosterURL(posterPath: String?, mediaPosterPath: String?) -> URL? {
    // Vue: if (!posterPath) return props.media?.poster_path
    guard let posterPath = posterPath, !posterPath.isEmpty else {
      guard let mediaPosterPath = mediaPosterPath, !mediaPosterPath.isEmpty else { return nil }
      return URL(string: mediaPosterPath)
    }

    // Vue: return `https://${globalSettings.TMDB_IMAGE_DOMAIN}/t/p/w500${posterPath}`
    let domain = settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
    return URL(string: "https://\(domain)/t/p/w500\(posterPath)")
  }

  /// 获取人物图片 URL
  /// - 对应前端:
  ///   1. MoviePilot-Frontend/src/components/cards/PersonCard.vue (getPersonImage)
  ///   2. MoviePilot-Frontend/src/views/discover/PersonDetailView.vue (getPersonImage)
  /// - 应用场景: 演员列表、人物卡片头像及人物详情页的大图头像。聚合判断图片来源 (TMDB/Douban/Bangumi)，包含拦截豆瓣无头像占位图(personage-default)的原创优化。
  func getPersonImage(_ person: Person) -> URL? {
    return getPersonImageURL(from: person)
  }

  /// 获取 Staff 人员图片 URL
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/PersonCard.vue (getPersonImage)
  /// - 应用场景: 获取制作人员/工作人员图片，本质与 getPersonImage 逻辑完全一致，仅做语义区分。
  func getStaffImageURL(_ person: Person) -> URL? {
    return getPersonImageURL(from: person)
  }

  private func getPersonImageURL(from person: Person) -> URL? {
    var url = ""
    var source = person.source

    // 自动推断来源（对齐 getStaffImageURL 逻辑，Vue: getPersonImage）
    if source == nil || (source?.isEmpty ?? true) {
      if let profilePath = person.profile_path, profilePath.hasPrefix("/") {
        source = "themoviedb"
      } else if person.avatar != nil {
        source = "douban"
      } else if person.images != nil {
        source = "bangumi"
      } else if let profilePath = person.profile_path, profilePath.hasPrefix("http") {
        url = profilePath
      }
    }

    if source == "themoviedb" {
      if person.profile_path == nil && url.isEmpty {
        return nil
      }
      let domain = settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
      let path = person.profile_path ?? ""
      // 保护逻辑：只有当 url 尚未被赋值（例如未由绝对路径推断补充）时才做拼接
      if url.isEmpty {
        url = "https://\(domain)/t/p/w600_and_h900_bestv2\(path)"
      }
    } else if source == "douban" {
      guard let avatar = person.avatar else {
        return nil
      }
      switch avatar {
      case .object(let normal):
        url = normal
      case .url(let link):
        url = link
      }
    } else if source == "bangumi" {
      guard let medium = person.images?.medium else {
        return nil
      }
      url = medium
    }

    if url.isEmpty {
      return nil
    }

    // 匹配豆瓣默认人员图标并拦截 (针对 Apple TV 的特殊优化，Vue 会顺推显示丑陋的缩略默认图)
    if url.contains("doubanio.com")
      && (url.contains("personage-default") || (url.contains("celebrity-default")))
    {
      return nil
    }

    if useImageCache {
      guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    return URL(string: url)
  }
}
