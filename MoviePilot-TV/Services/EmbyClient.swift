import Foundation

/// Emby 请求失败。错误里不带 URL：流地址和请求可能含密钥，不能经错误描述进入日志或提示。
enum EmbyClientError: LocalizedError, Equatable {
  /// 连接失败；`transportSecurity` 表示被系统 ATS 拦截（http 域名地址）。
  case unreachable(transportSecurity: Bool)
  case http(Int)
  case invalidResponse
  case invalidURL

  var errorDescription: String? {
    switch self {
    case .unreachable(true):
      return "系统不允许连接 http 域名地址，请为 Emby 配置 https 地址或内网 IP"
    case .unreachable(false):
      return "无法连接 Emby"
    case .http(let status):
      return "Emby 返回错误（HTTP \(status)）"
    case .invalidResponse:
      return "Emby 返回的数据无法识别"
    case .invalidURL:
      return "Emby 地址无效"
    }
  }
}

/// 直接访问 Emby 的最小客户端。地址与密钥来自 MoviePilot 媒体服务器配置，和 MoviePilot 会话无关；
/// 实例创建后不再变化，播放结束时的上报沿用开播时的地址和密钥。
struct EmbyClient {
  let baseURL: URL
  let deviceID: String
  private let apiKey: String
  private let session: URLSession

