import Combine
import Foundation

struct SeasonSubscriptionSummary: Equatable, Hashable {
  let id: Int
  let season: Int
  let episodeGroup: String?

  init(id: Int, season: Int, episodeGroup: String?) {
    self.id = id
    self.season = season
    self.episodeGroup = Self.normalizedEpisodeGroup(episodeGroup)
  }

  init?(subscribe: Subscribe) {
    guard let id = subscribe.id, let season = subscribe.season else { return nil }
    self.init(id: id, season: season, episodeGroup: subscribe.episode_group)
  }

  static func indexBySeason(from subscriptions: [Subscribe], matching media: MediaInfo)
    -> [Int: SeasonSubscriptionSummary]
  {
    var summaries: [Int: SeasonSubscriptionSummary] = [:]

    for subscription in subscriptions where matches(subscription, media: media) {
      guard let summary = SeasonSubscriptionSummary(subscribe: subscription) else { continue }
      if summaries[summary.season] == nil {
        summaries[summary.season] = summary
      }
    }

    return summaries
  }

  func groupDisplayName(episodeGroups: [EpisodeGroup]) -> String {
    SubscriptionCancelConfirmation.episodeGroupDisplayName(
      episodeGroup,
      episodeGroups: episodeGroups
    )
  }

  func statusDisplayText(episodeGroups: [EpisodeGroup]) -> String {
    "已订阅 · \(groupDisplayName(episodeGroups: episodeGroups))"
  }

  private static func matches(_ subscription: Subscribe, media: MediaInfo) -> Bool {
    guard subscription.type == "电视剧" else { return false }
    if let tmdbId = validNumericIdentifier(media.tmdb_id), subscription.tmdbid == tmdbId { return true }
    if let doubanId = normalizedIdentifier(media.douban_id),
      normalizedIdentifier(subscription.doubanid) == doubanId
    {
      return true
    }
    if let bangumiId = validNumericIdentifier(media.bangumi_id), subscription.bangumiid == bangumiId {
      return true
    }
    if let mediaId = normalizedMediaIdentifier(media.apiMediaId),
      normalizedMediaIdentifier(subscription.apiMediaId) == mediaId
    {
      return true
    }
    return false
  }

  private static func validNumericIdentifier(_ id: Int?) -> Int? {
    guard let id, id > 0 else { return nil }
    return id
  }

