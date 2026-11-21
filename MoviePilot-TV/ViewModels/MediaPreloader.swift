import Combine
import Foundation
import Kingfisher
import SwiftUI

enum MediaDetailBackgroundImage {
  nonisolated static let blurRadius: CGFloat = 60
  /// 详情背景按 2K 长边解码（2560×1440），不到 4K 屏幕也不上采样。
  nonisolated static let targetLongEdgePixels = MediaDetailImageSizing.longEdgePixels

  nonisolated static func downsampleScale(
    for pointSize: CGSize,
    screenScale: CGFloat
  ) -> CGFloat {
    let longEdge = max(pointSize.width, pointSize.height)
    guard longEdge > 0 else { return 1 }
    return min(screenScale, targetLongEdgePixels / longEdge)
  }

  nonisolated static func heroProcessor(
    for size: CGSize,
    usingPosterAsBackdrop: Bool,
    screenScale: CGFloat
  ) -> any ImageProcessor {
    usingPosterAsBackdrop
      ? posterFallbackProcessor(for: size, screenScale: screenScale)
      : heroDownsamplingProcessor(for: size, screenScale: screenScale)
  }

  nonisolated static func posterFallbackProcessor(
    for size: CGSize,
    screenScale: CGFloat
  ) -> any ImageProcessor {
    heroDownsamplingProcessor(for: size, screenScale: screenScale)
      |> BlurImageProcessor(blurRadius: blurRadius)
  }

  nonisolated static func heroDownsamplingProcessor(
    for size: CGSize,
    screenScale: CGFloat
  ) -> MediaDetailHeroDownsamplingProcessor {
    MediaDetailHeroDownsamplingProcessor(
      size: size,
      scale: downsampleScale(for: size, screenScale: screenScale)
    )
  }

  static func heroOptions(
    for size: CGSize,
    scaleFactor: CGFloat,
    usingPosterAsBackdrop: Bool
  ) -> KingfisherOptionsInfo {
    let scale = downsampleScale(for: size, screenScale: scaleFactor)
    return [
      .processor(
        heroProcessor(
          for: size,
          usingPosterAsBackdrop: usingPosterAsBackdrop,
          screenScale: scaleFactor
        )
      ),
      .scaleFactor(scale),
      TransientDecodedImage.skipMemoryCache,
    ]
  }

  nonisolated static func removePosterFallbackBackgroundFromMemory(
    for url: URL,
    size: CGSize,
    screenScale: CGFloat,
    cacheKey: String? = nil,
    cache: ImageCache = .default
  ) {
    cache.removeImage(
      forKey: cacheKey ?? url.cacheKey,
      processorIdentifier: posterFallbackProcessor(
        for: size,
        screenScale: screenScale
      ).identifier,
      fromMemory: true,
      fromDisk: false
    )
  }

  nonisolated static func removeFirstPageBackgroundFromMemory(
    for url: URL,
    size: CGSize,
    screenScale: CGFloat,
    cacheKey: String? = nil,
    cache: ImageCache = .default
  ) {
    cache.removeImage(
      forKey: cacheKey ?? url.cacheKey,
      processorIdentifier: heroProcessor(
        for: size,
        usingPosterAsBackdrop: false,
        screenScale: screenScale
      ).identifier,
      fromMemory: true,
      fromDisk: false
    )
  }

  nonisolated static func removeHeroFromMemory(
    for url: URL,
    size: CGSize,
    usingPosterAsBackdrop: Bool,
    screenScale: CGFloat,
    cacheKey: String? = nil,
    cache: ImageCache = .default
  ) {
    if usingPosterAsBackdrop {
      removePosterFallbackBackgroundFromMemory(
        for: url,
        size: size,
        screenScale: screenScale,
        cacheKey: cacheKey,
        cache: cache
      )
    } else {
      removeFirstPageBackgroundFromMemory(
        for: url,
        size: size,
        screenScale: screenScale,
        cacheKey: cacheKey,
        cache: cache
      )
    }
  }

  /// 预载可能写入主图和海报原图 fallback 两份处理后的 hero，释放时都要清。
  @MainActor
  static func backgroundHeroURLs(from detail: MediaInfo) -> (
    urls: [URL], isPoster: Bool
  ) {
    let target = detail.imageURLs.backgroundTarget
    var urls: [URL] = []
    if let url = target.url {
      urls.append(url)
    }
    if let fallbackURL = target.fallbackURL, fallbackURL != target.url {
      urls.append(fallbackURL)
    }
    return (urls, target.isPoster)
  }
}

/// 按指定 scale 做 ImageIO 缩略图解码。identifier 带目标长边像素，避免沿用旧的 4K `DownsamplingImageProcessor` 磁盘缓存。
struct MediaDetailHeroDownsamplingProcessor: ImageProcessor {
  let size: CGSize
  let scale: CGFloat

  var identifier: String {
    let longEdgePixels = Int((max(size.width, size.height) * scale).rounded())
    return "com.moviepilot.hero-downsample(\(Int(size.width))x\(Int(size.height)),\(longEdgePixels))"
  }

  func process(
    item: ImageProcessItem,
    options _: KingfisherParsedOptionsInfo
  ) -> KFCrossPlatformImage? {
    let data: Data?
    switch item {
    case .image(let image):
      data = image.kf.data(format: .unknown)
    case .data(let dataValue):
      data = dataValue
    }
    guard let data else { return nil }
    return KingfisherWrapper.downsampledImage(data: data, to: size, scale: scale)
  }
}

// MARK: - 单个媒体的预加载任务

