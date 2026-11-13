import XCTest

@testable import MoviePilot_TV

/// 详情页每集的入口：卡片状态、按下与长按、单集面板。纯逻辑，不涉及界面和网络。
final class EpisodeEntryTests: XCTestCase {
  private func trial(
    _ progress: EpisodeTrialProgress? = nil, subscriptionID: Int? = nil, followingDownload: Bool = false,
    cancelRequested: Bool = false, otherEpisode: Int? = nil, starting: Bool = false
  ) -> EpisodeTrialSnapshot {
    EpisodeTrialSnapshot(
      progress: progress, subscriptionID: subscriptionID, isFollowingDownload: followingDownload,
      isCancelRequested: cancelRequested, otherEpisodeInSeason: otherEpisode, isStarting: starting)
  }

  private func entry(
    _ availability: EpisodeAvailability?, trial: EpisodeTrialSnapshot = EpisodeTrialSnapshot(),
    block: EpisodeTrialBlock? = nil, canCancel: Bool = true, checking: Bool = false
  ) -> EpisodeEntry {
    EpisodeEntry(
      availability: availability, isCheckingAvailability: checking, trial: trial, trialBlock: block,
      canCancelTrial: canCancel)
  }

  // MARK: 按下与长按

  func testPlayableEpisodePlaysOnSelectAndOffersPlayInTheMenu() {
    let playable = entry(.playable(server: "客厅"))
    XCTAssertEqual(playable.primaryAction, .play)
    XCTAssertEqual(playable.menuActions, [.play, .details])
    XCTAssertEqual(playable.cardStatus, .playable)
    XCTAssertNil(playable.notPlayableMessage)
    XCTAssertEqual(playable.panel.buttons, [.play])
    XCTAssertEqual(playable.panel.message, "在“客厅”上可以播放")
  }

  func testEpisodeNotOnServerOpensThePanelAndOffersTrial() {
    let missing = entry(.notOnServer)
    XCTAssertEqual(missing.primaryAction, .openPanel)
    XCTAssertEqual(missing.menuActions, [.startTrial, .details])
    XCTAssertNil(missing.cardStatus, "不在库是常态，卡片上不标")
    XCTAssertEqual(missing.panel.buttons, [.startTrial(isRetry: false)])
    XCTAssertEqual(missing.panel.message, "媒体服务器上没有这一集。试看会下载这一集，下好的文件会留在媒体库里")
    XCTAssertEqual(missing.notPlayableMessage, EpisodeAvailability.notOnServerMessage)
  }

  func testTrialIsNotOfferedWhenTheServerCouldNotBeChecked() {
    for availability in [EpisodeAvailability.failed("连不上“客厅”"), .unidentifiable(.missingEpisodeID)] {
      let unsure = entry(availability)
      XCTAssertFalse(unsure.canStartTrial, "\(availability)")
      XCTAssertEqual(unsure.menuActions, [.details], "\(availability)")
      XCTAssertEqual(unsure.panel.buttons, [.recheck], "\(availability)")
      XCTAssertEqual(unsure.panel.message, availability.message, "\(availability)")
    }
    XCTAssertNil(entry(.failed("连不上")).cardStatus, "读取失败在行头提示一次，不盖在每张卡上")
    XCTAssertEqual(entry(.unidentifiable(.missingEpisodeID)).cardStatus, .attention)
  }

  // MARK: 有认不出是哪一集的文件

