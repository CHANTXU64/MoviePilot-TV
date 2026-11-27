import SwiftUI

/// 长按菜单里「详情」之外的另一个详情入口：默认打开 TMDB 时给原来源页，
/// 否则沿用原来的 TMDB 详情页。按解析后的主来源判断，插件条目不受辅助豆瓣 ID 影响。
nonisolated enum MediaDetailMenuPolicy {
  static func alternateDetailSourceTitle(
    for item: MediaInfo,
    defaultOpenTMDBDetail: Bool
  ) -> String? {
    guard defaultOpenTMDBDetail, let source = item.identity?.source else { return nil }
    switch source {
    case "douban": return "豆瓣详情页"
    case "bangumi": return "Bangumi详情页"
    case "anilist": return "AniList详情页"
    default: return nil
    }
  }
}

struct MediaContextMenuItems: View {
  let item: MediaInfo
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @EnvironmentObject var mediaActionHandler: MediaActionHandler
  @EnvironmentObject private var navigationCoordinator: ImageNavigationCoordinator

  // 可选的自定义订阅操作
  var onSubscribe: ((MediaInfo) -> Void)? = nil

  private var canSubscribeMedia: Bool {
    APIService.shared.canAccess(.subscribe)
  }

  private var canSearchResources: Bool {
    APIService.shared.canAccess(.search)
  }

  private var usesDefaultTMDBDetail: Bool {
    SystemViewModel.shouldDefaultOpenTMDBDetail && APIService.shared.supportsTMDBRecognitionReporting
  }

  private var alternateDetailSourceTitle: String? {
    MediaDetailMenuPolicy.alternateDetailSourceTitle(
      for: item, defaultOpenTMDBDetail: usesDefaultTMDBDetail)
  }

  var body: some View {
    if canSubscribeMedia, !item.isCollection, item.type != "音乐", let share = item.subscribeShare {
      // 订阅分享的专属菜单
      Button {
        subscriptionHandler.forkSheetRequest = share
      } label: {
        Label(
          subscriptionHandler.forkCapability.unavailableHint ?? "复用订阅",
          systemImage: AppSymbol.forkSubscription)
      }
      .disabled(!subscriptionHandler.forkCapability.isAvailable)
    }

    Button {
      // 按默认详情来源打开：豆瓣、Bangumi、AniList 条目先识别 TMDB，识别不到再打开原来源页。
      let sourceToken = navigationCoordinator.sourceToken()
      Task { @MainActor in
        await mediaActionHandler.openMediaDetail(
          item,
          in: navigationCoordinator,
          sourceToken: sourceToken,
          loadingPosterURL: item.imageURLs.poster
        )
      }
    } label: {
      Label("详情", systemImage: AppSymbol.details)
    }

    if !item.isCollection {
      // 默认打开 TMDB 时，长按提供原来源详情页；关闭时仍是 TMDB 详情页。
      if let alternateDetailSourceTitle {
        Button {
          navigationCoordinator.push(item, loadingPosterURL: item.imageURLs.poster)
        } label: {
          Label(alternateDetailSourceTitle, systemImage: AppSymbol.details)
        }
      } else if item.canJumpToTMDB {
        // TMDB 详情页：复用 MediaActionHandler 逻辑，点击时实时获取/识别 TMDB ID
        // 不依赖预加载状态，按钮永远可点，避免菜单状态不刷新的问题
        Button {
          let navigationSource = navigationCoordinator.sourceToken()
          Task {
            // 优先传入预加载的映射目标或 tmdbId，避免重复网络请求
            // ⚠️ 此处在 Button 操作中（非 body 渲染），可安全使用 getTask
            let preloadTask = APIService.shared.mediaPreloader.getTask(for: item)
            let preloadedTarget = preloadTask?.tmdbTarget
            let preloadedTmdbId = MediaIdentifier.validNumericIdentifier(preloadTask?.tmdbId)
            let target: MediaInfo?
            if let preloadedTarget {
              target = preloadedTarget
            } else {
              target = await mediaActionHandler.getTMDBJumpTarget(
                for: item,
                targetTmdbId: preloadedTmdbId
              )
            }
            if let target {
              navigationCoordinator.push(
                target,
                loadingPosterURL: item.imageURLs.poster,
                ifCurrent: navigationSource
              )
            }
          }
        } label: {
          Label("TMDB详情页", systemImage: AppSymbol.link)
        }
      }

      // 订阅按钮：预加载状态只控制显示；点击后由 Handler 向后端复查
      // ⚠️ 使用 peekTask（纯读取），避免在 body 渲染期间修改预载任务生命周期状态
      let preloadedSubscribed = APIService.shared.mediaPreloader.peekTask(for: item)?.isSubscribed

      if canSubscribeMedia, item.type != "音乐" {
        Button {
          if let onSubscribe = onSubscribe {
            onSubscribe(item)
          } else {
            subscriptionHandler.handleSubscribe(
              item,
              expectedSubscribed: preloadedSubscribed == true
            )
          }
        } label: {
          if item.canDirectlySubscribe, let subscribed = preloadedSubscribed, subscribed {
            Label("已订阅", systemImage: AppSymbol.subscribed)
          } else {
            Label(
              item.canDirectlySubscribe ? "订阅" : "分季订阅",
              systemImage: item.canDirectlySubscribe ? AppSymbol.subscribe : AppSymbol.chooseSeasons)
          }
        }
      }

      if canSearchResources {
        Button {
          let navigationSource = navigationCoordinator.sourceToken()
          Task { @MainActor in
            if let request = await mediaActionHandler.searchResourcesTargetUsingDefaultSites(
              for: item
            ) {
              navigationCoordinator.push(request, ifCurrent: navigationSource)
            }
          }
        } label: {
          Label("搜索资源", systemImage: AppSymbol.search)
        }
        if SubtitleSearchRequest.supportsSubtitleSearch(item) {
          Button {
            let navigationSource = navigationCoordinator.sourceToken()
            Task { @MainActor in
              if let request = await mediaActionHandler.subtitleSearchRequestUsingDefaultSites(for: item) {
                navigationCoordinator.push(request, ifCurrent: navigationSource)
              }
            }
          } label: {
            Label("搜索字幕", systemImage: AppSymbol.searchSubtitles)
          }
        }
      }
    }
  }
}

struct MediaContextMenu: ViewModifier {
  let item: MediaInfo
  @EnvironmentObject var subscriptionHandler: SubscriptionHandler

  // 可选的自定义订阅操作
  var onSubscribe: ((MediaInfo) -> Void)? = nil

  func body(content: Content) -> some View {
    content
      .compositingGroup()
      .contextMenu {
        MediaContextMenuItems(
          item: item,
          subscriptionHandler: subscriptionHandler,
          onSubscribe: onSubscribe
        )
      }
  }
}

extension View {
  func mediaContextMenu(
    item: MediaInfo,
    onSubscribe: ((MediaInfo) -> Void)? = nil
  ) -> some View {
    self.modifier(
      MediaContextMenu(
        item: item,
        onSubscribe: onSubscribe
      )
    )
  }
}
