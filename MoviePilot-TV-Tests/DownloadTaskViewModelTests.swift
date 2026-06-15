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

  private func downloadPayload(
    hash: String,
    title: String,
    username: String,
    state: String = "downloading",
    progress: Int
  ) -> String {
    """
    [
      {
        "hash": "\(hash)",
        "title": "\(title)",
        "name": "\(title)",
        "state": "\(state)",
        "progress": \(progress),
        "username": "\(username)"
      }
    ]
    """
  }
}

@MainActor
private struct DownloadTaskServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let accessTokenDefaults: String?

  static func capture(service: APIService) -> DownloadTaskServiceSnapshot {
    DownloadTaskServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL"),
      accessTokenDefaults: UserDefaults.standard.string(forKey: "accessToken")
    )
  }

  func restore(to service: APIService) {
    service.baseURL = baseURL

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
  }
}

private struct DownloadTaskHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
  let gate: DownloadTaskAsyncGate?
}

private actor DownloadTaskURLProtocolStub {
  private var responsesByClient: [String: DownloadTaskHTTPStubResponse] = [:]
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
    responsesByClient[clientName] = DownloadTaskHTTPStubResponse(
      statusCode: statusCode,
      data: Data(json.utf8),
      gate: gate
    )
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

    guard let response = responsesByClient[clientName] else {
      throw URLError(.unsupportedURL)
    }

    if let gate = response.gate {
      await gate.wait()
    }

    return response
  }

  func waitForRequest(clientName: String) async {
    while !requestedClients.contains(clientName) {
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
