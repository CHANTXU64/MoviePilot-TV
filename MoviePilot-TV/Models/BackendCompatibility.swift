import CryptoKit
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

nonisolated enum BackendContractProfile: String, Sendable {
  case v304
  case v30101
}

/// 三类证据互不代替。reference 指向对应版本、范围与执行结果，不能以测试源码代替执行证据。
nonisolated enum BackendCompatibilityEvidence: Equatable, Sendable {
  case pending
  case verified(reference: String)
  case failed(reference: String)

  var isVerified: Bool {
    if case .verified(let reference) = self {
      return !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return false
  }

  fileprivate var identity: String {
    switch self {
    case .pending: return "pending"
    case .verified(let reference): return "verified:\(reference)"
    case .failed(let reference): return "failed:\(reference)"
    }
  }

  fileprivate func summary(pending: String, verified: String, failed: String) -> String {
    switch self {
    case .pending: return pending
    case .verified: return isVerified ? verified : pending
    case .failed: return failed
    }
  }
}

nonisolated struct BackendCompatibilityRecord: Equatable, Sendable {
  let version: MoviePilotVersion
  let profile: BackendContractProfile
  let sourceReview: BackendCompatibilityEvidence
  let fixtureValidation: BackendCompatibilityEvidence
  let liveValidation: BackendCompatibilityEvidence
  let limitations: [String]

  var isFullyValidated: Bool {
    sourceReview.isVerified && fixtureValidation.isVerified && liveValidation.isVerified
  }

  var validationSummary: String {
    [
      sourceReview.summary(pending: "源码合同待审查", verified: "源码合同已审查", failed: "源码合同审查未通过"),
      fixtureValidation.summary(pending: "合同 fixture 待执行", verified: "合同 fixture 已通过", failed: "合同 fixture 未通过"),
      liveValidation.summary(pending: "真实后端未实测", verified: "真实后端实测已通过", failed: "真实后端实测未通过"),
    ].joined(separator: "；")
  }

  var summary: String {
    let limitationText = limitations.isEmpty ? "未登记额外限制" : limitations.joined(separator: "；")
    return "\(version)：\(validationSummary)。限制：\(limitationText)"
  }

  fileprivate var identityComponents: [String] {
    [version.description, profile.rawValue, sourceReview.identity, fixtureValidation.identity,
      liveValidation.identity, String(limitations.count)] + limitations
  }
}

nonisolated enum BackendCompatibilityStatus: String, Sendable {
  case belowMinimum
  case unregistered
  case newerThanRegistry
  case unparseable
  case registered
}

nonisolated struct BackendCompatibilityAssessment: Equatable, Sendable {
  let status: BackendCompatibilityStatus
  let version: MoviePilotVersion?
  let record: BackendCompatibilityRecord?
  let newerRecords: [BackendCompatibilityRecord]

  /// 在维护范围内按已知合同边界选协议；有协议不等于该精确版本已登记或验证。
  let profile: BackendContractProfile?
  var isFullyValidated: Bool { record?.isFullyValidated == true }
}

nonisolated struct BackendCompatibilityRegistry: Equatable, Sendable {
  let revision: String
  let minimumMaintainedVersion: MoviePilotVersion
  let records: [BackendCompatibilityRecord]

  init(revision: String, minimumMaintainedVersion: MoviePilotVersion, records: [BackendCompatibilityRecord]) {
    precondition(Set(records.map(\.version)).count == records.count, "登记版本不能重复")
    precondition(records.allSatisfy { $0.version >= minimumMaintainedVersion }, "登记版本不能低于维护下限")
    self.revision = revision
    self.minimumMaintainedVersion = minimumMaintainedVersion
    self.records = records.sorted { $0.version < $1.version }
  }

  var latestRegisteredVersion: MoviePilotVersion? { records.last?.version }
  var latestValidatedVersion: MoviePilotVersion? { records.last(where: \.isFullyValidated)?.version }

  func assessment(for rawVersion: String?) -> BackendCompatibilityAssessment {
    guard let version = MoviePilotVersion(rawVersion) else {
      return BackendCompatibilityAssessment(status: .unparseable, version: nil, record: nil, newerRecords: [], profile: nil)
    }
    let newerRecords = records.filter { $0.version > version }
    let record = records.first { $0.version == version }
    let status: BackendCompatibilityStatus
    if version < minimumMaintainedVersion {
      status = .belowMinimum
    } else if record != nil {
      status = .registered
    } else if let latestRegisteredVersion, version > latestRegisteredVersion {
      status = .newerThanRegistry
    } else {
      status = .unregistered
    }
    let profile: BackendContractProfile?
    if version >= minimumMaintainedVersion, let latestRegisteredVersion, version <= latestRegisteredVersion {
      profile = records.last(where: { $0.version <= version })?.profile
    } else {
      profile = nil
    }
    return BackendCompatibilityAssessment(status: status, version: version, record: record,
      newerRecords: newerRecords, profile: profile)
  }

  /// 含证据内容及限制，避免维护者更新证据却漏改 revision 时仍抑制新提示。
  var acknowledgementIdentity: String {
    let components = [revision, minimumMaintainedVersion.description, String(records.count)]
      + records.flatMap(\.identityComponents)
    let payload = components.map { "\($0.utf8.count):\($0)" }.joined()
    return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static let current = BackendCompatibilityRegistry(
    revision: "2026-10-02.1",
    minimumMaintainedVersion: MoviePilotVersion("v3.0.4")!,
    records: [
      BackendCompatibilityRecord(
        version: MoviePilotVersion("v3.0.4")!,
        profile: .v304,
        sourceReview: .verified(
          reference: "docs/backend-version-compatibility.md#登记与证据; MoviePilot e195cc164fc8ff869ffee0ea44a49c7ec475310c; Frontend v3.0.4; TV 使用端点、Subscribe 写回、fork、lookup、整理预览"
        ),
        fixtureValidation: .pending,
        liveValidation: .pending,
        limitations: ["订阅复用（fork）接口存在上游响应声明问题；该问题的后端合同在 v3.0.5 修复", "兼容适配待真实后端实测"]
      ),
      BackendCompatibilityRecord(
        version: MoviePilotVersion("v3.0.5")!,
        profile: .v304,
        sourceReview: .verified(
          reference: "docs/backend-version-compatibility.md#登记与证据; MoviePilot ce3489ae75ff06119f076550f72df57e6f92a6bf; Frontend v3.0.5; TV 使用端点、Subscribe 写回、fork、lookup、整理预览"
        ),
        fixtureValidation: .pending,
        liveValidation: .pending,
        limitations: ["兼容适配待真实后端实测"]
      ),
      BackendCompatibilityRecord(
        version: MoviePilotVersion("v3.0.10-1")!,
        profile: .v30101,
        sourceReview: .verified(
          reference: "docs/backend-version-compatibility.md#登记与证据; MoviePilot 0aa857173f77de31c7c8d9d2e12052d99f37bcc1; Frontend v3.0.10; TV 使用端点、Subscribe 写回、fork、lookup、整理预览"
        ),
        fixtureValidation: .pending,
        liveValidation: .pending,
        limitations: ["兼容适配待真实后端实测"]
      ),
      BackendCompatibilityRecord(
        version: MoviePilotVersion("v3.1.0")!,
        profile: .v30101,
        sourceReview: .verified(
          reference: "docs/backend-version-compatibility.md#登记与证据; MoviePilot 31537bb89dddd3813037c05c4ed0fb939c885813; Frontend v3.1.0; TV 使用端点、Subscribe 写回、fork、lookup、整理预览"
        ),
        fixtureValidation: .pending,
        liveValidation: .pending,
        limitations: ["兼容适配待真实后端实测"]
      ),
    ]
  )
}
