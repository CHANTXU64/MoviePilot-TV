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

  @Published private(set) var isInLibrary = false

  /// 第二页首行数据是否已就绪。
  /// 用于控制 Loading 遮罩的显隐——必须等首行数据加载完才能移除遮罩，
  /// 否则首行 Card 顶部露出在第一页底部时，非首行先加载会导致闪烁。
  @Published var isFirstRowReady = false
  @Published private(set) var isRelatedContentSnapshotComplete = false

  // 视图模型与服务
  @Published var siteFilter: SiteFilterViewModel
  private let apiService: APIService

  /// 可变引用盒子：让 Paginator 闭包始终读取最新的 detail 值。
  /// init 时可能传入 partial data，applyFullDetail 会更新 box 内的值，
  /// 闭包通过 capture 这个 box（引用类型）自动读到 applyFullDetail 后的 detail。
  private final class DetailBox {
    var value: MediaInfo
    init(_ v: MediaInfo) { value = v }
  }
  private let detailBox: DetailBox
  private var cancellables = Set<AnyCancellable>()
  private var mediaServerExistsTask: Task<Void, Never>?
  private var relatedContentTask: Task<Void, Never>?
  private var relatedContentChildTasks: [Task<Void, Never>] = []

  init(detail: MediaInfo, apiService: APIService = .shared) {
    self.detail = detail
    self.apiService = apiService
    self.siteFilter = SiteFilterViewModel(apiService: apiService)
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
      imageURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
      },
      imagePrefetchProcessor: MediaCard.posterProcessor(for: MediaCard.defaultPosterSize),
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
      imageURLsProvider: { @MainActor item in
        [item.imageURLs.poster].compactMap { $0 }
      },
      imagePrefetchProcessor: MediaCard.posterProcessor(for: MediaCard.defaultPosterSize),
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
      },
      imageURLsProvider: { item in
        [item.imageURLs.profile].compactMap(\.self)
      },
      imagePrefetchProcessor: PersonCard.imageProcessor()
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

  private var hasAppliedFullDetail = false

  /// 应用完整的媒体详情数据并加载辅助内容。
  /// 在 fullDetail 加载完成后调用，负责：
  /// 1. 设置 detail、更新背景图、派生演职员等所有依赖属性（同步，立即生效）
  /// 2. 自动启动演职员、推荐、相似内容的网络加载（异步，不阻塞调用方返回）
  /// 3. 在第二页首行数据就绪后设置 isFirstRowReady，控制 Loading 遮罩显隐
  func applyFullDetail(_ fullDetail: MediaInfo) {
    self.detail = fullDetail
    detailBox.value = fullDetail  // 同步更新引用盒子，让 Paginator 闭包读取最新数据
    setBackground()

    guard !hasAppliedFullDetail else { return }
    hasAppliedFullDetail = true

    // 从完整详情中派生演职员数据，作为 API 加载前的快速初始显示
    uniqueDirectors = StaffManager.processCrew(persons: fullDetail.directors ?? [])
    heroTopStaff = StaffManager.getTopGroupedStaff(from: fullDetail.directors ?? [], count: 1)
    heroTopActors = StaffManager.processActors(
      persons: Array((fullDetail.actors ?? []).prefix(4)))

    mediaServerExistsTask = Task { [weak self] in
      await self?.loadMediaServerExists()
      self?.mediaServerExistsTask = nil
    }

    // ── 判断第二页首行类型 ──
    // 电视剧首行固定是 season（由 preloadTask 异步加载，在 View 层通过 onChange 监听）
    let isSeasonFirst =
      apiService.canAccess(.subscribe) && fullDetail.type == "电视剧"

    if isSeasonFirst {
      // season 由 preloadTask 管理，检查数据是否已实际加载完毕
      if preloadTask?.isSeasonDataLoaded == true {
        isFirstRowReady = true
      }
      // 否则：View 层通过 onChange(of: preloadTask.isSeasonDataLoaded) 设置
    }

    // 异步加载网络数据（不阻塞调用方返回，数据到达后渐进显示）
    relatedContentTask = Task { [weak self] in
      guard let self else { return }
      defer {
        relatedContentChildTasks.removeAll()
        relatedContentTask = nil
        if !Task.isCancelled {
          isRelatedContentSnapshotComplete = true
        }
      }

      // 1. 并发启动演职员、推荐和相似内容加载，并保存句柄供 Pop 取消。
      let actorsTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await actorsPaginator.refresh()
      }
      let recommendTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await recommendPaginator.refresh()
      }
      let similarTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await similarPaginator.refresh()
      }
      relatedContentChildTasks = [actorsTask, recommendTask, similarTask]

      // 2. 优先等待演员信息加载完成，用于快速更新 Hero 区域和判断首行就绪
      await actorsTask.value
      guard !Task.isCancelled else { return }

      if heroTopActors.isEmpty {
        heroTopActors = Array(actorsPaginator.items.prefix(4))
      }

      // ── 非电视剧：演员加载完后判断首行是否就绪 ──
      // 视图渲染优先级：season -> actors -> directors -> recommend -> similar
      if !isSeasonFirst {
        if !actorsPaginator.items.isEmpty || !uniqueDirectors.isEmpty {
          // 首行是 actors 或 directors，数据已就绪
          isFirstRowReady = true
        }
        // 否则需要等 recommend/similar 加载完
      }

      // 3. 继续等待推荐和相似内容的并行任务完成
      _ = await (recommendTask.value, similarTask.value)
      guard !Task.isCancelled else { return }

      // ── 所有数据加载完毕，兜底设置 ──
      // 仅对非电视剧（首行不是 season）生效：此时 actors/directors/recommend/similar 都已确定。
      // 电视剧的 isFirstRowReady 完全由 isSeasonDataLoaded 控制（通过 View 层 onChange），
      // 不在此处兜底，防止分季 API 比其他 API 慢时提前移除 Loading 遮罩。
      if !isSeasonFirst && !isFirstRowReady {
        isFirstRowReady = true
      }
    }
  }

  /// 当前详情页已加载的普通卡片图片快照。
  var pageImageSnapshot: PageImageSnapshot {
    PageImageSnapshot(
      mediaPosterURLs: Set(
        (recommendPaginator.items + similarPaginator.items)
          .compactMap { $0.imageURLs.poster }
      ),
      personImageURLs: Set(
        (actorsPaginator.items + uniqueDirectors)
          .compactMap { $0.imageURLs.profile }
      ),
      isComplete: isRelatedContentSnapshotComplete
        && !actorsPaginator.isLoading
        && !recommendPaginator.isLoading
        && !similarPaginator.isLoading
    )
  }

  /// 仅在页面已确认被 Pop 出 NavigationPath 后调用。
  func cancelForPop(returningTo target: PageImageCleanupTarget?) {
    mediaServerExistsTask?.cancel()
    mediaServerExistsTask = nil
    relatedContentTask?.cancel()
    relatedContentTask = nil
    relatedContentChildTasks.forEach { $0.cancel() }
    relatedContentChildTasks.removeAll()
    if let target {
      let preloader = MediaPreloader.shared
      recommendPaginator.cancelForPop { urls in
        preloader.enqueuePrefetchedCardImages(
          PageImageSnapshot(mediaPosterURLs: urls),
          returningTo: target
        )
      }
      similarPaginator.cancelForPop { urls in
        preloader.enqueuePrefetchedCardImages(
          PageImageSnapshot(mediaPosterURLs: urls),
          returningTo: target
        )
      }
      actorsPaginator.cancelForPop { urls in
        preloader.enqueuePrefetchedCardImages(
          PageImageSnapshot(personImageURLs: urls),
          returningTo: target
        )
      }
    } else {
      actorsPaginator.cancel()
      recommendPaginator.cancel()
      similarPaginator.cancel()
    }
    preloadTask = nil
  }

  private func loadMediaServerExists() async {
    guard apiService.canAccess(.subscribe), detail.type == "电影", detail.identity != nil else {
      return
    }
    do {
      isInLibrary = try await apiService.fetchMediaServerExists(media: detail)
    } catch {
      Logger.error("检查媒体入库状态失败: \(error)")
    }
  }

  /// 根据媒体的海报或背景图更新详情页背景
  private func setBackground() {
    let backdrop = detail.imageURLs.backdrop
    let poster = detail.imageURLs.poster

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
    let identity = detail.identity
    return Subscribe(
      id: nil,
      name: detail.title ?? "",
      year: detail.year,
      type: detail.type ?? "电影",
      season: season,
      poster: detail.poster_path,
      state: "N",
      last_update: nil,
      // 完整详情是当前页面的权威身份；预识别 TMDB 仅在详情未提供时兜底。
      tmdbid: detail.tmdb_id ?? preloadTask?.tmdbId,
      doubanid: detail.douban_id,
      bangumiid: detail.bangumi_id,
      anilistid: detail.anilist_id,
      media_source: identity?.source,
      media_id: identity?.mediaId,
      mediaid: detail.apiMediaId
    )
  }

  /// 取消当前媒体的订阅
  func cancelSubscription() async {
    let snapshot = apiService.sessionSnapshot()
    isUnsubscribing = true
    defer { isUnsubscribing = false }

    let didCancel = await deleteResolvedSubscription(snapshot: snapshot)
    guard apiService.isSessionUnchanged(from: snapshot) else { return }

    // 刷新所有订阅状态（包括全局和分季）
    await refreshSubscriptionStatus(forceRefresh: true)
    guard apiService.isSessionUnchanged(from: snapshot) else { return }

    if didCancel {
      // 通知首页刷新订阅列表
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    }
  }

  /// 刷新订阅状态：同时更新全局订阅和分季订阅（preloadTask 是唯一数据源）
  @discardableResult
  func refreshSubscriptionStatus(forceRefresh: Bool = true) async -> Bool {
    guard apiService.canAccess(.subscribe) else {
      preloadTask?.isSubscribed = false
      return true
    }

    // 使用 TaskGroup 或并发 Task 同时刷新全局和分季订阅
    var resultCount = 0
    var didRefreshAll = true
    await withTaskGroup(of: Bool.self) { group in
      // 刷新全局订阅状态
      if detail.canDirectlySubscribe {
        let detail = self.detail
        let preloadTmdbId = self.preloadTask?.tmdbId
        let tmdbMedia: MediaInfo? = {
          guard detail.tmdb_id == nil, let tmdbId = preloadTmdbId else { return nil }
          return MediaInfo(tmdb_id: tmdbId, type: detail.type)
        }()
        group.addTask {
          do {
            var isSubscribed = try await self.apiService.checkSubscription(
              media: detail,
              forceRefresh: forceRefresh
            )
            // 豆瓣/Bangumi 来源：用识别到的 tmdbId 补查
            if !isSubscribed, let tmdbMedia {
              isSubscribed = try await self.apiService.checkSubscription(
                media: tmdbMedia,
                forceRefresh: forceRefresh
              )
            }
            await MainActor.run {
              self.preloadTask?.isSubscribed = isSubscribed
            }
            return true
          } catch {
            print("[MediaDetailViewModel] 刷新订阅状态失败: \(error)")
            return false
          }
        }
      }

      // 刷新分季订阅状态
      if let seasonVM = preloadTask?.seasonViewModel {
        group.addTask {
          await seasonVM.checkSubscriptionStatus(forceRefresh: true)
        }
      }

      for await didRefresh in group {
        resultCount += 1
        didRefreshAll = didRefreshAll && didRefresh
      }
    }
    return resultCount > 0 && didRefreshAll
  }

  private func deleteResolvedSubscription(snapshot: APIServiceSessionSnapshot) async -> Bool {
    guard apiService.canAccess(.subscribe) else { return false }
    var fallbackSubscriptionId: Int?
    for media in subscriptionLookupCandidates() {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return false }
        guard
          let subscription = try await apiService.fetchSubscriptionLookup(
            media: media
          )
        else {
          continue
        }
        guard apiService.isSessionUnchanged(from: snapshot) else { return false }
        if canDeleteByMediaId(subscription.mediaId),
          subscription.isResolvedMediaId || media.apiMediaId?.hasPrefix("tmdb:") == true
        {
          return try await apiService.deleteSubscriptionResult(
            mediaId: subscription.mediaId,
            season: nil
          ).success
        }
        fallbackSubscriptionId = subscription.id
      } catch is CancellationError {
        return false
      } catch {
        print("[MediaDetailViewModel] 取消订阅失败: \(error)")
      }
    }
    if let fallbackSubscriptionId {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return false }
        return try await apiService.deleteSubscription(id: fallbackSubscriptionId)
      } catch is CancellationError {
        return false
      } catch {
        print("[MediaDetailViewModel] 取消订阅失败: \(error)")
      }
    }
    return false
  }

  func headerUnsubscribeConfirmationMessage() async -> String {
    let baseMessage = SubscriptionCancelConfirmation.headerMessage(for: detail)
    let snapshot = apiService.sessionSnapshot()
    guard let warning = await resolvedTMDBMultiSeasonCancellationWarning(snapshot: snapshot),
      apiService.isSessionUnchanged(from: snapshot)
    else {
      return baseMessage
    }
    return "\(baseMessage)\n\n\(warning)"
  }

  private func resolvedTMDBMultiSeasonCancellationWarning(
    snapshot: APIServiceSessionSnapshot
  ) async -> String? {
    guard detail.tmdb_id == nil, detail.douban_id != nil || detail.bangumi_id != nil else {
      return nil
    }
    guard let mediaId = await resolvedMediaDeleteTargetForHeaderUnsubscribe(snapshot: snapshot),
      apiService.isSessionUnchanged(from: snapshot),
      mediaId.hasPrefix("tmdb:"),
      let tmdbId = Int(mediaId.dropFirst("tmdb:".count))
    else {
      return nil
    }

    do {
      let subscriptions = try await apiService.fetchSubscriptions(forceRefresh: true)
      guard apiService.isSessionUnchanged(from: snapshot) else { return nil }
      let targetMediaId = "tmdb:\(tmdbId)"
      let matchingSubscriptions = subscriptions.filter {
        $0.type == "电视剧"
          && MediaIdentifier.normalizedMediaIdentifier($0.apiMediaId) == targetMediaId
      }
      guard matchingSubscriptions.count > 1 else { return nil }
      let seasons = Array(Set(matchingSubscriptions.compactMap(\.season))).sorted()
      guard seasons.count > 1 else {
        return "当前内容匹配到 TMDB 下 \(matchingSubscriptions.count) 条订阅，确认后会一并取消。"
      }
      return "当前内容匹配到 TMDB 下多个分季订阅：\(seasonListText(seasons))。确认后会一并取消。"
    } catch is CancellationError {
      return nil
    } catch {
      print("[MediaDetailViewModel] 读取订阅取消影响范围失败: \(error)")
      return nil
    }
  }

  private func resolvedMediaDeleteTargetForHeaderUnsubscribe(
    snapshot: APIServiceSessionSnapshot
  ) async -> String? {
    for media in subscriptionLookupCandidates() {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return nil }
        guard let subscription = try await apiService.fetchSubscriptionLookup(media: media) else {
          continue
        }
        guard apiService.isSessionUnchanged(from: snapshot) else { return nil }
        if canDeleteByMediaId(subscription.mediaId),
          subscription.isResolvedMediaId || media.apiMediaId?.hasPrefix("tmdb:") == true
        {
          return subscription.mediaId
        }
      } catch is CancellationError {
        return nil
      } catch {
        print("[MediaDetailViewModel] 读取订阅取消目标失败: \(error)")
      }
    }
    return nil
  }

  private func seasonListText(_ seasons: [Int]) -> String {
    guard seasons.allSatisfy({ $0 > 0 }) else {
      return seasons.map { $0 == 0 ? "特别篇" : "第 \($0) 季" }.joined(separator: "、")
    }
    return "第 \(seasons.map(String.init).joined(separator: "、")) 季"
  }

  private func canDeleteByMediaId(_ mediaId: String) -> Bool {
    !mediaId.hasPrefix("bangumi:")
  }

  private func subscriptionLookupCandidates() -> [MediaInfo] {
    var candidates = [detail]
    if detail.tmdb_id == nil, let tmdbId = preloadTask?.tmdbId {
      candidates.append(MediaInfo(tmdb_id: tmdbId, type: detail.type))
    }
    return candidates
  }
}
