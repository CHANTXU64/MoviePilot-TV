import Combine
import Foundation
import Kingfisher

enum APIError: Error {
  case invalidURL
  case networkError(Error)
  case decodingError(Error)
  case serverMessage(String)
  case unauthorized
  case unknown
}

extension APIError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "无效的请求地址"
    case .networkError(let error):
      return error.localizedDescription
    case .decodingError:
      return "响应解析失败"
    case .serverMessage(let message):
      return message
    case .unauthorized:
      return "登录已失效"
    case .unknown:
      return "未知错误"
    }
  }
}

enum SessionRefreshResult: Equatable {
  case alreadyRefreshed
  case noStoredSession
  case skippedWithoutCredentials
  case refreshed
  case refreshFailed
}

/// 统一错误文本选择器：逐项 trim 后按顺序取首个非空文本；全部无效返回 nil。
nonisolated func trimmedNonEmpty(_ candidates: [String?]) -> String? {
  for candidate in candidates {
    if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    {
      return trimmed
    }
  }
  return nil
}

nonisolated struct ApiResponse<T: Decodable>: Decodable {
  let success: Bool?
  let data: T?
  let message: String?
  let message_i18n: String?

  var localizedMessage: String? {
    trimmedNonEmpty([message_i18n, message])
  }
}

nonisolated struct SubscriptionLookupResult: Equatable, Sendable {
  let id: Int
  let mediaId: String
  let isResolvedMediaId: Bool
}

struct APIServiceSessionSnapshot: Equatable {
  let epoch: UInt64
}

struct APIServiceSessionState: Equatable {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let epoch: UInt64
  let imageNamespace: String

  var profileKey: String? {
    guard let userId = currentUser?.user_id else { return nil }
    return "\(baseURL)|user:\(userId)"
  }

  var uiIdentity: String {
    guard token != nil else { return "logged-out" }
    guard let profileKey else { return "pending:\(baseURL)" }
    return "\(profileKey)|\(permissionFingerprint)"
  }

  private var permissionFingerprint: String {
    if currentUser?.super_user?.value == true { return "superuser" }
    return (currentUser?.permissions ?? [:])
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value ? 1 : 0)" }
      .joined(separator: ",")
  }
}

private struct APIServiceSessionLease {
  let epoch: UInt64
  let baseURL: String
  let token: String?
  let runtime: APIServiceSessionRuntime
}

nonisolated private final class ResourceCookieVault: @unchecked Sendable {
  private let lock = NSLock()
  private var cookies: [HTTPCookie] = []

  func update(from response: HTTPURLResponse, for url: URL) {
    let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
      guard let key = entry.key as? String else { return }
      result[key] = String(describing: entry.value)
    }
    let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    guard !received.isEmpty else { return }

    lock.lock()
    defer { lock.unlock() }
    for cookie in received {
      cookies.removeAll {
        $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
      }
      if cookie.expiresDate.map({ $0 > Date() }) ?? true {
        cookies.append(cookie)
      }
    }
  }

  func cookieHeader(for url: URL) -> String? {
    lock.lock()
    cookies.removeAll { !($0.expiresDate.map { $0 > Date() } ?? true) }
    let matchingCookies = cookies.filter { cookie in
      guard let host = url.host?.lowercased() else { return false }
      let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      guard host == domain || host.hasSuffix(".\(domain)") else { return false }
      guard !cookie.isSecure || url.scheme?.lowercased() == "https" else { return false }
      let path = cookie.path.isEmpty ? "/" : cookie.path
      guard url.path.hasPrefix(path) else { return false }
      return path.hasSuffix("/") || url.path.count == path.count
        || url.path.dropFirst(path.count).first == "/"
    }
    lock.unlock()
    guard !matchingCookies.isEmpty else { return nil }
    return HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"]
  }

  func snapshot() -> [HTTPCookie] {
    lock.lock()
    defer { lock.unlock() }
    return cookies
  }

  func replace(with cookies: [HTTPCookie]) {
    lock.lock()
    self.cookies = cookies
    lock.unlock()
  }
}

private final class APIServiceSessionRuntime: @unchecked Sendable {
  let transport: URLSession
  let cookieVault = ResourceCookieVault()
  let imageDownloader: ImageDownloader

  init(
    identifier: String = UUID().uuidString,
    configuration baseConfiguration: URLSessionConfiguration
  ) {
    let configuration = baseConfiguration.copy() as! URLSessionConfiguration
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    transport = URLSession(configuration: configuration)

    imageDownloader = ImageDownloader(name: "moviepilot-session-\(identifier)")
    let imageConfiguration = baseConfiguration.copy() as! URLSessionConfiguration
    imageConfiguration.httpShouldSetCookies = false
    imageConfiguration.httpCookieStorage = nil
    imageDownloader.sessionConfiguration = imageConfiguration
  }

  func cancel() {
    transport.invalidateAndCancel()
    imageDownloader.cancelAll()
  }
}

private struct StoredSessionRecord: Codable {
  let revision: UInt64
  let baseURL: String
  let token: String
  let currentUser: Token?
  let username: String?
  let password: String?
  let imageNamespace: String
}

private struct StoredSessionMarker: Codable {
  enum Storage: String, Codable {
    case keychain
    case userDefaults
    case tombstone
  }

  let revision: UInt64
  let storage: Storage
}

private struct CurrentUserResponse: Decodable {
  let id: Int
  let name: String
  let is_superuser: FlexibleBool?
  let avatar: String?
  let permissions: [String: Bool]?

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case is_superuser
    case avatar
    case permissions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    is_superuser = try container.decodeIfPresent(FlexibleBool.self, forKey: .is_superuser)
    avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
    permissions = try decodeUserPermissions(from: container, forKey: .permissions)
  }

  func token(accessToken: String) -> Token {
    Token(
      access_token: accessToken,
      token_type: "bearer",
      super_user: is_superuser,
      permissions: permissions ?? [:],
      user_id: id,
      user_name: name,
      avatar: avatar
    )
  }
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

nonisolated func encodeURIComponent(_ value: String) -> String? {
  let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
  return value.addingPercentEncoding(withAllowedCharacters: allowed)
}

nonisolated func appendPercentEncodedQueryParams(
  to components: inout URLComponents,
  params: [String: String?]
) {
  let additions = params.compactMap { name, value -> String? in
    guard let value,
      let encodedName = encodeURIComponent(name),
      let encodedValue = encodeURIComponent(value)
    else {
      return nil
    }
    return "\(encodedName)=\(encodedValue)"
  }
  guard !additions.isEmpty else { return }
  let suffix = additions.joined(separator: "&")
  if let existing = components.percentEncodedQuery, !existing.isEmpty {
    components.percentEncodedQuery = existing + "&" + suffix
  } else {
    components.percentEncodedQuery = suffix
  }
}

nonisolated private func encodeMediaIDPathSegment(_ value: String) -> String? {
  let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:")
  return value.addingPercentEncoding(withAllowedCharacters: allowed)
}

nonisolated func redactedEndpointForLogging(_ endpoint: String) -> String {
  String(endpoint.split(separator: "?", maxSplits: 1).first ?? "")
    .split(separator: "#", maxSplits: 1)
    .first
    .map(String.init) ?? ""
}

nonisolated func relativeBackendEndpoint(
  path: String,
  params: [String: String?] = [:]
) throws -> String {
  guard var components = URLComponents(string: path),
    components.scheme == nil,
    components.host == nil,
    !path.hasPrefix("//"),
    !components.path.split(separator: "/").contains("..")
  else {
    throw APIError.invalidURL
  }
  components.path = "/" + components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  guard !components.path.isEmpty, components.path != "/" else {
    throw APIError.invalidURL
  }
  appendPercentEncodedQueryParams(to: &components, params: params)
  guard let endpoint = components.string else { throw APIError.invalidURL }
  return endpoint
}

nonisolated private func isBangumiImageURL(_ value: String) -> Bool {
  if let host = URLComponents(string: value)?.host?.lowercased() {
    return host == "lain.bgm.tv" || host.hasSuffix(".lain.bgm.tv")
  }
  return value.contains("lain.bgm.tv")
}

nonisolated private func displayImageURL(
  _ value: String?,
  baseURL: String,
  useImageCache: Bool
) -> URL? {
  guard let value, !value.isEmpty else {
    return nil
  }

  let lowercasedValue = value.lowercased()
  guard lowercasedValue.hasPrefix("http://") || lowercasedValue.hasPrefix("https://") else {
    return URL(string: value)
  }

  guard let encodedUrl = encodeURIComponent(value) else {
    return nil
  }

  if isBangumiImageURL(value) {
    var urlString = "\(baseURL)/api/v1/system/img/1?imgurl=\(encodedUrl)"
    if useImageCache {
      urlString += "&cache=true"
    }
    return URL(string: urlString)
  }

  if useImageCache {
    return URL(string: "\(baseURL)/api/v1/system/cache/image?url=\(encodedUrl)")
  }

  if value.contains("doubanio.com") {
    return URL(string: "\(baseURL)/api/v1/system/img/0?imgurl=\(encodedUrl)")
  }

  return URL(string: value)
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
      if response.success == false {
        throw APIError.serverMessage(response.localizedMessage ?? "Request failed")
      }
      if let wrappedData = response.data {
        return wrappedData
      }
      if let message = response.localizedMessage, !message.isEmpty {
        throw APIError.serverMessage(message)
      }
    } catch let error as APIError {
      throw error
    } catch let error as DecodingError {
      if let response = try? JSONDecoder().decode(ApiResponse<JSONValue>.self, from: data),
        response.success == false
      {
        throw APIError.serverMessage(response.localizedMessage ?? "Request failed")
      }
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
  // 仅零字节空 body 按旧契约兼容为成功；非空响应一律按严格 envelope 解码，畸形/错类型失败关闭。
  if data.isEmpty {
    return (true, nil)
  }
  return try decodeStrictActionResponseSync(from: data)
}

nonisolated private func decodeStrictActionResponseSync(from data: Data) throws -> (
  success: Bool, message: String?
) {
  struct ActionResponse: Decodable {
    let success: Bool?
    let message: String?
    let message_i18n: String?
  }
  let response = try JSONDecoder().decode(ActionResponse.self, from: data)
  return (
    response.success ?? false,
    trimmedNonEmpty([response.message_i18n, response.message])
  )
}

