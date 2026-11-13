import Foundation

/// 一台媒体服务器上已连通的地址和选中的用户。播放协调器、播放会话和播放界面只通过它访问服务器，
/// 各类服务器（目前是 Emby）各自实现；新增类型时实现这个协议和 `MediaServerConnector`，并在 `MediaServerAdapters` 登记。
protocol MediaServerConnection: Sendable {
  /// MoviePilot 里这台服务器的配置名称
  var serverName: String { get }
  /// 建立连接时用的配置和 MoviePilot 用户名；任一项变了就不再沿用这个连接。
  var config: MediaServerConnectionConfig { get }
  var preferredUserName: String? { get }
  /// 服务器地址和服务器上的用户：上报队列用它们区分条目。
  var reportingServer: URL { get }
  var userID: String { get }

  /// 条目不在这台服务器上时返回 nil。
  func item(id: String, timeout: TimeInterval?) async throws -> ServerMediaItem?
  /// 按外部编号搜索的候选条目，调用方须再用 `LibraryItemExpectation.accepts` 核对。没有能搜的编号时返回空。
  /// 服务器报错、连不上等照常抛出，不能当作搜不到：调用方据此区分“这台上没有”和“无法确认”。
  func items(matching expected: LibraryItemExpectation) async throws -> [ServerMediaItem]
  /// 剧集的全部集（服务器顺序，带外部编号），不含缺失的集。
  func episodes(seriesID: String) async throws -> [ServerMediaItem]
  /// 读取条目的播放信息并选定版本：`preferredSourceID` 指定时用它，否则取第一个能直连的版本。
  func prepareStream(for item: ServerMediaItem, preferredSourceID: String?) async throws -> PreparedStream
  /// 播放状态上报，让服务器后台显示“正在播放”。
  func report(_ event: PlaybackReportEvent, for stream: PreparedStream, positionSeconds: Double, isPaused: Bool)
    async throws
  /// 写回观看进度（续播点、已看完、最后播放时间）。
  func saveWatchProgress(_ progress: WatchProgress) async throws
  /// 拖动预览图的图集地址（如 Jellyfin trickplay）；服务器没有时为 nil。
  func trickplayTileURL(itemID: String, width: Int, index: Int, mediaSourceID: String) -> URL?
  /// 服务器上的媒体库和各自的文件夹：叫服务器入库时按整理后的路径找该刷新哪个媒体库。
  func libraryFolders() async throws -> [MediaLibraryFolder]
  /// 叫服务器重新扫描，新整理进来的文件不用等它自己发现。只等服务器受理，不等扫描完成。
  func refreshLibrary(_ scope: MediaLibraryRefreshScope) async throws
}

/// 按 MoviePilot 的服务器配置建立连接：探测地址、选用户。
protocol MediaServerConnector: Sendable {
  func connect(
    server: MediaServerConf, config: MediaServerConnectionConfig, candidateBaseURLs: [URL],
    preferredUserName: String?, session: URLSession
  ) async throws -> any MediaServerConnection
}

/// 支持应用内播放的服务器类型（MoviePilot 配置里的 `type`）。新增类型时 `displayNames` 和 `connector(for:)` 一起改。
enum MediaServerAdapters {
  /// 类型（小写）→ 提示文字里的名称，按显示顺序。
  nonisolated private static let displayNames: KeyValuePairs<String, String> = ["emby": "Emby"]

  nonisolated static func supportsInAppPlayback(type: String) -> Bool {
    displayNames.contains { $0.key == type.lowercased() }
  }

  /// 提示文字用：目前支持哪几种服务器，如「Emby」。
  nonisolated static var supportedNames: String {
    displayNames.map(\.value).joined(separator: "、")
  }

  static func connector(for type: String) -> (any MediaServerConnector)? {
    switch type.lowercased() {
    case "emby": EmbyConnector()
    default: nil
    }
  }
}

