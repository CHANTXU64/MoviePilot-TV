import Foundation

enum AppVersionInfo {
  nonisolated static let compatibleMoviePilotVersion = "v2.15.6"

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
    switch moviePilotVersionCompatibility(backendVersion, minimumVersion: minimumVersion) {
    case .supported:
      return true
    case .unsupported:
      return false
    case .unparseable:
      return nil
    }
  }

  nonisolated static func moviePilotVersionCompatibility(
    _ backendVersion: String?,
    minimumVersion: String = compatibleMoviePilotVersion
  ) -> MoviePilotVersionCompatibility {
    guard let result = compareMoviePilotVersion(backendVersion, to: minimumVersion) else {
      return .unparseable
    }
    return result == .orderedAscending ? .unsupported : .supported
  }

  nonisolated private static func moviePilotVersionComponents(_ version: String?) -> [Int]? {
    guard let version else { return nil }
    var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty, normalized != "未知" else { return nil }
    if normalized.hasPrefix("v") {
      normalized.removeFirst()
    }
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

nonisolated enum MoviePilotVersionCompatibility: Equatable {
  case supported
  case unsupported
  case unparseable
}

nonisolated struct BackendVersionWarning: Identifiable, Equatable {
  let backendVersion: String?
  let requiredVersion: String
  private let compatibility: MoviePilotVersionCompatibility

  init?(backendVersion: String?, requiredVersion: String) {
    let compatibility = AppVersionInfo.moviePilotVersionCompatibility(
      backendVersion,
      minimumVersion: requiredVersion
    )
    guard compatibility != .supported else { return nil }
    self.backendVersion = backendVersion
    self.requiredVersion = requiredVersion
    self.compatibility = compatibility
  }

  private var normalizedBackendVersion: String? {
    guard let trimmed = backendVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty,
      trimmed != "未知"
    else {
      return nil
    }
    return trimmed
  }

  var id: String {
    "\(normalizedBackendVersion ?? "unknown")|\(requiredVersion)"
  }

  var title: String {
    if compatibility == .unparseable {
      return "无法确认 MoviePilot 后端版本"
    }
    return "MoviePilot 后端版本过低"
  }

  var message: String {
    let currentVersion = normalizedBackendVersion ?? "无法确认"
    if compatibility == .unparseable {
      let reason = normalizedBackendVersion == nil ? "未取得可解析的后端版本号" : "无法解析该版本号"
      return
        "当前后端版本：\(currentVersion)\n\(reason)，因此无法确认是否满足 MoviePilot-TV 的最低兼容要求 \(requiredVersion)。仍可继续使用；如遇异常，请确认后端版本信息。"
    }
    return
      "当前后端版本：\(currentVersion)\nMoviePilot-TV 需要 \(requiredVersion) 或更高版本。低版本后端可能带来严重功能异常或数据丢失，请尽快升级后端。如仍需临时使用，仍可继续使用。"
  }
}
