import Foundation
import XCTest

@testable import MoviePilot_TV

private enum SearchViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
  }
}

private actor SearchAsyncGate {
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
      throw SearchViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

@MainActor
final class SearchViewModelTests: XCTestCase {
  func testOlderUnifiedSearchCompletionDoesNotClearLoadingForNewerSearch() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SearchViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(SearchViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SearchViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await SearchViewModelURLProtocol.stub.reset()
    let oldSearchGate = SearchAsyncGate()
    let newSearchGate = SearchAsyncGate()
    await SearchViewModelURLProtocol.stub.setGate(oldSearchGate, forQuery: "old")
    await SearchViewModelURLProtocol.stub.setGate(newSearchGate, forQuery: "new")

    service.baseURL = "http://search-tests.local"

    let viewModel = SearchViewModel()
    viewModel.searchType = .unified
    viewModel.query = "old"

    let oldSearchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { oldSearchTask.cancel() }

    try await withTimeout("old search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "old")
    }

    viewModel.query = "new"
    let newSearchTask = Task { @MainActor in
      await viewModel.autoSearch()
    }
    defer { newSearchTask.cancel() }

    try await withTimeout("new search request to start") {
      await SearchViewModelURLProtocol.stub.waitForRequest(query: "new")
    }

    await oldSearchGate.open()
    try await withTimeout("old search to finish after new search starts") {
      await oldSearchTask.value
    }

    XCTAssertEqual(viewModel.submittedQuery, "new")
    XCTAssertTrue(
      viewModel.isLoading,
      "A stale unified search must not clear loading while a newer search is still running."
    )
    XCTAssertFalse(
      viewModel.hasSearched,
      "A stale unified search must not mark a newer in-flight search as completed."
    )

    await newSearchGate.open()
    try await withTimeout("new search to finish") {
      await newSearchTask.value
    }

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertTrue(viewModel.hasSearched)
    let bestResultTitles = viewModel.bestResults.compactMap { item -> String? in
      if case .media(let media) = item {
        return media.title
      }
      return nil
    }
    XCTAssertEqual(bestResultTitles, ["New Result"])
  }
}

@MainActor
private struct SearchViewModelServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let accessTokenDefaults: String?

  static func capture(service: APIService) -> SearchViewModelServiceSnapshot {
    SearchViewModelServiceSnapshot(
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

private struct SearchViewModelHTTPStubResponse: Sendable {
  let statusCode: Int
  let data: Data
}

private actor SearchViewModelURLProtocolStub {
  private var gatesByQuery: [String: SearchAsyncGate] = [:]
  private var requestedQueries: [String] = []

  func reset() {
    gatesByQuery.removeAll()
    requestedQueries.removeAll()
  }

  func setGate(_ gate: SearchAsyncGate, forQuery query: String) {
    gatesByQuery[query] = gate
  }

  func response(for request: URLRequest) async throws -> SearchViewModelHTTPStubResponse {
    guard
      let url = request.url,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    let queryItems = components.queryItems ?? []
    let query = queryItems.first(where: { $0.name == "title" })?.value
      ?? queryItems.first(where: { $0.name == "name" })?.value
      ?? ""
    recordRequest(for: query)

    if let gate = gatesByQuery[query] {
      await gate.wait()
    }

    return SearchViewModelHTTPStubResponse(
      statusCode: 200,
      data: responseData(path: components.path, queryItems: queryItems, query: query)
    )
  }

  func waitForRequest(query: String) async {
    while !requestedQueries.contains(query) {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  private func recordRequest(for query: String) {
    requestedQueries.append(query)
  }

  private func responseData(path: String, queryItems: [URLQueryItem], query: String) -> Data {
    if path == "/api/v1/subscribe/shares" {
      return Data("[]".utf8)
    }

    let type = queryItems.first(where: { $0.name == "type" })?.value
    guard type == nil else {
      return Data("[]".utf8)
    }

    let page = queryItems.first(where: { $0.name == "page" })?.value ?? "1"
    guard page == "1" else {
      return Data("[]".utf8)
    }

    let id = query == "new" ? 1002 : 1001
    let title = query == "new" ? "New Result" : "Old Result"
    return Data(
      """
      [
        {
          "tmdb_id": \(id),
          "title": "\(title)",
          "type": "电影",
          "year": "2026",
          "poster_path": "/poster-\(id).jpg",
          "popularity": 100
        }
      ]
      """.utf8)
  }
}

private final class SearchViewModelURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = SearchViewModelURLProtocolStub()

  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "search-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SearchViewModelURLProtocolTaskContext(
      request: request,
      clientBox: SearchViewModelURLProtocolClientBox(protocolInstance: self, client: client)
    )

    loadingTask = SearchViewModelURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SearchViewModelURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let stubResponse = try await SearchViewModelURLProtocol.stub.response(for: context.request)
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

private final class SearchViewModelURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SearchViewModelURLProtocolClientBox

  init(request: URLRequest, clientBox: SearchViewModelURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SearchViewModelURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(request: URLRequest, stubResponse: SearchViewModelHTTPStubResponse) {
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
