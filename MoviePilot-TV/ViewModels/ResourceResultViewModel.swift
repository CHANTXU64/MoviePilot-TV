import Combine
import Foundation
import SwiftUI

@MainActor
class ResourceResultViewModel: ObservableObject {
  @Published var results: [Context] = []
  @Published var isLoading = true

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
    isLoading = true
    do {
      results = try await apiService.searchResources(
        keyword: keyword, type: type, area: area, title: title, year: year, season: season,
        sites: sites)
    } catch {
      print("Search error: \(error)")
    }
    isLoading = false
  }
}
