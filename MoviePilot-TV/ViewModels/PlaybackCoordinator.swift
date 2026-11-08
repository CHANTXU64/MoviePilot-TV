import AVFoundation
import Combine
import Foundation
import MPVUI
import UIKit

/// 应用内播放的入口目标。
enum PlaybackTarget: Equatable {
  /// 详情页：MoviePilot 媒体库同步表里的条目 ID，不知道属于哪台服务器，也可能是别的服务器上的 ID。
  /// 起播时在各台可播放的服务器上按 `expected`（类型、外部编号）找条目，见 `PlaybackCoordinator.findLibraryItem`。
  case libraryItem(itemID: String, expected: LibraryItemExpectation)
  /// 已知服务器名称和这台服务器自己的条目 ID（首页“最近添加”，或详情页已在服务器上找到）。
  case serverItem(serverName: String, itemID: String)
  /// 详情页集列表里的一集：在各台可播放的服务器上按 TMDB 单集 ID 找，见 `EpisodeAvailability`。
  case episode(EpisodePlaybackContext, MoviePilotEpisode)
}

enum PlaybackError: LocalizedError, Equatable {
  case notAllowed
  case backendTooOld
  case disabledInSettings
  case noPlayableServer
  case serverNotSupported(String)
  case unreachable(server: String, transportSecurity: Bool)
  case noServerUser(server: String)
  case notFound
  case episodeUnavailable(String)
  case unsupportedItemType
  case noEpisodes
  case unsupported(PlaybackUnsupported)
  case server(String)

  var errorDescription: String? {
    switch self {
    case .notAllowed:
      return "只有管理员账号可以在应用内播放"
    case .backendTooOld:
      return "应用内播放需要 MoviePilot \(InAppPlaybackAvailability.minimumBackendVersion) 及以上版本"
    case .disabledInSettings:
      return "应用内播放已在设置中关闭"
    case .noPlayableServer:
      return "MoviePilot 中没有能在应用内播放的媒体服务器（目前支持 \(MediaServerAdapters.supportedNames)，需启用并填写地址和密钥）"
    case .serverNotSupported(let name):
      return "媒体服务器“\(name)”暂不支持应用内播放，目前只支持 \(MediaServerAdapters.supportedNames)"
    case .unreachable(let server, true):
      return "无法连接“\(server)”：系统不允许连接 http 域名地址，请为媒体服务器配置 https 地址或内网 IP"
    case .unreachable(let server, false):
      return "无法连接“\(server)”，已尝试 MoviePilot 中配置的内网和外网地址"
    case .noServerUser(let server):
      return "在“\(server)”上没有找到可用的用户"
    case .notFound:
      return "未在媒体服务器中找到该条目，可能 MoviePilot 媒体库同步尚未更新"
    case .episodeUnavailable(let message):
      return message
    case .unsupportedItemType:
      return "应用内播放暂只支持电影和剧集"
    case .noEpisodes:
      return "这部剧在媒体服务器中还没有可播放的剧集"
    case .unsupported(let reason):
      return reason.message
    case .server(let message):
      return message
    }
  }
}

/// 按集播放时正在播的这一集，以及开播时冻结的上下文。
struct QueuedEpisode: Equatable, Sendable {
  let context: EpisodePlaybackContext
  let episode: MoviePilotEpisode
}

/// 解析完成、可以交给播放器的结果。
struct PreparedPlayback {
  let connection: any MediaServerConnection
  let stream: PreparedStream
  /// 按集播放时有：播放器标题按详情页的编号显示，上一集、下一集从它往前后找。
  var episode: QueuedEpisode?

  var item: ServerMediaItem { stream.item }
  var streamURL: URL { stream.streamURL }

  var titles: (primary: String, secondary: String?) {
    guard let episode else { return item.playerTitles }
    return episode.episode.playerTitles(seriesName: episode.context.seriesName ?? item.seriesName)
  }

  var title: String { PlaybackTitles.singleLine(titles) }

  var resumePosition: Double? {
    PlaybackResumePolicy.resumePosition(
      positionSeconds: item.resumePositionSeconds, runtimeSeconds: item.runtimeSeconds)
  }
}

/// 播放界面的队列（上一集、下一集、同季列表）从这里取数据。
@MainActor
protocol EpisodeQueueProviding: AnyObject {
  /// `refresh` 时先重新读当前服务器上这部剧的集和当前季的集列表（播完一集要接着播时），不沿用缓存。
  func adjacentEpisode(
    _ direction: EpisodeNavigator.Direction, from playback: PreparedPlayback, refresh: Bool
  ) async throws -> EpisodeNavigator.Outcome
  func playableEpisodes(inSeason season: Int, from playback: PreparedPlayback) async throws -> [EpisodeQueueEntry]
}

/// 应用内播放的唯一 owner。由 `SessionScope` 持有：换账号或登出时随作用域拆除，正在解析的任务取消、播放器停止。
/// 只通过 `MediaServerConnection` 访问媒体服务器，不关心是哪一类服务器。
@MainActor
final class PlaybackCoordinator: ObservableObject, EpisodeQueueProviding {
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

  /// 连接（地址和服务器用户）沿用的时长；到期重新探测、重选用户，服务器端删改用户后能自行恢复。
  static let connectionTTL: TimeInterval = 600
  /// 服务器上一部剧的集索引沿用的时长：详情页的每集状态、起播和上一集/下一集共用，短时间内不重复读整部剧的集。
  static let episodeIndexTTL: TimeInterval = 60
  /// 起播前最多等这么久，让上一次播放的停止上报和进度写回先发完，续播询问才读得到刚保存的位置。
  /// 服务器连不上时不会一直卡在“正在准备播放”。
  static let pendingReportWait: Duration = .seconds(5)

