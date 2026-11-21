import Kingfisher
import SwiftUI

struct SubscribeSeasonView: View {
  @StateObject private var viewModel: SubscribeSeasonViewModel
  @ObservedObject var imageLifecycle: PageImageLifecycle

  init(
    mediaInfo: MediaInfo,
    initialSeason: Int? = nil,
    initialEpisodeGroup: String? = nil,
    imageLifecycle: PageImageLifecycle
  ) {
    self.imageLifecycle = imageLifecycle
    _viewModel = StateObject(
      wrappedValue: SubscribeSeasonViewModel(
        mediaInfo: mediaInfo,
        initialSeason: initialSeason,
        initialEpisodeGroup: initialEpisodeGroup
      ))
  }

  var body: some View {
    SubscribeSeasonContentView(viewModel: viewModel, layout: .grid(imageLifecycle))
      .task { await viewModel.loadSeasonManagementData() }
  }
}

enum SeasonLayout {
  case shelf
  case grid(PageImageLifecycle)
}

struct SubscribeSeasonContentView: View {
  private static let seasonPageSize = 100

  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @ObservedObject private var apiService = APIService.shared
  @ObservedObject var viewModel: SubscribeSeasonViewModel
  var layout: SeasonLayout = .shelf
  var title: String? = nil
  var showBadges: Bool = true
  var loadsImages: Bool = true
  var allowsEpisodeGroupRequests = true
  var onSeasonTap: ((TmdbSeason) -> Void)? = nil
  var onMoreTapped: (() -> Void)? = nil

  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  /// 打开着季面板的那一季：按下季卡片打开，订阅、取消订阅都在面板里。
  @State private var selectedSeasonDetail: TmdbSeason?
  /// 季面板关掉后要做的事：订阅表单、取消确认不能叠在面板上弹出，先关面板再弹。
  @State private var afterSeasonSheetDismiss: (() -> Void)?
  @State private var seasonPageOffset = 0
  @FocusState private var focusedSeasonId: Int?

  private func performSeasonAction(_ season: TmdbSeason, isSubscribed: Bool) {
    let source = navigationCoordinator.sourceToken()
    Task { @MainActor in
      await Self.performSeasonPrimaryAction(
        season: season, isSubscribed: isSubscribed,
        refreshSubscribedState: { seasonNumber in
          let refreshed = await viewModel.checkSubscriptionStatus(forceRefresh: true)
          guard refreshed, navigationCoordinator.isCurrent(source) else { return nil }
          return viewModel.isSeasonSubscribed(seasonNumber)
        },
        showUnsubscribeConfirm: { viewModel.requestUnsubscribe(season: $0) },
        prepareSubscription: { viewModel.prepareSubscription(seasonNumber: $0) })
    }
  }

  static func performSeasonPrimaryAction(
    season: TmdbSeason,
    isSubscribed: Bool,
    onSeasonTap _: ((TmdbSeason) -> Void)?,
    showUnsubscribeConfirm: (Int) -> Void,
    prepareSubscription: (Int) -> Void
  ) {
    let seasonNumber = season.season_number ?? 0
    if isSubscribed {
      showUnsubscribeConfirm(seasonNumber)
    } else {
      prepareSubscription(seasonNumber)
    }
  }

  static func performSeasonPrimaryAction(
    season: TmdbSeason,
    isSubscribed: Bool,
    refreshSubscribedState: (Int) async -> Bool?,
    showUnsubscribeConfirm: (Int) -> Void,
    prepareSubscription: (Int) -> Void
  ) async {
    let seasonNumber = season.season_number ?? 0
    guard let latestSubscribedState = await refreshSubscribedState(seasonNumber) else {
      return
    }
    performSeasonPrimaryAction(
      seasonNumber: seasonNumber,
      isSubscribed: isSubscribed,
      latestSubscribedState: latestSubscribedState,
      showUnsubscribeConfirm: showUnsubscribeConfirm,
      prepareSubscription: prepareSubscription
    )
  }

