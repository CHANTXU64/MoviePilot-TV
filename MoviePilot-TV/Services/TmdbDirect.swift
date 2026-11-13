import Foundation
import Network

// 单集对应补查时由 TV 端直接请求 TMDB：用 MoviePilot 配置的 key、接口域名和网络代理，只查还只按季号集号对上的文件。
// 查到的结果按请求存在本机缓存里（TMDB 公开数据，不含 key，不分账号），之后打开同一部剧不用再等。
// 请求量要克制：MoviePilot 默认那把 key 是所有 MoviePilot 用户共用的，用得太狠会连累所有人。

// MARK: - 访问配置

/// MoviePilot 的 TMDB 访问配置（`GET /api/v1/system/env`，管理员才能读）。key 只放在内存里，随会话作用域拆除，
/// 不写日志，也不进磁盘缓存。
nonisolated struct TmdbAccess: Equatable, Sendable {
  let apiKey: String
  /// 接口域名，MoviePilot 按 `https://{域名}/3` 拼地址，可以带路径前缀（反向代理）。
  let domain: String
  /// MoviePilot 集列表用的语言（`TMDB_LOCALE`），补查其他语言时跳过它。
  let locale: String?
  /// MoviePilot 访问 TMDB 用的代理；没配时为 nil。
  let proxy: TmdbProxy?

  init(apiKey: String, domain: String, locale: String? = nil, proxy: TmdbProxy? = nil) {
    self.apiKey = apiKey
    self.domain = domain
    self.locale = locale
    self.proxy = proxy
  }
}

/// MoviePilot 的网络代理（`PROXY_HOST`）。
nonisolated struct TmdbProxy: Equatable, Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    /// `http://`、`https://`：HTTP CONNECT 代理，`https` 时到代理这段也加密。
    case http(tls: Bool)
    /// `socks5://`、`socks5h://`
    case socks5
  }

  let kind: Kind
  let host: String
  let port: UInt16
  let username: String?
  let password: String?

  /// 读不出或 TV 用不了时为 nil 并给出原因：`127.0.0.1`、`localhost` 这类地址是 MoviePilot 所在机器自己的，Apple TV 连不到。
  static func parse(_ raw: String) -> Result<TmdbProxy, ProxyProblem> {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
      let host = components.host.flatMap({ trimmedNonEmpty([$0]) })
    else { return .failure(.unreadable) }
    let kind: Kind
    let defaultPort: UInt16
    switch scheme {
    case "http": (kind, defaultPort) = (.http(tls: false), 80)
    case "https": (kind, defaultPort) = (.http(tls: true), 443)
    case "socks5", "socks5h": (kind, defaultPort) = (.socks5, 1080)
    default: return .failure(.unsupportedScheme)
    }
    let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if lowered == "localhost" || lowered.hasPrefix("127.") || lowered == "::1" || lowered == "0.0.0.0"
      || lowered == "host.docker.internal"
    {
      return .failure(.loopback)
    }
    guard let port = components.port.map({ UInt16(exactly: $0) }) ?? defaultPort else { return .failure(.unreadable) }
    return .success(
      TmdbProxy(
        kind: kind, host: host, port: port, username: components.user?.removingPercentEncoding,
        password: components.password?.removingPercentEncoding))
  }

  enum ProxyProblem: Error, Equatable, Sendable {
    case unreadable, unsupportedScheme, loopback

    var message: String {
      switch self {
      case .unreadable: "MoviePilot 的网络代理地址读不出来"
      case .unsupportedScheme: "MoviePilot 的网络代理不是 HTTP 或 SOCKS5 代理"
      case .loopback: "MoviePilot 的网络代理是它所在机器自己的地址，Apple TV 连不上"
      }
    }
  }
}

