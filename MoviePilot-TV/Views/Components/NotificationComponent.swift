import SwiftUI

struct NotificationView: View {
  var message: String
  var type: NotificationType

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: type.icon)
        .font(.body)
        .foregroundColor(type.tintColor)
      Text(message)
        .font(.body)
    }
    .padding()
    .background(Material.regular)
    .clipShape(Capsule())
    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
  }
}

struct NotificationModifier: ViewModifier {
  @EnvironmentObject var notificationManager: NotificationManager

  func body(content: Content) -> some View {
    ZStack(alignment: .topTrailing) {
      content

      if notificationManager.isShowing {
        NotificationView(
          message: notificationManager.message,
          type: notificationManager.type
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }
}

extension View {
  func withNotification() -> some View {
    self.modifier(NotificationModifier())
  }
}