  @Published private(set) var phase: Phase = .idle
  @Published var failure: Failure?
  /// 播放结束时的说明（比如下一集在另一台服务器上），不是错误。
  @Published var notice: Failure?

  /// 弱引用：`APIService` → `SessionScope` → 本对象，强引用会让整个会话在登出后无法释放。
  private weak var apiService: APIService?
  private let mediaServerSession: URLSession
  /// 所有播放会话共用的上报队列：上一次播放的写回不会晚于下一次播放的上报和写回。
  private let reporter = PlaybackReporter()
  private var switchTask: Task<Void, Never>?
  /// 按服务器名称缓存的连接：下次播放不再探测地址、查询用户；同一台同时发起的连接合并为一次。
  private let connections: CoalescingCache<String, any MediaServerConnection>
  private let episodeIndexes: CoalescingCache<String, ServerEpisodeIndex>
  /// 设置页「播放」里的应用内播放开关。
  private let isEnabledInSettings: () -> Bool
  private var isTornDown = false

  init(
    apiService: APIService, mediaServerSession: URLSession = MediaServerHTTP.sharedSession,
    isEnabledInSettings: @escaping () -> Bool = { PlaybackPreferences.isInAppPlaybackEnabled },
    now: @escaping () -> Date = Date.init
  ) {
    self.apiService = apiService
    self.mediaServerSession = mediaServerSession
    self.isEnabledInSettings = isEnabledInSettings
    connections = CoalescingCache(
      ttl: Self.connectionTTL, capacity: 8, renewsTTLOnAccess: false, now: now)
    episodeIndexes = CoalescingCache(
      ttl: Self.episodeIndexTTL, capacity: 16, renewsTTLOnAccess: false, now: now)
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
    var reporterForTesting: PlaybackReporter { reporter }
  #endif

  /// 当前会话能否在应用内播放：管理员、后端版本支持、设置里没关。各入口另外判断媒体类型和服务器。
  private var allowsPlayback: Bool {
    guard let apiService else { return false }
    return apiService.canRequestSuperUserEndpoints
      && InAppPlaybackAvailability.isEnabled(
        backendVersion: apiService.settings?.BACKEND_VERSION, userEnabled: isEnabledInSettings())
  }

  func play(_ target: PlaybackTarget) {
    guard !isTornDown, !isBusy, let apiService else { return }
    guard apiService.canRequestSuperUserEndpoints else {
      fail(PlaybackError.notAllowed)
      return
    }
    guard InAppPlaybackAvailability.supports(backendVersion: apiService.settings?.BACKEND_VERSION) else {
      fail(PlaybackError.backendTooOld)
      return
    }
    guard isEnabledInSettings() else {
      fail(PlaybackError.disabledInSettings)
      return
    }
    // 只在发布结果时复核会话：中间的服务器请求与 MoviePilot 会话无关，换账号时由作用域拆除取消。
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

  /// 播放界面关闭后收尾。只结束给定的会话：界面的关闭回调可能晚于下一次播放开始。
  /// `notice` 是播放结束时要告诉用户的说明（比如下一集在另一台服务器上）。
  func endSession(_ session: PlaybackSession, notice: String? = nil) {
    guard isPlaying(session) else { return }
    switchTask?.cancel()
    switchTask = nil
    phase = .idle
    session.stop()
    if let notice { self.notice = Failure(message: notice) }
  }

  /// App 离开前台（回主屏、打开 App 切换器）时保存正在播放条目的观看进度，播放不结束。
  /// 之后 App 可能被系统回收或被用户关掉，停止上报和写回就再也发不出去；申请一段后台执行时间等写回发完。
  func saveProgressForBackground() {
    guard let session else { return }
    session.saveProgress()
    let reporter = reporter
    BackgroundExecution.run(named: "保存播放进度") { await reporter.waitForQueued() }
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
    episodeIndexes.invalidateAll()
  }

  /// 详情页的条目 ID 不带服务器名，可能来自任何一台媒体服务器，不同服务器的数字 ID 还会撞号（同类服务器之间也会）。
  /// 只启用了一台服务器（且可在应用内播放）时 ID 只可能来自它，不必确认，起播时再找；
  /// 否则在每台可播放的服务器上找这个条目（见 `findLibraryItem`），第一台找到的为准，用它自己的条目 ID。
  /// `preferredServer` 是 MoviePilot 入库查询给的所属服务器，先查它；这个 ID 确定属于它，按 ID 兜底时不要求外部编号对上。
  /// 确认不在任何一台上时返回 nil（不显示播放）；无法确认（连不上等）时仍返回媒体库条目，起播时再逐台找。
  func locateLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, in servers: [MediaServerConf],
    preferredServer: String? = nil
  ) async -> PlaybackTarget? {
    guard !isTornDown, allowsPlayback, let apiService else { return nil }
    let enabled = servers.filter(\.isEnabled)
    let playable = Self.playableServers(in: servers, preferring: preferredServer)
    guard !playable.isEmpty else { return nil }
    let libraryItem = PlaybackTarget.libraryItem(itemID: itemID, expected: expected)
    if enabled.count == 1 { return libraryItem }
    let userName = apiService.currentOrStoredUserName
    var isUncertain = false
    for server in playable {
      do {
        let ownsItem = server.name == preferredServer
        let found = try await withConnection(to: server, preferredUserName: userName) {
          try await Self.findLibraryItem(itemID, expected: expected, strict: !ownsItem, on: $0)
        }
        if let found { return .serverItem(serverName: server.name, itemID: found.id) }
      } catch {
        if error is CancellationError || Task.isCancelled { return nil }
        isUncertain = true
      }
    }
    return isUncertain ? libraryItem : nil
  }

  /// 可在应用内播放的服务器，`preferring` 指定的排在最前，其余保持 MoviePilot 配置顺序。
  private static func playableServers(in servers: [MediaServerConf], preferring name: String?) -> [MediaServerConf] {
    let playable = servers.filter(\.supportsInAppPlayback)
    guard let name, let index = playable.firstIndex(where: { $0.name == name }) else { return playable }
    var ordered = playable
    ordered.insert(ordered.remove(at: index), at: 0)
    return ordered
  }

  /// 在一台服务器上找详情页的条目，返回这台服务器自己的条目（ID 可能与 MoviePilot 给的不同）。
  /// 先按外部编号搜索，同一部片在各台服务器上的 ID 不同也能找到；搜不到再看 MoviePilot 给的 ID 在这台上是不是它。
  /// `strict`（启用了多台服务器）时外部编号必须对得上，见 `LibraryItemExpectation.accepts`。
  private static func findLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, strict: Bool, on connection: any MediaServerConnection
  ) async throws -> ServerMediaItem? {
    let found = try await connection.items(matching: expected)
    if let item = found.first(where: { expected.accepts($0, strict: true) }) { return item }
    guard let item = try await connection.item(id: itemID, timeout: MediaServerHTTP.quickTimeout) else { return nil }
    return expected.accepts(item, strict: strict) ? item : nil
  }

