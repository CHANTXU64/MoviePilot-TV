import Combine
import XCTest

@testable import MoviePilot_TV

private enum TransferHistoryViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor TransferHistoryAsyncGate {
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

private func withTransferHistoryTimeout<T: Sendable>(
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
      throw TransferHistoryViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

private func transferHistoryListJSON(ids: ClosedRange<Int>) -> String {
  let items = ids.map { id in
    #"{"id":\#(id),"title":"记录\#(id)","type":"电影","status":true}"#
  }.joined(separator: ",")
  return #"{"list":[\#(items)],"total":\#(ids.count)}"#
}

@MainActor
final class TransferHistoryViewModelTests: XCTestCase {
  func testAiRedoRequiresExplicitlyEnabledSetting() throws {
    let service = APIService.testingInstance()
    let viewModel = TransferHistoryViewModel(apiService: service)

    XCTAssertFalse(viewModel.isAiRedoEnabled)

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{}"#.utf8)
    )
    XCTAssertFalse(viewModel.isAiRedoEnabled)

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":null}"#.utf8)
    )
    XCTAssertFalse(viewModel.isAiRedoEnabled)

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":false}"#.utf8)
    )
    XCTAssertFalse(viewModel.isAiRedoEnabled)

    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )
    XCTAssertTrue(viewModel.isAiRedoEnabled)
  }

  func testSearchFetcherDoesNotRetainViewModelAfterSearchCompletes() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    weak var retainedViewModel: TransferHistoryViewModel?
    do {
      let viewModel = TransferHistoryViewModel(apiService: service)
      retainedViewModel = viewModel
      viewModel.search(with: "电影")
    }

    for _ in 0..<2_000 {
      guard retainedViewModel != nil else { break }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertNil(retainedViewModel)
  }

  func testSparseFileItemDoesNotRejectTransferHistoryPage() throws {
    let response = try JSONDecoder().decode(
      TransferHistoryResponse.self,
      from: Data(
        """
        {
          "list": [
            {
              "id": 1,
              "title": "完整记录",
              "status": true,
              "src_fileitem": {
                "name": "movie.mkv",
                "path": "/downloads/movie.mkv",
                "type": "file",
                "size": 1024
              },
              "dest_fileitem": {
                "name": "movie.mkv",
                "path": "/library/movie.mkv",
                "type": "file",
                "size": 1024
              }
            },
            {
              "id": 2,
              "title": "稀疏记录",
              "status": true,
              "src_fileitem": { "path": "/downloads/sparse.mkv" }
            },
            {
              "id": 3,
              "title": "空文件项",
              "status": false,
              "src_fileitem": null
            },
            {
              "id": 4,
              "title": "空对象文件项",
              "status": true,
              "src_fileitem": {}
            }
          ],
          "total": 4
        }
        """.utf8
      )
    )

    XCTAssertEqual(response.list.map(\.id), [1, 2, 3, 4])
    XCTAssertEqual(response.list[0].src_fileitem?.name, "movie.mkv")
    XCTAssertEqual(response.list[0].dest_fileitem?.path, "/library/movie.mkv")
    XCTAssertNil(response.list[1].src_fileitem)
    XCTAssertNil(response.list[2].src_fileitem)
    XCTAssertNil(response.list[3].src_fileitem)
  }

  func testPendingRefreshDoesNotPublishAfterPermissionIsRestricted() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let historyGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setHistoryGate(historyGate)

    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel(apiService: service)
    let refreshTask = Task { @MainActor in
      await viewModel.refresh()
    }
    defer { refreshTask.cancel() }

    try await withTransferHistoryTimeout("history request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(path: "/api/v1/history/transfer")
    }

    configureRestrictedUser(service)
    await viewModel.refresh()

    XCTAssertTrue(viewModel.items.isEmpty)

    await historyGate.open()
    try await withTransferHistoryTimeout("old history refresh to finish") {
      await refreshTask.value
    }

    XCTAssertTrue(
      viewModel.items.isEmpty,
      "Late transfer-history responses must not repopulate state after the user loses manage access."
    )
  }

  func testManageUserCanRefreshTransferHistory() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()

    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.refresh()

    XCTAssertEqual(viewModel.items.map(\.id), [10])
    XCTAssertEqual(viewModel.storageDict["local"], "本地")
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/history/transfer"))
    XCTAssertTrue(paths.contains("/api/v1/system/setting/public/Storages"))
  }

  func testPendingPollingDoesNotPublishAfterSearchChanges() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: .shared)
    defer { persistenceSnapshot.restore(to: .shared) }
    let service = APIService.testingInstance()

    await TransferHistoryURLProtocol.stub.reset()
    let historyGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setHistoryGate(historyGate)
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel(apiService: service)
    let pollingTask = Task { @MainActor in
      await viewModel.fetchLatest()
    }
    defer { pollingTask.cancel() }

    try await withTransferHistoryTimeout("polling request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(path: "/api/v1/history/transfer")
    }

    viewModel.search(with: "新查询")
    try await withTransferHistoryTimeout("new search results to publish") {
      while await MainActor.run(body: { viewModel.items.map { $0.id } }) != [20] {
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
      }
    }

    await historyGate.open()
    await pollingTask.value

    XCTAssertEqual(viewModel.items.map(\.id), [20])
  }

  func testAuthoritativeRefreshInvalidatesPollingThatReturnsDuringStorageLoad() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let oldPollGate = TransferHistoryAsyncGate()
    let storageGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setHistoryGate(oldPollGate)
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"旧轮询记录","type":"电影","status":true}],"total":1}"#.utf8)
    )
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel(apiService: service)
    let pollingTask = Task { @MainActor in
      await viewModel.fetchLatest()
    }
    defer { pollingTask.cancel() }
    try await withTransferHistoryTimeout("old polling request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(path: "/api/v1/history/transfer")
    }

    await TransferHistoryURLProtocol.stub.setHistoryGate(nil)
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"权威刷新记录","type":"电影","status":true}],"total":1}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setStorageGate(storageGate)
    let refreshTask = Task { @MainActor in
      await viewModel.refresh()
    }
    defer { refreshTask.cancel() }
    try await withTransferHistoryTimeout("authoritative storage request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(
        path: "/api/v1/system/setting/public/Storages"
      )
    }

    await oldPollGate.open()
    await pollingTask.value
    await storageGate.open()
    await refreshTask.value

    XCTAssertEqual(viewModel.items.map(\.title), ["权威刷新记录"])
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [20, 20])
  }

  func testPollingScanLimitFallbackRefreshesInsteadOfDroppingTail() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    // 初始已知项
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":999,"title":"已知记录","type":"电影","status":true}],"total":1}"#.utf8)
    )
    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.refresh()
    XCTAssertEqual(viewModel.items.map(\.id), [999])

    // 一次 101+ 条新增：页 1-5 各 20 条满页新记录，页 6 为 101-120，页 7 已知项，页 8 空
    var dataByPage: [Int: Data] = [:]
    for page in 1...5 {
      let start = (page - 1) * 20 + 1
      dataByPage[page] = Data(transferHistoryListJSON(ids: start...(start + 19)).utf8)
    }
    dataByPage[6] = Data(transferHistoryListJSON(ids: 101...120).utf8)
    dataByPage[7] =
      Data(#"{"list":[{"id":999,"title":"已知记录","type":"电影","status":true}],"total":1}"#.utf8)
    dataByPage[8] = Data(#"{"list":[],"total":0}"#.utf8)
    await TransferHistoryURLProtocol.stub.setHistoryResponseDataByPage(dataByPage)

    // 轮询扫满 5 页仍未遇到已知项：不得提交不完整前缀，必须回退权威刷新
    await viewModel.fetchLatest()
    // 回退 refresh 会把游标重置回第 1 页，首屏只加载第 1 页（Paginator 首屏一页 + 滚动加载）
    XCTAssertEqual(
      viewModel.items.map(\.id), Array(1...20),
      "应回退权威刷新而非提交前 100 条不完整前缀")

    // 滚动加载全部页：旧缺陷下游标已被推到第 7 页，第 101-120 条永远拿不到
    for _ in 0..<8 {
      guard let lastId = viewModel.items.last?.id else { break }
      await viewModel.loadMore(currentItemId: lastId)
    }

    let ids = Set(viewModel.items.map(\.id))
    XCTAssertEqual(ids.count, 121)
    XCTAssertTrue(
      Set(101...120).isSubset(of: ids), "第 101-120 条不应被扫描上限丢弃")
    XCTAssertTrue(ids.contains(999), "原有已知记录应保留")
  }

  func testLeavingStatusTabCancelsRefreshBeforeHistoryRequestStarts() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let storageGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setStorageGate(storageGate)
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let viewModel = TransferHistoryViewModel(apiService: service)
    let refreshTask = Task { @MainActor in
      await viewModel.refresh()
    }
    try await withTransferHistoryTimeout("storage request before leaving tab") {
      await TransferHistoryURLProtocol.stub.waitForRequest(
        path: "/api/v1/system/setting/public/Storages"
      )
    }

    refreshTask.cancel()
    viewModel.cancelRefresh()
    await storageGate.open()
    await refreshTask.value

    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertTrue(historyRequestCounts.isEmpty)
    XCTAssertFalse(viewModel.isFirstLoading)
  }

  func testDeleteTransferHistoryRequiresExplicitSuccess() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)
    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )

    let result = try await service.deleteTransferHistory(
      item: history,
      deleteSource: false,
      deleteDest: false
    )

    XCTAssertFalse(result.success)
  }

  func testTransferHistoryDeleteCannotStartTwiceWhileRequestIsRunning() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )
    let gate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setHistoryGate(gate)
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)
    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    let viewModel = TransferHistoryViewModel(apiService: service)

    let firstDelete = Task { @MainActor in
      await viewModel.deleteHistory(
        item: history,
        deleteSource: true,
        deleteDest: true,
        sourceSession: viewModel.captureMutationSession()
      )
    }
    defer { firstDelete.cancel() }
    try await withTransferHistoryTimeout("first delete request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(path: "/api/v1/history/transfer")
    }
    XCTAssertTrue(viewModel.isDeleting)

    await viewModel.deleteHistory(
      item: history,
      deleteSource: true,
      deleteDest: true,
      sourceSession: viewModel.captureMutationSession()
    )
    await viewModel.triggerAiRedo(
      for: history,
      sourceSession: viewModel.captureMutationSession()
    )
    let pendingPaths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertEqual(pendingPaths.filter { $0 == "/api/v1/history/transfer" }.count, 1)
    XCTAssertFalse(pendingPaths.contains("/api/v1/history/transfer/10/ai-redo"))

    await gate.open()
    try await withTransferHistoryTimeout("first delete request to finish") {
      await firstDelete.value
    }
    XCTAssertFalse(viewModel.isDeleting)
  }

  func testStatusOnlyMutationFingerprintChangeRefreshesAndRejectsDelete() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setDeleteResponse(
      Data(#"{"success":true}"#.utf8),
      gate: nil
    )
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let oldItem = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(
        #"{"id":10,"title":"History","type":"电影","src":"/downloads/movie.mkv","dest":"/library/movie.mkv","src_storage":"local","dest_storage":"local","mode":"move","status":false,"errmsg":"临时失败","src_fileitem":{"name":"movie.mkv","path":"/downloads/movie.mkv","type":"file","size":1024},"dest_fileitem":{"name":"movie.mkv","path":"/library/movie.mkv","type":"file","size":1024},"date":"2026-08-11 10:00:00"}"#
          .utf8
      )
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(
        #"{"list":[{"id":10,"title":"History","type":"电影","src":"/downloads/movie.mkv","dest":"/library/movie.mkv","src_storage":"local","dest_storage":"local","mode":"move","status":true,"src_fileitem":{"name":"movie.mkv","path":"/downloads/movie.mkv","type":"file","size":1024},"dest_fileitem":{"name":"movie.mkv","path":"/library/movie.mkv","type":"file","size":1024},"date":"2026-08-11 10:00:00"}],"total":1}"#
          .utf8
      )
    )

    let viewModel = TransferHistoryViewModel(apiService: service)
    viewModel.items = [oldItem]
    await viewModel.deleteHistory(
      item: oldItem,
      deleteSource: true,
      deleteDest: true,
      sourceSession: viewModel.captureMutationSession()
    )

    let deleteRequestCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(deleteRequestCount, 0)
    XCTAssertEqual(historyRequestCounts, [-1, 20])
    XCTAssertEqual(viewModel.items.first?.status.value, true)
    XCTAssertNil(viewModel.items.first?.errmsg)
    XCTAssertEqual(
      viewModel.mutationRetryMessage,
      "服务器记录有未知变化，请重试。"
    )
    XCTAssertFalse(viewModel.isDeleting)
  }

  func testMissingHistoryRefreshesAndRejectsReorganizePreflight() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[],"total":0}"#.utf8)
    )
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)
    let oldItem = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(
        #"{"id":10,"title":"History","type":"电影","src":"/downloads/movie.mkv","src_storage":"local","status":true,"date":"2026-08-11 10:00:00"}"#
          .utf8
      )
    )

    let viewModel = TransferHistoryViewModel(apiService: service)
    viewModel.items = [oldItem]
    let message = try await viewModel.validateBeforeReorganize(
      items: [oldItem],
      sourceSession: viewModel.captureMutationSession()
    )

    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [-1, 20])
    XCTAssertEqual(
      message,
      "服务器记录有未知变化，请重试。"
    )
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertNil(viewModel.mutationRetryMessage, "Sheet应自行呈现返回的重试提示。")
    XCTAssertFalse(viewModel.isValidatingMutation)
  }

  func testBatchFingerprintMismatchRejectsEveryDeleteBeforeMutation() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setDeleteResponse(
      Data(#"{"success":true}"#.utf8),
      gate: nil
    )
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let confirmedItems = try JSONDecoder().decode(
      [TransferHistory].self,
      from: Data(
        #"[{"id":10,"title":"A","type":"电影","src":"/downloads/a.mkv","src_storage":"local","status":true,"date":"2026-08-11 10:00:00"},{"id":11,"title":"B","type":"电影","src":"/downloads/b.mkv","src_storage":"local","status":true,"date":"2026-08-11 10:00:00"}]"#
          .utf8
      )
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(
        #"{"list":[{"id":10,"title":"A","type":"电影","src":"/downloads/a.mkv","src_storage":"local","status":true,"date":"2026-08-11 10:00:00"},{"id":11,"title":"B","type":"电影","src":"/downloads/reused-id.mkv","src_storage":"local","status":true,"date":"2026-08-11 10:00:01"}],"total":2}"#
          .utf8
      )
    )

    let viewModel = TransferHistoryViewModel(apiService: service)
    viewModel.items = confirmedItems
    viewModel.deleteSelected(
      items: confirmedItems,
      deleteSource: true,
      deleteDest: true,
      sourceSession: viewModel.captureMutationSession()
    )

    try await withTransferHistoryTimeout("batch fingerprint validation to finish") {
      while await MainActor.run(body: { viewModel.isDeleting }) {
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
      }
    }

    let deleteRequestCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(deleteRequestCount, 0)
    XCTAssertEqual(historyRequestCounts, [-1, 20])
    XCTAssertEqual(
      viewModel.mutationRetryMessage,
      "服务器记录有未知变化，请重试。"
    )
  }

  func testBatchDeleteDoesNotPreflightWhenSessionChangesBeforeTaskStarts() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setDeleteResponse(
      Data(#"{"success":true}"#.utf8),
      gate: nil
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )
    let accountA = Token(
      access_token: "manager-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager-a",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let item = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )

    let viewModel = TransferHistoryViewModel(apiService: service)
    var didSwitchSession = false
    let deletingCancellable = viewModel.$isDeleting.sink { isDeleting in
      guard isDeleting, !didSwitchSession else { return }
      didSwitchSession = true
      let accountB = Token(
        access_token: "manager-b",
        token_type: "bearer",
        super_user: FlexibleBool(false),
        permissions: [UserPermissionKey.manage.rawValue: true],
        user_id: 2,
        user_name: "transfer-manager-b",
        avatar: nil
      )
      service.replaceSessionForTesting(
        baseURL: "http://transfer-history-tests.local",
        token: accountB.access_token,
        currentUser: accountB
      )
    }
    defer { deletingCancellable.cancel() }

    let sourceSession = viewModel.captureMutationSession()
    viewModel.deleteSelected(
      items: [item],
      deleteSource: true,
      deleteDest: true,
      sourceSession: sourceSession
    )
    try await withTransferHistoryTimeout("cross-session batch delete to stop") {
      while await MainActor.run(body: { viewModel.isDeleting }) {
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
      }
    }

    XCTAssertTrue(didSwitchSession)
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    let deleteRequestCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
    XCTAssertTrue(historyRequestCounts.isEmpty)
    XCTAssertEqual(deleteRequestCount, 0)
    XCTAssertFalse(viewModel.isDeleting)
  }

  func testFrozenMutationIntentsDoNotStartInReplacementSession() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setDeleteResponse(
      Data(#"{"success":true}"#.utf8),
      gate: nil
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(
        #"{"list":[{"id":10,"title":"History","type":"电影","src":"/downloads/movie.mkv","dest":"/library/movie.mkv","status":true,"date":"2026-08-11 10:00:00"}],"total":1}"#
          .utf8
      )
    )
    let accountA = Token(
      access_token: "manager-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager-a",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )

    let item = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(
        #"{"id":10,"title":"History","type":"电影","src":"/downloads/movie.mkv","dest":"/library/movie.mkv","status":true,"date":"2026-08-11 10:00:00"}"#
          .utf8
      )
    )
    let historyViewModel = TransferHistoryViewModel(apiService: service)
    let sourceSession = historyViewModel.captureMutationSession()
    var reorganizeValidationStarted = false
    let reorganizeViewModel = ReorganizeViewModel(
      logIds: [item.id],
      fileItem: item.src_fileitem,
      validateBeforeSubmit: {
        reorganizeValidationStarted = true
        return try await historyViewModel.validateBeforeReorganize(
          items: [item],
          sourceSession: sourceSession
        )
      },
      sourceSession: sourceSession,
      apiService: service
    )

    // B 账号故意返回与 A 完全相同的记录；来源会话不匹配时仍不得开始预检。
    let accountB = Token(
      access_token: "manager-b",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 2,
      user_name: "transfer-manager-b",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountB.access_token,
      currentUser: accountB
    )

    await historyViewModel.deleteHistory(
      item: item,
      deleteSource: true,
      deleteDest: true,
      sourceSession: sourceSession
    )
    historyViewModel.deleteSelected(
      items: [item],
      deleteSource: true,
      deleteDest: true,
      sourceSession: sourceSession
    )
    await historyViewModel.triggerAiRedo(
      for: item,
      sourceSession: sourceSession
    )
    let reorganizeSubmitted = await reorganizeViewModel.submit(background: true)

    do {
      _ = try await historyViewModel.validateBeforeReorganize(
        items: [item],
        sourceSession: sourceSession
      )
      XCTFail("切换会话后的整理预检应被取消")
    } catch is CancellationError {
      // Expected.
    }

    XCTAssertFalse(reorganizeSubmitted)
    XCTAssertFalse(reorganizeValidationStarted)
    XCTAssertFalse(historyViewModel.isDeleting)
    XCTAssertFalse(historyViewModel.isAiRedoing)
    XCTAssertTrue(historyViewModel.aiRedoingIds.isEmpty)
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    let deleteRequestCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertTrue(historyRequestCounts.isEmpty)
    XCTAssertEqual(deleteRequestCount, 0)
    XCTAssertTrue(paths.isEmpty)
  }

  func testBatchDeleteKeepsConfirmedItemsAfterViewModelOwnerIsReleased() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let serviceSnapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { serviceSnapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let deleteGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setDeleteResponse(
      Data(#"{"success":true}"#.utf8),
      gate: deleteGate
    )
    defer {
      Task { await deleteGate.open() }
    }
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)

    let confirmedItems = try JSONDecoder().decode(
      [TransferHistory].self,
      from: Data(
        #"[{"id":10,"title":"A","type":"电影","status":true},{"id":11,"title":"B","type":"电影","status":true}]"#
          .utf8
      )
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(
        #"{"list":[{"id":10,"title":"A","type":"电影","status":true},{"id":11,"title":"B","type":"电影","status":true}],"total":2}"#
          .utf8
      )
    )
    let replacementItem = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":20,"title":"新列表","type":"电影","status":true}"#.utf8)
    )
    weak var retainedViewModel: TransferHistoryViewModel?
    do {
      let viewModel = TransferHistoryViewModel(apiService: service)
      retainedViewModel = viewModel
      viewModel.items = confirmedItems
      viewModel.selectedIds = [10, 11]

      let snapshot = viewModel.selectedItemsSnapshot()
      XCTAssertEqual(snapshot.map(\.id), [10, 11])

      viewModel.deleteSelected(
        items: snapshot,
        deleteSource: false,
        deleteDest: false,
        sourceSession: viewModel.captureMutationSession()
      )
      XCTAssertTrue(viewModel.isDeleting)

      try await withTransferHistoryTimeout("first confirmed delete request to start") {
        await TransferHistoryURLProtocol.stub.waitForDeleteRequestCount(1)
      }

      // 模拟列表迟到替换，并确认批删期间所有相邻入口均不能改变批次或启动新请求。
      viewModel.items = [replacementItem]
      viewModel.selectedIds.removeAll()
      viewModel.search(with: "新查询")
      await viewModel.refresh()
      await viewModel.loadMore(currentItemId: replacementItem.id)
      await viewModel.fetchLatest()
      viewModel.toggleSelection(id: replacementItem.id)
      XCTAssertTrue(viewModel.selectedIds.isEmpty)
      viewModel.selectAll()
      XCTAssertTrue(viewModel.selectedIds.isEmpty)
      viewModel.deselectAll()
      XCTAssertTrue(viewModel.selectedIds.isEmpty)
      viewModel.deleteSelected(
        items: snapshot,
        deleteSource: false,
        deleteDest: false,
        sourceSession: viewModel.captureMutationSession()
      )
      await viewModel.deleteHistory(
        item: replacementItem,
        deleteSource: false,
        deleteDest: false,
        sourceSession: viewModel.captureMutationSession()
      )
      await viewModel.triggerAiRedo(
        for: replacementItem,
        sourceSession: viewModel.captureMutationSession()
      )

      XCTAssertEqual(viewModel.searchText, "")
      let blockedDeleteCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
      XCTAssertEqual(blockedDeleteCount, 1)
    }

    // 对应父 View 因 Back/Menu 销毁：外部 owner 已释放，只有运行中的批删 Task 保活 ViewModel。
    XCTAssertNotNil(retainedViewModel)

    await deleteGate.open()
    try await withTransferHistoryTimeout("confirmed batch delete to finish") {
      await TransferHistoryURLProtocol.stub.waitForDeleteRequestCount(2)
    }

    for _ in 0..<2_000 {
      guard retainedViewModel != nil else { break }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    let finishedDeleteRequestCount = await TransferHistoryURLProtocol.stub.deleteRequestCount()
    XCTAssertEqual(finishedDeleteRequestCount, 2)
    XCTAssertNil(retainedViewModel)
  }

  func testAIRedoUsesWebSingleAndBatchRoutesAndShowsFailures() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )

    let singleResult = try await service.aiRedoTransferHistory(id: 10)
    let batchResult = try await service.aiRedoTransferHistories(ids: [10, 11])
    XCTAssertEqual(singleResult.progressKey, "single-progress")
    XCTAssertEqual(singleResult.acceptedIds, [10])
    XCTAssertEqual(batchResult.progressKey, "batch-progress")
    XCTAssertEqual(batchResult.acceptedIds, [10, 11])

    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/history/transfer/10/ai-redo"))
    XCTAssertTrue(paths.contains("/api/v1/history/transfer/ai-redo"))

    let aiItems = try JSONDecoder().decode(
      [TransferHistory].self,
      from: Data(
        #"[{"id":10,"title":"History","type":"电影","status":true},{"id":11,"title":"History 11","type":"电影","status":true}]"#
          .utf8
      )
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(
        #"{"list":[{"id":10,"title":"History","type":"电影","status":true},{"id":11,"title":"History 11","type":"电影","status":true}],"total":2}"#
          .utf8
      )
    )
    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.triggerAiRedo(
      for: aiItems[0],
      sourceSession: viewModel.captureMutationSession()
    )
    let progressFailureDeadline = Date().addingTimeInterval(2)
    while viewModel.errorMessage != "AI 整理业务失败",
      Date() < progressFailureDeadline
    {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(viewModel.errorMessage, "AI 整理业务失败")
    XCTAssertFalse(viewModel.isAiRedoing)

    viewModel.errorMessage = nil
    await viewModel.triggerAiRedo(
      for: aiItems[1],
      sourceSession: viewModel.captureMutationSession()
    )
    let startFailureDeadline = Date().addingTimeInterval(2)
    while viewModel.errorMessage != "AI 整理启动失败",
      Date() < startFailureDeadline
    {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(viewModel.errorMessage, "AI 整理启动失败")
    XCTAssertFalse(viewModel.isAiRedoing)
    let historyRequestCounts =
      await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [-1, 20, -1])

    await TransferHistoryURLProtocol.stub.reset()
    let guardedViewModel = TransferHistoryViewModel(apiService: service)
    guardedViewModel.isAiRedoing = true
    await guardedViewModel.triggerBatchAiRedo(
      for: aiItems,
      sourceSession: guardedViewModel.captureMutationSession()
    )
    let guardedHistory = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    await guardedViewModel.deleteHistory(
      item: guardedHistory,
      deleteSource: false,
      deleteDest: false,
      sourceSession: guardedViewModel.captureMutationSession()
    )
    let guardedPaths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertFalse(
      guardedPaths.contains("/api/v1/history/transfer/ai-redo"),
      "固定 Web 在任一 AI 重整运行时全局阻止再次启动。"
    )
    XCTAssertFalse(
      guardedPaths.contains("/api/v1/history/transfer"),
      "AI 重整运行时不得并发删除同一整理历史。"
    )
  }

  func testAIRedoCleanEOFWithoutTerminalEventShowsRetryableFailure() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    service.baseURLForTesting = "http://transfer-history-tests.local"
    configureManageUser(service)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setProgressResponseData(
      Data(
        #"data: {"type":"progress","text":"处理中"}"#
          .appending("\n\n").utf8
      )
    )

    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.triggerAiRedo(
      for: history,
      sourceSession: viewModel.captureMutationSession()
    )

    let deadline = Date().addingTimeInterval(2)
    while viewModel.errorMessage != "AI 整理连接中断，请重试。", Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertFalse(viewModel.isAiRedoing)
    XCTAssertEqual(viewModel.errorMessage, "AI 整理连接中断，请重试。")
  }

  func testAIRedoDoesNotPostWhenSessionChangesAfterValidation() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let service = APIService.testingInstance()
    let snapshot = TransferHistoryServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await TransferHistoryURLProtocol.stub.reset()
    let accountA = Token(
      access_token: "manager-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager-a",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )
    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )

    let viewModel = TransferHistoryViewModel(apiService: service)
    var didSwitchSession = false
    let progressCancellable = viewModel.$aiRedoProgressText.sink { text in
      guard text == "正在启动 AI 整理...", !didSwitchSession else { return }
      didSwitchSession = true
      let accountB = Token(
        access_token: "manager-b",
        token_type: "bearer",
        super_user: FlexibleBool(false),
        permissions: [UserPermissionKey.manage.rawValue: true],
        user_id: 2,
        user_name: "transfer-manager-b",
        avatar: nil
      )
      service.replaceSessionForTesting(
        baseURL: "http://transfer-history-tests.local",
        token: accountB.access_token,
        currentUser: accountB
      )
    }
    defer { progressCancellable.cancel() }

    await viewModel.triggerAiRedo(
      for: history,
      sourceSession: viewModel.captureMutationSession()
    )
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isAiRedoing, Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertTrue(didSwitchSession)
    XCTAssertFalse(viewModel.isAiRedoing)
    XCTAssertTrue(viewModel.aiRedoingIds.isEmpty)
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/history/transfer/10/ai-redo"))
    let historyRequestCounts = await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [-1])
  }

  func testAIRedoClearsPendingStateWhenSameProfileRefreshCancelsStream() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    await TransferHistoryURLProtocol.stub.reset()
    let progressGate = TransferHistoryAsyncGate()
    await TransferHistoryURLProtocol.stub.setProgressGate(progressGate)
    let accountA = Token(
      access_token: "manager-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )

    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )
    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.triggerAiRedo(
      for: history,
      sourceSession: viewModel.captureMutationSession()
    )
    try await withTransferHistoryTimeout("AI progress request to start") {
      await TransferHistoryURLProtocol.stub.waitForRequest(
        path: "/api/v1/system/progress/single-progress")
    }
    XCTAssertTrue(viewModel.isAiRedoing)
    XCTAssertEqual(viewModel.aiRedoingIds, [10])

    let refreshedAccountA = Token(
      access_token: "manager-b",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: refreshedAccountA.access_token,
      currentUser: refreshedAccountA
    )
    await progressGate.open()

    let deadline = Date().addingTimeInterval(2)
    while viewModel.isAiRedoing, Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertFalse(viewModel.isAiRedoing)
    XCTAssertTrue(viewModel.aiRedoingIds.isEmpty)
    XCTAssertNil(viewModel.errorMessage)
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/setting/public/Storages"))
    let historyRequestCounts = await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [-1])
  }

  func testAIRedoDoesNotRefreshWhenSessionChangesAfterFinalProgressEvent() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(TransferHistoryURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(TransferHistoryURLProtocol.self) }

    let sharedService = APIService.shared
    let persistenceSnapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { persistenceSnapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    await TransferHistoryURLProtocol.stub.reset()
    await TransferHistoryURLProtocol.stub.setProgressResponseData(
      Data(#"data: {"text":"切换会话"}"#.appending("\n\n").utf8)
    )
    let accountA = Token(
      access_token: "manager-a",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [UserPermissionKey.manage.rawValue: true],
      user_id: 1,
      user_name: "transfer-manager",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://transfer-history-tests.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(#"{"AI_AGENT_ENABLE":true}"#.utf8)
    )

    let history = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    await TransferHistoryURLProtocol.stub.setHistoryResponseData(
      Data(#"{"list":[{"id":10,"title":"History","type":"电影","status":true}],"total":1}"#.utf8)
    )
    let viewModel = TransferHistoryViewModel(apiService: service)
    var didSwitchSession = false
    let progressCancellable = viewModel.$aiRedoProgressText.sink { text in
      guard text == "切换会话", !didSwitchSession else { return }
      didSwitchSession = true
      let accountB = Token(
        access_token: "manager-b",
        token_type: "bearer",
        super_user: FlexibleBool(false),
        permissions: [UserPermissionKey.manage.rawValue: true],
        user_id: 2,
        user_name: "transfer-manager-b",
        avatar: nil
      )
      service.replaceSessionForTesting(
        baseURL: "http://transfer-history-tests.local",
        token: accountB.access_token,
        currentUser: accountB
      )
    }
    defer { progressCancellable.cancel() }

    await viewModel.triggerAiRedo(
      for: history,
      sourceSession: viewModel.captureMutationSession()
    )
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isAiRedoing, Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertTrue(didSwitchSession)
    XCTAssertFalse(viewModel.isAiRedoing)
    XCTAssertTrue(viewModel.aiRedoingIds.isEmpty)
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/setting/public/Storages"))
    let historyRequestCounts = await TransferHistoryURLProtocol.stub.recordedHistoryRequestCounts()
    XCTAssertEqual(historyRequestCounts, [-1])
  }

  private func configureManageUser(_ service: APIService) {
    service.currentUserForTesting = Token(
      access_token: "transfer-history-manager-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "transfer-manager",
      avatar: nil
    )
  }

  private func configureRestrictedUser(_ service: APIService) {
    service.currentUserForTesting = Token(
      access_token: "transfer-history-restricted-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: true,
        UserPermissionKey.search.rawValue: true,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: false,
      ],
      user_name: "transfer-restricted",
      avatar: nil
    )
  }
}

