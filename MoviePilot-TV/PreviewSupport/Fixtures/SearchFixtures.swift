#if DEBUG
import Foundation

/// 「搜索 + 资源搜索结果」域的预览 fixture。
///
/// 只构造 Model 值或驱动页面使用的回调，不发真实请求。APIService 的对应方法在
/// `-uiPreviewMode` 下调用这里，页面本身仍走真实的 ViewModel/分页/筛选逻辑。
extension UIPreviewFixtures {

  // MARK: - 聚合搜索

  /// 聚合搜索的媒体结果。只为包含「边境信号」的预览关键词返回数据，
  /// 避免详情页里按标题识别 TMDB ID 时误拿到一批固定结果。
  static func searchMedia(
    query: String,
    page: Int,
    source: MediaSearchSource?
  ) async throws -> [MediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchMedia)
    // SharedMediaFetcher 首屏会并发取第 1、2 页；第 3 页起才是真正的「加载更多」。
    if page > 2 {
      try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchMediaMore)
      if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchMediaMore) {
        return []
      }
    }
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchMedia) {
      return []
    }

    let matched = mediaSearchResults.filter { media in
      guard let title = media.title else { return false }
      return title.localizedCaseInsensitiveContains(query)
    }
    let start = (page - 1) * 10
    guard start < matched.count else { return [] }
    return Array(matched[start..<min(start + 10, matched.count)])
  }

  static func searchCollection(
    query: String,
    page: Int,
    source: MediaSearchSource?
  ) async throws -> [MediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchCollection)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchCollection) {
      return []
    }
    guard page == 1 else { return [] }
    return [
      collectionMedia(id: 94_001, title: "边境信号系列"),
      collectionMedia(id: 94_002, title: "边境信号 · 幕后特辑合集"),
      collectionMedia(id: 94_003, title: "边境信号 · 导演剪辑合集"),
    ]
  }

  static func searchPerson(
    query: String,
    page: Int,
    source: MediaSearchSource?
  ) async throws -> [Person] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchPerson)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchPerson) {
      return []
    }
    guard page == 1 else { return [] }
    return [
      person(id: 95_001, name: "林原真", character: "导演"),
      person(id: 95_002, name: "高桥遥", character: "领航员"),
      person(id: 95_003, name: "陈述", character: "工程师"),
      person(id: 95_004, name: "雨宫澄", character: "声效设计"),
    ]
  }

  static func searchSubscriptionShares(
    query: String,
    page: Int
  ) async throws -> [SubscribeShare] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchSubscriptionShares)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchSubscriptionShares) {
      return []
    }
    guard page == 1 else { return [] }
    return [
      subscribeShare(id: 96_001, title: "边境信号 · 高质量订阅分享"),
      subscribeShare(id: 96_002, title: "边境信号 第二季 · 订阅分享"),
    ]
  }

  /// 手动媒体搜索对话框（添加下载 / 字幕等复用）。
  static func searchManualMedia(
    title: String,
    source: MediaSearchSource
  ) async throws -> [MediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchManualMedia)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchManualMedia) {
      return []
    }
    switch source {
    case .douban:
      return [externalSourceMedia(id: 97_101, title: "边境信号（豆瓣）")]
    case .bangumi, .anilist:
      return [baseTVMedia(id: 97_201, title: "边境信号（番剧）")]
    default:
      return [
        baseTVMedia(id: 97_001, title: "边境信号"),
        movieMedia(id: 97_002, title: "边境信号：归途"),
      ]
    }
  }

  /// 影视来源目录；目录为空时页面保留内置来源。
  static func searchMediaSources() async throws -> [MediaSourceInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchMediaSources)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchMediaSources) {
      return []
    }
    return [
      MediaSourceInfo(name: "TMDB", media_source: "themoviedb", media_types: ["电影", "电视剧"]),
      MediaSourceInfo(name: "豆瓣", media_source: "douban", media_types: ["电影", "电视剧"]),
      MediaSourceInfo(name: "Bangumi", media_source: "bangumi", media_types: ["电视剧"]),
    ]
  }

  // MARK: - 站点与筛选配置

  /// 权威站点域（/site/，需 manage 权限）。`fetchSites` 已由 PageDataFixtures 提供。
  static func searchAllSites() async throws -> [Site] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchAllSites)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchAllSites) {
      return []
    }
    return sites
  }

  static func searchDirectories() async throws -> [TransferDirectoryConf] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchDirectories)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchDirectories) {
      return []
    }
    return directories
  }

  static func searchFilterRuleGroups() async throws -> [FilterRuleGroup] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchFilterRuleGroups)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchFilterRuleGroups) {
      return []
    }
    return [
      FilterRuleGroup(name: "默认规则"),
      FilterRuleGroup(name: "动画规则"),
    ]
  }

  static func searchCustomFilterRules() async throws -> [CustomRule] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchCustomFilterRules)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchCustomFilterRules) {
      return []
    }
    return customRules
  }

  // MARK: - 资源搜索（分页 SSE 协议）

  /// 模拟 `readResourceSearchPage` 的逐页 SSE：先发进度事件，再发一批 `replace_batch`
  /// 最终结果。调用方（ResourceSearchSession）在事务完整后会抛出 `PageFinished`
  /// 结束连接，所以这里不吞掉 `receive` 的错误。
  ///
  /// - Parameter source: nil 表示首屏；非 nil 表示「继续搜索」轮到某个来源。
  static func resourceSearchPage(
    query: ResourceSearchQuery,
    source: String?,
    page: Int,
    maximumEventBytes: @MainActor @Sendable () throws -> Int,
    receive: @MainActor @Sendable (SearchStreamEvent, Int) async throws -> Void
  ) async throws {
    let backend = UIPreviewBackend.shared
    try await backend.gate(UIPreviewBehaviorKey.resourcePage)

    let isInitial = source == nil
    if !isInitial {
      try await backend.gate(UIPreviewBehaviorKey.resourcePageMore)
    }

    if backend.isEmpty(for: UIPreviewBehaviorKey.resourcePage)
      || (!isInitial && backend.isEmpty(for: UIPreviewBehaviorKey.resourcePageMore))
    {
      let finishedSources = isInitial
        ? resourceSourceFacts(page: page, canContinue: false)
        : [resourceSourceFact(source: source, page: page, canContinue: false)]
      try await sendResourceEvent(
        resourceBatchEvent(items: [], sources: finishedSources),
        receive: receive
      )
      return
    }

    let name = isInitial ? "全部站点" : resourceSiteName(for: source)
    try await sendResourceEvent(
      resourceProgressEvent(text: "正在搜索 \(name)…", value: 0.28),
      receive: receive
    )
    try await sendResourceEvent(
      resourceProgressEvent(text: "正在过滤 \(name) 的结果…", value: 0.72),
      receive: receive
    )

    if isInitial {
      try await sendResourceEvent(
        resourceBatchEvent(
          items: resourceSearchContexts,
          sources: resourceSourceFacts(page: page, canContinue: true)
        ),
        receive: receive
      )
    } else {
      let items = resourceContinuationItems(source: source, page: page)
      try await sendResourceEvent(
        resourceBatchEvent(
          items: items,
          sources: [resourceSourceFact(source: source, page: page, canContinue: false)]
        ),
        receive: receive
      )
    }
  }

  // MARK: - 资源搜索结果数据

  static var resourceSearchContexts: [Context] {
    [
      context(
        index: 1,
        title: "Frontier.Signal.S01E01.2160p.WEB-DL.HEVC.DV.HDR-Alpha",
        site: "AlphaPT",
        size: 12_884_901_888,
        seeders: 86,
        filtered: false
      ),
      context(
        index: 2,
        title: "Frontier.Signal.S01E01.1080p.WEB-DL.H264-Beta",
        site: "BetaHD",
        size: 4_294_967_296,
        seeders: 42,
        filtered: false
      ),
      context(
        index: 3,
        title: "Frontier.Signal.S01E01.1080p.WEB-DL.H264-Gamma",
        site: "GammaPT",
        size: 3_865_470_566,
        seeders: 17,
        filtered: false
      ),
      context(
        index: 4,
        title: "Frontier.Signal.S01E02.1080p.WEB-DL.HEVC-Alpha",
        site: "AlphaPT",
        size: 5_368_709_120,
        seeders: 63,
        filtered: false
      ),
    ]
  }

  /// 资源卡片与「添加下载」面板共用的种子/识别值。
  static var resourceTorrent: TorrentInfo {
    TorrentInfo(
      site: 1,
      site_name: "AlphaPT",
      site_order: 1,
      title: "Frontier.Signal.S01E01.2160p.WEB-DL.HEVC.DV.HDR-Alpha",
      description: "预览资源描述，包含字幕、杜比视界和多版本信息。",
      enclosure: "https://example.com/1.torrent",
      page_url: "https://example.com/torrents/1",
      size: 12_884_901_888,
      seeders: 86,
      peers: 172,
      pubdate: "2026-07-01 10:00:00",
      uploadvolumefactor: 2,
      downloadvolumefactor: 0,
      pri_order: 9,
      labels: ["preview"],
      volume_factor: "Free"
    )
  }

  static var resourceMeta: MetaInfo {
    MetaInfo(
      title: "Frontier Signal",
      year: "2026",
      resource_team: "Alpha",
      video_encode: "HEVC",
      resource_pix: "2160p",
      name: "边境信号",
      season_episode: "S01E01",
      subtitle: "简繁字幕",
      web_source: "WEB-DL",
      edition: "DV HDR",
      total_season: 1,
      total_episode: 12
    )
  }

  // MARK: - 写入型操作

  static func addDownload(
    payload: AddDownloadRequest
  ) async throws -> (success: Bool, message: String?) {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchAddDownload)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.searchAddDownload) {
      return (false, "预览：后端拒绝了这次下载（保存路径不可用）")
    }
    return (true, nil)
  }

  static func forkSubscription(share: SubscribeShare) async throws -> Int {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.searchForkSubscription)
    return 96_999
  }

  // MARK: - 聚合搜索结果数据

  private static var mediaSearchResults: [MediaInfo] {
    [
      movieMedia(id: 91_001, title: "边境信号：归途"),
      baseTVMedia(id: 92_001, title: "边境信号"),
      movieMedia(id: 91_002, title: "边境信号：失联信标"),
      baseTVMedia(id: 92_002, title: "边境信号 第二季"),
      movieMedia(id: 91_003, title: "边境信号：深空回声"),
      baseTVMedia(id: 92_003, title: "边境信号：前传"),
      movieMedia(id: 91_004, title: "边境信号：最后航道"),
      baseTVMedia(id: 92_004, title: "边境信号 特别篇"),
      movieMedia(id: 91_005, title: "边境信号：无人区"),
      baseTVMedia(id: 92_005, title: "边境信号 第三季"),
      movieMedia(id: 91_006, title: "边境信号：静默协议"),
      baseTVMedia(id: 92_006, title: "边境信号：维护小队"),
      movieMedia(id: 91_007, title: "边境信号：远航"),
      baseTVMedia(id: 92_007, title: "边境信号：信号溯源"),
      movieMedia(id: 91_008, title: "边境信号：残响"),
      baseTVMedia(id: 92_008, title: "边境信号 圣诞特别篇"),
      movieMedia(id: 91_009, title: "边境信号：零号站"),
      baseTVMedia(id: 92_009, title: "边境信号：档案"),
      movieMedia(id: 91_010, title: "边境信号：终点"),
      baseTVMedia(id: 92_010, title: "边境信号 第四季"),
    ]
  }

  // MARK: - 资源 SSE 事件构造

  private static func sendResourceEvent(
    _ event: SearchStreamEvent,
    receive: @MainActor @Sendable (SearchStreamEvent, Int) async throws -> Void
  ) async throws {
    try await receive(event, 512)
  }

  private static func resourceProgressEvent(text: String, value: Double) -> SearchStreamEvent {
    SearchStreamEvent(
      type: "append",
      text: text,
      text_i18n: nil,
      value: value,
      enable: nil,
      total_items: nil,
      items: nil,
      message: nil,
      message_i18n: nil,
      data: nil
    )
  }

  private static func resourceBatchEvent(
    items: [Context],
    sources: [ResourceSearchSource]
  ) -> SearchStreamEvent {
    SearchStreamEvent(
      type: "replace",
      text: "正在整理结果…",
      text_i18n: nil,
      value: 1,
      enable: nil,
      total_items: items.count,
      items: items,
      message: nil,
      message_i18n: nil,
      sources: sources,
      stage: "done",
      replace_batch: true,
      batch_index: 0,
      batch_count: 1,
      data: nil
    )
  }

  private static func resourceSourceFacts(
    page: Int,
    canContinue: Bool
  ) -> [ResourceSearchSource] {
    ["1", "3", "7"].map {
      resourceSourceFact(source: $0, page: page, canContinue: canContinue)
    }
  }

  private static func resourceSourceFact(
    source: String?,
    page: Int,
    canContinue: Bool
  ) -> ResourceSearchSource {
    let id = source ?? ""
    return ResourceSearchSource(
      source: id,
      site_name: resourceSiteName(for: id),
      page: page,
      can_continue: canContinue,
      error: nil
    )
  }

  private static func resourceSiteName(for source: String?) -> String {
    switch source {
    case "1": return "AlphaPT"
    case "3": return "BetaHD"
    case "7": return "GammaPT"
    default: return "全部站点"
    }
  }

  private static func resourceContinuationItems(
    source: String?,
    page: Int
  ) -> [Context] {
    guard page == 1 else { return [] }
    switch source {
    case "1":
      return [
        context(
          index: 5,
          title: "Frontier.Signal.S01E03.2160p.WEB-DL.HEVC-Alpha",
          site: "AlphaPT",
          size: 11_811_160_064,
          seeders: 54,
          filtered: false
        )
      ]
    case "3":
      return [
        context(
          index: 6,
          title: "Frontier.Signal.S01E03.1080p.WEB-DL.H264-Beta",
          site: "BetaHD",
          size: 4_026_531_840,
          seeders: 31,
          filtered: false
        )
      ]
    case "7":
      return [
        context(
          index: 7,
          title: "Frontier.Signal.S01E03.1080p.WEB-DL.H264-Gamma",
          site: "GammaPT",
          size: 3_758_096_384,
          seeders: 9,
          filtered: false
        )
      ]
    default:
      return []
    }
  }
}

extension UIPreviewBehaviorKey {
  // 聚合搜索。
  static let searchMedia = "search.media"
  static let searchMediaMore = "search.mediaMore"
  static let searchCollection = "search.collection"
  static let searchPerson = "search.person"
  static let searchSubscriptionShares = "search.subscriptionShares"
  static let searchManualMedia = "search.manualMedia"
  static let searchMediaSources = "search.mediaSources"

  // 站点与筛选配置。`search.sites` 由 PageDataFixtures 提供，这里不重复定义。
  static let searchAllSites = "search.allSites"
  static let searchDirectories = "search.directories"
  static let searchFilterRuleGroups = "search.filterRuleGroups"
  static let searchCustomFilterRules = "search.customFilterRules"

  // 资源搜索结果页（分页 SSE）。
  static let resourcePage = "search.resourcePage"
  static let resourcePageMore = "search.resourcePageMore"

  // 写入型操作。
  static let searchAddDownload = "search.addDownload"
  static let searchForkSubscription = "search.forkSubscription"
}
#endif