  // MARK: - 按集播放

  /// 详情页每一集能不能播，与 `episodes` 一一对应：在各台可播放的服务器上按 TMDB 单集 ID 找，第一台有的为准。
  /// 不提供应用内播放（非管理员、后端版本过低、没有可播放的服务器）时返回 nil，详情页不显示播放状态。
  /// 结果不含会话校验，调用方在发布时复核会话。
  /// `forceRefresh` 时重新读各服务器上这部剧的集（比如重新进入详情页），不沿用缓存。
  func episodeAvailability(
    for episodes: [MoviePilotEpisode], context: EpisodePlaybackContext, forceRefresh: Bool = false
  ) async -> [EpisodeAvailability]? {
    guard !isTornDown, allowsPlayback, let apiService else { return nil }
    let servers: [MediaServerConf]
    do {
      servers = try await apiService.fetchCachedMediaServers()
    } catch {
      if error is CancellationError || Task.isCancelled { return nil }
      return episodes.map { _ in .failed("读取媒体服务器配置失败") }
    }
    guard servers.contains(where: \.supportsInAppPlayback) else { return nil }
    let lookups = await episodeLookups(
      context, servers: servers, preferredUserName: apiService.currentOrStoredUserName, forceRefresh: forceRefresh)
    guard !Task.isCancelled else { return nil }
    return episodes.map { EpisodeAvailability.resolve($0, lookups: lookups) }
  }

  /// 在每台可播放的服务器上读这部剧的集索引，单台失败只记在它自己的结果里。
  private func episodeLookups(
    _ context: EpisodePlaybackContext, servers: [MediaServerConf], preferredUserName: String?,
    excluding excluded: String? = nil, forceRefresh: Bool = false
  ) async -> [ServerEpisodeLookup] {
    let strict = servers.filter(\.isEnabled).count > 1
    var lookups: [ServerEpisodeLookup] = []
    for server in Self.playableServers(in: servers, preferring: context.libraryItem?.server)
    where server.name != excluded {
      do {
        let index = try await withConnection(to: server, preferredUserName: preferredUserName) {
          try await self.episodeIndex(context, on: $0, strict: strict, forceRefresh: forceRefresh)
        }
        lookups.append(.loaded(index))
      } catch {
        if error is CancellationError || Task.isCancelled { return lookups }
        lookups.append(.failed(server: server.name, message: Self.message(for: error)))
      }
    }
    return lookups
  }

  /// 一台服务器上这部剧的集索引：找出全部对得上的整剧条目（同一部剧可能在多个媒体库里各有一个），读它们的集。
  private func episodeIndex(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, strict: Bool,
    forceRefresh: Bool = false
  ) async throws -> ServerEpisodeIndex {
    let key = [
      connection.serverName, connection.reportingServer.absoluteString, connection.userID, context.seriesLookupKey,
      strict ? "strict" : "",
    ].joined(separator: "|")
    return try await episodeIndexes.value(for: key, forceRefresh: forceRefresh, validate: validateNotTornDown) {
      let series = try await Self.seriesItems(context, on: connection, strict: strict)
      var episodes: [ServerMediaItem] = []
      for item in series {
        episodes += try await connection.episodes(seriesID: item.id)
      }
      return ServerEpisodeIndex(serverName: connection.serverName, hasSeries: !series.isEmpty, episodes: episodes)
    }
  }

