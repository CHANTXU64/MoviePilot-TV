import Foundation

// 详情页集列表里一集的入口：能不能播、试看到哪一步，决定卡片上显示什么、按下做什么、长按菜单和单集面板里有哪些操作。
// 只在应用内播放可用时（管理员、后端版本支持、设置里没关、有能播放的服务器）才有播放和试看；否则只能看单集简介。

/// 试看服务里和这一集有关的部分，卡片和单集面板据此显示。卡片不刷新进度，只读服务已有的结果。
nonisolated struct EpisodeTrialSnapshot: Equatable, Sendable {
  /// 本次运行里查到的进度；没有时用保存的结局。
  var progress: EpisodeTrialProgress?
  /// 本机这一集的试看订阅（已确认的）。
  var subscriptionID: Int?
  /// 试看订阅已经删掉（MoviePilot 提交下载后自己删的），服务还在跟这一集的下载、整理和入库。
  var isFollowingDownload = false
  var isCancelRequested = false
  /// 同一季另一集正在本机试看时，那一集的集号。MoviePilot 按季合并订阅，这时不能试看这一集。
  var otherEpisodeInSeason: Int?
  /// 刚按下「试看」、服务还没给出结果（要先查下载、订阅和媒体库，再建订阅、补搜，可能要几秒）。
  var isStarting = false

  init(
    progress: EpisodeTrialProgress? = nil, subscriptionID: Int? = nil, isFollowingDownload: Bool = false,
    isCancelRequested: Bool = false, otherEpisodeInSeason: Int? = nil, isStarting: Bool = false
  ) {
    self.progress = progress
    self.subscriptionID = subscriptionID
    self.isFollowingDownload = isFollowingDownload
    self.isCancelRequested = isCancelRequested
    self.otherEpisodeInSeason = otherEpisodeInSeason
    self.isStarting = isStarting
  }

  /// `followedDownloads` 是服务正在跟下载的集（试看键），见 `EpisodeTrialService.followedDownloads`。
  init(
    key: String, seasonKey: String, progress: [String: EpisodeTrialProgress], endings: [EpisodeTrialStoredEnding],
    credentials: [EpisodeTrialCredential], followedDownloads: Set<String> = []
  ) {
    self.progress = progress[key] ?? endings.last(where: { $0.key == key })?.ending.progress
    let own = credentials.first { $0.target.episodeKey == key && $0.subscriptionID != nil }
    subscriptionID = own?.subscriptionID
    isFollowingDownload = followedDownloads.contains(key)
    isCancelRequested = own?.cancelRequested == true
    otherEpisodeInSeason = credentials.first {
      $0.target.seasonKey == seasonKey && $0.target.episodeKey != key
    }?.target.episodeNumber
  }

  /// 服务还在跟这一集：有本机的试看订阅，或订阅删掉后还在跟下载。
  var isTracked: Bool { subscriptionID != nil || isFollowingDownload }

  /// 发出了创建试看订阅的请求但没收到回执，订阅列表里也没找到：MoviePilot 可能没收到。服务不为它轮询，
  /// 等用户再按「试看」（沿用同一个标记，订阅已经落库时认回那一条，不会建出两条）。
  var isSubmissionUnconfirmed: Bool { !isStarting && progress == .submissionUnconfirmed && !isTracked }

  /// 本机这一集的试看还在进行。正在发起也算；服务还在跟这一集、进度却还没写（App 刚启动）或这次没查成
  /// （稍后接着查）时也算，不能因为一次查询失败就不显示试看中。创建没确认、服务也没在跟的不算，可以重新发起。
  var isInProgress: Bool {
    if isStarting { return true }
    if isSubmissionUnconfirmed { return false }
    if let progress, progress.isInProgress { return true }
    switch progress {
    case nil, .notStarted, .unavailable: return isTracked
    default: return false
    }
  }
}

