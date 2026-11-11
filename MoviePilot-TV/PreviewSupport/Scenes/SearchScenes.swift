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
      scenes: entryScenes + keywordScenes + aggregateScenes + siteScenes + resourceScenes
        + sheetScenes + permissionScenes
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

  // MARK: - 关键词搜索入口

  private static var keywordScenes: [UIPreviewScene] {
    [
      searchPage(
        id: "search.keyword.failure",
        title: "关键词搜索 · 请求失败",
        note:
          "真实搜索 Tab。在顶部搜索栏输入「边境信号」，再点「聚合搜索」按钮（按钮动作会带上当前关键词发起请求）；四类请求全部抛错。聚合页没有错误位，只会落成「未找到相关结果」。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .failure,
          UIPreviewBehaviorKey.searchCollection: .failure,
          UIPreviewBehaviorKey.searchPerson: .failure,
          UIPreviewBehaviorKey.searchSubscriptionShares: .failure,
        ]
      ),
      searchPage(
        id: "search.keyword.timeout",
        title: "关键词搜索 · 超时",
        note:
          "四类请求都以 networkTimeout 失败。先在搜索栏输入关键词，再点「聚合搜索」按钮发起请求；页面同样只显示「未找到相关结果」，不会出现超时文案。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchCollection: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchPerson: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchSubscriptionShares: .error(.networkTimeout),
        ]
      ),
      searchPage(
        id: "search.keyword.empty",
        title: "关键词搜索 · 无结果",
        note:
          "四类请求都返回空列表。先在搜索栏输入关键词，再点「聚合搜索」按钮发起请求；显示「未找到相关结果」。清空搜索词不会自动重搜，结果区仍保留上一次的空态。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .empty,
          UIPreviewBehaviorKey.searchCollection: .empty,
          UIPreviewBehaviorKey.searchPerson: .empty,
          UIPreviewBehaviorKey.searchSubscriptionShares: .empty,
        ]
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
        id: "search.unified.mediaFailure",
        title: "聚合搜索 · 仅媒体失败",
        note: "只有 searchMedia 抛错：电影/电视剧行消失，合集、人物、订阅分享仍正常；媒体分页器的错误不会显示在聚合页。",
        behaviors: [UIPreviewBehaviorKey.searchMedia: .failure]
      ),
      unifiedScene(
        id: "search.unified.collectionFailure",
        title: "聚合搜索 · 仅合集失败",
        note: "只有 searchCollection 抛错：系列行消失，其余行正常。",
        behaviors: [UIPreviewBehaviorKey.searchCollection: .failure]
      ),
      unifiedScene(
        id: "search.unified.personFailure",
        title: "聚合搜索 · 仅人物失败",
        note: "只有 searchPerson 抛错：演职人员行消失，其余行正常。",
        behaviors: [UIPreviewBehaviorKey.searchPerson: .failure]
      ),
      unifiedScene(
        id: "search.unified.shareFailure",
        title: "聚合搜索 · 仅订阅分享失败",
        note: "只有 searchSubscriptionShares 抛错：订阅分享行消失，其余行正常；分享入口也不显示错误。",
        behaviors: [UIPreviewBehaviorKey.searchSubscriptionShares: .failure]
      ),
      unifiedScene(
        id: "search.unified.unauthorized",
        title: "聚合搜索 · 401 未授权",
        note:
          "四类请求都抛 unauthorized（「登录已失效」）。错误在分页层被吞掉，聚合页最终只显示「未找到相关结果」；此场景不模拟 APIService 的全局会话失效处理。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .error(.unauthorized),
          UIPreviewBehaviorKey.searchCollection: .error(.unauthorized),
          UIPreviewBehaviorKey.searchPerson: .error(.unauthorized),
          UIPreviewBehaviorKey.searchSubscriptionShares: .error(.unauthorized),
        ]
      ),
      unifiedScene(
        id: "search.unified.timeout",
        title: "聚合搜索 · 请求超时",
        note: "四类请求都以 networkTimeout 失败；与通用 .failure 一样被分页器吞掉，页面只落空态。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchCollection: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchPerson: .error(.networkTimeout),
          UIPreviewBehaviorKey.searchSubscriptionShares: .error(.networkTimeout),
        ]
      ),
      unifiedScene(
        id: "search.unified.decoding",
        title: "聚合搜索 · 响应解析失败",
        note: "四类请求都以 decodingError 失败，页面同样没有解析失败提示，只显示空态。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .error(.decoding),
          UIPreviewBehaviorKey.searchCollection: .error(.decoding),
          UIPreviewBehaviorKey.searchPerson: .error(.decoding),
          UIPreviewBehaviorKey.searchSubscriptionShares: .error(.decoding),
        ]
      ),
      unifiedScene(
        id: "search.unified.gateway",
        title: "聚合搜索 · 网关 503",
        note: "四类请求都返回 gatewayStatus(503)；聚合页不会区分网关错误，只显示「未找到相关结果」。",
        behaviors: [
          UIPreviewBehaviorKey.searchMedia: .error(.gateway(503)),
          UIPreviewBehaviorKey.searchCollection: .error(.gateway(503)),
          UIPreviewBehaviorKey.searchPerson: .error(.gateway(503)),
          UIPreviewBehaviorKey.searchSubscriptionShares: .error(.gateway(503)),
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
        id: "search.sites.loadFailure",
        title: "站点菜单 · 站点加载失败",
        note:
          "权威站点请求以 networkTimeout 失败（预览钩子直接抛出，不演示 /site/rss 降级）。按钮显示「全部站点」，打开菜单会看到真实超时文案和「重新加载」按钮。",
        selection: [],
        behaviors: [UIPreviewBehaviorKey.searchAllSites: .error(.networkTimeout)]
      ),
      siteScene(
        id: "search.sites.allDisabled",
        title: "站点菜单 · 全部停用",
        note:
          "权威域返回三个站点但全部 is_active=false。菜单仍列出名称；「全部站点」在请求时解析不到 active 站点，不再生成显式 sites 参数。",
        selection: [],
        behaviors: [UIPreviewBehaviorKey.searchAllSitesDisabled: .data]
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
        id: "resource.error.http500",
        title: "资源结果 · 首屏 HTTP 500",
        note:
          "首页 SSE 返回 HTTP 500。空态标题仍是「未找到相关资源」，描述区显示真实 APIError 文案「HTTP 500」，并提供「重新搜索」。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .error(.http(500))]
      ),
      resourceScene(
        id: "resource.error.http502",
        title: "资源结果 · 首屏 HTTP 502",
        note: "首页 SSE 返回网关 502，空态描述显示「HTTP 502」；不计入来源失败，仍可重新搜索。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .error(.gateway(502))]
      ),
      resourceScene(
        id: "resource.error.offline",
        title: "资源结果 · 网络断开",
        note: "首页 SSE 以 networkOffline 失败，空态描述使用系统网络错误文案；「重新搜索」可重新发起。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .error(.networkOffline)]
      ),
      resourceScene(
        id: "resource.error.timeout",
        title: "资源结果 · 首屏超时",
        note: "首页 SSE 以 networkTimeout 失败，空态显示超时文案与「重新搜索」。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .error(.networkTimeout)]
      ),
      resourceScene(
        id: "resource.error.invalidEvent",
        title: "资源结果 · 非法 SSE 事件",
        note:
          "终页事件的 total_items 与 items 数量不一致，真实事务校验抛出 incompletePage；页面显示「本页结果未完整返回，已保留已有结果，可继续搜索重试。」",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourceMalformedBatch: .data]
      ),
      resourceScene(
        id: "resource.error.moreFailure",
        title: "资源结果 · 加载更多失败",
        note:
          "首屏 4 条正常。按「继续搜索」后 AlphaPT 下一页超时：结果保留，结果区上方出现错误文案，来源轮转仍可继续。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourcePageMore: .error(.networkTimeout)]
      ),
      resourceScene(
        id: "resource.sources.partialFailure",
        title: "资源结果 · 部分站点失败",
        note:
          "BetaHD 来源带 error、结果只来自 AlphaPT/GammaPT。页面显示「部分搜索来源失败，已保留成功结果。」并保留继续搜索。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourceSourcesPartialFailure: .data]
      ),
      resourceScene(
        id: "resource.sources.allUnavailable",
        title: "资源结果 · 全部站点不可用",
        note:
          "首屏先收到 4 条预览（可见「已保留 4 条」），约 1.2 秒后终页把三个来源都标记为无法连接且没有最终条目；终页替换掉预览后只剩「未找到相关资源」和真实的「部分搜索来源失败，已保留成功结果。」（已保留 0 条），且「重新搜索/继续搜索」都不会出现（真实死路状态）。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourceSourcesAllUnavailable: .data]
      ),
      resourceScene(
        id: "resource.progressStuck",
        title: "资源结果 · 搜索迟迟不结束",
        note:
          "收到 4 条预览结果后连接挂起，进度停在 88%，可看到「已保留 4 条 · 本次新增 4 条」与「停止并查看」；点按后同一页切到结果列表并显示这 4 条预览。",
        request: titleResourceRequest,
        behaviors: [UIPreviewBehaviorKey.resourceStuckProgress: .hang]
      ),
      UIPreviewScene.page(
        id: "resource.cancelled",
        title: "资源结果 · 搜索中取消",
        note:
          "首屏 SSE 挂起。点按「取消」会走真实 stop 路径：搜索停止、保留 0 条并显示「重新搜索」（生产页由上层负责关闭，预览留在本页观察停止后的状态）。",
        environment: .standard,
        behaviors: [UIPreviewBehaviorKey.resourcePage: .hang]
      ) {
        UIPreviewPageHost {
          SearchPreviewCancellableResource(request: mediaResourceRequest)
        }
      },
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
        id: "resource.filteredEmpty",
        title: "资源结果 · 筛选后为空",
        note:
          "加载完成后同时应用「站点 BetaHD」与「2160p」两个互相排斥的筛选，4 条资源全部被筛掉；显示「没有符合当前筛选条件的资源，可以清除筛选。」",
        environment: .standard
      ) {
        UIPreviewPageHost {
          SearchPreviewFilteredResource(
            request: titleResourceRequest,
            filterForm: ["site": ["BetaHD"], "resolution": ["2160p"]],
            note: "预览：加载完成后应用站点 BetaHD + 分辨率 2160p，结果为空"
          )
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
        id: "sheet.manualMedia.noResults",
        title: "对话框 · 手动媒体搜索（无结果）",
        note: "输入任意片名点「搜索」：searchManualMedia 返回空数组，显示「没有找到「片名」，请换个片名再试。」。",
        behaviors: [UIPreviewBehaviorKey.searchManualMedia: .empty]
      ) {
        ManualMediaSearchSheet(source: .themoviedb, onSelect: { _, _ in })
      },
      sheetScene(
        id: "sheet.manualMedia.failure",
        title: "对话框 · 手动媒体搜索（请求失败）",
        note: "提交搜索后 fixture 抛错：显示「搜索失败，请稍后重试。」与「重试」，重试仍走失败分支。",
        behaviors: [UIPreviewBehaviorKey.searchManualMedia: .failure]
      ) {
        ManualMediaSearchSheet(source: .themoviedb, onSelect: { _, _ in })
      },
      sheetScene(
        id: "sheet.manualMedia.timeout",
        title: "对话框 · 手动媒体搜索（超时）",
        note: "searchManualMedia 以 networkTimeout 失败：ViewModel 不区分错误类型，仍只显示通用失败文案与「重试」。",
        behaviors: [UIPreviewBehaviorKey.searchManualMedia: .error(.networkTimeout)]
      ) {
        ManualMediaSearchSheet(source: .themoviedb, onSelect: { _, _ in })
      },
      sheetScene(
        id: "sheet.manualMedia.noPermission",
        title: "对话框 · 手动媒体搜索（无搜索权限）",
        note:
          "只有 discovery 权限。当前 ManualMediaSearchSheet 没有 search 权限守卫，输入片名仍能搜索成功；本场景用于暴露这一实现现状，若产品要求禁止需在生产代码补守卫。",
        permissions: [.discovery]
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
        id: "sheet.addDownload.noDownloader",
        title: "对话框 · 添加下载（无下载器）",
        note: "fetchDownloadClients 返回空数组：下载器选择器只剩内建「自动」，保存路径仍有两个目录可选。",
        behaviors: [UIPreviewBehaviorKey.downloadClients: .empty]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.noPermission",
        title: "对话框 · 添加下载（无搜索权限）",
        note:
          "只有 discovery 权限：loadData 因权限直接清空下载器/目录且不写 loadErrorMessage，「下载」按钮保持禁用，面板内没有权限说明。",
        permissions: [.discovery]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.downloaderOffline",
        title: "对话框 · 添加下载（下载器离线）",
        note: "点「下载」后 addDownload 返回 success=false 与离线业务文案，错误显示在按钮上方，可再次提交。",
        behaviors: [UIPreviewBehaviorKey.searchAddDownloadOffline: .data]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.rejected",
        title: "对话框 · 添加下载（后端拒绝）",
        note: "点「下载」后 addDownload 返回 success=false 与保存路径业务文案；与目录加载失败不同，选项仍可正常选择。",
        behaviors: [UIPreviewBehaviorKey.searchAddDownload: .empty]
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
        )
      },
      sheetScene(
        id: "sheet.addDownload.invalidMediaId",
        title: "对话框 · 添加下载（TMDB ID 非法）",
        note: "媒体身份预填为 themoviedb + media_id=0：面板显示「媒体 ID 格式无效。」，「下载」按钮禁用。"
      ) {
        AddDownloadSheet(
          torrent: UIPreviewFixtures.resourceTorrent,
          media: invalidMediaIdMedia
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
      sheetScene(
        id: "sheet.forkSheet.noPermission",
        title: "对话框 · 复用订阅无权限",
        note: "没有 subscribe 权限：handler 在发请求前直接返回，按钮可点但不会产生错误文案或进度。",
        permissions: [.discovery]
      ) {
        SearchPreviewForkSheet()
      },
      sheetScene(
        id: "sheet.forkSheet.notFound",
        title: "对话框 · 复用订阅（分享不存在）",
        note: "forkSubscription 返回 HTTP 404：handler 统一捕获，按钮上方只显示「暂时无法复用订阅《…》，请稍后重试。」。",
        behaviors: [UIPreviewBehaviorKey.searchForkSubscription: .error(.http(404))]
      ) {
        SearchPreviewForkSheet()
      },
      sheetScene(
        id: "sheet.forkSheet.serverError",
        title: "对话框 · 复用订阅（服务端 500）",
        note: "forkSubscription 返回 HTTP 500：不区分状态码，仍显示通用复用失败文案。",
        behaviors: [UIPreviewBehaviorKey.searchForkSubscription: .error(.http(500))]
      ) {
        SearchPreviewForkSheet()
      },
      sheetScene(
        id: "sheet.forkSheet.timeout",
        title: "对话框 · 复用订阅（超时）",
        note: "forkSubscription 以 networkTimeout 失败：显示通用复用失败文案，而不是系统超时文案。",
        behaviors: [UIPreviewBehaviorKey.searchForkSubscription: .error(.networkTimeout)]
      ) {
        SearchPreviewForkSheet()
      },
      sheetScene(
        id: "sheet.forkSheet.businessFailure",
        title: "对话框 · 复用订阅（业务失败）",
        note: "后端抛出业务错误「分享已被删除或不可见」：handler 丢弃原始文案，只显示通用复用失败提示。",
        behaviors: [
          UIPreviewBehaviorKey.searchForkSubscription: .error(.business("分享已被删除或不可见"))
        ]
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
    permissions: Set<UserPermissionKey>? = nil,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    @ViewBuilder content: @escaping () -> Content
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: previewEnvironment(permissions: permissions).with(behaviors: behaviors)
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

  /// 添加下载面板的非法身份：themoviedb 的 media_id=0 会被判为格式无效。
  private static var invalidMediaIdMedia: MediaInfo {
    UIPreviewFixtures.decode(
      MediaInfo.self,
      """
      {
        "media_source": "themoviedb",
        "media_id": "0",
        "title": "边境信号（TMDB ID 非法）",
        "type": "电视剧",
        "year": "2026"
      }
      """
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
  let filterForm: [String: Set<String>]
  let note: String
  @StateObject private var search: ResourceSearchSession

  init(
    request: ResourceSearchRequest,
    filterForm: [String: Set<String>] = ["site": ["AlphaPT"]],
    note: String = "预览：加载完成后自动应用站点筛选 AlphaPT"
  ) {
    self.request = request
    self.filterForm = filterForm
    self.note = note
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
        Text(note)
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
      search.filterForm = filterForm
      search.updateProjection()
    }
    .onDisappear { search.deactivate() }
  }
}

/// 直接驱动真实 `ResourceSearchSession`，用于观察搜索中取消后的停止态。
private struct SearchPreviewCancellableResource: View {
  @StateObject private var search: ResourceSearchSession

  init(request: ResourceSearchRequest) {
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
    PagedResourceResultsView(search: search, onCancel: { search.stop() }) {
      VStack(alignment: .leading, spacing: 4) {
        Text("边境信号 · 资源搜索")
          .font(.title3)
          .bold()
        Text("预览：搜索中；点「取消」执行真实 stop()，页面保留用于观察停止后状态")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 48)
      .padding(.top, 24)
    }
    .task { search.start() }
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
