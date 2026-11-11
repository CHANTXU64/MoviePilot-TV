import SwiftUI

/// 挂在主界面上的播放呈现：解析中的遮罩、续播询问、全屏播放器和失败提示。
struct PlaybackPresentationModifier: ViewModifier {
  @ObservedObject var coordinator: PlaybackCoordinator
  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  /// 全屏播放器正在显示的会话，播放界面出现时记下。
  @State private var presented = PresentedSession()

  private final class PresentedSession {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var session: PlaybackSession?
  }

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
          // 系统自行关闭时在这里收尾；按键退出由 `onExit` 收尾。只结束这个播放器显示的会话：
          // 关闭回调可能晚于下一次播放开始，那时的当前会话已是新的一次。
          set: {
            guard $0 == nil, let session = presented.session else { return }
            coordinator.endSession(session)
          })
      ) { session in
        MPVPlaybackScreen(
          session: session,
          onExit: { notice in coordinator.endSession(session, notice: notice) },
          onSwitchItem: { itemID, sourceID, position, episode, completion in
            coordinator.switchItem(
              to: itemID, mediaSourceID: sourceID, startPosition: position, episode: episode, in: session,
              completion: completion)
          }
        )
        .onAppear { presented.session = session }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { coordinator.saveProgressForBackground() }
      }
      .onChange(of: coordinator.failure) { _, failure in
        guard let failure else { return }
        notificationManager.show(message: failure.message, type: .error)
        coordinator.failure = nil
      }
      .onChange(of: coordinator.notice) { _, notice in
        guard let notice else { return }
        notificationManager.show(message: notice.message, type: .info)
        coordinator.notice = nil
      }
  }
}

extension View {
  func playbackPresentation(_ coordinator: PlaybackCoordinator) -> some View {
    modifier(PlaybackPresentationModifier(coordinator: coordinator))
  }
}
