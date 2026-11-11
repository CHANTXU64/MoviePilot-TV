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

/// 播放器预览的条目类型。剧集用默认 fixture；电影用于核对无队列的播放界面；
/// `longTitleEpisode` 用于核对工具栏超长剧名的截断。
enum UIPlayerPreviewContent: Equatable {
  case episode
  case movie
  case longTitleEpisode

  var isEpisode: Bool { self != .movie }
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
  /// 条目类型：剧集、电影或超长标题剧集。
  var content: UIPlayerPreviewContent = .episode
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
  var includeAudioTracks = true
  var includeSubtitleTracks = true

  var subtitleOffset: Duration = .zero
  var audioOffset: Duration = .zero
  var rate: Double = 1

  /// 顶部 toast；预览会循环重放，避免默认 2 秒后消失而截不到。
  var toast: String?
  /// 写入 `MediaSession.commandError`，走真实 `VideoPlayer` 的 toast 观察链路。
  /// 预览会循环重放，避免默认 2 秒后消失而截不到。
  var commandError: String?
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

  /// 换集/换版本解析新条目时：沿用旧条目画面，控件不可用。
  static var loadingItem: Self {
    var value = Self()
    value.state = .loadingItem
    value.isReady = false
    value.canControlPlayback = false
    value.canSeek = false
    value.activity = .loading
    return value
  }

  /// mpv 缓冲中：时间旁显示缓冲指示器。
  static var buffering: Self {
    var value = Self()
    value.isBuffering = true
    value.activity = .buffering
    return value
  }

  /// mpv 正在跳转。
  static var seeking: Self {
    var value = Self()
    value.activity = .seeking
    return value
  }

  /// 会话存在但不能控制播放，也不在加载或错误状态。
  static var disabledControls: Self {
    var value = Self()
    value.canControlPlayback = false
    value.canSeek = false
    return value
  }

  /// 没有音轨和字幕轨：工具栏不应出现音频、字幕及其偏移入口。
  static var noTracks: Self {
    var value = Self()
    value.subtitlesEnabled = false
    value.selectedAudioIndex = nil
    value.selectedSubtitleIndex = nil
    value.includeAudioTracks = false
    value.includeSubtitleTracks = false
    return value
  }

  /// 只有一个可直连版本：播放设置不可用。
  static var singleVersion: Self {
    var value = Self()
    value.includeVersions = false
    return value
  }

  /// 剧集条目但没有队列上下文（整部剧直接起播）。
  static var noQueue: Self {
    var value = Self()
    value.includeQueue = false
    return value
  }

  static var noChapters: Self {
    var value = Self()
    value.includeChapters = false
    return value
  }

  /// 电影条目：无季集编号、无队列。
  static var movie: Self {
    var value = Self()
    value.content = .movie
    value.includeQueue = false
    value.position = .seconds(2_215)
    value.duration = .seconds(7_080)
    return value
  }
}

/// 播放界面内提示使用的文案。
/// 能直接取生产类型或常量的都取；只有生产代码内联的固定文案在这里复制，避免预览文案随意改写。
enum UIPlayerPreviewMessages {
  /// 与 `PlaybackSession` 把 mpv 致命错误交给 `onFailure` 时的文案一致。
  static let mpvFailure = "无法播放该影片，请检查与媒体服务器的网络连接"
  /// 跳转失败时写入 `MediaSession.commandError` 的文案。
  static let seekFailure = L10n.unableToSeek
  /// 换集/换版本失败时取 `PlaybackError.errorDescription`。
  static let switchItemFailure = PlaybackError.notFound.errorDescription ?? ""
  /// 播放结束说明下一集在另一台服务器上；格式取自 `EpisodeNavigator.adjacent` 的 stop 文案。
  static let nextEpisodeOnAnotherServer =
    "\(EpisodeNavigator.Direction.next.noun)在另一台媒体服务器“卧室 Emby”上，请回到详情页选择"
}

@MainActor
enum UIPlayerPreviewFixtures {
  static let itemID = "ui-preview-episode-7"
  static let seriesName = "星际拓荒"
  static let episodeName = "静默的轨道"
  static let movieID = "ui-preview-movie-1"
  static let movieName = "深空静默：第七信号"
  /// 超长剧名与集名：工具栏只显示剧名，副标题是季集号。
  static let longSeriesName =
    "星际拓荒：静默轨道之外的回声档案、失联补给船与木星背面那一段反复出现的呼吸声调查记录"
  static let longEpisodeName =
    "第七集 · 穿越木星轨道背面的漫长静默与那一段反复出现的呼吸声"
  static let sourceFourKID = "ui-preview-source-4k"
  static let sourceHDID = "ui-preview-source-1080p"

  static func sources() -> [ServerMediaSource] {
    [
      ServerMediaSource(id: sourceFourKID, name: "4K HDR · HEVC", container: "mkv"),
      ServerMediaSource(id: sourceHDID, name: "1080p · H.264", container: "mp4"),
    ]
  }

