import Combine
import Foundation

struct SeasonSubscriptionSummary: Equatable, Hashable {
  let id: Int
  let season: Int
  let episodeGroup: String?
  /// 试看一集用的临时订阅占着这一季：标成「试看中」，不能取消，也不能另建订阅。
  let isEpisodeTrial: Bool

  init(id: Int, season: Int, episodeGroup: String?, isEpisodeTrial: Bool = false) {
    self.id = id
    self.season = season
    self.episodeGroup = Self.normalizedEpisodeGroup(episodeGroup)
    self.isEpisodeTrial = isEpisodeTrial
  }

  init?(subscribe: Subscribe) {
    guard let id = subscribe.id, let season = subscribe.season else { return nil }
    self.init(
      id: id, season: season, episodeGroup: subscribe.episode_group, isEpisodeTrial: subscribe.isEpisodeTrial)
  }

  static func indexBySeason(from subscriptions: [Subscribe], matching media: MediaInfo)
    -> [Int: SeasonSubscriptionSummary]
  {
    var summaries: [Int: SeasonSubscriptionSummary] = [:]

    for subscription in subscriptions where matches(subscription, media: media) {
      guard let summary = SeasonSubscriptionSummary(subscribe: subscription) else { continue }
      // 不同剧集组可以各有一条：正式订阅优先显示，试看订阅只在这一季没有正式订阅时出现。
      if summaries[summary.season].map({ $0.isEpisodeTrial && !summary.isEpisodeTrial }) ?? true {
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
    "\(isEpisodeTrial ? "试看中" : "已订阅") · \(groupDisplayName(episodeGroups: episodeGroups))"
  }

  private static func matches(_ subscription: Subscribe, media: MediaInfo) -> Bool {
    guard subscription.type == "电视剧" else { return false }

    let mediaId = media.apiMediaId
    if let source = subscription.media_source, !source.isEmpty,
      let subscriptionMediaId = subscription.media_id, !subscriptionMediaId.isEmpty
    {
      let prefix = source == "themoviedb" ? "tmdb" : source
      return mediaId == "\(prefix):\(subscriptionMediaId)"
    }
    if let legacyMediaId = subscription.mediaid, !legacyMediaId.isEmpty {
      return mediaId == legacyMediaId
    }
    if let mediaTMDBId = media.tmdb_id, mediaTMDBId != 0,
      let subscriptionTMDBId = subscription.tmdbid, subscriptionTMDBId != 0
    {
      return mediaTMDBId == subscriptionTMDBId
    }
    if let mediaDoubanId = media.douban_id, !mediaDoubanId.isEmpty,
      let subscriptionDoubanId = subscription.doubanid, !subscriptionDoubanId.isEmpty
    {
      return mediaDoubanId == subscriptionDoubanId
    }
    if let mediaBangumiId = media.bangumi_id, mediaBangumiId != 0,
      let subscriptionBangumiId = subscription.bangumiid, subscriptionBangumiId != 0
    {
      return mediaBangumiId == subscriptionBangumiId
    }
    if let mediaAniListId = media.anilist_id, mediaAniListId != 0,
      let subscriptionAniListId = subscription.anilistid, subscriptionAniListId != 0
    {
      return mediaAniListId == subscriptionAniListId
    }
    return false
  }

  private static func normalizedEpisodeGroup(_ episodeGroup: String?) -> String? {
    guard let episodeGroup else { return nil }
    let trimmed = episodeGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private struct SeasonAvailabilityScope: Equatable {
  let uiIdentity: String
  let episodeGroup: String?
}

@MainActor
class SubscribeSeasonViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  let mediaInfo: MediaInfo
  // 分季模型也可能被会话预载缓存持有，不能反向延长服务的生命周期。
  private weak var apiService: APIService?

  @Published private var standardSeasonInfos: [TmdbSeason]
  var seasonInfos: [TmdbSeason] {
    if let effectiveEpisodeGroup {
      return episodeGroupCatalog.seasonsByGroup[effectiveEpisodeGroup] ?? []
    }
    return standardSeasonInfos
  }
  @Published private(set) var defaultSeasonInfos: [TmdbSeason]
  let episodeGroupCatalog: EpisodeGroupCatalog
  var episodeGroups: [EpisodeGroup] { episodeGroupCatalog.groups }
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
  /// 按到了试看中的季：用系统提示框说明这一季暂时不能取消或另建订阅。
  @Published var episodeTrialNoticeSeason: Int?
  @Published var subscribingSeasons: Set<Int> = []

  // 订阅配置弹窗所需数据
  @Published var sheetSubscribe: Subscribe?
  @Published var showUnsubscribeConfirm: Int?  // 待取消订阅的季号

  private let initialSeason: Int?
  private var hasLoaded = false
  private var isSeasonManagementContext = false
  private var seasonLoadRevision = 0
  private var seasonAvailabilityRevision = 0
  private var seasonAvailabilityScope: SeasonAvailabilityScope

  init(
    mediaInfo: MediaInfo,
    initialSeason: Int? = nil,
    initialEpisodeGroup: String? = nil,
    apiService: APIService = .shared
  ) {
    self.mediaInfo = mediaInfo
    self.apiService = apiService
    self.initialSeason = initialSeason
    self.standardSeasonInfos = mediaInfo.season_info ?? []
    self.defaultSeasonInfos = mediaInfo.season_info ?? []
    self.episodeGroupCatalog = EpisodeGroupCatalog(apiService: apiService)
    let selectedGroupId =
      Self.episodeGroupTMDBID(for: mediaInfo) != nil
      ? (initialEpisodeGroup ?? "")
      : ""
    self.selectedGroupId = selectedGroupId
    self.seasonAvailabilityScope = SeasonAvailabilityScope(
      uiIdentity: apiService.uiIdentity,
      episodeGroup: selectedGroupId.isEmpty ? nil : selectedGroupId
    )
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

  private func beginSeasonLoad() -> (revision: Int, episodeGroup: String?) {
    seasonLoadRevision &+= 1
    return (seasonLoadRevision, effectiveEpisodeGroup)
  }

  private func isSeasonLoadCurrent(
    _ load: (revision: Int, episodeGroup: String?),
    snapshot: APIServiceSessionSnapshot
  ) -> Bool {
    isSeasonLoadOwnerCurrent(load)
      && apiService?.isSessionUnchanged(from: snapshot) == true
  }

  private func isSeasonLoadOwnerCurrent(
    _ load: (revision: Int, episodeGroup: String?)
  ) -> Bool {
    seasonLoadRevision == load.revision
      && effectiveEpisodeGroup == load.episodeGroup
  }

  private func validateSeasonLoad(
    _ load: (revision: Int, episodeGroup: String?),
    snapshot: APIServiceSessionSnapshot
  ) throws {
    try Task.checkCancellation()
    guard isSeasonLoadCurrent(load, snapshot: snapshot) else { throw CancellationError() }
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
    guard let apiService else { return }
    let snapshot = apiService.sessionSnapshot()
    if isSeasonManagementContext != seasonManagement {
      hasLoaded = false
    }
    isSeasonManagementContext = seasonManagement
    guard !hasLoaded else { return }
    let load = beginSeasonLoad()
    hasLoaded = true
    isLoading = true
    hasSeasonLoadError = false
    defer {
      if seasonLoadRevision == load.revision {
        isLoading = false
      }
    }

    do {
      // 执行初始分季数据获取
      try await fetchSeasonsInternal(
        forceRefreshSubscriptions: forceRefreshSubscriptions,
        snapshot: snapshot,
        load: load
      )
    } catch is CancellationError {
      if seasonLoadRevision == load.revision {
        hasLoaded = false
      }
      return
    } catch {
      guard isSeasonLoadCurrent(load, snapshot: snapshot) else { return }
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

  func loadEpisodeGroups() async throws {
    guard let apiService, let tmdbID = Self.episodeGroupTMDBID(for: mediaInfo) else { return }
    try await episodeGroupCatalog.load(tmdbID: tmdbID, apiService: apiService)
  }

  /// 当用户在界面切换剧集组时触发重新加载
  func fetchSeasons() async {
    guard let apiService else { return }
    let snapshot = apiService.sessionSnapshot()
    let load = beginSeasonLoad()
    isLoading = true
    hasSeasonLoadError = false
    defer {
      if seasonLoadRevision == load.revision {
        isLoading = false
      }
    }

    do {
      try await fetchSeasonsInternal(snapshot: snapshot, load: load)
    } catch is CancellationError {
      return
    } catch {
      guard isSeasonLoadCurrent(load, snapshot: snapshot) else { return }
      hasSeasonLoadError = true
      errorMessage = error.localizedDescription
    }
  }

  /// 内部核心加载方法：获取分季详情并排序，随后检查入库和订阅状态
  private func fetchSeasonsInternal(
    forceRefreshSubscriptions: Bool = false,
    snapshot: APIServiceSessionSnapshot,
    load: (revision: Int, episodeGroup: String?)
  ) async throws {
    guard let apiService else { throw CancellationError() }
    try validateSeasonLoad(load, snapshot: snapshot)
    if let episodeGroup = load.episodeGroup {
      try await episodeGroupCatalog.loadSeasons(groupID: episodeGroup, apiService: apiService)
    } else {
      let loadedSeasons: [TmdbSeason]
      if isSeasonManagementContext {
        loadedSeasons = try await apiService.getMediaSeasons(media: mediaInfo)
      } else {
        loadedSeasons = mediaInfo.season_info ?? []
      }
      try validateSeasonLoad(load, snapshot: snapshot)
      standardSeasonInfos = loadedSeasons.sorted { ($0.season_number ?? 0) < ($1.season_number ?? 0) }
      if mediaInfo.season == nil, !standardSeasonInfos.isEmpty {
        defaultSeasonInfos = standardSeasonInfos
      }
    }
    try validateSeasonLoad(load, snapshot: snapshot)

    // 加载完成后，立即检查每季在媒体服务器中的入库状态
    seasonAvailabilityRevision &+= 1
    let availabilityRevision = seasonAvailabilityRevision
    try await checkSeasonsStatus(
      snapshot: snapshot,
      episodeGroup: load.episodeGroup,
      preserveVisibleState: false,
      isCurrent: {
        self.seasonAvailabilityRevision == availabilityRevision
          && self.isSeasonLoadOwnerCurrent(load)
      }
    )
    try validateSeasonLoad(load, snapshot: snapshot)

    // 同时检查各季当前的订阅状态
    if apiService.canAccess(.subscribe) {
      do {
        let summaries = try await loadSubscriptionSummaries(
          forceRefresh: forceRefreshSubscriptions
        )
        try validateSeasonLoad(load, snapshot: snapshot)
        applySubscriptionSummaries(summaries)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try validateSeasonLoad(load, snapshot: snapshot)
        Logger.error("检查季订阅状态失败: \(error)")
        errorMessage = error.localizedDescription
      }
    } else {
      try validateSeasonLoad(load, snapshot: snapshot)
      applySubscriptionSummaries([:])
    }
  }

  /// 调用后端接口，比对媒体库中已有的集数，确定每一季的完整性
  func checkSeasonsStatus() async {
    guard let apiService else { return }
    let snapshot = apiService.sessionSnapshot()
    let episodeGroup = effectiveEpisodeGroup
    seasonAvailabilityRevision &+= 1
    let revision = seasonAvailabilityRevision
    do {
      try await checkSeasonsStatus(
        snapshot: snapshot,
        episodeGroup: episodeGroup,
        preserveVisibleState: true,
        isCurrent: {
          self.seasonAvailabilityRevision == revision
            && self.effectiveEpisodeGroup == episodeGroup
        }
      )
    } catch is CancellationError {
      return
    } catch {
      guard seasonAvailabilityRevision == revision,
        effectiveEpisodeGroup == episodeGroup,
        apiService.isSessionUnchanged(from: snapshot)
      else { return }
      Logger.error("检查季入库状态失败: \(error)")
    }
  }

  private func checkSeasonsStatus(
    snapshot: APIServiceSessionSnapshot,
    episodeGroup: String?,
    preserveVisibleState: Bool,
    isCurrent: () -> Bool
  ) async throws {
    guard let apiService else { throw CancellationError() }
    guard apiService.isSessionUnchanged(from: snapshot), isCurrent() else {
      throw CancellationError()
    }
    let requestedScope = SeasonAvailabilityScope(
      uiIdentity: apiService.uiIdentity,
      episodeGroup: episodeGroup
    )
    let previousScope = seasonAvailabilityScope
    let previousStatuses = seasonsNotExisted
    let previousWasLoaded = isSeasonAvailabilityLoaded
    // 同账号、同剧集组的后台复查保留上一成功快照，成功后再整体替换。
    let canPreserveVisibleState =
      preserveVisibleState
      && previousWasLoaded
      && previousScope == requestedScope

    seasonAvailabilityScope = requestedScope
    if !canPreserveVisibleState {
      isSeasonAvailabilityLoaded = false
      if previousScope != requestedScope {
        seasonsNotExisted = [:]
      }
    }

    guard apiService.canAccess(.subscribe) else {
      seasonsNotExisted = [:]
      isSeasonAvailabilityLoaded = false
      return
    }

    do {
      let result = try await apiService.checkSeasonsNotExists(
        mediaInfo: seasonAvailabilityMedia(episodeGroup: episodeGroup)
      )
      guard apiService.isSessionUnchanged(from: snapshot), isCurrent() else {
        throw CancellationError()
      }

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
      seasonsNotExisted = newStatus
      isSeasonAvailabilityLoaded = true
      seasonAvailabilityScope = requestedScope
    } catch is CancellationError {
      restoreOrClearAvailabilityAfterInterruption(
        previousScope: previousScope,
        previousStatuses: previousStatuses,
        previousWasLoaded: previousWasLoaded,
        requestedScope: requestedScope,
        requestIsCurrent: isCurrent()
      )
      throw CancellationError()
    } catch {
      let requestIsCurrent = isCurrent()
      guard apiService.isSessionUnchanged(from: snapshot), requestIsCurrent else {
        restoreOrClearAvailabilityAfterInterruption(
          previousScope: previousScope,
          previousStatuses: previousStatuses,
          previousWasLoaded: previousWasLoaded,
          requestedScope: requestedScope,
          requestIsCurrent: requestIsCurrent
        )
        throw CancellationError()
      }
      restoreOrClearAvailabilityAfterInterruption(
        previousScope: previousScope,
        previousStatuses: previousStatuses,
        previousWasLoaded: previousWasLoaded,
        requestedScope: requestedScope,
        requestIsCurrent: true
      )
      Logger.error("检查季入库状态失败: \(error)")
    }
  }

  private func restoreOrClearAvailabilityAfterInterruption(
    previousScope: SeasonAvailabilityScope,
    previousStatuses: [Int: Int],
    previousWasLoaded: Bool,
    requestedScope: SeasonAvailabilityScope,
    requestIsCurrent: Bool
  ) {
    guard let apiService else { return }
    guard requestIsCurrent else { return }

    let currentScope = SeasonAvailabilityScope(
      uiIdentity: apiService.uiIdentity,
      episodeGroup: effectiveEpisodeGroup
    )
    guard currentScope == requestedScope, previousScope == requestedScope else {
      seasonsNotExisted = [:]
      isSeasonAvailabilityLoaded = false
      seasonAvailabilityScope = currentScope
      return
    }

    seasonsNotExisted = previousStatuses
    isSeasonAvailabilityLoaded = previousWasLoaded
    seasonAvailabilityScope = previousScope
  }

  func seasonAvailabilityMedia() throws -> MediaInfo {
    try seasonAvailabilityMedia(episodeGroup: effectiveEpisodeGroup)
  }

  private func seasonAvailabilityMedia(episodeGroup: String?) throws -> MediaInfo {
    let encoder = JSONEncoder()
    var payload = try JSONDecoder().decode(
      [String: JSONValue].self,
      from: encoder.encode(mediaInfo)
    )
    payload["episode_group"] = .string(episodeGroup ?? "")
    return try JSONDecoder().decode(MediaInfo.self, from: encoder.encode(payload))
  }

  /// 查询当前媒体所有分季订阅摘要，填充 seasonSubscriptions 和 subscribedSeasons
  @discardableResult
  func checkSubscriptionStatus(forceRefresh: Bool = false) async -> Bool {
    guard let apiService else { return false }
    guard apiService.canAccess(.subscribe) else {
      seasonSubscriptions = [:]
      subscribedSeasons = []
      return false
    }

    do {
      let summaries = try await loadSubscriptionSummaries(forceRefresh: forceRefresh)
      applySubscriptionSummaries(summaries)
      return true
    } catch {
      if error is CancellationError {
        return false
      }
      Logger.error("检查季订阅状态失败: \(error)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func refreshSubscriptionSummaries(forceRefresh: Bool) async throws {
    applySubscriptionSummaries(
      try await loadSubscriptionSummaries(forceRefresh: forceRefresh)
    )
  }

  private func loadSubscriptionSummaries(forceRefresh: Bool) async throws
    -> [Int: SeasonSubscriptionSummary]
  {
    guard let apiService else { throw CancellationError() }
    let subscriptions = try await apiService.fetchSubscriptions(forceRefresh: forceRefresh)
    return SeasonSubscriptionSummary.indexBySeason(from: subscriptions, matching: mediaInfo)
  }

  private func applySubscriptionSummaries(_ summaries: [Int: SeasonSubscriptionSummary]) {
    seasonSubscriptions = summaries
    subscribedSeasons = Set(summaries.keys)
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
    guard let apiService else { return }
    subscribingSeasons.insert(seasonNumber)
    defer { subscribingSeasons.remove(seasonNumber) }
    let sessionSnapshot = apiService.sessionSnapshot()

    do {
      try await refreshSubscriptionSummaries(forceRefresh: true)
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
      guard let summary = seasonSubscriptions[seasonNumber] else {
        showUnsubscribeConfirm = nil
        return
      }
      // 按季删除会连试看的临时订阅一起删掉；试看订阅由试看服务自己收尾。
      guard !summary.isEpisodeTrial else {
        showUnsubscribeConfirm = nil
        episodeTrialNoticeSeason = seasonNumber
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

  func isSeasonHeldByEpisodeTrial(_ seasonNumber: Int) -> Bool {
    seasonSubscriptions[seasonNumber]?.isEpisodeTrial == true
  }

  /// 已订阅的季按下后：正式订阅确认取消；试看中的季只提示，不进入取消流程。
  func requestUnsubscribe(season seasonNumber: Int) {
    if isSeasonHeldByEpisodeTrial(seasonNumber) {
      episodeTrialNoticeSeason = seasonNumber
    } else {
      showUnsubscribeConfirm = seasonNumber
    }
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
