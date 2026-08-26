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

  @StateObject private var viewModel = SystemViewModel()
  @StateObject private var recommendViewModel = RecommendViewModel(selectShelf: false)
  @ObservedObject private var apiService = APIService.shared
  @State private var showAppInfo = false
  @State private var selectedChangelogEntry: AppChangelogEntry?
  @State private var updateNotice: AppChangelogEntry?
  @State private var showLogoutConfirmation = false
  @State private var route: [SystemSettingsPage] = []
  @State private var displayedRoute: [SystemSettingsPage] = []
  @State private var pageOffsetDepth = 0
  @State private var navigationRevision = 0
  @FocusState private var focusedItem: SystemSettingsFocus?

  init(isSelected: Bool = true) {
    self.isSelected = isSelected
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

  private var canConfigureCustomFilters: Bool {
    apiService.canRequestSuperUserEndpoints
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
    .sheet(item: $selectedChangelogEntry) { entry in
      changelogDetailSheet(entry)
    }
    .alert(item: $updateNotice) { entry in
      Alert(
        title: Text("已更新到 \(entry.version)"),
        message: Text(AppChangelog.updateNoticeMessage(for: entry))
          .font(.callout),
        dismissButton: .default(Text("知道了")) {
          AppChangelog.markPresented(entry)
        }
      )
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
      .systemSettingsExitCommand(isEnabled: isSelected && isActive && page != .root, perform: pop)
  }

  private func pageView(_ page: SystemSettingsPage, isActive: Bool) -> some View {
    ScrollViewReader { scrollProxy in
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
          case .siteSelection:
            if canConfigureSearch {
              siteSelectionPage
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
          case .recommendation:
            if canConfigureRecommendations {
              recommendationPage
            }
          case .changelog:
            changelogPage
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, Self.contentBottomPadding)
      }
      .scrollClipDisabled()
      .background(
        SystemSettingsRootBackObserver(
          // Sheet / Alert 呈现期间禁用 Menu 手势：否则按 Menu 关闭弹层时
          // 会同时触发 scrollTo(top)，随后焦点恢复又滚回原行，形成"先上滑再下滑"。
          isEnabled: isSelected && isActive && page == .root
            && !showAppInfo && updateNotice == nil && selectedChangelogEntry == nil
            && !showLogoutConfirmation,
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
      if canConfigureSubscriptions {
        section("订阅") {
          Toggle(
            "新增订阅后立即搜索",
            isOn: Binding(
              get: { viewModel.autoSearchNewSubscriptions },
              set: { viewModel.autoSearchNewSubscriptions = $0 }
            )
          )
          .font(.body.weight(.semibold))
          .focused($focusedItem, equals: .autoSearch)
        }
      }

      if canConfigureRecommendations {
        section("推荐页") {
          Button {
            push(.recommendation)
          } label: {
            row("推荐页显示内容", showsDisclosure: true)
          }
          .focused($focusedItem, equals: .recommendation)
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

      section("详情页") {
        Toggle(
          "预加载 TMDB 详情",
          isOn: Binding(
            get: { viewModel.preloadTMDBDetails },
            set: { viewModel.preloadTMDBDetails = $0 }
          )
        )
        .font(.body.weight(.semibold))
        .focused($focusedItem, equals: .preloadTMDBDetails)

        Toggle(
          "等待背景海报加载",
          isOn: Binding(
            get: { viewModel.waitMediaDetailBackgroundImage },
            set: { viewModel.waitMediaDetailBackgroundImage = $0 }
          )
        )
        .font(.body.weight(.semibold))
        .focused($focusedItem, equals: .waitBackgroundImage)
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
        staticRow("兼容 MoviePilot 版本", viewModel.compatibleMoviePilotVersion)
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
          selectedChangelogEntry = entry
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

  private func changelogDetailSheet(_ entry: AppChangelogEntry) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 10) {
          Text(entry.version)
            .font(.title2.bold())
          Text(entry.releaseDate)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Divider()

        changelogSection("更新内容", items: entry.highlights, isPrimary: true)
        changelogSection("新增功能", items: entry.updates)
        changelogSection("修复", items: entry.fixes)
        changelogSection("优化", items: entry.optimizations)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 72)
      .padding(.vertical, 54)
    }
    .frame(width: 1_440, height: 1_025)
  }

  @ViewBuilder
  private func changelogSection(
    _ title: String,
    items: [String],
    isPrimary: Bool = false
  ) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 16) {
        Text(title)
          .font(isPrimary ? .headline.bold() : .subheadline.bold())

        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          Text("• \(item)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var recommendationPage: some View {
    section(nil) {
      ForEach(recommendViewModel.shelves) { shelf in
        Toggle(
          shelf.title,
          isOn: Binding(
            get: { recommendViewModel.enableConfig[shelf.title] == true },
            set: { enabled in
              var config = recommendViewModel.enableConfig
              config[shelf.title] = enabled
              recommendViewModel.saveEnableConfig(config)
            }
          )
        )
        .font(.body.weight(.semibold))
        .focused($focusedItem, equals: .recommendationShelf(shelf.id))
      }
    }
    .task {
      await recommendViewModel.refreshSources(selectShelf: false)
    }
  }

  private var siteSelectionPage: some View {
    section(nil) {
      Button {
        viewModel.defaultSearchSites = []
      } label: {
        row("全部站点", value: viewModel.defaultSearchSites.isEmpty ? "已选择" : nil)
      }
      .focused($focusedItem, equals: .allSites)

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
          toggleDefaultSearchSite(site.id)
        } label: {
          row(site.name, value: viewModel.defaultSearchSites.contains(site.id) ? "已选择" : nil)
        }
        .focused($focusedItem, equals: .site(site.id))
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

      ForEach(MediaSearchSource.allowed(for: .media)) { source in
        Button {
          viewModel.defaultMediaSearchSource = source
        } label: {
          row(
            source.title,
            value: viewModel.defaultMediaSearchSource == source ? "已选择" : nil
          )
        }
        .focused($focusedItem, equals: .mediaSource(source))
      }
    }
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

  private func section<Content: View>(
    _ title: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading) {
      if let title, !title.isEmpty {
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.leading, 16)
      }
      VStack() {
        content()
          .padding(.horizontal, 10)
      }
    }
  }

  private func row(
    _ title: String,
    value: String? = nil,
    showsProgress: Bool = false,
    showsDisclosure: Bool = false
  ) -> some View {
    HStack {
      Text(title)
        .font(.body.weight(.semibold))
        .lineLimit(1)

      Spacer()

      HStack(spacing: 8) {
        if showsProgress {
          ProgressView()
        }

        if let value {
          Text(value)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .truncationMode(.middle)
        }

        if showsDisclosure {
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func staticRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
    .font(.body.weight(.semibold))
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
      focusFirstItem(on: page)
      return
    }

    let target: SystemSettingsFocus
    switch poppedPage {
    case .connection, .root:
      target = .connection
    case .changelog:
      target = .changelog
    case .mediaSourceSelection:
      target = .mediaSourceSelection
    case .siteSelection:
      target = .siteSelection
    case .hardFilter:
      target = .hardFilter
    case .softFilter:
      target = .softFilter
    case .recommendation:
      target = .recommendation
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
    case .mediaSourceSelection:
      target = .defaultMediaSource
    case .siteSelection:
      target = .allSites
    case .hardFilter:
      target = .hardFilterNone
    case .softFilter:
      target = .softFilterNone
    case .recommendation:
      target = .recommendationShelf(RecommendViewModel.allShelves[0].id)
    }

    DispatchQueue.main.async {
      focusedItem = target
    }
  }

  private var filterNoneFocusTarget: SystemSettingsFocus {
    switch route.last {
    case .softFilter:
      return .softFilterNone
    case .root, .connection, .changelog, .mediaSourceSelection, .siteSelection, .hardFilter,
      .recommendation, .none:
      return .hardFilterNone
    }
  }

  private func filterRuleFocusTarget(_ ruleId: String) -> SystemSettingsFocus {
    switch route.last {
    case .softFilter:
      return .softFilterRule(ruleId)
    case .root, .connection, .changelog, .mediaSourceSelection, .siteSelection, .hardFilter,
      .recommendation, .none:
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

  private func previewDescription(
    for page: SystemSettingsPage,
    focusedItem: SystemSettingsFocus?
  ) -> String? {
    guard let focusedItem else { return nil }

    if page == .root {
      switch focusedItem {
      case .autoSearch:
        return "新增订阅后立即开始搜索，无需等待 MoviePilot 稍后自动处理。（只影响 TV 端）"
      case .waitBackgroundImage:
        return "进入媒体详情页前的加载动画会等待背景海报就绪实现平滑过渡，网络较慢时可关闭以更快进入详情页。（只影响 TV 端）"
      case .preloadTMDBDetails:
        return "进入豆瓣、Bangumi 或 AniList 详情页并识别到对应 TMDB 条目后，提前加载其详情，以缩短后续跳转等待时间。（只影响 TV 端）"
      case .mediaSourceSelection:
        return "设置聚合搜索默认使用的媒体来源；未选择时沿用 MoviePilot 后端搜索设置。（只影响 TV 端）"
      case .siteSelection:
        return "设置资源搜索默认使用的站点。（只影响 TV 端）"
      case .hardFilter:
        return "在资源搜索结果中，隐藏不符合要求的资源。（只影响 TV 端）"
      case .softFilter:
        return "在资源搜索结果中，将不符合要求的资源灰置于结果末尾。（只影响 TV 端）"
      case .recommendation:
        return "设置推荐页面显示的内容。（只影响 TV 端）"
      case .connection:
        return "查看当前登录状态、服务器地址和后端连接状态。"
      case .appInfo:
        return nil
      case .changelog:
        return "查看 MoviePilot TV 各版本的更新摘要、完整改动和后端兼容版本。"
      case .allSites, .site, .defaultMediaSource, .mediaSource, .relogin, .logout,
        .hardFilterNone, .softFilterNone, .hardFilterRule, .softFilterRule,
        .recommendationShelf, .changelogVersion:
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
    case .mediaSourceSelection:
      return "设置聚合搜索默认使用的媒体来源。（只影响 TV 端）"
    case .siteSelection:
      return "设置资源搜索默认使用的站点。（只影响 TV 端）"
    case .hardFilter:
      return "在资源搜索结果中，隐藏不符合要求的资源。（只影响 TV 端）"
    case .softFilter:
      return "在资源搜索结果中，将不符合要求的资源灰置于结果末尾。（只影响 TV 端）"
    case .recommendation:
      return "设置推荐页面显示的内容。（只影响 TV 端）"
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
    if viewModel.defaultSearchSites.isEmpty {
      return "全部站点"
    } else if viewModel.defaultSearchSites.count == 1 {
      if let site = viewModel.availableSites.first(where: {
        viewModel.defaultSearchSites.contains($0.id)
      }) {
        return site.name
      }
      return "1 个站点"
    } else {
      return "\(viewModel.defaultSearchSites.count) 个站点"
    }
  }

  private var mediaSourceButtonLabel: String {
    viewModel.defaultMediaSearchSource?.title ?? "默认"
  }

}

private enum SystemSettingsPage: Hashable {
  case root
  case connection
  case changelog
  case mediaSourceSelection
  case siteSelection
  case hardFilter
  case softFilter
  case recommendation
}

private enum SystemSettingsFocus: Hashable {
  case connection
  case changelog
  case changelogVersion(String)
  case mediaSourceSelection
  case defaultMediaSource
  case mediaSource(MediaSearchSource)
  case siteSelection
  case allSites
  case site(Int)
  case appInfo
  case autoSearch
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
  case recommendationShelf(String)
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
