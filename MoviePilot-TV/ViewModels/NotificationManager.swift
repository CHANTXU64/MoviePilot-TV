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

class NotificationManager: ObservableObject {
  @Published private(set) var isShowing: Bool = false
  @Published private(set) var message: String = ""
  @Published private(set) var type: NotificationType = .info

  private var task: DispatchWorkItem?

  func show(message: String, type: NotificationType = .info, duration: TimeInterval = 5) {
    DispatchQueue.main.async {
      self.task?.cancel()

      self.message = message
      self.type = type
      withAnimation(.spring()) {
        self.isShowing = true
      }

      let task = DispatchWorkItem {
        withAnimation(.spring()) {
          self.isShowing = false
        }
      }
      self.task = task
      DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
  }
}

