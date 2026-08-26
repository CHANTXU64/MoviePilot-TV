import Combine
import Foundation
import SwiftUI

@MainActor
class SiteFilterViewModel: ObservableObject {
  @Published var selectedSites: Set<Int> {
    didSet {
      guard !isUpdatingSelectionInternally, selectedSites != oldValue else { return }
      followsDefaultSites = false
    }
  }
  @Published var availableSites: [Site] = []
  private(set) var hasLoadedSites: Bool = false

  private let apiService: APIService
  private var lastAppliedDefaultSites: Set<Int>
  private var followsDefaultSites = true
  private var isUpdatingSelectionInternally = false
  private var cancellables = Set<AnyCancellable>()

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    let defaultSites = SystemViewModel.currentDefaultSearchSites(apiService: apiService)
    self.selectedSites = defaultSites
    self.lastAppliedDefaultSites = defaultSites

    NotificationCenter.default.publisher(for: .searchDefaultsDidChange)
      .compactMap { $0.object as? SearchDefaultsChange }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] change in
        guard let self, change.profileKey == self.apiService.profileKey else { return }
        self.applyDefaultSites(change.defaultSearchSites)
      }
      .store(in: &cancellables)
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
      applyDefaultSites(SystemViewModel.currentDefaultSearchSites(apiService: apiService))
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
    lastAppliedDefaultSites.formIntersection(availableSiteIds)
    let normalizedSelection = selectedSites.intersection(availableSiteIds)
    let nextSelection = followsDefaultSites ? lastAppliedDefaultSites : normalizedSelection
    updateSelectionInternally(nextSelection)
  }

  private func applyDefaultSites(_ sites: Set<Int>) {
    let nextDefault =
      hasLoadedSites ? sites.intersection(Set(availableSites.map(\.id))) : sites
    lastAppliedDefaultSites = nextDefault
    if followsDefaultSites {
      updateSelectionInternally(nextDefault)
    }
  }

  private func clearLoadedSites() {
    availableSites = []
    lastAppliedDefaultSites = []
    followsDefaultSites = true
    updateSelectionInternally([])
    hasLoadedSites = false
  }

  private func updateSelectionInternally(_ sites: Set<Int>) {
    guard selectedSites != sites else { return }
    isUpdatingSelectionInternally = true
    selectedSites = sites
    isUpdatingSelectionInternally = false
  }
}
