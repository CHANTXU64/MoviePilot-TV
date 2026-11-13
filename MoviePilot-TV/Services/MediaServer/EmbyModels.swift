import Foundation

// Emby 接口的数据结构，只在 Emby 适配器（`EmbyServerConnection`）内使用；对外一律转换成 `ServerMediaItem`、`ServerMediaSource`。

nonisolated struct EmbyPublicSystemInfo: Decodable, Sendable {
  let id: String?
  let serverName: String?
  let version: String?

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case serverName = "ServerName"
    case version = "Version"
  }
}

nonisolated struct EmbyUser: Decodable, Sendable {
  let id: String
  let name: String?
  let isAdministrator: Bool

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case policy = "Policy"
  }

  private struct Policy: Decodable {
    let isAdministrator: Bool?
    private enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator" }
  }

  init(id: String, name: String?, isAdministrator: Bool) {
    self.id = id
    self.name = name
    self.isAdministrator = isAdministrator
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    let policy = try? container.decodeIfPresent(Policy.self, forKey: .policy)
    isAdministrator = policy?.isAdministrator ?? false
  }

  /// 与 MoviePilot `Emby.get_user` 相同的选择顺序：依次匹配候选用户名，都不匹配时取第一个管理员。
  static func select(from users: [EmbyUser], preferredNames: [String?]) -> EmbyUser? {
    for name in preferredNames {
      guard let name, !name.isEmpty else { continue }
      if let user = users.first(where: { $0.name == name }) { return user }
    }
    return users.first { $0.isAdministrator }
  }
}

