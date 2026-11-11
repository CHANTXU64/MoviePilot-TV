import Combine
import Foundation

/// 试看任务与订阅行分开保存。MoviePilot 可以在接收下载后立即完成并删除订阅。
@MainActor
final class EpisodeTrialService: ObservableObject {
  nonisolated deinit {}

  /// 查这一集在不在媒体库里；`fresh` 时不沿用媒体服务器的集索引缓存。
  typealias Availability = @MainActor (EpisodeTrialRequest, _ fresh: Bool) async -> EpisodeAvailability?
  typealias Sleep = @Sendable (Duration) async throws -> Void

  private static let interrupted = EpisodeTrialProgress.unavailable("本次试看查询已中断")
  private static let restartable = EpisodeTrialProgress.unavailable("上次试看准备未完成，可以重新发起")
  private static let editedElsewhere = EpisodeTrialProgress.unavailable("试看订阅已由其他入口修改")
  private static let formalEnded = EpisodeTrialProgress.unavailable("原订阅已结束，可以发起试看")
  static let cancelled = EpisodeTrialProgress.unavailable("已取消试看，可以重新发起")
  private static let leftLibrary = EpisodeTrialProgress.unavailable("这一集已不在媒体库里，可以重新发起")
  private static let downloadGone = EpisodeTrialProgress.unavailable("试看的下载已不在下载器里，可以重新发起")
  /// 下载在下载器、整理队列和整理历史里都找不到，持续这么久才算结束。
  private static let missingDownloadWindow: TimeInterval = 60 * 60
  /// 补搜回执丢了、订阅也没了时，MoviePilot 那次搜索最多还能运行的时长（搜索执行权两小时），再留些余量。
  private static let lostSearchWindow: TimeInterval = 130 * 60
  private static let cancelFailed = EpisodeTrialProgress.unavailable(EpisodeTrialHoldNotice.cancelFailure)
  /// 临时订阅创建后这段时间内补搜通常还在进行，清理检查得勤一些；之后放慢，直到服务器上没有本服务的临时订阅。
  private static let activeCleanupPeriod: TimeInterval = 20 * 60
  private static let activeCleanupInterval = Duration.seconds(20)
  private static let idleCleanupInterval = Duration.seconds(10 * 60)
  /// 页面可见时的刷新间隔：试看进行中跟得紧一些；只是在等正式订阅时放慢。
  nonisolated static let activePollInterval = Duration.seconds(10)
  nonisolated static let formalPollInterval = Duration.seconds(60)

  @Published private(set) var progress: [String: EpisodeTrialProgress] = [:]
  /// 当前账号保存的试看规则；没保存过时是默认规则，沿用 MoviePilot 的默认站点、规则组和下载设置。
  @Published private(set) var rule = EpisodeTrialRule()
  private weak var api: APIService?
  private let defaults: UserDefaults
  private let storageKey: String?
  private let availability: Availability
  private let now: @MainActor () -> Date
  private let sleep: Sleep
  private var jobs: [String: EpisodeTrialJob] = [:]
  private var seasonRuns: [String: SeasonRun] = [:]
  private var cleanupLoop: Task<Void, Never>?
  private var cleanupLoopID: UUID?
  /// 清理循环正在等的间隔；正在对账时为空。
  private var cleanupSleep: Duration?
  private var isTornDown = false
  /// 正在显示这一集的页面，各自等着这一集被发起后接着刷新。有页面时进度直接显示在页面上，不另发通知。
  private var visiblePages: [String: [UUID: AsyncStream<Void>.Continuation]] = [:]
  /// 没有页面在看时接着跟踪的试看。只在本次运行内、试看还在进行时存在。
  private var followers: [String: Follower] = [:]

  private struct Follower {
    let id: UUID
    let task: Task<Void, Never>
  }

  /// 范围大的推进覆盖范围小的：发起包含刷新，刷新包含清理。
  private enum RunKind: Int, Comparable {
    case cleanup, refresh, start

    static func < (lhs: RunKind, rhs: RunKind) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  /// 后端按季去重订阅，同一季同时只能有一条试看订阅，所以同季的推进依次执行。
  /// 推进由服务持有：页面离开不会把创建、暂停、写规则和补搜截断在中间，会话拆除时统一取消。
  private struct SeasonRun {
    let key: String
    let kind: RunKind
    let task: Task<EpisodeTrialProgress, Never>
  }

  init(
    api: APIService, defaults: UserDefaults = .standard,
    now: @escaping @MainActor () -> Date = { Date() },
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    availability: @escaping Availability
  ) {
    self.api = api
    self.defaults = defaults
    self.now = now
    self.sleep = sleep
    storageKey = api.profileKey.map { "episodeTrial.v1.\($0)" }
    if let storageKey, let data = defaults.data(forKey: storageKey + ".jobs"),
      let saved = try? JSONDecoder().decode([String: EpisodeTrialJob].self, from: data)
    {
      jobs = saved
      progress = saved.mapValues(\.progress)
    }
    if let storageKey, let data = defaults.data(forKey: storageKey + ".rule"),
      let saved = try? JSONDecoder().decode(EpisodeTrialRule.self, from: data)
    {
      rule = saved
    }
    self.availability = availability
    scheduleCleanup()
  }

