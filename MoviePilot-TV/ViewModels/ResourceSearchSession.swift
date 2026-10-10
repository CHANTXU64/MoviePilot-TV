import Combine
import Foundation

struct ResourceSearchRow: Identifiable {
  let id: String
  var context: Context
  let isCandidate: Bool
  var estimatedBytes = 0

  func downloadMedia(override: MediaInfo?) -> MediaInfo? {
    // 未匹配的预览由卡片禁止绑定媒体；最终结果也必须先有后端识别出的媒体，
    // 才允许详情页覆盖季号等信息。标题搜索或缺少识别信息的结果不借用搜索目标。
    isCandidate || context.media_info == nil ? context.media_info : override ?? context.media_info
  }
}

/// 两个搜索入口共用同一 owner；浏览投影、规则和来源进度跨收集阶段保留。
@MainActor
final class ResourceSearchSession: ObservableObject {
  private enum CollectionPhase { case searching, processing }
  @Published private var collectionPhase: CollectionPhase?
  @Published private(set) var isPreparing = false
  @Published private(set) var rows: [ResourceSearchRow] = []
  @Published private(set) var retainedCount = 0
  @Published private(set) var newCount = 0
  @Published private(set) var progressText = "正在搜索…"
  @Published private(set) var progress = 0.0
  @Published private(set) var ruleNotice: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var reachedCapacity = false
  @Published private(set) var rulePending = false
  @Published private(set) var rulesBypassed = false
  @Published private(set) var canReapplyRules = false
  @Published private(set) var initialComplete = false
  @Published private(set) var filterOptions: [String: [String]] = [:]
  @Published private(set) var hardAllowedCount = 0
  @Published var filterForm: [String: Set<String>] = [:]
  @Published var sortField: SortField = .default
  @Published var sortType: SortType = .default

  let query: ResourceSearchQuery
  let processor = ResourceSearchProcessor()
  let capacityBytes: Int
  let maximumEventBytes: Int
  private let apiService: APIService
  private let session: APIServiceSessionSnapshot
  private var ruleTask: Task<Void, Never>?
  private var networkTask: Task<Void, Never>?
  private var projectionTask: Task<Void, Never>?
  private var sessionSubscription: AnyCancellable?
  private var started = false
  private var collectionStartCount = 0
  private var publishedPages: [String: Int] = [:]
  private var detachedPublishedCost = 0

  private struct StoredPage {
    let ordinal: Int
    var rows: [ResourceSearchRow] = []
    var cost = 0
  }
  private struct Cursor {
    var page: Int
    var name: String
    var failed: Bool
  }
  private final class Run {}
  private final class PageAttempt {
    let key: String
    let hadSnapshot: Bool
    var transaction: ResourceSearchPage
    var finalCost = 0
    init(key: String, hadSnapshot: Bool, source: String?, page: Int) {
      self.key = key; self.hadSnapshot = hadSnapshot
      transaction = ResourceSearchPage(source: source, page: page)
    }
  }
  private struct PageFinished: Error {}
  private var run: Run?
  private var pages: [String: StoredPage] = [:]
  private var pageOrder: [String] = []
  private var cursors: [String: Cursor] = [:]
  private var queue: [String] = []

  init(query: ResourceSearchQuery, apiService: APIService, capacityBytes: Int? = nil) {
    self.query = query
    self.apiService = apiService
    self.session = apiService.sessionSnapshot()
    // 以字节预算限制整次收集，另留系统和 UI 余量；不按某个资源条数假定对象大小。
    self.capacityBytes = capacityBytes ?? min(64 * 1024 * 1024, Int(ProcessInfo.processInfo.physicalMemory / 32))
    self.maximumEventBytes = min(2 * 1024 * 1024, self.capacityBytes / 32)
    // UI 作用域按账号和权限复用；同账号刷新令牌也会更换请求 epoch，需收尾旧搜索。
    sessionSubscription = apiService.$session.map(\.epoch).removeDuplicates().sink { [weak self] epoch in
      guard let self, epoch != self.session.epoch else { return }
      self.cancel()
      self.rulePending = false
      self.canReapplyRules = false
      self.errorMessage = "登录状态已更新，请返回后重新搜索。"
    }
  }

  deinit {
    networkTask?.cancel(); ruleTask?.cancel(); projectionTask?.cancel()
  }

