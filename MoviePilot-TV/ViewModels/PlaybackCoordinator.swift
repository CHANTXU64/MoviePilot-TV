import AVFoundation
import Combine
import Foundation
import MPVUI
import UIKit

/// 应用内播放的入口目标。
enum PlaybackTarget: Equatable {
  /// 详情页：MoviePilot 媒体库同步表里的条目 ID，可能是别的服务器上的 ID。
  /// 起播时在各台可播放的服务器上按 `expected`（类型、外部编号）找条目，见 `PlaybackCoordinator.findLibraryItem`。
  /// `owner` 是入库查询给的所属服务器（不知道时为 nil）：先找它，只在它上面按 ID 兜底。
  case libraryItem(itemID: String, expected: LibraryItemExpectation, owner: String? = nil)
  /// 已知服务器名称和这台服务器自己的条目 ID（首页“最近添加”，或详情页已在服务器上找到）。
  case serverItem(serverName: String, itemID: String)
  /// 详情页集列表里的一集，带着它所在那一季的集列表：在各台可播放的服务器上找这一集的文件，见 `EpisodeMatching.swift`。
  /// `allowsUncertain`：用户已在单集面板看过“可能不是这一集”的说明时为 true，才会试只按季号集号对上的文件。
  case episode(QueuedEpisode, allowsUncertain: Bool)
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

/// 解析完成、可以交给播放器的结果。
struct PreparedPlayback {
  let connection: any MediaServerConnection
  let stream: PreparedStream
  /// 按集播放时有：上一集、下一集从它往前后找。
  var episode: QueuedEpisode?
  /// MoviePilot 的条目信息（见 `PlaybackMetadataLookup`）；MoviePilot 认不出、查询失败或超时为 nil。
  var moviePilot: PlaybackMetadata?

  init(
    connection: any MediaServerConnection, stream: PreparedStream, episode: QueuedEpisode? = nil,
    moviePilot: PlaybackMetadata? = nil
  ) {
    self.connection = connection
    self.stream = stream
    self.episode = episode
    self.moviePilot = moviePilot
  }

  var item: ServerMediaItem { stream.item }
  var streamURL: URL { stream.streamURL }

  /// 播放界面和续播询问显示的信息：MoviePilot 的为准，缺的项用媒体服务器的。
  var metadata: PlaybackMetadata {
    (moviePilot ?? PlaybackMetadata()).filling(item.metadata)
  }

  var titles: (primary: String, secondary: String?) {
    metadata.playerTitles(isEpisode: item.kind == .episode)
  }

  var title: String { PlaybackTitles.singleLine(titles) }

  var resumePosition: Double? {
    PlaybackResumePolicy.resumePosition(
      positionSeconds: item.resumePositionSeconds, durationSeconds: durationSeconds(playerSeconds: nil))
  }

  /// 所播文件的时长（秒），见 `PlaybackDuration`。`playerSeconds` 是 mpv 读到的时长，还没读到时传 nil。
  func durationSeconds(playerSeconds: Double?) -> Double? {
    PlaybackDuration.seconds(
      player: playerSeconds, source: stream.source.runtimeSeconds, item: item.runtimeSeconds)
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
  /// 这部剧的整理记录也沿用这么久。
  static let episodeIndexTTL: TimeInterval = 60
  /// 单集对应读整理记录时每页的条数和最多读几页：记录多的剧只用最近的这些，没对上记录的文件照常按季号集号对应。
  static let transferRecordPageSize = 100
  static let transferRecordPageLimit = 10
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
  private nonisolated struct ConnectionKey: Hashable, Sendable {
    let type: String
    let name: String
    let restrictedAddresses: [URL]?
  }

  /// 同一服务器的连接可复用。限制地址的恢复请求只与同样限制的请求共用连接。
  private let connections: CoalescingCache<ConnectionKey, any MediaServerConnection>
  private let episodeIndexes: CoalescingCache<String, ServerEpisodeIndex>
  /// 这部剧在 MoviePilot 的整理记录，各台服务器的集索引共用。
  private let transferRecords: CoalescingCache<String, [EpisodeTransferRecord]>
  /// 各台服务器的媒体库配置（单集元数据来源）和读到的时间。只在补查一轮里读，建对应表时只看这里；
  /// 过了 `connectionTTL` 重新读，改了刮削配置最多过这么久就按新的判断。
  private var libraryProfiles: [String: (profiles: [MediaLibraryProfile], readAt: Date)] = [:]
  /// 单集对应直接请求 TMDB 补查（带本机缓存和限速）。
  private let tmdbDirectory: any TmdbEpisodeDirectory
  /// 进行中的补查：键是“服务器|TMDB 编号”，同一部剧在同一台服务器上同时只有一轮。
  private var lookupRounds: [String: LookupRound] = [:]
  /// 各部剧上一轮补查的开始时间：没查全的过一阵才再查，不随每次打开详情页重开一轮。
  private var lastLookupRound: [String: (startedAt: Date, files: Set<String>)] = [:]
  /// 一轮到点结束后，等已经发出的请求回来再通知一次（它们的结果会写进缓存，到点时还没回来）。
  private var lateLookupNotices: [String: Task<Void, Never>] = [:]
  /// 上次读到的 MoviePilot 集列表语言（`TMDB_LOCALE`），只读缓存时按它挑要比的其他语言。
  private var tmdbLocale: String?
  private let now: () -> Date
  /// 一轮补查结束时发出这部剧的 TMDB 编号（集索引已作废，结果在本机缓存里），详情页据此重读播放状态：
  /// 查到的集变成能播，“正在核对”的集按查完的结果显示。
  let evidenceUpdates = PassthroughSubject<Int, Never>()
  /// 一轮补查结束后，这么久之内不再开下一轮。
  static let lookupRoundRetryInterval: TimeInterval = 600
  /// 一轮补查最多多久（见 `TmdbEpisodeEvidence.roundBudget`），测试可以改短。
  private let lookupRoundBudget: Duration
  /// 设置页「播放」里的应用内播放开关。
  private let isEnabledInSettings: () -> Bool
  private var isTornDown = false

  init(
    apiService: APIService, mediaServerSession: URLSession = MediaServerHTTP.sharedSession,
    isEnabledInSettings: @escaping () -> Bool = { PlaybackPreferences.isInAppPlaybackEnabled },
    tmdbDirectory: any TmdbEpisodeDirectory = TmdbLookupStore.shared,
    lookupRoundBudget: Duration = TmdbEpisodeEvidence.roundBudget,
    now: @escaping () -> Date = Date.init
  ) {
    self.apiService = apiService
    self.mediaServerSession = mediaServerSession
    self.isEnabledInSettings = isEnabledInSettings
    self.tmdbDirectory = tmdbDirectory
    self.lookupRoundBudget = lookupRoundBudget
    self.now = now
    connections = CoalescingCache(
      ttl: Self.connectionTTL, capacity: 8, renewsTTLOnAccess: false, now: now)
    episodeIndexes = CoalescingCache(
      ttl: Self.episodeIndexTTL, capacity: 16, renewsTTLOnAccess: false, now: now)
    transferRecords = CoalescingCache(
      ttl: Self.episodeIndexTTL, capacity: 8, renewsTTLOnAccess: false, now: now)
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
    return InAppPlaybackAvailability.isEnabledForSession(
      canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
      backendVersion: apiService.settings?.BACKEND_VERSION,
      userEnabled: isEnabledInSettings()
    )
  }

  /// `media` 是详情页的 MoviePilot 详情（从详情页起播时）：播放界面的信息直接用它，不再按服务器条目查。
  func play(_ target: PlaybackTarget, media: MediaInfo? = nil) {
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
        outcome = .success(try await self.prepare(target, media: media, preferredUserName: userName))
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
    transferRecords.invalidateAll()
    libraryProfiles = [:]
    lookupRounds.values.forEach { $0.cancel() }
    lookupRounds = [:]
    lateLookupNotices.values.forEach { $0.cancel() }
    lateLookupNotices = [:]
    knownSeasons = nil
  }

  /// 详情页的条目 ID 不带服务器名，可能来自任何一台媒体服务器，不同服务器的数字 ID 还会撞号（同类服务器之间也会）。
  /// 只启用了一台服务器（且可在应用内播放）、入库查询也没说条目属于别的服务器时，ID 只可能来自它，不必确认，起播时再找；
  /// 否则在每台可播放的服务器上找这个条目（见 `findLibraryItem`），第一台找到的为准，用它自己的条目 ID。
  /// `preferredServer` 是 MoviePilot 入库查询给的所属服务器，先查它。
  /// 确认不在任何一台上时返回 nil（不显示播放）；无法确认（连不上、服务器报错等）时仍返回媒体库条目，起播时再逐台找。
  func locateLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, in servers: [MediaServerConf],
    preferredServer: String? = nil
  ) async -> PlaybackTarget? {
    guard !isTornDown, allowsPlayback, let apiService else { return nil }
    let enabled = servers.filter(\.isEnabled)
    let playable = Self.playableServers(in: servers, preferring: preferredServer)
    guard !playable.isEmpty else { return nil }
    let libraryItem = PlaybackTarget.libraryItem(itemID: itemID, expected: expected, owner: preferredServer)
    if enabled.count == 1, preferredServer == nil || preferredServer == enabled[0].name { return libraryItem }
    let strict = Self.requiresStrictMatch(servers)
    let userName = apiService.currentOrStoredUserName
    var isUncertain = false
    for server in playable {
      do {
        let found = try await withConnection(to: server, preferredUserName: userName) {
          try await Self.findLibraryItem(itemID, expected: expected, owner: preferredServer, strict: strict, on: $0)
        }
        if let found { return .serverItem(serverName: server.name, itemID: found.id) }
      } catch {
        if error is CancellationError || Task.isCancelled { return nil }
        isUncertain = true
      }
    }
    return isUncertain ? libraryItem : nil
  }

