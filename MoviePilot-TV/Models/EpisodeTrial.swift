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

/// 与服务器和账号绑定的试看订阅配置，具体的季集来自每次请求。没指定的项保留 MoviePilot 默认订阅配置的值。
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

  /// 只写规则里指定了的项，没指定的保留草稿原值：试看订阅上是 MoviePilot 新建时按默认订阅配置填好的值，
  /// 规则编辑表单上是空。包含规则例外：试看订阅创建时写成了拒绝所有资源，没指定就换成 `includeFallback`。
  /// IMDb 搜索只有开和不指定两种，不指定时沿用原值。
  func apply(to draft: inout Subscribe, includeFallback: String? = nil) {
    func text(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }
    if let sites = sites, !sites.isEmpty { draft.sites = sites }
    if searchByIMDb { draft.search_imdbid = 1 }
    if let keyword = text(keyword) { draft.keyword = keyword }
    if let quality = text(quality) { draft.quality = quality }
    if let resolution = text(resolution) { draft.resolution = resolution }
    if let effect = text(effect) { draft.effect = effect }
    draft.include = text(include) ?? includeFallback
    if let exclude = text(exclude) { draft.exclude = exclude }
    if let customWords = text(customWords) { draft.custom_words = customWords }
    if let filterGroups = filterGroups, !filterGroups.isEmpty { draft.filter_groups = filterGroups }
    if let downloader = text(downloader) { draft.downloader = downloader }
    if let savePath = text(savePath) { draft.save_path = savePath }
  }
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
  /// 补搜回执没拿到时订阅就没了，从这时起按下载历史等那次搜索的结果；过了搜索最长运行时间仍没有就不会再有。
  var searchLostSince: Date?
  var downloadHash: String?
  var downloader: String?
  /// 下载在下载器、整理队列和整理历史里都确认找不到的起始时刻。
  var downloadMissingSince: Date?
  /// MoviePilot 识别出的标准标题，整理历史按它查询。
  var historyTitle: String?
  var previousDownloadHistoryIDs: Set<Int> = []

  var isTracking: Bool {
    // 可以播放、整理失败都算结束：只剩服务器上的临时订阅要收尾。整理失败后在 MoviePilot 重新整理成功的，
    // 页面再打开时按媒体库发现。
    if progress.isReady || progress == .organizationFailed { return temporary != nil || creationMarker != nil }
    return formalSubscriptionID != nil || temporary != nil || creationMarker != nil || searchPending
      || (batchID != nil && !searchFinished) || searchMayHaveDownloaded || downloadHash != nil
  }

  /// 服务器上不再有本任务的临时订阅，也不会有本任务提交的下载时，才允许重新发起。
  var canRestart: Bool {
    if progress == .organizationFailed { return temporary == nil && creationMarker == nil }
    return !progress.isReady && formalSubscriptionID == nil && temporary == nil && creationMarker == nil
      && !searchPending && !searchMayHaveDownloaded && downloadHash == nil
  }

  /// 媒体库里这一集可能刚有或刚没：从没查过、整理中或整理完在等入库、整理失败（可能在 MoviePilot 重新整理）、
  /// 已经可以播放（可能又被删掉）时。
  /// 其余时候（搜索、下载中）这一集不会进媒体库，按集索引缓存查就够了，不用每次轮询都重读各台媒体服务器。
  var libraryMayChange: Bool {
    switch progress {
    case .checking, .organizing, .organizationFailed, .waitingForLibrary, .ready: true
    default: false
    }
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

  /// 全部可写字段的指纹。只把后端会整理的几处先统一：空文本当作没填，站点去重排序，空列表当作没填。
  /// 写入后没读回来时，后端整理过的样子也能认出是自己写的；别处改过任何字段都对不上。
  static func fingerprint(_ row: Subscribe) throws -> String {
    let blank = Subscribe(id: row.id, name: "", type: "")
    var settings = row
    // 分类路径由 MoviePilot 从稳定 ID 派生。
    if settings.media_category_id != nil { settings.media_category = nil }
    let texts: [WritableKeyPath<Subscribe, String?>] = [
      \.year, \.keyword, \.quality, \.resolution, \.effect, \.include, \.exclude, \.downloader, \.save_path,
      \.custom_words, \.filter, \.episode_group, \.media_category, \.music_type, \.audio_quality, \.audio_format,
      \.media_category_id,
    ]
    for keyPath in texts where settings[keyPath: keyPath] == "" { settings[keyPath: keyPath] = nil }
    settings.sites = settings.sites.flatMap { $0.isEmpty ? nil : Array(Set($0)).sorted() }
    if settings.filter_groups?.isEmpty == true { settings.filter_groups = nil }
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
    guard let written = try? settingsDigest(draft), let read = try? settingsDigest(row) else { return false }
    return written == read
  }

  /// `preservesSettings` 比较的那组字段按含义归一后的摘要。
  static func settingsDigest(_ row: Subscribe) throws -> String {
    struct Settings: Encodable {
      let season, start, total, bestVersion, bestVersionFull: Int?
      let searchIMDb: Int
      let sites: [Int]
      let filterGroups: [String]
      let texts: [String?]
    }
    func text(_ value: String?) -> String? { value == "" ? nil : value }
    let settings = Settings(
      season: row.season, start: row.start_episode, total: row.total_episode, bestVersion: row.best_version,
      bestVersionFull: row.best_version_full, searchIMDb: row.search_imdbid ?? 0,
      sites: Array(Set(row.sites ?? [])).sorted(), filterGroups: row.filter_groups ?? [],
      texts: [
        row.keyword, row.quality, row.resolution, row.effect, row.include, row.exclude, row.custom_words,
        row.downloader, row.save_path,
      ].map(text))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(settings), as: UTF8.self)
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
  /// 后端受理并给出订阅 ID：可能是新建的，也可能是同季已有的那条。
  case accepted(Int)
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
  /// 还在试看中的临时订阅。期间占着这一季，不能另建、编辑、暂停或取消，试看结束后自动删除。
  /// 试看订阅一直暂停着，只有刚创建、还没暂停的几秒里是拒绝所有资源的占位。在别处被重新启用、
  /// 不再暂停的就已经是正式订阅，不再按试看拦着；带不带试看标记只决定它归不归试看服务收尾。
  var isEpisodeTrial: Bool {
    EpisodeTrialTemporarySubscription.isTrialRow(self)
      && (state == "S" || include == EpisodeTrialTemporarySubscription.blockedInclude)
  }

  /// 是否是按这个媒体身份和季删除时会被一起删掉的试看订阅。MoviePilot 按来源对应的 ID 列匹配，
  /// 不看剧集组；`season` 为空时整部剧都算。
  func isEpisodeTrial(of identity: MediaIdentity, season: Int?) -> Bool {
    guard isEpisodeTrial, season == nil || self.season == season else { return false }
    if self.identity == identity { return true }
    let sourceID: String? =
      switch identity.source {
      case "themoviedb": tmdbid.map(String.init)
      case "douban": doubanid
      case "bangumi": bangumiid.map(String.init)
      case "anilist": anilistid.map(String.init)
      default: nil
      }
    return sourceID == identity.mediaId
  }

  /// 试看的是哪一季哪一集，例如「第 2 季第 5 集」，订阅卡上代替集数进度显示。
  var episodeTrialTargetText: String? {
    guard isEpisodeTrial, let episode = start_episode, episode > 0 else { return nil }
    return season.map { "第 \($0) 季第 \(episode) 集" } ?? "第 \(episode) 集"
  }
}

