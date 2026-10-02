import Foundation
import XCTest

@testable import MoviePilot_TV

final class LogStorageFailureTests: XCTestCase {
  func testDirectoryListingFailureIsReportedAndRetryRecoversPersistedRecords() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    store.append(failureRecord(at: fixture.now, message: "persisted"))
    store.synchronize()

    fixture.fileManager.failListing = true
    let failed = await store.records(matching: LogQuery())

    XCTAssertTrue(failed.records.isEmpty)
    XCTAssertFalse(failed.isTruncated)
    XCTAssertTrue(failed.storageIssues.contains(.readFailed))
    XCTAssertTrue(failed.storageIssues.contains(.maintenanceFailed))

    fixture.fileManager.failListing = false
    let retried = await store.records(matching: LogQuery())

    XCTAssertEqual(retried.records.map(\.message), ["persisted"])
    XCTAssertTrue(retried.storageIssues.isEmpty)
  }

  func testUnreadableDayFileReturnsReadableRecordsAndReadFailure() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    store.append(
      failureRecord(at: fixture.now.addingTimeInterval(-86_400), message: "readable"))
    store.synchronize()

    // 在合法日文件路径放置目录，稳定触发真实 Data 读取失败。
    let unreadable = fixture.dayURL(for: fixture.now)
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
    XCTAssertThrowsError(try Data(contentsOf: unreadable))

    let result = await store.records(matching: LogQuery())

    XCTAssertEqual(result.records.map(\.message), ["readable"])
    XCTAssertEqual(result.storageIssues, [.readFailed])
    XCTAssertFalse(result.isTruncated)
  }

  func testSuccessfulReadDoesNotClearWriteFailureButSuccessfulAppendDoes() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    store.append(
      failureRecord(at: fixture.now.addingTimeInterval(-86_400), message: "before"))
    store.synchronize()

    let blockedDay = fixture.dayURL(for: fixture.now)
    try FileManager.default.createDirectory(at: blockedDay, withIntermediateDirectories: false)
    store.append(failureRecord(at: fixture.now, message: "not-written"))
    store.synchronize()
    try FileManager.default.removeItem(at: blockedDay)

    let readable = await store.records(matching: LogQuery())
    XCTAssertEqual(readable.records.map(\.message), ["before"])
    XCTAssertEqual(readable.storageIssues, [.writeFailed])

    let readableAgain = await store.records(matching: LogQuery())
    XCTAssertEqual(readableAgain.storageIssues, [.writeFailed])

    store.append(failureRecord(at: fixture.now, message: "after"))
    let recovered = await store.records(matching: LogQuery())

    XCTAssertEqual(recovered.records.map(\.message), ["after", "before"])
    XCTAssertTrue(recovered.storageIssues.isEmpty)
  }

  func testTrimReadFailureLeavesOriginalItemAndItsContentsUntouched() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore(maxTotalBytes: 1_024)
    let unreadable = fixture.dayURL(for: fixture.now)
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
    let sentinel = unreadable.appendingPathComponent("original-data")
    let original = Data("must survive a failed trim".utf8)
    try original.write(to: sentinel)
    fixture.fileManager.reportSize(2_048, for: unreadable)
    XCTAssertThrowsError(try Data(contentsOf: unreadable))

    store.pruneExpired()
    store.synchronize()
    let result = await store.records(matching: LogQuery())

    XCTAssertTrue(FileManager.default.fileExists(atPath: unreadable.path))
    XCTAssertEqual(try Data(contentsOf: sentinel), original)
    XCTAssertFalse(fixture.fileManager.removalAttempts.contains(unreadable.path))
    XCTAssertTrue(result.storageIssues.contains(.maintenanceFailed))
    XCTAssertTrue(result.storageIssues.contains(.readFailed))
  }

  func testFailedAtomicTrimPreservesOriginalBytesAndReportsMaintenanceFailure() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
    let originalPermissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: originalPermissions], ofItemAtPath: fixture.directory.path)
    }
    let seedStore = fixture.makeStore()
    for offset in 0..<3 {
      seedStore.append(
        failureRecord(
          at: fixture.now.addingTimeInterval(TimeInterval(offset - 2)),
          message: "original-\(offset)"))
    }
    seedStore.synchronize()
    let dayFile = fixture.dayURL(for: fixture.now)
    let originalData = try Data(contentsOf: dayFile)
    let store = fixture.makeStore(maxTotalBytes: originalData.count - 1)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: fixture.directory.path)
    XCTAssertEqual(try Data(contentsOf: dayFile), originalData)

    // 先确认当前进程受目录写权限限制，避免特权执行环境把失败路径测成成功。
    let probe = fixture.directory.appendingPathComponent("atomic-write-permission-probe")
    var probeSucceeded = false
    do {
      try Data("probe".utf8).write(to: probe, options: .atomic)
      probeSucceeded = true
    } catch {}
    if probeSucceeded {
      throw XCTSkip("当前进程可写入只读目录，无法可靠触发 atomic trim 写入失败")
    }

    store.pruneExpired()
    store.synchronize()
    let result = await store.records(matching: LogQuery())

    XCTAssertEqual(try Data(contentsOf: dayFile), originalData)
    XCTAssertEqual(result.records.map(\.message), ["original-2", "original-1", "original-0"])
    XCTAssertEqual(result.storageIssues, [.maintenanceFailed])
  }

  func testFailedRemovalDoesNotCountAsFreedCapacityOrAllowAppend() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let seedStore = fixture.makeStore()
    let oldestDate = fixture.now.addingTimeInterval(-2 * 86_400)
    let newerDate = fixture.now.addingTimeInterval(-86_400)
    seedStore.append(failureRecord(at: oldestDate, message: String(repeating: "a", count: 500)))
    seedStore.append(failureRecord(at: newerDate, message: String(repeating: "b", count: 500)))
    seedStore.synchronize()
    let oldestURL = fixture.dayURL(for: oldestDate)
    let newerURL = fixture.dayURL(for: newerDate)
    let oldestData = try Data(contentsOf: oldestURL)
    let newerData = try Data(contentsOf: newerURL)
    let store = fixture.makeStore(maxTotalBytes: oldestData.count + newerData.count)
    fixture.fileManager.denyRemoval(of: oldestURL)

    store.append(failureRecord(at: fixture.now, message: "must-not-fit"))
    store.synchronize()
    let failed = await store.records(matching: LogQuery())

    XCTAssertTrue(fixture.fileManager.removalAttempts.contains(oldestURL.path))
    XCTAssertEqual(try Data(contentsOf: oldestURL), oldestData)
    XCTAssertEqual(try Data(contentsOf: newerURL), newerData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dayURL(for: fixture.now).path))
    XCTAssertFalse(failed.records.contains { $0.message == "must-not-fit" })
    XCTAssertEqual(failed.storageIssues, [.writeFailed])

    fixture.fileManager.allowRemoval(of: oldestURL)
    store.append(failureRecord(at: fixture.now, message: "after-retry"))
    let recovered = await store.records(matching: LogQuery())

    XCTAssertEqual(recovered.records.first?.message, "after-retry")
    XCTAssertTrue(recovered.storageIssues.isEmpty)
  }

  func testUnknownFileSizeBlocksAppendAndReportsMaintenanceFailure() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    let previousDay = fixture.now.addingTimeInterval(-86_400)
    store.append(failureRecord(at: previousDay, message: "original"))
    store.synchronize()
    let originalURL = fixture.dayURL(for: previousDay)
    let originalData = try Data(contentsOf: originalURL)
    fixture.fileManager.denyAttributes(of: originalURL)

    store.append(failureRecord(at: fixture.now, message: "blocked"))
    let result = await store.records(matching: LogQuery())

    XCTAssertEqual(result.records.map(\.message), ["original"])
    XCTAssertEqual(result.storageIssues, [.writeFailed, .maintenanceFailed])
    XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dayURL(for: fixture.now).path))
  }
}

