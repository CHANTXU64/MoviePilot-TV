#if DEBUG
import SwiftUI

struct PreviewCatalogView: View {
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var selectedScene: UIPreviewScene?
  @State private var didResetPreviewState = false

  init(initialSceneID: String? = nil) {
    UIPreviewFixtures.resetPreviewState()
    _didResetPreviewState = State(initialValue: true)
    _selectedScene = State(initialValue: UIPreviewCatalog.scene(id: initialSceneID))
  }

  var body: some View {
    ZStack {
      NavigationStack {
        UIPreviewCatalogHomeView(isActive: selectedScene == nil) { scene in
          selectedScene = scene
        }
        .navigationTitle("UI 预览")
      }
      .opacity(selectedScene == nil ? 1 : 0)
      .disabled(selectedScene != nil)

      if let selectedScene {
        UIPreviewSceneDestination(scene: selectedScene)
          .id(selectedScene.id)
          .onExitCommand {
            self.selectedScene = nil
          }
      }
    }
    .mediaActionAlerts()
    .environmentObject(mediaActionHandler)
    .withNotification()
    .onAppear {
      guard !didResetPreviewState else { return }
      didResetPreviewState = true
      UIPreviewFixtures.resetPreviewState()
    }
  }
}

private struct UIPreviewCatalogHomeView: View {
  let isActive: Bool
  let selectScene: (UIPreviewScene) -> Void
  @State private var expandedSectionIDs: Set<String> = []
  @State private var lastFocusedControlID: String?
  @FocusState private var focusedControlID: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 34) {
        ForEach(UIPreviewCatalog.sections) { section in
          VStack(alignment: .leading, spacing: 14) {
            Button {
              toggleSection(section.id)
            } label: {
              Label(section.title, systemImage: expandedSectionIDs.contains(section.id) ? "chevron.down" : "chevron.right")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focusedControlID, equals: section.id)

            if expandedSectionIDs.contains(section.id) {
              VStack(spacing: 10) {
                ForEach(section.scenes) { scene in
                  Button {
                    lastFocusedControlID = scene.id
                    selectScene(scene)
                  } label: {
                    VStack(alignment: .leading) {
                      Text(scene.title)
                      Text(scene.note)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .focused($focusedControlID, equals: scene.id)
                }
              }
            }
          }
        }
      }
      .frame(width: 760, alignment: .leading)
      .padding(.vertical, 60)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .onAppear {
      focusedControlID = focusedControlID ?? UIPreviewCatalog.firstSectionID
      lastFocusedControlID = lastFocusedControlID ?? focusedControlID
    }
    .onChange(of: focusedControlID) { _, newValue in
      lastFocusedControlID = newValue ?? lastFocusedControlID
    }
    .onChange(of: isActive) { _, isActive in
      guard isActive else { return }
      focusedControlID = lastFocusedControlID ?? focusedControlID ?? UIPreviewCatalog.firstSectionID
    }
  }

  private func toggleSection(_ sectionID: String) {
    if expandedSectionIDs.contains(sectionID) {
      expandedSectionIDs.remove(sectionID)
    } else {
      expandedSectionIDs.insert(sectionID)
    }
  }
}

private struct UIPreviewSceneDestination: View {
  let scene: UIPreviewScene
  @State private var navigationPath = NavigationPath()

  var body: some View {
    switch scene.kind {
    case .app(let previewCase):
      UIPreviewAppSceneView(previewCase: previewCase)
    case .page(let previewCase):
      UIPreviewPageSceneView(previewCase: previewCase)
    case .detail(let detailCase):
      UIPreviewDetailSceneView(detailCase: detailCase)
    case .season(let seasonCase):
      UIPreviewSeasonSceneView(seasonCase: seasonCase)
    case .search(let searchCase):
      UIPreviewSearchSceneView(searchCase: searchCase)
    case .status(let statusCase):
      UIPreviewStatusSceneView(statusCase: statusCase)
    case .settings(let settingsCase):
      UIPreviewSettingsSceneView(settingsCase: settingsCase)
    case .sheet(let sheetCase):
      UIPreviewSheetSceneView(sheetCase: sheetCase)
    case .component(let componentCase):
      UIPreviewComponentSceneView(componentCase: componentCase, navigationPath: $navigationPath)
    }
  }
}

@MainActor
private struct UIPreviewAppSceneView: View {
  let previewCase: UIPreviewAppCase

  var body: some View {
    Group {
      switch previewCase {
      case .startupPreparing:
        UIPreviewStartupPreparingView()
      case .loggedIn:
        UIPreviewLoggedInRootView()
      case .loggedInLimitedTabs:
        UIPreviewLoggedInRootView(
          permissions: [.discovery],
          canRequestSuperUserEndpoints: false
        )
      case .backendVersionWarning:
        UIPreviewLoggedInRootAlertView(alertCase: .backendVersion)
      case .accountPermissionWarning:
        UIPreviewLoggedInRootAlertView(alertCase: .accountPermission)
      case .login, .loginReady, .loginLoading, .loginFailed:
        LoginView(previewViewModel: UIPreviewFixtures.loginViewModel(previewCase))
      }
    }
    .onAppear {
      switch previewCase {
      case .startupPreparing, .loggedIn, .backendVersionWarning:
        UIPreviewFixtures.applyPermissions(.allPreviewPermissions, canRequestSuperUserEndpoints: true)
      case .loggedInLimitedTabs, .accountPermissionWarning:
        UIPreviewFixtures.applyPermissions([.discovery], canRequestSuperUserEndpoints: false)
      case .login, .loginReady, .loginLoading, .loginFailed:
        UIPreviewFixtures.applyPermissions([], canRequestSuperUserEndpoints: false)
      }
    }
  }
}

private struct UIPreviewStartupPreparingView: View {
  @FocusState private var isReturnAnchorFocused: Bool

  var body: some View {
    ZStack {
      ProgressView("正在准备会话...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Color.clear
        .frame(width: 1, height: 1)
        .focusable()
        .focused($isReturnAnchorFocused)
        .accessibilityHidden(true)
    }
    .onAppear {
      isReturnAnchorFocused = true
    }
  }
}

private enum UIPreviewLoggedInRootAlertCase {
  case backendVersion
  case accountPermission
}

private struct UIPreviewRootAlert: Identifiable {
  let id: String
  let title: String
  let message: String
}

@MainActor
private struct UIPreviewLoggedInRootAlertView: View {
  let alertCase: UIPreviewLoggedInRootAlertCase

  @State private var activeAlert: UIPreviewRootAlert?

  var body: some View {
    UIPreviewLoggedInRootView(
      permissions: alertCase == .accountPermission ? [.discovery] : .allPreviewPermissions,
      canRequestSuperUserEndpoints: alertCase != .accountPermission
    )
    .alert(item: $activeAlert) { warning in
      Alert(
        title: Text(warning.title),
        message: Text(warning.message),
        dismissButton: .default(Text("继续使用"))
      )
    }
    .onAppear {
      Task { @MainActor in
        await Task.yield()
        switch alertCase {
        case .backendVersion:
          let warning = BackendVersionWarning(
            backendVersion: "v2.12.0",
            requiredVersion: AppVersionInfo.compatibleMoviePilotVersion
          )
          activeAlert = UIPreviewRootAlert(
            id: warning.id,
            title: warning.title,
            message: warning.message
          )
        case .accountPermission:
          let warning = AccountPermissionWarning(
            id: "preview-account-permission-warning",
            title: "账号权限不足",
            message: "当前账号缺少搜索、订阅权限。MoviePilot-TV 兼容验证至少要求账号具备探索、搜索和订阅权限；继续使用时部分入口会隐藏，页面布局或焦点可能不完整。",
            missingPermissions: [.search, .subscribe]
          )
          activeAlert = UIPreviewRootAlert(
            id: warning.id,
            title: warning.title,
            message: warning.message
          )
        }
      }
    }
  }
}

@MainActor
private struct UIPreviewLoggedInRootView: View {
  @StateObject private var homeViewModel: HomeViewModel
  @StateObject private var recommendViewModel: RecommendViewModel
  @StateObject private var exploreViewModel: ExploreViewModel
  @StateObject private var searchViewModel: SearchViewModel
  @StateObject private var statusViewModel: StatusViewModel
  @StateObject private var downloadViewModel: DownloadTaskViewModel
  @StateObject private var transferViewModel: TransferHistoryViewModel
  @StateObject private var systemViewModel: SystemViewModel
  @State private var selectedTab: ContentViewModel.Tab

  private let permissions: Set<UserPermissionKey>
  private let canRequestSuperUserEndpoints: Bool
  private let systemPresentation: SystemViewUIPreviewPresentation?
  private let downloadPresentation: DownloadTaskUIPreviewPresentation?
  private let transferPresentation: TransferHistoryUIPreviewPresentation?
  private let homePreviewDestinations: HomeViewUIPreviewDestinations?
  private let homeInitialPath: NavigationPath
  private let searchInitialPath: NavigationPath
  private let searchPreviewDestinations: SearchViewUIPreviewDestinations?
  private let showsSearchSiteSelection: Bool
  private let explorePreviewForkShare: SubscribeShare?

  init(
    selectedTab: ContentViewModel.Tab = .home,
    homeMode: UIPreviewHomeMode = .full,
    recommendMode: UIPreviewRecommendMode = .full,
    exploreMode: UIPreviewExploreMode = .tmdb,
    searchCase: UIPreviewSearchCase = .unifiedResults,
    statusMode: UIPreviewStatusMode = .full,
    downloadMode: UIPreviewDownloadMode = .multiState,
    transferMode: UIPreviewTransferMode = .aiRedoing,
    settingsCase: UIPreviewSettingsCase = .fullAccess,
    permissions: Set<UserPermissionKey> = .allPreviewPermissions,
    canRequestSuperUserEndpoints: Bool = true,
    systemPresentation: SystemViewUIPreviewPresentation? = nil,
    downloadPresentation: DownloadTaskUIPreviewPresentation? = nil,
    transferPresentation: TransferHistoryUIPreviewPresentation? = nil,
    homePreviewDestinations: HomeViewUIPreviewDestinations? = nil,
    homeInitialPath: NavigationPath = NavigationPath(),
    searchInitialPath: NavigationPath = NavigationPath(),
    searchPreviewDestinations: SearchViewUIPreviewDestinations? = nil,
    showsSearchSiteSelection: Bool = false,
    explorePreviewForkShare: SubscribeShare? = nil
  ) {
    UIPreviewFixtures.applyPermissions(
      permissions,
      canRequestSuperUserEndpoints: canRequestSuperUserEndpoints
    )
    _homeViewModel = StateObject(wrappedValue: UIPreviewFixtures.homeViewModel(homeMode))
    _recommendViewModel = StateObject(wrappedValue: UIPreviewFixtures.recommendViewModel(recommendMode))
    _exploreViewModel = StateObject(wrappedValue: UIPreviewFixtures.exploreViewModel(exploreMode))
    _searchViewModel = StateObject(wrappedValue: UIPreviewFixtures.searchViewModel(searchCase))
    _statusViewModel = StateObject(wrappedValue: UIPreviewFixtures.statusViewModel(statusMode))
    _downloadViewModel = StateObject(wrappedValue: UIPreviewFixtures.downloadViewModel(downloadMode))
    _transferViewModel = StateObject(wrappedValue: UIPreviewFixtures.transferHistoryViewModel(transferMode))
    _systemViewModel = StateObject(wrappedValue: UIPreviewFixtures.systemViewModel(settingsCase))
    _selectedTab = State(initialValue: Self.resolvedSelectedTab(selectedTab, permissions: permissions))
    self.permissions = permissions
    self.canRequestSuperUserEndpoints = canRequestSuperUserEndpoints
    self.systemPresentation = systemPresentation
    self.downloadPresentation = downloadPresentation
    self.transferPresentation = transferPresentation
    self.homePreviewDestinations = homePreviewDestinations
    self.homeInitialPath = homeInitialPath
    self.searchInitialPath = searchInitialPath
    self.searchPreviewDestinations = searchPreviewDestinations
    self.showsSearchSiteSelection = showsSearchSiteSelection
    self.explorePreviewForkShare = explorePreviewForkShare
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      HomeView(
        viewModel: homeViewModel,
        loadsDataOnAppear: false,
        initialPath: homeInitialPath,
        uiPreviewDestinations: homePreviewDestinations
      )
        .tabItem { Label("媒体库", systemImage: "play.tv") }
        .tag(ContentViewModel.Tab.home)

      if visibleTabs.contains(.recommend) {
        RecommendView(viewModel: recommendViewModel)
          .tabItem { Label("推荐", systemImage: "sparkles.tv") }
          .tag(ContentViewModel.Tab.recommend)
      }

      if visibleTabs.contains(.explore) {
        ExploreView(viewModel: exploreViewModel, uiPreviewForkShare: explorePreviewForkShare)
          .tabItem { Label("探索", systemImage: "safari") }
          .tag(ContentViewModel.Tab.explore)
      }

      if visibleTabs.contains(.search) {
        SearchView(
          viewModel: searchViewModel,
          loadsSitesOnAppear: false,
          initialPath: searchInitialPath,
          uiPreviewDestinations: searchPreviewDestinations,
          showsSiteSelection: showsSearchSiteSelection
        )
        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
        .tag(ContentViewModel.Tab.search)
      }

      if visibleTabs.contains(.status) {
        StatusView(
          viewModel: statusViewModel,
          downloadTaskViewModel: downloadViewModel,
          transferHistoryViewModel: transferViewModel,
          refreshesOnAppear: false,
          downloadPresentation: downloadPresentation,
          transferPresentation: transferPresentation
        )
        .tabItem { Label("状态", systemImage: "slider.horizontal.3") }
        .tag(ContentViewModel.Tab.status)
      }

      systemTab
        .tabItem { Label("设置", systemImage: "gear") }
        .tag(ContentViewModel.Tab.system)
    }
    .foregroundColor(.primary)
    .onAppear {
      UIPreviewFixtures.applyPermissions(
        permissions,
        canRequestSuperUserEndpoints: canRequestSuperUserEndpoints
      )
      selectedTab = Self.resolvedSelectedTab(selectedTab, permissions: permissions)
    }
  }

  @ViewBuilder
  private var systemTab: some View {
    if let systemPresentation {
      SystemView(uiPreviewPresentation: systemPresentation, viewModel: systemViewModel)
    } else {
      SystemView(isSelected: selectedTab == .system, viewModel: systemViewModel, loadsDataOnAppear: false)
    }
  }

  private var visibleTabs: Set<ContentViewModel.Tab> {
    Self.visibleTabs(for: permissions)
  }

  private static func resolvedSelectedTab(
    _ selectedTab: ContentViewModel.Tab,
    permissions: Set<UserPermissionKey>
  ) -> ContentViewModel.Tab {
    let visibleTabs = visibleTabs(for: permissions)
    return visibleTabs.contains(selectedTab) ? selectedTab : .home
  }

  private static func visibleTabs(for permissions: Set<UserPermissionKey>) -> Set<ContentViewModel.Tab> {
    var tabs: Set<ContentViewModel.Tab> = [.home, .system]
    if permissions.contains(.discovery) {
      tabs.insert(.recommend)
      tabs.insert(.explore)
    }
    if permissions.contains(.search) {
      tabs.insert(.search)
    }
    if permissions.contains(.manage) {
      tabs.insert(.status)
    }
    return tabs
  }
}

@MainActor
private struct UIPreviewPageSceneView: View {
  let previewCase: UIPreviewPageCase

  var body: some View {
    switch previewCase {
    case .homeLoading, .homeEmpty, .homeFull, .homeLatestEmptyServer, .homeSubscriptionsOnly,
      .homeNoSubscribePermission, .homeNoSearchPermission, .homeSubscribeSheet,
      .homeUnsubscribeConfirmation:
      UIPreviewLoggedInRootView(
        selectedTab: .home,
        homeMode: previewCase.homeMode,
        permissions: previewCase.permissions,
        homePreviewDestinations: HomeViewUIPreviewDestinations(homePresentation: previewCase.homePresentation)
      )
    case .recommendInitial, .recommendLoading, .recommendEmpty, .recommendFull, .recommendLimitedPermissions:
      UIPreviewLoggedInRootView(
        selectedTab: .recommend,
        recommendMode: previewCase.recommendMode,
        permissions: previewCase.permissions
      )
    case .exploreInitial, .exploreLoading, .exploreTmdb, .exploreDouban, .exploreBangumi, .explorePopular,
      .exploreShare, .exploreShareSheet, .exploreNoSubscribePermission, .exploreEmpty:
      UIPreviewLoggedInRootView(
        selectedTab: .explore,
        exploreMode: previewCase.exploreMode,
        permissions: previewCase.permissions,
        explorePreviewForkShare: previewCase.explorePreviewForkShare
      )
    case .collectionLoading, .collectionEmpty, .collectionFull, .collectionLoadingMore:
      UIPreviewCollectionScene(mode: previewCase.collectionMode)
    case .personLoading, .personNoBiography, .personBiographySheet, .personFull, .personLoadingMore:
      UIPreviewPersonScene(mode: previewCase.personMode)
    }
  }
}

@MainActor
private struct UIPreviewCollectionScene: View {
  let mode: UIPreviewCollectionMode

  var body: some View {
    let media = UIPreviewFixtures.collectionMedia(id: 991, title: "边境信号系列")

    UIPreviewLoggedInRootView(
      selectedTab: .search,
      searchInitialPath: media.previewNavigationPath(),
      searchPreviewDestinations: SearchViewUIPreviewDestinations(
        collectionViewModel: UIPreviewFixtures.collectionViewModel(mode)
      )
    )
  }
}

@MainActor
private struct UIPreviewPersonScene: View {
  let mode: UIPreviewPersonMode

  var body: some View {
    let viewModel = UIPreviewFixtures.personViewModel(mode)

    UIPreviewLoggedInRootView(
      selectedTab: .search,
      searchInitialPath: viewModel.person.previewNavigationPath(),
      searchPreviewDestinations: SearchViewUIPreviewDestinations(
        personViewModel: viewModel,
        personShowsBiographySheet: mode == .biographySheet
      ),
      showsSearchSiteSelection: false
    )
  }
}

@MainActor
private struct UIPreviewDetailSceneView: View {
  let detailCase: UIPreviewDetailCase
  @State private var media: MediaInfo

  init(detailCase: UIPreviewDetailCase) {
    self.detailCase = detailCase
    _media = State(initialValue: UIPreviewFixtures.installDetail(detailCase))
  }

