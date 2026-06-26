import Foundation

enum AppVersionInfo {
  nonisolated static let compatibleMoviePilotVersion = "v2.13.14"

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

  nonisolated static func compareMoviePilotVersion(
    _ lhs: String?,
    to rhs: String
  ) -> ComparisonResult? {
    guard
      let lhsComponents = moviePilotVersionComponents(lhs),
      let rhsComponents = moviePilotVersionComponents(rhs)
    else {
      return nil
    }

    let length = max(lhsComponents.count, rhsComponents.count)
    for index in 0..<length {
      let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
      let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
      if lhsValue < rhsValue { return .orderedAscending }
      if lhsValue > rhsValue { return .orderedDescending }
    }
    return .orderedSame
  }

  nonisolated static func supportsMoviePilotVersion(
    _ backendVersion: String?,
    minimumVersion: String = compatibleMoviePilotVersion
  ) -> Bool? {
    guard let result = compareMoviePilotVersion(backendVersion, to: minimumVersion) else {
      return nil
    }
    return result != .orderedAscending
  }

  nonisolated private static func moviePilotVersionComponents(_ version: String?) -> [Int]? {
    guard let version else { return nil }
    var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty, normalized != "未知" else { return nil }
    if normalized.hasPrefix("v") {
      normalized.removeFirst()
    }
    let core = normalized.split(whereSeparator: { $0 == "-" || $0 == "+" || $0 == " " }).first
    guard let core else { return nil }

    let components = core.split(separator: ".").compactMap { part -> Int? in
      let numericPrefix = part.prefix { $0.isNumber }
      guard !numericPrefix.isEmpty else { return nil }
      return Int(numericPrefix)
    }
    return components.isEmpty ? nil : components
  }
}

nonisolated struct BackendVersionWarning: Identifiable, Equatable {
  let backendVersion: String?
  let requiredVersion: String

  var id: String {
    "\(backendVersion ?? "unknown")|\(requiredVersion)"
  }

  var title: String {
    if backendVersion == nil {
      return "无法确认 MoviePilot 后端版本"
    }
    return "MoviePilot 后端版本过低"
  }

  var message: String {
    let currentVersion = backendVersion ?? "无法确认"
    return
      "当前后端版本：\(currentVersion)\nMoviePilot-TV 需要 \(requiredVersion) 或更高版本。低版本后端可能带来严重功能异常或数据丢失，请尽快升级后端。如仍需临时使用，仍可继续使用。"
  }
}
