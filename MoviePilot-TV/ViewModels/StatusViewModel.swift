import Foundation
import SwiftUI
import Combine

@MainActor
class StatusViewModel: ObservableObject {
  @Published var statistic: Statistic?
  @Published var storage: Storage?
  @Published var downloader: DownloaderInfo?

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  func refreshAllData() async {
    guard apiService.canRequestSuperUserEndpoints else {
      statistic = nil
      storage = nil
      downloader = nil
      return
    }

    let sessionSnapshot = apiService.sessionSnapshot()
    // 刷新统计信息
    do {
      async let stat = apiService.fetchStatistic()
      async let stor = apiService.fetchStorage()
      async let down = apiService.fetchDownloaderInfo()

      let values = try await (stat, stor, down)
      guard apiService.isSessionUnchanged(from: sessionSnapshot),
        apiService.canRequestSuperUserEndpoints
      else { return }
      statistic = values.0
      storage = values.1
      downloader = values.2
    } catch {
      print("Error fetching dashboard data: \(error)")
    }
  }
}
