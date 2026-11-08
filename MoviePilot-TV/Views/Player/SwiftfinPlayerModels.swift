import Foundation
import Observation
import SwiftUI

// 移植自 Swiftfin 的播放界面读取的是 Jellyfin SDK 的数据类型（BaseItemDto、ChapterInfo、BaseItemPerson、MediaStream…）。
// 这里按同名提供只含界面用到成员的适配类型，移植文件不用改类型名；数据来自与服务器无关的 `ServerMediaItem`、`ServerMediaSource`。
// 目前只填播放本身已有的数据（标题、季集号、片长、mpv 的音轨字幕、可选的版本）。简介、章节、演职员、海报、片源详情、
// 片头片尾等元数据暂不接入，保持为空，界面大多按 Swiftfin 原逻辑自然隐藏。
// 从详情页按集播放时，标题、季集号用 MoviePilot 集列表的，上一集/下一集和同季列表也按它走（见 `UserSession`）；
// 其他入口（首页“最近添加”、整剧从第一集播）没有集列表，队列为空。

// MARK: - 条目

nonisolated enum BaseItemKind: String {
  case audio, audioBook, book, boxSet, episode, liveTvProgram, movie, musicAlbum, musicVideo
  case photo, photoAlbum, playlist, program, recording, season, series, trailer, tvProgram, video
  case person, other

  init(_ kind: ServerMediaItem.Kind) {
    switch kind {
    case .movie: self = .movie
    case .episode: self = .episode
    case .series: self = .series
    case .other: self = .other
    }
  }

  var preferredPosterDisplayType: PosterDisplayType {
    switch self {
    case .episode, .musicVideo, .video, .program, .tvProgram, .liveTvProgram, .recording: .landscape
    case .audio, .musicAlbum, .photo, .photoAlbum, .playlist: .square
    default: .portrait
    }
  }
}

nonisolated enum MediaType {
  case video
  case audio
}

/// 直播节目信息。直连播放没有直播，恒为 nil。
nonisolated struct ProgramInfo {
  let id: String?
  let displayTitle: String
  let overview: String?
}

/// Jellyfin trickplay 图集参数。目前恒为空（接入点见 `JellyfinClient.trickplayTileURL`）。
nonisolated struct TrickplayInfo {
  let width: Int?
  let height: Int?
  let tileWidth: Int?
  let tileHeight: Int?
  let interval: Int?
}

