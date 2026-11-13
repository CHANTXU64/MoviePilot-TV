import Kingfisher
import SwiftUI

/// 详情页「剧集」行：行头选季（和剧集组），下面是这一季的单集卡片。
/// 应用内播放可用时，能播的集按下即播，其余的打开单集面板（试看在面板里）；长按有播放、试看、取消试看和详情。
struct MediaDetailEpisodesView: View {
  let media: MediaInfo
  let tmdbID: Int
  let subscriptionSeasons: SubscribeSeasonViewModel?
  /// 按集播放和试看；没有应用内播放时为 nil，按下单集只看简介。
  let playback: EpisodePlaybackSource?
  let allowsRequests: Bool
  let isContentVisible: Bool
  /// 第一页底部只露出卡片：本行是第二页首行时，行头在翻到第二页后才出现，与其他行一致。
  let showsHeader: Bool
  let onExpand: (MediaEpisodeGridRequest) -> Void

  var body: some View {
    if let subscriptionSeasons {
      SharedEpisodeGroupView(seasons: subscriptionSeasons) { groupID in
        shelf(groupID: groupID, groupMenu: nil, catalog: subscriptionSeasons.episodeGroupCatalog)
      }
    } else {
      LocalEpisodeGroupView(tmdbID: tmdbID, isActive: allowsRequests && isContentVisible) {
        groupID, groupMenu, catalog in
        shelf(groupID: groupID, groupMenu: groupMenu, catalog: catalog)
      }
    }
  }

  private func shelf(
    groupID: String?, groupMenu: EpisodeGroupMenu?, catalog: EpisodeGroupCatalog
  ) -> some View {
    EpisodeBrowser(
      media: media, tmdbID: tmdbID, groupID: groupID, groupMenu: groupMenu,
      catalog: catalog, allowsRequests: allowsRequests, playback: playback,
      trial: APIService.shared.sessionScope.episodeTrial,
      layout: .shelf(showsHeader: showsHeader, onExpand: onExpand)
    )
  }
}

struct MediaEpisodeGridView: View {
  let request: MediaEpisodeGridRequest
  let imageLifecycle: PageImageLifecycle
  let allowsRequests: Bool

  var body: some View {
    LocalEpisodeGroupView(
      tmdbID: request.tmdbID, isActive: allowsRequests,
      initialGroupID: request.initialEpisodeGroup
    ) { groupID, groupMenu, catalog in
      EpisodeBrowser(
        media: request.mediaInfo, tmdbID: request.tmdbID, groupID: groupID, groupMenu: groupMenu,
        catalog: catalog, allowsRequests: allowsRequests, playback: request.playback,
        trial: APIService.shared.sessionScope.episodeTrial,
        layout: .grid(imageLifecycle),
        initialSeason: groupID == request.initialEpisodeGroup ? request.initialSeason : nil,
        initialEpisodeOffset: groupID == request.initialEpisodeGroup ? request.initialEpisodeOffset : nil
      )
    }
  }
}

/// 详情页沿用分季订阅的剧集组选择。两行共享季表，单集请求可独立进行。
private struct SharedEpisodeGroupView<Content: View>: View {
  @ObservedObject var seasons: SubscribeSeasonViewModel
  let content: (String?) -> Content

  var body: some View {
    content(trimmedNonEmpty([seasons.selectedGroupId]))
  }
}

/// 没有分季订阅时，剧集组由本行自己查询和选择。
private struct LocalEpisodeGroupView<Content: View>: View {
  @ObservedObject private var apiService = APIService.shared
  let tmdbID: Int
  let isActive: Bool
  let content: (String?, EpisodeGroupMenu, EpisodeGroupCatalog) -> Content

  @State private var catalog = EpisodeGroupCatalog()
  @State private var selectedGroupID: String

  init(
    tmdbID: Int, isActive: Bool, initialGroupID: String? = nil,
    content: @escaping (String?, EpisodeGroupMenu, EpisodeGroupCatalog) -> Content
  ) {
    self.tmdbID = tmdbID
    self.isActive = isActive
    self.content = content
    _selectedGroupID = State(initialValue: initialGroupID ?? "")
  }

  var body: some View {
    let session = apiService.sessionSnapshot()
    content(
      trimmedNonEmpty([selectedGroupID]),
      EpisodeGroupMenu(catalog: catalog, selection: $selectedGroupID),
      catalog
    )
    .task(id: isActive ? catalog.loadKey(session: session) : nil) {
      guard isActive, apiService.isSessionUnchanged(from: session) else { return }
      try? await catalog.load(tmdbID: tmdbID, apiService: apiService)
    }
  }
}

private enum EpisodeLoadState<Value> {
  case loading
  case failed
  case loaded(Value)
}

private enum EpisodeRowFocus: Hashable {
  case status
  case episode(MoviePilotEpisode.ID)
}

private struct SeasonOption: Identifiable {
  let id: Int
  let title: String
}

private enum EpisodeBrowserLayout {
  case shelf(showsHeader: Bool, onExpand: (MediaEpisodeGridRequest) -> Void)
  case grid(PageImageLifecycle)

  var episodePageSize: Int {
    switch self {
    case .shelf: 50
    case .grid: 100
    }
  }
}

private struct EpisodeBrowser: View {
  @ObservedObject private var apiService = APIService.shared
  @EnvironmentObject private var notificationManager: NotificationManager
  let media: MediaInfo
  let tmdbID: Int
  let groupID: String?
  let groupMenu: EpisodeGroupMenu?
  let catalog: EpisodeGroupCatalog
  let allowsRequests: Bool
  /// 按集播放和试看；nil 时按下单集只看简介。
  let playback: EpisodePlaybackSource?
  /// 卡片和单集面板跟着试看进度变化。
  @ObservedObject var trial: EpisodeTrialService
  let layout: EpisodeBrowserLayout
  var initialSeason: Int? = nil
  var initialEpisodeOffset: Int? = nil

  @State private var storedGroup = GroupState(id: nil)
  @FocusState private var focus: EpisodeRowFocus?
  @FocusState private var focusedSeason: Int?
  /// 打开着单集面板的那一集。面板由本行弹出，内容随本行的播放状态和试看进度实时变化。
  @State private var panelEpisode: MoviePilotEpisode?
  /// 面板关掉后要做的事：全屏播放器不能叠在面板上起播，先关面板再播。
  @State private var afterPanelDismiss: (() -> Void)?
  /// 按下「试看」到服务给出结果之间的集（试看键），期间再按不重复发起。
  @State private var startingTrials: Set<String> = []
  /// 按下「取消试看」到服务给出结果之间的试看订阅。
  @State private var cancellingTrials: Set<Int> = []

