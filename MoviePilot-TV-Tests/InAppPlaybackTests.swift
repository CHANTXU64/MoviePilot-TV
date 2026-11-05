import XCTest

@testable import MoviePilot_TV

// MARK: - 配置与判定（纯逻辑）

final class InAppPlaybackModelTests: XCTestCase {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
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
    XCTAssertEqual(EmbyBaseURL.normalized("192.168.1.2:8096")?.absoluteString, "http://192.168.1.2:8096")
    XCTAssertEqual(
      EmbyBaseURL.normalized(" https://media.example.com/emby/ ")?.absoluteString,
      "https://media.example.com/emby")
    XCTAssertEqual(
      EmbyBaseURL.normalized("HTTPS://media.example.com/emby/?x=1#web")?.absoluteString,
      "HTTPS://media.example.com/emby")
    XCTAssertNil(EmbyBaseURL.normalized("   "))
    XCTAssertNil(EmbyBaseURL.normalized(nil))

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

  @MainActor
  func testMPVErrorLogsDropAPIKey() {
    XCTAssertEqual(
      PlaybackSession.redacted("open https://e/Videos/1/stream.mkv?Static=true&api_key=abc123&DeviceId=d failed"),
      "open https://e/Videos/1/stream.mkv?Static=true&api_key=<redacted>&DeviceId=d failed")
    XCTAssertEqual(PlaybackSession.seconds(.milliseconds(1500)), 1.5)
  }

