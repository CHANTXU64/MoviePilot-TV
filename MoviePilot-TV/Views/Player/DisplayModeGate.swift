import AVKit
import UIKit

/// 电视显示模式（tvOS「匹配内容」）的状态；测试用替身实现。
@MainActor
protocol DisplayModeSwitching: AnyObject {
  var isDisplayCriteriaMatchingEnabled: Bool { get }
  var isDisplayModeSwitchInProgress: Bool { get }
}

extension AVDisplayManager: DisplayModeSwitching {}

/// 起播后等电视切好显示模式，期间播放界面整屏盖黑。
/// 开了「匹配内容」时，播放器按读出的片源格式向电视申请帧率和动态范围，电视随即切换 HDMI 模式并黑屏约 1 秒，
/// 切换前露出的画面或控件就像闪了一下。AetherEngine 在交给系统播放器之前申请、切换期间压住起播；
/// 这里只决定何时揭开遮挡，不控制播放。
@MainActor
enum DisplayModeGate {
  struct Timing {
    /// 播放器就绪后，留给电视开始切换的时间；这段时间里没开始切换，就当不用切。
    var settle: Duration = .milliseconds(200)
    /// 最长等待，从起播算起。超时就揭开：宁可闪一下，也不能一直黑屏。
    var timeout: Duration = .seconds(8)
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

  /// 等到可以揭开遮挡：播放器就绪后一小段时间内没开始切换，或切换已结束，或超时，或任务被取消。
  static func wait(
    for display: any DisplayModeSwitching, timing: Timing = Timing(), isPlayerSettled: () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timing.timeout)

    func pause() async -> Bool {
      guard clock.now < deadline, (try? await Task.sleep(for: timing.poll)) != nil else { return false }
      return clock.now < deadline
    }

    while !isPlayerSettled() {
      guard await pause() else { return }
    }
    let settleEnd = clock.now.advanced(by: timing.settle)
    while !display.isDisplayModeSwitchInProgress, clock.now < settleEnd {
      guard await pause() else { return }
    }
    while display.isDisplayModeSwitchInProgress {
      guard await pause() else { return }
    }
  }
}
