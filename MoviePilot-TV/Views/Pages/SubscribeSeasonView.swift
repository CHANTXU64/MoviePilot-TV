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
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator
  @ObservedObject var viewModel: SubscribeSeasonViewModel
  var layout: SeasonLayout = .shelf
  var title: String? = nil
  var showBadges: Bool = true
  var loadsImages: Bool = true
  var onSeasonTap: ((TmdbSeason) -> Void)? = nil
  var onMoreTapped: (() -> Void)? = nil

  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedSeasonDetail: TmdbSeason?
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
      case .grid(let imageLifecycle):
        let seasons = viewModel.isLoading || viewModel.hasSeasonLoadError ? [] : viewModel.seasonInfos
        DetailExpansionGrid(
          columns: MediaCard.defaultGridColumns,
          itemIDs: seasons.enumerated().map { index, season in
            "season:\(season.season_number.map(String.init) ?? "missing"):\(index)"
          },
          imageLifecycle: imageLifecycle,
          cardFocus: $focusedSeasonId,
          firstFocus: seasons.first?.season_number,
          lastFocus: seasons.last?.season_number
        ) {
          DetailExpansionHeader(title: "订阅   \(viewModel.mediaInfo.title ?? "")") {
            if !viewModel.episodeGroups.isEmpty {
              HStack {
                Spacer()
                episodeGroupPicker
              }
              .focusSection()
            }
          }
        } status: {
          status
        } card: { index, onFocus in
          let season = seasons[index]
          seasonCard(season, onFocus: onFocus)
            .focused($focusedSeasonId, equals: season.season_number)
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
        options: EpisodeGroupPickerOptions.make(viewModel.episodeGroups, defaultSeasons: viewModel.mediaInfo.season_info),
        label: { "剧集组：\($0)" }
      )
      .onChange(of: viewModel.selectedGroupId) { _, _ in
        Task { await viewModel.fetchSeasons() }
      }
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

        Spacer()

        HStack(spacing: 20) {
          episodeGroupPicker
          if viewModel.seasonInfos.count > 10 {
            Button("展开") { onMoreTapped?() }
          }
        }
      }
      .padding(.horizontal, 89)

      if !viewModel.episodeGroups.isEmpty || viewModel.seasonInfos.count > 10 {
        content.focusSection()
      } else {
        content
      }
    }
  }

  @ViewBuilder
  private var status: some View {
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
      }
      .frame(maxWidth: .infinity, minHeight: 200)
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
