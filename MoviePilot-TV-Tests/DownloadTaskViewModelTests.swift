import Foundation
import XCTest

@testable import MoviePilot_TV

private enum DownloadTaskViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor DownloadTaskAsyncGate {
  private var isOpen = false

  func wait() async {
    while !isOpen {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func open() {
    isOpen = true
  }
}

private func withTimeout<T: Sendable>(
  _ description: String,
  seconds: TimeInterval = 2,
  operation: @escaping @Sendable () async -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw DownloadTaskViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

@MainActor
final class DownloadTaskViewModelTests: XCTestCase {
  func testIndependentPickerLoadCannotPublishAfterRapidTabRoundTrip() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let requestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "stale-picker-hash",
        title: "Stale Picker Task",
        username: "old-user",
        progress: 10
      ),
      forClient: "old",
      waitFor: requestGate
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"
    let pickerLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }
    defer { pickerLoadTask.cancel() }

    try await withTimeout("picker request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old")
    }

    viewModel.setPresentationActive(false)
    viewModel.setPresentationActive(true)
    await requestGate.open()
    try await withTimeout("stale picker load to finish") {
      await pickerLoadTask.value
    }

    XCTAssertTrue(
      viewModel.downloads.isEmpty,
      "切走再快速切回后，旧 Picker Task 不能把隐藏期间的下载行写回"
    )
  }

  func testStalePickerFailuresCannotPublishAfterRapidTabRoundTrip() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let requestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["old"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      Array(repeating: (json: "{}", gate: requestGate), count: 6),
      forClient: "old",
      statusCode: 500
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.loadClientsIfNeeded()
    XCTAssertEqual(viewModel.selectedClient, "old")
    let staleTasks = (0..<6).map { _ in
      Task { @MainActor in await viewModel.loadDownloads() }
    }
    defer { staleTasks.forEach { $0.cancel() } }

    try await withTimeout("all stale picker requests to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old", count: 6)
    }

    viewModel.setPresentationActive(false)
    viewModel.setPresentationActive(true)
    await requestGate.open()
    for task in staleTasks {
      try await withTimeout("stale picker failure to finish") {
        await task.value
      }
    }

    XCTAssertNil(
      viewModel.errorMessage,
      "切走前的失败响应不能在快速切回后累计并发布旧错误"
    )
  }

  func testOlderClientLoadThatCompletesLaterDoesNotPublishOverCurrentClientDownloads()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let oldRequestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "old-hash", title: "Old Client Task", username: "old-user", progress: 10),
      forClient: "old",
      waitFor: oldRequestGate
    )
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "new-hash", title: "New Client Task", username: "new-user", progress: 80),
      forClient: "new"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"

    let oldLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }
    defer { oldLoadTask.cancel() }

    try await withTimeout("old client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old")
    }

    viewModel.selectedClient = "new"
    let newLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }

    try await withTimeout("new client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "new")
    }
    try await withTimeout("new client load to finish") {
      await newLoadTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "new")
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["new-hash"])

    await oldRequestGate.open()
    try await withTimeout("old client load to finish") {
      await oldLoadTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "new")
    XCTAssertEqual(
      viewModel.downloads.map(\.hash),
      ["new-hash"],
      "Late responses for an older downloader must not republish the list for the current downloader."
    )
  }

  func testPendingDownloadLoadDoesNotPublishAfterPermissionIsRestricted() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let requestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "stale-hash", title: "Stale Task", username: "old-user", progress: 10),
      forClient: "old",
      waitFor: requestGate
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"

    let oldLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }
    defer { oldLoadTask.cancel() }

    try await withTimeout("old client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old")
    }

    configureRestrictedUser(service)
    await viewModel.loadDownloads()

    XCTAssertTrue(viewModel.downloads.isEmpty)

    await requestGate.open()
    try await withTimeout("old client load to finish") {
      await oldLoadTask.value
    }

    XCTAssertTrue(
      viewModel.downloads.isEmpty,
      "Late download responses must not repopulate state after the user loses manage access."
    )
  }

  func testDownloadVisibilityMatchesWebOwnerFilter() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let payload = """
      [
        {"hash":"userid-match","userid":"download-manager","username":"legacy-name"},
        {"hash":"username-match","userid":"other-user","username":"download-manager"},
        {"hash":"foreign","userid":"other-user","username":"other-user"},
        {"hash":"ownerless"}
      ]
      """
    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [(payload, nil), (payload, nil)],
      forClient: "same"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "same"
    await viewModel.loadDownloads()

    XCTAssertEqual(viewModel.downloads.compactMap(\.hash), ["userid-match", "username-match"])

    configureManageUser(service, superUser: true)
    await viewModel.loadDownloads()

    XCTAssertEqual(
      Set(viewModel.downloads.compactMap(\.hash)),
      Set(["userid-match", "username-match", "foreign", "ownerless"])
    )
  }

  func testOlderClientLoadThatCompletesLaterDoesNotMutateCurrentClientDownloadWithSameId()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let oldRequestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "shared-hash", title: "Shared Task", username: "same-user", state: "paused",
        progress: 10),
      forClient: "old",
      waitFor: oldRequestGate
    )
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "shared-hash", title: "Shared Task", username: "same-user", state: "downloading",
        progress: 80),
      forClient: "new"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"

    let oldLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }
    defer { oldLoadTask.cancel() }

    try await withTimeout("old client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old")
    }

    viewModel.selectedClient = "new"
    let newLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }

    try await withTimeout("new client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "new")
    }
    try await withTimeout("new client load to finish") {
      await newLoadTask.value
    }

    XCTAssertEqual(viewModel.downloads.map(\.hash), ["shared-hash"])
    XCTAssertEqual(viewModel.downloads.first?.state, "downloading")
    XCTAssertEqual(viewModel.downloads.first?.progress, 80)

    await oldRequestGate.open()
    try await withTimeout("old client load to finish") {
      await oldLoadTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "new")
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["shared-hash"])
    XCTAssertEqual(
      viewModel.downloads.first?.state,
      "downloading",
      "Late responses for an older downloader must not mutate the current downloader row state."
    )
    XCTAssertEqual(
      viewModel.downloads.first?.progress,
      80,
      "Late responses for an older downloader must not mutate the current downloader row progress."
    )
  }

  func testOlderLoadForSameClientThatCompletesLaterDoesNotMutateCurrentDownload()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let olderRequestGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "shared-hash", title: "Shared Task", username: "same-user", state: "paused",
            progress: 10),
          olderRequestGate
        ),
        (
          downloadPayload(
            hash: "shared-hash", title: "Shared Task", username: "same-user",
            state: "downloading", progress: 80),
          nil
        ),
      ],
      forClient: "same"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "same"

    let olderLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }
    defer { olderLoadTask.cancel() }

    try await withTimeout("first same-client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "same", count: 1)
    }

    let newerLoadTask = Task { @MainActor in
      await viewModel.loadDownloads()
    }

    try await withTimeout("second same-client request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "same", count: 2)
    }
    try await withTimeout("second same-client load to finish") {
      await newerLoadTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "same")
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["shared-hash"])
    XCTAssertEqual(viewModel.downloads.first?.state, "downloading")
    XCTAssertEqual(viewModel.downloads.first?.progress, 80)

    await olderRequestGate.open()
    try await withTimeout("first same-client load to finish") {
      await olderLoadTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "same")
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["shared-hash"])
    XCTAssertEqual(
      viewModel.downloads.first?.state,
      "downloading",
      "Late responses for an older request from the same downloader must not mutate current row state."
    )
    XCTAssertEqual(
      viewModel.downloads.first?.progress,
      80,
      "Late responses for an older request from the same downloader must not mutate current row progress."
    )
  }

  func testDownloadsJSONSequenceFailsAfterConfiguredResponsesAreConsumed()
    async throws
  {
    await DownloadTaskURLProtocol.stub.reset()
    let firstPayload = downloadPayload(
      hash: "first-hash", title: "First Task", username: "user", progress: 10)
    let secondPayload = downloadPayload(
      hash: "second-hash", title: "Second Task", username: "user", progress: 80)
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (firstPayload, nil),
        (secondPayload, nil),
      ],
      forClient: "same"
    )

    let request = try XCTUnwrap(
      URL(string: "http://download-tests.local/api/v1/download/?name=same")
    ).absoluteURL
    let urlRequest = URLRequest(url: request)

    _ = try await DownloadTaskURLProtocol.stub.response(for: urlRequest)
    _ = try await DownloadTaskURLProtocol.stub.response(for: urlRequest)

    do {
      _ = try await DownloadTaskURLProtocol.stub.response(for: urlRequest)
      XCTFail("Expected the sequence stub to fail after all configured responses are consumed.")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .unsupportedURL)
    }
  }

  func testInitialClientsFailureIsRetriedOnNextPollAndRecovers() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSONSequence([
      (json: "[]", statusCode: 500),
      (json: clientsPayload(["qbittorrent"]), statusCode: 200),
    ])
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "recovered-hash",
        title: "Recovered Task",
        username: "user",
        progress: 42
      ),
      forClient: "qbittorrent"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertFalse(viewModel.clientsLoadFailed)
    XCTAssertEqual(viewModel.clients.map(\.name), ["qbittorrent"])
    XCTAssertEqual(viewModel.selectedClient, "qbittorrent")
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["recovered-hash"])
    let clientsRequestCount = await DownloadTaskURLProtocol.stub.clientsRequestCount()
    XCTAssertEqual(
      clientsRequestCount,
      2,
      "The failed first clients load must be retried before downloads can load."
    )
  }

  func testFirstLoadShowsLoadingThenPersistentFailureUntilTheFirstTaskListArrives() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "qbittorrent", statusCode: 500)

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    XCTAssertEqual(viewModel.pendingLoadState, .loading, "还没请求时不能先显示「暂无下载任务」")

    await viewModel.initialLoad()
    XCTAssertEqual(viewModel.pendingLoadState, .failed, "第一次结果前请求失败：显示失败文字，轮询继续重试")
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "qbittorrent", statusCode: 500)
    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.pendingLoadState, .failed, "重试仍失败时失败文字一直保留，不会退回转圈")

    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "qbittorrent")
    await viewModel.loadDownloads()
    XCTAssertNil(viewModel.pendingLoadState)
    XCTAssertTrue(viewModel.downloads.isEmpty, "真拿到空列表后才显示「暂无下载任务」")
  }

  func testFirstLoadFailureBelongsToTheDownloaderThatFailed() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["a", "b"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "a", statusCode: 500)

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()
    XCTAssertEqual(viewModel.selectedClient, "a")
    XCTAssertEqual(viewModel.pendingLoadState, .failed)

    viewModel.selectedClient = "b"
    XCTAssertEqual(viewModel.pendingLoadState, .loading, "切到别的下载器后不沿用上一个下载器的失败文字")
  }

  func testStaleFailureFromPreviousDownloaderDoesNotShowWhileNewDownloaderLoads() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let aGate = DownloadTaskAsyncGate()
    let bGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["a", "b"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "a", statusCode: 500, waitFor: aGate)
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "b", waitFor: bGate)

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    let aTask = Task { @MainActor in await viewModel.initialLoad() }
    defer { aTask.cancel() }
    try await withTimeout("a request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "a")
    }

    viewModel.selectedClient = "b"
    let bTask = Task { @MainActor in await viewModel.loadDownloads() }
    defer { bTask.cancel() }
    try await withTimeout("b request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "b")
    }

    await aGate.open()
    try await withTimeout("stale a load to finish") { await aTask.value }
    XCTAssertEqual(viewModel.pendingLoadState, .loading, "旧下载器晚到的失败不能显示到正在加载的新下载器上")

    await bGate.open()
    try await withTimeout("b load to finish") { await bTask.value }
    XCTAssertNil(viewModel.pendingLoadState)
  }

  func testSwitchingAfterASuccessfulLoadShowsPendingStateUntilTheNewDownloaderLoads() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["a", "b"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(hash: "a-hash", title: "A Task", username: "user", progress: 10),
      forClient: "a"
    )
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "b", statusCode: 500)

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()
    XCTAssertNil(viewModel.pendingLoadState)
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["a-hash"])

    viewModel.selectedClient = "b"
    XCTAssertEqual(
      viewModel.pendingLoadState, .loading,
      "b 还没拿到结果：转圈，不能显示「暂无下载任务」或 a 的任务")

    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.pendingLoadState, .failed, "b 读取失败时显示失败文字")

    viewModel.selectedClient = "a"
    XCTAssertNil(viewModel.pendingLoadState, "切回已有结果的 a，照常显示 a 的列表")
  }

  func testStaleFailureFromPreviousDownloaderDoesNotCountTowardFailureNotice() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let aGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["a", "b"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "a", statusCode: 500, waitFor: aGate)
    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "b", statusCode: 500)

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    let aTask = Task { @MainActor in await viewModel.initialLoad() }
    defer { aTask.cancel() }
    try await withTimeout("a request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "a")
    }

    // b 连续失败 5 次：还差 1 次才弹提示。
    viewModel.selectedClient = "b"
    for _ in 0..<5 {
      await viewModel.loadDownloads()
    }
    XCTAssertNil(viewModel.errorMessage)

    await aGate.open()
    try await withTimeout("stale a load to finish") { await aTask.value }
    XCTAssertNil(viewModel.errorMessage, "旧下载器晚到的失败不能计入当前下载器的连续失败次数")
    XCTAssertEqual(viewModel.pendingLoadState, .failed)
  }

  func testFirstLoadStateIsNilWithoutDownloadersOrWhenDownloaderListFails() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON("[]")
    let noDownloaders = DownloadTaskViewModel(apiService: service)
    await noDownloaders.initialLoad()
    XCTAssertNil(noDownloaders.pendingLoadState, "没有下载器时不会再请求任务列表，不能一直转圈")

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON("[]", statusCode: 500)
    let clientsFailed = DownloadTaskViewModel(apiService: service)
    await clientsFailed.initialLoad()
    XCTAssertTrue(clientsFailed.clientsLoadFailed)
    XCTAssertNil(clientsFailed.pendingLoadState, "下载器列表失败沿用原有的失败文字")
  }

  func testPollingFailuresNotifyOncePerSixConsecutiveFailuresAndResetOnSuccess() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      Array(
        repeating: (json: "{}", gate: nil),
        count: 6
      ),
      forClient: "qbittorrent",
      statusCode: 500
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertNil(viewModel.errorMessage)
    for _ in 0..<4 {
      await viewModel.loadDownloads()
    }
    XCTAssertNil(viewModel.errorMessage, "First five consecutive failures must stay silent.")
    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.errorMessage, "下载任务刷新失败，正在自动重试。")

    viewModel.errorMessage = nil
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      Array(
        repeating: (json: "{}", gate: nil),
        count: 6
      ),
      forClient: "qbittorrent",
      statusCode: 500
    )
    for _ in 0..<5 {
      await viewModel.loadDownloads()
    }
    XCTAssertNil(viewModel.errorMessage)
    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.errorMessage, "下载任务刷新失败，正在自动重试。")

    viewModel.errorMessage = nil
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "recovered-hash",
        title: "Recovered Task",
        username: "user",
        progress: 10
      ),
      forClient: "qbittorrent"
    )
    await viewModel.loadDownloads()
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["recovered-hash"])
  }

  func testDownloadActionFailureNotifiesImmediately() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "action-hash",
            title: "Action Task",
            username: "user",
            progress: 30
          ),
          nil
        ),
        ("{\"success\":false,\"message\":\"下载器不可用\"}", nil),
      ],
      forClient: "qbittorrent"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()
    XCTAssertEqual(viewModel.downloads.map(\.hash), ["action-hash"])

    let stopped = await viewModel.stopDownload(
      clientName: "qbittorrent",
      hash: "action-hash"
    )

    XCTAssertFalse(stopped)
    XCTAssertEqual(viewModel.errorMessage, "下载器不可用")
  }

  func testSameDownloadRefreshUpdatesLatestMetadataForExistingRow() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "shared-hash",
            title: "Old Torrent Title",
            name: "Old Recognized Name",
            mediaTitle: "Old Media Title",
            mediaImage: "/old-backdrop.jpg",
            seasonEpisode: "S01E01",
            username: "same-user",
            progress: 10
          ),
          nil
        ),
        (
          downloadPayload(
            hash: "shared-hash",
            title: "New Torrent Title",
            name: "New Recognized Name",
            mediaTitle: "New Media Title",
            mediaImage: "/new-backdrop.jpg",
            seasonEpisode: "S01E02",
            username: "same-user",
            progress: 80
          ),
          nil
        ),
      ],
      forClient: "same"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "same"

    await viewModel.loadDownloads()
    let firstRow = try XCTUnwrap(viewModel.downloads.first)
    XCTAssertEqual(firstRow.title, "Old Torrent Title")
    XCTAssertEqual(firstRow.media?.title, "Old Media Title")

    await viewModel.loadDownloads()

    let refreshedRow = try XCTUnwrap(viewModel.downloads.first)
    XCTAssertTrue(firstRow === refreshedRow)
    XCTAssertEqual(refreshedRow.title, "New Torrent Title")
    XCTAssertEqual(refreshedRow.name, "New Recognized Name")
    XCTAssertEqual(refreshedRow.media?.title, "New Media Title")
    XCTAssertEqual(refreshedRow.media?.image, "/new-backdrop.jpg")
    XCTAssertEqual(refreshedRow.season_episode, "S01E02")
    XCTAssertEqual(refreshedRow.progress, 80)
  }

  /// 下载卡片的季集一律中文：优先 media 的季、集，两项都缺时退回 season_episode；
  /// 电影或读不出季集时整段不显示。
  func testDownloadCardSeasonEpisodeIsChinese() throws {
    let cases: [(json: String, expected: String?)] = [
      // media 的季集优先于 season_episode。
      (
        #"{"hash":"h1","season_episode":"S09E09","media":{"season":"S01","episode":"E02"}}"#,
        "1季 2集"
      ),
      // 一个文件多集。
      (
        #"{"hash":"h2","season_episode":"S02E05-E07","media":{"season":"S02","episode":"E05-E07"}}"#,
        "2季 5-7集"
      ),
      // 订阅补齐缺失集：后端 format_ranges 的顿号并列多区间，media 与 season_episode 两条入口都要中文化。
      (
        #"{"hash":"h9","season_episode":"S01E01","media":{"season":"S01","episode":"E01-E03、E05"}}"#,
        "1季 1-3、5集"
      ),
      (#"{"hash":"h10","season_episode":"S01 E01、E03","media":{"title":"某剧"}}"#, "1季 1、3集"),
      // media 没有季集时退回 season_episode。
      (#"{"hash":"h3","season_episode":"S03E04","media":{"title":"某剧"}}"#, "3季 4集"),
      (#"{"hash":"h4","season_episode":"S03E04"}"#, "3季 4集"),
      // 只有季。
      (#"{"hash":"h5","media":{"season":"S01","episode":""}}"#, "1季"),
      // 电影：季集都是空串，不能显示成空白或英文。
      (#"{"hash":"h6","season_episode":"","media":{"season":"","episode":""}}"#, nil),
      (#"{"hash":"h7","season_episode":"  ","media":{"season":" ","episode":" "}}"#, nil),
      (#"{"hash":"h8"}"#, nil),
    ]

    for (json, expected) in cases {
      let row = try XCTUnwrap(decodeDownloads("[\(json)]").first, json)
      XCTAssertEqual(row.seasonEpisodeDisplay, expected, json)
    }
  }

  func testOldRowsCannotSendActionsAfterDownloaderSelectionChanges() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      downloadPayload(
        hash: "shared-hash", title: "Old Client Task", username: "old-user", progress: 10),
      forClient: "old"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"
    await viewModel.loadDownloads()

    XCTAssertEqual(viewModel.loadedClient, "old")
    XCTAssertTrue(viewModel.canOperateDownloads)
    let oldRequestCountBeforeSwitch = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "old")
    XCTAssertEqual(oldRequestCountBeforeSwitch, 1)

    viewModel.selectedClient = "new"

    XCTAssertFalse(viewModel.canOperateDownloads)
    let didStop = await viewModel.stopDownload(clientName: "old", hash: "shared-hash")
    let didStart = await viewModel.startDownload(clientName: "old", hash: "shared-hash")
    await viewModel.deleteDownload(clientName: "old", hash: "shared-hash")

    XCTAssertFalse(didStop)
    XCTAssertFalse(didStart)
    let oldRequestCountAfterActions = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "old")
    let newRequestCountAfterActions = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "new")
    XCTAssertEqual(oldRequestCountAfterActions, 1)
    XCTAssertEqual(newRequestCountAfterActions, 0)
  }

  func testMalformedNonEmptyActionResponseFailsClosedForDownloadActions() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "h1", title: "Task", username: "download-manager", progress: 10),
          nil
        ),
        // 非空但畸形的 2xx body：暂停与删除都必须失败关闭，不得翻转状态或移除仍存在的任务。
        ("not-json", nil),
        ("not-json", nil),
      ],
      forClient: "client"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "client"
    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.downloads.count, 1)

    let didStop = await viewModel.stopDownload(clientName: "client", hash: "h1")
    XCTAssertFalse(didStop)
    XCTAssertEqual(
      viewModel.downloads.count, 1,
      "A malformed action response must not flip the download state."
    )

    await viewModel.deleteDownload(clientName: "client", hash: "h1")
    XCTAssertEqual(
      viewModel.downloads.count, 1,
      "A malformed delete response must not remove a task that still exists."
    )
  }

  func testEmptyActionResponseRemainsCompatibleSuccess() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "h1", title: "Task", username: "download-manager", progress: 10),
          nil
        ),
        // 零字节空 body 按旧契约兼容为删除成功。
        ("", nil),
      ],
      forClient: "client"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "client"
    await viewModel.loadDownloads()
    XCTAssertEqual(viewModel.downloads.count, 1)

    await viewModel.deleteDownload(clientName: "client", hash: "h1")
    XCTAssertEqual(
      viewModel.downloads.count, 0,
      "An empty response body must remain a compatible success for delete."
    )
  }

  func testOlderClientDeleteThatCompletesLaterDoesNotRemoveCurrentClientDownloadWithSameHash()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let deleteGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSONSequence(
      [
        (
          downloadPayload(
            hash: "shared-hash", title: "Old Client Task", username: "old-user", progress: 10),
          nil
        ),
        (#"{"success": true, "message": "ok"}"#, deleteGate),
      ],
      forClient: "old"
    )

    service.baseURLForTesting = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel(apiService: service)
    viewModel.selectedClient = "old"
    await viewModel.loadDownloads()

    let deleteTask = Task { @MainActor in
      await viewModel.deleteDownload(clientName: "old", hash: "shared-hash")
    }
    defer { deleteTask.cancel() }

    try await withTimeout("old client delete request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old", count: 2)
    }
    let oldRequestCount = await DownloadTaskURLProtocol.stub.requestCount(clientName: "old")
    XCTAssertEqual(oldRequestCount, 2)

    viewModel.selectedClient = "new"
    viewModel.downloads = try decodeDownloads(
      downloadPayload(
        hash: "shared-hash", title: "New Client Task", username: "new-user", progress: 80)
    )

    await deleteGate.open()
    try await withTimeout("old client delete to finish") {
      await deleteTask.value
    }

    XCTAssertEqual(viewModel.selectedClient, "new")
    XCTAssertEqual(
      viewModel.downloads.map(\.hash),
      ["shared-hash"],
      "A delete response for an older downloader must not remove the current downloader row."
    )
    XCTAssertEqual(viewModel.downloads.first?.username, "new-user")
  }

  private func downloadPayload(
    hash: String,
    title: String,
    name: String? = nil,
    mediaTitle: String? = nil,
    mediaImage: String? = nil,
    seasonEpisode: String? = nil,
    userid: String = "download-manager",
    username: String,
    state: String = "downloading",
    progress: Int
  ) -> String {
    let recognizedName = name ?? title
    let mediaTitle = mediaTitle ?? title
    let mediaImage = mediaImage ?? "/download-backdrop.jpg"
    let seasonEpisode = seasonEpisode ?? "S01E01"
    return """
    [
      {
        "hash": "\(hash)",
        "title": "\(title)",
        "name": "\(recognizedName)",
        "state": "\(state)",
        "progress": \(progress),
        "season_episode": "\(seasonEpisode)",
        "media": {
          "title": "\(mediaTitle)",
          "image": "\(mediaImage)",
          "season": "S01",
          "episode": "E01"
        },
        "userid": "\(userid)",
        "username": "\(username)"
      }
    ]
    """
  }

  func testForbiddenDownloadListShowsPermissionStateAndRetriesOnReentry() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let previousSettings = service.settings
    defer { service.settings = previousSettings }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      #"{"detail":"用户权限不足"}"#,
      forClient: "qbittorrent",
      statusCode: 403
    )

    service.baseURLForTesting = "http://download-tests.local"
    service.tokenForTesting = "download-task-tests"
    configureManageUser(service, userId: 0)
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.11")

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertTrue(viewModel.downloadsPermissionDenied)
    XCTAssertTrue(viewModel.downloads.isEmpty)
    XCTAssertNil(viewModel.pendingLoadState)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.clients.map(\.name), ["qbittorrent"])

    let requestCountAfterForbidden = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterForbidden, 1)

    await viewModel.loadDownloads()
    let requestCountAfterPolling = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterPolling, 1, "权限拒绝后轮询不应继续请求 /download/")

    viewModel.setPresentationActive(false)
    viewModel.setPresentationActive(true)
    XCTAssertFalse(viewModel.downloadsPermissionDenied)

    await DownloadTaskURLProtocol.stub.setDownloadsJSON("[]", forClient: "qbittorrent")
    await viewModel.loadDownloads()

    XCTAssertFalse(viewModel.downloadsPermissionDenied)
    XCTAssertEqual(viewModel.loadedClient, "qbittorrent")
    let requestCountAfterReentry = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterReentry, 2)
  }

  func testForbiddenDownloadListFromProxyWithValidSessionKeepsRetryBehavior() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let previousSettings = service.settings
    defer { service.settings = previousSettings }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      #"{"detail":"blocked by proxy"}"#,
      forClient: "qbittorrent",
      statusCode: 403
    )

    service.baseURLForTesting = "http://download-tests.local"
    service.tokenForTesting = "download-task-tests"
    configureManageUser(service, userId: 0)
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.11")

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertFalse(
      viewModel.downloadsPermissionDenied,
      "token 有效但 403 不是 MoviePilot 权限文案时不能进入无下载管理权限状态"
    )
    XCTAssertEqual(viewModel.downloadsLoadFailedClient, "qbittorrent")
    XCTAssertEqual(viewModel.pendingLoadState, .failed)

    let requestCountAfterForbidden = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterForbidden, 1)

    await viewModel.loadDownloads()
    let requestCountAfterRetry = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterRetry, 2, "反代 403 仍按普通失败重试")
    XCTAssertFalse(viewModel.downloadsPermissionDenied)
  }

  func testAmbiguousAuthenticationProbeForbiddenKeepsRetryBehavior() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let previousSettings = service.settings
    defer { service.settings = previousSettings }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      "[]",
      forClient: "qbittorrent",
      statusCode: 403
    )
    await DownloadTaskURLProtocol.stub.setCurrentUserResponse(
      statusCode: 403,
      json: #"{"detail":"无法识别的认证响应"}"#
    )

    service.baseURLForTesting = "http://download-tests.local"
    service.tokenForTesting = "download-task-tests"
    configureManageUser(service, userId: 0)
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.11")

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertFalse(
      viewModel.downloadsPermissionDenied,
      "认证状态无法确认时不能进入无下载管理权限状态"
    )
    XCTAssertEqual(viewModel.downloadsLoadFailedClient, "qbittorrent")
    XCTAssertEqual(viewModel.pendingLoadState, .failed)

    let requestCountAfterForbidden = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterForbidden, 1)

    await viewModel.loadDownloads()
    let requestCountAfterRetry = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterRetry, 2, "无法确认认证状态时 403 仍按原有失败路径重试")
    XCTAssertFalse(viewModel.downloadsPermissionDenied)
  }

  func testForbiddenDownloadListOnOlderBackendKeepsRetryBehavior() async throws {
    try await assertForbiddenDownloadFallsBackToRetry(backendVersion: "v3.2.10")
  }

  func testForbiddenDownloadListWithoutBackendVersionKeepsRetryBehavior() async throws {
    try await assertForbiddenDownloadFallsBackToRetry(backendVersion: nil)
  }

  func testDownloadPermissionStateRequiresBackendVersion() {
    XCTAssertFalse(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: nil))
    XCTAssertFalse(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "v3.2.10"))
    XCTAssertFalse(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "v3.2.10-1"))
    XCTAssertFalse(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "garbage"))
    XCTAssertTrue(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "v3.2.11"))
    XCTAssertTrue(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "v3.2.11-1"))
    XCTAssertTrue(DownloadTaskViewModel.supportsDownloadPermissionState(backendVersion: "v3.3.0"))
  }

  private func assertForbiddenDownloadFallsBackToRetry(backendVersion: String?) async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(DownloadTaskURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(DownloadTaskURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    let previousSettings = service.settings
    defer {
      snapshot.restore(to: service)
      service.settings = previousSettings
    }

    await DownloadTaskURLProtocol.stub.reset()
    await DownloadTaskURLProtocol.stub.setClientsJSON(clientsPayload(["qbittorrent"]))
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      "[]",
      forClient: "qbittorrent",
      statusCode: 403
    )

    service.baseURLForTesting = "http://download-tests.local"
    service.tokenForTesting = "download-task-tests"
    configureManageUser(service, userId: 0)
    service.settings = backendVersion.map { GlobalSettings(BACKEND_VERSION: $0) }

    let viewModel = DownloadTaskViewModel(apiService: service)
    await viewModel.initialLoad()

    XCTAssertFalse(viewModel.downloadsPermissionDenied)
    XCTAssertEqual(viewModel.downloadsLoadFailedClient, "qbittorrent")
    XCTAssertEqual(viewModel.pendingLoadState, .failed)

    let requestCountAfterForbidden = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterForbidden, 1)

    await viewModel.loadDownloads()
    let requestCountAfterRetry = await DownloadTaskURLProtocol.stub.requestCount(
      clientName: "qbittorrent")
    XCTAssertEqual(requestCountAfterRetry, 2, "门禁不通过时 403 仍按原有失败路径重试")
    XCTAssertFalse(viewModel.downloadsPermissionDenied)
  }

  private func decodeDownloads(_ json: String) throws -> [DownloadingInfo] {
    try JSONDecoder().decode([DownloadingInfo].self, from: Data(json.utf8))
  }

  private func configureManageUser(
    _ service: APIService,
    superUser: Bool = false,
    userId: Int? = nil
  ) {
    service.currentUserForTesting = Token(
      access_token: "download-task-tests",
      token_type: "bearer",
      super_user: FlexibleBool(superUser),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_id: userId,
      user_name: "download-manager",
      avatar: nil
    )
  }

  private func configureRestrictedUser(_ service: APIService) {
    service.currentUserForTesting = Token(
      access_token: "download-task-restricted-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "download-restricted",
      avatar: nil
    )
  }

  private func clientsPayload(_ names: [String]) -> String {
    let items = names.map { name in
      """
      {"name":"\(name)","type":"qbittorrent","enabled":true}
      """
    }
    return "[" + items.joined(separator: ",") + "]"
  }
}

