#if DEBUG
import SwiftUI

struct PreviewCatalogView: View {
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var selectedScene: UIPreviewScene?
  @State private var didResetPreviewState = false

  var body: some View {
    Group {
      if let selectedScene {
        UIPreviewSceneDestination(scene: selectedScene)
          .id(selectedScene.id)
          .onExitCommand {
            self.selectedScene = nil
          }
      } else {
        NavigationStack {
          UIPreviewCatalogHomeView { scene in
            selectedScene = scene
          }
          .navigationTitle("UI 预览")
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
  let selectScene: (UIPreviewScene) -> Void
  @FocusState private var focusedSceneID: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 34) {
        ForEach(UIPreviewCatalog.sections) { section in
          VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
              .font(.title3.bold())
              .foregroundStyle(.secondary)

            VStack(spacing: 10) {
              ForEach(section.scenes) { scene in
                let isFocused = focusedSceneID == scene.id

                Button {
                  selectScene(scene)
                } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    Text(scene.title)
                      .font(.headline)
                      .foregroundStyle(isFocused ? .black : .primary)
                    Text(scene.note)
                      .font(.caption)
                      .foregroundStyle(isFocused ? .black.opacity(0.65) : .secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(UIPreviewCatalogButtonStyle())
                .focused($focusedSceneID, equals: scene.id)
              }
            }
          }
        }
      }
      .padding(.horizontal, 96)
      .padding(.vertical, 60)
    }
    .onAppear {
      focusedSceneID = focusedSceneID ?? UIPreviewCatalog.firstSceneID
    }
  }
}

private struct UIPreviewCatalogButtonStyle: ButtonStyle {
  @Environment(\.isFocused) private var isFocused

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 26)
      .padding(.vertical, 18)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(backgroundColor(isPressed: configuration.isPressed))
      }
      .scaleEffect(isFocused && !configuration.isPressed ? 1.02 : 1.0)
      .animation(.easeOut(duration: 0.18), value: isFocused)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  private func backgroundColor(isPressed: Bool) -> Color {
    if isFocused {
      return .white
    }
    return .white.opacity(isPressed ? 0.12 : 0.04)
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
      case .loggedIn:
        UIPreviewLoggedInRootView()
      case .login:
        LoginView()
      }
    }
    .onAppear {
      switch previewCase {
      case .loggedIn:
        UIPreviewFixtures.applyPermissions(.allPreviewPermissions, canRequestSuperUserEndpoints: true)
      case .login:
        UIPreviewFixtures.applyPermissions([], canRequestSuperUserEndpoints: false)
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
  private let transferPresentation: TransferHistoryUIPreviewPresentation?
  private let homeInitialPath: NavigationPath
  private let searchInitialPath: NavigationPath
  private let searchPreviewDestinations: SearchViewUIPreviewDestinations?

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
    transferPresentation: TransferHistoryUIPreviewPresentation? = nil,
    homeInitialPath: NavigationPath = NavigationPath(),
    searchInitialPath: NavigationPath = NavigationPath(),
    searchPreviewDestinations: SearchViewUIPreviewDestinations? = nil
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
    self.transferPresentation = transferPresentation
    self.homeInitialPath = homeInitialPath
    self.searchInitialPath = searchInitialPath
    self.searchPreviewDestinations = searchPreviewDestinations
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      HomeView(viewModel: homeViewModel, loadsDataOnAppear: false, initialPath: homeInitialPath)
        .tabItem { Label("媒体库", systemImage: "play.tv") }
        .tag(ContentViewModel.Tab.home)

      if visibleTabs.contains(.recommend) {
        RecommendView(viewModel: recommendViewModel)
          .tabItem { Label("推荐", systemImage: "sparkles.tv") }
          .tag(ContentViewModel.Tab.recommend)
      }

      if visibleTabs.contains(.explore) {
        ExploreView(viewModel: exploreViewModel)
          .tabItem { Label("探索", systemImage: "safari") }
          .tag(ContentViewModel.Tab.explore)
      }

      if visibleTabs.contains(.search) {
        SearchView(
          viewModel: searchViewModel,
          loadsSitesOnAppear: false,
          initialPath: searchInitialPath,
          uiPreviewDestinations: searchPreviewDestinations
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
    case .homeLoading, .homeEmpty, .homeFull:
      UIPreviewLoggedInRootView(selectedTab: .home, homeMode: previewCase.homeMode)
    case .recommendLoading, .recommendEmpty, .recommendFull:
      UIPreviewLoggedInRootView(selectedTab: .recommend, recommendMode: previewCase.recommendMode)
    case .exploreTmdb, .exploreShare:
      UIPreviewLoggedInRootView(selectedTab: .explore, exploreMode: previewCase.exploreMode)
    case .collectionLoading, .collectionFull:
      UIPreviewCollectionScene(mode: previewCase.collectionMode)
    case .personLoading, .personFull:
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
      searchPreviewDestinations: SearchViewUIPreviewDestinations(personViewModel: viewModel)
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
      searchPreviewDestinations: SearchViewUIPreviewDestinations(seasonViewModel: viewModel)
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
    case .unifiedResults, .unifiedEmpty, .resourceLoading, .resourceResults, .resourceEmpty:
      UIPreviewLoggedInRootView(selectedTab: .search, searchCase: searchCase)
    case .resourcePageLoading, .resourcePageResults:
      UIPreviewResourceResultScene(mode: searchCase.resourcePageMode)
    }
  }
}

@MainActor
private struct UIPreviewResourceResultScene: View {
  let mode: UIPreviewResourcePageMode

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
        resourceResultViewModel: UIPreviewFixtures.resourceResultViewModel(mode)
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
    case .downloadEmpty, .downloadMultiState:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        downloadMode: statusCase.downloadMode
      )
    case .transferLoading, .transferEmpty, .transferAiRedoing:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        transferMode: statusCase.transferMode
      )
    case .transferDetail:
      UIPreviewLoggedInRootView(
        selectedTab: .status,
        transferMode: .aiRedoing,
        transferPresentation: .detail
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

  init(sheetCase: UIPreviewSheetCase) {
    self.sheetCase = sheetCase
    UIPreviewFixtures.applyPermissions(.allPreviewPermissions, canRequestSuperUserEndpoints: true)
  }

  var body: some View {
    switch sheetCase {
    case .subscribe:
      SubscribeSheet(previewViewModel: UIPreviewFixtures.subscribeSheetViewModel())
        .previewRoot(sheetCase.title)
    case .addDownload:
      AddDownloadSheet(previewViewModel: UIPreviewFixtures.addDownloadViewModel())
        .environmentObject(NotificationManager())
        .previewRoot(sheetCase.title)
    case .reorganize:
      ReorganizeSheet(previewViewModel: UIPreviewFixtures.reorganizeViewModel()) {}
        .environmentObject(NotificationManager())
        .previewRoot(sheetCase.title)
    case .reorganizeBatch:
      ReorganizeSheet(previewViewModel: UIPreviewFixtures.reorganizeBatchViewModel()) {}
        .environmentObject(NotificationManager())
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

  var body: some View {
    switch componentCase {
    case .mediaCards:
      NavigationStack(path: $navigationPath) {
        UIPreviewMediaCards(navigationPath: $navigationPath)
          .uiPreviewNavigationDestinations(path: $navigationPath)
      }
    case .torrentCards:
      UIPreviewTorrentCards()
        .previewRoot(componentCase.title)
        .onAppear { UIPreviewFixtures.applyPermissions(.allPreviewPermissions, canRequestSuperUserEndpoints: true) }
    case .pickers:
      UIPreviewPickerComponents()
        .previewRoot(componentCase.title)
    case .notification:
      UIPreviewNotificationComponents()
        .previewRoot(componentCase.title)
    }
  }
}

private struct UIPreviewMediaCards: View {
  @Binding var navigationPath: NavigationPath

  var body: some View {
    MediaGridView(
      items: [
        UIPreviewFixtures.movieMedia(id: 98_001, title: "长标题电影：跨越三行也不能挤坏焦点卡片"),
        UIPreviewFixtures.baseTVMedia(id: 98_002, title: "无海报剧集", hasArtwork: false),
        UIPreviewFixtures.collectionMedia(id: 98_003, title: "边境信号系列"),
        UIPreviewFixtures.shareMedia(id: 98_004, title: "订阅分享卡片"),
      ],
      isLoading: false,
      isLoadingMore: true,
      onLoadMore: { _ in },
      navigationPath: $navigationPath,
      header: {
        Text("媒体卡片 / 网格 / 加载更多")
          .font(.largeTitle.bold())
          .foregroundStyle(.secondary)
      }
    )
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

private struct UIPreviewNotificationComponents: View {
  @StateObject private var manager = NotificationManager()

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 24) {
        NotificationView(message: "信息提示：正在使用 UI 预览目录", type: .info)
        NotificationView(message: "成功提示：订阅已保存", type: .success)
        NotificationView(message: "警告提示：站点响应较慢", type: .warning)
        NotificationView(message: "错误提示：搜索任务失败", type: .error)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Color.clear
        .withNotification()
        .environmentObject(manager)
    }
    .onAppear {
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
        ResourceResultView(request: request)
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
  static var firstSceneID: String? {
    sections.first?.scenes.first?.id
  }

  static let sections: [UIPreviewSection] = [
    UIPreviewSection(
      id: "app",
      title: "App 入口 / Tab 页面",
      scenes: [
        scene(.app(.loggedIn), id: "app-loggedIn", title: "启动入口 · 正常已登录"),
        scene(.app(.login), id: "app-login", title: "启动入口 · 登录页"),
      ]
    ),
    UIPreviewSection(
      id: "detail",
      title: "详情页",
      scenes: [
        scene(.detail(.loading), id: "detail-loading", title: "详情页 · 加载中"),
        scene(.detail(.tvWithSeasons), id: "detail-tvWithSeasons", title: "详情页 · 电视剧，有分季"),
        scene(.detail(.tvWithoutSeasons), id: "detail-tvWithoutSeasons", title: "详情页 · 电视剧，无分季"),
        scene(.detail(.seasonLoadFailed), id: "detail-seasonLoadFailed", title: "详情页 · 分季加载失败"),
        scene(.detail(.noArtwork), id: "detail-noArtwork", title: "详情页 · 无海报 / 无背景图"),
        scene(.detail(.noSubscribePermission), id: "detail-noSubscribePermission", title: "详情页 · 无订阅权限"),
        scene(.detail(.noSearchPermission), id: "detail-noSearchPermission", title: "详情页 · 无搜索权限"),
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
      ]
    ),
    UIPreviewSection(
      id: "page",
      title: "页面入口",
      scenes: [
        scene(.page(.homeLoading), id: "page-homeLoading", title: "首页 · 加载中"),
        scene(.page(.homeEmpty), id: "page-homeEmpty", title: "首页 · 空数据"),
        scene(.page(.homeFull), id: "page-homeFull", title: "首页 · 完整数据"),
        scene(.page(.recommendLoading), id: "page-recommendLoading", title: "推荐 · 加载中"),
        scene(.page(.recommendEmpty), id: "page-recommendEmpty", title: "推荐 · 空数据"),
        scene(.page(.recommendFull), id: "page-recommendFull", title: "推荐 · 完整数据"),
        scene(.page(.exploreTmdb), id: "page-exploreTmdb", title: "探索 · TMDB 筛选"),
        scene(.page(.exploreShare), id: "page-exploreShare", title: "探索 · 订阅分享"),
        scene(.page(.collectionLoading), id: "page-collectionLoading", title: "合集详情 · 加载中"),
        scene(.page(.collectionFull), id: "page-collectionFull", title: "合集详情 · 完整数据"),
        scene(.page(.personLoading), id: "page-personLoading", title: "人物详情 · 加载中"),
        scene(.page(.personFull), id: "page-personFull", title: "人物详情 · 完整数据"),
      ]
    ),
    UIPreviewSection(
      id: "search",
      title: "搜索链路",
      scenes: [
        scene(.search(.unifiedResults), id: "search-unifiedResults", title: "搜索 · 聚合结果"),
        scene(.search(.unifiedEmpty), id: "search-unifiedEmpty", title: "搜索 · 聚合空结果"),
        scene(.search(.resourceLoading), id: "search-resourceLoading", title: "搜索 · 资源加载中"),
        scene(.search(.resourceResults), id: "search-resourceResults", title: "搜索 · 资源结果"),
        scene(.search(.resourceEmpty), id: "search-resourceEmpty", title: "搜索 · 资源空结果"),
        scene(.search(.resourcePageLoading), id: "search-resourcePageLoading", title: "资源结果页 · 加载中"),
        scene(.search(.resourcePageResults), id: "search-resourcePageResults", title: "资源结果页 · 完整数据"),
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
        scene(.status(.transferLoading), id: "status-transferLoading", title: "整理历史 · 加载中"),
        scene(.status(.transferEmpty), id: "status-transferEmpty", title: "整理历史 · 空数据"),
        scene(.status(.transferAiRedoing), id: "status-transferAiRedoing", title: "整理历史 · 多选 / AI 整理中"),
        scene(.status(.transferDetail), id: "status-transferDetail", title: "整理历史 · 详情弹窗"),
      ]
    ),
    UIPreviewSection(
      id: "settings",
      title: "设置",
      scenes: [
        scene(.settings(.fullAccess), id: "settings-fullAccess", title: "设置 · 全权限"),
        scene(.settings(.noSubscribe), id: "settings-noSubscribe", title: "设置 · 无订阅权限"),
        scene(.settings(.noSearch), id: "settings-noSearch", title: "设置 · 无搜索权限"),
        scene(.settings(.appInfo), id: "settings-appInfo", title: "设置 · APP 信息"),
        scene(.settings(.logoutConfirmation), id: "settings-logoutConfirmation", title: "设置 · 退出登录确认"),
      ]
    ),
    UIPreviewSection(
      id: "sheet",
      title: "弹窗",
      scenes: [
        scene(.sheet(.subscribe), id: "sheet-subscribe", title: "订阅弹窗 · 新增"),
        scene(.sheet(.forkSubscribe), id: "sheet-forkSubscribe", title: "订阅分享弹窗 · 复用"),
        scene(.sheet(.addDownload), id: "sheet-addDownload", title: "下载弹窗 · 添加下载"),
        scene(.sheet(.reorganize), id: "sheet-reorganize", title: "整理弹窗 · 单项重整"),
        scene(.sheet(.reorganizeBatch), id: "sheet-reorganizeBatch", title: "整理弹窗 · 批量重整"),
        scene(.sheet(.seasonDetail), id: "sheet-seasonDetail", title: "分季详情弹窗"),
        scene(.sheet(.multiSelection), id: "sheet-multiSelection", title: "多选弹窗 · 站点选择"),
      ]
    ),
    UIPreviewSection(
      id: "component",
      title: "核心组件",
      scenes: [
        scene(.component(.mediaCards), id: "component-mediaCards", title: "组件 · 媒体卡片"),
        scene(.component(.torrentCards), id: "component-torrentCards", title: "组件 · 种子卡片"),
        scene(.component(.pickers), id: "component-pickers", title: "组件 · 选择器 / 输入框"),
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
  case login

  var title: String {
    switch self {
    case .loggedIn: return "启动入口 · 正常已登录"
    case .login: return "启动入口 · 登录页"
    }
  }

  var note: String {
    switch self {
    case .loggedIn: return "TabView 根入口，覆盖首页/推荐/探索/搜索/状态/设置焦点切换。"
    case .login: return "未登录根入口，检查服务器地址、用户名、密码和登录按钮焦点。"
    }
  }
}

private enum UIPreviewHomeMode { case loading, empty, full }
private enum UIPreviewRecommendMode { case loading, empty, full }
private enum UIPreviewExploreMode { case tmdb, share }
private enum UIPreviewCollectionMode { case loading, full }
private enum UIPreviewPersonMode { case loading, full }

private enum UIPreviewPageCase: String, UIPreviewCase {
  case homeLoading
  case homeEmpty
  case homeFull
  case recommendLoading
  case recommendEmpty
  case recommendFull
  case exploreTmdb
  case exploreShare
  case collectionLoading
  case collectionFull
  case personLoading
  case personFull

  var title: String {
    switch self {
    case .homeLoading: return "首页 · 加载中"
    case .homeEmpty: return "首页 · 空数据"
    case .homeFull: return "首页 · 完整数据"
    case .recommendLoading: return "推荐 · 加载中"
    case .recommendEmpty: return "推荐 · 空数据"
    case .recommendFull: return "推荐 · 完整数据"
    case .exploreTmdb: return "探索 · TMDB 筛选"
    case .exploreShare: return "探索 · 订阅分享"
    case .collectionLoading: return "合集详情 · 加载中"
    case .collectionFull: return "合集详情 · 完整数据"
    case .personLoading: return "人物详情 · 加载中"
    case .personFull: return "人物详情 · 完整数据"
    }
  }

  var note: String {
    switch self {
    case .homeLoading: return "首页全屏 Loading，检查 Tab 切入后的焦点落点。"
    case .homeEmpty: return "无最近添加、无电影订阅、无电视剧订阅。"
    case .homeFull: return "最近添加服务器 Picker + 电影/电视剧订阅行 + 行操作菜单。"
    case .recommendLoading: return "推荐页 Paginator 首次加载。"
    case .recommendEmpty: return "推荐页分类/货架存在但网格为空。"
    case .recommendFull: return "推荐页分类、货架和媒体网格完整组合。"
    case .exploreTmdb: return "探索页 TheMovieDb 多 Picker 过滤器。"
    case .exploreShare: return "探索页订阅分享源，卡片触发 Fork 入口。"
    case .collectionLoading: return "合集详情真实根路径加载中。"
    case .collectionFull: return "合集详情网格 + 详情导航。"
    case .personLoading: return "人物详情简介加载占位 + 作品加载。"
    case .personFull: return "人物详情头像/简介/作品网格。"
    }
  }

  var homeMode: UIPreviewHomeMode {
    switch self {
    case .homeLoading: return .loading
    case .homeEmpty: return .empty
    default: return .full
    }
  }

  var recommendMode: UIPreviewRecommendMode {
    switch self {
    case .recommendLoading: return .loading
    case .recommendEmpty: return .empty
    default: return .full
    }
  }

  var exploreMode: UIPreviewExploreMode {
    self == .exploreShare ? .share : .tmdb
  }

  var collectionMode: UIPreviewCollectionMode {
    self == .collectionLoading ? .loading : .full
  }

  var personMode: UIPreviewPersonMode {
    self == .personLoading ? .loading : .full
  }
}

private enum UIPreviewDetailCase: String, UIPreviewCase {
  case loading
  case tvWithSeasons
  case tvWithoutSeasons
  case seasonLoadFailed
  case noArtwork
  case noSubscribePermission
  case noSearchPermission

  var title: String {
    switch self {
    case .loading: return "详情页 · 加载中"
    case .tvWithSeasons: return "详情页 · 电视剧，有分季"
    case .tvWithoutSeasons: return "详情页 · 电视剧，无分季"
    case .seasonLoadFailed: return "详情页 · 分季加载失败"
    case .noArtwork: return "详情页 · 无海报 / 无背景图"
    case .noSubscribePermission: return "详情页 · 无订阅权限"
    case .noSearchPermission: return "详情页 · 无搜索权限"
    }
  }

  var note: String {
    switch self {
    case .loading: return "保持 Loading 遮罩，验证焦点不会落到下层详情。"
    case .tvWithSeasons: return "Header 分季订阅 + 第二页分季横向 Shelf。"
    case .tvWithoutSeasons: return "分季加载完成但为空，Header 显示不可用状态。"
    case .seasonLoadFailed: return "分季区域保留错误 Banner，可关闭错误提示。"
    case .noArtwork: return "背景和海报都为空，验证占位背景与文字可读性。"
    case .noSubscribePermission: return "隐藏订阅入口，只保留搜索和 TMDB 跳转。"
    case .noSearchPermission: return "隐藏搜索和站点筛选，只保留分季订阅。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .noSubscribePermission:
      return [.discovery, .search, .manage]
    case .noSearchPermission:
      return [.discovery, .subscribe, .manage]
    default:
      return .allPreviewPermissions
    }
  }
}

private enum UIPreviewSeasonCase: String, UIPreviewCase {
  case loading
  case seasons
  case empty
  case failed
  case mixedSubscription

  var title: String {
    switch self {
    case .loading: return "分季页 · 加载中"
    case .seasons: return "分季页 · 普通多季"
    case .empty: return "分季页 · 空数据"
    case .failed: return "分季页 · 加载失败"
    case .mixedSubscription: return "分季页 · 已订阅 / 缺集混合"
    }
  }

  var note: String {
    switch self {
    case .loading: return "Grid 根路径中的加载态。"
    case .seasons: return "多季卡片、剧集组 Picker 和焦点重定向。"
    case .empty: return "无季集信息空态。"
    case .failed: return "错误 Banner + 空态组合。"
    case .mixedSubscription: return "已订阅、完整入库、部分缺失、整季缺失组合。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    .allPreviewPermissions
  }
}

private enum UIPreviewResourcePageMode { case loading, results }

private enum UIPreviewSearchCase: String, UIPreviewCase {
  case unifiedResults
  case unifiedEmpty
  case resourceLoading
  case resourceResults
  case resourceEmpty
  case resourcePageLoading
  case resourcePageResults

  var title: String {
    switch self {
    case .unifiedResults: return "搜索 · 聚合结果"
    case .unifiedEmpty: return "搜索 · 聚合空结果"
    case .resourceLoading: return "搜索 · 资源加载中"
    case .resourceResults: return "搜索 · 资源结果"
    case .resourceEmpty: return "搜索 · 资源空结果"
    case .resourcePageLoading: return "资源结果页 · 加载中"
    case .resourcePageResults: return "资源结果页 · 完整数据"
    }
  }

  var note: String {
    switch self {
    case .unifiedResults: return "最佳结果、电影、电视剧、合集、人物、订阅分享多行组合。"
    case .unifiedEmpty: return "搜索完成但没有任何聚合结果。"
    case .resourceLoading: return "资源模式流式进度文案和进度条。"
    case .resourceResults: return "资源模式结果筛选栏 + 种子卡片。"
    case .resourceEmpty: return "资源模式搜索完成但无资源。"
    case .resourcePageLoading: return "从详情/菜单进入的资源结果页加载中。"
    case .resourcePageResults: return "资源结果页背景图 + 筛选栏 + 种子卡片。"
    }
  }

  var resourcePageMode: UIPreviewResourcePageMode {
    self == .resourcePageLoading ? .loading : .results
  }
}

private enum UIPreviewStatusMode { case empty, full }
private enum UIPreviewDownloadMode { case empty, multiState }
private enum UIPreviewTransferMode { case loading, empty, aiRedoing }

private enum UIPreviewStatusCase: String, UIPreviewCase {
  case statusEmpty
  case statusFull
  case downloadEmpty
  case downloadMultiState
  case transferLoading
  case transferEmpty
  case transferAiRedoing
  case transferDetail

  var title: String {
    switch self {
    case .statusEmpty: return "状态页 · 空权限 / 空数据"
    case .statusFull: return "状态页 · 完整数据"
    case .downloadEmpty: return "下载任务 · 空数据"
    case .downloadMultiState: return "下载任务 · 多状态任务"
    case .transferLoading: return "整理历史 · 加载中"
    case .transferEmpty: return "整理历史 · 空数据"
    case .transferAiRedoing: return "整理历史 · 多选 / AI 整理中"
    case .transferDetail: return "整理历史 · 详情弹窗"
    }
  }

  var note: String {
    switch self {
    case .statusEmpty: return "统计、存储、下载器为空，任务列表为空。"
    case .statusFull: return "统计卡、存储、下载器、下载任务、整理历史组合。"
    case .downloadEmpty: return "下载任务标题区、下载器 Picker 和空态。"
    case .downloadMultiState: return "下载中、暂停、错误、校验等状态徽标和 ActionRow。"
    case .transferLoading: return "整理历史首次加载中。"
    case .transferEmpty: return "整理历史空态。"
    case .transferAiRedoing: return "多选、AI 整理中遮罩和行操作按钮。"
    case .transferDetail: return "整理历史长按详情弹窗，检查路径、存储名和状态信息。"
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
    case .transferEmpty: return .empty
    default: return .aiRedoing
    }
  }
}

private enum UIPreviewSettingsCase: String, UIPreviewCase {
  case fullAccess
  case noSubscribe
  case noSearch
  case appInfo
  case logoutConfirmation

  var title: String {
    switch self {
    case .fullAccess: return "设置 · 全权限"
    case .noSubscribe: return "设置 · 无订阅权限"
    case .noSearch: return "设置 · 无搜索权限"
    case .appInfo: return "设置 · APP 信息"
    case .logoutConfirmation: return "设置 · 退出登录确认"
    }
  }

  var note: String {
    switch self {
    case .fullAccess: return "订阅、详情页、搜索站点、自定义过滤、连接信息全部可见。"
    case .noSubscribe: return "隐藏订阅设置，保留详情页和搜索设置。"
    case .noSearch: return "隐藏资源搜索设置，保留订阅和详情页设置。"
    case .appInfo: return "设置页 App 信息 Sheet，检查版本、兼容版本和链接行。"
    case .logoutConfirmation: return "退出登录系统 Alert，检查取消/确认焦点。"
    }
  }

  var permissions: Set<UserPermissionKey> {
    switch self {
    case .fullAccess, .appInfo, .logoutConfirmation: return .allPreviewPermissions
    case .noSubscribe: return [.discovery, .search, .manage]
    case .noSearch: return [.discovery, .subscribe, .manage]
    }
  }

  var canRequestSuperUserEndpoints: Bool {
    switch self {
    case .fullAccess, .appInfo, .logoutConfirmation:
      return true
    case .noSubscribe, .noSearch:
      return false
    }
  }

  var presentation: SystemViewUIPreviewPresentation? {
    switch self {
    case .appInfo:
      return .appInfo
    case .logoutConfirmation:
      return .logoutConfirmation
    case .fullAccess, .noSubscribe, .noSearch:
      return nil
    }
  }
}

private enum UIPreviewSheetCase: String, UIPreviewCase {
  case subscribe
  case forkSubscribe
  case addDownload
  case reorganize
  case reorganizeBatch
  case seasonDetail
  case multiSelection

  var title: String {
    switch self {
    case .subscribe: return "订阅弹窗 · 新增"
    case .forkSubscribe: return "订阅分享弹窗 · 复用"
    case .addDownload: return "下载弹窗 · 添加下载"
    case .reorganize: return "整理弹窗 · 单项重整"
    case .reorganizeBatch: return "整理弹窗 · 批量重整"
    case .seasonDetail: return "分季详情弹窗"
    case .multiSelection: return "多选弹窗 · 站点选择"
    }
  }

  var note: String {
    switch self {
    case .subscribe: return "新增订阅表单、站点/下载器/保存路径/高级配置入口。"
    case .forkSubscribe: return "订阅分享复用入口，检查海报、分享人和复用按钮焦点。"
    case .addDownload: return "添加下载表单、种子信息、下载器、保存路径和 TMDB ID。"
    case .reorganize: return "重新整理表单、目的存储、整理方式、剧集定位和高级配置。"
    case .reorganizeBatch: return "整理历史批量重整表单，检查无单文件时的字段状态。"
    case .seasonDetail: return "分季详情弹窗，检查海报、播出日期、评分和简介。"
    case .multiSelection: return "多选 Sheet、禁用项说明和确认按钮焦点。"
    }
  }
}

private enum UIPreviewComponentCase: String, UIPreviewCase {
  case mediaCards
  case torrentCards
  case pickers
  case notification

  var title: String {
    switch self {
    case .mediaCards: return "组件 · 媒体卡片"
    case .torrentCards: return "组件 · 种子卡片"
    case .pickers: return "组件 · 选择器 / 输入框"
    case .notification: return "组件 · 通知"
    }
  }

  var note: String {
    switch self {
    case .mediaCards: return "普通媒体、无图、合集、订阅分享、加载更多组合。"
    case .torrentCards: return "免费、促销、软过滤、低做种等种子卡片组合。"
    case .pickers: return "Segmented Picker、ShelfPicker、SheetPicker、SheetTextField。"
    case .notification: return "信息/成功/警告/错误四类通知和悬浮提示。"
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

  @discardableResult
  static func installDetail(_ detailCase: UIPreviewDetailCase) -> MediaInfo {
    applyPermissions(
      detailCase.permissions,
      canRequestSuperUserEndpoints: detailCase.permissions.contains(.manage)
    )
    MediaPreloader.shared.clearAll()

    let media = detailMedia(detailCase)
    let task = MediaPreloadTask(partialMedia: media)

    if detailCase != .loading {
      task.fullDetail = media
      task.isDetailReady = true
      task.tmdbId = media.tmdb_id
      task.isSubscribed = false
    }

    switch detailCase {
    case .tvWithSeasons, .noArtwork, .noSearchPermission:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .mixedSubscription)
      task.isSeasonDataLoaded = true
    case .tvWithoutSeasons:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .empty)
      task.isSeasonDataLoaded = true
    case .seasonLoadFailed:
      task.seasonViewModel = seasonViewModel(mediaInfo: media, initialSeason: nil, mode: .failed)
      task.isSeasonDataLoaded = true
    case .loading, .noSubscribePermission:
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
    }
    return viewModel
  }

  static func recommendViewModel(_ mode: UIPreviewRecommendMode) -> RecommendViewModel {
    let viewModel = RecommendViewModel(loadsAutomatically: false)
    viewModel.selectedCategory = .movie
    viewModel.selectedShelf = RecommendViewModel.allShelves.first { $0.category == .movie }
    switch mode {
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
    case .tmdb:
      viewModel.selectedSource = .themoviedb
      viewModel.selectedType = .movies
      viewModel.tmdbGenre = "878"
      viewModel.tmdbLanguage = "ja"
      viewModel.installUIPreviewPaginator(.uiPreview(items: previewMediaGrid, isLoadingMore: true))
    case .share:
      viewModel.selectedSource = .subscriptionShare
      viewModel.selectedType = .tvs
      viewModel.shareGenre = "10765"
      viewModel.installUIPreviewPaginator(.uiPreview(items: [
        shareMedia(id: 33_001, title: "高质量订阅分享 · 边境信号"),
        shareMedia(id: 33_002, title: "整季打包分享 · 海岸档案"),
      ]))
    }
    return viewModel
  }

  static func searchViewModel(_ searchCase: UIPreviewSearchCase) -> SearchViewModel {
    let viewModel = SearchViewModel()
    viewModel.siteFilter.availableSites = sites
    viewModel.siteFilter.selectedSites = [1, 3]
    switch searchCase {
    case .unifiedResults:
      let movies = [movieMedia(id: 34_001, title: "边境信号：序章")]
      let tvShows = [baseTVMedia(id: 34_101, title: "边境信号")]
      let collections = [collectionMedia(id: 34_201, title: "边境信号系列")]
      let people = [person(id: 34_301, name: "林原真", character: "导演")]
      let shares = [shareMedia(id: 34_401, title: "边境信号 订阅分享")]
      viewModel.installUIPreviewUnifiedResults(
        query: "边境信号",
        movies: movies,
        tvShows: tvShows,
        collections: collections,
        persons: people,
        shares: shares,
        bestResults: [.media(tvShows[0]), .person(people[0]), .media(shares[0])]
      )
    case .unifiedEmpty:
      viewModel.installUIPreviewUnifiedEmpty(query: "没有结果的关键词")
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
    case .resourcePageLoading, .resourcePageResults:
      break
    }
    return viewModel
  }

  static func collectionViewModel(_ mode: UIPreviewCollectionMode) -> CollectionDetailViewModel {
    switch mode {
    case .loading:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(isFirstLoading: true))
    case .full:
      return CollectionDetailViewModel(previewPaginator: .uiPreview(items: previewMediaGrid))
    }
  }

  static func personViewModel(_ mode: UIPreviewPersonMode) -> PersonDetailViewModel {
    let previewPerson = person(
      id: 35_001,
      name: "林原真",
      character: nil,
      biography: mode == .loading ? nil : "长期活跃于科幻与悬疑题材的导演，作品以冷静的工业质感和细密的人物关系见长。这段长简介用于检查可聚焦简介卡片、Sheet 展开和多行文本。"
    )
    switch mode {
    case .loading:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(isFirstLoading: true),
        isLoadingDetails: true
      )
    case .full:
      return PersonDetailViewModel(
        person: previewPerson,
        previewPaginator: .uiPreview(items: previewMediaGrid),
        isLoadingDetails: false
      )
    }
  }

  static func resourceResultViewModel(_ mode: UIPreviewResourcePageMode) -> ResourceResultViewModel {
    ResourceResultViewModel(
      previewTitle: "边境信号",
      mediaInfo: baseTVMedia(id: 36_001, title: "边境信号"),
      results: mode == .loading ? [] : contexts,
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
      availableSites: settingsCase == .noSearch ? [] : sites,
      customFilterRules: settingsCase == .fullAccess ? customRules : [],
      isRefreshing: false,
      refreshMessage: "上次刷新成功"
    )
    return viewModel
  }

  static func subscribeSheetViewModel() -> SubscribeSheetViewModel {
    let viewModel = SubscribeSheetViewModel(
      subscribe: subscribe(id: 45_001, name: "边境信号", type: "电视剧", state: "S", lack: 6),
      isNewSubscription: true
    )
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
    return viewModel
  }

  static func addDownloadViewModel() -> AddDownloadViewModel {
    let viewModel = AddDownloadViewModel(
      torrent: contexts[0].torrent_info!,
      media: baseTVMedia(id: 45_101, title: "边境信号")
    )
    viewModel.installUIPreviewOptions(
      downloaders: downloaders,
      directories: directories,
      selectedDownloader: "qb-main",
      selectedDirectory: "/downloads/tv",
      tmdbId: "90101"
    )
    return viewModel
  }

  static func reorganizeViewModel() -> ReorganizeViewModel {
    let viewModel = ReorganizeViewModel(
      logIds: [44_001],
      fileItem: fileItem(name: "Frontier.Signal.S01E01.mkv", path: "/downloads/Frontier.Signal.S01E01.mkv"),
      targetStorage: "local"
    )
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
    return seasonViewModel(mediaInfo: baseTVMedia(id: 91_100, title: "分季预览剧集"), initialSeason: nil, mode: seasonCase)
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
    mode: UIPreviewSeasonCase
  ) -> SubscribeSeasonViewModel {
    let viewModel = SubscribeSeasonViewModel(mediaInfo: mediaInfo, initialSeason: initialSeason)

    switch mode {
    case .loading:
      viewModel.isLoading = true
    case .seasons:
      viewModel.episodeGroups = [episodeGroup(id: "preview-main", name: "官方顺序")]
      viewModel.seasonInfos = previewSeasons
      viewModel.seasonsNotExisted = [:]
      viewModel.isSeasonAvailabilityLoaded = true
    case .empty:
      viewModel.seasonInfos = []
      viewModel.isSeasonAvailabilityLoaded = true
    case .failed:
      viewModel.hasSeasonLoadError = true
      viewModel.errorMessage = "预览：分季接口加载失败"
      viewModel.isSeasonAvailabilityLoaded = true
    case .mixedSubscription:
      viewModel.episodeGroups = [
        episodeGroup(id: "preview-main", name: "官方顺序"),
        episodeGroup(id: "preview-alt", name: "播出顺序"),
      ]
      viewModel.seasonInfos = previewSeasons
      viewModel.seasonsNotExisted = [1: 0, 2: 1, 3: 2]
      viewModel.isSeasonAvailabilityLoaded = true
      viewModel.seasonSubscriptions = [
        1: SeasonSubscriptionSummary(id: 90_001, season: 1, episodeGroup: nil)
      ]
      viewModel.subscribedSeasons = [1]
    }

    return viewModel
  }

  private static func detailMedia(_ detailCase: UIPreviewDetailCase) -> MediaInfo {
    switch detailCase {
    case .loading:
      return baseTVMedia(id: 90_001, title: "边境信号 · 加载中")
    case .tvWithSeasons:
      return baseTVMedia(id: 90_002, title: "边境信号")
    case .tvWithoutSeasons:
      return baseTVMedia(id: 90_003, title: "边境信号 · 无分季")
    case .seasonLoadFailed:
      return baseTVMedia(id: 90_004, title: "边境信号 · 分季失败")
    case .noArtwork:
      return baseTVMedia(id: 90_005, title: "边境信号 · 无图", hasArtwork: false)
    case .noSubscribePermission:
      return baseTVMedia(id: 90_006, title: "边境信号 · 无订阅权限")
    case .noSearchPermission:
      return baseTVMedia(id: 90_007, title: "边境信号 · 无搜索权限")
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