nonisolated struct EmbyItem: Decodable, Sendable {
  let id: String
  let name: String?
  let type: String?
  let runTimeTicks: Int64?
  /// 原样保留的用户数据（续播位置等）。剧集列表里的 `PlayCount` 恒为 0，写回观看进度以重新读取的单条条目为准
  /// （见 `EmbyServerConnection.saveWatchProgress`）。
  let userData: [String: JSONValue]?
  /// 剧集：集号、季号、剧名。一个文件包含多集时 `IndexNumberEnd` 是最后一集。
  let indexNumber: Int?
  let indexNumberEnd: Int?
  let parentIndexNumber: Int?
  let seriesName: String?
  /// `Virtual` 表示 Emby 只有元数据、没有文件（缺失的集）。
  let locationType: String?
  /// 外部编号，如 `{"Tmdb": "12345", "Imdb": "tt…"}`。MoviePilot 同步媒体库时读的就是它；单集条目上的 `Tmdb` 是 TMDB 单集 ID。
  let providerIDs: [String: String]?
  /// 服务器上的文件路径。列表接口要在 `Fields` 里点名才给。
  let path: String?
  let premiereDate: String?
  /// 单集所属的剧。
  let seriesID: String?
  /// 以下是播放界面的展示信息，MoviePilot 没有时才用（见 `PlaybackMetadata`）。简介在列表接口里要点名才给。
  let overview: String?
  let communityRating: Double?
  let officialRating: String?
  /// 图片类型（`Primary`、`Thumb` 等）→ 图片版本标签。
  let imageTags: [String: String]?
  let backdropImageTags: [String]?
  let seriesPrimaryImageTag: String?

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case type = "Type"
    case runTimeTicks = "RunTimeTicks"
    case userData = "UserData"
    case indexNumber = "IndexNumber"
    case indexNumberEnd = "IndexNumberEnd"
    case parentIndexNumber = "ParentIndexNumber"
    case seriesName = "SeriesName"
    case locationType = "LocationType"
    case providerIDs = "ProviderIds"
    case path = "Path"
    case premiereDate = "PremiereDate"
    case seriesID = "SeriesId"
    case overview = "Overview"
    case communityRating = "CommunityRating"
    case officialRating = "OfficialRating"
    case imageTags = "ImageTags"
    case backdropImageTags = "BackdropImageTags"
    case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    runTimeTicks = try? container.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
    userData = try? container.decodeIfPresent([String: JSONValue].self, forKey: .userData)
    indexNumber = try? container.decodeIfPresent(Int.self, forKey: .indexNumber)
    indexNumberEnd = try? container.decodeIfPresent(Int.self, forKey: .indexNumberEnd)
    parentIndexNumber = try? container.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
    seriesName = try? container.decodeIfPresent(String.self, forKey: .seriesName)
    locationType = try? container.decodeIfPresent(String.self, forKey: .locationType)
    providerIDs = try? container.decodeIfPresent([String: String].self, forKey: .providerIDs)
    path = try? container.decodeIfPresent(String.self, forKey: .path)
    premiereDate = try? container.decodeIfPresent(String.self, forKey: .premiereDate)
    seriesID = try? container.decodeIfPresent(String.self, forKey: .seriesID)
    overview = try? container.decodeIfPresent(String.self, forKey: .overview)
    communityRating = try? container.decodeIfPresent(Double.self, forKey: .communityRating)
    officialRating = try? container.decodeIfPresent(String.self, forKey: .officialRating)
    imageTags = try? container.decodeIfPresent([String: String].self, forKey: .imageTags)
    backdropImageTags = try? container.decodeIfPresent([String].self, forKey: .backdropImageTags)
    seriesPrimaryImageTag = try? container.decodeIfPresent(String.self, forKey: .seriesPrimaryImageTag)
  }

  var playbackPositionTicks: Int64 {
    switch userData?["PlaybackPositionTicks"] {
    case .int(let value): return Int64(value)
    case .double(let value): return Int64(value)
    default: return 0
    }
  }

  /// 转成与服务器无关的条目。没有 `Type` 时按 `defaultKind`（剧集列表里的都是单集）。
  /// `image` 按条目 ID、图片类型和版本标签给出图片地址；不传时条目不带图片。
  func serverItem(
    defaultKind: ServerMediaItem.Kind = .other, image: ((_ itemID: String, _ type: String, _ tag: String) -> URL?)? = nil
  ) -> ServerMediaItem {
    let kind: ServerMediaItem.Kind
    switch type {
    case "Movie": kind = .movie
    case "Series": kind = .series
    case "Episode": kind = .episode
    case nil: kind = defaultKind
    default: kind = .other
    }
    return ServerMediaItem(
      id: id,
      kind: kind,
      name: name,
      seriesName: seriesName,
      seasonNumber: parentIndexNumber,
      episodeNumber: indexNumber,
      episodeNumberEnd: indexNumberEnd,
      runtimeSeconds: runTimeTicks.map(EmbyTicks.seconds),
      resumePositionSeconds: EmbyTicks.seconds(playbackPositionTicks),
      hasFile: locationType?.lowercased() != "virtual",
      externalIDs: ExternalMediaID.normalizedTable(providerIDs),
      path: path,
      premiereDate: premiereDate,
      seriesID: seriesID,
      overview: overview,
      communityRating: communityRating,
      officialRating: officialRating,
      posterURL: posterURL(kind: kind, image: image),
      thumbnailURL: thumbnailURL(kind: kind, image: image))
  }

  /// 竖版海报：单集用所属剧的主图，其他用自己的主图。
  private func posterURL(
    kind: ServerMediaItem.Kind, image: ((String, String, String) -> URL?)?
  ) -> URL? {
    guard let image else { return nil }
    if kind == .episode {
      guard let seriesID, let tag = trimmedNonEmpty([seriesPrimaryImageTag]) else { return nil }
      return image(seriesID, "Primary", tag)
    }
    return trimmedNonEmpty([imageTags?["Primary"]]).flatMap { image(id, "Primary", $0) }
  }

  /// 横版图：单集的主图就是这一集的截图；电影用横版缩略图，没有时用第一张背景图。
  private func thumbnailURL(
    kind: ServerMediaItem.Kind, image: ((String, String, String) -> URL?)?
  ) -> URL? {
    guard let image else { return nil }
    if kind == .episode {
      return trimmedNonEmpty([imageTags?["Primary"]]).flatMap { image(id, "Primary", $0) }
    }
    if let tag = trimmedNonEmpty([imageTags?["Thumb"]]) { return image(id, "Thumb", tag) }
    return trimmedNonEmpty([backdropImageTags?.first]).flatMap { image(id, "Backdrop", $0) }
  }
}