/// 泛型轻量级接口缓存，带过期及淘汰策略
actor APICache<Key: Hashable, Value> {
  struct LoadToken: Equatable, Sendable {
    fileprivate let revision: UInt64
  }

  private struct CacheEntry {
    let value: Value
    var expiresAt: Date
  }

  private var cache: [Key: CacheEntry] = [:]
  private var activeLoadRevisions: [Key: UInt64] = [:]
  private let defaultTTL: TimeInterval
  private let size: Int
  private let renewsTTLOnAccess: Bool

  init(
    defaultTTL: TimeInterval = 60,
    size: Int = 50,
    renewsTTLOnAccess: Bool = true
  ) {
    self.defaultTTL = defaultTTL
    self.size = size
    self.renewsTTLOnAccess = renewsTTLOnAccess
  }

  func get(_ key: Key) -> Value? {
    guard var entry = cache[key] else { return nil }

    let currentDate = Date()
    if currentDate > entry.expiresAt {
      cache.removeValue(forKey: key)
      return nil
    }

    if renewsTTLOnAccess {
      // 访问时“续期”，变相实现了 LRU
      entry.expiresAt = currentDate.addingTimeInterval(defaultTTL)
      cache[key] = entry
    }

    return entry.value
  }

  func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
    activeLoadRevisions.removeValue(forKey: key)
    store(key, value: value, ttl: ttl)
  }

  func beginLoad(_ key: Key, revision: UInt64) -> LoadToken {
    if revision > activeLoadRevisions[key, default: 0] {
      activeLoadRevisions[key] = revision
    }
    return LoadToken(revision: revision)
  }

  func setIfCurrent(
    _ key: Key,
    value: Value,
    token: LoadToken,
    ttl: TimeInterval? = nil
  ) -> Bool {
    guard activeLoadRevisions[key] == token.revision else { return false }
    activeLoadRevisions.removeValue(forKey: key)
    store(key, value: value, ttl: ttl)
    return true
  }

  func endLoadIfCurrent(_ key: Key, token: LoadToken) {
    guard activeLoadRevisions[key] == token.revision else { return }
    activeLoadRevisions.removeValue(forKey: key)
  }

  private func store(_ key: Key, value: Value, ttl: TimeInterval?) {
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
    activeLoadRevisions.removeValue(forKey: key)
    cache.removeValue(forKey: key)
  }

  func clear() {
    activeLoadRevisions.removeAll()
    cache.removeAll()
  }
}

@MainActor
class APIService: ObservableObject {
  static let shared = APIService()
  static let sessionRefreshAppVersionKey = "lastSessionRefreshAppVersion"
  private static let noAccessibleFeatureMessage = "当前用户没有可访问的功能权限"
  private static let keychainService = "MoviePilot-TV"
  private static let accessTokenAccount = "accessToken"
  private static let currentUserAccount = "currentUser"
  private static let sessionRecordAccount = "sessionRecord.v2"
  private static let sessionMarkerKey = "sessionMarker.v2"
  private static let defaultBaseURL = "http://192.168.1.1:3000"

  @Published private(set) var session: APIServiceSessionState
  private let sessionConfiguration: URLSessionConfiguration
  private var runtime: APIServiceSessionRuntime
  private var storedUsername: String?
  private var storedPassword: String?
  private var storageLocation: StoredSessionMarker.Storage = .tombstone
  private var activeCandidateLoginCounts: [UInt64: Int] = [:]

  var baseURL: String { session.baseURL }
  var token: String? { session.token }
  var currentUser: Token? { session.currentUser }

  var profileKey: String? {
    if let key = session.profileKey {
      return key
    }
    return Self.persistedProfileKey(baseURL: session.baseURL, token: session.token)
  }
  var uiIdentity: String { session.uiIdentity }

  /// 会话身份尚未恢复（token-only 会话在 /user/current 恢复完成前或恢复失败）时，
  /// 回退到持久化且与当前 token 匹配的已验证快照，避免四类 profile 偏好读写静默失效。
  private static func persistedProfileKey(baseURL: String, token: String?) -> String? {
    guard let token, !token.isEmpty,
      let storedUser = loadStoredCurrentUser(),
      let restoredUser = storedUser.withRestoredAccessToken(token),
      let userId = restoredUser.user_id
    else {
      return nil
    }
    return "\(baseURL)|user:\(userId)"
  }

  var isSessionStoredInKeychain: Bool? {
    guard session.token != nil else { return nil }
    return storageLocation == .keychain
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
  private let subscriptionStatusCache = APICache<String, Bool>(defaultTTL: 120, size: 100)
  private let subscriptionSnapshotCache = APICache<String, [Subscribe]>(
    defaultTTL: 30,
    size: 1,
    renewsTTLOnAccess: false
  )
  private var subscriptionCacheGeneration = 0
  private var subscriptionStatusLoadRevision: UInt64 = 0
  private var subscriptionStatusLoadOwners: [String: UInt64] = [:]
  private var subscriptionSnapshotFetchGeneration: Int?
  private var subscriptionSnapshotFetchRevision = 0
  private var subscriptionSnapshotFetchTaskRevision: Int?
  private var subscriptionSnapshotFetchTask: Task<[Subscribe], Error>?

  private func invalidateSubscriptionCaches() {
    subscriptionCacheGeneration &+= 1
    subscriptionSnapshotFetchTask?.cancel()
    subscriptionSnapshotFetchGeneration = nil
    subscriptionSnapshotFetchTaskRevision = nil
    subscriptionSnapshotFetchTask = nil
    let snapshotCache = subscriptionSnapshotCache
    Task {
      await snapshotCache.clear()
    }
  }

  private func invalidateSubscriptionCachesAfterSessionChange() {
    invalidateSubscriptionCaches()
  }

  private enum StoredCurrentUserState {
    case missing
    case noAccessibleFeature
    case invalidToken
    case restored(Token)
  }

  private static var storedAccessToken: String? {
    KeychainHelper.shared.read(service: keychainService, account: accessTokenAccount)
      ?? UserDefaults.standard.string(forKey: accessTokenAccount)
  }

  private static func loadStoredCurrentUser() -> Token? {
    guard
      let json = KeychainHelper.shared.read(service: keychainService, account: currentUserAccount)
        ?? UserDefaults.standard.string(forKey: currentUserAccount),
      let data = json.data(using: .utf8)
    else {
      return nil
    }
    return try? JSONDecoder().decode(Token.self, from: data)
  }

  private static func clearStoredSessionCredentials() {
    [
      accessTokenAccount,
      currentUserAccount,
      "username",
      "password",
    ].forEach { account in
      if !KeychainHelper.shared.delete(service: keychainService, account: account) {
        print("Failed to delete keychain item for account: \(account)")
      }
      UserDefaults.standard.removeObject(forKey: account)
    }
  }

  private static func storedCurrentUserState(storedToken: String) -> StoredCurrentUserState {
    guard let storedUser = loadStoredCurrentUser() else { return .missing }
    guard storedUser.hasKnownFeaturePermissions else { return .missing }
    guard storedUser.hasLoginAccessibleFeature else { return .noAccessibleFeature }
    guard let restoredUser = storedUser.withRestoredAccessToken(storedToken) else {
      return .invalidToken
    }
    return .restored(restoredUser)
  }

  private func restoreCurrentUserFromStorage() -> Bool {
    guard let storedToken = token else { return false }
    switch Self.persistedCurrentUserState(storedToken: storedToken) {
    case .restored(let restoredUser):
      let cookies = runtime.cookieVault.snapshot()
      replaceSession(
        baseURL: baseURL,
        token: storedToken,
        currentUser: restoredUser,
        username: storedUsername,
        password: storedPassword,
        persist: true,
        cookies: cookies
      )
      return true
    case .noAccessibleFeature:
      logout()
      return false
    case .missing, .invalidToken:
      return false
    }
  }

  init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
    let initial = Self.loadInitialSession()
    self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
    session = initial.state
    runtime = APIServiceSessionRuntime(
      identifier: initial.state.imageNamespace,
      configuration: self.sessionConfiguration
    )
    storedUsername = initial.username
    storedPassword = initial.password
    storageLocation = initial.storage
    if UserDefaults.standard.object(forKey: Self.sessionMarkerKey) == nil {
      if let token = initial.state.token, !token.isEmpty {
        storageLocation = persistRecord(
          StoredSessionRecord(
            revision: 1,
            baseURL: initial.state.baseURL,
            token: token,
            currentUser: initial.state.currentUser?.withoutPersistedAccessToken(),
            username: initial.username,
            password: initial.password,
            imageNamespace: initial.state.imageNamespace
          )
        )
      } else {
        persistMarker(StoredSessionMarker(revision: 1, storage: .tombstone))
        storageLocation = .tombstone
      }
    }
  }

  var isLoggedIn: Bool {
    return token != nil
  }

  func logout() {
    let revision = nextStoredRevision()
    persistMarker(StoredSessionMarker(revision: revision, storage: .tombstone))
    storageLocation = .tombstone
    clearStoredRecordAndLegacyCredentials()
    replaceSession(
      baseURL: baseURL,
      token: nil,
      currentUser: nil,
      username: nil,
      password: nil,
      persist: false
    )
    NotificationCenter.default.post(name: .sessionDidLogout, object: nil)
  }

  private var currentOrStoredUser: Token? {
    if let currentUser {
      return currentUser
    }
    guard let token, !token.isEmpty else { return nil }
    switch Self.persistedCurrentUserState(storedToken: token) {
    case .restored(let storedUser):
      return storedUser
    case .noAccessibleFeature, .invalidToken, .missing:
      return nil
    }
  }

  var canRequestSuperUserEndpoints: Bool {
    currentOrStoredUser?.canRequestSuperUserEndpoints == true
  }

  func canAccess(_ permission: UserPermissionKey) -> Bool {
    currentOrStoredUser?.canAccess(permission) == true
  }

  func sessionSnapshot() -> APIServiceSessionSnapshot {
    APIServiceSessionSnapshot(epoch: session.epoch)
  }

  func isSessionUnchanged(from snapshot: APIServiceSessionSnapshot) -> Bool {
    session.epoch == snapshot.epoch
  }

  private struct InitialSession {
    let state: APIServiceSessionState
    let username: String?
    let password: String?
    let storage: StoredSessionMarker.Storage
  }

  private static func loadInitialSession() -> InitialSession {
    let defaults = UserDefaults.standard
    let fallbackBaseURL = normalizedBaseURL(defaults.string(forKey: "serverURL")) ?? defaultBaseURL
    if let marker = loadMarker() {
      return restoreInitialSession(from: marker, fallbackBaseURL: fallbackBaseURL)
    }

    // 新格式标记存在但无法解码时必须失败关闭，不能退回旧字段复活已退出的账号。
    if defaults.object(forKey: sessionMarkerKey) != nil {
      return loggedOutInitialSession(baseURL: fallbackBaseURL)
    }

    return migrateLegacyInitialSession(baseURL: fallbackBaseURL, defaults: defaults)
  }

  private static func restoreInitialSession(
    from marker: StoredSessionMarker,
    fallbackBaseURL: String
  ) -> InitialSession {
    guard marker.storage != .tombstone,
      let record = loadRecord(from: marker.storage),
      record.revision == marker.revision,
      let normalizedURL = normalizedBaseURL(record.baseURL),
      !record.token.isEmpty
    else {
      return loggedOutInitialSession(baseURL: fallbackBaseURL, epoch: marker.revision)
    }

    let restoredUser = record.currentUser?.withRestoredAccessToken(record.token)
    guard record.currentUser == nil || restoredUser != nil else {
      return loggedOutInitialSession(baseURL: fallbackBaseURL, epoch: marker.revision)
    }
    return InitialSession(
      state: APIServiceSessionState(
        baseURL: normalizedURL,
        token: record.token,
        currentUser: restoredUser,
        epoch: marker.revision,
        imageNamespace: record.imageNamespace
      ),
      username: record.username,
      password: record.password,
      storage: marker.storage
    )
  }

