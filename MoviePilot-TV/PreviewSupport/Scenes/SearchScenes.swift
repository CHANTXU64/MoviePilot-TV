#if DEBUG
import SwiftUI

/// 「搜索 + 资源搜索结果」域的预览场景。
///
/// 入口场景渲染真实 `SearchView`/`MainContentView`；聚合结果直接复用真实
/// `UnifiedSearchResult` 与 `SearchViewModel`，资源页复用真实 `ResourceResultView`，
/// 只把 APIService 的数据方法替换成 fixture。
@MainActor
enum UIPreviewScenesSearch {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "search",
      title: "搜索与资源结果",
      scenes: entryScenes + aggregateScenes + siteScenes + resourceScenes + sheetScenes
        + permissionScenes
    )
  }

  // MARK: - 搜索入口

  private static var entryScenes: [UIPreviewScene] {
    [
      searchPage(
        id: "search.entry",
        title: "搜索入口 · 未搜索",
        note:
          "真实搜索 Tab。未提交时只显示原生搜索栏、搜索类型与站点筛选；当前 main 没有搜索历史模块，所以没有历史列表可预览。"
      ),
      searchPage(
        id: "search.keyword",
        title: "搜索入口 · 关键词输入态",
        note:
          "打开后点按顶部搜索栏即可输入关键词。tvOS 不允许代码强制唤起系统键盘，此场景本身不预填文本。"
      ),
    ]
  }

  // MARK: - 聚合搜索结果

  private static var aggregateScenes: [UIPreviewScene] {
    [
      unifiedScene(
        id: "search.unified",
        title: "聚合搜索 · 全部结果",
        note: "自动以「边境信号」搜索。最佳结果与媒体、合集、人物、订阅分享行同时出现。"
      ),
      unifiedScene(
        id: "search.unified.media",
        title: "聚合搜索 · 仅媒体结果",
        note: "合集、人物、订阅分享置空，只验证电影/电视剧行与最佳结果。",
        behaviors: [
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
        ]
      ),
      unifiedScene(
        id: "search.unified.collections",
        title: "聚合搜索 · 仅合集结果",
        note: "媒体、人物、订阅分享置空，只保留系列行。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
        ]
      ),
      unifiedScene(
        id: "search.unified.persons",
        title: "聚合搜索 · 仅人物结果",
        note: "媒体、合集、订阅分享置空，只保留演职人员行。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .empty,
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
        ]
      ),
      unifiedScene(
        id: "search.unified.shares",
        title: "聚合搜索 · 仅订阅分享",
        note: "媒体、合集、人物置空，只保留订阅分享行；分享卡片可继续打开复用订阅面板。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .empty,
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
        ]
      ),
      unifiedScene(
        id: "search.unified.empty",
        title: "聚合搜索 · 无结果",
        note: "四类请求都返回空列表，页面显示「未找到相关结果」。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .empty,
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
        ]
      ),
      unifiedScene(
        id: "search.unified.failure",
        title: "聚合搜索 · 请求失败",
        note: "四类请求全部抛错。聚合页没有单独错误文案，失败会直接落成「未找到相关结果」空态。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .failure,
          UIPreviewBehaviorKey.searchCollection: .failure,
          UIPreviewBehaviorKey.searchPerson: .failure,
          UIPreviewBehaviorKey.searchSubscriptionShares: .failure,
        ]
      ),
      unifiedScene(
        id: "search.unified.loading",
        title: "聚合搜索 · 首次加载",
        note: "四类请求都挂起，保持聚合搜索的加载指示器。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .hang,
          UIPreviewBehaviorKey.searchCollection: .hang,
          UIPreviewBehaviorKey.searchPerson: .hang,
          UIPreviewBehaviorKey.searchSubscriptionShares: .hang,
        ]
      ),
      unifiedScene(
        id: "search.unified.loadMore",
        title: "聚合搜索 · 加载更多",
        note: "首屏有数据，第 3 页挂起。把焦点移到电影/电视剧行最后一张卡片，触发分页并在行尾显示加载指示器。",
        behaviors: [
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
          UIPreviewBehaviorKey.searchMediaMore: .hang,
        ]
      ),
      unifiedScene(
        id: "search.unified.noSubscribe",
        title: "聚合搜索 · 无订阅权限",
        note: "没有 subscribe 权限：订阅分享行不出现，媒体/人物卡片也不提供订阅入口。",
        permissions: [.discovery, .search]
      ),
    ]
  }

  // MARK: - 站点筛选菜单

  private static var siteScenes: [UIPreviewScene] {
    [
      siteScene(
        id: "search.sites.all",
        title: "站点菜单 · 全部站点",
        note: "按钮显示「全部站点」。聚焦按钮按确认打开真实站点菜单，默认/全部/指定站点三组都在。",
        selection: []
      ),
      siteScene(
        id: "search.sites.partial",
        title: "站点菜单 · 选中部分站点",
        note: "按钮显示「2 个站点」，菜单中 AlphaPT / BetaHD 处于选中态。",
        selection: [1, 3]
      ),
      siteScene(
        id: "search.sites.default",
        title: "站点菜单 · 默认",
        note: "按钮显示「默认」，表示跟随系统设置里的默认搜索站点，而不是显式全选。",
        selection: nil
      ),
      siteScene(
        id: "search.sites.empty",
        title: "站点菜单 · 站点为空",
        note: "权威域与订阅域都没有站点；按钮显示「全部站点」，打开菜单只能看到「暂无可选站点」。",
        selection: [],
        behaviors: [
          UIPreviewBehaviorKey.settingsSites: .empty,
          UIPreviewBehaviorKey.searchAllSites: .empty,
          UIPreviewBehaviorKey.searchSites: .empty,
        ]
      ),
      siteScene(
        id: "search.sites.noManage",
        title: "站点菜单 · 无管理权限",
        note:
          "没有 manage 权限。生产逻辑会降级到订阅域 /site/rss；预览钩子对 fetchSearchableSites 统一返回完整站点数据，因此列表内容与有权限时相同。",
        selection: [1, 3],
        permissions: [.discovery, .search]
      ),
    ]
  }

  // MARK: - 资源结果页

  private static var resourceScenes: [UIPreviewScene] {
    [
      resourceScene(
        id: "resource.loading",
        title: "资源结果 · 首次加载",
        note: "从媒体卡片「搜索资源」进入（媒体 ID 搜索）。SSE 挂起，停留在搜索中并可取消。",
        request: mediaResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .hang]
      ),
      resourceScene(
        id: "resource.results",
        title: "资源结果 · 多站结果",
        note: "标题搜索返回 4 条资源，来自 AlphaPT / BetaHD / GammaPT 三个站点，可继续搜索。",
        request: titleResourceRequest
      ),
      resourceScene(
        id: "resource.empty",
        title: "资源结果 · 无结果",
        note: "首页 SSE 返回空批次，显示「未找到相关资源」。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .empty]
      ),
      resourceScene(
        id: "resource.failure",
        title: "资源结果 · 搜索失败",
        note: "首页 SSE 抛错，空态上方显示模拟的失败原因。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .failure]
      ),
      resourceScene(
        id: "resource.loadMore",
        title: "资源结果 · 继续搜索中",
        note: "首屏数据正常，某个来源的下一页挂起。按「继续搜索」后进入停止/取消加载态。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePageMore: .hang]
      ),
      UIPreviewScene.page(
        id: "resource.filtered",
        title: "资源结果 · 筛选后",
        note: "页面加载完成后自动应用「站点 AlphaPT」筛选，只留下 2 条；可用筛选条清除。",
        environment: .standard
      ) {
        UIPreviewPageHost {
          SearchPreviewFilteredResource(request: titleResourceRequest)
        }
      },
      UIPreviewScene.page(
        id: "resource.noPermission",
        title: "资源结果 · 无搜索权限",
        note: "没有 search 权限时入口不会出现；这里直接渲染页面，搜索请求被权限守卫拦下，只显示空态。",
        environment: .limited(permissions: [.discovery])
      ) {
        UIPreviewPageHost {
          SearchPreviewResourcePage(request: mediaResourceRequest)
        }
      },
    ]
  }

  // MARK: - 对话框

  private static var sheetScenes: [UIPreviewScene] {
    [
      sheetScene(
        id: "sheet.manualMedia",
        title: "对话框 · 手动媒体搜索",
        note: "打开为未搜索状态；输入片名点「搜索」会调用 searchManualMedia 钩子。预览无法代填文本。"
      ) {
        ManualMediaSearchSheet(source: .themoviedb, onSelect: { _, _ in })
      },
      sheetScene(
        id: "sheet.addDownload",
        title: "对话框 · 添加下载",
        note: "种子、媒体与识别信息均为预填；下载器/保存路径来自 fetchDownloadClients 与 fetchDirectories fixture。"
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号"),
          meta: UIPreviewFixtures.resourceMeta
        )
      },
      sheetScene(
        id: "sheet.addDownload.directoryEmpty",
        title: "对话框 · 添加下载（目录为空）",
        note: "保存路径目录返回空数组，选择器只剩内建「自动」。",
        behaviors: [UIPreviewBehaviorKey.searchDirectories: .empty]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.failure",
        title: "对话框 · 添加下载（选项失败）",
        note: "目录请求抛错，面板显示「下载设置没有加载完成，请重试。」，下载按钮禁用并提供重试。",
        behaviors: [UIPreviewBehaviorKey.searchDirectories: .failure]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.submitting",
        title: "对话框 · 添加下载（提交中）",
        note: "点击「下载」后写请求延迟 30 秒，按钮保持「添加中」；本场景不会真正写入。",
        behaviors: [UIPreviewBehaviorKey.searchAddDownload: .delayed(seconds: 30)]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.forkSheet",
        title: "对话框 · 复用订阅",
        note: "订阅分享 → 我的订阅。点击「复用订阅」调用 forkSubscription 钩子，成功后关闭面板。"
      ) {
        SearchPreviewForkSheet()
      },
      sheetScene(
        id: "sheet.forkSheet.failure",
        title: "对话框 · 复用订阅失败",
        note: "点击「复用订阅」后写请求抛错，失败原因显示在按钮上方，可再次提交。",
        behaviors: [UIPreviewBehaviorKey.searchForkSubscription: .failure]
      ) {
        SearchPreviewForkSheet()
      },
    ]
  }

  // MARK: - 权限

  private static var permissionScenes: [UIPreviewScene] {
    [
      searchPage(
        id: "search.noSearchPermission",
        title: "搜索入口 · 无搜索权限",
        note: "只有 discovery 权限：搜索 Tab 仍可见，但只剩「聚合搜索」类型，资源搜索与字幕搜索类型被隐藏。",
        permissions: [.discovery]
      )
    ]
  }

  // MARK: - 构造辅助

  private static func searchPage(
    id: String,
    title: String,
    note: String,
    permissions: Set<UserPermissionKey>? = nil,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: previewEnvironment(permissions: permissions),
      behaviors: behaviors
    ) {
      UIPreviewTabRootView(tab: .search)
    }
  }

  private static func unifiedScene(
    id: String,
    title: String,
    note: String,
    permissions: Set<UserPermissionKey>? = nil,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: previewEnvironment(permissions: permissions),
      behaviors: behaviors
    ) {
      UIPreviewPageHost {
        SearchPreviewUnifiedResult()
      }
    }
  }

  private static func siteScene(
    id: String,
    title: String,
    note: String,
    selection: Set<Int>?,
    permissions: Set<UserPermissionKey>? = nil,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: previewEnvironment(permissions: permissions),
      behaviors: behaviors
    ) {
      UIPreviewPageHost {
        SearchPreviewSiteMenu(selection: selection)
      }
    }
  }

  private static func previewEnvironment(
    permissions: Set<UserPermissionKey>?
  ) -> UIPreviewEnvironment {
    if let permissions {
      return .limited(permissions: permissions)
    }
    return .standard
  }

  private static func resourceScene(
    id: String,
    title: String,
    note: String,
    request: ResourceSearchRequest,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: .standard,
      behaviors: behaviors
    ) {
      UIPreviewPageHost {
        SearchPreviewResourcePage(request: request)
      }
    }
  }

  private static func sheetScene<Content: View>(
    id: String,
    title: String,
    note: String,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    @ViewBuilder content: @escaping () -> Content
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: .standard.with(behaviors: behaviors)
    ) {
      UIPreviewPageHost {
        SearchPreviewSheetHost {
          content()
        }
      }
    }
  }

  private static var mediaResourceRequest: ResourceSearchRequest {
    let media = UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
    return ResourceSearchRequest(
      keyword: "tmdb:88001",
      type: media.type,
      area: nil,
      title: media.title,
      year: media.year,
      season: 1,
      mediaInfo: media,
      sites: nil
    )
  }

  private static var titleResourceRequest: ResourceSearchRequest {
    ResourceSearchRequest(
      keyword: "边境信号",
      type: "电视剧",
      area: "日本",
      title: "边境信号",
      year: "2026",
      season: 1,
      mediaInfo: nil,
      sites: nil
    )
  }
}

