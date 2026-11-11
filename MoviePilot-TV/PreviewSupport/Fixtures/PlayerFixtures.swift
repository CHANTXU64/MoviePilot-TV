#if DEBUG
import Combine
import Foundation
import Observation
import UIKit

// 播放器预览 fixture：用真实的播放界面类型（MediaSession / MediaPlayerItem / BaseItemDto）
// 组装一套假会话。数据只进入界面状态，不启动 mpv 解码、不访问媒体服务器、不请求真实流。
// 界面需要的少量状态注入见 MediaSession.previewSession（Views/Player/SwiftfinPlayerAdapter.swift）。

extension UIPreviewBehaviorKey {
  /// 播放器常规播放状态（控件可见）。
  static let playerPlayback = "player.playback"
  /// 字幕菜单入口及字幕开关状态。
  static let playerSubtitles = "player.subtitles"
  /// 音轨菜单入口。
  static let playerAudio = "player.audio"
  /// 章节面板。
  static let playerChapters = "player.chapters"
  /// 队列 / 下一集面板。
  static let playerQueue = "player.queue"
  /// 播放设置（版本）菜单入口。
  static let playerSettings = "player.settings"
  /// 倍速面板。
  static let playerSpeed = "player.speed"
  /// 起播失败提示。
  static let playerFailure = "player.failure"
}

/// 播放器预览需要界面呈现的状态。位置、轨道、队列都由这里提供，不经过 mpv。
struct UIPlayerPreviewSession {
  enum Supplement {
    case info
    case chapters
    case queue
  }

  enum Guest {
    case subtitleOffset
    case audioOffset
    case playbackSpeed
  }

  var state: MediaSession.State = .playback
  var isReady = true
  var canControlPlayback = true
  var canSeek = true
  var isBuffering = false
  var isPaused = false
  var position: Duration = .seconds(968)
  var duration: Duration? = .seconds(2_732)
  var activity: MediaSession.Activity?
  var videoSize: CGSize = .init(width: 3_840, height: 2_160)
  var baseItem: BaseItemDto
  var tracks: UIPlayerPreviewTracks
  var queue: (any MediaPlayerQueue)?
  var previewImageProvider: PreviewImageProvider?
}

/// 假轨道表。选中项由菜单直接写入这里，代替 MPVPlayer 的轨道状态。
struct UIPlayerPreviewTracks {
  var audio: [MediaStream] = []
  var subtitles: [MediaStream] = []
  var selectedAudioIndex: Int?
  var selectedSubtitleIndex: Int?
  var subtitlesEnabled = false
  /// 关闭字幕后记住的轨道。
  var disabledSubtitleIndex: Int?

  var defaultSubtitleIndex: Int? {
    subtitles.first?.index
  }
}

/// 预览场景的建造参数。场景里按不同状态覆盖少量字段。
struct UIPlayerPreviewConfiguration {
  var state: MediaSession.State = .playback
  var isReady = true
  var isPaused = false
  var isBuffering = false
  var activity: MediaSession.Activity?
  var position: Duration = .seconds(968)
  var duration: Duration? = .seconds(2_732)
  var canControlPlayback = true
  var canSeek = true

  var subtitlesEnabled = true
  var selectedAudioIndex: Int? = 0
  var selectedSubtitleIndex: Int? = 0
  var includeQueue = true
  var includeChapters = true
  var includeVersions = true

  var subtitleOffset: Duration = .zero
  var audioOffset: Duration = .zero
  var rate: Double = 1

  /// 顶部 toast；预览会循环重放，避免默认 2 秒后消失而截不到。
  var toast: String?
  /// 界面出现后自动收起控件。
  var hideControls = false
  /// 界面出现后进入拖动状态。
  var startScrubbing = false
  /// 拖动状态的目标位置；nil 表示停在当前位置。
  var scrubTarget: Duration?
  /// 界面出现后自动打开的面板。
  var supplement: UIPlayerPreviewSession.Supplement?
  /// 界面出现后自动打开的调整面板。
  var guest: UIPlayerPreviewSession.Guest?
  /// 让工具栏上的某个按钮取得焦点（如 subtitles / audio / playbackSettings）。
  var focusAction: String?

  static var playing: Self { .init() }

  static var loading: Self {
    var value = Self()
    value.state = .preparing
    value.isReady = false
    value.canControlPlayback = false
    value.canSeek = false
    value.activity = .loading
    value.position = .zero
    return value
  }

  static func failed(message: String) -> Self {
    var value = Self()
    value.state = .error
    value.isReady = false
    value.canControlPlayback = false
    value.canSeek = false
    value.toast = message
    return value
  }