  private static func seriesItems(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, strict: Bool
  ) async throws -> [ServerMediaItem] {
    var series = try await connection.items(matching: context.expected).filter {
      context.expected.accepts($0, strict: true)
    }
    // 按外部编号搜不到（或服务器不支持这类搜索）时，在入库条目所属的服务器上按 MoviePilot 给的 ID 再找。
    // 已知 ID 属于这台服务器时不要求外部编号对上（Emby 没刮到编号也能认）；不知道属于哪台时多台服务器下要对上，防撞号。
    if let ref = context.libraryItem, ref.server == nil || ref.server == connection.serverName,
      !series.contains(where: { $0.id == ref.itemID }),
      let item = try await connection.item(id: ref.itemID, timeout: MediaServerHTTP.quickTimeout),
      context.expected.accepts(item, strict: ref.server == connection.serverName ? false : strict)
    {
      series.append(item)
    }
    return series
  }

  private func prepareEpisode(
    _ context: EpisodePlaybackContext, _ episode: MoviePilotEpisode, servers: [MediaServerConf],
    preferredUserName: String?
  ) async throws -> PreparedPlayback {
    guard let tmdbEpisodeID = episode.tmdbEpisodeID else {
      throw PlaybackError.episodeUnavailable(EpisodeAvailability.UnidentifiableReason.missingEpisodeID.message)
    }
    let candidates = Self.playableServers(in: servers, preferring: context.libraryItem?.server)
    guard !candidates.isEmpty else { throw PlaybackError.noPlayableServer }
    let strict = servers.filter(\.isEnabled).count > 1
    var lookups: [ServerEpisodeLookup] = []
    var firstError: Error?
    let queued = QueuedEpisode(context: context, episode: episode)
    for server in candidates {
      do {
        let (connection, cached) = try await withConnection(to: server, preferredUserName: preferredUserName) {
          connection in (connection, try await self.episodeIndex(context, on: connection, strict: strict))
        }
        var index = cached
        if index.playableEpisodes(tmdbEpisodeID: tmdbEpisodeID).isEmpty {
          // 缓存的集索引里没有：可能是刚入库的集，重新读一次这台服务器再下结论。
          index = try await episodeIndex(context, on: connection, strict: strict, forceRefresh: true)
        }
        lookups.append(.loaded(index))
        if let prepared = try await Self.prepareFirstPlayable(
          index.playableEpisodes(tmdbEpisodeID: tmdbEpisodeID), on: connection, episode: queued)
        {
          return prepared
        }
      } catch let error where error is CancellationError {
        throw error
      } catch {
        if firstError == nil { firstError = error }
        lookups.append(.failed(server: server.name, message: Self.message(for: error)))
      }
    }
    if let firstError { throw firstError }
    switch EpisodeAvailability.resolve(episode, lookups: lookups) {
    case .unidentifiable(let reason): throw PlaybackError.episodeUnavailable(reason.message)
    default: throw PlaybackError.episodeUnavailable("没有在媒体服务器上找到这一集")
    }
  }

  /// 同一集在一台服务器上的各个条目（不同媒体库各一个）逐个试：先重新读条目，续播点以服务器此刻为准；
  /// 能直连的为准，远程链接（strm）等不能直连的换下一个。都不能直连时报第一个原因；条目都已不在时返回 nil。
  private static func prepareFirstPlayable(
    _ candidates: [ServerMediaItem], on connection: any MediaServerConnection, episode: QueuedEpisode,
    preferredSourceID: String? = nil
  ) async throws -> PreparedPlayback? {
    var unsupported: PlaybackError?
    for candidate in candidates {
      guard let fresh = try await connection.item(id: candidate.id, timeout: nil) else { continue }
      do {
        return try await preparePlayback(
          fresh, on: connection, preferredSourceID: preferredSourceID, episode: episode)
      } catch PlaybackError.unsupported(let reason) {
        if unsupported == nil { unsupported = .unsupported(reason) }
      }
    }
    if let unsupported { throw unsupported }
    return nil
  }

  /// 同一集在这台服务器上除 `itemID` 外的条目，换集时作后备。读不到集索引时没有后备。
  private func episodeAlternates(
    _ queued: QueuedEpisode, excluding itemID: String, on connection: any MediaServerConnection
  ) async -> [ServerMediaItem] {
    guard let tmdbEpisodeID = queued.episode.tmdbEpisodeID, let apiService,
      let servers = try? await apiService.fetchCachedMediaServers(),
      let index = try? await episodeIndex(
        queued.context, on: connection, strict: servers.filter(\.isEnabled).count > 1)
    else { return [] }
    return index.playableEpisodes(tmdbEpisodeID: tmdbEpisodeID).filter { $0.id != itemID }
  }

  // MARK: - 播放队列（上一集、下一集）

  func adjacentEpisode(
    _ direction: EpisodeNavigator.Direction, from playback: PreparedPlayback, refresh: Bool = false
  ) async throws -> EpisodeNavigator.Outcome {
    guard let queued = playback.episode else { return .end }
    if refresh {
      // 播完一集要接着播时重新读一次：播放期间下一集可能刚入库（订阅还在下载后面的集），不能沿用开播时的结果。
      // 只刷新当前服务器和当前季，之后的查找照常走缓存（刚刷新过）。刷新失败时照常用缓存判断。
      do {
        let servers = try await apiService?.fetchCachedMediaServers() ?? []
        _ = try await episodeIndex(
          queued.context, on: playback.connection, strict: servers.filter(\.isEnabled).count > 1,
          forceRefresh: true)
        _ = try await moviePilotEpisodes(queued.context, season: queued.episode.seasonNumber, forceRefresh: true)
      } catch let error where !(error is CancellationError) {
        Logger.warning("[Playback] 重新读取剧集失败: \(Self.message(for: error))")
      }
    }
    return try await EpisodeNavigator.adjacent(
      direction, from: queued.episode, currentItemID: playback.item.id, seasons: queued.context.seasons,
      loadSeason: { [weak self] season in
        guard let self else { throw CancellationError() }
        return try await self.moviePilotEpisodes(queued.context, season: season)
      },
      status: { [weak self] episode in
        guard let self else { throw CancellationError() }
        return try await self.queueStatus(episode, context: queued.context, current: playback.connection)
      })
  }