  private static func migrateLegacyInitialSession(
    baseURL: String,
    defaults: UserDefaults
  ) -> InitialSession {
    guard let legacyToken = storedAccessToken, !legacyToken.isEmpty else {
      clearStoredSessionCredentials()
      return loggedOutInitialSession(baseURL: baseURL)
    }
    let legacyUserState = storedCurrentUserState(storedToken: legacyToken)
    if case .noAccessibleFeature = legacyUserState {
      clearStoredSessionCredentials()
      return loggedOutInitialSession(baseURL: baseURL)
    }
    let legacyUser: Token?
    if case .restored(let user) = legacyUserState {
      legacyUser = user
    } else {
      legacyUser = nil
    }
    return InitialSession(
      state: APIServiceSessionState(
        baseURL: baseURL,
        token: legacyToken,
        currentUser: legacyUser,
        epoch: 0,
        imageNamespace: UUID().uuidString
      ),
      username: KeychainHelper.shared.read(service: keychainService, account: "username")
        ?? defaults.string(forKey: "username"),
      password: KeychainHelper.shared.read(service: keychainService, account: "password")
        ?? defaults.string(forKey: "password"),
      storage: .userDefaults
    )
  }

  private static func loggedOutInitialSession(
    baseURL: String,
    epoch: UInt64 = 0
  ) -> InitialSession {
    InitialSession(
      state: loggedOutState(baseURL: baseURL, epoch: epoch),
      username: nil,
      password: nil,
      storage: .tombstone
    )
  }

  private static func loggedOutState(baseURL: String, epoch: UInt64) -> APIServiceSessionState {
    APIServiceSessionState(
      baseURL: baseURL,
      token: nil,
      currentUser: nil,
      epoch: epoch,
      imageNamespace: UUID().uuidString
    )
  }

  private static func normalizedBaseURL(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let components = URLComponents(string: trimmed),
      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
      components.host != nil
    else {
      return nil
    }
    return trimmed
  }

  private static func loadMarker() -> StoredSessionMarker? {
    guard let data = UserDefaults.standard.data(forKey: sessionMarkerKey) else { return nil }
    return try? JSONDecoder().decode(StoredSessionMarker.self, from: data)
  }

  private static func loadRecord(from storage: StoredSessionMarker.Storage) -> StoredSessionRecord? {
    let json: String?
    switch storage {
    case .keychain:
      json = KeychainHelper.shared.read(service: keychainService, account: sessionRecordAccount)
    case .userDefaults:
      json = UserDefaults.standard.string(forKey: sessionRecordAccount)
    case .tombstone:
      json = nil
    }
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(StoredSessionRecord.self, from: data)
  }

  private static func persistedCurrentUserState(storedToken: String) -> StoredCurrentUserState {
    if let marker = loadMarker(), marker.storage != .tombstone,
      let record = loadRecord(from: marker.storage),
      record.revision == marker.revision,
      record.token == storedToken,
      let storedUser = record.currentUser
    {
      guard storedUser.hasKnownFeaturePermissions else { return .missing }
      guard storedUser.hasLoginAccessibleFeature else { return .noAccessibleFeature }
      guard let restoredUser = storedUser.withRestoredAccessToken(storedToken) else {
        return .invalidToken
      }
      return .restored(restoredUser)
    }
    return .missing
  }

  private func nextStoredRevision() -> UInt64 {
    max(Self.loadMarker()?.revision ?? 0, session.epoch) &+ 1
  }

  private func persistMarker(_ marker: StoredSessionMarker) {
    guard let data = try? JSONEncoder().encode(marker) else { return }
    UserDefaults.standard.set(data, forKey: Self.sessionMarkerKey)
  }

  @discardableResult
  private func persistRecord(_ record: StoredSessionRecord) -> StoredSessionMarker.Storage {
    guard let data = try? JSONEncoder().encode(record),
      let json = String(data: data, encoding: .utf8)
    else {
      return .tombstone
    }

    let storage: StoredSessionMarker.Storage
    if KeychainHelper.shared.save(
      json,
      service: Self.keychainService,
      account: Self.sessionRecordAccount
    ) {
      storage = .keychain
      UserDefaults.standard.removeObject(forKey: Self.sessionRecordAccount)
    } else {
      storage = .userDefaults
      UserDefaults.standard.set(json, forKey: Self.sessionRecordAccount)
    }
    persistMarker(StoredSessionMarker(revision: record.revision, storage: storage))
    Self.clearStoredSessionCredentials()
    return storage
  }

  private func clearStoredRecordAndLegacyCredentials() {
    if !KeychainHelper.shared.delete(
      service: Self.keychainService,
      account: Self.sessionRecordAccount
    ) {
      print("Failed to delete keychain item for account: \(Self.sessionRecordAccount)")
    }
    UserDefaults.standard.removeObject(forKey: Self.sessionRecordAccount)
    Self.clearStoredSessionCredentials()
  }

  func replaceSession(
    baseURL rawBaseURL: String,
    token: String?,
    currentUser: Token?,
    username: String?,
    password: String?,
    persist: Bool,
    cookies: [HTTPCookie] = []
  ) {
    let normalizedURL = Self.normalizedBaseURL(rawBaseURL) ?? session.baseURL
    let nextEpoch = session.epoch &+ 1
    let provisional = APIServiceSessionState(
      baseURL: normalizedURL,
      token: token,
      currentUser: currentUser,
      epoch: nextEpoch,
      imageNamespace: session.imageNamespace
    )
    let preserveImageNamespace = provisional.profileKey != nil
      && provisional.uiIdentity == session.uiIdentity
    let nextState = APIServiceSessionState(
      baseURL: normalizedURL,
      token: token,
      currentUser: currentUser,
      epoch: nextEpoch,
      imageNamespace: preserveImageNamespace ? session.imageNamespace : UUID().uuidString
    )

    if persist, let token, !token.isEmpty {
      let revision = nextStoredRevision()
      // 先让旧记录失效；若随后写入或进程中断，重启时宁可退出，也不能复活旧账号。
      persistMarker(StoredSessionMarker(revision: revision, storage: .tombstone))
      storageLocation = .tombstone
      let record = StoredSessionRecord(
        revision: revision,
        baseURL: normalizedURL,
        token: token,
        currentUser: currentUser?.withoutPersistedAccessToken(),
        username: username,
        password: password,
        imageNamespace: nextState.imageNamespace
      )
      storageLocation = persistRecord(record)
    }

    let oldUIIdentity = session.uiIdentity
    let oldRuntime = runtime
    let newRuntime = APIServiceSessionRuntime(
      identifier: nextState.imageNamespace,
      configuration: sessionConfiguration
    )
    newRuntime.cookieVault.replace(with: cookies)
    runtime = newRuntime
    session = nextState
    storedUsername = username
    storedPassword = password
    UserDefaults.standard.set(normalizedURL, forKey: "serverURL")
    oldRuntime.cancel()
    invalidateAllSessionCaches()
    if oldUIIdentity != nextState.uiIdentity {
      settings = nil
    }
  }

  private func invalidateAllSessionCaches() {
    invalidateSubscriptionCachesAfterSessionChange()
    let episodeGroupsCache = episodeGroupsCache
    let mediaSeasonsCache = mediaSeasonsCache
    let groupSeasonsCache = groupSeasonsCache
    Task {
      await episodeGroupsCache.clear()
      await mediaSeasonsCache.clear()
      await groupSeasonsCache.clear()
    }
  }

  private func currentLease() -> APIServiceSessionLease {
    APIServiceSessionLease(
      epoch: session.epoch,
      baseURL: session.baseURL,
      token: session.token,
      runtime: runtime
    )
  }

  private func validate(_ lease: APIServiceSessionLease) throws {
    guard session.epoch == lease.epoch else { throw CancellationError() }
  }

  func refreshStoredSessionAfterAppUpdateIfNeeded(
    appVersion: String = AppVersionInfo.currentAppVersion()
  ) async -> SessionRefreshResult {
    let normalizedAppVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAppVersion.isEmpty, normalizedAppVersion != "未知" else {
      return .noStoredSession
    }

    let defaults = UserDefaults.standard
    if let currentUser, currentUser.hasKnownFeaturePermissions,
      !currentUser.hasLoginAccessibleFeature
    {
      logout()
      defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
      return .noStoredSession
    }

    if defaults.string(forKey: Self.sessionRefreshAppVersionKey) == normalizedAppVersion {
      if token != nil, currentUser == nil {
        _ = restoreCurrentUserFromStorage()
        if token == nil {
          defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
          return .noStoredSession
        }
        if currentUser == nil {
          _ = await recoverCurrentUserFromCurrentUserEndpoint()
          if token == nil {
            defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
            return .noStoredSession
          }
        }
      }
      return .alreadyRefreshed
    }

    guard token != nil else {
      defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
      return .noStoredSession
    }

    if currentUser == nil {
      _ = restoreCurrentUserFromStorage()
      if token == nil {
        defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
        return .noStoredSession
      }
    }

    let username = storedUsername
    let password = storedPassword

    guard let username, let password, !username.isEmpty, !password.isEmpty else {
      if currentUser == nil {
        if await recoverCurrentUserFromCurrentUserEndpoint() {
          defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
          return .refreshed
        }
        if token == nil {
          defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
          return .noStoredSession
        }
      }
      defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
      return .skippedWithoutCredentials
    }

    let startEpoch = session.epoch
    do {
      _ = try await login(
        username: username,
        password: password
      )
      defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
      return .refreshed
    } catch {
      if Self.isNoAccessibleFeatureError(error), session.epoch == startEpoch {
        logout()
        defaults.set(normalizedAppVersion, forKey: Self.sessionRefreshAppVersionKey)
        return .noStoredSession
      }
      return .refreshFailed
    }
  }

  func refreshCurrentUserForStartup() async {
    _ = await recoverCurrentUserFromCurrentUserEndpoint()
  }

  private func recoverCurrentUserFromCurrentUserEndpoint() async -> Bool {
    guard token?.isEmpty == false else { return false }
    do {
      let data = try await makeRequest(endpoint: "/user/current")
      let user = try JSONDecoder().decode(CurrentUserResponse.self, from: data)
      guard let accessToken = token, !accessToken.isEmpty else { return false }
      let recoveredUser = user.token(accessToken: accessToken)
      guard recoveredUser.hasLoginAccessibleFeature else {
        logout()
        return false
      }
      let cookies = runtime.cookieVault.snapshot()
      replaceSession(
        baseURL: baseURL,
        token: accessToken,
        currentUser: recoveredUser,
        username: storedUsername,
        password: storedPassword,
        persist: true,
        cookies: cookies
      )
      return true
    } catch {
      return false
    }
  }

  private func makeRequest(
    endpoint: String, method: String = "GET", body: Data? = nil, isForm: Bool = false
  ) async throws -> Data {
    let lease = currentLease()
    do {
      return try await performRequest(
        endpoint: endpoint,
        method: method,
        body: body,
        isForm: isForm,
        lease: lease,
        requireCurrentLease: true
      )
    } catch APIError.unauthorized {
      try await recoverSessionAfterUnauthorized(lease)
      throw CancellationError()
    }
  }

  private func recoverSessionAfterUnauthorized(_ lease: APIServiceSessionLease) async throws {
    try validate(lease)
    guard let username = storedUsername, let password = storedPassword,
      !username.isEmpty, !password.isEmpty
    else {
      logout()
      throw APIError.unauthorized
    }

    do {
      _ = try await login(username: username, password: password, serverURL: lease.baseURL)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if session.epoch == lease.epoch {
        logout()
      }
      throw APIError.unauthorized
    }
  }

