import XCTest

@testable import MoviePilot_TV

final class LogStorageBoundaryTests: XCTestCase {
  func testJSONLLFFramingPreservesUnicodeNewlinesAndCRLF() async throws {
    let fixture = try LogBoundaryFixture()
    let text = "前\u{0085}中\u{2028}后\u{2029}尾"
    let record = fixture.record(message: text, metadata: ["text": text])
    var json = try XCTUnwrap(String(data: fixture.line(record), encoding: .utf8))
    // Fixture 必须真的包含 Unicode 分隔符，不能被 encoder 的转义策略掩盖。
    for (escape, scalar) in [("\\u0085", "\u{0085}"), ("\\u2028", "\u{2028}"), ("\\u2029", "\u{2029}")] {
      json = json.replacingOccurrences(of: escape, with: scalar)
      XCTAssertTrue(json.contains(scalar))
    }
    try Data((json.dropLast() + "\r\n").utf8).write(to: fixture.file)

    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(result.records, [record])
    XCTAssertTrue(result.storageIssues.isEmpty)
  }

  func testInvalidUTF8LineAndTruncatedTailDoNotHideValidRecordsOrNextAppend() async throws {
    let fixture = try LogBoundaryFixture()
    let before = fixture.record(message: "before")
    let after = fixture.record(message: "after")
    var data = try fixture.line(before)
    data.append(contentsOf: [0xE4, 0xB8, 0x0A])
    data.append(try fixture.line(after))
    data.append(Data("{\"message\":\"断尾".utf8))
    data.append(contentsOf: [0xF0, 0x9F])
    try data.write(to: fixture.file)

    let initial = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(initial.records.map(\.message), ["after", "before"])
    fixture.store.append(fixture.record(message: "next"))
    fixture.store.append(fixture.record(message: "last"))
    let appended = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(appended.records.map(\.message), ["last", "next", "after", "before"])
  }

