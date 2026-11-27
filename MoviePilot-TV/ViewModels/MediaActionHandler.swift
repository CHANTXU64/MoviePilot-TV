import SwiftUI
import Combine

/// 共享映射、按需查找或名称识别得到的 TMDB 目标，连同请求时的原来源身份。
struct TMDBTargetResolution {
  let origin: MediaIdentity
  let target: MediaInfo
  /// 只靠片名、年份猜出，后端没有确认过这层关系。
  var isNameRecognized = false
}

/// 默认详情入口的目标选择。只在共享映射与按需识别/上报 API 可用（后端 v3.2.9 起），
/// 且条目解析后的主来源是豆瓣、Bangumi、AniList 时改道；
/// 合集、音乐、主来源是 TMDB 或插件等其他来源的条目保持原样。
nonisolated enum TMDBDetailOpenPolicy {
  private static let reroutablePrimarySources: Set<String> = ["douban", "bangumi", "anilist"]

  enum Decision: Equatable {
    /// 条目自己带着可用的 TMDB 编号，直接打开，不再识别。
    case openTMDB(Int)
    /// 先按后端共享映射/按需查找确认 TMDB。
    case recognize
    /// 打开原条目。
    case openSource
  }

  /// 条目带来源季号时，只有后端确认了 TMDB 季的目标才能用；否则回原来源页，不替用户猜一季。
  static func targetKeepsConfirmedSeason(_ target: MediaInfo, for item: MediaInfo) -> Bool {
    guard item.type == "电视剧", let season = item.season, season >= 0 else { return true }
    return target.tmdbSeasonHint != nil
  }

  static func decision(
    for item: MediaInfo,
    isEnabled: Bool,
    hasRecognitionReporting: Bool
  ) -> Decision {
    // 默认打开 TMDB 详情要求共享映射和能把识别结果写回共享表的按需识别 API。
    // 低于 v3.2.9、版本读不出或无法解析时不启用，避免为了跳转退回名称识别去直查 TMDB。
    guard isEnabled, hasRecognitionReporting, item.shouldPreloadDetail else { return .openSource }
    // 只按解析后的主来源改道：插件条目即使带辅助豆瓣 ID 也留在自己的详情页。
    guard let primarySource = item.identity?.source,
      reroutablePrimarySources.contains(primarySource),
      item.type != "音乐"
    else { return .openSource }
    if let tmdbId = MediaIdentifier.validNumericIdentifier(item.tmdb_id) {
      return .openTMDB(tmdbId)
    }
    return .recognize
  }
}

