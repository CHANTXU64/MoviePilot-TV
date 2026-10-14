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

  func start() {
    guard state == .idle, isSessionValid else { return }
    collect()
  }

  func restart() {
    guard canRestart else { return }
    collect()
  }

  func cancel() {
    invalidateRun()
    rows = []
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

  private func publish(_ items: [SubtitleInfo]) {
    rows = SubtitleSearchRow.makeRows(from: items)
  }

  private func collect() {
    let run = runs.begin()
    state = .searching
    progress = 0
    progressText = "正在搜索…"
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
          if try collector.receive(event) { self?.publish(collector.publishedItems) }
          if event.type == "done" {
            receivedDone = true
            try await Task.sleep(nanoseconds: doneCloseDelayNanoseconds)
            guard runs.isCurrent(run) else { return }
            break
          }
        }
        guard runs.isCurrent(run) else { return }
        if !receivedDone { throw URLError(.networkConnectionLost) }
        self?.publish(collector.publishedItems)
        self?.state = .completed
      } catch is CancellationError {
        if runs.isCurrent(run) { self?.state = .interrupted }
      } catch let failure as SubtitleSearchFailure {
        guard runs.isCurrent(run) else { return }
        // 服务端已交付最终列表时，后续终态错误不撤销已交付的结果。
        if collector.finalApplied, !collector.publishedItems.isEmpty {
          Logger.error("字幕搜索在最终列表后收到错误: \(failure.localizedDescription)")
          self?.publish(collector.publishedItems)
          self?.state = .completed
        } else {
          self?.state = .failed(failure.localizedDescription)
        }
      } catch {
        guard runs.isCurrent(run) else { return }
        Logger.error("字幕搜索流中断，改用普通请求: \(error.localizedDescription)")
        do {
          let items = try await apiService.searchSubtitles(request)
          guard runs.isCurrent(run) else { return }
          self?.publish(items)
          self?.state = .completed
        } catch is CancellationError {
          if runs.isCurrent(run) { self?.state = .interrupted }
        } catch {
          guard runs.isCurrent(run) else { return }
          self?.state = .failed(error.localizedDescription)
        }
      }
    }
  }
}
