import Combine
import Foundation

/// 单集试看：在 MoviePilot 上建一条只针对这一集的临时订阅，暂停后写入试看规则并补搜，搜索结束就删掉它。
///
/// 服务器上留着的订阅由持久保存的凭据负责收尾，只管本机建的；别的设备留下的带标记订阅按普通订阅处理。
/// 订阅删掉后对下载、整理和入库的跟踪只在内存里，App 退出就丢，页面再打开时按服务器现状重新推导。
/// 试看结束留下的结局按账号保存，App 重启后仍显示，直到用户再次发起或这一集入库。
@MainActor
final class EpisodeTrialService: ObservableObject {
  nonisolated deinit {}

  /// 查这一集在不在媒体库里；`fresh` 时不沿用媒体服务器的集索引缓存。
  typealias Availability = @MainActor (EpisodeTrialRequest, _ fresh: Bool) async -> EpisodeAvailability?
  /// 叫媒体服务器马上入库整理好的这一集（见 `PlaybackCoordinator.requestLibraryScan`）。
  typealias LibraryScan = @MainActor (EpisodePlaybackContext, LibraryScanRequest) async -> Void
  typealias Sleep = @Sendable (Duration) async throws -> Void

  static let interrupted = EpisodeTrialProgress.unavailable("本次试看查询已中断")
  static let cancelled = EpisodeTrialProgress.concluded(.cancelled)
  static let unconfirmedQuery = EpisodeTrialProgress.unavailable("暂时无法确认试看进度")
  static let released = EpisodeTrialProgress.concluded(.modifiedElsewhere)
  static let removedElsewhere = EpisodeTrialProgress.concluded(.removedElsewhere)
  static let untrackable = EpisodeTrialProgress.concluded(.lostTrack("提交过下载，但找不到下载记录，无法继续跟踪"))
  static let batchLost = EpisodeTrialProgress.concluded(.lostTrack("MoviePilot 找不到这次试看搜索的记录，可以重新试看"))
  static let downloadGone = EpisodeTrialProgress.concluded(
    .lostTrack("下载器、整理队列和整理记录里都找不到这次试看的下载，可以重新试看"))
  /// MoviePilot 每 5 分钟整理一次下载器里下完的任务；下载器、整理队列和整理记录连续这么久都明确查不到，
  /// 就当下载任务已经不在了（比如在下载器里删掉了）。留半小时，整理积压或下载器晚标记下完时不至于过早放弃。
  nonisolated static let missingDownloadLimit: TimeInterval = 30 * 60
  /// 叫媒体服务器按位置刷新以后，这么久还没入库就叫每台刷新整个库（可能刷错了地方，比如新的一集整理到了另一个目录）。
  /// 刷新一部剧、读完新文件一般用不了这么久。
  nonisolated static let libraryScanFallbackDelay: TimeInterval = 2 * 60
  /// 有本机试看订阅需要推进或收尾时，按这个间隔对账。
  nonisolated static let driveInterval = Duration.seconds(20)
  /// 页面显示着这一集时跟得紧：下载中只查下载器，和 MoviePilot Web「正在下载」页一样 3 秒一次；其他步骤 10 秒一次。
  nonisolated static let downloadPollInterval = Duration.seconds(3)
  nonisolated static let activePollInterval = Duration.seconds(10)
  /// 没有页面在看时等整理、等入库，等正式订阅，或状态说不清时放慢。
  nonisolated static let slowPollInterval = Duration.seconds(60)
  /// 下载历史按时间倒序，最多往后翻这么多页。只用于尽力而为的查找。
  private static let historyPageLimit = 5
  /// 创建没确认的凭据不按时间淘汰，按条数只留最近这么多条。
  private static let unconfirmedLimit = 20
  /// 保存的结局按条数只留最近这么多条。
  nonisolated static let endingLimit = 50

  @Published private(set) var progress: [String: EpisodeTrialProgress] = [:]
  /// 当前账号保存的试看规则；没保存过时是默认规则，沿用 MoviePilot 的默认站点、规则组和下载设置。
  @Published private(set) var rule = EpisodeTrialRule()
  /// 本机建的、服务器上可能还留着的试看订阅。
  @Published private(set) var credentials: [EpisodeTrialCredential] = []
  private weak var api: APIService?
  private let defaults: UserDefaults
  private let storageKey: String?
  private let availability: Availability
  private let libraryScan: LibraryScan
  private let now: @MainActor () -> Date
  private let sleep: Sleep
  private var observations: [String: Observation] = [:]
  /// 已经结束的试看留下的结局：没有符合条件的资源、搜索失败或被跳过、在别处改过或删掉、已取消、整理失败等。
  /// 用户再次发起或这一集入库前一直显示，刷新不会把它改回「可以试看」。按账号保存，App 重启后仍在；从旧到新排列。
  /// 卡片不刷新进度，没有进度时显示这里保存的结局。
  @Published private(set) var endings: [EpisodeTrialStoredEnding] = []
  private var seasonRuns: [String: SeasonRun] = [:]
  private var driveLoop: Task<Void, Never>?
  private var isTornDown = false
  /// 正在显示这一集的页面，各自等着这一集被发起后接着刷新。有页面时进度直接显示在页面上，不另发通知。
  private var visiblePages: [String: [UUID: AsyncStream<Void>.Continuation]] = [:]
  /// 没有页面在看时接着跟踪的试看。只在本次运行内、试看还在进行时存在。
  private var followers: [String: Follower] = [:]
  /// 在途的催办请求（见 `nudge`），拆除时取消。
  private var nudges: [UUID: Task<Void, Never>] = [:]

  /// 订阅删掉以后接着看这一集的下载。只在本次运行内存在。
  private struct Observation {
    let target: EpisodeTrialTarget
    /// 本机试看订阅的 ID；为空表示看的是别的入口已经在下的这一集。
    let subscriptionID: Int?
    /// 找不到下载记录时显示的说明。
    let missingRecord: EpisodeTrialProgress
    var hash: String?
    var downloader: String?
    var historyTitle: String?
    /// 从什么时候起下载器、整理队列和整理记录都明确查不到这个下载。
    var missingSince: Date?
    /// 已经叫过 MoviePilot 马上整理：每次观察叫一次。
    var organizationRequested = false
    /// 第一次看到它在下载的时间和进度，按平均速度估剩余时间。
    var downloadETA: EpisodeTrialDownloadETA?
    /// 什么时候叫媒体服务器按位置刷新的，以及叫没叫过刷新整个库：每次观察各叫一次。
    var libraryScanRequestedAt: Date?
    var wholeLibraryScanRequested = false
  }

  /// 试看服务自己判定的失败，说明直接显示在进度上。`isPermanent` 的失败重试也不会变，记下后只做收尾。
  nonisolated private struct Failure: Error {
    let message: String
    let isPermanent: Bool
  }

  private struct Follower {
    let id: UUID
    let task: Task<Void, Never>
  }

  /// 范围大的推进覆盖范围小的：发起包含刷新，刷新包含后台对账。
  private enum RunKind: Int, Comparable {
    case drive, refresh, start

