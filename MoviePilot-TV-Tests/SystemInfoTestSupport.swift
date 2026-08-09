import Foundation

@testable import MoviePilot_TV

actor SystemInfoURLProtocolStub {
  private var requests: [URLRequest] = []
  private var systemEnvStatusCode = 200

  func reset() {
    requests.removeAll()
    systemEnvStatusCode = 200
  }

  func setSystemEnvStatusCode(_ statusCode: Int) {
    systemEnvStatusCode = statusCode
  }

  func requestPaths() -> [String] {
    requests.map { $0.url?.path ?? "" }
  }

  func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    requests.append(request)
    guard let url = request.url else {
      throw URLError(.badURL)
    }

    let statusCode: Int
    let data: Data
    switch url.path {
    case "/api/v1/system/global":
      statusCode = 200
      data =
        #"{"success":true,"data":{"BACKEND_VERSION":"v9.9.9","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}}"#
        .data(using: .utf8)!
    case "/api/v1/system/global/user":
      statusCode = 200
      data = #"{"success":true,"data":{}}"#.data(using: .utf8)!
    case "/api/v1/system/env":
      statusCode = systemEnvStatusCode
      if systemEnvStatusCode == 200 {
        data = #"{"success":true,"data":{"VERSION":"v2.13.14"}}"#.data(using: .utf8)!
      } else {
        data = #"{"success":false,"message":"forbidden"}"#.data(using: .utf8)!
      }
    default:
      statusCode = 404
      data = #"{"success":false,"message":"not found"}"#.data(using: .utf8)!
    }

    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}
final class SystemInfoURLProtocol: URLProtocol {
  static let stub = SystemInfoURLProtocolStub()
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "system-info-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let context = SystemInfoURLProtocolTaskContext(
      request: request,
      clientBox: SystemInfoURLProtocolClientBox(protocolInstance: self, client: client)
    )
    loadingTask = SystemInfoURLProtocol.makeLoadingTask(for: context)
  }

  private static func makeLoadingTask(for context: SystemInfoURLProtocolTaskContext)
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

private final class SystemInfoURLProtocolTaskContext: @unchecked Sendable {
  let request: URLRequest
  let clientBox: SystemInfoURLProtocolClientBox

  init(request: URLRequest, clientBox: SystemInfoURLProtocolClientBox) {
    self.request = request
    self.clientBox = clientBox
  }
}

private final class SystemInfoURLProtocolClientBox: @unchecked Sendable {
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
