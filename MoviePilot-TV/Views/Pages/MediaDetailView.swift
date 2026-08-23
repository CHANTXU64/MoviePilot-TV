import Kingfisher
import SwiftUI

private final class MediaDetailImageLifetime {
  var isBackgroundMounted = true
  var didReleaseAfterPop = false
}

private struct MediaDetailBackgroundLayer: View {
  let url: URL?
  let usingPosterAsBackdrop: Bool
  var onFailure: ((URL) -> Void)? = nil
  var onLoaded: ((URL) -> Void)? = nil

  @ViewBuilder
  var body: some View {
    if let url {
      let size = UIScreen.main.bounds.size
      let screenScale = UIScreen.main.scale
      backgroundImage(
        url,
        processor: MediaDetailBackgroundImage.heroProcessor(
          for: size,
          usingPosterAsBackdrop: usingPosterAsBackdrop,
          screenScale: screenScale
        ),
        scaleFactor: MediaDetailBackgroundImage.downsampleScale(
          for: size,
          screenScale: screenScale
        ),
        alignment: usingPosterAsBackdrop ? .top : .center
      )
    } else {
      Color.gray.opacity(0.3)
        .ignoresSafeArea()
    }
  }

  private func backgroundImage(
    _ url: URL,
    processor: any ImageProcessor,
    scaleFactor: CGFloat,
    alignment: Alignment
  ) -> some View {
    KFImage.sessionImage(url)
      .onSuccess { _ in
        onLoaded?(url)
      }
      .onFailure { _ in
        onFailure?(url)
      }
      .placeholder {
        EmptyView()
      }
      .setProcessor(processor)
      .scaleFactor(scaleFactor)
      .skippingMemoryCache()
      .cancelOnDisappear(true)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(
        width: UIScreen.main.bounds.width,
        height: UIScreen.main.bounds.height,
        alignment: alignment
      )
      .id("\(url.absoluteString)-\(processor.identifier)")
      .ignoresSafeArea()
  }
}

struct MediaDetailView: View {
  @StateObject private var viewModel: MediaDetailViewModel
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  @EnvironmentObject private var notificationManager: NotificationManager
  @ObservedObject private var apiService = APIService.shared
  /// 预加载任务：订阅状态、TMDB 识别、分季信息的唯一数据源
  @ObservedObject var preloadTask: MediaPreloadTask
  /// 由 ContainerView 传入，当第二页首行内容就绪时回写 true，控制 Loading 遮罩显隐
  @Binding var isContentReady: Bool
  let routeID: UUID
  @ObservedObject var imageLifecycle: PageImageLifecycle
  let loadingPosterURL: URL?
  @State private var showSiteSelection = false
  @State private var showContentPage = false
  @State private var hasAppeared = false
  @State private var hasRefreshedSubscriptionAfterFullDetail = false
  @State private var isBackgroundMounted = true
  @State private var backgroundGeneration = 0
  @State private var didReleaseAfterPop = false
  @State private var imageLifetime = MediaDetailImageLifetime()
  @State private var contentPageBackgroundUnmountTask: Task<Void, Never>?

  // 订阅相关 UI 状态（弹窗开关，纯 UI 逻辑）
  @State private var sheetSubscribe: Subscribe?
  @State private var showUnsubscribeConfirm = false
  @State private var unsubscribeConfirmationMessage = ""
  /// 推荐区预加载防抖任务
  @State private var recommendPreloadDebounce: Task<Void, Never>?
  /// 相似区预加载防抖任务
  @State private var similarPreloadDebounce: Task<Void, Never>?
  @State private var directorImageAnchorId: Person.ID?
  @State private var actorImageAnchorId: Person.ID?
  @State private var recommendImageAnchorId: MediaInfo.ID?
  @State private var similarImageAnchorId: MediaInfo.ID?

  @FocusState private var focusedDirectorId: Person.ID?
  @FocusState private var focusedRecommendId: MediaInfo.ID?
  @FocusState private var focusedSimilarId: MediaInfo.ID?
  @FocusState private var focusedActorId: Person.ID?
  @FocusState private var isHeroFocused: Bool
  @FocusState private var isContentFocused: Bool
  enum ButtonField {
    case subscribe, search, sites, otherInfo
  }
  @FocusState private var focusedButton: ButtonField?
  @State private var lastFocusedButton: ButtonField?

  private var canSubscribeMedia: Bool {
    apiService.canAccess(.subscribe) && !viewModel.detail.isCollection
  }

  private var canSearchResources: Bool {
    apiService.canAccess(.search)
  }

  private var canJumpToTMDB: Bool {
    viewModel.detail.canJumpToTMDB
  }

  private var shouldShowOtherInfo: Bool {
    Self.shouldShowOtherInfo(
      canSubscribeMedia: canSubscribeMedia,
      canSearchResources: canSearchResources
    )
  }

  private var preferredHeaderFocus: ButtonField? {
    if canSubscribeMedia { return .subscribe }
    if canSearchResources { return .search }
    if shouldShowOtherInfo { return .otherInfo }
    return nil
  }

  private func loadsHorizontalImage<Item: Identifiable>(
    at index: Int,
    in items: [Item],
    anchorID: Item.ID?,
    cardKind: ImageLoadWindow.HorizontalCardKind
  ) -> Bool where Item.ID: Equatable {
    let anchorIndex = anchorID.flatMap { id in
      items.firstIndex(where: { $0.id == id })
    }
    return ImageLoadWindow.containsHorizontalItem(
      at: index,
      itemCount: items.count,
      anchorIndex: anchorIndex,
      cardKind: cardKind
    )
  }