@MainActor
final class LogViewerStorageFailureTests: XCTestCase {
  func testReadFailureSuppressesEmptyStateAndSuccessfulRetryRestoresIt() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    let viewModel = LogViewerViewModel(store: store, now: { fixture.now }, calendar: fixture.calendar)
    fixture.fileManager.failListing = true

    await viewModel.reloadRecords()

    XCTAssertTrue(viewModel.records.isEmpty)
    XCTAssertTrue(viewModel.storageIssues.contains(.readFailed))
    XCTAssertTrue(viewModel.storageErrorMessage?.contains(LogStorageIssue.readFailed.message) == true)
    XCTAssertFalse(viewModel.showsEmptyState)
    XCTAssertFalse(viewModel.isLoading)

    fixture.fileManager.failListing = false
    await viewModel.reloadRecords()

    XCTAssertTrue(viewModel.storageIssues.isEmpty)
    XCTAssertNil(viewModel.storageErrorMessage)
    XCTAssertTrue(viewModel.showsEmptyState)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testPartialReadKeepsRecordsVisibleWithErrorUntilRetrySucceeds() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let store = fixture.makeStore()
    store.append(
      failureRecord(at: fixture.now.addingTimeInterval(-86_400), message: "still-visible"))
    store.synchronize()
    let unreadable = fixture.dayURL(for: fixture.now)
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
    let viewModel = LogViewerViewModel(store: store, now: { fixture.now }, calendar: fixture.calendar)
    viewModel.timeFilter = .last7Days

    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["still-visible"])
    XCTAssertEqual(viewModel.storageIssues, [.readFailed])
    XCTAssertEqual(viewModel.storageErrorMessage, LogStorageIssue.readFailed.message)
    XCTAssertFalse(viewModel.showsEmptyState)

    try FileManager.default.removeItem(at: unreadable)
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["still-visible"])
    XCTAssertTrue(viewModel.storageIssues.isEmpty)
    XCTAssertNil(viewModel.storageErrorMessage)
  }

  func testLateFailedReloadCannotReplaceNewerSuccessfulReload() async throws {
    let fixture = try LogFailureFixture()
    defer { fixture.cleanUp() }
    let gate = LogFailureReloadGate()
    let store = fixture.makeGatedStore(gate: gate)
    let viewModel = LogViewerViewModel(store: store, now: { fixture.now }, calendar: fixture.calendar)
    fixture.fileManager.failListing = true

    let oldReload = Task { await viewModel.reloadRecords() }
    await gate.waitUntilEntered()
    fixture.fileManager.failListing = false
    store.append(failureRecord(at: fixture.now, message: "new-success"))
    await viewModel.reloadRecords()

    XCTAssertEqual(viewModel.records.map(\.message), ["new-success"])
    XCTAssertTrue(viewModel.storageIssues.isEmpty)
    XCTAssertNil(viewModel.storageErrorMessage)

    await gate.release()
    await oldReload.value

    XCTAssertEqual(viewModel.records.map(\.message), ["new-success"])
    XCTAssertTrue(viewModel.storageIssues.isEmpty)
    XCTAssertNil(viewModel.storageErrorMessage)
    XCTAssertFalse(viewModel.showsEmptyState)
    XCTAssertFalse(viewModel.isLoading)
  }
}

