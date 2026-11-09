import Kingfisher
import SwiftUI

enum SeasonDisplayFormatter {
  /// 季卡与详情 Sheet 共用季名规则，避免 S00、缺失和非法季号出现不同文案。
  static func name(seasonNumber: Int?, rawName: String?) -> String {
    guard let seasonNumber else { return "未知季" }

    switch seasonNumber {
    case 0:
      return nonEmpty(rawName) ?? "特别篇"
    case let seasonNumber where seasonNumber > 0:
      return "第 \(seasonNumber) 季"
    default:
      return "未知季"
    }
  }

  /// 将可选文本统一裁剪空白；纯空白值按缺失处理。
  static func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func cardTitle(seasonNumber: Int?, rawName: String?, airDate: String?) -> String {
    var title = name(seasonNumber: seasonNumber, rawName: rawName)
    if let airDate = nonEmpty(airDate) {
      title += " · \(airDate.prefix(4))"
    }
    return title
  }
}

struct SubscribeSeasonView: View {
  @StateObject private var viewModel: SubscribeSeasonViewModel
  @ObservedObject var imageLifecycle: PageImageLifecycle
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @State private var gridListIdentity: GridListIdentity
  @StateObject private var gridDOMRetention: GridDOMRetentionController
  @StateObject private var gridImageRetention: GridImageLifecycleController

  init(
    mediaInfo: MediaInfo,
    initialSeason: Int? = nil,
    initialEpisodeGroup: String? = nil,
    imageLifecycle: PageImageLifecycle
  ) {
    self.imageLifecycle = imageLifecycle
    let listIdentity = GridListIdentity.make()
    _gridListIdentity = State(initialValue: listIdentity)
    _viewModel = StateObject(
      wrappedValue: SubscribeSeasonViewModel(
        mediaInfo: mediaInfo,
        initialSeason: initialSeason,
        initialEpisodeGroup: initialEpisodeGroup
      ))
    _gridDOMRetention = StateObject(
      wrappedValue: GridDOMRetentionController(
        listIdentity: listIdentity,
        itemIDs: [],
        columnCount: MediaCard.defaultGridColumns.count
      )
    )
    _gridImageRetention = StateObject(
      wrappedValue: GridImageLifecycleController(
        listIdentity: listIdentity,
        itemIDs: [],
        columnCount: MediaCard.defaultGridColumns.count,
        imageLifecycle: imageLifecycle
      )
    )
  }

  var body: some View {
    let itemIDs = Self.gridItemIDs(for: viewModel.seasonInfos)
    let retainedItemCount = gridDOMRetention.retainedItemCount(
      for: viewModel.seasonInfos.count,
      listIdentity: gridListIdentity
    )

    ScrollView {
      SubscribeSeasonContentView(
        viewModel: viewModel,
        layout: .grid,
        loadsImages: true,
        gridLifecycle: SeasonGridLifecycleContext(
          listIdentity: gridListIdentity,
          itemIDs: itemIDs,
          retainedItemCount: retainedItemCount,
          imageController: gridImageRetention,
          onFocus: handleGridFocus
        )
      )
    }
    .focusSection()
    .onScrollGeometryChange(
      for: CGFloat.self,
      of: { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      },
      action: { _, adjustedOffsetY in
        gridDOMRetention.scrollPositionChanged(adjustedOffsetY: adjustedOffsetY)
      }
    )
    .onScrollPhaseChange { _, newPhase in
      gridDOMRetention.scrollPhaseChanged(newPhase)
    }
    .onAppear {
      gridDOMRetention.reconcile(listIdentity: gridListIdentity, itemIDs: itemIDs)
      gridImageRetention.reconcile(listIdentity: gridListIdentity, itemIDs: itemIDs)
      gridDOMRetention.setViewActive(true)
      gridDOMRetention.setStackInteractive(navigationCoordinator.isStackInteractive)
    }
    .onChange(of: itemIDs) { oldItemIDs, newItemIDs in
      let isAppend = newItemIDs.count >= oldItemIDs.count
        && newItemIDs.prefix(oldItemIDs.count).elementsEqual(oldItemIDs)
      let newIdentity = isAppend ? gridListIdentity : gridListIdentity.advanced()
      if newIdentity != gridListIdentity {
        gridListIdentity = newIdentity
      }
      gridDOMRetention.reconcile(listIdentity: newIdentity, itemIDs: newItemIDs)
      gridImageRetention.reconcile(listIdentity: newIdentity, itemIDs: newItemIDs)
    }
    .onChange(of: navigationCoordinator.isStackInteractive) { _, isInteractive in
      gridDOMRetention.setStackInteractive(isInteractive)
    }
    .onDisappear {
      gridDOMRetention.setViewActive(false)
    }
    .task {
      await viewModel.loadSeasonManagementData()
    }
  }

  private static func gridItemIDs(for seasons: [TmdbSeason]) -> [MediaInfo.ID] {
    seasons.enumerated().map { index, season in
      "season:\(season.season_number.map(String.init) ?? "missing"):\(index)"
    }
  }

