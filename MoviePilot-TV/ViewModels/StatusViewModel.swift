import Foundation
import SwiftUI
import Combine

@MainActor
class StatusViewModel: ObservableObject {
  @Published var statistic: Statistic?
  @Published var storage: Storage?
  @Published var downloader: DownloaderInfo?

  private let apiService = APIService.shared

  func refreshAllData() async {
    guard apiService.canRequestManageEndpoints else {
      statistic = nil
      storage = nil
      downloader = nil
      return
    }

    // 刷新统计信息
    do {
      async let stat = apiService.fetchStatistic()
      async let stor = apiService.fetchStorage()
      async let down = apiService.fetchDownloaderInfo()

      statistic = try await stat
      storage = try await stor
      downloader = try await down
    } catch {
      print("Error fetching dashboard data: \(error)")
    }
  }
}
