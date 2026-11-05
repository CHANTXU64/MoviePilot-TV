import AVKit
import SwiftUI

/// 系统播放器：进度条、快进快退、音轨与字幕菜单、信息面板都使用 tvOS 原生控件。
struct PlayerView: UIViewControllerRepresentable {
  let session: PlaybackSession

  func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = session.player
    // 按影片切换 HDR/帧率（需用户在系统设置里开启“匹配内容”）。
    controller.appliesPreferredDisplayCriteriaAutomatically = true
    session.start()
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: UIViewControllerRepresentableContext<Self>) {}

  static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
    controller.player = nil
  }
}

/// 挂在主界面上的播放呈现：解析中的遮罩、续播询问、全屏播放器和失败提示。
struct PlaybackPresentationModifier: ViewModifier {
  @ObservedObject var coordinator: PlaybackCoordinator
  @EnvironmentObject private var notificationManager: NotificationManager

  func body(content: Content) -> some View {
    content
      .disabled(coordinator.isResolving)
      .accessibilityHidden(coordinator.isResolving)
      .overlay {
        if coordinator.isResolving {
          ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 32) {
              ProgressView("正在准备播放…")
              Button("取消") { coordinator.cancelResolving() }
            }
          }
          .onExitCommand { coordinator.cancelResolving() }
        }
      }
      .confirmationDialog(
        coordinator.resumePrompt?.prepared.title ?? "继续播放",
        isPresented: Binding(
          get: { coordinator.resumePrompt != nil },
          set: { if !$0 { coordinator.dismissResumePrompt() } }),
        titleVisibility: .visible,
        presenting: coordinator.resumePrompt
      ) { prompt in
        Button("从 \(PlaybackResumePolicy.formatted(prompt.position)) 继续播放") {
          coordinator.resume(prompt, fromBeginning: false)
        }
        Button("从头播放") {
          coordinator.resume(prompt, fromBeginning: true)
        }
        Button("取消", role: .cancel) { coordinator.dismissResumePrompt() }
      }
      .fullScreenCover(
        item: Binding(
          get: { coordinator.session },
          set: { if $0 == nil { coordinator.endSession() } }),
        onDismiss: { coordinator.endSession() }
      ) { session in
        PlayerView(session: session)
          .ignoresSafeArea()
      }
      .onChange(of: coordinator.failure) { _, failure in
        guard let failure else { return }
        notificationManager.show(message: failure.message, type: .error)
        coordinator.failure = nil
      }
  }
}

extension View {
  func playbackPresentation(_ coordinator: PlaybackCoordinator) -> some View {
    modifier(PlaybackPresentationModifier(coordinator: coordinator))
  }
}
