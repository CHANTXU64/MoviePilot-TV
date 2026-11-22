import Combine
import SwiftUI
import UIKit

// 把移植自 Swiftfin 的 tvOS 播放界面（Views/Player/Swiftfin）接到 MoviePilot-TV 的播放会话上。
// Swiftfin 界面读写的是它自己的 `MediaSession`（依赖 Jellyfin），这里按同名提供只实现界面用到成员的适配对象，
// 底层是 `PlaybackSession` 与它创建的 `AetherPlayer`；条目、章节等数据类型见 SwiftfinPlayerModels.swift。

/// 应用内的全屏播放界面。播放中换集、换版本只替换会话里的条目，界面不重建。
/// `MediaSession` 在界面出现时创建一次：外层状态变化会让 SwiftUI 反复执行本视图的 init，
/// 在 init 里创建会每次多建一套再丢掉。
struct InAppPlaybackScreen: View {
  let session: PlaybackSession
  let onExit: MediaSession.Exit
  let onSwitchItem: MediaSession.SwitchItem
  @State private var mediaSession: MediaSession?

  init(
    session: PlaybackSession,
    onExit: @escaping MediaSession.Exit,
    onSwitchItem: @escaping MediaSession.SwitchItem
  ) {
    self.session = session
    self.onExit = onExit
    self.onSwitchItem = onSwitchItem
  }

  /// 起播遮挡；会话建好前也算在准备。
  private var startupCover: StartupCover? {
    guard let mediaSession else { return .loading }
    return mediaSession.startupCover
  }

  var body: some View {
    ZStack {
      if let mediaSession {
        VideoPlayer(mediaSession: mediaSession)
      }
      // 和外层起播前的黑屏是同一个样子，播放器盖上来时看不出换了一层；从第一帧起就在，中途不换视图。
      // 揭开不带过渡，直接出画面。
      if let startupCover {
        PlaybackLoadingScreen(showsIndicator: startupCover == .loading)
          .transition(.asymmetric(insertion: .opacity, removal: .identity))
      }
    }
    .onAppear {
      guard mediaSession == nil else { return }
      mediaSession = MediaSession(session: session, onExit: onExit, onSwitchItem: onSwitchItem)
    }
  }
}

/// 播放器设置项的固定取值；平台能力的差异在使用处说明。
enum VideoPlayerDefaults {
  /// 遥控器左右键点一下跳多远，与系统播放器相同。
  static let jumpInterval: Duration = .seconds(10)
  /// 左右键按住多久算长按，开始快退、快进。
  static let scanHoldDelay: Duration = .milliseconds(500)
  /// 控制条显示多久后自动收起；只显示进度条（跳转、轻触触控板）时更短。
  static let controlsAutoHideInterval: TimeInterval = 5
  static let progressAutoHideInterval: TimeInterval = 2
  static let playbackRates: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]
  /// 控制条收起后再按 Menu 是否先确认再退出。
  static let confirmClose = false
  static let appMaximumBitrate: PlaybackBitrate = .auto
  static let supplements: [VideoPlayerSupplementType] = VideoPlayerSupplementType.supportedCases
  /// 工具栏按钮。Swiftfin 默认还有「填充」（`.aspectFill`），这里不放；字幕选择直接放工具栏，不进「…」菜单。
  static let barActionButtons: [VideoPlayerActionButton] = [.playPreviousItem, .playNextItem, .subtitles]
  static let menuActionButtons: [VideoPlayerActionButton] = [
    .audio, .audioOffset, .subtitleOffset, .playbackSpeed, .pictureInPicture, .playbackSettings,
  ].filter { VideoPlayerActionButton.supportedCases.contains($0) }
}

// MARK: - 播放器能力（与 Swiftfin 同名的协议）

@MainActor
protocol MediaPlayer: AnyObject {
  var displayTitle: String { get }
  var supportedRates: ClosedRange<Double> { get }
}

@MainActor
protocol VideoMediaPlayer: MediaPlayer {
  var videoState: VideoPlaybackState { get }
}

/// 支持音频、字幕偏移。
@MainActor
protocol MediaPlayerOffsetProviding {}

/// 支持画中画。MoviePilot-TV 的 tvOS 播放不提供，没有类型遵循它（tvOS 上 Swiftfin 也去掉了画中画按钮）。
@MainActor
protocol MediaPlayerPictureInPictureProviding {
  var isPiPActive: Bool { get }
  var isPiPTransitioning: Bool { get }
}

struct VideoPlaybackState: Equatable {
  var videoSize: CGSize = .zero
}

/// `MediaSession.player` 指向的播放器描述。
@MainActor
final class AetherPlayerAdapter: VideoMediaPlayer, MediaPlayerOffsetProviding {
  nonisolated deinit {}

  private let player: AetherPlayer

  init(player: AetherPlayer) {
    self.player = player
  }

  let displayTitle = "AetherEngine"
  /// 引擎视频播放最快 2 倍速，不支持倒放。
  var supportedRates: ClosedRange<Double> { 0.5...2 }

  var videoState: VideoPlaybackState {
    VideoPlaybackState(videoSize: player.videoSize)
  }
}

// MARK: - MediaSession

