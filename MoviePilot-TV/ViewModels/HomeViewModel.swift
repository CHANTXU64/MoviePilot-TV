import Combine
import Foundation
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

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
  /// 当前选中服务器的「继续观看」条目（电影或单集，带已播放进度）
  @Published var continueWatching: [MediaServerPlayItem] = []
  /// 「继续观看」可选的媒体服务器
  @Published var continueWatchingServers: [String] = []
  /// 「继续观看」当前选中的媒体服务器，与「最近添加」各自记住
  @Published var selectedContinueWatchingServer: String = "" {
    didSet {
      guard oldValue != selectedContinueWatchingServer else { return }
      persistSelectedContinueWatchingServer()
      applyContinueWatchingSelection()
    }
  }
  /// 电影订阅列表
  @Published var movieSubscriptions: [Subscribe] = []
  /// 电视剧订阅列表
  @Published var tvSubscriptions: [Subscribe] = []
  /// 最近播放加载失败标记（成功空视为有效结果；失败保留旧快照并置位）
  @Published var latestLoadFailed = false
  /// 「继续观看」加载失败标记，与「最近添加」分开：一行失败不影响另一行的提示
  @Published var continueWatchingLoadFailed = false
  /// 订阅加载失败标记（成功空视为有效结果；失败保留旧数组并置位）
  @Published var subscriptionsLoadFailed = false
  /// 加载状态
  @Published var isLoading = true
  /// 能在应用内播放的媒体服务器名称（已启用、类型支持应用内播放，且配置了地址和密钥）
  @Published private(set) var inAppPlayableServers: Set<String> = []
  /// 能在应用内播放的服务器上，「最近添加」各条目按下做什么（有没有 TMDB 编号），键见 `itemKey`。每次读列表时一起重读。
  @Published private(set) var libraryLinks: [String: LibraryItemLink] = [:]
  private var libraryLinksTask: Task<Void, Never>?
  /// 「最近添加」里海报读不出来的条目改用的 TMDB 海报，键见 `itemKey`。
  @Published private(set) var posterFallbacks: [String: URL] = [:]
  /// 报过海报读不出来的卡片，和找回退海报时用的身份（`libraryLinks` 里的，nil 表示还不知道、按标题找）。
  /// 身份变了（读到编号、识别结果变了）就按新身份重找，结果写回前复核身份没再变。
  private var posterRequests: [String: (item: MediaServerPlayItem, server: String, link: LibraryItemLink?)] = [:]

  private let apiService: APIService
  private var latestMediaSelectedServerKey: String? {
    apiService.profileKey.map { "home.latestMedia.selectedServer.v2_\($0)" }
  }
  private var continueWatchingSelectedServerKey: String? {
    apiService.profileKey.map { "home.continueWatching.selectedServer.v1_\($0)" }
  }
  /// 「继续观看」一行最多读多少条：横排一次只露 4 张，20 条够翻几屏。
  static let continueWatchingCount = 20
  private var latestMediaByServer: [String: [MediaServerPlayItem]] = [:]
  private var continueWatchingByServer: [String: [MediaServerPlayItem]] = [:]
  /// 「继续观看」的整次读取（服务器列表 + 条目）走「最新者胜出」：页面激活、手动重试、进度写回通知三个入口
  /// 可能同时在读，慢的旧请求不得覆盖快的新请求——这一行不跟轮询，覆盖错了旧进度会一直显示。
  /// 复用 `CoalescingCache` 的强刷取代链，不手写代际计数器。ttl 0：不留缓存，每次都现读。
  private let continueWatchingReads = CoalescingCache<String, ContinueWatchingRead>(
    ttl: 0, capacity: 1, renewsTTLOnAccess: false, cancelsAbandonedLoads: true)
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
    if let key = continueWatchingSelectedServerKey {
      self.selectedContinueWatchingServer = UserDefaults.standard.string(forKey: key) ?? ""
    }

    // 设置里的应用内播放开关变了：重绘卡片的点击方式和长按菜单（是否能在应用内播放每次都现读）。
    NotificationCenter.default.publisher(for: PlaybackPreferences.inAppPlaybackDidChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

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

  /// 页面每次成为当前 Tab 时调用（见 `HomeView` 的 `.task(id: isSelected)`）：三个板块各自刷新、各自发布。
  /// 不设「已加载过」门闩——每次进入都要刷新，门闩只会让快速切 Tab 时新旧任务交错、绕过结束 Loading 的那一步。
  func loadData() async {
    // 仅在还没有任何数据时显示全屏 Loading
    if latestMedia.isEmpty && continueWatching.isEmpty
      && movieSubscriptions.isEmpty && tvSubscriptions.isEmpty
    {
      isLoading = true
    }

    await refreshData()

    // 被取消（切走页面）就不动 Loading，交给下一次进入的那一轮跑完再关。
    guard !Task.isCancelled else { return }
    isLoading = false
  }

  /// 刷新首页数据：三个板块并发、各自发布结果，互不阻塞。
  /// `includeContinueWatching` 为 false 时只刷「最近添加」和订阅（10 秒轮询用）：Jellyfin 后端会为每条
  /// 续播条目向媒体服务器探测一次封面（`_get_resume_image`），持续轮询会把这份开销压到媒体服务器上；
  /// Web 也只在页面激活时读。「继续观看」另由页面激活、手动重试和进度写回完成后触发。
  func refreshData(includeContinueWatching: Bool = true) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadLatestMedia() }
      if includeContinueWatching {
        group.addTask { await self.loadContinueWatching() }
      }
      group.addTask { await self.refreshSubscriptions(forceRefresh: true) }
    }
  }

  /// 只重读「继续观看」：播放的停止上报和进度写回发完后调用（见 `PlaybackCoordinator.watchStateUpdates`）。
  /// 不碰「最近添加」和订阅，它们由轮询负责。
  func refreshContinueWatching() async {
    await loadContinueWatching()
  }

  /// 「最近添加」：现拉媒体服务器配置（写回会话缓存，详情页和播放沿用同一份），
  /// 再按启用服务器读列表。自己发布快照、失败标记和可选服务器，不等另一行。
  private func loadLatestMedia() async {
    guard apiService.canRequestSuperUserEndpoints else {
      clearLatestMedia()
      if !inAppPlayableServers.isEmpty { inAppPlayableServers = [] }
      return
    }
    let session = apiService.sessionSnapshot()
    let servers: [MediaServerConf]
    do {
      servers = try await apiService.fetchCachedMediaServers(forceRefresh: true)
    } catch {
      guard apiService.isSessionUnchanged(from: session) else { return }
      if error is CancellationError {
        Logger.debug("加载媒体服务器配置被取消")
      } else {
        Logger.error("加载媒体服务器配置失败: \(error)")
        latestLoadFailed = true
      }
      return
    }
    guard apiService.isSessionUnchanged(from: session) else { return }
    let playableServers = Set(servers.filter(\.supportsInAppPlayback).map(\.name))
    if inAppPlayableServers != playableServers { inAppPlayableServers = playableServers }
    // 只保留启用服务器（保持后端返回顺序）
    let enabledServers = servers.filter { $0.enabled?.value ?? false }

    let read = await readServerItems(enabledServers, row: .latest)
    guard apiService.isSessionUnchanged(from: session) else { return }
    // 全部完成（无取消）时按结果刷新失败标记；有取消保持原值。
    if !read.anyCancelled { latestLoadFailed = read.anyFailed }

    let merged = Self.mergedRow(
      read, enabledServers: enabledServers, previous: latestMediaByServer,
      selected: selectedLatestMediaServer)
    latestMediaByServer = merged.byServer
    loadLibraryLinks(read.byServer, playableServers: playableServers, session: session)
    if latestMediaServers != merged.servers { latestMediaServers = merged.servers }
    selectedLatestMediaServer = merged.selected
    applyLatestMediaSelection()
  }

  /// 「继续观看」：自己读配置和条目、自己发布，不等「最近添加」。快照、失败标记和选择规则与它相同（共用 `mergedRow`）。
  /// 整次读取经 `continueWatchingReads` 的取代链：并发的几个入口都拿最新那次的结果，旧的不会覆盖新的。
  private func loadContinueWatching() async {
    guard apiService.canRequestSuperUserEndpoints else {
      clearContinueWatching()
      return
    }
    let session = apiService.sessionSnapshot()
    let read: ContinueWatchingRead
    do {
      read = try await continueWatchingReads.value(
        for: "continueWatching", forceRefresh: true, validate: { try Task.checkCancellation() }
      ) {
        // 配置也现拉：读缓存会拿到上一轮的旧列表，而这一行不跟轮询，两行的可选服务器会一直不一致。
        // 与「最近添加」并发强刷时，配置缓存的取代链让两边都拿到最新那次的结果，即同一次读取。
        let servers = try await self.apiService.fetchCachedMediaServers(forceRefresh: true)
        let enabled = servers.filter { $0.enabled?.value ?? false }
        return ContinueWatchingRead(
          enabledServers: enabled, items: await self.readServerItems(enabled, row: .continueWatching))
      }
    } catch is CancellationError {
      // 调用方被取消（切走页面、会话拆除）：不发布任何结果。
      return
    } catch {
      guard apiService.isSessionUnchanged(from: session) else { return }
      Logger.error("加载媒体服务器配置失败: \(error)")
      continueWatchingLoadFailed = true
      return
    }
    guard apiService.isSessionUnchanged(from: session) else { return }
    if !read.items.anyCancelled { continueWatchingLoadFailed = read.items.anyFailed }

    let merged = Self.mergedRow(
      read.items, enabledServers: read.enabledServers, previous: continueWatchingByServer,
      selected: selectedContinueWatchingServer)
    continueWatchingByServer = merged.byServer
    if continueWatchingServers != merged.servers { continueWatchingServers = merged.servers }
    selectedContinueWatchingServer = merged.selected
    applyContinueWatchingSelection()
  }

  /// 「继续观看」的一次完整读取：服务器列表和条目属于同一次读取，不能分开管理——
  /// 否则并发的旧请求会拿最新条目配自己那份旧服务器列表，把已停用的服务器又放回选择器。
  private struct ContinueWatchingRead {
    var enabledServers: [MediaServerConf] = []
    var items = ServerItemsRead()
  }

  /// 两行共用的快照与选择规则：这一轮读成功的服务器覆盖旧快照，失败/取消的保留上一轮，停用的随新列表移除；
  /// 没有可选服务器时选择清空（这一行随之为空），否则保留仍有效的旧选择，无效时选第一个。
  private static func mergedRow(
    _ read: ServerItemsRead, enabledServers: [MediaServerConf],
    previous: [String: [MediaServerPlayItem]], selected: String
  ) -> (byServer: [String: [MediaServerPlayItem]], servers: [String], selected: String) {
    let enabledServerNames = Set(enabledServers.map(\.name))
    var byServer = previous.filter { enabledServerNames.contains($0.key) }
    for (serverName, items) in read.byServer {
      byServer[serverName] = items
    }
    let servers = enabledServers.map(\.name)
    return (byServer, servers, servers.contains(selected) ? selected : (servers.first ?? ""))
  }

  /// 媒体库页两行读的是同一个形状：按服务器并发读同一个列表。
  private enum MediaServerItemRow {
    case latest
    case continueWatching

    nonisolated var logName: String {
      switch self {
      case .latest: "最新媒体"
      case .continueWatching: "继续观看"
      }
    }

    func read(server: String, api: APIService) async throws -> [MediaServerPlayItem] {
      switch self {
      case .latest:
        return try await api.fetchMediaServerLatest(server: server)
      case .continueWatching:
        return try await api.fetchMediaServerPlaying(server: server, count: HomeViewModel.continueWatchingCount)
      }
    }
  }

  private struct ServerItemsRead {
    var byServer: [String: [MediaServerPlayItem]] = [:]
    var anyFailed = false
    var anyCancelled = false
  }

  /// 并发读各台已启用服务器的同一个列表。只有成功结果（含成功空）进快照；失败和取消分别记账，
  /// 由调用方决定保留旧快照还是置失败标记。
  private func readServerItems(_ servers: [MediaServerConf], row: MediaServerItemRow) async -> ServerItemsRead {
    await withTaskGroup(of: (String, ServerItemOutcome).self) { group in
      for server in servers {
        group.addTask {
          let label = row.logName
          do {
            let items = try await row.read(server: server.name, api: self.apiService)
            return (server.name, .success(items))
          } catch is CancellationError {
            return (server.name, .cancelled)
          } catch {
            Logger.error("加载服务器 \(server.name) \(label)失败: \(error)")
            return (server.name, .failed)
          }
        }
      }

      var read = ServerItemsRead()
      for await (serverName, outcome) in group {
        switch outcome {
        case .success(let items):
          read.byServer[serverName] = items
        case .failed:
          read.anyFailed = true
        case .cancelled:
          read.anyCancelled = true
        }
      }
      return read
    }
  }

  private enum ServerItemOutcome {
    case success([MediaServerPlayItem])
    case failed
    case cancelled
  }

  /// 读不到媒体服务器配置（没有超管权限）：这一行清空，不算加载失败。两行各自清各自的。
  private func clearLatestMedia() {
    latestMediaByServer = [:]
    latestMediaServers = []
    latestLoadFailed = false
    if selectedLatestMediaServer != "" { selectedLatestMediaServer = "" }
    if !latestMedia.isEmpty { latestMedia = [] }
  }

  private func clearContinueWatching() {
    continueWatchingByServer = [:]
    continueWatchingServers = []
    continueWatchingLoadFailed = false
    if selectedContinueWatchingServer != "" { selectedContinueWatchingServer = "" }
    if !continueWatching.isEmpty { continueWatching = [] }
  }

  /// 这一行要显示的条目就是选中服务器的快照；没有选中服务器时这一行为空。
  private static func selectedItems(
    _ selected: String, byServer: [String: [MediaServerPlayItem]]
  ) -> [MediaServerPlayItem] {
    selected.isEmpty ? [] : (byServer[selected] ?? [])
  }

  private func applyLatestMediaSelection() {
    let newMedia = Self.selectedItems(selectedLatestMediaServer, byServer: latestMediaByServer)
    if latestMedia != newMedia { latestMedia = newMedia }
  }

  private func persistSelectedLatestMediaServer() {
    guard let key = latestMediaSelectedServerKey else { return }
    UserDefaults.standard.set(selectedLatestMediaServer, forKey: key)
  }

  private func applyContinueWatchingSelection() {
    let newItems = Self.selectedItems(
      selectedContinueWatchingServer, byServer: continueWatchingByServer)
    if continueWatching != newItems { continueWatching = newItems }
  }

  private func persistSelectedContinueWatchingServer() {
    guard let key = continueWatchingSelectedServerKey else { return }
    UserDefaults.standard.set(selectedContinueWatchingServer, forKey: key)
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
      Logger.debug("加载订阅被取消")
      return false
    } catch {
      Logger.error("加载订阅失败: \(error)")
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

  /// 本机发起的试看。订阅卡片据此标「试看」；别的设备留下的试看订阅按普通订阅显示。
  var episodeTrials: EpisodeTrialService { apiService.sessionScope.episodeTrial }

  /// 当前账号能否取消试看订阅（管理员）。
  var canCancelEpisodeTrial: Bool { episodeTrials.canCancelTrial }

  /// 取消试看：请求停止搜索，搜索结束后删掉这条试看订阅；删掉了就刷新订阅列表。
  func cancelEpisodeTrial(subscribe: Subscribe) async -> EpisodeTrialCancelOutcome {
    guard let id = subscribe.id else { return .failed }
    let sessionSnapshot = apiService.sessionSnapshot()
    let outcome = await episodeTrials.cancelTrial(subscriptionID: id)
    guard outcome == .done, apiService.isSessionUnchanged(from: sessionSnapshot) else { return outcome }
    await refreshSubscriptions(forceRefresh: true)
    return outcome
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

  /// 指定服务器上这个条目能在应用内播放时的条目 ID；不能播放时为 nil。
  /// 服务器由调用方给：媒体库页两行各有自己的选择，条目 ID 只在它自己的服务器上有意义。
  func inAppPlaybackItemID(_ item: MediaServerPlayItem, server: String) -> String? {
    Self.inAppPlaybackItemID(
      item, server: server, playableServers: inAppPlayableServers,
      canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
      backendVersion: apiService.settings?.BACKEND_VERSION)
  }

  static func inAppPlaybackItemID(
    _ item: MediaServerPlayItem, server: String, playableServers: Set<String>,
    canRequestSuperUserEndpoints: Bool, backendVersion: String?
  ) -> String? {
    guard playableServers.contains(server),
      InAppPlaybackAvailability.offers(
        mediaType: item.type, canRequestSuperUserEndpoints: canRequestSuperUserEndpoints,
        backendVersion: backendVersion)
    else { return nil }
    return trimmedNonEmpty([item.item_id?.value])
  }

  /// 按下「最近添加」卡片是跳到媒体服务器 App（卡片左下角有跳转图标），还是打开详情页。卡片不直接播放：
  /// 播放在详情页里（电影按「播放」、剧按单集卡片）。能在应用内播放且设置里选了在应用内打开时打开详情页；
  /// 否则这类服务器支持跳转就跳过去，不支持跳转（如 Jellyfin）的也打开详情页。
  static func opensMediaServerApp(canOpenMediaLibrary: Bool, canPlayInApp: Bool, prefersInApp: Bool) -> Bool {
    canOpenMediaLibrary && !(canPlayInApp && prefersInApp)
  }

  func opensMediaServerApp(_ item: MediaServerPlayItem, server: String) -> Bool {
    Self.opensMediaServerApp(
      canOpenMediaLibrary: Self.supportsMediaLibraryDeepLink(serverType: item.server_type),
      canPlayInApp: inAppPlaybackItemID(item, server: server) != nil,
      prefersInApp: SystemViewModel.shouldPlayHomeMediaInApp)
  }

  /// 读列表后一次读出各台能在应用内播放的服务器上这些条目的 TMDB 编号（见 `PlaybackCoordinator.libraryItemLinks`），
  /// 没有编号的再按标题、年份识别（见 `resolve`），卡片据此决定按下打开详情页还是直接播放。
  /// 还没读到、识别请求失败的不写，按下时现读；读不到的服务器保留上一次的结果。
  private func loadLibraryLinks(
    _ latestByServer: [String: [MediaServerPlayItem]], playableServers: Set<String>, session: APIServiceSessionSnapshot
  ) {
    libraryLinksTask?.cancel()
    let requests: [(server: String, items: [String: MediaServerPlayItem])] = latestByServer.compactMap { server, items in
      var byID: [String: MediaServerPlayItem] = [:]
      for item in items {
        guard
          let id = Self.inAppPlaybackItemID(
            item, server: server, playableServers: playableServers,
            canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
            backendVersion: apiService.settings?.BACKEND_VERSION)
        else { continue }
        byID[id] = item
      }
      return byID.isEmpty ? nil : (server, byID)
    }
    guard !requests.isEmpty else { return }
    let coordinator = apiService.sessionScope.playbackCoordinator
    libraryLinksTask = Task { [weak self] in
      for request in requests {
        let raw = await coordinator.libraryItemLinks(serverName: request.server, itemIDs: Array(request.items.keys))
        guard let self, !Task.isCancelled else { return }
        guard let raw else { continue }
        var links: [String: LibraryItemLink] = [:]
        await withTaskGroup(of: (String, LibraryItemLink?).self) { group in
          for (id, link) in raw {
            guard let item = request.items[id] else { continue }
            group.addTask { (id, await self.resolve(link, for: item)) }
          }
          for await (id, link) in group { links[id] = link }
        }
        guard !Task.isCancelled, self.apiService.isSessionUnchanged(from: session) else { return }
        var next = self.libraryLinks.filter { !$0.key.hasPrefix("\(request.server)|") }
        for (id, link) in links { next[Self.itemKey(server: request.server, itemID: id)] = link }
        self.libraryLinks = next
        self.refreshPosterFallbacks(on: request.server)
      }
    }
  }

  /// 条目上没有 TMDB 编号时按标题、年份识别（结果在会话里记住，见 `APIService.cachedRecognizedTmdbId`）：
  /// 识别出来就打开那部片的详情页，认不出才直接播放。识别请求失败时为 nil（不知道）。
  private func resolve(_ link: LibraryItemLink, for item: MediaServerPlayItem) async -> LibraryItemLink? {
    guard link == .libraryOnly else { return link }
    do {
      guard
        let tmdbID = try await apiService.cachedRecognizedTmdbId(title: item.title, year: item.subtitle, type: item.type)
      else { return .libraryOnly }
      return .detail(tmdbID: tmdbID, mediaType: item.type ?? "")
    } catch {
      return nil
    }
  }

  private static func itemKey(server: String, itemID: String) -> String { "\(server)|\(itemID)" }

  /// 这张卡对应的条目按下做什么；还没读到或不能在应用内播放时为 nil。
  func libraryLink(for item: MediaServerPlayItem, server: String) -> LibraryItemLink? {
    inAppPlaybackItemID(item, server: server).flatMap { libraryLinks[Self.itemKey(server: server, itemID: $0)] }
  }

  /// 没跳到媒体服务器 App 时，这张卡按下是不是直接播放：条目没有 TMDB 编号、按标题也识别不出，MoviePilot 没有它的详情页。
  func playsDirectly(_ item: MediaServerPlayItem, server: String) -> Bool {
    libraryLink(for: item, server: server) == .libraryOnly
  }

  /// 「继续观看」卡片按下做什么。
  enum ContinueWatchingAction: Equatable {
    /// 在应用内从上次的位置接着播（起播位置由 `PlaybackResumePolicy` 决定）。
    case play(PlaybackTarget)
    case openInServerApp
    case detail

    /// 剧照角标上的图标，标出按下会做什么：接着播是播放图标，离开本 App 是跳转图标，
    /// 打开详情页不带图标（同 `MediaCard` 的约定）。
    var badgeIcon: String? {
      switch self {
      case .play: AppSymbol.play
      case .openInServerApp: AppSymbol.openInLibrary
      case .detail: nil
      }
    }

    /// 无障碍提示：说出按下会做什么。
    var accessibilityHint: String {
      switch self {
      case .play: "接着播放"
      case .openInServerApp: "在媒体服务器 App 中打开"
      case .detail: "打开详情"
      }
    }
  }

  /// 这一行就是接着看，所以能在应用内播放时直接续播，不经过详情页，也不受「首页媒体在应用内打开」
  /// 开关影响——那个开关只管「最近添加」，而且默认关闭。不能应用内播放时，支持深链的服务器跳到它自己的
  /// App（同 Web），不支持深链的打开 MoviePilot 详情页。
  func continueWatchingAction(for item: MediaServerPlayItem, server: String) -> ContinueWatchingAction {
    if let itemID = inAppPlaybackItemID(item, server: server) {
      // 电视剧的续播条目是单集：走带剧集上下文的那条，起播前认出这一集就有选集和连播。
      return .play(
        item.type == "电视剧"
          ? .serverEpisode(serverName: server, itemID: itemID)
          : .serverItem(serverName: server, itemID: itemID))
    }
    return Self.supportsMediaLibraryDeepLink(serverType: item.server_type) ? .openInServerApp : .detail
  }

  /// 「继续观看」条目识别用的媒体信息：优先按服务器上的外部编号认出是哪部片（电影用条目自己的，
  /// 单集用所属整剧的），读不到再按标题、年份识别——同名不同年的剧不会认错。
  /// 退回按标题时，剧集的副标题是季集和集名，不能当年份（见 `ContinueWatchingDisplay.mediaInfo`）。
  /// **期间换了账号返回 nil，调用方必须终止整个操作**：不能拿旧账号的媒体标题向新会话发识别请求。
  /// 身份读不到（服务器没配置、条目不在、认不出）才退回按标题，两者不是一回事。
  func continueWatchingMediaInfo(for item: MediaServerPlayItem, server: String) async -> MediaInfo? {
    let byTitle = ContinueWatchingDisplay.mediaInfo(
      title: item.title, type: item.type, subtitle: item.subtitle)
    guard let itemID = trimmedNonEmpty([item.item_id?.value]) else { return byTitle }
    let snapshot = apiService.sessionSnapshot()
    let identified = await apiService.sessionScope.playbackCoordinator.resumeItemIdentity(
      serverName: server, itemID: itemID)
    guard apiService.isSessionUnchanged(from: snapshot) else { return nil }
    return identified ?? byTitle
  }

  /// 「继续观看」条目没有应用内播放、这台服务器也不支持跳转时，打开它的详情页。
  /// 读服务器身份期间沿用「正在识别」提示，别让按下后静默等着（同 `cardDestination`）。
  func continueWatchingDetailTarget(
    for item: MediaServerPlayItem, server: String, using handler: MediaActionHandler
  ) async -> MediaInfo? {
    handler.isRecognizingTmdb = true
    let info = await continueWatchingMediaInfo(for: item, server: server)
    handler.isRecognizingTmdb = false
    guard let info else { return nil }
    return await handler.getTMDBJumpTarget(for: info)
  }

  /// 「最近添加」卡片按下（没跳到媒体服务器 App 时）去哪里。
  enum CardDestination {
    case detail(MediaInfo)
    /// 没有 TMDB 编号、也识别不出：在应用内直接播放这个条目。
    case play(PlaybackTarget)
  }

  /// 按下卡片去哪里。能在应用内播放的服务器上按条目自己的 TMDB 编号（与这份文件一一对应）打开详情页，没有编号的按标题识别，
  /// 认不出才直接播放；读列表时没读到的现读一次（期间显示「正在识别」）。服务器读不到时按标题、年份识别（识别不出时
  /// `handler` 会提示）。
  func cardDestination(
    for item: MediaServerPlayItem, server: String, using handler: MediaActionHandler
  ) async -> CardDestination? {
    let snapshot = apiService.sessionSnapshot()
    if let itemID = inAppPlaybackItemID(item, server: server) {
      let key = Self.itemKey(server: server, itemID: itemID)
      var link = libraryLinks[key]
      if link == nil {
        handler.isRecognizingTmdb = true
        var resolved: LibraryItemLink?
        var hasEntry = false
        if let raw = await apiService.sessionScope.playbackCoordinator.libraryItemLinks(
          serverName: server, itemIDs: [itemID])?[itemID]
        {
          hasEntry = true
          resolved = await resolve(raw, for: item)
        }
        handler.isRecognizingTmdb = false
        guard apiService.isSessionUnchanged(from: snapshot), !Task.isCancelled else { return nil }
        // 只记下确定的结果；识别请求失败的这次照样直接播放（打不开详情页，至少能看），下次再识别。
        if let resolved { libraryLinks[key] = resolved }
        link = resolved ?? (hasEntry ? .libraryOnly : nil)
      }
      switch link {
      case .detail(let tmdbID, let mediaType):
        let typed = MediaInfo(title: item.title, type: mediaType, year: item.subtitle)
        var target = MediaActionHandler.tmdbJumpTarget(for: typed, tmdbId: tmdbID)
        // 带上这份文件：MoviePilot 还没同步到它时，详情页仍能播放。
        target.libraryItemHint = MediaServerItemRef(itemID: itemID, server: server)
        return .detail(target)
      case .libraryOnly:
        return .play(.serverItem(serverName: server, itemID: itemID))
      case nil:
        break
      }
    }
    let info = MediaInfo(title: item.title, type: item.type, year: item.subtitle)
    guard var target = await handler.getTMDBJumpTarget(for: info) else { return nil }
    // 服务器暂时读不到时也带上这份文件：MoviePilot 还没同步到它、之后服务器恢复时，详情页仍能播放（起播前按编号核对）。
    if let itemID = inAppPlaybackItemID(item, server: server) {
      target.libraryItemHint = MediaServerItemRef(itemID: itemID, server: server)
    }
    return .detail(target)
  }

  func posterFallbackURL(for item: MediaServerPlayItem, server: String) -> URL? {
    posterFallbacks[Self.itemKey(server: server, itemID: item.id)]
  }

  /// 海报读不出来（媒体服务器上没有封面，或者图片读不到）时改用这部片的 TMDB 海报：TMDB 编号按读列表时读到、识别到的
  /// （见 `libraryLinks`），不知道时按标题、年份识别；确认没有 TMDB 编号的不找。识别结果和海报路径都在会话里记住
  /// （`APIService.cachedRecognizedTmdbId`、`cachedTmdbPosterPath`），请求失败的下次再找。
  /// `server` 是卡片所在的服务器（建卡片时取），不用回调到达时选中的：条目 ID 只在它自己的服务器上有意义。
  func loadPosterFallback(for item: MediaServerPlayItem, server: String) {
    let key = Self.itemKey(server: server, itemID: item.id)
    let link = posterLink(for: item, server: server)
    // 同一身份已经找到了就不再找（卡片滚回来会再报一次）。
    if let request = posterRequests[key], request.link == link, posterFallbacks[key] != nil { return }
    posterRequests[key] = (item, server, link)
    let snapshot = apiService.sessionSnapshot()
    Task { [weak self] in
      guard let self else { return }
      let url = await self.tmdbPosterURL(for: item, link: link)
      // 找的期间身份变了（编号读到了）：以按新身份找的为准。
      guard self.apiService.isSessionUnchanged(from: snapshot), self.posterRequests[key]?.link == link else { return }
      if let url {
        self.posterFallbacks[key] = url
      } else if link != nil {
        // 按确定的身份找不到海报：之前按别的身份找到的不对，去掉。
        self.posterFallbacks[key] = nil
      }
    }
  }

  /// 卡片对应条目在 `libraryLinks` 里的身份；不能在应用内播放或还没读到时为 nil。
  private func posterLink(for item: MediaServerPlayItem, server: String) -> LibraryItemLink? {
    Self.inAppPlaybackItemID(
      item, server: server, playableServers: inAppPlayableServers,
      canRequestSuperUserEndpoints: apiService.canRequestSuperUserEndpoints,
      backendVersion: apiService.settings?.BACKEND_VERSION
    ).flatMap { libraryLinks[Self.itemKey(server: server, itemID: $0)] }
  }

  /// `server` 上的条目身份读到或变了以后，对报过缺图、当时身份不同的卡片按新身份重找海报。
  private func refreshPosterFallbacks(on server: String) {
    for request in posterRequests.values where request.server == server {
      guard posterLink(for: request.item, server: server) != request.link else { continue }
      loadPosterFallback(for: request.item, server: server)
    }
  }

  private func tmdbPosterURL(for item: MediaServerPlayItem, link: LibraryItemLink?) async -> URL? {
    let tmdbID: Int?
    var mediaType = item.type
    switch link {
    case .detail(let id, let type):
      tmdbID = id
      mediaType = type
    case .libraryOnly:
      return nil
    case nil:
      tmdbID = (try? await apiService.cachedRecognizedTmdbId(title: item.title, year: item.subtitle, type: item.type))
        ?? nil
    }
    guard let tmdbID, !Task.isCancelled,
      let path = (try? await apiService.cachedTmdbPosterPath(tmdbID: tmdbID, type: mediaType)) ?? nil
    else { return nil }
    return apiService.getPosterImageUrl(posterPath: path)
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
