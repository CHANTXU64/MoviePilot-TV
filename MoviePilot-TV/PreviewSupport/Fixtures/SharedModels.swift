#if DEBUG
import Foundation

/// UI 预览共享 Model fixture（媒体、人物、分季、站点、状态、下载、整理等）。
/// 只构造 Model 值，不发真实请求；各业务域在 Fixtures/ 下用 extension 追加自己的数据。
extension UIPreviewFixtures {
  static func baseTVMedia(
    id: Int,
    title: String,
    hasArtwork: Bool = true
  ) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      original_title: "Frontier Signal",
      names: ["Frontier Signal", "边境信号"],
      type: "电视剧",
      year: "2026",
      poster_path: hasArtwork ? "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg" : nil,
      backdrop_path: hasArtwork ? "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg" : nil,
      overview: "一支深空维护小队在边境航道收到异常信号，必须在有限补给和分裂意见中决定是否继续追踪。",
      vote_average: 8.4,
      popularity: 125,
      directors: [person(id: 70_001, name: "林原真")],
      actors: [
        person(id: 70_002, name: "高桥遥", character: "领航员"),
        person(id: 70_003, name: "陈述", character: "工程师"),
      ],
      release_date: "2026-01-12",
      original_language: "ja",
      production_countries: [country("日本")],
      genres: [genre("科幻"), genre("冒险")],
      category: "剧集"
    )
  }

  static func movieMedia(id: Int, title: String, hasArtwork: Bool = true) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      original_title: "Long Road",
      type: "电影",
      year: "2025",
      poster_path: hasArtwork ? "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg" : nil,
      backdrop_path: hasArtwork ? "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg" : nil,
      overview: "用于预览电影卡片、详情跳转和订阅操作。",
      vote_average: 7.7,
      popularity: 88,
      genres: [genre("剧情")]
    )
  }

  static func externalSourceMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: nil,
      douban_id: "\(id)",
      source: "douban",
      title: title,
      original_title: "Frontier Signal",
      type: "电影",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview: "外部来源媒体，预览媒体卡片菜单中的 TMDB 详情页入口。",
      vote_average: 8.1,
      popularity: 76,
      genres: [genre("科幻")]
    )
  }

  static func collectionMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      type: "合集",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview: "合集预览",
      vote_average: 8.2,
      popularity: 55,
      collection_id: id
    )
  }

  static func shareMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      type: "电视剧",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      overview: "来自 preview-user 的订阅分享，复用 128 次。",
      vote_average: 8.8,
      popularity: 128,
      subscribeShare: subscribeShare(id: id, title: title)
    )
  }

  static var previewMediaGrid: [MediaInfo] {
    [
      movieMedia(id: 80_001, title: "荒原长路"),
      baseTVMedia(id: 80_002, title: "边境信号"),
      movieMedia(id: 80_003, title: "无海报电影", hasArtwork: false),
      collectionMedia(id: 80_004, title: "边境信号系列"),
      shareMedia(id: 80_005, title: "订阅分享：边境信号"),
      baseTVMedia(id: 80_006, title: "标题很长很长的剧集名称用于检查卡片文字截断和焦点缩放"),
    ]
  }

  static var previewMediaGridWithoutShares: [MediaInfo] {
    previewMediaGrid.filter { $0.subscribeShare == nil }
  }


  static func mediaServerItems(prefix: String) -> [MediaServerPlayItem] {
    [
      MediaServerPlayItem(
        id: "\(prefix)-1",
        title: "边境信号",
        subtitle: "2026",
        type: "电视剧",
        image: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        link: "emby://items/1",
        server_type: .emby
      ),
      MediaServerPlayItem(
        id: "\(prefix)-2",
        title: "荒原长路",
        subtitle: "2025",
        type: "电影",
        image: nil,
        link: "emby://items/2",
        server_type: .emby
      ),
    ]
  }

  static var previewSeasons: [TmdbSeason] {
    [
      season(number: 1, name: "第 1 季", episodes: 12, vote: 8.5),
      season(number: 2, name: "第 2 季", episodes: 10, vote: 8.1),
      season(number: 3, name: "特别篇", episodes: 0, vote: 0),
    ]
  }

  static var previewManySeasons: [TmdbSeason] {
    var seasons: [TmdbSeason] = []
    for number in 1...12 {
      let name = number == 12 ? "特别篇合集" : "第 \(number) 季"
      let episodeCount = number == 12 ? 4 : 8 + (number % 5)
      let vote = number == 12 ? 7.6 : 8.0 + Double(number % 4) * 0.2
      seasons.append(season(number: number, name: name, episodes: episodeCount, vote: vote))
    }
    return seasons
  }

  static var previewEpisodeGroups: [EpisodeGroup] {
    [
      episodeGroup(id: "preview-main", name: "官方顺序"),
      episodeGroup(id: "preview-alt", name: "播出顺序"),
    ]
  }

  static var previewSeasonDetail: TmdbSeason {
    season(number: 1, name: "第 1 季", episodes: 12, vote: 8.5)
  }

  static var sites: [Site] {
    [
      Site(id: 1, name: "AlphaPT", domain: "alpha", url: "https://alpha.example", downloader: "qb-main", is_active: FlexibleBool(true)),
      Site(id: 3, name: "BetaHD", domain: "beta", url: "https://beta.example", downloader: "tr-main", is_active: FlexibleBool(true)),
      Site(id: 5, name: "维护中站点", domain: "offline", url: "https://offline.example", downloader: nil, is_active: FlexibleBool(false)),
    ]
  }

  static var downloaders: [DownloaderConf] {
    [
      DownloaderConf(name: "qb-main", type: "qbittorrent", enabled: FlexibleBool(true)),
      DownloaderConf(name: "tr-main", type: "transmission", enabled: FlexibleBool(true)),
    ]
  }

  static var directories: [TransferDirectoryConf] {
    [
      TransferDirectoryConf(
        name: "电视剧",
        storage: "local",
        download_path: "/downloads/tv",
        library_path: "/media/TV",
        library_storage: "local",
        transfer_type: "link",
        scraping: FlexibleBool(true),
        library_category_folder: FlexibleBool(true),
        library_type_folder: FlexibleBool(true)
      ),
      TransferDirectoryConf(
        name: "电影",
        storage: "nas",
        download_path: "/downloads/movie",
        library_path: "/media/Movies",
        library_storage: "nas",
        transfer_type: "copy",
        scraping: FlexibleBool(true),
        library_category_folder: FlexibleBool(false),
        library_type_folder: FlexibleBool(true)
      ),
    ]
  }

  static var storages: [StorageConf] {
    [
      StorageConf(name: "本地存储", type: "local"),
      StorageConf(name: "NAS", type: "nas"),
    ]
  }

  static var customRules: [CustomRule] {
    [
      CustomRule(id: "rule-hard", name: "硬过滤：排除低清", include: ["1080p|2160p"], exclude: ["CAM|TS"], size_range: "1024-51200", seeders: "5", publish_time: nil),
      CustomRule(id: "rule-soft", name: "软过滤：官组优先", include: ["Alpha|Beta"], exclude: nil, size_range: nil, seeders: nil, publish_time: "10080"),
    ]
  }

  static var contexts: [Context] {
    [
      context(index: 1, title: "Frontier.Signal.S01E01.2160p.WEB-DL.DV.HDR.HEVC-Alpha", site: "AlphaPT", size: 8_600_000_000, seeders: 42, filtered: false),
      context(index: 2, title: "Frontier.Signal.S01E02.1080p.WEB-DL.H264-Beta", site: "BetaHD", size: 3_200_000_000, seeders: 7, filtered: false),
      context(index: 3, title: "Frontier.Signal.S01E03.720p.HDTV-LowSeeds", site: "Gamma", size: 1_400_000_000, seeders: 1, filtered: true),
    ]
  }

  static var previewSubscribeShare: SubscribeShare {
    subscribeShare(id: 46_001, title: "边境信号 · 高质量订阅分享")
  }

  static var downloads: [DownloadingInfo] {
    [
      downloading(hash: "hash-1", title: "Frontier.Signal.S01E01.2160p", state: "downloading", progress: 72, dlspeed: "18.4 MB", left: "12 分钟"),
      downloading(hash: "hash-2", title: "Long.Road.2025.1080p", state: "paused", progress: 35, dlspeed: "0 B", left: "暂停"),
      downloading(hash: "hash-3", title: "Coast.Archive.S02E04.1080p", state: "error", progress: 91, dlspeed: "0 B", left: "错误"),
      downloading(hash: "hash-4", title: "Checking.File.S01E02", state: "checking", progress: 8, dlspeed: "0 B", left: "校验中"),
      downloading(hash: "hash-5", title: "Stalled.File.S01E03", state: "stalledDL", progress: 18, dlspeed: "0 B", left: "等待连接"),
      downloading(hash: "hash-6", title: "Uploading.File.S01E04", state: "uploading", progress: 100, dlspeed: "0 B", left: "做种中"),
      downloading(hash: "hash-7", title: "Missing.File.S01E05", state: "missingFiles", progress: 64, dlspeed: "0 B", left: "文件丢失"),
      downloading(hash: "hash-8", title: "Queued.File.S01E06", state: "queuedDL", progress: 0, dlspeed: "0 B", left: "等待中"),
    ]
  }

  static var transferHistoryItems: [TransferHistory] {
    [
      transfer(id: 44_001, title: "边境信号", status: true, mode: "link"),
      transfer(id: 44_002, title: "荒原长路", status: false, mode: "copy"),
      transfer(id: 44_003, title: "海岸档案", status: true, mode: "softlink"),
    ]
  }

  static func subscribe(
    id: Int,
    name: String,
    type: String,
    state: String,
    lack: Int?
  ) -> Subscribe {
    Subscribe(
      id: id,
      name: name,
      year: "2026",
      type: type,
      poster: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      vote: 8.4,
      state: state,
      last_update: "2026-07-03 10:20:00",
      tmdbid: id,
      best_version: 1,
      total_episode: type == "电视剧" ? 12 : nil,
      start_episode: type == "电视剧" ? 1 : nil,
      lack_episode: lack,
      quality: "WEB-DL",
      resolution: "1080[pi]|x1080",
      include: "Alpha",
      sites: [1, 3],
      downloader: "qb-main",
      save_path: "/downloads/tv",
      description: "预览订阅描述"
    )
  }

  static func subscribeShare(id: Int, title: String) -> SubscribeShare {
    decode(
      SubscribeShare.self,
      """
      {
        "id": \(id),
        "share_title": "\(title)",
        "share_comment": "预览订阅分享说明",
        "share_user": "preview-user",
        "share_uid": "preview",
        "name": "\(title)",
        "year": "2026",
        "type": "电视剧",
        "tmdbid": \(id),
        "poster": "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        "vote": 8.8,
        "count": 128
      }
      """
    )
  }

  static func season(number: Int, name: String, episodes: Int, vote: Double) -> TmdbSeason {
    decode(
      TmdbSeason.self,
      """
      {
        "air_date": "2026-01-\(String(format: "%02d", min(number, 9)))",
        "episode_count": \(episodes),
        "name": "\(name)",
        "overview": "预览用分季描述，用于检查长文本、评分、缺集徽标和焦点状态。",
        "poster_path": "/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        "season_number": \(number),
        "vote_average": \(vote)
      }
      """
    )
  }

  static func episodeGroup(id: String, name: String) -> EpisodeGroup {
    decode(
      EpisodeGroup.self,
      """
      {
        "id": "\(id)",
        "name": "\(name)",
        "group_count": 3,
        "episode_count": 22
      }
      """
    )
  }

  static func person(
    id: Int,
    name: String,
    character: String? = nil,
    biography: String? = nil
  ) -> Person {
    let characterLine = character.map { #","character":"\#($0)""# } ?? ""
    let biographyLine = biography.map { #","biography":"\#($0)""# } ?? ""
    return decode(
      Person.self,
      """
      {
        "source": "themoviedb",
        "id": \(id),
        "name": "\(name)",
        "original_name": "Makoto Hayashibara",
        "profile_path": "/r3A7ev7QkjOGocVn3kQrJ0eOouk.jpg",
        "birthday": "1982-04-11",
        "place_of_birth": "Tokyo, Japan",
        "popularity": 12.3\(characterLine)\(biographyLine)
      }
      """
    )
  }

  static func context(
    index: Int,
    title: String,
    site: String,
    size: Int64,
    seeders: Int,
    filtered: Bool
  ) -> Context {
    var result = Context(
      media_info: baseTVMedia(id: 81_000 + index, title: "边境信号"),
      torrent_info: TorrentInfo(
        site: index,
        site_name: site,
        site_order: index,
        title: title,
        description: "预览资源描述，包含字幕、杜比视界和多版本信息。",
        enclosure: "https://example.com/\(index).torrent",
        page_url: "https://example.com/torrents/\(index)",
        size: size,
        seeders: seeders,
        peers: max(seeders * 2, 1),
        pubdate: "2026-07-0\(index) 10:00:00",
        uploadvolumefactor: index == 1 ? 2 : 1,
        downloadvolumefactor: index == 1 ? 0 : 1,
        pri_order: 10 - index,
        labels: ["preview"],
        volume_factor: index == 1 ? "Free" : nil
      ),
      meta_info: MetaInfo(
        title: "Frontier Signal",
        year: "2026",
        resource_team: index == 3 ? "LowSeeds" : "Alpha",
        video_encode: index == 1 ? "HEVC" : "H264",
        resource_pix: index == 1 ? "2160p" : "1080p",
        name: "边境信号",
        season_episode: "S01E0\(index)",
        subtitle: "简繁字幕",
        web_source: "WEB-DL",
        edition: index == 1 ? "DV HDR" : "SDR",
        total_season: 1,
        total_episode: 12
      )
    )
    result.isFilteredOut = filtered
    return result
  }

  static func downloading(
    hash: String,
    title: String,
    state: String,
    progress: Double,
    dlspeed: String,
    left: String
  ) -> DownloadingInfo {
    decode(
      DownloadingInfo.self,
      """
      {
        "hash": "\(hash)",
        "title": "\(title)",
        "name": "边境信号",
        "state": "\(state)",
        "progress": \(progress),
        "dlspeed": "\(dlspeed)",
        "upspeed": "2.1 MB",
        "size": 8600000000,
        "left_time": "\(left)",
        "season_episode": "S01E01",
        "username": "preview",
        "media": {
          "image": "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
          "title": "边境信号",
          "season": "S01",
          "episode": "E01"
        }
      }
      """
    )
  }

  static func transfer(id: Int, title: String, status: Bool, mode: String) -> TransferHistory {
    decode(
      TransferHistory.self,
      """
      {
        "id": \(id),
        "title": "\(title)",
        "type": "电视剧",
        "seasons": "S01",
        "episodes": "E01",
        "category": "科幻",
        "src": "/downloads/\(title).mkv",
        "dest": "/media/TV/\(title)/S01E01.mkv",
        "src_storage": "local",
        "dest_storage": "nas",
        "mode": "\(mode)",
        "status": \(status),
        "errmsg": \(status ? "null" : "\"预览：目标文件已存在\""),
        "src_fileitem": {
          "name": "\(title).mkv",
          "path": "/downloads/\(title).mkv",
          "type": "file",
          "size": 8600000000
        },
        "date": "2026-07-03 10:20:00"
      }
      """
    )
  }

  static func fileItem(name: String, path: String) -> FileItem {
    FileItem(name: name, path: path, type: "file", size: 8_600_000_000)
  }

  static func genre(_ name: String) -> MediaGenre {
    decode(MediaGenre.self, "\"\(name)\"")
  }

  static func country(_ name: String) -> ProductionCountry {
    decode(ProductionCountry.self, "\"\(name)\"")
  }

  static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    guard let data = json.data(using: .utf8) else {
      fatalError("Invalid UI preview fixture")
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      fatalError("Invalid UI preview fixture for \(type): \(error)")
    }
  }
}
#endif