  var body: some View {
    UIPreviewLoggedInRootView(
      selectedTab: .home,
      permissions: detailCase.permissions,
      canRequestSuperUserEndpoints: detailCase.permissions.contains(.manage),
      homePreviewDestinations: HomeViewUIPreviewDestinations(
        mediaDetailPresentation: detailCase.presentation,
        mediaDetailSites: UIPreviewFixtures.sites,
        mediaDetailRows: UIPreviewFixtures.detailRows(for: detailCase)
      ),
      homeInitialPath: initialPath
    )
  }

  private var initialPath: NavigationPath {
    var path = NavigationPath()
    path.append(media)
    return path
  }
}

@MainActor
private struct UIPreviewSeasonSceneView: View {
  let seasonCase: UIPreviewSeasonCase
  @StateObject private var viewModel: SubscribeSeasonViewModel

  init(seasonCase: UIPreviewSeasonCase) {
    self.seasonCase = seasonCase
    _viewModel = StateObject(wrappedValue: UIPreviewFixtures.seasonViewModel(seasonCase))
  }

  var body: some View {
    UIPreviewLoggedInRootView(
      selectedTab: .search,
      searchInitialPath: SubscribeSeasonRequest(
        mediaInfo: viewModel.mediaInfo,
        initialSeason: nil
      ).previewNavigationPath(),
      searchPreviewDestinations: SearchViewUIPreviewDestinations(
        seasonViewModel: viewModel,
        seasonPresentation: seasonCase.presentation
      )
    )
    .onAppear {
      UIPreviewFixtures.applyPermissions(seasonCase.permissions)
    }
  }
}

@MainActor
private struct UIPreviewSearchSceneView: View {
  let searchCase: UIPreviewSearchCase

  var body: some View {
    switch searchCase {
    case .notSearched, .unifiedLoading, .unifiedResults, .unifiedLoadingMore, .unifiedShareSheet, .unifiedEmpty, .siteSelection,
      .unifiedResultsNoSubscribePermission, .resourceLoading, .resourceResults, .resourceEmpty:
      UIPreviewLoggedInRootView(
        selectedTab: .search,
        searchCase: searchCase,
        permissions: searchCase.permissions,
        searchPreviewDestinations: SearchViewUIPreviewDestinations(forkShare: searchCase.searchPreviewForkShare),
        showsSearchSiteSelection: searchCase.showsSiteSelection
      )
    case .resourcePageLoading, .resourcePageEmpty, .resourcePageResults, .resourcePageFilterSelection:
      UIPreviewResourceResultScene(
        mode: searchCase.resourcePageMode,
        torrentsPresentation: searchCase.resourceTorrentsPresentation
      )
    }
  }
}

@MainActor
private struct UIPreviewResourceResultScene: View {
  let mode: UIPreviewResourcePageMode
  var torrentsPresentation: TorrentsResultUIPreviewPresentation? = nil

  var body: some View {
    let media = UIPreviewFixtures.baseTVMedia(id: 97_101, title: "边境信号")
    let title = mode == .loading ? "边境信号 · 搜索中" : "边境信号 · 资源结果"
    let request = ResourceSearchRequest(
      keyword: "边境信号",
      type: media.type,
      area: nil,
      title: title,
      year: media.year,
      season: nil,
      mediaInfo: media,
      sites: nil
    )

    UIPreviewLoggedInRootView(
      selectedTab: .search,
      searchInitialPath: request.previewNavigationPath(),
      searchPreviewDestinations: SearchViewUIPreviewDestinations(
        resourceResultViewModel: UIPreviewFixtures.resourceResultViewModel(mode),
        resourceTorrentsPresentation: torrentsPresentation
      )
    )
  }
}

@MainActor
private struct UIPreviewStatusSceneView: View {
  let statusCase: UIPreviewStatusCase

  var body: some View {
    switch statusCase {
    case .statusEmpty, .statusFull:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        statusMode: statusCase.statusMode,
        downloadMode: statusCase == .statusEmpty ? .empty : .multiState,
        transferMode: statusCase == .statusEmpty ? .empty : .aiRedoing
      )
    case .downloadEmpty, .downloadMultiState, .downloadCollapsed, .downloadDeleteConfirmation:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        downloadMode: statusCase.downloadMode,
        downloadPresentation: statusCase.downloadPresentation
      )
    case .transferLoading, .transferLoadingMore, .transferEmpty, .transferAiRedoing, .transferDetail, .transferSingleDelete,
      .transferBatchDelete, .transferBatchReorganize:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        transferMode: statusCase.transferMode,
        transferPresentation: statusCase.transferPresentation
      )
    }
  }
}

@MainActor
private struct UIPreviewSettingsSceneView: View {
  let settingsCase: UIPreviewSettingsCase

  var body: some View {
    UIPreviewLoggedInRootView(
      selectedTab: .system,
      settingsCase: settingsCase,
      permissions: settingsCase.permissions,
      canRequestSuperUserEndpoints: settingsCase.canRequestSuperUserEndpoints,
      systemPresentation: settingsCase.presentation
    )
  }
}

@MainActor
private struct UIPreviewSheetSceneView: View {
  let sheetCase: UIPreviewSheetCase
  @State private var isSheetPresented = false

  init(sheetCase: UIPreviewSheetCase) {
    self.sheetCase = sheetCase
    UIPreviewFixtures.applyPermissions(sheetCase.permissions, canRequestSuperUserEndpoints: true)
  }

  var body: some View {
    VStack(spacing: 24) {
      Text(sheetCase.title)
        .font(.title)
      Button("打开弹窗") {
        isSheetPresented = true
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: $isSheetPresented) {
      sheetContent
    }
    .onAppear {
      Task { @MainActor in
        await Task.yield()
        isSheetPresented = true
      }
    }
  }

  @ViewBuilder
  private var sheetContent: some View {
    switch sheetCase {
    case .subscribeLoading:
      SubscribeSheet(previewViewModel: UIPreviewFixtures.subscribeSheetViewModel(isLoading: true))
        .previewRoot(sheetCase.title)
    case .subscribeMovie:
      SubscribeSheet(previewViewModel: UIPreviewFixtures.subscribeSheetViewModel(type: "电影"))
        .previewRoot(sheetCase.title)
    case .subscribe, .subscribeAdvanced, .subscribeSiteSelection, .subscribeFilterGroupSelection, .subscribeSaving:
      SubscribeSheet(
        previewViewModel: UIPreviewFixtures.subscribeSheetViewModel(
          isSaving: sheetCase == .subscribeSaving
        ),
        presentation: sheetCase.subscribePresentation
      )
        .previewRoot(sheetCase.title)
    case .addDownloadLoading:
      AddDownloadSheet(previewViewModel: UIPreviewFixtures.addDownloadViewModel(isLoading: true))
        .previewRoot(sheetCase.title)
    case .addDownload, .addDownloadAdvanced, .addDownloadSubmitting, .addDownloadNoSearchPermission,
      .addDownloadError:
      AddDownloadSheet(
        previewViewModel: UIPreviewFixtures.addDownloadViewModel(
          isSubmitting: sheetCase == .addDownloadSubmitting
        ),
        presentation: sheetCase.addDownloadPresentation
      )
        .previewRoot(sheetCase.title)
    case .reorganizeLoading:
      ReorganizeSheet(previewViewModel: UIPreviewFixtures.reorganizeViewModel(isLoading: true)) {}
        .previewRoot(sheetCase.title)
    case .reorganize, .reorganizeAdvanced, .reorganizeDouban, .reorganizeSubmitting, .reorganizeError:
      ReorganizeSheet(
        previewViewModel: UIPreviewFixtures.reorganizeViewModel(
          isSubmitting: sheetCase == .reorganizeSubmitting
        ),
        presentation: sheetCase.reorganizePresentation
      ) {}
        .previewRoot(sheetCase.title)
    case .reorganizeBatch:
      ReorganizeSheet(previewViewModel: UIPreviewFixtures.reorganizeBatchViewModel()) {}
        .previewRoot(sheetCase.title)
    case .forkSubscribe:
      ForkSubscribeSheet(
        share: UIPreviewFixtures.previewSubscribeShare,
        onFork: { _ in },
        subscriptionHandler: SubscriptionHandler()
      )
      .previewRoot(sheetCase.title)
    case .seasonDetail:
      SeasonDetailSheet(
        season: UIPreviewFixtures.previewSeasonDetail,
        mediaInfo: UIPreviewFixtures.baseTVMedia(id: 45_301, title: "边境信号")
      )
      .previewRoot(sheetCase.title)
    case .multiSelection:
      UIPreviewMultiSelectionSheet()
        .previewRoot(sheetCase.title)
    }
  }

}

@MainActor
private struct UIPreviewMultiSelectionSheet: View {
  @State private var selected: Set<Int> = [1, 3]

  var body: some View {
    MultiSelectionSheet(
      options: UIPreviewFixtures.sites,
      id: \.id,
      selected: $selected,
      label: { $0.name },
      disabledOptions: [5],
      disabledOptionsTitle: "预览：当前搜索源不可用"
    )
  }
}

@MainActor
private struct UIPreviewComponentSceneView: View {
  let componentCase: UIPreviewComponentCase
  @Binding var navigationPath: NavigationPath

  init(componentCase: UIPreviewComponentCase, navigationPath: Binding<NavigationPath>) {
    self.componentCase = componentCase
    _navigationPath = navigationPath
    UIPreviewFixtures.applyPermissions(componentCase.permissions, canRequestSuperUserEndpoints: true)
  }

  var body: some View {
    switch componentCase {
    case .mediaCards, .mediaCardsContextMenu, .mediaCardsLimitedPermissions:
      NavigationStack(path: $navigationPath) {
        UIPreviewMediaCards(
          navigationPath: $navigationPath,
          showsContextMenu: componentCase != .mediaCards
        )
          .uiPreviewNavigationDestinations(path: $navigationPath)
      }
    case .torrentCards, .torrentCardsNoSearchPermission:
      UIPreviewTorrentCards()
        .previewRoot(componentCase.title)
    case .torrentDownloadSheet:
      UIPreviewTorrentDownloadSheet()
        .previewRoot(componentCase.title)
    case .sheetPickerSelection:
      UIPreviewSheetPickerSelection()
        .previewRoot(componentCase.title)
    case .subscriptionAlert:
      UIPreviewSubscriptionAlert()
        .previewRoot(componentCase.title)
    case .pickers:
      UIPreviewPickerComponents()
        .previewRoot(componentCase.title)
    case .mediaActionLoading, .mediaActionNotFound:
      UIPreviewMediaActionComponents(componentCase: componentCase)
        .previewRoot(componentCase.title)
    case .notification:
      UIPreviewNotificationComponents()
        .previewRoot(componentCase.title)
    }
  }
}

@MainActor
private struct UIPreviewMediaCards: View {
  @Binding var navigationPath: NavigationPath
  let showsContextMenu: Bool
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  private let items: [MediaInfo]

  init(navigationPath: Binding<NavigationPath>, showsContextMenu: Bool) {
    _navigationPath = navigationPath
    self.showsContextMenu = showsContextMenu
    let items = [
      UIPreviewFixtures.movieMedia(id: 98_001, title: "长标题电影：跨越三行也不能挤坏焦点卡片"),
      UIPreviewFixtures.baseTVMedia(id: 98_002, title: "无海报剧集", hasArtwork: false),
      UIPreviewFixtures.collectionMedia(id: 98_003, title: "边境信号系列"),
      UIPreviewFixtures.shareMedia(id: 98_004, title: "订阅分享卡片"),
      UIPreviewFixtures.externalSourceMedia(id: 98_005, title: "外部来源：边境信号"),
    ]
    self.items = items
    Self.installSubscribedContextMenuPreviewTask(for: items)
  }

  private static func installSubscribedContextMenuPreviewTask(for items: [MediaInfo]) {
    guard !items.isEmpty else { return }
    let subscribedItem = items[0]
    let task = MediaPreloadTask(partialMedia: subscribedItem)
    task.fullDetail = subscribedItem
    task.isDetailReady = true
    task.tmdbId = subscribedItem.tmdb_id
    task.isSubscribed = true
    MediaPreloader.shared.installPreviewTask(task, for: subscribedItem)
  }

  private var headerView: some View {
    Text("媒体卡片 / 网格 / 加载更多")
      .font(.largeTitle.bold())
      .foregroundStyle(.secondary)
  }

  var body: some View {
    if showsContextMenu {
      MediaGridView(
        items: items,
        isLoading: false,
        isLoadingMore: true,
        onLoadMore: { _ in },
        navigationPath: $navigationPath,
        header: { headerView },
        contextMenu: { item in
          MediaContextMenuItems(
            item: item,
            navigationPath: $navigationPath,
            subscriptionHandler: subscriptionHandler
          )
        },
        onShareTapped: { share in
          guard APIService.shared.canAccess(.subscribe) else { return }
          subscriptionHandler.forkSheetRequest = share
        }
      )
      .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $navigationPath)
      .sheet(item: $subscriptionHandler.forkSheetRequest) { share in
        ForkSubscribeSheet(
          share: share,
          onFork: { _ in },
          subscriptionHandler: subscriptionHandler
        )
      }
    } else {
      MediaGridView(
        items: items,
        isLoading: false,
        isLoadingMore: true,
        onLoadMore: { _ in },
        navigationPath: $navigationPath,
        header: { headerView }
      )
    }
  }
}

private struct UIPreviewTorrentCards: View {
  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 620), spacing: 36)], spacing: 36) {
        ForEach(UIPreviewFixtures.contexts) { context in
          TorrentCard(context: context, overrideMediaInfo: UIPreviewFixtures.baseTVMedia(id: 98_011, title: "边境信号"))
        }
      }
      .padding(60)
    }
    .focusSection()
  }
}

private struct UIPreviewTorrentDownloadSheet: View {
  @StateObject private var notificationManager = NotificationManager()
  @State private var isSheetPresented = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("种子卡片下载入口")
          .font(.largeTitle.bold())
          .foregroundStyle(.secondary)

        TorrentCard(
          context: UIPreviewFixtures.contexts[0],
          overrideMediaInfo: UIPreviewFixtures.baseTVMedia(id: 98_012, title: "边境信号")
        )
        .frame(maxWidth: 620)
      }
      .padding(80)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .focusSection()
    .sheet(isPresented: $isSheetPresented) {
      AddDownloadSheet(previewViewModel: UIPreviewFixtures.addDownloadViewModel())
        .previewRoot("组件 · 种子卡片下载弹窗")
        .environmentObject(notificationManager)
        .overlay(alignment: .topTrailing) {
          notificationOverlay
        }
    }
    .overlay(alignment: .topTrailing) {
      notificationOverlay
    }
    .environmentObject(notificationManager)
    .onAppear {
      Task { @MainActor in
        await Task.yield()
        isSheetPresented = true
      }
    }
  }

  @ViewBuilder
  private var notificationOverlay: some View {
    if notificationManager.isShowing {
      NotificationView(
        message: notificationManager.message,
        type: notificationManager.type
      )
      .padding(.top, 60)
      .padding(.trailing, 60)
      .transition(.move(edge: .top).combined(with: .opacity))
    }
  }
}

private struct UIPreviewPickerComponents: View {
  @State private var selectedCategory: RecommendCategory = .movie
  @State private var selectedShelf: RecommendShelf? = RecommendViewModel.allShelves.first
  @State private var pickerSelection = "1080p"
  @State private var text = "边境信号 S01E01"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 40) {
        CategoryPickerView(selectedCategory: $selectedCategory)

        ShelfPicker(
          shelves: RecommendViewModel.allShelves,
          selectedShelf: $selectedShelf
        )

        VStack(spacing: 16) {
          SheetPicker(
            title: "分辨率",
            selection: $pickerSelection,
            options: [
              PickerOption(title: "全部", value: ""),
              PickerOption(title: "1080P", value: "1080p"),
              PickerOption(title: "4K", value: "4k"),
            ]
          )
          SheetTextField(title: "搜索词", placeholder: "输入关键字", text: $text)
        }
        .frame(width: 980)
        .applySheetStyles()
      }
      .padding(80)
    }
    .focusSection()
  }
}

private struct UIPreviewSheetPickerSelection: View {
  @State private var pickerSelection = "1080p"