  var isCollecting: Bool { collectionPhase != nil }
  var isSearching: Bool { collectionPhase == .searching }
  var canStopAndView: Bool { isSearching && (initialComplete || retainedCount > 0) }
  var isBusy: Bool { isCollecting || isPreparing }
  var canContinue: Bool { isSessionValid && !isBusy && !reachedCapacity && initialComplete && !queue.isEmpty }
  var canRestart: Bool { isSessionValid && !isBusy && !initialComplete && !reachedCapacity }
  var continueTitle: String {
    queue.allSatisfy { cursors[$0]?.failed == true } ? "重试搜索" : "继续搜索"
  }
  var resultErrorMessage: String? {
    reachedCapacity ? ResourceSearchFailure.capacity.localizedDescription : errorMessage
  }
  var emptyDescription: String {
    if let resultErrorMessage { return resultErrorMessage }
    if retainedCount == 0 { return "本次尚未找到资源。" }
    if hardAllowedCount == 0 { return "已收到的资源均被 TV 过滤规则排除。" }
    return "没有符合当前筛选条件的资源，可以清除筛选。"
  }
  private var isSessionValid: Bool {
    apiService.isSessionUnchanged(from: session) && apiService.canAccess(.search)
  }
  private func isCurrent(_ candidate: Run) -> Bool { run === candidate && isSessionValid && !Task.isCancelled }
  private var settings: ResourceProjectionSettings {
    .init(filters: filterForm, sortField: sortField.rawValue, sortType: sortType.rawValue)
  }

  func start() {
    guard !started, isSessionValid else { return }
    started = true
    prepareRules()
    collect(initial: true)
  }

  func continueSearch() {
    guard canContinue else { return }
    collect(initial: false)
  }

  func restart() {
    guard canRestart, isSessionValid else { return }
    // 旧展示快照保留到新结果发布；原页与新首轮不拼接。
    detachedPublishedCost += publishedPages.values.reduce(0, +)
    publishedPages = [:]
    pages = [:]; pageOrder = []; cursors = [:]; queue = []
    retainedCount = 0
    initialComplete = false
    rulesBypassed = false
    ruleNotice = nil
    prepareRules()
    collect(initial: true, resetProcessor: true)
  }

  func stop() {
    guard isSearching else { return }
    stopCollection()
  }

  private func stopCollection() {
    guard isCollecting else { return }
    networkTask?.cancel()
    networkTask = nil
    run = nil
    collectionPhase = nil
    publishSnapshot(refreshTime: true)
  }

  /// 离页只停止本次收集；保留的页面再次出现不自动恢复网络搜索。
  func deactivate() {
    stopCollection()
  }

  func cancel() {
    run = nil
    networkTask?.cancel(); ruleTask?.cancel(); projectionTask?.cancel()
    networkTask = nil; ruleTask = nil; projectionTask = nil
    collectionPhase = nil; isPreparing = false
  }

  private func prepareRules() {
    ruleTask?.cancel()
    let hardID = SystemViewModel.currentSelectedHardFilterRuleId(apiService: apiService)
    let softID = SystemViewModel.currentSelectedSoftFilterRuleId(apiService: apiService)
    let shouldFetch = apiService.canRequestSuperUserEndpoints && (hardID != nil || softID != nil)
    refreshRuleAvailability()
    rulePending = true
    let api = apiService
    ruleTask = Task { [weak self] in
      do {
        let rules = shouldFetch ? try await api.fetchCustomFilterRules() : []
        guard let self, !Task.isCancelled, self.isSessionValid, self.rulePending else { return }
        let selection = ResourceRuleSelection(
          hard: shouldFetch ? hardID.map { id in ResourceRule(rules.first { $0.id == id }) } : nil,
          soft: shouldFetch ? softID.map { id in ResourceRule(rules.first { $0.id == id }) } : nil)
        await self.processor.configure(selection)
        guard !Task.isCancelled, self.isSessionValid, self.rulePending else { return }
        self.rulePending = false
        self.ruleNotice = nil
        if !self.isCollecting { self.publishSnapshot(refreshTime: true) }
      } catch {
        guard let self, !Task.isCancelled, self.isSessionValid, self.rulePending,
          !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        await self.processor.configure(.none)
        guard !Task.isCancelled, self.isSessionValid, self.rulePending else { return }
        self.rulePending = false
        self.rulesBypassed = true
        self.ruleNotice = "TV 过滤规则加载失败，本次搜索不应用 TV 过滤。"
        if !self.isCollecting { self.publishSnapshot(refreshTime: true) }
      }
    }
  }

  func bypassPendingRules() {
    guard rulePending, !isCollecting else { return }
    ruleTask?.cancel(); rulePending = false; rulesBypassed = true
    ruleNotice = "本次搜索不应用 TV 过滤。"
    projectionTask?.cancel()
    projectionTask = Task { [weak self] in
      guard let self else { return }
      await self.processor.configure(.none)
      guard !Task.isCancelled, self.isSessionValid else { return }
      self.publishSnapshot(refreshTime: true)
    }
  }

