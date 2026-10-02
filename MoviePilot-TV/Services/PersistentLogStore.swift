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
  var storageIssues: Set<LogStorageIssue> = []
}

nonisolated enum LogStorageIssue: CaseIterable, Hashable, Sendable {
  case readFailed
  case writeFailed
  case maintenanceFailed
  case recordTooLarge

  var message: String {
    switch self {
    case .readFailed: return "部分日志读取失败，请重试。"
    case .writeFailed: return "日志保存失败，部分新日志可能未记录。"
    case .maintenanceFailed: return "日志清理失败，请重试。"
    case .recordTooLarge: return "有日志超过单条大小限制，未保存。"
    }
  }
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
  /// 包含来源、metadata、JSON 转义和行尾，避免单条记录撑破总容量。
  static let maxRecordBytes = 64 * 1_024
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
  /// 仅在 IO 队列访问；读成功不能掩盖之前的写失败。
  private var writeIssue: LogStorageIssue?
  private var maintenanceFailed = false

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
    self.maxTotalBytes = max(0, maxTotalBytes)
    self.maxMessageLength = max(0, maxMessageLength)
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
        self.maintainLocked()
        continuation.resume(returning: self.loadLocked(query: query))
      }
    }
  }

  func pruneExpired() {
    // 启动时即使关闭了记录，也执行年龄和容量清理。
    queue.async { self.maintainLocked() }
  }

  func synchronize() {
    queue.sync {}
  }

  private func write(_ record: LogRecord) {
    let current = now()
    guard record.timestamp >= current.addingTimeInterval(-retention) else { return }
    do {
      let data = try encodeLine(record)
      try prepareDirectory()
      try pruneExpiredLocked(now: current)
      // 断尾可能需要一个分隔符；整条等于上限时会先清空所有旧内容。
      try enforceSizeCapLocked(reservingBytes: min(maxTotalBytes, data.count + 1))
      let url = fileURL(for: record.timestamp)
      if fileManager.fileExists(atPath: url.path) {
        // 容量清理可能替换 inode，必须在清理之后才打开句柄。
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var payload = Data()
        if end > 0 {
          try handle.seek(toOffset: end - 1)
          guard let lastByte = try handle.read(upToCount: 1), lastByte.count == 1 else {
            throw CocoaError(.fileReadUnknown)
          }
          if lastByte.first != 0x0A { payload.append(0x0A) }
        }
        payload.append(data)
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
        try handle.close()
      } else {
        try data.write(to: url, options: .atomic)
      }
      writeIssue = nil
      maintenanceFailed = false
    } catch RecordError.tooLarge {
      writeIssue = .recordTooLarge
    } catch {
      writeIssue = .writeFailed
    }
  }

  nonisolated private enum RecordError: Error { case tooLarge }

  private func encodeLine(_ record: LogRecord) throws -> Data {
    let budget = min(Self.maxRecordBytes, maxTotalBytes)
    // 先限制原始字段，避免为明显超限的 metadata 分配巨大的编码缓冲。
    var remaining = budget
    func consume(_ text: String) throws {
      let count = text.utf8.prefix(remaining + 1).count
      guard count <= remaining else { throw RecordError.tooLarge }
      remaining -= count
    }
    try consume(record.message)
    try consume(record.fileName)
    try consume(record.function)
    for (key, value) in record.metadata ?? [:] {
      try consume(key)
      try consume(value)
      guard remaining >= 6 else { throw RecordError.tooLarge }
      remaining -= 6
    }
    var data = try encoder.encode(record)
    data.append(0x0A)
    guard data.count <= budget else { throw RecordError.tooLarge }
    return data
  }

  private func prepareDirectory() throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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

  private func maintainLocked() {
    do {
      try pruneExpiredLocked(now: now())
      try enforceSizeCapLocked()
      maintenanceFailed = false
    } catch {
      maintenanceFailed = true
    }
  }

  private func pruneExpiredLocked(now: Date) throws {
    let cutoff = now.addingTimeInterval(-retention)
    for url in try dayFiles() {
      guard let fileDay = day(from: url) else { continue }
      let nextDay = calendar.date(byAdding: .day, value: 1, to: fileDay) ?? fileDay
      if nextDay <= cutoff {
        try fileManager.removeItem(at: url)
      }
    }
  }

  private func loadLocked(query: LogQuery) -> LogQueryResult {
    let current = now()
    let fetchLimit = max(query.limit, 0)
    var issues: Set<LogStorageIssue> = []
    if let writeIssue { issues.insert(writeIssue) }
    if maintenanceFailed { issues.insert(.maintenanceFailed) }
    guard fetchLimit > 0 else {
      return LogQueryResult(records: [], isTruncated: false, storageIssues: issues)
    }

    var collected: [LogRecord] = []
    do {
      fileLoop: for url in try dayFiles().reversed() {
        do {
          for record in try decodeFile(url).reversed() {
            guard query.matches(record, now: current, retention: retention) else { continue }
            collected.append(record)
            if collected.count > fetchLimit { break fileLoop }
          }
        } catch {
          issues.insert(.readFailed)
        }
      }
    } catch {
      issues.insert(.readFailed)
    }

    let truncated = collected.count > fetchLimit
    if truncated {
      collected.removeLast()
    }
    return LogQueryResult(records: collected, isTruncated: truncated, storageIssues: issues)
  }

  private func dayFiles() throws -> [URL] {
    let contents: [URL]
    do {
      contents = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    } catch let error as NSError where error.domain == NSCocoaErrorDomain
      && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    {
      return []
    }

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

  private func decodeFile(_ url: URL) throws -> [LogRecord] {
    let data = try Data(contentsOf: url)
    // JSONL 只使用 LF 分行；Unicode 换行字符属于 JSON 字符串内容。
    // 单行损坏（包括断裂的 UTF-8 尾部）不能拖垮其他已完成记录。
    return data.split(separator: 0x0A).compactMap { line in
      try? decoder.decode(LogRecord.self, from: Data(line))
    }
  }

  private func enforceSizeCapLocked(reservingBytes: Int = 0) throws {
    var files = try dayFiles()
    var total = try files.reduce(0) { try $0 + fileSize($1) }
    guard total > maxTotalBytes - reservingBytes else { return }
    // 一次回收至少 25%，避免单日满额后每追加一条就重写整个文件。
    let target = maxTotalBytes - max(maxTotalBytes / 4, reservingBytes)
    while total > target, files.count > 1, let oldest = files.first {
      let size = try fileSize(oldest)
      try fileManager.removeItem(at: oldest)
      files.removeFirst()
      total -= size
    }
    guard let newest = files.last, total > target else { return }
    try trimFileLocked(newest, keepingBytes: target)
  }

  private func trimFileLocked(_ url: URL, keepingBytes maxBytes: Int) throws {
    // 先完整读成功再修改；按原始行裁剪，不把解码失败当成空文件删除。
    let data = try Data(contentsOf: url)
    var kept: [Data.SubSequence] = []
    var bytes = 0
    for line in data.split(separator: 0x0A).reversed() {
      let size = line.count + 1
      if size > maxBytes, kept.isEmpty { continue }
      guard size <= maxBytes - bytes else { break }
      kept.append(line)
      bytes += size
    }
    var payload = Data()
    payload.reserveCapacity(bytes)
    for line in kept.reversed() {
      payload.append(line)
      payload.append(0x0A)
    }
    try payload.write(to: url, options: .atomic)
  }

  private func fileSize(_ url: URL) throws -> Int {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber else {
      throw CocoaError(.fileReadUnknown)
    }
    return size.intValue
  }
}
