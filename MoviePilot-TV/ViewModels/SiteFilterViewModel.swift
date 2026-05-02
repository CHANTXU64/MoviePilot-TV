import Combine
import Foundation
import SwiftUI

@MainActor
class SiteFilterViewModel: ObservableObject {
  @Published var selectedSites: Set<Int> = SystemViewModel.currentDefaultSearchSites()
  @Published var availableSites: [Site] = []

  private let apiService = APIService.shared

  func loadSites() async {
    do {
      let sites = try await apiService.fetchSites()
      self.availableSites = sites
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
    selectedSites.isEmpty ? nil : selectedSites.map { String($0) }.joined(separator: ",")
  }
}