  static func performSeasonPrimaryAction(
    seasonNumber: Int,
    isSubscribed: Bool,
    latestSubscribedState: Bool,
    showUnsubscribeConfirm: (Int) -> Void,
    prepareSubscription: (Int) -> Void
  ) {
    guard latestSubscribedState == isSubscribed else {
      return
    }
    if latestSubscribedState {
      showUnsubscribeConfirm(seasonNumber)
    } else {
      prepareSubscription(seasonNumber)
    }
  }

  /// 提示框对应的那一季已经在取消试看：只说明，不再提供取消。
  private var noticeIsCancelling: Bool {
    viewModel.episodeTrialNoticeSeason.map(viewModel.isSeasonCancellingTrial) == true
  }

  var body: some View {
    let session = apiService.sessionSnapshot()
    Group {
      switch layout {
      case .shelf:
        VStack(spacing: 0) {
          shelfHeader
          if viewModel.seasonInfos.isEmpty || viewModel.isLoading || viewModel.hasSeasonLoadError {
            status
          } else {
            shelf
          }
        }
        .focusLiftRow(cardImageSize: MediaCard.defaultPosterSize)
      case .grid(let imageLifecycle):
        expandedGrid(imageLifecycle: imageLifecycle)
      }
    }
    .task(id: allowsEpisodeGroupRequests ? viewModel.episodeGroupCatalog.loadKey(session: session) : nil) {
      guard allowsEpisodeGroupRequests, apiService.isSessionUnchanged(from: session) else { return }
      try? await viewModel.loadEpisodeGroups()
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      afterSeasonSheetDismiss = nil
      selectedSeasonDetail = nil
      viewModel.sheetSubscribe = nil
      viewModel.showUnsubscribeConfirm = nil
      viewModel.episodeTrialNoticeSeason = nil
    }
    .sheet(item: $selectedSeasonDetail, onDismiss: runAfterSeasonSheetDismiss) { season in
      SeasonDetailSheet(season: season, mediaInfo: viewModel.mediaInfo, panel: seasonPanel(for: season)) { action in
        performPanelAction(action, on: season)
      }
    }
    .sheet(item: $viewModel.sheetSubscribe) { subscribe in
      SubscribeSheet(subscribe: subscribe, isNewSubscription: true) {
        Task {
          await viewModel.checkSeasonsStatus()
          await viewModel.checkSubscriptionStatus(forceRefresh: true)
        }
      }
    }
    .alert(
      SubscriptionCancelConfirmation.title,
      isPresented: Binding(
        get: { viewModel.showUnsubscribeConfirm != nil },
        set: { if !$0 { viewModel.showUnsubscribeConfirm = nil } }
      )
    ) {
      Button("取消", role: .cancel) {}
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        if let season = viewModel.showUnsubscribeConfirm {
          Task { await viewModel.unsubscribeSeason(season) }
        }
      }
    } message: {
      if let season = viewModel.showUnsubscribeConfirm {
        Text(viewModel.unsubscribeConfirmationMessage(for: season))
      }
    }
    .episodeTrialNotice(
      isPresented: Binding(
        get: { viewModel.episodeTrialNoticeSeason != nil },
        set: { if !$0 { viewModel.episodeTrialNoticeSeason = nil } }
      ),
      context: .manage, isCancelling: noticeIsCancelling, canCancel: viewModel.canCancelEpisodeTrial
    ) {
      guard let season = viewModel.episodeTrialNoticeSeason else { return }
      Task { await viewModel.cancelEpisodeTrial(season: season) }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task {
        // 前台恢复同时重查"每季入库状态"：后台期间媒体库可能已变化，陈旧
        // availability 不只让角标过时，还会作为 best_version 默认进入新建订阅。
        await viewModel.checkSeasonsStatus()
        await viewModel.checkSubscriptionStatus(forceRefresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .subscriptionDidUpdate)) { _ in
      Task {
        await viewModel.checkSubscriptionStatus(forceRefresh: true)
      }
    }
    .task { await viewModel.followEpisodeTrials() }
    .onChange(of: viewModel.errorMessage) { _, newValue in
      if let message = newValue {
        notificationManager.show(message: message, type: .error)
        viewModel.errorMessage = nil
      }
    }
  }