  /// 启用了多台服务器时，不知道属于哪台的条目 ID 可能来自任何一台、还会撞号，按 ID 找到的条目要外部编号对得上才算
  /// （见 `idFallbackStrictness`）。也是集索引缓存键的一部分，各处必须用同一个判断。
  private static func requiresStrictMatch(_ servers: [MediaServerConf]) -> Bool {
    servers.filter(\.isEnabled).count > 1
  }

  /// 按 MoviePilot 给的条目 ID 在一台服务器上兜底时，找到的条目要不要外部编号对上；nil 表示不在这台上按 ID 找。
  /// 条目 ID 只在所属服务器内有意义，不同服务器的数字 ID 会撞号：
  /// - 知道所属服务器（入库查询给的）：只在它上面按 ID 找，不要求外部编号对上（服务器没刮到编号也能认）；
  ///   其他服务器上同号的条目是别的片，只按外部编号找。
  /// - 不知道所属服务器（旧缓存）：`strict`（启用了多台服务器）时要外部编号对上；只启用了一台时 ID 只可能来自它，只比类型。
  static func idFallbackStrictness(on server: String, owner: String?, strict: Bool) -> Bool? {
    guard let owner else { return strict }
    return owner == server ? false : nil
  }

  /// 可恢复的失败交给调用方记下、接着试别的（另一份副本、按 ID 补查）：服务器报错、回包无法识别、条目读取被拒等。
  /// 影响整台服务器的失败（连不上、证书、密钥无效等，见 `MediaServerError.Reason.isServerWide`）和取消照常抛出，
  /// 由 `withConnection` 换地址或重读配置后重试，或者直接报给用户。
  private static func recovering<T>(_ work: () async throws -> T) async throws -> Result<T, Error> {
    do {
      return .success(try await work())
    } catch let error where error is CancellationError || (error as? MediaServerError)?.reason.isServerWide == true {
      throw error
    } catch {
      return .failure(error)
    }
  }

  /// 可在应用内播放的服务器，`preferring` 指定的排在最前，其余保持 MoviePilot 配置顺序。
  private static func playableServers(in servers: [MediaServerConf], preferring name: String?) -> [MediaServerConf] {
    let playable = servers.filter(\.supportsInAppPlayback)
    guard let name, let index = playable.firstIndex(where: { $0.name == name }) else { return playable }
    var ordered = playable
    ordered.insert(ordered.remove(at: index), at: 0)
    return ordered
  }

  /// 在一台服务器上找详情页的条目（电影或整部剧），返回这台服务器自己的条目（ID 可能与 MoviePilot 给的不同）。
  /// 先按外部编号找（同一部片在各台服务器上 ID 不同也能找到），找到就用；找不到再按 MoviePilot 给的 ID 兜底（见 `idFallbackStrictness`）。
  /// 都没找到、但其中一步出错时抛出那个错误（先报按外部编号查找的）：无法确认这台上没有。
  private static func findLibraryItem(
    _ itemID: String, expected: LibraryItemExpectation, owner: String?, strict: Bool,
    on connection: any MediaServerConnection
  ) async throws -> ServerMediaItem? {
    var searchFailure: Error?
    switch try await recovering({ try await connection.items(matching: expected) }) {
    case .success(let items):
      if let item = items.first(where: { expected.accepts($0, strict: true) }) { return item }
    case .failure(let error):
      searchFailure = error
    }
    guard let strictness = idFallbackStrictness(on: connection.serverName, owner: owner, strict: strict) else {
      if let searchFailure { throw searchFailure }
      return nil
    }
    switch try await recovering({ try await connection.item(id: itemID, timeout: MediaServerHTTP.quickTimeout) }) {
    case .success(let item?) where expected.accepts(item, strict: strictness):
      return item
    case .success:
      if let searchFailure { throw searchFailure }
      return nil
    case .failure(let error):
      throw searchFailure ?? error
    }
  }

  // MARK: - 按集播放

