import SwiftUI
import UIKit

struct SystemView: View {
  private static let pageAnimationDuration: TimeInterval = 0.42
  private static let topAnchorID = "SystemSettingsTopAnchor"
  private static let listWidth: CGFloat = 780
  private static let previewWidth: CGFloat = 600
  private static let pageSpacing: CGFloat = 44
  private static let columnSpacing: CGFloat = 210
  private static let horizontalPadding: CGFloat = 240
  private static let previewTopPadding: CGFloat = 160
  private static let contentBottomPadding: CGFloat = 80
  private static let pageEdgeFadeWidth: CGFloat = 44
  private static let pageMaskHeight: CGFloat = 1400
  private static let pageMaskTopOverflow: CGFloat = 160

  private let isSelected: Bool

  @Environment(\.topShelfPresentation) private var topShelfPresentation
  @StateObject private var viewModel: SystemViewModel
  @StateObject private var recommendViewModel: RecommendViewModel
  @StateObject private var topShelfExplore: ExploreViewModel
  @StateObject private var exploreContentSources: ExploreViewModel
  @StateObject private var exploreDefaultDraft: ExploreViewModel
  @StateObject private var logViewerViewModel: LogViewerViewModel
  @StateObject private var mediaSources = MediaSourceOptionsModel()
  @ObservedObject private var apiService: APIService
  private var memoryOptimization: MemoryOptimizationSettings
  @EnvironmentObject private var topShelfManager: TopShelfManager
  @State private var showAppInfo = false
  @State private var selectedDetail: SystemSettingsDetailItem?
  @State private var updateNotice: AppChangelogEntry?
  @State private var showLogoutConfirmation = false
  @State private var showsEpisodeTrialRule = false
  @State private var isOrderingRecommendation = false
  @State private var isOrderingExploreContent = false
  @State private var route: [SystemSettingsPage] = []
  @State private var displayedRoute: [SystemSettingsPage] = []
  @State private var pageOffsetDepth = 0
  @State private var navigationRevision = 0
  @FocusState private var focusedItem: SystemSettingsFocus?

  init(isSelected: Bool = true, apiService: APIService = .shared, initialPage: SystemSettingsPage = .root) {
    self.isSelected = isSelected
    self.apiService = apiService
    memoryOptimization = MemoryOptimizationSettings(apiService: apiService)
    _topShelfExplore = StateObject(wrappedValue: ExploreViewModel(apiService: apiService, loadsResults: false, sourcePolicy: .topShelf))
    _exploreContentSources = StateObject(wrappedValue: ExploreViewModel(apiService: apiService, loadsResults: false, sourcePolicy: .contentSettings))
    _exploreDefaultDraft = StateObject(wrappedValue: ExploreViewModel(apiService: apiService, loadsResults: false, sourcePolicy: .defaultSettings))
    _viewModel = StateObject(wrappedValue: SystemViewModel(apiService: apiService))
    _recommendViewModel = StateObject(wrappedValue: RecommendViewModel(selectShelf: false, apiService: apiService))
    _logViewerViewModel = StateObject(wrappedValue: LogViewerViewModel())
    let pages: [SystemSettingsPage] = initialPage == .root ? [] : [initialPage]
    _route = State(initialValue: pages)
    _displayedRoute = State(initialValue: pages)
    _pageOffsetDepth = State(initialValue: pages.count)
  }

  private var canConfigureSubscriptions: Bool {
    apiService.canAccess(.subscribe)
  }

  private var canConfigureSearch: Bool {
    apiService.canAccess(.search)
  }

  private var canConfigureRecommendations: Bool {
    apiService.canAccess(.discovery)
  }

  /// 应用内播放需要读取媒体服务器配置，只有管理员可用。
  private var canConfigurePlayback: Bool {
    apiService.canRequestSuperUserEndpoints
  }

  private var canConfigureCustomFilters: Bool {
    apiService.canRequestSuperUserEndpoints
  }

  /// 试看订阅规则只在试看可用时显示：管理员，且后端版本支持（见 `EpisodeTrialAvailability`）。
  private var canConfigureEpisodeTrial: Bool {
    canConfigureSubscriptions
      && EpisodeTrialAvailability.isAvailable(
        canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
        backendVersion: apiService.settings?.BACKEND_VERSION)
  }

  private var selectedLogRecordBinding: Binding<LogRecord?> {
    Binding(
      get: {
        if case .log(let record) = selectedDetail { return record }
        return nil
      },
      set: { record in
        if let record {
          selectedDetail = .log(record)
        } else if case .log = selectedDetail {
          selectedDetail = nil
        }
      }
    )
  }