  private struct GroupState {
    let id: String?
    var loadedSeasons: [TmdbSeason]?
    var seasonLoad: EpisodeLoadState<Void>?
    var seasonRetry = 0
    var selectedSeason: Int?
    var episodeStates: [Int: EpisodeLoadState<[MoviePilotEpisode]>] = [:]
    var episodeRetries: [Int: Int] = [:]
    var episodePageOffsets: [Int: Int] = [:]
    var availability: [Int: SeasonAvailability] = [:]
    var availabilityRetries: [Int: Int] = [:]
  }

  /// 一季每集能不能播。`source` 变了（入库条目、应用内播放开关）就作废重查。
  private struct SeasonAvailability {
    let source: EpisodePlaybackSource
    /// nil 表示第一次查、还没有结果。
    var results: [MoviePilotEpisode.ID: EpisodeAvailability]?
    /// 应用内播放不可用（不是管理员、版本不支持、设置里关了、没有能播放的服务器）：不显示播放和试看。
    var isOffered = true
    /// 重查期间沿用上次的结果，按钮显示加载中，焦点不跳。
    var isRefreshing = false
    /// 上次查询用的重试次数：重试次数变大时强制重读服务器。
    var retry = 0
  }

  // 切换剧集组时只更换数据，不重建剧集组按钮，保留遥控器焦点。
  private var group: GroupState {
    get { storedGroup.id == groupID ? storedGroup : GroupState(id: groupID) }
    nonmutating set { storedGroup = newValue }
  }

  private struct SeasonRequest: Equatable {
    let groupID: String?
    let retry: Int
    let session: APIServiceSessionSnapshot
  }

  private struct EpisodeRequest: Equatable {
    let groupID: String?
    let season: Int?
    let retry: Int
    let session: APIServiceSessionSnapshot
  }

  private struct AvailabilityRequest: Equatable {
    let groupID: String?
    let season: Int
    let episodeCount: Int
    let episodeRetry: Int
    let retry: Int
    let source: EpisodePlaybackSource
    let session: APIServiceSessionSnapshot
  }

  // MARK: 季

  private var detailSeasons: [TmdbSeason] {
    guard groupID == nil else { return [] }
    return MediaDetailEpisodeSeasons.selectable(media.season_info ?? [])
  }

  private var needsSeasonLookup: Bool {
    groupID != nil || MediaDetailEpisodeSeasons.needsLookup(detailSeasons, media: media)
  }

  private var seasons: [TmdbSeason] {
    if let groupID {
      return MediaDetailEpisodeSeasons.selectable(catalog.seasonsByGroup[groupID] ?? [])
    }
    return group.loadedSeasons ?? detailSeasons
  }

  private var defaultMenuSeasons: [TmdbSeason]? {
    let defaults = groupID == nil ? seasons : MediaDetailEpisodeSeasons.selectable(media.season_info ?? [])
    return MediaDetailEpisodeSeasons.needsLookup(defaults, media: media) ? nil : defaults
  }

  private var showsSupplementalSeasonRetry: Bool {
    guard !detailSeasons.isEmpty else { return false }
    switch group.seasonLoad {
    case .failed: return true
    case .loaded: return MediaDetailEpisodeSeasons.needsLookup(seasons, media: media)
    case .loading, nil: return false
    }
  }

  private var seasonOptions: [SeasonOption] {
    seasons.compactMap { season in
      season.season_number.map { SeasonOption(id: $0, title: seasonName(season, number: $0)) }
    }
  }

  private var seasonNumber: Int? {
    MediaDetailEpisodeSeasons.current(
      selected: group.selectedSeason ?? initialSeason,
      preferred: groupID == nil ? media.season : nil,
      available: seasons.compactMap(\.season_number)
    )
  }

  private func seasonName(_ season: TmdbSeason, number: Int) -> String {
    if groupID != nil, let name = trimmedNonEmpty([season.name]) {
      return SeasonDisplayFormatter.localizedLabel(name)
    }
    return SeasonDisplayFormatter.name(seasonNumber: number, rawName: season.name)
  }

  // MARK: 行内容

  private enum RowContent {
    case episodes([MoviePilotEpisode])
    case status(EpisodeShelfStatusCard.Status, retry: (() -> Void)?)
  }

  private var rowContent: RowContent {
    guard let seasonNumber else {
      switch group.seasonLoad {
      case .failed:
        return .status(.failed("分季信息加载失败"), retry: retrySeasonList)
      case .loaded:
        return .status(.empty("暂无分季信息"), retry: retrySeasonList)
      case .loading, nil:
        return .status(.loading("正在加载分季信息"), retry: nil)
      }
    }
    let retry = { group.episodeRetries[seasonNumber, default: 0] += 1 }
    switch group.episodeStates[seasonNumber] {
    case .loaded(let episodes) where !episodes.isEmpty:
      return .episodes(episodes)
    case .loaded:
      // MoviePilot 读 TMDB 失败时也返回空列表，给一个重试入口。
      return .status(.empty("暂未取得剧集信息"), retry: retry)
    case .failed:
      return .status(.failed("剧集加载失败"), retry: retry)
    case .loading, nil:
      return .status(.loading("正在加载剧集"), retry: nil)
    }
  }

  private var firstEpisodeID: MoviePilotEpisode.ID? {
    guard case .episodes(let episodes) = rowContent else { return nil }
    return visibleEpisodes(episodes).first?.id
  }

  private func episodePage(count: Int, season: Int) -> Range<Int> {
    let initialOffset = season == initialSeason ? initialEpisodeOffset : nil
    return DetailPageRanges.current(
      count: count, size: layout.episodePageSize,
      offset: group.episodePageOffsets[season] ?? initialOffset ?? 0
    )
  }

  private func visibleEpisodes(_ episodes: [MoviePilotEpisode]) -> ArraySlice<MoviePilotEpisode> {
    guard let seasonNumber else { return episodes[...] }
    return episodes[episodePage(count: episodes.count, season: seasonNumber)]
  }

  private var visibleEpisodeOffset: Int? {
    guard let seasonNumber, case .episodes(let episodes) = rowContent else { return nil }
    return episodePage(count: episodes.count, season: seasonNumber).lowerBound
  }

  private var showsExpandButton: Bool {
    let loadedCount: Int
    if case .episodes(let episodes) = rowContent {
      loadedCount = episodes.count
    } else {
      loadedCount = 0
    }
    return MediaDetailEpisodeSeasons.canExpand(seasons: seasons, loadedEpisodeCount: loadedCount)
  }

