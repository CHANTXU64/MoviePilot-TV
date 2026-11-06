import SwiftUI

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
        Button("从 \(Duration.seconds(Int(prompt.position)).formatted(.runtime)) 继续播放") {
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
          // 系统自行关闭时在这里收尾（此时旧会话仍是当前会话）；按键退出由 `onExit` 收尾。
          set: { if $0 == nil { coordinator.endSession() } })
      ) { session in
        MPVPlaybackScreen(
          session: session,
          onExit: { coordinator.endSession(session) },
          onSwitchItem: { itemID, sourceID, position, completion in
            coordinator.switchItem(
              to: itemID, mediaSourceID: sourceID, startPosition: position, in: session,
              completion: completion)
          })
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