  func testUnidentifiedFilesOnTheServerStillAllowATrialAfterExplainingInThePanel() {
    // 服务器上有文件认不出是哪一集，这一集可能就在里面：角上照样提示，但不把这一集挡住；
    // 先在面板里说明再给「试看」，长按菜单不放，免得绕过说明。
    let unmatched = entry(.unmatched(server: "客厅"))
    XCTAssertEqual(unmatched.cardStatus, .attention)
    XCTAssertTrue(unmatched.canStartTrial)
    XCTAssertEqual(unmatched.primaryAction, .openPanel)
    XCTAssertEqual(unmatched.menuActions, [.details])
    XCTAssertEqual(unmatched.panel.buttons, [.startTrial(isRetry: false), .recheck])
    XCTAssertEqual(
      unmatched.panel.message,
      "媒体服务器“客厅”上有文件认不出是哪一集，这一集可能已经在里面。试看会下载这一集，下好的文件会留在媒体库里")
    XCTAssertEqual(unmatched.notPlayableMessage, EpisodeAvailability.unmatchedMessage(server: "客厅"))
    XCTAssertEqual(unmatched.accessibilityStatus, EpisodeAvailability.unmatchedMessage(server: "客厅"))
  }

  func testUnidentifiedFilesKeepTheExplanationWhateverTheTrialState() {
    let note = "媒体服务器“客厅”上有文件认不出是哪一集，这一集可能已经在里面"
    let unaired = entry(.unmatched(server: "客厅"), block: .notAired("2099-01-01"))
    XCTAssertEqual(unaired.panel.message, note + "。这一集 2099-01-01 播出，播出后才能试看")
    XCTAssertEqual(unaired.panel.buttons, [.recheck])

    let blocked = entry(.unmatched(server: "客厅"), trial: trial(otherEpisode: 3))
    XCTAssertEqual(blocked.panel.message, note + "。这一季的第 3 集正在试看，结束后才能试看这一集")
    XCTAssertEqual(blocked.panel.buttons, [.recheck])

    let failed = entry(.unmatched(server: "客厅"), trial: trial(.unavailable("MoviePilot 拒绝创建试看订阅")))
    XCTAssertEqual(failed.panel.message, note + "。MoviePilot 拒绝创建试看订阅")
    XCTAssertEqual(failed.panel.buttons, [.startTrial(isRetry: true), .recheck])

    let ended = entry(.unmatched(server: "客厅"), trial: trial(.concluded(.noEligibleResource)))
    XCTAssertEqual(
      ended.panel.message, note + "。没有找到符合试看规则的资源，可以在设置里调整试看订阅规则后重新试看",
      "上一次试看结束了，重新试看前也要先说明")
    XCTAssertEqual(ended.panel.buttons, [.startTrial(isRetry: true), .recheck])
    XCTAssertEqual(ended.menuActions, [.details])

    let unsupported = entry(.unmatched(server: "客厅"), block: .unsupported)
    XCTAssertFalse(unsupported.canStartTrial)
    XCTAssertEqual(unsupported.panel.message, EpisodeAvailability.unmatchedMessage(server: "客厅"))
    XCTAssertEqual(unsupported.panel.buttons, [.recheck])
  }

  func testUnsupportedOrUnairedEpisodesDoNotOfferTrial() {
    let unsupported = entry(.notOnServer, block: .unsupported)
    XCTAssertEqual(unsupported.menuActions, [.details])
    XCTAssertEqual(unsupported.panel.buttons, [])
    XCTAssertEqual(unsupported.panel.message, EpisodeAvailability.notOnServerMessage)

    let unaired = entry(.notOnServer, block: .notAired("2099-01-01"))
    XCTAssertEqual(unaired.menuActions, [.details])
    XCTAssertEqual(unaired.panel.buttons, [])
    XCTAssertEqual(unaired.panel.message, "媒体服务器上没有这一集。这一集 2099-01-01 播出，播出后才能试看")
  }

  func testWithoutInAppPlaybackThePanelOnlyShowsTheOverview() {
    let none = entry(nil, block: .unsupported)
    XCTAssertEqual(none.primaryAction, .openPanel)
    XCTAssertNil(none.panel.message)
    XCTAssertEqual(none.panel.buttons, [])
    XCTAssertNil(none.cardStatus)
  }

  func testCheckingAvailabilityIsExplainedOnPlayPause() {
    let checking = entry(nil, checking: true)
    XCTAssertEqual(checking.notPlayableMessage, "正在检查这一集能不能播放")
    XCTAssertEqual(checking.panel.message, "正在检查这一集能不能播放")
    XCTAssertEqual(checking.panel.buttons, [])
  }

