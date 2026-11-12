import Foundation

// 详情页集列表里一集的入口：能不能播、试看到哪一步，决定卡片上显示什么、按下做什么、长按菜单和单集面板里有哪些操作。
// 只在应用内播放可用时（管理员、后端版本支持、设置里没关、有能播放的服务器）才有播放和试看；否则只能看单集简介。

/// 试看服务里和这一集有关的部分，卡片和单集面板据此显示。卡片不刷新进度，只读服务已有的结果。
nonisolated struct EpisodeTrialSnapshot: Equatable, Sendable {
  /// 本次运行里查到的进度；没有时用保存的结局。
  var progress: EpisodeTrialProgress?
  /// 本机这一集的试看订阅（已确认的）。
  var subscriptionID: Int?
  var isCancelRequested = false
  /// 同一季另一集正在本机试看时，那一集的集号。MoviePilot 按季合并订阅，这时不能试看这一集。
  var otherEpisodeInSeason: Int?
  /// 刚按下「试看」、服务还没给出结果（要先查下载、订阅和媒体库，再建订阅、补搜，可能要几秒）。
  var isStarting = false

  init(
    progress: EpisodeTrialProgress? = nil, subscriptionID: Int? = nil, isCancelRequested: Bool = false,
    otherEpisodeInSeason: Int? = nil, isStarting: Bool = false
  ) {
    self.progress = progress
    self.subscriptionID = subscriptionID
    self.isCancelRequested = isCancelRequested
    self.otherEpisodeInSeason = otherEpisodeInSeason
    self.isStarting = isStarting
  }

  init(
    key: String, seasonKey: String, progress: [String: EpisodeTrialProgress], endings: [EpisodeTrialStoredEnding],
    credentials: [EpisodeTrialCredential]
  ) {
    self.progress = progress[key] ?? endings.last(where: { $0.key == key })?.ending.progress
    let own = credentials.first { $0.target.episodeKey == key && $0.subscriptionID != nil }
    subscriptionID = own?.subscriptionID
    isCancelRequested = own?.cancelRequested == true
    otherEpisodeInSeason = credentials.first {
      $0.target.seasonKey == seasonKey && $0.target.episodeKey != key
    }?.target.episodeNumber
  }

  /// 本机这一集的试看还在进行。正在发起也算；有本机的试看订阅、进度却还没写（App 刚启动）或这次没查成
  /// （后台接着重试）时也算，不能因为一次查询失败就不显示试看中。
  var isInProgress: Bool {
    if isStarting { return true }
    if let progress, progress.isInProgress { return true }
    switch progress {
    case nil, .notStarted, .unavailable: return subscriptionID != nil
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

  init(
    availability: EpisodeAvailability?, isCheckingAvailability: Bool = false,
    trial: EpisodeTrialSnapshot = EpisodeTrialSnapshot(), trialBlock: EpisodeTrialBlock? = .unsupported,
    canCancelTrial: Bool = false
  ) {
    self.availability = availability
    self.isCheckingAvailability = isCheckingAvailability
    self.trial = trial
    self.trialBlock = trialBlock
    self.canCancelTrial = canCancelTrial
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

  /// 遥控器播放键在不能播的集上提示的原因；能播（含按季号集号找到了文件）时为 nil。
  var notPlayableMessage: String? {
    guard !offersPlayback else { return nil }
    if isCheckingAvailability { return "正在检查这一集能不能播放" }
    if trial.isInProgress, let indicator = Self.trialIndicator(trial) {
      return "这一集正在试看（\(indicator.label)），入库后才能播放"
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

  /// 可以发起（或重新发起）试看：媒体服务器上确认没有、条件都满足、这一集和这一季都没在试看。
  var canStartTrial: Bool {
    trialBlock == nil && availability == .notOnServer && !trial.isInProgress && !isSeasonOccupied
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

  /// 试看进行中显示的内容。`fraction` 是下载进度（0–1），拿不到时转圈。
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
    case .unmatched, .unidentifiable: return .attention
    default: return nil
    }
  }

  static func trialIndicator(_ trial: EpisodeTrialSnapshot) -> TrialIndicator? {
    if trial.isStarting { return TrialIndicator(label: "正在发起", fraction: nil, stage: nil) }
    if trial.isCancelRequested { return TrialIndicator(label: "正在取消", fraction: nil, stage: nil) }
    switch trial.progress {
    case .searching: return TrialIndicator(label: "搜索资源", fraction: nil, stage: .search)
    case .downloading(let progress):
      let fraction = progress.map { min(max($0 / 100, 0), 1) }
      return TrialIndicator(label: "下载中", fraction: fraction, stage: .download)
    case .waitingForOrganization: return TrialIndicator(label: "等待整理", fraction: nil, stage: .organize)
    case .organizing: return TrialIndicator(label: "整理中", fraction: nil, stage: .organize)
    case .waitingForLibrary: return TrialIndicator(label: "等待入库", fraction: nil, stage: .library)
    case .cancelling: return TrialIndicator(label: "正在取消", fraction: nil, stage: nil)
    case .submissionUnconfirmed: return TrialIndicator(label: "确认中", fraction: nil, stage: nil)
    case nil, .notStarted, .unavailable:
      return trial.subscriptionID == nil ? nil : TrialIndicator(label: "试看中", fraction: nil, stage: nil)
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
  /// 只按季号集号找到的集不放「播放」：要先看面板里的说明，从「详情」进去播。
  var menuActions: [MenuAction] {
    var actions: [MenuAction] = []
    if isPlayable {
      actions.append(.play)
    } else if trial.isInProgress, let id = cancellableSubscriptionID {
      actions.append(.cancelTrial(subscriptionID: id))
    } else if canStartTrial {
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

  enum StepState: Equatable, Sendable {
    case done, current, pending, failed
  }

  struct Panel: Equatable, Sendable {
    /// 状态说明；nil 时面板只有简介（没有应用内播放）。
    let message: String?
    let isWorking: Bool
    /// 试看的几步；不涉及试看时为空。
    let steps: [Step]
    let buttons: [PanelButton]

    struct Step: Equatable, Sendable {
      let stage: EpisodeTrialStage
      let state: StepState
    }
  }

  var panel: Panel {
    if let server = playableServer {
      return Panel(message: "在“\(server)”上可以播放", isWorking: false, steps: [], buttons: [.play])
    }
    if let uncertain = uncertainMatch {
      var message = uncertain.match.message(server: uncertain.server)
      if trial.progress?.isReady == true {
        message = "试看的这一集已经整理入库。" + message
      } else if trialBlock == nil {
        message += "。按季号集号算这一集已经在媒体服务器上，所以不提供试看"
      }
      return Panel(message: message, isWorking: false, steps: [], buttons: [.play])
    }
    if trial.isStarting {
      // 发起期间留着「试看」按钮（显示加载中），结果到了同一个位置换成「取消试看」，焦点不跳。
      return Panel(
        message: "正在发起试看", isWorking: true, steps: Self.steps(current: nil, failedAt: nil),
        buttons: [.startTrial(isRetry: false)])
    }
    if trial.isInProgress {
      let indicator = Self.trialIndicator(trial)
      let message: String
      if trial.isCancelRequested || trial.progress == .cancelling {
        message = EpisodeTrialHoldNotice.cancellingMessage
      } else if trial.progress == .submissionUnconfirmed {
        message = "暂时没确认试看到了哪一步，稍后会再查"
      } else if trial.progress == .waitingForOrganization {
        message = "下载器里已经看不到这个任务，多半已经下完，等 MoviePilot 整理"
      } else if case .unavailable(let reason) = trial.progress {
        message = reason
      } else if let stage = indicator?.stage {
        message = stage.detail
      } else {
        message = "这一集正在试看"
      }
      let buttons: [PanelButton] = cancellableSubscriptionID.map { [.cancelTrial(subscriptionID: $0)] } ?? []
      return Panel(
        message: message, isWorking: true, steps: Self.steps(current: indicator?.stage, failedAt: nil),
        buttons: buttons)
    }
    let retry: [PanelButton] = canStartTrial ? [.startTrial(isRetry: true)] : []
    if case .concluded(let ending) = trial.progress {
      let failedAt = ending.stoppedStage
      return Panel(
        message: ending.message, isWorking: false,
        steps: failedAt == nil ? [] : Self.steps(current: nil, failedAt: failedAt), buttons: retry)
    }
    if isCheckingAvailability {
      return Panel(message: "正在检查这一集能不能播放", isWorking: true, steps: [], buttons: [])
    }
    guard let availability else {
      // 没有应用内播放：只看简介。
      return Panel(message: nil, isWorking: false, steps: [], buttons: [])
    }
    switch availability {
    case .playable, .uncertain:
      return Panel(message: nil, isWorking: false, steps: [], buttons: [.play])
    case .failed, .unmatched, .unidentifiable:
      // 读取失败、个别文件没编号、没法按编号对应：都不能确认服务器上没有，不提供试看。
      return Panel(message: availability.message, isWorking: false, steps: [], buttons: [.recheck])
    case .notOnServer:
      break
    }
    if let other = trial.otherEpisodeInSeason {
      return Panel(
        message: "这一季的第 \(other) 集正在试看，结束后才能试看这一集", isWorking: false, steps: [], buttons: [])
    }
    switch trial.progress {
    case .seasonTrialInProgress, .waitingForSubscription, .subscriptionPaused:
      return Panel(message: Self.startFeedback(trial.progress), isWorking: false, steps: [], buttons: [])
    case .unavailable(let message):
      return Panel(message: message, isWorking: false, steps: [], buttons: retry)
    default:
      break
    }
    switch trialBlock {
    case .notAired(let date):
      return Panel(
        message: "媒体服务器上没有这一集。这一集 \(date) 播出，播出后才能试看", isWorking: false, steps: [], buttons: [])
    case .unsupported:
      return Panel(message: EpisodeAvailability.notOnServerMessage, isWorking: false, steps: [], buttons: [])
    case nil:
      return Panel(
        message: Self.trialIntroduction, isWorking: false, steps: Self.steps(current: nil, failedAt: nil),
        buttons: [.startTrial(isRetry: false)])
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

  static let trialIntroduction =
    "媒体服务器上没有这一集。试看会在 MoviePilot 建一条只针对这一集的临时订阅，搜索结束后自动删除订阅；下载的文件会留在媒体库里。"

  /// 试看的几步：当前这一步之前的算完成；`failedAt` 那一步停下，之前的算完成。都没有时全部未开始。
  static func steps(current: EpisodeTrialStage?, failedAt: EpisodeTrialStage?) -> [Panel.Step] {
    EpisodeTrialStage.allCases.map { stage in
      let state: StepState
      if let failedAt {
        state = stage < failedAt ? .done : stage == failedAt ? .failed : .pending
      } else if let current {
        state = stage < current ? .done : stage == current ? .current : .pending
      } else {
        state = .pending
      }
      return Panel.Step(stage: stage, state: state)
    }
  }

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

extension EpisodeTrialEnding {
  /// 试看停在了哪一步，面板据此标出失败的那一步；说不清时为 nil。
  nonisolated var stoppedStage: EpisodeTrialStage? {
    switch self {
    case .noEligibleResource, .searchIncomplete, .failed: .search
    case .organizationFailed: .organize
    case .cancelled, .lostTrack, .removedElsewhere, .modifiedElsewhere: nil
    }
  }
}
