import Combine
import Foundation
import Kingfisher
import SwiftUI

enum MediaDetailBackgroundImage {
  nonisolated static let blurRadius: CGFloat = 60
  /// 详情背景按 2K 长边解码（2560×1440），不到 4K 屏幕也不上采样。
  nonisolated static let targetLongEdgePixels: CGFloat = 2560

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

enum MediaDetailLoadingPoster {
  nonisolated static let size = CGSize(width: 460, height: 690)

  nonisolated static var processor: DownsamplingImageProcessor {
    DownsamplingImageProcessor(size: size)
  }

  nonisolated static func removeFromMemory(
    for url: URL,
    cacheKey: String? = nil,
    cache: ImageCache = .default
  ) {
    cache.removeImage(
      forKey: cacheKey ?? url.cacheKey,
      processorIdentifier: processor.identifier,
      fromMemory: true,
      fromDisk: false
    )
  }
}

struct PageImageSnapshot: Equatable {
  let mediaPosterURLs: Set<URL>
  let personImageURLs: Set<URL>
  let isComplete: Bool

  init(
    mediaPosterURLs: Set<URL> = [],
    personImageURLs: Set<URL> = [],
    isComplete: Bool = true
  ) {
    self.mediaPosterURLs = mediaPosterURLs
    self.personImageURLs = personImageURLs
    self.isComplete = isComplete
  }
}

/// 页面级图片清理目标。只保存 URL 快照和待清理 URL；不会持有页面、ViewModel 或下载任务。
@MainActor
final class PageImageCleanupTarget {
  fileprivate var snapshot: PageImageSnapshot?
  fileprivate var pendingMediaPosterURLs: Set<URL> = []
  fileprivate var pendingPersonImageURLs: Set<URL> = []
  fileprivate var forwardingTarget: PageImageCleanupTarget?
  fileprivate var isDiscarded = false

  var currentSnapshot: PageImageSnapshot? { snapshot }
}

private struct MediaNavigationStackIDKey: EnvironmentKey {
  static let defaultValue = UUID()
}

extension EnvironmentValues {
  var mediaNavigationStackID: UUID {
    get { self[MediaNavigationStackIDKey.self] }
    set { self[MediaNavigationStackIDKey.self] = newValue }
  }
}

private struct PendingMediaNavigation {
  let mediaKey: String
  let stackID: UUID
  let expectedPathDepth: Int
}

// MARK: - 单个媒体的预加载任务

/// 管理单个媒体项的所有预加载数据。
/// 作为 DetailView 和右键菜单的唯一数据源 (Single Source of Truth)。
@MainActor
class MediaPreloadTask: ObservableObject {
  let partialMedia: MediaInfo
  private let apiService: APIService

  // ⭐ 首屏可展示状态：完整详情已加载，且背景/海报已预取或等待超时
  @Published var fullDetail: MediaInfo?
  @Published var isDetailReady = false
  @Published var isDetailFailed = false

  // 可选预加载数据（持久存在，加载完直接显示）
  @Published var tmdbId: Int?
  @Published var isTmdbRecognitionFinished = false
  @Published var isSubscribed: Bool?
  @Published var seasonViewModel: SubscribeSeasonViewModel?
  /// 分季数据是否已实际加载完毕（seasonViewModel 创建时 isLoading=true，loadData 完成后才设为 true）
  @Published var isSeasonDataLoaded = false

  /// 所有内部异步任务（用于取消）
  private var internalTasks: [Task<Void, Never>] = []
  private var isStarted = false

  /// 当前正在进行的 Kingfisher 图片下载任务（用于取消时中断 HTTP 请求）
  /// nonisolated(unsafe) 因为需要在 withTaskCancellationHandler 的 onCancel 闭包中访问，
  /// 该闭包可能在任意线程执行。实际写入只在 @MainActor 隔离的方法中进行，读取仅在取消时（单次），无竞争风险。
  nonisolated(unsafe) private var activeImageDownload: DownloadTask?
  private let imageRetrieveState = ImageRetrieveContinuationBox()
  private var activeImageWarmHandle: MPImageWarmer.Handle?
  private var allowsImageWarm = true

