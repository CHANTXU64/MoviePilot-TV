import XCTest

@testable import MoviePilot_TV

final class UIPreviewModeTests: XCTestCase {
  func testPreviewModeRequiresExplicitLaunchArgument() {
    XCTAssertTrue(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV", "-uiPreviewMode"]))
    XCTAssertFalse(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV"]))
    XCTAssertFalse(UIPreviewMode.isEnabled(arguments: ["MoviePilot-TV", "uiPreviewMode"]))
  }

  func testLaunchArgumentMatchesDocumentedEntryPoint() {
    XCTAssertEqual(UIPreviewMode.launchArgument, "-uiPreviewMode")
  }

  func testContentViewPreviewEntryIsDebugOnly() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Views/ContentView.swift"))

    XCTAssertTrue(source.contains("#if DEBUG"))
    XCTAssertTrue(source.contains("UIPreviewMode.isEnabled()"))
    XCTAssertTrue(source.contains("PreviewCatalogView()"))
  }

  func testPreviewSupportFilesAreDebugWrapped() throws {
    let fileManager = FileManager.default
    let directory = repoFile("MoviePilot-TV/PreviewSupport")
    let files = try fileManager.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".swift") }

    XCTAssertFalse(files.isEmpty)

    for file in files {
      let source = try String(contentsOf: directory.appendingPathComponent(file))
      XCTAssertTrue(
        source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#if DEBUG"),
        "\(file) must be compiled only in DEBUG."
      )
    }
  }

  func testPreviewCatalogCoversAllManualReviewAreas() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredSections = [
      "App 入口 / Tab 页面",
      "详情页",
      "分季页",
      "搜索链路",
      "状态 / 任务",
      "设置",
      "弹窗",
      "核心组件",
    ]

    for section in requiredSections {
      XCTAssertTrue(source.contains("title: \"\(section)\""), "Missing preview section: \(section)")
    }

    let requiredScenes = [
      "启动入口 · 正常已登录",
      "启动入口 · 登录页",
      "首页 · 加载中",
      "首页 · 空数据",
      "首页 · 完整数据",
      "推荐 · 加载中",
      "推荐 · 空数据",
      "推荐 · 完整数据",
      "探索 · TMDB 筛选",
      "探索 · 订阅分享",
      "搜索 · 聚合结果",
      "搜索 · 聚合空结果",
      "搜索 · 资源加载中",
      "搜索 · 资源结果",
      "搜索 · 资源空结果",
      "合集详情 · 加载中",
      "合集详情 · 完整数据",
      "人物详情 · 加载中",
      "人物详情 · 完整数据",
      "资源结果页 · 加载中",
      "资源结果页 · 完整数据",
      "状态页 · 空权限 / 空数据",
      "状态页 · 完整数据",
      "下载任务 · 空数据",
      "下载任务 · 多状态任务",
      "整理历史 · 加载中",
      "整理历史 · 空数据",
      "整理历史 · 多选 / AI 整理中",
      "整理历史 · 详情弹窗",
      "设置 · 全权限",
      "设置 · 无订阅权限",
      "设置 · 无搜索权限",
      "设置 · APP 信息",
      "设置 · 退出登录确认",
      "订阅弹窗 · 新增",
      "订阅分享弹窗 · 复用",
      "下载弹窗 · 添加下载",
      "整理弹窗 · 单项重整",
      "整理弹窗 · 批量重整",
      "分季详情弹窗",
      "多选弹窗 · 站点选择",
      "组件 · 媒体卡片",
      "组件 · 种子卡片",
      "组件 · 选择器 / 输入框",
      "组件 · 通知",
    ]

    for scene in requiredScenes {
      XCTAssertTrue(source.contains("title: \"\(scene)\""), "Missing preview scene: \(scene)")
    }
  }

  func testPreviewCatalogReferencesPrimaryPageSheetAndComponentViews() throws {
    let source = try [
      "MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift",
      "MoviePilot-TV/Views/Pages/SearchView.swift",
      "MoviePilot-TV/Views/Pages/StatusView.swift",
    ]
    .map { try String(contentsOf: repoFile($0)) }
    .joined(separator: "\n")

    let requiredViewEntries = [
      "LoginView(",
      "HomeView(",
      "RecommendView(",
      "ExploreView(",
      "SearchView(",
      "StatusView(",
      "SystemView(",
      "CollectionDetailView(",
      "PersonDetailView(",
      "MediaDetailContainerView(",
      "SubscribeSeasonView(",
      "ResourceResultView(",
      "DownloadTaskView(",
      "TransferHistoryView(",
      "SubscribeSheet(",
      "ForkSubscribeSheet(",
      "AddDownloadSheet(",
      "ReorganizeSheet(",
      "MultiSelectionSheet(",
      "SeasonDetailSheet(",
      "MediaGridView(",
      "TorrentCard(",
      "CategoryPickerView(",
      "ShelfPicker(",
      "SheetPicker(",
      "SheetTextField(",
      "NotificationView(",
    ]

    for viewEntry in requiredViewEntries {
      XCTAssertTrue(
        source.contains(viewEntry),
        "Preview catalog must route through primary UI entry: \(viewEntry)"
      )
    }
  }

  func testPreviewCatalogPresentsScenesAsRootViews() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    XCTAssertTrue(source.contains("@State private var selectedScene: UIPreviewScene?"))
    XCTAssertTrue(source.contains("if let selectedScene"))
    XCTAssertTrue(source.contains("UIPreviewCatalogHomeView { scene in"))
    XCTAssertTrue(source.contains("selectedScene = scene"))
    XCTAssertTrue(source.contains("UIPreviewSceneDestination(scene: selectedScene)"))
    XCTAssertTrue(source.contains(".onExitCommand"))
    XCTAssertTrue(source.contains(".navigationTitle(\"UI 预览\")"))
    XCTAssertEqual(source.components(separatedBy: ".navigationTitle(").count - 1, 1)
    XCTAssertTrue(source.contains("ScrollView {"))
    XCTAssertTrue(source.contains("Button {"))
    XCTAssertFalse(source.contains("List {"))
    XCTAssertFalse(source.contains("NavigationLink(value: scene)"))
    XCTAssertFalse(source.contains(".navigationDestination(for: UIPreviewScene.self)"))
    XCTAssertFalse(source.contains("path.append(scene)"))
    XCTAssertFalse(source.contains("ToolbarItem(placement: .navigationBarLeading)"))
    XCTAssertFalse(source.contains("返回目录"))
  }

  func testTopLevelPreviewScenesPreserveRealTabRoot() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredTabLabels = [
      "Label(\"媒体库\", systemImage: \"play.tv\")",
      "Label(\"推荐\", systemImage: \"sparkles.tv\")",
      "Label(\"探索\", systemImage: \"safari\")",
      "Label(\"搜索\", systemImage: \"magnifyingglass\")",
      "Label(\"状态\", systemImage: \"slider.horizontal.3\")",
      "Label(\"设置\", systemImage: \"gear\")",
    ]

    for tabLabel in requiredTabLabels {
      XCTAssertTrue(source.contains(tabLabel), "Missing real TabView entry: \(tabLabel)")
    }

    let requiredPreviewRoutes = [
      "UIPreviewLoggedInRootView(selectedTab: .home, homeMode: previewCase.homeMode)",
      "UIPreviewLoggedInRootView(selectedTab: .recommend, recommendMode: previewCase.recommendMode)",
      "UIPreviewLoggedInRootView(selectedTab: .explore, exploreMode: previewCase.exploreMode)",
      "UIPreviewLoggedInRootView(selectedTab: .search, searchCase: searchCase)",
      "selectedTab: .status",
      "selectedTab: .system",
    ]

    for route in requiredPreviewRoutes {
      XCTAssertTrue(source.contains(route), "Preview scene must keep the real TabView root: \(route)")
    }

    XCTAssertFalse(source.contains("HomeView(viewModel: UIPreviewFixtures.homeViewModel"))
    XCTAssertFalse(source.contains("RecommendView(viewModel: UIPreviewFixtures.recommendViewModel"))
    XCTAssertFalse(source.contains("SearchView(viewModel: UIPreviewFixtures.searchViewModel"))
  }

  func testDeepPreviewScenesPreserveRealTabRoot() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let searchSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SearchView.swift"))

    let requiredRoutes = [
      "searchPreviewDestinations: SearchViewUIPreviewDestinations(",
      "collectionViewModel: UIPreviewFixtures.collectionViewModel(mode)",
      "personViewModel: viewModel",
      "seasonViewModel: viewModel",
      "resourceResultViewModel: UIPreviewFixtures.resourceResultViewModel(mode)",
      "searchInitialPath: media.previewNavigationPath()",
      "searchInitialPath: viewModel.person.previewNavigationPath()",
      "searchInitialPath: request.previewNavigationPath()",
    ]

    for route in requiredRoutes {
      XCTAssertTrue(source.contains(route), "Deep preview scene must keep the real TabView root: \(route)")
    }

    XCTAssertTrue(searchSource.contains("SearchViewUIPreviewDestinations"))
    XCTAssertTrue(searchSource.contains("CollectionDetailView("))
    XCTAssertTrue(searchSource.contains("PersonDetailView(previewViewModel: previewViewModel"))
    XCTAssertTrue(searchSource.contains("ResourceResultView("))
    XCTAssertTrue(searchSource.contains("SubscribeSeasonView(previewViewModel: previewViewModel)"))
    XCTAssertFalse(source.contains("NavigationStack {\n      SubscribeSeasonView(previewViewModel: viewModel)"))
    XCTAssertFalse(source.contains("ResourceResultView(\n      title: mode"))
  }

  func testPreviewRootDoesNotAddPreviewNavigationChrome() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let functionRange = try XCTUnwrap(source.range(of: "func previewRoot(_ title: String) -> some View"))
    let functionSource = String(source[functionRange.lowerBound...])
      .prefix(200)

    XCTAssertFalse(functionSource.contains("NavigationStack"))
    XCTAssertFalse(functionSource.contains(".navigationTitle(title)"))
  }

  func testDetailPreviewStartsAsNativeNavigationDestination() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let homeSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/HomeView.swift"))

    XCTAssertTrue(source.contains("homeInitialPath: initialPath"))
    XCTAssertTrue(source.contains("path.append(media)"))
    XCTAssertTrue(source.contains("HomeView(viewModel: homeViewModel, loadsDataOnAppear: false, initialPath: homeInitialPath)"))
    XCTAssertTrue(homeSource.contains("MediaDetailContainerView(media: mediaInfo, navigationPath: $path)"))
    XCTAssertFalse(source.contains(".navigationDestination(for: String.self)"))
    XCTAssertFalse(source.contains("path.append(\"detail\")"))
    XCTAssertFalse(source.contains(".navigationTitle(detailCase.title)"))
  }

  func testPreviewCatalogDoesNotContainSyntheticComponentPlayground() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    XCTAssertFalse(source.contains("组件 · 空态 / 操作行"))
    XCTAssertFalse(source.contains("UIPreviewEmptyAndActionRows"))
    XCTAssertFalse(source.contains("Color.green"))
  }

  func testReleaseVisiblePreviewControlSignaturesAreNotExposed() throws {
    let forbiddenSignaturesByFile = [
      "MoviePilot-TV/Views/Pages/HomeView.swift": [
        "init(viewModel: HomeViewModel? = nil, loadsDataOnAppear: Bool = true)"
      ],
      "MoviePilot-TV/Views/Pages/DownloadTaskView.swift": [
        "init(viewModel: DownloadTaskViewModel? = nil, refreshesOnAppear: Bool = true)"
      ],
      "MoviePilot-TV/Views/Pages/SearchView.swift": [
        "init(viewModel: SearchViewModel? = nil, loadsSitesOnAppear: Bool = true)"
      ],
      "MoviePilot-TV/Views/Pages/StatusView.swift": [
        "viewModel: StatusViewModel? = nil",
        "downloadTaskViewModel: DownloadTaskViewModel? = nil",
        "transferHistoryViewModel: TransferHistoryViewModel? = nil",
        "refreshesOnAppear: Bool = true",
      ],
      "MoviePilot-TV/Views/Pages/SystemView.swift": [
        "init(isSelected: Bool = true, viewModel: SystemViewModel? = nil, loadsDataOnAppear: Bool = true)"
      ],
      "MoviePilot-TV/Views/Pages/TransferHistoryView.swift": [
        "init(viewModel: TransferHistoryViewModel, refreshesOnAppear: Bool = true)"
      ],
      "MoviePilot-TV/ViewModels/ExploreViewModel.swift": [
        "init(loadsAutomatically: Bool = true)"
      ],
      "MoviePilot-TV/ViewModels/RecommendViewModel.swift": [
        "init(loadsAutomatically: Bool = true)"
      ],
      "MoviePilot-TV/Views/Pages/RecommendView.swift": [
        "init(viewModel: RecommendViewModel? = nil)"
      ],
      "MoviePilot-TV/Views/Pages/ExploreView.swift": [
        "init(viewModel: ExploreViewModel? = nil)"
      ],
    ]

    for (file, signatures) in forbiddenSignaturesByFile {
      let source = try String(contentsOf: repoFile(file))
      for signature in signatures {
        XCTAssertFalse(source.contains(signature), "\(file) exposes preview-only control: \(signature)")
      }
    }
  }

  func testPreviewModeShortCircuitsBackendActions() throws {
    let requiredSnippetsByFile = [
      "MoviePilot-TV/ViewModels/ContentViewModel.swift": [
        "if UIPreviewMode.isEnabled() { return }",
        "apiService.$token",
        "UIApplication.willEnterForegroundNotification",
      ],
      "MoviePilot-TV/ViewModels/MediaPreloader.swift": [
        "return uiPreviewTask(for: media)",
      ],
      "MoviePilot-TV/ViewModels/MediaActionHandler.swift": [
        "return searchResourcesTarget(for: item)",
        "tmdbIdToUse = 900_000",
      ],
      "MoviePilot-TV/ViewModels/HomeViewModel.swift": [
        "private func persistSelectedLatestMediaServer()",
        "func toggleSubscribeStatus(subscribe: Subscribe) async -> Bool",
        "func resetSubscribe(subscribe: Subscribe) async -> Bool",
        "func searchSubscribe(subscribe: Subscribe) async -> Bool",
        "func deleteSubscribe(subscribe: Subscribe) async -> Bool",
      ],
      "MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift": [
        "func checkSubscriptionStatus(forceRefresh: Bool = false) async -> Bool",
        "func unsubscribeSeason(_ seasonNumber: Int) async",
      ],
      "MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift": [
        "func save() async -> Bool",
        "func cancel() async",
      ],
      "MoviePilot-TV/ViewModels/SubscriptionHandler.swift": [
        "func handleSubscribe(_ item: MediaInfo)",
        "func fork(share: SubscribeShare) async -> Int?",
      ],
      "MoviePilot-TV/ViewModels/AddDownloadViewModel.swift": [
        "func addDownload() async",
      ],
      "MoviePilot-TV/ViewModels/ReorganizeViewModel.swift": [
        "func submit(background: Bool) async -> Bool",
      ],
      "MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift": [
        "func stopDownload(hash: String) async -> Bool",
        "func startDownload(hash: String) async -> Bool",
        "func deleteDownload(hash: String) async",
      ],
      "MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift": [
        "func deleteHistory(item: TransferHistory, deleteSource: Bool, deleteDest: Bool) async",
        "func deleteSelected(deleteSource: Bool, deleteDest: Bool) async",
        "func triggerAiRedo(for ids: [Int]) async",
      ],
    ]

    for (file, snippets) in requiredSnippetsByFile {
      let source = try String(contentsOf: repoFile(file))
      XCTAssertTrue(source.contains("UIPreviewMode.isEnabled()"), "\(file) must guard UI preview backend actions.")
      for snippet in snippets {
        XCTAssertTrue(source.contains(snippet), "\(file) missing preview action guard near \(snippet)")
      }
    }
  }

  func testPreviewModeSkipsStartupSettingsAndHomePersistence() throws {
    let contentSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/ContentViewModel.swift"))
    let previewGuardRange = try XCTUnwrap(contentSource.range(of: "if UIPreviewMode.isEnabled() { return }"))
    let tokenSinkRange = try XCTUnwrap(contentSource.range(of: "apiService.$token"))
    let foregroundRange = try XCTUnwrap(contentSource.range(of: "UIApplication.willEnterForegroundNotification"))
    XCTAssertLessThan(previewGuardRange.lowerBound, tokenSinkRange.lowerBound)
    XCTAssertLessThan(previewGuardRange.lowerBound, foregroundRange.lowerBound)

    let homeSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/HomeViewModel.swift"))
    let persistRange = try XCTUnwrap(homeSource.range(of: "private func persistSelectedLatestMediaServer()"))
    let persistSource = String(homeSource[persistRange.lowerBound...]).prefix(220)
    XCTAssertTrue(persistSource.contains("if UIPreviewMode.isEnabled() { return }"))
    XCTAssertTrue(persistSource.contains("UserDefaults.standard.set"))
  }

  func testPreviewPermissionsAreInstalledBeforeFirstPreviewFrame() throws {
    let previewSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let initStart = try XCTUnwrap(
      previewSource.range(of: "init(\n    selectedTab: ContentViewModel.Tab = .home")
    )
    let bodyStart = try XCTUnwrap(previewSource.range(of: "\n  var body: some View", range: initStart.upperBound..<previewSource.endIndex))
    let initSource = String(previewSource[initStart.lowerBound..<bodyStart.lowerBound])
    let applyRange = try XCTUnwrap(initSource.range(of: "UIPreviewFixtures.applyPermissions("))
    let firstStateObjectRange = try XCTUnwrap(initSource.range(of: "_homeViewModel = StateObject"))

    XCTAssertLessThan(applyRange.lowerBound, firstStateObjectRange.lowerBound)

    let apiSource = try String(contentsOf: repoFile("MoviePilot-TV/Services/APIService.swift"))
    XCTAssertTrue(apiSource.contains("return uiPreviewCanRequestSuperUserEndpoints ?? false"))
    XCTAssertTrue(apiSource.contains("return uiPreviewPermissions?.contains(permission) ?? false"))

    let sheetStart = try XCTUnwrap(previewSource.range(of: "private struct UIPreviewSheetSceneView: View"))
    let sheetEnd = try XCTUnwrap(
      previewSource.range(of: "\n@MainActor\nprivate struct UIPreviewMultiSelectionSheet", range: sheetStart.upperBound..<previewSource.endIndex)
    )
    let sheetSource = String(previewSource[sheetStart.lowerBound..<sheetEnd.lowerBound])
    let sheetInitRange = try XCTUnwrap(sheetSource.range(of: "init(sheetCase: UIPreviewSheetCase)"))
    let sheetBodyRange = try XCTUnwrap(sheetSource.range(of: "\n  var body: some View"))
    let sheetApplyRange = try XCTUnwrap(
      sheetSource.range(of: "UIPreviewFixtures.applyPermissions(", range: sheetInitRange.lowerBound..<sheetBodyRange.lowerBound)
    )
    let addDownloadRange = try XCTUnwrap(sheetSource.range(of: "AddDownloadSheet("))

    XCTAssertLessThan(sheetApplyRange.lowerBound, addDownloadRange.lowerBound)
    XCTAssertFalse(sheetSource.contains(".onAppear { UIPreviewFixtures.applyPermissions("))
  }

  private func repoFile(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(path)
  }
}