  var body: some View {
    let session = apiService.sessionSnapshot()
    let requestedSeason = seasonNumber
    let availabilityRequest = allowsRequests ? makeAvailabilityRequest(session: session) : nil
    Group {
      switch layout {
      case .grid(let imageLifecycle):
        expandedGrid(imageLifecycle: imageLifecycle)
      case .shelf(let showsHeader, _):
        VStack(alignment: .leading, spacing: 0) {
          if showsHeader {
            shelfHeader
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          }
          shelfContent
            // 同演员行：翻页时行头从卡片位置往上滑入，卡片盖在它上面，不被胶囊挡住。
            .zIndex(2)
        }
      }
    }
    .task(id: allowsRequests && needsSeasonLookup
      ? SeasonRequest(groupID: groupID, retry: group.seasonRetry, session: session) : nil) {
      await loadSeasonsIfNeeded(session: session)
    }
    .task(
      id: allowsRequests ? EpisodeRequest(
        groupID: groupID,
        season: requestedSeason,
        retry: requestedSeason.map { group.episodeRetries[$0, default: 0] } ?? 0,
        session: session
      ) : nil
    ) {
      await loadEpisodesIfNeeded(season: requestedSeason, session: session)
    }
    .task(id: availabilityRequest) {
      await loadAvailability(availabilityRequest)
    }
    .task(id: allowsRequests ? polledTrialRequest?.key : nil) {
      guard allowsRequests, let request = polledTrialRequest else { return }
      await trial.poll(request)
    }
    .sheet(item: $panelEpisode, onDismiss: runAfterPanelDismiss) { episode in
      panel(for: episode)
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      afterPanelDismiss = nil
      panelEpisode = nil
    }
    // 焦点停在状态卡上时集列表到了：交给第一集，状态卡被移除时焦点不会跳出本行。
    .onChange(of: firstEpisodeID) { _, firstID in
      guard let firstID, focus == .status else { return }
      focus = .episode(firstID)
    }
  }

  // MARK: 行头

  private var shelfHeader: some View {
    HStack(spacing: 20) {
      shelfSeasonSelector
      Spacer(minLength: 0)
      episodePagePicker
      supplementalSeasonRetry
      availabilityRetry
      groupMenu?.control(defaultSeasons: defaultMenuSeasons)
      if case .shelf(_, let onExpand) = layout, showsExpandButton {
        Button("展开") {
          onExpand(MediaEpisodeGridRequest(
            mediaInfo: media, tmdbID: tmdbID, initialSeason: seasonNumber,
            initialEpisodeGroup: groupID, initialEpisodeOffset: visibleEpisodeOffset, playback: playback
          ))
        }
        .accessibilityLabel("展开剧集")
      }
    }
    .font(.callout)
    .padding(.horizontal, 81)
    .focusSection()
  }

  private var gridHeader: some View {
    DetailExpansionHeader(title: media.cleanedTitle ?? media.title ?? "剧集") {
      HStack(spacing: 20) {
        gridSeasonSelector
          .frame(maxWidth: .infinity, alignment: .leading)
        episodePagePicker
        supplementalSeasonRetry
        availabilityRetry
        if let groupMenu, groupMenu.isVisible {
          groupMenu.control(defaultSeasons: defaultMenuSeasons)
            .frame(maxWidth: 540, alignment: .trailing)
        }
      }
      .font(.callout)
      .focusSection()
    }
  }

  @ViewBuilder
  private var supplementalSeasonRetry: some View {
    if showsSupplementalSeasonRetry {
      Button("重试分季", systemImage: AppSymbol.retry, action: retrySeasonList)
    }
  }

  /// 媒体服务器读取失败通常整季每一集都一样（比如服务器连不上），在行头提示一次，不在每张卡上都盖警告。
  /// 具体原因在单集面板里。
  @ViewBuilder
  private var availabilityRetry: some View {
    if let seasonNumber, let state = currentAvailability(season: seasonNumber),
      state.results?.values.contains(where: { if case .failed = $0 { true } else { false } }) == true
    {
      Button("重试播放状态", systemImage: AppSymbol.warning) {
        retryAvailability(season: seasonNumber)
      }
      .accessibilityLabel("播放状态读取失败，重试")
    }
  }

  @ViewBuilder
  private var shelfSeasonSelector: some View {
    let options = seasonOptions
    if let seasonNumber, options.count > 1 {
      seasonControls(options, selection: seasonNumber, showsMenuTitle: true)
    } else {
      sectionTitle(options.first?.title ?? "剧集")
    }
  }

  @ViewBuilder
  private var gridSeasonSelector: some View {
    if let seasonNumber {
      seasonControls(seasonOptions, selection: seasonNumber, showsMenuTitle: false)
    }
  }

