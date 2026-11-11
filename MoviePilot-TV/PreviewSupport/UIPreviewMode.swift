#if DEBUG
import Foundation

enum UIPreviewMode {
  nonisolated static let launchArgument = "-uiPreviewMode"
  nonisolated static let sceneLaunchArgument = "-uiPreviewScene"

  nonisolated static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
    arguments.contains(launchArgument)
  }

  nonisolated static func sceneID(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
    guard let index = arguments.firstIndex(of: sceneLaunchArgument) else { return nil }
    let valueIndex = arguments.index(after: index)
    guard arguments.indices.contains(valueIndex) else { return nil }
    let value = arguments[valueIndex]
    return value.hasPrefix("-") ? nil : value
  }
}
#endif