    static func < (lhs: RunKind, rhs: RunKind) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  /// 后端按季去重订阅，同一季同时只能有一条试看订阅，所以同季的推进依次执行。
  /// 推进由服务持有：页面离开不会把创建、暂停、写规则和补搜截断在中间，会话拆除时统一取消。
  private struct SeasonRun {
    let key: String
    let kind: RunKind
    let task: Task<EpisodeTrialProgress, Never>
  }

  /// 对账一条凭据的结果。
  private enum Driven {
    /// 创建请求没确认，订阅列表里还没有这个标记。
    case unconfirmed
    case inProgress(EpisodeTrialProgress)
    /// 凭据已经了结（删掉了订阅、订阅已不在、或在别处被改过）。
    case ended(EpisodeTrialProgress)

    var progress: EpisodeTrialProgress {
      switch self {
      case .unconfirmed: .submissionUnconfirmed
      case .inProgress(let progress), .ended(let progress): progress
      }
    }
  }

  init(
    api: APIService, defaults: UserDefaults = .standard,
    now: @escaping @MainActor () -> Date = { Date() },
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    libraryScan: @escaping LibraryScan = { _, _ in },
    availability: @escaping Availability
  ) {
    self.api = api
    self.defaults = defaults
    self.now = now
    self.sleep = sleep
    self.libraryScan = libraryScan
    self.availability = availability
    storageKey = api.profileKey.map { "episodeTrial.v2.\($0)" }
    if let storageKey, let data = defaults.data(forKey: storageKey + ".credentials"),
      let saved = try? JSONDecoder().decode([EpisodeTrialCredential].self, from: data)
    {
      credentials = saved
    }
    if let storageKey, let data = defaults.data(forKey: storageKey + ".rule"),
      let saved = try? JSONDecoder().decode(EpisodeTrialRule.self, from: data)
    {
      rule = saved
    }
    // 读不出（旧格式或损坏）按没有结局处理，不影响凭据和规则。
    if let storageKey, let data = defaults.data(forKey: storageKey + ".endings") {
      do {
        endings = try JSONDecoder().decode([EpisodeTrialStoredEnding].self, from: data)
      } catch {
        Logger.warning("[试看] 保存的试看结局读不出来，按没有结局处理：\(error.localizedDescription)")
      }
    }
    scheduleDrive()
  }

  /// 规则只影响之后写入的试看订阅；已经写进服务器的不跟着改。
  func saveRule(_ rule: EpisodeTrialRule) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    defaults.set(try JSONEncoder().encode(rule), forKey: storageKey + ".rule")
    self.rule = rule
  }

  // MARK: - 页面入口

  /// 用户按「试看」：先按服务器现状对账，这一集已经在路上就接着显示，都没有才新建。
  func start(_ request: EpisodeTrialRequest) async -> EpisodeTrialProgress {
    let result = await enqueue(seasonKey: request.seasonKey, key: request.key, kind: .start) { service in
      await service.run(request, mayCreate: true)
    }
    if let pages = visiblePages[request.key] {
      for page in pages.values { page.yield() }
    } else {
      follow(request)
    }
    return result
  }

  func refresh(_ request: EpisodeTrialRequest) async -> EpisodeTrialProgress {
    await enqueue(seasonKey: request.seasonKey, key: request.key, kind: .refresh) { service in
      await service.run(request, mayCreate: false)
    }
  }