nonisolated struct EmbyMediaStream: Decodable, Sendable, Equatable {
  let type: String?
  let codec: String?
  let isDefault: Bool?
  /// 文件外的流（外挂字幕等），不是文件里的轨道。
  var isExternal: Bool?
  /// 以下只有视频流有，开播前向电视申请显示模式用（见 `DisplayModeHint`）。
  var width: Int?
  var height: Int?
  /// Emby 读到的帧率，如 23.976025。
  var frameRate: Double?
  /// `SDR`、`HDR 10`、`HLG`、`DolbyVision` 等。
  var videoRange: String?
  /// `Hdr10`、`Hdr10Plus`、`HyperLogGamma`、`DolbyVision` 等。
  var extendedVideoType: String?
  /// 杜比视界的配置，如 `DoviProfile50`、`DoviProfile81`。
  var extendedVideoSubType: String?

  init(type: String?, codec: String?, isDefault: Bool? = nil, isExternal: Bool? = nil) {
    self.type = type
    self.codec = codec
    self.isDefault = isDefault
    self.isExternal = isExternal
  }

  private enum CodingKeys: String, CodingKey {
    case type = "Type"
    case codec = "Codec"
    case isDefault = "IsDefault"
    case isExternal = "IsExternal"
    case width = "Width"
    case height = "Height"
    case realFrameRate = "RealFrameRate"
    case averageFrameRate = "AverageFrameRate"
    case videoRange = "VideoRange"
    case extendedVideoType = "ExtendedVideoType"
    case extendedVideoSubType = "ExtendedVideoSubType"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    codec = try? container.decodeIfPresent(String.self, forKey: .codec)
    isDefault = try? container.decodeIfPresent(Bool.self, forKey: .isDefault)
    isExternal = try? container.decodeIfPresent(Bool.self, forKey: .isExternal)
    width = try? container.decodeIfPresent(Int.self, forKey: .width)
    height = try? container.decodeIfPresent(Int.self, forKey: .height)
    frameRate =
      (try? container.decodeIfPresent(Double.self, forKey: .realFrameRate))
      ?? (try? container.decodeIfPresent(Double.self, forKey: .averageFrameRate))
    videoRange = try? container.decodeIfPresent(String.self, forKey: .videoRange)
    extendedVideoType = try? container.decodeIfPresent(String.self, forKey: .extendedVideoType)
    extendedVideoSubType = try? container.decodeIfPresent(String.self, forKey: .extendedVideoSubType)
  }
}

