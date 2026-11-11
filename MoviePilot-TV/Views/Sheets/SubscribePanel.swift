import SwiftUI

/// 订阅面板。新增订阅：先是只看的快速面板，点「订阅设置」后同一个 Sheet 原地变成三栏大面板。
/// 编辑订阅：直接是三栏大面板，左栏只放固定信息（已有集数、订阅状态），按钮是「保存」。
///
/// 快速面板上面是媒体（片名、类型 · 年份），下面一排是这次订阅会用的设置标签，
/// 「订阅」直接提交；要改设置才进大面板。不放海报：只会从媒体卡片或详情页进来，进来前已经看过海报。
///
/// 系统 sheet 改尺寸不做动画，边框会直接跳到新尺寸，所以变大分三步：先淡出快速面板内容 →
/// 内容为空时切换尺寸 → 再淡入大面板内容。tvOS 18 的 sheet 本来就是全屏，只有内容变化。
/// 变大后按 Menu 关闭整个 Sheet（系统行为），不退回快速面板。
///
/// 出错统一处理：加载失败、订阅（保存）失败、之后启用或搜索失败，都在按钮上方显示一行原因，
/// 能重试时下面再放一个「重试」；「订阅」「订阅设置」不藏，默认焦点仍在「订阅」。
/// 加载失败时直接按「订阅」或「订阅设置」也会先重新加载，成功后接着做。
/// 加载失败又不能重试（需要关掉重开）时，「订阅设置」不可用，主按钮变成「关闭」。
struct SubscribePanel: View {
  @ObservedObject var viewModel: SubscribeSheetViewModel
  let isSaving: Bool
  let onSubscribe: () -> Void

  @State private var isExpanded = false
  @State private var isContentVisible = true
  @State private var isReloading = false
  /// 面板还在显示；关掉后迟到的重新加载结果不再接着订阅。
  @State private var isActive = true
  @FocusState private var isConfirmFocused: Bool
  @FocusState private var focusedField: SubscribeSettingField?

  var body: some View {
    // 不单独显示加载页：系统 sheet 换尺寸没有动画，加载页和面板来回切会连闪几下。
    // 一打开就是最终尺寸的面板，加载中只让主按钮显示「加载中」。
    Group {
      if isExpanded || !viewModel.isNewSubscription {
        // 打开新增时查到已有订阅，会切成编辑，这时也直接显示大面板。
        expandedPanel
      } else {
        quickPanel
      }
    }
    .scaleEffect(isContentVisible ? 1 : 0.97)
    .opacity(isContentVisible ? 1 : 0)
    .onAppear { isActive = true }
    .onDisappear { isActive = false }
  }

  private func expand() {
    guard isContentVisible, !isExpanded else { return }
    Task {
      withAnimation(.easeIn(duration: 0.15)) { isContentVisible = false }
      try? await Task.sleep(nanoseconds: 170_000_000)
      isExpanded = true
      // 等 sheet 换好尺寸再淡入，避免内容跟着边框一起跳。
      try? await Task.sleep(nanoseconds: 60_000_000)
      withAnimation(.easeOut(duration: 0.3)) { isContentVisible = true }
    }
  }

  // MARK: - 快速面板

  private var quickPanel: some View {
    SheetCompactPanel {
      header(titleLineLimit: 6, showsTags: true)

      messageBlock(spacingEdges: .top, spacing: 24)

      VStack(spacing: 18) {
        subscribeButton(focus: $isConfirmFocused)
        Button {
          afterLoaded(expand)
        } label: {
          Text("订阅设置")
            .frame(maxWidth: .infinity)
        }
        // 保存中、只能关掉重开时不再进入设置。
        .disabled(isSaving || viewModel.mustClose)
      }
      .padding(.top, 32)
    }
    .defaultFocus($isConfirmFocused, true)
  }

  // MARK: - 大面板

  /// 左侧栏：媒体区、信息（新增是随设置变化的标签，编辑是固定信息）、居中的当前项说明，主按钮固定在底部。
  /// 右边设置不分组，平铺成两列，一次全部显示、不滚动；改完任意一项往左就能订阅。
  private var expandedPanel: some View {
    SheetSettingsPanel(
      fields: SubscribeSettingField.visibleFields(isTV: viewModel.subscribe.type == "电视剧"),
      focusedField: $focusedField,
      helpText: focusedField?.help
    ) {
      header(titleLineLimit: 10, showsTags: viewModel.isNewSubscription)
    } actions: {
      messageBlock(spacingEdges: .bottom, spacing: 20)
      subscribeButton(focus: $isConfirmFocused)
    } row: { field in
      row(field)
    }
  }

  // MARK: - 共用部分

