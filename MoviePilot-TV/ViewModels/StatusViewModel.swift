import Foundation
import SwiftUI
import Combine

@MainActor
class StatusViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var statistic: Statistic?
  @Published var storage: Storage?
  @Published var downloader: DownloaderInfo?
  @Published private(set) var hasCompletedInitialLoad = false

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  var canRequestSuperUserEndpoints: Bool {
    apiService.canRequestSuperUserEndpoints
  }

  var unavailableValueText: String {
    hasCompletedInitialLoad ? "未获取" : "获取中…"
  }

  func refreshAllData() async {
    guard apiService.canRequestSuperUserEndpoints else {
      statistic = nil
      storage = nil
      downloader = nil
      hasCompletedInitialLoad = true
      return
    }

    let sessionSnapshot = apiService.sessionSnapshot()
    // 刷新统计信息
    do {
      async let stat = apiService.fetchStatistic()
      async let stor = apiService.fetchStorage()
      async let down = apiService.fetchDownloaderInfo()

      let values = try await (stat, stor, down)
      guard !Task.isCancelled,
        apiService.isSessionUnchanged(from: sessionSnapshot),
        apiService.canRequestSuperUserEndpoints
      else { return }
      statistic = values.0
      storage = values.1
      downloader = values.2
      hasCompletedInitialLoad = true
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled,
        apiService.isSessionUnchanged(from: sessionSnapshot),
        apiService.canRequestSuperUserEndpoints
      else { return }
      hasCompletedInitialLoad = true
      Logger.error("Error fetching dashboard data: \(error)")
    }
  }
}
