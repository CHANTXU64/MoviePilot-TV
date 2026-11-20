import Combine
import Kingfisher
import SwiftUI

@MainActor
struct HomeView: View {
  private let isSelected: Bool
  @StateObject private var viewModel: HomeViewModel
  @ObservedObject private var apiService = APIService.shared
  @Environment(\.scenePhase) private var scenePhase

  // Sheet 状态
  @State private var selectedSubscribe: Subscribe?

  // 导航状态
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()

  init(isSelected: Bool = true, viewModel: HomeViewModel? = nil) {
    self.isSelected = isSelected
    _viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
  }

  var body: some View {
    NavigationStack(path: $navigationCoordinator.path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 30) {
          if viewModel.isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, minHeight: 200)
          } else {
            // 部分数据失败：保留旧快照并提示（成功空不算失败）
            if viewModel.latestLoadFailed || viewModel.subscriptionsLoadFailed {
              HStack {
                Text("部分数据加载失败，当前显示的是旧数据")
                  .font(.body)
                  .foregroundColor(.secondary)
                Button("重试") {
                  Task { await viewModel.refreshData() }
                }
              }
              .padding(.horizontal)
            }

            // 第1节：最近添加
            if !viewModel.latestMediaServers.isEmpty {
              MediaSectionView(
                title: "最近添加",
                items: viewModel.latestMedia,
                servers: viewModel.latestMediaServers,
                selectedServer: $viewModel.selectedLatestMediaServer,
                isFirstRow: true,
                loadsPageImages: true,
                viewModel: viewModel
              )
            }

            // 第2节：电影订阅
            if !viewModel.movieSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电影订阅",
                items: viewModel.movieSubscriptions,
                isFirstRow: viewModel.latestMediaServers.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            // 第3节：电视剧订阅
            if !viewModel.tvSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电视剧订阅",
                items: viewModel.tvSubscriptions,
                isFirstRow: viewModel.latestMediaServers.isEmpty
                  && viewModel.movieSubscriptions.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            if viewModel.latestMediaServers.isEmpty && viewModel.movieSubscriptions.isEmpty
              && viewModel.tvSubscriptions.isEmpty
            {
              if viewModel.latestLoadFailed || viewModel.subscriptionsLoadFailed {
                VStack(spacing: 12) {
                  Text("加载失败，请重试")
                    .font(.headline)
                    .foregroundColor(.secondary)
                  Button("重试") {
                    Task { await viewModel.refreshData() }
                  }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
              } else {
                Text("暂无内容")
                  .font(.headline)
                  .foregroundColor(.secondary)
                  .frame(maxWidth: .infinity, minHeight: 200)
              }
            }
          }
        }
      }
      .task {
        // 每次页面出现时都会先加载一次（内部有 hasLoaded 控制全屏 Loading）
        await viewModel.loadData()

        // 定期刷新数据（类似 Status 页面的下载器/整理信息）
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
          guard !Task.isCancelled else { break }
          await viewModel.refreshData()
        }
      }
      // 编辑订阅 Sheet
      .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in selectedSubscribe = nil }
      .sheet(item: $selectedSubscribe) { subscribe in
        SubscribeSheet(subscribe: subscribe)
      }
      // 导航目的地
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .onAppear {
      updateStackForeground()
    }
    .onChange(of: isSelected) { _, _ in
      updateStackForeground()
    }
    .onChange(of: scenePhase) { _, _ in
      updateStackForeground()
    }
  }

  // MARK: - 动作

  private func presentEditSheet(for subscribe: Subscribe) {
    self.selectedSubscribe = subscribe
  }

  private func navigateToDetail(for subscribe: Subscribe) {
    // 订阅列表的 navigationMediaInfo() 不含海报（poster_path 为 nil），
    // 必须显式携带订阅海报，否则冷加载阶段详情背景没有海报兜底。
    navigationCoordinator.push(
      subscribe.navigationMediaInfo(),
      loadingPosterURL: subscribe.imageURLs.poster
    )
  }

  private func updateStackForeground() {
    navigationCoordinator.setStackPresentation(isSelected: isSelected, scenePhase: scenePhase)
  }
}

enum HomeSubscribeFocusID {
  static func value(for id: Int?) -> String? {
    id.map(String.init)
  }
}

// MARK: - 子视图