  /// 规则只影响之后发起的试看；已经写进服务器的临时订阅不跟着改。
  func saveRule(_ rule: EpisodeTrialRule) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    defaults.set(try JSONEncoder().encode(rule), forKey: storageKey + ".rule")
    self.rule = rule
  }

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
  /// 试看进行中按间隔刷新；没有需要跟踪的事（从没发起、已结束或可以播放）时不请求后端，等这一集被发起再继续。
  /// 只推进已有的试看，不会发起新的。页面离开时试看还在进行，就转给服务在后台接着跟踪。
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
      let wasTracking = jobs[key]?.isTracking == true
      let current = await refresh(request)
      // 刷新途中页面离开了，这次变成可以播放已经没人看到，照样通知。从没试看过、本来就在库里的不算。
      if Task.isCancelled, wasTracking, visiblePages[key]?.count == 1 {
        announceIfReady(request, from: before, to: current)
      }
      guard !Task.isCancelled else { return }
      if let delay = pollDelay(for: key) {
        do { try await sleep(delay) } catch { return }
      } else if await wakeUps.next() == nil {
        return
      }
    }
  }

  private func leavePage(_ request: EpisodeTrialRequest, id: UUID) {
    visiblePages[request.key]?.removeValue(forKey: id)?.finish()
    guard visiblePages[request.key]?.isEmpty != false else { return }
    visiblePages[request.key] = nil
    follow(request)
  }

  /// 没有页面在看时接着跟踪进行中的试看，入库后发通知，用户离开详情页也能知道可以播放了。
  /// 只在等正式订阅时不跟，避免 App 开着就一直请求后端。App 重启后不会恢复，进度等页面再打开时刷新。
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
        self.announceIfReady(request, from: before, to: current)
      }
      if self?.followers[key]?.id == id { self?.followers[key] = nil }
    }
    followers[key] = Follower(id: id, task: task)
  }

  private func backgroundDelay(for key: String) -> Duration? {
    pollDelay(for: key) == Self.activePollInterval ? Self.activePollInterval : nil
  }

  private func announceIfReady(
    _ request: EpisodeTrialRequest, from before: EpisodeTrialProgress?, to current: EpisodeTrialProgress
  ) {
    guard current.isReady, before?.isReady != true, !isTornDown, let api else { return }
    NotificationCenter.default.post(
      name: .episodeTrialDidBecomeReady, object: api,
      userInfo: [EpisodeTrialReadyNotice.messageKey: EpisodeTrialReadyNotice.message(for: request)])
  }

  private func pollDelay(for key: String) -> Duration? {
    guard let job = jobs[key], job.isTracking else { return nil }
    let followsFormalOnly = job.formalSubscriptionID != nil && job.temporary == nil && job.creationMarker == nil
      && job.downloadHash == nil
    return followsFormalOnly ? Self.formalPollInterval : Self.activePollInterval
  }

  /// 用户在订阅卡片或订阅面板上取消试看：停掉还在进行的搜索，删除这条试看订阅，这一季就能正常订阅。
  /// 别的设备或重装前发起的试看也能取消；已经提交给下载器的任务不动。返回试看订阅是否已经不在了。
  func cancelTrial(subscriptionID id: Int) async -> Bool {
    let seasonKey = await cancelSeasonKey(for: id)
    let result = await enqueue(seasonKey: seasonKey, key: "cancel-\(id)", kind: .start) { service in
      await service.performCancel(subscriptionID: id)
    }
    return result == Self.cancelled
  }

  /// 取消只是停掉搜索、删掉订阅，旧版本后端也能做；试看订阅只有管理员建得出来，也只有管理员能删。
  var canCancelTrial: Bool { !isTornDown && api?.canRequestSuperUserEndpoints == true }

  /// 取消和本服务对同一季的推进排在一起，避免一边删订阅一边还在写规则或补搜。
  /// 创建回执还没拿到的试看只记着标记，按订阅列表里这条订阅的标记找到它属于哪一季；标记创建后不变，列表缓存就够用。
  private func cancelSeasonKey(for id: Int) async -> String {
    if let job = jobs.values.first(where: { $0.temporary?.id == id }), let key = job.target?.seasonKey { return key }
    let pending = jobs.values.filter { $0.creationMarker != nil }
    if !pending.isEmpty, let api,
      let marker = (try? await api.fetchSubscriptions())?.first(where: { $0.id == id })?.filter,
      let key = pending.first(where: { $0.creationMarker == marker })?.target?.seasonKey
    {
      return key
    }
    return "cancel-\(id)"
  }

  /// 只有 MoviePilot 确认已停止，或者这次搜索已经结束，才能确定它不会再往下载器提交；
  /// 停止请求失败、答复说不清时不删订阅，让用户稍后再试。
  private func stopSearch(_ batchID: String, operation: Operation) async throws -> Bool {
    let stopped = try? await operation.api.cancelEpisodeTrialBatch(id: batchID)
    try operation.check()
    if stopped == true { return true }
    let batch = try? await operation.api.fetchEpisodeTrialBatch(id: batchID)
    try operation.check()
    return batch?.isFinished == true
  }

  private func performCancel(subscriptionID id: Int) async -> EpisodeTrialProgress {
    guard canCancelTrial, !Task.isCancelled, let api else { return Self.cancelFailed }
    let operation = Operation(api: api, session: api.sessionSnapshot())
    do {
      let row = try await operation.api.fetchSubscriptions(forceRefresh: true).first { $0.id == id }
      try operation.check()
      // 确认时看到的是试看订阅，这时同一个 ID 已经不是了，就不删。
      if let row, !row.isEpisodeTrial { return Self.cancelFailed }
      let owned = jobs.filter { _, job in
        job.temporary?.id == id || (row?.filter != nil && job.creationMarker == row?.filter)
      }
      if let row {
        let batches = Set(([row.execution_status?.batch_id] + owned.values.map(\.batchID)).compactMap { $0 })
        for batch in batches where EpisodeTrialBatch.isValidID(batch) {
          guard try await stopSearch(batch, operation: operation) else { return Self.cancelFailed }
        }
        guard try await operation.api.deleteSubscription(id: id) else { return Self.cancelFailed }
        try operation.check()
      }
      for (key, job) in owned {
        var ended = EpisodeTrialJob()
        ended.target = job.target
        ended.finishedTemporaryID = id
        ended.progress = Self.cancelled
        try save(ended, key: key)
      }
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
      return Self.cancelled
    } catch {
      return Self.cancelFailed
    }
  }

  func tearDown() {
    isTornDown = true
    for run in seasonRuns.values { run.task.cancel() }
    seasonRuns.removeAll()
    cleanupLoop?.cancel()
    cleanupLoop = nil
    cleanupLoopID = nil
    cleanupSleep = nil
    for follower in followers.values { follower.task.cancel() }
    followers.removeAll()
    for pages in visiblePages.values { for page in pages.values { page.finish() } }
    visiblePages.removeAll()
    jobs.removeAll()
    progress.removeAll()
  }

  private struct Operation {
    let api: APIService
    let session: APIServiceSessionSnapshot

    func check() throws {
      try Task.checkCancellation()
      guard api.isSessionUnchanged(from: session) else { throw CancellationError() }
    }
  }

  private func save(_ job: EpisodeTrialJob, key: String) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    jobs[key] = job
    let recoverable = jobs.filter { $0.value.isTracking }
    defaults.set(try JSONEncoder().encode(recoverable), forKey: storageKey + ".jobs")
    progress[key] = job.progress
    scheduleCleanup()
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

  /// 试看只对支持的版本和管理员会话开放；清理沿用同一前提，旧版本或无权限时不碰服务器。
  private func availableAPI() -> APIService? {
    guard !isTornDown, !Task.isCancelled, let api, storageKey != nil,
      EpisodeTrialAvailability.isAvailable(
        canRequestSuperUserEndpoints: api.canRequestSuperUserEndpoints,
        backendVersion: api.settings?.BACKEND_VERSION)
    else { return nil }
    return api
  }

  private func run(_ request: EpisodeTrialRequest, mayCreate: Bool) async -> EpisodeTrialProgress {
    guard !isTornDown, !Task.isCancelled else { return Self.interrupted }
    guard let api = availableAPI() else {
      return .unavailable(EpisodeTrialAvailability.requirementMessage)
    }

    var job = jobs[request.key] ?? EpisodeTrialJob()
    if mayCreate, job.canRestart {
      job = EpisodeTrialJob()
    }
    job.target = request.target
    let operation = Operation(api: api, session: api.sessionSnapshot())
    do {
      try await update(&job, for: request, mayCreate: mayCreate, operation: operation)
      try operation.check()
      try save(job, key: request.key)
    } catch is CancellationError {
      return Self.interrupted
    } catch {
      guard (try? operation.check()) != nil else { return Self.interrupted }
      if !job.progress.isReady {
        job.progress = job.creationMarker != nil || job.searchPending
          ? .submissionUnconfirmed : .unavailable("暂时无法确认试看进度")
      }
      try? save(job, key: request.key)
    }
    return job.progress
  }

  // MARK: - 定时清理

  /// 只要还有任务可能在服务器上留着临时订阅，就按间隔对账；App 重启后从持久化的任务继续，
  /// 不需要用户重新打开那一集。
  /// 循环正按空闲间隔等着时又发起了新的试看，就提前醒来改按密的间隔对账。
  private func scheduleCleanup() {
    guard !isTornDown, let next = nextCleanupDelay() else { return }
    if let loop = cleanupLoop {
      guard let sleeping = cleanupSleep, next < sleeping else { return }
      loop.cancel()
    }
    let id = UUID()
    let sleep = self.sleep
    cleanupLoopID = id
    cleanupLoop = Task { [weak self] in
      while let delay = self?.nextCleanupDelay() {
        self?.cleanupSleep = delay
        do { try await sleep(delay) } catch { break }
        guard let self, !Task.isCancelled else { break }
        self.cleanupSleep = nil
        await self.cleanUpTemporarySubscriptions()
      }
      guard let self, self.cleanupLoopID == id else { return }
      self.cleanupLoop = nil
      self.cleanupLoopID = nil
      self.cleanupSleep = nil
    }
  }

  private func nextCleanupDelay() -> Duration? {
    let date = now()
    let starts = jobs.values.filter(\.needsCleanup).map { $0.cleanupStartedAt ?? .distantPast }
    guard !starts.isEmpty else { return nil }
    let active = starts.contains { date.timeIntervalSince($0) < Self.activeCleanupPeriod }
    return active ? Self.activeCleanupInterval : Self.idleCleanupInterval
  }

  private func cleanUpTemporarySubscriptions() async {
    for (key, job) in jobs where job.needsCleanup {
      guard let target = job.target else { continue }
      _ = await enqueue(seasonKey: target.seasonKey, key: key, kind: .cleanup) { service in
        await service.cleanUp(key: key)
      }
    }
  }

  private func cleanUp(key: String) async -> EpisodeTrialProgress {
    guard let api = availableAPI() else { return Self.interrupted }
    guard var job = jobs[key], job.needsCleanup, let target = job.target else {
      return jobs[key]?.progress ?? .checking
    }
    let operation = Operation(api: api, session: api.sessionSnapshot())
    do {
      try await reconcileTemporary(&job, target: target, key: key, operation: operation)
      try operation.check()
      try save(job, key: key)
    } catch is CancellationError {
      return Self.interrupted
    } catch {
      // 清理失败只记下已确认的部分，下一轮再试；不覆盖页面上的进度。
      guard (try? operation.check()) != nil else { return Self.interrupted }
      try? save(job, key: key)
    }
    return job.progress
  }

  // MARK: - 推进

  private func update(
    _ job: inout EpisodeTrialJob, for request: EpisodeTrialRequest, mayCreate: Bool, operation: Operation
  ) async throws {
    let library = await availability(request, mayCreate || job.libraryMayChange)
    try operation.check()
    if case .playable(let server) = library {
      job.progress = .ready(server: server)
    } else if library == .notOnServer, job.progress.isReady {
      // 入库后又从媒体库里删掉了：不再显示可以播放，可以重新试看。带来这次入库的下载和正式订阅都已了结，
      // 不再跟踪；服务器上还留着的临时订阅照常收尾。
      job.progress = Self.leftLibrary
      job.formalSubscriptionID = nil
      job.previousDownloadHistoryIDs = []
      job.searchMayHaveDownloaded = false
      job.searchLostSince = nil
      job.downloadHash = nil
      job.downloader = nil
      job.historyTitle = nil
      job.downloadMissingSince = nil
    }

    if job.creationMarker != nil || job.temporary != nil {
      try await reconcileTemporary(&job, target: request.target, key: request.key, operation: operation)
    }
    if job.progress.isReady { return }

    if let hash = job.downloadHash {
      try await trackDownload(hash, job: &job, request: request, operation: operation)
      return
    }

    if job.creationMarker != nil { return }
    if job.temporary != nil || job.searchPending || job.searchMayHaveDownloaded {
      let history = try await operation.api.fetchEpisodeTrialDownloadHistory()
      try operation.check()
      if let id = job.temporary?.id ?? job.finishedTemporaryID,
        let record = history.first(where: {
          $0.note?.subscription_download?.subscription_id == id
            && !job.previousDownloadHistoryIDs.contains($0.id) && $0.download_hash != nil && $0.matches(request)
        }), let hash = record.download_hash
      {
        try attach(record, job: &job, key: request.key)
        try await trackDownload(hash, job: &job, request: request, operation: operation)
      } else if job.temporary == nil, !job.searchPending, job.batchID == nil, let since = job.searchLostSince,
        now().timeIntervalSince(since) >= Self.lostSearchWindow
      {
        // 那次搜索早已超过最长运行时间，下载历史里仍没有它提交的下载，就不会再有了。
        job.searchMayHaveDownloaded = false
        job.searchLostSince = nil
        job.progress = Self.restartable
      }
      return
    }

    guard mayCreate || job.formalSubscriptionID != nil else { return }
    let fetched = try await operation.api.fetchSubscriptions(forceRefresh: true)
    try operation.check()
    let subscriptions =
      mayCreate
      ? try await removeAbandonedPlaceholders(from: fetched, request: request, operation: operation)
      : fetched
    let history = try await operation.api.fetchEpisodeTrialDownloadHistory()
    try operation.check()
    let matchingHistory = history.filter { $0.download_hash != nil && $0.matches(request) }
    if let active = try await findActiveDownload(in: matchingHistory, operation: operation) {
      try attach(active.record, downloader: active.downloader, job: &job, key: request.key)
      job.progress = .downloading(progress: active.progress)
      return
    }
    if !matchingHistory.isEmpty {
      let queue = try await operation.api.fetchEpisodeTrialTransferQueue()
      try operation.check()
      for record in matchingHistory {
        guard let hash = record.download_hash else { continue }
        let downloaders = transferDownloaders(in: queue, hash: hash)
        guard downloaders.count <= 1 else {
          throw APIError.serverMessage("无法确认目标集在整理队列中对应的下载器")
        }
        if let downloader = downloaders.first {
          try attach(record, downloader: downloader, job: &job, key: request.key)
          job.progress = .organizing
          return
        }
      }
    }

    if let id = job.formalSubscriptionID {
      if let record = matchingHistory.first(where: {
        $0.note?.subscription_download?.subscription_id == id && !job.previousDownloadHistoryIDs.contains($0.id)
      }), let hash = record.download_hash {
        try attach(record, job: &job, key: request.key)
        try await trackDownload(hash, job: &job, request: request, operation: operation)
        return
      }
      if let formal = subscriptions.first(where: { $0.id == id }) {
        job.progress = formal.state == "S" ? .subscriptionPaused : .waitingForSubscription
        return
      }
      // 正式订阅已结束。仍在下载或整理的情况上面已经接住；这期间新下载的这一集若已整理成功，
      // 只是媒体库还没扫到，等它入库。没有这样的记录就不再拦着试看。
      for record in matchingHistory where !job.previousDownloadHistoryIDs.contains(record.id) {
        guard let hash = record.download_hash,
          let transfer = try await transferRecord(
            hash: hash, recognizedTitle: record.title, request: request, operation: operation).record,
          transfer.status == true
        else { continue }
        try attach(record, job: &job, key: request.key)
        job.progress = .waitingForLibrary
        return
      }
      job.formalSubscriptionID = nil
      job.previousDownloadHistoryIDs = []
      guard mayCreate else {
        job.progress = Self.formalEnded
        return
      }
    }

    let related = subscriptions.filter { isRelated($0, to: request) }
    if let row = related.first(where: {
      $0.season == request.season && trimmedNonEmpty([$0.episode_group]) == request.episodeGroup
        && $0.identity.map(request.knownIdentities.contains) == true
        && !EpisodeTrialTemporarySubscription.isTrialRow($0)
    }), let id = row.id, id > 0 {
      job.formalSubscriptionID = id
      job.previousDownloadHistoryIDs = Set(history.map(\.id))
      job.progress = row.state == "S" ? .subscriptionPaused : .waitingForSubscription
      return
    }
    if !related.isEmpty {
      job.progress = related.contains(where: EpisodeTrialTemporarySubscription.isTrialRow)
        ? .seasonTrialInProgress : .unavailable("已有相关订阅，无法确认与当前季集使用同一套编号")
      return
    }

    guard library == .notOnServer else {
      job.progress = .unavailable(library?.message ?? "无法确认媒体库是否已有这一集")
      return
    }
    try await submit(&job, request: request, rule: rule, history: history, operation: operation)
  }

  private func isRelated(_ row: Subscribe, to request: EpisodeTrialRequest) -> Bool {
    guard row.type == "电视剧", row.season == nil || row.season == request.season else { return false }
    if let identity = row.identity, request.knownIdentities.contains(identity) { return true }
    let names = [request.media.title, request.media.original_title].compactMap { trimmedNonEmpty([$0]) }
    let sameTitle = names.contains { $0.caseInsensitiveCompare(row.name) == .orderedSame }
    return sameTitle && (row.year == nil || request.media.year == nil || row.year == request.media.year)
  }

  /// 占位订阅仍在，同季既不能再试看，正式订阅也会被后端当作“已存在”。只清理本账号、本季、
  /// 本服务没有在跟踪、且超过确认期的占位；删除失败时留给下一次发起。
  private func removeAbandonedPlaceholders(
    from subscriptions: [Subscribe], request: EpisodeTrialRequest, operation: Operation
  ) async throws -> [Subscribe] {
    guard let owner = operation.api.currentOrStoredUserName, !owner.isEmpty else { return subscriptions }
    let tracked = Set(jobs.values.flatMap { [$0.creationMarker, $0.temporary?.marker].compactMap { $0 } })
    let date = now()
    var remaining = subscriptions
    for row in subscriptions {
      guard let id = row.id, let marker = row.filter, !tracked.contains(marker), isRelated(row, to: request),
        EpisodeTrialTemporarySubscription.isAbandonedPlaceholder(row, owner: owner, now: date)
      else { continue }
      let deleted = (try? await operation.api.deleteSubscription(id: id)) == true
      try operation.check()
      if deleted { remaining.removeAll { $0.id == id } }
    }
    return remaining
  }

  private func submit(
    _ job: inout EpisodeTrialJob, request: EpisodeTrialRequest, rule: EpisodeTrialRule,
    history: [EpisodeTrialHistoryRecord], operation: Operation
  ) async throws {
    guard let owner = operation.api.currentOrStoredUserName, !owner.isEmpty else {
      job.progress = .unavailable("无法确认试看订阅的归属")
      return
    }
    let key = request.key
    let target = request.target
    // 建订阅前先读好，读不到就不建，免得留下一条写不了规则的占位。
    let defaultInclude = rule.include == nil ? try await operation.api.fetchDefaultTvSubscribeInclude() : nil
    try operation.check()
    let startedAt = now()
    let marker = EpisodeTrialTemporarySubscription.makeMarker(at: startedAt)
    job = EpisodeTrialJob()
    job.target = target
    job.previousDownloadHistoryIDs = Set(history.map(\.id))
    job.creationMarker = marker
    job.pendingSince = startedAt
    try save(job, key: key)

    let receipt = try await operation.api.createEpisodeTrialSubscription(
      EpisodeTrialCreateSubscription(request: request, marker: marker))
    try operation.check()
    switch receipt {
    case .reused(let id):
      job.creationMarker = nil
      job.pendingSince = nil
      job.formalSubscriptionID = id
      try save(job, key: key)
      let row = try await operation.api.fetchSubscription(id: id)
      try operation.check()
      if EpisodeTrialTemporarySubscription.isTrialRow(row) {
        job.formalSubscriptionID = nil
        job.progress = .seasonTrialInProgress
      } else {
        job.formalSubscriptionID = id
        job.progress = row.state == "S" ? .subscriptionPaused : .waitingForSubscription
      }
      return
    case .rejected:
      job.creationMarker = nil
      job.pendingSince = nil
      job.progress = .unavailable("MoviePilot 拒绝创建试看订阅")
      return
    case .unconfirmed:
      job.progress = .submissionUnconfirmed
      return
    case .created(let id):
      job.temporary = EpisodeTrialTemporarySubscription(id: id, marker: marker, owner: owner)
      job.creationMarker = nil
      job.pendingSince = nil
      try save(job, key: key)
    }

    guard let temporary = job.temporary else { return }
    let row = try await operation.api.fetchSubscription(id: temporary.id)
    try operation.check()
    guard temporary.matches(row, target: target), row.include == EpisodeTrialTemporarySubscription.blockedInclude,
      row.best_version == 1, row.best_version_full == 0
    else { throw APIError.serverMessage("试看订阅的保护条件未生效") }
    job.temporary?.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(row)]
    try save(job, key: key)

    let paused = try await operation.api.updateSubscriptionStatus(id: temporary.id, state: "S")
    try operation.check()
    guard paused.success else { throw APIError.serverMessage("试看订阅暂停失败") }
    let pausedRow = try await verifiedPausedRow(job, target: target, operation: operation)
    guard pausedRow.total_episode != request.episodeNumber else {
      throw APIError.serverMessage("无法锁定试看总集数")
    }
    var draft = pausedRow
    draft.start_episode = request.episodeNumber
    draft.total_episode = request.episodeNumber
    rule.apply(to: &draft, includeFallback: defaultInclude)
    try await write(draft, from: pausedRow, job: &job, target: target, key: key, operation: operation)

    job.searchPending = true
    job.pendingSince = now()
    job.progress = .searching
    try save(job, key: key)
    let searchReceipt = try await operation.api.searchEpisodeTrialSubscription(id: temporary.id)
    try operation.check()
    switch searchReceipt {
    case .scheduled(let batchID):
      job.batchID = batchID
      job.searchPending = false
      job.pendingSince = nil
      job.searchMayHaveDownloaded = true
    case .rejected:
      job.searchPending = false
      job.pendingSince = nil
      try await reconcileTemporary(&job, target: target, key: key, operation: operation)
      job.progress = .unavailable("MoviePilot 拒绝试看补搜")
    case .unconfirmed:
      job.progress = .submissionUnconfirmed
    }
  }

  private func verifiedPausedRow(
    _ job: EpisodeTrialJob, target: EpisodeTrialTarget, operation: Operation
  ) async throws -> Subscribe {
    guard let temporary = job.temporary else { throw CancellationError() }
    let row = try await operation.api.fetchSubscription(id: temporary.id)
    try operation.check()
    guard temporary.matches(row, target: target), row.state == "S",
      temporary.fingerprints.contains(try EpisodeTrialTemporarySubscription.fingerprint(row))
    else { throw APIError.serverMessage("试看订阅的配置已变化") }
    return row
  }

  /// 写入后按含义核对回读结果，再以回读的样子作为“未被改动”的基准，
  /// 后端对空值或站点顺序的整理不会被当成其他入口的修改。
  private func write(
    _ draft: Subscribe, from row: Subscribe, job: inout EpisodeTrialJob, target: EpisodeTrialTarget,
    key: String, operation: Operation
  ) async throws {
    guard let temporary = job.temporary else { throw CancellationError() }
    job.temporary?.fingerprints.insert(try EpisodeTrialTemporarySubscription.fingerprint(draft))
    job.temporary?.writtenSettings = try EpisodeTrialTemporarySubscription.settingsDigest(draft)
    try save(job, key: key)
    let result = try await operation.api.saveSubscription(original: row, draft: draft)
    try operation.check()
    guard result.success else { throw APIError.serverMessage("保存试看订阅失败") }
    let updated = try await operation.api.fetchSubscription(id: temporary.id)
    try operation.check()
    guard temporary.matches(updated, target: target), updated.state == "S",
      EpisodeTrialTemporarySubscription.preservesSettings(of: draft, in: updated)
    else { throw APIError.serverMessage("试看订阅未保留指定的季集及规则") }
    job.temporary?.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(updated)]
    try save(job, key: key)
  }

  /// 把创建、补搜和批次三个阶段对齐到服务器事实，并在不再需要时删除未被改动的临时订阅。
  /// 发出后没拿到回执的请求在确认期内继续等待，过期仍无受理痕迹则按未受理收尾。
  private func reconcileTemporary(
    _ job: inout EpisodeTrialJob, target: EpisodeTrialTarget, key: String, operation: Operation
  ) async throws {
    // 一次对账里订阅列表只读一次，创建、补搜和收尾三步看的是同一份服务器结果；这期间不改服务器。
    var listed: [Subscribe]?
    func subscriptions() async throws -> [Subscribe] {
      if let listed { return listed }
      let rows = try await operation.api.fetchSubscriptions(forceRefresh: true)
      try operation.check()
      listed = rows
      return rows
    }
    if let marker = job.creationMarker {
      guard let owner = operation.api.currentOrStoredUserName, !owner.isEmpty else {
        if !job.progress.isReady { job.progress = .submissionUnconfirmed }
        return
      }
      guard let row = try await subscriptions().first(where: { $0.filter == marker }), let id = row.id, id > 0
      else {
        if job.isPending(at: now()) {
          if !job.progress.isReady { job.progress = .submissionUnconfirmed }
        } else {
          // 创建请求没有送达。之后才落库的同标记订阅仍拒绝所有资源，由占位清理收尾。
          job.creationMarker = nil
          job.pendingSince = nil
          if !job.progress.isReady { job.progress = Self.restartable }
          try save(job, key: key)
        }
        return
      }
      var recovered = EpisodeTrialTemporarySubscription(id: id, marker: marker, owner: owner)
      guard recovered.matches(row, target: target),
        row.include == EpisodeTrialTemporarySubscription.blockedInclude
      else {
        job.creationMarker = nil
        job.pendingSince = nil
        if !job.progress.isReady { job.progress = Self.editedElsewhere }
        try save(job, key: key)
        return
      }
      recovered.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(row)]
      job.temporary = recovered
      job.creationMarker = nil
      job.pendingSince = nil
      try save(job, key: key)
    }

    guard let temporary = job.temporary else { return }
    if job.searchPending {
      if let row = try await subscriptions().first(where: { temporary.matches($0, target: target) }) {
        if let execution = row.execution_status, execution.source == "manual",
          let batchID = execution.batch_id, EpisodeTrialBatch.isValidID(batchID)
        {
          job.batchID = batchID
          job.searchMayHaveDownloaded = true
        } else if job.isPending(at: now()) {
          if !job.progress.isReady { job.progress = .submissionUnconfirmed }
          return
        }
        // 过期仍没有手动搜索任务：补搜没有送达。新订阅自动搜索会因订阅已暂停而跳过。
      } else {
        // 订阅已消失或不再是本次试看，无法排除补搜已下载，只沿下载历史跟踪。
        job.searchMayHaveDownloaded = true
        job.searchLostSince = now()
        if !job.progress.isReady { job.progress = .submissionUnconfirmed }
      }
      job.searchPending = false
      job.pendingSince = nil
      try save(job, key: key)
    }
    if let batchID = job.batchID, !job.searchFinished {
      let batch = try? await operation.api.fetchEpisodeTrialBatch(id: batchID)
      try operation.check()
      guard let batch, batch.isFinished else { return }
      job.searchFinished = true
      let submitted = batch.download_counts["submitted"]
      if submitted == 0 { job.searchMayHaveDownloaded = false }
      if !job.progress.isReady, job.downloadHash == nil {
        if submitted == 0 {
          job.progress = batch.state == "completed" && batch.finished_count == batch.total_count
            ? .noEligibleResource : .unavailable("MoviePilot 没有完成本次试看搜索，可以重新发起")
        } else {
          job.progress = .submissionUnconfirmed
        }
      }
      try save(job, key: key)
    }
    if let row = try await subscriptions().first(where: { $0.id == temporary.id }) {
      let guarded = row.include == EpisodeTrialTemporarySubscription.blockedInclude
      let unchanged = temporary.fingerprints.contains(try EpisodeTrialTemporarySubscription.fingerprint(row))
      // 写入后没读回来：后端整理过空值或站点顺序，表单指纹对不上，但仍是暂停着的、自己写的样子。
      let ownWrite = row.state == "S"
        && temporary.writtenSettings == (try? EpisodeTrialTemporarySubscription.settingsDigest(row))
      let untouched = temporary.matches(row, target: target)
        && (unchanged || ownWrite || (guarded && temporary.fingerprints.isEmpty)) && (row.state == "S" || guarded)
      guard untouched else {
        job.finishedTemporaryID = temporary.id
        job.temporary = nil
        if !job.progress.isReady { job.progress = Self.editedElsewhere }
        try save(job, key: key)
        return
      }
      let deleted = try await operation.api.deleteSubscription(id: temporary.id)
      try operation.check()
      guard deleted else { throw APIError.serverMessage("试看订阅暂未清理") }
    }
    job.finishedTemporaryID = temporary.id
    job.temporary = nil
    if job.batchID == nil, !job.searchMayHaveDownloaded, !job.progress.isReady {
      job.progress = Self.restartable
    }
    try save(job, key: key)
  }

  // MARK: - 下载与整理

  private struct ActiveDownload {
    let record: EpisodeTrialHistoryRecord
    let downloader: String
    let progress: Double?
  }

  /// 只查询可能持有这些记录的下载器。个别下载器连不上时，只要其他下载器已找到任务就继续；
  /// 都没找到时不能断定没有在下载，交给调用方按“暂时无法确认”处理。
  private func findActiveDownload(
    in history: [EpisodeTrialHistoryRecord], operation: Operation
  ) async throws -> ActiveDownload? {
    guard !history.isEmpty else { return nil }
    let clients = try await operation.api.fetchDownloadClients()
    try operation.check()
    var found: [ActiveDownload] = []
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
          found.append(.init(record: record, downloader: client.name, progress: progress))
        }
      }
    }
    guard let first = found.first else {
      if unreachable { throw APIError.serverMessage("有下载器暂时无法连接，无法确认目标集是否正在下载") }
      return nil
    }
    guard found.allSatisfy({
      $0.record.download_hash != first.record.download_hash || $0.downloader == first.downloader
    }) else { throw APIError.serverMessage("无法确认目标集对应的下载器") }
    return first
  }

  private func attach(
    _ record: EpisodeTrialHistoryRecord, downloader: String? = nil, job: inout EpisodeTrialJob, key: String
  ) throws {
    job.downloadHash = record.download_hash
    job.downloader = downloader ?? record.downloader
    job.historyTitle = trimmedNonEmpty([record.title])
    job.progress = .downloading(progress: nil)
    try save(job, key: key)
  }

  /// 整理历史只能按标题或路径模糊查询。先用 MoviePilot 下载时识别的标题，再用页面标题，
  /// 都查不到时看最新一页，按下载 hash 认定是哪一条。
  /// `complete` 表示每次查询都有答复；有查询失败时没找到不能算确认没有。
  private func transferRecord(
    hash: String, recognizedTitle: String?, request: EpisodeTrialRequest, operation: Operation
  ) async throws -> (record: EpisodeTrialHistoryRecord?, complete: Bool) {
    var titles: [String?] = []
    for title in [recognizedTitle, request.media.title] {
      if let title = trimmedNonEmpty([title]), !titles.contains(title) { titles.append(title) }
    }
    titles.append(nil)
    var complete = true
    for title in titles {
      let history = try? await operation.api.fetchEpisodeTrialTransferHistory(title: title)
      try operation.check()
      if history == nil { complete = false }
      if let record = history?.first(where: { $0.download_hash == hash && $0.matches(request) }) {
        return (record, true)
      }
    }
    return (nil, complete)
  }

  private func trackDownload(
    _ hash: String, job: inout EpisodeTrialJob, request: EpisodeTrialRequest, operation: Operation
  ) async throws {
    let found = try await locateDownload(hash, job: &job, request: request, operation: operation)
    if found != false { job.downloadMissingSince = nil }
    if found == true { return }
    if found == false {
      // 下载器、整理队列和整理历史里都确认没有：多半是在下载器里被删了，或者下完后 MoviePilot 一直没整理。
      // 下完到开始整理之间也会短暂找不到（下载器只列出还在下载的任务），所以要持续一段时间才算结束。
      let since = job.downloadMissingSince ?? now()
      job.downloadMissingSince = since
      if now().timeIntervalSince(since) >= Self.missingDownloadWindow {
        job.downloadHash = nil
        job.downloader = nil
        job.searchMayHaveDownloaded = false
        job.downloadMissingSince = nil
        job.progress = Self.downloadGone
        return
      }
    }
    if case .downloading = job.progress { job.progress = .downloading(progress: nil) }
  }

  /// 找到时更新进度并返回 true；各处都确认没有时返回 false；有查询失败、说不清时返回 nil。
  private func locateDownload(
    _ hash: String, job: inout EpisodeTrialJob, request: EpisodeTrialRequest, operation: Operation
  ) async throws -> Bool? {
    let transfer = try await transferRecord(
      hash: hash, recognizedTitle: job.historyTitle, request: request, operation: operation)
    if let transferred = transfer.record?.status {
      job.progress = transferred ? .waitingForLibrary : .organizationFailed
      return true
    }

    let queue = try? await operation.api.fetchEpisodeTrialTransferQueue()
    try operation.check()
    if let queue {
      let downloaders = transferDownloaders(in: queue, hash: hash)
      if let downloader = job.downloader, downloaders.contains(downloader) {
        job.progress = .organizing
        return true
      }
      if job.downloader == nil, downloaders.count == 1 {
        job.downloader = downloaders.first
        job.progress = .organizing
        return true
      }
    }

    if let downloader = job.downloader {
      let tasks = try await operation.api.fetchDownloading(clientName: downloader)
      try operation.check()
      if let task = tasks.first(where: { $0.hash == hash }) {
        job.progress = .downloading(progress: task.progress.flatMap { $0.isFinite ? $0 : nil })
        return true
      }
    } else {
      guard let history = try? await operation.api.fetchEpisodeTrialDownloadHistory() else {
        try operation.check()
        return nil
      }
      try operation.check()
      if let active = try await findActiveDownload(
        in: history.filter { $0.download_hash == hash && $0.matches(request) }, operation: operation)
      {
        job.downloader = active.downloader
        job.progress = .downloading(progress: active.progress)
        return true
      }
    }
    // 有整理记录但没写结果，也不算找不到。
    return queue == nil || !transfer.complete || transfer.record != nil ? nil : false
  }

  private func transferDownloaders(in queue: [EpisodeTrialTransferJob], hash: String) -> Set<String> {
    Set(queue.flatMap { $0.tasks ?? [] }.filter { $0.download_hash == hash }.compactMap(\.downloader))
  }
}