  private func expandedGrid(imageLifecycle: PageImageLifecycle) -> some View {
    let allSeasons = viewModel.isLoading || viewModel.hasSeasonLoadError ? [] : viewModel.seasonInfos
    let page = DetailPageRanges.current(
      count: allSeasons.count, size: Self.seasonPageSize, offset: seasonPageOffset
    )
    let seasons = allSeasons[page]
    return DetailExpansionGrid(
      columns: MediaCard.defaultGridColumns,
      itemIDs: seasons.indices.map { index in
        let number = seasons[index].season_number.map(String.init) ?? "missing"
        return "season:\(viewModel.selectedGroupId):\(number):\(index)"
      },
      imageLifecycle: imageLifecycle,
      cardFocus: $focusedSeasonId,
      firstFocus: seasons.first?.season_number,
      lastFocus: seasons.last?.season_number
    ) {
      DetailExpansionHeader(title: "订阅   \(viewModel.mediaInfo.title ?? "")") {
        if allSeasons.count > Self.seasonPageSize || episodeGroupMenu.isVisible {
          HStack(spacing: 20) {
            Spacer(minLength: 0)
            if allSeasons.count > Self.seasonPageSize {
              seasonPagePicker(allSeasons, page: page)
            }
            episodeGroupPicker
          }
          .focusSection()
        }
      }
    } status: {
      // 独立的季订阅页是整页：加载转圈改由外层 pageLoadingOverlay 居中；详情页里的分季区块仍原位转圈。
      if !viewModel.showsLoadingState {
        status
      }
    } card: { index, onFocus in
      let season = seasons[page.lowerBound + index]
      seasonCard(season, onFocus: onFocus)
        .focused($focusedSeasonId, equals: season.season_number)
    }
    .pageLoadingOverlay(viewModel.showsLoadingState)
  }

  private func seasonPagePicker(_ seasons: [TmdbSeason], page: Range<Int>) -> some View {
    ShelfMenuPicker(
      title: "季数范围",
      selection: Binding(get: { page.lowerBound }, set: { seasonPageOffset = $0 }),
      options: DetailPageRanges.ranges(count: seasons.count, size: Self.seasonPageSize).map { range in
        PickerOption(title: Self.seasonPageTitle(range, numbers: seasons[range].map(\.season_number)), value: range.lowerBound)
      }
    )
    .fixedSize(horizontal: true, vertical: false)
  }

  /// 季数范围的名字。特别篇排在最后（见 `SeasonDisplayOrder`），不计入季号范围，单独写在后面。
  /// 正片季号对不上（不递增、缺季号）时按位置写「第 x–y 项」。
  static func seasonPageTitle(_ range: Range<Int>, numbers: [Int?]) -> String {
    let regular = numbers.filter { $0 != 0 }
    guard regular.count < numbers.count, !regular.isEmpty else {
      return DetailPageRanges.title(for: range, numbers: numbers, unit: "季")
    }
    let regularRange = range.lowerBound..<(range.lowerBound + regular.count)
    let title = DetailPageRanges.title(for: regularRange, numbers: regular, unit: "季")
    return title.hasPrefix("第 ") ? DetailPageRanges.title(for: range, numbers: [], unit: "季") : "\(title) · 特别篇"
  }

  private var episodeGroupMenu: EpisodeGroupMenu {
    EpisodeGroupMenu(catalog: viewModel.episodeGroupCatalog, selection: $viewModel.selectedGroupId)
  }

  private var episodeGroupPicker: some View {
    episodeGroupMenu
      .control(defaultSeasons: viewModel.defaultSeasonInfos)
      .onChange(of: viewModel.selectedGroupId) { _, _ in
        seasonPageOffset = 0
        Task { await viewModel.fetchSeasons() }
      }
  }

