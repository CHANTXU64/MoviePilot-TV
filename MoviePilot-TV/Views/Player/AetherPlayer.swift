import AVFoundation
import AetherEngine
import Combine
import Foundation
import Observation
import SwiftUI
import UIKit

// AetherEngine 只在这个文件和字幕、失败提示两处直接使用。播放会话和播放界面经 `AetherPlayer` 读写播放器，
// 引擎的类型在这里换成与引擎无关的值（`PlaybackFailure`、`PlayerTrack`、`SubtitleSnapshot`）。

// MARK: - 与引擎无关的值

/// 播放失败。由引擎的 `PlaybackErrorInfo` 转来；给用户的提示按 `kind` 分类，见 `PlaybackFailureMessage`。
nonisolated struct PlaybackFailure: Equatable, Sendable {
  /// 引擎的失败类别（`PlaybackErrorKind.rawValue`，引擎承诺取值不变）；引擎没给类别时为 nil。
  var kind: String?
  var underlyingDomain: String?
  var underlyingCode: Int?
  /// 解封装失败时 FFmpeg 的原始错误码（负数）。
  var ffmpegErrorCode: Int?
  /// 引擎给的原文。一部分是引擎的英文句子，一部分是系统按设备语言翻译的 AVFoundation 错误，只写日志、不拿来分类。
  var message: String

  init(
    kind: String? = nil, underlyingDomain: String? = nil, underlyingCode: Int? = nil, ffmpegErrorCode: Int? = nil,
    message: String
  ) {
    self.kind = kind
    self.underlyingDomain = underlyingDomain
    self.underlyingCode = underlyingCode
    self.ffmpegErrorCode = ffmpegErrorCode
    self.message = message
  }
}

/// 一条音轨或字幕轨。
nonisolated struct PlayerTrack: Equatable, Identifiable, Sendable {
  /// 引擎的轨道编号（文件里的流序号），选轨时交回引擎。
  let id: Int
  /// 片源写的轨道标题；没写时为 nil。
  let title: String?
  let language: String?
  /// libavcodec 的解码器名，如 `aac`、`subrip`、`pgssub`。
  let codec: String
  let isDefault: Bool
  let isForced: Bool
  let isExternal: Bool

  init(
    id: Int, title: String? = nil, language: String? = nil, codec: String, isDefault: Bool = false,
    isForced: Bool = false, isExternal: Bool = false
  ) {
    self.id = id
    self.title = title
    self.language = language
    self.codec = codec
    self.isDefault = isDefault
    self.isForced = isForced
    self.isExternal = isExternal
  }

  /// 引擎给轨道的名字：片源写了标题就是标题，没写时是它自己拼的「ENG (subrip)」「Track 3 (subrip)」，后者不当标题。
  static func title(fromEngineName name: String, language: String?, codec: String) -> String? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    if let language, name == "\(language.uppercased()) (\(codec))" { return nil }
    let generated = "^Track \\d+ \\(" + NSRegularExpression.escapedPattern(for: codec) + "\\)$"
    if name.range(of: generated, options: .regularExpression) != nil { return nil }
    return name
  }
}

/// 此刻该显示的字幕。引擎把 SRT、ASS 等文字字幕和 PGS 等图片字幕都交给应用绘制。
nonisolated struct SubtitleSnapshot: Equatable {
  struct TextCue: Equatable, Identifiable {
    let id: Int
    let spans: [SubtitleSpan]
    /// ASS 小键盘对齐（1 左下 … 9 右上）；nil 时放在画面底部居中。
    let alignment: Int?
    /// ASS `\pos` 给的锚点，按画面归一化（y 从上往下）；nil 时按对齐放。
    let position: CGPoint?

    var text: String { spans.map(\.text).joined() }
  }

  struct ImageCue: Equatable, Identifiable {
    let id: Int
    let image: CGImage
    /// 在画面里的位置，按画面宽高归一化。
    let frame: CGRect

    static func == (lhs: ImageCue, rhs: ImageCue) -> Bool {
      lhs.id == rhs.id && lhs.frame == rhs.frame
    }
  }

  var texts: [TextCue] = []
  var images: [ImageCue] = []

  var isEmpty: Bool { texts.isEmpty && images.isEmpty }
  /// 文字字幕的全文，读屏和系统字幕上报用。
  var text: String { texts.map(\.text).joined(separator: "\n") }
}

/// 一段同样式的字幕文字。
nonisolated struct SubtitleSpan: Equatable, Sendable {
  struct Color: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
  }

  let text: String
  var color: Color? = nil
  var isBold = false
  var isItalic = false
  var isUnderlined = false
  var isStruckThrough = false
}

