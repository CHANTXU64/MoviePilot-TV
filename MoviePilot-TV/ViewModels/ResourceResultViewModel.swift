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
  private let searchStreamDoneCloseDelay: UInt64 = 1_500_000_000

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

  deinit {
    searchStreamTask?.cancel()
  }

  func cancelSearch() {
    searchStreamTask?.cancel()
    searchStreamTask = nil
    hasSearched = false
    isLoading = false
  }

  func search() async {
    guard !hasSearched else { return }
    hasSearched = true
    isLoading = true

    // 取消可能正在进行的流式搜索
    searchStreamTask?.cancel()
    searchProgressText = "正在搜索..."
    searchProgress = 0.0

    let keyword = self.keyword
    let type = self.type
    let area = self.area
    let title = self.title
    let year = self.year
    let season = self.season
    let sites = self.sites
    let apiService = self.apiService
    let doneCloseDelay = searchStreamDoneCloseDelay

    searchStreamTask = Task { @MainActor [weak self] in
      var accumulatedResults: [Context] = []

      do {
        let stream: AsyncThrowingStream<SearchStreamEvent, Error>

        // 判断是否为媒体搜索（如 "tmdb:1234"）
        if keyword.contains(":") && keyword.prefix(while: { $0.isLetter }).count > 0 {
          stream = apiService.searchMediaStream(
            keyword: keyword,
            type: type,
            area: area,
            title: title,
            year: year,
            season: season,
            sites: sites
          )
        } else {
          stream = apiService.searchTitleStream(keyword: keyword, sites: sites)
        }

        for try await event in stream {
          if Task.isCancelled { break }

          if let text = event.text {
            self?.searchProgressText = text
          }
          if let value = event.value {
            self?.searchProgress = value
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
            // 与 Web v2.13.2 保持一致：给后端搜索结果缓存写入留出收尾时间。
            try? await Task.sleep(nanoseconds: doneCloseDelay)
            break
          }
        }

        if !Task.isCancelled {
          // 获取所有本次搜索的目标站点
          var targetSites: Set<Int> = []
          if let specificSites = sites, !specificSites.isEmpty {
            let siteIds = specificSites.split(separator: ",").compactMap { Int($0) }
            targetSites = Set(siteIds)
          } else {
            do {
              let allSites = try await apiService.fetchIndexerSites()
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
              let retryResults = try await apiService.searchResources(
                keyword: keyword,
                type: type,
                area: area,
                title: title,
                year: year,
                season: season,
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
          guard let self else { return }
          let filteredResults = await self.applyCustomFilter(to: accumulatedResults)
          
          if Task.isCancelled { return }

          self.results = filteredResults
          self.isLoading = false
        }
      } catch {
        print("Search Stream error: \(error)")
        if !Task.isCancelled {
          do {
            var searchResults = try await apiService.searchResources(
              keyword: keyword,
              type: type,
              area: area,
              title: title,
              year: year,
              season: season,
              sites: sites
            )
            if Task.isCancelled { return }

            guard let self else { return }
            searchResults = await self.applyCustomFilter(to: searchResults)
            if Task.isCancelled { return }

            self.results = searchResults
          } catch {
            print("Search fallback error: \(error)")
          }
          if Task.isCancelled { return }

          self?.isLoading = false
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
