#if DEBUG
import SwiftUI

/// 主 Tab 页面场景：首页、推荐、探索、搜索、状态。
///
/// 每个场景都渲染真实 `MainContentView`，只把接口数据换成 fixture；
/// 加载中 / 空 / 失败 / 无权限通过 `UIPreviewBackend` 的逐接口行为控制。
@MainActor
enum UIPreviewScenesTabs {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "tabs",
      title: "主框架与一级页面",
      scenes: [
        // MARK: 首页
        .page(
          id: "home.dashboard",
          title: "首页 · 仪表盘（常规）",
          note:
            "「继续观看」+「最近添加」+「我的订阅」三行，标准全权限用户。继续观看卡片右上角是已播放百分比，剧集标题下是「S1:1 - 集名」。"
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.continueWatching.loading",
          title: "首页 · 继续观看加载中",
          note: "继续观看接口挂起、最近添加正常：本行显示加载占位卡，不影响其它行。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerPlaying: .hang]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.continueWatching.empty",
          title: "首页 · 继续观看为空",
          note: "继续观看接口成功但没有条目：本行显示「该服务器暂无继续观看内容」，最近添加照常。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerPlaying: .empty]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.continueWatching.failure",
          title: "首页 · 继续观看失败",
          note:
            "继续观看接口失败：页面顶部出现「部分数据加载失败，当前显示的是旧数据」与「重试」；行内没有单独的失败卡，没有条目时只写「该服务器暂无继续观看内容」。最近添加不受影响。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerPlaying: .failure]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.continueWatching.longList",
          title: "首页 · 继续观看长列表",
          note: "继续观看返回 12 条，验证横向长列表滚动、焦点移动与末尾项加载。",
          environment: UIPreviewEnvironment.standard.with(context: [
            UIPreviewContextKey.homeContinueWatchingLongList: "1"
          ])
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.loading",
          title: "首页 · 加载中",
          note: "媒体服务器最新入库接口挂起，页面保持骨架/加载态。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerLatest: .hang]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.empty",
          title: "首页 · 空数据",
          note: "没有媒体服务器、没有订阅，页面展示空状态。",
          behaviors: [
            UIPreviewBehaviorKey.homeMediaServers: .empty,
            UIPreviewBehaviorKey.homeMediaServerLatest: .empty,
            UIPreviewBehaviorKey.homeSubscriptions: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.failure",
          title: "首页 · 加载失败",
          note: "媒体服务器最新入库接口失败，页面展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerLatest: .failure]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.noSubscriptionPermission",
          title: "首页 · 无订阅权限",
          note: "仅有发现权限的用户，订阅区块被隐藏或提示无权限。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.discovery]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.subscriptionsTimeout",
          title: "首页 · 订阅列表超时",
          note:
            "最近添加正常；订阅接口模拟网络超时，页面顶部提示“部分数据加载失败，当前显示的是旧数据”并保留最近添加区块。订阅与最近添加使用不同的接口键，失败互不影响。",
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.subscriptionsUnauthorized",
          title: "首页 · 订阅列表登录失效",
          note:
            "订阅接口返回“登录已失效”。APIError 的本地化文案不会出现在首页，只落到同一条“部分数据加载失败”提示；验证底层错误细节不会泄漏给用户。",
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .error(.unauthorized)]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.latestFailureOffline",
          title: "首页 · 最近添加离线",
          note:
            "媒体服务器配置读取成功，但“最近添加”接口离线失败：最近添加为空并提示部分失败，我的订阅仍然完整展示。",
          behaviors: [UIPreviewBehaviorKey.homeMediaServerLatest: .error(.networkOffline)]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.allSectionsFailure",
          title: "首页 · 全部区块失败",
          note:
            "最近添加与订阅同时失败且没有旧数据：顶部只显示“部分数据加载失败，当前显示的是旧数据”和“重试”，最近添加区显示“该服务器暂无最近内容”，生产没有整页“加载失败”错误页。",
          behaviors: [
            UIPreviewBehaviorKey.homeMediaServerLatest: .error(.gateway(503)),
            UIPreviewBehaviorKey.detailSubscriptions: .error(.networkConnectionLost),
          ]
        ) {
          UIPreviewTabRootView(tab: .home)
        },
        .page(
          id: "home.refreshFailure",
          title: "首页 · 刷新失败保留旧数据",
          note:
            "进入场景先成功加载一屏，随后把最近添加与订阅都切为失败并调用真实 refreshData：旧快照保留，顶部出现部分失败提示，用于验证自动刷新/手动重试失败不会清空已有内容。",
          environment: UIPreviewEnvironment.standard
        ) {
          UIPreviewHomeRefreshFailureScene()
        },

        // MARK: 订阅
        .page(
          id: "subscriptions.list",
          title: "订阅页 · 电影与电视剧",
          note:
            "「订阅」Tab：电影订阅、电视剧订阅两行，卡片带海报与状态标记（阅/待/停）；按下编辑订阅，长按给详情、搜索、暂停/启用、重置和取消。",
          environment: UIPreviewEnvironment.standard
        ) {
          UIPreviewTabRootView(tab: .subscriptions)
        },
        .page(
          id: "subscriptions.loading",
          title: "订阅页 · 首次加载",
          note: "首轮加载未完成且没有可显示的订阅：整页居中转圈（pageLoadingOverlay）。",
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .hang]
        ) {
          UIPreviewTabRootView(tab: .subscriptions)
        },
        .page(
          id: "subscriptions.empty",
          title: "订阅页 · 空",
          note: "读取成功但没有订阅：说明订阅从哪里来，不显示重试。",
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .empty]
        ) {
          UIPreviewTabRootView(tab: .subscriptions)
        },
        .page(
          id: "subscriptions.failure",
          title: "订阅页 · 加载失败",
          note: "首轮读取失败且没有旧数据：整页显示「订阅加载失败，请重试」与重试按钮。",
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .failure]
        ) {
          UIPreviewTabRootView(tab: .subscriptions)
        },
        .page(
          id: "subscriptions.longList",
          title: "订阅页 · 长列表",
          note: "共 12 条电影/电视剧订阅，验证两行横向滚动、焦点移动与末尾卡片。",
          environment: UIPreviewEnvironment.standard.with(context: [
            UIPreviewContextKey.subscriptionsLongList: "1"
          ])
        ) {
          UIPreviewTabRootView(tab: .subscriptions)
        },

        // MARK: 推荐
        .page(
          id: "recommend.shelves",
          title: "推荐 · 货架列表（常规）",
          note: "多组推荐货架按行渲染，可横向滚动。"
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.loading",
          title: "推荐 · 加载中",
          note: "推荐接口挂起，首屏保持加载状态。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .hang]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.empty",
          title: "推荐 · 空数据",
          note: "推荐接口返回空列表，货架展示空状态。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .empty]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.failure",
          title: "推荐 · 加载失败",
          note: "推荐接口失败，货架展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .failure]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.loadingMore",
          title: "推荐 · 加载更多",
          note: "第一页已加载，第二页挂起，展示加载更多态。",
          behaviors: [UIPreviewBehaviorKey.recommendMore: .hang]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.timeout",
          title: "推荐 · 加载超时",
          note:
            "推荐接口以网络超时失败。推荐页没有单独的错误卡片，货架列表保持空态；用于确认超时与普通失败在 UI 上同形，错误细节只进日志。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.loadMoreFailure",
          title: "推荐 · 加载更多失败",
          note:
            "第一页正常，第二页返回 502。分页器保留已加载货架、不弹出错误；连续失败 3 次才会由分页器发全局通知。",
          behaviors: [UIPreviewBehaviorKey.recommendMore: .error(.gateway(502))]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },
        .page(
          id: "recommend.sourcesFailure",
          title: "推荐 · 推荐来源失败",
          note:
            "推荐来源接口失败、推荐数据正常：来自“更多推荐”等来源的货架缺失，内置货架仍显示，属于部分区块失败。",
          behaviors: [UIPreviewBehaviorKey.recommendSources: .error(.decoding)]
        ) {
          UIPreviewTabRootView(tab: .recommend)
        },

        // MARK: 探索
        .page(
          id: "explore.discover",
          title: "探索 · 发现列表（常规）",
          note: "默认数据源、来源切换与分页列表。"
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.loading",
          title: "探索 · 加载中",
          note: "发现列表接口挂起。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .hang]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.empty",
          title: "探索 · 空数据",
          note: "发现列表接口返回空列表。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .empty]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.failure",
          title: "探索 · 加载失败",
          note: "发现列表接口失败。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .failure]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.timeout",
          title: "探索 · 加载超时",
          note:
            "发现列表接口网络超时：网格保持空态，页面不展示具体错误文案；连续失败 3 次才由分页器发全局错误通知。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.unauthorized",
          title: "探索 · 登录失效",
          note:
            "发现列表接口返回“登录已失效”。预览钩子直接抛错，不经过真实 401 会话处理，因此页面只表现为空网格；会话失效链路需在真实网络下验证。",
          behaviors: [UIPreviewBehaviorKey.recommendMedia: .error(.unauthorized)]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.sourceFailurePartial",
          title: "探索 · 来源接口失败",
          note:
            "动态发现来源接口失败、列表接口正常：来源行保留内置项，额外的“豆瓣热榜”来源缺失，列表内容不受影响。",
          behaviors: [UIPreviewBehaviorKey.discoverSources: .error(.serverMessage("来源服务暂不可用"))]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.loadMoreFailure",
          title: "探索 · 加载更多失败",
          note:
            "第一页正常，第二页网络超时。分页器保留第一页网格，静默失败；只有连续失败触达上限后才弹出全局通知。",
          behaviors: [UIPreviewBehaviorKey.recommendMore: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.subscriptionShare",
          title: "探索 · 订阅分享",
          note: "订阅分享来源的列表，卡片带分享信息。"
        ) {
          UIPreviewTabRootView(tab: .explore)
        },
        .page(
          id: "explore.noDiscoveryPermission",
          title: "探索 · 无发现权限",
          note: "没有发现权限的用户，探索 Tab 不可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.manage, .subscribe]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },

        // MARK: 状态
        .page(
          id: "status.dashboard",
          title: "状态 · 仪表盘（常规）",
          note: "统计、存储、下载器概览全部有数据。"
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.loading",
          title: "状态 · 加载中",
          note: "仪表盘三个接口全部挂起。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .hang,
            UIPreviewBehaviorKey.statusStorage: .hang,
            UIPreviewBehaviorKey.statusDownloader: .hang,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.empty",
          title: "状态 · 空数据",
          note: "统计/存储/下载器均无数据。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .empty,
            UIPreviewBehaviorKey.statusStorage: .empty,
            UIPreviewBehaviorKey.statusDownloader: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.failure",
          title: "状态 · 加载失败",
          note: "仪表盘接口失败，展示错误与重试。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .failure,
            UIPreviewBehaviorKey.statusDownloader: .failure,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.statisticTimeout",
          title: "状态 · 统计超时",
          note:
            "统计接口网络超时。统计、存储、下载器三项用 async let 并发加载，任一失败会让三项都保持 nil，最终统一显示“未获取”，不会出现半套数据。",
          behaviors: [UIPreviewBehaviorKey.statusStatistic: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.storageDecoding",
          title: "状态 · 存储解码失败",
          note:
            "存储接口返回无法解码的响应。页面只显示“未获取”，不会暴露“响应解析失败”等底层文案；用于确认解码失败与超时在仪表盘上不可区分。",
          behaviors: [UIPreviewBehaviorKey.statusStorage: .error(.decoding)]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloaderOffline",
          title: "状态 · 下载器概览离线",
          note:
            "下载器概览接口离线失败。与下载任务列表使用不同的接口键：仪表盘三项“未获取”，下方下载任务仍可正常加载。",
          behaviors: [UIPreviewBehaviorKey.statusDownloader: .error(.networkOffline)]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.partialDashboardFailure",
          title: "状态 · 仪表盘部分接口失败",
          note:
            "统计与存储失败、下载器成功：因为三路结果在同一个 async let 元组里汇总，成功的一路也不会展示，三项全部显示“未获取”。",
          behaviors: [
            UIPreviewBehaviorKey.statusStatistic: .error(.serverMessage("统计服务异常")),
            UIPreviewBehaviorKey.statusStorage: .error(.gateway(504)),
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.noManagePermission",
          title: "状态 · 无管理权限",
          note: "没有管理权限的用户，状态 Tab 不可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.discovery]))
        ) {
          UIPreviewTabRootView(tab: .home)
        },

        // MARK: 状态页细节状态（统一走真实状态页，保留 Tab 栏与仪表盘）
        .page(
          id: "status.downloading",
          title: "状态 · 下载任务",
          note: "整页状态页：仪表盘概览、下载任务区块（客户端选择、进度、状态徽标）和整理历史。"
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingEmpty",
          title: "状态 · 下载任务为空",
          note: "没有下载任务时展示空状态。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .empty]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingFailure",
          title: "状态 · 下载任务失败",
          note: "下载任务接口失败时展示错误与重试。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .failure]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingItemsTimeout",
          title: "状态 · 下载任务接口超时",
          note:
            "下载器在线、任务列表接口超时：页面最终显示“暂无下载任务”，没有错误文案或重试入口；只有连续失败 5 次才弹出“下载任务刷新失败，正在自动重试。”，这是当前的一处反馈缺口。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .error(.networkTimeout)]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingClientsFailure",
          title: "状态 · 下载器列表失败",
          note:
            "下载器配置接口失败：页面显示“下载器加载失败，正在自动重试”，任务列表为空；与任务接口失败时的纯空态不同。",
          behaviors: [UIPreviewBehaviorKey.downloadClients: .error(.unauthorized)]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingNoClients",
          title: "状态 · 未配置下载器",
          note:
            "下载器配置返回空列表：没有可选择的下载器，页面只显示“暂无下载任务”，不会提示“未配置下载器”或引导去设置。",
          behaviors: [UIPreviewBehaviorKey.downloadClients: .empty]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.downloadingOperationFailure",
          title: "状态 · 暂停下载失败通知",
          note:
            "覆盖真实下载列表并展示操作失败后的全局错误通知“暂停下载失败，请稍后重试。”。预览无法注入点击，因此通知文案按生产提示直接展示；恢复/删除失败共用同一条错误通知通道。",
          environment: UIPreviewEnvironment.standard
        ) {
          UIPreviewBannerHost(
            type: .error,
            message: "暂停下载失败，请稍后重试。",
            duration: 600
          ) {
            UIPreviewTabRootView(tab: .status)
          }
        },
        .page(
          id: "status.transferHistory",
          title: "状态 · 整理历史",
          note: "整页状态页：仪表盘、下载任务和整理历史列表（媒体信息、整理状态、批量操作入口）。下载任务置空，保证整理历史首屏可见。",
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .empty]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistoryEmpty",
          title: "状态 · 整理历史为空",
          note: "整页状态页；没有整理记录时展示空状态。下载任务置空，保证整理历史首屏可见。",
          behaviors: [
            UIPreviewBehaviorKey.downloadingItems: .empty,
            UIPreviewBehaviorKey.transferHistory: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistoryFailure",
          title: "状态 · 整理历史失败",
          note: "整页状态页；整理历史接口失败时展示错误与重试。下载任务置空，保证整理历史首屏可见。",
          behaviors: [
            UIPreviewBehaviorKey.downloadingItems: .empty,
            UIPreviewBehaviorKey.transferHistory: .failure,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistoryTimeout",
          title: "状态 · 整理历史超时",
          note:
            "整页状态页；整理历史接口网络超时。页面只显示“没有数据”，与真正空列表同形；超时/解析失败等错误细节不会出现在列表里。下载任务置空，保证整理历史首屏可见。",
          behaviors: [
            UIPreviewBehaviorKey.downloadingItems: .empty,
            UIPreviewBehaviorKey.transferHistory: .error(.networkTimeout),
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistorySearchEmpty",
          title: "状态 · 整理历史搜索为空",
          note:
            "整页状态页；整理历史为空。真实搜索不存在的关键词后也会重置分页并展示同样的“没有数据”，预览直接呈现该结果。整理历史没有状态筛选，只支持关键词。",
          behaviors: [
            UIPreviewBehaviorKey.downloadingItems: .empty,
            UIPreviewBehaviorKey.transferHistory: .empty,
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistoryFailedOnly",
          title: "状态 · 整理失败记录",
          note:
            "整页状态页；只返回失败记录（状态 false），聚焦其中一条时展示红色失败原因；原因超过 20 个字符会截断，完整内容需进入详情或日志确认。下载任务置空，保证整理历史首屏可见。",
          environment: transferFailedEnvironment,
          behaviors: [UIPreviewBehaviorKey.downloadingItems: .empty]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.transferHistoryLoadMoreFailure",
          title: "状态 · 整理历史加载更多失败",
          note:
            "整页状态页，首屏 20 条；滚动到整理历史底部会触发真实 loadMore，连续 3 次第二页失败后列表保留第一页并弹出“加载数据失败，请重试。”。",
          environment: transferLoadMoreFailureEnvironment,
          behaviors: [
            UIPreviewBehaviorKey.downloadingItems: .empty,
            UIPreviewBehaviorKey.transferHistoryMore: .error(.networkTimeout),
          ]
        ) {
          UIPreviewTabRootView(tab: .status)
        },
        .page(
          id: "status.manageOnly",
          title: "状态 · 仅管理权限",
          note: "非超级管理员只有 manage 权限：仪表盘概览隐藏，下载/整理仍可见。",
          environment: UIPreviewEnvironment.limited(permissions: Set([.manage]), superUser: false)
        ) {
          UIPreviewTabRootView(tab: .status)
        },

        // MARK: 设置入口
        .page(
          id: "system.root",
          title: "设置 · 根页面",
          note: "设置页入口列表（子页面在“设置”分区）。"
        ) {
          UIPreviewTabRootView(tab: .system)
        },
      ]
    )
  }

  /// 只返回失败记录的整理历史环境。
  private static var transferFailedEnvironment: UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.standard
    environment.context[UIPreviewContextKey.transferHistoryOnlyFailed] = "1"
    return environment
  }

  /// 24 条整理历史 + 第二页失败的环境。
  private static var transferLoadMoreFailureEnvironment: UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.standard
    environment.context[UIPreviewContextKey.transferHistoryLongList] = "1"
    return environment
  }
}

// MARK: - 刷新失败 / 搜索为空 / 加载更多失败

/// 先成功加载首页，再切换为失败行为并调用真实 `refreshData`，用于验证旧数据保留。
@MainActor
private struct UIPreviewHomeRefreshFailureScene: View {
  @StateObject private var viewModel = HomeViewModel()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var didStart = false
  @State private var isReady = false

  var body: some View {
    Group {
      if isReady {
        HomeView(viewModel: viewModel)
      } else {
        ProgressView("正在加载首页…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(AppBackground())
    .environmentObject(mediaActionHandler)
    .withNotification()
    .task {
      guard !didStart else { return }
      didStart = true
      UIPreviewBackend.shared.activate(.standard)
      await viewModel.loadData()

      var failed = UIPreviewEnvironment.standard
      failed.behaviors[UIPreviewBehaviorKey.homeMediaServerLatest] = .error(.networkTimeout)
      failed.behaviors[UIPreviewBehaviorKey.detailSubscriptions] = .error(.networkOffline)
      UIPreviewBackend.shared.activate(failed)
      await viewModel.refreshData()
      isReady = true
    }
  }
}

#endif
