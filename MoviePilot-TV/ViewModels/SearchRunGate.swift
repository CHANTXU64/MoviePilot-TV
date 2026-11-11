import Foundation

/// 搜索运行的发布门禁。每次运行冻结发起时的会话；被新运行取代、显式结束、
/// 会话变化、失去搜索权限或所在任务取消后，旧运行不得再发布结果或状态。
@MainActor
final class SearchRunGate {
  final class Run {
    fileprivate let session: APIServiceSessionSnapshot

    fileprivate init(session: APIServiceSessionSnapshot) {
      self.session = session
    }

    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}
  }

  private let apiService: APIService
  private var current: Run?

  init(apiService: APIService) {
    self.apiService = apiService
  }

  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  func begin() -> Run {
    let run = Run(session: apiService.sessionSnapshot())
    current = run
    return run
  }

  /// 不传 run 时结束任意当前运行；传入时只结束仍属于它的运行，旧收尾不清理新运行。
  func end(_ run: Run? = nil) {
    guard run == nil || current === run else { return }
    current = nil
  }

  func owns(_ run: Run) -> Bool {
    current === run
  }

  func isCurrent(_ run: Run) -> Bool {
    current === run
      && apiService.isSessionUnchanged(from: run.session)
      && apiService.canAccess(.search)
      && !Task.isCancelled
  }
}
