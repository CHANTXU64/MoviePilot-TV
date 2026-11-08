import Foundation

/// MoviePilot 的纯数字后缀表示稳定热修复；预发布和未知后缀不推断为稳定版本。
nonisolated struct MoviePilotVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
  let major: Int
  let minor: Int
  let patch: Int
  let hotfix: Int?

  init?(_ rawValue: String?) {
    guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else { return nil }
    if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
    let release = value.split(separator: "-", omittingEmptySubsequences: false)
    guard release.count == 1 || release.count == 2 else { return nil }
    let core = release[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
      let major = Self.decimal(core[0]),
      let minor = Self.decimal(core[1]),
      let patch = Self.decimal(core[2])
    else { return nil }
    let hotfix: Int?
    if release.count == 2 {
      guard let revision = Self.decimal(release[1]), revision > 0 else { return nil }
      hotfix = revision
    } else {
      hotfix = nil
    }
    self.major = major
    self.minor = minor
    self.patch = patch
    self.hotfix = hotfix
  }

  private static func decimal(_ value: Substring) -> Int? {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
      value.count == 1 || value.first != "0"
    else { return nil }
    return Int(value)
  }

  var description: String {
    "v\(major).\(minor).\(patch)" + (hotfix.map { "-\($0)" } ?? "")
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    return (lhs.hotfix ?? 0) < (rhs.hotfix ?? 0)
  }
}

/// 按后端版本开放新行为、或提示从某版本起才有的副作用。两种极性相反，不能混用（`.agents/engineering-invariants.md` §7）；
/// 起始版本登记在各自的使用处。已知缺陷版本门禁按缺陷区间判断，不走这里（见 `BackendCapability`）。
nonisolated enum BackendVersionGate {
  /// 新行为、新取值从 `minimum` 起才成立：可解析且不低于它（含热修复和尚未登记的更新版本）才开放；读不出或无法解析时不开放。
  static func isAvailable(since minimum: String, backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion), let minimum = MoviePilotVersion(minimum) else {
      return false
    }
    return version >= minimum
  }

  /// 破坏性副作用从 `minimum` 起才发生：只有已解析且低于它时才确定不会发生；读不出或无法解析时按会发生处理，照常提示。
  static func mayHaveSideEffect(since minimum: String, backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion), let minimum = MoviePilotVersion(minimum) else {
      return true
    }
    return version >= minimum
  }
}

nonisolated enum BackendCompatibilityStatus: String, Sendable {
  case belowMinimum
  case unregistered
  case newerThanRegistry
  case unparseable
  case registered
}

/// 已兼容的 MoviePilot 精确版本。按官方源码核对 TV 实际用到的接口和写回字段没有影响即可登记，
/// 不要求真实后端实测；未登记的中间版本不推断为兼容。核对依据见 docs/backend-version-compatibility.md。
nonisolated struct BackendCompatibilityRegistry: Equatable, Sendable {
  let versions: [MoviePilotVersion]

  init(versions: [MoviePilotVersion]) {
    precondition(!versions.isEmpty, "至少登记一个兼容版本")
    precondition(Set(versions).count == versions.count, "兼容版本不能重复")
    self.versions = versions.sorted()
  }

  var minimumVersion: MoviePilotVersion { versions[0] }
  var latestVersion: MoviePilotVersion { versions[versions.count - 1] }

  func status(for rawVersion: String?) -> BackendCompatibilityStatus {
    guard let version = MoviePilotVersion(rawVersion) else { return .unparseable }
    if versions.contains(version) { return .registered }
    if version < minimumVersion { return .belowMinimum }
    if version > latestVersion { return .newerThanRegistry }
    return .unregistered
  }

  static let current = BackendCompatibilityRegistry(
    versions: [
      "v3.0.4", "v3.0.5", "v3.0.7", "v3.0.10", "v3.0.10-1", "v3.1.0", "v3.1.1", "v3.1.2", "v3.1.2-1",
      "v3.1.4", "v3.1.6", "v3.1.7", "v3.1.8", "v3.1.9", "v3.2.0", "v3.2.1", "v3.2.2", "v3.2.3",
    ].map { MoviePilotVersion($0)! }
  )
}

nonisolated enum BackendFeature: Equatable, Sendable {
  case forkSubscription
}

nonisolated struct BackendCapability: Equatable, Sendable {
  let unavailableReason: String?
  let unavailableHint: String?
  var isAvailable: Bool { unavailableReason == nil }
}

/// 已证实的功能缺陷独立于兼容登记：未登记、未知或未来版本不因此禁用。
nonisolated enum BackendCapabilities {
  private struct KnownDefect: Sendable {
    let feature: BackendFeature
    let firstAffected: MoviePilotVersion
    let firstFixed: MoviePilotVersion
    let reason: @Sendable (MoviePilotVersion) -> String
    /// 入口置灰时替代原标题的短提示。
    let hint: String
  }

  private static let knownDefects = [
    KnownDefect(
      feature: .forkSubscription,
      firstAffected: MoviePilotVersion("v3.0.1")!,
      firstFixed: MoviePilotVersion("v3.0.5")!,
      reason: { version in
        "当前 MoviePilot \(version) 的复用订阅接口存在已知问题，可能创建成功却返回失败。为避免重复创建，此版本暂不可复用；升级到 v3.0.5 或更高版本后即可使用。普通订阅与编辑仍可使用。"
      },
      hint: "复用订阅（需升级至 v3.0.5）"
    )
  ]

  static func capability(for feature: BackendFeature, backendVersion: String?) -> BackendCapability
  {
    guard let version = MoviePilotVersion(backendVersion),
      let defect = knownDefects.first(where: {
        $0.feature == feature && version >= $0.firstAffected && version < $0.firstFixed
      })
    else { return BackendCapability(unavailableReason: nil, unavailableHint: nil) }
    return BackendCapability(unavailableReason: defect.reason(version), unavailableHint: defect.hint)
  }
}