/// 播放界面读到的会话状态。播放位置、就绪、缓冲由播放器的位置和事件写入，值不变时不发布，
/// 与 Swiftfin `MPVMediaPlayer.updateTiming` 相同：播放位置每秒刷新多次，界面若直接跟着它，
/// 整个控制层（含菜单）会跟着反复重建。
/// 跳转在这里合并连续请求，界面立即显示目标位置，播放器完成后再回到真实位置。
@MainActor
@Observable
final class MediaSession {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  /// 换集、换版本：交给 `PlaybackCoordinator.switchItem`。按集播放时带上 MoviePilot 集列表里的那一集和它所在那一季的列表。
  typealias SwitchItem = (
    _ itemID: String, _ mediaSourceID: String?, _ startPosition: Double, _ episode: QueuedEpisode?,
    _ completion: @escaping (PlaybackCoordinator.SwitchResult) -> Void
  ) -> Void

  /// 退出播放，交给 `PlaybackCoordinator.endSession`。`notice` 是要告诉用户的说明（比如下一集在另一台服务器上）。
  typealias Exit = (_ notice: String?) -> Void

  enum State {
    case initial
    case loadingItem
    case preparing
    case playback
    case error
    case stopped
  }

  enum PlaybackRequestStatus {
    case playing
    case paused
  }

  enum Activity: Equatable {
    case loading
    case buffering
    case seeking
    case switchingDisplay
  }

  struct PlaybackState: Equatable {
    var isReady = false
    var isSeekable = false
    var isBuffering = false
    var duration: Duration?
  }

  /// 与 Swiftfin `mediaSession.logger` 相同的调用方式，写入工程日志。
  struct SessionLogger {
    func debug(_ message: String) { Logger.debug("[Playback] \(PlaybackLog.redacted(message))") }
    func error(_ message: String) { Logger.error("[Playback] \(PlaybackLog.redacted(message))") }
  }

  let enginePlayer: AetherPlayer
  let logger = SessionLogger()
  let session: PlaybackSession
  private(set) var playbackItem: MediaPlayerItem?
  let userSession: UserSession
  #if DEBUG
    /// UI 预览：只驱动界面状态，不启动 mpv、不访问媒体服务器。见 `PreviewSupport/Fixtures/PlayerFixtures.swift`。
    var previewSession: UIPlayerPreviewSession?
  #endif
  private(set) var queue: (any MediaPlayerQueue)?
  private(set) var playbackRequestStatus: PlaybackRequestStatus = .playing
  var commandError: String?

  var rate: Double = 1 {
    didSet {
      #if DEBUG
        if previewSession != nil { return }
      #endif
      enginePlayer.setRate(effectiveRate)
    }
  }

  /// 就绪、可跳转、缓冲与时长，值变化时才更新。
  private(set) var playbackState = PlaybackState()
  /// 播放器读到的当前条目内嵌章节，随播放器更新；播放器还不知道时为 nil。
  private var embeddedChapters: [ServerChapter]?
  /// 播放器报告的播放位置，变化满 `positionPublishStep` 才更新（见 `publishPosition`）。只有进度条和时间读它。
  private var observedPosition: Duration = .zero
  /// 界面显示的跳转目标；播放器完成跳转后清空。
  private var pendingSeek: Duration?
  private(set) var isStopped = false
  /// 播放界面出现后才起播。
  private var hasStarted = false
  /// 正在为换集、换版本解析新条目。
  private var isSwitchingItem = false
  /// 起播遮挡：从起播到首帧备好整屏盖住（见 `coverUntilStartupSettles`），nil 是已揭开。只是遮挡，不影响播放。
  private(set) var startupCover: StartupCover? = .loading

  @ObservationIgnored private let playerAdapter: AetherPlayerAdapter
  @ObservationIgnored private let onExit: Exit
  @ObservationIgnored private let onSwitchItem: SwitchItem
  @ObservationIgnored private var pendingPlaybackStatus: PlaybackRequestStatus?
  /// 暂停时跳转还没落定就要求播放（确认或取消快退快进、选章节）：等跳到最后一个目标再播，见 `performPendingSeeks`。
  @ObservationIgnored private var playsAfterSeek = false
  @ObservationIgnored private var seekTask: Task<Void, Never>?
  @ObservationIgnored private var eventObservation: AnyCancellable?
  @ObservationIgnored private var positionObservation: AnyCancellable?
  @ObservationIgnored private var itemObservations: [AnyCancellable] = []
  @ObservationIgnored private var queueObservation: AnyCancellable?
  @ObservationIgnored private var displayTask: Task<Void, Never>?
  /// 播完时重新查下一集。
  @ObservationIgnored private var nextLookupTask: Task<Void, Never>?
  /// 当前条目已经播完（之后要么接着播下一集，要么退出）。这时换集失败，就没有画面可以留在原处。
  @ObservationIgnored private var currentItemEnded = false

  init(
    session: PlaybackSession,
    onExit: @escaping Exit,
    onSwitchItem: @escaping SwitchItem
  ) {
    self.session = session
    self.onExit = onExit
    self.onSwitchItem = onSwitchItem
    let player = session.makePlayer()
    enginePlayer = player
    playerAdapter = AetherPlayerAdapter(player: player)
    userSession = UserSession(session: session)
  }

  var player: (any MediaPlayer)? { playerAdapter }

