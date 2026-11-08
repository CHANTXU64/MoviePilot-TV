import AVKit
import CoreMedia
import MPVUI

/// 电视显示模式（tvOS「匹配内容」）的状态；测试用替身实现。
@MainActor
protocol DisplayModeSwitching: AnyObject {
  var isDisplayCriteriaMatchingEnabled: Bool { get }
  var isDisplayModeSwitchInProgress: Bool { get }
  var preferredDisplayCriteria: AVDisplayCriteria? { get set }
}

extension AVDisplayManager: DisplayModeSwitching {}

/// 起播后等电视切好显示模式，期间播放界面整屏盖黑。
/// 开了「匹配内容」时，MPVUI 读出视频格式后才向系统申请帧率和动态范围，电视随即切换 HDMI 模式并黑屏约 1 秒，
/// 切换前露出的画面或控件就像闪了一下（Swiftfin 的系统播放器是先切模式再出画面）。这里只决定何时揭开遮挡，不控制播放。
@MainActor
enum DisplayModeGate {
  struct Timing {
    /// 播放器就绪后，留给 MPVUI 提交要求、系统开始切换的时间；这段时间里没开始切换，就当不用切。
    var settle: Duration = .milliseconds(600)
    /// 最长等待，从起播算起。超时就揭开：宁可闪一下，也不能一直黑屏。
    var timeout: Duration = .seconds(8)
    var poll: Duration = .milliseconds(50)
  }

