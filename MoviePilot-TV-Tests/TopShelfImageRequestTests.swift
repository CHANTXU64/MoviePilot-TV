import ImageIO
import TVServices
import UIKit
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfImageRequestTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(TopShelfImageURLProtocol.self))
    TopShelfImageURLProtocol.reset()
  }

  override func tearDown() async throws {
    APIService.removeURLProtocolForTesting(TopShelfImageURLProtocol.self)
    try await super.tearDown()
  }

  func testProtectedImageUsesFrozenSessionCredentialsAndPreservesOriginalBytes() async throws {
    let service = makeService()
    _ = try await service.fetchRecommend(path: "seed-cookie")

    let resource = try await service.fetchTopShelfImageResource(
      at: URL(string: "https://image-test.local/api/v1/system/cache/image?case=direct")!
    )

    let final = try XCTUnwrap(TopShelfImageURLProtocol.receivedRequest(named: "direct"))
    XCTAssertEqual(final.value(forHTTPHeaderField: "Authorization"), "Bearer image-token")
    XCTAssertEqual(final.value(forHTTPHeaderField: "Cookie"), "resource_cookie=session-a")
    XCTAssertEqual(resource.fileExtension, "gif")
    XCTAssertEqual(resource.data, TopShelfTestArtwork.data)
    XCTAssertFalse(resource.data.isEmpty)
  }

  func testProtectedRedirectToThirdPartyStripsCredentialsAtFinalReceiver() async throws {
    let service = makeService()
    _ = try await service.fetchRecommend(path: "seed-cookie")

    _ = try await service.fetchTopShelfImageResource(
      at: URL(
        string: "https://image-test.local/api/v1/system/cache/image?case=redirect-third"
      )!
    )

    let final = try XCTUnwrap(TopShelfImageURLProtocol.receivedRequest(named: "third-final"))
    XCTAssertNil(final.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(final.value(forHTTPHeaderField: "Cookie"))
  }

  func testProtectedRedirectToSameOriginNonProtectedPathStripsCredentials() async throws {
    let service = makeService()
    _ = try await service.fetchRecommend(path: "seed-cookie")

    _ = try await service.fetchTopShelfImageResource(
      at: URL(
        string: "https://image-test.local/api/v1/system/cache/image?case=redirect-public-path"
      )!
    )

    let final = try XCTUnwrap(TopShelfImageURLProtocol.receivedRequest(named: "public-final"))
    XCTAssertNil(final.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(final.value(forHTTPHeaderField: "Cookie"))
  }

  func testPublicRedirectIntoProtectedPathNeverEscalatesCredentials() async throws {
    let service = makeService()
    _ = try await service.fetchRecommend(path: "seed-cookie")

    _ = try await service.fetchTopShelfImageResource(
      at: URL(string: "https://public-image.local/public-to-protected")!
    )

    let final = try XCTUnwrap(
      TopShelfImageURLProtocol.receivedRequest(named: "public-to-protected-final")
    )
    XCTAssertNil(final.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(final.value(forHTTPHeaderField: "Cookie"))
  }

  func testHTTPSRedirectToHTTPIsRejectedBeforeFinalReceiver() async throws {
    let service = makeService()

    do {
      _ = try await service.fetchTopShelfImageResource(
        at: URL(
          string: "https://image-test.local/api/v1/system/cache/image?case=downgrade"
        )!
      )
      XCTFail("HTTPS 降级重定向不应成功")
    } catch let error as TopShelfImageError {
      XCTAssertEqual(error, .insecureRedirect)
    }
    XCTAssertNil(TopShelfImageURLProtocol.receivedRequest(named: "downgrade-final"))
  }

  func testSuccessfulHTTPWithFakeImagePayloadIsRejected() async throws {
    let service = makeService()

    do {
      _ = try await service.fetchTopShelfImageResource(
        at: URL(string: "https://public-image.local/fake-image")!
      )
      XCTFail("伪造 MIME 的文本不应进入 Top Shelf 快照")
    } catch let error as TopShelfImageError {
      XCTAssertEqual(error, .invalidImage)
    }
  }

  func testDeclaredOversizedImageIsRejectedBeforeBodyIsAccepted() async throws {
    let service = makeService()

    do {
      _ = try await service.fetchTopShelfImageResource(
        at: URL(string: "https://public-image.local/oversized")!
      )
      XCTFail("超出上限的图片不应进入内存快照")
    } catch let error as TopShelfImageError {
      XCTAssertEqual(error, .tooLarge)
    }
  }

  func testStreamingBodyWithoutContentLengthStopsAtByteLimit() async throws {
    let service = makeService()

    do {
      _ = try await service.fetchTopShelfImageResource(
        at: URL(string: "https://public-image.local/body-too-large")!,
        maximumBytes: 4
      )
      XCTFail("没有 Content-Length 的响应也必须执行流式字节上限")
    } catch let error as TopShelfImageError {
      XCTAssertEqual(error, .tooLarge)
    }
  }

  func testDecodedPixelLimitRejectsOtherwiseValidImage() async throws {
    let service = makeService()

    do {
      _ = try await service.fetchTopShelfImageResource(
        at: URL(string: "https://public-image.local/valid-image")!,
        maximumPixels: 0
      )
      XCTFail("有效编码也不能绕过像素上限")
    } catch let error as TopShelfImageError {
      XCTAssertEqual(error, .tooLarge)
    }
  }

  func testLandscapePreparesCardAndTwoKBackgroundFromEncodedData() async throws {
    let data = TopShelfTestArtwork.landscapeData()
    let images = try await TopShelfImageLoader.prepareImages(from: data)
    XCTAssertEqual(TopShelfImageLoader.cardShape, .hdtv)
    let background = try XCTUnwrap(UIImage(data: images.background.data)?.cgImage)
    XCTAssertEqual(background.width, 2560)
    XCTAssertEqual(background.height, 1440)
    let thumbnail = try XCTUnwrap(UIImage(data: images.card.data)?.cgImage)
    XCTAssertLessThanOrEqual(thumbnail.width, Int(ceil(TopShelfImageLoader.cardSize.width * 2)))
    XCTAssertLessThan(thumbnail.width, background.width)
    XCTAssertEqual(Double(thumbnail.width) / Double(thumbnail.height), 16.0 / 9.0, accuracy: 0.01)
  }

  func testPreparedImagesDoNotUpscaleSmallSources() async throws {
    let images = try await TopShelfImageLoader.prepareImages(from: TopShelfTestArtwork.data)
    for data in [images.card.data, images.background.data] {
      let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
      XCTAssertEqual(image.width, 1)
      XCTAssertEqual(image.height, 1)
    }
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "image-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_id: 700,
      user_name: "image-user",
      avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://image-test.local",
      token: "image-token",
      currentUser: user
    )
    return service
  }
}

private final class TopShelfImageURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var received: [String: URLRequest] = [:]
  private static let imageData = Data(
    base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
  )!

  static func reset() {
    lock.lock()
    received = [:]
    lock.unlock()
  }

  static func receivedRequest(named name: String) -> URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return received[name]
  }

  override class func canInit(with request: URLRequest) -> Bool {
    ["image-test.local", "public-image.local", "third-image.local"].contains(
      request.url?.host ?? ""
    )
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    if url.path == "/api/v1/seed-cookie" {
      respond(
        statusCode: 200,
        headers: [
          "Content-Type": "application/json",
          "Set-Cookie": "resource_cookie=session-a; Path=/",
        ],
        data: Data("[]".utf8)
      )
      return
    }

    let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first(where: { $0.name == "case" })?.value
    switch item {
    case "redirect-third":
      redirect(to: URL(string: "https://third-image.local/third-final")!)
    case "redirect-public-path":
      redirect(to: URL(string: "https://image-test.local/public-final")!)
    case "downgrade":
      redirect(to: URL(string: "http://third-image.local/downgrade-final")!)
    default:
      switch (url.host, url.path) {
      case ("public-image.local", "/public-to-protected"):
        redirect(
          to: URL(
            string:
              "https://image-test.local/api/v1/system/cache/image?case=public-to-protected-final"
          )!
        )
      case ("public-image.local", "/fake-image"):
        respond(
          statusCode: 200,
          headers: ["Content-Type": "image/jpeg"],
          data: Data("not an image".utf8)
        )
      case ("public-image.local", "/oversized"):
        respond(
          statusCode: 200,
          headers: [
            "Content-Type": "image/jpeg",
            "Content-Length": "9000001",
          ],
          data: Self.imageData
        )
      case ("public-image.local", "/body-too-large"):
        respond(
          statusCode: 200,
          headers: ["Content-Type": "image/gif"],
          data: Self.imageData
        )
      case ("public-image.local", "/valid-image"):
        imageResponse()
      case ("third-image.local", "/third-final"):
        record("third-final")
        imageResponse()
      case ("third-image.local", "/downgrade-final"):
        record("downgrade-final")
        imageResponse()
      case ("image-test.local", "/public-final"):
        record("public-final")
        imageResponse()
      case ("image-test.local", "/api/v1/system/cache/image"):
        record(item == "public-to-protected-final" ? "public-to-protected-final" : "direct")
        imageResponse()
      default:
        respond(statusCode: 404, headers: [:], data: Data())
      }
    }
  }

  override func stopLoading() {}

  private func record(_ name: String) {
    Self.lock.lock()
    Self.received[name] = request
    Self.lock.unlock()
  }

  private func imageResponse() {
    respond(
      statusCode: 200,
      headers: ["Content-Type": "image/gif"],
      data: Self.imageData
    )
  }

  private func redirect(to url: URL) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 302,
      httpVersion: "HTTP/1.1",
      headerFields: ["Location": url.absoluteString]
    )!
    client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: url), redirectResponse: response)
  }

  private func respond(statusCode: Int, headers: [String: String], data: Data) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !data.isEmpty {
      client?.urlProtocol(self, didLoad: data)
    }
    client?.urlProtocolDidFinishLoading(self)
  }
}
