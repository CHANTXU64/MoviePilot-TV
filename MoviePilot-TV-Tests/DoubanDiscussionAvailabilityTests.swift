import XCTest

@testable import MoviePilot_TV

@MainActor
final class DoubanDiscussionAvailabilityTests: XCTestCase {
  // MARK: - 版本门禁

  /// 入口是「新行为版本限制」：接口本身自 v3.1.7 已有，TV 从 v3.2.1 起才展示，
  /// 更低版本、缺失版本、无法解析的版本都必须隐藏且不发请求。
  func testVersionGateStartsAtBackend321() {
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: nil))
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: ""))
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: "   "))
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: "unknown"))
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: "v3.1.7"))
    XCTAssertFalse(DoubanDiscussionAvailability.supports(backendVersion: "v3.2.0"))
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v3.2.1"))
    // 热修版本号高于同 patch 的正式版本，仍属于支持范围。
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v3.2.1-1"))
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v3.2.2"))
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v3.2.3"))
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v3.3.0"))
    XCTAssertTrue(DoubanDiscussionAvailability.supports(backendVersion: "v4.0.0"))
  }

  // MARK: - 入口条件

  /// 版本、豆瓣 ID、媒体类型三者缺一不可；音乐/合集等类型后端无法解析媒体类型。
  func testEligibilityRequiresVersionDoubanIDAndSupportedMediaType() {
    let movie = MediaInfo(
      douban_id: "1292052",
      source: "douban",
      title: "肖申克的救赎",
      type: "电影"
    )
    XCTAssertTrue(DoubanDiscussionAvailability.isEligible(detail: movie, backendVersion: "v3.2.1"))
    XCTAssertFalse(DoubanDiscussionAvailability.isEligible(detail: movie, backendVersion: "v3.2.0"))
    XCTAssertFalse(DoubanDiscussionAvailability.isEligible(detail: movie, backendVersion: nil))

    let noDouban = MediaInfo(tmdb_id: 1, source: "themoviedb", title: "测试", type: "电影")
    XCTAssertFalse(
      DoubanDiscussionAvailability.isEligible(detail: noDouban, backendVersion: "v3.2.1"))

    let blankDouban = MediaInfo(douban_id: "   ", source: "douban", title: "测试", type: "电影")
    XCTAssertFalse(
      DoubanDiscussionAvailability.isEligible(detail: blankDouban, backendVersion: "v3.2.1"))

    let music = MediaInfo(douban_id: "1", source: "douban", title: "测试", type: "音乐")
    XCTAssertFalse(DoubanDiscussionAvailability.isEligible(detail: music, backendVersion: "v3.2.1"))

    let collection = MediaInfo(douban_id: "1", source: "douban", title: "测试", type: "合集")
    XCTAssertFalse(
      DoubanDiscussionAvailability.isEligible(detail: collection, backendVersion: "v3.2.1"))

    let missingType = MediaInfo(douban_id: "1", source: "douban", title: "测试")
    XCTAssertFalse(
      DoubanDiscussionAvailability.isEligible(detail: missingType, backendVersion: "v3.2.1"))

    let tv = MediaInfo(douban_id: "1", source: "douban", title: "测试", type: "电视剧")
    XCTAssertTrue(DoubanDiscussionAvailability.isEligible(detail: tv, backendVersion: "v3.2.1"))
  }

  // MARK: - 行状态与区块可见性

  private func state(
    requested: Bool = true,
    inFlight: Bool = false,
    items: Int = 0,
    firstLoading: Bool = false,
    error: Bool = false,
    hasMore: Bool = true
  ) -> DoubanDiscussionRowState {
    DoubanDiscussionAvailability.rowState(
      hasRequested: requested,
      isFirstPageInFlight: inFlight,
      itemCount: items,
      isLoadingFirstPage: firstLoading,
      hasError: error,
      hasMore: hasMore
    )
  }

  /// 未请求 / 加载中 / 失败 / 空 / 有内容 必须是互不折叠的五种状态。
  func testRowStateMatrix() {
    XCTAssertEqual(state(requested: false), .idle)
    XCTAssertEqual(state(inFlight: true, firstLoading: true), .loading)
    XCTAssertEqual(state(error: true), .failed)
    XCTAssertEqual(state(hasMore: false), .empty)
    XCTAssertEqual(state(items: 3), .ready)
    // loadMore 失败时不清空已加载内容，仍按 ready 展示。
    XCTAssertEqual(state(items: 3, error: true), .ready)
    // 首屏请求进行中、分页器刚 reset 还没开始加载：按加载中处理，
    // 重试时状态卡不会闪成「未请求」而把焦点带出区块。
    XCTAssertEqual(state(inFlight: true), .loading)
    // 首屏请求已结束却没有结果（被中途取消）：按失败处理，可以重试，不会一直转圈。
    XCTAssertEqual(state(), .failed)
  }

  /// 两类都未请求或都确认为空时整块隐藏；任一类加载中、失败或有内容时展示。
  func testSectionVisibility() {
    let visible = DoubanDiscussionAvailability.isSectionVisible
    XCTAssertFalse(visible(.idle, .idle))
    XCTAssertFalse(visible(.empty, .idle))
    XCTAssertFalse(visible(.empty, .empty))
    XCTAssertTrue(visible(.loading, .idle))
    XCTAssertTrue(visible(.failed, .idle))
    XCTAssertTrue(visible(.ready, .idle))
    XCTAssertTrue(visible(.empty, .loading))
    XCTAssertTrue(visible(.empty, .ready))
    XCTAssertTrue(visible(.ready, .empty))
  }

  /// 胶囊文字与 Web 页签一致：优先用 `total`，没有时用已加载条数，0 不显示数量。
  func testChipTitleShowsCountLikeWeb() {
    let title = DoubanDiscussionAvailability.chipTitle
    XCTAssertEqual(title(.comment, 128, 10), "短评 128")
    XCTAssertEqual(title(.review, nil, 3), "影评 3")
    XCTAssertEqual(title(.review, nil, 0), "影评")
    XCTAssertEqual(title(.comment, 0, 0), "短评")
    XCTAssertEqual(title(.comment, 12873, 10), "短评 12873", "与 Web 一致，原样显示，不加千分位")
  }

  // MARK: - 模型与展示

  /// 后端字段全 Optional：缺 id/decode 组合不得拖垮整页，正文换行必须保留。
  func testCommentPageDecodesSparseEntriesAndPreservesLineBreaks() throws {
    let json = """
      {
        "start": 0,
        "count": 2,
        "total": 42,
        "items": [
          {
            "id": "c1",
            "comment": "第一部\\n\\n第二段",
            "rating": 4.5,
            "vote_count": 12,
            "create_time": "2024-01-01",
            "author": {
              "name": "影迷",
              "avatar": "https://img9.doubanio.com/view/celebrity/s_ratio_celebrity/public/p1.jpg"
            },
            "url": "https://movie.douban.com/review/1/"
          },
          {
            "comment": "没有 id 也没有评分",
            "author": {}
          }
        ]
      }
      """

    let page = try decode(json, as: DoubanCommentPage.self)
    XCTAssertEqual(page.total, 42)
    XCTAssertEqual(page.resolvedItems.count, 2)

    let first = DoubanDiscussionEntry(comment: page.resolvedItems[0])
    XCTAssertEqual(first.kind, .comment)
    XCTAssertNil(first.title)
    XCTAssertEqual(first.displayAuthorName, "影迷")
    XCTAssertEqual(first.authorInitial, "影")
    XCTAssertEqual(first.ratingText, "4.5")
    XCTAssertEqual(first.usefulText, "12 有用")
    XCTAssertEqual(first.paragraphs, ["第一部", "第二段"])
    XCTAssertEqual(first.id, "comment:c1")

    let second = DoubanDiscussionEntry(comment: page.resolvedItems[1])
    // 缺失 id 时用「作者 + 时间 + 正文前缀」兜底，不能和第一条撞成同一个 key。
    XCTAssertNotEqual(second.id, first.id)
    XCTAssertEqual(second.displayAuthorName, "豆瓣用户")
    XCTAssertNil(second.ratingText)
    XCTAssertNil(second.usefulText)
  }

  /// 影评与短评共用同一张卡片模型：只是多一行标题，摘要保留换行。
  func testReviewPageUsesTitleAndAbstractWithSingleCardTemplate() throws {
    let json = """
      {
        "start": 0,
        "count": 1,
        "total": 1,
        "items": [
          {
            "id": "r1",
            "title": "标题在作者名下面",
            "abstract": "摘要第一段\\n摘要第二段",
            "rating": 3.5,
            "useful_count": 5,
            "comments_count": 7,
            "create_time": "2024-02-02",
            "author": { "name": "作者" },
            "url": "https://movie.douban.com/review/2/"
          }
        ]
      }
      """

    let page = try decode(json, as: DoubanReviewPage.self)
    XCTAssertEqual(page.resolvedItems.count, 1)

    let entry = DoubanDiscussionEntry(review: page.resolvedItems[0])
    XCTAssertEqual(entry.kind, .review)
    XCTAssertEqual(entry.title, "标题在作者名下面")
    XCTAssertEqual(entry.body, "摘要第一段\n摘要第二段")
    // 单个换行留在段内（与 Web 的 pre-line 一致），只有空行才分段。
    XCTAssertEqual(entry.paragraphs, ["摘要第一段\n摘要第二段"])
    XCTAssertEqual(entry.ratingText, "3.5")
    XCTAssertEqual(entry.usefulText, "5 有用")
    XCTAssertEqual(entry.id, "review:r1")
  }

  /// 成功但没有任何条目 → 空数组，由视图隐藏整行。
  func testEmptyPageDecodesToNoItems() throws {
    let page = try decode("{}", as: DoubanCommentPage.self)
    XCTAssertTrue(page.resolvedItems.isEmpty)

    let reviewPage = try decode(#"{"items":null}"#, as: DoubanReviewPage.self)
    XCTAssertTrue(reviewPage.resolvedItems.isEmpty)
  }

  private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }
}