  init(partialMedia: MediaInfo, apiService: APIService = .shared) {
    self.partialMedia = partialMedia
    self.apiService = apiService
  }

  /// 启动所有预加载任务（幂等，多次调用不会重复启动）
  func start() {
    guard !isStarted else { return }
    isStarted = true

    // 只有带 collection_id 的合集走 CollectionDetailView，没有普通 media detail。
    // type 显示为合集但缺少 collection_id 时仍按普通媒体预加载，避免空合集 ID 卡住。
    guard partialMedia.shouldPreloadDetail else { return }

    internalTasks.append(
      Task {
        // ⑤ TMDB 识别 — 必须先于 checkSubscription 完成，否则 fallback 查询会因 tmdbId 为 nil 而跳过
        // 与 loadDetail 并发启动（两者互不依赖），但都在依赖任务之前完成
        async let tmdbRecognition: Void = {
          if self.partialMedia.tmdb_id == nil && self.partialMedia.canJumpToTMDB {
            try await self.recognizeTmdb()
          }
        }()
        async let detailLoad: Void = self.loadDetail()

        // 等待两者都完成；识别被取消时提前结束，不再启动依赖任务
        try? await (tmdbRecognition, detailLoad)
        guard !Task.isCancelled else { return }

        // 无论成功还是失败，都尝试加载依赖任务（失败时用 partialMedia 做 fallback）
        let mediaForDeps = fullDetail ?? partialMedia
        await withTaskGroup(of: Void.self) { group in
          // ③ 分季信息（仅电视剧）
          group.addTask { await self.loadSeasonData(for: mediaForDeps) }
          // ④ 订阅状态（此时 self.tmdbId 已就绪，可正确执行 fallback 查询）
          group.addTask { await self.checkSubscription(for: mediaForDeps) }
        }
      })
  }

  /// 取消所有预加载任务（包括正在进行的 Kingfisher 图片下载）
  func cancel() {
    imageRetrieveState.markOwnerReleased()
    internalTasks.forEach { $0.cancel() }
    internalTasks.removeAll()
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
    if let activeImageWarmHandle {
      MPImageWarmer.shared.cancel(activeImageWarmHandle)
      self.activeImageWarmHandle = nil
    }
    imageRetrieveState.keepResultInMemoryUnlessOwnerReleased()
  }

