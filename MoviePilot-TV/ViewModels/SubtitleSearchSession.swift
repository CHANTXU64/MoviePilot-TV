import Combine
import Foundation

/// 字幕搜索由服务端翻页，一次运行收集到最终列表；中断后由用户重新发起。
@MainActor
final class SubtitleSearchSession: ObservableObject, PageImageStackObserver {
  enum State: Equatable {
    case idle, searching, interrupted, completed, cancelled, invalidated
    case failed(String)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var rows: [SubtitleSearchRow] = []
  /// 只有服务端交付的最终列表为 true。媒体搜索在此之前的行是未匹配候选。
  @Published private(set) var resultsAreFinal = false
  /// 本次已收到的条数。预览阶段只显示前几条，可能多于 rows。
  @Published private(set) var receivedCount = 0
  @Published private(set) var progressText = "正在搜索…"
  @Published private(set) var progress = 0.0
  @Published private(set) var downloadedEnclosures: Set<String> = []

  let request: SubtitleSearchRequest
  private let apiService: APIService
  private let session: APIServiceSessionSnapshot
  private let doneCloseDelayNanoseconds: UInt64
  private var networkTask: Task<Void, Never>?
  private var sessionSubscription: AnyCancellable?
  private let runs: SearchRunGate

  init(
    request: SubtitleSearchRequest,
    apiService: APIService = .shared,
    doneCloseDelayNanoseconds: UInt64 = 1_500_000_000
  ) {
    self.request = request
    self.apiService = apiService
    self.doneCloseDelayNanoseconds = doneCloseDelayNanoseconds
    self.session = apiService.sessionSnapshot()
    self.runs = SearchRunGate(apiService: apiService)
    sessionSubscription = apiService.sessionInvalidationPublisher(for: session).sink { [weak self] in
      guard let self else { return }
      self.cancel()
      self.state = .invalidated
    }
  }

  // Task 可跨执行器取消；AnyCancellable 在释放时自行取消订阅。
  nonisolated deinit { networkTask?.cancel() }

  var isSearching: Bool { state == .searching }
  var didFinish: Bool {
    switch state {
    case .completed, .failed, .invalidated: true
    default: false
    }
  }
  var errorMessage: String? {
    switch state {
    case .failed(let message): message
    case .invalidated: "登录状态已更新，请返回后重新搜索。"
    default: nil
    }
  }
  var canRestart: Bool {
    guard isSessionValid else { return false }
    return switch state {
    case .interrupted, .failed: true
    default: false
    }
  }
  var canDownload: Bool { isSessionValid && state != .cancelled }
  /// 详情页在出现后才开始搜，首帧也按加载显示，不能先闪成功空态。
  var showsLoading: Bool { isSearching || (state == .idle && isSessionValid) }
  /// 取消后页面正在退场，不再显示空态。
  var showsEmptyState: Bool { rows.isEmpty && (didFinish || state == .interrupted) }
  /// 搜索进行中不铺卡片。已收到候选后才能停下来查看。
  var canStopAndView: Bool { isSearching && !rows.isEmpty }
  var receivedSummary: String {
    let received = "已收到 \(receivedCount) 个字幕"
    guard receivedCount > rows.count else { return received }
    return "\(received) · 停止后显示最新 \(rows.count) 个"
  }
  var showsResultCards: Bool { !isSearching && !rows.isEmpty }
  /// 媒体搜索的候选还没经过季集匹配。查看时不能预填当前媒体，避免下进这部片子。
  var showsIncompleteMatch: Bool {
    !resultsAreFinal && request.initialMediaIdentity != nil && !rows.isEmpty
  }

  static func loadingButtonTitle(canStopAndView: Bool) -> String {
    canStopAndView ? "停止并查看" : "取消"
  }

  static func emptyTitle(hasError: Bool) -> String {
    hasError ? "字幕搜索失败" : "未搜索到字幕"
  }

  var emptyStateTitle: String { Self.emptyTitle(hasError: errorMessage != nil) }

  func start() {
    guard state == .idle, isSessionValid else { return }
    collect()
  }

  func restart() {
    guard canRestart else { return }
    collect()
  }

  func stopAndView() { deactivate() }