  /// 页面显示这一集期间刷新进度，调用方在页面的 `.task` 里等待它，页面离开、任务取消时才返回。
  /// 有要跟的事时按间隔刷新；没有时不请求后端，等这一集被发起再继续。只推进已有的试看，不会发起新的。
  /// 页面离开时试看还在进行，就转给服务在后台接着跟踪。
  func poll(_ request: EpisodeTrialRequest) async {
    let key = request.key
    let id = UUID()
    let (started, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    followers.removeValue(forKey: key)?.task.cancel()
    visiblePages[key, default: [:]][id] = continuation
    defer { leavePage(request, id: id) }
    var wakeUps = started.makeAsyncIterator()
    while !Task.isCancelled, !isTornDown {
      let before = progress[key]
      let wasTracked = isTracked(key)
      let current = await refresh(request)
      // 刷新途中页面离开了，这次变成可以播放已经没人看到，照样通知。从没试看过、本来就在库里的不算。
      if Task.isCancelled, wasTracked, visiblePages[key]?.count == 1 {
        announceIfReady(request.target, from: before, to: current)
      }
      guard !Task.isCancelled else { return }
      if let delay = pollDelay(for: key, isVisible: true) {
        do { try await sleep(delay) } catch { return }
      } else if await wakeUps.next() == nil {
        return
      }
    }
  }

  // MARK: - 订阅卡片和季订阅页

  /// 这条订阅是不是本机正在试看的订阅。别的设备留下的、带标记的订阅不算，按普通订阅处理。
  func trialState(of subscribe: Subscribe) -> EpisodeTrialState? {
    EpisodeTrialHold.state(of: subscribe, in: EpisodeTrialHold.holds(in: credentials))
  }

  /// 取消只是停掉搜索、删掉订阅，旧版本后端也能做；试看订阅只有管理员建得出来，也只有管理员能删。
  var canCancelTrial: Bool { !isTornDown && api?.canRequestSuperUserEndpoints == true && storageKey != nil }

  /// 用户取消试看：先记下取消意图，再请求停止搜索；搜索结束后核对并删掉订阅。搜索还没停下来时返回 `pending`，
  /// 服务在后台接着收尾，App 重启后也会继续。已经提交给下载器的任务不动。
  /// 记下意图和其他推进一样排在这一季的队列里：在途的推进写回凭据时不会把它抹掉，之后的推进都按取消处理。
  func cancelTrial(subscriptionID id: Int) async -> EpisodeTrialCancelOutcome {
    guard canCancelTrial, let credential = credentials.first(where: { $0.subscriptionID == id }) else {
      return .failed
    }
    let marker = credential.marker
    _ = await enqueue(seasonKey: credential.target.seasonKey, key: "cancel-\(marker)", kind: .start) { service in
      await service.requestCancel(marker: marker)
    }
    guard !isTornDown else { return .failed }
    guard let current = credentials.first(where: { $0.marker == marker }) else { return .done }
    return current.cancelRequested ? .pending : .failed
  }

  private func requestCancel(marker: String) async -> EpisodeTrialProgress {
    guard var credential = credentials.first(where: { $0.marker == marker }) else { return Self.cancelled }
    credential.cancelRequested = true
    do { try store(credential) } catch { return Self.interrupted }
    progress[credential.target.episodeKey] = .cancelling
    return await driveStored(seasonKey: credential.target.seasonKey)
  }

  #if TESTING
    /// 测试用：把一条凭据记成本机的，订阅面板和季订阅页的测试据此构造“本机正在试看”的订阅。
    func recordCredentialForTesting(_ credential: EpisodeTrialCredential) throws { try store(credential) }

    /// 测试用：清掉这个账号保存的凭据和规则，测试结束时不在偏好里留下记录。
    func clearStoredStateForTesting() {
      guard let storageKey else { return }
      defaults.removeObject(forKey: storageKey + ".credentials")
      defaults.removeObject(forKey: storageKey + ".rule")
      defaults.removeObject(forKey: storageKey + ".endings")
    }
  #endif

  func tearDown() {
    isTornDown = true
    for run in seasonRuns.values { run.task.cancel() }
    seasonRuns.removeAll()
    driveLoop?.cancel()
    driveLoop = nil
    for follower in followers.values { follower.task.cancel() }
    followers.removeAll()
    for task in nudges.values { task.cancel() }
    nudges.removeAll()
    for pages in visiblePages.values { for page in pages.values { page.finish() } }
    visiblePages.removeAll()
    credentials.removeAll()
    observations.removeAll()
    endings.removeAll()
    progress.removeAll()
  }

  // MARK: - 跟踪与通知

  private func leavePage(_ request: EpisodeTrialRequest, id: UUID) {
    visiblePages[request.key]?.removeValue(forKey: id)?.finish()
    guard visiblePages[request.key]?.isEmpty != false else { return }
    visiblePages[request.key] = nil
    follow(request)
  }

  /// 没有页面在看时接着跟踪进行中的试看，入库后发通知，用户离开详情页也能知道可以播放了。
  /// 只在本次运行内，App 重启后进度等页面再打开时按服务器现状推导。
  private func follow(_ request: EpisodeTrialRequest) {
    let key = request.key
    guard !isTornDown, followers[key] == nil, backgroundDelay(for: key) != nil else { return }
    let id = UUID()
    let sleep = self.sleep
    let task = Task { [weak self] in
      while let delay = self?.backgroundDelay(for: key) {
        do { try await sleep(delay) } catch { break }
        guard let self, !Task.isCancelled else { break }
        let before = self.progress[key]
        let current = await self.refresh(request)
        guard !Task.isCancelled else { break }
        self.announceIfReady(request.target, from: before, to: current)
      }
      if self?.followers[key]?.id == id { self?.followers[key] = nil }
    }
    followers[key] = Follower(id: id, task: task)
  }

  /// 本机还有这一集的试看订阅，或者正看着它的下载。创建没确认的不算，不为它轮询。
  private func isTracked(_ key: String) -> Bool {
    observations[key] != nil
      || credentials.contains { $0.target.episodeKey == key && $0.subscriptionID != nil }
  }

  private func backgroundDelay(for key: String) -> Duration? {
    isTracked(key) ? pollDelay(for: key, isVisible: false) : nil
  }

  /// 下一次刷新前等多久；nil 表示没有要跟的事。后台跟踪只为入库后发通知，等整理、等入库时放慢。
  private func pollDelay(for key: String, isVisible: Bool) -> Duration? {
    let current = progress[key]
    guard isTracked(key) else {
      return current == .waitingForSubscription || current == .subscriptionPaused ? Self.slowPollInterval : nil
    }
    switch current {
    case .downloading: return isVisible ? Self.downloadPollInterval : Self.activePollInterval
    case .waitingForOrganization, .waitingForLibrary: return isVisible ? Self.activePollInterval : Self.slowPollInterval
    case .submissionUnconfirmed: return Self.slowPollInterval
    default: return Self.activePollInterval
    }
  }

  private func announceIfReady(
    _ target: EpisodeTrialTarget, from before: EpisodeTrialProgress?, to current: EpisodeTrialProgress
  ) {
    guard current.isReady, before?.isReady != true, !isTornDown, let api else { return }
    NotificationCenter.default.post(
      name: .episodeTrialDidBecomeReady, object: api,
      userInfo: [EpisodeTrialReadyNotice.messageKey: EpisodeTrialReadyNotice.message(for: target)])
  }

  // MARK: - 执行框架

  private struct Operation {
    let api: APIService
    let session: APIServiceSessionSnapshot

    func check() throws {
      try Task.checkCancellation()
      guard api.isSessionUnchanged(from: session) else { throw CancellationError() }
    }
  }

  /// 同一集正在推进且覆盖本次意图时直接等它的结果；否则排在同季上一次推进之后。
  private func enqueue(
    seasonKey: String, key: String, kind: RunKind,
    _ work: @escaping @MainActor @Sendable (EpisodeTrialService) async -> EpisodeTrialProgress
  ) async -> EpisodeTrialProgress {
    guard !isTornDown else { return Self.interrupted }
    if let current = seasonRuns[seasonKey], current.key == key, current.kind >= kind {
      return await current.task.value
    }
    let previous = seasonRuns[seasonKey]?.task
    let task = Task { [weak self] () -> EpisodeTrialProgress in
      _ = await previous?.value
      guard let self else { return EpisodeTrialService.interrupted }
      return await work(self)
    }
    seasonRuns[seasonKey] = SeasonRun(key: key, kind: kind, task: task)
    let result = await task.value
    if seasonRuns[seasonKey]?.task == task { seasonRuns.removeValue(forKey: seasonKey) }
    return result
  }

  /// 发起和刷新只对支持的版本和管理员会话开放。
  private func availableAPI() -> APIService? {
    guard let api = managingAPI(),
      EpisodeTrialAvailability.supports(backendVersion: api.settings?.BACKEND_VERSION)
    else { return nil }
    return api
  }

  /// 收尾已有的试看订阅（推进、取消、删除）只要求管理员：凭据只在支持的版本上建得出来，收尾不该因为版本读不出就停下。
  private func managingAPI() -> APIService? {
    guard !isTornDown, !Task.isCancelled, let api, storageKey != nil, api.canRequestSuperUserEndpoints else {
      return nil
    }
    return api
  }

  private func run(_ request: EpisodeTrialRequest, mayCreate: Bool) async -> EpisodeTrialProgress {
    guard !isTornDown, !Task.isCancelled else { return Self.interrupted }
    guard let api = availableAPI() else {
      return .unavailable(EpisodeTrialAvailability.requirementMessage)
    }
    let operation = Operation(api: api, session: api.sessionSnapshot())
    var result: EpisodeTrialProgress
    do {
      result = try await advance(request, mayCreate: mayCreate, operation: operation)
      try operation.check()
    } catch {
      guard !(error is CancellationError), (try? operation.check()) != nil else { return Self.interrupted }
      result = report(error)
    }
    progress[request.key] = result
    return result
  }

  /// 记下失败的具体原因。服务自己判定的失败照原样显示；请求失败等其他原因只记日志，显示「暂时无法确认」，下次接着查。
  private func report(_ error: Error) -> EpisodeTrialProgress {
    if let failure = error as? Failure {
      Logger.warning("[试看] \(failure.message)")
      return .unavailable(failure.message)
    }
    Logger.error("[试看] 查询或推进试看失败：\(error.localizedDescription)")
    return Self.unconfirmedQuery
  }

  /// 失败了只记日志、按没拿到结果处理的请求：回执丢了也能从服务器现状补回来，或者下次对账会再查。
  private func attempt<T>(_ action: String, _ request: () async throws -> T) async -> T? {
    do {
      return try await request()
    } catch {
      if !(error is CancellationError) { Logger.warning("[试看] \(action)失败：\(error.localizedDescription)") }
      return nil
    }
  }

  /// 这一集的试看结束了，记下结局，用户再次发起前一直显示。「可以试看」不算结局。
  private func conclude(_ key: String, _ outcome: EpisodeTrialProgress) -> EpisodeTrialProgress {
    observations[key] = nil
    if let ending = EpisodeTrialEnding(outcome) {
      var updated = endings.filter { $0.key != key }
      updated.append(EpisodeTrialStoredEnding(key: key, ending: ending, endedAt: now()))
      updated.removeFirst(max(0, updated.count - Self.endingLimit))
      saveEndings(updated)
    }
    return outcome
  }

  private func ending(for key: String) -> EpisodeTrialProgress? {
    endings.last { $0.key == key }?.ending.progress
  }

  /// 用户再次发起或这一集入库时清掉这一集的结局。
  private func clearEnding(_ key: String) {
    guard endings.contains(where: { $0.key == key }) else { return }
    saveEndings(endings.filter { $0.key != key })
  }

  /// 结局只用来显示：存不下只记日志，不打断试看；拆除后不再写，内存里的也不改。
  private func saveEndings(_ updated: [EpisodeTrialStoredEnding]) {
    guard !isTornDown, let storageKey else { return }
    endings = updated
    do {
      defaults.set(try JSONEncoder().encode(updated), forKey: storageKey + ".endings")
    } catch {
      Logger.warning("[试看] 试看结局没有保存：\(error.localizedDescription)")
    }
  }

  // MARK: - 推导与发起

  private func advance(
    _ request: EpisodeTrialRequest, mayCreate: Bool, operation: Operation
  ) async throws -> EpisodeTrialProgress {
    let key = request.key
    if mayCreate { clearEnding(key) }
    let library = await availability(request, mayCreate || Self.libraryMayChange(progress[key]))
    try operation.check()

    var reusableMarker: String?
    var ended: EpisodeTrialProgress?
    if let credential = credential(forSeason: request.seasonKey) {
      switch try await drive(credential, operation: operation) {
      case .unconfirmed:
        // 创建没确认：再按「试看」时沿用同一个标记，不论哪次请求落了库，订阅上都是同一个标记。
        // 同一季改试看别的集也沿用：换新标记会让已落库的旧占位没人认领，MoviePilot 按季去重时还会把新请求合到它上面。
        // 认回的是旧集的占位时，准备阶段按集数对不上停止并删掉它，用户再按一次即可。
        if mayCreate {
          reusableMarker = credential.marker
        } else if credential.target.episodeKey == key {
          return .submissionUnconfirmed
        }
      case .inProgress(let current):
        return credential.target.episodeKey == key ? current : .seasonTrialInProgress
      case .ended(let result):
        if credential.target.episodeKey == key { ended = result }
      }
    }

    // 只按季号集号对上也算入库：这一步只看媒体服务器上有没有这一集的文件（试看订阅在搜索结束时已经删掉），
    // 可能不是这一集，由单集面板说明。
    if let ready = Self.ready(library) {
      observations[key] = nil
      clearEnding(key)
      return ready
    }
    if observations[key] != nil {
      let observed = try await observe(key, request: request, operation: operation)
      if mayCreate, observed == .submissionUnconfirmed || observed == .waitingForOrganization {
        // 用户重新发起：下载器、整理队列和整理记录都查不到的旧下载不再挡着，按服务器现状重新推导。
        observations[key] = nil
      } else if observations[key] != nil || !mayCreate {
        return observed
      }
    }
    if let ended, !mayCreate { return ended }
    let examined = try await examine(
      request, library: library, mayCreate: mayCreate, marker: reusableMarker, operation: operation)
    if examined == .notStarted, let ending = ending(for: key) { return ending }
    return examined
  }

  private static func ready(_ library: EpisodeAvailability?) -> EpisodeTrialProgress? {
    switch library {
    case .playable(let server): .ready(server: server)
    case .uncertain(let server, let match): .ready(server: server, uncertain: match)
    default: nil
    }
  }

  /// 按服务器现状推导这一集：已有订阅、已在下载或整理时照实显示；都没有、媒体库也确认没有时才新建。
  private func examine(
    _ request: EpisodeTrialRequest, library: EpisodeAvailability?, mayCreate: Bool, marker: String?,
    operation: Operation
  ) async throws -> EpisodeTrialProgress {
    if let existing = try await existingDownload(of: request, operation: operation) {
      return existing
    }
    let ownMarkers = Set(credentials.map(\.marker))
    let subscriptions = try await operation.api.fetchSubscriptions(forceRefresh: true)
    try operation.check()
    let related = subscriptions.filter { isRelated($0, to: request) && !ownMarkers.contains($0.filter ?? "") }
    if let row = related.first(where: {
      $0.season == request.season && trimmedNonEmpty([$0.episode_group]) == request.episodeGroup
        && $0.identity.map(request.knownIdentities.contains) == true
    }) {
      return row.state == "S" ? .subscriptionPaused : .waitingForSubscription
    }
    if !related.isEmpty {
      return .unavailable("已有相关订阅，无法确认与当前季集使用同一套编号")
    }
    guard library == .notOnServer else {
      return .unavailable(library?.message ?? "无法确认媒体库是否已有这一集")
    }
    guard mayCreate else { return .notStarted }
    return try await create(request, marker: marker, operation: operation)
  }

  private func isRelated(_ row: Subscribe, to request: EpisodeTrialRequest) -> Bool {
    guard row.type == "电视剧", row.season == nil || row.season == request.season else { return false }
    if let identity = row.identity, request.knownIdentities.contains(identity) { return true }
    let names = [request.media.title, request.media.original_title].compactMap { trimmedNonEmpty([$0]) }
    let sameTitle = names.contains { $0.caseInsensitiveCompare(row.name) == .orderedSame }
    return sameTitle && (row.year == nil || request.media.year == nil || row.year == request.media.year)
  }

  /// 这一集是不是已经在下载或整理（不论哪个入口提交的）。尽力而为：只看最近几页下载记录。
  /// 下载器连不上又没在别处找到时抛错，交给调用方按“暂时无法确认”处理，不新建。
  private func existingDownload(
    of request: EpisodeTrialRequest, operation: Operation
  ) async throws -> EpisodeTrialProgress? {
    let records = try await downloadHistory(operation: operation).filter {
      $0.download_hash != nil && $0.matches(request)
    }
    guard !records.isEmpty else { return nil }
    let queue = try await operation.api.fetchEpisodeTrialTransferQueue()
    try operation.check()
    for record in records {
      guard let hash = record.download_hash else { continue }
      if let downloader = transferDownloaders(in: queue, hash: hash).first {
        observe(record, downloader: downloader, request: request)
        return .organizing
      }
    }
    guard let active = try await findActiveDownload(in: records, operation: operation) else { return nil }
    observe(active.record, downloader: active.downloader, request: request)
    return downloadProgress(request.key, progress: active.progress)
  }

  private func observe(_ record: EpisodeTrialHistoryRecord, downloader: String, request: EpisodeTrialRequest) {
    observations[request.key] = Observation(
      target: request.target, subscriptionID: nil, missingRecord: .notStarted, hash: record.download_hash,
      downloader: downloader, historyTitle: trimmedNonEmpty([record.title]))
  }

  private func create(
    _ request: EpisodeTrialRequest, marker: String?, operation: Operation
  ) async throws -> EpisodeTrialProgress {
    guard let owner = operation.api.currentOrStoredUserName, !owner.isEmpty else {
      return .unavailable("无法确认试看订阅的归属")
    }
    var credential = EpisodeTrialCredential(
      marker: marker ?? EpisodeTrialTemporarySubscription.makeMarker(at: now()), target: request.target, owner: owner)
    try store(credential)
    let receipt =
      await attempt("创建试看订阅") {
        try await operation.api.createEpisodeTrialSubscription(
          EpisodeTrialCreateSubscription(request: request, marker: credential.marker))
      } ?? .unconfirmed
    try operation.check()
    switch receipt {
    case .rejected:
      try remove(credential)
      return .unavailable("MoviePilot 拒绝创建试看订阅")
    case .unconfirmed:
      return .submissionUnconfirmed
    case .accepted(let id):
      // 后端按季去重，同季已有订阅时返回的是那一条。先记下 ID 交给后台对账：读回失败时也有人接着核对。
      // 读回来带着这次的标记才是本机建的，不是就放手不碰。
      credential.subscriptionID = id
      try store(credential)
      let row = try await operation.api.fetchSubscription(id: id)
      try operation.check()
      guard row.filter == credential.marker else {
        try remove(credential)
        return row.state == "S" ? .subscriptionPaused : .waitingForSubscription
      }
      return try await drive(credential, operation: operation).progress
    }
  }

  // MARK: - 推进本机的试看订阅

  /// 后台对账一季的凭据，结果写到那一集的进度上，页面打开时直接能看到。
  private func driveStored(seasonKey: String) async -> EpisodeTrialProgress {
    guard let api = managingAPI(), let credential = credential(forSeason: seasonKey) else {
      return Self.interrupted
    }
    let operation = Operation(api: api, session: api.sessionSnapshot())
    let key = credential.target.episodeKey
    do {
      let result = try await drive(credential, operation: operation)
      try operation.check()
      var current = result.progress
      if case .ended = result, observations[key] != nil {
        current = try await observe(key, request: nil, operation: operation)
      }
      progress[key] = current
      return current
    } catch {
      guard !(error is CancellationError), (try? operation.check()) != nil else { return Self.interrupted }
      let reported = report(error)
      // 请求失败时后台接着重试，不把页面上的进度换成「暂时无法确认」；服务自己判定的失败照实显示。
      if error is Failure { progress[key] = reported }
      return progress[key] ?? reported
    }
  }

  /// 按服务器上这条订阅的样子推进一步：认领 → 暂停 → 写规则 → 补搜 → 搜索结束后核对并删除；
  /// 要求取消时改为请求停止 → 搜索结束后核对并删除。每次都从服务器现状出发，中途中断后下次接着做。
  private func drive(_ start: EpisodeTrialCredential, operation: Operation) async throws -> Driven {
    var credential = start
    /// 服务器上这条订阅现在的样子；nil 表示已经不在（或当前账号看不到）。
    let current: Subscribe?
    if let id = credential.subscriptionID, credential.batchID != nil {
      // 补搜已经发出，只等批次结束：按 ID 读这一条就够了。订阅详情不带手动搜索状态，认领和补回批次
      // 都发生在这之前，要看整份列表。
      current = try await operation.api.fetchSubscriptionIfPresent(id: id)
      try operation.check()
    } else {
      let subscriptions = try await operation.api.fetchSubscriptions(forceRefresh: true)
      try operation.check()
      if credential.subscriptionID == nil {
        // MoviePilot 由数据库唯一键按账号和季去重，同一个标记最多落一条。
        guard
          let id = subscriptions.first(where: { $0.filter == credential.marker && $0.username == credential.owner })?
            .id, id > 0
        else { return .unconfirmed }
        credential.subscriptionID = id
        // 认领后由后台对账接着推进和收尾，不靠页面一直开着。
        try store(credential)
      }
      guard let id = credential.subscriptionID else { return .unconfirmed }
      current = subscriptions.first { $0.id == id }
    }
    guard let id = credential.subscriptionID else { return .unconfirmed }

    guard let row = current, row.filter == credential.marker, row.username == credential.owner else {
      try remove(credential)
      // 这个 ID 上是别的订阅：创建回执给的是同季已有的订阅（后端按季去重），或标记在别处被改掉了。放手不碰。
      if let existing = current {
        return .ended(existing.state == "S" ? .subscriptionPaused : .waitingForSubscription)
      }
      // 订阅已不在了：补搜提交了下载，MoviePilot 就会把这条普通订阅标成完成并删掉；否则是在别处被删掉。
      // 写过规则就可能补搜过，按下载记录接着看；补搜批次说提交过下载、却找不到记录时按无法跟踪结束。
      guard !credential.fingerprints.isEmpty || credential.batchID != nil else {
        return .ended(conclude(credential.target.episodeKey, Self.removedElsewhere))
      }
      var submitted = false
      if let batchID = credential.batchID {
        let batch = try? await searchBatch(batchID, operation: operation)
        submitted = (batch?.submittedCount ?? 0) > 0
        try operation.check()
      }
      startObservation(credential, missingRecord: submitted ? Self.untrackable : Self.removedElsewhere)
      return .ended(submitted ? .downloading(progress: nil) : .submissionUnconfirmed)
    }
    guard EpisodeTrialTemporarySubscription.isUntouched(row, by: credential) else {
      try remove(credential)
      return .ended(conclude(credential.target.episodeKey, Self.released))
    }
    if credential.cancelRequested || credential.failure != nil {
      return try await cancel(credential, row: row, operation: operation)
    }
    if row.include == EpisodeTrialTemporarySubscription.blockedInclude {
      do {
        try await prepare(&credential, row: row, operation: operation)
      } catch let failure as Failure where failure.isPermanent {
        // 重试也不会变：记下说明，不再推进，核对后删掉这条订阅。删除没成功时下次对账接着收尾。
        Logger.warning("[试看] \(failure.message)，收尾删除试看订阅 \(id)")
        credential.failure = failure.message
        try store(credential)
        return try await finish(
          credential, batch: nil, outcome: .concluded(.failed(failure.message)), operation: operation)
      }
    }

    if credential.batchID == nil, let batchID = Self.manualBatch(of: row) {
      credential.batchID = batchID
      try store(credential)
    }
    if credential.batchID == nil {
      // 回执丢了时列表上也看不到手动搜索，就再发一次；MoviePilot 对同一条订阅的搜索会排队，不会并行。
      let receipt =
        await attempt("试看补搜") { try await operation.api.searchEpisodeTrialSubscription(id: id) } ?? .unconfirmed
      try operation.check()
      switch receipt {
      case .scheduled(let batchID):
        credential.batchID = batchID
        try store(credential)
      case .rejected:
        return try await finish(
          credential, batch: nil, outcome: .concluded(.searchIncomplete("MoviePilot 拒绝试看补搜")),
          operation: operation)
      case .unconfirmed:
        return .inProgress(.searching)
      }
    }
    guard let batchID = credential.batchID else { return .inProgress(.searching) }
    guard let batch = try await searchBatch(batchID, operation: operation) else {
      // MoviePilot 已经没有这次搜索的记录，等不到它结束：删掉订阅，按下载记录看有没有提交过下载。
      return try await finish(credential, batch: nil, outcome: Self.batchLost, batchLost: true, operation: operation)
    }
    guard batch.isFinished else { return .inProgress(.searching) }
    return try await finish(credential, batch: batch, outcome: nil, operation: operation)
  }

  /// 查批次。MoviePilot 明确说没有这次搜索（404）时返回 nil；网络等其他失败照常抛出，下次对账再查。
  private func searchBatch(_ id: String, operation: Operation) async throws -> EpisodeTrialBatch? {
    do {
      let batch = try await operation.api.fetchEpisodeTrialBatch(id: id)
      try operation.check()
      return batch
    } catch APIError.serverMessage(let message) where APIService.httpStatusCode(fromServerMessage: message) == 404 {
      try operation.check()
      Logger.warning("[试看] MoviePilot 找不到试看搜索批次 \(id)")
      return nil
    }
  }

  /// 暂停占位订阅，再写入这一集的季集锁定和试看规则。写入前先记下写入后的指纹，没读回来时下次也认得出。
  /// 不是普通订阅（MoviePilot 改成了洗版）、集数对不上、MoviePilot 拒绝或没按规则保存，重试也不会变，按永久失败交给调用方收尾。
  private func prepare(
    _ credential: inout EpisodeTrialCredential, row: Subscribe, operation: Operation
  ) async throws {
    guard let id = credential.subscriptionID, (row.best_version ?? 0) == 0, (row.best_version_full ?? 0) == 0 else {
      throw Failure(message: "试看订阅没有按普通订阅创建，已停止试看", isPermanent: true)
    }
    var paused = row
    if row.state != "S" {
      let result = try await operation.api.updateSubscriptionStatus(id: id, state: "S")
      try operation.check()
      guard result.success else {
        throw Failure(
          message: trimmedNonEmpty([result.message]).map { "试看订阅暂停失败：\($0)" } ?? "试看订阅暂停失败",
          isPermanent: true)
      }
      paused = try await operation.api.fetchSubscription(id: id)
      try operation.check()
      guard EpisodeTrialTemporarySubscription.isUntouched(paused, by: credential), paused.state == "S",
        paused.include == EpisodeTrialTemporarySubscription.blockedInclude
      else { throw Failure(message: "试看订阅的配置刚刚有变化，稍后再核对", isPermanent: false) }
    }
    let episode = credential.target.episodeNumber
    // 占位订阅从目标集开始、总集数比目标集多一集；总集数改成目标集才会启用后端的手动集数锁。
    // 对不上说明这条订阅是为别的集建的（例如创建回执丢了以后同一季改试看另一集），重试也锁不住。
    guard paused.start_episode == episode, paused.total_episode != episode else {
      throw Failure(message: "试看订阅的集数和要试看的这一集对不上，已停止试看", isPermanent: true)
    }
    var draft = paused
    draft.start_episode = episode
    draft.total_episode = episode
    let defaultInclude = rule.include == nil ? try await operation.api.fetchDefaultTvSubscribeInclude() : nil
    try operation.check()
    rule.apply(to: &draft, includeFallback: defaultInclude)
    credential.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(draft)]
    try store(credential)

    let result = try await operation.api.saveSubscription(original: paused, draft: draft)
    try operation.check()
    guard result.success else {
      throw Failure(
        message: trimmedNonEmpty([result.message]).map { "保存试看订阅失败：\($0)" } ?? "保存试看订阅失败",
        isPermanent: true)
    }
    let updated = try await operation.api.fetchSubscription(id: id)
    try operation.check()
    guard updated.filter == credential.marker, updated.state == "S",
      EpisodeTrialTemporarySubscription.preservesSettings(of: draft, in: updated)
    else {
      // 写完立刻读回的就是这次写入在服务器上的结果，记下它，收尾核对时认得出这是自己写过的订阅。
      // 不一致多半是 MoviePilot 对写入值另有整理，每次都会出现；不记的话每次都留一条暂停的订阅要用户手动删。
      // 代价是保存和读回之间别处恰好改了这条订阅，改动会随收尾一起删掉，空隙和删除前重读一样只隔一个请求。
      if updated.filter == credential.marker,
        let actual = try? EpisodeTrialTemporarySubscription.fingerprint(updated)
      {
        credential.fingerprints.insert(actual)
        try store(credential)
      }
      throw Failure(message: "MoviePilot 没有按试看规则保存这条订阅，已停止试看", isPermanent: true)
    }
  }

