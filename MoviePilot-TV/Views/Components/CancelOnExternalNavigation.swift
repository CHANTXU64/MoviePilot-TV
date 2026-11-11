import SwiftUI

/// 外部入口沿用 Sheet 的 dismiss / onDisappear 取消清理，包括嵌套选择框。
private struct CancelOnExternalNavigation: ViewModifier {
  @Environment(\.dismiss) private var dismiss

  func body(content: Content) -> some View {
    content.onReceive(NotificationCenter.default.publisher(
      for: .imageNavigationPresentationWillReset, object: APIService.shared
    )) { _ in
      dismiss()
    }
  }
}

extension View {
  func cancelOnExternalNavigation() -> some View {
    modifier(CancelOnExternalNavigation())
  }
}
