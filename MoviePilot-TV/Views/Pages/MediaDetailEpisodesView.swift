import Kingfisher
import SwiftUI

/// 详情页「剧集」行：行头选季（和剧集组），下面是这一季的单集卡片。
struct MediaDetailEpisodesView: View {
  let media: MediaInfo
  let tmdbID: Int
  let subscriptionSeasons: SubscribeSeasonViewModel?
  let allowsRequests: Bool
  let isContentVisible: Bool
  /// 第一页底部只露出卡片：本行是第二页首行时，行头在翻到第二页后才出现，与其他行一致。
  let showsHeader: Bool
  let onExpand: (MediaEpisodeGridRequest) -> Void
  let onSelect: (MoviePilotEpisode) -> Void

  var body: some View {
    if let subscriptionSeasons {
      SharedEpisodeGroupView(seasons: subscriptionSeasons) { groupID in
        shelf(groupID: groupID, groupMenu: nil)
      }
    } else {
      LocalEpisodeGroupView(tmdbID: tmdbID, isActive: allowsRequests && isContentVisible) {
        groupID, groupMenu in
        shelf(groupID: groupID, groupMenu: groupMenu)
      }
    }
  }

  private func shelf(groupID: String?, groupMenu: EpisodeGroupMenu?) -> some View {
    EpisodeBrowser(
      media: media, tmdbID: tmdbID, groupID: groupID, groupMenu: groupMenu,
      allowsRequests: allowsRequests,
      layout: .shelf(showsHeader: showsHeader, onExpand: onExpand), onSelect: onSelect
    )
  }
}

struct MediaEpisodeGridView: View {
  let request: MediaEpisodeGridRequest
  let imageLifecycle: PageImageLifecycle
  let allowsRequests: Bool
  @State private var selectedEpisode: MoviePilotEpisode?

  var body: some View {
    LocalEpisodeGroupView(
      tmdbID: request.tmdbID, isActive: allowsRequests,
      initialGroupID: request.initialEpisodeGroup
    ) { groupID, groupMenu in
      EpisodeBrowser(
        media: request.mediaInfo, tmdbID: request.tmdbID, groupID: groupID, groupMenu: groupMenu,
        allowsRequests: allowsRequests,
        layout: .grid(imageLifecycle),
        initialSeason: groupID == request.initialEpisodeGroup ? request.initialSeason : nil,
        initialEpisodeOffset: groupID == request.initialEpisodeGroup ? request.initialEpisodeOffset : nil,
        onSelect: { selectedEpisode = $0 }
      )
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: APIService.shared)) { _ in
      selectedEpisode = nil
    }
    .sheet(item: $selectedEpisode) { episode in
      EpisodeDetailSheet(episode: episode)
    }
  }
}