  @ViewBuilder
  private var shelfHeader: some View {
    if let title {
      let content = HStack {
        Text(title)
          .font(.callout)
          .bold()
          .foregroundStyle(.secondary)
          .focusLiftHeaderPart()

        Spacer()

        HStack(spacing: 20) {
          episodeGroupPicker
          if viewModel.seasonInfos.count > 10 {
            Button("展开") { onMoreTapped?() }
          }
        }
        .focusLiftHeaderPart()
      }
      .padding(.horizontal, 89)

      if episodeGroupMenu.isVisible || viewModel.seasonInfos.count > 10 {
        content.focusSection()
      } else {
        content
      }
    }
  }

  @ViewBuilder
  private var status: some View {
    if viewModel.showsLoadingState {
      FirstLoadIndicator()
    } else if viewModel.hasSeasonLoadError {
      VStack(spacing: 16) {
        Image(systemName: AppSymbol.warning)
          .font(.system(size: 48))
          .foregroundColor(.secondary)
        Text("分季信息加载失败")
          .foregroundColor(.secondary)
        Button {
          Task { await viewModel.retryLoadData() }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: AppSymbol.retry)
            Text("重试")
          }
        }
      }
      .frame(maxWidth: .infinity, minHeight: 200)
      .focusSection()
    } else {
      VStack(spacing: 16) {
        Image(systemName: AppSymbol.noResults)
          .font(.system(size: 48))
          .foregroundColor(.gray)
        Text("未查询到季集信息")
          .foregroundColor(.secondary)
        // 详情页按「分季订阅」把焦点交到这一行，空态也要有能聚焦的控件；后端识别结果可能变，空结果也不缓存。
        Button {
          Task { await viewModel.retryLoadData() }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: AppSymbol.retry)
            Text("重新查询")
          }
        }
      }
      .frame(maxWidth: .infinity, minHeight: 200)
      .focusSection()
    }
  }

  private var shelf: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: 40) {
        let displayCount = min(10, viewModel.seasonInfos.count)
        ForEach(viewModel.seasonInfos.prefix(displayCount), id: \.self) { season in
          seasonCard(season)
            .focused($focusedSeasonId, equals: season.season_number)
        }
        if viewModel.seasonInfos.count > 10 {
          viewAllCard(nextSeason: viewModel.seasonInfos[displayCount])
            .focused($focusedSeasonId, equals: -1)
        }
      }
      .padding(.horizontal, 81)
      .padding(.top, 25)
      .padding(.bottom, 30)
    }
    .scrollClipDisabled()
    .focusSection()
  }

  @ViewBuilder
  private func seasonCard(
    _ season: TmdbSeason,
    onFocus: ((Bool) -> Void)? = nil
  ) -> some View {
    let seasonNumber = season.season_number ?? 0
    let isSubscribed = viewModel.isSeasonSubscribed(seasonNumber)
    let isHeldByTrial = viewModel.isSeasonHeldByEpisodeTrial(seasonNumber)
    let isCancellingTrial = viewModel.isSeasonCancellingTrial(seasonNumber)
    let isProcessing = viewModel.isSeasonSubscribing(seasonNumber)

    let title = SeasonDisplayFormatter.cardTitle(
      seasonNumber: season.season_number,
      rawName: season.name,
      airDate: season.air_date
    )
    let statusText = viewModel.getStatusText(season: seasonNumber)
    let episodeCount = season.episode_count ?? 0
    let bottomLeft = statusText.map { "\(episodeCount) 集 · \($0)" }

    // 卡片只显示状态，不写「订阅」这类操作提示：按下打开季面板，在面板里订阅或取消。
    MediaCard(
      title: title,
      posterUrl: APIService.shared.getSeasonPosterURL(
        posterPath: season.poster_path,
        mediaPosterPath: viewModel.mediaInfo.poster_path
      ),
      typeText: nil,
      ratingText: (season.vote_average ?? 0) > 0
        ? String(format: "%.1f", season.vote_average!) : nil,
      bottomLeftText: bottomLeft,
      bottomLeftSecondaryText: subscriptionBadge(
        seasonNumber, isSubscribed: isSubscribed, isHeldByTrial: isHeldByTrial,
        isBusy: isProcessing || isCancellingTrial),
      source: nil,
      showBadges: showBadges,
      loadsImage: loadsImages,
      action: { selectedSeasonDetail = season },
      onFocus: onFocus
    )
    .compositingGroup()
    .contextMenu {
      if isHeldByTrial {
        if viewModel.canCancelEpisodeTrial, !isCancellingTrial {
          Button(role: .destructive) {
            guard !isProcessing else { return }
            viewModel.episodeTrialNoticeSeason = seasonNumber
          } label: {
            Label(EpisodeTrialHoldNotice.cancelTitle, systemImage: AppSymbol.unsubscribe)
          }
        }
      } else if isSubscribed {
        Button(role: .destructive) {
          guard !isProcessing else { return }
          performSeasonAction(season, isSubscribed: true)
        } label: {
          Label("取消订阅", systemImage: AppSymbol.unsubscribe)
        }
      } else {
        Button {
          performSeasonAction(season, isSubscribed: false)
        } label: {
          Label("订阅", systemImage: AppSymbol.subscribe)
        }
      }
    }
  }

  /// 海报下沿的订阅状态（与入库状态并排）。没订阅时不显示。
  private func subscriptionBadge(
    _ seasonNumber: Int, isSubscribed: Bool, isHeldByTrial: Bool, isBusy: Bool
  ) -> String? {
    if isBusy { return isHeldByTrial ? "取消试看中" : "处理中" }
    if isHeldByTrial { return "试看中" }
    return isSubscribed ? "已订阅" : nil
  }

  /// 季面板显示的订阅状态和操作，与长按菜单同一套判断。
  private func seasonPanel(for season: TmdbSeason) -> SeasonDetailSheet.Panel {
    let seasonNumber = season.season_number ?? 0
    let isSubscribed = viewModel.isSeasonSubscribed(seasonNumber)
    let isHeldByTrial = viewModel.isSeasonHeldByEpisodeTrial(seasonNumber)
    let isCancellingTrial = viewModel.isSeasonCancellingTrial(seasonNumber)
    let isProcessing = viewModel.isSeasonSubscribing(seasonNumber)
    var panel = SeasonDetailSheet.Panel(libraryStatus: viewModel.getStatusText(season: seasonNumber))
    if isHeldByTrial {
      panel.subscriptionStatus = isCancellingTrial ? "正在取消试看" : "试看中"
      if viewModel.canCancelEpisodeTrial, !isCancellingTrial { panel.action = .cancelTrial }
    } else if isSubscribed {
      panel.subscriptionStatus = viewModel.subscriptionStatusText(for: seasonNumber) ?? "已订阅"
      panel.action = .unsubscribe
    } else {
      panel.action = .subscribe
    }
    panel.isProcessing = isProcessing
    return panel
  }

  /// 面板里的操作：先关面板，关掉后再弹订阅表单或取消确认。按下时的意图原样交出，状态变了由下游拒绝。
  private func performPanelAction(_ action: SeasonDetailSheet.Action, on season: TmdbSeason) {
    let seasonNumber = season.season_number ?? 0
    switch action {
    case .subscribe:
      afterSeasonSheetDismiss = { performSeasonAction(season, isSubscribed: false) }
    case .unsubscribe:
      afterSeasonSheetDismiss = { performSeasonAction(season, isSubscribed: true) }
    case .cancelTrial:
      afterSeasonSheetDismiss = { viewModel.episodeTrialNoticeSeason = seasonNumber }
    }
    selectedSeasonDetail = nil
  }

  private func runAfterSeasonSheetDismiss() {
    let action = afterSeasonSheetDismiss
    afterSeasonSheetDismiss = nil
    action?()
  }

  @ViewBuilder
  private func viewAllCard(nextSeason: TmdbSeason) -> some View {
    MoreCard(
      titleText: "查看全部",
      posterUrl: APIService.shared.getSeasonPosterURL(
        posterPath: nextSeason.poster_path,
        mediaPosterPath: viewModel.mediaInfo.poster_path
      ),
      loadsImage: loadsImages,
      action: {
        onMoreTapped?()
      }
    )
  }
}

