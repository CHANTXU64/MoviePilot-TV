import SwiftUI

struct MediaContextMenuItems: View {
  let item: MediaInfo
  @Binding var navigationPath: NavigationPath
  @ObservedObject var subscriptionHandler: SubscriptionHandler
  @EnvironmentObject var mediaActionHandler: MediaActionHandler

  // 可选的自定义订阅操作
  var onSubscribe: ((MediaInfo) -> Void)? = nil

  var body: some View {
    Button {
      // 点击"详情"时立即触发预加载
      MediaPreloader.shared.preload(for: item)
      navigationPath.append(item)
    } label: {
      Label("详情", systemImage: "info.circle")
    }

    if item.collection_id == nil {
      // TMDB 详情页：复用 MediaActionHandler 逻辑，点击时实时获取/识别 TMDB ID
      // 不依赖预加载状态，按钮永远可点，避免菜单状态不刷新的问题
      if item.douban_id != nil || item.bangumi_id != nil {
        Button {
          Task {
            // 优先传入预加载的 tmdbId，避免重复网络请求
            // ⚠️ 此处在 Button 操作中（非 body 渲染），可安全使用 getTask
            let preloadedTmdbId = MediaPreloader.shared.getTask(for: item)?.tmdbId
            if let target = await mediaActionHandler.getTMDBJumpTarget(
              for: item, targetTmdbId: preloadedTmdbId)
            {
              navigationPath.append(target)
            }
          }
        } label: {
          Label("TMDB详情页", systemImage: "link")
        }
      }

      // 订阅按钮：读取预加载的订阅状态来决定显示文本
      // ⚠️ 使用 peekTask（纯读取），避免在 body 渲染期间修改最近使用 (LRU) 状态
      let preloadedSubscribed = MediaPreloader.shared.peekTask(for: item)?.isSubscribed

      Button {
        if let onSubscribe = onSubscribe {
          onSubscribe(item)
        } else {
          subscriptionHandler.handleSubscribe(item)
        }
      } label: {
        if item.canDirectlySubscribe, let subscribed = preloadedSubscribed, subscribed {
          Label("已订阅", systemImage: "checkmark.circle.fill")
        } else {
          Label(
            item.canDirectlySubscribe ? "订阅" : "分季订阅",
            systemImage: item.canDirectlySubscribe ? "plus.circle" : "list.bullet.circle")
        }
      }

      Button {
        let request = mediaActionHandler.searchResourcesTarget(for: item)
        navigationPath.append(request)
      } label: {
        Label("搜索资源", systemImage: "magnifyingglass")
      }
    }
  }
}

struct MediaContextMenu: ViewModifier {
  let item: MediaInfo
  @Binding var navigationPath: NavigationPath
  @ObservedObject var subscriptionHandler: SubscriptionHandler

  // 可选的自定义订阅操作
  var onSubscribe: ((MediaInfo) -> Void)? = nil

  func body(content: Content) -> some View {
    content
      .compositingGroup()
      .contextMenu {
        MediaContextMenuItems(
          item: item,
          navigationPath: $navigationPath,
          subscriptionHandler: subscriptionHandler,
          onSubscribe: onSubscribe
        )
      }
  }
}

extension View {
  func mediaContextMenu(
    item: MediaInfo,
    navigationPath: Binding<NavigationPath>,
    subscriptionHandler: SubscriptionHandler,
    onSubscribe: ((MediaInfo) -> Void)? = nil
  ) -> some View {
    self.modifier(
      MediaContextMenu(
        item: item,
        navigationPath: navigationPath,
        subscriptionHandler: subscriptionHandler,
        onSubscribe: onSubscribe
      )
    )
  }
}