// MARK: - 播放器

/// 一次全屏播放用的播放器：包着一个 AetherEngine（每个播放会话一个，会话结束时 `stop()`）。
/// 状态由引擎的发布值同步过来；播放会话和播放界面经 `observe` 收事件。状态、刷新和失败事件在下一轮主线程发出：
/// 引擎的发布值在赋值前通知，这时同步处理（比如播完就退出、停掉引擎）会重入引擎正在进行的赋值。
/// 「开始跳转」和「位置已确认」同步发出，处理方只记位置、不碰引擎，退出时读得到最后一次采样。
/// 事件带发生时所属载入的 `generation`，换条目后才处理到的上一条目的事件按它丢弃。
@MainActor
@Observable
final class AetherPlayer {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  enum Status: Equatable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case ended
    case failed
  }

  enum Event: Equatable {
    case statusChanged(Status)
    /// 就绪、可跳转、缓冲、时长、首帧、显示模式切换或章节有变化（合并到下一轮主线程再发，那时引擎的值都已更新）。
    case updated
    /// 播放失败。载入期间的失败在载入返回时报，之后的失败在状态变成出错时报，每次载入只报一次。
    case failed(PlaybackFailure)
    /// 包含引擎接到的系统拖动和应用内跳转。
    case seekStarted
    /// 已出画面且未处于跳转中的位置。同步交给进度上报，退出时可以读到最后一次采样。
    case positionConfirmed(Double, isPlaying: Bool)
  }

  /// 播放器跟随的四个引擎发布值：状态、会话就绪、解码方式和文件里的章节。平时取自引擎；
  /// 测试换成自己的 `@Published` 替身（同样在赋值前发出新值），经同一套订阅进入播放器。
  struct EngineSignals {
    var state: AnyPublisher<PlaybackState, Never>
    var isSessionReady: AnyPublisher<Bool, Never>
    var videoRoute: AnyPublisher<VideoRoute, Never>
    /// 引擎的 `mediaChapters`，逐条经 `AetherPlayer.fileChapter` 换好。
    var mediaChapters: AnyPublisher<[ServerChapter], Never>

    init(
      state: AnyPublisher<PlaybackState, Never>, isSessionReady: AnyPublisher<Bool, Never>,
      videoRoute: AnyPublisher<VideoRoute, Never>, mediaChapters: AnyPublisher<[ServerChapter], Never>
    ) {
      self.state = state
      self.isSessionReady = isSessionReady
      self.videoRoute = videoRoute
      self.mediaChapters = mediaChapters
    }

    init(_ engine: AetherEngine) {
      // 引擎的章节类型与 Swiftfin 的 `ChapterInfo` 同名，引擎模块又与引擎类同名，写不出它的类型，就地换掉。
      self.init(
        state: engine.$state.eraseToAnyPublisher(), isSessionReady: engine.$isSessionReady.eraseToAnyPublisher(),
        videoRoute: engine.$videoRoute.eraseToAnyPublisher(),
        mediaChapters: engine.$mediaChapters
          .map { $0.map { AetherPlayer.fileChapter(name: $0.name, startSeconds: $0.startSeconds) } }
          .eraseToAnyPublisher())
    }
  }

  /// 引擎给的一条文件章节。没写名字的章节引擎给空字符串，`ServerChapter` 把它当作没有名字（界面按位置命名）。
  nonisolated static func fileChapter(name: String, startSeconds: Double) -> ServerChapter {
    ServerChapter(name: name, startSeconds: startSeconds)
  }

  /// 字幕偏移能调到的最大幅度（秒），与播放界面的调节范围一致。
  static let subtitleOffsetLimit: Double = 5
  /// 音频偏移能调到的最大幅度（秒）：引擎把音频延迟限制在 ±2 秒。
  static let audioOffsetLimit: Double = 2
  /// 优先选中文字幕（简体在前）；没有中文字幕时选片源标了默认的字幕轨（与原先 mpv 内核的默认行为相同）。
  static let preferredSubtitleLanguages = ["zh-Hans", "zh"]

  /// 字幕：引擎交来的字幕按播放时间筛出此刻要显示的。
  let subtitles = SubtitlePresentation()

  private(set) var audioTracks: [PlayerTrack] = []
  private(set) var hasDroppedAudio = false
  private(set) var subtitleTracks: [PlayerTrack] = []
  private(set) var selectedAudioTrackID: Int?
  /// 正在显示的字幕轨；字幕关闭时为 nil。
  private(set) var selectedSubtitleTrackID: Int?
  /// 画面显示的尺寸（已按像素宽高比换算）；还没读到时为零。
  private(set) var videoSize: CGSize = .zero

  @ObservationIgnored private(set) var status: Status = .idle
  /// 文件里内嵌的章节（Matroska、MP4），与进度条同一时间轴；空表示文件里没有章节。
  /// nil 表示还不知道：引擎还没定下解码方式（载入、重建中）。引擎定下解码方式时才把章节换算到那条时间轴上发出，
  /// 在那之前给的空列表不代表没有章节，就绪也不代表已经定下（暂停方式重建时先就绪）。
  /// 定下后引擎还可能换算后再发一次（软件解码的时钟按第一帧定下零点、播放中换了解码方式）。这两样变了都发 `.updated`。
  var chapters: [ServerChapter]? { hasVideoRoute ? fileChapters : nil }
  @ObservationIgnored private var fileChapters: [ServerChapter] = []
  /// 引擎已定下解码方式（`videoRoute` 不是 `.none`）。
  @ObservationIgnored private var hasVideoRoute = false
  /// 引擎的会话已就绪（`AetherEngine.isSessionReady`）。
  @ObservationIgnored private var isSessionReady = false
  /// 每次载入或停止加一，事件带上它。
  @ObservationIgnored private(set) var generation: UInt64 = 0
  /// 最近一次交给引擎的地址，可能含密钥，不得写入日志。
  @ObservationIgnored private(set) var loadedURL: URL?
  @ObservationIgnored private let engine: AetherEngine?
  @ObservationIgnored private let events = PassthroughSubject<(Event, UInt64), Never>()
  @ObservationIgnored private let positions = PassthroughSubject<Double, Never>()
  @ObservationIgnored private var subscriptions: [AnyCancellable] = []
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// 已经返回的那次载入；载入返回前的出错由载入自己报。
  @ObservationIgnored private var returnedLoadGeneration: UInt64?
  @ObservationIgnored private var reportedFailureGeneration: UInt64?
  @ObservationIgnored private var isUpdateScheduled = false
  @ObservationIgnored private var rate: Double = 1
  @ObservationIgnored private var audioDelay: Double = 0
  private struct SeekWaiter {
    let continuation: CheckedContinuation<Bool, Never>
    let timeout: Task<Void, Never>
    /// 为 nil 时等首次开始，或等 deferred 交接后的实际跳转。
    var eventID: UInt64?
  }
  @ObservationIgnored private var seekWaiter: SeekWaiter?
  @ObservationIgnored private var seekWaiterID: UInt64 = 0

  convenience init() {
    self.init(signals: nil)
  }

  /// 测试用：状态、会话就绪和章节改由 `signals` 发出，引擎的这三个值不再跟随；其余照常读引擎。
  convenience init(signalsForTesting signals: EngineSignals) {
    self.init(signals: signals)
  }

  private init(signals: EngineSignals?) {
    do {
      engine = try AetherEngine()
    } catch {
      Logger.error("[Playback] 播放器初始化失败: \(error)")
      engine = nil
    }
    guard let engine else { return }
    // 应用自己不放别的声音：停止播放时交还音频会话，功放不会一直循环最后一帧 Atmos。
    engine.deactivatesAudioSessionOnStop = true
    // 关闭持续的字幕提前预读，避免重复读取远端文件。文字靠主读取，跳转可能错过落点前已开始的那句。
    // PGS 等图片轨仍会在起播和跳转落点补读，远端可能为此额外传输一个 32 MiB 的 Range。
    engine.maximumSubtitleDelaySeconds = Self.subtitleOffsetLimit
    engine.maximumSubtitleAdvanceSeconds = 0
    subscribe(to: engine, signals: signals ?? EngineSignals(engine))
  }

  // MARK: 读数

  var isPlaybackReady: Bool {
    guard engine != nil, isSessionReady else { return false }
    switch status {
    case .playing, .paused, .seeking, .ended: return true
    case .idle, .loading, .failed: return false
    }
  }

  var isSeekable: Bool { engine?.canSeek ?? false }
  var isBuffering: Bool { engine?.isBuffering ?? false }
  var isSeeking: Bool { engine?.isSeeking ?? false }
  /// 片长（秒）；还没读到时为 0。
  var duration: Double { engine?.duration ?? 0 }
  /// 播放位置（秒），与进度条同一轴。
  var position: Double { engine?.clock.currentTime ?? 0 }
  /// 首帧已经可以显示（每次载入重新计）。
  var hasFirstFrame: Bool { engine?.hasFirstFrameReadyForDisplay ?? false }
  /// 起播正等电视切换显示模式（「匹配内容」或 SDR/HDR 切换）。
  var isAwaitingDisplaySwitch: Bool { engine?.isAwaitingDisplaySwitch ?? false }

  /// 播放画面。
  @ViewBuilder
  var surface: some View {
    if let engine {
      AetherPlayerSurface(engine: engine)
    } else {
      Color.black
    }
  }

  // MARK: 事件

  /// 收播放器事件，返回值释放即停止。事件在主线程发出。
  func observe(_ handler: @escaping @MainActor (Event, UInt64) -> Void) -> AnyCancellable {
    events.sink { event, generation in handler(event, generation) }
  }

  /// 收播放位置（约每秒 10 次）。
  func observePosition(_ handler: @escaping @MainActor (Double) -> Void) -> AnyCancellable {
    positions.sink { handler($0) }
  }

  private func emit(_ event: Event) {
    post(event, generation: generation)
  }

  /// 下一轮主线程发出事件，按发出顺序到达。
  private func post(_ event: Event, generation eventGeneration: UInt64) {
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated { self?.events.send((event, eventGeneration)) }
    }
  }

  // MARK: 控制

  /// 载入并自动起播。`startTime` 为续播位置（秒）。字幕、音频偏移和倍速回到默认，见 `MediaPlayerItem`。
  func load(_ url: URL, startTime: Double?) {
    loadTask?.cancel()
    generation += 1
    let loadGeneration = generation
    loadedURL = url
    returnedLoadGeneration = nil
    // 上一条目的就绪和播完状态不留给新条目。
    setStatus(.loading)
    subtitles.reset()
    audioDelay = 0
    hasDroppedAudio = false
    resolveSeekWaiter(false)
    // 解码方式与内嵌章节同步清掉：换集原位交接保留的是旧画面，不是旧条目的数据。
    // 引擎异步载入完成前 chapters 仍返回旧值，不在这里清就会被 refreshPlaybackState 写回界面缓存，带进新条目。
    hasVideoRoute = false
    fileChapters = []
    guard let engine else {
      reportFailure(
        PlaybackFailure(kind: PlaybackFailureMessage.initializationKind, message: "AetherEngine init failed"),
        generation: loadGeneration)
      return
    }
    var options = LoadOptions()
    options.preferredSubtitleLanguages = Self.preferredSubtitleLanguages
    options.skipsContainerAttachments = true
    options.matchContentEnabled = DisplayModeGate.currentDisplay?.isDisplayCriteriaMatchingEnabled ?? true
    loadTask = Task { [weak self] in
      do {
        try await engine.load(url: url, startPosition: startTime, options: options)
        self?.loadDidReturn(loadGeneration)
      } catch is CancellationError {
        // 被更新的载入或停止取代，不算失败。
      } catch {
        self?.loadDidFail(error, generation: loadGeneration)
      }
    }
  }

  /// 停止当前条目。`keepsDisplayMode` 为真时电视保持当前显示模式，留给下一次载入；否则还原并交还音频会话。
  func stop(keepsDisplayMode: Bool = false) {
    // 还没开始执行的载入不再开始：停止之后再起播就没人管了。
    loadTask?.cancel()
    loadTask = nil
    generation += 1
    returnedLoadGeneration = nil
    hasDroppedAudio = false
    resolveSeekWaiter(false)
    subtitles.reset()
    engine?.stop(resetDisplayCriteria: !keepsDisplayMode, finalTeardown: !keepsDisplayMode)
  }

  /// 换条目：停住当前画面，交给下一次载入原位替换。原生解码（`VideoRoute.loopback`/`.remoteBypass`）旧画面保留到新条目就绪、不出黑帧；
  /// 软件解码（`.software`）不支持原位交接，仍会露黑帧（见 `MediaSession.coverUntilStartupSettles` 的边界说明）。
  /// 引擎的原位交接不暂停播放，旧条目会一直播到新条目替换，这里先停住。
  func handOverForItemReplacement() {
    // 与 stop 一致：还在途的旧载入不再返回发布，避免它抢在新条目载入前写回旧状态。
    loadTask?.cancel()
    engine?.pause()
    engine?.prepareForItemReplacement()
  }

  func play() {
    guard let engine else { return }
    if engine.needsForegroundVideoRestore {
      restoreVideo(playing: true)
    } else {
      engine.play()
    }
  }

  func pause() {
    engine?.pause()
  }

  func setRate(_ rate: Double) {
    self.rate = rate
    engine?.setRate(Float(rate))
  }

  /// 音频偏移（秒），正数让声音晚出。引擎在原生路径上为此原位重载一次。
  func setAudioDelay(_ seconds: Double) {
    let clamped = min(max(seconds, -Self.audioOffsetLimit), Self.audioOffsetLimit)
    guard clamped != audioDelay else { return }
    audioDelay = clamped
    engine?.setAudioDelay(clamped)
  }

  /// 字幕偏移（秒），正数让字幕晚出。只改应用自己绘制的时间，不重载。
  func setSubtitleDelay(_ seconds: Double) {
    subtitles.delay = min(max(seconds, -Self.subtitleOffsetLimit), Self.subtitleOffsetLimit)
  }

  func selectAudioTrack(_ id: Int) {
    engine?.selectAudioTrack(index: id)
  }

  /// 选字幕轨；nil 关闭字幕。
  func selectSubtitleTrack(_ id: Int?) {
    guard let engine else { return }
    if let id {
      engine.selectSubtitleTrack(index: id)
    } else {
      engine.clearSubtitle()
    }
  }

  /// 跳到 `seconds`，等跳转落定（或被拒、卡住、被取代）后返回是否成功。一次只等一个跳转。
  func seek(to seconds: Double) async -> Bool {
    guard let engine else { return false }
    return await seek(to: seconds) { target in
      // AV1 软件路径需要指定精确模式，章节、片头和快进快退才能按指定位置落点。
      await engine.seek(to: target, exact: true)
    }
  }

  /// 回调可由测试驱动引擎事件的发布顺序。
  func seek(to seconds: Double, request: @escaping @MainActor (Double) async -> Void) async -> Bool {
    guard seconds.isFinite, !Task.isCancelled else { return false }
    resolveSeekWaiter(false)
    seekWaiterID &+= 1
    let id = seekWaiterID
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // 原生跳转最坏约 44 秒才报卡住。只在引擎一直没有给出结果时使用这个兜底。
        let timeout = Task { [weak self] in
          guard (try? await Task.sleep(for: .seconds(60))) != nil, let self, self.seekWaiterID == id else { return }
          self.resolveSeekWaiter(false)
        }
        seekWaiter = SeekWaiter(continuation: continuation, timeout: timeout)
        Task { [weak self] in
          guard let self, self.seekWaiterID == id, self.seekWaiter != nil else { return }
          await request(seconds)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self, self.seekWaiterID == id else { return }
        self.resolveSeekWaiter(false)
      }
    }
  }

  private func resolveSeekWaiter(_ succeeded: Bool) {
    guard let waiter = seekWaiter else { return }
    seekWaiter = nil
    waiter.timeout.cancel()
    waiter.continuation.resume(returning: succeeded)
  }

  // MARK: 引擎回调

  private func subscribe(to engine: AetherEngine, signals: EngineSignals) {
    // `@Published` 在赋值前发出新值：这里只用传进来的值，或合并到下一轮主线程再读引擎。
    signals.state.sink { [weak self] in self?.engineStateWillChange(to: $0) }.store(in: &subscriptions)
    signals.isSessionReady.sink { [weak self] ready in
      guard let self else { return }
      self.isSessionReady = ready
      self.scheduleUpdate()
    }
    .store(in: &subscriptions)
    signals.videoRoute.sink { [weak self] in self?.videoRouteDidChange($0) }.store(in: &subscriptions)
    signals.mediaChapters.sink { [weak self] in self?.mediaChaptersDidChange($0) }.store(in: &subscriptions)
    for publisher in [
      engine.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
      engine.$isSeeking.map { _ in () }.eraseToAnyPublisher(),
      engine.$isSourceSeekable.map { _ in () }.eraseToAnyPublisher(),
      engine.$duration.map { _ in () }.eraseToAnyPublisher(),
      engine.$hasFirstFrameReadyForDisplay.map { _ in () }.eraseToAnyPublisher(),
      engine.$isAwaitingDisplaySwitch.map { _ in () }.eraseToAnyPublisher(),
      engine.$sourceVideoWidth.map { _ in () }.eraseToAnyPublisher(),
      engine.$sourceVideoHeight.map { _ in () }.eraseToAnyPublisher(),
      engine.$softwareDisplaySize.map { _ in () }.eraseToAnyPublisher(),
    ] {
      publisher.sink { [weak self] in self?.scheduleUpdate() }.store(in: &subscriptions)
    }
    engine.seekEvents.sink { [weak self] in self?.seekDidChange($0) }.store(in: &subscriptions)
    engine.clock.$currentTime.sink { [weak self, weak engine] time in
      guard let self, let engine else { return }
      self.clockDidChange(
        time, status: self.status, hasFirstFrame: engine.hasFirstFrameReadyForDisplay,
        isSeeking: engine.isSeeking, isBuffering: engine.isBuffering)
    }
    .store(in: &subscriptions)
    engine.clock.$sourceTime.sink { [weak self] in self?.subtitles.update(time: $0) }.store(in: &subscriptions)
    engine.$subtitleCues.sink { [weak self] in self?.subtitles.update(cues: $0.map(TimedSubtitle.init)) }
      .store(in: &subscriptions)
    engine.$audioDelivery.sink { [weak self] in self?.audioDeliveryDidChange($0) }.store(in: &subscriptions)
    engine.$audioTracks.sink { [weak self] in self?.audioTracks = $0.map(PlayerTrack.init) }
      .store(in: &subscriptions)
    engine.$subtitleTracks.sink { [weak self] in self?.subtitleTracks = $0.map(PlayerTrack.init) }
      .store(in: &subscriptions)
    engine.$activeAudioTrackIndex.sink { [weak self] in self?.selectedAudioTrackID = $0 }.store(in: &subscriptions)
    engine.$activeSubtitleTrackIndex.sink { [weak self] in self?.selectedSubtitleTrackID = $0 }
      .store(in: &subscriptions)
    NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self, self.engine?.needsForegroundVideoRestore == true else { return }
        self.restoreVideo(playing: false)
      }
      .store(in: &subscriptions)
  }

  /// 引擎在同一次赋值里先改解码方式、再发换算好的章节；合并到下一轮主线程再发事件，界面读到的是两样都更新后的值。
  private func videoRouteDidChange(_ route: VideoRoute) {
    let next = route != .none
    guard next != hasVideoRoute else { return }
    hasVideoRoute = next
    scheduleUpdate()
  }

  private func mediaChaptersDidChange(_ next: [ServerChapter]) {
    guard next != fileChapters else { return }
    fileChapters = next
    scheduleUpdate()
  }

  func audioDeliveryDidChange(_ delivery: AudioDelivery) {
    let dropped = delivery == .droppedNoPipeline
    if hasDroppedAudio != dropped { hasDroppedAudio = dropped }
  }

  /// 跳转目标照常给进度条。引擎可能先发布 deferred 目标再发「开始」，观看记录从请求发出时就开始等。
  func clockDidChange(_ time: Double, status: Status, hasFirstFrame: Bool, isSeeking: Bool, isBuffering: Bool) {
    positions.send(time)
    guard time.isFinite, hasFirstFrame, !isSeeking, seekWaiter == nil else { return }
    switch status {
    case .playing, .paused, .ended:
      events.send((.positionConfirmed(max(0, time), isPlaying: status == .playing && !isBuffering), generation))
    case .idle, .loading, .seeking, .failed: break
    }
  }

  private func setStatus(_ next: Status) {
    guard status != next else { return }
    status = next
    emit(.statusChanged(next))
  }

  private func engineStateWillChange(to state: PlaybackState) {
    let next: Status
    switch state {
    case .idle: next = .idle
    case .loading: next = .loading
    case .playing: next = .playing
    case .paused: next = .paused
    case .seeking: next = .seeking
    case .ended: next = .ended
    case .error(let message):
      next = .failed
      // `errorInfo` 先于 `state` 赋值，这里读到的就是这次失败的。
      if returnedLoadGeneration == generation {
        reportFailure(Self.failure(engine?.errorInfo, message: message), generation: generation)
      }
    }
    setStatus(next)
  }

  private func loadDidReturn(_ loadGeneration: UInt64) {
    guard loadGeneration == generation, let engine else { return }
    returnedLoadGeneration = loadGeneration
    if case .error(let message) = engine.state {
      reportFailure(Self.failure(engine.errorInfo, message: message), generation: loadGeneration)
      return
    }
    if rate != 1 { engine.setRate(Float(rate)) }
    // 没有中文字幕时按片源默认的字幕轨。
    if !engine.isSubtitleActive, let fallback = engine.subtitleTracks.first(where: \.isDefault) {
      engine.selectSubtitleTrack(index: fallback.id)
    }
    scheduleUpdate()
  }

  private func loadDidFail(_ error: any Error, generation loadGeneration: UInt64) {
    guard loadGeneration == generation else { return }
    let info = engine?.errorInfo
    reportFailure(Self.failure(info, message: info?.message ?? String(describing: error)), generation: loadGeneration)
  }

  private func reportFailure(_ failure: PlaybackFailure, generation failedGeneration: UInt64) {
    guard failedGeneration == generation, reportedFailureGeneration != failedGeneration else { return }
    reportedFailureGeneration = failedGeneration
    post(.failed(failure), generation: failedGeneration)
  }

  private static func failure(_ info: PlaybackErrorInfo?, message: String) -> PlaybackFailure {
    PlaybackFailure(
      kind: info?.kind.rawValue, underlyingDomain: info?.underlyingDomain, underlyingCode: info?.underlyingCode,
      ffmpegErrorCode: info?.ffmpegErrorCode, message: info?.message ?? message)
  }

  private func scheduleUpdate() {
    guard !isUpdateScheduled else { return }
    isUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.isUpdateScheduled = false
        self.refreshVideoSize()
        self.events.send((.updated, self.generation))
      }
    }
  }

  /// 画面尺寸：软件解码路径用它实际显示的尺寸，原生路径用编码尺寸乘像素宽高比。
  private func refreshVideoSize() {
    guard let engine else { return }
    let coded = CGSize(width: CGFloat(engine.sourceVideoWidth), height: CGFloat(engine.sourceVideoHeight))
    subtitles.codedVideoSize = coded
    let size =
      engine.softwareDisplaySize
      ?? CGSize(width: coded.width * CGFloat(engine.sourceVideoPixelAspectRatio), height: coded.height)
    if videoSize != size { videoSize = size }
  }

  /// Deferred 交接会结束旧编号，随后才开始实际跳转。只有实际落定才向命令调用方返回成功。
  func seekDidChange(_ event: SeekEvent) {
    if event.outcome == .began { events.send((.seekStarted, generation)) }
    guard let waiter = seekWaiter, event.origin != .nativeScrub else { return }
    guard let awaitedEventID = waiter.eventID else {
      switch event.outcome {
      case .began:
        seekWaiter?.eventID = event.id
      case .rejected:
        resolveSeekWaiter(false)
      case .landed, .stalled, .superseded:
        break
      }
      return
    }
    guard event.id == awaitedEventID else { return }
    switch event.outcome {
    case .landed: resolveSeekWaiter(true)
    case .superseded where event.origin == .deferred: seekWaiter?.eventID = nil
    case .stalled, .rejected, .superseded: resolveSeekWaiter(false)
    case .began: break
    }
  }

  /// 回到前台：引擎在后台释放了画面，先在原位置重建。`playing` 为真时重建后接着播。
  private func restoreVideo(playing: Bool) {
    guard let engine else { return }
    let restoringGeneration = generation
    Task { [weak self] in
      do {
        try await engine.reloadAtCurrentPosition(applying: { $0.autoplay = playing })
      } catch is CancellationError {
      } catch {
        guard let self, restoringGeneration == self.generation else { return }
        Logger.warning("[Playback] 回到前台后重建画面失败: \(PlaybackLog.redacted(String(describing: error)))")
      }
    }
  }
}