nonisolated struct EmbyMediaSource: Decodable, Sendable, Equatable {
  let id: String
  /// 版本名（如「4K HDR」「1080p」），播放设置里的版本选择用它。
  let name: String?
  let container: String?
  let `protocol`: String?
  let mediaStreams: [EmbyMediaStream]
  /// `MediaStreams` 里有读不出的条目：数不准文件里有几条轨道。
  let hasUnreadableStreams: Bool
  /// 这个版本的片长。条目上的 `RunTimeTicks` 只对应其中一个版本。
  let runTimeTicks: Int64?
  init(
    id: String, name: String? = nil, container: String?, protocol: String? = "File", mediaStreams: [EmbyMediaStream],
    runTimeTicks: Int64? = nil
  ) {
    self.id = id
    self.name = name
    self.container = container
    self.protocol = `protocol`
    self.mediaStreams = mediaStreams
    hasUnreadableStreams = false
    self.runTimeTicks = runTimeTicks
  }

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case container = "Container"
    case `protocol` = "Protocol"
    case mediaStreams = "MediaStreams"
    case runTimeTicks = "RunTimeTicks"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try? container.decodeIfPresent(String.self, forKey: .name)
    self.container = try? container.decodeIfPresent(String.self, forKey: .container)
    self.protocol = try? container.decodeIfPresent(String.self, forKey: .protocol)
    let streams = try? container.decodeIfPresent([LossyDecodable<EmbyMediaStream>].self, forKey: .mediaStreams)
    mediaStreams = streams?.compactMap(\.value) ?? []
    hasUnreadableStreams = streams?.contains { $0.value == nil } ?? false
    runTimeTicks = try? container.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
  }

  /// 文件里音视频和字幕轨的条数（不含外挂字幕等文件外的流）。没有流信息、有条目读不出或类型认不出、
  /// 或一条音视频流都没有时为 nil：数不准。封面图、字体等附件不是轨道，不算。
  var embeddedTrackCount: Int? {
    guard !hasUnreadableStreams else { return nil }
    var count = 0
    var hasAudioOrVideo = false
    for stream in mediaStreams where stream.isExternal != true {
      switch stream.type?.lowercased() {
      case "video", "audio":
        count += 1
        hasAudioOrVideo = true
      case "subtitle":
        count += 1
      case "embeddedimage", "attachment":
        continue
      default:
        return nil
      }
    }
    return hasAudioOrVideo ? count : nil
  }

  /// 转成与服务器无关的片源：能否直连、显示模式提示都在这里按 Emby 的数据算好。
  var serverSource: ServerMediaSource {
    let unsupported: PlaybackUnsupported?
    switch EmbyDirectPlay.evaluate(self) {
    case .success: unsupported = nil
    case .failure(let reason): unsupported = reason
    }
    return ServerMediaSource(
      id: id, name: name, container: container, unsupportedReason: unsupported,
      displayModeHint: DisplayModeHint(source: self), embeddedTrackCount: embeddedTrackCount,
      runtimeSeconds: runTimeTicks.map(EmbyTicks.seconds))
  }
}

nonisolated extension DisplayModeHint {
  /// Emby 片源的第一条视频流。
  init?(source: EmbyMediaSource) {
    guard let video = source.mediaStreams.first(where: { $0.type?.lowercased() == "video" }) else { return nil }
    self.init(
      width: video.width, height: video.height, framesPerSecond: video.frameRate, codec: video.codec,
      range: Self.dynamicRange(of: video))
  }

  /// Emby 的 `VideoRange`、`ExtendedVideoType`、`ExtendedVideoSubType` 对应的动态范围；认不准时为 nil。
  private static func dynamicRange(of video: EmbyMediaStream) -> DynamicRange? {
    let extended = video.extendedVideoType?.lowercased() ?? ""
    let range = video.videoRange?.lowercased() ?? ""
    if extended == "dolbyvision" || range == "dolbyvision" {
      switch video.extendedVideoSubType?.lowercased() {
      case "doviprofile50": return .dolbyVision(profile: 5, compatibilityID: 0)
      case "doviprofile81": return .dolbyVision(profile: 8, compatibilityID: 1)
      case "doviprofile84": return .dolbyVision(profile: 8, compatibilityID: 4)
      default: return nil
      }
    }
    if extended.hasPrefix("hdr10") || range.contains("hdr 10") || range.contains("hdr10") { return .hdr10 }
    if extended == "hyperloggamma" || extended == "hlg" || range.contains("hlg") { return .hlg }
    if range == "sdr" || extended == "none" || (extended.isEmpty && range.isEmpty) { return .sdr }
    return nil
  }
}

nonisolated struct EmbyPlaybackInfo: Decodable, Sendable {
  let mediaSources: [EmbyMediaSource]
  let playSessionID: String?
  let errorCode: String?

  private enum CodingKeys: String, CodingKey {
    case mediaSources = "MediaSources"
    case playSessionID = "PlaySessionId"
    case errorCode = "ErrorCode"
  }

  /// `MediaSources` 读不到有效列表时报告解码失败；有 Emby 错误码则交给调用方报告。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    playSessionID = try? container.decodeIfPresent(String.self, forKey: .playSessionID)
    errorCode = try? container.decodeIfPresent(String.self, forKey: .errorCode)
    do {
      mediaSources = try LossyDecodable<EmbyMediaSource>.decodeArray(in: container, forKey: .mediaSources)
    } catch where errorCode?.isEmpty == false {
      mediaSources = []
    }
  }
}