/// 与 Jellyfin `BaseItemDto` 同名的条目适配。
nonisolated struct BaseItemDto: Identifiable {
  var id: String?
  var name: String?
  var type: BaseItemKind?
  var overview: String?
  var premiereDate: Date?
  var runTimeTicks: Int?
  var officialRating: String?
  var communityRating: Double?
  var genres: [String]?
  var indexNumber: Int?
  var parentIndexNumber: Int?
  var seriesName: String?
  var seriesID: String?
  var seasonID: String?
  var seasonName: String?
  /// MoviePilot-TV 只直连原文件，不按分辨率/码率转码：不报告 `.video`，播放设置里的分辨率项按原逻辑隐藏。
  var mediaType: MediaType?
  var mediaSources: [PlaybackMediaSourceInfo]?
  var people: [BaseItemPerson]?
  var chapters: [ChapterInfo]?
  /// 竖版海报、横版缩略图地址（不带密钥）。
  var portraitImageURL: URL?
  var landscapeImageURL: URL?
  /// 从详情页按集播放时，MoviePilot 集列表里的这一集；换集时随条目交给协调器。
  var moviePilotEpisode: MoviePilotEpisode?

  // 直播、节目、附加内容相关，直连播放不出现。
  var currentProgram: ProgramInfo? { nil }
  var trickplay: [String: [String: TrickplayInfo]]? { nil }
  var startDate: Date? { nil }
  var endDate: Date? { nil }
  var channelName: String? { nil }
  var extraType: String? { nil }
  var isLiveStream: Bool { false }
  var canBeRecorded: Bool { false }

  init(id: String?) {
    self.id = id
  }

  /// 只取播放本身已有的基本字段；其余元数据（简介、海报、演职员、章节、片源详情）暂不接入，保持为空。
  /// 按集播放时，集名和季集号用 MoviePilot 集列表的（与详情页一致），并带上队列用的剧集、季标识；
  /// 其他条目不带这两个标识，播放界面的队列为空。
  init(item: ServerMediaItem, episode: QueuedEpisode? = nil) {
    id = item.id
    type = BaseItemKind(item.kind)
    runTimeTicks = item.runtimeSeconds.map { Int($0 * 10_000_000) }
    if let episode {
      name = episode.episode.name
      indexNumber = episode.episode.episodeNumber
      parentIndexNumber = episode.episode.seasonNumber
      seriesName = episode.context.seriesName ?? item.seriesName
      moviePilotEpisode = episode.episode
      seriesID = String(episode.context.tmdbID)
      seasonID = UserSession.queueSeasonID(episode.episode.seasonNumber)
    } else {
      name = item.name
      indexNumber = item.episodeNumber
      parentIndexNumber = item.seasonNumber
      seriesName = item.seriesName
    }
  }

  // MARK: 与 Swiftfin 的 BaseItemDto 扩展相同的派生值

  var displayTitle: String {
    name ?? .emptyDash
  }

  var runtime: Duration? {
    guard let ticks = runTimeTicks, ticks > 0 else { return nil }
    return Duration.ticks(ticks)
  }

  var seasonEpisodeLabel: String? {
    guard let seasonNo = parentIndexNumber, let episodeNo = indexNumber else { return nil }
    return L10n.seasonAndEpisode(String(seasonNo), String(episodeNo))
  }

  var episodeLocator: String? {
    guard let episodeNo = indexNumber else { return nil }
    return L10n.episodeNumber(episodeNo)
  }

  var parentTitle: String? {
    switch type {
    case .episode, .season: seriesName
    default: nil
    }
  }

  var runTimeLabel: String? {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.hour, .minute]
    guard let runTimeTicks, let text = formatter.string(from: Double(runTimeTicks / 10_000_000)) else {
      return nil
    }
    return text
  }

  var premiereDateLabel: String? {
    guard let premiereDate else { return nil }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: premiereDate)
  }

  var premiereDateYear: String? {
    guard let premiereDate else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "YYYY"
    return formatter.string(from: premiereDate)
  }

  /// 合并同一人的多个幕后职务，与 Swiftfin 相同。
  var mergedPeople: [BaseItemPerson]? {
    guard let people else { return nil }
    let crew = Dictionary(grouping: people.filter(\.isCrew), by: \.id)
    var seen: Set<String> = []
    return people.compactMap { person in
      guard person.isCrew, let id = person.id, let credits = crew[id], credits.count > 1 else {
        return person
      }
      guard seen.insert(id).inserted else { return nil }
      var roles: [String] = []
      for role in credits.compactMap(\.role) where !role.isEmpty && !roles.contains(role) {
        roles.append(role)
      }
      var merged = person
      merged.role = roles.isEmpty ? nil : roles.joined(separator: " / ")
      return merged
    }
  }

  func posterSubtitle(using field: Any? = nil) -> String? { nil }
}