  func playableEpisodes(inSeason season: Int, from playback: PreparedPlayback) async throws -> [EpisodeQueueEntry] {
    guard let queued = playback.episode else { return [] }
    let list = try await moviePilotEpisodes(queued.context, season: season)
    return try await EpisodeNavigator.playableEntries(in: list) { [weak self] episode in
      guard let self else { throw CancellationError() }
      return try await self.queueStatus(episode, context: queued.context, current: playback.connection)
    }
  }

  private func moviePilotEpisodes(
    _ context: EpisodePlaybackContext, season: Int, forceRefresh: Bool = false
  ) async throws -> [MoviePilotEpisode] {
    guard let apiService else { throw CancellationError() }
    let episodes = try await apiService.fetchTmdbEpisodes(
      tmdbID: context.tmdbID, season: season, episodeGroup: context.episodeGroup, forceRefresh: forceRefresh)
    return MoviePilotEpisode.list(episodes, season: season)
  }

  /// 先只看当前服务器：下一集多半就在这里，不必连其他服务器；当前服务器上没有时，再看其他服务器以区分“在别处”和“确认没有”。
  private func queueStatus(
    _ episode: MoviePilotEpisode, context: EpisodePlaybackContext, current: any MediaServerConnection
  ) async throws -> EpisodeQueueStatus {
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    let strict = servers.filter(\.isEnabled).count > 1
    let currentLookup: ServerEpisodeLookup
    do {
      currentLookup = .loaded(try await episodeIndex(context, on: current, strict: strict))
    } catch let error where !(error is CancellationError) {
      currentLookup = .failed(server: current.serverName, message: Self.message(for: error))
    }
    let onCurrent = EpisodeQueueStatus.resolve(episode, currentServer: current.serverName, lookups: [currentLookup])
    if case .playable = onCurrent { return onCurrent }
    let others = await episodeLookups(
      context, servers: servers, preferredUserName: apiService.currentOrStoredUserName, excluding: current.serverName)
    try Task.checkCancellation()
    return EpisodeQueueStatus.resolve(episode, currentServer: current.serverName, lookups: [currentLookup] + others)
  }

  // MARK: - 解析

  private func isPlaying(_ session: PlaybackSession) -> Bool {
    guard case .playing(let current) = phase else { return false }
    return current === session
  }

  /// 媒体服务器配置很少变化，平时用会话缓存；解析失败时重新读一次，
  /// 地址、密钥或服务器列表确实变了才用新配置重试，没变就原样报告失败。
  private func prepare(_ target: PlaybackTarget, preferredUserName: String?) async throws -> PreparedPlayback {
    await reporter.waitForQueued(atMost: Self.pendingReportWait)
    try Task.checkCancellation()
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
      guard !candidates.isEmpty else { throw PlaybackError.noPlayableServer }
    case .serverItem(let serverName, let id):
      itemID = id
      expected = nil
      guard let server = servers.first(where: { $0.name == serverName }) else {
        throw PlaybackError.noPlayableServer
      }
      guard server.supportsInAppPlayback else {
        throw MediaServerAdapters.supportsInAppPlayback(type: server.type)
          ? PlaybackError.noPlayableServer : PlaybackError.serverNotSupported(server.name)
      }
      candidates = [server]
    case .episode(let context, let episode):
      return try await prepareEpisode(context, episode, servers: servers, preferredUserName: preferredUserName)
    }

