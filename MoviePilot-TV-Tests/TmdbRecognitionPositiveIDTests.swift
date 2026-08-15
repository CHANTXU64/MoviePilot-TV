import XCTest

@testable import MoviePilot_TV

@MainActor
final class TmdbRecognitionPositiveIDTests: XCTestCase {
  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(TmdbRecognitionURLProtocol.self))
    TmdbRecognitionURLProtocol.stub.reset()
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(TmdbRecognitionURLProtocol.self)
    TmdbRecognitionURLProtocol.stub.reset()
    super.tearDown()
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://tmdb-recognition-tests.local"
    service.tokenForTesting = "recognition-token"
    service.currentUserForTesting = Token(
      access_token: "recognition-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: nil,
      user_name: "recognition-admin",
      avatar: nil
    )
    return service
  }

  func testSearchSkipsZeroCandidateAndPicksPositiveCandidate() async {
    TmdbRecognitionURLProtocol.stub.setSearchResults(
      """
      [
        {"tmdb_id":0,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"},
        {"tmdb_id":42,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"}
      ]
      """
    )

    let service = makeService()
    let recognized = await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }

  func testSearchSkipsNegativeCandidateAndPicksPositiveCandidate() async {
    TmdbRecognitionURLProtocol.stub.setSearchResults(
      """
      [
        {"tmdb_id":-1,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"},
        {"tmdb_id":42,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"}
      ]
      """
    )

    let service = makeService()
    let recognized = await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }

  func testRecognizeFallbackZeroResultIsRejected() async {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":0,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()
    let recognized = await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertNil(recognized)
  }

  func testRecognizeFallbackPositiveResultIsAccepted() async {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":42,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()
    let recognized = await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }
}

private final class TmdbRecognitionURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var searchResults = "[]"
  private var recognizeResult = #"{"media_info":null}"#

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    searchResults = "[]"
    recognizeResult = #"{"media_info":null}"#
  }

  func setSearchResults(_ json: String) {
    lock.lock()
    defer { lock.unlock() }
    searchResults = json
  }

  func setRecognizeResult(_ json: String) {
    lock.lock()
    defer { lock.unlock() }
    recognizeResult = json
  }

  func searchResultsValue() -> String {
    lock.lock()
    defer { lock.unlock() }
    return searchResults
  }

  func recognizeResultValue() -> String {
    lock.lock()
    defer { lock.unlock() }
    return recognizeResult
  }
}

private final class TmdbRecognitionURLProtocol: URLProtocol {
  static let stub = TmdbRecognitionURLProtocolStub()

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "tmdb-recognition-tests.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    switch url.path {
    case "/api/v1/media/search":
      respond(statusCode: 200, body: Self.stub.searchResultsValue())
    case "/api/v1/media/recognize":
      respond(statusCode: 200, body: Self.stub.recognizeResultValue())
    default:
      respond(statusCode: 200, body: "[]")
    }
  }

  override func stopLoading() {}

  private func respond(statusCode: Int, body: String) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
