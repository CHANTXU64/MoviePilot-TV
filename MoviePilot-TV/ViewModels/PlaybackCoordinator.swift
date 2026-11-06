import Combine
import Foundation
import MPVUI

/// 应用内播放的入口目标。
enum PlaybackTarget: Equatable {
  /// 详情页：MoviePilot 媒体库同步表里的条目 ID，不知道属于哪台服务器。
  case libraryItem(itemID: String)
  /// 首页“最近添加”：已知服务器名称和条目 ID。
  case serverItem(serverName: String, itemID: String)
}

enum PlaybackError: LocalizedError, Equatable {
  case notAllowed
  case noEmbyServer
  case serverNotSupported(String)
  case unreachable(server: String, transportSecurity: Bool)
  case noEmbyUser
  case notFound
  case unsupportedItemType
  case noEpisodes
  case unsupported(EmbyDirectPlay.Unsupported)
  case server(String)

  var errorDescription: String? {
    switch self {
    case .notAllowed:
      return "只有管理员账号可以在应用内播放"
    case .noEmbyServer:
      return "MoviePilot 中没有可用的 Emby 服务器（需启用并填写地址和 API 密钥）"
    case .serverNotSupported(let name):
      return "媒体服务器“\(name)”暂不支持应用内播放，目前只支持 Emby"
    case .unreachable(let server, true):
      return "无法连接“\(server)”：系统不允许连接 http 域名地址，请为 Emby 配置 https 地址或内网 IP"
    case .unreachable(let server, false):
      return "无法连接“\(server)”，已尝试 MoviePilot 中配置的内网和外网地址"
    case .noEmbyUser:
      return "未找到可用的 Emby 用户"
    case .notFound:
      return "未在 Emby 中找到该条目，可能 MoviePilot 媒体库同步尚未更新"
    case .unsupportedItemType:
      return "应用内播放暂只支持电影和剧集"
    case .noEpisodes:
      return "这部剧在 Emby 中还没有可播放的剧集"
    case .unsupported(let reason):
      return reason.message
    case .server(let message):
      return message
    }
  }
}

/// 解析完成、可以交给播放器的结果。
struct PreparedPlayback {
  let client: EmbyClient
  let userID: String
  let item: EmbyItem
  let selection: EmbyDirectPlay.Selection
  let playSessionID: String?
  let streamURL: URL
  /// Emby 返回的全部版本，供播放界面的“版本”选择。
  var mediaSources: [EmbyMediaSource] = []

  var title: String { item.displayTitle }
  var resumePosition: Double? {
    PlaybackResumePolicy.resumePosition(
      positionTicks: item.playbackPositionTicks, runTimeTicks: item.runTimeTicks)
  }
}

