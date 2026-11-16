import AetherEngine
import Foundation

/// 播放失败时给用户看的提示，按引擎的失败类别（`PlaybackErrorKind`）和底层错误区分。
/// 完整错误照旧写日志；这里只给出用户能理解、和真实原因一致的一句话。不按引擎的错误原文分类：
/// 原生路径上那段文字是系统按设备语言翻译过的。
/// 提示经全局通知胶囊单行显示，保持简短，不要写成多行长句。
nonisolated enum PlaybackFailureMessage {
  /// 播放器没能创建时用的类别（不是引擎的类别）。
  static let initializationKind = "playerInitializationFailed"

  static func message(for failure: PlaybackFailure) -> String {
    if failure.kind == initializationKind { return playerInitializationFailed }
    switch failure.kind.map(PlaybackErrorKind.init(rawValue:)) {
    case .dolbyVisionRequiresHardware?:
      return dolbyVisionUnavailable
    case .sourceRefused?:
      return sourceRefused
    case .sourceRateLimited?:
      return sourceRateLimited
    case .sourceCertificateRejected?:
      return certificateRejected
    case .sourceOpenFailed?:
      // 只有底层是网络错误时才提网络；FFmpeg 认不出数据是格式问题。
      if isNetworkFailure(failure) { return sourceUnreachable }
      if failure.ffmpegErrorCode == invalidDataCode { return unknownFormat }
      return loadFailedGeneric
    case .vodSourceFailed?:
      return isNetworkFailure(failure) ? sourceInterrupted : playbackInterrupted
    case .nativeItemFailed?:
      return isNetworkFailure(failure) ? sourceInterrupted : formatUnsupported
    case .noPlayableTrackWithinBudget?, .masterPlaylistRejected?:
      return formatUnsupported
    case .softwarePipelineFailed?:
      return decodeFailed
    case .audioBridgeProducedNoOutput?:
      return audioUndecodable
    case .audioTrackSwitchFailed?:
      return audioSwitchFailed
    case .storageExhausted?:
      return storageExhausted
    case .reloadFailed?:
      return playbackInterrupted
    default:
      return playbackFailedGeneric
    }
  }

  static let dolbyVisionUnavailable = "该片源为杜比视界格式，这台设备无法硬件解码"
  static let sourceUnreachable = "无法从媒体服务器读取片源，请检查网络和服务器状态"
  static let sourceInterrupted = "读取片源中断，请检查网络和服务器状态"
  static let sourceRefused = "媒体服务器拒绝提供片源，请检查服务器状态"
  static let sourceRateLimited = "媒体服务器暂时限制访问，请稍后重试"
  static let certificateRejected = "媒体服务器的证书不受信任，无法读取片源"
  static let unknownFormat = "无法识别该片源的格式，文件可能已损坏"
  static let formatUnsupported = "这台设备无法播放该片源的格式"
  static let decodeFailed = "解码失败，无法播放该片源"
  static let audioUndecodable = "该片源的音轨无法解码，无法播放"
  static let audioSwitchFailed = "切换音轨失败，无法继续播放"
  static let storageExhausted = "设备存储空间不足，无法播放"
  static let loadFailedGeneric = "读取片源失败，无法播放该影片"
  static let playbackInterrupted = "播放意外中断，无法继续播放该影片"
  static let playerInitializationFailed = "播放器初始化失败，请稍后重试"
  static let playbackFailedGeneric = "播放器出错，无法播放该影片"

  /// 片源里有轨道用了这版 FFmpeg 解不开的封装压缩（MKV 的 zlib 压缩轨）时，可能因此失败的类别：
  /// 解码、出画面阶段的失败。打不开片源、服务器拒绝等另有原因，不归到压缩上。
  static func mayBeCausedByCompressedTracks(_ failure: PlaybackFailure) -> Bool {
    switch failure.kind.map(PlaybackErrorKind.init(rawValue:)) {
    case .nativeItemFailed?, .softwarePipelineFailed?, .audioBridgeProducedNoOutput?, .noPlayableTrackWithinBudget?,
      .masterPlaylistRejected?:
      return !isNetworkFailure(failure)
    default:
      return false
    }
  }

  /// FFmpeg 的 `AVERROR_INVALIDDATA`（`FFERRTAG('I','N','D','A')`）：数据不是认得的格式。
  static let invalidDataCode = -1_094_995_529

  private static func isNetworkFailure(_ failure: PlaybackFailure) -> Bool {
    failure.underlyingDomain == NSURLErrorDomain
  }
}
