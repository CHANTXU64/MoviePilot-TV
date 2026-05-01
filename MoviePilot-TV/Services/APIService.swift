import Combine
import CryptoKit
import Foundation

enum APIError: Error {
  case invalidURL
  case networkError(Error)
  case decodingError(Error)
  case serverMessage(String)
  case unauthorized
  case unknown
}

nonisolated struct ApiResponse<T: Decodable>: Decodable {
  let success: Bool?
  let data: T?
  let message: String?
}

nonisolated struct MediaImageURLConfig: Sendable {
  let baseURL: String
  let useImageCache: Bool
}

nonisolated private func decodingContext(from error: DecodingError) -> DecodingError.Context? {
  switch error {
  case .typeMismatch(_, let context), .valueNotFound(_, let context),
    .keyNotFound(_, let context), .dataCorrupted(let context):
    return context
  @unknown default:
    return nil
  }
}

nonisolated private func firstNonWhitespaceByte(in data: Data) -> UInt8? {
  data.first { byte in
    byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D
  }
}

nonisolated private func decodeOrUnwrapSync<T: Decodable>(from data: Data) throws -> T {
  let firstByte = firstNonWhitespaceByte(in: data)

  // 顶层数组场景直接解码目标类型，避免先解包 ApiResponse 再失败重试。
  if firstByte == UInt8(ascii: "[") {
    return try JSONDecoder().decode(T.self, from: data)
  }

  if firstByte == UInt8(ascii: "{") {
    do {
      let response = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
      if let wrappedData = response.data {
        return wrappedData
      }
      if response.success == false {
        throw APIError.serverMessage(response.message ?? "Request failed")
      }
      if let message = response.message, !message.isEmpty {
        throw APIError.serverMessage(message)
      }
    } catch let error as APIError {
      throw error
    } catch let error as DecodingError {
      if let context = decodingContext(from: error), !context.codingPath.isEmpty {
        throw APIError.decodingError(error)
      }
    } catch {
      print("DEBUG: [decodeOrUnwrap] unknown error: \(error)")
    }
  }

  return try JSONDecoder().decode(T.self, from: data)
}

nonisolated private func decodeActionResponseSync(from data: Data) throws -> (
  success: Bool, message: String?
) {
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

nonisolated private func posterImageURL(posterPath: String?, config: MediaImageURLConfig) -> URL? {
  let url = posterPath?.replacingOccurrences(of: "original", with: "w500")

  if let currentUrl = url, currentUrl.contains("doubanio.com") {
    if currentUrl.contains("movie_default") || currentUrl.contains("tv_default") {
      return nil
    }
  }

  if let currentUrl = url, currentUrl.contains("doubanio.com") {
    guard
      let encodedUrl = currentUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return nil
    }
    return URL(string: "\(config.baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)")
  }

  if config.useImageCache, let currentUrl = url {
    guard
      let encodedUrl = currentUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return nil
    }
    return URL(string: "\(config.baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
  }

  if let finalUrl = url {
    return URL(string: finalUrl)
  }
  return nil
}