/// 管理单个媒体项的所有预加载数据。
/// 作为 DetailView 和右键菜单的唯一数据源 (Single Source of Truth)。
@MainActor
class MediaPreloadTask: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  let partialMedia: MediaInfo
  private weak var apiService: APIService?

  // ⭐ 首屏可展示状态：完整详情已加载，且背景/海报已预取或等待超时
  @Published var fullDetail: MediaInfo?
  @Published var isDetailReady = false
  @Published private(set) var isDetailFailed = false
  @Published private(set) var detailRetryNumber: Int?
  /// 详情终止加载的原因，供过渡画面说明。
  @Published private(set) var detailFailureReason: String?
  /// 由预加载器提供：当前是否有导航页面持有本任务。只在预加载器的 owner 表里记录一份。
  fileprivate var isNavigationOwned: @MainActor () -> Bool = { false }

  // 可选预加载数据（持久存在，加载完直接显示）
  /// 名称识别得到的 ID，用于 TMDB 跳转。只凭片名猜出，电影等直接订阅的条目不按它补查订阅状态。
  @Published var tmdbId: Int?
  /// TMDB 跳转和目标详情预载使用的完整目标，保留独立的类型和季号。
  var tmdbTarget: MediaInfo? { tmdbResolution?.target }
  @Published private var tmdbResolution: TMDBTargetResolution?
  @Published var isTmdbRecognitionFinished = false
  /// 打开详情后才做的 TMDB 识别（按需查找，没找到再按名称识别）还没结束。
  @Published private(set) var isOpenedDetailTMDBPending = false
  /// 名称识别已确认没有匹配时用的片名、年份和类型。
  @Published private var unrecognizedQuery: RecognitionQuery?
  @Published var isSubscribed: Bool?
  @Published var seasonViewModel: SubscribeSeasonViewModel?
  /// 分季数据是否已实际加载完毕（seasonViewModel 创建时 isLoading=true，loadData 完成后才设为 true）
  @Published var isSeasonDataLoaded = false

  /// 编排识别、详情等待、分季、单集预览与订阅的任务（用于取消）
  private var internalTasks: [Task<Void, Never>] = []
  private var detailTask: Task<Void, Never>?
  private var isStarted = false

  /// 当前正在进行的 Kingfisher 图片下载任务（用于取消时中断 HTTP 请求）
  /// nonisolated(unsafe) 因为需要在 withTaskCancellationHandler 的 onCancel 闭包中访问，
  /// 该闭包可能在任意线程执行。实际写入只在 @MainActor 隔离的方法中进行，读取仅在取消时（单次），无竞争风险。
  nonisolated(unsafe) private var activeImageDownload: DownloadTask?
  private let imageRetrieveState = ImageRetrieveContinuationBox()
  private let imageWarmer: MPImageWarmer?
  private var activeImageWarmHandle: MPImageWarmer.Handle?
  private var allowsImageWarm = true

  init(
    partialMedia: MediaInfo, apiService: APIService? = .shared,
    preparedContent: TopShelfCachedContent? = nil
  ) {
    self.partialMedia = partialMedia
    self.apiService = apiService
    // 任务创建于所属会话内，此处解析的预热器即该会话的实例。
    imageWarmer = apiService?.imageWarmer
    installPreparedContentIfNeeded(preparedContent)
  }

  private(set) var preparedContent: TopShelfCachedContent?

  func installPreparedContentIfNeeded(_ content: TopShelfCachedContent?) {
    guard fullDetail == nil, let content, Self.hasDisplayableDetail(content.detail) else { return }
    // 本地完整详情可接管其他导航栈的在途请求，保留共享任务及其辅助数据。
    detailTask?.cancel()
    detailTask = nil
    preparedContent = content
    fullDetail = content.detail
    if isStarted {
      startEpisodePreview(for: content.detail)
    }
    isDetailReady = true
    isDetailFailed = false
    detailRetryNumber = nil
    detailFailureReason = nil
  }

  nonisolated static func hasDisplayableDetail(_ detail: MediaInfo) -> Bool {
    detail.title != nil || detail.tmdb_id != nil || detail.douban_id != nil
  }

  /// 启动所有预加载任务（幂等，多次调用不会重复启动）
  func start() {
    guard !isStarted else { return }
    isStarted = true

    // 只有带 collection_id 的合集走 CollectionDetailView，没有普通 media detail。
    // type 显示为合集但缺少 collection_id 时仍按普通媒体预加载，避免空合集 ID 卡住。
    guard partialMedia.shouldPreloadDetail else { return }

    if let fullDetail {
      startEpisodePreview(for: fullDetail)
    }
    let detailLoad = Task { await self.loadDetail() }
    detailTask = detailLoad
    internalTasks.append(
      Task {
        // 预读跳转映射，或对内置来源执行名称识别。打开详情后的按需查找独立运行。
        async let tmdbRecognition: Void = {
          if MediaIdentifier.validNumericIdentifier(self.partialMedia.tmdb_id) == nil,
            self.partialMedia.canJumpToTMDB
          {
            try await self.preloadTMDBTarget(using: self.partialMedia)
          }
        }()
        // 识别可能先抛出取消；基础详情结束前必须保留其取消句柄。
        await detailLoad.value
        self.detailTask = nil
        try? await tmdbRecognition
        guard !Task.isCancelled, let canonical = fullDetail else { return }

        // 卡片缺少可识别身份时，用完整详情补查，让 TMDB 按钮能够结束加载。
        if self.tmdbId == nil, !self.isTmdbRecognitionFinished,
          MediaIdentifier.validNumericIdentifier(canonical.tmdb_id) == nil,
          canonical.canJumpToTMDB
        {
          try? await self.preloadTMDBTarget(using: canonical)
        }

        await withTaskGroup(of: Void.self) { group in
          // ③ 分季信息（仅电视剧）
          group.addTask { await self.loadSeasonData(for: canonical) }
          // ④ 直接订阅状态，电视剧由分季流程处理。
          group.addTask { _ = await self.refreshDirectSubscription(for: canonical) }
        }
      })
  }

  /// 取消所有预加载任务（包括正在进行的 Kingfisher 图片下载）
  func cancel() {
    imageRetrieveState.markOwnerReleased()
    internalTasks.forEach { $0.cancel() }
    internalTasks.removeAll()
    detailTask?.cancel()
    detailTask = nil
    // 主动中断 Kingfisher 下载，释放网络资源和内存
    activeImageDownload?.cancel()
    activeImageDownload = nil
    cancelImageWarm()
  }

  var imageRetrieveGeneration: UInt {
    imageRetrieveState.generation
  }

  func shouldDiscardRetrievedBackground(generation: UInt) -> Bool {
    imageRetrieveState.shouldDiscardResult(generation: generation)
  }

  /// 当前媒体即将真正显示时，停止仅用于服务器缓存的 warm，并把已解码的候选背景交给前台复用。
  func cancelImageWarm() {
    allowsImageWarm = false
    if let activeImageWarmHandle, let imageWarmer {
      imageWarmer.cancel(activeImageWarmHandle)
      self.activeImageWarmHandle = nil
    }
    imageRetrieveState.keepResultInMemoryUnlessOwnerReleased()
  }

  func shouldWarmBackgroundImage() -> Bool {
    allowsImageWarm
  }

  func shouldReleasePreparedBackgroundFromMemory(preparedAsCandidate: Bool) -> Bool {
    preparedAsCandidate && allowsImageWarm
  }

  var shouldRemoveRetrievedBackgroundAfterCompletion: Bool {
    imageRetrieveState.shouldRemoveResultFromMemory
  }

  func markPreparedBackgroundForReleaseAfterCompletion() {
    imageRetrieveState.markCandidateResultForRemoval()
  }

  // MARK: - ① 加载完整媒体详情

  private func loadDetail() async {
    guard fullDetail == nil else { return }
    guard let uiIdentity = apiService?.uiIdentity,
      partialMedia.identity != nil, trimmedNonEmpty([partialMedia.type]) != nil
    else {
      markDetailFailed(reason: nil)
      return
    }

    var delay: Duration = .milliseconds(1500)
    var attempt = 0
    while true {
      guard !Task.isCancelled, let apiService, apiService.uiIdentity == uiIdentity else { return }
      attempt += 1
      let snapshot = apiService.sessionSnapshot()
      do {
        let fetched = try await apiService.fetchMediaDetail(media: partialMedia)
        try Task.checkCancellation()
        guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
        // 校验返回数据有效性：API 可能返回 200 但 body 是空/残缺 JSON
        // 此时 Codable 解码成功但所有字段为 nil，导致详情页显示 "Unknown" 空白页
        if Self.hasDisplayableDetail(fetched) {
          self.fullDetail = fetched
          startEpisodePreview(for: fetched)
          let backgroundImageTimeout: Duration =
            SystemViewModel.shouldWaitMediaDetailBackgroundImage ? .seconds(3) : .milliseconds(100)
          await self.prefetchBackgroundImage(for: fetched, timeout: backgroundImageTimeout)
          try Task.checkCancellation()
          detailRetryNumber = nil
          self.isDetailReady = true
          return
        } else {
          Logger.warning(
            "第 \(attempt) 次请求详情返回空数据",
            metadata: ["title": partialMedia.title ?? "", "mediaId": partialMedia.id]
          )
        }
      } catch {
        guard !Task.isCancelled, apiService.uiIdentity == uiIdentity else { return }
        Logger.error(
          "加载详情失败（第 \(attempt) 次，\(type(of: error))）",
          metadata: ["title": partialMedia.title ?? "", "mediaId": partialMedia.id]
        )
        // 会话已更换时，旧请求的错误不代表当前结果，按可重试处理。
        if apiService.isSessionUnchanged(from: snapshot), !Self.canRetryDetail(after: error) {
          markDetailFailed(reason: Self.detailFailureReason(for: error))
          return
        }
      }
      // 焦点候选只短暂预载。实际打开的详情在导航 owner 存活期间继续等待。
      if attempt >= 3, !isNavigationOwned() {
        markDetailFailed(reason: nil)
        return
      }
      detailRetryNumber = attempt
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      delay = min(delay * 2, .seconds(8))
    }
  }

  private func markDetailFailed(reason: String?) {
    isDetailFailed = true
    detailRetryNumber = nil
    detailFailureReason = reason
  }

  /// 连接故障、网关错误、5xx、空详情和同账号重登打断的请求会继续重试；
  /// 权限拒绝、4xx、业务失败和无法解析的响应重试也不会变化，直接停下并说明原因。
  nonisolated static func canRetryDetail(after error: Error) -> Bool {
    if error is CancellationError { return true }
    guard let error = error as? APIError else { return false }
    switch error {
    case .networkError, .gatewayStatus:
      return true
    case .serverMessage(let message):
      guard let status = APIService.httpStatusCode(fromServerMessage: message) else { return false }
      return status >= 500 || status == 408 || status == 429
    case .invalidURL, .decodingError, .authenticationChallenge, .credentialsRejected,
      .mfaUnsupported, .unauthorized, .unknown:
      return false
    }
  }

  nonisolated static func detailFailureReason(for error: Error) -> String? {
    trimmedNonEmpty([(error as? LocalizedError)?.errorDescription])
  }

  // MARK: - ② 预热背景图

  private func prefetchBackgroundImage(for detail: MediaInfo, timeout: Duration? = nil) async {
    // 避免为已取消（生命周期释放）的任务发起无意义的图片请求
    guard !Task.isCancelled else { return }
    guard let apiService, let imageWarmer else { return }
    // 与 MediaInfo.ImageURLs.backgroundTarget 保持一致：backdrop 优先，无则 poster
    let target = detail.imageURLs.backgroundTarget
    guard let url = target.url else { return }

    let preparedAsCandidate = shouldWarmBackgroundImage()

    let canWarmOnMoviePilot = MPImageWarmer.isWarmable(
      url,
      baseURL: apiService.baseURL,
      imageCacheEnabled: apiService.useImageCache
    )
    if preparedAsCandidate, canWarmOnMoviePilot {
      let handle = await imageWarmer.warm(url)
      guard !Task.isCancelled,
        shouldWarmBackgroundImage()
      else {
        if let handle {
          imageWarmer.cancel(handle)
        }
        return
      }
      activeImageWarmHandle = handle
      return
    }
    guard !Task.isCancelled else { return }

    if let timeout {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          await self.retrieveHeroImage(url, fallbackURL: target.fallbackURL)
        }
        group.addTask {
          try? await Task.sleep(for: timeout)
        }

        await group.next()
        group.cancelAll()
      }
    } else {
      await retrieveHeroImage(url, fallbackURL: target.fallbackURL)
    }

    // 下载完成后清理引用
    activeImageDownload = nil

    // 仍停留在推荐页时才释放候选图；进入详情后保留同一份内存图供前台直接复用。
    guard
      shouldReleasePreparedBackgroundFromMemory(preparedAsCandidate: preparedAsCandidate),
      !Task.isCancelled
    else { return }
    markPreparedBackgroundForReleaseAfterCompletion()
    let size = UIScreen.main.bounds.size
    let screenScale = UIScreen.main.scale
    let heroes = MediaDetailBackgroundImage.backgroundHeroURLs(from: detail)
    for heroURL in heroes.urls {
      removePreparedHeroFromMemory(
        url: heroURL,
        isUsingPosterAsBackdrop: heroes.isPoster,
        size: size,
        screenScale: screenScale
      )
    }
  }

  private func retrieveHeroImage(_ url: URL, fallbackURL: URL?) async {
    let isUsingPosterAsBackdrop = (fullDetail ?? partialMedia).imageURLs.backgroundTarget.isPoster
    let succeeded = await retrieveHeroImage(url, isUsingPosterAsBackdrop: isUsingPosterAsBackdrop)
    guard !succeeded, !Task.isCancelled, let fallbackURL, fallbackURL != url else { return }
    _ = await retrieveHeroImage(fallbackURL, isUsingPosterAsBackdrop: isUsingPosterAsBackdrop)
  }

  private func retrieveHeroImage(
    _ url: URL,
    isUsingPosterAsBackdrop: Bool
  ) async -> Bool {
    let continuationBox = ImageRetrieveContinuationBox()
    let retrieveGeneration = imageRetrieveState.generation
    let size = UIScreen.main.bounds.size
    let screenScale = UIScreen.main.scale
    var options = MediaDetailBackgroundImage.heroOptions(
      for: size,
      scaleFactor: screenScale,
      usingPosterAsBackdrop: isUsingPosterAsBackdrop
    )
    guard let service = apiService else { return false }
    let source = service.imageSource(for: url)
    options.append(contentsOf: service.imageOptions(for: url))

    // 使用 withTaskCancellationHandler 确保 Swift Task 取消时能中断 Kingfisher 的 HTTP 下载
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        continuationBox.set(continuation)
        self.activeImageDownload = KingfisherManager.shared.retrieveImage(
          with: source,
          options: options
        ) { result in
          if self.imageRetrieveState.shouldDiscardResult(generation: retrieveGeneration) {
            MediaDetailBackgroundImage.removeHeroFromMemory(
              for: url,
              size: size,
              usingPosterAsBackdrop: isUsingPosterAsBackdrop,
              screenScale: screenScale,
              cacheKey: source.cacheKey
            )
          }
          switch result {
          case .success:
            continuationBox.resume(returning: true)
          case .failure:
            continuationBox.resume(returning: false)
          }
        }
      }
    } onCancel: {
      // 此闭包可能在任意线程执行，直接取消 Kingfisher 下载任务
      self.activeImageDownload?.cancel()
      continuationBox.resume(returning: false)
    }
  }

  private func removePreparedHeroFromMemory(
    url: URL,
    isUsingPosterAsBackdrop: Bool,
    size: CGSize,
    screenScale: CGFloat
  ) {
    guard let apiService else { return }
    MediaDetailBackgroundImage.removeHeroFromMemory(
      for: url,
      size: size,
      usingPosterAsBackdrop: isUsingPosterAsBackdrop,
      screenScale: screenScale,
      cacheKey: apiService.imageSource(for: url).cacheKey
    )
  }

  // MARK: - ③ 分季信息

  private func loadSeasonData(for detail: MediaInfo) async {
    guard let apiService else { return }
    guard apiService.canAccess(.subscribe) else { return }
    guard detail.type == "电视剧" else { return }

    let vm = SubscribeSeasonViewModel(mediaInfo: detail, apiService: apiService)
    self.seasonViewModel = vm
    await vm.loadData(forceRefreshSubscriptions: false)
    self.isSeasonDataLoaded = true
  }

  private func startEpisodePreview(for detail: MediaInfo) {
    guard let apiService, let tmdbID = MediaDetailEpisodeSeasons.tmdbID(for: detail) else { return }
    guard !MediaDetailView.shouldShowSeasonSubscriptionSection(
      canSubscribeMedia: apiService.canAccess(.subscribe), detail: detail, isSeasonDataLoaded: true,
      seasonCount: detail.season_info?.count, hasSeasonLoadError: false
    ) else { return }

    let seasons = MediaDetailEpisodeSeasons.selectable(detail.season_info ?? []).compactMap(\.season_number)
    guard let season = MediaDetailEpisodeSeasons.current(
      selected: MediaDetailEpisodeSeasons.navigationSeason(for: detail, routeMedia: partialMedia),
      preferred: detail.season, available: seasons
    ) else { return }

    // 只预载首行的单集信息，进入详情后复用同一接口缓存。
    internalTasks.append(Task {
      do {
        try Task.checkCancellation()
        _ = try await apiService.fetchTmdbEpisodes(tmdbID: tmdbID, season: season, episodeGroup: nil)
      } catch is CancellationError {
        return
      } catch {
        Logger.debug("预载单集信息失败: \(type(of: error))")
      }
    })
  }

  // MARK: - ④ 订阅状态

  /// 电影订阅补查只接受同一来源条目、后端确认过的同类型目标（共享映射或按需查找）。
  /// 名称识别可能猜中同名同年的另一部，原影片的订阅状态、新建与取消都不能按它走。
  func mappedMovieTarget(for media: MediaInfo) -> MediaInfo? {
    guard let apiService, media.canDirectlySubscribe,
      MediaIdentifier.validNumericIdentifier(media.tmdb_id) == nil,
      let type = media.type, apiService.normalizeMediaType(type) == "movie",
      let resolution = tmdbResolution, !resolution.isNameRecognized,
      resolution.origin == media.identity, resolution.target.type == "电影"
    else { return nil }
    return resolution.target
  }

  func refreshDirectSubscription(for detail: MediaInfo, forceRefresh: Bool = false) async -> Bool {
    guard let apiService else { return false }
    guard apiService.canAccess(.subscribe) else {
      isSubscribed = false
      return true
    }
    guard detail.canDirectlySubscribe else { return false }

    let snapshot = apiService.sessionSnapshot()
    do {
      var subscribed = try await apiService.checkSubscription(
        media: detail, forceRefresh: forceRefresh
      )
      if !subscribed, let target = mappedMovieTarget(for: detail) {
        subscribed = try await apiService.checkSubscription(
          media: target, forceRefresh: forceRefresh, requireExactMovieIdentity: true
        )
      }
      try apiService.validateSessionSnapshot(snapshot)
      isSubscribed = subscribed
      return true
    } catch is CancellationError {
      return false
    } catch {
      Logger.error("[MediaPreloadTask] 检查订阅状态失败: \(error)")
      return false
    }
  }

  /// 外部触发刷新订阅状态（收到订阅变更通知时调用）
  func refreshSubscriptionStatus(forceRefreshSeasonSnapshot: Bool = true) async {
    guard let apiService else { return }
    guard apiService.canAccess(.subscribe) else {
      self.isSubscribed = false
      return
    }
    let detail = fullDetail ?? partialMedia
    if detail.canDirectlySubscribe {
      _ = await refreshDirectSubscription(for: detail, forceRefresh: true)
    } else if let seasonVM = seasonViewModel {
      // 电视剧：刷新分季订阅状态
      await seasonVM.checkSubscriptionStatus(forceRefresh: forceRefreshSeasonSnapshot)
    }
  }

  // MARK: - ⑤ TMDB 识别

  private func preloadTMDBTarget(using media: MediaInfo) async throws {
    guard let apiService else { throw CancellationError() }
    defer { isTmdbRecognitionFinished = true }

    do {
      if let target = try await MediaActionHandler.sharedTMDBTarget(
        for: media,
        apiService: apiService
      ) {
        self.tmdbResolution = target
        return
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      Logger.error("[MediaPreloadTask] TMDB 共享映射查询失败: \(error)")
    }

    // 能按需查找的条目等打开详情后再查找，没有结果时才按名称识别；焦点预载不占后端的查找名额。
    if MediaActionHandler.canMatchTMDB(for: media, apiService: apiService) {
      isOpenedDetailTMDBPending = true
      return
    }
    // 插件等其他来源不静默识别，用户按下 TMDB 时再识别。
    guard MediaActionHandler.hasBuiltInTMDBConversion(for: media) else { return }

    // 预加载识别失败静默处理：不弹提示，也不伪装 no-match。
    // 取消向上传播，避免取消后仍继续启动依赖任务（分季/订阅 fallback 补查）。
    let result: Int?
    do {
      result = try await apiService.recognizeTmdbId(
        title: media.title ?? "",
        year: media.year,
        type: media.type
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return
    }
    applyRecognition(result, for: media, apiService: apiService)
  }

  /// 写入名称识别结论：找到时同时记下带原来源身份的目标，没找到时记下已确认无匹配。
  private func applyRecognition(
    _ result: Int?, for media: MediaInfo, season: Int?? = nil, apiService: APIService
  ) {
    guard let tmdbId = MediaIdentifier.validNumericIdentifier(result) else {
      let query = RecognitionQuery(media)
      unrecognizedQuery = query.title.isEmpty ? nil : query
      return
    }
    self.tmdbId = tmdbId
    if let target = MediaActionHandler.recognizedTMDBTarget(
      for: media, tmdbId: tmdbId, season: season, apiService: apiService)
    {
      tmdbResolution = target
    }
  }

  /// 由已打开的详情页启动，分季和订阅的首次加载不等待这个长请求。
  /// 按需查找没有结果（含失败）时按名称识别，结论与预载识别写法相同。
  /// 被取消时保留待办，详情页再次显示时重新开始。
  func matchTMDBForOpenedDetail(_ detail: MediaInfo) async {
    guard let apiService, isOpenedDetailTMDBPending else { return }
    guard MediaIdentifier.validNumericIdentifier(detail.tmdb_id) == nil, detail.canJumpToTMDB else {
      isOpenedDetailTMDBPending = false
      return
    }

    // 完整详情可能只返回整剧。来源与类型一致时保留卡片预读过的明确季号，映射按卡片的季查；
    // 名称识别仍用完整详情的片名和年份，卡片简称可能识别到另一部作品。
    let keepsCardSeason =
      detail.season == nil && partialMedia.season != nil
      && detail.identity == partialMedia.identity && detail.type == partialMedia.type
    let mappingMedia = keepsCardSeason ? partialMedia : detail
    let snapshot = apiService.sessionSnapshot()
    do {
      if let target = try await MediaActionHandler.mappedTMDBTarget(
        for: mappingMedia, apiService: apiService)
      {
        try apiService.validateSessionSnapshot(snapshot)
        tmdbResolution = target
      } else {
        let result = try await apiService.recognizeTmdbId(
          title: detail.title ?? "", year: detail.year, type: detail.type)
        try apiService.validateSessionSnapshot(snapshot)
        applyRecognition(
          result, for: detail, season: .some(mappingMedia.season), apiService: apiService)
      }
    } catch {
      if error is CancellationError || Task.isCancelled { return }
      // 失败不弹提示，用户按下 TMDB 时再识别一次。
      Logger.error("[MediaPreloadTask] TMDB 识别失败: \(error)")
    }
    isOpenedDetailTMDBPending = false

    if isSubscribed != true, mappedMovieTarget(for: detail) != nil {
      _ = await refreshDirectSubscription(for: detail)
    }
  }

  /// 已确认按 `media` 当前的片名、年份和类型识别不到。卡片用简称没识别到时，
  /// 完整详情的正式片名还要再识别一次。
  func isTMDBUnrecognized(for media: MediaInfo) -> Bool {
    unrecognizedQuery != nil && unrecognizedQuery == RecognitionQuery(media)
  }

  /// 等预载和打开详情后的 TMDB 识别结束；调用方随后读取 `tmdbTarget` / `tmdbId`。
  func waitForTMDBIdentification() async {
    // 不给 Combine 传闭包：闭包会继承主线程隔离，而 Combine 在别的线程调用它。
    let states = $isTmdbRecognitionFinished.combineLatest($isOpenedDetailTMDBPending).values
    for await (finished, pending) in states where finished && !pending {
      return
    }
  }
}

/// 名称识别实际使用的参数，用来判断“没有匹配”的结论是否适用于另一份详情。
private struct RecognitionQuery: Equatable {
  let title: String
  let year: String?
  let type: String?

  init(_ media: MediaInfo) {
    title = media.title?.trimmingCharacters(in: .whitespaces) ?? ""
    year = media.year
    type = media.type
  }
}

private final class ImageRetrieveContinuationBox: @unchecked Sendable {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  private let lock = NSLock()
  nonisolated(unsafe) private var continuation: CheckedContinuation<Bool, Never>?
  nonisolated(unsafe) private var pendingResult: Bool?
  nonisolated(unsafe) private var hasResumed = false
  nonisolated(unsafe) private var removeResultFromMemory = false
  nonisolated(unsafe) private var ownerReleased = false
  nonisolated(unsafe) private var retrieveGeneration: UInt = 0

  nonisolated var generation: UInt {
    lock.lock()
    defer { lock.unlock() }
    return retrieveGeneration
  }

  nonisolated var shouldRemoveResultFromMemory: Bool {
    lock.lock()
    defer { lock.unlock() }
    return removeResultFromMemory
  }

  nonisolated func shouldDiscardResult(generation: UInt) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return removeResultFromMemory || generation != retrieveGeneration
  }

  nonisolated func markOwnerReleased() {
    lock.lock()
    ownerReleased = true
    removeResultFromMemory = true
    retrieveGeneration &+= 1
    lock.unlock()
  }

  nonisolated func markCandidateResultForRemoval() {
    lock.lock()
    removeResultFromMemory = true
    lock.unlock()
  }

  nonisolated func keepResultInMemoryUnlessOwnerReleased() {
    lock.lock()
    if !ownerReleased {
      removeResultFromMemory = false
    }
    lock.unlock()
  }

  nonisolated func set(_ continuation: CheckedContinuation<Bool, Never>) {
    lock.lock()
    if let pendingResult {
      hasResumed = true
      self.pendingResult = nil
      lock.unlock()
      continuation.resume(returning: pendingResult)
      return
    }

    self.continuation = continuation
    lock.unlock()
  }

  nonisolated func resume(returning result: Bool) {
    lock.lock()
    guard !hasResumed else {
      lock.unlock()
      return
    }

    if let continuation {
      hasResumed = true
      self.continuation = nil
      lock.unlock()
      continuation.resume(returning: result)
    } else {
      pendingResult = result
      lock.unlock()
    }
  }
}

