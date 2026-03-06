import Combine
import Foundation
import SwiftUI

struct GroupedStaff: Identifiable {
  let id: String
  let job: String
  let names: [String]
}

/// MediaDetailView 的 ViewModel。
/// 仅负责：演职员、推荐、相似内容的加载。
/// 订阅状态、TMDB 识别、分季信息全部由 MediaPreloadTask 提供。
@MainActor
class MediaDetailViewModel: ObservableObject {
  @Published var detail: MediaInfo

  // 界面背景稳定性控制
  @Published var backgroundUrl: URL?
  @Published var isUsingPosterAsBackdrop = false

  // 推荐内容
  @Published var recommendations: [MediaInfo] = []
  private var recommendPage = 1
  @Published var hasMoreRecommendations = true
  @Published var isRecommendLoading = false

  // 相似媒体
  @Published var similarMedia: [MediaInfo] = []
  private var similarPage = 1
  @Published var hasMoreSimilar = true
  @Published var isSimilarLoading = false

  // 站点筛选器 ViewModel
  @Published var siteFilter = SiteFilterViewModel()

  // 演职人员信息
  @Published var heroTopActors: [Person] = []
  @Published var heroTopStaff: [GroupedStaff] = []
  @Published var uniqueDirectors: [Person] = []
  @Published var uniqueActors: [Person] = []

  private var creditsPage = 1
  @Published var hasMoreCredits = true
  @Published var isCreditsLoading = false

  private let apiService = APIService.shared
  private var recommendSeenKeys = Set<String>()
  private var similarSeenKeys = Set<String>()

  init(detail: MediaInfo) {
    self.detail = detail
    updateBackground()
  }

  /// 当 fullDetail 加载完成后，更新详情数据及背景图。
  /// 由 MediaDetailContainerContent 在 fullDetail 就绪时调用。
  func updateDetail(_ newDetail: MediaInfo) {
    // 强制清除旧背景，防止导航时短暂闪烁旧图
    if detail.id != newDetail.id {
      backgroundUrl = nil
    }

    self.detail = newDetail
    updateBackground()
  }

  /// 根据媒体的海报或背景图更新详情页背景
  func updateBackground() {
    let backdrop = apiService.getBackdropImageUrl(detail)
    let poster = apiService.getPosterImageUrl(detail)

    let targetUrl: URL?
    let targetIsPoster: Bool

    // 优先级：背景大图 > 海报图
    if let backdrop = backdrop {
      targetUrl = backdrop
      targetIsPoster = false
    } else if let poster = poster {
      targetUrl = poster
      targetIsPoster = true
    } else {
      targetUrl = nil
      targetIsPoster = false
    }

    // 核心保护逻辑：只有当背景 URL 真正改变时才触发 @Published 更新。
    // 这能有效防止因为值相同但对象不同导致的 UI 重新闪烁刷新。
    if self.backgroundUrl != targetUrl || self.isUsingPosterAsBackdrop != targetIsPoster {
      withAnimation(.easeInOut(duration: 0.8)) {
        if self.backgroundUrl != targetUrl {
          self.backgroundUrl = targetUrl
        }
        if self.isUsingPosterAsBackdrop != targetIsPoster {
          self.isUsingPosterAsBackdrop = targetIsPoster
        }
      }
    }
  }

  /// 加载辅助数据：演职员、推荐、相似内容（三个请求互不依赖，并发执行）
  /// 注意：fetchMediaDetail / 订阅 / TMDB 识别 / 分季信息全部由 MediaPreloadTask 负责，此处不再处理。
  func loadSupplementaryData() async {
    async let initialActors: Void = loadInitialActors()
    async let recommendations: Void = loadRecommendations(reset: true)
    async let similar: Void = loadSimilar(reset: true)
    _ = await (initialActors, recommendations, similar)
  }

  /// 仅在首次进入详情页时调用，负责设置演职员的初始状态。
  func loadInitialActors() async {
    // 重置演员和分页状态
    creditsPage = 1
    uniqueActors = []  // 保证列表从零开始，完全由 Fetch 获取
    hasMoreCredits = true
    isCreditsLoading = false

    // 从媒体详情中加载初始的职员（如导演）
    uniqueDirectors = StaffManager.processCrew(persons: detail.directors ?? [])

    // 主视觉区域数据直接使用 detail 中的信息
    if heroTopActors.isEmpty {
      heroTopActors = StaffManager.processActors(persons: Array((detail.actors ?? []).prefix(4)))
      heroTopStaff = StaffManager.getTopGroupedStaff(from: detail.directors ?? [], count: 1)
    }

    // 尝试加载第一页，uniqueActors 将完全由网络请求填充
    await loadMoreActors()
  }

  /// 加载更多演员（支持分页）
  func loadMoreActors() async {
    guard hasMoreCredits, !isCreditsLoading else { return }
    isCreditsLoading = true
    defer { isCreditsLoading = false }

    let maxAttempts = 2
    var attempts = 0
    var hasNewContent = false

    while attempts < maxAttempts, hasMoreCredits, !hasNewContent {
      attempts += 1
      let initialActorCount = uniqueActors.count

      do {
        let newActors = try await apiService.fetchMediaActors(detail: detail, page: creditsPage)

        if newActors.isEmpty {
          hasMoreCredits = false
          break
        }

        uniqueActors = StaffManager.mergeActors(existing: uniqueActors, newBatch: newActors)

        if uniqueActors.count > initialActorCount {
          hasNewContent = true
        }

        // 如果是第一页加载完，需要更新 Hero 数据
        if creditsPage == 1 && heroTopActors.isEmpty {
          updateHeroData()
        }

        creditsPage += 1

      } catch {
        print("加载演职员出错: \(error)")
        hasMoreCredits = false
        break
      }
    }

    if !hasNewContent {
      hasMoreCredits = false
    }
  }