  var effectiveRate: Double {
    let range = playerAdapter.supportedRates
    return min(max(rate, range.lowerBound), range.upperBound)
  }

  /// 所播文件的片长（见 `PlaybackDuration`）：起播后以播放器读到的为准，之前用所选片源的。
  /// 进度条、跳转上限、跳过片头片尾、信息面板的片长和结束时间都读这里，与看完判定同一个值。
  var runtime: Duration? {
    session.playback.durationSeconds(playerSeconds: playbackState.duration?.seconds).map { .seconds($0) }
  }

  /// 当前条目，片长换成 `runtime`。
  var item: BaseItemDto {
    var item = playbackItem?.baseItem ?? BaseItemDto(id: session.item.id)
    item.runTimeTicks = runtime.map { BaseItemDto.ticks(seconds: $0.seconds) }
    return item
  }

  /// 「章节」面板和进度条刻度用的章节（取法见 `PlaybackChapters`），随片长和播放器读到的章节变化。
  var chapters: PlaybackChapterList {
    guard let playbackItem else { return .chapters([]) }
    switch PlaybackChapters.resolve(
      server: playbackItem.serverChapters, embedded: embeddedChapters, durationSeconds: runtime?.seconds)
    {
    case .waitingForPlayer:
      return .loading
    case .chapters(let chapters):
      return .chapters(
        ChapterInfo.fullInfo(chapters, placeholderSymbol: playbackItem.chapterPlaceholderSymbol))
    }
  }

  var state: State {
    #if DEBUG
      if let previewSession { return previewSession.state }
    #endif
    if isStopped { return .stopped }
    guard hasStarted else { return .initial }
    if isSwitchingItem { return .loadingItem }
    return playbackState.isReady ? .playback : .preparing
  }

  /// 当前显示的播放位置：有未完成的跳转时是跳转目标。
  var seconds: Duration {
    #if DEBUG
      if let previewSession { return previewSession.position }
    #endif
    return pendingSeek ?? observedPosition
  }

  var isSeeking: Bool {
    #if DEBUG
      if previewSession != nil { return false }
    #endif
    return pendingSeek != nil
  }

  var canControlPlayback: Bool {
    #if DEBUG
      if let previewSession { return previewSession.canControlPlayback }
    #endif
    return (state == .preparing || state == .playback) && playbackState.isReady
  }

  var canSeek: Bool {
    #if DEBUG
      if let previewSession { return previewSession.canSeek }
    #endif
    return canControlPlayback && playbackState.isSeekable && !item.isLiveStream
  }

  var activity: Activity? {
    #if DEBUG
      if let previewSession { return previewSession.activity }
    #endif
    switch state {
    case .initial, .loadingItem: return .loading
    case .preparing where !playbackState.isReady: return .loading
    case .error, .stopped: return nil
    case .preparing, .playback: break
    }
    if pendingSeek != nil || enginePlayer.isSeeking { return .seeking }
    return playbackState.isBuffering ? .buffering : nil
  }

  var videoSize: CGSize {
    #if DEBUG
      if let previewSession { return previewSession.videoSize }
    #endif
    return playerAdapter.videoState.videoSize
  }

  /// 投屏只在 iOS 上有。
  var isRemotePlayback: Bool { false }

  var playbackBitrate: PlaybackBitrate { VideoPlayerDefaults.appMaximumBitrate }

  // MARK: 生命周期

  /// 界面出现时调用：开始收播放器事件，再交给 `PlaybackSession` 起播。
  func start() {
    guard !hasStarted, !isStopped else { return }
    hasStarted = true
    #if DEBUG
      if previewSession != nil {
        preparePreviewItem()
        return
      }
    #endif
    observeEvents()
    loadCurrentItem()
  }

  /// 会话已换成新条目（播放中换集、换版本后），上一条目已由会话上报停止：重建条目状态并起播。
  private func itemDidChange() {
    isSwitchingItem = false
    currentItemEnded = false
    seekTask?.cancel()
    seekTask = nil
    pendingSeek = nil
    pendingPlaybackStatus = nil
    playsAfterSeek = false
    playbackRequestStatus = .playing
    guard hasStarted else { return }
    loadCurrentItem()
  }

  /// 起播会话里的当前条目，首次起播和换集、换版本共用。倍速在载入后由播放器重新设上（引擎每次载入回到 1 倍速）。
  private func loadCurrentItem() {
    prepareItem()
    enginePlayer.setRate(effectiveRate)
    session.start()
    coverUntilStartupSettles()
    refreshPlaybackState()
  }

