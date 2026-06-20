import XCTest

@testable import MoviePilot_TV

@MainActor
final class SubscribeSheetViewModelTests: XCTestCase {
  private let autoSearchKey = "autoSearchNewSubscriptions"

  func testAutoSearchNewSubscriptionsDefaultsToEnabled() {
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    UserDefaults.standard.removeObject(forKey: autoSearchKey)
    defer { restoreUserDefaultsValue(originalValue, forKey: autoSearchKey) }

    let viewModel = SystemViewModel()

    XCTAssertTrue(viewModel.autoSearchNewSubscriptions)
    XCTAssertTrue(SystemViewModel.shouldAutoSearchNewSubscriptions)
  }

  func testSaveNewSubscriptionSkipsSearchWhenAutoSearchSettingIsDisabled() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    UserDefaults.standard.set(false, forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 777, name: "关闭自动搜索", type: "电影", tmdbid: 123456),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/777")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/777")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 0)
  }

  func testSaveNewSubscriptionSearchesByDefault() async throws {
    XCTAssertTrue(URLProtocol.registerClass(SubscribeSheetURLProtocol.self))
    defer { URLProtocol.unregisterClass(SubscribeSheetURLProtocol.self) }

    let service = APIService.shared
    let snapshot = SubscribeSheetServiceSnapshot.capture(service: service)
    let originalValue = UserDefaults.standard.object(forKey: autoSearchKey)
    defer {
      snapshot.restore(to: service)
      restoreUserDefaultsValue(originalValue, forKey: autoSearchKey)
    }

    await SubscribeSheetURLProtocol.stub.reset()
    service.baseURL = "http://subscribe-sheet-tests.local"
    UserDefaults.standard.removeObject(forKey: autoSearchKey)

    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 778, name: "默认自动搜索", type: "电影", tmdbid: 123457),
      isNewSubscription: true
    )

    let didSave = await viewModel.save()

    XCTAssertTrue(didSave)
    let statusRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "PUT", path: "/api/v1/subscribe/status/778")
    let searchRequestCount = await SubscribeSheetURLProtocol.stub.requestCount(
      method: "GET", path: "/api/v1/subscribe/search/778")
    XCTAssertEqual(statusRequestCount, 1)
    XCTAssertEqual(searchRequestCount, 1)
  }

  private func restoreUserDefaultsValue(_ value: Any?, forKey key: String) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

private struct SubscribeSheetServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SubscribeSheetServiceSnapshot {
    SubscribeSheetServiceSnapshot(
      baseURL: service.baseURL,
      serverURLDefaults: UserDefaults.standard.string(forKey: "serverURL")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL

    if let serverURLDefaults {
      UserDefaults.standard.set(serverURLDefaults, forKey: "serverURL")
    } else {
      UserDefaults.standard.removeObject(forKey: "serverURL")
    }
  }
}

private actor SubscribeSheetURLProtocolStub {
  private var requestCounts: [String: Int] = [:]

  func reset() {
    requestCounts.removeAll()
  }

  func requestCount(method: String, path: String) -> Int {
    requestCounts["\(method) \(path)", default: 0]
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""
    requestCounts["\(method) \(path)", default: 0] += 1

    guard path.hasPrefix("/api/v1/subscribe") else {
      throw URLError(.badServerResponse)
    }

    let data = #"{"success":true}"#.data(using: .utf8)!
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class SubscribeSheetURLProtocol: URLProtocol {
  static let stub = SubscribeSheetURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "subscribe-sheet-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SubscribeSheetURLProtocolTaskContext(
      request: request,
      clientBox: SubscribeSheetURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SubscribeSheetURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SubscribeSheetURLProtocolTaskContext)
    -> Task<Void, Never>
  {
    Task {
      do {
        let (response, data) = try await Self.stub.response(for: context.request)
        guard !Task.isCancelled else { return }
        context.clientBox.succeed(response: response, data: data)
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

private final class SubscribeSheetURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SubscribeSheetURLProtocolClientBox

  init(request: URLRequest, clientBox: SubscribeSheetURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SubscribeSheetURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
  }

  func succeed(response: HTTPURLResponse, data: Data) {
    client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: data)
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }

  func fail(_ error: Error) {
    client?.urlProtocol(protocolInstance, didFailWithError: error)
  }
}
