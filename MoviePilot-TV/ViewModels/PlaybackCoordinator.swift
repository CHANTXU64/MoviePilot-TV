import Combine
import Foundation
import MPVUI

/// 应用内播放的入口目标。
enum PlaybackTarget: Equatable {
  /// 详情页：MoviePilot 媒体库同步表里的条目 ID，不知道属于哪台服务器，也可能是别的服务器上的 ID。
  /// 起播时在各台 Emby 上按 `expected`（类型、外部编号）找条目，见 `PlaybackCoordinator.findLibraryItem`。
  case libraryItem(itemID: String, expected: LibraryItemExpectation)
  /// 已知服务器名称和这台服务器自己的条目 ID（首页“最近添加”，或详情页已在 Emby 上找到）。
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

/// 一台 Emby 上已连通的地址和选中的用户。MoviePilot 配置或 MoviePilot 用户名变了就不再沿用。
struct EmbyConnection {
  let config: MediaServerConnectionConfig
  let preferredUserName: String?
  let client: EmbyClient
  let userID: String
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

  /// 解析、询问续播、播放三者互斥，同一时间只处于一个阶段。
  enum Phase {
    case idle
    case resolving(Task<Void, Never>)
    case prompting(ResumePrompt)
    case playing(PlaybackSession)
  }

  /// 换集或换版本的结果，交给播放界面提示。
  enum SwitchResult {
    case switched
    case failed(String)
    /// 期间播放已结束或账号已切换。
    case discarded
  }

  /// 多个地址都连通时，排在前面的（内网）可以晚到这么久仍被选中。
  static let preferredAddressGrace: Duration = .milliseconds(500)
  /// 连接（地址和 Emby 用户）沿用的时长；到期重新探测、重选用户，Emby 端删改用户后能自行恢复。
  static let connectionTTL: TimeInterval = 600

  @Published private(set) var phase: Phase = .idle
  @Published var failure: Failure?

  /// 弱引用：`APIService` → `SessionScope` → 本对象，强引用会让整个会话在登出后无法释放。
  private weak var apiService: APIService?
  private let embySession: URLSession
  private var switchTask: Task<Void, Never>?
  /// 按服务器名称缓存的连接：下次播放不再探测地址、查询用户；同一台同时发起的连接合并为一次。
  private let connections: CoalescingCache<String, EmbyConnection>
  private var isTornDown = false

  init(
    apiService: APIService, embySession: URLSession = EmbyClient.sharedSession,
    now: @escaping () -> Date = Date.init
  ) {
    self.apiService = apiService
    self.embySession = embySession
    connections = CoalescingCache(
      ttl: Self.connectionTTL, capacity: 8, renewsTTLOnAccess: false, now: now)
  }

  var isResolving: Bool {
    guard case .resolving = phase else { return false }
    return true
  }

  var resumePrompt: ResumePrompt? {
    guard case .prompting(let prompt) = phase else { return nil }
    return prompt
  }

  var session: PlaybackSession? {
    guard case .playing(let session) = phase else { return nil }
    return session
  }

  var isBusy: Bool {
    guard case .idle = phase else { return true }
    return false
  }

  #if TESTING
    var resolveTaskForTesting: Task<Void, Never>? {
      guard case .resolving(let task) = phase else { return nil }
      return task
    }
    var switchTaskForTesting: Task<Void, Never>? { switchTask }
  #endif

  func play(_ target: PlaybackTarget) {
    guard !isTornDown, !isBusy, let apiService else { return }
    guard apiService.canRequestSuperUserEndpoints else {
      fail(PlaybackError.notAllowed)
      return
    }
    // 只在发布结果时复核会话：中间的 Emby 请求与 MoviePilot 会话无关，换账号时由作用域拆除取消。
    let snapshot = apiService.sessionSnapshot()
    let userName = apiService.currentOrStoredUserName
    let task = Task { [weak self] in
      let outcome: Result<PreparedPlayback, Error>
      do {
        guard let self else { return }
        outcome = .success(try await self.prepare(target, preferredUserName: userName))
      } catch {
        outcome = .failure(error)
      }
      // 取消来自取消按钮或作用域拆除，阶段已由取消方复位。
      guard let self, !Task.isCancelled else { return }
      self.phase = .idle
      guard self.apiService?.isSessionUnchanged(from: snapshot) == true else { return }
      switch outcome {
      case .success(let prepared):
        if let position = prepared.resumePosition {
          self.phase = .prompting(ResumePrompt(prepared: prepared, position: position))
        } else {
          self.start(prepared, at: 0)
        }
      case .failure(let error):
        if !(error is CancellationError) { self.fail(error) }
      }
    }
    phase = .resolving(task)
  }

