import SwiftUI

nonisolated enum MediaDetailPresentationStyle: Hashable {
  case standard
  case direct

  var usesLoadingTransition: Bool { self == .standard }
}

/// 详情入口就绪判定。抽成纯函数以便直接验证「有完整详情且首行就绪才揭示」。
nonisolated enum MediaDetailLoadingCover {
  static func isReady(
    fullDetailLoaded: Bool,
    usesLoadingTransition: Bool,
    wasPreloaded: Bool,
    detailReady: Bool,
    contentReady: Bool
  ) -> Bool {
    guard fullDetailLoaded else { return false }
    if !usesLoadingTransition { return contentReady }
    return wasPreloaded || (detailReady && contentReady)
  }
}

/// 媒体详情的容器视图。
/// 入口采用渐进渲染：立即渲染 MediaDetailView（完整详情未到先用卡片媒体），
/// 标题 move-in、固定按钮胶囊在但文案透明不可按、可变槽位就地占位；就绪后仅可变内容淡入。
/// 不再用整块交叉淡入的遮罩盖住文字。
struct MediaDetailContainerView: View {
  let media: MediaInfo
  let routeID: UUID
  let loadingPosterURL: URL?
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let presentationStyle: MediaDetailPresentationStyle
  let allowsRequests: Bool
  let onInitialContentReady: () -> Void

  /// 预加载任务：在 init 中立即获取/创建，确保首帧就有数据
  /// 非 Optional，消除 if let 条件分支导致的视图结构变化
  @State private var preloadTask: MediaPreloadTask

  init(
    media: MediaInfo,
    preloadTask: MediaPreloadTask,
    routeID: UUID,
    imageLifecycle: PageImageLifecycle,
    loadingPosterURL: URL? = nil,
    presentationStyle: MediaDetailPresentationStyle = .standard,
    allowsRequests: Bool = true,
    onInitialContentReady: @escaping () -> Void = {}
  ) {
    self.media = media
    self.routeID = routeID
    self.loadingPosterURL = loadingPosterURL
    self.imageLifecycle = imageLifecycle
    self.presentationStyle = presentationStyle
    self.allowsRequests = allowsRequests
    self.onInitialContentReady = onInitialContentReady
    // task 由导航 entry 在 Push 时取得；转场重求值不能创建无 owner task。
    preloadTask.cancelImageWarm()
    _preloadTask = State(wrappedValue: preloadTask)
  }

  @MainActor
  static func tmdbPreloadTarget(
    for sourceMedia: MediaInfo,
    fullDetail: MediaInfo?,
    recognizedTmdbId: Int?,
    isEnabled: Bool = SystemViewModel.shouldPreloadTMDBDetails
  ) -> MediaInfo? {
    guard isEnabled,
      sourceMedia.tmdb_id == nil,
      sourceMedia.canJumpToTMDB,
      let fullDetail,
      let tmdbId = recognizedTmdbId ?? fullDetail.tmdb_id
    else {
      return nil
    }

    return MediaActionHandler.tmdbJumpTarget(for: fullDetail, tmdbId: tmdbId)
  }

  var body: some View {
    MediaDetailContainerContent(
      media: media,
      preloadTask: preloadTask,
      routeID: routeID,
      imageLifecycle: imageLifecycle,
      loadingPosterURL: loadingPosterURL,
      presentationStyle: presentationStyle,
      allowsRequests: allowsRequests,
      onInitialContentReady: onInitialContentReady
    )
  }
}

/// 内部辅助视图：通过 @ObservedObject 监听 MediaPreloadTask 的 @Published 属性变化，驱动 UI 刷新
private struct MediaDetailContainerContent: View {
  let media: MediaInfo
  @ObservedObject var preloadTask: MediaPreloadTask
  let routeID: UUID
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let presentationStyle: MediaDetailPresentationStyle
  let allowsRequests: Bool
  let onInitialContentReady: () -> Void

  /// 第二页首行内容是否已就绪（由 MediaDetailView 回写）
  @State private var isContentReady = false
  /// 记录首次出现时数据是否已预加载完毕（在 init 中设置，确保第一帧就生效）
  @State private var wasPreloaded: Bool
  /// 记录进入页面时由导航条目携带的加载海报，供详情页背景兜底使用。
  @State private var loadingPosterURL: URL?

  init(
    media: MediaInfo,
    preloadTask: MediaPreloadTask,
    routeID: UUID,
    imageLifecycle: PageImageLifecycle,
    loadingPosterURL transitionPosterURL: URL?,
    presentationStyle: MediaDetailPresentationStyle,
    allowsRequests: Bool,
    onInitialContentReady: @escaping () -> Void
  ) {
    self.media = media
    self.preloadTask = preloadTask
    self.routeID = routeID
    self.imageLifecycle = imageLifecycle
    self.presentationStyle = presentationStyle
    self.allowsRequests = allowsRequests
    self.onInitialContentReady = onInitialContentReady
    _isContentReady = State(
      initialValue: presentationStyle == .direct && preloadTask.fullDetail != nil
    )
    // 在 init 中判断，确保第一帧 isReady 就正确
    _wasPreloaded = State(initialValue: preloadTask.isDetailReady)
    _loadingPosterURL = State(
      initialValue: transitionPosterURL ?? media.imageURLs.poster
    )
  }

  /// 冷加载在完整详情的首行准备好后结束入口加载态。
  private var isReady: Bool {
    MediaDetailLoadingCover.isReady(
      fullDetailLoaded: preloadTask.fullDetail != nil,
      usesLoadingTransition: presentationStyle.usesLoadingTransition,
      wasPreloaded: wasPreloaded,
      detailReady: preloadTask.isDetailReady,
      contentReady: isContentReady
    )
  }

  private var loadingStatusMessage: String? {
    if !allowsRequests { return "正在验证登录状态…" }
    if preloadTask.isDetailFailed {
      guard let reason = preloadTask.detailFailureReason else { return "无法加载详情，请返回后重试" }
      return "无法加载详情（\(reason)），请返回后重试" }
    return preloadTask.detailRetryNumber.map { "重试加载中……（第 \($0) 次）" }
  }

  private var tmdbPreloadTarget: MediaInfo? {
    MediaDetailContainerView.tmdbPreloadTarget(
      for: media,
      fullDetail: preloadTask.fullDetail,
      recognizedTmdbId: preloadTask.tmdbId
    )
  }

  var body: some View {
    // 渐进渲染：完整详情未到先用卡片媒体，真实内容首帧即可显示稳定部分，
    // 不存在「已显示→闪成占位→闪回」的整块遮罩。
    MediaDetailView(
      detail: preloadTask.fullDetail ?? media,
      libraryItemHint: media.libraryItemHint,
      preloadTask: preloadTask,
      isContentReady: $isContentReady,
      routeID: routeID,
      imageLifecycle: imageLifecycle,
      loadingPosterURL: loadingPosterURL,
      presentationStyle: presentationStyle,
      allowsRequests: allowsRequests,
      isEntryLoading: !isReady,
      entryStatusMessage: loadingStatusMessage
    )
    .onAppear { reportInitialContentReady() }
    .onChange(of: preloadTask.fullDetail) { _, _ in reportInitialContentReady() }
    .task(id: tmdbPreloadTarget?.id) {
      guard allowsRequests, let target = tmdbPreloadTarget else { return }
      APIService.shared.mediaPreloader.preloadAuxiliary(
        for: target,
        owner: routeID
      )
    }
  }

  private func reportInitialContentReady() {
    if preloadTask.fullDetail != nil {
      onInitialContentReady()
    }
  }
}