  /// 更新主视觉区域的静态数据。仅调用一次。
  private func updateHeroData() {
    heroTopActors = Array(uniqueActors.prefix(4))
    heroTopStaff = StaffManager.getTopGroupedStaff(from: detail.directors ?? [], count: 1)
  }

  /// 加载推荐内容（带“二次确认”逻辑防止因重复数据导致无限加载）
  func loadRecommendations(reset: Bool = false) async {
    if reset {
      recommendPage = 1
      recommendations = []
      hasMoreRecommendations = true
      isRecommendLoading = false
      recommendSeenKeys.removeAll()
    }
    guard hasMoreRecommendations, !isRecommendLoading else { return }
    isRecommendLoading = true
    defer { isRecommendLoading = false }

    let maxAttempts = 2
    var attempts = 0
    var hasNewContent = false

    while attempts < maxAttempts, hasMoreRecommendations, !hasNewContent {
      attempts += 1
      let initialCount = recommendations.count

      do {
        let newItems = try await apiService.fetchMediaRecommendations(
          detail: detail, page: recommendPage)

        if newItems.isEmpty {
          hasMoreRecommendations = false
          break
        }

        let unique = MediaInfo.deduplicate(newItems, existingKeys: &recommendSeenKeys)
        if !unique.isEmpty {
          recommendations.append(contentsOf: unique)
        }

        recommendPage += 1

        if recommendations.count > initialCount {
          hasNewContent = true
        }

      } catch {
        print("加载推荐出错: \(error)")
        hasMoreRecommendations = false
        break
      }
    }

    if !hasNewContent {
      hasMoreRecommendations = false
    }
  }

  /// 加载相似内容（带“二次确认”逻辑防止因重复数据导致无限加载）
  func loadSimilar(reset: Bool = false) async {
    if reset {
      similarPage = 1
      similarMedia = []
      hasMoreSimilar = true
      isSimilarLoading = false
      similarSeenKeys.removeAll()
    }

    guard hasMoreSimilar, !isSimilarLoading else { return }
    isSimilarLoading = true
    defer { isSimilarLoading = false }

    let maxAttempts = 2
    var attempts = 0
    var hasNewContent = false

    while attempts < maxAttempts, hasMoreSimilar, !hasNewContent {
      attempts += 1
      let initialCount = similarMedia.count

      do {
        let newItems = try await apiService.fetchMediaSimilar(detail: detail, page: similarPage)

        if newItems.isEmpty {
          hasMoreSimilar = false
          break
        }

        let unique = MediaInfo.deduplicate(newItems, existingKeys: &similarSeenKeys)
        if !unique.isEmpty {
          similarMedia.append(contentsOf: unique)
        }
        similarPage += 1

        if similarMedia.count > initialCount {
          hasNewContent = true
        }
      } catch {
        print("加载相似内容出错: \(error)")
        hasMoreSimilar = false
        break
      }
    }
    if !hasNewContent {
      hasMoreSimilar = false
    }
  }

  // MARK: - 订阅操作（业务逻辑，由 View 层调用）

  /// 订阅状态（从 preloadTask 读取）
  var isSubscribed: Bool {
    preloadTask?.isSubscribed ?? false
  }

  /// 取消订阅状态标记
  @Published var isUnsubscribing = false

  /// 预加载任务引用（由 View 注入，订阅操作需要读取 tmdbId 和回写 isSubscribed）
  var preloadTask: MediaPreloadTask?

  /// 构建订阅请求对象（用于弹出 SubscribeSheet）
  func buildSubscribeRequest(season: Int? = nil) -> Subscribe {
    Subscribe(
      id: nil,
      name: detail.title ?? "",
      year: detail.year,
      type: detail.type ?? "电影",
      season: season,
      poster: detail.poster_path,
      state: "N",
      // 优先使用预加载识别到的 TMDB ID（豆瓣/Bangumi 来源可能在预加载阶段才拿到）
      tmdbid: preloadTask?.tmdbId ?? detail.tmdb_id,
      doubanid: detail.douban_id,
      bangumiid: detail.bangumi_id
    )
  }

  /// 取消当前媒体的订阅
  func cancelSubscription() async {
    isUnsubscribing = true
    defer { isUnsubscribing = false }

    let _ = try? await apiService.deleteSubscription(media: detail, season: detail.season)

    // 刷新所有订阅状态（包括全局和分季）
    await refreshSubscriptionStatus()
  }

  /// 刷新订阅状态：同时更新全局订阅和分季订阅（preloadTask 是唯一数据源）
  func refreshSubscriptionStatus() async {

    // 刷新全局订阅状态
    if detail.canDirectlySubscribe {
      do {
        preloadTask?.isSubscribed = try await apiService.checkSubscription(media: detail)
      } catch {
        print("[MediaDetailViewModel] 刷新订阅状态失败: \(error)")
      }
    }

    // 刷新分季订阅状态
    if let seasonVM = preloadTask?.seasonViewModel {
      await seasonVM.checkSubscriptionStatus()
    }
  }
}