/// Emby 列表接口的分页结构（`/Shows/{id}/Episodes` 等）。
/// 只有确实读到 `Items: []` 才是空列表。部分条目坏掉时保留能读到的条目。
nonisolated struct EmbyItemsPage: Decodable, Sendable {
  let items: [EmbyItem]

  private enum CodingKeys: String, CodingKey { case items = "Items" }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    items = try LossyDecodable<EmbyItem>.decodeArray(in: container, forKey: .items)
  }
}

/// `Library/SelectableMediaFolders` 里的一个媒体库：`Id` 用来刷新这个媒体库，`SubFolders` 的 `Path` 是 Emby 看到的文件夹。
/// MoviePilot 叫 Emby 刷新时按这个接口找媒体库。
nonisolated struct EmbyMediaFolder: Decodable, Sendable {
  let id: String
  let paths: [String]

  private enum CodingKeys: String, CodingKey {
    case id = "Id"
    case subFolders = "SubFolders"
  }

  private struct SubFolder: Decodable, Sendable {
    let path: String?
    private enum CodingKeys: String, CodingKey { case path = "Path" }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let id = trimmedNonEmpty([try container.decode(String.self, forKey: .id)]) else {
      throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "媒体库没有 ID")
    }
    self.id = id
    // 文件夹读不出时这个媒体库还能整库刷新，只是按路径找不到它。
    let subFolders = (try? container.decodeIfPresent([LossyDecodable<SubFolder>].self, forKey: .subFolders)) ?? nil
    paths = (subFolders ?? []).compactMap { $0.value?.path.flatMap { trimmedNonEmpty([$0]) } }
  }

  /// 整份列表：个别媒体库读不出时丢掉它，其余照常用。
  static func list(from decoder: Decoder) throws -> [EmbyMediaFolder] {
    var container = try decoder.unkeyedContainer()
    var folders: [EmbyMediaFolder] = []
    var count = 0
    while !container.isAtEnd {
      count += 1
      if let folder = try container.decode(LossyDecodable<EmbyMediaFolder>.self).value { folders.append(folder) }
    }
    guard count == 0 || !folders.isEmpty else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "媒体库全部无法解码"))
    }
    return folders
  }
}

