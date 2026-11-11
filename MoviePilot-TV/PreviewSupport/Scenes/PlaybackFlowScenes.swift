#if DEBUG
import SwiftUI

/// 播放呈现流程场景：起播解析遮罩与续播询问。
///
/// 复用真实 `PlaybackPresentationModifier`（遮罩、禁用底层页面、确认弹窗），
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
          note: "点击播放后的“正在准备播放…”遮罩与取消按钮，底层页面被禁用，按 Menu 也可取消。",
          environment: .playback
        ) {
          UIPreviewPlaybackFlowScene(presentation: .resolving)
        },
        .page(
          id: "player.resume.prompt",
          title: "续播询问",
          note: "媒体有观看进度时的“从 12:34 继续播放 / 从头播放 / 取消”确认弹窗。",
          environment: .playback
        ) {
          UIPreviewPlaybackFlowScene(presentation: .resumePrompt)
        },
      ]
    )
  }
}

private struct UIPreviewPlaybackFlowScene: View {
  enum Presentation {
    case resolving
    case resumePrompt
  }

  private let presentation: Presentation
  @State private var coordinator: PlaybackCoordinator?

  init(presentation: Presentation) {
    self.presentation = presentation
  }

  var body: some View {
    Group {
      if let coordinator {
        UIPreviewTabRootView(tab: .home)
          .playbackPresentation(coordinator)
      } else {
        Color(white: 0.08)
      }
    }
    .onAppear {
      guard coordinator == nil else { return }
      let coordinator = PlaybackCoordinator(apiService: APIService.shared)
      switch presentation {
      case .resolving:
        coordinator.installUIPreviewPresentation(isResolving: true)
      case .resumePrompt:
        coordinator.installUIPreviewPresentation(
          resumePrompt: UIPreviewPlaybackFlowFixtures.resumePrompt()
        )
      }
      self.coordinator = coordinator
    }
  }
}
#endif
