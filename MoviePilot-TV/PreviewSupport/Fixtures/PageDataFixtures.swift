#if DEBUG
import Foundation

/// 首页 / 推荐 / 探索 / 状态 / 下载 / 整理 等页面共用的接口 fixture。
///
/// 每个方法内部按 `UIPreviewBehaviorKey` 读取场景行为：
/// `.empty` 返回空数据、`.failure` 抛错、`.hang` 永不返回、`.delayed` 延迟返回。
extension UIPreviewFixtures {
  // MARK: - 首页

  static func homeMediaServers() async throws -> [MediaServerConf] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.homeMediaServers)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.homeMediaServers) {
      return []
    }
    return [
      MediaServerConf(name: "Emby · 客厅", type: "emby", enabled: FlexibleBool(true)),
      MediaServerConf(name: "Jellyfin · 书房", type: "jellyfin", enabled: FlexibleBool(true)),
      MediaServerConf(name: "Plex · 备份", type: "plex", enabled: FlexibleBool(false)),
    ]
  }

  static func homeMediaServerLatest(server: String) async throws -> [MediaServerPlayItem] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.homeMediaServerLatest)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.homeMediaServerLatest) {
      return []
    }
    return [
      MediaServerPlayItem(
        id: "\(server)-1",
        title: "边境信号",
        subtitle: "2026 · S01E01",
        type: "电视剧",
        image: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        link: "emby://items/1",
        server_type: .emby
      ),
      MediaServerPlayItem(
        id: "\(server)-2",
        title: "荒原长路",
        subtitle: "2025",
        type: "电影",
        image: nil,
        link: "emby://items/2",
        server_type: .emby
      ),
      MediaServerPlayItem(
        id: "\(server)-3",
        title: "星门回声",
        subtitle: "2026 · S02E04",
        type: "电视剧",
        image: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        link: "emby://items/3",
        server_type: .emby
      ),
    ]
  }

  static func homeSubscriptions() async throws -> [Subscribe] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.homeSubscriptions)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.homeSubscriptions) {
      return []
    }
    return [
      subscribe(id: 46_101, name: "边境信号", type: "电视剧", state: "R", lack: 3),
      subscribe(id: 46_102, name: "荒原长路", type: "电影", state: "R", lack: nil),
      subscribe(id: 46_103, name: "星门回声", type: "电视剧", state: "P", lack: 1),
      subscribe(id: 46_104, name: "轨道边界", type: "电视剧", state: "S", lack: 12),
    ]
  }

  // MARK: - 推荐

  static func recommendSources() async throws -> [RecommendSourceDescriptor] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.recommendSources)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.recommendSources) {
      return []
    }
    return [
      RecommendSourceDescriptor(name: "更多推荐", api_path: "recommend/more", type: "media")
    ]
  }

  static func recommendMedia(path: String, page: Int) async throws -> [MediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.recommendMedia)
    if page > 1 {
      try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.recommendMore)
      if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.recommendMore) {
        return []
      }
    }
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.recommendMedia) {
      return []
    }
    let base = previewMediaGrid.withoutShares()
    if page <= 1 { return base }
    return [
      mediaTitled(id: 81_001, title: "加载更多 · 星门回声"),
      mediaTitled(id: 81_002, title: "加载更多 · 轨道边界"),
      mediaTitled(id: 81_003, title: "加载更多 · 深空信号"),
    ]
  }

  // MARK: - 探索

  static func discoverSources() async throws -> [DiscoverSourceDescriptor] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.discoverSources)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.discoverSources) {
      return []
    }
    return [
      DiscoverSourceDescriptor(
        name: "豆瓣热榜",
        mediaid_prefix: "douban_hot",
        api_path: "recommend/douban_hot",
        filter_params: [:],
        filter_ui: [],
        depends: nil
      )
    ]
  }

  static func subscriptionShares(path: String, page: Int) async throws -> [SubscribeShare] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.subscriptionShares)
    if page > 1 {
      try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.subscriptionSharesMore)
      if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.subscriptionSharesMore) {
        return []
      }
    }
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.subscriptionShares) {
      return []
    }
    return [
      subscribeShare(id: 47_101, title: "边境信号 · 高质量订阅分享"),
      subscribeShare(id: 47_102, title: "荒原长路 · 4K 收藏"),
      subscribeShare(id: 47_103, title: "星门回声 · 全季"),
    ]
  }

  // MARK: - 状态 / 仪表盘

  static func dashboardStatistic() async throws -> Statistic {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.statusStatistic)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.statusStatistic) {
      return decode(Statistic.self, "{}")
    }
    return UIPreviewFixtures.statisticValue()
  }

  static func dashboardStorage() async throws -> Storage {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.statusStorage)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.statusStorage) {
      return Storage(total_storage: 0, used_storage: 0)
    }
    return Storage(total_storage: 4_000_000_000_000, used_storage: 2_700_000_000_000)
  }

  static func dashboardDownloader() async throws -> DownloaderInfo {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.statusDownloader)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.statusDownloader) {
      return decode(DownloaderInfo.self, "{}")
    }
    return UIPreviewFixtures.downloaderInfoValue()
  }

  static func statisticValue() -> Statistic {
    decode(
      Statistic.self,
      #"{"movie_count":128,"tv_count":46,"episode_count":1284}"#
    )
  }

  static func downloaderInfoValue() -> DownloaderInfo {
    decode(
      DownloaderInfo.self,
      #"{"download_speed":18400000,"upload_speed":2100000,"download_size":860000000000,"upload_size":420000000000,"free_space":1300000000000}"#
    )
  }

  // MARK: - 下载任务

  static func downloadClients() async throws -> [DownloaderConf] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.downloadClients)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.downloadClients) {
      return []
    }
    return downloaders
  }

  static func downloadingItems(clientName: String) async throws -> [DownloadingInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.downloadingItems)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.downloadingItems) {
      return []
    }
    return downloads
  }

  // MARK: - 整理历史

  /// 整理历史列表。除分页外还支持三个预览专用变体：
  /// - `transfer.historyLongList`：生成 24 条记录，用来触发第二页；
  /// - `transfer.historyOnlyFailed`：只保留失败记录，隔离失败原因样式；
  /// - `title`：按标题过滤，用来展示关键词搜索后的空结果。
  static func transferHistory(page: Int, count: Int, title: String?) async throws
    -> TransferHistoryResponse
  {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.transferHistory)
    if page > 1 {
      try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.transferHistoryMore)
    }
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.transferHistory) {
      return TransferHistoryResponse(list: [], total: 0)
    }

    var all: [TransferHistory]
    if UIPreviewBackend.shared.context(UIPreviewContextKey.transferHistoryLongList) == "1" {
      all = (1...24).map { index in
        transfer(
          id: 44_100 + index,
          title: "预览整理记录 \(String(format: "%02d", index))",
          status: index % 4 != 0,
          mode: index.isMultiple(of: 2) ? "copy" : "softlink"
        )
      }
    } else {
      all = transferHistoryItems
    }
    if UIPreviewBackend.shared.context(UIPreviewContextKey.transferHistoryOnlyFailed) == "1" {
      all = all.filter { !$0.status.value }
    }

    let keyword = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyword.isEmpty {
      all = all.filter {
        ($0.title ?? "").localizedCaseInsensitiveContains(keyword)
      }
    }

    let pageSize = max(count, 1)
    let start = max(page - 1, 0) * pageSize
    guard start < all.count else {
      return TransferHistoryResponse(list: [], total: all.count)
    }
    let end = min(start + pageSize, all.count)
    return TransferHistoryResponse(list: Array(all[start..<end]), total: all.count)
  }

  static func transferStorages() async throws -> [StorageConf] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.transferStorages)
    return storages
  }

  // MARK: - 搜索站点

  static func searchSites() async throws -> [Site] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchSites)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchSites) {
      return []
    }
    return sites
  }

  // MARK: - 共享辅助

  /// 分页器失败态演示：只经过 `component.paginator` 行为门，由调用方决定返回数据还是抛错。
  static func componentPaginatorMedia() async throws -> [MediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.componentPaginator)
    return previewMediaGrid
  }

  static func mediaTitled(id: Int, title: String) -> MediaInfo {
    baseTVMedia(id: id, title: title)
  }
}

