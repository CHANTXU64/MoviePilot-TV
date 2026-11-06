import Foundation
import Observation
import SwiftUI

// 移植自 Swiftfin 的播放界面读取的是 Jellyfin SDK 的数据类型（BaseItemDto、ChapterInfo、BaseItemPerson、MediaStream…）。
// 这里按同名提供只含界面用到成员的适配类型，移植文件不用改类型名。
// 目前只填播放本身已有的数据（标题、季集号、片长、mpv 的音轨字幕）。简介、章节、演职员、海报、片源详情、
// 队列、片头片尾等元数据暂不接入，保持为空，界面大多按 Swiftfin 原逻辑自然隐藏；剧集的自动播放、上一集/下一集和
// 队列页只看队列是否存在，仍会显示但没有内容。以后接数据时只需填这些字段和接入点。

// MARK: - 条目

nonisolated enum BaseItemKind: String {
  case audio, audioBook, book, boxSet, episode, liveTvProgram, movie, musicAlbum, musicVideo
  case photo, photoAlbum, playlist, program, recording, season, series, trailer, tvProgram, video
  case person, other

  init(emby type: String?) {
    switch type {
    case "Movie": self = .movie
    case "Episode": self = .episode
    case "Season": self = .season
    case "Series": self = .series
    case "Video": self = .video
    case "MusicVideo": self = .musicVideo
    case "Trailer": self = .trailer
    case "BoxSet": self = .boxSet
    case "Person": self = .person
    default: self = .other
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

/// 直播节目信息。Emby 直连播放没有直播，恒为 nil。
nonisolated struct ProgramInfo {
  let id: String?
  let displayTitle: String
  let overview: String?
}

/// Jellyfin trickplay 图集参数。Emby 没有这套接口，恒为空（接入点见 `JellyfinClient.trickplayTileURL`）。
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
  /// 竖版海报、横版缩略图地址（Emby 图片接口，不带密钥）。
  var portraitImageURL: URL?
  var landscapeImageURL: URL?

  // 直播、节目、附加内容相关，Emby 直连播放不出现。
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
  init(emby item: EmbyItem) {
    id = item.id
    name = item.name
    type = BaseItemKind(emby: item.type)
    runTimeTicks = item.runTimeTicks.map { Int($0) }
    indexNumber = item.indexNumber
    parentIndexNumber = item.parentIndexNumber
    seriesName = item.seriesName
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

  /// 只记录片源 ID；名称、容器、大小、码率和流详情暂不接入。
  init(id: String?) {
    self.id = id
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

/// 与 Swiftfin `UserSession` 同名：当前 Emby 连接与用户。
/// 队列、相邻集、片头片尾的数据暂不接入，下面三个方法是接入点，目前都返回空，相关界面按 Swiftfin 原逻辑隐藏或显示为空。
@MainActor
@Observable
final class UserSession {
  nonisolated deinit {}

  private static let autoPlayKey = "swiftfin.enableNextEpisodeAutoPlay"

  @ObservationIgnored let client: EmbyClient
  @ObservationIgnored let userID: String

  /// 播完自动播下一集。Swiftfin 读写服务器上的用户配置；这里存在本机，默认开（与 Jellyfin/Emby 用户默认值相同）。
  var isAutoPlayEnabled: Bool {
    didSet { UserDefaults.standard.set(isAutoPlayEnabled, forKey: Self.autoPlayKey) }
  }

  init(client: EmbyClient, userID: String) {
    self.client = client
    self.userID = userID
    isAutoPlayEnabled = UserDefaults.standard.object(forKey: Self.autoPlayKey) as? Bool ?? true
  }

  /// 接入点：片头/片尾片段。
  func mediaSegments(itemID: String) async throws -> [MediaSegmentDto] { [] }

  /// 接入点：同一季的全部集（队列面板）。
  func seasonEpisodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto] { [] }

  /// 接入点：相邻集（上一集/下一集）。
  func adjacentEpisodes(seriesID: String, itemID: String) async throws -> [BaseItemDto] { [] }
}

/// 与 Swiftfin 的 `JellyfinClient` 同名：拖动预览图用到的图集地址。
nonisolated struct JellyfinClient {
  let emby: EmbyClient

  /// Jellyfin trickplay 图集。Emby 没有这套接口；若日后接入 Emby 的 BIF 缩略图，在这里返回图集地址并给条目填 `trickplay`。
  func trickplayTileURL(itemID: String, width: Int, index: Int, mediaSourceID: String) -> URL? {
    nil
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
