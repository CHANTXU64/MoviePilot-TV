#if DEBUG
import Foundation

enum UIPreviewMode {
  /// 仅在测试宿主里用来显式开启预览（诊断用）；App 运行不依赖它。
  nonisolated static let launchArgument = "-uiPreviewMode"
  nonisolated static let sceneLaunchArgument = "-uiPreviewScene"

  /// 该分支 Debug App 运行即预览；测试宿主必须保持关闭，否则单元测试会走到 fixture。
  nonisolated static func isEnabled(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    isRunningTests: Bool = UIPreviewMode.isRunningTests
  ) -> Bool {
    if isRunningTests { return arguments.contains(launchArgument) }
    return true
  }

  nonisolated static var isRunningTests: Bool {
    let environment = ProcessInfo.processInfo.environment
    if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
      return true
    }
    if NSClassFromString("XCTestCase") != nil { return true }
    return Bundle.main.bundleIdentifier?.hasSuffix(".Testing") == true
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
