import Combine
import Foundation

@MainActor
final class SubtitleDownloadViewModel: ObservableObject, Identifiable {
  let id = UUID()
  struct Target: Equatable {
    let identity: MediaIdentity
    let savePath: String?
  }
  enum State: Equatable {
    case editing, submitting(Target), completed, failed(String), invalidated, closed
  }

  /// 只有收到字幕下载接口的响应才算服务端处理结束。取消、超时和断线都还可能继续落盘。
  enum RemoteExchange: Equatable {
    case pending
    case serverFinished
    case interrupted
  }

  let subtitle: SubtitleInfo
  @Published private(set) var state: State = .editing
  @Published private(set) var remoteExchange: RemoteExchange = .pending
  @Published private(set) var mediaSource: MediaSearchSource
  @Published var mediaId: String
  @Published private(set) var selectedSavePath: String?
  @Published private(set) var directories: [DownloadDirectory] = []
  @Published private(set) var directoryError: String?
  @Published private(set) var isLoadingDirectories = false

  private let onDownloaded: (String?) -> Void
  private let apiService: APIService
  private let session: APIServiceSessionSnapshot
  private var downloadTask: Task<Void, Never>?
  private var sessionSubscription: AnyCancellable?

  init(
    subtitle: SubtitleInfo, request: SubtitleSearchRequest,
    apiService: APIService = .shared, session: APIServiceSessionSnapshot? = nil,
    onDownloaded: @escaping (String?) -> Void = { _ in }
  ) {
    self.subtitle = subtitle
    self.onDownloaded = onDownloaded
    self.apiService = apiService
    self.session = session ?? apiService.sessionSnapshot()
    // 预填身份的来源与 ID 成对使用；来源无法识别时不把 ID 挪到别的来源下。
    let identity = request.initialMediaIdentity
    let initialSource = identity.flatMap { MediaSearchSource(rawValue: $0.source) }
    mediaSource = initialSource
      ?? MediaSearchSource(rawValue: apiService.settings?.RECOGNIZE_SOURCE ?? "") ?? .themoviedb
    mediaId = initialSource == nil ? "" : identity?.mediaId ?? ""
    sessionSubscription = apiService.sessionInvalidationPublisher(for: self.session).sink { [weak self] in
      guard let self, self.state != .closed, self.state != .completed else { return }
      self.state = .invalidated
      self.downloadTask?.cancel()
    }
  }

  nonisolated deinit { downloadTask?.cancel() }

  private var isSessionValid: Bool {
    apiService.isSessionUnchanged(from: session) && apiService.canAccess(.search)
  }
  var canEdit: Bool {
    guard isSessionValid else { return false }
    return switch state {
    case .editing, .failed: true
    default: false
    }
  }
  var isSubmitting: Bool {
    if case .submitting = state { return true }
    return false
  }
  var failure: String? {
    switch state {
    case .failed(let message): message
    case .invalidated: "登录状态已更新，请关闭后重新搜索字幕。"
    default: nil
    }
  }
  private var normalizedMediaId: String {
    mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  var canSubmit: Bool {
    canEdit && !normalizedMediaId.isEmpty && mediaSource.isValidManualId(normalizedMediaId)
  }

  var savePathChoices: [String] {
    var seen = Set<String>()
    return directories.compactMap { directory in
      guard let path = directory.save_path,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        seen.insert(path).inserted else { return nil }
      return path
    }
  }

  func selectSource(_ source: MediaSearchSource) {
    guard canEdit, source != mediaSource else { return }
    mediaSource = source
    mediaId = ""
  }

  func selectSavePath(_ path: String?) {
    guard canEdit else { return }
    selectedSavePath = path
  }

  func loadDirectories() async {
    guard canEdit, !isLoadingDirectories else { return }
    isLoadingDirectories = true
    directoryError = nil
    defer { isLoadingDirectories = false }
    do {
      let directories = try await apiService.fetchDownloadDirectories()
      guard state != .closed, isSessionValid, !Task.isCancelled else { return }
      self.directories = directories
      directoryError = nil
    } catch is CancellationError {
      return
    } catch {
      guard state != .closed, isSessionValid, !Task.isCancelled else { return }
      directoryError = error.localizedDescription
    }
  }

  @discardableResult
  func submit() -> Task<Void, Never>? {
    guard canSubmit else { return nil }
    let target = Target(
      identity: MediaIdentity(source: mediaSource.rawValue, mediaId: normalizedMediaId),
      savePath: selectedSavePath
    )
    state = .submitting(target)
    // 重试必须从 pending 重新计，否则取消和断线会沿用上一次的已结束状态。
    remoteExchange = .pending
    let task = Task { [weak self, apiService, session, subtitle] in
      defer { self?.downloadTask = nil }
      do {
        try await apiService.downloadSubtitle(
          subtitle: subtitle, mediaSource: target.identity.source,
          mediaId: target.identity.mediaId, savePath: target.savePath
        )
        // 正常返回说明同步下载接口已经结束。先记下这个事实，再决定能否把成功显示出来。
        guard let self else { return }
        self.remoteExchange = .serverFinished
        guard apiService.isSessionUnchanged(from: session),
          self.state == .submitting(target) else { return }
        self.onDownloaded(subtitle.enclosure)
        self.state = .completed
      } catch {
        guard let self else { return }
        if Self.serverFinished(error) {
          self.remoteExchange = .serverFinished
        } else if self.remoteExchange == .pending {
          self.remoteExchange = .interrupted
        }
        guard self.state == .submitting(target) else { return }
        if error is CancellationError || Task.isCancelled {
          self.state = .failed("下载请求已中断，请检查保存结果后再重试。")
        } else {
          self.state = .failed(error.localizedDescription)
        }
      }
    }
    downloadTask = task
    return task
  }

  func close() {
    if remoteExchange == .pending {
      remoteExchange = .interrupted
    }
    state = .closed
    downloadTask?.cancel()
    downloadTask = nil
  }

  private static func serverFinished(_ error: Error) -> Bool {
    switch error as? APIError {
    case .serverMessage, .authenticationChallenge, .unauthorized, .credentialsRejected,
      .decodingError, .mfaUnsupported:
      return true
    case .networkError, .invalidURL, .unknown, .none:
      return false
    }
  }
}
