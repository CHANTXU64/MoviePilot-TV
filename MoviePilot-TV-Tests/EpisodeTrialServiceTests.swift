import Foundation
import XCTest

@testable import MoviePilot_TV

@MainActor
final class EpisodeTrialServiceTests: XCTestCase {
  override func setUp() async throws {
    EpisodeTrialURLProtocol.fixture.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(EpisodeTrialURLProtocol.self))
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(EpisodeTrialURLProtocol.self)
  }

  func testPausedFormalSubscriptionRemainsReadOnlyEvenAfterItDisappears() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .subscriptionPaused)

      fixture.setMode(.missingFormal)
      let refresh = await service.refresh(request)
      XCTAssertEqual(refresh, .unavailable("原订阅已结束，可以发起试看"))
      XCTAssertEqual(fixture.mutations, [])
    }
  }

  func testCreateReturningExistingIDDoesNotPauseEditSearchOrDeleteIt() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.reuse)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .waitingForSubscription)
      let refresh = await service.refresh(request)
      XCTAssertEqual(refresh, .waitingForSubscription)
      XCTAssertEqual(fixture.mutations, ["POST subscribe"])
    }
  }

  func testNativeSearchKeepsExactEpisodeAndTracksAfterSubscriptionDisappears() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { api, service, defaults, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      XCTAssertEqual(fixture.mutations, [
        "POST subscribe", "PUT subscribe/status/81", "PUT subscribe", "POST subscribe/search/81"
      ])
      XCTAssertEqual(fixture.createdValues, .init(
        season: 2, start: 5, total: 6, include: "(?!)", bestVersion: 1, fullPack: 0, quality: nil))
      XCTAssertEqual(fixture.searchValues, .init(
        season: 2, start: 5, total: 5, include: "WEB", bestVersion: 1, fullPack: 0, quality: "WEB-DL"))

      // 模拟 TV 重建任务作用域，以及 MoviePilot 在接收下载后直接移除临时订阅。
      service.tearDown()
      fixture.setMode(.downloading)
      var library: EpisodeAvailability = .notOnServer
      let resumed = EpisodeTrialService(api: api, defaults: defaults) { _ in library }
      defer { resumed.tearDown() }
      let downloading = await resumed.refresh(request)
      XCTAssertEqual(downloading, .downloading(progress: 42))

      fixture.setMode(.organizing)
      let organizing = await resumed.refresh(request)
      XCTAssertEqual(organizing, .organizing)

      fixture.setMode(.transferred)
      let transferred = await resumed.refresh(request)
      XCTAssertEqual(transferred, .waitingForLibrary)

      library = .playable(server: "测试媒体库")
      let ready = await resumed.refresh(request)
      XCTAssertEqual(ready, .ready(server: "测试媒体库"))
      XCTAssertFalse(fixture.mutations.contains("DELETE subscribe/81"))
    }
  }

  func testFinishedWithoutResourceCleansOnlyUnchangedTemporaryRow() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      fixture.setMode(.noResource)
      let refresh = await service.refresh(request)
      XCTAssertEqual(refresh, .noEligibleResource)
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")
    }
  }

  func testExternalEditPreventsAutomaticDeletion() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      fixture.setMode(.externallyEdited)
      let refresh = await service.refresh(request)
      XCTAssertEqual(refresh, .unavailable("试看订阅已由其他入口修改"))
      XCTAssertFalse(fixture.mutations.contains("DELETE subscribe/81"))
    }
  }

  func testLostSearchReceiptRecoversTheBatchWithoutPostingAgain() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.lostSearchReceipt)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .submissionUnconfirmed)
      fixture.setMode(.noResource)
      let refresh = await service.refresh(request)
      XCTAssertEqual(refresh, .noEligibleResource)
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe/search/81" }.count, 1)
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")
    }
  }

  func testVersionAndUnconfirmedLibraryBlockNewSubscription() async throws {
    try await withService(library: .failed("媒体服务器暂不可用")) { api, service, _, request in
      api.settings?.BACKEND_VERSION = "v3.2.5"
      let unsupported = await service.start(request)
      XCTAssertEqual(unsupported, .unavailable("试看需要 MoviePilot v3.2.6 或更高版本和管理员账号"))
      api.settings?.BACKEND_VERSION = "v3.2.6"
      let unknown = await service.start(request)
      XCTAssertEqual(unknown, .unavailable("媒体服务器暂不可用"))
      XCTAssertEqual(EpisodeTrialURLProtocol.fixture.mutations, [])
    }
  }

  func testLostCreateRequestWaitsThenAllowsStartingAgain() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let clock = TrialClock()
    fixture.setMode(.lostCreate)
    try await withService(clock: clock) { _, service, _, request in
      let lost = await service.start(request)
      XCTAssertEqual(lost, .submissionUnconfirmed)

      // 确认期内不能重复创建，避免第一次请求晚到后留下两条试看订阅。
      fixture.setMode(.initial)
      let waiting = await service.start(request)
      XCTAssertEqual(waiting, .submissionUnconfirmed)
      XCTAssertEqual(fixture.mutations, ["POST subscribe"])

      clock.advance(EpisodeTrialTemporarySubscription.confirmationWindow + 1)
      let restarted = await service.start(request)
      XCTAssertEqual(restarted, .searching)
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe" }.count, 2)
    }
  }

  func testUndeliveredSearchRemovesTemporaryRowThenAllowsStartingAgain() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let clock = TrialClock()
    fixture.setMode(.searchNotReceived)
    try await withService(clock: clock) { _, service, _, request in
      let lost = await service.start(request)
      XCTAssertEqual(lost, .submissionUnconfirmed)

      let waiting = await service.refresh(request)
      XCTAssertEqual(waiting, .submissionUnconfirmed)
      XCTAssertFalse(fixture.mutations.contains("DELETE subscribe/81"))

      clock.advance(EpisodeTrialTemporarySubscription.confirmationWindow + 1)
      let expired = await service.refresh(request)
      XCTAssertEqual(expired, .unavailable("上次试看准备未完成，可以重新发起"))
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")

      fixture.setMode(.initial)
      let restarted = await service.start(request)
      XCTAssertEqual(restarted, .searching)
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe/search/81" }.count, 2)
    }
  }

  func testFailedSearchBatchAllowsStartingAgain() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      fixture.setMode(.batchFailed)
      let failed = await service.refresh(request)
      XCTAssertEqual(failed, .unavailable("MoviePilot 没有完成本次试看搜索，可以重新发起"))
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")

      fixture.setMode(.initial)
      let restarted = await service.start(request)
      XCTAssertEqual(restarted, .searching)
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe" }.count, 2)
    }
  }

  func testOnlyExpiredPlaceholderIsRemovedBeforeStarting() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let clock = TrialClock()
    try await withService(clock: clock) { _, service, _, request in
      fixture.setPlaceholder(marker: EpisodeTrialTemporarySubscription.makeMarker(at: clock.now))
      let blocked = await service.start(request)
      XCTAssertEqual(blocked, .seasonTrialInProgress)
      XCTAssertEqual(fixture.mutations, [])

      clock.advance(EpisodeTrialTemporarySubscription.confirmationWindow)
      let started = await service.start(request)
      XCTAssertEqual(started, .searching)
      XCTAssertEqual(fixture.mutations.first, "DELETE subscribe/90")
    }
  }

  func testUnreachableDownloaderDoesNotHideDownloadOnAnotherClient() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.existingDownload)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .downloading(progress: 30))
      XCTAssertEqual(fixture.mutations, [])
    }
  }

  func testUnreachableDownloaderBlocksNewSubscriptionWhenDownloadIsNotFound() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.existingDownloadUnconfirmed)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .unavailable("暂时无法确认试看进度"))
      XCTAssertEqual(fixture.mutations, [])
    }
  }

  func testConcurrentStartsShareOneSubmission() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      async let first = service.start(request)
      async let second = service.start(request)
      let results = await [first, second]
      XCTAssertEqual(results, [.searching, .searching])
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe" }.count, 1)
    }
  }

  func testTimedCleanupRemovesTemporaryRowWithoutReopeningTheEpisode() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let clock = TrialClock()
    try await withService(clock: clock) { api, service, defaults, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      // 模拟 App 被关掉后很久才重新打开，用户也没有再进这一集。
      service.tearDown()
      fixture.setMode(.noResource)
      clock.advance(30 * 60)
      let sleeper = CleanupSleeper()
      let resumed = EpisodeTrialService(
        api: api, defaults: defaults, now: { clock.now }, sleep: sleeper.sleep
      ) { _ in .notOnServer }
      defer { resumed.tearDown() }

      for _ in 0..<300 where !fixture.mutations.contains("DELETE subscribe/81") {
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")
      XCTAssertEqual(resumed.progress[request.key], .noEligibleResource)
      XCTAssertEqual(sleeper.delays.first, .seconds(600))
    }
  }

  func testEndedFormalSubscriptionWithoutNewDownloadAllowsTrial() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    try await withService { _, service, _, request in
      let paused = await service.start(request)
      XCTAssertEqual(paused, .subscriptionPaused)

      fixture.setMode(.missingFormal)
      let started = await service.start(request)
      XCTAssertEqual(started, .searching)
      XCTAssertEqual(fixture.mutations.first, "POST subscribe")
    }
  }

  func testEndedFormalSubscriptionWaitsForLibraryAfterItsDownloadWasOrganized() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    try await withService { _, service, _, request in
      let paused = await service.start(request)
      XCTAssertEqual(paused, .subscriptionPaused)

      // 正式订阅下完、整理成功后结束了，媒体库还没扫到这一集。
      fixture.setMode(.formalEndedOrganized)
      let waiting = await service.start(request)
      XCTAssertEqual(waiting, .waitingForLibrary)
      XCTAssertEqual(fixture.mutations, [])
    }
  }

  func testBackendNormalizedWriteStillSearchesAndCleansUp() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.normalizesWrites)
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      fixture.setMode(.noResource)
      let finished = await service.refresh(request)
      XCTAssertEqual(finished, .noEligibleResource)
      XCTAssertEqual(fixture.mutations.last, "DELETE subscribe/81")
    }
  }

  func testTransferResultIsFoundByTitleMoviePilotRecognized() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      fixture.setMode(.transferredUnderRecognizedTitle)
      let transferred = await service.refresh(request)
      XCTAssertEqual(transferred, .waitingForLibrary)
    }
  }

  func testVersionGateFollowsNewBehaviorPolarity() {
    XCTAssertEqual(EpisodeTrialAvailability.minimumBackendVersion, "v3.2.6")
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: "v3.2.5"))
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.2.6"))
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.2.6-1"), "热修复版本照常提供")
    XCTAssertTrue(EpisodeTrialAvailability.supports(backendVersion: "v3.3.0"), "未登记的更新版本照常提供")
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: nil), "读不出版本时不提供")
    XCTAssertFalse(EpisodeTrialAvailability.supports(backendVersion: "dev"), "无法解析的版本不提供")
    XCTAssertFalse(
      EpisodeTrialAvailability.isAvailable(canRequestSuperUserEndpoints: false, backendVersion: "v3.2.6"),
      "普通用户不提供")
  }

  func testUnsupportedBackendNeverTouchesServer() async throws {
    try await withService { api, service, _, request in
      for version in ["v3.2.5", "dev"] {
        api.settings?.BACKEND_VERSION = version
        let progress = await service.start(request)
        XCTAssertEqual(progress, .unavailable(EpisodeTrialAvailability.requirementMessage))
      }
      api.settings?.BACKEND_VERSION = nil
      let missing = await service.start(request)
      XCTAssertEqual(missing, .unavailable(EpisodeTrialAvailability.requirementMessage))
      XCTAssertEqual(EpisodeTrialURLProtocol.fixture.requestCount, 0)
    }
  }

  func testWithoutSavedRuleTrialUsesMoviePilotDefaults() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService(rule: nil) { _, service, _, request in
      XCTAssertTrue(service.rule.isDefault)
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      XCTAssertEqual(fixture.searchValues, .init(
        season: 2, start: 5, total: 5, include: nil, bestVersion: 1, fullPack: 0, quality: nil))
    }
  }

  func testSavedRuleIsPublishedAndKeptForTheAccount() async throws {
    try await withService(rule: nil) { api, service, defaults, _ in
      let rule = EpisodeTrialRule(sites: [3], resolution: "1080[pi]|x1080", downloader: "qb")
      try service.saveRule(rule)
      XCTAssertEqual(service.rule, rule)

      let reopened = EpisodeTrialService(api: api, defaults: defaults) { _ in .notOnServer }
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

  func testPollKeepsRefreshingUntilTrialFinishes() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let sleeper = PollSleeper { fixture.setMode(.noResource) }
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      // 进度先变成没有资源，随后才删除临时订阅，两件事都等到。
      try await waitUntil {
        service.progress[request.key] == .noEligibleResource && fixture.mutations.last == "DELETE subscribe/81"
      }
      XCTAssertEqual(sleeper.pollDelays, [EpisodeTrialService.activePollInterval])
      page.cancel()
      await page.value
    }
  }

  func testPollNeverStartsATrial() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let sleeper = PollSleeper {}
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      let requests = fixture.requestCount
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(fixture.requestCount, requests, "没有可跟踪的事时页面不请求后端")
      XCTAssertEqual(sleeper.pollDelays, [])
      XCTAssertEqual(fixture.mutations, [])
      page.cancel()
      await page.value
    }
  }

  func testPollFollowsFormalSubscriptionSlowly() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    let sleeper = PollSleeper { fixture.setMode(.missingFormal) }
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let page = try await openPage(service, request)
      let paused = await service.start(request)
      XCTAssertEqual(paused, .subscriptionPaused)

      try await waitUntil { service.progress[request.key] == .unavailable("原订阅已结束，可以发起试看") }
      XCTAssertEqual(sleeper.pollDelays, [EpisodeTrialService.formalPollInterval])
      XCTAssertEqual(fixture.mutations, [])
      page.cancel()
      await page.value
    }
  }

  func testLeavingThePageHandsOverAndAnnouncesWhenReady() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let library = LibraryBox()
    // 第 1 次等待属于页面；页面离开后第 2 次属于后台跟踪，这时这一集整理完并入库。
    let sleeper = PollSleeper([.suspend, .proceed {
      fixture.setMode(.transferred)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let page = try await openPage(service, request)
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      try await waitUntil { sleeper.pollDelays.count == 1 }
      page.cancel()
      await page.value

      try await waitUntil { notices.messages.count == 1 }
      XCTAssertEqual(service.progress[request.key], .ready(server: "测试媒体库"))
      XCTAssertEqual(sleeper.pollDelays, [EpisodeTrialService.activePollInterval, EpisodeTrialService.activePollInterval])
      XCTAssertEqual(notices.messages, ["《试看测试》第 2 季第 5 集已入库，可以播放了。"])
    }
  }

  func testStartWithoutPageIsFollowedAndAnnounced() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let library = LibraryBox()
    let sleeper = PollSleeper([.proceed {
      fixture.setMode(.transferred)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      try await waitUntil { notices.messages.count == 1 }
      XCTAssertEqual(service.progress[request.key], .ready(server: "测试媒体库"))
    }
  }

  func testVisiblePageShowsReadyWithoutNotice() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let library = LibraryBox()
    let sleeper = PollSleeper([.proceed {
      fixture.setMode(.transferred)
      library.value = .playable(server: "测试媒体库")
    }])
    try await withService(sleep: sleeper.sleep, availability: { _ in library.value }) { api, service, _, request in
      let notices = ReadyNoticeRecorder(api: api)
      let page = try await openPage(service, request)
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      try await waitUntil { service.progress[request.key]?.isReady == true }
      // 可以播放是在这次刷新中途发布的；排一次刷新，等这次推进完整结束再离开页面。
      _ = await service.refresh(request)
      page.cancel()
      await page.value
      // 已经可以播放、没有可跟踪的事，页面离开后也不转给后台。
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(notices.messages, [])
      XCTAssertEqual(sleeper.pollDelays.count, 1)
    }
  }

  func testWaitingForFormalSubscriptionIsNotFollowedInBackground() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    let sleeper = PollSleeper([], then: .suspend)
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let paused = await service.start(request)
      XCTAssertEqual(paused, .subscriptionPaused)
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(sleeper.pollDelays, [])
    }
  }

  func testCancelStopsSearchDeletesRowAndAllowsStartingAgain() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    try await withService { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)

      let cancelled = await service.cancelTrial(subscriptionID: 81)
      XCTAssertTrue(cancelled)
      let cancel = "PUT subscribe/execution/batches/0123456789abcdef0123456789abcdef/cancel"
      XCTAssertEqual(Array(fixture.mutations.suffix(2)), [cancel, "DELETE subscribe/81"], "先停搜索再删订阅")
      XCTAssertEqual(service.progress[request.key], EpisodeTrialService.cancelled)

      // 取消后这一集不再跟踪，可以重新发起。
      let again = await service.start(request)
      XCTAssertEqual(again, .searching)
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe" }.count, 2)
    }
  }

  func testCancelOnlyDeletesARowThatIsStillATrial() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setMode(.pausedFormal)
    try await withService { _, service, _, _ in
      let cancelled = await service.cancelTrial(subscriptionID: 81)
      XCTAssertFalse(cancelled)
      XCTAssertEqual(fixture.mutations, [])
    }
  }

  func testTrialStartedElsewhereCanBeCancelled() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    fixture.setPlaceholder(marker: EpisodeTrialTemporarySubscription.makeMarker(at: Date()))
    try await withService { api, service, _, _ in
      // 取消只是删订阅，不受试看的版本门禁限制。
      api.settings?.BACKEND_VERSION = "v3.2.5"
      XCTAssertTrue(service.canCancelTrial)
      let cancelled = await service.cancelTrial(subscriptionID: 90)
      XCTAssertTrue(cancelled)
      XCTAssertEqual(fixture.mutations, ["DELETE subscribe/90"])
    }
  }

  func testOrganizationFailureEndsTheTrial() async throws {
    let fixture = EpisodeTrialURLProtocol.fixture
    let sleeper = PollSleeper([], then: .suspend)
    try await withService(sleep: sleeper.sleep) { _, service, _, request in
      let start = await service.start(request)
      XCTAssertEqual(start, .searching)
      fixture.setMode(.transferFailed)
      let failed = await service.refresh(request)
      XCTAssertEqual(failed, .organizationFailed)

      // 不再轮询，也不在后台跟踪。
      let page = try await openPage(service, request)
      try await Task.sleep(for: .milliseconds(100))
      page.cancel()
      await page.value
      XCTAssertEqual(sleeper.pollDelays.filter { $0 == EpisodeTrialService.activePollInterval }.count, 1,
        "只剩发起时后台跟踪的那一次等待")

      let again = await service.start(request)
      XCTAssertEqual(again, .searching, "整理失败后可以重新发起")
      XCTAssertEqual(fixture.mutations.filter { $0 == "POST subscribe" }.count, 2)
    }
  }

  /// 打开显示这一集的页面，等它第一次刷新完、进入等待。
  private func openPage(
    _ service: EpisodeTrialService, _ request: EpisodeTrialRequest
  ) async throws -> Task<Void, Never> {
    let page = Task { await service.poll(request) }
    try await waitUntil { service.progress[request.key] != nil }
    return page
  }

  private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<300 where !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition())
  }

  private func withService(
    library: EpisodeAvailability = .notOnServer, clock: TrialClock = TrialClock(),
    rule: EpisodeTrialRule? = EpisodeTrialRule(sites: [7], quality: "WEB-DL", include: "WEB", customWords: "test words"),
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
      access_token: "trial-fixture", token_type: "bearer", super_user: FlexibleBool(true),
      permissions: nil, user_id: 81, user_name: "fixture", avatar: nil)
    api.replaceSessionForTesting(baseURL: "https://episode-trial.local", token: token.access_token, currentUser: token)
    api.settings = GlobalSettings(BACKEND_VERSION: "v3.2.6")
    let availability = availability ?? { _ in library }
    let service = sleep.map { sleep in
      EpisodeTrialService(api: api, defaults: defaults, now: { clock.now }, sleep: sleep, availability: availability)
    } ?? EpisodeTrialService(api: api, defaults: defaults, now: { clock.now }, availability: availability)
    defer { service.tearDown() }
    if let rule { try service.saveRule(rule) }
    let request = try XCTUnwrap(EpisodeTrialRequest(
      media: MediaInfo(tmdb_id: 91, title: "试看测试", type: "电视剧"),
      episode: MoviePilotEpisode(TmdbEpisode(id: 234, episodeNumber: 5), season: 2, index: 4)
    ))
    try await body(api, service, defaults, request)
  }
}