private struct MediaSectionView: View {
  /// 卡片海报向服务端请求的缩略宽度，与卡片降采样后实际保留的像素一致。
  private static let cardPosterPixelWidth = MediaCard.posterThumbnailMaxWidth(
    for: MediaCard.defaultPosterSize)

  private var memoryOptimization = MemoryOptimizationSettings()
  let title: String
  let items: [MediaServerPlayItem]
  let servers: [String]
  @Binding var selectedServer: String
  var isFirstRow: Bool = false
  let loadsPageImages: Bool
  @ObservedObject var viewModel: HomeViewModel

  @Environment(\.openURL) private var openURL
  @Environment(\.playbackFocusHandoff) private var playbackFocusHandoff
  @Environment(\.playbackEndedGeneration) private var playbackEndedGeneration
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  @EnvironmentObject private var notificationManager: NotificationManager
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false
  @State private var imageAnchorId: String?
  /// 这一行的实例身份，焦点只交回起播的那一个。
  @State private var focusOwnerID = UUID()
  /// 正在等待焦点写回的媒体卡；播放器收起有转场，同一次更新里写回会被丢掉，交给 `PresentationReadyAction` 轮询。
  @State private var pendingFocusRestore: String?
  /// 每次开始恢复自增，用来让上一轮的 3 秒超时失效。
  @State private var focusRestoreGeneration = 0

  private var canSearchResources: Bool {
    APIService.shared.canAccess(.search)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text(title)
          .font(.callout)
          .bold()
          .foregroundStyle(.secondary)
          .focusLiftHeaderPart()

        Spacer()

        if servers.count > 1 {
          Picker("服务器", selection: $selectedServer) {
            ForEach(servers, id: \.self) { server in
              Text(server).tag(server)
            }
          }
          .pickerStyle(.menu)
          .focusLiftHeaderPart()
        }
      }
      .padding(.horizontal, 8)
      .focusSection()

      if isFirstRow {
        // 顶部焦点重定向器：确保在首次加载时来自标签栏的焦点进入第一个项目，然后禁用自身。
        Color.clear
          .frame(height: 1)
          .focusable(!hasRedirectedFocus)
          .focused($isTopRedirectorFocused)
          .onChange(of: isTopRedirectorFocused) { _, isFocused in
            if isFocused {
              focusedItemId = items.first?.id
              hasRedirectedFocus = true
              isTopRedirectorFocused = false
            }
          }
      }

