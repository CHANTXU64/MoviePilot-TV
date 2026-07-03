#if DEBUG
import Foundation

enum UIPreviewMode {
  nonisolated static let launchArgument = "-uiPreviewMode"

  nonisolated static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
    arguments.contains(launchArgument)
  }
}
#endif
