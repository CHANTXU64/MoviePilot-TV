import Combine
import Foundation
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
  /// 媒体服务器最近播放/新增的项目
  @Published var latestMedia: [MediaServerPlayItem] = []
  /// 电影订阅列表
  @Published var movieSubscriptions: [Subscribe] = []
  /// 电视剧订阅列表
  @Published var tvSubscriptions: [Subscribe] = []
  /// 加载状态
  @Published var isLoading = true

  private let apiService: APIService

  init(apiService: APIService? = nil) {
    self.apiService = apiService ?? APIService.shared
  }

  /// 初始或刷新加载数据
  func loadData() async {
    // 仅在首次加载（无数据时）显示全屏 Loading
    let isFirstLoad = latestMedia.isEmpty && movieSubscriptions.isEmpty && tvSubscriptions.isEmpty
    if isFirstLoad {
      isLoading = true
    }

    await refreshData()

    if isFirstLoad {
      isLoading = false
    }
  }

  /// 刷新首页数据
  func refreshData() async {
    // 采用 TaskGroup 并发加载首页的两大板块：最近播放和我的订阅，提升首屏响应速度
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadLatestMedia() }
      group.addTask { await self.loadSubscriptions() }
    }
  }

  /// 从已启用的媒体服务器加载最近媒体
  private func loadLatestMedia() async {
    do {
      // 1. 获取所有配置的媒体服务器（如 Jellyfin/Emby/Plex）
      let servers = try await apiService.fetchMediaServers()
      var allItems: [MediaServerPlayItem] = []

      // 2. 遍历并获取已启用服务器的“最近新增/播放”列表
      for server in servers where server.enabled?.value ?? false {
        let items = try await apiService.fetchMediaServerLatest(server: server.name)
        allItems.append(contentsOf: items)
      }

      // 注意：由于后端 API 缺少跨服务器统一的 date_added 时间戳字段，目前无法实现全局严格排序。
      // 当前逻辑是将各服务器返回的结果简单聚合展示。
      self.latestMedia = allItems
    } catch {
      print("加载最新媒体失败: \(error)")
      self.latestMedia = []
    }
  }

  /// 加载所有订阅并按电影/电视剧分类，且按 ID 倒序排列，也就是最新的在最前面
  private func loadSubscriptions() async {
    do {
      let subs = try await apiService.fetchSubscriptions()

      self.movieSubscriptions = subs.filter { $0.type == "电影" }
        .sorted { ($0.id ?? 0) > ($1.id ?? 0) }

      self.tvSubscriptions = subs.filter { $0.type == "电视剧" }
        .sorted { ($0.id ?? 0) > ($1.id ?? 0) }
    } catch {
      print("加载订阅失败: \(error)")
      self.movieSubscriptions = []
      self.tvSubscriptions = []
    }
  }

  // MARK: - 订阅操作

  /// 切换订阅状态（运行/停止）
  func toggleSubscribeStatus(subscribe: Subscribe) async -> Bool {
    guard let id = subscribe.id else { return false }
    // 前端逻辑：如果是 'S' (已停止) -> 切换到 'R' (运行)，否则 -> 'S' (停止)
    let newState = subscribe.state == "S" ? "R" : "S"
    do {
      let success = try await apiService.updateSubscriptionStatus(id: id, state: newState)
      if success {
        await loadSubscriptions()
      }
      return success
    } catch {
      print("切换订阅状态失败: \(error)")
      return false
    }
  }

  /// 重置订阅历史
  func resetSubscribe(subscribe: Subscribe) async -> Bool {
    guard let id = subscribe.id else { return false }
    do {
      let success = try await apiService.resetSubscription(id: id)
      if success {
        await loadSubscriptions()
      }
      return success
    } catch {
      print("重置订阅失败: \(error)")
      return false
    }
  }

  /// 立即触发订阅搜索
  func searchSubscribe(subscribe: Subscribe) async -> Bool {
    guard let id = subscribe.id else { return false }
    do {
      return try await apiService.searchSubscription(id: id)
    } catch {
      print("搜索订阅失败: \(error)")
      return false
    }
  }

  /// 删除订阅
  func deleteSubscribe(subscribe: Subscribe) async -> Bool {
    guard let id = subscribe.id else { return false }
    do {
      let success = try await apiService.deleteSubscription(id: id)
      if success {
        await loadSubscriptions()
      }
      return success
    } catch {
      print("删除订阅失败: \(error)")
      return false
    }
  }

  func openMediaItem(_ item: MediaServerPlayItem, using openURL: OpenURLAction) {
    guard let link = item.link, let originalUrl = URL(string: link) else { return }

    var finalUrl: URL? = nil

    // 统一处理 Fragment 解析：有些后端返回 #!/item... 有些返回 #/item...
    let cleanFragment: String? = {
      guard let fragment = originalUrl.fragment else { return nil }
      return fragment.starts(with: "!") ? String(fragment.dropFirst(1)) : fragment
    }()

    switch item.server_type {
    case .emby:
      // 如果是 Emby 服务器，则尝试构建深度链接，目前 Emby 2.0.3(2) 还不支持跳转到媒体
      // 后端链接格式: https://your-emby-server/web/index.html#!/item?id=xxxx&serverId=...
      // emby://items?serverId={your_server_id}&itemId={your_item_id}
      if let fragment = cleanFragment, let components = URLComponents(string: "https://dummy.com" + fragment) {
        let queryItems = components.queryItems ?? []
        let itemId = queryItems.first { $0.name == "id" }?.value
        let serverId = queryItems.first { $0.name == "serverId" }?.value
        if let itemId = itemId, let serverId = serverId {
          var deepLinkComponents = URLComponents()
          deepLinkComponents.scheme = "emby"
          deepLinkComponents.host = "items"
          deepLinkComponents.queryItems = [
            URLQueryItem(name: "serverId", value: serverId),
            URLQueryItem(name: "itemId", value: itemId),
          ]
          finalUrl = deepLinkComponents.url
        }
      }

    case .plex:
      // 后端链接格式: http://ip:port/web/index.html#!/media/{server_id}/com.plexapp.plugins.library?source={library.key}&X-Plex-Token={token}
      // plex://preplay/?metadataKey={metadataKey}&server={serverId}
      if let fragment = cleanFragment, let components = URLComponents(string: "https://dummy.com" + fragment) {
        let pathParts = components.path.split(separator: "/")
        if pathParts.count >= 2, pathParts[0] == "media", let rawId = item.raw_id?.value {
          let serverId = String(pathParts[1])
          let metadataKey = "/library/metadata/\(rawId)"

          var deepLinkComponents = URLComponents()
          deepLinkComponents.scheme = "plex"
          deepLinkComponents.host = "preplay"
          deepLinkComponents.path = "/"
          deepLinkComponents.queryItems = [
            URLQueryItem(name: "metadataKey", value: metadataKey),
            URLQueryItem(name: "server", value: serverId),
          ]
          finalUrl = deepLinkComponents.url
        }
      }
      // 降级策略
      if finalUrl == nil { finalUrl = URL(string: "plex://") }

    case .jellyfin:
      print("Jellyfin 暂不支持在 tvOS 打开媒体")
    case .trimemedia:
      print("飞牛 Nas 暂不支持在 tvOS 打开媒体")
    case .ugreen:
      print("绿联 Nas 暂不支持在 tvOS 打开媒体")
    default:
      // 处理未来未知的服务器类型（item.server_type.rawValue）
      print("未知的媒体服务器类型: \(item.server_type?.rawValue ?? "未知")，且 tvOS 无法直接打开网页")
    }

    if let finalUrl = finalUrl {
      openURL(finalUrl) { accepted in
        print(accepted ? "成功打开深度链接: \(finalUrl)" : "无法打开深度链接: \(finalUrl)")
      }
    } else if let serverType = item.server_type {
      print("未能生成 \(serverType.rawValue) 的有效深度链接: \(originalUrl)")
    }
  }
}
