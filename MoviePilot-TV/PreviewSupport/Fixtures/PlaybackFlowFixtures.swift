#if DEBUG
import Foundation

/// 播放呈现流程（解析中 / 续播询问）的预览 fixture。
///
/// 只构造真实 `PlaybackCoordinator.ResumePrompt` 需要的展示数据（标题、续播位置），
/// 不发起真实起播，也不访问媒体服务器。
@MainActor
enum UIPreviewPlaybackFlowFixtures {
  static func resumePrompt(position: Double = 754) -> PlaybackCoordinator.ResumePrompt {
    let item = UIPlayerPreviewFixtures.item()
    let sources = UIPlayerPreviewFixtures.sources()
    let stream = PreparedStream(
      item: item,
      source: sources[0],
      sources: sources,
      playSessionID: "ui-preview-resume",
      streamURL: URL(string: "http://moviepilot-ui-preview.local:3000/ui-preview/stream.mkv")!
    )
    let prepared = PreparedPlayback(
      connection: UIPlayerPreviewConnection(item: item, sources: sources),
      stream: stream,
      episode: nil
    )
    return PlaybackCoordinator.ResumePrompt(prepared: prepared, position: position)
  }
}
#endif