    // 媒体库条目逐台找，第一台找到的为准。MoviePilot `/mediaserver/play` 只拿 ID 逐台试、认第一台有这个 ID 的，
    // 这里按外部编号找、核对类型，撞号时不播错片，各台 ID 不同也能找到。
    let strict = servers.filter(\.isEnabled).count > 1
    var firstError: Error?
    for server in candidates {
      do {
        let prepared = try await withConnection(to: server, preferredUserName: preferredUserName) {
          connection -> PreparedPlayback? in
          let found: ServerMediaItem?
          if let expected {
            found = try await Self.findLibraryItem(itemID, expected: expected, strict: strict, on: connection)
          } else {
            found = try await connection.item(id: itemID, timeout: MediaServerHTTP.quickTimeout)
          }
          guard let item = found else { return nil }
          return try await Self.preparePlayback(item, on: connection)
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

  /// 电影、单集直接播；整部剧从第一集开始（不带集列表上下文，没有上一集、下一集）。
  private static func preparePlayback(
    _ requested: ServerMediaItem, on connection: any MediaServerConnection, preferredSourceID: String? = nil,
    episode: QueuedEpisode? = nil
  ) async throws -> PreparedPlayback {
    let item: ServerMediaItem
    switch requested.kind {
    case .movie, .episode:
      item = requested
    case .series:
      let episodes = try await connection.episodes(seriesID: requested.id)
      guard let first = PlaybackEpisodeOrder.firstEpisode(in: episodes) else {
        throw PlaybackError.noEpisodes
      }
      item = first
    case .other:
      throw PlaybackError.unsupportedItemType
    }
    let stream = try await connection.prepareStream(for: item, preferredSourceID: preferredSourceID)
    return PreparedPlayback(connection: connection, stream: stream, episode: episode)
  }

  // MARK: - 连接

  private var validateNotTornDown: () throws -> Void {
    { [weak self] in
      try Task.checkCancellation()
      guard self?.isTornDown == false else { throw CancellationError() }
    }
  }

  /// 用缓存的连接执行；地址连不上时（如离开了内网）重新探测一次再执行。
  private func withConnection<T>(
    to server: MediaServerConf, preferredUserName: String?,
    _ body: (any MediaServerConnection) async throws -> T
  ) async throws -> T {
    do {
      return try await body(try await connection(to: server, preferredUserName: preferredUserName))
    } catch let error as MediaServerReachabilityError where error.isUnreachable {
      try Task.checkCancellation()
    }
    return try await body(
      try await connection(to: server, preferredUserName: preferredUserName, forceRefresh: true))
  }

  /// 取缓存的连接；缓存是按旧配置或旧 MoviePilot 用户名建立的，就重新连接。
  private func connection(
    to server: MediaServerConf, preferredUserName: String?, forceRefresh: Bool = false
  ) async throws -> any MediaServerConnection {
    guard let config = server.config, config.apiKey != nil,
      let connector = MediaServerAdapters.connector(for: server.type)
    else { throw PlaybackError.noPlayableServer }
    let session = mediaServerSession
    let load: @MainActor () async throws -> any MediaServerConnection = {
      try await connector.connect(
        server: server, config: config, preferredUserName: preferredUserName, session: session)
    }
    let cached = try await connections.value(
      for: server.name, forceRefresh: forceRefresh, validate: validateNotTornDown, load: load)
    guard !forceRefresh, cached.config != config || cached.preferredUserName != preferredUserName else {
      return cached
    }
    return try await connections.value(
      for: server.name, forceRefresh: true, validate: validateNotTornDown, load: load)
  }

  // MARK: - 播放

  private func start(_ prepared: PreparedPlayback, at position: Double) {
    let session = PlaybackSession(prepared: prepared, startPosition: position, reporter: reporter)
    session.episodeQueue = self
    session.onFailure = { [weak self, weak session] message in
      guard let self, let session else { return }
      self.endSession(session)
      self.failure = Failure(message: message)
    }
    phase = .playing(session)
  }

  // MARK: - 播放中换集、换版本

  /// 在当前 mpv 播放界面里改播另一集或另一个版本（对应 Swiftfin 的 `playNewItem`）。
  /// 沿用当前会话的服务器连接，为新条目重新取播放信息、选版本；成功后会话换成新条目，
  /// 上一条目照常上报停止，播放界面随后起播新条目。新的切换会取代仍在进行的切换，被取代的不再回报。
  /// `episode` 是详情页集列表里的那一集（按集播放时），沿用当前会话冻结的上下文。
  func switchItem(
    to itemID: String, mediaSourceID: String? = nil, startPosition: Double = 0, episode: MoviePilotEpisode? = nil,
    in session: PlaybackSession, completion: @escaping (SwitchResult) -> Void = { _ in }
  ) {
    guard let apiService, isPlaying(session) else {
      completion(.discarded)
      return
    }
    let snapshot = apiService.sessionSnapshot()
    let connection = session.connection
    let queued = episode.flatMap { episode in
      session.episode.map { QueuedEpisode(context: $0.context, episode: episode) }
    }
    switchTask?.cancel()
    switchTask = Task { [weak self] in
      let outcome: Result<PreparedPlayback, Error>
      do {
        if let queued, mediaSourceID == nil {
          // 换到另一集：同一集在这台服务器上的其他条目作后备，第一个是远程链接时换下一个。
          let alternates = await self?.episodeAlternates(queued, excluding: itemID, on: connection) ?? []
          let requested = ServerMediaItem(id: itemID, kind: .episode)
          guard
            let prepared = try await Self.prepareFirstPlayable(
              [requested] + alternates, on: connection, episode: queued)
          else { throw PlaybackError.notFound }
          outcome = .success(prepared)
        } else {
          guard let item = try await connection.item(id: itemID, timeout: nil) else {
            throw PlaybackError.notFound
          }
          outcome = .success(
            try await Self.preparePlayback(
              item, on: connection, preferredSourceID: mediaSourceID, episode: queued))
        }
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
          let message = Self.message(for: error)
          Logger.warning("[Playback] 切换条目失败: \(message)")
          result = .failed(message)
        }
      }
      completion(result)
    }
  }

  private static func message(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? "播放失败"
  }

  private func fail(_ error: Error) {
    let message = Self.message(for: error)
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

  /// mpv 默认优先选中文字幕；没有中文字幕时按片源默认轨道。杜比数字的解码方式见 `dolbyDecoding(for:)`。
  static func mpvConfiguration(dolbyDecoding: MPVAudioConfiguration.DolbyDecoding) -> MPVPlayerConfiguration {
    MPVPlayerConfiguration(
      additionalOptions: ["slang": "chi,zho,zh,chs,cht,sc,tc,cn,zh-Hans,zh-Hant"].merging(
        subtitleFontOptions, uniquingKeysWith: { current, _ in current }),
      audio: MPVAudioConfiguration(dolbyDecoding: dolbyDecoding),
      automaticallyPlays: true
    )
  }

  /// 杜比数字（AC-3 / E-AC-3）按创建播放器时的音频输出决定怎么解码。经 HDMI（电视、功放、回音壁）原样交给系统，
  /// 保留 Atmos；其他输出（HomePod 等 AirPlay、蓝牙）和读不到输出时由 mpv 解码成 PCM：MPVUI 原样输出带 Atmos 的
  /// E-AC-3 时，经 HomePod 没有声音，也不回退。播放中途换输出不会重新判断。
  nonisolated static func dolbyDecoding(for outputs: [AVAudioSession.Port]) -> MPVAudioConfiguration.DolbyDecoding {
    outputs.contains(.HDMI) ? .automatic : .software
  }

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
  /// 按集播放时，播放界面的队列从这里取上一集、下一集和同季列表。
  weak var episodeQueue: (any EpisodeQueueProviding)?

  private var prepared: PreparedPlayback
  private var startPosition: Double
  /// 当前条目已交给 mpv；换条目后等播放界面再次调用 `start()`。
  private var isItemLoaded = false
  private(set) var isStopped = false
  private var lastReportedPause = false
  private var mpvEventTask: Task<Void, Never>?
  private var mpvProgressTask: Task<Void, Never>?
  /// 开始、进度、停止和观看进度写回都排进协调器的队列，按顺序发送，见 `PlaybackReporter`。
  private let reporter: PlaybackReporter

  init(prepared: PreparedPlayback, startPosition: Double, reporter: PlaybackReporter) {
    self.prepared = prepared
    self.startPosition = startPosition
    self.reporter = reporter
  }

  /// 直连原文件的地址，可能含密钥，不得写入日志。
  var streamURL: URL { prepared.streamURL }
  var titles: (primary: String, secondary: String?) { prepared.titles }
  /// 以下供播放界面的信息、章节、队列等面板使用。
  var playback: PreparedPlayback { prepared }
  var connection: any MediaServerConnection { prepared.connection }
  var userID: String { prepared.connection.userID }
  var item: ServerMediaItem { prepared.item }
  var episode: QueuedEpisode? { prepared.episode }
  var mediaSource: ServerMediaSource { prepared.stream.source }
  var mediaSources: [ServerMediaSource] { prepared.stream.sources }
  var startSeconds: Double { startPosition }

  func makeMPVPlayer() -> MPVPlayer {
    if let mpvPlayer { return mpvPlayer }
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
    let player = MPVPlayer(configuration: Self.mpvConfiguration(dolbyDecoding: Self.dolbyDecoding(for: outputs)))
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

  /// 上报当前条目停止并保存观看进度；位置和时长须在 mpv 停止前读取。
  private func endCurrentItem() {
    guard isItemLoaded else { return }
    isItemLoaded = false
    let position = currentSeconds
    let ending = EndedItem(stream: prepared.stream, positionSeconds: position, progress: watchProgress(at: position))
    let connection = prepared.connection
    reporter.enqueue(.finish, for: reportedItem) { await Self.finishItem(ending, connection: connection) }
  }

  /// 不结束播放，只写回当前条目的观看进度（App 离开前台时）。
  func saveProgress() {
    guard !isStopped, isItemLoaded else { return }
    let progress = watchProgress(at: currentSeconds)
    let connection = prepared.connection
    reporter.enqueue(.saveProgress, for: reportedItem) {
      await Self.saveWatchProgress(progress, connection: connection)
    }
  }

  private var reportedItem: PlaybackReporter.Item {
    PlaybackReporter.Item(
      server: prepared.connection.reportingServer, userID: prepared.connection.userID, itemID: prepared.item.id)
  }

  private func watchProgress(at position: Double) -> WatchProgress {
    let playerDuration = mpvPlayer.map { $0.duration.seconds }
    return WatchProgress(
      itemID: prepared.item.id,
      completed: PlaybackResumePolicy.isCompleted(
        positionSeconds: position, runtimeSeconds: prepared.item.runtimeSeconds,
        playerDurationSeconds: playerDuration),
      positionSeconds: position,
      playedAt: Date())
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
          self.report(.progress(.timeUpdate), isPaused: false, position: self.currentSeconds)
        }
      }
    }
  }

  /// 处理 mpv 事件（测试也直接调用它模拟 mpv）。
  func handle(_ change: MPVPlaybackEvent.Change) {
    switch change {
    case .stateChanged(.failed(let error)), .error(let error, fatal: true):
      Logger.error("[Playback] mpv 播放失败: \(PlaybackLog.redacted(String(describing: error)))")
      onFailure?("无法播放该影片，请检查与媒体服务器的网络连接")
    case .pauseChanged(let isPaused):
      handlePauseChange(isPaused: isPaused)
    default:
      break
    }
  }

  private func handlePauseChange(isPaused: Bool) {
    guard isItemLoaded, isPaused != lastReportedPause else { return }
    lastReportedPause = isPaused
    report(.progress(isPaused ? .pause : .unpause), isPaused: isPaused, position: currentSeconds)
  }

  // MARK: - 上报（排进 `PlaybackReporter` 按顺序发送，调用方不等结果，失败只记日志）

  private func report(_ event: PlaybackReportEvent, isPaused: Bool, position: Double) {
    let stream = prepared.stream
    let connection = prepared.connection
    let kind: PlaybackReporter.Kind = event == .start ? .start : .progress
    reporter.enqueue(kind, for: reportedItem) {
      await Self.send(event, for: stream, positionSeconds: position, isPaused: isPaused, connection: connection)
    }
  }

  private static func send(
    _ event: PlaybackReportEvent, for stream: PreparedStream, positionSeconds: Double, isPaused: Bool,
    connection: any MediaServerConnection
  ) async {
    do {
      try await connection.report(event, for: stream, positionSeconds: positionSeconds, isPaused: isPaused)
    } catch {
      Logger.warning("[Playback] 播放状态上报失败: \(error.localizedDescription)")
    }
  }

  /// 停止播放的条目：停止上报用的流和位置，以及要写回的观看进度。
  struct EndedItem {
    let stream: PreparedStream
    let positionSeconds: Double
    let progress: WatchProgress
  }

  /// 先上报停止，再写回观看进度；按顺序发，写回不会被停止上报刚更新的数据盖掉。
  static func finishItem(_ ending: EndedItem, connection: any MediaServerConnection) async {
    await send(.stopped, for: ending.stream, positionSeconds: ending.positionSeconds, isPaused: true, connection: connection)
    await saveWatchProgress(ending.progress, connection: connection)
  }

  static func saveWatchProgress(_ progress: WatchProgress, connection: any MediaServerConnection) async {
    do {
      try await connection.saveWatchProgress(progress)
    } catch {
      Logger.warning("[Playback] 保存观看进度失败: \(error.localizedDescription)")
    }
  }
}

/// 向媒体服务器发送播放状态上报和观看进度写回的队列。由协调器持有，所有播放会话共用，按排队顺序逐条发送：
/// 同一次播放的开始、进度、停止、写回不会乱序（后发的停止先到，服务器后台就一直显示“正在播放”），
/// 上一次播放的写回也不会晚于下一次播放的写回，把较新的续播点盖回旧值。
/// 每个请求最多等 15 秒（`MediaServerHTTP.sharedSession`），所以不能让积压无限增长：还没发出的进度只留同一条目最新的一条，
/// 排进停止或保存进度时，同一条目还没发出的进度（和更早的保存进度）直接丢弃，停止上报不必排在一串过期进度后面。
@MainActor
final class PlaybackReporter {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  enum Kind {
    case start
    case progress
    /// 只写回观看进度，播放继续。
    case saveProgress
    /// 停止上报和观看进度写回。
    case finish
  }

