import Combine
import Foundation

@MainActor
class SiteFilterViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  enum Preference {
    case resource
    case subtitle
  }

  /// nil 跟随各自的默认设置；空集合显式选择全部站点；非空集合由两种搜索共用。
  @Published var selectedSites: Set<Int>? = nil
  @Published var availableSites: [Site] = []
  @Published private(set) var isLoadingSites = false
  @Published private(set) var siteLoadError: String?
  var hasLoadedSites = false
  /// 降级为订阅域（/site/rss）时不能用它裁剪搜索站点选择。
  var loadedSitesAuthoritative = false

  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
  }

  func loadSites() async {
    guard apiService.canAccess(.search) else {
      clearLoadedSites()
      return
    }
    guard !isLoadingSites else { return }
    isLoadingSites = true
    siteLoadError = nil
    defer { isLoadingSites = false }
    do {
      let (sites, authoritative) = try await apiService.fetchSearchableSites()
      availableSites = sites
      loadedSitesAuthoritative = authoritative
      hasLoadedSites = true
      normalizeSelectedSites()
    } catch is CancellationError {
      if !apiService.canAccess(.search) {
        clearLoadedSites()
      }
    } catch {
      siteLoadError = "站点加载失败，请重试。"
      Logger.error("Failed to load sites: \(error)")
    }
  }

  var siteButtonLabel: String {
    guard let selectedSites else { return "默认" }
    if selectedSites.isEmpty {
      return "全部站点"
    } else if selectedSites.count == 1 {
      return availableSites.first { selectedSites.contains($0.id) }?.name ?? "1 个站点"
    } else {
      return "\(selectedSites.count) 个站点"
    }
  }

  var sitesString: String? { sitesString(for: .resource) }

  /// 只在请求时解析默认值，不让焦点或搜索类型改变页面上的共享选择。
  func sitesString(for preference: Preference) -> String? {
    let sites: Set<Int>
    if let selectedSites {
      sites = selectedSites
    } else {
      let defaults = switch preference {
      case .resource: SystemViewModel.currentDefaultSearchSites(apiService: apiService)
      case .subtitle: SystemViewModel.currentDefaultSubtitleSearchSites(apiService: apiService)
      }
      sites = clipped(defaults)
    }
    return siteScope.query(for: sites)
  }

  private var siteScope: SearchSiteScope {
    SearchSiteScope(sites: availableSites, authoritative: hasLoadedSites && loadedSitesAuthoritative)
  }

  func normalizeSelectedSites() {
    guard let selectedSites else { return }
    let normalized = clipped(selectedSites)
    if normalized != selectedSites {
      self.selectedSites = normalized
    }
  }

  private func clipped(_ sites: Set<Int>) -> Set<Int> {
    siteScope.normalized(sites)
  }

  private func clearLoadedSites() {
    availableSites = []
    selectedSites = nil
    hasLoadedSites = false
    loadedSitesAuthoritative = false
    siteLoadError = nil
  }
}


/// 页面选择与无筛选控件的快捷入口使用同一站点域规则。
struct SearchSiteScope {
  let sites: [Site]
  let authoritative: Bool

  func normalized(_ selection: Set<Int>) -> Set<Int> {
    authoritative ? selection.intersection(Set(sites.map(\.id))) : selection
  }

  func query(for selection: Set<Int>) -> String? {
    if !selection.isEmpty { return selection.sorted().map(String.init).joined(separator: ",") }
    guard authoritative else { return nil }
    let activeIDs = sites.filter { $0.is_active?.value == true }.map(\.id).sorted()
    return activeIDs.isEmpty ? nil : activeIDs.map(String.init).joined(separator: ",")
  }
}
