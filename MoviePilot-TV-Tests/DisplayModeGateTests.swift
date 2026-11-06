import AVKit
import CoreMedia
import XCTest

@testable import MoviePilot_TV

/// 开播前等电视切显示模式的规则：播放器就绪后，没开始切换就很快放行，在切换就等切完，卡住了到时间也放行。
@MainActor
final class DisplayModeGateTests: XCTestCase {
  private final class FakeDisplay: DisplayModeSwitching {
    var isDisplayCriteriaMatchingEnabled = true
    var isDisplayModeSwitchInProgress = false
    var preferredDisplayCriteria: AVDisplayCriteria?
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

/// 开播前按 Emby 片源信息申请的显示模式，要和 MPVUI 开播后申请的一致，否则电视会再切一次。
final class DisplayModeHintTests: XCTestCase {
  private func source(_ video: String) throws -> EmbyMediaSource {
    try JSONDecoder().decode(
      EmbyMediaSource.self,
      from: Data(#"{"Id":"s","Container":"mkv","MediaStreams":[{"Type":"Audio","Codec":"truehd"},\#(video)]}"#.utf8))
  }

  private func extensionValue(_ description: CMFormatDescription, _ key: CFString) -> CFPropertyList? {
    CMFormatDescriptionGetExtension(description, extensionKey: key)
  }

  func testHDR10FilmAt23976() throws {
    // 《星际穿越》：4K HDR10，23.976 帧。
    let hint = try XCTUnwrap(DisplayModeHint(source: source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":2160,"RealFrameRate":23.976025,"VideoRange":"HDR 10","ExtendedVideoType":"Hdr10"}"#)))
    XCTAssertEqual(hint.refreshRate, Float(24000.0 / 1001), "23.976 不能当成 24")
    XCTAssertEqual(hint.range, .hdr10)
    let description = try XCTUnwrap(hint.makeFormatDescription())
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_HEVC)
    XCTAssertEqual(
      extensionValue(description, kCMFormatDescriptionExtension_TransferFunction) as? String,
      kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
    XCTAssertNotNil(hint.makeCriteria())
  }

  func testDolbyVisionProfile5() throws {
    // 《美国队长3》：杜比视界 Profile 5，按杜比视界编码申请，并带上配置记录（4K 24 帧是 6 级）。
    let hint = try XCTUnwrap(DisplayModeHint(source: source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":2160,"RealFrameRate":23.976025,"VideoRange":"DolbyVision","ExtendedVideoType":"DolbyVision","ExtendedVideoSubType":"DoviProfile50"}"#)))
    XCTAssertEqual(hint.range, .dolbyVision(profile: 5, compatibilityID: 0))
    let description = try XCTUnwrap(hint.makeFormatDescription())
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_DolbyVisionHEVC)
    let atoms = try XCTUnwrap(
      extensionValue(description, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data])
    let record = try XCTUnwrap(atoms["dvcC"])
    XCTAssertEqual(Array(record.prefix(5)), [1, 0, 0x0A, 0x35, 0x00], "版本 1.0、Profile 5、6 级、有 RPU 和基础层")
  }

  func testDolbyVisionProfile81UsesDvvC() throws {
    let hint = try XCTUnwrap(DisplayModeHint(source: source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":2160,"RealFrameRate":24,"ExtendedVideoType":"DolbyVision","ExtendedVideoSubType":"DoviProfile81"}"#)))
    XCTAssertEqual(hint.range, .dolbyVision(profile: 8, compatibilityID: 1))
    let description = try XCTUnwrap(hint.makeFormatDescription())
    let atoms = extensionValue(description, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data]
    XCTAssertEqual(atoms?["dvvC"]?[4], 0x10, "兼容 ID 1")
  }

  func testSeriesAt25AndSDRVideo() throws {
    // 《小城良方》：HDR10，25 帧。
    let series = try XCTUnwrap(DisplayModeHint(source: source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":1608,"RealFrameRate":25,"VideoRange":"HDR 10","ExtendedVideoType":"Hdr10"}"#)))
    XCTAssertEqual(series.refreshRate, 25)
    let sdr = try XCTUnwrap(DisplayModeHint(source: source(
      #"{"Type":"Video","Codec":"h264","Width":1920,"Height":1080,"AverageFrameRate":29.97003,"VideoRange":"SDR"}"#)))
    XCTAssertEqual(sdr.range, .sdr)
    XCTAssertEqual(sdr.refreshRate, Float(30000.0 / 1001), "实际帧率缺失时用平均帧率")
    let description = try XCTUnwrap(sdr.makeFormatDescription())
    XCTAssertEqual(
      extensionValue(description, kCMFormatDescriptionExtension_TransferFunction) as? String,
      kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
  }

  func testUncertainSourcesAreLeftToThePlayer() throws {
    // 认不准就不提前申请：杜比视界 Profile 7、不认识的编码、缺帧率或分辨率。
    XCTAssertNil(DisplayModeHint(source: try source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":2160,"RealFrameRate":23.976,"ExtendedVideoType":"DolbyVision","ExtendedVideoSubType":"DoviProfile76"}"#)))
    XCTAssertNil(DisplayModeHint(source: try source(
      #"{"Type":"Video","Codec":"mpeg2video","Width":720,"Height":480,"RealFrameRate":29.97,"VideoRange":"SDR"}"#)))
    XCTAssertNil(DisplayModeHint(source: try source(
      #"{"Type":"Video","Codec":"hevc","Width":3840,"Height":2160,"VideoRange":"HDR 10"}"#)))
    XCTAssertNil(DisplayModeHint(source: try source(
      #"{"Type":"Video","Codec":"hevc","RealFrameRate":24,"VideoRange":"HDR 10"}"#)))
  }
}
