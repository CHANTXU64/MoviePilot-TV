import Foundation

/// 字幕搜索请求只携带参数和展示用媒体，不进入导航栈的结果、签名链接或站点凭据。
struct SubtitleSearchRequest: Hashable {
  enum Kind: Hashable {
    case title(keyword: String)
    case media(source: String, mediaId: String, type: String?, season: Int?, episode: Int?)
  }

  let kind: Kind
  let sites: String?
  let displayTitle: String?
  let mediaInfo: MediaInfo?

  var titleKeyword: String? {
    if case .title(let keyword) = kind { return keyword }
    return nil
  }

  /// 详情、已识别首页和长按菜单携带的媒体身份，用于预填下载表单。标题搜索为 nil。
  var initialMediaIdentity: MediaIdentity? {
    guard case .media(let source, let mediaId, _, _, _) = kind else { return nil }
    let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedID = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSource.isEmpty, !normalizedID.isEmpty else { return nil }
    return MediaIdentity(source: normalizedSource, mediaId: normalizedID)
  }

  var navigationTitle: String {
    MediaIdentifier.normalizedString(displayTitle) ?? "字幕搜索"
  }

  /// 字幕下载只接受电影和电视剧。合集、系列和音乐不提供入口。
  static func supportsSubtitleSearch(type: String?, isCollection: Bool = false) -> Bool {
    guard !isCollection else { return false }
    switch type {
    case "音乐", "合集", "collection", "系列":
      return false
    default:
      return true
    }
  }

  static func supportsSubtitleSearch(_ item: MediaInfo) -> Bool {
    supportsSubtitleSearch(type: item.type, isCollection: item.isCollection)
  }
}

/// 站点字幕结果，按后端字段类型解码；可选字段允许缺失或 null。
/// enclosure 按原始字符串往返，保留签名片段；不要改写成 URL。
nonisolated struct SubtitleInfo: Codable, Hashable, Sendable {
  var site: Int?
  var site_name: String?
  var site_cookie: String?
  var site_ua: String?
  // SSE 直接输出站点的 0/1；与资源结果共用布尔编码，下载时仍传 Bool。
  var site_proxy: FlexibleBool?
  var site_order: Int?
  var title: String?
  var description: String?
  var enclosure: String?
  var page_url: String?
  var language: String?
  var language_icon: String?
  var size: Double?
  var pubdate: String?
  var date_elapsed: String?
  var grabs: Int?
  var uploader: String?
  var report_url: String?
  var torrent_id: String?
  var subtitle_id: String?
  var file_name: String?
  var meta_info: JSONValue?
  var season_episode: String?
  var episode_list: [Int]?

  // 有业务链接时按链接辨认；无链接的稀疏记录只用字段值维持展示身份。
  enum ListIdentity: Hashable, Sendable {
    case enclosure(String)
    case subtitle(site: Int?, id: String)
    case page(site: Int?, url: String)
    case metadata(site: Int?, siteName: String?, title: String?, fileName: String?)
  }

  var listIdentity: ListIdentity {
    if let enclosure, !enclosure.isEmpty { return .enclosure(enclosure) }
    if let subtitle_id, !subtitle_id.isEmpty { return .subtitle(site: site, id: subtitle_id) }
    if let page_url, !page_url.isEmpty { return .page(site: site, url: page_url) }
    return .metadata(site: site, siteName: site_name, title: title, fileName: file_name)
  }

  /// 与资源搜索一样，展示字节数只采用可精确表示的整数；下载仍传回原始 size。
  var sizeInBytes: Int64? { size.flatMap { Int64(exactly: $0) } }

  var displayTitle: String {
    MediaIdentifier.normalizedString(title) ?? "未命名字幕"
  }

}

nonisolated struct SubtitleSearchEvent: Decodable, Sendable {
  let type: String?
  let text: String?
  let text_i18n: String?
  let value: Double?
  let items: [SubtitleInfo]?
  let message: String?
  let message_i18n: String?
  let stage: String?
  let replace_batch: Bool?
  let batch_index: Int?
  let batch_count: Int?
  let total_items: Int?

  var localizedMessage: String? {
    trimmedNonEmpty([message_i18n, message])
  }

  var localizedProgress: String? {
    trimmedNonEmpty([text_i18n, text])
  }
}