/// 轮询（页面和后台跟踪）的等待按步骤编排：挂起到被取消，或执行一次服务器变化后立即返回；
/// 步骤用完后按 `then` 处理。定时清理的等待一直挂起，不干扰轮询的断言。被取消的等待不计入。
nonisolated private final class PollSleeper: @unchecked Sendable {
  enum Step {
    case suspend
    case proceed(@Sendable () -> Void)
  }

  private let lock = NSLock()
  private var requested: [Duration] = []
  private var steps: [Step]
  private let rest: Step

  init(_ steps: [Step], then rest: Step = .suspend) {
    self.steps = steps
    self.rest = rest
  }

  convenience init(onPoll: @escaping @Sendable () -> Void) {
    self.init([], then: .proceed(onPoll))
  }

  var pollDelays: [Duration] { lock.withLock { requested } }

  var sleep: EpisodeTrialService.Sleep {
    { [self] delay in
      try Task.checkCancellation()
      let polls = [EpisodeTrialService.activePollInterval, EpisodeTrialService.formalPollInterval]
      guard polls.contains(delay) else {
        try await Task.sleep(for: .seconds(3600))
        return
      }
      let step = lock.withLock { () -> Step in
        requested.append(delay)
        return steps.isEmpty ? rest : steps.removeFirst()
      }
      switch step {
      case .suspend: try await Task.sleep(for: .seconds(3600))
      case .proceed(let change): change()
      }
    }
  }
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

/// 第一次等待立即返回，之后挂起到被取消，测试可以确定地触发一轮定时清理。
nonisolated private final class CleanupSleeper: @unchecked Sendable {
  private let lock = NSLock()
  private var requested: [Duration] = []

  var delays: [Duration] { lock.withLock { requested } }

  var sleep: EpisodeTrialService.Sleep {
    { [self] delay in
      let first = lock.withLock { () -> Bool in
        requested.append(delay)
        return requested.count == 1
      }
      if !first { try await Task.sleep(for: .seconds(3600)) }
    }
  }
}

@MainActor
private final class TrialClock {
  private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)

  func advance(_ seconds: TimeInterval) { now += seconds }
}

