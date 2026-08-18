import Combine
import Foundation
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
  /// 媒体服务器最近播放/新增的项目
  @Published var latestMedia: [MediaServerPlayItem] = []
  /// 可选的媒体服务器（用于首页最近添加筛选）
  @Published var latestMediaServers: [String] = []
  /// 当前选中的媒体服务器
  @Published var selectedLatestMediaServer: String = "" {
    didSet {
      guard oldValue != selectedLatestMediaServer else { return }
      persistSelectedLatestMediaServer()
      applyLatestMediaSelection()
    }
  }
  /// 电影订阅列表
  @Published var movieSubscriptions: [Subscribe] = []
  /// 电视剧订阅列表
  @Published var tvSubscriptions: [Subscribe] = []
  /// 最近播放加载失败标记（成功空视为有效结果；失败保留旧快照并置位）
  @Published var latestLoadFailed = false
  /// 订阅加载失败标记（成功空视为有效结果；失败保留旧数组并置位）
  @Published var subscriptionsLoadFailed = false
  /// 加载状态
  @Published var isLoading = true

  private let apiService: APIService
  private var latestMediaSelectedServerKey: String? {
    apiService.profileKey.map { "home.latestMedia.selectedServer.v2_\($0)" }
  }
  private var latestMediaByServer: [String: [MediaServerPlayItem]] = [:]
  private var cancellables = Set<AnyCancellable>()

  init(apiService: APIService? = nil) {
    self.apiService = apiService ?? APIService.shared
    if let key = latestMediaSelectedServerKey {
      let defaults = UserDefaults.standard
      if defaults.object(forKey: key) == nil,
        let legacyValue = defaults.string(forKey: "home.latestMedia.selectedServer.v1")
      {
        defaults.set(legacyValue, forKey: key)
        defaults.removeObject(forKey: "home.latestMedia.selectedServer.v1")
      }
      self.selectedLatestMediaServer = defaults.string(forKey: key) ?? ""
    }

    // 监听订阅变更通知，从其他页面订阅后首页立即刷新
    NotificationCenter.default.publisher(for: .subscriptionDidUpdate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { [weak self] in
          await self?.refreshSubscriptions(forceRefresh: true)
        }
      }
      .store(in: &cancellables)
  }

  private var hasLoaded = false

  /// 初始或刷新加载数据
  func loadData() async {
    guard !hasLoaded else { return }
    hasLoaded = true

    // 仅在首次加载（无数据时）显示全屏 Loading
    let isFirstLoad = latestMedia.isEmpty && movieSubscriptions.isEmpty && tvSubscriptions.isEmpty
    if isFirstLoad {
      isLoading = true
    }

    await refreshData()

    // 页面 .task 被取消（切 Tab 等）后复位门闩，重新出现时能立即重试
    if Task.isCancelled {
      hasLoaded = false
      return
    }

    if isFirstLoad {
      isLoading = false
    }
  }

  /// 刷新首页数据
  func refreshData() async {
    // 采用 TaskGroup 并发加载首页的两大板块：最近播放和我的订阅，提升首屏响应速度
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadLatestMedia() }
      group.addTask { await self.refreshSubscriptions(forceRefresh: true) }
    }
  }

  /// 从已启用的媒体服务器加载最近媒体
  private func loadLatestMedia() async {
    guard apiService.canRequestSuperUserEndpoints else {
      latestMediaByServer = [:]
      latestMediaServers = []
      latestLoadFailed = false
      if selectedLatestMediaServer != "" { selectedLatestMediaServer = "" }
      if !latestMedia.isEmpty { latestMedia = [] }
      return
    }
    let sessionSnapshot = apiService.sessionSnapshot()

    do {
      // 1. 获取所有配置的媒体服务器（如 Jellyfin/Emby/Plex）
      let servers = try await apiService.fetchMediaServers()
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }

      // 只保留启用服务器（保持后端返回顺序）
      let enabledServers = servers.filter { $0.enabled?.value ?? false }

      // 2. 使用 TaskGroup 并发获取已启用服务器的“最近新增/播放”列表
      // 只有成功结果（含成功空）才覆盖对应服务器快照；
      // 失败保留上一轮快照并置失败标记，取消保留快照但不视为失败。
      let latestByServer = await withTaskGroup(of: (String, ServerLatestOutcome).self) {
        group in
        for server in enabledServers {
          group.addTask {
            do {
              let items = try await self.apiService.fetchMediaServerLatest(server: server.name)
              return (server.name, .success(items))
            } catch is CancellationError {
              return (server.name, .cancelled)
            } catch {
              print("加载服务器 \(server.name) 最新媒体失败: \(error)")
              return (server.name, .failed)
            }
          }
        }

        // 收集各服务器结果，仅保留成功项
        var byServer: [String: [MediaServerPlayItem]] = [:]
        var anyFailed = false
        var anyCancelled = false
        for await (serverName, outcome) in group {
          switch outcome {
          case .success(let items):
            byServer[serverName] = items
          case .failed:
            anyFailed = true
          case .cancelled:
            anyCancelled = true
          }
        }
        // 全部完成（无取消）时按结果刷新失败标记；有取消保持原值。
        if !anyCancelled {
          self.latestLoadFailed = anyFailed
        }
        return byServer
      }
      guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return }

      // 3. 更新筛选器和当前展示列表
      // 失败/取消的服务器保留上一轮快照；停用服务器随新列表移除。
      let enabledServerNames = Set(enabledServers.map(\.name))
      var nextByServer = latestMediaByServer.filter { enabledServerNames.contains($0.key) }
      for (serverName, items) in latestByServer {
        nextByServer[serverName] = items
      }
      self.latestMediaByServer = nextByServer
      let newServerNames = enabledServers.map(\.name)
      if self.latestMediaServers != newServerNames {
        self.latestMediaServers = newServerNames
      }

      if latestMediaServers.isEmpty {
        if self.selectedLatestMediaServer != "" { self.selectedLatestMediaServer = "" }
        if !self.latestMedia.isEmpty { self.latestMedia = [] }
      } else {
        if selectedLatestMediaServer.isEmpty
          || !latestMediaServers.contains(selectedLatestMediaServer)
        {
          self.selectedLatestMediaServer = latestMediaServers[0]
        }
        applyLatestMediaSelection()
      }
    } catch {
      if error is CancellationError {
        print("加载最新媒体被取消")
      } else {
        print("加载最新媒体失败: \(error)")
        latestLoadFailed = true
      }
    }
  }

  private enum ServerLatestOutcome {
    case success([MediaServerPlayItem])
    case failed
    case cancelled
  }

  private func applyLatestMediaSelection() {
    guard !selectedLatestMediaServer.isEmpty else {
      if !self.latestMedia.isEmpty { self.latestMedia = [] }
      return
    }
    let newMedia = latestMediaByServer[selectedLatestMediaServer] ?? []
    if self.latestMedia != newMedia {
      self.latestMedia = newMedia
    }
  }

  private func persistSelectedLatestMediaServer() {
    guard let key = latestMediaSelectedServerKey else { return }
    UserDefaults.standard.set(selectedLatestMediaServer, forKey: key)
  }

  /// 加载所有订阅并按电影/电视剧分类，且按 ID 倒序排列，也就是最新的在最前面
  @discardableResult
  func refreshSubscriptions(forceRefresh: Bool = false) async -> Bool {
    guard apiService.canAccess(.subscribe) else {
      if !movieSubscriptions.isEmpty { movieSubscriptions = [] }
      if !tvSubscriptions.isEmpty { tvSubscriptions = [] }
      subscriptionsLoadFailed = false
      return true
    }
    do {
      let subs = try await apiService.fetchSubscriptions(forceRefresh: forceRefresh)
      let newMovies = subs.filter { $0.type == "电影" }
        .sorted { ($0.id ?? 0) > ($1.id ?? 0) }
      if self.movieSubscriptions != newMovies {
        self.movieSubscriptions = newMovies
      }

      let newTVs = subs.filter { $0.type == "电视剧" }
        .sorted { ($0.id ?? 0) > ($1.id ?? 0) }
      if self.tvSubscriptions != newTVs {
        self.tvSubscriptions = newTVs
      }
      subscriptionsLoadFailed = false
      return true
    } catch is CancellationError {
      print("加载订阅被取消")
      return false
    } catch {
      print("加载订阅失败: \(error)")
      subscriptionsLoadFailed = true
      return false
    }
  }

  // MARK: - 订阅操作

  /// 切换订阅状态（运行/停止）
  func toggleSubscribeStatus(subscribe: Subscribe) async throws -> (
    success: Bool, message: String?
  ) {
    guard apiService.canAccess(.subscribe) else { return (false, nil) }
    guard let id = subscribe.id else { return (false, nil) }
    let sessionSnapshot = apiService.sessionSnapshot()
    // 前端逻辑：如果是 'S' (已停止) -> 切换到 'R' (运行)，否则 -> 'S' (停止)
    let newState = subscribe.state == "S" ? "R" : "S"
    let result = try await apiService.updateSubscriptionStatus(id: id, state: newState)
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return (false, nil) }
    if result.success {
      await refreshSubscriptions(forceRefresh: true)
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    }
    return result
  }

  /// 重置订阅历史
  func resetSubscribe(subscribe: Subscribe) async throws -> (
    success: Bool, message: String?
  ) {
    guard apiService.canAccess(.subscribe) else { return (false, nil) }
    guard let id = subscribe.id else { return (false, nil) }
    let sessionSnapshot = apiService.sessionSnapshot()
    let result = try await apiService.resetSubscription(id: id)
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return (false, nil) }
    if result.success {
      await refreshSubscriptions(forceRefresh: true)
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    }
    return result
  }

  /// 立即触发订阅搜索
  func searchSubscribe(subscribe: Subscribe) async throws -> Bool {
    guard apiService.canAccess(.subscribe) else { return false }
    guard let id = subscribe.id else { return false }
    let sessionSnapshot = apiService.sessionSnapshot()
    let success = try await apiService.searchSubscription(id: id)
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { return false }
    if success {
      await refreshSubscriptions(forceRefresh: true)
      NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    }
    return success
  }

  /// 删除订阅
  func deleteSubscribe(subscribe: Subscribe) async throws -> Bool {
    guard apiService.canAccess(.subscribe) else { return false }
    guard let id = subscribe.id else { return false }
    let sessionSnapshot = apiService.sessionSnapshot()
    let success = try await apiService.deleteSubscription(id: id)
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { throw CancellationError() }

    let didRefresh = await refreshSubscriptions(forceRefresh: true)
    guard apiService.isSessionUnchanged(from: sessionSnapshot) else { throw CancellationError() }

    let stillExists = movieSubscriptions.contains { $0.id == id }
      || tvSubscriptions.contains { $0.id == id }
    guard success || (didRefresh && !stillExists) else { return false }

    // 通知其他页面（如详情页 preloadTask）订阅已变更
    NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
    return true
  }

  private func validLinkValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if ["none", "null", "undefined"].contains(trimmed.lowercased()) {
      return nil
    }
    return trimmed
  }

  /// 该服务器类型是否已知支持在 tvOS 打开媒体库深链（静态能力，不依赖具体链接）
  static func supportsMediaLibraryDeepLink(serverType: MediaServerType?) -> Bool {
    guard let serverType else { return true }
    switch serverType {
    case .jellyfin, .trimemedia, .ugreen, .zspace:
      return false
    default:
      return true
    }
  }

  func openMediaItem(
    _ item: MediaServerPlayItem,
    using openURL: OpenURLAction,
    onFailure: @escaping (String) -> Void
  ) {
    let originalUrl = validLinkValue(item.link).flatMap { URL(string: $0) }
    guard originalUrl != nil || item.server_type == .emby else {
      onFailure("无法打开媒体库：链接无效")
      return
    }

    var finalUrl: URL? = nil

    // 统一处理 Fragment 解析：有些后端返回 #!/item... 有些返回 #/item...
    let cleanFragment: String? = {
      guard let fragment = originalUrl?.fragment else { return nil }
      return fragment.starts(with: "!") ? String(fragment.dropFirst(1)) : fragment
    }()

    switch item.server_type {
    case .emby:
      // 保留 Emby 社区提到的深度链接格式，但 tvOS 端仍受 Emby App 自身支持限制。
      // 2026-06-29 使用 Emby for Apple TV 2.0.7 实机测试：该 URL 只能打开 Emby，尚不能跳转到具体媒体详情。
      // 后端链接格式: https://your-emby-server/web/index.html#!/item?id=xxxx&serverId=...
      // 尝试的深度链接格式: emby://items?serverId={your_server_id}&itemId={your_item_id}
      var itemId = validLinkValue(item.item_id?.value)
      var serverId = validLinkValue(item.server_id?.value)
      if let fragment = cleanFragment,
        let components = URLComponents(string: "https://dummy.com" + fragment)
      {
        let queryItems = components.queryItems ?? []
        if itemId == nil {
          itemId =
            validLinkValue(queryItems.first { $0.name == "id" }?.value)
            ?? validLinkValue(queryItems.first { $0.name == "parentId" }?.value)
        }
        if serverId == nil {
          serverId = validLinkValue(queryItems.first { $0.name == "serverId" }?.value)
        }
      }

      if let itemId {
        var queryItems = [URLQueryItem]()
        if let serverId {
          queryItems.append(URLQueryItem(name: "serverId", value: serverId))
        }
        queryItems.append(URLQueryItem(name: "itemId", value: itemId))

        var deepLinkComponents = URLComponents()
        deepLinkComponents.scheme = "emby"
        deepLinkComponents.host = "items"
        deepLinkComponents.queryItems = queryItems
        finalUrl = deepLinkComponents.url
      }

    case .plex:
      // 后端链接格式: http://ip:port/web/index.html#!/media/{server_id}/com.plexapp.plugins.library?source={library.key}&X-Plex-Token={token}
      // plex://preplay/?metadataKey={metadataKey}&server={serverId}
      if let fragment = cleanFragment,
        let components = URLComponents(string: "https://dummy.com" + fragment)
      {
        let pathParts = components.path.split(separator: "/")
        if pathParts.count >= 2, pathParts[0] == "media",
          let rawId = validLinkValue(item.raw_id?.value)
        {
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
      onFailure("Jellyfin 暂不支持在 tvOS 打开媒体")
      return
    case .trimemedia:
      onFailure("飞牛 NAS 暂不支持在 tvOS 打开媒体")
      return
    case .ugreen:
      onFailure("绿联 NAS 暂不支持在 tvOS 打开媒体")
      return
    case .zspace:
      onFailure("极空间 NAS 暂不支持在 tvOS 打开媒体")
      return
    default:
      // 处理未来未知的服务器类型（item.server_type.rawValue）
      onFailure(
        "未知的媒体服务器类型\(item.server_type.map { "（\($0.rawValue)）" } ?? "")暂不支持在 tvOS 打开媒体")
      return
    }

    if let finalUrl = finalUrl {
      openURL(finalUrl) { accepted in
        if !accepted {
          onFailure("无法打开媒体库 App，请确认已安装后重试")
        }
      }
    } else if let serverType = item.server_type {
      onFailure("未能生成 \(serverType.rawValue) 的有效媒体库链接")
    }
  }
}
