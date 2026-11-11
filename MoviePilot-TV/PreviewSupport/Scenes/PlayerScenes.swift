#if DEBUG
import SwiftUI

// 「播放器」预览分组。画面渲染的是真实的 VideoPlayer / PlaybackControls / 面板与菜单入口，
// 数据来自 PlayerFixtures 里的假会话；不启动 mpv 媒体流，也不访问媒体服务器。
// 场景 ID 统一以 player. 开头，注册进预览目录由 PreviewCatalogView 的维护方负责。

/// 播放器预览分组。
@MainActor
enum UIPreviewScenesPlayer {

  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "player",
      title: "播放器",
      scenes: [
        scene(
          id: "player.loading",
          title: "起播加载中",
          note: "假会话处于起播前：activity = .loading、isReady = false。画面为黑场，时间旁显示「加载中」，工具栏按钮禁用；不加载真实媒体。",
          configuration: .loading,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .hang]
        ),
        scene(
          id: "player.failure",
          title: "起播失败",
          note: "模拟起播失败：状态为 .error，顶部 toast 使用线上失败文案。预览每 1.4 秒重放一次，避免默认 2 秒后消失。",
          configuration: .failed(message: "无法播放该影片，请检查与媒体服务器的网络连接"),
          behaviors: [UIPreviewBehaviorKey.playerFailure: .failure]
        ),
        scene(
          id: "player.playing.controls",
          title: "播放中 · 控件可见",
          note: "正常播放：位置 16:08 / 45:32，已选「简体中文 · ASS（内嵌）」与「国语 · DTS-HD MA 5.1」。视频画面来自 MPVUI，预览未加载流，因此为黑场；控件、章节刻度与面板入口照常渲染。",
          configuration: .playing,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.playing.hidden",
          title: "播放中 · 控件隐藏",
          note: "控件收起后的播放画面；预览在界面出现后主动收起控件，用于核对隐藏态。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.hideControls = true
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.paused",
          title: "暂停",
          note: "暂停状态：时间旁显示暂停图标，播放按钮为继续。",
          configuration: .paused,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.scrubbing",
          title: "拖动进度 · 预览缩略图",
          note: "正在拖动进度条：显示章节刻度和本地生成的预览缩略图（PreviewImageProvider 的章节来源），没有网络图片请求。",
          configuration: .scrubbing,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.subtitles.menu",
          title: "字幕菜单 · 开启与选轨",
          note: "字幕菜单入口：字幕已开启并选中「简体中文 · ASS（内嵌）」，另有繁体中文、English PGS 与外挂 SRT。tvOS 原生菜单无法由预览代码自动展开，本场景把焦点停在「字幕」按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.off",
          title: "字幕菜单 · 关闭",
          note: "在字幕菜单中关闭字幕后：字幕按钮变为关闭样式，字幕轨选择仍保留，重新开启时恢复。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.subtitlesOff
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.offset",
          title: "字幕偏移",
          note: "字幕偏移调整面板（真实 PlaybackAdjustmentSupplement）：当前 -1.5 秒。面板由预览直接打开。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.subtitleOffset = .milliseconds(-1_500)
            value.guest = .subtitleOffset
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.subtitles.style",
          title: "字幕菜单 · 文本样式入口",
          note: "字幕文本样式列表和「开放字幕样式设置」都在字幕菜单内，需要手动按遥控器展开；本场景同样把焦点停在字幕按钮，记录样式入口所在位置。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.subtitles.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSubtitles: .data]
        ),
        scene(
          id: "player.audio.menu",
          title: "音轨菜单",
          note: "音轨菜单入口：已选「英语 · E-AC-3 5.1」，另有国语 DTS-HD 与国语 AAC 评论轨。tvOS 原生菜单需手动展开，本场景把焦点停在「音频」按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.selectedAudioIndex = 1
            value.focusAction = VideoPlayerActionButton.audio.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerAudio: .data]
        ),
        scene(
          id: "player.audio.offset",
          title: "音频偏移",
          note: "音频偏移调整面板（真实 PlaybackAdjustmentSupplement）：当前 +0.25 秒，用于核对音画不同步时的调整界面。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.audioOffset = .milliseconds(250)
            value.guest = .audioOffset
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerAudio: .data]
        ),
        scene(
          id: "player.chapters",
          title: "章节面板",
          note: "章节面板（真实 MediaChaptersSupplement）：五个章节，当前 16:08 落在「第二幕：轨道上的回声」。章节图未接真实地址，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .chapters
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerChapters: .data]
        ),
        scene(
          id: "player.queue",
          title: "队列 · 下一集",
          note: "队列面板（真实 MediaQueueView）：本季五集，当前第七集；工具栏上一集/下一集按钮由队列提供。海报地址未接真实图片，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .queue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerQueue: .data]
        ),
        scene(
          id: "player.playbackSettings.menu",
          title: "播放设置菜单 · 版本",
          note: "播放设置菜单入口：两个可直连版本（4K HDR / 1080p），菜单内显示「版本」选择。MoviePilot-TV 只直连，不显示码率与分辨率。原生菜单需手动展开，本场景把焦点停在设置按钮。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.focusAction = VideoPlayerActionButton.playbackSettings.rawValue
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSettings: .data]
        ),
        scene(
          id: "player.speed",
          title: "播放速度",
          note: "倍速调整面板（真实 PlaybackAdjustmentSupplement.playbackSpeed）：当前 1.25×，预设 0.5×–2×，作用于假会话的播放速率。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.rate = 1.25
            value.guest = .playbackSpeed
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerSpeed: .data]
        ),
        scene(
          id: "player.ended",
          title: "播放结束",
          note: "播放结束：位置到片尾 45:32、状态 .stopped、显示暂停图标。线上此时会退出播放器，预览为便于查看保留画面。",
          configuration: .ended,
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
        scene(
          id: "player.info",
          title: "简介 · 演职员",
          note: "简介面板（真实 MediaInfoSupplement）：简介、类型、评分、演职员来自 fixture 的 BaseItemDto；海报地址为空，显示占位。",
          configuration: {
            var value = UIPlayerPreviewConfiguration.playing
            value.supplement = .info
            return value
          }(),
          behaviors: [UIPreviewBehaviorKey.playerPlayback: .data]
        ),
      ]
    )
  }

  private static func scene(
    id: String,
    title: String,
    note: String,
    configuration: UIPlayerPreviewConfiguration,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: .playback,
      behaviors: behaviors
    ) {
      UIPreviewPageHost {
        UIPlayerPreviewHost(configuration: configuration)
      }
    }
  }
}

