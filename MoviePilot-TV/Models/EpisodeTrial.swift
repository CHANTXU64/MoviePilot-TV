import Foundation
import CryptoKit

/// 单集试看的入口判断，试看服务和设置页共用。
nonisolated enum EpisodeTrialAvailability {
  /// 试看从 MoviePilot v3.2.6 起开放：整季包从这个版本起只下载订阅范围内的集，单集试看才不会整季下载；
  /// 按集定位也依赖这个版本起季集列表返回的 TMDB 单集 ID。
  /// 极性属于「新行为版本限制」：低于该版本、读不出或无法解析时不提供；可解析且不低于该版本（含热修复）时提供。
  static let minimumBackendVersion = "v3.2.6"

  static func supports(backendVersion: String?) -> Bool {
    BackendVersionGate.isAvailable(since: minimumBackendVersion, backendVersion: backendVersion)
  }

  /// 试看要读写所有人的订阅、下载器和整理记录，只对管理员开放。
  static func isAvailable(canRequestSuperUserEndpoints: Bool, backendVersion: String?) -> Bool {
    canRequestSuperUserEndpoints && supports(backendVersion: backendVersion)
  }

  static var requirementMessage: String {
    "试看需要 MoviePilot \(minimumBackendVersion) 或更高版本和管理员账号"
  }
}

/// 与服务器和账号绑定的试看订阅配置，具体的季集来自每次请求。全部留空表示沿用 MoviePilot 的默认设置。
/// 不含整理类别：试看的这一集按 MoviePilot 自动识别的类别整理，和正式订阅进同一个媒体库。
nonisolated struct EpisodeTrialRule: Codable, Equatable, Sendable {
  var sites: [Int]? = nil
  var searchByIMDb = false
  var keyword: String? = nil
  var quality: String? = nil
  var resolution: String? = nil
  var effect: String? = nil
  var include: String? = nil
  var exclude: String? = nil
  var customWords: String? = nil
  var filterGroups: [String]? = nil
  var downloader: String? = nil
  var savePath: String? = nil

  init(
    sites: [Int]? = nil, searchByIMDb: Bool = false, keyword: String? = nil, quality: String? = nil,
    resolution: String? = nil, effect: String? = nil, include: String? = nil, exclude: String? = nil,
    customWords: String? = nil, filterGroups: [String]? = nil, downloader: String? = nil, savePath: String? = nil
  ) {
    self.sites = sites
    self.searchByIMDb = searchByIMDb
    self.keyword = keyword
    self.quality = quality
    self.resolution = resolution
    self.effect = effect
    self.include = include
    self.exclude = exclude
    self.customWords = customWords
    self.filterGroups = filterGroups
    self.downloader = downloader
    self.savePath = savePath
  }

  /// 从规则编辑表单的草稿读回，和 `apply(to:)` 互逆：空文本、空列表都记为未指定。
  init(settingsOf draft: Subscribe) {
    func text(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }
    func list<T>(_ value: [T]?) -> [T]? { value?.isEmpty == false ? value : nil }
    self.init(
      sites: list(draft.sites).map { Array(Set($0)).sorted() }, searchByIMDb: draft.search_imdbid == 1,
      keyword: text(draft.keyword), quality: text(draft.quality), resolution: text(draft.resolution),
      effect: text(draft.effect), include: text(draft.include), exclude: text(draft.exclude),
      customWords: text(draft.custom_words), filterGroups: list(draft.filter_groups),
      downloader: text(draft.downloader), savePath: text(draft.save_path))
  }

  var isDefault: Bool { self == EpisodeTrialRule() }

  func apply(to draft: inout Subscribe) {
    draft.sites = sites
    draft.search_imdbid = searchByIMDb ? 1 : 0
    draft.keyword = nonEmpty(keyword)
    draft.quality = nonEmpty(quality)
    draft.resolution = nonEmpty(resolution)
    draft.effect = nonEmpty(effect)
    draft.include = nonEmpty(include)
    draft.exclude = nonEmpty(exclude)
    draft.custom_words = nonEmpty(customWords)
    draft.filter_groups = filterGroups
    draft.downloader = nonEmpty(downloader)
    draft.save_path = nonEmpty(savePath)
  }

  private func nonEmpty(_ value: String?) -> String? { value == "" ? nil : value }
}