  /// 从起播到首帧备好整屏盖住（Apple TV App 的做法）：准备期间黑底转圈；开了「匹配内容」时电视切换显示模式期间纯黑
  /// （HDMI 黑屏约 1 秒，之前露出的首帧和控件就像闪了一下），切好直接揭开。只是遮挡，播放照常进行。
  /// 播放中换集、换版本不盖：保留当前画面和控制条，加载状态由控制条上的转圈表示。
  /// 边界：原位交接保留旧画面只对原生解码（`VideoRoute.loopback`/`.remoteBypass`）成立；软件解码（`.software`）
  /// 不支持原位交接，引擎会释放软件播放器露出黑帧。换到不同格式（如 SDR↔HDR）时显示模式切换的约 1 秒 HDMI 黑屏也会露出。
  /// 这两种黑帧因这里不盖遮挡而直接可见（已知取舍，暂不处理）。
  private func coverUntilStartupSettles() {
    displayTask?.cancel()
    // 遮挡揭开后换集：不再整屏盖住，否则控制条和进度条会一起被盖没。
    guard startupCover != nil else { return }
    startupCover = .loading
    let display = DisplayModeGate.currentDisplay
    displayTask = Task { [weak self] in
      await DisplayModeGate.wait(
        for: display,
        show: { [weak self] cover in self?.startupCover = cover },
        isPlayerSettled: { [weak self] in
          guard let self else { return true }
          return DisplayModeGate.isSettled(
            status: self.enginePlayer.status, hasFirstFrame: self.enginePlayer.hasFirstFrame,
            isAwaitingDisplaySwitch: self.enginePlayer.isAwaitingDisplaySwitch)
        })
      guard let self, !Task.isCancelled else { return }
      self.startupCover = nil
    }
  }

  /// 退出播放。可重复调用；实际停止、显示模式还原和进度上报由外部的退出闭包（结束 `PlaybackSession`）完成。
  func stop() {
    #if DEBUG
      if previewSession != nil {
        previewSession?.state = .stopped
        isStopped = true
        return
      }
    #endif
    finish(notice: nil)
  }

  private func finish(notice: String?) {
    guard !isStopped else { return }
    isStopped = true
    nextLookupTask?.cancel()
    nextLookupTask = nil
    displayTask?.cancel()
    displayTask = nil
    seekTask?.cancel()
    seekTask = nil
    pendingSeek = nil
    eventObservation = nil
    positionObservation = nil
    itemObservations.removeAll()
    queueObservation = nil
    // 起播遮挡还在时退出：播放器收起期间只留纯黑，不再转圈。
    if startupCover != nil { startupCover = .blank }
    onExit(notice)
  }

  /// 播放设置里可选的版本：只列能直接播放的片源，多于一个时才显示版本选择。
  static func versions(of sources: [ServerMediaSource]) -> [PlaybackMediaSourceInfo] {
    sources.filter(\.isDirectlyPlayable).map(PlaybackMediaSourceInfo.init(source:))
  }

  /// 为当前条目建立 `MediaPlayerItem`、片段与队列观察。
  private func prepareItem() {
    itemObservations.removeAll()
    embeddedChapters = nil
    var baseItem = BaseItemDto.playback(session.playback)
    baseItem.mediaSources = Self.versions(of: session.mediaSources)
    let item = MediaPlayerItem(
      baseItem: baseItem,
      source: session.mediaSource,
      player: enginePlayer,
      startSeconds: session.startSeconds)
    playbackItem = item
    if let segments = item.segments {
      itemObservations.append(segments.observe(self))
    }

    // 只有带剧集上下文起播（详情页集列表、认出这一集的「继续观看」）才有选集和上一集/下一集。
    // 没有上下文时取集列表恒为空，挂上面板只会是个空面板，所以不挂。
    if baseItem.type == .episode, session.episode != nil {
      if queue == nil {
        let queue = MoviePilotEpisodeQueue()
        self.queue = queue
        queueObservation = queue.observe(self)
      }
    } else {
      queueObservation = nil
      queue = nil
    }
  }

  #if DEBUG
    /// UI 预览：用 fixture 条目替换真实片源解析，轨道与队列都来自假会话。
    private func preparePreviewItem() {
      guard let previewSession else { return }
      let item = MediaPlayerItem(
        baseItem: previewSession.baseItem,
        source: session.mediaSource,
        player: enginePlayer,
        startSeconds: 0)
      item.installPreviewTracks(previewSession.tracks)
      playbackItem = item
      queue = previewSession.queue
      playbackState = PlaybackState(
        isReady: previewSession.isReady,
        isSeekable: previewSession.canSeek,
        isBuffering: previewSession.isBuffering,
        duration: previewSession.duration)
      playbackRequestStatus = previewSession.isPaused ? .paused : .playing
      // 预览没有真实的显示模式切换，直接收起起播遮挡，避免黑屏遮住整个界面。
      startupCover = nil
    }
  #endif

  enum EndAction {
    /// 正在换集，上一集刚好播完：等切换完成。
    case waitForSwitch
    case playNext(PlaybackIntent)
    /// 按集播放，但还不知道下一集，或已知的下一集是跳过还没入库的集找到的：重新查一次再决定。
    case lookUpNext
    case exit
  }

  /// 播完后怎么做：有下一集就接着播，否则退出（与 Swiftfin `MediaSession.ended` 相同）。
  /// 按集播放时，还不知道下一集（开播时没找到、或查询还没回来），或已知的下一集跳过了当时还没入库的集，
  /// 先重新查一次：播放期间那几集可能刚入库，应按顺序接上。
  /// 不看“能否控制播放”：播完时播放器可能已经报告不再就绪。
  static func endAction(
    isSwitchingItem: Bool, isSeeking: Bool, isLiveStream: Bool,
    nextItem: PlaybackIntent?, canLookUpNext: Bool = false, nextNeedsRecheck: Bool = false
  ) -> EndAction {
    if isSwitchingItem { return .waitForSwitch }
    guard !isSeeking, !isLiveStream else { return .exit }
    if canLookUpNext, nextItem == nil || nextNeedsRecheck { return .lookUpNext }
    if let nextItem { return .playNext(nextItem) }
    return .exit
  }