      if items.isEmpty {
        Text("该服务器暂无最近内容")
          .font(.headline)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
          .padding(.top, 25)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(Array(items.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let item = entry.element
              let opensApp = viewModel.opensMediaServerApp(item)
              let playsDirectly = !opensApp && viewModel.playsDirectly(item)
              MediaCard(
                title: item.title,
                posterUrl: item.imageURLs(cardPosterPixelWidth: Self.cardPosterPixelWidth).image,
                posterFallbackUrl: viewModel.posterFallbackURL(for: item, server: selectedServer),
                typeText: item.type,
                ratingText: nil,
                bottomLeftText: nil,
                bottomLeftSecondaryText: nil,
                source: nil,
                // 左下角标出按下不是打开详情页的卡片：跳到媒体服务器 App 的是跳转图标；没有 TMDB 编号、
                // MoviePilot 没有详情页的，按下直接播放，是播放图标（和单集卡片一样）。其余的按下打开详情页。
                bottomLeftIcon: opensApp ? AppSymbol.openInLibrary : playsDirectly ? AppSymbol.play : nil,
                loadsImage: loadsPageImages
                  && ImageLoadWindow.containsHorizontalItem(
                    at: index,
                    itemCount: items.count,
                    anchorIndex: imageAnchorId.flatMap { id in
                      items.firstIndex(where: { $0.id == id })
                    },
                    cardKind: .media,
                    usesFocusWindow: memoryOptimization.isEnabled
                  ),
                action: { opensApp ? openMediaItem(item) : openDetail(item) },
                // 媒体服务器上没有封面或读不到时，改用 TMDB 海报。
                onPosterUnavailable: { [selectedServer] in viewModel.loadPosterFallback(for: item, server: selectedServer) }
              )
              .accessibilityHint(opensApp ? "在媒体服务器 App 中打开" : playsDirectly ? "播放" : "打开详情")
              .focused($focusedItemId, equals: item.id)
              .compositingGroup()
              .contextMenu {
                // 按下打开的那一种不再重复列出；有详情页的不在这里直接播放，播放从详情页开始。
                if opensApp {
                  // 没有详情页的条目，在应用内打开就是直接播放。
                  if viewModel.playsDirectly(item) {
                    Button {
                      openDetail(item)
                    } label: {
                      Label("在应用内播放", systemImage: AppSymbol.play)
                    }
                  } else {
                    Button {
                      openDetail(item)
                    } label: {
                      Label("详情", systemImage: AppSymbol.details)
                    }
                  }
                } else if canOpenMediaLibrary(item) {
                  Button {
                    openMediaItem(item)
                  } label: {
                    Label("跳转媒体库", systemImage: AppSymbol.openInLibrary)
                  }
                }
                if canSearchResources {
                  Button {
                    let navigationSource = navigationCoordinator.sourceToken()
                    Task {
                      guard APIService.shared.canAccess(.search) else { return }
                      let sessionSnapshot = APIService.shared.sessionSnapshot()
                      let info = MediaInfo(title: item.title, type: item.type, year: item.subtitle)
                      // 识别不出来会走下面的 else 分支退回按标题搜索，动作照样完成 ——
                      // 因此不要弹「未识别到此媒体的TMDB信息」，否则弹窗与跳转同时发生（F-122）。
                      if let target = await mediaActionHandler.getTMDBJumpTarget(
                        for: info, notifyWhenUnrecognized: false)
                      {
                        if let request =
                          await mediaActionHandler.searchResourcesTargetUsingDefaultSites(
                            for: target)
                        {
                          navigationCoordinator.push(request, ifCurrent: navigationSource)
                        }
                      } else {
                        guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else {
                          return
                        }
                        let sites = await SystemViewModel.normalizedDefaultSearchSitesString()
                        guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else {
                          return
                        }
                        let request = ResourceSearchRequest(
                          keyword: item.title, type: item.type, area: nil, title: nil, year: nil,
                          season: nil, mediaInfo: nil, sites: sites)
                        navigationCoordinator.push(request, ifCurrent: navigationSource)
                      }
                    }
                  } label: {
                    Label("搜索资源", systemImage: AppSymbol.search)
                  }
                }
                if canSearchResources, SubtitleSearchRequest.supportsSubtitleSearch(type: item.type) {
                  Button {
                    let navigationSource = navigationCoordinator.sourceToken()
                    Task {
                      let info = MediaInfo(title: item.title, type: item.type, year: item.subtitle)
                      if let request = await mediaActionHandler.subtitleSearchRequestUsingDefaultSites(
                        for: info, recognizeIfNeeded: true
                      ) {
                        navigationCoordinator.push(request, ifCurrent: navigationSource)
                      }
                    }
                  } label: {
                    Label("搜索字幕", systemImage: AppSymbol.searchSubtitles)
                  }
                }
              }
            }
          }
          .padding(.top, 25)
          .padding(.bottom, 30)
          .onChange(of: focusedItemId) { _, newId in
            // Push 或上下文菜单可能暂时清空焦点；保留当前图片窗口锚点。
            guard let newId else { return }
            imageAnchorId = newId
          }
        }
        .scrollClipDisabled()
        .focusSection()
      }
    }
    .focusLiftRow(cardImageSize: MediaCard.defaultPosterSize)
    // 盖播放器之前把焦点交回起播的媒体卡：模态关闭时系统还原的是盖上去那一刻的焦点项。
    .onChange(of: playbackFocusHandoff.request) { _, _ in
      guard case .homeMedia(let owner, let itemID)? = playbackFocusHandoff.target,
        owner == focusOwnerID
      else { return }
      focusedItemId = itemID
    }
    // 焦点真的落回这张卡了，通知呈现层可以盖播放器。
    .onChange(of: focusedItemId) { _, newValue in
      guard case .homeMedia(let owner, let itemID)? = playbackFocusHandoff.target,
        owner == focusOwnerID, newValue == itemID
      else { return }
      playbackFocusHandoff.acknowledged = playbackFocusHandoff.request
    }
    // 播放结束：盖上过播放器时由系统还原，准备期取消没出来时主动写回。两者都等转场结束后再写。
    .onChange(of: playbackEndedGeneration) { _, _ in
      guard case .homeMedia(let owner, let itemID)? = playbackFocusHandoff.target,
        owner == focusOwnerID
      else { return }
      playbackFocusHandoff.target = nil
      beginFocusRestore(itemID)
    }
    .background(PresentationReadyAction(
      isEnabled: pendingFocusRestore != nil,
      requiresNavigationTop: true,
      contentFocusMatches: pendingFocusRestore.map { focusedItemId == $0 } ?? false,
      onContentFocus: {
        pendingFocusRestore = nil
        focusRestoreGeneration += 1
      },
      action: {
        // 值没变时 SwiftUI 不会重新请求焦点：先把绑定清空，下一帧再写回。
        guard let id = pendingFocusRestore else { return }
        // 轮询期间卡被刷掉：立刻放弃，焦点交给系统默认，不再空转。
        guard items.contains(where: { $0.id == id }) else {
          pendingFocusRestore = nil
          return
        }
        focusedItemId = focusedItemId == id ? nil : id
      }
    ))
  }

  /// 焦点没被系统还原回来时把焦点补写回这张卡。真正的写回由 `PresentationReadyAction` 轮询完成：
  /// 播放器收起有转场，同一次更新里写回会被丢掉。3 秒内没落回就放弃。
  private func beginFocusRestore(_ id: String) {
    // 卡已经被刷掉就别等了，焦点交给系统默认。
    guard items.contains(where: { $0.id == id }) else { return }
    focusRestoreGeneration += 1
    let generation = focusRestoreGeneration
    pendingFocusRestore = id
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(3))
      guard focusRestoreGeneration == generation else { return }
      pendingFocusRestore = nil
    }
  }

  private func canOpenMediaLibrary(_ item: MediaServerPlayItem) -> Bool {
    HomeViewModel.supportsMediaLibraryDeepLink(serverType: item.server_type)
  }

  /// 在应用内打开条目（见 `HomeViewModel.cardDestination`）：打开详情页，没有 TMDB 编号的直接播放。
  /// 期间页面变了（已经进了别的页）就不再推入、不再起播。
  private func openDetail(_ item: MediaServerPlayItem) {
    let navigationSource = navigationCoordinator.sourceToken()
    // 详情冷加载拿它当全屏背景兜底，不能降成卡片尺寸。
    let loadingPosterURL = item.imageURLs().image
    Task {
      switch await viewModel.cardDestination(for: item, using: mediaActionHandler) {
      case .detail(let target):
        navigationCoordinator.push(target, loadingPosterURL: loadingPosterURL, ifCurrent: navigationSource)
      case .play(let target):
        guard navigationCoordinator.isCurrent(navigationSource) else { return }
        let coordinator = APIService.shared.sessionScope.playbackCoordinator
        // 已有别的播放在准备或播放：这次会被拒绝，先别登记目标，免得焦点目标错改成这张卡。
        guard !coordinator.isBusy else { return }
        // 播放器盖上之后退出时，焦点要回到这张卡。
        playbackFocusHandoff.target = .homeMedia(ownerID: focusOwnerID, itemID: item.id)
        coordinator.play(target)
        // 这次没被接受（没权限、后端太旧、设置关闭）：别把目标留给下一次播放。
        if !coordinator.isBusy { playbackFocusHandoff.target = nil }
      case nil:
        break
      }
    }
  }

  private func openMediaItem(_ item: MediaServerPlayItem) {
    viewModel.openMediaItem(item, using: openURL) { message in
      notificationManager.show(message: message, type: .error)
    }
  }
}