private final class LogFailureFileManager: FileManager, @unchecked Sendable {
  private let lock = NSLock()
  private var listingFails = false
  private var deniedRemovals: Set<String> = []
  private var deniedAttributes: Set<String> = []
  private var sizes: [String: Int] = [:]
  private var attemptedRemovals: [String] = []

  var failListing: Bool {
    get { lock.withLock { listingFails } }
    set { lock.withLock { listingFails = newValue } }
  }

  var removalAttempts: [String] {
    lock.withLock { attemptedRemovals }
  }

  func reportSize(_ size: Int, for url: URL) {
    lock.withLock { sizes[url.path] = size }
  }

  func denyRemoval(of url: URL) {
    lock.withLock { _ = deniedRemovals.insert(url.path) }
  }

  func allowRemoval(of url: URL) {
    lock.withLock { _ = deniedRemovals.remove(url.path) }
  }

  func denyAttributes(of url: URL) {
    lock.withLock { _ = deniedAttributes.insert(url.path) }
  }

  override func contentsOfDirectory(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions = []
  ) throws -> [URL] {
    if failListing { throw CocoaError(.fileReadNoPermission) }
    return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
  }

  override func removeItem(at url: URL) throws {
    let denied = lock.withLock {
      attemptedRemovals.append(url.path)
      return deniedRemovals.contains(url.path)
    }
    if denied { throw CocoaError(.fileWriteNoPermission) }
    try super.removeItem(at: url)
  }