nonisolated private final class EpisodeTrialURLProtocol: URLProtocol, @unchecked Sendable {
  static let fixture = EpisodeTrialFixture()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "episode-trial.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    do {
      let body = try Self.fixture.respond(to: request)
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

nonisolated private final class EpisodeTrialFixture: @unchecked Sendable {
  enum Mode {
    case initial, pausedFormal, missingFormal, reuse, downloading, organizing, transferred
    case noResource, externallyEdited, lostSearchReceipt
    case lostCreate, searchNotReceived, batchFailed, existingDownload, existingDownloadUnconfirmed
    case normalizesWrites, transferredUnderRecognizedTitle, formalEndedOrganized, transferFailed
  }

  struct Values: Equatable {
    var season: Int?
    var start: Int?
    var total: Int?
    var include: String?
    var bestVersion: Int?
    var fullPack: Int?
    var quality: String?

    init(season: Int?, start: Int?, total: Int?, include: String?, bestVersion: Int?, fullPack: Int?, quality: String?) {
      self.season = season
      self.start = start
      self.total = total
      self.include = include
      self.bestVersion = bestVersion
      self.fullPack = fullPack
      self.quality = quality
    }

    init(_ row: [String: Any]) {
      self.init(
        season: row["season"] as? Int, start: row["start_episode"] as? Int, total: row["total_episode"] as? Int,
        include: row["include"] as? String, bestVersion: row["best_version"] as? Int,
        fullPack: row["best_version_full"] as? Int, quality: row["quality"] as? String)
    }
  }

  private let lock = NSLock()
  private let batchID = "0123456789abcdef0123456789abcdef"
  private let newSubscriptionBatchID = "fedcba9876543210fedcba9876543210"
  private var mode = Mode.initial
  private var temporary: [String: Any]?
  private var placeholder: [String: Any]?
  private var requests: [String] = []
  private var totalRequests = 0
  private var created: Values?
  private var searched: Values?

  var mutations: [String] { lock.withLock { requests } }
  /// 读和写都算，用来证明某条路径完全没有访问服务器。
  var requestCount: Int { lock.withLock { totalRequests } }
  var createdValues: Values? { lock.withLock { created } }
  var searchValues: Values? { lock.withLock { searched } }

  func reset() {
    lock.withLock {
      mode = .initial
      temporary = nil
      placeholder = nil
      requests = []
      totalRequests = 0
      created = nil
      searched = nil
    }
  }

  func setMode(_ mode: Mode) { lock.withLock { self.mode = mode } }

  /// 发起方中断后留下的占位订阅：拒绝所有资源，与目标同季。
  func setPlaceholder(marker: String) {
    lock.withLock {
      placeholder = [
        "id": 90, "name": "试看测试", "type": "电视剧", "season": 2, "media_source": "tmdb", "media_id": "91",
        "username": "fixture", "state": "R", "include": "(?!)", "filter": marker,
      ]
    }
  }

  func respond(to request: URLRequest) throws -> Data {
    try lock.withLock {
      let method = request.httpMethod ?? "GET"
      let path = request.url?.path.split(separator: "/").dropFirst(2).joined(separator: "/") ?? ""
      let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
      let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
      totalRequests += 1
      if method != "GET" { requests.append("\(method) \(path)") }
      let response = try responseValue(method: method, path: path, query: query, request: request)
      return try JSONSerialization.data(withJSONObject: response)
    }
  }

  private func responseValue(
    method: String, path: String, query: [String: String], request: URLRequest
  ) throws -> Any {
    let formal: [String: Any] = [
      "id": 81, "name": "试看测试", "type": "电视剧", "season": 2,
      "media_source": "tmdb", "media_id": "91", "state": mode == .pausedFormal ? "S" : "R"
    ]
    let accepted = ["success": true]
    let terminal = [
      .downloading, .organizing, .transferred, .noResource, .externallyEdited, .batchFailed,
      .transferredUnderRecognizedTitle, .transferFailed,
    ].contains(mode)
    let earlierDownload = [.existingDownload, .existingDownloadUnconfirmed].contains(mode)
    let submitted = [.downloading, .organizing, .transferred, .transferredUnderRecognizedTitle, .transferFailed]
      .contains(mode)
    let history: [String: Any] = [
      "id": 2, "title": "MP 识别标题", "media_source": "tmdb", "media_id": "91", "seasons": "S02", "episodes": "E05",
      "download_hash": "target-hash", "note": ["subscription_download": ["subscription_id": 81]]
    ]

    let formalDownload: [String: Any] = [
      "id": 6, "title": "MP 识别标题", "media_source": "tmdb", "media_id": "91", "seasons": "S02",
      "episodes": "E05", "download_hash": "formal-hash",
    ]

    switch (method, path) {
    case ("GET", "subscribe"):
      if mode == .pausedFormal || (mode == .reuse && !requests.isEmpty) { return [formal] }
      if submitted || [.missingFormal, .formalEndedOrganized].contains(mode) { return [] as [[String: Any]] }
      var rows = [placeholder].compactMap { $0 }
      if var temporary {
        if mode == .externallyEdited { temporary["quality"] = "BluRay" }
        rows.append(temporary)
      }
      return rows
    case ("POST", "subscribe"):
      if mode == .reuse { return ["success": true, "message": "订阅已存在", "data": ["id": 81]] as [String: Any] }
      if mode == .lostCreate { throw URLError(.timedOut) }
      var fields = try body(request)
      created = Values(fields)
      fields["id"] = 81
      fields["username"] = "fixture"
      fields["state"] = "N"
      // MoviePilot 为新订阅安排一分钟后的自动搜索；暂停后这条任务会被跳过。
      fields["execution_status"] = ["source": "new", "batch_id": newSubscriptionBatchID]
      // 后端把未提交的列表字段存成空列表。
      if mode == .normalizesWrites { fields["filter_groups"] = [] as [String] }
      temporary = fields
      return ["success": true, "message": "新增订阅成功", "data": ["id": 81]] as [String: Any]
    case ("GET", "subscribe/81"):
      return mode == .reuse ? formal : temporary ?? [:]
    case ("PUT", "subscribe/status/81"):
      temporary?["state"] = "S"
      return accepted
    case ("PUT", "subscribe"):
      for (key, value) in try body(request) {
        let normalized = mode == .normalizesWrites && value is NSNull && ["sites", "filter_groups"].contains(key)
        temporary?[key] = normalized ? [] as [Any] : value
      }
      return accepted
    case ("POST", "subscribe/search/81"):
      if mode == .searchNotReceived { throw URLError(.timedOut) }
      searched = temporary.map(Values.init)
      temporary?["execution_status"] = ["source": "manual", "batch_id": batchID]
      if mode == .lostSearchReceipt { throw URLError(.networkConnectionLost) }
      return [
        "success": true,
        "data": ["batch_id": batchID, "batch_ids": [batchID], "single": true, "target_count": 1] as [String: Any]
      ] as [String: Any]
    case ("GET", "subscribe/execution/batches/\(batchID)"):
      return [
        "batch_id": batchID, "state": mode == .batchFailed ? "failed" : terminal ? "completed" : "running",
        "total_count": 1, "finished_count": terminal && mode != .batchFailed ? 1 : 0,
        "download_counts": ["submitted": submitted ? 1 : 0]
      ] as [String: Any]
    case ("PUT", let path) where path.hasPrefix("subscribe/execution/batches/") && path.hasSuffix("/cancel"):
      return accepted
    case ("DELETE", "subscribe/81"):
      temporary = nil
      return accepted
    case ("DELETE", "subscribe/90"):
      placeholder = nil
      return accepted
    case ("GET", "history/download"):
      if mode == .formalEndedOrganized { return [formalDownload] }
      if earlierDownload {
        return [[
          "id": 5, "media_source": "tmdb", "media_id": "91", "seasons": "S02", "episodes": "E05",
          "download_hash": "earlier-hash",
        ] as [String: Any]]
      }
      guard submitted else { return [] as [[String: Any]] }
      var otherSeason = history
      otherSeason["id"] = 3
      otherSeason["seasons"] = "S01"
      otherSeason["download_hash"] = "other-hash"
      return [otherSeason, history]
    case ("GET", "download/clients"):
      guard earlierDownload else { return [["name": "fixture-client", "type": "qbittorrent"]] }
      return [["name": "offline-client", "type": "qbittorrent"], ["name": "fixture-client", "type": "qbittorrent"]]
    case ("GET", "download"):
      if query["name"] == "offline-client" { throw URLError(.cannotConnectToHost) }
      if mode == .existingDownload { return [["hash": "earlier-hash", "progress": 30]] }
      guard mode == .downloading else { return [] as [[String: Any]] }
      return [["hash": "target-hash", "progress": 42]]
    case ("GET", "transfer/queue"):
      guard mode == .organizing else { return [] as [[String: Any]] }
      return [["tasks": [["downloader": "fixture-client", "download_hash": "target-hash"]]]]
    case ("GET", "history/transfer"):
      var transfer = history
      transfer["status"] = true
      if mode == .formalEndedOrganized {
        var organized = formalDownload
        organized["status"] = true
        return ["success": true, "data": ["list": [organized]]] as [String: Any]
      }
      if mode == .transferFailed {
        transfer["status"] = false
        return ["success": true, "data": ["list": [transfer]]] as [String: Any]
      }
      let found = mode == .transferred
        || (mode == .transferredUnderRecognizedTitle && query["title"] == "MP 识别标题")
      return ["success": true, "data": ["list": found ? [transfer] : []]] as [String: Any]
    default:
      throw URLError(.unsupportedURL)
    }
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
