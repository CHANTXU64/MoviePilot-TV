import Foundation
import MPVUI

/// mpv 播放失败时给用户看的提示，按 `MPVPlayerError` 类别和 libmpv 错误码区分。
/// 完整错误照旧写日志；这里只给出用户能理解、和真实原因一致的一句话。
/// 提示经全局通知胶囊单行显示，保持简短，不要写成多行长句。
nonisolated enum PlaybackFailureMessage {
  static func message(for error: MPVPlayerError) -> String {
    switch error {
    case .nativeVideoOutputUnavailable(let reason):
      return mentionsDolbyVision(reason) ? dolbyVisionUnavailable : nativeOutputUnavailable
    case .loadFailed(let code, _):
      // 只有 LOADING_FAILED 来自打不开片源地址（mpv `stream_create` 失败），这时才提网络和服务器。
      // MPVUI 也把 `pause`、`vid` 属性和 `loadfile` 命令被拒的返回码装进 loadFailed，那些不是网络问题。
      if code == LibmpvError.loadingFailed { return sourceUnreachable }
      return message(forMediaCode: code) ?? loadFailedGeneric
    case .playbackFailed(let code, _):
      // 起播后 mpv 把错误码清零，播放中断网会按读到文件末尾处理，不会走到这里，所以这里不提网络。
      return message(forMediaCode: code) ?? playbackInterrupted
    case .clientCreationFailed, .clientUnavailable, .initializationFailed:
      return playerInitializationFailed
    default:
      return playbackFailedGeneric
    }
  }

  static let dolbyVisionUnavailable = "该片源为杜比视界格式，这台设备无法硬件解码"
  static let nativeOutputUnavailable = "该片源的画面格式无法在这台设备上原生播放"
  static let sourceUnreachable = "无法从媒体服务器读取片源，请检查网络和服务器状态"
  static let unknownFormat = "无法识别该片源的格式，文件可能已损坏"
  static let nothingToPlay = "该片源中没有可以播放的音视频"
  static let videoOutputFailed = "视频输出初始化失败，无法播放该片源"
  static let audioOutputFailed = "音频输出初始化失败，无法播放该片源"
  static let loadFailedGeneric = "读取片源失败，无法播放该影片"
  static let playbackInterrupted = "播放意外中断，无法继续播放该影片"
  static let playerInitializationFailed = "播放器初始化失败，请稍后重试"
  static let playbackFailedGeneric = "播放器出错，无法播放该影片"

  /// 读取与播放阶段共有的、能指明原因的 libmpv 错误码；其余（如 GENERIC 和各类 API 错误）返回 nil，由调用方给通用提示。
  private static func message(forMediaCode code: Int32) -> String? {
    switch code {
    case LibmpvError.unknownFormat: unknownFormat
    case LibmpvError.nothingToPlay: nothingToPlay
    case LibmpvError.voInitFailed: videoOutputFailed
    case LibmpvError.aoInitFailed: audioOutputFailed
    default: nil
    }
  }

  /// MPVUI 原生输出拒绝杜比视界时的原因文本都来自其补丁：mpv `0005-avfoundation-native-video`
  /// （含 `Dolby Vision` 或 `P7 conversion`）与 ffmpeg `0005`/`0006`（含 `Dolby Vision` 或 `RPU`）。
  /// 另外两条色彩元数据原因不属于杜比视界。
  private static func mentionsDolbyVision(_ reason: String) -> Bool {
    reason.range(of: #"(?i)dolby vision|\bRPU\b|\bP7 conversion\b"#, options: .regularExpression) != nil
  }
}

/// libmpv `client.h` 中 `mpv_error` 的取值（MPV_CLIENT_API_VERSION 2.5）。MPVUI 不导出 libmpv 模块，这里按头文件照抄。
/// 各码在 end-file 事件中的来源（mpv `player/loadfile.c`、`video.c`、`audio.c`）：
/// - LOADING_FAILED：片源流打不开（`demux_open_url` 里 `stream_create` 返回空）。
/// - UNKNOWN_FORMAT：流已打开，但没有分离器认得这种格式，或文件损坏。
/// - NOTHING_TO_PLAY：没有选中任何音视频流，或什么都没播出来。
/// - VO_INIT_FAILED / AO_INIT_FAILED：视频输出、音频设备初始化失败。
nonisolated enum LibmpvError {
  static let loadingFailed: Int32 = -13
  static let aoInitFailed: Int32 = -14
  static let voInitFailed: Int32 = -15
  static let nothingToPlay: Int32 = -16
  static let unknownFormat: Int32 = -17
}
