import Foundation

enum AppVersionInfo {
  nonisolated static var minimumCompatibleMoviePilotVersion: String {
    BackendCompatibilityRegistry.current.minimumVersion.description
  }

  nonisolated static var latestCompatibleMoviePilotVersion: String {
    BackendCompatibilityRegistry.current.latestVersion.description
  }

  nonisolated static func currentAppVersion(bundle: Bundle = .main) -> String {
    let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return displayAppVersion(shortVersion: shortVersion)
  }

  nonisolated static func displayAppVersion(shortVersion: String?) -> String {
    guard let shortVersion else { return "未知" }
    let trimmedVersion = shortVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedVersion.isEmpty else { return "未知" }
    return trimmedVersion.hasPrefix("v") ? trimmedVersion : "v\(trimmedVersion)"
  }

  /// 比较 MoviePilot-TV 自身的版本号（更新说明使用）。App 版本可能只有两段，
  /// 缺少的段按 0 处理；不能用只接受三段的 MoviePilot 后端版本解析。
  nonisolated static func compareAppVersion(_ lhs: String?, to rhs: String) -> ComparisonResult? {
    guard let lhsComponents = appVersionComponents(lhs),
      let rhsComponents = appVersionComponents(rhs)
    else { return nil }
    let length = max(lhsComponents.count, rhsComponents.count)
    for index in 0..<length {
      let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
      let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
      if lhsValue < rhsValue { return .orderedAscending }
      if lhsValue > rhsValue { return .orderedDescending }
    }
    return .orderedSame
  }

  nonisolated private static func appVersionComponents(_ version: String?) -> [Int]? {
    guard let version else { return nil }
    var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty, normalized != "未知" else { return nil }
    if normalized.hasPrefix("v") { normalized.removeFirst() }
    let core = normalized.split(
      omittingEmptySubsequences: false,
      whereSeparator: { $0 == "-" || $0 == "+" || $0 == " " }
    ).first
    guard let core, core.first?.isNumber == true else { return nil }
    let components = core.split(separator: ".", omittingEmptySubsequences: false).map { part -> Int? in
      guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
      return Int(part)
    }
    guard components.allSatisfy({ $0 != nil }) else { return nil }
    let numericComponents = components.compactMap { $0 }
    return numericComponents.isEmpty ? nil : numericComponents
  }
}

/// 已登记的兼容版本不提示；其余情况提示一次，确认后同一服务器的同一后端版本不再提示。
nonisolated struct BackendVersionWarning: Identifiable, Equatable {
  let backendVersion: String?
  let status: BackendCompatibilityStatus
  private let registry: BackendCompatibilityRegistry

  init?(backendVersion: String?, registry: BackendCompatibilityRegistry = .current) {
    let status = registry.status(for: backendVersion)
    guard status != .registered else { return nil }
    self.backendVersion = backendVersion
    self.status = status
    self.registry = registry
  }

  private var normalizedBackendVersion: String? {
    guard let trimmed = backendVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty, trimmed != "未知"
    else { return nil }
    return trimmed
  }

  /// 只由后端版本决定：新增兼容版本或修改提示文字都不会让已确认的同一版本重新提示。
  var id: String {
    MoviePilotVersion(backendVersion)?.description ?? normalizedBackendVersion ?? "unknown"
  }

  var title: String {
    switch status {
    case .belowMinimum: return "MoviePilot 后端版本过低"
    case .unregistered: return "MoviePilot 后端版本尚未核对"
    case .newerThanRegistry: return "MoviePilot 后端版本较新"
    case .unparseable: return "无法确认 MoviePilot 后端版本"
    case .registered: return "MoviePilot 后端版本"
    }
  }

  var message: String {
    var lines = ["当前后端版本：\(normalizedBackendVersion ?? "无法确认")"]
    switch status {
    case .belowMinimum:
      lines.append("MoviePilot-TV 最早兼容 \(registry.minimumVersion)，低版本后端可能出现功能异常，建议升级后端。")
    case .unregistered:
      lines.append("该版本尚未核对兼容性。已兼容的版本：\(compatibleVersionList)。")
    case .newerThanRegistry:
      lines.append("该版本高于已兼容的最新版本 \(registry.latestVersion)，可能存在兼容问题，可留意 MoviePilot-TV 更新。")
    case .unparseable:
      let reason = normalizedBackendVersion == nil ? "未取得后端版本号" : "无法识别该版本号"
      lines.append("\(reason)，无法确认是否兼容。已兼容的版本：\(compatibleVersionList)。")
    case .registered:
      break
    }
    lines.append("仍可继续使用。")
    return lines.joined(separator: "\n")
  }

  private var compatibleVersionList: String {
    registry.versions.map(\.description).joined(separator: "、")
  }
}
