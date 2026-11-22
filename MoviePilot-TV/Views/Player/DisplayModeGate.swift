import AVKit
import UIKit

/// 电视显示模式（tvOS「匹配内容」）的状态；测试用替身实现。
@MainActor
protocol DisplayModeSwitching: AnyObject {
  var isDisplayCriteriaMatchingEnabled: Bool { get }
  var isDisplayModeSwitchInProgress: Bool { get }
}

extension AVDisplayManager: DisplayModeSwitching {}

/// 起播遮挡的样子（见 `PlaybackLoadingScreen`）。
enum StartupCover: Equatable {
  /// 黑底正中转圈：还在准备。
  case loading
  /// 纯黑：电视正在切换显示模式。切换时 HDMI 本来就黑屏，切完很快就绪时直接出画面，中间不再闪一下转圈。
  case blank
}

/// 起播时整屏盖住播放界面，首帧备好才揭开（Apple TV App 的做法）：准备期间黑底转圈，电视切换显示模式时纯黑，
/// 切好直接出画面。
/// 开了「匹配内容」时，播放器按读出的片源格式向电视申请帧率和动态范围，电视随即切换 HDMI 模式并黑屏约 1 秒，
/// 切换前露出的画面或控件就像闪了一下。AetherEngine 在交给系统播放器之前申请、切换期间压住起播；
/// 这里只决定遮挡的样子和何时揭开，不控制播放。
@MainActor
enum DisplayModeGate {
  struct Timing {
    /// 播放器就绪后，留给电视开始切换的时间；这段时间里没开始切换，就当不用切。没开「匹配内容」时不等。
    var settle: Duration = .milliseconds(200)
    /// 切换结束后过了这么久还没就绪，纯黑换回转圈。切完通常马上就绪，这时直接揭开；远端慢时不让人对着纯黑干等。
    var loadingResumeDelay: Duration = .seconds(1)
    /// 一次切换最多等这么久。超时就揭开：宁可闪一下，也不能一直纯黑。
    var switchTimeout: Duration = .seconds(8)
    /// 播放器一直不就绪时最多盖这么久，之后交给播放器自己的界面。准备期间有转圈，正常的慢起播在这之前就绪或报错。
    var loadingTimeout: Duration = .seconds(30)
    var poll: Duration = .milliseconds(50)
  }

  /// 前台窗口的显示管理器，播放器也是向它申请显示模式。
  static var currentDisplay: (any DisplayModeSwitching)? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return (scene?.keyWindow ?? scene?.windows.first)?.avDisplayManager
  }

  /// 可以揭开遮挡的播放器状态：首帧已备好，且起播不再等电视切换显示模式。
  /// 出错或已结束也算，交给播放失败或播完的流程处理。
  static func isSettled(status: AetherPlayer.Status, hasFirstFrame: Bool, isAwaitingDisplaySwitch: Bool) -> Bool {
    switch status {
    case .idle, .loading:
      return false
    case .ended, .failed:
      return true
    case .playing, .paused, .seeking:
      return hasFirstFrame && !isAwaitingDisplaySwitch
    }
  }

  /// 等到可以揭开遮挡，期间遮挡样子有变就交给 `show`；调用方先按 `.loading` 盖上。
  /// 播放器就绪后（开了「匹配内容」时再留一小段时间给电视开始切换）、切换结束、超时或任务被取消时返回。
  static func wait(
    for display: (any DisplayModeSwitching)?,
    timing: Timing = Timing(),
    show: (StartupCover) -> Void = { _ in },
    isPlayerSettled: () -> Bool
  ) async {
    let clock = ContinuousClock()
    let start = clock.now
    let matchesContent = display?.isDisplayCriteriaMatchingEnabled == true
    var cover = StartupCover.loading
    /// 正在进行的切换从何时开始。
    var switchStart: ContinuousClock.Instant?
    /// 最近一次切换何时结束。
    var lastSwitchEnd: ContinuousClock.Instant?
    /// 播放器从何时起一直是就绪的。
    var settledSince: ContinuousClock.Instant?

    func present(_ next: StartupCover) {
      guard next != cover else { return }
      cover = next
      show(next)
    }

    while !Task.isCancelled {
      let now = clock.now
      if display?.isDisplayModeSwitchInProgress == true {
        let began = switchStart ?? now
        switchStart = began
        present(.blank)
        if began.duration(to: now) >= timing.switchTimeout { return }
      } else {
        if switchStart != nil {
          switchStart = nil
          lastSwitchEnd = now
        }
        if isPlayerSettled() {
          let since = settledSince ?? now
          settledSince = since
          if !matchesContent || since.duration(to: now) >= timing.settle { return }
        } else {
          settledSince = nil
          if start.duration(to: now) >= timing.loadingTimeout { return }
        }
        if let end = lastSwitchEnd, end.duration(to: now) >= timing.loadingResumeDelay {
          present(.loading)
        }
      }
      guard (try? await Task.sleep(for: timing.poll)) != nil else { return }
    }
  }
}