  @ViewBuilder
  private func seasonControls(_ options: [SeasonOption], selection: Int, showsMenuTitle: Bool) -> some View {
    if MediaDetailEpisodeSeasons.fitsChips(titles: options.map(\.title)) {
      // 同一行的季按钮与剧集组都直接参与横向焦点；季名放不下时改用菜单。
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) {
          ForEach(options) { option in
            ShelfChip(
              title: option.title, isSelected: selection == option.id,
              isFocused: focusedSeason == option.id
            ) {
              group.selectedSeason = option.id
            }
            .focused($focusedSeason, equals: option.id)
          }
        }
        .fixedSize(horizontal: true, vertical: false)
        seasonMenu(options, selection: selection, showsTitle: showsMenuTitle)
      }
    } else {
      seasonMenu(options, selection: selection, showsTitle: showsMenuTitle)
    }
  }

  private func seasonMenu(_ options: [SeasonOption], selection: Int, showsTitle: Bool) -> some View {
    let choices = options.map { PickerOption(title: $0.title, value: $0.id) }
    return HStack(spacing: 20) {
      if showsTitle { sectionTitle("剧集") }
      ShelfMenuPicker(
        title: "季",
        selection: Binding(get: { selection }, set: { group.selectedSeason = $0 }),
        options: choices,
        groups: MediaDetailEpisodeSeasons.menuGroups(choices)
      )
    }
  }

  @ViewBuilder
  private var episodePagePicker: some View {
    if let seasonNumber, case .episodes(let episodes) = rowContent,
      episodes.count > layout.episodePageSize
    {
      let page = episodePage(count: episodes.count, season: seasonNumber)
      ShelfMenuPicker(
        title: "集数范围",
        selection: Binding(
          get: { page.lowerBound },
          set: { group.episodePageOffsets[seasonNumber] = $0 }
        ),
        options: DetailPageRanges.ranges(count: episodes.count, size: layout.episodePageSize).map { range in
          PickerOption(
            title: DetailPageRanges.title(for: range, numbers: episodes[range].map(\.episodeNumber), unit: "集"),
            value: range.lowerBound
          )
        }
      )
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  private func expandedGrid(imageLifecycle: PageImageLifecycle) -> some View {
    let content = rowContent
    let episodes: [MoviePilotEpisode] =
      if case .episodes(let episodes) = content { Array(visibleEpisodes(episodes)) } else { [] }
    return DetailExpansionGrid(
      columns: EpisodeCardLayout.gridColumns,
      itemIDs: episodes.map { "\(groupID ?? ""):\($0.id)" },
      imageLifecycle: imageLifecycle,
      cardFocus: $focus,
      firstFocus: episodes.first.map { .episode($0.id) },
      lastFocus: episodes.last.map { .episode($0.id) }
    ) {
      gridHeader
    } status: {
      if case .status(let status, let retry) = content {
        statusRow(status, retry: retry, stillSize: EpisodeCardLayout.gridStillSize)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } card: { index, onFocus in
      episodeCard(episodes[index], stillSize: EpisodeCardLayout.gridStillSize, onFocus: onFocus)
    }
  }

  @ViewBuilder
  private var shelfContent: some View {
    switch rowContent {
    case .episodes(let episodes):
      let page = visibleEpisodes(episodes)
      let focusedID: MoviePilotEpisode.ID? = if case .episode(let id) = focus { id } else { nil }
      EpisodeShelfRow(episodes: page, focusedEpisodeID: focusedID) { episode, loadsImage in
        episodeCard(episode, stillSize: EpisodeCardLayout.stillSize, loadsImage: loadsImage)
      }
      .id(page.first?.id)
      .id(groupID)
    case .status(let status, let retry):
      statusRow(status, retry: retry, stillSize: EpisodeCardLayout.stillSize)
        .padding(.horizontal, 81)
        .padding(.top, 25)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func statusRow(
    _ status: EpisodeShelfStatusCard.Status, retry: (() -> Void)?, stillSize: CGSize
  ) -> some View {
    EpisodeShelfStatusRow(
      status: status,
      statusFocus: $focus,
      stillSize: stillSize,
      onRetry: retry.map { retry in
        {
          // 先把焦点交给状态卡：按下后重试按钮随即消失，焦点不能跟着掉出本行。
          focus = .status
          retry()
        }
      }
    )
    .focusSection()
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .bold()
      .foregroundStyle(.secondary)
      .lineLimit(1)
      // 与胶囊、菜单按钮里的文字对齐。
      .padding(.leading, 8)
  }

  // MARK: 卡片行

  private func episodeCard(
    _ episode: MoviePilotEpisode,
    stillSize: CGSize,
    loadsImage: Bool = true,
    onFocus: ((Bool) -> Void)? = nil
  ) -> some View {
    let entry = entry(for: episode)
    return EpisodeCard(
      episode: episode,
      stillURL: apiService.getSeasonPosterURL(posterPath: episode.stillPath, mediaPosterPath: nil),
      stillSize: stillSize,
      loadsImage: loadsImage,
      status: entry?.cardStatus,
      accessibilityStatus: entry?.accessibilityStatus,
      // 没有应用内播放时长按只有「详情」，和有播放时一样都有长按菜单。
      menuActions: entry?.menuActions ?? [.details],
      onSelect: { select(episode) },
      onPlayPause: { playPause(episode) },
      onMenuAction: { perform($0, on: episode) },
      onFocus: onFocus
    )
    .focused($focus, equals: .episode(episode.id))
  }

  // MARK: 播放与试看

  private func currentAvailability(season: Int) -> SeasonAvailability? {
    guard let playback, let state = group.availability[season], state.source == playback else { return nil }
    return state
  }

  private func playbackContext(_ source: EpisodePlaybackSource) -> EpisodePlaybackContext? {
    source.context(media: media, episodeGroup: groupID, seasons: seasons.compactMap(\.season_number))
  }

  /// 这一季里正在试看的那一集。本行显示着时由本行按页面的间隔刷新它的进度（见 `EpisodeTrialService.poll`），
  /// 卡片正中的进度跟得上；单集面板开着这一集时由面板刷新，不重复请求。
  private var polledTrialRequest: EpisodeTrialRequest? {
    guard let seasonNumber, case .loaded(let episodes) = group.episodeStates[seasonNumber],
      let episode = episodes.first(where: {
        $0.id != panelEpisode?.id && entry(for: $0)?.trial.isInProgress == true
      })
    else { return nil }
    return trialRequest(for: episode)
  }

  private func trialRequest(for episode: MoviePilotEpisode) -> EpisodeTrialRequest? {
    EpisodeTrialRequest(media: media, episode: episode, episodeGroup: groupID, libraryItem: playback?.libraryItem)
  }

  /// 一集的试看键，与按它建的请求的 `key` 相同。
  private func trialKey(for episode: MoviePilotEpisode) -> String? {
    EpisodeTrialRequest.key(tmdbID: tmdbID, episode: episode, episodeGroup: groupID)
  }

  /// 一集的入口状态；没有应用内播放时为 nil（按下只看简介，长按只有详情）。
  private func entry(for episode: MoviePilotEpisode) -> EpisodeEntry? {
    guard playback != nil else { return nil }
    let state = currentAvailability(season: episode.seasonNumber)
    if state?.isOffered == false { return nil }
    var snapshot = EpisodeTrialSnapshot()
    var block: EpisodeTrialBlock? = .unsupported
    if let key = trialKey(for: episode) {
      let seasonKey = EpisodeTrialRequest.seasonKey(
        tmdbID: tmdbID, season: episode.seasonNumber, episodeGroup: groupID)
      snapshot = trial.snapshot(key: key, seasonKey: seasonKey)
      snapshot.isStarting = startingTrials.contains(key)
      if media.identity != nil,
        EpisodeTrialAvailability.isAvailable(
          canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
          backendVersion: apiService.settings?.BACKEND_VERSION)
      {
        block = EpisodeEntry.notAiredDate(episode.airDate).map(EpisodeTrialBlock.notAired)
      }
    }
    return EpisodeEntry(
      availability: state?.results?[episode.id], isCheckingAvailability: state?.results == nil,
      trial: snapshot, trialBlock: block, canCancelTrial: trial.canCancelTrial,
      allowsSeasonDateOffset: groupID == nil && catalog.hasOnlyDefaultOrder)
  }

  private func select(_ episode: MoviePilotEpisode) {
    if entry(for: episode)?.primaryAction == .play {
      play(episode, allowsUncertain: confirmedByUser(episode))
    } else {
      panelEpisode = episode
    }
  }

  /// 遥控器播放键（见 `EpisodeEntry.playPauseAction`）。没有应用内播放时不响应。
  private func playPause(_ episode: MoviePilotEpisode) {
    switch entry(for: episode)?.playPauseAction {
    case .play: play(episode, allowsUncertain: confirmedByUser(episode))
    case .openPanel: panelEpisode = episode
    case .explain(let message): notificationManager.show(message: message, type: .info)
    case nil: break
    }
  }

  private func perform(_ action: EpisodeEntry.MenuAction, on episode: MoviePilotEpisode) {
    switch action {
    case .play: play(episode, allowsUncertain: confirmedByUser(episode))
    case .startTrial: startTrial(episode)
    case .cancelTrial(let id): cancelTrial(id)
    case .details: panelEpisode = episode
    }
  }

  private func performPanelAction(_ button: EpisodeEntry.PanelButton, on episode: MoviePilotEpisode) {
    switch button {
    case .play:
      let allowsUncertain = entry(for: episode)?.uncertainMatch != nil
      afterPanelDismiss = { play(episode, allowsUncertain: allowsUncertain) }
      panelEpisode = nil
    case .startTrial:
      // 进度显示在卡片正中，不用开着面板等：关掉面板，焦点回到这张卡。
      panelEpisode = nil
      startTrial(episode)
    case .cancelTrial(let id): cancelTrial(id)
    case .recheck: retryAvailability(season: episode.seasonNumber)
    case .confirmAndPlay:
      guard let uncertain = entry(for: episode)?.uncertainMatch, let tmdbEpisodeID = episode.tmdbEpisodeID else { return }
      apiService.sessionScope.playbackCoordinator.rememberEpisodeConfirmation(
        server: uncertain.server, match: uncertain.match, tmdbEpisodeID: tmdbEpisodeID)
      afterPanelDismiss = { play(episode, allowsUncertain: true) }
      panelEpisode = nil
      retryAvailability(season: episode.seasonNumber)
    case .forgetConfirmation:
      guard let uncertain = entry(for: episode)?.uncertainMatch else { return }
      apiService.sessionScope.playbackCoordinator.forgetEpisodeConfirmation(
        server: uncertain.server, match: uncertain.match)
      retryAvailability(season: episode.seasonNumber)
    }
  }

  /// 用户确认过的集按下直接播，起播时要允许只按季号集号对上的文件。
  private func confirmedByUser(_ episode: MoviePilotEpisode) -> Bool {
    entry(for: episode)?.isConfirmedByUser == true
  }

  private func runAfterPanelDismiss() {
    let action = afterPanelDismiss
    afterPanelDismiss = nil
    action?()
  }

  /// 按集起播：带上这一集所在那一季的集列表，播放器里能接着播上一集、下一集。
  private func play(_ episode: MoviePilotEpisode, allowsUncertain: Bool) {
    guard let playback, let context = playbackContext(playback),
      case .loaded(let list) = group.episodeStates[episode.seasonNumber]
    else { return }
    apiService.sessionScope.playbackCoordinator.play(
      .episode(QueuedEpisode(context: context, episode: episode, seasonEpisodes: list), allowsUncertain: allowsUncertain))
  }

  /// 发起试看（面板和长按菜单都从这里发起，面板已经关了）。结果显示在卡片上；卡片上看不出结果时（比如这一季已有订阅）
  /// 另外提示，这时又打开了这一集的面板就由面板说明。
  private func startTrial(_ episode: MoviePilotEpisode) {
    guard let request = trialRequest(for: episode), startingTrials.insert(request.key).inserted else { return }
    let service = trial
    let session = apiService.sessionSnapshot()
    Task { @MainActor in
      let result = await service.start(request)
      startingTrials.remove(request.key)
      // 创建没确认时卡片上不再显示试看中（服务不跟它），说明可以重新试看。
      let unconfirmed = service.snapshot(key: request.key, seasonKey: request.seasonKey).isSubmissionUnconfirmed
      guard apiService.isSessionUnchanged(from: session), panelEpisode?.id != episode.id,
        let message = unconfirmed ? EpisodeEntry.unconfirmedSubmissionMessage : EpisodeEntry.startFeedback(result)
      else { return }
      notificationManager.show(message: message, type: .info)
    }
  }

  private func cancelTrial(_ subscriptionID: Int) {
    guard cancellingTrials.insert(subscriptionID).inserted else { return }
    let service = trial
    let session = apiService.sessionSnapshot()
    Task { @MainActor in
      let outcome = await service.cancelTrial(subscriptionID: subscriptionID)
      cancellingTrials.remove(subscriptionID)
      guard outcome == .failed, apiService.isSessionUnchanged(from: session) else { return }
      notificationManager.show(message: EpisodeTrialHoldNotice.cancelFailure, type: .error)
    }
  }

  private func retryAvailability(season: Int) {
    guard currentAvailability(season: season)?.isRefreshing != true else { return }
    group.availabilityRetries[season, default: 0] += 1
  }

  @ViewBuilder
  private func panel(for episode: MoviePilotEpisode) -> some View {
    let entry = entry(for: episode) ?? EpisodeEntry(availability: nil)
    let request = trialRequest(for: episode)
    // 只在可能有试看要跟的时候刷新进度：已经能播、或不能试看时不请求后端。
    let pollsTrial = request != nil && !entry.offersPlayback
      && (entry.availability?.allowsTrial == true || entry.trial.isTracked || entry.trial.progress != nil)
    EpisodeActionSheet(
      episode: episode,
      seriesTitle: media.cleanedTitle ?? media.title,
      entry: entry,
      isCancellingTrial: entry.trial.subscriptionID.map(cancellingTrials.contains) ?? false,
      isRechecking: currentAvailability(season: episode.seasonNumber)?.isRefreshing == true,
      onAction: { performPanelAction($0, on: episode) }
    )
    .task(id: pollsTrial ? request?.key : nil) {
      guard pollsTrial, let request else { return }
      await trial.poll(request)
    }
  }

  // MARK: 加载

  private func retrySeasonList() {
    group.seasonLoad = .loading
    group.seasonRetry += 1
  }

  private func canPublish(_ session: APIServiceSessionSnapshot) -> Bool {
    !Task.isCancelled && apiService.uiIdentity == catalog.uiIdentity
      && apiService.isSessionUnchanged(from: session)
  }

  private func loadSeasonsIfNeeded(session: APIServiceSessionSnapshot) async {
    guard allowsRequests, needsSeasonLookup, canPublish(session) else { return }
    if case .loaded = group.seasonLoad, !seasons.isEmpty { return }
    let forceRefresh = group.seasonRetry > 0
    group.seasonLoad = .loading
    do {
      if let groupID {
        try await catalog.loadSeasons(groupID: groupID, apiService: apiService, forceRefresh: forceRefresh)
      } else {
        let result = try await MediaDetailEpisodeSeasons.fetch(
          media: media, forceRefresh: forceRefresh, apiService: apiService
        )
        guard canPublish(session) else { return }
        group.loadedSeasons = result
      }
      guard canPublish(session) else { return }
      group.seasonLoad = .loaded(())
    } catch {
      guard canPublish(session) else { return }
      group.seasonLoad = .failed
    }
  }

  private func makeAvailabilityRequest(session: APIServiceSessionSnapshot) -> AvailabilityRequest? {
    guard let playback, let seasonNumber, case .loaded(let episodes) = group.episodeStates[seasonNumber],
      !episodes.isEmpty
    else { return nil }
    return AvailabilityRequest(
      groupID: groupID, season: seasonNumber, episodeCount: episodes.count,
      episodeRetry: group.episodeRetries[seasonNumber, default: 0],
      retry: group.availabilityRetries[seasonNumber, default: 0], source: playback, session: session)
  }

  /// 查这一季每集能不能播：一季一次，在各台能播放的服务器上读这部剧的集（协调器缓存一分钟）。
  /// 重试时强制重读，期间沿用上次的结果。查之前就已试看入库的集，这次查到确认没有了，交给试看服务不再当作能播。
  private func loadAvailability(_ request: AvailabilityRequest?) async {
    guard let request, canPublish(request.session),
      case .loaded(let episodes) = group.episodeStates[request.season],
      let context = playbackContext(request.source)
    else { return }
    let previous = currentAvailability(season: request.season)
    let forceRefresh = request.retry > (previous?.retry ?? 0)
    var pending = previous ?? SeasonAvailability(source: request.source)
    pending.isRefreshing = previous?.results != nil
    group.availability[request.season] = pending
    let readyBeforeCheck = trial.readyEpisodes(among: episodes.compactMap(trialKey(for:)))
    let results = await apiService.sessionScope.playbackCoordinator.episodeAvailability(
      for: episodes, context: context, forceRefresh: forceRefresh)
    guard canPublish(request.session) else { return }
    var state = SeasonAvailability(source: request.source, retry: request.retry)
    if let results {
      state.results = Dictionary(zip(episodes.map(\.id), results), uniquingKeysWith: { first, _ in first })
      let rechecked = zip(episodes, results).compactMap { episode, availability in
        trialKey(for: episode).map { ($0, availability) }
      }
      trial.libraryRechecked(
        Dictionary(rechecked, uniquingKeysWith: { first, _ in first }), readyBeforeCheck: readyBeforeCheck)
    } else {
      state.results = [:]
      state.isOffered = false
    }
    group.availability[request.season] = state
  }

  private func loadEpisodesIfNeeded(season: Int?, session: APIServiceSessionSnapshot) async {
    guard allowsRequests, let season, canPublish(session) else { return }
    if case .loaded(let episodes) = group.episodeStates[season], !episodes.isEmpty { return }
    let retry = group.episodeRetries[season, default: 0]
    group.episodeStates[season] = .loading
    do {
      let result = try await apiService.fetchTmdbEpisodes(
        tmdbID: tmdbID, season: season, episodeGroup: groupID, forceRefresh: retry > 0
      )
      guard canPublish(session) else { return }
      group.episodeStates[season] = .loaded(MoviePilotEpisode.list(result, season: season))
    } catch {
      guard canPublish(session) else { return }
      group.episodeStates[season] = .failed
    }
  }
}

/// 剧集行的季列表规则，单独拆出便于测试。
enum MediaDetailEpisodeSeasons {
  /// 胶囊最多放几季、标题总字数上限。超过任一项改用下拉菜单，免得胶囊一行滚不完。
  static let maxChipCount = 8
  static let maxChipCharacters = 48

  static func tmdbID(for media: MediaInfo) -> Int? {
    guard media.type == "电视剧", media.identity?.source == "themoviedb" else { return nil }
    return MediaIdentifier.validNumericIdentifier(media.tmdb_id)
  }

  static func needsLookup(_ seasons: [TmdbSeason], media: MediaInfo) -> Bool {
    if seasons.isEmpty { return true }
    guard let expected = media.reportedSeasonCount else { return false }
    // 第 0 季是特别篇，不计入 TMDB 的常规季总数。
    return seasons.count(where: { ($0.season_number ?? 0) > 0 }) < expected
  }

  static func fetch(
    media: MediaInfo, forceRefresh: Bool, apiService: APIService
  ) async throws -> [TmdbSeason] {
    let seasons = try await apiService.getMediaSeasons(
      media: media, allSeasons: true, forceRefresh: forceRefresh
    )
    return selectable(seasons + (media.season_info ?? []))
  }

  static func canExpand(seasons: [TmdbSeason], loadedEpisodeCount: Int) -> Bool {
    seasons.count > 1 || loadedEpisodeCount > 10 || (seasons.first?.episode_count ?? 0) > 10
  }

  /// 去掉缺季号、负季号和重复季号，按季号升序（特别篇第 0 季在最前，与分季订阅一致）。
  static func selectable(_ seasons: [TmdbSeason]) -> [TmdbSeason] {
    var seen: Set<Int> = []
    return seasons.filter {
      guard let number = $0.season_number, number >= 0 else { return false }
      return seen.insert(number).inserted
    }.sorted { ($0.season_number ?? 0) < ($1.season_number ?? 0) }
  }

  /// 当前显示的季：用户选过的 → 详情指定的季 → 第一个正片季 → 第一季（只有特别篇时）。
  static func current(selected: Int?, preferred: Int?, available: [Int]) -> Int? {
    if let selected, available.contains(selected) { return selected }
    if let preferred, available.contains(preferred) { return preferred }
    return available.first(where: { $0 > 0 }) ?? available.first
  }

  static func fitsChips(titles: [String]) -> Bool {
    titles.count <= maxChipCount && titles.reduce(0) { $0 + $1.count } <= maxChipCharacters
  }

  static func menuGroups(_ options: [PickerOption<Int>]) -> [ShelfMenuOptionGroup<Int>] {
    let size = 50
    guard options.count > size else { return [] }

    let regular = Array(options.drop(while: { $0.value == 0 }))
    var groups: [ShelfMenuOptionGroup<Int>] = []
    if let specials = options.first, specials.value == 0 {
      groups.append(ShelfMenuOptionGroup(id: specials.value, title: nil, options: [specials]))
    }
    for range in DetailPageRanges.ranges(count: regular.count, size: size) {
      let first = regular[range.lowerBound].value
      let last = regular[range.upperBound - 1].value
      let title = first == last ? "第 \(first) 季" : "第 \(first)–\(last) 季"
      groups.append(ShelfMenuOptionGroup(id: first, title: title, options: Array(regular[range])))
    }
    return groups
  }
}

// MARK: - 单集卡片

/// 单集卡片的尺寸。四张卡正好铺满左右 81pt 安全边距之间，第五张只露出一条边，提示还能往右翻。
enum EpisodeCardLayout {
  static let spacing: CGFloat = 40
  static let stillSize = CGSize(width: 410, height: 231)
  private static let gridColumnCount = 4
  static let gridStillSize: CGSize = {
    let posterGridWidth = DetailExpansionGridLayout.width(
      columnWidth: MediaCard.defaultPosterSize.width, columnCount: MediaCard.defaultGridColumns.count
    )
    let gaps = CGFloat(gridColumnCount - 1) * DetailExpansionGridLayout.columnSpacing
    let width = (posterGridWidth - gaps) / CGFloat(gridColumnCount)
    return CGSize(width: width, height: width * stillSize.height / stillSize.width)
  }()
  static let gridColumns = DetailExpansionGridLayout.columns(width: gridStillSize.width, count: gridColumnCount)
  static let stillCornerRadius: CGFloat = 20
  static let focusedScale: CGFloat = 1.08
  /// 剧照和文字之间的距离（未聚焦）。
  static let textGap: CGFloat = 18
  /// 聚焦底板比文字多出的上下留白。
  static let platterVerticalInset: CGFloat = 16
  /// 聚焦底板与放大后剧照之间的缝。
  static let platterGap: CGFloat = 10

  /// 底板左右各伸出多少：正好与放大后的剧照左右两边对齐。
  static func platterHorizontalInset(stillWidth: CGFloat) -> CGFloat {
    stillWidth * (focusedScale - 1) / 2
  }

  /// 聚焦时文字下移多少：让底板顶边落在放大后剧照下方 `platterGap` 处。
  static func focusedTextOffset(stillSize: CGSize) -> CGFloat {
    stillSize.height * (focusedScale - 1) / 2 + platterGap + platterVerticalInset - textGap
  }
}

private struct EpisodeShelfRow<Card: View>: View {
  let episodes: ArraySlice<MoviePilotEpisode>
  let focusedEpisodeID: MoviePilotEpisode.ID?
  @ViewBuilder let card: (MoviePilotEpisode, Bool) -> Card
  private var memoryOptimization = MemoryOptimizationSettings()
  @State private var imageAnchorID: MoviePilotEpisode.ID?

  var body: some View {
    let anchorID = focusedEpisodeID ?? imageAnchorID
    let anchorIndex = episodes.firstIndex { $0.id == anchorID }
      .map { $0 - episodes.startIndex }
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: EpisodeCardLayout.spacing) {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { offset, episode in
          card(episode, ImageLoadWindow.containsHorizontalItem(
            at: offset, itemCount: episodes.count, anchorIndex: anchorIndex, cardKind: .episode,
            usesFocusWindow: memoryOptimization.isEnabled
          ))
        }
      }
      .padding(.horizontal, 81)
      .padding(.top, 25)
      .padding(.bottom, 30)
    }
    .scrollClipDisabled()
    .focusSection()
    .onChange(of: focusedEpisodeID, initial: true) { _, id in
      if let id { imageAnchorID = id }
    }
  }
}

private struct EpisodeCard: View {
  let episode: MoviePilotEpisode
  let stillURL: URL?
  let stillSize: CGSize
  let loadsImage: Bool
  let status: EpisodeEntry.CardStatus?
  let accessibilityStatus: String?
  /// 长按菜单，至少有「详情」。
  let menuActions: [EpisodeEntry.MenuAction]
  let onSelect: () -> Void
  let onPlayPause: () -> Void
  let onMenuAction: (EpisodeEntry.MenuAction) -> Void
  let onFocus: ((Bool) -> Void)?

  @FocusState private var isFocused: Bool

  var body: some View {
    Button(action: onSelect) {
      EpisodeCardContent(
        episode: episode, stillURL: stillURL, isFocused: isFocused,
        stillSize: stillSize, loadsImage: loadsImage, status: status
      )
      .contentShape(.rect)
    }
    .buttonStyle(EpisodeCardButtonStyle())
    .focusEffectDisabled()
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in onFocus?(focused) }
    .onPlayPauseCommand(perform: onPlayPause)
    // 菜单一直挂着，只换里面的项：状态到了时卡片不重建，焦点不丢。
    .contextMenu {
      ForEach(menuActions, id: \.menuID) { action in
        Button { onMenuAction(action) } label: {
          Label(action.title, systemImage: action.systemImage)
        }
      }
    }
    .accessibilityLabel(episode.cardTitle)
    .accessibilityValue((episode.metadata + [accessibilityStatus].compactMap { $0 }).joined(separator: "，"))
    .accessibilityActions {
      ForEach(menuActions, id: \.menuID) { action in
        Button(action.title) { onMenuAction(action) }
      }
    }
  }
}

extension EpisodeEntry.MenuAction {
  fileprivate var title: String {
    switch self {
    case .play: "播放"
    case .startTrial: "试看这一集"
    case .cancelTrial: EpisodeTrialHoldNotice.cancelTitle
    case .details: "详情"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .play: AppSymbol.play
    case .startTrial: AppSymbol.subscriptionTrial
    case .cancelTrial: AppSymbol.unsubscribe
    case .details: AppSymbol.details
    }
  }

  fileprivate var menuID: String {
    switch self {
    case .play: "play"
    case .startTrial: "startTrial"
    case .cancelTrial(let id): "cancelTrial-\(id)"
    case .details: "details"
    }
  }
}

/// 焦点外观由卡片内容自己画（剧照放大、文字底板），按钮样式只负责按下时略回缩。
private struct EpisodeCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}

