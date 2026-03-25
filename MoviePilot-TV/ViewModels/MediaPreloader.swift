import Combine
import Foundation
import Kingfisher
import SwiftUI

// MARK: - 单个媒体的预加载任务

/// 管理单个媒体项的所有预加载数据。
/// 作为 DetailView 和右键菜单的唯一数据源 (Single Source of Truth)。
@MainActor
class MediaPreloadTask: ObservableObject {
  let partialMedia: MediaInfo

  // ⭐ 必须加载完才能打开 DetailView
  @Published var fullDetail: MediaInfo?
  @Published var isDetailLoaded = false
  @Published var isDetailFailed = false

  // 可选预加载数据（持久存在，加载完直接显示）
  @Published var tmdbId: Int?
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

  init(partialMedia: MediaInfo) {
    self.partialMedia = partialMedia
  }

  /// 启动所有预加载任务（幂等，多次调用不会重复启动）
  func start() {
    guard !isStarted else { return }
    isStarted = true

    // 合集(Collection)没有 media detail 详情页，走的是 CollectionDetailView，
    // fetchMediaDetail / checkSubscription / recognizeTmdb 等全部无意义且会失败，直接跳过
    guard partialMedia.collection_id == nil else { return }

    internalTasks.append(
      Task {
        // ⑤ TMDB 识别 — 必须先于 checkSubscription 完成，否则 fallback 查询会因 tmdbId 为 nil 而跳过
        // 与 loadDetail 并发启动（两者互不依赖），但都在依赖任务之前完成
        async let tmdbRecognition: Void = {
          if self.partialMedia.tmdb_id == nil
            && (self.partialMedia.douban_id != nil || self.partialMedia.bangumi_id != nil)
          {
            await self.recognizeTmdb()
          }
        }()
        async let detailLoad: Void = self.loadDetail()

        // 等待两者都完成
        _ = await (tmdbRecognition, detailLoad)
        guard !Task.isCancelled else { return }

        // 无论成功还是失败，都尝试加载依赖任务（失败时用 partialMedia 做 fallback）
        let mediaForDeps = fullDetail ?? partialMedia
        await withTaskGroup(of: Void.self) { group in
          // ② 预取背景图
          group.addTask { await self.prefetchBackgroundImage(for: mediaForDeps) }
          // ③ 分季信息（仅电视剧）
          group.addTask { await self.loadSeasonData(for: mediaForDeps) }
          // ④ 订阅状态（此时 self.tmdbId 已就绪，可正确执行 fallback 查询）
          group.addTask { await self.checkSubscription(for: mediaForDeps) }
        }
      })
  }

  /// 取消所有预加载任务（包括正在进行的 Kingfisher 图片下载）
  func cancel() {
    internalTasks.forEach { $0.cancel() }
    internalTasks.removeAll()
    // 主动中断 Kingfisher 下载，释放网络资源和内存
    activeImageDownload?.cancel()
    activeImageDownload = nil
  }

  // MARK: - ① 加载完整媒体详情

  private func loadDetail() async {
    do {
      let fetched = try await APIService.shared.fetchMediaDetail(media: partialMedia)
      // 校验返回数据有效性：API 可能返回 200 但 body 是空/残缺 JSON
      // 此时 Codable 解码成功但所有字段为 nil，导致详情页显示 "Unknown" 空白页
      guard fetched.title != nil || fetched.tmdb_id != nil || fetched.douban_id != nil else {
        print("[MediaPreloadTask] API 返回空数据，视为失败")
        self.isDetailFailed = true
        return
      }
      self.fullDetail = fetched
      self.isDetailLoaded = true
    } catch {
      print("[MediaPreloadTask] 加载详情失败: \(error)")
      self.isDetailFailed = true
    }
  }

  // MARK: - ② 预取背景图（Kingfisher）

  private func prefetchBackgroundImage(for detail: MediaInfo) async {
    // 避免为已取消（LRU 淘汰）的任务发起无意义的图片请求
    guard !Task.isCancelled else { return }
    // 逻辑同 MediaDetailViewModel.updateBackground()：backdrop 优先，无则 poster
    let backdropUrl = detail.imageURLs.backdrop
    let posterUrl = detail.imageURLs.poster
    let targetUrl = backdropUrl ?? posterUrl
    guard let url = targetUrl else { return }

    // 使用 withTaskCancellationHandler 确保 Swift Task 取消时能中断 Kingfisher 的 HTTP 下载
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let modifier = AnyModifier.cookieModifier
        self.activeImageDownload = KingfisherManager.shared.retrieveImage(
          with: .network(url),
          options: [.requestModifier(modifier), .cacheOriginalImage]
        ) { _ in
          continuation.resume()
        }
      }
    } onCancel: {
      // 此闭包可能在任意线程执行，直接取消 Kingfisher 下载任务
      self.activeImageDownload?.cancel()
    }
    // 下载完成后清理引用
    activeImageDownload = nil
  }

  // MARK: - ③ 分季信息

  private func loadSeasonData(for detail: MediaInfo) async {
    guard detail.type == "电视剧" else { return }
    // tmdb_id 是分季加载的前提（与 DetailView 中逻辑一致）
    guard detail.tmdb_id != nil else { return }

    let vm = SubscribeSeasonViewModel(mediaInfo: detail)
    self.seasonViewModel = vm
    await vm.loadData(checkSubscriptionLimit: 10)
    self.isSeasonDataLoaded = true
  }

  // MARK: - ④ 订阅状态

  private func checkSubscription(for detail: MediaInfo) async {
    // 电视剧的订阅是分季维度，由 seasonViewModel 内部处理，预加载阶段不查全局订阅
    guard detail.canDirectlySubscribe else { return }

    do {
      self.isSubscribed = try await APIService.shared.checkSubscription(media: detail)
    } catch {
      print("[MediaPreloadTask] 检查订阅状态失败: \(error)")
      self.isSubscribed = false
    }
  }

  // MARK: - ⑤ TMDB 识别

  private func recognizeTmdb() async {
    let queryTitle =
      partialMedia.year != nil
      ? "\(partialMedia.title ?? "") \(partialMedia.year!)"
      : (partialMedia.title ?? "")
    guard !queryTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

    do {
      let result = try await APIService.shared.recognizeMedia(title: queryTitle)
      if let tmdbId = result.media_info?.tmdb_id {
        self.tmdbId = tmdbId
      }
    } catch {
      print("[MediaPreloadTask] TMDB 识别失败: \(error)")
    }
  }
}