private struct SubscribeSectionView: View {
  private var memoryOptimization = MemoryOptimizationSettings()
  let title: String
  let items: [Subscribe]
  var isFirstRow: Bool = false
  let loadsPageImages: Bool
  @ObservedObject var viewModel: HomeViewModel
  let onEdit: (Subscribe) -> Void
  let onViewDetail: (Subscribe) -> Void

  @FocusState private var focusedItemId: String?
  @FocusState private var isTopRedirectorFocused: Bool
  @State private var hasRedirectedFocus: Bool = false
  @State private var imageAnchorId: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.callout)
        .bold()
        .foregroundStyle(.secondary)
        .focusLiftHeaderPart()
        .padding(.leading, 8)

      if isFirstRow {
        // 顶部焦点重定向器：确保在首次加载时来自上方的焦点进入第一个项目，然后禁用自身。
        Color.clear
          .frame(height: 1)
          .focusable(!hasRedirectedFocus)
          .focused($isTopRedirectorFocused)
          .onChange(of: isTopRedirectorFocused) { _, isFocused in
            if isFocused {
              focusedItemId = HomeSubscribeFocusID.value(for: items.first?.id)
              hasRedirectedFocus = true
              isTopRedirectorFocused = false
            }
          }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 40) {
          ForEach(Array(items.enumerated()), id: \.element.id) { entry in
            let index = entry.offset
            let item = entry.element
            SubscribeItemView(
              item: item,
              loadsImage: loadsPageImages
                && ImageLoadWindow.containsHorizontalItem(
                  at: index,
                  itemCount: items.count,
                  anchorIndex: imageAnchorId.flatMap { id in
                    items.firstIndex(where: { HomeSubscribeFocusID.value(for: $0.id) == id })
                  },
                  cardKind: .media,
                  usesFocusWindow: memoryOptimization.isEnabled
                ),
              viewModel: viewModel,
              trials: viewModel.episodeTrials,
              onEdit: { onEdit(item) },
              onViewDetail: { onViewDetail(item) }
            )
            .focused($focusedItemId, equals: HomeSubscribeFocusID.value(for: item.id))
          }
        }
        .padding(.top, 25)
        .padding(.bottom, 30)
        .onChange(of: focusedItemId) { _, newId in
          // Push 或上下文菜单可能暂时清空焦点；保留当前图片窗口锚点。
          guard let newId else { return }
          imageAnchorId = newId
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
    .focusLiftRow(cardImageSize: MediaCard.defaultPosterSize)
  }
}