nonisolated extension BaseItemDto: Hashable {
  static func == (lhs: BaseItemDto, rhs: BaseItemDto) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension BaseItemDto: Poster {

  typealias Environment = Empty

  var preferredPosterDisplayType: PosterDisplayType {
    type?.preferredPosterDisplayType ?? .portrait
  }

  var subtitle: String? {
    switch type {
    case .episode: seasonEpisodeLabel
    default: nil
    }
  }

  /// 海报没图时的占位，和 App 其他页面的媒体类型图标一致；播放器用不到的类型（音乐等）显示通用缺图占位。
  var systemImage: String {
    switch type {
    case .movie, .video: AppSymbol.movie
    case .series, .season, .episode, .program: AppSymbol.tv
    case .boxSet: AppSymbol.collection
    case .person: AppSymbol.person
    default: AppSymbol.imagePlaceholder
    }
  }

  var posterLabel: some View {
    BaseItemDtoPosterLabel(item: self)
  }

  func posterOverlay(for displayType: PosterDisplayType) -> some View {
    PosterSelectionOverlay()
  }

  func imageSources(for displayType: PosterDisplayType, environment: Empty) -> [ImageSource] {
    let url = displayType == .landscape ? landscapeImageURL ?? portraitImageURL : portraitImageURL ?? landscapeImageURL
    return url.map { [ImageSource(url: $0)] } ?? []
  }
}

// MARK: - 演职员

nonisolated enum PersonKind: String, CaseIterable {
  case unknown, actor, director, composer, writer, guestStar, producer

  /// 与 Swiftfin `PersonKind.supportedCases` 相同。
  static var supportedCases: [PersonKind] { [.actor, .director, .writer, .producer] }

  var isSupported: Bool { Self.supportedCases.contains(self) }
}

/// 与 Jellyfin `BaseItemPerson` 同名的演职员适配。
nonisolated struct BaseItemPerson: Hashable, Identifiable {
  var id: String?
  var name: String?
  var role: String?
  var type: PersonKind?
  var imageURL: URL?

  var displayTitle: String {
    name ?? .emptyDash
  }

  var isCrew: Bool {
    type == .director || type == .writer || type == .producer
  }

  /// 幕后职务原样显示；演员有多个角色名时只取第一个（与 Swiftfin 相同）。
  var displayRole: String? {
    guard let role else { return nil }
    guard !isCrew else { return role }
    let split = role.split(separator: "/")
    guard split.count > 1, let firstRole = split.first?.trimmingCharacters(in: .whitespaces),
      let lastRole = split.last?.trimmingCharacters(in: .whitespaces)
    else { return role }
    var final = firstRole
    if let open = lastRole.lastIndex(of: "("), let close = lastRole.lastIndex(of: ")"), open < close {
      final.append(" \(lastRole[open...close])")
    }
    return final
  }
}

extension BaseItemPerson: Poster {

  typealias Environment = Empty

  var preferredPosterDisplayType: PosterDisplayType { .portrait }

  var subtitle: String? { displayRole }

  var systemImage: String { AppSymbol.person }

  var posterLabel: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(displayTitle)
        .font(.footnote)
        .lineLimit(1)
      Text(displayRole ?? .space)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  func imageSources(for displayType: PosterDisplayType, environment: Empty) -> [ImageSource] {
    imageURL.map { [ImageSource(url: $0)] } ?? []
  }
}

// MARK: - 章节

/// 与 Jellyfin `ChapterInfo` 同名的章节适配。
nonisolated struct ChapterInfo: Hashable {
  var name: String?
  var startPositionTicks: Int?
  var imageTag: String?
  var imageURL: URL?
}

extension BaseItemDto {

  /// 与 Swiftfin `fullChapterInfo(using:)` 相同：去掉没有起点的章节、按起点排序，附上章节图。
  var fullChapterInfo: [ChapterInfo.FullInfo] {
    (chapters ?? [])
      .filter { $0.startPositionTicks != nil }
      .sorted { ($0.startPositionTicks ?? 0) < ($1.startPositionTicks ?? 0) }
      .map { ChapterInfo.FullInfo(chapterInfo: $0, imageSource: $0.imageURL.map { ImageSource(url: $0) }) }
  }
}

// MARK: - 片源与流

nonisolated enum MediaProtocol: String {
  case file = "File"
  case http = "Http"
  case other = "Other"
}

nonisolated enum MediaStreamProtocol: String {
  case hls
}

nonisolated struct VideoRangeType: RawRepresentable, Hashable {
  let rawValue: String
}

nonisolated enum MediaStreamType {
  case video, audio, subtitle, other
}

/// 与 Jellyfin `MediaStream` 同名的轨道适配。`index` 是 mpv 的轨道编号（播放器用它切换）；
/// 编码取 mpv 报告的值，码率、声道、分辨率等详情暂不接入。
nonisolated struct MediaStream: Hashable {
  var index: Int?
  var type: MediaStreamType = .other
  var displayTitle: String?
  var codec: String?
  var profile: String?
  var bitRate: Int?
  var channels: Int?
  var sampleRate: Int?
  var width: Int?
  var height: Int?
  var videoRangeType: VideoRangeType?
}

/// 对应 Jellyfin `MediaSourceInfo` 的片源适配（工程里已有同名的 MoviePilot 类型，改名为 `PlaybackMediaSourceInfo`）。
nonisolated struct PlaybackMediaSourceInfo: Identifiable, Hashable {
  var id: String?
  var name: String?
  var container: String?
  var size: Int?
  var bitrate: Int?
  var `protocol`: MediaProtocol?
  /// 转码播放才有，MoviePilot-TV 只直连。
  var transcodingSubProtocol: MediaStreamProtocol? { nil }
  /// 可选的转码码率，MoviePilot-TV 只直连，为空。
  var supportedBitrates: [PlaybackBitrate] { [] }
  var mediaStreams: [MediaStream]?

  /// 记录片源 ID、版本名和容器；大小、码率和流详情暂不接入。
  init(source: ServerMediaSource) {
    id = source.id
    name = source.name
    container = source.container
  }

  var displayTitle: String {
    name ?? .emptyDash
  }
}

// MARK: - 片头/片尾

nonisolated enum MediaSegmentType: String {
  case unknown = "Unknown"
  case commercial = "Commercial"
  case preview = "Preview"
  case recap = "Recap"
  case outro = "Outro"
  case intro = "Intro"
}

/// 与 Jellyfin `MediaSegmentDto` 同名的片段适配。片头/片尾数据暂不接入（接入点：`UserSession.mediaSegments`）。
nonisolated struct MediaSegmentDto {
  var id: String?
  var itemID: String?
  var type: MediaSegmentType?
  var startTicks: Int?
  var endTicks: Int?
}

// MARK: - 队列条目与播放意图

/// 与 Swiftfin `ItemEntry` 同名：队列里的一项。
nonisolated struct ItemEntry: Identifiable, Hashable {

  struct ID: Hashable, Sendable {
    let itemID: String
    let occurrence: String?
  }

  let id: ID
  let snapshot: BaseItemDto

  init(item: BaseItemDto, occurrence: String? = nil) {
    id = ID(itemID: item.id ?? "", occurrence: occurrence)
    snapshot = item
  }

  var itemID: String { id.itemID }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ItemEntry: Poster {

  typealias Environment = Empty

  var displayTitle: String { snapshot.displayTitle }
  var systemImage: String { snapshot.systemImage }
  var subtitle: String? { snapshot.subtitle }
  var preferredPosterDisplayType: PosterDisplayType { snapshot.preferredPosterDisplayType }

  func posterAccessibility(configuration: PosterConfiguration) -> PosterAccessibility {
    snapshot.posterAccessibility(configuration: configuration)
  }

  func imageSources(for displayType: PosterDisplayType, environment: Empty) -> [ImageSource] {
    snapshot.imageSources(for: displayType, environment: environment)
  }

  var posterLabel: some View { snapshot.posterLabel }

  func posterOverlay(for displayType: PosterDisplayType) -> some View {
    snapshot.posterOverlay(for: displayType)
  }
}

/// 与 Swiftfin `MediaPlaybackConfiguration` 同名的播放配置（只含界面用到的字段）。
struct MediaPlaybackConfiguration {
  var requestedBitrate: PlaybackBitrate = .auto
  var maxResolution: PlaybackResolution = .max
  var startSeconds: Duration?
  private(set) var mediaSourceID: String?

  mutating func selectMediaSource(id: String?) {
    mediaSourceID = id
  }
}

/// 与 Swiftfin `PlaybackIntent` 同名：要播放的条目及配置。
struct PlaybackIntent {
  let entry: ItemEntry
  var queue: (any MediaPlayerQueue)?
  var configuration: MediaPlaybackConfiguration

  var item: BaseItemDto { entry.snapshot }

  init(item: BaseItemDto, configuration: MediaPlaybackConfiguration = .init(), queue: (any MediaPlayerQueue)? = nil) {
    entry = ItemEntry(item: item)
    self.queue = queue
    self.configuration = configuration
  }
}

// MARK: - 用户会话

nonisolated enum UserSessionError: Error {
  case missingCurrentSession
}

/// 一个方向上的相邻集。
enum AdjacentEpisode {
  /// `skippedMissing`：中间跳过了还不在服务器上的集，播完时要重新确认。
  case episode(BaseItemDto, skippedMissing: Bool)
  /// 不能接着播的原因：在别的服务器上、无法确认、还不在媒体服务器上。
  case unavailable(String)
  /// 这一方向没有集了。
  case none
}

/// 与 Swiftfin `UserSession` 同名：当前播放会话的服务器连接与队列数据。
/// 上一集、下一集和同季列表按 MoviePilot 集列表走，只在当前服务器上找（见 `EpisodeNavigator`）；片头片尾暂不接入。
@MainActor
@Observable
final class UserSession {
  nonisolated deinit {}

  nonisolated private static let queueSeasonPrefix = "moviepilot-season-"

  /// 队列面板按季取集用的季标识。
  nonisolated static func queueSeasonID(_ season: Int) -> String { "\(queueSeasonPrefix)\(season)" }

  nonisolated private static func season(fromQueueSeasonID id: String) -> Int? {
    guard id.hasPrefix(queueSeasonPrefix) else { return nil }
    return Int(id.dropFirst(queueSeasonPrefix.count))
  }

  /// 播放界面持有会话，这里不延长它的生命周期。
  @ObservationIgnored private weak var session: PlaybackSession?
  @ObservationIgnored let connection: any MediaServerConnection

  /// 播完自动播下一集。Swiftfin 读写服务器上的用户配置；这里存在本机，与设置页「播放」的开关是同一个。
  var isAutoPlayEnabled: Bool {
    didSet { UserDefaults.standard.set(isAutoPlayEnabled, forKey: PlaybackPreferences.autoPlayNextEpisodeKey) }
  }

  init(session: PlaybackSession) {
    self.session = session
    connection = session.connection
    isAutoPlayEnabled = PlaybackPreferences.autoPlaysNextEpisode
  }

  /// 接入点：片头/片尾片段。
  func mediaSegments(itemID: String) async throws -> [MediaSegmentDto] { [] }

  /// 同一季里能在当前服务器上播的集（队列面板）。
  func seasonEpisodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto] {
    guard let session, let queue = session.episodeQueue, let context = session.episode?.context,
      let season = Self.season(fromQueueSeasonID: seasonID)
    else { return [] }
    return try await queue.playableEpisodes(inSeason: season, from: session.playback).map {
      BaseItemDto(item: $0.item, episode: QueuedEpisode(context: context, episode: $0.episode))
    }
  }

  /// 正在播的 `itemID` 在 `direction` 方向的相邻集。会话已换成别的条目时返回 `.none`，由调用方按新条目重新取。
  /// `refresh` 时重新读服务器和集列表（播完一集要接着播时），播放期间刚入库的集也能找到。
  func adjacentEpisode(
    _ direction: EpisodeNavigator.Direction, itemID: String, refresh: Bool = false
  ) async throws -> AdjacentEpisode {
    guard let session, session.item.id == itemID, let queue = session.episodeQueue,
      let context = session.episode?.context
    else { return .none }
    switch try await queue.adjacentEpisode(direction, from: session.playback, refresh: refresh) {
    case .play(let entry, let skippedMissing):
      return .episode(
        BaseItemDto(item: entry.item, episode: QueuedEpisode(context: context, episode: entry.episode)),
        skippedMissing: skippedMissing)
    case .stop(let reason):
      return .unavailable(reason)
    case .missing:
      return direction == .next ? .unavailable(EpisodeNavigator.nextMissingMessage) : .none
    case .end:
      return .none
    }
  }
}

/// 与 Swiftfin 的 `JellyfinClient` 同名：拖动预览图用到的图集地址，由当前服务器的连接提供。
struct JellyfinClient {
  let connection: any MediaServerConnection

  func trickplayTileURL(itemID: String, width: Int, index: Int, mediaSourceID: String) -> URL? {
    connection.trickplayTileURL(itemID: itemID, width: width, index: index, mediaSourceID: mediaSourceID)
  }
}

// MARK: - 播放信息面板

nonisolated struct TranscodeReason: Hashable {
  let displayTitle: String
}

nonisolated enum HardwareAccelerationType: String {
  case none
}

/// 与 Jellyfin `TranscodingInfo` 同名。MoviePilot-TV 只直连，恒为 nil。
nonisolated struct TranscodingInfo {
  var videoCodec: String?
  var audioCodec: String?
  var isVideoDirect: Bool?
  var isAudioDirect: Bool?
  var hardwareAccelerationType: HardwareAccelerationType?
  var completionPercentage: Double?
  var transcodeReasons: [TranscodeReason]?
}

/// 与 Jellyfin `SessionInfoDto` 同名：播放信息面板读取的本设备会话信息。
nonisolated struct SessionInfoDto {
  var playMethodDisplayTitle: String?
  var transcodingInfo: TranscodingInfo?
}

/// 与 Swiftfin 同名。原版订阅 Jellyfin WebSocket 会话；MoviePilot-TV 只直连原文件，播放方式固定为“直接播放”，没有转码信息。
@MainActor
@Observable
final class PlaybackInformationProvider {
  nonisolated deinit {}

  var currentSession: SessionInfoDto?

  func observe(itemID: String) {
    currentSession = SessionInfoDto(playMethodDisplayTitle: L10n.directPlay, transcodingInfo: nil)
  }
}