  private func ended() {
    currentItemEnded = true
    let episodeQueue = queue as? MoviePilotEpisodeQueue
    switch Self.endAction(
      isSwitchingItem: isSwitchingItem, isSeeking: isSeeking, isLiveStream: item.isLiveStream,
      nextItem: queue?.nextItem,
      canLookUpNext: episodeQueue?.canLookUpNext == true, nextNeedsRecheck: episodeQueue?.nextNeedsRecheck == true)
    {
    case .waitForSwitch: break
    case .playNext(let next): playNewItem(intent: next)
    case .lookUpNext:
      guard let episodeQueue else { return stop() }
      lookUpNextAfterEnd(episodeQueue)
    case .exit: stop()
    }
  }

  /// 重新查下一集，查询期间显示加载中；查到就接着播，查不到就退出并说明原因（已是最后一集时不说明）。
  /// 期间用户退出，或手动换了集（`playNewItem` 取消这次查询），结果都丢弃。
  private func lookUpNextAfterEnd(_ episodeQueue: MoviePilotEpisodeQueue) {
    isSwitchingItem = true
    nextLookupTask?.cancel()
    let endedItemID = session.item.id
    nextLookupTask = Task { [weak self] in
      let result = await episodeQueue.lookUpNext()
      guard let self, !Task.isCancelled, !self.isStopped, self.session.item.id == endedItemID else { return }
      self.nextLookupTask = nil
      self.isSwitchingItem = false
      switch result {
      case .play(let intent): self.playNewItem(intent: intent)
      case .unavailable(let reason): self.finish(notice: reason)
      }
    }
  }

  // MARK: 播放控制

  /// 暂停中、跳转还没落定时要求播放，先不让播放器播：否则先从跳转前的画面播一会儿再跳，跳转失败就从错的位置接着播。
  /// 界面先显示为播放，跳到最后一个目标后再播（见 `performPendingSeeks`）；其间暂停就不再播。正在播放时照常边播边跳。
  func setPlaybackRequestStatus(status: PlaybackRequestStatus) {
    guard state != .stopped, state != .error else { return }
    let waitsForSeek =
      status == .playing && pendingSeek != nil && (playbackRequestStatus == .paused || playsAfterSeek)
    playbackRequestStatus = status
    #if DEBUG
      if previewSession != nil {
        previewSession?.isPaused = status == .paused
        return
      }
    #endif
    playsAfterSeek = false
    guard hasStarted else { return }
    pendingPlaybackStatus = status
    if waitsForSeek {
      playsAfterSeek = true
      return
    }
    switch status {
    case .playing: enginePlayer.play()
    case .paused: enginePlayer.pause()
    }
  }

  func togglePlayPause() {
    guard canControlPlayback else { return }
    setPlaybackRequestStatus(status: playbackRequestStatus == .playing ? .paused : .playing)
  }

  @discardableResult
  func seek(to position: Duration) -> Bool {
    guard canSeek else { return false }
    let limit = runtime
    let target = max(.zero, limit.map { min(position, $0) } ?? position)
    commandError = nil
    #if DEBUG
      if previewSession != nil {
        previewSession?.position = target
        return true
      }
    #endif
    guard target != seconds else { return true }
    pendingSeek = target
    if seekTask == nil {
      seekTask = Task { [weak self] in await self?.performPendingSeeks() }
    }
    return true
  }

  @discardableResult
  func seek(by offset: Duration) -> Bool {
    seek(to: seconds + offset)
  }

  /// 一次只发一个跳转；进行中又有新目标时，完成后接着跳到最新目标。
  /// 跳完最后一个目标再处理等着的播放（见 `setPlaybackRequestStatus`）：跳转失败就停在暂停，不从没确认的位置播。
  private func performPendingSeeks() async {
    defer { seekTask = nil }
    while pendingSeek != nil {
      // 合并连按，不推迟界面对每次按键的响应。
      try? await Task.sleep(for: .milliseconds(80))
      guard !Task.isCancelled, !isStopped, let target = pendingSeek else { return }
      guard canSeek else {
        // 重新载入、换集等：没跳，播放照原来的要求。
        pendingSeek = nil
        resumeAfterSeek(landed: true)
        return
      }
      let succeeded = await enginePlayer.seek(to: target.seconds)
      guard !Task.isCancelled, !isStopped else { return }
      if pendingSeek == target {
        pendingSeek = nil
        if !succeeded { commandError = L10n.unableToSeek }
        // 跳转中播放器重新载入（换音轨、回前台）会让这次跳转算作失败。已经知道不能跳转时，与上面没跳一样，照原来的要求播放；
        // 播放器事件还没到、仍显示可跳转时，按失败处理：停在暂停、提示无法跳转，再按一次播放即可。
        resumeAfterSeek(landed: succeeded || !canSeek)
      }
    }
  }

  private func resumeAfterSeek(landed: Bool) {
    guard playsAfterSeek else { return }
    playsAfterSeek = false
    if landed {
      enginePlayer.play()
    } else {
      setPlaybackRequestStatus(status: .paused)
    }
  }