  var body: some View {
    VStack {
      SheetPicker(
        title: "分辨率",
        selection: $pickerSelection,
        options: [
          PickerOption(title: "全部", value: ""),
          PickerOption(title: "1080P", value: "1080p"),
          PickerOption(title: "4K", value: "4k"),
        ],
        uiPreviewPresentation: .options
      )
      .frame(width: 980)
      .applySheetStyles()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct UIPreviewSubscriptionAlert: View {
  @StateObject private var handler = SubscriptionHandler()
  @State private var navigationPath = NavigationPath()
  @FocusState private var isReturnAnchorFocused: Bool

  var body: some View {
    ZStack {
      VStack(spacing: 24) {
        Image(systemName: "bell.badge")
          .font(.system(size: 90, weight: .semibold))
        Text("组件 · 订阅结果提示")
          .font(.largeTitle.bold())
        Text("全局订阅动作通知")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Color.clear
        .frame(width: 1, height: 1)
        .focusable()
        .focused($isReturnAnchorFocused)
        .accessibilityHidden(true)
    }
    .mediaSubscriptionAlerts(using: handler, navigationPath: $navigationPath)
    .onAppear {
      isReturnAnchorFocused = true
      Task { @MainActor in
        await Task.yield()
        handler.showNotification(message: "已订阅，请勿重复操作", type: .warning)
      }
    }
  }
}

@MainActor
private struct UIPreviewMediaActionComponents: View {
  let componentCase: UIPreviewComponentCase
  @StateObject private var handler = MediaActionHandler()
  @FocusState private var isReturnAnchorFocused: Bool

  var body: some View {
    ZStack {
      VStack(spacing: 24) {
        Image(systemName: "film.stack")
          .font(.system(size: 90, weight: .semibold))
        Text(componentCase.title)
          .font(.largeTitle.bold())
        Text(componentCase.note)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Color.clear
        .frame(width: 1, height: 1)
        .focusable()
        .focused($isReturnAnchorFocused)
        .accessibilityHidden(true)
    }
    .mediaActionAlerts()
    .environmentObject(handler)
    .onAppear {
      isReturnAnchorFocused = true
      Task { @MainActor in
        await Task.yield()
        switch componentCase {
        case .mediaActionLoading:
          handler.isRecognizingTmdb = true
        case .mediaActionNotFound:
          handler.showTMDBNotFoundAlert = true
        case .mediaCards, .mediaCardsContextMenu, .mediaCardsLimitedPermissions, .torrentCards, .torrentCardsNoSearchPermission,
          .torrentDownloadSheet, .sheetPickerSelection, .subscriptionAlert, .pickers, .notification:
          break
        }
      }
    }
  }
}

private struct UIPreviewNotificationComponents: View {
  @StateObject private var manager = NotificationManager()
  @FocusState private var isReturnAnchorFocused: Bool

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 24) {
        NotificationView(message: "信息提示：正在使用 UI 预览目录", type: .info)
        NotificationView(message: "成功提示：订阅已保存", type: .success)
        NotificationView(message: "警告提示：站点响应较慢", type: .warning)
        NotificationView(message: "错误提示：搜索任务失败", type: .error)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if manager.isShowing {
        NotificationView(message: manager.message, type: manager.type)
          .padding(.top, 60)
          .padding(.trailing, 60)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      Color.clear
        .frame(width: 1, height: 1)
        .focusable()
        .focused($isReturnAnchorFocused)
        .accessibilityHidden(true)
    }
    .onAppear {
      isReturnAnchorFocused = true
      manager.show(message: "悬浮通知预览", type: .success, duration: 20)
    }
  }
}

@MainActor
private struct UIPreviewPushedMediaDetailView: View {
  let media: MediaInfo
  @Binding var path: NavigationPath

  init(media: MediaInfo, path: Binding<NavigationPath>) {
    self.media = media
    _path = path
    UIPreviewFixtures.installReadyDetail(media)
  }

  var body: some View {
    MediaDetailContainerView(media: media, navigationPath: $path)
  }
}

private extension View {
  func previewRoot(_ title: String) -> some View {
    _ = title
    return self
  }

  func uiPreviewNavigationDestinations(path: Binding<NavigationPath>) -> some View {
    self
      .navigationDestination(for: MediaInfo.self) { media in
        UIPreviewPushedMediaDetailView(media: media, path: path)
      }
      .navigationDestination(for: Person.self) { person in
        PersonDetailView(person: person, navigationPath: path)
      }
      .navigationDestination(for: ResourceSearchRequest.self) { request in
        ResourceResultView(
          title: request.title ?? "资源搜索",
          mediaInfo: request.mediaInfo,
          previewViewModel: UIPreviewFixtures.resourceResultViewModel(.results)
        )
      }
      .navigationDestination(for: SubscribeSeasonRequest.self) { request in
        SubscribeSeasonView(
          previewViewModel: UIPreviewFixtures.seasonViewModel(
            mediaInfo: request.mediaInfo,
            initialSeason: request.initialSeason
          )
        )
      }
  }
}

private extension Hashable {
  func previewNavigationPath() -> NavigationPath {
    var path = NavigationPath()
    path.append(self)
    return path
  }
}

private struct UIPreviewSection: Identifiable {
  let id: String
  let title: String
  let scenes: [UIPreviewScene]
}

private struct UIPreviewScene: Identifiable, Hashable {
  let id: String
  let title: String
  let note: String
  let kind: UIPreviewSceneKind
}

private enum UIPreviewSceneKind: Hashable {
  case app(UIPreviewAppCase)
  case page(UIPreviewPageCase)
  case detail(UIPreviewDetailCase)
  case season(UIPreviewSeasonCase)
  case search(UIPreviewSearchCase)
  case status(UIPreviewStatusCase)
  case settings(UIPreviewSettingsCase)
  case sheet(UIPreviewSheetCase)
  case component(UIPreviewComponentCase)
}

private extension UIPreviewSceneKind {
  var note: String {
    switch self {
    case .app(let previewCase):
      return previewCase.note
    case .page(let previewCase):
      return previewCase.note
    case .detail(let detailCase):
      return detailCase.note
    case .season(let seasonCase):
      return seasonCase.note
    case .search(let searchCase):
      return searchCase.note
    case .status(let statusCase):
      return statusCase.note
    case .settings(let settingsCase):
      return settingsCase.note
    case .sheet(let sheetCase):
      return sheetCase.note
    case .component(let componentCase):
      return componentCase.note
    }
  }
}

private enum UIPreviewCatalog {
  static var firstSectionID: String? {
    sections.first?.id
  }

  static func scene(id: String?) -> UIPreviewScene? {
    guard let id else { return nil }
    return sections.lazy.flatMap(\.scenes).first { $0.id == id }
  }

  static let sections: [UIPreviewSection] = [
    UIPreviewSection(
      id: "app",
      title: "App 入口 / Tab 页面",
      scenes: [
        scene(.app(.loggedIn), id: "app-loggedIn", title: "启动入口 · 正常已登录"),
        scene(.app(.startupPreparing), id: "app-startupPreparing", title: "启动入口 · 启动会话准备中"),
        scene(.app(.loggedInLimitedTabs), id: "app-loggedInLimitedTabs", title: "启动入口 · 低权限 Tab"),
        scene(.app(.backendVersionWarning), id: "app-backendVersionWarning", title: "启动入口 · 后端版本告警"),
        scene(.app(.accountPermissionWarning), id: "app-accountPermissionWarning", title: "启动入口 · 账号权限告警"),
        scene(.app(.login), id: "app-login", title: "启动入口 · 登录页"),
        scene(.app(.loginReady), id: "app-loginReady", title: "启动入口 · 可提交登录"),
        scene(.app(.loginLoading), id: "app-loginLoading", title: "启动入口 · 登录中"),
        scene(.app(.loginFailed), id: "app-loginFailed", title: "启动入口 · 登录失败"),
      ]
    ),
    UIPreviewSection(
      id: "detail",
      title: "详情页",
      scenes: [
        scene(.detail(.loading), id: "detail-loading", title: "详情页 · 加载中"),
        scene(.detail(.detailLoadFailed), id: "detail-detailLoadFailed", title: "详情页 · 详情加载失败"),
        scene(.detail(.movieUnsubscribed), id: "detail-movieUnsubscribed", title: "详情页 · 电影，未订阅"),
        scene(.detail(.movieSubscribed), id: "detail-movieSubscribed", title: "详情页 · 电影，已订阅"),
        scene(.detail(.tvWithSeasons), id: "detail-tvWithSeasons", title: "详情页 · 电视剧，有分季"),
        scene(
          .detail(.tvWithSeasonsNoSubscribePermission),
          id: "detail-tvWithSeasonsNoSubscribePermission",
          title: "详情页 · 有分季且无订阅权限"
        ),
        scene(.detail(.tvWithoutSeasons), id: "detail-tvWithoutSeasons", title: "详情页 · 电视剧，无分季"),
        scene(.detail(.seasonLoadFailed), id: "detail-seasonLoadFailed", title: "详情页 · 分季加载失败"),
        scene(.detail(.noArtwork), id: "detail-noArtwork", title: "详情页 · 无海报 / 无背景图"),
        scene(.detail(.contentPage), id: "detail-contentPage", title: "详情页 · 第二页内容"),
        scene(
          .detail(.contentPageRowsLoadingMore),
          id: "detail-contentPageRowsLoadingMore",
          title: "详情页 · 第二页行加载更多"
        ),
        scene(
          .detail(.contentPageNoSearchAndNoSubscribePermission),
          id: "detail-contentPageNoSearchAndNoSubscribePermission",
          title: "详情页 · 第二页无操作权限"
        ),
        scene(
          .detail(.contentPageSingleEpisodeGroup),
          id: "detail-contentPageSingleEpisodeGroup",
          title: "详情页 · 分季单剧集组"
        ),
        scene(
          .detail(.contentPageManySeasons),
          id: "detail-contentPageManySeasons",
          title: "详情页 · 多分季 / 多剧集组"
        ),
        scene(.detail(.tmdbJumpLoading), id: "detail-tmdbJumpLoading", title: "详情页 · TMDB 跳转识别中"),
        scene(.detail(.siteSelection), id: "detail-siteSelection", title: "详情页 · 站点选择弹窗"),
        scene(.detail(.subscribeSheet), id: "detail-subscribeSheet", title: "详情页 · 订阅弹窗"),
        scene(.detail(.unsubscribeConfirmation), id: "detail-unsubscribeConfirmation", title: "详情页 · 取消订阅确认"),
        scene(.detail(.unsubscribing), id: "detail-unsubscribing", title: "详情页 · 取消订阅中"),
        scene(.detail(.noSubscribePermission), id: "detail-noSubscribePermission", title: "详情页 · 无订阅权限"),
        scene(.detail(.noSearchPermission), id: "detail-noSearchPermission", title: "详情页 · 无搜索权限"),
        scene(
          .detail(.tvWithoutSeasonsNoSubscribePermission),
          id: "detail-tvWithoutSeasonsNoSubscribePermission",
          title: "详情页 · 无分季且无订阅权限"
        ),
        scene(
          .detail(.tvWithoutSeasonsNoSearchPermission),
          id: "detail-tvWithoutSeasonsNoSearchPermission",
          title: "详情页 · 无分季且无搜索权限"
        ),
        scene(
          .detail(.noSearchAndNoSubscribePermission),
          id: "detail-noSearchAndNoSubscribePermission",
          title: "详情页 · 无搜索且无订阅权限"
        ),
      ]
    ),
    UIPreviewSection(
      id: "season",
      title: "分季页",
      scenes: [
        scene(.season(.loading), id: "season-loading", title: "分季页 · 加载中"),
        scene(.season(.seasons), id: "season-seasons", title: "分季页 · 普通多季"),
        scene(.season(.empty), id: "season-empty", title: "分季页 · 空数据"),
        scene(.season(.failed), id: "season-failed", title: "分季页 · 加载失败"),
        scene(.season(.mixedSubscription), id: "season-mixedSubscription", title: "分季页 · 已订阅 / 缺集混合"),
        scene(.season(.noSubscribePermission), id: "season-noSubscribePermission", title: "分季页 · 无订阅权限"),
        scene(.season(.seasonDetail), id: "season-seasonDetail", title: "分季页 · 分季详情弹窗"),
        scene(.season(.subscribeSheet), id: "season-subscribeSheet", title: "分季页 · 新增订阅弹窗"),
        scene(.season(.unsubscribeConfirmation), id: "season-unsubscribeConfirmation", title: "分季页 · 取消订阅确认"),
      ]
    ),
    UIPreviewSection(
      id: "page",
      title: "页面入口",
      scenes: [
        scene(.page(.homeLoading), id: "page-homeLoading", title: "首页 · 加载中"),
        scene(.page(.homeEmpty), id: "page-homeEmpty", title: "首页 · 空数据"),
        scene(.page(.homeFull), id: "page-homeFull", title: "首页 · 完整数据"),
        scene(.page(.homeLatestEmptyServer), id: "page-homeLatestEmptyServer", title: "首页 · 最近添加空服务器"),
        scene(.page(.homeSubscriptionsOnly), id: "page-homeSubscriptionsOnly", title: "首页 · 仅订阅"),
        scene(.page(.homeNoSubscribePermission), id: "page-homeNoSubscribePermission", title: "首页 · 无订阅权限"),
        scene(.page(.homeNoSearchPermission), id: "page-homeNoSearchPermission", title: "首页 · 无搜索权限"),
        scene(.page(.homeSubscribeSheet), id: "page-homeSubscribeSheet", title: "首页 · 订阅编辑弹窗"),
        scene(.page(.homeUnsubscribeConfirmation), id: "page-homeUnsubscribeConfirmation", title: "首页 · 取消订阅确认"),
        scene(.page(.recommendInitial), id: "page-recommendInitial", title: "推荐 · 初始化中"),
        scene(.page(.recommendLoading), id: "page-recommendLoading", title: "推荐 · 加载中"),
        scene(.page(.recommendEmpty), id: "page-recommendEmpty", title: "推荐 · 空数据"),
        scene(.page(.recommendFull), id: "page-recommendFull", title: "推荐 · 完整数据"),
        scene(.page(.recommendLimitedPermissions), id: "page-recommendLimitedPermissions", title: "推荐 · 低权限菜单"),
        scene(.page(.exploreInitial), id: "page-exploreInitial", title: "探索 · 初始化中"),
        scene(.page(.exploreLoading), id: "page-exploreLoading", title: "探索 · 加载中"),
        scene(.page(.exploreTmdb), id: "page-exploreTmdb", title: "探索 · TMDB 筛选"),
        scene(.page(.exploreDouban), id: "page-exploreDouban", title: "探索 · 豆瓣筛选"),
        scene(.page(.exploreBangumi), id: "page-exploreBangumi", title: "探索 · Bangumi 筛选"),
        scene(.page(.explorePopular), id: "page-explorePopular", title: "探索 · 热门订阅"),
        scene(.page(.exploreShare), id: "page-exploreShare", title: "探索 · 订阅分享"),
        scene(.page(.exploreShareSheet), id: "page-exploreShareSheet", title: "探索 · 订阅分享弹窗"),
        scene(
          .page(.exploreNoSubscribePermission),
          id: "page-exploreNoSubscribePermission",
          title: "探索 · 无订阅权限"
        ),
        scene(.page(.exploreEmpty), id: "page-exploreEmpty", title: "探索 · 空结果"),
        scene(.page(.collectionLoading), id: "page-collectionLoading", title: "合集详情 · 加载中"),
        scene(.page(.collectionEmpty), id: "page-collectionEmpty", title: "合集详情 · 空数据"),
        scene(.page(.collectionFull), id: "page-collectionFull", title: "合集详情 · 完整数据"),
        scene(.page(.collectionLoadingMore), id: "page-collectionLoadingMore", title: "合集详情 · 加载更多中"),
        scene(.page(.personLoading), id: "page-personLoading", title: "人物详情 · 加载中"),
        scene(.page(.personNoBiography), id: "page-personNoBiography", title: "人物详情 · 无简介"),
        scene(.page(.personBiographySheet), id: "page-personBiographySheet", title: "人物详情 · 简介弹窗"),
        scene(.page(.personFull), id: "page-personFull", title: "人物详情 · 完整数据"),
        scene(.page(.personLoadingMore), id: "page-personLoadingMore", title: "人物详情 · 加载更多中"),
      ]
    ),
    UIPreviewSection(
      id: "search",
      title: "搜索链路",
      scenes: [
        scene(.search(.notSearched), id: "search-notSearched", title: "搜索 · 未搜索"),
        scene(.search(.unifiedLoading), id: "search-unifiedLoading", title: "搜索 · 聚合加载中"),
        scene(.search(.unifiedResults), id: "search-unifiedResults", title: "搜索 · 聚合结果"),
        scene(.search(.unifiedLoadingMore), id: "search-unifiedLoadingMore", title: "搜索 · 聚合行加载更多"),
        scene(.search(.unifiedShareSheet), id: "search-unifiedShareSheet", title: "搜索 · 订阅分享弹窗"),
        scene(
          .search(.unifiedResultsNoSubscribePermission),
          id: "search-unifiedResultsNoSubscribePermission",
          title: "搜索 · 聚合结果无订阅权限"
        ),
        scene(.search(.unifiedEmpty), id: "search-unifiedEmpty", title: "搜索 · 聚合空结果"),
        scene(.search(.siteSelection), id: "search-siteSelection", title: "搜索 · 站点选择弹窗"),
        scene(.search(.resourceLoading), id: "search-resourceLoading", title: "搜索 · 资源加载中"),
        scene(.search(.resourceResults), id: "search-resourceResults", title: "搜索 · 资源结果"),
        scene(.search(.resourceEmpty), id: "search-resourceEmpty", title: "搜索 · 资源空结果"),
        scene(.search(.resourcePageLoading), id: "search-resourcePageLoading", title: "资源结果页 · 加载中"),
        scene(.search(.resourcePageEmpty), id: "search-resourcePageEmpty", title: "资源结果页 · 空数据"),
        scene(.search(.resourcePageResults), id: "search-resourcePageResults", title: "资源结果页 · 完整数据"),
        scene(.search(.resourcePageFilterSelection), id: "search-resourcePageFilterSelection", title: "资源结果页 · 筛选弹窗"),
      ]
    ),
    UIPreviewSection(
      id: "status",
      title: "状态 / 任务",
      scenes: [
        scene(.status(.statusEmpty), id: "status-statusEmpty", title: "状态页 · 空权限 / 空数据"),
        scene(.status(.statusFull), id: "status-statusFull", title: "状态页 · 完整数据"),
        scene(.status(.downloadEmpty), id: "status-downloadEmpty", title: "下载任务 · 空数据"),
        scene(.status(.downloadMultiState), id: "status-downloadMultiState", title: "下载任务 · 多状态任务"),
        scene(.status(.downloadCollapsed), id: "status-downloadCollapsed", title: "下载任务 · 收起"),
        scene(.status(.downloadDeleteConfirmation), id: "status-downloadDeleteConfirmation", title: "下载任务 · 删除确认"),
        scene(.status(.transferLoading), id: "status-transferLoading", title: "整理历史 · 加载中"),
        scene(.status(.transferLoadingMore), id: "status-transferLoadingMore", title: "整理历史 · 加载更多中"),
        scene(.status(.transferEmpty), id: "status-transferEmpty", title: "整理历史 · 空数据"),
        scene(.status(.transferAiRedoing), id: "status-transferAiRedoing", title: "整理历史 · 多选 / AI 整理中"),
        scene(.status(.transferDetail), id: "status-transferDetail", title: "整理历史 · 详情弹窗"),
        scene(.status(.transferSingleDelete), id: "status-transferSingleDelete", title: "整理历史 · 单项删除确认"),
        scene(.status(.transferBatchDelete), id: "status-transferBatchDelete", title: "整理历史 · 批量删除确认"),
        scene(.status(.transferBatchReorganize), id: "status-transferBatchReorganize", title: "整理历史 · 批量重整弹窗"),
      ]
    ),
    UIPreviewSection(
      id: "settings",
      title: "设置",
      scenes: [
        scene(.settings(.fullAccess), id: "settings-fullAccess", title: "设置 · 全权限"),
        scene(.settings(.noSubscribe), id: "settings-noSubscribe", title: "设置 · 无订阅权限"),
        scene(.settings(.noSearch), id: "settings-noSearch", title: "设置 · 无搜索权限"),
        scene(.settings(.noSuperUser), id: "settings-noSuperUser", title: "设置 · 无超级用户权限"),
        scene(.settings(.limitedPermissions), id: "settings-limitedPermissions", title: "设置 · 低权限"),
        scene(.settings(.connection), id: "settings-connection", title: "设置 · 连接页"),
        scene(.settings(.connectionRefreshing), id: "settings-connectionRefreshing", title: "设置 · 刷新登录凭据中"),
        scene(.settings(.siteSelection), id: "settings-siteSelection", title: "设置 · 站点选择页"),
        scene(.settings(.siteEmpty), id: "settings-siteEmpty", title: "设置 · 站点空列表"),
        scene(.settings(.hardFilter), id: "settings-hardFilter", title: "设置 · 硬过滤页"),
        scene(.settings(.hardFilterLoading), id: "settings-hardFilterLoading", title: "设置 · 硬过滤加载中"),
        scene(.settings(.hardFilterEmpty), id: "settings-hardFilterEmpty", title: "设置 · 硬过滤空列表"),
        scene(.settings(.softFilter), id: "settings-softFilter", title: "设置 · 软过滤页"),
        scene(.settings(.softFilterLoading), id: "settings-softFilterLoading", title: "设置 · 软过滤加载中"),
        scene(.settings(.softFilterEmpty), id: "settings-softFilterEmpty", title: "设置 · 软过滤空列表"),
        scene(.settings(.siteLoading), id: "settings-siteLoading", title: "设置 · 站点加载中"),
        scene(.settings(.rulesLoading), id: "settings-rulesLoading", title: "设置 · 过滤规则加载中"),
        scene(.settings(.rulesEmpty), id: "settings-rulesEmpty", title: "设置 · 过滤规则空列表"),
        scene(.settings(.appInfo), id: "settings-appInfo", title: "设置 · APP 信息"),
        scene(.settings(.logoutConfirmation), id: "settings-logoutConfirmation", title: "设置 · 退出登录确认"),
      ]
    ),
    UIPreviewSection(
      id: "sheet",
      title: "弹窗",
      scenes: [
        scene(.sheet(.subscribeLoading), id: "sheet-subscribeLoading", title: "订阅弹窗 · 加载中"),
        scene(.sheet(.subscribe), id: "sheet-subscribe", title: "订阅弹窗 · 新增"),
        scene(.sheet(.subscribeMovie), id: "sheet-subscribeMovie", title: "订阅弹窗 · 电影新增"),
        scene(.sheet(.subscribeAdvanced), id: "sheet-subscribeAdvanced", title: "订阅弹窗 · 高级配置"),
        scene(.sheet(.subscribeSiteSelection), id: "sheet-subscribeSiteSelection", title: "订阅弹窗 · 站点选择"),
        scene(
          .sheet(.subscribeFilterGroupSelection),
          id: "sheet-subscribeFilterGroupSelection",
          title: "订阅弹窗 · 过滤组选择"
        ),
        scene(.sheet(.subscribeSaving), id: "sheet-subscribeSaving", title: "订阅弹窗 · 保存中"),
        scene(.sheet(.forkSubscribe), id: "sheet-forkSubscribe", title: "订阅分享弹窗 · 复用"),
        scene(.sheet(.addDownloadLoading), id: "sheet-addDownloadLoading", title: "下载弹窗 · 加载中"),
        scene(.sheet(.addDownload), id: "sheet-addDownload", title: "下载弹窗 · 添加下载"),
        scene(.sheet(.addDownloadAdvanced), id: "sheet-addDownloadAdvanced", title: "下载弹窗 · 高级配置"),
        scene(.sheet(.addDownloadSubmitting), id: "sheet-addDownloadSubmitting", title: "下载弹窗 · 提交中"),
        scene(
          .sheet(.addDownloadNoSearchPermission),
          id: "sheet-addDownloadNoSearchPermission",
          title: "下载弹窗 · 无搜索权限"
        ),
        scene(.sheet(.addDownloadError), id: "sheet-addDownloadError", title: "下载弹窗 · 失败反馈"),
        scene(.sheet(.reorganizeLoading), id: "sheet-reorganizeLoading", title: "整理弹窗 · 加载中"),
        scene(.sheet(.reorganize), id: "sheet-reorganize", title: "整理弹窗 · 单项重整"),
        scene(.sheet(.reorganizeBatch), id: "sheet-reorganizeBatch", title: "整理弹窗 · 批量重整"),
        scene(.sheet(.reorganizeDouban), id: "sheet-reorganizeDouban", title: "整理弹窗 · 豆瓣识别源"),
        scene(.sheet(.reorganizeAdvanced), id: "sheet-reorganizeAdvanced", title: "整理弹窗 · 高级配置"),
        scene(.sheet(.reorganizeSubmitting), id: "sheet-reorganizeSubmitting", title: "整理弹窗 · 提交中"),
        scene(.sheet(.reorganizeError), id: "sheet-reorganizeError", title: "整理弹窗 · 失败反馈"),
        scene(.sheet(.seasonDetail), id: "sheet-seasonDetail", title: "分季详情弹窗"),
        scene(.sheet(.multiSelection), id: "sheet-multiSelection", title: "多选弹窗 · 站点选择"),
      ]
    ),
    UIPreviewSection(
      id: "component",
      title: "核心组件",
      scenes: [
        scene(.component(.mediaCards), id: "component-mediaCards", title: "组件 · 媒体卡片"),
        scene(
          .component(.mediaCardsContextMenu),
          id: "component-mediaCardsContextMenu",
          title: "组件 · 媒体卡片完整菜单"
        ),
        scene(
          .component(.mediaCardsLimitedPermissions),
          id: "component-mediaCardsLimitedPermissions",
          title: "组件 · 媒体卡片低权限菜单"
        ),
        scene(.component(.torrentCards), id: "component-torrentCards", title: "组件 · 种子卡片"),
        scene(
          .component(.torrentCardsNoSearchPermission),
          id: "component-torrentCardsNoSearchPermission",
          title: "组件 · 种子卡片无搜索权限"
        ),
        scene(.component(.torrentDownloadSheet), id: "component-torrentDownloadSheet", title: "组件 · 种子卡片下载弹窗"),
        scene(.component(.sheetPickerSelection), id: "component-sheetPickerSelection", title: "组件 · 单选弹窗"),
        scene(.component(.subscriptionAlert), id: "component-subscriptionAlert", title: "组件 · 订阅结果提示"),
        scene(.component(.pickers), id: "component-pickers", title: "组件 · 选择器 / 输入框"),
        scene(.component(.mediaActionLoading), id: "component-mediaActionLoading", title: "组件 · TMDB 识别中"),
        scene(.component(.mediaActionNotFound), id: "component-mediaActionNotFound", title: "组件 · TMDB 未识别提示"),
        scene(.component(.notification), id: "component-notification", title: "组件 · 通知"),
      ]
    ),
  ]

  private static func scene(
    _ kind: UIPreviewSceneKind,
    id: String,
    title: String
  ) -> UIPreviewScene {
    UIPreviewScene(
      id: id,
      title: title,
      note: kind.note,
      kind: kind
    )
  }
}

private protocol UIPreviewCase: CaseIterable, Hashable, RawRepresentable where RawValue == String {
  var title: String { get }
  var note: String { get }
}

private enum UIPreviewAppCase: String, UIPreviewCase {
  case loggedIn
  case startupPreparing
  case loggedInLimitedTabs
  case backendVersionWarning
  case accountPermissionWarning
  case login
  case loginReady
  case loginLoading
  case loginFailed

  var title: String {
    switch self {
    case .loggedIn: return "启动入口 · 正常已登录"
    case .startupPreparing: return "启动入口 · 启动会话准备中"
    case .loggedInLimitedTabs: return "启动入口 · 低权限 Tab"
    case .backendVersionWarning: return "启动入口 · 后端版本告警"
    case .accountPermissionWarning: return "启动入口 · 账号权限告警"
    case .login: return "启动入口 · 登录页"
    case .loginReady: return "启动入口 · 可提交登录"
    case .loginLoading: return "启动入口 · 登录中"
    case .loginFailed: return "启动入口 · 登录失败"
    }
  }

  var note: String {
    switch self {
    case .loggedIn: return "TabView 根入口，覆盖首页/推荐/探索/搜索/状态/设置焦点切换。"
    case .startupPreparing: return "已登录启动时刷新存储会话的全屏准备状态。"
    case .loggedInLimitedTabs: return "低权限账号只显示可访问 Tab，检查 Tab 数量变化和焦点落点。"
    case .backendVersionWarning: return "启动后弹出 MoviePilot 后端版本兼容告警。"
    case .accountPermissionWarning: return "启动后弹出账号推荐权限不足告警。"
    case .login: return "未登录根入口，检查空表单和禁用登录按钮。"
    case .loginReady: return "未登录根入口，表单已填充，检查可提交按钮焦点。"
    case .loginLoading: return "登录按钮进入 ProgressView，检查按钮宽度和焦点稳定。"
    case .loginFailed: return "登录失败红色错误文案，检查表单间距和按钮状态。"
    }
  }
}

private enum UIPreviewHomeMode { case loading, empty, full, latestEmptyServer, subscriptionsOnly, noSubscribePermission }
private enum UIPreviewRecommendMode { case initial, loading, empty, full }
private enum UIPreviewExploreMode { case initial, loading, tmdb, douban, bangumi, popular, share, noSubscribePermission, empty }
private enum UIPreviewCollectionMode { case loading, empty, full, loadingMore }
private enum UIPreviewPersonMode { case loading, noBiography, full, biographySheet, loadingMore }

private enum UIPreviewPageCase: String, UIPreviewCase {
  case homeLoading
  case homeEmpty
  case homeFull
  case homeLatestEmptyServer
  case homeSubscriptionsOnly
  case homeNoSubscribePermission
  case homeNoSearchPermission
  case homeSubscribeSheet
  case homeUnsubscribeConfirmation
  case recommendInitial
  case recommendLoading
  case recommendEmpty
  case recommendFull
  case recommendLimitedPermissions
  case exploreInitial
  case exploreLoading
  case exploreTmdb
  case exploreDouban
  case exploreBangumi
  case explorePopular
  case exploreShare
  case exploreShareSheet
  case exploreNoSubscribePermission
  case exploreEmpty
  case collectionLoading
  case collectionEmpty
  case collectionFull
  case collectionLoadingMore
  case personLoading
  case personNoBiography
  case personBiographySheet
  case personFull
  case personLoadingMore

  var title: String {
    switch self {
    case .homeLoading: return "首页 · 加载中"
    case .homeEmpty: return "首页 · 空数据"
    case .homeFull: return "首页 · 完整数据"
    case .homeLatestEmptyServer: return "首页 · 最近添加空服务器"
    case .homeSubscriptionsOnly: return "首页 · 仅订阅"
    case .homeNoSubscribePermission: return "首页 · 无订阅权限"
    case .homeNoSearchPermission: return "首页 · 无搜索权限"
    case .homeSubscribeSheet: return "首页 · 订阅编辑弹窗"
    case .homeUnsubscribeConfirmation: return "首页 · 取消订阅确认"
    case .recommendInitial: return "推荐 · 初始化中"
    case .recommendLoading: return "推荐 · 加载中"
    case .recommendEmpty: return "推荐 · 空数据"
    case .recommendFull: return "推荐 · 完整数据"
    case .recommendLimitedPermissions: return "推荐 · 低权限菜单"
    case .exploreInitial: return "探索 · 初始化中"
    case .exploreLoading: return "探索 · 加载中"
    case .exploreTmdb: return "探索 · TMDB 筛选"
    case .exploreDouban: return "探索 · 豆瓣筛选"
    case .exploreBangumi: return "探索 · Bangumi 筛选"
    case .explorePopular: return "探索 · 热门订阅"
    case .exploreShare: return "探索 · 订阅分享"
    case .exploreShareSheet: return "探索 · 订阅分享弹窗"
    case .exploreNoSubscribePermission: return "探索 · 无订阅权限"
    case .exploreEmpty: return "探索 · 空结果"
    case .collectionLoading: return "合集详情 · 加载中"
    case .collectionEmpty: return "合集详情 · 空数据"
    case .collectionFull: return "合集详情 · 完整数据"
    case .collectionLoadingMore: return "合集详情 · 加载更多中"
    case .personLoading: return "人物详情 · 加载中"
    case .personNoBiography: return "人物详情 · 无简介"
    case .personBiographySheet: return "人物详情 · 简介弹窗"
    case .personFull: return "人物详情 · 完整数据"
    case .personLoadingMore: return "人物详情 · 加载更多中"
    }
  }

  var note: String {
    switch self {
    case .homeLoading: return "首页全屏 Loading，检查 Tab 切入后的焦点落点。"
    case .homeEmpty: return "无最近添加、无电影订阅、无电视剧订阅。"
    case .homeFull: return "最近添加服务器 Picker + 电影/电视剧订阅行 + 行操作菜单。"
    case .homeLatestEmptyServer: return "最近添加服务器存在但当前服务器内容为空，检查空行文案。"
    case .homeSubscriptionsOnly: return "无最近添加服务器，仅显示电影/电视剧订阅行。"
    case .homeNoSubscribePermission: return "缺少订阅权限时，只保留最近添加媒体，订阅行为空。"
    case .homeNoSearchPermission: return "缺少搜索权限时，最近添加卡片菜单不出现搜索资源入口。"
    case .homeSubscribeSheet: return "首页订阅卡片编辑 Sheet。"
    case .homeUnsubscribeConfirmation: return "首页订阅卡片取消订阅确认 Alert。"
    case .recommendInitial: return "推荐页 paginator 尚未初始化。"
    case .recommendLoading: return "推荐页 Paginator 首次加载。"
    case .recommendEmpty: return "推荐页分类/货架存在但网格为空。"
    case .recommendFull: return "推荐页分类、货架和媒体网格完整组合。"
    case .recommendLimitedPermissions: return "推荐页保留发现权限，卡片菜单隐藏订阅和资源搜索入口。"
    case .exploreInitial: return "探索页 paginator 尚未初始化。"
    case .exploreLoading: return "探索页 Paginator 首次加载。"
    case .exploreTmdb: return "探索页 TheMovieDb 多 Picker 过滤器。"
    case .exploreDouban: return "探索页豆瓣排序、风格、地区、年代过滤器。"
    case .exploreBangumi: return "探索页 Bangumi 分类、排序、年份过滤器。"
    case .explorePopular: return "探索页热门订阅排序、风格和评分过滤器。"
    case .exploreShare: return "探索页订阅分享源，卡片触发 Fork 入口。"
    case .exploreShareSheet: return "探索页订阅分享卡片点击后，通过真实 ExploreView sheet 展示 ForkSubscribeSheet。"
    case .exploreNoSubscribePermission: return "探索页缺少订阅权限时，数据源不出现订阅分享。"
    case .exploreEmpty: return "探索页筛选器存在但结果为空。"
    case .collectionLoading: return "合集详情真实根路径加载中。"
    case .collectionEmpty: return "合集详情真实根路径空态。"
    case .collectionFull: return "合集详情网格 + 详情导航。"
    case .collectionLoadingMore: return "合集详情已有内容时底部加载更多中。"
    case .personLoading: return "人物详情简介加载占位 + 作品加载。"
    case .personNoBiography: return "人物详情无简介占位 + 作品网格。"
    case .personBiographySheet: return "人物详情简介 Sheet 展开。"
    case .personFull: return "人物详情头像/简介/作品网格。"
    case .personLoadingMore: return "人物详情已有作品时底部加载更多中。"
    }
  }

  var homeMode: UIPreviewHomeMode {
    switch self {
    case .homeLoading: return .loading
    case .homeEmpty: return .empty
    case .homeLatestEmptyServer: return .latestEmptyServer
    case .homeSubscriptionsOnly: return .subscriptionsOnly
    case .homeNoSubscribePermission: return .noSubscribePermission
    case .homeSubscribeSheet, .homeUnsubscribeConfirmation: return .full
    default: return .full
    }
  }

  var homePresentation: HomeViewUIPreviewPresentation? {
    switch self {
    case .homeSubscribeSheet: return .subscribeSheet
    case .homeUnsubscribeConfirmation: return .unsubscribeConfirmation
    default: return nil
    }
  }

  var recommendMode: UIPreviewRecommendMode {
    switch self {
    case .recommendInitial: return .initial
    case .recommendLoading: return .loading
    case .recommendEmpty: return .empty
    default: return .full
    }
  }

  var exploreMode: UIPreviewExploreMode {
    switch self {
    case .exploreInitial: return .initial
    case .exploreLoading: return .loading
    case .exploreDouban: return .douban
    case .exploreBangumi: return .bangumi
    case .explorePopular: return .popular
    case .exploreShare: return .share
    case .exploreShareSheet: return .share
    case .exploreNoSubscribePermission: return .noSubscribePermission
    case .exploreEmpty: return .empty
    default: return .tmdb
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .homeNoSubscribePermission:
      return [.discovery, .search, .manage]
    case .homeNoSearchPermission:
      return [.discovery, .subscribe, .manage]
    case .exploreNoSubscribePermission:
      return [.discovery, .search, .manage]
    case .recommendLimitedPermissions:
      return [.discovery]
    case .homeLoading, .homeEmpty, .homeFull, .homeLatestEmptyServer, .homeSubscriptionsOnly,
      .homeSubscribeSheet, .homeUnsubscribeConfirmation, .recommendInitial, .recommendLoading,
      .recommendEmpty, .recommendFull, .exploreInitial, .exploreLoading, .exploreTmdb, .exploreDouban,
      .exploreBangumi, .explorePopular, .exploreShare, .exploreShareSheet, .exploreEmpty, .collectionLoading,
      .collectionEmpty, .collectionFull, .collectionLoadingMore, .personLoading, .personNoBiography,
      .personBiographySheet, .personFull, .personLoadingMore:
      return .allPreviewPermissions
    }
  }

  var collectionMode: UIPreviewCollectionMode {
    switch self {
    case .collectionLoading: return .loading
    case .collectionEmpty: return .empty
    case .collectionLoadingMore: return .loadingMore
    default: return .full
    }
  }

  var personMode: UIPreviewPersonMode {
    switch self {
    case .personLoading: return .loading
    case .personNoBiography: return .noBiography
    case .personBiographySheet: return .biographySheet
    case .personLoadingMore: return .loadingMore
    default: return .full
    }
  }

  var explorePreviewForkShare: SubscribeShare? {
    switch self {
    case .exploreShareSheet:
      return UIPreviewFixtures.previewSubscribeShare
    default:
      return nil
    }
  }
}

private enum UIPreviewDetailCase: String, UIPreviewCase {
  case loading
  case detailLoadFailed
  case movieUnsubscribed
  case movieSubscribed
  case tvWithSeasons
  case tvWithSeasonsNoSubscribePermission
  case tvWithoutSeasons
  case seasonLoadFailed
  case noArtwork
  case contentPage
  case contentPageRowsLoadingMore
  case contentPageNoSearchAndNoSubscribePermission
  case contentPageSingleEpisodeGroup
  case contentPageManySeasons
  case tmdbJumpLoading
  case siteSelection
  case subscribeSheet
  case unsubscribeConfirmation
  case unsubscribing
  case noSubscribePermission
  case noSearchPermission
  case tvWithoutSeasonsNoSubscribePermission
  case tvWithoutSeasonsNoSearchPermission
  case noSearchAndNoSubscribePermission

  var title: String {
    switch self {
    case .loading: return "详情页 · 加载中"
    case .detailLoadFailed: return "详情页 · 详情加载失败"
    case .movieUnsubscribed: return "详情页 · 电影，未订阅"
    case .movieSubscribed: return "详情页 · 电影，已订阅"
    case .tvWithSeasons: return "详情页 · 电视剧，有分季"
    case .tvWithSeasonsNoSubscribePermission: return "详情页 · 有分季且无订阅权限"
    case .tvWithoutSeasons: return "详情页 · 电视剧，无分季"
    case .seasonLoadFailed: return "详情页 · 分季加载失败"
    case .noArtwork: return "详情页 · 无海报 / 无背景图"
    case .contentPage: return "详情页 · 第二页内容"
    case .contentPageRowsLoadingMore: return "详情页 · 第二页行加载更多"
    case .contentPageNoSearchAndNoSubscribePermission: return "详情页 · 第二页无操作权限"
    case .contentPageSingleEpisodeGroup: return "详情页 · 分季单剧集组"
    case .contentPageManySeasons: return "详情页 · 多分季 / 多剧集组"
    case .tmdbJumpLoading: return "详情页 · TMDB 跳转识别中"
    case .siteSelection: return "详情页 · 站点选择弹窗"
    case .subscribeSheet: return "详情页 · 订阅弹窗"
    case .unsubscribeConfirmation: return "详情页 · 取消订阅确认"
    case .unsubscribing: return "详情页 · 取消订阅中"
    case .noSubscribePermission: return "详情页 · 无订阅权限"
    case .noSearchPermission: return "详情页 · 无搜索权限"
    case .tvWithoutSeasonsNoSubscribePermission: return "详情页 · 无分季且无订阅权限"
    case .tvWithoutSeasonsNoSearchPermission: return "详情页 · 无分季且无搜索权限"
    case .noSearchAndNoSubscribePermission: return "详情页 · 无搜索且无订阅权限"
    }
  }

  var note: String {
    switch self {
    case .loading: return "保持 Loading 遮罩，验证焦点不会落到下层详情。"
    case .detailLoadFailed: return "完整详情接口失败时，容器退掉 Loading 并显示 partial detail fallback。"
    case .movieUnsubscribed: return "电影直订阅 Header，检查订阅按钮和资源搜索并列。"
    case .movieSubscribed: return "电影已订阅 Header，检查已订阅按钮和取消确认入口。"
    case .tvWithSeasons: return "Header 分季订阅 + 第二页分季横向 Shelf。"
    case .tvWithSeasonsNoSubscribePermission: return "有分季数据但无订阅权限，检查 Header 和分季行不出现订阅入口。"
    case .tvWithoutSeasons: return "分季加载完成但为空，Header 显示“暂无分季信息”，按钮仍可进入第二页。"
    case .seasonLoadFailed: return "分季加载失败时，Header 按钮仍可进入第二页，分季区域保留错误说明。"
    case .noArtwork: return "背景和海报都为空，验证占位背景与文字可读性。"
    case .contentPage: return "详情页第二页内容，检查分季/演职员/推荐行和背景模糊。"
    case .contentPageRowsLoadingMore:
      return "详情页第二页演员、推荐、类似行显示加载更多进度。"
    case .contentPageNoSearchAndNoSubscribePermission:
      return "关闭订阅和搜索后直接进入第二页，检查演员/职员/推荐/类似行焦点和滚动。"
    case .contentPageSingleEpisodeGroup:
      return "分季 Shelf 只有默认剧集组，检查无剧集组 Picker 的布局。"
    case .contentPageManySeasons:
      return "超过 10 季并带多个剧集组，检查展开按钮和查看全部卡片。"
    case .tmdbJumpLoading: return "外部来源详情缺少 TMDB ID，Header 跳转按钮显示识别中。"
    case .siteSelection: return "详情页资源搜索站点选择 Sheet。"
    case .subscribeSheet: return "详情页 Header 订阅弹窗。"
    case .unsubscribeConfirmation: return "详情页 Header 取消订阅确认。"
    case .unsubscribing: return "已订阅电影 Header 中，订阅按钮显示取消订阅进行中的 ProgressView。"
    case .noSubscribePermission: return "隐藏订阅入口，只保留搜索和 TMDB 跳转。"
    case .noSearchPermission: return "隐藏搜索和站点筛选，只保留分季订阅。"
    case .tvWithoutSeasonsNoSubscribePermission: return "无分季数据同时无订阅权限，检查 Header 不出现不可用订阅按钮。"
    case .tvWithoutSeasonsNoSearchPermission: return "无分季数据同时无搜索权限，检查“暂无分季信息”仍可进入第二页。"
    case .noSearchAndNoSubscribePermission: return "隐藏订阅和资源搜索入口，检查“其他信息”成为首选操作。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .noSubscribePermission, .tvWithSeasonsNoSubscribePermission, .tvWithoutSeasonsNoSubscribePermission:
      return [.discovery, .search, .manage]
    case .noSearchPermission, .tvWithoutSeasonsNoSearchPermission:
      return [.discovery, .subscribe, .manage]
    case .contentPageNoSearchAndNoSubscribePermission, .noSearchAndNoSubscribePermission:
      return [.discovery, .manage]
    default:
      return .allPreviewPermissions
    }
  }

  var isSubscribed: Bool {
    self == .movieSubscribed || self == .unsubscribeConfirmation || self == .unsubscribing
  }

  var presentation: MediaDetailUIPreviewPresentation? {
    switch self {
    case .contentPage, .contentPageRowsLoadingMore, .contentPageNoSearchAndNoSubscribePermission,
      .contentPageSingleEpisodeGroup, .contentPageManySeasons:
      return .contentPage
    case .tmdbJumpLoading:
      return .tmdbJumpLoading
    case .siteSelection:
      return .siteSelection
    case .subscribeSheet:
      return .subscribeSheet
    case .unsubscribeConfirmation:
      return .unsubscribeConfirmation
    case .unsubscribing:
      return .unsubscribing
    default:
      return nil
    }
  }
}

private enum UIPreviewSeasonCase: String, UIPreviewCase {
  case loading
  case seasons
  case empty
  case failed
  case mixedSubscription
  case noSubscribePermission
  case seasonDetail
  case subscribeSheet
  case unsubscribeConfirmation

  var title: String {
    switch self {
    case .loading: return "分季页 · 加载中"
    case .seasons: return "分季页 · 普通多季"
    case .empty: return "分季页 · 空数据"
    case .failed: return "分季页 · 加载失败"
    case .mixedSubscription: return "分季页 · 已订阅 / 缺集混合"
    case .noSubscribePermission: return "分季页 · 无订阅权限"
    case .seasonDetail: return "分季页 · 分季详情弹窗"
    case .subscribeSheet: return "分季页 · 新增订阅弹窗"
    case .unsubscribeConfirmation: return "分季页 · 取消订阅确认"
    }
  }

  var note: String {
    switch self {
    case .loading: return "Grid 根路径中的加载态。"
    case .seasons: return "多季卡片、剧集组 Picker 和焦点重定向。"
    case .empty: return "无季集信息空态。"
    case .failed: return "错误 Banner + 空态组合。"
    case .mixedSubscription: return "已订阅、完整入库、部分缺失、整季缺失组合。"
    case .noSubscribePermission: return "缺少订阅权限时，分季卡片显示锁定状态且不出现订阅菜单项。"
    case .seasonDetail: return "分季页卡片详情 Sheet。"
    case .subscribeSheet: return "未订阅分季新增订阅 Sheet。"
    case .unsubscribeConfirmation: return "已订阅分季取消确认 Alert。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .noSubscribePermission:
      return [.discovery, .search, .manage]
    case .loading, .seasons, .empty, .failed, .mixedSubscription, .seasonDetail, .subscribeSheet,
      .unsubscribeConfirmation:
      return .allPreviewPermissions
    }
  }

  var dataMode: UIPreviewSeasonCase {
    switch self {
    case .noSubscribePermission:
      return .seasons
    case .seasonDetail, .subscribeSheet, .unsubscribeConfirmation:
      return .mixedSubscription
    default:
      return self
    }
  }

  var presentation: SubscribeSeasonUIPreviewPresentation? {
    switch self {
    case .seasonDetail:
      return .seasonDetail
    case .subscribeSheet:
      return .subscribeSheet
    case .unsubscribeConfirmation:
      return .unsubscribeConfirmation
    default:
      return nil
    }
  }
}

private enum UIPreviewResourcePageMode { case loading, empty, results }

private enum UIPreviewSearchCase: String, UIPreviewCase {
  case notSearched
  case unifiedLoading
  case unifiedResults
  case unifiedLoadingMore
  case unifiedShareSheet
  case unifiedResultsNoSubscribePermission
  case unifiedEmpty
  case siteSelection
  case resourceLoading
  case resourceResults
  case resourceEmpty
  case resourcePageLoading
  case resourcePageEmpty
  case resourcePageResults
  case resourcePageFilterSelection

  var title: String {
    switch self {
    case .notSearched: return "搜索 · 未搜索"
    case .unifiedLoading: return "搜索 · 聚合加载中"
    case .unifiedResults: return "搜索 · 聚合结果"
    case .unifiedLoadingMore: return "搜索 · 聚合行加载更多"
    case .unifiedShareSheet: return "搜索 · 订阅分享弹窗"
    case .unifiedResultsNoSubscribePermission: return "搜索 · 聚合结果无订阅权限"
    case .unifiedEmpty: return "搜索 · 聚合空结果"
    case .siteSelection: return "搜索 · 站点选择弹窗"
    case .resourceLoading: return "搜索 · 资源加载中"
    case .resourceResults: return "搜索 · 资源结果"
    case .resourceEmpty: return "搜索 · 资源空结果"
    case .resourcePageLoading: return "资源结果页 · 加载中"
    case .resourcePageEmpty: return "资源结果页 · 空数据"
    case .resourcePageResults: return "资源结果页 · 完整数据"
    case .resourcePageFilterSelection: return "资源结果页 · 筛选弹窗"
    }
  }

  var note: String {
    switch self {
    case .notSearched: return "搜索页未输入/未提交时，仅显示顶部搜索类型区。"
    case .unifiedLoading: return "聚合搜索提交后加载中。"
    case .unifiedResults: return "最佳结果、电影、电视剧、合集、人物、订阅分享多行组合。"
    case .unifiedLoadingMore: return "聚合搜索已有结果时，各横向结果行底部显示加载更多进度。"
    case .unifiedShareSheet: return "聚合搜索订阅分享点击后，通过真实 SearchView sheet 展示 ForkSubscribeSheet。"
    case .unifiedResultsNoSubscribePermission: return "聚合搜索结果中隐藏订阅分享行和复用入口。"
    case .unifiedEmpty: return "搜索完成但没有任何聚合结果。"
    case .siteSelection: return "资源模式站点筛选 Sheet。"
    case .resourceLoading: return "资源模式流式进度文案和进度条。"
    case .resourceResults: return "资源模式结果筛选栏 + 种子卡片。"
    case .resourceEmpty: return "资源模式搜索完成但无资源。"
    case .resourcePageLoading: return "从详情/菜单进入的资源结果页加载中。"
    case .resourcePageEmpty: return "从详情/菜单进入的资源结果页空态。"
    case .resourcePageResults: return "资源结果页背景图 + 筛选栏 + 种子卡片。"
    case .resourcePageFilterSelection: return "资源结果页筛选栏弹出的站点多选 Sheet。"
    }
  }

  var resourcePageMode: UIPreviewResourcePageMode {
    switch self {
    case .resourcePageLoading: return .loading
    case .resourcePageEmpty: return .empty
    default: return .results
    }
  }

  var showsSiteSelection: Bool {
    self == .siteSelection
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .unifiedResultsNoSubscribePermission:
      return [.discovery, .search, .manage]
    case .notSearched, .unifiedLoading, .unifiedResults, .unifiedLoadingMore, .unifiedShareSheet, .unifiedEmpty, .siteSelection,
      .resourceLoading, .resourceResults, .resourceEmpty, .resourcePageLoading, .resourcePageEmpty,
      .resourcePageResults, .resourcePageFilterSelection:
      return .allPreviewPermissions
    }
  }

  var resourceTorrentsPresentation: TorrentsResultUIPreviewPresentation? {
    self == .resourcePageFilterSelection ? .filterSelection : nil
  }

  var searchPreviewForkShare: SubscribeShare? {
    switch self {
    case .unifiedShareSheet:
      return UIPreviewFixtures.previewSubscribeShare
    default:
      return nil
    }
  }
}

private enum UIPreviewStatusMode { case empty, full }
private enum UIPreviewDownloadMode { case empty, multiState }
private enum UIPreviewTransferMode { case loading, loadingMore, empty, aiRedoing }

private enum UIPreviewStatusCase: String, UIPreviewCase {
  case statusEmpty
  case statusFull
  case downloadEmpty
  case downloadMultiState
  case downloadCollapsed
  case downloadDeleteConfirmation
  case transferLoading
  case transferLoadingMore
  case transferEmpty
  case transferAiRedoing
  case transferDetail
  case transferSingleDelete
  case transferBatchDelete
  case transferBatchReorganize

  var title: String {
    switch self {
    case .statusEmpty: return "状态页 · 空权限 / 空数据"
    case .statusFull: return "状态页 · 完整数据"
    case .downloadEmpty: return "下载任务 · 空数据"
    case .downloadMultiState: return "下载任务 · 多状态任务"
    case .downloadCollapsed: return "下载任务 · 收起"
    case .downloadDeleteConfirmation: return "下载任务 · 删除确认"
    case .transferLoading: return "整理历史 · 加载中"
    case .transferLoadingMore: return "整理历史 · 加载更多中"
    case .transferEmpty: return "整理历史 · 空数据"
    case .transferAiRedoing: return "整理历史 · 多选 / AI 整理中"
    case .transferDetail: return "整理历史 · 详情弹窗"
    case .transferSingleDelete: return "整理历史 · 单项删除确认"
    case .transferBatchDelete: return "整理历史 · 批量删除确认"
    case .transferBatchReorganize: return "整理历史 · 批量重整弹窗"
    }
  }

  var note: String {
    switch self {
    case .statusEmpty: return "统计、存储、下载器为空，任务列表为空。"
    case .statusFull: return "统计卡、存储、下载器、下载任务、整理历史组合。"
    case .downloadEmpty: return "下载任务标题区、下载器 Picker 和空态。"
    case .downloadMultiState: return "下载中、暂停、错误、校验等状态徽标和 ActionRow。"
    case .downloadCollapsed: return "下载任务收起后只保留标题和操作区。"
    case .downloadDeleteConfirmation: return "下载任务行删除确认 Alert。"
    case .transferLoading: return "整理历史首次加载中。"
    case .transferLoadingMore: return "整理历史已有列表时底部加载更多中。"
    case .transferEmpty: return "整理历史空态。"
    case .transferAiRedoing: return "多选、AI 整理中遮罩和行操作按钮。"
    case .transferDetail: return "整理历史长按详情弹窗，检查路径、存储名和状态信息。"
    case .transferSingleDelete: return "整理历史单项删除确认 Alert。"
    case .transferBatchDelete: return "整理历史批量删除确认 Alert。"
    case .transferBatchReorganize: return "整理历史批量重整 Sheet。"
    }
  }

  var statusMode: UIPreviewStatusMode {
    self == .statusEmpty ? .empty : .full
  }

  var downloadMode: UIPreviewDownloadMode {
    self == .downloadEmpty ? .empty : .multiState
  }

  var transferMode: UIPreviewTransferMode {
    switch self {
    case .transferLoading: return .loading
    case .transferLoadingMore: return .loadingMore
    case .transferEmpty: return .empty
    default: return .aiRedoing
    }
  }

  var downloadPresentation: DownloadTaskUIPreviewPresentation? {
    switch self {
    case .downloadCollapsed:
      return .collapsed
    case .downloadDeleteConfirmation:
      return .deleteConfirmation
    default:
      return nil
    }
  }

  var transferPresentation: TransferHistoryUIPreviewPresentation? {
    switch self {
    case .transferDetail:
      return .detail
    case .transferSingleDelete:
      return .singleDelete
    case .transferBatchDelete:
      return .batchDelete
    case .transferBatchReorganize:
      return .batchReorganize
    default:
      return nil
    }
  }
}

private enum UIPreviewSettingsCase: String, UIPreviewCase {
  case fullAccess
  case noSubscribe
  case noSearch
  case noSuperUser
  case limitedPermissions
  case connection
  case connectionRefreshing
  case siteSelection
  case siteEmpty
  case hardFilter
  case hardFilterLoading
  case hardFilterEmpty
  case softFilter
  case softFilterLoading
  case softFilterEmpty
  case siteLoading
  case rulesLoading
  case rulesEmpty
  case appInfo
  case logoutConfirmation

  var title: String {
    switch self {
    case .fullAccess: return "设置 · 全权限"
    case .noSubscribe: return "设置 · 无订阅权限"
    case .noSearch: return "设置 · 无搜索权限"
    case .noSuperUser: return "设置 · 无超级用户权限"
    case .limitedPermissions: return "设置 · 低权限"
    case .connection: return "设置 · 连接页"
    case .connectionRefreshing: return "设置 · 刷新登录凭据中"
    case .siteSelection: return "设置 · 站点选择页"
    case .siteEmpty: return "设置 · 站点空列表"
    case .hardFilter: return "设置 · 硬过滤页"
    case .hardFilterLoading: return "设置 · 硬过滤加载中"
    case .hardFilterEmpty: return "设置 · 硬过滤空列表"
    case .softFilter: return "设置 · 软过滤页"
    case .softFilterLoading: return "设置 · 软过滤加载中"
    case .softFilterEmpty: return "设置 · 软过滤空列表"
    case .siteLoading: return "设置 · 站点加载中"
    case .rulesLoading: return "设置 · 过滤规则加载中"
    case .rulesEmpty: return "设置 · 过滤规则空列表"
    case .appInfo: return "设置 · APP 信息"
    case .logoutConfirmation: return "设置 · 退出登录确认"
    }
  }

  var note: String {
    switch self {
    case .fullAccess: return "订阅、详情页、搜索站点、自定义过滤、连接信息全部可见。"
    case .noSubscribe: return "隐藏订阅设置，保留详情页和搜索设置。"
    case .noSearch: return "隐藏资源搜索设置，保留订阅和详情页设置。"
    case .noSuperUser: return "保留订阅和搜索设置，隐藏需要超级用户端点的自定义过滤。"
    case .limitedPermissions: return "只保留详情页、连接和 APP 信息，隐藏订阅、搜索与超级用户设置。"
    case .connection: return "设置连接子页，检查登录凭据和状态信息。"
    case .connectionRefreshing: return "设置连接子页刷新登录凭据中，检查按钮 ProgressView 和禁用态。"
    case .siteSelection: return "默认搜索站点子页。"
    case .siteEmpty: return "默认搜索站点子页空列表，检查全部站点和空状态提示。"
    case .hardFilter: return "硬过滤规则选择子页。"
    case .hardFilterLoading: return "硬过滤规则选择子页加载中。"
    case .hardFilterEmpty: return "硬过滤规则选择子页空列表。"
    case .softFilter: return "软过滤规则选择子页。"
    case .softFilterLoading: return "软过滤规则选择子页加载中。"
    case .softFilterEmpty: return "软过滤规则选择子页空列表。"
    case .siteLoading: return "默认搜索站点子页加载中。"
    case .rulesLoading: return "资源搜索根设置中的规则状态加载中。"
    case .rulesEmpty: return "资源搜索根设置中的规则状态为空。"
    case .appInfo: return "设置页 App 信息 Sheet，检查版本、兼容版本和链接行。"
    case .logoutConfirmation: return "退出登录系统 Alert，检查取消/确认焦点。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .fullAccess, .noSuperUser, .connection, .connectionRefreshing, .siteSelection, .siteEmpty,
      .hardFilter, .hardFilterLoading, .hardFilterEmpty, .softFilter, .softFilterLoading,
      .softFilterEmpty, .siteLoading, .rulesLoading, .rulesEmpty, .appInfo, .logoutConfirmation:
      return .allPreviewPermissions
    case .noSubscribe: return [.discovery, .search, .manage]
    case .noSearch: return [.discovery, .subscribe, .manage]
    case .limitedPermissions: return [.discovery]
    }
  }

  var canRequestSuperUserEndpoints: Bool {
    switch self {
    case .fullAccess, .connection, .connectionRefreshing, .siteSelection, .siteEmpty, .hardFilter,
      .hardFilterLoading, .hardFilterEmpty, .softFilter, .softFilterLoading, .softFilterEmpty,
      .siteLoading, .rulesLoading, .rulesEmpty, .appInfo, .logoutConfirmation:
      return true
    case .noSubscribe, .noSearch, .noSuperUser, .limitedPermissions:
      return false
    }
  }

  var presentation: SystemViewUIPreviewPresentation? {
    switch self {
    case .connection, .connectionRefreshing:
      return .connection
    case .siteSelection, .siteEmpty, .siteLoading:
      return .siteSelection
    case .hardFilter, .hardFilterLoading, .hardFilterEmpty:
      return .hardFilter
    case .softFilter, .softFilterLoading, .softFilterEmpty:
      return .softFilter
    case .appInfo:
      return .appInfo
    case .logoutConfirmation:
      return .logoutConfirmation
    case .fullAccess, .noSubscribe, .noSearch, .noSuperUser, .limitedPermissions, .rulesLoading, .rulesEmpty:
      return nil
    }
  }

  var hasEmptySites: Bool {
    switch self {
    case .noSearch, .limitedPermissions, .siteLoading, .siteEmpty:
      return true
    case .fullAccess, .noSubscribe, .noSuperUser, .connection, .connectionRefreshing, .siteSelection,
      .hardFilter, .hardFilterLoading, .hardFilterEmpty, .softFilter, .softFilterLoading,
      .softFilterEmpty, .rulesLoading, .rulesEmpty, .appInfo, .logoutConfirmation:
      return false
    }
  }

  var hasEmptyFilterRules: Bool {
    switch self {
    case .noSearch, .limitedPermissions, .rulesLoading, .rulesEmpty, .hardFilterLoading, .hardFilterEmpty,
      .softFilterLoading, .softFilterEmpty:
      return true
    case .fullAccess, .noSubscribe, .noSuperUser, .connection, .connectionRefreshing, .siteSelection,
      .siteEmpty, .hardFilter, .softFilter, .siteLoading, .appInfo, .logoutConfirmation:
      return false
    }
  }

  var isLoadingFilterRules: Bool {
    switch self {
    case .rulesLoading, .hardFilterLoading, .softFilterLoading:
      return true
    case .fullAccess, .noSubscribe, .noSearch, .noSuperUser, .limitedPermissions, .connection, .connectionRefreshing,
      .siteSelection, .siteEmpty, .hardFilter, .hardFilterEmpty, .softFilter, .softFilterEmpty,
      .siteLoading, .rulesEmpty, .appInfo, .logoutConfirmation:
      return false
    }
  }
}

private enum UIPreviewSheetCase: String, UIPreviewCase {
  case subscribeLoading
  case subscribe
  case subscribeMovie
  case subscribeAdvanced
  case subscribeSiteSelection
  case subscribeFilterGroupSelection
  case subscribeSaving
  case forkSubscribe
  case addDownloadLoading
  case addDownload
  case addDownloadAdvanced
  case addDownloadSubmitting
  case addDownloadNoSearchPermission
  case addDownloadError
  case reorganizeLoading
  case reorganize
  case reorganizeBatch
  case reorganizeDouban
  case reorganizeAdvanced
  case reorganizeSubmitting
  case reorganizeError
  case seasonDetail
  case multiSelection

  var title: String {
    switch self {
    case .subscribeLoading: return "订阅弹窗 · 加载中"
    case .subscribe: return "订阅弹窗 · 新增"
    case .subscribeMovie: return "订阅弹窗 · 电影新增"
    case .subscribeAdvanced: return "订阅弹窗 · 高级配置"
    case .subscribeSiteSelection: return "订阅弹窗 · 站点选择"
    case .subscribeFilterGroupSelection: return "订阅弹窗 · 过滤组选择"
    case .subscribeSaving: return "订阅弹窗 · 保存中"
    case .forkSubscribe: return "订阅分享弹窗 · 复用"
    case .addDownloadLoading: return "下载弹窗 · 加载中"
    case .addDownload: return "下载弹窗 · 添加下载"
    case .addDownloadAdvanced: return "下载弹窗 · 高级配置"
    case .addDownloadSubmitting: return "下载弹窗 · 提交中"
    case .addDownloadNoSearchPermission: return "下载弹窗 · 无搜索权限"
    case .addDownloadError: return "下载弹窗 · 失败反馈"
    case .reorganizeLoading: return "整理弹窗 · 加载中"
    case .reorganize: return "整理弹窗 · 单项重整"
    case .reorganizeBatch: return "整理弹窗 · 批量重整"
    case .reorganizeDouban: return "整理弹窗 · 豆瓣识别源"
    case .reorganizeAdvanced: return "整理弹窗 · 高级配置"
    case .reorganizeSubmitting: return "整理弹窗 · 提交中"
    case .reorganizeError: return "整理弹窗 · 失败反馈"
    case .seasonDetail: return "分季详情弹窗"
    case .multiSelection: return "多选弹窗 · 站点选择"
    }
  }

  var note: String {
    switch self {
    case .subscribeLoading: return "订阅弹窗配置加载中，检查全屏 ProgressView。"
    case .subscribe: return "新增订阅表单、站点/下载器/保存路径/高级配置入口。"
    case .subscribeMovie: return "电影订阅表单，检查电视剧集数和剧集组字段隐藏。"
    case .subscribeAdvanced: return "新增订阅表单高级配置展开。"
    case .subscribeSiteSelection: return "新增订阅站点选择 Sheet。"
    case .subscribeFilterGroupSelection: return "高级配置中的优先级规则组选择 Sheet。"
    case .subscribeSaving: return "新增订阅保存中按钮进度。"
    case .forkSubscribe: return "订阅分享复用入口，检查海报、分享人和复用按钮焦点。"
    case .addDownloadLoading: return "下载弹窗配置加载中，检查 Loading 居中和 Sheet 尺寸。"
    case .addDownload: return "添加下载表单、种子信息、下载器、保存路径和 TMDB ID。"
    case .addDownloadAdvanced: return "添加下载高级配置展开。"
    case .addDownloadSubmitting: return "添加下载提交中按钮进度。"
    case .addDownloadNoSearchPermission: return "搜索权限缺失时，添加下载确认按钮禁用。"
    case .addDownloadError: return "添加下载失败后，按钮变为重试并在下方显示一行说明。"
    case .reorganizeLoading: return "整理弹窗配置加载中，检查 NavigationStack 内 Loading。"
    case .reorganize: return "重新整理表单、目的存储、整理方式、剧集定位和高级配置。"
    case .reorganizeBatch: return "整理历史批量重整表单，检查无单文件时的字段状态。"
    case .reorganizeDouban: return "后端识别源为 Douban 时显示豆瓣 ID 字段。"
    case .reorganizeAdvanced: return "整理弹窗高级配置展开。"
    case .reorganizeSubmitting: return "整理弹窗提交中按钮进度。"
    case .reorganizeError: return "整理失败后，按钮变为重试并在下方显示一行说明。"
    case .seasonDetail: return "分季详情弹窗，检查海报、播出日期、评分和简介。"
    case .multiSelection: return "多选 Sheet、禁用项说明和确认按钮焦点。"
    }
  }

  var subscribePresentation: SubscribeSheetUIPreviewPresentation? {
    switch self {
    case .subscribeAdvanced:
      return .advanced
    case .subscribeSiteSelection:
      return .siteSelection
    case .subscribeFilterGroupSelection:
      return .filterGroupSelection
    default:
      return nil
    }
  }

  var addDownloadPresentation: AddDownloadSheetUIPreviewPresentation? {
    switch self {
    case .addDownloadAdvanced:
      return .advanced
    case .addDownloadError:
      return .errorFeedback
    default:
      return nil
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .addDownloadNoSearchPermission:
      return [.discovery, .subscribe, .manage]
    case .subscribeLoading, .subscribe, .subscribeMovie, .subscribeAdvanced, .subscribeSiteSelection,
      .subscribeFilterGroupSelection, .subscribeSaving, .forkSubscribe, .addDownloadLoading,
      .addDownload, .addDownloadAdvanced, .addDownloadSubmitting, .addDownloadError,
      .reorganizeLoading, .reorganize, .reorganizeBatch, .reorganizeDouban, .reorganizeAdvanced,
      .reorganizeSubmitting, .reorganizeError, .seasonDetail, .multiSelection:
      return .allPreviewPermissions
    }
  }

  var reorganizePresentation: ReorganizeSheetUIPreviewPresentation? {
    switch self {
    case .reorganizeAdvanced:
      return .advanced
    case .reorganizeDouban:
      return .doubanRecognition
    case .reorganizeError:
      return .errorNotification
    default:
      return nil
    }
  }

}

private enum UIPreviewComponentCase: String, UIPreviewCase {
  case mediaCards
  case mediaCardsContextMenu
  case mediaCardsLimitedPermissions
  case torrentCards
  case torrentCardsNoSearchPermission
  case torrentDownloadSheet
  case sheetPickerSelection
  case subscriptionAlert
  case pickers
  case mediaActionLoading
  case mediaActionNotFound
  case notification

  var title: String {
    switch self {
    case .mediaCards: return "组件 · 媒体卡片"
    case .mediaCardsContextMenu: return "组件 · 媒体卡片完整菜单"
    case .mediaCardsLimitedPermissions: return "组件 · 媒体卡片低权限菜单"
    case .torrentCards: return "组件 · 种子卡片"
    case .torrentCardsNoSearchPermission: return "组件 · 种子卡片无搜索权限"
    case .torrentDownloadSheet: return "组件 · 种子卡片下载弹窗"
    case .sheetPickerSelection: return "组件 · 单选弹窗"
    case .subscriptionAlert: return "组件 · 订阅结果提示"
    case .pickers: return "组件 · 选择器 / 输入框"
    case .mediaActionLoading: return "组件 · TMDB 识别中"
    case .mediaActionNotFound: return "组件 · TMDB 未识别提示"
    case .notification: return "组件 · 通知"
    }
  }

  var note: String {
    switch self {
    case .mediaCards: return "普通媒体、无图、合集、订阅分享、加载更多组合。"
    case .mediaCardsContextMenu: return "全权限媒体卡片菜单，覆盖 TMDB 跳转、已订阅、分季订阅、搜索资源和订阅分享复用入口。"
    case .mediaCardsLimitedPermissions: return "缺少订阅和搜索权限时，媒体卡片菜单只保留允许的详情入口。"
    case .torrentCards: return "免费、促销、软过滤、低做种等种子卡片组合。"
    case .torrentCardsNoSearchPermission: return "缺少搜索权限时，种子卡片不能打开添加下载弹窗，菜单不显示下载入口。"
    case .torrentDownloadSheet: return "从种子卡片入口进入添加下载 Sheet。"
    case .sheetPickerSelection: return "SheetPicker 单选列表 Sheet。"
    case .subscriptionAlert: return "全局订阅动作通知，覆盖重复订阅/复用结果提示样式。"
    case .pickers: return "Segmented Picker、ShelfPicker、SheetPicker、SheetTextField。"
    case .mediaActionLoading: return "全局媒体动作遮罩，检查识别中 ProgressView。"
    case .mediaActionNotFound: return "全局媒体动作 Alert，检查 TMDB 未识别提示。"
    case .notification: return "信息/成功/警告/错误四类通知和悬浮提示。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .mediaCardsLimitedPermissions:
      return [.discovery, .manage]
    case .torrentCardsNoSearchPermission:
      return [.discovery, .subscribe, .manage]
    case .mediaCards, .mediaCardsContextMenu, .torrentCards, .torrentDownloadSheet, .sheetPickerSelection, .subscriptionAlert,
      .pickers, .mediaActionLoading, .mediaActionNotFound, .notification:
      return .allPreviewPermissions
    }
  }
}

private extension Set where Element == UserPermissionKey {
  static let allPreviewPermissions: Set<UserPermissionKey> = [.discovery, .search, .subscribe, .manage]
}

@MainActor
private enum UIPreviewFixtures {
  static func resetPreviewState() {
    APIService.shared.uiPreviewPermissions = nil
    APIService.shared.uiPreviewCanRequestSuperUserEndpoints = nil
    MediaPreloader.shared.clearAll()
  }

  static func applyPermissions(
    _ permissions: Set<UserPermissionKey>,
    canRequestSuperUserEndpoints: Bool = true
  ) {
    APIService.shared.uiPreviewPermissions = permissions
    APIService.shared.uiPreviewCanRequestSuperUserEndpoints = canRequestSuperUserEndpoints
  }

  static func loginViewModel(_ previewCase: UIPreviewAppCase) -> LoginViewModel {
    let viewModel = LoginViewModel()
    let filledServerURL = "http://moviepilot.local:3000"
    switch previewCase {
    case .login:
      viewModel.serverURL = ""
      viewModel.username = ""
      viewModel.password = ""
    case .loginReady:
      viewModel.serverURL = filledServerURL
      viewModel.username = "preview-user"
      viewModel.password = "preview-password"
    case .loginLoading:
      viewModel.serverURL = filledServerURL
      viewModel.username = "preview-user"
      viewModel.password = "preview-password"
      viewModel.isLoading = true
    case .loginFailed:
      viewModel.serverURL = filledServerURL
      viewModel.username = "preview-user"
      viewModel.password = "wrong-password"
      viewModel.errorMessage = "登录失败: 用户名或密码错误"
    case .loggedIn, .startupPreparing, .loggedInLimitedTabs, .backendVersionWarning, .accountPermissionWarning:
      break
    }
    return viewModel
  }

  @discardableResult
  static func installDetail(_ detailCase: UIPreviewDetailCase) -> MediaInfo {
    applyPermissions(
      detailCase.permissions,
      canRequestSuperUserEndpoints: detailCase.permissions.contains(.manage)
    )
    MediaPreloader.shared.clearAll()

    let media = detailMedia(detailCase)
    let task = MediaPreloadTask(partialMedia: media)

    if detailCase == .detailLoadFailed {
      task.isDetailFailed = true
    } else if detailCase != .loading {
      task.fullDetail = media
      task.isDetailReady = true
      task.tmdbId = media.tmdb_id
      task.isSubscribed = detailCase.isSubscribed
    }

    switch detailCase {
    case .tvWithSeasons, .tvWithSeasonsNoSubscribePermission, .noArtwork, .noSearchPermission, .contentPage,
      .contentPageRowsLoadingMore, .contentPageNoSearchAndNoSubscribePermission, .siteSelection:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .mixedSubscription)
      task.isSeasonDataLoaded = true
    case .contentPageSingleEpisodeGroup:
      task.seasonViewModel = seasonViewModel(
        mediaInfo: media,
        initialSeason: nil,
        mode: .seasons,
        episodeGroups: []
      )
      task.isSeasonDataLoaded = true
    case .contentPageManySeasons:
      task.seasonViewModel = seasonViewModel(
        mediaInfo: media,
        initialSeason: nil,
        mode: .mixedSubscription,
        seasons: previewManySeasons,
        episodeGroups: previewEpisodeGroups
      )
      task.isSeasonDataLoaded = true
    case .tvWithoutSeasons, .tvWithoutSeasonsNoSubscribePermission, .tvWithoutSeasonsNoSearchPermission:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .empty)
      task.isSeasonDataLoaded = true
    case .seasonLoadFailed:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .failed)
      task.isSeasonDataLoaded = true
    case .loading, .detailLoadFailed, .movieUnsubscribed, .movieSubscribed, .tmdbJumpLoading, .subscribeSheet,
      .unsubscribeConfirmation, .unsubscribing, .noSubscribePermission,
      .noSearchAndNoSubscribePermission:
      break
    }

    MediaPreloader.shared.installPreviewTask(task, for: media)
    return media
  }

