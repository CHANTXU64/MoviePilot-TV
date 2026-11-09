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
    EpisodeShelf(
      media: media, tmdbID: tmdbID, groupID: groupID, groupMenu: groupMenu,
      allowsRequests: allowsRequests, isContentVisible: isContentVisible,
      showsHeader: showsHeader, onSelect: onSelect
    )
    // 换剧集组后季号含义不同，季列表、选中的季和已加载的集都从头来。
    .id(groupID)
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
  let content: (String?, EpisodeGroupMenu?) -> Content

  @State private var groups: [EpisodeGroup] = []
  @State private var selectedGroupID = ""

  var body: some View {
    content(
      trimmedNonEmpty([selectedGroupID]),
      groups.isEmpty ? nil : EpisodeGroupMenu(groups: groups, selection: $selectedGroupID)
    )
    .task(id: isActive) {
      guard isActive else { return }
      do {
        let loaded = try await apiService.fetchEpisodeGroups(tmdbId: tmdbID)
        try Task.checkCancellation()
        groups = loaded
      } catch {
        // 默认编排独立可用，剧集组查询失败不挡住当前季。
      }
    }
  }
}

struct EpisodeGroupMenu {
  let groups: [EpisodeGroup]
  let selection: Binding<String>
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

private struct EpisodeShelf: View {
  @ObservedObject private var apiService = APIService.shared
  let media: MediaInfo
  let tmdbID: Int
  let groupID: String?
  let groupMenu: EpisodeGroupMenu?
  let allowsRequests: Bool
  let isContentVisible: Bool
  let showsHeader: Bool
  let onSelect: (MoviePilotEpisode) -> Void

  @State private var loadedSeasons: EpisodeLoadState<[TmdbSeason]>?
  @State private var seasonRetry = 0
  @State private var selectedSeason: Int?
  /// 本剧集组下已请求过的季，切回去直接显示，不再闪一次加载。
  @State private var episodeStates: [Int: EpisodeLoadState<[MoviePilotEpisode]>] = [:]
  @State private var episodeRetries: [Int: Int] = [:]
  @FocusState private var focus: EpisodeRowFocus?

  private struct EpisodeRequest: Equatable {
    let season: Int?
    let retry: Int
    let isActive: Bool
  }

  // MARK: 季

  private var detailSeasons: [TmdbSeason] {
    guard groupID == nil else { return [] }
    return MediaDetailEpisodeSeasons.selectable(media.season_info ?? [])
  }

  private var seasons: [TmdbSeason] {
    if !detailSeasons.isEmpty { return detailSeasons }
    guard case .loaded(let loaded) = loadedSeasons else { return [] }
    return MediaDetailEpisodeSeasons.selectable(loaded)
  }

  private var seasonOptions: [SeasonOption] {
    seasons.compactMap { season in
      season.season_number.map { SeasonOption(id: $0, title: seasonName(season, number: $0)) }
    }
  }

  private var seasonNumber: Int? {
    MediaDetailEpisodeSeasons.current(
      selected: selectedSeason,
      preferred: groupID == nil ? media.season : nil,
      available: seasonOptions.map(\.id)
    )
  }

  private func seasonName(_ season: TmdbSeason, number: Int) -> String {
    if groupID != nil, let name = trimmedNonEmpty([season.name]) { return name }
    return SeasonDisplayFormatter.name(seasonNumber: number, rawName: season.name)
  }

  // MARK: 行内容

  private enum RowContent {
    case episodes([MoviePilotEpisode])
    case status(EpisodeShelfStatusCard.Status, retry: (() -> Void)?)
  }