  private func performRequest(
    endpoint: String,
    method: String,
    body: Data?,
    isForm: Bool,
    lease: APIServiceSessionLease,
    requireCurrentLease: Bool
  ) async throws -> Data {
    if requireCurrentLease { try validate(lease) }
    let request = try buildRequest(
      endpoint: endpoint,
      method: method,
      body: body,
      isForm: isForm,
      lease: lease
    )
    let (data, response) = try await send(
      request,
      lease: lease,
      requireCurrentLease: requireCurrentLease
    )
    if requireCurrentLease { try validate(lease) }
    if let httpResponse = response as? HTTPURLResponse {
      try handleHTTPResponse(
        httpResponse,
        data: data,
        endpoint: endpoint,
        lease: lease,
        requireCurrentLease: requireCurrentLease
      )
    }
    if requireCurrentLease { try validate(lease) }
    return data
  }

  private func buildRequest(
    endpoint: String,
    method: String,
    body: Data?,
    isForm: Bool,
    lease: APIServiceSessionLease
  ) throws -> URLRequest {
    guard let url = URL(string: "\(lease.baseURL)/api/v1\(endpoint)") else {
      throw APIError.invalidURL
    }
    return Self.configuredRequest(
      url: url,
      method: method,
      body: body,
      isForm: isForm,
      token: lease.token,
      cookieHeader: lease.runtime.cookieVault.cookieHeader(for: url)
    )
  }

  static func configuredRequest(
    url: URL,
    method: String,
    body: Data?,
    isForm: Bool,
    token: String?,
    cookieHeader: String?
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let cookieHeader {
      request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
    }
    request.setValue("zh-CN", forHTTPHeaderField: "X-MoviePilot-Locale")
    request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
    if isForm {
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    } else {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    request.httpBody = body
    return request
  }

  private func send(
    _ request: URLRequest,
    lease: APIServiceSessionLease,
    requireCurrentLease: Bool
  ) async throws -> (Data, URLResponse) {
    do {
      return try await lease.runtime.transport.data(for: request)
    } catch {
      if requireCurrentLease, session.epoch != lease.epoch {
        throw CancellationError()
      }
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        throw CancellationError()
      }
      throw APIError.networkError(error)
    }
  }

  private func handleHTTPResponse(
    _ response: HTTPURLResponse,
    data: Data,
    endpoint: String,
    lease: APIServiceSessionLease,
    requireCurrentLease: Bool
  ) throws {
    if let responseURL = response.url {
      lease.runtime.cookieVault.update(from: response, for: responseURL)
    }
    if response.statusCode == 401 || response.statusCode == 403 {
      if requireCurrentLease, session.epoch == lease.epoch {
        if isCandidateLoginActive(for: lease.epoch) {
          throw CancellationError()
        }
        throw APIError.unauthorized
      }
      throw Self.serverMessageError(statusCode: response.statusCode, data: data)
    }
    guard (200...299).contains(response.statusCode) else {
      Logger.error("HTTP \(response.statusCode): \(redactedEndpointForLogging(endpoint))")
      throw Self.serverMessageError(statusCode: response.statusCode, data: data)
    }
  }

