import AVFoundation
import MPVUI
import XCTest

@testable import MoviePilot_TV

// MARK: - 配置与判定（纯逻辑）

final class InAppPlaybackModelTests: XCTestCase {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  /// Emby 条目经适配器转换后的样子：协调器只认 `ServerMediaItem`。
  private func embyItem(_ json: String, defaultKind: ServerMediaItem.Kind = .other) throws -> ServerMediaItem {
    try decode(EmbyItem.self, json).serverItem(defaultKind: defaultKind)
  }

  func testLibraryScanFindsTheLibraryByWholeFoldersThenByCategory() {
    let folders = [
      MediaLibraryFolder(id: "tv2", paths: ["/media/电视剧2"]),
      MediaLibraryFolder(id: "tv", paths: ["/mnt/old", "/media/电视剧/"]),
      MediaLibraryFolder(id: "cn", paths: ["/data/国产剧"]),
    ]
    let file = "/media/电视剧/国产剧/试看 (2025)/Season 1/E01.mkv"
    XCTAssertEqual(
      MediaLibraryScan.library(for: TransferredFileLocation(path: file, category: "国产剧"), in: folders), "tv",
      "路径落在哪个媒体库的文件夹里就是哪个；按整级目录比较，「电视剧2」不算")
    XCTAssertEqual(
      MediaLibraryScan.library(
        for: TransferredFileLocation(path: "/downloads/国产剧/试看/E01.mkv", category: "国产剧"), in: folders),
      "cn", "路径对不上时按二级分类目录找，和 MoviePilot 一样")
    XCTAssertNil(
      MediaLibraryScan.library(for: TransferredFileLocation(path: "/downloads/试看/E01.mkv", category: nil), in: folders),
      "都对不上时交给调用方刷新整个库")
    XCTAssertNil(MediaLibraryScan.library(for: TransferredFileLocation(path: nil, category: nil), in: folders))
  }