/// `/system/env` 里补查用到的几项，其余（下载器、通知等的密码）不解码。
nonisolated struct TmdbAccessSettings: Decodable, Sendable {
  let apiKey: String?
  let domain: String?
  let locale: String?
  let proxyHost: String?

  private enum CodingKeys: String, CodingKey {
    case apiKey = "TMDB_API_KEY"
    case domain = "TMDB_API_DOMAIN"
    case locale = "TMDB_LOCALE"
    case proxyHost = "PROXY_HOST"
  }

  init(apiKey: String?, domain: String?, locale: String? = nil, proxyHost: String? = nil) {
    self.apiKey = apiKey
    self.domain = domain
    self.locale = locale
    self.proxyHost = proxyHost
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    apiKey = try? container.decodeIfPresent(String.self, forKey: .apiKey)
    domain = try? container.decodeIfPresent(String.self, forKey: .domain)
    locale = try? container.decodeIfPresent(String.self, forKey: .locale)
    proxyHost = try? container.decodeIfPresent(String.self, forKey: .proxyHost)
  }

  /// 能用的访问配置；key 或域名没有、代理用不了时给出原因。
  var access: Result<TmdbAccess, TmdbDirectError> {
    guard let apiKey = trimmedNonEmpty([apiKey]), let domain = trimmedNonEmpty([domain]) else {
      return .failure(.notConfigured("MoviePilot 没有提供 TMDB 的 key 或接口地址"))
    }
    var proxy: TmdbProxy?
    if let proxyHost = trimmedNonEmpty([proxyHost]) {
      switch TmdbProxy.parse(proxyHost) {
      case .success(let value): proxy = value
      case .failure(let problem): return .failure(.notConfigured(problem.message))
      }
    }
    return .success(TmdbAccess(apiKey: apiKey, domain: domain, locale: trimmedNonEmpty([locale]), proxy: proxy))
  }
}

nonisolated enum TmdbDirectError: Error, Equatable, Sendable {
  /// 没有可用的访问配置
  case notConfigured(String)
  /// TMDB 限流（HTTP 429），或刚才连不上、还在等待时间里：这一轮不再请求
  case coolingDown
  case status(Int)
  case invalidResponse
  /// 连不上（超时、代理或域名不通）
  case unreachable
  /// 只读缓存时缓存里没有
  case notCached

  var message: String {
    switch self {
    case .notConfigured(let reason): reason
    case .coolingDown: "TMDB 暂时限流或连不上，稍后再查"
    case .status(let code): "TMDB 返回 HTTP \(code)"
    case .invalidResponse: "TMDB 返回的数据认不出"
    case .unreachable: "连不上 TMDB"
    case .notCached: "还没查过"
    }
  }
}

// MARK: - 查询接口

/// 按外部编号在 TMDB 反查到的一集。
nonisolated struct TmdbFoundEpisode: Codable, Equatable, Sendable {
  let id: Int
  /// 所属剧的 TMDB 编号
  let showID: Int
}

/// 补查用到的 TMDB 查询。`TmdbLookupStore` 带缓存和限速，测试用替身。`cachedOnly` 时只读缓存，没有就抛 `notCached`。
nonisolated protocol TmdbEpisodeDirectory: Sendable {
  /// 按外部编号反查单集。`source` 是规范来源（`tvdb`、`imdb`）。
  func findEpisodes(source: String, value: String, access: TmdbAccess, cachedOnly: Bool) async throws
    -> [TmdbFoundEpisode]
  /// 一季的集列表（默认顺序），`language` 如 `en-US`、`ja`。这一季不存在时为空。
  func seasonEpisodes(tvID: Int, season: Int, language: String, access: TmdbAccess, cachedOnly: Bool) async throws
    -> [TmdbEpisode]
  /// 剧的原始语言（`original_language`），如 `ja`。
  func originalLanguage(tvID: Int, access: TmdbAccess, cachedOnly: Bool) async throws -> String?
}

// MARK: - 补查

