#if DEBUG
import SwiftUI

/// 播放呈现流程场景：起播解析遮罩。
///
/// 复用真实 `PlaybackPresentationModifier`（黑屏、转圈、禁用底层页面、Menu 取消），
/// 只通过 `PlaybackCoordinator` 的 DEBUG seam 安装呈现状态，不发起真实起播。
@MainActor
enum UIPreviewScenesPlaybackFlow {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "playbackFlow",
      title: "播放流程",
      scenes: [
        .page(
          id: "player.resolve.loading",
          title: "起播解析中",
          note: "按下播放后的准备态：页面淡出为黑屏，正中一个放大的转圈，不带文字；底层页面被禁用，按 Menu 取消准备。预览用守护任务保持这一帧，按 Menu 也会真的取消回首页。",
          environment: .playback
        ) {
          UIPreviewPlaybackFlowScene()
        }
      ]
    )
  }
}

private struct UIPreviewPlaybackFlowScene: View {
  @State private var coordinator: PlaybackCoordinator?

  var body: some View {
    Group {
      if let coordinator {
        UIPreviewTabRootView(tab: .home)
          .playbackPresentation(coordinator)
      } else {
        AppBackground()
      }
    }
    .onAppear {
      guard coordinator == nil else { return }
      let coordinator = PlaybackCoordinator(apiService: APIService.shared)
      coordinator.installUIPreviewResolving()
      self.coordinator = coordinator
    }
    .onDisappear {
      coordinator?.clearUIPreviewResolving()
    }
  }
}
#endif