  /// 上报针对的条目：同一台服务器、同一个服务器用户的同一个条目。
  struct Item: Hashable {
    let server: URL
    let userID: String
    let itemID: String
  }

  private struct Job {
    let sequence: Int
    let kind: Kind
    let item: Item
    let work: @MainActor () async -> Void
  }

  private struct Waiter {
    let id: UUID
    let sequence: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private var pending: [Job] = []
  private var runningSequence: Int?
  private var nextSequence = 0
  private var drainTask: Task<Void, Never>?
  private var waiters: [Waiter] = []

  func enqueue(_ kind: Kind, for item: Item, _ work: @escaping @MainActor () async -> Void) {
    let superseded: Set<Kind>
    switch kind {
    case .start: superseded = []
    case .progress: superseded = [.progress]
    case .saveProgress, .finish: superseded = [.progress, .saveProgress]
    }
    if !superseded.isEmpty {
      pending.removeAll { $0.item == item && superseded.contains($0.kind) }
    }
    pending.append(Job(sequence: nextSequence, kind: kind, item: item, work: work))
    nextSequence += 1
    resumeFinishedWaiters()
    if drainTask == nil {
      drainTask = Task { await self.drain() }
    }
  }

  /// 等此刻已排进队的上报和写回发完（或被同一条目更新的一条取代）。任务取消时立即返回。
  func waitForQueued() async {
    await wait(through: nextSequence - 1)
  }

