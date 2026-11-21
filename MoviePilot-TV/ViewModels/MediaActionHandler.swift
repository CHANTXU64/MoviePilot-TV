import SwiftUI
import Combine

/// 共享映射、按需查找或名称识别得到的 TMDB 目标，连同请求时的原来源身份。
struct TMDBTargetResolution {
  let origin: MediaIdentity
  let target: MediaInfo
  /// 只靠片名、年份猜出，后端没有确认过这层关系。
  var isNameRecognized = false
}

@MainActor
class MediaActionHandler: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  @Published var isRecognizingTmdb = false
  @Published var showTMDBNotFoundAlert = false

  func cancelPresentation() {
    showTMDBNotFoundAlert = false
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
  static func recognizedTMDBTarget(
    for item: MediaInfo,
    tmdbId: Int,
    apiService: APIService
  ) -> TMDBTargetResolution? {
    guard let request = mappingRequest(for: item, apiService: apiService) else { return nil }
    let isTV = request.mediaType == "tv"
    var target = tmdbJumpTarget(
      for: item, tmdbId: tmdbId, type: isTV ? "电视剧" : "电影",
      season: .some(isTV ? item.season : nil))
    target.tmdbSeasonHint = isTV ? item.season : nil
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
      mediaType: mediaType)
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
