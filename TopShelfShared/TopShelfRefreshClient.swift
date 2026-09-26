import Foundation
import Security
import TVServices

nonisolated struct TopShelfRefreshConfiguration: Codable, Equatable, Sendable {
  let sessionID: String
  let baseURL: String
  let useImageCache: Bool
  let bangumiProxyEnabled: Bool
  let bangumiImageDomain: String?

  func imageURL(_ path: String?) -> URL? {
    guard let path, !isDefaultPlaceholderImageURL(path) else { return nil }
    return displayImageURL(
      path,
      baseURL: baseURL, useImageCache: useImageCache,
      bangumiProxyEnabled: bangumiProxyEnabled, bangumiImageDomain: bangumiImageDomain
    )
  }
}

/// 扩展只共享当前会话的访问令牌；不保存登录密码，也不把令牌写入共享 JSON。
nonisolated enum TopShelfCredentials {
  private static func query(_ sessionID: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "MoviePilot.TopShelf",
      kSecAttrAccount as String: sessionID,
      kSecAttrAccessGroup as String: TopShelfSharedStore.appGroupIdentifier,
    ]
  }

  static func save(_ token: String, sessionID: String) -> Bool {
    let query = query(sessionID)
    let data = Data(token.utf8)
    let result = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if result == errSecSuccess { return true }
    guard result == errSecItemNotFound else { return false }
    var addition = query
    addition[kSecValueData as String] = data
    addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(addition as CFDictionary, nil) == errSecSuccess
  }

  static func read(_ sessionID: String) -> String? {
    var query = query(sessionID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(_ sessionID: String) {
    SecItemDelete(query(sessionID) as CFDictionary)
  }
}

nonisolated private struct TopShelfMediaRecord: Decodable {
  let tmdb_id: Int?
  let douban_id: String?
  let bangumi_id: Int?
  let anilist_id: Int?
  let imdb_id: String?
  let tvdb_id: Int?
  let media_source: String?
  let source: String?
  let mediaid_prefix: String?
  let media_id: String?
  let title: String?
  let type: String?
  let year: String?
  let season: Int?
  let poster_path: String?
  let backdrop_path: String?
  let collection_id: Int?
  let overview: String?
  let vote_average: Double?

  var identity: MediaIdentity? {
    MediaIdentifier.resolve(
      mediaIdPrefix: mediaid_prefix, source: media_source ?? source,
      mediaId: media_id, tmdbId: tmdb_id, doubanId: douban_id, bangumiId: bangumi_id,
      anilistId: anilist_id)
  }

  func payload(sessionID: String) -> TopShelfRoutePayload {
    TopShelfRoutePayload(
      sessionID: sessionID, source: media_source ?? source,
      mediaID: media_id, mediaIDPrefix: mediaid_prefix, tmdbID: tmdb_id, doubanID: douban_id,
      bangumiID: bangumi_id, anilistID: anilist_id, imdbID: imdb_id, tvdbID: tvdb_id,
      title: title, type: type, year: year, season: season, posterPath: poster_path,
      collectionID: collection_id, overview: overview, voteAverage: vote_average)
  }
}

nonisolated enum TopShelfRefreshError: Error {
  case invalidResponse
  case invalidURL
}

/// 用与主 App 相同的媒体身份、图片地址和图片下载器准备整批卡片。
nonisolated struct TopShelfRefreshClient: Sendable {
  let store: TopShelfSharedStore
  let transport: URLSession?
  let readToken: @Sendable (String) -> String?

  init(
    store: TopShelfSharedStore, transport: URLSession? = nil,
    readToken: @escaping @Sendable (String) -> String? = TopShelfCredentials.read
  ) {
    self.store = store
    self.transport = transport
    self.readToken = readToken
  }

  func refresh() async throws {
    guard let expected = try store.loadState(), let configuration = expected.refreshConfiguration,
      let selection = expected.selection, expected.activeSessionID == configuration.sessionID,
      let token = readToken(configuration.sessionID)
    else { return }
    let session: URLSession
    if let transport {
      session = transport
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpShouldSetCookies = false
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      session = URLSession(configuration: configuration)
    }
    defer { if transport == nil { session.invalidateAndCancel() } }
    let context = RequestContext(configuration: configuration, token: token, transport: session)
    let params = selection.isSubscriptionShare ? ["page": "1", "count": "30"] : ["page": "1"]
    let raw = try await context.json(path: selection.requestPath, params: params)
    guard let objects = raw as? [[String: Any]] else { throw TopShelfRefreshError.invalidResponse }
    var items: [TopShelfSnapshotItem] = []
    var seen = Set<String>()
    for rawObject in objects {
      if items.count == TopShelfSnapshot.maximumItems { break }
      try Task.checkCancellation()
      guard try store.loadState() == expected else { throw CancellationError() }
      do {
        let object = selection.isSubscriptionShare
          ? Self.subscriptionShareMedia(rawObject) : rawObject
        let media = try JSONDecoder().decode(
          TopShelfMediaRecord.self, from: JSONSerialization.data(withJSONObject: object))
        guard let title = media.title?.trimmingCharacters(in: .whitespacesAndNewlines),
          !title.isEmpty,
          let identifier = media.payload(sessionID: configuration.sessionID).cardIdentifier
        else { continue }
        guard seen.insert(identifier).inserted else { continue }
        var prepared: [String: Any]
        let detail: TopShelfMediaRecord
        if let collectionID = media.collection_id {
          let children = try await context.json(
            path: "tmdb/collection/\(collectionID)", params: ["page": "1", "title": title])
          guard children is [[String: Any]] else { throw TopShelfRefreshError.invalidResponse }
          detail = media
          prepared = ["detail": object, "collectionItems": children]
        } else if let identity = media.identity {
          let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:")
          guard let id = identity.mediaId.addingPercentEncoding(withAllowedCharacters: allowed)
          else { continue }
          let response = try await context.json(
            path: "media/\(id)", params: ["media_source": identity.source, "type_name": media.type])
          guard let object = response as? [String: Any] else {
            throw TopShelfRefreshError.invalidResponse
          }
          detail = try JSONDecoder().decode(
            TopShelfMediaRecord.self, from: JSONSerialization.data(withJSONObject: object))
          guard detail.title != nil || detail.tmdb_id != nil || detail.douban_id != nil else {
            continue
          }
          prepared = ["detail": object]
        } else {
          continue
        }
        let posterURL = configuration.imageURL(detail.poster_path ?? media.poster_path)
        let backdropURL = configuration.imageURL(detail.backdrop_path ?? media.backdrop_path)
        let images: (card: TopShelfImageResource, background: TopShelfImageResource)
        let backgroundURL: URL
        let backgroundIsPoster: Bool
        if let backdropURL {
          do {
            let original = try await context.image(backdropURL)
            images = try await TopShelfImageLoader.prepareImages(from: original.data)
            backgroundURL = backdropURL
            backgroundIsPoster = false
          } catch is CancellationError { throw CancellationError() } catch {
            guard let posterURL else { throw error }
            let original = try await context.image(posterURL)
            images = try await TopShelfImageLoader.prepareImages(from: original.data)
            backgroundURL = posterURL
            backgroundIsPoster = true
          }
        } else {
          guard let posterURL else { continue }
          let original = try await context.image(posterURL)
          images = try await TopShelfImageLoader.prepareImages(from: original.data)
          backgroundURL = posterURL
          backgroundIsPoster = true
        }
        try Task.checkCancellation()
        guard try store.loadState() == expected else { throw CancellationError() }
        let imagePath = try store.writeImage(
          images.card,
          cacheKey: "\(configuration.sessionID)|hdtv-card|\(backgroundURL.absoluteString)")
        let backgroundPath = try store.writeImage(
          images.background,
          cacheKey:
            "\(configuration.sessionID)|detail-\(Int(MediaDetailImageSizing.longEdgePixels))|\(backgroundURL.absoluteString)"
        )
        let detailPath = try store.writeDetailData(
          JSONSerialization.data(withJSONObject: prepared),
          cacheKey: "\(configuration.sessionID)|\(identifier)")
        items.append(
          TopShelfSnapshotItem(
            identifier: identifier, title: title, imageRelativePath: imagePath,
            displayURL: try TopShelfDeepLink.url(
              for: media.payload(sessionID: configuration.sessionID)),
            detailRelativePath: detailPath, backgroundRelativePath: backgroundPath,
            backgroundIsPoster: backgroundIsPoster))
      } catch is CancellationError { throw CancellationError() } catch { continue }
    }
    guard !items.isEmpty else { return }
    try store.publish(
      TopShelfSnapshot(
        sessionID: configuration.sessionID, selection: selection,
        generatedAt: Date(), items: items, refreshConfiguration: configuration), replacing: expected
    )
    let retained = Set(
      store.resourcePaths(for: items) + store.resourcePaths(for: expected.snapshot?.items ?? []))
    try? store.pruneResources(
      keepingRelativePaths: retained, now: Date(),
      gracePeriod: TopShelfSnapshot.imageCleanupGracePeriod)
  }

  /// 分享记录只提供对应媒体身份；分享人的标题和复用入口不进入主屏卡片。
  static func subscriptionShareMedia(_ share: [String: Any]) -> [String: Any] {
    let fields = [
      "tmdbid": "tmdb_id", "doubanid": "douban_id", "bangumiid": "bangumi_id",
      "anilistid": "anilist_id", "type": "type", "year": "year", "season": "season",
      "poster": "poster_path", "backdrop": "backdrop_path", "vote": "vote_average",
      "description": "overview",
    ]
    var media: [String: Any] = [:]
    for (from, to) in fields { media[to] = share[from] }
    media["title"] = (share["name"] as? String) ?? (share["share_title"] as? String)
    if let source = MediaIdentifier.normalizeSource(share["media_source"] as? String), source != "0",
      let id = MediaIdentifier.normalizedString(share["media_id"] as? String),
      Int(id).map({ $0 > 0 }) ?? true
    {
      media["source"] = source
      media["media_id"] = id
    }
    return media
  }

  nonisolated private struct RequestContext {
    let configuration: TopShelfRefreshConfiguration
    let token: String
    let transport: URLSession

    func json(path: String, params: [String: String?]) async throws -> Any {
      guard var relative = URLComponents(string: path), relative.scheme == nil,
        relative.host == nil,
        !path.hasPrefix("//"), !relative.path.split(separator: "/").contains("..")
      else { throw TopShelfRefreshError.invalidURL }
      appendPercentEncodedQueryParams(to: &relative, params: params)
      guard let relativeString = relative.string else { throw TopShelfRefreshError.invalidURL }
      let endpoint =
        relativeString.hasPrefix("/") ? String(relativeString.dropFirst()) : relativeString
      guard let url = URL(string: "\(configuration.baseURL)/api/v1/\(endpoint)") else {
        throw TopShelfRefreshError.invalidURL
      }
      var request = URLRequest(url: url, timeoutInterval: 10)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
      let (data, response) = try await transport.data(
        for: request,
        delegate: TopShelfAPIRedirectDelegate(baseURL: configuration.baseURL, token: token))
      guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode)
      else { throw TopShelfRefreshError.invalidResponse }
      let object = try JSONSerialization.jsonObject(with: data)
      if let envelope = object as? [String: Any] {
        if envelope["success"] as? Bool == false { throw TopShelfRefreshError.invalidResponse }
        if let data = envelope["data"], !(data is NSNull) { return data }
      }
      return object
    }

    func image(_ url: URL) async throws -> TopShelfImageResource {
      let isProtected = isProtectedMoviePilotImageURL(url, baseURL: configuration.baseURL)
      var request = URLRequest(url: url, timeoutInterval: 10)
      request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
      if isProtected { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
      let delegate = TopShelfImageRedirectDelegate(
        startedProtected: isProtected, baseURL: configuration.baseURL,
        token: token, cookieHeader: { _ in nil })
      return try await TopShelfImageLoader.downloadTopShelfImage(
        request: request, transport: transport,
        redirectDelegate: delegate, maximumBytes: 8_000_000,
        maximumPixels: 40_000_000)
    }
  }
}

nonisolated private final class TopShelfAPIRedirectDelegate: NSObject, URLSessionTaskDelegate,
  Sendable
{
  private let baseURL: String
  private let token: String

  init(baseURL: String, token: String) {
    self.baseURL = baseURL
    self.token = token
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let destination = request.url, isMoviePilotAPIURL(destination, baseURL: baseURL) else {
      completionHandler(nil)
      return
    }
    var redirected = request
    redirected.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    redirected.setValue(nil, forHTTPHeaderField: "Cookie")
    completionHandler(redirected)
  }
}
