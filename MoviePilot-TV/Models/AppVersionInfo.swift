import Foundation

enum AppVersionInfo {
  nonisolated static let compatibleMoviePilotVersion = "v2.13.6"

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
}
