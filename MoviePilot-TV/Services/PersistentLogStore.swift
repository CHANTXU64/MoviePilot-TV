import Foundation

nonisolated struct LogRecord: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let timestamp: Date
  let level: Logger.Level
  let message: String
  let fileName: String
  let function: String
  let line: UInt
  let metadata: [String: String]?
}

nonisolated struct LogQuery: Equatable, Sendable {
  static let defaultLimit = 2_000

  var levels: Set<Logger.Level>?
  var startDate: Date?
  var endDate: Date?
  var limit: Int

  init(
    levels: Set<Logger.Level>? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    limit: Int = LogQuery.defaultLimit
  ) {
    self.levels = levels
    self.startDate = startDate
    self.endDate = endDate
    self.limit = limit
  }

  func matches(_ record: LogRecord, now: Date, retention: TimeInterval) -> Bool {
    guard record.timestamp >= now.addingTimeInterval(-retention) else { return false }
    if let levels, !levels.contains(record.level) { return false }
    if let startDate, record.timestamp < startDate { return false }
    if let endDate, record.timestamp > endDate { return false }
    return true
  }
}

nonisolated struct LogQueryResult: Equatable, Sendable {
  var records: [LogRecord]
  var isTruncated: Bool
}

nonisolated struct PersistentLogHandler: LogHandler {
  let store: PersistentLogStore

  func log(
    level: Logger.Level,
    message: @autoclosure () -> Any,
    metadata: [String: Any]?,
    file: String,
    function: String,
    line: UInt
  ) {
    guard store.isRecordingEnabled else { return }
    store.append(
      LogRecord(
        id: UUID(),
        timestamp: Date(),
        level: level,
        message: String(describing: message()),
        fileName: URL(fileURLWithPath: file).lastPathComponent,
        function: function,
        line: line,
        metadata: PersistentLogStore.stringify(metadata)
      )
    )
  }
}