  func refreshRuleAvailability() {
    guard isSessionValid else { return }
    canReapplyRules = canReapplyRules || rulesBypassed
      || SystemViewModel.currentSelectedHardFilterRuleId(apiService: apiService) != nil
      || SystemViewModel.currentSelectedSoftFilterRuleId(apiService: apiService) != nil
  }

  func reapplyRules() {
    guard !isBusy, isSessionValid else { return }
    projectionTask?.cancel()
    rulesBypassed = false
    errorMessage = nil
    isPreparing = true
    prepareRules()
    if !rulePending { publishSnapshot(refreshTime: true) }
  }

  private func collect(initial: Bool, resetProcessor: Bool = false) {
    guard isSessionValid, !isBusy, !reachedCapacity else { return }
    projectionTask?.cancel()
    let current = Run()
    run = current
    collectionPhase = .searching
    errorMessage = nil
    collectionStartCount = retainedCount
    newCount = 0; progress = 0; progressText = "正在搜索…"
    let api = apiService, query = query, frameLimit = maximumEventBytes
    let processor = processor
    networkTask = Task { [weak self] in
      if resetProcessor { await processor.reset() }
      if self?.isCurrent(current) == true,
        let attempt = self?.nextAttempt(initial: initial)
      {
        do {
          try await api.readResourceSearchPage(
            query: query, source: attempt.transaction.source, page: attempt.transaction.page,
            maximumEventBytes: frameLimit
          ) { [weak self] event, bytes in
            guard let self, self.isCurrent(current) else { throw CancellationError() }
            try await self.receive(event, bytes: bytes, attempt: attempt)
            if attempt.transaction.isComplete { throw PageFinished() }
          }
          if !attempt.transaction.isComplete { throw ResourceSearchFailure.incompletePage }
        } catch is PageFinished {
          // 完整结果和页事实已一起提交，可以关闭该连接。
        } catch {
          guard self?.isCurrent(current) == true else { return }
          self?.fail(error, attempt: attempt)
        }
      }
      guard let self, self.isCurrent(current) else { return }
      self.run = nil; self.networkTask = nil; self.collectionPhase = nil
      self.publishSnapshot(refreshTime: true)
    }
  }

  private func nextAttempt(initial: Bool) -> PageAttempt? {
    let source: String?, page: Int, key: String
    if initial { source = nil; page = 0; key = "initial" }
    else {
      guard let next = queue.first, let cursor = cursors[next] else { return nil }
      source = next; page = cursor.page; key = "\(next):\(page)"
      // 请求一开始就移到队尾；中断后仍然保持轮转位置。
      queue.removeAll { $0 == next }; queue.append(next)
      progressText = "正在搜索 \(cursor.name) 第 \(page + 1) 页…"
    }
    return PageAttempt(key: key, hadSnapshot: pages[key]?.rows.isEmpty == false, source: source, page: page)
  }

  private func receive(_ event: SearchStreamEvent, bytes: Int, attempt: PageAttempt) async throws {
    if let text = event.text_i18n ?? event.text { progressText = text }
    if let value = event.value { progress = value }
    switch event.stage {
    case "searching": collectionPhase = .searching
    case "filtering", "filtered", "done": collectionPhase = .processing
    default: break
    }
    let isFinal = event.type == "replace" || event.replace_batch == true
    let keepsPreview = event.type == "append" && event.replace_batch != true && !attempt.hadSnapshot
    if isFinal {
      collectionPhase = .processing
    }
    let items = event.items ?? []
    if isFinal || (keepsPreview && !items.isEmpty) {
      let cost = max(bytes * 8, items.count * 4096)
      let retained = pages.values.reduce(0) { $0 + $1.cost }
      // 原页（含预览）只计一次；8 倍字节估算含 Context、投影数组和过滤派生值。
      // 另计已脱离原页的旧展示和待提交最终包。逐事件等待消费，只留一帧解码余量，
      // 不保留的重试预览也由这份余量覆盖，不再算作新增保留数据。
      guard retained + detachedPublishedCost + attempt.finalCost + cost + maximumEventBytes * 8 <= capacityBytes else {
        throw ResourceSearchFailure.capacity
      }
      if isFinal { attempt.finalCost += cost }
    }
    try attempt.transaction.receive(event)
    if attempt.transaction.isComplete {
      progressText = "正在整理结果…"
      let facts = attempt.transaction.sources ?? []
      let final = attempt.transaction.finalItems
      // 主线程提交事实和原始页，不在两个 await 之间暴露半个事务。
      let inputs = store(final, key: attempt.key, replacing: true, candidate: false, cost: attempt.finalCost)
      if attempt.transaction.source == nil {
        initialComplete = true
        cursors = [:]; queue = []
        for fact in facts where fact.can_continue {
          cursors[fact.source] = Cursor(page: fact.error == nil ? fact.page + 1 : fact.page,
            name: fact.site_name ?? "搜索来源", failed: fact.error != nil)
          queue.append(fact.source)
        }
        if facts.contains(where: { $0.error != nil }) { errorMessage = "部分搜索来源失败，已保留成功结果。" }
      } else if let fact = facts.first {
        if fact.can_continue {
          cursors[fact.source] = Cursor(page: fact.page + 1, name: fact.site_name ?? "搜索来源", failed: false)
        } else { cursors[fact.source] = nil; queue.removeAll { $0 == fact.source } }
      }
      try await processor.ingest(key: attempt.key, inputs: inputs, replacing: true, now: Date())
    } else if keepsPreview, !items.isEmpty {
      let inputs = store(items, key: attempt.key, replacing: false,
        candidate: query.isMediaSearch, cost: max(bytes * 8, items.count * 4096))
      try await processor.ingest(key: attempt.key, inputs: inputs, replacing: false, now: Date())
    }
  }

