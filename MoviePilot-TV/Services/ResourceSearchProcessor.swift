import Foundation

nonisolated struct ResourceRuleSelection: Equatable, Sendable {
  var hard: ResourceRule?
  var soft: ResourceRule?
  static let none = Self()
}

nonisolated struct ResourceProjection: Sendable {
  struct Row: Sendable { let id: String; let softRejected: Bool }
  var rows: [Row]
  var options: [String: [String]]
  var hardAllowedCount: Int
}

nonisolated struct ResourceProjectionSettings: Equatable, Sendable {
  var filters: [String: Set<String>] = [:]
  var sortField = "默认"
  var sortType = "默认排序"
}

/// 一个搜索一个串行处理器；网络交付等待处理完成，没有逐帧 Task 或无界工作队列。
actor ResourceSearchProcessor {
  private struct Record {
    let input: ResourceFilterInput
    let date: Date?
    var hardStatic: Bool?
    var softStatic: Bool?
    var failure: Error?
    var hardAllowed = false
    var softRejected = false
  }
  private struct Batch {
    var records: [Record]
    var visible: [Int] = []
    var sorted: [Int] = []
    var needsSelection = true
    var needsSort = true
  }
  private var batches: [String: Batch] = [:]
  private var batchOrder: [String] = []
  private var selection = ResourceRuleSelection.none
  private var hard: PreparedResourceRule?
  private var soft: PreparedResourceRule?
  private var settings = ResourceProjectionSettings()
  private var counts: [String: [String: Int]] = [:]
  private let formatter = ResourceResultSemantics.dateFormatter()
  private(set) var staticEvaluations = 0
  private(set) var parsedRecords = 0
  private(set) var compiledPatterns = 0

  func configure(_ next: ResourceRuleSelection) {
    let hardChanged = selection.hard != next.hard
    let softChanged = selection.soft != next.soft
    if hardChanged {
      hard = next.hard.map(PreparedResourceRule.init)
      compiledPatterns += (next.hard?.include.count ?? 0) + (next.hard?.exclude.count ?? 0)
    }
    if softChanged {
      soft = next.soft.map(PreparedResourceRule.init)
      compiledPatterns += (next.soft?.include.count ?? 0) + (next.soft?.exclude.count ?? 0)
    }
    selection = next
    for key in batchOrder {
      guard var batch = batches.removeValue(forKey: key) else { continue }
      for i in batch.records.indices {
        if hardChanged { batch.records[i].hardStatic = nil }
        if softChanged { batch.records[i].softStatic = nil }
        if hardChanged || softChanged { batch.records[i].failure = nil }
      }
      batches[key] = batch
    }
  }

  func ingest(key: String, inputs: [ResourceFilterInput], replacing: Bool, now: Date) throws {
    if replacing, let old = batches.removeValue(forKey: key) {
      for record in old.records where record.hardAllowed { count(record.input.fields, delta: -1) }
    }
    if !batchOrder.contains(key) { batchOrder.append(key) }
    var batch = batches.removeValue(forKey: key) ?? Batch(records: [])
    for input in inputs {
      var record = Record(input: input, date: input.pubdate.isEmpty ? nil : formatter.date(from: input.pubdate))
      parsedRecords += 1
      do {
        var evaluated = record
        try evaluate(&evaluated, now: now)
        record = evaluated
      } catch { record.failure = error }
      if record.hardAllowed { count(input.fields, delta: 1) }
      batch.records.append(record)
    }
    batch.needsSelection = true
    batch.needsSort = true
    batches[key] = batch
  }

  func reset() {
    batches = [:]; batchOrder = []; counts = [:]
  }

  private func evaluate(_ record: inout Record, now: Date) throws {
    if record.hardStatic == nil {
      staticEvaluations += hard == nil ? 0 : 1
      record.hardStatic = try hard?.matchesStatic(record.input) ?? true
    }
    record.hardAllowed = try record.hardStatic == true
      && (hard?.matchesTime(record.date, hasTorrent: record.input.hasTorrent, now: now) ?? true)
    guard record.hardAllowed else { return }
    if record.softStatic == nil {
      staticEvaluations += soft == nil ? 0 : 1
      record.softStatic = try soft?.matchesStatic(record.input) ?? true
    }
    record.softRejected = try !(record.softStatic == true
      && (soft?.matchesTime(record.date, hasTorrent: record.input.hasTorrent, now: now) ?? true))
  }

  private func count(_ fields: [String: String], delta: Int) {
    for (key, value) in fields {
      let updated = (counts[key]?[value] ?? 0) + delta
      counts[key, default: [:]][value] = updated > 0 ? updated : nil
    }
  }

  private func matches(_ input: ResourceFilterInput, filters: [String: Set<String>]) -> Bool {
    ResourceResultSemantics.matches(input.fields, filters: filters)
  }

  func disabledOptions(for key: String, filters: [String: Set<String>]) -> Set<String> {
    let other = filters.filter { $0.key != key }
    var available = Set<String>()
    for batch in batches.values {
      for record in batch.records where record.hardAllowed && matches(record.input, filters: other) {
        if let value = record.input.fields[key] { available.insert(value) }
      }
    }
    // 当前已选项始终可取消，即使新页替换后计数变为零。
    return Set(counts[key]?.keys.map { $0 } ?? []).subtracting(available).subtracting(filters[key] ?? [])
  }

  func project(settings next: ResourceProjectionSettings, evaluationTime: Date?) throws -> ResourceProjection {
    var succeeded = false
    defer {
      if !succeeded {
        // 规则求值失败时，尚未访问的批次也不能把旧投影当作新条件的缓存。
        for key in batchOrder {
          batches[key]?.needsSelection = true
          batches[key]?.needsSort = true
        }
      }
    }
    let filterChanged = next.filters != settings.filters
    let sortChanged = next.sortField != settings.sortField || next.sortType != settings.sortType
    settings = next
    var chunks: [[Record]] = []
    var allowedCount = 0
    for key in batchOrder {
      guard var batch = batches.removeValue(forKey: key) else { continue }
      defer { batches[key] = batch }
      if let now = evaluationTime {
        for i in batch.records.indices {
          let wasAllowed = batch.records[i].hardAllowed
          let wasSoft = batch.records[i].softRejected
          var evaluated = batch.records[i]
          try evaluate(&evaluated, now: now)
          evaluated.failure = nil
          batch.records[i] = evaluated
          if wasAllowed != batch.records[i].hardAllowed {
            count(batch.records[i].input.fields, delta: wasAllowed ? -1 : 1)
            batch.needsSelection = true
          }
          if wasSoft != batch.records[i].softRejected { batch.needsSort = true }
        }
      }
      if let failure = batch.records.compactMap(\.failure).first { throw failure }
      allowedCount += batch.records.lazy.filter(\.hardAllowed).count
      if batch.needsSelection || filterChanged {
        batch.visible = batch.records.indices.filter {
          batch.records[$0].hardAllowed && matches(batch.records[$0].input, filters: next.filters)
        }
        batch.needsSort = true
      }
      if batch.needsSort || sortChanged {
        batch.sorted = batch.visible.sorted { before(batch.records[$0], batch.records[$1]) }
      }
      batch.needsSelection = false
      batch.needsSort = false
      chunks.append(batch.sorted.map { batch.records[$0] })
      batches[key] = batch
    }
    // 两两合并已有序批次，不在采集时逐页复制累计数组。
    while chunks.count > 1 {
      var merged: [[Record]] = []
      for i in stride(from: 0, to: chunks.count, by: 2) {
        if i + 1 == chunks.count { merged.append(chunks[i]); continue }
        let a = chunks[i], b = chunks[i + 1]
        var rows: [Record] = []; rows.reserveCapacity(a.count + b.count)
        var x = 0, y = 0
        while x < a.count && y < b.count {
          if before(a[x], b[y]) { rows.append(a[x]); x += 1 }
          else { rows.append(b[y]); y += 1 }
        }
        rows.append(contentsOf: a[x...]); rows.append(contentsOf: b[y...])
        merged.append(rows)
      }
      chunks = merged
    }
    var options = counts.mapValues { $0.keys.sorted() }
    for (key, selected) in next.filters { options[key] = Array(Set(options[key] ?? []).union(selected)).sorted() }
    succeeded = true
    return ResourceProjection(
      rows: (chunks.first ?? []).map { .init(id: $0.input.id, softRejected: $0.softRejected) },
      options: options, hardAllowedCount: allowedCount)
  }

  private func before(_ lhs: Record, _ rhs: Record) -> Bool {
    ResourceResultSemantics.before(lhs.input, softRejected: lhs.softRejected,
      rhs.input, softRejected: rhs.softRejected, sortField: settings.sortField, sortType: settings.sortType)
  }
}