  static func installReadyDetail(_ media: MediaInfo) {
    let task = MediaPreloadTask(partialMedia: media)
    task.fullDetail = media
    task.isDetailReady = true
    task.tmdbId = media.tmdb_id
    task.isSubscribed = false
    MediaPreloader.shared.installPreviewTask(task, for: media)
  }

  static func homeViewModel(_ mode: UIPreviewHomeMode) -> HomeViewModel {
    let viewModel = HomeViewModel()
    switch mode {
    case .loading:
      viewModel.installUIPreviewData(
        latestMediaByServer: [:],
        selectedServer: "",
        movieSubscriptions: [],
        tvSubscriptions: [],
        isLoading: true
      )
    case .empty:
      viewModel.installUIPreviewData(
        latestMediaByServer: [:],
        selectedServer: "",
        movieSubscriptions: [],
        tvSubscriptions: [],
        isLoading: false
      )
    case .full:
      viewModel.installUIPreviewData(
        latestMediaByServer: [
          "Emby": mediaServerItems(prefix: "emby"),
          "Plex": mediaServerItems(prefix: "plex"),
        ],
        selectedServer: "Emby",
        movieSubscriptions: [
          subscribe(id: 31_001, name: "沙丘：预言", type: "电影", state: "R", lack: nil),
          subscribe(id: 31_002, name: "荒原长路", type: "电影", state: "S", lack: nil),
        ],
        tvSubscriptions: [
          subscribe(id: 31_101, name: "边境信号", type: "电视剧", state: "R", lack: 3),
          subscribe(id: 31_102, name: "海岸档案", type: "电视剧", state: "N", lack: 12),
        ],
        isLoading: false
      )
    case .latestEmptyServer:
      viewModel.installUIPreviewData(
        latestMediaByServer: [
          "Emby": [],
          "Plex": mediaServerItems(prefix: "plex"),
        ],
        selectedServer: "Emby",
        movieSubscriptions: [
          subscribe(id: 31_201, name: "荒原长路", type: "电影", state: "R", lack: nil),
        ],
        tvSubscriptions: [
          subscribe(id: 31_202, name: "边境信号", type: "电视剧", state: "N", lack: 4),
        ],
        isLoading: false
      )
    case .subscriptionsOnly:
      viewModel.installUIPreviewData(
        latestMediaByServer: [:],
        selectedServer: "",
        movieSubscriptions: [
          subscribe(id: 31_301, name: "荒原长路", type: "电影", state: "R", lack: nil),
        ],
        tvSubscriptions: [
          subscribe(id: 31_302, name: "边境信号", type: "电视剧", state: "S", lack: 6),
        ],
        isLoading: false
      )
    case .noSubscribePermission:
      viewModel.installUIPreviewData(
        latestMediaByServer: [
          "Emby": mediaServerItems(prefix: "emby"),
          "Plex": mediaServerItems(prefix: "plex"),
        ],
        selectedServer: "Emby",
        movieSubscriptions: [],
        tvSubscriptions: [],
        isLoading: false
      )
    }
    return viewModel
  }

