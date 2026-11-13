import AVKit
import Combine
import MPVUI
import SwiftUI
import UIKit

// 把移植自 Swiftfin 的 tvOS 播放界面（Views/Player/Swiftfin）接到 MoviePilot-TV 的播放会话上。
// Swiftfin 界面读写的是它自己的 `MediaSession`（依赖 Jellyfin），这里按同名提供只实现界面用到成员的适配对象，
// 底层是 `PlaybackSession` 与它创建的 `MPVPlayer`；条目、章节等数据类型见 SwiftfinPlayerModels.swift。

/// mpv 内核的全屏播放界面。播放中换集、换版本只替换会话里的条目，界面不重建。
/// `MediaSession` 在界面出现时创建一次：外层状态变化会让 SwiftUI 反复执行本视图的 init，
/// 在 init 里创建会每次多建一套再丢掉。
struct MPVPlaybackScreen: View {
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

  var body: some View {
    Group {
      if let mediaSession {
        VideoPlayer(mediaSession: mediaSession)
      } else {
        Color.black.ignoresSafeArea()
      }
    }
    .onAppear {
      guard mediaSession == nil else { return }
      mediaSession = MediaSession(session: session, onExit: onExit, onSwitchItem: onSwitchItem)
    }
  }
}

/// Swiftfin 播放器设置项的固定取值（均为 Swiftfin 默认值）。
enum VideoPlayerDefaults {
  static let jumpBackwardInterval: Duration = .seconds(15)
  static let jumpForwardInterval: Duration = .seconds(15)
  /// 长按右键加速的倍率。
  static let longPressSpeedMultiplier: Double = 2
  static let playbackRates: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]
  /// 控制条收起后再按 Menu 是否先确认再退出。
  static let confirmClose = false
  /// 进度条上显示章节刻度。
  static let chapterSlider = true
  static let appMaximumBitrate: PlaybackBitrate = .auto
  /// 拖动预览图来源：Swiftfin 默认只用 trickplay、不回退到章节图。
  static let previewImageScrubbing: PreviewImageScrubbingOption = .trickplay(fallbackToChapters: false)
  static let supplements: [VideoPlayerSupplementType] = VideoPlayerSupplementType.supportedCases
  /// 工具栏按钮。Swiftfin 默认还有「填充」（`.aspectFill`），这里不放。
  static let barActionButtons: [VideoPlayerActionButton] = [.autoPlay, .playPreviousItem, .playNextItem]
  static let menuActionButtons: [VideoPlayerActionButton] = [
    .audio, .audioOffset, .subtitles, .subtitleOffset, .playbackSpeed, .pictureInPicture, .playbackSettings,
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

/// `MediaSession.player` 指向的 mpv 播放器描述。
@MainActor
final class MPVPlayerAdapter: VideoMediaPlayer, MediaPlayerOffsetProviding {
  nonisolated deinit {}

  private let player: MPVPlayer

  init(player: MPVPlayer) {
    self.player = player
  }

  let displayTitle = "MPV"
  var supportedRates: ClosedRange<Double> { 0.1...5 }

  var videoState: VideoPlaybackState {
    guard let dimensions = player.mediaInformation.presentationDimensions else { return .init() }
    return VideoPlaybackState(videoSize: CGSize(width: dimensions.width, height: dimensions.height))
  }
}

// MARK: - MediaSession

/// 播放界面读到的会话状态。播放位置、就绪、缓冲由 mpv 的时间流和事件流写入，值不变时不发布，
/// 与 Swiftfin `MPVMediaPlayer.updateTiming` 相同：mpv 每帧都会刷新位置和缓存状态，界面若直接读 `MPVPlayer`
/// 的这些属性，整个控制层（含菜单）会跟着每帧重建。
/// 跳转在这里合并连续请求，界面立即显示目标位置，mpv 完成后再回到真实位置。
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

  let mpvPlayer: MPVPlayer
  let textSubtitles = TextSubtitlePresentation()
  let logger = SessionLogger()
  let session: PlaybackSession
  private(set) var playbackItem: MediaPlayerItem?
  let userSession: UserSession
  private(set) var queue: (any MediaPlayerQueue)?
  private(set) var playbackRequestStatus: PlaybackRequestStatus = .playing
  var commandError: String?

  var rate: Double = 1 {
    didSet { mpvPlayer.setPlaybackRate(effectiveRate) }
  }

  /// 就绪、可跳转、缓冲与时长，值变化时才更新。
  private(set) var playbackState = PlaybackState()
  /// mpv 报告的播放位置，变化满 `positionPublishStep` 才更新（见 `publishPosition`）。只有进度条和时间读它。
  private var observedPosition: Duration = .zero
  /// 界面显示的跳转目标；mpv 完成跳转后清空。
  private var pendingSeek: Duration?
  private(set) var isStopped = false
  /// 播放界面出现后才起播；起播前 `MPVPlayer` 可能还留着上一集的就绪状态。
  private var hasStarted = false
  /// 正在为换集、换版本解析新条目。
  private var isSwitchingItem = false
  /// 开了「匹配内容」时，从起播到电视切好显示模式整屏盖黑（见 `coverUntilDisplaySettles`）。只是遮挡，不影响播放。
  private(set) var isCoveringForDisplay: Bool

  @ObservationIgnored private let playerAdapter: MPVPlayerAdapter
  @ObservationIgnored private let onExit: Exit
  @ObservationIgnored private let onSwitchItem: SwitchItem
  @ObservationIgnored private var pendingPlaybackStatus: PlaybackRequestStatus?
  @ObservationIgnored private var seekTask: Task<Void, Never>?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var timingTask: Task<Void, Never>?
  @ObservationIgnored private var itemObservations: [AnyCancellable] = []
  @ObservationIgnored private var queueObservation: AnyCancellable?
  @ObservationIgnored private var displayTask: Task<Void, Never>?
  /// 播完时重新查下一集。
  @ObservationIgnored private var nextLookupTask: Task<Void, Never>?
  /// 当前条目已经播完（之后要么接着播下一集，要么退出）。这时换集失败，就没有画面可以留在原处。
  @ObservationIgnored private var currentItemEnded = false
  /// 已按片源信息向电视申请过显示模式，退出时要还原。
  @ObservationIgnored private var hasRequestedDisplayMode = false

  init(
    session: PlaybackSession,
    onExit: @escaping Exit,
    onSwitchItem: @escaping SwitchItem
  ) {
    self.session = session
    self.onExit = onExit
    self.onSwitchItem = onSwitchItem
    let player = session.makeMPVPlayer()
    mpvPlayer = player
    playerAdapter = MPVPlayerAdapter(player: player)
    userSession = UserSession(session: session)
    isCoveringForDisplay = Self.displayManager?.isDisplayCriteriaMatchingEnabled == true
  }

  var player: (any MediaPlayer)? { playerAdapter }

  var effectiveRate: Double {
    let range = playerAdapter.supportedRates
    return min(max(rate, range.lowerBound), range.upperBound)
  }

  /// 当前条目。片长是所播文件的时长（见 `PlaybackDuration`）：进度条、跳转上限、跳过片头片尾都读这里，
  /// 与续播询问和看完判定用同一个值。
  var item: BaseItemDto {
    var item = playbackItem?.baseItem ?? BaseItemDto(id: session.item.id)
    item.runTimeTicks = session.playback.durationSeconds(playerSeconds: playbackState.duration?.seconds)
      .map { Int($0 * 10_000_000) }
    return item
  }

  var state: State {
    if isStopped { return .stopped }
    guard hasStarted else { return .initial }
    if isSwitchingItem { return .loadingItem }
    return playbackState.isReady ? .playback : .preparing
  }

  /// 当前显示的播放位置：有未完成的跳转时是跳转目标。
  var seconds: Duration {
    pendingSeek ?? observedPosition
  }

  var isSeeking: Bool { pendingSeek != nil }

  var canControlPlayback: Bool {
    (state == .preparing || state == .playback) && playbackState.isReady
  }

  var canSeek: Bool {
    canControlPlayback && playbackState.isSeekable && !item.isLiveStream
  }

  var activity: Activity? {
    switch state {
    case .initial, .loadingItem: return .loading
    case .preparing where !playbackState.isReady: return .loading
    case .error, .stopped: return nil
    case .preparing, .playback: break
    }
    if pendingSeek != nil || mpvPlayer.state == .seeking { return .seeking }
    return playbackState.isBuffering ? .buffering : nil
  }

  var videoSize: CGSize { playerAdapter.videoState.videoSize }

  /// 投屏只在 iOS 上有。
  var isRemotePlayback: Bool { false }

  var playbackBitrate: PlaybackBitrate { VideoPlayerDefaults.appMaximumBitrate }

  // MARK: 生命周期

  /// 界面出现时调用：先打开文字字幕拦截（SRT 等由界面用系统字体绘制），再交给 `PlaybackSession` 起播。
  func start() {
    guard !hasStarted, !isStopped else { return }
    hasStarted = true
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
    playbackRequestStatus = .playing
    guard hasStarted else { return }
    loadCurrentItem()
  }

  /// 起播会话里的当前条目，首次起播和换集、换版本共用。文字字幕拦截、倍速和显示模式都要在交给 mpv 之前设好：
  /// 字幕拦截从载入起生效，显示模式提前申请才能和载入同时进行。
  private func loadCurrentItem() {
    prepareItem()
    textSubtitles.start(mpvPlayer)
    mpvPlayer.setPlaybackRate(effectiveRate)
    let requested = requestDisplayMode()
    session.start()
    coverUntilDisplaySettles(afterRequest: requested)
    refreshPlaybackState()
  }

  /// 开了「匹配内容」时，按片源信息在起播前向电视申请显示模式（见 `DisplayModeHint`），切换与载入同时进行；
  /// 切换期间 MPVUI 会暂停时钟。认不准格式时不申请，交给 MPVUI 开播后自己申请。返回是否已申请。
  private func requestDisplayMode() -> Bool {
    guard let display = Self.displayManager, display.isDisplayCriteriaMatchingEnabled,
      let criteria = session.mediaSource.displayModeHint?.makeCriteria()
    else { return false }
    display.preferredDisplayCriteria = criteria
    hasRequestedDisplayMode = true
    return true
  }

  /// 开了「匹配内容」时，从起播到电视切好显示模式整屏盖黑：切换时 HDMI 黑屏约 1 秒，之前露出的首帧和控件就像闪了一下。
  /// 只是遮挡，播放照常进行。已提前申请过模式时，MPVUI 再申请同一模式不会再切，就绪后只留很短的时间确认。
  private func coverUntilDisplaySettles(afterRequest requested: Bool) {
    displayTask?.cancel()
    guard let display = Self.displayManager, display.isDisplayCriteriaMatchingEnabled else {
      isCoveringForDisplay = false
      return
    }
    isCoveringForDisplay = true
    var timing = DisplayModeGate.Timing()
    if requested { timing.settle = .milliseconds(200) }
    displayTask = Task { [weak self] in
      await DisplayModeGate.wait(for: display, timing: timing) { [weak self] in
        guard let self else { return true }
        return DisplayModeGate.isSettled(self.mpvPlayer)
      }
      guard let self, !Task.isCancelled else { return }
      self.isCoveringForDisplay = false
    }
  }

  /// 前台窗口的显示管理器。MPVUI 也是向播放画面所在窗口的这个对象申请显示模式。
  private static var displayManager: (any DisplayModeSwitching)? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return (scene?.keyWindow ?? scene?.windows.first)?.avDisplayManager
  }

  /// 退出播放。可重复调用；实际停止和进度上报由外部的退出闭包（结束 `PlaybackSession`）完成。
  func stop() {
    finish(notice: nil)
  }

  private func finish(notice: String?) {
    guard !isStopped else { return }
    isStopped = true
    nextLookupTask?.cancel()
    nextLookupTask = nil
    displayTask?.cancel()
    displayTask = nil
    if hasRequestedDisplayMode {
      Self.displayManager?.preferredDisplayCriteria = nil
    }
    seekTask?.cancel()
    seekTask = nil
    pendingSeek = nil
    eventTask?.cancel()
    eventTask = nil
    timingTask?.cancel()
    timingTask = nil
    itemObservations.removeAll()
    queueObservation = nil
    textSubtitles.clear()
    onExit(notice)
  }

  /// 播放设置里可选的版本：只列能直接播放的片源，多于一个时才显示版本选择。
  static func versions(of sources: [ServerMediaSource]) -> [PlaybackMediaSourceInfo] {
    sources.filter(\.isDirectlyPlayable).map(PlaybackMediaSourceInfo.init(source:))
  }

  /// 为当前条目建立 `MediaPlayerItem`、片段与队列观察。
  private func prepareItem() {
    itemObservations.removeAll()
    var baseItem = BaseItemDto.playback(session.playback)
    baseItem.mediaSources = Self.versions(of: session.mediaSources)
    let item = MediaPlayerItem(
      baseItem: baseItem,
      source: session.mediaSource,
      player: mpvPlayer,
      connection: session.connection,
      startSeconds: session.startSeconds)
    playbackItem = item
    if let segments = item.segments {
      itemObservations.append(segments.observe(self))
    }

    if baseItem.type == .episode {
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

  enum EndAction {
    /// 正在换集，上一集刚好播完：等切换完成。
    case waitForSwitch
    case playNext(PlaybackIntent)
    /// 开着自动播放、按集播放，但还不知道下一集，或已知的下一集是跳过还没入库的集找到的：重新查一次再决定。
    case lookUpNext
    case exit
  }

  /// 播完后怎么做：开了自动播放且有下一集就接着播，否则退出（与 Swiftfin `MediaSession.ended` 相同）。
  /// 按集播放时，还不知道下一集（开播时没找到、或查询还没回来），或已知的下一集跳过了当时还没入库的集，
  /// 先重新查一次：播放期间那几集可能刚入库，应按顺序接上。
  /// 不看“能否控制播放”：mpv 先报告就绪变为否、再报告播完，到这里时它总是否。
  static func endAction(
    isSwitchingItem: Bool, isSeeking: Bool, isLiveStream: Bool, isAutoPlayEnabled: Bool,
    nextItem: PlaybackIntent?, canLookUpNext: Bool = false, nextNeedsRecheck: Bool = false
  ) -> EndAction {
    if isSwitchingItem { return .waitForSwitch }
    guard !isSeeking, !isLiveStream, isAutoPlayEnabled else { return .exit }
    if canLookUpNext, nextItem == nil || nextNeedsRecheck { return .lookUpNext }
    if let nextItem { return .playNext(nextItem) }
    return .exit
  }

  private func ended() {
    currentItemEnded = true
    let episodeQueue = queue as? MoviePilotEpisodeQueue
    switch Self.endAction(
      isSwitchingItem: isSwitchingItem, isSeeking: isSeeking, isLiveStream: item.isLiveStream,
      isAutoPlayEnabled: userSession.isAutoPlayEnabled, nextItem: queue?.nextItem,
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

  /// 片尾重新查下一集的结果怎么用：查询期间从工具栏关掉了自动播放，就和平常播完一样退出，不起播、也不说明原因。
  static func resultAfterLookUp(
    _ result: MoviePilotEpisodeQueue.NextLookup, isAutoPlayEnabled: Bool
  ) -> MoviePilotEpisodeQueue.NextLookup {
    isAutoPlayEnabled ? result : .unavailable(nil)
  }

  /// 重新查下一集，查询期间显示加载中；查到就接着播，查不到就退出并说明原因（已是最后一集时不说明）。
  /// 期间用户退出，或手动换了集（`playNewItem` 取消这次查询），结果都丢弃；关掉了自动播放见 `resultAfterLookUp`。
  private func lookUpNextAfterEnd(_ episodeQueue: MoviePilotEpisodeQueue) {
    isSwitchingItem = true
    nextLookupTask?.cancel()
    let endedItemID = session.item.id
    nextLookupTask = Task { [weak self] in
      let result = await episodeQueue.lookUpNext()
      guard let self, !Task.isCancelled, !self.isStopped, self.session.item.id == endedItemID else { return }
      self.nextLookupTask = nil
      self.isSwitchingItem = false
      switch Self.resultAfterLookUp(result, isAutoPlayEnabled: self.userSession.isAutoPlayEnabled) {
      case .play(let intent): self.playNewItem(intent: intent)
      case .unavailable(let reason): self.finish(notice: reason)
      }
    }
  }

  // MARK: 播放控制

  func setPlaybackRequestStatus(status: PlaybackRequestStatus) {
    guard state != .stopped, state != .error else { return }
    playbackRequestStatus = status
    guard hasStarted else { return }
    pendingPlaybackStatus = status
    switch status {
    case .playing: mpvPlayer.play()
    case .paused: mpvPlayer.pause()
    }
  }

  func togglePlayPause() {
    guard canControlPlayback else { return }
    setPlaybackRequestStatus(status: playbackRequestStatus == .playing ? .paused : .playing)
  }

  @discardableResult
  func seek(to position: Duration) -> Bool {
    guard canSeek else { return false }
    let limit = item.runtime
    let target = max(.zero, limit.map { min(position, $0) } ?? position)
    commandError = nil
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
  private func performPendingSeeks() async {
    defer { seekTask = nil }
    while pendingSeek != nil {
      // 合并连按，不推迟界面对每次按键的响应。
      try? await Task.sleep(for: .milliseconds(80))
      guard !Task.isCancelled, !isStopped, let target = pendingSeek else { return }
      guard canSeek else {
        pendingSeek = nil
        return
      }
      let succeeded: Bool
      do {
        _ = try await mpvPlayer.seekAndWait(to: target)
        succeeded = true
      } catch is CancellationError {
        return
      } catch {
        succeeded = false
      }
      guard !Task.isCancelled, !isStopped else { return }
      if pendingSeek == target {
        pendingSeek = nil
        if !succeeded { commandError = L10n.unableToSeek }
      }
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

  // MARK: mpv 事件

  /// 用户发出的播放/暂停在 mpv 确认前保持；之后跟随 mpv 的实际暂停状态（与 Swiftfin MPVMediaPlayer 相同）。
  private func observeEvents() {
    let events = mpvPlayer.makeEventStream()
    eventTask = Task { [weak self] in
      for await event in events {
        guard let self, !Task.isCancelled, !self.isStopped else { return }
        self.handlePlayerEvent(event.change, generation: event.generation)
      }
    }
    let timing = mpvPlayer.makeTimingStream()
    timingTask = Task { [weak self] in
      for await value in timing {
        guard let self, !Task.isCancelled, !self.isStopped else { return }
        // 上一条目的位置同样丢弃，见 `handlePlayerEvent`。
        guard value.generation == self.mpvPlayer.generation else { continue }
        self.publishPosition(value.position)
        self.refreshPlaybackState()
      }
    }
  }

  /// 处理一条 mpv 事件（测试也直接调用它模拟 mpv）。`generation` 是事件所属的那次载入（`MPVPlayer.generation`）：
  /// 事件流会留着还没读的事件，换条目后才读到的上一条目的事件（比如播完）不能算到新条目头上，直接丢弃。
  func handlePlayerEvent(_ change: MPVPlaybackEvent.Change, generation: UInt64) {
    guard !isStopped, generation == mpvPlayer.generation else { return }
    switch change {
    case .stateChanged(.ended):
      ended()
      guard !isStopped else { return }
      refreshPlaybackState()
      syncPlaybackRequestStatus()
    case .snapshot, .pauseChanged, .readinessChanged, .stateChanged:
      refreshPlaybackState()
      syncPlaybackRequestStatus()
    default:
      break
    }
  }

  /// 界面上播放位置的最小刷新步长。
  static let positionPublishStep: Duration = .milliseconds(250)

  /// mpv 几乎每帧报一次位置；控制条显示时进度条和时间若跟着每帧重算，真机上主线程占用明显。
  /// 进度条一像素就是好几秒，时间文字按秒显示，因此位置变化满 0.25 秒才更新界面（Swiftfin 原版每帧更新）。
  /// 跳转目标仍立即显示（见 `seconds`）；向 Emby 上报的进度直接读 mpv，不受影响。
  private func publishPosition(_ position: Duration) {
    let delta = position > observedPosition ? position - observedPosition : observedPosition - position
    guard delta >= Self.positionPublishStep || (position == .zero && observedPosition != .zero) else { return }
    observedPosition = position
  }

  /// 从 mpv 读一次就绪、可跳转、缓冲与时长；没变就不写，避免界面重建。
  private func refreshPlaybackState() {
    let next = PlaybackState(
      isReady: hasStarted && mpvPlayer.isPlaybackReady,
      isSeekable: mpvPlayer.isSeekable || mpvPlayer.state == .ended,
      isBuffering: mpvPlayer.bufferStatus.isBuffering,
      duration: mpvPlayer.duration > .zero ? mpvPlayer.duration : nil)
    if playbackState != next {
      playbackState = next
    }
  }

  private func syncPlaybackRequestStatus() {
    guard mpvPlayer.isPlaybackReady, canControlPlayback else { return }
    let observed: PlaybackRequestStatus = mpvPlayer.isPaused ? .paused : .playing
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

/// 与 Swiftfin `MediaPlayerItem` 同名：当前条目、片源、轨道选择、偏移与预览图。轨道选择直接读写 `MPVPlayer`。
/// 字幕关闭时记住所选轨道，再打开时恢复。
@MainActor
@Observable
final class MediaPlayerItem {
  nonisolated deinit {}

  let baseItem: BaseItemDto
  let mediaSource: PlaybackMediaSourceInfo
  let chapters: [ChapterInfo.FullInfo]
  let segments: MediaSegmentObserver? = MediaSegmentObserver()
  @ObservationIgnored let previewImageProvider: PreviewImageProvider?
  var configuration = MediaPlaybackConfiguration()

  @ObservationIgnored private let player: MPVPlayer
  /// 字幕关闭时记住的轨道；nil 表示还没选过，打开时用默认轨道。
  private var disabledSubtitleTrackIndex: Int?

  var audioOffset: Duration = .zero {
    didSet { player.setAudioDelay(audioOffset) }
  }

  var subtitleOffset: Duration = .zero {
    didSet { player.setSubtitleDelay(subtitleOffset, for: .primary) }
  }

  /// MoviePilot-TV 不提供第二字幕。
  var secondarySubtitleOffset: Duration = .zero

  init(
    baseItem: BaseItemDto, source: ServerMediaSource, player: MPVPlayer, connection: any MediaServerConnection,
    startSeconds: Double
  ) {
    self.baseItem = baseItem
    mediaSource = PlaybackMediaSourceInfo(source: source)
    self.player = player
    chapters = baseItem.fullChapterInfo
    var configuration = MediaPlaybackConfiguration()
    configuration.startSeconds = .milliseconds(Int64(startSeconds * 1000))
    configuration.selectMediaSource(id: source.id)
    let images = PreviewImageCache(session: MediaServerHTTP.sharedSession)
    previewImageProvider = PreviewImageProvider(
      option: VideoPlayerDefaults.previewImageScrubbing,
      item: baseItem,
      mediaSourceID: source.id,
      chapters: chapters,
      client: JellyfinClient(connection: connection),
      resolveImage: { await images.image(for: $0) })
    self.configuration = configuration
    images.provider = previewImageProvider
  }

  private var canSelectTracks: Bool { player.isPlaybackReady }

  private func stream(for track: MPVMediaTrack, offset: Int, type: MediaStreamType) -> MediaStream {
    MediaStream(
      index: track.mpvID,
      type: type,
      displayTitle: MPVTrackLabel.text(for: track, index: offset),
      codec: track.codec)
  }

  var videoStreams: [MediaStream] {
    (mediaSource.mediaStreams ?? []).filter { $0.type == .video }
  }

  var audioStreams: [MediaStream] {
    player.audioTracks.enumerated().map { stream(for: $1, offset: $0, type: .audio) }
  }

  var subtitleStreams: [MediaStream] {
    player.subtitleTracks.enumerated().map { stream(for: $1, offset: $0, type: .subtitle) }
  }

  /// MoviePilot-TV 不提供第二字幕。
  var secondarySubtitleStreams: [MediaStream] { [] }
  var supportsSecondarySubtitles: Bool { false }
  /// MoviePilot-TV 不提供“向后跳转时临时显示字幕”。
  var isShowingSubtitlesOnSkipBack: Bool { false }

  var selectedAudioStreamIndex: Int? {
    get { player.audioTracks.first(where: \.isSelected)?.mpvID }
    set {
      guard canSelectTracks, let newValue,
        let track = player.audioTracks.first(where: { $0.mpvID == newValue }), !track.isSelected
      else { return }
      player.selectTrack(track.id)
    }
  }

  var selectedSubtitleStreamIndex: Int? {
    player.selectedSubtitle(for: .primary)?.mpvID
  }

  var selectedSecondarySubtitleStreamIndex: Int? { nil }

  var subtitlesEnabled: Bool {
    player.selectedSubtitle(for: .primary) != nil
  }

  func subtitleTrackIndex(secondary: Bool) -> Int {
    guard !secondary else { return -1 }
    let index: Int =
      if subtitlesEnabled {
        player.selectedSubtitle(for: .primary)?.mpvID ?? -1
      } else {
        disabledSubtitleTrackIndex ?? defaultSubtitleTrackIndex
      }
    guard player.subtitleTracks.contains(where: { $0.mpvID == index }) else { return -1 }
    return index
  }

  private var defaultSubtitleTrackIndex: Int {
    player.subtitleTracks.first(where: \.isDefault)?.mpvID ?? player.subtitleTracks.first?.mpvID ?? -1
  }

  /// 字幕开着时切换轨道（选“无”即关闭）；关着时只记住，下次打开用它。
  func setSubtitleTrack(index: Int, secondary: Bool) {
    guard !secondary, canSelectTracks,
      index == -1 || player.subtitleTracks.contains(where: { $0.mpvID == index })
    else { return }
    let wasEnabled = subtitlesEnabled
    disabledSubtitleTrackIndex = index
    if wasEnabled { selectSubtitle(index) }
  }

  func setSubtitlesEnabled(_ enabled: Bool) {
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
    let track = player.subtitleTracks.first { $0.mpvID == index }
    if player.selectedSubtitle(for: .primary)?.id != track?.id {
      player.selectSubtitle(track?.id, for: .primary)
    }
  }

  /// 从当前位置继续播放同一条目（换版本用）。
  func resumingIntent(at seconds: Duration) -> PlaybackIntent {
    var configuration = configuration
    configuration.startSeconds = seconds
    return PlaybackIntent(item: baseItem, configuration: configuration)
  }
}

/// 拖动预览图的下载缓存（对应 Swiftfin 的 `PlaybackTemporaryFiles.image(for:)`，这里只放内存）。
@MainActor
final class PreviewImageCache {
  nonisolated deinit {}

  weak var provider: PreviewImageProvider?
  private let session: URLSession
  private var images: [Int: UIImage] = [:]
  private var tasks: [Int: Task<UIImage?, Never>] = [:]

  init(session: URLSession) {
    self.session = session
  }

  func image(for id: Int) async -> UIImage? {
    if let image = images[id] { return image }
    if let task = tasks[id] { return await task.value }
    guard let url = provider?.downloadURL(for: id) else { return nil }
    let session = session
    let task = Task<UIImage?, Never> {
      guard let (data, _) = try? await session.data(from: url) else { return nil }
      return UIImage(data: data)
    }
    tasks[id] = task
    let image = await task.value
    tasks[id] = nil
    images[id] = image
    return image
  }
}

/// 轨道显示名：片源写了标题就只用标题，否则用语言加编码。
enum MPVTrackLabel {
  static func text(for track: MPVMediaTrack, index: Int) -> String {
    var parts: [String] = []
    if let title = trimmedNonEmpty([track.title]) {
      parts.append(title)
    } else {
      if let language = track.language.map({ code in
        Locale.current.localizedString(forLanguageCode: code) ?? code
      }) {
        parts.append(language)
      } else {
        parts.append("轨道 \(index + 1)")
      }
      if let codec = track.codec, !codec.isEmpty { parts.append(codec.uppercased()) }
    }
    if track.isForced { parts.append("强制") }
    if track.isExternal { parts.append("外挂") }
    return parts.joined(separator: " · ")
  }
}
