import Combine
import Foundation

/// 「订阅」页：读订阅列表、按电影/电视剧分两行，以及订阅卡片长按菜单里的操作。
@MainActor
class SubscriptionsViewModel: ObservableObject {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 电影订阅列表
  @Published var movieSubscriptions: [Subscribe] = []
  /// 电视剧订阅列表
  @Published var tvSubscriptions: [Subscribe] = []
  /// 订阅加载失败标记（成功空视为有效结果；失败保留旧数组并置位）
  @Published var subscriptionsLoadFailed = false
  /// 这个页面的首轮加载还没跑完。只在页面第一次加载时为 true：再次进入页面时在后台刷新，
  /// 保留已显示的内容（包括空态和失败提示），不再整页转圈。
  @Published private(set) var isLoading = true

  /// 整页转圈：首轮加载还没跑完，而且还没有可以显示的订阅。
  var showsLoadingPlaceholder: Bool {
    isLoading && movieSubscriptions.isEmpty && tvSubscriptions.isEmpty
  }

  private let apiService: APIService
  private var cancellables = Set<AnyCancellable>()

  init(apiService: APIService? = nil) {
    self.apiService = apiService ?? APIService.shared

    // 在其他页面订阅、编辑或取消订阅后立即刷新
    NotificationCenter.default.publisher(for: .subscriptionDidUpdate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { [weak self] in
          await self?.refreshSubscriptions(forceRefresh: true)
        }
      }
      .store(in: &cancellables)
  }

  /// 页面每次成为当前 Tab 时调用（见 `SubscriptionsView` 的 `.task(id: isSelected)`）。
  /// 每次进入都刷新，不设「已加载过」门闩。`isLoading` 只从 true 变成 false：首轮被切走打断时留给下一次进入的
  /// 那一轮关；之后再进入是后台刷新，不回到整页转圈。
  func loadData() async {
    await refreshSubscriptions(forceRefresh: true)

    guard !Task.isCancelled else { return }
    isLoading = false
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
}