/// 季面板：统一阅读 Sheet 的两栏形式（与单集面板一致）。按下季卡片打开。
///
/// 左栏是这一季的固定信息（剧名、首播日期、集数、评分）、入库和订阅状态，最下面是订阅或取消的按钮；
/// 右栏是季简介，长简介可以往下翻。不放海报：卡片上已经有这一季的海报。
struct SeasonDetailSheet: View {
  enum Action: Equatable {
    case subscribe
    case unsubscribe
    case cancelTrial
  }

  struct Panel: Equatable {
    var libraryStatus: String?
    var subscriptionStatus: String?
    /// nil 表示只能看（比如试看中但当前账号不能取消）。
    var action: Action?
    var isProcessing = false
  }

  let season: TmdbSeason
  let mediaInfo: MediaInfo
  var panel = Panel()
  var onAction: (Action) -> Void = { _ in }

  @FocusState private var focusesAction: Bool

  var body: some View {
    ReadingSheet(
      title: SeasonDisplayFormatter.name(seasonNumber: season.season_number, rawName: season.name),
      blocks: Self.blocks(for: season),
      focusesBodyByDefault: panel.action == nil,
      size: .compact
    ) {
      sidebar
    }
    // 挂在整个面板上：只挂在左栏时，打开面板的默认焦点仍会落到右上的正文。
    .defaultFocus($focusesAction, panel.action != nil)
  }

