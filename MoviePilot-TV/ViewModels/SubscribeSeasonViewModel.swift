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
    subscription.type == "电视剧"
      && subscription.identity != nil
      && subscription.identity == media.identity
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
  private let apiService: APIService

  @Published var seasonInfos: [TmdbSeason] = []
  @Published var episodeGroups: [EpisodeGroup] = []
  @Published var selectedGroupId: String = ""
  // 季库状态映射：0-已入库 (Available), 1-部分缺失 (Partial), 2-完全缺失 (Missing)
  @Published var seasonsNotExisted: [Int: Int] = [:]
  @Published var isSeasonAvailabilityLoaded: Bool = false
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?
  @Published var hasSeasonLoadError = false

  // 各季的订阅状态
  @Published var seasonSubscriptions: [Int: SeasonSubscriptionSummary] = [:]
  @Published var subscribedSeasons: Set<Int> = []
  @Published var subscribingSeasons: Set<Int> = []

  // 订阅配置弹窗所需数据
  @Published var sheetSubscribe: Subscribe?
  @Published var showUnsubscribeConfirm: Int?  // 待取消订阅的季号

  private let initialSeason: Int?
  private var hasLoaded = false
  private var isSeasonManagementContext = false

  init(
    mediaInfo: MediaInfo,
    initialSeason: Int? = nil,
    initialEpisodeGroup: String? = nil,
    apiService: APIService = .shared
  ) {
    self.mediaInfo = mediaInfo
    self.apiService = apiService
    self.initialSeason = initialSeason
    self.seasonInfos = mediaInfo.season_info ?? []
    self.selectedGroupId =
      Self.episodeGroupTMDBID(for: mediaInfo) != nil
      ? (initialEpisodeGroup ?? "")
      : ""
  }

  private static func episodeGroupTMDBID(for mediaInfo: MediaInfo) -> Int? {
    guard mediaInfo.identity?.source == "themoviedb" else { return nil }
    return MediaIdentifier.truthyNumericIdentifier(mediaInfo.tmdb_id)
  }

  private var effectiveEpisodeGroup: String? {
    guard Self.episodeGroupTMDBID(for: mediaInfo) != nil, !selectedGroupId.isEmpty else {
      return nil
    }
    return selectedGroupId
  }

  func loadData(forceRefreshSubscriptions: Bool = true) async {
    await loadData(
      forceRefreshSubscriptions: forceRefreshSubscriptions,
      seasonManagement: false
    )
  }

  func loadSeasonManagementData(forceRefreshSubscriptions: Bool = true) async {
    await loadData(
      forceRefreshSubscriptions: forceRefreshSubscriptions,
      seasonManagement: true
    )
  }

  private func loadData(
    forceRefreshSubscriptions: Bool,
    seasonManagement: Bool
  ) async {
    let snapshot = apiService.sessionSnapshot()
    if isSeasonManagementContext != seasonManagement {
      hasLoaded = false
    }
    isSeasonManagementContext = seasonManagement
    guard !hasLoaded else { return }
    hasLoaded = true
    isLoading = true
    hasSeasonLoadError = false
    defer { isLoading = false }

    do {
      if let tmdbId = Self.episodeGroupTMDBID(for: mediaInfo) {
        do {
          episodeGroups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbId)
          guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          episodeGroups = []
          Logger.error("加载剧集组失败: \(error)")
        }
      }

      // 执行初始分季数据获取
      try await fetchSeasonsInternal(
        forceRefreshSubscriptions: forceRefreshSubscriptions,
        snapshot: snapshot
      )
    } catch is CancellationError {
      hasLoaded = false
      return
    } catch {
      hasSeasonLoadError = true
      errorMessage = error.localizedDescription
    }
  }

  func retryLoadData(forceRefreshSubscriptions: Bool = true) async {
    hasLoaded = false
    await loadData(
      forceRefreshSubscriptions: forceRefreshSubscriptions,
      seasonManagement: isSeasonManagementContext
    )
  }

  /// 当用户在界面切换剧集组时触发重新加载
  func fetchSeasons() async {
    let snapshot = apiService.sessionSnapshot()
    isLoading = true
    hasSeasonLoadError = false
    defer { isLoading = false }

    do {
      try await fetchSeasonsInternal(snapshot: snapshot)
    } catch is CancellationError {
      return
    } catch {
      hasSeasonLoadError = true
      errorMessage = error.localizedDescription
    }
  }

  /// 内部核心加载方法：获取分季详情并排序，随后检查入库和订阅状态
  private func fetchSeasonsInternal(
    forceRefreshSubscriptions: Bool = false,
    snapshot: APIServiceSessionSnapshot
  ) async throws {
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    if let effectiveEpisodeGroup {
      // 逻辑 A：如果选择了剧集组，则按组获取分季
      self.seasonInfos = try await apiService.getGroupSeasons(
        groupId: effectiveEpisodeGroup)
    } else if isSeasonManagementContext {
      // 逻辑 B：分季管理页进入后请求最新的统一媒体季接口。
      self.seasonInfos = try await apiService.getMediaSeasons(media: mediaInfo)
    } else {
      // 逻辑 C：详情货架直接使用详情响应中的 season_info。
      self.seasonInfos = mediaInfo.season_info ?? []
    }
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }

    // 按季号升序排列 (S00, S01, S02...)
    self.seasonInfos.sort { ($0.season_number ?? 0) < ($1.season_number ?? 0) }

    // 加载完成后，立即检查每季在媒体服务器中的入库状态
    try await checkSeasonsStatus(snapshot: snapshot)
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }

    // 同时检查各季当前的订阅状态
    await checkSubscriptionStatus(forceRefresh: forceRefreshSubscriptions)
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
  }

  /// 调用后端接口，比对媒体库中已有的集数，确定每一季的完整性
  func checkSeasonsStatus() async {
    let snapshot = apiService.sessionSnapshot()
    do {
      try await checkSeasonsStatus(snapshot: snapshot)
    } catch is CancellationError {
      return
    } catch {
      seasonsNotExisted = [:]
      print("检查季入库状态失败: \(error)")
    }
  }

  private func checkSeasonsStatus(snapshot: APIServiceSessionSnapshot) async throws {
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    let wasAvailabilityLoaded = isSeasonAvailabilityLoaded
    isSeasonAvailabilityLoaded = false
    guard apiService.canAccess(.subscribe) else {
      seasonsNotExisted = [:]
      return
    }

    do {
      let result = try await apiService.checkSeasonsNotExists(
        mediaInfo: seasonAvailabilityMedia()
      )
      guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }

      var newStatus: [Int: Int] = [:]

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
      self.isSeasonAvailabilityLoaded = true

    } catch is CancellationError {
      isSeasonAvailabilityLoaded = wasAvailabilityLoaded
      throw CancellationError()
    } catch {
      self.seasonsNotExisted = [:]
      print("检查季入库状态失败: \(error)")
    }
  }

  func seasonAvailabilityMedia() throws -> MediaInfo {
    let encoder = JSONEncoder()
    var payload = try JSONDecoder().decode(
      [String: JSONValue].self,
      from: encoder.encode(mediaInfo)
    )
    payload["episode_group"] = .string(effectiveEpisodeGroup ?? "")
    return try JSONDecoder().decode(MediaInfo.self, from: encoder.encode(payload))
  }

  /// 查询当前媒体所有分季订阅摘要，填充 seasonSubscriptions 和 subscribedSeasons
  @discardableResult
  func checkSubscriptionStatus(forceRefresh: Bool = false) async -> Bool {
    guard apiService.canAccess(.subscribe) else {
      seasonSubscriptions = [:]
      subscribedSeasons = []
      return false
    }

    do {
      try await refreshSubscriptionSummaries(forceRefresh: forceRefresh)
      return true
    } catch {
      if error is CancellationError {
        return false
      }
      print("检查季订阅状态失败: \(error)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func refreshSubscriptionSummaries(forceRefresh: Bool) async throws {
    let subscriptions = try await apiService.fetchSubscriptions(forceRefresh: forceRefresh)
    let summaries = SeasonSubscriptionSummary.indexBySeason(from: subscriptions, matching: mediaInfo)
    self.seasonSubscriptions = summaries
    self.subscribedSeasons = Set(summaries.keys)
  }

  func prepareSubscription(seasonNumber: Int) {
    // 已完整入库的季显式全集洗版；其他情况不传洗版字段，让后端应用默认配置。
    let isFullyAvailable =
      isSeasonAvailabilityLoaded
      && (seasonsNotExisted[seasonNumber] == nil || seasonsNotExisted[seasonNumber] == 0)

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
      anilistid: mediaInfo.anilist_id,
      media_source: mediaInfo.identity?.source,
      media_id: mediaInfo.identity?.mediaId,
      best_version: isFullyAvailable ? 1 : nil,
      best_version_full: isFullyAvailable ? 1 : nil,
      episode_group: effectiveEpisodeGroup,
      mediaid: mediaInfo.apiMediaId
    )
  }

  func unsubscribeSeason(_ seasonNumber: Int) async {
    subscribingSeasons.insert(seasonNumber)
    defer { subscribingSeasons.remove(seasonNumber) }
    let sessionSnapshot = apiService.sessionSnapshot()

    do {
      try await refreshSubscriptionSummaries(forceRefresh: true)
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      guard seasonSubscriptions[seasonNumber] != nil else {
        showUnsubscribeConfirm = nil
        return
      }

      let result = try await apiService.deleteSubscriptionResult(
        media: mediaInfo,
        season: seasonNumber
      )
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      if result.success {
        // 删除已经落到远端；后续列表刷新失败也不能吞掉订阅变更通知。
        NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
        try await refreshSubscriptionSummaries(forceRefresh: true)
        guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
        showUnsubscribeConfirm = nil
      } else {
        errorMessage =
          MediaIdentifier.normalizedString(result.message)
          ?? "取消订阅失败"
      }
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - UI 状态辅助方法

  /// 根据入库状态返回对应的资产颜色名称
  func getStatusColor(season: Int) -> String {
    guard isSeasonAvailabilityLoaded else { return "gray" }
    guard let state = seasonsNotExisted[season] else { return "green" }
    switch state {
    case 1: return "orange"  // 部分缺失
    case 2: return "red"  // 完全缺失
    default: return "green"  // 已完整入库
    }
  }

  func getStatusText(season: Int) -> String? {
    guard isSeasonAvailabilityLoaded else { return nil }
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