  static var paused: Self {
    var value = Self()
    value.isPaused = true
    return value
  }

  static var scrubbing: Self {
    var value = Self()
    value.startScrubbing = true
    value.scrubTarget = .seconds(1_168)
    return value
  }

  static var subtitlesOff: Self {
    var value = Self()
    value.subtitlesEnabled = false
    return value
  }

  static var ended: Self {
    var value = Self()
    value.state = .stopped
    value.isPaused = true
    value.canControlPlayback = false
    value.canSeek = false
    value.position = .seconds(2_732)
    return value
  }
}

@MainActor
enum UIPlayerPreviewFixtures {
  static let itemID = "ui-preview-episode-7"
  static let seriesName = "星际拓荒"
  static let episodeName = "静默的轨道"
  static let sourceFourKID = "ui-preview-source-4k"
  static let sourceHDID = "ui-preview-source-1080p"

  static func sources() -> [ServerMediaSource] {
    [
      ServerMediaSource(id: sourceFourKID, name: "4K HDR · HEVC", container: "mkv"),
      ServerMediaSource(id: sourceHDID, name: "1080p · H.264", container: "mp4"),
    ]
  }

  static func item() -> ServerMediaItem {
    ServerMediaItem(
      id: itemID,
      kind: .episode,
      name: episodeName,
      seriesName: seriesName,
      seasonNumber: 1,
      episodeNumber: 7,
      runtimeSeconds: 2_732,
      externalIDs: ["tmdb": "624107"]
    )
  }

  static func chapters(includeImages: Bool = false) -> [ChapterInfo] {
    let points: [(String, Int)] = [
      ("开场：深空信号", 0),
      ("第一幕：失联的补给船", 6 * 60),
      ("第二幕：轨道上的回声", 15 * 60),
      ("第三幕：静默的抉择", 27 * 60),
      ("片尾", 38 * 60),
    ]
    return points.enumerated().map { index, point in
      ChapterInfo(
        name: point.0,
        startPositionTicks: point.1 * 10_000_000,
        imageTag: nil,
        imageURL: includeImages ? URL(string: "ui-preview://chapter/\(index)") : nil
      )
    }
  }

  static func mediaSources(includeVersions: Bool) -> [PlaybackMediaSourceInfo] {
    let playable = includeVersions ? sources() : Array(sources().prefix(1))
    return playable.map { PlaybackMediaSourceInfo(source: $0) }
  }

  static func baseItem(
    includeChapters: Bool = true,
    includeVersions: Bool = true,
    chapterImages: Bool = false
  ) -> BaseItemDto {
    var item = BaseItemDto(id: itemID)
    item.name = episodeName
    item.type = .episode
    item.overview = """
      补给船在木星轨道附近失联七十二小时后，顾维在一次例行扫描里重新听到了它的信标。\
      信号里没有求救，只有一段重复的、像是从更远处传来的呼吸声。船员们必须决定，\
      是循着信号继续深入，还是按规程返航。
      """
    item.runTimeTicks = 2_732 * 10_000_000
    item.officialRating = "TV-14"
    item.communityRating = 8.6
    item.genres = ["科幻", "悬疑", "剧情"]
    item.indexNumber = 7
    item.parentIndexNumber = 1
    item.seriesName = seriesName
    item.seriesID = "ui-preview-series-1"
    item.seasonID = "ui-preview-season-1"
    item.seasonName = "第一季"
    item.premiereDate = Date(timeIntervalSince1970: 1_752_000_000)
    item.mediaSources = mediaSources(includeVersions: includeVersions)
    item.chapters = includeChapters ? chapters(includeImages: chapterImages) : nil
    item.people = [
      BaseItemPerson(id: "person-1", name: "林澈", role: "顾维", type: .actor),
      BaseItemPerson(id: "person-2", name: "周遥", role: "林岸", type: .actor),
      BaseItemPerson(id: "person-3", name: "沈弦", role: "声呐员", type: .actor),
      BaseItemPerson(id: "person-4", name: "许望", role: "导演", type: .director),
      BaseItemPerson(id: "person-5", name: "程未", role: "编剧", type: .writer),
    ]
    return item
  }