/// `Library/VirtualFolders` 里的一个媒体库：文件夹和单集的元数据来源（要管理员权限的密钥）。
/// 单集对应据此判断服务器上的单集资料是不是从 TMDB 来的（见 `MediaLibraryProfile`）。
nonisolated struct EmbyVirtualFolder: Decodable, Sendable {
  let profile: MediaLibraryProfile

  private enum CodingKeys: String, CodingKey {
    case locations = "Locations"
    case libraryOptions = "LibraryOptions"
  }

  private struct Options: Decodable, Sendable {
    let paths: [String]
    let episodeFetchers: [String]?

    private enum CodingKeys: String, CodingKey {
      case pathInfos = "PathInfos"
      case typeOptions = "TypeOptions"
    }

    private struct PathInfo: Decodable, Sendable {
      let path: String?
      private enum CodingKeys: String, CodingKey { case path = "Path" }
    }

    private struct TypeOption: Decodable, Sendable {
      let type: String?
      let fetchers: [String]?
      private enum CodingKeys: String, CodingKey {
        case type = "Type"
        case fetchers = "MetadataFetchers"
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let infos = (try? container.decodeIfPresent([LossyDecodable<PathInfo>].self, forKey: .pathInfos)) ?? nil
      paths = (infos ?? []).compactMap { $0.value?.path.flatMap { trimmedNonEmpty([$0]) } }
      let types = (try? container.decodeIfPresent([LossyDecodable<TypeOption>].self, forKey: .typeOptions)) ?? nil
      // 单集这一项读不出时按没有处理：服务器用默认来源，含 TMDB。
      episodeFetchers = (types ?? []).compactMap(\.value).first { $0.type == "Episode" }?.fetchers
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let locations = (try? container.decodeIfPresent([LossyDecodable<String>].self, forKey: .locations)) ?? nil
    let options = (try? container.decodeIfPresent(Options.self, forKey: .libraryOptions)) ?? nil
    var paths: [String] = []
    for path in (locations ?? []).compactMap({ $0.value.flatMap { trimmedNonEmpty([$0]) } }) + (options?.paths ?? [])
    where !paths.contains(path) {
      paths.append(path)
    }
    profile = MediaLibraryProfile(paths: paths, episodeFetchers: options?.episodeFetchers)
  }
}

/// `Library/VirtualFolders` 的回包（顶层是数组）。个别媒体库读不出时丢掉它：它的文件找不到所属的库，按来源不明处理。
nonisolated struct EmbyVirtualFolderList: Decodable, Sendable {
  let profiles: [MediaLibraryProfile]

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var profiles: [MediaLibraryProfile] = []
    while !container.isAtEnd {
      if let folder = try container.decode(LossyDecodable<EmbyVirtualFolder>.self).value { profiles.append(folder.profile) }
    }
    self.profiles = profiles
  }
}

/// `Library/SelectableMediaFolders` 的回包（顶层是数组）。
nonisolated struct EmbyMediaFolderList: Decodable, Sendable {
  let folders: [EmbyMediaFolder]

  init(from decoder: Decoder) throws {
    folders = try EmbyMediaFolder.list(from: decoder)
  }
}

/// 数组里单个元素坏掉时只丢弃该元素。
nonisolated private struct LossyDecodable<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
  init(from decoder: Decoder) throws {
    value = try? Value(from: decoder)
  }

  /// 读必需的数组字段。数组非空但没有一个有效元素时，整份数据无法识别。
  static func decodeArray<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> [Value] {
    let entries = try container.decode([Self].self, forKey: key)
    let values = entries.compactMap(\.value)
    guard entries.isEmpty || !values.isEmpty else {
      throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "数组中的元素全部无法解码")
    }
    return values
  }
}

// MARK: - 直接播放判定

/// 应用内播放都直连原文件，Emby 不转码、不重新封装，统一由 mpv 播放。
nonisolated enum EmbyDirectPlay {
  struct Selection: Equatable, Sendable {
    let source: EmbyMediaSource
    /// 流地址扩展名，帮助播放器识别容器
    let fileExtension: String
  }

  typealias Unsupported = PlaybackUnsupported

  /// 取第一个本地文件版本。
  static func select(from sources: [EmbyMediaSource]) -> Result<Selection, Unsupported> {
    var firstReason: Unsupported?
    for source in sources {
      switch evaluate(source) {
      case .success(let selection):
        return .success(selection)
      case .failure(let reason):
        if firstReason == nil { firstReason = reason }
      }
    }
    return .failure(firstReason ?? .noSource)
  }

  static func evaluate(_ source: EmbyMediaSource) -> Result<Selection, Unsupported> {
    if let sourceProtocol = source.protocol, sourceProtocol.lowercased() != "file" {
      return .failure(.remoteSource)
    }
    // Emby 可能返回 ffprobe 的格式名，例如 `mov,mp4,m4a,3gp,3g2,mj2`、`matroska,webm`。
    let containerNames = (source.container ?? "")
      .lowercased()
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return .success(Selection(source: source, fileExtension: fileExtension(containerNames)))
  }

  private static func fileExtension(_ containerNames: [String]) -> String {
    if containerNames.contains(where: { $0 == "matroska" || $0 == "mkv" }) { return "mkv" }
    if containerNames.contains("mp4") { return "mp4" }
    let candidate = containerNames.first ?? ""
    let allowed = CharacterSet.alphanumerics
    guard !candidate.isEmpty, candidate.unicodeScalars.allSatisfy(allowed.contains) else {
      return "mkv"
    }
    return candidate
  }
}

/// Emby 的时间单位 tick 为 100 纳秒。
nonisolated enum EmbyTicks {
  static let perSecond: Double = 10_000_000

  static func from(seconds: Double) -> Int { Int(seconds * perSecond) }
  static func seconds(_ ticks: Int64) -> Double { Double(ticks) / perSecond }
}
