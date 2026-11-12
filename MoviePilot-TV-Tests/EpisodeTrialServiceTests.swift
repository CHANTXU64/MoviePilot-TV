import Foundation
import XCTest

@testable import MoviePilot_TV

/// 试看服务按约定的端到端行为：只管本机凭据对应的订阅；取消以批次结束为准；查不到、查失败和远端结束分开处理。
/// 测试替身按 MoviePilot 的接口合同模拟：取消请求只让运行中的批次进入“停止中”，结束要由测试显式结算。
@MainActor
final class EpisodeTrialServiceTests: XCTestCase {
  override func setUp() async throws {
    FakeMoviePilot.shared.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(EpisodeTrialURLProtocol.self))
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(EpisodeTrialURLProtocol.self)
  }

  private var backend: FakeMoviePilot { FakeMoviePilot.shared }

  // MARK: - 发起

  func testTrialCreatesPausesWritesRuleAndSearchesOnlyThisEpisode() async throws {
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      XCTAssertEqual(backend.mutations, [
        "POST subscribe", "PUT subscribe/status/81", "PUT subscribe", "POST subscribe/search/81",
      ])
      let created = try XCTUnwrap(backend.created.first)
      XCTAssertEqual(created["include"] as? String, "(?!)", "创建时拒绝所有资源")
      XCTAssertEqual(created["start_episode"] as? Int, 5)
      XCTAssertEqual(created["total_episode"] as? Int, 6)
      let searched = try XCTUnwrap(backend.searched.first)
      XCTAssertEqual(searched["start_episode"] as? Int, 5)
      XCTAssertEqual(searched["total_episode"] as? Int, 5, "补搜前总集数锁到目标集")
      XCTAssertEqual(searched["state"] as? String, "S")
      XCTAssertEqual(searched["include"] as? String, "WEB")
      XCTAssertEqual(searched["quality"] as? String, "WEB-DL")
      XCTAssertEqual(searched["best_version"] as? Int, 1)
      XCTAssertEqual(searched["best_version_full"] as? Int, 0)
      XCTAssertEqual(service.credentials.count, 1)
      XCTAssertEqual(service.trialState(of: try XCTUnwrap(backend.subscribe(81))), .active)
    }
  }

  func testSearchWithoutDownloadDeletesTrialAndAllowsStartingAgain() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: false)
      let finished = await service.refresh(request)
      XCTAssertEqual(finished, .noEligibleResource)
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
      XCTAssertTrue(service.credentials.isEmpty)

      let again = await service.start(request)
      XCTAssertEqual(again, .searching)
      XCTAssertEqual(backend.mutations.filter { $0 == "POST subscribe" }.count, 2)
    }
  }

  func testUnfinishedSearchesExplainHowTheyEnded() async throws {
    for (state, expected) in [
      ("failed", EpisodeTrialProgress.unavailable("MoviePilot 没有完成本次试看搜索，可以重新发起")),
      ("skipped", .unavailable("MoviePilot 跳过了本次试看搜索，可以重新发起")),
    ] {
      backend.reset()
      try await withService { _, service, _, request in
        _ = await service.start(request)
        backend.settleBatch(state)
        let ended = await service.refresh(request)
        XCTAssertEqual(ended, expected, state)
        XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81", state)
      }
    }
  }

  func testSubmittedDownloadIsFollowedAfterTrialIsDeleted() async throws {
    let library = LibraryBox()
    try await withService(availability: { _, _ in library.value }) { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true)
      let downloading = await service.refresh(request)
      XCTAssertEqual(downloading, .downloading(progress: 42))
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81", "搜索结束就删订阅，不等入库")
      XCTAssertTrue(service.credentials.isEmpty)

      backend.moveToQueue("target-hash")
      let organizing = await service.refresh(request)
      XCTAssertEqual(organizing, .organizing)

      backend.organize("target-hash", succeeded: true)
      let organized = await service.refresh(request)
      XCTAssertEqual(organized, .waitingForLibrary)

      library.value = .playable(server: "测试媒体库")
      let ready = await service.refresh(request)
      XCTAssertEqual(ready, .ready(server: "测试媒体库"))
    }
  }

  func testOrganizationFailureEndsTheTrial() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true)
      _ = await service.refresh(request)
      backend.organize("target-hash", succeeded: false)
      let failed = await service.refresh(request)
      XCTAssertEqual(failed, .organizationFailed)

      let again = await service.start(request)
      XCTAssertEqual(again, .searching, "整理失败后可以重新发起")
    }
  }

  func testSubmittedDownloadWithoutRecordStopsTracking() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true, recordsHistory: false)
      let ended = await service.refresh(request)
      XCTAssertEqual(ended, EpisodeTrialService.untrackable)
    }
  }

  func testDownloadRecordBeyondTheFirstHistoryPageIsFound() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true)
      backend.pushHistoryToSecondPage()
      let downloading = await service.refresh(request)
      XCTAssertEqual(downloading, .downloading(progress: 42))
    }
  }

  func testDownloadBetweenDownloaderAndQueueKeepsBeingWatched() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true)
      _ = await service.refresh(request)
      backend.finishDownload("target-hash")
      let between = await service.refresh(request)
      XCTAssertEqual(between, .submissionUnconfirmed, "下载器只列出还在下载的任务，暂时三处都找不到")
      backend.moveToQueue("target-hash")
      let organizing = await service.refresh(request)
      XCTAssertEqual(organizing, .organizing)
    }
  }

  // MARK: - 别处已有的东西

  func testExistingSubscriptionIsShownAndNeverTouched() async throws {
    backend.addFormal(state: "S")
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .subscriptionPaused)
      XCTAssertEqual(backend.mutations, [])
    }
  }

  func testOtherDevicesTrialIsTreatedAsAnOrdinarySubscription() async throws {
    let other = backend.addFormal(state: "S", marker: EpisodeTrialTemporarySubscription.makeMarker(at: Date()))
    try await withService { _, service, _, request in
      XCTAssertNil(service.trialState(of: other), "没有本机凭据，不算试看中")
      let start = await service.start(request)
      XCTAssertEqual(start, .subscriptionPaused)
      XCTAssertEqual(backend.mutations, [], "别的设备的试看订阅不暂停、不删")
      let cancelled = await service.cancelTrial(subscriptionID: 70)
      XCTAssertEqual(cancelled, .failed)
    }
  }

  func testCreateReturningExistingSubscriptionLeavesItAlone() async throws {
    backend.returnExistingOnCreate(state: "R")
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .waitingForSubscription)
      XCTAssertEqual(backend.mutations, ["POST subscribe"], "拿回的已有订阅不暂停、不改、不补搜、不删")
      XCTAssertTrue(service.credentials.isEmpty)
    }
  }

  func testCreateOutcomeDoesNotDependOnMessageWording() async throws {
    backend.setCreateMessage("已添加订阅")
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
    }
  }

  func testEpisodeAlreadyDownloadingIsShownInsteadOfCreating() async throws {
    backend.addDownload(hash: "earlier-hash", progress: 30)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .downloading(progress: 30))
      XCTAssertFalse(backend.mutations.contains("POST subscribe"))
    }
  }

  func testUnreachableDownloaderBlocksNewTrialWhenDownloadIsNotFound() async throws {
    backend.addDownload(hash: "earlier-hash", progress: nil, offline: true)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, EpisodeTrialService.unconfirmedQuery)
      XCTAssertFalse(backend.mutations.contains("POST subscribe"))
    }
  }

  func testUnconfirmedLibraryBlocksNewTrial() async throws {
    try await withService(library: .failed("媒体服务器读取失败")) { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .unavailable("媒体服务器读取失败"))
      XCTAssertEqual(backend.mutations, [])
    }
  }

  // MARK: - 回执丢失与恢复

  func testLostCreateReceiptIsRecognizedByMarker() async throws {
    backend.loseCreateReceipt(afterStoring: true)
    try await withService { _, service, _, request in
      let lost = await service.start(request)
      XCTAssertEqual(lost, .submissionUnconfirmed)
      XCTAssertNil(service.credentials.first?.subscriptionID)

      let recovered = await service.start(request)
      XCTAssertEqual(recovered, .searching)
      XCTAssertEqual(backend.mutations.filter { $0 == "POST subscribe" }.count, 1, "按标记认出来，不再新建")
      XCTAssertEqual(service.credentials.first?.subscriptionID, 81)
    }
  }

  func testUndeliveredCreateIsSentAgainWithTheSameMarker() async throws {
    backend.loseCreateReceipt(afterStoring: false)
    try await withService { _, service, _, request in
      let lost = await service.start(request)
      XCTAssertEqual(lost, .submissionUnconfirmed)
      let marker = try XCTUnwrap(service.credentials.first?.marker)

      backend.loseCreateReceipt(afterStoring: nil)
      let again = await service.start(request)
      XCTAssertEqual(again, .searching)
      XCTAssertEqual(backend.created.compactMap { $0["filter"] as? String }, [marker, marker])
    }
  }

  func testUnconfirmedCreateIsNotPolled() async throws {
    backend.loseCreateReceipt(afterStoring: false)
    let sleeper = ScriptedSleeper()
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      _ = await service.start(request)
      let page = try await openPage(service, request)
      try await Task.sleep(for: .milliseconds(100))
      page.cancel()
      await page.value
      XCTAssertEqual(sleeper.delays, [], "创建没确认时不轮询")
      XCTAssertEqual(sleeper.driveCount, 0, "也不定时对账")
    }
  }

  func testDuplicatePlaceholderWithTheSameMarkerIsRemoved() async throws {
    backend.landCreateTwice()
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      XCTAssertTrue(backend.mutations.contains("DELETE subscribe/82"), "同标记的第二条占位删掉")
      XCTAssertNotNil(backend.subscribe(81))
    }
  }

  func testLostSearchReceiptIsRecoveredFromTheSubscription() async throws {
    backend.loseSearchReceipt(afterQueueing: true)
    try await withService { _, service, _, request in
      let lost = await service.start(request)
      XCTAssertEqual(lost, .searching)
      XCTAssertNil(service.credentials.first?.batchID)

      _ = await service.refresh(request)
      XCTAssertEqual(service.credentials.first?.batchID, FakeMoviePilot.batchID)
      XCTAssertEqual(backend.mutations.filter { $0 == "POST subscribe/search/81" }.count, 1, "不重复补搜")
    }
  }

  func testUndeliveredSearchIsSentAgain() async throws {
    backend.loseSearchReceipt(afterQueueing: false)
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.loseSearchReceipt(afterQueueing: nil)
      _ = await service.refresh(request)
      XCTAssertEqual(backend.mutations.filter { $0 == "POST subscribe/search/81" }.count, 2)
      XCTAssertEqual(service.credentials.first?.batchID, FakeMoviePilot.batchID)
    }
  }

  func testRejectedSearchDeletesTheTrial() async throws {
    backend.rejectSearch()
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .unavailable("MoviePilot 拒绝试看补搜"))
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
      XCTAssertTrue(service.credentials.isEmpty)
    }
  }

  func testUnreadWriteIsStillRecognizedAndContinues() async throws {
    backend.failReadBackAfterWrite()
    backend.normalizeWrites()
    try await withService(rule: EpisodeTrialRule(sites: [3, 7], include: "WEB")) { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, EpisodeTrialService.unconfirmedQuery)
      XCTAssertFalse(backend.mutations.contains("POST subscribe/search/81"), "没读回来就先不补搜")

      let resumed = await service.refresh(request)
      XCTAssertEqual(resumed, .searching, "后端整理过站点顺序，仍认得是自己写的")
      XCTAssertTrue(backend.mutations.contains("POST subscribe/search/81"))
    }
  }

  // MARK: - 别处改过、删过

  func testEditElsewhereReleasesTheTrialWithoutDeletingIt() async throws {
    for (key, value) in [
      ("keyword", "用户改的" as Any), ("search_interval", 6 as Any), ("state", "R" as Any),
    ] {
      backend.reset()
      try await withService { _, service, _, request in
        _ = await service.start(request)
        backend.edit(81, key, value)
        backend.finishSearch(submitted: false)
        let released = await service.refresh(request)
        XCTAssertEqual(released, EpisodeTrialService.released, key)
        XCTAssertFalse(backend.mutations.contains("DELETE subscribe/81"), key)
        XCTAssertTrue(service.credentials.isEmpty, key)
        XCTAssertNil(service.trialState(of: try XCTUnwrap(backend.subscribe(81))), "之后按普通订阅处理")
      }
    }
  }

  func testMoviePilotMetadataRefreshIsNotAnEdit() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.edit(81, "name", "MoviePilot 刷新的剧名")
      backend.edit(81, "year", "2024")
      backend.finishSearch(submitted: false)
      let finished = await service.refresh(request)
      XCTAssertEqual(finished, .noEligibleResource)
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
    }
  }

  func testEditBetweenListAndDeleteIsCaughtByRereading() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: false)
      backend.editOnNextBatchQuery(81, "keyword", "用户改的")
      let released = await service.refresh(request)
      XCTAssertEqual(released, EpisodeTrialService.released)
      XCTAssertFalse(backend.mutations.contains("DELETE subscribe/81"), "删除前按 ID 重读核对")
    }
  }

  func testTrialDeletedElsewhereEnds() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.deleteElsewhere(81)
      let ended = await service.refresh(request)
      XCTAssertEqual(ended, EpisodeTrialService.removedElsewhere)
      XCTAssertTrue(service.credentials.isEmpty)
    }
  }

  func testTrialDeletedElsewhereAfterSubmittingIsStillFollowed() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.finishSearch(submitted: true)
      backend.deleteElsewhere(81)
      let downloading = await service.refresh(request)
      XCTAssertEqual(downloading, .downloading(progress: 42))
    }
  }

  // MARK: - 取消

  func testCancelWaitsForTheSearchToStopBeforeDeleting() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      let row = try XCTUnwrap(backend.subscribe(81))
      let pending = await service.cancelTrial(subscriptionID: 81)
      XCTAssertEqual(pending, .pending)
      XCTAssertTrue(backend.mutations.contains("PUT subscribe/execution/batches/\(FakeMoviePilot.batchID)/cancel"))
      XCTAssertFalse(backend.mutations.contains("DELETE subscribe/81"), "取消受理只是停止中，批次还没结束")
      XCTAssertEqual(service.trialState(of: row), .cancelling)
      XCTAssertEqual(service.progress[request.key], .cancelling)

      let stillCancelling = await service.refresh(request)
      XCTAssertEqual(stillCancelling, .cancelling)

      backend.settleBatch("cancelled")
      let cancelled = await service.refresh(request)
      XCTAssertEqual(cancelled, EpisodeTrialService.cancelled)
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
      XCTAssertTrue(service.credentials.isEmpty)
    }
  }

  func testCancelAfterTheSearchEndedDeletesRightAway() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      backend.settleBatch("completed")
      let done = await service.cancelTrial(subscriptionID: 81)
      XCTAssertEqual(done, .done)
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
      XCTAssertFalse(backend.mutations.contains { $0.hasSuffix("/cancel") }, "已结束就不用再请求停止")
    }
  }

  func testCancelThatStillSubmittedADownloadKeepsFollowingIt() async throws {
    try await withService { _, service, _, request in
      _ = await service.start(request)
      _ = await service.cancelTrial(subscriptionID: 81)
      backend.finishSearch(submitted: true, state: "cancelled")
      let downloading = await service.refresh(request)
      XCTAssertEqual(downloading, .downloading(progress: 42), "停止前已提交的下载不动，接着看")
    }
  }

  func testCancelIntentSurvivesRestart() async throws {
    try await withService { api, service, defaults, request in
      _ = await service.start(request)
      _ = await service.cancelTrial(subscriptionID: 81)
      service.tearDown()

      backend.settleBatch("cancelled")
      let sleeper = ScriptedSleeper(drive: [.proceed])
      let resumed = EpisodeTrialService(api: api, defaults: defaults, sleep: sleeper.sleep) { _, _ in .notOnServer }
      defer { resumed.tearDown() }
      XCTAssertEqual(resumed.credentials.first?.cancelRequested, true)
      try await waitUntil { resumed.credentials.isEmpty }
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81", "重启后不用打开这一集也会收尾")
    }
  }

  func testCancelWithoutAnySearchDeletesThePlaceholder() async throws {
    backend.loseSearchReceipt(afterQueueing: false)
    try await withService { _, service, _, request in
      _ = await service.start(request)
      let done = await service.cancelTrial(subscriptionID: 81)
      XCTAssertEqual(done, .done)
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
    }
  }

  func testOnlyAdministratorsCanCancel() async throws {
    try await withService(superUser: false) { _, service, _, _ in
      XCTAssertFalse(service.canCancelTrial)
      let failed = await service.cancelTrial(subscriptionID: 81)
      XCTAssertEqual(failed, .failed)
    }
  }

  // MARK: - 后台对账

  func testBackgroundDriveFinishesTheTrialWithoutReopeningTheEpisode() async throws {
    try await withService { api, service, defaults, request in
      _ = await service.start(request)
      service.tearDown()

      backend.finishSearch(submitted: false)
      let resumed = EpisodeTrialService(
        api: api, defaults: defaults, sleep: ScriptedSleeper(drive: [.proceed]).sleep
      ) { _, _ in .notOnServer }
      defer { resumed.tearDown() }
      try await waitUntil { resumed.credentials.isEmpty }
      XCTAssertEqual(backend.mutations.last, "DELETE subscribe/81")
      XCTAssertEqual(resumed.progress[request.key], .noEligibleResource)
    }
  }

  func testConcurrentStartsShareOneSubmission() async throws {
    try await withService { _, service, _, request in
      async let first = service.start(request)
      async let second = service.start(request)
      let results = await [first, second]
      XCTAssertEqual(results, [.searching, .searching])
      XCTAssertEqual(backend.mutations.filter { $0 == "POST subscribe" }.count, 1)
    }
  }

  // MARK: - 版本门槛

  func testVersionGateFollowsNewBehaviorPolarity() {
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: nil))
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: "v3.2.5"))
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: "unknown"))
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.2.6"))
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.2.6-1"))
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.3.0"))
    XCTAssertFalse(EpisodeTrialAvailability.isAvailable(canRequestSuperUserEndpoints: false, backendVersion: "v3.3.0"))
  }

  func testUnsupportedBackendNeverTouchesServer() async throws {
    for version in ["v3.2.5", nil] as [String?] {
      backend.reset()
      try await withService { api, service, _, request in
        api.settings?.BACKEND_VERSION = version
        let result = await service.start(request)
        XCTAssertEqual(result, .unavailable(EpisodeTrialAvailability.requirementMessage))
        XCTAssertEqual(backend.requestCount, 0)
      }
    }
  }

  // MARK: - 规则

  func testWithoutSavedRuleTrialKeepsMoviePilotDefaults() async throws {
    try await withService(rule: nil) { _, service, _, request in
      XCTAssertTrue(service.rule.isDefault)
      _ = await service.start(request)
      let searched = try XCTUnwrap(backend.searched.first)
      XCTAssertEqual(searched["quality"] as? String, "MP 默认质量", "没指定的项保留 MoviePilot 默认值")
      XCTAssertEqual(searched["include"] as? String, "MP 默认包含", "包含规则从拒绝所有资源换回默认配置")
    }
  }

  func testSavedRuleIsPublishedAndKeptForTheAccount() async throws {
    try await withService(rule: nil) { api, service, defaults, _ in
      let rule = EpisodeTrialRule(sites: [3], resolution: "1080[pi]|x1080", downloader: "qb")
      try service.saveRule(rule)
      XCTAssertEqual(service.rule, rule)

      let reopened = EpisodeTrialService(api: api, defaults: defaults) { _, _ in .notOnServer }
      defer { reopened.tearDown() }
      XCTAssertEqual(reopened.rule, rule)

      service.tearDown()
      XCTAssertThrowsError(try service.saveRule(EpisodeTrialRule()), "拆除后的服务不能再写规则")
      XCTAssertEqual(reopened.rule, rule)
    }
  }

  func testRuleRoundTripsThroughTheEditingDraft() {
    let rule = EpisodeTrialRule(
      sites: [9, 2], searchByIMDb: true, keyword: "Show", quality: "WEB-?DL|WEB-?RIP", include: "简中",
      exclude: "预告", customWords: "A => B", filterGroups: ["高清"], downloader: "qb", savePath: "/tv")
    var draft = Subscribe(id: nil, name: "试看规则", type: "电视剧")
    rule.apply(to: &draft)
    XCTAssertEqual(EpisodeTrialRule(settingsOf: draft), EpisodeTrialRule(
      sites: [2, 9], searchByIMDb: true, keyword: "Show", quality: "WEB-?DL|WEB-?RIP", include: "简中",
      exclude: "预告", customWords: "A => B", filterGroups: ["高清"], downloader: "qb", savePath: "/tv"))

    // 选「全部」「默认」或清空输入框，都回到未指定。
    draft.quality = ""
    draft.sites = []
    draft.filter_groups = []
    draft.keyword = ""
    draft.search_imdbid = 0
    let cleared = EpisodeTrialRule(settingsOf: draft)
    XCTAssertNil(cleared.quality)
    XCTAssertNil(cleared.sites)
    XCTAssertNil(cleared.filterGroups)
    XCTAssertNil(cleared.keyword)
    XCTAssertFalse(cleared.searchByIMDb)
    XCTAssertTrue(EpisodeTrialRule(settingsOf: Subscribe(id: nil, name: "", type: "电视剧")).isDefault)
  }

  func testRuleEditorSavesOnlyWhenAsked() async throws {
    try await withService(rule: nil) { api, service, _, _ in
      try service.saveRule(EpisodeTrialRule(quality: "Remux"))
      let editor = EpisodeTrialRuleViewModel(service: service, apiService: api)
      XCTAssertEqual(editor.draft.quality, "Remux")

      editor.draft.quality = ""
      editor.draft.downloader = "tr"
      XCTAssertEqual(service.rule, EpisodeTrialRule(quality: "Remux"), "改草稿不写规则，按 Menu 关掉就不保存")

      XCTAssertTrue(editor.save())
      XCTAssertEqual(service.rule, EpisodeTrialRule(downloader: "tr"))

      service.tearDown()
      editor.draft.downloader = "qb"
      XCTAssertFalse(editor.save())
      XCTAssertNotNil(editor.saveErrorMessage)
    }
  }

  // MARK: - 页面轮询和入库提示

  func testPollNeverStartsATrial() async throws {
    let sleeper = ScriptedSleeper()
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      try await Task.sleep(for: .milliseconds(100))
      page.cancel()
      await page.value
      XCTAssertEqual(service.progress[request.key], .notStarted)
      XCTAssertEqual(backend.mutations, [])
      XCTAssertEqual(sleeper.delays, [], "没有要跟的事时不轮询")
    }
  }

  func testPollKeepsRefreshingWhileTheTrialRuns() async throws {
    let sleeper = ScriptedSleeper(polls: [.proceed, .suspend])
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      _ = await service.start(request)
      try await waitUntil { sleeper.delays.count == 2 }
      let whileVisible = sleeper.delays
      page.cancel()
      await page.value
      XCTAssertEqual(whileVisible, [EpisodeTrialService.activePollInterval, EpisodeTrialService.activePollInterval])
    }
  }

  func testPollFollowsAnExistingSubscriptionSlowlyAndNotInBackground() async throws {
    backend.addFormal(state: "R")
    let sleeper = ScriptedSleeper(polls: [.suspend])
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      try await waitUntil { sleeper.delays.count == 1 }
      XCTAssertEqual(sleeper.delays, [EpisodeTrialService.slowPollInterval])
      page.cancel()
      await page.value
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(sleeper.delays.count, 1, "离开页面后不在后台等正式订阅")
    }
  }

  func testLeavingThePageHandsOverAndAnnouncesWhenReady() async throws {
    let library = LibraryBox()
    // 第 1 次等待属于页面；页面离开后第 2 次属于后台跟踪，这时这一集已经入库。
    let sleeper = ScriptedSleeper(polls: [.suspend, .run {
      FakeMoviePilot.shared.finishSearch(submitted: true)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _, _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let page = try await openPage(service, request)
      _ = await service.start(request)
      try await waitUntil { sleeper.delays.count == 1 }
      page.cancel()
      await page.value

      try await waitUntil { notices.messages.count == 1 }
      XCTAssertEqual(notices.messages, ["《试看测试》第 2 季第 5 集已入库，可以播放了。"])
    }
  }

  func testStartWithoutPageIsFollowedAndAnnounced() async throws {
    let library = LibraryBox()
    let sleeper = ScriptedSleeper(polls: [.run {
      FakeMoviePilot.shared.finishSearch(submitted: true)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _, _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      _ = await service.start(request)
      try await waitUntil { notices.messages.count == 1 }
      XCTAssertEqual(service.progress[request.key], .ready(server: "测试媒体库"))
    }
  }

  func testVisiblePageShowsReadyWithoutNotice() async throws {
    let library = LibraryBox()
    let sleeper = ScriptedSleeper(polls: [.run {
      FakeMoviePilot.shared.finishSearch(submitted: true)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _, _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let page = try await openPage(service, request)
      _ = await service.start(request)
      try await waitUntil { service.progress[request.key]?.isReady == true }
      _ = await service.refresh(request)
      page.cancel()
      await page.value
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(notices.messages, [])
    }
  }

  /// 从没试看过、本来就在媒体库里的一集：页面在第一次刷新途中离开，也不提示“已入库”。
  func testLeavingMidRefreshDoesNotAnnounceAnEpisodeNeverTrialled() async throws {
    let checking = Flag()
    let availability: EpisodeTrialService.Availability = { _, _ in
      checking.isSet = true
      try? await Task.sleep(for: .milliseconds(200))
      return .playable(server: "测试媒体库")
    }
    try await withService(availability: availability) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let page = Task { await service.poll(request) }
      try await waitUntil { checking.isSet }
      page.cancel()
      await page.value
      XCTAssertEqual(service.progress[request.key], .ready(server: "测试媒体库"))
      try await Task.sleep(for: .milliseconds(50))
      XCTAssertEqual(notices.messages, [])
    }
  }

  /// 搜索、下载期间这一集进不了媒体库，按缓存查；要发起前和整理完等入库时才重读媒体服务器。
  func testLibraryIsReadFreshOnlyWhenItMayHaveChanged() async throws {
    let reads = FreshReads()
    try await withService(availability: { _, fresh in
      reads.values.append(fresh)
      return .notOnServer
    }) { _, service, _, request in
      _ = await service.start(request)
      _ = await service.refresh(request)
      backend.finishSearch(submitted: true)
      backend.organize("target-hash", succeeded: true)
      let organized = await service.refresh(request)
      XCTAssertEqual(organized, .waitingForLibrary)
      _ = await service.refresh(request)
      XCTAssertEqual(reads.values, [true, false, false, true])
    }
  }

  // MARK: - 辅助

  /// 打开显示这一集的页面，等它第一次刷新完、进入等待。
  private func openPage(
    _ service: EpisodeTrialService, _ request: EpisodeTrialRequest
  ) async throws -> Task<Void, Never> {
    let page = Task { await service.poll(request) }
    try await waitUntil { service.progress[request.key] != nil }
    try await Task.sleep(for: .milliseconds(20))
    return page
  }

  private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<300 where !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition())
  }

  private func withService(
    library: EpisodeAvailability = .notOnServer,
    rule: EpisodeTrialRule? = EpisodeTrialRule(sites: [7], quality: "WEB-DL", include: "WEB", customWords: "test words"),
    superUser: Bool = true,
    sleep: EpisodeTrialService.Sleep? = nil,
    availability: EpisodeTrialService.Availability? = nil,
    _ body: (APIService, EpisodeTrialService, UserDefaults, EpisodeTrialRequest) async throws -> Void
  ) async throws {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    let suite = "EpisodeTrialServiceTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let api = APIService.isolatedTestingInstance()
    let token = Token(
      access_token: "trial-fixture", token_type: "bearer", super_user: FlexibleBool(superUser),
      permissions: nil, user_id: 81, user_name: "fixture", avatar: nil)
    api.replaceSessionForTesting(baseURL: "https://episode-trial.local", token: token.access_token, currentUser: token)
    api.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")
    let availability = availability ?? { _, _ in library }
    let service = EpisodeTrialService(
      api: api, defaults: defaults, sleep: sleep ?? ScriptedSleeper().sleep, availability: availability)
    defer { service.tearDown() }
    if let rule { try service.saveRule(rule) }
    let request = try XCTUnwrap(EpisodeTrialRequest(
      media: MediaInfo(tmdb_id: 91, title: "试看测试", type: "电视剧"),
      episode: MoviePilotEpisode(TmdbEpisode(id: 234, episodeNumber: 5), season: 2, index: 4)
    ))
    try await body(api, service, defaults, request)
  }
}

/// 服务里的等待按步骤编排。页面和后台跟踪的轮询（`polls`）、后台对账（`drive`）各有一串步骤，
/// 用完后挂起到被取消。`.proceed` 立即返回；`.run` 先改一下服务器再返回。
nonisolated private final class ScriptedSleeper: @unchecked Sendable {
  enum Step {
    case suspend
    case proceed
    case run(@Sendable () -> Void)
  }

  private let lock = NSLock()
  private var requested: [Duration] = []
  private var drives = 0
  private var polls: [Step]
  private var drive: [Step]

  init(polls: [Step] = [], drive: [Step] = []) {
    self.polls = polls
    self.drive = drive
  }

  /// 轮询请求过的间隔（不含后台对账）。
  var delays: [Duration] { lock.withLock { requested } }
  var driveCount: Int { lock.withLock { drives } }

  var sleep: EpisodeTrialService.Sleep {
    { [self] delay in
      try Task.checkCancellation()
      let isDrive = delay == EpisodeTrialService.driveInterval
      let step = lock.withLock { () -> Step in
        if isDrive {
          drives += 1
          return drive.isEmpty ? .suspend : drive.removeFirst()
        }
        requested.append(delay)
        return polls.isEmpty ? .suspend : polls.removeFirst()
      }
      switch step {
      case .suspend: try await Task.sleep(for: .seconds(3600))
      case .proceed: return
      case .run(let change): change()
      }
    }
  }
}

nonisolated private final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = false

  var isSet: Bool {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

private final class FreshReads {
  var values: [Bool] = []
}

/// 测试改变的媒体库结果，后台跟踪的等待里会改它。
nonisolated private final class LibraryBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: EpisodeAvailability = .notOnServer

  var value: EpisodeAvailability {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// 记下某个 APIService 的试看服务发出的入库通知。
@MainActor
private final class ReadyNoticeRecorder {
  private(set) var messages: [String] = []
  private var observer: NSObjectProtocol?

  init(api: APIService) {
    observer = NotificationCenter.default.addObserver(
      forName: .episodeTrialDidBecomeReady, object: api, queue: .main
    ) { [weak self] notification in
      let message = notification.userInfo?[EpisodeTrialReadyNotice.messageKey] as? String
      MainActor.assumeIsolated { self?.messages.append(message ?? "") }
    }
  }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}

nonisolated private final class EpisodeTrialURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "episode-trial.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    do {
      let body = try FakeMoviePilot.shared.respond(to: request)
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

/// 按 MoviePilot 接口合同模拟的后端：订阅、搜索批次、下载历史、下载器、整理队列和整理历史。
/// 媒体都是 tmdb:91 第 2 季，试看的是第 5 集。
nonisolated private final class FakeMoviePilot: @unchecked Sendable {
  static let shared = FakeMoviePilot()
  static let batchID = "0123456789abcdef0123456789abcdef"
  private static let finishedStates: Set<String> = ["completed", "failed", "cancelled", "skipped"]

  private let lock = NSLock()
  private var rows: [Int: [String: Any]] = [:]
  private var nextID = 81
  private var batchState: String?
  private var batchSubmitted = 0
  private var history: [[String: Any]] = []
  private var historyOnSecondPage = false
  private var downloading: [String: Double?] = [:]
  private var offlineClient = false
  private var queue: Set<String> = []
  private var transfers: [String: Bool] = [:]
  private var requests: [String] = []
  private var totalRequests = 0
  private var createdBodies: [[String: Any]] = []
  private var searchedRows: [[String: Any]] = []
  /// 创建回执：nil 正常；true 落库后回执丢失；false 请求没送到。
  private var createLoss: Bool?
  private var createMessage = "新增订阅成功"
  /// 查询之后、新增之前，别处正好建了同季订阅，新增时按季去重返回它。
  private var existingOnCreate: String?
  private var createLandsTwice = false
  /// 补搜回执：nil 正常；true 排上队后回执丢失；false 请求没送到。
  private var searchLoss: Bool?
  private var searchRejected = false
  private var normalizesWrites = false
  private var failsReadBackAfterWrite = false
  private var readBackFails = false
  private var pendingEdit: (id: Int, key: String, value: Any)?

  var mutations: [String] { lock.withLock { requests } }
  /// 读和写都算，用来证明某条路径完全没有访问服务器。
  var requestCount: Int { lock.withLock { totalRequests } }
  var created: [[String: Any]] { lock.withLock { createdBodies } }
  /// 每次补搜时订阅的样子。
  var searched: [[String: Any]] { lock.withLock { searchedRows } }

  func reset() {
    lock.withLock {
      rows = [:]
      nextID = 81
      batchState = nil
      batchSubmitted = 0
      history = []
      historyOnSecondPage = false
      downloading = [:]
      offlineClient = false
      queue = []
      transfers = [:]
      requests = []
      totalRequests = 0
      createdBodies = []
      searchedRows = []
      createLoss = nil
      createMessage = "新增订阅成功"
      existingOnCreate = nil
      createLandsTwice = false
      searchLoss = nil
      searchRejected = false
      normalizesWrites = false
      failsReadBackAfterWrite = false
      readBackFails = false
      pendingEdit = nil
    }
  }

  func subscribe(_ id: Int) -> Subscribe? {
    guard let row = lock.withLock({ rows[id] }), let data = try? JSONSerialization.data(withJSONObject: row) else {
      return nil
    }
    return try? JSONDecoder().decode(Subscribe.self, from: data)
  }

  // MARK: 场景

  /// 同季已有的订阅（ID 70）。带标记时就是别的设备留下的试看订阅。
  @discardableResult
  func addFormal(state: String, marker: String? = nil) -> Subscribe {
    lock.withLock { rows[70] = Self.formalRow(state: state, marker: marker) }
    return subscribe(70)!
  }

  private static func formalRow(state: String, marker: String?) -> [String: Any] {
    var row: [String: Any] = [
      "id": 70, "name": "试看测试", "type": "电视剧", "season": 2, "media_source": "tmdb", "media_id": "91",
      "username": "other", "state": state,
    ]
    if let marker {
      row["filter"] = marker
      row["include"] = "WEB"
    }
    return row
  }

  func returnExistingOnCreate(state: String) { lock.withLock { existingOnCreate = state } }
  func setCreateMessage(_ message: String) { lock.withLock { createMessage = message } }
  func loseCreateReceipt(afterStoring: Bool?) { lock.withLock { createLoss = afterStoring } }
  func landCreateTwice() { lock.withLock { createLandsTwice = true } }
  func loseSearchReceipt(afterQueueing: Bool?) { lock.withLock { searchLoss = afterQueueing } }
  func rejectSearch() { lock.withLock { searchRejected = true } }
  func normalizeWrites() { lock.withLock { normalizesWrites = true } }
  func failReadBackAfterWrite() { lock.withLock { failsReadBackAfterWrite = true } }
  func edit(_ id: Int, _ key: String, _ value: Any) { lock.withLock { rows[id]?[key] = value } }
  func deleteElsewhere(_ id: Int) { lock.withLock { _ = rows.removeValue(forKey: id) } }
  /// 下一次查批次时，别处正好改了这条订阅（发生在读列表之后、删除之前）。
  func editOnNextBatchQuery(_ id: Int, _ key: String, _ value: Any) {
    lock.withLock { pendingEdit = (id, key, value) }
  }

  func settleBatch(_ state: String) { lock.withLock { batchState = state } }

  /// 搜索结束；提交下载时按 MoviePilot 的做法写下载记录（带订阅 ID），下载器里出现任务。
  func finishSearch(submitted: Bool, state: String = "completed", recordsHistory: Bool = true) {
    lock.withLock {
      batchState = state
      batchSubmitted = submitted ? 1 : 0
      guard submitted else { return }
      downloading["target-hash"] = 42
      guard recordsHistory else { return }
      history.insert([
        "id": 2, "title": "MP 识别标题", "media_source": "tmdb", "media_id": "91", "seasons": "S02",
        "episodes": "E05", "download_hash": "target-hash", "downloader": "fixture-client",
        "note": ["subscription_download": ["subscription_id": 81]],
      ], at: 0)
    }
  }

  /// 别的入口已经在下这一集。
  func addDownload(hash: String, progress: Double?, offline: Bool = false) {
    lock.withLock {
      history.append([
        "id": 5, "media_source": "tmdb", "media_id": "91", "seasons": "S02", "episodes": "E05", "download_hash": hash,
      ])
      downloading[hash] = progress
      offlineClient = offline
    }
  }

  func pushHistoryToSecondPage() { lock.withLock { historyOnSecondPage = true } }
  func finishDownload(_ hash: String) { lock.withLock { _ = downloading.removeValue(forKey: hash) } }

  func moveToQueue(_ hash: String) {
    lock.withLock {
      _ = downloading.removeValue(forKey: hash)
      queue.insert(hash)
    }
  }

  func organize(_ hash: String, succeeded: Bool) {
    lock.withLock {
      _ = downloading.removeValue(forKey: hash)
      queue.remove(hash)
      transfers[hash] = succeeded
    }
  }

  // MARK: 接口

  func respond(to request: URLRequest) throws -> Data {
    try lock.withLock {
      let method = request.httpMethod ?? "GET"
      let path = request.url?.path.split(separator: "/").dropFirst(2).joined(separator: "/") ?? ""
      let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
      let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
      totalRequests += 1
      if method != "GET" { requests.append("\(method) \(path)") }
      let value = try respond(method: method, path: path, query: query, request: request)
      return try JSONSerialization.data(withJSONObject: value)
    }
  }

  private func respond(method: String, path: String, query: [String: String], request: URLRequest) throws -> Any {
    let accepted = ["success": true]
    let parts = path.split(separator: "/").map(String.init)
    let trailingID = parts.last.flatMap { Int($0) }
    let batchPath = "subscribe/execution/batches/\(Self.batchID)"
    switch (method, path) {
    case ("GET", "subscribe"):
      return rows.keys.sorted().compactMap { rows[$0] }
    case ("POST", "subscribe"):
      return try create(try body(request))
    case ("PUT", "subscribe"):
      return try save(try body(request))
    case ("GET", _) where parts.count == 2 && parts[0] == "subscribe" && trailingID != nil:
      if readBackFails {
        readBackFails = false
        throw URLError(.networkConnectionLost)
      }
      guard let row = rows[trailingID!] else { throw URLError(.fileDoesNotExist) }
      return row
    case ("DELETE", _) where parts.count == 2 && parts[0] == "subscribe" && trailingID != nil:
      return rows.removeValue(forKey: trailingID!) != nil ? accepted : ["success": false]
    case ("PUT", _) where path.hasPrefix("subscribe/status/") && trailingID != nil:
      guard rows[trailingID!] != nil else { return ["success": false] }
      rows[trailingID!]?["state"] = query["state"]
      return accepted
    case ("POST", _) where path.hasPrefix("subscribe/search/") && trailingID != nil:
      return try search(trailingID!)
    case ("GET", batchPath):
      if let edit = pendingEdit {
        pendingEdit = nil
        rows[edit.id]?[edit.key] = edit.value
      }
      guard let state = batchState else { throw URLError(.fileDoesNotExist) }
      return [
        "batch_id": Self.batchID, "state": state, "total_count": 1,
        "finished_count": Self.finishedStates.contains(state) ? 1 : 0, "download_counts": ["submitted": batchSubmitted],
      ] as [String: Any]
    case ("PUT", batchPath + "/cancel"):
      // 只给运行中的批次打上取消标记；任务到下一个检查点才停，结束要等测试结算。
      guard let state = batchState, !Self.finishedStates.contains(state) else {
        return ["success": false, "message": "这次搜索已经结束，暂时无法停止"]
      }
      batchState = "cancelling"
      return accepted
    case ("GET", "system/setting/public/DefaultTvSubscribeConfig"):
      return ["value": ["include": "MP 默认包含", "quality": "MP 默认质量"]]
    case ("GET", "history/download"):
      guard historyOnSecondPage else { return query["page"] == "1" ? history : [] }
      let filler = (0..<100).map { offset -> [String: Any] in
        [
          "id": 1_100 - offset, "media_source": "tmdb", "media_id": "777", "seasons": "S01", "episodes": "E01",
          "download_hash": "other-\(offset)",
        ]
      }
      return query["page"] == "1" ? filler : query["page"] == "2" ? history : []
    case ("GET", "download/clients"):
      return [["name": offlineClient ? "offline-client" : "fixture-client", "type": "qbittorrent"]]
    case ("GET", "download"):
      if query["name"] == "offline-client" { throw URLError(.cannotConnectToHost) }
      return downloading.map { hash, progress -> [String: Any] in
        var task: [String: Any] = ["hash": hash]
        if let progress { task["progress"] = progress }
        return task
      }
    case ("GET", "transfer/queue"):
      return queue.isEmpty ? [] : [["tasks": queue.map { ["downloader": "fixture-client", "download_hash": $0] }]]
    case ("GET", "history/transfer"):
      let list = transfers.map { hash, status -> [String: Any] in
        [
          "id": 9, "title": "MP 识别标题", "media_source": "tmdb", "media_id": "91", "seasons": "S02",
          "episodes": "E05", "download_hash": hash, "status": status,
        ]
      }
      return ["success": true, "data": ["list": list]] as [String: Any]
    default:
      throw URLError(.unsupportedURL)
    }
  }

  private func create(_ body: [String: Any]) throws -> Any {
    createdBodies.append(body)
    if let state = existingOnCreate {
      rows[70] = Self.formalRow(state: state, marker: nil)
      return ["success": true, "message": "订阅已存在", "data": ["id": 70]] as [String: Any]
    }
    if createLoss == false { throw URLError(.timedOut) }
    // MoviePilot 按电视剧默认订阅配置填上请求没给的项，并安排一分钟后的自动搜索（暂停后会跳过）。
    var fields = body
    if fields["quality"] == nil { fields["quality"] = "MP 默认质量" }
    fields["username"] = "fixture"
    fields["state"] = "N"
    fields["execution_status"] = ["source": "new", "batch_id": "fedcba9876543210fedcba9876543210"]
    let id = nextID
    nextID += 1
    fields["id"] = id
    rows[id] = fields
    if createLandsTwice {
      var twin = fields
      twin["id"] = nextID
      rows[nextID] = twin
      nextID += 1
    }
    if createLoss == true { throw URLError(.networkConnectionLost) }
    return ["success": true, "message": createMessage, "data": ["id": id]] as [String: Any]
  }

  private func save(_ fields: [String: Any]) throws -> Any {
    guard let id = fields["id"] as? Int, rows[id] != nil else { return ["success": false] }
    for (key, value) in fields {
      if normalizesWrites, key == "sites", let sites = value as? [Int] {
        rows[id]?[key] = Array(sites.reversed())
      } else if normalizesWrites, value is NSNull, ["sites", "filter_groups"].contains(key) {
        rows[id]?[key] = [] as [Any]
      } else {
        rows[id]?[key] = value
      }
    }
    if failsReadBackAfterWrite {
      failsReadBackAfterWrite = false
      readBackFails = true
    }
    return ["success": true]
  }

  private func search(_ id: Int) throws -> Any {
    guard let row = rows[id] else { return ["success": false] }
    if searchRejected { return ["success": false, "message": "订阅不存在"] }
    if searchLoss == false { throw URLError(.timedOut) }
    searchedRows.append(row)
    // 补搜先写进队列再回复：订阅行带上最新一次手动搜索的批次。
    batchState = "running"
    rows[id]?["execution_status"] = ["source": "manual", "batch_id": Self.batchID]
    if searchLoss == true { throw URLError(.networkConnectionLost) }
    return [
      "success": true,
      "data": ["batch_id": Self.batchID, "batch_ids": [Self.batchID], "single": true, "target_count": 1],
    ] as [String: Any]
  }

  private func body(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let size = stream.read(&buffer, maxLength: buffer.count)
        guard size > 0 else { break }
        data.append(contentsOf: buffer.prefix(size))
      }
    }
    guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw URLError(.cannotParseResponse)
    }
    return fields
  }
}
