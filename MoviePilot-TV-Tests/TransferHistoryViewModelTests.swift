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

@MainActor
final class TransferHistoryViewModelTests: XCTestCase {
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
        deleteDest: true
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
      deleteDest: true
    )
    await viewModel.triggerAiRedo(for: history.id)
    let pendingPaths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertEqual(pendingPaths.filter { $0 == "/api/v1/history/transfer" }.count, 1)
    XCTAssertFalse(pendingPaths.contains("/api/v1/history/transfer/10/ai-redo"))

    await gate.open()
    try await withTransferHistoryTimeout("first delete request to finish") {
      await firstDelete.value
    }
    XCTAssertFalse(viewModel.isDeleting)
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

    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.triggerAiRedo(for: 10)
    let progressFailureDeadline = Date().addingTimeInterval(2)
    while viewModel.errorMessage != "AI 整理业务失败",
      Date() < progressFailureDeadline
    {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(viewModel.errorMessage, "AI 整理业务失败")
    XCTAssertFalse(viewModel.isAiRedoing)

    viewModel.errorMessage = nil
    await viewModel.triggerAiRedo(for: 11)
    let startFailureDeadline = Date().addingTimeInterval(2)
    while viewModel.errorMessage != "AI 整理启动失败",
      Date() < startFailureDeadline
    {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(viewModel.errorMessage, "AI 整理启动失败")
    XCTAssertFalse(viewModel.isAiRedoing)

    await TransferHistoryURLProtocol.stub.reset()
    let guardedViewModel = TransferHistoryViewModel(apiService: service)
    guardedViewModel.isAiRedoing = true
    await guardedViewModel.triggerBatchAiRedo(for: [10, 11])
    let guardedHistory = try JSONDecoder().decode(
      TransferHistory.self,
      from: Data(#"{"id":10,"title":"History","type":"电影","status":true}"#.utf8)
    )
    await guardedViewModel.deleteHistory(
      item: guardedHistory,
      deleteSource: false,
      deleteDest: false
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

    let viewModel = TransferHistoryViewModel(apiService: service)
    await viewModel.triggerAiRedo(for: 10)
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
    XCTAssertFalse(paths.contains("/api/v1/history/transfer"))
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

    await viewModel.triggerAiRedo(for: 10)
    let deadline = Date().addingTimeInterval(2)
    while viewModel.isAiRedoing, Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertTrue(didSwitchSession)
    XCTAssertFalse(viewModel.isAiRedoing)
    XCTAssertTrue(viewModel.aiRedoingIds.isEmpty)
    let paths = await TransferHistoryURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/setting/public/Storages"))
    XCTAssertFalse(paths.contains("/api/v1/history/transfer"))
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
  private var historyGate: TransferHistoryAsyncGate?
  private var progressGate: TransferHistoryAsyncGate?
  private var progressResponseData = Data(
    #"data: {"enable":false,"data":{"success":false,"error_i18n":"AI 整理业务失败"}}"#
      .appending("\n\n").utf8
  )

  func reset() {
    paths.removeAll()
    historyGate = nil
    progressGate = nil
    progressResponseData = Data(
      #"data: {"enable":false,"data":{"success":false,"error_i18n":"AI 整理业务失败"}}"#
        .appending("\n\n").utf8
    )
  }

  func setHistoryGate(_ gate: TransferHistoryAsyncGate?) {
    historyGate = gate
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

    switch url.path {
    case "/api/v1/system/setting/public/Storages":
      return TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(#"{"value":[{"name":"本地","type":"local"}]}"#.utf8),
        gate: nil
      )
    case "/api/v1/history/transfer":
      let response = TransferHistoryHTTPStubResponse(
        statusCode: 200,
        data: Data(
          #"{"list":[{"id":10,"title":"Late History","type":"电影","status":true}],"total":1}"#
            .utf8
        ),
        gate: historyGate
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
