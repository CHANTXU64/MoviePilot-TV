import Foundation

enum AppVersionInfo {
  nonisolated static var minimumMaintainedMoviePilotVersion: String {
    BackendCompatibilityRegistry.current.minimumMaintainedVersion.description
  }

  nonisolated static var latestRegisteredMoviePilotVersion: String {
    BackendCompatibilityRegistry.current.latestRegisteredVersion?.description ?? "暂无登记"
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

  nonisolated static func compareMoviePilotVersion(_ lhs: String?, to rhs: String) -> ComparisonResult? {
    guard let lhs = MoviePilotVersion(lhs), let rhs = MoviePilotVersion(rhs) else { return nil }
    if lhs < rhs { return .orderedAscending }
    if lhs > rhs { return .orderedDescending }
    return .orderedSame
  }
}

nonisolated struct BackendVersionWarning: Identifiable, Equatable {
  let backendVersion: String?
  let assessment: BackendCompatibilityAssessment
  private let registry: BackendCompatibilityRegistry

  init?(backendVersion: String?, registry: BackendCompatibilityRegistry = .current) {
    let assessment = registry.assessment(for: backendVersion)
    guard !assessment.isFullyValidated || assessment.record?.limitations.isEmpty == false else { return nil }
    self.backendVersion = backendVersion
    self.assessment = assessment
    self.registry = registry
  }

  private var normalizedBackendVersion: String? {
    guard let trimmed = backendVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty, trimmed != "未知"
    else { return nil }
    return trimmed
  }

  var id: String {
    let version = assessment.version?.description ?? normalizedBackendVersion ?? "unknown"
    return "\(version)|\(assessment.status.rawValue)|\(registry.acknowledgementIdentity)"
  }

  var title: String {
    switch assessment.status {
    case .belowMinimum: return "MoviePilot 后端版本低于维护下限"
    case .unregistered: return "MoviePilot 后端版本尚未登记"
    case .newerThanRegistry: return "MoviePilot 后端版本高于最新登记"
    case .unparseable: return "无法确认 MoviePilot 后端版本"
    case .registered:
      return assessment.isFullyValidated ? "MoviePilot 后端兼容性提示" : "MoviePilot 后端兼容性待验证"
    }
  }

  var message: String {
    var lines = ["当前后端版本：\(normalizedBackendVersion ?? "无法确认")"]
    switch assessment.status {
    case .belowMinimum:
      lines.append("低于最早维护版本 \(registry.minimumMaintainedVersion)，不在当前维护范围内。")
    case .unregistered:
      lines.append("该精确版本未登记，不能依据版本区间确认兼容。")
    case .newerThanRegistry:
      lines.append("高于最新登记版本 \(registry.latestRegisteredVersion?.description ?? "暂无登记")，尚无该版本的兼容记录。请更新 MoviePilot-TV 客户端后重新检查兼容记录。")
    case .unparseable:
      let reason = normalizedBackendVersion == nil ? "未取得可解析的后端版本号" : "无法解析该版本号"
      lines.append("\(reason)，预发布或未知后缀不能视为已登记的稳定版本。")
    case .registered:
      if let record = assessment.record { lines.append(record.summary) }
    }
    if !assessment.newerRecords.isEmpty {
      lines.append("比当前版本更新的登记记录（不代表中间版本均兼容）：")
      lines.append(contentsOf: assessment.newerRecords.map(\.summary))
    } else if assessment.status == .unparseable {
      lines.append("现有登记记录（无法与当前版本比较）：")
      lines.append(contentsOf: registry.records.map(\.summary))
    }
    if let validated = registry.latestValidatedVersion {
      if let version = assessment.version, validated > version {
        lines.append("建议升级到已完成源码审查、合同 fixture 和真实后端实测的 \(validated)。")
      } else {
        lines.append("已完成上述验证的最新登记版本：\(validated)；请核对当前版本后再决定是否切换。")
      }
    } else {
      lines.append("当前暂无完成全部验证的真实后端实测记录，暂无已验证升级目标。")
      if let current = assessment.version,
        let reviewed = registry.records.last(where: { $0.sourceReview.isVerified }),
        reviewed.version > current
      {
        lines.append("如需更新，建议选择较新的源码已审查登记版本 \(reviewed.version)；其状态为：\(reviewed.validationSummary)。源码审查不能替代真实后端实测。")
      }
    }
    lines.append("仍可继续使用；具体功能限制以登记说明为准。")
    return lines.joined(separator: "\n")
  }
}
