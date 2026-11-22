#if DEBUG
import SwiftUI

/// 「媒体详情」域预览场景：详情页、订阅面板、分季管理、合集、人物与豆瓣阅读页。
///
/// 详情页的第二页（推荐、演员、豆瓣）在第一页「内容」区域向下滑进入；
/// 场景 note 会提示需要滑动到第二页才能看到对应覆盖项。
@MainActor
enum UIPreviewScenesDetail {
  private static let movie = UIPreviewFixtures.detailMovieMedia()
  private static let externalMovie = UIPreviewFixtures.detailExternalMovieMedia()
  private static let tv = UIPreviewFixtures.detailTVMedia()

  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "detail",
      title: "媒体详情",
      scenes: [
        // MARK: 详情加载

        .page(
          id: "detail.loading",
          title: "详情 · 加载中",
          note: "详情接口挂起，保留转场遮罩、海报与标题骨架。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .hang]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failure",
          title: "详情 · 加载失败",
          note: "详情接口失败，遮罩显示失败原因；当前错误不可重试。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .failure]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },

        // MARK: 电影详情

        .page(
          id: "detail.movie",
          title: "详情 · 电影（未订阅）",
          note: "评分与来源徽章、订阅按钮、TMDB 入口。向下滑到第二页查看推荐、演员与豆瓣行。"
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.movieSubscribed",
          title: "详情 · 电影已订阅（不在库）",
          note: "订阅状态查询命中，头部显示已订阅；媒体服务器无入库记录。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "subscribed"])
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.movieInLibrary",
          title: "详情 · 电影已订阅且入库",
          note:
            "订阅状态命中且媒体服务器存在条目：头部显示「已订阅」，TMDB 后面多一个圆形「跳转媒体库」按钮（Emby 深链由 `/mediaserver/play` 返回的网页地址换算）。",
          environment: detailEnvironment(context: [
            UIPreviewDetailContext.subscription: "subscribed",
            UIPreviewDetailContext.libraryItem: "1",
          ])
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.libraryJumpFailure",
          title: "详情 · 跳转媒体库地址读取失败",
          note:
            "已入库但 `/mediaserver/play` 失败：拿不到 App 深链，圆形「跳转媒体库」按钮不出现，订阅与 TMDB 按钮照常可用。",
          environment: detailEnvironment(context: [
            UIPreviewDetailContext.subscription: "subscribed",
            UIPreviewDetailContext.libraryItem: "1",
          ]),
          behaviors: [UIPreviewBehaviorKey.detailMediaServerPlayLink: .failure]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.movieNoMediaServer",
          title: "详情 · 无媒体服务器",
          note: "应用内播放版本、已入库但没有任何媒体服务器，页面不出现播放入口。",
          environment: detailPlaybackEnvironment(context: [
            UIPreviewDetailContext.subscription: "subscribed",
            UIPreviewDetailContext.libraryItem: "1",
          ]),
          behaviors: [UIPreviewBehaviorKey.homeMediaServers: .empty]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.externalSource",
          title: "详情 · 豆瓣来源徽章",
          note: "豆瓣条目没有 TMDB ID：展示来源与评分，TMDB 按钮负责识别后再跳转。"
        ) {
          UIPreviewDetailSceneRoot(media: externalMovie)
        },
        .page(
          id: "detail.tmdbJump",
          title: "详情 · TMDB 跳转",
          note: "点按 TMDB 按钮后识别 90_101 并 push 对应详情页，导航栈为真实实现。"
        ) {
          UIPreviewDetailSceneRoot(media: externalMovie)
        },
        .page(
          id: "detail.tmdbRecognizing",
          title: "详情 · TMDB 识别中",
          note: "TMDB 识别接口挂起，按钮保持加载态，详情正文仍可浏览。",
          behaviors: [UIPreviewBehaviorKey.detailRecognizeTmdb: .hang]
        ) {
          UIPreviewDetailSceneRoot(media: externalMovie)
        },

        // MARK: 电视剧详情

        .page(
          id: "detail.tvSeasons",
          title: "详情 · 电视剧分季",
          note: "第一页分季选择（3 季），第二页剧集列表；切换季会加载对应集。"
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },
        .page(
          id: "detail.tvManySeasons",
          title: "详情 · 电视剧多季",
          note: "12 季数据，用于确认季名过长、季菜单溢出时的布局。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.manySeasons: "1"])
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },
        .page(
          id: "detail.tvEpisodeGroup",
          title: "详情 · 剧集分组",
          note: "详情带播出顺序剧集组；剧集行的组菜单可切换官方顺序 / 播出顺序。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.episodeGroup: "1"]),
          behaviors: [UIPreviewBehaviorKey.detailGroupSeasons: .delayed(seconds: 1)]
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },

        // MARK: 权限

        .page(
          id: "detail.noSubscribePermission",
          title: "详情 · 无订阅权限",
          note: "只有发现与搜索权限：订阅按钮和分季管理入口隐藏，剧集与豆瓣仍可见。",
          environment: UIPreviewEnvironment.limited(permissions: [.discovery, .search])
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },
        .page(
          id: "detail.noSearchPermission",
          title: "详情 · 无搜索权限",
          note: "只有发现与订阅权限：搜索资源、搜索字幕入口隐藏，订阅与 TMDB 保留。",
          environment: UIPreviewEnvironment.limited(permissions: [.discovery, .subscribe])
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },

        // MARK: 第二页内容

        .page(
          id: "detail.rowsEmpty",
          title: "详情 · 推荐 / 相似 / 演员为空",
          note: "第二页的推荐、相似、演职员、豆瓣短评与影评全部为空，页面只保留基础信息。",
          behaviors: [
            UIPreviewBehaviorKey.detailRecommendations: .empty,
            UIPreviewBehaviorKey.detailSimilar: .empty,
            UIPreviewBehaviorKey.detailActors: .empty,
            UIPreviewBehaviorKey.detailDoubanComments: .empty,
            UIPreviewBehaviorKey.detailDoubanReviews: .empty,
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.rowsFailure",
          title: "详情 · 推荐 / 相似 / 演员失败",
          note: "第二页各行接口失败，检查行内错误提示；重新进入场景可重试。",
          behaviors: [
            UIPreviewBehaviorKey.detailRecommendations: .failure,
            UIPreviewBehaviorKey.detailSimilar: .failure,
            UIPreviewBehaviorKey.detailActors: .failure,
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.rowsLoadMore",
          title: "详情 · 推荐 / 相似 / 演员加载更多",
          note: "第二页把焦点移到行尾触发下一页；更多数据延迟 1 秒返回，观察加载占位。",
          behaviors: [
            UIPreviewBehaviorKey.detailRecommendationsMore: .delayed(seconds: 1),
            UIPreviewBehaviorKey.detailSimilarMore: .delayed(seconds: 1),
            UIPreviewBehaviorKey.detailActorsMore: .delayed(seconds: 1),
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.actorsPagination",
          title: "详情 · 演员表分页",
          note: "第一页 8 位演员；焦点移到行尾后拉取第二页，更多演员延迟返回。",
          behaviors: [UIPreviewBehaviorKey.detailActorsMore: .delayed(seconds: 1)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },

        // MARK: 豆瓣

        .page(
          id: "detail.douban",
          title: "详情 · 豆瓣短评与影评",
          note: "第二页豆瓣区块：短评/影评切换、分页入口；点条目会打开阅读 Sheet。"
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanCommentReader",
          title: "详情 · 豆瓣短评阅读页",
          note: "直接渲染真实的豆瓣短评阅读 Sheet，检查作者栏、星级与长正文排版。"
        ) {
          UIPreviewReadingScene(entry: UIPreviewFixtures.detailCommentEntry)
        },
        .page(
          id: "detail.doubanReviewReader",
          title: "详情 · 豆瓣长评阅读页",
          note: "直接渲染真实的豆瓣影评阅读 Sheet，检查标题、分段正文与侧栏信息。"
        ) {
          UIPreviewReadingScene(entry: UIPreviewFixtures.detailReviewEntry)
        },

        // MARK: 取消订阅

        .page(
          id: "detail.unsubscribeConfirm",
          title: "详情 · 取消订阅确认",
          note: "详情页已订阅状态，直接展示生产环境同一套取消订阅文案与确认按钮。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "subscribed"])
        ) {
          UIPreviewDetailUnsubscribeScene(media: movie)
        },

        // MARK: 订阅面板

        .page(
          id: "detail.subscribeQuick",
          title: "订阅面板 · 可订阅",
          note: "新增订阅的快速面板；点「订阅」会真实执行创建→暂停→保存链路。"
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailNewMovieSubscription(),
            isNewSubscription: true
          )
        },
        .page(
          id: "detail.subscribeSubscribed",
          title: "订阅面板 · 已订阅",
          note: "编辑已订阅条目：左栏固定信息、右侧设置项与保存按钮。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "subscribed"])
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailMovieSubscription(state: "R"),
            isNewSubscription: false,
            autoLoad: true
          )
        },
        .page(
          id: "detail.subscribePaused",
          title: "订阅面板 · 已暂停",
          note: "编辑暂停中的订阅，状态文案显示已暂停，仍可修改设置并保存。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "paused"])
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailMovieSubscription(state: "S"),
            isNewSubscription: false,
            autoLoad: true
          )
        },
        .page(
          id: "detail.subscribeSubmitting",
          title: "订阅面板 · 提交中",
          note: "自动加载后立即保存；保存接口挂起，主按钮保持提交中。",
          behaviors: [UIPreviewBehaviorKey.detailSaveSubscription: .hang]
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailNewMovieSubscription(),
            isNewSubscription: true,
            autoLoad: true,
            autoSave: true
          )
        },
        .page(
          id: "detail.subscribeFailure",
          title: "订阅面板 · 提交失败",
          note: "自动加载后保存失败，面板在按钮上方显示失败原因。",
          behaviors: [UIPreviewBehaviorKey.detailSaveSubscription: .failure]
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailNewMovieSubscription(),
            isNewSubscription: true,
            autoLoad: true,
            autoSave: true
          )
        },

        // MARK: 字幕

        .page(
          id: "detail.subtitleDownload",
          title: "详情 · 字幕下载面板",
          note: "真实字幕下载面板：保存路径来自目录 fixture，可提交并由 fixture 返回成功。"
        ) {
          UIPreviewSubtitleDownloadScene(
            request: SubtitleSearchRequest(
              kind: .media(
                source: "themoviedb", mediaId: "90101", type: "电影", season: nil, episode: nil),
              sites: nil,
              displayTitle: "荒原长路",
              mediaInfo: movie
            ),
            subtitle: UIPreviewFixtures.detailSubtitleResult
          )
        },

        // MARK: 分季管理

        .page(
          id: "season.manager",
          title: "详情 · 分季选择",
          note: "分季管理页：标准 3 季、入库状态徽标、逐季订阅按钮。"
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerSubscribed",
          title: "详情 · 分季已订阅",
          note: "S1 已订阅、S2 已暂停；逐季按钮显示对应订阅状态。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.seasonSubscriptions: "1"])
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerFailure",
          title: "详情 · 分季加载失败",
          note: "分季接口失败，页面展示错误与重试，不影响从详情页其他入口继续浏览。",
          behaviors: [UIPreviewBehaviorKey.detailSeasons: .failure]
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerEpisodeGroup",
          title: "详情 · 分季页剧集组",
          note: "以播出顺序剧集组打开分季页，观察组名、组内季号与重新拉取后的列表。"
        ) {
          UIPreviewSeasonManagerScene(
            media: tv,
            initialEpisodeGroup: "preview-alt"
          )
        },

        // MARK: 合集

        .page(
          id: "detail.collection",
          title: "详情 · 合集详情页",
          note: "合集跳转的目标页：从卡片点按合集进入的真实合集详情页，合集内 6 部作品，继续向下可触发下一页。"
        ) {
          UIPreviewCollectionScene(
            title: "边境信号 · 系列合集",
            collectionId: 77_001
          )
        },
        .page(
          id: "detail.collectionLoadMore",
          title: "详情 · 合集加载更多",
          note: "第一页已加载，合集第二页延迟返回；焦点移到列表末尾观察加载占位。",
          behaviors: [UIPreviewBehaviorKey.detailCollectionMore: .delayed(seconds: 1)]
        ) {
          UIPreviewCollectionScene(
            title: "边境信号 · 系列合集",
            collectionId: 77_001
          )
        },

        // MARK: 人物

        .page(
          id: "detail.person",
          title: "详情 · 人物详情页",
          note: "真实人物页：头像、简介、作品列表第一页。"
        ) {
          UIPreviewPersonDetailScene(person: detailPerson)
        },
        .page(
          id: "detail.personWorks",
          title: "详情 · 人物作品列表",
          note: "人物页作品分页：第一页 10 部，第二页延迟返回，焦点移到末尾触发。",
          behaviors: [UIPreviewBehaviorKey.detailPersonCreditsMore: .delayed(seconds: 1)]
        ) {
          UIPreviewPersonDetailScene(person: detailPerson)
        },

        // MARK: 详情主体错误

        .page(
          id: "detail.failureTimeout",
          title: "详情 · 请求超时（自动重试）",
          note: "详情接口超时：加载页先显示「重试加载中……（第 N 次）」自动重试；预览场景不在导航栈内，约 3 次后停到「无法加载详情，请返回后重试」，可观察重试次数递增到终态。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureOffline",
          title: "详情 · 断网（自动重试）",
          note: "详情接口断网：与超时一样先自动重试并显示重试次数；预览场景约 3 次后停到「无法加载详情，请返回后重试」（真实导航栈内会持续重试）。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.networkOffline)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureGateway503",
          title: "详情 · 网关 503（自动重试）",
          note: "详情接口返回 503：按可重试错误重试，加载页显示「重试加载中……（第 N 次）」；预览场景约 3 次后停到「无法加载详情，请返回后重试」。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.gateway(503))]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureHTTP500",
          title: "详情 · HTTP 500（终态）",
          note: "详情接口返回 500：不可重试，加载页停在「无法加载详情（HTTP 500），请返回后重试」；页面没有重试按钮。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.http(500))]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureHTTP403",
          title: "详情 · HTTP 403（终态）",
          note: "详情接口返回 403：不可重试，加载页显示「无法加载详情（HTTP 403），请返回后重试」；可确认权限错误不会触发自动重试。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.http(403))]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureDecoding",
          title: "详情 · 响应解析失败（终态）",
          note: "详情接口返回无法解析的数据：加载页显示「无法加载详情（响应解析失败），请返回后重试」，不自动重试。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.decoding)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureUnauthorized",
          title: "详情 · 登录失效（终态）",
          note: "详情接口返回未授权：加载页显示「无法加载详情（登录已失效），请返回后重试」；不会自动重试。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.unauthorized)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureServerMessage",
          title: "详情 · 后端业务错误（终态）",
          note: "详情接口返回带 message 的业务错误：加载页把后端原文拼进「无法加载详情（…），请返回后重试」，可检查长文案截断与排版。",
          behaviors: [
            UIPreviewBehaviorKey.detailMediaDetail:
              .error(.serverMessage("媒体信息不存在或已被删除，请返回列表刷新后重试"))
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureInvalidURL",
          title: "详情 · 请求地址无效（终态）",
          note: "详情请求的 URL 无效：加载页显示「无法加载详情（无效的请求地址），请返回后重试」，不自动重试。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.invalidURL)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.failureUnknown",
          title: "详情 · 未知错误（终态）",
          note: "详情接口抛出未知错误：加载页显示「无法加载详情（未知错误），请返回后重试」；用于核对未分类错误的最终文案。",
          behaviors: [UIPreviewBehaviorKey.detailMediaDetail: .error(.unknown)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },

        // MARK: 第二页行失败

        .page(
          id: "detail.recommendFailure",
          title: "详情 · 推荐行首屏失败",
          note: "推荐接口首屏失败：整行直接不渲染，页面显示后续相似、演职员、豆瓣行；行内没有错误文案或重试入口。",
          behaviors: [UIPreviewBehaviorKey.detailRecommendations: .error(.serverMessage("推荐接口不可用"))]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.similarFailure",
          title: "详情 · 相似行首屏失败",
          note: "相似接口首屏失败：相似行静默消失，推荐等其它行不受影响；确认失败不会渲染空行或错误卡。",
          behaviors: [UIPreviewBehaviorKey.detailSimilar: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.actorsFailureCrewFallback",
          title: "详情 · 演员失败后只剩导演",
          note: "演员首屏失败但详情自带导演：演职员行退化为只剩「导演」职员分类，没有错误提示；用于确认真实降级效果。",
          behaviors: [UIPreviewBehaviorKey.detailActors: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.rowsPartialFailure",
          title: "详情 · 行首屏部分失败",
          note: "推荐与演员同时失败、相似正常：推荐行静默消失，演职员行退化为只剩导演（职员）分类，相似行照常显示；验证单行失败不会拖垮整页。",
          behaviors: [
            UIPreviewBehaviorKey.detailRecommendations: .error(.serverMessage("推荐接口不可用")),
            UIPreviewBehaviorKey.detailActors: .error(.networkTimeout),
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.recommendLoadMoreFailure",
          title: "详情 · 推荐行加载更多失败",
          note: "推荐首屏 6 条正常；焦点移到行尾触发第二页失败后停在 6 条，没有错误提示或重试按钮；连续失败达上限后不再自动请求。",
          behaviors: [UIPreviewBehaviorKey.detailRecommendationsMore: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.similarLoadMoreFailure",
          title: "详情 · 相似行加载更多失败",
          note: "相似首屏 5 条正常；焦点移到最后一张触发下一页失败，静默停在 5 条，无加载指示、错误文案或重试入口。",
          behaviors: [UIPreviewBehaviorKey.detailSimilarMore: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.actorsLoadMoreFailure",
          title: "详情 · 演职员加载更多失败",
          note: "演职员首屏 8 位正常；焦点移到最后一位触发下一页失败后停止加载，不显示错误；可确认分页失败没有 UI 反馈。",
          behaviors: [UIPreviewBehaviorKey.detailActorsMore: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },

        // MARK: 分季与剧集失败

        .page(
          id: "season.managerTimeout",
          title: "分季管理 · 请求超时",
          note: "分季接口超时：页面显示「分季信息加载失败」与「重试」，顶部同时出现错误通知；重试仍会失败，用于检查错误态排版。",
          behaviors: [UIPreviewBehaviorKey.detailSeasons: .error(.networkTimeout)]
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerUnauthorized",
          title: "分季管理 · 登录失效",
          note: "分季接口返回未授权：错误卡与「重试」不变，顶部通知显示「登录已失效」；确认登录失效不会把页面留在无限加载。",
          behaviors: [UIPreviewBehaviorKey.detailSeasons: .error(.unauthorized)]
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerServerMessage",
          title: "分季管理 · 后端业务错误",
          note: "分季接口返回业务错误：错误卡仍为通用「分季信息加载失败」，具体后端文案只在顶部通知里出现；用于核对两处文案差异。",
          behaviors: [
            UIPreviewBehaviorKey.detailSeasons:
              .error(.serverMessage("媒体信息不存在或已被删除"))
          ]
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "season.managerSubscriptionsFailure",
          title: "分季管理 · 订阅汇总失败",
          note: "分季列表正常、订阅汇总接口失败：季卡仍可浏览但全部显示「订阅」，顶部出现错误通知；确认部分失败不会阻断分季加载。",
          environment: detailEnvironment(context: [
            UIPreviewDetailContext.seasonSubscriptions: "1"
          ]),
          behaviors: [UIPreviewBehaviorKey.detailSubscriptions: .error(.unauthorized)]
        ) {
          UIPreviewSeasonManagerScene(media: tv)
        },
        .page(
          id: "detail.episodesFailure",
          title: "详情 · 剧集列表加载失败",
          note: "电视剧第二页剧集接口失败：剧集行显示「剧集加载失败」状态卡与「重试」，分季行仍正常；没有整页错误。",
          behaviors: [UIPreviewBehaviorKey.detailEpisodes: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },
        .page(
          id: "detail.seasonsLookupFailure",
          title: "详情 · 分季回查失败",
          note: "详情没有返回 season_info，剧集行回查分季失败：显示「分季信息加载失败」+「重试分季」，头部订阅按钮变「暂无分季信息」。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.emptySeasons: "1"]),
          behaviors: [UIPreviewBehaviorKey.detailSeasons: .error(.unauthorized)]
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },
        .page(
          id: "detail.episodeGroupSeasonsFailure",
          title: "详情 · 剧集组分季读取失败",
          note: "剧集组模式下读取组内分季失败：头部订阅按钮变「分季信息加载失败」，剧集行显示分季失败状态卡；确认不会静默回退官方季。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.episodeGroup: "1"]),
          behaviors: [
            UIPreviewBehaviorKey.detailGroupSeasons:
              .error(.serverMessage("剧集组不存在或已被删除"))
          ]
        ) {
          UIPreviewDetailSceneRoot(media: tv)
        },

        // MARK: 订阅写操作失败

        .page(
          id: "detail.subscribeAddBusinessFailure",
          title: "订阅面板 · 新建后暂停失败",
          note: "自动加载并创建新订阅，随后暂停接口返回业务失败：面板在按钮上方显示后端文案并给「重试」，可继续重试加载。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.pauseFailure: "1"])
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailNewMovieSubscription(),
            isNewSubscription: true,
            autoLoad: true
          )
        },
        .page(
          id: "detail.subscribeSaveBusinessFailure",
          title: "订阅面板 · 保存被拒绝",
          note: "打开已有订阅并自动保存，保存接口返回业务失败：面板显示后端原因与「重试」；用于核对保存失败不会被当成成功关闭。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.saveRejected: "1"])
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailMovieSubscription(state: "R"),
            isNewSubscription: false,
            autoLoad: true,
            autoSave: true
          )
        },
        .page(
          id: "detail.subscribeResumeFailure",
          title: "订阅面板 · 保存后启用失败",
          note: "新建→暂停→保存都成功，最后启用接口返回业务失败：面板显示文案并允许重试；订阅已保存，只是没有启用。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.resumeFailure: "1"])
        ) {
          UIPreviewSubscribePanelScene(
            subscribe: UIPreviewFixtures.detailNewMovieSubscription(),
            isNewSubscription: true,
            autoLoad: true,
            autoSave: true
          )
        },
        .page(
          id: "detail.subscriptionLookupFailure",
          title: "详情 · 订阅状态查询失败",
          note: "订阅状态查询接口失败：头部静默回退为「订阅」，没有任何错误提示；实际已订阅的状态不会显示。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "subscribed"]),
          behaviors: [UIPreviewBehaviorKey.detailSubscriptionLookup: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.unsubscribeFailure",
          title: "详情 · 取消订阅失败通知",
          note: "删除订阅接口失败时生产页面弹出的顶部错误条；这里用同一文案与已订阅详情作背景，确认通知条位置与可读性。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.subscription: "subscribed"])
        ) {
          UIPreviewBannerHost(
            type: .error,
            message: SubscriptionCancelConfirmation.failureMessage
          ) {
            UIPreviewDetailSceneRoot(media: movie)
          }
        },

        // MARK: 字幕下载失败

        .page(
          id: "detail.subtitleDownloadNoPermission",
          title: "字幕面板 · 无搜索权限",
          note: "账号没有搜索权限：面板显示「当前账号没有搜索权限，无法下载字幕。」，设置不可编辑，主按钮变为「关闭」，不能重试。",
          environment: UIPreviewEnvironment.limited(permissions: [.discovery])
        ) {
          UIPreviewSubtitleDownloadScene(
            request: SubtitleSearchRequest(
              kind: .media(
                source: "themoviedb", mediaId: "90101", type: "电影", season: nil, episode: nil),
              sites: nil,
              displayTitle: "荒原长路",
              mediaInfo: movie
            ),
            subtitle: UIPreviewFixtures.detailSubtitleResult
          )
        },
        .page(
          id: "detail.subtitleDownloadDirectoriesFailure",
          title: "字幕面板 · 保存路径读取失败",
          note: "保存路径接口失败：面板在「下载」上方显示错误并提供「重试」，路径选择只剩「自动」；字幕信息仍可查看。",
          behaviors: [UIPreviewBehaviorKey.detailDownloadDirectories: .error(.networkTimeout)]
        ) {
          UIPreviewSubtitleDownloadScene(
            request: SubtitleSearchRequest(
              kind: .media(
                source: "themoviedb", mediaId: "90101", type: "电影", season: nil, episode: nil),
              sites: nil,
              displayTitle: "荒原长路",
              mediaInfo: movie
            ),
            subtitle: UIPreviewFixtures.detailSubtitleResult
          )
        },
        .page(
          id: "detail.subtitleDownloadSubmitting",
          title: "字幕面板 · 下载中",
          note: "打开后自动提交，下载接口一直不返回：主按钮显示「下载中」且不可再点，设置整块禁用；用于核对提交中的禁用态。",
          behaviors: [UIPreviewBehaviorKey.detailDownloadSubtitle: .hang]
        ) {
          UIPreviewSubtitleDownloadScene(
            request: SubtitleSearchRequest(
              kind: .media(
                source: "themoviedb", mediaId: "90101", type: "电影", season: nil, episode: nil),
              sites: nil,
              displayTitle: "荒原长路",
              mediaInfo: movie
            ),
            subtitle: UIPreviewFixtures.detailSubtitleResult,
            autoSubmit: true
          )
        },
        .page(
          id: "detail.subtitleDownloadFailure",
          title: "字幕面板 · 下载接口失败",
          note: "打开后自动提交，下载接口返回业务错误：面板显示后端原文并允许修改后重试；不会关闭面板或假装成功。",
          behaviors: [
            UIPreviewBehaviorKey.detailDownloadSubtitle:
              .error(.serverMessage("保存路径不可写，请检查挂载"))
          ]
        ) {
          UIPreviewSubtitleDownloadScene(
            request: SubtitleSearchRequest(
              kind: .media(
                source: "themoviedb", mediaId: "90101", type: "电影", season: nil, episode: nil),
              sites: nil,
              displayTitle: "荒原长路",
              mediaInfo: movie
            ),
            subtitle: UIPreviewFixtures.detailSubtitleResult,
            autoSubmit: true
          )
        },

        // MARK: TMDB / 合集 / 人物失败

        .page(
          id: "detail.tmdbRecognizeFailure",
          title: "详情 · TMDB 识别失败",
          note: "外部来源详情点 TMDB 按钮时识别接口失败：只写日志，不弹提示也不跳转，加载遮罩短暂出现后恢复；确认与「未识别」空结果不是同一条路径。",
          behaviors: [UIPreviewBehaviorKey.detailRecognizeTmdb: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: externalMovie)
        },
        .page(
          id: "detail.tmdbNotFound",
          title: "详情 · TMDB 未识别到匹配",
          note:
            "识别接口正常返回空结果（不是失败）：点按 TMDB 后等识别结束，弹「未找到匹配」提示，不跳转；与上一场景的接口失败区分。",
          behaviors: [UIPreviewBehaviorKey.detailRecognizeTmdb: .empty]
        ) {
          UIPreviewDetailSceneRoot(media: externalMovie)
        },
        .page(
          id: "detail.collectionFailure",
          title: "合集 · 首屏加载失败",
          note: "合集详情接口失败与空合集都只渲染「暂无数据」，没有错误文案或重试按钮；用于锁定当前真实行为。",
          behaviors: [UIPreviewBehaviorKey.detailCollection: .error(.decoding)]
        ) {
          UIPreviewCollectionScene(title: "边境信号 · 系列合集", collectionId: 77_001)
        },
        .page(
          id: "detail.collectionLoadMoreFailure",
          title: "合集 · 加载更多失败",
          note: "合集首屏 6 部正常；列表末尾触发第二页失败后静默停在 6 部，没有加载失败提示或重试入口。",
          behaviors: [UIPreviewBehaviorKey.detailCollectionMore: .error(.networkTimeout)]
        ) {
          UIPreviewCollectionScene(title: "边境信号 · 系列合集", collectionId: 77_001)
        },
        .page(
          id: "detail.personDetailFailure",
          title: "人物 · 详情接口失败",
          note: "人物详情接口失败只写日志：头像与姓名仍显示入口数据，简介保留入口自带内容（入口无简介时显示「暂无简介」），作品列表继续加载。",
          behaviors: [UIPreviewBehaviorKey.detailPerson: .error(.unauthorized)]
        ) {
          UIPreviewPersonDetailScene(person: detailPerson)
        },
        .page(
          id: "detail.personCreditsFailure",
          title: "人物 · 作品首屏失败",
          note: "人物作品接口首屏失败：作品网格显示「暂无数据」，没有错误文案或重试；人物简介不受影响。",
          behaviors: [UIPreviewBehaviorKey.detailPersonCredits: .error(.networkTimeout)]
        ) {
          UIPreviewPersonDetailScene(person: detailPerson)
        },
        .page(
          id: "detail.personCreditsLoadMoreFailure",
          title: "人物 · 作品加载更多失败",
          note: "人物作品首屏 10 部正常；焦点移到末尾触发第二页失败后停在 10 部，无提示、无重试。",
          behaviors: [UIPreviewBehaviorKey.detailPersonCreditsMore: .error(.networkTimeout)]
        ) {
          UIPreviewPersonDetailScene(person: detailPerson)
        },

        // MARK: 豆瓣空态与失败

        .page(
          id: "detail.doubanCommentsEmpty",
          title: "豆瓣 · 短评为空",
          note: "短评首屏返回空：页面自动切到「影评」分类并显示影评内容；确认空短评不会留下空白区块。",
          behaviors: [UIPreviewBehaviorKey.detailDoubanComments: .empty]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanCommentsFailure",
          title: "豆瓣 · 短评加载失败",
          note: "短评首屏失败：区块显示「短评加载失败」状态卡与「重试」，不会自动切到影评；可切分类查看互不影响。",
          behaviors: [UIPreviewBehaviorKey.detailDoubanComments: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanReviewsEmpty",
          title: "豆瓣 · 影评为空",
          note: "短评正常；手动切到「影评」后显示「暂无影评」状态卡，不会自动切回短评；用于核对空分类的占位。",
          behaviors: [UIPreviewBehaviorKey.detailDoubanReviews: .empty]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanReviewsFailure",
          title: "豆瓣 · 影评加载失败",
          note: "短评正常；切到「影评」后首屏失败，显示「影评加载失败」与「重试」，短评数据不受影响。",
          behaviors: [
            UIPreviewBehaviorKey.detailDoubanReviews:
              .error(.serverMessage("豆瓣影评接口暂不可用"))
          ]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanCommentsLoadMoreFailure",
          title: "豆瓣 · 短评加载更多失败",
          note: "短评首屏 3 条、总数 13（胶囊显示「短评 13」）；焦点移到最后一张触发下一页失败，行尾出现「重试」按钮，已有 3 条保留。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.doubanPagination: "1"]),
          behaviors: [UIPreviewBehaviorKey.detailDoubanCommentsMore: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
        .page(
          id: "detail.doubanReviewsLoadMoreFailure",
          title: "豆瓣 · 影评加载更多失败",
          note: "先切到「影评」：首屏 2 条、总数 12；焦点移到最后一张触发下一页失败，行尾出现「重试」，短评分区不受影响。",
          environment: detailEnvironment(context: [UIPreviewDetailContext.doubanPagination: "1"]),
          behaviors: [UIPreviewBehaviorKey.detailDoubanReviewsMore: .error(.networkTimeout)]
        ) {
          UIPreviewDetailSceneRoot(media: movie)
        },
      ]
    )
  }

  private static var detailPerson: Person {
    UIPreviewFixtures.person(
      id: 71_001,
      name: "周野",
      biography:
        "周野，电影导演、编剧。早年拍摄纪录短片，关注公路、迁徙与通信基础设施。长片处女作《荒原长路》以极简对白和大量环境声获得关注，之后继续在类型片框架里讨论人与距离。"
    )
  }

  private static func detailPlaybackEnvironment(context: [String: String]) -> UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.playback
    environment.context = context
    return environment
  }

  private static func detailEnvironment(
    context: [String: String],
    permissions: Set<UserPermissionKey>? = nil
  ) -> UIPreviewEnvironment {
    var environment =
      permissions.map { UIPreviewEnvironment.limited(permissions: $0) } ?? .standard
    environment.context = context
    return environment
  }
}

// MARK: - 详情页根视图

/// 详情页预览根视图：不经过 `MainContentView`，但补齐它平时注入的环境对象，
/// 并使用与线上相同的 `NavigationStack(path:)` + `ImageNavigationDestination`，
/// 让 TMDB、人物、合集等 push 在预览里也能真实发生。
@MainActor
private struct UIPreviewDetailSceneRoot: View {
  private let media: MediaInfo
  private let presentationStyle: MediaDetailPresentationStyle
  @StateObject private var coordinator = ImageNavigationCoordinator()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @State private var preloadTask: MediaPreloadTask

  init(media: MediaInfo, presentationStyle: MediaDetailPresentationStyle = .standard) {
    self.media = media
    self.presentationStyle = presentationStyle
    _preloadTask = State(
      initialValue: APIService.shared.mediaPreloader.preload(for: media)
    )
  }

  var body: some View {
    NavigationStack(path: $coordinator.path) {
      MediaDetailContainerView(
        media: media,
        preloadTask: preloadTask,
        routeID: coordinator.rootLifecycle.id,
        imageLifecycle: coordinator.rootLifecycle,
        presentationStyle: presentationStyle,
        allowsRequests: true
      )
      .environment(\.pageImageLifecycle, coordinator.rootLifecycle)
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .withNotification()
    .environmentObject(coordinator)
    .environmentObject(mediaActionHandler)
  }
}

/// 取消订阅确认：`MediaDetailView` 的确认弹窗由私有 State 驱动，无法通过接口行为触发，
/// 这里复用生产环境的文案与按钮标题，直接把同一个确认内容展示出来。
@MainActor
private struct UIPreviewDetailUnsubscribeScene: View {
  let media: MediaInfo
  @State private var isPresented = true

  var body: some View {
    UIPreviewDetailSceneRoot(
      media: media,
      presentationStyle: .standard
    )
    .alert(SubscriptionCancelConfirmation.title, isPresented: $isPresented) {
      Button(SubscriptionCancelConfirmation.confirmButtonTitle, role: .destructive) {
        isPresented = false
      }
      Button("取消", role: .cancel) {
        isPresented = false
      }
    } message: {
      Text(SubscriptionCancelConfirmation.headerMessage(for: media))
    }
  }
}

// MARK: - 订阅面板

@MainActor
private struct UIPreviewSubscribePanelScene: View {
  private let autoLoad: Bool
  private let autoSave: Bool
  @StateObject private var viewModel: SubscribeSheetViewModel

  init(
    subscribe: Subscribe,
    isNewSubscription: Bool,
    autoLoad: Bool = false,
    autoSave: Bool = false
  ) {
    _viewModel = StateObject(
      wrappedValue: SubscribeSheetViewModel(
        subscribe: subscribe,
        isNewSubscription: isNewSubscription
      )
    )
    self.autoLoad = autoLoad
    self.autoSave = autoSave
  }

  var body: some View {
    UIPreviewSheetHost {
      SubscribePanel(
        viewModel: viewModel,
        isSaving: viewModel.isSaving,
        onSubscribe: startSubscribing
      )
      .task { await prepare() }
    }
  }

  private func prepare() async {
    guard autoLoad else { return }
    let loaded = await viewModel.loadData()
    guard loaded, autoSave else { return }
    _ = await viewModel.save()
  }

  private func startSubscribing() {
    Task {
      guard await viewModel.loadData() else { return }
      _ = await viewModel.save()
    }
  }
}

// MARK: - 字幕下载

@MainActor
private struct UIPreviewSubtitleDownloadScene: View {
  @StateObject private var viewModel: SubtitleDownloadViewModel
  private let autoSubmit: Bool

  init(request: SubtitleSearchRequest, subtitle: SubtitleInfo, autoSubmit: Bool = false) {
    _viewModel = StateObject(
      wrappedValue: SubtitleDownloadViewModel(
        subtitle: subtitle,
        request: request,
        bindsCurrentMedia: true
      )
    )
    self.autoSubmit = autoSubmit
  }

  var body: some View {
    UIPreviewSheetHost {
      SubtitleDownloadSheet(viewModel: viewModel)
        .task {
          guard autoSubmit else { return }
          try? await Task.sleep(for: .seconds(1))
          viewModel.submit()
        }
    }
  }
}

// MARK: - 分季管理

@MainActor
private struct UIPreviewSeasonManagerScene: View {
  private let media: MediaInfo
  private let initialSeason: Int?
  private let initialEpisodeGroup: String?
  @StateObject private var coordinator = ImageNavigationCoordinator()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @StateObject private var lifecycle = PageImageLifecycle()

  init(
    media: MediaInfo,
    initialSeason: Int? = nil,
    initialEpisodeGroup: String? = nil
  ) {
    self.media = media
    self.initialSeason = initialSeason
    self.initialEpisodeGroup = initialEpisodeGroup
  }

  var body: some View {
    NavigationStack(path: $coordinator.path) {
      SubscribeSeasonView(
        mediaInfo: media,
        initialSeason: initialSeason,
        initialEpisodeGroup: initialEpisodeGroup,
        imageLifecycle: lifecycle
      )
      .environment(\.pageImageLifecycle, lifecycle)
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .withNotification()
    .environmentObject(coordinator)
    .environmentObject(mediaActionHandler)
  }
}

// MARK: - 合集

@MainActor
private struct UIPreviewCollectionScene: View {
  private let title: String
  private let collectionId: Int
  @StateObject private var coordinator = ImageNavigationCoordinator()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @StateObject private var lifecycle = PageImageLifecycle()

  init(title: String, collectionId: Int) {
    self.title = title
    self.collectionId = collectionId
  }

  var body: some View {
    NavigationStack(path: $coordinator.path) {
      CollectionDetailView(
        title: title,
        collectionId: collectionId,
        imageLifecycle: lifecycle
      )
      .environment(\.pageImageLifecycle, lifecycle)
      .navigationDestination(for: ImageNavigationEntry.self) { entry in
        ImageNavigationDestination(entry: entry)
      }
    }
    .withNotification()
    .environmentObject(coordinator)
    .environmentObject(mediaActionHandler)
  }
}

// MARK: - 人物

@MainActor
private struct UIPreviewPersonDetailScene: View {
  private let person: Person
  @StateObject private var coordinator = ImageNavigationCoordinator()
  @StateObject private var mediaActionHandler = MediaActionHandler()
  @StateObject private var lifecycle = PageImageLifecycle()

  init(person: Person) {
    self.person = person
  }

  var body: some View {
    NavigationStack(path: $coordinator.path) {
      PersonDetailView(person: person, imageLifecycle: lifecycle)
        .environment(\.pageImageLifecycle, lifecycle)
        .navigationDestination(for: ImageNavigationEntry.self) { entry in
          ImageNavigationDestination(entry: entry)
        }
    }
    .withNotification()
    .environmentObject(coordinator)
    .environmentObject(mediaActionHandler)
  }
}

// MARK: - 豆瓣阅读

@MainActor
private struct UIPreviewReadingScene: View {
  let entry: DoubanDiscussionEntry

  var body: some View {
    UIPreviewSheetHost {
      DoubanDiscussionDetailSheet(entry: entry, avatarURL: nil)
    }
  }
}
#endif