  private func handleGridFocus(
    listIdentity: GridListIdentity,
    itemIDs: [MediaInfo.ID],
    itemID: MediaInfo.ID,
    itemIndex: Int,
    isFocused: Bool
  ) {
    gridImageRetention.reconcileEventSnapshot(listIdentity: listIdentity, itemIDs: itemIDs)
    gridDOMRetention.reconcileEventSnapshot(listIdentity: listIdentity, itemIDs: itemIDs)
    guard gridImageRetention.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: itemID,
      itemIndex: itemIndex,
      isFocused: isFocused
    ) else { return }
    _ = gridDOMRetention.cardFocusChanged(
      listIdentity: listIdentity,
      itemID: itemID,
      itemIndex: itemIndex,
      isFocused: isFocused
    )
  }
}

/// Shared content view used both in standalone SubscribeSeasonView and embedded in MediaDetailView
enum SeasonLayout {
  case shelf
  case grid
}

struct SeasonGridLifecycleContext {
  let listIdentity: GridListIdentity
  let itemIDs: [MediaInfo.ID]
  let retainedItemCount: Int
  let imageController: GridImageLifecycleController
  let onFocus:
    (GridListIdentity, [MediaInfo.ID], MediaInfo.ID, Int, Bool) -> Void
}

struct SubscribeSeasonContentView: View {
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @ObservedObject var viewModel: SubscribeSeasonViewModel
  var layout: SeasonLayout = .shelf
  var title: String? = nil
  var showBadges: Bool = true
  var loadsImages: Bool = true
  var onSeasonTap: ((TmdbSeason) -> Void)? = nil
  var onMoreTapped: (() -> Void)? = nil
  var gridLifecycle: SeasonGridLifecycleContext? = nil

  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedSeasonDetail: TmdbSeason?
  @FocusState private var focusedSeasonId: Int?
  @FocusState private var isTopRedirectorFocused: Bool
  @FocusState private var isBottomRedirectorFocused: Bool

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
        showUnsubscribeConfirm: { viewModel.showUnsubscribeConfirm = $0 },
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

  var body: some View {
    VStack(spacing: 0) {
      // Header Section (Title + Picker)
      VStack(spacing: 0) {
        if layout == .grid {
          Text("订阅   \(viewModel.mediaInfo.title ?? "")")
            .font(.title2.bold())
            .foregroundColor(.secondary)
        }
        headerSection
      }
      .padding(.bottom, layout == .grid ? 20 : 0)

      if viewModel.isLoading {
        ProgressView("加载中...")
          .frame(maxWidth: .infinity, minHeight: 200)
      } else if viewModel.hasSeasonLoadError {
        VStack(spacing: 16) {
          Image(systemName: AppSymbol.warning)
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("分季信息加载失败")
            .foregroundColor(.secondary)
          Button {
            Task {
              await viewModel.retryLoadData()
            }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: AppSymbol.retry)
              Text("重试")
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .focusSection()
      } else if viewModel.seasonInfos.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: AppSymbol.noResults)
            .font(.system(size: 48))
            .foregroundColor(.gray)
          Text("未查询到季集信息")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
      } else {
        switch layout {
        case .shelf:
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 40) {
              let displayCount = min(10, viewModel.seasonInfos.count)
              ForEach(viewModel.seasonInfos.prefix(displayCount), id: \.self) { season in
                seasonCard(season)
                  .focused($focusedSeasonId, equals: season.season_number)
              }
              if viewModel.seasonInfos.count > 10 {
                let nextSeason = viewModel.seasonInfos[displayCount]
                viewAllCard(nextSeason: nextSeason)
                  .focused($focusedSeasonId, equals: -1)
              }
            }
            .padding(.horizontal, 81)
            .padding(.top, 25)
            .padding(.bottom, 30)
          }
          .scrollClipDisabled()
          .focusSection()
        case .grid:
          let gridLifecycle = gridLifecycle
          let retainedItemCount = min(
            viewModel.seasonInfos.count,
            gridLifecycle?.retainedItemCount ?? viewModel.seasonInfos.count
          )
          VStack(spacing: 0) {
            // Top Focus Redirector: Catches focus when navigating down from header
            Color.clear
              .frame(height: 1)
              .focusable(focusedSeasonId == nil)
              .focused($isTopRedirectorFocused)
              .onChange(of: isTopRedirectorFocused) { _, isFocused in
                if isFocused {
                  focusedSeasonId = viewModel.seasonInfos.first?.season_number
                  isTopRedirectorFocused = false
                }
              }

            LazyVGrid(columns: MediaCard.defaultGridColumns, spacing: 40) {
              ForEach(
                Array(viewModel.seasonInfos.prefix(retainedItemCount).enumerated()),
                id: \.offset
              ) { entry in
                let index = entry.offset
                let season = entry.element
                let itemID = gridLifecycle?.itemIDs[index]
                  ?? "season:\(season.season_number.map(String.init) ?? "missing"):\(index)"
                seasonCard(
                  season,
                  onFocus: { isFocused in
                    guard let gridLifecycle else { return }
                    gridLifecycle.onFocus(
                      gridLifecycle.listIdentity,
                      gridLifecycle.itemIDs,
                      itemID,
                      index,
                      isFocused
                    )
                  }
                )
                  .focused($focusedSeasonId, equals: season.season_number)
                  .environment(
                    \.gridImageDemandContext,
                    gridLifecycle.map {
                      GridImageDemandContext(
                        controller: $0.imageController,
                        listIdentity: $0.listIdentity,
                        itemIDs: $0.itemIDs,
                        itemID: itemID,
                        itemIndex: index
                      )
                    }
                  )
              }
            }
            .id(gridLifecycle?.listIdentity.id)
            .padding()

            // Focus Redirector: Catches focus when navigating down from an incomplete row
            Color.clear
              .frame(height: 1)
              .focusable()
              .focused($isBottomRedirectorFocused)
              .onChange(of: isBottomRedirectorFocused) { _, isFocused in
                if isFocused {
                  focusedSeasonId = viewModel.seasonInfos.last?.season_number
                  isBottomRedirectorFocused = false
                }
              }
          }
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      selectedSeasonDetail = nil
      viewModel.sheetSubscribe = nil
      viewModel.showUnsubscribeConfirm = nil
    }
    .sheet(item: $selectedSeasonDetail) { season in
      SeasonDetailSheet(season: season, mediaInfo: viewModel.mediaInfo)
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
    .onChange(of: viewModel.errorMessage) { _, newValue in
      if let message = newValue {
        notificationManager.show(message: message, type: .error)
        viewModel.errorMessage = nil
      }
    }
  }

