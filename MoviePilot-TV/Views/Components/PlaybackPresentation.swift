import Observation
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
  /// 播放结束的次数。盖过播放器时由系统还原盖上那一刻的焦点项；准备期取消时没有可还原的对象，
  /// 页面据此把焦点交回起播的那个控件。
  @State private var playbackEndedGeneration = 0
  /// 盖播放器之前的焦点交接：请页面把焦点放回起播控件，页面回执后再盖（见 `requestFocusHandoff`）。
  @State private var focusHandoff = PlaybackFocusHandoff()
  /// 已经排上呈现、还没盖上的会话。
  @State private var pendingPresentation: PlaybackSession?
  /// 页面是否已经解除禁用。准备阶段（黑屏淡入、解析中）页面保持禁用；到真要交回焦点那一刻才解除，
  /// 之后播放期间和退出时也保持解除，系统关闭模态才能把焦点还原到页面控件。
  @State private var isHandingOffFocus = false

  private final class PresentedSession {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var session: PlaybackSession?
  }

  func body(content: Content) -> some View {
    content
      .environment(\.playbackEndedGeneration, playbackEndedGeneration)
      .environment(\.playbackFocusHandoff, focusHandoff)
      // 准备阶段禁用整页：那时焦点要落在黑屏上接返回键，页面不能先被遥控器操作。
      // 到交回焦点那一刻才解除，之后播放期间保持解除，模态关闭时系统才能把记下的页面控件还原回来。
      .disabled(coordinator.isBusy && !isHandingOffFocus)
      .accessibilityHidden(coordinator.isBusy && !isHandingOffFocus)
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
      .onChange(of: coordinator.isBusy, initial: true) { wasBusy, isBusy in
        updateLoadingScreen(isBusy: isBusy)
        // 每次起播都从锁住页面开始，等交回焦点那一刻再解除。
        if isBusy { isHandingOffFocus = false }
        // 播放结束（含准备期取消）：播放器盖上之前焦点交回了页面，正常情况下系统会自己还原；
        // 没盖上播放器就结束时没有可还原的对象，由起播的那个控件自己写回。
        if !isBusy, wasBusy { playbackEndedGeneration += 1 }
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
      .onChange(of: focusHandoff.acknowledged) { _, acknowledged in
        // 页面已经把焦点写回起播控件，这时才盖播放器，让系统记下的是那个控件。
        guard acknowledged == focusHandoff.request, let session = pendingPresentation else { return }
        presentCover(session)
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
    // 还没盖上播放器就结束了（准备期取消）：撤销排队中的呈现。
    pendingPresentation = nil
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
      pendingPresentation = nil
      playerSession = nil
      return
    }
    guard isLoadingScreenOpaque, playerSession !== session, pendingPresentation == nil else { return }
    pendingPresentation = session
    // 有要交回的起播控件时先等页面把焦点写回去；没有就直接盖，和原来一样不耽误起播。
    guard focusHandoff.target != nil else {
      presentCover(session)
      return
    }
    requestFocusHandoff(for: session)
  }

  /// 盖播放器之前先让页面把焦点放回起播控件。模态关闭时系统还原它"盖上去那一刻"的焦点项：
  /// 那一刻焦点在黑屏锚点上，锚点退出时已经撤掉，只能退回 Tab 栏。
  private func requestFocusHandoff(for session: PlaybackSession) {
    // 解除页面禁用和发出请求放在同一帧，页面可操作到播放器盖上之间只剩交接本身的几帧。
    isHandingOffFocus = true
    focusHandoff.request += 1
    let request = focusHandoff.request
    Task { @MainActor in
      // 页面没能写回（要交回的控件已经不在页面上）时别把播放器一直卡在黑屏里。
      try? await Task.sleep(for: .milliseconds(150))
      guard focusHandoff.request == request, pendingPresentation === session else { return }
      presentCover(session)
    }
  }

  private func presentCover(_ session: PlaybackSession) {
    guard pendingPresentation === session, playerSession !== session else { return }
    pendingPresentation = nil
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

private struct PlaybackFocusHandoffKey: EnvironmentKey {
  static let defaultValue = PlaybackFocusHandoff()
}

extension EnvironmentValues {
  /// 盖播放器之前的焦点交接（见 `PlaybackFocusHandoff`）。
  var playbackFocusHandoff: PlaybackFocusHandoff {
    get { self[PlaybackFocusHandoffKey.self] }
    set { self[PlaybackFocusHandoffKey.self] = newValue }
  }
}

/// 起播的控件：播放器盖上之后，退出播放时焦点要回到它。带上起播方身份，栈里还有别的详情页、
/// 或者货架行和展开的剧集页同时活着时，只有起播的那一个实例写焦点、回执、清目标。
enum PlaybackFocusTarget: Hashable {
  /// 详情页头部的「播放」。
  case detailHeader(routeID: UUID)
  /// 详情页的某一集。集 ID 只是本季列表里的位置，别的剧、同一部剧的另一行都会重复，所以带上行实例和剧。
  case episode(ownerID: UUID, seriesID: Int, id: MoviePilotEpisode.ID)
  /// 首页「最近添加」「继续观看」里直接起播的媒体卡（不经过详情页）。带上行实例身份，焦点只交回起播的那一个。
  case homeMedia(ownerID: UUID, itemID: String)
}

/// 盖播放器之前的焦点交接：呈现层请页面把焦点放回起播控件，页面写回后回执，呈现层再盖上播放器。
/// 模态关闭时系统还原的是"盖上去那一刻"的焦点项，所以那一刻焦点必须在页面控件上；留在准备阶段的
/// 黑屏锚点上不行——锚点退出时已经撤掉，系统只能退回 Tab 栏。
@MainActor
@Observable
final class PlaybackFocusHandoff {
  // 与播放会话一起释放时，避开 tvOS 18 的隔离析构回部署问题。
  nonisolated deinit {}

  /// 起播控件在按下播放时登记的目标；`nil` 表示这次起播没有要交回的焦点。
  var target: PlaybackFocusTarget?
  /// 呈现层自增：请求页面把焦点放回 `target`。
  var request = 0
  /// 页面确认焦点已写回（回填对应的 `request`）。
  var acknowledged = 0

  /// 起播并登记退出后焦点要交回的控件。已有别的播放在准备或播放时这次会被拒绝，先不登记目标，
  /// 免得把焦点目标错改成这个控件；起播没被接受（没权限、后端太旧、设置关闭）时清掉目标，
  /// 不留给下一次播放。
  func play(
    returningTo focus: PlaybackFocusTarget, on coordinator: PlaybackCoordinator, start: () -> Void
  ) {
    guard !coordinator.isBusy else { return }
    target = focus
    start()
    if !coordinator.isBusy { target = nil }
  }
}

private struct PlaybackEndedGenerationKey: EnvironmentKey {
  static let defaultValue = 0
}

extension EnvironmentValues {
  /// 播放结束（含准备期取消）时自增。盖过播放器时系统会还原盖上那一刻的焦点项（见 `PlaybackFocusHandoff`），
  /// 页面收到这个信号后等焦点落定，没还原回来就补写一遍。
  var playbackEndedGeneration: Int {
    get { self[PlaybackEndedGenerationKey.self] }
    set { self[PlaybackEndedGenerationKey.self] = newValue }
  }
}

/// 起播控件一侧等着补写的焦点（见 `playbackFocusReturn`）。由页面持有，页面可以改写要补写的目标，
/// 比如那张卡被刷掉时换成相邻的卡。
struct PlaybackFocusRestore<Focus: Hashable> {
  /// 播放器收起有转场，同一次更新里写回会被丢掉，交给 `PresentationReadyAction` 等转场结束后补写。
  var pending: Focus?
  /// 每次开始补写自增，让上一轮的超时失效。
  fileprivate var generation = 0

  init() {}
}

extension View {
  /**
   起播控件一侧的焦点交接，详情页「播放」、集列表、首页卡片共用：
   - 盖播放器之前，呈现层请求时把焦点写回本控件，焦点真的落上去后回执，呈现层再盖播放器
     （模态关闭时系统还原的是盖上去那一刻的焦点项）。
   - 播放结束时清掉目标。盖上过播放器的由系统还原；没盖上就结束（准备期取消）时没有可还原的对象，
     等模态和转场结束后补写，3 秒内没落回就放弃。

   - Parameters:
     - restore: 页面持有的补写状态。
     - focused: 页面当前的焦点值（`@FocusState` 的值）。
     - focus: 写焦点用的绑定。
     - isEnabled: 额外的补写条件（比如会话验证期间不写）。
     - canRestore: 开始补写和每次写之前确认目标还在页面上；不在就放弃，焦点交给系统。
     - match: 交接目标是不是本控件起播的；是就返回本控件的焦点值。
   */
  func playbackFocusReturn<Focus: Hashable>(
    _ restore: Binding<PlaybackFocusRestore<Focus>>,
    focused: Focus?,
    focus: FocusState<Focus?>.Binding,
    isEnabled: Bool = true,
    canRestore: @escaping (Focus) -> Bool = { _ in true },
    match: @escaping (PlaybackFocusTarget) -> Focus?
  ) -> some View {
    modifier(PlaybackFocusReturnModifier(
      restore: restore, focused: focused, focus: focus,
      isEnabled: isEnabled, canRestore: canRestore, match: match))
  }
}

private struct PlaybackFocusReturnModifier<Focus: Hashable>: ViewModifier {
  static var timeout: Duration { .seconds(3) }

  @Environment(\.playbackFocusHandoff) private var handoff
  @Environment(\.playbackEndedGeneration) private var endedGeneration
  @Binding var restore: PlaybackFocusRestore<Focus>
  let focused: Focus?
  let focus: FocusState<Focus?>.Binding
  let isEnabled: Bool
  let canRestore: (Focus) -> Bool
  let match: (PlaybackFocusTarget) -> Focus?

  /// 当前交接目标属于本控件时的焦点值。
  private var ownFocus: Focus? { handoff.target.flatMap(match) }

  func body(content: Content) -> some View {
    content
      .onChange(of: handoff.request) { _, _ in
        guard let value = ownFocus else { return }
        focus.wrappedValue = value
      }
      .onChange(of: focused) { _, newValue in
        guard let value = ownFocus, newValue == value else { return }
        handoff.acknowledged = handoff.request
      }
      .onChange(of: endedGeneration) { _, _ in
        guard let value = ownFocus else { return }
        handoff.target = nil
        guard canRestore(value) else { return }
        beginRestore(value)
      }
      .background(PresentationReadyAction(
        isEnabled: restore.pending != nil && isEnabled,
        requiresNavigationTop: true,
        contentFocusMatches: restore.pending.map { focused == $0 } ?? false,
        onContentFocus: {
          restore.pending = nil
          restore.generation += 1
        },
        action: {
          guard let value = restore.pending else { return }
          guard canRestore(value) else {
            restore.pending = nil
            return
          }
          // 值没变时 SwiftUI 不会重新请求焦点：先把绑定清空，下一帧再写回。
          focus.wrappedValue = focused == value ? nil : value
        }
      ))
  }

  private func beginRestore(_ value: Focus) {
    restore.generation += 1
    let generation = restore.generation
    restore.pending = value
    let restore = $restore
    Task { @MainActor in
      try? await Task.sleep(for: Self.timeout)
      guard restore.wrappedValue.generation == generation else { return }
      restore.wrappedValue.pending = nil
    }
  }
}
