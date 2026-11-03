import XCTest

@testable import MoviePilot_TV

@MainActor
final class DoubanDiscussionRequestTests: XCTestCase {
  private var service: APIService!
  private var account: Token!

  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(DoubanDiscussionStubURLProtocol.self))
    DoubanDiscussionStubURLProtocol.reset()

    account = Token(
      access_token: "douban-discussion-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_id: 601,
      user_name: "douban-discussion-user",
      avatar: nil
    )
    service = APIService.isolatedTestingInstance()
    service.replaceSessionForTesting(
      baseURL: "http://douban-discussion.local",
      token: account.access_token,
      currentUser: account
    )
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.1")
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(DoubanDiscussionStubURLProtocol.self)
    service = nil
    account = nil
    super.tearDown()
  }

  // MARK: - 请求契约

  /// 短评走 `/douban/interests/{doubanid}/{type_name}`，分页只发偏移量 start 与固定 count。
  func testCommentRequestSendsOffsetAndCount() async throws {
    DoubanDiscussionStubURLProtocol.commentBodies = [
      0: Self.commentPageJSON(start: 0, count: 2, total: 2, ids: ["c1", "c2"])
    ]

    let page = try await service.fetchDoubanComments(
      doubanId: "1292052",
      typeName: "电影",
      start: 0,
      count: 10
    )
    XCTAssertEqual(page.resolvedItems.count, 2)
    XCTAssertEqual(page.resolvedItems.first?.author?.name, "用户0")

    let request = try recordedRequest(pathPrefix: "/api/v1/douban/interests/")
    XCTAssertEqual(request.method, "GET")
    XCTAssertEqual(request.path, "/api/v1/douban/interests/1292052/电影")
    XCTAssertEqual(request.query["start"], "0")
    XCTAssertEqual(request.query["count"], "10")
    // 中文媒体类型必须百分号编码进 path，不能直接塞进 URL。
    XCTAssertTrue(
      request.url.absoluteString.contains("%E7%94%B5%E5%BD%B1"),
      "媒体类型未按 URL path 规则编码：\(request.url.absoluteString)"
    )
  }

  /// 影评走 `/douban/reviews/{doubanid}/{type_name}`，与短评同一套偏移分页。
  func testReviewRequestSendsOffsetAndCount() async throws {
    DoubanDiscussionStubURLProtocol.reviewBodies = [
      20: Self.reviewPageJSON(start: 20, count: 1, total: 21, ids: ["r21"])
    ]

    let page = try await service.fetchDoubanReviews(
      doubanId: "1292052",
      typeName: "电视剧",
      start: 20,
      count: 10
    )
    XCTAssertEqual(page.resolvedItems.count, 1)
    XCTAssertEqual(page.resolvedItems.first?.title, "标题20")

    let request = try recordedRequest(pathPrefix: "/api/v1/douban/reviews/")
    XCTAssertEqual(request.path, "/api/v1/douban/reviews/1292052/电视剧")
    XCTAssertEqual(request.query["start"], "20")
    XCTAssertEqual(request.query["count"], "10")
  }

  /// 偏移分页：第二页必须是 start=10 而不是 page=2。
  func testSecondPageSendsOffsetStart() async throws {
    DoubanDiscussionStubURLProtocol.commentBodies = [
      0: Self.commentPageJSON(start: 0, count: 10, total: 12, ids: (1...10).map { "c\($0)" }),
      10: Self.commentPageJSON(start: 10, count: 2, total: 12, ids: ["c11", "c12"]),
    ]

    _ = try await service.fetchDoubanComments(
      doubanId: "1", typeName: "电影", start: 0, count: 10)
    _ = try await service.fetchDoubanComments(
      doubanId: "1", typeName: "电影", start: 10, count: 10)

    let starts = DoubanDiscussionStubURLProtocol.recordedRequests
      .filter { ($0.url?.path ?? "").hasPrefix("/api/v1/douban/interests/") }
      .compactMap { Self.queryValue("start", in: $0.url) }
    XCTAssertEqual(starts, ["0", "10"])
  }

  /// 豆瓣 ID 按单个路径段编码：里面的 `/` 不得把路径拆成多段。
  func testDoubanIDIsEncodedAsSinglePathSegment() async throws {
    DoubanDiscussionStubURLProtocol.commentBodies = [
      0: Self.commentPageJSON(start: 0, count: 1, total: 1, ids: ["c1"])
    ]
    _ = try await service.fetchDoubanComments(
      doubanId: "12/34", typeName: "电影", start: 0, count: 10)

    let request = try recordedRequest(pathPrefix: "/api/v1/douban/interests/")
    XCTAssertTrue(
      request.url.absoluteString.contains("/douban/interests/12%2F34/%E7%94%B5%E5%BD%B1?"),
      "豆瓣 ID 未按单个路径段编码：\(request.url.absoluteString)"
    )
  }

  // MARK: - 头像

  /// 豆瓣头像必须经后端图片代理，直连豆瓣 CDN 会 418。
  func testCommentAvatarUsesBackendImageProxy() throws {
    service.useImageCache = false
    let rawAvatar =
      "https://img9.doubanio.com/view/celebrity/s_ratio_celebrity/public/p1.jpg"

    let url = try XCTUnwrap(service.getDoubanCommentAvatarImageUrl(rawAvatar))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.path, "/api/v1/system/img/0")
    let imgurl = try XCTUnwrap(
      components.queryItems?.first(where: { $0.name == "imgurl" })?.value)
    XCTAssertTrue(imgurl.contains("doubanio.com"))
    XCTAssertTrue(imgurl.contains("p1.jpg"))
  }

  /// 开启全局图片缓存时走缓存代理分支，仍然不能暴露原始豆瓣地址。
  func testCommentAvatarUsesCacheProxyWhenImageCacheEnabled() throws {
    service.useImageCache = true
    let rawAvatar =
      "https://img9.doubanio.com/view/celebrity/s_ratio_celebrity/public/p1.jpg"

    let url = try XCTUnwrap(service.getDoubanCommentAvatarImageUrl(rawAvatar))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.path, "/api/v1/system/cache/image")
    let proxied = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "url" })?.value)
    XCTAssertTrue(proxied.contains("doubanio.com"))
  }

  /// 无头像 / 空白头像不生成 URL，卡片据此回退到首字母占位。
  func testMissingAvatarReturnsNil() {
    XCTAssertNil(service.getDoubanCommentAvatarImageUrl(nil))
    XCTAssertNil(service.getDoubanCommentAvatarImageUrl(""))
    XCTAssertNil(service.getDoubanCommentAvatarImageUrl("   "))
  }

  // MARK: - Helpers

  private struct RecordedRequest {
    let url: URL
    let method: String?
    let path: String
    let query: [String: String]
  }

  private func recordedRequest(pathPrefix: String) throws -> RecordedRequest {
    let request = try XCTUnwrap(
      DoubanDiscussionStubURLProtocol.recordedRequests.first {
        ($0.url?.path ?? "").hasPrefix(pathPrefix)
      })
    let url = try XCTUnwrap(request.url)
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    var query: [String: String] = [:]
    for item in components.queryItems ?? [] {
      query[item.name] = item.value
    }
    return RecordedRequest(
      url: url,
      method: request.httpMethod,
      path: components.path,
      query: query
    )
  }

  private static func queryValue(_ name: String, in url: URL?) -> String? {
    guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    return components.queryItems?.first(where: { $0.name == name })?.value
  }

  private static func commentPageJSON(start: Int, count: Int, total: Int, ids: [String])
    -> Data
  {
    let items = ids.enumerated().map { index, id in
      """
      {
        "id": "\(id)",
        "comment": "短评\(index)",
        "rating": 4.0,
        "vote_count": \(index),
        "create_time": "2024-01-01",
        "author": { "name": "用户\(index)" }
      }
      """
    }
    let json = """
      {"success":true,"data":{"start":\(start),"count":\(count),"total":\(total),"items":[\(items.joined(separator: ","))]}}
      """
    return Data(json.utf8)
  }

  private static func reviewPageJSON(start: Int, count: Int, total: Int, ids: [String]) -> Data {
    let items = ids.enumerated().map { index, id in
      """
      {
        "id": "\(id)",
        "title": "标题\(index + start)",
        "abstract": "摘要\(index)",
        "rating": 3.0,
        "useful_count": \(index),
        "comments_count": \(index),
        "create_time": "2024-02-02",
        "author": { "name": "作者\(index)" }
      }
      """
    }
    let json = """
      {"success":true,"data":{"start":\(start),"count":\(count),"total":\(total),"items":[\(items.joined(separator: ","))]}}
      """
    return Data(json.utf8)
  }
}

/// 只接管豆瓣短评/影评两个接口分支，其余请求返回空 data，
/// 避免把未预期路径的响应误当成成功。
private final class DoubanDiscussionStubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var commentBodies: [Int: Data] = [:]
  nonisolated(unsafe) static var reviewBodies: [Int: Data] = [:]
  nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

  private static let lock = NSLock()

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    commentBodies = [:]
    reviewBodies = [:]
    recordedRequests = []
  }

  private static func record(_ request: URLRequest) {
    lock.lock()
    defer { lock.unlock() }
    recordedRequests.append(request)
  }

  private static func body(for url: URL) -> Data {
    let path = url.path
    let start =
      URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "start" })?.value
      .flatMap(Int.init) ?? 0
    if path.hasPrefix("/api/v1/douban/interests/") {
      return commentBodies[start] ?? Data(#"{"success":true,"data":[]}"#.utf8)
    }
    if path.hasPrefix("/api/v1/douban/reviews/") {
      return reviewBodies[start] ?? Data(#"{"success":true,"data":[]}"#.utf8)
    }
    return Data(#"{"success":true,"data":[]}"#.utf8)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "douban-discussion.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    Self.record(request)
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body(for: url))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
