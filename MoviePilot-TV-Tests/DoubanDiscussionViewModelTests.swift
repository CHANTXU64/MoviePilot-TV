import XCTest

@testable import MoviePilot_TV

@MainActor
final class DoubanDiscussionViewModelTests: XCTestCase {
  private var service: APIService!
  private var account: Token!

  override func setUp() {
    super.setUp()
    XCTAssertTrue(APIService.installURLProtocolForTesting(DoubanDetailStubURLProtocol.self))
    DoubanDetailStubURLProtocol.reset()

    account = Token(
      access_token: "douban-detail-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true, "search": true, "subscribe": false, "manage": false],
      user_id: 602,
      user_name: "douban-detail-user",
      avatar: nil
    )
    service = APIService.isolatedTestingInstance()
    service.replaceSessionForTesting(
      baseURL: "http://douban-detail.local",
      token: account.access_token,
      currentUser: account
    )
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(DoubanDetailStubURLProtocol.self)
    service = nil
    account = nil
    super.tearDown()
  }

  // MARK: - 进入详情页即请求

  /// 进入详情页只拉短评第一页；影评与 Web 一样等用户切过去才请求，两类各只请求一次。
  func testEnteringDetailPageRequestsCommentsOnlyAndReviewsOnDemand() async throws {
    DoubanDetailStubURLProtocol.commentBodies = [
      0: commentPageJSON(start: 0, count: 10, total: 30, ids: (1...10).map { "c\($0)" })
    ]
    DoubanDetailStubURLProtocol.reviewBodies = [
      0: reviewPageJSON(start: 0, count: 1, total: 1)
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)

    try await waitUntil("短评第一页") { viewModel.doubanCommentsPaginator.items.count == 10 }
    XCTAssertEqual(viewModel.doubanDiscussionKind, .comment)
    XCTAssertEqual(viewModel.doubanRowState(for: .review), .idle)
    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/reviews/").isEmpty)

    viewModel.selectDoubanDiscussion(.review)
    XCTAssertEqual(viewModel.doubanDiscussionKind, .review)
    try await waitUntil("影评第一页") { viewModel.doubanReviewsPaginator.items.count == 1 }

    // 重复触发（视图重新出现、来回切换胶囊）不得重发第一页请求。
    viewModel.loadDoubanDiscussionIfNeeded()
    viewModel.selectDoubanDiscussion(.comment)
    viewModel.selectDoubanDiscussion(.review)
    try await Task.sleep(for: .milliseconds(150))

    let commentCalls = DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/")
    XCTAssertEqual(commentCalls.map(\.start), [0])
    XCTAssertEqual(commentCalls.first?.count, 10)
    let reviewCalls = DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/reviews/")
    XCTAssertEqual(reviewCalls.map(\.start), [0])
  }

  /// 短评确认为空时自动改看影评，区块仍有内容可看。
  func testEmptyCommentsSwitchToReviewsAutomatically() async throws {
    DoubanDetailStubURLProtocol.reviewBodies = [
      0: reviewPageJSON(start: 0, count: 2, total: 2)
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)

    try await waitUntil("自动切到影评") { viewModel.doubanReviewsPaginator.items.count == 2 }
    XCTAssertEqual(viewModel.doubanDiscussionKind, .review)
    XCTAssertEqual(viewModel.doubanRowState(for: .comment), .empty)
    XCTAssertTrue(viewModel.isDoubanDiscussionSectionVisible)
  }

  /// 两类都为空时整块隐藏。
  func testBothEmptyHidesSection() async throws {
    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)

