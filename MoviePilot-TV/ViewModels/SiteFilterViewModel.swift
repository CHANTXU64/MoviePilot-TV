import Combine
import Foundation
import SwiftUI

@MainActor
class SiteFilterViewModel: ObservableObject {
  @Published var selectedSites: Set<Int>
  @Published var availableSites: [Site] = []
  private(set) var hasLoadedSites: Bool = false

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    self.selectedSites = SystemViewModel.currentDefaultSearchSites(apiService: apiService)
  }

  func loadSites() async {
    guard apiService.canAccess(.search) else {
      clearLoadedSites()
      return
    }
    do {
      let sites = try await apiService.fetchSites()
      self.availableSites = sites
      hasLoadedSites = true
      normalizeSelectedSites()
    } catch is CancellationError {
      if !apiService.canAccess(.search) {
        clearLoadedSites()
      }
      return
    } catch {
      print("Failed to load sites: \(error)")
    }
  }

  var siteButtonLabel: String {
    if selectedSites.isEmpty {
      return "全部站点"
    } else if selectedSites.count == 1 {
      if let site = availableSites.first(where: { selectedSites.contains($0.id) }) {
        return site.name
      }
      return "1 个站点"
    } else {
      return "\(selectedSites.count) 个站点"
    }
  }

  var sitesString: String? {
    selectedSites.isEmpty ? nil : selectedSites.sorted().map { String($0) }.joined(separator: ",")
  }

  private func normalizeSelectedSites() {
    guard hasLoadedSites else { return }

    let availableSiteIds = Set(availableSites.map(\.id))
    let normalizedSites = selectedSites.intersection(availableSiteIds)
    if normalizedSites != selectedSites {
      selectedSites = normalizedSites
    }
  }

  private func clearLoadedSites() {
    availableSites = []
    selectedSites = []
    hasLoadedSites = false
  }
}
