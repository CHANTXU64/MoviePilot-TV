import Foundation

enum PresentationTransitionRetention {
  static let duration = Duration.seconds(1)
}

@MainActor
final class PresentationReleaseScheduler {
  private var releaseTask: Task<Void, Never>?

  var isPending: Bool {
    releaseTask != nil
  }

  func schedule(
    after retention: Duration = PresentationTransitionRetention.duration,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    cancel()
    releaseTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: retention)
      guard !Task.isCancelled, let self else { return }
      self.releaseTask = nil
      action()
    }
  }

  func cancel() {
    releaseTask?.cancel()
    releaseTask = nil
  }

  isolated deinit {
    releaseTask?.cancel()
  }
}