  // MARK: 试看进行中

  func testTrialInProgressShowsTheStageOnTheCardAndInThePanel() {
    let downloading = entry(.notOnServer, trial: trial(.downloading(progress: 42), subscriptionID: 81))
    XCTAssertEqual(
      downloading.cardStatus,
      .trialInProgress(EpisodeEntry.TrialIndicator(label: "下载中", fraction: 0.42, stage: .download)))
    XCTAssertEqual(downloading.menuActions, [.cancelTrial(subscriptionID: 81), .details])
    XCTAssertEqual(downloading.panel.buttons, [.cancelTrial(subscriptionID: 81)])
    XCTAssertEqual(downloading.panel.message, "正在下载 42%，下完还要整理和入库才能播放")
    XCTAssertFalse(downloading.canStartTrial)
    XCTAssertEqual(downloading.accessibilityStatus, "试看中，下载中，42%")
    XCTAssertEqual(downloading.notPlayableMessage, "正在下载 42%，下完还要整理和入库才能播放", "按播放键时说明还要多久、还差哪几步")
  }

  func testThePanelSaysWhatIsLeftSoDownloadedIsNotMistakenForPlayable() {
    // 面板不列整个流程，只写现在这一步，和后面还要经过什么才能播。
    let searching = entry(.notOnServer, trial: trial(.searching, subscriptionID: 81))
    XCTAssertEqual(searching.panel.message, "正在搜索资源，找到后还要下载、整理和入库才能播放")

    let unknownProgress = entry(.notOnServer, trial: trial(.downloading(progress: nil)))
    XCTAssertEqual(unknownProgress.panel.message, "正在下载，下完还要整理和入库才能播放")

    let waiting = entry(.notOnServer, trial: trial(.waitingForOrganization, subscriptionID: 81))
    XCTAssertEqual(
      waiting.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "等待整理", fraction: nil, stage: .organize)))
    XCTAssertEqual(waiting.panel.message, "下载器里已经看不到这个任务，多半已经下完，在等 MoviePilot 整理")

    let organizing = entry(.notOnServer, trial: trial(.organizing))
    XCTAssertEqual(organizing.panel.message, "MoviePilot 正在整理，整理完还要入库才能播放")

    let library = entry(.notOnServer, trial: trial(.waitingForLibrary))
    XCTAssertEqual(library.panel.message, "已经整理好，在等媒体服务器入库")
    XCTAssertEqual(library.panel.buttons, [], "订阅已删、只在跟下载时没有可取消的")
  }

  func testCardLabelsSayWhichStepTheTrialIsAt() {
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.searching))?.label, "搜索资源中")
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.submissionUnconfirmed))?.label, "正在确认进度")
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.cancelling))?.label, "正在取消试看")
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.downloading(progress: 42)))?.label, "下载中", "没有速度时不估时间")
  }

  func testDownloadShowsHowLongTheDownloadStillTakes() {
    let downloading = entry(.notOnServer, trial: trial(.downloading(progress: 42, remainingSeconds: 725), subscriptionID: 81))
    XCTAssertEqual(
      downloading.cardStatus,
      .trialInProgress(EpisodeEntry.TrialIndicator(label: "下载还需约 13 分钟", fraction: 0.42, stage: .download)),
      "写明是下载还要多久，不是还要多久能播")
    XCTAssertEqual(downloading.panel.message, "正在下载 42%，还需约 13 分钟，下完还要整理和入库才能播放")
    XCTAssertEqual(downloading.accessibilityStatus, "试看中，下载还需约 13 分钟，42%")
  }

  func testRemainingTimeComesFromTheAverageSpeedSinceTheDownloadWasFirstSeen() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let eta = EpisodeTrialDownloadETA(since: start, startProgress: 40)
    // 60 秒下了 10%，还剩 50%：约 300 秒。
    XCTAssertEqual(eta.remainingSeconds(progress: 50, now: start.addingTimeInterval(60)), 300)
    XCTAssertNil(eta.remainingSeconds(progress: 45, now: start.addingTimeInterval(20)), "刚开始样本太少，先不估")
    XCTAssertNil(eta.remainingSeconds(progress: 40, now: start.addingTimeInterval(120)), "这段时间进度没动，估不出来")
    XCTAssertNil(eta.remainingSeconds(progress: 100, now: start.addingTimeInterval(120)), "已经下完")
  }

  func testRemainingTimeIsRoundedUpToMinutes() {
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 0), "不到 1 分钟")
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 59), "不到 1 分钟")
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 60), "约 1 分钟")
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 725), "约 13 分钟", "按分钟向上取整")
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 3600), "约 1 小时")
    XCTAssertEqual(EpisodeTrialDownloadETA.text(seconds: 3723), "约 1 小时 3 分钟")
  }

  func testDownloadProgressIsClampedToTheRing() {
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.downloading(progress: 140)))?.fraction, 1)
    XCTAssertEqual(EpisodeEntry.trialIndicator(trial(.downloading(progress: -5)))?.fraction, 0)
    XCTAssertNil(EpisodeEntry.trialIndicator(trial(.downloading(progress: nil)))?.fraction, "拿不到进度时转圈")
  }

  func testTrialSubscriptionWithoutProgressYetCountsAsInProgress() {
    // App 刚启动，后台对账还没写进度，只有本机的试看订阅。
    let restored = entry(.notOnServer, trial: trial(subscriptionID: 81))
    XCTAssertEqual(
      restored.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "试看中", fraction: nil, stage: nil)))
    XCTAssertEqual(restored.menuActions, [.cancelTrial(subscriptionID: 81), .details])
  }

  func testAQueryFailureWhileOnlyFollowingTheDownloadKeepsShowingTheTrialInProgress() {
    // MoviePilot 提交下载后删了试看订阅，服务只在跟下载；这次没查成，照样显示试看中、不提供重新试看。
    let following = entry(
      .notOnServer, trial: trial(.unavailable("暂时无法确认试看进度"), followingDownload: true))
    XCTAssertEqual(
      following.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "试看中", fraction: nil, stage: nil)))
    XCTAssertFalse(following.canStartTrial)
    XCTAssertEqual(following.menuActions, [.details])
    XCTAssertEqual(following.panel.message, "暂时无法确认试看进度")
    XCTAssertEqual(following.panel.buttons, [], "订阅已经删了，没有可取消的")
  }

  func testATransientQueryFailureKeepsShowingTheTrialInProgress() {
    // 后台对账这次没查成（比如订阅刚被改过、稍后再核对），本机的试看订阅还在，照样显示试看中。
    let retrying = entry(
      .notOnServer, trial: trial(.unavailable("试看订阅的配置刚刚有变化，稍后再核对"), subscriptionID: 81))
    XCTAssertEqual(
      retrying.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "试看中", fraction: nil, stage: nil)))
    XCTAssertEqual(retrying.panel.message, "试看订阅的配置刚刚有变化，稍后再核对")
    XCTAssertEqual(retrying.panel.buttons, [.cancelTrial(subscriptionID: 81)])
    XCTAssertFalse(retrying.canStartTrial)
  }

  func testEndedTrialWhoseSubscriptionIsStillBeingRemovedOffersNoCancel() {
    // 永久失败已经有了结局，删除订阅还没成功、后台接着收尾：不再提供取消。
    let cleaning = entry(.notOnServer, trial: trial(.concluded(.failed("集数对不上")), subscriptionID: 81))
    XCTAssertEqual(cleaning.cardStatus, .trialStopped(.failed("集数对不上")))
    XCTAssertFalse(cleaning.menuActions.contains(.cancelTrial(subscriptionID: 81)))
  }

  func testStartingKeepsTheTrialButtonInPlaceUntilTheResultArrives() {
    let starting = entry(.notOnServer, trial: trial(starting: true))
    XCTAssertEqual(starting.panel.buttons, [.startTrial(isRetry: false)], "按钮留在原位显示加载中")
    XCTAssertEqual(starting.menuActions, [.details], "发起中不能再发起")
    XCTAssertEqual(
      starting.cardStatus,
      .trialInProgress(EpisodeEntry.TrialIndicator(label: "正在发起试看", fraction: nil, stage: nil)))
    XCTAssertEqual(starting.notPlayableMessage, "正在发起试看，入库后才能播放")
  }

  func testCancellingIsShownAndCannotBeCancelledAgain() {
    let cancelling = entry(.notOnServer, trial: trial(.searching, subscriptionID: 81, cancelRequested: true))
    XCTAssertEqual(
      cancelling.cardStatus,
      .trialInProgress(EpisodeEntry.TrialIndicator(label: "正在取消试看", fraction: nil, stage: nil)))
    XCTAssertEqual(cancelling.notPlayableMessage, "正在取消试看")
    XCTAssertEqual(cancelling.menuActions, [.details])
    XCTAssertEqual(cancelling.panel.message, EpisodeTrialHoldNotice.cancellingMessage)
    XCTAssertEqual(cancelling.panel.buttons, [])
  }

  func testNonAdminCannotCancel() {
    let watching = entry(.notOnServer, trial: trial(.searching, subscriptionID: 81), canCancel: false)
    XCTAssertEqual(watching.menuActions, [.details])
    XCTAssertEqual(watching.panel.buttons, [])
  }

  func testReadyTrialIsPlayableEvenBeforeAvailabilityIsRechecked() {
    let ready = entry(.notOnServer, trial: trial(.ready(server: "客厅")))
    XCTAssertEqual(ready.primaryAction, .play)
    XCTAssertEqual(ready.cardStatus, .playable)
    XCTAssertEqual(ready.panel.buttons, [.play])
  }

  // MARK: 只按季号集号找到的

  private let numberMatch = UncertainEpisodeMatch(season: 1, episode: 5, episodeGroup: nil, airDate: .matches)

  func testNumberMatchShowsThePlayBadgeButExplainsBeforePlaying() {
    let uncertain = entry(.uncertain(server: "客厅", match: numberMatch))
    XCTAssertEqual(uncertain.cardStatus, .playable, "卡片上照样是播放角标")
    XCTAssertEqual(uncertain.primaryAction, .openPanel, "按下先看说明")
    XCTAssertEqual(uncertain.playPauseAction, .openPanel, "播放键也先看说明")
    XCTAssertEqual(uncertain.menuActions, [.details], "长按不能绕过说明直接播")
    XCTAssertFalse(uncertain.canStartTrial)
    XCTAssertNil(uncertain.notPlayableMessage)
    XCTAssertEqual(uncertain.accessibilityStatus, "可以播放，可能不是这一集")
    XCTAssertEqual(uncertain.panel.buttons, [.play])
    XCTAssertEqual(
      uncertain.panel.message,
      "“客厅”上的文件没有 TMDB 编号，也对不上 MoviePilot 的整理记录，是按季号集号找到的第 1 季第 5 集，"
        + "播出日期也对得上，但仍可能不是这一集。按季号集号算这一集已经在媒体服务器上，所以不提供试看")
    XCTAssertEqual(
      entry(.uncertain(server: "客厅", match: numberMatch), block: .unsupported).panel.message,
      numberMatch.message(server: "客厅"), "本来就不能试看时不提试看")
    XCTAssertEqual(entry(.playable(server: "客厅")).playPauseAction, .play)
    XCTAssertEqual(entry(.notOnServer).playPauseAction, .explain(EpisodeAvailability.notOnServerMessage))
  }

  func testTrialThatLandsAsANumberMatchSaysItMayNotBeThisEpisode() {
    let ready = entry(.notOnServer, trial: trial(.ready(server: "客厅", uncertain: numberMatch)))
    XCTAssertFalse(ready.isPlayable)
    XCTAssertEqual(ready.primaryAction, .openPanel)
    XCTAssertEqual(ready.cardStatus, .playable)
    XCTAssertEqual(ready.panel.buttons, [.play])
    XCTAssertEqual(ready.panel.message, "试看的这一集已经整理入库。" + numberMatch.message(server: "客厅"))
  }

  // MARK: 试看结局

  func testEndingsAreShownInTheMiddleOfTheCardExceptTheUsersOwnCancel() {
    let noResource = entry(.notOnServer, trial: trial(.concluded(.noEligibleResource)))
    XCTAssertEqual(noResource.cardStatus, .trialStopped(.noEligibleResource))
    XCTAssertEqual(noResource.menuActions, [.startTrial, .details], "结束后可以重新试看")
    XCTAssertEqual(noResource.panel.buttons, [.startTrial(isRetry: true)])
    XCTAssertEqual(noResource.panel.message, EpisodeTrialEnding.noEligibleResource.message)

    let organize = entry(.notOnServer, trial: trial(.concluded(.organizationFailed)))
    XCTAssertEqual(organize.panel.message, EpisodeTrialEnding.organizationFailed.message)

    let cancelled = entry(.notOnServer, trial: trial(.concluded(.cancelled)))
    XCTAssertNil(cancelled.cardStatus, "用户自己取消是预期的结果，卡片上不提示")
    XCTAssertEqual(cancelled.panel.message, "已取消试看，可以重新试看")
    XCTAssertEqual(cancelled.panel.buttons, [.startTrial(isRetry: true)])
  }

  func testEachEndingHasItsOwnShortLabel() {
    let labels: [(EpisodeTrialEnding, String?)] = [
      (.cancelled, nil), (.noEligibleResource, "没找到资源"), (.searchIncomplete("跳过"), "搜索失败"),
      (.organizationFailed, "整理失败"), (.lostTrack("找不到"), "无法跟踪"), (.removedElsewhere, "订阅已删"),
      (.modifiedElsewhere, "订阅已改"), (.failed("集数对不上"), "试看失败"),
    ]
    for (ending, label) in labels {
      XCTAssertEqual(ending.shortLabel, label, "\(ending)")
      XCTAssertEqual(EpisodeTrialEnding(.concluded(ending)), ending)
    }
    XCTAssertTrue(EpisodeTrialEnding.removedElsewhere.isHandledElsewhere)
    XCTAssertFalse(EpisodeTrialEnding.noEligibleResource.isHandledElsewhere)
    XCTAssertNil(EpisodeTrialEnding(.unavailable("暂时无法确认试看进度")), "不是结局的不保存")
  }

  // MARK: 同一季

  func testAnotherEpisodeOnTrialInTheSameSeasonBlocksThisOne() {
    let blocked = entry(.notOnServer, trial: trial(otherEpisode: 3))
    XCTAssertFalse(blocked.canStartTrial)
    XCTAssertEqual(blocked.menuActions, [.details])
    XCTAssertEqual(blocked.panel.message, "这一季的第 3 集正在试看，结束后才能试看这一集")
    XCTAssertEqual(blocked.panel.buttons, [])

    let subscribed = entry(.notOnServer, trial: trial(.waitingForSubscription))
    XCTAssertFalse(subscribed.canStartTrial)
    XCTAssertEqual(subscribed.panel.message, "这一季已经有订阅，等订阅下载这一集")
  }

  func testStartFeedbackOnlyCoversResultsTheCardCannotShow() {
    XCTAssertEqual(EpisodeEntry.startFeedback(.unavailable("MoviePilot 拒绝创建试看订阅")), "MoviePilot 拒绝创建试看订阅")
    XCTAssertEqual(EpisodeEntry.startFeedback(.subscriptionPaused), "这一季已经有订阅，但订阅已暂停")
    XCTAssertNil(EpisodeEntry.startFeedback(.searching))
    XCTAssertNil(EpisodeEntry.startFeedback(.concluded(.noEligibleResource)))
  }

  // MARK: 试看服务里的状态

  func testSnapshotReadsProgressThenStoredEndingAndTheSeasonsOtherTrial() {
    let target = EpisodeTrialTarget(
      identity: MediaIdentity(source: "themoviedb", mediaId: "91"), tmdbID: 91, season: 2, episodeGroup: nil,
      seasonKey: "91|2|", episodeKey: "91|2||233|3", episodeNumber: 3, title: "试看测试")
    let credential = EpisodeTrialCredential(marker: "m", target: target, owner: "admin", subscriptionID: 81)
    let ending = EpisodeTrialStoredEnding(key: "91|2||235|5", ending: .noEligibleResource, endedAt: Date())

    let own = EpisodeTrialSnapshot(
      key: "91|2||233|3", seasonKey: "91|2|", progress: [:], endings: [ending], credentials: [credential])
    XCTAssertEqual(own.subscriptionID, 81)
    XCTAssertNil(own.otherEpisodeInSeason)
    XCTAssertTrue(own.isInProgress)

    let other = EpisodeTrialSnapshot(
      key: "91|2||235|5", seasonKey: "91|2|", progress: [:], endings: [ending], credentials: [credential])
    XCTAssertEqual(other.progress, .concluded(.noEligibleResource), "没有进度时用保存的结局")
    XCTAssertEqual(other.otherEpisodeInSeason, 3)
    XCTAssertNil(other.subscriptionID)

    let refreshed = EpisodeTrialSnapshot(
      key: "91|2||235|5", seasonKey: "91|2|", progress: ["91|2||235|5": .searching], endings: [ending],
      credentials: [])
    XCTAssertEqual(refreshed.progress, .searching, "本次运行查到的进度优先")
  }

  func testTrialKeyForCardsMatchesTheRequestKey() throws {
    let media = MediaInfo(tmdb_id: 91, source: "themoviedb", media_id: "91", title: "试看测试", type: "电视剧")
    let episode = MoviePilotEpisode(TmdbEpisode(id: 233, episodeNumber: 3), season: 2, index: 2)
    let request = try XCTUnwrap(EpisodeTrialRequest(media: media, episode: episode, episodeGroup: "g1"))
    XCTAssertEqual(EpisodeTrialRequest.key(tmdbID: 91, episode: episode, episodeGroup: "g1"), request.key)
    XCTAssertEqual(EpisodeTrialRequest.key(tmdbID: 91, episode: episode, episodeGroup: " "), "91|2||233|3")
    XCTAssertNil(
      EpisodeTrialRequest.key(
        tmdbID: 91, episode: MoviePilotEpisode(TmdbEpisode(id: nil, episodeNumber: 3), season: 2, index: 2),
        episodeGroup: nil),
      "缺 TMDB 单集 ID 时不能试看")
  }

  // MARK: 播出日期

  func testUnairedEpisodesAreDetectedByDate() {
    XCTAssertEqual(EpisodeEntry.notAiredDate("2026-11-13", today: "2026-11-12"), "2026-11-13")
    XCTAssertNil(EpisodeEntry.notAiredDate("2026-11-12", today: "2026-11-12"), "当天播出的照常试看")
    XCTAssertNil(EpisodeEntry.notAiredDate("2026-11-01", today: "2026-11-12"))
    XCTAssertNil(EpisodeEntry.notAiredDate(nil, today: "2026-11-12"), "没有日期按已播出")
    XCTAssertNil(EpisodeEntry.notAiredDate("2026-1-3", today: "2026-11-12"), "认不出的格式按已播出")
    XCTAssertNil(EpisodeEntry.notAiredDate("明天", today: "2026-11-12"))
  }

  func testTodayIsInTheGivenTimeZone() {
    let instant = Date(timeIntervalSince1970: 1_794_441_600)  // 2026-11-12 00:00 UTC
    XCTAssertEqual(EpisodeEntry.todayString(now: instant, timeZone: TimeZone(identifier: "UTC")!), "2026-11-12")
    XCTAssertEqual(
      EpisodeEntry.todayString(now: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-11-11")
  }
}