  /// 片名 + 媒体本身的信息（类型 · 年份）。
  /// 新增订阅下面是这次订阅的设置标签（季、集数属于订阅设置，不和年份混在一行）；
  /// 编辑订阅下面只放固定信息：已有集数、订阅状态，不随正在改的设置变化。
  private func header(titleLineLimit: Int, showsTags: Bool) -> some View {
    let subscribe = viewModel.subscribe
    return VStack(alignment: .leading, spacing: 0) {
      SheetMediaTitle(
        title: MediaIdentifier.normalizedString(subscribe.name) ?? "未知",
        type: subscribe.type, year: subscribe.year, lineLimit: titleLineLimit)
      Group {
        if showsTags {
          tags
        } else {
          savedInfo
        }
      }
      .padding(.top, 16)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 编辑订阅的固定信息，样式同设置标签。
  private var savedInfo: some View {
    SheetInfoTags {
      if let progress = viewModel.progressText {
        SheetInfoTag(systemImage: AppSymbol.progress, text: progress)
      }
      SheetInfoTag(systemImage: viewModel.savedState.systemImage, text: viewModel.savedState.title)
    }
  }

  /// 这次订阅的设置，样式同「添加下载」的信息行：带图标的小字，放不下时换行。
  /// 季、集数、站点、下载器总是显示；洗版、分辨率只有不是默认值时才显示。
  private var tags: some View {
    let subscribe = viewModel.subscribe
    let isTV = subscribe.type == "电视剧"
    return SheetInfoTags {
      if isTV, let season = subscribe.season {
        SheetInfoTag(systemImage: AppSymbol.season, text: "第 \(season) 季")
      }
      if let episodes = viewModel.episodeRangeText {
        SheetInfoTag(systemImage: AppSymbol.episodes, text: episodes)
      }
      if viewModel.subscribeMode != .normal {
        SheetInfoTag(systemImage: AppSymbol.subscribeMode, text: viewModel.subscribeModeTitle)
      }
      if let resolution = viewModel.resolutionTitle {
        SheetInfoTag(systemImage: AppSymbol.resolution, text: resolution)
      }
      SheetInfoTag(
        systemImage: AppSymbol.site, text: viewModel.sitesSummary(empty: "默认站点") { "\($0) 个站点" })
      SheetInfoTag(
        systemImage: AppSymbol.downloader,
        text: MediaIdentifier.normalizedString(subscribe.downloader) ?? "默认下载器")
    }
  }

  /// 出错原因：加载失败优先，其次是订阅时的失败。
  private var statusMessage: String? {
    viewModel.loadErrorMessage ?? viewModel.errorMessage
  }

  private var isBusy: Bool { isSaving || isReloading || viewModel.isLoading || viewModel.isReleasingEpisodeTrial }


  /// 加载失败时先重新加载，真正加载完成后再执行；没失败就直接执行。
  /// 加载中、面板正在放大（内容透明）时按了不做事；焦点不受限制。
  /// 重新加载后发现这部片已经订阅过（新增变成编辑），停下来让用户先看编辑面板，不自动保存。
  private func afterLoaded(_ action: @escaping () -> Void) {
    guard isContentVisible, !viewModel.isLoading else { return }
    guard viewModel.loadErrorMessage != nil else {
      action()
      return
    }
    guard viewModel.canRetryLoad, !isReloading else { return }
    isReloading = true
    Task {
      let canContinue = await viewModel.reloadBeforeContinuing()
      isReloading = false
      guard canContinue, isActive else { return }
      action()
    }
  }

  /// 「重试」做什么：加载失败且能重试时重新加载；订阅（保存）失败或之后启用、搜索失败时再提交一次。
  /// 加载失败但不能重试（需要关掉重开）时没有「重试」。
  private var retryAction: (() -> Void)? {
    if viewModel.loadErrorMessage != nil {
      guard viewModel.canRetryLoad else { return nil }
      return {
        guard isContentVisible, !isReloading else { return }
        isReloading = true
        Task {
          await viewModel.loadData()
          isReloading = false
        }
      }
    }
    guard viewModel.errorMessage != nil else { return nil }
    return {
      guard isContentVisible else { return }
      onSubscribe()
    }
  }

  private func messageBlock(spacingEdges: Edge.Set, spacing: CGFloat) -> some View {
    SheetRetryingMessage(
      message: statusMessage, isBusy: isBusy, retry: retryAction,
      spacingEdges: spacingEdges, spacing: spacing
    ) {
      isConfirmFocused = true
    }
  }

  private func subscribeButton(focus: FocusState<Bool>.Binding?) -> some View {
    let isNew = viewModel.isNewSubscription
    return SheetActionButton(
      title: isNew ? "订阅" : "保存", systemImage: isNew ? AppSymbol.subscribe : AppSymbol.save,
      loadingTitle: viewModel.isLoading ? "加载中" : isNew ? "订阅中" : "保存中",
      isLoading: isBusy, closesSheet: viewModel.mustClose, focus: focus
    ) {
      afterLoaded(onSubscribe)
    }
  }

  // MARK: - 设置行

  @ViewBuilder
  private func row(_ field: SubscribeSettingField) -> some View {
    switch field {
    case .totalEpisode:
      textRow(
        field,
        text: Binding(
          get: { viewModel.totalEpisodeText }, set: { viewModel.totalEpisodeText = $0 }),
        keyboardType: .numberPad)
    case .startEpisode:
      textRow(
        field,
        text: Binding(
          get: { String(viewModel.subscribe.start_episode ?? 0) },
          set: { viewModel.subscribe.start_episode = Int($0) }),
        keyboardType: .numberPad)
    case .subscribeMode:
      SheetPicker(
        title: field.title, selection: $viewModel.subscribeMode,
        options: viewModel.subscribeModeOptions.map { PickerOption(title: $0.title, value: $0.value) })
    case .episodeGroup:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.subscribe.episode_group ?? "" },
          set: { viewModel.subscribe.episode_group = $0.isEmpty ? nil : $0 }),
        options: EpisodeGroupPickerOptions.make(viewModel.episodeGroups, defaultSeasons: nil))
    case .season:
      SheetPicker(
        title: field.title,
        selection: Binding(
          get: { viewModel.subscribe.season.map(String.init) ?? "" },
          set: { viewModel.subscribe.season = Int($0) }),
        options: [PickerOption(title: "全部", value: "")]
          + viewModel.seasonOptions.map { PickerOption(title: "第 \($0) 季", value: String($0)) })
    case .mediaCategory:
      textRow(field, text: $viewModel.mediaCategoryText)
    case .quality, .resolution, .effect, .sites, .downloader, .savePath, .searchImdb, .keyword, .include,
      .exclude, .filterGroups, .customWords:
      SubscribeRuleFieldRow(field: field, subscribe: $viewModel.subscribe, options: viewModel.ruleOptions)
    }
  }

  private func textRow(
    _ field: SubscribeSettingField, text: Binding<String>,
    keyboardType: UIKeyboardType = .default
  ) -> some View {
    SheetInlineTextField(title: field.title, text: text, keyboardType: keyboardType)
  }
}

