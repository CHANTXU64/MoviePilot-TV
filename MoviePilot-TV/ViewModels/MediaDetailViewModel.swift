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
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published var detail: MediaInfo

  // 界面背景稳定性控制
  @Published var backgroundUrl: URL?
  @Published var backgroundFallbackUrl: URL?
  @Published var isUsingPosterAsBackdrop = false

  // 分页加载器
  let recommendPaginator: Paginator<MediaInfo>
  let similarPaginator: Paginator<MediaInfo>
  let actorsPaginator: Paginator<Person>
  /// 豆瓣短评（进入详情页即拉第一页，条件见 `DoubanDiscussionAvailability`）
  let doubanCommentsPaginator: Paginator<DoubanDiscussionEntry>
  /// 豆瓣影评（与 Web 一样按需加载：切到「影评」或短评为空时才请求）
  let doubanReviewsPaginator: Paginator<DoubanDiscussionEntry>
  /// 「短评 / 影评」区块当前展示的分类。
  @Published private(set) var doubanDiscussionKind: DoubanDiscussionEntry.Kind = .comment

  // 演职人员信息
  @Published var heroTopActors: [Person] = []
  @Published var heroTopStaff: [GroupedStaff] = []
  @Published var uniqueDirectors: [Person] = []

  @Published private(set) var isInLibrary = false
  /// 管理员且条目在（或无法确认不在）可在应用内播放的服务器上时，应用内播放的目标。
  @Published private(set) var inAppPlaybackTarget: PlaybackTarget?
  /// 电视剧集列表的按集播放和试看，应用内播放可用时才有；这部剧不在媒体库里时也有（每集都可以试看）。
  /// 入库查询结束后才给出，集列表据此查每集能不能播，不会在还不知道入库条目时先把每集都当成不在库。
  @Published private(set) var episodePlayback: EpisodePlaybackSource?
  /// 剧的「继续播放」：按服务器上的观看记录从接着看的那一集开始（见 `PlaybackEpisodeProgress`）。
  /// nil 时详情页显示普通的「播放」（`inAppPlaybackTarget`）。
  @Published private(set) var seriesPlayAction: SeriesPlayAction?
  /// 电影看到了哪里（0…1）：有值时「播放」按钮只有播放图标和已播放进度条。
  @Published private(set) var movieProgress: Double?
  /// 集列表默认显示的季和停在哪一集：看过的剧停在接着看的那一集；没看过时是服务器上最新入库的那一季。
  @Published private(set) var episodeRowHint: EpisodeRowHint?
  /// 「继续播放」用的默认顺序季目录（读到 MoviePilot 的全部季时才有）：集列表行按它显示季，
  /// 结论指向的季集列表行一定有（见 `MediaDetailEpisodeSeasons.catalog`）。
  @Published private(set) var episodeSeasons: [TmdbSeason]?
  /// 「继续播放」指向服务器上还没有的下一集时，按下请集列表打开那一集的面板（每次按下一个新请求）。
  @Published private(set) var episodePanelRequest: EpisodePanelRequest?

  /// 第二页首行数据是否已就绪。
  /// 用于控制 Loading 遮罩的显隐——必须等首行数据加载完才能移除遮罩，
  /// 否则首行 Card 顶部露出在第一页底部时，非首行先加载会导致闪烁。
  @Published var isFirstRowReady = false

  // 视图模型与服务
  @Published var siteFilter: SiteFilterViewModel
  private let apiService: APIService

  /// 可变引用盒子：让 Paginator 闭包始终读取最新的 detail 值。
  /// init 时可能传入 partial data，applyFullDetail 会更新 box 内的值，
  /// 闭包通过 capture 这个 box（引用类型）自动读到 applyFullDetail 后的 detail。
  private final class DetailBox {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    var value: MediaInfo
    init(_ v: MediaInfo) { value = v }
  }
  private let detailBox: DetailBox
  private var cancellables = Set<AnyCancellable>()
  /// 跟随应用内播放开关和后端版本的变化，出栈时停止。
  private var playbackAvailabilityObservation: AnyCancellable?
  private var mediaServerExistsTask: Task<Void, Never>?
  private var seriesProgressTask: Task<Void, Never>?
  /// 剧的观看进度这一次读完、定下了「继续播放」（含没有能接着看的）。没定下时头部的「播放」等它定下再按结果做，
  /// 不按服务器的观看记录直接播（见 `playFromHeader`）。每次重读、换播放目标时重来。
  private var seriesProgressDecided = false
  /// 页面已出栈（`cancelForPop`）：头部「播放」还在等结论时不再重读、不再起播。
  private var isPopped = false
  /// 播放结束（回到详情页）时重读观看进度，「继续播放」跟着变到下一集。出栈时停止。
  private var playbackEndObservations = Set<AnyCancellable>()
  private var relatedContentTask: Task<Void, Never>?
  private var relatedContentChildTasks: [Task<Void, Never>] = []
  /// 已发起过首屏请求的分类；离页前不会自动重发，失败只能由用户在状态卡上重试。
  private var requestedDoubanKinds: Set<DoubanDiscussionEntry.Kind> = []
  /// 用户亲手切换过分类后，不再因为短评为空自动改看影评。
  private var hasUserChosenDoubanKind = false

  init(detail: MediaInfo, apiService: APIService = .shared) {
    self.detail = detail
    self.apiService = apiService
    self.siteFilter = SiteFilterViewModel(apiService: apiService)
    let box = DetailBox(detail)
    self.detailBox = box

    // 预加载命中时容器首帧即揭示内容，这里同步安装背景避免首帧灰底；
    // 网络加载路径随后由 applyFullDetail 以动画升级为完整详情背景。
    let initialBackground = detail.imageURLs.backgroundTarget
    self.backgroundUrl = initialBackground.url
    self.backgroundFallbackUrl = initialBackground.fallbackURL
    self.isUsingPosterAsBackdrop = initialBackground.isPoster

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
      imageWarmer: apiService.imageWarmer,
      imageWarmURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
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
      imageWarmer: apiService.imageWarmer,
      imageWarmURLsProvider: { @MainActor item in
        [item.imageURLs.poster].compactMap { $0 }
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
      },
      imageWarmer: apiService.imageWarmer,
      imageWarmURLsProvider: { item in
        [item.imageURLs.profile].compactMap(\.self)
      }
    )

    self.doubanCommentsPaginator = Self.makeDoubanDiscussionPaginator(
      kind: .comment, detailBox: box, apiService: apiService)
    self.doubanReviewsPaginator = Self.makeDoubanDiscussionPaginator(
      kind: .review, detailBox: box, apiService: apiService)

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

    self.doubanCommentsPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    self.doubanReviewsPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    self.siteFilter.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    // 详情页可能留在另一个标签页的导航栈里，也可能在读到后端设置之前就打开了（比如从 Top Shelf 冷启动直接进来），
    // 设置里的开关或后端版本变了都要重新判断播放入口。
    playbackAvailabilityObservation = Publishers.Merge(
      NotificationCenter.default.publisher(for: PlaybackPreferences.inAppPlaybackDidChangeNotification).map { _ in () },
      apiService.$settings.map { $0?.BACKEND_VERSION }.removeDuplicates().dropFirst().map { _ in () }
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.inAppPlaybackAvailabilityDidChange() }
  }

  /// 应用内播放开关或后端版本变了：不再提供时立即收起播放入口；再重新查一次入库状态和播放目标，
  /// 可以提供时补回入口。正在进行的上一次查询被取代。
  private func inAppPlaybackAvailabilityDidChange() {
    let isEnabled = InAppPlaybackAvailability.isEnabled(
      backendVersion: apiService.settings?.BACKEND_VERSION, userEnabled: PlaybackPreferences.isInAppPlaybackEnabled)
    if !isEnabled {
      episodePlayback = nil
      inAppPlaybackTarget = nil
      seriesPlayAction = nil
      movieProgress = nil
      episodeRowHint = nil
    }
    guard hasAppliedFullDetail else { return }
    startMediaServerExistsCheck()
  }

  private func startMediaServerExistsCheck() {
    mediaServerExistsTask?.cancel()
    mediaServerExistsTask = Task { [weak self] in
      await self?.loadMediaServerExists()
      // 被取代的查询已取消，不能清掉新查询的句柄。
      guard !Task.isCancelled else { return }
      self?.mediaServerExistsTask = nil
    }
  }

  // MARK: - 豆瓣短评 / 影评

  /// 短评与影评共用的分页器：后端是偏移分页，`start` 取此前各批实际返回的条数（去重前）。
  ///
  /// 与 Web 的 `start = 已加载条数` 一致。不按「页码 × 每页条数」推算：豆瓣某批返回不足
  /// 每页条数时会跳过条目或提前判到底。也不按去重后的条数推算：去重丢掉的条目仍占用服务端
  /// 的位置，按去重后条数推算会让下一批与上一批重叠。入口条件在请求前重新求值，详情或设置
  /// 变化后不会用失效的条件发请求。
  private static func makeDoubanDiscussionPaginator(
    kind: DoubanDiscussionEntry.Kind,
    detailBox box: DetailBox,
    apiService: APIService
  ) -> Paginator<DoubanDiscussionEntry> {
    var seenKeys = Set<String>()
    return Paginator<DoubanDiscussionEntry>(
      threshold: DoubanDiscussionAvailability.loadMoreThreshold,
      // 豆瓣返回 total：分页器据此判到底，不再多发一次空请求；胶囊数量也读它。
      cursorFetcher: { @MainActor [apiService, box] cursor in
        let detail = box.value
        guard
          DoubanDiscussionAvailability.isEligible(
            detail: detail,
            backendVersion: apiService.settings?.BACKEND_VERSION
          ),
          let doubanId = DoubanDiscussionAvailability.normalizedDoubanID(detail.douban_id),
          let typeName = DoubanDiscussionAvailability.normalizedMediaType(detail.type)
        // 入口条件中途失效时按「取消」处理：不能返回空数组，否则会被当成确认为空的终页。
        else { throw CancellationError() }
        let pageSize = DoubanDiscussionAvailability.pageSize
        let start = cursor.offset
        switch kind {
        case .comment:
          let page = try await apiService.fetchDoubanComments(
            doubanId: doubanId, typeName: typeName, start: start, count: pageSize)
          return PaginatedBatch(
            items: page.resolvedItems.map(DoubanDiscussionEntry.init(comment:)), total: page.total)
        case .review:
          let page = try await apiService.fetchDoubanReviews(
            doubanId: doubanId, typeName: typeName, start: start, count: pageSize)
          return PaginatedBatch(
            items: page.resolvedItems.map(DoubanDiscussionEntry.init(review:)), total: page.total)
        }
      },
      processor: { @MainActor items, newItems in
        let unique = newItems.filter { seenKeys.insert($0.id).inserted }
        guard !unique.isEmpty else { return false }
        items.append(contentsOf: unique)
        return true
      },
      onReset: { @MainActor in
        seenKeys.removeAll()
      }
    )
  }

  /// 胶囊文字，例如「短评 128」；规则见 `DoubanDiscussionAvailability.chipTitle`。
  func doubanChipTitle(for kind: DoubanDiscussionEntry.Kind) -> String {
    DoubanDiscussionAvailability.chipTitle(
      for: kind,
      total: doubanPaginator(for: kind).total,
      loadedCount: doubanPaginator(for: kind).items.count
    )
  }

  func doubanPaginator(for kind: DoubanDiscussionEntry.Kind) -> Paginator<DoubanDiscussionEntry> {
    switch kind {
    case .comment: return doubanCommentsPaginator
    case .review: return doubanReviewsPaginator
    }
  }

  func doubanRowState(for kind: DoubanDiscussionEntry.Kind) -> DoubanDiscussionRowState {
    let paginator = doubanPaginator(for: kind)
    return DoubanDiscussionAvailability.rowState(
      hasRequested: requestedDoubanKinds.contains(kind),
      itemCount: paginator.items.count,
      isLoadingFirstPage: paginator.isFirstLoading,
      hasError: paginator.hasError,
      hasMore: paginator.hasMore
    )
  }

  /// 区块是否可见（不含入口条件；入口条件由视图结合当前设置判断）。
  var isDoubanDiscussionSectionVisible: Bool {
    DoubanDiscussionAvailability.isSectionVisible(
      comments: doubanRowState(for: .comment),
      reviews: doubanRowState(for: .review)
    )
  }

  /// 进入详情页即拉取短评第一页；影评等用户切过去再拉（与 Web 一致，避免同时请求两个豆瓣接口）。
  ///
  /// - 不参与首屏预载、不阻塞 `isFirstRowReady`，区块异步渐进显示。
  /// - 完整详情应用之前不发请求：入口卡片带来的部分详情里的豆瓣 ID / 类型可能与完整详情不同。
  /// - 版本 / 豆瓣 ID / 媒体类型任一不满足时**不发请求**。
  /// - 条件在调用时重新求值，「设置晚到」时后续调用仍能补发；发起后不再重发。
  /// - 调用方负责 `allowsRequests` 门禁：启动会话准备期间不得调用。
  func loadDoubanDiscussionIfNeeded() {
    startDoubanDiscussionIfNeeded(.comment)
  }

  /// 用户点了分类胶囊。点当前已选中的分类不算改选，短评为空时仍会自动改看影评。
  func selectDoubanDiscussion(_ kind: DoubanDiscussionEntry.Kind) {
    guard kind != doubanDiscussionKind else { return }
    hasUserChosenDoubanKind = true
    doubanDiscussionKind = kind
    startDoubanDiscussionIfNeeded(kind)
  }

  /// 状态卡后面的「重试」按钮：只重试当前分类。
  func retryDoubanDiscussion() {
    let kind = doubanDiscussionKind
    guard isDoubanDiscussionEligible else { return }
    requestedDoubanKinds.insert(kind)
    runDoubanDiscussionFirstPage(kind)
  }

  /// 已有内容、加载更多失败时行尾的「重试」按钮：只重试当前分类的下一批。
  func retryDoubanDiscussionNextPage() {
    guard isDoubanDiscussionEligible else { return }
    let paginator = doubanPaginator(for: doubanDiscussionKind)
    Task { await paginator.retryAfterError() }
  }

  private var isDoubanDiscussionEligible: Bool {
    hasAppliedFullDetail
      && DoubanDiscussionAvailability.isEligible(
        detail: detail,
        backendVersion: apiService.settings?.BACKEND_VERSION
      )
  }

  private func startDoubanDiscussionIfNeeded(_ kind: DoubanDiscussionEntry.Kind) {
    guard !requestedDoubanKinds.contains(kind), isDoubanDiscussionEligible else { return }
    requestedDoubanKinds.insert(kind)
    runDoubanDiscussionFirstPage(kind)
  }

  /// 重新拉取某一类的第一页。分页器同步进入首屏加载中，状态卡不会在任务启动前闪成失败；
  /// 再次重试或离页取消会让上一轮加载提前结束，结束时的状态不是「空」，不会误切分类。
  private func runDoubanDiscussionFirstPage(_ kind: DoubanDiscussionEntry.Kind) {
    let load = doubanPaginator(for: kind).startRefresh()
    guard kind == .comment else { return }
    Task { @MainActor [weak self] in
      await load.value
      guard let self else { return }
      // 短评确认为空时自动改看影评，否则整个区块没有可看的内容；
      // 用户已经亲手选过分类就尊重用户的选择。
      if !hasUserChosenDoubanKind, doubanRowState(for: .comment) == .empty {
        doubanDiscussionKind = .review
        startDoubanDiscussionIfNeeded(.review)
      }
    }
  }

  private var hasAppliedFullDetail = false

  /// 页面重新激活时，对处于“成功空终态”的推荐/相似/演员分页各重试一次。
  func refreshSuccessEmptySections() async {
    if recommendPaginator.items.isEmpty, !recommendPaginator.isLoading, !recommendPaginator.hasError,
      !recommendPaginator.hasMore
    {
      await recommendPaginator.refresh()
    }
    if similarPaginator.items.isEmpty, !similarPaginator.isLoading, !similarPaginator.hasError,
      !similarPaginator.hasMore
    {
      await similarPaginator.refresh()
    }
    if actorsPaginator.items.isEmpty, !actorsPaginator.isLoading, !actorsPaginator.hasError,
      !actorsPaginator.hasMore
    {
      await actorsPaginator.refresh()
    }
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

    guard !hasAppliedFullDetail else { return }
    hasAppliedFullDetail = true

    // 从完整详情中派生演职员数据，作为 API 加载前的快速初始显示
    let directors = fullDetail.resolvedDirectors
    uniqueDirectors = StaffManager.processCrew(persons: directors)
    heroTopStaff = StaffManager.getTopGroupedStaff(from: directors, count: 1)
    // F-050：**先去重、再取前四**，不要反过来。
    //
    // 后端 `actors` 取自 TMDB `credits.cast`（`app/core/context.py:481-486`），只过滤
    // `known_for_department == "Acting"` 而**不去重**，而 TMDB 的 cast 允许同一个人以不同
    // `character` 出现多条。原实现先 `prefix(4)` 再交给 `processActors` 按 id 合并，于是这 4 条
    // 里的多角色重复被折叠成一个、Hero 只剩 2~3 人，而本方法尾部「Hero 完全为空才用分页
    // 数据补」的分支只在**彻底为空**时才兜底，半空状态永远补不上。
    //
    // 顺序颠倒后与分页那一路同构（`actorsPaginator` 的 processor 本就是 `mergeActors`），
    // 所以该兜底分支里的 `prefix(4)` 是对的、无需改动。`mergeActors` 保持服务端顺序且合并
    // `character`（多角色显示成「角色A/角色B」），故就顺序这一项而言，改的只是「取哪四个人」，
    // 被合并者的角色信息不丢；下面 F-056 的过滤是另一件事，它确实会丢弃无名者 —— 那些人
    // 在 Hero 行里本就渲染不出任何内容。
    //
    // F-056（G07 第三裁并入本项）：**空名一并剔掉**，无名氏不能白占名额。
    // 视图侧 `MediaDetailView.swift:1037` 是 `compactMap { $0.name }.joined(...)`，
    // name 为 nil 或去空白后为空的人渲染出来只是一个空档，却照样消耗四个名额之一，
    // 后面明明还有别的演员可以顶上 —— 与上面重复项挤人同属「取样顺序」这一个根因，
    // 故两条一起在这里收口，顺序是 G07 第三裁给的 `processActors` → 过滤 → `prefix(4)`。
    //
    // 过滤只放在 Hero 取样这一层，**不下沉到 `mergeActors`**：演员货架要不要收无名者
    // 是另一条口径，verify_s006 已明确货架不受本项影响，不在这里顺带改。
    //
    // 尾部的「完全为空才补」也**不需要放宽**：分页第一页取的就是同一份 `credits.cast`
    // 的前 24 条，故 `fullDetail.actors` 非空时分页不会有新面孔可补；本处修好后
    // 「去重后自然不足四人」只剩「这份 cast 去重后本就不足四人」一种解释，无处可补。
    // 该分支保持原样：它只在 `heroTopActors` 彻底为空时兜底，此时过滤与否都不改变
    // 「这份数据本就没有可显示的主演」这一结论，为它加过滤只会扩大本次改动面。
    heroTopActors = Array(
      StaffManager.processActors(persons: fullDetail.actors ?? [])
        .filter { !($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .prefix(4))

    startMediaServerExistsCheck()

    // 进入详情页就拉豆瓣短评/影评第一页：独立任务、不参与首屏就绪判断、不做任何预载。
    loadDoubanDiscussionIfNeeded()

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

  /// 仅在页面已确认被 Pop 出 NavigationPath 后调用。
  func cancelForPop() {
    playbackAvailabilityObservation = nil
    playbackEndObservations.removeAll()
    mediaServerExistsTask?.cancel()
    mediaServerExistsTask = nil
    seriesProgressTask?.cancel()
    seriesProgressTask = nil
    isPopped = true
    relatedContentTask?.cancel()
    relatedContentTask = nil
    relatedContentChildTasks.forEach { $0.cancel() }
    relatedContentChildTasks.removeAll()
    actorsPaginator.cancel()
    recommendPaginator.cancel()
    similarPaginator.cancel()
    doubanCommentsPaginator.cancel()
    doubanReviewsPaginator.cancel()
    preloadTask = nil
  }

  private func loadMediaServerExists() async {
    guard detail.identity != nil else { return }
    let isMovie = detail.type == "电影"
    // 电影的入库状态显示在订阅按钮上；剧集只用于管理员的应用内播放。
    let showsLibraryState = isMovie && apiService.canAccess(.subscribe)
    let offersPlayback = InAppPlaybackAvailability.offers(
      mediaType: detail.type, canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
      backendVersion: apiService.settings?.BACKEND_VERSION)
    guard showsLibraryState || offersPlayback else { return }
    let snapshot = apiService.sessionSnapshot()
    let coordinator = apiService.sessionScope.playbackCoordinator
    let itemRef: MediaServerItemRef?
    do {
      itemRef = try await apiService.fetchMediaServerItemRef(media: detail)
    } catch is CancellationError {
      return
    } catch {
      Logger.error("检查媒体入库状态失败: \(error)")
      return
    }
    guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot) else { return }
    if showsLibraryState { isInLibrary = itemRef != nil }
    guard offersPlayback else { return }
    do {
      let servers = try await apiService.fetchCachedMediaServers()
      guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot),
        servers.contains(where: \.supportsInAppPlayback)
      else { return }
      // MoviePilot 还没同步到的新条目（首页「最近添加」里刚入库的）入库查询查不到，用首页带来的条目；
      // 起播前照常按详情页的编号核对（见 `PlaybackCoordinator.findLibraryItem`）。
      let playbackRef = itemRef ?? libraryItemHint
      if detail.type == "电视剧" { episodePlayback = EpisodePlaybackSource(libraryItem: playbackRef) }
      guard let playbackRef else { return }
      // 入库条目可能属于不能在应用内播放的服务器，ID 也可能和别的服务器撞号：需要时在可播放的服务器上按外部编号找到它。
      let expected = LibraryItemExpectation(media: detail)
      let target = await coordinator.locateLibraryItem(
        playbackRef.itemID, expected: expected, in: servers, preferredServer: playbackRef.server)
      guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot) else { return }
      if inAppPlaybackTarget != target { seriesProgressDecided = false }
      inAppPlaybackTarget = target
      if let target {
        startWatchProgressLoad(target)
        observePlaybackEnd(target)
      }
    } catch is CancellationError {
    } catch {
      Logger.warning("读取媒体服务器配置失败: \(error.localizedDescription)")
    }
  }

  // MARK: - 剧的观看进度

  /// 读观看进度：剧算「继续播放」和集列表默认的位置，电影算按钮上的已播放进度。
  /// `forceRefresh`：集列表、季列表和集索引都不用缓存（按下「播放」重试上次说明过原因的结论时）。
  private func startWatchProgressLoad(_ target: PlaybackTarget, forceRefresh: Bool = false) {
    seriesProgressTask?.cancel()
    // 重读期间上次的结论可能已经过时（刚播完、从别的 App 回来）：按钮照常显示上次的，头部「播放」等这次读完（见 `playFromHeader`）。
    seriesProgressDecided = false
    seriesProgressTask = Task { [weak self] in
      guard let self else { return }
      switch self.detail.type {
      case "电视剧": await self.loadSeriesProgress(target, forceRefresh: forceRefresh)
      case "电影": await self.loadMovieProgress(target)
      default: break
      }
    }
  }

  private func loadMovieProgress(_ target: PlaybackTarget) async {
    let snapshot = apiService.sessionSnapshot()
    let progress = await apiService.sessionScope.playbackCoordinator.movieProgress(for: target)
    guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot), inAppPlaybackTarget == target
    else { return }
    movieProgress = progress
  }

  /// 播放结束、进度写回发完后重读（见 `PlaybackCoordinator.watchStateUpdates`）。播的是别的片时不动。
  /// 播放器一关（`watchStateChanging`）就先作废旧的「继续播放」结论：写回发完前按「播放」也等新结论（见 `playFromHeader`）。
  private func observePlaybackEnd(_ target: PlaybackTarget) {
    let coordinator = apiService.sessionScope.playbackCoordinator
    let concerns = { [weak self] (change: WatchStateChange) -> Bool in
      guard let self, self.inAppPlaybackTarget == target else { return false }
      return change.concerns(tmdbID: MediaIdentifier.validNumericIdentifier(self.detail.tmdb_id), itemID: target.itemID)
    }
    playbackEndObservations.removeAll()
    coordinator.watchStateChanging
      .sink { [weak self] change in
        guard concerns(change), let self else { return }
        // 播放前开始的那次读取晚到时会把旧结论写回来：一并取消，等写回发完后的重读。
        self.seriesProgressTask?.cancel()
        self.seriesProgressDecided = false
      }
      .store(in: &playbackEndObservations)
    coordinator.watchStateUpdates
      .sink { [weak self] change in
        guard concerns(change) else { return }
        self?.startWatchProgressLoad(target)
      }
      .store(in: &playbackEndObservations)
    // 集索引重建了（起播后台核对出新的整理记录、集列表行强制重查）：集卡片会跟着变，「继续播放」也按新的集索引重算。
    coordinator.evidenceUpdates.merge(with: coordinator.episodeIndexRefreshes)
      .sink { [weak self] tmdbID in
        guard let self, self.inAppPlaybackTarget == target,
          tmdbID == MediaIdentifier.validNumericIdentifier(self.detail.tmdb_id)
        else { return }
        self.startWatchProgressLoad(target)
      }
      .store(in: &playbackEndObservations)
  }

  /// 读这部剧的观看进度，算出「继续播放」和集列表默认的位置。读不到时保留上次的结果。
  /// 「这份文件是哪一集」只认集索引，按下做什么见 `SeriesContinuation.choose`。
  private func loadSeriesProgress(_ target: PlaybackTarget, forceRefresh: Bool = false) async {
    let snapshot = apiService.sessionSnapshot()
    let coordinator = apiService.sessionScope.playbackCoordinator
    // 每次 await 之后复核：没被取消、账号没变、还是这个播放目标，才写回。
    let isCurrent = { [weak self] in
      guard let self else { return false }
      return !Task.isCancelled && self.apiService.isSessionUnchanged(from: snapshot) && self.inAppPlaybackTarget == target
    }
    let selectable = MediaDetailEpisodeSeasons.selectable(detail.season_info ?? []).compactMap(\.season_number)
    let context = episodePlayback?.context(media: detail, episodeGroup: nil, seasons: selectable)
    guard let progress = await coordinator.seriesProgress(for: target, context: context), isCurrent() else { return }
    let latestSeason = progress.latestSeason.map { EpisodeRowHint(season: $0) }

    /// 写下结论：按钮做什么、集列表停在哪。之后头部的「播放」按它做（见 `playFromHeader`）。
    func publish(_ action: SeriesPlayAction?, _ hint: EpisodeRowHint?) {
      seriesPlayAction = action
      episodeRowHint = hint
      seriesProgressDecided = true
    }
    func hint(_ episode: MoviePilotEpisode) -> EpisodeRowHint {
      EpisodeRowHint(season: episode.seasonNumber, tmdbEpisodeID: episode.tmdbEpisodeID, episodeNumber: episode.episodeNumber)
    }
    /// 播服务器上的这份。`season`/`episode` 是按钮上写的季号集号（缺一个就不写集号），`hint` 是集列表停的位置。
    func playServerFile(
      _ file: ServerMediaItem, resumes: Bool, season: Int? = nil, episode: Int? = nil, hint: EpisodeRowHint? = nil
    ) {
      publish(
        SeriesPlayAction.labeled(
          .play(.serverItem(serverName: progress.serverName, itemID: file.id)), resumeFile: resumes ? file : nil,
          season: season, episode: episode),
        hint ?? latestSeason)
    }

    // 详情页不是 TMDB 来源（豆瓣、Bangumi）：没有集列表可对（集列表行也不显示），按服务器的观看记录播，写服务器上的集号。
    guard let context, MediaDetailEpisodeSeasons.tmdbID(for: detail) != nil else {
      if let upNext = progress.upNext {
        let file = upNext.episode
        playServerFile(
          file, resumes: upNext.resumes, season: file.seasonNumber, episode: file.episodeNumber,
          hint: file.seasonNumber.map { EpisodeRowHint(season: $0, episodeNumber: file.episodeNumber) })
      } else {
        publish(nil, latestSeason)
      }
      return
    }
    async let lookups = coordinator.episodeLookups(for: context, forceRefresh: forceRefresh)
    let lists = await moviePilotSeasonCatalog(tmdbID: context.tmdbID, selectable: selectable, forceRefresh: forceRefresh)
    guard isCurrent() else { return }
    if let catalog = lists.catalog, episodeSeasons != catalog { episodeSeasons = catalog }
    // 集列表按需读：先读眼下用得到的几季（和集索引同时读），判断说还要别的季再补读（见 `SeriesContinuation.decide`），
    // 不等不相关的季。一次最多读 `continuationSeasonReadLimit` 季，超过的当成没读到（判断按读不到的季处理）。
    var seasons: [SeriesContinuation.Season] = []
    var unread = Set(lists.known)
    var budget = Self.continuationSeasonReadLimit
    let anchor = SeriesContinuation.anchorSeason(upNext: progress.upNext, lastWatched: progress.lastWatched, known: lists.known)
    func read(_ numbers: [Int]) async {
      let batch = Array(numbers.filter(unread.contains).prefix(budget))
      budget -= batch.count
      unread.subtract(batch)
      seasons += await readMoviePilotSeasons(batch, tmdbID: context.tmdbID, forceRefresh: forceRefresh)
    }
    await read(
      SeriesContinuation.seasonsToReadFirst(upNext: progress.upNext, lastWatched: progress.lastWatched, known: lists.known))
    // 读不到服务器配置时当成集索引读不到（不是服务器上没有这些集）。
    let loaded = await lookups ?? [.failed(server: progress.serverName, message: "没能读取媒体服务器配置")]
    guard isCurrent() else { return }
    var choice: SeriesContinuation.Choice?
    deciding: while true {
      let outcome = SeriesContinuation.decide(
        upNext: progress.upNext, lastWatched: progress.lastWatched, serverName: progress.serverName, lookups: loaded,
        seasons: seasons, unread: unread, knownSeasons: lists.known, catalogComplete: lists.catalogComplete)
      switch outcome {
      case .decided(let decided):
        choice = decided
        break deciding
      case .needs(let wanted):
        // 读到上限了：剩下的季不再读，当成没读到。
        guard budget > 0 else {
          unread = []
          continue
        }
        await read(SeriesContinuation.readingOrder(wanted, near: anchor))
        guard isCurrent() else { return }
      }
    }
    func explain(_ message: String) {
      publish(SeriesPlayAction(title: "播放", accessibilityLabel: "播放", action: .explain(message)), latestSeason)
    }
    // 播放器里接着播下一集的季顺序用同一份季目录（集列表行显示的季）。
    let queueContext =
      lists.catalog.flatMap {
        episodePlayback?.context(media: detail, episodeGroup: nil, seasons: $0.compactMap(\.season_number))
      } ?? context
    func queued(_ episode: MoviePilotEpisode, _ season: [MoviePilotEpisode], resumeFile: ServerMediaItem?) -> PlaybackTarget {
      var queued = QueuedEpisode(context: queueContext, episode: episode, seasonEpisodes: season)
      if let resumeFile { queued.preferredFile = ServerFileRef(server: progress.serverName, itemID: resumeFile.id) }
      return .episode(queued, accepting: .consistentNumberMatches)
    }
    switch choice {
    case .play(let episode, let season, let resumeFile):
      publish(
        SeriesPlayAction.labeled(
          .play(queued(episode, season, resumeFile: resumeFile)), resumeFile: resumeFile,
          season: episode.seasonNumber, episode: episode.episodeNumber),
        hint(episode))
    case .start(let episode, let season):
      // 没看过或全看完：按钮是普通的「播放」，集列表停在服务器上最新的一季。
      publish(
        SeriesPlayAction(title: "播放", accessibilityLabel: "播放", action: .play(queued(episode, season, resumeFile: nil))),
        latestSeason ?? EpisodeRowHint(season: episode.seasonNumber))
    case .openPanel(let episode):
      let text = SeriesPlayAction.title(resumes: false, season: episode.seasonNumber, episode: episode.episodeNumber)
      publish(SeriesPlayAction(title: text, accessibilityLabel: text, action: .openEpisode), hint(episode))
    case .playServerFile(let file, let resumes, let episode?):
      // 对上了集列表里的这一集，但起播不会试这份（那一集另有确定的文件）：照常播这份，按钮写那一集的集号。
      playServerFile(
        file, resumes: resumes, season: episode.seasonNumber, episode: episode.episodeNumber, hint: hint(episode))
    case .playServerFile(let file, let resumes, nil):
      // 对不到集列表（认不出、集列表还没有、读不到），没有反证：照常播，按钮不写集号，不以集列表里某一集的名义播。
      playServerFile(file, resumes: resumes)
    case .explain(.fileContradicted(let file)):
      let name = SeriesPlayAction.episodeText(season: file.seasonNumber, episode: file.episodeNumber).map { "「\($0)」" } ?? ""
      explain("媒体服务器上\(name)和集列表对不上（播出日期、单集编号或外部编号），没法确定是哪一集，请在集列表里选择要播的集")
    case .explain(.seasonListUnreadable):
      explain("有一季的集列表没读到，暂时没法确定接着看哪一集，请稍后再试，或在集列表里选择要播的集")
    case .explain(.nextUnknown):
      explain("看完的那一集对不上集列表，没法确定下一集，请在集列表里选择要播的集")
    case .explain(.episodesUnreadable):
      explain("读不到媒体服务器上这部剧的集，暂时没法确定下一集，请稍后再试，或在集列表里选择要播的集")
    case nil:
      // MoviePilot 的集列表一集都没读到，服务器上也没有接着看的那份：没法确定从哪一集开始。
      explain("读不到 MoviePilot 的集列表，暂时没法确定从哪一集开始，请稍后再试")
    }
  }

  /// 「继续播放」一次判断最多读几季集列表：季很多的剧（几十上百季）不一下子全读，不给 MoviePilot 和 TMDB 一次压上
  /// 几百个请求。剧的季数在这以内时，最坏也只是和全部读完一样。
  static let continuationSeasonReadLimit = 20

  /// MoviePilot 集列表（默认顺序）应有的季：季号取 MoviePilot 给的全部季（含新出的季和特别篇，和集索引用的一样），
  /// 并上详情里的季（`known`，不含一集都还没有的季）；季列表本身没读到时 `catalogComplete` 为 false。
  private func moviePilotSeasonCatalog(tmdbID: Int, selectable: [Int], forceRefresh: Bool) async
    -> (known: [Int], catalogComplete: Bool, catalog: [TmdbSeason]?)
  {
    let media = MediaInfo(
      tmdb_id: tmdbID, source: "themoviedb", media_id: String(tmdbID), title: detail.title, type: "电视剧",
      season_info: detail.season_info)
    let all = try? await apiService.getMediaSeasons(media: media, allSeasons: true, forceRefresh: forceRefresh)
    let catalogComplete = !(all ?? []).isEmpty
    // 和集列表行同一份季目录（读不到全部季时只有详情里的季，集列表行自己补读、重试）。
    let catalog = catalogComplete ? MediaDetailEpisodeSeasons.catalog(all ?? [], media: media) : nil
    // TMDB 已公布、但还一集都没有的季（`episode_count` 为 0）不算应有的季：它的集列表本来就是空的，不是没读到。
    // 只要有一处说有集（或没给集数）就照常读。
    let reported = (detail.season_info ?? []) + (all ?? [])
    var numbers = catalog.map { Set($0.compactMap(\.season_number)) } ?? Set(selectable)
    numbers = numbers.filter { number in
      let counts = reported.filter { $0.season_number == number }.map(\.episode_count)
      return counts.isEmpty || counts.contains { $0 != 0 }
    }
    return (numbers.sorted(), catalogComplete, catalog)
  }

  /// 同时读这几季的集列表，走会话缓存。读不到或 MoviePilot 读 TMDB 失败返回空列表的季不在结果里。
  private func readMoviePilotSeasons(_ numbers: [Int], tmdbID: Int, forceRefresh: Bool) async
    -> [SeriesContinuation.Season]
  {
    let apiService = apiService
    let reads = numbers.map { number in
      Task { @MainActor () -> SeriesContinuation.Season? in
        let list =
          (try? await apiService.fetchTmdbEpisodes(
            tmdbID: tmdbID, season: number, episodeGroup: nil, forceRefresh: forceRefresh)) ?? []
        if list.isEmpty { return nil }
        return SeriesContinuation.Season(number: number, episodes: MoviePilotEpisode.list(list, season: number))
      }
    }
    return await withTaskCancellationHandler {
      var seasons: [SeriesContinuation.Season] = []
      for read in reads { if let season = await read.value { seasons.append(season) } }
      return seasons
    } onCancel: {
      reads.forEach { $0.cancel() }
    }
  }

  /// 头部「播放」按下。剧只按这一次读出的「继续播放」结论做（按集起播、打开那一集的面板、说明为什么没法播；
  /// 不是 TMDB 来源的详情页按服务器的观看记录播）：结论还没定下（第一次读、播完或回前台重读，按钮上可能还是上一次的）时
  /// 先显示「正在准备播放」等它定下。不能趁没定下按旧结论或整剧播放：整剧播放会按服务器的观看记录直接播，不核对单集。
  func playFromHeader(_ target: PlaybackTarget) {
    let coordinator = apiService.sessionScope.playbackCoordinator
    guard detail.type == "电视剧" else {
      coordinator.play(target, media: detail)
      return
    }
    // 上次的结论是说明原因（读不到、对不上）：情况可能已经变了，按下时重读一次再定，不只重复上次的说明。
    if seriesProgressDecided, case .explain? = seriesPlayAction?.action, inAppPlaybackTarget == target {
      startWatchProgressLoad(target, forceRefresh: true)
    }
    if seriesProgressDecided {
      if let seriesPlayAction {
        performSeriesPlayAction(seriesPlayAction)
      } else {
        coordinator.play(target, media: detail)
      }
      return
    }
    coordinator.play(media: detail) { [weak self] in
      guard let self else { return nil }
      var retried = false
      while !Task.isCancelled, !self.isPopped, self.inAppPlaybackTarget == target, !self.seriesProgressDecided {
        let loading = self.seriesProgressTask
        await loading?.value
        if Task.isCancelled || self.seriesProgressDecided { break }
        // 被新的一次重读取代了：等新的那次。
        if self.seriesProgressTask != loading { continue }
        // 这次没读到：再读一次，还读不到就不再等。
        if retried { break }
        retried = true
        self.startWatchProgressLoad(target)
      }
      guard !Task.isCancelled, !self.isPopped, self.inAppPlaybackTarget == target else { return nil }
      guard self.seriesProgressDecided else {
        throw PlaybackError.episodeUnavailable("读不到这部剧在媒体服务器上的观看记录，没法确定接着看哪一集，请稍后再试，或在集列表里选择要播的集")
      }
      guard let action = self.seriesPlayAction else { return target }
      if case .play(let decided) = action.action { return decided }
      self.performSeriesPlayAction(action)
      return nil
    }
  }

  /// 「继续播放」按下：能播时起播，指向服务器上还没有的集时请集列表打开那一集的面板。
  private func performSeriesPlayAction(_ action: SeriesPlayAction) {
    switch action.action {
    case .play(let target):
      apiService.sessionScope.playbackCoordinator.play(target, media: detail)
    case .openEpisode:
      guard let hint = episodeRowHint else { return }
      episodePanelRequest = EpisodePanelRequest(hint: hint)
    case .explain(let message):
      apiService.sessionScope.playbackCoordinator.inform(message)
    }
  }

  /// 根据媒体的海报或背景图更新详情页背景
  private func setBackground() {
    let target = detail.imageURLs.backgroundTarget

    // 核心保护逻辑：只有当背景 URL 真正改变时才触发 @Published 更新。
    // 这能有效防止因为值相同但对象不同导致的 UI 重新闪烁刷新。
    if self.backgroundUrl != target.url || self.backgroundFallbackUrl != target.fallbackURL
      || self.isUsingPosterAsBackdrop != target.isPoster
    {
      withAnimation(.easeInOut(duration: 0.8)) {
        if self.backgroundUrl != target.url {
          self.backgroundUrl = target.url
        }
        if self.backgroundFallbackUrl != target.fallbackURL {
          self.backgroundFallbackUrl = target.fallbackURL
        }
        if self.isUsingPosterAsBackdrop != target.isPoster {
          self.isUsingPosterAsBackdrop = target.isPoster
        }
      }
    }
  }

  func refreshBackgroundForImageConfiguration() {
    setBackground()
  }

  func useBackgroundFallback(afterFailing failedURL: URL) {
    guard backgroundUrl == failedURL, let fallbackURL = backgroundFallbackUrl,
      fallbackURL != failedURL
    else { return }
    backgroundFallbackUrl = nil
    backgroundUrl = fallbackURL
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
  /// 从首页「最近添加」打开时那张卡在媒体服务器上的条目（见 `MediaInfo.libraryItemHint`）：入库查询查不到时用它播放。
  var libraryItemHint: MediaServerItemRef?

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
  @discardableResult
  func cancelSubscription() async -> Bool {
    let snapshot = apiService.sessionSnapshot()
    isUnsubscribing = true
    defer { isUnsubscribing = false }

    let didCancel = await deleteResolvedSubscription(snapshot: snapshot)
    guard apiService.isSessionUnchanged(from: snapshot) else { return false }

    // 刷新所有订阅状态（包括全局和分季）
    await refreshSubscriptionStatus(forceRefresh: true)
    guard apiService.isSessionUnchanged(from: snapshot) else { return false }

    if didCancel {
      // 通知首页刷新订阅列表
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    }
    // 远端已被其他入口删除时，刷新后的未订阅状态也视为收敛成功。
    return didCancel || preloadTask?.isSubscribed == false
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
            Logger.error("[MediaDetailViewModel] 刷新订阅状态失败: \(error)")
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
            media: media,
            includeVideoMetadataFallback: false
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
        Logger.error("[MediaDetailViewModel] 取消订阅失败: \(error)")
      }
    }
    if let fallbackSubscriptionId {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return false }
        return try await apiService.deleteSubscription(id: fallbackSubscriptionId)
      } catch is CancellationError {
        return false
      } catch {
        Logger.error("[MediaDetailViewModel] 取消订阅失败: \(error)")
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
      Logger.error("[MediaDetailViewModel] 读取订阅取消影响范围失败: \(error)")
      return nil
    }
  }

  private func resolvedMediaDeleteTargetForHeaderUnsubscribe(
    snapshot: APIServiceSessionSnapshot
  ) async -> String? {
    for media in subscriptionLookupCandidates() {
      do {
        guard apiService.isSessionUnchanged(from: snapshot) else { return nil }
        guard let subscription = try await apiService.fetchSubscriptionLookup(
          media: media,
          includeVideoMetadataFallback: false
        ) else {
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
        Logger.error("[MediaDetailViewModel] 读取订阅取消目标失败: \(error)")
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

/// 详情页剧的「继续播放」按钮：标题写明从哪一集开始，按下起播。
/// 看到一半时按钮是播放图标、已播放进度条和「第 X 季第 Y 集」（与 Apple TV App 一样）。
struct SeriesPlayAction: Equatable {
  let title: String
  /// 看到一半时的已播放进度（0…1），画在播放图标后面；从头看的一集、或服务器没给时长时为 nil。
  var progress: Double? = nil
  /// 读屏用的完整说法（有进度条时标题里省掉了「继续播放」）。
  var accessibilityLabel: String
  let action: Action

  enum Action: Equatable {
    case play(PlaybackTarget)
    /// 下一集服务器上还没有：打开集列表里那一集的面板（能试看时在面板里试看），和按那张集卡片一样。
    case openEpisode
    /// 接着看的那份对不到集列表里的任何一集：说明原因，请用户在集列表里选。
    case explain(String)
  }

  /// 按钮的样子：`resumeFile` 是接着看到一半的那份时显示播放图标、它的已播放进度条和季集号（读屏念「继续播放 …」），
  /// 否则是「播放 第 X 季第 Y 集」。
  static func labeled(_ action: Action, resumeFile: ServerMediaItem?, season: Int?, episode: Int?) -> SeriesPlayAction {
    let progress = resumeFile.flatMap {
      PlaybackResumePolicy.progressFraction(positionSeconds: $0.resumePositionSeconds, durationSeconds: $0.runtimeSeconds)
    }
    let spoken = title(resumes: resumeFile != nil, season: season, episode: episode)
    return SeriesPlayAction(
      title: progress == nil ? spoken : episodeText(season: season, episode: episode) ?? spoken,
      progress: progress, accessibilityLabel: spoken, action: action)
  }

  /// 「继续播放 第 2 季第 5 集」「播放 第 2 季第 6 集」；缺编号时只写「继续播放」「播放」。
  static func title(resumes: Bool, season: Int?, episode: Int?) -> String {
    let verb = resumes ? "继续播放" : "播放"
    guard let text = episodeText(season: season, episode: episode) else { return verb }
    return "\(verb) \(text)"
  }

  /// 「第 2 季第 5 集」「特别篇第 1 集」；缺编号时为 nil。
  static func episodeText(season: Int?, episode: Int?) -> String? {
    guard let season, let episode else { return nil }
    let seasonText = season == 0 ? "特别篇" : "第 \(season) 季"
    return "\(seasonText)第 \(episode) 集"
  }
}

/// 详情页集列表默认显示的季，和要停在哪一集（按 TMDB 单集编号找，没有时按集号）。
struct EpisodeRowHint: Equatable {
  let season: Int
  var tmdbEpisodeID: Int? = nil
  var episodeNumber: Int? = nil

  var pointsAtEpisode: Bool { tmdbEpisodeID != nil || episodeNumber != nil }

  func episode(in episodes: some Collection<MoviePilotEpisode>) -> MoviePilotEpisode? {
    guard pointsAtEpisode else { return nil }
    if let tmdbEpisodeID, let hit = episodes.first(where: { $0.tmdbEpisodeID == tmdbEpisodeID }) { return hit }
    guard let episodeNumber else { return nil }
    return episodes.first { $0.episodeNumber == episodeNumber && $0.seasonNumber == season }
  }
}

/// 请集列表打开某一集的面板。`id` 每次不同：同一集连按两次也各打开一次。
struct EpisodePanelRequest: Equatable {
  let id = UUID()
  let hint: EpisodeRowHint
}
