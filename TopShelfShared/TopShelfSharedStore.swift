import CryptoKit
import Darwin
import Foundation

nonisolated enum TopShelfSharedStoreError: Error, Equatable {
  case unsupportedSchema
  case invalidImagePath
}

nonisolated struct TopShelfSharedStore: @unchecked Sendable {
  static func appGroupIdentifier(in bundle: Bundle = .main) -> String? {
    TopShelfAppGroup.identifier(in: bundle)
  }

  typealias DataWriter = @Sendable (Data, URL) throws -> Void

  private let containerURL: URL
  private let writeData: DataWriter
  private let persistentDefaults: UserDefaults?
  private static let recoveryKey = "TopShelfRecoveryState"

  init(
    containerURL: URL,
    persistentDefaults: UserDefaults? = nil,
    writeData: @escaping DataWriter = { data, url in
      try data.write(to: url, options: .atomic)
    }
  ) {
    self.containerURL = containerURL.standardizedFileURL
    self.writeData = writeData
    self.persistentDefaults = persistentDefaults
  }

  static func appGroupStore(
    fileManager: FileManager = .default, bundle: Bundle = .main
  ) -> TopShelfSharedStore? {
    guard
      let appGroupIdentifier = appGroupIdentifier(in: bundle),
      let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      ),
      let defaults = UserDefaults(suiteName: appGroupIdentifier)
    else { return nil }
    return TopShelfSharedStore(containerURL: containerURL, persistentDefaults: defaults)
  }

  var stateFileURL: URL {
    storageRootURL.appendingPathComponent("state.json", isDirectory: false)
  }

  fileprivate var storageRootURL: URL {
    containerURL.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
  }

  private var imageRootURL: URL {
    storageRootURL.appendingPathComponent("images", isDirectory: true)
  }

  private var detailRootURL: URL {
    storageRootURL.appendingPathComponent("details", isDirectory: true)
  }

  func loadState() throws -> TopShelfSharedState? {
    let data: Data
    if FileManager.default.fileExists(atPath: stateFileURL.path) {
      data = try Data(contentsOf: stateFileURL)
    } else {
      guard let persistentDefaults else { return nil }
      guard let saved = persistentDefaults.data(forKey: Self.recoveryKey) else { return nil }
      data = saved
    }
    let state = try JSONDecoder().decode(TopShelfSharedState.self, from: data)
    guard state.schemaVersion == TopShelfSharedState.currentSchemaVersion else {
      throw TopShelfSharedStoreError.unsupportedSchema
    }
    return state
  }

  func saveState(_ state: TopShelfSharedState) throws {
    try withPublicationLock { try writeState(state) }
  }

  private func writeState(_ state: TopShelfSharedState) throws {
    try ensureStorageRoot()
    if let persistentDefaults {
      var recovery = state
      recovery.snapshot = nil
      recovery.previousSnapshot = nil
      persistentDefaults.set(try JSONEncoder().encode(recovery), forKey: Self.recoveryKey)
    }
    if let snapshot = state.snapshot {
      try FileManager.default.createDirectory(at: cardRootURL, withIntermediateDirectories: true)
      for item in snapshot.items {
        try writeData(JSONEncoder().encode(item), cardURL(for: item.displayURL))
      }
    }
    try writeData(JSONEncoder().encode(state), stateFileURL)
  }

  private var cardRootURL: URL { storageRootURL.appendingPathComponent("cards", isDirectory: true) }

  private func cardURL(for url: URL) -> URL {
    let canonicalURL =
      TopShelfDeepLink.payload(from: url).flatMap { try? TopShelfDeepLink.url(for: $0) } ?? url
    let digest = SHA256.hash(data: Data(canonicalURL.absoluteString.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    return cardRootURL.appendingPathComponent(digest + ".json")
  }

  fileprivate func withPublicationLock<T>(_ body: () throws -> T) throws -> T {
    try ensureStorageRoot()
    let fd = open(
      storageRootURL.appendingPathComponent("publication.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  /// App 和扩展共享同一发布边界；改选、登出或另一轮发布后，旧请求不能写回。
  func publish(_ snapshot: TopShelfSnapshot, replacing expected: TopShelfSharedState) throws {
    try withPublicationLock {
      try publishLocked(snapshot, replacing: expected)
    }
  }

  fileprivate func publishLocked(
    _ snapshot: TopShelfSnapshot, replacing expected: TopShelfSharedState
  ) throws {
    try Task.checkCancellation()
    guard var current = try loadState(), current == expected else { throw CancellationError() }
    let previouslyProtected = protectedResourcePaths(in: current)
    current.previousSnapshot = current.snapshot
    current.snapshot = snapshot
    let retired = previouslyProtected.subtracting(protectedResourcePaths(in: current))
    let now = Date()
    for path in retired {
      let url = storageRootURL.appendingPathComponent(path)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      // 先延长保留时间再切换快照；发布失败至多延迟回收，不会提前删除旧批次。
      try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
    try writeState(current)
  }

  func setRefreshConfiguration(_ configuration: TopShelfRefreshConfiguration?) throws {
    try withPublicationLock {
      guard var state = try loadState() else { return }
      if let configuration {
        guard state.activeSessionID == configuration.sessionID, state.selection != nil else {
          return
        }
      }
      guard state.refreshConfiguration != configuration else { return }
      state.refreshConfiguration = configuration
      try writeState(state)
    }
  }

  /// 选择是下一批的来源；同账号已发布的内容保留到新批次就绪。
  func setSelection(_ selection: TopShelfSelection, sessionID: String) throws {
    try withPublicationLock {
      guard let state = try loadState(), state.activeSessionID == sessionID else {
        throw CancellationError()
      }
      try writeState(
        TopShelfSharedState(
          schemaVersion: state.schemaVersion, activeSessionID: sessionID,
          selection: selection, snapshot: state.snapshot,
          refreshConfiguration: state.refreshConfiguration, previousSnapshot: state.previousSnapshot
        ))
    }
  }

  /// 会话切换、登出、撤权或关闭展示时先把旧状态移出发布路径。
  /// 即使随后 disabled state 写失败，扩展也无法再读取旧快照。
  func invalidatePublishedState(_ disabledState: TopShelfSharedState) throws {
    try withPublicationLock { try invalidateState(disabledState) }
  }

  private func invalidateState(_ disabledState: TopShelfSharedState) throws {
    if let persistentDefaults {
      persistentDefaults.removeObject(forKey: Self.recoveryKey)
    }
    try ensureStorageRoot()
    let fileManager = FileManager.default
    var revokedURL: URL?

    if fileManager.fileExists(atPath: stateFileURL.path) {
      let quarantine = storageRootURL.appendingPathComponent(
        ".revoked-\(UUID().uuidString).json",
        isDirectory: false
      )
      do {
        try fileManager.moveItem(at: stateFileURL, to: quarantine)
        revokedURL = quarantine
      } catch {
        // rename 失败时再尝试删除；两者都失败则不能声称已 fail-closed。
        try fileManager.removeItem(at: stateFileURL)
      }
    }

    do {
      try writeState(disabledState)
      if let revokedURL {
        try? fileManager.removeItem(at: revokedURL)
      }
    } catch {
      // 不恢复 quarantine：canonical 路径保持不存在才是失败时的安全状态。
      throw error
    }
  }

  func imageURL(relativePath: String) -> URL? {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
    let candidate = storageRootURL.appendingPathComponent(relativePath).standardizedFileURL
    let rootPath = imageRootURL.standardizedFileURL.path
    guard candidate.path.hasPrefix(rootPath + "/") else { return nil }
    return candidate
  }

  func hasPreparedResources(for snapshot: TopShelfSnapshot) -> Bool {
    !snapshot.items.isEmpty
      && snapshot.items.allSatisfy { item in
        guard let poster = imageURL(relativePath: item.imageRelativePath),
          let backgroundPath = item.backgroundRelativePath,
          let background = imageURL(relativePath: backgroundPath),
          let detailPath = item.detailRelativePath
        else { return false }
        return FileManager.default.fileExists(atPath: poster.path)
          && FileManager.default.fileExists(atPath: background.path)
          && (try? detailData(relativePath: detailPath)) != nil
      }
  }

  func presentation(at date: Date) -> TopShelfPresentation? {
    guard let state = try? loadState(),
      let activeSessionID = state.activeSessionID,
      state.selection != nil,
      let snapshot = state.snapshot,
      snapshot.sessionID == activeSessionID,
      !snapshot.items.isEmpty
    else { return nil }

    let fileManager = FileManager.default
    var items: [TopShelfPresentationItem] = []
    items.reserveCapacity(snapshot.items.count)
    for item in snapshot.items.prefix(TopShelfSnapshot.maximumItems) {
      let identifier = item.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
      let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !identifier.isEmpty, !title.isEmpty,
        let imageURL = imageURL(relativePath: item.imageRelativePath),
        fileManager.fileExists(atPath: imageURL.path),
        let payload = TopShelfDeepLink.payload(from: item.displayURL),
        payload.sessionID == activeSessionID
      else { continue }
      items.append(
        TopShelfPresentationItem(
          identifier: identifier,
          title: title,
          imageURL: imageURL,
          displayURL: item.displayURL
        )
      )
    }
    return items.isEmpty ? nil : TopShelfPresentation(title: snapshot.selection.title, items: items)
  }

  /// 只从当前会话的共享快照解析本地图片，深链不能自行指定文件路径。
  func previewImageURL(for payload: TopShelfRoutePayload, at date: Date) -> URL? {
    guard let item = cachedItem(for: payload, at: date),
      let url = imageURL(relativePath: item.imageRelativePath),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }

  func cachedItem(for payload: TopShelfRoutePayload, at date: Date) -> TopShelfSnapshotItem? {
    guard let state = try? loadState(), state.activeSessionID == payload.sessionID,
      state.selection != nil
    else { return nil }
    if let item = state.snapshot?.items.first(where: {
      TopShelfDeepLink.payload(from: $0.displayURL) == payload
    }) {
      return item
    }
    guard let url = try? TopShelfDeepLink.url(for: payload),
      let data = try? Data(contentsOf: cardURL(for: url)),
      let item = try? JSONDecoder().decode(TopShelfSnapshotItem.self, from: data),
      TopShelfDeepLink.payload(from: item.displayURL) == payload
    else { return nil }
    return item
  }

  func writeDetailData(_ data: Data, cacheKey: String) throws -> String {
    try FileManager.default.createDirectory(at: detailRootURL, withIntermediateDirectories: true)
    let digest = SHA256.hash(data: Data(cacheKey.utf8) + data)
      .map { String(format: "%02x", $0) }.joined()
    let path = "details/\(digest).json"
    try writeData(data, storageRootURL.appendingPathComponent(path))
    return path
  }

  func detailData(relativePath: String) throws -> Data? {
    guard relativePath.hasPrefix("details/"), !relativePath.hasPrefix("/") else { return nil }
    let url = storageRootURL.appendingPathComponent(relativePath).standardizedFileURL
    guard url.path.hasPrefix(detailRootURL.path + "/"),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return try Data(contentsOf: url)
  }

  func writeImage(_ resource: TopShelfImageResource, cacheKey: String) throws -> String {
    let ext = resource.fileExtension.lowercased()
    guard !ext.isEmpty, ext.count <= 8,
      ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
    else { throw TopShelfSharedStoreError.invalidImagePath }

    try FileManager.default.createDirectory(
      at: imageRootURL,
      withIntermediateDirectories: true
    )
    let digest = SHA256.hash(data: Data(cacheKey.utf8) + resource.data)
      .map { String(format: "%02x", $0) }
      .joined()
    let fileName = "\(digest).\(ext)"
    let target = imageRootURL.appendingPathComponent(fileName, isDirectory: false)
    try resource.data.write(to: target, options: .atomic)
    return "images/\(fileName)"
  }

  func resourcePaths(for items: [TopShelfSnapshotItem]) -> [String] {
    items.flatMap { $0.resourcePaths + ["cards/" + cardURL(for: $0.displayURL).lastPathComponent] }
  }

  private func protectedResourcePaths(in state: TopShelfSharedState) -> Set<String> {
    Set(resourcePaths(for: state.snapshot?.items ?? [])
      + resourcePaths(for: state.previousSnapshot?.items ?? []))
  }

  fileprivate var preparationRootURL: URL {
    storageRootURL.appendingPathComponent("preparations", isDirectory: true)
  }

  func beginResourcePreparation() throws -> TopShelfResourcePreparation {
    try withPublicationLock {
      try? pruneResourcesLocked(
        keepingRelativePaths: [], now: Date(), gracePeriod: TopShelfSnapshot.imageCleanupGracePeriod
      )
      return try TopShelfResourcePreparation(store: self)
    }
  }

  func pruneResources(
    keepingRelativePaths: Set<String>, now: Date, gracePeriod: TimeInterval
  ) throws {
    try withPublicationLock {
      try pruneResourcesLocked(
        keepingRelativePaths: keepingRelativePaths, now: now, gracePeriod: gracePeriod)
    }
  }

  /// 写入、发布和回收共用跨进程锁；引用集合必须从锁内的最新状态读取。
  fileprivate func pruneResourcesLocked(
    keepingRelativePaths: Set<String>, now: Date, gracePeriod: TimeInterval,
    excludingPreparation: URL? = nil
  ) throws {
    let fileManager = FileManager.default
    let state = try loadState()
    var retained = keepingRelativePaths.union(state.map(protectedResourcePaths) ?? [])
    var abandoned: [URL] = []
    if fileManager.fileExists(atPath: preparationRootURL.path) {
      for directory in try fileManager.contentsOfDirectory(
        at: preparationRootURL, includingPropertiesForKeys: [.isDirectoryKey])
      {
        guard directory != excludingPreparation,
          try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        else { continue }
        let manifest = directory.appendingPathComponent("resources.json")
        if try TopShelfResourcePreparation.isCurrent(manifest, at: now) {
          let paths = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: manifest))
          retained.formUnion(paths)
        } else {
          abandoned.append(directory)
        }
      }
    }

    var resources: [(url: URL, path: String, modifiedAt: Date)] = []
    for root in [imageRootURL, detailRootURL, cardRootURL] {
      guard fileManager.fileExists(atPath: root.path) else { continue }
      for file in try fileManager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles])
      {
        let values = try file.resourceValues(forKeys: [
          .contentModificationDateKey,
          .isRegularFileKey,
        ])
        guard values.isRegularFile == true else { continue }
        let path = "\(root.lastPathComponent)/\(file.lastPathComponent)"
        let modifiedAt = values.contentModificationDate ?? .distantPast
        resources.append((file, path, modifiedAt))
        // 系统可能仍在使用最近展示过的旧卡片，宽限期内连同图片和详情一起保留。
        if root == cardRootURL,
          retained.contains(path) || now.timeIntervalSince(modifiedAt) < gracePeriod
        {
          let data = try Data(contentsOf: file)
          if let item = try? JSONDecoder().decode(TopShelfSnapshotItem.self, from: data) {
            retained.formUnion(item.resourcePaths)
          }
        }
      }
    }
    for resource in resources where !retained.contains(resource.path) {
      guard now.timeIntervalSince(resource.modifiedAt) >= gracePeriod else { continue }
      try fileManager.removeItem(at: resource.url)
    }
    for directory in abandoned { try fileManager.removeItem(at: directory) }
  }

  private func ensureStorageRoot() throws {
    try FileManager.default.createDirectory(
      at: storageRootURL,
      withIntermediateDirectories: true
    )
  }
}

/// 准备清单在每次写入时续期；过期后禁止继续写入或发布，网络等待期间不持文件锁。
nonisolated final class TopShelfResourcePreparation: @unchecked Sendable {
  private static let maximumIdleInterval: TimeInterval = 24 * 60 * 60
  private let store: TopShelfSharedStore
  private let directory: URL
  private let lock = NSLock()
  private var finished = false
  private var paths: Set<String> = []

  private var manifestURL: URL { directory.appendingPathComponent("resources.json") }

  fileprivate static func isCurrent(_ manifest: URL, at date: Date) throws -> Bool {
    guard FileManager.default.fileExists(atPath: manifest.path) else { return false }
    let values = try manifest.resourceValues(forKeys: [.contentModificationDateKey])
    guard let modifiedAt = values.contentModificationDate else { return false }
    return date.timeIntervalSince(modifiedAt) < maximumIdleInterval
  }

  fileprivate init(store: TopShelfSharedStore) throws {
    self.store = store
    directory = store.preparationRootURL.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
      try JSONEncoder().encode(paths).write(to: manifestURL, options: .atomic)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  deinit { try? finish() }

  func writeImage(_ resource: TopShelfImageResource, cacheKey: String) throws -> String {
    try record { try store.writeImage(resource, cacheKey: cacheKey) }
  }

  func writeDetailData(_ data: Data, cacheKey: String) throws -> String {
    try record { try store.writeDetailData(data, cacheKey: cacheKey) }
  }

  private func record(_ write: () throws -> String) throws -> String {
    try withCurrentPreparation {
      let path = try write()
      paths.insert(path)
      try JSONEncoder().encode(paths).write(to: manifestURL, options: .atomic)
      return path
    }
  }

  func publish(_ snapshot: TopShelfSnapshot, replacing expected: TopShelfSharedState) throws {
    try withCurrentPreparation {
      let referenced = Set(snapshot.items.flatMap(\.resourcePaths))
      guard referenced.isSubset(of: paths), referenced.allSatisfy({
        FileManager.default.fileExists(atPath: store.storageRootURL.appendingPathComponent($0).path)
      }) else { throw CancellationError() }
      try store.publishLocked(snapshot, replacing: expected)
    }
  }

  private func withCurrentPreparation<T>(_ operation: () throws -> T) throws -> T {
    try lock.withLock {
      guard !finished else { throw CancellationError() }
      return try store.withPublicationLock {
        try Task.checkCancellation()
        guard try Self.isCurrent(manifestURL, at: Date()) else { throw CancellationError() }
        return try operation()
      }
    }
  }

  func finish(now: Date = Date()) throws {
    try lock.withLock {
      guard !finished else { return }
      defer { finished = true }
      try store.withPublicationLock {
        try store.pruneResourcesLocked(
          keepingRelativePaths: [], now: now, gracePeriod: TopShelfSnapshot.imageCleanupGracePeriod,
          excludingPreparation: directory)
        if FileManager.default.fileExists(atPath: directory.path) {
          try FileManager.default.removeItem(at: directory)
        }
      }
    }
  }
}