  static func tracks(
    subtitlesEnabled: Bool,
    selectedSubtitleIndex: Int?,
    selectedAudioIndex: Int?
  ) -> UIPlayerPreviewTracks {
    UIPlayerPreviewTracks(
      audio: [
        MediaStream(index: 0, type: .audio, displayTitle: "国语 · DTS-HD MA 5.1", codec: "dts", channels: 6),
        MediaStream(index: 1, type: .audio, displayTitle: "英语 · E-AC-3 5.1", codec: "eac3", channels: 6),
        MediaStream(index: 2, type: .audio, displayTitle: "国语 · AAC 2.0（评论音轨）", codec: "aac", channels: 2),
      ],
      subtitles: [
        MediaStream(index: 0, type: .subtitle, displayTitle: "简体中文 · ASS（内嵌）", codec: "ass"),
        MediaStream(index: 1, type: .subtitle, displayTitle: "繁体中文 · SRT（内嵌）", codec: "subrip"),
        MediaStream(index: 2, type: .subtitle, displayTitle: "English · PGS（内嵌）", codec: "hdmv_pgs_subtitle"),
        MediaStream(index: 3, type: .subtitle, displayTitle: "简体中文 · SRT（外挂）", codec: "subrip"),
      ],
      selectedAudioIndex: selectedAudioIndex,
      selectedSubtitleIndex: selectedSubtitleIndex,
      subtitlesEnabled: subtitlesEnabled,
      disabledSubtitleIndex: selectedSubtitleIndex
    )
  }

  static func queue() -> UIPlayerPreviewQueue {
    let names = [
      (6, "第六集 · 低温休眠"),
      (7, "第七集 · 静默的轨道"),
      (8, "第八集 · 回声之外"),
      (9, "第九集 · 返航窗口"),
      (10, "第十集 · 第一束光"),
    ]
    let entries = names.map { number, name -> ItemEntry in
      var item = BaseItemDto(id: "ui-preview-episode-\(number)")
      item.name = name
      item.type = .episode
      item.indexNumber = number
      item.parentIndexNumber = 1
      item.seriesName = seriesName
      item.runTimeTicks = 2_640 * 10_000_000
      return ItemEntry(item: item)
    }
    return UIPlayerPreviewQueue(
      items: entries,
      currentEntryID: entries.first(where: { $0.itemID == itemID })?.id ?? entries[1].id
    )
  }

  static func previewImageProvider() -> PreviewImageProvider? {
    let item = baseItem(includeChapters: true, includeVersions: true, chapterImages: true)
    return PreviewImageProvider(
      option: .chapters,
      item: item,
      mediaSourceID: sourceFourKID,
      chapters: item.fullChapterInfo,
      client: JellyfinClient(
        connection: UIPlayerPreviewConnection(
          item: UIPlayerPreviewFixtures.item(),
          sources: UIPlayerPreviewFixtures.sources()
        )
      ),
      resolveImage: { index in
        await MainActor.run { UIPlayerPreviewFixtures.thumbnail(chapter: index) }
      }
    )
  }

  /// 拖动预览用的本地图片，不下载任何远程地址。
  static func thumbnail(chapter: Int) -> UIImage {
    let size = CGSize(width: 960, height: 540)
    return UIGraphicsImageRenderer(size: size).image { context in
      let colors = [
        UIColor(red: 0.05, green: 0.10, blue: 0.18, alpha: 1).cgColor,
        UIColor(red: 0.20, green: 0.33, blue: 0.52, alpha: 1).cgColor,
      ] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
      ) {
        context.cgContext.drawLinearGradient(
          gradient,
          start: .zero,
          end: CGPoint(x: size.width, y: size.height),
          options: []
        )
      }

      let title = "预览缩略图 · 第 \(chapter + 1) 章节"
      (title as NSString).draw(
        at: CGPoint(x: 48, y: 210),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
          .foregroundColor: UIColor.white,
        ]
      )

