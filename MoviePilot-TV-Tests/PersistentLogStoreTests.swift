import XCTest

@testable import MoviePilot_TV

final class PersistentLogStoreTests: XCTestCase {
  func testAppendReturnsNewestFirstAndKeepsSourceLocation() async throws {
    let (store, directory) = try makeStore()
    defer { removeDirectory(directory) }

    let older = Date(timeIntervalSince1970: 2_000_000_000)
    store.append(makeLogRecord(timestamp: older, message: "older"))
    store.append(
      makeLogRecord(
        timestamp: older.addingTimeInterval(5),
        level: .error,
        message: "newer",
        fileName: "/tmp/Paginator.swift",
        function: "loadPage()",
        line: 288,
        metadata: ["code": "500"]
      )
    )

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["newer", "older"])
    XCTAssertFalse(result.isTruncated)
    XCTAssertEqual(result.records[0].level, .error)
    XCTAssertEqual(result.records[0].fileName, "Paginator.swift")
    XCTAssertEqual(result.records[0].function, "loadPage()")
    XCTAssertEqual(result.records[0].line, 288)
    XCTAssertEqual(result.records[0].metadata?["code"], "500")
  }

  func testLevelAndTimeFiltersExcludeNonMatchingRecords() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let (store, directory) = try makeStore(now: { now })
    defer { removeDirectory(directory) }

    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-30), level: .debug, message: "debug"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-10), level: .error, message: "error"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-90), level: .error, message: "too-old"))

    let result = await store.records(
      matching: LogQuery(
        levels: [.error],
        startDate: now.addingTimeInterval(-60),
        endDate: now
      )
    )

    XCTAssertEqual(result.records.map(\.message), ["error"])
  }

  func testSkipsMalformedLinesAndStillReadsValidRecords() async throws {
    let (store, directory) = try makeStore()
    defer { removeDirectory(directory) }

    let now = Date(timeIntervalSince1970: 2_000_000_100)
    store.append(makeLogRecord(timestamp: now, message: "before"))
    store.synchronize()

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let file = try XCTUnwrap(files.first { $0.pathExtension == "jsonl" })
    let original = try String(contentsOf: file, encoding: .utf8)
    try (original + "{not json}\n").write(to: file, atomically: true, encoding: .utf8)

    store.append(makeLogRecord(timestamp: now.addingTimeInterval(1), message: "after"))

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["after", "before"])
  }

  func testLegacyVerboseLevelLinesAreSkipped() async throws {
    let (store, directory) = try makeStore()
    defer { removeDirectory(directory) }

    let now = Date(timeIntervalSince1970: 2_000_000_150)
    store.append(makeLogRecord(timestamp: now, message: "kept"))
    store.synchronize()

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let file = try XCTUnwrap(files.first { $0.pathExtension == "jsonl" })
    let original = try String(contentsOf: file, encoding: .utf8)
    let legacyVerbose =
      "{\"fileName\":\"A.swift\",\"function\":\"f()\",\"id\":\"00000000-0000-0000-0000-000000000001\",\"level\":\"verbose\",\"line\":1,\"message\":\"old-verbose\",\"timestamp\":2000000150000}\n"
    try (original + legacyVerbose).write(to: file, atomically: true, encoding: .utf8)

    store.append(makeLogRecord(timestamp: now.addingTimeInterval(1), message: "after"))

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["after", "kept"])
  }

  func testQueryLimitReturnsNewestAndMarksTruncation() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000_200)
    let (store, directory) = try makeStore(now: { now })
    defer { removeDirectory(directory) }

    for offset in 0..<5 {
      store.append(
        makeLogRecord(timestamp: now.addingTimeInterval(TimeInterval(offset)), message: "m\(offset)"))
    }

    let result = await store.records(matching: LogQuery(limit: 2))
    XCTAssertEqual(result.records.map(\.message), ["m4", "m3"])
    XCTAssertTrue(result.isTruncated)
  }

  func testRecordsOlderThanSevenDaysAreDropped() async throws {
    let now = Date(timeIntervalSince1970: 2_000_100_000)
    let box = DateBox(now)
    let (store, directory) = try makeStore(now: { box.value })
    defer { removeDirectory(directory) }

    store.append(
      makeLogRecord(
        timestamp: now.addingTimeInterval(-PersistentLogStore.retention + 1),
        message: "keep"
      ))
    store.append(
      makeLogRecord(
        timestamp: now.addingTimeInterval(-PersistentLogStore.retention - 1),
        message: "drop"
      ))

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["keep"])
  }

  func testAdvancingPastRetentionDeletesPersistedFiles() async throws {
    let now = Date(timeIntervalSince1970: 2_000_200_000)
    let box = DateBox(now)
    let (store, directory) = try makeStore(now: { box.value })
    defer { removeDirectory(directory) }

    store.append(makeLogRecord(timestamp: now, message: "old"))
    store.synchronize()
    XCTAssertFalse(try jsonlFiles(in: directory).isEmpty)

    box.value = now.addingTimeInterval(PersistentLogStore.retention + 24 * 60 * 60)
    store.pruneExpired()
    store.synchronize()

    XCTAssertTrue(try jsonlFiles(in: directory).isEmpty)
    let expired = await store.records(matching: LogQuery())
    XCTAssertTrue(expired.records.isEmpty)
  }

  func testSizeCapKeepsNewestRecords() async throws {
    let now = Date(timeIntervalSince1970: 2_000_300_000)
    let (store, directory) = try makeStore(
      now: { now },
      maxTotalBytes: 900,
      maxMessageLength: 120
    )
    defer { removeDirectory(directory) }

    for index in 0..<20 {
      store.append(
        makeLogRecord(
          timestamp: now.addingTimeInterval(TimeInterval(index)),
          message: String(repeating: "x", count: 40) + "-\(index)"
        ))
    }

    let result = await store.records(matching: LogQuery())
    XCTAssertFalse(result.records.isEmpty)
    XCTAssertLessThan(result.records.count, 20)
    XCTAssertTrue(result.records.first?.message.hasSuffix("-19") == true)
    XCTAssertEqual(
      result.records.map(\.message),
      result.records.map(\.message).sorted { lhs, rhs in
        let left = Int(lhs.split(separator: "-").last ?? "") ?? 0
        let right = Int(rhs.split(separator: "-").last ?? "") ?? 0
        return left > right
      }
    )
  }

  func testMessageLongerThanCapIsTruncatedOnWrite() async throws {
    let (store, directory) = try makeStore(maxMessageLength: 8)
    defer { removeDirectory(directory) }

    store.append(
      LogRecord(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 2_000_400_000),
        level: .info,
        message: "abcdefghijk",
        fileName: "A.swift",
        function: "f()",
        line: 1,
        metadata: nil
      )
    )

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["abcdefgh"])
  }

  func testPersistentLogHandlerWritesThroughLoggerFacade() async throws {
    let (store, directory) = try makeStore()
    defer {
      Logger.bootstrap(handler: PrintLogHandler())
      removeDirectory(directory)
    }

    Logger.bootstrap(handler: PersistentLogHandler(store: store))
    Logger.error("boom", metadata: ["n": 7], file: "/src/APIService.swift", function: "fetch()", line: 12)

    let result = await store.records(matching: LogQuery())
    let record = try XCTUnwrap(result.records.first)
    XCTAssertEqual(record.level, .error)
    XCTAssertEqual(record.message, "boom")
    XCTAssertEqual(record.fileName, "APIService.swift")
    XCTAssertEqual(record.function, "fetch()")
    XCTAssertEqual(record.line, 12)
    XCTAssertEqual(record.metadata?["n"], "7")
  }

  func testDisabledRecordingDropsNewAppendsAndKeepsExisting() async throws {
    let now = Date(timeIntervalSince1970: 2_000_700_000)
    let (store, directory) = try makeStore(now: { now })
    defer { removeDirectory(directory) }

    XCTAssertTrue(store.isRecordingEnabled)
    store.append(makeLogRecord(timestamp: now, message: "kept"))
    store.setRecordingEnabled(false)
    XCTAssertFalse(store.isRecordingEnabled)
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(1), message: "dropped"))
    store.synchronize()

    let result = await store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["kept"])
  }

  func testRecordingPreferencePersistsAcrossStoreInstances() throws {
    let directory = try makeDirectory()
    let suiteName = "persistent-log-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      removeDirectory(directory)
    }

    let first = PersistentLogStore(directory: directory, defaults: defaults)
    XCTAssertTrue(first.isRecordingEnabled)
    first.setRecordingEnabled(false)

    let second = PersistentLogStore(directory: directory, defaults: defaults)
    XCTAssertFalse(second.isRecordingEnabled)
  }

  func testDisabledHandlerDoesNotPersistLoggerMessages() async throws {
    let (store, directory) = try makeStore()
    defer {
      Logger.bootstrap(handler: PrintLogHandler())
      removeDirectory(directory)
    }

    store.setRecordingEnabled(false)
    Logger.bootstrap(handler: PersistentLogHandler(store: store))
    Logger.error("secret")

    let result = await store.records(matching: LogQuery())
    XCTAssertTrue(result.records.isEmpty)
  }

  func testMultiplexLogHandlerEvaluatesMessageOnce() {
    let first = RecordingLogHandler()
    let second = RecordingLogHandler()
    let handler = MultiplexLogHandler(handlers: [first, second])
    let evaluations = EvaluationCounter()

    func emit(_ message: @autoclosure () -> Any) {
      handler.log(
        level: .info,
        message: message(),
        metadata: nil,
        file: "Logger.swift",
        function: "emit()",
        line: 1
      )
    }

    emit(evaluations.nextMessage())

    XCTAssertEqual(evaluations.count, 1)
    XCTAssertEqual(first.messages, ["counted"])
    XCTAssertEqual(second.messages, ["counted"])
  }
}