extension PlayerTrack {
  fileprivate init(_ track: TrackInfo) {
    self.init(
      id: track.id, title: Self.title(fromEngineName: track.name, language: track.language, codec: track.codec),
      language: track.language, codec: track.codec, isDefault: track.isDefault, isForced: track.isForced,
      isExternal: track.isExternal)
  }
}

// MARK: - 字幕

/// 此刻要显示的字幕：引擎交来的字幕（按片源时间戳）减去字幕偏移后，和画面的片源时间比。
/// 片源时间约每秒更新 10 次；显示的字幕没变时不发布，界面不跟着重建。
@MainActor
@Observable
final class SubtitlePresentation {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  private(set) var snapshot: SubtitleSnapshot?

  /// 字幕偏移（秒），正数让字幕晚出。
  @ObservationIgnored var delay: Double = 0 {
    didSet { refresh() }
  }
  /// 视频的编码尺寸。图片字幕的位置按字幕画布给出，要先换算到画面上。
  @ObservationIgnored var codedVideoSize: CGSize = .zero {
    didSet { if codedVideoSize != oldValue { refresh() } }
  }
  @ObservationIgnored private var cues: [TimedSubtitle] = []
  @ObservationIgnored private var time: Double = 0

  func update(cues: [TimedSubtitle]) {
    self.cues = cues
    refresh()
  }