  func testValidFinalJSONWithoutLFRemainsSeparateFromNextAppend() async throws {
    let fixture = try LogBoundaryFixture()
    let original = fixture.record(message: "without LF")
    try Data(fixture.line(original).dropLast()).write(to: fixture.file)

    fixture.store.append(fixture.record(message: "next"))
    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["next", "without LF"])
  }

  func testTruncatedUTF8TailSurvivesCapacityMaintenanceAndAppendWithoutLosingValidPrefix() async throws {
    let fixture = try LogBoundaryFixture(cap: 1_500)
    var data = Data()
    for name in ["old", "middle", "keep"] {
      data.append(try fixture.line(fixture.record(message: name + String(repeating: "x", count: 100))))
    }
    data.append(Data("{\"message\":\"".utf8))
    data.append(contentsOf: [0xE4, 0xB8])
    try data.write(to: fixture.file)
    let appended = "new" + String(repeating: "n", count: 600)
    XCTAssertGreaterThan(data.count + (try fixture.line(fixture.record(message: appended))).count, 1_500)

    fixture.store.append(fixture.record(message: appended))
    fixture.store.pruneExpired()
    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(result.records.first?.message, appended)
    XCTAssertTrue(result.records.contains { $0.message.hasPrefix("keep") })
    XCTAssertLessThanOrEqual(try fixture.totalBytes(), 1_500)
    XCTAssertTrue(result.storageIssues.isEmpty)
  }

  func testCapacityTrimDoesNotDeleteMalformedFileAsIfItWereEmpty() async throws {
    let fixture = try LogBoundaryFixture(cap: 1_000)
    let invalidLine = Data([0xE4, 0xB8, 0x0A])
    var data = Data()
    for _ in 0..<400 { data.append(invalidLine) }
    try data.write(to: fixture.file)

    fixture.store.pruneExpired()
    fixture.store.synchronize()
    let retained = try Data(contentsOf: fixture.file)
    XCTAssertFalse(retained.isEmpty)
    XCTAssertLessThanOrEqual(retained.count, 750)
    XCTAssertEqual(retained.suffix(3), invalidLine)
  }

  func testEncodedLineExactlyAtCapFitsAndOneByteOverIsRejectedWithoutEviction() async throws {
    let cap = 512
    let fixture = try LogBoundaryFixture(cap: cap)
    let id = UUID()
    let base = fixture.record(id: id, message: "exact", metadata: ["padding": ""])
    let padding = cap - (try fixture.line(base)).count
    XCTAssertGreaterThan(padding, 0)
    let exact = fixture.record(id: id, message: "exact", metadata: ["padding": String(repeating: "x", count: padding)])
    XCTAssertEqual(try fixture.line(exact).count, cap)
    fixture.store.append(exact)
    fixture.store.synchronize()
    let original = try Data(contentsOf: fixture.file)
    XCTAssertEqual(original.count, cap)

    fixture.store.append(fixture.record(id: id, message: "exact", metadata: ["padding": String(repeating: "x", count: padding + 1)]))
    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(result.records, [exact])
    XCTAssertEqual(result.storageIssues, [.recordTooLarge])
    XCTAssertEqual(try Data(contentsOf: fixture.file), original)
  }

  func testJSONEscapingAndHugeMetadataCannotBypassByteLimits() async throws {
    let fixture = try LogBoundaryFixture(cap: 512)
    let escaping = fixture.record(message: "small", metadata: ["value": String(repeating: "\u{0000}", count: 80)])
    XCTAssertGreaterThan(try fixture.line(escaping).count, 512)
    fixture.store.append(escaping)
    let first = await fixture.store.records(matching: LogQuery())
    XCTAssertTrue(first.records.isEmpty)
    XCTAssertEqual(first.storageIssues, [.recordTooLarge])
    XCTAssertEqual(try fixture.totalBytes(), 0)

    let regular = try LogBoundaryFixture()
    regular.store.append(regular.record(message: "keep"))
    regular.store.synchronize()
    let original = try Data(contentsOf: regular.file)
    regular.store.append(regular.record(message: "oversized", metadata: ["value": String(repeating: "界", count: PersistentLogStore.maxTotalBytes / 3 + 1)]))
    let second = await regular.store.records(matching: LogQuery())
    XCTAssertEqual(second.records.map(\.message), ["keep"])
    XCTAssertEqual(second.storageIssues, [.recordTooLarge])
    XCTAssertEqual(try Data(contentsOf: regular.file), original)
  }

  func testOversizedSourceFieldsAndSingleGraphemeAreBounded() async throws {
    let fixture = try LogBoundaryFixture()
    for record in [
      fixture.record(message: "source", function: String(repeating: "f", count: 70_000)),
      fixture.record(message: "a" + String(repeating: "\u{0301}", count: 40_000)),
    ] {
      fixture.store.append(record)
      let result = await fixture.store.records(matching: LogQuery())
      XCTAssertTrue(result.records.isEmpty)
      XCTAssertEqual(result.storageIssues, [.recordTooLarge])
      XCTAssertEqual(try fixture.totalBytes(), 0)
    }
  }

  func testLegacyOversizedSingleRecordDoesNotExceedActualCapAfterMaintenance() async throws {
    let fixture = try LogBoundaryFixture(cap: 1_000)
    var data = try fixture.line(fixture.record(message: "small"))
    data.append(try fixture.line(fixture.record(message: String(repeating: "x", count: 2_000))))
    try data.write(to: fixture.file)

    fixture.store.pruneExpired()
    fixture.store.synchronize()
    XCTAssertLessThanOrEqual(try fixture.totalBytes(), 1_000)
    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertEqual(result.records.map(\.message), ["small"])
  }

  func testStartupMaintenanceEnforcesAgeAndTotalCapacityWhileRecordingDisabled() async throws {
    let fixture = try LogBoundaryFixture(cap: 2_000, enabled: false)
    let expired = fixture.file(for: LogBoundaryFixture.now.addingTimeInterval(-9 * 24 * 60 * 60))
    try fixture.line(fixture.record(message: "expired")).write(to: expired)
    for offset in [-2, -1, 0] {
      let date = LogBoundaryFixture.now.addingTimeInterval(Double(offset) * 24 * 60 * 60)
      let record = fixture.record(timestamp: date, message: "day\(offset)" + String(repeating: "x", count: 600))
      try fixture.line(record).write(to: fixture.file(for: date))
    }
    XCTAssertGreaterThan(try fixture.totalBytes(), 2_000)
    XCTAssertFalse(fixture.store.isRecordingEnabled)

    // 与 App bootstrap 相同的启动入口；不靠查询或 append 才触发清理。
    fixture.store.pruneExpired()
    fixture.store.synchronize()
    XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
    XCTAssertLessThanOrEqual(try fixture.totalBytes(), 2_000)
    let before = try Data(contentsOf: fixture.file)
    fixture.store.append(fixture.record(message: "disabled"))
    fixture.store.synchronize()
    XCTAssertEqual(try Data(contentsOf: fixture.file), before)
    let result = await fixture.store.records(matching: LogQuery())
    XCTAssertTrue(result.records.first?.message.hasPrefix("day0") == true)
  }

  @MainActor
  func testEightMiBFullDayAmortizesThreeThousandRealisticAppends() async throws {
    let cap = PersistentLogStore.maxTotalBytes
    let fixture = try LogBoundaryFixture()
    let seed = try fixture.line(fixture.record(message: String(repeating: "s", count: 768)))
    var initial = Data()
    initial.reserveCapacity(cap)
    while initial.count + seed.count <= cap { initial.append(seed) }
    if initial.count < cap {
      initial.append(Data(repeating: 0x20, count: cap - initial.count - 1))
      initial.append(0x0A)
    }
    try initial.write(to: fixture.file)
    XCTAssertEqual(try fixture.totalBytes(), cap)
    var inode = try fixture.inode()
    var compactions = 0
    var appendedBytes = 0
    let start = Date()
    for index in 0..<3_000 {
      let record = fixture.record(message: "\(index):" + String(repeating: "a", count: 768))
      appendedBytes += try fixture.line(record).count
      fixture.store.append(record)
      fixture.store.synchronize()
      XCTAssertLessThanOrEqual(try fixture.totalBytes(), cap, "append \(index)")
      let nextInode = try fixture.inode()
      if nextInode != inode { compactions += 1 }
      inode = nextInode
    }
    let duration = Date().timeIntervalSince(start)
    XCTAssertGreaterThan(compactions, 0)
    XCTAssertLessThanOrEqual(compactions, 3, "full-day atomic replacements must be amortized")
    let result = await fixture.store.records(matching: LogQuery(limit: 1))
    XCTAssertTrue(result.records.first?.message.hasPrefix("2999:") == true)
    XCTAssertTrue(result.storageIssues.isEmpty)
    XCTContext.runActivity(named: "8 MiB / 3000 appends: \(compactions) compactions, \(appendedBytes) bytes, \(duration)s") { activity in
      let attachment = XCTAttachment(string: "Initial bytes: \(cap)\nAppends: 3000\nAppended bytes: \(appendedBytes)\nAtomic compactions: \(compactions)\nElapsed seconds: \(duration)\nFinal bytes: \((try? fixture.totalBytes()) ?? -1)")
      attachment.lifetime = .keepAlways
      activity.add(attachment)
    }
  }
}