  init(baseURL: URL, apiKey: String, deviceID: String = EmbyClient.installDeviceID, session: URLSession = EmbyClient.sharedSession) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.deviceID = deviceID
    self.session = session
  }

  static let sharedSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = 15
    return URLSession(configuration: configuration)
  }()

  private static let deviceIDKey = "embyDeviceID"

  /// 每次安装固定的设备 ID，让 Emby 把同一台 Apple TV 识别为同一个设备。
  static var installDeviceID: String {
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty { return existing }
    let created = UUID().uuidString
    defaults.set(created, forKey: deviceIDKey)
    return created
  }

  // MARK: - 地址

  /// 在根地址（含反代前缀）后追加路径段；每段按不透明 ID 编码一次。
  func url(_ segments: [String], query: [String: String?] = [:]) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw EmbyClientError.invalidURL
    }
    var path = components.percentEncodedPath
    while path.hasSuffix("/") { path.removeLast() }
    for segment in segments {
      guard let encoded = encodeMediaIDPathSegment(segment), !encoded.isEmpty else {
        throw EmbyClientError.invalidURL
      }
      path += "/" + encoded
    }
    components.percentEncodedPath = path
    components.percentEncodedQuery = nil
    appendPercentEncodedQueryParams(to: &components, params: query)
    guard let url = components.url else { throw EmbyClientError.invalidURL }
    return url
  }

  /// 直接播放原文件的流地址。密钥放在 query 里，此地址不得写入日志。
  func directStreamURL(
    itemID: String, selection: EmbyDirectPlay.Selection, playSessionID: String?
  ) throws -> URL {
    try url(
      ["Videos", itemID, "stream.\(selection.fileExtension)"],
      query: [
        "Static": "true",
        "MediaSourceId": selection.source.id,
        "PlaySessionId": playSessionID,
        "DeviceId": deviceID,
        "api_key": apiKey,
      ])
  }

  /// 日志里去掉地址和密钥：mpv 等组件的错误信息可能带出含密钥的流地址。
  nonisolated static func redactedForLogging(_ text: String) -> String {
    text
      .replacingOccurrences(
        of: #"(?i)\b(?:https?|rtsp|rtmp|ftp|file)://[^\s]+"#, with: "<URL>", options: .regularExpression)
      .replacingOccurrences(
        of: #"api_key=[^&\s"']*"#, with: "api_key=<redacted>", options: .regularExpression)
  }

  // MARK: - 接口

  /// 探测地址、用缓存连接发出的第一个请求所用的超时：地址失效时尽快改用其他地址，不等普通请求的 15 秒。
  static let quickTimeout: TimeInterval = 3

  func publicSystemInfo(timeout: TimeInterval = quickTimeout) async throws -> EmbyPublicSystemInfo {
    let data = try await send(url(["System", "Info", "Public"]), timeout: timeout)
    return try decode(EmbyPublicSystemInfo.self, from: data)
  }

  func users() async throws -> [EmbyUser] {
    let data = try await send(url(["Users"]))
    return try decode([EmbyUser].self, from: data)
  }

  /// 条目不在这台服务器上时返回 nil。
  func item(id: String, userID: String, timeout: TimeInterval? = nil) async throws -> EmbyItem? {
    do {
      let data = try await send(url(["Users", userID, "Items", id]), timeout: timeout)
      return try decode(EmbyItem.self, from: data)
    } catch EmbyClientError.http(let status) where status == 400 || status == 404 {
      return nil
    }
  }

  /// 剧集的全部集（按 Emby 顺序，带用户观看数据），不含缺失的集。
  func episodes(seriesID: String, userID: String) async throws -> [EmbyItem] {
    let data = try await send(
      url(
        ["Shows", seriesID, "Episodes"],
        query: ["UserId": userID, "IsMissing": "false"]))
    return try decode(EmbyItemsPage.self, from: data).items
  }

  /// 声明任何视频都可以直接播放（mpv 直连原文件），并关闭重新封装和转码，
  /// Emby 不会为此启动转码任务。
  func playbackInfo(itemID: String, userID: String) async throws -> EmbyPlaybackInfo {
    let bitrate = "200000000"
    let target = try url(
      ["Items", itemID, "PlaybackInfo"],
      query: [
        "UserId": userID,
        "IsPlayback": "true",
        "AutoOpenLiveStream": "false",
        "MaxStreamingBitrate": bitrate,
        "EnableDirectPlay": "true",
        "EnableDirectStream": "false",
        "EnableTranscoding": "false",
      ])
    let profile: JSONValue = .object([
      "DeviceProfile": .object([
        "Name": .string("MoviePilot-TV"),
        "MaxStreamingBitrate": .int(200_000_000),
        "MaxStaticBitrate": .int(200_000_000),
        "DirectPlayProfiles": .array([.object(["Type": .string("Video")])]),
        "TranscodingProfiles": .array([]),
        "ContainerProfiles": .array([]),
        "CodecProfiles": .array([]),
        "SubtitleProfiles": .array([
          .object(["Format": .string("srt"), "Method": .string("Embed")]),
          .object(["Format": .string("ass"), "Method": .string("Embed")]),
          .object(["Format": .string("ssa"), "Method": .string("Embed")]),
          .object(["Format": .string("pgssub"), "Method": .string("Embed")]),
          .object(["Format": .string("mov_text"), "Method": .string("Embed")]),
        ]),
      ])
    ])
    let data = try await send(target, method: "POST", body: profile)
    return try decode(EmbyPlaybackInfo.self, from: data)
  }

  enum PlaybackEvent {
    case start, progress, stopped

    var pathSegments: [String] {
      switch self {
      case .start: return ["Sessions", "Playing"]
      case .progress: return ["Sessions", "Playing", "Progress"]
      case .stopped: return ["Sessions", "Playing", "Stopped"]
      }
    }
  }

  /// 播放状态上报，让 Emby 后台显示“正在播放”。
  func report(_ event: PlaybackEvent, body: [String: JSONValue]) async throws {
    _ = try await send(url(event.pathSegments), method: "POST", body: .object(body))
  }

  /// 直接写入用户观看数据（续播点、已看完）。系统密钥上报的播放状态可能不归属任何用户，续播点以此为准。
  func updateUserData(userID: String, itemID: String, userData: [String: JSONValue]) async throws {
    _ = try await send(
      url(["Users", userID, "Items", itemID, "UserData"]), method: "POST", body: .object(userData))
  }

  // MARK: - 传输

  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  private static let clientVersion = AppVersionInfo.currentAppVersion()
    .trimmingCharacters(in: CharacterSet(charactersIn: "v"))

  private var authorizationHeader: String {
    "MediaBrowser Client=\"MoviePilot-TV\", Device=\"Apple TV\", DeviceId=\"\(deviceID)\", Version=\"\(Self.clientVersion)\", Token=\"\(apiKey)\""
  }

  private func send(
    _ url: URL, method: String = "GET", body: JSONValue? = nil, timeout: TimeInterval? = nil
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(apiKey, forHTTPHeaderField: "X-Emby-Token")
    request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
    if let timeout { request.timeoutInterval = timeout }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try Self.encoder.encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw EmbyClientError.unreachable(
        transportSecurity: error.code == .appTransportSecurityRequiresSecureConnection)
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw EmbyClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw EmbyClientError.http(http.statusCode) }
    return data
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try Self.decoder.decode(type, from: data)
    } catch {
      throw EmbyClientError.invalidResponse
    }
  }
}