nonisolated private func backdropImageURL(backdropPath: String?, config: MediaImageURLConfig)
  -> URL?
{
  guard let url = backdropPath, !url.isEmpty else { return nil }

  if config.useImageCache {
    guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return nil
    }
    return URL(string: "\(config.baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
  }

  return URL(string: url)
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

  private func decodeOrUnwrap<T: Decodable>(
    _ type: T.Type,
    from data: Data
  ) async throws -> T {
    if type == MediaInfo.self {
      let config = currentMediaImageURLConfig()
      let mappedMedia = try await decodeMediaInfoInBackground(from: data, config: config)
      guard let mapped = mappedMedia as? T else {
        throw APIError.decodingError(
          DecodingError.typeMismatch(
            T.self,
            DecodingError.Context(
              codingPath: [], debugDescription: "Failed to map MediaInfoJSON to \(T.self)")
          ))
      }
      return mapped
    }
    if type == [MediaInfo].self {
      let config = currentMediaImageURLConfig()
      let mappedMedia = try await decodeMediaInfoArrayInBackground(from: data, config: config)
      guard let mapped = mappedMedia as? T else {
        throw APIError.decodingError(
          DecodingError.typeMismatch(
            T.self,
            DecodingError.Context(
              codingPath: [], debugDescription: "Failed to map [MediaInfoJSON] to \(T.self)")
          ))
      }
      return mapped
    }
    return try decodeOrUnwrapSync(from: data)
  }

  private func currentMediaImageURLConfig() -> MediaImageURLConfig {
    MediaImageURLConfig(baseURL: baseURL, useImageCache: useImageCache)
  }

  /// 仅对 MediaInfo 热路径做后台解码，避免主线程解析大 JSON。
  private func decodeMediaInfoInBackground(from data: Data, config: MediaImageURLConfig)
    async throws -> MediaInfo
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<MediaInfo, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let raw: MediaInfoJSON = try decodeOrUnwrapSync(from: data)
          let imageURLs = MediaInfo.ImageURLs(
            poster: posterImageURL(posterPath: raw.poster_path, config: config),
            backdrop: backdropImageURL(backdropPath: raw.backdrop_path, config: config)
          )
          continuation.resume(returning: MediaInfo(json: raw, precomputedImageURLs: imageURLs))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// 仅对 MediaInfo 列表热路径做后台解码，缓解分页加载时的主线程压力。
  private func decodeMediaInfoArrayInBackground(from data: Data, config: MediaImageURLConfig)
    async throws -> [MediaInfo]
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[MediaInfo], Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let raw: [MediaInfoJSON] = try decodeOrUnwrapSync(from: data)
          let mapped = raw.map { item -> MediaInfo in
            let imageURLs = MediaInfo.ImageURLs(
              poster: posterImageURL(posterPath: item.poster_path, config: config),
              backdrop: backdropImageURL(backdropPath: item.backdrop_path, config: config)
            )
            return MediaInfo(json: item, precomputedImageURLs: imageURLs)
          }
          continuation.resume(returning: mapped)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// 静默验证 Token 有效性。
  /// 仅在 App 启动、切回前台或 Tab 切换时调用，频率极低且不阻塞 UI。
  /// 如果 Token 失效且有保存凭证，makeRequest 会自动触发重连并更新 Cookie。
  func validateTokenSilently() {
    guard isLoggedIn else { return }

    Task {
      do {
        // 请求一个极其轻量的接口来验证 Token 和更新 Cookie
        _ = try await makeRequest(endpoint: "/dashboard/statistic", retryOn401: true)
        print("Token/Session validation successful.")
      } catch {
        print("Silent token validation background process handled: \(error)")
      }
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
    return try await decodeOrUnwrap(Statistic.self, from: data)
  }

  /// 获取存储空间信息
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/AnalyticsStorage.vue
  /// - 应用场景: 首页仪表盘展示磁盘/网盘的存储使用情况。
  func fetchStorage() async throws -> Storage {
    let data = try await makeRequest(endpoint: "/dashboard/storage")
    return try await decodeOrUnwrap(Storage.self, from: data)
  }

  /// 获取下载器实时信息
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/AnalyticsSpeed.vue
  /// - 应用场景: 首页仪表盘展示当前下载速度与任务信息。
  func fetchDownloaderInfo() async throws -> DownloaderInfo {
    let data = try await makeRequest(endpoint: "/dashboard/downloader")
    return try await decodeOrUnwrap(DownloaderInfo.self, from: data)
  }

  /// 获取全局设置
  /// - 对应前端: MoviePilot-Frontend/src/utils/globalSetting.ts (fetchGlobalSettings)
  /// - 应用场景: 初始化系统基础配置（如 TMDB 图片域名、是否启用图片缓存等）。
  func fetchSettings() async throws -> GlobalSettings {
    do {
      let data = try await makeRequest(endpoint: "/system/global?token=moviepilot")
      let response = try await decodeOrUnwrap(GlobalSettings.self, from: data)
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
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 归一化媒体类型名称，统一转换为 API 识别的 'movie' 或 'tv'
  private func normalizeMediaType(_ type: String) -> String {
    let t = type.lowercased()
    if t == "电影" || t == "movie" { return "movie" }
    if t == "电视剧" || t == "剧集" || t == "tv" { return "tv" }
    return t
  }

  /// 优化后的 TMDB ID 识别逻辑 (移植并增强自 MediaIdSelector.vue)
  /// 结合了 searchMedia (基于影视数据库的精确搜索) 和 recognizeMedia (基于名称规则的模糊猜测)
  /// 旨在提升 Douban、Bangumi、媒体库项目的识别准确率。
  func recognizeTmdbId(title: String, year: String? = nil, type: String? = nil) async -> Int? {
    var queryTitle = title.trimmingCharacters(in: .whitespaces)
    let searchYear = year?.trimmingCharacters(in: .whitespaces)

    guard !queryTitle.isEmpty else { return nil }

    // 1. 媒体库标题清洗逻辑：如果标题包含年份（常见于 Emby/Plex），则剥离年份以提高搜索准度
    if let sy = searchYear, sy.count == 4, queryTitle.contains(sy) {
      // 包含半角、全角及空格的年份后缀模式
      let patterns = [
        "(\(sy))", "[\(sy)]", " \(sy)",
        "（\(sy)）", "【\(sy)】", "　\(sy)"
      ]
      for pattern in patterns {
        queryTitle = queryTitle.replacingOccurrences(of: pattern, with: "")
      }
    }

    // 1.5 电视剧季数清洗逻辑：移除 "第二季"、"Season 2"、"S02" 等后缀，以便匹配 TMDB 原始系列标题
    let seasonPatterns = ["\\s*第[一二三四五六七八九十\\d]+季$", "\\s*Season\\s*\\d+$", "\\s*S\\d+$"]
    for pattern in seasonPatterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
        let range = NSRange(queryTitle.startIndex..., in: queryTitle)
        queryTitle = regex.stringByReplacingMatches(in: queryTitle, options: [], range: range, withTemplate: "")
      }
    }
    queryTitle = queryTitle.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !queryTitle.isEmpty else { return nil }

    // 2. 尝试使用 searchMedia 进行精确搜索
    do {
      Logger.debug("[APIService] 开始 TMDB 搜索识别: '\(title)' -> 清洗后: '\(queryTitle)'", metadata: ["year": searchYear ?? "n/a", "type": type ?? "n/a"])
      
      // 恢复原始调用：API 不带 type 参数，保持与 SearchBarDialog.vue 一致
      let results = try await searchMedia(query: queryTitle)
      let targetTitle = queryTitle.lowercased().trimmingCharacters(in: .whitespaces)

      let normalizedTargetType = type.map { normalizeMediaType($0) }

      // 第一轮：最严格匹配（标题 + 类型 + 年份完全一致）
      for result in results {
        let rTitle = (result.title ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let rOrigTitle = (result.original_title ?? "").lowercased().trimmingCharacters(
          in: .whitespaces)
        let rOrigName = (result.original_name ?? "").lowercased().trimmingCharacters(
          in: .whitespaces)

        let titleMatch =
          (rTitle == targetTitle || rOrigTitle == targetTitle || rOrigName == targetTitle)

        let typeMatch: Bool = {
          guard let targetT = normalizedTargetType, let resultT = result.type else { return true }
          return targetT == normalizeMediaType(resultT)
        }()

        // 年份必须完全一致（如果都有年份的话）
        let yearMatch = (searchYear == nil || result.year == nil || searchYear == result.year)

        if titleMatch && typeMatch && yearMatch {
          if let tmdbId = result.tmdb_id {
            Logger.info("[APIService] Search 识别成功 (严格匹配): \(rTitle), TMDB: \(tmdbId)")
            return tmdbId
          }
        }
      }

      // 第二轮：允许1年误差的匹配（标题 + 类型 + 年份误差1年）
      for result in results {
        let rTitle = (result.title ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let rOrigTitle = (result.original_title ?? "").lowercased().trimmingCharacters(
          in: .whitespaces)
        let rOrigName = (result.original_name ?? "").lowercased().trimmingCharacters(
          in: .whitespaces)

        let titleMatch =
          (rTitle == targetTitle || rOrigTitle == targetTitle || rOrigName == targetTitle)

        let typeMatch: Bool = {
          guard let targetT = normalizedTargetType, let resultT = result.type else { return true }
          return targetT == normalizeMediaType(resultT)
        }()

        // 允许年份有 1 年的误差（上映 vs 制作）
        let yearMatch: Bool = {
          guard let sy = searchYear, let ry = result.year else { return true }
          if sy == ry { return true }
          if let siy = Int(sy), let riy = Int(ry) {
            return abs(siy - riy) <= 1
          }
          return false
        }()

        if titleMatch && typeMatch && yearMatch {
          if let tmdbId = result.tmdb_id {
            Logger.info("[APIService] Search 识别成功 (年份误差匹配): \(rTitle), TMDB: \(tmdbId)")
            return tmdbId
          }
        }
      }
    } catch {
      Logger.error("[APIService] searchMedia during recognition failed: \(error)")
    }

    // 3. Fallback 到 recognizeMedia
    // 适用于包含季、集、制作组信息的原始文件名字符串
    do {
      Logger.debug("[APIService] Search 未命中，尝试 Fallback 到后端 Recognize 接口: \(title)")
      let recognizeQuery =
        (searchYear != nil && !title.contains(searchYear!)) ? "\(title) \(searchYear!)" : title
      let result = try await recognizeMedia(title: recognizeQuery)

      // 检查识别出的类型是否匹配（如果已知 type）
      if let targetType = type, let recognizedType = result.media_info?.type {
        if normalizeMediaType(targetType) == normalizeMediaType(recognizedType) {
          if let tmdbId = result.media_info?.tmdb_id {
             Logger.info("[APIService] Recognize 识别成功: \(result.media_info?.title ?? ""), TMDB: \(tmdbId)")
             return tmdbId
          }
        } else {
          // 识别出的类型不符，属于误报，拒绝该结果
          Logger.warning("[APIService] recognizeMedia 类型不匹配: 期望 \(targetType), 实际 \(recognizedType)")
          return nil
        }
      }

      if let tmdbId = result.media_info?.tmdb_id {
        Logger.info("[APIService] Recognize 识别成功: \(result.media_info?.title ?? ""), TMDB: \(tmdbId)")
        return tmdbId
      }
    } catch {
      Logger.error("[APIService] recognizeMedia fallback failed: \(error)")
    }

    Logger.info("[APIService] 识别失败: \(title)")
    return nil
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
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
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
    return try await decodeOrUnwrap([Person].self, from: data)
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
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 获取订阅分享列表
  /// - 对应前端: MoviePilot-Frontend/src/views/subscribe/SubscribeShareView.vue (fetchData)
  /// - 应用场景: "探索"页面的"订阅分享"板块，分页加载用户分享的订阅规则。
  func fetchSubscriptionShares(path: String, page: Int = 1) async throws -> [SubscribeShare] {
    let absolutePath = path.hasPrefix("/") ? path : "/\(path)"
    let endpoint = try buildEndpoint(path: absolutePath, params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([SubscribeShare].self, from: data)
  }

  /// 搜索订阅分享
  /// - 对应前端: MoviePilot-Frontend/src/views/subscribe/SubscribeShareView.vue (但增加了搜索功能)
  /// - 应用场景: 聚合搜索页面，与电影、电视剧、人物等结果一同展示。
  func searchSubscriptionShares(query: String, page: Int = 1) async throws -> [SubscribeShare] {
    let endpoint = try buildEndpoint(
      path: "/subscribe/shares",
      params: [
        "name": query,
        "page": String(page),
        "count": "20",
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([SubscribeShare].self, from: data)
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
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 获取下载客户端列表
  /// - 对应前端: MoviePilot-Frontend/src/pages/downloading.vue, src/components/dialog/SiteAddEditDialog.vue, src/components/dialog/AddDownloadDialog.vue, src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 获取系统配置的所有下载器实例，用于切换下载器视图或在站点/订阅配置中选择下载目标
  func fetchDownloadClients() async throws -> [DownloaderConf] {
    let data = try await makeRequest(endpoint: "/download/clients")
    return try await decodeOrUnwrap([DownloaderConf].self, from: data)
  }

  /// 获取下载中任务
  /// - 对应前端: MoviePilot-Frontend/src/views/reorganize/DownloadingListView.vue (通过 apipath)
  /// - 应用场景: 获取特定下载器当前的下载任务列表
  func fetchDownloading(clientName: String) async throws -> [DownloadingInfo] {
    let endpoint = try buildEndpoint(path: "/download/", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([DownloadingInfo].self, from: data)
  }

  /// 暂停下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (toggleDownload)
  /// - 应用场景: 在下载任务列表页暂停指定的下载任务。
  func stopDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/download/stop/\(hash)", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint, method: "GET")
    return try await decodeActionResponse(from: data)
  }

  /// 继续下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (toggleDownload)
  /// - 应用场景: 在下载任务列表页恢复指定的已暂停任务。
  func startDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/download/start/\(hash)", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint, method: "GET")
    return try await decodeActionResponse(from: data)
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
    return try await decodeActionResponse(from: data)
  }

  /// 辅助方法：解码通用操作响应
  private func decodeActionResponse(from data: Data) async throws -> (
    success: Bool,
    message: String?
  ) {
    try decodeActionResponseSync(from: data)
  }

  // MARK: - Transfer History

  /// 获取媒体整理历史
  /// - 对应前端: `MoviePilot-Frontend/src/views/reorganize/TransferHistoryView.vue`
  /// - 应用场景: "媒体整理"页面，分页加载历史记录。
  /// - Parameters:
  ///   - page: 分页页码。
  ///   - count: 每页数量。
  ///   - title: 按标题搜索的关键词。
  func fetchTransferHistory(page: Int, count: Int, title: String?) async throws
    -> TransferHistoryResponse
  {
    let endpoint = try buildEndpoint(
      path: "/history/transfer",
      params: [
        "page": String(page),
        "count": String(count),
        "title": title,
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap(TransferHistoryResponse.self, from: data)
  }

  /// 删除整理历史记录
  /// - 对应前端: `MoviePilot-Frontend/src/views/reorganize/TransferHistoryView.vue` (remove)
  /// - 应用场景: 在"媒体整理"页面删除一条或多条历史记录。
  /// - Parameters:
  ///   - item: 要删除的历史记录项。
  ///   - deleteSource: 是否同时删除源文件。
  ///   - deleteDest: 是否同时删除目标文件。
  func deleteTransferHistory(item: TransferHistory, deleteSource: Bool, deleteDest: Bool)
    async throws
    -> Bool
  {
    let body = try JSONEncoder().encode(item)
    let endpoint = try buildEndpoint(
      path: "/history/transfer",
      params: [
        "deletesrc": String(deleteSource),
        "deletedest": String(deleteDest),
      ])
    let data = try await makeRequest(endpoint: endpoint, method: "DELETE", body: body)
    return try await decodeActionResponse(from: data).success
  }

  /// AI重新整理历史记录
  /// - 对应前端: `MoviePilot-Frontend/src/views/reorganize/TransferHistoryView.vue`
  func aiRedoTransferHistory(id: Int) async throws -> String? {
    let endpoint = try buildEndpoint(path: "/history/transfer/\(id)/ai-redo")
    let data = try await makeRequest(endpoint: endpoint, method: "POST")
    struct AiRedoResponse: Codable {
      let success: Bool?
      let message: String?
      let data: AiRedoResponseData?
    }
    struct AiRedoResponseData: Codable {
      let progress_key: String?
    }
    let res = try JSONDecoder().decode(AiRedoResponse.self, from: data)
    guard res.success == true else {
      throw APIError.serverMessage(res.message ?? "未知错误")
    }
    return res.data?.progress_key
  }

  /// 手动整理
  /// - 对应前端: `MoviePilot-Frontend/src/components/dialog/ReorganizeDialog.vue`
  /// - 应用场景: 执行手动文件整理或重新整理。
  /// - Parameters:
  ///   - form: 包含整理所需全部信息的表单。
  ///   - background: 是否在后台执行整理任务。`true`为后台执行，会立即返回；`false`为前台执行，会等待任务完成。
  func manualTransfer(form: ReorganizeForm, background: Bool) async throws -> Bool {
    let body = try JSONEncoder().encode(form)
    let endpoint = try buildEndpoint(
      path: "/transfer/manual", params: ["background": String(background)])
    let data = try await makeRequest(endpoint: endpoint, method: "POST", body: body)
    return try await decodeActionResponse(from: data).success
  }

  /// 获取存储配置
  /// - 对应前端: `MoviePilot-Frontend/src/components/dialog/ReorganizeDialog.vue` (loadStorages)
  /// - 应用场景: 在手动整理弹窗中，加载可用的目标存储（如 local, alipan, rclone 等）列表。
  func fetchStorages() async throws -> [StorageConf] {
    struct ConfigValue: Decodable {
      let value: [StorageConf]
    }
    let data = try await makeRequest(endpoint: "/system/setting/Storages")
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
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
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取媒体服务器最新入库
  /// - 对应前端: MoviePilot-Frontend/src/views/dashboard/MediaServerLatest.vue
  /// - 应用场景: 首页仪表盘展示最近添加的影片
  func fetchMediaServerLatest(server: String) async throws -> [MediaServerPlayItem] {
    let endpoint = try buildEndpoint(path: "/mediaserver/latest", params: ["server": server])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([MediaServerPlayItem].self, from: data)
  }

  // MARK: - 资源搜索

  // MARK: - Server-Sent Events (SSE) Streaming

  /// 通用 SSE 流式请求
  private func streamSSE(endpoint: String) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    let serviceBaseURL = baseURL
    let authToken = token

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          guard let url = URL(string: "\(serviceBaseURL)/api/v1\(endpoint)") else {
            throw APIError.invalidURL
          }
          var request = URLRequest(url: url)
          request.timeoutInterval = 300 // 长连接
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

          if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
          }

          let (result, response) = try await URLSession.shared.bytes(for: request)

          guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverMessage("无效响应")
          }

          if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 401 {
              throw APIError.unauthorized
            }
            throw APIError.serverMessage("HTTP Error \(httpResponse.statusCode)")
          }

          for try await line in result.lines {
            if line.hasPrefix("data:") {
              let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
              if let data = jsonString.data(using: .utf8) {
                do {
                  let event = try JSONDecoder().decode(SearchStreamEvent.self, from: data)
                  continuation.yield(event)
                } catch {
                  print("SSE Decoding Error: \(error), raw string: \(jsonString)")
                }
              }
            }
          }
          continuation.finish()
        } catch {
          if Task.isCancelled {
            continuation.finish()
          } else {
            continuation.finish(throwing: error)
          }
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// 流式标题搜索 (SSE)
  func searchTitleStream(keyword: String, sites: String?) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    do {
      let endpoint = try buildEndpoint(
        path: "/search/title/stream",
        params: [
          "keyword": keyword,
          "sites": sites,
        ]
      )
      return streamSSE(endpoint: endpoint)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  }

  /// 流式聚合媒体搜索 (SSE)
  func searchMediaStream(
    keyword: String, type: String?, area: String?, title: String?, year: String?, season: Int?, sites: String?
  ) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    do {
      let endpoint = try buildEndpoint(
        path: "/search/media/\(keyword)/stream",
        params: [
          "mtype": type,
          "area": area,
          "title": title,
          "year": year,
          "season": season.map(String.init),
          "sites": sites,
        ])
      return streamSSE(endpoint: endpoint)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  }

  /// 进度监听 (SSE)
  func progressStream(progressKey: String) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    return streamSSE(endpoint: "/system/progress/\(progressKey)")
  }

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
    return try await decodeOrUnwrap([Context].self, from: data)
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
    return try await decodeOrUnwrap(RecognizeResponse.self, from: data)
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
    return try await decodeOrUnwrap(MediaInfo.self, from: data)
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
    return try await decodeOrUnwrap(Person.self, from: data)
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
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
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
    return try await decodeOrUnwrap([Person].self, from: data)
  }

  /// 获取 RSS 站点列表
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 在 **订阅编辑对话框** 中，作为“订阅站点”下拉菜单的数据源。
  func fetchSites() async throws -> [Site] {
    let data = try await makeRequest(endpoint: "/site/rss")
    return try await decodeOrUnwrap([Site].self, from: data)
  }

  /// 获取目录配置
  /// - 对应前端: MoviePilot-Frontend/src/views/setting/AccountSettingDirectory.vue
  /// - 应用场景: 添加下载时选择目标存储目录
  func fetchDirectories() async throws -> [TransferDirectoryConf] {
    struct ConfigValue: Decodable {
      let value: [TransferDirectoryConf]
    }
    let data = try await makeRequest(endpoint: "/system/setting/Directories")
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
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
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取自定义过滤规则列表
  /// - 对应后端: CustomFilterRules 配置项
  /// - 应用场景: 在设置页面加载可用的自定义规则列表，供用户选择后用于前端资源搜索结果的过滤。
  func fetchCustomFilterRules() async throws -> [CustomRule] {
    let data = try await makeRequest(endpoint: "/system/setting/CustomFilterRules")
    let config = try await decodeOrUnwrap(CustomFilterRulesResponse.self, from: data)
    return config.value
  }

  /// 获取剧集分组信息（针对部分长篇动漫）
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue, MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 在前端，有两个地方会用到：1. **季订阅弹窗**中，用于展示所有可供选择的剧集组（如“司法岛篇”）。 2. **订阅配置编辑弹窗**中，当编辑一个电视剧订阅时，作为“剧集组”下拉框的数据源，允许用户修改该订阅所属的剧集组。
  func fetchEpisodeGroups(tmdbId: Int) async throws -> [EpisodeGroup] {
    let endpoint = "/media/groups/\(tmdbId)"
    if let cached = await episodeGroupsCache.get(endpoint) { return cached }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try await decodeOrUnwrap([EpisodeGroup].self, from: data)
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
    let result = try await decodeOrUnwrap([TmdbSeason].self, from: data)
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
    let result = try await decodeOrUnwrap([TmdbSeason].self, from: data)
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
    let result = try await decodeOrUnwrap([NotExistMediaInfo].self, from: data)
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

  /// 复用（Fork）一个订阅分享
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/ForkSubscribeDialog.vue (doFork)
  /// - 应用场景: 在"订阅分享"中，点击"复用"按钮，基于分享的配置创建一个新的个人订阅。
  func forkSubscription(share: SubscribeShare) async throws -> Int? {
    let body = try JSONEncoder().encode(share)
    let data = try await makeRequest(endpoint: "/subscribe/fork", method: "POST", body: body)
    struct ForkResponse: Decodable {
      let id: Int?
    }
    if let response = try? JSONDecoder().decode(ApiResponse<ForkResponse>.self, from: data) {
      return response.data?.id
    }
    return nil
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
    return try await decodeOrUnwrap(Subscribe.self, from: data)
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
      let resp = try await decodeOrUnwrap(SubscribeResp.self, from: data)
      let isSubscribed = resp.id != nil
      await subscriptionStatusCache.set(cacheKey, value: isSubscribed)
      return isSubscribed
    } catch {
      return false
    }
  }

  /// 拉取当前用户的所有订阅列表
  /// - 对应前端: `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`, `MoviePilot-Frontend/src/views/subscribe/FullCalendarView.swift`
  /// - 应用场景: 1. **订阅列表页面** (`SubscribeListView`) 的核心数据源。 2. **日历视图** (`FullCalendarView`) 的数据源。 (注: 全局搜索栏不直接调用此API)
  func fetchSubscriptions() async throws -> [Subscribe] {
    let data = try await makeRequest(endpoint: "/subscribe/")
    return try await decodeOrUnwrap([Subscribe].self, from: data)
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
  func getSubscribePosterImageUrl(_ subscribe: Subscribe) -> URL? {
    return getSubscribePosterImageUrl(poster: subscribe.poster)
  }

  func getSubscribePosterImageUrl(poster: String?) -> URL? {
    guard let url = poster, !url.isEmpty else { return nil }

    if useImageCache {
      guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else {
        return nil
      }
      return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
    }

    return URL(string: url)
  }

  /// 获取订阅分享的海报图片 URL
  func getSubscribeSharePosterImageUrl(_ share: SubscribeShare) -> URL? {
    return getSubscribePosterImageUrl(poster: share.poster)
  }

  /// 获取媒体海报图片 URL
  func getPosterImageUrl(_ media: MediaInfo) -> URL? {
    return getPosterImageUrl(posterPath: media.poster_path)
  }

  func getPosterImageUrl(posterPath: String?) -> URL? {
    let url = posterPath?.replacingOccurrences(of: "original", with: "w500")

    // 1. 匹配豆瓣默认海报并拦截
    if let currentUrl = url, currentUrl.contains("doubanio.com") {
      if currentUrl.contains("movie_default") || currentUrl.contains("tv_default") {
        return nil
      }
    }

    // 2. 如果地址中包含 douban 则使用中转代理 (豆瓣必须中转)
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
  func getBackdropImageUrl(_ media: MediaInfo) -> URL? {
    return getBackdropImageUrl(backdropPath: media.backdrop_path)
  }

  func getBackdropImageUrl(backdropPath: String?) -> URL? {
    guard let url = backdropPath, !url.isEmpty else { return nil }

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
  func getDownloadItemBackdropImageUrl(_ media: DownloadingMediaInfo) -> URL? {
    return getBackdropImageUrl(backdropPath: media.image)
  }

  /// 获取媒体服务器播放项的海报
  func getMediaServerPosterImageURL(_ item: MediaServerPlayItem) -> URL? {
    return getMediaServerPosterImageURL(image: item.image, useCookies: item.use_cookies?.value)
  }

  func getMediaServerPosterImageURL(image: String?, useCookies: Bool?) -> URL? {
    guard let path = image, !path.isEmpty else { return nil }
    guard let encodedUrl = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return nil
    }

    var urlString = "\(baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)"

    if useCookies == true {
      urlString += "&use_cookies=true"
    }

    return URL(string: urlString)
  }

  /// 获取季海报 URL，严格参照 Vue 逻辑
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
  func getPersonImage(_ person: Person) -> URL? {
    return getPersonImageURL(
      source: person.source,
      profilePath: person.profile_path,
      avatar: person.avatar,
      images: person.images
    )
  }

  /// 获取 Staff 人员图片 URL
  func getStaffImageURL(_ person: Person) -> URL? {
    return getPersonImage(person)
  }

  func getPersonImageURL(
    source: String?, profilePath: String?, avatar: PersonAvatar?, images: BangumiImages?
  ) -> URL? {
    var url = ""
    var effectiveSource = source

    // 自动推断来源
    if effectiveSource == nil || (effectiveSource?.isEmpty ?? true) {
      if let path = profilePath, path.hasPrefix("/") {
        effectiveSource = "themoviedb"
      } else if avatar != nil {
        effectiveSource = "douban"
      } else if images != nil {
        effectiveSource = "bangumi"
      } else if let path = profilePath, path.hasPrefix("http") {
        url = path
      }
    }

    if effectiveSource == "themoviedb" {
      if profilePath == nil && url.isEmpty {
        return nil
      }
      let domain = settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
      let path = profilePath ?? ""
      if url.isEmpty {
        url = "https://\(domain)/t/p/w600_and_h900_bestv2\(path)"
      }
    } else if effectiveSource == "douban" {
      guard let avatar = avatar else {
        return nil
      }
      switch avatar {
      case .object(let normal):
        url = normal
      case .url(let link):
        url = link
      }
    } else if effectiveSource == "bangumi" {
      guard let medium = images?.medium else {
        return nil
      }
      url = medium
    }

    if url.isEmpty {
      return nil
    }

    // 匹配豆瓣默认人员图标并拦截 (针对 Apple TV 的特殊优化)
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