  static func item(_ content: UIPlayerPreviewContent = .episode) -> ServerMediaItem {
    switch content {
    case .episode:
      return ServerMediaItem(
        id: itemID,
        kind: .episode,
        name: episodeName,
        seriesName: seriesName,
        seasonNumber: 1,
        episodeNumber: 7,
        runtimeSeconds: 2_732,
        externalIDs: ["tmdb": "624107"]
      )
    case .movie:
      return ServerMediaItem(
        id: movieID,
        kind: .movie,
        name: movieName,
        runtimeSeconds: 7_080,
        externalIDs: ["tmdb": "1000001"]
      )
    case .longTitleEpisode:
      return ServerMediaItem(
        id: itemID,
        kind: .episode,
        name: longEpisodeName,
        seriesName: longSeriesName,
        seasonNumber: 1,
        episodeNumber: 7,
        runtimeSeconds: 2_732,
        externalIDs: ["tmdb": "624107"]
      )
    }
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
    content: UIPlayerPreviewContent = .episode,
    includeChapters: Bool = true,
    includeVersions: Bool = true,
    chapterImages: Bool = false
  ) -> BaseItemDto {
    var item = BaseItemDto(id: content.isEpisode ? itemID : movieID)
    item.overview = """
      补给船在木星轨道附近失联七十二小时后，顾维在一次例行扫描里重新听到了它的信标。\
      信号里没有求救，只有一段重复的、像是从更远处传来的呼吸声。船员们必须决定，\
      是循着信号继续深入，还是按规程返航。
      """
    item.runTimeTicks = (content.isEpisode ? 2_732 : 7_080) * 10_000_000
    item.officialRating = content.isEpisode ? "TV-14" : "PG-13"
    item.communityRating = content.isEpisode ? 8.6 : 8.2
    item.genres = content.isEpisode ? ["科幻", "悬疑", "剧情"] : ["科幻", "冒险", "悬疑"]
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

    switch content {
    case .episode:
      item.name = episodeName
      item.type = .episode
      item.indexNumber = 7
      item.parentIndexNumber = 1
      item.seriesName = seriesName
      item.seriesID = "ui-preview-series-1"
      item.seasonID = "ui-preview-season-1"
      item.seasonName = "第一季"
    case .longTitleEpisode:
      item.name = longEpisodeName
      item.type = .episode
      item.indexNumber = 7
      item.parentIndexNumber = 1
      item.seriesName = longSeriesName
      item.seriesID = "ui-preview-series-1"
      item.seasonID = "ui-preview-season-1"
      item.seasonName = "第一季"
    case .movie:
      item.name = movieName
      item.type = .movie
    }
    return item
  }

  static func tracks(
    subtitlesEnabled: Bool,
    selectedSubtitleIndex: Int?,
    selectedAudioIndex: Int?,
    includeAudio: Bool = true,
    includeSubtitles: Bool = true
  ) -> UIPlayerPreviewTracks {
    let audioTracks: [MediaStream] = includeAudio
      ? [
        MediaStream(index: 0, type: .audio, displayTitle: "国语 · DTS-HD MA 5.1", codec: "dts", channels: 6),
        MediaStream(index: 1, type: .audio, displayTitle: "英语 · E-AC-3 5.1", codec: "eac3", channels: 6),
        MediaStream(index: 2, type: .audio, displayTitle: "国语 · AAC 2.0（评论音轨）", codec: "aac", channels: 2),
      ] : []
    let subtitleTracks: [MediaStream] = includeSubtitles
      ? [
        MediaStream(index: 0, type: .subtitle, displayTitle: "简体中文 · ASS（内嵌）", codec: "ass"),
        MediaStream(index: 1, type: .subtitle, displayTitle: "繁体中文 · SRT（内嵌）", codec: "subrip"),
        MediaStream(index: 2, type: .subtitle, displayTitle: "English · PGS（内嵌）", codec: "hdmv_pgs_subtitle"),
        MediaStream(index: 3, type: .subtitle, displayTitle: "简体中文 · SRT（外挂）", codec: "subrip"),
      ] : []
    return UIPlayerPreviewTracks(
      audio: audioTracks,
      subtitles: subtitleTracks,
      selectedAudioIndex: includeAudio ? selectedAudioIndex : nil,
      selectedSubtitleIndex: includeSubtitles ? selectedSubtitleIndex : nil,
      subtitlesEnabled: includeSubtitles && subtitlesEnabled,
      disabledSubtitleIndex: includeSubtitles ? selectedSubtitleIndex : nil
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

  static func previewImageProvider(content: UIPlayerPreviewContent = .episode) -> PreviewImageProvider? {
    let item = baseItem(
      content: content,
      includeChapters: true,
      includeVersions: true,
      chapterImages: true
    )
    return PreviewImageProvider(
      option: .chapters,
      item: item,
      mediaSourceID: sourceFourKID,
      chapters: item.fullChapterInfo,
      client: JellyfinClient(
        connection: UIPlayerPreviewConnection(
          item: UIPlayerPreviewFixtures.item(content),
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
    let item = self.item(configuration.content)
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
      selectedAudioIndex: configuration.selectedAudioIndex,
      includeAudio: configuration.includeAudioTracks,
      includeSubtitles: configuration.includeSubtitleTracks
    )
    let previewQueue: (any MediaPlayerQueue)? =
      configuration.includeQueue && configuration.content.isEpisode ? queue() : nil
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
        content: configuration.content,
        includeChapters: configuration.includeChapters,
        includeVersions: configuration.includeVersions
      ),
      tracks: tracks,
      queue: previewQueue,
      previewImageProvider: previewImageProvider(content: configuration.content)
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