private struct SubscribeItemView: View {
  let item: Subscribe
  let loadsImage: Bool
  @ObservedObject var viewModel: HomeViewModel
  /// 只跟随本机试看订阅的认领、取消和了结，试看进度刷新时不重算整排订阅卡。
  let trials: EpisodeTrialService
  let onEdit: () -> Void
  let onViewDetail: () -> Void
  @EnvironmentObject private var notificationManager: NotificationManager
  @State private var showUnsubscribeConfirm = false
  @State private var showsEpisodeTrialNotice = false
  @State private var trialHolds: Set<EpisodeTrialHold>

  init(
    item: Subscribe, loadsImage: Bool, viewModel: HomeViewModel, trials: EpisodeTrialService,
    onEdit: @escaping () -> Void, onViewDetail: @escaping () -> Void
  ) {
    self.item = item
    self.loadsImage = loadsImage
    self.viewModel = viewModel
    self.trials = trials
    self.onEdit = onEdit
    self.onViewDetail = onViewDetail
    _trialHolds = State(initialValue: EpisodeTrialHold.holds(in: trials.credentials))
  }

  var body: some View {
    let trialState = EpisodeTrialHold.state(of: item, in: trialHolds)
    let isEpisodeTrial = trialState != nil
    let isCancellingTrial = trialState == .cancelling
    MediaCard(
      title: item.name,
      posterUrl: item.imageURLs.poster,
      typeText: isEpisodeTrial ? "试看" : formatState(item.state),
      ratingText: nil,
      bottomLeftText: isCancellingTrial
        ? "取消试看中"
        : isEpisodeTrial
          ? item.episodeTrialTargetText : formatProgress(total: item.total_episode, lack: item.lack_episode),
      bottomLeftSecondaryText: item.last_update?.toRelativeDateString() ?? nil,
      source: nil,
      loadsImage: loadsImage,
      action: {
        if isEpisodeTrial {
          showsEpisodeTrialNotice = true
        } else {
          onEdit()
        }
      }
    )
    .compositingGroup()
    .contextMenu {
      if isEpisodeTrial {
        Button {
          onViewDetail()
        } label: {
          Label("详情", systemImage: AppSymbol.details)
        }
        if viewModel.canCancelEpisodeTrial, !isCancellingTrial {
          Button(role: .destructive) {
            showsEpisodeTrialNotice = true
          } label: {
            Label(EpisodeTrialHoldNotice.cancelTitle, systemImage: AppSymbol.unsubscribe)
          }
        }
      } else {
        actionMenu
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      showUnsubscribeConfirm = false
      showsEpisodeTrialNotice = false
    }
    .onReceive(trials.$credentials.map(EpisodeTrialHold.holds(in:)).removeDuplicates()) { holds in
      trialHolds = holds
    }
    .alert(SubscriptionCancelConfirmation.title, isPresented: $showUnsubscribeConfirm) {
      Button("取消", role: .cancel) {}
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        deleteSubscribe()
      }
    } message: {
      Text(SubscriptionCancelConfirmation.message(for: item))
    }
    .episodeTrialNotice(
      isPresented: $showsEpisodeTrialNotice, context: .manage, isCancelling: isCancellingTrial,
      canCancel: viewModel.canCancelEpisodeTrial
    ) {
      cancelEpisodeTrial()
    }
  }

