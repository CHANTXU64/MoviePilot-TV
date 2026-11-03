import Kingfisher
import SwiftUI

private final class MediaDetailImageLifetime {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  var isBackgroundMounted = true
  var didReleaseAfterPop = false
}

/// 详情页「演员 / 职员」合并行当前展示的分类。
enum MediaDetailCreditKind: String, CaseIterable, Identifiable {
  case cast
  case crew

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cast: return "演员"
    case .crew: return "职员"
    }
  }

  /// 有内容的分类，按「演员、职员」的顺序。
  static func available(hasCast: Bool, hasCrew: Bool) -> [MediaDetailCreditKind] {
    allCases.filter { $0 == .cast ? hasCast : hasCrew }
  }

  /// 实际展示的分类；返回 nil 时整行不渲染。
  ///
  /// 所选分类有内容就展示它。默认的演员没有内容时，要等演员首轮加载结束（确认为空或失败）
  /// 才退到职员：职员随详情同步到达、演员要等网络，不等的话几乎每次进页都会先渲染职员行、
  /// 白白请求一批职员头像，演员一到又换回来。
  static func resolved(
    selected: MediaDetailCreditKind,
    hasCast: Bool,
    hasCrew: Bool,
    isCastSettled: Bool
  ) -> MediaDetailCreditKind? {
    switch selected {
    case .cast:
      if hasCast { return .cast }
      return isCastSettled && hasCrew ? .crew : nil
    case .crew:
      if hasCrew { return .crew }
      return hasCast ? .cast : nil
    }
  }
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
  @State private var subscriptionHandler = SubscriptionHandler()
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.topShelfPresentation) private var topShelfPresentation
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
  let presentationStyle: MediaDetailPresentationStyle
  @State private var cachedBackgroundFailed = false
  private var cachedContent: TopShelfCachedContent? {
    cachedBackgroundFailed ? nil : preloadTask.preparedContent
  }
  let allowsRequests: Bool
  @State private var showSiteSelection = false
  @State private var showContentPage = false
  /// TMDB 跳转动作的同步防重入标记；预识别期间沿用原有 disabled 门禁。
  @State private var isTMDBJumpInFlight = false
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
  /// 当前打开的豆瓣短评/影评详情
  @State private var selectedDoubanDiscussion: DoubanDiscussionEntry?
  /// 「演员 / 职员」行选中的分类。默认演员；演员确认为空、退到职员后记成职员，
  /// 之后演员重新加载（如页面重新激活时重试空结果）也不会让这一行消失或被换掉。
  @State private var selectedCreditKind: MediaDetailCreditKind = .cast
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
  /// 豆瓣区块的焦点：条目 ID，或没有条目时的状态卡 `doubanStatusFocusID`。
  @FocusState private var focusedDiscussionId: String?
  @FocusState private var isHeroFocused: Bool
  @FocusState private var isContentFocused: Bool
  /// 第二页当前含焦点的行，取值与 `firstVisibleRow` 相同。
  @FocusState private var focusedContentRow: String?
  enum ButtonField {
    case subscribe, search, subtitleSearch, sites, otherInfo
  }
  @FocusState private var focusedButton: ButtonField?
  @State private var lastFocusedButton: ButtonField?

  /// 音乐走独立订阅链，TV 不提供入口：既不能当电影直接订阅，也不能进分季流程（否则是死按钮）。
  private var canSubscribeMedia: Bool {
    apiService.canAccess(.subscribe) && !viewModel.detail.isCollection
      && viewModel.detail.type != "音乐"
  }

  private var canSearchResources: Bool {
    apiService.canAccess(.search)
  }

  private var canSearchSubtitles: Bool {
    canSearchResources && SubtitleSearchRequest.supportsSubtitleSearch(viewModel.detail)
      && viewModel.detail.identity != nil
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

  /// 豆瓣短评/影评的入口条件：后端版本 >= v3.2.1、有豆瓣 ID、类型是电影或电视剧。
  /// 条件在请求前后都会重新求值，读不出版本时按「隐藏并不可发请求」处理。
  private var isDoubanDiscussionEligible: Bool {
    DoubanDiscussionAvailability.isEligible(
      detail: viewModel.detail,
      backendVersion: apiService.settings?.BACKEND_VERSION
    )
  }

  /// 区块实际是否渲染：入口条件满足，且至少一类处于加载中、失败或有内容。
  private var showsDoubanDiscussionSection: Bool {
    isDoubanDiscussionEligible && viewModel.isDoubanDiscussionSectionVisible
  }

  private static let doubanStatusFocusID = "douban-discussion-status"
  private static let doubanRowStartID = "douban-discussion-row-start"
  private static let creditsRowStartID = "credits-row-start"

  /// 「演员 / 职员」行实际展示的分类；两类都没有时为 nil，整行不渲染。
  private var creditKind: MediaDetailCreditKind? {
    let actors = viewModel.actorsPaginator
    return MediaDetailCreditKind.resolved(
      selected: selectedCreditKind,
      hasCast: !actors.items.isEmpty,
      hasCrew: !viewModel.uniqueDirectors.isEmpty,
      isCastSettled: !actors.isLoading && (actors.hasError || !actors.hasMore)
    )
  }

  private var preferredHeaderFocus: ButtonField? {
    if canSubscribeMedia { return .subscribe }
    if canSearchResources { return .search }
    if shouldShowOtherInfo { return .otherInfo }
    return nil
  }

  private static let pageTransitionAnimation = Animation.easeInOut(duration: 0.6)

  /// 第一页 ⇄ 第二页的滚动放到下一轮主线程再开始。
  ///
  /// 切页会插入（或移除）第二页大标题、首行标题等内容，这段布局动画要等本轮更新提交后才起步；
  /// 滚动若在同一轮发起会先跑，先到终点后卡片又被还在长高的标题挤下去，看起来往上弹一下。
  /// 推迟一轮让两段动画同时起步、按同一条曲线走完。期间焦点已换页时放弃这次滚动。
  private func scrollAfterPageLayout(
    _ proxy: ScrollViewProxy,
    to id: String,
    whenContentPage expectedContentPage: Bool
  ) {
    DispatchQueue.main.async {
      guard showContentPage == expectedContentPage else { return }
      withAnimation(Self.pageTransitionAnimation) {
        proxy.scrollTo(id, anchor: .top)
      }
    }
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
    if focusedButton == .search || focusedButton == .subtitleSearch || focusedButton == .sites {
      return true
    }
    if focusedButton == nil
      && (lastFocusedButton == .search || lastFocusedButton == .subtitleSearch
        || lastFocusedButton == .sites)
    {
      return true
    }
    return false
  }

  private var firstVisibleRow: String {
    if shouldShowSeasonSubscriptionSection {
      return "season"
    }
    if creditKind != nil {
      return "credits"
    }
    if showsDoubanDiscussionSection {
      return "doubanDiscussion"
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
    loadingPosterURL: URL?,
    presentationStyle: MediaDetailPresentationStyle = .standard,
    allowsRequests: Bool = true
  ) {
    let vm = MediaDetailViewModel(detail: detail)
    vm.preloadTask = preloadTask
    _viewModel = StateObject(wrappedValue: vm)
    self.preloadTask = preloadTask
    _isContentReady = isContentReady
    self.routeID = routeID
    self.imageLifecycle = imageLifecycle
    self.loadingPosterURL = loadingPosterURL
    self.presentationStyle = presentationStyle
    self.allowsRequests = allowsRequests
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

      if isBackgroundMounted, imageLifecycle.keepsActivePageImages,
        (cachedContent != nil || presentationStyle == .direct),
        let localBackground = cachedContent?.backgroundURL ?? loadingPosterURL,
        localBackground.isFileURL
      {
        MediaDetailBackgroundLayer(
          url: localBackground, usingPosterAsBackdrop: cachedContent?.backgroundIsPoster ?? true,
          onFailure: { _ in cachedBackgroundFailed = true }
        )
          .opacity(showContentPage ? 0 : 1)
      }

      if isBackgroundMounted && imageLifecycle.keepsActivePageImages,
        cachedContent == nil,
        presentationStyle == .standard || (allowsRequests && preloadTask.fullDetail != nil)
      {
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
                  .font(.title2.bold())
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.bottom, 10)
                  .transition(.opacity)
              }

              seasonSubscriptionSection
                .focused($focusedContentRow, equals: "season")
              creditsSection
                .focused($focusedContentRow, equals: "credits")
              doubanDiscussionSection
                .focused($focusedContentRow, equals: "doubanDiscussion")
              recommendationsSection
                .focused($focusedContentRow, equals: "recommendations")
              similarSection
                .focused($focusedContentRow, equals: "similar")
            }
            .id("contentTop")
            // tvOS 会把聚焦控件保持在离滚动区顶部约 180pt 以外。60pt 时首行可聚焦标题（胶囊、
            // 分季的剧集组按钮）离顶部不到 180pt，焦点从卡片移上去会再滚几 pt；实测 72pt 起不再滚。
            .padding(.top, showContentPage ? 72 : 0)
            .padding(.bottom, 80)
            .focused($isContentFocused)
            .animation(Self.pageTransitionAnimation, value: showContentPage)
            .onChange(of: isHeroFocused) { _, focused in
              guard focused else { return }
              remountBackgroundForHeroIfNeeded()
              withAnimation(Self.pageTransitionAnimation) {
                showContentPage = false
              }
              scrollAfterPageLayout(proxy, to: "top", whenContentPage: false)
            }
            .onChange(of: isContentFocused) { _, focused in
              guard focused, !showContentPage else { return }
              withAnimation(Self.pageTransitionAnimation) {
                showContentPage = true
              }
              scrollAfterPageLayout(proxy, to: "contentTop", whenContentPage: true)
            }
            // 第二页从下面的行回到首行时，系统只把聚焦的卡片滚进可视区，首行上方的胶囊标题
            // 和页面大标题会被截掉。焦点一进首行就回到第二页顶部，与从 Hero 进来时位置一致。
            .onChange(of: focusedContentRow) { _, row in
              guard showContentPage, let row, row == firstVisibleRow else { return }
              withAnimation(Self.pageTransitionAnimation) {
                proxy.scrollTo("contentTop", anchor: .top)
              }
            }

            Color.clear
              .frame(height: UIScreen.main.bounds.height)
          }
        }
      }
    }
    .disabled(!allowsRequests)
    .onChange(of: apiService.imageConfigurationIdentity) { _, _ in
      guard allowsRequests else { return }
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
    .task(id: allowsRequests) {
      guard allowsRequests else { return }
      if presentationStyle == .standard, !hasAppeared, let preferredHeaderFocus {
        focusedButton = preferredHeaderFocus
        hasAppeared = true
      } else if presentationStyle == .standard, !hasAppeared {
        hasAppeared = true
      }
      // 如果 fullDetail 已经就绪（预加载命中），立即应用（网络加载自动在后台启动）
      hasRefreshedSubscriptionAfterFullDetail = await Self.applyReadyPreloadedDetail(
        from: preloadTask,
        to: viewModel,
        hasRefreshedSubscription: hasRefreshedSubscriptionAfterFullDetail,
        requiresBackgroundReady: presentationStyle.usesLoadingTransition
      )
      if canSearchResources {
        await viewModel.siteFilter.loadSites()
      }
      // 重新激活时自动恢复成功空终态的推荐/相似/演员区域
      await viewModel.refreshSuccessEmptySections()
      // 进详情页就拉短评/影评第一页（不预载）；版本等条件晚到时由这里补发。
      viewModel.loadDoubanDiscussionIfNeeded()
    }
    .task(id: allowsRequests) {
      guard allowsRequests else { return }
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
      guard allowsRequests else { return }
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
      if isLoaded, allowsRequests, presentationStyle == .standard {
        Task { @MainActor in
          hasRefreshedSubscriptionAfterFullDetail = await Self.applyReadyPreloadedDetail(
            from: preloadTask,
            to: viewModel,
            hasRefreshedSubscription: hasRefreshedSubscriptionAfterFullDetail
          )
        }
      }
    }
    .onChange(of: preloadTask.fullDetail) { _, detail in
      guard allowsRequests, presentationStyle == .direct, detail != nil else { return }
      Task { @MainActor in
        hasRefreshedSubscriptionAfterFullDetail = await Self.applyReadyPreloadedDetail(
          from: preloadTask,
          to: viewModel,
          hasRefreshedSubscription: hasRefreshedSubscriptionAfterFullDetail,
          requiresBackgroundReady: false
        )
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
      if allowsRequests && isLoaded && canSubscribeMedia && !viewModel.isFirstRowReady
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
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      subscriptionHandler.cancelPresentation()
      subscriptionHandler = SubscriptionHandler()
      sheetSubscribe = nil
      showSiteSelection = false
      showUnsubscribeConfirm = false
      selectedDoubanDiscussion = nil
    }
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .sheet(isPresented: $showSiteSelection) {
      SearchSiteSelectionSheet(viewModel: viewModel.siteFilter)
    }
    // 短评/影评详情：正文长文靠段落焦点停靠点驱动纵向滚动，不用浏览器打开豆瓣链接。
    .sheet(item: $selectedDoubanDiscussion) { entry in
      DoubanDiscussionDetailSheet(
        entry: entry,
        avatarURL: apiService.getDoubanCommentAvatarImageUrl(entry.avatar)
      )
    }
    .onChange(of: focusedButton) { _, newValue in
      if let newValue = newValue {
        lastFocusedButton = newValue
      }
    }
    // 设置为晚到（例如启动后才拿到 BACKEND_VERSION）或详情后到时补发首屏请求；
    // 请求成功后 `loadDoubanDiscussionIfNeeded` 自己不会再重发。
    .onChange(of: isDoubanDiscussionEligible) { _, eligible in
      guard eligible, allowsRequests else { return }
      viewModel.loadDoubanDiscussionIfNeeded()
    }
    .background(PresentationReadyAction(
      isEnabled: presentationStyle == .direct && !hasAppeared && allowsRequests
        && !topShelfPresentation.blocksInteraction && scenePhase == .active
        && navigationCoordinator.isStackInteractive && navigationCoordinator.topEntryID == routeID,
      requiresNavigationTop: true,
      contentFocusMatches: isHeroFocused && focusedButton == preferredHeaderFocus,
      onContentFocus: { hasAppeared = true },
      action: { focusedButton = preferredHeaderFocus }
    ))
  }

  private func navigateFromSecondPage(to destination: Person) {
    navigationCoordinator.push(destination)
  }

  private func navigateFromSecondPage(to destination: ResourceSearchRequest) {
    navigationCoordinator.push(destination)
  }

  private func navigateFromSecondPage(to destination: SubtitleSearchRequest) {
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
    APIService.shared.mediaPreloader.setHeroPresented(
      false,
      for: viewModel.detail,
      owner: routeID,
      size: size,
      screenScale: screenScale,
    )
  }

  private func discardLoadedBackgroundIfAbandoned(url: URL) {
    APIService.shared.mediaPreloader.discardLoadedBackgroundIfAbandoned(
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
    APIService.shared.mediaPreloader.setHeroPresented(
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
    hasRefreshedSubscription: Bool,
    requiresBackgroundReady: Bool = true
  ) async -> Bool {
    guard !requiresBackgroundReady || preloadTask.isDetailReady,
      let fullDetail = preloadTask.fullDetail
    else {
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
    let source = navigationCoordinator.sourceToken()
    Task { @MainActor in
      await Self.performHeaderSubscribeAction(
        isSubscribed: isSubscribed,
        refreshSubscribedState: {
          let didRefresh = await viewModel.refreshSubscriptionStatus()
          guard didRefresh, navigationCoordinator.isCurrent(source) else { return nil }
          return viewModel.isSubscribed
        },
        showUnsubscribeConfirm: {
          unsubscribeConfirmationMessage = SubscriptionCancelConfirmation.headerMessage(for: viewModel.detail)
          Task { @MainActor in
            let message = await viewModel.headerUnsubscribeConfirmationMessage()
            guard navigationCoordinator.isCurrent(source) else { return }
            unsubscribeConfirmationMessage = message
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
            .font(.title2.bold())
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 740, alignment: .leading)

          // 第一行元数据组装见 `MediaMetadataText.primaryLine`：
          // 空串/畸形类型不再拼出悬空分隔符（F-038/F-043/F-046）。
          let metadataTexts1: [String] = MediaMetadataText.primaryLine(for: detail)

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
              .foregroundColor(.secondary)
              .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
          }

          // Detailed metadata line
          // 第二行元数据组装见 `MediaMetadataText.secondaryLine`（同上）。
          let metadataTexts2: [String] = MediaMetadataText.secondaryLine(for: detail)

          if !metadataTexts2.isEmpty {
            Text(metadataTexts2.joined(separator: " · "))
              .font(.caption)
              .lineLimit(2)
              .foregroundColor(.primary)
              .frame(maxWidth: 740, alignment: .leading)
          }

          // Action Buttons — Apple TV style: primary + icon buttons
          if presentationStyle == .direct {
            if !allowsRequests {
              Label("正在验证登录状态…", systemImage: "person.crop.circle")
                .font(.caption).foregroundStyle(.secondary)
            } else if preloadTask.isDetailFailed {
              Text("详情加载失败，请返回后重试")
                .font(.caption).foregroundStyle(.secondary)
            } else if preloadTask.fullDetail == nil {
              ProgressView("正在加载详情…")
                .font(.caption)
            }
          }
          HStack(spacing: 20) {
            // TMDB Jump Button — 复用 MediaActionHandler 逻辑，传入预加载的 tmdbId
            if canJumpToTMDB {
              let targetTmdbId = preloadTask.tmdbId ?? viewModel.detail.tmdb_id
              let isButtonLoading =
                targetTmdbId == nil && !preloadTask.isTmdbRecognitionFinished

              Button(action: {
                // 预识别期间沿用原有禁用门禁；其余重复 Select 只在动作入口被忽略。
                guard !isButtonLoading, !isTMDBJumpInFlight else { return }
                isTMDBJumpInFlight = true
                let navigationSource = navigationCoordinator.sourceToken()
                Task {
                  defer { isTMDBJumpInFlight = false }
                  if let target = await mediaActionHandler.getTMDBJumpTarget(
                    for: viewModel.detail, targetTmdbId: targetTmdbId)
                  {
                    navigationCoordinator.push(
                      target,
                      loadingPosterURL: viewModel.detail.imageURLs.poster,
                      ifCurrent: navigationSource
                    )
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
                guard !(detail.canDirectlySubscribe && viewModel.isUnsubscribing) else { return }
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
              // 取消订阅中保持可聚焦：tvOS 上聚焦元素变 disabled 会导致焦点跳走并触发滚动；
              // 点击已由 action 内 guard 忽略。
            }

            if canSearchResources {
              // Search resources icon button
              Button(action: {
                let request = mediaActionHandler.searchResourcesTarget(
                  for: viewModel.detail,
                  sites: viewModel.siteFilter.sitesString(for: .resource)
                )
                navigateFromSecondPage(to: request)
              }) {
                Label("搜索资源", systemImage: "magnifyingglass")
                  .foregroundColor(.primary)
              }
              .focused($focusedButton, equals: .search)
            }

            if canSearchSubtitles {
              Button(action: {
                guard let request = mediaActionHandler.subtitleSearchRequest(
                  for: viewModel.detail,
                  sites: viewModel.siteFilter.sitesString(for: .subtitle)
                ) else { return }
                navigateFromSecondPage(to: request)
              }) {
                Label("搜索字幕", systemImage: "captions.bubble")
                  .foregroundColor(.primary)
              }
              .focused($focusedButton, equals: .subtitleSearch)
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
          .disabled(!allowsRequests)
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
              .foregroundColor(.secondary)
              + Text(topActors.compactMap { $0.name }.joined(separator: ", "))
              .foregroundColor(.primary))
              .font(.caption)
              .lineLimit(2)
          }

          if !topStaff.isEmpty {
            ForEach(topStaff) { staff in
              (Text("\(staff.job)  ")
                .foregroundColor(.secondary)
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

  /// 「演员 / 职员」合并成一行，顶部胶囊切换；只有一类有内容时直接显示标题。
  ///
  /// 只渲染选中的那一类：另一类的卡片不在视图树里，不会加载头像，切走时已加载的图片随卡片一起释放。
  /// 切换后行回到开头，图片窗口的锚点同步清空，否则窗口仍停在上次浏览的位置，开头几张卡片拿不到图。
  @ViewBuilder
  private var creditsSection: some View {
    if let kind = creditKind {
      let kinds = MediaDetailCreditKind.available(
        hasCast: !viewModel.actorsPaginator.items.isEmpty,
        hasCrew: !viewModel.uniqueDirectors.isEmpty
      )
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "credits" {
          Group {
            if kinds.count > 1 {
              ShelfPicker(
                items: kinds,
                selection: Binding(
                  get: { creditKind },
                  set: { if let option = $0 { selectCreditKind(option) } }
                ),
                title: \.title
              )
              .font(.callout)
              .padding(.leading, 81)
            } else {
              Text(kind.title)
                .font(.callout)
                .bold()
                .foregroundStyle(.secondary)
                .padding(.leading, 89)
            }
          }
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40) {
              switch kind {
              case .cast:
                actorCards
              case .crew:
                directorCards
              }
            }
            .padding(.horizontal, 81)
            // 锚点包含左右内边距：滚回开头时保留 81pt 左边距，不让第一张卡贴着屏幕左边。
            .id(Self.creditsRowStartID)
            .padding(.top, 25)
            .padding(.bottom, 30)
            .onChange(of: focusedActorId) { _, newId in
              guard let newId else { return }
              actorImageAnchorId = newId
              APIService.shared.mediaPreloader.focusDidMove(
                to: "person:\(newId)",
                stackID: navigationCoordinator.id
              )
              Task {
                await viewModel.actorsPaginator.loadMore(newId)
              }
            }
            .onChange(of: focusedDirectorId) { _, newId in
              guard let newId else { return }
              directorImageAnchorId = newId
              APIService.shared.mediaPreloader.focusDidMove(
                to: "person:\(newId)",
                stackID: navigationCoordinator.id
              )
            }
          }
          .scrollClipDisabled()
          .focusSection()
          .onChange(of: kind) { _, _ in
            resetCreditImageAnchors()
            proxy.scrollTo(Self.creditsRowStartID, anchor: .leading)
          }
          // 退到职员后记住这个选择（含首次出现就是职员的情况）。
          .onChange(of: kind, initial: true) { _, newKind in
            if newKind == .crew, selectedCreditKind != .crew { selectedCreditKind = .crew }
          }
        }
        // 胶囊自带 zIndex(1)。翻到第二页时它从卡片位置往上滑入，卡片行必须盖在它上面，
        // 否则实心胶囊会在滑动途中挡住头像；纯文字标题本来就画在卡片下面，效果与之一致。
        .zIndex(2)
      }
    }
  }

  @ViewBuilder
  private var actorCards: some View {
    let actors = viewModel.actorsPaginator.items
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

  @ViewBuilder
  private var directorCards: some View {
    let directors = viewModel.uniqueDirectors
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

  private func selectCreditKind(_ kind: MediaDetailCreditKind) {
    guard kind != creditKind else { return }
    // 同一次更新里先清锚点：新一行首次求值时就按开头计算图片窗口。
    resetCreditImageAnchors()
    selectedCreditKind = kind
  }

  private func resetCreditImageAnchors() {
    actorImageAnchorId = nil
    directorImageAnchorId = nil
  }

  /// 豆瓣「短评 / 影评」区块：顶部胶囊切换分类，下面是当前分类的横向卡片。
  /// 入口条件（版本 / 豆瓣 ID / 类型）不满足时整块不渲染，也不会发请求。
  @ViewBuilder
  private var doubanDiscussionSection: some View {
    if showsDoubanDiscussionSection {
      let kind = viewModel.doubanDiscussionKind
      let paginator = viewModel.doubanPaginator(for: kind)
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "doubanDiscussion" {
          // 与推荐页货架同一个选择器：焦点从上下相邻行移进来时落到当前选中的分类上。
          ShelfPicker(
            items: DoubanDiscussionEntry.Kind.allCases,
            selection: Binding(
              get: { viewModel.doubanDiscussionKind },
              set: { if let option = $0 { viewModel.selectDoubanDiscussion(option) } }
            ),
            title: { viewModel.doubanChipTitle(for: $0) }
          )
          .font(.callout)
          .padding(.leading, 81)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40) {
              if paginator.items.isEmpty {
                // 加载中 / 失败 / 为空共用同一个状态卡，状态变化时焦点不丢。
                let status = doubanStatus(for: viewModel.doubanRowState(for: kind))
                DoubanDiscussionStatusCard(kind: kind, status: status)
                  .focused($focusedDiscussionId, equals: Self.doubanStatusFocusID)
                if status == .failed {
                  Button {
                    // 先把焦点交给状态卡：按下后按钮随即消失，焦点不能跟着掉出本区块。
                    focusedDiscussionId = Self.doubanStatusFocusID
                    viewModel.retryDoubanDiscussion()
                  } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                  }
                }
              } else {
                ForEach(paginator.items) { entry in
                  DoubanDiscussionCard(
                    entry: entry,
                    avatarURL: apiService.getDoubanCommentAvatarImageUrl(entry.avatar),
                    onTap: { selectedDoubanDiscussion = entry }
                  )
                  .focused($focusedDiscussionId, equals: entry.id)
                }
                if paginator.isLoadingMore {
                  posterCenteredLoadingIndicator(height: DoubanDiscussionCard.cardHeight)
                } else if paginator.hasError {
                  // 加载更多失败：连续失败到上限后移动焦点不会再请求，这里给一个手动恢复入口。
                  Button {
                    // 先把焦点交给最后一张卡：按下后按钮换成加载指示，焦点不能跟着掉出本区块。
                    if let lastId = paginator.items.last?.id {
                      focusedDiscussionId = lastId
                    }
                    viewModel.retryDoubanDiscussionNextPage()
                  } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                  }
                }
              }
            }
            .padding(.horizontal, 81)
            // 锚点包含左右内边距：滚回开头时保留 81pt 左边距，不让第一张卡贴着屏幕左边。
            .id(Self.doubanRowStartID)
            .padding(.top, 30)
            .padding(.bottom, 40)
          }
          .scrollClipDisabled()
          .focusSection()
          // 切换分类后从头展示，避免沿用上一类的横向滚动位置。
          .onChange(of: kind) { _, _ in
            proxy.scrollTo(Self.doubanRowStartID, anchor: .leading)
          }
        }
        // 同演员行：滑入中的胶囊画在卡片下面，不挡卡片。
        .zIndex(2)
        .onChange(of: focusedDiscussionId) { _, newId in
          guard let newId, newId != Self.doubanStatusFocusID else { return }
          Task { await viewModel.doubanPaginator(for: kind).loadMore(newId) }
        }
        // 焦点停在状态卡上时内容到了：把焦点交给第一张卡，状态卡被移除时焦点不会跳出本区块。
        .onChange(of: paginator.items.first?.id) { _, firstId in
          guard let firstId, focusedDiscussionId == Self.doubanStatusFocusID else { return }
          focusedDiscussionId = firstId
        }
      }
    }
  }

  private func doubanStatus(
    for state: DoubanDiscussionRowState
  ) -> DoubanDiscussionStatusCard.Status {
    switch state {
    case .failed: return .failed
    case .empty: return .empty
    case .idle, .loading, .ready: return .loading
    }
  }

  @ViewBuilder
  private var recommendationsSection: some View {
    if !viewModel.recommendPaginator.items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if showContentPage || firstVisibleRow != "recommendations" {
          Text("推荐")
            .font(.callout)
            .bold()
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
              APIService.shared.mediaPreloader.focusDidMove(
                to: newId,
                stackID: navigationCoordinator.id
              )
              recommendPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                APIService.shared.mediaPreloader.preloadFocusedCandidateIfNeeded(
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
            .bold()
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
              APIService.shared.mediaPreloader.focusDidMove(
                to: newId,
                stackID: navigationCoordinator.id
              )
              similarPreloadDebounce = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                APIService.shared.mediaPreloader.preloadFocusedCandidateIfNeeded(
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