/// 为什么不能为这一集发起试看。
nonisolated enum EpisodeTrialBlock: Equatable, Sendable {
  /// 不是管理员、后端版本不支持，或缺少 TMDB 单集 ID、集号：不提试看。
  case unsupported
  /// 还没播出，搜不到资源。
  case notAired(String)
}

nonisolated struct EpisodeEntry: Equatable, Sendable {
  /// 应用内播放查到的结果；没有应用内播放或还没查到时为 nil。
  let availability: EpisodeAvailability?
  /// 应用内播放可用、正在查这一集能不能播。
  let isCheckingAvailability: Bool
  let trial: EpisodeTrialSnapshot
  /// 不能发起试看的原因；nil 表示条件都满足。
  let trialBlock: EpisodeTrialBlock?
  /// 能不能取消试看（管理员）。
  let canCancelTrial: Bool
  let allowsSeasonDateOffset: Bool

  init(
    availability: EpisodeAvailability?, isCheckingAvailability: Bool = false,
    trial: EpisodeTrialSnapshot = EpisodeTrialSnapshot(), trialBlock: EpisodeTrialBlock? = .unsupported,
    canCancelTrial: Bool = false, allowsSeasonDateOffset: Bool = false
  ) {
    self.availability = availability
    self.isCheckingAvailability = isCheckingAvailability
    self.trial = trial
    self.trialBlock = trialBlock
    self.canCancelTrial = canCancelTrial
    self.allowsSeasonDateOffset = allowsSeasonDateOffset
  }

  // MARK: 播放

  /// 确定能播的服务器：查到确定能播，或试看的这一集已经入库、而且确定是这一集。
  var playableServer: String? {
    if case .playable(let server) = availability { return server }
    if case .ready(let server, nil) = trial.progress { return server }
    return nil
  }

  /// 确定能播：按下直接播。
  var isPlayable: Bool { playableServer != nil }

  /// 只按季号集号找到了文件（可能不是这一集）：能播，但要先在面板里说明。确定能播时为 nil。
  var uncertainMatch: (server: String, match: UncertainEpisodeMatch)? {
    guard playableServer == nil else { return nil }
    if case .uncertain(let server, let match) = availability { return (server, match) }
    if case .ready(let server, let match?) = trial.progress { return (server, match) }
    return nil
  }

  /// 卡片上显示播放角标、面板里有「播放」：确定能播，或按季号集号找到了文件。
  var offersPlayback: Bool { isPlayable || uncertainMatch != nil }

  /// 在单集面板按「播放」「仍要播放」时给起播的许可：按此刻面板显示的说明。
  var panelPlaybackAcceptance: EpisodeMatchAcceptance {
    guard let uncertain = uncertainMatch else { return .confirmedOnly }
    return uncertain.match.identityConflict ? .identityConflicts : .numberMatches
  }

  /// 遥控器播放键在不能播的集上提示的原因；能播（含按季号集号找到了文件）时为 nil。
  var notPlayableMessage: String? {
    guard !offersPlayback else { return nil }
    if isCheckingAvailability { return "正在检查这一集能不能播放" }
    if trial.isInProgress {
      if trial.isStarting { return "正在发起试看，入库后才能播放" }
      if trial.isCancelRequested || trial.progress == .cancelling { return "正在取消试看" }
      return Self.inProgressMessage(trial)
    }
    return availability?.message ?? EpisodeAvailability.notOnServerMessage
  }

  // MARK: 试看

  /// 同一季另一集在试看、已有这一季的订阅时不能试看，原因在面板里说明。
  private var isSeasonOccupied: Bool {
    if trial.otherEpisodeInSeason != nil { return true }
    switch trial.progress {
    case .seasonTrialInProgress, .waitingForSubscription, .subscriptionPaused: return true
    default: return false
    }
  }

  /// 可以发起（或重新发起）试看：媒体服务器上确认没有，或没找到、只是有认不出是哪一集的文件（面板里先说明）；
  /// 条件都满足、这一集和这一季都没在试看。
  var canStartTrial: Bool {
    trialBlock == nil && availability?.allowsTrial == true && !trial.isInProgress && !isSeasonOccupied
  }

  /// 有认不出或没核对成的文件、这一集可能已经在里面时，面板里先说的结论和原因。
  private var possiblyPresentNote: StatusText? {
    switch availability {
    case .unmatched, .unverified: availability?.statusText
    default: nil
    }
  }

  /// 可以取消的试看订阅；没在试看、已在取消或不能取消时为 nil。
  var cancellableSubscriptionID: Int? {
    guard canCancelTrial, !trial.isCancelRequested, trial.progress != .cancelling else { return nil }
    return trial.subscriptionID
  }

  /// 已经结束、要提示用户的试看结局；用户自己取消的不算。
  private var stoppedEnding: EpisodeTrialEnding? {
    guard case .concluded(let ending) = trial.progress, ending.shortLabel != nil else { return nil }
    return ending
  }

  // MARK: 卡片

  /// 卡片上的状态。能播放的放在角上（已入库的剧可能整季都能播，不能每张都大大地标），只按季号集号找到的也一样；
  /// 试看进行中和试看结局放在剧照正中；个别集没法对应时在角上提示。读取失败通常整季都一样，在行头提示一次。
  enum CardStatus: Equatable, Sendable {
    case playable
    case trialInProgress(TrialIndicator)
    case trialStopped(EpisodeTrialEnding)
    case attention
  }

  /// 试看进行中卡片上显示的内容：`label` 是一行短字，`fraction` 是下载进度（0–1），拿不到时转圈。
  struct TrialIndicator: Equatable, Sendable {
    let label: String
    let fraction: Double?
    let stage: EpisodeTrialStage?
  }

  var cardStatus: CardStatus? {
    if offersPlayback { return .playable }
    if trial.isInProgress, let indicator = Self.trialIndicator(trial) { return .trialInProgress(indicator) }
    if let stoppedEnding { return .trialStopped(stoppedEnding) }
    switch availability {
    case .unmatched, .unverified, .unidentifiable: return .attention
    default: return nil
    }
  }

  static func trialIndicator(_ trial: EpisodeTrialSnapshot) -> TrialIndicator? {
    if trial.isStarting { return TrialIndicator(label: "正在发起试看", fraction: nil, stage: nil) }
    if trial.isCancelRequested { return TrialIndicator(label: "正在取消试看", fraction: nil, stage: nil) }
    switch trial.progress {
    case .searching: return TrialIndicator(label: "搜索资源中", fraction: nil, stage: .search)
    case .downloading(let progress, let remaining):
      let fraction = progress.map { min(max($0 / 100, 0), 1) }
      // 写「下载还需」：剩余时间只算下载，下完还要整理和入库。
      let label = remaining.map { "下载还需\(EpisodeTrialDownloadETA.text(seconds: $0))" } ?? "下载中"
      return TrialIndicator(label: label, fraction: fraction, stage: .download)
    case .waitingForOrganization: return TrialIndicator(label: "等待整理", fraction: nil, stage: .organize)
    case .organizing: return TrialIndicator(label: "整理中", fraction: nil, stage: .organize)
    case .waitingForLibrary: return TrialIndicator(label: "等待入库", fraction: nil, stage: .library)
    case .cancelling: return TrialIndicator(label: "正在取消试看", fraction: nil, stage: nil)
    case .submissionUnconfirmed: return TrialIndicator(label: "正在确认进度", fraction: nil, stage: nil)
    case nil, .notStarted, .unavailable:
      return trial.isTracked ? TrialIndicator(label: "试看中", fraction: nil, stage: nil) : nil
    default: return nil
    }
  }

  /// 读屏读到的状态，跟在单集信息后面。
  var accessibilityStatus: String? {
    switch cardStatus {
    case .playable: return isPlayable ? "可以播放" : "可以播放，可能不是这一集"
    case .trialInProgress(let indicator):
      let percent = indicator.fraction.map { "，\(Int(($0 * 100).rounded()))%" } ?? ""
      return "试看中，\(indicator.label)\(percent)"
    case .trialStopped(let ending): return "试看结束，\(ending.message)"
    case .attention: return availability?.message
    case nil: return nil
    }
  }

  // MARK: 按下与长按

  enum PrimaryAction: Equatable, Sendable {
    case play
    case openPanel
  }

  /// 按下卡片：确定能播就直接播，否则打开单集面板（只按季号集号找到的，先在面板里说明再播）。
  var primaryAction: PrimaryAction { isPlayable ? .play : .openPanel }

  enum PlayPauseAction: Equatable, Sendable {
    case play
    case openPanel
    /// 不能播，提示原因
    case explain(String)
  }

  /// 遥控器播放键：确定能播就播；只按季号集号找到的打开面板；不能播时说明原因。
  var playPauseAction: PlayPauseAction? {
    if isPlayable { return .play }
    if uncertainMatch != nil { return .openPanel }
    return notPlayableMessage.map(PlayPauseAction.explain)
  }

  enum MenuAction: Equatable, Sendable {
    case play
    case startTrial
    case cancelTrial(subscriptionID: Int)
    case details
  }

  /// 长按菜单：只列现在能做的，最后是详情。菜单里的操作单集面板里都有。
  /// 只按季号集号找到的集不放「播放」、有认不出是哪一集的文件时不放「试看」：要先看面板里的说明，从「详情」进去。
  var menuActions: [MenuAction] {
    var actions: [MenuAction] = []
    if isPlayable {
      actions.append(.play)
    } else if trial.isInProgress, let id = cancellableSubscriptionID {
      actions.append(.cancelTrial(subscriptionID: id))
    } else if canStartTrial, possiblyPresentNote == nil {
      actions.append(.startTrial)
    }
    actions.append(.details)
    return actions
  }

  // MARK: 单集面板

  enum PanelButton: Equatable, Sendable {
    case play
    /// `isRetry` 时按钮写「重新试看」：上一次试看已经结束或没发起成功。
    case startTrial(isRetry: Bool)
    case cancelTrial(subscriptionID: Int)
    /// 重新查这一集能不能播。
    case recheck
  }

  struct Panel: Equatable, Sendable {
    /// 结论前的状态图标。
    enum Tone: Equatable, Sendable {
      case ready
      /// 可能不是这一集、这一集可能已经入库、检查失败：按下去之前要先看说明。
      case caution
      case working
      case info
    }

    let tone: Tone
    /// 一句结论；nil 时面板只有简介（没有应用内播放）。
    let headline: String?
    /// 原因或下一步。
    let detail: String?
    let buttons: [PanelButton]
    /// 说明里提醒了风险（可能不是这一集、这一集可能已经入库）：按钮写「仍要播放」「仍要试看」。
    let proceedsDespiteWarning: Bool

    init(
      _ tone: Tone, _ headline: String?, _ detail: String? = nil, buttons: [PanelButton],
      proceedsDespiteWarning: Bool = false
    ) {
      self.tone = tone
      self.headline = headline
      self.detail = detail
      self.buttons = buttons
      self.proceedsDespiteWarning = proceedsDespiteWarning
    }

    init(_ tone: Tone, _ text: StatusText, buttons: [PanelButton], proceedsDespiteWarning: Bool = false) {
      self.init(tone, text.headline, text.detail, buttons: buttons, proceedsDespiteWarning: proceedsDespiteWarning)
    }

    /// 拼成一句的说明（读屏、测试用）。
    var message: String? { headline.map { StatusText(headline: $0, detail: detail).joined } }
  }

  var panel: Panel {
    if let server = playableServer {
      return Panel(.ready, "可以播放", "在“\(server)”上", buttons: [.play])
    }
    if let uncertain = uncertainMatch {
      let text = uncertain.match.statusText(server: uncertain.server, allowsSeasonDateOffset: allowsSeasonDateOffset)
      let detail = trial.progress?.isReady == true ? "试看的这一集已经入库。" + (text.detail ?? "") : text.detail
      // 服务器上没有资料的，刷新元数据后要能在这里重新检查。
      let buttons: [PanelButton] = uncertain.match.serverHasNoMetadata ? [.play, .recheck] : [.play]
      return Panel(.caution, text.headline, detail, buttons: buttons, proceedsDespiteWarning: true)
    }
    if trial.isStarting {
      // 按「试看」后面板就关了，进度看卡片；发起期间再打开时留着「试看」按钮（显示加载中），
      // 结果到了同一个位置换成「取消试看」，焦点不跳。
      return Panel(.working, "正在发起试看", buttons: [.startTrial(isRetry: false)])
    }
    if trial.isInProgress {
      let buttons: [PanelButton] = cancellableSubscriptionID.map { [.cancelTrial(subscriptionID: $0)] } ?? []
      return Panel(.working, "试看中", Self.inProgressMessage(trial), buttons: buttons)
    }
    // 有认不出或没核对成的文件：结论是这一集可能已经入库，原因后面接上这一步的说明，保留「重新检查」。
    let unidentified = possiblyPresentNote
    func explained(_ tone: Panel.Tone, _ headline: String, _ detail: String?, _ buttons: [PanelButton]) -> Panel {
      guard let note = unidentified else { return Panel(tone, headline, detail, buttons: buttons) }
      let combined = [note.detail, detail].compactMap { $0 }.joined(separator: "。")
      return Panel(
        .caution, note.headline, combined.isEmpty ? nil : combined, buttons: buttons + [.recheck],
        proceedsDespiteWarning: true)
    }
    let retry: [PanelButton] = canStartTrial ? [.startTrial(isRetry: true)] : []
    if case .concluded(let ending) = trial.progress {
      return explained(.info, "试看结束", ending.message, retry)
    }
    if isCheckingAvailability {
      return Panel(.working, "正在检查", buttons: [])
    }
    guard let availability else {
      // 没有应用内播放：只看简介。
      return Panel(.info, nil, buttons: [])
    }
    switch availability {
    case .playable, .uncertain:
      return Panel(.ready, nil, buttons: [.play])
    case .failed, .unidentifiable:
      // 读取失败、这一集缺编号：都不能确认服务器上没有，不提供试看。
      return Panel(.caution, availability.statusText ?? StatusText(headline: "检查失败"), buttons: [.recheck])
    case .checking:
      // 正在核对：核对完自动更新，不用重试。
      return Panel(.working, availability.statusText ?? StatusText(headline: "正在核对"), buttons: [])
    case .notOnServer, .unmatched, .unverified:
      break
    }
    if let other = trial.otherEpisodeInSeason {
      return explained(.info, "暂时不能试看", "这一季的第 \(other) 集正在试看，结束后才能试看这一集", [])
    }
    switch trial.progress {
    case .seasonTrialInProgress, .waitingForSubscription, .subscriptionPaused:
      let text = Self.seasonOccupiedText(trial.progress)
      return explained(.info, text.headline, text.detail, [])
    case .unavailable(let message):
      return explained(.caution, "没能发起试看", message, retry)
    case .submissionUnconfirmed:
      return explained(.caution, "没能确认试看已发起", Self.unconfirmedSubmissionMessage, retry)
    default:
      break
    }
    switch trialBlock {
    case .notAired(let date):
      let aired = "这一集 \(date) 播出，播出后才能试看"
      return unidentified == nil
        ? Panel(.info, EpisodeAvailability.notOnServerMessage, aired, buttons: []) : explained(.info, "", aired, [])
    case .unsupported:
      if let unidentified { return Panel(.caution, unidentified, buttons: [.recheck]) }
      return Panel(.info, availability.statusText ?? StatusText(headline: EpisodeAvailability.notOnServerMessage), buttons: [])
    case nil:
      // 可能已经入库时只说原因，按钮「仍要试看」已经够清楚。
      return explained(
        .info, EpisodeAvailability.notOnServerMessage, unidentified == nil ? Self.trialDescription : nil,
        [.startTrial(isRetry: false)])
    }
  }

  /// 这一季已有订阅或另一集在试看时面板里的说明。
  private static func seasonOccupiedText(_ result: EpisodeTrialProgress?) -> StatusText {
    switch result {
    case .waitingForSubscription: StatusText(headline: "这一季已经有订阅", detail: "等订阅下载这一集")
    case .subscriptionPaused: StatusText(headline: "这一季已经有订阅", detail: "订阅已暂停，不会下载这一集")
    default: StatusText(headline: "暂时不能试看", detail: "这一季的另一集正在试看，结束后才能试看这一集")
    }
  }

  /// 试看进行中面板里的一句话：现在到了哪一步，后面还要经过什么才能播。第一次用的人多半以为下完就能播。
  static func inProgressMessage(_ trial: EpisodeTrialSnapshot) -> String {
    if trial.isCancelRequested || trial.progress == .cancelling { return EpisodeTrialHoldNotice.cancellingMessage }
    switch trial.progress {
    case .searching:
      return "正在搜索资源，找到后还要下载、整理和入库才能播放"
    case .downloading(_, let remaining):
      let percent = trialIndicator(trial)?.fraction.map { " \(Int(($0 * 100).rounded()))%" } ?? ""
      let eta = remaining.map { "，还需\(EpisodeTrialDownloadETA.text(seconds: $0))" } ?? ""
      return "正在下载\(percent)\(eta)，下完还要整理和入库才能播放"
    case .waitingForOrganization:
      return "下载器里已经看不到这个任务，多半已经下完，在等 MoviePilot 整理"
    case .organizing:
      return "MoviePilot 正在整理，整理完还要入库才能播放"
    case .waitingForLibrary:
      return "已经整理好，在等媒体服务器入库"
    case .submissionUnconfirmed:
      return "暂时没确认试看到了哪一步，稍后会再查"
    case .unavailable(let reason):
      return reason
    default:
      return "这一集正在试看，入库后才能播放"
    }
  }

  /// 发起试看的结果在卡片上看不出来时（没发起成功、这一季已有订阅或另一集在试看）给用户的说明；看得出来时为 nil。
  static func startFeedback(_ result: EpisodeTrialProgress?) -> String? {
    switch result {
    case .unavailable(let message): message
    case .seasonTrialInProgress: "这一季的另一集正在试看，结束后才能试看这一集"
    case .waitingForSubscription: "这一季已经有订阅，等订阅下载这一集"
    case .subscriptionPaused: "这一季已经有订阅，但订阅已暂停"
    default: nil
    }
  }

  /// 创建试看订阅没确认（见 `EpisodeTrialSnapshot.isSubmissionUnconfirmed`）时面板里和按下「试看」后的说明。
  static let unconfirmedSubmissionMessage = "没能确认 MoviePilot 收到了试看请求，可以重新试看，不会重复创建订阅"

  static let trialDescription = "试看下载的文件会留在媒体库里"

  // MARK: 播出日期

  /// 播出日期晚于今天的集还没播出，不提供试看。没有日期或格式认不出时按已播出处理。
  /// 日期是 TMDB 的 `yyyy-MM-dd`，按本机所在时区的今天比较。
  static func notAiredDate(_ airDate: String?, today: String = todayString()) -> String? {
    guard let date = trimmedNonEmpty([airDate]), isISODate(date), isISODate(today), date > today else { return nil }
    return date
  }

  static func todayString(now: Date = Date(), timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  private static func isISODate(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return false }
    return bytes.enumerated().allSatisfy { index, byte in
      index == 4 || index == 7 || (48...57).contains(byte)
    }
  }
}