  func shouldWarmBackgroundImage(memoryOptimizationEnabled: Bool) -> Bool {
    memoryOptimizationEnabled && allowsImageWarm
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
    let maxRetries = 2
    for attempt in 0...maxRetries {
      if Task.isCancelled { return }
      do {
        let fetched = try await apiService.fetchMediaDetail(media: partialMedia)
        // 校验返回数据有效性：API 可能返回 200 但 body 是空/残缺 JSON
        // 此时 Codable 解码成功但所有字段为 nil，导致详情页显示 "Unknown" 空白页
        if fetched.title != nil || fetched.tmdb_id != nil || fetched.douban_id != nil {
          self.fullDetail = fetched
          let backgroundImageTimeout: Duration =
            SystemViewModel.shouldWaitMediaDetailBackgroundImage ? .seconds(3) : .milliseconds(100)
          await self.prefetchBackgroundImage(for: fetched, timeout: backgroundImageTimeout)
          self.isDetailReady = true
          return
        } else {
          Logger.warning(
            "第 \(attempt + 1) 次请求详情返回空数据，等待重试",
            metadata: ["title": partialMedia.title ?? "", "mediaId": partialMedia.id]
          )
          if attempt < maxRetries {
            try await Task.sleep(nanoseconds: 1_500_000_000)  // 等待 1.5 秒后重试
          }
        }
      } catch {
        Logger.error(
          "加载详情失败(attempt \(attempt + 1)): \(error)",
          metadata: ["title": partialMedia.title ?? "", "mediaId": partialMedia.id]
        )
        if attempt < maxRetries {
          try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else {
          markDetailFailed()
          return
        }
      }
    }
    Logger.error(
      "API 重试后仍返回空数据，视为失败",
      metadata: ["title": partialMedia.title ?? "", "mediaId": partialMedia.id]
    )
    markDetailFailed()
  }

  /// 详情连续失败终态：置失败标志并交由全局通知提示用户。
  private func markDetailFailed() {
    isDetailFailed = true
    NotificationCenter.default.post(name: .mediaDetailLoadDidFail, object: nil)
  }

  // MARK: - ② 预热背景图

  private func prefetchBackgroundImage(for detail: MediaInfo, timeout: Duration? = nil) async {
    // 避免为已取消（生命周期释放）的任务发起无意义的图片请求
    guard !Task.isCancelled else { return }
    // 与 MediaInfo.ImageURLs.backgroundTarget 保持一致：backdrop 优先，无则 poster
    let target = detail.imageURLs.backgroundTarget
    guard let url = target.url else { return }

    let preparedAsCandidate = shouldWarmBackgroundImage(
      memoryOptimizationEnabled: MemoryOptimizationPolicy.shared.isEnabled
    )

    if preparedAsCandidate {
      let handle = await MPImageWarmer.shared.warm(url)
      guard !Task.isCancelled,
        shouldWarmBackgroundImage(memoryOptimizationEnabled: true)
      else {
        if let handle {
          MPImageWarmer.shared.cancel(handle)
        }
        return
      }
      activeImageWarmHandle = handle
      return
    }

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
    let service = apiService
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
    guard apiService.canAccess(.subscribe) else { return }
    guard detail.type == "电视剧" else { return }

    let vm = SubscribeSeasonViewModel(mediaInfo: detail, apiService: apiService)
    self.seasonViewModel = vm
    await vm.loadData(forceRefreshSubscriptions: false)
    self.isSeasonDataLoaded = true
  }

  // MARK: - ④ 订阅状态

  private func checkSubscription(for detail: MediaInfo) async {
    guard apiService.canAccess(.subscribe) else {
      self.isSubscribed = false
      return
    }
    // 电视剧的订阅是分季维度，由 seasonViewModel 内部处理，预加载阶段不查全局订阅
    guard detail.canDirectlySubscribe else { return }

    do {
      var subscribed = try await apiService.checkSubscription(media: detail)
      // 豆瓣/Bangumi 来源：后端通常用 TMDB ID 存储订阅，
      // 当用原始 mediaId（如 douban:xxx）查不到时，用识别到的 tmdbId 补查一次
      if !subscribed, detail.tmdb_id == nil, let tmdbId = self.tmdbId {
        let tmdbMedia = MediaInfo(tmdb_id: tmdbId, type: detail.type)
        subscribed = try await apiService.checkSubscription(media: tmdbMedia)
      }
      self.isSubscribed = subscribed
    } catch {
      print("[MediaPreloadTask] 检查订阅状态失败: \(error)")
    }
  }

  /// 外部触发刷新订阅状态（收到订阅变更通知时调用）
  func refreshSubscriptionStatus(forceRefreshSeasonSnapshot: Bool = true) async {
    guard apiService.canAccess(.subscribe) else {
      self.isSubscribed = false
      return
    }
    let detail = fullDetail ?? partialMedia
    if detail.canDirectlySubscribe {
      // 电影等可直接订阅的类型：重新查询全局订阅状态
      do {
        var subscribed = try await apiService.checkSubscription(
          media: detail,
          forceRefresh: true
        )
        // 豆瓣/Bangumi 来源：后端通常用 TMDB ID 存储订阅，
        // 当用原始 mediaId（如 douban:xxx）查不到时，用识别到的 tmdbId 补查一次
        if !subscribed, detail.tmdb_id == nil, let tmdbId = self.tmdbId {
          let tmdbMedia = MediaInfo(tmdb_id: tmdbId, type: detail.type)
          subscribed = try await apiService.checkSubscription(
            media: tmdbMedia,
            forceRefresh: true
          )
        }
        self.isSubscribed = subscribed
      } catch {
        print("[MediaPreloadTask] 刷新订阅状态失败: \(error)")
      }
    } else if let seasonVM = seasonViewModel {
      // 电视剧：刷新分季订阅状态
      await seasonVM.checkSubscriptionStatus(forceRefresh: forceRefreshSeasonSnapshot)
    }
  }

  // MARK: - ⑤ TMDB 识别

  private func recognizeTmdb() async throws {
    defer { isTmdbRecognitionFinished = true }
    // 预加载识别失败静默处理：不弹提示，也不伪装 no-match。
    // 取消向上传播，避免取消后仍继续启动依赖任务（分季/订阅 fallback 补查）。
    let result: Int?
    do {
      result = try await apiService.recognizeTmdbId(
        title: partialMedia.title ?? "",
        year: partialMedia.year,
        type: partialMedia.type
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      result = nil
    }
    if let tmdbId = result {
      self.tmdbId = tmdbId
    }
  }
}

private final class ImageRetrieveContinuationBox: @unchecked Sendable {
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

// MARK: - 预加载管理器（单例）

/// 管理所有媒体的预加载任务缓存。
/// MediaCard 聚焦时触发预加载，ContainerView 和右键菜单读取预加载结果。
@MainActor
class MediaPreloader: ObservableObject {
  static let shared = MediaPreloader(apiService: .shared)

  /// 预加载任务缓存，key = MediaInfo.id
  private var cache: [String: MediaPreloadTask] = [:]
  /// 尚未进入详情页的临时焦点候选。新候选出现时立即释放旧候选。
  private var candidateKey: String?
  /// 仍存在于导航栈中的详情页 owner；同一媒体可以在栈中出现多次。
  private var navigationOwners: [String: Set<UUID>] = [:]
  /// 当前屏幕页面的图片 URL，用于新详情捕获自己的返回目标。
  private var activePageImageOwner: UUID?
  private weak var activePageImageCleanupTarget: PageImageCleanupTarget?
  /// Pop 回列表后，阻止焦点恢复立即重新预载刚退出的媒体。
  private var suppressedFocusCandidateKey: String?
  /// `NavigationPath.append` 到目的页 `onAppear` 之间的临时 owner。
  private var pendingMediaNavigations: [UUID: PendingMediaNavigation] = [:]
  /// 详情页附带预载（如 TMDB 跳转目标），不占用焦点 candidateKey。
  private var auxiliaryPreloads: [UUID: Set<String>] = [:]
  private static let legacyNavigationOwner = UUID()
  private var cancellables = Set<AnyCancellable>()
  private var subscriptionRefreshTask: Task<Void, Never>?
  private var observedSessionUIIdentity: String
  private let apiService: APIService

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    observedSessionUIIdentity = apiService.uiIdentity
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

    apiService.$session
      .dropFirst()
      .sink { [weak self] session in
        guard let self else { return }
        let shouldClear = session.token == nil
          || session.uiIdentity != self.observedSessionUIIdentity
        self.observedSessionUIIdentity = session.uiIdentity
        if shouldClear { self.clearAll() }
      }
      .store(in: &cancellables)
  }

  /// 获取已有预加载任务，或创建并启动新任务
  @discardableResult
  func preload(for media: MediaInfo) -> MediaPreloadTask {
    let key = media.id
    if let existing = cache[key] {
      // 失败的任务不缓存：移除后重新创建，允许自动重试
      // 场景：API 超时/网络抖动/后端返回空数据 → 任务卡在 isDetailFailed 永远无法恢复
      if existing.isDetailFailed {
        existing.cancel()
        cache.removeValue(forKey: key)
      } else {
        return existing
      }
    }

    // 创建新任务
    let task = MediaPreloadTask(partialMedia: media, apiService: apiService)
    cache[key] = task
    task.start()

    return task
  }

  /// 仅为需要普通媒体详情的对象创建预加载任务。
  /// 合集由 CollectionDetailView 自己分页加载，不应进入普通详情预加载缓存。
  @discardableResult
  func preloadIfNeeded(for media: MediaInfo) -> MediaPreloadTask? {
    guard media.shouldPreloadDetail else { return nil }
    replaceCandidate(with: media.id)
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
  func preloadFocusedCandidateIfNeeded(for media: MediaInfo) -> MediaPreloadTask? {
    guard suppressedFocusCandidateKey != media.id else { return nil }
    return preloadIfNeeded(for: media)
  }

  /// 焦点真正移动到另一项后，解除上一次 Pop 的单次抑制。
  func focusDidMove(to key: String) {
    guard let suppressedFocusCandidateKey, suppressedFocusCandidateKey != key else { return }
    self.suppressedFocusCandidateKey = nil
  }

  func isFocusPreloadSuppressed(for key: String) -> Bool {
    suppressedFocusCandidateKey == key
  }

  // MARK: - 当前页面图片快照

  func activatePageImageSnapshot(
    _ snapshot: PageImageSnapshot,
    owner: UUID,
    target: PageImageCleanupTarget,
    cache: ImageCache = .default
  ) {
    updatePageImageSnapshot(snapshot, target: target, cache: cache)
    activePageImageOwner = owner
    activePageImageCleanupTarget = target
  }

  /// 页面被子页面覆盖后仍更新自己的引用，避免子页面捕获到永久不完整的值快照。
  func updatePageImageSnapshot(
    _ snapshot: PageImageSnapshot,
    target: PageImageCleanupTarget,
    cache: ImageCache = .default
  ) {
    guard target.forwardingTarget == nil, !target.isDiscarded else { return }
    target.snapshot = snapshot
    flushPendingCardImagesIfPossible(from: target, cache: cache)
  }

  func captureActivePageImageSnapshot() -> PageImageSnapshot? {
    activePageImageCleanupTarget?.snapshot
  }

  func captureActivePageImageCleanupTarget() -> PageImageCleanupTarget? {
    activePageImageCleanupTarget
  }

  /// 普通媒体在 append 前建立临时 owner；合集保持原有导航行为。
  func appendMedia(
    _ media: MediaInfo,
    to navigationPath: Binding<NavigationPath>,
    stackID: UUID
  ) {
    _ = beginMediaNavigation(
      for: media,
      pathDepth: navigationPath.wrappedValue.count,
      stackID: stackID
    )
    navigationPath.wrappedValue.append(media)
  }

  /// 在追加普通媒体详情前建立临时 owner，防止转场期间的焦点变化取消目标任务。
  @discardableResult
  func beginMediaNavigation(
    for media: MediaInfo,
    pathDepth: Int,
    stackID: UUID
  ) -> UUID? {
    guard media.shouldPreloadDetail else { return nil }

    let key = media.id
    let expectedPathDepth = pathDepth + 1
    if let existing = pendingMediaNavigations.first(where: {
      $0.value.mediaKey == key
        && $0.value.stackID == stackID
        && $0.value.expectedPathDepth == expectedPathDepth
    }) {
      return existing.key
    }

    replaceCandidate(with: key)
    _ = preload(for: media)

    let token = UUID()
    navigationOwners[key, default: []].insert(token)
    pendingMediaNavigations[token] = PendingMediaNavigation(
      mediaKey: key,
      stackID: stackID,
      expectedPathDepth: expectedPathDepth
    )
    candidateKey = nil
    return token
  }

  /// 目的页首次出现时，把唯一匹配的临时 owner 转成页面自己的 owner。
  @discardableResult
  func transferPendingMediaNavigation(
    for mediaKey: String,
    pathDepth: Int,
    stackID: UUID,
    to owner: UUID
  ) -> Bool {
    let matches = pendingMediaNavigations.filter {
      $0.value.mediaKey == mediaKey
        && $0.value.stackID == stackID
        && $0.value.expectedPathDepth <= pathDepth
    }
    guard matches.count == 1, let match = matches.first else { return false }

    pendingMediaNavigations.removeValue(forKey: match.key)
    unpin(key: mediaKey, owner: match.key)
    navigationOwners[mediaKey, default: []].insert(owner)
    return true
  }

  /// 根栈路径回滚到预期深度以下时，回收没有完成交接的临时 owner。
  func reconcilePendingMediaNavigations(currentPathDepth: Int, stackID: UUID) {
    let staleTokens = pendingMediaNavigations.compactMap { token, pending in
      pending.stackID == stackID && currentPathDepth < pending.expectedPathDepth
        ? token
        : nil
    }
    for token in staleTokens {
      cancelPendingMediaNavigation(token)
    }
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

  /// 页面真正被 Pop 后解除 owner；最后一个 owner 离开时彻底释放该详情任务和背景内存。
  func releaseAfterPop(
    media: MediaInfo,
    owner: UUID,
    size: CGSize,
    leavingImageSnapshot: PageImageSnapshot,
    pageImageCleanupTarget: PageImageCleanupTarget,
    returnTargetImageCleanupTarget: PageImageCleanupTarget?,
    loadingPosterURL: URL? = nil,
    imageCache: ImageCache = .default
  ) {
    let key = media.id
    unpin(key: key, owner: owner)
    forwardCardImageCleanup(
      leaving: leavingImageSnapshot,
      from: pageImageCleanupTarget,
      to: returnTargetImageCleanupTarget,
      cache: imageCache
    )
    suppressedFocusCandidateKey = key
    removeLoadingPosterFromMemory(url: loadingPosterURL, imageCache: imageCache)
    releaseAuxiliaryPreloads(ownedBy: owner, size: size, imageCache: imageCache)
    releaseTask(forKey: key, fallbackMedia: media, size: size, imageCache: imageCache)
  }

  func discardLoadedBackgroundIfAbandoned(
    url: URL,
    detail: MediaInfo,
    usingPosterAsBackdrop: Bool,
    isAbandoned: Bool,
    size: CGSize,
    screenScale: CGFloat = UIScreen.main.scale,
    imageCache: ImageCache = .default
  ) {
    guard isAbandoned else { return }
    let cacheKey = apiService.imageSource(for: url).cacheKey
    MediaDetailBackgroundImage.removeHeroFromMemory(
      for: url,
      size: size,
      usingPosterAsBackdrop: usingPosterAsBackdrop,
      screenScale: screenScale,
      cacheKey: cacheKey,
      cache: imageCache
    )
    removeBackgroundTargetHeroesFromMemory(
      for: detail,
      size: size,
      screenScale: screenScale,
      imageCache: imageCache
    )
  }

  /// 页面快速连续 Pop 时，把尚未能处理的 URL 转发到更上一级目标。
  func forwardCardImageCleanup(
    leaving: PageImageSnapshot,
    from pageTarget: PageImageCleanupTarget,
    to returnTarget: PageImageCleanupTarget?,
    cache: ImageCache = .default
  ) {
    let mediaURLs = pageTarget.pendingMediaPosterURLs.union(leaving.mediaPosterURLs)
    let personURLs = pageTarget.pendingPersonImageURLs.union(leaving.personImageURLs)
    pageTarget.pendingMediaPosterURLs.removeAll()
    pageTarget.pendingPersonImageURLs.removeAll()
    pageTarget.snapshot = nil

    guard let returnTarget else {
      pageTarget.isDiscarded = true
      pageTarget.forwardingTarget = nil
      return
    }

    pageTarget.forwardingTarget = returnTarget
    enqueuePrefetchedCardImages(
      PageImageSnapshot(
        mediaPosterURLs: mediaURLs,
        personImageURLs: personURLs
      ),
      returningTo: returnTarget,
      cache: cache
    )
  }

  /// Paginator completion 用同一入口补交晚到写回的 URL。
  func enqueuePrefetchedCardImages(
    _ images: PageImageSnapshot,
    returningTo target: PageImageCleanupTarget,
    cache: ImageCache = .default
  ) {
    if target.isDiscarded { return }
    if let forwardingTarget = target.forwardingTarget {
      enqueuePrefetchedCardImages(images, returningTo: forwardingTarget, cache: cache)
      return
    }

    guard let snapshot = target.snapshot, snapshot.isComplete else {
      target.pendingMediaPosterURLs.formUnion(images.mediaPosterURLs)
      target.pendingPersonImageURLs.formUnion(images.personImageURLs)
      return
    }

    releaseCardImagesAfterPop(leaving: images, returningTo: snapshot, cache: cache)
  }

  private func flushPendingCardImagesIfPossible(
    from target: PageImageCleanupTarget,
    cache: ImageCache
  ) {
    guard let snapshot = target.snapshot, snapshot.isComplete else { return }
    guard !target.pendingMediaPosterURLs.isEmpty || !target.pendingPersonImageURLs.isEmpty else {
      return
    }

    let pending = PageImageSnapshot(
      mediaPosterURLs: target.pendingMediaPosterURLs,
      personImageURLs: target.pendingPersonImageURLs
    )
    target.pendingMediaPosterURLs.removeAll()
    target.pendingPersonImageURLs.removeAll()
    releaseCardImagesAfterPop(leaving: pending, returningTo: snapshot, cache: cache)
  }

  func releaseCardImagesAfterPop(
    leaving: PageImageSnapshot,
    returningTo target: PageImageSnapshot?,
    cache: ImageCache = .default
  ) {
    guard let target, target.isComplete else { return }

    let mediaProcessor = MediaCard.posterProcessor(for: MediaCard.defaultPosterSize)
    for url in leaving.mediaPosterURLs.subtracting(target.mediaPosterURLs) {
      cache.removeImage(
        forKey: apiService.imageSource(for: url).cacheKey,
        processorIdentifier: mediaProcessor.identifier,
        fromMemory: true,
        fromDisk: false
      )
    }

    let personProcessor = PersonCard.imageProcessor()
    for url in leaving.personImageURLs.subtracting(target.personImageURLs) {
      cache.removeImage(
        forKey: apiService.imageSource(for: url).cacheKey,
        processorIdentifier: personProcessor.identifier,
        fromMemory: true,
        fromDisk: false
      )
    }
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
  /// 用于用户退出登录或切换服务器时，避免残留旧 Cookie 的图片 URL、旧订阅状态等脏数据。
  func clearAll() {
    subscriptionRefreshTask?.cancel()
    subscriptionRefreshTask = nil
    for task in cache.values {
      task.cancel()
    }
    MPImageWarmer.shared.clear()
    cache.removeAll()
    candidateKey = nil
    navigationOwners.removeAll()
    pendingMediaNavigations.removeAll()
    auxiliaryPreloads.removeAll()
    activePageImageOwner = nil
    activePageImageCleanupTarget = nil
    suppressedFocusCandidateKey = nil
  }

  // MARK: - 订阅状态批量刷新

  /// 收到订阅变更通知后，刷新活跃详情页持有的 task 的订阅状态。
  /// 普通海报墙预加载缓存不主动强刷，避免浏览海报墙后一次通知触发大量订阅查询。
  private func refreshAllSubscriptionStatus() async {
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

  private func replaceCandidate(with key: String) {
    guard candidateKey != key else { return }
    let previousKey = candidateKey
    candidateKey = navigationOwners[key] == nil ? key : nil
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

  func removeLoadingPosterFromMemory(
    url: URL?,
    imageCache: ImageCache = .default
  ) {
    guard let url else { return }
    MediaDetailLoadingPoster.removeFromMemory(
      for: url,
      cacheKey: apiService.imageSource(for: url).cacheKey,
      cache: imageCache
    )
  }

  private func cancelPendingMediaNavigation(_ token: UUID) {
    guard let pending = pendingMediaNavigations.removeValue(forKey: token) else { return }
    unpin(key: pending.mediaKey, owner: token)
    releaseTask(
      forKey: pending.mediaKey,
      fallbackMedia: cache[pending.mediaKey]?.partialMedia,
      size: UIScreen.main.bounds.size
    )
  }

  func removeBackgroundTargetHeroesFromMemory(
    for detail: MediaInfo,
    size: CGSize,
    screenScale: CGFloat = UIScreen.main.scale,
    imageCache: ImageCache = .default
  ) {
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