/// 把 `Logger` 记录追加到按日切分的 JSONL 文件，并按 7 天窗口淘汰。
nonisolated class PersistentLogStore: @unchecked Sendable {
  static let retention: TimeInterval = 7 * 24 * 60 * 60
  static let maxTotalBytes = 8 * 1_024 * 1_024
  static let maxMessageLength = 8_192
  static let recordingEnabledKey = "moviepilot.persistentLog.recordingEnabled"

  static let shared = PersistentLogStore(directory: defaultDirectory())

  static var defaultCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  static func defaultDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("MoviePilot-TV", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
  }

  static func stringify(_ metadata: [String: Any]?) -> [String: String]? {
    guard let metadata, !metadata.isEmpty else { return nil }
    var result: [String: String] = [:]
    result.reserveCapacity(metadata.count)
    for (key, value) in metadata {
      result[key] = String(describing: value)
    }
    return result
  }

  private let directory: URL
  private let fileManager: FileManager
  private let defaults: UserDefaults
  private let queue = DispatchQueue(label: "moviepilot.persistent-log-store")
  private let now: @Sendable () -> Date
  private let calendar: Calendar
  private let retention: TimeInterval
  private let maxTotalBytes: Int
  private let maxMessageLength: Int
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  /// 与文件 IO 队列分离，避免读盘时卡住 Logger 热路径。
  private let recordingLock = NSLock()
  private var recordingEnabledValue = true

  var isRecordingEnabled: Bool {
    recordingLock.lock()
    defer { recordingLock.unlock() }
    return recordingEnabledValue
  }

  func setRecordingEnabled(_ enabled: Bool) {
    recordingLock.lock()
    recordingEnabledValue = enabled
    recordingLock.unlock()
    defaults.set(enabled, forKey: Self.recordingEnabledKey)
  }

  convenience init(
    directory: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = { Date() },
    calendar: Calendar = PersistentLogStore.defaultCalendar,
    retention: TimeInterval = PersistentLogStore.retention,
    maxTotalBytes: Int = PersistentLogStore.maxTotalBytes,
    maxMessageLength: Int = PersistentLogStore.maxMessageLength
  ) {
    self.init(
      directory: directory,
      fileManager: fileManager,
      now: now,
      calendar: calendar,
      retention: retention,
      maxTotalBytes: maxTotalBytes,
      maxMessageLength: maxMessageLength,
      defaults: .standard
    )
  }

  init(
    directory: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = { Date() },
    calendar: Calendar = PersistentLogStore.defaultCalendar,
    retention: TimeInterval = PersistentLogStore.retention,
    maxTotalBytes: Int = PersistentLogStore.maxTotalBytes,
    maxMessageLength: Int = PersistentLogStore.maxMessageLength,
    defaults: UserDefaults
  ) {
    self.directory = directory
    self.fileManager = fileManager
    self.defaults = defaults
    self.now = now
    self.calendar = calendar
    self.retention = retention
    self.maxTotalBytes = maxTotalBytes
    self.maxMessageLength = maxMessageLength
    if defaults.object(forKey: Self.recordingEnabledKey) != nil {
      recordingEnabledValue = defaults.bool(forKey: Self.recordingEnabledKey)
    } else {
      recordingEnabledValue = true
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    self.decoder = decoder
  }

  func truncatedMessage(from message: Any) -> String {
    let rendered = String(describing: message)
    guard rendered.count > maxMessageLength else { return rendered }
    let end = rendered.index(rendered.startIndex, offsetBy: maxMessageLength)
    return String(rendered[..<end])
  }

  func append(_ record: LogRecord) {
    guard isRecordingEnabled else { return }
    queue.async {
      let capped = LogRecord(
        id: record.id,
        timestamp: record.timestamp,
        level: record.level,
        message: self.truncatedMessage(from: record.message),
        fileName: record.fileName,
        function: record.function,
        line: record.line,
        metadata: record.metadata
      )
      self.write(capped)
    }
  }

  func records(matching query: LogQuery) async -> LogQueryResult {
    await withCheckedContinuation { continuation in
      queue.async {
        self.pruneExpiredLocked(now: self.now())
        continuation.resume(returning: self.loadLocked(query: query))
      }
    }
  }

  func pruneExpired() {
    queue.async { self.pruneExpiredLocked(now: self.now()) }
  }

  func synchronize() {
    queue.sync {}
  }

  private func write(_ record: LogRecord) {
    let current = now()
    pruneExpiredLocked(now: current)
    guard record.timestamp >= current.addingTimeInterval(-retention) else { return }
    prepareDirectory()
    let url = fileURL(for: record.timestamp)
    guard let data = encodeLine(record) else { return }
    if fileManager.fileExists(atPath: url.path) {
      do {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        return
      }
    } else {
      do {
        try data.write(to: url, options: .atomic)
      } catch {
        return
      }
    }
    enforceSizeCapLocked()
  }

  private func encodeLine(_ record: LogRecord) -> Data? {
    guard var data = try? encoder.encode(record) else { return nil }
    data.append(0x0A)
    return data
  }

  private func prepareDirectory() {
    guard !fileManager.fileExists(atPath: directory.path) else { return }
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func fileURL(for date: Date) -> URL {
    directory.appendingPathComponent("\(dayString(for: date)).jsonl")
  }

  private func dayString(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  private func pruneExpiredLocked(now: Date) {
    let cutoff = now.addingTimeInterval(-retention)
    for url in dayFiles() {
      guard let fileDay = day(from: url) else {
        try? fileManager.removeItem(at: url)
        continue
      }
      let nextDay = calendar.date(byAdding: .day, value: 1, to: fileDay) ?? fileDay
      if nextDay <= cutoff {
        try? fileManager.removeItem(at: url)
      }
    }
  }

  private func loadLocked(query: LogQuery) -> LogQueryResult {
    let current = now()
    let fetchLimit = max(query.limit, 0)
    guard fetchLimit > 0 else {
      return LogQueryResult(records: [], isTruncated: false)
    }

    var collected: [LogRecord] = []
    fileLoop: for url in dayFiles().reversed() {
      for record in decodeFile(url).reversed() {
        guard query.matches(record, now: current, retention: retention) else { continue }
        collected.append(record)
        if collected.count > fetchLimit {
          break fileLoop
        }
      }
    }

    let truncated = collected.count > fetchLimit
    if truncated {
      collected.removeLast()
    }
    return LogQueryResult(records: collected, isTruncated: truncated)
  }

  private func dayFiles() -> [URL] {
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    return contents
      .filter { isDayFile($0) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func isDayFile(_ url: URL) -> Bool {
    url.pathExtension == "jsonl" && day(from: url) != nil
  }

  private func day(from url: URL) -> Date? {
    let name = url.deletingPathExtension().lastPathComponent
    let parts = name.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  private func decodeFile(_ url: URL) -> [LogRecord] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    var records: [LogRecord] = []
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
      if let record = try? decoder.decode(LogRecord.self, from: lineData) {
        records.append(record)
      }
    }
    return records
  }

  private func enforceSizeCapLocked() {
    var files = dayFiles()
    var total = files.reduce(0) { $0 + fileSize($1) }
    while total > maxTotalBytes, files.count > 1, let oldest = files.first {
      let size = fileSize(oldest)
      try? fileManager.removeItem(at: oldest)
      files.removeFirst()
      total -= max(size, 0)
    }
    guard let newest = files.last, total > maxTotalBytes else { return }
    trimFileLocked(newest, keepingBytes: maxTotalBytes)
  }

  private func trimFileLocked(_ url: URL, keepingBytes maxBytes: Int) {
    let records = decodeFile(url)
    guard !records.isEmpty else {
      try? fileManager.removeItem(at: url)
      return
    }

    var kept: [LogRecord] = []
    var bytes = 0
    for record in records.reversed() {
      guard let data = encodeLine(record) else { continue }
      if bytes + data.count > maxBytes && !kept.isEmpty { break }
      kept.append(record)
      bytes += data.count
    }
    kept.reverse()
    let payload = kept.compactMap { encodeLine($0) }.reduce(Data(), +)
    try? payload.write(to: url, options: .atomic)
  }

  private func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }
}