@MainActor
private struct DownloadTaskServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let accessTokenDefaults: String?
  let currentUser: Token?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  static func capture(service: APIService) -> DownloadTaskServiceSnapshot {
    DownloadTaskServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      accessTokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      currentUser: service.currentUser,
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
    )
  }

  func restore(to service: APIService) {
    service.baseURLForTesting = baseURL
    service.currentUserForTesting = currentUser

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }

    if let accessTokenDefaults {
      UserDefaults.standard.set(accessTokenDefaults, forKey: "accessToken")
    } else {
      UserDefaults.standard.removeObject(forKey: "accessToken")
    }

    restoreCredential(
      account: "currentUser",
      keychainValue: currentUserKeychain,
      defaultsValue: currentUserDefaults
    )
  }

  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(
        keychainValue,
        service: "MoviePilot-TV",
        account: account
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }

    if let defaultsValue {
      UserDefaults.standard.set(defaultsValue, forKey: account)
    } else {
      UserDefaults.standard.removeObject(forKey: account)
    }
  }
}

private struct DownloadTaskHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: DownloadTaskAsyncGate?
}

private actor DownloadTaskURLProtocolStub {
  private var responsesByClient: [String: [DownloadTaskHTTPStubResponse]] = [:]
  private var clientsResponses: [DownloadTaskHTTPStubResponse] = []
  private var requestedClients: [String] = []
  private var requestedClientsLoads = 0
  private var currentUserResponse = DownloadTaskHTTPStubResponse(
    statusCode: 200,
    data: Data(
      #"{"id":0,"name":"download-manager","is_superuser":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":true,"features":{"manage.downloading":false}}}"#
        .utf8
    ),
    gate: nil
  )

  func reset() {
    responsesByClient.removeAll()
    clientsResponses.removeAll()
    requestedClients.removeAll()
    requestedClientsLoads = 0
    currentUserResponse = DownloadTaskHTTPStubResponse(
      statusCode: 200,
      data: Data(
        #"{"id":0,"name":"download-manager","is_superuser":false,"permissions":{"discovery":false,"search":false,"subscribe":false,"manage":true,"features":{"manage.downloading":false}}}"#
          .utf8
      ),
      gate: nil
    )
  }

  func setCurrentUserResponse(statusCode: Int = 200, json: String) {
    currentUserResponse = DownloadTaskHTTPStubResponse(
      statusCode: statusCode,
      data: Data(json.utf8),
      gate: nil
    )
  }

  func setClientsJSON(_ json: String, statusCode: Int = 200) {
    clientsResponses = [
      DownloadTaskHTTPStubResponse(
        statusCode: statusCode,
        data: Data(json.utf8),
        gate: nil
      )
    ]
  }

  func setClientsJSONSequence(_ sequence: [(json: String, statusCode: Int)]) {
    clientsResponses = sequence.map { item in
      DownloadTaskHTTPStubResponse(
        statusCode: item.statusCode,
        data: Data(item.json.utf8),
        gate: nil
      )
    }
  }

  func setDownloadsJSON(
    _ json: String,
    forClient clientName: String,
    statusCode: Int = 200,
    waitFor gate: DownloadTaskAsyncGate? = nil
  ) {
    responsesByClient[clientName] = [
      DownloadTaskHTTPStubResponse(
        statusCode: statusCode,
        data: Data(json.utf8),
        gate: gate
      )
    ]
  }

  func setDownloadsJSONSequence(
    _ sequence: [(json: String, gate: DownloadTaskAsyncGate?)],
    forClient clientName: String,
    statusCode: Int = 200
  ) {
    responsesByClient[clientName] = sequence.map { item in
      DownloadTaskHTTPStubResponse(
        statusCode: statusCode,
        data: Data(item.json.utf8),
        gate: item.gate
      )
    }
  }

  func response(for request: URLRequest) async throws -> DownloadTaskHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    // `/download/` 返回 403 时 APIService 会先探测 `/user/current`。默认返回
    // 一个关闭 manage.downloading 的 manage 用户，让 403 成为已确认的业务拒绝；
    // 需要模拟“认证状态无法确认”的用例可覆盖这个响应。
    if components.path == "/api/v1/user/current" {
      return currentUserResponse
    }

    if components.path == "/api/v1/download/clients" {
      requestedClientsLoads += 1
      guard let response = clientsResponses.first else {
        throw URLError(.unsupportedURL)
      }
      clientsResponses.removeFirst()
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    }

    guard let clientName = components.queryItems?.first(where: { $0.name == "name" })?.value else {
      throw URLError(.badURL)
    }

    recordRequest(for: clientName)

    guard var responses = responsesByClient[clientName], let response = responses.first else {
      throw URLError(.unsupportedURL)
    }
    responses.removeFirst()
    if responses.isEmpty {
      responsesByClient.removeValue(forKey: clientName)
    } else {
      responsesByClient[clientName] = responses
    }

    if let gate = response.gate {
      await gate.wait()
    }

    return response
  }

  func waitForRequest(clientName: String) async {
    await waitForRequest(clientName: clientName, count: 1)
  }

  func waitForRequest(clientName: String, count: Int) async {
    while requestedClients.filter({ $0 == clientName }).count < count {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func requestCount(clientName: String) -> Int {
    requestedClients.filter { $0 == clientName }.count
  }

  func clientsRequestCount() -> Int {
    requestedClientsLoads
  }

  private func recordRequest(for clientName: String) {
    requestedClients.append(clientName)
  }
}

private final class DownloadTaskURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = DownloadTaskURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "download-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = DownloadTaskURLProtocolTaskContext(
      request: request,
      clientBox: DownloadTaskURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = DownloadTaskURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: DownloadTaskURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await DownloadTaskURLProtocol.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(request: context.request, stubResponse: stubResponse)
      } catch {
        guard !Task.isCancelled else { return }
        context.clientBox.fail(error)
      }
    }
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class DownloadTaskURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: DownloadTaskURLProtocolClientBox

  init(request: URLRequest, clientBox: DownloadTaskURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class DownloadTaskURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: DownloadTaskHTTPStubResponse) {
    guard let url = request.url else {
      fail(URLError(.badURL))
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: stubResponse.statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      fail(URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: stubResponse.data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