  func testResumePolicySkipsStartAndNearEnd() {
    let twoHours: Int64 = 7200 * 10_000_000
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionTicks: 0, runTimeTicks: twoHours))
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionTicks: 59 * 10_000_000, runTimeTicks: twoHours))
    XCTAssertEqual(
      PlaybackResumePolicy.resumePosition(positionTicks: 1800 * 10_000_000, runTimeTicks: twoHours), 1800)
    XCTAssertNil(PlaybackResumePolicy.resumePosition(positionTicks: 6500 * 10_000_000, runTimeTicks: twoHours))
    XCTAssertEqual(PlaybackResumePolicy.resumePosition(positionTicks: 600 * 10_000_000, runTimeTicks: nil), 600)
    XCTAssertTrue(PlaybackResumePolicy.isCompleted(positionSeconds: 6500, runTimeTicks: twoHours))
    XCTAssertFalse(PlaybackResumePolicy.isCompleted(positionSeconds: 6400, runTimeTicks: twoHours))
    XCTAssertFalse(PlaybackResumePolicy.isCompleted(positionSeconds: 6500, runTimeTicks: nil))
    XCTAssertEqual(PlaybackResumePolicy.formatted(754), "12:34")
    XCTAssertEqual(PlaybackResumePolicy.formatted(3754), "1:02:34")
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
      return EmbyEpisodeOrder.firstEpisode(in: page.items)?.id
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
    let episode = try decode(
      EmbyItem.self,
      #"{"Id":"e","Type":"Episode","Name":"开端","SeriesName":"某剧","ParentIndexNumber":1,"IndexNumber":1}"#)
    XCTAssertEqual(episode.displayTitle, "某剧 · 第 1 季 第 1 集 · 开端")
    XCTAssertEqual(episode.playerTitles.primary, "第 1 季 第 1 集 · 开端")
    XCTAssertEqual(episode.playerTitles.secondary, "某剧")
    let movie = try decode(EmbyItem.self, #"{"Id":"m","Type":"Movie","Name":"电影名"}"#)
    XCTAssertEqual(movie.displayTitle, "电影名")
    XCTAssertNil(movie.playerTitles.secondary)

    // 集名只是占位时不重复显示。
    for placeholder in ["第1集", "第 1 集", "第一集", "第12话", "Episode 1", "EP01", "e3", "1"] {
      let item = try decode(
        EmbyItem.self,
        #"{"Id":"e","Type":"Episode","Name":"\#(placeholder)","SeriesName":"小城良方","ParentIndexNumber":1,"IndexNumber":1}"#)
      XCTAssertEqual(item.displayTitle, "小城良方 · 第 1 季 第 1 集", placeholder)
    }
    XCTAssertFalse(EmbyItem.isPlaceholderEpisodeName("第一集 重逢", episodeNumber: 1))
    // 纯数字只在等于集号时算占位，真实的数字集名保留。
    XCTAssertTrue(EmbyItem.isPlaceholderEpisodeName("03", episodeNumber: 3))
    let numbered = try decode(
      EmbyItem.self,
      #"{"Id":"e","Type":"Episode","Name":"1984","SeriesName":"某剧","ParentIndexNumber":1,"IndexNumber":3}"#)
    XCTAssertEqual(numbered.displayTitle, "某剧 · 第 1 季 第 3 集 · 1984")
    XCTAssertFalse(EmbyItem.isPlaceholderEpisodeName("12", episodeNumber: nil))
    // 没有季集号时，占位集名仍然保留，否则标题是空的。
    let bare = try decode(EmbyItem.self, #"{"Id":"e","Type":"Episode","Name":"第1集"}"#)
    XCTAssertEqual(bare.displayTitle, "第1集")
  }

  @MainActor
  func testHomeCardsOfferInAppPlaybackOnlyForAdministratorEmbyMoviesAndSeries() throws {
    func item(_ type: String, server: String, itemID: String? = "m1") throws -> MediaServerPlayItem {
      let idField = itemID.map { #","item_id":"\#($0)""# } ?? ""
      return try JSONDecoder().decode(
        MediaServerPlayItem.self,
        from: Data(#"{"id":"x","title":"t","type":"\#(type)","server_type":"\#(server)"\#(idField)}"#.utf8))
    }
    XCTAssertTrue(HomeViewModel.supportsInAppPlayback(try item("电影", server: "emby"), canRequestSuperUserEndpoints: true))
    XCTAssertFalse(HomeViewModel.supportsInAppPlayback(try item("电影", server: "emby"), canRequestSuperUserEndpoints: false))
    XCTAssertTrue(HomeViewModel.supportsInAppPlayback(try item("电视剧", server: "emby"), canRequestSuperUserEndpoints: true))
    XCTAssertFalse(HomeViewModel.supportsInAppPlayback(try item("音乐", server: "emby"), canRequestSuperUserEndpoints: true))
    XCTAssertFalse(HomeViewModel.supportsInAppPlayback(try item("电影", server: "plex"), canRequestSuperUserEndpoints: true))
    XCTAssertFalse(
      HomeViewModel.supportsInAppPlayback(try item("电影", server: "emby", itemID: nil), canRequestSuperUserEndpoints: true))
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
    return service
  }

  private func makeCoordinator(_ service: APIService) -> PlaybackCoordinator {
    services.append(service)
    return PlaybackCoordinator(apiService: service, embySession: PlaybackURLProtocol.session)
  }

  private static func movie(
    id: String = "m1", type: String = "Movie", positionSeconds: Int64 = 0
  ) -> String {
    #"{"Id":"\#(id)","Name":"测试电影","Type":"\#(type)","RunTimeTicks":\#(twoHours),"UserData":{"PlaybackPositionTicks":\#(positionSeconds * 10_000_000),"IsFavorite":true}}"#
  }

  private static func playbackInfo(container: String = "mp4") -> String {
    #"{"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Container":"\#(container)","Protocol":"File","MediaStreams":[{"Type":"Video","Codec":"hevc"},{"Type":"Audio","Codec":"eac3"}]}]}"#
  }

  private static func embyServer(name: String, host: String, playHost: String? = nil) -> String {
    let play = playHost.map { #","play_host":"\#($0)""# } ?? ""
    return #"{"name":"\#(name)","type":"emby","enabled":true,"config":{"host":"\#(host)"\#(play),"apikey":"emby-key","username":"admin"}}"#
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
    coordinator.endSession()
    XCTAssertNil(coordinator.session)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.contains("/Sessions/") })
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
    coordinator.endSession()
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
    coordinator.endSession()
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
    coordinator.endSession()
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
    await run(coordinator, .libraryItem(itemID: "m1"))
    XCTAssertNil(coordinator.failure)
    XCTAssertEqual(streamURL(coordinator)?.host, "wan.playback-tests.local")
    coordinator.endSession()
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

    XCTAssertNil(coordinator.session)
    XCTAssertNil(coordinator.resumePrompt)
    XCTAssertNil(coordinator.failure)
    XCTAssertFalse(coordinator.isResolving)
    XCTAssertFalse(PlaybackURLProtocol.stub.requests().contains { $0.url.path.hasSuffix("/PlaybackInfo") })
  }

  private func startEpisodeSession(_ coordinator: PlaybackCoordinator) async throws -> PlaybackSession {
    PlaybackURLProtocol.stub.configure {
      $0.mediaServers = "[\(Self.embyServer(name: "emby", host: "lan.playback-tests.local"))]"
      $0.users = #"[{"Id":"u-admin","Name":"admin"}]"#
      $0.items = [
        "lan.playback-tests.local|e1": #"{"Id":"e1","Type":"Episode","Name":"一","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":1}"#,
        "lan.playback-tests.local|e2": #"{"Id":"e2","Type":"Episode","Name":"二","SeriesId":"s1","ParentIndexNumber":1,"IndexNumber":2}"#,
      ]
      $0.playbackInfo = Self.playbackInfo(container: "mkv")
    }
    await run(coordinator, .serverItem(serverName: "emby", itemID: "e1"))
    return try XCTUnwrap(coordinator.session)
  }

  func testSwitchingEpisodeStopsOldSessionAndKeepsPlayerScreen() async throws {
    let coordinator = makeCoordinator(makeService())
    let first = try await startEpisodeSession(coordinator)
    let player = first.makeMPVPlayer()
    var result: PlaybackCoordinator.SwitchResult?

    coordinator.switchItem(to: "e2", startPosition: 0, from: first) { result = $0 }
    await coordinator.switchTaskForTesting?.value

    guard case .switched(let next) = result else { return XCTFail("应切到下一集，实际 \(String(describing: result))") }
    XCTAssertTrue(first.isStopped, "旧会话停止并上报")
    XCTAssertTrue(coordinator.session === next)
    XCTAssertEqual(next.id, first.id, "沿用播放界面身份，全屏界面不重新弹出")
    XCTAssertTrue(next.mpvPlayer === player, "复用同一个 mpv 播放器")
    XCTAssertEqual(next.streamURL.path, "/Videos/e2/stream.mkv")
    XCTAssertEqual(next.item.id, "e2")
    XCTAssertNil(coordinator.failure)

    // 旧会话的退出回调不能结束新会话。
    coordinator.endSession(first)
    XCTAssertTrue(coordinator.session === next)
    coordinator.endSession(next)
    XCTAssertNil(coordinator.session)
  }

  func testRapidSecondSwitchSupersedesFirstWithoutEarlyCompletion() async throws {
    let coordinator = makeCoordinator(makeService())
    let first = try await startEpisodeSession(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.playbackInfoGate = gate }
    var results: [PlaybackCoordinator.SwitchResult] = []

    coordinator.switchItem(to: "e2", from: first) { results.append($0) }
    let replaced = try XCTUnwrap(coordinator.switchTaskForTesting)
    coordinator.switchItem(to: "e2", from: first) { results.append($0) }
    let latest = try XCTUnwrap(coordinator.switchTaskForTesting)
    await replaced.value

    XCTAssertTrue(results.isEmpty, "被替换的切换不回报，界面保持加载状态")
    XCTAssertEqual(coordinator.switchTaskForTesting, latest, "旧任务结束不能清掉新任务")
    XCTAssertTrue(coordinator.session === first)
    gate.signal()
    gate.signal()
    await latest.value

    XCTAssertEqual(results.count, 1)
    guard case .switched(let next) = results.first else { return XCTFail("应切到下一集，实际 \(results)") }
    XCTAssertTrue(coordinator.session === next)
    XCTAssertEqual(next.item.id, "e2")
    XCTAssertNil(coordinator.switchTaskForTesting)
    coordinator.endSession()
  }

  func testAccountChangeDuringSwitchPublishesNothing() async throws {
    let service = makeService()
    let coordinator = makeCoordinator(service)
    let first = try await startEpisodeSession(coordinator)
    let gate = DispatchSemaphore(value: 0)
    PlaybackURLProtocol.stub.configure { $0.playbackInfoGate = gate }
    let before = PlaybackURLProtocol.stub.requests().count
    var result: PlaybackCoordinator.SwitchResult?

    coordinator.switchItem(to: "e2", from: first) { result = $0 }
    let task = try XCTUnwrap(coordinator.switchTaskForTesting)
    for _ in 0..<200
    where !PlaybackURLProtocol.stub.requests().dropFirst(before).contains(where: { $0.url.path.hasSuffix("/PlaybackInfo") }) {
      try await Task.sleep(for: .milliseconds(10))
    }
    service.tokenForTesting = "another-token"
    gate.signal()
    await task.value

    guard case .discarded = result else { return XCTFail("账号切换后不应发布，实际 \(String(describing: result))") }
    XCTAssertTrue(coordinator.session === first, "没有发布新会话")
    XCTAssertFalse(first.isStopped)
    coordinator.endSession()
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
    /// `host|seriesID` → 剧集列表 JSON
    var episodes: [String: String] = [:]
    var usersGate: DispatchSemaphore?
    var playbackInfoGate: DispatchSemaphore?
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

    let path = url.path
    if path.hasSuffix("/System/Info/Public") {
      respond(200, #"{"Id":"server","Version":"4.8.0.0"}"#)
    } else if path.hasSuffix("/Users") {
      scenario.usersGate?.wait()
      respond(200, scenario.users)
    } else if path.hasSuffix("/Episodes") {
      let seriesID = url.deletingLastPathComponent().lastPathComponent
      respond(200, scenario.episodes["\(host)|\(seriesID)"] ?? #"{"Items":[]}"#)
    } else if path.hasSuffix("/PlaybackInfo") {
      scenario.playbackInfoGate?.wait()
      respond(200, scenario.playbackInfo)
    } else if recorded.method == "GET", path.contains("/Items/") {
      let itemID = url.lastPathComponent
      if let item = scenario.items["\(host)|\(itemID)"] {
        respond(200, item)
      } else {
        respond(404, "")
      }
    } else {
      respond(204, "")
    }
  }

  override func stopLoading() {}

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
