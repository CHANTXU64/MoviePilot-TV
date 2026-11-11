#if DEBUG
import Foundation

/// 设置 / 登录 / 日志域的行为键。
///
/// 已有的设置相关接口（`fetchSettings`、`fetchSites`、`fetchDownloadClients`、`fetchStorages`）
/// 分别由 SharedFixtures / PageDataFixtures 覆盖，这里只补充当前还没有 fixture 的接口。
extension UIPreviewBehaviorKey {
  /// `fetchAllSites()`（权威站点域 `/site/`）。
  static let settingsSites = "settings.sites"
  /// `fetchCustomFilterRules()`（自定义过滤规则）。
  static let settingsCustomRules = "settings.rules"
  /// `fetchSystemEnv()`（系统环境 / 后端版本）。
  static let settingsEnv = "settings.env"
  /// `fetchMediaSources()`（聚合搜索来源目录）。
  static let settingsMediaSources = "settings.mediaSources"
  /// 日志页数据源。日志读的是本地 `PersistentLogStore`，不是 APIService 接口。
  static let logRecords = "log.records"
}

/// 场景附加参数键（对应 `UIPreviewEnvironment.context`）。
enum UIPreviewContextKey {
  /// 为 "1" 时，登录页进入场景后自动发起一次登录，用于展示提交中 / 失败态。
  static let loginAutoSubmit = "login.autoSubmit"
  /// 为 "1" 时，日志 fixture 返回大量记录，用于验证滚动。
  static let logLongList = "log.longList"
}

extension UIPreviewFixtures {
  // MARK: - 设置：站点

  /// 全部站点（含未启用），对应 `/site/` 权威域。
  static func allSites() async throws -> [Site] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.settingsSites)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.settingsSites) {
      return []
    }
    return sites
  }

  // MARK: - 设置：过滤规则

  /// 自定义过滤规则（设置页硬过滤 / 软过滤共用的列表）。
  static func customFilterRules() async throws -> [CustomRule] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.settingsCustomRules)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.settingsCustomRules) {
      return []
    }
    return customRules
  }

  // MARK: - 设置：系统环境 / 媒体来源

  /// 系统环境。当前模型只有版本号；空数据返回 nil 版本，由设置页回退到公开设置里的版本。
  static func systemEnv() async throws -> SystemEnv {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.settingsEnv)
    let version =
      UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.settingsEnv)
      ? nil : UIPreviewBackend.shared.environment.backendVersion
    return SystemEnv(VERSION: version)
  }

  /// `/media/source` 的媒体来源目录。模型在目录为空或请求失败时回退到内置来源。
  static func mediaSourceCatalog() async throws -> [MediaSourceInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.settingsMediaSources)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.settingsMediaSources) {
      return []
    }
    return [
      MediaSourceInfo(name: "TMDB", media_source: "themoviedb", media_types: ["电影", "电视剧"]),
      MediaSourceInfo(name: "豆瓣", media_source: "douban", media_types: ["电影", "电视剧"]),
      MediaSourceInfo(name: "Bangumi", media_source: "bangumi", media_types: ["电视剧"]),
      MediaSourceInfo(name: "AniList", media_source: "anilist", media_types: ["电视剧"]),
      MediaSourceInfo(name: "自建影视源", media_source: "custom_plugin", media_types: ["电影"]),
    ]
  }

  // MARK: - 日志页
  //
  // 日志页读的是本机 `PersistentLogStore`，不经过 APIService；
  // 因此没有对应的网络钩子，由 `LogViewerViewModel.reloadRecords()` 的 DEBUG 分支取这里的数据。

  /// 按当前 `LogQuery`（级别 / 时间范围）过滤后的日志。
  /// 失败行为映射为「日志读取失败」，与真实读取失败时页面的展示一致。
  static func logQueryResult(query: LogQuery) async -> LogQueryResult {
    do {
      try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.logRecords)
    } catch {
      return LogQueryResult(records: [], isTruncated: false, storageIssues: [.readFailed])
    }

    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.logRecords) {
      return LogQueryResult(records: [], isTruncated: false)
    }

    let now = Date()
    let longList = UIPreviewBackend.shared.context(UIPreviewContextKey.logLongList) == "1"
    let matching = logRecords(now: now, longList: longList)
      .filter { query.matches($0, now: now, retention: PersistentLogStore.retention) }
      .sorted { $0.timestamp > $1.timestamp }
    let records = Array(matching.prefix(max(0, query.limit)))
    return LogQueryResult(records: records, isTruncated: matching.count > records.count)
  }

  /// 日志 fixture。时间都相对当前时间生成，默认的「今天 / WARN」筛选也能看到记录。
  private static func logRecords(now: Date, longList: Bool) -> [LogRecord] {
    let samples: [(Logger.Level, Double, String, [String: String]?)] = [
      (.error, 1, "下载任务提交失败：qb-main 连接超时", ["downloader": "qb-main", "hash": "hash-1"]),
      (.warning, 4, "站点 AlphaPT 登录失败，已从候选站点中跳过", ["site": "AlphaPT"]),
      (.warning, 9, "整理任务「海岸档案 S02E04」未匹配到目录配置", ["task": "transfer-44003"]),
      (.error, 16, "读取 /system/env 失败：The request timed out.", ["endpoint": "/system/env"]),
      (.info, 30, "已加载 3 个站点，其中 2 个启用", nil),
      (.info, 60, "订阅「荒原长路」第 12 集已入库", ["tmdb_id": "44002"]),
      (.debug, 180, "缓存命中：/media/source", ["cache": "mediaSourceCatalogCache"]),
      (.debug, 600, "图片预载完成：8cdWjvZQUExUUTzyp4t6EDMubfO", ["size": "w500"]),
    ]

    if longList {
      let levels: [Logger.Level] = [.warning, .error]
      return (0..<36).map { index in
        let level = levels[index % levels.count]
        let message =
          level == .error
          ? "第 \(index + 1) 条模拟错误：下载器返回 503，已重试 \(index % 3) 次"
          : "第 \(index + 1) 条模拟警告：站点响应较慢（\(index + 1)20 ms）"
        return LogRecord(
          id: previewLogID(index + 100),
          timestamp: previewTimestamp(secondsAgo: Double(index) * 90 + 30, now: now),
          level: level,
          message: message,
          fileName: "APIService.swift",
          function: "makeRequest(endpoint:)",
          line: UInt(1200 + index),
          metadata: ["index": "\(index + 1)"]
        )
      }
    }

    return samples.enumerated().map { index, sample in
      LogRecord(
        id: previewLogID(index),
        timestamp: previewTimestamp(secondsAgo: sample.1 * 60, now: now),
        level: sample.0,
        message: sample.2,
        fileName: "UIPreviewLogFixture.swift",
        function: "logRecords(now:longList:)",
        line: UInt(200 + index),
        metadata: sample.3
      )
    }
  }

  /// 相对当前时间生成，并夹到今天 0 点之后，避免刚过零点时默认的「今天」筛选把所有记录滤掉。
  private static func previewTimestamp(secondsAgo: Double, now: Date) -> Date {
    let startOfDay = Calendar.current.startOfDay(for: now)
    let candidate = now.addingTimeInterval(-secondsAgo)
    return max(candidate, startOfDay.addingTimeInterval(1))
  }

  private static func previewLogID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", index))!
  }
}
#endif