@MainActor
class MediaActionHandler: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 默认打开详情时等待后端确认 TMDB 目标的上限；超过就打开原来源详情页。
  nonisolated static let defaultOpenRecognitionTimeout: Duration = .seconds(10)

  /// 一次按导航栈发起的默认详情打开。新点击取代旧等待，不同栈互不阻塞。
  private struct OpenAttempt {
    let id: UUID
    let task: Task<ImageNavigationEntry?, Never>
  }

  private let apiService: APIService
  private let openRecognitionTimeout: Duration
  private var openAttempts: [UUID: OpenAttempt] = [:]

  init(
    apiService: APIService = .shared,
    openRecognitionTimeout: Duration = MediaActionHandler.defaultOpenRecognitionTimeout
  ) {
    self.apiService = apiService
    self.openRecognitionTimeout = openRecognitionTimeout
  }

  @Published var isRecognizingTmdb = false
  @Published var showTMDBNotFoundAlert = false

  func cancelPresentation() {
    showTMDBNotFoundAlert = false
  }

  /// 打开媒体详情的默认入口：豆瓣、Bangumi、AniList 条目先请后端确认 TMDB 目标（最多等
  /// `openRecognitionTimeout`），确认到就打开 TMDB 详情页；确认不到、失败或超时就打开原来源详情页。
  /// 默认入口只接受条目自带的 TMDB 编号或后端确认的共享映射/按需查找，不用名称识别猜测。
  /// 需要后端的共享 TMDB 映射与按需识别/上报能力（v3.2.9 起）；
  /// 设置关闭、能力不足、合集、音乐和主来源不是这些站点的条目仍直接打开原条目。
  @discardableResult
  func openMediaDetail(
    _ item: MediaInfo,
    in coordinator: ImageNavigationCoordinator,
    sourceToken: ImageNavigationSourceToken,
    loadingPosterURL: URL? = nil
  ) async -> ImageNavigationEntry? {
    let coordinatorID = coordinator.id
    // 新点击立即取代同一导航栈里还在等待的旧动作；旧结果由 sourceToken 丢弃。
    openAttempts[coordinatorID]?.task.cancel()

    let attemptID = UUID()
    let task = Task<ImageNavigationEntry?, Never> { @MainActor [weak self] in
      guard let self else { return nil }
      return await self.performOpen(
        item,
        in: coordinator,
        sourceToken: sourceToken,
        attemptID: attemptID,
        loadingPosterURL: loadingPosterURL
      )
    }
    // 来源页离开、切标签或栈失效时，结束还在等待的回调；不再让进度提示留在新页面上。
    let observation = coordinator.objectWillChange.sink { [weak coordinator] _ in
      Task { @MainActor in
        guard let coordinator, !coordinator.isCurrent(sourceToken) else { return }
        task.cancel()
      }
    }
    openAttempts[coordinatorID] = OpenAttempt(id: attemptID, task: task)
    let entry = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    observation.cancel()
    if openAttempts[coordinatorID]?.id == attemptID {
      openAttempts[coordinatorID] = nil
    }
    return entry
  }

  private func performOpen(
    _ item: MediaInfo,
    in coordinator: ImageNavigationCoordinator,
    sourceToken: ImageNavigationSourceToken,
    attemptID: UUID,
    loadingPosterURL: URL?
  ) async -> ImageNavigationEntry? {
    // 同栈后一次点击会取消前一次的内层任务；被取消的任务不得再抢先入栈。
    guard !Task.isCancelled, coordinator.isCurrent(sourceToken) else { return nil }
    let sessionSnapshot = apiService.sessionSnapshot()
    let posterURL = loadingPosterURL ?? item.imageURLs.poster

    let isDefaultOpenEnabled = SystemViewModel.shouldDefaultOpenTMDBDetail
    let hasRecognitionReporting = apiService.supportsTMDBRecognitionReporting
    switch TMDBDetailOpenPolicy.decision(
      for: item,
      isEnabled: isDefaultOpenEnabled,
      hasRecognitionReporting: hasRecognitionReporting
    ) {
    case .openSource:
      let target = Self.sourceRouteTarget(
        for: item, isDefaultOpenActive: isDefaultOpenEnabled && hasRecognitionReporting)
      return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)

    case .openTMDB(let tmdbId):
      // 焦点预载已经切到确认过的 TMDB 目标时直接复用，包括映射给出的季号。
      if let target = apiService.mediaPreloader.confirmedTMDBTarget(for: item),
        TMDBDetailOpenPolicy.targetKeepsConfirmedSeason(target, for: item)
      {
        return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
      }
      // 来源季号不能直接当成 TMDB 季：先让后端确认；确认不到就回原来源页，避免打开另一季。
      if item.type == "电视剧", let season = item.season, season >= 0 {
        let target = await resolveConfirmedTMDBTarget(
          for: item, in: coordinator, attemptID: attemptID)
        guard !Task.isCancelled, apiService.isSessionUnchanged(from: sessionSnapshot),
          coordinator.isCurrent(sourceToken)
        else { return nil }
        // 关系确认了但没确认季号时也回原来源页，不替用户猜一季。
        if let target, target.tmdbSeasonHint != nil {
          return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
        }
        return pushIfCurrent(item, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
      }
      // 电影没有 TMDB 季；条目上残留的季号不能带进 TMDB 目标。
      let target = Self.tmdbJumpTarget(
        for: item, tmdbId: tmdbId,
        season: item.type == "电视剧" ? nil : .some(nil))
      return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)

    case .recognize:
      if let target = apiService.mediaPreloader.confirmedTMDBTarget(for: item),
        TMDBDetailOpenPolicy.targetKeepsConfirmedSeason(target, for: item)
      {
        return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
      }
      let target = await resolveConfirmedTMDBTarget(
          for: item, in: coordinator, attemptID: attemptID)
      guard !Task.isCancelled, apiService.isSessionUnchanged(from: sessionSnapshot),
        coordinator.isCurrent(sourceToken)
      else { return nil }
      // 原来源页保留「TMDB详情页」入口：后端没确认到目标时用户仍可手动识别。
      if let target, TMDBDetailOpenPolicy.targetKeepsConfirmedSeason(target, for: item) {
        return pushIfCurrent(target, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
      }
      return pushIfCurrent(item, posterURL: posterURL, sourceToken: sourceToken, in: coordinator)
    }
  }

  /// 所有默认入口的入栈都经过这里：任务已被后一次点击取消时直接放弃。
  private func pushIfCurrent(
    _ target: MediaInfo,
    posterURL: URL?,
    sourceToken: ImageNavigationSourceToken,
    in coordinator: ImageNavigationCoordinator
  ) -> ImageNavigationEntry? {
    guard !Task.isCancelled else { return nil }
    return coordinator.push(
      target, loadingPosterURL: posterURL, ifCurrent: sourceToken)
  }

  /// 只向后端要确认过的 TMDB 目标，最多等 `openRecognitionTimeout`；不在这里做名称识别。
  private func resolveConfirmedTMDBTarget(
    for item: MediaInfo,
    in coordinator: ImageNavigationCoordinator,
    attemptID: UUID
  ) async -> MediaInfo? {
    coordinator.beginPreparingMediaDetail(attemptID: attemptID)
    defer { coordinator.endPreparingMediaDetail(attemptID: attemptID) }
    return await withTaskGroup(of: MediaInfo?.self) { group in
      group.addTask {
        (try? await Self.mappedTMDBTarget(for: item, apiService: self.apiService))?.target
      }
      group.addTask {
        try? await Task.sleep(for: self.openRecognitionTimeout)
        return nil
      }
      let target = await group.next() ?? nil
      group.cancelAll()
      return target
    }
  }

  /// 默认入口启用时，TMDB 主身份的剧集把卡片季号当作已确认的 TMDB 季交给剧集行；
  /// 其他主来源或功能关闭时原样返回，保持关闭后的旧行为。
  private static func sourceRouteTarget(
    for item: MediaInfo, isDefaultOpenActive: Bool
  ) -> MediaInfo {
    guard isDefaultOpenActive, item.identity?.source == "themoviedb", item.type == "电视剧",
      item.tmdbSeasonHint == nil, let season = item.season, season >= 0
    else { return item }
    var target = item
    target.tmdbSeasonHint = season
    return target
  }

  func searchResourcesTarget(
    for item: MediaInfo, sites: String? = nil
  ) -> ResourceSearchRequest {
    return ResourceSearchRequest(
      keyword: item.apiMediaId ?? "",
      type: item.type,
      area: "title",
      title: item.title ?? "Unknown",
      year: item.year,
      season: item.season,
      mediaInfo: item,
      sites: sites
    )
  }

  func searchResourcesTargetUsingDefaultSites(for item: MediaInfo) async -> ResourceSearchRequest? {
    let snapshot = apiService.sessionSnapshot()
    let sites = await SystemViewModel.normalizedDefaultSearchSitesString(apiService: apiService)
    guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
    return searchResourcesTarget(for: item, sites: sites)
  }

  /// 有媒体身份时按精确字幕搜索。季号只沿用条目上已经存在的值，0 保留，缺失不补当前季。
  func subtitleSearchRequest(for item: MediaInfo, sites: String?) -> SubtitleSearchRequest? {
    guard SubtitleSearchRequest.supportsSubtitleSearch(item), let identity = item.identity else {
      return nil
    }
    let season = item.season.flatMap { $0 >= 0 ? $0 : nil }
    return SubtitleSearchRequest(
      kind: .media(
        source: identity.source,
        mediaId: identity.mediaId,
        type: item.type,
        season: season,
        episode: nil
      ),
      sites: sites,
      displayTitle: item.title,
      mediaInfo: item
    )
  }

  /// 快捷入口共用：可选识别、默认站点、标题回退都属于同一次动作。
  func subtitleSearchRequestUsingDefaultSites(
    for item: MediaInfo, recognizeIfNeeded: Bool = false
  ) async -> SubtitleSearchRequest? {
    guard apiService.canAccess(.search), SubtitleSearchRequest.supportsSubtitleSearch(item) else { return nil }
    let snapshot = apiService.sessionSnapshot()
    var target = item
    if recognizeIfNeeded, item.identity == nil,
      let recognized = await getTMDBJumpTarget(
        for: item, notifyWhenUnrecognized: false, useSharedMapping: false)
    {
      target = recognized
    }
    guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
    let sites = await SystemViewModel.normalizedDefaultSubtitleSearchSitesString(apiService: apiService)
    guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
    return subtitleSearchRequest(for: target, sites: sites)
      ?? Self.titleSubtitleSearchRequest(keyword: item.title ?? "", sites: sites)
  }

  static func titleSubtitleSearchRequest(keyword: String, sites: String?) -> SubtitleSearchRequest? {
    let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else { return nil }
    return SubtitleSearchRequest(
      kind: .title(keyword: keyword),
      sites: sites,
      displayTitle: keyword,
      mediaInfo: nil
    )
  }

  /// 解析出可用于跳转/搜索的 TMDB 目标。
  ///
  /// - Parameter notifyWhenUnrecognized: 真正无匹配时是否弹「未识别到此媒体的TMDB信息」。
  ///   默认 `true`，适用于「TMDB详情页」这类**以 TMDB 为目标**的动作 —— 找不到就该告诉用户。
  ///   取 `false` 适用于「搜索资源」这类**识别失败可自愈**的调用方：拿不到 ID 会退回按标题
  ///   搜索，避免识别提示与结果跳转同时发生。
  /// - Parameter useSharedMapping: 是否先用非 TMDB 来源到 TMDB 的映射关系（共享映射、按需查找）。
  ///   「搜索资源」这类不依赖 TMDB 目标的入口传 `false`，避免为辅助查询多等。
  func getTMDBJumpTarget(
    for item: MediaInfo,
    targetTmdbId: Int? = nil,
    notifyWhenUnrecognized: Bool = true,
    useSharedMapping: Bool = true
  ) async -> MediaInfo? {
    let snapshot = apiService.sessionSnapshot()
    let validTargetTmdbId = MediaIdentifier.validNumericIdentifier(targetTmdbId)
    let validItemTmdbId = MediaIdentifier.validNumericIdentifier(item.tmdb_id)
    var tmdbIdToUse: Int? = validTargetTmdbId ?? validItemTmdbId

    if tmdbIdToUse == nil {
      isRecognizingTmdb = true
      defer { isRecognizingTmdb = false }

      // 先用映射关系；映射没有结果（含查找失败）时，照旧按名称识别。
      if useSharedMapping {
        do {
          if let target = try await Self.mappedTMDBTarget(for: item, apiService: apiService) {
            guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
            return target.target
          }
        } catch {
          return nil
        }
      }

      // 无标题且映射未命中，不属于"媒体不存在"，直接返回不弹提示。
      let title = item.title?.trimmingCharacters(in: .whitespaces) ?? ""
      guard !title.isEmpty else { return nil }
      do {
        tmdbIdToUse = try await apiService.recognizeTmdbId(
          title: title,
          year: item.year,
          type: item.type
        )
      } catch is CancellationError {
        return nil
      } catch {
        // 网络/后端/解码失败不是"媒体不存在"，不弹误导提示。
        Logger.error("TMDB 识别失败: \(error)")
        return nil
      }
    }

    guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }

    guard let tmdbId = tmdbIdToUse else {
      // 识别确实无匹配。但「搜索资源」这类调用方会自愈为标题搜索，弹窗只会拦住用户（F-122）。
      if notifyWhenUnrecognized {
        showTMDBNotFoundAlert = true
      }
      return nil
    }

    // 条目本身没有 TMDB 编号时，编号来自识别：目标带上类型和选季提示，与预载结果一致。
    if validItemTmdbId == nil,
      let recognized = Self.recognizedTMDBTarget(for: item, tmdbId: tmdbId, apiService: apiService)
    {
      return recognized.target
    }
    return Self.tmdbJumpTarget(for: item, tmdbId: tmdbId)
  }

  /// 映射关系给出的 TMDB 目标：先查共享映射；没有时，后端能转换的来源再按需查找。
  /// 返回 nil 表示映射这条路没有结果（含查询失败），调用方改用名称识别；只抛出取消。
  static func mappedTMDBTarget(
    for item: MediaInfo,
    apiService: APIService
  ) async throws -> TMDBTargetResolution? {
    let snapshot = apiService.sessionSnapshot()
    do {
      if let target = try await sharedTMDBTarget(for: item, apiService: apiService) {
        return target
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      Logger.error("TMDB 共享映射查询失败: \(error)")
    }
    try apiService.validateSessionSnapshot(snapshot)
    guard canMatchTMDB(for: item, apiService: apiService) else { return nil }
    do {
      return try await matchTMDBTarget(for: item, apiService: apiService)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try apiService.validateSessionSnapshot(snapshot)
      Logger.error("TMDB 按需查找失败，改用名称识别: \(error)")
      return nil
    }
  }

  /// 条目能否请后端按需查找；不能时直接按名称识别。
  static func canMatchTMDB(for item: MediaInfo, apiService: APIService) -> Bool {
    guard let request = mappingRequest(for: item, apiService: apiService) else { return false }
    return apiService.canRequestMediaMappingMatch(
      identity: request.identity, type: request.rawType, season: item.season)
  }

  /// 来源在后端有内置的 TMDB 转换（豆瓣、Bangumi、AniList）；预载只对这些来源做名称识别。
  static func hasBuiltInTMDBConversion(for item: MediaInfo) -> Bool {
    guard let source = MediaIdentifier.normalizeSource(item.identity?.source) else { return false }
    return APIService.tmdbConvertibleSources.contains(source)
  }

  /// 预载名称识别的结果，与映射结果一样记下原来源身份：电影订阅按精确记录查询和取消，
  /// 分季卡片的季号作为目标页选季提示（目标页没有这一季时按默认季显示）。
  /// `season` 缺省时用条目自己的季号。
  static func recognizedTMDBTarget(
    for item: MediaInfo,
    tmdbId: Int,
    season: Int?? = nil,
    apiService: APIService
  ) -> TMDBTargetResolution? {
    guard let request = mappingRequest(for: item, apiService: apiService) else { return nil }
    let isTV = request.mediaType == "tv"
    let seasonHint = isTV ? (season ?? item.season) : nil
    var target = tmdbJumpTarget(
      for: item, tmdbId: tmdbId, type: isTV ? "电视剧" : "电影", season: .some(seasonHint))
    target.tmdbSeasonHint = seasonHint
    return TMDBTargetResolution(origin: request.identity, target: target, isNameRecognized: true)
  }

  /// 共享映射的完整 TMDB 目标；返回 nil 表示没有可用关系。
  static func sharedTMDBTarget(
    for item: MediaInfo,
    apiService: APIService
  ) async throws -> TMDBTargetResolution? {
    guard let request = mappingRequest(for: item, apiService: apiService),
      let mapping = try await apiService.fetchMediaMapping(
        identity: request.identity, type: request.rawType, season: item.season)
    else {
      return nil
    }
    return mappingTMDBTarget(for: item, mapping: mapping, request: request)
  }

  /// 按需查找的完整 TMDB 目标；返回 nil 表示后端查找后没有关系。
  private static func matchTMDBTarget(
    for item: MediaInfo,
    apiService: APIService
  ) async throws -> TMDBTargetResolution? {
    guard let request = mappingRequest(for: item, apiService: apiService),
      let mapping = try await apiService.fetchMediaMappingMatch(
        identity: request.identity, type: request.rawType, season: item.season)
    else {
      return nil
    }
    return mappingTMDBTarget(for: item, mapping: mapping, request: request)
  }

  private struct MappingRequest {
    let identity: MediaIdentity
    let rawType: String
    let mediaType: String
    /// 请求时带的来源季号；映射必须回显它，否则可能是整剧关系，不能拿来给分季卡片选季。
    let season: Int?
  }

  private static func mappingRequest(
    for item: MediaInfo,
    apiService: APIService
  ) -> MappingRequest? {
    guard let identity = item.identity,
      let source = MediaIdentifier.normalizeSource(identity.source),
      source != "themoviedb",
      let mediaId = MediaIdentifier.normalizedString(identity.mediaId),
      let rawType = item.type
    else {
      return nil
    }
    let mediaType = apiService.normalizeMediaType(rawType)
    guard mediaType == "movie" || mediaType == "tv" else { return nil }
    return MappingRequest(
      identity: MediaIdentity(source: source, mediaId: mediaId),
      rawType: rawType,
      mediaType: mediaType,
      season: mediaType == "tv" ? item.season : nil)
  }

  private static func mappingTMDBTarget(
    for item: MediaInfo,
    mapping: MediaMapping,
    request: MappingRequest
  ) -> TMDBTargetResolution? {
    // 只接受与请求身份回显一致、且 TMDB 类型合法的映射，防止把别人的关系当成当前条目的目标。
    guard mapping.media_source == request.identity.source,
      mapping.media_id == request.identity.mediaId,
      mapping.type == request.mediaType,
      mapping.season == request.season,
      mapping.tmdb_id > 0,
      mapping.tmdb_type == "movie" || mapping.tmdb_type == "tv"
    else {
      return nil
    }

    let targetType = mapping.tmdb_type == "movie" ? "电影" : "电视剧"
    let targetSeason = mapping.tmdb_type == "tv" ? mapping.tmdb_season : nil
    var target = tmdbJumpTarget(
      for: item, tmdbId: mapping.tmdb_id, type: targetType, season: .some(targetSeason))
    target.tmdbSeasonHint = targetSeason
    return TMDBTargetResolution(origin: request.identity, target: target)
  }

  static func tmdbJumpTarget(
    for item: MediaInfo,
    tmdbId: Int,
    type: String? = nil,
    season: Int?? = nil
  ) -> MediaInfo {
    let resolvedSeason: Int?
    switch season {
    case .some(let value): resolvedSeason = value
    case .none: resolvedSeason = item.season
    }
    return MediaInfo(
      tmdb_id: tmdbId,
      douban_id: nil,
      bangumi_id: nil,
      imdb_id: nil,
      tvdb_id: nil,
      source: "tmdb",
      mediaid_prefix: nil,
      media_id: nil,
      title: item.title,
      original_title: item.original_title,
      original_name: item.original_name,
      names: item.names,
      type: type ?? item.type,
      year: item.year,
      season: resolvedSeason,
      // 必须将图像路径设为 nil。
      // 此处创建的 MediaInfo 是一个用于导航的“部分对象”。
      // 如果保留旧的 poster/backdrop 路径，新页面在加载完成前会短暂显示旧页面的图像，导致闪烁。
      // 将其设为 nil 可确保新页面在获取到自己的完整详情前不显示任何背景。
      // 加载动画需要复用源海报时，由导航 entry 单独携带。
      // 禁止为复用加载海报而修改这里的 nil，否则会重新引入旧图闪烁。
      poster_path: nil,
      backdrop_path: nil,
      overview: item.overview,
      vote_average: item.vote_average,
      popularity: item.popularity,
      season_info: nil,  // 该信息将在 MediaDetailView 中获取
      collection_id: item.collection_id,
      directors: item.directors,
      actors: item.actors,
      episode_group: item.episode_group,
      runtime: item.runtime,
      release_date: item.release_date,
      original_language: item.original_language,
      production_countries: item.production_countries,
      genres: item.genres,
      category: item.category
    )
  }
}
