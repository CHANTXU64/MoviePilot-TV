import Foundation

/// Emby：同时探测内网和外网地址（内网优先），再按 MoviePilot `Emby.get_user` 的规则选 Emby 用户。
struct EmbyConnector: MediaServerConnector {
  func connect(
    server: MediaServerConf, config: MediaServerConnectionConfig, preferredUserName: String?, session: URLSession
  ) async throws -> any MediaServerConnection {
    guard let apiKey = config.apiKey else { throw PlaybackError.noPlayableServer }
    let clients = config.candidateBaseURLs.map {
      EmbyClient(baseURL: $0, apiKey: apiKey, session: session)
    }
    let probe = await PreferredReachability.first(of: clients, grace: MediaServerHTTP.preferredAddressGrace) {
      _ = try await $0.publicSystemInfo()
    }
    let client: EmbyClient
    switch probe {
    case .success(let reachable):
      client = reachable
    case .failure(let failures):
      try Task.checkCancellation()
      var blockedByTransportSecurity = false
      for error in failures.errors {
        if case EmbyClientError.unreachable(let transportSecurity) = error {
          blockedByTransportSecurity = blockedByTransportSecurity || transportSecurity
        } else {
          Logger.warning("[Playback] 探测 \(server.name) 地址失败: \(error.localizedDescription)")
        }
      }
      throw PlaybackError.unreachable(server: server.name, transportSecurity: blockedByTransportSecurity)
    }
    // 候选顺序与 MoviePilot 首页的继续观看、最近添加相同：先当前登录的 MoviePilot 用户名，再服务器配置里的用户名。
    // 播放读写的续播点、已看状态因此和首页显示的是同一个 Emby 用户。
    let users = try await client.users()
    guard let user = EmbyUser.select(from: users, preferredNames: [preferredUserName, config.username]) else {
      throw PlaybackError.noServerUser(server: server.name)
    }
    return EmbyServerConnection(
      serverName: server.name, config: config, preferredUserName: preferredUserName, client: client,
      userID: user.id)
  }
}

/// 一台 Emby 上的连接：把 Emby 接口转换成 `MediaServerConnection`。
struct EmbyServerConnection: MediaServerConnection {
  let serverName: String
  let config: MediaServerConnectionConfig
  let preferredUserName: String?
  let client: EmbyClient
  let userID: String

  var reportingServer: URL { client.baseURL }

  func item(id: String, timeout: TimeInterval?) async throws -> ServerMediaItem? {
    try await client.item(id: id, userID: userID, timeout: timeout)?.serverItem()
  }

  func items(matching expected: LibraryItemExpectation) async throws -> [ServerMediaItem] {
    let keys = Self.providerSearchKeys(for: expected)
    guard !keys.isEmpty else { return [] }
    do {
      return try await client.items(
        withAnyProviderID: keys, type: Self.itemType(expected.kind), userID: userID,
        timeout: EmbyClient.quickTimeout
      ).map { $0.serverItem() }
    } catch EmbyClientError.http(_) {
      // 搜索被拒绝时由调用方退回按 ID 查；连不上等错误照常抛出。
      return []
    }
  }

  func episodes(seriesID: String) async throws -> [ServerMediaItem] {
    try await client.episodes(seriesID: seriesID, userID: userID).map { $0.serverItem(defaultKind: .episode) }
  }

  /// 声明任何视频都可以直接播放（mpv 直连原文件），并关闭重新封装和转码，Emby 不会为此启动转码任务。
  func prepareStream(for item: ServerMediaItem, preferredSourceID: String?) async throws -> PreparedStream {
    let info = try await client.playbackInfo(itemID: item.id, userID: userID)
    if let code = info.errorCode, !code.isEmpty, info.mediaSources.isEmpty {
      throw PlaybackError.server("Emby 拒绝播放：\(code)")
    }
    let selection: EmbyDirectPlay.Selection
    let preferred = preferredSourceID.flatMap { id in info.mediaSources.first { $0.id == id } }
    switch preferred.map({ EmbyDirectPlay.evaluate($0) }) ?? EmbyDirectPlay.select(from: info.mediaSources) {
    case .success(let value): selection = value
    case .failure(let reason): throw PlaybackError.unsupported(reason)
    }
    let streamURL = try client.directStreamURL(
      itemID: item.id, selection: selection, playSessionID: info.playSessionID)
    return PreparedStream(
      item: item, source: selection.source.serverSource, sources: info.mediaSources.map(\.serverSource),
      playSessionID: info.playSessionID, streamURL: streamURL)
  }

