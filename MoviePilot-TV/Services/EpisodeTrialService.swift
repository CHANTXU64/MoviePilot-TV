import Combine
import Foundation

/// 试看任务与订阅行分开保存。MoviePilot 可以在接收下载后立即完成并删除订阅。
@MainActor
final class EpisodeTrialService: ObservableObject {
  nonisolated deinit {}

  typealias Availability = @MainActor (EpisodeTrialRequest) async -> EpisodeAvailability?

  private static let interrupted = EpisodeTrialProgress.unavailable("本次试看查询已中断")
  private static let restartable = EpisodeTrialProgress.unavailable("上次试看准备未完成，可以重新发起")
  private static let editedElsewhere = EpisodeTrialProgress.unavailable("试看订阅已由其他入口修改")

  @Published private(set) var progress: [String: EpisodeTrialProgress] = [:]
  private weak var api: APIService?
  private let defaults: UserDefaults
  private let storageKey: String?
  private let availability: Availability
  private let now: @MainActor () -> Date
  private var jobs: [String: EpisodeTrialJob] = [:]
  private var seasonRuns: [String: SeasonRun] = [:]
  private var monitors: [String: Task<Void, Never>] = [:]
  private var isTornDown = false

  /// 后端按季去重订阅，同一季同时只能有一条试看订阅，所以同季的推进依次执行。
  /// 推进由服务持有：页面离开不会把创建、暂停、写规则和补搜截断在中间，会话拆除时统一取消。
  private struct SeasonRun {
    let key: String
    let mayCreate: Bool
    let task: Task<EpisodeTrialProgress, Never>
  }

  init(
    api: APIService, defaults: UserDefaults = .standard,
    now: @escaping @MainActor () -> Date = { Date() },
    availability: @escaping Availability
  ) {
    self.api = api
    self.defaults = defaults
    self.now = now
    storageKey = api.profileKey.map { "episodeTrial.v1.\($0)" }
    if let storageKey, let data = defaults.data(forKey: storageKey + ".jobs"),
      let saved = try? JSONDecoder().decode([String: EpisodeTrialJob].self, from: data)
    {
      jobs = saved
      progress = saved.mapValues(\.progress)
    }
    self.availability = availability
  }

  var rule: EpisodeTrialRule? {
    guard let storageKey, let data = defaults.data(forKey: storageKey + ".rule") else { return nil }
    return try? JSONDecoder().decode(EpisodeTrialRule.self, from: data)
  }