  func update(time: Double) {
    self.time = time
    refresh()
  }

  func reset() {
    cues = []
    delay = 0
    if snapshot != nil { snapshot = nil }
  }

  private func refresh() {
    let now = time - delay
    var next = SubtitleSnapshot()
    for cue in cues where cue.start <= now && now < cue.end {
      switch cue.content {
      case .text(let text):
        next.texts.append(text)
      case .image(let id, let image, let position, let canvas):
        next.images.append(
          SubtitleSnapshot.ImageCue(
            id: id, image: image, frame: Self.pictureFrame(of: position, canvas: canvas, codedVideo: codedVideoSize)))
      }
    }
    let shown = next.isEmpty ? nil : next
    if snapshot != shown { snapshot = shown }
  }

  /// 图片字幕在画面里的归一化位置。字幕画布按宽度对齐、上下居中放到编码画面上，再按编码画面归一化；
  /// 画布或画面尺寸未知时当作画布就是画面。
  nonisolated static func pictureFrame(of position: CGRect, canvas: CGSize, codedVideo: CGSize) -> CGRect {
    guard canvas.width > 0, canvas.height > 0, codedVideo.width > 0, codedVideo.height > 0 else { return position }
    let scale = codedVideo.width / canvas.width
    let canvasHeight = canvas.height * scale
    let top = (codedVideo.height - canvasHeight) / 2
    return CGRect(
      x: position.minX,
      y: (top + position.minY * canvasHeight) / codedVideo.height,
      width: position.width,
      height: position.height * canvasHeight / codedVideo.height)
  }
}

