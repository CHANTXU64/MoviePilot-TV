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
  @Published var errorMessage: String?

  private var searchStreamTask: Task<Void, Never>?
  private var searchGeneration = 0
  private let searchStreamDoneCloseDelay: UInt64 = 1_500_000_000

  private let apiService: APIService

  init(
    keyword: String, type: String? = nil, area: String? = nil, title: String? = nil,
    year: String? = nil, season: Int? = nil, sites: String? = nil,
    apiService: APIService = .shared
  ) {
    self.keyword = keyword
    self.type = type
    self.area = area
    self.title = title
    self.year = year
    self.season = season
    self.sites = sites
    self.apiService = apiService
  }

  deinit {
    searchStreamTask?.cancel()
  }

  func cancelSearch() {
    searchGeneration += 1
    searchStreamTask?.cancel()
    searchStreamTask = nil
    hasSearched = false
    isLoading = false
  }

  func cancelInFlightSearch() {
    let wasInFlight = isLoading
    searchGeneration += 1
    searchStreamTask?.cancel()
    searchStreamTask = nil
    isLoading = false
    if wasInFlight {
      hasSearched = false
    }
  }

  func search() async {
    guard apiService.canAccess(.search) else { return }
    guard !hasSearched else { return }
    hasSearched = true
    isLoading = true
    searchGeneration += 1
    let currentSearchGeneration = searchGeneration

    // 取消可能正在进行的流式搜索
    searchStreamTask?.cancel()
    searchProgressText = "正在搜索..."
    searchProgress = 0.0
    errorMessage = nil

    let keyword = self.keyword
    let type = self.type
    let area = self.area
    let title = self.title
    let year = self.year
    let season = self.season
    let sites = self.sites
    let apiService = self.apiService
    let doneCloseDelay = searchStreamDoneCloseDelay
    let sessionSnapshot = apiService.sessionSnapshot()

    searchStreamTask = Task { @MainActor [weak self] in
      var accumulatedResults: [Context] = []
      var finalResultApplied = false
      // 只有收到端点认可的 done 才允许 missingSites 补偿与发布；业务 error 与无终止 EOF 均不发布。
      var receivedDone = false
      defer {
        self?.finishSearchIfCurrent(
          generation: currentSearchGeneration,
          sessionSnapshot: sessionSnapshot
        )
      }

      let canContinue: @MainActor () -> Bool = { [weak self] in
        guard let self else { return false }
        return self.searchGeneration == currentSearchGeneration
          && apiService.isSessionUnchanged(from: sessionSnapshot)
          && apiService.canAccess(.search)
          && !Task.isCancelled
      }

      do {
        guard canContinue() else { return }
        let stream: AsyncThrowingStream<SearchStreamEvent, Error>

        // 判断是否为媒体搜索（如 "tmdb:1234"）
        if isResourceMediaSearchKeyword(keyword) {
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
          guard canContinue() else { return }

          if let text = event.text_i18n ?? event.text {
            self?.searchProgressText = text
          }
          if let value = event.value {
            self?.searchProgress = value
          }

          event.applyResourceItems(
            to: &accumulatedResults,
            finalResultApplied: &finalResultApplied
          )

          if event.type == "error" {
            self?.errorMessage = event.localizedMessage ?? "未找到相关资源"
            // 整次搜索失败：不发布已积累的部分结果，也不执行站点补偿。
            return
          }

          if event.type == "done" {
            receivedDone = true
            // 与 Web v2.13.2 保持一致：给后端搜索结果缓存写入留出收尾时间。
            try? await Task.sleep(nanoseconds: doneCloseDelay)
            guard canContinue() else { return }
            break
          }
        }

        if canContinue() {
          // 只有明确成功终止（done）才允许 missingSites 补偿与结果发布。
          guard receivedDone else {
            self?.errorMessage = "搜索连接中断，请重试。"
            return
          }
          // 获取所有本次搜索的目标站点
          var targetSites: Set<Int> = []
          if let specificSites = sites, !specificSites.isEmpty {
            let siteIds = specificSites.split(separator: ",").compactMap { Int($0) }
            targetSites = Set(siteIds)
          } else {
            do {
              let allSites = try await apiService.fetchIndexerSites()
              guard canContinue() else { return }
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
              guard canContinue() else { return }
              // 追加到原结果后面
              accumulatedResults.append(contentsOf: retryResults)
            } catch {
              print("Search missing sites retry error: \(error)")
            }
          }

          guard canContinue() else { return }

          // 应用自定义过滤规则（规则内容非法时显式提示；拉取规则网络失败时放行不过滤）
          guard let self else { return }
          let filteredResults: [Context]
          do {
            filteredResults = try await self.applyCustomFilter(to: accumulatedResults)
          } catch let error as CustomFilterService.FilterError {
            guard canContinue() else { return }
            self.errorMessage = error.localizedDescription
            return
          } catch {
            print("❌ [ResourceResultVM] 加载过滤规则失败，放行不过滤: \(error)")
            filteredResults = accumulatedResults
          }
          
          guard canContinue() else { return }

          self.results = filteredResults
        }
      } catch {
        print("Search Stream error: \(error)")
        if canContinue() {
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
            guard canContinue() else { return }

            guard let self else { return }
            do {
              searchResults = try await self.applyCustomFilter(to: searchResults)
            } catch let error as CustomFilterService.FilterError {
              self.errorMessage = error.localizedDescription
              return
            } catch {
              print("❌ [ResourceResultVM] 加载过滤规则失败，放行不过滤: \(error)")
            }
            guard canContinue() else { return }

            self.results = searchResults
          } catch {
            print("Search fallback error: \(error)")
            guard canContinue() else { return }
            self?.errorMessage = error.localizedDescription
          }
          guard canContinue() else { return }
        }
      }
    }
  }

  private func finishSearchIfCurrent(
    generation: Int,
    sessionSnapshot: APIServiceSessionSnapshot
  ) {
    guard searchGeneration == generation else { return }
    isLoading = false
    searchStreamTask = nil
    if Task.isCancelled
      || !apiService.isSessionUnchanged(from: sessionSnapshot)
      || !apiService.canAccess(.search)
    {
      hasSearched = false
    }
  }

  /// 应用自定义过滤规则
  private func applyCustomFilter(to contexts: [Context]) async throws -> [Context] {
    try await CustomFilterService.applyHardAndSoftFilter(
      to: contexts, using: apiService, caller: "ResourceResultVM")
  }
}
