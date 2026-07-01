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
  func testOlderClientLoadThatCompletesLaterDoesNotPublishOverCurrentClientDownloads()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
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

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
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
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
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

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
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

  func testOlderClientLoadThatCompletesLaterDoesNotMutateCurrentClientDownloadWithSameId()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
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

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
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
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
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

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
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

  func testSameDownloadRefreshUpdatesLatestMetadataForExistingRow() async throws {
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
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

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
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

  func testOlderClientDeleteThatCompletesLaterDoesNotRemoveCurrentClientDownloadWithSameHash()
    async throws
  {
    XCTAssertTrue(URLProtocol.registerClass(DownloadTaskURLProtocol.self))
    defer { URLProtocol.unregisterClass(DownloadTaskURLProtocol.self) }

    let service = APIService.shared
    let snapshot = DownloadTaskServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await DownloadTaskURLProtocol.stub.reset()
    let deleteGate = DownloadTaskAsyncGate()
    await DownloadTaskURLProtocol.stub.setDownloadsJSON(
      #"{"success": true, "message": "ok"}"#,
      forClient: "old",
      waitFor: deleteGate
    )

    service.baseURL = "http://download-tests.local"
    configureManageUser(service)

    let viewModel = DownloadTaskViewModel()
    viewModel.selectedClient = "old"
    viewModel.downloads = try decodeDownloads(
      downloadPayload(
        hash: "shared-hash", title: "Old Client Task", username: "old-user", progress: 10)
    )

    let deleteTask = Task { @MainActor in
      await viewModel.deleteDownload(hash: "shared-hash")
    }
    defer { deleteTask.cancel() }

    try await withTimeout("old client delete request to start") {
      await DownloadTaskURLProtocol.stub.waitForRequest(clientName: "old")
    }

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
        "username": "\(username)"
      }
    ]
    """
  }

  private func decodeDownloads(_ json: String) throws -> [DownloadingInfo] {
    try JSONDecoder().decode([DownloadingInfo].self, from: Data(json.utf8))
  }

  private func configureManageUser(_ service: APIService) {
    service.currentUser = Token(
      access_token: "download-task-tests",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        UserPermissionKey.discovery.rawValue: false,
        UserPermissionKey.search.rawValue: false,
        UserPermissionKey.subscribe.rawValue: false,
        UserPermissionKey.manage.rawValue: true,
      ],
      user_name: "download-manager",
      avatar: nil
    )
  }

  private func configureRestrictedUser(_ service: APIService) {
    service.currentUser = Token(
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
    service.baseURL = baseURL
    service.currentUser = currentUser

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
  private var requestedClients: [String] = []

  func reset() {
    responsesByClient.removeAll()
    requestedClients.removeAll()
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
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let clientName = components.queryItems?.first(where: { $0.name == "name" })?.value
    else {
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