private extension [MediaInfo] {
  func withoutShares() -> [MediaInfo] {
    filter { $0.subscribeShare == nil }
  }
}

extension UIPreviewBehaviorKey {
  static let homeMediaServers = "home.mediaServers"
  static let homeMediaServerLatest = "home.mediaServerLatest"
  static let homeSubscriptions = "home.subscriptions"
  static let recommendSources = "recommend.sources"
  static let recommendMedia = "recommend.media"
  static let recommendMore = "recommend.more"
  static let discoverSources = "discover.sources"
  static let subscriptionShares = "discover.subscriptionShares"
  static let subscriptionSharesMore = "discover.subscriptionSharesMore"
  static let statusStatistic = "status.statistic"
  static let statusStorage = "status.storage"
  static let statusDownloader = "status.downloader"
  static let downloadClients = "download.clients"
  static let downloadingItems = "download.items"
  static let transferHistory = "transfer.history"
  static let transferHistoryMore = "transfer.historyMore"
  static let transferStorages = "transfer.storages"
  static let searchSites = "search.sites"
  /// 核心组件区「Paginator 连续失败」演示使用的独立接口门。
  static let componentPaginator = "component.paginator"
}

extension UIPreviewContextKey {
  /// 为 "1" 时整理历史返回 24 条记录，用于触发第二页加载。
  static let transferHistoryLongList = "transfer.historyLongList"
  /// 为 "1" 时整理历史只返回失败记录，用于隔离失败原因样式。
  static let transferHistoryOnlyFailed = "transfer.historyOnlyFailed"
}
#endif