  func cancelResolving() {
    guard case .resolving(let task) = phase else { return }
    task.cancel()
    phase = .idle
  }

  func resume(_ prompt: ResumePrompt, fromBeginning: Bool) {
    guard case .prompting(let current) = phase, current.id == prompt.id else { return }
    start(prompt.prepared, at: fromBeginning ? 0 : prompt.position)
  }

  func dismissResumePrompt() {
    guard case .prompting = phase else { return }
    phase = .idle
  }

  /// 播放界面关闭后收尾。
  func endSession() {
    if let session { endSession(session) }
  }

  /// 只结束给定的会话：界面的关闭回调可能晚于下一次播放开始。
  func endSession(_ session: PlaybackSession) {
    guard isPlaying(session) else { return }
    switchTask?.cancel()
    switchTask = nil
    phase = .idle
    session.stop()
  }

  func tearDown() {
    isTornDown = true
    switchTask?.cancel()
    switchTask = nil
    switch phase {
    case .resolving(let task): task.cancel()
    case .playing(let session): session.stop()
    case .idle, .prompting: break
    }
    phase = .idle
    connections.invalidateAll()
  }

  /// 详情页的条目 ID 不带服务器名，可能来自任何一台媒体服务器，不同服务器的数字 ID 还会撞号（多台 Emby 之间也会）。
  /// 只启用了一台服务器（且是可播放的 Emby）时 ID 只可能来自它，不必确认，起播时再找；
  /// 否则在每台可播放的 Emby 上找这个条目（见 `findLibraryItem`），第一台找到的为准，用它自己的条目 ID。
  /// 确认不在任何一台上时返回 nil（不显示播放）；无法确认（连不上等）时仍返回媒体库条目，起播时再逐台找。
  func locateLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, in servers: [MediaServerConf]
  ) async -> PlaybackTarget? {
    guard !isTornDown, let apiService, apiService.canRequestSuperUserEndpoints else { return nil }
    let enabled = servers.filter(\.isEnabled)
    let playable = enabled.filter(\.supportsInAppPlayback)
    guard !playable.isEmpty else { return nil }
    let libraryItem = PlaybackTarget.libraryItem(itemID: itemID, expected: expected)
    if enabled.count == 1 { return libraryItem }
    let userName = apiService.currentOrStoredUserName
    var isUncertain = false
    for server in playable {
      do {
        let found = try await withConnection(to: server, preferredUserName: userName) {
          try await Self.findLibraryItem(itemID, expected: expected, strict: true, on: $0)
        }
        if let found { return .serverItem(serverName: server.name, itemID: found.id) }
      } catch {
        if error is CancellationError || Task.isCancelled { return nil }
        isUncertain = true
      }
    }
    return isUncertain ? libraryItem : nil
  }