    try await waitUntil("影评确认为空") { viewModel.doubanRowState(for: .review) == .empty }
    XCTAssertEqual(viewModel.doubanRowState(for: .comment), .empty)
    XCTAssertFalse(viewModel.isDoubanDiscussionSectionVisible)
  }

  /// 用户已经亲手选过分类时，短评后到的空结果不得把选择改掉。
  func testUserChoiceIsNotOverriddenByEmptyComments() async throws {
    DoubanDetailStubURLProtocol.interestsDelay = .milliseconds(200)

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)
    viewModel.selectDoubanDiscussion(.review)
    viewModel.selectDoubanDiscussion(.comment)

    try await waitUntil("短评确认为空") { viewModel.doubanRowState(for: .comment) == .empty }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(viewModel.doubanDiscussionKind, .comment)
  }

  /// 后端低于启用版本 v3.2.1 时：整块隐藏且一个请求都不发。
  func testBackendBelow321HidesSectionAndSendsNoRequest() async throws {
    DoubanDetailStubURLProtocol.commentBodies = [
      0: commentPageJSON(start: 0, count: 10, total: 30, ids: (1...10).map { "c\($0)" })
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.0")
    viewModel.applyFullDetail(detail)
    viewModel.loadDoubanDiscussionIfNeeded()
    viewModel.selectDoubanDiscussion(.review)

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertTrue(viewModel.doubanCommentsPaginator.items.isEmpty)
    XCTAssertTrue(viewModel.doubanReviewsPaginator.items.isEmpty)
    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/").isEmpty)
    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/reviews/").isEmpty)
    XCTAssertEqual(viewModel.doubanRowState(for: .comment), .idle)
    XCTAssertFalse(viewModel.isDoubanDiscussionSectionVisible)
  }

  /// 没有豆瓣 ID 的内容（例如 TMDB-only）同样不发请求。
  func testDetailWithoutDoubanIDSendsNoRequest() async throws {
    let detail = MediaInfo(
      tmdb_id: 27205,
      source: "themoviedb",
      title: "盗梦空间",
      type: "电影"
    )
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)
    viewModel.loadDoubanDiscussionIfNeeded()

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertTrue(viewModel.doubanCommentsPaginator.items.isEmpty)
    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/").isEmpty)
    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/reviews/").isEmpty)
  }

  /// 后端只认「电影 / 电视剧」，其他类型不发请求。
  func testUnsupportedMediaTypeSendsNoRequest() async throws {
    let detail = MediaInfo(douban_id: "123", source: "douban", title: "某合集", type: "合集")
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)
    viewModel.loadDoubanDiscussionIfNeeded()

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertTrue(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/").isEmpty)
  }

  // MARK: - 分页

  /// 聚焦到列表末尾时加载下一页，偏移量按页推进（去重不影响服务端偏移）；重复条目只保留一份。
  func testLoadMoreUsesStartOffsetAndDropsDuplicates() async throws {
    DoubanDetailStubURLProtocol.commentBodies = [
      0: commentPageJSON(start: 0, count: 10, total: 12, ids: (1...10).map { "c\($0)" }),
      // 第二页第 1 条与第一页最后一条同 id，模拟后端排序不稳定导致的重复。
      10: commentPageJSON(start: 10, count: 3, total: 12, ids: ["c10", "c11", "c12"]),
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)
    try await waitUntil("短评第一页") { viewModel.doubanCommentsPaginator.items.count == 10 }

    let lastID = try XCTUnwrap(viewModel.doubanCommentsPaginator.items.last?.id)
    await viewModel.doubanCommentsPaginator.loadMore(lastID)
    try await waitUntil("短评第二页") { viewModel.doubanCommentsPaginator.items.count == 12 }

    let starts = DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/")
      .map(\.start)
    XCTAssertEqual(starts, [0, 10])

    let ids = viewModel.doubanCommentsPaginator.items.map(\.id)
    XCTAssertEqual(ids.count, Set(ids).count, "重复条目未被去重")
  }

  /// 空批次是终页而不是错误：继续滚动不得再发请求。
  func testEmptyBatchTerminatesPaginationAsSuccess() async throws {
    DoubanDetailStubURLProtocol.commentBodies = [
      0: commentPageJSON(start: 0, count: 10, total: 10, ids: (1...10).map { "c\($0)" }),
      10: #"{"success":true,"data":{"start":10,"count":0,"total":10,"items":[]}}"#.data(using: .utf8)!,
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)
    try await waitUntil("短评第一页") { viewModel.doubanCommentsPaginator.items.count == 10 }

    let lastID = try XCTUnwrap(viewModel.doubanCommentsPaginator.items.last?.id)
    await viewModel.doubanCommentsPaginator.loadMore(lastID)
    try await waitUntil("终页") { !viewModel.doubanCommentsPaginator.hasMore }

    let callsAfterTermination = DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/").count
    await viewModel.doubanCommentsPaginator.loadMore(lastID)
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(
      DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/interests/").count,
      callsAfterTermination
    )
    XCTAssertFalse(viewModel.doubanCommentsPaginator.hasError)
    XCTAssertEqual(viewModel.doubanCommentsPaginator.items.count, 10)
  }

  // MARK: - 失败与重试

  /// 短评首屏失败时区块保留可重试状态卡，不阻塞影评；重试只重发当前分类。
  func testFirstPageFailureKeepsRetryCardAndRetriesCurrentKind() async throws {
    DoubanDetailStubURLProtocol.failInterests = true
    DoubanDetailStubURLProtocol.commentBodies = [
      0: commentPageJSON(start: 0, count: 2, total: 2, ids: ["c1", "c2"])
    ]
    DoubanDetailStubURLProtocol.reviewBodies = [
      0: reviewPageJSON(start: 0, count: 1, total: 1)
    ]

    let detail = eligibleMovieDetail()
    let viewModel = makeViewModel(detail: detail, backendVersion: "v3.2.1")
    viewModel.applyFullDetail(detail)

    try await waitUntil("短评失败") { viewModel.doubanRowState(for: .comment) == .failed }
    XCTAssertTrue(viewModel.isDoubanDiscussionSectionVisible)
    // 失败不是空：不得自动切到影评。
    XCTAssertEqual(viewModel.doubanDiscussionKind, .comment)

    // 影评不受短评失败影响。
    viewModel.selectDoubanDiscussion(.review)
    try await waitUntil("影评第一页") { viewModel.doubanReviewsPaginator.items.count == 1 }

    // 回到短评重试，只重发短评。
    viewModel.selectDoubanDiscussion(.comment)
    DoubanDetailStubURLProtocol.failInterests = false
    viewModel.retryDoubanDiscussion()
    try await waitUntil("短评重试成功") { viewModel.doubanCommentsPaginator.items.count == 2 }
    XCTAssertEqual(viewModel.doubanRowState(for: .comment), .ready)
    XCTAssertEqual(DoubanDetailStubURLProtocol.calls(matching: "/api/v1/douban/reviews/").count, 1)
  }

  // MARK: - Helpers

  private func makeViewModel(
    detail: MediaInfo,
    backendVersion: String?
  ) -> MediaDetailViewModel {
    service.settings = GlobalSettings(BACKEND_VERSION: backendVersion)
    return MediaDetailViewModel(detail: detail, apiService: service)
  }

  private func eligibleMovieDetail() -> MediaInfo {
    MediaInfo(
      douban_id: "1292052",
      source: "douban",
      title: "肖申克的救赎",
      type: "电影"
    )
  }

  private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @MainActor () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("等待超时：\(description)", file: file, line: line)
  }

  private func commentPageJSON(
    start: Int,
    count: Int,
    total: Int,
    ids: [String]
  ) -> Data {
    let items = ids.enumerated().map { index, id in
      """
      {
        "id": "\(id)",
        "comment": "短评 \(id)",
        "rating": 4.0,
        "vote_count": \(index + 1),
        "create_time": "2024-01-01T10:00:00",
        "author": { "name": "用户\(index)" }
      }
      """
    }
    let json = """
      {"success":true,"data":{"start":\(start),"count":\(count),"total":\(total),"items":[\(items.joined(separator: ","))]}}
      """
    return Data(json.utf8)
  }

  private func reviewPageJSON(start: Int, count: Int, total: Int) -> Data {
    let ids = (start...max(start, start + count - 1)).map { "r\($0)" }
    let items = ids.enumerated().map { index, id in
      """
      {
        "id": "\(id)",
        "title": "影评标题 \(id)",
        "abstract": "影评摘要 \(id)",
        "rating": 3.0,
        "useful_count": \(index + 1),
        "comments_count": \(index + 2),
        "create_time": "2024-02-02T10:00:00",
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

/// 详情页 ViewModel 的测试替身：只关心豆瓣短评/影评两个分支的偏移量，
/// 其他请求（演职员/推荐/相似/站点）一律返回空 data，避免误触发解码失败。
private final class DoubanDetailStubURLProtocol: URLProtocol {
  struct RecordedCall {
    let path: String
    let start: Int?
    let count: Int?
  }

  nonisolated(unsafe) static var commentBodies: [Int: Data] = [:]
  nonisolated(unsafe) static var reviewBodies: [Int: Data] = [:]
  nonisolated(unsafe) static var failInterests = false
  nonisolated(unsafe) static var interestsDelay: Duration?
  nonisolated(unsafe) static var recordedCalls: [RecordedCall] = []

  private static let lock = NSLock()

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    commentBodies = [:]
    reviewBodies = [:]
    failInterests = false
    interestsDelay = nil
    recordedCalls = []
  }

  static func calls(matching pathPrefix: String) -> [RecordedCall] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls.filter { $0.path.hasPrefix(pathPrefix) }
  }

  private static func record(_ call: RecordedCall) {
    lock.lock()
    defer { lock.unlock() }
    recordedCalls.append(call)
  }

  private static func emptyPage(start: Int) -> Data {
    Data(
      #"{"success":true,"data":{"start":\#(start),"count":0,"total":0,"items":[]}}"#.utf8
    )
  }

  private static func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == name })?.value
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "douban-detail.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let path = url.path
    let start = Self.queryValue("start", in: url).flatMap(Int.init)
    let count = Self.queryValue("count", in: url).flatMap(Int.init)
    Self.record(RecordedCall(path: path, start: start, count: count))

    let isInterests = path.hasPrefix("/api/v1/douban/interests/")
    let isReviews = path.hasPrefix("/api/v1/douban/reviews/")
    let shouldFail = isInterests && Self.failInterests

    let statusCode = shouldFail ? 500 : 200
    let payload: Data
    if shouldFail {
      payload = Data(#"{"success":false,"message":"interests boom"}"#.utf8)
    } else if isInterests {
      payload =
        Self.commentBodies[start ?? 0] ?? Self.emptyPage(start: start ?? 0)
    } else if isReviews {
      payload = Self.reviewBodies[start ?? 0] ?? Self.emptyPage(start: start ?? 0)
    } else {
      payload = Data(#"{"success":true,"data":[]}"#.utf8)
    }

    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let deliver = { [self] in
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: payload)
      client?.urlProtocolDidFinishLoading(self)
    }
    if isInterests, let delay = Self.interestsDelay {
      let milliseconds = Int(delay.components.seconds * 1000)
        + Int(delay.components.attoseconds / 1_000_000_000_000_000)
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: deliver)
    } else {
      deliver()
    }
  }

  override func stopLoading() {}
}