  /// 同 `waitForQueued()`，但最多等 `limit`。
  func waitForQueued(atMost limit: Duration) async {
    let sequence = nextSequence - 1
    guard !isFinished(through: sequence) else { return }
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.wait(through: sequence) }
      group.addTask { try? await Task.sleep(for: limit) }
      await group.next()
      group.cancelAll()
    }
  }

  private func drain() async {
    while !pending.isEmpty {
      let job = pending.removeFirst()
      runningSequence = job.sequence
      await job.work()
      runningSequence = nil
      resumeFinishedWaiters()
    }
    drainTask = nil
  }

  /// 队列先进先出：序号不大于 `sequence` 的都已发完或被丢弃，等价于正在发送的和排在最前的都比它新。
  private func isFinished(through sequence: Int) -> Bool {
    if let runningSequence, runningSequence <= sequence { return false }
    guard let first = pending.first else { return true }
    return first.sequence > sequence
  }

  private func wait(through sequence: Int) async {
    guard !isFinished(through: sequence) else { return }
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled || isFinished(through: sequence) {
          continuation.resume()
        } else {
          waiters.append(Waiter(id: id, sequence: sequence, continuation: continuation))
        }
      }
    } onCancel: {
      Task { @MainActor in self.resumeWaiter(id) }
    }
  }

  private func resumeFinishedWaiters() {
    let finished = waiters.filter { isFinished(through: $0.sequence) }
    guard !finished.isEmpty else { return }
    waiters.removeAll { isFinished(through: $0.sequence) }
    finished.forEach { $0.continuation.resume() }
  }

  private func resumeWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume()
  }
}

/// 申请一段后台执行时间，`work` 完成或系统收回时结束。
enum BackgroundExecution {
  private final class Assertion {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
      guard id != .invalid else { return }
      UIApplication.shared.endBackgroundTask(id)
      id = .invalid
    }
  }

  static func run(named name: String, _ work: @escaping @MainActor () async -> Void) {
    let assertion = Assertion()
    assertion.id = UIApplication.shared.beginBackgroundTask(withName: name) { assertion.end() }
    Task {
      await work()
      assertion.end()
    }
  }
}
