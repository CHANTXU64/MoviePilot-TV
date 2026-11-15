import XCTest

@testable import MoviePilot_TV

/// 开播前等电视切显示模式的规则：播放器就绪后，没开始切换就很快放行，在切换就等切完，卡住了到时间也放行。
@MainActor
final class DisplayModeGateTests: XCTestCase {
  private final class FakeDisplay: DisplayModeSwitching {
    var isDisplayCriteriaMatchingEnabled = true
    var isDisplayModeSwitchInProgress = false
  }

  private final class Flag {
    var value = false
  }

  private let timing = DisplayModeGate.Timing(
    settle: .milliseconds(150), timeout: .seconds(3), poll: .milliseconds(10))
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
    XCTAssertLessThan(elapsed, timing.timeout, "不用切换时不等到超时")
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
    let short = DisplayModeGate.Timing(settle: .milliseconds(50), timeout: .milliseconds(300), poll: .milliseconds(10))
    let start = clock.now
    await DisplayModeGate.wait(for: display, timing: short) { true }
    let elapsed = start.duration(to: clock.now)

    XCTAssertTrue(display.isDisplayModeSwitchInProgress)
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(300), "到超时才放行")
    XCTAssertLessThan(elapsed, .seconds(2), "超时后不再等，不能一直黑屏")
  }

  func testGivesUpWhenPlayerNeverSettles() async {
    let short = DisplayModeGate.Timing(settle: .milliseconds(50), timeout: .milliseconds(300), poll: .milliseconds(10))
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
    let slow = DisplayModeGate.Timing(settle: .milliseconds(50), timeout: .seconds(30), poll: .milliseconds(10))
    let start = clock.now
    let task = Task { await DisplayModeGate.wait(for: display, timing: slow) { true } }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await task.value

    XCTAssertLessThan(start.duration(to: clock.now), .seconds(5), "退出播放时立即停止等待")
  }
}