nonisolated enum TmdbEpisodeEvidence {
  /// 后台一轮补查最多花这么久，到点不再发新请求，已经查到的照常用；没查完的下次打开再查（查到的已经缓存）。
  static let budget: Duration = .seconds(30)
  /// 一轮里同时在途的查询数，和 `TmdbLookupStore` 的并发上限一致：不往限速队列里堆请求，到点后不会再有排着队的请求发出去。
  static let maxInFlight = 2

  /// 先按外部编号反查，反查到这部剧唯一一集的就算确定；剩下的有具体标题的文件，再取这一季的原语言和英文列表核对标题。
  /// `cachedOnly` 时只读本机缓存（建对应表时用，不等网络），没查过的记为没查全。
  static func collect(
    _ request: ExternalEvidenceRequest, access: TmdbAccess, directory: any TmdbEpisodeDirectory, cachedOnly: Bool,
    budget: Duration = budget
  ) async -> ExternalEvidenceResult {
    let deadline = ContinuousClock.now.advanced(by: budget)
    var result = ExternalEvidenceResult()
    var stopped = false
    var failures = 0
    let lookups = request.candidates.filter { !$0.externalIDs.isEmpty }
    await withTaskGroup(of: LookupOutcome.self) { group in
      var pending = lookups.makeIterator()
      func startNext() -> Bool {
        guard !stopped, ContinuousClock.now < deadline, let candidate = pending.next() else { return false }
        group.addTask {
          await lookUp(
            candidate, tmdbID: request.tmdbID, access: access, directory: directory, cachedOnly: cachedOnly,
            deadline: deadline)
        }
        return true
      }
      for _ in 0..<maxInFlight where !startNext() { break }
      while let outcome = await group.next() {
        if let match = outcome.match { result.lookedUp[outcome.itemID] = match }
        if !outcome.isComplete { result.isComplete = false }
        if outcome.failed { failures += 1 }
        if outcome.coolingDown { stopped = true }
        _ = startNext()
      }
      // 没轮到的（限流、到时间）都没查。
      if pending.next() != nil { result.isComplete = false }
    }
    let seasons = Set(request.candidates.compactMap { candidate in
      result.lookedUp[candidate.itemID] == nil ? candidate.titleSeason : nil
    })
    var seasonLists = 0
    if !seasons.isEmpty {
      do {
        guard !stopped, ContinuousClock.now < deadline else { throw TmdbDirectError.coolingDown }
        let original = try await directory.originalLanguage(tvID: request.tmdbID, access: access, cachedOnly: cachedOnly)
        let languages = otherLanguages(original: original, locale: access.locale)
        for season in seasons.sorted() {
          for language in languages {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { throw CancellationError() }
            do {
              let list = try await directory.seasonEpisodes(
                tvID: request.tmdbID, season: season, language: language, access: access, cachedOnly: cachedOnly)
              if !list.isEmpty {
                result.translatedSeasons[season, default: []].append(list)
                seasonLists += 1
              }
            } catch TmdbDirectError.notCached {
              result.isComplete = false
            }
          }
        }
      } catch {
        result.isComplete = false
        if error as? TmdbDirectError == .coolingDown {
          stopped = true
        } else if !(error is CancellationError), error as? TmdbDirectError != .notCached {
          failures += 1
        }
      }
    }
    if !cachedOnly {
      Logger.info(
        "[Playback] 去 TMDB 补查 \(request.candidates.count) 个还没确定对应的文件：按外部编号反查到 \(result.lookedUp.count) 个，"
          + "取了 \(seasonLists) 份其他语言的季列表"
          + (failures > 0 ? "，\(failures) 次请求失败" : "") + (stopped ? "，TMDB 限流或连不上，这一轮先停" : "")
          + (ContinuousClock.now >= deadline ? "，到时间没查完的下次再查" : ""))
    }
    return result
  }

  private struct LookupOutcome: Sendable {
    let itemID: String
    var match: ExternalEpisodeMatch?
    var isComplete = true
    var failed = false
    var coolingDown = false
  }

  /// 依次用各个外部编号反查。结果里这部剧只有一集才算；有两集以上说明 TMDB 的关联有歧义，不再用别的编号。
  private static func lookUp(
    _ candidate: ExternalEvidenceRequest.Candidate, tmdbID: Int, access: TmdbAccess,
    directory: any TmdbEpisodeDirectory, cachedOnly: Bool, deadline: ContinuousClock.Instant
  ) async -> LookupOutcome {
    var outcome = LookupOutcome(itemID: candidate.itemID)
    for (source, value) in candidate.externalIDs {
      guard ContinuousClock.now < deadline, !Task.isCancelled else {
        outcome.isComplete = false
        break
      }
      do {
        let mine = try await directory.findEpisodes(source: source, value: value, access: access, cachedOnly: cachedOnly)
          .filter { $0.showID == tmdbID }
        if mine.count == 1, let found = mine.first {
          outcome.match = ExternalEpisodeMatch(tmdbEpisodeID: found.id, source: source, value: value)
          return outcome
        }
        if mine.count > 1 { break }
      } catch TmdbDirectError.notCached {
        outcome.isComplete = false
      } catch TmdbDirectError.coolingDown {
        outcome.isComplete = false
        outcome.coolingDown = true
        break
      } catch {
        outcome.isComplete = false
        if error is CancellationError { break }
        outcome.failed = true
      }
    }
    return outcome
  }

  /// 要取的其他语言：剧的原始语言和英文，去掉 MoviePilot 集列表已经用的语言（按语言部分比，`zh-CN` 和 `zh` 算同一种）。
  static func otherLanguages(original: String?, locale: String?) -> [String] {
    func base(_ code: String) -> String { code.split(separator: "-").first.map { $0.lowercased() } ?? code.lowercased() }
    let used = locale.map(base)
    var languages: [String] = []
    for code in [original.flatMap { trimmedNonEmpty([$0]) }, "en-US"].compactMap({ $0 }) {
      let key = base(code)
      guard key != used, !languages.contains(where: { base($0) == key }) else { continue }
      languages.append(code)
    }
    return languages
  }
}