  func report(
    _ event: PlaybackReportEvent, for stream: PreparedStream, positionSeconds: Double, isPaused: Bool
  ) async throws {
    var body: [String: JSONValue] = [
      "ItemId": .string(stream.item.id),
      "MediaSourceId": .string(stream.source.id),
      "PositionTicks": .int(EmbyTicks.from(seconds: positionSeconds)),
      "IsPaused": .bool(isPaused),
      "CanSeek": .bool(true),
      "PlayMethod": .string("DirectPlay"),
    ]
    if let playSessionID = stream.playSessionID {
      body["PlaySessionId"] = .string(playSessionID)
    }
    let endpoint: EmbyClient.PlaybackEvent
    switch event {
    case .start:
      endpoint = .start
    case .progress(let progress):
      endpoint = .progress
      // 省略时 Emby 一律按 TimeUpdate 处理，暂停、继续要明确告诉它。
      body["EventName"] = .string(Self.eventName(progress))
    case .stopped:
      endpoint = .stopped
    }
    try await client.report(endpoint, body: body)
  }

  /// 写回前重新读取单条条目的用户数据，只改续播位置、已看完和最后播放时间：开播时的条目可能来自剧集列表，
  /// Emby 列表里的 `PlayCount` 恒为 0、也没有最后播放时间，整份写回会把真实播放次数改成 0。
  /// 读不到用户数据就不写，不用残缺对象覆盖收藏等字段。
  func saveWatchProgress(_ progress: WatchProgress) async throws {
    guard let item = try await client.item(id: progress.itemID, userID: userID),
      var userData = item.userData
    else {
      Logger.warning("[Playback] 读不到条目的用户数据，未保存观看进度")
      return
    }
    userData["PlaybackPositionTicks"] = .int(
      progress.completed ? 0 : EmbyTicks.from(seconds: progress.positionSeconds))
    if progress.completed { userData["Played"] = .bool(true) }
    userData["LastPlayedDate"] = .string(ISO8601DateFormatter().string(from: progress.playedAt))
    try await client.updateUserData(userID: userID, itemID: progress.itemID, userData: userData)
  }

  /// Emby 没有 Jellyfin 的 trickplay 图集；若日后接入 Emby 的 BIF 缩略图，在这里返回图集地址。
  func trickplayTileURL(itemID: String, width: Int, index: Int, mediaSourceID: String) -> URL? {
    nil
  }

  /// 按外部编号搜索用的参数（Emby `AnyProviderIdEquals`，如 `tmdb.12345`），只取 Emby 自带刮削器会写的来源。
  nonisolated static func providerSearchKeys(for expected: LibraryItemExpectation) -> [String] {
    ["tmdb", "imdb", "tvdb"].compactMap { source in expected.externalIDs[source].map { "\(source).\($0)" } }
  }

  private static func itemType(_ kind: ServerMediaItem.Kind?) -> String? {
    switch kind {
    case .movie: "Movie"
    case .series: "Series"
    case .episode: "Episode"
    case .other, nil: nil
    }
  }

  private static func eventName(_ progress: PlaybackReportEvent.Progress) -> String {
    switch progress {
    case .timeUpdate: "TimeUpdate"
    case .pause: "Pause"
    case .unpause: "Unpause"
    }
  }
}

extension EmbyClientError: MediaServerReachabilityError {
  var isUnreachable: Bool {
    if case .unreachable = self { return true }
    return false
  }
}