  /// 用户取消或永久失败后的收尾：请求停止这次搜索，查到批次已结束才删订阅；没结束时保持「取消中」，下次对账接着查。
  /// MoviePilot 已经没有这次搜索的记录时不再等，删掉订阅，按下载记录看有没有提交过下载。
  private func cancel(
    _ credential: EpisodeTrialCredential, row: Subscribe, operation: Operation
  ) async throws -> Driven {
    let outcome = credential.failure.map { EpisodeTrialProgress.concluded(.failed($0)) } ?? Self.cancelled
    // 回执和订阅行上都没有批次，就是补搜没被受理：MoviePilot 先把搜索任务入库才回执，订阅行显示最近一次任务。
    // 请求还在服务器上没处理完的话，删掉订阅后那次搜索在提交下载前查不到订阅，会自己放弃。
    guard let batchID = credential.batchID ?? Self.manualBatch(of: row) else {
      return try await finish(credential, batch: nil, outcome: outcome, operation: operation)
    }
    var batch = try await searchBatch(batchID, operation: operation)
    if let current = batch, !current.isFinished {
      _ = await attempt("停止试看搜索") { try await operation.api.cancelEpisodeTrialBatch(id: batchID) }
      try operation.check()
      batch = try await searchBatch(batchID, operation: operation)
    }
    guard let batch else {
      return try await finish(credential, batch: nil, outcome: outcome, batchLost: true, operation: operation)
    }
    guard batch.isFinished else { return .inProgress(.cancelling) }
    return try await finish(credential, batch: batch, outcome: outcome, operation: operation)
  }

