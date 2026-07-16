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

  func testPreviewSceneLaunchArgumentSelectsSpecificCatalogScene() {
    XCTAssertEqual(
      UIPreviewMode.sceneID(arguments: ["MoviePilot-TV", "-uiPreviewMode", "-uiPreviewScene", "detail-tvWithSeasons"]),
      "detail-tvWithSeasons"
    )
    XCTAssertNil(UIPreviewMode.sceneID(arguments: ["MoviePilot-TV", "-uiPreviewMode"]))
    XCTAssertNil(UIPreviewMode.sceneID(arguments: ["MoviePilot-TV", "-uiPreviewScene"]))
  }

  func testInitialPreviewSceneResetsStateBeforeResolvingScene() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let initSource = try sourceSlice(
      source,
      from: "init(initialSceneID: String? = nil)",
      to: "\n\n  var body"
    )

    XCTAssertTrue(initSource.contains("UIPreviewFixtures.resetPreviewState()"))
    XCTAssertTrue(initSource.contains("_didResetPreviewState = State(initialValue: true)"))

    let resetRange = try XCTUnwrap(initSource.range(of: "UIPreviewFixtures.resetPreviewState()"))
    let selectedSceneRange = try XCTUnwrap(initSource.range(of: "_selectedScene = State"))
    XCTAssertLessThan(resetRange.lowerBound, selectedSceneRange.lowerBound)
  }

  func testContentViewPreviewEntryIsDebugOnly() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Views/ContentView.swift"))

    XCTAssertTrue(source.contains("#if DEBUG"))
    XCTAssertTrue(source.contains("UIPreviewMode.isEnabled()"))
    XCTAssertTrue(source.contains("PreviewCatalogView(initialSceneID: UIPreviewMode.sceneID())"))
  }

  func testPreviewEntryDoesNotInstantiateRealRootStateBeforePreviewBranch() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/Views/ContentView.swift"))

    XCTAssertTrue(source.contains("private struct RealAppContentView: View"))

    let contentViewSource = try sourceSlice(
      source,
      from: "struct ContentView: View",
      to: "private struct RealAppContentView: View"
    )
    XCTAssertFalse(contentViewSource.contains("@StateObject private var viewModel = ContentViewModel()"))
    XCTAssertFalse(contentViewSource.contains("@StateObject private var mediaActionHandler = MediaActionHandler()"))

    let realRootSource = try sourceSlice(source, from: "private struct RealAppContentView: View")
    XCTAssertTrue(realRootSource.contains("@StateObject private var viewModel = ContentViewModel()"))
    XCTAssertTrue(realRootSource.contains("@StateObject private var mediaActionHandler = MediaActionHandler()"))
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
      "页面入口",
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
      "启动入口 · 启动会话准备中",
      "启动入口 · 低权限 Tab",
      "启动入口 · 后端版本告警",
      "启动入口 · 账号权限告警",
      "启动入口 · 登录页",
      "启动入口 · 可提交登录",
      "启动入口 · 登录中",
      "启动入口 · 登录失败",
      "首页 · 加载中",
      "首页 · 空数据",
      "首页 · 完整数据",
      "首页 · 最近添加空服务器",
      "首页 · 仅订阅",
      "首页 · 无订阅权限",
      "首页 · 无搜索权限",
      "首页 · 订阅编辑弹窗",
      "首页 · 取消订阅确认",
      "推荐 · 初始化中",
      "推荐 · 加载中",
      "推荐 · 空数据",
      "推荐 · 完整数据",
      "推荐 · 低权限菜单",
      "探索 · 初始化中",
      "探索 · 加载中",
      "探索 · TMDB 筛选",
      "探索 · 豆瓣筛选",
      "探索 · Bangumi 筛选",
      "探索 · 热门订阅",
      "探索 · 订阅分享",
      "探索 · 订阅分享弹窗",
      "探索 · 无订阅权限",
      "探索 · 空结果",
      "详情页 · 电影，未订阅",
      "详情页 · 电影，已订阅",
      "详情页 · 加载中",
      "详情页 · 详情加载失败",
      "详情页 · 电视剧，有分季",
      "详情页 · 有分季且无订阅权限",
      "详情页 · 电视剧，无分季",
      "详情页 · 分季加载失败",
      "详情页 · 无海报 / 无背景图",
      "详情页 · 第二页内容",
      "详情页 · 第二页行加载更多",
      "详情页 · 第二页无操作权限",
      "详情页 · 分季单剧集组",
      "详情页 · 多分季 / 多剧集组",
      "详情页 · TMDB 跳转识别中",
      "详情页 · 站点选择弹窗",
      "详情页 · 订阅弹窗",
      "详情页 · 取消订阅确认",
      "详情页 · 取消订阅中",
      "详情页 · 无订阅权限",
      "详情页 · 无搜索权限",
      "详情页 · 无分季且无订阅权限",
      "详情页 · 无分季且无搜索权限",
      "详情页 · 无搜索且无订阅权限",
      "分季页 · 加载中",
      "分季页 · 普通多季",
      "分季页 · 空数据",
      "分季页 · 加载失败",
      "分季页 · 已订阅 / 缺集混合",
      "分季页 · 无订阅权限",
      "分季页 · 分季详情弹窗",
      "分季页 · 新增订阅弹窗",
      "分季页 · 取消订阅确认",
      "搜索 · 未搜索",
      "搜索 · 聚合加载中",
      "搜索 · 聚合结果",
      "搜索 · 聚合行加载更多",
      "搜索 · 订阅分享弹窗",
      "搜索 · 聚合结果无订阅权限",
      "搜索 · 聚合空结果",
      "搜索 · 站点选择弹窗",
      "搜索 · 资源加载中",
      "搜索 · 资源结果",
      "搜索 · 资源空结果",
      "合集详情 · 加载中",
      "合集详情 · 空数据",
      "合集详情 · 完整数据",
      "合集详情 · 加载更多中",
      "人物详情 · 加载中",
      "人物详情 · 无简介",
      "人物详情 · 简介弹窗",
      "人物详情 · 完整数据",
      "人物详情 · 加载更多中",
      "资源结果页 · 加载中",
      "资源结果页 · 空数据",
      "资源结果页 · 完整数据",
      "资源结果页 · 筛选弹窗",
      "状态页 · 空权限 / 空数据",
      "状态页 · 完整数据",
      "下载任务 · 空数据",
      "下载任务 · 多状态任务",
      "下载任务 · 收起",
      "下载任务 · 删除确认",
      "整理历史 · 加载中",
      "整理历史 · 加载更多中",
      "整理历史 · 空数据",
      "整理历史 · 多选 / AI 整理中",
      "整理历史 · 详情弹窗",
      "整理历史 · 单项删除确认",
      "整理历史 · 批量删除确认",
      "整理历史 · 批量重整弹窗",
      "设置 · 全权限",
      "设置 · 无订阅权限",
      "设置 · 无搜索权限",
      "设置 · 无超级用户权限",
      "设置 · 低权限",
      "设置 · 连接页",
      "设置 · 刷新登录凭据中",
      "设置 · 站点选择页",
      "设置 · 站点空列表",
      "设置 · 硬过滤页",
      "设置 · 硬过滤加载中",
      "设置 · 硬过滤空列表",
      "设置 · 软过滤页",
      "设置 · 软过滤加载中",
      "设置 · 软过滤空列表",
      "设置 · 站点加载中",
      "设置 · 过滤规则加载中",
      "设置 · 过滤规则空列表",
      "设置 · APP 信息",
      "设置 · 退出登录确认",
      "订阅弹窗 · 加载中",
      "订阅弹窗 · 新增",
      "订阅弹窗 · 电影新增",
      "订阅弹窗 · 高级配置",
      "订阅弹窗 · 站点选择",
      "订阅弹窗 · 过滤组选择",
      "订阅弹窗 · 保存中",
      "订阅分享弹窗 · 复用",
      "下载弹窗 · 加载中",
      "下载弹窗 · 添加下载",
      "下载弹窗 · 高级配置",
      "下载弹窗 · 提交中",
      "下载弹窗 · 无搜索权限",
      "下载弹窗 · 失败反馈",
      "整理弹窗 · 加载中",
      "整理弹窗 · 单项重整",
      "整理弹窗 · 批量重整",
      "整理弹窗 · 豆瓣识别源",
      "整理弹窗 · 高级配置",
      "整理弹窗 · 提交中",
      "整理弹窗 · 失败反馈",
      "分季详情弹窗",
      "多选弹窗 · 站点选择",
      "组件 · 媒体卡片",
      "组件 · 媒体卡片完整菜单",
      "组件 · 媒体卡片低权限菜单",
      "组件 · 种子卡片",
      "组件 · 种子卡片无搜索权限",
      "组件 · 种子卡片下载弹窗",
      "组件 · 单选弹窗",
      "组件 · 订阅结果提示",
      "组件 · 选择器 / 输入框",
      "组件 · TMDB 识别中",
      "组件 · TMDB 未识别提示",
      "组件 · 通知",
    ]

    for scene in requiredScenes {
      XCTAssertTrue(source.contains("title: \"\(scene)\""), "Missing preview scene: \(scene)")
    }
  }

  func testLoginPreviewsCoverEmptyReadyLoadingAndFailedStates() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let loginSource = try sourceSlice(source, from: "static func loginViewModel", to: "\n  @discardableResult")

    let requiredSnippets = [
      "case .login:",
      "viewModel.serverURL = \"\"",
      "viewModel.username = \"\"",
      "viewModel.password = \"\"",
      "let filledServerURL = \"http://moviepilot.local:3000\"",
      "case .loginReady:",
      "viewModel.serverURL = filledServerURL",
      "case .loginLoading:",
      "viewModel.isLoading = true",
      "case .loginFailed:",
      "viewModel.errorMessage = \"登录失败: 用户名或密码错误\"",
    ]

    for snippet in requiredSnippets {
      XCTAssertTrue(loginSource.contains(snippet), "Missing login preview fixture state: \(snippet)")
    }

    let emptyCaseRange = try XCTUnwrap(loginSource.range(of: "case .login:"))
    let readyCaseRange = try XCTUnwrap(loginSource.range(of: "case .loginReady:"))
    XCTAssertLessThan(emptyCaseRange.lowerBound, readyCaseRange.lowerBound)
    XCTAssertNil(
      loginSource.range(of: "viewModel.serverURL = filledServerURL", range: emptyCaseRange.upperBound..<readyCaseRange.lowerBound)
    )
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
      "MediaContextMenuItems(",
      "TorrentCard(",
      "CategoryPickerView(",
      "ShelfPicker(",
      "SheetPicker(",
      "SheetTextField(",
      "NotificationView(",
      "MediaActionHandler()",
      ".mediaActionAlerts()",
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
    let rootSource = try sourceSlice(source, from: "struct PreviewCatalogView: View", to: "private struct UIPreviewCatalogHomeView")

    XCTAssertTrue(source.contains("@State private var selectedScene: UIPreviewScene?"))
    XCTAssertTrue(source.contains("ZStack {"))
    XCTAssertTrue(source.contains("if let selectedScene"))
    XCTAssertTrue(source.contains("UIPreviewCatalogHomeView(isActive: selectedScene == nil) { scene in"))
    XCTAssertTrue(source.contains("selectedScene = scene"))
    XCTAssertTrue(source.contains("UIPreviewSceneDestination(scene: selectedScene)"))
    XCTAssertTrue(rootSource.contains(".onExitCommand"))
    XCTAssertTrue(rootSource.contains("selectedScene = nil"))
    XCTAssertFalse(rootSource.contains("UIPreviewBackObserver"))
    XCTAssertFalse(source.contains("import UIKit"))
    XCTAssertFalse(source.contains("UIPress.PressType.menu.rawValue"))
    XCTAssertFalse(source.contains("recognizer.cancelsTouchesInView"))
    XCTAssertFalse(source.contains("shouldRecognizeSimultaneouslyWith otherGestureRecognizer"))
    XCTAssertTrue(source.contains(".navigationTitle(\"UI 预览\")"))
    XCTAssertTrue(rootSource.contains(".opacity(selectedScene == nil ? 1 : 0)"))
    XCTAssertTrue(rootSource.contains(".disabled(selectedScene != nil)"))
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

  func testPreviewCatalogKeepsFocusAndSectionsCollapsedByDefault() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let rootSource = try sourceSlice(source, from: "struct PreviewCatalogView: View", to: "private struct UIPreviewCatalogHomeView")
    let homeSource = try sourceSlice(source, from: "private struct UIPreviewCatalogHomeView", to: "private enum UIPreviewCatalog")

    XCTAssertTrue(rootSource.contains("ZStack {"))
    XCTAssertFalse(rootSource.contains("focusedCatalogItemID"))
    XCTAssertTrue(homeSource.contains("let isActive: Bool"))
    XCTAssertTrue(homeSource.contains("@State private var lastFocusedControlID: String?"))
    XCTAssertTrue(homeSource.contains("@State private var expandedSectionIDs: Set<String> = []"))
    XCTAssertFalse(homeSource.contains("@Binding var focusedItemID"))
    XCTAssertTrue(homeSource.contains("focusedControlID = focusedControlID ?? UIPreviewCatalog.firstSectionID"))
    XCTAssertFalse(homeSource.contains(".defaultFocus("))
    XCTAssertFalse(source.contains("focusedItemID = newValue"))
    XCTAssertTrue(homeSource.contains("lastFocusedControlID = newValue ?? lastFocusedControlID"))
    XCTAssertTrue(homeSource.contains(".onChange(of: isActive)"))
    XCTAssertTrue(homeSource.contains("focusedControlID = lastFocusedControlID ?? focusedControlID ?? UIPreviewCatalog.firstSectionID"))
    XCTAssertTrue(homeSource.contains(".frame(width: 760, alignment: .leading)"))
    XCTAssertTrue(homeSource.contains(".frame(maxWidth: .infinity, alignment: .center)"))
    XCTAssertGreaterThanOrEqual(homeSource.components(separatedBy: ".frame(maxWidth: .infinity, alignment: .leading)").count - 1, 2)
    XCTAssertTrue(homeSource.contains("if expandedSectionIDs.contains(section.id)"))
    XCTAssertTrue(homeSource.contains("expandedSectionIDs.remove(sectionID)"))
    XCTAssertTrue(homeSource.contains("expandedSectionIDs.insert(sectionID)"))
    XCTAssertFalse(homeSource.contains(".buttonStyle("))
    XCTAssertFalse(homeSource.contains("UIPreviewCatalogButtonStyle"))
  }

  func testNotificationPreviewHasLocalFocusAnchorForExitCommand() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let notificationSource = try sourceSlice(
      source,
      from: "private struct UIPreviewNotificationComponents",
      to: "private struct UIPreviewPushedMediaDetailView"
    )

    XCTAssertTrue(notificationSource.contains("@FocusState private var isReturnAnchorFocused: Bool"))
    XCTAssertTrue(notificationSource.contains(".focusable()"))
    XCTAssertTrue(notificationSource.contains(".focused($isReturnAnchorFocused)"))
    XCTAssertTrue(notificationSource.contains("isReturnAnchorFocused = true"))
    XCTAssertTrue(notificationSource.contains(".accessibilityHidden(true)"))
    XCTAssertFalse(notificationSource.contains("UIPreviewBackObserver"))
    XCTAssertFalse(notificationSource.contains("返回目录"))
  }

  func testStartupPreparingPreviewHasLocalFocusAnchorForExitCommand() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let startupSource = try sourceSlice(
      source,
      from: "private struct UIPreviewStartupPreparingView",
      to: "private enum UIPreviewLoggedInRootAlertCase"
    )

    XCTAssertTrue(startupSource.contains("@FocusState private var isReturnAnchorFocused: Bool"))
    XCTAssertTrue(startupSource.contains(".focusable()"))
    XCTAssertTrue(startupSource.contains(".focused($isReturnAnchorFocused)"))
    XCTAssertTrue(startupSource.contains("isReturnAnchorFocused = true"))
    XCTAssertTrue(startupSource.contains(".accessibilityHidden(true)"))
    XCTAssertFalse(startupSource.contains("UIPreviewBackObserver"))
    XCTAssertFalse(startupSource.contains("返回目录"))
  }

  func testAlertOnlyComponentPreviewsHaveLocalFocusAnchorForExitCommand() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let componentSources = [
      try sourceSlice(
        source,
        from: "private struct UIPreviewSubscriptionAlert",
        to: "\n@MainActor\nprivate struct UIPreviewMediaActionComponents"
      ),
      try sourceSlice(
        source,
        from: "private struct UIPreviewMediaActionComponents",
        to: "private struct UIPreviewNotificationComponents"
      ),
    ]

    for componentSource in componentSources {
      XCTAssertTrue(componentSource.contains("@FocusState private var isReturnAnchorFocused: Bool"))
      XCTAssertTrue(componentSource.contains(".focusable()"))
      XCTAssertTrue(componentSource.contains(".focused($isReturnAnchorFocused)"))
      XCTAssertTrue(componentSource.contains("isReturnAnchorFocused = true"))
      XCTAssertTrue(componentSource.contains(".accessibilityHidden(true)"))
      XCTAssertFalse(componentSource.contains("UIPreviewBackObserver"))
      XCTAssertFalse(componentSource.contains("返回目录"))
    }
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
      "selectedTab: .home",
      "homeMode: previewCase.homeMode",
      "homePreviewDestinations: HomeViewUIPreviewDestinations(homePresentation: previewCase.homePresentation)",
      "selectedTab: .recommend",
      "recommendMode: previewCase.recommendMode",
      "exploreMode: previewCase.exploreMode",
      "permissions: previewCase.permissions",
      "selectedTab: .search",
      "searchCase: searchCase",
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
    XCTAssertTrue(searchSource.contains("PersonDetailView("))
    XCTAssertTrue(searchSource.contains("previewViewModel: previewViewModel"))
    XCTAssertTrue(searchSource.contains("ResourceResultView("))
    XCTAssertTrue(searchSource.contains("SubscribeSeasonView("))
    XCTAssertTrue(searchSource.contains("uiPreviewPresentation: uiPreviewDestinations?.seasonPresentation"))
    XCTAssertFalse(source.contains("NavigationStack {\n      SubscribeSeasonView(previewViewModel: viewModel)"))
    XCTAssertFalse(source.contains("ResourceResultView(\n      title: mode"))
  }

  func testSettingsPreviewCoversPermissionLoadingAndEmptyCombinations() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let systemSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SystemView.swift"))

    let requiredSettingsIDs = [
      "settings-noSuperUser",
      "settings-siteEmpty",
      "settings-hardFilterLoading",
      "settings-hardFilterEmpty",
      "settings-softFilterLoading",
      "settings-softFilterEmpty",
      "settings-rulesLoading",
      "settings-rulesEmpty",
    ]

    for id in requiredSettingsIDs {
      XCTAssertTrue(catalogSource.contains("id: \"\(id)\""), "Missing settings preview id: \(id)")
    }

    XCTAssertTrue(catalogSource.contains("case .noSuperUser:"))
    XCTAssertTrue(catalogSource.contains("case .siteEmpty:"))
    XCTAssertTrue(catalogSource.contains(".hardFilterLoading"))
    XCTAssertTrue(catalogSource.contains(".hardFilterEmpty"))
    XCTAssertTrue(catalogSource.contains(".softFilterLoading"))
    XCTAssertTrue(catalogSource.contains(".softFilterEmpty"))
    XCTAssertTrue(catalogSource.contains("var hasEmptySites: Bool"))
    XCTAssertTrue(catalogSource.contains("var hasEmptyFilterRules: Bool"))
    XCTAssertTrue(catalogSource.contains("var isLoadingFilterRules: Bool"))
    XCTAssertTrue(systemSource.contains("if viewModel.isLoadingRules {"))
    XCTAssertTrue(systemSource.contains("row(\"规则状态\", value: \"正在加载\")"))
    XCTAssertTrue(systemSource.contains("row(\"规则状态\", value: \"暂无自定义过滤规则\")"))
  }

  func testDownloadTaskPreviewCoversEveryTaskStateBadge() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredStates = [
      "downloading",
      "paused",
      "error",
      "checking",
      "stalledDL",
      "uploading",
      "missingFiles",
      "queuedDL",
    ]

    for state in requiredStates {
      XCTAssertTrue(source.contains("state: \"\(state)\""), "Missing download preview state: \(state)")
    }
  }

  func testTransferHistoryPreviewCoversLoadingMoreBranch() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredSnippets = [
      "case transferLoadingMore",
      "id: \"status-transferLoadingMore\"",
      "title: \"整理历史 · 加载更多中\"",
      "case .transferLoadingMore: return .loadingMore",
      "case .loadingMore:",
      "isLoadingMore: true",
    ]

    for snippet in requiredSnippets {
      XCTAssertTrue(source.contains(snippet), "Missing transfer-history loading-more preview coverage: \(snippet)")
    }
  }

  func testTransferHistoryBatchReorganizePreviewDoesNotStayLoading() throws {
    let transferSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/TransferHistoryView.swift"))
    let reorganizeViewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/ReorganizeViewModel.swift"))

    XCTAssertTrue(transferSource.contains("case .batchReorganize:"))
    XCTAssertTrue(transferSource.contains("showBatchRedoSheet = true"))
    XCTAssertTrue(transferSource.contains("ReorganizeSheet(logIds: Array(viewModel.selectedIds), fileItem: nil)"))
    XCTAssertTrue(reorganizeViewModelSource.contains("if UIPreviewMode.isEnabled() {"))
    XCTAssertTrue(reorganizeViewModelSource.contains("isLoading = false"))
  }

  func testDeepMediaGridPreviewsCoverLoadingMoreBranches() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredSnippets = [
      "case collectionLoadingMore",
      "id: \"page-collectionLoadingMore\"",
      "title: \"合集详情 · 加载更多中\"",
      "case .collectionLoadingMore: return .loadingMore",
      "case .loadingMore:",
      "return CollectionDetailViewModel(previewPaginator: .uiPreview(items: previewMediaGrid, isLoadingMore: true))",
      "case personLoadingMore",
      "id: \"page-personLoadingMore\"",
      "title: \"人物详情 · 加载更多中\"",
      "case .personLoadingMore: return .loadingMore",
      "previewPaginator: .uiPreview(items: previewMediaGrid, isLoadingMore: true)",
    ]

    for snippet in requiredSnippets {
      XCTAssertTrue(source.contains(snippet), "Missing deep media-grid loading-more preview coverage: \(snippet)")
    }
  }

  func testExplorePreviewCoversForkSubscribeSheetBranch() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let exploreSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/ExploreView.swift"))

    let requiredCatalogSnippets = [
      "case exploreShareSheet",
      "id: \"page-exploreShareSheet\"",
      "title: \"探索 · 订阅分享弹窗\"",
      "case .exploreShareSheet: return \"探索 · 订阅分享弹窗\"",
      "case .exploreShareSheet: return \"探索页订阅分享卡片点击后，通过真实 ExploreView sheet 展示 ForkSubscribeSheet。\"",
      "explorePreviewForkShare: previewCase.explorePreviewForkShare",
      "case .exploreShareSheet: return .share",
      "case .exploreShareSheet:",
      "return UIPreviewFixtures.previewSubscribeShare",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing explore fork-sheet preview coverage: \(snippet)")
    }

    XCTAssertTrue(exploreSource.contains("uiPreviewForkShare: SubscribeShare? = nil"))
    XCTAssertTrue(exploreSource.contains("private let uiPreviewForkShare: SubscribeShare?"))
    XCTAssertTrue(exploreSource.contains("guard let uiPreviewForkShare else { return }"))
    XCTAssertTrue(exploreSource.contains("subscriptionHandler.forkSheetRequest = uiPreviewForkShare"))
  }

  func testUnifiedSearchPreviewCoversRowLoadingMoreBranches() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let searchViewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/SearchViewModel.swift"))
    let searchViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SearchView.swift"))

    let requiredCatalogSnippets = [
      "case unifiedLoadingMore",
      "id: \"search-unifiedLoadingMore\"",
      "title: \"搜索 · 聚合行加载更多\"",
      "case .unifiedLoadingMore: return \"搜索 · 聚合行加载更多\"",
      "case .unifiedLoadingMore: return \"聚合搜索已有结果时，各横向结果行底部显示加载更多进度。\"",
      "isLoadingMore: true",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing unified-search loading-more preview coverage: \(snippet)")
    }

    XCTAssertTrue(searchViewModelSource.contains("isLoadingMore: Bool = false"))
    XCTAssertTrue(searchViewModelSource.contains("moviePaginator = .uiPreview(items: movies, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(searchViewModelSource.contains("tvPaginator = .uiPreview(items: tvShows, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(searchViewModelSource.contains("collectionPaginator = .uiPreview(items: collections, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(searchViewModelSource.contains("personPaginator = .uiPreview(items: persons, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(searchViewModelSource.contains("subscriptionSharePaginator = .uiPreview(items: shares, isLoadingMore: isLoadingMore)"))

    XCTAssertTrue(searchViewSource.contains("isLoadingMore: paginator?.isLoadingMore ?? false"))
    XCTAssertTrue(searchViewSource.contains("isLoadingMore: viewModel.personPaginator?.isLoadingMore ?? false"))
  }

  func testUnifiedSearchPreviewCoversForkSubscribeSheetBranch() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let searchViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SearchView.swift"))

    let requiredCatalogSnippets = [
      "case unifiedShareSheet",
      "id: \"search-unifiedShareSheet\"",
      "title: \"搜索 · 订阅分享弹窗\"",
      "case .unifiedShareSheet: return \"搜索 · 订阅分享弹窗\"",
      "case .unifiedShareSheet: return \"聚合搜索订阅分享点击后，通过真实 SearchView sheet 展示 ForkSubscribeSheet。\"",
      "searchPreviewDestinations: SearchViewUIPreviewDestinations(forkShare: searchCase.searchPreviewForkShare)",
      "case .unifiedShareSheet:",
      "return UIPreviewFixtures.previewSubscribeShare",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing unified-search fork-sheet preview coverage: \(snippet)")
    }

    XCTAssertTrue(searchViewSource.contains("var forkShare: SubscribeShare? = nil"))
    XCTAssertTrue(searchViewSource.contains("guard let forkShare = uiPreviewDestinations?.forkShare else { return }"))
    XCTAssertTrue(searchViewSource.contains("subscriptionHandler.forkSheetRequest = forkShare"))
  }

  func testSheetPreviewsCoverMovieSubscriptionAndDoubanRecognitionBranches() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let subscribeSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Sheets/SubscribeSheet.swift"))
    let reorganizeSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift"))

    let requiredCatalogSnippets = [
      "case subscribeMovie",
      "id: \"sheet-subscribeMovie\"",
      "title: \"订阅弹窗 · 电影新增\"",
      "UIPreviewFixtures.subscribeSheetViewModel(type: \"电影\")",
      "case reorganizeDouban",
      "id: \"sheet-reorganizeDouban\"",
      "title: \"整理弹窗 · 豆瓣识别源\"",
      "case .reorganizeDouban:",
      "return .doubanRecognition",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(source.contains(snippet), "Missing sheet branch preview coverage: \(snippet)")
    }

    XCTAssertTrue(subscribeSource.contains("if viewModel.subscribe.type == \"电视剧\""))
    XCTAssertTrue(reorganizeSource.contains("recognizeSource == \"themoviedb\""))
    XCTAssertTrue(reorganizeSource.contains("title: \"豆瓣 ID\""))
  }

  func testMediaCardPreviewCoversSubscribedAndExternalSourceContextMenuBranches() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let contextMenuSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Components/MediaContextMenu.swift"))

    let requiredCatalogSnippets = [
      "case mediaCardsContextMenu",
      "id: \"component-mediaCardsContextMenu\"",
      "title: \"组件 · 媒体卡片完整菜单\"",
      "case .mediaCardsContextMenu: return \"组件 · 媒体卡片完整菜单\"",
      "case .mediaCardsContextMenu: return \"全权限媒体卡片菜单，覆盖 TMDB 跳转、已订阅、分季订阅、搜索资源和订阅分享复用入口。\"",
      "showsContextMenu: componentCase != .mediaCards",
      "externalSourceMedia(id: 98_005",
      "title: \"外部来源：边境信号\"",
      "installSubscribedContextMenuPreviewTask(for: items)",
      "let subscribedItem = items[0]",
      "task.isSubscribed = true",
      "MediaPreloader.shared.installPreviewTask(task, for: subscribedItem)",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing media-card context-menu preview fixture: \(snippet)")
    }

    XCTAssertTrue(contextMenuSource.contains("if item.collection_id == nil"))
    XCTAssertTrue(contextMenuSource.contains("if item.douban_id != nil || item.bangumi_id != nil"))
    XCTAssertTrue(contextMenuSource.contains("Label(\"TMDB详情页\", systemImage: \"link\")"))
    XCTAssertTrue(contextMenuSource.contains("Label(\"已订阅\", systemImage: \"checkmark.circle.fill\")"))
  }

  func testPreviewCatalogCoversPermissionSensitiveCardMenus() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))

    let requiredSnippets = [
      "case homeNoSearchPermission",
      "id: \"page-homeNoSearchPermission\"",
      "title: \"首页 · 无搜索权限\"",
      "case recommendLimitedPermissions",
      "id: \"page-recommendLimitedPermissions\"",
      "title: \"推荐 · 低权限菜单\"",
      "case tvWithSeasonsNoSubscribePermission",
      "id: \"detail-tvWithSeasonsNoSubscribePermission\"",
      "title: \"详情页 · 有分季且无订阅权限\"",
      ".tvWithSeasonsNoSubscribePermission, .noArtwork",
      "case mediaCardsLimitedPermissions",
      "id: \"component-mediaCardsLimitedPermissions\"",
      "title: \"组件 · 媒体卡片低权限菜单\"",
      "case limitedPermissions",
      "id: \"settings-limitedPermissions\"",
      "title: \"设置 · 低权限\"",
      "case torrentCardsNoSearchPermission",
      "id: \"component-torrentCardsNoSearchPermission\"",
      "title: \"组件 · 种子卡片无搜索权限\"",
      "componentCase.permissions",
      "MediaContextMenuItems(",
    ]

    for snippet in requiredSnippets {
      XCTAssertTrue(source.contains(snippet), "Missing permission-sensitive preview coverage: \(snippet)")
    }
  }

  func testDetailPreviewsCoverContentRowsPermissionsAndSeasonShelfBranches() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let detailViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/MediaDetailView.swift"))
    let detailViewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaDetailViewModel.swift"))
    let paginatorSource = try String(contentsOf: repoFile("MoviePilot-TV/Services/Paginator.swift"))
    let seasonViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift"))

    let requiredSceneSnippets = [
      "case contentPageNoSearchAndNoSubscribePermission",
      "id: \"detail-contentPageNoSearchAndNoSubscribePermission\"",
      "title: \"详情页 · 第二页无操作权限\"",
      "case contentPageSingleEpisodeGroup",
      "id: \"detail-contentPageSingleEpisodeGroup\"",
      "title: \"详情页 · 分季单剧集组\"",
      "case contentPageManySeasons",
      "id: \"detail-contentPageManySeasons\"",
      "title: \"详情页 · 多分季 / 多剧集组\"",
    ]

    for snippet in requiredSceneSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing detail preview branch: \(snippet)")
    }

    XCTAssertTrue(detailViewSource.contains("struct MediaDetailUIPreviewRows"))
    XCTAssertTrue(detailViewSource.contains("uiPreviewRows: MediaDetailUIPreviewRows?"))
    XCTAssertTrue(detailViewSource.contains("scrollToUIPreviewContentPage"))
    XCTAssertTrue(detailViewSource.contains("proxy.scrollTo(\"contentTop\", anchor: .top)"))
    XCTAssertTrue(detailViewModelSource.contains("func installUIPreviewRows("))
    XCTAssertTrue(paginatorSource.contains("func installUIPreviewItems("))

    XCTAssertTrue(catalogSource.contains("previewDetailRows"))
    XCTAssertTrue(catalogSource.contains("previewManySeasons"))
    XCTAssertTrue(catalogSource.contains("seasons: previewManySeasons"))
    XCTAssertTrue(catalogSource.contains("episodeGroups: []"))
    XCTAssertTrue(catalogSource.contains("episodeGroups: previewEpisodeGroups"))
    XCTAssertTrue(catalogSource.contains("viewModel.seasonInfos = seasonInfos"))
    XCTAssertTrue(catalogSource.contains("viewModel.episodeGroups = groups"))

    XCTAssertTrue(seasonViewSource.contains("if viewModel.seasonInfos.count > 10"))
    XCTAssertTrue(seasonViewSource.contains("titleText: \"查看全部\""))
  }

  func testDetailContentPagePreviewCoversRowsLoadingMoreBranch() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let detailViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/MediaDetailView.swift"))
    let detailViewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaDetailViewModel.swift"))

    let requiredSnippets = [
      "case contentPageRowsLoadingMore",
      "id: \"detail-contentPageRowsLoadingMore\"",
      "title: \"详情页 · 第二页行加载更多\"",
      "case .contentPageRowsLoadingMore: return \"详情页 · 第二页行加载更多\"",
      "case .contentPageRowsLoadingMore:",
      "return \"详情页第二页演员、推荐、类似行显示加载更多进度。\"",
      "previewDetailRowsLoadingMore",
      "isLoadingMore: true",
    ]

    for snippet in requiredSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing detail row loading-more preview coverage: \(snippet)")
    }

    XCTAssertTrue(detailViewSource.contains("if viewModel.actorsPaginator.isLoadingMore"))
    XCTAssertTrue(detailViewSource.contains("if viewModel.recommendPaginator.isLoadingMore"))
    XCTAssertTrue(detailViewSource.contains("if viewModel.similarPaginator.isLoadingMore"))
    XCTAssertTrue(detailViewModelSource.contains("isLoadingMore: Bool = false"))
    XCTAssertTrue(detailViewModelSource.contains("actorsPaginator.installUIPreviewItems(actors, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(detailViewModelSource.contains("recommendPaginator.installUIPreviewItems(recommendations, isLoadingMore: isLoadingMore)"))
    XCTAssertTrue(detailViewModelSource.contains("similarPaginator.installUIPreviewItems(similar, isLoadingMore: isLoadingMore)"))
  }

  func testLastPermissionDetailPreviewsInstallSecondPageRows() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let detailRowsSource = try sourceSlice(
      catalogSource,
      from: "static func detailRows(for detailCase: UIPreviewDetailCase)",
      to: "\n  private static func detailMedia"
    )

    XCTAssertTrue(detailRowsSource.contains(".tvWithoutSeasonsNoSearchPermission"))
    XCTAssertTrue(detailRowsSource.contains(".noSearchAndNoSubscribePermission"))
  }

  func testDetailPreviewCoversUnsubscribingButtonLoadingState() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let detailViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/MediaDetailView.swift"))
    let detailViewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaDetailViewModel.swift"))

    let requiredCatalogSnippets = [
      "case unsubscribing",
      "id: \"detail-unsubscribing\"",
      "title: \"详情页 · 取消订阅中\"",
      "case .unsubscribing: return \"详情页 · 取消订阅中\"",
      "case .unsubscribing: return \"已订阅电影 Header 中，订阅按钮显示取消订阅进行中的 ProgressView。\"",
      "self == .movieSubscribed || self == .unsubscribeConfirmation || self == .unsubscribing",
      "case .unsubscribing:",
      "return .unsubscribing",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing detail unsubscribing preview coverage: \(snippet)")
    }

    XCTAssertTrue(detailViewSource.contains("case unsubscribing"))
    XCTAssertTrue(detailViewSource.contains("vm.isUnsubscribing = uiPreviewPresentation == .unsubscribing"))
    XCTAssertTrue(
      detailViewSource.contains("if detail.canDirectlySubscribe && viewModel.isUnsubscribing")
    )
    XCTAssertTrue(
      detailViewSource.contains(".disabled(detail.canDirectlySubscribe && viewModel.isUnsubscribing)")
    )
    XCTAssertTrue(detailViewModelSource.contains("@Published var isUnsubscribing = false"))
  }

  func testDetailPreviewCoversFullDetailLoadFailureBranch() throws {
    let catalogSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let containerSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift"))

    let requiredCatalogSnippets = [
      "case detailLoadFailed",
      "id: \"detail-detailLoadFailed\"",
      "title: \"详情页 · 详情加载失败\"",
      "case .detailLoadFailed: return \"详情页 · 详情加载失败\"",
      "case .detailLoadFailed: return \"完整详情接口失败时，容器退掉 Loading 并显示 partial detail fallback。\"",
      "task.isDetailFailed = true",
    ]

    for snippet in requiredCatalogSnippets {
      XCTAssertTrue(catalogSource.contains(snippet), "Missing detail load-failed preview coverage: \(snippet)")
    }

    XCTAssertTrue(containerSource.contains("|| preloadTask.isDetailFailed"))
  }

  func testPreviewRootDoesNotAddPreviewNavigationChrome() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let functionRange = try XCTUnwrap(source.range(of: "func previewRoot(_ title: String) -> some View"))
    let functionSource = String(source[functionRange.lowerBound...])
      .prefix(200)

    XCTAssertFalse(functionSource.contains("NavigationStack"))
    XCTAssertFalse(functionSource.contains(".navigationTitle(title)"))
  }

  func testSheetPreviewsUseNativeSheetPresentation() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let sheetSource = try sourceSlice(
      source,
      from: "private struct UIPreviewSheetSceneView: View",
      to: "\n@MainActor\nprivate struct UIPreviewMultiSelectionSheet"
    )

    XCTAssertTrue(sheetSource.contains("@State private var isSheetPresented = false"))
    XCTAssertTrue(sheetSource.contains(".sheet(isPresented: $isSheetPresented)"))
    XCTAssertTrue(sheetSource.contains("isSheetPresented = true"))
    XCTAssertTrue(sheetSource.contains("private var sheetContent: some View"))
    XCTAssertTrue(sheetSource.contains("Button(\"打开弹窗\")"))
  }

  func testReorganizeFailurePreviewUsesSheetLocalFeedback() throws {
    let previewSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let sheetSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift"))

    XCTAssertTrue(previewSource.contains("整理弹窗 · 失败反馈"))
    XCTAssertTrue(sheetSource.contains("viewModel.errorMessage = previewErrorMessage"))
    XCTAssertFalse(sheetSource.contains("presentError("))
  }

  func testAddDownloadFailurePreviewUsesSheetLocalFeedback() throws {
    let previewSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let sheetSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift"))

    XCTAssertTrue(previewSource.contains("下载弹窗 · 失败反馈"))
    XCTAssertTrue(sheetSource.contains("viewModel.errorMessage = previewErrorMessage"))
    XCTAssertFalse(sheetSource.contains("presentError("))
  }

  func testDetailPreviewStartsAsNativeNavigationDestination() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let homeSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/HomeView.swift"))

    XCTAssertTrue(source.contains("homeInitialPath: initialPath"))
    XCTAssertTrue(source.contains("path.append(media)"))
    XCTAssertTrue(source.contains("uiPreviewDestinations: homePreviewDestinations"))
    XCTAssertTrue(homeSource.contains("MediaDetailContainerView(media: mediaInfo, navigationPath: $path)"))
    XCTAssertTrue(homeSource.contains("uiPreviewPresentation: presentation"))
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
        "tmdbIdToUse = deterministicUIPreviewTMDBId(for: item.id)",
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
    let homeGuardRange = try XCTUnwrap(persistSource.range(of: "if UIPreviewMode.isEnabled() { return }"))
    let homeWriteRange = try XCTUnwrap(persistSource.range(of: "UserDefaults.standard.set"))
    XCTAssertLessThan(homeGuardRange.lowerBound, homeWriteRange.lowerBound)
  }

  func testSystemPreviewActionsAndPreferencesAreSandboxed() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/SystemViewModel.swift"))

    try assertPreviewGuard(
      in: source,
      function: "func relogin() async",
      before: "APIService.shared.login"
    )
    try assertPreviewGuard(
      in: source,
      function: "func logout()",
      before: "APIService.shared.logout"
    )

    try assertPreviewGuard(
      in: source,
      function: "@Published var waitMediaDetailBackgroundImage",
      before: "UserDefaults.standard.set(waitMediaDetailBackgroundImage"
    )
    try assertPreviewGuard(
      in: source,
      function: "@Published var autoSearchNewSubscriptions",
      before: "UserDefaults.standard.set(autoSearchNewSubscriptions"
    )

    XCTAssertTrue(source.contains("private var uiPreviewDefaultSearchSites: Set<Int> = []"))
    XCTAssertTrue(source.contains("private var uiPreviewHardFilterRuleId: String?"))
    XCTAssertTrue(source.contains("private var uiPreviewSoftFilterRuleId: String?"))
    XCTAssertTrue(source.contains("if Self.isUIPreviewMode { return uiPreviewDefaultSearchSites }"))
    XCTAssertTrue(source.contains("if Self.isUIPreviewMode { return uiPreviewHardFilterRuleId }"))
    XCTAssertTrue(source.contains("if Self.isUIPreviewMode { return uiPreviewSoftFilterRuleId }"))

    let systemViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SystemView.swift"))
    let previewInitSource = try sourceSlice(
      systemViewSource,
      from: "init(uiPreviewPresentation: SystemViewUIPreviewPresentation",
      to: "#endif"
    )
    XCTAssertTrue(previewInitSource.contains("let route = uiPreviewPresentation.initialRoute"))
    XCTAssertTrue(previewInitSource.contains("_route = State(initialValue: route)"))
    XCTAssertTrue(systemViewSource.contains("case .connection, .logoutConfirmation:"))
    XCTAssertTrue(systemViewSource.contains("return [.connection]"))
  }

  func testDetailPreviewDoesNotRefreshBackendOrDeleteSubscription() throws {
    let source = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaDetailViewModel.swift"))

    try assertPreviewGuard(
      in: source,
      function: "func applyFullDetail(_ fullDetail: MediaInfo)",
      before: "Task {"
    )
    try assertPreviewGuard(
      in: source,
      function: "func refreshSubscriptionStatus(forceRefresh: Bool = true) async -> Bool",
      before: "withTaskGroup"
    )
    try assertPreviewGuard(
      in: source,
      function: "func cancelSubscription() async",
      before: "deleteResolvedSubscription()"
    )
    try assertPreviewGuard(
      in: source,
      function: "private func deleteResolvedSubscription() async -> Bool",
      before: "fetchSubscriptionLookup"
    )
  }

  func testSearchPreviewDoesNotEscapeToProductionResourceSearch() throws {
    let viewModelSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/SearchViewModel.swift"))
    try assertPreviewGuard(
      in: viewModelSource,
      function: "func autoSearch() async",
      before: "searchGeneration += 1"
    )

    let searchViewSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/SearchView.swift"))
    let resourceDestinationSource = try sourceSlice(
      searchViewSource,
      from: "private func resourceDestination(for request: ResourceSearchRequest) -> some View",
      to: "private func seasonDestination"
    )
    XCTAssertTrue(resourceDestinationSource.contains("} else if UIPreviewMode.isEnabled() {"))

    let previewSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let previewDestinationsSource = try sourceSlice(
      previewSource,
      from: "func uiPreviewNavigationDestinations(path: Binding<NavigationPath>) -> some View",
      to: "func previewNavigationPath() -> NavigationPath"
    )
    XCTAssertFalse(previewDestinationsSource.contains("ResourceResultView(request: request)"))

    let resourceResultSource = try String(contentsOf: repoFile("MoviePilot-TV/Views/Pages/ResourceResultView.swift"))
    let onDisappearSource = try sourceSlice(resourceResultSource, from: ".onDisappear {")
    let guardRange = try XCTUnwrap(onDisappearSource.range(of: "guard searchesOnAppear else { return }"))
    let cancelRange = try XCTUnwrap(onDisappearSource.range(of: "viewModel.cancelInFlightSearch()"))
    XCTAssertLessThan(guardRange.lowerBound, cancelRange.lowerBound)
  }

  func testComponentPreviewsInstallPermissionsBeforeBodyAndPreviewStateIsStable() throws {
    let previewSource = try String(contentsOf: repoFile("MoviePilot-TV/PreviewSupport/PreviewCatalogView.swift"))
    let componentSource = try sourceSlice(
      previewSource,
      from: "private struct UIPreviewComponentSceneView: View",
      to: "private struct UIPreviewMediaCards: View"
    )
    let initRange = try XCTUnwrap(componentSource.range(of: "init(componentCase: UIPreviewComponentCase"))
    let applyRange = try XCTUnwrap(componentSource.range(of: "UIPreviewFixtures.applyPermissions("))
    let bodyRange = try XCTUnwrap(componentSource.range(of: "var body: some View"))
    XCTAssertLessThan(initRange.lowerBound, bodyRange.lowerBound)
    XCTAssertLessThan(applyRange.lowerBound, bodyRange.lowerBound)
    XCTAssertFalse(componentSource.contains(".onAppear { UIPreviewFixtures.applyPermissions("))

    let preloaderSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaPreloader.swift"))
    let previewTaskSource = try sourceSlice(preloaderSource, from: "private func uiPreviewTask(for media: MediaInfo)")
    XCTAssertTrue(previewTaskSource.contains("task.isSeasonDataLoaded = media.type == \"电视剧\""))

    let actionSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/MediaActionHandler.swift"))
    XCTAssertFalse(actionSource.contains(".hashValue"))
    XCTAssertTrue(actionSource.contains("deterministicUIPreviewTMDBId(for: item.id)"))

    let transferSource = try String(contentsOf: repoFile("MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift"))
    let installSource = try sourceSlice(transferSource, from: "func installUIPreviewData(")
    XCTAssertTrue(installSource.contains("paginatorItems = items"))
    XCTAssertTrue(installSource.contains("prependedItems.removeAll()"))
    XCTAssertTrue(installSource.contains("deletedIds.removeAll()"))
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
    XCTAssertNil(
      sheetSource.range(
        of: #"\\.onAppear\\s*\\{[^}]*UIPreviewFixtures\\.applyPermissions"#,
        options: .regularExpression
      )
    )
  }

  private func assertPreviewGuard(
    in source: String,
    function: String,
    before guardedMarker: String
  ) throws {
    let functionSource = try sourceSlice(source, from: function)
    let guardRange = try XCTUnwrap(
      functionSource.range(of: "UIPreviewMode.isEnabled()")
        ?? functionSource.range(of: "Self.isUIPreviewMode")
    )
    let markerRange = try XCTUnwrap(functionSource.range(of: guardedMarker))
    XCTAssertLessThan(guardRange.lowerBound, markerRange.lowerBound)
  }

  private func sourceSlice(
    _ source: String,
    from startMarker: String,
    to endMarker: String? = nil
  ) throws -> Substring {
    let start = try XCTUnwrap(source.range(of: startMarker))
    if let endMarker {
      let end = try XCTUnwrap(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
      return source[start.lowerBound..<end.lowerBound]
    }
    return source[start.lowerBound...]
  }

  private func repoFile(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(path)
  }
}
