import XCTest

@testable import MoviePilot_TV

/// 起播遮挡的规则：播放器就绪后，没开始切换就很快放行，在切换就等切完，卡住了到时间也放行；
/// 准备期间转圈，切换期间纯黑，切完很快就绪时直接揭开、不再转圈。
@MainActor
final class DisplayModeGateTests: XCTestCase {
  private final class FakeDisplay: DisplayModeSwitching {
    var isDisplayCriteriaMatchingEnabled = true
    var isDisplayModeSwitchInProgress = false
  }

  private final class Flag {
    var value = false
  }

  /// 记下遮挡样子的每次变化。
  private final class Covers {
    var shown: [StartupCover] = []
  }

  private let timing = DisplayModeGate.Timing(
    settle: .milliseconds(150), loadingResumeDelay: .milliseconds(300), switchTimeout: .seconds(3),
    loadingTimeout: .seconds(3), poll: .milliseconds(10))
  private let clock = ContinuousClock()

  func testWaitsForPlayerThenReturnsWhenNoSwitchStarts() async {
    let display = FakeDisplay()
    let settled = Flag()
    Task {
      try? await Task.sleep(for: .milliseconds(100))
      settled.value = true
    }
    let start = clock.now
    await DisplayModeGate.wait(for: display, timing: timing) { settled.value }
    let elapsed = start.duration(to: clock.now)

    XCTAssertTrue(settled.value, "播放器就绪前不放行")
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(250), "就绪后还要留出系统开始切换的时间")
    XCTAssertLessThan(elapsed, timing.loadingTimeout, "不用切换时不等到超时")
  }

  /// 没开「匹配内容」不会切换，就绪就揭开，不留等切换的时间。
  func testReturnsOnceSettledWithoutContentMatching() async {
    let display = FakeDisplay()
    display.isDisplayCriteriaMatchingEnabled = false
    let slowSettle = DisplayModeGate.Timing(
      settle: .seconds(2), switchTimeout: .seconds(3), loadingTimeout: .seconds(3), poll: .milliseconds(10))
    let covers = Covers()
    let start = clock.now
    await DisplayModeGate.wait(for: display, timing: slowSettle, show: { covers.shown.append($0) }) { true }

    XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    XCTAssertEqual(covers.shown, [], "一直是准备中的转圈")

    let startWithoutDisplay = clock.now
    await DisplayModeGate.wait(for: nil, timing: slowSettle) { true }
    XCTAssertLessThan(startWithoutDisplay.duration(to: clock.now), .seconds(1), "拿不到显示管理器时同样不等")
  }

  /// 切换期间纯黑；切完播放器已就绪就直接揭开，中间不再出转圈。
  func testSwitchBlanksThenRevealsWithoutSpinner() async {
    let display = FakeDisplay()
    let covers = Covers()
    Task {
      try? await Task.sleep(for: .milliseconds(50))
      display.isDisplayModeSwitchInProgress = true
      try? await Task.sleep(for: .milliseconds(200))
      display.isDisplayModeSwitchInProgress = false
    }
    await DisplayModeGate.wait(for: display, timing: timing, show: { covers.shown.append($0) }) { true }

    XCTAssertFalse(display.isDisplayModeSwitchInProgress)
    XCTAssertEqual(covers.shown, [.blank])
  }

  /// 切完了播放器还没就绪（远端慢），过一会儿纯黑换回转圈，不让人对着纯黑干等。
  func testSpinnerReturnsWhenStillLoadingAfterSwitch() async {
    let display = FakeDisplay()
    let covers = Covers()
    let settled = Flag()
    Task {
      display.isDisplayModeSwitchInProgress = true
      try? await Task.sleep(for: .milliseconds(100))
      display.isDisplayModeSwitchInProgress = false
      try? await Task.sleep(for: .milliseconds(600))
      settled.value = true
    }
    await DisplayModeGate.wait(for: display, timing: timing, show: { covers.shown.append($0) }) { settled.value }

    XCTAssertTrue(settled.value)
    XCTAssertEqual(covers.shown, [.blank, .loading])
  }

  /// 切完很快就绪，不换回转圈。
  func testNoSpinnerWhenSettlingSoonAfterSwitch() async {
    let display = FakeDisplay()
    let covers = Covers()
    let settled = Flag()
    var timing = timing
    timing.loadingResumeDelay = .seconds(1)
    Task {
      display.isDisplayModeSwitchInProgress = true
      try? await Task.sleep(for: .milliseconds(100))
      display.isDisplayModeSwitchInProgress = false
      try? await Task.sleep(for: .milliseconds(50))
      settled.value = true
    }
    await DisplayModeGate.wait(for: display, timing: timing, show: { covers.shown.append($0) }) { settled.value }

    XCTAssertEqual(covers.shown, [.blank])
  }

  func testWaitsUntilSwitchEnds() async {
    let display = FakeDisplay()
    let ended = Flag()
    Task {
      try? await Task.sleep(for: .milliseconds(50))
      display.isDisplayModeSwitchInProgress = true
      try? await Task.sleep(for: .milliseconds(400))
      ended.value = true
      display.isDisplayModeSwitchInProgress = false
    }
    await DisplayModeGate.wait(for: display, timing: timing) { true }

    XCTAssertTrue(ended.value, "切换结束后才放行")
  }

  func testGivesUpWhenSwitchNeverEnds() async {
    let display = FakeDisplay()
    display.isDisplayModeSwitchInProgress = true
    let short = DisplayModeGate.Timing(
      settle: .milliseconds(50), switchTimeout: .milliseconds(300), loadingTimeout: .seconds(30),
      poll: .milliseconds(10))
    let start = clock.now
    await DisplayModeGate.wait(for: display, timing: short) { true }
    let elapsed = start.duration(to: clock.now)

    XCTAssertTrue(display.isDisplayModeSwitchInProgress)
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(300), "到超时才放行")
    XCTAssertLessThan(elapsed, .seconds(2), "超时后不再等，不能一直纯黑")
  }

  func testGivesUpWhenPlayerNeverSettles() async {
    let short = DisplayModeGate.Timing(
      settle: .milliseconds(50), switchTimeout: .seconds(30), loadingTimeout: .milliseconds(300),
      poll: .milliseconds(10))
    let start = clock.now
    await DisplayModeGate.wait(for: FakeDisplay(), timing: short) { false }

    XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
  }

  /// 遮挡在首帧备好、且引擎不再为电视切换显示模式压住起播时才揭开；出错或播完不等。
  func testPlayerSettlesOnFirstFrameAfterDisplaySwitch() {
    func settled(_ status: AetherPlayer.Status, firstFrame: Bool = true, awaitingSwitch: Bool = false) -> Bool {
      DisplayModeGate.isSettled(status: status, hasFirstFrame: firstFrame, isAwaitingDisplaySwitch: awaitingSwitch)
    }
    XCTAssertFalse(settled(.loading), "载入中")
    XCTAssertFalse(settled(.idle), "还没开始载入")
    XCTAssertFalse(settled(.playing, firstFrame: false), "首帧还没备好，揭开会露出黑屏")
    XCTAssertFalse(settled(.paused, awaitingSwitch: true), "引擎在等电视切换，揭开会看到切换时的闪烁")
    XCTAssertTrue(settled(.playing))
    XCTAssertTrue(settled(.paused))
    XCTAssertTrue(settled(.failed, firstFrame: false), "出错交给失败流程")
    XCTAssertTrue(settled(.ended, firstFrame: false))
  }

  func testCancellationStopsWaiting() async {
    let display = FakeDisplay()
    display.isDisplayModeSwitchInProgress = true
    let slow = DisplayModeGate.Timing(
      settle: .milliseconds(50), switchTimeout: .seconds(30), loadingTimeout: .seconds(30), poll: .milliseconds(10))
    let start = clock.now
    let task = Task { await DisplayModeGate.wait(for: display, timing: slow) { true } }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await task.value

    XCTAssertLessThan(start.duration(to: clock.now), .seconds(5), "退出播放时立即停止等待")
  }
}
