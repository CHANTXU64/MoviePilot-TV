import Foundation

/// 单集对应按一种查法（剧名开头或包含剧名）读到的 MoviePilot 整理记录，下次接着增量读。
/// MoviePilot 按整理时间从新到旧分页返回，新整理的记录总在最前面。
nonisolated struct TransferRecordQuery: Equatable, Sendable {
  typealias Page = (records: [EpisodeTransferRecord], total: Int?)

  /// 这部剧的成功整理记录，按整理时间从新到旧。
  let records: [EpisodeTransferRecord]
  /// 这种查法读到过的记录编号（含别的剧的），增量读遇到读过的就停。有记录没带编号时为 nil，下次只能从头读。
  let seenIDs: Set<Int>?
  /// MoviePilot 按这种查法数的总条数，增量读完用它核对中间有没有删掉或改掉的记录。读不到时为 nil，下次只能从头读。
  let total: Int?

  init(records: [EpisodeTransferRecord], seenIDs: Set<Int>?, total: Int?) {
    self.records = records
    self.seenIDs = seenIDs
    self.total = total
  }

  /// 读到的各页：留下这部剧的记录。读页之间有新整理的记录时分页会后移，同一条可能读到两次，只留第一次的。
  private init(rows: [EpisodeTransferRecord], tmdbID: Int, total: Int?) {
    let ids = rows.compactMap(\.id)
    var kept: Set<Int> = []
    self.init(
      records: rows.filter { $0.belongs(toSeries: tmdbID) && $0.id.map { kept.insert($0).inserted } ?? true },
      seenIDs: ids.count == rows.count ? Set(ids) : nil, total: total)
  }

  /// 按一种查法读最多 `pageLimit` 页。有上次的结果时增量读：从第 1 页往后读到出现读过的记录为止，新读到的放在前面，
  /// 同编号的换成新读到的（重新整理过的记录可能排到前面）。读完核对总条数等于上次的总数加新出现的条数；
  /// 对不上（中间删过、改过或整理失败的记录不再算进来）时从头重读，不留可能已经删掉的旧记录。
  static func read(
    query: String, tmdbID: Int, previous: Self?, pageSize: Int, pageLimit: Int,
    fetch: (String, Int) async throws -> Page
  ) async throws -> Self {
    let seen = previous?.total == nil ? nil : previous?.seenIDs
    var rows: [EpisodeTransferRecord] = []
    var total: Int?
    var reachedSeen = false
    for page in 1...pageLimit {
      let batch = try await fetch(query, page)
      if page == 1 { total = batch.total }
      rows += batch.records
      if let seen, batch.records.contains(where: { $0.id.map(seen.contains) == true }) {
        reachedSeen = true
        break
      }
      // 按整页数量判断结尾：筛掉别的剧后变少不算读完。
      if batch.records.count < pageSize { break }
      if let total = batch.total, page * pageSize >= total { break }
    }
    let fresh = Self(rows: rows, tmdbID: tmdbID, total: total)
    // 没遇到读过的：已经从头读到了结尾或页数上限，和从头读一样。
    guard reachedSeen, let previous, let seen, let previousTotal = previous.total else { return fresh }
    let fetchedIDs = Set(rows.compactMap(\.id))
    guard let total, let freshSeen = fresh.seenIDs, previousTotal + fetchedIDs.subtracting(seen).count == total else {
      return try await read(query: query, tmdbID: tmdbID, previous: nil, pageSize: pageSize, pageLimit: pageLimit, fetch: fetch)
    }
    let kept = previous.records.filter { record in record.id.map { !fetchedIDs.contains($0) } ?? false }
    return Self(records: fresh.records + kept, seenIDs: seen.union(freshSeen), total: total)
  }
}
