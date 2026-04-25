import Combine
import Foundation
import SwiftUI

@MainActor
class ResourceResultViewModel: ObservableObject {
  @Published var results: [Context] = []
  @Published var isLoading = true
  private var hasSearched = false

  let keyword: String
  let type: String?
  let area: String?
  let title: String?
  let year: String?
  let season: Int?
  let sites: String?

  private let apiService = APIService.shared

  init(
    keyword: String, type: String? = nil, area: String? = nil, title: String? = nil,
    year: String? = nil, season: Int? = nil, sites: String? = nil
  ) {
    self.keyword = keyword
    self.type = type
    self.area = area
    self.title = title
    self.year = year
    self.season = season
    self.sites = sites
  }

  func search() async {
    guard !hasSearched else { return }
    hasSearched = true
    isLoading = true
    do {
      var searchResults = try await apiService.searchResources(
        keyword: keyword, type: type, area: area, title: title, year: year, season: season,
        sites: sites)

      // 应用自定义过滤规则
      searchResults = await applyCustomFilter(to: searchResults)

      results = searchResults
    } catch {
      print("Search error: \(error)")
    }
    isLoading = false
  }

  /// 应用自定义过滤规则
  private func applyCustomFilter(to contexts: [Context]) async -> [Context] {
    guard let ruleId = SystemViewModel.currentSelectedFilterRuleId() else {
      return contexts
    }

    // 从 API 获取规则详情
    do {
      let rules = try await apiService.fetchCustomFilterRules()
      guard let rule = rules.first(where: { $0.id == ruleId }) else {
        print("⚠️ [ResourceResultVM] 选中的规则 \(ruleId) 不存在")
        return contexts
      }

      let originalCount = contexts.count
      let filtered = CustomFilterService.filter(contexts: contexts, with: rule)
      print("🔍 [ResourceResultVM] 应用过滤规则「\(rule.name)」: \(originalCount) → \(filtered.count) 个资源")
      return filtered
    } catch {
      print("❌ [ResourceResultVM] 加载过滤规则失败: \(error)")
      return contexts
    }
  }
}