  /// 删除前当场按 ID 重读核对：只删本机建的、没被别处改过的那一条。删掉后提交过下载的，接着看下载；
  /// `batchLost` 表示不知道这次搜索提交过什么，按下载记录找，找不到就以 `outcome` 结束。
  private func finish(
    _ credential: EpisodeTrialCredential, batch: EpisodeTrialBatch?, outcome: EpisodeTrialProgress?,
    batchLost: Bool = false, operation: Operation
  ) async throws -> Driven {
    guard let id = credential.subscriptionID else { return .unconfirmed }
    let key = credential.target.episodeKey
    let row = try await operation.api.fetchSubscription(id: id)
    try operation.check()
    guard EpisodeTrialTemporarySubscription.isUntouched(row, by: credential) else {
      try remove(credential)
      return .ended(conclude(key, Self.released))
    }
    guard try await operation.api.deleteSubscription(id: id) else {
      throw Failure(message: "试看订阅暂时没删掉，稍后会再试", isPermanent: false)
    }
    try operation.check()
    try remove(credential)
    NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    if let batch, batch.submittedCount > 0 {
      startObservation(credential, missingRecord: Self.untrackable)
      return .ended(.downloading(progress: nil))
    }
    if batchLost {
      startObservation(credential, missingRecord: outcome ?? Self.batchLost)
      return .ended(.submissionUnconfirmed)
    }
    return .ended(conclude(key, outcome ?? Self.outcome(of: batch)))
  }