nonisolated struct EpisodeTrialRequest: Sendable {
  let media: MediaInfo
  let episode: MoviePilotEpisode
  let playbackContext: EpisodePlaybackContext
  let identity: MediaIdentity
  let episodeID: Int
  let episodeNumber: Int

  init?(
    media: MediaInfo, episode: MoviePilotEpisode, episodeGroup: String? = nil,
    libraryItem: MediaServerItemRef? = nil
  ) {
    guard let identity = media.identity,
      let episodeID = MediaIdentifier.validNumericIdentifier(episode.tmdbEpisodeID),
      let episodeNumber = MediaIdentifier.validNumericIdentifier(episode.episodeNumber),
      episodeNumber < Int.max,
      episode.seasonNumber >= 0,
      let playbackContext = EpisodePlaybackContext(
        media: media, episodeGroup: episodeGroup, seasons: [episode.seasonNumber], libraryItem: libraryItem)
    else { return nil }
    self.media = media
    self.episode = episode
    self.playbackContext = playbackContext
    self.identity = identity
    self.episodeID = episodeID
    self.episodeNumber = episodeNumber
  }

  var season: Int { episode.seasonNumber }
  var episodeGroup: String? { playbackContext.episodeGroup }
  var seasonKey: String { "\(playbackContext.tmdbID)|\(season)|\(episodeGroup ?? "")" }
  var key: String { "\(seasonKey)|\(episodeID)|\(episodeNumber)" }

  var target: EpisodeTrialTarget {
    EpisodeTrialTarget(identity: identity, season: season, episodeGroup: episodeGroup, seasonKey: seasonKey)
  }

  var knownIdentities: Set<MediaIdentity> {
    var identities: Set<MediaIdentity> = [identity]
    for (source, id) in playbackContext.expected.externalIDs {
      if let source = MediaIdentifier.normalizeSource(source) {
        identities.insert(MediaIdentity(source: source, mediaId: id))
      }
    }
    return identities
  }
}

/// 临时订阅属于哪一季。随任务持久化，定时清理不需要用户重新打开这一集。
nonisolated struct EpisodeTrialTarget: Codable, Equatable, Sendable {
  let source: String
  let mediaId: String
  let season: Int
  let episodeGroup: String?
  let seasonKey: String

  init(identity: MediaIdentity, season: Int, episodeGroup: String?, seasonKey: String) {
    source = identity.source
    mediaId = identity.mediaId
    self.season = season
    self.episodeGroup = episodeGroup
    self.seasonKey = seasonKey
  }

  var identity: MediaIdentity { MediaIdentity(source: source, mediaId: mediaId) }
}