// MARK: - 预加载管理器

/// 管理所有媒体的预加载任务缓存。
/// MediaCard 聚焦时触发预加载，ContainerView 和右键菜单读取预加载结果。
/// 由 `SessionScope` 按会话持有：换账号或登出时整体拆除，因此这里不再自行监听会话变化。
@MainActor
class MediaPreloader: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 预加载任务缓存，key = MediaInfo.id
  private var cache: [String: MediaPreloadTask] = [:]
  /// 尚未进入详情页的临时焦点候选。新候选出现时立即释放旧候选。
  private var candidateKey: String?
  private var candidateStackID: UUID?
  /// 仍存在于导航栈中的详情页 owner；同一媒体可以在栈中出现多次。
  private var navigationOwners: [String: Set<UUID>] = [:]
  /// 当前实际挂载详情背景的 route owner；跨 Tab 共用，避免一个栈误删另一个栈的 hero。
  private var presentedHeroOwners: [String: Set<UUID>] = [:]
  private var presentedHeroKeyByOwner: [UUID: String] = [:]
  private var presentedHeroDetailByOwner: [UUID: MediaInfo] = [:]
  /// Pop 回列表后，阻止焦点恢复立即重新预载刚退出的媒体。
  private var suppressedFocusCandidateKeys: [UUID: String] = [:]
  /// 详情页附带预载（如 TMDB 跳转目标），不占用焦点 candidateKey。
  private var auxiliaryPreloads: [UUID: Set<String>] = [:]
  private static let legacyNavigationOwner = UUID()
  private var cancellables = Set<AnyCancellable>()
  private var subscriptionRefreshTask: Task<Void, Never>?
  // 服务拥有预载缓存；缓存及其子任务只在执行操作期间保留服务。
  private weak var apiService: APIService?

  init(apiService: APIService) {
    self.apiService = apiService
    // 监听订阅变更通知，刷新活跃详情页持有的 task 的订阅状态
    NotificationCenter.default.publisher(for: .subscriptionDidUpdate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.subscriptionRefreshTask?.cancel()
        self.subscriptionRefreshTask = Task { [weak self] in
          await self?.refreshAllSubscriptionStatus()
        }
      }
      .store(in: &cancellables)
  }

  /// 会话结束时同步拆除：清空缓存并停止接收订阅变更通知。
  func tearDown() {
    clearAll()
    cancellables.removeAll()
  }

  /// 获取已有预加载任务，或创建并启动新任务
  @discardableResult
  func preload(
    for media: MediaInfo, startImmediately: Bool = true, preparedContent: TopShelfCachedContent? = nil
  ) -> MediaPreloadTask {
    let key = media.id
    if let existing = cache[key] {
      // 重启失败的候选预载，同时保留仍由导航栈持有的任务。
      if existing.isDetailFailed, navigationOwners[key] == nil {
        existing.cancel()
        cache.removeValue(forKey: key)
      } else {
        existing.installPreparedContentIfNeeded(preparedContent)
        if startImmediately { existing.start() }
        return existing
      }
    }

    // 创建新任务
    let task = MediaPreloadTask(
      partialMedia: media, apiService: apiService, preparedContent: preparedContent
    )
    task.isNavigationOwned = { [weak self] in self?.navigationOwners[key] != nil }
    guard apiService != nil else {
      task.cancel()
      return task
    }
    cache[key] = task
    if startImmediately { task.start() }

    return task
  }

  /// 仅为需要普通媒体详情的对象创建预加载任务。
  /// 合集由 CollectionDetailView 自己分页加载，不应进入普通详情预加载缓存。
  @discardableResult
  func preloadIfNeeded(
    for media: MediaInfo, stackID: UUID = MediaPreloader.legacyNavigationOwner
  ) -> MediaPreloadTask? {
    guard media.shouldPreloadDetail else { return nil }
    replaceCandidate(with: media.id, stackID: stackID)
    return preload(for: media)
  }

  /// 给当前详情页附带预载，不抢走推荐页焦点候选。
  @discardableResult
  func preloadAuxiliary(for media: MediaInfo, owner: UUID) -> MediaPreloadTask? {
    guard media.shouldPreloadDetail else { return nil }
    let key = media.id
    let previous = auxiliaryPreloads[owner] ?? []
    auxiliaryPreloads[owner] = [key]
    let task = preload(for: media)
    for staleKey in previous where staleKey != key {
      releaseTask(
        forKey: staleKey,
        fallbackMedia: cache[staleKey]?.partialMedia,
        size: UIScreen.main.bounds.size
      )
    }
    return task
  }

  func isFocusCandidate(_ key: String) -> Bool {
    candidateKey == key
  }

  /// 仅供焦点停留触发的预载。刚 Pop 的同一媒体会被抑制，显式点击不受影响。
  @discardableResult
  func preloadFocusedCandidateIfNeeded(
    for media: MediaInfo,
    stackID: UUID = MediaPreloader.legacyNavigationOwner
  ) -> MediaPreloadTask? {
    guard suppressedFocusCandidateKeys[stackID] != media.id else { return nil }
    return preloadIfNeeded(for: media, stackID: stackID)
  }

  /// 焦点真正移动到另一项后，解除上一次 Pop 的单次抑制。
  func focusDidMove(to key: String, stackID: UUID = MediaPreloader.legacyNavigationOwner) {
    guard let suppressedKey = suppressedFocusCandidateKeys[stackID], suppressedKey != key else {
      return
    }
    suppressedFocusCandidateKeys.removeValue(forKey: stackID)
  }

  func isFocusPreloadSuppressed(
    for key: String,
    stackID: UUID = MediaPreloader.legacyNavigationOwner
  ) -> Bool {
    suppressedFocusCandidateKeys[stackID] == key
  }

  /// 栈终态销毁后不会再回到原焦点，不保留其 Pop 抑制状态。
  func releaseStack(_ stackID: UUID) {
    suppressedFocusCandidateKeys.removeValue(forKey: stackID)
    if candidateStackID == stackID, let key = candidateKey {
      candidateKey = nil
      candidateStackID = nil
      releaseTask(forKey: key, fallbackMedia: cache[key]?.partialMedia, size: UIScreen.main.bounds.size)
    }
  }

  /// Push 前用稳定 route ID 获取预加载任务和所有权；不再等待 destination onAppear 交接。
  @discardableResult
  func acquireNavigation(
    for media: MediaInfo, owner: UUID, startImmediately: Bool = true,
    preparedContent: TopShelfCachedContent? = nil
  ) -> MediaPreloadTask? {
    guard media.shouldPreloadDetail else { return nil }
    replaceCandidate(with: media.id)
    let task = preload(
      for: media, startImmediately: startImmediately, preparedContent: preparedContent
    )
    pin(key: media.id, owner: owner)
    return task
  }

  /// 仅获取已有的预加载任务（不创建新的）。
  func getTask(for media: MediaInfo) -> MediaPreloadTask? {
    cache[media.id]
  }

  /// 纯读取：仅查询缓存中是否存在对应任务，不改变任何生命周期所有权。
  /// 可安全在 SwiftUI body / contextMenu @ViewBuilder 中使用。
  func peekTask(for media: MediaInfo) -> MediaPreloadTask? {
    return cache[media.id]
  }

  // MARK: - 导航生命周期

  /// 兼容现有测试和非导航调用；生产详情页应传入自己的 owner。
  func pin(key: String) {
    pin(key: key, owner: Self.legacyNavigationOwner)
  }

  func unpin(key: String) {
    unpin(key: key, owner: Self.legacyNavigationOwner)
  }

  /// 标记详情页仍存在于 NavigationPath 中。被子页面覆盖时不解除。
  func pin(key: String, owner: UUID) {
    // 首页/订阅等入口可能直接 append NavigationPath，没有经过焦点候选交接。
    // 新详情接管时立即释放旧的临时候选，避免它脱离任何生命周期长期留在缓存里。
    let previousCandidate = candidateKey
    candidateKey = nil
    candidateStackID = nil
    if let previousCandidate, previousCandidate != key {
      releaseTask(
        forKey: previousCandidate,
        fallbackMedia: cache[previousCandidate]?.partialMedia,
        size: UIScreen.main.bounds.size
      )
    }
    navigationOwners[key, default: []].insert(owner)
  }

  private func unpin(key: String, owner: UUID) {
    navigationOwners[key]?.remove(owner)
    if navigationOwners[key]?.isEmpty == true {
      navigationOwners.removeValue(forKey: key)
    }
  }

  /// typed route 被终态移除后释放 owner；同媒体仍被其他 route 持有时不会取消共享任务。
  func releaseNavigation(
    for media: MediaInfo,
    owner: UUID,
    stackID: UUID,
    size: CGSize,
    imageCache: ImageCache = .default
  ) {
    let key = media.id
    setHeroPresented(false, for: media, owner: owner, size: size, imageCache: imageCache)
    unpin(key: key, owner: owner)
    suppressedFocusCandidateKeys[stackID] = key
    releaseAuxiliaryPreloads(ownedBy: owner, size: size, imageCache: imageCache)
    releaseTask(forKey: key, fallbackMedia: media, size: size, imageCache: imageCache)
  }

  func setHeroPresented(
    _ isPresented: Bool,
    for detail: MediaInfo,
    owner: UUID,
    size: CGSize,
    screenScale: CGFloat = UIScreen.main.scale,
    imageCache: ImageCache = .default
  ) {
    let key = detail.id
    if isPresented {
      if let previousKey = presentedHeroKeyByOwner[owner], previousKey != key {
        releasePresentedHero(owner: owner, size: size, screenScale: screenScale, imageCache: imageCache)
      }
      presentedHeroOwners[key, default: []].insert(owner)
      presentedHeroKeyByOwner[owner] = key
      presentedHeroDetailByOwner[owner] = detail
      return
    }

    releasePresentedHero(owner: owner, size: size, screenScale: screenScale, imageCache: imageCache)
  }

  /// 通过 mediaId（如 "tmdb:123"）查找对应的预加载任务。
  /// 用于 SubscribeSheet 关闭后回写订阅状态。
  func findTask(byMediaId mediaId: String) -> MediaPreloadTask? {
    guard !mediaId.isEmpty else { return nil }
    // 直接匹配 partialMedia 的 apiMediaId
    if let task = cache.values.first(where: { $0.partialMedia.apiMediaId == mediaId }) {
      return task
    }
    // 补充匹配：subscribe 的 mediaId 可能是 tmdb:xxx（后端用 TMDB 存储），
    // 但 task 的 partialMedia 是豆瓣/Bangumi 来源，通过预加载识别的 tmdbId 匹配
    if mediaId.hasPrefix("tmdb:"),
      let tmdbIdStr = mediaId.split(separator: ":").last,
      let tmdbId = Int(tmdbIdStr)
    {
      return cache.values.first(where: { $0.tmdbId == tmdbId })
    }
    return nil
  }

  // MARK: - 全局清理（登出/切换服务器时调用）

  /// 取消所有预加载任务并清空缓存。
  func clearAll() {
    subscriptionRefreshTask?.cancel()
    subscriptionRefreshTask = nil
    for task in cache.values {
      task.cancel()
    }
    cache.removeAll()
    candidateKey = nil
    candidateStackID = nil
    navigationOwners.removeAll()
    presentedHeroOwners.removeAll()
    presentedHeroKeyByOwner.removeAll()
    presentedHeroDetailByOwner.removeAll()
    auxiliaryPreloads.removeAll()
    suppressedFocusCandidateKeys.removeAll()
  }

  // MARK: - 订阅状态批量刷新

  /// 收到订阅变更通知后，刷新活跃详情页持有的 task 的订阅状态。
  /// 普通海报墙预加载缓存不主动强刷，避免浏览海报墙后一次通知触发大量订阅查询。
  private func refreshAllSubscriptionStatus() async {
    guard let apiService else { return }
    let snapshot = apiService.sessionSnapshot()
    let tasks = navigationOwners.keys.compactMap { cache[$0] }
    guard !tasks.isEmpty else { return }

    if tasks.contains(where: { $0.seasonViewModel != nil }) {
      do {
        _ = try await apiService.fetchSubscriptions(forceRefresh: true)
      } catch is CancellationError {
        return
      } catch {
        // 单个 task 随后仍可各自刷新；这里只负责预热共享订阅快照。
      }
    }
    guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot) else { return }

    for task in tasks {
      guard !Task.isCancelled, apiService.isSessionUnchanged(from: snapshot) else { return }
      await task.refreshSubscriptionStatus(forceRefreshSeasonSnapshot: false)
    }
  }

  // MARK: - 临时候选与释放

  private func replaceCandidate(
    with key: String, stackID: UUID = MediaPreloader.legacyNavigationOwner
  ) {
    if candidateKey == key {
      candidateStackID = stackID
      return
    }
    let previousKey = candidateKey
    candidateKey = navigationOwners[key] == nil ? key : nil
    candidateStackID = candidateKey == nil ? nil : stackID
    if let previousKey {
      releaseTask(
        forKey: previousKey,
        fallbackMedia: cache[previousKey]?.partialMedia,
        size: UIScreen.main.bounds.size
      )
    }
  }

  private func releaseAuxiliaryPreloads(
    ownedBy owner: UUID,
    size: CGSize,
    imageCache: ImageCache
  ) {
    let keys = auxiliaryPreloads.removeValue(forKey: owner) ?? []
    for key in keys {
      releaseTask(
        forKey: key,
        fallbackMedia: cache[key]?.partialMedia,
        size: size,
        imageCache: imageCache
      )
    }
  }

  private func releasePresentedHero(
    owner: UUID,
    size: CGSize,
    screenScale: CGFloat,
    imageCache: ImageCache
  ) {
    guard let key = presentedHeroKeyByOwner.removeValue(forKey: owner) else { return }
    let detail = presentedHeroDetailByOwner.removeValue(forKey: owner)
    presentedHeroOwners[key]?.remove(owner)
    guard presentedHeroOwners[key]?.isEmpty != false else { return }
    presentedHeroOwners.removeValue(forKey: key)
    guard let resolvedDetail = cache[key]?.fullDetail ?? detail else { return }
    removeBackgroundTargetHeroesFromMemory(
      for: resolvedDetail,
      size: size,
      screenScale: screenScale,
      imageCache: imageCache
    )
  }

  func removeBackgroundTargetHeroesFromMemory(
    for detail: MediaInfo,
    size: CGSize,
    screenScale: CGFloat = UIScreen.main.scale,
    imageCache: ImageCache = .default
  ) {
    guard let apiService else { return }
    let heroes = MediaDetailBackgroundImage.backgroundHeroURLs(from: detail)
    for url in heroes.urls {
      let cacheKey = apiService.imageSource(for: url).cacheKey
      MediaDetailBackgroundImage.removeHeroFromMemory(
        for: url,
        size: size,
        usingPosterAsBackdrop: heroes.isPoster,
        screenScale: screenScale,
        cacheKey: cacheKey,
        cache: imageCache
      )
      if !heroes.isPoster {
        MediaDetailBackgroundImage.removePosterFallbackBackgroundFromMemory(
          for: url,
          size: size,
          screenScale: screenScale,
          cacheKey: cacheKey,
          cache: imageCache
        )
      }
    }
  }

  private func releaseTask(
    forKey key: String,
    fallbackMedia: MediaInfo?,
    size: CGSize,
    imageCache: ImageCache = .default
  ) {
    guard !isTaskRetained(key) else { return }
    let task = cache.removeValue(forKey: key)
    let detail = task?.fullDetail ?? fallbackMedia ?? task?.partialMedia
    task?.cancel()

    guard let detail else { return }
    removeBackgroundTargetHeroesFromMemory(for: detail, size: size, imageCache: imageCache)
  }

  private func isTaskRetained(_ key: String) -> Bool {
    candidateKey == key
      || navigationOwners[key] != nil
      || auxiliaryPreloads.values.contains { $0.contains(key) }
  }
}