// MARK: - 预加载管理器（单例）

/// 管理所有媒体的预加载任务缓存。
/// MediaCard 聚焦时触发预加载，ContainerView 和右键菜单读取预加载结果。
@MainActor
class MediaPreloader: ObservableObject {
  static let shared = MediaPreloader()

  /// 预加载任务缓存，key = MediaInfo.id
  private var cache: [String: MediaPreloadTask] = [:]
  /// LRU 访问顺序
  private var accessOrder: [String] = []
  /// 被 DetailView 持有中的 Task keys — 淘汰时跳过，防止活跃详情页数据丢失
  private var pinnedKeys: Set<String> = []
  /// 最大缓存数量（Apple TV 内存有限，但 20 太小容易淘汰活跃数据）
  private let maxCacheSize = 30

  private init() {}

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
        accessOrder.removeAll { $0 == key }
      } else {
        // 更新 LRU 顺序
        touchLRU(key: key)
        return existing
      }
    }

    // 创建新任务
    let task = MediaPreloadTask(partialMedia: media)
    cache[key] = task
    accessOrder.append(key)
    task.start()

    // LRU 淘汰
    evictIfNeeded()

    return task
  }

  /// 仅获取已有的预加载任务（不创建新的），并更新 LRU 顺序。
  /// ⚠️ 不要在 SwiftUI body 中使用此方法（会修改状态），请用 peekTask。
  func getTask(for media: MediaInfo) -> MediaPreloadTask? {
    let key = media.id
    if let existing = cache[key] {
      touchLRU(key: key)
      return existing
    }
    return nil
  }

  /// 纯读取：仅查询缓存中是否存在对应任务，**不修改 LRU 顺序**。
  /// 可安全在 SwiftUI body / contextMenu @ViewBuilder 中使用。
  func peekTask(for media: MediaInfo) -> MediaPreloadTask? {
    return cache[media.id]
  }

  // MARK: - Pin / Unpin（DetailView 生命周期保护）

  /// 标记某个 Task 为"活跃使用中"，淘汰时自动跳过。
  /// 应在 MediaDetailContainerView 的 .task / .onAppear 中调用。
  func pin(key: String) {
    pinnedKeys.insert(key)
  }

  /// 解除"活跃使用中"标记。
  /// 应在 MediaDetailContainerView 的 .onDisappear 中调用。
  func unpin(key: String) {
    pinnedKeys.remove(key)
  }

  /// 通过 mediaId（如 "tmdb:123"）查找对应的预加载任务。
  /// 用于 SubscribeSheet 关闭后回写订阅状态。
  func findTask(byMediaId mediaId: String) -> MediaPreloadTask? {
    guard !mediaId.isEmpty else { return nil }
    return cache.values.first { $0.partialMedia.apiMediaId == mediaId }
  }

  // MARK: - 全局清理（登出/切换服务器时调用）

  /// 取消所有预加载任务并清空缓存。
  /// 用于用户退出登录或切换服务器时，避免残留旧 Cookie 的图片 URL、旧订阅状态等脏数据。
  func clearAll() {
    for task in cache.values {
      task.cancel()
    }
    cache.removeAll()
    accessOrder.removeAll()
    pinnedKeys.removeAll()
  }

  // MARK: - LRU 管理

  private func touchLRU(key: String) {
    accessOrder.removeAll { $0 == key }
    accessOrder.append(key)
  }

  private func evictIfNeeded() {
    // 从最老的开始淘汰，但跳过被 pin 住的 Task
    while cache.count > maxCacheSize {
      // 找到第一个未被 pin 的 key
      guard let indexToEvict = accessOrder.firstIndex(where: { !pinnedKeys.contains($0) }) else {
        // 所有缓存都被 pin 住了（极端情况），无法淘汰，退出
        break
      }
      let keyToEvict = accessOrder[indexToEvict]
      cache[keyToEvict]?.cancel()
      cache.removeValue(forKey: keyToEvict)
      accessOrder.remove(at: indexToEvict)
    }
  }
}