/// 引擎交来的一条字幕：片源时间戳上的起止，和文字或图片内容。
nonisolated struct TimedSubtitle {
  enum Content {
    case text(SubtitleSnapshot.TextCue)
    /// `position` 按字幕画布归一化，`canvas` 是画布的编码像素尺寸（未知时为零）。
    case image(id: Int, image: CGImage, position: CGRect, canvas: CGSize)
  }

  let start: Double
  let end: Double
  let content: Content
}

extension TimedSubtitle {
  fileprivate init(_ cue: SubtitleCue) {
    start = cue.startTime
    end = cue.endTime
    switch cue.body {
    case .text(let text):
      content = .text(
        SubtitleSnapshot.TextCue(
          id: cue.id, spans: [SubtitleSpan(text: text)], alignment: cue.placement?.alignment,
          position: cue.placement?.position))
    case .richText(let runs):
      content = .text(
        SubtitleSnapshot.TextCue(
          id: cue.id, spans: runs.map(SubtitleSpan.init), alignment: cue.placement?.alignment,
          position: cue.placement?.position))
    case .image(let image):
      content = .image(id: cue.id, image: image.cgImage, position: image.position, canvas: image.canvasSize)
    }
  }
}

extension SubtitleSpan {
  fileprivate init(_ run: SubtitleTextRun) {
    self.init(
      text: run.text, color: run.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) }, isBold: run.isBold,
      isItalic: run.isItalic, isUnderlined: run.isUnderlined, isStruckThrough: run.isStruckThrough)
  }
}