/// 碰到试看订阅时的系统提示框文字，订阅面板、首页订阅卡和季订阅页共用。
nonisolated enum EpisodeTrialHoldNotice {
  static let title = "这一季正在试看"
  static let subscribeMessage = "要订阅这一季，先取消试看。已经下载的文件不会删除。"
  /// 不能取消试看的账号（不是管理员）看到的说明。
  static let waitMessage = "试看结束后再订阅这一季。"
  static let manageMessage = "这是试看一集用的临时订阅，试看结束后会自动删除。取消试看后，这一季就能正常订阅；已经下载的文件不会删除。"
  /// 不能取消试看的账号（不是管理员）在订阅卡片上看到的说明。
  static let infoMessage = "这是试看一集用的临时订阅，试看结束后会自动删除。"
  static let cancelTitle = "取消试看"
  static let cancelAndSubscribeTitle = "取消试看，继续订阅"
  static let backTitle = "返回"
  static let cancelFailure = "暂时无法取消试看，请稍后重试。"
  /// 按季或整部剧取消订阅时，同一季还有试看订阅（可能在另一个剧集组）。
  static let deleteBlockedMessage = "这一季正在试看，先取消试看再取消订阅。"
}

/// 试看的这一集入库后的提示。用户多半已经离开详情页，看不到进度，所以用全局提示告诉他可以播放了。
nonisolated enum EpisodeTrialReadyNotice {
  static let messageKey = "message"

  static func message(for request: EpisodeTrialRequest) -> String {
    let title = trimmedNonEmpty([request.media.title]).map { "《\($0)》" } ?? "试看的剧集"
    return "\(title)第 \(request.season) 季第 \(request.episodeNumber) 集已入库，可以播放了。"
  }
}