@MainActor
final class LogViewerViewModelTests: XCTestCase {
  func testTodayFilterUsesStartOfDayAndCurrentTime() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 15, minute: 0))
    )
    let (store, directory) = try makeStore(now: { now }, calendar: calendar)
    defer { removeDirectory(directory) }

    store.append(
      makeLogRecord(
        timestamp: try XCTUnwrap(calendar.date(byAdding: .minute, value: -1, to: calendar.startOfDay(for: now))),
        message: "yesterday"
      ))
    store.append(makeLogRecord(timestamp: calendar.startOfDay(for: now), message: "start"))
    store.append(makeLogRecord(timestamp: now, message: "now"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(60), message: "future"))

    let viewModel = LogViewerViewModel(store: store, now: { now }, calendar: calendar)
    viewModel.levelFilter = .debug
    viewModel.timeFilter = .today
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["now", "start"])
    XCTAssertEqual(viewModel.summaryText, "共 2 条")
  }

  func testLast24HoursIncludesPreviousCalendarDayInsideWindow() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 15, minute: 0))
    )
    let (store, directory) = try makeStore(now: { now }, calendar: calendar)
    defer { removeDirectory(directory) }

    store.append(
      makeLogRecord(
        timestamp: try XCTUnwrap(calendar.date(byAdding: .hour, value: -23, to: now)),
        message: "inside"
      ))
    store.append(
      makeLogRecord(
        timestamp: try XCTUnwrap(calendar.date(byAdding: .hour, value: -25, to: now)),
        message: "outside"
      ))

    let viewModel = LogViewerViewModel(store: store, now: { now }, calendar: calendar)
    viewModel.levelFilter = .debug
    viewModel.timeFilter = .last24Hours
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["inside"])
  }

  func testDefaultLevelFilterIsWarningAndIncludesHigherLevels() async throws {
    let now = Date(timeIntervalSince1970: 2_000_500_000)
    let (store, directory) = try makeStore(now: { now })
    defer { removeDirectory(directory) }

    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-3), level: .debug, message: "debug"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-2), level: .info, message: "info"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-1), level: .error, message: "error"))
    store.append(makeLogRecord(timestamp: now, level: .warning, message: "warn"))

    let viewModel = LogViewerViewModel(store: store, now: { now })
    XCTAssertEqual(
      LogViewerViewModel.LevelFilter.allCases.map(\.rawValue),
      ["debug", "info", "warning", "error"]
    )
    XCTAssertEqual(viewModel.levelFilter, .warning)
    XCTAssertEqual(viewModel.summaryText, "共 0 条")
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["warn", "error"])
    XCTAssertEqual(viewModel.makeQuery().levels, [.warning, .error])
    XCTAssertEqual(viewModel.summaryText, "共 2 条")

    viewModel.levelFilter = LogViewerViewModel.LevelFilter.info
    XCTAssertEqual(viewModel.levelFilter, .info)
    await viewModel.reloadRecords()
    XCTAssertEqual(viewModel.records.map(\.message), ["warn", "error", "info"])
    XCTAssertEqual(viewModel.makeQuery().levels, [.info, .warning, .error])

    viewModel.levelFilter = .error
    await viewModel.reloadRecords()
    XCTAssertEqual(viewModel.records.map(\.message), ["error"])
    XCTAssertEqual(viewModel.makeQuery().levels, [.error])
  }

  func testRecordingToggleStopsNewWritesThroughViewModel() async throws {
    let now = Date(timeIntervalSince1970: 2_000_800_000)
    let (store, directory) = try makeStore(now: { now })
    defer { removeDirectory(directory) }

    store.append(makeLogRecord(timestamp: now, level: .warning, message: "before"))
    let viewModel = LogViewerViewModel(store: store, now: { now })
    viewModel.timeFilter = .last7Days
    XCTAssertTrue(viewModel.isRecordingEnabled)

    viewModel.isRecordingEnabled = false
    XCTAssertFalse(store.isRecordingEnabled)
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(1), level: .error, message: "after"))
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["before"])
  }

  func testStaleReloadDoesNotReplaceNewerFilterResults() async throws {
    let now = Date(timeIntervalSince1970: 2_000_600_000)
    let gate = ReloadGate()
    let store = GatedLogStore(
      directory: try makeDirectory(),
      now: { now },
      gate: gate
    )
    defer { removeDirectory(store.directoryURL) }

    store.append(makeLogRecord(timestamp: now, level: .error, message: "error"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-1), level: .info, message: "info"))
    store.synchronize()

    let viewModel = LogViewerViewModel(store: store, now: { now })
    viewModel.timeFilter = .last7Days
    viewModel.levelFilter = .debug
    let slow = Task { await viewModel.reloadRecords() }
    await gate.waitUntilEntered()
    viewModel.levelFilter = .error
    await viewModel.reloadRecords()
    gate.release()
    await slow.value

    XCTAssertEqual(viewModel.records.map(\.message), ["error"])
  }

  func testStaleReloadWithSameQueryDoesNotReplaceNewerResults() async throws {
    let now = Date(timeIntervalSince1970: 2_000_600_100)
    let gate = ReloadGate()
    let store = GatedLogStore(
      directory: try makeDirectory(),
      now: { now },
      gate: gate
    )
    defer { removeDirectory(store.directoryURL) }

    store.append(makeLogRecord(timestamp: now, level: .error, message: "error"))
    store.append(makeLogRecord(timestamp: now.addingTimeInterval(-1), level: .info, message: "info"))
    store.synchronize()

    let viewModel = LogViewerViewModel(store: store, now: { now })
    viewModel.timeFilter = .last7Days
    viewModel.levelFilter = .debug
    let slow = Task { await viewModel.reloadRecords() }
    await gate.waitUntilEntered()
    store.append(makeLogRecord(timestamp: now, level: .warning, message: "late"))
    await viewModel.reloadRecords()
    gate.release()
    await slow.value

    XCTAssertEqual(viewModel.records.map(\.message), ["late", "info", "error"])
  }
}

