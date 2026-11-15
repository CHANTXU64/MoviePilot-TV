import SwiftUI

/// 挂在主界面上的播放呈现：起播前的黑屏、全屏播放器和失败提示。有续播点时直接接着播，不询问。
struct PlaybackPresentationModifier: ViewModifier {
  @ObservedObject var coordinator: PlaybackCoordinator
  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  /// 准备超过 `loadingIndicatorDelay` 的那次解析，黑屏上显示转圈。
  @State private var resolveWithVisibleProgress: Task<Void, Never>?
  @FocusState private var isLoadingScreenFocused: Bool
  /// 全屏播放器正在显示的会话，播放界面出现时记下。
  @State private var presented = PresentedSession()

  private final class PresentedSession {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var session: PlaybackSession?
  }

  /// 准备超过这么久才显示转圈（HIG「Playing video › Loading content」：加载超过两秒才考虑显示加载画面）。
  static let loadingIndicatorDelay: Duration = .seconds(2)

  func body(content: Content) -> some View {
    let resolvingTask = coordinator.resolvingTask
    let showsIndicator = resolvingTask != nil && resolvingTask == resolveWithVisibleProgress
    let showsBlackScreen = coordinator.isBusy
    content
      .disabled(coordinator.isBusy)
      .accessibilityHidden(coordinator.isBusy)
      .overlay {
        // HIG「Playing video」：按下播放立即换成黑屏，一直黑到播放器出画面；很快就绪时不显示任何加载内容，
        // 超过两秒才在黑底正中显示转圈，不带文字和其他内容。返回键取消。
        ZStack {
          if showsBlackScreen {
            loadingScreen(isPreparing: resolvingTask != nil, showsIndicator: showsIndicator)
              .transition(.asymmetric(insertion: .identity, removal: .opacity))
          }
        }
        .animation(.easeOut(duration: 0.2), value: showsBlackScreen)
      }
      .task(id: resolvingTask) {
        resolveWithVisibleProgress = nil
        guard let resolvingTask else { return }
        do {
          try await Task.sleep(for: Self.loadingIndicatorDelay)
        } catch {
          return
        }
        guard !Task.isCancelled, coordinator.resolvingTask == resolvingTask else { return }
        withAnimation(.easeIn(duration: 0.3)) { resolveWithVisibleProgress = resolvingTask }
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
        InAppPlaybackScreen(
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
        switch phase {
        case .background: coordinator.noteEnteredBackground()
        case .active: coordinator.refreshWatchStateAfterReturningToForeground()
        default: break
        }
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

  /// 准备期间底下的页面已禁用，焦点落在黑屏上，返回键由这里接住、取消准备。播放器出现后黑屏只是垫在下面，
  /// 不再可聚焦，退出播放时焦点直接回到页面。
  private func loadingScreen(isPreparing: Bool, showsIndicator: Bool) -> some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if showsIndicator {
        ProgressView()
          .transition(.opacity)
      }
    }
    .environment(\.colorScheme, .dark)
    .focusable(isPreparing)
    .focusEffectDisabled()
    .focused($isLoadingScreenFocused)
    .onAppear { isLoadingScreenFocused = isPreparing }
    .onExitCommand { coordinator.cancelResolving() }
    .accessibilityElement()
    .accessibilityLabel("正在准备播放")
  }
}

extension View {
  func playbackPresentation(_ coordinator: PlaybackCoordinator) -> some View {
    modifier(PlaybackPresentationModifier(coordinator: coordinator))
  }
}
