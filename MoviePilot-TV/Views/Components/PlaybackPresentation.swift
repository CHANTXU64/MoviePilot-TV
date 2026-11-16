import SwiftUI

/// 挂在主界面上的播放呈现：起播前的黑屏、全屏播放器和失败提示。有续播点时直接接着播，不询问。
struct PlaybackPresentationModifier: ViewModifier {
  @ObservedObject var coordinator: PlaybackCoordinator
  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.scenePhase) private var scenePhase
  /// 起播前的黑屏：按下播放淡入；播放器出来前取消或出错时淡出，退出播放时直接撤掉。
  @State private var showsLoadingScreen = false
  /// 黑屏已经完全盖住页面。播放器等到这时才出现，直接接在黑屏上。
  @State private var isLoadingScreenOpaque = false
  /// 全屏播放器显示的会话（见 `presentPlayerIfReady`）。
  @State private var playerSession: PlaybackSession?
  /// 这次起播已经弹出过播放器。之后下面的黑屏不再转圈，退出播放时直接撤掉（见 `updateLoadingScreen`）。
  @State private var hasShownPlayer = false
  @FocusState private var isLoadingScreenFocused: Bool
  /// 全屏播放器正在显示的会话，播放界面出现时记下。
  @State private var presented = PresentedSession()

  private final class PresentedSession {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var session: PlaybackSession?
  }

  func body(content: Content) -> some View {
    content
      .disabled(coordinator.isBusy)
      .accessibilityHidden(coordinator.isBusy)
      .overlay {
        // 按下播放先从页面淡入黑屏，正中转圈、不带文字（Apple TV App 的做法，HIG「Playing video › Loading content」
        // 的黑底居中转圈）。黑屏盖满后播放器接上，播放器里同样的黑屏一直盖到出画面。返回键取消。
        ZStack {
          if showsLoadingScreen {
            loadingScreen(isPreparing: coordinator.resolvingTask != nil)
              .transition(.opacity)
          }
        }
      }
      .onChange(of: coordinator.isBusy, initial: true) { _, isBusy in
        updateLoadingScreen(isBusy: isBusy)
      }
      .task(id: showsLoadingScreen) {
        guard showsLoadingScreen else { return }
        guard (try? await Task.sleep(for: PlaybackLoadingScreen.fadeInDuration)) != nil else { return }
        isLoadingScreenOpaque = true
        presentPlayerIfReady()
      }
      .onChange(of: coordinator.session?.id) {
        presentPlayerIfReady()
      }
      .fullScreenCover(
        item: Binding(
          get: { playerSession },
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

  private func updateLoadingScreen(isBusy: Bool) {
    guard isBusy != showsLoadingScreen else { return }
    if isBusy {
      withAnimation(PlaybackLoadingScreen.fadeIn) { showsLoadingScreen = true }
      return
    }
    isLoadingScreenOpaque = false
    if hasShownPlayer {
      // 退出播放：没什么要加载了，播放器收起时露出的直接是页面，不再露出黑屏和转圈。
      hasShownPlayer = false
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { showsLoadingScreen = false }
    } else {
      // 播放器还没出来就取消或出错：黑屏淡出回到页面。
      withAnimation(.easeOut(duration: 0.2)) { showsLoadingScreen = false }
    }
  }

  /// 会话就绪、黑屏也已盖满时显示播放器，不带系统的弹出动画：播放器的起播遮挡和这层黑屏一样，看不出换了一层。
  /// 会话结束时收起播放器。
  private func presentPlayerIfReady() {
    guard let session = coordinator.session else {
      playerSession = nil
      return
    }
    guard isLoadingScreenOpaque, playerSession !== session else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      // 和弹出播放器同一次更新里收起下面的转圈：播放器盖在上面，看不出变化。全屏弹出后底下页面停在最后画出的那一帧，
      // 退出时播放器收起的一瞬间可能露出来，那一帧里也只有黑底，不会再看到转圈。
      hasShownPlayer = true
      playerSession = session
    }
  }

  /// 准备期间底下的页面已禁用，焦点落在黑屏上，返回键由这里接住、取消准备。播放器出现后黑屏只是垫在下面，
  /// 不再可聚焦，退出播放时焦点直接回到页面。
  private func loadingScreen(isPreparing: Bool) -> some View {
    PlaybackLoadingScreen(showsIndicator: !hasShownPlayer)
      .focusable(isPreparing)
      .focusEffectDisabled()
      .focused($isLoadingScreenFocused)
      .onAppear { isLoadingScreenFocused = isPreparing }
      .onExitCommand { coordinator.cancelResolving() }
  }
}

/// 起播时的黑屏：黑底，正中一个转圈，不带文字。起播前的黑屏和播放器里的起播遮挡共用这一个样子，两层接替时看不出换了一层。
struct PlaybackLoadingScreen: View {
  private static let fadeInSeconds = 0.35
  static let fadeInDuration: Duration = .seconds(fadeInSeconds)
  /// 从页面或正在播的画面淡入黑屏。
  static let fadeIn: Animation = .easeInOut(duration: fadeInSeconds)

  /// 转圈的直径：整屏只有它，比系统默认的 64pt 大。
  private static let indicatorDiameter: CGFloat = 100

  /// 电视切换显示模式时不转圈，只留纯黑（见 `StartupCover`）。
  var showsIndicator = true

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if showsIndicator {
        // 系统转圈是 64pt 的位图，这里整体放大到 `indicatorDiameter`。
        ProgressView()
          .visualEffect { content, geometry in
            content.scaleEffect(Self.indicatorDiameter / max(geometry.size.width, 1))
          }
          .frame(width: Self.indicatorDiameter, height: Self.indicatorDiameter)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: showsIndicator)
    .environment(\.colorScheme, .dark)
    .accessibilityElement()
    .accessibilityLabel("正在准备播放")
  }
}

extension View {
  func playbackPresentation(_ coordinator: PlaybackCoordinator) -> some View {
    modifier(PlaybackPresentationModifier(coordinator: coordinator))
  }
}
