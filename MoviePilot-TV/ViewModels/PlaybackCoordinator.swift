import AVFoundation
import AVKit
import Combine
import Foundation

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

  private let apiService: APIService
  private let embySession: URLSession
  private var resolveTask: Task<Void, Never>?
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
    guard !isTornDown, !isBusy else { return }
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
        guard self.apiService.isSessionUnchanged(from: snapshot), !(error is CancellationError)
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
    guard let session else { return }
    self.session = nil
    session.stop()
  }

  func tearDown() {
    isTornDown = true
    cancelResolving()
    resumePrompt = nil
    endSession()
  }

  // MARK: - 解析

  private func ensureCurrent(_ snapshot: APIServiceSessionSnapshot) throws {
    try Task.checkCancellation()
    guard !isTornDown, apiService.isSessionUnchanged(from: snapshot) else {
      throw CancellationError()
    }
  }

  private func prepare(
    _ target: PlaybackTarget, snapshot: APIServiceSessionSnapshot
  ) async throws -> PreparedPlayback {
    let servers = try await apiService.fetchMediaServers()
    try ensureCurrent(snapshot)

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
    client: EmbyClient, userID: String, item requested: EmbyItem, snapshot: APIServiceSessionSnapshot
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
    switch EmbyDirectPlay.select(from: info.mediaSources) {
    case .success(let value): selection = value
    case .failure(let reason): throw PlaybackError.unsupported(reason)
    }
    let streamURL = try client.directStreamURL(
      itemID: item.id, selection: selection, playSessionID: info.playSessionID)
    return PreparedPlayback(
      client: client, userID: userID, item: item, selection: selection,
      playSessionID: info.playSessionID, streamURL: streamURL)
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
    session.onFinish = { [weak self, weak session] message in
      guard let self, let session, self.session === session else { return }
      self.endSession()
      if let message { self.failure = Failure(message: message) }
    }
    self.session = session
  }

  private func fail(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? "播放失败"
    Logger.error("[Playback] 应用内播放失败: \(message)")
    failure = Failure(message: message)
  }
}

/// 一次播放：持有 AVPlayer，负责起播位置、进度上报和结束收尾。`stop()` 可重复调用。
@MainActor
final class PlaybackSession: Identifiable {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  static let progressInterval: Double = 10

  let id = UUID()
  let player: AVPlayer
  /// 正常结束传 nil，出错传提示文字。
  var onFinish: ((String?) -> Void)?

  private let prepared: PreparedPlayback
  private let startPosition: Double
  private var hasStarted = false
  private(set) var isStopped = false
  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var pauseObservation: NSKeyValueObservation?
  private var notificationObservers: [NSObjectProtocol] = []

  init(prepared: PreparedPlayback, startPosition: Double) {
    self.prepared = prepared
    self.startPosition = startPosition
    let item = AVPlayerItem(url: prepared.streamURL)
    item.externalMetadata = Self.metadata(for: prepared.item)
    player = AVPlayer(playerItem: item)
  }

  var title: String { prepared.title }

  private var currentSeconds: Double {
    let seconds = player.currentTime().seconds
    return seconds.isFinite ? max(0, seconds) : 0
  }

  func start() {
    guard !hasStarted, !isStopped else { return }
    hasStarted = true
    if startPosition > 0 {
      player.seek(
        to: CMTime(seconds: startPosition, preferredTimescale: 600),
        toleranceBefore: .zero, toleranceAfter: .zero)
    }
    observe()
    player.play()
    report(.start, isPaused: false, position: startPosition)
  }

  func stop() {
    guard !isStopped else { return }
    isStopped = true
    let position = currentSeconds
    player.pause()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    statusObservation = nil
    pauseObservation = nil
    notificationObservers.forEach(NotificationCenter.default.removeObserver)
    notificationObservers = []
    player.replaceCurrentItem(with: nil)
    onFinish = nil
    guard hasStarted else { return }
    report(.stopped, isPaused: true, position: position)
    saveUserData(position: position)
  }

  private func observe() {
    let interval = CMTime(seconds: Self.progressInterval, preferredTimescale: 1)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.isStopped, self.player.timeControlStatus == .playing else { return }
        self.report(.progress, isPaused: false, position: self.currentSeconds)
      }
    }
    statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in self?.handleItemStatus() }
    }
    pauseObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in self?.handlePauseChange() }
    }
    let center = NotificationCenter.default
    notificationObservers = [
      center.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.finish(message: nil) }
      },
      center.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: player.currentItem,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.finish(message: "播放中断，请检查与 Emby 的网络连接") }
      },
    ]
  }

  private func handleItemStatus() {
    guard !isStopped, let item = player.currentItem, item.status == .failed else { return }
    if let error = item.error as NSError? {
      Logger.error("[Playback] AVPlayer 起播失败: \(error.domain) \(error.code)")
    }
    finish(message: "无法播放该影片，可能是编码不受 Apple TV 支持或网络无法访问 Emby")
  }

  private var lastReportedPause = false

  private func handlePauseChange() {
    guard !isStopped, hasStarted else { return }
    let isPaused = player.timeControlStatus == .paused
    guard isPaused != lastReportedPause else { return }
    lastReportedPause = isPaused
    report(.progress, isPaused: isPaused, position: currentSeconds)
  }

  private func finish(message: String?) {
    guard !isStopped else { return }
    onFinish?(message)
  }

  // MARK: - 上报（只发不等，失败只记日志）

  private static func ticks(_ seconds: Double) -> Int { Int(seconds * 10_000_000) }

  private func report(_ event: EmbyClient.PlaybackEvent, isPaused: Bool, position: Double) {
    var body: [String: JSONValue] = [
      "ItemId": .string(prepared.item.id),
      "MediaSourceId": .string(prepared.selection.source.id),
      "PositionTicks": .int(Self.ticks(position)),
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
    userData["PlaybackPositionTicks"] = .int(completed ? 0 : Self.ticks(position))
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

  private static func metadata(for item: EmbyItem) -> [AVMetadataItem] {
    var result: [AVMetadataItem] = []
    func add(_ identifier: AVMetadataIdentifier, _ value: String?) {
      guard let value, !value.isEmpty else { return }
      let entry = AVMutableMetadataItem()
      entry.identifier = identifier
      entry.value = value as NSString
      entry.extendedLanguageTag = "und"
      result.append(entry)
    }
    add(.commonIdentifierTitle, item.displayTitle)
    add(.commonIdentifierDescription, item.overview)
    return result
  }
}
