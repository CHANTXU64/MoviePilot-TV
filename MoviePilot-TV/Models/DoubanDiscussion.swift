import Foundation

/// 豆瓣短评/影评的公共身份与展示规则。
///
/// 后端 `app/schemas/comment.py` 的 `MediaCommentPage` / `MediaReviewPage` 所有字段都是
/// Optional，且豆瓣条目的 `id` 并不保证存在，因此这里统一用 `stableID` 生成去重键：
/// 优先用后端透传的 `id`，退化为条目 `url`，最后用「作者 + 时间 + 正文前缀」兜底，
/// 避免同一页内多条空 id 被折叠成一条。
nonisolated enum DoubanDiscussionIdentity {
  /// 去掉首尾空白；纯空白视同缺失。
  static func normalized(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  static func stableID(
    prefix: String,
    remoteID: String?,
    url: String?,
    authorName: String?,
    time: String?,
    text: String?
  ) -> String {
    if let remoteID = normalized(remoteID) {
      return "\(prefix):\(remoteID)"
    }
    if let url = normalized(url) {
      return "\(prefix):url:\(url)"
    }
    let parts = [authorName, time, text.map { String($0.prefix(48)) }]
      .map { normalized($0) ?? "n" }
    return "\(prefix):fallback:\(parts.joined(separator: "|"))"
  }
}

/// 豆瓣评论作者。
nonisolated struct DoubanDiscussionAuthor: Decodable, Hashable, Sendable {
  let id: String?
  let name: String?
  /// 豆瓣头像原始地址。豆瓣 CDN 对非同源 Referer 返回 418，展示时必须走后端图片代理，
  /// 不能直接把该地址交给图片组件。
  let avatar: String?
  let url: String?
}

/// 豆瓣短评条目（后端 `MediaComment`）。
nonisolated struct DoubanComment: Decodable, Hashable, Sendable, Identifiable {
  let remoteID: String?
  let comment: String?
  /// 五星制评分，可能为 null。
  let rating: Double?
  /// 有用数（后端 `vote_count`）。
  let voteCount: Int?
  let createTime: String?
  let author: DoubanDiscussionAuthor?
  let url: String?

  enum CodingKeys: String, CodingKey {
    case remoteID = "id"
    case comment, rating, author, url
    case voteCount = "vote_count"
    case createTime = "create_time"
  }

  var id: String {
    DoubanDiscussionIdentity.stableID(
      prefix: "comment",
      remoteID: remoteID,
      url: url,
      authorName: author?.name,
      time: createTime,
      text: comment
    )
  }
}

/// 豆瓣影评条目（后端 `MediaReview`）。`abstract` 只是豆瓣返回的摘要，不是全文。
nonisolated struct DoubanReview: Decodable, Hashable, Sendable, Identifiable {
  let remoteID: String?
  let title: String?
  let abstract: String?
  /// 五星制评分，可能为 null。
  let rating: Double?
  /// 有用数（后端 `useful_count`）。
  let usefulCount: Int?
  let createTime: String?
  let author: DoubanDiscussionAuthor?
  let url: String?

  enum CodingKeys: String, CodingKey {
    case remoteID = "id"
    case title, abstract, rating, author, url
    case usefulCount = "useful_count"
    case createTime = "create_time"
  }

  var id: String {
    DoubanDiscussionIdentity.stableID(
      prefix: "review",
      remoteID: remoteID,
      url: url,
      authorName: author?.name,
      time: createTime,
      text: abstract ?? title
    )
  }
}

/// 短评分页响应（后端 `MediaCommentPage`）。
nonisolated struct DoubanCommentPage: Decodable, Sendable {
  let start: Int?
  let count: Int?
  let total: Int?
  let items: [DoubanComment]?

  var resolvedItems: [DoubanComment] { items ?? [] }
}

/// 影评分页响应（后端 `MediaReviewPage`）。
nonisolated struct DoubanReviewPage: Decodable, Sendable {
  let start: Int?
  let count: Int?
  let total: Int?
  let items: [DoubanReview]?

  var resolvedItems: [DoubanReview] { items ?? [] }
}

/// 详情页卡片与 Sheet 共用的展示模型。
///
/// 短评与影评共用同一张卡片模板（作者行 → 标题 → 正文 → 元信息），
/// 影评只是多了 `title` 这一行，避免两套视觉。`usefulCount` 展示为「N 有用」，
/// 与 Web 的 `media.usefulCount`（`{count} 有用`）一致；Web 不展示回应数，这里同样不展示。
nonisolated struct DoubanDiscussionEntry: Identifiable, Hashable, Sendable {
  nonisolated enum Kind: String, CaseIterable, Identifiable, Sendable {
    case comment
    case review

    var id: String { rawValue }

    var title: String {
      switch self {
      case .comment: return "短评"
      case .review: return "影评"
      }
    }

    var emptyText: String { "暂无\(title)" }
    var failureText: String { "\(title)加载失败" }
  }

  /// 五星制评分的单颗星填充状态。
  nonisolated enum StarFill: Equatable, Sendable {
    case full
    case half
    case empty
  }

  let kind: Kind
  /// 条目稳定 ID，同时作为 `Identifiable.id` 与列表去重键。
  let itemID: String
  let authorName: String?
  let avatar: String?
  let rating: Double?
  /// 仅影评有标题。
  let title: String?
  let body: String
  let createTime: String?
  let usefulCount: Int?

  var id: String { itemID }

  init(comment: DoubanComment) {
    self.kind = .comment
    self.itemID = comment.id
    self.authorName = comment.author?.name
    self.avatar = comment.author?.avatar
    self.rating = comment.rating
    self.title = nil
    self.body = comment.comment ?? ""
    self.createTime = comment.createTime
    self.usefulCount = comment.voteCount
  }

  init(review: DoubanReview) {
    self.kind = .review
    self.itemID = review.id
    self.authorName = review.author?.name
    self.avatar = review.author?.avatar
    self.rating = review.rating
    self.title = DoubanDiscussionIdentity.normalized(review.title)
    self.body = review.abstract ?? ""
    self.createTime = review.createTime
    self.usefulCount = review.usefulCount
  }

  var displayAuthorName: String {
    DoubanDiscussionIdentity.normalized(authorName) ?? "豆瓣用户"
  }

  /// 头像加载失败时的回退字符。
  var authorInitial: String {
    String(displayAuthorName.prefix(1))
  }

  /// 数字评分，只用于无障碍朗读；画面上用 `starFills` 画五颗星。
  var ratingText: String? {
    guard let rating, rating > 0 else { return nil }
    return String(format: "%.1f", rating)
  }

  /// 五颗星的填充状态，按 0.5 星取整；没有评分时返回 nil（不画空星，避免误读成 0 分）。
  var starFills: [StarFill]? {
    guard let rating, rating > 0 else { return nil }
    let halves = Int((min(rating, 5) * 2).rounded())
    return (0..<5).map { index in
      let remaining = halves - index * 2
      if remaining >= 2 { return .full }
      if remaining == 1 { return .half }
      return .empty
    }
  }

  /// 元信息里的日期只到「天」：豆瓣原始 `create_time` 可能带时分秒
  /// （如 `2021-10-29 12:00:00`），方案里的展示示例是 `2024-01-01`。
  var timeText: String? {
    guard let raw = DoubanDiscussionIdentity.normalized(createTime) else { return nil }
    guard let dateRange = raw.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression)
    else { return raw }
    return String(raw[dateRange])
  }

  /// 详情 Sheet 里的发帖日期与时刻，分两行显示：`("2021-10-29", "12:00")`。
  /// 没有时分时只有日期；格式意外时原值整体放在日期一栏。
  var postedDateAndTime: (date: String, time: String?)? {
    guard let raw = DoubanDiscussionIdentity.normalized(createTime) else { return nil }
    guard
      let match = raw.firstMatch(of: #/^(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}))?/#)
    else { return (raw, nil) }
    return (String(match.output.1), match.output.2.map(String.init))
  }

  /// 「N 有用」，与 Web 文案一致。
  var usefulText: String? {
    guard let usefulCount, usefulCount > 0 else { return nil }
    return "\(usefulCount) 有用"
  }

  /// 保留豆瓣正文里的换行（Web 用 `white-space: pre-line`）。
  var paragraphs: [String] {
    ReadingSheetLayout.paragraphs(body)
  }

  var accessibilityLabel: String {
    var parts: [String] = [kind.title, displayAuthorName]
    if let ratingText { parts.append("评分 \(ratingText)") }
    if let title { parts.append(title) }
    if let body = DoubanDiscussionIdentity.normalized(body) { parts.append(body) }
    if let usefulText { parts.append(usefulText) }
    return parts.joined(separator: "，")
  }
}

/// 媒体详情页「短评 / 影评」的入口条件、分页参数与区块状态。
///
/// 极性属于「新行为版本限制」：这两个接口与返回结构自后端 v3.1.7 起没有变化，但 TV 目前
/// 只在 v3.2.1 后端上完成过验收，所以从 v3.2.1 起开放入口。更低或读不出的版本一律隐藏并
/// **不发请求**；以后在更低版本上验收通过后，只需下调 `minimumBackendVersion`。
nonisolated enum DoubanDiscussionAvailability {
  static let minimumBackendVersion = "v3.2.1"
  /// 后端 `_resolve_media_type` 只认电影/电视剧；音乐、合集等类型不该出现这个区块。
  static let supportedMediaTypes: Set<String> = ["电影", "电视剧"]
  /// 与 Web `MediaCommentView` 的 `PAGE_SIZE` 一致。
  static let pageSize = 10
  /// 焦点落到已加载列表的最后几张卡之内时加载下一页；一屏约显示 3 张卡。
  static let loadMoreThreshold = 4

  static func supports(backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion),
      let minimum = MoviePilotVersion(minimumBackendVersion)
    else { return false }
    return version >= minimum
  }

  static func normalizedDoubanID(_ raw: String?) -> String? {
    DoubanDiscussionIdentity.normalized(raw)
  }

  static func normalizedMediaType(_ raw: String?) -> String? {
    guard let type = DoubanDiscussionIdentity.normalized(raw),
      supportedMediaTypes.contains(type)
    else { return nil }
    return type
  }

  /// 三个入口条件缺一不可：后端版本、豆瓣 ID、可解析的媒体类型。
  static func isEligible(detail: MediaInfo, backendVersion: String?) -> Bool {
    supports(backendVersion: backendVersion)
      && normalizedDoubanID(detail.douban_id) != nil
      && normalizedMediaType(detail.type) != nil
  }

  /// 单个分类（短评或影评）的状态。
  ///
  /// - 首屏请求还在进行（含 `refresh()` 刚重置、分页任务尚未运行的间隙）算 `.loading`，
  ///   重试时状态卡不会闪成「未请求」而被移出视图树、带走焦点。
  /// - 首屏请求已结束，却既没有内容、没有报错、也没确认为空：请求被中途取消
  ///   （会话切换、入口条件失效等），按 `.failed` 处理，用户可以重试，不会一直转圈。
  static func rowState(
    hasRequested: Bool,
    isFirstPageInFlight: Bool,
    itemCount: Int,
    isLoadingFirstPage: Bool,
    hasError: Bool,
    hasMore: Bool
  ) -> DoubanDiscussionRowState {
    guard hasRequested else { return .idle }
    if itemCount > 0 { return .ready }
    if hasError { return .failed }
    if isLoadingFirstPage || isFirstPageInFlight { return .loading }
    if !hasMore { return .empty }
    return .failed
  }

  /// 胶囊文字：与 Web 页签一致，分类名后面跟总条数。总数取豆瓣返回的 `total`，
  /// 没有时用已加载条数；为 0 或还没加载时只显示分类名。
  static func chipTitle(
    for kind: DoubanDiscussionEntry.Kind,
    total: Int?,
    loadedCount: Int
  ) -> String {
    let count = total ?? loadedCount
    guard count > 0 else { return kind.title }
    return "\(kind.title) \(count)"
  }

  /// 区块可见性：两类都还没请求或都确认为空时整块隐藏；其余情况（加载中、失败可重试、有内容）展示。
  static func isSectionVisible(
    comments: DoubanDiscussionRowState,
    reviews: DoubanDiscussionRowState
  ) -> Bool {
    let quiet: Set<DoubanDiscussionRowState> = [.idle, .empty]
    return !(quiet.contains(comments) && quiet.contains(reviews))
  }
}

nonisolated enum DoubanDiscussionRowState: Hashable, Sendable {
  /// 还没请求（影评在用户切过去之前保持此状态）。
  case idle
  case loading
  case ready
  /// 首屏成功但为空。
  case empty
  /// 首屏失败或被中途取消，状态卡后面显示「重试」按钮。
  case failed
}