  private static func normalizedIdentifier(_ identifier: String?) -> String? {
    guard let identifier else { return nil }
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func normalizedMediaIdentifier(_ mediaId: String?) -> String? {
    guard let mediaId = normalizedIdentifier(mediaId), !mediaId.hasSuffix(":") else { return nil }

    let parts = mediaId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2 {
      let prefix = parts[0]
      let value = parts[1]
      if value.isEmpty { return nil }
      if (prefix == "tmdb" || prefix == "bangumi"), Int(value) == 0 { return nil }
    }

    return mediaId
  }

  private static func normalizedEpisodeGroup(_ episodeGroup: String?) -> String? {
    guard let episodeGroup else { return nil }
    let trimmed = episodeGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

@MainActor
class SubscribeSeasonViewModel: ObservableObject {
  let mediaInfo: MediaInfo

  @Published var seasonInfos: [TmdbSeason] = []
  @Published var episodeGroups: [EpisodeGroup] = []
  @Published var selectedGroupId: String = ""
  // 季库状态映射：0-已入库 (Available), 1-部分缺失 (Partial), 2-完全缺失 (Missing)
  @Published var seasonsNotExisted: [Int: Int] = [:]
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?

  // 各季的订阅状态
  @Published var seasonSubscriptions: [Int: SeasonSubscriptionSummary] = [:]
  @Published var subscribedSeasons: Set<Int> = []
  @Published var subscribingSeasons: Set<Int> = []

  // 订阅配置弹窗所需数据
  @Published var sheetSubscribe: Subscribe?
  @Published var showUnsubscribeConfirm: Int?  // 待取消订阅的季号

  private let initialSeason: Int?
  private var hasLoaded = false

  init(mediaInfo: MediaInfo, initialSeason: Int? = nil) {
    self.mediaInfo = mediaInfo
    self.initialSeason = initialSeason
  }

  func loadData(
    checkSubscriptionLimit: Int? = nil,
    forceRefreshSubscriptions: Bool = true
  ) async {
    guard !hasLoaded else { return }
    hasLoaded = true
    isLoading = true
    defer { isLoading = false }

    do {
      // 如果有 TMDB ID，加载该剧集关联的剧集组 (Episode Groups)
      if let tmdbId = mediaInfo.tmdb_id {
        self.episodeGroups = try await APIService.shared.fetchEpisodeGroups(tmdbId: tmdbId)
      }

      // 执行初始分季数据获取
      try await fetchSeasonsInternal(
        checkSubscriptionLimit: checkSubscriptionLimit,
        forceRefreshSubscriptions: forceRefreshSubscriptions
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 当用户在界面切换剧集组时触发重新加载
  func fetchSeasons() async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await fetchSeasonsInternal()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 内部核心加载方法：获取分季详情并排序，随后检查入库和订阅状态
  private func fetchSeasonsInternal(
    checkSubscriptionLimit: Int? = nil,
    forceRefreshSubscriptions: Bool = false
  ) async throws {
    if !selectedGroupId.isEmpty {
      // 逻辑 A：如果选择了剧集组，则按组获取分季
      self.seasonInfos = try await APIService.shared.getGroupSeasons(
        groupId: selectedGroupId)
    } else {
      // 逻辑 B：按媒体 ID 获取原始分季
      self.seasonInfos = try await APIService.shared.getMediaSeasons(media: mediaInfo)
    }

    // 按季号升序排列 (S00, S01, S02...)
    self.seasonInfos.sort { ($0.season_number ?? 0) < ($1.season_number ?? 0) }

    // 加载完成后，立即检查每季在媒体服务器中的入库状态
    await checkSeasonsStatus()

    // 同时检查各季当前的订阅状态
    await checkSubscriptionStatus(
      limit: checkSubscriptionLimit,
      forceRefresh: forceRefreshSubscriptions
    )
  }

  /// 调用后端接口，比对媒体库中已有的集数，确定每一季的完整性
  func checkSeasonsStatus() async {
    do {
      // 构建临时的 MediaInfo 结构用于状态查询，需手动注入选中的剧集组 (episode_group)
      // 逻辑参考 Vue 前端实现，确保后端能正确识别分组后的集数
      // 通过完整复制 mediaInfo 属性并仅修改 episode_group，确保用于状态检查的 checkMedia 哈希值稳定
      let checkMedia = MediaInfo(
        tmdb_id: mediaInfo.tmdb_id,
        douban_id: mediaInfo.douban_id,
        bangumi_id: mediaInfo.bangumi_id,
        imdb_id: mediaInfo.imdb_id,
        tvdb_id: mediaInfo.tvdb_id,
        source: mediaInfo.source,
        mediaid_prefix: mediaInfo.mediaid_prefix,
        media_id: mediaInfo.media_id,
        title: mediaInfo.title,
        original_title: mediaInfo.original_title,
        original_name: mediaInfo.original_name,
        names: mediaInfo.names,
        type: mediaInfo.type,
        year: mediaInfo.year,
        season: mediaInfo.season,
        poster_path: mediaInfo.poster_path,
        backdrop_path: mediaInfo.backdrop_path,
        overview: mediaInfo.overview,
        vote_average: mediaInfo.vote_average,
        popularity: mediaInfo.popularity,
        season_info: mediaInfo.season_info,
        collection_id: mediaInfo.collection_id,
        directors: mediaInfo.directors,
        actors: mediaInfo.actors,
        episode_group: selectedGroupId.isEmpty ? nil : selectedGroupId,
        runtime: mediaInfo.runtime,
        release_date: mediaInfo.release_date,
        original_language: mediaInfo.original_language,
        production_countries: mediaInfo.production_countries,
        genres: mediaInfo.genres,
        category: mediaInfo.category
      )

      let result = try await APIService.shared.checkSeasonsNotExists(mediaInfo: checkMedia)

      var newStatus: [Int: Int] = [:]

      // 预先将总集数为 0 的季标记为缺失 (2)，避免 fallback 到默认已入库
      for season in seasonInfos {
        if let seasonNumber = season.season_number, (season.episode_count ?? 0) == 0 {
          newStatus[seasonNumber] = 2
        }
      }

      for item in result {
        // 状态定义映射：
        // 0 -> 已完整入库 (Exists)
        // 1 -> 部分集数缺失 (Partial)
        // 2 -> 整季缺失 (Missing)
        var state = 0
        if item.episodes.isEmpty {
          state = 2
        } else if item.episodes.count < item.total_episode {
          state = 1
        }
        newStatus[item.season] = state
      }
      self.seasonsNotExisted = newStatus

    } catch {
      print("检查季入库状态失败: \(error)")
    }
  }

  /// 查询当前媒体所有分季订阅摘要，填充 seasonSubscriptions 和 subscribedSeasons
  func checkSubscriptionStatus(limit _: Int? = nil, forceRefresh: Bool = false) async {
    do {
      try await refreshSubscriptionSummaries(forceRefresh: forceRefresh)
    } catch {
      if error is CancellationError {
        return
      }
      print("检查季订阅状态失败: \(error)")
      errorMessage = error.localizedDescription
    }
  }

  private func refreshSubscriptionSummaries(forceRefresh: Bool) async throws {
    let subscriptions = try await APIService.shared.fetchSubscriptions(forceRefresh: forceRefresh)
    let summaries = SeasonSubscriptionSummary.indexBySeason(from: subscriptions, matching: mediaInfo)
    self.seasonSubscriptions = summaries
    self.subscribedSeasons = Set(summaries.keys)
  }

  func prepareSubscription(seasonNumber: Int) {
    // 逻辑参考 Vue：如果该季已经完整入库 (state 为 0 或不在字典中)，默认开启“洗版”模式 (best_version = 1)
    let best_version =
      (seasonsNotExisted[seasonNumber] == nil || seasonsNotExisted[seasonNumber] == 0)
      ? 1 : 0

    self.sheetSubscribe = Subscribe(
      id: nil,
      name: mediaInfo.title ?? "",
      year: mediaInfo.year,
      type: mediaInfo.type ?? "电视剧",
      season: seasonNumber,
      poster: mediaInfo.poster_path,
      state: "N",
      last_update: nil,
      tmdbid: mediaInfo.tmdb_id,
      doubanid: mediaInfo.douban_id,
      bangumiid: mediaInfo.bangumi_id,
      best_version: best_version,
      episode_group: selectedGroupId.isEmpty ? nil : selectedGroupId
    )
  }

  func unsubscribeSeason(_ seasonNumber: Int) async {
    subscribingSeasons.insert(seasonNumber)
    defer { subscribingSeasons.remove(seasonNumber) }

    do {
      try await refreshSubscriptionSummaries(forceRefresh: true)
      guard let summary = seasonSubscriptions[seasonNumber] else {
        showUnsubscribeConfirm = nil
        return
      }

      let success = try await APIService.shared.deleteSubscription(id: summary.id)
      if success {
        try await refreshSubscriptionSummaries(forceRefresh: true)
        showUnsubscribeConfirm = nil
        // 通知首页刷新订阅列表
        NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
      } else {
        errorMessage = "取消订阅失败"
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - UI 状态辅助方法

  /// 根据入库状态返回对应的资产颜色名称
  func getStatusColor(season: Int) -> String {
    guard let state = seasonsNotExisted[season] else { return "green" }  // 默认已入库
    switch state {
    case 1: return "orange"  // 部分缺失
    case 2: return "red"  // 完全缺失
    default: return "green"  // 已完整入库
    }
  }

  func getStatusText(season: Int) -> String {
    guard let state = seasonsNotExisted[season] else { return "已入库" }
    switch state {
    case 1: return "部分缺失"
    case 2: return "缺失"
    default: return "已入库"
    }
  }

  func isSeasonSubscribed(_ seasonNumber: Int) -> Bool {
    seasonSubscriptions[seasonNumber] != nil
  }

  func isSeasonSubscribing(_ seasonNumber: Int) -> Bool {
    subscribingSeasons.contains(seasonNumber)
  }

  func subscriptionSummary(for seasonNumber: Int) -> SeasonSubscriptionSummary? {
    seasonSubscriptions[seasonNumber]
  }

  func subscriptionGroupText(for seasonNumber: Int) -> String {
    seasonSubscriptions[seasonNumber]?.groupDisplayName(episodeGroups: episodeGroups) ?? "默认剧集组"
  }

  func subscriptionStatusText(for seasonNumber: Int) -> String? {
    seasonSubscriptions[seasonNumber]?.statusDisplayText(episodeGroups: episodeGroups)
  }

  func unsubscribeConfirmationMessage(for seasonNumber: Int) -> String {
    let title = mediaInfo.cleanedTitle ?? mediaInfo.title ?? ""
    return SubscriptionCancelConfirmation.message(
      title: title,
      season: seasonNumber,
      episodeGroupText: subscriptionGroupText(for: seasonNumber)
    )
  }
}