// MARK: - 预览宿主

private struct UIPlayerPreviewHost: View {
  let configuration: UIPlayerPreviewConfiguration

  @State private var box: UIPlayerPreviewBox?

  var body: some View {
    ZStack {
      Color.black

      if let box {
        VideoPlayer(mediaSession: box.session, previewViewState: box.viewState)
      }
    }
    .ignoresSafeArea()
    .onAppear {
      guard box == nil else { return }
      box = UIPlayerPreviewBox(configuration: configuration)
    }
    .task(id: box?.id) {
      guard let box else { return }
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      box.applyAfterAppear()

      guard let message = box.configuration.toast else { return }
      while !Task.isCancelled {
        box.viewState.toastProxy.present(message, systemName: AppSymbol.playbackError)
        try? await Task.sleep(for: .seconds(1.4))
      }
    }
  }
}

/// 预览会话与 ViewState 的组合。放在 `@State` 里，避免 SwiftUI 重求值时反复创建 mpv 播放器。
@MainActor
final class UIPlayerPreviewBox {
  let id = UUID()
  let configuration: UIPlayerPreviewConfiguration
  let session: MediaSession
  let viewState: VideoPlayer.ViewState

  init(configuration: UIPlayerPreviewConfiguration) {
    self.configuration = configuration

    let session = UIPlayerPreviewFixtures.makeSession(configuration: configuration)
    self.session = session

    let viewState = VideoPlayer.ViewState()
    self.viewState = viewState
    viewState.connect(mediaSession: session)
    session.start()
  }

  /// 等播放器容器出现后再补上拖动、面板、隐藏控件等状态。`VideoPlayer` 会在首次出现时
  /// 主动显示控件，因此这些状态不能提前设置。
  func applyAfterAppear() {
    if configuration.startScrubbing {
      viewState.beginScrub()
      if let target = configuration.scrubTarget {
        viewState.scrubbedSeconds = target
      }
    }

    if let supplement = configuration.supplement {
      switch supplement {
      case .info:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("MediaInfo-") })?.id
      case .chapters:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("Chapters-") })?.id
      case .queue:
        viewState.selectedSupplementID = viewState.supplements
          .first(where: { $0.id.hasPrefix("Queue-") })?.id
      }
    }

    if let guest = configuration.guest {
      switch guest {
      case .subtitleOffset:
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.subtitleOffset)
      case .audioOffset:
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.audioOffset)
      case .playbackSpeed:
        let range = session.player?.supportedRates ?? (0.5...2.0)
        viewState.presentGuestSupplement(PlaybackAdjustmentSupplement.playbackSpeed(range: range))
      }
    }

    if configuration.hideControls {
      viewState.hideControls()
    }

    if let action = configuration.focusAction {
      viewState.focusCoordinator.focus(VideoPlayer.ViewState.Focus.action(action))
    }
  }
}
#endif