// MARK: - 带缓存和限速的查询

/// 发 TMDB 请求的传输层，测试用替身。
nonisolated protocol TmdbTransport: Sendable {
  func data(for request: URLRequest, proxy: TmdbProxy?) async throws -> (Data, HTTPURLResponse)
}

/// 按代理配置复用 URLSession。不存 Cookie、不用系统缓存（结果自己缓存）。
nonisolated final class URLSessionTmdbTransport: TmdbTransport, @unchecked Sendable {
  static let requestTimeout: TimeInterval = 6
  private let lock = NSLock()
  private var sessions: [TmdbProxy?: URLSession] = [:]

  func data(for request: URLRequest, proxy: TmdbProxy?) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session(for: proxy).data(for: request)
    guard let http = response as? HTTPURLResponse else { throw TmdbDirectError.invalidResponse }
    return (data, http)
  }

  private func session(for proxy: TmdbProxy?) -> URLSession {
    lock.lock()
    defer { lock.unlock() }
    if let session = sessions[proxy] { return session }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Self.requestTimeout
    configuration.timeoutIntervalForResource = Self.requestTimeout * 2
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    if let proxy, let port = NWEndpoint.Port(rawValue: proxy.port) {
      let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: port)
      var proxyConfiguration: ProxyConfiguration
      switch proxy.kind {
      case .http(let tls):
        proxyConfiguration = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: tls ? NWProtocolTLS.Options() : nil)
      case .socks5:
        proxyConfiguration = ProxyConfiguration(socksv5Proxy: endpoint)
      }
      if let username = proxy.username {
        proxyConfiguration.applyCredential(username: username, password: proxy.password ?? "")
      }
      configuration.proxyConfigurations = [proxyConfiguration]
    }
    let session = URLSession(configuration: configuration)
    sessions[proxy] = session
    return session
  }
}