  /// 正文是季简介；没有简介时写明，不留空白页。
  static func blocks(for season: TmdbSeason) -> [ReadingBlock] {
    guard let overview = SeasonDisplayFormatter.nonEmpty(season.overview) else {
      return [ReadingBlock("暂无简介", style: .secondary)]
    }
    return ReadingSheetLayout.paragraphs(AttributedString(overview)).map { ReadingBlock($0) }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      info
      Spacer(minLength: 24)
      if let action = panel.action {
        actionButton(action)
      }
    }
  }

  private func actionButton(_ action: Action) -> some View {
    let title: String
    let systemImage: String
    let loadingTitle: String
    switch action {
    case .subscribe:
      title = "订阅"
      systemImage = AppSymbol.subscribe
      loadingTitle = "订阅中"
    case .unsubscribe:
      title = "取消订阅"
      systemImage = AppSymbol.unsubscribe
      loadingTitle = "取消订阅中"
    case .cancelTrial:
      title = EpisodeTrialHoldNotice.cancelTitle
      systemImage = AppSymbol.unsubscribe
      loadingTitle = "取消试看中"
    }
    return SheetActionButton(
      title: title, systemImage: systemImage, loadingTitle: loadingTitle, isLoading: panel.isProcessing,
      focus: $focusesAction
    ) {
      onAction(action)
    }
  }

  private var info: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title = SeasonDisplayFormatter.nonEmpty(mediaInfo.title) {
        Text(title)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, 28)
      }

      // 与其他面板的信息标签同一组件、同一套图标；阅读 Sheet 左栏竖排，字号与豆瓣短评详情一致。
      VStack(alignment: .leading, spacing: 14) {
        if let date = SeasonDisplayFormatter.nonEmpty(season.air_date) {
          SheetInfoTag(systemImage: AppSymbol.time, text: date)
        }
        if let count = season.episode_count {
          SheetInfoTag(systemImage: AppSymbol.episodes, text: "共 \(count) 集")
        }
        if let vote = season.vote_average, vote > 0 {
          SheetInfoTag(systemImage: AppSymbol.rating, text: String(format: "%.1f", vote))
        }
        if let status = SeasonDisplayFormatter.nonEmpty(panel.libraryStatus) {
          SheetInfoTag(systemImage: AppSymbol.libraryStatus, text: status)
        }
        if let status = SeasonDisplayFormatter.nonEmpty(panel.subscriptionStatus) {
          SheetInfoTag(systemImage: AppSymbol.subscribed, text: status)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}
