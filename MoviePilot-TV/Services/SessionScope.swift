import Foundation

/// 一次会话（服务器 + 账号 + 权限指纹）内共享的协作对象。
///
/// 由 `APIService` 按 `uiIdentity` 持有：同账号刷新沿用同一个作用域，换账号或登出时整体拆除并重建。
/// 因此作用域内的对象不需要各自监听会话变化再自清，生命周期本身保证它们不跨会话存活。
@MainActor
final class SessionScope {
  let uiIdentity: String
  let mediaPreloader: MediaPreloader
  let imageWarmer: MPImageWarmer

  // MARK: - 短暂内存缓存 (提升二级页面和分季组件流畅度)
  let episodeGroupsCache = CoalescingCache<String, [EpisodeGroup]>(ttl: 120, capacity: 20)
  let mediaSeasonsCache = CoalescingCache<String, [TmdbSeason]>(ttl: 120, capacity: 20)
  let groupSeasonsCache = CoalescingCache<String, [TmdbSeason]>(ttl: 120, capacity: 20)
  let subscriptionStatusCache = CoalescingCache<String, Bool>(ttl: 120, capacity: 100)
  let subscriptionSnapshotCache = CoalescingCache<String, [Subscribe]>(
    ttl: 30,
    capacity: 1,
    renewsTTLOnAccess: false
  )

  init(apiService: APIService, uiIdentity: String) {
    self.uiIdentity = uiIdentity
    imageWarmer = MPImageWarmer(apiService: apiService)
    mediaPreloader = MediaPreloader(apiService: apiService)
  }

  /// 订阅相关 mutation 后失效：订阅状态与订阅列表快照。
  func invalidateSubscriptionCaches() {
    subscriptionStatusCache.invalidateAll()
    subscriptionSnapshotCache.invalidateAll()
  }

  /// 会话状态变化后失效作用域内全部接口缓存。
  func invalidateAllCaches() {
    invalidateSubscriptionCaches()
    episodeGroupsCache.invalidateAll()
    mediaSeasonsCache.invalidateAll()
    groupSeasonsCache.invalidateAll()
  }

  /// 会话结束时同步拆除：取消在途任务、清空缓存与订阅，旧作用域不再响应任何事件。
  func tearDown() {
    invalidateAllCaches()
    imageWarmer.clear()
    mediaPreloader.tearDown()
  }
}