/// 卡片内容：剧照在上，「第几集 · 时长 · 日期」、标题、两行简介在下。
/// 聚焦时剧照放大并投影，文字下面出现一块与放大后剧照同宽的底板。
struct EpisodeCardContent: View {
  let episode: MoviePilotEpisode?
  var stillURL: URL?
  var isFocused = false
  var stillSize = EpisodeCardLayout.stillSize
  var loadsImage = true
  /// 能不能播、试看到哪一步，画在剧照上（见 `EpisodeCardStatusOverlay`）。
  var status: EpisodeEntry.CardStatus?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: EpisodeCardLayout.textGap) {
      still
        .scaleEffect(isFocused ? EpisodeCardLayout.focusedScale : 1)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, y: 10)
      EpisodeCardText(episode: episode, focusProgress: isFocused ? 1 : 0, stillSize: stillSize)
    }
    .frame(width: stillSize.width, alignment: .leading)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isFocused)
  }

  private var still: some View {
    ZStack {
      Rectangle()
        .fill(Color(white: 0.12))
      Image(systemName: AppSymbol.imagePlaceholder)
        .font(.title3)
        .foregroundStyle(.secondary)
      if episode != nil {
        PageManagedImage(
          url: stillURL,
          processor: DownsamplingImageProcessor(size: stillSize),
          isEnabled: loadsImage,
          participatesInPageLifecycle: true,
          skipsMemoryCache: true
        )
      }
      if let status {
        EpisodeCardStatusOverlay(status: status, stillSize: stillSize)
          .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
    .frame(width: stillSize.width, height: stillSize.height)
    .clipShape(.rect(cornerRadius: EpisodeCardLayout.stillCornerRadius))
    .accessibilityHidden(true)
  }
}

/// 卡片的文字部分。三行都预留行高，所有卡片、状态行一样高。
struct EpisodeCardText: View, Animatable {
  let episode: MoviePilotEpisode?
  nonisolated var focusProgress: CGFloat = 0
  var stillSize = EpisodeCardLayout.stillSize

  nonisolated var animatableData: CGFloat {
    get { focusProgress }
    set { focusProgress = newValue }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(episode?.eyebrow ?? "第 1 集 · 45 分钟")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1, reservesSpace: true)
      Text(episode?.displayTitle ?? "剧集标题")
        .font(.caption.bold())
        .foregroundStyle(Color.secondary.mix(with: .primary, by: Double(focusProgress)))
        .lineLimit(1, reservesSpace: true)
      Text(episode.map { $0.displayOverview ?? "暂无简介" } ?? "单集简介\n单集简介")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2, reservesSpace: true)
        .padding(.top, 2)
    }
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      // 底板只画在背景里往外伸，不改变卡片的布局尺寸。
      RoundedRectangle(cornerRadius: EpisodeCardLayout.stillCornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.18 * Double(focusProgress)))
        .padding(.horizontal, -EpisodeCardLayout.platterHorizontalInset(stillWidth: stillSize.width))
        .padding(.vertical, -EpisodeCardLayout.platterVerticalInset)
    }
    .compositingGroup()
    .offset(y: EpisodeCardLayout.focusedTextOffset(stillSize: stillSize) * focusProgress)
  }
}

