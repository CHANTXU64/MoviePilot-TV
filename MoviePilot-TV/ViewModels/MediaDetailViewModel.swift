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

  // 分页加载器
  let recommendPaginator: Paginator<MediaInfo>
  let similarPaginator: Paginator<MediaInfo>
  let actorsPaginator: Paginator<Person>

  // 演职人员信息
  @Published var heroTopActors: [Person] = []
  @Published var heroTopStaff: [GroupedStaff] = []
  @Published var uniqueDirectors: [Person] = []

  // 视图模型与服务
  @Published var siteFilter = SiteFilterViewModel()
  private let apiService = APIService.shared

  init(detail: MediaInfo) {
    self.detail = detail

    // --- Paginator for Recommend ---
    var recommendSeenKeys = Set<String>()
    self.recommendPaginator = Paginator<MediaInfo>(
      fetcher: { @MainActor [apiService, detail] page in
        try await apiService.fetchMediaRecommendations(detail: detail, page: page)
      },
      processor: { @MainActor items, newItems in
        let unique = MediaInfo.deduplicate(newItems, existingKeys: &recommendSeenKeys)
        if !unique.isEmpty {
          items.append(contentsOf: unique)
          return true
        }
        return false
      },
      onReset: { @MainActor in
        recommendSeenKeys.removeAll()
      }
    )

    // --- Paginator for Similar Media ---
    var similarSeenKeys = Set<String>()
    self.similarPaginator = Paginator<MediaInfo>(
      fetcher: { @MainActor [apiService, detail] page in
        try await apiService.fetchMediaSimilar(detail: detail, page: page)
      },
      processor: { @MainActor items, newItems in
        let unique = MediaInfo.deduplicate(newItems, existingKeys: &similarSeenKeys)
        if !unique.isEmpty {
          items.append(contentsOf: unique)
          return true
        }
        return false
      },
      onReset: { @MainActor in
        similarSeenKeys.removeAll()
      }
    )

    // --- Paginator for Actors ---
    self.actorsPaginator = Paginator<Person>(
      fetcher: { @MainActor [apiService, detail] page in
        try await apiService.fetchMediaActors(detail: detail, page: page)
      },
      processor: { @MainActor items, newItems in
        let initialCount = items.count
        items = StaffManager.mergeActors(existing: items, newBatch: newItems)
        return items.count > initialCount
      }
    )

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
    // 准备静态的演职员信息
    uniqueDirectors = StaffManager.processCrew(persons: detail.directors ?? [])
    if heroTopActors.isEmpty {
      // 在加载网络数据前，先用详情页自带的数据填充
      heroTopActors = StaffManager.processActors(persons: Array((detail.actors ?? []).prefix(4)))
      heroTopStaff = StaffManager.getTopGroupedStaff(from: detail.directors ?? [], count: 1)
    }

    // 1. 优先加载演员信息并等待
    await actorsPaginator.refresh()

    // 2. 演员加载完毕，立即更新 Hero 区域
    if heroTopActors.isEmpty {
      updateHeroData(from: actorsPaginator.items)
    }

    // 3. 在后台并发加载推荐和相似内容
    // 创建显式的 @MainActor 任务来强制在主线程上执行
    let recommendTask = Task { @MainActor in
      await recommendPaginator.refresh()
    }
    let similarTask = Task { @MainActor in
      await similarPaginator.refresh()
    }

    // 等待后台任务完成
    _ = await (recommendTask.value, similarTask.value)
  }

  /// 更新主视觉区域的静态数据。
  private func updateHeroData(from actors: [Person]) {
    heroTopActors = Array(actors.prefix(4))
    // 此处的 Staff 数据也应保持同步更新
    heroTopStaff = StaffManager.getTopGroupedStaff(from: detail.directors ?? [], count: 1)
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