private final class DateBox: @unchecked Sendable {
  var value: Date
  init(_ value: Date) { self.value = value }
}

private final class RecordingLogHandler: LogHandler, @unchecked Sendable {
  var messages: [String] = []

  func log(
    level: Logger.Level,
    message: @autoclosure () -> Any,
    metadata: [String: Any]?,
    file: String,
    function: String,
    line: UInt
  ) {
    messages.append(String(describing: message()))
  }
}

private final class ReloadGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var entered = false
  private var released = false

  func hasEntered() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    return entered
  }

  func waitUntilEntered() async {
    while !hasEntered() {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func isReleased() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    return released
  }

  func waitUntilReleased() async {
    while !isReleased() {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func enter() {
    condition.lock()
    entered = true
    condition.broadcast()
    condition.unlock()
  }

  func release() {
    condition.lock()
    released = true
    condition.broadcast()
    condition.unlock()
  }
}

private final class GatedLogStore: PersistentLogStore {
  let directoryURL: URL
  private let gate: ReloadGate
  private var shouldGate = true

  init(directory: URL, now: @escaping @Sendable () -> Date, gate: ReloadGate) {
    self.directoryURL = directory
    self.gate = gate
    let suiteName = "gated-log-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    super.init(directory: directory, now: now, defaults: defaults)
  }

  override func records(matching query: LogQuery) async -> LogQueryResult {
    let result = await super.records(matching: query)
    if shouldGate {
      shouldGate = false
      gate.enter()
      await gate.waitUntilReleased()
    }
    return result
  }
}

private final class EvaluationCounter {
  var count = 0

  func nextMessage() -> String {
    count += 1
    return "counted"
  }
}

private func makeStore(
  now: @escaping @Sendable () -> Date = { Date() },
  calendar: Calendar = PersistentLogStore.defaultCalendar,
  retention: TimeInterval = PersistentLogStore.retention,
  maxTotalBytes: Int = PersistentLogStore.maxTotalBytes,
  maxMessageLength: Int = PersistentLogStore.maxMessageLength
) throws -> (PersistentLogStore, URL) {
  let directory = try makeDirectory()
  let suiteName = "persistent-log-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  let store = PersistentLogStore(
    directory: directory,
    now: now,
    calendar: calendar,
    retention: retention,
    maxTotalBytes: maxTotalBytes,
    maxMessageLength: maxMessageLength,
    defaults: defaults
  )
  return (store, directory)
}

private func makeDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("persistent-logs-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func removeDirectory(_ directory: URL) {
  try? FileManager.default.removeItem(at: directory)
}

private func jsonlFiles(in directory: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "jsonl" }
}

private func makeLogRecord(
  id: UUID = UUID(),
  timestamp: Date,
  level: Logger.Level = .info,
  message: String = "hello",
  fileName: String = "Test.swift",
  function: String = "test()",
  line: UInt = 1,
  metadata: [String: String]? = nil
) -> LogRecord {
  LogRecord(
    id: id,
    timestamp: timestamp,
    level: level,
    message: message,
    fileName: URL(fileURLWithPath: fileName).lastPathComponent,
    function: function,
    line: line,
    metadata: metadata
  )
}