nonisolated enum EpisodeTrialProgress: Equatable, Codable, Sendable {
  case checking
  case waitingForSubscription
  case subscriptionPaused
  case seasonTrialInProgress
  case searching
  case noEligibleResource
  case submissionUnconfirmed
  case downloading(progress: Double?)
  case organizing
  case organizationFailed
  case waitingForLibrary
  case ready(server: String)
  case unavailable(String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}

nonisolated struct EpisodeTrialJob: Codable, Sendable {
  var progress: EpisodeTrialProgress = .checking
  var target: EpisodeTrialTarget?
  var formalSubscriptionID: Int?
  var temporary: EpisodeTrialTemporarySubscription?
  var finishedTemporaryID: Int?
  var creationMarker: String?
  var searchPending = false
  /// 创建或补搜请求发出但没拿到回执的时刻；超过确认期仍查不到受理痕迹，按未受理收尾。
  var pendingSince: Date?
  var batchID: String?
  var searchFinished = false
  /// 补搜已受理且不能排除提交过下载。为真时不得重新发起，只能沿下载历史继续跟踪。
  var searchMayHaveDownloaded = false
  var downloadHash: String?
  var downloader: String?
  /// MoviePilot 识别出的标准标题，整理历史按它查询。
  var historyTitle: String?
  var previousDownloadHistoryIDs: Set<Int> = []

  var isTracking: Bool {
    if progress.isReady { return temporary != nil || creationMarker != nil }
    return formalSubscriptionID != nil || temporary != nil || creationMarker != nil || searchPending
      || (batchID != nil && !searchFinished) || searchMayHaveDownloaded || downloadHash != nil
  }

  /// 服务器上不再有本任务的临时订阅，也不会有本任务提交的下载时，才允许重新发起。
  var canRestart: Bool {
    !progress.isReady && formalSubscriptionID == nil && temporary == nil && creationMarker == nil
      && !searchPending && !searchMayHaveDownloaded && downloadHash == nil
  }

  /// 服务器上可能还留着本任务的临时订阅，需要定时对账并清理。
  var needsCleanup: Bool { target != nil && (temporary != nil || creationMarker != nil) }

  /// 临时订阅的创建时间，用来决定清理频率。
  var cleanupStartedAt: Date? {
    (temporary?.marker ?? creationMarker).flatMap(EpisodeTrialTemporarySubscription.creationDate(of:))
  }

  func isPending(at now: Date) -> Bool {
    guard let pendingSince else { return false }
    return now.timeIntervalSince(pendingSince) < EpisodeTrialTemporarySubscription.confirmationWindow
  }
}

nonisolated struct EpisodeTrialTemporarySubscription: Codable, Sendable {
  static let markerPrefix = "tv-episode-trial-"
  static let blockedInclude = "(?!)"
  /// 一次创建或补搜从发出到在订阅列表里留下痕迹的最长等待。暂停、写规则和补搜在几秒内连续完成，
  /// 超过这个时长仍停在某一步，说明发起方已经中断。
  static let confirmationWindow: TimeInterval = 120

  /// 标记带上创建时间，任何会话都能判断一条仍拒绝所有资源的占位订阅是否已被发起方放弃。
  static func makeMarker(at date: Date) -> String {
    "\(markerPrefix)\(Int(date.timeIntervalSince1970))-\(UUID().uuidString.lowercased())"
  }

  static func creationDate(of marker: String) -> Date? {
    guard marker.hasPrefix(markerPrefix),
      let seconds = marker.dropFirst(markerPrefix.count).split(separator: "-").first,
      !seconds.isEmpty, seconds.utf8.allSatisfy({ (48...57).contains($0) }),
      let value = TimeInterval(seconds)
    else { return nil }
    return Date(timeIntervalSince1970: value)
  }

  static func isTrialRow(_ row: Subscribe) -> Bool {
    row.filter?.hasPrefix(markerPrefix) == true
  }

  /// 只创建、还没写入试看规则的占位订阅拒绝所有资源，删除它不会丢失用户设置或打断下载。
  static func isAbandonedPlaceholder(_ row: Subscribe, owner: String, now: Date) -> Bool {
    guard let id = row.id, id > 0, row.type == "电视剧", row.username == owner,
      row.include == blockedInclude, let marker = row.filter, let created = creationDate(of: marker)
    else { return false }
    return now.timeIntervalSince(created) >= confirmationWindow
  }

  let id: Int
  let marker: String
  let owner: String
  // 只保存表单指纹。用户从其他入口编辑过这条订阅时，TV 放弃自动清理。
  var fingerprints: Set<String> = []

  static func fingerprint(_ row: Subscribe) throws -> String {
    let blank = Subscribe(id: row.id, name: "", type: "")
    var settings = row
    // 分类路径由 MoviePilot 从稳定 ID 派生。
    if settings.media_category_id != nil { settings.media_category = nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(SubscriptionWriteDTO(original: blank, draft: settings))
    return Data(SHA256.hash(data: bytes)).base64EncodedString()
  }

  func matches(_ row: Subscribe, target: EpisodeTrialTarget) -> Bool {
    row.id == id && row.username == owner && row.type == "电视剧"
      && row.identity == target.identity && row.season == target.season
      && trimmedNonEmpty([row.episode_group]) == target.episodeGroup
      && row.filter == marker
  }

  /// 回读的订阅是否仍是这次写入的试看设置。季集锁定和洗版开关必须原样保留；
  /// 规则按含义比较：空文本与缺省相同，站点与缺省的空列表相同且不计顺序。
  static func preservesSettings(of draft: Subscribe, in row: Subscribe) -> Bool {
    func text(_ value: String?) -> String? { value == "" ? nil : value }
    guard row.season == draft.season, row.start_episode == draft.start_episode,
      row.total_episode == draft.total_episode, row.best_version == draft.best_version,
      row.best_version_full == draft.best_version_full,
      (row.search_imdbid ?? 0) == (draft.search_imdbid ?? 0),
      Set(row.sites ?? []) == Set(draft.sites ?? []), (row.filter_groups ?? []) == (draft.filter_groups ?? [])
    else { return false }
    let texts: [KeyPath<Subscribe, String?>] = [
      \.keyword, \.quality, \.resolution, \.effect, \.include, \.exclude, \.custom_words, \.downloader,
      \.save_path,
    ]
    return texts.allSatisfy { text(row[keyPath: $0]) == text(draft[keyPath: $0]) }
  }
}

nonisolated struct EpisodeTrialCreateSubscription: Encodable {
  let name: String?
  let type = "电视剧"
  let year: String?
  let media_source: String
  let media_id: String
  let season: Int
  let episode_group: String?
  let start_episode: Int
  let total_episode: Int
  let best_version = 1
  let best_version_full = 0
  let include = EpisodeTrialTemporarySubscription.blockedInclude
  // 当前 MoviePilot 保留旧 filter 字段，实际筛选读取 include、exclude 和 filter_groups。
  let filter: String

  init(request: EpisodeTrialRequest, marker: String) {
    name = request.media.title
    year = request.media.year
    media_source = request.identity.source
    media_id = request.identity.mediaId
    season = request.season
    episode_group = request.episodeGroup
    start_episode = request.episodeNumber
    // 创建时包含规则拒绝所有资源，暂停后把总集数改为目标集以启用后端手动集数锁。
    total_episode = request.episodeNumber + 1
    filter = marker
  }
}

nonisolated enum EpisodeTrialCreateReceipt {
  case created(Int)
  case reused(Int)
  case rejected
  case unconfirmed
}

nonisolated enum EpisodeTrialSearchReceipt {
  case scheduled(String)
  case rejected
  case unconfirmed
}

nonisolated struct EpisodeTrialBatch: Decodable {
  let batch_id: String
  let state: String
  let total_count: Int
  let finished_count: Int
  let download_counts: [String: Int]

  var isFinished: Bool { ["completed", "failed", "cancelled", "skipped"].contains(state) }

  static func isValidID(_ id: String) -> Bool {
    id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

nonisolated struct EpisodeTrialExecutionStatus: Decodable, Hashable {
  let source: String?
  let batch_id: String?
}

nonisolated struct EpisodeTrialTransferJob: Decodable {
  struct Transfer: Decodable {
    let downloader: String?
    let download_hash: String?
  }
  let tasks: [Transfer]?
}

/// 下载和整理历史都能提供媒体身份和季集范围。历史未注明下载器，须结合可信的下载回执或实时任务。
nonisolated struct EpisodeTrialHistoryRecord: Decodable, Sendable {
  struct Note: Decodable, Sendable {
    struct Subscription: Decodable, Sendable {
      let subscription_id: Int?
    }

    let subscription_download: Subscription?
  }

  let id: Int
  let title: String?
  let media_source: String?
  let media_id: String?
  let seasons: String?
  let episodes: String?
  let episode_group: String?
  let download_hash: String?
  let downloader: String?
  let status: Bool?
  let note: Note?

  private enum CodingKeys: String, CodingKey {
    case id, title, media_source, media_id, seasons, episodes, episode_group, download_hash, downloader, status
    case note
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(Int.self, forKey: .id)
    title = try? values.decodeIfPresent(String.self, forKey: .title)
    media_source = try values.decodeIfPresent(String.self, forKey: .media_source)
    media_id = try values.decodeIfPresent(String.self, forKey: .media_id)
    seasons = try values.decodeIfPresent(String.self, forKey: .seasons)
    episodes = try values.decodeIfPresent(String.self, forKey: .episodes)
    episode_group = try values.decodeIfPresent(String.self, forKey: .episode_group)
    download_hash = try values.decodeIfPresent(String.self, forKey: .download_hash)
    downloader = try? values.decodeIfPresent(String.self, forKey: .downloader)
    status = try? values.decodeIfPresent(Bool.self, forKey: .status)
    note = try? values.decodeIfPresent(Note.self, forKey: .note)
  }

  func matches(_ request: EpisodeTrialRequest) -> Bool {
    guard let identity = MediaIdentifier.resolve(source: media_source, mediaId: media_id),
      request.knownIdentities.contains(identity),
      trimmedNonEmpty([episode_group]) == request.episodeGroup,
      seasons.map({ Self.contains(request.season, in: $0, prefix: "S", single: true) }) == true,
      episodes.map({ Self.contains(request.episodeNumber, in: $0, prefix: "E", single: false) }) == true
    else { return false }
    return true
  }

  private static func contains(_ number: Int, in value: String, prefix: String, single: Bool) -> Bool {
    let parts = value.uppercased().split(
      omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "、" })
    if single && parts.count != 1 { return false }
    var matched = false
    for part in parts {
      let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
      let numbers = bounds.compactMap { component -> Int? in
        let token = component.trimmingCharacters(in: .whitespaces)
        let digits = token.hasPrefix(prefix) ? String(token.dropFirst()) : token
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(digits)
      }
      guard numbers.count == bounds.count, let first = numbers.first, let last = numbers.last,
        first <= last, (1...2).contains(numbers.count), !single || numbers.count == 1
      else { return false }
      matched = matched || (first...last).contains(number)
    }
    return matched
  }
}

nonisolated extension Subscribe {
  /// 单集试看建的临时订阅。期间占着这一季，不能另建、编辑、暂停或取消，试看结束后自动删除。
  var isEpisodeTrial: Bool { EpisodeTrialTemporarySubscription.isTrialRow(self) }

  /// 试看的是哪一季哪一集，例如「第 2 季第 5 集」，订阅卡上代替集数进度显示。
  var episodeTrialTargetText: String? {
    guard isEpisodeTrial, let episode = start_episode, episode > 0 else { return nil }
    return season.map { "第 \($0) 季第 \(episode) 集" } ?? "第 \(episode) 集"
  }
}

/// 碰到试看订阅时的系统提示框文字，订阅面板、首页订阅卡和季订阅页共用。
nonisolated enum EpisodeTrialHoldNotice {
  static let title = "这一季正在试看"
  static let subscribeMessage = "试看结束后再订阅这一季。"
  static let manageMessage = "这是试看一集用的临时订阅，试看结束后会自动删除，期间不能编辑、暂停或取消。"
}
