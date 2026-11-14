import Foundation

/// Emby 请求失败。错误里不带 URL：流地址和请求可能含密钥，不能经错误描述进入日志或提示。
nonisolated enum EmbyClientError: LocalizedError, Equatable {
  /// 连接失败；`transportSecurity` 表示被系统 ATS 拦截（http 域名地址）。
  case unreachable(transportSecurity: Bool)
  /// https 证书不受信任，或加密连接建立失败。
  case certificate
  case http(Int)
  case invalidResponse
  case invalidURL

  var errorDescription: String? {
    switch self {
    case .unreachable(true):
      return "系统不允许连接 http 域名地址，请为 Emby 配置 https 地址或内网 IP"
    case .unreachable(false):
      return "无法连接 Emby"
    case .certificate:
      return "Emby 的 https 证书不受信任或加密连接失败"
    case .http(let status):
      return "Emby 返回错误（HTTP \(status)）"
    case .invalidResponse:
      return "Emby 返回的数据无法识别"
    case .invalidURL:
      return "Emby 地址无效"
    }
  }

  /// 按接下来怎么处理分类，见 `MediaServerError.Reason`。
  var reason: MediaServerError.Reason {
    switch self {
    case .unreachable(true): .transportSecurity
    case .unreachable(false): .unreachable
    case .certificate: .certificate
    case .http(400): .badRequest
    case .http(401): .unauthorized
    case .http(403): .forbidden
    case .http(404): .notFound
    case .http(let status) where (500..<600).contains(status): .serverError(status)
    case .http(let status): .status(status)
    case .invalidResponse: .invalidResponse
    case .invalidURL: .invalidURL
    }
  }
}

/// 直接访问 Emby 的最小客户端，只供 Emby 适配器（`EmbyServerConnection`）使用。地址与密钥来自 MoviePilot 媒体服务器配置，
/// 和 MoviePilot 会话无关；实例创建后不再变化，播放结束时的上报沿用开播时的地址和密钥。
struct EmbyClient {
  let baseURL: URL
  let deviceID: String
  private let apiKey: String
  private let session: URLSession

  init(
    baseURL: URL, apiKey: String, deviceID: String = EmbyClient.installDeviceID,
    session: URLSession = MediaServerHTTP.sharedSession
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.deviceID = deviceID
    self.session = session
  }

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

