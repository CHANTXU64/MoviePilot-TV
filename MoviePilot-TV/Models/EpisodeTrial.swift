import Foundation
import CryptoKit

/// 与服务器和账号绑定的试看订阅配置，具体的季集来自每次请求。
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
  var mediaCategoryID: String? = nil

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
    if let mediaCategoryID = nonEmpty(mediaCategoryID) {
      draft.media_category_id = mediaCategoryID
    }
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
  var previousDownloadHistoryIDs: Set<Int> = []

  var isTracking: Bool {
    if progress.isReady { return temporary != nil || creationMarker != nil }
    return formalSubscriptionID != nil || temporary != nil || creationMarker != nil || searchPending
      || batchID != nil || searchMayHaveDownloaded || downloadHash != nil
  }

  /// 服务器上不再有本任务的临时订阅，也不会有本任务提交的下载时，才允许重新发起。
  var canRestart: Bool {
    !progress.isReady && formalSubscriptionID == nil && temporary == nil && creationMarker == nil
      && !searchPending && !searchMayHaveDownloaded && downloadHash == nil
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

  func matches(_ row: Subscribe, request: EpisodeTrialRequest) -> Bool {
    row.id == id && row.username == owner && row.type == "电视剧"
      && row.identity == request.identity && row.season == request.season
      && trimmedNonEmpty([row.episode_group]) == request.episodeGroup
      && row.filter == marker
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
    case id, media_source, media_id, seasons, episodes, episode_group, download_hash, downloader, status, note
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(Int.self, forKey: .id)
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
