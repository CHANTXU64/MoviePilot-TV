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

  /// 第二页首行数据是否已就绪。
  /// 用于控制 Loading 遮罩的显隐——必须等首行数据加载完才能移除遮罩，
  /// 否则首行 Card 顶部露出在第一页底部时，非首行先加载会导致闪烁。
  @Published var isFirstRowReady = false

  // 视图模型与服务
  @Published var siteFilter = SiteFilterViewModel()
  private let apiService = APIService.shared

  /// 可变引用盒子：让 Paginator 闭包始终读取最新的 detail 值。
  /// init 时可能传入 partial data，applyFullDetail 会更新 box 内的值，
  /// 闭包通过 capture 这个 box（引用类型）自动读到 applyFullDetail 后的 detail。
  private final class DetailBox {
    var value: MediaInfo
    init(_ v: MediaInfo) { value = v }
  }
  private let detailBox: DetailBox
  private var cancellables = Set<AnyCancellable>()

  init(detail: MediaInfo) {
    self.detail = detail
    let box = DetailBox(detail)
    self.detailBox = box

    // --- Paginator for Recommend ---
    // ⚠️ 闭包 capture box（引用类型），而非 capture init 时的 detail 值。
    // applyFullDetail 会更新 box.value，让闭包读取完整数据。
    var recommendSeenKeys = Set<String>()
    self.recommendPaginator = Paginator<MediaInfo>(
      threshold: 10,
      fetcher: { @MainActor [apiService, box] page in
        try await apiService.fetchMediaRecommendations(detail: box.value, page: page)
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
      threshold: 10,
      fetcher: { @MainActor [apiService, box] page in
        try await apiService.fetchMediaSimilar(detail: box.value, page: page)
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
      threshold: 10,
      fetcher: { @MainActor [apiService, box] page in
        try await apiService.fetchMediaActors(detail: box.value, page: page)
      },
      processor: { @MainActor items, newItems in
        let initialCount = items.count
        items = StaffManager.mergeActors(existing: items, newBatch: newItems)
        return items.count > initialCount
      }
    )

    // --- Forward Paginator Updates ---
    self.recommendPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    self.similarPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    self.actorsPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  /// 应用完整的媒体详情数据并加载辅助内容。
  /// 在 fullDetail 加载完成后调用，负责：
  /// 1. 设置 detail、更新背景图、派生演职员等所有依赖属性（同步，立即生效）
  /// 2. 自动启动演职员、推荐、相似内容的网络加载（异步，不阻塞调用方返回）
  /// 3. 在第二页首行数据就绪后设置 isFirstRowReady，控制 Loading 遮罩显隐
  func applyFullDetail(_ fullDetail: MediaInfo) {
    self.detail = fullDetail
    detailBox.value = fullDetail  // 同步更新引用盒子，让 Paginator 闭包读取最新数据
    setBackground()

    // 从完整详情中派生演职员数据，作为 API 加载前的快速初始显示
    uniqueDirectors = StaffManager.processCrew(persons: fullDetail.directors ?? [])
    heroTopStaff = StaffManager.getTopGroupedStaff(from: fullDetail.directors ?? [], count: 1)
    heroTopActors = StaffManager.processActors(
      persons: Array((fullDetail.actors ?? []).prefix(4)))

    // ── 判断第二页首行类型 ──
    // 电视剧首行固定是 season（由 preloadTask 异步加载，在 View 层通过 onChange 监听）
    let isSeasonFirst = fullDetail.type == "电视剧" && fullDetail.tmdb_id != nil

    if isSeasonFirst {
      // season 由 preloadTask 管理，检查数据是否已实际加载完毕
      if preloadTask?.isSeasonDataLoaded == true {
        isFirstRowReady = true
      }
      // 否则：View 层通过 onChange(of: preloadTask.isSeasonDataLoaded) 设置
    }

    // 异步加载网络数据（不阻塞调用方返回，数据到达后渐进显示）
    Task {
      // 1. 优先加载演员信息
      await actorsPaginator.refresh()

      // 2. 演员加载完毕，用网络数据更新 Hero 区域
      if heroTopActors.isEmpty {
        heroTopActors = Array(actorsPaginator.items.prefix(4))
      }

      // ── 非电视剧：演员加载完后判断首行就绪 ──
      // 加载顺序：directors(同步) → actors(此处) → recommend+similar(下方)
      // 视图渲染顺序：season → actors → directors → recommend → similar
      // 此时 actors 和 directors 的数据状态已确定
      if !isSeasonFirst {
        if !actorsPaginator.items.isEmpty || !uniqueDirectors.isEmpty {
          // 首行是 actors 或 directors，数据已就绪
          isFirstRowReady = true
        }
        // 否则需要等 recommend/similar 加载完
      }

      // 3. 并发加载推荐和相似内容
      let recommendTask = Task { @MainActor in
        await recommendPaginator.refresh()
      }
      let similarTask = Task { @MainActor in
        await similarPaginator.refresh()
      }
      _ = await (recommendTask.value, similarTask.value)

      // ── 所有数据加载完毕，兜底设置 ──
      // 仅对非电视剧（首行不是 season）生效：此时 actors/directors/recommend/similar 都已确定。
      // 电视剧的 isFirstRowReady 完全由 isSeasonDataLoaded 控制（通过 View 层 onChange），
      // 不在此处兜底，防止分季 API 比其他 API 慢时提前移除 Loading 遮罩。
      if !isSeasonFirst && !isFirstRowReady {
        isFirstRowReady = true
      }
    }
  }

  /// 根据媒体的海报或背景图更新详情页背景
  private func setBackground() {
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