/// 应用内播放的唯一 owner。由 `SessionScope` 持有：换账号或登出时随作用域拆除，正在解析的任务取消、播放器停止。
@MainActor
final class PlaybackCoordinator: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  struct ResumePrompt: Identifiable {
    let id = UUID()
    let prepared: PreparedPlayback
    let position: Double
  }

  struct Failure: Identifiable, Equatable {
    let id = UUID()
    let message: String
  }

  @Published private(set) var isResolving = false
  @Published var resumePrompt: ResumePrompt?
  @Published private(set) var session: PlaybackSession?
  @Published var failure: Failure?

  /// 弱引用：`APIService` → `SessionScope` → 本对象，强引用会让整个会话在登出后无法释放。
  private weak var apiService: APIService?
  private let embySession: URLSession
  private var resolveTask: Task<Void, Never>?
  private var switchTask: Task<Void, Never>?
  /// 每台服务器上次连通的地址，下次优先探测。
  private var preferredBaseURL: [String: URL] = [:]
  private var isTornDown = false

  init(apiService: APIService, embySession: URLSession = EmbyClient.sharedSession) {
    self.apiService = apiService
    self.embySession = embySession
  }

  #if TESTING
    var resolveTaskForTesting: Task<Void, Never>? { resolveTask }
  #endif

  var isBusy: Bool { isResolving || resumePrompt != nil || session != nil }

  func play(_ target: PlaybackTarget) {
    guard !isTornDown, !isBusy, let apiService else { return }
    guard apiService.canRequestSuperUserEndpoints else {
      fail(PlaybackError.notAllowed)
      return
    }
    let snapshot = apiService.sessionSnapshot()
    isResolving = true
    resolveTask = Task { [weak self] in
      guard let self else { return }
      do {
        let prepared = try await self.prepare(target, snapshot: snapshot)
        try self.ensureCurrent(snapshot)
        self.isResolving = false
        self.resolveTask = nil
        if let position = prepared.resumePosition {
          self.resumePrompt = ResumePrompt(prepared: prepared, position: position)
        } else {
          self.start(prepared, at: 0)
        }
      } catch {
        // 任务被取消时，状态已由取消方（取消按钮、作用域拆除）复位。
        guard !Task.isCancelled else { return }
        self.isResolving = false
        self.resolveTask = nil
        guard self.apiService?.isSessionUnchanged(from: snapshot) == true, !(error is CancellationError)
        else { return }
        self.fail(error)
      }
    }
  }

  func cancelResolving() {
    resolveTask?.cancel()
    resolveTask = nil
    isResolving = false
  }

  func resume(_ prompt: ResumePrompt, fromBeginning: Bool) {
    guard resumePrompt?.id == prompt.id else { return }
    resumePrompt = nil
    start(prompt.prepared, at: fromBeginning ? 0 : prompt.position)
  }

  func dismissResumePrompt() {
    resumePrompt = nil
  }

  /// 播放器关闭（Menu、播放结束或出错）后统一收尾。
  func endSession() {
    switchTask?.cancel()
    switchTask = nil
    guard let session else { return }
    self.session = nil
    session.stop()
  }

  /// 只在给定会话仍是当前会话时收尾：播放界面换集后，旧会话的退出回调不能结束新会话。
  func endSession(_ expected: PlaybackSession) {
    guard session === expected else { return }
    endSession()
  }

  func tearDown() {
    isTornDown = true
    switchTask?.cancel()
    switchTask = nil
    cancelResolving()
    resumePrompt = nil
    endSession()
  }

  // MARK: - 解析

  private func ensureCurrent(_ snapshot: APIServiceSessionSnapshot) throws {
    try Task.checkCancellation()
    guard !isTornDown, apiService?.isSessionUnchanged(from: snapshot) == true else {
      throw CancellationError()
    }
  }

  /// 媒体服务器配置很少变化，平时用会话缓存；解析失败时重新读一次，
  /// 地址、密钥或服务器列表确实变了才用新配置重试，没变就原样报告失败。
  private func prepare(
    _ target: PlaybackTarget, snapshot: APIServiceSessionSnapshot
  ) async throws -> PreparedPlayback {
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    try ensureCurrent(snapshot)
    do {
      return try await prepare(target, servers: servers, snapshot: snapshot)
    } catch let error where !(error is CancellationError) {
      let fresh = try? await apiService.fetchCachedMediaServers(forceRefresh: true)
      try ensureCurrent(snapshot)
      guard let fresh, fresh != servers else { throw error }
      return try await prepare(target, servers: fresh, snapshot: snapshot)
    }
  }

  private func prepare(
    _ target: PlaybackTarget, servers: [MediaServerConf], snapshot: APIServiceSessionSnapshot
  ) async throws -> PreparedPlayback {
    guard let apiService else { throw CancellationError() }
    let itemID: String
    let candidates: [MediaServerConf]
    switch target {
    case .libraryItem(let id):
      itemID = id
      candidates = servers.filter(\.supportsInAppPlayback)
      guard !candidates.isEmpty else { throw PlaybackError.noEmbyServer }
    case .serverItem(let serverName, let id):
      itemID = id
      guard let server = servers.first(where: { $0.name == serverName }) else {
        throw PlaybackError.noEmbyServer
      }
      guard server.supportsInAppPlayback else {
        throw server.type.lowercased() == "emby"
          ? PlaybackError.noEmbyServer : PlaybackError.serverNotSupported(server.name)
      }
      candidates = [server]
    }

    // 详情页的条目 ID 不带服务器名：逐台确认归属，第一台找到的为准（与 MoviePilot `/mediaserver/play` 相同）。
    var firstError: Error?
    for server in candidates {
      do {
        let client = try await connect(server, snapshot: snapshot)
        let users = try await client.users()
        try ensureCurrent(snapshot)
        guard
          let user = EmbyUser.select(
            from: users,
            preferredNames: [server.config?.username, apiService.currentUser?.user_name])
        else { throw PlaybackError.noEmbyUser }
        guard let item = try await client.item(id: itemID, userID: user.id) else { continue }
        try ensureCurrent(snapshot)
        return try await preparePlayback(client: client, userID: user.id, item: item, snapshot: snapshot)
      } catch let error where error is CancellationError {
        throw error
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    throw firstError ?? PlaybackError.notFound
  }

  private func preparePlayback(
    client: EmbyClient, userID: String, item requested: EmbyItem, snapshot: APIServiceSessionSnapshot,
    preferredSourceID: String? = nil
  ) async throws -> PreparedPlayback {
    // 剧集先简单处理：从第 1 季第 1 集开始。
    let item: EmbyItem
    switch requested.type {
    case "Movie", "Episode":
      item = requested
    case "Series":
      let episodes = try await client.episodes(seriesID: requested.id, userID: userID)
      try ensureCurrent(snapshot)
      guard let first = EmbyEpisodeOrder.firstEpisode(in: episodes) else {
        throw PlaybackError.noEpisodes
      }
      item = first
    default:
      throw PlaybackError.unsupportedItemType
    }
    let info = try await client.playbackInfo(itemID: item.id, userID: userID)
    try ensureCurrent(snapshot)
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
    return PreparedPlayback(
      client: client, userID: userID, item: item, selection: selection,
      playSessionID: info.playSessionID, streamURL: streamURL, mediaSources: info.mediaSources)
  }

  /// 按「上次可用 → 内网 → 外网」探测，第一个响应的地址即用于本次播放。
  private func connect(
    _ server: MediaServerConf, snapshot: APIServiceSessionSnapshot
  ) async throws -> EmbyClient {
    guard let config = server.config, let apiKey = config.apiKey else {
      throw PlaybackError.noEmbyServer
    }
    var candidates = config.candidateBaseURLs
    if let preferred = preferredBaseURL[server.name], let index = candidates.firstIndex(of: preferred) {
      candidates.insert(candidates.remove(at: index), at: 0)
    }
    var blockedByTransportSecurity = false
    for baseURL in candidates {
      let client = EmbyClient(baseURL: baseURL, apiKey: apiKey, session: embySession)
      do {
        _ = try await client.publicSystemInfo()
        try ensureCurrent(snapshot)
        preferredBaseURL[server.name] = baseURL
        return client
      } catch EmbyClientError.unreachable(let transportSecurity) {
        blockedByTransportSecurity = blockedByTransportSecurity || transportSecurity
      } catch let error as EmbyClientError {
        Logger.warning("[Playback] 探测 \(server.name) 地址失败: \(error.localizedDescription)")
      }
    }
    preferredBaseURL[server.name] = nil
    throw PlaybackError.unreachable(server: server.name, transportSecurity: blockedByTransportSecurity)
  }

  // MARK: - 播放

  private func start(_ prepared: PreparedPlayback, at position: Double) {
    guard !isTornDown else { return }
    let session = PlaybackSession(prepared: prepared, startPosition: position)
    attachFinishHandler(to: session)
    self.session = session
  }

  private func attachFinishHandler(to session: PlaybackSession) {
    session.onFinish = { [weak self, weak session] message in
      guard let self, let session, self.session === session else { return }
      self.endSession()
      if let message { self.failure = Failure(message: message) }
    }
  }

  // MARK: - 播放中换集、换版本

  /// 换集或换版本的结果，交给播放界面提示。
  enum SwitchResult {
    case switched(PlaybackSession)
    case failed(String)
    /// 期间会话已结束、账号已切换或又发起了新的切换。
    case discarded
  }

  #if TESTING
    var switchTaskForTesting: Task<Void, Never>? { switchTask }
  #endif

  /// 在当前 mpv 播放界面里改播另一集或另一个版本（对应 Swiftfin 的 `playNewItem`）。
  /// 沿用当前会话的 Emby 客户端和用户，为新条目重新取 PlaybackInfo、选版本。
  /// 旧会话照常停止并上报进度，新会话复用同一个 mpv 播放器和界面。
  func switchItem(
    to itemID: String, mediaSourceID: String? = nil, startPosition: Double = 0,
    from current: PlaybackSession, completion: @escaping (SwitchResult) -> Void = { _ in }
  ) {
    guard !isTornDown, session === current, let apiService else {
      completion(.discarded)
      return
    }
    let snapshot = apiService.sessionSnapshot()
    switchTask?.cancel()
    switchTask = Task { [weak self] in
      guard let self else { return }
      let result: SwitchResult
      do {
        let client = current.client
        let userID = current.userID
        guard let item = try await client.item(id: itemID, userID: userID) else {
          throw PlaybackError.notFound
        }
        try self.ensureCurrent(snapshot)
        let prepared = try await self.preparePlayback(
          client: client, userID: userID, item: item, snapshot: snapshot, preferredSourceID: mediaSourceID)
        try self.ensureCurrent(snapshot)
        guard !Task.isCancelled, self.session === current, !current.isStopped else { throw CancellationError() }
        current.stop()
        let next = PlaybackSession(
          prepared: prepared, startPosition: startPosition, id: current.id, mpvPlayer: current.mpvPlayer)
        self.attachFinishHandler(to: next)
        self.session = next
        result = .switched(next)
      } catch {
        if Task.isCancelled || error is CancellationError
          || self.apiService?.isSessionUnchanged(from: snapshot) != true || self.session !== current
        {
          result = .discarded
        } else {
          let message = (error as? LocalizedError)?.errorDescription ?? "播放失败"
          Logger.warning("[Playback] 切换条目失败: \(message)")
          result = .failed(message)
        }
      }
      // 取消只来自新的切换、结束会话或登出：`switchTask` 已归新任务或已清空，也不再回报，
      // 免得旧任务清掉新任务的引用、让界面在新切换完成前就结束加载状态。
      guard !Task.isCancelled else { return }
      self.switchTask = nil
      completion(result)
    }
  }

  private func fail(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? "播放失败"
    Logger.error("[Playback] 应用内播放失败: \(message)")
    failure = Failure(message: message)
  }
}

/// 一次播放：持有 mpv 播放器，负责起播位置、进度上报和结束收尾。`stop()` 可重复调用。
@MainActor
final class PlaybackSession: Identifiable {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  static let progressInterval: Double = 10

  /// mpv 默认优先选中文字幕；没有中文字幕时按片源默认轨道。
  static let mpvConfiguration = MPVPlayerConfiguration(
    additionalOptions: ["slang": "chi,zho,zh,chs,cht,sc,tc,cn,zh-Hans,zh-Hant"].merging(
      subtitleFontOptions, uniquingKeysWith: { current, _ in current }),
    automaticallyPlays: true
  )

  /// ASS 等由 mpv（libass）绘制的字幕用内置的思源黑体（Noto Sans SC）。
  /// libass 自带的 FreeType 打不开 tvOS 的系统中文字体（PingFang 是 `hvgl` 字形，Hiragino 是 CFF 字形），
  /// 按系统字体回退只会画出方块；因此不查系统字体，只用内置字体和片源 MKV 附带的字体，找不到的字体名一律落到内置字体。
  /// SRT 等文字字幕由界面用系统字体绘制，不经过这里。
  private static var subtitleFontOptions: [String: String] {
    guard let directory = Bundle.main.url(forResource: "SubtitleFonts", withExtension: "bundle") else {
      return [:]
    }
    return [
      "sub-fonts-dir": directory.path(percentEncoded: false),
      "sub-font": "Noto Sans SC",
      "sub-font-provider": "none",
    ]
  }

  /// 播放界面的身份。播放中换集时新会话沿用旧会话的 id，全屏播放界面不重新弹出。
  let id: UUID
  /// 直连原文件的地址，含密钥，不得写入日志。
  let streamURL: URL
  /// 在播放界面出现时创建，未展示就不启动解码。
  private(set) var mpvPlayer: MPVPlayer?
  /// 正常结束传 nil，出错传提示文字。
  var onFinish: ((String?) -> Void)?

  private let prepared: PreparedPlayback
  private let startPosition: Double
  private var hasStarted = false
  private(set) var isStopped = false
  private var lastReportedPause = false
  private var mpvEventTask: Task<Void, Never>?
  private var mpvProgressTask: Task<Void, Never>?

  init(prepared: PreparedPlayback, startPosition: Double, id: UUID = UUID(), mpvPlayer: MPVPlayer? = nil) {
    self.id = id
    self.prepared = prepared
    self.startPosition = startPosition
    self.mpvPlayer = mpvPlayer
    streamURL = prepared.streamURL
  }

  var titles: (primary: String, secondary: String?) { prepared.item.playerTitles }
  /// 以下供播放界面的信息、章节、队列等面板使用。
  var client: EmbyClient { prepared.client }
  var userID: String { prepared.userID }
  var item: EmbyItem { prepared.item }
  var mediaSource: EmbyMediaSource { prepared.selection.source }
  var mediaSources: [EmbyMediaSource] { prepared.mediaSources }
  var startSeconds: Double { startPosition }

  func makeMPVPlayer() -> MPVPlayer {
    if let mpvPlayer { return mpvPlayer }
    let player = MPVPlayer(configuration: Self.mpvConfiguration)
    mpvPlayer = player
    return player
  }

  private var currentSeconds: Double {
    let seconds = mpvPlayer?.position.seconds ?? 0
    return seconds.isFinite ? max(0, seconds) : 0
  }

  func start() {
    guard !hasStarted, !isStopped else { return }
    hasStarted = true
    let player = makeMPVPlayer()
    observe(player)
    player.load(
      streamURL, playAutomatically: true,
      startTime: startPosition > 0 ? .milliseconds(Int64(startPosition * 1000)) : nil)
    report(.start, isPaused: false, position: startPosition)
  }

  func stop() {
    guard !isStopped else { return }
    isStopped = true
    let position = currentSeconds
    mpvEventTask?.cancel()
    mpvEventTask = nil
    mpvProgressTask?.cancel()
    mpvProgressTask = nil
    mpvPlayer?.stop()
    onFinish = nil
    guard hasStarted else { return }
    report(.stopped, isPaused: true, position: position)
    saveUserData(position: position)
  }

  // MARK: - mpv

  private func observe(_ player: MPVPlayer) {
    let events = player.makeEventStream()
    mpvEventTask = Task { [weak self] in
      for await event in events {
        guard let self, !self.isStopped else { return }
        self.handle(event.change)
      }
    }
    mpvProgressTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Self.progressInterval))
        guard let self, !self.isStopped, !Task.isCancelled else { return }
        if self.mpvPlayer?.state == .playing {
          self.report(.progress, isPaused: false, position: self.currentSeconds)
        }
      }
    }
  }

  private func handle(_ change: MPVPlaybackEvent.Change) {
    switch change {
    case .stateChanged(.ended):
      finish(message: nil)
    case .stateChanged(.failed(let error)), .error(let error, fatal: true):
      Logger.error("[Playback] mpv 播放失败: \(EmbyClient.redactedForLogging(String(describing: error)))")
      finish(message: "无法播放该影片，请检查与 Emby 的网络连接")
    case .pauseChanged(let isPaused):
      handlePauseChange(isPaused: isPaused)
    default:
      break
    }
  }

  // MARK: - 共用

  private func handlePauseChange(isPaused: Bool) {
    guard !isStopped, hasStarted, isPaused != lastReportedPause else { return }
    lastReportedPause = isPaused
    report(.progress, isPaused: isPaused, position: currentSeconds)
  }

  private func finish(message: String?) {
    guard !isStopped else { return }
    onFinish?(message)
  }

  // MARK: - 上报（只发不等，失败只记日志）

  private func report(_ event: EmbyClient.PlaybackEvent, isPaused: Bool, position: Double) {
    var body: [String: JSONValue] = [
      "ItemId": .string(prepared.item.id),
      "MediaSourceId": .string(prepared.selection.source.id),
      "PositionTicks": .int(EmbyTicks.from(seconds: position)),
      "IsPaused": .bool(isPaused),
      "CanSeek": .bool(true),
      "PlayMethod": .string("DirectPlay"),
    ]
    if let playSessionID = prepared.playSessionID {
      body["PlaySessionId"] = .string(playSessionID)
    }
    let client = prepared.client
    Task {
      do {
        try await client.report(event, body: body)
      } catch {
        Logger.warning("[Playback] 播放状态上报失败: \(error.localizedDescription)")
      }
    }
  }

  private func saveUserData(position: Double) {
    let completed = PlaybackResumePolicy.isCompleted(
      positionSeconds: position, runTimeTicks: prepared.item.runTimeTicks)
    var userData = prepared.item.userData ?? [:]
    userData["PlaybackPositionTicks"] = .int(completed ? 0 : EmbyTicks.from(seconds: position))
    if completed { userData["Played"] = .bool(true) }
    userData["LastPlayedDate"] = .string(ISO8601DateFormatter().string(from: Date()))
    let client = prepared.client
    let userID = prepared.userID
    let itemID = prepared.item.id
    Task {
      do {
        try await client.updateUserData(userID: userID, itemID: itemID, userData: userData)
      } catch {
        Logger.warning("[Playback] 保存观看进度失败: \(error.localizedDescription)")
      }
    }
  }
}
