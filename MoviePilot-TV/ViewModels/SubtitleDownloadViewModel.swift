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

  let subtitle: SubtitleInfo
  @Published private(set) var state: State = .editing
  @Published private(set) var mediaSource: MediaSearchSource
  @Published var mediaId: String
  @Published private(set) var selectedSavePath: String?
  @Published private(set) var directories: [DownloadDirectory] = []
  @Published private(set) var directoryError: String?
  @Published private(set) var isLoadingDirectories = false

  /// 提交的媒体来源。预填身份沿用搜索时的来源，切换来源后改用所选来源。
  private var submissionSource: String
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
    let identity = request.initialMediaIdentity
    let source = identity.flatMap { MediaSearchSource(rawValue: $0.source) }
      ?? MediaSearchSource(rawValue: apiService.settings?.RECOGNIZE_SOURCE ?? "") ?? .themoviedb
    mediaSource = source
    mediaId = identity?.mediaId ?? ""
    submissionSource = identity?.source ?? source.rawValue
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
    canEdit && !normalizedMediaId.isEmpty && MediaIdentifier.isValidManualMediaId(normalizedMediaId)
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
    submissionSource = source.rawValue
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
      identity: MediaIdentity(source: submissionSource, mediaId: normalizedMediaId),
      savePath: selectedSavePath
    )
    state = .submitting(target)
    let task = Task { [weak self, apiService, session, subtitle] in
      defer { self?.downloadTask = nil }
      do {
        try await apiService.downloadSubtitle(
          subtitle: subtitle, mediaSource: target.identity.source,
          mediaId: target.identity.mediaId, savePath: target.savePath
        )
        guard let self, !Task.isCancelled, apiService.isSessionUnchanged(from: session),
          self.state == .submitting(target) else { return }
        self.onDownloaded(subtitle.enclosure)
        self.state = .completed
      } catch {
        guard self?.state == .submitting(target) else { return }
        if error is CancellationError || Task.isCancelled {
          self?.state = .failed("下载请求已中断，请检查保存结果后再重试。")
        } else {
          self?.state = .failed(error.localizedDescription)
        }
      }
    }
    downloadTask = task
    return task
  }

  func close() {
    state = .closed
    downloadTask?.cancel()
    downloadTask = nil
  }
}