  /// 条目图片地址。Emby 的图片接口不需要登录，地址里不带密钥；`tag` 是图片版本，换图后地址跟着变，缓存不会用到旧图。
  func imageURL(itemID: String, type: String, tag: String) -> URL? {
    try? url(["Items", itemID, "Images", type], query: ["tag": tag, "maxWidth": "1280", "quality": "90"])
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

  // MARK: - 接口

  static let quickTimeout: TimeInterval = MediaServerHTTP.quickTimeout

  func publicSystemInfo(timeout: TimeInterval = quickTimeout) async throws -> EmbyPublicSystemInfo {
    let data = try await send(url(["System", "Info", "Public"]), timeout: timeout)
    return try await Self.decode(EmbyPublicSystemInfo.self, from: data)
  }

  func users() async throws -> [EmbyUser] {
    let data = try await send(url(["Users"]))
    return try await Self.decode([EmbyUser].self, from: data)
  }

  /// 条目不在这台服务器上（HTTP 404）时返回 nil。400 等其他错误照常抛出，不当作不在。
  func item(id: String, userID: String, timeout: TimeInterval? = nil) async throws -> EmbyItem? {
    do {
      let data = try await send(url(["Users", userID, "Items", id]), timeout: timeout)
      return try await Self.decode(EmbyItem.self, from: data)
    } catch EmbyClientError.http(404) {
      return nil
    }
  }

  /// 按外部编号找条目（`AnyProviderIdEquals`，如 `tmdb.12345`），返回的是这台服务器自己的条目 ID。
  /// 不认识这个参数的服务器会返回不相干的条目，调用方须再核对返回条目的类型和编号。
  /// 详情页起播时找到的条目直接拿去播，所以和单条读取一样带上简介、首播日期，MoviePilot 缺这些时播放界面用它们。
  func items(
    withAnyProviderID keys: [String], type: String?, userID: String, timeout: TimeInterval? = nil
  ) async throws -> [EmbyItem] {
    let data = try await send(
      url(
        ["Users", userID, "Items"],
        query: [
          "Recursive": "true",
          "AnyProviderIdEquals": keys.joined(separator: ","),
          "IncludeItemTypes": type,
          "Fields": "ProviderIds,Overview,PremiereDate",
          "Limit": "20",
        ]),
      timeout: timeout)
    return try await Self.decode(EmbyItemsPage.self, from: data).items
  }

  /// 剧集的全部集（按 Emby 顺序，带用户观看数据、外部编号、文件路径和首播日期），不含缺失的集。
  /// 单集对应（见 `EpisodeMatching.swift`）先看 `ProviderIds.Tmdb`（TMDB 单集 ID），没有时拿路径对整理记录、按季号集号和首播日期对。
  func episodes(seriesID: String, userID: String) async throws -> [EmbyItem] {
    let data = try await send(
      url(
        ["Shows", seriesID, "Episodes"],
        query: ["UserId": userID, "IsMissing": "false", "Fields": "ProviderIds,Path,PremiereDate,Overview"]))
    return try await Self.decode(EmbyItemsPage.self, from: data).items
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
    return try await Self.decode(EmbyPlaybackInfo.self, from: data)
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

  /// 可选的媒体库和各自的文件夹（MoviePilot 叫 Emby 刷新时也按它找媒体库）。
  func mediaFolders() async throws -> [EmbyMediaFolder] {
    let data = try await send(url(["Library", "SelectableMediaFolders"]))
    return try await Self.decode(EmbyMediaFolderList.self, from: data).folders
  }

  /// 各媒体库的文件夹和元数据来源配置（要管理员权限的密钥）。和 MoviePilot 一样读 `Library/VirtualFolders/Query`
  /// （回包的 `Items`）；没有这个接口（404）的旧版 Emby 退回 `Library/VirtualFolders`（顶层数组）。
  func virtualFolders() async throws -> [MediaLibraryProfile] {
    let data: Data
    do {
      data = try await send(url(["Library", "VirtualFolders", "Query"]))
    } catch EmbyClientError.http(404) {
      data = try await send(url(["Library", "VirtualFolders"]))
    }
    return try await Self.decode(EmbyVirtualFolderList.self, from: data).profiles
  }

  /// 重新扫描一个条目（一部剧或一个媒体库）下面的文件，参数同 MoviePilot。Emby 受理后在后台扫描。
  func refreshItem(id: String) async throws {
    _ = try await send(url(["Items", id, "Refresh"], query: ["Recursive": "true"]), method: "POST")
  }

  /// 扫描整个库（所有媒体库）。
  func refreshAllLibraries() async throws {
    _ = try await send(url(["Library", "Refresh"]), method: "POST")
  }

  // MARK: - 传输

  private static let encoder = JSONEncoder()

  /// 证书和加密连接问题：地址是通的，换地址重试不会好，要换证书或改用别的地址。
  private static let certificateErrors: Set<URLError.Code> = [
    .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
    .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
    .clientCertificateRequired,
  ]

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
      if Self.certificateErrors.contains(error.code) { throw EmbyClientError.certificate }
      throw EmbyClientError.unreachable(
        transportSecurity: error.code == .appTransportSecurityRequiresSecureConnection)
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw EmbyClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else { throw EmbyClientError.http(http.statusCode) }
    return data
  }

  /// 解码放到后台：一部长篇剧的全部集可能有上千条，播完每一集都要重读一次，在主线程解析会卡界面。
  @concurrent
  nonisolated private static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw EmbyClientError.invalidResponse
    }
  }
}
