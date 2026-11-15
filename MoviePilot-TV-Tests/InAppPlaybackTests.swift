import Combine
import CoreGraphics
import SwiftUI
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
    let versions = MediaSession.versions(of: info.mediaSources.map { $0.serverSource() })
    XCTAssertEqual(versions.map(\.id), ["a", "c"], "远程片源不能直连，不列出")
    XCTAssertEqual(versions.map(\.displayTitle), ["4K HDR", "1080p"])
  }

  func testPrimaryIdentityDecidesWhenTheServerMisidentifiedAnotherSource() throws {
    // Emby 把 TVDB 刮成了别的条目（TMDB、IMDb 都对）：MoviePilot 按 TMDB 判断已入库，这里也按主身份认。
    let media = MediaInfo(
      tmdb_id: 63926, imdb_id: "tt4508902", tvdb_id: 293088, source: "themoviedb", media_id: "63926", type: "电视剧")
    let expected = LibraryItemExpectation(media: media)
    XCTAssertEqual(expected.primarySource, "tmdb")
    let wrongTVDB = try embyItem(
      #"{"Id":"s1","Type":"Series","ProviderIds":{"Tmdb":"63926","Imdb":"tt4508902","Tvdb":"362966"}}"#)
    XCTAssertTrue(expected.accepts(wrongTVDB, strict: true))
    let wrongTMDB = try embyItem(
      #"{"Id":"s2","Type":"Series","ProviderIds":{"Tmdb":"1","Imdb":"tt4508902","Tvdb":"293088"}}"#)
    XCTAssertFalse(expected.accepts(wrongTMDB, strict: false), "主身份对不上，其他编号再对也不是")
    let noTMDB = try embyItem(#"{"Id":"s3","Type":"Series","ProviderIds":{"Imdb":"tt4508902","Tvdb":"362966"}}"#)
    XCTAssertFalse(expected.accepts(noTMDB, strict: false), "没带主身份时任一编号冲突都不算")
    let movie = try embyItem(#"{"Id":"m","Type":"Movie","ProviderIds":{"Tmdb":"63926"}}"#)
    XCTAssertFalse(expected.accepts(movie, strict: false), "类型不符")
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

  @MainActor
  func testEngineGeneratedTrackNamesAreNotUsedAsTitles() {
    // 片源没写标题时引擎自己拼名字，不能当成片源写的标题显示（否则界面会出现「CHI (subrip)」这种名字）。
    XCTAssertNil(PlayerTrack.title(fromEngineName: "CHI (subrip)", language: "chi", codec: "subrip"))
    XCTAssertNil(PlayerTrack.title(fromEngineName: "Track 3 (hdmv_pgs_subtitle)", language: nil, codec: "hdmv_pgs_subtitle"))
    XCTAssertNil(PlayerTrack.title(fromEngineName: "  ", language: nil, codec: "aac"))
    XCTAssertEqual(PlayerTrack.title(fromEngineName: "简体中文", language: "chi", codec: "ass"), "简体中文")
    XCTAssertEqual(
      PlayerTrack.title(fromEngineName: "Track 3 (Director)", language: nil, codec: "aac"), "Track 3 (Director)",
      "片源自己写的标题恰好以 Track 开头时照常显示")

    let untitled = PlayerTrack(id: 2, language: "chi", codec: "subrip", isForced: true)
    XCTAssertTrue(PlayerTrackLabel.text(for: untitled, index: 0).hasSuffix("SUBRIP · 强制"))
    let titled = PlayerTrack(id: 3, title: "国语 5.1", language: "chi", codec: "eac3", isExternal: true)
    XCTAssertEqual(PlayerTrackLabel.text(for: titled, index: 1), "国语 5.1 · 外挂", "写了标题就只用标题")
    XCTAssertEqual(PlayerTrackLabel.text(for: PlayerTrack(id: 4, codec: "aac"), index: 2), "轨道 3 · AAC")
  }

  @MainActor
  func testOnlySubtitlesCoveringThePictureTimeAreShownAndOffsetShiftsThem() {
    let presentation = SubtitlePresentation()
    func text(_ id: Int, _ value: String, alignment: Int? = nil) -> SubtitleSnapshot.TextCue {
      SubtitleSnapshot.TextCue(id: id, spans: [SubtitleSpan(text: value)], alignment: alignment, position: nil)
    }
    do {
      presentation.update(cues: [
        TimedSubtitle(start: 10, end: 12, content: .text(text(1, "第一句"))),
        TimedSubtitle(start: 11.5, end: 14, content: .text(text(2, "第二句", alignment: 8))),
      ])
      presentation.update(time: 9.9)
      XCTAssertNil(presentation.snapshot, "还没到第一句")
      presentation.update(time: 10)
      XCTAssertEqual(presentation.snapshot?.texts.map(\.id), [1])
      presentation.update(time: 11.6)
      XCTAssertEqual(presentation.snapshot?.texts.map(\.id), [1, 2], "重叠时两句都显示")
      XCTAssertEqual(presentation.snapshot?.text, "第一句\n第二句")
      presentation.update(time: 12)
      XCTAssertEqual(presentation.snapshot?.texts.map(\.id), [2], "结束时间不含在内")

      presentation.delay = 2
      XCTAssertEqual(presentation.snapshot?.texts.map(\.id), [1], "字幕偏移 +2 秒：12 秒时显示 10 秒那句")
      presentation.reset()
      XCTAssertNil(presentation.snapshot, "换条目时清空")
      presentation.update(time: 11)
      XCTAssertNil(presentation.snapshot, "清空后没有字幕可显示")
    }
  }

  func testBitmapSubtitleCanvasIsMappedOntoThePicture() {
    // 1920x1080 的 PGS 画布放到裁过黑边的 1920x800 画面上：按宽度对齐、上下居中，底部黑边里的字幕落到画面之外。
    let frame = SubtitlePresentation.pictureFrame(
      of: CGRect(x: 0.25, y: 0.9, width: 0.5, height: 0.05), canvas: CGSize(width: 1920, height: 1080),
      codedVideo: CGSize(width: 1920, height: 800))
    XCTAssertEqual(frame.minX, 0.25, accuracy: 0.0001)
    XCTAssertEqual(frame.width, 0.5, accuracy: 0.0001)
    XCTAssertEqual(frame.minY, (-140 + 0.9 * 1080) / 800, accuracy: 0.0001)
    XCTAssertEqual(frame.height, 0.05 * 1080 / 800, accuracy: 0.0001)

    let same = CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)
    XCTAssertEqual(
      SubtitlePresentation.pictureFrame(of: same, canvas: .zero, codedVideo: CGSize(width: 1920, height: 1080)), same,
      "画布未知时当作画布就是画面")
    XCTAssertEqual(
      SubtitlePresentation.pictureFrame(of: same, canvas: CGSize(width: 1920, height: 1080), codedVideo: .zero), same)
  }

  @MainActor
  func testSubtitleAlignmentFollowsASSNumpad() {
    XCTAssertEqual(SubtitleAnchor.alignment(nil), 2, "没给对齐时放在底部居中")
    XCTAssertEqual(SubtitleAnchor.alignment(0), 2)
    XCTAssertEqual(SubtitleAnchor.frameAlignment(8), .top)
    XCTAssertEqual(SubtitleAnchor.frameAlignment(1), .bottomLeading)
    XCTAssertEqual(SubtitleAnchor.frameAlignment(6), .trailing)
    XCTAssertEqual(SubtitleAnchor.textAlignment(7), .leading)
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
    // 起播后播放器读到的就是正在播的文件：服务器的片源记录过时（文件被洗版换成 3 小时的加长版，Emby 还记 2 小时）也不受影响。
    XCTAssertEqual(PlaybackDuration.seconds(player: 10_800, source: 7200, item: 7200), 10_800)
    // 起播前还没有实测值：条目记的是 2 小时的版本，选的是 3 小时的加长版，以所选片源为准。
    XCTAssertEqual(PlaybackDuration.seconds(player: nil, source: 10_800, item: 7200), 10_800)
    // 刚入库、Emby 还没分析出片源时长：退回条目的。
    XCTAssertEqual(PlaybackDuration.seconds(player: nil, source: nil, item: 7200), 7200)
    // 0、负数、非有限值都跳过（播放器还没读到时长时报 0）。
    XCTAssertEqual(PlaybackDuration.seconds(player: 0, source: .infinity, item: 7200), 7200)
    XCTAssertEqual(PlaybackDuration.seconds(player: .nan, source: -1, item: 0), nil)
    XCTAssertNil(PlaybackDuration.seconds(player: nil, source: nil, item: nil))
  }

  func testEmbySourceKeepsItsOwnRuntime() throws {
    let info = try decode(
      EmbyPlaybackInfo.self,
      #"{"MediaSources":[{"Id":"a","Container":"mkv","Protocol":"File","RunTimeTicks":108000000000,"MediaStreams":[]},{"Id":"b","Container":"mkv","Protocol":"File","MediaStreams":[]},{"Id":"c","Container":"mkv","Protocol":"File","RunTimeTicks":"bad","MediaStreams":[]}]}"#)
    let sources = info.mediaSources.map { $0.serverSource() }
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

  func testUpNextResumesACopyRewatchedAfterAnotherCopyWasFinished() throws {
    // 同一集在两个媒体库各有一份：一份看完了，另一份看到一半。看到一半那份播得更晚（重新在看）就接着播它；
    // 更早（旧续播点）或读不到时间时以看完为准，接着看下一集。被看完的合集包含的那一集也一样。
    func episode(
      _ id: String, episode: Int, end: Int? = nil, played: Bool = false, position: Int = 0, lastPlayed: String? = nil
    ) -> String {
      let ticks = Int64(position) * 10_000_000
      let end = end.map { #","IndexNumberEnd":\#($0)"# } ?? ""
      let date = lastPlayed.map { #","LastPlayedDate":"\#($0)""# } ?? ""
      return #"{"Id":"\#(id)","Type":"Episode","ParentIndexNumber":1,"IndexNumber":\#(episode)\#(end),"RunTimeTicks":72000000000,"UserData":{"Played":\#(played),"PlaybackPositionTicks":\#(ticks)\#(date)}}"#
    }
    func upNext(_ episodes: [String]) throws -> (String, Bool)? {
      let items = try decode(EmbyItemsPage.self, #"{"Items":[\#(episodes.joined(separator: ","))]}"#).items
        .map { $0.serverItem(defaultKind: .episode) }
      return PlaybackEpisodeProgress.upNext(in: items).map { ($0.episode.id, $0.resumes) }
    }
    let first = episode("e1", episode: 1, played: true, lastPlayed: "2026-01-01T10:00:00.0000000Z")
    let finished = episode("e2a", episode: 2, played: true, lastPlayed: "2026-01-02T10:00:00.0000000Z")
    let next = episode("e3", episode: 3)
    let rewatching = episode("e2b", episode: 2, position: 1800, lastPlayed: "2026-02-01T21:30:00.1234567Z")
    XCTAssertEqual(try upNext([first, finished, rewatching, next])?.0, "e2b", "重新在看的那份")
    XCTAssertEqual(try upNext([first, finished, rewatching, next])?.1, true)
    let stale = episode("e2b", episode: 2, position: 1800, lastPlayed: "2025-12-31T10:00:00Z")
    XCTAssertEqual(try upNext([first, finished, stale, next])?.0, "e3", "旧续播点不盖掉看完")
    let undated = episode("e2b", episode: 2, position: 1800)
    XCTAssertEqual(try upNext([first, finished, undated, next])?.0, "e3", "读不到时间时以看完为准")
    // 看完了 E01–E02 的合集，之后又单独看了一半 E02。
    let pack = episode("pack", episode: 1, end: 2, played: true, lastPlayed: "2026-01-02T10:00:00Z")
    XCTAssertEqual(try upNext([pack, rewatching, next])?.0, "e2b")
    XCTAssertEqual(try upNext([pack, stale, next])?.0, "e3")
  }

  func testEmbyLastPlayedDateIsRead() throws {
    XCTAssertEqual(
      EmbyDate.parse("2026-02-01T21:30:00.1234567Z")?.timeIntervalSince1970 ?? 0,
      ISO8601DateFormatter().date(from: "2026-02-01T21:30:00Z")!.timeIntervalSince1970 + 0.1234567, accuracy: 0.0001)
    XCTAssertEqual(EmbyDate.parse("2026-02-01T21:30:00Z"), ISO8601DateFormatter().date(from: "2026-02-01T21:30:00Z"))
    XCTAssertEqual(EmbyDate.parse("2026-02-01T21:30:00"), ISO8601DateFormatter().date(from: "2026-02-01T21:30:00Z"))
    XCTAssertNil(EmbyDate.parse("昨天"))
  }

  func testUpNextContinuesTheFurthestWatchedEpisode() throws {
    // 每集 2 小时（72000000000 tick）；`position` 是续播点（秒）。
    func episode(
      _ id: String, season: Int, episode: Int, played: Bool = false, position: Int = 0, location: String = "FileSystem"
    ) -> String {
      let ticks = Int64(position) * 10_000_000
      return #"{"Id":"\#(id)","Type":"Episode","ParentIndexNumber":\#(season),"IndexNumber":\#(episode),"RunTimeTicks":72000000000,"LocationType":"\#(location)","UserData":{"Played":\#(played),"PlaybackPositionTicks":\#(ticks)}}"#
    }
    func items(_ episodes: [String]) throws -> [ServerMediaItem] {
      try decode(EmbyItemsPage.self, #"{"Items":[\#(episodes.joined(separator: ","))]}"#).items
        .map { $0.serverItem(defaultKind: .episode) }
    }
    func upNext(_ episodes: [String]) throws -> (String, Bool)? {
      PlaybackEpisodeProgress.upNext(in: try items(episodes)).map { ($0.episode.id, $0.resumes) }
    }

    let watchedTwo = [
      episode("s1e1", season: 1, episode: 1, played: true),
      episode("s1e2", season: 1, episode: 2, played: true),
      episode("s1e3", season: 1, episode: 3),
    ]
    XCTAssertTrue(try items(watchedTwo)[0].played, "读出 Emby 的已看完标记")
    XCTAssertEqual(try upNext(watchedTwo)?.0, "s1e3", "看完第 2 集，接着看第 3 集")
    XCTAssertEqual(try upNext(watchedTwo)?.1, false)

    let halfway = [episode("s1e1", season: 1, episode: 1, played: true), episode("s1e2", season: 1, episode: 2, position: 1800)]
    XCTAssertEqual(try upNext(halfway)?.0, "s1e2", "看到一半的接着看")
    XCTAssertEqual(try upNext(halfway)?.1, true)

    // 前面有一集看了一半，后面又看完了更靠后的：以最靠后的为准。
    XCTAssertEqual(
      try upNext([
        episode("s1e1", season: 1, episode: 1, position: 1800),
        episode("s2e1", season: 2, episode: 1, played: true),
        episode("s2e2", season: 2, episode: 2),
      ])?.0, "s2e2")
    // 实际遇到的：整季看完后又回头看了第 1、2 集几分钟——仍按看到的最后一集算，不回到前面。
    XCTAssertEqual(
      try upNext([
        episode("e1", season: 1, episode: 1, played: true, position: 698),
        episode("e2", season: 1, episode: 2, played: true, position: 306),
        episode("e3", season: 1, episode: 3, played: true),
        episode("e4", season: 1, episode: 4),
      ])?.0, "e4")
    // 续播点接近片尾算看完；不到 1 分钟不算看过。
    XCTAssertEqual(
      try upNext([episode("e1", season: 1, episode: 1, position: 7000), episode("e2", season: 1, episode: 2)])?.0, "e2")
    XCTAssertNil(try upNext([episode("e1", season: 1, episode: 1, position: 30), episode("e2", season: 1, episode: 2)]))
    // 特别篇、缺失的集不算；最后一集看完了就没有接着看的。
    XCTAssertEqual(
      try upNext([
        episode("sp", season: 0, episode: 1, played: true),
        episode("e1", season: 1, episode: 1, played: true),
        episode("missing", season: 1, episode: 2, location: "Virtual"),
        episode("e3", season: 1, episode: 3),
      ])?.0, "e3")
    XCTAssertNil(try upNext([episode("e1", season: 1, episode: 1, played: true)]), "全看完了")
    // 看完含两集的文件（E01–E02），同库里还有单独的 E02：接着看 E03，不重播 E02。
    XCTAssertEqual(
      try upNext([
        #"{"Id":"e1-2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":2,"RunTimeTicks":72000000000,"UserData":{"Played":true}}"#,
        episode("e2", season: 1, episode: 2),
        episode("e3", season: 1, episode: 3),
      ])?.0, "e3")
    let combined =
      #"{"Id":"e1-2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":2,"RunTimeTicks":72000000000,"UserData":{"Played":true}}"#
    XCTAssertEqual(
      try upNext([combined, episode("e2", season: 1, episode: 2, position: 1800), episode("e3", season: 1, episode: 3)])?.0,
      "e3", "单独的 E02 带着旧续播点：合集已经看完了它，不回去接着看")
    XCTAssertEqual(
      try upNext([
        episode("e1", season: 1, episode: 1, played: true), combined,
        episode("e2", season: 1, episode: 2), episode("e3", season: 1, episode: 3),
      ])?.0, "e3", "单独的 E01 排在合集前面：合集看完的范围不丢")
    // 两份看完的合集范围重叠（E01–E05、E02–E03）：接着看 E06，详情页核对用的「看完的最后一集」也是到 E05 的那份。
    let overlapping = try items([
      #"{"Id":"e1-5","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":5,"UserData":{"Played":true}}"#,
      #"{"Id":"e2-3","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2,"IndexNumberEnd":3,"UserData":{"Played":true}}"#,
      episode("e6", season: 1, episode: 6),
    ])
    XCTAssertEqual(PlaybackEpisodeProgress.upNext(in: overlapping)?.episode.id, "e6")
    XCTAssertEqual(PlaybackEpisodeProgress.lastWatched(in: overlapping)?.id, "e1-5")
    // 只看完 E01–E05，没看过的 E02–E07 起始集被覆盖：接着看 E06，看完的最后一集仍是 E01–E05，不被推到 E07。
    let unwatchedOverlap = try items([
      #"{"Id":"e1-5","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":5,"UserData":{"Played":true}}"#,
      #"{"Id":"e2-7","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2,"IndexNumberEnd":7}"#,
      episode("e6", season: 1, episode: 6),
    ])
    XCTAssertEqual(PlaybackEpisodeProgress.upNext(in: unwatchedOverlap)?.episode.id, "e6")
    XCTAssertEqual(PlaybackEpisodeProgress.lastWatched(in: unwatchedOverlap)?.id, "e1-5")
    // 缺季集编号的文件排不进顺序：有编号齐全的正片时不参与接着看哪一集。
    let unnumberedWatched =
      #"{"Id":"x","Type":"Episode","RunTimeTicks":72000000000,"UserData":{"Played":true}}"#
    let unnumbered = #"{"Id":"x","Type":"Episode","RunTimeTicks":72000000000}"#
    XCTAssertEqual(
      try upNext([
        episode("e1", season: 1, episode: 1, played: true), episode("e2", season: 1, episode: 2), unnumberedWatched,
      ])?.0, "e2", "看完的未编号文件不让人以为整部看完了")
    XCTAssertEqual(
      try PlaybackEpisodeProgress.lastWatched(in: items([
        episode("e1", season: 1, episode: 1, played: true), episode("e2", season: 1, episode: 2), unnumberedWatched,
      ]))?.id, "e1")
    XCTAssertNil(
      try upNext([
        episode("e1", season: 1, episode: 1, played: true), episode("e2", season: 1, episode: 2, played: true), unnumbered,
      ]), "没看过的未编号文件不算最后一集的下一集")
    XCTAssertEqual(
      try upNext([unnumberedWatched, #"{"Id":"y","Type":"Episode","RunTimeTicks":72000000000}"#])?.0, "y",
      "全都缺编号时仍按服务器的顺序接着看")
    // 服务器给的结束集号异常大也照常算，不逐集展开。
    XCTAssertNil(
      try upNext([
        #"{"Id":"bad","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"IndexNumberEnd":2000000000,"UserData":{"Played":true}}"#,
        episode("e2", season: 1, episode: 2),
      ]), "看完的范围包含后面所有集")
    // 同一部剧在两个媒体库各有一份：同一集在哪份上看完都算，接着看下一集，不会落到另一份的同一集上。
    XCTAssertEqual(
      try upNext([
        episode("a1", season: 1, episode: 1, played: true),
        episode("a2", season: 1, episode: 2),
        episode("b1", season: 1, episode: 1),
        episode("b2", season: 1, episode: 2, position: 1800),
      ]).map { "\($0.0)\($0.1)" }, "b2true", "另一份上第 2 集看到一半：接着看那一份")
    XCTAssertEqual(
      try upNext([
        episode("a1", season: 1, episode: 1, played: true),
        episode("b1", season: 1, episode: 1),
        episode("a2", season: 1, episode: 2),
        episode("b2", season: 1, episode: 2),
      ])?.0, "a2")
    XCTAssertEqual(
      PlaybackEpisodeProgress.lastWatched(in: try items([
        episode("e1", season: 1, episode: 1, played: true, position: 698),
        episode("e2", season: 1, episode: 2, played: true),
      ]))?.id, "e2", "服务器上看完的最后一集，详情页据此在集列表里找下一集")
    XCTAssertNil(
      PlaybackEpisodeProgress.lastWatched(in: try items([
        episode("e1", season: 1, episode: 1, played: true), episode("e2", season: 1, episode: 2, position: 1800),
      ])), "后面还有看到一半的，接着看它")
    XCTAssertNil(try upNext([episode("e1", season: 1, episode: 1)]), "一集都没看过")

    XCTAssertEqual(
      PlaybackEpisodeProgress.latestSeason(in: try items([
        episode("sp", season: 0, episode: 1), episode("s3", season: 3, episode: 1, location: "Virtual"),
        episode("s2", season: 2, episode: 1), episode("s1", season: 1, episode: 1),
      ])), 2, "最新的、有文件的正片季")
  }

  func testProgressFractionOnlyForAValidResumePoint() {
    XCTAssertEqual(PlaybackResumePolicy.progressFraction(positionSeconds: 1800, durationSeconds: 3600), 0.5)
    XCTAssertNil(PlaybackResumePolicy.progressFraction(positionSeconds: 30, durationSeconds: 3600), "不到 1 分钟不算看过")
    XCTAssertNil(PlaybackResumePolicy.progressFraction(positionSeconds: 3400, durationSeconds: 3600), "接近片尾算看完")
    XCTAssertNil(PlaybackResumePolicy.progressFraction(positionSeconds: 1800, durationSeconds: nil), "不知道时长不画")
    XCTAssertNil(PlaybackResumePolicy.progressFraction(positionSeconds: 1800, durationSeconds: 0))
  }

  @MainActor
  func testSeriesPlayActionShowsProgressAndEpisodeWhenResuming() {
    let half = ServerMediaItem(
      id: "e5", kind: .episode, seasonNumber: 2, episodeNumber: 5, runtimeSeconds: 3600, resumePositionSeconds: 900)
    let target = PlaybackTarget.serverItem(serverName: "emby", itemID: "e5")
    let resuming = SeriesPlayAction.labeled(.play(target), resumeFile: half, season: 2, episode: 5)
    XCTAssertEqual(resuming.title, "第 2 季第 5 集", "看到一半：播放图标、进度条和季集号")
    XCTAssertEqual(resuming.progress, 0.25)
    XCTAssertEqual(resuming.accessibilityLabel, "继续播放 第 2 季第 5 集")

    let fresh = SeriesPlayAction.labeled(.play(target), resumeFile: nil, season: 2, episode: 6)
    XCTAssertEqual(fresh.title, "播放 第 2 季第 6 集")
    XCTAssertNil(fresh.progress)
  }

  @MainActor
  func testContinueDecisionPlaysUnlessThereIsEvidenceOfAnotherEpisode() {
    func match(airDate: AirDateCheck, conflict: Bool = false, offset: Bool = false) -> UncertainEpisodeMatch {
      var match = UncertainEpisodeMatch(season: 1, episode: 2, episodeGroup: nil, airDate: airDate)
      match.identityConflict = conflict
      match.hasConsistentSeasonOffset = offset
      return match
    }
    let differs = AirDateCheck.differs(server: "2024-01-01", moviePilot: "2024-03-01")
    XCTAssertTrue(match(airDate: .matches).hasNoContraryEvidence)
    XCTAssertTrue(match(airDate: .unknown).hasNoContraryEvidence, "核对不了日期也以 TMDB 集列表为准")
    XCTAssertFalse(match(airDate: .matches, conflict: true).hasNoContraryEvidence, "编号指向别的集")
    XCTAssertFalse(match(airDate: differs).hasNoContraryEvidence, "播出日期对不上，多半是别的集")
    XCTAssertFalse(match(airDate: differs, offset: true).hasNoContraryEvidence, "整季差两三天交给面板说明")

    // 按下做什么见 `SeriesContinuationTests`。
  }

  @MainActor
  func testSeriesPlayActionTitleNamesTheEpisode() {
    XCTAssertEqual(SeriesPlayAction.title(resumes: true, season: 2, episode: 5), "继续播放 第 2 季第 5 集")
    XCTAssertEqual(SeriesPlayAction.title(resumes: false, season: 2, episode: 6), "播放 第 2 季第 6 集")
    XCTAssertEqual(SeriesPlayAction.title(resumes: false, season: 0, episode: 1), "播放 特别篇第 1 集")
    XCTAssertEqual(SeriesPlayAction.title(resumes: true, season: nil, episode: 3), "继续播放")
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

  func testPlaybackFailureMessageFollowsEngineErrorKind() {
    typealias M = PlaybackFailureMessage
    func message(_ kind: String?, domain: String? = nil, code: Int? = nil, ffmpeg: Int? = nil) -> String {
      M.message(
        for: PlaybackFailure(
          kind: kind, underlyingDomain: domain, underlyingCode: code, ffmpegErrorCode: ffmpeg, message: "engine text"))
    }

    XCTAssertEqual(message("dolbyVisionRequiresHardware"), M.dolbyVisionUnavailable)
    // 打不开片源：只有底层是网络错误时才提网络；FFmpeg 认不出数据是格式问题。
    XCTAssertEqual(message("sourceOpenFailed", domain: NSURLErrorDomain, code: -1004), M.sourceUnreachable)
    XCTAssertEqual(message("sourceOpenFailed", domain: "AetherEngine.DemuxerError", code: 0, ffmpeg: -1_094_995_529), M.unknownFormat)
    XCTAssertEqual(message("sourceOpenFailed", domain: "AetherEngine.DemuxerError", code: 1), M.loadFailedGeneric)
    // 服务器的 HTTP 回答。
    XCTAssertEqual(message("sourceRefused", code: 403), M.sourceRefused)
    XCTAssertEqual(message("sourceRateLimited", code: 429), M.sourceRateLimited)
    XCTAssertEqual(message("sourceCertificateRejected", domain: NSURLErrorDomain, code: -1202), M.certificateRejected)
    // 播放中：系统播放器失败时，底层是网络错误才提网络，否则是格式问题（错误原文按设备语言翻译过，不拿来分类）。
    XCTAssertEqual(message("nativeItemFailed", domain: NSURLErrorDomain, code: -1005), M.sourceInterrupted)
    XCTAssertEqual(message("nativeItemFailed", domain: "AVFoundationErrorDomain", code: -11821), M.formatUnsupported)
    XCTAssertEqual(message("vodSourceFailed", domain: NSURLErrorDomain, code: -1001), M.sourceInterrupted)
    XCTAssertEqual(message("vodSourceFailed", code: 5), M.playbackInterrupted)
    XCTAssertEqual(message("softwarePipelineFailed"), M.decodeFailed)
    XCTAssertEqual(message("audioBridgeProducedNoOutput"), M.audioUndecodable)
    XCTAssertEqual(message("storageExhausted", code: -28), M.storageExhausted)
    XCTAssertEqual(message(M.initializationKind), M.playerInitializationFailed)
    XCTAssertEqual(message(nil), M.playbackFailedGeneric, "引擎没给类别时给通用提示")
    XCTAssertEqual(message("someKindAddedLater"), M.playbackFailedGeneric, "引擎以后新增的类别不会让提示出错")

    let withoutNetworkEvidence: [String?] = [
      "dolbyVisionRequiresHardware", "nativeItemFailed", "softwarePipelineFailed", "audioBridgeProducedNoOutput",
      "storageExhausted", "vodSourceFailed", "reloadFailed", "masterPlaylistRejected", nil,
    ]
    for kind in withoutNetworkEvidence {
      XCTAssertFalse(message(kind).contains("网络"), "没有指向网络的证据时不提网络：\(String(describing: kind))")
    }
    for text in [
      M.dolbyVisionUnavailable, M.sourceUnreachable, M.sourceInterrupted, M.sourceRefused, M.sourceRateLimited,
      M.certificateRejected, M.unknownFormat, M.formatUnsupported, M.decodeFailed, M.audioUndecodable,
      M.audioSwitchFailed, M.storageExhausted, M.loadFailedGeneric, M.playbackInterrupted, M.playerInitializationFailed,
      M.playbackFailedGeneric,
    ] {
      XCTAssertLessThanOrEqual(text.count, 30, "提示在全局通知里单行显示：\(text)")
    }
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
      tmdbDirectory: OfflineTmdbDirectory(), now: now)
  }

  /// 测试不直接请求 TMDB。
  private struct OfflineTmdbDirectory: TmdbEpisodeDirectory {
    func findEpisodes(source: String, value: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?)
      async throws -> [TmdbFoundEpisode]
    {
      throw access == nil ? TmdbDirectError.notCached : TmdbDirectError.unreachable
    }
    func seasonEpisodes(
      tvID: Int, season: Int, language: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?
    ) async throws -> [TmdbEpisode] {
      throw access == nil ? TmdbDirectError.notCached : TmdbDirectError.unreachable
    }
    func originalLanguage(tvID: Int, access: TmdbAccess?, deadline: ContinuousClock.Instant?) async throws -> String? {
      throw access == nil ? TmdbDirectError.notCached : TmdbDirectError.unreachable
    }
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
    XCTAssertEqual(coordinator.session?.startSeconds, 0, "没有续播点时从头播")
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

  func testSavedPositionResumesWithoutAsking() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local:8096"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie(positionSeconds: 1800)]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))

    let session = try XCTUnwrap(coordinator.session, "有续播点也直接起播，不询问")
    XCTAssertEqual(session.startSeconds, 1800, "从上次的位置接着播")

    coordinator.play(.serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(coordinator.resolveTaskForTesting, "播放期间不重复开始解析")
    coordinator.endCurrentSession()
  }

  func testMKVPlaysDirectlyWithoutTranscoding() async throws {
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
    XCTAssertNil(session.player, "播放器等播放界面出现再创建")
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

  func testSeriesPlayedFromLibraryContinuesUpNext() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|s1": #"{"Id":"s1","Name":"某剧","Type":"Series"}"#]
      $0.episodes = [
        "lan.playback-tests.local|s1":
          #"{"Items":[{"Id":"e1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"Played":true}},{"Id":"e2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2,"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":18000000000}}]}"#
      ]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "s1"))
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.item.id, "e2", "接着看到一半的那一集")
    XCTAssertEqual(session.startSeconds, 1800)
    coordinator.endCurrentSession()
  }

  func testSeriesProgressReadsWatchStateFromTheLocatedSeries() async throws {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|s1": #"{"Id":"s1","Name":"某剧","Type":"Series"}"#]
      $0.episodes = [
        "lan.playback-tests.local|s1":
          #"{"Items":[{"Id":"e1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"Played":true}},{"Id":"e2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2,"RunTimeTicks":\#(Self.twoHours),"UserData":{"Played":false,"PlaybackPositionTicks":18000000000}},{"Id":"s2e1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":1}]}"#
      ]
    }
    let coordinator = makeCoordinator(makeService())
    let progress = await coordinator.seriesProgress(for: .serverItem(serverName: "emby", itemID: "s1"))
    XCTAssertEqual(progress?.serverName, "emby")
    XCTAssertEqual(progress?.upNext?.episode.id, "e2")
    XCTAssertEqual(progress?.upNext?.resumes, true)
    XCTAssertEqual(progress?.latestSeason, 2)
    XCTAssertNil(coordinator.session, "只读进度，不起播")

    let notSeries = await coordinator.seriesProgress(for: .serverItem(serverName: "other", itemID: "s1"))
    XCTAssertNil(notSeries, "不是可播放的服务器时没有进度")
  }

  func testMovieProgressReadsTheResumePoint() async {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie(positionSeconds: 1800)]
    }
    let coordinator = makeCoordinator(makeService())
    let progress = await coordinator.movieProgress(for: .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertEqual(progress, 0.25, "两小时的片子看到 30 分钟")
    XCTAssertNil(coordinator.session, "只读进度，不起播")

    PlaybackURLProtocol.stub.configure { $0.items["lan.playback-tests.local|m1"] = Self.movie(positionSeconds: 0) }
    let unwatched = await coordinator.movieProgress(for: .serverItem(serverName: "emby", itemID: "m1"))
    XCTAssertNil(unwatched, "没看过不画进度条")
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

  func testLibraryItemWatchStateIsReadFresh() async throws {
    let host = "lan.playback-tests.local"
    func movie(positionSeconds: Int64) -> String {
      #"{"Id":"731","Name":"测试电影","Type":"Movie","ProviderIds":{"Tmdb":"222"},"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":\#(positionSeconds * 10_000_000)}}"#
    }
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(host)|tmdb.222": movie(positionSeconds: 1800)]
      $0.items = ["\(host)|731": movie(positionSeconds: 1800)]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    let target = PlaybackTarget.libraryItem(itemID: "42", expected: expectation(tmdb: "222"))
    let first = await coordinator.movieProgress(for: target)
    XCTAssertEqual(first, 0.25)

    // 别处又看了一段：每次都按编号重新找，读到的是此刻的续播点。
    PlaybackURLProtocol.stub.configure { $0.providerSearch["\(host)|tmdb.222"] = movie(positionSeconds: 3600) }
    let second = await coordinator.movieProgress(for: target)
    XCTAssertEqual(second, 0.5)
    await run(coordinator, target)
    let session = try XCTUnwrap(coordinator.session)
    XCTAssertEqual(session.startSeconds, 3600)
    coordinator.endCurrentSession()
  }

  func testLocatedTargetIsVerifiedAgainWhenPlaying() async throws {
    // 两台服务器，详情页定位到 a 上的 731；之后 731 在服务器上被改认成别的片，真正的 222 是 800。
    let a = Self.embyServer(name: "a", host: "lan.playback-tests.local")
    let b = Self.embyServer(name: "b", host: "wan.playback-tests.local")
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(a),\(b)]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["lan.playback-tests.local|tmdb.222": Self.movie(id: "731", tmdb: "222")]
      $0.items = ["lan.playback-tests.local|731": Self.movie(id: "731", tmdb: "222")]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    let located = await coordinator.locateLibraryItem("42", expected: expectation(tmdb: "222"), in: try servers(a, b))
    let target = try XCTUnwrap(located)
    PlaybackURLProtocol.stub.configure {
      $0.items = [
        "lan.playback-tests.local|731": Self.movie(id: "731", tmdb: "999"),
        "lan.playback-tests.local|800": Self.movie(id: "800", tmdb: "222"),
      ]
      $0.providerSearch = ["lan.playback-tests.local|tmdb.222": Self.movie(id: "800", tmdb: "222")]
    }
    await run(coordinator, target)
    XCTAssertEqual(streamURL(coordinator)?.path, "/Videos/800/stream.mp4", "起播时按编号重新核对，不播改认后的 731")
    coordinator.endCurrentSession()
  }

  func testReidentifiedMovieIsFoundAgain() async throws {
    let host = "lan.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(host)|tmdb.222": Self.movie(id: "731", tmdb: "222")]
      $0.items = ["\(host)|731": Self.movie(id: "731", tmdb: "222")]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    let target = PlaybackTarget.libraryItem(itemID: "42", expected: expectation(tmdb: "222"))
    _ = await coordinator.movieProgress(for: target)

    // 在服务器上把 731 改认成了别的片，真正的 222 是 800：ID 没变，但不能再播 731。
    PlaybackURLProtocol.stub.configure {
      $0.items = ["\(host)|731": Self.movie(id: "731", tmdb: "999"), "\(host)|800": Self.movie(id: "800", tmdb: "222")]
      $0.providerSearch = ["\(host)|tmdb.222": Self.movie(id: "800", tmdb: "222")]
    }
    await run(coordinator, target)
    XCTAssertEqual(streamURL(coordinator)?.path, "/Videos/800/stream.mp4")
    coordinator.endCurrentSession()
  }

  func testSeriesProgressCountsEveryCopyOnTheServer() async throws {
    let host = "lan.playback-tests.local"
    func series(_ id: String) -> String { #"{"Id":"\#(id)","Name":"某剧","Type":"Series","ProviderIds":{"Tmdb":"222"}}"# }
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(host)|tmdb.222": "\(series("hd")),\(series("uhd"))"]
      $0.episodes = [
        "\(host)|hd":
          #"{"Items":[{"Id":"hd1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1},{"Id":"hd2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2}]}"#,
        "\(host)|uhd":
          #"{"Items":[{"Id":"uhd1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"Played":true}},{"Id":"uhd2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2}]}"#,
      ]
    }
    let media = MediaInfo(tmdb_id: 222, source: "themoviedb", media_id: "222", title: "某剧", type: "电视剧")
    let context = try XCTUnwrap(
      EpisodePlaybackSource(libraryItem: MediaServerItemRef(itemID: "hd", server: "a"))
        .context(media: media, episodeGroup: nil, seasons: [1]))
    let coordinator = makeCoordinator(makeService())
    let progress = await coordinator.seriesProgress(
      for: .libraryItem(itemID: "hd", expected: context.expected, owner: "a"), context: context)
    XCTAssertEqual(progress?.upNext?.episode.seasonNumber, 1)
    XCTAssertEqual(progress?.upNext?.episode.episodeNumber, 2, "在 4K 那份上看完了第 1 集，接着看第 2 集")
  }

  func testReaddedMovieWithNewIDIsFoundAgain() async throws {
    let host = "lan.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(host)|tmdb.222": Self.movie(id: "731", tmdb: "222")]
      $0.items = ["\(host)|731": Self.movie(id: "731", tmdb: "222")]
      $0.playbackInfo = Self.playbackInfo()
    }
    let coordinator = makeCoordinator(makeService())
    let target = PlaybackTarget.libraryItem(itemID: "42", expected: expectation(tmdb: "222"))
    _ = await coordinator.movieProgress(for: target)

    // 删掉重新入库后，服务器对旧 ID 回的是 500 而不是 404。
    PlaybackURLProtocol.stub.configure {
      $0.itemStatus["\(host)|731"] = 500
      $0.items["\(host)|800"] = Self.movie(id: "800", tmdb: "222")
      $0.providerSearch = ["\(host)|tmdb.222": Self.movie(id: "800", tmdb: "222")]
    }
    await run(coordinator, target)
    XCTAssertEqual(streamURL(coordinator)?.path, "/Videos/800/stream.mp4")
    coordinator.endCurrentSession()
  }

  func testPreferredFileIsTriedFirstOnItsServer() {
    let files = [ServerMediaItem(id: "hd5", kind: .episode), ServerMediaItem(id: "uhd5", kind: .episode)]
    let preferred = ServerFileRef(server: "a", itemID: "uhd5")
    XCTAssertEqual(
      PlaybackCoordinator.preferringFile(preferred, in: files, on: "a").map(\.id), ["uhd5", "hd5"],
      "有续播点的那一份先试")
    XCTAssertEqual(PlaybackCoordinator.preferringFile(preferred, in: files, on: "b").map(\.id), ["hd5", "uhd5"])
    XCTAssertEqual(
      PlaybackCoordinator.preferringFile(ServerFileRef(server: "a", itemID: "gone"), in: files, on: "a").map(\.id),
      ["hd5", "uhd5"], "不在确定的文件里时照常按顺序")
  }

  func testWatchStateChangeOnlyConcernsThePlayedMedia() {
    let episode = ServerMediaItem(id: "e1", kind: .episode, seriesID: "s1")
    let fromLibrary = WatchStateChange(episode, episode: nil)
    XCTAssertNil(fromLibrary.tmdbID)
    XCTAssertTrue(fromLibrary.concerns(tmdbID: 100, itemID: nil), "不知道播的是哪部时都重读")

    let known = WatchStateChange(tmdbID: 222, itemIDs: ["e1", "s1"])
    XCTAssertTrue(known.concerns(tmdbID: 222, itemID: nil))
    XCTAssertTrue(known.concerns(tmdbID: nil, itemID: "s1"), "详情页在服务器上找到的就是这部剧")
    XCTAssertFalse(known.concerns(tmdbID: 333, itemID: "s9"), "别的片的详情页不重读")
  }

  func testReaddedSeriesWithNewIDIsFoundAgain() async {
    let host = "lan.playback-tests.local"
    func series(_ id: String) -> String { #"{"Id":"\#(id)","Name":"某剧","Type":"Series","ProviderIds":{"Tmdb":"222"}}"# }
    let watched = #"{"Items":[{"Id":"e1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"Played":true}},{"Id":"e2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2}]}"#
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(host)|tmdb.222": series("s1")]
      $0.episodes = ["\(host)|s1": watched]
    }
    let coordinator = makeCoordinator(makeService())
    let target = PlaybackTarget.libraryItem(itemID: "s1", expected: expectation("电视剧", tmdb: "222"))
    let first = await coordinator.seriesProgress(for: target)
    XCTAssertEqual(first?.upNext?.episode.id, "e2")

    // 删掉重新入库，换了 ID：缓存里的 s1 读集是 404（当作没有集），要重新找到 s9。
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch = ["\(host)|tmdb.222": series("s9")]
      $0.episodesStatus["\(host)|s1"] = 404
      $0.episodes = [
        "\(host)|s9":
          #"{"Items":[{"Id":"n1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":1,"UserData":{"Played":true}},{"Id":"n2","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2}]}"#
      ]
    }
    let second = await coordinator.seriesProgress(for: target)
    XCTAssertEqual(second?.upNext?.episode.id, "n2")
  }

  func testLibraryItemLinksTellDetailFromLibraryOnly() async {
    let host = "lan.playback-tests.local"
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "a", host: host))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "\(host)|731": Self.movie(id: "731", tmdb: "222"),
        "\(host)|800": Self.movie(id: "800", tmdb: nil),
        "\(host)|s1": #"{"Id":"s1","Name":"某剧","Type":"Series","ProviderIds":{"Tmdb":"333"}}"#,
      ]
    }
    let coordinator = makeCoordinator(makeService())
    let links = await coordinator.libraryItemLinks(serverName: "a", itemIDs: ["731", "800", "s1", "gone"])
    XCTAssertEqual(links?["731"], .detail(tmdbID: 222, mediaType: "电影"))
    XCTAssertEqual(links?["800"], .libraryOnly, "没刮到 TMDB 编号的直接播放")
    XCTAssertEqual(links?["s1"], .detail(tmdbID: 333, mediaType: "电视剧"))
    XCTAssertNil(links?["gone"], "不在服务器上的不知道，按标题识别")
    let reads = PlaybackURLProtocol.stub.requests().filter { $0.url.host == host && $0.url.path.hasSuffix("/Items") }
    XCTAssertEqual(reads.count, 1, "一次读完")

    let unknownServer = await coordinator.libraryItemLinks(serverName: "other", itemIDs: ["731"])
    XCTAssertNil(unknownServer)
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
    XCTAssertEqual(
      second, .libraryItem(itemID: "7", expected: expectation(tmdb: "222"), owner: "b"), "a 上同号的电影外部编号对不上，不能选它")
    let first = await coordinator.locateLibraryItem("7", expected: expectation(tmdb: "111"), in: servers)
    XCTAssertEqual(first, .libraryItem(itemID: "7", expected: expectation(tmdb: "111"), owner: "a"))
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
    XCTAssertEqual(
      target, .libraryItem(itemID: "7", expected: expectation(tmdb: "222"), owner: "b"), "多台服务器时只有类型相符不算找到")

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
    XCTAssertEqual(
      target, .libraryItem(itemID: "731", expected: expectation(tmdb: "222"), owner: "a"), "用 Emby 自己的条目 ID，带着身份条件")
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
    XCTAssertEqual(target, .libraryItem(itemID: "731", expected: LibraryItemExpectation(media: media), owner: "a"))
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
    XCTAssertEqual(
      movie, .libraryItem(itemID: "7", expected: expectation(), owner: "b"), "全是 Emby 也要逐台核对，不能播 a 上同号的剧集")
    let series = await coordinator.locateLibraryItem("7", expected: expectation("电视剧"), in: servers)
    XCTAssertEqual(series, .libraryItem(itemID: "7", expected: expectation("电视剧"), owner: "a"))
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
    XCTAssertEqual(found, .libraryItem(itemID: "m1", expected: expectation(), owner: "b"))
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

  /// 播放器报错经会话的 `onFailure` 交到协调器，提示按错误类别给出，不再一律说网络连接。
  func testPlayerFailureShowsMessageMatchingErrorKind() async throws {
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)

    // 软件解码路径上杜比视界 Profile 5（没有兼容的基础层）时引擎给的失败。
    session.handleCurrent(
      .failed(
        PlaybackFailure(
          kind: "dolbyVisionRequiresHardware",
          message: "Dolby Vision Profile 5 has no compatible base layer and cannot be color-correctly decoded")))

    XCTAssertEqual(coordinator.failure?.message, "该片源为杜比视界格式，这台设备无法硬件解码")
    XCTAssertNil(coordinator.session, "播放失败后结束会话")

    let other = makeCoordinator(makeService())
    let next = try await startEpisodeSession(other)
    var received: [String] = []
    next.onFailure = { received.append($0) }
    next.handleCurrent(
      .failed(
        PlaybackFailure(
          kind: "sourceOpenFailed", underlyingDomain: "AetherEngine.DemuxerError", underlyingCode: 0,
          ffmpegErrorCode: PlaybackFailureMessage.invalidDataCode, message: "Invalid data found when processing input")))
    next.handleCurrent(
      .failed(
        PlaybackFailure(
          kind: "sourceOpenFailed", underlyingDomain: NSURLErrorDomain, underlyingCode: -1004,
          message: "Could not connect to the server.")))
    next.handleCurrent(.statusChanged(.paused))
    next.handleCurrent(.updated)

    XCTAssertEqual(
      received, ["无法识别该片源的格式，文件可能已损坏", "无法从媒体服务器读取片源，请检查网络和服务器状态"],
      "格式无法识别不说网络；连不上服务器才提网络；其他事件不提示")
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

  func testEndingPlaybackPublishesWatchStateAfterProgressIsSaved() async throws {
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSessionWithUserData(coordinator)
    session.itemDidLoadForTesting()
    await coordinator.reporterForTesting.waitForQueued()
    let fired = expectation(description: "观看进度更新")
    var savedBeforeNotice = false
    var change: WatchStateChange?
    let subscription = coordinator.watchStateUpdates.sink {
      change = $0
      savedBeforeNotice = PlaybackURLProtocol.stub.requests().contains {
        "\($0.method) \($0.url.path)" == "POST /Users/u-admin/Items/e1/UserData"
      }
      fired.fulfill()
    }
    coordinator.endSession(session)
    await fulfillment(of: [fired], timeout: 10)
    XCTAssertTrue(savedBeforeNotice, "进度写回发完之后才通知详情页重读")
    XCTAssertTrue(change?.itemIDs.contains("e1") == true, "带着刚播的是哪个条目，别的详情页不重读")
    subscription.cancel()
  }

  func testEndingPlaybackAnnouncesTheComingWatchStateChangeAtOnce() async throws {
    // 详情页要在写回发完之前就作废旧的「继续播放」结论：关播放器时立刻告知，不等写回。
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSessionWithUserData(coordinator)
    var changing: [WatchStateChange] = []
    let subscription = coordinator.watchStateChanging.sink { changing.append($0) }
    coordinator.endSession(session)
    XCTAssertTrue(changing.contains { $0.itemIDs.contains("e1") }, "同步发出")
    subscription.cancel()
  }

  func testReturningFromBackgroundDuringPlaybackRereadsEveryDetailPageWhenPlaybackEnds() async throws {
    // 应用内播放时按 Home 去 Emby App 看了别的片再回来：回来时还在播，不读；退出播放器时除了刚播的片，每个详情页都重读。
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSessionWithUserData(coordinator)
    var changes: [WatchStateChange] = []
    let subscription = coordinator.watchStateUpdates.sink { changes.append($0) }
    coordinator.noteEnteredBackground()
    coordinator.refreshWatchStateAfterReturningToForeground()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(changes, [], "还在播，播完再读")

    coordinator.endSession(session)
    try await waitUntil { changes.count == 2 }
    XCTAssertTrue(changes.contains(.unknown))
    XCTAssertTrue(changes.contains { $0.itemIDs.contains("e1") })
    subscription.cancel()
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

  func testResumePointUsesSelectedSourceRuntime() async throws {
    // 条目记的是 2 小时的版本，起播的是 3 小时的加长版，停在 1 小时 55 分：离片尾还远，应接着播。
    func startSeconds(sourceRuntime: String) async throws -> Double? {
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
      defer { coordinator.endCurrentSession() }
      return coordinator.session?.startSeconds
    }

    let threeHours = #","RunTimeTicks":108000000000"#
    let extended = try await startSeconds(sourceRuntime: threeHours)
    XCTAssertEqual(extended, 6900, "按所选片源的 3 小时算，1 小时 55 分还没接近片尾")
    let unknown = try await startSeconds(sourceRuntime: "")
    XCTAssertEqual(unknown, 0, "片源没给时长时退回条目的 2 小时：已过 90%，直接从头播放")
  }

  /// 从播放界面换集：界面发起，协调器解析并替换会话条目，界面再起播新条目。走真实的 `MediaSession` 和 AetherEngine 播放器，
  /// 只证明三者交接正确；测试地址打不开，画面能否真正播出来要在模拟器或真机上看。
  func testSwitchFromPlayerScreenLoadsNewItemOnceAndDropsOldEvents() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSession(coordinator)
    // 播放器打不开测试地址时会异步报失败，这里接住，免得结束会话；下面只在同步代码里比较前后次数。
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
    let player = try XCTUnwrap(session.player, "界面创建时建好播放器")
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
    XCTAssertEqual(player.loadedURL, session.streamURL, "交给播放器的是新条目的地址")
    let started = PlaybackURLProtocol.stub.requests().dropFirst(before)
      .filter { "\($0.method) \($0.url.path)" == "POST /Sessions/Playing" }
      .compactMap { (try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any])?["ItemId"] as? String }
    XCTAssertEqual(started, ["e1", "e2"], "每个条目各上报一次开始")

    // 上一条目还没读到的事件：播完、播放失败都不能算到新条目头上。
    let failuresBefore = failures.count
    screen.handlePlayerEvent(.statusChanged(.ended), generation: firstGeneration)
    XCTAssertNotEqual(screen.state, .stopped, "上一条目的播完不让新条目退出")
    XCTAssertNotEqual(screen.state, .loadingItem, "也不让新条目去接下一集")
    session.handle(.failed(PlaybackFailure(kind: "nativeItemFailed", message: "old")), generation: firstGeneration)
    XCTAssertEqual(failures.count, failuresBefore, "上一条目的失败不结束新条目")

    // 同样的事件属于当前条目时照常处理，说明上面确实是按代号丢弃的。
    session.handle(.failed(PlaybackFailure(kind: "nativeItemFailed", message: "now")), generation: player.generation)
    XCTAssertEqual(failures.count, failuresBefore + 1)
    screen.handlePlayerEvent(.statusChanged(.ended), generation: player.generation)
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

  /// FFmpeg 打开 MKV 时遇到解不开的封装压缩（zlib 压缩轨）报的错误。FFmpeg 只说解不开，不说是哪条轨道。
  private func recordUnsupportedTrackEncoding(in session: PlaybackSession) {
    session.recordEngineLog("[matroska,webm @ 0x10a8c4000] Unsupported encoding type")
  }

  func testDecodeFailureAfterCompressedTrackWarningSaysSoInsteadOfBlamingTheNetwork() async throws {
    // 这版 FFmpeg 没编 zlib：画面和声音压缩了的 MKV 解不出来。FFmpeg 先报解不开，之后系统播放器解码失败。
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)
    recordUnsupportedTrackEncoding(in: session)
    session.handleCurrent(
      .failed(
        PlaybackFailure(
          kind: "nativeItemFailed", underlyingDomain: "AVFoundationErrorDomain", underlyingCode: -11821,
          message: "Cannot Decode")))

    XCTAssertEqual(coordinator.failure?.message, "有轨道用了 zlib 压缩，无法解码，请用媒体服务器 App")
    XCTAssertNil(coordinator.session, "播放失败后结束会话")
  }

  func testCompressedTrackWarningOnlyExplainsDecodeFailures() {
    // 解不开的压缩轨只会让解码失败；打不开片源、服务器拒绝、网络中断另有原因，照常按类别说。
    let zlib = "有轨道用了 zlib 压缩，无法解码，请用媒体服务器 App"
    func message(_ kind: String, domain: String? = nil) -> String {
      PlaybackSession.failureMessage(
        for: PlaybackFailure(kind: kind, underlyingDomain: domain, message: ""), sawUnsupportedTrackEncoding: true)
    }
    XCTAssertEqual(message("softwarePipelineFailed"), zlib)
    XCTAssertEqual(message("nativeItemFailed"), zlib)
    XCTAssertEqual(message("audioBridgeProducedNoOutput"), zlib)
    XCTAssertEqual(message("nativeItemFailed", domain: NSURLErrorDomain), PlaybackFailureMessage.sourceInterrupted)
    XCTAssertEqual(message("sourceRefused"), PlaybackFailureMessage.sourceRefused)
    XCTAssertEqual(message("sourceOpenFailed", domain: NSURLErrorDomain), PlaybackFailureMessage.sourceUnreachable)
    XCTAssertEqual(message("dolbyVisionRequiresHardware"), PlaybackFailureMessage.dolbyVisionUnavailable)
    XCTAssertLessThanOrEqual(zlib.count, 30, "提示在全局通知里单行显示")
  }

  func testFailuresWithoutCompressedTrackWarningUseTheCategoryMessage() async throws {
    XCTAssertEqual(
      PlaybackSession.failureMessage(
        for: PlaybackFailure(kind: "softwarePipelineFailed", message: ""), sawUnsupportedTrackEncoding: false),
      PlaybackFailureMessage.decodeFailed, "没看到解不开的压缩轨时不猜原因，按错误类别说")

    // 上一集报过解不开的压缩轨，换到下一集后不再算到它头上。
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(coordinator)
    recordUnsupportedTrackEncoding(in: session)
    var result: PlaybackCoordinator.SwitchResult?
    coordinator.switchItem(to: "e2", startPosition: 0, in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value
    guard case .switched = result else { return XCTFail("应切到下一集，实际 \(String(describing: result))") }
    var received: [String] = []
    session.onFailure = { received.append($0) }
    session.handleCurrent(.failed(PlaybackFailure(kind: "softwarePipelineFailed", message: "")))
    XCTAssertEqual(received, [PlaybackFailureMessage.decodeFailed])
    coordinator.endCurrentSession()
  }

  func testReportsOfOnePlaybackAreSentInOrderWithEventNames() async throws {
    let coordinator = makeCoordinator(makeService())
    let reporter = coordinator.reporterForTesting
    let session = try await startEpisodeSessionWithUserData(coordinator)
    let before = PlaybackURLProtocol.stub.requests().count

    session.itemDidLoadForTesting()
    await reporter.waitForQueued()
    session.handleCurrent(.statusChanged(.paused))
    await reporter.waitForQueued()
    session.handleCurrent(.statusChanged(.playing))
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
    session.handleCurrent(.statusChanged(.paused))
    session.handleCurrent(.statusChanged(.playing))
    session.handleCurrent(.statusChanged(.paused))
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
      session.handleCurrent(.statusChanged(isPaused ? .paused : .playing))
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
    let player = session.makePlayer()
    var result: PlaybackCoordinator.SwitchResult?

    coordinator.switchItem(to: "e2", startPosition: 0, in: session) { result = $0 }
    await coordinator.switchTaskForTesting?.value

    guard case .switched = result else { return XCTFail("应切到下一集，实际 \(String(describing: result))") }
    XCTAssertTrue(coordinator.session === session, "同一个会话，全屏界面不重新弹出")
    XCTAssertFalse(session.isStopped)
    XCTAssertTrue(session.player === player, "复用同一个播放器")
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))

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
      fields, "ProviderIds,Path,PremiereDate,Overview,UserDataLastPlayedDate", "集列表要带外部编号、文件路径、首播日期、集列表缺简介时用的简介，和最后播放时间")
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
    await run(coordinator, .episode(QueuedEpisode(context: context(), episode: season[0], seasonEpisodes: season), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(1), accepting: .numberMatches))

    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, "服务器上没有这一集")
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
      [
        .uncertain(
          server: "emby",
          match: UncertainEpisodeMatch(
            season: 2, episode: 3, episodeGroup: nil, airDate: .unknown, serverHasNoMetadata: true))
      ])
    let historyRequest = try XCTUnwrap(
      PlaybackURLProtocol.stub.requests().first { $0.url.path == "/api/v1/history/transfer" }, "先查整理记录")
    let query = URLComponents(url: historyRequest.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(query.first { $0.name == "title" }?.value, "长风渡*", "先查标题以剧名开头的记录")
    XCTAssertEqual(query.first { $0.name == "status" }?.value, "true")

    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure, "整理记录读不到也照常按季号集号播")
    XCTAssertEqual(coordinator.session?.item.id, "e-s2e3")
    coordinator.endCurrentSession()
  }

  /// 网络请求等放行后才返回，返回过的记进“缓存”（之后不再发请求）；只读缓存时只有查过的。没列出的编号查空，季列表都没有。
  private actor ScriptedTmdbDirectory: TmdbEpisodeDirectory {
    let found: [String: [TmdbFoundEpisode]]
    private var released: Bool
    private var answered: Set<String> = []
    private(set) var networkCalls = 0

    init(found: [String: [TmdbFoundEpisode]] = [:], released: Bool = true) {
      self.found = found
      self.released = released
    }

    func release() { released = true }
    /// 之后的网络请求再卡住，直到 `release()`。
    func hold() { released = false }
    /// 只读缓存的查询先按当时的缓存定下结果，再卡住到 `releaseCacheReads()` 才返回（模拟建表读完补查依据后还没返回）。
    private var cacheReadsHeld = false
    private var cacheReadBatch = 0
    private(set) var heldCacheReads = 0
    func holdCacheReads() { cacheReadsHeld = true }
    func releaseCacheReads() { cacheReadsHeld = false }
    /// 放行已经卡住的那些，之后的仍然卡住。
    func releaseHeldCacheReads() { cacheReadBatch += 1 }

    func findEpisodes(source: String, value: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?)
      async throws -> [TmdbFoundEpisode]
    {
      let key = "\(source) \(value)"
      // 和 `TmdbLookupStore` 一样：查过的直接用缓存，不再发请求。
      if access == nil, cacheReadsHeld {
        let cached = answered.contains(key)
        heldCacheReads += 1
        let batch = cacheReadBatch
        while cacheReadsHeld, batch == cacheReadBatch { try await Task.sleep(for: .milliseconds(20)) }
        if cached { return found[key] ?? [] }
        throw TmdbDirectError.notCached
      }
      if answered.contains(key) { return found[key] ?? [] }
      if access == nil { throw TmdbDirectError.notCached }
      networkCalls += 1
      while !released { try await Task.sleep(for: .milliseconds(20)) }
      answered.insert(key)
      return found[key] ?? []
    }
    func seasonEpisodes(
      tvID: Int, season: Int, language: String, access: TmdbAccess?, deadline: ContinuousClock.Instant?
    ) async throws -> [TmdbEpisode] {
      []
    }
    func originalLanguage(tvID: Int, access: TmdbAccess?, deadline: ContinuousClock.Instant?) async throws -> String? {
      nil
    }
  }

  /// 只用 TVDB 刮单集的媒体库，MoviePilot 给了 TMDB 的 key。
  private func configureTvdbOnlyLibraryWithTmdbAccess() {
    PlaybackURLProtocol.stub.configure {
      $0.virtualFolders[Self.lan] = #"""
        [{"Locations":["/emby"],"LibraryOptions":{"TypeOptions":[{"Type":"Episode","MetadataFetchers":["TheTVDB"]}]}}]
        """#
      $0.mediaDetails["/api/v1/system/env"] =
        #"{"success":true,"data":{"TMDB_API_KEY":"k","TMDB_API_DOMAIN":"api.themoviedb.org","TMDB_LOCALE":"zh"}}"#
    }
  }

  private func makeCoordinator(
    _ service: APIService, tmdb directory: any TmdbEpisodeDirectory,
    roundBudget: Duration = TmdbEpisodeEvidence.roundBudget,
    retryDelay: Duration = .seconds(PlaybackCoordinator.lookupRoundRetryInterval), now: @escaping () -> Date = Date.init
  ) -> PlaybackCoordinator {
    services.append(service)
    let enabled = enabledInSettings
    return PlaybackCoordinator(
      apiService: service, mediaServerSession: PlaybackURLProtocol.session, isEnabledInSettings: { enabled },
      tmdbDirectory: directory, lookupRoundBudget: roundBudget, lookupRetryDelay: retryDelay, now: now)
  }

  /// 先订阅、再触发：协调器这一轮补查结束时（一定会发通知）满足。
  private func lookupRoundEnd(_ coordinator: PlaybackCoordinator, tmdbID: Int = 100) -> (XCTestExpectation, AnyCancellable) {
    let ended = expectation(description: "一轮补查结束")
    ended.assertForOverFulfill = false
    let subscription = coordinator.evidenceUpdates.sink { id in
      if id == tmdbID { ended.fulfill() }
    }
    return (ended, subscription)
  }

  func testTmdbLookupRunsInTheBackgroundThenRefreshesTheEpisode() async throws {
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"e-bg","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Name":"Other","Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8001"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(
      found: ["tvdb 8001": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]], released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }

    let before = await coordinator.episodeAvailability(for: [episode], context: context())
    guard case .uncertain? = before?.first else { return XCTFail("TMDB 还没回来时先按本地结果显示，不等网络") }
    await directory.release()
    await fulfillment(of: [ended], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertEqual(after, [.playable(server: "emby")])
    let calls = await directory.networkCalls
    XCTAssertEqual(calls, 1)
  }

  func testOlderEmbyWithoutTheQueryEndpointStillGivesLibrarySettings() async throws {
    // 和 MoviePilot 一样先读 `Library/VirtualFolders/Query`；旧版 Emby 没有（404）时退回 `Library/VirtualFolders`。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"e-bg","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Name":"Other","Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8001"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    PlaybackURLProtocol.stub.configure { $0.legacyVirtualFolders = [Self.lan] }
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8001": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [ended], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertEqual(after, [.playable(server: "emby")])
    let paths = PlaybackURLProtocol.stub.requests().map(\.url.path).filter { $0.contains("VirtualFolders") }
    XCTAssertEqual(paths, ["/Library/VirtualFolders/Query", "/Library/VirtualFolders"])
  }

  func testMissingEpisodeWaitsForTheLookupRoundBeforeOfferingTrial() async throws {
    // 没有 TMDB 单集编号、季号集号也对不上任何一集的文件：查清之前，第 2 季第 3 集先不说没有，试看也不放行。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let directory = ScriptedTmdbDirectory(released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }

    let checking = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(checking, [.checking(server: "emby", files: 1)], "第一次核对时不下结论")
    // 试看提交前的复查也是强制重读：沿用同一轮，不重开，照样挡住。
    let recheck = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(recheck?.first?.allowsTrial, false)
    await directory.release()
    await fulfillment(of: [ended], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(after, [.notOnServer], "编号明确查空：那个文件按它自己的编号不会是这一集")
    let calls = await directory.networkCalls
    XCTAssertEqual(calls, 1, "复查没有重开一轮")
  }

  func testLaterRoundsRunInTheBackgroundWithoutBlockingTrial() async throws {
    // 第一轮没查成（TMDB 一直卡着、到点结束）。冷却过后再查是后台重查：缺的集照样能试看，只提示可能已有。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    nonisolated(unsafe) var clock = Date()
    let directory = ScriptedTmdbDirectory(released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory, roundBudget: .milliseconds(300), now: { clock })
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()
    let firstCalls = await directory.networkCalls
    XCTAssertEqual(firstCalls, 1)

    let stillCooling = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(stillCooling, [.unverified(server: "emby", reason: .lookupIncomplete)])

    clock += PlaybackCoordinator.lookupRoundRetryInterval + 60
    let (second, secondSubscription) = lookupRoundEnd(coordinator)
    defer { secondSubscription.cancel() }
    let retried = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(retried, [.unverified(server: "emby", reason: .lookupIncomplete)])
    XCTAssertEqual(retried?.first?.allowsTrial, true, "重查不挡试看")
    await fulfillment(of: [second], timeout: 5)
    let secondCalls = await directory.networkCalls
    XCTAssertEqual(secondCalls, 2, "冷却过后确实又查了一轮，冷却期内没有")
  }

  func testIncompleteRoundAsksTheOpenPageToCheckAgainLater() async throws {
    // 第一轮没查全（TMDB 卡着、到点结束）：面板写着“稍后自动重试”，详情页一直开着也要在重查间隔后收到通知，
    // 重读时开下一轮。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    nonisolated(unsafe) var clock = Date()
    let directory = ScriptedTmdbDirectory(released: false)
    let coordinator = makeCoordinator(
      makeService(), tmdb: directory, roundBudget: .milliseconds(300), retryDelay: .milliseconds(300), now: { clock })
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()

    clock += PlaybackCoordinator.lookupRoundRetryInterval + 1
    let (retry, retrySubscription) = lookupRoundEnd(coordinator)
    await fulfillment(of: [retry], timeout: 5)
    retrySubscription.cancel()
    let (second, secondSubscription) = lookupRoundEnd(coordinator)
    defer { secondSubscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [second], timeout: 5)
    let calls = await directory.networkCalls
    XCTAssertEqual(calls, 2, "收到通知重读时又查了一轮")
  }

  func testCompleteRoundDoesNotScheduleARetry() async throws {
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let coordinator = makeCoordinator(makeService(), tmdb: ScriptedTmdbDirectory(), retryDelay: .milliseconds(200))
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()
    let (retry, retrySubscription) = lookupRoundEnd(coordinator)
    defer { retrySubscription.cancel() }
    retry.isInverted = true
    await fulfillment(of: [retry], timeout: 0.8)
  }

  func testNewFileStartsALookupWithoutWaitingForTheCooldown() async throws {
    // 第一轮查过的文件明确查空；之后新入库一集（带 TVDB 编号）：不等冷却就查它。
    let first = #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#
    configureLibraryWithoutEpisodeIDs(first)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8039": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (firstRound, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [firstRound], timeout: 10)
    firstSubscription.cancel()

    let added = #"{"Id":"new","Type":"Episode","ParentIndexNumber":2,"IndexNumber":39,"Path":"/emby/长风渡/Season 2/39.mkv","ProviderIds":{"Tvdb":"8039"}}"#
    configureLibraryWithoutEpisodeIDs(first, added)
    let (secondRound, secondSubscription) = lookupRoundEnd(coordinator)
    defer { secondSubscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    await fulfillment(of: [secondRound], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertEqual(after, [.playable(server: "emby")], "新文件反查到了这一集")
    let calls = await directory.networkCalls
    XCTAssertEqual(calls, 2, "只查新文件，旧文件用缓存")
  }

  func testNewFileIsCheckedBeforeTrialEvenAfterAnEarlierRound() async throws {
    // 第一轮没查清旧文件（到点结束），之后的重查不挡试看。新入库一集：服务器叫它第 2 季第 39 集，可能就是缺的第 2 季第 3 集；
    // 它还没核对过，查清之前同样先显示正在核对、不能试看，试看提交前的复查也挡住。
    let old = #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#
    configureLibraryWithoutEpisodeIDs(old)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(
      found: ["tvdb 8039": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]], released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory, roundBudget: .seconds(1))
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()
    let afterFirst = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(afterFirst, [.unverified(server: "emby", reason: .lookupIncomplete)], "旧文件核对过、没查清：可以试看")

    let added = #"{"Id":"new","Type":"Episode","ParentIndexNumber":2,"IndexNumber":39,"Path":"/emby/长风渡/Season 2/39.mkv","ProviderIds":{"Tvdb":"8039"}}"#
    configureLibraryWithoutEpisodeIDs(old, added)
    let (second, secondSubscription) = lookupRoundEnd(coordinator)
    defer { secondSubscription.cancel() }
    let checking = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(checking, [.checking(server: "emby", files: 1)], "只算没核对过的新文件")
    let recheck = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(recheck?.first?.allowsTrial, false, "提交前的复查也挡住")
    await directory.release()
    await fulfillment(of: [second], timeout: 5)
    let after = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertEqual(after, [.playable(server: "emby")], "新文件反查到了这一集")
  }

  func testNewFileWhoseIDWasAlreadyAnsweredDoesNotWaitForARound() async throws {
    // 这一集换了文件（洗版），服务器条目 ID 变了、TVDB 编号没变；这个编号以前反查出这部剧的两集（有歧义），已经缓存。
    // 新条目没核对过，但缓存里已经有答案：按没查清处理、可以试看，不显示一个不会结束的“正在核对”。
    let old = #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#
    configureLibraryWithoutEpisodeIDs(old)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let directory = ScriptedTmdbDirectory(
      found: ["tvdb 8038": [TmdbFoundEpisode(id: 556, showID: 100), TmdbFoundEpisode(id: 557, showID: 100)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()

    configureLibraryWithoutEpisodeIDs(old.replacingOccurrences(of: #""Id":"far""#, with: #""Id":"far2""#))
    let replaced = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(replaced, [.unverified(server: "emby", reason: .idsDisagree)])
    let calls = await directory.networkCalls
    XCTAssertEqual(calls, 1, "编号查过，不再请求")
  }

  func testSameItemWithANewExternalIDIsCheckedAgain() async throws {
    // 条目 ID 没变（换了文件或重新刮削），TVDB 编号从 8038 变成 8039：新编号没核对过，查清前缺的集同样先显示正在核对，
    // 也不按重查间隔跳过。
    let item = #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#
    configureLibraryWithoutEpisodeIDs(item)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8039": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (first, firstSubscription) = lookupRoundEnd(coordinator)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [first], timeout: 5)
    firstSubscription.cancel()

    await directory.hold()
    configureLibraryWithoutEpisodeIDs(item.replacingOccurrences(of: "8038", with: "8039"))
    let (second, secondSubscription) = lookupRoundEnd(coordinator)
    defer { secondSubscription.cancel() }
    let checking = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(checking, [.checking(server: "emby", files: 1)])
    await directory.release()
    await fulfillment(of: [second], timeout: 5)
    let after = await coordinator.episodeAvailability(for: [episode], context: context())
    XCTAssertEqual(after, [.playable(server: "emby")], "新编号反查到了这一集")
  }

  func testNumberMatchStartsWithACopyWhoseIDDoesNotPointToAnotherShow() async throws {
    // emby（排在前面）上这一集的文件 TVDB 编号在 TMDB 指向另一部剧，emby2 上同一集的文件没有冲突：
    // 面板按 emby2 说明，「仍要播放」也播 emby2 的，不先试冲突的那份。
    let conflicting =
      #"{"Id":"c1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8100"}}"#
    configureLibraryWithoutEpisodeIDs(conflicting)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let second = "lan2.playback-tests.local"
    let clean = Self.embyEpisode("f1", season: 2, episode: 3, tmdb: nil)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(clean)
      $0.items["\(second)|f1"] = clean
      $0.virtualFolders[second] = $0.virtualFolders[Self.lan]
    }
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8100": [TmdbFoundEpisode(id: 999, showID: 4242)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    await fulfillment(of: [ended], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    guard case .uncertain(let server, let match)? = after?.first else { return XCTFail("\(String(describing: after))") }
    XCTAssertEqual(server, "emby2")
    XCTAssertFalse(match.identityConflict)

    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "f1")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Items/c1/PlaybackInfo") })
    coordinator.endCurrentSession()
  }

  func testContinuePermissionNeverFallsBackToACopyWithAnotherAirDate() async throws {
    // 同一集两份都没有 TMDB 单集编号：日期核对不了的那份（能不问就播）不能直连，另一份播出日期明显不对。
    // 「继续播放」的许可只试第一份，不换成日期对不上的那份；面板里按「仍要播放」（numberMatches）才试它。
    let unplayable = Self.embyEpisode("x-ok", season: 2, episode: 3, tmdb: nil)
    let otherDate =
      #"{"Id":"x-date","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z"}"#
    configureLibraryWithoutEpisodeIDs(unplayable, otherDate)
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2
      $0.playbackInfoByItem["\(Self.lan)|x-ok"] =
        #"{"MediaSources":[{"Id":"remote","Container":"mkv","Protocol":"Http","MediaStreams":[]}]}"#
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    guard case .uncertain(_, let match)? = availability?.first else { return XCTFail("\(String(describing: availability))") }
    XCTAssertTrue(match.hasNoContraryEvidence, "详情页看到的是日期核对不了的那份")

    await run(coordinator, .episode(try queued(0), accepting: .consistentNumberMatches))
    XCTAssertNil(coordinator.session, "不换成日期对不上的那份")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Items/x-date/PlaybackInfo") })

    coordinator.failure = nil
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertEqual(coordinator.session?.item.id, "x-date", "用户在面板里看过说明后才试它")
    coordinator.endCurrentSession()
  }

  /// 默认分季第 2 季第 3 集（TMDB 555，播出日期 2025-10-02）：「继续播放」只用默认分季。
  private static let datedDefaultSeason2 = #"[{"id":555,"season_number":2,"episode_number":3,"air_date":"2025-10-02"}]"#

  private func datedDefaultEpisode() throws -> QueuedEpisode {
    let season = MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(Self.datedDefaultSeason2.utf8)), season: 2)
    return QueuedEpisode(context: context(group: nil), episode: season[0], seasonEpisodes: season)
  }

  func testContinuePermissionChecksTheAirDateReadJustBeforePlaying() async throws {
    // 建索引时这份没有播出日期（没反证）；起播前重新读到的条目补上了明显对不上的日期：不问就播的许可下不播它。
    let undated = Self.embyEpisode("x-1", season: 2, episode: 3, tmdb: nil)
    configureLibraryWithoutEpisodeIDs(undated)
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2
    }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    _ = await coordinator.episodeAvailability(for: [queued.episode], context: queued.context)
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|x-1"] =
        #"{"Id":"x-1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z"}"#
    }
    await run(coordinator, .episode(queued, accepting: .consistentNumberMatches))
    XCTAssertNil(coordinator.session)
    XCTAssertNotNil(coordinator.failure, "说明播出日期对不上，请到集列表里确认")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Items/x-1/PlaybackInfo") })
  }

  func testCredibleCopyListedSecondOnTheSameServerIsChosenAndPlayed() async throws {
    // 同一台上先列出日期对不上的那份、再列出没有反证的那份：详情页的结论和起播都以后者为准，直接播它。
    let otherDate =
      #"{"Id":"x-date","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z"}"#
    let undated = Self.embyEpisode("x-ok", season: 2, episode: 3, tmdb: nil)
    configureLibraryWithoutEpisodeIDs(otherDate, undated)
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2
    }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    let availability = await coordinator.episodeAvailability(for: [queued.episode], context: queued.context)
    guard case .uncertain(_, let match)? = availability?.first else { return XCTFail("\(String(describing: availability))") }
    XCTAssertTrue(match.hasNoContraryEvidence, "代表结果取没有反证的那份")

    await run(coordinator, .episode(queued, accepting: .consistentNumberMatches))
    XCTAssertEqual(coordinator.session?.item.id, "x-ok")
    coordinator.endCurrentSession()
  }

  func testContinueRecheckComparesAMultiEpisodeFileByItsFirstEpisode() async throws {
    // 第 2 季第 3、4 集在一个没有 TMDB 单集编号的文件里；要播第 4 集（晚一周播出）。建索引时文件还没有日期，
    // 起播前重新读到补上了第 3 集的日期：按建索引时核对这个文件用的日期（第一集的）比，不因为和第 4 集不同就拦下。
    let combined = #"{"Id":"x-34","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"IndexNumberEnd":4}"#
    configureLibraryWithoutEpisodeIDs(combined)
    let list =
      #"[{"id":555,"season_number":2,"episode_number":3,"air_date":"2025-10-02"},{"id":556,"season_number":2,"episode_number":4,"air_date":"2025-10-09"}]"#
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = list }
    let season = MoviePilotEpisode.list(try JSONDecoder().decode([TmdbEpisode].self, from: Data(list.utf8)), season: 2)
    let queued = QueuedEpisode(context: context(group: nil), episode: season[1], seasonEpisodes: season)

    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [season[1]], context: queued.context)
    guard case .uncertain(_, let match)? = availability?.first, match.hasNoContraryEvidence else {
      return XCTFail("第二集在这种文件里应按集号对上、没有反证：\(String(describing: availability))")
    }
    XCTAssertEqual(match.referenceAirDate, "2025-10-02", "索引按文件的第一集核对")
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|x-34"] =
        #"{"Id":"x-34","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"IndexNumberEnd":4,"PremiereDate":"2025-10-02T00:00:00Z"}"#
    }
    await run(coordinator, .episode(queued, accepting: .consistentNumberMatches))
    XCTAssertEqual(coordinator.session?.item.id, "x-34")
    coordinator.endCurrentSession()
  }

  func testContinueRecheckTrustsATMDBEpisodeIDAddedJustBeforePlaying() async throws {
    // 建索引时没有 TMDB 单集编号、也没有日期；起播前重新读到补上了这一集的编号（日期却是服务器那边的另一个日期）：
    // 编号确定了就是这一集，不再按日期拦。
    let undated = Self.embyEpisode("x-1", season: 2, episode: 3, tmdb: nil)
    configureLibraryWithoutEpisodeIDs(undated)
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2 }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    _ = await coordinator.episodeAvailability(for: [queued.episode], context: queued.context)
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|x-1"] =
        #"{"Id":"x-1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z","ProviderIds":{"Tmdb":"555"}}"#
    }
    await run(coordinator, .episode(queued, accepting: .consistentNumberMatches))
    XCTAssertEqual(coordinator.session?.item.id, "x-1")
    coordinator.endCurrentSession()
  }

  func testCardProgressComesFromTheSameCopyThePanelDescribes() async throws {
    // 同一台上先列出日期对不上、看过一半的那份，再列出日期核对不了、没看过的那份：面板和起播以后者为准，
    // 集卡片的已播放进度也取后者（没有进度），不显示另一份的 50%。
    let otherDate =
      #"{"Id":"x-date","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z","RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":36000000000}}"#
    let undated = Self.embyEpisode("x-ok", season: 2, episode: 3, tmdb: nil)
    configureLibraryWithoutEpisodeIDs(otherDate, undated)
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2 }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    let lookup = await coordinator.episodePlaybackLookup(for: [queued.episode], context: queued.context)
    XCTAssertEqual(lookup?.watchProgress, [nil], "进度和面板代表的是同一份")
  }

  func testPanelCardAndPlaybackAgreeOnTheMostCredibleCopyAcrossServers() async throws {
    // emby（排在前面）上只有日期对不上、看过一半的那份；emby2 上有日期核对不了、没看过的那份。
    // 面板说明 emby2 的、集卡片不显示 emby 的 50%、面板「仍要播放」也先试 emby2 的。
    let otherDate =
      #"{"Id":"x-date","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z","RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":36000000000}}"#
    configureLibraryWithoutEpisodeIDs(otherDate)
    let second = "lan2.playback-tests.local"
    let clean = Self.embyEpisode("x-ok", season: 2, episode: 3, tmdb: nil)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(clean)
      $0.items["\(second)|x-ok"] = clean
      $0.virtualFolders[second] = $0.virtualFolders[Self.lan]
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2
    }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    let lookup = await coordinator.episodePlaybackLookup(for: [queued.episode], context: queued.context)
    guard case .uncertain(let server, let match)? = lookup?.availability.first else {
      return XCTFail("\(String(describing: lookup?.availability))")
    }
    XCTAssertEqual(server, "emby2")
    XCTAssertTrue(match.hasNoContraryEvidence)
    XCTAssertEqual(lookup?.watchProgress, [nil], "集卡片的进度和面板代表的是同一份")

    await run(coordinator, .episode(queued, accepting: .numberMatches))
    XCTAssertEqual(coordinator.session?.item.id, "x-ok", "「仍要播放」先试没有反证的那份")
    coordinator.endCurrentSession()
  }

  func testRebuiltIndexCredibleCopyIsTriedAfterTheOldCopyTurnsOutStale() async throws {
    // 面板「仍要播放」时旧索引里只有日期对不上的那份；它已经删了，重建索引后找到一份没有反证的新副本：直接播新副本。
    let otherDate =
      #"{"Id":"x-date","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"PremiereDate":"2020-01-01T00:00:00Z"}"#
    configureLibraryWithoutEpisodeIDs(otherDate)
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.datedDefaultSeason2 }
    let coordinator = makeCoordinator(makeService())
    let queued = try datedDefaultEpisode()
    _ = await coordinator.episodeAvailability(for: [queued.episode], context: queued.context)

    let fresh = Self.embyEpisode("x-new", season: 2, episode: 3, tmdb: nil)
    PlaybackURLProtocol.stub.configure {
      $0.items = ["\(Self.lan)|x-new": fresh]
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(fresh)
    }
    await run(coordinator, .episode(queued, accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "x-new", "重建后按当前许可重新考虑新索引里的候选")
    coordinator.endCurrentSession()
  }

  func testPanelPermissionIsNotWidenedWhenTheCleanCopyGoesOffline() async throws {
    // 面板按 emby2 上没有冲突的副本说明“可能不是这一集”，用户按「仍要播放」时 emby2 离线了：不换成 emby 上编号冲突的那份，
    // 报错让用户看到新的说明。面板改成说明编号冲突后再按，才播冲突的那份。
    let conflicting =
      #"{"Id":"c1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8100"}}"#
    configureLibraryWithoutEpisodeIDs(conflicting)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let second = "lan2.playback-tests.local"
    let clean = Self.embyEpisode("f1", season: 2, episode: 3, tmdb: nil)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(clean)
      $0.items["\(second)|f1"] = clean
      $0.virtualFolders[second] = $0.virtualFolders[Self.lan]
    }
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8100": [TmdbFoundEpisode(id: 999, showID: 4242)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    await fulfillment(of: [ended], timeout: 10)
    let shownList = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    let shown = try XCTUnwrap(shownList?.first)
    let acceptance = EpisodeEntry(availability: shown, trialBlock: nil).panelPlaybackAcceptance
    XCTAssertEqual(acceptance, .numberMatches, "面板说明的是没有冲突的副本")

    PlaybackURLProtocol.stub.configure { $0.unreachableHosts = [second] }
    await run(coordinator, .episode(try queued(0), accepting: acceptance))
    XCTAssertNotNil(coordinator.failure)
    XCTAssertNil(coordinator.session)
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Items/c1/PlaybackInfo") },
      "没给编号冲突的许可，冲突的那份一次都不试")

    coordinator.failure = nil
    let reshownList = await coordinator.episodeAvailability(
      for: [try groupEpisode(0)], context: context(), forceRefresh: true)
    let reshown = try XCTUnwrap(reshownList?.first)
    let conflictAcceptance = EpisodeEntry(availability: reshown, trialBlock: nil).panelPlaybackAcceptance
    XCTAssertEqual(conflictAcceptance, .identityConflicts, "emby2 读不到后，面板说明的是编号冲突")
    await run(coordinator, .episode(try queued(0), accepting: conflictAcceptance))
    XCTAssertEqual(coordinator.session?.item.id, "c1", "看过冲突说明后可以播")
    coordinator.endCurrentSession()
  }

  func testIndexReadThatOverlapsAFinishedRoundReturnsTheNewResult() async throws {
    // 强制重读读完补查依据（那时还没查到）后、返回之前，这部剧的一轮补查结束了：原来的调用方要拿到补查后的结果，
    // 不是补查前的。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"e-bg","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Name":"Other","Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8001"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let tmdbEpisodeID = try XCTUnwrap(episode.tmdbEpisodeID)
    let directory = ScriptedTmdbDirectory(
      found: ["tvdb 8001": [TmdbFoundEpisode(id: tmdbEpisodeID, showID: 100)]], released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    // 等后台那轮读到媒体库配置、开始请求 TMDB：之后建表才会读补查缓存。
    for _ in 0..<300 {
      if await directory.networkCalls > 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    await directory.holdCacheReads()
    let reread = Task { await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true) }
    for _ in 0..<300 {
      if await directory.heldCacheReads > 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let held = await directory.heldCacheReads
    XCTAssertGreaterThan(held, 0, "重读卡在读补查依据之后")
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    await directory.release()
    await fulfillment(of: [ended], timeout: 10)
    await directory.releaseCacheReads()
    let result = await reread.value
    XCTAssertEqual(result, [.playable(server: "emby")])
  }

  func testIndexReadThatKeepsMissingNewResultsFailsInsteadOfReturningAStaleOne() async throws {
    // 几台服务器的补查先后结束，读集索引的每一次都碰上这部剧的补查版本变了：跟满次数后报读取失败，
    // 不把已知过期的结果交出去。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"e-bg","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Name":"Other","Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8001"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let directory = ScriptedTmdbDirectory(released: false)
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    // 等后台那轮读到媒体库配置、开始请求 TMDB：之后建表才会读补查缓存。
    for _ in 0..<300 {
      if await directory.networkCalls > 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    await directory.holdCacheReads()
    let reread = Task { await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true) }
    for attempt in 1...PlaybackCoordinator.evidenceFollowLimit {
      for _ in 0..<300 {
        if await directory.heldCacheReads >= attempt { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      let held = await directory.heldCacheReads
      XCTAssertEqual(held, attempt, "第 \(attempt) 次读取卡在读补查依据之后")
      coordinator.evidenceChanged(100)
      await directory.releaseHeldCacheReads()
    }
    let result = await reread.value
    await directory.releaseCacheReads()
    XCTAssertEqual(result, [.failed(PlaybackCoordinator.evidenceUnsettledMessage(server: "emby"))])
  }

  func testRescrapedNumberMatchWithAConflictingIDNeedsTheConflictPermission() async throws {
    // 面板说明“可能不是这一集”时，这份文件的 TVDB 编号还没有冲突；起播前服务器重新刮削，路径和季号集号没变，
    // TVDB 编号换成了已知指向另一部剧的编号：按新编号重建对应表，用面板给的许可不播它。面板改成说明编号冲突后才播。
    let file =
      #"{"Id":"c1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8200"}}"#
    let other =
      #"{"Id":"x1","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8100"}}"#
    configureLibraryWithoutEpisodeIDs(file, other)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let directory = ScriptedTmdbDirectory(found: ["tvdb 8100": [TmdbFoundEpisode(id: 999, showID: 4242)]])
    let coordinator = makeCoordinator(makeService(), tmdb: directory)
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    await fulfillment(of: [ended], timeout: 10)
    let shownList = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    let shown = try XCTUnwrap(shownList?.first)
    let acceptance = EpisodeEntry(availability: shown, trialBlock: nil).panelPlaybackAcceptance
    XCTAssertEqual(acceptance, .numberMatches, "面板显示时编号还没冲突")

    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|c1"] = file.replacingOccurrences(of: "8200", with: "8100")
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(file.replacingOccurrences(of: "8200", with: "8100") + "," + other)
    }
    await run(coordinator, .episode(try queued(0), accepting: acceptance))
    XCTAssertEqual(coordinator.failure?.message, EpisodeAvailability.identityConflictMessage(server: "emby"))
    XCTAssertNil(coordinator.session)
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Items/c1/PlaybackInfo") },
      "编号换成冲突的以后，没有冲突许可就不播")

    coordinator.failure = nil
    let reshownList = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    let reshown = try XCTUnwrap(reshownList?.first)
    let conflictAcceptance = EpisodeEntry(availability: reshown, trialBlock: nil).panelPlaybackAcceptance
    XCTAssertEqual(conflictAcceptance, .identityConflicts, "重建后的对应表按新编号说明编号冲突")
    await run(coordinator, .episode(try queued(0), accepting: conflictAcceptance))
    XCTAssertEqual(coordinator.session?.item.id, "c1")
    coordinator.endCurrentSession()
  }

  func testFinishedLookupRoundOnlyRebuildsThatShowsIndex() async throws {
    // 长风渡一轮补查结束：只让长风渡的集索引按新结果重建，另一部剧缓存着的集索引照常用，不重读。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch["\(Self.lan)|tmdb.200"] = Self.series(id: "s2", tmdb: "200")
      $0.episodes["\(Self.lan)|s2"] = Self.embyEpisodes(Self.embyEpisode("y1", season: 1, episode: 1, tmdb: 901))
    }
    let otherShow = try XCTUnwrap(
      EpisodePlaybackContext(
        media: MediaInfo(tmdb_id: 200, source: "themoviedb", media_id: "200", title: "另一部剧", type: "电视剧"),
        episodeGroup: nil, seasons: [1], libraryItem: nil))
    let otherEpisode = MoviePilotEpisode(TmdbEpisode(id: 901, episodeNumber: 1, seasonNumber: 1), season: 1, index: 0)
    let coordinator = makeCoordinator(makeService(), tmdb: ScriptedTmdbDirectory())
    let before = await coordinator.episodeAvailability(for: [otherEpisode], context: otherShow)
    XCTAssertEqual(before, [.playable(server: "emby")])
    func otherShowReads() -> Int {
      PlaybackURLProtocol.stub.requests().filter { $0.url.path.contains("s2") && $0.url.path.hasSuffix("/Episodes") }.count
    }
    let readsBefore = otherShowReads()

    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    await fulfillment(of: [ended], timeout: 10)
    _ = await coordinator.episodeAvailability(for: [otherEpisode], context: otherShow)
    XCTAssertEqual(otherShowReads(), readsBefore, "另一部剧的集索引没被作废")
  }

  func testRoundEndsAtTheDeadlineEvenIfARequestHangs() async throws {
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    configureTvdbOnlyLibraryWithTmdbAccess()
    let episode = try groupEpisode(0)
    let coordinator = makeCoordinator(
      makeService(), tmdb: ScriptedTmdbDirectory(released: false), roundBudget: .milliseconds(400))
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    let started = ContinuousClock.now
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [ended], timeout: 5)
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(3), "到点就结束，不等卡住的请求")
    let after = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(
      after, [.unverified(server: "emby", reason: .lookupIncomplete)], "没查成：可以试看，但先说明媒体库里可能已有")
  }

  func testUnreadableLibrarySettingsStillWarnThatTheEpisodeMayBeThere() async throws {
    // Emby 的媒体库配置读不到（这里没模拟那个接口，返回 404）：带编号的文件没法核对，缺的集不能直接说没有。
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"far","Type":"Episode","ParentIndexNumber":2,"IndexNumber":38,"Path":"/emby/长风渡/Season 2/38.mkv","ProviderIds":{"Tvdb":"8038"}}"#)
    let episode = try groupEpisode(0)
    let coordinator = makeCoordinator(makeService(), tmdb: ScriptedTmdbDirectory())
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    _ = await coordinator.episodeAvailability(for: [episode], context: context())
    await fulfillment(of: [ended], timeout: 10)
    let after = await coordinator.episodeAvailability(for: [episode], context: context(), forceRefresh: true)
    XCTAssertEqual(after, [.unverified(server: "emby", reason: .librarySettingsUnreadable)])
    XCTAssertEqual(after?.first?.allowsTrial, true, "提示之后仍可选择试看")
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
    XCTAssertEqual(
      transferHistoryQueries().count, 2,
      "第二台的文件在第一台开始读时还没要过，读到的可能没有它们的记录，再增量读一次（一页）")

    _ = await coordinator.episodeAvailability(for: episodes, context: context(), forceRefresh: true)
    XCTAssertEqual(
      PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Episodes") }.count, 4, "两台的集都重读了")
    XCTAssertEqual(transferHistoryQueries().count, 3, "整理记录这一轮只重读一次，不是每台各一次")
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

  /// 新入库的第 11 集：没有 TMDB 单集 ID，路径对得上 `transferRecordE11`。
  private static let unnumberedFileE11 =
    #"{"Id":"e-y","Type":"Episode","Name":"Emby 集名","SeriesName":"长风渡","Path":"/data/电视剧/长风渡 (2023)/Season 1/长风渡 - S01E11 - 第 11 集.mkv"}"#
  private static let transferRecordE11 =
    #"{"id":2,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S01","episodes":"E11","episode_group":"g1","dest":"/media/tv/长风渡 (2023)/Season 1/长风渡 - S01E11 - 第 11 集.mkv","status":true}"#

  func testTransferRecordsAreReusedUntilANewFileAppearsThenReadIncrementally() async throws {
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 1)]
    }
    nonisolated(unsafe) var clock = Date()
    let coordinator = makeCoordinator(makeService(), now: { clock })
    let episodes = try groupSeason1()
    _ = await coordinator.episodeAvailability(for: episodes, context: context())
    XCTAssertEqual(transferHistoryQueries(), ["长风渡*|1"])

    clock += PlaybackCoordinator.episodeIndexTTL + 60
    let reused = await coordinator.episodeAvailability(for: episodes, context: context())
    XCTAssertEqual(reused?.first, .playable(server: "emby"))
    XCTAssertEqual(transferHistoryQueries().count, 1, "集索引过期重建，整理记录还在有效期内、文件没变，不重读")

    // 新整理入库第 11 集：MoviePilot 的第 1 页最前面是新记录，接着是读过的那条。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile, Self.unnumberedFileE11)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage([Self.transferRecordE11, Self.transferRecord(mediaID: "100")], total: 2)
      ]
    }
    clock += PlaybackCoordinator.episodeIndexTTL + 60
    let added = await coordinator.episodeAvailability(for: episodes, context: context())
    XCTAssertEqual(Array(added?.prefix(2) ?? []), [.playable(server: "emby"), .playable(server: "emby")])
    XCTAssertEqual(transferHistoryQueries(), ["长风渡*|1", "长风渡*|1"], "出现新文件就增量读，读到见过的记录为止")
  }

  func testIncrementalReadStartsOverWhenTheTotalShowsARecordWasRemoved() async throws {
    // 上次读到两条（第 10 集和别的剧的一条），总数 2。之后别的剧那条被删、新整理了第 11 集：第 1 页是新记录和第 10 集，
    // 总数仍是 2，对不上“上次 2 条 + 新出现 1 条”，从头重读，不留可能删掉的旧记录。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage(
          [Self.transferRecord(mediaID: "100"), Self.transferRecord(mediaID: "200", id: 9)], total: 2)
      ]
    }
    let coordinator = makeCoordinator(makeService())
    _ = await coordinator.episodeAvailability(for: try groupSeason1(), context: context())
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage([Self.transferRecordE11, Self.transferRecord(mediaID: "100")], total: 2)
      ]
    }
    _ = await coordinator.episodeAvailability(for: try groupSeason1(), context: context(), forceRefresh: true)
    XCTAssertEqual(transferHistoryQueries(), ["长风渡*|1", "长风渡*|1", "长风渡*|1"], "增量读一页，总数对不上，从头再读")
  }

  func testShowWithoutTransferRecordsIsNotReReadOnEveryVisit() async throws {
    // 不是 MoviePilot 整理的剧：两种查法都没有这部剧的记录。查不到的结果也缓存；出现新文件时两种查法各增量读一页。
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    let others = (1...100).map { Self.transferRecord(mediaID: "200", id: 1000 + $0) }
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage([], total: 0),
        "长风渡|1": Self.transferPage(others, total: 150),
        "长风渡|2": Self.transferPage(Array(others.prefix(50)).map { $0.replacingOccurrences(of: #""id":1"#, with: #""id":2"#) }, total: 150),
      ]
    }
    nonisolated(unsafe) var clock = Date()
    let coordinator = makeCoordinator(makeService(), now: { clock })
    _ = await coordinator.episodeAvailability(for: try groupSeason1(), context: context())
    XCTAssertEqual(transferHistoryQueries(), ["长风渡*|1", "长风渡|1", "长风渡|2"])

    clock += PlaybackCoordinator.episodeIndexTTL + 60
    _ = await coordinator.episodeAvailability(for: try groupSeason1(), context: context())
    XCTAssertEqual(transferHistoryQueries().count, 3, "查不到的结果也沿用")

    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile, Self.unnumberedFileE11)
    clock += PlaybackCoordinator.episodeIndexTTL + 60
    _ = await coordinator.episodeAvailability(for: try groupSeason1(), context: context())
    XCTAssertEqual(
      transferHistoryQueries(), ["长风渡*|1", "长风渡|1", "长风渡|2", "长风渡*|1", "长风渡|1"],
      "新文件：按开头查还是空的（总数没变），按包含查第 1 页就遇到读过的，不再读第 2 页")
  }

  func testServerJoiningAnInFlightReadWithANewFileReadsAgain() async throws {
    // 第一台开始读整理记录（那时还没有第 11 集的记录）；第二台带着刚入库的第 11 集跟上这次在途的读取。
    // 读回来的结果不覆盖第二台的新文件，第二台再增量读一次，第 11 集对上记录。
    let second = "lan2.playback-tests.local"
    configureLibraryWithoutEpisodeIDs(Self.unnumberedFile)
    let records = DispatchSemaphore(value: 0)
    let secondEpisodes = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers =
        "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "emby2", host: second))]"
      $0.providerSearch["\(second)|tmdb.100"] = Self.series(id: "t1")
      $0.episodes["\(second)|t1"] = Self.embyEpisodes(Self.unnumberedFileE11)
      $0.transferHistoryPages = ["长风渡*|1": Self.transferPage([Self.transferRecord(mediaID: "100")], total: 1)]
      $0.transferHistoryGate = records
      $0.episodesGates[second] = secondEpisodes
    }
    let coordinator = makeCoordinator(makeService())
    let episodes = try groupSeason1()
    let load = Task { await coordinator.episodeAvailability(for: episodes, context: context()) }
    for _ in 0..<300 where transferHistoryQueries().isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(transferHistoryQueries().count, 1, "第一台开始读")
    secondEpisodes.signal()
    try await Task.sleep(for: .milliseconds(300))
    // 第一台的那次请求已经按旧数据回了；之后的请求能读到新整理的第 11 集。
    PlaybackURLProtocol.stub.configure {
      $0.transferHistoryPages = [
        "长风渡*|1": Self.transferPage([Self.transferRecordE11, Self.transferRecord(mediaID: "100")], total: 2)
      ]
    }
    records.signal()
    records.signal()
    let availability = await load.value
    XCTAssertEqual(Array(availability?.prefix(2) ?? []), [.playable(server: "emby"), .playable(server: "emby2")])
    XCTAssertEqual(transferHistoryQueries().count, 2, "第二台再增量读一次")
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-x")
    coordinator.endCurrentSession()
  }

  func testSameDirectoryVersionsBothRemainPlaybackCandidates() async throws {
    configureLibraryWithoutEpisodeIDs(
      #"{"Id":"original","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/长风渡/Season 2/03.mp4"}"#,
      #"{"Id":"alternate","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Path":"/emby/长风渡/Season 2/03.mkv"}"#)
    PlaybackURLProtocol.stub.configure {
      $0.transferHistory = """
        [{"id":1,"media_source":"themoviedb","media_id":"100","type":"电视剧","seasons":"S02","episodes":"E03","dest":"/mp/长风渡/Season 2/03.mp4","status":true}]
        """
      $0.items.removeValue(forKey: "\(Self.lan)|original")
    }
    let coordinator = makeCoordinator(makeService())
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])
    await run(coordinator, .episode(try queued(0), accepting: .confirmedOnly))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "alternate")
    let itemPaths = PlaybackURLProtocol.stub.requests().map(\.url.path)
    XCTAssertTrue(itemPaths.contains { $0.hasSuffix("/Items/original") })
    coordinator.endCurrentSession()
  }

  func testSpecificEpisodeTitleConfirmsPlaybackAndMustStillMatchAtStart() async throws {
    let item = #"{"Id":"e-title","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"Name":"重逢","PremiereDate":"2025-10-02T16:00:00Z","Path":"/emby/长风渡/Season 2/03.mkv","ProviderIds":{"Tvdb":"8001"}}"#
    configureLibraryWithoutEpisodeIDs(item)
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] =
        #"[{"id":555,"episode_number":3,"season_number":2,"name":"重逢","air_date":"2025-10-04"}]"#
    }
    // 媒体库配置读不到：服务器的标题可能是 TMDB 按季号集号给的，不能拿来核实。
    let unknownSource = makeCoordinator(makeService(), tmdb: ScriptedTmdbDirectory())
    let (unknownEnded, unknownSubscription) = lookupRoundEnd(unknownSource)
    defer { unknownSubscription.cancel() }
    _ = await unknownSource.episodeAvailability(for: [try groupEpisode(0)], context: context())
    await fulfillment(of: [unknownEnded], timeout: 10)
    let unverified = await unknownSource.episodeAvailability(for: [try groupEpisode(0)], context: context())
    guard case .uncertain? = unverified?.first else { return XCTFail("来源不明时只按季号集号") }

    // 只用 TVDB 刮单集，TVDB 编号在 TMDB 明确查空：标题才拿来核实。
    configureTvdbOnlyLibraryWithTmdbAccess()
    let coordinator = makeCoordinator(makeService(), tmdb: ScriptedTmdbDirectory())
    let (ended, subscription) = lookupRoundEnd(coordinator)
    defer { subscription.cancel() }
    let pending = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    guard case .uncertain? = pending?.first else { return XCTFail("编号还没查清时不用标题确认") }
    await fulfillment(of: [ended], timeout: 10)
    let availability = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    XCTAssertEqual(availability, [.playable(server: "emby")])
    XCTAssertEqual(EpisodeEntry(availability: availability?.first).primaryAction, .play)
    await run(coordinator, .episode(try queued(0), accepting: .confirmedOnly))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-title")
    coordinator.endCurrentSession()

    PlaybackURLProtocol.stub.configure {
      let changed = item.replacingOccurrences(of: "重逢", with: "另一集")
      $0.items["\(Self.lan)|e-title"] = changed
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(changed)
    }
    await run(coordinator, .episode(try queued(0), accepting: .confirmedOnly))
    XCTAssertNil(coordinator.session, "起播前标题变化时不能绕过面板使用季集号兜底")
  }

  func testNextEpisodeMatchedOnlyByNumbersPlaysWithoutStopping() async throws {
    // 第 2 季第 3 集带编号，第 4 集没有：下一集照样接着播第 4 集的文件。
    configureLibraryWithoutEpisodeIDs(
      Self.embyEpisode("e-s2e3", season: 2, episode: 3, tmdb: 555),
      Self.embyEpisode("e-s2e4", season: 2, episode: 4, tmdb: nil))
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(0, owned), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(QueuedEpisode(context: context, episode: season[2], seasonEpisodes: season), accepting: .numberMatches))
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
    await run(coordinator, .episode(QueuedEpisode(context: context, episode: season[3], seasonEpisodes: season), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby2")), accepting: .numberMatches))

    XCTAssertEqual(coordinator.session?.item.id, "f1")
    XCTAssertFalse(
      PlaybackURLProtocol.stub.requests().contains { $0.url.host == Self.lan && $0.url.path.hasSuffix("/Episodes") },
      "入库查询说在 emby2，先查它，找到了就不再查别的服务器")
    coordinator.endCurrentSession()
  }

  func testNextEpisodeFollowsMoviePilotOrderOnTheCurrentServer() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertEqual(coordinator.session?.startSeconds, 1800, "续播点以起播前重新读到的为准，不用集索引里的旧值")
    XCTAssertEqual(coordinator.session?.playback.title, "长风渡 · 第 1 季 第 10 集 · 重逢")
    coordinator.endCurrentSession()
  }

  func testResumeStartsTheCopyWithTheResumePointEvenIfTheIndexPredatesIt() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    // 集索引建的时候只有 s1 这一份。
    _ = await coordinator.episodeAvailability(for: [try groupEpisode(0)], context: context())
    // 之后另一个媒体库多了一份 4K（uhd），续播点在它上面；60 秒的集索引里还没有它。
    let uhdEpisode =
      #"{"Id":"x-uhd","Type":"Episode","ParentIndexNumber":2,"IndexNumber":3,"ProviderIds":{"Tmdb":"555"},"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":18000000000}}"#
    PlaybackURLProtocol.stub.configure {
      $0.providerSearch["\(Self.lan)|tmdb.100"] = [Self.series(), Self.series(id: "uhd")].joined(separator: ",")
      $0.episodes["\(Self.lan)|uhd"] = Self.embyEpisodes(uhdEpisode)
      $0.items["\(Self.lan)|x-uhd"] = uhdEpisode
    }
    var queued = try queued(0)
    queued.preferredFile = ServerFileRef(server: "emby", itemID: "x-uhd")
    await run(coordinator, .episode(queued, accepting: .confirmedOnly))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "x-uhd", "播有续播点的那一份，不从头播旧索引里的另一份")
    XCTAssertEqual(coordinator.session?.startSeconds, 1800)
    coordinator.endCurrentSession()
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(1), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    let session = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: session.playback)
    XCTAssertEqual(
      next, .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(2), accepting: .numberMatches))
    let last = try XCTUnwrap(coordinator.session)
    let afterLast = try await coordinator.adjacentEpisode(.next, from: last.playback)
    XCTAssertEqual(afterLast, .stop(EpisodeAvailability.unmatchedMessage(server: "emby", noun: "下一集")))
    XCTAssertEqual(
      EpisodeAvailability.unmatchedMessage(server: "emby", noun: "下一集"),
      "下一集可能已经入库。有文件认不出是哪一集，刷新元数据后再检查")
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(1), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0, owned), accepting: .numberMatches))
    let first = try XCTUnwrap(coordinator.session)
    let next = try await coordinator.adjacentEpisode(.next, from: first.playback)
    XCTAssertEqual(
      next, .play(try queueEntry(2, item: try Self.serverEpisode("e-s2e5", season: 2, episode: 5, tmdb: 557)), skippedMissing: true))
    coordinator.endCurrentSession()

    await run(coordinator, .episode(try queued(2, owned), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0, owned), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-new", "重新读到的已经是另一集：重读集索引，播现在的那一条")
    coordinator.endCurrentSession()
  }

  func testSwitchingToARescrapedItemPlaysTheCurrentCopy() async throws {
    // 队列给的第 12 集是 e-s2e5，换集前 Emby 重新刮削，它成了 999，557 换成了 e-557。
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "e-new")
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path == "/Items/e-s2e3/PlaybackInfo" })
    coordinator.endCurrentSession()
  }

  func testSwitchingEpisodeExplainsWhenTheFreshItemLacksAnIDAndHasNoConfirmedCopy() async throws {
    configureDefaultOrderLibrary()
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(2), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(1, owned), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(2), accepting: .numberMatches))
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
    await run(fresh, .episode(try queued(2), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(coordinator.session?.item.id, "x-b")
    coordinator.endCurrentSession()

    PlaybackURLProtocol.stub.configure { $0.itemStatus["\(Self.lan)|x-b"] = 500 }
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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

    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby")), accepting: .numberMatches))
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
    await run(episodes, .episode(try queued(0, context(libraryServer: "emby", libraryItemID: "old-s")), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0), accepting: .numberMatches))
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
    await run(coordinator, .episode(try queued(0, context(libraryServer: "emby")), accepting: .numberMatches))
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

  /// 默认顺序第 1 季两集（TMDB 单集 11、12），带 `withSeason2` 时还有第 2 季两集（21、22）；Emby 上的集由 `episodes` 给出。
  /// 详情页带季信息，能按集对应。
  private func makeContinueWatchingDetailViewModel(
    _ episodes: String..., withSeason2: Bool = false, season2Readable: Bool = true, seasonInfo custom: String? = nil,
    configure: (inout PlaybackStub.Scenario) -> Void = { _ in }
  ) throws
    -> (MediaDetailViewModel, APIService)
  {
    enableInAppPlaybackPreferenceForTest()
    let seasonInfo =
      custom ?? (withSeason2
      ? #"[{"season_number":1,"episode_count":2},{"season_number":2,"episode_count":2}]"#
      : #"[{"season_number":1,"episode_count":2}]"#)
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.providerSearch = ["\(Self.lan)|tmdb.100": Self.series()]
      $0.items = ["\(Self.lan)|s1": Self.series()]
      $0.episodes = ["\(Self.lan)|s1": Self.embyEpisodes(episodes.joined(separator: ","))]
      $0.tmdbEpisodes = ["/api/v1/tmdb/100/1": Self.twoEpisodeSeason1]
      if season2Readable { $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.twoEpisodeSeason2 }
      // MoviePilot 给的全部季（「继续播放」对集时用，和集索引一样）。
      $0.mediaSeasons = seasonInfo
      $0.mediaServerExists = #"{"success":true,"data":{"item":{"id":"s1","server":"emby"}}}"#
      configure(&$0)
    }
    let service = makeService()
    services.append(service)
    service.makePlaybackCoordinatorForTesting = {
      PlaybackCoordinator(
        apiService: $0, mediaServerSession: PlaybackURLProtocol.session, isEnabledInSettings: { true },
        tmdbDirectory: OfflineTmdbDirectory())
    }
    let seasons = try JSONDecoder().decode([TmdbSeason].self, from: Data(seasonInfo.utf8))
    let detail = MediaInfo(
      tmdb_id: 100, source: "themoviedb", media_id: "100", title: "长风渡", type: "电视剧", season_info: seasons)
    let viewModel = MediaDetailViewModel(detail: detail, apiService: service)
    viewModel.applyFullDetail(detail)
    return (viewModel, service)
  }

  private static let twoEpisodeSeason1 =
    #"[{"id":11,"season_number":1,"episode_number":1},{"id":12,"season_number":1,"episode_number":2}]"#
  private static let twoEpisodeSeason2 =
    #"[{"id":21,"season_number":2,"episode_number":1},{"id":22,"season_number":2,"episode_number":2}]"#

  /// Emby 上第 1 季的一集（每集 2 小时），`position` 是续播点（秒）。
  private static func watchedEpisode(
    _ id: String, season: Int = 1, episode: Int, tmdb: Int, played: Bool = false, position: Int = 0
  ) -> String {
    let ticks = Int64(position) * 10_000_000
    return #"{"Id":"\#(id)","Type":"Episode","SeriesId":"s1","ParentIndexNumber":\#(season),"IndexNumber":\#(episode),"RunTimeTicks":\#(twoHours),"ProviderIds":{"Tmdb":"\#(tmdb)"},"UserData":{"Played":\#(played),"PlaybackPositionTicks":\#(ticks)}}"#
  }

  func testContinueJudgesTheWatchedFileFromTheSameServerRead() async throws {
    // 第一次打开时 Emby 上只有第 1 集；再打开时多了一份看到一半的第 2 集，带的 TMDB 编号是 999（别的集），而且之后再读
    // Emby 都会失败。观看记录和集索引共用这一次读取：缓存里的旧索引没有这份文件，就按这次读到的重建，照常认出编号对不上，
    // 打开第 2 集的面板，不把它当成对不到、没有反证直接续播；也不再读一次 Emby。
    let e1 = Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true)
    let e2 = Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
    let (first, service) = try makeContinueWatchingDetailViewModel(e1)
    try await waitUntil { first.seriesPlayAction != nil }
    let detail = first.detail
    first.cancelForPop()
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(e1 + "," + e2)
      $0.items["\(Self.lan)|e2"] = e2
      $0.playbackInfo = Self.playbackInfo()
      $0.successfulEpisodeReadsBeforeFailure = 1
    }
    let before = PlaybackURLProtocol.stub.requests().count
    let second = MediaDetailViewModel(detail: detail, apiService: service)
    defer { second.cancelForPop() }
    second.applyFullDetail(detail)
    try await waitUntil { second.seriesPlayAction != nil }
    XCTAssertEqual(second.seriesPlayAction?.action, .openEpisode)
    XCTAssertEqual(second.episodeRowHint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
    let episodeReads = PlaybackURLProtocol.stub.requests().dropFirst(before).filter { $0.url.path.hasSuffix("/Episodes") }
    XCTAssertEqual(episodeReads.count, 1, "观看记录和集索引共用一次读取")
  }

  func testRetryReadsEachSeasonListOnceForTheDetailPageAndTheIndex() async throws {
    // 按「播放」重试的这一轮里，集索引和详情页都要第 1 季的集列表：只读一次，两边用同一份回包。MoviePilot 恰好在
    // 集索引读完、详情页还没读时恢复，详情页也不另读一份，结论和集索引一致（还是读不到集列表），不只打开面板。
    let file = #"{"Id":"e1","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(file) {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = "[]"
      $0.transferHistory = "[]"
      $0.items["\(Self.lan)|e1"] = file
      $0.playbackInfo = Self.playbackInfo()
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("一开始读不到集列表：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    // 卡住季目录：详情页读完季目录才读集列表，让集索引先读第 1 季。
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<4 { gate.signal() } }
    PlaybackURLProtocol.stub.configure { $0.mediaSeasonsGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    func listReads() -> Int {
      PlaybackURLProtocol.stub.requests().dropFirst(before).filter { $0.url.path == "/api/v1/tmdb/100/1" }.count
    }
    try await waitUntil { listReads() == 1 }
    try await Task.sleep(for: .milliseconds(150))
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = Self.twoEpisodeSeason1 }
    for _ in 0..<4 { gate.signal() }
    try await waitUntil { !coordinator.isBusy }
    XCTAssertEqual(listReads(), 1)
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("和集索引同一份回包：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertNil(viewModel.episodePanelRequest)
    XCTAssertNil(coordinator.session)
  }

  func testConcurrentPagesEachJudgeTheirOwnServerRead() async throws {
    // 两页同时打开同一部剧：A 页读到的 Emby 上有一份第 2 集带着别的集的编号 999（还有一份第 2 季没编号的文件，
    // 它的集索引要等第 2 季的集列表）；A 页还没定下时 B 页打开，读到的已经换成编号正确的第 2 集。A 页按它自己读到的那批
    // 文件判断，不会配上 B 页的集索引：认出 999 那份对不上，打开第 2 集的面板，按头部也不给它创建播放会话。
    let e1 = Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true)
    let wrong = Self.watchedEpisode("wrong", episode: 2, tmdb: 999, position: 1800)
    let valid = Self.watchedEpisode("valid", episode: 2, tmdb: 12)
    let extra = #"{"Id":"extra","Type":"Episode","SeriesId":"s1","ParentIndexNumber":2,"IndexNumber":1}"#
    let (warm, service) = try makeContinueWatchingDetailViewModel(e1)
    try await waitUntil { warm.seriesPlayAction != nil }
    let detail = warm.detail
    warm.cancelForPop()
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<4 { gate.signal() } }
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes([e1, wrong, extra].joined(separator: ","))
      $0.items["\(Self.lan)|wrong"] = wrong
      $0.playbackInfo = Self.playbackInfo()
      $0.transferHistory = "[]"
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.twoEpisodeSeason2
      $0.tmdbEpisodesGates["/api/v1/tmdb/100/2"] = gate
    }
    let a = MediaDetailViewModel(detail: detail, apiService: service)
    defer { a.cancelForPop() }
    a.applyFullDetail(detail)
    try await waitUntil { Self.seasonListRequests().contains("/api/v1/tmdb/100/2") }
    PlaybackURLProtocol.stub.configure { $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(e1 + "," + valid) }
    let b = MediaDetailViewModel(detail: detail, apiService: service)
    defer { b.cancelForPop() }
    b.applyFullDetail(detail)
    try await waitUntil { b.seriesPlayAction != nil }
    XCTAssertNil(a.seriesPlayAction)
    for _ in 0..<4 { gate.signal() }
    try await waitUntil { a.seriesPlayAction != nil }
    XCTAssertEqual(a.seriesPlayAction?.action, .openEpisode)
    XCTAssertEqual(a.episodeRowHint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
    let coordinator = service.sessionScope.playbackCoordinator
    a.playFromHeader(try XCTUnwrap(a.inAppPlaybackTarget))
    try await waitUntil { a.episodePanelRequest != nil }
    XCTAssertNil(coordinator.session)
  }

  func testRetrySharesAFailedEpisodeListReadAndTheNextRetryRecovers() async throws {
    // 按「播放」重试的这一轮里，集索引先读第 1 季、MoviePilot 回 404；详情页随后要第 1 季时 MoviePilot 已经恢复，
    // 但同一轮不再读：两处看到同样的失败（读不到集列表），不会一处失败一处成功、只打开面板。下一次重试重新读，照常起播。
    let file = #"{"Id":"e1","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(file) {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = "[]"
      $0.transferHistory = "[]"
      $0.items["\(Self.lan)|e1"] = file
      $0.playbackInfo = Self.playbackInfo()
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("一开始读不到集列表：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    // 卡住季目录：详情页读完季目录才读集列表，让集索引先读第 1 季。
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<4 { gate.signal() } }
    PlaybackURLProtocol.stub.configure {
      $0.mediaSeasonsGate = gate
      $0.tmdbEpisodes.removeValue(forKey: "/api/v1/tmdb/100/1")
    }
    let before = PlaybackURLProtocol.stub.requests().count
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    func listReads() -> Int {
      PlaybackURLProtocol.stub.requests().dropFirst(before).filter { $0.url.path == "/api/v1/tmdb/100/1" }.count
    }
    try await waitUntil { listReads() == 1 }
    try await Task.sleep(for: .milliseconds(150))
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = Self.twoEpisodeSeason1
      $0.mediaSeasonsGate = nil
    }
    for _ in 0..<4 { gate.signal() }
    try await waitUntil { !coordinator.isBusy }
    XCTAssertEqual(listReads(), 1)
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("和集索引看到同样的失败：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertNil(viewModel.episodePanelRequest)
    XCTAssertNil(coordinator.session)
    // 下一次重试：重新读，MoviePilot 已恢复，照常起播。
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.session != nil || coordinator.failure != nil }
    XCTAssertEqual(coordinator.session?.item.id, "e1")
    coordinator.endCurrentSession()
  }

  /// 接着看到一半、没有单集编号的第 1 季第 3 集（集列表只有两集，对不到、没有反证）。
  private static let unlistedHalfWatched =
    #"{"Id":"e3","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":3,"RunTimeTicks":72000000000,"UserData":{"Played":false,"PlaybackPositionTicks":18000000000}}"#

  func testServerFileThatCannotBePlacedIsResumedAtLaunch() async throws {
    // 对不到集列表、没有反证的那份：照现有规则续播它，起播时核对编号没变，照常创建播放会话。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true), Self.unlistedHalfWatched
    ) {
      $0.items["\(Self.lan)|e3"] = Self.unlistedHalfWatched
      $0.playbackInfo = Self.playbackInfo()
      $0.transferHistory = "[]"
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e3")
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.session != nil || coordinator.failure != nil }
    XCTAssertEqual(coordinator.session?.item.id, "e3")
    coordinator.endCurrentSession()
  }

  func testServerFileWhoseAirDateTurnsContradictoryIsNotResumedAsIs() async throws {
    // 第 2 集另有编号确定的副本（e2b），按钮按续播点在 e2a（只按季号集号对上，日期相符）定下。之后 e2a 的播出日期被改成
    // 和这一集明显对不上，季号集号、编号都没变：起播前和按集起播同一处复核，日期对不上就不原样播；详情页重新判断，
    // 改成按集播第 2 集（从编号确定的那份）。
    let file = #"{"Id":"e2a","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":2,"PremiereDate":"2025-09-01T00:00:00Z","RunTimeTicks":72000000000,"UserData":{"PlaybackPositionTicks":18000000000}}"#
    let first = Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true)
    let confirmed = Self.watchedEpisode("e2b", episode: 2, tmdb: 12)
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(first, file, confirmed) {
      $0.items["\(Self.lan)|e2a"] = file
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] =
        #"[{"id":11,"season_number":1,"episode_number":1},{"id":12,"season_number":1,"episode_number":2,"air_date":"2025-09-01"}]"#
      $0.playbackInfo = Self.playbackInfo()
      $0.transferHistory = "[]"
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e2a")
    let redated = file.replacingOccurrences(of: "2025-09-01", with: "2025-01-01")
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e2a"] = redated
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes([first, redated, confirmed].joined(separator: ","))
    }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.session != nil || coordinator.failure != nil }
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, PlaybackCoordinator.seriesFileChangedMessage)
    try await waitUntil {
      if case .play(.episode)? = viewModel.seriesPlayAction?.action { return true }
      return false
    }
    guard case .play(.episode(let queued, _))? = viewModel.seriesPlayAction?.action else { return }
    XCTAssertEqual(queued.episode.tmdbEpisodeID, 12)
  }

  func testLeavingTheDetailPageStopsDispatchingSeasonListReads() async throws {
    // 10 季、每季都有没编号的文件（集索引要读 10 份集列表，同时读 4 份）：读到第一批时离开详情页，放行这一批后
    // 不再发出后面的季。
    let show = Self.manySeasons(10)
    let files = (1...10).map { number in
      #"{"Id":"e\#(number)","Type":"Episode","SeriesId":"s1","ParentIndexNumber":\#(number),"IndexNumber":1}"#
    }
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<8 { gate.signal() } }
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(files[0], seasonInfo: show.seasonInfo) {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(files.joined(separator: ","))
      $0.tmdbEpisodes = show.lists
      $0.transferHistory = "[]"
      $0.tmdbEpisodesGates = Dictionary(uniqueKeysWithValues: (1...4).map { ("/api/v1/tmdb/100/\($0)", gate) })
    }
    try await waitUntil { Set(Self.seasonListRequests()).count >= 4 }
    XCTAssertEqual(Set(Self.seasonListRequests()).count, 4)
    viewModel.cancelForPop()
    for _ in 0..<4 { gate.signal() }
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertEqual(Set(Self.seasonListRequests()).count, 4, "\(Self.seasonListRequests())")
    XCTAssertNil(viewModel.seriesPlayAction)
  }

  func testLeavingTheDetailPageStopsDispatchingSecondaryServerSeasonListReads() async throws {
    // 两台服务器：观看记录在第一台；第二台（集索引走共享缓存）上第 2–11 季都有没编号的文件，它的集索引读第一批 4 份时
    // 离开详情页。没有别的页面在等这份集索引：放行这一批后，不再发出后面的季。
    let backup = "backup.playback-tests.local"
    let show = Self.manySeasons(11)
    let main = Self.watchedEpisode("e1", episode: 1, tmdb: 101)
    let files = (2...11).map { number in
      #"{"Id":"backup-e\#(number)","Type":"Episode","SeriesId":"s1","ParentIndexNumber":\#(number),"IndexNumber":1}"#
    }
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<8 { gate.signal() } }
    let initial = Set((2...5).map { "/api/v1/tmdb/100/\($0)" })
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(main, seasonInfo: show.seasonInfo) {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: Self.lan)),\(Self.embyServer(name: "backup", host: backup))]"
      $0.providerSearch["\(backup)|tmdb.100"] = Self.series()
      $0.episodes["\(backup)|s1"] = Self.embyEpisodes(files.joined(separator: ","))
      $0.tmdbEpisodes = show.lists
      $0.transferHistory = "[]"
      $0.tmdbEpisodesGates = Dictionary(uniqueKeysWithValues: initial.map { ($0, gate) })
    }
    func secondaryListRequests() -> [String] {
      Self.seasonListRequests().filter { $0 != "/api/v1/tmdb/100/1" }
    }
    try await waitUntil { initial.isSubset(of: Set(secondaryListRequests())) }
    XCTAssertEqual(Set(secondaryListRequests()), initial)
    viewModel.cancelForPop()
    for _ in 0..<4 { gate.signal() }
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertEqual(Set(secondaryListRequests()), initial, "\(secondaryListRequests())")
    XCTAssertNil(viewModel.seriesPlayAction)
  }

  func testEpisodeListRequestAsksEmbyForTheLastPlayedDate() async throws {
    // 同一集重新在看的判断要用最后播放时间：Emby 剧集列表默认不给，读观看记录的那次请求要点名要它，不逐集另发请求。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true))
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    let reads = PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Episodes") }
    XCTAssertFalse(reads.isEmpty)
    for read in reads {
      let fields = URLComponents(url: read.url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "Fields" }?.value?.split(separator: ",").map(String.init) ?? []
      XCTAssertTrue(fields.contains("UserDataLastPlayedDate"), "\(read.url)")
    }
    XCTAssertTrue(PlaybackURLProtocol.stub.requests().filter { $0.url.path.contains("/Items/e1") }.isEmpty, "不逐集另读")
  }

  func testServerFileMovedToAnotherSeriesIsNotResumedAsIs() async throws {
    // 按钮定下要续播那份对不到集列表的文件之后，服务器把这个条目归到了另一部剧（季号集号、路径都没变）：
    // 起播前复核认出所属剧变了，不原样播。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true), Self.unlistedHalfWatched
    ) {
      $0.items["\(Self.lan)|e3"] = Self.unlistedHalfWatched
      $0.playbackInfo = Self.playbackInfo()
      $0.transferHistory = "[]"
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e3")
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e3"] = Self.unlistedHalfWatched.replacingOccurrences(of: #""SeriesId":"s1""#, with: #""SeriesId":"other""#)
    }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.failure != nil || coordinator.session != nil }
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, PlaybackCoordinator.seriesFileChangedMessage)
  }

  func testServerFileRenumberedAfterTheDecisionIsNotPlayedAsIs() async throws {
    // 按钮定下要续播那份对不到集列表的文件之后，它被重新刮削成第 1 季第 2 集、编号 999（和集列表的第 2 集对不上）：
    // 起播时现读到编号变了，不原样播；详情页按新数据重新判断，认出对不上，改成打开第 2 集的面板。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true), Self.unlistedHalfWatched
    ) {
      $0.items["\(Self.lan)|e3"] = Self.unlistedHalfWatched
      $0.playbackInfo = Self.playbackInfo()
      $0.transferHistory = "[]"
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e3")
    let renumbered = Self.watchedEpisode("e3", episode: 2, tmdb: 999, position: 1800)
    PlaybackURLProtocol.stub.configure {
      $0.items["\(Self.lan)|e3"] = renumbered
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true) + "," + renumbered)
    }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.failure != nil || coordinator.session != nil }
    XCTAssertNil(coordinator.session)
    XCTAssertEqual(coordinator.failure?.message, PlaybackCoordinator.seriesFileChangedMessage)
    try await waitUntil { viewModel.seriesPlayAction?.action == .openEpisode }
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
  }

  func testRetryIndexReusesTheEpisodeListTheDetailPageJustRead() async throws {
    // 反过来的顺序：这一轮详情页先读到第 1 季（集索引还在等整理记录），集索引随后用同一份，不再读一次。
    let file = #"{"Id":"e1","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(file) {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = "[]"
      $0.transferHistory = "[]"
      $0.items["\(Self.lan)|e1"] = file
      $0.playbackInfo = Self.playbackInfo()
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    let gate = DispatchSemaphore(value: 0)
    defer { for _ in 0..<4 { gate.signal() } }
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = Self.twoEpisodeSeason1
      $0.transferHistoryGate = gate
    }
    let before = PlaybackURLProtocol.stub.requests().count
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    func listReads() -> Int {
      PlaybackURLProtocol.stub.requests().dropFirst(before).filter { $0.url.path == "/api/v1/tmdb/100/1" }.count
    }
    try await waitUntil { listReads() == 1 }
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<4 { gate.signal() }
    try await waitUntil { coordinator.session != nil || coordinator.failure != nil }
    XCTAssertEqual(coordinator.session?.item.id, "e1")
    XCTAssertEqual(listReads(), 1)
    coordinator.endCurrentSession()
  }

  func testRetryRebuildsTheEpisodeIndexFromTheRefreshedEpisodeList() async throws {
    // MoviePilot 一开始读不到第 1 季的集列表（空列表）；恢复后按「播放」重试：集索引也按新的集列表重建，照常起播，
    // 不因为索引仍用缓存里的空列表、说这一季没读全而只打开面板。
    let unnumbered = #"{"Id":"e1","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(unnumbered) {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = "[]"
      $0.transferHistory = "[]"
      $0.items["\(Self.lan)|e1"] = unnumbered
      $0.playbackInfo = Self.playbackInfo()
    }
    defer { viewModel.cancelForPop() }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("一开始读不到集列表：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    // 卡住详情页这次重读的季目录（它读完季目录才读集列表）：集索引先重建完，不能靠详情页刚写进缓存的新列表。
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    PlaybackURLProtocol.stub.configure {
      $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = Self.twoEpisodeSeason1
      $0.mediaSeasonsGate = gate
    }
    let before = PlaybackURLProtocol.stub.requests().count
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil {
      PlaybackURLProtocol.stub.requests().dropFirst(before).contains { $0.url.path == "/api/v1/tmdb/100/1" }
    }
    try await Task.sleep(for: .milliseconds(250))
    gate.signal()
    try await waitUntil { coordinator.session != nil || coordinator.failure != nil }
    XCTAssertEqual(coordinator.session?.item.id, "e1")
    XCTAssertNil(viewModel.episodePanelRequest)
    coordinator.endCurrentSession()
  }

  func testPartialSeasonCatalogIsNotTreatedAsTheWholeSeries() async throws {
    // 详情说有 2 季，MoviePilot 的季目录只给了第 1 季：看完第 1 季最后一集，不当成全剧看完从头播，说明有一季没读到；
    // 这份不完整的季目录也不交给集列表行（它自己补读、显示重试）。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true))
    viewModel.cancelForPop()
    let detail = try JSONDecoder().decode(
      MediaInfo.self, from: Data("""
        {"tmdb_id":100,"source":"themoviedb","media_id":"100","title":"长风渡","type":"电视剧",
        "number_of_seasons":2,"season_info":[{"season_number":1,"episode_count":2}]}
        """.utf8))
    let partial = MediaDetailViewModel(detail: detail, apiService: service)
    defer { partial.cancelForPop() }
    partial.applyFullDetail(detail)
    try await waitUntil { partial.seriesPlayAction != nil }
    guard case .explain? = partial.seriesPlayAction?.action else {
      return XCTFail("不从头播：\(String(describing: partial.seriesPlayAction?.action))")
    }
    XCTAssertNil(partial.episodeSeasons)
  }

  func testAnUnrelatedSlowSeasonDoesNotDelayTheNextEpisode() async throws {
    // 看完第 1 季第 1 集，集列表就能定下一集是第 1 季第 2 集；服务器上接着看的那份在第 20 季，第 20 季的集列表很慢：
    // 不等它，先定下结论。
    let show = Self.manySeasons(30)
    let slow = "/api/v1/tmdb/100/20"
    let gate = DispatchSemaphore(value: 0)
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 101, played: true),
      Self.watchedEpisode("far", season: 20, episode: 1, tmdb: 2001), seasonInfo: show.seasonInfo
    ) {
      $0.tmdbEpisodes = show.lists
      $0.tmdbEpisodesGates[slow] = gate
    }
    defer {
      gate.signal()
      viewModel.cancelForPop()
    }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(viewModel.seriesPlayAction?.action, .openEpisode)
    XCTAssertEqual(viewModel.episodeRowHint?.tmdbEpisodeID, 102)
  }

  func testContinueDoesNotResumeAServerFileCarryingAnotherTMDBEpisodeID() async throws {
    // MoviePilot 的第 1 季第 2 集是 TMDB 单集 12；Emby 上标着第 1 季第 2 集、看到一半的文件带的是 999（别的集）。
    // 「继续播放」不能直接续播这份文件，打开第 2 集的面板。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800))
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(viewModel.seriesPlayAction?.action, .openEpisode)
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
    viewModel.cancelForPop()
  }

  func testContinueResumesTheEpisodeTheServerFileIDPointsToInAnotherSeason() async throws {
    // Emby 按别的顺序分季：标着第 1 季第 2 集、看到一半的文件带的是默认顺序第 2 季第 2 集（22）的编号。
    // 这份文件就是那一集，接着看它，不按同号映射成第 1 季第 2 集（12）。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 22, position: 1800), withSeason2: true)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .play(.episode(let queued, _))? = viewModel.seriesPlayAction?.action else {
      return XCTFail("按集续播：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertEqual(queued.episode.tmdbEpisodeID, 22)
    XCTAssertEqual(queued.preferredFile, ServerFileRef(server: "emby", itemID: "e2"), "先试有续播点的这份")
    XCTAssertNotNil(viewModel.seriesPlayAction?.progress)
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 2, tmdbEpisodeID: 22, episodeNumber: 2))
    viewModel.cancelForPop()
  }

  func testContinueResumesTheServerFileWhoseIDMayBeInAnUnreadSeason() async throws {
    // 看到一半的那份带的编号（22）不在第 1 季，第 2 季没读到：编号可能就在第 2 季，没有反证。
    // 接着播这份（按钮不写集号），不当成第 1 季第 2 集，也不替用户改播第 1 季第 2 集的另一份。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 22, position: 1800),
      Self.watchedEpisode("e2b", episode: 2, tmdb: 12), withSeason2: true, season2Readable: false)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e2")
    XCTAssertEqual(viewModel.seriesPlayAction?.accessibilityLabel, "继续播放")
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 1))
    viewModel.cancelForPop()
  }

  func testHeaderPlayPressedBeforeWatchProgressLoadsFollowsTheContinueDecision() async throws {
    // 观看进度还没读完时按头部「播放」：不按服务器的观看记录直接播看到一半的那份（编号 999，不是第 2 集），
    // 先显示正在准备播放，读完按结论打开第 2 集的面板。
    let gate = DispatchSemaphore(value: 0)
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
    ) {
      $0.episodesGates[Self.lan] = gate
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    XCTAssertNil(viewModel.seriesPlayAction, "观看进度还没读完")
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    XCTAssertTrue(coordinator.isResolving, "先显示正在准备播放")

    for _ in 0..<20 { gate.signal() }
    try await waitUntil { viewModel.episodePanelRequest != nil }
    XCTAssertEqual(viewModel.episodePanelRequest?.hint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
    try await waitUntil { !coordinator.isBusy }
    XCTAssertNil(coordinator.session, "不播编号对不上的那份")
    viewModel.cancelForPop()
  }

  func testHeaderPlayPressedWhileWatchProgressRereadsWaitsForTheNewDecision() async throws {
    // 上次读到的是「没看过」（整剧播放）。在 Emby App 里看了一部分编号 999 的那份再回来，重读还没完时按「播放」：
    // 不按上次的结论整剧播放（那会直接续播 999 那份），等这次读完，按结论打开第 2 集的面板。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11),
      Self.watchedEpisode("e2", episode: 2, tmdb: 999)
    ) {
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "播放", "没看过：从第 1 集按集播放")

    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.episodesGates[Self.lan] = gate
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800))
    }
    let coordinator = service.sessionScope.playbackCoordinator
    let reads = PlaybackURLProtocol.stub.requests().count
    coordinator.noteEnteredBackground()
    coordinator.refreshWatchStateAfterReturningToForeground()
    try await waitUntil { PlaybackURLProtocol.stub.requests().count > reads }
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "播放", "重读还没完，按钮还是上一次的")
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    XCTAssertTrue(coordinator.isResolving, "等这次读完")

    for _ in 0..<20 { gate.signal() }
    try await waitUntil { viewModel.episodePanelRequest != nil }
    XCTAssertEqual(viewModel.episodePanelRequest?.hint, EpisodeRowHint(season: 1, tmdbEpisodeID: 12, episodeNumber: 2))
    try await waitUntil { !coordinator.isBusy }
    XCTAssertNil(coordinator.session, "不播编号对不上的那份")
    viewModel.cancelForPop()
  }

  // MARK: 「继续播放」对到集列表的每种情况（见 `MediaDetailViewModel.ServerFilePlacement`）

  func testContinueResumesAServerFileWhoseIDMatchesNoEpisodeWithoutAnEpisodeNumber() async throws {
    // 看到一半的「第 1 季第 20 集」带的编号（999）MoviePilot 哪一季都没有，第 1 季又只有 2 集：对不到任何一集，
    // 但也没有反证（TMDB 集列表可能还没更新到）。接着播这份，按钮不写集号，不以集列表里某一集的名义播。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e20", episode: 20, tmdb: 999, position: 1800))
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e20")
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "继续播放")
    XCTAssertEqual(viewModel.seriesPlayAction?.accessibilityLabel, "继续播放")
    XCTAssertEqual(viewModel.seriesPlayAction?.progress ?? 0, 0.25, accuracy: 0.001)
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 1), "集列表不指向哪一集")
    viewModel.cancelForPop()
  }

  func testContinueResumesAServerFileWhoseIDMayBeInAnUnreadSeason() async throws {
    // 同上，但第 2 季没读到：编号可能在那一季，同样没有反证，接着播这份。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e20", episode: 20, tmdb: 999, position: 1800), withSeason2: true, season2Readable: false)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e20")
    viewModel.cancelForPop()
  }

  func testContinueExplainsWhenTheWatchedEpisodeMatchesNoEpisodeAndNothingFollows() async throws {
    // 看完的「第 1 季第 20 集」对不到集列表，服务器上也没有接着看的那份：没法确定下一集，说明原因，不从头。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e20", episode: 20, tmdb: 999, played: true))
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .explain(let message)? = viewModel.seriesPlayAction?.action else {
      return XCTFail("说明原因：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertTrue(message.contains("看完的那一集对不上集列表"), message)

    // 按下时不用缓存重读一次（情况可能变了），仍对不上就照样说明。
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.notice != nil }
    XCTAssertEqual(coordinator.notice?.message, message)
    try await waitUntil { !coordinator.isBusy }
    XCTAssertNil(coordinator.session)
    viewModel.cancelForPop()
  }

  func testContinueResumesAnUnnumberedServerFileWhoseEpisodeIsNotInTheListYet() async throws {
    // 没有单集编号、集号也不在集列表里（TMDB 还没更新到刚播出的一集）：没有反证，接着播这份，不打断观看。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      #"{"Id":"e3","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":3,"RunTimeTicks":\#(Self.twoHours),"UserData":{"PlaybackPositionTicks":18000000000}}"#)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e3")
    viewModel.cancelForPop()
  }

  func testContinueResumesTheServerFileWhenTheEpisodeListCannotBeRead() async throws {
    // MoviePilot 的集列表读不到：没法核对、也没有反证，接着播这份。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800)
    ) { $0.tmdbEpisodes = [:] }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e2")
    viewModel.cancelForPop()
  }

  func testContinuePlaysTheNextServerFileWhenTheEpisodeListCannotBeRead() async throws {
    // 同上，看完第 1 集、服务器上接着看的是第 2 集：没有反证，播第 2 集（按钮不写集号）。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12)
    ) { $0.tmdbEpisodes = [:] }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e2")
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "播放")
    viewModel.cancelForPop()
  }

  func testContinuePlaysANewServerEpisodeTheListDoesNotHaveYet() async throws {
    // 集列表只有第 1、2 集，第 2 集看完了；Emby 上第 3 集刚入库、TMDB 还没更新到：播第 3 集，不从第 1 集重来。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true),
      #"{"Id":"e3","Type":"Episode","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":3,"RunTimeTicks":\#(Self.twoHours),"UserData":{"Played":false,"PlaybackPositionTicks":0}}"#)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(Self.judgedServerFileID(viewModel), "e3")
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "播放")
    viewModel.cancelForPop()
  }

  func testContinuePublishesTheSeasonCatalogItDecidedWith() async throws {
    // 详情缓存里只有第 1 季，MoviePilot 已经有第 2 季：看完第 1 季，下一集第 2 季第 1 集服务器上没有，打开它的面板。
    // 集列表行要能显示第 2 季：发布「继续播放」用的季目录，里面有第 2 季。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true),
      seasonInfo: #"[{"season_number":1,"episode_count":2}]"#
    ) {
      $0.mediaSeasons = #"[{"season_number":1,"episode_count":2},{"season_number":2,"episode_count":2}]"#
      $0.tmdbEpisodes["/api/v1/tmdb/100/2"] = Self.twoEpisodeSeason2
    }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(viewModel.seriesPlayAction?.action, .openEpisode)
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 2, tmdbEpisodeID: 21, episodeNumber: 1))
    XCTAssertEqual(viewModel.episodeSeasons?.compactMap(\.season_number), [1, 2])
    viewModel.cancelForPop()
  }

  func testHeaderPlayRetriesAnExplainedDecisionWithFreshLists() async throws {
    // 集列表读不到、服务器上也没有接着看的那份：说明原因。之后集列表能读了，再按「播放」不只重复上次的说明：
    // 不用缓存重读（空列表也会被缓存），按新结论从第 1 集开始播。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true)
    ) {
      $0.tmdbEpisodes = ["/api/v1/tmdb/100/1": "[]"]
      $0.items["\(Self.lan)|e1"] = Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .explain? = viewModel.seriesPlayAction?.action else {
      return XCTFail("说明原因：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    PlaybackURLProtocol.stub.configure { $0.tmdbEpisodes["/api/v1/tmdb/100/1"] = Self.twoEpisodeSeason1 }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.session != nil || coordinator.notice != nil || coordinator.failure != nil }
    XCTAssertNil(coordinator.notice, "不重复上次的说明")
    XCTAssertEqual(coordinator.session?.item.id, "e1")
    coordinator.endCurrentSession()
    viewModel.cancelForPop()
  }

  /// 「继续播放」按服务器上的哪一份播（带着判断时读到的这份，起播时核对编号，见 `PlaybackTarget.seriesFile`）；
  /// 不是按服务器上的一份播时为 nil。
  private static func judgedServerFileID(_ viewModel: MediaDetailViewModel) -> String? {
    guard case .play(.seriesFile(let server, let judgement, let tmdbID))? = viewModel.seriesPlayAction?.action,
      server == "emby", tmdbID == 100
    else { return nil }
    return judgement.file?.id
  }

  /// 一部 `count` 季的剧：每季两集，第 n 季第 k 集是 TMDB n*100+k。
  private static func manySeasons(_ count: Int) -> (seasonInfo: String, lists: [String: String]) {
    let info = (1...count).map { #"{"season_number":\#($0),"episode_count":2}"# }.joined(separator: ",")
    var lists: [String: String] = [:]
    for season in 1...count {
      lists["/api/v1/tmdb/100/\(season)"] =
        "[" + (1...2).map { #"{"id":\#(season * 100 + $0),"season_number":\#(season),"episode_number":\#($0)}"# }
        .joined(separator: ",") + "]"
    }
    return ("[\(info)]", lists)
  }

  private static func seasonListRequests() -> [String] {
    PlaybackURLProtocol.stub.requests().map(\.url.path).filter { $0.hasPrefix("/api/v1/tmdb/100/") }
  }

  func testContinueReadsOnlyTheSeasonsItNeeds() async throws {
    // 30 季的剧，接着看第 12 季第 1 集到一半：只读第 12 季的集列表，不等其他 29 季。
    let show = Self.manySeasons(30)
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e", season: 12, episode: 1, tmdb: 1201, position: 1800), seasonInfo: show.seasonInfo
    ) { $0.tmdbEpisodes = show.lists }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .play(.episode(let queued, _))? = viewModel.seriesPlayAction?.action else {
      return XCTFail("接着看第 12 季第 1 集：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertEqual(queued.episode.tmdbEpisodeID, 1201)
    XCTAssertEqual(Set(Self.seasonListRequests()), ["/api/v1/tmdb/100/12"])
    viewModel.cancelForPop()
  }

  func testContinueDoesNotReadSeasonsForAServerFileTheDecisionIgnores() async throws {
    // 30 季的剧，看完第 1 季第 1 集，集列表的下一集是第 1 季第 2 集；Emby 上接着看的那份标着第 1 季第 2 集，
    // 单集编号却是第 25 季第 1 集。以集列表为准：只读先读的第 1、2 季，不为服务器上那份去找第 25 季。
    let show = Self.manySeasons(30)
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 101, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 2501), seasonInfo: show.seasonInfo
    ) { $0.tmdbEpisodes = show.lists }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    XCTAssertEqual(viewModel.episodeRowHint?.season, 1)
    XCTAssertEqual(viewModel.episodeRowHint?.tmdbEpisodeID, 102)
    XCTAssertEqual(Set(Self.seasonListRequests()), ["/api/v1/tmdb/100/1", "/api/v1/tmdb/100/2"])
    viewModel.cancelForPop()
  }

  func testContinueStopsReadingSeasonListsAtTheLimit() async throws {
    // 100 季的剧，接着看到一半的那份带的单集编号哪一季都没有（要找遍所有季才知道）：最多读上限那么多季，
    // 剩下的当成没读到，照常续播这份（没有反证），不一下子读 100 季。
    let show = Self.manySeasons(100)
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e", season: 50, episode: 1, tmdb: 999_999, position: 1800), seasonInfo: show.seasonInfo
    ) { $0.tmdbEpisodes = show.lists }
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard let itemID = Self.judgedServerFileID(viewModel) else {
      return XCTFail("照常续播这份：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertEqual(itemID, "e")
    let reads = Self.seasonListRequests()
    XCTAssertEqual(reads.count, MediaDetailViewModel.continuationSeasonReadLimit, "\(reads)")
    // 离第 50 季近的先读。
    XCTAssertTrue(reads.contains("/api/v1/tmdb/100/50") && reads.contains("/api/v1/tmdb/100/45"), "\(reads)")
    XCTAssertFalse(reads.contains("/api/v1/tmdb/100/1"), "\(reads)")
    viewModel.cancelForPop()
  }

  func testContinueDoesNotWaitForASeasonThatHasNoEpisodesYet() async throws {
    // TMDB 已公布第 2 季、但还一集都没有（episode_count 为 0，集列表本来就是空的）：看完第 1 季不当成第 2 季没读到，
    // 按全看完从头播。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true),
      seasonInfo: #"[{"season_number":1,"episode_count":2},{"season_number":2,"episode_count":0}]"#)
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .play(.episode(let queued, _))? = viewModel.seriesPlayAction?.action else {
      return XCTFail("从头播第 1 集：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertEqual(queued.episode.tmdbEpisodeID, 11)
    XCTAssertEqual(viewModel.seriesPlayAction?.title, "播放")
    viewModel.cancelForPop()
  }

  func testContinueIsRecomputedWhenBackgroundVerificationChangesTheEpisodeIndex() async throws {
    // 起播后台核对完（集对应可能变了）：集卡片会跟着变，「继续播放」也重读重算，不停在旧结论上。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800), withSeason2: true)
    try await waitUntil { viewModel.seriesPlayAction?.progress != nil }
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true))
    }
    service.sessionScope.playbackCoordinator.evidenceChanged(100)
    try await waitUntil { viewModel.seriesPlayAction?.action == .openEpisode }
    XCTAssertEqual(viewModel.episodeRowHint, EpisodeRowHint(season: 2, tmdbEpisodeID: 21, episodeNumber: 1))
    viewModel.cancelForPop()
  }

  func testContinueIsRecomputedWhenTheEpisodeRowForcesARecheck() async throws {
    // 集列表行按了重试（强制重读集索引）：「继续播放」也按新的集索引重算，头部和卡片不各说各的。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800), withSeason2: true)
    try await waitUntil { viewModel.seriesPlayAction?.progress != nil }
    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true))
    }
    let context = try XCTUnwrap(
      viewModel.episodePlayback?.context(media: viewModel.detail, episodeGroup: nil, seasons: [1, 2]))
    _ = await service.sessionScope.playbackCoordinator.episodeAvailability(
      for: [], context: context, forceRefresh: true)
    try await waitUntil { viewModel.seriesPlayAction?.action == .openEpisode }
    viewModel.cancelForPop()
  }

  func testReadStartedBeforePlaybackEndsDoesNotWriteBackTheOldDecision() async throws {
    // 播放器关闭前开始的那次读取晚到：读到的是写回之前的观看记录，不能把结论写回来，等写回发完后的重读。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800), withSeason2: true)
    try await waitUntil { viewModel.seriesPlayAction?.progress != nil }
    let coordinator = service.sessionScope.playbackCoordinator
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.episodesGates[Self.lan] = gate
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true))
    }
    let reads = PlaybackURLProtocol.stub.requests().count
    coordinator.evidenceChanged(100)
    try await waitUntil { PlaybackURLProtocol.stub.requests().count > reads }
    let change = WatchStateChange(tmdbID: 100, itemIDs: ["e2", "s1"])
    coordinator.watchStateChanging.send(change)
    for _ in 0..<20 { gate.signal() }
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNotNil(viewModel.seriesPlayAction?.progress, "晚到的那次读取不写回")

    PlaybackURLProtocol.stub.configure { $0.episodesGates[Self.lan] = nil }
    coordinator.watchStateUpdates.send(change)
    try await waitUntil { viewModel.seriesPlayAction?.action == .openEpisode }
    viewModel.cancelForPop()
  }

  // MARK: 头部「播放」只按这一次读出的结论做

  func testHeaderPlayPressedWhileRereadingIgnoresTheOldContinueAction() async throws {
    // 上次的结论是续播第 1 季第 2 集。在 Emby App 里看完它再回来，重读还没完时按「播放」：不按旧结论播第 2 集，
    // 等这次读完：下一集第 2 季第 1 集服务器上没有，打开它的面板。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800), withSeason2: true
    ) {
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.seriesPlayAction?.progress != nil }

    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure {
      $0.episodesGates[Self.lan] = gate
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 12, played: true))
    }
    let coordinator = service.sessionScope.playbackCoordinator
    let reads = PlaybackURLProtocol.stub.requests().count
    coordinator.noteEnteredBackground()
    coordinator.refreshWatchStateAfterReturningToForeground()
    try await waitUntil { PlaybackURLProtocol.stub.requests().count > reads }
    XCTAssertNotNil(viewModel.seriesPlayAction?.progress, "重读还没完，按钮还是上一次的")
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    XCTAssertTrue(coordinator.isResolving, "等这次读完")

    for _ in 0..<20 { gate.signal() }
    try await waitUntil { viewModel.episodePanelRequest != nil }
    XCTAssertEqual(viewModel.episodePanelRequest?.hint, EpisodeRowHint(season: 2, tmdbEpisodeID: 21, episodeNumber: 1))
    try await waitUntil { !coordinator.isBusy }
    XCTAssertNil(coordinator.session, "不按旧结论重播看完的第 2 集")
    viewModel.cancelForPop()
  }

  func testHeaderPlayWaitingForTheDecisionStopsWhenThePageIsPopped() async throws {
    // 等结论时页面被外部导航（Top Shelf）弹出：不在出栈的页面上重读，也不起播、不报错。
    let gate = DispatchSemaphore(value: 0)
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800)
    ) {
      $0.episodesGates[Self.lan] = gate
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    XCTAssertTrue(coordinator.isResolving)
    let episodeReads = { PlaybackURLProtocol.stub.requests().filter { $0.url.path.hasSuffix("/Episodes") }.count }
    viewModel.cancelForPop()
    let reads = episodeReads()
    for _ in 0..<20 { gate.signal() }
    try await waitUntil { !coordinator.isBusy }
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(episodeReads(), reads, "不再重读")
    XCTAssertNil(coordinator.session)
    XCTAssertNil(coordinator.failure)
  }

  func testHeaderPlayDoesNotFallBackToTheWholeSeriesWhenWatchProgressCannotBeRead() async throws {
    // 观看进度读了两次都读不到：不整剧播放（那会按服务器的观看记录直接播、不核对单集），说明原因。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
    ) {
      $0.episodesStatus["\(Self.lan)|s1"] = 500
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    try await waitUntil { coordinator.failure != nil }
    XCTAssertTrue(coordinator.failure?.message.contains("读不到这部剧在媒体服务器上的观看记录") == true)
    XCTAssertFalse(coordinator.isBusy)
    XCTAssertNil(coordinator.session)
    viewModel.cancelForPop()
  }

  func testHeaderPlayPressedBeforeWatchProgressLoadsStartsTheDecidedEpisode() async throws {
    // 同上，读完的结论是按集续播第 2 集：等到结论后直接起播，播的是有续播点的那份。
    let gate = DispatchSemaphore(value: 0)
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800)
    ) {
      $0.episodesGates[Self.lan] = gate
      $0.items["\(Self.lan)|e2"] = Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800)
      $0.playbackInfo = Self.playbackInfo()
    }
    try await waitUntil { viewModel.inAppPlaybackTarget != nil }
    let coordinator = service.sessionScope.playbackCoordinator
    viewModel.playFromHeader(try XCTUnwrap(viewModel.inAppPlaybackTarget))
    XCTAssertTrue(coordinator.isResolving)

    for _ in 0..<20 { gate.signal() }
    try await waitUntil { coordinator.session != nil }
    XCTAssertEqual(coordinator.session?.item.id, "e2")
    XCTAssertEqual(coordinator.session?.episode?.episode.tmdbEpisodeID, 12, "按集起播，能接着播下一集")
    coordinator.endCurrentSession()
    viewModel.cancelForPop()
  }

  func testContinuePlaysTheMatchedEpisodeFromItsOwnCopyWhenTheResumedFileIsAnotherEpisode() async throws {
    // 看到一半的那份带的编号（999）MoviePilot 哪一季都没有；同号的第 2 集（12）在另一份文件上确定能播：播第 2 集，
    // 不先试编号对不上的那份（试不到还会重建集索引），按钮也不显示它的进度。
    let (viewModel, _) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 999, position: 1800),
      Self.watchedEpisode("e2b", episode: 2, tmdb: 12))
    try await waitUntil { viewModel.seriesPlayAction != nil }
    guard case .play(.episode(let queued, _))? = viewModel.seriesPlayAction?.action else {
      return XCTFail("按集播放第 2 集：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertEqual(queued.episode.tmdbEpisodeID, 12)
    XCTAssertNil(queued.preferredFile)
    XCTAssertNil(viewModel.seriesPlayAction?.progress)
    XCTAssertEqual(viewModel.seriesPlayAction?.accessibilityLabel, "播放 第 1 季第 2 集")
    viewModel.cancelForPop()
  }

  func testDetailPageRereadsWatchProgressAfterReturningFromAnotherApp() async throws {
    // 在详情页打开 Emby App 看了一部分第 2 集，回来时「继续播放」和集索引里的进度要跟着变。
    let (viewModel, service) = try makeContinueWatchingDetailViewModel(
      Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
      Self.watchedEpisode("e2", episode: 2, tmdb: 12))
    try await waitUntil { viewModel.seriesPlayAction != nil }
    let coordinator = service.sessionScope.playbackCoordinator
    let context = try XCTUnwrap(
      viewModel.episodePlayback?.context(media: viewModel.detail, episodeGroup: nil, seasons: [1]))
    let episodes = MoviePilotEpisode.list(
      try JSONDecoder().decode([TmdbEpisode].self, from: Data(Self.twoEpisodeSeason1.utf8)), season: 1)
    func cardProgress() async -> Double?? {
      await coordinator.episodePlaybackLookup(for: episodes, context: context)?.watchProgress.last
    }
    if case .play(.episode)? = viewModel.seriesPlayAction?.action {} else {
      XCTFail("看完第 1 集，按集播放第 2 集：\(String(describing: viewModel.seriesPlayAction?.action))")
    }
    XCTAssertNil(viewModel.seriesPlayAction?.progress)
    // 集卡片读过一次（集索引进了缓存；「继续播放」用的那份只在它自己的判断里用，不进缓存）。
    _ = await cardProgress()

    PlaybackURLProtocol.stub.configure {
      $0.episodes["\(Self.lan)|s1"] = Self.embyEpisodes(
        Self.watchedEpisode("e1", episode: 1, tmdb: 11, played: true),
        Self.watchedEpisode("e2", episode: 2, tmdb: 12, position: 1800))
    }
    let cached = await cardProgress()
    XCTAssertEqual(cached, .some(nil), "集索引还在缓存里，第 2 集卡片仍是读到的旧进度")
    // 只是短暂不活跃（没进后台）不重读。
    coordinator.refreshWatchStateAfterReturningToForeground()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertNil(viewModel.seriesPlayAction?.progress)

    coordinator.noteEnteredBackground()
    coordinator.refreshWatchStateAfterReturningToForeground()
    try await waitUntil { viewModel.seriesPlayAction?.progress != nil }
    XCTAssertEqual(viewModel.seriesPlayAction?.accessibilityLabel.hasPrefix("继续播放"), true)
    let refreshed = await cardProgress()
    XCTAssertNotNil(refreshed ?? nil, "集索引已作废，第 2 集卡片拿到新的进度")
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
  /// 跳转本身要等播放器就绪才发，测试里播放器打不开测试地址，只能断言跳转上限读的那个值（`MediaSession.item.runtime`）。
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
    // 起播后播放器读出的时长经 `runtime` 给出（测试里播放器打不开测试地址，读不到时长，取值顺序见 `PlaybackDuration` 的测试）。
    // 播放器的失败与这里无关，接住免得结束会话。
    session.onFailure = { _ in }
    let reporter = coordinator.reporterForTesting
    screen.start()
    let playing = try XCTUnwrap(screen.playbackItem)
    XCTAssertEqual(playing.baseItem.runtime, .seconds(10_800), "选集里的当前一集按这份显示")
    let info = try XCTUnwrap(
      VideoPlayerSupplementType.info.makeSupplement(for: playing, queue: nil, chapters: screen.chapters)
        as? MediaInfoSupplement)
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

  /// 播放界面上的章节：「章节」面板（不显示时为 nil）和进度条刻度读的章节。
  @MainActor
  private struct ShownChapters {
    let panel: MediaChaptersSupplement?
    let slider: [ChapterInfo]

    init(_ screen: MediaSession) throws {
      let playing = try XCTUnwrap(screen.playbackItem)
      panel = VideoPlayerSupplementType.chapters.makeSupplement(for: playing, queue: nil, chapters: screen.chapters)
        as? MediaChaptersSupplement
      slider = screen.chapters.loaded.map(\.chapterInfo)
    }
  }

  /// 按播放界面的入口起播，读出播放器读完文件前、后（交来 `embedded`）的章节。
  /// 测试里播放器打不开测试地址、读不到文件，由测试交来它读到的内嵌章节；片长按片源或条目的。
  private func playerChapters(
    _ coordinator: PlaybackCoordinator, _ session: PlaybackSession, embedded: [ServerChapter] = []
  ) async throws -> (beforeRead: ShownChapters, afterRead: ShownChapters) {
    session.onFailure = { _ in }
    let reporter = coordinator.reporterForTesting
    let screen = MediaSession(session: session, onExit: { _ in }, onSwitchItem: { _, _, _, _, completion in completion(.discarded) })
    screen.start()
    let before = try ShownChapters(screen)
    screen.embeddedChaptersDidLoad(embedded)
    let after = try ShownChapters(screen)
    screen.stop()
    coordinator.endCurrentSession()
    await reporter.waitForQueued()
    return (before, after)
  }

  private func configureMovie(playbackInfo: String) {
    PlaybackURLProtocol.stub.reset()
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = ["lan.playback-tests.local|m1": Self.movie()]
      $0.playbackInfo = playbackInfo
    }
  }

  private func movieChapters(
    sourceRuntime: String = "", chapters: String = "[]", embedded: [ServerChapter] = []
  ) async throws -> (beforeRead: ShownChapters, afterRead: ShownChapters) {
    configureMovie(
      playbackInfo:
        #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","ItemId":"m1","Container":"mkv","Protocol":"File"\#(sourceRuntime),"MediaStreams":[],"Chapters":\#(chapters)}]}"#
    )
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    return try await playerChapters(coordinator, try XCTUnwrap(coordinator.session), embedded: embedded)
  }

  /// Emby 的章节在所播版本的片源里：一起播就有，不等播放器。按起点排好，片头片尾检测的标记不算章节，
  /// 起点在片尾之后的（文件换了更短的版本、Emby 还没重新分析）不列，有截图的带上截图地址。
  func testEmbyChaptersOfThePlayedSourceShowInThePlayer() async throws {
    let shown = try await movieChapters(
      chapters: #"""
        [
          {"StartPositionTicks":13200000000,"Name":"片尾","MarkerType":"Chapter","ChapterIndex":3},
          {"StartPositionTicks":0,"Name":"片头","MarkerType":"Chapter","ChapterIndex":0},
          {"StartPositionTicks":900000000,"Name":"","MarkerType":"IntroEnd","ChapterIndex":1},
          {"StartPositionTicks":890000000,"Name":"正片","MarkerType":"Chapter","ChapterIndex":2,"ImageTag":"t2"},
          {"StartPositionTicks":108000000000,"Name":"旧版片尾","MarkerType":"Chapter","ChapterIndex":4}]
        """#)

    let chapters = try XCTUnwrap(shown.beforeRead.panel, "服务器有章节时一开始就显示").chapters
    XCTAssertFalse(try XCTUnwrap(shown.beforeRead.panel).isLoading)
    XCTAssertEqual(chapters.map(\.displayTitle), ["片头", "正片", "片尾"], "按起点排序；片头结束标记、2 小时片长之后的章节都不列")
    XCTAssertEqual(chapters.map(\.startSeconds), [.zero, .seconds(89), .seconds(1320)])
    let image = try XCTUnwrap(chapters[1].imageSource?.url)
    XCTAssertEqual(image.path, "/Items/m1/Images/Chapter/2", "截图按 Emby 给的章节序号取")
    XCTAssertEqual(URLComponents(url: image, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "tag" }?.value, "t2")
    XCTAssertNil(image.query?.range(of: "api_key"), "图片地址不带密钥")
    XCTAssertNil(chapters[0].imageSource, "没有截图的章节不带地址，卡片显示占位图标")
    XCTAssertEqual(chapters[0].systemImage, AppSymbol.movie)
    XCTAssertEqual(shown.beforeRead.slider.map(\.name), ["片头", "正片", "片尾"], "进度条的章节刻度和面板同一份")
    XCTAssertEqual(
      shown.afterRead.panel?.chapters.map(\.displayTitle), ["片头", "正片", "片尾"],
      "播放器读到的内嵌章节不替换服务器的")
  }

  /// 老版本 Emby 不给 `ChapterIndex`、片源也不给 `ItemId`：截图序号按章节在服务器列表里的位置（读不出的条目也占位），
  /// 只有一个版本时截图挂在正在播的条目上。
  func testChapterImagesWithoutIndexOrItemIDFallBackToListPositionAndPlayedItem() async throws {
    configureMovie(
      playbackInfo: #"""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mkv","Protocol":"File","MediaStreams":[],"Chapters":[
          {"StartPositionTicks":0,"Name":"一"},null,
          {"StartPositionTicks":6000000000,"Name":"二","ImageTag":"t"}]}]}
        """#)
    let coordinator = makeCoordinator(makeService())
    await run(coordinator, .serverItem(serverName: "emby", itemID: "m1"))
    let shown = try await playerChapters(coordinator, try XCTUnwrap(coordinator.session))
    let chapters = try XCTUnwrap(shown.beforeRead.panel).chapters
    XCTAssertEqual(chapters.map(\.displayTitle), ["一", "二"])
    XCTAssertEqual(chapters[1].imageSource?.url?.path, "/Items/m1/Images/Chapter/2")
  }

  /// 服务器没有章节：「章节」先转圈，等播放器读完文件。文件里有章节就用，没有就按片长每 10 分钟分一段。
  func testWithoutServerChaptersThePlayerWaitsForEmbeddedChaptersThenSplitsEveryTenMinutes() async throws {
    let embedded = try await movieChapters(embedded: [
      ServerChapter(name: "序幕", startSeconds: 0), ServerChapter(name: nil, startSeconds: 1800),
      ServerChapter(name: "终章", startSeconds: 5400),
    ])
    let waiting = try XCTUnwrap(embedded.beforeRead.panel, "播放器读完文件前就显示「章节」，告诉用户会有章节")
    XCTAssertTrue(waiting.isLoading)
    XCTAssertTrue(waiting.chapters.isEmpty, "转圈时还没有章节")
    XCTAssertTrue(embedded.beforeRead.slider.isEmpty)
    let fromFile = try XCTUnwrap(embedded.afterRead.panel)
    XCTAssertFalse(fromFile.isLoading)
    XCTAssertEqual(fromFile.chapters.map(\.displayTitle), ["序幕", "章节 2", "终章"], "文件里没写名字的按位置命名")
    XCTAssertEqual(embedded.afterRead.slider.count, 3)

    // 文件里也没有：2 小时按 10 分钟分 12 段，没有截图。
    let none = try await movieChapters()
    let split = try XCTUnwrap(none.afterRead.panel).chapters
    XCTAssertEqual(split.count, 12)
    XCTAssertEqual(split.prefix(3).map(\.displayTitle), ["章节 1", "章节 2", "章节 3"])
    XCTAssertEqual(split.last?.startSeconds, .seconds(6600))
    XCTAssertTrue(split.allSatisfy { $0.imageSource == nil && $0.systemImage == AppSymbol.movie }, "没有截图，显示电影图标")

    // 服务器只给了一个章节：没有可跳的位置，按没有章节处理。
    let single = try await movieChapters(chapters: #"[{"StartPositionTicks":0,"Name":"Chapter 1","MarkerType":"Chapter"}]"#)
    XCTAssertTrue(try XCTUnwrap(single.beforeRead.panel).isLoading, "一个章节不算有章节，等播放器")
    XCTAssertEqual(try XCTUnwrap(single.afterRead.panel).chapters.count, 12)
  }

  /// 自动分段的边界：片尾不足 1 分钟并进前一段，恰好 1 分钟的单独成段；只分得出一段、片长离谱时都不分，「章节」随之消失。
  func testGeneratedChaptersMergeAShortTailAndSkipTooShortOrBrokenDurations() async throws {
    // 20 分 30 秒：0、10 分各一段，最后 30 秒并进第 2 段。
    let tailShown = try await movieChapters(sourceRuntime: #","RunTimeTicks":12300000000"#)
    let tail = try XCTUnwrap(tailShown.afterRead.panel)
    XCTAssertEqual(tail.chapters.map(\.startSeconds), [.zero, .seconds(600)])

    // 11 分、21 分：最后一段恰好 1 分钟，不并。
    let elevenShown = try await movieChapters(sourceRuntime: #","RunTimeTicks":6600000000"#)
    XCTAssertEqual(try XCTUnwrap(elevenShown.afterRead.panel).chapters.map(\.startSeconds), [.zero, .seconds(600)])
    let twentyOneShown = try await movieChapters(sourceRuntime: #","RunTimeTicks":12600000000"#)
    XCTAssertEqual(
      try XCTUnwrap(twentyOneShown.afterRead.panel).chapters.map(\.startSeconds), [.zero, .seconds(600), .seconds(1200)])

    let short = try await movieChapters(sourceRuntime: #","RunTimeTicks":6500000000"#)
    XCTAssertNotNil(short.beforeRead.panel, "读完前不知道文件里有没有章节")
    XCTAssertNil(short.afterRead.panel, "10 分 50 秒只分得出一段，不显示「章节」")
    XCTAssertTrue(short.afterRead.slider.isEmpty, "进度条也不画刻度")

    // 1 万小时：超过 500 段的上限，当作坏片长。
    let broken = try await movieChapters(sourceRuntime: #","RunTimeTicks":360000000000000"#)
    XCTAssertNil(broken.afterRead.panel)
  }

  /// 没有截图的章节：剧集显示电视图标（电影的见上面的用例）。
  func testEpisodeChaptersWithoutImagesUseTheTVSymbol() async throws {
    let coordinator = makeCoordinator(makeService())
    let session = try await startEpisodeSession(
      coordinator,
      playbackInfo:
        #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"mkv","Protocol":"File","RunTimeTicks":15000000000,"MediaStreams":[]}]}"#
    )
    let episode = try await playerChapters(coordinator, session)
    let episodeChapters = try XCTUnwrap(episode.afterRead.panel).chapters
    XCTAssertEqual(episodeChapters.count, 3)
    XCTAssertTrue(episodeChapters.allSatisfy { $0.systemImage == AppSymbol.tv })
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
  /// 模拟播放器发来属于当前这次载入的事件。
  func handleCurrent(_ event: AetherPlayer.Event) {
    handle(event, generation: makePlayer().generation)
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
    /// 读这部剧的集（`/Episodes`）成功这么多次后，之后每次都回 500；nil 时不限。
    var successfulEpisodeReadsBeforeFailure: Int?
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
    /// 卡住这些集列表路径的回复，放开（或 10 秒）后才回。
    var tmdbEpisodesGates: [String: DispatchSemaphore] = [:]
    /// MoviePilot 整理记录（`/api/v1/history/transfer`）的 `list`，不论查什么都回它；nil 时回 404。
    var transferHistory: String?
    /// 按查询回整理记录：`title|page` → `data`（`{"list":[…],"total":…}`）。不为空时优先，没列出的查询回空的一页。
    var transferHistoryPages: [String: String] = [:]
    /// MoviePilot `/api/v1/media/seasons`（默认顺序的季列表）；nil 时回 404。
    var mediaSeasons: String?
    /// 卡住 `/api/v1/media/seasons` 的回复
    var mediaSeasonsGate: DispatchSemaphore?
    /// MoviePilot 媒体详情（`/api/v1/media/{id}`）：路径 → 详情 JSON；没列出的回 404。
    var mediaDetails: [String: String] = [:]
    /// 卡住 MoviePilot 媒体详情的查询
    var mediaDetailGate: DispatchSemaphore?
    /// MoviePilot `/mediaserver/exists` 的回包
    var mediaServerExists = #"{"success":true,"data":{"item":{}}}"#
    /// host → Emby `Library/SelectableMediaFolders` 的回包（没有时是空数组）
    var mediaFolders: [String: String] = [:]
    /// host → Emby 媒体库列表（顶层数组）。默认由 `Library/VirtualFolders/Query` 包在 `Items` 里回；没有时 404：媒体库配置读不到。
    var virtualFolders: [String: String] = [:]
    /// 这些 host 是旧版 Emby：没有 `Query` 接口，只有 `Library/VirtualFolders`。
    var legacyVirtualFolders: Set<String> = []
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
    var response = scenario
    if request.url.path.hasSuffix("/Episodes"), let host = request.url.host,
      let remaining = scenario.successfulEpisodeReadsBeforeFailure
    {
      if remaining == 0 {
        let seriesID = request.url.deletingLastPathComponent().lastPathComponent
        response.episodesStatus["\(host)|\(seriesID)"] = 500
      } else {
        scenario.successfulEpisodeReadsBeforeFailure = remaining - 1
      }
    }
    return response
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
        respond(200, episodes, after: scenario.tmdbEpisodesGates[url.path])
      } else if url.path == "/api/v1/history/transfer", !scenario.transferHistoryPages.isEmpty {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let title = query.first { $0.name == "title" }?.value ?? ""
        let page = query.first { $0.name == "page" }?.value ?? ""
        let data = scenario.transferHistoryPages["\(title)|\(page)"] ?? #"{"list":[],"total":0}"#
        respond(200, #"{"success":true,"data":\#(data)}"#, after: scenario.transferHistoryGate)
      } else if url.path == "/api/v1/history/transfer", let list = scenario.transferHistory {
        respond(200, #"{"success":true,"data":{"list":\#(list),"total":null}}"#)
      } else if url.path == "/api/v1/media/seasons", let seasons = scenario.mediaSeasons {
        respond(200, seasons, after: scenario.mediaSeasonsGate)
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
    } else if path.hasSuffix("/Library/VirtualFolders/Query") {
      // 旧版 Emby 没有这个接口：回 404，客户端退回 `Library/VirtualFolders`。
      if let folders = scenario.virtualFolders[host], !scenario.legacyVirtualFolders.contains(host) {
        respond(200, #"{"Items":\#(folders),"TotalRecordCount":1}"#)
      } else {
        respond(404, "")
      }
    } else if path.hasSuffix("/Library/VirtualFolders") {
      if let folders = scenario.virtualFolders[host], scenario.legacyVirtualFolders.contains(host) {
        respond(200, folders)
      } else {
        respond(404, "")
      }
    } else if recorded.method == "GET", path.hasSuffix("/Items") {
      if let status = scenario.searchStatus[host] {
        respond(status, "{}")
        return
      }
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      if let ids = query.first(where: { $0.name == "Ids" })?.value?.split(separator: ",") {
        // 一次读多个条目：不在这台服务器上的不返回。
        let found = ids.compactMap { scenario.items["\(host)|\($0)"] }
        respond(200, #"{"Items":[\#(found.joined(separator: ","))]}"#)
        return
      }
      let keys = query.first { $0.name == "AnyProviderIdEquals" }?.value?.split(separator: ",") ?? []
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