  private func store(_ items: [Context], key: String, replacing: Bool, candidate: Bool, cost: Int) -> [ResourceFilterInput] {
    if pages[key] == nil { pages[key] = StoredPage(ordinal: pageOrder.count); pageOrder.append(key) }
    var page = pages.removeValue(forKey: key)!
    if replacing {
      detachedPublishedCost += publishedPages.removeValue(forKey: key) ?? 0
      page.rows = []; page.cost = 0
    }
    let offset = page.rows.count
    let inputs = items.enumerated().map { i, context in
      let id = "\(page.ordinal):\(offset + i)"
      // 按本批次分摊估算，保留筛选后仍被展示引用的成本，不重新编码 Context。
      let rowCost = cost / items.count + (i < cost % items.count ? 1 : 0)
      page.rows.append(ResourceSearchRow(id: id, context: context, isCandidate: candidate, estimatedBytes: rowCost))
      return ResourceFilterInput(context: context, id: id, order: page.ordinal * 1_000_000 + offset + i)
    }
    page.cost += cost
    pages[key] = page
    retainedCount = pages.values.reduce(0) { $0 + $1.rows.count }
    newCount = max(0, retainedCount - collectionStartCount)
    return inputs
  }

  private func fail(_ error: Error, attempt: PageAttempt) {
    if case ResourceSearchFailure.capacity = error {
      reachedCapacity = true
    } else {
      errorMessage = error.localizedDescription
    }
    if let source = attempt.transaction.source {
      cursors[source]?.failed = true
    }
  }

  func updateProjection() { publishSnapshot(refreshTime: false) }

  private func publishSnapshot(refreshTime: Bool) {
    guard !isCollecting, isSessionValid else { return }
    isPreparing = refreshTime
    if rulePending {
      isPreparing = true
      progressText = "搜索已停止，所选 TV 过滤规则尚未就绪，已保留 \(retainedCount) 条"
      return
    }
    progressText = "正在整理结果…"
    projectionTask?.cancel()
    let settings = settings
    let evaluationTime = refreshTime ? Date() : nil
    projectionTask = Task { [weak self] in
      guard let self else { return }
      do {
        let projection = try await self.processor.project(settings: settings, evaluationTime: evaluationTime)
        guard !Task.isCancelled, self.isSessionValid, !self.isCollecting else { return }
        let originals = Dictionary(uniqueKeysWithValues: self.pageOrder.flatMap { self.pages[$0]?.rows ?? [] }.map { ($0.id, $0) })
        self.rows = projection.rows.compactMap { projected in
          guard var row = originals[projected.id] else { return nil }
          row.context.isFilteredOut = projected.softRejected
          return row
        }
        self.filterOptions = ResourceResultSemantics.sortedOptions(projection.options)
        self.hardAllowedCount = projection.hardAllowedCount
        let visibleIDs = Set(self.rows.map(\.id))
        self.publishedPages = self.pages.mapValues { page in
          page.rows.reduce(0) { $0 + (visibleIDs.contains($1.id) ? $1.estimatedBytes : 0) }
        }
        self.detachedPublishedCost = 0
        self.isPreparing = false
      } catch {
        guard !Task.isCancelled, self.isSessionValid else { return }
        self.errorMessage = error.localizedDescription
        if error is CustomFilterService.FilterError {
          self.rows = []; self.publishedPages = [:]; self.detachedPublishedCost = 0
        }
        self.isPreparing = false
      }
    }
  }

  func disabledOptions(for key: String) async -> Set<String> {
    await processor.disabledOptions(for: key, filters: filterForm)
  }
}