  func testEmbyMediaFoldersKeepTheReadableLibraries() throws {
    let list = try decode(
      EmbyMediaFolderList.self,
      #"[{"Name":"坏的"},{"Id":"lib-tv","SubFolders":[{"Path":"/media/电视剧"},{"Name":"没路径"}]},{"Id":"lib-x"}]"#)
    XCTAssertEqual(list.folders.map(\.id), ["lib-tv", "lib-x"], "个别媒体库读不出时只丢它")
    XCTAssertEqual(list.folders.map(\.paths), [["/media/电视剧"], []], "没有文件夹的媒体库只是按路径找不到它")
    XCTAssertThrowsError(try decode(EmbyMediaFolderList.self, #"[{"Name":"坏的"}]"#), "一个都读不出时无法识别")
  }

  func testLibraryItemExpectationComparesTypeAndExternalID() throws {
    let movie = try embyItem(
      #"{"Id":"7","Type":"Movie","ProviderIds":{"Tmdb":"222","IMDB":"tt0001","douban_id":" 35 "}}"#)
    let bare = try embyItem(#"{"Id":"8","Type":"Movie"}"#)
    func expect(_ ids: [String: String], type mediaType: String = "电影") -> LibraryItemExpectation {
      LibraryItemExpectation(mediaType: mediaType, externalIDs: ids)
    }
    XCTAssertTrue(expect(["tmdb": "222"]).accepts(movie, strict: true))
    XCTAssertTrue(expect(["themoviedb": "222"]).accepts(movie, strict: true), "themoviedb 与 tmdb 是同一来源")
    XCTAssertFalse(expect(["tmdb": "111"]).accepts(movie, strict: false), "同来源编号对不上")
    XCTAssertFalse(expect(["tmdb": "222", "imdb": "tt9999"]).accepts(movie, strict: false), "任一编号冲突都不算")
    XCTAssertTrue(expect(["imdb": "TT0001"]).accepts(movie, strict: true), "键名和编号不区分大小写")
    XCTAssertTrue(expect(["douban": "35"]).accepts(movie, strict: true), "认 douban_id 写法，去掉首尾空白")
    XCTAssertFalse(expect(["tmdb": "222"], type: "电视剧").accepts(movie, strict: false), "类型不符")

    XCTAssertTrue(expect(["tmdb": "222"]).accepts(bare, strict: false), "一台服务器：没有编号也算")
    XCTAssertFalse(expect(["tmdb": "222"]).accepts(bare, strict: true), "多台服务器：没有编号能对上不算")
    XCTAssertTrue(expect([:]).accepts(bare, strict: true), "详情页没有外部编号时只能比类型")
  }

  @MainActor
  func testPlaybackVersionsListOnlyDirectlyPlayableSourcesWithNames() throws {
    let info = try decode(
      EmbyPlaybackInfo.self,
      #"{"MediaSources":[{"Id":"a","Name":"4K HDR","Container":"mkv","Protocol":"File","MediaStreams":[]},{"Id":"b","Name":"远程","Protocol":"Http","MediaStreams":[]},{"Id":"c","Name":"1080p","Container":"mp4","Protocol":"File","MediaStreams":[]}]}"#)
    let versions = MediaSession.versions(of: info.mediaSources.map(\.serverSource))
    XCTAssertEqual(versions.map(\.id), ["a", "c"], "远程片源不能直连，不列出")
    XCTAssertEqual(versions.map(\.displayTitle), ["4K HDR", "1080p"])
  }

  func testLibraryItemExpectationCollectsDetailExternalIDs() {
    let media = MediaInfo(
      tmdb_id: 222, douban_id: "35", imdb_id: " tt0001 ", tvdb_id: 9, source: "themoviedb", media_id: "222",
      type: "电视剧")
    let expected = LibraryItemExpectation(media: media)
    XCTAssertEqual(expected.kind, .series)
    XCTAssertEqual(expected.externalIDs, ["tmdb": "222", "douban": "35", "imdb": "tt0001", "tvdb": "9"])
    XCTAssertEqual(
      EmbyServerConnection.providerSearchKeys(for: expected), ["tmdb.222", "imdb.tt0001", "tvdb.9"],
      "只搜 Emby 刮削器会写的来源")
  }

  func testDolbyDecodingDependsOnAudioOutput() {
    // 经 HDMI 原样输出、保留 Atmos；HomePod（AirPlay）、蓝牙和读不到输出时由 mpv 解码，避免带 Atmos 的 E-AC-3 无声。
    XCTAssertEqual(PlaybackSession.dolbyDecoding(for: [.HDMI]), .automatic)
    XCTAssertEqual(PlaybackSession.dolbyDecoding(for: [.airPlay]), .software)
    XCTAssertEqual(PlaybackSession.dolbyDecoding(for: [.bluetoothA2DP]), .software)
    XCTAssertEqual(PlaybackSession.dolbyDecoding(for: []), .software)
  }

  func testLibraryItemExpectationIgnoresInvalidExternalIDs() throws {
    // 详情里 TMDB 为 0、TVDB 为负数：都是占位，不能拿去和 Emby 上的真实编号比。
    let media = MediaInfo(tmdb_id: 0, douban_id: "0", imdb_id: "tt123456", tvdb_id: -3, source: "themoviedb", type: "电影")
    let expected = LibraryItemExpectation(media: media)
    XCTAssertEqual(expected.externalIDs, ["imdb": "tt123456"])
    XCTAssertEqual(EmbyServerConnection.providerSearchKeys(for: expected), ["imdb.tt123456"], "不搜 tmdb.0")
    let movie = try embyItem(#"{"Id":"7","Type":"Movie","ProviderIds":{"Tmdb":"222","Imdb":"tt123456"}}"#)
    XCTAssertTrue(expected.accepts(movie, strict: true), "IMDb 对上了，TMDB 的 0 不算冲突")

    let negativeIdentity = LibraryItemExpectation(
      media: MediaInfo(tmdb_id: -5, imdb_id: "tt123456", source: "themoviedb", type: "电影"))
    XCTAssertEqual(negativeIdentity.externalIDs, ["imdb": "tt123456"], "主身份是负数编号时也不收")
    XCTAssertEqual(
      LibraryItemExpectation(mediaType: "电影", externalIDs: ["tvdb": "abc", "bangumi": " 0 ", "imdb": " "]).externalIDs,
      [:], "数字来源要正整数，空白与 0 都不收")

    // Emby 那边写成 0 的编号同样按没有处理。
    let zeroOnServer = try embyItem(#"{"Id":"8","Type":"Movie","ProviderIds":{"Tmdb":"0","Imdb":"tt123456"}}"#)
    XCTAssertNil(zeroOnServer.externalID(for: "tmdb"))
    XCTAssertTrue(
      LibraryItemExpectation(mediaType: "电影", externalIDs: ["tmdb": "222", "imdb": "tt123456"])
        .accepts(zeroOnServer, strict: true))
  }

  func testConnectionConfigReadsAlternateKeyNamesAndIgnoresBlankOrMistypedFields() throws {
    let standard = try decode(
      MediaServerConnectionConfig.self,
      #"{"host":" http://10.0.0.2:8096 ","play_host":"https://emby.example.com/emby/","apikey":"k1","username":"admin"}"#
    )
    XCTAssertEqual(standard.host, "http://10.0.0.2:8096")
    XCTAssertEqual(standard.playHost, "https://emby.example.com/emby/")
    XCTAssertEqual(standard.apiKey, "k1")
    XCTAssertEqual(standard.username, "admin")

    XCTAssertEqual(try decode(MediaServerConnectionConfig.self, #"{"api_key":"k2"}"#).apiKey, "k2")
    XCTAssertEqual(try decode(MediaServerConnectionConfig.self, #"{"token":"k3"}"#).apiKey, "k3")
    // 空白首选值不能遮住后面的有效值；类型不符按未配置处理，不拖垮整条配置。
    let mixed = try decode(
      MediaServerConnectionConfig.self, #"{"apikey":"  ","api_key":"k4","host":123,"play_host":null}"#)
    XCTAssertEqual(mixed.apiKey, "k4")
    XCTAssertNil(mixed.host)
    XCTAssertNil(mixed.playHost)
  }

  func testMediaServerListSurvivesMalformedConfigAndGatesInAppPlayback() throws {
    let servers = try decode(
      [MediaServerConf].self,
      #"""
      [
        {"name":"emby","type":"emby","enabled":true,"config":{"host":"10.0.0.2:8096","apikey":"k"}},
        {"name":"broken","type":"emby","enabled":true,"config":["unexpected"]},
        {"name":"disabled","type":"emby","enabled":false,"config":{"host":"10.0.0.3","apikey":"k"}},
        {"name":"nokey","type":"emby","enabled":true,"config":{"host":"10.0.0.4"}},
        {"name":"nohost","type":"emby","enabled":true,"config":{"apikey":"k"}},
        {"name":"plex","type":"plex","enabled":true,"config":{"host":"10.0.0.5","token":"k"}},
        {"name":"legacy","type":"emby","enabled":"true"}
      ]
      """#)
    XCTAssertEqual(servers.map(\.name), ["emby", "broken", "disabled", "nokey", "nohost", "plex", "legacy"])
    XCTAssertNil(servers[1].config)
    XCTAssertEqual(servers.filter(\.supportsInAppPlayback).map(\.name), ["emby"])
  }

  func testConfigDescriptionNeverContainsAPIKey() throws {
    let server = try decode(
      MediaServerConf.self,
      #"{"name":"emby","type":"emby","enabled":true,"config":{"host":"10.0.0.2","apikey":"secret-key-123"}}"#)
    XCTAssertFalse(String(describing: server).contains("secret-key-123"))
    XCTAssertFalse(String(reflecting: server).contains("secret-key-123"))
    XCTAssertFalse("\(server.config!)".contains("secret-key-123"))
  }

  func testBaseURLNormalizationKeepsReverseProxyPrefix() {
    XCTAssertEqual(MediaServerBaseURL.normalized("192.168.1.2:8096")?.absoluteString, "http://192.168.1.2:8096")
    XCTAssertEqual(
      MediaServerBaseURL.normalized(" https://media.example.com/emby/ ")?.absoluteString,
      "https://media.example.com/emby")
    XCTAssertEqual(
      MediaServerBaseURL.normalized("HTTPS://media.example.com/emby/?x=1#web")?.absoluteString,
      "HTTPS://media.example.com/emby")
    XCTAssertNil(MediaServerBaseURL.normalized("   "))
    XCTAssertNil(MediaServerBaseURL.normalized(nil))

    let config = MediaServerConnectionConfig(
      host: "http://10.0.0.2:8096/", playHost: "10.0.0.2:8096", apiKey: "k", username: nil)
    XCTAssertEqual(config.candidateBaseURLs.map(\.absoluteString), ["http://10.0.0.2:8096"])
  }

  func testEmbyUserSelectionMatchesMoviePilotOrder() {
    let users = [
      EmbyUser(id: "1", name: "guest", isAdministrator: false),
      EmbyUser(id: "2", name: "root", isAdministrator: true),
      EmbyUser(id: "3", name: "admin", isAdministrator: false),
    ]
    XCTAssertEqual(EmbyUser.select(from: users, preferredNames: ["admin", "guest"])?.id, "3")
    XCTAssertEqual(EmbyUser.select(from: users, preferredNames: [nil, "guest"])?.id, "1")
    XCTAssertEqual(EmbyUser.select(from: users, preferredNames: ["nobody", ""])?.id, "2")
    XCTAssertNil(
      EmbyUser.select(
        from: [EmbyUser(id: "1", name: "guest", isAdministrator: false)], preferredNames: ["x"]))
  }

  func testEveryLocalFilePlaysDirectlyWithContainerExtension() {
    func source(
      _ container: String?, video: String? = "h264", audio: [String] = ["aac"],
      protocol sourceProtocol: String? = "File", id: String = "s"
    ) -> EmbyMediaSource {
      var streams: [EmbyMediaStream] = []
      if let video { streams.append(EmbyMediaStream(type: "Video", codec: video)) }
      streams += audio.map { EmbyMediaStream(type: "Audio", codec: $0) }
      return EmbyMediaSource(id: id, container: container, protocol: sourceProtocol, mediaStreams: streams)
    }
    func fileExtension(_ source: EmbyMediaSource) -> String? {
      guard case .success(let selection) = EmbyDirectPlay.evaluate(source) else { return nil }
      return selection.fileExtension
    }

    XCTAssertEqual(fileExtension(source("mp4")), "mp4")
    XCTAssertEqual(fileExtension(source("mov,mp4,m4a,3gp,3g2,mj2", video: "hevc")), "mp4")
    XCTAssertEqual(fileExtension(source("mov")), "mov")
    XCTAssertEqual(fileExtension(source("mkv")), "mkv")
    XCTAssertEqual(fileExtension(source("matroska,webm", video: "hevc", audio: ["dts"])), "mkv")
    XCTAssertEqual(fileExtension(source("mp4", video: "vp9")), "mp4")
    XCTAssertEqual(fileExtension(source("avi")), "avi")
    XCTAssertEqual(fileExtension(source(nil)), "mkv")
    XCTAssertEqual(fileExtension(source("a/b")), "mkv", "扩展名只保留字母数字")
    XCTAssertEqual(EmbyDirectPlay.evaluate(source("mp4", protocol: "Http")), .failure(.remoteSource))

    // 多个版本时取第一个本地文件版本。
    XCTAssertEqual(try EmbyDirectPlay.select(from: [source("mkv", id: "a"), source("mp4", id: "b")]).get().source.id, "a")
    XCTAssertEqual(
      try EmbyDirectPlay.select(from: [source("mp4", protocol: "Http", id: "a"), source("mkv", id: "b")]).get().source.id,
      "b")
    XCTAssertEqual(EmbyDirectPlay.select(from: [source("mp4", protocol: "Http")]), .failure(.remoteSource))
    XCTAssertEqual(EmbyDirectPlay.select(from: []), .failure(.noSource))
  }

  func testPlayerLogsDropStreamURLAndAPIKey() {
    XCTAssertEqual(
      PlaybackLog.redacted("open https://e/Videos/1/stream.mkv?Static=true&api_key=abc123&DeviceId=d failed"),
      "open <URL> failed")
    XCTAssertEqual(
      PlaybackLog.redacted("lavf: Static=true&api_key=abc123&DeviceId=d"),
      "lavf: Static=true&api_key=<redacted>&DeviceId=d")
  }

  func testResumePolicySkipsStartAndNearEnd() {
    let twoHours: Double = 7200
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionSeconds: 0, durationSeconds: twoHours))
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionSeconds: 59, durationSeconds: twoHours))
    XCTAssertEqual(PlaybackResumePolicy.resumePosition(positionSeconds: 1800, durationSeconds: twoHours), 1800)
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionSeconds: 6500, durationSeconds: twoHours))
    XCTAssertEqual(PlaybackResumePolicy.resumePosition(positionSeconds: 600, durationSeconds: nil), 600)
    XCTAssertTrue(PlaybackResumePolicy.isCompleted(positionSeconds: 6500, durationSeconds: twoHours))
    XCTAssertFalse(PlaybackResumePolicy.isCompleted(positionSeconds: 6400, durationSeconds: twoHours))
    XCTAssertFalse(PlaybackResumePolicy.isCompleted(positionSeconds: 6500, durationSeconds: nil), "没有时长不算看完")
    XCTAssertFalse(PlaybackResumePolicy.isCompleted(positionSeconds: 6500, durationSeconds: 0))
    XCTAssertEqual(Duration.seconds(754).formatted(.runtime), "12:34")
    XCTAssertEqual(Duration.seconds(3754).formatted(.runtime), "1:02:34")
  }

  func testDurationPrefersPlayerThenSelectedSourceThenItem() {
    // 起播后 mpv 读到的就是正在播的文件：服务器的片源记录过时（文件被洗版换成 3 小时的加长版，Emby 还记 2 小时）也不受影响。
    XCTAssertEqual(PlaybackDuration.seconds(player: 10_800, source: 7200, item: 7200), 10_800)
    // 起播前还没有实测值：条目记的是 2 小时的版本，选的是 3 小时的加长版，以所选片源为准。
    XCTAssertEqual(PlaybackDuration.seconds(player: nil, source: 10_800, item: 7200), 10_800)
    // 刚入库、Emby 还没分析出片源时长：退回条目的。
    XCTAssertEqual(PlaybackDuration.seconds(player: nil, source: nil, item: 7200), 7200)
    // 0、负数、非有限值都跳过（mpv 还没读到时长时报 0）。
    XCTAssertEqual(PlaybackDuration.seconds(player: 0, source: .infinity, item: 7200), 7200)
    XCTAssertEqual(PlaybackDuration.seconds(player: .nan, source: -1, item: 0), nil)
    XCTAssertNil(PlaybackDuration.seconds(player: nil, source: nil, item: nil))
  }

  func testEmbySourceKeepsItsOwnRuntime() throws {
    let info = try decode(
      EmbyPlaybackInfo.self,
      #"{"MediaSources":[{"Id":"a","Container":"mkv","Protocol":"File","RunTimeTicks":108000000000,"MediaStreams":[]},{"Id":"b","Container":"mkv","Protocol":"File","MediaStreams":[]},{"Id":"c","Container":"mkv","Protocol":"File","RunTimeTicks":"bad","MediaStreams":[]}]}"#)
    let sources = info.mediaSources.map(\.serverSource)
    XCTAssertEqual(sources.map(\.id), ["a", "b", "c"], "时长读不出不影响片源本身")
    XCTAssertEqual(sources.map(\.runtimeSeconds), [10_800, nil, nil])
  }

  func testPlaybackMetadataPrefersMoviePilotAndFillsGapsFromServer() {
    let moviePilot = PlaybackMetadata(title: "MP 片名", overview: "  ", communityRating: 0)
    let server = PlaybackMetadata(
      title: "Emby 片名", overview: "Emby 简介", communityRating: 6.5, officialRating: "PG-13",
      posterURL: URL(string: "http://emby.local/p.jpg"))
    let merged = moviePilot.filling(server)
    XCTAssertEqual(merged.title, "MP 片名", "MoviePilot 有的项以它为准")
    XCTAssertEqual(merged.overview, "Emby 简介", "空白简介当作没有，用服务器的")
    XCTAssertEqual(merged.communityRating, 6.5, "0 分是没人打分，不算有评分")
    XCTAssertEqual(merged.officialRating, "PG-13", "MoviePilot 没有分级，用服务器的")
    XCTAssertEqual(merged.posterURL, URL(string: "http://emby.local/p.jpg"))
  }

  func testServerEpisodeMatchesMoviePilotEpisodeByIDThenNumberAndAirDate() throws {
    let list = try JSONDecoder().decode(
      [TmdbEpisode].self,
      from: Data(
        #"[{"id":11,"episode_number":1,"air_date":"2024-01-01"},{"id":12,"episode_number":2,"air_date":"2024-01-08"}]"#.utf8))
    func episode(number: Int?, tmdb: String? = nil, premiere: String? = nil) -> ServerMediaItem {
      ServerMediaItem(
        id: "e", kind: .episode, seasonNumber: 1, episodeNumber: number,
        externalIDs: tmdb.map { ["tmdb": $0] } ?? [:], premiereDate: premiere)
    }
    XCTAssertEqual(PlaybackMetadataLookup.episode(matching: episode(number: 1, tmdb: "12"), in: list)?.id, 12, "单集编号优先")
    XCTAssertNil(
      PlaybackMetadataLookup.episode(matching: episode(number: 2, tmdb: "99"), in: list),
      "有单集编号却不在这一季的列表里（比如按剧集组分季）：不按集号凑成第 2 集")
    XCTAssertEqual(PlaybackMetadataLookup.episode(matching: episode(number: 2), in: list)?.id, 12)
    XCTAssertEqual(
      PlaybackMetadataLookup.episode(matching: episode(number: 2, premiere: "2024-01-09T00:00:00Z"), in: list)?.id, 12,
      "日期差一天以内仍算对上")
    XCTAssertNil(
      PlaybackMetadataLookup.episode(matching: episode(number: 2, premiere: "2020-05-01T00:00:00Z"), in: list),
      "集号相同、播出日期对不上：服务器按别的顺序编号，不认")
    XCTAssertNil(PlaybackMetadataLookup.episode(matching: episode(number: nil), in: list))
    XCTAssertNil(PlaybackMetadataLookup.episode(matching: episode(number: 9), in: list))
  }

  func testMoviePilotLookupUsesTMDBThenDouban() {
    XCTAssertEqual(PlaybackMetadataLookup.lookupMedia(externalIDs: ["tmdb": "222", "douban": "35"], type: "电影")?.tmdb_id, 222)
    let douban = PlaybackMetadataLookup.lookupMedia(externalIDs: ["douban": "35"], type: "电视剧")
    XCTAssertEqual(douban?.douban_id, "35")
    XCTAssertEqual(douban?.type, "电视剧")
    XCTAssertNil(PlaybackMetadataLookup.lookupMedia(externalIDs: ["imdb": "tt1"], type: "电影"), "MoviePilot 详情只按 TMDB、豆瓣查")
  }

  @MainActor
  func testEmbyItemCarriesDisplayInfoAndKeylessImages() throws {
    let client = EmbyClient(baseURL: URL(string: "http://emby.local:8096/emby")!, apiKey: "secret-key")
    let episode = try decode(
      EmbyItem.self,
      #"{"Id":"e1","Type":"Episode","SeriesId":"s1","Overview":" 集简介 ","CommunityRating":7.2,"OfficialRating":"TV-14","ImageTags":{"Primary":"ep"},"SeriesPrimaryImageTag":"sp"}"#
    ).serverItem(image: { client.imageURL(itemID: $0, type: $1, tag: $2) })
    XCTAssertEqual(episode.seriesID, "s1")
    XCTAssertEqual(episode.overview, "集简介")
    XCTAssertEqual(episode.communityRating, 7.2)
    XCTAssertEqual(episode.officialRating, "TV-14")
    XCTAssertEqual(episode.posterURL?.path, "/emby/Items/s1/Images/Primary", "单集的竖版海报是剧的")
    XCTAssertEqual(episode.thumbnailURL?.path, "/emby/Items/e1/Images/Primary", "单集的横版图是这一集的截图")
    for url in [episode.posterURL, episode.thumbnailURL].compactMap({ $0 }) {
      XCTAssertFalse(url.absoluteString.contains("secret-key"), "图片地址不带密钥")
    }

    let movie = try decode(
      EmbyItem.self, #"{"Id":"m1","Type":"Movie","ImageTags":{"Primary":"mp"},"BackdropImageTags":["bd"]}"#
    ).serverItem(image: { client.imageURL(itemID: $0, type: $1, tag: $2) })
    XCTAssertEqual(movie.posterURL?.path, "/emby/Items/m1/Images/Primary")
    XCTAssertEqual(movie.thumbnailURL?.path, "/emby/Items/m1/Images/Backdrop", "没有横版缩略图时用背景图")
    XCTAssertNil(try decode(EmbyItem.self, #"{"Id":"x","Type":"Movie"}"#).serverItem().posterURL, "没有图片标签就不带图")
  }

  func testSeriesStartsFromFirstRegularEpisodeThatHasAFile() throws {
    func episode(_ id: String, season: Int?, episode: Int?, location: String? = "FileSystem") -> String {
      let s = season.map { #","ParentIndexNumber":\#($0)"# } ?? ""
      let e = episode.map { #","IndexNumber":\#($0)"# } ?? ""
      let l = location.map { #","LocationType":"\#($0)""# } ?? ""
      return #"{"Id":"\#(id)","Type":"Episode"\#(s)\#(e)\#(l)}"#
    }
    func first(_ episodes: [String]) throws -> String? {
      let page = try decode(EmbyItemsPage.self, #"{"Items":[\#(episodes.joined(separator: ","))]}"#)
      return PlaybackEpisodeOrder.firstEpisode(in: page.items.map { $0.serverItem(defaultKind: .episode) })?.id
    }
    XCTAssertEqual(
      try first([
        episode("special", season: 0, episode: 1),
        episode("s2e1", season: 2, episode: 1),
        episode("missing", season: 1, episode: 1, location: "Virtual"),
        episode("s1e2", season: 1, episode: 2),
        episode("s1e3", season: 1, episode: 3),
      ]), "s1e2")
    XCTAssertEqual(try first([episode("special", season: 0, episode: 1)]), "special", "只有特别篇时播放特别篇")
    XCTAssertEqual(try first([episode("a", season: nil, episode: 2), episode("b", season: nil, episode: 1)]), "b")
    XCTAssertNil(try first([episode("missing", season: 1, episode: 1, location: "Virtual")]))
    XCTAssertNil(try first([]))
  }

  func testEpisodeTitleShowsSeriesAndNumbers() throws {
    func titles(_ item: ServerMediaItem) -> (primary: String, secondary: String?) {
      item.metadata.playerTitles(isEpisode: item.kind == .episode)
    }
    func line(_ item: ServerMediaItem) -> String { PlaybackTitles.singleLine(titles(item)) }
    let episode = try embyItem(
      #"{"Id":"e","Type":"Episode","Name":"开端","SeriesName":"某剧","ParentIndexNumber":1,"IndexNumber":1}"#)
    XCTAssertEqual(line(episode), "某剧 · 第 1 季 第 1 集 · 开端")
    XCTAssertEqual(titles(episode).primary, "第 1 季 第 1 集 · 开端")
    XCTAssertEqual(titles(episode).secondary, "某剧")
    let movie = try embyItem(#"{"Id":"m","Type":"Movie","Name":"电影名"}"#)
    XCTAssertEqual(line(movie), "电影名")
    XCTAssertNil(titles(movie).secondary)

    // 集名只是占位时不重复显示。
    for placeholder in ["第1集", "第 1 集", "第一集", "第12话", "Episode 1", "EP01", "e3", "1"] {
      let item = try embyItem(
        #"{"Id":"e","Type":"Episode","Name":"\#(placeholder)","SeriesName":"小城良方","ParentIndexNumber":1,"IndexNumber":1}"#)
      XCTAssertEqual(line(item), "小城良方 · 第 1 季 第 1 集", placeholder)
      XCTAssertEqual(
        BaseItemDto(item: item, metadata: item.metadata).name, "第 1 季 第 1 集", "信息面板的标题也不显示占位集名：\(placeholder)")
    }
    XCTAssertFalse(PlaybackTitles.isPlaceholderEpisodeName("第一集 重逢", episodeNumber: 1))
    // 纯数字只在等于集号时算占位，真实的数字集名保留。
    XCTAssertTrue(PlaybackTitles.isPlaceholderEpisodeName("03", episodeNumber: 3))
    let numbered = try embyItem(
      #"{"Id":"e","Type":"Episode","Name":"1984","SeriesName":"某剧","ParentIndexNumber":1,"IndexNumber":3}"#)
    XCTAssertEqual(line(numbered), "某剧 · 第 1 季 第 3 集 · 1984")
    XCTAssertFalse(PlaybackTitles.isPlaceholderEpisodeName("12", episodeNumber: nil))
    // 没有季集号时，占位集名仍然保留，否则标题是空的。
    let bare = try embyItem(#"{"Id":"e","Type":"Episode","Name":"第1集"}"#)
    XCTAssertEqual(line(bare), "第1集")
  }

  @MainActor
  func testHomeCardsOfferInAppPlaybackOnlyForAdministratorMoviesAndSeriesOnPlayableEmby() throws {
    func item(_ type: String, itemID: String? = "m1") throws -> MediaServerPlayItem {
      let idField = itemID.map { #","item_id":"\#($0)""# } ?? ""
      return try JSONDecoder().decode(
        MediaServerPlayItem.self,
        from: Data(#"{"id":"x","title":"t","type":"\#(type)","server_type":"emby"\#(idField)}"#.utf8))
    }
    func itemID(
      _ item: MediaServerPlayItem, server: String = "emby", admin: Bool = true, backendVersion: String? = "v3.2.6"
    ) -> String? {
      HomeViewModel.inAppPlaybackItemID(
        item, server: server, playableServers: ["emby"], canRequestSuperUserEndpoints: admin,
        backendVersion: backendVersion)
    }
    XCTAssertEqual(itemID(try item("电影")), "m1")
    XCTAssertEqual(itemID(try item("电视剧", itemID: " m2 ")), "m2")
    XCTAssertNil(itemID(try item("电影"), admin: false))
    XCTAssertNil(itemID(try item("音乐")))
    XCTAssertNil(itemID(try item("电影"), server: "emby-unconfigured"), "服务器未配置地址和密钥时不显示播放")
    XCTAssertNil(itemID(try item("电影", itemID: nil)))
    XCTAssertNil(itemID(try item("电影", itemID: "  ")))
    XCTAssertNil(itemID(try item("电影"), backendVersion: "v3.2.5"), "v3.2.6 以前的后端不提供应用内播放")
    XCTAssertNil(itemID(try item("电影"), backendVersion: nil), "读不出版本时不提供")
    XCTAssertEqual(itemID(try item("电影"), backendVersion: "v3.2.6-1"), "m1")
  }

  func testPlaybackFailureMessageFollowsErrorCategoryAndLibmpvCode() {
    typealias M = PlaybackFailureMessage
    func message(_ error: MPVPlayerError) -> String { M.message(for: error) }

    // 原生输出拒绝：原因文本取自 MPVUI 补丁原文。
    for reason in [
      "software Dolby Vision needs libplacebo reshaping",
      "decoder supplied no validated native Dolby Vision sample metadata",
      "P7 conversion was not explicitly enabled for this output",
      "missing, malformed, duplicate, or unconvertible current-frame RPU",
    ] {
      XCTAssertEqual(message(.nativeVideoOutputUnavailable(reason)), M.dolbyVisionUnavailable, reason)
    }
    XCTAssertEqual(
      message(.nativeVideoOutputUnavailable("no color space for native CI overlay")), M.nativeOutputUnavailable,
      "非杜比视界的画面格式不说杜比视界")
    XCTAssertEqual(
      message(.nativeVideoOutputUnavailable("software color signal cannot be represented by CoreVideo metadata")),
      M.nativeOutputUnavailable)

    // 读取阶段：只有 LOADING_FAILED（片源流打不开）才提网络。
    XCTAssertEqual(message(.loadFailed(code: -13, message: "loading failed")), M.sourceUnreachable)
    XCTAssertEqual(message(.loadFailed(code: -17, message: "unrecognized file format")), M.unknownFormat)
    XCTAssertEqual(message(.loadFailed(code: -16, message: "no audio or video data played")), M.nothingToPlay)
    XCTAssertEqual(message(.loadFailed(code: -15, message: "vo init failed")), M.videoOutputFailed)
    XCTAssertEqual(message(.loadFailed(code: -14, message: "audio output initialization failed")), M.audioOutputFailed)
    XCTAssertEqual(message(.loadFailed(code: -12, message: "error running command")), M.loadFailedGeneric, "命令被拒不是网络问题")
    XCTAssertEqual(message(.loadFailed(code: -20, message: "something happened")), M.loadFailedGeneric)

    // 播放阶段：起播后 mpv 清零错误码，残留的 -13 也不当成网络问题。
    XCTAssertEqual(message(.playbackFailed(code: -13, message: "loading failed")), M.playbackInterrupted)
    XCTAssertEqual(message(.playbackFailed(code: -20, message: "something happened")), M.playbackInterrupted)
    XCTAssertEqual(message(.playbackFailed(code: -15, message: "vo init failed")), M.videoOutputFailed)

    for error: MPVPlayerError in [
      .clientCreationFailed, .clientUnavailable,
      .initializationFailed(context: "Initialize mpv", code: -1, message: "event queue full"),
    ] {
      XCTAssertEqual(message(error), M.playerInitializationFailed, "\(error)")
    }
    XCTAssertEqual(message(.seekTimedOut), M.playbackFailedGeneric)

    let all: [MPVPlayerError] = [
      .nativeVideoOutputUnavailable("software Dolby Vision needs libplacebo reshaping"),
      .nativeVideoOutputUnavailable("no color space for native CI overlay"),
      .loadFailed(code: -17, message: ""), .loadFailed(code: -12, message: ""), .loadFailed(code: -20, message: ""),
      .playbackFailed(code: -13, message: ""), .playbackFailed(code: -20, message: ""),
      .clientCreationFailed, .clientUnavailable, .initializationFailed(context: "", code: -1, message: ""),
      .seekTimedOut,
    ]
    for error in all {
      XCTAssertFalse(message(error).contains("网络"), "没有指向网络的证据时不提网络：\(error)")
      XCTAssertLessThanOrEqual(message(error).count, 30, "提示在全局通知里单行显示")
    }
    XCTAssertLessThanOrEqual(M.sourceUnreachable.count, 30)
  }
}

// MARK: - 播完后的动作

@MainActor
final class PlaybackEndActionTests: XCTestCase {
  private func action(
    switching: Bool = false, seeking: Bool = false, autoPlay: Bool = true, hasNext: Bool = true,
    canLookUpNext: Bool = false
  ) -> MediaSession.EndAction {
    MediaSession.endAction(
      isSwitchingItem: switching, isSeeking: seeking, isLiveStream: false, isAutoPlayEnabled: autoPlay,
      nextItem: hasNext ? PlaybackIntent(item: BaseItemDto(id: "e2")) : nil, canLookUpNext: canLookUpNext)
  }

  func testAutoPlayContinuesWithNextEpisode() {
    guard case .playNext(let next) = action() else { return XCTFail("应接着播下一集") }
    XCTAssertEqual(next.item.id, "e2")
  }

  func testEndingDuringManualSwitchWaitsForIt() {
    guard case .waitForSwitch = action(switching: true) else { return XCTFail("正在换集时不能退出") }
  }

  func testExitsWithoutNextEpisodeOrAutoPlay() {
    guard case .exit = action(hasNext: false) else { return XCTFail("没有下一集应退出") }
    guard case .exit = action(autoPlay: false) else { return XCTFail("关了自动播放应退出") }
    guard case .exit = action(seeking: true) else { return XCTFail("拖动中播完应退出") }
  }

  func testEpisodeQueueLooksUpNextAgainWhenItWasNotKnown() {
    // 按集播放：开播时下一集还没入库（或查询还没回来），播完时重新查一次，不直接退出。
    guard case .lookUpNext = action(hasNext: false, canLookUpNext: true) else { return XCTFail("应重新查下一集") }
    guard case .playNext = action(canLookUpNext: true) else { return XCTFail("已知下一集时直接播") }
    guard case .exit = action(autoPlay: false, hasNext: false, canLookUpNext: true) else {
      return XCTFail("关了自动播放不再查")
    }
  }

  func testNextFoundBySkippingMissingEpisodesIsRecheckedAtTheEnd() {
    // 开播时第 2 集还没入库，队列记下的是第 3 集；播完时第 2 集可能已经入库，要按顺序先播它。
    let recheck = MediaSession.endAction(
      isSwitchingItem: false, isSeeking: false, isLiveStream: false, isAutoPlayEnabled: true,
      nextItem: PlaybackIntent(item: BaseItemDto(id: "e3")), canLookUpNext: true, nextNeedsRecheck: true)
    guard case .lookUpNext = recheck else { return XCTFail("应重新确认下一集，实际 \(recheck)") }
  }

  func testAutoPlayTurnedOffDuringTheEndLookupExitsNormally() {
    // 片尾正在重新查下一集时，用户从工具栏关掉了自动播放：查到了也不起播，和平常播完一样退出、不说明原因。
    let found = MoviePilotEpisodeQueue.NextLookup.play(PlaybackIntent(item: BaseItemDto(id: "e3")))
    guard case .unavailable(nil) = MediaSession.resultAfterLookUp(found, isAutoPlayEnabled: false) else {
      return XCTFail("关了自动播放不能起播")
    }
    let missing = MoviePilotEpisodeQueue.NextLookup.unavailable(EpisodeNavigator.nextMissingMessage)
    guard case .unavailable(nil) = MediaSession.resultAfterLookUp(missing, isAutoPlayEnabled: false) else {
      return XCTFail("关了自动播放不再说明下一集的情况")
    }
    guard case .play(let next) = MediaSession.resultAfterLookUp(found, isAutoPlayEnabled: true) else {
      return XCTFail("开着自动播放照常接着播")
    }
    XCTAssertEqual(next.item.id, "e3")
  }
}

// MARK: - 地址探测

final class PreferredReachabilityTests: XCTestCase {
  private struct Unreachable: Error {}

  private func probe(_ delays: [String: Duration], failing: Set<String> = []) -> @Sendable (String) async throws -> Void {
    { candidate in
      try await Task.sleep(for: delays[candidate] ?? .zero)
      if failing.contains(candidate) { throw Unreachable() }
    }
  }

  func testEarlierCandidateWinsWhenItAnswersWithinGrace() async {
    let result = await PreferredReachability.first(
      of: ["lan", "wan"], grace: .milliseconds(500), probe: probe(["lan": .milliseconds(100)]))
    XCTAssertEqual(try result.get(), "lan")
  }

  func testLaterCandidateIsUsedWhenEarlierFails() async {
    let result = await PreferredReachability.first(
      of: ["lan", "wan"], grace: .seconds(5), probe: probe(["lan": .milliseconds(50)], failing: ["lan"]))
    XCTAssertEqual(try result.get(), "wan")
  }

  func testLaterCandidateIsUsedAfterGraceWhenEarlierHangs() async {
    let started = ContinuousClock.now
    let result = await PreferredReachability.first(
      of: ["lan", "wan"], grace: .milliseconds(100), probe: probe(["lan": .seconds(10)]))
    XCTAssertEqual(try result.get(), "wan")
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "不等内网超时")
  }

  func testAllFailuresAreReported() async {
    let result = await PreferredReachability.first(
      of: ["lan", "wan"], grace: .milliseconds(100), probe: probe([:], failing: ["lan", "wan"]))
    guard case .failure(let failures) = result else { return XCTFail("应全部失败") }
    XCTAssertEqual(failures.errors.count, 2)
  }
}

// MARK: - Emby 客户端

@MainActor
final class EmbyClientTests: XCTestCase {
  override func setUp() {
    super.setUp()
    PlaybackURLProtocol.stub.reset()
  }

  private func client(_ base: String = "https://wan.playback-tests.local/emby", key: String = "k+&=y") -> EmbyClient {
    EmbyClient(
      baseURL: URL(string: base)!, apiKey: key, deviceID: "device-1", session: PlaybackURLProtocol.session)
  }

  func testPathsStayUnderReverseProxyPrefixAndIDsAreEncodedOnce() throws {
    let url = try client().url(["Users", "u 1", "Items", "a/b%c"])
    XCTAssertEqual(url.host, "wan.playback-tests.local")
    XCTAssertEqual(url.path(percentEncoded: true), "/emby/Users/u%201/Items/a%2Fb%25c")
    XCTAssertEqual(url.path, "/emby/Users/u 1/Items/a/b%c")
  }

  func testDirectStreamURLCarriesKeyAndSessionOnlyInQuery() throws {
    let selection = EmbyDirectPlay.Selection(
      source: EmbyMediaSource(id: "src&1", container: "mp4", mediaStreams: []), fileExtension: "mp4")
    let url = try client().directStreamURL(itemID: "m1", selection: selection, playSessionID: "ps 1")
    XCTAssertEqual(url.path, "/emby/Videos/m1/stream.mp4")
    let query = Dictionary(
      uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map {
        ($0.name, $0.value)
      })
    XCTAssertEqual(query["Static"], "true")
    XCTAssertEqual(query["MediaSourceId"], "src&1")
    XCTAssertEqual(query["PlaySessionId"], "ps 1")
    XCTAssertEqual(query["DeviceId"], "device-1")
    XCTAssertEqual(query["api_key"], "k+&=y")
  }

  func testRequestsAuthenticateByHeaderAndMissingItemIsNil() async throws {
    PlaybackURLProtocol.stub.configure { $0.users = #"[{"Id":"u1","Name":"admin"}]"# }
    let users = try await client().users()
    XCTAssertEqual(users.map(\.id), ["u1"])
    let request = try XCTUnwrap(PlaybackURLProtocol.stub.requests().last)
    XCTAssertEqual(request.headers["X-Emby-Token"], "k+&=y")
    XCTAssertTrue(request.headers["X-Emby-Authorization"]?.contains(#"DeviceId="device-1""#) == true)
    XCTAssertNil(request.url.query, "接口请求的密钥只走请求头，不进 URL")

    let missing = try await client().item(id: "nope", userID: "u1")
    XCTAssertNil(missing)
  }

  func testTransportErrorsDoNotExposeAddressOrKey() async {
    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = ["wan.playback-tests.local"] }
    do {
      _ = try await client(key: "secret-key").users()
      XCTFail("应当连接失败")
    } catch {
      XCTAssertEqual(error as? EmbyClientError, .unreachable(transportSecurity: false))
      XCTAssertFalse(String(describing: error).contains("secret-key"))
      XCTAssertFalse(String(describing: error).contains("playback-tests"))
    }
  }

  func testPlaybackInfoAsksForDirectPlayOnly() async throws {
    PlaybackURLProtocol.stub.configure { $0.playbackInfo = #"{"MediaSources":[],"PlaySessionId":"p"}"# }
    let info = try await client().playbackInfo(itemID: "m1", userID: "u1")
    XCTAssertEqual(info.playSessionID, "p")
    let request = try XCTUnwrap(PlaybackURLProtocol.stub.requests().last)
    XCTAssertEqual(request.method, "POST")
    let query = Dictionary(
      uniqueKeysWithValues: URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!.map {
        ($0.name, $0.value ?? "")
      })
    XCTAssertEqual(query["UserId"], "u1")
    XCTAssertEqual(query["EnableTranscoding"], "false")
    XCTAssertEqual(query["EnableDirectStream"], "false")
    let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let profile = try XCTUnwrap(body["DeviceProfile"] as? [String: Any])
    XCTAssertEqual((profile["TranscodingProfiles"] as? [Any])?.count, 0)
  }
}

// MARK: - 播放协调器（经 MoviePilot 与 Emby 替身走完整解析）

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
  private static let mpBase = "https://mp.playback-tests.local"
  private static let twoHours: Int64 = 7200 * 10_000_000
  /// 协调器弱引用 `APIService`（生产中由 `APIService` 经 `SessionScope` 持有协调器），测试期间由这里持有。
  private var services: [APIService] = []

  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(PlaybackURLProtocol.self))
    PlaybackURLProtocol.stub.reset()
  }

  override func tearDown() {
    services = []
    APIService.removeURLProtocolForTesting(PlaybackURLProtocol.self)
    PlaybackURLProtocol.stub.reset()
    super.tearDown()
  }

  private func makeService(superUser: Bool = true) -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = Self.mpBase
    service.tokenForTesting = "mp-token"
    service.currentUserForTesting = Token(
      access_token: "mp-token", token_type: "bearer", super_user: FlexibleBool(superUser),
      permissions: nil, user_id: 1, user_name: "admin", avatar: nil)
    service.settings = GlobalSettings(BACKEND_VERSION: backendVersion)
    return service
  }

  private var backendVersion: String? = "v3.2.6"
  /// 设置页「播放」里的应用内播放开关；不读真实的本机设置，免得测试之间互相影响。
  private var enabledInSettings = true

  private func makeCoordinator(
    _ service: APIService, now: @escaping () -> Date = Date.init
  ) -> PlaybackCoordinator {
    services.append(service)
    let enabled = enabledInSettings
    return PlaybackCoordinator(
      apiService: service, mediaServerSession: PlaybackURLProtocol.session, isEnabledInSettings: { enabled },
      now: now)
  }

  private static func movie(
    id: String = "m1", type: String = "Movie", positionSeconds: Int64 = 0
  ) -> String {
    #"{"Id":"\#(id)","Name":"测试电影","Type":"\#(type)","RunTimeTicks":\#(twoHours),"UserData":{"PlaybackPositionTicks":\#(positionSeconds * 10_000_000),"IsFavorite":true}}"#
  }

  private static func playbackInfo(container: String = "mp4") -> String {
    #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"\#(container)","Protocol":"File","MediaStreams":[{"Type":"Video","Codec":"hevc"},{"Type":"Audio","Codec":"eac3"}]}]}"#
  }

  private static func embyServer(name: String, host: String, playHost: String? = nil, key: String = "emby-key") -> String {
    let play = playHost.map { #","play_host":"\#($0)""# } ?? ""
    return #"{"name":"\#(name)","type":"emby","enabled":true,"config":{"host":"\#(host)"\#(play),"apikey":"\#(key)","username":"admin"}}"#
  }

  private func streamURL(_ coordinator: PlaybackCoordinator) -> URL? {
    coordinator.session?.streamURL
  }

  private func run(_ coordinator: PlaybackCoordinator, _ target: PlaybackTarget) async {
    coordinator.play(target)
    await coordinator.resolveTaskForTesting?.value
  }

  func testNonAdministratorCannotPlayAndSendsNoRequests() async {
    let coordinator = makeCoordinator(makeService(superUser: false))
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.notAllowed.errorDescription)
    XCTAssertFalse(coordinator.isResolving)
    XCTAssertNil(coordinator.session)
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().isEmpty)
  }

  func testFallsBackToPlayHostAndPresentsDirectStream() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local:8096", playHost: "https://wan.playback-tests.local/emby/"))]"
      $0.unreachableHosts = ["lan.playback-tests.local"]
      $0.users = #"[{"Id":"u-guest","Name":"guest"},{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["wan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    XCTAssertNil(coordinator.failure)
    XCTAssertFalse(coordinator.isResolving)
    XCTAssertNil(coordinator.resumePrompt)
    let url = try XCTUnwrap(streamURL(coordinator))
    XCTAssertEqual(url.host, "wan.playback-tests.local")
    XCTAssertEqual(url.path, "/emby/Videos/m1/stream.mp4")
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "api_key", value: "emby-key")))
    XCTAssertTrue(query.contains(URLQueryItem(name: "MediaSourceId", value: "src1")))
    XCTAssertTrue(query.contains(URLQueryItem(name: "PlaySessionId", value: "ps1")))

    let itemRequest = PlaybackURLProtocol.stub.requests().first { $0.url.path.contains("/Items/m1") && $0.method == "GET" }
    XCTAssertEqual(itemRequest?.url.path, "/emby/Users/u-admin/Items/m1", "按 MoviePilot 配置的用户名选 Emby 用户")

    // 未起播就关闭不上报任何播放状态。
    coordinator.endCurrentSession()
    XCTAssertNil(coordinator.session)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Sessions/") })
  }

  private func mediaServerFetchCount() -> Int {
    PlaybackURLProtocol.stub.requests().filter { $0.url.path == "/api/v1/system/setting/MediaServers" }.count
  }

  func testStaleCachedServerConfigIsRefreshedOnceAfterFailure() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "old.playback-tests.local"))]"
      $0.unreachableHosts = ["old.playback-tests.local"]
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    _ = try await service.fetchCachedMediaServers()
    // MoviePilot 里改了 Emby 地址，缓存仍是旧的。
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
    }

    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "lan.playback-tests.local")
    XCTAssertEqual(mediaServerFetchCount(), 2, "缓存命中一次，失败后重新读取一次")
    coordinator.endCurrentSession()

    // 新配置已写回缓存，下次播放不再读取。
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNotNil(coordinator.session)
    XCTAssertEqual(mediaServerFetchCount(), 2)
    coordinator.endCurrentSession()
  }

  func testUnchangedServerConfigDoesNotRetryFailedPlayback() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.unreachableHosts = ["lan.playback-tests.local"]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    XCTAssertEqual(
      coordinator.failure?.message,
      PlaybackError.unreachable(server: "emby", transportSecurity: false).errorDescription)
    XCTAssertEqual(mediaServerFetchCount(), 2)
    let probes = PlaybackURLProtocol.stub.requests().filter { $0.url.host == "lan.playback-tests.local" }
    XCTAssertEqual(probes.count, 1, "配置没变时不再重新探测")
  }

  func testSavedPositionAsksBeforePlaying() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local:8096"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie(positionSeconds: 1800)]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    let prompt = try XCTUnwrap(coordinator.resumePrompt)
    XCTAssertEqual(prompt.position, 1800)
    XCTAssertNil(coordinator.session)

    coordinator.play(.serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.resolveTaskForTesting, "询问期间不重复开始解析")

    coordinator.resume(prompt, fromBeginning: false)
    XCTAssertNil(coordinator.resumePrompt)
    XCTAssertNotNil(coordinator.session)
    coordinator.endCurrentSession()
  }

  func testMKVPlaysThroughMPVWithoutTranscoding() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo(container: "mkv")
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.failure)
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertNil(session.mpvPlayer, "mpv 等播放界面出现再创建")
    XCTAssertEqual(session.streamURL.path, "/Videos/m1/stream.mkv")
    let query = URLComponents(url: session.streamURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "Static", value: "true")))
    coordinator.endCurrentSession()
  }

  func testRemoteSourceExplainsWhyWithoutPresenting() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mp4","Protocol":"Http","MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(coordinator.failure?.message, EmbyDirectPlay.Unsupported.remoteSource.message)
    XCTAssertNil(coordinator.session)
    XCTAssertFalse(coordinator.isResolving)
  }

  func testSeriesPlaysFirstEpisode() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|s1": #"{"Id":"s1","Name":"某剧","Type":"Series"}"#]
      $0.episodes = [
        "lan.playback-tests.local|s1":
          #"{"Items":[{"Id":"sp","Type":"Episode","ParentIndexNumber":0,"IndexNumber":1},{"Id":"e2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2},{"Id":"e1","Type":"Episode","SeriesName":"某剧","ParentIndexNumber":1,"IndexNumber":1,"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":0}}]}"#
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "s1"))

    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.path, "/Videos/e1/stream.mp4")
    let episodesRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/Episodes") })
    let query = URLComponents(url: episodesRequest.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "UserId", value: "u-admin")))
    let playbackInfoRequest = PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/PlaybackInfo") }
    XCTAssertEqual(playbackInfoRequest?.url.path, "/Items/e1/PlaybackInfo")
    coordinator.endCurrentSession()
  }

  func testSeriesWithoutPlayableEpisodesExplains() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|s1": #"{"Id":"s1","Type":"Series"}"#]
      $0.episodes = ["lan.playback-tests.local|s1": #"{"Items":[]}"#]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "s1"))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.noEpisodes.errorDescription)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/PlaybackInfo") })
  }

  func testOtherItemTypesAreRejected() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|b1": #"{"Id":"b1","Type":"BoxSet"}"#]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "b1"))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.unsupportedItemType.errorDescription)
  }

  func testLibraryItemIsPlayedFromTheServerThatOwnsIt() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "a", host: "lan.playback-tests.local")),\(Self.embyServer(name: "b", host: "wan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["wan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "m1", expected: expectation()))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "wan.playback-tests.local")
    coordinator.endCurrentSession()
  }

  func testLibraryItemSkipsSameIDOfAnotherTypeOnEarlierServer() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "a", host: "lan.playback-tests.local")),\(Self.embyServer(name: "b", host: "wan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      // 两台 Emby 的数字 ID 撞号：a 上同号的是一集剧集，b 上才是要播的电影。
      $0.items = [
        "lan.playback-tests.local|m1": Self.movie(type: "Episode"),
        "wan.playback-tests.local|m1": Self.movie(),
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "m1", expected: expectation()))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "wan.playback-tests.local", "不能播 a 上同号的剧集")
    XCTAssertEqual(coordinator.session?.item.kind, .movie)
    coordinator.endCurrentSession()
  }

  func testLibraryItemPlaysEmbyItemFoundByExternalID() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: "lan.playback-tests.local")),\(Self.plexServer)]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["lan.playback-tests.local|tmdb.222": Self.movie(id: "731", tmdb: "222")]
      $0.items = ["lan.playback-tests.local|731": Self.movie(id: "731", tmdb: "222")]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "42", expected: expectation(tmdb: "222")))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.path, "/Videos/731/stream.mp4")
    coordinator.endCurrentSession()
  }

  func testSingleServerPlaysLibraryItemWithoutExternalID() async throws {
    // 只启用了一台服务器时 ID 只可能来自它，条目没刮削编号也照常播放。
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "m1", expected: expectation(tmdb: "222")))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "m1")
    coordinator.endCurrentSession()
  }

  func testLibraryItemSkipsSameIDAndTypeWithOtherExternalID() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "a", host: "lan.playback-tests.local")),\(Self.embyServer(name: "b", host: "wan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "lan.playback-tests.local|7": Self.movie(id: "7", tmdb: "111"),
        "wan.playback-tests.local|7": Self.movie(id: "7", tmdb: "222"),
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "7", expected: expectation(tmdb: "222")))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "wan.playback-tests.local", "不能播 a 上同号、外部编号不同的电影")
    coordinator.endCurrentSession()
  }

  func testHTTPDomainBlockedByTransportSecurityExplainsFix() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.transportSecurityHosts = ["lan.playback-tests.local"]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertTrue(coordinator.failure?.message.contains("http 域名") == true)
  }

  func testNonEmbyServerIsRejectedBeforeContactingIt() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = #"[{"name":"jf","type":"jellyfin","enabled":true,"config":{"host":"lan.playback-tests.local","apikey":"k"}}]"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "jf", itemID: "m1"))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.serverNotSupported("jf").errorDescription)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.host == "lan.playback-tests.local" })
  }

  func testSessionChangeDuringResolveDropsResult() async throws {
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
      $0.usersGate = gate
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    coordinator.play(.serverItem(serverName: "emby", itemID: "m1"))
    let task = try XCTUnwrap(coordinator.resolveTaskForTesting)

    for _ in 0..<200 where !PlaybackURLProtocol.stub.requests().contains(where: { $0.url.path.hasSuffix("/Users") }) {
      try await Task.sleep(for: .milliseconds(10))
    }
    service.tokenForTesting = "another-token"
    gate.signal()
    await task.value

    // Emby 请求与 MoviePilot 会话无关，可以跑完；结果在发布前按会话丢弃。
    XCTAssertNil(coordinator.session)
    XCTAssertNil(coordinator.resumePrompt)
    XCTAssertNil(coordinator.failure)
    XCTAssertFalse(coordinator.isResolving)
  }

  func testConnectionIsReusedAcrossPlays() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    coordinator.endCurrentSession()
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNotNil(coordinator.session)
    coordinator.endCurrentSession()

    let paths = PlaybackURLProtocol.stub.requests().map(\.url.path)
    XCTAssertEqual(paths.filter { $0.hasSuffix("/System/Info/Public") }.count, 1, "第二次播放不再探测地址")
    XCTAssertEqual(paths.filter { $0.hasSuffix("/Users") }.count, 1, "第二次播放不再查询用户")
  }

  func testCachedAddressThatStopsRespondingIsReprobed() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local", playHost: "https://wan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "lan.playback-tests.local|m1": Self.movie(),
        "wan.playback-tests.local|m1": Self.movie(),
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(streamURL(coordinator)?.host, "lan.playback-tests.local", "内网和外网都通时用内网")
    coordinator.endCurrentSession()

    // 离开内网：缓存的内网地址连不上，重新探测后改用外网。
    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = ["lan.playback-tests.local"] }
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "wan.playback-tests.local")
    coordinator.endCurrentSession()
  }

  private static let plexServer =
    #"{"name":"plex","type":"plex","enabled":true,"config":{"host":"plex.playback-tests.local","token":"k"}}"#

  private func servers(_ entries: String...) throws -> [MediaServerConf] {
    try JSONDecoder().decode([MediaServerConf].self, from: Data("[\(entries.joined(separator: ","))]".utf8))
  }

  /// 详情页条目的期望：默认电影、不带外部编号（只比类型）。
  private func expectation(_ mediaType: String = "电影", tmdb: String? = nil) -> LibraryItemExpectation {
    LibraryItemExpectation(mediaType: mediaType, externalIDs: tmdb.map { ["tmdb": $0] } ?? [:])
  }

  private static func movie(id: String, tmdb: String?) -> String {
    let providerIDs = tmdb.map { #","ProviderIds":{"Tmdb":"\#($0)"}"# } ?? ""
    return #"{"Id":"\#(id)","Name":"测试电影","Type":"Movie","RunTimeTicks":\#(twoHours)\#(providerIDs)}"#
  }

  func testDetailPageMatchesExternalIDWhenSameIDAndTypeCollide() async throws {
    let servers = try servers(
      Self.embyServer(name: "a", host: "lan.playback-tests.local"),
      Self.embyServer(name: "b", host: "wan.playback-tests.local"))
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      // 两台 Emby 上的 7 都是电影，只有外部编号能分清。
      $0.items = [
        "lan.playback-tests.local|7": Self.movie(id: "7", tmdb: "111"),
        "wan.playback-tests.local|7": Self.movie(id: "7", tmdb: "222"),
      ]
    }
    let coordinator = makeCoordinator(makeService())

    let second = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "222"), in: servers)
    XCTAssertEqual(second, .serverItem(serverName: "b", itemID: "7"), "a 上同号的电影外部编号对不上，不能选它")
    let first = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "111"), in: servers)
    XCTAssertEqual(first, .serverItem(serverName: "a", itemID: "7"))
    let neither = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "333"), in: servers)
    XCTAssertNil(neither, "两台都对不上就不显示播放")
  }

  func testSeveralServersRequireExternalIDMatchNotJustType() async throws {
    let servers = try servers(
      Self.embyServer(name: "a", host: "lan.playback-tests.local"),
      Self.embyServer(name: "b", host: "wan.playback-tests.local"))
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      // a 上的 7 是没刮削的电影（没有 TMDB 编号），b 上的 7 才是 TMDB 222。
      $0.items = [
        "lan.playback-tests.local|7": Self.movie(id: "7"),
        "wan.playback-tests.local|7": Self.movie(id: "7", tmdb: "222"),
      ]
    }
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "222"), in: servers)
    XCTAssertEqual(target, .serverItem(serverName: "b", itemID: "7"), "多台服务器时只有类型相符不算找到")

    PlaybackURLProtocol.stub.configure { $0.items = ["lan.playback-tests.local|7": Self.movie(id: "7")] }
    let unconfirmed = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "222"), in: servers)
    XCTAssertNil(unconfirmed, "编号对不上的条目不显示播放")
  }

  func testDetailPageFindsEmbyItemByExternalIDWhenServerIDsDiffer() async throws {
    // MoviePilot 给的 42 是 Plex 上的 ID；同一部片在 Emby 上是 731。
    let servers = try servers(Self.embyServer(name: "a", host: "lan.playback-tests.local"), Self.plexServer)
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["lan.playback-tests.local|tmdb.222": Self.movie(id: "731", tmdb: "222")]
    }
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem("42", expected: expectation(tmdb: "222"), in: servers)
    XCTAssertEqual(target, .serverItem(serverName: "a", itemID: "731"), "用 Emby 自己的条目 ID")
    let search = try XCTUnwrap(PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/Items") })
    let query = URLComponents(url: search.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "AnyProviderIdEquals", value: "tmdb.222")))
    XCTAssertTrue(query.contains(URLQueryItem(name: "IncludeItemTypes", value: "Movie")))
  }

  func testDetailPageIgnoresSearchResultsThatDoNotMatch() async throws {
    // 不认识搜索参数的服务器会返回不相干的条目，要再核对编号。
    let servers = try servers(Self.embyServer(name: "a", host: "lan.playback-tests.local"), Self.plexServer)
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["lan.playback-tests.local|tmdb.222": Self.movie(id: "5", tmdb: "999")]
    }
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem("42", expected: expectation(tmdb: "222"), in: servers)
    XCTAssertNil(target)
  }

  func testDetailPageFindsItemByValidExternalIDWhenDetailHasPlaceholderTMDB() async throws {
    // 详情的 TMDB 是 0、IMDb 有效；Emby 上的那部片 TMDB 222、IMDb 相同，要能找到。
    let servers = try servers(Self.embyServer(name: "a", host: "lan.playback-tests.local"), Self.plexServer)
    let found = #"{"Id":"731","Name":"测试电影","Type":"Movie","ProviderIds":{"Tmdb":"222","Imdb":"tt123456"}}"#
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["lan.playback-tests.local|imdb.tt123456": found]
    }
    let coordinator = makeCoordinator(makeService())
    let media = MediaInfo(tmdb_id: 0, imdb_id: "tt123456", type: "电影")
    let target = await coordinator.locateLibraryItem("42", expected: LibraryItemExpectation(media: media), in: servers)
    XCTAssertEqual(target, .serverItem(serverName: "a", itemID: "731"))
    let search = try XCTUnwrap(PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/Items") })
    let query = URLComponents(url: search.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "AnyProviderIdEquals", value: "imdb.tt123456")))
  }

  func testDetailPageSkipsEmbyLookupWhenOnlyEnabledServerIsPlayableEmby() async throws {
    let servers = try servers(
      Self.embyServer(name: "a", host: "lan.playback-tests.local"),
      #"{"name":"off","type":"plex","enabled":false}"#)
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem("m1", expected: expectation(), in: servers)
    XCTAssertEqual(target, .libraryItem(itemID: "m1", expected: expectation()), "起播时仍按类型确认")
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().isEmpty, "条目 ID 只可能来自这台 Emby，不必确认")
  }

  func testDetailPageConfirmsOwnerAmongSeveralEmbyServers() async throws {
    let servers = try servers(
      Self.embyServer(name: "a", host: "lan.playback-tests.local"),
      Self.embyServer(name: "b", host: "wan.playback-tests.local"))
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      // 两台 Emby 的数字 ID 撞号：a 上的 7 是剧集，b 上的 7 是电影。
      $0.items = [
        "lan.playback-tests.local|7": #"{"Id":"7","Type":"Series"}"#,
        "wan.playback-tests.local|7": Self.movie(id: "7"),
      ]
    }
    let coordinator = makeCoordinator(makeService())

    let movie = await coordinator.locateLibraryItem("7", expected: expectation(), in: servers)
    XCTAssertEqual(movie, .serverItem(serverName: "b", itemID: "7"), "全是 Emby 也要逐台核对，不能播 a 上同号的剧集")
    let series = await coordinator.locateLibraryItem("7", expected: expectation("电视剧"), in: servers)
    XCTAssertEqual(series, .serverItem(serverName: "a", itemID: "7"))
  }

  func testDetailPageLocatesLibraryItemOnEmbyWhenOtherServersAreEnabled() async throws {
    let servers = try servers(
      Self.embyServer(name: "a", host: "lan.playback-tests.local"),
      Self.embyServer(name: "b", host: "wan.playback-tests.local"),
      Self.plexServer)
    PlaybackURLProtocol.stub.configure {
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "wan.playback-tests.local|m1": Self.movie(),
        "lan.playback-tests.local|42": #"{"Id":"42","Type":"BoxSet"}"#,
      ]
    }
    let coordinator = makeCoordinator(makeService())

    let found = await coordinator.locateLibraryItem("m1", expected: expectation(), in: servers)
    XCTAssertEqual(found, .serverItem(serverName: "b", itemID: "m1"))
    // 只在 Plex 上的条目：所有 Emby 都确认没有，不显示播放。
    let missing = await coordinator.locateLibraryItem("plex-only", expected: expectation(), in: servers)
    XCTAssertNil(missing)
    // Plex 的数字 ID 在 Emby 上撞到类型不符的条目，不算找到。
    let collided = await coordinator.locateLibraryItem("42", expected: expectation(), in: servers)
    XCTAssertNil(collided)
    // 连不上时无法确认，仍显示播放，点击后再说明原因。
    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = ["lan.playback-tests.local", "wan.playback-tests.local"] }
    let uncertain = await coordinator.locateLibraryItem("x", expected: expectation(), in: servers)
    XCTAssertEqual(uncertain, .libraryItem(itemID: "x", expected: expectation()))
  }

  func testConnectionExpiresAndReselectsUser() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    var now = Date(timeIntervalSince1970: 1_000_000)
    let service = makeService()
    services.append(service)
    let coordinator = PlaybackCoordinator(
      apiService: service, mediaServerSession: PlaybackURLProtocol.session, isEnabledInSettings: { true },
      now: { now })
    func userLookups() -> Int {
      PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Users") }.count
    }

    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    coordinator.endCurrentSession()
    now += PlaybackCoordinator.connectionTTL - 1
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    coordinator.endCurrentSession()
    XCTAssertEqual(userLookups(), 1)

    // 到期后重新连接，Emby 端删改用户后能自行恢复。
    now += 2
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    coordinator.endCurrentSession()
    XCTAssertEqual(userLookups(), 2)
  }

  func testChangedMoviePilotUserNameReselectsEmbyUser() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        #"[{"name":"emby","type":"emby","enabled":true,"config":{"host":"lan.playback-tests.local","apikey":"k"}}]"#
      $0.users = #"[{"Id":"u-root","Name":"root","Policy":{"IsAdministrator":true}},{"Id":"u-bob","Name":"bob"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    coordinator.endCurrentSession()

    service.currentUserForTesting = Token(
      access_token: "mp-token", token_type: "bearer", super_user: FlexibleBool(true),
      permissions: nil, user_id: 1, user_name: "bob", avatar: nil)
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    let itemRequest = PlaybackURLProtocol.stub.requests().last { $0.url.path.contains("/Items/m1") && $0.method == "GET" }
    XCTAssertEqual(itemRequest?.url.path, "/Users/u-bob/Items/m1", "MoviePilot 用户名变了，重选同名 Emby 用户")
    coordinator.endCurrentSession()
  }

  func testLoggedInMoviePilotUserComesBeforeConfiguredUserName() async throws {
    // 与 MoviePilot 首页的继续观看相同：登录用户名和服务器配置的用户名在 Emby 里都有时，用登录的那个，
    // 播放写回的进度才会出现在首页的继续观看里。
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin","Policy":{"IsAdministrator":true}},{"Id":"u-bob","Name":"bob"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
    }
    let service = makeService()
    service.currentUserForTesting = Token(
      access_token: "mp-token", token_type: "bearer", super_user: FlexibleBool(true),
      permissions: nil, user_id: 1, user_name: "bob", avatar: nil)
    let coordinator = makeCoordinator(service)

    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.userID, "u-bob", "服务器配置的用户名是 admin，但登录的是 bob")
    coordinator.endCurrentSession()
  }

  /// mpv 报错经会话的 `onFailure` 交到协调器，提示按错误类别给出，不再一律说网络连接。
  func testMPVFailureShowsMessageMatchingErrorCategory() async throws {
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)

    // 模拟器上杜比视界 P5 被原生输出拒绝时 mpv 实际发来的错误。
    session.handleCurrent(
      .stateChanged(.failed(.nativeVideoOutputUnavailable("software Dolby Vision needs libplacebo reshaping"))))

    XCTAssertEqual(coordinator.failure?.message, "该片源为杜比视界格式，这台设备无法硬件解码")
    XCTAssertNil(coordinator.session, "播放失败后结束会话")

    let other = makeCoordinator(makeService())
    let next = try await startEpisodeSession(other)
    var received: [String] = []
    next.onFailure = { received.append($0) }
    next.handleCurrent(.error(.loadFailed(code: -17, message: "unrecognized file format"), fatal: true))
    next.handleCurrent(.error(.loadFailed(code: -13, message: "loading failed"), fatal: true))
    next.handleCurrent(.error(.seekTimedOut, fatal: false))

    XCTAssertEqual(
      received, ["无法识别该片源的格式，文件可能已损坏", "无法从媒体服务器读取片源，请检查网络和服务器状态"],
      "格式无法识别不说网络；片源打不开才提网络；非致命错误不提示")
    other.endCurrentSession()
  }

  private func startEpisodeSession(
    _ coordinator: PlaybackCoordinator, playbackInfo: String = PlaybackCoordinatorTests.playbackInfo(container: "mkv")
  ) async throws -> PlaybackSession {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "lan.playback-tests.local|e1": #"{"Id":"e1","Type":"Episode","Name":"一","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#,
        "lan.playback-tests.local|e2": #"{"Id":"e2","Type":"Episode","Name":"二","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":2}"#,
      ]
      $0.playbackInfo = playbackInfo
    }
    await run(coordinator, .serverItem(serverName: "emby", itemID: "e1"))
    return try XCTUnwrap(coordinator.session)
  }

  private func stoppedItem(completed: Bool = false) -> PlaybackSession.EndedItem {
    let item = ServerMediaItem(id: "e1", kind: .episode)
    let source = ServerMediaSource(id: "src1", container: "mkv")
    return PlaybackSession.EndedItem(
      stream: PreparedStream(
        item: item, source: source, sources: [source], playSessionID: "ps1",
        streamURL: URL(string: "http://lan.playback-tests.local/Videos/e1/stream.mkv")!),
      positionSeconds: 60,
      progress: WatchProgress(
        itemID: "e1", completed: completed, positionSeconds: 60, playedAt: Date(timeIntervalSince1970: 0)))
  }

  private var stubEmbyConnection: EmbyServerConnection {
    EmbyServerConnection(
      serverName: "emby", config: MediaServerConnectionConfig(host: nil, playHost: nil, apiKey: "emby-key", username: nil),
      preferredUserName: nil,
      client: EmbyClient(
        baseURL: URL(string: "http://lan.playback-tests.local")!, apiKey: "emby-key", deviceID: "device",
        session: PlaybackURLProtocol.session),
      userID: "u-admin")
  }

  func testStoppingWritesProgressOnTopOfFreshUserData() async throws {
    // 开播时的剧集来自剧集列表（Emby 列表里 PlayCount 恒为 0）；写回要以单条条目的真实数据为底，只改进度相关字段。
    PlaybackURLProtocol.stub.configure {
      $0.items = [
        "lan.playback-tests.local|e1":
          #"{"Id":"e1","Type":"Episode","UserData":{"PlayCount":3,"Played":true,"IsFavorite":true,"PlaybackPositionTicks":0,"Key":"k1"}}"#
      ]
    }
    await PlaybackSession.finishItem(stoppedItem(), connection: stubEmbyConnection)

    let requests = PlaybackURLProtocol.stub.requests()
    XCTAssertEqual(
      requests.map { "\($0.method) \($0.url.path)" },
      ["POST /Sessions/Playing/Stopped", "GET /Users/u-admin/Items/e1", "POST /Users/u-admin/Items/e1/UserData"],
      "先上报停止，再读最新用户数据，最后写回")
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(requests.last).body) as? [String: Any])
    XCTAssertEqual(body["PlayCount"] as? Int, 3, "不能把真实播放次数写成列表里的 0")
    XCTAssertEqual(body["IsFavorite"] as? Bool, true)
    XCTAssertEqual(body["Played"] as? Bool, true)
    XCTAssertEqual(body["Key"] as? String, "k1")
    XCTAssertEqual(body["PlaybackPositionTicks"] as? Int, 600_000_000)
    XCTAssertEqual(body["LastPlayedDate"] as? String, "1970-01-01T00:00:00Z")
  }

  func testStoppingAfterFinishingMarksPlayedAndClearsResumePoint() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.items = [
        "lan.playback-tests.local|e1":
          #"{"Id":"e1","Type":"Episode","UserData":{"PlayCount":1,"Played":false,"PlaybackPositionTicks":5000}}"#
      ]
    }
    await PlaybackSession.finishItem(stoppedItem(completed: true), connection: stubEmbyConnection)

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(PlaybackURLProtocol.stub.requests().last).body) as? [String: Any])
    XCTAssertEqual(body["Played"] as? Bool, true)
    XCTAssertEqual(body["PlaybackPositionTicks"] as? Int, 0)
    XCTAssertEqual(body["PlayCount"] as? Int, 1)
  }

  func testStoppingDoesNotWriteWhenUserDataCannotBeRead() async {
    // 条目读不到，或回包里没有用户数据：不提交残缺对象，免得覆盖收藏等字段。
    PlaybackURLProtocol.stub.configure {
      $0.items = ["lan.playback-tests.local|e1": #"{"Id":"e1","Type":"Episode"}"#]
    }
    await PlaybackSession.finishItem(stoppedItem(), connection: stubEmbyConnection)
    PlaybackURLProtocol.stub.configure { $0.items = [:] }
    await PlaybackSession.finishItem(stoppedItem(), connection: stubEmbyConnection)

    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/UserData") },
      "读不到用户数据时不写回")
  }

  func testSwitchingToAnotherVersionPlaysThatSource() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo =
        #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Name":"1080p","Container":"mp4","Protocol":"File","MediaStreams":[]},{"Id":"src2","Name":"4K","Container":"mkv","Protocol":"File","MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.mediaSource.id, "src1")
    XCTAssertEqual(session.mediaSources.map(\.name), ["1080p", "4K"])

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "m1", mediaSourceID: "src2", startPosition: 30, in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value

    guard case .switched = result else { return XCTFail("应切到另一个版本，实际 \(String(describing: result))") }
    XCTAssertTrue(coordinator.session === session, "同一个会话，全屏界面不重新弹出")
    XCTAssertEqual(session.mediaSource.id, "src2")
    XCTAssertEqual(session.streamURL.path, "/Videos/m1/stream.mkv")
    XCTAssertEqual(session.startSeconds, 30)
    coordinator.endSession(session)
  }

  func testResumeAskUsesSelectedSourceRuntime() async throws {
    // 条目记的是 2 小时的版本，起播的是 3 小时的加长版，停在 1 小时 55 分：离片尾还远，应询问续播。
    func prompt(sourceRuntime: String) async throws -> PlaybackCoordinator.ResumePrompt? {
      PlaybackURLProtocol.stub.reset()
      PlaybackURLProtocol.stub.configure {
        $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
        $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
        $0.items = ["lan.playback-tests.local|m1": Self.movie(positionSeconds: 6900)]
        $0.playbackInfo =
          #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mkv","Protocol":"File"\#(sourceRuntime),"MediaStreams":[]}]}"#
      }
      let coordinator = makeCoordinator(makeService())
      await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
      defer {
        coordinator.dismissResumePrompt()
        coordinator.endCurrentSession()
      }
      return coordinator.resumePrompt
    }

    let threeHours = #","RunTimeTicks":108000000000"#
    let extended = try await prompt(sourceRuntime: threeHours)
    XCTAssertEqual(extended?.position, 6900, "按所选片源的 3 小时算，1 小时 55 分还没接近片尾")
    let unknown = try await prompt(sourceRuntime: "")
    XCTAssertNil(unknown, "片源没给时长时退回条目的 2 小时：已过 90%，直接从头播放")
  }

  /// 从播放界面换集：界面发起，协调器解析并替换会话条目，界面再起播新条目。走真实的 `MediaSession` 和 mpv 播放器，
  /// 只证明三者交接正确；测试地址 mpv 打不开，画面能否真正播出来要在模拟器或真机上看。
  func testSwitchFromPlayerScreenLoadsNewItemOnceAndDropsOldEvents() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSession(coordinator)
    // mpv 打不开测试地址时会异步报失败，这里接住，免得结束会话；下面只在同步代码里比较前后次数。
    var failures: [String] = []
    session.onFailure = { failures.append($0) }
    let screen = MediaSession(
      session: session,
      onExit: { notice in coordinator.endSession(session, notice: notice) },
      onSwitchItem: { itemID, sourceID, position, episode, completion in
        coordinator.switchItem(
          to: itemID, mediaSourceID: sourceID, startPosition: position, episode: episode, in: session,
          completion: completion)
      })
    let player = try XCTUnwrap(session.mpvPlayer, "界面创建时建好播放器")
    let before = PlaybackURLProtocol.stub.requests().count

    screen.start()
    let firstGeneration = player.generation
    screen.playNewItem(intent: PlaybackIntent(item: BaseItemDto(id: "e2")))
    XCTAssertEqual(screen.state, .loadingItem, "解析期间显示加载中")
    await coordinator.switchTaskForTesting?.value
    await reporter.waitForQueued()

    XCTAssertEqual(session.item.id, "e2")
    XCTAssertEqual(screen.item.id, "e2", "界面的条目跟着换了")
    XCTAssertNotEqual(screen.state, .loadingItem, "新条目已起播，不再停在加载中")
    XCTAssertEqual(player.generation, firstGeneration + 2, "旧条目停止一次、新条目载入一次，没有重复载入")
    XCTAssertEqual(player.mediaInformation.sourceURL, session.streamURL, "交给 mpv 的是新条目的地址")
    let started = PlaybackURLProtocol.stub.requests().dropFirst(before)
      .filter { "\($0.method) \($0.url.path)" == "POST /Sessions/Playing" }
      .compactMap { (try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any])?["ItemId"] as? String }
    XCTAssertEqual(started, ["e1", "e2"], "每个条目各上报一次开始")

    // 上一条目还没读到的事件：播完、播放失败都不能算到新条目头上。
    let failuresBefore = failures.count
    screen.handlePlayerEvent(.stateChanged(.ended), generation: firstGeneration)
    XCTAssertNotEqual(screen.state, .stopped, "上一条目的播完不让新条目退出")
    XCTAssertNotEqual(screen.state, .loadingItem, "也不让新条目去接下一集")
    session.handle(.stateChanged(.failed(.playbackFailed(code: -16, message: "old"))), generation: firstGeneration)
    XCTAssertEqual(failures.count, failuresBefore, "上一条目的失败不结束新条目")

    // 同样的事件属于当前条目时照常处理，说明上面确实是按代号丢弃的。
    session.handle(.stateChanged(.failed(.playbackFailed(code: -16, message: "now"))), generation: player.generation)
    XCTAssertEqual(failures.count, failuresBefore + 1)
    screen.handlePlayerEvent(.stateChanged(.ended), generation: player.generation)
    XCTAssertTrue([.stopped, .loadingItem].contains(screen.state), "当前条目播完后退出或接下一集")

    screen.stop()
    coordinator.endCurrentSession()
    await reporter.waitForQueued()
  }

  private func requestPaths(after count: Int) -> [String] {
    PlaybackURLProtocol.stub.requests().dropFirst(count).map { "\($0.method) \($0.url.path)" }
  }

  /// 等被卡住的请求到达替身（最多 2 秒），再多等一会儿，让不该提前发出的请求有机会出现。
  /// 不用固定时长：机器忙时请求可能晚到，固定等待会误判。
  private func waitUntilBlocked(on path: String, after count: Int) async throws {
    for _ in 0..<200 where !requestPaths(after: count).contains(path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(200))
  }

  private func progressEvents(after count: Int) -> [String?] {
    PlaybackURLProtocol.stub.requests().dropFirst(count)
      .filter { $0.url.path.hasSuffix("/Progress") }
      .map { (try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any])?["EventName"] as? String }
  }

  /// 起播一集并让剧集回包带用户数据（停止后才写得回进度）。
  private func startEpisodeSessionWithUserData(
    _ coordinator: PlaybackCoordinator
  ) async throws -> PlaybackSession {
    let session = try await startEpisodeSession(coordinator)
    PlaybackURLProtocol.stub.configure {
      $0.items["lan.playback-tests.local|e1"] =
        #"{"Id":"e1","Type":"Episode","Name":"一","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"PlayCount":1}}"#
    }
    return session
  }

  /// mpv 跳过一条 zlib 压缩的轨道时的警告（mpv 在中间换行，日志回调分两条收到）。
  private func recordSkippedTrack(_ track: Int, in session: PlaybackSession) {
    session.record(
      MPVLogMessage(
        prefix: "mkv", level: .warning, message: "Track \(track) was compressed with zlib but mpv has not been compiled"))
    session.record(MPVLogMessage(prefix: "mkv", level: .warning, message: "with support for zlib compression. Skipping track."))
  }

  /// Emby 片源只有这些流时的 PlaybackInfo。
  private static func playbackInfo(streams: String) -> String {
    #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mkv","Protocol":"File","MediaStreams":[\#(streams)]}]}"#
  }

  func testFailureFromZlibCompressedTracksSaysSoInsteadOfBlamingTheNetwork() async throws {
    // MPVUI 的 libmpv 没编 zlib：画面和声音都压缩了的 MKV 一帧都解不出来。mpv 先警告跳过轨道，最后报什么都没播出来。
    // 片源只有一条视频、一条音频，两条都被跳过：确定是画面和声音压缩了。
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)
    recordSkippedTrack(1, in: session)
    recordSkippedTrack(2, in: session)
    session.handleCurrent(.stateChanged(.failed(.playbackFailed(code: -16, message: "no audio or video data played"))))

    XCTAssertEqual(
      coordinator.failure?.message, "音视频用了 zlib 压缩，无法解码，请用媒体服务器 App")
    XCTAssertNil(coordinator.session, "播放失败后结束会话")
  }

  func testZlibIsOnlyBlamedForPictureAndSoundWhenEveryTrackInTheFileWasSkipped() async throws {
    // mpv 的警告不说跳过的是哪类轨道：只有跳过的条数不少于文件里音视频和字幕轨的总数，才能确定画面和声音都在里面。
    let video = #"{"Type":"Video","Codec":"h264"}"#
    let audio = #"{"Type":"Audio","Codec":"aac"}"#
    let subtitle = #"{"Type":"Subtitle","Codec":"PGSSUB"}"#
    let external = #"{"Type":"Subtitle","Codec":"srt","IsExternal":true}"#
    let certain = "音视频用了 zlib 压缩，无法解码，请用媒体服务器 App"
    let possible = "有轨道用了 zlib 压缩，无法解码，请用媒体服务器 App"
    let cases: [(name: String, streams: String, skipped: [Int], expected: String)] = [
      ("跳过两条，文件里还有一条字幕：可能只是字幕压缩、音视频因别的原因没播出来", [video, audio, subtitle].joined(separator: ","), [1, 2], possible),
      ("跳过三条，文件里一共三条", [video, audio, subtitle].joined(separator: ","), [1, 2, 3], certain),
      ("外挂字幕不在文件里，不算", [video, audio, external].joined(separator: ","), [1, 2], certain),
      ("同一条轨道报了两次只算一条", [video, audio].joined(separator: ","), [1, 1], possible),
      ("服务器没给流信息：数不准", "", [1, 2, 3], possible),
      ("有流的类型认不出：数不准", [video, audio, #"{"Codec":"x"}"#].joined(separator: ","), [1, 2], possible),
    ]
    for item in cases {
      PlaybackURLProtocol.stub.reset()
      let coordinator = makeCoordinator(makeService())
      let session = try await startEpisodeSession(coordinator, playbackInfo: Self.playbackInfo(streams: item.streams))
      for track in item.skipped { recordSkippedTrack(track, in: session) }
      session.handleCurrent(.stateChanged(.failed(.playbackFailed(code: -16, message: "no audio or video data played"))))
      XCTAssertEqual(coordinator.failure?.message, item.expected, item.name)
    }
    for message in [certain, possible] {
      XCTAssertLessThanOrEqual(message.count, 30, "提示在全局通知里单行显示：\(message)")
    }
  }

  func testFailuresWithoutZlibEvidenceUseTheCategoryMessage() {
    XCTAssertEqual(
      PlaybackSession.failureMessage(
        for: .playbackFailed(code: -16, message: "no audio or video data played"), skippedCompressedTracks: 0,
        embeddedTrackCount: 2),
      PlaybackFailureMessage.nothingToPlay, "没看到 zlib 警告时不猜原因，按错误类别说")
    XCTAssertEqual(
      PlaybackSession.failureMessage(
        for: .loadFailed(code: -13, message: "loading failed"), skippedCompressedTracks: 2, embeddedTrackCount: 2),
      PlaybackFailureMessage.sourceUnreachable, "失败不是“什么都没播出来”时，另有原因，不说成 zlib")
  }

  func testReportsOfOnePlaybackAreSentInOrderWithEventNames() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSessionWithUserData(coordinator)
    let before = PlaybackURLProtocol.stub.requests().count

    session.itemDidLoadForTesting()
    await reporter.waitForQueued()
    session.handleCurrent(.pauseChanged(true))
    await reporter.waitForQueued()
    session.handleCurrent(.pauseChanged(false))
    await reporter.waitForQueued()
    coordinator.endSession(session)
    await reporter.waitForQueued()

    XCTAssertEqual(
      requestPaths(after: before),
      [
        "POST /Sessions/Playing", "POST /Sessions/Playing/Progress", "POST /Sessions/Playing/Progress",
        "POST /Sessions/Playing/Stopped", "GET /Users/u-admin/Items/e1", "POST /Users/u-admin/Items/e1/UserData",
      ])
    XCTAssertEqual(progressEvents(after: before), ["Pause", "Unpause"])
  }

  func testStopIsNotQueuedBehindStaleProgressWhileStartIsSlow() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSessionWithUserData(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.reportStartGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count

    // “开始”上报卡在网络上时连续暂停、继续，再退出。
    session.itemDidLoadForTesting()
    session.handleCurrent(.pauseChanged(true))
    session.handleCurrent(.pauseChanged(false))
    session.handleCurrent(.pauseChanged(true))
    coordinator.endSession(session)
    try await waitUntilBlocked(on: "POST /Sessions/Playing", after: before)
    let whileBlocked = requestPaths(after: before)
    gate.signal()
    await reporter.waitForQueued()

    XCTAssertEqual(whileBlocked, ["POST /Sessions/Playing"], "开始上报没完成前，后面的上报都不能先发")
    XCTAssertEqual(
      requestPaths(after: before),
      [
        "POST /Sessions/Playing", "POST /Sessions/Playing/Stopped", "GET /Users/u-admin/Items/e1",
        "POST /Users/u-admin/Items/e1/UserData",
      ],
      "还没发出的进度被停止取代，停止上报不排在过期进度后面")
  }

  func testQueuedProgressKeepsOnlyTheLatest() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSessionWithUserData(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.reportStartGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count

    session.itemDidLoadForTesting()
    for isPaused in [true, false, true, false] {
      session.handleCurrent(.pauseChanged(isPaused))
    }
    gate.signal()
    await reporter.waitForQueued()

    XCTAssertEqual(
      requestPaths(after: before), ["POST /Sessions/Playing", "POST /Sessions/Playing/Progress"],
      "Emby 慢时积压的进度只发最新一条")
    XCTAssertEqual(progressEvents(after: before), ["Unpause"])
    coordinator.endSession(session)
    await reporter.waitForQueued()
  }

  func testNextPlaybackWaitsForPreviousWriteBack() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let first = try await startEpisodeSessionWithUserData(coordinator)
    first.itemDidLoadForTesting()
    await reporter.waitForQueued()
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.reportStoppedGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count

    // 退出后马上重新播放同一集，而上一次的停止上报还卡在网络上。
    coordinator.endSession(first)
    coordinator.play(.serverItem(serverName: "emby", itemID: "e1"))
    let resolve = try XCTUnwrap(coordinator.resolveTaskForTesting)
    try await waitUntilBlocked(on: "POST /Sessions/Playing/Stopped", after: before)
    let whileBlocked = requestPaths(after: before)
    PlaybackURLProtocol.stub.configure { $0.reportStoppedGate = nil }
    gate.signal()
    await resolve.value
    let second = try XCTUnwrap(coordinator.session)
    second.itemDidLoadForTesting()
    await reporter.waitForQueued()

    XCTAssertEqual(whileBlocked, ["POST /Sessions/Playing/Stopped"], "上一次的写回没发完，这次不能先读条目的续播点")
    // 播放界面的信息要按剧的外部编号查 MoviePilot，先读剧条目；它和读播放信息同时进行，先后不定，单独核对。
    let paths = requestPaths(after: before)
    let seriesLookup = "GET /Users/u-admin/Items/s1"
    XCTAssertEqual(
      paths.filter { $0 != seriesLookup },
      [
        "POST /Sessions/Playing/Stopped", "GET /Users/u-admin/Items/e1", "POST /Users/u-admin/Items/e1/UserData",
        "GET /Users/u-admin/Items/e1", "POST /Items/e1/PlaybackInfo", "POST /Sessions/Playing",
      ])
    let lookupIndex = try XCTUnwrap(paths.firstIndex(of: seriesLookup))
    XCTAssertGreaterThan(lookupIndex, try XCTUnwrap(paths.lastIndex(of: "GET /Users/u-admin/Items/e1")), "也要等写回发完")
    coordinator.endSession(second)
    await reporter.waitForQueued()
  }

  func testCancellingWhileWaitingForPreviousWriteBackStopsAtOnce() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let first = try await startEpisodeSessionWithUserData(coordinator)
    first.itemDidLoadForTesting()
    await reporter.waitForQueued()
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.reportStoppedGate = gate }

    coordinator.endSession(first)
    coordinator.play(.serverItem(serverName: "emby", itemID: "e1"))
    let resolve = try XCTUnwrap(coordinator.resolveTaskForTesting)
    try await Task.sleep(for: .milliseconds(100))
    let clock = ContinuousClock()
    let cancelledAt = clock.now
    coordinator.cancelResolving()
    await resolve.value
    let elapsed = clock.now - cancelledAt
    gate.signal()
    await reporter.waitForQueued()

    XCTAssertLessThan(elapsed, .seconds(2), "取消不必等上一次的写回（最多 \(PlaybackCoordinator.pendingReportWait)）")
    XCTAssertNil(coordinator.session)
    XCTAssertNil(coordinator.failure)
  }

  func testLeavingForegroundSavesProgressWithoutStopping() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSessionWithUserData(coordinator)
    session.itemDidLoadForTesting()
    await reporter.waitForQueued()
    let before = PlaybackURLProtocol.stub.requests().count

    coordinator.saveProgressForBackground()
    await reporter.waitForQueued()

    XCTAssertEqual(
      requestPaths(after: before), ["GET /Users/u-admin/Items/e1", "POST /Users/u-admin/Items/e1/UserData"],
      "只写回观看进度，不上报停止")
    XCTAssertTrue(coordinator.session === session, "播放继续")
    XCTAssertFalse(session.isStopped)

    coordinator.endSession(session)
    await reporter.waitForQueued()
    XCTAssertEqual(
      requestPaths(after: before).suffix(3),
      ["POST /Sessions/Playing/Stopped", "GET /Users/u-admin/Items/e1", "POST /Users/u-admin/Items/e1/UserData"],
      "之后退出照常上报停止并写回")
  }

  func testSwitchingEpisodeReplacesItemAndKeepsPlayerScreen() async throws {
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)
    let player = session.makeMPVPlayer()
    var result: PlaybackCoordinator.SwitchResult?

    coordinator.switchItem(to: "e2", startPosition: 0, in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value

    guard case .switched = result else { return XCTFail("应切到下一集，实际 \(String(describing: result))") }
    XCTAssertTrue(coordinator.session === session, "同一个会话，全屏界面不重新弹出")
    XCTAssertFalse(session.isStopped)
    XCTAssertTrue(session.mpvPlayer === player, "复用同一个 mpv 播放器")
    XCTAssertEqual(session.streamURL.path, "/Videos/e2/stream.mkv")
    XCTAssertEqual(session.item.id, "e2")
    XCTAssertNil(coordinator.failure)

    coordinator.endSession(session)
    XCTAssertNil(coordinator.session)
    XCTAssertTrue(session.isStopped)
  }

  func testRapidSecondSwitchSupersedesFirstWithoutEarlyCompletion() async throws {
    let coordinator = makeCoordinator(makeService())
    let first = try await startEpisodeSession(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.playbackInfoGate = gate }
    var results: [PlaybackCoordinator.SwitchResult] = []

    coordinator.switchItem(to: "e2", in: first) { results.append($0) }
    let replaced = try XCTUnwrap(coordinator.switchTaskForTesting)
    coordinator.switchItem(to: "e2", in: first) { results.append($0) }
    let latest = try XCTUnwrap(coordinator.switchTaskForTesting)
    await replaced.value

    XCTAssertTrue(results.isEmpty, "被替换的切换不回报，界面保持加载状态")
    XCTAssertEqual(coordinator.switchTaskForTesting, latest, "旧任务结束不能清掉新任务")
    XCTAssertEqual(first.item.id, "e1")
    gate.signal()
    gate.signal()
    await latest.value

    XCTAssertEqual(results.count, 1)
    guard case .switched = results.first else { return XCTFail("应切到下一集，实际 \(results)") }
    XCTAssertTrue(coordinator.session === first)
    XCTAssertEqual(first.item.id, "e2")
    XCTAssertNil(coordinator.switchTaskForTesting)
    coordinator.endCurrentSession()
  }

  func testAccountChangeDuringSwitchPublishesNothing() async throws {
    let service = makeService()
    let coordinator = makeCoordinator(service)
    let first = try await startEpisodeSession(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.playbackInfoGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count
    var result: PlaybackCoordinator.SwitchResult?

    coordinator.switchItem(to: "e2", in: first) { result = $0 }
    let task = try XCTUnwrap(coordinator.switchTaskForTesting)
    for _ in 0..<200
    where !PlaybackURLProtocol.stub.requests().dropFirst(before).contains(where: { $0.url.path.hasSuffix("/PlaybackInfo") }) {
      try await Task.sleep(for: .milliseconds(10))
    }
    service.tokenForTesting = "another-token"
    gate.signal()
    await task.value

    guard case .discarded = result else { return XCTFail("账号切换后不应发布，实际 \(String(describing: result))") }
    XCTAssertEqual(first.item.id, "e1", "没有换成新条目")
    XCTAssertFalse(first.isStopped)
    coordinator.endCurrentSession()
  }

  func testCancelDuringResolveKeepsNothing() async throws {
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = Self.playbackInfo()
      $0.usersGate = gate
    }
    let coordinator = makeCoordinator(makeService())
    coordinator.play(.serverItem(serverName: "emby", itemID: "m1"))
    let task = try XCTUnwrap(coordinator.resolveTaskForTesting)
    coordinator.cancelResolving()
    XCTAssertFalse(coordinator.isResolving)
    gate.signal()
    await task.value
    XCTAssertNil(coordinator.session)
    XCTAssertNil(coordinator.failure)
    XCTAssertFalse(coordinator.isResolving)
  }
}

// MARK: - 按集播放（MoviePilot 集列表 + Emby 替身）

extension PlaybackCoordinatorTests {
  private static let lan = "lan.playback-tests.local"

  private static func series(id: String = "s1", tmdb: String = "100") -> String {
    #"{"Id":"\#(id)","Type":"Series","Name":"长风渡","ProviderIds":{"Tmdb":"\#(tmdb)"}}"#
  }

  /// Emby 上的一集：`tmdb` 是 TMDB 单集 ID，`season`/`episode` 是文件的季集号。
  private static func embyEpisode(_ id: String, season: Int, episode: Int, tmdb: Int?) -> String {
    let ids = tmdb.map { #","ProviderIds":{"Tmdb":"\#($0)"}"# } ?? ""
    return #"{"Id":"\#(id)","Type":"Episode","Name":"Emby 集名","SeriesName":"长风渡","ParentIndexNumber":\#(season),"IndexNumber":\#(episode)\#(ids)}"#
  }

  /// 适配器转换后的同一集。
  private static func serverEpisode(_ id: String, season: Int, episode: Int, tmdb: Int?) throws -> ServerMediaItem {
    try JSONDecoder().decode(EmbyItem.self, from: Data(embyEpisode(id, season: season, episode: episode, tmdb: tmdb).utf8))
      .serverItem(defaultKind: .episode)
  }

  private static func embyEpisodes(_ episodes: String...) -> String {
    #"{"Items":[\#(episodes.joined(separator: ","))]}"#
  }

  /// 剧集组第 1 季：组内第 10 集是 TMDB 单集 555（原第 2 季第 3 集），第 11 集是 556，第 12 集是 557。
  private static let groupSeason1 =
    #"[{"id":555,"season_number":2,"episode_number":10,"name":"重逢"},{"id":556,"season_number":2,"episode_number":11,"name":"离别"},{"id":557,"season_number":2,"episode_number":12,"name":"归来"}]"#

  /// 剧集组第 2 季：第 1 集（TMDB 601）还不在服务器上。
  private static let groupSeason2 = #"[{"id":601,"season_number":3,"episode_number":1,"name":"新篇"}]"#

  private func context(
    group: String? = "g1", libraryServer: String? = nil, libraryItemID: String = "s1"
  ) -> EpisodePlaybackContext {
    EpisodePlaybackContext(
      media: MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧"),
      episodeGroup: group, seasons: [1, 2],
      libraryItem: libraryServer.map { MediaServerItemRef(itemID: libraryItemID, server: $0) })!
  }

  private func groupEpisode(_ index: Int) throws -> MoviePilotEpisode {
    try groupSeason1()[index]
  }

  /// 详情页剧集组第 1 季的集列表。
  private func groupSeason1() throws -> [MoviePilotEpisode] {
    let episodes = try JSONDecoder().decode([TmdbEpisode].self, from: Data(Self.groupSeason1.utf8))
    return MoviePilotEpisode.list(episodes, season: 1)
  }

  /// 详情页上选的组内第 `index` 集，带着它所在的那一季。
  private func queued(_ index: Int, _ context: EpisodePlaybackContext? = nil) throws -> QueuedEpisode {
    QueuedEpisode(context: context ?? self.context(), episode: try groupEpisode(index), seasonEpisodes: try groupSeason1())
  }

  private func queueEntry(_ index: Int, item: ServerMediaItem) throws -> EpisodeQueueEntry {
    EpisodeQueueEntry(episode: try groupEpisode(index), item: item, seasonEpisodes: try groupSeason1())
  }

  /// 一台 Emby：剧 s1 的文件按 TMDB 默认顺序命名，S1E10 是另一集（TMDB 777），S2E3 才是组内第 10 集（555）。
  private func configureDefaultOrderLibrary() {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(Self.lan)|tmdb.100": Self.series()]
      $0.episodes = [
        "\(Self.lan)|s1": Self.embyEpisodes(
          Self.embyEpisode("e-s1e10", season: 1, episode: 10, tmdb: 777),
          Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
          Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557))
      ]
      // 起播前会重新读单条条目（续播点以此为准）。
      $0.items = [
        "\(Self.lan)|e-s1e10": Self.embyEpisode("e-s1e10", season: 1, episode: 10, tmdb: 777),
        "\(Self.lan)|e-s2e3": Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
        "\(Self.lan)|e-s2e5": Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557),
      ]
      $0.tmdbEpisodes = ["/api/v1/tmdb/100/1": Self.groupSeason1, "/api/v1/tmdb/100/2": Self.groupSeason2]
      $0.playbackInfo = Self.playbackInfo(container: "mkv")
    }
  }

  func testEpisodePlaysTheServerEpisodeWithTheSameTMDBEpisodeID() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))

    XCTAssertNil(coordinator.failure)
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.item.id, "e-s2e3", "按 TMDB 单集 ID 找，不按页面上的第 1 季第 10 集找")
    XCTAssertEqual(session.streamURL.path, "/Videos/e-s2e3/stream.mkv")
    XCTAssertEqual(session.titles.primary, "第 1 季 第 10 集 · 重逢", "播放器标题与详情页编号一致")
    XCTAssertEqual(session.titles.secondary, "长风渡")
    // 播放界面读的是 `BaseItemDto`：标题、季集号、剧名与续播询问同一来源，都按详情页的编号。
    let shown = BaseItemDto.playback(session.playback)
    XCTAssertEqual(shown.name, "重逢")
    XCTAssertEqual(shown.parentIndexNumber, 1)
    XCTAssertEqual(shown.indexNumber, 10)
    XCTAssertEqual(shown.seriesName, "长风渡")
    let episodesRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/Episodes") })
    let fields = URLComponents(url: episodesRequest.url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "Fields" }?.value
    XCTAssertEqual(
      fields, "ProviderIds,Path,PremiereDate,Overview", "集列表要带外部编号、文件路径、首播日期，和集列表缺简介时用的简介")
    coordinator.endCurrentSession()
  }

  func testEpisodesInThePlayerCarryTheirStillFromTheMoviePilotList() async throws {
    // 选集列表、上一集下一集的条目带上 MoviePilot 集列表里这一集的剧照，地址和详情页单集卡片的一样；
    // 集列表里没有剧照的集不带。
    configureDefaultOrderLibrary()
    let withStills =
      #"[{"id":555,"season_number":2,"episode_number":10,"name":"重逢","still_path":"/still-555.jpg"},{"id":556,"season_number":2,"episode_number":11,"name":"离别"},{"id":557,"season_number":2,"episode_number":12,"name":"归来","still_path":"/still-557.jpg"}]"#
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = withStills }
    let season = MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(withStills.utf8)), season: 1)
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(QueuedEpisode(context: context(), episode: season[0], seasonEpisodes: season)))
    let session = try XCTUnwrap(coordinator.session)
    func still(_ path: String) throws -> URL {
      try XCTUnwrap(APIService.shared.getSeasonPosterURL(posterPath: path, mediaPosterPath: nil))
    }

    let user = UserSession(session: session)
    let items = try await user.seasonEpisodes(seriesID: "100", seasonID: UserSession.queueSeasonID(1))
    XCTAssertEqual(items.map(\.id), ["e-s2e3", "e-s2e5"])
    XCTAssertEqual(items.map(\.landscapeImageURL), [try still("/still-555.jpg"), try still("/still-557.jpg")])
    XCTAssertEqual(
      items.first?.imageSources(for: .landscape, environment: .default).map(\.url), [try still("/still-555.jpg")],
      "选集卡片按横版取这张图")

    guard case .episode(let next, _) = try await user.adjacentEpisode(.next, itemID: "e-s2e3") else {
      return XCTFail("下一集是组内第 12 集")
    }
    XCTAssertEqual(next.landscapeImageURL, try still("/still-557.jpg"))

    let noStill = MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(Self.groupSeason1.utf8)), season: 1)
    XCTAssertNil(
      BaseItemDto.playback(
        session.item, episode: QueuedEpisode(context: context(), episode: noStill[0], seasonEpisodes: noStill)
      ).landscapeImageURL, "集列表里没有剧照时不带")
    coordinator.endCurrentSession()
  }

  func testEpisodeNotOnServerExplainsWithoutPlaying() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(1)))

    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, "没有在媒体服务器上找到这一集")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/PlaybackInfo") })
  }

  /// 默认顺序第 2 季的条目没有 TMDB 单集 ID（只用 TVDB 刮削），整理记录读不到：按季号集号对应。
  private func configureLibraryWithoutEpisodeIDs(_ episodes: String...) {
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.episodes = ["\(Self.lan)|s1": Self.embyEpisodes(episodes.joined(separator: ","))]
      for episode in episodes {
        guard let id = Self.itemID(episode) else { continue }
        $0.items["\(Self.lan)|\(id)"] = episode
      }
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.defaultSeason2
      $0.tmdbEpisodes["/api/v1/tmdb/100/1?episode_group=g1"] = Self.groupSeason1
      $0.tmdbEpisodes["/api/v1/tmdb/100/2?episode_group=g1"] = Self.groupSeason2
    }
  }

  private static func itemID(_ json: String) -> String? {
    (try? JSONDecoder().decode(EmbyItem.self, from: Data(json.utf8)))?.id
  }

  func testServerEpisodeWithoutTMDBIDIsMatchedByDefaultNumberingAndPlays() async throws {
    // 详情页看的是剧集组，文件按默认顺序命名为第 2 季第 3 集、没有 TMDB 单集 ID：按默认顺序对上组内第 10 集（555），不确定。
    configureLibraryWithoutEpisodeIDs(Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: nil))
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(
      availability,
      [.uncertain(server: "emby", match: UncertainEpisodeMatch(season: 2, episode: 3, episodeGroup: nil, airDate: .unknown))])
    let historyRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path == "/api/v1/history/transfer" }, "先查整理记录")
    let query = URLComponents(url: historyRequest.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(query.first { $0.name == "title" }?.value, "长风渡*", "先查标题以剧名开头的记录")
    XCTAssertEqual(query.first { $0.name == "status" }?.value, "true")

    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure, "整理记录读不到也照常按季号集号播")
    XCTAssertEqual(coordinator.session?.item.id, "e-s2e3")
    coordinator.endCurrentSession()
  }

  /// 没有 TMDB 单集 ID、Emby 也没解析出季号集号的文件，路径能对上 `transferRecord(mediaID: "100")`（挂载点不同）。
  private static let unnumberedFile =
    #"{"Id":"e-x","Type":"Episode","Name":"Emby 集名","SeriesName":"长风渡","Path":"/data/电视剧/长风渡 (2023)/Season 1/长风渡 - S01E10 - 第 10 集.mkv"}"#

  /// 一条成功的整理记录：剧集组 g1 第 1 季第 10 集。`mediaID` 是记录所属的剧，100 是长风渡。
  private static func transferRecord(mediaID: String, id: Int = 1) -> String {
    #"{"id":\#(id),"media_source":"themoviedb","media_id":"\#(mediaID)","type":"电视剧","seasons":"S01","episodes":"E10","episode_group":"g1","dest":"/media/tv/长风渡 (2023)/Season 1/长风渡 - S01E10 - 第 10 集.mkv","status":true}"#
  }

  /// 整理记录接口一页的 `data`。
  private static func transferPage(_ records: [String], total: Int?) -> String {
    #"{"list":[\#(records.joined(separator: ","))],"total":\#(total.map(String.init) ?? "null")}"#
  }

  /// 发出的整理记录查询，`title|page`。
  private func transferHistoryQueries() -> [String] {
    PlaybackURLProtocol.stub.requests().filter { $0.url.path == "/api/v1/history/transfer" }.map { request in
      let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func value(_ name: String) -> String { query.first { $0.name == name }?.value ?? "" }
      return "\(value("title"))|\(value("page"))"
    }
  }

  func testTransferRecordsAreLookedUpByTitlePrefixFirst() async throws {
    // MoviePilot 的 title 不带通配符时对标题和路径做分词包含匹配，短剧名会混进大量别的剧；先查标题以剧名开头的。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 1)]
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])
    XCTAssertEqual(transferHistoryQueries(), ["长风渡*|1"], "按开头查到了这部剧的记录，不再按包含查")
  }

  func testTransferRecordsFallBackToAContainingMatchWhenNoTitleStartsWithTheName() async throws {
    // 记录里存的标题可能和现在的剧名不同：按开头查到的记录里一条这部剧的都没有，才退回包含匹配。
    // 两种查法各自按整页条数和总数判断读完。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    let others = (1...100).map { Self.transferRecord(mediaID: "200", id: 1000 + $0) }
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage(others, total: 100),
        "长风渡|1": Self.transferPage(others, total: 101),
        "长风渡|2": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 101),
      ]
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])
    XCTAssertEqual(
      transferHistoryQueries(), ["长风渡*|1", "长风渡|1", "长风渡|2"],
      "按开头查：满页但总数只有 100 条就读完；包含匹配：第 1 页满页、总数 101，再读第 2 页，不足一页读完")
  }

  func testTitleWithWildcardCharactersFallsBackToAWildcardContainingMatch() async throws {
    // 剧名自带 `?`：MoviePilot 按通配符对整串匹配，原样传等于只认这个标题；退回时前后补 `*` 才是包含。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    PlaybackURLProtocol.stub.configure { $0.transferHistoryPages = ["Who?*|1": Self.transferPage([], total: 0)] }
    let coordinator = makeCoordinator(makeService())
    let context = try XCTUnwrap(
      EpisodePlaybackContext(
        media: MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "Who?", type: "电视剧"),
        episodeGroup: "g1", seasons: [1, 2], libraryItem: nil))
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context)
    XCTAssertEqual(transferHistoryQueries(), ["Who?*|1", "*Who?*|1"])
  }

  func testTitleWithLikeCharactersIsSentAsIsForMoviePilotToEscape() async throws {
    // MoviePilot 按通配符查时把 `\`、`%`、`_` 转义成字面字符（`_glob_to_like`），TV 端原样传、只在末尾加 `*`；
    // 退回包含匹配时剧名里没有 `*`、`?`，原样传。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    let title = #"A\B_100%"#
    PlaybackURLProtocol.stub.configure { $0.transferHistoryPages = ["\(title)*|1": Self.transferPage([], total: 0)] }
    let coordinator = makeCoordinator(makeService())
    let context = try XCTUnwrap(
      EpisodePlaybackContext(
        media: MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: title, type: "电视剧"),
        episodeGroup: "g1", seasons: [1, 2], libraryItem: nil))
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context)
    XCTAssertEqual(transferHistoryQueries(), [title + "*|1", title + "|1"])
  }

  func testForcedRereadOnSeveralServersAsksForTransferRecordsOnce() async throws {
    // 两台服务器上的文件都没有 TMDB 单集编号：强制重读时两台的集都重读，这部剧的整理记录只重读一次，两台共用。
    configureLibraryWithoutEpisodeIDs(Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: nil))
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.embyEpisode("f1", season: 2, episode: 4, tmdb: nil))
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 1)]
    }
    let coordinator = makeCoordinator(makeService())
    let episodes = try groupSeason1()
    _ = await coordinator.episodeAvailability(for: episodes, context: context())
    XCTAssertEqual(transferHistoryQueries().count, 1, "两台同时要整理记录，共用一次读取")

    _ = await coordinator.episodeAvailability(for: episodes, context: context(), forceRefresh: true)
    XCTAssertEqual(
      PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Episodes") }.count, 4, "两台的集都重读了")
    XCTAssertEqual(transferHistoryQueries().count, 2, "整理记录这一轮只重读一次，不是每台各一次")
  }

  func testServerThatNeedsTransferRecordsWhileTheForcedRereadIsInFlightWaitsForIt() async throws {
    // 刚整理好的这一集只在第二台上，文件没有 TMDB 单集编号，要靠整理记录对上。强制重读时第一台先去重读整理记录，
    // 还没读完第二台也要了：第二台要等这次重读，不能拿缓存里这一轮以前的记录建索引（那样这一集对不上，还会缓存下来）。
    let second = "lan2.playback-tests.local"
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"e-y","Type":"Episode","Name":"Emby 集名","SeriesName":"长风渡","Path":"/data/电视剧/长风渡 (2023)/Season 1/长风渡 - S01E11 - 第 11 集.mkv"}"#
    )
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.unnumberedFile)
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([], total: 0)]
    }
    let coordinator = makeCoordinator(makeService())
    let episode = try groupEpisode(0)
    let before = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertNotEqual(before, [.playable(server: "emby2")], "整理之前两台都对不上")

    let records = DispatchSemaphore(value: 0)
    let secondEpisodes = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 1)]
      $0.transferHistoryGate = records
      $0.episodesGates[second] = secondEpisodes
    }
    let queriesBefore = transferHistoryQueries().count
    let reread = Task { await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true) }
    for _ in 0..<300 where transferHistoryQueries().count == queriesBefore {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(transferHistoryQueries().count, queriesBefore + 1, "第一台开始重读整理记录")
    secondEpisodes.signal()
    // 第二台读完集列表、要整理记录时，第一台的重读还没回来。
    try await Task.sleep(for: .milliseconds(300))
    records.signal()
    records.signal()
    let after = await reread.value
    XCTAssertEqual(after, [.playable(server: "emby2")])
    XCTAssertEqual(transferHistoryQueries().count, queriesBefore + 1, "第二台跟上第一台的重读，不另读")
  }

  func testSpecialsThatTMDBDoesNotHaveDoNotTurnEveryMissingEpisodeIntoAReadFailure() async throws {
    // 服务器上有特别篇（第 0 季，没有 TMDB 单集编号），TMDB 没有第 0 季，MoviePilot 的第 0 季集列表是空的。
    // 季列表里确实没有第 0 季：这个文件按集列表里没有那一集处理，缺的集照常是没有（可以试看），不是整部剧都读取失败。
    configureLibraryWithoutEpisodeIDs(
      Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555), Self.embyEpisode("sp1", season: 0, episode: 1, tmdb: nil))
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/0"] = "[]"
      $0.mediaSeasons = #"[{"season_number":1,"name":"第 1 季"},{"season_number":2,"name":"第 2 季"}]"#
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(
      for: try defaultSeason2Episodes(), context: context(group: nil))
    XCTAssertEqual(availability, [.notOnServer, .playable(server: "emby"), .notOnServer, .notOnServer])
    let seasonsRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path == "/api/v1/media/seasons" }, "集列表是空的才读季列表")
    let query = URLComponents(url: seasonsRequest.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(query.first { $0.name == "media_source" }?.value, "themoviedb", "按 TMDB 身份查，不按剧名识别")
    XCTAssertEqual(query.first { $0.name == "media_id" }?.value, "100")
  }

  func testSpecialsThatTMDBDoesNotHaveDoNotStopAutoplayAtAMissingEpisode() async throws {
    // 同样的特别篇：MoviePilot 的第 0 季集列表是空的、季列表里没有第 0 季，不算没读全。
    // 组内第 11 集不在服务器上，播完第 10 集照常跳过它接着播第 12 集，不停在“读取失败”上。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
        Self.embyEpisode("sp1", season: 0, episode: 1, tmdb: nil),
        Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557))
      $0.tmdbEpisodes["/api/v1/tmdb/100/0"] = "[]"
      $0.mediaSeasons = #"[{"season_number":1,"name":"第 1 季"},{"season_number":2,"name":"第 2 季"}]"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(
      next,
      .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    coordinator.endCurrentSession()
  }

  func testServerEpisodeMatchedByTransferRecordIsConfirmed() async throws {
    // 文件没有 TMDB 单集 ID，Emby 也没解析出季号集号；路径和整理记录对得上（挂载点不同）：按记录的剧集组编号确定是组内第 10 集。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistory = """
        [{"id":2,"media_source":"themoviedb","media_id":"200","type":"电视剧","seasons":"S01","episodes":"E10","dest":"/media/别的剧/Season 1/长风渡 - S01E10 - 第 10 集.mkv","status":true},
         {"id":1,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S01","episodes":"E10","episode_group":"g1","dest":"/media/tv/长风渡 (2023)/Season 1/长风渡 - S01E10 - 第 10 集.mkv","status":true}]
        """
    }
    let coordinator = makeCoordinator(makeService())
    let inGroup = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(inGroup, [.playable(server: "emby")])
    let defaultOrder = try defaultSeason2Episodes()
    let inDefault = await coordinator.episodeAvailability(for: [defaultOrder[1]], context: context(group: nil))
    XCTAssertEqual(inDefault, [.playable(server: "emby")], "详情页选不选剧集组都是同一集")

    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-x")
    coordinator.endCurrentSession()
  }

  func testTransferPathsLearnTheDirectoryFromOtherIdentifiedEpisodes() async throws {
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"anchor-a","Type":"Episode","ParentIndexNumber":2,"IndexNumber":2,"ProviderIds":{"Tmdb":"554"},"Path":"/emby/第二季/02.mkv"}"#,
      #"{"Id":"anchor-b","Type":"Episode","ParentIndexNumber":2,"IndexNumber":4,"ProviderIds":{"Tmdb":"556"},"Path":"/emby/第二季/04.mkv"}"#,
      #"{"Id":"right","Type":"Episode","Path":"/emby/第二季/03.mkv"}"#,
      #"{"Id":"wrong","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/另一份/03.mkv"}"#)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistory = """
        [{"id":1,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S02","episodes":"E02","dest":"/mp/Season 2/02.mkv","status":true},
         {"id":2,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S02","episodes":"E04","dest":"/mp/Season 2/04.mkv","status":true},
         {"id":3,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S02","episodes":"E03","dest":"/mp/Season 2/03.mkv","status":true}]
        """
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])

    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "right")
    coordinator.endCurrentSession()
  }

  func testNextEpisodeMatchedOnlyByNumbersPlaysWithoutStopping() async throws {
    // 第 2 季第 3 集带编号，第 4 集没有：下一集照样接着播第 4 集的文件。
    configureLibraryWithoutEpisodeIDs(
      Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
      Self.embyEpisode("e-s2e4", season: 2, episode: 4, tmdb: nil))
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    guard case .play(let entry, let skipped) = next else { return XCTFail("应接着播第 4 集，实际 \(next)") }
    XCTAssertEqual(entry.item.id, "e-s2e4")
    XCTAssertEqual(entry.episode.tmdbEpisodeID, 556)
    XCTAssertFalse(skipped)

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(
      to: entry.item.id,
      episode: QueuedEpisode(context: context(), episode: entry.episode, seasonEpisodes: entry.seasonEpisodes),
      in: session
    ) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到第 4 集的文件，实际 \(String(describing: result))") }
    XCTAssertEqual(session.item.id, "e-s2e4")
    XCTAssertEqual(
      PlaybackURLProtocol.stub.requests().filter { $0.url.path == "/Shows/s1/Episodes" }.count, 1,
      "没有编号的条目按缓存的集索引核对，不重读整部剧")
    coordinator.endCurrentSession()
  }

  func testConfirmedEpisodeOnAnotherServerWinsOverANumberMatch() async throws {
    // 所属服务器 emby 上只按季号集号对上，emby2 上的文件带编号：以编号为准，播 emby2 的。
    configureLibraryWithoutEpisodeIDs(Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: nil))
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.embyEpisode("f1", season: 2, episode: 3, tmdb: 555))
      $0.items["\(second)|f1"] = Self.embyEpisode("f1", season: 2, episode: 3, tmdb: 555)
    }
    let coordinator = makeCoordinator(makeService())
    let owned = context(libraryServer: "emby")
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: owned)
    XCTAssertEqual(availability, [.playable(server: "emby2")])

    await run(coordinator, .episode(try queued(0, owned)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "f1")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path == "/Items/e-s2e3/PlaybackInfo" })
    coordinator.endCurrentSession()
  }

  func testAvailabilityMarksEachEpisodeAndReusesTheServerIndex() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    let missingID = MoviePilotEpisode(TmdbEpisode(id: nil, episodeNumber: 13), season: 1, index: 3)
    let episodes = [try groupEpisode(0), try groupEpisode(1), try groupEpisode(2), missingID]
    let availability = await coordinator.episodeAvailability(for: episodes, context: context())
    XCTAssertEqual(
      availability, [.playable(server: "emby"), .notOnServer, .playable(server: "emby"), .unidentifiable(.missingEpisodeID)])

    _ = await coordinator.episodeAvailability(for: episodes, context: context())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(
      PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Episodes") }.count, 1,
      "详情页的每集状态和起播共用这部剧的集索引")
    coordinator.endCurrentSession()
  }

  /// 默认顺序的第 2 季：554–557 依次是第 2–5 集。
  private static let defaultSeason2 =
    #"[{"id":554,"season_number":2,"episode_number":2},{"id":555,"season_number":2,"episode_number":3},{"id":556,"season_number":2,"episode_number":4},{"id":557,"season_number":2,"episode_number":5}]"#

  /// 一个文件包含第 2 季第 3、4 集，服务器只给它记了第 3 集的 TMDB 单集 ID（555）。
  private static let multiEpisodeFile =
    #"{"Id":"e-s2e3-4","Type":"Episode","Name":"Emby 集名","SeriesName":"长风渡","ParentIndexNumber":2,"IndexNumber":3,"IndexNumberEnd":4,"ProviderIds":{"Tmdb":"555"}}"#

  // MARK: 叫媒体服务器入库

  private static let nas2 = "nas2.playback-tests.local"
  private static let organizedFile = TransferredFileLocation(
    path: "/media/电视剧/国产剧/长风渡 (2023)/Season 2/长风渡 - S02E05.mkv", category: "国产剧")

  /// 两台 Emby：第一台有这部剧（s1），第二台没有。
  private func configureTwoServersWithSeriesOnTheFirst() {
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "nas2", host: Self.nas2))]"
    }
  }

  private func refreshRequests() -> [String] {
    PlaybackURLProtocol.stub.requests().filter { $0.method == "POST" && $0.url.path.hasSuffix("Refresh") }.map {
      "\($0.url.host ?? "")\($0.url.path)" + ($0.url.query.map { "?\($0)" } ?? "")
    }
  }

  func testLibraryScanRefreshesOnlyTheSeriesWhereItIsAlreadyOnTheServer() async throws {
    configureTwoServersWithSeriesOnTheFirst()
    let coordinator = makeCoordinator(makeService())
    await coordinator.requestLibraryScan(context: context(), scope: .located(Self.organizedFile))

    XCTAssertEqual(refreshRequests(), ["\(Self.lan)/Items/s1/Refresh?Recursive=true"], "已有这部剧的服务器只刷新这部剧")
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/Library/SelectableMediaFolders") },
      "有服务器已经有这部剧时，不去别的服务器找媒体库、也不刷新整个库")
  }

  func testLibraryScanWithoutTheSeriesRefreshesTheLibraryHoldingTheFile() async throws {
    configureTwoServersWithSeriesOnTheFirst()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch = [:]
      $0.mediaFolders = [
        Self.lan: #"[{"Id":"lib-movie","SubFolders":[{"Path":"/media/电影"}]},{"Id":"lib-tv","SubFolders":[{"Path":"/media/电视剧"}]}]"#,
        Self.nas2: #"[{"Id":"lib-other","SubFolders":[{"Path":"/volume1/影视"}]}]"#,
      ]
    }
    let coordinator = makeCoordinator(makeService())
    await coordinator.requestLibraryScan(context: context(), scope: .located(Self.organizedFile))

    XCTAssertEqual(
      refreshRequests(), ["\(Self.lan)/Items/lib-tv/Refresh?Recursive=true"],
      "哪台都没有这部剧时只刷新文件所在的媒体库，对不上的服务器不刷新")
  }

  func testLibraryScanRefreshesEveryWholeLibraryWhenThePathMatchesNowhere() async throws {
    // Docker 里 MoviePilot 和 Emby 挂载的路径不同：照 MoviePilot 的做法刷新整个库。
    configureTwoServersWithSeriesOnTheFirst()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch = [:]
      $0.mediaFolders = [Self.lan: #"[{"Id":"lib-tv","SubFolders":[{"Path":"/data/tv"}]}]"#]
    }
    let coordinator = makeCoordinator(makeService())
    await coordinator.requestLibraryScan(
      context: context(), scope: .located(TransferredFileLocation(path: Self.organizedFile.path, category: nil)))

    XCTAssertEqual(refreshRequests(), ["\(Self.lan)/Library/Refresh", "\(Self.nas2)/Library/Refresh"])
  }

  func testLibraryScanSkipsAServerThatCannotBeReached() async throws {
    configureTwoServersWithSeriesOnTheFirst()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch = [:]
      $0.unreachableHosts = [Self.nas2]
    }
    let coordinator = makeCoordinator(makeService())
    await coordinator.requestLibraryScan(
      context: context(), scope: .located(TransferredFileLocation(path: "/downloads/x.mkv", category: nil)))

    XCTAssertEqual(refreshRequests(), ["\(Self.lan)/Library/Refresh"], "连不上的服务器查不到有没有这部剧，不刷新它")
  }

  func testLibraryScanNeedsInAppPlayback() async throws {
    configureTwoServersWithSeriesOnTheFirst()
    let coordinator = makeCoordinator(makeService(superUser: false))
    await coordinator.requestLibraryScan(context: context(), scope: .located(Self.organizedFile))
    await coordinator.requestLibraryScan(context: context(), scope: .everything)
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().isEmpty)
  }

  func testWholeLibraryFallbackRefreshesEveryServerWithoutLookingForTheSeries() async throws {
    // 试看服务的兜底：按位置刷新过还没入库，可能刷错了地方，有没有这部剧都每台刷新整个库。
    configureTwoServersWithSeriesOnTheFirst()
    let coordinator = makeCoordinator(makeService())
    await coordinator.requestLibraryScan(context: context(), scope: .everything)

    XCTAssertEqual(refreshRequests(), ["\(Self.lan)/Library/Refresh", "\(Self.nas2)/Library/Refresh"])
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.method == "GET" && $0.url.path.hasSuffix("/Items") },
      "兜底不再查这部剧在哪")
  }

  private func configureMultiEpisodeFile() {
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.episodes = ["\(Self.lan)|s1": Self.embyEpisodes(Self.multiEpisodeFile)]
      $0.items["\(Self.lan)|e-s2e3-4"] = Self.multiEpisodeFile
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.defaultSeason2
    }
  }

  private func defaultSeason2Episodes() throws -> [MoviePilotEpisode] {
    MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(Self.defaultSeason2.utf8)), season: 2)
  }

  func testSecondEpisodeOfAMultiEpisodeFileIsPlayable() async throws {
    configureMultiEpisodeFile()
    let coordinator = makeCoordinator(makeService())
    let season = try defaultSeason2Episodes()
    let context = context(group: nil)
    let availability = await coordinator.episodeAvailability(for: season, context: context)
    XCTAssertEqual(
      availability, [.notOnServer, .playable(server: "emby"), .playable(server: "emby"), .notOnServer],
      "第 4 集在第 3 集的文件里，不能当成不在服务器上（否则会给它试看）")

    await run(coordinator, .episode(QueuedEpisode(context: context, episode: season[2], seasonEpisodes: season)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-s2e3-4", "播第 4 集就是播这个文件")
    coordinator.endCurrentSession()
  }

  func testGoingBackOntoTheSecondEpisodeOfAMultiEpisodeFilePlaysThatFile() async throws {
    configureMultiEpisodeFile()
    let e5 = Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)
    PlaybackURLProtocol.stub.configure {
      $0.episodes = ["\(Self.lan)|s1": Self.embyEpisodes(Self.multiEpisodeFile, e5)]
      $0.items["\(Self.lan)|e-s2e5"] = e5
    }
    let coordinator = makeCoordinator(makeService())
    let season = try defaultSeason2Episodes()
    let context = context(group: nil)
    await run(coordinator, .episode(QueuedEpisode(context: context, episode: season[3], seasonEpisodes: season)))
    let session = try XCTUnwrap(coordinator.session)

    let previous = try await coordinator.adjacentEpisode(.previous, from: session.playback)
    guard case .play(let entry, _) = previous else { return XCTFail("应能回到第 4 集，实际 \(previous)") }
    XCTAssertEqual(entry.episode.tmdbEpisodeID, 556)
    XCTAssertEqual(entry.item.id, "e-s2e3-4")

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(
      to: entry.item.id,
      episode: QueuedEpisode(context: context, episode: entry.episode, seasonEpisodes: entry.seasonEpisodes),
      in: session
    ) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到包含第 4 集的文件，实际 \(String(describing: result))") }
    XCTAssertEqual(session.item.id, "e-s2e3-4")
    coordinator.endCurrentSession()
  }

  func testMultiEpisodeFileThatCannotBeVerifiedIsNotTreatedAsMissing() async throws {
    configureMultiEpisodeFile()
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = "[]" }
    let coordinator = makeCoordinator(makeService())
    let season = try defaultSeason2Episodes()
    let availability = await coordinator.episodeAvailability(for: season, context: context(group: nil))
    XCTAssertEqual(availability?[1], .playable(server: "emby"), "文件自己记着的那一集照常能播")
    guard case .failed(let message) = availability?[2] else {
      return XCTFail("读不到默认顺序列表时第 4 集无法确认：\(String(describing: availability))")
    }
    XCTAssertTrue(message.contains("第 2 季集列表是空的"), message)
  }

  func testDetailPageOffersEpisodeEntriesForASeriesNotInTheLibrary() async throws {
    // 整部剧还不在媒体库里：没有整剧播放入口，但集列表要能查每集（都不在库）并提供试看。
    enableInAppPlaybackPreferenceForTest()
    configureDefaultOrderLibrary()
    let service = makeService()
    services.append(service)
    let detail = MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧")
    let viewModel = MediaDetailViewModel(detail: detail, apiService: service)
    viewModel.applyFullDetail(detail)
    try await waitUntil { viewModel.episodePlayback != nil }
    XCTAssertEqual(viewModel.episodePlayback, EpisodePlaybackSource(libraryItem: nil))
    XCTAssertNil(viewModel.inAppPlaybackTarget)
    viewModel.cancelForPop()
  }

  func testEpisodePlaybackNeedsBackend326() async throws {
    configureDefaultOrderLibrary()
    backendVersion = "v3.2.5"
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertNil(availability, "旧后端不显示每集的播放状态")
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.backendTooOld.errorDescription)
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().isEmpty, "不发任何请求")
  }

  func testEpisodeIsLookedUpOnTheServerMoviePilotNamesFirst() async throws {
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.embyEpisode("f1", season: 1, episode: 10, tmdb: 555))
      $0.items["\(second)|f1"] = Self.embyEpisode("f1", season: 1, episode: 10, tmdb: 555)
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby2"))))

    XCTAssertEqual(coordinator.session?.item.id, "f1")
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.host == Self.lan && $0.url.path.hasSuffix("/Episodes") },
      "入库查询说在 emby2，先查它，找到了就不再查别的服务器")
    coordinator.endCurrentSession()
  }

  func testNextEpisodeFollowsMoviePilotOrderOnTheCurrentServer() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)

    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(
      next,
      .play(
        try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)),
        skippedMissing: true),
      "组内第 11 集服务器上没有，跳到第 12 集；不用 Emby 自己的相邻集（S2E4）")
    let previous = try await coordinator.adjacentEpisode(.previous, from: session.playback)
    XCTAssertEqual(previous, .end)
    let tmdbRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path == "/api/v1/tmdb/100/1" })
    XCTAssertTrue(tmdbRequest.url.query?.contains("episode_group=g1") == true, "沿用开播时冻结的剧集组")

    // 换到下一集：沿用冻结的上下文，标题按详情页编号。
    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e-s2e5", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到下一集，实际 \(String(describing: result))") }
    XCTAssertEqual(session.episode?.episode, try groupEpisode(2))
    XCTAssertEqual(session.episode?.context, context())
    XCTAssertEqual(session.titles.primary, "第 1 季 第 12 集 · 归来")
    coordinator.endCurrentSession()
  }

  func testNextEpisodeOnAnotherServerStopsTheQueue() async throws {
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.embyEpisode("f2", season: 1, episode: 11, tmdb: 556))
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)

    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    guard case .stop(let reason) = next else { return XCTFail("下一集只在另一台服务器上，要停下，实际 \(next)") }
    XCTAssertTrue(reason.contains("另一台媒体服务器"), reason)

    coordinator.endSession(session, notice: reason)
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.notice?.message, reason, "退出后告诉用户为什么没有接着播")
  }

  func testInAppPlaybackTurnedOffInSettingsOffersNothing() async throws {
    configureDefaultOrderLibrary()
    enabledInSettings = false
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertNil(availability)
    let target = await coordinator.locateLibraryItem(
      "s1", expected: context().expected, in: try servers(Self.embyServer(name: "emby", host: Self.lan)))
    XCTAssertNil(target, "设置里关掉后详情页不显示播放")
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.disabledInSettings.errorDescription)
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().isEmpty, "不发任何请求")
  }

  func testEpisodeResumePointIsReadFreshBeforeStarting() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    // 集索引是刚才读的（没有续播点）；之后在别处看到 30 分钟，Emby 上的单条条目已经更新。
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e-s2e3"] =
        #"{"Id":"e-s2e3","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"ProviderIds":{"Tmdb":"555"},"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":18000000000}}"#
    }
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(coordinator.resumePrompt?.position, 1800, "续播点以起播前重新读到的为准，不用集索引里的旧值")
    XCTAssertEqual(coordinator.resumePrompt?.prepared.title, "长风渡 · 第 1 季 第 10 集 · 重逢")
  }

  func testUnplayableCopyFallsBackToAnotherCopyOnTheSameServer() async throws {
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      // 同一部剧在两个媒体库：strm 库排在前面，本地文件库在后面。
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(id: "strm"), Self.series(id: "local")].joined(separator: ",")
      $0.episodes = [
        "\(Self.lan)|strm": Self.embyEpisodes(Self.embyEpisode("x-strm", season: 2, episode: 3, tmdb: 555)),
        "\(Self.lan)|local": Self.embyEpisodes(Self.embyEpisode("x-local", season: 2, episode: 3, tmdb: 555)),
      ]
      $0.items = [
        "\(Self.lan)|x-strm": Self.embyEpisode("x-strm", season: 2, episode: 3, tmdb: 555),
        "\(Self.lan)|x-local": Self.embyEpisode("x-local", season: 2, episode: 3, tmdb: 555),
      ]
      $0.playbackInfoByItem["\(Self.lan)|x-strm"] =
        #"{"MediaSources":[{"Id":"remote","Container":"mkv","Protocol":"Http","MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "x-local", "第一份不能直连时换同一台服务器上的另一份")
    coordinator.endCurrentSession()
  }

  func testJustArrivedEpisodeIsFoundWhenPlayedFromDetail() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(1)], context: context())
    XCTAssertEqual(availability, [.notOnServer])
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(Self.embyEpisode("e-new", season: 2, episode: 4, tmdb: 556))
      $0.items["\(Self.lan)|e-new"] = Self.embyEpisode("e-new", season: 2, episode: 4, tmdb: 556)
    }
    await run(coordinator, .episode(try queued(1)))
    XCTAssertEqual(coordinator.session?.item.id, "e-new", "缓存里没有时重新读一次服务器")
    coordinator.endCurrentSession()
  }

  func testServerWithoutTheSeriesIsNotReadAgainWhenStarting() async throws {
    // 两台服务器，这部剧只在第二台上：第一台确认没有这部剧，起播时不再强制重读它。
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch = ["\(second)|tmdb.100": Self.series(id: "t1")]
      $0.episodes = ["\(second)|t1": Self.embyEpisodes(Self.embyEpisode("f1", season: 2, episode: 3, tmdb: 555))]
      $0.items = ["\(second)|f1": Self.embyEpisode("f1", season: 2, episode: 3, tmdb: 555)]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(coordinator.session?.item.id, "f1")
    let searchesOnFirst = PlaybackURLProtocol.stub.requests().filter {
      $0.url.host == Self.lan && ($0.url.query ?? "").contains("AnyProviderIdEquals")
    }
    XCTAssertEqual(searchesOnFirst.count, 1, "第一台只搜一次")
    coordinator.endCurrentSession()
  }

  func testQueuePanelOnlyReadsTheCurrentServer() async throws {
    // 另一台服务器关机：面板只列当前服务器上的集，不为每个没入库的集去连它。
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.unreachableHosts = [second]
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555))
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let requestsToSecond = { PlaybackURLProtocol.stub.requests().filter { $0.url.host == second }.count }
    let before = requestsToSecond()

    let entries = try await coordinator.playableEpisodes(inSeason: 1, from: session.playback)
    XCTAssertEqual(entries.map(\.item.id), ["e-s2e3"])
    XCTAssertEqual(requestsToSecond(), before, "第 11、12 集不在当前服务器上，也不去连另一台")
    coordinator.endCurrentSession()
  }

  func testSwitchingEpisodePlaysTheRequestedItemWithoutRereadingTheSeries() async throws {
    // 看完一集（早过了集索引的 60 秒缓存）换下一集：要求的条目能直接播，就不先重读整部剧的集。
    configureDefaultOrderLibrary()
    var clock = Date()
    let coordinator = makeCoordinator(makeService(), now: { clock })
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    clock += 45 * 60
    let seriesReads = {
      PlaybackURLProtocol.stub.requests().filter {
        $0.url.path.hasSuffix("/Episodes") || ($0.url.query ?? "").contains("AnyProviderIdEquals")
      }.count
    }
    let before = seriesReads()

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e-s2e5", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到第 12 集，实际 \(String(describing: result))") }
    XCTAssertEqual(session.item.id, "e-s2e5")
    XCTAssertEqual(seriesReads(), before)
    coordinator.endCurrentSession()
  }

  func testSwitchingToAnUnplayableCopyFallsBackToAnotherCopy() async throws {
    // 第 12 集在两个媒体库各有一份，队列给的是不能直连的 strm 那份：换同一台服务器上的另一份。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(), Self.series(id: "strm")].joined(separator: ",")
      $0.episodes["\(Self.lan)|strm"] = Self.embyEpisodes(Self.embyEpisode("x-strm", season: 2, episode: 5, tmdb: 557))
      $0.items["\(Self.lan)|x-strm"] = Self.embyEpisode("x-strm", season: 2, episode: 5, tmdb: 557)
      $0.playbackInfoByItem["\(Self.lan)|x-strm"] =
        #"{"MediaSources":[{"Id":"remote","Container":"mkv","Protocol":"Http","MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "x-strm", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到另一份，实际 \(String(describing: result))") }
    XCTAssertEqual(session.item.id, "e-s2e5")
    coordinator.endCurrentSession()
  }

  func testOwnerServerIsStillPreferredWhenTheDetailPageCouldNotConfirm() async throws {
    // 两台 Emby，入库查询说 7 属于 a，a 上的电影没刮到外部编号。进详情页时 a 连不上，只能判为不确定。
    let a = Self.embyServer(name: "a", host: "lan.playback-tests.local")
    let b = Self.embyServer(name: "b", host: "wan.playback-tests.local")
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(a),\(b)]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|7": Self.movie(id: "7", tmdb: nil)]
      $0.playbackInfo = Self.playbackInfo()
      $0.unreachableHosts = ["lan.playback-tests.local"]
    }
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem(
      "7", expected: expectation(tmdb: "222"), in: try servers(a, b), preferredServer: "a")
    XCTAssertEqual(target, .libraryItem(itemID: "7", expected: expectation(tmdb: "222"), owner: "a"))

    // 点播放时 a 已经能连上：它自己的条目不要求外部编号对上。
    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = [] }
    await run(coordinator, try XCTUnwrap(target))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "7")
    XCTAssertEqual(coordinator.session?.connection.serverName, "a")
    coordinator.endCurrentSession()
  }

  func testNextEpisodeThatArrivesDuringPlaybackIsFoundWhenRefreshed() async throws {
    // 订阅还在下载：开播时第 11、12 集都不在，播放期间第 11 集下载入库。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555))
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let before = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(before, .missing, "后面还有集，只是还没入库")

    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
        Self.embyEpisode("e-s2e4", season: 2, episode: 4, tmdb: 556))
    }
    let cached = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(cached, .missing, "不刷新时沿用缓存")
    let refreshed = try await coordinator.adjacentEpisode(.next, from: session.playback, refresh: true)
    XCTAssertEqual(
      refreshed,
      .play(
        try queueEntry(1, item: try Self.serverEpisode("e-s2e4", season: 2, episode: 4, tmdb: 556)),
        skippedMissing: false),
      "播完时重新读服务器，刚入库的下一集能接着播")
    coordinator.endCurrentSession()
  }

  func testNextIsFoundFromTheKnownSeasonWhenTheRefreshedListComesBackEmpty() async throws {
    // 播完时重新读集列表，MoviePilot 读 TMDB 失败、返回了空列表：下一集是组内第 12 集开播时就知道，服务器上有就接着播。
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = "[]" }

    let next = try await coordinator.adjacentEpisode(.next, from: session.playback, refresh: true)
    XCTAssertEqual(
      next, .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    let panel = try await coordinator.playableEpisodes(inSeason: 1, from: session.playback)
    XCTAssertEqual(panel.map(\.item.id), ["e-s2e3", "e-s2e5"], "队列面板同样按开播时的那份列")
    coordinator.endCurrentSession()
  }

  func testEpisodeStartReprobesACachedAddressThatStoppedResponding() async throws {
    // 详情页刚用内网地址读过集索引，点播放时已经离开内网：起播也要换外网地址重试，不能报“无法连接”。
    configureDefaultOrderLibrary()
    let wan = "wan.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan, playHost: "https://\(wan)"))]"
      $0.providerSearch["\(wan)|tmdb.100"] = Self.series()
      $0.episodes["\(wan)|s1"] = $0.episodes["\(Self.lan)|s1"]
      for (key, value) in $0.items where key.hasPrefix(Self.lan) {
        $0.items[key.replacingOccurrences(of: Self.lan, with: wan)] = value
      }
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])

    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = [Self.lan] }
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, wan)
    coordinator.endCurrentSession()
  }

  /// 刚入库、Emby 还没刮削的文件：没有编号也没有季号集号。
  private static func unscannedEpisode(_ id: String) -> String {
    #"{"Id":"\#(id)","Type":"Episode","Name":"新入库","SeriesName":"长风渡"}"#
  }

  func testEpisodeFileWithoutTMDBIDIsSkippedAndExplainedWhenNothingFollows() async throws {
    // 组内第 11 集的文件刚入库，Emby 还没刮削（没有编号、季号集号，也没有整理记录）：照常往后找，接着播第 12 集；
    // 第 12 集之后再也接不上时，提示有认不出是哪一集的文件，可以刷新元数据。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
        Self.unscannedEpisode("e-new"),
        Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557))
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(
      next, .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(2)))
    let last = try XCTUnwrap(coordinator.session)
    let afterLast = try await coordinator.adjacentEpisode(.next, from: last.playback)
    XCTAssertEqual(afterLast, .stop(EpisodeAvailability.unmatchedMessage(server: "emby", noun: "下一集")))
    XCTAssertEqual(
      EpisodeAvailability.unmatchedMessage(server: "emby", noun: "下一集"),
      "没有找到下一集，但媒体服务器“emby”上有文件认不出是哪一集（没有 TMDB 编号，季号集号缺失或认不出，"
        + "也对不上 MoviePilot 的整理记录），下一集可能就在其中。可以在媒体服务器上刷新元数据后重试")
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(1)))
    XCTAssertEqual(coordinator.failure?.message, EpisodeAvailability.unmatchedMessage(server: "emby"))
  }

  func testNextKeepsTheOtherServerNameWhenSomeFilesLackEpisodeIDs() async throws {
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(
        Self.embyEpisode("f1", season: 1, episode: 10, tmdb: 555),
        Self.unscannedEpisode("f2"))
    }
    let coordinator = makeCoordinator(makeService())
    let owned = context(libraryServer: "emby")
    await run(coordinator, .episode(try queued(0, owned)))
    let first = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: first.playback)
    XCTAssertEqual(
      next, .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(2, owned)))
    let last = try XCTUnwrap(coordinator.session)
    let afterLast = try await coordinator.adjacentEpisode(.next, from: last.playback)
    XCTAssertEqual(afterLast, .stop(EpisodeAvailability.unmatchedMessage(server: "emby2", noun: "下一集")))
    coordinator.endCurrentSession()
  }

  func testServerErrorWhileSearchingAnotherServerIsNotTreatedAsMissing() async throws {
    // 另一台服务器按外部编号搜索时报 500：不能当作它没有这部剧，把下一集当作哪里都没有而跳过。
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.searchStatus[second] = 500
    }
    let coordinator = makeCoordinator(makeService())
    let owned = context(libraryServer: "emby")
    await run(coordinator, .episode(try queued(0, owned)))
    let session = try XCTUnwrap(coordinator.session)

    let failure = "媒体服务器“emby2”按外部编号查找失败：服务器出错（HTTP 500），请稍后重试"
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(next, .stop("无法确认下一集：\(failure)"))
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(1)], context: owned)
    XCTAssertEqual(availability, [.failed(failure)])
    coordinator.endCurrentSession()
  }

  func testOneLibraryCopyFailingToLoadDoesNotHideTheOtherCopy() async throws {
    // 同一部剧在两个媒体库各有一份，第一份的集读取失败：照样用第二份播；第二份里没有的集不能说服务器上没有。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(id: "broken"), Self.series()].joined(separator: ",")
      $0.episodesStatus["\(Self.lan)|broken"] = 500
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-s2e3")
    coordinator.endCurrentSession()

    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(1)], context: context())
    XCTAssertEqual(availability, [.failed("媒体服务器“emby”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试")])
  }

  func testRescrapedItemThatIsNowAnotherEpisodeIsNotPlayed() async throws {
    // 集索引是刚才读的：e-s2e3 是 TMDB 555。之后 Emby 重新刮削，e-s2e3 成了 999，555 是新条目 e-new。
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e-s2e3"] = Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 999)
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 999),
        Self.embyEpisode("e-new", season: 2, episode: 3, tmdb: 555))
      $0.items["\(Self.lan)|e-new"] = Self.embyEpisode("e-new", season: 2, episode: 3, tmdb: 555)
    }
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-new", "重新读到的已经是另一集：重读集索引，播现在的那一条")
    coordinator.endCurrentSession()
  }

  func testSwitchingToARescrapedItemPlaysTheCurrentCopy() async throws {
    // 队列给的第 12 集是 e-s2e5，换集前 Emby 重新刮削，它成了 999，557 换成了 e-557。
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e-s2e5"] = Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 999)
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
        Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: 999),
        Self.embyEpisode("e-557", season: 2, episode: 6, tmdb: 557))
      $0.items["\(Self.lan)|e-557"] = Self.embyEpisode("e-557", season: 2, episode: 6, tmdb: 557)
    }
    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e-s2e5", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应换到第 12 集现在的条目，实际 \(String(describing: result))") }
    XCTAssertEqual(session.item.id, "e-557")
    coordinator.endCurrentSession()
  }

  func testEpisodeWithoutAnIDOnTheFreshItemUsesTheConfirmedCopy() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    PlaybackURLProtocol.stub.configure {
      let unidentified = Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: nil)
      let confirmed = Self.embyEpisode("e-new", season: 2, episode: 3, tmdb: 555)
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(unidentified, confirmed)
      $0.items["\(Self.lan)|e-s2e3"] = unidentified
      $0.items["\(Self.lan)|e-new"] = confirmed
    }

    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-new")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path == "/Items/e-s2e3/PlaybackInfo" })
    coordinator.endCurrentSession()
  }

  func testSwitchingEpisodeExplainsWhenTheFreshItemLacksAnIDAndHasNoConfirmedCopy() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    // 集列表仍把条目列为 TMDB 557，单条详情已读不到这个编号。
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e-s2e5"] = Self.embyEpisode("e-s2e5", season: 2, episode: 5, tmdb: nil)
    }

    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e-s2e5", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .failed(let reason) = result else { return XCTFail("无法确认时应报告切集失败") }
    let message = "无法确认这一集：媒体服务器“emby”重新读取的剧集条目缺少 TMDB 编号，可刷新元数据后重试"
    XCTAssertEqual(reason, message)
    XCTAssertEqual(session.item.id, "e-s2e3")
    XCTAssertEqual(PlaybackURLProtocol.stub.requests().filter { $0.url.path == "/Shows/s1/Episodes" }.count, 2)
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(2)))
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, message)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path == "/Items/e-s2e5/PlaybackInfo" })
  }

  func testEpisodeCachedOnAnotherServerStartsWithoutRereadingTheOwner() async throws {
    // 所属服务器 emby 上有这部剧、没有组内第 11 集，emby2 上有。详情页刚读过两台：起播直接用 emby2，不先把 emby 上的整部剧重读一遍。
    configureDefaultOrderLibrary()
    let second = "lan2.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.embyEpisode("f2", season: 1, episode: 11, tmdb: 556))
      $0.items["\(second)|f2"] = Self.embyEpisode("f2", season: 1, episode: 11, tmdb: 556)
    }
    let coordinator = makeCoordinator(makeService())
    let owned = context(libraryServer: "emby")
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(1)], context: owned)
    XCTAssertEqual(availability, [.playable(server: "emby2")])
    let ownerReads = {
      PlaybackURLProtocol.stub.requests().filter { $0.url.host == Self.lan && $0.url.path.hasSuffix("/Episodes") }.count
    }
    let before = ownerReads()

    await run(coordinator, .episode(try queued(1, owned)))
    XCTAssertEqual(coordinator.session?.item.id, "f2")
    XCTAssertEqual(ownerReads(), before)
    coordinator.endCurrentSession()
  }

  func testLibraryItemIDOwnedByAnotherServerIsNotLookedUpByIDElsewhere() async throws {
    // 入库缓存说条目 7 属于已经停用的 a，只启用了 b。b 上的 7 是另一部没刮削编号的电影：不能按 ID 播它。
    let a = #"{"name":"a","type":"emby","enabled":false,"config":{"host":"lan.playback-tests.local","apikey":"k"}}"#
    let b = Self.embyServer(name: "b", host: "wan.playback-tests.local")
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(a),\(b)]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["wan.playback-tests.local|7": Self.movie(id: "7", tmdb: nil)]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    let target = await coordinator.locateLibraryItem(
      "7", expected: expectation(tmdb: "222"), in: try servers(a, b), preferredServer: "a")
    XCTAssertNil(target, "b 上按外部编号找不到，就不显示播放")

    await run(coordinator, .libraryItem(itemID: "7", expected: expectation(tmdb: "222"), owner: "a"))
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, PlaybackError.notFound.errorDescription)
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/Items/7") }, "不在 b 上拿 a 的 ID 找")
  }

  // MARK: 错误分类

  func testSeasonListThatComesBackEmptyFallsBackToTheOneReadEarlier() async throws {
    configureDefaultOrderLibrary()
    let service = makeService()
    let coordinator = makeCoordinator(service)
    await run(coordinator, .episode(try queued(2)))
    let session = try XCTUnwrap(coordinator.session)
    let first = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(first, .missing, "第 2 季第 1 集还不在服务器上")

    // 之后 MoviePilot 读 TMDB 失败，第 2 季返回了空列表：用之前读到的那份，不停下。
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = "[]" }
    _ = try await service.fetchTmdbEpisodes(tmdbID: 100, season: 2, episodeGroup: "g1", forceRefresh: true)
    let later = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(later, .missing)
    coordinator.endCurrentSession()

    // 从没读到过第 2 季：停下请用户重试，不说成“下一集还不在”。
    let fresh = makeCoordinator(makeService())
    await run(fresh, .episode(try queued(2)))
    let freshSession = try XCTUnwrap(fresh.session)
    let unavailable = try await fresh.adjacentEpisode(.next, from: freshSession.playback)
    XCTAssertEqual(unavailable, .stop("第 2 季集列表暂不可用，请重试"))
    fresh.endCurrentSession()
  }

  func testRejectedKeyIsExplainedAndAKeyChangedInMoviePilotIsPickedUp() async throws {
    configureDefaultOrderLibrary()
    let service = makeService()
    let coordinator = makeCoordinator(service)
    _ = try await service.fetchCachedMediaServers()

    // MoviePilot 里的密钥没变，Emby 拒绝它：说明是密钥的问题。
    PlaybackURLProtocol.stub.configure { $0.rejectedKeys = ["emby-key"] }
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(
      coordinator.failure?.message,
      "媒体服务器“emby”读取用户失败：不接受 MoviePilot 中配置的 API Key，请检查媒体服务器设置里的密钥")

    // 密钥刚在 MoviePilot 里改过、TV 端缓存的还是旧的：重读一次配置，用新密钥接着读。
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan, key: "new-key"))]"
    }
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])
  }

  func testServerErrorOnOneCopyTriesTheOtherCopy() async throws {
    // 同一集在两个媒体库各有一份，第一份读条目时服务器出错：先试第二份；两份都出错时说明哪台、哪一步，请稍后重试。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(id: "a"), Self.series(id: "b")].joined(separator: ",")
      $0.episodes = [
        "\(Self.lan)|a": Self.embyEpisodes(Self.embyEpisode("x-a", season: 2, episode: 3, tmdb: 555)),
        "\(Self.lan)|b": Self.embyEpisodes(Self.embyEpisode("x-b", season: 2, episode: 3, tmdb: 555)),
      ]
      $0.items = [
        "\(Self.lan)|x-a": Self.embyEpisode("x-a", season: 2, episode: 3, tmdb: 555),
        "\(Self.lan)|x-b": Self.embyEpisode("x-b", season: 2, episode: 3, tmdb: 555),
      ]
      $0.itemStatus["\(Self.lan)|x-a"] = 500
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "x-b")
    coordinator.endCurrentSession()

    PlaybackURLProtocol.stub.configure { $0.itemStatus["\(Self.lan)|x-b"] = 500 }
    await run(coordinator, .episode(try queued(0)))
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, "媒体服务器“emby”读取条目失败：服务器出错（HTTP 500），请稍后重试")
  }

  func testBadRequestForAnItemIsNotTreatedAsMissing() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.itemStatus["\(Self.lan)|m1"] = 400
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(coordinator.failure?.message, "媒体服务器“emby”读取条目失败：服务器不接受这个请求（HTTP 400）")
  }

  func testEpisodeListWithoutItemsIsAnUnrecognizedResponse() async throws {
    // 剧集列表回包里没有 Items：不当作这部剧没有集。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure { $0.episodes["\(Self.lan)|s1"] = "{}" }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    XCTAssertEqual(
      coordinator.failure?.message, "媒体服务器“emby”读取剧集列表失败：返回的不是媒体服务器的数据，请检查地址或反向代理设置")
  }

  func testCertificateProblemAndLoginPageAreExplainedInsteadOfUnreachable() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "https://\(Self.lan)"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.certificateErrorHosts = [Self.lan]
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(
      coordinator.failure?.message, "媒体服务器“emby”连接失败：https 证书不受信任或加密连接失败，请换受信任的证书或改用内网地址")

    PlaybackURLProtocol.stub.configure {
      $0.certificateErrorHosts = []
      $0.htmlHosts = [Self.lan]
    }
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(
      coordinator.failure?.message, "媒体服务器“emby”连接失败：返回的不是媒体服务器的数据，请检查地址或反向代理设置")
  }

  func testCertificateFailureTriesOnlyTheNewlyConfiguredAddress() async throws {
    let oldHost = "old.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "https://\(oldHost)"))]"
      $0.certificateErrorHosts = [oldHost]
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items["\(Self.lan)|m1"] = Self.movie()
      $0.playbackInfo = Self.playbackInfo()
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    _ = try await service.fetchCachedMediaServers()
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "https://\(oldHost)", playHost: "https://\(Self.lan)"))]"
    }

    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, Self.lan)
    XCTAssertEqual(mediaServerFetchCount(), 2)
    XCTAssertEqual(PlaybackURLProtocol.stub.requests().filter { $0.url.host == oldHost }.count, 1)
    coordinator.endCurrentSession()
  }

  func testCertificateFailureDoesNotRetryTheSameEndpointAfterSettingsChange() async throws {
    let oldHost = "old.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "https://\(oldHost)"))]"
      $0.certificateErrorHosts = [oldHost]
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    _ = try await service.fetchCachedMediaServers()
    PlaybackURLProtocol.stub.configure {
      let sameEndpoint = Self.embyServer(name: "emby", host: "https://\(oldHost):443/emby", key: "new-key")
      $0.mediaServers = "[\(sameEndpoint),\(Self.embyServer(name: "other", host: Self.lan))]"
    }

    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(
      coordinator.failure?.message, "媒体服务器“emby”连接失败：https 证书不受信任或加密连接失败，请换受信任的证书或改用内网地址")
    XCTAssertEqual(mediaServerFetchCount(), 2)
    XCTAssertEqual(PlaybackURLProtocol.stub.requests().filter { $0.url.host == oldHost }.count, 1)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.host == Self.lan })
  }

  func testEpisodeStartRecoversWithTheChangedAddressAfterMixedFailures() async throws {
    configureDefaultOrderLibrary()
    let oldHost = "old.playback-tests.local"
    let newHost = "new.playback-tests.local"
    let first = Self.embyServer(name: "emby", host: Self.lan)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(first),\(Self.embyServer(name: "emby2", host: "https://\(oldHost)"))]"
      $0.certificateErrorHosts = [oldHost]
      $0.searchStatus[Self.lan] = 500
    }
    let service = makeService()
    let coordinator = makeCoordinator(service)
    _ = try await service.fetchCachedMediaServers()
    PlaybackURLProtocol.stub.configure {
      let updatedFirst = Self.embyServer(name: "emby", host: "updated.playback-tests.local")
      $0.mediaServers = "[\(updatedFirst),\(Self.embyServer(name: "emby2", host: newHost))]"
      $0.providerSearch["\(newHost)|tmdb.100"] = Self.series(id: "t1")
      let episode = Self.embyEpisode("f1", season: 1, episode: 10, tmdb: 555)
      $0.episodes["\(newHost)|t1"] = Self.embyEpisodes(episode)
      $0.items["\(newHost)|f1"] = episode
    }

    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby"))))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "f1")
    XCTAssertEqual(streamURL(coordinator)?.host, newHost)
    XCTAssertEqual(mediaServerFetchCount(), 2)
    XCTAssertEqual(PlaybackURLProtocol.stub.requests().filter { $0.url.host == oldHost }.count, 1)
    coordinator.endCurrentSession()
  }

  func testItemFoundByExternalIDIsKeptWhenTheOldLibraryIDFails() async throws {
    // 按外部编号已经在 a 上找到了 731；MoviePilot 缓存的旧 ID 42 读取会报 500，不能因此丢掉 731。
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: Self.lan)),\(Self.plexServer)]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(Self.lan)|tmdb.222": Self.movie(id: "731", tmdb: "222")]
      $0.items = ["\(Self.lan)|731": Self.movie(id: "731", tmdb: "222")]
      $0.itemStatus = ["\(Self.lan)|42": 500]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .libraryItem(itemID: "42", expected: expectation(tmdb: "222"), owner: "a"))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "731")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/Items/42") }, "已经找到就不再按旧 ID 查")
    coordinator.endCurrentSession()

    // 读一部剧的集时，按旧 ID 补查失败只记下，按外部编号找到的那一份照常用。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure { $0.itemStatus = ["\(Self.lan)|old-s": 500] }
    let episodes = makeCoordinator(makeService())
    await run(episodes, .episode(try queued(0, context(libraryServer: "emby", libraryItemID: "old-s"))))
    XCTAssertNil(episodes.failure)
    XCTAssertEqual(episodes.session?.item.id, "e-s2e3")
    XCTAssertTrue(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/Items/old-s") }, "所属服务器上照常按旧 ID 补查")
    episodes.endCurrentSession()
  }

  func testSwitchExplainsAnIncompleteIndexInsteadOfSayingTheEpisodeIsGone() async throws {
    // 队列给的第 12 集条目删了，重读集索引时一个媒体库报 500、另一个里没有第 12 集：说明是哪一步失败，不说“已经找不到”。
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e-s2e5"] = nil
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(), Self.series(id: "b")].joined(separator: ",")
      $0.episodesStatus["\(Self.lan)|s1"] = 500
      $0.episodes["\(Self.lan)|b"] = Self.embyEpisodes(Self.embyEpisode("x-b", season: 2, episode: 3, tmdb: 555))
    }
    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e-s2e5", episode: try queued(2), in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .failed(let message) = result else { return XCTFail("应换集失败，实际 \(String(describing: result))") }
    XCTAssertEqual(message, "媒体服务器“emby”读取剧集列表失败：服务器出错（HTTP 500），请稍后重试")
    coordinator.endCurrentSession()
  }

  func testRefreshedSeasonIsUsedWhenRereadingTheServerFails() async throws {
    // 播完时重读 Emby 报错，MoviePilot 的季列表却读到了新顺序（第 12 集排到了第 11 集前面）：按新列表找下一集，
    // 不因为另一项失败退回旧列表。（本用例固定两项的结果，不复现两项先后完成的时序。）
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0)))
    let session = try XCTUnwrap(coordinator.session)
    let reordered =
      #"[{"id":555,"season_number":2,"episode_number":10,"name":"重逢"},{"id":557,"season_number":2,"episode_number":11,"name":"归来"},{"id":556,"season_number":2,"episode_number":12,"name":"离别"}]"#
    PlaybackURLProtocol.stub.configure {
      $0.episodesStatus["\(Self.lan)|s1"] = 500
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = reordered
    }
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback, refresh: true)
    let list = MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(reordered.utf8)), season: 1)
    XCTAssertEqual(
      next,
      .play(
        EpisodeQueueEntry(
          episode: list[1], item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557), seasonEpisodes: list),
        skippedMissing: false))
    coordinator.endCurrentSession()
  }

  func testItemOwnedByTheNamedServerIsAcceptedWithoutExternalIDs() async throws {
    // 启用了两台服务器（另一台是不能在应用内播放的 Plex），Emby 上的剧没刮到外部编号，按编号也搜不到。
    // 入库查询已说明这个 ID 属于 emby，按 ID 兜底时不再要求编号对上。
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),{\"name\":\"plex\",\"type\":\"plex\",\"enabled\":true}]"
      $0.providerSearch = [:]
      $0.items["\(Self.lan)|s1"] = #"{"Id":"s1","Type":"Series","Name":"长风渡"}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby"))))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-s2e3")
    coordinator.endCurrentSession()
  }

  func testDetailPageFollowsTheInAppPlaybackSwitch() async throws {
    // 详情页留在别的标签页里时，在设置里关掉或打开应用内播放，播放入口要跟着变。
    let key = PlaybackPreferences.inAppPlaybackKey
    let saved = UserDefaults.standard.object(forKey: key)
    defer {
      if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    UserDefaults.standard.set(true, forKey: key)
    configureDefaultOrderLibrary()
    PlaybackURLProtocol.stub.configure {
      $0.mediaServerExists = #"{"success":true,"data":{"item":{"id":"s1","server":"emby"}}}"#
    }
    let service = makeService()
    services.append(service)
    let detail = MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧")
    let viewModel = MediaDetailViewModel(detail: detail, apiService: service)
    viewModel.applyFullDetail(detail)
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    XCTAssertEqual(viewModel.episodePlayback, EpisodePlaybackSource(libraryItem: MediaServerItemRef(itemID: "s1", server: "emby")))

    PlaybackPreferences.setInAppPlaybackEnabled(false)
    try await waitUntil { viewModel.inAppPlaybackTarget == nil }
    XCTAssertNil(viewModel.episodePlayback)

    PlaybackPreferences.setInAppPlaybackEnabled(true)
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    XCTAssertNotNil(viewModel.episodePlayback, "重新打开后补回入口")
    viewModel.cancelForPop()
  }

  /// 详情页读真实的本机开关：测试期间设为开，结束后还原。
  private func enableInAppPlaybackPreferenceForTest() {
    let key = PlaybackPreferences.inAppPlaybackKey
    let saved = UserDefaults.standard.object(forKey: key) as? Bool
    addTeardownBlock {
      if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    UserDefaults.standard.set(true, forKey: key)
  }

  private func makeSeriesDetailViewModel(_ service: APIService) -> MediaDetailViewModel {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServerExists = #"{"success":true,"data":{"item":{"id":"s1","server":"emby"}}}"#
    }
    services.append(service)
    let detail = MediaInfo(tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧")
    let viewModel = MediaDetailViewModel(detail: detail, apiService: service)
    viewModel.applyFullDetail(detail)
    return viewModel
  }

  func testDetailPageOpenedBeforeSettingsArriveAddsPlaybackLater() async throws {
    // 从 Top Shelf 冷启动直接进详情页时，后端设置还没读到：先不显示播放，读到支持的版本后补回。
    enableInAppPlaybackPreferenceForTest()
    configureDefaultOrderLibrary()
    backendVersion = nil
    let service = makeService()
    let viewModel = makeSeriesDetailViewModel(service)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(viewModel.inAppPlaybackTarget)

    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    XCTAssertNotNil(viewModel.episodePlayback)
    viewModel.cancelForPop()
  }

  func testPoppedDetailPageNoLongerFollowsPlaybackSettings() async throws {
    enableInAppPlaybackPreferenceForTest()
    configureDefaultOrderLibrary()
    let viewModel = makeSeriesDetailViewModel(makeService())
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }

    viewModel.cancelForPop()
    let requestCount = PlaybackURLProtocol.stub.requests().count
    PlaybackPreferences.setInAppPlaybackEnabled(false)
    PlaybackPreferences.setInAppPlaybackEnabled(true)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(PlaybackURLProtocol.stub.requests().count, requestCount, "出栈后不再查入库状态、不连媒体服务器")
  }

  /// 最多等 2 秒。
  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "等待超时")
  }

  func testOtherEntriesHaveNoEpisodeQueue() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "e-s2e5"))
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertNil(session.episode)
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(next, .end)
    XCTAssertEqual(session.titles.primary, "第 2 季 第 5 集 · Emby 集名", "没有集列表时按服务器的编号和集名")
    coordinator.endCurrentSession()
  }
}

// MARK: - 播放界面的条目信息（MoviePilot 为准，认不出时用媒体服务器的）

extension PlaybackCoordinatorTests {
  private static let mpMovieDetail =
    #"{"tmdb_id":222,"source":"themoviedb","type":"电影","title":"MP 片名","overview":"MP 简介","release_date":"2024-03-01","vote_average":8.1,"poster_path":"https://image.tmdb.org/t/p/original/mp-poster.jpg","backdrop_path":"https://image.tmdb.org/t/p/original/mp-backdrop.jpg"}"#

  private static func embyMovie(tmdb: String?) -> String {
    let ids = tmdb.map { #","ProviderIds":{"Tmdb":"\#($0)"}"# } ?? ""
    return #"{"Id":"m1","Type":"Movie","Name":"Emby 片名","Overview":"Emby 简介","CommunityRating":6.5,"OfficialRating":"PG-13","PremiereDate":"2023-01-01T00:00:00.0000000Z","RunTimeTicks":\#(twoHours),"ImageTags":{"Primary":"p1"},"BackdropImageTags":["b1"]\#(ids)}"#
  }

  private func configureRecentMovie(tmdb: String?) {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.embyMovie(tmdb: tmdb)]
      $0.playbackInfo = Self.playbackInfo()
    }
  }

  private func moviePilotDetailRequests() -> [URL] {
    PlaybackURLProtocol.stub.requests().map(\.url).filter {
      $0.host == "mp.playback-tests.local" && $0.path.hasPrefix("/api/v1/media/")
    }
  }

  func testRecentlyAddedMovieShowsMoviePilotDetail() async throws {
    configureRecentMovie(tmdb: "222")
    PlaybackURLProtocol.stub.configure { $0.mediaDetails = ["/api/v1/media/222": Self.mpMovieDetail] }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    let session = try XCTUnwrap(coordinator.session)
    let shown = BaseItemDto.playback(session.playback)
    XCTAssertEqual(shown.name, "MP 片名")
    XCTAssertEqual(session.playback.title, "MP 片名", "续播询问和播放界面同一个标题")
    XCTAssertEqual(shown.overview, "MP 简介")
    XCTAssertEqual(shown.premiereDateYear, "2024")
    XCTAssertEqual(shown.communityRating, 8.1)
    XCTAssertEqual(shown.officialRating, "PG-13", "MoviePilot 没有分级，用服务器的")
    XCTAssertEqual(shown.portraitImageURL?.lastPathComponent, "mp-poster.jpg")
    XCTAssertEqual(shown.landscapeImageURL?.lastPathComponent, "mp-backdrop.jpg")
    let query = try XCTUnwrap(moviePilotDetailRequests().first)
      .query.flatMap { URLComponents(string: "?\($0)")?.queryItems } ?? []
    XCTAssertTrue(query.contains(URLQueryItem(name: "media_source", value: "themoviedb")), "按服务器条目的 TMDB 编号查")
    XCTAssertTrue(query.contains(URLQueryItem(name: "type_name", value: "电影")))
    coordinator.endCurrentSession()
  }

  /// 手动下载的资源：服务器条目没有外部编号，或 MoviePilot 查不到。
  func testUnrecognizedMovieFallsBackToServerInfo() async throws {
    for tmdb in [nil, "999"] {
      PlaybackURLProtocol.stub.reset()
      configureRecentMovie(tmdb: tmdb)
      let coordinator = makeCoordinator(makeService())
      await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

      let session = try XCTUnwrap(coordinator.session, "查不到 MoviePilot 信息照常播放")
      let shown = BaseItemDto.playback(session.playback)
      let label = tmdb == nil ? "没有外部编号" : "MoviePilot 查不到"
      XCTAssertEqual(shown.name, "Emby 片名", label)
      XCTAssertEqual(shown.overview, "Emby 简介", label)
      XCTAssertEqual(shown.communityRating, 6.5, label)
      XCTAssertEqual(shown.premiereDateYear, "2023", label)
      XCTAssertEqual(shown.portraitImageURL?.path, "/Items/m1/Images/Primary", label)
      XCTAssertEqual(shown.landscapeImageURL?.path, "/Items/m1/Images/Backdrop", label)
      XCTAssertEqual(moviePilotDetailRequests().count, tmdb == nil ? 0 : 1, "没有编号时不去 MoviePilot 查")
      coordinator.endCurrentSession()
    }
  }

  func testSlowMoviePilotDoesNotHoldPlaybackBack() async throws {
    configureRecentMovie(tmdb: "222")
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.mediaDetails = ["/api/v1/media/222": Self.mpMovieDetail]
      $0.mediaDetailGate = gate
    }
    defer { gate.signal() }
    let coordinator = makeCoordinator(makeService())
    let started = ContinuousClock.now
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    let session = try XCTUnwrap(coordinator.session)
    XCTAssertLessThan(ContinuousClock.now - started, PlaybackMetadataLookup.timeout + .seconds(2), "最多等到超时")
    XCTAssertEqual(BaseItemDto.playback(session.playback).name, "Emby 片名", "MoviePilot 太慢时先用服务器的")
    coordinator.endCurrentSession()
  }

  func testDetailPagePlayUsesItsOwnDetailWithoutLookup() async throws {
    configureRecentMovie(tmdb: "222")
    let detail = MediaInfo(
      tmdb_id: 222, source: "themoviedb", title: "详情页片名", type: "电影", overview: "详情页简介", vote_average: 7.7)
    let coordinator = makeCoordinator(makeService())
    coordinator.play(.serverItem(serverName: "emby", itemID: "m1"), media: detail)
    await coordinator.resolveTaskForTesting?.value

    let shown = BaseItemDto.playback(try XCTUnwrap(coordinator.session).playback)
    XCTAssertEqual(shown.name, "详情页片名")
    XCTAssertEqual(shown.overview, "详情页简介")
    XCTAssertEqual(shown.communityRating, 7.7)
    XCTAssertEqual(shown.portraitImageURL?.path, "/Items/m1/Images/Primary", "详情页没有海报时用服务器的")
    XCTAssertTrue(moviePilotDetailRequests().isEmpty, "已有详情，不再查")
    coordinator.endCurrentSession()
  }

  /// 详情页起播、条目是按外部编号在服务器上搜到的（单台 Emby 的详情页通常走这条）：详情缺的简介和海报用搜索结果里 Emby 的。
  func testDetailPagePlayOfSearchedItemFillsGapsFromEmby() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = [
        "lan.playback-tests.local|tmdb.222":
          #"{"Id":"731","Type":"Movie","Name":"Emby 片名","Overview":"Emby 简介","ProviderIds":{"Tmdb":"222"},"ImageTags":{"Primary":"p1"}}"#
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let detail = MediaInfo(tmdb_id: 222, source: "themoviedb", title: "详情页片名", type: "电影")
    let coordinator = makeCoordinator(makeService())
    coordinator.play(.libraryItem(itemID: "m1", expected: expectation(tmdb: "222")), media: detail)
    await coordinator.resolveTaskForTesting?.value

    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.item.id, "731", "播的是搜到的条目")
    let shown = BaseItemDto.playback(session.playback)
    XCTAssertEqual(shown.name, "详情页片名")
    XCTAssertEqual(shown.overview, "Emby 简介", "详情页没有简介，用 Emby 的")
    XCTAssertEqual(shown.portraitImageURL?.path, "/Items/731/Images/Primary", "详情页没有海报，用 Emby 的")
    let search = try XCTUnwrap(PlaybackURLProtocol.stub.requests().first { $0.url.path.hasSuffix("/Items") })
    let fields = URLComponents(url: search.url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "Fields" }?.value?.split(separator: ",").map(String.init) ?? []
    XCTAssertTrue(fields.contains("Overview"), "搜索也要带上简介")
    coordinator.endCurrentSession()
  }

  private func configureRecentEpisode(premiere: String) {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "lan.playback-tests.local|e1":
          #"{"Id":"e1","Type":"Episode","Name":"Emby 集名","SeriesId":"s1","SeriesName":"Emby 剧名","ParentIndexNumber":1,"IndexNumber":2,"PremiereDate":"\#(premiere)","Overview":"Emby 集简介","ImageTags":{"Primary":"t1"},"SeriesPrimaryImageTag":"sp"}"#,
        "lan.playback-tests.local|s1": #"{"Id":"s1","Type":"Series","Name":"Emby 剧名","ProviderIds":{"Tmdb":"100"}}"#,
      ]
      $0.mediaDetails = [
        "/api/v1/media/100":
          #"{"tmdb_id":100,"source":"themoviedb","type":"电视剧","title":"MP 剧名","poster_path":"https://image.tmdb.org/t/p/original/mp-series.jpg"}"#
      ]
      $0.tmdbEpisodes = [
        "/api/v1/tmdb/100/1":
          #"[{"id":11,"episode_number":1,"name":"第一集","air_date":"2024-01-01"},{"id":12,"episode_number":2,"name":"MP 集名","overview":"MP 集简介","air_date":"2024-01-08","still_path":"/mp-still.jpg","vote_average":7.5}]"#
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
  }

  func testRecentlyAddedEpisodeUsesMoviePilotEpisodeList() async throws {
    configureRecentEpisode(premiere: "2024-01-08T00:00:00.0000000Z")
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "e1"))

    let session = try XCTUnwrap(coordinator.session)
    let shown = BaseItemDto.playback(session.playback)
    XCTAssertEqual(session.titles.primary, "第 1 季 第 2 集 · MP 集名")
    XCTAssertEqual(session.titles.secondary, "MP 剧名")
    XCTAssertEqual(shown.name, "MP 集名")
    XCTAssertEqual(shown.seriesName, "MP 剧名")
    XCTAssertEqual(shown.overview, "MP 集简介")
    XCTAssertEqual(shown.communityRating, 7.5)
    XCTAssertEqual(shown.landscapeImageURL?.lastPathComponent, "mp-still.jpg")
    XCTAssertEqual(shown.portraitImageURL?.lastPathComponent, "mp-series.jpg")
    coordinator.endCurrentSession()
  }

  func testEpisodeNotMatchingMoviePilotListKeepsServerEpisodeInfo() async throws {
    // 服务器按别的顺序编号：第 2 集的播出日期和 MoviePilot 的第 2 集对不上。
    configureRecentEpisode(premiere: "2019-06-01T00:00:00.0000000Z")
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "e1"))

    let shown = BaseItemDto.playback(try XCTUnwrap(coordinator.session).playback)
    XCTAssertEqual(shown.name, "Emby 集名", "认不准是哪一集时不借用别的集的集名")
    XCTAssertEqual(shown.overview, "Emby 集简介")
    XCTAssertEqual(shown.landscapeImageURL?.path, "/Items/e1/Images/Primary")
    XCTAssertEqual(shown.seriesName, "MP 剧名", "剧还是认得出的，剧名和海报照样用 MoviePilot 的")
    XCTAssertEqual(shown.portraitImageURL?.lastPathComponent, "mp-series.jpg")
    coordinator.endCurrentSession()
  }

  /// 条目记 2 小时、所选片源 3 小时：播放界面显示的片长、跳转上限读的片长和写回的看完判定都按 3 小时。
  /// 跳转本身要等 mpv 就绪才发，测试里 mpv 打不开测试地址，只能断言跳转上限读的那个值（`MediaSession.item.runtime`）。
  func testExtendedCutUsesSourceRuntimeForDisplaySeekAndWriteBack() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo =
        #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mkv","Protocol":"File","RunTimeTicks":108000000000,"MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    let session = try XCTUnwrap(coordinator.session)
    let screen = MediaSession(session: session, onExit: { _ in }, onSwitchItem: { _, _, _, _, completion in completion(.discarded) })

    XCTAssertEqual(screen.item.runtime, .seconds(10_800), "进度条、剩余时间和跳转上限都读这个值")
    XCTAssertFalse(session.watchProgress(at: 7000).completed, "按条目的 2 小时算会误判看完（7000/7200）")
    XCTAssertTrue(session.watchProgress(at: 9800).completed, "按 3 小时的 90%")

    // 信息面板和选集里的当前一集读播放界面建条目时的那份，片长在建条目时就按所选片源；
    // 起播后 mpv 读出的时长经 `runtime` 给出（测试里 mpv 打不开测试地址，读不到时长，取值顺序见 `PlaybackDuration` 的测试）。
    // mpv 的失败与这里无关，接住免得结束会话。
    session.onFailure = { _ in }
    let reporter = coordinator.reporterForTesting
    screen.start()
    let playing = try XCTUnwrap(screen.playbackItem)
    XCTAssertEqual(playing.baseItem.runtime, .seconds(10_800), "选集里的当前一集按这份显示")
    let info = try XCTUnwrap(
      VideoPlayerSupplementType.info.makeSupplement(for: playing, queue: nil) as? MediaInfoSupplement)
    XCTAssertEqual(info.item.runtime, .seconds(10_800), "按播放界面建面板的入口建出的信息面板")
    XCTAssertEqual(screen.runtime, .seconds(10_800), "面板的片长、结束时间和跳转上限读这个值")
    // 选集卡片来自按季取的集列表，条目上记的是 2 小时；正在播的那一集要显示所播文件的 3 小时。
    let listed = ItemEntry(item: BaseItemDto(item: session.item, metadata: session.item.metadata))
    XCTAssertEqual(listed.snapshot.runtime, .seconds(7200))
    XCTAssertEqual(screen.runTimeLabel(for: listed), BaseItemDto.runTimeLabel(seconds: 10_800), "选集里正在播的一集")
    let other = ItemEntry(item: BaseItemDto(item: ServerMediaItem(id: "m2", kind: .movie, runtimeSeconds: 5400), metadata: PlaybackMetadata()))
    XCTAssertEqual(screen.runTimeLabel(for: other), BaseItemDto.runTimeLabel(seconds: 5400), "其他集用自己的")
    screen.stop()
    coordinator.endCurrentSession()
    // 起播上报了开始、退出排进了停止和写回：发完再结束，免得请求落到后面的用例里。
    await reporter.waitForQueued()
  }

  /// 读播放信息先失败了：协调器取消还在查的 MoviePilot 信息。查询本身不响应取消时，也要立即返回，失败提示不被拖住。
  /// 直接调用 `withinTimeout`：测试替身的请求都会响应取消，从协调器入口造不出“查询不响应取消”。
  /// 协调器靠 `async let` 在读播放信息失败时隐式取消查询，这一步不在本用例覆盖范围内。
  func testCancelledMetadataLookupReturnsWithoutWaitingForTheQuery() async throws {
    let gate = QueryGate()
    let lookup = Task { @MainActor in
      await PlaybackMetadataLookup.withinTimeout(.seconds(5)) { () async -> Int? in
        await withCheckedContinuation { gate.continuation = $0 }
        return 1
      }
    }
    while gate.continuation == nil { await Task.yield() }
    let cancelled = ContinuousClock.now
    lookup.cancel()
    let value = await lookup.value
    XCTAssertNil(value)
    XCTAssertLessThan(ContinuousClock.now - cancelled, .seconds(1), "不等查询停下，也不等超时")
    gate.continuation?.resume()
  }
}

@MainActor
private final class QueryGate {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  var continuation: CheckedContinuation<Void, Never>?
}

private extension PlaybackSession {
  /// 模拟 mpv 发来属于当前这次载入的事件。
  func handleCurrent(_ change: MPVPlaybackEvent.Change) {
    handle(change, generation: makeMPVPlayer().generation)
  }
}

private extension PlaybackCoordinator {
  /// 测试收尾：结束当前会话（生产代码只按会话结束，见 `endSession(_:)`）。
  func endCurrentSession() {
    if let session { endSession(session) }
  }
}

// MARK: - 网络替身

private final class PlaybackStub: @unchecked Sendable {
  struct Recorded {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data
  }

  struct Scenario {
    var mediaServers = "[]"
    var unreachableHosts: Set<String> = []
    var transportSecurityHosts: Set<String> = []
    var users = "[]"
    /// `host|itemID` → 条目 JSON
    var items: [String: String] = [:]
    var playbackInfo = #"{"MediaSources":[]}"#
    /// `host|itemID` → 这个条目自己的 PlaybackInfo（没有时用 `playbackInfo`）
    var playbackInfoByItem: [String: String] = [:]
    /// `host|seriesID` → 剧集列表 JSON
    var episodes: [String: String] = [:]
    /// `host|tmdb.123` → 按外部编号搜索（`AnyProviderIdEquals`）能找到的条目 JSON
    var providerSearch: [String: String] = [:]
    /// host → 按外部编号搜索时回的 HTTP 错误码（模拟服务器报错）
    var searchStatus: [String: Int] = [:]
    /// `host|seriesID` → 读这部剧的集时回的 HTTP 错误码
    var episodesStatus: [String: Int] = [:]
    /// `host|itemID` → 读单个条目时回的 HTTP 错误码
    var itemStatus: [String: Int] = [:]
    /// 带这些密钥的 Emby 请求回 401（探测地址用的公开接口除外）
    var rejectedKeys: Set<String> = []
    /// 这些主机的 https 证书不受信任
    var certificateErrorHosts: Set<String> = []
    /// 这些主机回的是网页（比如反向代理的登录页）
    var htmlHosts: Set<String> = []
    /// MoviePilot 路径（如 `/api/v1/tmdb/100/1`，或带查询的 `/api/v1/tmdb/100/1?episode_group=g1`）→ 季集列表 JSON。
    /// 带查询的优先，没有时按路径。
    var tmdbEpisodes: [String: String] = [:]
    /// MoviePilot 整理记录（`/api/v1/history/transfer`）的 `list`，不论查什么都回它；nil 时回 404。
    var transferHistory: String?
    /// 按查询回整理记录：`title|page` → `data`（`{"list":[…],"total":…}`）。不为空时优先，没列出的查询回空的一页。
    var transferHistoryPages: [String: String] = [:]
    /// MoviePilot `/api/v1/media/seasons`（默认顺序的季列表）；nil 时回 404。
    var mediaSeasons: String?
    /// MoviePilot 媒体详情（`/api/v1/media/{id}`）：路径 → 详情 JSON；没列出的回 404。
    var mediaDetails: [String: String] = [:]
    /// 卡住 MoviePilot 媒体详情的查询
    var mediaDetailGate: DispatchSemaphore?
    /// MoviePilot `/mediaserver/exists` 的回包
    var mediaServerExists = #"{"success":true,"data":{"item":{}}}"#
    /// host → Emby `Library/SelectableMediaFolders` 的回包（没有时是空数组）
    var mediaFolders: [String: String] = [:]
    var usersGate: DispatchSemaphore?
    /// 卡住“开始播放”上报（模拟网络慢）
    var reportStartGate: DispatchSemaphore?
    /// 卡住“停止播放”上报
    var reportStoppedGate: DispatchSemaphore?
    var playbackInfoGate: DispatchSemaphore?
    /// 卡住 MoviePilot 整理记录的查询
    var transferHistoryGate: DispatchSemaphore?
    /// host → 卡住这台服务器读集列表
    var episodesGates: [String: DispatchSemaphore] = [:]
  }

  private let lock = NSLock()
  private var scenario = Scenario()
  private var recorded: [Recorded] = []

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    scenario = Scenario()
    recorded = []
  }

  func configure(_ change: (inout Scenario) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    change(&scenario)
  }

  func requests() -> [Recorded] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }


  func record(_ request: Recorded) -> Scenario {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(request)
    return scenario
  }
}

private final class PlaybackURLProtocol: URLProtocol {
  static let stub = PlaybackStub()

  static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PlaybackURLProtocol.self]
    return URLSession(configuration: configuration)
  }()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host?.hasSuffix("playback-tests.local") == true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let recorded = PlaybackStub.Recorded(
      method: request.httpMethod ?? "GET", url: url,
      headers: request.allHTTPHeaderFields ?? [:], body: Self.body(of: request))
    let scenario = Self.stub.record(recorded)

    if host == "mp.playback-tests.local" {
      if url.path == "/api/v1/system/setting/MediaServers" {
        respond(200, #"{"value":\#(scenario.mediaServers)}"#)
      } else if let episodes = url.query.flatMap({ scenario.tmdbEpisodes["\(url.path)?\($0)"] })
        ?? scenario.tmdbEpisodes[url.path]
      {
        respond(200, episodes)
      } else if url.path == "/api/v1/history/transfer", !scenario.transferHistoryPages.isEmpty {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let title = query.first { $0.name == "title" }?.value ?? ""
        let page = query.first { $0.name == "page" }?.value ?? ""
        let data = scenario.transferHistoryPages["\(title)|\(page)"] ?? #"{"list":[],"total":0}"#
        respond(200, #"{"success":true,"data":\#(data)}"#, after: scenario.transferHistoryGate)
      } else if url.path == "/api/v1/history/transfer", let list = scenario.transferHistory {
        respond(200, #"{"success":true,"data":{"list":\#(list),"total":null}}"#)
      } else if url.path == "/api/v1/media/seasons", let seasons = scenario.mediaSeasons {
        respond(200, seasons)
      } else if url.path == "/api/v1/mediaserver/exists" {
        respond(200, scenario.mediaServerExists)
      } else if let detail = scenario.mediaDetails[url.path] {
        respond(200, detail, after: scenario.mediaDetailGate)
      } else {
        respond(404, "{}")
      }
      return
    }
    if scenario.unreachableHosts.contains(host) {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    if scenario.transportSecurityHosts.contains(host) {
      client?.urlProtocol(self, didFailWithError: URLError(.appTransportSecurityRequiresSecureConnection))
      return
    }
    if scenario.certificateErrorHosts.contains(host) {
      client?.urlProtocol(self, didFailWithError: URLError(.serverCertificateUntrusted))
      return
    }
    if scenario.htmlHosts.contains(host) {
      respond(200, "<html><body>请先登录</body></html>")
      return
    }
    if !url.path.hasSuffix("/System/Info/Public"), let key = request.value(forHTTPHeaderField: "X-Emby-Token"),
      scenario.rejectedKeys.contains(key)
    {
      respond(401, "")
      return
    }

    let path = url.path
    if path.hasSuffix("/System/Info/Public") {
      respond(200, #"{"Id":"server","Version":"4.8.0.0"}"#)
    } else if path.hasSuffix("/Users") {
      Self.pass(scenario.usersGate)
      respond(200, scenario.users)
    } else if path.hasSuffix("/Episodes") {
      let seriesID = url.deletingLastPathComponent().lastPathComponent
      if let status = scenario.episodesStatus["\(host)|\(seriesID)"] {
        respond(status, "{}")
        return
      }
      respond(200, scenario.episodes["\(host)|\(seriesID)"] ?? #"{"Items":[]}"#, after: scenario.episodesGates[host])
    } else if path.hasSuffix("/PlaybackInfo") {
      Self.pass(scenario.playbackInfoGate)
      let itemID = url.deletingLastPathComponent().lastPathComponent
      respond(200, scenario.playbackInfoByItem["\(host)|\(itemID)"] ?? scenario.playbackInfo)
    } else if path.hasSuffix("/Sessions/Playing") {
      Self.pass(scenario.reportStartGate)
      respond(204, "")
    } else if path.hasSuffix("/Sessions/Playing/Stopped") {
      Self.pass(scenario.reportStoppedGate)
      respond(204, "")
    } else if path.hasSuffix("/Library/SelectableMediaFolders") {
      respond(200, scenario.mediaFolders[host] ?? "[]")
    } else if recorded.method == "GET", path.hasSuffix("/Items") {
      if let status = scenario.searchStatus[host] {
        respond(status, "{}")
        return
      }
      let keys = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "AnyProviderIdEquals" }?.value?.split(separator: ",") ?? []
      let found = keys.compactMap { scenario.providerSearch["\(host)|\($0)"] }
      respond(200, #"{"Items":[\#(found.joined(separator: ","))]}"#)
    } else if recorded.method == "GET", path.contains("/Items/") {
      let itemID = url.lastPathComponent
      if let status = scenario.itemStatus["\(host)|\(itemID)"] {
        respond(status, "{}")
      } else if let item = scenario.items["\(host)|\(itemID)"] {
        respond(200, item)
      } else {
        respond(404, "")
      }
    } else {
      respond(204, "")
    }
  }

  override func stopLoading() {}

  /// 等测试放行卡住的请求。所有请求共用替身的同一个线程，漏放行时最多卡 10 秒，只让这个测试自己失败。
  private static func pass(_ gate: DispatchSemaphore?) {
    _ = gate?.wait(timeout: .now() + 10)
  }

  /// 等 `gate` 放行再回包。在别的队列上等，不卡住其他请求（`pass` 会卡住加载线程上排在后面的请求）。
  private func respond(_ status: Int, _ body: String, after gate: DispatchSemaphore?) {
    guard let gate else { return respond(status, body) }
    DispatchQueue.global().async {
      _ = gate.wait(timeout: .now() + 10)
      self.respond(status, body)
    }
  }

  private func respond(_ status: Int, _ body: String) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
