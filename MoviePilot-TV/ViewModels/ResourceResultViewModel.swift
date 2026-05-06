import Combine
import Foundation
import SwiftUI

@MainActor
class ResourceResultViewModel: ObservableObject {
  @Published var results: [Context] = []
  @Published var isLoading = false
  private var hasSearched = false

  let keyword: String
  let type: String?
  let area: String?
  let title: String?
  let year: String?
  let season: Int?
  let sites: String?

  @Published var searchProgressText: String = ""
  @Published var searchProgress: Double = 0.0

  private var searchStreamTask: Task<Void, Never>?

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

    // 取消可能正在进行的流式搜索
    searchStreamTask?.cancel()
    searchProgressText = "正在搜索..."
    searchProgress = 0.0

    searchStreamTask = Task { @MainActor in
      var accumulatedResults: [Context] = []

      do {
        let stream: AsyncThrowingStream<SearchStreamEvent, Error>

        // 判断是否为媒体搜索（如 "tmdb:1234"）
        if keyword.contains(":") && keyword.prefix(while: { $0.isLetter }).count > 0 {
          stream = APIService.shared.searchMediaStream(
            keyword: keyword,
            type: type,
            area: area,
            title: title,
            year: year,
            season: season,
            sites: sites
          )
        } else {
          stream = APIService.shared.searchTitleStream(keyword: keyword, sites: sites)
        }

        for try await event in stream {
          if Task.isCancelled { break }

          if let text = event.text {
            self.searchProgressText = text
          }
          if let value = event.value {
            self.searchProgress = value
          }

          if let items = event.items {
            if event.type == "append" {
              accumulatedResults.append(contentsOf: items)
            } else if event.type == "replace" || event.type == "done" {
              accumulatedResults = items
            }
          }

          if event.type == "error" {
            print("Search Stream Error: \(event.message ?? "未知错误")")
            break
          }

          if event.type == "done" {
            break
          }
        }

        if !Task.isCancelled {
          // 获取所有本次搜索的目标站点
          var targetSites: Set<Int> = []
          if let specificSites = self.sites, !specificSites.isEmpty {
            let siteIds = specificSites.split(separator: ",").compactMap { Int($0) }
            targetSites = Set(siteIds)
          } else {
            do {
              let allSites = try await self.apiService.fetchIndexerSites()
              if Task.isCancelled { return }
              targetSites = Set(allSites)
            } catch {
              print("Fetch indexer sites error: \(error)")
            }
          }

          // 收集实际返回了数据的站点
          let respondedSites = Set(accumulatedResults.compactMap { $0.torrent_info?.site })
          
          // 找出没有返回数据的站点
          let missingSites = targetSites.subtracting(respondedSites)

          // 自动静默重试机制：对那些没有返回数据的站点在后台统一发起一次重试
          if !missingSites.isEmpty && !Task.isCancelled {
            let missingSitesString = missingSites.map { String($0) }.joined(separator: ",")
            do {
              let retryResults = try await self.apiService.searchResources(
                keyword: self.keyword,
                type: self.type,
                area: self.area,
                title: self.title,
                year: self.year,
                season: self.season,
                sites: missingSitesString
              )
              if Task.isCancelled { return }
              // 追加到原结果后面
              accumulatedResults.append(contentsOf: retryResults)
            } catch {
              print("Search missing sites retry error: \(error)")
            }
          }

          if Task.isCancelled { return }

          // 应用自定义过滤规则
          let filteredResults = await self.applyCustomFilter(to: accumulatedResults)
          
          if Task.isCancelled { return }

          self.results = filteredResults
          self.isLoading = false
        }
      } catch {
        print("Search Stream error: \(error)")
        if !Task.isCancelled {
          do {
            var searchResults = try await self.apiService.searchResources(
              keyword: self.keyword,
              type: self.type,
              area: self.area,
              title: self.title,
              year: self.year,
              season: self.season,
              sites: self.sites
            )
            searchResults = await self.applyCustomFilter(to: searchResults)
            self.results = searchResults
          } catch {
            print("Search fallback error: \(error)")
          }
          self.isLoading = false
        }
      }
    }
  }

  /// 应用自定义过滤规则
  private func applyCustomFilter(to contexts: [Context]) async -> [Context] {
    do {
      return try await CustomFilterService.applyHardAndSoftFilter(
        to: contexts, using: apiService, caller: "ResourceResultVM")
    } catch {
      print("❌ [ResourceResultVM] 加载过滤规则失败: \(error)")
      return contexts
    }
  }
}