  func saveRule(_ rule: EpisodeTrialRule?) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    let data = try rule.map { try JSONEncoder().encode($0) }
    defaults.set(data, forKey: storageKey + ".rule")
  }

  func start(_ request: EpisodeTrialRequest) async -> EpisodeTrialProgress {
    await advance(request, mayCreate: true)
  }

  func refresh(_ request: EpisodeTrialRequest) async -> EpisodeTrialProgress {
    await advance(request, mayCreate: false)
  }

  func tearDown() {
    isTornDown = true
    for run in seasonRuns.values { run.task.cancel() }
    seasonRuns.removeAll()
    for monitor in monitors.values { monitor.cancel() }
    monitors.removeAll()
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

  private func save(_ job: EpisodeTrialJob, for request: EpisodeTrialRequest) throws {
    guard !isTornDown, let storageKey else { throw CancellationError() }
    jobs[request.key] = job
    let recoverable = jobs.filter { $0.value.isTracking }
    defaults.set(try JSONEncoder().encode(recoverable), forKey: storageKey + ".jobs")
    progress[request.key] = job.progress
  }

  /// 同一集正在推进且覆盖本次意图时直接等它的结果；否则排在同季上一次推进之后。
  private func advance(_ request: EpisodeTrialRequest, mayCreate: Bool) async -> EpisodeTrialProgress {
    guard !isTornDown else { return Self.interrupted }
    let seasonKey = request.seasonKey
    if let current = seasonRuns[seasonKey], current.key == request.key, current.mayCreate || !mayCreate {
      return await current.task.value
    }
    let previous = seasonRuns[seasonKey]?.task
    let task = Task { [weak self] () -> EpisodeTrialProgress in
      _ = await previous?.value
      guard let self else { return EpisodeTrialService.interrupted }
      return await self.run(request, mayCreate: mayCreate)
    }
    seasonRuns[seasonKey] = SeasonRun(key: request.key, mayCreate: mayCreate, task: task)
    let result = await task.value
    if seasonRuns[seasonKey]?.task == task { seasonRuns.removeValue(forKey: seasonKey) }
    return result
  }

  private func run(_ request: EpisodeTrialRequest, mayCreate: Bool) async -> EpisodeTrialProgress {
    guard !isTornDown, !Task.isCancelled else { return Self.interrupted }
    guard let api, storageKey != nil, api.canRequestSuperUserEndpoints,
      InAppPlaybackAvailability.supports(backendVersion: api.settings?.BACKEND_VERSION)
    else { return .unavailable("试看需要 MoviePilot v3.2.6 或更高版本和管理员账号") }
    defer { monitorTemporarySubscription(for: request) }

    var job = jobs[request.key] ?? EpisodeTrialJob()
    if mayCreate, job.canRestart {
      job = EpisodeTrialJob()
    }
    let operation = Operation(api: api, session: api.sessionSnapshot())
    do {
      try await update(&job, for: request, mayCreate: mayCreate, operation: operation)
      try operation.check()
      try save(job, for: request)
    } catch is CancellationError {
      return Self.interrupted
    } catch {
      guard (try? operation.check()) != nil else { return Self.interrupted }
      if !job.progress.isReady {
        job.progress = job.creationMarker != nil || job.searchPending
          ? .submissionUnconfirmed : .unavailable("暂时无法确认试看进度")
      }
      try? save(job, for: request)
    }
    return job.progress
  }

  /// 在 TV 还处于活动状态时主动释放临时订阅身份。App 重新启动后可用同一请求恢复。
  private func monitorTemporarySubscription(for request: EpisodeTrialRequest) {
    guard !isTornDown, monitors[request.key] == nil,
      let job = jobs[request.key], job.temporary != nil || job.creationMarker != nil
    else { return }
    monitors[request.key] = Task { [weak self] in
      for attempt in 0..<60 {
        do {
          try await Task.sleep(for: .seconds(attempt == 0 ? 5 : 20))
        } catch { break }
        guard let self, let job = self.jobs[request.key],
          job.temporary != nil || job.creationMarker != nil
        else { break }
        _ = await self.refresh(request)
      }
      self?.monitors.removeValue(forKey: request.key)
    }
  }

  private func update(
    _ job: inout EpisodeTrialJob, for request: EpisodeTrialRequest, mayCreate: Bool, operation: Operation
  ) async throws {
    let library = await availability(request)
    try operation.check()
    if case .playable(let server) = library {
      job.progress = .ready(server: server)
    }

    if job.creationMarker != nil || job.temporary != nil {
      try await reconcileTemporary(&job, request: request, operation: operation)
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
        try attach(record, job: &job, request: request)
        try await trackDownload(hash, job: &job, request: request, operation: operation)
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
      try attach(active.record, downloader: active.downloader, job: &job, request: request)
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
          try attach(record, downloader: downloader, job: &job, request: request)
          job.progress = .organizing
          return
        }
      }
    }

    if let id = job.formalSubscriptionID {
      if let record = matchingHistory.first(where: {
        $0.note?.subscription_download?.subscription_id == id && !job.previousDownloadHistoryIDs.contains($0.id)
      }), let hash = record.download_hash {
        try attach(record, job: &job, request: request)
        try await trackDownload(hash, job: &job, request: request, operation: operation)
        return
      }
      guard let formal = subscriptions.first(where: { $0.id == id }) else {
        job.progress = .unavailable("原订阅已结束或已移除，等待媒体库更新")
        return
      }
      job.progress = formal.state == "S" ? .subscriptionPaused : .waitingForSubscription
      return
    }

    let related = subscriptions.filter { isRelated($0, to: request) }
    if let row = related.first(where: {
      $0.season == request.season && trimmedNonEmpty([$0.episode_group]) == request.episodeGroup
        && $0.identity.map(request.knownIdentities.contains) == true
        && $0.filter?.hasPrefix(EpisodeTrialTemporarySubscription.markerPrefix) != true
    }), let id = row.id, id > 0 {
      job.formalSubscriptionID = id
      job.previousDownloadHistoryIDs = Set(history.map(\.id))
      job.progress = row.state == "S" ? .subscriptionPaused : .waitingForSubscription
      return
    }
    if !related.isEmpty {
      job.progress = related.contains { $0.filter?.hasPrefix(EpisodeTrialTemporarySubscription.markerPrefix) == true }
        ? .seasonTrialInProgress : .unavailable("已有相关订阅，无法确认与当前季集使用同一套编号")
      return
    }

    guard library == .notOnServer else {
      job.progress = .unavailable(library?.message ?? "无法确认媒体库是否已有这一集")
      return
    }
    guard let rule else {
      job.progress = .unavailable("请先保存试看订阅规则")
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
    let startedAt = now()
    let marker = EpisodeTrialTemporarySubscription.makeMarker(at: startedAt)
    job = EpisodeTrialJob()
    job.previousDownloadHistoryIDs = Set(history.map(\.id))
    job.creationMarker = marker
    job.pendingSince = startedAt
    try save(job, for: request)

    let receipt = try await operation.api.createEpisodeTrialSubscription(
      EpisodeTrialCreateSubscription(request: request, marker: marker))
    try operation.check()
    switch receipt {
    case .reused(let id):
      job.creationMarker = nil
      job.pendingSince = nil
      job.formalSubscriptionID = id
      try save(job, for: request)
      let row = try await operation.api.fetchSubscription(id: id)
      try operation.check()
      if row.filter?.hasPrefix(EpisodeTrialTemporarySubscription.markerPrefix) == true {
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
      try save(job, for: request)
    }

    guard let temporary = job.temporary else { return }
    let row = try await operation.api.fetchSubscription(id: temporary.id)
    try operation.check()
    guard temporary.matches(row, request: request), row.include == EpisodeTrialTemporarySubscription.blockedInclude,
      row.best_version == 1, row.best_version_full == 0
    else { throw APIError.serverMessage("试看订阅的保护条件未生效") }
    job.temporary?.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(row)]
    try save(job, for: request)

    let paused = try await operation.api.updateSubscriptionStatus(id: temporary.id, state: "S")
    try operation.check()
    guard paused.success else { throw APIError.serverMessage("试看订阅暂停失败") }
    let pausedRow = try await verifiedPausedRow(job, request: request, operation: operation)
    guard pausedRow.total_episode != request.episodeNumber else {
      throw APIError.serverMessage("无法锁定试看总集数")
    }
    var draft = pausedRow
    draft.start_episode = request.episodeNumber
    draft.total_episode = request.episodeNumber
    rule.apply(to: &draft)
    try await write(draft, from: pausedRow, job: &job, request: request, operation: operation)

    job.searchPending = true
    job.pendingSince = now()
    job.progress = .searching
    try save(job, for: request)
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
      try await reconcileTemporary(&job, request: request, operation: operation)
      job.progress = .unavailable("MoviePilot 拒绝试看补搜")
    case .unconfirmed:
      job.progress = .submissionUnconfirmed
    }
  }

  private func verifiedPausedRow(
    _ job: EpisodeTrialJob, request: EpisodeTrialRequest, operation: Operation
  ) async throws -> Subscribe {
    guard let temporary = job.temporary else { throw CancellationError() }
    let row = try await operation.api.fetchSubscription(id: temporary.id)
    try operation.check()
    guard temporary.matches(row, request: request), row.state == "S",
      temporary.fingerprints.contains(try EpisodeTrialTemporarySubscription.fingerprint(row))
    else { throw APIError.serverMessage("试看订阅的配置已变化") }
    return row
  }

  private func write(
    _ draft: Subscribe, from row: Subscribe, job: inout EpisodeTrialJob, request: EpisodeTrialRequest,
    operation: Operation
  ) async throws {
    let fingerprint = try EpisodeTrialTemporarySubscription.fingerprint(draft)
    job.temporary?.fingerprints.insert(fingerprint)
    try save(job, for: request)
    let result = try await operation.api.saveSubscription(original: row, draft: draft)
    try operation.check()
    guard result.success else { throw APIError.serverMessage("保存试看订阅失败") }
    let updated = try await verifiedPausedRow(job, request: request, operation: operation)
    guard try EpisodeTrialTemporarySubscription.fingerprint(updated) == fingerprint else {
      throw APIError.serverMessage("试看订阅未保留指定的季集及规则")
    }
    job.temporary?.fingerprints = [fingerprint]
    try save(job, for: request)
  }

  /// 把创建、补搜和批次三个阶段对齐到服务器事实，并在不再需要时删除未被改动的临时订阅。
  /// 发出后没拿到回执的请求在确认期内继续等待，过期仍无受理痕迹则按未受理收尾。
  private func reconcileTemporary(
    _ job: inout EpisodeTrialJob, request: EpisodeTrialRequest, operation: Operation
  ) async throws {
    if let marker = job.creationMarker {
      guard let owner = operation.api.currentOrStoredUserName, !owner.isEmpty else {
        if !job.progress.isReady { job.progress = .submissionUnconfirmed }
        return
      }
      let subscriptions = try await operation.api.fetchSubscriptions(forceRefresh: true)
      try operation.check()
      guard let row = subscriptions.first(where: { $0.filter == marker }), let id = row.id, id > 0 else {
        if job.isPending(at: now()) {
          if !job.progress.isReady { job.progress = .submissionUnconfirmed }
        } else {
          // 创建请求没有送达。之后才落库的同标记订阅仍拒绝所有资源，由占位清理收尾。
          job.creationMarker = nil
          job.pendingSince = nil
          if !job.progress.isReady { job.progress = Self.restartable }
          try save(job, for: request)
        }
        return
      }
      var recovered = EpisodeTrialTemporarySubscription(id: id, marker: marker, owner: owner)
      guard recovered.matches(row, request: request),
        row.include == EpisodeTrialTemporarySubscription.blockedInclude
      else {
        job.creationMarker = nil
        job.pendingSince = nil
        if !job.progress.isReady { job.progress = Self.editedElsewhere }
        try save(job, for: request)
        return
      }
      recovered.fingerprints = [try EpisodeTrialTemporarySubscription.fingerprint(row)]
      job.temporary = recovered
      job.creationMarker = nil
      job.pendingSince = nil
      try save(job, for: request)
    }

    guard let temporary = job.temporary else { return }
    if job.searchPending {
      let subscriptions = try await operation.api.fetchSubscriptions(forceRefresh: true)
      try operation.check()
      if let row = subscriptions.first(where: { temporary.matches($0, request: request) }) {
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
        if !job.progress.isReady { job.progress = .submissionUnconfirmed }
      }
      job.searchPending = false
      job.pendingSince = nil
      try save(job, for: request)
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
      try save(job, for: request)
    }
    let subscriptions = try await operation.api.fetchSubscriptions(forceRefresh: true)
    try operation.check()
    if let row = subscriptions.first(where: { $0.id == temporary.id }) {
      let guarded = row.include == EpisodeTrialTemporarySubscription.blockedInclude
      let unchanged = temporary.fingerprints.contains(try EpisodeTrialTemporarySubscription.fingerprint(row))
      let untouched = temporary.matches(row, request: request)
        && (unchanged || (guarded && temporary.fingerprints.isEmpty)) && (row.state == "S" || guarded)
      guard untouched else {
        job.finishedTemporaryID = temporary.id
        job.temporary = nil
        if !job.progress.isReady { job.progress = Self.editedElsewhere }
        try save(job, for: request)
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
    try save(job, for: request)
  }

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
    _ record: EpisodeTrialHistoryRecord, downloader: String? = nil, job: inout EpisodeTrialJob,
    request: EpisodeTrialRequest
  ) throws {
    job.downloadHash = record.download_hash
    job.downloader = downloader ?? record.downloader
    job.progress = .downloading(progress: nil)
    try save(job, for: request)
  }

  private func trackDownload(
    _ hash: String, job: inout EpisodeTrialJob, request: EpisodeTrialRequest, operation: Operation
  ) async throws {
    let history = try? await operation.api.fetchEpisodeTrialTransferHistory(title: request.media.title)
    try operation.check()
    if let record = history?.first(where: { $0.download_hash == hash && $0.matches(request) }),
      let transferred = record.status
    {
      job.progress = transferred ? .waitingForLibrary : .organizationFailed
      return
    }

    if let queue = try? await operation.api.fetchEpisodeTrialTransferQueue() {
      try operation.check()
      let downloaders = transferDownloaders(in: queue, hash: hash)
      if let downloader = job.downloader, downloaders.contains(downloader) {
        job.progress = .organizing
        return
      }
      if job.downloader == nil, downloaders.count == 1 {
        job.downloader = downloaders.first
        job.progress = .organizing
        return
      }
    }
    try operation.check()

    if let downloader = job.downloader {
      let tasks = try await operation.api.fetchDownloading(clientName: downloader)
      try operation.check()
      if let task = tasks.first(where: { $0.hash == hash }) {
        job.progress = .downloading(progress: task.progress.flatMap { $0.isFinite ? $0 : nil })
        return
      }
    } else if let history = try? await operation.api.fetchEpisodeTrialDownloadHistory() {
      try operation.check()
      if let active = try await findActiveDownload(
        in: history.filter { $0.download_hash == hash && $0.matches(request) }, operation: operation)
      {
        job.downloader = active.downloader
        job.progress = .downloading(progress: active.progress)
        return
      }
    }
    try operation.check()
    if case .downloading = job.progress { job.progress = .downloading(progress: nil) }
  }

  private func transferDownloaders(in queue: [EpisodeTrialTransferJob], hash: String) -> Set<String> {
    Set(queue.flatMap { $0.tasks ?? [] }.filter { $0.download_hash == hash }.compactMap(\.downloader))
  }
}