  override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
    let (denied, reportedSize) = lock.withLock { (deniedAttributes.contains(path), sizes[path]) }
    if denied { throw CocoaError(.fileReadNoPermission) }
    var attributes = try super.attributesOfItem(atPath: path)
    if let reportedSize { attributes[.size] = NSNumber(value: reportedSize) }
    return attributes
  }
}

private final class LogFailureFixture {
  let directory: URL
  let fileManager = LogFailureFileManager()
  let now = Date(timeIntervalSince1970: 2_000_800_000)
  let calendar: Calendar
  private let suiteName: String
  private let defaults: UserDefaults
  private var stores: [PersistentLogStore] = []

  init() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let suiteName = "log-storage-failure-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("log-storage-failure-\(UUID().uuidString)", isDirectory: true)
    self.calendar = calendar
    self.suiteName = suiteName
    self.defaults = defaults
    self.directory = directory
    defaults.removePersistentDomain(forName: suiteName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func makeStore(maxTotalBytes: Int = PersistentLogStore.maxTotalBytes) -> PersistentLogStore {
    let fixedNow = now
    let store = PersistentLogStore(
      directory: directory,
      fileManager: fileManager,
      now: { fixedNow },
      calendar: calendar,
      maxTotalBytes: maxTotalBytes,
      defaults: defaults
    )
    stores.append(store)
    return store
  }

  func makeGatedStore(gate: LogFailureReloadGate) -> LogFailureGatedStore {
    let store = LogFailureGatedStore(
      directory: directory,
      fileManager: fileManager,
      now: now,
      calendar: calendar,
      defaults: defaults,
      gate: gate
    )
    stores.append(store)
    return store
  }

  func dayURL(for date: Date) -> URL {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let name = String(
      format: "%04d-%02d-%02d.jsonl", components.year!, components.month!, components.day!)
    return directory.appendingPathComponent(name)
  }

  func cleanUp() {
    for store in stores { store.synchronize() }
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private actor LogFailureReloadGate {
  private var shouldHold = true
  private var entered = false
  private var released = false
  private var entryContinuation: CheckedContinuation<Void, Never>?
  private var responseContinuation: CheckedContinuation<Void, Never>?

  func holdFirstResponse() async {
    guard shouldHold else { return }
    shouldHold = false
    entered = true
    entryContinuation?.resume()
    entryContinuation = nil
    guard !released else { return }
    await withCheckedContinuation { responseContinuation = $0 }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { entryContinuation = $0 }
  }

  func release() {
    released = true
    responseContinuation?.resume()
    responseContinuation = nil
  }
}

private final class LogFailureGatedStore: PersistentLogStore, @unchecked Sendable {
  private let gate: LogFailureReloadGate

  init(
    directory: URL,
    fileManager: FileManager,
    now: Date,
    calendar: Calendar,
    defaults: UserDefaults,
    gate: LogFailureReloadGate
  ) {
    self.gate = gate
    super.init(
      directory: directory,
      fileManager: fileManager,
      now: { now },
      calendar: calendar,
      defaults: defaults
    )
  }

  override func records(matching query: LogQuery) async -> LogQueryResult {
    let result = await super.records(matching: query)
    await gate.holdFirstResponse()
    return result
  }
}

private func failureRecord(at date: Date, message: String) -> LogRecord {
  LogRecord(
    id: UUID(),
    timestamp: date,
    level: .warning,
    message: message,
    fileName: "LogStorageFailureTests.swift",
    function: "test()",
    line: 1,
    metadata: nil
  )
}
