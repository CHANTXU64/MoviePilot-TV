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
          note: "订阅状态命中且媒体服务器存在条目，头部显示「已订阅（已入库）」。",
          environment: detailEnvironment(context: [
            UIPreviewDetailContext.subscription: "subscribed",
            UIPreviewDetailContext.libraryItem: "1",
          ])
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
    UIPreviewPageHost {
      VStack {
        SubscribePanel(
          viewModel: viewModel,
          isSaving: viewModel.isSaving,
          onSubscribe: startSubscribing
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(80)
      .background(Color(white: 0.08).ignoresSafeArea())
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

  init(request: SubtitleSearchRequest, subtitle: SubtitleInfo) {
    _viewModel = StateObject(
      wrappedValue: SubtitleDownloadViewModel(
        subtitle: subtitle,
        request: request,
        bindsCurrentMedia: true
      )
    )
  }

  var body: some View {
    UIPreviewPageHost {
      SubtitleDownloadSheet(viewModel: viewModel)
        .background(Color(white: 0.08).ignoresSafeArea())
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
    UIPreviewPageHost {
      DoubanDiscussionDetailSheet(entry: entry, avatarURL: nil)
    }
  }
}
#endif
