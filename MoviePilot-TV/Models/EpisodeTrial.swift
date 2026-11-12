import Foundation
import CryptoKit

/// 空文本当作没填。
nonisolated private func specified(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }

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
    func list<T>(_ value: [T]?) -> [T]? { value?.isEmpty == false ? value : nil }
    self.init(
      sites: list(draft.sites).map { Array(Set($0)).sorted() }, searchByIMDb: draft.search_imdbid == 1,
      keyword: specified(draft.keyword), quality: specified(draft.quality),
      resolution: specified(draft.resolution), effect: specified(draft.effect), include: specified(draft.include),
      exclude: specified(draft.exclude), customWords: specified(draft.custom_words),
      filterGroups: list(draft.filter_groups), downloader: specified(draft.downloader),
      savePath: specified(draft.save_path))
  }

  var isDefault: Bool { self == EpisodeTrialRule() }

  /// 只写规则里指定了的项，没指定的保留草稿原值：试看订阅上是 MoviePilot 新建时按默认订阅配置填好的值，
  /// 规则编辑表单上是空。包含规则例外：试看订阅创建时写成了拒绝所有资源，没指定就换成 `includeFallback`。
  /// IMDb 搜索只有开和不指定两种，不指定时沿用原值。
  func apply(to draft: inout Subscribe, includeFallback: String? = nil) {
    if let sites = sites, !sites.isEmpty { draft.sites = sites }
    if searchByIMDb { draft.search_imdbid = 1 }
    if let keyword = specified(keyword) { draft.keyword = keyword }
    if let quality = specified(quality) { draft.quality = quality }
    if let resolution = specified(resolution) { draft.resolution = resolution }
    if let effect = specified(effect) { draft.effect = effect }
    draft.include = specified(include) ?? includeFallback
    if let exclude = specified(exclude) { draft.exclude = exclude }
    if let customWords = specified(customWords) { draft.custom_words = customWords }
    if let filterGroups = filterGroups, !filterGroups.isEmpty { draft.filter_groups = filterGroups }
    if let downloader = specified(downloader) { draft.downloader = downloader }
    if let savePath = specified(savePath) { draft.save_path = savePath }
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
  var seasonKey: String { Self.seasonKey(tmdbID: playbackContext.tmdbID, season: season, episodeGroup: episodeGroup) }
  var key: String { Self.key(seasonKey: seasonKey, episodeID: episodeID, episodeNumber: episodeNumber) }

  static func seasonKey(tmdbID: Int, season: Int, episodeGroup: String?) -> String {
    "\(tmdbID)|\(season)|\(trimmedNonEmpty([episodeGroup]) ?? "")"
  }

  static func key(seasonKey: String, episodeID: Int, episodeNumber: Int) -> String {
    "\(seasonKey)|\(episodeID)|\(episodeNumber)"
  }

  /// 集列表里一集的试看键，与按它建的请求的 `key` 相同；建不出请求（缺 TMDB 单集 ID、集号）时为 nil。
  /// 卡片只用它查进度，不必为每张卡建完整的请求。
  static func key(tmdbID: Int, episode: MoviePilotEpisode, episodeGroup: String?) -> String? {
    guard let episodeID = MediaIdentifier.validNumericIdentifier(episode.tmdbEpisodeID),
      let episodeNumber = MediaIdentifier.validNumericIdentifier(episode.episodeNumber), episodeNumber < Int.max,
      episode.seasonNumber >= 0
    else { return nil }
    return key(
      seasonKey: seasonKey(tmdbID: tmdbID, season: episode.seasonNumber, episodeGroup: episodeGroup),
      episodeID: episodeID, episodeNumber: episodeNumber)
  }

  var target: EpisodeTrialTarget {
    EpisodeTrialTarget(
      identity: identity, tmdbID: playbackContext.tmdbID, season: season, episodeGroup: episodeGroup,
      seasonKey: seasonKey, episodeKey: key, episodeNumber: episodeNumber, title: trimmedNonEmpty([media.title]))
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

/// 试看的是哪一季哪一集。随凭据持久化，App 重启后不用重新打开这一集也能收尾。
nonisolated struct EpisodeTrialTarget: Codable, Equatable, Sendable {
  let source: String
  let mediaId: String
  /// 这部剧的 TMDB 编号。发起时的身份是豆瓣、Bangumi 等来源时，MoviePilot 新建订阅会换成 TMDB 身份，
  /// 订阅和下载记录上看到的是它。
  let tmdbID: Int?
  let season: Int
  let episodeGroup: String?
  let seasonKey: String
  /// 页面和进度用的这一集的键，与 `EpisodeTrialRequest.key` 相同。
  let episodeKey: String
  let episodeNumber: Int
  /// 整理历史只能按标题查，用页面上的剧名。
  let title: String?

  init(
    identity: MediaIdentity, tmdbID: Int? = nil, season: Int, episodeGroup: String?, seasonKey: String,
    episodeKey: String, episodeNumber: Int, title: String?
  ) {
    source = identity.source
    mediaId = identity.mediaId
    self.tmdbID = tmdbID
    self.season = season
    self.episodeGroup = episodeGroup
    self.seasonKey = seasonKey
    self.episodeKey = episodeKey
    self.episodeNumber = episodeNumber
    self.title = title
  }

  var identity: MediaIdentity { MediaIdentity(source: source, mediaId: mediaId) }

  /// 订阅和下载记录上可能出现的这部剧的身份：发起时的身份，以及 MoviePilot 换成的 TMDB 身份。
  var identities: Set<MediaIdentity> {
    var identities: Set<MediaIdentity> = [identity]
    if let tmdbID { identities.insert(MediaIdentity(source: "themoviedb", mediaId: String(tmdbID))) }
    return identities
  }
}

nonisolated enum EpisodeTrialProgress: Equatable, Sendable {
  /// 可以试看：媒体库、订阅和下载里都没有这一集。
  case notStarted
  case waitingForSubscription
  case subscriptionPaused
  /// 同一季的另一集正在试看。
  case seasonTrialInProgress
  case searching
  case cancelling
  /// 发出的请求没拿到回执，或有一处没查成，状态说不清。
  case submissionUnconfirmed
  /// `progress` 是下载器报的百分比（0–100），`remainingSeconds` 是 TV 按平均速度估的还要多久（见 `EpisodeTrialDownloadETA`）。
  case downloading(progress: Double?, remainingSeconds: Int? = nil)
  /// 下载器、整理队列和整理记录都明确查不到这个下载：下载器只列出还在下载的任务，通常是已经下完、等 MoviePilot 整理。
  /// 一直查不到时按 `EpisodeTrialService.missingDownloadLimit` 结束。
  case waitingForOrganization
  case organizing
  /// 整理完成，等媒体服务器把这一集入库。
  case waitingForLibrary
  /// 已经入库。`uncertain` 不为 nil 时只是按季号集号在 `server` 上找到了文件，可能不是这一集，播放前要说明。
  case ready(server: String, uncertain: UncertainEpisodeMatch? = nil)
  /// 试看结束了，没能看成（含用户取消）。
  case concluded(EpisodeTrialEnding)
  /// 现在不能试看，或这次没查成（不满足条件、已有相关订阅、请求失败、查询中断等）。不是结局，不保存。
  case unavailable(String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  /// 试看在进行中的哪一步。没在进行（可以试看、已结束、不能试看）或说不清是哪一步时为 nil。
  var stage: EpisodeTrialStage? {
    switch self {
    case .searching: .search
    case .downloading: .download
    case .waitingForOrganization, .organizing: .organize
    case .waitingForLibrary: .library
    default: nil
    }
  }

  /// 本机的试看还在进行：搜索、下载、整理、入库、取消中，或请求还没确认。
  var isInProgress: Bool {
    switch self {
    case .searching, .cancelling, .submissionUnconfirmed, .downloading, .waitingForOrganization, .organizing,
      .waitingForLibrary:
      true
    default: false
    }
  }
}

/// 试看的下载还要多久，按 TV 开始看到这个下载以来的平均速度估：已经下了多久 ÷ 这段时间下完的进度 × 还剩的进度。
/// 不用 MoviePilot 下载器接口的 `left_time`：qBittorrent 那边拿种子全部文件的大小（含整季包里没选的集）减已下载量，
/// 再除以这一刻的速度，快下完时反而越来越长。起点不用下载记录的时间：那是 MoviePilot 服务器的本地时间，不带时区。
nonisolated struct EpisodeTrialDownloadETA: Equatable, Sendable {
  /// 看了这么久才估：刚开始的样本太少，估出来跳得厉害。
  static let minimumSampleSeconds: TimeInterval = 30

  /// 开始看的时间和当时的进度（0–100）。
  let since: Date
  let startProgress: Double

  /// 还要多少秒；看得还不够久、这段时间进度没动或已经下完时为 nil，不显示剩余时间。
  func remainingSeconds(progress: Double, now: Date) -> Int? {
    let elapsed = now.timeIntervalSince(since)
    let done = progress - startProgress
    guard elapsed >= Self.minimumSampleSeconds, done > 0, progress < 100 else { return nil }
    return Int((elapsed * (100 - progress) / done).rounded(.up))
  }

  /// 按分钟向上取整：「不到 1 分钟」「约 13 分钟」「约 1 小时 5 分钟」。
  static func text(seconds: Int) -> String {
    guard seconds >= 60 else { return "不到 1 分钟" }
    let minutes = (seconds + 59) / 60
    guard minutes >= 60 else { return "约 \(minutes) 分钟" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "约 \(hours) 小时" : "约 \(hours) 小时 \(rest) 分钟"
  }
}

/// 试看从发起到能播放要经过的几步，卡片上画成几个进度点。第一次用的人多半以为下载完就能播，后面的整理和入库也要算进去。
nonisolated enum EpisodeTrialStage: Int, CaseIterable, Comparable, Sendable {
  case search, download, organize, library

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 试看没能看成的结局，按原因分类：卡片上显示短字，单集面板里显示完整说明。随账号保存。
nonisolated enum EpisodeTrialEnding: Codable, Equatable, Sendable {
  /// 用户取消了试看，或这次搜索在 MoviePilot 上被停掉了。
  case cancelled
  /// 搜索完成，没有符合条件的资源。
  case noEligibleResource
  /// MoviePilot 跳过或没做完这次搜索，说明写明是哪种。
  case searchIncomplete(String)
  case organizationFailed
  /// 跟不下去了：找不到下载记录、搜索记录，或下载任务不见了。说明写明是哪种。
  case lostTrack(String)
  /// 试看订阅在别处被删掉了。
  case removedElsewhere
  /// 试看订阅在别处被改过，TV 不再自动处理。
  case modifiedElsewhere
  /// 试看订阅没按要求生效（不是普通订阅、集数、规则没保存上），已停止。说明写明原因。
  case failed(String)

  init?(_ progress: EpisodeTrialProgress) {
    guard case .concluded(let ending) = progress else { return nil }
    self = ending
  }

  var progress: EpisodeTrialProgress { .concluded(self) }

  /// 单集面板里的完整说明。
  var message: String {
    switch self {
    case .cancelled: "已取消试看，可以重新试看"
    case .noEligibleResource: "没有找到符合试看规则的资源，可以在设置里调整试看订阅规则后重新试看"
    case .searchIncomplete(let message), .lostTrack(let message), .failed(let message): message
    case .organizationFailed: "下载完成了，但 MoviePilot 整理失败，可以在整理记录里查看原因"
    case .removedElsewhere: "试看订阅在别处被删除了，可以重新试看"
    case .modifiedElsewhere: "试看订阅已在别处修改，不再自动处理"
    }
  }

  /// 卡片正中的短字。用户自己取消是预期的结果，卡片上不提示，为 nil。
  var shortLabel: String? {
    switch self {
    case .cancelled: nil
    case .noEligibleResource: "没找到资源"
    case .searchIncomplete: "搜索失败"
    case .organizationFailed: "整理失败"
    case .lostTrack: "无法跟踪"
    case .removedElsewhere: "订阅已删"
    case .modifiedElsewhere: "订阅已改"
    case .failed: "试看失败"
    }
  }

  /// 不是这次试看出了问题，是别处处理了这条订阅：卡片上用提示图标，不用警告。
  var isHandledElsewhere: Bool {
    switch self {
    case .removedElsewhere, .modifiedElsewhere: true
    default: false
    }
  }
}

/// 按账号保存的一集的结局。`key` 与 `EpisodeTrialRequest.key` 相同。
nonisolated struct EpisodeTrialStoredEnding: Codable, Equatable, Sendable {
  let key: String
  let ending: EpisodeTrialEnding
  let endedAt: Date
}

/// 证明服务器上某条订阅是本机为试看建的。只在 TV 核对后删掉了它、读到订阅列表里已经没有它，
/// 或者发现它在别处被改过时消失。下载和入库的跟踪不在这里，只在内存里。
nonisolated struct EpisodeTrialCredential: Codable, Equatable, Sendable {
  /// 创建前生成并保存。同一季重试沿用同一个标记，不论哪次请求落了库，订阅上都是它。
  let marker: String
  var target: EpisodeTrialTarget
  let owner: String
  /// 拿到回执、或在订阅列表里按标记认出后补上。
  var subscriptionID: Int?
  /// 写入试看规则后这条订阅的指纹。为空表示还是拒绝所有资源的占位，按 `include` 核对。
  /// 先记本机写入的样子，写入后没读回来时下次也认得出；读回来与写入的不一致时再记上读回的样子，
  /// 收尾时认得出这是自己写过的订阅，核对后删掉。
  var fingerprints: Set<String> = []
  /// 补搜回执给的批次；回执丢了从订阅行的手动搜索状态补。
  var batchID: String?
  /// 用户要求取消。发出停止请求之前就保存，App 中途退出后接着收尾。
  var cancelRequested = false
  /// 重试也不会变的失败的说明。记下后不再推进，只停掉搜索、核对后删掉订阅，结局显示这段说明。
  var failure: String?
}

nonisolated enum EpisodeTrialTemporarySubscription {
  static let markerPrefix = "tv-episode-trial-"
  static let blockedInclude = "(?!)"

  static func makeMarker(at date: Date) -> String {
    "\(markerPrefix)\(Int(date.timeIntervalSince1970))-\(UUID().uuidString.lowercased())"
  }

  static func hasMarker(_ row: Subscribe) -> Bool {
    row.filter?.hasPrefix(markerPrefix) == true
  }

  /// 订阅是否还是凭据对应的那一条，并且没被别处改过：占位阶段仍拒绝所有资源；写过规则后仍暂停，
  /// 且 Web 能编辑的字段和本机记下的样子一致。
  static func isUntouched(_ row: Subscribe, by credential: EpisodeTrialCredential) -> Bool {
    let target = credential.target
    guard row.id == credential.subscriptionID, row.filter == credential.marker, row.username == credential.owner,
      row.type == "电视剧", row.identity.map(target.identities.contains) == true, row.season == target.season,
      trimmedNonEmpty([row.episode_group]) == target.episodeGroup
    else { return false }
    // 占位阶段只凭「仍拒绝所有资源」认定没被改过：创建后 MoviePilot 会补默认值，读回之前不知道占位的样子，
    // 记指纹也挡不住读回前的改动。别处只改了其他字段时 TV 仍会接管并删掉，这种订阅本来下载不了任何资源。
    if row.include == blockedInclude { return true }
    guard row.state == "S", let current = try? fingerprint(row) else { return false }
    return credential.fingerprints.contains(current)
  }

  /// Web 编辑框能改的字段的指纹（媒体身份另外核对）。名称、年份由 MoviePilot 定时按媒体信息刷新，不算在内，
  /// 否则 TV 会把自己的订阅当成被别处改过。后端会整理的几处先统一：空文本当作没填，站点去重排序，空列表当作没填。
  static func fingerprint(_ row: Subscribe) throws -> String {
    struct Settings: Encodable {
      let type: String
      let season, start, total, bestVersion, bestVersionFull, searchIMDb, searchInterval: Int?
      let minBitrate, minBitDepth, minSampleRate: Int?
      let sites: [Int]?
      let filterGroups: [String]?
      let texts: [String?]
    }
    let settings = Settings(
      type: row.type, season: row.season, start: row.start_episode, total: row.total_episode,
      bestVersion: row.best_version, bestVersionFull: row.best_version_full, searchIMDb: row.search_imdbid,
      searchInterval: row.search_interval, minBitrate: row.min_bitrate, minBitDepth: row.min_bit_depth,
      minSampleRate: row.min_sample_rate,
      sites: row.sites.flatMap { $0.isEmpty ? nil : Array(Set($0)).sorted() },
      filterGroups: row.filter_groups.flatMap { $0.isEmpty ? nil : $0 },
      texts: [
        row.keyword, row.quality, row.resolution, row.effect, row.include, row.exclude, row.custom_words,
        row.downloader, row.save_path, row.filter, row.episode_group, row.audio_quality, row.audio_format,
        // 分类路径由 MoviePilot 从稳定 ID 派生。
        specified(row.media_category_id) ?? row.media_category,
      ].map(specified))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Data(SHA256.hash(data: try encoder.encode(settings))).base64EncodedString()
  }

  /// 写入后读回的订阅是否保留了这次的季集锁定、普通订阅（不洗版）和试看规则。
  static func preservesSettings(of draft: Subscribe, in row: Subscribe) -> Bool {
    (try? fingerprint(draft)) == (try? fingerprint(row))
  }
}

/// 试看订阅固定是普通订阅，试看规则里不提供改成洗版。洗版订阅在 MoviePilot 上固定完整搜索，要把所有站点的所有页翻完
/// 才挑资源下载；普通订阅按用户设的搜索策略（默认智能，各站第一页到齐就先提交）。普通订阅提交下载后，MoviePilot
/// 会自己把订阅标成完成并删掉（记一条订阅历史、发完成通知），试看服务按下载记录接着跟踪。
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
  let best_version = 0
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
  var submittedCount: Int { download_counts["submitted"] ?? 0 }

  static func isValidID(_ id: String) -> Bool {
    id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
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
  /// 整理后的位置（只有整理记录有）：叫媒体服务器入库时按它找媒体库。
  let location: TransferredFileLocation

  private enum CodingKeys: String, CodingKey {
    case id, title, media_source, media_id, seasons, episodes, episode_group, download_hash, downloader, status
    case note, dest, dest_fileitem, category
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
    let fileItem = (try? values.decodeIfPresent(MoviePilotFileItem.self, forKey: .dest_fileitem)) ?? nil
    let dest = (try? values.decodeIfPresent(String.self, forKey: .dest)) ?? nil
    location = TransferredFileLocation(
      path: trimmedNonEmpty([fileItem?.path, dest]),
      category: trimmedNonEmpty([(try? values.decodeIfPresent(String.self, forKey: .category)) ?? nil]))
  }

  var subscriptionID: Int? { note?.subscription_download?.subscription_id }

  func matches(_ request: EpisodeTrialRequest) -> Bool {
    matches(
      identities: request.knownIdentities, season: request.season, episodeGroup: request.episodeGroup,
      episode: request.episodeNumber)
  }

  func matches(_ target: EpisodeTrialTarget) -> Bool {
    matches(
      identities: target.identities, season: target.season, episodeGroup: target.episodeGroup,
      episode: target.episodeNumber)
  }

  private func matches(identities: Set<MediaIdentity>, season: Int, episodeGroup: String?, episode: Int) -> Bool {
    guard let identity = MediaIdentifier.resolve(source: media_source, mediaId: media_id),
      identities.contains(identity),
      trimmedNonEmpty([episode_group]) == episodeGroup,
      seasons.map({ Self.contains(season, in: $0, prefix: "S", single: true) }) == true,
      episodes.map({ Self.contains(episode, in: $0, prefix: "E", single: false) }) == true
    else { return false }
    return true
  }

  /// 有一段格式不对就整条不认。
  private static func contains(_ number: Int, in value: String, prefix: String, single: Bool) -> Bool {
    EpisodeNumberText.ranges(in: value, prefix: prefix, single: single)?.contains { $0.contains(number) } == true
  }
}

nonisolated extension Subscribe {
  /// 带试看标记：不论是本机还是别的设备建的。订阅面板据此不把它当成自己刚建的订阅回滚。
  /// 是不是本机正在试看的订阅，要问 `EpisodeTrialService.trialState(of:)`。
  var hasEpisodeTrialMarker: Bool { EpisodeTrialTemporarySubscription.hasMarker(self) }

  /// 试看的是哪一季哪一集，例如「第 2 季第 5 集」，订阅卡上代替集数进度显示。
  var episodeTrialTargetText: String? {
    guard hasEpisodeTrialMarker, let episode = start_episode, episode > 0 else { return nil }
    return season.map { "第 \($0) 季第 \(episode) 集" } ?? "第 \(episode) 集"
  }
}

/// 本机正在试看的订阅处在哪一步，订阅卡片和季订阅页据此显示。
nonisolated enum EpisodeTrialState: Equatable, Hashable, Sendable {
  case active
  case cancelling
}

/// 本机试看凭据里决定订阅卡片和季订阅页显示的部分：哪条订阅、带哪个标记、是否在取消。
/// 只随认领、取消和了结变化，写指纹、记批次和刷新进度时不变，页面据此跟随而不必观察整个试看服务。
nonisolated struct EpisodeTrialHold: Hashable, Sendable {
  let subscriptionID: Int
  let marker: String
  let state: EpisodeTrialState

  static func holds(in credentials: [EpisodeTrialCredential]) -> Set<EpisodeTrialHold> {
    Set(credentials.compactMap { credential in
      credential.subscriptionID.map {
        EpisodeTrialHold(
          subscriptionID: $0, marker: credential.marker, state: credential.cancelRequested ? .cancelling : .active)
      }
    })
  }

  /// 这条订阅是不是本机正在试看的订阅。别的设备留下的、带标记的订阅不算，按普通订阅处理。
  static func state(of subscribe: Subscribe, in holds: Set<EpisodeTrialHold>) -> EpisodeTrialState? {
    guard let id = subscribe.id, let marker = subscribe.filter else { return nil }
    return holds.first { $0.subscriptionID == id && $0.marker == marker }?.state
  }
}

/// 取消试看的结果。`pending` 表示已经请求停止，等搜索结束后由服务在后台删掉订阅。
nonisolated enum EpisodeTrialCancelOutcome: Equatable, Sendable {
  case done
  case pending
  case failed
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
  static let cancellingTitle = "正在取消试看"
  static let cancellingMessage = "等这次搜索停下来后会自动删除试看订阅，之后这一季就能正常订阅。"
  static let cancelTitle = "取消试看"
  static let cancelAndSubscribeTitle = "取消试看，继续订阅"
  static let backTitle = "返回"
  static let cancelFailure = "暂时无法取消试看，请稍后重试。"
  static let cancelPending = "正在取消试看，搜索停下来后会自动完成。"

  /// 提示框出现在哪里：管理这条试看订阅（首页订阅卡、季订阅页），或想订阅被试看占着的这一季（订阅面板）。
  enum Context {
    case manage
    case subscribe
  }

  static func title(isCancelling: Bool) -> String { isCancelling ? cancellingTitle : title }

  static func cancelButtonTitle(for context: Context) -> String {
    switch context {
    case .manage: cancelTitle
    case .subscribe: cancelAndSubscribeTitle
    }
  }

  /// 已在取消时只说明进度；能取消（管理员）时说明取消的后果，不能取消时说明要等试看结束。
  static func message(for context: Context, isCancelling: Bool, canCancel: Bool) -> String {
    if isCancelling { return cancellingMessage }
    switch context {
    case .manage: return canCancel ? manageMessage : infoMessage
    case .subscribe: return canCancel ? subscribeMessage : waitMessage
    }
  }
}

/// 试看的这一集入库后的提示。用户多半已经离开详情页，看不到进度，所以用全局提示告诉他可以播放了。
nonisolated enum EpisodeTrialReadyNotice {
  static let messageKey = "message"

  static func message(for target: EpisodeTrialTarget) -> String {
    let title = target.title.map { "《\($0)》" } ?? "试看的剧集"
    return "\(title)第 \(target.season) 季第 \(target.episodeNumber) 集已入库，可以播放了。"
  }
}