  static func serverMessageError(statusCode: Int, data: Data) -> APIError {
    struct ErrorPayload: Decodable {
      let message: String?
      let message_i18n: String?
      let detail: String?
      let detail_i18n: String?
    }
    let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
    let message = trimmedNonEmpty([
      payload?.message_i18n,
      payload?.detail_i18n,
      payload?.message,
      payload?.detail,
    ])
    let description = [String(statusCode), message]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ": ")
    return APIError.serverMessage(description)
  }

  private func buildEndpoint(path: String, params: [String: String?] = [:]) throws -> String {
    guard var components = URLComponents(string: path) else {
      throw APIError.invalidURL
    }
    // 保留 path 中可能已存在的查询参数
    appendPercentEncodedQueryParams(to: &components, params: params)
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
    let decodeEpoch = session.epoch
    let decoded: T
    if type == MediaInfo.self {
      let mappedMedia = try await decodeMediaInfoInBackground(from: data)
      guard let mapped = mappedMedia as? T else {
        throw APIError.decodingError(
          DecodingError.typeMismatch(
            T.self,
            DecodingError.Context(
              codingPath: [], debugDescription: "Failed to map MediaInfoJSON to \(T.self)")
          ))
      }
      decoded = mapped
    } else if type == [MediaInfo].self {
      let mappedMedia = try await decodeMediaInfoArrayInBackground(from: data)
      guard let mapped = mappedMedia as? T else {
        throw APIError.decodingError(
          DecodingError.typeMismatch(
            T.self,
            DecodingError.Context(
              codingPath: [], debugDescription: "Failed to map [MediaInfoJSON] to \(T.self)")
          ))
      }
      decoded = mapped
    } else {
      decoded = try decodeOrUnwrapSync(from: data)
    }
    guard session.epoch == decodeEpoch else { throw CancellationError() }
    return decoded
  }

  /// 仅对 MediaInfo 热路径做后台解码，避免主线程解析大 JSON。
  private func decodeMediaInfoInBackground(from data: Data) async throws -> MediaInfo
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<MediaInfo, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let raw: MediaInfoJSON = try decodeOrUnwrapSync(from: data)
          continuation.resume(returning: MediaInfo(json: raw))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// 仅对 MediaInfo 列表热路径做后台解码，缓解分页加载时的主线程压力。
  private func decodeMediaInfoArrayInBackground(from data: Data)
    async throws -> [MediaInfo]
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[MediaInfo], Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let raw: [MediaInfoJSON] = try decodeOrUnwrapSync(from: data)
          let mapped = raw.map { MediaInfo(json: $0) }
          continuation.resume(returning: mapped)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// 静默验证 Token 有效性。
  /// 仅在 App 启动、切回前台或 Tab 切换时调用，频率极低且不阻塞 UI。
  /// Token 失效时优先用保存的凭据自动登录，当前验证随会话切换结束。
  func validateTokenSilently() {
    guard isLoggedIn, !isCandidateLoginActive(for: session.epoch) else { return }

    Task {
      do {
        _ = try await makeRequest(endpoint: "/user/current")
        print("Token/Session validation successful.")
      } catch {
        print("Silent token validation background process handled: \(error)")
      }
    }
  }

  /// 登录获取 Token
  /// - 对应前端: MoviePilot-Frontend/src/pages/login.vue
  /// - 应用场景: 用户登录验证并获取访问令牌。
  func login(
    username: String,
    password: String,
    serverURL: String? = nil
  ) async throws -> Token {
    guard let targetBaseURL = Self.normalizedBaseURL(serverURL ?? baseURL) else {
      throw APIError.invalidURL
    }
    let startingEpoch = session.epoch
    beginCandidateLogin(for: startingEpoch)
    defer { endCandidateLogin(for: startingEpoch) }
    let candidateRuntime = APIServiceSessionRuntime(configuration: sessionConfiguration)
    defer { candidateRuntime.cancel() }
    guard let encodedUsername = encodeURIComponent(username),
      let encodedPassword = encodeURIComponent(password)
    else {
      throw APIError.unknown
    }
    let formBody = "username=\(encodedUsername)&password=\(encodedPassword)"
    guard let bodyData = formBody.data(using: .utf8) else {
      throw APIError.unknown
    }

    let candidateLease = APIServiceSessionLease(
      epoch: startingEpoch,
      baseURL: targetBaseURL,
      token: nil,
      runtime: candidateRuntime
    )
    let data = try await performRequest(
      endpoint: "/login/access-token",
      method: "POST",
      body: bodyData,
      isForm: true,
      lease: candidateLease,
      requireCurrentLease: false
    )
    let tokenResponse = try JSONDecoder().decode(Token.self, from: data)
    guard tokenResponse.hasLoginAccessibleFeature else {
      throw APIError.serverMessage(Self.noAccessibleFeatureMessage)
    }
    guard session.epoch == startingEpoch else { throw CancellationError() }

    replaceSession(
      baseURL: targetBaseURL,
      token: tokenResponse.access_token,
      currentUser: tokenResponse,
      username: username,
      password: password,
      persist: true,
      cookies: candidateRuntime.cookieVault.snapshot()
    )

    return tokenResponse
  }

  func reloginStoredSession() async throws -> Token {
    guard let storedUsername, let storedPassword,
      !storedUsername.isEmpty, !storedPassword.isEmpty
    else {
      throw APIError.serverMessage("未找到保存的凭据")
    }
    let startEpoch = session.epoch
    do {
      return try await login(
        username: storedUsername,
        password: storedPassword,
        serverURL: baseURL
      )
    } catch {
      if Self.isNoAccessibleFeatureError(error), session.epoch == startEpoch {
        logout()
      }
      throw error
    }
  }

  private static func isNoAccessibleFeatureError(_ error: Error) -> Bool {
    guard case APIError.serverMessage(let message) = error else { return false }
    return message.contains(noAccessibleFeatureMessage)
  }

  private func beginCandidateLogin(for epoch: UInt64) {
    activeCandidateLoginCounts[epoch, default: 0] += 1
  }

  private func endCandidateLogin(for epoch: UInt64) {
    guard let count = activeCandidateLoginCounts[epoch] else { return }
    if count > 1 {
      activeCandidateLoginCounts[epoch] = count - 1
    } else {
      activeCandidateLoginCounts.removeValue(forKey: epoch)
    }
  }

  private func isCandidateLoginActive(for epoch: UInt64) -> Bool {
    activeCandidateLoginCounts[epoch, default: 0] > 0
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
    let snapshot = sessionSnapshot()
    do {
      let data = try await makeRequest(endpoint: "/system/global?token=moviepilot")
      var response = try await decodeOrUnwrap(GlobalSettings.self, from: data)
      if token != nil {
        do {
          guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
          let userData = try await makeRequest(endpoint: "/system/global/user")
          let userSettings = try await decodeOrUnwrap(GlobalSettings.self, from: userData)
          response.mergeUserSettings(userSettings)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          print("DEBUG: [fetchSettings] Failed to fetch user settings: \(error)")
        }
      }
      guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
      self.settings = response
      return response
    } catch {
      print("DEBUG: [fetchSettings] Failed to fetch settings: \(error)")
      throw error
    }
  }

  /// 获取系统环境变量
  func fetchSystemEnv() async throws -> SystemEnv {
    let data = try await makeRequest(endpoint: "/system/env")
    return try await decodeOrUnwrap(SystemEnv.self, from: data)
  }

  /// 搜索通用媒体信息
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (path: '/browse/media/search')
  /// - 应用场景: 聚合搜索页面的“电影”和“电视剧”分类结果展示。前端路由 /browse/ 后接的部分即为 API 路径。
  func searchMedia(
    query: String,
    page: Int = 1,
    source: MediaSearchSource? = nil
  ) async throws -> [MediaInfo] {
    var params = [
      "type": "media",
      "title": query,
      "page": String(page),
    ]
    params["source"] = source?.rawValue
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: params
    )
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
  func recognizeTmdbId(
    title: String,
    year: String? = nil,
    type: String? = nil
  ) async -> Int? {
    let snapshot = sessionSnapshot()
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
      
      // 不传 type，保持与 Web 搜索接口一致；显式锁定 TMDB，避免受后端默认识别源影响。
      let results = try await searchMedia(query: queryTitle, source: .themoviedb)
      guard isSessionUnchanged(from: snapshot) else { return nil }
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
          if let tmdbId = MediaIdentifier.validNumericIdentifier(result.tmdb_id) {
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
          if let tmdbId = MediaIdentifier.validNumericIdentifier(result.tmdb_id) {
            Logger.info("[APIService] Search 识别成功 (年份误差匹配): \(rTitle), TMDB: \(tmdbId)")
            return tmdbId
          }
        }
      }
    } catch is CancellationError {
      return nil
    } catch {
      Logger.error("[APIService] searchMedia during recognition failed: \(error)")
    }

    // 3. Fallback 到 recognizeMedia
    // 适用于包含季、集、制作组信息的原始文件名字符串
    guard isSessionUnchanged(from: snapshot) else { return nil }
    do {
      Logger.debug("[APIService] Search 未命中，尝试 Fallback 到后端 Recognize 接口: \(title)")
      let recognizeQuery =
        (searchYear != nil && !title.contains(searchYear!)) ? "\(title) \(searchYear!)" : title
      let result = try await recognizeMedia(title: recognizeQuery, source: .themoviedb)

      // 检查识别出的类型是否匹配（如果已知 type）
      if let targetType = type, let recognizedType = result.media_info?.type {
        if normalizeMediaType(targetType) == normalizeMediaType(recognizedType) {
          if let tmdbId = MediaIdentifier.validNumericIdentifier(result.media_info?.tmdb_id) {
             Logger.info("[APIService] Recognize 识别成功: \(result.media_info?.title ?? ""), TMDB: \(tmdbId)")
             return tmdbId
          }
        } else {
          // 识别出的类型不符，属于误报，拒绝该结果
          Logger.warning("[APIService] recognizeMedia 类型不匹配: 期望 \(targetType), 实际 \(recognizedType)")
          return nil
        }
      }

      if let tmdbId = MediaIdentifier.validNumericIdentifier(result.media_info?.tmdb_id) {
        Logger.info("[APIService] Recognize 识别成功: \(result.media_info?.title ?? ""), TMDB: \(tmdbId)")
        return tmdbId
      }
    } catch is CancellationError {
      return nil
    } catch {
      Logger.error("[APIService] recognizeMedia fallback failed: \(error)")
    }

    Logger.info("[APIService] 识别失败: \(title)")
    return nil
  }

  /// 手动写入表单的媒体 ID 选择器，与 Web MediaIdSelector 请求保持一致。
  func searchManualMedia(
    title: String,
    source: MediaSearchSource
  ) async throws -> [MediaInfo] {
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: [
        "title": title,
        "page": "1",
        "count": "20",
        "source": source.rawValue,
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 搜索合集
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (searchMedia('collection'))
  /// - 应用场景: 聚合搜索页面的“合集”分类。用户在搜索框输入关键词并选择“合集”时调用，用于搜索 TMDB 系列电影。
  func searchCollection(
    query: String,
    page: Int = 1,
    source: MediaSearchSource? = nil
  ) async throws -> [MediaInfo] {
    var params = [
      "type": "collection",
      "title": query,
      "page": String(page),
    ]
    params["source"] = source?.rawValue
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: params
    )
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  /// 搜索人物
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SearchBarDialog.vue (searchMedia('person'))
  /// - 应用场景: 聚合搜索页面的“演职员”分类。用户在搜索框输入关键词并选择“人物”时调用，用于搜索导演、演员等资料。
  func searchPerson(
    query: String,
    page: Int = 1,
    source: MediaSearchSource? = nil
  ) async throws -> [Person] {
    var params = [
      "type": "person",
      "title": query,
      "page": String(page),
    ]
    params["source"] = source?.rawValue
    let endpoint = try buildEndpoint(
      path: "/media/search",
      params: params
    )
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
    let endpoint = try relativeBackendEndpoint(path: path, params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  func fetchDiscoverSources() async throws -> [DiscoverSourceDescriptor] {
    let data = try await makeRequest(endpoint: "/discover/source")
    return try await decodeOrUnwrap([DiscoverSourceDescriptor].self, from: data)
  }

  func fetchRecommendSources() async throws -> [RecommendSourceDescriptor] {
    let data = try await makeRequest(endpoint: "/recommend/source")
    return try await decodeOrUnwrap([RecommendSourceDescriptor].self, from: data)
  }

  /// 获取订阅分享列表
  /// - 对应前端: MoviePilot-Frontend/src/views/subscribe/SubscribeShareView.vue (fetchData)
  /// - 应用场景: "探索"页面的"订阅分享"板块，分页加载用户分享的订阅规则。
  func fetchSubscriptionShares(path: String, page: Int = 1) async throws -> [SubscribeShare] {
    let absolutePath = path.hasPrefix("/") ? path : "/\(path)"
    let endpoint = try buildEndpoint(
      path: absolutePath,
      params: [
        "page": String(page),
        "count": "30",
      ]
    )
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
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (按 TMDB、豆瓣、Bangumi、AniList 字段顺序构造 recommend 路径)
  /// - 应用场景: 在媒体详情页底部，根据 Web 支持的辅助内容来源获取“推荐”列表。
  /// - ⚠️ 注意: Bangumi 的推荐接口不需要传 type。
  func fetchMediaRecommendations(detail: MediaInfo, page: Int = 1) async throws -> [MediaInfo] {
    guard let identity = detail.auxiliaryContentIdentity else { return [] }
    var path: String?
    if identity.source == "themoviedb" {
      guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      else { return [] }
      path = "tmdb/recommend/\(identity.mediaId)/\(type)"
    } else if identity.source == "douban" {
      guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      else { return [] }
      path = "douban/recommend/\(identity.mediaId)/\(type)"
    } else if identity.source == "bangumi" {
      path = "bangumi/recommend/\(identity.mediaId)"
    } else if identity.source == "anilist" {
      path = "anilist/recommend/\(identity.mediaId)"
    }

    guard let finalPath = path else { return [] }
    return try await fetchRecommend(path: finalPath, page: page)
  }

  /// 获取类似媒体
  /// - 对应前端: MoviePilot-Frontend/src/views/discover/MediaDetailView.vue (构造 tmdb/similar/* 系列路径)
  /// - 应用场景: 媒体详情页获取相似推荐内容。
  /// - ⚠️ 注意: Web 只要详情包含有效 TMDB ID 就显示相似内容，不要求主身份为 TMDB。
  func fetchMediaSimilar(detail: MediaInfo, page: Int = 1) async throws -> [MediaInfo] {
    guard let identity = detail.auxiliaryContentIdentity, identity.source == "themoviedb" else {
      return []
    }
    guard let type = detail.type?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else { return [] }
    let path = "tmdb/similar/\(identity.mediaId)/\(type)"
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
    return try decodeActionResponseSync(from: data)
  }

  /// 继续下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/DownloadingCard.vue (toggleDownload)
  /// - 应用场景: 在下载任务列表页恢复指定的已暂停任务。
  func startDownload(clientName: String, hash: String) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/download/start/\(hash)", params: ["name": clientName])
    let data = try await makeRequest(endpoint: endpoint, method: "GET")
    return try decodeActionResponseSync(from: data)
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
    return try decodeActionResponseSync(from: data)
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
  func deleteTransferHistory(
    item: TransferHistory,
    deleteSource: Bool,
    deleteDest: Bool
  )
    async throws
    -> (success: Bool, message: String?)
  {
    let body = try JSONEncoder().encode(item)
    let endpoint = try buildEndpoint(
      path: "/history/transfer",
      params: [
        "deletesrc": String(deleteSource),
        "deletedest": String(deleteDest),
      ])
    let data = try await makeRequest(
      endpoint: endpoint,
      method: "DELETE",
      body: body
    )
    return try decodeStrictActionResponseSync(from: data)
  }

  /// 单条 AI 重新整理历史记录
  /// - 对应前端: `MoviePilot-Frontend/src/views/reorganize/TransferHistoryView.vue`
  func aiRedoTransferHistory(id: Int) async throws -> (progressKey: String, acceptedIds: [Int]) {
    let endpoint = try buildEndpoint(path: "/history/transfer/\(id)/ai-redo")
    let data = try await makeRequest(endpoint: endpoint, method: "POST")
    return try decodeAiRedoResponse(data, fallbackIds: [id])
  }

  /// 批量 AI 重新整理历史记录
  /// - 对应前端: `MoviePilot-Frontend/src/views/reorganize/TransferHistoryView.vue`
  func aiRedoTransferHistories(ids: [Int]) async throws -> (
    progressKey: String, acceptedIds: [Int]
  ) {
    let endpoint = try buildEndpoint(path: "/history/transfer/ai-redo")
    let body = try JSONEncoder().encode(["history_ids": ids])
    let data = try await makeRequest(
      endpoint: endpoint,
      method: "POST",
      body: body
    )
    return try decodeAiRedoResponse(data, fallbackIds: ids)
  }

  private func decodeAiRedoResponse(_ data: Data, fallbackIds: [Int]) throws -> (
    progressKey: String, acceptedIds: [Int]
  ) {
    struct AiRedoResponse: Codable {
      let success: Bool?
      let message: String?
      let message_i18n: String?
      let data: AiRedoResponseData?
    }
    struct AiRedoResponseData: Codable {
      let progress_key: String?
      let history_ids: [Int]?
    }
    let res = try JSONDecoder().decode(AiRedoResponse.self, from: data)
    let message = trimmedNonEmpty([res.message_i18n, res.message])
    guard res.success == true else {
      throw APIError.serverMessage(message ?? "未知错误")
    }
    guard let key = res.data?.progress_key, !key.isEmpty else {
      throw APIError.serverMessage(message ?? "AI 整理失败")
    }
    return (progressKey: key, acceptedIds: res.data?.history_ids ?? fallbackIds)
  }

  /// 手动整理
  /// - 对应前端: `MoviePilot-Frontend/src/components/dialog/ReorganizeDialog.vue`
  /// - 应用场景: 执行手动文件整理或重新整理。
  /// - Parameters:
  ///   - form: 包含整理所需全部信息的表单。
  ///   - background: 是否在后台执行整理任务。`true`为后台执行，会立即返回；`false`为前台执行，会等待任务完成。
  func manualTransfer(
    form: ReorganizeForm,
    background: Bool
  ) async throws -> (
    success: Bool, message: String?
  ) {
    let body = try JSONEncoder().encode(form)
    let endpoint = try buildEndpoint(
      path: "/transfer/manual", params: ["background": String(background)])
    let data = try await makeRequest(
      endpoint: endpoint,
      method: "POST",
      body: body
    )
    return try decodeStrictActionResponseSync(from: data)
  }

  func previewManualTransfer(form: ReorganizeForm) async throws -> ManualTransferPreviewData {
    var previewForm = form
    previewForm.preview = true
    let body = try JSONEncoder().encode(previewForm)
    let endpoint = try buildEndpoint(
      path: "/transfer/manual",
      params: ["background": "false"]
    )
    let data = try await makeRequest(
      endpoint: endpoint,
      method: "POST",
      body: body
    )
    let response = try JSONDecoder().decode(
      ApiResponse<ManualTransferPreviewData>.self,
      from: data
    )
    guard response.success == true else {
      throw APIError.serverMessage(response.localizedMessage ?? "整理预览失败")
    }
    guard var preview = response.data else {
      throw APIError.serverMessage("整理预览响应缺少数据")
    }
    preview.message = response.localizedMessage ?? preview.message
    return preview
  }

  /// 获取存储配置
  /// - 对应前端: `MoviePilot-Frontend/src/components/dialog/ReorganizeDialog.vue` (loadStorages)
  /// - 应用场景: 在手动整理弹窗中，加载可用的目标存储（如 local, alipan, rclone 等）列表。
  func fetchStorages() async throws -> [StorageConf] {
    struct ConfigValue: Decodable {
      let value: [StorageConf]
    }
    let data = try await makeRequest(endpoint: "/system/setting/public/Storages")
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

  /// 查询媒体是否已入库
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/MediaCard.vue (handleCheckExists)
  /// - 应用场景: 电影详情页订阅按钮展示入库状态
  func fetchMediaServerExists(media: MediaInfo) async throws -> Bool {
    let endpoint = try buildEndpoint(
      path: "/mediaserver/exists",
      params: [
        "tmdbid": media.tmdb_id.map(String.init),
        "title": media.title,
        "year": media.year,
        "season": media.season.map(String.init),
        "mtype": media.type,
      ])
    let data = try await makeRequest(endpoint: endpoint)
    return try decodeStrictActionResponseSync(from: data).success
  }

  // MARK: - 资源搜索

  // MARK: - Server-Sent Events (SSE) Streaming

  /// 通用 SSE 流式请求
  private func streamSSE<Event: Decodable & Sendable>(
    endpoint: String,
    as _: Event.Type
  ) -> AsyncThrowingStream<Event, Error> {
    let lease = currentLease()

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try self.validate(lease)
          guard let url = URL(string: "\(lease.baseURL)/api/v1\(endpoint)") else {
            throw APIError.invalidURL
          }
          var request = URLRequest(url: url)
          request.timeoutInterval = 300 // 长连接
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

          if let authToken = lease.token {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
          }
          if let cookie = lease.runtime.cookieVault.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
          }
          request.setValue("zh-CN", forHTTPHeaderField: "X-MoviePilot-Locale")
          request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")

          let (result, response) = try await lease.runtime.transport.bytes(for: request)
          try self.validate(lease)

          guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverMessage("无效响应")
          }
          lease.runtime.cookieVault.update(from: httpResponse, for: url)

          if httpResponse.statusCode != 200 {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
              throw APIError.unauthorized
            }
            throw APIError.serverMessage("HTTP Error \(httpResponse.statusCode)")
          }

          for try await line in result.lines {
            try self.validate(lease)
            if line.hasPrefix("data:") {
              let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
              if let data = jsonString.data(using: .utf8) {
                let event = try JSONDecoder().decode(Event.self, from: data)
                continuation.yield(event)
              }
            }
          }
          continuation.finish()
        } catch {
          if Task.isCancelled {
            continuation.finish()
          } else if self.session.epoch != lease.epoch
            || (error as? URLError)?.code == .cancelled
          {
            continuation.finish(throwing: CancellationError())
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
      return streamSSE(endpoint: endpoint, as: SearchStreamEvent.self)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  }

  /// 流式聚合媒体搜索 (SSE)
  func searchMediaStream(
    keyword: String, type: String?, area: String?, title: String?, year: String?, season: Int?, sites: String?
  ) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    do {
      guard let mediaId = encodeMediaIDPathSegment(keyword) else {
        throw APIError.invalidURL
      }
      let endpoint = try buildEndpoint(
        path: "/search/media/\(mediaId)/stream",
        params: [
          "mtype": type,
          "area": area,
          "title": title,
          "year": year,
          "season": season.map(String.init),
          "sites": sites,
        ])
      return streamSSE(endpoint: endpoint, as: SearchStreamEvent.self)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  }

  /// 进度监听 (SSE)
  func progressStream(progressKey: String) -> AsyncThrowingStream<SearchStreamEvent, Error> {
    return streamSSE(
      endpoint: "/system/progress/\(progressKey)",
      as: SearchStreamEvent.self
    )
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
    let isIdSearch = isResourceMediaSearchKeyword(keyword)

    let endpoint: String
    if isIdSearch {
      guard let mediaId = encodeMediaIDPathSegment(keyword) else {
        throw APIError.invalidURL
      }
      endpoint = try buildEndpoint(
        path: "/search/media/\(mediaId)",
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
  func recognizeMedia(
    title: String,
    source: MediaSearchSource? = nil
  ) async throws -> RecognizeResponse {
    let endpoint = try buildEndpoint(
      path: "/media/recognize",
      params: [
        "title": title,
        "source": source?.rawValue,
      ])
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
    let sourcePath = try personSourcePath(source)
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
    let sourcePath = try personSourcePath(source)
    let endpoint = try buildEndpoint(
      path: "/\(sourcePath)/person/credits/\(personId)",
      params: ["page": String(page)])
    let data = try await makeRequest(endpoint: endpoint)
    return try await decodeOrUnwrap([MediaInfo].self, from: data)
  }

  private func personSourcePath(_ source: String?) throws -> String {
    guard let source else { throw APIError.invalidURL }
    switch source {
    case "themoviedb":
      return "tmdb"
    case "douban", "bangumi", "anilist":
      return source
    default:
      throw APIError.invalidURL
    }
  }

  /// 获取媒体演员
  /// - 对应前端: `MoviePilot-Frontend/src/pages/credits.vue` (调用 `PersonCardListView.vue` 进行分页加载)
  /// - 应用场景: 影视详情页按 Web 的 TMDB、豆瓣、Bangumi、AniList 字段顺序展示演员，支持分页加载。
  func fetchMediaActors(detail: MediaInfo, page: Int) async throws -> [Person] {
    guard let identity = detail.auxiliaryContentIdentity else { return [] }
    let path: String
    if identity.source == "themoviedb" {
      let type = detail.type ?? ""
      path = "tmdb/credits/\(identity.mediaId)/\(type)"
    } else if identity.source == "douban" {
      let type = detail.type ?? ""
      path = "douban/credits/\(identity.mediaId)/\(type)"
    } else if identity.source == "bangumi" {
      path = "bangumi/credits/\(identity.mediaId)"
    } else if identity.source == "anilist" {
      path = "anilist/credits/\(identity.mediaId)"
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
    let data = try await makeRequest(endpoint: "/system/setting/public/Directories")
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value
  }

  /// 获取配置的搜索站点 (IndexerSites)
  func fetchIndexerSites() async throws -> [Int] {
    struct ConfigValue: Decodable {
      let value: [Int]?
    }
    let data = try await makeRequest(endpoint: "/system/setting/public/IndexerSites")
    let config = try await decodeOrUnwrap(ConfigValue.self, from: data)
    return config.value ?? []
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
    let snapshot = sessionSnapshot()
    let cacheKey = "\(snapshot.epoch):\(endpoint)"
    if let cached = await episodeGroupsCache.get(cacheKey) {
      guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
      return cached
    }
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try await decodeOrUnwrap([EpisodeGroup].self, from: data)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    await episodeGroupsCache.set(cacheKey, value: result)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
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
    let snapshot = sessionSnapshot()
    let cacheKey = "\(snapshot.epoch):\(endpoint)"
    if let cached = await mediaSeasonsCache.get(cacheKey) {
      guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
      return cached
    }
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try await decodeOrUnwrap([TmdbSeason].self, from: data)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    await mediaSeasonsCache.set(cacheKey, value: result)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    return result
  }

  /// 获取特定剧集组（如长篇连载划分的部/篇）下的季信息
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue (getGroupSeasons)
  /// - 应用场景: 在前端的季订阅弹窗中，当用户从下拉列表中**选择**了某个“剧集组”（如“司法岛篇”）后，调用此 API 以获取该组专属的分季信息。
  func getGroupSeasons(groupId: String) async throws -> [TmdbSeason] {
    let endpoint = "/media/group/seasons/\(groupId)"
    let snapshot = sessionSnapshot()
    let cacheKey = "\(snapshot.epoch):\(endpoint)"
    if let cached = await groupSeasonsCache.get(cacheKey) {
      guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
      return cached
    }
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    let data = try await makeRequest(endpoint: endpoint)
    let result = try await decodeOrUnwrap([TmdbSeason].self, from: data)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    await groupSeasonsCache.set(cacheKey, value: result)
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    return result
  }

  /// 批量检查媒体服务器中已入库的季、集状态
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue
  /// - 应用场景: 在前端的 **分季订阅弹窗** 中，实时标记哪些季“已入库”、“部分缺失”或“完全缺失”。
  func checkSeasonsNotExists(mediaInfo: MediaInfo) async throws -> [NotExistMediaInfo] {
    let body = try JSONEncoder().encode(mediaInfo)
    let data = try await makeRequest(
      endpoint: "/mediaserver/notexists",
      method: "POST",
      body: body
    )
    return try await decodeOrUnwrap([NotExistMediaInfo].self, from: data)
  }

  /// 保存（更新）订阅配置
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue` (更新) 2. `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (新增)
  /// - 应用场景: 1. 在订阅编辑弹窗中点击“保存”，对现有订阅进行修改 (PUT)。 2. 在媒体卡片或详情页上点击订阅，创建新的订阅记录 (POST)。
  func saveSubscription(_ subscribe: Subscribe) async throws -> (
    success: Bool, message: String?
  ) {
    let body = try JSONEncoder().encode(subscribe)
    let endpoint = "/subscribe/"
    // 如果存在 ID，则很可能是更新 (PUT)，但 API 可能同时处理 POST 或有其他逻辑。
    // 基于 Vue：更新是 PUT /subscribe/，创建是 POST /subscribe/ (或默认配置)
    // 由于 Subscribe 结构体有 ID，如果它 > 0 或不为 nil，则使用 PUT。
    let method = (subscribe.id != nil && subscribe.id != 0) ? "PUT" : "POST"

    let data = try await makeRequest(
      endpoint: endpoint,
      method: method,
      body: body
    )
    let result = try decodeStrictActionResponseSync(from: data)

    if result.success {
      invalidateSubscriptionCaches()
    }
    return result
  }

  /// 新增订阅（简单模式）
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/components/dialog/SubscribeSeasonDialog.vue`
  /// - 应用场景: 在媒体卡片或详情页点击“订阅”图标进行快速订阅。
  ///   - **订阅电影时**: 直接调用此 API，请求中的 `season` 参数为 null。
  ///   - **订阅电视剧分季时**: 会先弹出 `SubscribeSeasonDialog.vue` 分季选择框。用户确认后，前端遍历所选的每一季，并为每一季都单独调用一次此 API，每次传入对应的 `season` 编号。
  /// - 备注：Subscribe 参数用于更新订阅状态缓存
  func addSubscription(
    request: SubscribeRequest,
    subscribe: Subscribe
  ) async throws -> Int? {
    let body = try JSONEncoder().encode(request)
    let data = try await makeRequest(
      endpoint: "/subscribe/",
      method: "POST",
      body: body
    )

    struct SubscribeAddResp: Decodable {
      let id: Int?
    }

    let response = try JSONDecoder().decode(ApiResponse<SubscribeAddResp>.self, from: data)
    guard response.success == true else {
      throw APIError.serverMessage(response.localizedMessage ?? "新增订阅失败")
    }
    if let id = response.data?.id {
      invalidateSubscriptionCaches()
      return id
    }
    return nil
  }

  /// 通过订阅 ID 删除订阅
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue` 2. `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`
  /// - 应用场景: 1. 在订阅编辑弹窗中点击“取消订阅”按钮。 2. 在订阅列表页进行批量删除操作时并发调用。
  func deleteSubscription(id: Int) async throws -> Bool {
    let data = try await makeRequest(
      endpoint: "/subscribe/\(id)",
      method: "DELETE"
    )
    let result = try decodeStrictActionResponseSync(from: data)
    if result.success {
      invalidateSubscriptionCaches()
    }
    return result.success
  }

  /// 通过媒体 ID 和季数删除订阅
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue`
  /// - 应用场景: 在详情页或媒体卡片上，取消对该媒体的订阅（点击已激活的心形图标）。
  func deleteSubscription(media: MediaInfo, season: Int?) async throws -> Bool {
    try await deleteSubscriptionResult(media: media, season: season).success
  }

  func deleteSubscriptionResult(media: MediaInfo, season: Int?) async throws -> (
    success: Bool, message: String?
  ) {
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，返回失败
      return (false, "媒体身份不完整")
    }
    return try await deleteSubscriptionResult(mediaId: mediaId, season: season)
  }

  /// 通过已归一化的主媒体 ID 和季数删除订阅
  /// - 对应前端: `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue` 的 `removeSubscribe`
  /// - 应用场景: 保持 Web 的媒体级删除语义，使用共享身份解析结果。
  func deleteSubscription(mediaId: String, season: Int?) async throws -> Bool {
    try await deleteSubscriptionResult(mediaId: mediaId, season: season).success
  }

  func deleteSubscriptionResult(
    mediaId: String,
    season: Int?
  ) async throws -> (
    success: Bool, message: String?
  ) {
    guard let encodedMediaId = encodeMediaIDPathSegment(mediaId), !encodedMediaId.isEmpty else {
      throw APIError.invalidURL
    }
    let endpoint = try buildEndpoint(
      path: "/subscribe/media/\(encodedMediaId)",
      params: ["season": season.map(String.init)])
    let data = try await makeRequest(
      endpoint: endpoint,
      method: "DELETE"
    )
    let result = try decodeStrictActionResponseSync(from: data)
    if result.success {
      invalidateSubscriptionCaches()
    }
    return result
  }

  /// 复用（Fork）一个订阅分享
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/ForkSubscribeDialog.vue (doFork)
  /// - 应用场景: 在"订阅分享"中，点击"复用"按钮，基于分享的配置创建一个新的个人订阅。
  func forkSubscription(share: SubscribeShare) async throws -> Int {
    let body = try JSONEncoder().encode(share)
    let data = try await makeRequest(
      endpoint: "/subscribe/fork",
      method: "POST",
      body: body
    )
    struct ForkResponse: Decodable {
      let id: Int?
    }
    let response: ApiResponse<ForkResponse>
    do {
      response = try JSONDecoder().decode(ApiResponse<ForkResponse>.self, from: data)
    } catch {
      throw APIError.decodingError(error)
    }
    guard response.success != false else {
      throw APIError.serverMessage(response.localizedMessage ?? "复用订阅失败")
    }
    guard let id = response.data?.id else {
      throw APIError.serverMessage("复用订阅响应缺少 ID")
    }
    invalidateSubscriptionCaches()
    return id
  }

  /// 暂停或恢复订阅状态
  /// - 对应前端: 1. `MoviePilot-Frontend/src/components/cards/SubscribeCard.vue` 2. `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`
  /// - 应用场景: 1. 在订阅列表页对单个卡片进行“暂停/恢复”切换。 2. 在订阅列表页进行批量暂停/恢复操作时并发调用。
  func updateSubscriptionStatus(
    id: Int,
    state: String
  ) async throws -> (
    success: Bool, message: String?
  ) {
    let endpoint = try buildEndpoint(path: "/subscribe/status/\(id)", params: ["state": state])
    let data = try await makeRequest(endpoint: endpoint, method: "PUT")
    let result = try decodeStrictActionResponseSync(from: data)
    if result.success {
      invalidateSubscriptionCaches()
    }
    return result
  }

  /// 立即触发订阅搜索
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue (searchSubscribe)
  /// - 应用场景: 用户在订阅列表手动点击“搜索”按钮，强制后端立即针对该条目执行一次资源检索。
  func searchSubscription(id: Int) async throws -> Bool {
    let data = try await makeRequest(endpoint: "/subscribe/search/\(id)")
    let success = try decodeStrictActionResponseSync(from: data).success
    if success {
      invalidateSubscriptionCaches()
    }
    return success
  }

  /// 重置订阅状态（重新开始）
  /// - 对应前端: MoviePilot-Frontend/src/components/cards/SubscribeCard.vue (resetSubscribe)
  /// - 应用场景: 清除该条目的已下载/已入库记录，使其状态回到初始，通常用于重新洗版或出错后重试。
  func resetSubscription(id: Int) async throws -> (
    success: Bool, message: String?
  ) {
    let data = try await makeRequest(endpoint: "/subscribe/reset/\(id)")
    let result = try decodeStrictActionResponseSync(from: data)
    if result.success {
      invalidateSubscriptionCaches()
    }
    return result
  }

  /// 获取单条订阅详情
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/SubscribeEditDialog.vue
  /// - 应用场景: 编辑订阅前获取完整订阅配置
  func fetchSubscription(id: Int) async throws -> Subscribe {
    let data = try await makeRequest(endpoint: "/subscribe/\(id)")
    return try await decodeOrUnwrap(Subscribe.self, from: data)
  }

  /// 查询特定媒体（及特定季）命中的订阅摘要
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` 和 `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue` 的 `checkSubscribe`
  /// - 应用场景: 详情页 Header 取消订阅前，先复用查询结果解析出真实订阅归属的媒体 ID。
  /// - 备注: 这里只查询传入 `media.apiMediaId` 对应的订阅；原始 ID + fallback TMDB 的解析顺序由调用方控制。
  func fetchSubscriptionLookup(
    media: MediaInfo,
    season: Int? = nil
  ) async throws -> SubscriptionLookupResult? {
    struct SubscribeLookupResp: Codable {
      let id: Int?
      let tmdbid: Int?
      let doubanid: String?
      let bangumiid: Int?
      let anilistid: Int?
      let media_source: String?
      let media_id: String?
      let mediaid: String?

      var apiMediaId: String? {
        if let source = media_source, !source.isEmpty,
          let id = media_id, !id.isEmpty
        {
          let prefix = source == "themoviedb" ? "tmdb" : source
          return "\(prefix):\(id)"
        }
        return MediaIdentifier.apiMediaId(
          tmdbId: MediaIdentifier.truthyNumericIdentifier(tmdbid),
          doubanId: doubanid,
          bangumiId: MediaIdentifier.truthyNumericIdentifier(bangumiid),
          anilistId: MediaIdentifier.truthyNumericIdentifier(anilistid),
          fallbackMediaId: mediaid
        )
      }
    }
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求
      return nil
    }
    guard let encodedMediaId = encodeMediaIDPathSegment(mediaId), !encodedMediaId.isEmpty else {
      throw APIError.invalidURL
    }
    let endpoint = try buildEndpoint(
      path: "/subscribe/media/\(encodedMediaId)",
      params: [
        "season": season.map(String.init),
        "title": media.title,
      ])
    let data = try await makeRequest(endpoint: endpoint)
    let resp = try await decodeOrUnwrap(SubscribeLookupResp.self, from: data)
    guard let id = resp.id else { return nil }
    if let resolvedMediaId = resp.apiMediaId {
      return SubscriptionLookupResult(
        id: id,
        mediaId: resolvedMediaId,
        isResolvedMediaId: true
      )
    }
    return SubscriptionLookupResult(
      id: id,
      mediaId: mediaId,
      isResolvedMediaId: false
    )
  }

  /// 查询特定媒体（及特定季）命中的订阅 ID
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` 和 `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue` 的 `checkSubscribe`
  /// - 应用场景: 媒体卡片和详情页 Header 查询订阅状态。
  /// - 备注: 默认状态检查只需要 ID；需要真实媒体归属时请使用 `fetchSubscriptionLookup(media:season:)`。
  func fetchSubscriptionID(media: MediaInfo, season: Int? = nil) async throws -> Int? {
    try await fetchSubscriptionLookup(
      media: media,
      season: season
    )?.id
  }

  /// 检查特定媒体（及特定季）是否已在用户的订阅列表中
  /// - 对应前端: `MoviePilot-Frontend/src/components/cards/MediaCard.vue` (主要实现), `MoviePilot-Frontend/src/views/discover/MediaDetailView.vue`
  /// - 应用场景: 进入详情页或媒体卡片进入视窗时懒加载调用，用于实时检查并更新“心形”订阅按钮的状态。
  /// - 备注: 默认复用短 TTL Bool 缓存；取消订阅后的状态校准等实时场景应传入 `forceRefresh: true`。
  func checkSubscription(
    media: MediaInfo,
    season: Int? = nil,
    forceRefresh: Bool = false
  ) async throws -> Bool {
    guard let mediaId = media.apiMediaId else {
      // 遵循 Vue 逻辑，如果无法生成 mediaId，则不发起请求，返回 false
      return false
    }
    subscriptionStatusLoadRevision &+= 1
    let requestRevision = subscriptionStatusLoadRevision
    let loadOwnerKey = "\(mediaId):\(season.map(String.init) ?? "")"
    var ownsStatusLoad = false
    if forceRefresh {
      subscriptionStatusLoadOwners[loadOwnerKey] = requestRevision
      ownsStatusLoad = true
    }
    defer {
      if ownsStatusLoad,
        subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision
      {
        subscriptionStatusLoadOwners.removeValue(forKey: loadOwnerKey)
      }
    }
    let snapshot = sessionSnapshot()
    while true {
      try validateSubscriptionSnapshot(snapshot)
      let generation = subscriptionCacheGeneration
      let cacheKey = "\(generation):\(mediaId):\(season.map(String.init) ?? "")"
      if !forceRefresh, let cached = await subscriptionStatusCache.get(cacheKey) {
        try validateSubscriptionSnapshot(snapshot)
        guard generation == subscriptionCacheGeneration else { continue }
        if ownsStatusLoad {
          guard subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision else {
            throw CancellationError()
          }
        }
        return cached
      }
      if !ownsStatusLoad {
        if let currentOwner = subscriptionStatusLoadOwners[loadOwnerKey],
          currentOwner > requestRevision
        {
          throw CancellationError()
        }
        subscriptionStatusLoadOwners[loadOwnerKey] = requestRevision
        ownsStatusLoad = true
        // A newer load may have populated the cache while this caller was awaiting its first read.
        continue
      }
      guard subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision else {
        throw CancellationError()
      }
      let loadToken = await subscriptionStatusCache.beginLoad(
        cacheKey,
        revision: requestRevision
      )

      do {
        guard subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision else {
          await subscriptionStatusCache.endLoadIfCurrent(cacheKey, token: loadToken)
          throw CancellationError()
        }
        try validateSubscriptionSnapshot(snapshot)
        let isSubscribed =
          try await fetchSubscriptionLookup(
            media: media,
            season: season
          ) != nil
        try validateSubscriptionSnapshot(snapshot)
        guard generation == subscriptionCacheGeneration else {
          await subscriptionStatusCache.endLoadIfCurrent(cacheKey, token: loadToken)
          continue
        }
        guard subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision else {
          await subscriptionStatusCache.endLoadIfCurrent(cacheKey, token: loadToken)
          throw CancellationError()
        }
        guard await subscriptionStatusCache.setIfCurrent(
          cacheKey,
          value: isSubscribed,
          token: loadToken
        ) else {
          throw CancellationError()
        }
        try validateSubscriptionSnapshot(snapshot)
        guard generation == subscriptionCacheGeneration else { continue }
        guard subscriptionStatusLoadOwners[loadOwnerKey] == requestRevision else {
          throw CancellationError()
        }
        return isSubscribed
      } catch is CancellationError {
        await subscriptionStatusCache.endLoadIfCurrent(cacheKey, token: loadToken)
        throw CancellationError()
      } catch {
        await subscriptionStatusCache.endLoadIfCurrent(cacheKey, token: loadToken)
        throw error
      }
    }
  }

  /// 拉取当前用户的所有订阅列表
  /// - 对应前端: `MoviePilot-Frontend/src/views/subscribe/SubscribeListView.vue`, `MoviePilot-Frontend/src/views/subscribe/FullCalendarView.swift`
  /// - 应用场景: 1. **订阅列表页面** (`SubscribeListView`) 的核心数据源。 2. **日历视图** (`FullCalendarView`) 的数据源。 (注: 全局搜索栏不直接调用此API)
  func fetchSubscriptions(forceRefresh: Bool = false) async throws -> [Subscribe] {
    let snapshot = sessionSnapshot()
    var canReadCache = !forceRefresh
    while true {
      try validateSubscriptionSnapshot(snapshot)
      let generation = subscriptionCacheGeneration
      let cacheKey = "subscriptions:\(generation)"
      if canReadCache, let cached = await subscriptionSnapshotCache.get(cacheKey) {
        try validateSubscriptionSnapshot(snapshot)
        guard generation == subscriptionCacheGeneration else {
          canReadCache = true
          continue
        }
        return cached
      }

      let fetch = subscriptionSnapshotFetchTask(
        for: generation,
        reuseInFlight: canReadCache,
        snapshot: snapshot
      )
      guard let subscriptions = try await awaitSubscriptionSnapshot(
        fetch,
        generation: generation,
        snapshot: snapshot
      ) else {
        canReadCache = true
        continue
      }
      guard try await storeSubscriptionSnapshot(
        subscriptions,
        cacheKey: cacheKey,
        generation: generation,
        revision: fetch.revision,
        snapshot: snapshot
      ) else {
        canReadCache = true
        continue
      }
      return subscriptions
    }
  }

  private func awaitSubscriptionSnapshot(
    _ fetch: (revision: Int, task: Task<[Subscribe], Error>),
    generation: Int,
    snapshot: APIServiceSessionSnapshot
  ) async throws -> [Subscribe]? {
    let subscriptions: [Subscribe]
    do {
      subscriptions = try await fetch.task.value
    } catch {
      let wasSuperseded = subscriptionSnapshotFetchRevision != fetch.revision
      clearSubscriptionSnapshotFetchTaskIfCurrent(
        generation: generation,
        revision: fetch.revision
      )
      if error is CancellationError {
        try validateSubscriptionSnapshot(snapshot)
      }
      guard generation == subscriptionCacheGeneration, !wasSuperseded else { return nil }
      if error is CancellationError { throw CancellationError() }
      throw error
    }

    try validateSubscriptionSnapshot(snapshot)
    guard generation == subscriptionCacheGeneration else {
      clearSubscriptionSnapshotFetchTaskIfCurrent(
        generation: generation,
        revision: fetch.revision
      )
      return nil
    }
    guard fetch.revision == subscriptionSnapshotFetchTaskRevision else { return nil }
    return subscriptions
  }

  private func storeSubscriptionSnapshot(
    _ subscriptions: [Subscribe],
    cacheKey: String,
    generation: Int,
    revision: Int,
    snapshot: APIServiceSessionSnapshot
  ) async throws -> Bool {
    await subscriptionSnapshotCache.set(cacheKey, value: subscriptions)
    try validateSubscriptionSnapshot(snapshot)
    guard generation == subscriptionCacheGeneration else {
      clearSubscriptionSnapshotFetchTaskIfCurrent(generation: generation, revision: revision)
      return false
    }
    guard revision == subscriptionSnapshotFetchTaskRevision else { return false }
    clearSubscriptionSnapshotFetchTaskIfCurrent(generation: generation, revision: revision)
    return true
  }

  private func validateSubscriptionSnapshot(_ snapshot: APIServiceSessionSnapshot) throws {
    try Task.checkCancellation()
    guard isSessionUnchanged(from: snapshot) else { throw CancellationError() }
  }

  private func subscriptionSnapshotFetchTask(
    for generation: Int,
    reuseInFlight: Bool,
    snapshot: APIServiceSessionSnapshot
  ) -> (revision: Int, task: Task<[Subscribe], Error>) {
    if reuseInFlight,
      let task = subscriptionSnapshotFetchTask,
      let revision = subscriptionSnapshotFetchTaskRevision,
      subscriptionSnapshotFetchGeneration == generation
    {
      return (revision, task)
    }

    subscriptionSnapshotFetchRevision &+= 1
    let revision = subscriptionSnapshotFetchRevision
    let task = Task { [weak self] in
      guard let self else { throw CancellationError() }
      try self.validateSubscriptionSnapshot(snapshot)
      let data = try await self.makeRequest(endpoint: "/subscribe/")
      return try await self.decodeOrUnwrap([Subscribe].self, from: data)
    }
    subscriptionSnapshotFetchGeneration = generation
    subscriptionSnapshotFetchTaskRevision = revision
    subscriptionSnapshotFetchTask = task
    return (revision, task)
  }

  private func clearSubscriptionSnapshotFetchTaskIfCurrent(generation: Int, revision: Int) {
    guard subscriptionSnapshotFetchGeneration == generation else { return }
    guard subscriptionSnapshotFetchTaskRevision == revision else { return }
    subscriptionSnapshotFetchGeneration = nil
    subscriptionSnapshotFetchTaskRevision = nil
    subscriptionSnapshotFetchTask = nil
  }

  /// 添加下载任务
  /// - 对应前端: MoviePilot-Frontend/src/components/dialog/AddDownloadDialog.vue
  /// - 应用场景: 在资源搜索结果中选择特定条目后，将其推送到后端下载器执行下载。
  func addDownload(payload: AddDownloadRequest) async throws -> (
    success: Bool, message: String?
  ) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let body = try encoder.encode(payload)

    let endpoint = payload.media_in == nil ? "/download/add" : "/download/"
    let data = try await makeRequest(endpoint: endpoint, method: "POST", body: body)

    return try decodeStrictActionResponseSync(from: data)
  }

  /// 获取订阅的海报图片 URL
  func getSubscribePosterImageUrl(_ subscribe: Subscribe) -> URL? {
    return getSubscribePosterImageUrl(poster: subscribe.poster)
  }

  func getSubscribePosterImageUrl(poster: String?) -> URL? {
    return displayImageURL(poster, baseURL: baseURL, useImageCache: useImageCache)
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

    return displayImageURL(url, baseURL: baseURL, useImageCache: useImageCache)
  }

  /// 获取海报原始 URL（不降尺寸），作为降尺寸版本加载失败时的回退来源。
  /// 与降尺寸版本共用豆瓣默认海报拦截规则。
  func getPosterImageUrlOriginal(posterPath: String?) -> URL? {
    if let url = posterPath, url.contains("doubanio.com") {
      if url.contains("movie_default") || url.contains("tv_default") {
        return nil
      }
    }
    return displayImageURL(posterPath, baseURL: baseURL, useImageCache: useImageCache)
  }

  /// 获取媒体背景图片 URL
  func getBackdropImageUrl(_ media: MediaInfo) -> URL? {
    return getBackdropImageUrl(backdropPath: media.backdrop_path)
  }

  func getBackdropImageUrl(backdropPath: String?) -> URL? {
    return displayImageURL(backdropPath, baseURL: baseURL, useImageCache: useImageCache)
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
    guard let encodedUrl = encodeURIComponent(path)
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
    let resolvedPath = posterPath?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackPath = mediaPosterPath?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let path = [resolvedPath, fallbackPath].compactMap({ $0 }).first(where: { !$0.isEmpty })
    else { return nil }

    if path.hasPrefix("/") {
      let domain = settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
      return displayImageURL(
        "https://\(domain)/t/p/w500\(path)",
        baseURL: baseURL,
        useImageCache: useImageCache
      )
    }
    return displayImageURL(
      path.replacingOccurrences(of: "/t/p/original/", with: "/t/p/w500/"),
      baseURL: baseURL,
      useImageCache: useImageCache
    )
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
    let url: String
    switch source {
    case "themoviedb":
      guard let profilePath else { return nil }
      let domain = settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
      url = "https://\(domain)/t/p/w600_and_h900_bestv2\(profilePath)"
    case "douban":
      guard let avatarURL = avatar?.urlValue else { return nil }
      url = avatarURL
    case "bangumi":
      guard let image = images?.medium else { return nil }
      url = image
    case "anilist":
      // AniList 媒体详情的内嵌 directors/actors 使用 avatar.large，
      // 而独立 credits/person 端点使用 images.large；两种结构都要兼容。
      guard let image = images?.large ?? images?.medium ?? avatar?.urlValue else { return nil }
      url = image
    default:
      return nil
    }

    // 匹配豆瓣默认人员图标并拦截 (针对 Apple TV 的特殊优化)
    if url.contains("doubanio.com")
      && (url.contains("personage-default") || (url.contains("celebrity-default")))
    {
      return nil
    }

    return displayImageURL(url, baseURL: baseURL, useImageCache: useImageCache)
  }

  func isProtectedImageURL(_ url: URL) -> Bool {
    guard let server = URLComponents(string: baseURL),
      let target = URLComponents(url: url, resolvingAgainstBaseURL: false),
      server.scheme?.lowercased() == target.scheme?.lowercased(),
      server.host?.lowercased() == target.host?.lowercased(),
      effectivePort(server) == effectivePort(target)
    else {
      return false
    }
    let serverPath = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let apiPath = serverPath.isEmpty ? "/api/v1" : "/\(serverPath)/api/v1"
    return url.path.hasPrefix("\(apiPath)/system/img/")
      || url.path == "\(apiPath)/system/cache/image"
  }

  func imageSource(for url: URL) -> Source {
    let resource: KF.ImageResource
    if isProtectedImageURL(url) {
      resource = KF.ImageResource(
        downloadURL: url,
        cacheKey: "moviepilot-protected:\(session.imageNamespace):\(url.absoluteString)"
      )
    } else {
      resource = KF.ImageResource(downloadURL: url)
    }
    return .network(resource)
  }

  func imageOptions(for url: URL) -> KingfisherOptionsInfo {
    guard let downloader = imageDownloader(for: url),
      let modifier = imageRequestModifier(for: url)
    else {
      return []
    }
    return [
      .downloader(downloader),
      .requestModifier(modifier),
    ]
  }

  func imageDownloader(for url: URL) -> ImageDownloader? {
    isProtectedImageURL(url) ? runtime.imageDownloader : nil
  }

  func imageRequestModifier(for url: URL) -> AnyModifier? {
    guard isProtectedImageURL(url) else { return nil }
    let vault = runtime.cookieVault
    return AnyModifier { request in
      var request = request
      if let url = request.url, let cookie = vault.cookieHeader(for: url) {
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
      }
      return request
    }
  }

  private func effectivePort(_ components: URLComponents) -> Int? {
    if let port = components.port { return port }
    return components.scheme?.lowercased() == "https" ? 443 : 80
  }
}