/// 订阅大面板里的一项设置：标题、说明和出现顺序。
/// 不分组：以后加新设置项只是多一行，两列自动重新平分。
enum SubscribeSettingField: Hashable, CaseIterable {
  case totalEpisode, startEpisode
  case quality, resolution, effect
  case sites, downloader, savePath
  case subscribeMode, searchImdb
  case keyword, include, exclude, filterGroups
  case episodeGroup, season, mediaCategory, customWords

  /// 只对电视剧有意义的设置，其他类型不显示（与原订阅 Sheet 一致）。
  var isTVOnly: Bool {
    switch self {
    case .totalEpisode, .startEpisode, .episodeGroup, .season: true
    default: false
    }
  }

  static func visibleFields(isTV: Bool) -> [SubscribeSettingField] {
    allCases.filter { isTV || !$0.isTVOnly }
  }

  var title: String {
    switch self {
    case .totalEpisode: "总集数"
    case .startEpisode: "开始集数"
    case .quality: "质量"
    case .resolution: "分辨率"
    case .effect: "特效"
    case .sites: "站点"
    case .downloader: "下载器"
    case .savePath: "保存路径"
    case .subscribeMode: "订阅方式"
    case .searchImdb: "使用 IMDB 搜索"
    case .keyword: "搜索关键词"
    case .include: "包含"
    case .exclude: "排除"
    case .filterGroups: "优先级规则组"
    case .episodeGroup: "剧集组"
    case .season: "指定季"
    case .mediaCategory: "自定义类别"
    case .customWords: "自定义识别词"
    }
  }

  /// 当前项的说明，最多两行（左栏宽度下约 34 个字）。
  /// 写给家里所有人看，不提后台设置里的概念；含义已对照 MoviePilot 后端与 Web。
  var help: String {
    switch self {
    case .totalEpisode: "本季的总集数，全部下载完成后订阅结束。"
    case .startEpisode: "从此集开始订阅，之前的剧集不会下载。"
    case .quality: "仅下载指定质量的资源，如 WEB-DL、蓝光。"
    case .resolution: "仅下载指定分辨率的资源，如 4K、1080P。"
    case .effect: "仅下载带指定画面效果的资源，如 HDR、杜比视界。"
    case .sites: "仅在所选站点中搜索资源；不选则使用默认站点。"
    case .downloader: "匹配到资源后使用的下载器。"
    case .savePath: "资源的保存目录；自动表示按默认规则存放。"
    case .subscribeMode: "普通订阅完成即结束；洗版会持续下载更优版本；全集洗版仅下载整季资源。"
    case .searchImdb: "使用 IMDB 编号搜索，适合片名容易混淆的影片。"
    case .keyword: "替代片名用于搜索资源；留空则按片名搜索。"
    case .include: "资源名称须包含这些关键字。"
    case .exclude: "资源名称包含这些关键字时跳过。"
    case .filterGroups: "按规则筛选资源，不符合的将被跳过；不选则使用默认规则。"
    case .episodeGroup: "按指定剧集组划分季与集，用于播出顺序不一致的剧集。"
    case .season: "订阅的季，一般无需修改。"
    case .mediaCategory: "整理时使用的类别名称；留空则自动识别。"
    case .customWords: "仅对此订阅生效的识别词，用于纠正识别结果。"
    }
  }
}
