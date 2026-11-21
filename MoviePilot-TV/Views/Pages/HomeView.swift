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
          if viewModel.showsLoadingPlaceholder {
            // 整页首次加载的转圈由 ScrollView 外层的 firstLoadOverlay 居中显示。
            EmptyView()
          } else {
            // 部分数据失败：保留旧快照并提示（成功空不算失败）
            if viewModel.latestLoadFailed || viewModel.continueWatchingLoadFailed
              || viewModel.subscriptionsLoadFailed
            {
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

            // 第1节：继续观看。这一行没有条目时不接标签栏下来的焦点，交给下面的行（条件见各行的 isFirstRow）。
            if !viewModel.continueWatchingServers.isEmpty {
              MediaSectionView(
                content: .continueWatching,
                title: "继续观看",
                items: viewModel.continueWatching,
                servers: viewModel.continueWatchingServers,
                selectedServer: $viewModel.selectedContinueWatchingServer,
                isFirstRow: !viewModel.continueWatching.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel
              )
            }

            // 第2节：最近添加
            if !viewModel.latestMediaServers.isEmpty {
              MediaSectionView(
                content: .latest,
                title: "最近添加",
                items: viewModel.latestMedia,
                servers: viewModel.latestMediaServers,
                selectedServer: $viewModel.selectedLatestMediaServer,
                isFirstRow: viewModel.continueWatching.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel
              )
            }

            // 第3节：电影订阅
            if !viewModel.movieSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电影订阅",
                items: viewModel.movieSubscriptions,
                isFirstRow: viewModel.continueWatching.isEmpty
                  && viewModel.latestMediaServers.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            // 第4节：电视剧订阅
            if !viewModel.tvSubscriptions.isEmpty {
              SubscribeSectionView(
                title: "电视剧订阅",
                items: viewModel.tvSubscriptions,
                isFirstRow: viewModel.continueWatching.isEmpty
                  && viewModel.latestMediaServers.isEmpty
                  && viewModel.movieSubscriptions.isEmpty,
                loadsPageImages: true,
                viewModel: viewModel,
                onEdit: presentEditSheet,
                onViewDetail: navigateToDetail
              )
            }

            if viewModel.continueWatchingServers.isEmpty && viewModel.latestMediaServers.isEmpty
              && viewModel.movieSubscriptions.isEmpty && viewModel.tvSubscriptions.isEmpty
            {
              if viewModel.latestLoadFailed || viewModel.continueWatchingLoadFailed
                || viewModel.subscriptionsLoadFailed
              {
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
      .firstLoadOverlay(viewModel.showsLoadingPlaceholder)
      .task(id: isSelected) {
        // 成为当前 Tab 时加载：首屏完整加载，再次进入重刷一次（「继续观看」不跟轮询，见 `loadData`）。
        // 切走时任务取消，轮询不再在后台空转。
        guard isSelected else { return }
        await viewModel.loadData()

        // 定期刷新数据（类似 Status 页面的下载器/整理信息）。「继续观看」不跟着轮询：
        // 后端会为每条续播条目向媒体服务器探测封面，持续轮询会把这份开销压到媒体服务器上。
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
          guard !Task.isCancelled else { break }
          await viewModel.refreshData(includeContinueWatching: false)
        }
      }
      // 停止上报和进度写回发完后才重读「继续观看」：播放器刚关时进度还没写回媒体服务器，
      // 那时读会拿到旧进度，而这一行不跟轮询，旧值会一直留着。焦点恢复仍走 `playbackEndedGeneration`。
      // 从后台回到前台时协调器也发这个信号（期间可能在媒体服务器自己的 App 里看过）。
      .onReceive(apiService.sessionScope.playbackCoordinator.watchStateUpdates) { _ in
        guard isSelected else { return }
        Task { await viewModel.refreshContinueWatching() }
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

/// 媒体库页横向行里，聚焦的卡被刷掉时焦点交给谁。
enum HomeRowFocus {
  /// `removed` 不在新列表里时，按旧列表找它后面第一张还在的卡，后面没有就找前面最近的一张。
  /// `removed` 为 nil 或还在新列表里时返回 nil（不用换）。
  static func neighbor(of removed: String?, from oldIDs: [String], in newIDs: [String]) -> String? {
    guard let removed, !newIDs.contains(removed), let index = oldIDs.firstIndex(of: removed) else {
      return nil
    }
    let remaining = Set(newIDs)
    return oldIDs[(index + 1)...].first(where: remaining.contains)
      ?? oldIDs[..<index].last(where: remaining.contains)
  }
}

enum HomeSubscribeFocusID {
  static func value(for id: Int?) -> String? {
    id.map(String.init)
  }
}

// MARK: - 子视图

/// 媒体库页的一行媒体服务器条目。两行共用行头、服务器选择器、图片加载窗口和起播焦点交接，
/// 只有卡片样子和按下去做什么不同。
private struct MediaSectionView: View {
  /// 卡片海报向服务端请求的缩略宽度，与卡片降采样后实际保留的像素一致。
  private static let cardPosterPixelWidth = MediaCard.posterThumbnailMaxWidth(
    for: MediaCard.defaultPosterSize)

  /// 这一行是「最近添加」还是「继续观看」。
  enum Content {
    /// 海报卡；按下打开详情页，或按设置跳到媒体服务器 App。
    case latest
    /// 剧照卡（播放图标、进度、季集）；按下接着看。
    case continueWatching
  }

  private var memoryOptimization = MemoryOptimizationSettings()
  let content: Content
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

  private var cardImageSize: CGSize {
    content == .continueWatching ? ContinueWatchingCard.stillSize : MediaCard.defaultPosterSize
  }

  private var cardKind: ImageLoadWindow.HorizontalCardKind {
    content == .continueWatching ? .episode : .media
  }

  private var emptyText: String {
    content == .continueWatching ? "该服务器暂无继续观看内容" : "该服务器暂无最近内容"
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
        Text(emptyText)
          .font(.headline)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
          .padding(.top, 25)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 40) {
            ForEach(Array(items.enumerated()), id: \.element.id) { entry in
              let item = entry.element
              if content == .continueWatching {
                continueWatchingCard(item, at: entry.offset)
                  .focused($focusedItemId, equals: item.id)
              } else {
                latestCard(item, at: entry.offset)
                  .focused($focusedItemId, equals: item.id)
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
    .focusLiftRow(cardImageSize: cardImageSize)
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
    // 聚焦（或正等着还原焦点）的卡被刷掉了，比如刚看完从「继续观看」里消失：交给它原位置的相邻卡，
    // 不让系统随便挑一个（HIG：聚焦项消失时把焦点移到一步之内的剩余项）。
    // 两个都要换：播放器收起的转场会吞掉立即写入，等着还原的目标也换成相邻卡，转场后由 `PresentationReadyAction` 补写。
    .onChange(of: items.map(\.id)) { oldIDs, newIDs in
      if let pending = pendingFocusRestore, !newIDs.contains(pending) {
        pendingFocusRestore = HomeRowFocus.neighbor(of: pending, from: oldIDs, in: newIDs)
      }
      if let neighbor = HomeRowFocus.neighbor(of: focusedItemId, from: oldIDs, in: newIDs) {
        focusedItemId = neighbor
      }
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

  /// 这一行的图片加载窗口：以当前聚焦的卡为中心。剧照卡较宽，一屏只放 4 张。
  private func loadsImage(at index: Int) -> Bool {
    loadsPageImages
      && ImageLoadWindow.containsHorizontalItem(
        at: index,
        itemCount: items.count,
        anchorIndex: imageAnchorId.flatMap { id in
          items.firstIndex(where: { $0.id == id })
        },
        cardKind: cardKind,
        usesFocusWindow: memoryOptimization.isEnabled
      )
  }

  /// 「最近添加」的海报卡。
  @ViewBuilder
  private func latestCard(_ item: MediaServerPlayItem, at index: Int) -> some View {
    let opensApp = viewModel.opensMediaServerApp(item, server: selectedServer)
    let playsDirectly = !opensApp && viewModel.playsDirectly(item, server: selectedServer)
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
      loadsImage: loadsImage(at: index),
      action: { opensApp ? openMediaItem(item) : openDetail(item, server: selectedServer) },
      // 媒体服务器上没有封面或读不到时，改用 TMDB 海报。
      onPosterUnavailable: { [selectedServer] in viewModel.loadPosterFallback(for: item, server: selectedServer) }
    )
    .accessibilityHint(opensApp ? "在媒体服务器 App 中打开" : playsDirectly ? "播放" : "打开详情")
    .compositingGroup()
    .contextMenu {
      // 按下打开的那一种不再重复列出；有详情页的不在这里直接播放，播放从详情页开始。
      if opensApp {
        // 没有详情页的条目，在应用内打开就是直接播放。
        if viewModel.playsDirectly(item, server: selectedServer) {
          Button {
            openDetail(item, server: selectedServer)
          } label: {
            Label("在应用内播放", systemImage: AppSymbol.play)
          }
        } else {
          Button {
            openDetail(item, server: selectedServer)
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
      MediaServerSearchMenuItems(
        info: MediaInfo(title: item.title, type: item.type, year: item.subtitle))
    }
  }

  /// 「继续观看」的剧照卡：按下接着看，长按给详情、跳转媒体库和搜索。
  @ViewBuilder
  private func continueWatchingCard(_ item: MediaServerPlayItem, at index: Int) -> some View {
    // 卡片所在的服务器（建卡片时取，不用动作到达时选中的）：条目 ID 只在它自己的服务器上有意义。
    let server = selectedServer
    let action = viewModel.continueWatchingAction(for: item, server: server)
    ContinueWatchingCard(
      title: item.title,
      stillURL: item.imageURLs().image,
      icon: action.badgeIcon,
      episodeText: ContinueWatchingDisplay.episodeText(type: item.type, subtitle: item.subtitle),
      progress: ContinueWatchingDisplay.progress(percent: item.percent),
      loadsImage: loadsImage(at: index),
      action: {
        switch action {
        case .play(let target):
          play(target, from: item)
        case .openInServerApp:
          openMediaItem(item)
        case .detail:
          openDetail(item, server: server)
        }
      }
    )
    .accessibilityHint(action.accessibilityHint)
    .compositingGroup()
    .contextMenu {
      // 按下做的那一种不再重复列出。
      if action != .detail {
        Button {
          openDetail(item, server: server)
        } label: {
          Label("详情", systemImage: AppSymbol.details)
        }
      }
      if case .play = action, canOpenMediaLibrary(item) {
        Button {
          openMediaItem(item)
        } label: {
          Label("跳转媒体库", systemImage: AppSymbol.openInLibrary)
        }
      }
      // 剧集的副标题是季集和集名，不是年份；按下时再按服务器上的外部编号认出是哪部片。
      MediaServerSearchMenuItems(
        info: ContinueWatchingDisplay.mediaInfo(
          title: item.title, type: item.type, subtitle: item.subtitle),
        resolveIdentity: { await viewModel.continueWatchingMediaInfo(for: item, server: server) })
    }
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
  /// 「继续观看」只打开详情页——接着播由卡片按下直接做，不经过这里。
  /// `server` 是卡片所在的服务器（建卡片时取）：条目 ID 只在它自己的服务器上有意义。
  /// 期间页面变了（已经进了别的页）就不再推入、不再起播。
  private func openDetail(_ item: MediaServerPlayItem, server: String) {
    let navigationSource = navigationCoordinator.sourceToken()
    // 详情冷加载拿它当全屏背景兜底，不能降成卡片尺寸。
    let loadingPosterURL = item.imageURLs().image
    Task {
      let destination: HomeViewModel.CardDestination?
      if content == .continueWatching {
        destination = await viewModel.continueWatchingDetailTarget(
          for: item, server: server, using: mediaActionHandler).map { .detail($0) }
      } else {
        destination = await viewModel.cardDestination(for: item, server: server, using: mediaActionHandler)
      }
      switch destination {
      case .detail(let target):
        navigationCoordinator.push(target, loadingPosterURL: loadingPosterURL, ifCurrent: navigationSource)
      case .play(let target):
        guard navigationCoordinator.isCurrent(navigationSource) else { return }
        play(target, from: item)
      case nil:
        break
      }
    }
  }

  /// 不经过详情页直接起播：播放器盖上之后退出时，焦点要回到这张卡。
  private func play(_ target: PlaybackTarget, from item: MediaServerPlayItem) {
    let coordinator = APIService.shared.sessionScope.playbackCoordinator
    playbackFocusHandoff.play(
      returningTo: .homeMedia(ownerID: focusOwnerID, itemID: item.id), on: coordinator
    ) {
      coordinator.play(target)
    }
  }

  private func openMediaItem(_ item: MediaServerPlayItem) {
    viewModel.openMediaItem(item, using: openURL) { message in
      notificationManager.show(message: message, type: .error)
    }
  }
}

/// 媒体服务器条目（「最近添加」「继续观看」）长按菜单里的「搜索资源」「搜索字幕」。
/// 与 TMDB 媒体卡的菜单不同：这些条目常常没有 TMDB 编号，识别不出时退回按标题搜索，动作照样完成。
/// 没有搜索权限时两项都不出现；期间页面变了就不再推入。
private struct MediaServerSearchMenuItems: View {
  /// 识别和搜索用的媒体信息。年份只在确实是年份时给（剧集副标题是季集和集名，不是年份）。
  let info: MediaInfo
  /// 按下时先按服务器上的外部编号认出是哪部片（「继续观看」用）：同名不同年的剧不会搜错。
  /// 返回 nil 表示没认出来或期间换了账号：换账号由下面的会话守卫终止整个操作，认不出才用 `info` 按标题识别。
  /// 「最近添加」不传，维持原样。
  var resolveIdentity: (@MainActor () async -> MediaInfo?)? = nil
  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator

  private var canSearchResources: Bool {
    APIService.shared.canAccess(.search)
  }

  var body: some View {
    if canSearchResources {
      Button {
        let navigationSource = navigationCoordinator.sourceToken()
        Task {
          guard APIService.shared.canAccess(.search) else { return }
          let sessionSnapshot = APIService.shared.sessionSnapshot()
          var info = self.info
          if let resolved = await resolveIdentity?() { info = resolved }
          // 期间换了账号就终止整个操作：不能拿旧账号的媒体标题向新会话发识别请求。
          guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else { return }
          // 识别不出来会退回按标题搜索，动作照样完成，所以这里不弹「未识别到此媒体的TMDB信息」：
          // 否则弹窗与跳转同时发生。
          if let target = await mediaActionHandler.getTMDBJumpTarget(
            for: info, notifyWhenUnrecognized: false, useSharedMapping: false)
          {
            if let request = await mediaActionHandler.searchResourcesTargetUsingDefaultSites(
              for: target)
            {
              navigationCoordinator.push(request, ifCurrent: navigationSource)
            }
          } else {
            guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else { return }
            let sites = await SystemViewModel.normalizedDefaultSearchSitesString()
            guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else { return }
            let request = ResourceSearchRequest(
              keyword: info.title ?? "", type: info.type, area: nil, title: nil, year: nil,
              season: nil, mediaInfo: nil, sites: sites)
            navigationCoordinator.push(request, ifCurrent: navigationSource)
          }
        }
      } label: {
        Label("搜索资源", systemImage: AppSymbol.search)
      }
      if SubtitleSearchRequest.supportsSubtitleSearch(type: info.type) {
        Button {
          let navigationSource = navigationCoordinator.sourceToken()
          Task {
            let sessionSnapshot = APIService.shared.sessionSnapshot()
            var info = self.info
            if let resolved = await resolveIdentity?() { info = resolved }
            guard APIService.shared.isSessionUnchanged(from: sessionSnapshot) else { return }
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
