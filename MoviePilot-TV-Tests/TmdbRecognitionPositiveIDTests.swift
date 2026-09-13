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

  func testSearchSkipsZeroCandidateAndPicksPositiveCandidate() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults(
      """
      [
        {"tmdb_id":0,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"},
        {"tmdb_id":42,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"}
      ]
      """
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }

  func testSearchSkipsNegativeCandidateAndPicksPositiveCandidate() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults(
      """
      [
        {"tmdb_id":-1,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"},
        {"tmdb_id":42,"title":"测试电影","original_title":null,"original_name":null,"type":"电影","year":"2025"}
      ]
      """
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }

  func testRecognizeFallbackZeroResultIsRejected() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":0,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertNil(recognized)
  }

  func testRecognizeFallbackPositiveResultIsAccepted() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":42,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")

    XCTAssertEqual(recognized, 42)
  }

  func testSearchFailureThrowsInsteadOfReturningNil() async {
    TmdbRecognitionURLProtocol.stub.setSearchStatusCode(500)
    TmdbRecognitionURLProtocol.stub.setRecognizeStatusCode(500)

    let service = makeService()

    do {
      _ = try await service.recognizeTmdbId(title: "测试电影", year: "2025", type: "电影")
      XCTFail("搜索与兜底都失败时应抛出错误，而不是伪装 no-match")
    } catch is CancellationError {
      XCTFail("不应将后端错误折叠为取消")
    } catch {
      // 期望：抛出后端错误
    }
  }

  func testSearchFailureThenFallbackSuccessReturnsId() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchStatusCode(500)
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":42,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(
      title: "测试电影",
      year: "2025",
      type: "电影"
    )

    XCTAssertEqual(recognized, 42)
  }

  func testBothStagesNoMatchStillReturnsNil() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(#"{"media_info":null}"#)

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(
      title: "测试电影",
      year: "2025",
      type: "电影"
    )

    XCTAssertNil(recognized)
  }

  /// F-122：首段搜索失败、兜底请求成功但无匹配时，不得把「查询没做完」伪装成「真无匹配」。
  func testSearchFailureThenFallbackNoMatchThrowsInsteadOfReturningNil() async {
    TmdbRecognitionURLProtocol.stub.setSearchStatusCode(500)
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(#"{"media_info":null}"#)

    let service = makeService()

    do {
      let recognized = try await service.recognizeTmdbId(
        title: "测试电影",
        year: "2025",
        type: "电影"
      )
      XCTFail("首段失败 + 兜底无匹配时应抛出首段错误，而不是返回 nil（会被弹成「媒体不存在」），实际返回 \(String(describing: recognized))")
    } catch is CancellationError {
      XCTFail("不应将后端错误折叠为取消")
    } catch {
      // 期望：抛出首段后端错误
    }
  }

  /// 与上一条配对：兜底**给出了结果但没有可用 ID** 时同样不得伪装 no-match。
  func testSearchFailureThenFallbackMissingIdThrowsInsteadOfReturningNil() async {
    TmdbRecognitionURLProtocol.stub.setSearchStatusCode(500)
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":0,"title":"测试电影","type":"电影"}}"#
    )

    let service = makeService()

    do {
      let recognized = try await service.recognizeTmdbId(
        title: "测试电影",
        year: "2025",
        type: "电影"
      )
      XCTFail("兜底只给出 0 号 ID（无效）时应抛出首段错误，实际返回 \(String(describing: recognized))")
    } catch is CancellationError {
      XCTFail("不应将后端错误折叠为取消")
    } catch {
      // 期望：抛出首段后端错误
    }
  }

  /// F-122 的另一条漏网路径：兜底**成功但类型不符**时原先是直接 `return nil`，走不到方法
  /// 尾部的 `throw firstStageError`。首段（超时/500）其实从没查完，nil 却会被
  /// `getTMDBJumpTarget` 当成「媒体不存在」并弹出误导提示。
  func testSearchFailureThenFallbackTypeMismatchThrowsInsteadOfReturningNil() async {
    TmdbRecognitionURLProtocol.stub.setSearchStatusCode(500)
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":42,"title":"测试电影","type":"电视剧"}}"#
    )

    let service = makeService()

    do {
      let recognized = try await service.recognizeTmdbId(
        title: "测试电影",
        year: "2025",
        type: "电影"
      )
      XCTFail("首段失败 + 兜底类型不符时应抛出首段错误，实际返回 \(String(describing: recognized))")
    } catch is CancellationError {
      XCTFail("不应将后端错误折叠为取消")
    } catch {
      // 期望：抛出首段后端错误
    }
  }

  /// **阴性对照**：两段都成功、兜底明确认成另一种类型时，`nil`（= 不是这部媒体）仍然是对的 ——
  /// 不能因为上面那条把「类型不符」一律当成错误抛出去。修复前后都通过，
  /// 它守的是上一条的 `firstStageError` 条件别被放宽成无条件 throw。
  func testBothStagesSuccessThenFallbackTypeMismatchStillReturnsNil() async throws {
    TmdbRecognitionURLProtocol.stub.setSearchResults("[]")
    TmdbRecognitionURLProtocol.stub.setRecognizeResult(
      #"{"media_info":{"tmdb_id":42,"title":"测试电影","type":"电视剧"}}"#
    )

    let service = makeService()
    let recognized = try await service.recognizeTmdbId(
      title: "测试电影",
      year: "2025",
      type: "电影"
    )

    XCTAssertNil(recognized, "首段查完且无匹配、兜底认成另一类型 —— 这才是真的不属于这部媒体")
  }
}

private final class TmdbRecognitionURLProtocolStub: @unchecked Sendable {
  private let lock = NSLock()
  private var searchResults = "[]"
  private var recognizeResult = #"{"media_info":null}"#
  private var searchStatusCode = 200
  private var recognizeStatusCode = 200

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    searchResults = "[]"
    recognizeResult = #"{"media_info":null}"#
    searchStatusCode = 200
    recognizeStatusCode = 200
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

  func setSearchStatusCode(_ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    searchStatusCode = statusCode
  }

  func setRecognizeStatusCode(_ statusCode: Int) {
    lock.lock()
    defer { lock.unlock() }
    recognizeStatusCode = statusCode
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

  func searchStatusCodeValue() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return searchStatusCode
  }

  func recognizeStatusCodeValue() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return recognizeStatusCode
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
      respond(statusCode: Self.stub.searchStatusCodeValue(), body: Self.stub.searchResultsValue())
    case "/api/v1/media/recognize":
      respond(
        statusCode: Self.stub.recognizeStatusCodeValue(),
        body: Self.stub.recognizeResultValue()
      )
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
