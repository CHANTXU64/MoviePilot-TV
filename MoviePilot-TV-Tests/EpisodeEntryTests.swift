import XCTest

@testable import MoviePilot_TV

/// 详情页每集的入口：卡片状态、按下与长按、单集面板。纯逻辑，不涉及界面和网络。
final class EpisodeEntryTests: XCTestCase {
  private func trial(
    _ progress: EpisodeTrialProgress? = nil, subscriptionID: Int? = nil, cancelRequested: Bool = false,
    otherEpisode: Int? = nil, starting: Bool = false
  ) -> EpisodeTrialSnapshot {
    EpisodeTrialSnapshot(
      progress: progress, subscriptionID: subscriptionID, isCancelRequested: cancelRequested,
      otherEpisodeInSeason: otherEpisode, isStarting: starting)
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
    XCTAssertEqual(missing.panel.message, EpisodeEntry.trialIntroduction)
    XCTAssertEqual(missing.panel.steps.map(\.state), [.pending, .pending, .pending, .pending], "发起前先列出要经过的几步")
    XCTAssertEqual(missing.notPlayableMessage, EpisodeAvailability.notOnServerMessage)
  }

  func testTrialIsOnlyOfferedWhenTheServerConfirmsTheEpisodeIsMissing() {
    for availability in [
      EpisodeAvailability.failed("连不上“客厅”"), .unmatched(server: "客厅"), .unidentifiable(.missingEpisodeID),
    ] {
      let unsure = entry(availability)
      XCTAssertFalse(unsure.canStartTrial, "\(availability)")
      XCTAssertEqual(unsure.menuActions, [.details], "\(availability)")
      XCTAssertEqual(unsure.panel.buttons, [.recheck], "\(availability)")
      XCTAssertEqual(unsure.panel.message, availability.message, "\(availability)")
    }
    XCTAssertNil(entry(.failed("连不上")).cardStatus, "读取失败在行头提示一次，不盖在每张卡上")
    XCTAssertEqual(entry(.unmatched(server: "客厅")).cardStatus, .attention)
    XCTAssertEqual(entry(.unidentifiable(.missingEpisodeID)).cardStatus, .attention)
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
    XCTAssertEqual(downloading.panel.steps.map(\.state), [.done, .current, .pending, .pending])
    XCTAssertFalse(downloading.canStartTrial)
    XCTAssertEqual(downloading.accessibilityStatus, "试看中，下载中，42%")
    XCTAssertEqual(downloading.notPlayableMessage, "这一集正在试看（下载中），入库后才能播放")
  }

  func testTheStepsAfterDownloadAreShownSoDownloadedIsNotMistakenForPlayable() {
    let waiting = entry(.notOnServer, trial: trial(.waitingForOrganization, subscriptionID: 81))
    XCTAssertEqual(
      waiting.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "等待整理", fraction: nil, stage: .organize)))
    XCTAssertEqual(waiting.panel.steps.map(\.state), [.done, .done, .current, .pending])
    XCTAssertEqual(waiting.panel.message, "下载器里已经看不到这个任务，多半已经下完，等 MoviePilot 整理")

    let library = entry(.notOnServer, trial: trial(.waitingForLibrary))
    XCTAssertEqual(library.panel.steps.map(\.state), [.done, .done, .done, .current])
    XCTAssertEqual(library.panel.message, EpisodeTrialStage.library.detail)
    XCTAssertEqual(library.panel.buttons, [], "订阅已删、只在跟下载时没有可取消的")
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
      starting.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "正在发起", fraction: nil, stage: nil)))
  }

  func testCancellingIsShownAndCannotBeCancelledAgain() {
    let cancelling = entry(.notOnServer, trial: trial(.searching, subscriptionID: 81, cancelRequested: true))
    XCTAssertEqual(
      cancelling.cardStatus, .trialInProgress(EpisodeEntry.TrialIndicator(label: "正在取消", fraction: nil, stage: nil)))
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

  // MARK: 试看结局

  func testEndingsAreShownInTheMiddleOfTheCardExceptTheUsersOwnCancel() {
    let noResource = entry(.notOnServer, trial: trial(.concluded(.noEligibleResource)))
    XCTAssertEqual(noResource.cardStatus, .trialStopped(.noEligibleResource))
    XCTAssertEqual(noResource.menuActions, [.startTrial, .details], "结束后可以重新发起")
    XCTAssertEqual(noResource.panel.buttons, [.startTrial(isRetry: true)])
    XCTAssertEqual(noResource.panel.steps.map(\.state), [.failed, .pending, .pending, .pending])
    XCTAssertEqual(noResource.panel.message, EpisodeTrialEnding.noEligibleResource.message)

    let organize = entry(.notOnServer, trial: trial(.concluded(.organizationFailed)))
    XCTAssertEqual(organize.panel.steps.map(\.state), [.done, .done, .failed, .pending])

    let cancelled = entry(.notOnServer, trial: trial(.concluded(.cancelled)))
    XCTAssertNil(cancelled.cardStatus, "用户自己取消是预期的结果，卡片上不提示")
    XCTAssertEqual(cancelled.panel.message, "已取消试看，可以重新发起")
    XCTAssertEqual(cancelled.panel.buttons, [.startTrial(isRetry: true)])
  }

  func testEachEndingHasItsOwnShortLabel() {
    let labels: [(EpisodeTrialEnding, String?)] = [
      (.cancelled, nil), (.noEligibleResource, "无资源"), (.searchIncomplete("跳过"), "搜索失败"),
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