/// 访问一台媒体服务器失败：哪台、哪一步、什么原因。各适配器把自己的错误转成它；协调器按 `reason` 决定接下来怎么做，
/// 给用户的说明写明服务器和那一步。
nonisolated struct MediaServerError: LocalizedError, Equatable, Sendable {
  enum Operation: Equatable, Sendable {
    case connect, listUsers, search, readItem, readEpisodes, readPlaybackInfo, report, saveProgress
    case readLibraries, refreshLibrary

    var text: String {
      switch self {
      case .connect: "连接"
      case .listUsers: "读取用户"
      case .search: "按外部编号查找"
      case .readItem: "读取条目"
      case .readEpisodes: "读取剧集列表"
      case .readPlaybackInfo: "读取播放信息"
      case .report: "上报播放状态"
      case .saveProgress: "保存观看进度"
      case .readLibraries: "读取媒体库"
      case .refreshLibrary: "刷新媒体库"
      }
    }
  }

  /// 失败的原因，按接下来怎么处理分类。
  enum Reason: Equatable, Sendable {
    /// 连不上（超时、拒绝连接、域名解析失败）：换地址重新探测一次（离开内网等）。
    case unreachable
    /// 系统不允许连接 http 域名地址：不重试，要改地址。
    case transportSecurity
    /// https 证书不受信任，或加密连接建立失败：不重试，要换证书或地址。
    case certificate
    /// HTTP 401，服务器不接受配置里的密钥：重读一次 MoviePilot 的服务器配置（可能刚改过），没变就停。
    case unauthorized
    /// HTTP 403，密钥或所选用户没有权限：停。
    case forbidden
    /// HTTP 404。读条目、读一份剧的集时适配器按“不在”处理，到这里的是其他接口，照常报错。
    case notFound
    /// HTTP 400，服务器不接受这个请求（参数不支持、ID 格式不对等）：停，不当作不在。
    case badRequest
    /// HTTP 5xx（含反向代理的 502/503/504），临时故障：不当作没有，先试已找到的其他副本，都不行请用户稍后重试。
    case serverError(Int)
    /// 其他 HTTP 状态码
    case status(Int)
    /// 回包不是预期的数据（反向代理的登录页、地址不是媒体服务器、缺字段）：停。
    case invalidResponse
    /// 配置的地址拼不成有效的请求地址：停。
    case invalidURL

    /// 影响整台服务器、换一份副本也没用的失败：读一部剧的集时不当作“这一份没读到”接着试别的，直接交给 `withConnection` 处理。
    var isServerWide: Bool {
      switch self {
      case .unreachable, .transportSecurity, .certificate, .unauthorized, .invalidURL: true
      case .forbidden, .notFound, .badRequest, .serverError, .status, .invalidResponse: false
      }
    }

    var text: String {
      switch self {
      case .unreachable: "连不上服务器"
      case .transportSecurity: "系统不允许连接 http 域名地址，请为媒体服务器配置 https 地址或内网 IP"
      case .certificate: "https 证书不受信任或加密连接失败，请换受信任的证书或改用内网地址"
      case .unauthorized: "不接受 MoviePilot 中配置的 API Key，请检查媒体服务器设置里的密钥"
      case .forbidden: "没有权限（HTTP 403），请检查 API Key 和所选用户的权限"
      case .notFound: "找不到（HTTP 404）"
      case .badRequest: "服务器不接受这个请求（HTTP 400）"
      case .serverError(let status): "服务器出错（HTTP \(status)），请稍后重试"
      case .status(let status): "服务器返回 HTTP \(status)"
      case .invalidResponse: "返回的不是媒体服务器的数据，请检查地址或反向代理设置"
      case .invalidURL: "地址无效，请检查 MoviePilot 中的媒体服务器地址"
      }
    }
  }

  let server: String
  let operation: Operation
  let reason: Reason
  /// 证书错误时这一轮连接使用的候选地址，仅用于判断新配置能否恢复连接。
  var certificateOrigins: Set<MediaServerBaseURL.Origin> = []

  var errorDescription: String? { "媒体服务器“\(server)”\(operation.text)失败：\(reason.text)" }
}

/// 选定版本、可以交给播放器的流。
struct PreparedStream: Sendable {
  let item: ServerMediaItem
  let source: ServerMediaSource
  /// 服务器返回的全部版本，供播放界面的“版本”选择。
  let sources: [ServerMediaSource]
  /// 服务器分配的播放会话标识（Emby 的 `PlaySessionId`），上报时带上。
  let playSessionID: String?
  /// 直连原文件的地址，可能含密钥，不得写入日志。
  let streamURL: URL
}

/// 播放状态上报。
enum PlaybackReportEvent: Equatable, Sendable {
  case start
  case progress(Progress)
  case stopped

  enum Progress: Equatable, Sendable {
    /// 周期进度
    case timeUpdate
    case pause
    case unpause
  }
}

/// 要写回服务器的观看进度。
struct WatchProgress: Sendable {
  let itemID: String
  let completed: Bool
  let positionSeconds: Double
  let playedAt: Date
}