  static func recommendViewModel(_ mode: UIPreviewRecommendMode) -> RecommendViewModel {
    let viewModel = RecommendViewModel(loadsAutomatically: false)
    viewModel.selectedCategory = .movie
    viewModel.selectedShelf = RecommendViewModel.allShelves.first { $0.category == .movie }
    switch mode {
    case .initial:
      viewModel.installUIPreviewPaginator(nil)
    case .loading:
      viewModel.installUIPreviewPaginator(.uiPreview(isFirstLoading: true))
    case .empty:
      viewModel.installUIPreviewPaginator(.uiPreview(items: []))
    case .full:
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid, isLoadingMore: true))
    }
    return viewModel
  }

  static func exploreViewModel(_ mode: UIPreviewExploreMode) -> ExploreViewModel {
    let viewModel = ExploreViewModel(loadsAutomatically: false)
    switch mode {
    case .initial:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .movies
      viewModel.installUIPreviewPaginator(nil)
    case .loading:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .movies
      viewModel.tmdbGenre = "878"
      viewModel.installUIPreviewPaginator(.uiPreview(isFirstLoading: true))
    case .tmdb:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .movies
      viewModel.tmdbGenre = "878"
      viewModel.tmdbLanguage = "ja"
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid, isLoadingMore: true))
    case .douban:
      viewModel.selectedSource = .douban
      viewModel.selectedType = .movies
      viewModel.doubanSort = "S"
      viewModel.doubanCategory = "悬疑"
      viewModel.doubanZone = "日本"
      viewModel.doubanYear = "2020年代"
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid))
    case .bangumi:
      viewModel.selectedSource = .bangumi
      viewModel.selectedType = .tvs
      viewModel.bangumiCat = "1"
      viewModel.bangumiSort = "rank"
      viewModel.bangumiYear = "2026"
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid))
    case .popular:
      viewModel.selectedSource = .popular
      viewModel.selectedType = .tvs
      viewModel.popularSortBy = "rating"
      viewModel.popularGenre = "10765"
      viewModel.popularMinRating = 8
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid, isLoadingMore: true))
    case .share:
      viewModel.selectedSource = .subscriptionShare
      viewModel.selectedType = .tvs
      viewModel.shareGenre = "10765"
      viewModel.installUIPreviewPaginator(.uiPreview(items: [
        shareMedia(id: 33_001, title: "高质量订阅分享 · 边境信号"),
        shareMedia(id: 33_002, title: "整季打包分享 · 海岸档案"),
      ]))
    case .noSubscribePermission:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .tvs
      viewModel.tmdbGenre = "10765"
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGridWithoutShares, isLoadingMore: true))
    case .empty:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .movies
      viewModel.tmdbGenre = "878"
      viewModel.tmdbVoteAverage = 9
      viewModel.installUIPreviewPaginator(.uiPreview(items: []))
    }
    return viewModel
  }

  static func searchViewModel(_ searchCase: UIPreviewSearchCase) -> SearchViewModel {
    let viewModel = SearchViewModel()
    viewModel.siteFilter.availableSites = sites
    viewModel.siteFilter.selectedSites = [1, 3]
    switch searchCase {
    case .notSearched:
      viewModel.query = ""
      viewModel.submittedQuery = ""
      viewModel.searchType = .unified
      viewModel.hasSearched = false
      viewModel.isLoading = false
    case .unifiedLoading:
      viewModel.query = "边境信号"
      viewModel.submittedQuery = "边境信号"
      viewModel.searchType = .unified
      viewModel.hasSearched = true
      viewModel.isLoading = true
    case .unifiedResults, .unifiedLoadingMore, .unifiedShareSheet, .unifiedResultsNoSubscribePermission:
      let movies = [movieMedia(id: 34_001, title: "边境信号：序章")]
      let tvShows = [baseTVMedia(id: 34_101, title: "边境信号")]
      let collections = [collectionMedia(id: 34_201, title: "边境信号系列")]
      let people = [person(id: 34_301, name: "林原真", character: "导演")]
      let shares = searchCase == .unifiedResultsNoSubscribePermission
        ? []
        : [shareMedia(id: 34_401, title: "边境信号 订阅分享")]
      var bestResults: [BestResultItem] = [.media(tvShows[0]), .person(people[0])]
      if let share = shares.first {
        bestResults.append(.media(share))
      }
      viewModel.installUIPreviewUnifiedResults(
        query: "边境信号",
        movies: movies,
        tvShows: tvShows,
        collections: collections,
        persons: people,
        shares: shares,
        bestResults: bestResults,
        isLoadingMore: searchCase == .unifiedLoadingMore
      )
    case .unifiedEmpty:
      viewModel.installUIPreviewUnifiedEmpty(query: "没有结果的关键词")
    case .siteSelection:
      viewModel.installUIPreviewResourceResults(query: "边境信号", results: contexts)
    case .resourceLoading:
      viewModel.installUIPreviewResourceResults(
        query: "边境信号",
        results: [],
        isLoading: true,
        progressText: "正在搜索 3 个站点...",
        progress: 45
      )
    case .resourceResults:
      viewModel.installUIPreviewResourceResults(query: "边境信号", results: contexts)
    case .resourceEmpty:
      viewModel.installUIPreviewResourceResults(query: "没有资源的关键词", results: [])
    case .resourcePageLoading, .resourcePageEmpty, .resourcePageResults, .resourcePageFilterSelection:
      break
    }
    return viewModel
  }

  static func collectionViewModel(_ mode: UIPreviewCollectionMode) -> CollectionDetailViewModel {
    switch mode {
    case .loading:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(isFirstLoading: true))
    case .empty:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(items: []))
    case .full:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(items: previewMediaGrid))
    case .loadingMore:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(items: previewMediaGrid, isLoadingMore: true))
    }
  }

  static func personViewModel(_ mode: UIPreviewPersonMode) -> PersonDetailViewModel {
    let previewPerson = person(
      id: 35_001,
      name: "林原真",
      character: nil,
      biography: (mode == .full || mode == .biographySheet) ? "长期活跃于科幻与悬疑题材的导演，作品以冷静的工业质感和细密的人物关系见长。这段长简介用于检查可聚焦简介卡片、Sheet 展开和多行文本。" : nil
    )
    switch mode {
    case .loading:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(isFirstLoading: true),
        isLoadingDetails: true
      )
    case .noBiography:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(items: previewMediaGrid),
        isLoadingDetails: false
      )
    case .full, .biographySheet:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(items: previewMediaGrid),
        isLoadingDetails: false
      )
    case .loadingMore:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(items: previewMediaGrid, isLoadingMore: true),
        isLoadingDetails: false
      )
    }
  }

  static func resourceResultViewModel(_ mode: UIPreviewResourcePageMode) -> ResourceResultViewModel {
    ResourceResultViewModel(
      previewTitle: "边境信号",
      mediaInfo: baseTVMedia(id: 36_001, title: "边境信号"),
      results: mode == .results ? contexts : [],
      isLoading: mode == .loading,
      progressText: "正在搜索默认站点...",
      progress: 60
    )
  }

  static func statusViewModel(_ mode: UIPreviewStatusMode) -> StatusViewModel {
    let viewModel = StatusViewModel()
    switch mode {
    case .empty:
      viewModel.installUIPreviewData(statistic: nil, storage: nil, downloader: nil)
    case .full:
      viewModel.installUIPreviewData(
        statistic: Statistic(movie_count: 326, tv_count: 74, episode_count: 4821),
        storage: Storage(total_storage: 16_000_000_000_000, used_storage: 11_200_000_000_000),
        downloader: DownloaderInfo(
          download_speed: 18_400_000,
          upload_speed: 2_300_000,
          download_size: 9_400_000_000,
          upload_size: 18_800_000_000,
          free_space: 2_500_000_000_000
        )
      )
    }
    return viewModel
  }

  static func downloadViewModel(_ mode: UIPreviewDownloadMode) -> DownloadTaskViewModel {
    let viewModel = DownloadTaskViewModel()
    viewModel.installUIPreviewData(
      clients: downloaders,
      selectedClient: "qb-main",
      downloads: mode == .empty ? [] : downloads
    )
    return viewModel
  }

  static func transferHistoryViewModel(_ mode: UIPreviewTransferMode) -> TransferHistoryViewModel {
    let viewModel = TransferHistoryViewModel()
    switch mode {
    case .loading:
      viewModel.installUIPreviewData(items: [], isFirstLoading: true)
    case .loadingMore:
      viewModel.installUIPreviewData(
        items: transferHistory,
        storageDict: ["local": "本地存储", "nas": "NAS"],
        isLoadingMore: true
      )
    case .empty:
      viewModel.installUIPreviewData(items: [], storageDict: ["local": "本地存储"])
    case .aiRedoing:
      viewModel.installUIPreviewData(
        items: transferHistory,
        storageDict: ["local": "本地存储", "nas": "NAS"],
        selectedIds: [44_001, 44_002],
        isAiRedoing: true,
        aiRedoingIds: [44_001],
        aiRedoProgressText: "正在重新整理 1 / 2"
      )
    }
    return viewModel
  }

  static func systemViewModel(_ settingsCase: UIPreviewSettingsCase) -> SystemViewModel {
    let viewModel = SystemViewModel()
    viewModel.installUIPreviewData(
      storageDescription: "已登录 (安全存储)",
      serverURL: "http://moviepilot.local:3000",
      username: "preview-user",
      backendVersion: "v2.14.1",
      availableSites: settingsCase.hasEmptySites ? [] : sites,
      customFilterRules: settingsCase.hasEmptyFilterRules ? [] : customRules,
      isRefreshing: settingsCase == .connectionRefreshing,
      refreshMessage: settingsCase == .connectionRefreshing ? "正在刷新登录凭据" : "上次刷新成功",
      isLoadingSites: settingsCase == .siteLoading,
      isLoadingRules: settingsCase.isLoadingFilterRules
    )
    return viewModel
  }

  static func subscribeSheetViewModel(
    type: String = "电视剧",
    isLoading: Bool = false,
    isSaving: Bool = false
  ) -> SubscribeSheetViewModel {
    let viewModel = SubscribeSheetViewModel(
      subscribe: subscribe(id: 45_001, name: type == "电视剧" ? "边境信号" : "边境信号：序章", type: type, state: "S", lack: type == "电视剧" ? 6 : nil),
      isNewSubscription: true
    )
    guard !isLoading else {
      viewModel.isLoading = true
      return viewModel
    }
    viewModel.installUIPreviewOptions(
      sites: sites,
      downloaders: downloaders,
      directories: directories,
      filterGroups: [FilterRuleGroup(name: "官组优先"), FilterRuleGroup(name: "体积过滤")],
      episodeGroups: [
        episodeGroup(id: "preview-main", name: "官方顺序"),
        episodeGroup(id: "preview-alt", name: "播出顺序"),
      ]
    )
    viewModel.isSaving = isSaving
    return viewModel
  }

  static func addDownloadViewModel(
    isLoading: Bool = false,
    isSubmitting: Bool = false
  ) -> AddDownloadViewModel {
    let viewModel = AddDownloadViewModel(
      torrent: contexts[0].torrent_info!,
      media: baseTVMedia(id: 45_101, title: "边境信号")
    )
    guard !isLoading else {
      viewModel.isLoading = true
      return viewModel
    }
    viewModel.installUIPreviewOptions(
      downloaders: downloaders,
      directories: directories,
      selectedDownloader: "qb-main",
      selectedDirectory: "/downloads/tv",
      tmdbId: "90101"
    )
    viewModel.isSubmitting = isSubmitting
    return viewModel
  }

  static func reorganizeViewModel(
    isLoading: Bool = false,
    isSubmitting: Bool = false
  ) -> ReorganizeViewModel {
    let viewModel = ReorganizeViewModel(
      logIds: [44_001],
      fileItem: fileItem(name: "Frontier.Signal.S01E01.mkv", path: "/downloads/Frontier.Signal.S01E01.mkv"),
      targetStorage: "local"
    )
    guard !isLoading else {
      viewModel.isLoading = true
      return viewModel
    }
    viewModel.form.type_name = "电视剧"
    viewModel.form.tmdbid = 90_101
    viewModel.form.season = 1
    viewModel.form.episode_detail = "1"
    viewModel.installUIPreviewConfig(
      directories: directories,
      storages: storages,
      targetDirectoryOptions: [
        PickerOption(title: "自动", value: ""),
        PickerOption(title: "/media/TV", value: "/media/TV"),
        PickerOption(title: "/media/Movies", value: "/media/Movies"),
      ]
    )
    viewModel.isSubmitting = isSubmitting
    return viewModel
  }

  static func reorganizeBatchViewModel() -> ReorganizeViewModel {
    let viewModel = ReorganizeViewModel(logIds: [44_001, 44_002], fileItem: nil)
    viewModel.form.type_name = "电视剧"
    viewModel.form.tmdbid = 90_101
    viewModel.form.season = 1
    viewModel.installUIPreviewConfig(
      directories: directories,
      storages: storages,
      targetDirectoryOptions: [
        PickerOption(title: "自动", value: ""),
        PickerOption(title: "/media/TV", value: "/media/TV"),
        PickerOption(title: "/media/Movies", value: "/media/Movies"),
      ]
    )
    return viewModel
  }

  static func seasonViewModel(_ seasonCase: UIPreviewSeasonCase) -> SubscribeSeasonViewModel {
    applyPermissions(seasonCase.permissions)
    return seasonViewModel(mediaInfo: baseTVMedia(id: 91_100, title: "分季预览剧集"), initialSeason: nil, mode: seasonCase.dataMode)
  }

  static func seasonViewModel(
    mediaInfo: MediaInfo,
    initialSeason: Int?
  ) -> SubscribeSeasonViewModel {
    seasonViewModel(mediaInfo: mediaInfo, initialSeason: initialSeason, mode: .mixedSubscription)
  }

  private static func seasonViewModel(
    mediaInfo: MediaInfo,
    initialSeason: Int?,
    mode: UIPreviewSeasonCase,
    seasons: [TmdbSeason]? = nil,
    episodeGroups: [EpisodeGroup]? = nil
  ) -> SubscribeSeasonViewModel {
    let viewModel = SubscribeSeasonViewModel(mediaInfo: mediaInfo, initialSeason: initialSeason)
    let seasonInfos = seasons ?? previewSeasons
    let groups = episodeGroups ?? previewEpisodeGroups

    switch mode {
    case .loading:
      viewModel.isLoading = true
    case .seasons, .noSubscribePermission:
      viewModel.episodeGroups = groups
      viewModel.seasonInfos = seasonInfos
      viewModel.seasonsNotExisted = [:]
      viewModel.isSeasonAvailabilityLoaded = true
    case .empty:
      viewModel.seasonInfos = []
      viewModel.isSeasonAvailabilityLoaded = true
    case .failed:
      viewModel.hasSeasonLoadError = true
      viewModel.errorMessage = "预览：分季接口加载失败"
      viewModel.isSeasonAvailabilityLoaded = true
    case .mixedSubscription, .seasonDetail, .subscribeSheet, .unsubscribeConfirmation:
      viewModel.episodeGroups = groups
      viewModel.seasonInfos = seasonInfos
      viewModel.seasonsNotExisted = [1: 0, 2: 1, 3: 2]
      viewModel.isSeasonAvailabilityLoaded = true
      viewModel.seasonSubscriptions = [
        1: SeasonSubscriptionSummary(id: 90_001, season: 1, episodeGroup: nil)
      ]
      viewModel.subscribedSeasons = [1]
    }

    return viewModel
  }

  static func detailRows(for detailCase: UIPreviewDetailCase) -> MediaDetailUIPreviewRows? {
    switch detailCase {
    case .contentPage, .contentPageNoSearchAndNoSubscribePermission, .contentPageSingleEpisodeGroup,
      .contentPageManySeasons, .tvWithoutSeasonsNoSearchPermission, .noSearchAndNoSubscribePermission:
      return previewDetailRows
    case .contentPageRowsLoadingMore:
      return previewDetailRowsLoadingMore
    default:
      return nil
    }
  }

  private static func detailMedia(_ detailCase: UIPreviewDetailCase) -> MediaInfo {
    switch detailCase {
    case .loading:
      return baseTVMedia(id: 90_001, title: "边境信号 · 加载中")
    case .detailLoadFailed:
      return baseTVMedia(id: 90_021, title: "边境信号 · 详情失败")
    case .movieUnsubscribed:
      return movieMedia(id: 90_101, title: "荒原长路 · 未订阅")
    case .movieSubscribed:
      return movieMedia(id: 90_102, title: "荒原长路 · 已订阅")
    case .tvWithSeasons:
      return baseTVMedia(id: 90_002, title: "边境信号")
    case .tvWithSeasonsNoSubscribePermission:
      return baseTVMedia(id: 90_015, title: "边境信号 · 有分季无订阅权限")
    case .tvWithoutSeasons:
      return baseTVMedia(id: 90_003, title: "边境信号 · 无分季")
    case .seasonLoadFailed:
      return baseTVMedia(id: 90_004, title: "边境信号 · 分季失败")
    case .noArtwork:
      return baseTVMedia(id: 90_005, title: "边境信号 · 无图", hasArtwork: false)
    case .contentPage:
      return baseTVMedia(id: 90_010, title: "边境信号 · 第二页")
    case .contentPageRowsLoadingMore:
      return baseTVMedia(id: 90_019, title: "边境信号 · 第二页加载更多")
    case .contentPageNoSearchAndNoSubscribePermission:
      return baseTVMedia(id: 90_016, title: "边境信号 · 第二页无操作权限")
    case .contentPageSingleEpisodeGroup:
      return baseTVMedia(id: 90_017, title: "边境信号 · 单剧集组")
    case .contentPageManySeasons:
      return baseTVMedia(id: 90_018, title: "边境信号 · 多分季")
    case .tmdbJumpLoading:
      return MediaInfo(
        tmdb_id: nil,
        douban_id: "36789012",
        source: "douban",
        title: "荒原长路 · 识别中",
        original_title: "Long Road",
        type: "电影",
        year: "2025",
        poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
        overview: "外部来源详情缺少 TMDB ID，用于检查跳转按钮的识别中状态。",
        vote_average: 7.7,
        popularity: 88,
        genres: [genre("剧情")]
      )
    case .siteSelection:
      return baseTVMedia(id: 90_011, title: "边境信号 · 站点选择")
    case .subscribeSheet:
      return movieMedia(id: 90_012, title: "荒原长路 · 订阅弹窗")
    case .unsubscribeConfirmation:
      return movieMedia(id: 90_013, title: "荒原长路 · 取消订阅")
    case .unsubscribing:
      return movieMedia(id: 90_020, title: "荒原长路 · 取消订阅中")
    case .noSubscribePermission:
      return baseTVMedia(id: 90_006, title: "边境信号 · 无订阅权限")
    case .noSearchPermission:
      return baseTVMedia(id: 90_007, title: "边境信号 · 无搜索权限")
    case .tvWithoutSeasonsNoSubscribePermission:
      return baseTVMedia(id: 90_008, title: "边境信号 · 无分季无订阅权限")
    case .tvWithoutSeasonsNoSearchPermission:
      return baseTVMedia(id: 90_014, title: "边境信号 · 无分季无搜索权限")
    case .noSearchAndNoSubscribePermission:
      return baseTVMedia(id: 90_009, title: "边境信号 · 无操作权限")
    }
  }

  static func baseTVMedia(
    id: Int,
    title: String,
    hasArtwork: Bool = true
  ) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      original_title: "Frontier Signal",
      names: ["Frontier Signal", "边境信号"],
      type: "电视剧",
      year: "2026",
      poster_path: hasArtwork ? "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg" : nil,
      backdrop_path: hasArtwork ? "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg" : nil,
      overview: "一支深空维护小队在边境航道收到异常信号，必须在有限补给和分裂意见中决定是否继续追踪。",
      vote_average: 8.4,
      popularity: 125,
      directors: [person(id: 70_001, name: "林原真")],
      actors: [
        person(id: 70_002, name: "高桥遥", character: "领航员"),
        person(id: 70_003, name: "陈述", character: "工程师"),
      ],
      release_date: "2026-01-12",
      original_language: "ja",
      production_countries: [country("日本")],
      genres: [genre("科幻"), genre("冒险")],
      category: "剧集"
    )
  }

  static func movieMedia(id: Int, title: String, hasArtwork: Bool = true) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      original_title: "Long Road",
      type: "电影",
      year: "2025",
      poster_path: hasArtwork ? "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg" : nil,
      backdrop_path: hasArtwork ? "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg" : nil,
      overview: "用于预览电影卡片、详情跳转和订阅操作。",
      vote_average: 7.7,
      popularity: 88,
      genres: [genre("剧情")]
    )
  }

  static func externalSourceMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: nil,
      douban_id: "\(id)",
      source: "douban",
      title: title,
      original_title: "Frontier Signal",
      type: "电影",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview: "外部来源媒体，预览媒体卡片菜单中的 TMDB 详情页入口。",
      vote_average: 8.1,
      popularity: 76,
      genres: [genre("科幻")]
    )
  }

  static func collectionMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      type: "合集",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      backdrop_path: "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
      overview: "合集预览",
      vote_average: 8.2,
      popularity: 55,
      collection_id: id
    )
  }

  static func shareMedia(id: Int, title: String) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      type: "电视剧",
      year: "2026",
      poster_path: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      overview: "来自 preview-user 的订阅分享，复用 128 次。",
      vote_average: 8.8,
      popularity: 128,
      subscribeShare: subscribeShare(id: id, title: title)
    )
  }

  private static var previewMediaGrid: [MediaInfo] {
    [
      movieMedia(id: 80_001, title: "荒原长路"),
      baseTVMedia(id: 80_002, title: "边境信号"),
      movieMedia(id: 80_003, title: "无海报电影", hasArtwork: false),
      collectionMedia(id: 80_004, title: "边境信号系列"),
      shareMedia(id: 80_005, title: "订阅分享：边境信号"),
      baseTVMedia(id: 80_006, title: "标题很长很长的剧集名称用于检查卡片文字截断和焦点缩放"),
    ]
  }

  private static var previewMediaGridWithoutShares: [MediaInfo] {
    previewMediaGrid.filter { $0.subscribeShare == nil }
  }

  private static var previewDetailRows: MediaDetailUIPreviewRows {
    MediaDetailUIPreviewRows(
      actors: [
        person(id: 70_101, name: "高桥遥", character: "领航员"),
        person(id: 70_102, name: "陈述", character: "工程师"),
        person(id: 70_103, name: "周念", character: "通讯官"),
        person(id: 70_104, name: "森田葵", character: "医疗官"),
      ],
      recommendations: Array(previewMediaGridWithoutShares.prefix(4)),
      similar: [
        baseTVMedia(id: 80_201, title: "星门回声"),
        movieMedia(id: 80_202, title: "荒原长路"),
        baseTVMedia(id: 80_203, title: "轨道边界"),
        collectionMedia(id: 80_204, title: "深空信号系列"),
      ]
    )
  }

  private static var previewDetailRowsLoadingMore: MediaDetailUIPreviewRows {
    var rows = previewDetailRows
    rows.isLoadingMore = true
    return rows
  }

  private static func mediaServerItems(prefix: String) -> [MediaServerPlayItem] {
    [
      MediaServerPlayItem(
        id: "\(prefix)-1",
        title: "边境信号",
        subtitle: "2026",
        type: "电视剧",
        image: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        link: "emby://items/1",
        server_type: .emby
      ),
      MediaServerPlayItem(
        id: "\(prefix)-2",
        title: "荒原长路",
        subtitle: "2025",
        type: "电影",
        image: nil,
        link: "emby://items/2",
        server_type: .emby
      ),
    ]
  }

  private static var previewSeasons: [TmdbSeason] {
    [
      season(number: 1, name: "第 1 季", episodes: 12, vote: 8.5),
      season(number: 2, name: "第 2 季", episodes: 10, vote: 8.1),
      season(number: 3, name: "特别篇", episodes: 0, vote: 0),
    ]
  }

  private static var previewManySeasons: [TmdbSeason] {
    var seasons: [TmdbSeason] = []
    for number in 1...12 {
      let name = number == 12 ? "特别篇合集" : "第 \(number) 季"
      let episodeCount = number == 12 ? 4 : 8 + (number % 5)
      let vote = number == 12 ? 7.6 : 8.0 + Double(number % 4) * 0.2
      seasons.append(season(number: number, name: name, episodes: episodeCount, vote: vote))
    }
    return seasons
  }

  private static var previewEpisodeGroups: [EpisodeGroup] {
    [
      episodeGroup(id: "preview-main", name: "官方顺序"),
      episodeGroup(id: "preview-alt", name: "播出顺序"),
    ]
  }

  static var previewSeasonDetail: TmdbSeason {
    season(number: 1, name: "第 1 季", episodes: 12, vote: 8.5)
  }

  static var sites: [Site] {
    [
      Site(id: 1, name: "AlphaPT", domain: "alpha", url: "https://alpha.example", downloader: "qb-main", is_active: FlexibleBool(true)),
      Site(id: 3, name: "BetaHD", domain: "beta", url: "https://beta.example", downloader: "tr-main", is_active: FlexibleBool(true)),
      Site(id: 5, name: "维护中站点", domain: "offline", url: "https://offline.example", downloader: nil, is_active: FlexibleBool(false)),
    ]
  }

  private static var downloaders: [DownloaderConf] {
    [
      DownloaderConf(name: "qb-main", type: "qbittorrent", enabled: FlexibleBool(true)),
      DownloaderConf(name: "tr-main", type: "transmission", enabled: FlexibleBool(true)),
    ]
  }

  private static var directories: [TransferDirectoryConf] {
    [
      TransferDirectoryConf(
        name: "电视剧",
        storage: "local",
        download_path: "/downloads/tv",
        library_path: "/media/TV",
        library_storage: "local",
        transfer_type: "link",
        scraping: FlexibleBool(true),
        library_category_folder: FlexibleBool(true),
        library_type_folder: FlexibleBool(true)
      ),
      TransferDirectoryConf(
        name: "电影",
        storage: "nas",
        download_path: "/downloads/movie",
        library_path: "/media/Movies",
        library_storage: "nas",
        transfer_type: "copy",
        scraping: FlexibleBool(true),
        library_category_folder: FlexibleBool(false),
        library_type_folder: FlexibleBool(true)
      ),
    ]
  }

  private static var storages: [StorageConf] {
    [
      StorageConf(name: "本地存储", type: "local"),
      StorageConf(name: "NAS", type: "nas"),
    ]
  }

  private static var customRules: [CustomRule] {
    [
      CustomRule(id: "rule-hard", name: "硬过滤：排除低清", include: "1080p|2160p", exclude: "CAM|TS", size_range: "1024-51200", seeders: "5", publish_time: nil),
      CustomRule(id: "rule-soft", name: "软过滤：官组优先", include: "Alpha|Beta", exclude: nil, size_range: nil, seeders: nil, publish_time: "10080"),
    ]
  }

  static var contexts: [Context] {
    [
      context(index: 1, title: "Frontier.Signal.S01E01.2160p.WEB-DL.DV.HDR.HEVC-Alpha", site: "AlphaPT", size: 8_600_000_000, seeders: 42, filtered: false),
      context(index: 2, title: "Frontier.Signal.S01E02.1080p.WEB-DL.H264-Beta", site: "BetaHD", size: 3_200_000_000, seeders: 7, filtered: false),
      context(index: 3, title: "Frontier.Signal.S01E03.720p.HDTV-LowSeeds", site: "Gamma", size: 1_400_000_000, seeders: 1, filtered: true),
    ]
  }

  static var previewSubscribeShare: SubscribeShare {
    subscribeShare(id: 46_001, title: "边境信号 · 高质量订阅分享")
  }

  private static var downloads: [DownloadingInfo] {
    [
      downloading(hash: "hash-1", title: "Frontier.Signal.S01E01.2160p", state: "downloading", progress: 72, dlspeed: "18.4 MB", left: "12 分钟"),
      downloading(hash: "hash-2", title: "Long.Road.2025.1080p", state: "paused", progress: 35, dlspeed: "0 B", left: "暂停"),
      downloading(hash: "hash-3", title: "Coast.Archive.S02E04.1080p", state: "error", progress: 91, dlspeed: "0 B", left: "错误"),
      downloading(hash: "hash-4", title: "Checking.File.S01E02", state: "checking", progress: 8, dlspeed: "0 B", left: "校验中"),
      downloading(hash: "hash-5", title: "Stalled.File.S01E03", state: "stalledDL", progress: 18, dlspeed: "0 B", left: "等待连接"),
      downloading(hash: "hash-6", title: "Uploading.File.S01E04", state: "uploading", progress: 100, dlspeed: "0 B", left: "做种中"),
      downloading(hash: "hash-7", title: "Missing.File.S01E05", state: "missingFiles", progress: 64, dlspeed: "0 B", left: "文件丢失"),
      downloading(hash: "hash-8", title: "Queued.File.S01E06", state: "queuedDL", progress: 0, dlspeed: "0 B", left: "等待中"),
    ]
  }

  private static var transferHistory: [TransferHistory] {
    [
      transfer(id: 44_001, title: "边境信号", status: true, mode: "link"),
      transfer(id: 44_002, title: "荒原长路", status: false, mode: "copy"),
      transfer(id: 44_003, title: "海岸档案", status: true, mode: "softlink"),
    ]
  }

  private static func subscribe(
    id: Int,
    name: String,
    type: String,
    state: String,
    lack: Int?
  ) -> Subscribe {
    Subscribe(
      id: id,
      name: name,
      year: "2026",
      type: type,
      poster: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
      vote: 8.4,
      state: state,
      last_update: "2026-07-03 10:20:00",
      tmdbid: id,
      best_version: 1,
      total_episode: type == "电视剧" ? 12 : nil,
      start_episode: type == "电视剧" ? 1 : nil,
      lack_episode: lack,
      quality: "WEB-DL",
      resolution: "1080[pi]|x1080",
      include: "Alpha",
      sites: [1, 3],
      downloader: "qb-main",
      save_path: "/downloads/tv",
      description: "预览订阅描述"
    )
  }

  private static func subscribeShare(id: Int, title: String) -> SubscribeShare {
    decode(
      SubscribeShare.self,
      """
      {
        "id": \(id),
        "share_title": "\(title)",
        "share_comment": "预览订阅分享说明",
        "share_user": "preview-user",
        "share_uid": "preview",
        "name": "\(title)",
        "year": "2026",
        "type": "电视剧",
        "tmdbid": \(id),
        "poster": "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        "vote": 8.8,
        "count": 128
      }
      """
    )
  }

  private static func season(number: Int, name: String, episodes: Int, vote: Double) -> TmdbSeason {
    decode(
      TmdbSeason.self,
      """
      {
        "air_date": "2026-01-\(String(format: "%02d", min(number, 9)))",
        "episode_count": \(episodes),
        "name": "\(name)",
        "overview": "预览用分季描述，用于检查长文本、评分、缺集徽标和焦点状态。",
        "poster_path": "/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
        "season_number": \(number),
        "vote_average": \(vote)
      }
      """
    )
  }

  private static func episodeGroup(id: String, name: String) -> EpisodeGroup {
    decode(
      EpisodeGroup.self,
      """
      {
        "id": "\(id)",
        "name": "\(name)",
        "group_count": 3,
        "episode_count": 22
      }
      """
    )
  }

  private static func person(
    id: Int,
    name: String,
    character: String? = nil,
    biography: String? = nil
  ) -> Person {
    let characterLine = character.map { #","character":"\#($0)""# } ?? ""
    let biographyLine = biography.map { #","biography":"\#($0)""# } ?? ""
    return decode(
      Person.self,
      """
      {
        "source": "themoviedb",
        "id": \(id),
        "name": "\(name)",
        "original_name": "Makoto Hayashibara",
        "profile_path": "/r3A7ev7QkjOGocVn3kQrJ0eOouk.jpg",
        "birthday": "1982-04-11",
        "place_of_birth": "Tokyo, Japan",
        "popularity": 12.3\(characterLine)\(biographyLine)
      }
      """
    )
  }

  private static func context(
    index: Int,
    title: String,
    site: String,
    size: Int64,
    seeders: Int,
    filtered: Bool
  ) -> Context {
    var result = Context(
      media_info: baseTVMedia(id: 81_000 + index, title: "边境信号"),
      torrent_info: TorrentInfo(
        site: index,
        site_name: site,
        site_order: index,
        title: title,
        description: "预览资源描述，包含字幕、杜比视界和多版本信息。",
        enclosure: "https://example.com/\(index).torrent",
        page_url: "https://example.com/torrents/\(index)",
        size: size,
        seeders: seeders,
        peers: max(seeders * 2, 1),
        pubdate: "2026-07-0\(index) 10:00:00",
        uploadvolumefactor: index == 1 ? 2 : 1,
        downloadvolumefactor: index == 1 ? 0 : 1,
        pri_order: 10 - index,
        labels: ["preview"],
        volume_factor: index == 1 ? "Free" : nil
      ),
      meta_info: MetaInfo(
        title: "Frontier Signal",
        year: "2026",
        resource_team: index == 3 ? "LowSeeds" : "Alpha",
        video_encode: index == 1 ? "HEVC" : "H264",
        resource_pix: index == 1 ? "2160p" : "1080p",
        name: "边境信号",
        season_episode: "S01E0\(index)",
        subtitle: "简繁字幕",
        web_source: "WEB-DL",
        edition: index == 1 ? "DV HDR" : "SDR",
        total_season: 1,
        total_episode: 12
      )
    )
    result.isFilteredOut = filtered
    return result
  }

  private static func downloading(
    hash: String,
    title: String,
    state: String,
    progress: Double,
    dlspeed: String,
    left: String
  ) -> DownloadingInfo {
    decode(
      DownloadingInfo.self,
      """
      {
        "hash": "\(hash)",
        "title": "\(title)",
        "name": "边境信号",
        "state": "\(state)",
        "progress": \(progress),
        "dlspeed": "\(dlspeed)",
        "upspeed": "2.1 MB",
        "size": 8600000000,
        "left_time": "\(left)",
        "season_episode": "S01E01",
        "username": "preview",
        "media": {
          "image": "https://image.tmdb.org/t/p/original/3V4kLQg0kSqPLctI5ziYWabAZYF.jpg",
          "title": "边境信号",
          "season": "S01",
          "episode": "E01"
        }
      }
      """
    )
  }

  private static func transfer(id: Int, title: String, status: Bool, mode: String) -> TransferHistory {
    decode(
      TransferHistory.self,
      """
      {
        "id": \(id),
        "title": "\(title)",
        "type": "电视剧",
        "seasons": "S01",
        "episodes": "E01",
        "category": "科幻",
        "src": "/downloads/\(title).mkv",
        "dest": "/media/TV/\(title)/S01E01.mkv",
        "src_storage": "local",
        "dest_storage": "nas",
        "mode": "\(mode)",
        "status": \(status),
        "errmsg": \(status ? "null" : "\"预览：目标文件已存在\""),
        "src_fileitem": {
          "name": "\(title).mkv",
          "path": "/downloads/\(title).mkv",
          "type": "file",
          "size": 8600000000
        },
        "date": "2026-07-03 10:20:00"
      }
      """
    )
  }

  private static func fileItem(name: String, path: String) -> FileItem {
    FileItem(name: name, path: path, type: "file", size: 8_600_000_000)
  }

  private static func genre(_ name: String) -> MediaGenre {
    decode(MediaGenre.self, "\"\(name)\"")
  }

  private static func country(_ name: String) -> ProductionCountry {
    decode(ProductionCountry.self, "\"\(name)\"")
  }

  private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    guard let data = json.data(using: .utf8) else {
      fatalError("Invalid UI preview fixture")
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      fatalError("Invalid UI preview fixture for \(type): \(error)")
    }
  }
}
#endif