// MARK: - 场景根视图

/// 直接驱动真实 `UnifiedSearchResult`，避免为了预填搜索词而改生产 `SearchView`。
private struct SearchPreviewUnifiedResult: View {
  @StateObject private var viewModel = SearchViewModel()
  @StateObject private var navigationCoordinator = ImageNavigationCoordinator()
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var hasStarted = false

  var body: some View {
    Group {
      if !hasStarted || viewModel.isLoading {
        VStack(spacing: 24) {
          header
          Spacer()
          ProgressView("正在搜索…")
          Spacer()
        }
      } else {
        UnifiedSearchResult(
          viewModel: viewModel,
          imageLifecycle: navigationCoordinator.rootLifecycle,
          header: { header },
          onShareTapped: { share in
            guard APIService.shared.canAccess(.subscribe) else { return }
            subscriptionHandler.forkSheetRequest = share
          }
        )
      }
    }
    .environment(\.pageImageLifecycle, navigationCoordinator.rootLifecycle)
    .environmentObject(navigationCoordinator)
    .environmentObject(subscriptionHandler)
    .environmentObject(mediaActionHandler)
    .mediaSubscriptionAlerts(using: subscriptionHandler)
    .navigationDestination(for: ImageNavigationEntry.self) { entry in
      ImageNavigationDestination(entry: entry)
    }
    .task {
      hasStarted = true
      viewModel.query = "边境信号"
      viewModel.searchType = .unified
      // 预览不读取用户真实的默认影视来源，避免本机偏好把合集/人物行过滤掉。
      viewModel.mediaSearchSource = .themoviedb
      await viewModel.autoSearch()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("边境信号")
        .font(.largeTitle)
        .bold()
      Text("聚合搜索 · 媒体 / 系列 / 人物 / 订阅分享")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 60)
    .padding(.top, 40)
  }
}

