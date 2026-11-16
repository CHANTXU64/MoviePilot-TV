import enum AetherEngine.PlaybackState
import enum AetherEngine.VideoRoute
import Combine
import Foundation

@testable import MoviePilot_TV

/// 播放器跟随的四个引擎发布值（状态、会话就绪、解码方式、文件里的章节）的替身。
/// 测试里真实引擎打不开测试地址，读不到文件，也到不了就绪；替身和引擎一样用 `@Published`（赋值前发出新值），
/// 按引擎的赋值顺序发值，经 `AetherPlayer` 生产代码里的同一套订阅进入播放器，再由播放器的事件交给播放界面。
/// 需要界面在两步之间处理事件的，测试分步调用并在中间等待。
@MainActor
final class EngineSignalsStandIn {
  // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
  nonisolated deinit {}

  @Published private(set) var state: PlaybackState = .idle
  @Published private(set) var isSessionReady = false
  @Published private(set) var videoRoute: VideoRoute = .none
  @Published private(set) var mediaChapters: [ServerChapter] = []

  var signals: AetherPlayer.EngineSignals {
    AetherPlayer.EngineSignals(
      state: $state.eraseToAnyPublisher(), isSessionReady: $isSessionReady.eraseToAnyPublisher(),
      videoRoute: $videoRoute.eraseToAnyPublisher(), mediaChapters: $mediaChapters.eraseToAnyPublisher())
  }

  /// 首次起播（自动播放）：定下解码方式并发布换算好的章节，会话就绪，然后开始播放。
  func finishReading(chapters: [ServerChapter]) {
    settleRoute(chapters: chapters)
    isSessionReady = true
    state = .playing
  }

  /// 定下解码方式：`playbackBackend` 的 didSet 先改 `videoRoute`，再把章节换算到这条时间轴上重新发布。
  func settleRoute(chapters: [ServerChapter], route: VideoRoute = .loopback) {
    videoRoute = route
    publishChapters(chapters)
  }

  /// 定下解码方式后重新发布章节：软件解码的时钟按第一帧定下零点，时间轴随之换算。
  /// 没有名字的章节按引擎的给法传空字符串，经生产代码的 `AetherPlayer.fileChapter` 换成播放器的章节。
  func publishChapters(_ chapters: [ServerChapter]) {
    mediaChapters = chapters.map { AetherPlayer.fileChapter(name: $0.name ?? "", startSeconds: $0.startSeconds) }
  }

  /// 回前台重建（URL 片源重新 `load`）：`stopInternal` 让会话不就绪、解码方式回到 `.none`，
  /// `loadSession` 再把状态设成载入中、清空章节。
  func beginReloadAfterBackgroundTeardown() {
    isSessionReady = false
    videoRoute = .none
    state = .loading
    mediaChapters = []
  }

  /// 暂停方式载入（回前台时原本暂停着）：会话就绪时状态直接落到 `.paused`，这时解码方式还没定下，
  /// 要等载入返回后 `settleRoute` 才重新发布章节。
  func becomeReadyPaused() {
    isSessionReady = true
    state = .paused
  }

  /// 换音轨等内部重建（`stopInternal` 不清章节）：会话不就绪、解码方式回到 `.none`，章节留着上次的。
  func beginReopenKeepingChapters() {
    isSessionReady = false
    videoRoute = .none
  }

  /// 内部重建完成：定下解码方式（章节可能换算到新的时间轴），会话就绪，接着播放。
  func finishReopen(chapters: [ServerChapter]) {
    settleRoute(chapters: chapters)
    isSessionReady = true
    state = .playing
  }
}