  /// MPVUI 会申请显示模式时才算就绪：文件已载入，且不在跳转或缓冲中。杜比视界片源还要等 MPVUI 判定能否原样输出，
  /// 它据此决定向电视要杜比视界还是 HDR 模式。出错或已结束也算就绪，交给播放失败的流程处理。
  static func isSettled(_ player: MPVPlayer) -> Bool {
    switch player.state {
    case .idle, .loading, .seeking, .buffering:
      return false
    case .ended, .stopped, .failed:
      return true
    case .ready, .playing, .paused:
      let status = player.dolbyVisionStatus
      return status.sourceProfile == nil || status.nativeValidation != .unknown
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

/// 按片源信息提前向电视申请的显示模式（帧率、动态范围）。各服务器适配器把片源信息转成它，见 `ServerMediaSource.displayModeHint`；
/// Emby 片源由 `init(source:)` 解析。
/// MPVUI 要等开播、读出视频格式后才申请，电视这时切换会让已经出声的播放停一下。开播前先按这里申请，
/// 等 MPVUI 再申请同一个模式时电视已经切好，不会再切。规则照 MPVUI `MPVDisplayMatchingContent`：
/// 帧率按标准帧率族取（23.976 不当 24），杜比视界只认 MPVUI 能原样输出的 Profile 5、8.1、8.4。
/// 认不准的片源（未知编码、杜比视界 Profile 7 等）返回 nil，交给 MPVUI 自己申请。
nonisolated struct DisplayModeHint: Equatable {
  enum DynamicRange: Equatable {
    case sdr
    case hdr10
    case hlg
    case dolbyVision(profile: Int, compatibilityID: Int)
  }

  let width: Int32
  let height: Int32
  let refreshRate: Float
  let codec: CMVideoCodecType
  let range: DynamicRange

  init?(source: EmbyMediaSource) {
    guard let video = source.mediaStreams.first(where: { $0.type?.lowercased() == "video" }),
      let width = video.width.flatMap({ Int32(exactly: $0) }), width > 0,
      let height = video.height.flatMap({ Int32(exactly: $0) }), height > 0,
      let refreshRate = Self.refreshRate(for: video.frameRate),
      let codec = Self.codecType(for: video.codec),
      let range = Self.dynamicRange(of: video)
    else { return nil }
    if case .dolbyVision = range, codec != kCMVideoCodecType_HEVC { return nil }
    self.width = width
    self.height = height
    self.refreshRate = refreshRate
    self.codec = codec
    self.range = range
  }

  /// 标准帧率族（含 NTSC 的 1000/1001），与 MPVUI 相同：差不到 0.001 就取标准值。
  static func refreshRate(for framesPerSecond: Double?) -> Float? {
    guard let value = framesPerSecond, value.isFinite, value > 0, value <= 240 else { return nil }
    let standard = [
      24000.0 / 1001, 24, 25, 30000.0 / 1001, 30, 48000.0 / 1001, 48, 50, 60000.0 / 1001, 60, 100,
      120_000.0 / 1001, 120,
    ]
    return Float(standard.first { abs($0 - value) < 0.001 } ?? value)
  }

  private static func codecType(for codec: String?) -> CMVideoCodecType? {
    switch codec?.lowercased() {
    case "h264", "avc", "avc1": kCMVideoCodecType_H264
    case "hevc", "h265", "hev1", "hvc1", "dvh1", "dvhe": kCMVideoCodecType_HEVC
    case "av1", "av01": kCMVideoCodecType_AV1
    case "vp9", "vp09": kCMVideoCodecType_VP9
    default: nil
    }
  }

  private static func dynamicRange(of video: EmbyMediaStream) -> DynamicRange? {
    let extended = video.extendedVideoType?.lowercased() ?? ""
    let range = video.videoRange?.lowercased() ?? ""
    if extended == "dolbyvision" || range == "dolbyvision" {
      switch video.extendedVideoSubType?.lowercased() {
      case "doviprofile50": return .dolbyVision(profile: 5, compatibilityID: 0)
      case "doviprofile81": return .dolbyVision(profile: 8, compatibilityID: 1)
      case "doviprofile84": return .dolbyVision(profile: 8, compatibilityID: 4)
      default: return nil
      }
    }
    if extended.hasPrefix("hdr10") || range.contains("hdr 10") || range.contains("hdr10") { return .hdr10 }
    if extended == "hyperloggamma" || extended == "hlg" || range.contains("hlg") { return .hlg }
    if range == "sdr" || extended == "none" || (extended.isEmpty && range.isEmpty) { return .sdr }
    return nil
  }

  /// 杜比视界等级：按每秒像素数取能容纳的最低等级（Dolby Vision Levels 表）。
  private var dolbyVisionLevel: Int {
    let pixelRate = Double(width) * Double(height) * Double(refreshRate)
    let limits: [Double] = [
      22_118_400, 27_648_000, 49_766_400, 62_208_000, 124_416_000, 199_065_600, 248_832_000,
      398_131_200, 497_664_000, 995_328_000, 995_328_000, 1_990_656_000, 3_981_312_000,
    ]
    return (limits.firstIndex { pixelRate <= $0 + 1 } ?? limits.count - 1) + 1
  }

  func makeFormatDescription() -> CMVideoFormatDescription? {
    var extensions: [String: Any] = [:]
    var codecType = codec
    switch range {
    case .sdr:
      extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_709_2
      extensions[kCMFormatDescriptionExtension_TransferFunction as String] =
        kCMFormatDescriptionTransferFunction_ITU_R_709_2
      extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
    case .hdr10, .hlg, .dolbyVision:
      extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_2020
      extensions[kCMFormatDescriptionExtension_TransferFunction as String] =
        range == .hlg
        ? kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG : kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
      extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
      extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] = 10
    }
    if case .dolbyVision(let profile, let compatibilityID) = range {
      // 杜比视界配置记录 v1.0（与 MPVUI 相同：有 RPU 和基础层、无增强层）。
      let flags = UInt16(profile << 9 | dolbyVisionLevel << 3 | 0b101)
      let record = Data(
        [1, 0, UInt8(flags >> 8), UInt8(flags & 0xFF), UInt8(compatibilityID << 4)] + Array(repeating: 0, count: 19))
      extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] = [
        profile > 7 ? "dvvC" : "dvcC": record
      ]
      codecType = kCMVideoCodecType_DolbyVisionHEVC
    }
    var description: CMVideoFormatDescription?
    let status = CMVideoFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, codecType: codecType, width: width, height: height,
      extensions: extensions as CFDictionary, formatDescriptionOut: &description)
    return status == noErr ? description : nil
  }

  func makeCriteria() -> AVDisplayCriteria? {
    makeFormatDescription().map { AVDisplayCriteria(refreshRate: refreshRate, formatDescription: $0) }
  }
}
