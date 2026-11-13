import Foundation

/// 播放界面的条目信息以 MoviePilot 的为准（见 `PlaybackMetadata`），这里负责从 MoviePilot 取：
/// 详情页集列表起播的那一集直接用集列表；其他入口（详情页的「播放」、首页最近入库）按服务器条目的外部编号查 MoviePilot 详情。
/// 用户手动下载、MoviePilot 认不出的资源查不到，返回 nil，界面用媒体服务器适配器给的信息。
@MainActor
enum PlaybackMetadataLookup {
  /// 查询最多等这么久。MoviePilot 慢或连不上时不拖慢起播，界面先用媒体服务器的信息。
  nonisolated static let timeout: Duration = .seconds(3)

  /// 详情页集列表里的一集：集名、简介、播出日期、评分和剧照来自集列表，剧名和海报来自详情页。
  static func metadata(for queued: QueuedEpisode) -> PlaybackMetadata {
    var metadata = queued.episode.playbackMetadata(
      seriesName: queued.context.seriesName,
      stillURL: APIService.shared.getSeasonPosterURL(posterPath: queued.episode.stillPath, mediaPosterPath: nil))
    metadata.posterURL = APIService.shared.getPosterImageUrl(posterPath: queued.context.seriesPosterPath)
    return metadata
  }

  /// 按服务器条目查 MoviePilot。电影查详情；单集查所属剧的详情和这一季的集列表，再找到这一集（见 `episode(matching:in:)`）。
  /// `media` 是详情页已有的 MoviePilot 详情（从详情页起播时），类型对得上就直接用，不再查。
  /// 认不出、查不到、出错或超过 `timeout` 都返回 nil；单集找不到对应的集时只给剧名和海报。
  static func metadata(
    for item: ServerMediaItem, media: MediaInfo?, on connection: any MediaServerConnection, api: APIService
  ) async -> PlaybackMetadata? {
    await withinTimeout {
      switch item.kind {
      case .movie: await movieMetadata(for: item, media: media, api: api)
      case .episode: await episodeMetadata(for: item, media: media, on: connection, api: api)
      case .series, .other: nil
      }
    }
  }

  /// 单集对应到 MoviePilot 集列表（TMDB 默认顺序）里的哪一集，身份规则与 `EpisodeMatching` 相同：服务器条目有 TMDB 单集编号时
  /// 只认编号，这一季的列表里没有它（比如服务器按剧集组分季）就不认，不再按集号凑；没有编号时才按集号，
  /// 两边都有播出日期又对不上（服务器按别的顺序编号）时也不认，免得显示别的集的简介。
  nonisolated static func episode(matching item: ServerMediaItem, in list: [TmdbEpisode]) -> TmdbEpisode? {
    if let id = item.tmdbEpisodeID { return list.first { $0.id == id } }
    guard let number = item.episodeNumber, let hit = list.first(where: { $0.episodeNumber == number }) else {
      return nil
    }
    if case .differs = AirDateCheck.compare(server: item.premiereDate, moviePilot: hit.airDate) { return nil }
    return hit
  }

  /// 按外部编号查 MoviePilot 详情时用的身份：TMDB 优先，其次豆瓣。服务器条目没有这两种编号时为 nil。
  nonisolated static func lookupMedia(externalIDs: [String: String], type: String) -> MediaInfo? {
    if let tmdb = externalIDs["tmdb"].flatMap(Int.init), let tmdbID = MediaIdentifier.validNumericIdentifier(tmdb) {
      return MediaInfo(tmdb_id: tmdbID, source: "themoviedb", type: type)
    }
    if let douban = trimmedNonEmpty([externalIDs["douban"]]) {
      return MediaInfo(douban_id: douban, source: "douban", type: type)
    }
    return nil
  }

  // MARK: - 电影、单集

  private static func movieMetadata(for item: ServerMediaItem, media: MediaInfo?, api: APIService) async
    -> PlaybackMetadata?
  {
    guard let detail = await detail(of: item, type: "电影", known: media, api: api) else { return nil }
    return PlaybackMetadata(
      title: detail.title, overview: detail.overview, premiereDate: detail.release_date,
      communityRating: detail.vote_average, posterURL: api.getPosterImageUrl(posterPath: detail.poster_path),
      thumbnailURL: api.getBackdropImageUrl(backdropPath: detail.backdrop_path))
  }

  private static func episodeMetadata(
    for item: ServerMediaItem, media: MediaInfo?, on connection: any MediaServerConnection, api: APIService
  ) async -> PlaybackMetadata? {
    let series: ServerMediaItem?
    if media?.type == "电视剧" {
      series = nil
    } else {
      guard let seriesID = item.seriesID,
        let found = try? await connection.item(id: seriesID, timeout: MediaServerHTTP.quickTimeout)
      else { return nil }
      series = found
    }
    guard let detail = await detail(of: series, type: "电视剧", known: media, api: api) else { return nil }
    var metadata = PlaybackMetadata(
      seriesName: detail.title, posterURL: api.getPosterImageUrl(posterPath: detail.poster_path))
    guard let tmdbID = MediaIdentifier.validNumericIdentifier(detail.tmdb_id), let season = item.seasonNumber,
      let list = try? await api.fetchTmdbEpisodes(tmdbID: tmdbID, season: season, episodeGroup: nil),
      let episode = episode(matching: item, in: list)
    else { return metadata }
    let still = api.getSeasonPosterURL(posterPath: episode.stillPath, mediaPosterPath: nil)
    metadata = MoviePilotEpisode(episode, season: season, index: 0)
      .playbackMetadata(seriesName: metadata.seriesName, stillURL: still)
      .filling(metadata)
    return metadata
  }

  /// MoviePilot 详情：详情页给的类型对得上就用它；否则按服务器条目的外部编号查。查到的详情没有标题时当作认不出。
  private static func detail(
    of item: ServerMediaItem?, type: String, known: MediaInfo?, api: APIService
  ) async -> MediaInfo? {
    if let known, known.type == type { return known }
    guard let item, let query = lookupMedia(externalIDs: item.externalIDs, type: type),
      let detail = try? await api.fetchMediaDetail(media: query), trimmedNonEmpty([detail.title]) != nil
    else { return nil }
    return detail
  }

  /// 在 `timeout` 内等 `work` 的结果，超时返回 nil 并取消它。不等被取消的查询真正停下（任务组会等），
  /// 免得某个请求不及时响应取消时又把起播拖住；调用方被取消时也取消查询。
  private static func withinTimeout<T: Sendable>(
    _ work: @escaping @MainActor @Sendable () async -> T?
  ) async -> T? {
    let query = Task { @MainActor in await work() }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let first = FirstResult(continuation)
        let timer = Task { @MainActor in
          guard (try? await Task.sleep(for: timeout)) != nil else { return }
          query.cancel()
          first.finish(nil)
        }
        Task { @MainActor in
          let value = await query.value
          timer.cancel()
          first.finish(value)
        }
      }
    } onCancel: {
      query.cancel()
    }
  }

  /// 只认先到的一个结果。
  private final class FirstResult<T: Sendable> {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
      self.continuation = continuation
    }

    func finish(_ value: T?) {
      continuation?.resume(returning: value)
      continuation = nil
    }
  }
}