private final class LogBoundaryFixture {
  static let now = Date(timeIntervalSince1970: 2_000_000_000)
  let directory: URL
  let defaults: UserDefaults
  let suiteName: String
  let store: PersistentLogStore
  let calendar: Calendar

  init(cap: Int = PersistentLogStore.maxTotalBytes, enabled: Bool = true) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("log-boundary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    suiteName = "log-boundary-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(enabled, forKey: PersistentLogStore.recordingEnabledKey)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar = utc
    store = PersistentLogStore(directory: directory, now: { Self.now }, calendar: utc, maxTotalBytes: cap, defaults: defaults)
  }

  deinit {
    store.synchronize()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }

  var file: URL { file(for: Self.now) }

  func file(for date: Date) -> URL {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return directory.appendingPathComponent(String(format: "%04d-%02d-%02d.jsonl", parts.year!, parts.month!, parts.day!))
  }

  func record(id: UUID = UUID(), timestamp: Date = LogBoundaryFixture.now, message: String,
              function: String = "test()", metadata: [String: String]? = nil) -> LogRecord {
    LogRecord(id: id, timestamp: timestamp, level: .warning, message: message, fileName: "Test.swift", function: function, line: 1, metadata: metadata)
  }

  func line(_ record: LogRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
  }

  func totalBytes() throws -> Int {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }
      .reduce(0) { total, url in
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return total + (try XCTUnwrap(attributes[.size] as? NSNumber)).intValue
      }
  }

  func inode() throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    return try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
  }
}