  private var rowContent: RowContent {
    guard let seasonNumber else {
      switch loadedSeasons {
      case .failed:
        return .status(.failed("分季信息加载失败"), retry: { seasonRetry += 1 })
      case .loaded:
        return .status(.empty("暂无分季信息"), retry: nil)
      case .loading, nil:
        return .status(.loading("正在加载分季信息"), retry: nil)
      }
    }
    let retry = { episodeRetries[seasonNumber, default: 0] += 1 }
    switch episodeStates[seasonNumber] {
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
    return episodes.first?.id
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsHeader {
        header
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
      row
        // 同演员行：翻页时行头从卡片位置往上滑入，卡片盖在它上面，不被胶囊挡住。
        .zIndex(2)
    }
    .task(id: allowsRequests && detailSeasons.isEmpty ? seasonRetry : nil) {
      await loadSeasonsIfNeeded()
    }
    .task(
      id: EpisodeRequest(
        season: seasonNumber,
        retry: seasonNumber.map { episodeRetries[$0, default: 0] } ?? 0,
        isActive: allowsRequests && isContentVisible
      )
    ) {
      await loadEpisodesIfNeeded()
    }
    // 焦点停在状态卡上时集列表到了：交给第一集，状态卡被移除时焦点不会跳出本行。
    .onChange(of: firstEpisodeID) { _, firstID in
      guard let firstID, focus == .status else { return }
      focus = .episode(firstID)
    }
  }

  // MARK: 行头

  private var header: some View {
    HStack(spacing: 20) {
      seasonSelector
      Spacer(minLength: 0)
      if let groupMenu {
        ShelfMenuPicker(
          title: "剧集组",
          selection: groupMenu.selection,
          options: EpisodeGroup.menuOptions(groupMenu.groups),
          label: { "剧集组：\($0)" }
        )
      }
    }
    .font(.callout)
    .padding(.horizontal, 81)
    .focusSection()
  }

  @ViewBuilder
  private var seasonSelector: some View {
    let options = seasonOptions
    if let seasonNumber, options.count > 1 {
      if MediaDetailEpisodeSeasons.fitsChips(titles: options.map(\.title)) {
        ShelfPicker(
          items: options,
          selection: Binding(
            get: { options.first { $0.id == seasonNumber } },
            set: { if let option = $0 { selectedSeason = option.id } }
          ),
          title: \.title
        )
      } else {
        sectionTitle("剧集")
        ShelfMenuPicker(
          title: "季",
          selection: Binding(get: { seasonNumber }, set: { selectedSeason = $0 }),
          options: options.map { PickerOption(title: $0.title, value: $0.id) }
        )
      }
    } else {
      sectionTitle(options.first?.title ?? "剧集")
    }
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

  @ViewBuilder
  private var row: some View {
    switch rowContent {
    case .episodes(let episodes):
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: EpisodeCardLayout.spacing) {
          ForEach(episodes) { episode in
            EpisodeCard(
              episode: episode,
              stillURL: apiService.getSeasonPosterURL(posterPath: episode.stillPath, mediaPosterPath: nil),
              onSelect: { onSelect(episode) }
            )
            .focused($focus, equals: .episode(episode.id))
          }
        }
        .padding(.horizontal, 81)
        .padding(.top, 25)
        .padding(.bottom, 30)
      }
      .scrollClipDisabled()
      .focusSection()
    case .status(let status, let retry):
      EpisodeShelfStatusRow(
        status: status,
        statusFocus: $focus,
        onRetry: retry.map { retry in
          {
            // 先把焦点交给状态卡：按下后重试按钮随即消失，焦点不能跟着掉出本行。
            focus = .status
            retry()
          }
        }
      )
      .padding(.horizontal, 81)
      .padding(.top, 25)
      .padding(.bottom, 30)
      .frame(maxWidth: .infinity, alignment: .leading)
      .focusSection()
    }
  }

  // MARK: 加载

  private func loadSeasonsIfNeeded() async {
    guard allowsRequests, detailSeasons.isEmpty else { return }
    if case .loaded = loadedSeasons { return }
    loadedSeasons = .loading
    do {
      let result: [TmdbSeason]
      if let groupID {
        result = try await apiService.getGroupSeasons(groupId: groupID)
      } else {
        result = try await apiService.getMediaSeasons(media: media)
      }
      try Task.checkCancellation()
      loadedSeasons = .loaded(result)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      loadedSeasons = .failed
    }
  }

  private func loadEpisodesIfNeeded() async {
    guard allowsRequests, isContentVisible, let season = seasonNumber else { return }
    if case .loaded(let episodes) = episodeStates[season], !episodes.isEmpty { return }
    let retry = episodeRetries[season, default: 0]
    episodeStates[season] = .loading
    do {
      let result = try await apiService.fetchTmdbEpisodes(
        tmdbID: tmdbID, season: season, episodeGroup: groupID, forceRefresh: retry > 0
      )
      try Task.checkCancellation()
      episodeStates[season] = .loaded(MoviePilotEpisode.list(result, season: season))
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      episodeStates[season] = .failed
    }
  }
}

/// 剧集行的季列表规则，单独拆出便于测试。
enum MediaDetailEpisodeSeasons {
  /// 胶囊最多放几季、标题总字数上限。超过任一项改用下拉菜单，免得胶囊一行滚不完。
  static let maxChipCount = 8
  static let maxChipCharacters = 48

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
}

// MARK: - 单集卡片

/// 单集卡片的尺寸。四张卡正好铺满左右 81pt 安全边距之间，第五张只露出一条边，提示还能往右翻。
enum EpisodeCardLayout {
  static let spacing: CGFloat = 40
  static let stillSize = CGSize(width: 410, height: 231)
  static let stillCornerRadius: CGFloat = 20
  static let focusedScale: CGFloat = 1.08
  /// 剧照和文字之间的距离（未聚焦）。
  static let textGap: CGFloat = 18
  /// 聚焦底板比文字多出的上下留白。
  static let platterVerticalInset: CGFloat = 16
  /// 聚焦底板与放大后剧照之间的缝。
  static let platterGap: CGFloat = 10