// MARK: - 状态

/// 行里还没有单集可显示时：剧照大小、可聚焦的状态卡，能重试时按钮在它右侧。
/// 加载中、失败、为空是同一张卡，状态变化时焦点留在原地。下面按卡片文字预留同样高度，内容到了行高不跳。
private struct EpisodeShelfStatusRow: View {
  let status: EpisodeShelfStatusCard.Status
  var statusFocus: FocusState<EpisodeRowFocus?>.Binding
  let stillSize: CGSize
  let onRetry: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: EpisodeCardLayout.textGap) {
      HStack(spacing: EpisodeCardLayout.spacing) {
        EpisodeShelfStatusCard(
          status: status, stillSize: stillSize, isFocused: statusFocus.wrappedValue == .status
        )
          .focused(statusFocus, equals: .status)
        if let onRetry {
          Button("重试", systemImage: AppSymbol.retry, action: onRetry)
        }
      }
      EpisodeCardText(episode: nil, stillSize: stillSize)
        .frame(width: stillSize.width)
        .hidden()
        .accessibilityHidden(true)
    }
  }
}

struct EpisodeShelfStatusCard: View {
  enum Status: Equatable {
    case loading(String)
    case failed(String)
    case empty(String)

    var text: String {
      switch self {
      case .loading(let text), .failed(let text), .empty(let text): return text
      }
    }
  }