  /// 换集、换版本没成功时怎么办：当前条目还在播，就留在原处、提示原因；已经播完（自动接下一集，或手动换集时刚好播完），
  /// 画面停在片尾、一直显示加载中，只能退出并说明原因。被丢弃（播放已结束、账号已切换）时没有原因可说。
  enum SwitchFailureAction: Equatable {
    case stay(error: String?)
    case exit(notice: String?)
  }

  static func afterFailedSwitch(message: String?, currentItemEnded: Bool) -> SwitchFailureAction {
    currentItemEnded ? .exit(notice: message) : .stay(error: message)
  }

  /// 改播另一集或另一个版本（Swiftfin 的 `playNewItem`）。取代仍在进行的播完查询。
  func playNewItem(intent: PlaybackIntent) {
    guard state != .stopped, let itemID = intent.item.id else { return }
    #if DEBUG
      if previewSession != nil { return }
    #endif
    nextLookupTask?.cancel()
    nextLookupTask = nil
    isSwitchingItem = true
    let start = intent.configuration.startSeconds.map { $0.seconds } ?? 0
    onSwitchItem(itemID, intent.configuration.mediaSourceID, start, intent.item.queuedEpisode) {
      [weak self] result in
      guard let self, !self.isStopped else { return }
      let message: String?
      switch result {
      case .switched:
        self.itemDidChange()
        return
      case .failed(let reason): message = reason
      case .discarded: message = nil
      }
      self.isSwitchingItem = false
      switch Self.afterFailedSwitch(message: message, currentItemEnded: self.currentItemEnded) {
      case .stay(let error): if let error { self.commandError = error }
      case .exit(let notice): self.finish(notice: notice)
      }
    }
  }

  /// 转码码率与分辨率：MoviePilot-TV 只直连原文件，界面不会提供这两项（见 PlaybackSettingsActionButton.swift）。
  func setBitrate(bitrate: PlaybackBitrate) {}

  func setResolution(resolution: PlaybackResolution) {}

  /// 画中画：tvOS 播放不提供（Swiftfin tvOS 也去掉了画中画按钮）。
  func startPictureInPicture() {}

  func stopPictureInPicture() {}

  // MARK: 播放器事件

  /// 用户发出的播放/暂停在播放器确认前保持；之后跟随播放器的实际暂停状态（与 Swiftfin MPVMediaPlayer 相同）。
  private func observeEvents() {
    eventObservation = enginePlayer.observe { [weak self] event, generation in
      guard let self, !self.isStopped else { return }
      self.handlePlayerEvent(event, generation: generation)
    }
    positionObservation = enginePlayer.observePosition { [weak self] position in
      guard let self, !self.isStopped, position.isFinite else { return }
      self.publishPosition(.milliseconds(Int64(max(0, position) * 1000)))
    }
  }

  /// 处理一条播放器事件（测试也直接调用它模拟播放器）。`generation` 是事件所属的那次载入（`AetherPlayer.generation`）：
  /// 换条目后才处理到的上一条目的事件（比如播完）不能算到新条目头上，直接丢弃。失败由 `PlaybackSession` 处理。
  func handlePlayerEvent(_ event: AetherPlayer.Event, generation: UInt64) {
    guard !isStopped, generation == enginePlayer.generation else { return }
    switch event {
    case .statusChanged(.ended):
      ended()
      guard !isStopped else { return }
      refreshPlaybackState()
      syncPlaybackRequestStatus()
    case .statusChanged, .updated:
      refreshPlaybackState()
      syncPlaybackRequestStatus()
    case .failed, .seekStarted, .positionConfirmed:
      break
    }
  }

  /// 界面上播放位置的最小刷新步长。
  static let positionPublishStep: Duration = .milliseconds(250)

  /// 播放器每秒报约 10 次位置；控制条显示时进度条和时间若跟着每次重算，真机上主线程占用明显。
  /// 进度条一像素就是好几秒，时间文字按秒显示，因此位置变化满 0.25 秒才更新界面（Swiftfin 原版每帧更新）。
  /// 跳转目标仍立即显示（见 `seconds`）；向 Emby 上报的进度直接读播放器，不受影响。
  private func publishPosition(_ position: Duration) {
    let delta = position > observedPosition ? position - observedPosition : observedPosition - position
    guard delta >= Self.positionPublishStep || (position == .zero && observedPosition != .zero) else { return }
    observedPosition = position
  }

  /// 从播放器读一次就绪、可跳转、缓冲与时长；没变就不写，避免界面重建。
  private func refreshPlaybackState() {
    let duration = enginePlayer.duration
    let next = PlaybackState(
      isReady: hasStarted && enginePlayer.isPlaybackReady,
      isSeekable: enginePlayer.isSeekable || enginePlayer.status == .ended,
      isBuffering: enginePlayer.isBuffering,
      duration: duration.isFinite && duration > 0 ? .milliseconds(Int64(duration * 1000)) : nil)
    if playbackState != next {
      playbackState = next
    }
    // 播放器知道章节时每次都跟上（之后还可能换算到新的时间轴，见 `AetherPlayer.chapters`）；
    // 还不知道时（载入、换音轨或回前台重建中）保留上次的，不闪成按片长分段。换条目时由 `prepareItem` 清空。
    if let chapters = enginePlayer.chapters, embeddedChapters != chapters {
      embeddedChapters = chapters
    }
  }