      ("UI Preview · 假数据" as NSString).draw(
        at: CGPoint(x: 48, y: 280),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 28, weight: .regular),
          .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
      )
    }
  }

  static func makeSession(configuration: UIPlayerPreviewConfiguration) -> MediaSession {
    let item = self.item()
    let (stream, prepared) = preparedPlayback(item: item, sources: sources(), includeVersions: configuration.includeVersions)
    let playbackSession = PlaybackSession(
      prepared: prepared,
      startPosition: 0,
      reporter: PlaybackReporter()
    )
    let session = MediaSession(
      session: playbackSession,
      onExit: { _ in },
      onSwitchItem: { _, _, _, _, completion in completion(.discarded) }
    )

    let tracks = tracks(
      subtitlesEnabled: configuration.subtitlesEnabled,
      selectedSubtitleIndex: configuration.selectedSubtitleIndex,
      selectedAudioIndex: configuration.selectedAudioIndex
    )
    let previewQueue: (any MediaPlayerQueue)? = configuration.includeQueue ? queue() : nil
    session.previewSession = UIPlayerPreviewSession(
      state: configuration.state,
      isReady: configuration.isReady,
      canControlPlayback: configuration.canControlPlayback,
      canSeek: configuration.canSeek,
      isBuffering: configuration.isBuffering,
      isPaused: configuration.isPaused,
      position: configuration.position,
      duration: configuration.duration,
      activity: configuration.activity,
      videoSize: .init(width: 3_840, height: 2_160),
      baseItem: baseItem(
        includeChapters: configuration.includeChapters,
        includeVersions: configuration.includeVersions
      ),
      tracks: tracks,
      queue: previewQueue,
      previewImageProvider: previewImageProvider()
    )

    session.start()
    if let playbackItem = session.playbackItem {
      playbackItem.subtitleOffset = configuration.subtitleOffset
      playbackItem.audioOffset = configuration.audioOffset
    }
    session.rate = configuration.rate
    if let streamItem = session.playbackItem {
      streamItem.configuration.selectMediaSource(id: stream.source.id)
    }
    return session
  }

  // MARK: 假连接与流

  private static func preparedPlayback(
    item: ServerMediaItem,
    sources: [ServerMediaSource],
    includeVersions: Bool
  ) -> (PreparedStream, PreparedPlayback) {
    let playable = includeVersions ? sources : Array(sources.prefix(1))
    let stream = PreparedStream(
      item: item,
      source: playable[0],
      sources: playable,
      playSessionID: "ui-preview-session",
      streamURL: URL(string: "http://moviepilot-ui-preview.local:3000/ui-preview/stream.mkv")!
    )
    let connection = UIPlayerPreviewConnection(item: item, sources: playable)
    let prepared = PreparedPlayback(connection: connection, stream: stream, episode: nil)
    return (stream, prepared)
  }
}

/// 预览专用队列：只提供界面需要的条目和当前项，不向服务器取数据。
@MainActor
@Observable
final class UIPlayerPreviewQueue: MediaPlayerQueue {
  nonisolated deinit {}

  var state: MediaPlayerQueueState = .content
  var items: [ItemEntry] = []
  var currentEntryID: ItemEntry.ID?

  init(items: [ItemEntry], currentEntryID: ItemEntry.ID?) {
    self.items = items
    self.currentEntryID = currentEntryID
  }

  var currentIndex: Int? {
    guard let currentEntryID else { return nil }
    return items.firstIndex { $0.id == currentEntryID }
  }

  var nextItem: PlaybackIntent? {
    guard let index = currentIndex, items.indices.contains(index + 1) else { return nil }
    return PlaybackIntent(item: items[index + 1].snapshot)
  }

  var previousItem: PlaybackIntent? {
    guard let index = currentIndex, items.indices.contains(index - 1) else { return nil }
    return PlaybackIntent(item: items[index - 1].snapshot)
  }

  func refresh() {}

  func select(_ entry: ItemEntry) {
    currentEntryID = entry.id
  }

  func observe(_ mediaSession: MediaSession) -> AnyCancellable {
    AnyCancellable {}
  }
}

/// 预览专用连接。所有方法都是内存操作；不会建立网络请求。
struct UIPlayerPreviewConnection: MediaServerConnection {
  let item: ServerMediaItem
  let sources: [ServerMediaSource]

  var serverName: String { "Emby 预览" }
  var config: MediaServerConnectionConfig {
    MediaServerConnectionConfig(host: "moviepilot-ui-preview.local", playHost: nil, apiKey: nil, username: "预览用户")
  }
  var preferredUserName: String? { "预览用户" }
  var reportingServer: URL { URL(string: "http://moviepilot-ui-preview.local:3000")! }
  var userID: String { "ui-preview-server-user" }

  func item(id: String, timeout: TimeInterval?) async throws -> ServerMediaItem? {
    id == item.id ? item : nil
  }

  func items(matching expected: LibraryItemExpectation) async throws -> [ServerMediaItem] {
    []
  }

  func episodes(seriesID: String) async throws -> [ServerMediaItem] {
    []
  }

  func prepareStream(for item: ServerMediaItem, preferredSourceID: String?) async throws -> PreparedStream {
    let source = sources.first { $0.id == preferredSourceID } ?? sources[0]
    return PreparedStream(
      item: item,
      source: source,
      sources: sources,
      playSessionID: "ui-preview-session",
      streamURL: URL(string: "http://moviepilot-ui-preview.local:3000/ui-preview/stream.mkv")!
    )
  }

  func report(
    _ event: PlaybackReportEvent,
    for stream: PreparedStream,
    positionSeconds: Double,
    isPaused: Bool
  ) async throws {}

  func saveWatchProgress(_ progress: WatchProgress) async throws {}

  func trickplayTileURL(itemID: String, width: Int, index: Int, mediaSourceID: String) -> URL? {
    nil
  }
}
#endif