  /// 底板左右各伸出多少：正好与放大后的剧照左右两边对齐。
  static var platterHorizontalInset: CGFloat {
    stillSize.width * (focusedScale - 1) / 2
  }

  /// 聚焦时文字下移多少：让底板顶边落在放大后剧照下方 `platterGap` 处。
  static var focusedTextOffset: CGFloat {
    stillSize.height * (focusedScale - 1) / 2 + platterGap + platterVerticalInset - textGap
  }
}

private struct EpisodeCard: View {
  let episode: MoviePilotEpisode
  let stillURL: URL?
  let onSelect: () -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    Button(action: onSelect) {
      EpisodeCardContent(episode: episode, stillURL: stillURL, isFocused: isFocused)
        .contentShape(.rect)
    }
    .buttonStyle(EpisodeCardButtonStyle())
    .focusEffectDisabled()
    .focused($isFocused)
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: EpisodeCardLayout.textGap) {
      still
        .scaleEffect(isFocused ? EpisodeCardLayout.focusedScale : 1)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, y: 10)
      EpisodeCardText(episode: episode, isFocused: isFocused)
        .offset(y: isFocused ? EpisodeCardLayout.focusedTextOffset : 0)
    }
    .frame(width: EpisodeCardLayout.stillSize.width, alignment: .leading)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFocused)
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
          processor: DownsamplingImageProcessor(size: EpisodeCardLayout.stillSize),
          // Hero 和剧集区在同一次滚动过渡中都可能可见，图片随导航页的生命周期释放。
          isEnabled: true,
          participatesInPageLifecycle: true,
          skipsMemoryCache: true
        )
      }
    }
    .frame(width: EpisodeCardLayout.stillSize.width, height: EpisodeCardLayout.stillSize.height)
    .clipShape(.rect(cornerRadius: EpisodeCardLayout.stillCornerRadius))
    .accessibilityHidden(true)
  }
}

/// 卡片的文字部分。三行都预留行高，所有卡片、状态行一样高。
struct EpisodeCardText: View {
  let episode: MoviePilotEpisode?
  var isFocused = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(episode?.eyebrow ?? "第 1 集 · 45 分钟")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1, reservesSpace: true)
      Text(episode?.displayTitle ?? "剧集标题")
        .font(.caption.bold())
        .foregroundStyle(.primary)
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
        .fill(Color.white.opacity(isFocused ? 0.18 : 0))
        .padding(.horizontal, -EpisodeCardLayout.platterHorizontalInset)
        .padding(.vertical, -EpisodeCardLayout.platterVerticalInset)
    }
  }
}

// MARK: - 状态

/// 行里还没有单集可显示时：剧照大小、可聚焦的状态卡，失败时旁边跟「重试」。
/// 加载中、失败、为空是同一张卡，状态变化时焦点留在原地。下面按卡片文字预留同样高度，内容到了行高不跳。
private struct EpisodeShelfStatusRow: View {
  let status: EpisodeShelfStatusCard.Status
  var statusFocus: FocusState<EpisodeRowFocus?>.Binding
  let onRetry: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: EpisodeCardLayout.textGap) {
      HStack(spacing: EpisodeCardLayout.spacing) {
        EpisodeShelfStatusCard(status: status)
          .focused(statusFocus, equals: .status)
        if let onRetry {
          Button("重试", systemImage: AppSymbol.retry, action: onRetry)
        }
      }
      EpisodeCardText(episode: nil)
        .frame(width: EpisodeCardLayout.stillSize.width)
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

  var body: some View {
    // 卡片本身不响应选择键；失败时由旁边的「重试」重新加载。
    Button {
    } label: {
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
      .frame(width: EpisodeCardLayout.stillSize.width, height: EpisodeCardLayout.stillSize.height)
    }
    .buttonStyle(TextCardButtonStyle())
    .accessibilityLabel(status.text)
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

extension EpisodeGroup {
  /// 剧集组下拉菜单的选项：第一项是 TMDB 默认顺序（空字符串）。
  static func menuOptions(_ groups: [EpisodeGroup]) -> [PickerOption<String>] {
    [PickerOption(title: "默认", value: "")]
      + groups.map { PickerOption(title: $0.name, value: $0.id) }
  }
}
