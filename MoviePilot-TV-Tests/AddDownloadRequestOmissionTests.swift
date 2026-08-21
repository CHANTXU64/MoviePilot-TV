import Foundation
import XCTest

@testable import MoviePilot_TV

// MARK: - URLProtocol stub（捕获 /download/add 请求体）

private actor AddDownloadRequestStub {
  static let shared = AddDownloadRequestStub()

  private var capturedBodies: [Data] = []

  func reset() {
    capturedBodies.removeAll()
  }

  func capture(_ body: Data) {
    capturedBodies.append(body)
  }

  var bodyCount: Int {
    capturedBodies.count
  }

  func bodyText(at index: Int) -> String {
    guard capturedBodies.indices.contains(index) else { return "" }
    return String(data: capturedBodies[index], encoding: .utf8) ?? ""
  }
}

private final class AddDownloadRequestURLProtocol: URLProtocol {
  private var loadingTask: Task<Void, Never>?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "add-download.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let box = AddDownloadURLProtocolClientBox(protocolInstance: self, client: client)
    let body = Self.bodyData(from: box.request)
    loadingTask = Task {
      await AddDownloadRequestStub.shared.capture(body)
      guard !Task.isCancelled else { return }
      box.succeed()
    }
  }

  private static func bodyData(from request: URLRequest) -> Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }

  override func stopLoading() {
    loadingTask?.cancel()
    loadingTask = nil
  }
}

private final class AddDownloadURLProtocolClientBox: @unchecked Sendable {
  private let protocolInstance: URLProtocol
  private let client: URLProtocolClient?
  let request: URLRequest

  init(protocolInstance: URLProtocol, client: URLProtocolClient?) {
    self.protocolInstance = protocolInstance
    self.client = client
    self.request = protocolInstance.request
  }

  func succeed() {
    guard let url = request.url else { return }
    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(protocolInstance, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(protocolInstance, didLoad: Data(#"{"success":true}"#.utf8))
    client?.urlProtocolDidFinishLoading(protocolInstance)
  }
}

// MARK: - 测试

@MainActor
final class AddDownloadRequestOmissionTests: XCTestCase {
  override func setUp() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(AddDownloadRequestURLProtocol.self))
    await AddDownloadRequestStub.shared.reset()
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(AddDownloadRequestURLProtocol.self)
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "http://add-download.local"
    service.tokenForTesting = "add-download-token"
    service.currentUserForTesting = Token(
      access_token: "add-download-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: nil,
      user_id: 601,
      user_name: "add-download-user",
      avatar: nil
    )
    return service
  }

  func testDownloaderResetToAutoOmitsFieldFromPayload() async throws {
    let service = makeService()
    let viewModel = AddDownloadViewModel(torrent: Self.torrentFixture(), apiService: service)

    // 初始未选下载器（后端默认）：请求体省略 downloader 字段
    await viewModel.addDownload()
    let initialBody = await AddDownloadRequestStub.shared.bodyText(at: 0)
    XCTAssertFalse(initialBody.contains("downloader"))

    // 选中具体下载器：请求体携带 downloader
    viewModel.selectedDownloader = "clientA"
    await viewModel.addDownload()
    let selectedBody = await AddDownloadRequestStub.shared.bodyText(at: 1)
    XCTAssertTrue(selectedBody.contains("downloader"))
    XCTAssertTrue(selectedBody.contains("clientA"))

    // 选回"自动"（Binding 把空串转回 nil）：请求体恢复省略，与初始一致
    viewModel.selectedDownloader = nil
    await viewModel.addDownload()
    let resetBody = await AddDownloadRequestStub.shared.bodyText(at: 2)
    XCTAssertFalse(resetBody.contains("downloader"))

    let count = await AddDownloadRequestStub.shared.bodyCount
    XCTAssertEqual(count, 3)
  }

  private static func torrentFixture() -> TorrentInfo {
    TorrentInfo(
      site: 1,
      site_name: "站点",
      site_order: nil,
      title: "测试资源",
      description: nil,
      enclosure: "https://example.com/test.torrent",
      page_url: nil,
      size: 1024,
      seeders: nil,
      peers: nil,
      pubdate: nil,
      uploadvolumefactor: 1,
      downloadvolumefactor: 1,
      pri_order: nil,
      labels: nil,
      volume_factor: nil
    )
  }
}