  let status: Status
  var stillSize = EpisodeCardLayout.stillSize
  let isFocused: Bool

  var body: some View {
    VStack(spacing: 14) {
      switch status {
      case .loading:
        ProgressView()
      case .failed:
        Image(systemName: AppSymbol.warning)
          .font(.title3)
          .foregroundStyle(.secondary)
      case .empty:
        Image(systemName: AppSymbol.noResults)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      Text(status.text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(width: stillSize.width, height: stillSize.height)
    .textCardFocusAppearance(isFocused: isFocused)
    .focusable()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.text)
    .accessibilityAddTraits(.isStaticText)
  }
}

extension MoviePilotEpisode {
  var episodeLabel: String? {
    episodeNumber.flatMap { $0 >= 0 ? "第 \($0) 集" : nil }
  }

  /// 详情 Sheet 标题：「第 N 集 · 标题」。
  var cardTitle: String {
    let parts = [episodeLabel, trimmedNonEmpty([name])].compactMap { $0 }
    return parts.isEmpty ? "单集详情" : parts.joined(separator: " · ")
  }

  /// 卡片标题：单集名；没有名字时用「第 N 集」。
  var displayTitle: String {
    trimmedNonEmpty([name]) ?? episodeLabel ?? "单集"
  }

  /// 卡片顶行小字：「第 N 集 · 45 分钟 · 2024-01-01」。
  var eyebrow: String {
    ([episodeLabel] + metadata.map(Optional.some)).compactMap { $0 }.joined(separator: " · ")
  }

  /// 播出日期与时长
  var metadata: [String] {
    let runtime = runtimeMinutes.flatMap { $0 > 0 ? "\($0) 分钟" : nil }
    return [runtime, trimmedNonEmpty([airDate])].compactMap { $0 }
  }

  var displayOverview: String? {
    trimmedNonEmpty([overview])
  }
}