  private func syncPlaybackRequestStatus() {
    guard enginePlayer.isPlaybackReady, canControlPlayback else { return }
    let observed: PlaybackRequestStatus
    switch enginePlayer.status {
    case .paused: observed = .paused
    case .playing: observed = .playing
    default: return
    }
    guard pendingPlaybackStatus == nil || pendingPlaybackStatus == observed else { return }
    pendingPlaybackStatus = nil
    if playbackRequestStatus != observed {
      playbackRequestStatus = observed
    }
  }

}

// MARK: - 按集队列

/// 按集队列跟随的播放界面（见 MoviePilotEpisodeQueue.swift）。
extension MediaSession: EpisodeQueueHost {
  var currentItem: BaseItemDto? { playbackItem?.baseItem }
  var episodeSource: any EpisodeQueueSource { userSession }
}

extension UserSession: EpisodeQueueSource {}

// MARK: - MediaPlayerItem

/// 与 Swiftfin `MediaPlayerItem` 同名：当前条目、片源、轨道选择、偏移与预览图。轨道选择直接读写 `AetherPlayer`。
/// 字幕关闭时记住所选轨道，再打开时恢复。
@MainActor
@Observable
final class MediaPlayerItem {
  nonisolated deinit {}

  let baseItem: BaseItemDto
  let mediaSource: PlaybackMediaSourceInfo
  /// 服务器给所播片源的章节。播放界面显示的章节由 `MediaSession.chapters` 按片长和播放器读到的章节算出。
  let serverChapters: [ServerChapter]
  /// 没有截图的章节卡片显示的图标：电影、剧集各用自己的。其他类型现在不会起播（见 `PlaybackError.unsupportedItemType`），
  /// 万一有也用中性的图片图标，不装成电影。
  let chapterPlaceholderSymbol: String
  let segments: MediaSegmentObserver? = MediaSegmentObserver()
  var configuration = MediaPlaybackConfiguration()

  @ObservationIgnored private let player: AetherPlayer
  /// 字幕关闭时记住的轨道；nil 表示还没选过，打开时用默认轨道。
  private var disabledSubtitleTrackIndex: Int?

  #if DEBUG
    /// UI 预览：假轨道表与选中状态。见 `PreviewSupport/Fixtures/PlayerFixtures.swift`。
    var previewTracks: UIPlayerPreviewTracks?

    func installPreviewTracks(_ tracks: UIPlayerPreviewTracks) {
      previewTracks = tracks
    }
  #endif

  var audioOffset: Duration = .zero {
    didSet {
      #if DEBUG
        if previewTracks != nil { return }
      #endif
      player.setAudioDelay(audioOffset.seconds)
    }
  }

  var subtitleOffset: Duration = .zero {
    didSet {
      #if DEBUG
        if previewTracks != nil { return }
      #endif
      player.setSubtitleDelay(subtitleOffset.seconds)
    }
  }

  /// MoviePilot-TV 不提供第二字幕。
  var secondarySubtitleOffset: Duration = .zero

  init(
    baseItem: BaseItemDto, source: ServerMediaSource, player: AetherPlayer, startSeconds: Double
  ) {
    self.baseItem = baseItem
    mediaSource = PlaybackMediaSourceInfo(source: source)
    self.player = player
    serverChapters = source.chapters
    let placeholderSymbol: String
    switch baseItem.type {
    case .movie: placeholderSymbol = AppSymbol.movie
    case .episode: placeholderSymbol = AppSymbol.tv
    default: placeholderSymbol = AppSymbol.imagePlaceholder
    }
    chapterPlaceholderSymbol = placeholderSymbol
    var configuration = MediaPlaybackConfiguration()
    configuration.startSeconds = .milliseconds(Int64(startSeconds * 1000))
    configuration.selectMediaSource(id: source.id)
    self.configuration = configuration
  }

  private var canSelectTracks: Bool {
    #if DEBUG
      if previewTracks != nil { return true }
    #endif
    return player.isPlaybackReady
  }

  private func stream(for track: PlayerTrack, offset: Int, type: MediaStreamType) -> MediaStream {
    MediaStream(
      index: track.id,
      type: type,
      displayTitle: PlayerTrackLabel.text(for: track, index: offset),
      codec: track.codec)
  }

  var videoStreams: [MediaStream] {
    (mediaSource.mediaStreams ?? []).filter { $0.type == .video }
  }

  var audioStreams: [MediaStream] {
    #if DEBUG
      if let previewTracks { return previewTracks.audio }
    #endif
    return player.audioTracks.enumerated().map { stream(for: $1, offset: $0, type: .audio) }
  }

  var subtitleStreams: [MediaStream] {
    #if DEBUG
      if let previewTracks { return previewTracks.subtitles }
    #endif
    return player.subtitleTracks.enumerated().map { stream(for: $1, offset: $0, type: .subtitle) }
  }

  /// MoviePilot-TV 不提供第二字幕。
  var secondarySubtitleStreams: [MediaStream] { [] }
  var supportsSecondarySubtitles: Bool { false }
  /// MoviePilot-TV 不提供“向后跳转时临时显示字幕”。
  var isShowingSubtitlesOnSkipBack: Bool { false }

