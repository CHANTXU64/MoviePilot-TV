import XCTest

@testable import MoviePilot_TV

/// 遥控器播放键、触控板中央和左右键快退快进的规则，与 Apple TV 系统播放器一致。
@MainActor
final class PlayerRemoteCommandTests: XCTestCase {
  private typealias ViewState = VideoPlayer.ViewState
  private typealias Scan = ViewState.Scan

  private func action(
    _ button: ViewState.PlaybackButton,
    presentation: ViewState.Presentation = .hidden,
    scrubbing: Bool = false,
    progressFocused: Bool = false,
    overlayFocused: Bool = false,
    canControl: Bool = true,
    paused: Bool = false
  ) -> ViewState.PlaybackButtonAction {
    ViewState.action(
      for: button,
      presentation: presentation,
      isScrubbing: scrubbing,
      isProgressBarFocused: progressFocused,
      isOverlayActionFocused: overlayFocused,
      canControlPlayback: canControl,
      isPaused: paused
    )
  }

  // MARK: 播放/暂停键、触控板中央

  func testPlayPauseWhileWatchingPausesAtOnceAndShowsControls() {
    XCTAssertEqual(action(.playPause), .pause(showsControls: true), "控制条收起时按一下就暂停，不只是呼出控制条")
    XCTAssertEqual(
      action(.playPause, presentation: .progress, progressFocused: true), .pause(showsControls: true),
      "只显示进度条时暂停，呼出完整控制条")
    XCTAssertEqual(action(.playPause, presentation: .controls, progressFocused: true), .pause(showsControls: false))
    XCTAssertEqual(action(.playPause, paused: true), .play, "控制条收起时暂停着，按一下接着播")
    XCTAssertEqual(action(.playPause, presentation: .controls, paused: true), .play)
    XCTAssertEqual(
      action(.playPause, presentation: .supplement("info")), .pause(showsControls: false), "开着面板也能暂停")
    XCTAssertEqual(action(.playPause, presentation: .supplement("info"), paused: true), .play)
  }

  func testSelectTogglesPlaybackLikeTheSystemPlayer() {
    XCTAssertEqual(action(.select), .pause(showsControls: true), "控制条收起时按触控板中央暂停")
    XCTAssertEqual(action(.select, paused: true), .play)
    XCTAssertEqual(action(.select, presentation: .controls, progressFocused: true), .pause(showsControls: false))
    XCTAssertEqual(
      action(.select, presentation: .progress), .pause(showsControls: true),
      "跳转后只显示进度条、焦点还没落到进度条上，按中央照样暂停")
    XCTAssertEqual(action(.select, presentation: .progress, paused: true), .play)
    XCTAssertEqual(action(.select, presentation: .controls), .forwardToFocusedControl, "聚焦在工具栏按钮上时按下按钮")
    XCTAssertEqual(action(.select, presentation: .supplement("chapters")), .forwardToFocusedControl, "面板里按下卡片")
    XCTAssertEqual(action(.select, overlayFocused: true), .forwardToFocusedControl, "聚焦在「跳过片头」时按下它")
    XCTAssertEqual(action(.playPause, overlayFocused: true), .pause(showsControls: true), "播放键不按画面上的按钮")
  }

  func testBothButtonsResumeFromTheScrubbedPosition() {
    XCTAssertEqual(
      action(.playPause, presentation: .progress, scrubbing: true, progressFocused: true, paused: true), .commitScrub,
      "拖动或快退快进中按播放键从新位置播放，不是取消")
    XCTAssertEqual(
      action(.select, presentation: .progress, scrubbing: true, progressFocused: true, paused: true), .commitScrub)
    XCTAssertEqual(action(.playPause, scrubbing: true, canControl: false), .ignore)
  }

  func testButtonsBeforePlaybackIsReady() {
    XCTAssertEqual(action(.playPause, canControl: false), .ignore)
    XCTAssertEqual(action(.select, canControl: false), .showControls, "还不能控制播放时，按中央仍呼出控制条")
    XCTAssertEqual(action(.select, presentation: .controls, progressFocused: true, canControl: false), .ignore)
  }

  // MARK: 快退快进

  func testPressingAgainCyclesSpeedsAndReverses() {
    var scan = Scan.next(after: nil, pressing: .forward)
    XCTAssertEqual(scan, Scan(direction: .forward))
    XCTAssertEqual(scan.rate, 2)
    scan = Scan.next(after: scan, pressing: .forward)
    XCTAssertEqual(scan.rate, 3)
    scan = Scan.next(after: scan, pressing: .forward)
    XCTAssertEqual(scan.rate, 4)
    scan = Scan.next(after: scan, pressing: .forward)
    XCTAssertEqual(scan.rate, 2, "4× 之后回到 2×")

    XCTAssertEqual(
      Scan.next(after: Scan(direction: .forward, level: 2), pressing: .backward), Scan(direction: .backward),
      "快进中按左键，从 2× 开始快退")
  }

  func testScanMovesAtItsRateAndStopsAtTheEnds() {
    let runtime = Duration.seconds(600)

    let forward = Scan(direction: .forward, level: 2)
    XCTAssertEqual(forward.position(after: .seconds(1), from: .seconds(100), runtime: runtime), .seconds(104))
    XCTAssertFalse(forward.hasReachedBound(.seconds(104), runtime: runtime))
    let nearEnd = forward.position(after: .seconds(10), from: .seconds(590), runtime: runtime)
    XCTAssertEqual(nearEnd, .seconds(598), "快进停在片尾前 2 秒，跳到最末尾会被当成播完")
    XCTAssertTrue(forward.hasReachedBound(nearEnd, runtime: runtime))

    let backward = Scan(direction: .backward)
    XCTAssertEqual(backward.position(after: .seconds(1), from: .seconds(100), runtime: runtime), .seconds(98))
    let start = backward.position(after: .seconds(10), from: .seconds(5), runtime: runtime)
    XCTAssertEqual(start, .zero)
    XCTAssertTrue(backward.hasReachedBound(start, runtime: runtime))

    XCTAssertEqual(Scan.upperBound(runtime: runtime), .seconds(598), "拖动中点左右键挪位置也停在片尾前 2 秒")

    let short = Scan(direction: .forward)
    let shortEnd = short.position(after: .seconds(1), from: .zero, runtime: .seconds(1))
    XCTAssertEqual(shortEnd, .zero, "比 2 秒还短的片子不往前走")
    XCTAssertTrue(short.hasReachedBound(shortEnd, runtime: .seconds(1)))
  }
}
