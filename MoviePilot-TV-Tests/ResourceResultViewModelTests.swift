import Foundation
import XCTest

@testable import MoviePilot_TV

private enum ResourceResultViewModelTestFailure: Error, LocalizedError {
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .timedOut(let description):
      return "Timed out waiting for \(description)"
    }
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
      throw ResourceResultViewModelTestFailure.timedOut(description)
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

private final class WeakBox<T: AnyObject> {
  weak var value: T?

  init(_ value: T?) {
    self.value = value
  }
}

@MainActor
final class ResourceResultViewModelTests: XCTestCase {
  func testDeinitCancelsInFlightSearchStream() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"

    var viewModel: ResourceResultViewModel? = ResourceResultViewModel(keyword: "stale")
    let releasedViewModel = WeakBox(viewModel)

    await viewModel?.search()

    try await withTimeout("resource search stream request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest()
    }

    viewModel = nil

    XCTAssertNil(
      releasedViewModel.value,
      "The in-flight resource stream task must not keep the view model alive after the view is gone."
    )
    try await withTimeout("resource search stream cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation()
    }
  }

  func testCancelSearchCancelsInFlightSearchStream() async throws {
    XCTAssertTrue(URLProtocol.registerClass(ResourceResultViewModelURLProtocol.self))
    defer { URLProtocol.unregisterClass(ResourceResultViewModelURLProtocol.self) }

    let service = APIService.shared
    let snapshot = ResourceResultViewModelServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    await ResourceResultViewModelURLProtocol.stub.reset()
    service.baseURL = "http://resource-result-tests.local"

    let viewModel = ResourceResultViewModel(keyword: "stale")
    await viewModel.search()

    try await withTimeout("resource search stream request to start") {
      await ResourceResultViewModelURLProtocol.stub.waitForRequest()
    }

    viewModel.cancelSearch()

    try await withTimeout("resource search stream cancellation") {
      await ResourceResultViewModelURLProtocol.stub.waitForCancellation()
    }
    XCTAssertFalse(viewModel.isLoading)
  }
}

@MainActor
private struct ResourceResultViewModelServiceSnapshot {
  let baseURL: String
  let serverURLDefaults: String?
  let accessTokenDefaults: String?

  static func capture(service: APIService) -> ResourceResultViewModelServiceSnapshot {
    ResourceResultViewModelServiceSnapshot(
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

private actor ResourceResultViewModelURLProtocolStub {
  private var didRequest = false
  private var didCancel = false

  func reset() {
    didRequest = false
    didCancel = false
  }

  func recordRequest() {
    didRequest = true
  }

  func recordCancellation() {
    didCancel = true
  }

  func waitForRequest() async {
    while !didRequest {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForCancellation() async {
    while !didCancel {
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}

private final class ResourceResultViewModelURLProtocol: URLProtocol, @unchecked Sendable {
  static let stub = ResourceResultViewModelURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "resource-result-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Task {
      await ResourceResultViewModelURLProtocol.stub.recordRequest()
    }
  }

  override func stopLoading() {
    Task {
      await ResourceResultViewModelURLProtocol.stub.recordCancellation()
    }
  }
}