nonisolated enum SubtitleSearchFailure: Error, LocalizedError {
  case business(String)

  var errorDescription: String? {
    switch self {
    case .business(let message): message
    }
  }
}

/// 字幕流收集器。预览最多展示 24 条、缓冲 96 条；最终 replace 或收齐的分块替换预览。
/// 有条目的 done 才换成最终列表。空的 done 留下已经展示的预览，和资源搜索一样。心跳不改变列表。
nonisolated struct SubtitleSearchCollector {
  static let previewDisplayLimit = 24
  static let previewBufferLimit = 96

  private(set) var finalApplied = false
  private var preview: [SubtitleInfo] = []
  private var finalItems: [SubtitleInfo] = []
  private var pendingFinalItems: [SubtitleInfo] = []
  private var finalBatch = SearchReplaceBatchState<SubtitleInfo>()

  var publishedItems: [SubtitleInfo] {
    if finalApplied { return finalItems }
    return Array(preview.prefix(Self.previewDisplayLimit))
  }

  var bufferedPreviewCount: Int {
    finalApplied ? 0 : preview.count
  }

  mutating func receive(_ event: SubtitleSearchEvent) throws -> Bool {
    if event.type == "heartbeat" { return false }
    if event.type == "error" {
      throw SubtitleSearchFailure.business(event.localizedMessage ?? "搜索失败，请稍后重试")
    }
    if event.replace_batch == true {
      guard !finalApplied else { return false }
      if try finalBatch.receive(
        type: event.type,
        isReplaceBatch: true,
        batchIndex: event.batch_index,
        batchCount: event.batch_count,
        totalItems: event.total_items,
        items: event.items,
        into: &pendingFinalItems
      ) {
        finalItems = pendingFinalItems
        pendingFinalItems = []
        preview = []
        finalApplied = true
        return true
      }
      return false
    }
    if finalBatch.isPending,
      event.type == "append" || event.type == "replace" || event.type == "done"
    {
      throw ResourceSearchFailure.incompletePage
    }
    let items = event.items ?? []
    switch event.type {
    case "append" where !finalApplied:
      guard !items.isEmpty else { return false }
      preview.insert(contentsOf: items, at: 0)
      if preview.count > Self.previewBufferLimit {
        preview.removeLast(preview.count - Self.previewBufferLimit)
      }
      return true
    case "replace":
      finalItems = items
      preview = []
      finalApplied = true
      return true
    case "done" where !items.isEmpty && !finalApplied:
      finalItems = items
      preview = []
      finalApplied = true
      return true
    default:
      return false
    }
  }
}

/// 自动目录必须写出 JSON null，不能省略 save_path。
nonisolated struct SubtitleDownloadRequest: Encodable {
  let subtitle: SubtitleInfo
  let mediaSource: String
  let mediaId: String
  let savePath: String?

  enum CodingKeys: String, CodingKey {
    case subtitle_in
    case media_source
    case media_id
    case save_path
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(subtitle, forKey: .subtitle_in)
    try container.encode(mediaSource, forKey: .media_source)
    try container.encode(mediaId, forKey: .media_id)
    try container.encode(savePath, forKey: .save_path)
  }
}

/// `/download/paths` 的目录。提交给下载接口的是 save_path，不是 name。
nonisolated struct DownloadDirectory: Decodable, Hashable, Sendable {
  let name: String?
  let storage: String?
  let download_path: String?
  let save_path: String?
  let priority: Int?
  let media_type: String?
  let media_category: String?
}

struct SubtitleSearchRow: Identifiable {
  struct ID: Hashable {
    let identity: SubtitleInfo.ListIdentity
    let occurrence: Int
  }
  let id: ID
  let subtitle: SubtitleInfo

  static func makeRows(from items: [SubtitleInfo]) -> [Self] {
    var occurrences: [SubtitleInfo.ListIdentity: Int] = [:]
    return items.map { item in
      let identity = item.listIdentity
      let occurrence = occurrences[identity, default: 0]
      occurrences[identity] = occurrence + 1
      return Self(id: ID(identity: identity, occurrence: occurrence), subtitle: item)
    }
  }
}