  private var shouldShowSiteFilter: Bool {
    guard canSearchResources else { return false }
    if focusedButton == .search || focusedButton == .sites {
      return true
    }
    if focusedButton == nil && (lastFocusedButton == .search || lastFocusedButton == .sites) {
      return true
    }
    return false
  }

  private var firstVisibleRow: String {
    if shouldShowSeasonSubscriptionSection {
      return "season"
    }
    if !viewModel.actorsPaginator.items.isEmpty {
      return "actors"
    }
    if !viewModel.uniqueDirectors.isEmpty {
      return "directors"
    }
    if !viewModel.recommendPaginator.items.isEmpty {
      return "recommendations"
    }
    if !viewModel.similarPaginator.items.isEmpty {
      return "similar"
    }
    return ""
  }

  private var seasonInfoCount: Int? {
    preloadTask.seasonViewModel?.seasonInfos.count
  }

  private var hasSeasonLoadError: Bool {
    preloadTask.seasonViewModel?.hasSeasonLoadError == true
  }

  private var isSeasonLoading: Bool {
    preloadTask.seasonViewModel?.isLoading == true
  }

  private var shouldShowSeasonSubscriptionSection: Bool {
    Self.shouldShowSeasonSubscriptionSection(
      canSubscribeMedia: canSubscribeMedia,
      detail: viewModel.detail,
      isSeasonDataLoaded: preloadTask.isSeasonDataLoaded,
      seasonCount: seasonInfoCount,
      hasSeasonLoadError: hasSeasonLoadError,
      isSeasonLoading: isSeasonLoading
    )
  }

  private var isSeasonInformationUnavailable: Bool {
    Self.isSeasonInformationUnavailable(
      canSubscribeMedia: canSubscribeMedia,
      detail: viewModel.detail,
      isSeasonDataLoaded: preloadTask.isSeasonDataLoaded,
      seasonCount: seasonInfoCount,
      hasSeasonLoadError: hasSeasonLoadError,
      isSeasonLoading: isSeasonLoading
    )
  }

  /// 从 ViewModel 读取的订阅状态（ViewModel 代理到 preloadTask）
  private var isSubscribed: Bool {
    viewModel.isSubscribed
  }

  init(
    detail: MediaInfo,
    preloadTask: MediaPreloadTask, isContentReady: Binding<Bool>,
    routeID: UUID,
    imageLifecycle: PageImageLifecycle,
    loadingPosterURL: URL?
  ) {
    let vm = MediaDetailViewModel(detail: detail)
    vm.preloadTask = preloadTask
    _viewModel = StateObject(wrappedValue: vm)
    self.preloadTask = preloadTask
    _isContentReady = isContentReady
    self.routeID = routeID
    self.imageLifecycle = imageLifecycle
    self.loadingPosterURL = loadingPosterURL
  }

  nonisolated static let contentPageBackgroundFadeDuration: TimeInterval = 0.4

  static func shouldRefreshBackground(isMounted: Bool, showingContentPage: Bool) -> Bool {
    !isMounted && !showingContentPage
  }

  static func shouldUnmountContentPageBackground(
    fadeElapsed: Bool,
    showingContentPage: Bool
  ) -> Bool {
    fadeElapsed && showingContentPage
  }

  static func shouldDiscardLoadedBackground(
    didReleaseAfterPop: Bool,
    isBackgroundMounted: Bool
  ) -> Bool {
    didReleaseAfterPop || !isBackgroundMounted
  }

