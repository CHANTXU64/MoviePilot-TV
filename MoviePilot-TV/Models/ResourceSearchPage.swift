import Foundation

nonisolated struct ResourceSearchSource: Codable, Equatable, Sendable {
  let source: String
  let site_name: String?
  let page: Int
  let can_continue: Bool
  let error: String?
}

nonisolated enum ResourceSearchFailure: Error, LocalizedError {
  case incompletePage
  case source(String)
  case capacity

  var errorDescription: String? {
    switch self {
    case .incompletePage: "本页结果未完整返回，已保留已有结果，可继续搜索重试。"
    case .source(let message): message
    case .capacity: "已达到本次搜索容量。请缩小关键词、季号或搜索站点范围后重新搜索。"
    }
  }
}

/// 新旧搜索共用最终分块的顺序和数量校验，资源数组仍由各自的收集器持有。
struct SearchReplaceBatchState {
  private var nextBatch = 0
  private var batchCount: Int?
  private var totalItems: Int?

  var hasStarted: Bool { batchCount != nil }
  var isPending: Bool { batchCount.map { nextBatch < $0 } ?? false }

  mutating func receive(_ event: SearchStreamEvent, into results: inout [Context]) throws -> Bool {
    guard event.replace_batch == true,
      let index = event.batch_index, let count = event.batch_count,
      let total = event.total_items, let items = event.items,
      count > 0, total >= 0, index == nextBatch, index < count,
      event.type == (index == 0 ? "replace" : "append"),
      batchCount == nil || batchCount == count,
      totalItems == nil || totalItems == total
    else { throw ResourceSearchFailure.incompletePage }
    batchCount = count
    totalItems = total
    results.append(contentsOf: items)
    nextBatch += 1
    guard results.count <= total else { throw ResourceSearchFailure.incompletePage }
    if nextBatch == count {
      guard results.count == total else { throw ResourceSearchFailure.incompletePage }
      return true
    }
    return false
  }
}

/// 页事务只保存待提交的最终分块；可停止查看的预览由搜索会话持有。
struct ResourceSearchPage {
  let source: String?
  let page: Int
  private(set) var finalItems: [Context] = []
  private(set) var sources: [ResourceSearchSource]?
  private(set) var isComplete = false
  private var finalBatch = SearchReplaceBatchState()

  init(source: String?, page: Int) {
    self.source = source
    self.page = page
  }

  mutating func receive(_ event: SearchStreamEvent) throws {
    if event.type == "error" {
      throw ResourceSearchFailure.source(event.localizedMessage ?? "搜索失败")
    }
    if isComplete { return }
    if event.replace_batch == true {
      guard sources == nil || sources == event.sources
      else { throw ResourceSearchFailure.incompletePage }
      sources = event.sources
      if try finalBatch.receive(event, into: &finalItems) {
        try validateSources()
        isComplete = true
      }
    } else if event.type == "replace" {
      guard !finalBatch.hasStarted, let items = event.items,
        event.total_items == items.count
      else { throw ResourceSearchFailure.incompletePage }
      finalItems = items
      sources = event.sources
      try validateSources()
      isComplete = true
    } else if event.type == "append" {
      guard !finalBatch.hasStarted else { throw ResourceSearchFailure.incompletePage }
    } else if event.type == "done" {
      // done 不携带完整资源，不能代替最终包。
      throw ResourceSearchFailure.incompletePage
    }
  }

  private func validateSources() throws {
    guard let sources, Set(sources.map(\.source)).count == sources.count,
      sources.allSatisfy({ !$0.source.isEmpty && $0.page == page })
    else { throw ResourceSearchFailure.incompletePage }
    if let source {
      guard sources.count == 1, sources[0].source == source else {
        throw ResourceSearchFailure.incompletePage
      }
      if let error = sources[0].error { throw ResourceSearchFailure.source(error) }
    }
  }
}

struct ResourceSearchQuery {
  let keyword: String
  var type: String? = nil
  var area: String? = nil
  var title: String? = nil
  var year: String? = nil
  var season: Int? = nil
  var sites: String? = nil
  var isMediaSearch = false

  static func supportsPaging(backendVersion: String?) -> Bool {
    guard let version = MoviePilotVersion(backendVersion) else { return false }
    return version >= MoviePilotVersion("v3.1.2-1")!
  }
}

/// 仅新资源协议使用：在批量构造 Context 前限制单事件记录数，包含合法的稀疏对象。
nonisolated struct BoundedResourceSearchEvent: Decodable, @unchecked Sendable {
  static let itemLimitKey = CodingUserInfoKey(rawValue: "resourceSearchItemLimit")!
  let event: SearchStreamEvent
  private enum CodingKeys: String, CodingKey { case items }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.items), try !container.decodeNil(forKey: .items),
      let limit = decoder.userInfo[Self.itemLimitKey] as? Int
    {
      let items = try container.nestedUnkeyedContainer(forKey: .items)
      guard let count = items.count, count <= limit else { throw ResourceSearchFailure.capacity }
    }
    event = try SearchStreamEvent(from: decoder)
  }
}
