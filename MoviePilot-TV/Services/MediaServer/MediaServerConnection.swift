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
  /// 按外部编号搜索的候选条目，调用方须再用 `LibraryItemExpectation.accepts` 核对。
  /// 服务器拒绝这类搜索或不支持时返回空，连不上等错误照常抛出。
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
}

/// 按 MoviePilot 的服务器配置建立连接：探测地址、选用户。
protocol MediaServerConnector: Sendable {
  func connect(
    server: MediaServerConf, config: MediaServerConnectionConfig, preferredUserName: String?, session: URLSession
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

/// 连接层的地址不通错误。协调器据此判断要不要重新探测地址（比如离开了内网）。
protocol MediaServerReachabilityError: Error {
  var isUnreachable: Bool { get }
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
