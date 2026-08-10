import SwiftUI
import Combine

enum NotificationType {
  case info
  case success
  case warning
  case error

  var tintColor: Color {
    switch self {
    case .info:
      return .blue
    case .success:
      return .green
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }

  var icon: String {
    switch self {
    case .info:
      "info.circle.fill"
    case .success:
      "checkmark.circle.fill"
    case .warning:
      "exclamationmark.triangle.fill"
    case .error:
      "xmark.circle.fill"
    }
  }
}

@MainActor
class NotificationManager: ObservableObject {
  @Published private(set) var isShowing: Bool = false
  @Published private(set) var message: String = ""
  @Published private(set) var type: NotificationType = .info

  private var task: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()
  private var observedSessionUIIdentity: String

  init() {
    observedSessionUIIdentity = APIService.shared.uiIdentity
    APIService.shared.$session
      .dropFirst()
      .sink { [weak self] session in
        guard let self else { return }
        let shouldHide = session.token == nil
          || session.uiIdentity != self.observedSessionUIIdentity
        self.observedSessionUIIdentity = session.uiIdentity
        guard shouldHide else { return }
        self.task?.cancel()
        self.isShowing = false
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .subscriptionSaveDidComplete)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.show(message: "订阅成功", type: .success)
      }
      .store(in: &cancellables)
  }

  func show(message: String, type: NotificationType = .info, duration: TimeInterval = 5) {
    task?.cancel()
    self.message = message
    self.type = type
    withAnimation(.spring()) {
      self.isShowing = true
    }

    task = Task { [weak self] in
      let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled, let self else { return }
      withAnimation(.spring()) {
        self.isShowing = false
      }
    }
  }
}