  /// 详情页每一集能不能播，与 `episodes` 一一对应：在各台可播放的服务器上找，确定有的优先，其次第一台有的（见 `EpisodeAvailability.resolve`）。
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
      let failure = EpisodeAvailability.failed("没能从 MoviePilot 读取媒体服务器配置：\(Self.message(for: error))")
      return episodes.map { _ in failure }
    }
    guard servers.contains(where: \.supportsInAppPlayback) else { return nil }
    let lookups = await episodeLookups(
      context, servers: servers, preferredUserName: apiService.currentOrStoredUserName, forceRefresh: forceRefresh)
    guard !Task.isCancelled else { return nil }
    return episodes.map { EpisodeAvailability.resolve($0, lookups: lookups) }
  }

  /// 在每台可播放的服务器上读这部剧的集索引，单台失败只记在它自己的结果里。各台互不依赖，同时读；
  /// 结果按服务器顺序排（所属服务器在前，第一台有的为准）。取消时只返回已经读到的。
  /// `forceRefresh` 时各台都重读，这部剧的整理记录只重读一次，各台共用（见 `RefreshRound`）。
  private func episodeLookups(
    _ context: EpisodePlaybackContext, servers: [MediaServerConf], preferredUserName: String?,
    excluding excluded: String? = nil, forceRefresh: Bool = false
  ) async -> [ServerEpisodeLookup] {
    let strict = Self.requiresStrictMatch(servers)
    let targets = Self.playableServers(in: servers, preferring: context.libraryItem?.server)
      .filter { $0.name != excluded }
    let round = forceRefresh ? RefreshRound() : nil
    var lookups = [ServerEpisodeLookup?](repeating: nil, count: targets.count)
    await withTaskGroup(of: (Int, ServerEpisodeLookup?).self) { group in
      for position in targets.indices {
        let server = targets[position]
        group.addTask {
          let lookup = await self.episodeLookup(
            context, on: server, strict: strict, preferredUserName: preferredUserName, refresh: round)
          return (position, lookup)
        }
      }
      for await result in group {
        lookups[result.0] = result.1
      }
    }
    return lookups.compactMap { $0 }
  }

  /// 试看的这一集整理好了：叫媒体服务器马上入库，不等它自己发现新文件。按位置刷新时照 MoviePilot 的媒体库刷新：
  /// 已有这部剧的服务器只刷新这部剧；哪台都还没有时，刷新整理后的文件所在的媒体库（见 `MediaLibraryScan`）；
  /// 也对不上（比如 Docker 里两边挂载的路径不同）时，每台都刷新整个库。`.everything` 是试看服务的兜底，直接每台刷新整个库。
  /// 只等服务器受理，不等扫描完成；哪台连不上或报错只记日志，不影响别的服务器。
  func requestLibraryScan(context: EpisodePlaybackContext, scope: LibraryScanRequest) async {
    guard !isTornDown, allowsPlayback, let apiService else { return }
    let servers: [MediaServerConf]
    do {
      servers = try await apiService.fetchCachedMediaServers()
    } catch {
      if !(error is CancellationError) {
        Logger.warning("[Playback] 叫媒体服务器入库前读取服务器配置失败: \(Self.message(for: error))")
      }
      return
    }
    let strict = Self.requiresStrictMatch(servers)
    let userName = apiService.currentOrStoredUserName
    func refresh(_ scope: MediaLibraryRefreshScope, on server: MediaServerConf) async {
      do {
        try await withConnection(to: server, preferredUserName: userName) { try await $0.refreshLibrary(scope) }
        Logger.info("[Playback] 已叫“\(server.name)”入库（\(Self.describe(scope))）")
      } catch {
        guard !(error is CancellationError) else { return }
        Logger.warning("[Playback] 叫“\(server.name)”入库失败: \(Self.message(for: error))")
      }
    }

    let targets = Self.playableServers(in: servers, preferring: context.libraryItem?.server)
    guard case .located(let file) = scope else {
      for server in targets { await refresh(.all, on: server) }
      return
    }
    // 查得到这部剧在不在的服务器才往下判断；查不成的不刷新。
    var reached: [MediaServerConf] = []
    var seriesFound: [(server: MediaServerConf, ids: [String])] = []
    for server in targets {
      do {
        let copies = try await withConnection(to: server, preferredUserName: userName) {
          try await Self.seriesCopies(context, on: $0, strict: strict).items
        }
        reached.append(server)
        if !copies.isEmpty { seriesFound.append((server, copies.map(\.id))) }
      } catch {
        guard !(error is CancellationError), !Task.isCancelled else { return }
        Logger.warning("[Playback] 叫“\(server.name)”入库前查找这部剧失败: \(Self.message(for: error))")
      }
    }
    if !seriesFound.isEmpty {
      for (server, ids) in seriesFound {
        for id in ids { await refresh(.series(id: id), on: server) }
      }
      return
    }
    var libraries: [(server: MediaServerConf, id: String)] = []
    for server in reached {
      do {
        let folders = try await withConnection(to: server, preferredUserName: userName) { try await $0.libraryFolders() }
        if let id = MediaLibraryScan.library(for: file, in: folders) { libraries.append((server, id)) }
      } catch {
        guard !(error is CancellationError), !Task.isCancelled else { return }
        Logger.warning("[Playback] 叫“\(server.name)”入库前读取媒体库失败: \(Self.message(for: error))")
      }
    }
    if libraries.isEmpty {
      for server in reached { await refresh(.all, on: server) }
    } else {
      for (server, id) in libraries { await refresh(.library(id: id), on: server) }
    }
  }

  private static func describe(_ scope: MediaLibraryRefreshScope) -> String {
    switch scope {
    case .series: "这部剧"
    case .library: "所在的媒体库"
    case .all: "整个库"
    }
  }

  /// 一台服务器上这部剧的集索引；取消时为 nil。失败的说明已写明服务器和那一步（见 `MediaServerError`）。
  private func episodeLookup(
    _ context: EpisodePlaybackContext, on server: MediaServerConf, strict: Bool, preferredUserName: String?,
    refresh: RefreshRound?
  ) async -> ServerEpisodeLookup? {
    do {
      let index = try await withConnection(to: server, preferredUserName: preferredUserName) {
        try await self.episodeIndex(context, on: $0, strict: strict, refresh: refresh)
      }
      return .loaded(index)
    } catch {
      if error is CancellationError || Task.isCancelled { return nil }
      return .failed(server: server.name, message: Self.message(for: error))
    }
  }

  /// 一轮强制重读（详情页重试、起播时重读过时的服务器、播完重读当前服务器）。各台服务器的集索引都重读；
  /// 这部剧的整理记录只有第一台用到的那次强制重读，之后各台跟上那次在途的读取或读它刚写进缓存的结果（`CoalescingCache`），
  /// 不必每台都重发一遍、最后只用上一遍。那次重读成功之前缓存里的是这一轮以前的记录，后面的各台不用。
  @MainActor
  private final class RefreshRound {
    private var transferRecordsClaimed = false
    private(set) var transferRecordsRefreshed = false

    /// 这一轮第一次要整理记录时为 true（由它强制重读），之后为 false。
    func claimsTransferRecordRefresh() -> Bool {
      defer { transferRecordsClaimed = true }
      return !transferRecordsClaimed
    }

    func transferRecordRefreshSucceeded() { transferRecordsRefreshed = true }
  }

  /// 一台服务器上这部剧的集索引，缓存 `episodeIndexTTL`，见 `loadEpisodeIndex`。`refresh` 不为 nil 时不沿用缓存。
  private func episodeIndex(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, strict: Bool,
    refresh: RefreshRound? = nil
  ) async throws -> ServerEpisodeIndex {
    let key = [
      connection.serverName, connection.reportingServer.absoluteString, connection.userID, context.seriesLookupKey,
      strict ? "strict" : "",
    ].joined(separator: "|")
    return try await episodeIndexes.value(for: key, forceRefresh: refresh != nil, validate: validateNotTornDown) {
      [weak self] in
      let sources = EpisodeMatchingSources(
        seasonList: { list in
          guard let apiService = self?.apiService else { throw CancellationError() }
          return try await apiService.fetchTmdbEpisodes(
            tmdbID: context.tmdbID, season: list.season, episodeGroup: list.episodeGroup)
        },
        seasons: { episodeGroup in
          guard let apiService = self?.apiService else { throw CancellationError() }
          let seasons: [TmdbSeason]
          if let episodeGroup {
            seasons = try await apiService.getGroupSeasons(groupId: episodeGroup)
          } else {
            // 按 TMDB 身份查：MoviePilot 直接给 TMDB 的季列表（含特别篇第 0 季），不按剧名识别。
            let media = MediaInfo(
              tmdb_id: context.tmdbID, source: "themoviedb", media_id: String(context.tmdbID),
              title: context.seriesName, type: "电视剧")
            seasons = try await apiService.getMediaSeasons(media: media, allSeasons: true)
          }
          return seasons.compactMap(\.season_number)
        },
        transferRecords: {
          guard let self else { throw CancellationError() }
          return try await self.seriesTransferRecords(context, round: refresh)
        },
        evidence: { [weak self] episodes, local in
          await self?.episodeEvidence(episodes: episodes, local: local, tmdbID: context.tmdbID, on: connection)
            ?? EpisodeEvidence()
        })
      return try await Self.loadEpisodeIndex(context, on: connection, strict: strict, sources: sources)
    }
  }

  // MARK: 单集对应的补查

  private static func profileKey(_ connection: any MediaServerConnection) -> String {
    [connection.serverName, connection.reportingServer.absoluteString, connection.userID].joined(separator: "|")
  }

  /// 读过的媒体库配置和它还新不新（过了 `connectionTTL` 要重读）；没读过时为 nil。过期的照常用到重读成功为止，
  /// 不然每次重读期间，靠编号确认过的集会短暂变回不确定。
  private func storedLibraryProfiles(for connection: any MediaServerConnection) -> (
    profiles: [MediaLibraryProfile], isFresh: Bool
  )? {
    guard let entry = libraryProfiles[Self.profileKey(connection)] else { return nil }
    return (entry.profiles, now().timeIntervalSince(entry.readAt) < Self.connectionTTL)
  }

  /// 建对应表时文件以外的依据：只用本机已有的（读过的媒体库配置、TMDB 补查缓存），不等任何外部请求，已确定的集和起播不受影响。
  /// 缺媒体库配置或缓存没查全时在后台开一轮补查（见 `startLookupRound`）。这一轮进行中时，还没确定是哪一集的带编号文件
  /// 记为 `unresolved`，没找到的集先显示正在核对、不能试看；一轮结束后按查到的结果显示（没查成的按可能已有处理）。
  private func episodeEvidence(
    episodes: [ServerMediaItem], local: ServerEpisodeIndex, tmdbID: Int, on connection: any MediaServerConnection
  ) async -> EpisodeEvidence {
    let roundKey = "\(connection.serverName)|\(tmdbID)"
    var evidence = EpisodeEvidence()
    var needsRound = false
    var candidates: Set<String> = []
    if let stored = storedLibraryProfiles(for: connection) {
      evidence.independentFiles = MediaLibraryProfile.independentFiles(episodes, in: stored.profiles)
      if let request = ExternalEvidenceRequest(
        tmdbID: tmdbID, episodes: episodes, local: local, independentFiles: evidence.independentFiles)
      {
        let cached = await TmdbEpisodeEvidence.collect(
          request, access: nil, locale: tmdbLocale, directory: tmdbDirectory)
        evidence.lookups = cached.lookups
        evidence.translatedSeasons = cached.translatedSeasons
        needsRound = !cached.isComplete
        candidates = Set(request.candidates.map(\.itemID))
      }
      needsRound = needsRound || !stored.isFresh
    } else if let pending = ExternalEvidenceRequest(
      tmdbID: tmdbID, episodes: episodes, local: local, independentFiles: nil)
    {
      // 还没读到媒体库配置（这一轮里先读；或读失败了）：带编号的文件都没法核对，没找到的集不能直接说没有。
      needsRound = true
      candidates = Set(pending.candidates.map(\.itemID))
      for id in candidates { evidence.lookups[id] = .unresolved }
      evidence.librarySettingsUnknown = true
    }
    if needsRound {
      startLookupRound(roundKey, tmdbID: tmdbID, episodes: episodes, local: local, files: candidates, on: connection)
    }
    evidence.lookupInProgress = lookupRounds[roundKey]?.isFirst == true
    return evidence
  }

  /// 进行中的一轮补查：查询任务和到点计时器。哪个先结束都由 `finishLookupRound` 收尾，按 `id` 只收一次。
  /// `isFirst`：这部剧在这台服务器上第一次核对，没找到的集先显示正在核对、不能试看；之后的重查在后台进行，不挡试看。
  private struct LookupRound {
    let id: UUID
    let isFirst: Bool
    let work: Task<Void, Never>
    let timer: Task<Void, Never>

    func cancel() {
      work.cancel()
      timer.cancel()
    }
  }

  /// 后台补查一轮：读媒体库配置、读 MoviePilot 的 TMDB 配置、去 TMDB 查，从开始算最多 `lookupRoundBudget`，
  /// 到点结束。结束时（查没查到、查成没查成都一样）作废集索引、通知详情页重读，“正在核对”不会挂着不走。
  /// 同一部剧在同一台服务器上同时只有一轮；上一轮开始后 `lookupRoundRetryInterval` 内不再开，除非出现了上一轮没查过的文件
  /// （比如刚入库的一集）。`files` 是这次要查的文件。
  private func startLookupRound(
    _ key: String, tmdbID: Int, episodes: [ServerMediaItem], local: ServerEpisodeIndex, files: Set<String>,
    on connection: any MediaServerConnection
  ) {
    guard !isTornDown, lookupRounds[key] == nil else { return }
    let previous = lastLookupRound[key]
    if let previous, now().timeIntervalSince(previous.startedAt) < Self.lookupRoundRetryInterval,
      files.isSubset(of: previous.files)
    {
      return
    }
    lastLookupRound[key] = (now(), files.union(previous?.files ?? []))
    lateLookupNotices[key]?.cancel()
    lateLookupNotices[key] = nil
    let deadline = ContinuousClock.now.advanced(by: lookupRoundBudget)
    let id = UUID()
    let work = Task { [weak self] in
      await self?.runLookupRound(tmdbID: tmdbID, episodes: episodes, local: local, on: connection, deadline: deadline)
      self?.finishLookupRound(key, id: id, tmdbID: tmdbID)
    }
    // 到点直接收尾，不等查询退场：排队等名额、等在途请求都不响应取消，等它们会让“正在核对”拖过截止时间。
    // 到点后还没发出的请求在 `TmdbLookupStore` 里按截止时间放弃。
    let timer = Task { [weak self] in
      try? await Task.sleep(until: deadline, clock: .continuous)
      guard !Task.isCancelled else { return }
      self?.finishLookupRound(key, id: id, tmdbID: tmdbID, byDeadline: true)
    }
    lookupRounds[key] = LookupRound(id: id, isFirst: previous == nil, work: work, timer: timer)
  }

  /// 一轮补查结束（查完或到点）：停掉查询和计时器，作废集索引，通知详情页重读。查没查到都通知，“正在核对”不会挂着不走。
  /// 到点结束时，已经发出的请求还会把结果写进缓存（最多再等一个请求超时），那时再通知一次。
  private func finishLookupRound(_ key: String, id: UUID, tmdbID: Int, byDeadline: Bool = false) {
    guard !isTornDown, let round = lookupRounds[key], round.id == id else { return }
    lookupRounds[key] = nil
    round.cancel()
    episodeIndexes.invalidateAll()
    evidenceUpdates.send(tmdbID)
    guard byDeadline else { return }
    lateLookupNotices[key] = Task { [weak self] in
      try? await Task.sleep(for: .seconds(URLSessionTmdbTransport.resourceTimeout + 1))
      guard !Task.isCancelled, let self, !self.isTornDown else { return }
      self.lateLookupNotices[key] = nil
      self.episodeIndexes.invalidateAll()
      self.evidenceUpdates.send(tmdbID)
    }
  }

  private func runLookupRound(
    tmdbID: Int, episodes: [ServerMediaItem], local: ServerEpisodeIndex, on connection: any MediaServerConnection,
    deadline: ContinuousClock.Instant
  ) async {
    let profiles: [MediaLibraryProfile]
    let stored = storedLibraryProfiles(for: connection)
    if let stored, stored.isFresh {
      profiles = stored.profiles
    } else {
      do {
        profiles = try await connection.libraryProfiles()
        guard !isTornDown, !Task.isCancelled else { return }
        libraryProfiles[Self.profileKey(connection)] = (profiles, now())
      } catch {
        if error is CancellationError || Task.isCancelled { return }
        // 重读失败时沿用读过的；从没读到过就不核实。
        guard let stored else {
          Logger.warning(
            "[Playback] 没能读取“\(connection.serverName)”的媒体库配置，不用单集外部编号和标题核实: \(Self.message(for: error))")
          return
        }
        profiles = stored.profiles
      }
    }
    let independent = MediaLibraryProfile.independentFiles(episodes, in: profiles)
    guard
      let request = ExternalEvidenceRequest(tmdbID: tmdbID, episodes: episodes, local: local, independentFiles: independent),
      let apiService
    else { return }
    let access: TmdbAccess
    do {
      access = try await apiService.fetchTmdbAccess()
      tmdbLocale = access.locale
    } catch {
      if !(error is CancellationError), !Task.isCancelled {
        let reason = (error as? TmdbDirectError)?.message ?? Self.message(for: error)
        Logger.warning("[Playback] 没有去 TMDB 补查单集：\(reason)")
      }
      return
    }
    _ = await TmdbEpisodeEvidence.collect(request, access: access, directory: tmdbDirectory, deadline: deadline)
  }

  /// 强制重读这一轮里各台服务器要的整理记录：第一台强制重读，其余的跟上那次在途的读取，成功失败都和它一样。失败时不替跟上的各台重试：
  /// 同一个 MoviePilot 刚失败时，这一轮的各台服务器沿用相同结果，让单集匹配继续使用其他依据。
  /// 那次已经读完才来要的：成功了用它写进缓存的结果，失败了（或第一台中途取消）自己再读。都不用这一轮以前的缓存。
  /// 不在强制重读时按缓存读。
  private func seriesTransferRecords(
    _ context: EpisodePlaybackContext, round: RefreshRound?
  ) async throws -> [EpisodeTransferRecord] {
    guard let round else { return try await seriesTransferRecords(context, forceRefresh: false) }
    guard round.claimsTransferRecordRefresh() else {
      return try await seriesTransferRecords(
        context, forceRefresh: false, acceptsCachedValue: { _ in round.transferRecordsRefreshed })
    }
    let records = try await seriesTransferRecords(context, forceRefresh: true)
    round.transferRecordRefreshSucceeded()
    return records
  }

  /// 这部剧在 MoviePilot 的成功整理记录，按 TMDB 编号筛出这部剧的。剧名为空时不查。集索引强制重读时一起重读，
  /// 刚整理的文件才对得上。
  ///
  /// `title` 不带通配符时，MoviePilot 分词后对标题、源路径和目标路径做包含匹配，剧名短（如「24」「You」）时混进大量别的剧，
  /// 读到的几页里可能一条这部剧的都没有。带 `*` 或 `?` 时按通配符对整串匹配，所以先用「剧名*」查标题以剧名开头的记录
  /// （路径是绝对路径，不会命中）；筛完一条这部剧的都没有时（记录里存的标题可能和现在的剧名不同），再退回包含匹配。
  private func seriesTransferRecords(
    _ context: EpisodePlaybackContext, forceRefresh: Bool,
    acceptsCachedValue: ([EpisodeTransferRecord]) -> Bool = { _ in true }
  ) async throws -> [EpisodeTransferRecord] {
    guard let title = context.seriesName else { return [] }
    let tmdbID = context.tmdbID
    return try await transferRecords.value(
      for: "\(tmdbID)|\(title)", forceRefresh: forceRefresh, acceptsCachedValue: acceptsCachedValue,
      validate: validateNotTornDown
    ) { [weak self] in
      let fetch: (String, Int) async throws -> (records: [EpisodeTransferRecord], total: Int?) = { query, page in
        guard let apiService = self?.apiService else { throw CancellationError() }
        return try await apiService.fetchEpisodeMatchTransferRecords(
          title: query, page: page, count: Self.transferRecordPageSize)
      }
      let prefixed = try await Self.readTransferRecords(query: title + "*", tmdbID: tmdbID, fetch: fetch)
      guard prefixed.isEmpty else { return prefixed }
      return try await Self.readTransferRecords(query: Self.containingQuery(for: title), tmdbID: tmdbID, fetch: fetch)
    }
  }

  /// 按一种查法读最多 `transferRecordPageLimit` 页，留下这部剧的记录。
  private static func readTransferRecords(
    query: String, tmdbID: Int,
    fetch: (String, Int) async throws -> (records: [EpisodeTransferRecord], total: Int?)
  ) async throws -> [EpisodeTransferRecord] {
    var records: [EpisodeTransferRecord] = []
    for page in 1...transferRecordPageLimit {
      let batch = try await fetch(query, page)
      records += batch.records.filter { $0.belongs(toSeries: tmdbID) }
      // 按整页数量判断结尾：筛掉别的剧后变少不算读完。`total` 是 MoviePilot 按同一种查法数的总条数。
      if batch.records.count < transferRecordPageSize { break }
      if let total = batch.total, page * transferRecordPageSize >= total { break }
    }
    return records
  }

  /// 退回的包含匹配。剧名里没有 `*`、`?` 时原样传，MoviePilot 分词后做包含匹配；有的话 MoviePilot 会按通配符对整串匹配，
  /// 前后补上 `*` 才是包含。
  private static func containingQuery(for title: String) -> String {
    title.contains("*") || title.contains("?") ? "*\(title)*" : title
  }

  /// 播放中的当前服务器上这部剧的集索引，`strict` 按当前的服务器配置。
  private func sessionEpisodeIndex(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, forceRefresh: Bool = false
  ) async throws -> ServerEpisodeIndex {
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    return try await episodeIndex(
      context, on: connection, strict: Self.requiresStrictMatch(servers),
      refresh: forceRefresh ? RefreshRound() : nil)
  }

  /// 一台服务器上对得上这部剧的整剧条目：按外部编号找到的（同一部剧可能在几个媒体库里各有一个）都留着，
  /// 再按入库记录里的 ID 补上那一份（见 `idFallbackStrictness`）。某一步失败时返回读到的那些和失败的原因；
  /// 一份都没找到又有失败时抛出那个错误：无法确认这台上没有。
  private static func seriesCopies(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, strict: Bool
  ) async throws -> (items: [ServerMediaItem], failures: [Error]) {
    var failures: [Error] = []
    var series: [ServerMediaItem] = []
    switch try await recovering({ try await connection.items(matching: context.expected) }) {
    case .success(let items): series = items.filter { context.expected.accepts($0, strict: true) }
    case .failure(let error): failures.append(error)
    }
    if let ref = context.libraryItem, !series.contains(where: { $0.id == ref.itemID }),
      let strictness = idFallbackStrictness(on: connection.serverName, owner: ref.server, strict: strict)
    {
      switch try await recovering({ try await connection.item(id: ref.itemID, timeout: MediaServerHTTP.quickTimeout) }) {
      case .success(let item?) where context.expected.accepts(item, strict: strictness): series.append(item)
      case .success: break
      case .failure(let error): failures.append(error)
      }
    }
    if series.isEmpty, let failure = failures.first { throw failure }
    return (series, failures)
  }

  /// 读一台服务器上这部剧的集：先找出对得上的整剧条目（见 `seriesCopies`），再逐份读集。
  /// 某一步失败（按外部编号查找、按 ID 补查、某一份的集）时用读到的那些，并记下没读全；一份都没读到时抛出错误。
  /// 读到的集交给 `EpisodeMatchLoader` 和 MoviePilot 的集对应（要用的集列表、整理记录由 `sources` 按需读取）。
  private static func loadEpisodeIndex(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection, strict: Bool,
    sources: EpisodeMatchingSources
  ) async throws -> ServerEpisodeIndex {
    let (series, failures) = try await seriesCopies(context, on: connection, strict: strict)
    var episodes: [ServerMediaItem] = []
    var copyFailures: [Error] = []
    for copy in series {
      switch try await recovering({ try await connection.episodes(seriesID: copy.id) }) {
      case .success(let items): episodes += items
      case .failure(let error): copyFailures.append(error)
      }
    }
    if let failure = copyFailures.first, copyFailures.count == series.count { throw failure }
    let incomplete = (failures + copyFailures).first.map { message(for: $0) }
    if let incomplete {
      Logger.warning("[Playback] “\(connection.serverName)”上这部剧没有读全: \(incomplete)")
    }
    return try await EpisodeMatchLoader.index(
      serverName: connection.serverName, hasSeries: !series.isEmpty, episodes: episodes, incompleteReason: incomplete,
      sources: sources, describe: message(for:))
  }

  /// 按集起播：先用缓存的集索引逐台试（入库查询给的所属服务器在前），第一台能播的为准。都不行时，重读缓存里有这部剧、
  /// 却没能播这一集的服务器再试一次：这一集可能刚入库，缓存给的条目可能已经删了或重新刮削成了别的集，也可能上次没读全。
  /// 别的服务器缓存里就能播时，不为所属服务器上刚入库的可能先重读一遍整部剧。服务器报错不自动重试（先试其他副本和服务器）。
  /// 以编号为准：先只试确定的文件，各台都没有确定能播的，才按服务器顺序试只按季号集号对上的。
  /// 每台服务器的读取和起播都在 `withConnection` 里，缓存的地址连不上时换地址重试。
  private func prepareEpisode(
    _ queued: QueuedEpisode, allowsUncertain: Bool, servers: [MediaServerConf], preferredUserName: String?,
    certificateFailures: inout [String: MediaServerError]
  ) async throws -> PreparedPlayback {
    guard let tmdbEpisodeID = queued.episode.tmdbEpisodeID else {
      throw PlaybackError.episodeUnavailable(EpisodeAvailability.UnidentifiableReason.missingEpisodeID.message)
    }
    let candidates = Self.playableServers(in: servers, preferring: queued.context.libraryItem?.server)
    guard !candidates.isEmpty else { throw PlaybackError.noPlayableServer }
    let strict = Self.requiresStrictMatch(servers)
    var lookups: [String: ServerEpisodeLookup] = [:]
    var firstError: Error?
    var missingIdentity: PlaybackError?
    var outdated: [MediaServerConf] = []
    var uncertain: [MediaServerConf] = []
    /// 重读过时的服务器是一轮：各台都重读，整理记录只重读一次。
    let refreshRound = RefreshRound()
    enum Pass { case cached, refreshed, uncertain }
    for pass in [Pass.cached, .refreshed, .uncertain] {
      let servers: [MediaServerConf] =
        switch pass {
        case .cached: candidates
        case .refreshed: outdated
        case .uncertain: allowsUncertain ? candidates.filter { server in uncertain.contains { $0.name == server.name } } : []
        }
      for server in servers {
        do {
          let (index, attempt) = try await withPreparationConnection(
            to: server, preferredUserName: preferredUserName, certificateFailures: &certificateFailures
          ) {
            connection in
            let index = try await self.episodeIndex(
              queued.context, on: connection, strict: strict, refresh: pass == .refreshed ? refreshRound : nil)
            let files =
              pass == .uncertain
              ? index.uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).map(\.item)
              : index.confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID)
            let attempt = try await Self.prepareFirstPlayable(
              files, on: connection, episode: queued, tmdbEpisodeID: tmdbEpisodeID,
              confirmedBy: index.confirmedBy)
            return (index, attempt)
          }
          if let prepared = attempt.prepared { return prepared }
          lookups[server.name] = .loaded(index)
          if firstError == nil { firstError = attempt.error }
          if missingIdentity == nil { missingIdentity = attempt.missingIdentity }
          guard pass != .uncertain else { continue }
          let hasUncertain = !index.uncertainEpisodes(tmdbEpisodeID: tmdbEpisodeID).isEmpty
          if hasUncertain, !uncertain.contains(where: { $0.name == server.name }) { uncertain.append(server) }
          let isMissing = index.confirmedEpisodes(tmdbEpisodeID: tmdbEpisodeID).isEmpty && !hasUncertain
          if pass == .cached, index.hasSeries, isMissing || attempt.foundStale || index.incompleteReason != nil {
            outdated.append(server)
          }
        } catch let error where error is CancellationError {
          throw error
        } catch {
          if firstError == nil { firstError = error }
          lookups[server.name] = .failed(server: server.name, message: Self.message(for: error))
        }
      }
    }
    if let firstError { throw firstError }
    let availability = EpisodeAvailability.resolve(
      queued.episode, lookups: candidates.compactMap { lookups[$0.name] })
    switch availability {
    case .failed(let reason):
      throw PlaybackError.episodeUnavailable(reason)
    case .playable, .uncertain:
      // 集索引里有，重新读取时条目已经变了。
      throw missingIdentity ?? PlaybackError.episodeUnavailable(EpisodeAvailability.notOnServerMessage)
    default:
      throw missingIdentity
        ?? PlaybackError.episodeUnavailable(availability.message ?? EpisodeAvailability.notOnServerMessage)
    }
  }

  /// 在一台服务器上起播一集的结果。
  struct EpisodeAttempt {
    var prepared: PreparedPlayback?
    /// 第一份读取失败的原因（服务器报错、拒绝播放等，已写明服务器和那一步）
    var failure: Error?
    /// 都不能直连时，第一份的原因
    var unsupported: PlaybackError?
    /// 集索引里有匹配，重新读取条目却拿不到它的单集编号。
    var missingIdentity: PlaybackError?
    /// 重新读取条目时未能确认索引里的匹配，需要刷新集索引。
    var foundStale = false
    /// 只知道条目 ID、条目上又没有编号，要按集索引核对。
    var needsIndex = false

    /// 都没播成时报给用户的原因：读取失败在前（稍后重试可能就好），不能直连在后；都没有时为 nil。
    var error: Error? { failure ?? unsupported }
  }

  private enum EpisodeCandidate {
    case prepared(PreparedPlayback)
    case stale
    case missingEpisodeID
    case needsIndex
  }

  /// 同一集在一台服务器上的各个条目（不同媒体库各一个）逐个试：先重新读条目，续播点以服务器此刻为准；
  /// 重新核对还是集索引里记的那一集后才准备播放（见 `ServerEpisodeIndex.recheck`）。无法确认、读取失败或不能直连时，继续试其他副本。
  /// `fromIndex` 为 false 时候选只是条目 ID（播放中换集），条目上没有编号时留给调用方按集索引核对。
  private static func prepareFirstPlayable(
    _ candidates: [ServerMediaItem], on connection: any MediaServerConnection, episode: QueuedEpisode,
    tmdbEpisodeID: Int, fromIndex: Bool = true, confirmedBy: [String: EpisodeConfirmationBasis] = [:]
  ) async throws -> EpisodeAttempt {
    var attempt = EpisodeAttempt()
    for candidate in candidates {
      let result = try await recovering { () -> EpisodeCandidate in
        guard let fresh = try await connection.item(id: candidate.id, timeout: nil), fresh.kind == .episode
        else { return .stale }
        switch ServerEpisodeIndex.recheck(
          fresh, recorded: fromIndex ? candidate : nil, tmdbEpisodeID: tmdbEpisodeID,
          basis: confirmedBy[candidate.id])
        {
        case .same: return .prepared(try await preparePlayback(fresh, on: connection, episode: episode))
        case .changed: return .stale
        case .lostEpisodeID: return .missingEpisodeID
        case .needsIndex: return .needsIndex
        }
      }
      switch result {
      case .success(.prepared(let prepared)):
        attempt.prepared = prepared
        return attempt
      case .success(.stale):
        attempt.foundStale = true
      case .success(.needsIndex):
        attempt.needsIndex = true
      case .success(.missingEpisodeID):
        attempt.foundStale = true
        attempt.missingIdentity = .episodeUnavailable(
          "无法确认这一集：媒体服务器“\(connection.serverName)”重新读取的剧集条目缺少 TMDB 编号，可刷新元数据后重试")
      case .failure(let error):
        if case .unsupported(let reason)? = error as? PlaybackError {
          if attempt.unsupported == nil { attempt.unsupported = .unsupported(reason) }
        } else if attempt.failure == nil {
          attempt.failure = error
        }
      }
    }
    return attempt
  }

  /// 播放中换到另一集：先试要求的条目；它已经不在、对不上、没有编号要按集索引核对、读取失败或不能直连（比如远程链接）时，
  /// 才读集索引，试同一集在这台服务器上的其他条目（要求的条目过时了就重读集索引）。
  /// 都没播成时：有读取失败或不能直连就报它；否则按集索引说明（没读全时说是哪一步失败，见 `ServerEpisodeIndex.availability`）。
  private func prepareSwitchedEpisode(
    _ itemID: String, _ queued: QueuedEpisode, on connection: any MediaServerConnection
  ) async throws -> PreparedPlayback {
    guard let tmdbEpisodeID = queued.episode.tmdbEpisodeID else {
      throw PlaybackError.episodeUnavailable(EpisodeAvailability.UnidentifiableReason.missingEpisodeID.message)
    }
    let requested = try await Self.prepareFirstPlayable(
      [ServerMediaItem(id: itemID, kind: .episode)], on: connection, episode: queued, tmdbEpisodeID: tmdbEpisodeID,
      fromIndex: false)
    if let prepared = requested.prepared { return prepared }
    // 要求的条目是包含多集的文件（记着的是第一集的编号），或者没有编号（按整理记录、季号集号对上的）时，
    // 上面按单集编号核对不过；按集索引记的样子再核对一次。缓存的集索引核对不过时重读一次。
    var refreshed = requested.foundStale
    var index: ServerEpisodeIndex
    var alternate: EpisodeAttempt
    repeat {
      do {
        index = try await sessionEpisodeIndex(queued.context, on: connection, forceRefresh: refreshed)
      } catch let error where !(error is CancellationError) {
        throw requested.error ?? error
      }
      let alternates = index.playableEpisodes(tmdbEpisodeID: tmdbEpisodeID).filter {
        requested.needsIndex || $0.id != itemID || $0.tmdbEpisodeID != tmdbEpisodeID
      }
      alternate = try await Self.prepareFirstPlayable(
        alternates, on: connection, episode: queued, tmdbEpisodeID: tmdbEpisodeID,
        confirmedBy: index.confirmedBy)
      if let prepared = alternate.prepared { return prepared }
      guard !refreshed, alternate.foundStale else { break }
      refreshed = true
    } while true
    if let error = requested.failure ?? alternate.failure ?? requested.unsupported ?? alternate.unsupported {
      throw error
    }
    let availability = index.availability(of: tmdbEpisodeID)
    if case .failed(let reason) = availability { throw PlaybackError.episodeUnavailable(reason) }
    if let missingIdentity = requested.missingIdentity ?? alternate.missingIdentity { throw missingIdentity }
    switch availability {
    case .playable, .uncertain, .notOnServer:
      throw PlaybackError.episodeUnavailable("媒体服务器“\(connection.serverName)”上已经找不到这一集")
    case .checking(let server, _):
      // 播放器里不会自动更新，请用户稍后再试。
      throw PlaybackError.episodeUnavailable(EpisodeAvailability.checkingQueueMessage(server: server))
    case let other:
      throw PlaybackError.episodeUnavailable(other.message ?? EpisodeAvailability.notOnServerMessage)
    }
  }

  // MARK: - 播放队列（上一集、下一集）

  func adjacentEpisode(
    _ direction: EpisodeNavigator.Direction, from playback: PreparedPlayback, refresh: Bool = false
  ) async throws -> EpisodeNavigator.Outcome {
    guard let queued = playback.episode else { return .end }
    var refreshedIndex: ServerEpisodeIndex?
    var refreshedSeason: [MoviePilotEpisode]?
    if refresh {
      // 播完一集要接着播时重新读一次：播放期间下一集可能刚入库（订阅还在下载后面的集），不能沿用开播时的结果。
      // 只刷新当前服务器和当前季。两项互不依赖，同时发出、分别等结果，一项失败不影响另一项；成功的直接用于这次找下一集，
      // 失败的照常用缓存。当前季重新读到的列表不可信时，按这一集所在的那份找（见 `EpisodeNavigator.currentSeasonList`）。
      async let index = refreshedEpisodeIndex(queued.context, on: playback.connection)
      async let season = refreshedSeasonEpisodes(queued.context, season: queued.episode.seasonNumber)
      (refreshedIndex, refreshedSeason) = await (index, season)
      try Task.checkCancellation()
    }
    var episodeIDsOnServer: Set<Int>?
    if direction == .previous {
      let index =
        if let refreshedIndex { refreshedIndex } else {
          try? await sessionEpisodeIndex(queued.context, on: playback.connection)
        }
      episodeIDsOnServer = index?.episodeIDs
    }
    return try await EpisodeNavigator.adjacent(
      direction, from: queued, currentItemID: playback.item.id, episodeIDsOnServer: episodeIDsOnServer,
      loadSeason: { [weak self] season in
        guard let self else { throw CancellationError() }
        if season == queued.episode.seasonNumber, let refreshedSeason { return refreshedSeason }
        return try await self.seasonEpisodes(queued.context, season: season)
      },
      status: { [weak self] episode in
        guard let self else { throw CancellationError() }
        return try await self.queueStatus(
          episode, context: queued.context, current: playback.connection, currentIndex: refreshedIndex)
      })
  }

  /// 播完时重读当前服务器上这部剧的集；失败记日志、返回 nil，照常用缓存。
  private func refreshedEpisodeIndex(
    _ context: EpisodePlaybackContext, on connection: any MediaServerConnection
  ) async -> ServerEpisodeIndex? {
    do {
      return try await sessionEpisodeIndex(context, on: connection, forceRefresh: true)
    } catch {
      if !(error is CancellationError) {
        Logger.warning("[Playback] 重新读取当前服务器上的剧集失败: \(Self.message(for: error))")
      }
      return nil
    }
  }

  /// 播完时重读当前季的 MoviePilot 集列表；失败记日志、返回 nil，照常用缓存。
  private func refreshedSeasonEpisodes(_ context: EpisodePlaybackContext, season: Int) async -> [MoviePilotEpisode]? {
    do {
      return try await seasonEpisodes(context, season: season, forceRefresh: true)
    } catch {
      if !(error is CancellationError) {
        Logger.warning("[Playback] 重新读取第 \(season) 季集列表失败: \(Self.message(for: error))")
      }
      return nil
    }
  }

  /// 队列面板只列当前服务器上能播的集，不必连其他服务器；读不到当前服务器的集时报错。
  /// 正在播的那一季读不到、或读到的列表里没有这一集时，用这一集所在的那份（见 `EpisodeNavigator.currentSeasonList`）。
  func playableEpisodes(inSeason season: Int, from playback: PreparedPlayback) async throws -> [EpisodeQueueEntry] {
    guard let queued = playback.episode else { return [] }
    let isCurrentSeason = season == queued.episode.seasonNumber
    let list: [MoviePilotEpisode]
    do {
      let loaded = try await seasonEpisodes(queued.context, season: season)
      list = isCurrentSeason ? EpisodeNavigator.currentSeasonList(queued, loaded: loaded) ?? loaded : loaded
    } catch let error where isCurrentSeason && !(error is CancellationError) {
      guard let known = EpisodeNavigator.currentSeasonList(queued, loaded: nil) else { throw error }
      list = known
    }
    let current = ServerEpisodeLookup.loaded(try await sessionEpisodeIndex(queued.context, on: playback.connection))
    return try await EpisodeNavigator.playableEntries(in: list) { episode in
      EpisodeQueueStatus.onCurrentServer(episode, lookup: current) ?? .absent
    }
  }

  /// 正在播的这部剧在这次会话里读到过的非空集列表，按季。
  private struct KnownSeasons {
    let series: String
    var lists: [Int: [MoviePilotEpisode]] = [:]
  }

  /// MoviePilot 在这一季确实没有集和读 TMDB 失败时都返回空列表；接口缓存过期或被空列表覆盖后就没有旧值了，所以另外记一份。
  /// 只记正在播的这部剧（换剧就清掉），随作用域拆除。
  private var knownSeasons: KnownSeasons?

  /// 一季的 MoviePilot 集列表。读到非空列表就记下；读到空列表或读取失败时，有这次会话里读到过的那份（可信的旧列表）就用它。
  /// 没有旧列表时空列表照常返回、读取失败照常抛出，由调用方说明（见 `EpisodeNavigator.adjacent`）。
  private func seasonEpisodes(
    _ context: EpisodePlaybackContext, season: Int, forceRefresh: Bool = false
  ) async throws -> [MoviePilotEpisode] {
    let series = "\(context.tmdbID)|\(context.episodeGroup ?? "")"
    let known = knownSeasons?.series == series ? knownSeasons?.lists[season] : nil
    let list: [MoviePilotEpisode]
    do {
      list = try await moviePilotEpisodes(context, season: season, forceRefresh: forceRefresh)
    } catch let error where !(error is CancellationError) {
      guard let known else { throw error }
      Logger.warning("[Playback] 第 \(season) 季集列表读取失败，用之前读到的: \(Self.message(for: error))")
      return known
    }
    guard !list.isEmpty else {
      if known != nil { Logger.warning("[Playback] MoviePilot 返回的第 \(season) 季集列表是空的，用之前读到的") }
      return known ?? []
    }
    if knownSeasons?.series != series { knownSeasons = KnownSeasons(series: series) }
    knownSeasons?.lists[season] = list
    return list
  }

  private func moviePilotEpisodes(
    _ context: EpisodePlaybackContext, season: Int, forceRefresh: Bool = false
  ) async throws -> [MoviePilotEpisode] {
    guard let apiService else { throw CancellationError() }
    let episodes = try await apiService.fetchTmdbEpisodes(
      tmdbID: context.tmdbID, season: season, episodeGroup: context.episodeGroup, forceRefresh: forceRefresh)
    return MoviePilotEpisode.list(episodes, season: season)
  }

  /// 一集相对当前服务器的状态。先只看当前服务器：能播、或当前服务器就无法确认时，不必连其他服务器
  /// （见 `EpisodeQueueStatus.onCurrentServer`）；当前服务器上没有时，再看其他服务器以区分“在别处”和“确认没有”。
  /// `currentIndex` 是刚重读到的当前服务器的集索引（播完时），没有时读缓存。
  private func queueStatus(
    _ episode: MoviePilotEpisode, context: EpisodePlaybackContext, current: any MediaServerConnection,
    currentIndex: ServerEpisodeIndex? = nil
  ) async throws -> EpisodeQueueStatus {
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    let currentLookup: ServerEpisodeLookup
    if let currentIndex {
      currentLookup = .loaded(currentIndex)
    } else {
      do {
        currentLookup = .loaded(
          try await episodeIndex(context, on: current, strict: Self.requiresStrictMatch(servers)))
      } catch let error where !(error is CancellationError) {
        currentLookup = .failed(server: current.serverName, message: Self.message(for: error))
      }
    }
    if let status = EpisodeQueueStatus.onCurrentServer(episode, lookup: currentLookup) { return status }
    let others = await episodeLookups(
      context, servers: servers, preferredUserName: apiService.currentOrStoredUserName, excluding: current.serverName)
    try Task.checkCancellation()
    return EpisodeQueueStatus.resolve(episode, current: currentLookup, others: others)
  }

  // MARK: - 解析

  private func isPlaying(_ session: PlaybackSession) -> Bool {
    guard case .playing(let current) = phase else { return false }
    return current === session
  }

  /// 媒体服务器配置很少变化，平时用会话缓存；解析失败时重新读一次，
  /// 配置确实变了才用新配置重试。遇到证书错误的服务器只尝试用户新配置的连接地址。
  private func prepare(
    _ target: PlaybackTarget, media: MediaInfo?, preferredUserName: String?
  ) async throws -> PreparedPlayback {
    await reporter.waitForQueued(atMost: Self.pendingReportWait)
    try Task.checkCancellation()
    guard let apiService else { throw CancellationError() }
    let servers = try await apiService.fetchCachedMediaServers()
    var certificateFailures: [String: MediaServerError] = [:]
    do {
      return try await prepare(
        target, servers: servers, media: media, preferredUserName: preferredUserName,
        certificateFailures: &certificateFailures)
    } catch let error where !(error is CancellationError) {
      let fresh = try? await apiService.fetchCachedMediaServers(forceRefresh: true)
      try Task.checkCancellation()
      guard let fresh, fresh != servers else { throw error }
      return try await prepare(
        target, servers: fresh, media: media, preferredUserName: preferredUserName,
        certificateFailures: &certificateFailures)
    }
  }

  private func prepare(
    _ target: PlaybackTarget, servers: [MediaServerConf], media: MediaInfo?, preferredUserName: String?,
    certificateFailures: inout [String: MediaServerError]
  ) async throws -> PreparedPlayback {
    let itemID: String
    let expected: LibraryItemExpectation?
    var owner: String?
    let candidates: [MediaServerConf]
    switch target {
    case .libraryItem(let id, let expectation, let libraryOwner):
      itemID = id
      expected = expectation
      owner = libraryOwner
      candidates = Self.playableServers(in: servers, preferring: libraryOwner)
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
    case .episode(let queued, let allowsUncertain):
      return try await prepareEpisode(
        queued, allowsUncertain: allowsUncertain, servers: servers, preferredUserName: preferredUserName,
        certificateFailures: &certificateFailures)
    }

    // 媒体库条目逐台找（所属服务器在前），第一台找到的为准。MoviePilot `/mediaserver/play` 只拿 ID 逐台试、
    // 认第一台有这个 ID 的；这里按外部编号找、只在所属服务器上按 ID 兜底，撞号时不播错片，各台 ID 不同也能找到。
    let strict = Self.requiresStrictMatch(servers)
    var firstError: Error?
    for server in candidates {
      do {
        let prepared = try await withPreparationConnection(
          to: server, preferredUserName: preferredUserName, certificateFailures: &certificateFailures
        ) {
          connection -> PreparedPlayback? in
          let found: ServerMediaItem?
          if let expected {
            found = try await Self.findLibraryItem(
              itemID, expected: expected, owner: owner, strict: strict, on: connection)
          } else {
            found = try await connection.item(id: itemID, timeout: MediaServerHTTP.quickTimeout)
          }
          guard let item = found else { return nil }
          return try await self.preparePlayback(item, on: connection, media: media)
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

  /// 不是从详情页集列表起播（详情页的「播放」、首页最近入库）：播放信息和 MoviePilot 的条目信息同时取，
  /// 后者最多等 `PlaybackMetadataLookup.timeout`，取不到就用媒体服务器的。
  private func preparePlayback(
    _ requested: ServerMediaItem, on connection: any MediaServerConnection, media: MediaInfo?
  ) async throws -> PreparedPlayback {
    let item = try await Self.playableItem(requested, on: connection)
    guard let apiService else { throw CancellationError() }
    async let moviePilot = PlaybackMetadataLookup.metadata(for: item, media: media, on: connection, api: apiService)
    let stream = try await connection.prepareStream(for: item, preferredSourceID: nil)
    return PreparedPlayback(connection: connection, stream: stream, moviePilot: await moviePilot)
  }

  /// 按集播放（`episode` 不为 nil）时条目信息来自集列表；换版本时由调用方沿用原来的。
  private static func preparePlayback(
    _ requested: ServerMediaItem, on connection: any MediaServerConnection, preferredSourceID: String? = nil,
    episode: QueuedEpisode? = nil
  ) async throws -> PreparedPlayback {
    let item = try await playableItem(requested, on: connection)
    let stream = try await connection.prepareStream(for: item, preferredSourceID: preferredSourceID)
    return PreparedPlayback(
      connection: connection, stream: stream, episode: episode,
      moviePilot: episode.map(PlaybackMetadataLookup.metadata(for:)))
  }

  /// 电影、单集直接播；整部剧从第一集开始（不带集列表上下文，没有上一集、下一集）。
  private static func playableItem(
    _ requested: ServerMediaItem, on connection: any MediaServerConnection
  ) async throws -> ServerMediaItem {
    switch requested.kind {
    case .movie, .episode:
      return requested
    case .series:
      let episodes = try await connection.episodes(seriesID: requested.id)
      guard let first = PlaybackEpisodeOrder.firstEpisode(in: episodes) else {
        throw PlaybackError.noEpisodes
      }
      return first
    case .other:
      throw PlaybackError.unsupportedItemType
    }
  }

  // MARK: - 连接

  private var validateNotTornDown: () throws -> Void {
    { [weak self] in
      try Task.checkCancellation()
      guard self?.isTornDown == false else { throw CancellationError() }
    }
  }

  /// 证书失败后只尝试不在原候选地址中的新地址，即使原地址仍保留在配置中。
  private func withPreparationConnection<T>(
    to server: MediaServerConf, preferredUserName: String?, certificateFailures: inout [String: MediaServerError],
    _ body: (any MediaServerConnection) async throws -> T
  ) async throws -> T {
    if let failure = certificateFailures[server.name] {
      let newAddresses = (server.config?.candidateBaseURLs ?? []).filter { address in
        !failure.certificateOrigins.contains(MediaServerBaseURL.Origin(address))
      }
      guard !newAddresses.isEmpty else { throw failure }
      let connection = try await connection(
        to: server, preferredUserName: preferredUserName, restrictedAddresses: newAddresses)
      return try await body(connection)
    }
    do {
      return try await withConnection(to: server, preferredUserName: preferredUserName, body)
    } catch let failure as MediaServerError where failure.reason == .certificate {
      certificateFailures[server.name] = failure
      throw failure
    }
  }

  /// 用缓存的连接执行，按失败原因（见 `MediaServerError.Reason`）各重试一次：
  /// - 连不上（如离开了内网）：重新探测地址再执行。
  /// - 密钥无效（HTTP 401）：密钥可能刚在 MoviePilot 里改过，重读一次服务器配置，变了就用新配置再执行，没变就照常报错。
  /// 其他失败（证书、权限、服务器报错等）不重试。
  private func withConnection<T>(
    to server: MediaServerConf, preferredUserName: String?,
    _ body: (any MediaServerConnection) async throws -> T
  ) async throws -> T {
    func attempt(_ target: MediaServerConf, forceRefresh: Bool = false) async throws -> T {
      do {
        return try await body(
          try await connection(to: target, preferredUserName: preferredUserName, forceRefresh: forceRefresh))
      } catch var failure as MediaServerError where failure.reason == .certificate {
        let addresses = (server.config?.candidateBaseURLs ?? []) + (target.config?.candidateBaseURLs ?? [])
        failure.certificateOrigins.formUnion(addresses.map(MediaServerBaseURL.Origin.init))
        throw failure
      }
    }
    do {
      return try await attempt(server)
    } catch let error as MediaServerError where error.reason == .unreachable {
      try Task.checkCancellation()
      return try await attempt(server, forceRefresh: true)
    } catch let error as MediaServerError where error.reason == .unauthorized {
      try Task.checkCancellation()
      guard let fresh = try? await apiService?.fetchCachedMediaServers(forceRefresh: true),
        let updated = fresh.first(where: { $0.name == server.name }), updated.config != server.config
      else { throw error }
      return try await attempt(updated)
    }
  }

  /// 取缓存的连接；缓存是按旧配置或旧 MoviePilot 用户名建立的，就重新连接。
  /// 按服务器类型和名称缓存：同名服务器改了类型（比如 Emby 换成 Jellyfin）时换用新类型的适配器。
  private func connection(
    to server: MediaServerConf, preferredUserName: String?, forceRefresh: Bool = false, restrictedAddresses: [URL]? = nil
  ) async throws -> any MediaServerConnection {
    guard let config = server.config, config.apiKey != nil,
      let connector = MediaServerAdapters.connector(for: server.type)
    else { throw PlaybackError.noPlayableServer }
    let session = mediaServerSession
    let load: @MainActor () async throws -> any MediaServerConnection = {
      try await connector.connect(
        server: server, config: config, candidateBaseURLs: restrictedAddresses ?? config.candidateBaseURLs,
        preferredUserName: preferredUserName, session: session)
    }
    let key = ConnectionKey(type: server.type.lowercased(), name: server.name, restrictedAddresses: restrictedAddresses)
    let cached = try await connections.value(
      for: key, forceRefresh: forceRefresh, validate: validateNotTornDown, load: load)
    guard !forceRefresh, cached.config != config || cached.preferredUserName != preferredUserName else {
      return cached
    }
    return try await connections.value(for: key, forceRefresh: true, validate: validateNotTornDown, load: load)
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
  /// `episode` 是详情页集列表里的那一集和它所在那一季的列表（按集播放时），上下文沿用当前会话冻结的。
  func switchItem(
    to itemID: String, mediaSourceID: String? = nil, startPosition: Double = 0, episode: QueuedEpisode? = nil,
    in session: PlaybackSession, completion: @escaping (SwitchResult) -> Void = { _ in }
  ) {
    guard let apiService, isPlaying(session) else {
      completion(.discarded)
      return
    }
    let snapshot = apiService.sessionSnapshot()
    let connection = session.connection
    let queued = episode.flatMap { requested in
      session.episode.map {
        QueuedEpisode(context: $0.context, episode: requested.episode, seasonEpisodes: requested.seasonEpisodes)
      }
    }
    switchTask?.cancel()
    switchTask = Task { [weak self] in
      let outcome: Result<PreparedPlayback, Error>
      do {
        if let queued, mediaSourceID == nil {
          guard let coordinator = self else { throw CancellationError() }
          outcome = .success(try await coordinator.prepareSwitchedEpisode(itemID, queued, on: connection))
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
        case .success(var prepared):
          // 换版本还是同一个条目，沿用已有的 MoviePilot 信息，不再查一次。
          if prepared.moviePilot == nil, prepared.item.id == session.item.id {
            prepared.moviePilot = session.playback.moviePilot
          }
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
  /// 当前条目已经记进日志的 mpv 警告和错误条数（见 `record`）。
  private var loggedMPVMessages = 0
  /// mpv 打开当前文件时跳过的 zlib 压缩轨道（MPVUI 的 libmpv 没编 zlib，解不开），按 mpv 报的轨道号记。
  /// 只是字幕轨压缩时字幕不显示；画面和声音都压缩时一帧都解不出来，播放失败时据此说明原因。
  private var skippedCompressedTracks: Set<String> = []
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
    player.logHandler = { [weak self] message in self?.record(message) }
    mpvPlayer = player
    return player
  }

  /// mpv 自己的警告和错误（MPVUI 默认只转发这两级）写进日志：播放失败时看得出卡在哪一步，比如读不到数据、解不了码。
  /// 解码出错时可能每帧都报，每个条目只记前 `mpvLogLimit` 条。流地址和密钥照常隐去。测试也直接调用它模拟 mpv。
  func record(_ message: MPVLogMessage) {
    if message.prefix == "mkv", message.message.contains("compressed with zlib") {
      skippedCompressedTracks.insert(Self.compressedTrackNumber(in: message.message) ?? message.message)
    }
    guard loggedMPVMessages < Self.mpvLogLimit else { return }
    loggedMPVMessages += 1
    let text = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
    let line = "[Playback] mpv[\(message.prefix)] \(PlaybackLog.redacted(text))"
    switch message.level {
    case .fatal, .error: Logger.error(line)
    default: Logger.warning(line)
    }
    if loggedMPVMessages == Self.mpvLogLimit {
      Logger.warning("[Playback] mpv 在这个条目上已经记了 \(Self.mpvLogLimit) 条警告和错误，后面的不再记")
    }
  }

  static let mpvLogLimit = 50

  /// mpv 警告「Track 3 was compressed with zlib …」里的轨道号；认不出时为 nil。
  private static func compressedTrackNumber(in text: String) -> String? {
    guard let range = text.range(of: #"Track \d+ was compressed"#, options: .regularExpression) else { return nil }
    return text[range].split(separator: " ").dropFirst().first.map(String.init)
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
    loggedMPVMessages = 0
    skippedCompressedTracks = []
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

  /// 停在 `position` 时要写回的观看进度（测试也直接调用：测试里 mpv 不会真的播到这个位置）。
  func watchProgress(at position: Double) -> WatchProgress {
    let duration = prepared.durationSeconds(playerSeconds: mpvPlayer.map { $0.duration.seconds })
    return WatchProgress(
      itemID: prepared.item.id,
      completed: PlaybackResumePolicy.isCompleted(positionSeconds: position, durationSeconds: duration),
      positionSeconds: position,
      playedAt: Date())
  }

  // MARK: - mpv

  private func observe(_ player: MPVPlayer) {
    let events = player.makeEventStream()
    mpvEventTask = Task { [weak self] in
      for await event in events {
        guard let self, !self.isStopped else { return }
        self.handle(event.change, generation: event.generation)
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

  /// 处理 mpv 事件（测试也直接调用它模拟 mpv）。`generation` 是事件所属的那次载入（`MPVPlayer.generation`）。
  /// 事件流会留着还没读的事件，换条目后才读到的上一条目的失败或暂停不能算到新条目头上，直接丢弃。
  func handle(_ change: MPVPlaybackEvent.Change, generation: UInt64) {
    guard generation == mpvPlayer?.generation else { return }
    switch change {
    case .stateChanged(.failed(let error)), .error(let error, fatal: true):
      Logger.error("[Playback] mpv 播放失败: \(PlaybackLog.redacted(String(describing: error)))")
      onFailure?(
        Self.failureMessage(
          for: error, skippedCompressedTracks: skippedCompressedTracks.count,
          embeddedTrackCount: prepared.stream.source.embeddedTrackCount))
    case .pauseChanged(let isPaused):
      handlePauseChange(isPaused: isPaused)
    default:
      break
    }
  }

  /// 播放失败时给用户的说明。mpv 跳过过 zlib 压缩的轨道、又一帧画面一段声音都没播出来时单独说，
  /// 只说有依据的：mpv 的警告不说跳过的是哪类轨道，跳过的条数不少于文件里音视频和字幕轨的总数
  /// （`embeddedTrackCount`，数不准时为 nil）时，才能确定画面和声音都在里面；否则只说有轨道压缩、解不开，不断言是失败原因。
  /// 只比音视频条数不够：字幕轨压缩、音视频因别的原因没播出来时条数也可能凑够。
  /// 其他失败按错误类别说明（见 `PlaybackFailureMessage`）。提示在全局通知里单行显示，同样不超过 30 字。
  static func failureMessage(
    for error: MPVPlayerError, skippedCompressedTracks: Int, embeddedTrackCount: Int?
  ) -> String {
    guard skippedCompressedTracks > 0, case .playbackFailed(let code, _) = error, code == LibmpvError.nothingToPlay
    else {
      return PlaybackFailureMessage.message(for: error)
    }
    if let embeddedTrackCount, skippedCompressedTracks >= embeddedTrackCount {
      return "音视频用了 zlib 压缩，无法解码，请用媒体服务器 App"
    }
    return "有轨道用了 zlib 压缩，无法解码，请用媒体服务器 App"
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
