#if DEBUG
import Foundation

/// 「媒体详情」域的场景附加参数。
///
/// 详情页的已订阅 / 已入库 / 分季订阅等状态无法只靠「有无数据」区分，
/// 这里用 context 让同一份 fixture 在不同场景返回不同状态，避免为每个状态复制接口实现。
enum UIPreviewDetailContext {
  /// `"1"`：媒体服务器中已入库。
  static let libraryItem = "detail.libraryItem"
  /// `"subscribed"` / `"paused"`：详情媒体已有订阅。
  static let subscription = "detail.subscription"
  /// `"1"`：分季管理页命中已订阅的分季。
  static let seasonSubscriptions = "detail.seasonSubscriptions"
  /// `"1"`：详情返回 12 季，用于季选择菜单溢出。
  static let manySeasons = "detail.manySeasons"
  /// `"1"`：详情带剧集组，用于剧集分组入口。
  static let episodeGroup = "detail.episodeGroup"
}

// MARK: - 媒体详情

extension UIPreviewFixtures {
  // MARK: 媒体

  static func detailMovieMedia(
    id: Int = 90_101,
    title: String = "荒原长路",
    doubanId: String? = "34567890"
  ) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      douban_id: doubanId,
      source: "themoviedb",
      title: title,
      original_title: "The Long Road",
      names: [title, "The Long Road"],
      type: "电影",
      year: "2025",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview:
        "一条穿过荒原的公路把两个陌生人绑在同一辆旧车上。沿途的加油站、废弃影院和夜里的信号塔，逐渐拼出他们各自想离开的过去。",
      vote_average: 7.9,
      popularity: 96,
      directors: [person(id: 70_101, name: "周野")],
      actors: [
        person(id: 70_102, name: "宋迟", character: "司机"),
        person(id: 70_103, name: "苑青", character: "搭车人"),
      ],
      runtime: 128,
      release_date: "2025-10-17",
      original_language: "zh",
      production_countries: [country("中国大陆")],
      genres: [genre("剧情"), genre("公路")],
      category: "电影"
    )
  }

  static func detailTVMedia(
    id: Int = 90_201,
    title: String = "边境信号",
    doubanId: String? = "34567891",
    seasons: [TmdbSeason]? = nil,
    episodeGroup: String? = nil
  ) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      douban_id: doubanId,
      source: "themoviedb",
      title: title,
      original_title: "Frontier Signal",
      names: [title, "Frontier Signal"],
      type: "电视剧",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview:
        "一支深空维护小队在边境航道收到异常信号，必须在有限补给和分裂意见中决定是否继续追踪。每一次分季的停靠，都让「信号来自谁」这个问题更难回答。",
      vote_average: 8.4,
      popularity: 125,
      season_info: seasons ?? previewSeasons,
      directors: [person(id: 70_201, name: "林原真")],
      actors: [
        person(id: 70_202, name: "高桥遥", character: "领航员"),
        person(id: 70_203, name: "陈述", character: "工程师"),
        person(id: 70_204, name: "林晚", character: "通讯员"),
      ],
      episode_group: episodeGroup,
      runtime: 52,
      release_date: "2026-01-12",
      original_language: "ja",
      production_countries: [country("日本")],
      genres: [genre("科幻"), genre("冒险")],
      category: "剧集"
    )
  }

  /// 豆瓣来源的详情：没有 TMDB ID，用来展示来源徽章与 TMDB 识别 / 跳转入口。
  static func detailExternalMovieMedia() -> MediaInfo {
    MediaInfo(
      douban_id: "34567892",
      source: "douban",
      title: "边境信号：失联航线",
      original_title: "Frontier Signal: Lost Route",
      names: ["边境信号：失联航线"],
      type: "电影",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview:
        "边境信号的首部剧场版。失联的补给舰在航道尽头重新出现，但船上的时间比外界慢了七年。",
      vote_average: 8.1,
      popularity: 88,
      directors: [person(id: 70_205, name: "久保田淳")],
      actors: [
        person(id: 70_202, name: "高桥遥", character: "领航员"),
        person(id: 70_203, name: "陈述", character: "工程师"),
      ],
      runtime: 112,
      release_date: "2026-08-21",
      original_language: "ja",
      production_countries: [country("日本")],
      genres: [genre("科幻"), genre("悬疑")],
      category: "电影"
    )
  }

  // MARK: 详情

  static func detailMediaDetail(media: MediaInfo) async throws -> MediaInfo {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailMediaDetail)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailMediaDetail) {
      return media
    }

    let backend = UIPreviewBackend.shared
    if media.source == "douban" || (media.tmdb_id == nil && media.douban_id != nil) {
      return detailExternalMovieMedia()
    }
    if media.type == "电视剧" {
      if backend.context(UIPreviewDetailContext.manySeasons) == "1" {
        return detailTVMedia(seasons: previewManySeasons)
      }
      if backend.context(UIPreviewDetailContext.episodeGroup) == "1" {
        return detailTVMedia(episodeGroup: "preview-alt")
      }
      return detailTVMedia()
    }
    return detailMovieMedia()
  }

  // MARK: 推荐 / 相似 / 演员

  static func detailRecommendations(detail: MediaInfo, page: Int) async throws -> [MediaInfo] {
    let key =
      page > 1
      ? UIPreviewBehaviorKey.detailRecommendationsMore
      : UIPreviewBehaviorKey.detailRecommendations
    try await UIPreviewBackend.shared.gate(key)
    if UIPreviewBackend.shared.isEmpty(for: key) {
      return []
    }
    return detailRecommendationItems(page: page)
  }

  static func detailSimilar(detail: MediaInfo, page: Int) async throws -> [MediaInfo] {
    let key =
      page > 1 ? UIPreviewBehaviorKey.detailSimilarMore : UIPreviewBehaviorKey.detailSimilar
    try await UIPreviewBackend.shared.gate(key)
    if UIPreviewBackend.shared.isEmpty(for: key) {
      return []
    }
    return detailSimilarItems(page: page)
  }

  static func detailActors(detail: MediaInfo, page: Int) async throws -> [Person] {
    let key = page > 1 ? UIPreviewBehaviorKey.detailActorsMore : UIPreviewBehaviorKey.detailActors
    try await UIPreviewBackend.shared.gate(key)
    if UIPreviewBackend.shared.isEmpty(for: key) {
      return []
    }
    return detailActorItems(page: page)
  }

  // MARK: 豆瓣

  static func detailDoubanComments(
    doubanId: String,
    typeName: String,
    start: Int,
    count: Int
  ) async throws -> DoubanCommentPage {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailDoubanComments)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailDoubanComments) || start > 0 {
      return decode(
        DoubanCommentPage.self,
        #"{"start":\#(start),"count":0,"total":3,"items":[]}"#
      )
    }
    return decode(
      DoubanCommentPage.self,
      #"""
      {
        "start": 0,
        "count": 3,
        "total": 3,
        "items": [
          {
            "id": "preview-comment-1",
            "comment": "公路片的外壳，讲的是两个人如何承认自己已经回不去。最后十分钟的沉默比任何台词都响。",
            "rating": 4.5,
            "vote_count": 128,
            "create_time": "2026-02-14 21:08:00",
            "author": {"id": "preview-user-1", "name": "夜航员", "avatar": null, "url": null},
            "url": "https://movie.douban.com/review/1/"
          },
          {
            "id": "preview-comment-2",
            "comment": "摄影和声音都很克制，长镜头没有炫技感。缺点是中段加油站那场戏略拖。",
            "rating": 4.0,
            "vote_count": 64,
            "create_time": "2026-02-09 09:31:00",
            "author": {"id": "preview-user-2", "name": "北纬三十度", "avatar": null, "url": null},
            "url": "https://movie.douban.com/review/2/"
          },
          {
            "id": "preview-comment-3",
            "comment": "看完想立刻再走一次那条路。配乐值得单独循环。",
            "rating": 5.0,
            "vote_count": 41,
            "create_time": "2026-01-28 23:47:00",
            "author": {"id": "preview-user-3", "name": "慢速快门", "avatar": null, "url": null},
            "url": "https://movie.douban.com/review/3/"
          }
        ]
      }
      """#
    )
  }

  static func detailDoubanReviews(
    doubanId: String,
    typeName: String,
    start: Int,
    count: Int
  ) async throws -> DoubanReviewPage {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailDoubanReviews)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailDoubanReviews) || start > 0 {
      return decode(
        DoubanReviewPage.self,
        #"{"start":\#(start),"count":0,"total":2,"items":[]}"#
      )
    }
    return decode(
      DoubanReviewPage.self,
      #"""
      {
        "start": 0,
        "count": 2,
        "total": 2,
        "items": [
          {
            "id": "preview-review-1",
            "title": "在荒原上，沉默是一种导航",
            "abstract": "影片把「离开」拍成一种需要练习的技能。两个主角都不是主动上路的人，他们只是被同一场故障留在了同一条公路上。导演很少给情绪特写，更多时候让环境替人物说话。",
            "rating": 4.5,
            "useful_count": 356,
            "create_time": "2026-02-02 18:20:00",
            "author": {"id": "preview-user-4", "name": "远光灯", "avatar": null, "url": null},
            "url": "https://movie.douban.com/review/10/"
          },
          {
            "id": "preview-review-2",
            "title": "公路片的减法",
            "abstract": "它没有把公路当作自由的隐喻，而是当作一条必须被走完的流程。每一次停靠都像一次被迫的复盘，人物在加油、修车、等天亮之间慢慢卸下防备。",
            "rating": 4.0,
            "useful_count": 187,
            "create_time": "2026-01-25 11:05:00",
            "author": {"id": "preview-user-5", "name": "备用轮胎", "avatar": null, "url": null},
            "url": "https://movie.douban.com/review/11/"
          }
        ]
      }
      """#
    )
  }

  // MARK: 订阅 / 入库

  static func detailMediaServerItemRef(media: MediaInfo) async throws -> MediaServerItemRef? {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailMediaServerItemRef)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailMediaServerItemRef) {
      return nil
    }
    guard UIPreviewBackend.shared.context(UIPreviewDetailContext.libraryItem) == "1" else {
      return nil
    }
    return MediaServerItemRef(itemID: "preview-item-9001", server: "Emby · 客厅")
  }

  static func detailSubscriptionLookup(
    media: MediaInfo,
    season: Int?,
    includeVideoMetadataFallback: Bool
  ) async throws -> SubscriptionLookupResult? {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSubscriptionLookup)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailSubscriptionLookup) {
      return nil
    }
    let state = UIPreviewBackend.shared.context(UIPreviewDetailContext.subscription)
    guard state == "subscribed" || state == "paused" else { return nil }
    return SubscriptionLookupResult(
      id: 97_001,
      mediaId: media.apiMediaId ?? "tmdb:90101",
      isResolvedMediaId: true
    )
  }

  static func detailSubscription(id: Int) async throws -> Subscribe {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSubscription)
    let state =
      UIPreviewBackend.shared.context(UIPreviewDetailContext.subscription) == "paused"
      ? "S" : "R"
    return detailMovieSubscribe(id: id, state: state)
  }

  static func detailAddSubscription(request: SubscribeRequest, subscribe: Subscribe) async throws
    -> Int?
  {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailAddSubscription)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailAddSubscription) {
      return nil
    }
    return 97_901
  }

  static func detailUpdateSubscriptionStatus(
    id: Int,
    state: String
  ) async throws -> (success: Bool, message: String?) {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailUpdateSubscriptionStatus)
    return (true, nil)
  }

  static func detailSaveSubscription(
    original: Subscribe,
    draft: Subscribe
  ) async throws -> (success: Bool, message: String?) {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSaveSubscription)
    return (true, nil)
  }

  static func detailDeleteSubscriptionResult(
    media: MediaInfo,
    season: Int?
  ) async throws -> (success: Bool, message: String?) {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailDeleteSubscription)
    return (true, nil)
  }

  static func detailSearchSubscription(id: Int) async throws -> Bool {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSearchSubscription)
    return true
  }

  /// 订阅列表路由：分季场景返回带 season 的订阅，其余场景回退首页订阅 fixture。
  ///
  /// 分季管理页读取的是 `fetchSubscriptions()` 的整表，不是逐季 lookup：
  /// 带 season 的场景返回逐季订阅，其余场景回退首页订阅 fixture。
  static func detailSubscriptions() async throws -> [Subscribe] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSubscriptions)
    guard UIPreviewBackend.shared.context(UIPreviewDetailContext.seasonSubscriptions) == "1"
    else {
      return try await homeSubscriptions()
    }
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailSubscriptions) {
      return []
    }
    return [
      detailSeasonSubscribe(id: 97_201, season: 1, state: "R"),
      detailSeasonSubscribe(id: 97_202, season: 2, state: "S"),
    ]
  }

  // MARK: 分季 / 剧集

  static func detailMediaSeasons(
    media: MediaInfo,
    allSeasons: Bool
  ) async throws -> [TmdbSeason] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSeasons)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailSeasons) {
      return []
    }
    if UIPreviewBackend.shared.context(UIPreviewDetailContext.manySeasons) == "1" {
      return previewManySeasons
    }
    return previewSeasons
  }

  static func detailGroupSeasons(groupId: String) async throws -> [TmdbSeason] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailGroupSeasons)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailGroupSeasons) {
      return []
    }
    return [
      season(number: 1, name: "第 1 季", episodes: 12, vote: 8.5),
      season(number: 2, name: "第 2 季", episodes: 8, vote: 8.1),
    ]
  }

  static func detailEpisodeGroups(tmdbId: Int) async throws -> [EpisodeGroup] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailEpisodeGroups)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailEpisodeGroups) {
      return []
    }
    return previewEpisodeGroups
  }

  static func detailSeasonEpisodes(
    tmdbID: Int,
    season: Int,
    episodeGroup: String?
  ) async throws -> [TmdbEpisode] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailEpisodes)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailEpisodes) {
      return []
    }
    let episodeCount = season == 2 ? 8 : (season >= 3 ? 0 : 12)
    guard episodeCount > 0 else { return [] }
    return (1...episodeCount).map { number in
      TmdbEpisode(
        id: 90_800 + number,
        episodeNumber: number,
        seasonNumber: season,
        name: number == 1 ? "停靠点 \(number)：静默频率" : "停靠点 \(number)",
        overview: "补给船在编号 \(number) 的停靠点短暂停留，通讯组捕捉到一段无法定位来源的重复信号。",
        stillPath: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
        airDate: "2026-01-\(String(format: "%02d", min(number, 28)))",
        runtime: 52
      )
    }
  }

  static func detailSeasonsNotExists(mediaInfo: MediaInfo) async throws -> [NotExistMediaInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailSeasonsNotExists)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailSeasonsNotExists) {
      return []
    }
    return [
      NotExistMediaInfo(season: 2, episodes: [7, 8, 9, 10], total_episode: 10, start_episode: 7)
    ]
  }

  // MARK: 字幕

  static func detailDownloadDirectories() async throws -> [DownloadDirectory] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailDownloadDirectories)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailDownloadDirectories) {
      return []
    }
    return decode(
      [DownloadDirectory].self,
      #"""
      [
        {
          "name": "电视剧",
          "storage": "local",
          "download_path": "/downloads/tv",
          "save_path": "/media/TV/边境信号",
          "priority": 1,
          "media_type": "电视剧",
          "media_category": "剧集"
        },
        {
          "name": "电影",
          "storage": "nas",
          "download_path": "/downloads/movie",
          "save_path": "/media/Movies",
          "priority": 2,
          "media_type": "电影",
          "media_category": "电影"
        }
      ]
      """#
    )
  }

  static func detailDownloadSubtitle(
    subtitle: SubtitleInfo,
    mediaSource: String,
    mediaId: String,
    savePath: String?
  ) async throws {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailDownloadSubtitle)
  }

  // MARK: 合集 / 人物

  static func detailCollection(
    collectionId: Int,
    page: Int,
    title: String
  ) async throws -> [MediaInfo] {
    let key =
      page > 1 ? UIPreviewBehaviorKey.detailCollectionMore : UIPreviewBehaviorKey.detailCollection
    try await UIPreviewBackend.shared.gate(key)
    if UIPreviewBackend.shared.isEmpty(for: key) {
      return []
    }
    return detailCollectionItems(page: page)
  }

  static func detailPersonDetail(personId: String, source: String?) async throws -> Person {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailPerson)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailPerson) {
      return person(id: 71_001, name: "周野")
    }
    return person(
      id: 71_001,
      name: "周野",
      biography:
        "周野，电影导演、编剧。早年拍摄纪录短片，关注公路、迁徙与通信基础设施。长片处女作《荒原长路》以极简的对白和大量环境声获得关注，之后继续在类型片框架里讨论人与距离。"
    )
  }

  static func detailPersonCredits(personId: String, source: String?, page: Int) async throws
    -> [MediaInfo]
  {
    let key =
      page > 1 ? UIPreviewBehaviorKey.detailPersonCreditsMore : UIPreviewBehaviorKey.detailPersonCredits
    try await UIPreviewBackend.shared.gate(key)
    if UIPreviewBackend.shared.isEmpty(for: key) {
      return []
    }
    return detailPersonCreditItems(page: page)
  }

  // MARK: TMDB 识别

  static func detailRecognizeTmdb(title: String, year: String?, type: String?) async throws
    -> Int?
  {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.detailRecognizeTmdb)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.detailRecognizeTmdb) {
      return nil
    }
    return 90_101
  }
}

// MARK: - fixture 数据

extension UIPreviewFixtures {
  private static func detailRecommendationItems(page: Int) -> [MediaInfo] {
    if page > 2 { return [] }
    if page > 1 {
      return [
        movieMedia(id: 90_501, title: "夜行列车"),
        movieMedia(id: 90_502, title: "无声站台"),
        movieMedia(id: 90_503, title: "南岸来客"),
        movieMedia(id: 90_504, title: "冬季航线"),
      ]
    }
    return [
      movieMedia(id: 90_511, title: "灯塔以北"),
      movieMedia(id: 90_512, title: "慢速公路"),
      movieMedia(id: 90_513, title: "港口来信"),
      movieMedia(id: 90_514, title: "候鸟时刻"),
      movieMedia(id: 90_515, title: "空房间"),
      movieMedia(id: 90_516, title: "六月回声"),
    ]
  }

  private static func detailSimilarItems(page: Int) -> [MediaInfo] {
    if page > 2 { return [] }
    if page > 1 {
      return [
        movieMedia(id: 90_521, title: "远方来客"),
        movieMedia(id: 90_522, title: "站台尽头"),
        movieMedia(id: 90_523, title: "夜班司机"),
      ]
    }
    return [
      movieMedia(id: 90_531, title: "同一条路"),
      movieMedia(id: 90_532, title: "信号盲区"),
      movieMedia(id: 90_533, title: "旧车票"),
      movieMedia(id: 90_534, title: "逆光行驶"),
      movieMedia(id: 90_535, title: "公路尽头"),
    ]
  }

  private static func detailActorItems(page: Int) -> [Person] {
    if page > 2 { return [] }
    if page > 1 {
      return [
        person(id: 71_111, name: "许知远", character: "加油站老板"),
        person(id: 71_112, name: "叶青", character: "电台主播"),
        person(id: 71_113, name: "沈默", character: "修车工"),
        person(id: 71_114, name: "路遥", character: "搭车学生"),
        person(id: 71_115, name: "程野", character: "巡警"),
        person(id: 71_116, name: "白露", character: "旅店老板"),
      ]
    }
    return [
      person(id: 71_101, name: "宋迟", character: "司机"),
      person(id: 71_102, name: "苑青", character: "搭车人"),
      person(id: 71_103, name: "周野", character: "导演 / 客串"),
      person(id: 71_104, name: "林原真", character: "制片人"),
      person(id: 71_105, name: "高桥遥", character: "配音"),
      person(id: 71_106, name: "陈默", character: "摄影指导"),
      person(id: 71_107, name: "苏晚", character: "剪辑"),
      person(id: 71_108, name: "顾南", character: "配乐"),
    ]
  }

  private static func detailCollectionItems(page: Int) -> [MediaInfo] {
    if page > 2 { return [] }
    if page > 1 {
      return [
        movieMedia(id: 90_611, title: "边境信号：归航"),
        movieMedia(id: 90_612, title: "边境信号：静默带"),
        movieMedia(id: 90_613, title: "边境信号：远日点"),
      ]
    }
    return [
      movieMedia(id: 90_601, title: "边境信号：失联航线"),
      movieMedia(id: 90_602, title: "边境信号：零号停靠点"),
      movieMedia(id: 90_603, title: "边境信号：回声"),
      movieMedia(id: 90_604, title: "边境信号：夜航"),
      movieMedia(id: 90_605, title: "边境信号：外层"),
      movieMedia(id: 90_606, title: "边境信号：返程"),
    ]
  }

  private static func detailPersonCreditItems(page: Int) -> [MediaInfo] {
    if page > 2 { return [] }
    if page > 1 {
      return [
        movieMedia(id: 90_711, title: "长夜将尽"),
        movieMedia(id: 90_712, title: "无人区来信"),
        movieMedia(id: 90_713, title: "南风过境"),
      ]
    }
    return [
      movieMedia(id: 90_701, title: "荒原长路"),
      movieMedia(id: 90_702, title: "公路尽头"),
      movieMedia(id: 90_703, title: "失重的下午"),
      movieMedia(id: 90_704, title: "九月站台"),
      movieMedia(id: 90_705, title: "潮汐之间"),
      movieMedia(id: 90_706, title: "北方来信"),
      movieMedia(id: 90_707, title: "慢速快门"),
      movieMedia(id: 90_708, title: "回声测试"),
      movieMedia(id: 90_709, title: "夜航日志"),
      movieMedia(id: 90_710, title: "终点之前"),
    ]
  }

  private static func detailMovieSubscribe(id: Int, state: String) -> Subscribe {
    Subscribe(
      id: id,
      name: "荒原长路",
      year: "2025",
      type: "电影",
      poster: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      vote: 7.9,
      state: state,
      last_update: "2026-11-11 16:00:00",
      tmdbid: 90_101,
      media_source: "themoviedb",
      media_id: "90101",
      best_version: 1,
      quality: "WEB-DL",
      resolution: "1080p",
      sites: [1, 3],
      downloader: "qb-main",
      save_path: "/downloads/movie",
      description: "预览订阅：荒原长路"
    )
  }

  private static func detailSeasonSubscribe(id: Int, season: Int, state: String) -> Subscribe {
    Subscribe(
      id: id,
      name: "边境信号",
      year: "2026",
      type: "电视剧",
      season: season,
      poster: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      vote: 8.4,
      state: state,
      last_update: "2026-11-11 16:00:00",
      tmdbid: 90_201,
      media_source: "themoviedb",
      media_id: "90201",
      best_version: 1,
      total_episode: season == 2 ? 10 : 12,
      start_episode: 1,
      lack_episode: state == "S" ? nil : 3,
      quality: "WEB-DL",
      resolution: "1080p",
      sites: [1, 3],
      downloader: "qb-main",
      save_path: "/downloads/tv",
      description: "预览分季订阅：边境信号"
    )
  }
}

// MARK: - 场景直接使用的展示 fixture

extension UIPreviewFixtures {
  /// 订阅面板「已订阅 / 已暂停」示例。面板不会自行请求详情，字段需要完整可保存。
  static func detailMovieSubscription(state: String = "R") -> Subscribe {
    detailMovieSubscribe(id: 97_001, state: state)
  }

  /// 订阅面板「可订阅 / 提交中 / 失败」示例。id 为空表示新增。
  static func detailNewMovieSubscription() -> Subscribe {
    Subscribe(
      name: "荒原长路",
      year: "2025",
      type: "电影",
      poster: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      vote: 7.9,
      tmdbid: 90_101,
      media_source: "themoviedb",
      media_id: "90101",
      best_version: 1,
      quality: "WEB-DL",
      resolution: "1080p",
      sites: [1, 3],
      downloader: "qb-main",
      save_path: "/downloads/movie",
      description: "预览新增订阅：荒原长路"
    )
  }

  /// 豆瓣短评阅读页条目。
  static var detailCommentEntry: DoubanDiscussionEntry {
    DoubanDiscussionEntry(
      comment: decode(
        DoubanComment.self,
        #"""
        {
          "id": "preview-comment-reader",
          "comment": "公路片的外壳，讲的是两个人如何承认自己已经回不去。最后十分钟的沉默比任何台词都响。摄影没有把荒原拍成奇观，而是拍成一整段必须被消耗的时间。",
          "rating": 4.5,
          "vote_count": 128,
          "create_time": "2026-02-14 21:08:00",
          "author": {"id": "preview-user-1", "name": "夜航员", "avatar": null, "url": null},
          "url": "https://movie.douban.com/review/1/"
        }
        """#
      )
    )
  }

  /// 豆瓣长评阅读页条目。
  static var detailReviewEntry: DoubanDiscussionEntry {
    DoubanDiscussionEntry(
      review: decode(
        DoubanReview.self,
        #"""
        {
          "id": "preview-review-reader",
          "title": "在荒原上，沉默是一种导航",
          "abstract": "影片把「离开」拍成一种需要练习的技能。两个主角都不是主动上路的人，他们只是被同一场故障留在了同一条公路上。导演很少给情绪特写，更多时候让环境替人物说话。\n\n第一段路几乎没有对白，观众和人物一起被发动机噪声包围。到第二段路，对话开始出现，但每句话都像在确认对方还在不在。真正改变关系的不是某个戏剧性事件，而是一次又一次把车停进加油站、又开出来。\n\n结尾没有给出答案，只把方向盘交回给人物自己。这种克制让影片在同类题材里显得格外安静，也让「到达」不再是唯一目标。",
          "rating": 4.5,
          "useful_count": 356,
          "create_time": "2026-02-02 18:20:00",
          "author": {"id": "preview-user-4", "name": "远光灯", "avatar": null, "url": null},
          "url": "https://movie.douban.com/review/10/"
        }
        """#
      )
    )
  }

  /// 字幕下载面板的候选字幕。
  static var detailSubtitleResult: SubtitleInfo {
    decode(
      SubtitleInfo.self,
      #"""
      {
        "site": 1,
        "site_name": "AlphaPT",
        "title": "荒原长路.The.Long.Road.2025.1080p.WEB-DL.简中.ass",
        "description": "匹配 WEB-DL 版本，含完整歌词与注释",
        "enclosure": "https://alpha.example/download/preview-subtitle",
        "page_url": "https://alpha.example/subtitles/1",
        "language": "简体中文",
        "size": 48213,
        "pubdate": "2026-11-01 12:00:00",
        "grabs": 42,
        "subtitle_id": "preview-sub-1",
        "file_name": "The.Long.Road.2025.1080p.WEB-DL.chs.ass",
        "season_episode": "",
        "uploader": "AlphaSub"
      }
      """#
    )
  }
}

// MARK: - 行为键

extension UIPreviewBehaviorKey {
  static let detailMediaDetail = "detail.mediaDetail"
  static let detailMediaServerItemRef = "detail.mediaServerItemRef"
  static let detailSubscriptionLookup = "detail.subscriptionLookup"
  static let detailSubscription = "detail.subscription"
  static let detailAddSubscription = "detail.addSubscription"
  static let detailUpdateSubscriptionStatus = "detail.updateSubscriptionStatus"
  static let detailSaveSubscription = "detail.saveSubscription"
  static let detailDeleteSubscription = "detail.deleteSubscription"
  static let detailSearchSubscription = "detail.searchSubscription"
  static let detailSubscriptions = "detail.subscriptions"
  static let detailSeasons = "detail.seasons"
  static let detailGroupSeasons = "detail.groupSeasons"
  static let detailEpisodeGroups = "detail.episodeGroups"
  static let detailEpisodes = "detail.episodes"
  static let detailSeasonsNotExists = "detail.seasonsNotExists"
  static let detailDownloadDirectories = "detail.downloadDirectories"
  static let detailDownloadSubtitle = "detail.downloadSubtitle"
  static let detailRecommendations = "detail.recommendations"
  static let detailRecommendationsMore = "detail.recommendationsMore"
  static let detailSimilar = "detail.similar"
  static let detailSimilarMore = "detail.similarMore"
  static let detailActors = "detail.actors"
  static let detailActorsMore = "detail.actorsMore"
  static let detailDoubanComments = "detail.doubanComments"
  static let detailDoubanReviews = "detail.doubanReviews"
  static let detailCollection = "detail.collection"
  static let detailCollectionMore = "detail.collectionMore"
  static let detailPerson = "detail.person"
  static let detailPersonCredits = "detail.personCredits"
  static let detailPersonCreditsMore = "detail.personCreditsMore"
  static let detailRecognizeTmdb = "detail.recognizeTmdb"
}
#endif