/// 详情页有分季订阅时，沿用它的剧集组选择（选择器在分季订阅的行头）。只观察选择，单集请求不等待订阅或入库查询。
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
  let content: (String?, EpisodeGroupMenu) -> Content

  @State private var catalog = EpisodeGroupCatalog()
  @State private var selectedGroupID: String

  init(
    tmdbID: Int, isActive: Bool, initialGroupID: String? = nil,
    content: @escaping (String?, EpisodeGroupMenu) -> Content
  ) {
    self.tmdbID = tmdbID
    self.isActive = isActive
    self.content = content
    _selectedGroupID = State(initialValue: initialGroupID ?? "")
  }

  var body: some View {
    content(
      trimmedNonEmpty([selectedGroupID]),
      EpisodeGroupMenu(groups: catalog.groups, selection: $selectedGroupID)
    )
    .task(id: isActive) {
      guard isActive else { return }
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
  let media: MediaInfo
  let tmdbID: Int
  let groupID: String?
  let groupMenu: EpisodeGroupMenu?
  let allowsRequests: Bool
  let layout: EpisodeBrowserLayout
  var initialSeason: Int? = nil
  var initialEpisodeOffset: Int? = nil
  let onSelect: (MoviePilotEpisode) -> Void

  @State private var storedGroup = GroupState(id: nil)
  @FocusState private var focus: EpisodeRowFocus?
  @FocusState private var focusedSeason: Int?

  private struct GroupState {
    let id: String?
    var loadedSeasons: [TmdbSeason]?
    var seasonLoad: EpisodeLoadState<Void>?
    var seasonRetry = 0
    var selectedSeason: Int?
    var episodeStates: [Int: EpisodeLoadState<[MoviePilotEpisode]>] = [:]
    var episodeRetries: [Int: Int] = [:]
    var episodePageOffsets: [Int: Int] = [:]
  }

  // 切换剧集组时只更换数据，不重建剧集组按钮，保留遥控器焦点。
  private var group: GroupState {
    get { storedGroup.id == groupID ? storedGroup : GroupState(id: groupID) }
    nonmutating set { storedGroup = newValue }
  }

  private struct SeasonRequest: Equatable {
    let groupID: String?
    let retry: Int
  }

  private struct EpisodeRequest: Equatable {
    let groupID: String?
    let season: Int?
    let retry: Int
    let isActive: Bool
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
    group.loadedSeasons ?? detailSeasons
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
    let requestedSeason = seasonNumber
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
      ? SeasonRequest(groupID: groupID, retry: group.seasonRetry) : nil) {
      await loadSeasonsIfNeeded()
    }
    .task(
      id: EpisodeRequest(
        groupID: groupID,
        season: requestedSeason,
        retry: requestedSeason.map { group.episodeRetries[$0, default: 0] } ?? 0,
        isActive: allowsRequests
      )
    ) {
      await loadEpisodesIfNeeded(season: requestedSeason)
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
      groupMenu?.control(defaultSeasons: defaultMenuSeasons)
      if case .shelf(_, let onExpand) = layout, showsExpandButton {
        Button("展开") {
          onExpand(MediaEpisodeGridRequest(
            mediaInfo: media, tmdbID: tmdbID, initialSeason: seasonNumber,
            initialEpisodeGroup: groupID, initialEpisodeOffset: visibleEpisodeOffset
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
        if let groupMenu, !groupMenu.groups.isEmpty {
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
      shelfRow(page)
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

  private func shelfRow(_ episodes: ArraySlice<MoviePilotEpisode>) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: EpisodeCardLayout.spacing) {
        ForEach(episodes) { episode in
          episodeCard(episode, stillSize: EpisodeCardLayout.stillSize)
        }
      }
      .padding(.horizontal, 81)
      .padding(.top, 25)
      .padding(.bottom, 30)
    }
    .scrollClipDisabled()
    .focusSection()
  }

  private func episodeCard(
    _ episode: MoviePilotEpisode, stillSize: CGSize, onFocus: ((Bool) -> Void)? = nil
  ) -> some View {
    EpisodeCard(
      episode: episode,
      stillURL: apiService.getSeasonPosterURL(posterPath: episode.stillPath, mediaPosterPath: nil),
      stillSize: stillSize,
      onSelect: { onSelect(episode) },
      onFocus: onFocus
    )
    .focused($focus, equals: .episode(episode.id))
  }

  // MARK: 加载

  private func retrySeasonList() {
    group.seasonLoad = .loading
    group.seasonRetry += 1
  }

  private func loadSeasonsIfNeeded() async {
    guard !Task.isCancelled, allowsRequests, needsSeasonLookup else { return }
    if case .loaded = group.seasonLoad { return }
    group.seasonLoad = .loading
    do {
      let result = try await MediaDetailEpisodeSeasons.fetch(
        media: media, groupID: groupID, forceRefresh: group.seasonRetry > 0, apiService: apiService
      )
      try Task.checkCancellation()
      group.loadedSeasons = result
      group.seasonLoad = .loaded(())
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      group.seasonLoad = .failed
    }
  }

  private func loadEpisodesIfNeeded(season: Int?) async {
    guard !Task.isCancelled, allowsRequests, let season else { return }
    if case .loaded(let episodes) = group.episodeStates[season], !episodes.isEmpty { return }
    let retry = group.episodeRetries[season, default: 0]
    group.episodeStates[season] = .loading
    do {
      let result = try await apiService.fetchTmdbEpisodes(
        tmdbID: tmdbID, season: season, episodeGroup: groupID, forceRefresh: retry > 0
      )
      try Task.checkCancellation()
      group.episodeStates[season] = .loaded(MoviePilotEpisode.list(result, season: season))
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
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
    media: MediaInfo, groupID: String?, forceRefresh: Bool, apiService: APIService
  ) async throws -> [TmdbSeason] {
    if let groupID {
      let seasons = try await apiService.getGroupSeasons(groupId: groupID, forceRefresh: forceRefresh)
      return selectable(seasons)
    }
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

private struct EpisodeCard: View {
  let episode: MoviePilotEpisode
  let stillURL: URL?
  let stillSize: CGSize
  let onSelect: () -> Void
  let onFocus: ((Bool) -> Void)?

  @FocusState private var isFocused: Bool

  var body: some View {
    Button(action: onSelect) {
      EpisodeCardContent(
        episode: episode, stillURL: stillURL, isFocused: isFocused,
        stillSize: stillSize
      )
      .contentShape(.rect)
    }
    .buttonStyle(EpisodeCardButtonStyle())
    .focusEffectDisabled()
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in onFocus?(focused) }
    .accessibilityLabel(episode.cardTitle)
    .accessibilityValue(episode.metadata.joined(separator: "，"))
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
          isEnabled: true,
          participatesInPageLifecycle: true,
          skipsMemoryCache: true
        )
      }
    }
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

// MARK: - 单集详情

struct EpisodeDetailSheet: View {
  let episode: MoviePilotEpisode

  var body: some View {
    let overview = episode.displayOverview.map(ReadingSheetLayout.paragraphs) ?? []
    let details = episode.metadata.isEmpty
      ? [] : [ReadingBlock(episode.metadata.joined(separator: " · "), style: .secondary)]
    let paragraphs = overview.isEmpty
      ? [ReadingBlock("暂无简介", style: .secondary)] : overview.map { ReadingBlock($0) }
    ReadingSheet(title: episode.cardTitle, blocks: details + paragraphs)
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