  var body: some View {
    let backgroundColor = Color(white: 0.1)

    ZStack {
      backgroundColor
        .ignoresSafeArea()

      if isBackgroundMounted && imageLifecycle.keepsActivePageImages {
        MediaDetailBackgroundLayer(
          url: viewModel.backgroundUrl,
          usingPosterAsBackdrop: viewModel.isUsingPosterAsBackdrop,
          onFailure: { failedURL in
            viewModel.useBackgroundFallback(afterFailing: failedURL)
          },
          onLoaded: { url in
            discardLoadedBackgroundIfAbandoned(url: url)
          }
        )
        .id(backgroundGeneration)
        .opacity(showContentPage ? 0 : 1)
        .animation(
          .easeInOut(duration: Self.contentPageBackgroundFadeDuration),
          value: showContentPage
        )
        .transition(.opacity)
      }

      // 首屏动态阴影
      ZStack {
        // 1. 顶部很淡的阴影（左边长一点，右边短一点）
        LinearGradient(
          gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.05), .clear]),
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.1)
        )
        LinearGradient(
          gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.15), .clear]),
          startPoint: .topLeading,
          endPoint: UnitPoint(x: 0.4, y: 0.4)
        )

        // 2. 左下角 1/4 圆形的阴影
        RadialGradient(
          gradient: Gradient(colors: [.black.opacity(0.5), .black.opacity(0.35), .clear]),
          center: .bottomLeading,
          startRadius: 0,
          endRadius: UIScreen.main.bounds.width * 0.5
        )

        // 3. 底部渐变：很黑 -> 到演员变浅 -> 延伸到中心
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: backgroundColor.opacity(1.0), location: 0.0),
            .init(color: backgroundColor.opacity(0.8), location: 0.1),
            .init(color: backgroundColor.opacity(0.5), location: 0.2),
            .init(color: backgroundColor.opacity(0.25), location: 0.3),
            .init(color: backgroundColor.opacity(0.15), location: 0.4),
            .init(color: backgroundColor.opacity(0.07), location: 0.5),
            .init(color: backgroundColor.opacity(0.02), location: 0.6),
            .init(color: backgroundColor.opacity(0), location: 0.7),
          ]),
          startPoint: .bottom,
          endPoint: .top
        )
      }
      .ignoresSafeArea()
      .opacity(showContentPage ? 0 : 1)
      .animation(
        .easeInOut(duration: Self.contentPageBackgroundFadeDuration),
        value: showContentPage
      )

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            heroSection(scrollProxy: proxy)
              .id("top")

            VStack(alignment: .leading, spacing: 30) {
              // Centered media title — only visible on second page
              if showContentPage {
                Text(viewModel.detail.cleanedTitle ?? "")
                  .font(.largeTitle.bold())
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.bottom, 10)
                  .transition(.opacity)
              }

              seasonSubscriptionSection
              actorsSection
              directorsSection
              recommendationsSection
              similarSection
            }
            .id("contentTop")
            .padding(.top, showContentPage ? 60 : 0)
            .padding(.bottom, 80)
            .focused($isContentFocused)
            .animation(.easeInOut(duration: 0.6), value: showContentPage)
            .onChange(of: isHeroFocused) { _, focused in
              guard focused else { return }
              remountBackgroundForHeroIfNeeded()
              withAnimation(.easeInOut(duration: 0.6)) {
                showContentPage = false
                proxy.scrollTo("top", anchor: .top)
              }
            }
            .onChange(of: isContentFocused) { _, focused in
              guard focused, !showContentPage else { return }
              withAnimation(.easeInOut(duration: 0.6)) {
                showContentPage = true
                proxy.scrollTo("contentTop", anchor: .top)
              }
            }

            Color.clear
              .frame(height: UIScreen.main.bounds.height)
          }
        }
      }
    }
    .onChange(of: apiService.imageConfigurationIdentity) { _, _ in
      viewModel.refreshBackgroundForImageConfiguration()
    }
    .environmentObject(subscriptionHandler)
    .ignoresSafeArea()
    .onDisappear {
      // 取消防抖任务，防止视图消失后仍发起无意义的预加载请求
      recommendPreloadDebounce?.cancel()
      similarPreloadDebounce?.cancel()
      contentPageBackgroundUnmountTask?.cancel()
      contentPageBackgroundUnmountTask = nil
      handleRouteRemovalIfNeeded()
    }
    .onAppear {
      handleRouteRemovalIfNeeded()
      remountBackgroundIfNeeded()
    }
    .onChange(of: showContentPage) { _, showingContent in
      contentPageBackgroundUnmountTask?.cancel()
      contentPageBackgroundUnmountTask = nil
      if showingContent {
        scheduleUnmountBackgroundAfterContentPageFade()
      } else {
        remountBackgroundIfNeeded()
      }
    }
    .onChange(of: imageLifecycle.keepsActivePageImages) { _, keepsBackground in
      if keepsBackground {
        remountBackgroundIfNeeded()
      } else {
        unmountBackgroundForNavigation()
      }
    }
    .onChange(of: imageLifecycle.isRemoved) { _, removed in
      if removed {
        handleRouteRemovalIfNeeded()
      }
    }
    .task {
      if !hasAppeared, let preferredHeaderFocus {
        focusedButton = preferredHeaderFocus
        hasAppeared = true
      } else if !hasAppeared {
        hasAppeared = true
      }
      // 如果 fullDetail 已经就绪（预加载命中），立即应用（网络加载自动在后台启动）
      hasRefreshedSubscriptionAfterFullDetail = await Self.applyReadyPreloadedDetail(
        from: preloadTask,
        to: viewModel,
        hasRefreshedSubscription: hasRefreshedSubscriptionAfterFullDetail
      )
      if canSearchResources {
        await viewModel.siteFilter.loadSites()
      }
      // 重新激活时自动恢复成功空终态的推荐/相似/演员区域
      await viewModel.refreshSuccessEmptySections()
    }
    .task(id: preloadTask.partialMedia.id) {
      await Self.runActiveSubscriptionRefreshLoop {
        guard Self.shouldRefreshActiveSubscriptionStatus(
          preloadTask: preloadTask,
          viewModel: viewModel
        ) else {
          return
        }
        await viewModel.refreshSubscriptionStatus()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      Task { @MainActor in
        await Self.refreshActiveSubscriptionStatusOnSceneActivation(
          scenePhase: phase,
          shouldRefresh: {
            Self.shouldRefreshActiveSubscriptionStatus(
              preloadTask: preloadTask,
              viewModel: viewModel
            )
          },
          refresh: {
            await viewModel.refreshSubscriptionStatus()
          }
        )
      }
    }
    // 焦点恢复关键：当 fullDetail 加载完成后，应用完整详情。
    // MediaDetailView 从第一帧就存在于视图树中（用 partialMedia 初始化），
    // 在 fullDetail 就绪前不配置任何内容，仅由 Loading 遮罩覆盖。
    .onChange(of: preloadTask.isDetailReady) { _, isLoaded in
      if isLoaded {
        Task { @MainActor in
          hasRefreshedSubscriptionAfterFullDetail = await Self.applyReadyPreloadedDetail(
            from: preloadTask,
            to: viewModel,
            hasRefreshedSubscription: hasRefreshedSubscriptionAfterFullDetail
          )
        }
      }
    }
    // 当 ViewModel 的 isFirstRowReady 变为 true 时，回写给 ContainerView 控制 Loading 遮罩
    .onChange(of: viewModel.isFirstRowReady) { _, ready in
      if ready {
        isContentReady = true
      }
    }
    // 电视剧首行是 season，由 preloadTask 异步加载，
    // 当分季数据实际加载完毕时通知 ViewModel（applyFullDetail 时可能尚未就绪）
    .onChange(of: preloadTask.isSeasonDataLoaded) { _, isLoaded in
      if isLoaded && canSubscribeMedia && !viewModel.isFirstRowReady
        && viewModel.detail.type == "电视剧"
      {
        viewModel.isFirstRowReady = true
        Task { @MainActor in
          let didRefresh = await viewModel.refreshSubscriptionStatus()
          hasRefreshedSubscriptionAfterFullDetail =
            didRefresh || hasRefreshedSubscriptionAfterFullDetail
        }
      }
    }
    .sheet(item: $sheetSubscribe) { subscribe in
      SubscribeSheet(subscribe: subscribe, isNewSubscription: true) {
        // 订阅完成后刷新订阅状态（通过 ViewModel 代理到 preloadTask）
        Task {
          await viewModel.refreshSubscriptionStatus()
        }
      }
    }
    .alert(SubscriptionCancelConfirmation.title, isPresented: $showUnsubscribeConfirm) {
      Button("取消", role: .cancel) {}
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        Task {
          guard await viewModel.cancelSubscription() else {
            notificationManager.show(
              message: SubscriptionCancelConfirmation.failureMessage,
              type: .error
            )
            return
          }
        }
      }
    } message: {
      Text(
        unsubscribeConfirmationMessage.isEmpty
          ? SubscriptionCancelConfirmation.headerMessage(for: viewModel.detail)
          : unsubscribeConfirmationMessage
      )
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .sheet(isPresented: $showSiteSelection) {
      MultiSelectionSheet(
        options: viewModel.siteFilter.availableSites,
        id: \.id,
        selected: $viewModel.siteFilter.selectedSites,
        label: { $0.name }
      )
    }
    .onChange(of: focusedButton) { _, newValue in
      if let newValue = newValue {
        lastFocusedButton = newValue
      }
    }
  }

  private func navigateFromSecondPage(to destination: Person) {
    navigationCoordinator.push(destination)
  }

  private func navigateFromSecondPage(to destination: ResourceSearchRequest) {
    navigationCoordinator.push(destination)
  }

  private func navigateFromSecondPage(to destination: SubscribeSeasonRequest) {
    navigationCoordinator.push(destination)
  }

  private func navigateToMediaFromSecondPage(_ media: MediaInfo) {
    navigationCoordinator.push(media)
  }

  private func releaseBackground() {
    contentPageBackgroundUnmountTask?.cancel()
    contentPageBackgroundUnmountTask = nil
    guard isBackgroundMounted else { return }
    isBackgroundMounted = false
    imageLifetime.isBackgroundMounted = false
    let size = UIScreen.main.bounds.size
    let screenScale = UIScreen.main.scale
    MediaPreloader.shared.setHeroPresented(
      false,
      for: viewModel.detail,
      owner: routeID,
      size: size,
      screenScale: screenScale,
    )
  }

  private func discardLoadedBackgroundIfAbandoned(url: URL) {
    MediaPreloader.shared.discardLoadedBackgroundIfAbandoned(
      url: url,
      detail: viewModel.detail,
      usingPosterAsBackdrop: viewModel.isUsingPosterAsBackdrop,
      isAbandoned: Self.shouldDiscardLoadedBackground(
        didReleaseAfterPop: imageLifetime.didReleaseAfterPop,
        isBackgroundMounted: imageLifetime.isBackgroundMounted
      ),
      size: UIScreen.main.bounds.size
    )
  }

  private func remountBackgroundIfNeeded() {
    guard !imageLifecycle.isRemoved,
      imageLifecycle.keepsActivePageImages,
      !showContentPage
    else { return }
    MediaPreloader.shared.setHeroPresented(
      true,
      for: viewModel.detail,
      owner: routeID,
      size: UIScreen.main.bounds.size
    )
    guard Self.shouldRefreshBackground(
      isMounted: isBackgroundMounted,
      showingContentPage: showContentPage
    ) else { return }
    remountBackgroundForHeroIfNeeded()
  }

  /// 回到 Hero 时先挂上透明背景，再随 showContentPage 淡入。
  private func remountBackgroundForHeroIfNeeded() {
    guard !isBackgroundMounted else { return }
    backgroundGeneration &+= 1
    isBackgroundMounted = true
    imageLifetime.isBackgroundMounted = true
  }

  /// 下滑淡出结束后再卸背景，避免动画中途突然消失。
  private func scheduleUnmountBackgroundAfterContentPageFade() {
    contentPageBackgroundUnmountTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(Self.contentPageBackgroundFadeDuration))
      guard
        !Task.isCancelled,
        Self.shouldUnmountContentPageBackground(
          fadeElapsed: true,
          showingContentPage: showContentPage
        )
      else { return }
      unmountBackgroundForContentPage()
    }
  }

  private func unmountBackgroundForContentPage() {
    releaseBackground()
  }

  private func unmountBackgroundForNavigation() {
    releaseBackground()
  }

  private func handleRouteRemovalIfNeeded() {
    guard imageLifecycle.isRemoved, !didReleaseAfterPop else { return }
    didReleaseAfterPop = true
    imageLifetime.didReleaseAfterPop = true
    viewModel.cancelForPop()
  }

  // MARK: - 订阅 UI 操作（业务逻辑委托给 ViewModel）

  @MainActor
  @discardableResult
  static func applyReadyPreloadedDetail(
    from preloadTask: MediaPreloadTask,
    to viewModel: MediaDetailViewModel,
    hasRefreshedSubscription: Bool
  ) async -> Bool {
    guard preloadTask.isDetailReady, let fullDetail = preloadTask.fullDetail else {
      return hasRefreshedSubscription
    }

    viewModel.applyFullDetail(fullDetail)

    guard !hasRefreshedSubscription else {
      return true
    }

    return await viewModel.refreshSubscriptionStatus()
  }

  static let activeSubscriptionRefreshIntervalNanoseconds: UInt64 = 60 * 1_000_000_000

  @MainActor
  static func runActiveSubscriptionRefreshLoop(
    refreshIfNeeded: () async -> Void,
    sleep: (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) },
    isCancelled: () -> Bool = { Task.isCancelled }
  ) async {
    while !isCancelled() {
      await sleep(activeSubscriptionRefreshIntervalNanoseconds)
      guard !isCancelled() else { break }
      await refreshIfNeeded()
    }
  }

  @MainActor
  static func shouldRefreshActiveSubscriptionStatus(
    preloadTask: MediaPreloadTask,
    viewModel: MediaDetailViewModel
  ) -> Bool {
    if viewModel.isSubscribed {
      return true
    }
    if let seasonViewModel = preloadTask.seasonViewModel,
      !seasonViewModel.subscribedSeasons.isEmpty
    {
      return true
    }
    return false
  }

  @MainActor
  static func refreshActiveSubscriptionStatusOnSceneActivation(
    scenePhase: ScenePhase,
    shouldRefresh: () -> Bool,
    refresh: () async -> Void
  ) async {
    guard scenePhase == .active else { return }
    guard shouldRefresh() else { return }
    await refresh()
  }

  static func performHeaderSubscribeAction(
    isSubscribed: Bool,
    showUnsubscribeConfirm: () -> Void,
    startSubscribe: () -> Void
  ) {
    if isSubscribed {
      showUnsubscribeConfirm()
    } else {
      startSubscribe()
    }
  }

  static func performHeaderSubscribeAction(
    isSubscribed: Bool,
    refreshSubscribedState: () async -> Bool?,
    showUnsubscribeConfirm: () -> Void,
    startSubscribe: () -> Void
  ) async {
    guard let latestSubscribedState = await refreshSubscribedState() else {
      return
    }
    performHeaderSubscribeAction(
      isSubscribed: isSubscribed,
      latestSubscribedState: latestSubscribedState,
      showUnsubscribeConfirm: showUnsubscribeConfirm,
      startSubscribe: startSubscribe
    )
  }

  static func performHeaderSubscribeAction(
    isSubscribed: Bool,
    latestSubscribedState: Bool,
    showUnsubscribeConfirm: () -> Void,
    startSubscribe: () -> Void
  ) {
    guard latestSubscribedState == isSubscribed else {
      return
    }
    if latestSubscribedState {
      showUnsubscribeConfirm()
    } else {
      startSubscribe()
    }
  }

  static func shouldShowSeasonSubscriptionSection(
    canSubscribeMedia: Bool,
    detail: MediaInfo,
    isSeasonDataLoaded: Bool,
    seasonCount: Int?,
    hasSeasonLoadError: Bool,
    isSeasonLoading: Bool = false
  ) -> Bool {
    guard canSubscribeMedia && detail.type == "电视剧" && !detail.canDirectlySubscribe else {
      return false
    }
    if isSeasonLoading { return true }
    if hasSeasonLoadError { return true }
    return !isSeasonDataLoaded || (seasonCount ?? 0) > 0
  }

  static func shouldShowOtherInfo(
    canSubscribeMedia: Bool,
    canSearchResources: Bool
  ) -> Bool {
    !canSubscribeMedia && !canSearchResources
  }

  static func isSeasonInformationUnavailable(
    canSubscribeMedia: Bool,
    detail: MediaInfo,
    isSeasonDataLoaded: Bool,
    seasonCount: Int?,
    hasSeasonLoadError: Bool,
    isSeasonLoading: Bool = false
  ) -> Bool {
    canSubscribeMedia && detail.type == "电视剧" && !detail.canDirectlySubscribe
      && isSeasonDataLoaded && (seasonCount ?? 0) == 0 && !hasSeasonLoadError && !isSeasonLoading
  }

  static func headerSubscribeButtonTitle(
    isSubscribed: Bool,
    detail: MediaInfo,
    isSeasonInformationUnavailable: Bool,
    hasSeasonLoadError: Bool,
    isSeasonLoading: Bool,
    isInLibrary: Bool = false
  ) -> String {
    if detail.canDirectlySubscribe {
      let title = isSubscribed ? "已订阅" : "订阅"
      return isInLibrary ? "\(title)（已入库）" : title
    }
    if isSeasonLoading { return "分季信息加载中" }
    if hasSeasonLoadError { return "分季信息加载失败" }
    return isSeasonInformationUnavailable ? "暂无分季信息" : "分季信息"
  }

  private func handleHeaderSubscribe() {
    Task { @MainActor in
      await Self.performHeaderSubscribeAction(
        isSubscribed: isSubscribed,
        refreshSubscribedState: {
          let didRefresh = await viewModel.refreshSubscriptionStatus()
          guard didRefresh else { return nil }
          return viewModel.isSubscribed
        },
        showUnsubscribeConfirm: {
          unsubscribeConfirmationMessage = SubscriptionCancelConfirmation.headerMessage(for: viewModel.detail)
          Task { @MainActor in
            unsubscribeConfirmationMessage = await viewModel.headerUnsubscribeConfirmationMessage()
            showUnsubscribeConfirm = true
          }
        },
        startSubscribe: {
          sheetSubscribe = viewModel.buildSubscribeRequest()
        }
      )
    }
  }

  @ViewBuilder
  private func heroSection(scrollProxy: ScrollViewProxy) -> some View {
    let detail = viewModel.detail
    ZStack(alignment: .bottom) {
      // Content
      HStack(alignment: .bottom, spacing: 0) {
        // Left Side: Title, Metadata, Overview, Buttons
        VStack(alignment: .leading, spacing: 20) {
          // Title
          Text(detail.cleanedTitle ?? "Unknown")
            .font(.largeTitle.bold())
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 740, alignment: .leading)

          let metadataTexts1: [String] = {
            var items: [String] = []
            if let category = detail.category, !category.isEmpty {
              items.append(category)
            } else if let type = detail.type, !type.isEmpty {
              items.append(type)
            }
            if let genres = detail.genres, !genres.isEmpty {
              items.append(
                genres
                  .compactMap { $0.name }
                  .map { TranslationHelper.translateGenre(for: $0) }
                  .joined(separator: " · ")
              )
            }
            return items
          }()

          if !metadataTexts1.isEmpty {
            Text(metadataTexts1.joined(separator: " · "))
              .font(.caption)
              .lineLimit(2)
              .foregroundColor(.primary)
              .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
              .frame(maxWidth: 740, alignment: .leading)
          }

          // Overview
          if let overview = detail.overview, !overview.isEmpty {
            let cleanedOverview =
              overview
              .components(separatedBy: .newlines)
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
              .joined(separator: " ")
            Text(cleanedOverview)
              .font(.caption)
              .lineLimit(5)
              .frame(maxWidth: 740, alignment: .leading)
              .foregroundColor(.primary.opacity(0.8))
              .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
          }

          // Detailed metadata line
          let metadataTexts2: [String] = {
            var items: [String] = []
            if let releaseDate = detail.release_date {
              items.append("\(releaseDate)")
            } else if let year = detail.year {
              items.append(year)
            }
            if let runtime = detail.runtime {
              items.append("\(runtime) 分钟")
            }
            if let vote = detail.vote_average, vote > 0 {
              items.append("评分 \(vote)")
            }
            if let countries = detail.production_countries, !countries.isEmpty {
              items.append(
                countries.map { TranslationHelper.countryName(for: $0) }.joined(separator: " / "))
            }
            if let language = detail.original_language {
              items.append(TranslationHelper.languageName(for: language))
            }
            return items
          }()

          if !metadataTexts2.isEmpty {
            Text(metadataTexts2.joined(separator: " · "))
              .font(.caption)
              .lineLimit(2)
              .foregroundColor(.primary)
              .frame(maxWidth: 740, alignment: .leading)
          }

          // Action Buttons — Apple TV style: primary + icon buttons
          HStack(spacing: 20) {
            // TMDB Jump Button — 复用 MediaActionHandler 逻辑，传入预加载的 tmdbId
            if canJumpToTMDB {
              let targetTmdbId = preloadTask.tmdbId ?? viewModel.detail.tmdb_id
              let isButtonLoading =
                targetTmdbId == nil && !preloadTask.isTmdbRecognitionFinished

              Button(action: {
                let navigationSource = navigationCoordinator.sourceToken()
                Task {
                  if let target = await mediaActionHandler.getTMDBJumpTarget(
                    for: viewModel.detail, targetTmdbId: targetTmdbId)
                  {
                    navigationCoordinator.push(target, ifCurrent: navigationSource)
                  }
                }
              }) {
                Label(
                  title: { Text("TMDB详情页") },
                  icon: {
                    if isButtonLoading {
                      ProgressView().controlSize(.small)
                    } else {
                      Image(systemName: "link")
                    }
                  }
                )
                .foregroundColor(.primary)
              }
              .disabled(isButtonLoading)
            }

            if canSubscribeMedia {
              // Primary subscribe button — 使用预加载的订阅状态
              Button(action: {
                if detail.canDirectlySubscribe {
                  handleHeaderSubscribe()
                } else if detail.type == "电视剧" {
                  isContentFocused = true
                }
              }) {
                if detail.canDirectlySubscribe && viewModel.isUnsubscribing {
                  HStack(spacing: 8) {
                    ProgressView()
                    Text("取消订阅中")
                  }
                  .foregroundColor(.primary)
                } else {
                  let isDirect = detail.canDirectlySubscribe
                  let label = Self.headerSubscribeButtonTitle(
                    isSubscribed: isSubscribed,
                    detail: detail,
                    isSeasonInformationUnavailable: isSeasonInformationUnavailable,
                    hasSeasonLoadError: hasSeasonLoadError,
                    isSeasonLoading: isSeasonLoading,
                    isInLibrary: viewModel.isInLibrary
                  )
                  let icon =
                    isDirect
                    ? (isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                    : (
                      isSeasonLoading
                        ? "arrow.triangle.2.circlepath"
                        : (
                          hasSeasonLoadError
                            ? "exclamationmark.circle"
                            : (isSeasonInformationUnavailable ? "info.circle" : "list.bullet.circle")
                        )
                    )

                  Label(label, systemImage: icon)
                    .foregroundColor(.primary)
                }
              }
              .focused($focusedButton, equals: .subscribe)
              .disabled(detail.canDirectlySubscribe && viewModel.isUnsubscribing)
            }

            if canSearchResources {
              // Search resources icon button
              Button(action: {
                let request = mediaActionHandler.searchResourcesTarget(
                  for: viewModel.detail,
                  sites: viewModel.siteFilter.sitesString
                )
                navigateFromSecondPage(to: request)
              }) {
                Label("搜索资源", systemImage: "magnifyingglass")
                  .foregroundColor(.primary)
              }
              .focused($focusedButton, equals: .search)
            }

            // Site selection button
            if canSearchResources && shouldShowSiteFilter {
              Button(action: {
                showSiteSelection = true
              }) {
                HStack(spacing: 8) {
                  Image(systemName: "server.rack")
                  Text(viewModel.siteFilter.siteButtonLabel)
                }
                .font(.caption)
                .foregroundColor(.primary)
              }
              .controlSize(.small)
              .focused($focusedButton, equals: .sites)
              .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // 没有订阅和搜索权限时始终提供第二页入口；TMDB 跳转不参与兜底判断。
            if shouldShowOtherInfo {
              Button(action: {
                isContentFocused = true
              }) {
                Label("其他信息", systemImage: "info.circle")
                  .foregroundColor(.primary)
              }
              .focused($focusedButton, equals: .otherInfo)
            }
          }
          .animation(.snappy, value: shouldShowSiteFilter)
        }
        .padding(.bottom, 40)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.62, alignment: .leading)

        Spacer()

        // Right Side: Cast & Director — Apple TV style
        VStack(alignment: .leading, spacing: 12) {
          let topActors = viewModel.heroTopActors
          let topStaff = viewModel.heroTopStaff

          if !topActors.isEmpty {
            (Text("主演  ")
              .foregroundColor(.primary.opacity(0.8))
              + Text(topActors.compactMap { $0.name }.joined(separator: ", "))
              .foregroundColor(.primary))
              .font(.caption)
              .lineLimit(2)
          }

          if !topStaff.isEmpty {
            ForEach(topStaff) { staff in
              (Text("\(staff.job)  ")
                .foregroundColor(.primary.opacity(0.8))
                + Text(staff.names.joined(separator: ", "))
                .foregroundColor(.primary))
                .font(.caption)
                .lineLimit(2)
            }
          }
        }
        .padding(.bottom, 40)
        .frame(width: 480, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .focused($isHeroFocused)
    }
    .focusSection()
    .padding(.horizontal, 81)
    .frame(height: UIScreen.main.bounds.height * 0.94)
  }

  // MARK: - 分季订阅（使用预加载的 SubscribeSeasonViewModel）

  @ViewBuilder
  private var seasonSubscriptionSection: some View {
    if shouldShowSeasonSubscriptionSection {
      VStack(alignment: .leading, spacing: 0) {
        if let seasonVM = preloadTask.seasonViewModel {
          // 使用预加载的 SubscribeSeasonViewModel
          SubscribeSeasonContentView(
            viewModel: seasonVM,
            layout: .shelf,
            title: showContentPage ? "分季订阅" : nil,
            showBadges: showContentPage,
            loadsImages: true,
            onSeasonTap: { season in
              let request = SubscribeSeasonRequest(
                mediaInfo: viewModel.detail,
                initialSeason: season.season_number,
                initialEpisodeGroup: seasonVM.selectedGroupId
              )
              navigateFromSecondPage(to: request)
            },
            onMoreTapped: {
              let request = SubscribeSeasonRequest(
                mediaInfo: viewModel.detail,
                initialSeason: nil,
                initialEpisodeGroup: seasonVM.selectedGroupId
              )
              navigateFromSecondPage(to: request)
            }
          )
        } else {
          // 分季信息尚在加载中
          HStack {
            Spacer()
            ProgressView()
              .padding()
            Spacer()
          }
        }
      }
      .id("seasonSubscriptionSection")
    }
  }

  @ViewBuilder
  private var directorsSection: some View {
    let directors = viewModel.uniqueDirectors
    if !directors.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "directors" {
          Text("职员")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(Array(directors.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let director = entry.element
              PersonCard(
                person: director,
                staffImageUrl: director.imageURLs.profile,
                loadsImage: loadsHorizontalImage(
                  at: index,
                  in: directors,
                  anchorID: directorImageAnchorId,
                  cardKind: .person
                )
              ) {
                navigateFromSecondPage(to: director)
              }
              .focused($focusedDirectorId, equals: director.id)
              .compositingGroup()
              .contextMenu {
                Button {
                  navigateFromSecondPage(to: director)
                } label: {
                  Label("详情", systemImage: "info.circle")
                }
              }
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedDirectorId) { _, newId in
            guard let newId else { return }
            directorImageAnchorId = newId
            MediaPreloader.shared.focusDidMove(
              to: "person:\(newId)",
              stackID: navigationCoordinator.id
            )
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var actorsSection: some View {
    let actors = viewModel.actorsPaginator.items
    if !actors.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "actors" {
          Text("演员")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(Array(actors.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let actor = entry.element
              PersonCard(
                person: actor,
                loadsImage: loadsHorizontalImage(
                  at: index,
                  in: actors,
                  anchorID: actorImageAnchorId,
                  cardKind: .person
                )
              ) {
                navigateFromSecondPage(to: actor)
              }
              .focused($focusedActorId, equals: actor.id)
              .compositingGroup()
              .contextMenu {
                Button {
                  navigateFromSecondPage(to: actor)
                } label: {
                  Label("详情", systemImage: "info.circle")
                }
              }
            }
            if viewModel.actorsPaginator.isLoadingMore {
              posterCenteredLoadingIndicator(height: 315)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedActorId) { _, newId in
            guard let newId else { return }
            actorImageAnchorId = newId
            MediaPreloader.shared.focusDidMove(
              to: "person:\(newId)",
              stackID: navigationCoordinator.id
            )
            Task {
              await viewModel.actorsPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var recommendationsSection: some View {
    if !viewModel.recommendPaginator.items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "recommendations" {
          Text("推荐")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            let badges = showContentPage || firstVisibleRow != "recommendations"
            let items = viewModel.recommendPaginator.items
            ForEach(Array(items.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let media = entry.element
              DetailCardView(
                item: media,
                showBadges: badges,
                loadsImage: loadsHorizontalImage(
                  at: index,
                  in: items,
                  anchorID: recommendImageAnchorId,
                  cardKind: .media
                ),
                imageConfigurationIdentity: apiService.imageConfigurationIdentity,
                onTap: {
                  navigateToMediaFromSecondPage(media)
                }
              )
              .equatable()
              .focused($focusedRecommendId, equals: media.id)
              .mediaContextMenu(item: media)
            }
            if viewModel.recommendPaginator.isLoadingMore {
              posterCenteredLoadingIndicator(height: 384)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedRecommendId) { _, newId in
            // 聚焦时触发预加载（带 300ms 防抖，避免快速滚动时浪费请求）
            recommendPreloadDebounce?.cancel()
            if let newId = newId,
              let item = viewModel.recommendPaginator.items.first(where: { $0.id == newId })
            {
              recommendImageAnchorId = newId
              MediaPreloader.shared.focusDidMove(
                to: newId,
                stackID: navigationCoordinator.id
              )
              recommendPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                MediaPreloader.shared.preloadFocusedCandidateIfNeeded(
                  for: item,
                  stackID: navigationCoordinator.id
                )
              }
            }
            // 分页加载
            guard let newId else { return }
            Task {
              await viewModel.recommendPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  @ViewBuilder
  private var similarSection: some View {
    if !viewModel.similarPaginator.items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "similar" {
          Text("类似")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.leading, 89)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            let badges = showContentPage || firstVisibleRow != "similar"
            let items = viewModel.similarPaginator.items
            ForEach(Array(items.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let media = entry.element
              DetailCardView(
                item: media,
                showBadges: badges,
                loadsImage: loadsHorizontalImage(
                  at: index,
                  in: items,
                  anchorID: similarImageAnchorId,
                  cardKind: .media
                ),
                imageConfigurationIdentity: apiService.imageConfigurationIdentity,
                onTap: {
                  navigateToMediaFromSecondPage(media)
                }
              )
              .equatable()
              .focused($focusedSimilarId, equals: media.id)
              .mediaContextMenu(item: media)
            }
            if viewModel.similarPaginator.isLoadingMore {
              posterCenteredLoadingIndicator(height: 384)
            }
          }
          .padding(.horizontal, 81)
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedSimilarId) { _, newId in
            // 聚焦时触发预加载（带 300ms 防抖）
            similarPreloadDebounce?.cancel()
            if let newId = newId,
              let item = viewModel.similarPaginator.items.first(where: { $0.id == newId })
            {
              similarImageAnchorId = newId
              MediaPreloader.shared.focusDidMove(
                to: newId,
                stackID: navigationCoordinator.id
              )
              similarPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                MediaPreloader.shared.preloadFocusedCandidateIfNeeded(
                  for: item,
                  stackID: navigationCoordinator.id
                )
              }
            }
            // 分页加载
            guard let newId else { return }
            Task {
              await viewModel.similarPaginator.loadMore(newId)
            }
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
  }

  private func posterCenteredLoadingIndicator(height: CGFloat) -> some View {
    VStack(spacing: 10) {
      ProgressView()
        .frame(width: 100, height: height)
      Color.clear
        .frame(width: 100, height: 44)
    }
  }
}