  private func cancelEpisodeTrial() {
    Task {
      switch await viewModel.cancelEpisodeTrial(subscribe: item) {
      case .done: break
      case .pending: notificationManager.show(message: EpisodeTrialHoldNotice.cancelPending, type: .info)
      case .failed: notificationManager.show(message: EpisodeTrialHoldNotice.cancelFailure, type: .error)
      }
    }
  }

  @ViewBuilder
  private var actionMenu: some View {
    // 1. 编辑订阅
    Button {
      onEdit()
    } label: {
      Label("编辑订阅", systemImage: AppSymbol.editSubscription)
    }

    // 2. 详情
    Button {
      onViewDetail()
    } label: {
      Label("详情", systemImage: AppSymbol.details)
    }

    // 3. 搜索订阅
    Button {
      searchSubscribe()
    } label: {
      Label("搜索订阅", systemImage: AppSymbol.search)
    }

    // 4. 启用/暂停
    Button {
      toggleSubscribeStatus()
    } label: {
      if item.state == "S" {
        Label("启用订阅", systemImage: AppSymbol.resume)
      } else {
        Label("暂停订阅", systemImage: AppSymbol.pause)
      }
    }

    // 5. 重置订阅
    Button {
      resetSubscribe()
    } label: {
      Label("重置订阅", systemImage: AppSymbol.resetSubscription)
    }

    Divider()

    // 6. 取消订阅
    Button(role: .destructive) {
      showUnsubscribeConfirm = true
    } label: {
      Label("取消订阅", systemImage: AppSymbol.unsubscribe)
    }
  }

  private func searchSubscribe() {
    Task {
      do {
        guard try await viewModel.searchSubscribe(subscribe: item) else {
          showRequestFailure()
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func toggleSubscribeStatus() {
    Task {
      do {
        let result = try await viewModel.toggleSubscribeStatus(subscribe: item)
        guard result.success else {
          showActionFailure(
            "\(item.state == "S" ? "启用" : "暂停")订阅失败",
            detail: result.message
          )
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func resetSubscribe() {
    Task {
      do {
        let result = try await viewModel.resetSubscribe(subscribe: item)
        guard result.success else {
          showActionFailure("重置订阅失败", detail: result.message)
          return
        }
      } catch {
        showRequestFailure()
      }
    }
  }

  private func deleteSubscribe() {
    Task {
      do {
        guard try await viewModel.deleteSubscribe(subscribe: item) else {
          showUnsubscribeFailure()
          return
        }
      } catch is CancellationError {
        return
      } catch {
        showUnsubscribeFailure()
      }
    }
  }

  private func showUnsubscribeFailure() {
    notificationManager.show(
      message: SubscriptionCancelConfirmation.failureMessage,
      type: .error
    )
  }

  private func showActionFailure(_ action: String, detail: String?) {
    let message = "《\(item.name)》\(action)"
    notificationManager.show(
      message: MediaIdentifier.normalizedString(detail).map { "\(message)：\($0)" } ?? "\(message)。",
      type: .error
    )
  }

  private func showRequestFailure() {
    notificationManager.show(message: "订阅请求失败，请稍后重试。", type: .error)
  }

  // 辅助格式化函数
  func formatProgress(total: Int?, lack: Int?) -> String? {
    guard let total = total, total > 0 else { return nil }
    if let lack = lack, lack > 0 {
      return "\(total - lack) / \(total)"
    }
    return "已完结"
  }

  func formatState(_ state: String?) -> String? {
    switch state {
    case "N": return "新"
    case "R": return "阅"
    case "P": return "待"
    case "S": return "停"
    default: return state
    }
  }
}