  @ViewBuilder
  private var episodeGroupPicker: some View {
    if !viewModel.episodeGroups.isEmpty {
      ShelfMenuPicker(
        title: "剧集组",
        selection: $viewModel.selectedGroupId,
        options: EpisodeGroup.menuOptions(viewModel.episodeGroups),
        label: { "剧集组：\($0)" }
      )
      .onChange(of: viewModel.selectedGroupId) { _, _ in
        Task { await viewModel.fetchSeasons() }
      }
    }
  }

  @ViewBuilder
  private var headerSection: some View {
    if let title = title {
      let content = HStack {
        Text(title)
          .font(.callout)
          .bold()
          .foregroundStyle(.secondary)

        Spacer()

        HStack(spacing: 20) {
          episodeGroupPicker

          if layout == .shelf, viewModel.seasonInfos.count > 10 {
            Button("展开") {
              onMoreTapped?()
            }
          }
        }
      }
      .padding(.horizontal, 89)
      .padding(.vertical, 0)

      if !viewModel.episodeGroups.isEmpty || (layout == .shelf && viewModel.seasonInfos.count > 10) {
        content.focusSection()
      } else {
        content
      }
    } else if layout == .grid && !viewModel.episodeGroups.isEmpty {
      HStack {
        Spacer()
        episodeGroupPicker
      }
      .padding(.vertical, 0)
      .focusSection()
    }
  }

  @ViewBuilder
  private func seasonCard(
    _ season: TmdbSeason,
    onFocus: ((Bool) -> Void)? = nil
  ) -> some View {
    let seasonNumber = season.season_number ?? 0
    let isSubscribed = viewModel.isSeasonSubscribed(seasonNumber)
    let isProcessing = viewModel.isSeasonSubscribing(seasonNumber)

    let title = SeasonDisplayFormatter.cardTitle(
      seasonNumber: season.season_number,
      rawName: season.name,
      airDate: season.air_date
    )
    let statusText = viewModel.getStatusText(season: seasonNumber)
    let episodeCount = season.episode_count ?? 0
    let bottomLeft = statusText.map { "\(episodeCount) 集 · \($0)" }
    let footerText =
      isProcessing
        ? "取消订阅中"
        : (isSubscribed ? (viewModel.subscriptionStatusText(for: seasonNumber) ?? "已订阅") : "订阅")

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
      bottomLeftSecondaryText: nil,
      source: nil,
      showBadges: showBadges,
      loadsImage: loadsImages,
      footerLabel: (
        icon: isSubscribed ? AppSymbol.unsubscribe : AppSymbol.subscribe,
        text: footerText
      ),
      action: {
        guard !isProcessing else { return }
        performSeasonAction(season, isSubscribed: isSubscribed)
      },
      onFocus: onFocus
    )
    .compositingGroup()
    .contextMenu {
      if isSubscribed {
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

      Button {
        selectedSeasonDetail = season
      } label: {
        Label("详情", systemImage: AppSymbol.details)
      }
    }
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

/// 季详情：统一阅读 Sheet 的两栏形式（与豆瓣短评详情一致）。
///
/// 左栏是这一季的固定信息：剧名、首播日期、集数、评分；右栏是季简介，长简介可以往下翻。
/// 不放海报：只会从季卡片的长按菜单进来，卡片上已经有这一季的海报。
struct SeasonDetailSheet: View {
  let season: TmdbSeason
  let mediaInfo: MediaInfo

  var body: some View {
    ReadingSheet(
      title: SeasonDisplayFormatter.name(seasonNumber: season.season_number, rawName: season.name),
      blocks: Self.blocks(for: season)
    ) {
      sidebar
    }
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
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}