@MainActor
private struct TransferHistoryServiceSnapshot {
  let baseURL: String
  let token: String?
  let currentUser: Token?
  let settings: GlobalSettings?
  let serverURLDefaults: String?
  let currentUserKeychain: String?
  let currentUserDefaults: String?

  static func capture(service: APIService) -> TransferHistoryServiceSnapshot {
    TransferHistoryServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      currentUser: service.currentUser,
      settings: service.settings,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      currentUserKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "currentUser"),
      currentUserDefaults: UserDefaults.standard.string(forKey: "currentUser")
    )
  }

  func restore(to service: APIService) {
    service.replaceSessionForTesting(
      baseURL: baseURL,
      token: token,
      currentUser: currentUser
    )
    service.settings = settings

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }

    if let currentUserKeychain {
      _ = KeychainHelper.shared.save(
        currentUserKeychain,
        service: "MoviePilot-TV",
        account: "currentUser"
      )
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "currentUser")
    }

    if let currentUserDefaults {
      UserDefaults.standard.set(currentUserDefaults, forKey: "currentUser")
    } else {
      UserDefaults.standard.removeObject(forKey: "currentUser")
    }
  }
}

private struct TransferHistoryHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: TransferHistoryAsyncGate?
}

private actor TransferHistoryURLProtocolStub {
  private var paths: [String] = []
  private var historyRequestCounts: [Int?] = []
  private var storageGate: TransferHistoryAsyncGate?
  private var historyGate: TransferHistoryAsyncGate?
  private var historyResponseData: Data?
  private var historyResponseDataByPage: [Int: Data] = [:]
  private var deleteGate: TransferHistoryAsyncGate?
  private var deleteResponseData: Data?
  private var recordedDeleteRequestCount = 0
  private var progressGate: TransferHistoryAsyncGate?
  private var progressResponseData = Data(
    #"data: {"enable":false,"data":{"success":false,"error_i18n":"AI 整理业务失败"}}"#
      .appending("\n\n").utf8
  )

  func reset() {
    paths.removeAll()
    historyRequestCounts.removeAll()
    storageGate = nil
    historyGate = nil
    historyResponseData = nil
    historyResponseDataByPage.removeAll()
    deleteGate = nil
    deleteResponseData = nil
    recordedDeleteRequestCount = 0
    progressGate = nil
    progressResponseData = Data(
      #"data: {"enable":false,"data":{"success":false,"error_i18n":"AI 整理业务失败"}}"#
        .appending("\n\n").utf8
    )
  }

  func setHistoryGate(_ gate: TransferHistoryAsyncGate?) {
    historyGate = gate
  }

  func setStorageGate(_ gate: TransferHistoryAsyncGate?) {
    storageGate = gate
  }

  func setHistoryResponseData(_ data: Data?) {
    historyResponseData = data
  }

  func setHistoryResponseDataByPage(_ dataByPage: [Int: Data]) {
    historyResponseDataByPage = dataByPage
  }

  func setDeleteResponse(_ data: Data, gate: TransferHistoryAsyncGate?) {
    deleteResponseData = data
    deleteGate = gate
  }

  func setProgressGate(_ gate: TransferHistoryAsyncGate?) {
    progressGate = gate
  }

  func setProgressResponseData(_ data: Data) {
    progressResponseData = data
  }

  func response(for request: URLRequest) async throws -> TransferHistoryHTTPStubResponse {
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    paths.append(url.path)

    if request.httpMethod == "DELETE", let deleteResponseData {
      recordedDeleteRequestCount += 1
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: deleteResponseData,
        gate: deleteGate
      )
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    }

    switch url.path {
    case "/api/v1/system/setting/public/Storages":
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(#"{"value":[{"name":"本地","type":"local"}]}"#.utf8),
        gate: storageGate
      )
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    case "/api/v1/history/transfer":
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      let title = queryItems?.first(where: { $0.name == "title" })?.value
      if request.httpMethod == "GET" {
        historyRequestCounts.append(
          queryItems?.first(where: { $0.name == "count" })?.value.flatMap(Int.init)
        )
      }
      let page = queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init)
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: page.flatMap({ historyResponseDataByPage[$0] })
          ?? historyResponseData
          ?? Data(
            (title == "新查询"
              ? #"{"list":[{"id":20,"title":"新查询结果","type":"电影","status":true}],"total":1}"#
              : #"{"list":[{"id":10,"title":"Late History","type":"电影","status":true}],"total":1}"#)
              .utf8
          ),
        gate: title == "新查询" ? nil : historyGate
      )
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    case "/api/v1/history/transfer/10/ai-redo":
      return TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(#"{"success":true,"data":{"progress_key":"single-progress"}}"#.utf8),
        gate: nil
      )
    case "/api/v1/history/transfer/11/ai-redo":
      return TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(
          #"{"success":false,"message":"AI redo failed","message_i18n":"AI 整理启动失败"}"#
            .utf8
        ),
        gate: nil
      )
    case "/api/v1/history/transfer/ai-redo":
      return TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(
          #"{"success":true,"data":{"progress_key":"batch-progress","history_ids":[10,11]}}"#
            .utf8
        ),
        gate: nil
      )
    case "/api/v1/system/progress/single-progress":
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: progressResponseData,
        gate: progressGate
      )
      if let gate = response.gate {
        await gate.wait()
      }
      return response
    default:
      throw URLError(.unsupportedURL)
    }
  }

  func waitForRequest(path: String) async {
    while !paths.contains(path) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForDeleteRequestCount(_ count: Int) async {
    while recordedDeleteRequestCount < count {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func deleteRequestCount() -> Int {
    recordedDeleteRequestCount
  }

  func recordedHistoryRequestCounts() -> [Int?] {
    historyRequestCounts
  }

  func requestPaths() -> [String] {
    paths
  }
}

private final class TransferHistoryURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = TransferHistoryURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "transfer-history-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = TransferHistoryURLProtocolTaskContext(
      request: request,
      clientBox: TransferHistoryURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = TransferHistoryURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: TransferHistoryURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await TransferHistoryURLProtocol.stub.response(for: context.request)
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

private final class TransferHistoryURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: TransferHistoryURLProtocolClientBox

  init(request: URLRequest, clientBox: TransferHistoryURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class TransferHistoryURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: TransferHistoryHTTPStubResponse) {
    guard let url = request.url,
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
