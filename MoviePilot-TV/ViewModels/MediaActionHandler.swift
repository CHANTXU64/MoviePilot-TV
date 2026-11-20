import SwiftUI
import Combine

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
  /// - Parameter useSharedMapping: 是否先查非 TMDB 来源到 TMDB 的共享映射。
  ///   「搜索资源」这类不依赖 TMDB 目标的入口传 `false`，避免为辅助查询多等 1.5s。
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
      let title = item.title?.trimmingCharacters(in: .whitespaces) ?? ""
      let canTrySharedMapping =
        useSharedMapping && apiService.supportsSharedMediaMapping && item.identity != nil

      if canTrySharedMapping {
        isRecognizingTmdb = true
        do {
          if let target = try await Self.sharedTMDBTarget(for: item, apiService: apiService) {
            isRecognizingTmdb = false
            guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
            return target
          }
        } catch is CancellationError {
          isRecognizingTmdb = false
          return nil
        } catch {
          // 映射是辅助查询：失败不能让原本可用的名称识别也失效。
          Logger.error("TMDB 共享映射查询失败: \(error)")
        }
      }

      // 无标题且映射未命中，不属于"媒体不存在"，直接返回不弹提示。
      guard !title.isEmpty else {
        isRecognizingTmdb = false
        return nil
      }
      if !canTrySharedMapping { isRecognizingTmdb = true }
      do {
        tmdbIdToUse = try await apiService.recognizeTmdbId(
          title: title,
          year: item.year,
          type: item.type
        )
      } catch is CancellationError {
        isRecognizingTmdb = false
        return nil
      } catch {
        // 网络/后端/解码失败不是"媒体不存在"，不弹误导提示。
        Logger.error("TMDB 识别失败: \(error)")
        isRecognizingTmdb = false
        return nil
      }
      isRecognizingTmdb = false
    }

    guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }

    guard let tmdbId = tmdbIdToUse else {
      // 识别确实无匹配。但「搜索资源」这类调用方会自愈为标题搜索，弹窗只会拦住用户（F-122）。
      if notifyWhenUnrecognized {
        showTMDBNotFoundAlert = true
      }
      return nil
    }

    return Self.tmdbJumpTarget(for: item, tmdbId: tmdbId)
  }

  /// 共享映射优先的完整 TMDB 目标；返回 nil 表示没有可用关系，调用方继续名称识别。
  /// 只接受与请求身份回显一致、且 TMDB 类型合法的映射，防止把别人的关系当成当前条目的目标。
  static func sharedTMDBTarget(
    for item: MediaInfo,
    apiService: APIService
  ) async throws -> MediaInfo? {
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

    guard
      let mapping = try await apiService.fetchMediaMapping(
        identity: MediaIdentity(source: source, mediaId: mediaId),
        type: rawType,
        season: item.season
      )
    else {
      return nil
    }
    guard mapping.media_source == source,
      mapping.media_id == mediaId,
      mapping.type == mediaType,
      mapping.tmdb_id > 0,
      mapping.tmdb_type == "movie" || mapping.tmdb_type == "tv"
    else {
      return nil
    }

    let targetType = mapping.tmdb_type == "movie" ? "电影" : "电视剧"
    let targetSeason = mapping.tmdb_type == "tv" ? (mapping.tmdb_season ?? item.season) : nil
    return tmdbJumpTarget(
      for: item, tmdbId: mapping.tmdb_id, type: targetType, season: .some(targetSeason))
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