/// TMDB 查询的本机缓存和限速，全 App 共用一份（TMDB 公开数据，不分账号）。
/// - 缓存：反查到的和完整、已播完一阵的季列表存 60 天；反查不到、这一季不存在的存 7 天（TMDB 可能补上关联）；
///   最近播出、标题还是占位名或缺日期的季列表只存 3 天（TMDB 会补正）。失败不缓存。存在 Caches 目录，系统清掉也只是重新查。
/// - 限速：同时最多两个请求；同一请求在途时合并。遇到 429 按 `Retry-After`（没有时 60 秒）暂停，连不上暂停 10 分钟，
///   期间直接报 `coolingDown`，不再发请求。
actor TmdbLookupStore: TmdbEpisodeDirectory {
  static let shared = TmdbLookupStore()

  static let longLife: TimeInterval = 60 * 24 * 3600
  static let missLife: TimeInterval = 7 * 24 * 3600
  static let freshLife: TimeInterval = 3 * 24 * 3600
  static let unreachablePause: TimeInterval = 600
  static let capacity = 20_000

  enum Payload: Codable, Equatable, Sendable {
    case found([TmdbFoundEpisode])
    case episodes([CachedEpisode])
    case language(String?)
  }

  struct CachedEpisode: Codable, Equatable, Sendable {
    let id: Int?
    let number: Int?
    let season: Int?
    let name: String?
    let airDate: String?
  }

  struct Entry: Codable, Equatable, Sendable {
    let expiresAt: Date
    let payload: Payload
  }

  private let fileURL: URL?
  private let transport: any TmdbTransport
  private let now: @Sendable () -> Date
  private let maxConcurrent: Int
  private var entries: [String: Entry]?
  private var inFlight: [String: Task<Payload, Error>] = [:]
  private var pausedUntil: Date?
  private var running = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var saveTask: Task<Void, Never>?

  init(
    fileURL: URL? = TmdbLookupStore.defaultFileURL, transport: any TmdbTransport = URLSessionTmdbTransport(),
    maxConcurrent: Int = 2, now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.fileURL = fileURL
    self.transport = transport
    self.maxConcurrent = maxConcurrent
    self.now = now
  }

  static var defaultFileURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("TmdbEpisodeLookup.json")
  }

  // MARK: 查询

  func findEpisodes(source: String, value: String, access: TmdbAccess, cachedOnly: Bool) async throws
    -> [TmdbFoundEpisode]
  {
    let externalSource = source == "imdb" ? "imdb_id" : "\(source)_id"
    let payload = try await cached("find|\(source)|\(value)", cachedOnly: cachedOnly) {
      let data = try await self.get(access, path: ["find", value], query: ["external_source": externalSource])
      guard let data else { return (.found([]), Self.missLife) }
      guard let decoded = try? JSONDecoder().decode(FindResponse.self, from: data) else {
        throw TmdbDirectError.invalidResponse
      }
      let found = decoded.episodes.compactMap { episode -> TmdbFoundEpisode? in
        guard let id = MediaIdentifier.validNumericIdentifier(episode.id),
          let show = MediaIdentifier.validNumericIdentifier(episode.showID)
        else { return nil }
        return TmdbFoundEpisode(id: id, showID: show)
      }
      return (.found(found), found.isEmpty ? Self.missLife : Self.longLife)
    }
    guard case .found(let found) = payload else { throw TmdbDirectError.invalidResponse }
    return found
  }

  func seasonEpisodes(tvID: Int, season: Int, language: String, access: TmdbAccess, cachedOnly: Bool) async throws
    -> [TmdbEpisode]
  {
    let payload = try await cached("season|\(tvID)|\(season)|\(language)", cachedOnly: cachedOnly) {
      let data = try await self.get(
        access, path: ["tv", String(tvID), "season", String(season)], query: ["language": language])
      guard let data else { return (.episodes([]), Self.missLife) }
      guard let decoded = try? JSONDecoder().decode(SeasonResponse.self, from: data) else {
        throw TmdbDirectError.invalidResponse
      }
      let episodes = decoded.episodes.map {
        CachedEpisode(id: $0.id, number: $0.episodeNumber, season: $0.seasonNumber, name: $0.name, airDate: $0.airDate)
      }
      return (.episodes(episodes), Self.life(of: episodes, now: self.now()))
    }
    guard case .episodes(let episodes) = payload else { throw TmdbDirectError.invalidResponse }
    return episodes.map {
      TmdbEpisode(id: $0.id, episodeNumber: $0.number, seasonNumber: $0.season, name: $0.name, airDate: $0.airDate)
    }
  }

  func originalLanguage(tvID: Int, access: TmdbAccess, cachedOnly: Bool) async throws -> String? {
    let payload = try await cached("language|\(tvID)", cachedOnly: cachedOnly) {
      let data = try await self.get(access, path: ["tv", String(tvID)], query: [:])
      guard let data else { return (.language(nil), Self.missLife) }
      guard let decoded = try? JSONDecoder().decode(SeriesResponse.self, from: data) else {
        throw TmdbDirectError.invalidResponse
      }
      return (.language(trimmedNonEmpty([decoded.originalLanguage])), Self.longLife)
    }
    guard case .language(let language) = payload else { throw TmdbDirectError.invalidResponse }
    return language
  }

  /// 季列表存多久：有集刚播出（30 天内）或还没播、缺日期、标题是占位名时 TMDB 还会补正，只存几天。
  nonisolated private static func life(of episodes: [CachedEpisode], now: Date) -> TimeInterval {
    guard !episodes.isEmpty else { return missLife }
    let recent = now.addingTimeInterval(-30 * 24 * 3600)
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    let settled = episodes.allSatisfy { episode in
      guard EpisodeTitle.normalized(episode.name) != nil, let text = episode.airDate,
        let date = formatter.date(from: String(text.prefix(10)))
      else { return false }
      return date < recent
    }
    return settled ? longLife : freshLife
  }

  // MARK: 缓存

  /// 有没过期的缓存就用；`cachedOnly` 时到此为止，没有就抛 `notCached`（不等在途的请求）。否则同一请求在途时等它，
  /// 再否则限速后发请求，成功的存起来。
  private func cached(
    _ key: String, cachedOnly: Bool, load: @escaping @Sendable () async throws -> (Payload, TimeInterval)
  ) async throws -> Payload {
    let stored = loadEntries()
    if let entry = stored[key], entry.expiresAt > now() { return entry.payload }
    if cachedOnly { throw TmdbDirectError.notCached }
    if let task = inFlight[key] { return try await task.value }
    if let pausedUntil, pausedUntil > now() { throw TmdbDirectError.coolingDown }
    let task = Task<Payload, Error> { try await self.perform(key, load: load) }
    inFlight[key] = task
    defer { inFlight[key] = nil }
    return try await task.value
  }

  /// 排队拿到请求名额后再看一次是否暂停（排队期间可能刚遇到限流），再发请求。
  private func perform(
    _ key: String, load: @Sendable () async throws -> (Payload, TimeInterval)
  ) async throws -> Payload {
    await acquire()
    defer { release() }
    if let pausedUntil, pausedUntil > now() { throw TmdbDirectError.coolingDown }
    let (payload, life) = try await load()
    store(key, Entry(expiresAt: now().addingTimeInterval(life), payload: payload))
    return payload
  }

  private func store(_ key: String, _ entry: Entry) {
    var current = loadEntries()
    current[key] = entry
    entries = current
    scheduleSave()
  }

  private func loadEntries() -> [String: Entry] {
    if let entries { return entries }
    var loaded: [String: Entry] = [:]
    if let fileURL, let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
    {
      let current = now()
      loaded = decoded.filter { $0.value.expiresAt > current }
    }
    entries = loaded
    return loaded
  }

  private func scheduleSave() {
    guard saveTask == nil, fileURL != nil else { return }
    saveTask = Task {
      try? await Task.sleep(for: .seconds(2))
      await self.flush()
    }
  }

  /// 把缓存写回磁盘：去掉过期的，超出容量时先丢最早过期的。
  func flush() {
    saveTask = nil
    guard let fileURL, let entries else { return }
    let current = now()
    var kept = entries.filter { $0.value.expiresAt > current }
    if kept.count > Self.capacity {
      let overflow = kept.sorted { $0.value.expiresAt < $1.value.expiresAt }.prefix(kept.count - Self.capacity)
      for (key, _) in overflow { kept[key] = nil }
    }
    self.entries = kept
    do {
      try JSONEncoder().encode(kept).write(to: fileURL, options: .atomic)
    } catch {
      Logger.warning("[Playback] TMDB 补查缓存没能写入：\(error.localizedDescription)")
    }
  }

  // MARK: 限速与请求

  private func acquire() async {
    if running < maxConcurrent {
      running += 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  private func release() {
    if waiters.isEmpty {
      running -= 1
    } else {
      waiters.removeFirst().resume()
    }
  }

  private func pause(for interval: TimeInterval) {
    let until = now().addingTimeInterval(interval)
    if pausedUntil.map({ $0 < until }) ?? true { pausedUntil = until }
  }

  /// 发一个 GET。404 返回 nil：这一季、这部剧不存在，或反查的编号格式不对（查不到时 TMDB 本来返回 200 和空结果），
  /// 都按查不到缓存。地址里带 key，不写日志。
  private func get(_ access: TmdbAccess, path: [String], query: [String: String]) async throws -> Data? {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    let segments = path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
    guard var components = URLComponents(string: "https://\(access.domain)/3/" + segments.joined(separator: "/")) else {
      throw TmdbDirectError.notConfigured("MoviePilot 的 TMDB 接口地址认不出")
    }
    components.queryItems = [URLQueryItem(name: "api_key", value: access.apiKey)]
      + query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let url = components.url else { throw TmdbDirectError.notConfigured("MoviePilot 的 TMDB 接口地址认不出") }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.data(for: request, proxy: access.proxy)
    } catch let error as URLError where error.code != .cancelled {
      pause(for: Self.unreachablePause)
      throw TmdbDirectError.unreachable
    }
    switch response.statusCode {
    case 200..<300:
      return data
    case 404:
      return nil
    case 429:
      let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
      pause(for: min(max(retryAfter, 1), 3600))
      throw TmdbDirectError.coolingDown
    default:
      throw TmdbDirectError.status(response.statusCode)
    }
  }

  private struct FindResponse: Decodable {
    let episodes: [Episode]

    struct Episode: Decodable {
      let id: Int?
      let showID: Int?
      private enum CodingKeys: String, CodingKey {
        case id
        case showID = "show_id"
      }
      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(Int.self, forKey: .id)
        showID = try? container.decodeIfPresent(Int.self, forKey: .showID)
      }
    }

    private enum CodingKeys: String, CodingKey { case episodes = "tv_episode_results" }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      episodes = (try? container.decodeIfPresent([Episode].self, forKey: .episodes)) ?? []
    }
  }

  private struct SeasonResponse: Decodable {
    let episodes: [TmdbEpisode]
    private enum CodingKeys: String, CodingKey { case episodes }
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      episodes = try container.decode([TmdbEpisode].self, forKey: .episodes)
    }
  }

  private struct SeriesResponse: Decodable {
    let originalLanguage: String?
    private enum CodingKeys: String, CodingKey { case originalLanguage = "original_language" }
  }
}
