import Foundation

/// 一次会话（服务器 + 账号 + 权限指纹）内共享的协作对象。
///
/// 由 `APIService` 按 `uiIdentity` 持有：同账号刷新沿用同一个作用域，换账号或登出时整体拆除并重建。
/// 因此作用域内的对象不需要各自监听会话变化再自清，生命周期本身保证它们不跨会话存活。
@MainActor
final class SessionScope {
  let uiIdentity: String
  let mediaPreloader: MediaPreloader

  init(apiService: APIService, uiIdentity: String) {
    self.uiIdentity = uiIdentity
    mediaPreloader = MediaPreloader(apiService: apiService)
  }

  /// 会话结束时同步拆除：取消在途任务、清空缓存与订阅，旧作用域不再响应任何事件。
  func tearDown() {
    mediaPreloader.tearDown()
  }
}