  /// 在一台 Emby 上找详情页的条目，返回这台服务器自己的条目（ID 可能与 MoviePilot 给的不同）。
  /// 先按外部编号搜索，同一部片在各台服务器上的 ID 不同也能找到；搜不到再看 MoviePilot 给的 ID 在这台上是不是它。
  /// `strict`（启用了多台服务器）时外部编号必须对得上，见 `LibraryItemExpectation.accepts`。
  private static func findLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, strict: Bool, on connection: EmbyConnection
  ) async throws -> EmbyItem? {
    let keys = expected.providerSearchKeys
    if !keys.isEmpty {
      do {
        let found = try await connection.client.items(
          withAnyProviderID: keys, type: expected.type, userID: connection.userID, timeout: EmbyClient.quickTimeout)
        if let item = found.first(where: { expected.accepts($0, strict: true) }) { return item }
      } catch EmbyClientError.http(_) {
        // 搜索被拒绝时退回按 ID 查；连不上等错误照常抛出。
      }
    }
    guard
      let item = try await connection.client.item(
        id: itemID, userID: connection.userID, timeout: EmbyClient.quickTimeout)
    else { return nil }
    return expected.accepts(item, strict: strict) ? item : nil
  }

  // MARK: - 解析

  private func isPlaying(_ session: PlaybackSession) -> Bool {
    guard case .playing(let current) = phase else { return false }
    return current === session
  }

  /// 媒体服务器配置很少变化，平时用会话缓存；解析失败时重新读一次，
  /// 地址、密钥或服务器列表确实变了才用新配置重试，没变就原样报告失败。
  private func prepare(_ target: PlaybackTarget, preferredUserName: String?) async throws -> PreparedPlayback {
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    do {
      return try await prepare(target, servers: servers, preferredUserName: preferredUserName)
    } catch let error where !(error is CancellationError) {
      let fresh = try? await apiService.fetchCachedMediaServers(forceRefresh: true)
      try Task.checkCancellation()
      guard let fresh, fresh != servers else { throw error }
      return try await prepare(target, servers: fresh, preferredUserName: preferredUserName)
    }
  }

  private func prepare(
    _ target: PlaybackTarget, servers: [MediaServerConf], preferredUserName: String?
  ) async throws -> PreparedPlayback {
    let itemID: String
    let expected: LibraryItemExpectation?
    let candidates: [MediaServerConf]
    switch target {
    case .libraryItem(let id, let expectation):
      itemID = id
      expected = expectation
      candidates = servers.filter(\.supportsInAppPlayback)
      guard !candidates.isEmpty else { throw PlaybackError.noEmbyServer }
    case .serverItem(let serverName, let id):
      itemID = id
      expected = nil
      guard let server = servers.first(where: { $0.name == serverName }) else {
        throw PlaybackError.noEmbyServer
      }
      guard server.supportsInAppPlayback else {
        throw server.type.lowercased() == "emby"
          ? PlaybackError.noEmbyServer : PlaybackError.serverNotSupported(server.name)
      }
      candidates = [server]
    }

    // 媒体库条目逐台找，第一台找到的为准。MoviePilot `/mediaserver/play` 只拿 ID 逐台试、认第一台有这个 ID 的，
    // 这里按外部编号找、核对类型，撞号时不播错片，各台 ID 不同也能找到。
    let strict = servers.filter(\.isEnabled).count > 1
    var firstError: Error?
    for server in candidates {
      do {
        let prepared = try await withConnection(to: server, preferredUserName: preferredUserName) {
          connection -> PreparedPlayback? in
          let found: EmbyItem?
          if let expected {
            found = try await Self.findLibraryItem(itemID, expected: expected, strict: strict, on: connection)
          } else {
            found = try await connection.client.item(
              id: itemID, userID: connection.userID, timeout: EmbyClient.quickTimeout)
          }
          guard let item = found else { return nil }
          return try await Self.preparePlayback(client: connection.client, userID: connection.userID, item: item)
        }
        if let prepared { return prepared }
      } catch let error where error is CancellationError {
        throw error
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    throw firstError ?? PlaybackError.notFound
  }

  private static func preparePlayback(
    client: EmbyClient, userID: String, item requested: EmbyItem, preferredSourceID: String? = nil
  ) async throws -> PreparedPlayback {
    // 剧集先简单处理：从第 1 季第 1 集开始。
    let item: EmbyItem
    switch requested.type {
    case "Movie", "Episode":
      item = requested
    case "Series":
      let episodes = try await client.episodes(seriesID: requested.id, userID: userID)
      guard let first = EmbyEpisodeOrder.firstEpisode(in: episodes) else {
        throw PlaybackError.noEpisodes
      }
      item = first
    default:
      throw PlaybackError.unsupportedItemType
    }
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
    return PreparedPlayback(
      client: client, userID: userID, item: item, selection: selection,
      playSessionID: info.playSessionID, streamURL: streamURL, mediaSources: info.mediaSources)
  }

  // MARK: - 连接

  /// 用缓存的连接执行；地址连不上时（如离开了内网）重新探测一次再执行。
  private func withConnection<T>(
    to server: MediaServerConf, preferredUserName: String?,
    _ body: (EmbyConnection) async throws -> T
  ) async throws -> T {
    do {
      return try await body(try await connection(to: server, preferredUserName: preferredUserName))
    } catch EmbyClientError.unreachable {
      try Task.checkCancellation()
    }
    return try await body(
      try await connection(to: server, preferredUserName: preferredUserName, forceRefresh: true))
  }

  /// 取缓存的连接；缓存是按旧配置或旧 MoviePilot 用户名建立的，就重新连接。
  private func connection(
    to server: MediaServerConf, preferredUserName: String?, forceRefresh: Bool = false
  ) async throws -> EmbyConnection {
    guard let config = server.config, config.apiKey != nil else { throw PlaybackError.noEmbyServer }
    let validate = { [weak self] in
      try Task.checkCancellation()
      guard self?.isTornDown == false else { throw CancellationError() }
    }
    let load: @MainActor () async throws -> EmbyConnection = { [weak self] in
      guard let self else { throw CancellationError() }
      return try await self.connect(server, config: config, preferredUserName: preferredUserName)
    }
    let cached = try await connections.value(
      for: server.name, forceRefresh: forceRefresh, validate: validate, load: load)
    guard !forceRefresh, cached.config != config || cached.preferredUserName != preferredUserName else {
      return cached
    }
    return try await connections.value(for: server.name, forceRefresh: true, validate: validate, load: load)
  }

  /// 同时探测内网和外网地址（内网优先），再按 MoviePilot 的规则选 Emby 用户。
  private func connect(
    _ server: MediaServerConf, config: MediaServerConnectionConfig, preferredUserName: String?
  ) async throws -> EmbyConnection {
    guard let apiKey = config.apiKey else { throw PlaybackError.noEmbyServer }
    let clients = config.candidateBaseURLs.map {
      EmbyClient(baseURL: $0, apiKey: apiKey, session: embySession)
    }
    let probe = await PreferredReachability.first(of: clients, grace: Self.preferredAddressGrace) {
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
    let users = try await client.users()
    guard let user = EmbyUser.select(from: users, preferredNames: [config.username, preferredUserName]) else {
      throw PlaybackError.noEmbyUser
    }
    return EmbyConnection(
      config: config, preferredUserName: preferredUserName, client: client, userID: user.id)
  }

  // MARK: - 播放

  private func start(_ prepared: PreparedPlayback, at position: Double) {
    let session = PlaybackSession(prepared: prepared, startPosition: position)
    session.onFailure = { [weak self, weak session] message in
      guard let self, let session else { return }
      self.endSession(session)
      self.failure = Failure(message: message)
    }
    phase = .playing(session)
  }

  // MARK: - 播放中换集、换版本

  /// 在当前 mpv 播放界面里改播另一集或另一个版本（对应 Swiftfin 的 `playNewItem`）。
  /// 沿用当前会话的 Emby 客户端和用户，为新条目重新取 PlaybackInfo、选版本；成功后会话换成新条目，
  /// 上一条目照常上报停止，播放界面随后起播新条目。新的切换会取代仍在进行的切换，被取代的不再回报。
  func switchItem(
    to itemID: String, mediaSourceID: String? = nil, startPosition: Double = 0,
    in session: PlaybackSession, completion: @escaping (SwitchResult) -> Void = { _ in }
  ) {
    guard let apiService, isPlaying(session) else {
      completion(.discarded)
      return
    }
    let snapshot = apiService.sessionSnapshot()
    switchTask?.cancel()
    switchTask = Task { [weak self] in
      let outcome: Result<PreparedPlayback, Error>
      do {
        guard let item = try await session.client.item(id: itemID, userID: session.userID) else {
          throw PlaybackError.notFound
        }
        outcome = .success(
          try await Self.preparePlayback(
            client: session.client, userID: session.userID, item: item, preferredSourceID: mediaSourceID))
      } catch {
        outcome = .failure(error)
      }
      // 取消只来自新的切换、结束会话或登出：`switchTask` 已归新任务或已清空。
      guard let self, !Task.isCancelled else { return }
      self.switchTask = nil
      let result: SwitchResult
      if !self.isPlaying(session) || self.apiService?.isSessionUnchanged(from: snapshot) != true {
        result = .discarded
      } else {
        switch outcome {
        case .success(let prepared):
          session.replaceItem(with: prepared, startPosition: startPosition)
          result = .switched
        case .failure(let error) where error is CancellationError:
          result = .discarded
        case .failure(let error):
          let message = (error as? LocalizedError)?.errorDescription ?? "播放失败"
          Logger.warning("[Playback] 切换条目失败: \(message)")
          result = .failed(message)
        }
      }
      completion(result)
    }
  }

  private func fail(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? "播放失败"
    Logger.error("[Playback] 应用内播放失败: \(message)")
    failure = Failure(message: message)
  }
}

/// 同时探测多个候选，按给定顺序优先：排在前面的连通即用；后面的先连通时，再给前面仍在探测的候选一段宽限，
/// 到时取已连通里最靠前的。全部失败时返回各候选的错误。
nonisolated enum PreferredReachability {
  struct Failures: Error {
    let errors: [any Error]
  }

  private enum ProbeState {
    case pending
    case reachable
    case failed(any Error)
  }

  private enum Event: Sendable {
    case probed(Int, (any Error)?)
    case graceElapsed
  }

  static func first<Candidate: Sendable>(
    of candidates: [Candidate], grace: Duration,
    probe: @escaping @Sendable (Candidate) async throws -> Void
  ) async -> Result<Candidate, Failures> {
    await withTaskGroup(of: Event.self) { group in
      for (index, candidate) in candidates.enumerated() {
        group.addTask {
          do {
            try await probe(candidate)
            return .probed(index, nil)
          } catch {
            return .probed(index, error)
          }
        }
      }
      var states = [ProbeState](repeating: .pending, count: candidates.count)
      var isGraceStarted = false
      var isGraceElapsed = false
      while let event = await group.next() {
        switch event {
        case .probed(let index, .none): states[index] = .reachable
        case .probed(let index, .some(let error)): states[index] = .failed(error)
        case .graceElapsed: isGraceElapsed = true
        }
        var waitsForEarlier = false
        scan: for (index, state) in states.enumerated() {
          switch state {
          case .pending:
            waitsForEarlier = true
          case .failed:
            continue
          case .reachable:
            if !waitsForEarlier || isGraceElapsed {
              group.cancelAll()
              return .success(candidates[index])
            }
            if !isGraceStarted {
              isGraceStarted = true
              group.addTask {
                try? await Task.sleep(for: grace)
                return .graceElapsed
              }
            }
            break scan
          }
        }
      }
      return .failure(
        Failures(
          errors: states.compactMap {
            guard case .failed(let error) = $0 else { return nil }
            return error
          }))
    }
  }
}

/// 一次全屏播放：持有 mpv 播放器，负责起播位置、进度上报和收尾。播放中换集、换版本只替换条目，界面不重新弹出。
/// `stop()` 可重复调用。
@MainActor
final class PlaybackSession: Identifiable {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  static let progressInterval: Double = 10

  /// mpv 默认优先选中文字幕；没有中文字幕时按片源默认轨道。
  /// 杜比数字（AC-3 / E-AC-3）由 mpv 解码成 PCM，不原样交给系统：MPVUI 的原样输出没在真实设备和 Atmos 上验证过，
  /// 带 Atmos 的 E-AC-3 经 HomePod 播放时没有声音，也没有回退。代价是不输出 Atmos 对象，5.1 等多声道照常。
  static let mpvConfiguration = MPVPlayerConfiguration(
    additionalOptions: ["slang": "chi,zho,zh,chs,cht,sc,tc,cn,zh-Hans,zh-Hant"].merging(
      subtitleFontOptions, uniquingKeysWith: { current, _ in current }),
    audio: MPVAudioConfiguration(dolbyDecoding: .software),
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

  let id = UUID()
  /// 在播放界面出现时创建，未展示就不启动解码。
  private(set) var mpvPlayer: MPVPlayer?
  /// mpv 播放出错时回调提示文字。正常播完由播放界面处理（自动播下一集或退出）。
  var onFailure: ((String) -> Void)?

  private var prepared: PreparedPlayback
  private var startPosition: Double
  /// 当前条目已交给 mpv；换条目后等播放界面再次调用 `start()`。
  private var isItemLoaded = false
  private(set) var isStopped = false
  private var lastReportedPause = false
  private var mpvEventTask: Task<Void, Never>?
  private var mpvProgressTask: Task<Void, Never>?
  /// 最后排进队的上报。同一次播放的开始、进度、暂停/继续、停止和观看进度写回按顺序逐条发送：
  /// 各自另起请求时，后发的停止可能先到 Emby，后台就一直显示“正在播放”，或停止后又收到旧进度。
  private var lastReport: Task<Void, Never>?

  init(prepared: PreparedPlayback, startPosition: Double) {
    self.prepared = prepared
    self.startPosition = startPosition
  }

  /// 直连原文件的地址，含密钥，不得写入日志。
  var streamURL: URL { prepared.streamURL }
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

  /// 起播当前条目：播放界面出现时，以及换条目后各调用一次。
  func start() {
    guard !isStopped, !isItemLoaded else { return }
    let player = makeMPVPlayer()
    if mpvEventTask == nil { observe(player) }
    player.load(
      streamURL, playAutomatically: true,
      startTime: startPosition > 0 ? .milliseconds(Int64(startPosition * 1000)) : nil)
    itemDidLoad()
  }

  /// 当前条目已交给 mpv：上报开始，之后的暂停、进度和停止也要上报。
  private func itemDidLoad() {
    isItemLoaded = true
    report(.start, isPaused: false, position: startPosition)
  }

  /// 测试用：不启动 mpv，直接进入条目已交给 mpv 之后的上报流程。
  func itemDidLoadForTesting() { itemDidLoad() }

  /// 测试用：等已排队的上报全部发完。
  var pendingReportsForTesting: Task<Void, Never>? { lastReport }

  /// 换成另一集或另一个版本：当前条目照常上报停止并保存进度，新条目等播放界面调用 `start()` 后起播。
  func replaceItem(with next: PreparedPlayback, startPosition: Double) {
    guard !isStopped else { return }
    endCurrentItem()
    mpvPlayer?.stop()
    prepared = next
    self.startPosition = startPosition
    lastReportedPause = false
  }

  func stop() {
    guard !isStopped else { return }
    isStopped = true
    endCurrentItem()
    mpvEventTask?.cancel()
    mpvEventTask = nil
    mpvProgressTask?.cancel()
    mpvProgressTask = nil
    mpvPlayer?.stop()
    onFailure = nil
  }

  /// 上报当前条目停止并保存观看进度；位置须在 mpv 停止前读取。
  private func endCurrentItem() {
    guard isItemLoaded else { return }
    isItemLoaded = false
    let position = currentSeconds
    let ending = EndedItem(
      userID: prepared.userID,
      itemID: prepared.item.id,
      stopReport: reportBody(isPaused: true, position: position),
      completed: PlaybackResumePolicy.isCompleted(
        positionSeconds: position, runTimeTicks: prepared.item.runTimeTicks),
      positionTicks: EmbyTicks.from(seconds: position),
      playedAt: Date())
    let client = prepared.client
    enqueueReport { await Self.finishItem(ending, client: client) }
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
        if self.isItemLoaded, self.mpvPlayer?.state == .playing {
          self.report(.progress, isPaused: false, position: self.currentSeconds, progressEvent: .timeUpdate)
        }
      }
    }
  }

  /// 处理 mpv 事件（测试也直接调用它模拟 mpv）。
  func handle(_ change: MPVPlaybackEvent.Change) {
    switch change {
    case .stateChanged(.failed(let error)), .error(let error, fatal: true):
      Logger.error("[Playback] mpv 播放失败: \(EmbyClient.redactedForLogging(String(describing: error)))")
      onFailure?("无法播放该影片，请检查与 Emby 的网络连接")
    case .pauseChanged(let isPaused):
      handlePauseChange(isPaused: isPaused)
    default:
      break
    }
  }

  private func handlePauseChange(isPaused: Bool) {
    guard isItemLoaded, isPaused != lastReportedPause else { return }
    lastReportedPause = isPaused
    report(.progress, isPaused: isPaused, position: currentSeconds, progressEvent: isPaused ? .pause : .unpause)
  }

  // MARK: - 上报（同一次播放按顺序逐条发送，调用方不等结果，失败只记日志）

  /// 进度上报的 `EventName`：周期进度为 TimeUpdate，暂停、继续为 Pause、Unpause（省略时 Emby 一律按 TimeUpdate 处理）。
  private enum ProgressEvent: String {
    case timeUpdate = "TimeUpdate"
    case pause = "Pause"
    case unpause = "Unpause"
  }

  private func enqueueReport(_ work: @escaping @MainActor () async -> Void) {
    let previous = lastReport
    lastReport = Task {
      await previous?.value
      await work()
    }
  }

  private func report(
    _ event: EmbyClient.PlaybackEvent, isPaused: Bool, position: Double, progressEvent: ProgressEvent? = nil
  ) {
    var body = reportBody(isPaused: isPaused, position: position)
    if let progressEvent { body["EventName"] = .string(progressEvent.rawValue) }
    let client = prepared.client
    enqueueReport { await Self.send(event, body: body, client: client) }
  }

  private func reportBody(isPaused: Bool, position: Double) -> [String: JSONValue] {
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
    return body
  }

  private static func send(
    _ event: EmbyClient.PlaybackEvent, body: [String: JSONValue], client: EmbyClient
  ) async {
    do {
      try await client.report(event, body: body)
    } catch {
      Logger.warning("[Playback] 播放状态上报失败: \(error.localizedDescription)")
    }
  }

  /// 停止播放的条目：停止上报的内容和要写回的观看进度。
  struct EndedItem {
    let userID: String
    let itemID: String
    let stopReport: [String: JSONValue]
    let completed: Bool
    let positionTicks: Int
    let playedAt: Date
  }

  /// 先上报停止，再写回观看进度。写回前重新读取单条条目的用户数据，只改续播位置、已看完和最后播放时间：
  /// 开播时的条目可能来自剧集列表，Emby 列表里的 `PlayCount` 恒为 0、也没有最后播放时间，整份写回会把真实播放次数改成 0；
  /// 按顺序发也不会盖掉停止上报刚更新的数据。读不到用户数据就不写，不用残缺对象覆盖收藏等字段。
  static func finishItem(_ ending: EndedItem, client: EmbyClient) async {
    await send(.stopped, body: ending.stopReport, client: client)
    do {
      guard let item = try await client.item(id: ending.itemID, userID: ending.userID),
        var userData = item.userData
      else {
        Logger.warning("[Playback] 读不到条目的用户数据，未保存观看进度")
        return
      }
      userData["PlaybackPositionTicks"] = .int(ending.completed ? 0 : ending.positionTicks)
      if ending.completed { userData["Played"] = .bool(true) }
      userData["LastPlayedDate"] = .string(ISO8601DateFormatter().string(from: ending.playedAt))
      try await client.updateUserData(userID: ending.userID, itemID: ending.itemID, userData: userData)
    } catch {
      Logger.warning("[Playback] 保存观看进度失败: \(error.localizedDescription)")
    }
  }
}