  var body: some View {
    let activePage = route.last ?? .root
    let pages = [.root] + displayedRoute

    HStack(alignment: .top, spacing: Self.columnSpacing) {
      preview(for: activePage, focusedItem: focusedItem)
        .frame(width: Self.previewWidth)
        .padding(.top, Self.previewTopPadding)
        .offset(x: 50, y: -40)

      HStack(alignment: .top, spacing: Self.pageSpacing) {
        ForEach(pages, id: \.self) { page in
          slidingPage(page, isActive: page == activePage)
        }
      }
      .frame(width: Self.listWidth, alignment: .topLeading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
      .offset(x: -CGFloat(pageOffsetDepth) * (Self.listWidth + Self.pageSpacing))
      .mask(alignment: .topLeading) {
        HStack(spacing: 0) {
          LinearGradient(
            colors: [.clear, .black],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: Self.pageEdgeFadeWidth)

          Rectangle()
            .frame(width: Self.listWidth)

          LinearGradient(
            colors: [.black, .clear],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: Self.pageEdgeFadeWidth)
        }
        .frame(height: Self.pageMaskHeight)
        .offset(x: -Self.pageEdgeFadeWidth, y: -Self.pageMaskTopOverflow)
      }
    }
    .padding(.horizontal, Self.horizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea(.container, edges: .bottom)
    .onAppear {
      displayedRoute = route
      pageOffsetDepth = route.count
      viewModel.checkKeychainStatus()
      refreshFilterRulesForEntryIfNeeded()
      presentUpdateNoticeIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .imageNavigationPresentationWillReset, object: apiService)) { _ in
      showAppInfo = false
      selectedDetail = nil
      updateNotice = nil
      showLogoutConfirmation = false
      showsEpisodeTrialRule = false
    }
    .onChange(of: isSelected) { _, selected in
      guard selected else { return }
      refreshFilterRulesForEntryIfNeeded()
      presentUpdateNoticeIfNeeded()
    }
    .task {
      await viewModel.loadSystemInfo()
      await viewModel.loadSites()
    }
    .sheet(isPresented: $showAppInfo) {
      appInfoSheet
    }
    .sheet(isPresented: $showsEpisodeTrialRule) {
      EpisodeTrialRuleSheet(service: apiService.sessionScope.episodeTrial, apiService: apiService)
    }
    .sheet(item: $selectedDetail) { detail in
      // 更新历史和日志详情共用这一个 item sheet，写法与版本更新历史相同。
      switch detail {
      case .changelog(let entry):
        changelogDetailSheet(entry)
      case .license(let notice):
        ThirdPartyLicenseSheet(notice: notice).equatable()
      case .log(let record):
        LogRecordDetailSheet(record: record)
      }
    }
    .alert(
      updateNotice.map { "已更新到 \($0.version)" } ?? "更新提示",
      isPresented: Binding(
        get: { updateNotice != nil },
        set: { if !$0, updateNotice != nil { updateNotice = nil } }),
      presenting: updateNotice
    ) { entry in
      Button("知道了", role: .cancel) {
        AppChangelog.markPresented(entry)
        updateNotice = nil
      }
    } message: { entry in
      Text(AppChangelog.updateNoticeMessage(for: entry)).font(.callout)
    }
  }

  private func preview(for page: SystemSettingsPage, focusedItem: SystemSettingsFocus?) -> some View {
    VStack(spacing: 58) {
      Image("SettingsLogoGlass")
        .resizable()
        .scaledToFit()
        .frame(width: 660, height: 440)

      if let description = previewDescription(for: page, focusedItem: focusedItem) {
        Text(description)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(5)
          .frame(maxWidth: 600)
      }
    }
  }

  private func slidingPage(_ page: SystemSettingsPage, isActive: Bool) -> some View {
    pageView(page, isActive: isActive)
      .frame(width: Self.listWidth, alignment: .top)
      .frame(maxHeight: .infinity, alignment: .top)
      .allowsHitTesting(isActive)
      .systemSettingsExitCommand(
        isEnabled: !topShelfPresentation.blocksInteraction && isSelected && isActive && page != .root,
        perform: pop
      )
  }

  private func pageView(_ page: SystemSettingsPage, isActive: Bool) -> some View {
    ScrollViewReader { scrollProxy in
      Group {
        if page == .logs {
          // 日志页自己用 ScrollView + LazyVStack。再包进外层 VStack 会让卡片一次性全部实例化。
          LogViewerView(
            viewModel: logViewerViewModel,
            focusedItem: $focusedItem,
            selectedRecord: selectedLogRecordBinding
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
          ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
              Color.clear
                .frame(height: 1)
                .id(Self.topAnchorID)

              switch page {
              case .root:
                rootPage
              case .connection:
                connectionPage
              case .mediaSourceSelection:
                if canConfigureRecommendations {
                  mediaSourceSelectionPage
                }
              case .memoryOptimization:
                memoryOptimizationPage
              case .siteSelection:
                if canConfigureSearch {
                  siteSelectionPage
                }
              case .subtitleSiteSelection:
                if canConfigureSearch {
                  subtitleSiteSelectionPage
                }
              case .hardFilter:
                if canConfigureCustomFilters {
                  filterPage(
                    selectedRuleId: viewModel.selectedHardFilterRuleId,
                    onSelect: { viewModel.selectedHardFilterRuleId = $0 }
                  )
                }
              case .softFilter:
                if canConfigureCustomFilters {
                  filterPage(
                    selectedRuleId: viewModel.selectedSoftFilterRuleId,
                    onSelect: { viewModel.selectedSoftFilterRuleId = $0 }
                  )
                }
              case .topShelfSelection:
                if canConfigureRecommendations { topShelfSelectionPage }
              case .topShelfRecommendations:
                if canConfigureRecommendations { topShelfRecommendationsPage }
              case .topShelfExplore:
                if canConfigureRecommendations { topShelfExplorePage }
              case .topShelfExploreSources:
                if canConfigureRecommendations { topShelfExploreSourcesPage }
              case .topShelfExploreField(let id):
                if canConfigureRecommendations { topShelfExploreFieldPage(id) }
              case .recommendation:
                if canConfigureRecommendations {
                  recommendationPage
                }
              case .exploreContent:
                if canConfigureRecommendations { exploreContentPage }
              case .exploreDefault:
                if canConfigureRecommendations { exploreDefaultPage }
              case .exploreDefaultSources:
                if canConfigureRecommendations { exploreDefaultSourcesPage }
              case .exploreDefaultField(let id):
                if canConfigureRecommendations { exploreDefaultFieldPage(id) }
              case .playback:
                if canConfigurePlayback {
                  playbackPage
                }
              case .changelog:
                changelogPage
              case .licenses:
                licensesPage
              case .logs:
                EmptyView()
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, Self.contentBottomPadding)
          }
        }
      }
      .scrollClipDisabled()
      .background(
        SystemSettingsRootBackObserver(
          // Sheet / Alert 呈现期间禁用 Menu 手势：否则按 Menu 关闭弹层时
          // 会同时触发 scrollTo(top)，随后焦点恢复又滚回原行，形成"先上滑再下滑"。
          isEnabled: !topShelfPresentation.blocksInteraction && isSelected && isActive && page == .root
            && !showAppInfo && updateNotice == nil && selectedDetail == nil
            && !showLogoutConfirmation && !showsEpisodeTrialRule,
          onExitPress: {
            focusedItem = nil
            withAnimation(.easeInOut(duration: 0.24)) {
              scrollProxy.scrollTo(Self.topAnchorID, anchor: .top)
            }
          }
        )
      )
    }
  }

  private var rootPage: some View {
    VStack(spacing: 38) {
      if canConfigureRecommendations {
        topShelfSettings
      }

      if canConfigureSubscriptions {
        section("订阅") {
          Toggle(
            "新增订阅后立即搜索",
            isOn: Binding(
              get: { viewModel.autoSearchNewSubscriptions },
              set: { viewModel.autoSearchNewSubscriptions = $0 }
            )
          )
          .font(.body.bold())
          .focused($focusedItem, equals: .autoSearch)

          if canConfigureEpisodeTrial {
            Button {
              showsEpisodeTrialRule = true
            } label: {
              EpisodeTrialRuleSummary(service: apiService.sessionScope.episodeTrial) {
                row("试看订阅规则", value: $0)
              }
            }
            .focused($focusedItem, equals: .episodeTrialRule)
          }
        }
      }

      if canConfigureRecommendations {
        section("推荐页") {
          Button {
            isOrderingRecommendation = false
            push(.recommendation)
          } label: {
            row("内容与顺序", showsDisclosure: true)
          }
          .focused($focusedItem, equals: .recommendation)
        }

        section("探索页") {
          Button {
            isOrderingExploreContent = false
            push(.exploreContent)
          } label: {
            row("内容与顺序", showsDisclosure: true)
          }
          .focused($focusedItem, equals: .exploreContent)
          Button {
            exploreDefaultDraft.reloadLocalConfig()
            exploreDefaultDraft.restoreConfiguration(
              ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration())
            push(.exploreDefault)
          } label: {
            row(
              "默认配置",
              value: ExploreViewModel.storedDefaultConfiguration()?.selectedSource.title ?? "TheMovieDb",
              showsDisclosure: true)
          }
          .focused($focusedItem, equals: .exploreDefault)
        }
      }

      if canConfigureRecommendations {
        section("聚合搜索") {
          Button {
            push(.mediaSourceSelection)
          } label: {
            row("默认搜索来源", value: mediaSourceButtonLabel, showsDisclosure: true)
          }
          .focused($focusedItem, equals: .mediaSourceSelection)
        }
      }

      if canConfigurePlayback {
        section("播放") {
          Button {
            viewModel.reloadPlaybackSettings()
            push(.playback)
          } label: {
            row("播放设置", value: playbackSummary, showsDisclosure: true)
          }
          .focused($focusedItem, equals: .playbackSettings)
        }
      }

      section("详情页") {
        Toggle(
          "预加载 TMDB 详情",
          isOn: Binding(
            get: { viewModel.preloadTMDBDetails },
            set: { viewModel.preloadTMDBDetails = $0 }
          )
        )
        .font(.body.bold())
        .focused($focusedItem, equals: .preloadTMDBDetails)

        Toggle(
          "等待背景海报加载",
          isOn: Binding(
            get: { viewModel.waitMediaDetailBackgroundImage },
            set: { viewModel.waitMediaDetailBackgroundImage = $0 }
          )
        )
        .font(.body.bold())
        .focused($focusedItem, equals: .waitBackgroundImage)
      }

      section("性能") {
        Button {
          push(.memoryOptimization)
        } label: {
          row(
            "内存优化",
            value: memoryOptimizationTitle(for: memoryOptimization.mode),
            showsDisclosure: true
          )
        }
        .focused($focusedItem, equals: .memoryOptimization)
      }

      if canConfigureSearch {
        section("资源搜索") {
          Button {
            push(.siteSelection)
          } label: {
            row("默认搜索站点", value: siteButtonLabel, showsDisclosure: true)
          }
          .focused($focusedItem, equals: .siteSelection)

          if canConfigureCustomFilters {
            Button {
              push(.hardFilter)
            } label: {
              row("硬过滤", value: selectedHardFilterTitle, showsDisclosure: true)
            }
            .focused($focusedItem, equals: .hardFilter)

            Button {
              push(.softFilter)
            } label: {
              row("软过滤", value: selectedSoftFilterTitle, showsDisclosure: true)
            }
            .focused($focusedItem, equals: .softFilter)

            if viewModel.isLoadingRules {
              row("规则状态", value: "正在加载")
                .foregroundStyle(.secondary)
            } else if viewModel.rulesLoadFailed {
              Button {
                Task { await viewModel.loadCustomFilterRules() }
              } label: {
                row("规则状态", value: "加载失败，点击重试")
                  .foregroundStyle(.secondary)
              }
            } else if viewModel.customFilterRules.isEmpty {
              row("规则状态", value: "暂无自定义过滤规则")
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if canConfigureSearch {
        section("字幕搜索") {
          Button {
            push(.subtitleSiteSelection)
          } label: {
            row("默认搜索站点", value: subtitleSiteButtonLabel, showsDisclosure: true)
          }
          .focused($focusedItem, equals: .subtitleSiteSelection)
        }
      }

      section("连接与APP信息") {
        Button {
          push(.connection)
        } label: {
          row("连接", value: viewModel.storageDescription, showsDisclosure: true)
        }
        .focused($focusedItem, equals: .connection)

        Button {
          showAppInfo = true
        } label: {
          row("APP 信息", value: viewModel.appVersion)
        }
        .focused($focusedItem, equals: .appInfo)

        Button {
          push(.changelog)
        } label: {
          row("版本更新历史", showsDisclosure: true)
        }
        .focused($focusedItem, equals: .changelog)

        Button {
          push(.licenses)
        } label: {
          row("第三方软件许可", showsDisclosure: true)
        }
        .focused($focusedItem, equals: .licenses)

        Button {
          push(.logs)
        } label: {
          row("查看日志", showsDisclosure: true)
        }
        .focused($focusedItem, equals: .logs)
      }
    }
  }

  private var connectionPage: some View {
    VStack(spacing: 38) {
      section("登录凭据") {
        Button {
          Task {
            await viewModel.relogin()
          }
        } label: {
          row(
            "刷新登录凭据",
            value: viewModel.isRefreshing ? "刷新中" : nil,
            showsProgress: viewModel.isRefreshing
          )
        }
        .focused($focusedItem, equals: .relogin)
        // 刷新中保持可聚焦：tvOS 上聚焦元素变 disabled 会导致焦点跳走并触发滚动；
        // 防重入由 SystemViewModel.relogin() 内的 guard !isRefreshing 保证。

        Button {
          showLogoutConfirmation = true
        } label: {
          row("退出登录")
        }
        .focused($focusedItem, equals: .logout)
      }

      VStack(alignment: .leading, spacing: 30) {
        Text("登录信息")
          .font(.callout)
          .foregroundStyle(.secondary)

        VStack(spacing: 24) {
          staticRow("登录状态", viewModel.storageDescription)
          staticRow("服务器", viewModel.serverURL.isEmpty ? "未连接" : viewModel.serverURL)
          staticRow("登录用户", viewModel.username.isEmpty ? "未知" : viewModel.username)
          staticRow("MoviePilot 版本", viewModel.backendVersion ?? "未知")

          if let refreshMessage = viewModel.refreshMessage {
            staticRow("最近状态", refreshMessage)
          }
        }

        Text(
          "密码安全提示：请勿将 MoviePilot 密码与其他服务共用。Apple 钥匙串不可用时，本 App 会自动降级为明文持久化密码；即使 Apple TV 环境相对封闭，仍存在密码泄露风险。"
        )
        .font(.body.bold())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, 16)
    }
    .alert("退出登录", isPresented: $showLogoutConfirmation) {
      Button("取消", role: .cancel) {}
      Button("确认退出登录", role: .destructive) {
        viewModel.logout()
      }
    } message: {
      Text("确定要退出当前账号吗？")
    }
  }

  private var appInfoSheet: some View {
    VStack(alignment: .leading) {
      Text("MoviePilot TV APP")
        .font(.headline)
        .lineLimit(1)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 42)

      Divider()
        .padding(.horizontal, 46)
        .padding(.top, 14)

      VStack(spacing: 32) {
        staticRow("作者", "CHANTXU64")
        staticRow("版本", viewModel.appVersion)
        staticRow("最新兼容 MoviePilot 版本", viewModel.latestCompatibleMoviePilotVersion)
        staticRow("GitHub", "CHANTXU64/MoviePilot-TV")
        staticRow("分发协议", "CC0 1.0 Universal")
      }
      .padding(.horizontal, 46)
      .padding(.top, 20)
      .padding(.bottom, 46)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var changelogPage: some View {
    section(nil) {
      ForEach(AppChangelog.entries) { entry in
        Button {
          selectedDetail = .changelog(entry)
        } label: {
          row(
            entry.version,
            value: "\(entry.releaseDate) · MoviePilot \(entry.compatibleMoviePilotVersion)",
            showsDisclosure: true
          )
        }
        .focused($focusedItem, equals: .changelogVersion(entry.version))
      }
    }
  }

  private var licensesPage: some View {
    section(nil) {
      ForEach(ThirdPartyNotices.all) { notice in
        Button {
          selectedDetail = .license(notice)
        } label: {
          row(notice.name, value: notice.license, showsDisclosure: true)
        }
        .focused($focusedItem, equals: .license(notice.id))
      }
    }
  }

  /// 第三方许可详情的正文：说明在前，许可原文按原样分段接在后面，一个组件有多份原文时各带标题。
  static func licenseBlocks(_ notice: ThirdPartyNotice, bundle: Bundle = .main) -> [ReadingBlock] {
    var blocks = [ReadingBlock("许可：\(notice.license)", style: .secondary)]
    blocks += notice.details.map { ReadingBlock($0) }
    for text in notice.texts {
      blocks.append(.divider)
      if let title = text.title { blocks.append(ReadingBlock(title, style: .heading)) }
      guard let content = ThirdPartyNotices.text(text.resource, in: bundle) else {
        blocks.append(ReadingBlock("许可原文读取失败", style: .secondary))
        continue
      }
      blocks += ReadingSheetLayout.paragraphs(content).map { ReadingBlock($0, style: .secondary) }
    }
    return blocks
  }

  private func changelogDetailSheet(_ entry: AppChangelogEntry) -> some View {
    ReadingSheet(title: entry.version, blocks: Self.changelogBlocks(entry))
  }

  /// 更新历史详情的正文：发布日期在最前，各小节为「小节标题 + • 条目」。
  static func changelogBlocks(_ entry: AppChangelogEntry) -> [ReadingBlock] {
    var blocks = [ReadingBlock(entry.releaseDate, style: .secondary)]
    let sections: [(String, [String])] = [
      ("更新内容", entry.highlights),
      ("新增功能", entry.updates),
      ("修复", entry.fixes),
      ("优化", entry.optimizations),
    ]
    for (title, items) in sections where !items.isEmpty {
      blocks.append(ReadingBlock(title, style: .heading))
      blocks += items.map { ReadingBlock("• \($0)", style: .secondary) }
    }
    return blocks
  }

  private var topShelfSettings: some View {
    section("Apple TV 主屏") {
      Button { push(.topShelfSelection) } label: {
        row("主屏显示内容", value: topShelfManager.selection?.title ?? "不显示", showsDisclosure: true)
      }
      .focused($focusedItem, equals: .topShelfRecommendation)
    }
  }

  private var topShelfSelectionPage: some View {
    section(nil) {
      Button { topShelfManager.select(nil) } label: {
        row("不显示", value: topShelfManager.selection == nil ? "已选择" : nil)
      }
      .focused($focusedItem, equals: .topShelfDisabled)
      Button { push(.topShelfRecommendations) } label: {
        row("推荐", value: topShelfManager.selection?.exploration == nil ? topShelfManager.selection?.title : nil,
          showsDisclosure: true)
      }
      .focused($focusedItem, equals: .topShelfModeRecommendation)
      Button {
        topShelfExplore.restoreConfiguration(topShelfManager.savedExploration ?? ExploreConfiguration())
        push(.topShelfExplore)
      } label: {
        row("探索", value: topShelfManager.selection?.exploration?.selectedSource.title, showsDisclosure: true)
      }
      .focused($focusedItem, equals: .topShelfModeExplore)
    }
  }

  private var topShelfRecommendationsPage: some View {
    section(nil) {
      ForEach(topShelfSelectionOptions) { selection in
        Button { topShelfManager.select(selection) } label: {
          row(selection.title, value: topShelfManager.selection == selection ? "已选择" : nil)
        }
        .focused($focusedItem, equals: .topShelfSource(selection.shelfID))
      }
    }
    .task { await recommendViewModel.refreshSources(selectShelf: false) }
  }

  private var topShelfExplorePage: some View {
    ExploreConfigurationEditorPage(
      viewModel: topShelfExplore,
      focusedItem: $focusedItem,
      sourceFocus: .topShelfExploreSource,
      fieldFocus: { .topShelfExploreField($0) },
      resetFocus: .topShelfExploreReset,
      factoryResetFocus: nil,
      saveFocus: .topShelfExploreSave,
      pushSources: { push(.topShelfExploreSources) },
      pushField: { push(.topShelfExploreField($0)) },
      onResetFilters: {
        topShelfExplore.restoreConfiguration(ExploreConfiguration(source: topShelfExplore.selectedSource))
      },
      onFactoryReset: nil,
      onSave: {
        topShelfManager.select(TopShelfSelection(exploration: topShelfExplore.configuration))
        pop()
      },
      saveDisabled: topShelfExplore.selectedSource == .subscriptionShare && !canConfigureSubscriptions
    )
  }

  private var topShelfExploreSourcesPage: some View {
    ExploreConfigurationSourceListPage(
      viewModel: topShelfExplore,
      focusedItem: $focusedItem,
      optionFocus: { .topShelfExploreSourceOption($0) },
      isSourceDisabled: { $0 == .subscriptionShare && !canConfigureSubscriptions },
      sourceNote: { _ in nil },
      onSelect: { source in
        if topShelfExplore.selectedSource.id != source.id {
          topShelfExplore.restoreConfiguration(ExploreConfiguration(source: source))
        }
        pop()
      }
    )
    .task { await topShelfExplore.refreshSources() }
  }

  @ViewBuilder
  private func topShelfExploreFieldPage(_ id: String) -> some View {
    if let field = topShelfExplore.settingsFields.first(where: { $0.id == id }) {
      ExploreConfigurationFieldPage(
        field: field,
        focusedItem: $focusedItem,
        optionFocus: { .topShelfExploreOption($0) },
        onSingleSelect: { pop() }
      )
    }
  }

  private var exploreDefaultPage: some View {
    ExploreConfigurationEditorPage(
      viewModel: exploreDefaultDraft,
      focusedItem: $focusedItem,
      sourceFocus: .exploreDefaultSource,
      fieldFocus: { .exploreDefaultField($0) },
      resetFocus: .exploreDefaultReset,
      factoryResetFocus: .exploreDefaultFactoryReset,
      saveFocus: .exploreDefaultSave,
      pushSources: { push(.exploreDefaultSources) },
      pushField: { push(.exploreDefaultField($0)) },
      onResetFilters: {
        exploreDefaultDraft.restoreConfiguration(ExploreConfiguration(source: exploreDefaultDraft.selectedSource))
      },
      onFactoryReset: {
        exploreDefaultDraft.restoreConfiguration(ExploreConfiguration())
      },
      onSave: {
        ExploreViewModel.saveDefaultConfiguration(exploreDefaultDraft.configuration)
        pop()
      },
      saveDisabled: exploreDefaultDraft.selectedSource == .subscriptionShare && !canConfigureSubscriptions
    )
  }

  private var exploreDefaultSourcesPage: some View {
    ExploreConfigurationSourceListPage(
      viewModel: exploreDefaultDraft,
      focusedItem: $focusedItem,
      optionFocus: { .exploreDefaultSourceOption($0) },
      isSourceDisabled: { $0 == .subscriptionShare && !canConfigureSubscriptions },
      sourceNote: { exploreDefaultDraft.sourceVisibility[$0.id] == false ? "已隐藏" : nil },
      onSelect: { source in
        if exploreDefaultDraft.selectedSource.id != source.id {
          exploreDefaultDraft.restoreConfiguration(ExploreConfiguration(source: source))
        }
        pop()
      }
    )
    .task { await exploreDefaultDraft.refreshSources() }
  }

  @ViewBuilder
  private func exploreDefaultFieldPage(_ id: String) -> some View {
    if let field = exploreDefaultDraft.settingsFields.first(where: { $0.id == id }) {
      ExploreConfigurationFieldPage(
        field: field,
        focusedItem: $focusedItem,
        optionFocus: { .exploreDefaultOption($0) },
        onSingleSelect: { pop() }
      )
    }
  }

  private var recommendationPage: some View {
    section(nil) {
      Button {
        isOrderingRecommendation.toggle()
      } label: {
        row(isOrderingRecommendation ? "完成" : "调整顺序")
      }
      .focused($focusedItem, equals: .recommendationOrdering)
      OrderableContentList(
        items: recommendViewModel.orderedShelves,
        title: { $0.title },
        isEnabled: { shelf in recommendViewModel.enableConfig[shelf.id] == true },
        isOrdering: isOrderingRecommendation,
        onToggle: { shelf, enabled in
          var config = recommendViewModel.enableConfig
          config[shelf.id] = enabled
          recommendViewModel.saveEnableConfig(config)
        },
        onMove: { shelf, direction in
          var order = recommendViewModel.orderedShelves.map(\.id)
          guard let index = order.firstIndex(of: shelf.id) else { return }
          let target = direction == .up ? index - 1 : index + 1
          guard target >= 0, target < order.count else { return }
          order.swapAt(index, target)
          recommendViewModel.saveShelfOrder(order)
        },
        focus: { shelf, role in
          switch role {
          case .toggle: return .recommendationShelf(shelf.id)
          case .moveUp: return .recommendationShelfMove(shelf.id, .up)
          case .moveDown: return .recommendationShelfMove(shelf.id, .down)
          }
        },
        focusedItem: $focusedItem
      )
      Button {
        recommendViewModel.resetShelfOrder()
      } label: {
        row("恢复默认顺序")
      }
      .focused($focusedItem, equals: .recommendationResetOrder)
    }
    .task {
      await recommendViewModel.refreshSources(selectShelf: false)
    }
  }

  private var exploreContentPage: some View {
    section(nil) {
      Button {
        isOrderingExploreContent.toggle()
      } label: {
        row(isOrderingExploreContent ? "完成" : "调整顺序")
      }
      .focused($focusedItem, equals: .exploreContentOrdering)
      OrderableContentList(
        items: exploreContentSources.availableSources,
        title: { $0.title },
        isEnabled: { exploreContentSources.sourceVisibility[$0.id] != false },
        isOrdering: isOrderingExploreContent,
        onToggle: { source, enabled in
          var config = exploreContentSources.sourceVisibility
          config[source.id] = enabled
          exploreContentSources.saveSourceVisibility(config)
        },
        onMove: { source, direction in
          var order = exploreContentSources.availableSources.map(\.id)
          guard let index = order.firstIndex(of: source.id) else { return }
          let target = direction == .up ? index - 1 : index + 1
          guard target >= 0, target < order.count else { return }
          order.swapAt(index, target)
          exploreContentSources.saveSourceOrder(order)
        },
        focus: { source, role in
          switch role {
          case .toggle: return .exploreSource(source.id)
          case .moveUp: return .exploreSourceMove(source.id, .up)
          case .moveDown: return .exploreSourceMove(source.id, .down)
          }
        },
        focusedItem: $focusedItem
      )
      Button {
        exploreContentSources.resetSourceOrder()
      } label: {
        row("恢复默认顺序")
      }
      .focused($focusedItem, equals: .exploreContentResetOrder)
    }
    .task {
      await exploreContentSources.refreshSources()
    }
  }

  private var topShelfSelectionOptions: [TopShelfSelection] {
    TopShelfSelectionPolicy.options(
      saved: topShelfManager.selection,
      shelves: recommendViewModel.shelves
    )
  }

  private var siteSelectionPage: some View {
    siteChoicePage(
      selected: viewModel.defaultSearchSites,
      selectAll: { viewModel.defaultSearchSites = [] },
      toggle: toggleDefaultSearchSite,
      allFocus: .allSites,
      siteFocus: { .site($0) }
    )
  }

  private var subtitleSiteSelectionPage: some View {
    siteChoicePage(
      selected: viewModel.defaultSubtitleSearchSites,
      selectAll: { viewModel.defaultSubtitleSearchSites = [] },
      toggle: toggleDefaultSubtitleSearchSite,
      allFocus: .allSubtitleSites,
      siteFocus: { .subtitleSite($0) }
    )
  }

  private func siteChoicePage(
    selected: Set<Int>,
    selectAll: @escaping () -> Void,
    toggle: @escaping (Int) -> Void,
    allFocus: SystemSettingsFocus,
    siteFocus: @escaping (Int) -> SystemSettingsFocus
  ) -> some View {
    section(nil) {
      Button(action: selectAll) {
        row("全部站点", value: selected.isEmpty ? "已选择" : nil)
      }
      .focused($focusedItem, equals: allFocus)

      if viewModel.isLoadingSites {
        row("站点状态", value: "正在加载")
          .foregroundStyle(.secondary)
      } else if let siteLoadError = viewModel.siteLoadError {
        Button {
          Task { await viewModel.loadSites() }
        } label: {
          row("站点状态", value: siteLoadError)
            .foregroundStyle(.red)
        }
      } else if viewModel.availableSites.isEmpty {
        row("站点状态", value: "暂无站点")
          .foregroundStyle(.secondary)
      }

      ForEach(viewModel.availableSites, id: \.id) { site in
        Button {
          toggle(site.id)
        } label: {
          row(site.name, value: selected.contains(site.id) ? "已选择" : nil)
        }
        .focused($focusedItem, equals: siteFocus(site.id))
      }
    }
  }

  private var mediaSourceSelectionPage: some View {
    section(nil) {
      Button {
        viewModel.defaultMediaSearchSource = nil
      } label: {
        row(
          "默认",
          value: viewModel.defaultMediaSearchSource == nil ? "已选择" : nil
        )
      }
      .focused($focusedItem, equals: .defaultMediaSource)

      ForEach(mediaSources.options(including: viewModel.defaultMediaSearchSource)) { option in
        Button {
          viewModel.defaultMediaSearchSource = option.source
        } label: {
          row(
            option.title,
            value: viewModel.defaultMediaSearchSource == option.source ? "已选择" : nil
          )
        }
        .focused($focusedItem, equals: .mediaSource(option.source))
      }
    }
    .task { await mediaSources.load() }
  }

  private func filterPage(
    selectedRuleId: String?,
    onSelect: @escaping (String?) -> Void
  ) -> some View {
    section(nil) {
      Button {
        onSelect(nil)
      } label: {
        row("不过滤", value: selectedRuleId == nil ? "已选择" : nil)
      }
      .focused($focusedItem, equals: filterNoneFocusTarget)

      ForEach(viewModel.customFilterRules, id: \.id) { rule in
        Button {
          onSelect(rule.id)
        } label: {
          row(rule.name, value: selectedRuleId == rule.id ? "已选择" : nil)
        }
        .focused($focusedItem, equals: filterRuleFocusTarget(rule.id))
      }
    }
  }

  /// 「播放」设置页，显示哪些行见 `SystemViewModel.playbackSettingRows`。
  private var playbackPage: some View {
    section("播放") {
      ForEach(viewModel.playbackSettingRows, id: \.self) { item in
        switch item {
        case .versionRequirement:
          Button {
            Task { await viewModel.recheckBackendVersion() }
          } label: {
            row("应用内播放", value: versionRequirementValue, showsProgress: viewModel.isCheckingBackendVersion)
          }
          .accessibilityHint("重新检查 MoviePilot 版本")
          .focused($focusedItem, equals: .inAppPlayback)
        case .inAppPlayback:
          Toggle(
            "应用内播放",
            isOn: Binding(
              get: { viewModel.inAppPlaybackEnabled },
              set: { viewModel.inAppPlaybackEnabled = $0 }
            )
          )
          .font(.body.bold())
          .focused($focusedItem, equals: .inAppPlayback)
        case .homeMediaTap:
          Toggle(
            "首页媒体在应用内打开",
            isOn: Binding(
              get: { viewModel.homeMediaTapPlaysInApp },
              set: { viewModel.homeMediaTapPlaysInApp = $0 }
            )
          )
          .font(.body.bold())
          .focused($focusedItem, equals: .homeMediaTapPlaysInApp)
        }
      }
    }
  }

  private var memoryOptimizationPage: some View {
    section("内存优化") {
      ForEach(MemoryOptimizationMode.allCases) { mode in
        Button {
          memoryOptimization.mode = mode
        } label: {
          row(
            memoryOptimizationTitle(for: mode),
            value: memoryOptimization.mode == mode ? "已选择" : nil
          )
        }
        .accessibilityAddTraits(memoryOptimization.mode == mode ? .isSelected : [])
        .focused($focusedItem, equals: .memoryOptimizationMode(mode))
      }
    }
  }

  private func memoryOptimizationTitle(for mode: MemoryOptimizationMode) -> String {
    guard mode == .automatic else { return mode.title }
    return "自动（\(memoryOptimization.automaticIsEnabled ? "开启" : "关闭")）"
  }

  private var versionRequirementValue: String {
    if viewModel.isCheckingBackendVersion { return "正在检查" }
    if viewModel.backendVersionCheckFailed { return "检查失败，按下重试" }
    return "需要 MoviePilot \(InAppPlaybackAvailability.minimumBackendVersion)"
  }

  private var playbackSummary: String {
    guard viewModel.backendSupportsInAppPlayback else {
      return apiService.settings?.BACKEND_VERSION == nil
        ? "未读取到后端版本" : "需要 \(InAppPlaybackAvailability.minimumBackendVersion)"
    }
    return viewModel.inAppPlaybackEnabled ? "已开启" : "已关闭"
  }

  private func section<Content: View>(
    _ title: String?,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    SettingsSection(title, content: content)
  }

  private func row(
    _ title: String,
    value: String? = nil,
    showsProgress: Bool = false,
    showsDisclosure: Bool = false
  ) -> some View {
    SettingsRowLabel(title, value: value, showsProgress: showsProgress, showsDisclosure: showsDisclosure)
  }

  private func staticRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
    .font(.body.bold())
    .lineLimit(1)
  }

  private func push(_ page: SystemSettingsPage) {
    navigationRevision += 1
    let nextRoute = route + [page]
    updateRoute(nextRoute, displayedRoute: nextRoute)
    focusFirstItem(on: page)

    withAnimation(.easeInOut(duration: Self.pageAnimationDuration)) {
      pageOffsetDepth = nextRoute.count
    }
  }

  private func pop() {
    guard !route.isEmpty else { return }
    isOrderingRecommendation = false
    isOrderingExploreContent = false

    navigationRevision += 1
    let revision = navigationRevision
    let previousRoute = route
    let poppedPage = route.last ?? .root
    let nextRoute = Array(route.dropLast())
    updateRoute(nextRoute, displayedRoute: previousRoute)
    focusAfterPop(from: poppedPage, to: nextRoute.last ?? .root)

    withAnimation(.easeInOut(duration: Self.pageAnimationDuration)) {
      pageOffsetDepth = nextRoute.count
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageAnimationDuration + 0.01) {
      guard navigationRevision == revision else { return }
      displayedRoute = nextRoute
    }
  }

  private func focusAfterPop(from poppedPage: SystemSettingsPage, to page: SystemSettingsPage) {
    if page != .root {
      let target: SystemSettingsFocus?
      switch poppedPage {
      case .topShelfExploreSources: target = .topShelfExploreSource
      case .topShelfExploreField(let id): target = .topShelfExploreField(id)
      case .topShelfExplore: target = .topShelfModeExplore
      case .topShelfRecommendations: target = .topShelfModeRecommendation
      case .exploreDefaultSources: target = .exploreDefaultSource
      case .exploreDefaultField(let id): target = .exploreDefaultField(id)
      default: target = nil
      }
      if let target { DispatchQueue.main.async { focusedItem = target } }
      else { focusFirstItem(on: page) }
      return
    }

    let target: SystemSettingsFocus
    switch poppedPage {
    case .connection, .root:
      target = .connection
    case .changelog:
      target = .changelog
    case .licenses:
      target = .licenses
    case .mediaSourceSelection:
      target = .mediaSourceSelection
    case .memoryOptimization:
      target = .memoryOptimization
    case .siteSelection:
      target = .siteSelection
    case .subtitleSiteSelection:
      target = .subtitleSiteSelection
    case .hardFilter:
      target = .hardFilter
    case .softFilter:
      target = .softFilter
    case .topShelfSelection, .topShelfRecommendations, .topShelfExplore,
      .topShelfExploreSources, .topShelfExploreField:
      target = .topShelfRecommendation
    case .recommendation:
      target = .recommendation
    case .exploreContent:
      target = .exploreContent
    case .exploreDefault, .exploreDefaultSources, .exploreDefaultField:
      target = .exploreDefault
    case .playback:
      target = .playbackSettings
    case .logs:
      target = .logs
    }

    DispatchQueue.main.async {
      focusedItem = target
    }
  }

  private func focusFirstItem(on page: SystemSettingsPage) {
    let target: SystemSettingsFocus
    switch page {
    case .root:
      target = .waitBackgroundImage
    case .connection:
      target = .relogin
    case .changelog:
      target = AppChangelog.latest.map { .changelogVersion($0.version) } ?? .changelog
    case .licenses:
      target = ThirdPartyNotices.all.first.map { .license($0.id) } ?? .licenses
    case .mediaSourceSelection:
      target = .defaultMediaSource
    case .memoryOptimization:
      target = .memoryOptimizationMode(memoryOptimization.mode)
    case .siteSelection:
      target = .allSites
    case .subtitleSiteSelection:
      target = .allSubtitleSites
    case .hardFilter:
      target = .hardFilterNone
    case .softFilter:
      target = .softFilterNone
    case .topShelfSelection:
      target = topShelfManager.selection == nil ? .topShelfDisabled
        : (topShelfManager.selection?.exploration == nil ? .topShelfModeRecommendation : .topShelfModeExplore)
    case .topShelfRecommendations:
      target = topShelfManager.selection.flatMap { $0.exploration == nil ? .topShelfSource($0.shelfID) : nil }
        ?? topShelfSelectionOptions.first.map { .topShelfSource($0.shelfID) } ?? .topShelfModeRecommendation
    case .topShelfExplore:
      target = .topShelfExploreSource
    case .topShelfExploreSources:
      target = .topShelfExploreSourceOption(topShelfExplore.selectedSource.id)
    case .topShelfExploreField(let id):
      target = topShelfExplore.settingsFields.first(where: { $0.id == id }).map {
        .topShelfExploreOption($0.kind == .multiChoice ? .null : $0.value.wrappedValue)
      } ?? .topShelfExploreSource
    case .recommendation:
      target = .recommendationOrdering
    case .exploreContent:
      target = .exploreContentOrdering
    case .exploreDefault:
      target = .exploreDefaultSource
    case .exploreDefaultSources:
      target = .exploreDefaultSourceOption(exploreDefaultDraft.selectedSource.id)
    case .exploreDefaultField(let id):
      target = exploreDefaultDraft.settingsFields.first(where: { $0.id == id }).map {
        .exploreDefaultOption($0.kind == .multiChoice ? .null : $0.value.wrappedValue)
      } ?? .exploreDefaultSource
    case .playback:
      target = .inAppPlayback
    case .logs:
      target = .logRecording
    }

    DispatchQueue.main.async {
      focusedItem = target
    }
  }

  private var filterNoneFocusTarget: SystemSettingsFocus {
    switch route.last {
    case .softFilter:
      return .softFilterNone
    case .root, .connection, .changelog, .licenses, .logs, .mediaSourceSelection, .memoryOptimization,
      .siteSelection, .subtitleSiteSelection, .hardFilter, .playback,
      .recommendation, .exploreContent, .exploreDefault, .exploreDefaultSources, .exploreDefaultField,
      .topShelfSelection, .topShelfRecommendations, .topShelfExplore,
      .topShelfExploreSources, .topShelfExploreField, .none:
      return .hardFilterNone
    }
  }

  private func filterRuleFocusTarget(_ ruleId: String) -> SystemSettingsFocus {
    switch route.last {
    case .softFilter:
      return .softFilterRule(ruleId)
    case .root, .connection, .changelog, .licenses, .logs, .mediaSourceSelection, .memoryOptimization,
      .siteSelection, .subtitleSiteSelection, .hardFilter, .playback,
      .recommendation, .exploreContent, .exploreDefault, .exploreDefaultSources, .exploreDefaultField,
      .topShelfSelection, .topShelfRecommendations, .topShelfExplore,
      .topShelfExploreSources, .topShelfExploreField, .none:
      return .hardFilterRule(ruleId)
    }
  }

  private func updateRoute(
    _ nextRoute: [SystemSettingsPage],
    displayedRoute nextDisplayedRoute: [SystemSettingsPage]
  ) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      route = nextRoute
      displayedRoute = nextDisplayedRoute
    }
  }

  private func refreshFilterRulesForEntryIfNeeded() {
    guard isSelected else { return }
    guard canConfigureCustomFilters else { return }

    Task {
      await viewModel.loadCustomFilterRules()
    }
  }

  private func presentUpdateNoticeIfNeeded() {
    guard isSelected, updateNotice == nil else { return }
    guard let entry = AppChangelog.pendingUpdate(appVersion: viewModel.appVersion) else { return }
    updateNotice = entry
  }

  private func toggleDefaultSearchSite(_ siteId: Int) {
    var selectedSites = viewModel.defaultSearchSites

    if selectedSites.contains(siteId) {
      selectedSites.remove(siteId)
    } else {
      selectedSites.insert(siteId)
    }

    viewModel.defaultSearchSites = selectedSites
  }

  private func toggleDefaultSubtitleSearchSite(_ siteId: Int) {
    var selectedSites = viewModel.defaultSubtitleSearchSites
    if selectedSites.contains(siteId) {
      selectedSites.remove(siteId)
    } else {
      selectedSites.insert(siteId)
    }
    viewModel.defaultSubtitleSearchSites = selectedSites
  }

  private func previewDescription(
    for page: SystemSettingsPage,
    focusedItem: SystemSettingsFocus?
  ) -> String? {
    guard let focusedItem else { return nil }

    if page == .root {
      switch focusedItem {
      case .autoSearch:
        return "新增订阅后立即开始搜索，无需等待 MoviePilot 稍后自动处理。（只影响 TV 端）"
      case .episodeTrialRule:
        return "试看一集时，临时订阅使用的站点、质量、规则组和下载设置。按当前账号保存在这台 Apple TV 上。"
      case .waitBackgroundImage:
        return "进入媒体详情页前的加载动画会等待背景海报就绪实现平滑过渡，网络较慢时可关闭以更快进入详情页。（只影响 TV 端）"
      case .playbackSettings:
        return "设置应用内播放和首页点击行为。（只影响 TV 端）"
      case .memoryOptimization:
        return memoryOptimizationDescription
      case .preloadTMDBDetails:
        return "进入豆瓣、Bangumi 或 AniList 详情页并识别到对应 TMDB 条目后，提前加载其详情，以缩短后续跳转等待时间。（只影响 TV 端）"
      case .mediaSourceSelection:
        return "设置聚合搜索默认使用的媒体来源；未选择时沿用 MoviePilot 后端搜索设置。（只影响 TV 端）"
      case .siteSelection:
        return "设置资源搜索默认使用的站点。（只影响 TV 端）"
      case .subtitleSiteSelection:
        return "设置字幕搜索默认使用的站点。（只影响 TV 端）"
      case .hardFilter:
        return "在资源搜索结果中，隐藏不符合要求的资源。（只影响 TV 端）"
      case .softFilter:
        return "在资源搜索结果中，将不符合要求的资源灰置于结果末尾。（只影响 TV 端）"
      case .recommendation:
        return "设置推荐页显示的内容与顺序。（只影响 TV 端）"
      case .exploreContent:
        return "设置探索页显示的数据源与顺序。（只影响 TV 端）"
      case .exploreDefault:
        return "设置探索页的默认数据源、类型与筛选，保存后下次进入探索页时应用一次。（只影响 TV 端）"
      case .topShelfRecommendation:
        return "选择 Apple TV 主屏幕显示的内容。"
      case .connection:
        return "查看当前登录状态、服务器地址和后端连接状态。"
      case .appInfo:
        return nil
      case .changelog:
        return "查看 MoviePilot TV 各版本的更新摘要、完整改动和后端兼容版本。"
      case .licenses:
        return Self.licensesDescription
      case .logs:
        return "查看本机保存的应用日志，可按级别和时间筛选，最长保留 7 天。"
      case .allSites, .site, .allSubtitleSites, .subtitleSite, .defaultMediaSource, .mediaSource,
        .relogin, .logout,
        .hardFilterNone, .softFilterNone, .hardFilterRule, .softFilterRule,
        .recommendationShelf, .recommendationOrdering, .recommendationResetOrder, .recommendationShelfMove,
        .exploreContentOrdering, .exploreContentResetOrder, .exploreSource, .exploreSourceMove,
        .exploreDefaultSource, .exploreDefaultField, .exploreDefaultOption, .exploreDefaultSourceOption,
        .exploreDefaultSave, .exploreDefaultReset, .exploreDefaultFactoryReset,
        .topShelfDisabled, .topShelfSource, .changelogVersion, .license,
        .topShelfModeRecommendation, .topShelfModeExplore, .topShelfExploreSource,
        .topShelfExploreField, .topShelfExploreOption, .topShelfExploreSourceOption,
        .topShelfExploreSave, .topShelfExploreReset, .logRecording, .logDownRedirector, .logLevelFilter,
        .homeMediaTapPlaysInApp, .inAppPlayback, .memoryOptimizationMode,
        .logTimeFilter:
        break
      }
    }

    switch (page, focusedItem) {
    case (.hardFilter, .hardFilterRule(let ruleId)), (.softFilter, .softFilterRule(let ruleId)):
      return filterRulePreviewDescription(for: ruleId)
    case (.hardFilter, .hardFilterNone):
      return "不对资源搜索结果应用硬过滤。（只影响 TV 端）"
    case (.softFilter, .softFilterNone):
      return "不对资源搜索结果应用软过滤。（只影响 TV 端）"
    case (.logs, .logRecording):
      return "关闭后不再把新日志写入本机，已保存的记录仍可查看。"
    case (.licenses, .license(let id)):
      return ThirdPartyNotices.all.first { $0.id == id }?.details.first
    case (.playback, .inAppPlayback):
      guard viewModel.backendSupportsInAppPlayback else {
        let version = apiService.settings?.BACKEND_VERSION ?? "未读取到"
        return "当前 MoviePilot 版本（\(version)）不支持应用内播放，需要 \(InAppPlaybackAvailability.minimumBackendVersion) 及以上。升级后按一下这里重新检查，通过后就能在这里设置。"
      }
      return "开启后，管理员可以在应用内直接播放 \(MediaServerAdapters.supportedNames) 中的电影和剧集；关闭后详情页和首页都不再提供应用内播放。（只影响 TV 端）"
    case (.playback, .homeMediaTapPlaysInApp):
      return "开启后，首页“最近添加”中的电影和剧集点击后直接在应用内播放（剧集从第一集开始）；关闭时跳转媒体服务器 App。长按卡片两种方式都可以选。（只影响 TV 端）"
    case (.memoryOptimization, .memoryOptimizationMode(let mode)):
      return memoryOptimizationModeDescription(for: mode)
    default:
      break
    }

    switch page {
    case .root:
      return nil
    case .connection:
      return "查看当前登录状态、服务器地址和后端连接状态。"
    case .changelog:
      return "查看 MoviePilot TV 各版本的更新摘要、完整改动和后端兼容版本。"
    case .licenses:
      return Self.licensesDescription
    case .logs:
      return "查看本机保存的应用日志，可按级别和时间筛选，最长保留 7 天。"
    case .mediaSourceSelection:
      return "设置聚合搜索默认使用的媒体来源。（只影响 TV 端）"
    case .memoryOptimization:
      return memoryOptimizationDescription
    case .siteSelection:
      return "设置资源搜索默认使用的站点。（只影响 TV 端）"
    case .subtitleSiteSelection:
      return "设置字幕搜索默认使用的站点。（只影响 TV 端）"
    case .hardFilter:
      return "在资源搜索结果中，隐藏不符合要求的资源。（只影响 TV 端）"
    case .softFilter:
      return "在资源搜索结果中，将不符合要求的资源灰置于结果末尾。（只影响 TV 端）"
    case .topShelfSelection, .topShelfRecommendations:
      return "选择 Apple TV 主屏幕显示的内容。"
    case .topShelfExplore, .topShelfExploreSources, .topShelfExploreField:
      return "按这套探索条件更新主屏内容。保存后生效，不影响探索页的筛选。"
    case .recommendation:
      return "设置推荐页显示的内容与顺序。（只影响 TV 端）"
    case .exploreContent:
      return "设置探索页显示的数据源与顺序。（只影响 TV 端）"
    case .exploreDefault, .exploreDefaultSources, .exploreDefaultField:
      return "保存后作为探索页的默认条件，下次进入探索页时应用一次，不影响当前浏览。（只影响 TV 端）"
    case .playback:
      return "设置应用内播放。（只影响 TV 端）"
    }
  }

  private static let licensesDescription = "查看本应用使用的开源软件和它们的许可。"

  private var memoryOptimizationDescription: String {
    "开启后，及时释放暂时看不到的图片，减少内存占用。往回滚动或返回页面时，图片可能需要重新加载。（只影响 TV 端）"
  }

  private func memoryOptimizationModeDescription(for mode: MemoryOptimizationMode) -> String {
    switch mode {
    case .automatic:
      return "能在应用内播放时关闭，让浏览更流畅；其他情况下开启。（只影响 TV 端）"
    case .enabled:
      return memoryOptimizationDescription
    case .disabled:
      return "保留已加载的图片，滚动和返回页面更流畅，但占用更多内存。（只影响 TV 端）"
    }
  }

  private func filterRulePreviewDescription(for ruleId: String) -> String {
    guard let rule = viewModel.customFilterRules.first(where: { $0.id == ruleId }) else {
      return "规则未加载"
    }

    return SystemFilterRulePreview.summary(for: rule) ?? "该规则没有附加过滤条件。"
  }

  private var selectedHardFilterTitle: String {
    selectedFilterTitle(ruleId: viewModel.selectedHardFilterRuleId)
  }

  private var selectedSoftFilterTitle: String {
    selectedFilterTitle(ruleId: viewModel.selectedSoftFilterRuleId)
  }

  private func selectedFilterTitle(ruleId: String?) -> String {
    guard let ruleId else { return "不过滤" }
    return viewModel.customFilterRules.first(where: { $0.id == ruleId })?.name ?? "规则未加载"
  }

  private var siteButtonLabel: String {
    siteChoiceLabel(viewModel.defaultSearchSites)
  }

  private var subtitleSiteButtonLabel: String {
    siteChoiceLabel(viewModel.defaultSubtitleSearchSites)
  }

  private func siteChoiceLabel(_ sites: Set<Int>) -> String {
    if sites.isEmpty {
      return "全部站点"
    } else if sites.count == 1 {
      if let site = viewModel.availableSites.first(where: { sites.contains($0.id) }) {
        return site.name
      }
      return "1 个站点"
    } else {
      return "\(sites.count) 个站点"
    }
  }

  private var mediaSourceButtonLabel: String {
    viewModel.defaultMediaSearchSource.map(mediaSources.title(for:)) ?? "默认"
  }

}

private enum SystemSettingsDetailItem: Identifiable {
  case changelog(AppChangelogEntry)
  case license(ThirdPartyNotice)
  case log(LogRecord)

  var id: String {
    switch self {
    case .changelog(let entry):
      return "changelog-\(entry.id)"
    case .license(let notice):
      return "license-\(notice.id)"
    case .log(let record):
      return "log-\(record.id.uuidString)"
    }
  }
}

enum SystemSettingsPage: Hashable {
  case root
  case connection
  case changelog
  case licenses
  case logs
  case mediaSourceSelection
  case memoryOptimization
  case siteSelection
  case subtitleSiteSelection
  case hardFilter
  case softFilter
  case recommendation
  case exploreContent
  case exploreDefault
  case exploreDefaultSources
  case exploreDefaultField(String)
  case topShelfSelection
  case topShelfRecommendations
  case topShelfExplore
  case topShelfExploreSources
  case topShelfExploreField(String)
  case playback
}

enum SystemSettingsFocus: Hashable {
  case connection
  case changelog
  case changelogVersion(String)
  case licenses
  case license(String)
  case logs
  case logRecording
  case logDownRedirector
  case logLevelFilter
  case logTimeFilter
  case mediaSourceSelection
  case memoryOptimization
  case memoryOptimizationMode(MemoryOptimizationMode)
  case defaultMediaSource
  case mediaSource(MediaSearchSource)
  case siteSelection
  case allSites
  case site(Int)
  case subtitleSiteSelection
  case allSubtitleSites
  case subtitleSite(Int)
  case appInfo
  case autoSearch
  case episodeTrialRule
  case homeMediaTapPlaysInApp
  case playbackSettings
  case inAppPlayback
  case preloadTMDBDetails
  case waitBackgroundImage
  case hardFilter
  case softFilter
  case relogin
  case logout
  case hardFilterNone
  case softFilterNone
  case hardFilterRule(String)
  case softFilterRule(String)
  case recommendation
  case recommendationOrdering
  case recommendationResetOrder
  case recommendationShelfMove(String, ContentMoveDirection)
  case exploreContent
  case exploreContentOrdering
  case exploreContentResetOrder
  case exploreSource(String)
  case exploreSourceMove(String, ContentMoveDirection)
  case exploreDefault
  case exploreDefaultSource
  case exploreDefaultField(String)
  case exploreDefaultOption(JSONValue)
  case exploreDefaultSourceOption(String)
  case exploreDefaultSave
  case exploreDefaultReset
  case exploreDefaultFactoryReset
  case topShelfRecommendation
  case topShelfDisabled
  case topShelfModeRecommendation
  case topShelfModeExplore
  case topShelfExploreSource
  case topShelfExploreField(String)
  case topShelfExploreOption(JSONValue)
  case topShelfExploreSourceOption(String)
  case topShelfExploreSave
  case topShelfExploreReset
  case topShelfSource(String)
  case recommendationShelf(String)
}

/// 一个第三方组件的许可详情。单独成一个视图并按组件比较：系统页重绘时组件没变就不重算正文，
/// 许可原文很长（GPL v3 约 35 KB），不必每次都重新读文件、拆焦点块。
private struct ThirdPartyLicenseSheet: View, Equatable {
  let notice: ThirdPartyNotice

  var body: some View {
    ReadingSheet(title: notice.name, blocks: SystemView.licenseBlocks(notice))
  }
}

private extension View {
  @ViewBuilder
  func systemSettingsExitCommand(
    isEnabled: Bool,
    perform action: @escaping () -> Void
  ) -> some View {
    if isEnabled {
      onExitCommand(perform: action)
    } else {
      self
    }
  }
}

private struct SystemSettingsRootBackObserver: UIViewRepresentable {
  typealias UIViewType = UIView

  let isEnabled: Bool
  let onExitPress: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(
    context: UIViewRepresentableContext<SystemSettingsRootBackObserver>
  ) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    context.coordinator.view = view
    return view
  }

  func updateUIView(
    _ uiView: UIView,
    context: UIViewRepresentableContext<SystemSettingsRootBackObserver>
  ) {
    context.coordinator.view = uiView
    context.coordinator.isEnabled = isEnabled
    context.coordinator.onExitPress = onExitPress
    context.coordinator.refresh()
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.uninstall()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var view: UIView?
    var isEnabled = false
    var onExitPress: (() -> Void)?

    private weak var installedWindow: UIWindow?
    private var recognizer: UITapGestureRecognizer?

    func refresh() {
      DispatchQueue.main.async { [weak self] in
        self?.installIfNeeded()
      }
    }

    func installIfNeeded() {
      guard isEnabled, let window = view?.window else {
        uninstall()
        return
      }
      guard installedWindow !== window else { return }

      uninstall()
      let recognizer = UITapGestureRecognizer(target: self, action: #selector(handlePress(_:)))
      recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
      recognizer.cancelsTouchesInView = false
      recognizer.delegate = self
      window.addGestureRecognizer(recognizer)

      installedWindow = window
      self.recognizer = recognizer
    }

    func uninstall() {
      if let recognizer {
        installedWindow?.removeGestureRecognizer(recognizer)
      }
      installedWindow = nil
      recognizer = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      isEnabled && view?.window != nil
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    @objc private func handlePress(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, isEnabled else { return }
      // 兜底：window 上若有模态呈现（sheet/alert 关闭动画中），Menu 键不属于设置页。
      guard windowHasNoPresentedContent() else { return }
      onExitPress?()
    }

    private func windowHasNoPresentedContent() -> Bool {
      guard let window = view?.window else { return true }
      return window.rootViewController?.presentedViewController == nil
    }
  }
}

enum SystemFilterRulePreview {
  nonisolated static func summary(for rule: CustomRule) -> String? {
    let parts = summaryParts(for: rule)
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " · ")
  }

  nonisolated private static func summaryParts(for rule: CustomRule) -> [String] {
    var parts: [String] = []

    if let include = normalized(rule.include?.joined(separator: " ")) {
      parts.append("包含: \(include)")
    }
    if let exclude = normalized(rule.exclude?.joined(separator: " ")) {
      parts.append("排除: \(exclude)")
    }
    if let sizeRange = normalized(rule.size_range) {
      parts.append("大小: \(sizeRange) MB")
    }
    if let seeders = normalized(rule.seeders) {
      parts.append("做种≥\(seeders)")
    }
    if let publishTime = normalized(rule.publish_time) {
      parts.append("发布: \(publishTime)分钟")
    }

    return parts
  }

  nonisolated private static func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}

/// 「试看订阅规则」一行的摘要，跟着当前账号保存的规则变化。
private struct EpisodeTrialRuleSummary<Label: View>: View {
  @ObservedObject var service: EpisodeTrialService
  @ViewBuilder let label: (String) -> Label

  var body: some View {
    label(service.rule.isDefault ? "默认" : "已自定义")
  }
}
