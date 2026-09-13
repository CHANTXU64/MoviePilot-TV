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
  var hasLoadedSites: Bool = false
  /// 是否拿到了权威搜索站点域（/site/）。降级为订阅域（/site/rss）时不能用来裁剪已保存选择（F-210）。
  var loadedSitesAuthoritative: Bool = false

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
      let (sites, authoritative) = try await apiService.fetchSearchableSites()
      self.availableSites = sites
      self.loadedSitesAuthoritative = authoritative
      hasLoadedSites = true
      applyDefaultSites(SystemViewModel.currentDefaultSearchSites(apiService: apiService))
      normalizeSelectedSites()
    } catch is CancellationError {
      if !apiService.canAccess(.search) {
        clearLoadedSites()
      }
      return
    } catch {
      Logger.error("Failed to load sites: \(error)")
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

  /// 站点过滤参数的请求编码：有具体选择时发选中的 ID 串；
  /// 选「全部站点」（空选择）时显式发送全部启用站点 ID，避免后端把空/nil 回退成
  /// 「搜索站点范围」默认子集而漏搜（F-209）。只有权威站点列表可以安全展开；
  /// 未加载、降级订阅域或启用站点为空时保留 nil 的后端默认语义。
  var sitesString: String? {
    if selectedSites.isEmpty {
      guard hasLoadedSites, loadedSitesAuthoritative else { return nil }
      let allActiveIds = availableSites
        .filter { $0.is_active?.value == true }
        .map(\.id)
        .sorted()
      guard !allActiveIds.isEmpty else { return nil }
      return allActiveIds.map(String.init).joined(separator: ",")
    }
    return selectedSites.sorted().map { String($0) }.joined(separator: ",")
  }

  func normalizeSelectedSites() {
    guard hasLoadedSites, loadedSitesAuthoritative else { return }

    let availableSiteIds = Set(availableSites.map(\.id))
    lastAppliedDefaultSites.formIntersection(availableSiteIds)
    let normalizedSelection = selectedSites.intersection(availableSiteIds)
    let nextSelection = followsDefaultSites ? lastAppliedDefaultSites : normalizedSelection
    updateSelectionInternally(nextSelection)
  }

  private func applyDefaultSites(_ sites: Set<Int>) {
    let nextDefault =
      hasLoadedSites && loadedSitesAuthoritative
        ? sites.intersection(Set(availableSites.map(\.id)))
        : sites
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
    loadedSitesAuthoritative = false
  }

  private func updateSelectionInternally(_ sites: Set<Int>) {
    guard selectedSites != sites else { return }
    isUpdatingSelectionInternally = true
    selectedSites = sites
    isUpdatingSelectionInternally = false
  }
}