// MARK: - 日志

/// AetherEngine 里 FFmpeg 报的警告和错误转给当前播放会话写日志（见 `PlaybackSession.recordEngineLog`）。
/// 引擎的日志回调是全局的，在解封装、本地服务器等线程上调用，不能阻塞，所以转到主线程再交给会话。
/// 引擎自己的流水日志很多，不转，需要时用 Console.app 按 `de.superuser404.AetherEngine` 看。
enum PlaybackEngineLog {
  private static weak var sink: PlaybackSession?
  private static var isInstalled = false

  static func attach(_ session: PlaybackSession) {
    sink = session
    guard !isInstalled else { return }
    isInstalled = true
    EngineLog.structuredHandler = { @Sendable line, category, _ in
      guard category == .ffmpeg else { return }
      DispatchQueue.main.async {
        MainActor.assumeIsolated { sink?.recordEngineLog(line) }
      }
    }
  }

  static func detach(_ session: PlaybackSession) {
    if sink === session { sink = nil }
  }

  /// 引擎写系统日志时只认得出 `api_key` 这类常见密钥名，服务器主机名和设备标识会原样留下。
  /// 起播时把流地址里这几样登记给引擎遮盖，返回登记成功的值，停止或换条目时交回 `unregister`。
  static func register(secretsIn url: URL) -> [String] {
    secrets(in: url).filter { EngineLog.registerSecret($0) }
  }

  static func unregister(_ secrets: [String]) {
    secrets.forEach { EngineLog.unregisterSecret($0) }
  }

  /// 流地址里不该进系统日志的值：主机名、设备标识和访问密钥。
  nonisolated static func secrets(in url: URL) -> [String] {
    let sensitiveKeys: Set<String> = ["deviceid", "api_key", "x-emby-token", "x-mediabrowser-token", "token"]
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let values = query.filter { sensitiveKeys.contains($0.name.lowercased()) }.compactMap(\.value)
    var seen = Set<String>()
    return ([url.host(percentEncoded: false)].compactMap { $0 } + values)
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }
}