  /// 换音轨时引擎在原位置重建这一条目，画面会停顿一下。
  var selectedAudioStreamIndex: Int? {
    get {
      #if DEBUG
        if let previewTracks { return previewTracks.selectedAudioIndex }
      #endif
      return player.selectedAudioTrackID
    }
    set {
      #if DEBUG
        if previewTracks != nil {
          previewTracks?.selectedAudioIndex = newValue
          return
        }
      #endif
      guard canSelectTracks, let newValue, newValue != player.selectedAudioTrackID,
        player.audioTracks.contains(where: { $0.id == newValue })
      else { return }
      player.selectAudioTrack(newValue)
    }
  }

  var selectedSubtitleStreamIndex: Int? {
    #if DEBUG
      if let previewTracks { return previewTracks.selectedSubtitleIndex }
    #endif
    return player.selectedSubtitleTrackID
  }

  var selectedSecondarySubtitleStreamIndex: Int? { nil }

  var subtitlesEnabled: Bool {
    #if DEBUG
      if let previewTracks { return previewTracks.subtitlesEnabled }
    #endif
    return player.selectedSubtitleTrackID != nil
  }

  func subtitleTrackIndex(secondary: Bool) -> Int {
    guard !secondary else { return -1 }
    #if DEBUG
      if let previewTracks {
        if previewTracks.subtitlesEnabled {
          return previewTracks.selectedSubtitleIndex ?? previewTracks.defaultSubtitleIndex ?? -1
        }
        return previewTracks.disabledSubtitleIndex ?? previewTracks.defaultSubtitleIndex ?? -1
      }
    #endif
    let index: Int =
      if subtitlesEnabled {
        player.selectedSubtitleTrackID ?? -1
      } else {
        disabledSubtitleTrackIndex ?? defaultSubtitleTrackIndex
      }
    guard player.subtitleTracks.contains(where: { $0.id == index }) else { return -1 }
    return index
  }

  private var defaultSubtitleTrackIndex: Int {
    #if DEBUG
      if let previewTracks { return previewTracks.defaultSubtitleIndex ?? -1 }
    #endif
    return player.subtitleTracks.first(where: \.isDefault)?.id ?? player.subtitleTracks.first?.id ?? -1
  }

  /// 字幕开着时切换轨道（选“无”即关闭）；关着时只记住，下次打开用它。
  func setSubtitleTrack(index: Int, secondary: Bool) {
    #if DEBUG
      if previewTracks != nil {
        guard !secondary,
              index == -1 || previewTracks?.subtitles.contains(where: { $0.index == index }) == true
        else { return }
        previewTracks?.disabledSubtitleIndex = index
        if index == -1 {
          previewTracks?.subtitlesEnabled = false
          previewTracks?.selectedSubtitleIndex = nil
        } else if previewTracks?.subtitlesEnabled == true {
          previewTracks?.selectedSubtitleIndex = index
        }
        return
      }
    #endif
    guard !secondary, canSelectTracks,
      index == -1 || player.subtitleTracks.contains(where: { $0.id == index })
    else { return }
    let wasEnabled = subtitlesEnabled
    disabledSubtitleTrackIndex = index
    if wasEnabled { selectSubtitle(index) }
  }

  func setSubtitlesEnabled(_ enabled: Bool) {
    #if DEBUG
      if previewTracks != nil {
        guard enabled != subtitlesEnabled else { return }
        previewTracks?.subtitlesEnabled = enabled
        if enabled {
          let remembered = previewTracks?.disabledSubtitleIndex ?? -1
          previewTracks?.selectedSubtitleIndex =
            remembered == -1 ? previewTracks?.defaultSubtitleIndex : remembered
        }
        return
      }
    #endif
    guard canSelectTracks, enabled != subtitlesEnabled else { return }
    var index = subtitleTrackIndex(secondary: false)
    if enabled {
      if index < 0 { index = defaultSubtitleTrackIndex }
      selectSubtitle(index)
    } else {
      disabledSubtitleTrackIndex = index
      selectSubtitle(-1)
    }
  }

  private func selectSubtitle(_ index: Int) {
    let track = player.subtitleTracks.first { $0.id == index }
    if player.selectedSubtitleTrackID != track?.id {
      player.selectSubtitleTrack(track?.id)
    }
  }

  /// 从当前位置继续播放同一条目（换版本用）。
  func resumingIntent(at seconds: Duration) -> PlaybackIntent {
    var configuration = configuration
    configuration.startSeconds = seconds
    return PlaybackIntent(item: baseItem, configuration: configuration)
  }
}

/// 轨道显示名：片源写了标题就只用标题，否则用语言加编码。
enum PlayerTrackLabel {
  static func text(for track: PlayerTrack, index: Int) -> String {
    var parts: [String] = []
    if let title = track.title {
      parts.append(title)
    } else {
      if let language = track.language.flatMap({ trimmedNonEmpty([$0]) }) {
        parts.append(Locale.current.localizedString(forLanguageCode: language) ?? language)
      } else {
        parts.append("轨道 \(index + 1)")
      }
      if !track.codec.isEmpty, track.codec != "unknown" { parts.append(track.codec.uppercased()) }
    }
    if track.isForced { parts.append("强制") }
    if track.isExternal { parts.append("外挂") }
    return parts.joined(separator: " · ")
  }
}
