import SwiftUI

enum MemoryOptimizationMode: String, CaseIterable, Identifiable {
  case automatic
  case enabled
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: return "自动"
    case .enabled: return "开启"
    case .disabled: return "关闭"
    }
  }
}

struct MemoryOptimizationSettings: DynamicProperty {
  static let modeKey = "memoryOptimizationMode"

  @ObservedObject private var apiService: APIService
  @AppStorage(MemoryOptimizationSettings.modeKey) var mode: MemoryOptimizationMode = .automatic
  @AppStorage(PlaybackPreferences.inAppPlaybackKey) private var inAppPlaybackEnabled =
    PlaybackPreferences.defaultInAppPlaybackEnabled

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  var isEnabled: Bool {
    switch mode {
    case .automatic: return automaticIsEnabled
    case .enabled: return true
    case .disabled: return false
    }
  }

  var automaticIsEnabled: Bool {
    !InAppPlaybackAvailability.isEnabledForSession(
      canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
      backendVersion: apiService.settings?.BACKEND_VERSION,
      userEnabled: inAppPlaybackEnabled
    )
  }
}