/// 直接驱动真实 `SiteFilterViewModel` + `SearchSiteSelectionMenu`，
/// 展示资源搜索页眉里同一个站点菜单。
private struct SearchPreviewSiteMenu: View {
  let selection: Set<Int>?
  @StateObject private var siteFilter = SiteFilterViewModel()

  var body: some View {
    VStack(spacing: 40) {
      Text("资源搜索 · 站点筛选")
        .font(.largeTitle)
      SearchSiteSelectionMenu(viewModel: siteFilter) {
        Label(siteFilter.siteButtonLabel, systemImage: "antenna.radiowaves.left.and.right")
          .font(.headline)
          .padding(.horizontal, 28)
          .padding(.vertical, 14)
          .background(.regularMaterial, in: Capsule())
      }
      Text("聚焦站点按钮按确认打开菜单；选择即写回，不会自动发起搜索。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      await siteFilter.loadSites()
      if let selection {
        siteFilter.selectedSites = selection
      }
    }
  }
}

private struct SearchPreviewResourcePage: View {
  let request: ResourceSearchRequest
  @StateObject private var imageLifecycle = PageImageLifecycle()
  @State private var isSettingsReady = false

  var body: some View {
    Group {
      if isSettingsReady {
        ResourceResultView(request: request, imageLifecycle: imageLifecycle)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task {
      // 直接进入的单页场景没有走 ContentViewModel 启动流程；资源搜索按后端版本
      // 选择分页/旧 SSE 协议，所以先让 APIService.settings 就位。
      if APIService.shared.settings == nil {
        _ = try? await APIService.shared.fetchSettings()
      }
      isSettingsReady = true
    }
  }
}

/// 直接驱动真实 `ResourceSearchSession`，用于展示「筛选后」这一页内状态。
private struct SearchPreviewFilteredResource: View {
  let request: ResourceSearchRequest
  @StateObject private var search: ResourceSearchSession

  init(request: ResourceSearchRequest) {
    self.request = request
    _search = StateObject(
      wrappedValue: ResourceSearchSession(
        query: ResourceSearchQuery(
          keyword: request.keyword,
          type: request.type,
          area: request.area,
          title: request.title,
          year: request.year,
          season: request.season,
          sites: request.sites,
          isMediaSearch: isResourceMediaSearchKeyword(request.keyword)
        ),
        apiService: .shared
      )
    )
  }

  var body: some View {
    PagedResourceResultsView(search: search, onCancel: {}) {
      VStack(alignment: .leading, spacing: 4) {
        Text("边境信号 · 资源搜索")
          .font(.title3)
          .bold()
        Text("预览：加载完成后自动应用站点筛选 AlphaPT")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 48)
      .padding(.top, 24)
    }
    .task {
      search.start()
      // 首屏事务完成（initialComplete）时收集阶段可能还没收口，此时 publishSnapshot
      // 会被 isCollecting 挡掉；等 isBusy 落下后再应用筛选，确保投影真实刷新。
      for _ in 0..<50 {
        if search.initialComplete && !search.isBusy { break }
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard search.initialComplete else { return }
      search.filterForm = ["site": ["AlphaPT"]]
      search.updateProjection()
    }
    .onDisappear { search.deactivate() }
  }
}

/// 自动弹出 Sheet 的预览根视图。tvOS 上直接渲染 Sheet 内容不会呈现，
/// 需要一个已进入窗口的承载视图；这里延后一帧再设置 `isPresented`。
private struct SearchPreviewSheetHost<Content: View>: View {
  private let content: Content
  @State private var isPresented = false

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    Color.black
      .ignoresSafeArea()
      .sheet(isPresented: $isPresented) {
        content
      }
      .task {
        try? await Task.sleep(for: .milliseconds(400))
        isPresented = true
      }
  }
}

private struct SearchPreviewForkSheet: View {
  @StateObject private var subscriptionHandler = SubscriptionHandler()
  private let share = UIPreviewFixtures.previewSubscribeShare

  var body: some View {
    ForkSubscribeSheet(
      share: share,
      onFork: { _ in },
      subscriptionHandler: subscriptionHandler
    )
  }
}
#endif