  func cancel() {
    invalidateRun()
    rows = []
    resultsAreFinal = false
    receivedCount = 0
    downloadedEnclosures = []
    state = .cancelled
  }

  func deactivate() {
    guard isSearching else { return }
    invalidateRun()
    state = .interrupted
  }

  func pageImageStackStateDidChange(_ state: PageImageStackState) {
    if !state.isInteractive { deactivate() }
  }

  func markDownloaded(enclosure: String?) {
    guard let enclosure, !enclosure.isEmpty, isSessionValid else { return }
    downloadedEnclosures.insert(enclosure)
  }

  func downloadModel(for subtitle: SubtitleInfo) -> SubtitleDownloadViewModel {
    SubtitleDownloadViewModel(
      subtitle: subtitle, request: request, apiService: apiService, session: session,
      bindsCurrentMedia: !showsIncompleteMatch,
      onDownloaded: { [weak self] in self?.markDownloaded(enclosure: $0) }
    )
  }

  private func invalidateRun() {
    runs.end()
    networkTask?.cancel()
    networkTask = nil
  }

  private var isSessionValid: Bool {
    apiService.isSessionUnchanged(from: session) && apiService.canAccess(.search)
  }

  private func publish(_ collector: SubtitleSearchCollector) {
    publish(collector.publishedItems, isFinal: collector.finalApplied)
    receivedCount = collector.receivedCount
  }

  private func publish(_ items: [SubtitleInfo], isFinal: Bool) {
    rows = SubtitleSearchRow.makeRows(from: items)
    resultsAreFinal = isFinal
    receivedCount = items.count
  }

  /// 服务端已交付非空最终列表时，后续错误不撤销它；空的最终列表仍按失败处理，允许重试。
  private func finish(_ collector: SubtitleSearchCollector, failure: Error) {
    guard collector.finalApplied, !collector.publishedItems.isEmpty else {
      state = .failed(failure.localizedDescription)
      return
    }
    Logger.error("字幕搜索在最终列表后失败: \(failure.localizedDescription)")
    publish(collector)
    state = .completed
  }

  private func collect() {
    let run = runs.begin()
    state = .searching
    progress = 0
    progressText = "正在搜索…"
    rows = []
    resultsAreFinal = false
    receivedCount = 0
    // 每次发布才短暂取得 owner，网络等待不能让页面和任务互相持有。
    networkTask = Task { [weak self, apiService, request, runs, doneCloseDelayNanoseconds] in
      guard runs.isCurrent(run) else { return }
      var collector = SubtitleSearchCollector()
      defer {
        if runs.owns(run) {
          self?.networkTask = nil
          runs.end(run)
        }
      }
      do {
        var receivedDone = false
        for try await event in apiService.openSubtitleSearchStream(request) {
          guard runs.isCurrent(run) else { return }
          if event.type == "heartbeat" { continue }
          if let text = event.localizedProgress { self?.progressText = text }
          if let value = event.value { self?.progress = value }
          if try collector.receive(event) { self?.publish(collector) }
          if event.type == "done" {
            receivedDone = true
            try await Task.sleep(nanoseconds: doneCloseDelayNanoseconds)
            guard runs.isCurrent(run) else { return }
            break
          }
        }
        guard runs.isCurrent(run) else { return }
        if !receivedDone { throw URLError(.networkConnectionLost) }
        self?.publish(collector)
        self?.state = .completed
      } catch is CancellationError {
        if runs.isCurrent(run) { self?.state = .interrupted }
      } catch let failure as SubtitleSearchFailure {
        guard runs.isCurrent(run) else { return }
        self?.finish(collector, failure: failure)
      } catch {
        guard runs.isCurrent(run) else { return }
        Logger.error("字幕搜索流中断，改用普通请求: \(error.localizedDescription)")
        do {
          let items = try await apiService.searchSubtitles(request)
          guard runs.isCurrent(run) else { return }
          self?.publish(items, isFinal: true)
          self?.state = .completed
        } catch is CancellationError {
          if runs.isCurrent(run) { self?.state = .interrupted }
        } catch {
          guard runs.isCurrent(run) else { return }
          self?.finish(collector, failure: error)
        }
      }
    }
  }
}