  private static func outcome(of batch: EpisodeTrialBatch?) -> EpisodeTrialProgress {
    switch batch?.state {
    case "completed": .concluded(.noEligibleResource)
    case "cancelled": EpisodeTrialService.cancelled
    case "skipped": .concluded(.searchIncomplete("MoviePilot 跳过了本次试看搜索，可以重新试看"))
    default: .concluded(.searchIncomplete("MoviePilot 没有完成本次试看搜索，可以重新试看"))
    }
  }

  private static func manualBatch(of row: Subscribe) -> String? {
    guard let execution = row.execution_status, execution.source == "manual",
      let batchID = execution.batch_id, EpisodeTrialBatch.isValidID(batchID)
    else { return nil }
    return batchID
  }

  // MARK: - 凭据

  private func credential(forSeason seasonKey: String) -> EpisodeTrialCredential? {
    credentials.first { $0.target.seasonKey == seasonKey }
  }

  /// 一季只留一条凭据。没确认的凭据按条数淘汰最早的。
  private func store(_ credential: EpisodeTrialCredential) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    var updated = credentials.filter {
      $0.marker != credential.marker && $0.target.seasonKey != credential.target.seasonKey
    }
    updated.append(credential)
    let unconfirmed = updated.filter { $0.subscriptionID == nil }
    if unconfirmed.count > Self.unconfirmedLimit {
      let dropped = Set(unconfirmed.prefix(unconfirmed.count - Self.unconfirmedLimit).map(\.marker))
      updated.removeAll { dropped.contains($0.marker) }
    }
    try persist(updated, storageKey: storageKey)
  }

  private func remove(_ credential: EpisodeTrialCredential) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    try persist(credentials.filter { $0.marker != credential.marker }, storageKey: storageKey)
  }

  /// 凭据一有已确认的订阅（新建、认领或回执给了 ID），后台对账就接手推进和收尾。
  private func persist(_ updated: [EpisodeTrialCredential], storageKey: String) throws {
    defaults.set(try JSONEncoder().encode(updated), forKey: storageKey + ".credentials")
    credentials = updated
    scheduleDrive()
  }

  /// 有已确认的本机试看订阅时按间隔对账，推进或收尾；只剩没确认的凭据时不轮询，等用户再按「试看」。
  private func scheduleDrive() {
    guard !isTornDown, driveLoop == nil, credentials.contains(where: { $0.subscriptionID != nil }) else { return }
    let sleep = self.sleep
    driveLoop = Task { [weak self] in
      while self?.credentials.contains(where: { $0.subscriptionID != nil }) == true {
        do { try await sleep(Self.driveInterval) } catch { break }
        guard let self, !Task.isCancelled else { break }
        for seasonKey in Set(self.credentials.map(\.target.seasonKey)) {
          guard let key = self.credential(forSeason: seasonKey)?.target.episodeKey else { continue }
          _ = await self.enqueue(seasonKey: seasonKey, key: key, kind: .drive) { service in
            await service.driveStored(seasonKey: seasonKey)
          }
        }
      }
      self?.driveLoop = nil
    }
  }

  // MARK: - 订阅删掉以后看下载

  private func startObservation(_ credential: EpisodeTrialCredential, missingRecord: EpisodeTrialProgress) {
    observations[credential.target.episodeKey] = Observation(
      target: credential.target, subscriptionID: credential.subscriptionID, missingRecord: missingRecord)
  }

  /// 按下载记录找到这次试看提交的下载，再看下载器和整理。找不到下载记录就结束观察；下载、整理队列和整理记录
  /// 都明确查不到时（下载器只列出还在下载的任务，下完到开始整理之间会这样）显示等待整理，照常留着，放慢再看；
  /// 有一处没查成时说不清，显示没确认。
  ///
  /// 看到下完了，叫 MoviePilot 马上整理；看到整理好了，叫媒体服务器马上入库，过一阵还没入库再叫它刷新整个库
  /// （要有 `request` 才知道是哪部剧，后台对账没有时等下次刷新再叫）。每件事每次观察只叫一次，失败只记日志，照常等它们自己来。
  private func observe(
    _ key: String, request: EpisodeTrialRequest?, operation: Operation
  ) async throws -> EpisodeTrialProgress {
    guard var observation = observations[key] else { return .notStarted }
    if observation.hash == nil {
      let record = try await downloadHistory(operation: operation).first {
        $0.download_hash != nil && $0.matches(observation.target)
          && (observation.subscriptionID == nil || $0.subscriptionID == observation.subscriptionID)
      }
      guard let record else { return conclude(key, observation.missingRecord) }
      observation.hash = record.download_hash
      observation.downloader = record.downloader
      observation.historyTitle = trimmedNonEmpty([record.title])
      observations[key] = observation
    }
    guard let hash = observation.hash else { return conclude(key, observation.missingRecord) }

    // 下载器只列出还没下完的任务，下完才会整理：还在里面就是还在下载，不用再查整理记录和整理队列。
    // 下载中页面 3 秒刷新一次，每次只发这一个请求。下载器没查成时先看整理那边，也没有才算这次没查成。
    var downloaderFailure: Error?
    if let downloader = observation.downloader {
      do {
        let tasks = try await operation.api.fetchDownloading(clientName: downloader)
        try operation.check()
        if let task = tasks.first(where: { $0.hash == hash }) {
          observations[key]?.missingSince = nil
          return downloadProgress(key, progress: task.progress.flatMap { $0.isFinite ? $0 : nil })
        }
      } catch {
        if error is CancellationError { throw error }
        try operation.check()
        downloaderFailure = error
      }
    }

    let transfer = try await transferRecord(hash: hash, observation: observation, operation: operation)
    if let record = transfer.record, let transferred = record.status {
      guard transferred else { return conclude(key, .concluded(.organizationFailed)) }
      observations[key]?.missingSince = nil
      if let request { requestLibraryScan(key: key, context: request.playbackContext, file: record.location) }
      return .waitingForLibrary
    }
    // 三处都成功查过、都没有，才算明确查不到；有一处没查成就不计时。
    var confirmedMissing = transfer.isComplete
    if let queue = await attempt("读取整理队列", { try await operation.api.fetchEpisodeTrialTransferQueue() }) {
      try operation.check()
      if !transferDownloaders(in: queue, hash: hash).isEmpty {
        observations[key]?.missingSince = nil
        return .organizing
      }
    } else {
      confirmedMissing = false
    }
    try operation.check()
    if let downloaderFailure { throw downloaderFailure }
    if observation.downloader == nil {
      if let records = await attempt("读取下载记录", { try await self.downloadHistory(operation: operation) }) {
        try operation.check()
        if let active = try await findActiveDownload(
          in: records.filter { $0.download_hash == hash }, operation: operation)
        {
          observations[key]?.downloader = active.downloader
          observations[key]?.missingSince = nil
          return downloadProgress(key, progress: active.progress)
        }
      } else {
        confirmedMissing = false
      }
    }
    try operation.check()
    guard confirmedMissing else { return .submissionUnconfirmed }
    let since = observation.missingSince ?? now()
    observations[key]?.missingSince = since
    guard now().timeIntervalSince(since) < Self.missingDownloadLimit else {
      return conclude(key, Self.downloadGone)
    }
    requestOrganization(key: key)
    return .waitingForOrganization
  }

  /// 还在下载：进度和按平均速度估的剩余时间（见 `EpisodeTrialDownloadETA`）。第一次看到、或进度倒退了（下载器重新校验）时
  /// 从这里重新算起。
  private func downloadProgress(_ key: String, progress: Double?) -> EpisodeTrialProgress {
    guard let progress else { return .downloading(progress: nil) }
    let now = now()
    guard let eta = observations[key]?.downloadETA, progress >= eta.startProgress else {
      observations[key]?.downloadETA = EpisodeTrialDownloadETA(since: now, startProgress: progress)
      return .downloading(progress: progress)
    }
    return .downloading(progress: progress, remainingSeconds: eta.remainingSeconds(progress: progress, now: now))
  }

  /// 下载器里看不到这次下载了，多半是下完了：叫 MoviePilot 马上整理，不等它每 5 分钟一次的定时整理。
  /// 会顺带整理下载器里其他下完还没整理的任务（本来 5 分钟内也会整理）。
  private func requestOrganization(key: String) {
    guard observations[key]?.organizationRequested == false else { return }
    observations[key]?.organizationRequested = true
    nudge("叫 MoviePilot 马上整理") { api in
      let result = try await api.runDownloadTransfer()
      if !result.success {
        Logger.warning("[试看] MoviePilot 没有受理马上整理：\(result.message ?? "没有说明")")
      }
    }
  }

  /// 整理好了：叫媒体服务器马上入库，不等它自己发现新文件（Emby 的实时监控要等一分半，网络挂载常常收不到通知）。
  /// 先按整理后的位置刷新；叫过 `libraryScanFallbackDelay` 还没入库（这里只在还没入库时才会走到），再叫每台刷新整个库。
  private func requestLibraryScan(key: String, context: EpisodePlaybackContext, file: TransferredFileLocation) {
    guard let observation = observations[key] else { return }
    let scan = libraryScan
    guard let requestedAt = observation.libraryScanRequestedAt else {
      observations[key]?.libraryScanRequestedAt = now()
      nudge("叫媒体服务器入库") { _ in await scan(context, .located(file)) }
      return
    }
    guard !observation.wholeLibraryScanRequested,
      now().timeIntervalSince(requestedAt) >= Self.libraryScanFallbackDelay
    else { return }
    observations[key]?.wholeLibraryScanRequested = true
    nudge("叫媒体服务器刷新整个库") { _ in await scan(context, .everything) }
  }

  /// 只是催一下、不影响试看进度的请求：不排进这一季的推进队列，不等它返回；失败只记日志。拆除时一起取消。
  private func nudge(_ action: String, _ work: @escaping @MainActor (APIService) async throws -> Void) {
    guard let api = managingAPI() else { return }
    let id = UUID()
    nudges[id] = Task { [weak self] in
      do {
        try await work(api)
      } catch is CancellationError {
      } catch {
        Logger.warning("[试看] \(action)失败：\(error.localizedDescription)")
      }
      self?.nudges[id] = nil
    }
  }

  /// 下载记录按时间倒序，最近几页。
  private func downloadHistory(operation: Operation) async throws -> [EpisodeTrialHistoryRecord] {
    var records: [EpisodeTrialHistoryRecord] = []
    for page in 1...Self.historyPageLimit {
      let batch = try await operation.api.fetchEpisodeTrialDownloadHistory(page: page)
      try operation.check()
      records += batch
      guard batch.count >= APIService.episodeTrialHistoryPageSize else { break }
    }
    return records
  }

  /// 整理历史只能按标题模糊查询。先用 MoviePilot 下载时识别的标题，再用页面标题，都查不到时看最新一页，
  /// 按下载 hash 认定是哪一条。查不到不代表没整理；`isComplete` 表示这几次查询都成功了。
  private func transferRecord(
    hash: String, observation: Observation, operation: Operation
  ) async throws -> (record: EpisodeTrialHistoryRecord?, isComplete: Bool) {
    var titles: [String?] = []
    for title in [observation.historyTitle, observation.target.title] {
      if let title = trimmedNonEmpty([title]), !titles.contains(title) { titles.append(title) }
    }
    titles.append(nil)
    var isComplete = true
    for title in titles {
      let history = await attempt("读取整理记录") {
        try await operation.api.fetchEpisodeTrialTransferHistory(title: title)
      }
      try operation.check()
      if history == nil { isComplete = false }
      if let record = history?.first(where: { $0.download_hash == hash && $0.matches(observation.target) }) {
        return (record, true)
      }
    }
    return (nil, isComplete)
  }

  private struct ActiveDownload {
    let record: EpisodeTrialHistoryRecord
    let downloader: String
    let progress: Double?
  }

  /// 只查询可能持有这些记录的下载器。个别下载器连不上时，只要其他下载器已找到任务就继续；
  /// 都没找到时不能断定没有在下载，抛错交给调用方按“暂时无法确认”处理。
  private func findActiveDownload(
    in history: [EpisodeTrialHistoryRecord], operation: Operation
  ) async throws -> ActiveDownload? {
    guard !history.isEmpty else { return nil }
    let clients = try await operation.api.fetchDownloadClients()
    try operation.check()
    var unreachable = false
    for client in clients where client.enabled?.value != false {
      let records = history.filter { $0.downloader == nil || $0.downloader == client.name }
      guard !records.isEmpty else { continue }
      let downloads: [DownloadingInfo]
      do {
        downloads = try await operation.api.fetchDownloading(clientName: client.name)
      } catch {
        try operation.check()
        unreachable = true
        continue
      }
      try operation.check()
      for record in records {
        if let download = downloads.first(where: { $0.hash == record.download_hash }) {
          let progress = download.progress.flatMap { $0.isFinite ? $0 : nil }
          return ActiveDownload(record: record, downloader: client.name, progress: progress)
        }
      }
    }
    if unreachable {
      throw Failure(message: "有下载器暂时无法连接，无法确认这一集是否正在下载", isPermanent: false)
    }
    return nil
  }

  private func transferDownloaders(in queue: [EpisodeTrialTransferJob], hash: String) -> Set<String> {
    Set(queue.flatMap { $0.tasks ?? [] }.filter { $0.download_hash == hash }.compactMap(\.downloader))
  }

  /// 媒体库里这一集可能刚有或刚没的时候才重读媒体服务器；搜索、下载中这一集进不了媒体库，按缓存查就够了。
  private static func libraryMayChange(_ progress: EpisodeTrialProgress?) -> Bool {
    switch progress {
    case nil, .notStarted, .waitingForOrganization, .organizing, .concluded(.organizationFailed), .waitingForLibrary,
      .ready, .submissionUnconfirmed:
      true
    default: false
    }
  }
}
