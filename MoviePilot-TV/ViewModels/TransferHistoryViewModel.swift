import Combine
import Foundation

private enum TransferHistoryMutationValidation: Equatable {
  case valid
  case changed
  case unavailable(String)
  case cancelled
}

@MainActor
class TransferHistoryViewModel: ObservableObject {
  // MARK: - Published Properties

  @Published var items: [TransferHistory] = []
  @Published var isFirstLoading: Bool = false
  @Published var isLoadingMore: Bool = false
  @Published private(set) var isDeleting = false
  @Published private(set) var isValidatingMutation = false
  @Published var errorMessage: String?  // TODO
  @Published var mutationRetryMessage: String?
  @Published var isSelectionMode: Bool = false
  @Published var selectedIds: Set<Int> = []
  @Published var searchText: String = ""
  @Published var storageDict: [String: String] = [:]

  // AI 重新整理相关状态
  @Published var aiRedoingIds: Set<Int> = []
  @Published var aiRedoProgressText: String = ""
  @Published var isAiRedoing: Bool = false
  private var aiRedoTask: Task<Void, Never>?

  var isAiRedoEnabled: Bool {
    apiService.settings?.AI_AGENT_ENABLE?.value != false
  }

  var isMutatingHistory: Bool {
    isDeleting || isAiRedoing || isValidatingMutation
  }

  // MARK: - Private State

  private var paginator: Paginator<TransferHistory>!
  private var fetcher: (Int) async throws -> TransferHistoryResponse
  private var queryGeneration = 0
  private var cancellables = Set<AnyCancellable>()
  private var batchDeleteTask: Task<Void, Never>?
  private let apiService: APIService
  // 后端固定每页条数，供轮询游标推进/回退统一计算。
  private let pageSize = 20
  // 与 Paginator threshold 保持一致，基于可见列表位置触发 loadMore。
  private let loadMoreThreshold = 8
  // Paginator 当前维护的分页数据层（按页追加）。
  private var paginatorItems: [TransferHistory] = []
  // 轮询拉到的最新数据层（插在列表头部）。
  private var prependedItems: [TransferHistory] = []
  // 已删除项目的屏蔽集，避免旧页回流到 UI。
  private var deletedIds: Set<Int> = []
  // 新增累计计数器：每累计满一页，推进一次分页游标。
  private var pendingInsertionShiftCount: Int = 0
  // 删除累计计数器：每累计满一页，回退一次分页游标。
  private var pendingDeletionShiftCount: Int = 0

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    // 使用局部变量 api 避免在初始化 dataManager 时捕获 self
    let pageSize = self.pageSize
    let api = apiService
    self.fetcher = { page in
      try await api.fetchTransferHistory(
        page: page,
        count: pageSize,
        title: nil)
    }
    configurePaginator()
  }

  private func configurePaginator() {
    paginator?.cancel()

    // 初始化 Paginator
    self.paginator = Paginator<TransferHistory>(
      threshold: loadMoreThreshold,
      fetcher: { [weak self] page in
        guard let self else { return [] }
        let response = try await self.fetcher(page)
        return response.list
      },
      processor: { items, newItems in
        let existingIds = Set(items.map(\.id))
        let uniqueNewItems = newItems.filter { !existingIds.contains($0.id) }
        if !uniqueNewItems.isEmpty {
          items.append(contentsOf: uniqueNewItems)
          return true
        }
        return false
      },
      onReset: { [weak self] in
        guard let self else { return }
        self.paginatorItems = []
        self.rebuildItems()
      }
    )
    syncWithPaginator()
  }

  private func syncWithPaginator() {
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()
    paginator.$items
      .sink { [weak self] newItems in
        guard let self else { return }
        self.paginatorItems = newItems
        self.rebuildItems()
      }
      .store(in: &cancellables)
  }

  func search(with text: String) {
    guard !isMutatingHistory else { return }
    queryGeneration += 1
    guard apiService.canAccess(.manage) else {
      searchText = text
      clearForRestrictedUser()
      return
    }
    searchText = text
    let api = apiService
    let effectiveText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = effectiveText.isEmpty ? nil : effectiveText

    self.fetcher = { page in
      try await api.fetchTransferHistory(
        page: page,
        count: self.pageSize,
        title: title)
    }
    resetDynamicState(clearDeletedIds: true)
    configurePaginator()

    Task {
      await refresh()
    }
  }

  private func handle(error: Error) {
    let errorDescription = "操作失败: \(error.localizedDescription)"
    print(errorDescription)
    errorMessage = errorDescription
  }

  @discardableResult
  func refresh() async -> Bool {
    guard !isMutatingHistory else { return false }
    await performAuthoritativeRefresh()
    return true
  }

  private func performAuthoritativeRefresh() async {
    // 与搜索切换相同：权威刷新开始后，之前已在途的增量结果一律失效。
    queryGeneration += 1
    errorMessage = nil
    isLoadingMore = false
    guard apiService.canAccess(.manage) else {
      clearForRestrictedUser()
      return
    }
    isFirstLoading = true
    defer {
      isFirstLoading = false
    }

    let sessionSnapshot = apiService.sessionSnapshot()
    resetDynamicState(clearDeletedIds: true)
    await loadStorages()
    guard !Task.isCancelled, apiService.isSessionUnchanged(from: sessionSnapshot) else { return }
    await paginator.refresh()
  }

  func cancelRefresh() {
    queryGeneration += 1
    paginator.cancel()
    isFirstLoading = false
    isLoadingMore = false
  }

  private func loadStorages() async {
    guard apiService.canAccess(.manage) else {
      storageDict = [:]
      return
    }
    do {
      let storages = try await apiService.fetchStorages()
      var dict = [String: String]()
      for storage in storages {
        dict[storage.type] = storage.name
      }
      storageDict = dict
    } catch is CancellationError {
      return
    } catch {
      print("[TransferHistoryViewModel] Failed to load storages: \(error.localizedDescription)")
    }
  }

  private func clearForRestrictedUser() {
    paginator.cancel()
    storageDict = [:]
    paginatorItems = []
    resetDynamicState(clearDeletedIds: true)
  }

  func loadMore(currentItemId: TransferHistory.ID) async {
    guard !isMutatingHistory else { return }
    errorMessage = nil
    guard apiService.canAccess(.manage) else { return }
    guard !isLoadingMore else { return }

    // 以“展示层”位置判断是否触底，避免 focus 落在 prependedItems 时被 Paginator 忽略。
    guard let focusedIndex = items.firstIndex(where: { $0.id == currentItemId }) else { return }
    let thresholdIndex = max(0, items.count - loadMoreThreshold)
    guard focusedIndex >= thresholdIndex else { return }

    isLoadingMore = true
    defer {
      isLoadingMore = false
    }

    applyPendingDeletionCursorShiftBeforeLoadMore()
    await paginator.loadMore(nil)
  }

  func captureMutationSession() -> APIServiceSessionSnapshot {
    apiService.sessionSnapshot()
  }

  func deleteHistory(
    item: TransferHistory,
    deleteSource: Bool,
    deleteDest: Bool,
    sourceSession: APIServiceSessionSnapshot
  ) async {
    errorMessage = nil
    mutationRetryMessage = nil
    guard apiService.isSessionUnchanged(from: sourceSession),
      apiService.canAccess(.manage), !isMutatingHistory
    else { return }
    isDeleting = true
    defer { isDeleting = false }

    let validation = await validateMutationTargets([item], sourceSession: sourceSession)
    guard validation == .valid else {
      mutationRetryMessage = await validationFailureMessage(for: validation)
      return
    }

    do {
      guard apiService.isSessionUnchanged(from: sourceSession) else {
        throw CancellationError()
      }
      let result = try await apiService.deleteTransferHistory(
        item: item,
        deleteSource: deleteSource,
        deleteDest: deleteDest)
      guard apiService.isSessionUnchanged(from: sourceSession) else {
        throw CancellationError()
      }

      if result.success {
        markDeleted(id: item.id)
        pendingDeletionShiftCount += 1
      } else {
        errorMessage = result.message ?? "删除失败 (id: \(item.id))"
      }
    } catch is CancellationError {
      return
    } catch {
      handle(error: error)
    }
  }

  func toggleSelection(id: Int) {
    guard !isMutatingHistory else { return }
    if selectedIds.contains(id) {
      selectedIds.remove(id)
    } else {
      selectedIds.insert(id)
    }
  }

  func selectAll() {
    guard !isMutatingHistory else { return }
    selectedIds = Set(items.map { $0.id })
  }

  func deselectAll() {
    guard !isMutatingHistory else { return }
    selectedIds.removeAll()
  }

  /// 在展示确认时冻结完整记录，确保确认数量和最终删除始终消费同一批次。
  func selectedItemsSnapshot() -> [TransferHistory] {
    items.filter { selectedIds.contains($0.id) }
  }

  func deleteSelected(
    items itemsToDelete: [TransferHistory],
    deleteSource: Bool,
    deleteDest: Bool,
    sourceSession: APIServiceSessionSnapshot
  ) {
    errorMessage = nil
    mutationRetryMessage = nil
    guard apiService.isSessionUnchanged(from: sourceSession),
      apiService.canAccess(.manage), !isMutatingHistory,
      batchDeleteTask == nil, !itemsToDelete.isEmpty
    else { return }

    isDeleting = true
    // 批删任务由 ViewModel 持有；页面退出后仍按确认快照完成，不回读实时列表。
    batchDeleteTask = Task { [self] in
      await performDeleteSelected(
        items: itemsToDelete,
        deleteSource: deleteSource,
        deleteDest: deleteDest,
        sourceSession: sourceSession
      )
    }
  }

  private func performDeleteSelected(
    items itemsToDelete: [TransferHistory],
    deleteSource: Bool,
    deleteDest: Bool,
    sourceSession: APIServiceSessionSnapshot
  ) async {
    defer {
      isDeleting = false
      batchDeleteTask = nil
    }
    guard apiService.isSessionUnchanged(from: sourceSession) else { return }
    var deletedCount = 0
    var failures: [String] = []

    let validation = await validateMutationTargets(
      itemsToDelete,
      sourceSession: sourceSession
    )
    guard validation == .valid else {
      mutationRetryMessage = await validationFailureMessage(for: validation)
      return
    }

    for item in itemsToDelete {
      let id = item.id
      do {
        guard apiService.isSessionUnchanged(from: sourceSession) else { return }
        let result = try await apiService.deleteTransferHistory(
          item: item,
          deleteSource: deleteSource,
          deleteDest: deleteDest)
        guard apiService.isSessionUnchanged(from: sourceSession) else { return }

        if result.success {
          markDeleted(id: id)
          deletedCount += 1
        } else {
          failures.append(result.message ?? "id: \(id)")
        }
      } catch is CancellationError {
        return
      } catch {
        failures.append("id: \(id)，\(error.localizedDescription)")
      }
    }

    if !failures.isEmpty {
      errorMessage = "部分记录删除失败：\(failures.joined(separator: "；"))"
    }

    pendingDeletionShiftCount += deletedCount

    if selectedIds.isEmpty {
      isSelectionMode = false
    }
  }

  /// 手动/批量整理在真正提交前复用同一校验；失败提示由当前 Sheet 呈现。
  func validateBeforeReorganize(
    items expectedItems: [TransferHistory],
    sourceSession: APIServiceSessionSnapshot
  ) async throws -> String? {
    guard apiService.isSessionUnchanged(from: sourceSession),
      apiService.canAccess(.manage), !isMutatingHistory, !expectedItems.isEmpty
    else {
      throw CancellationError()
    }

    isValidatingMutation = true
    defer { isValidatingMutation = false }
    let validation = await validateMutationTargets(
      expectedItems,
      sourceSession: sourceSession
    )
    if validation == .cancelled {
      throw CancellationError()
    }
    return await validationFailureMessage(for: validation)
  }

  private func validateMutationTargets(
    _ expectedItems: [TransferHistory],
    sourceSession: APIServiceSessionSnapshot
  ) async -> TransferHistoryMutationValidation {
    guard !expectedItems.isEmpty,
      apiService.isSessionUnchanged(from: sourceSession)
    else { return .cancelled }
    do {
      // 后端自 v2.15.1 起约定负 count 返回全表；只在 mutation 前使用一次。
      let response = try await apiService.fetchTransferHistory(page: 1, count: -1, title: nil)
      guard apiService.isSessionUnchanged(from: sourceSession) else { return .cancelled }

      var currentItemsByID: [Int: TransferHistory] = [:]
      currentItemsByID.reserveCapacity(response.list.count)
      for item in response.list {
        currentItemsByID[item.id] = item
      }

      let allTargetsAreCurrent = expectedItems.allSatisfy { expectedItem in
        guard let currentItem = currentItemsByID[expectedItem.id] else { return false }
        return expectedItem.hasSameMutationFingerprint(as: currentItem)
      }
      return allTargetsAreCurrent ? .valid : .changed
    } catch is CancellationError {
      return .cancelled
    } catch {
      Logger.error("Failed to validate transfer history before mutation: \(error)")
      return .unavailable("服务器记录有未知变化，请重试。")
    }
  }

  private func validationFailureMessage(
    for validation: TransferHistoryMutationValidation
  ) async -> String? {
    switch validation {
    case .valid, .cancelled:
      return nil
    case .changed:
      await performAuthoritativeRefresh()
      return "服务器记录有未知变化，请重试。"
    case .unavailable(let message):
      return message
    }
  }

  // MARK: - Polling Helpers

  func fetchLatest() async {
    guard apiService.canAccess(.manage), !isMutatingHistory else { return }
    let sessionSnapshot = apiService.sessionSnapshot()
    let pollGeneration = queryGeneration
    let pollFetcher = fetcher
    do {
      var allNewItems: [TransferHistory] = []
      var currentPage = 1
      let maxPagesToFetch = 5  // Safeguard to prevent infinite loops

      let firstPageResponse = try await pollFetcher(1)
      guard pollGeneration == queryGeneration,
        apiService.isSessionUnchanged(from: sessionSnapshot)
      else { return }
      var fetchedItems = firstPageResponse.list

      let existingIds = Set(items.map { $0.id }).union(deletedIds)

      while currentPage <= maxPagesToFetch {
        if fetchedItems.isEmpty {
          break
        }

        var foundExistingItem = false
        var newItemsOnThisPage: [TransferHistory] = []
        for item in fetchedItems {
          if existingIds.contains(item.id) {
            foundExistingItem = true
            break
          }
          newItemsOnThisPage.append(item)
        }

        allNewItems.append(contentsOf: newItemsOnThisPage)

        if foundExistingItem || fetchedItems.count < pageSize {
          break
        }

        currentPage += 1
        let nextPageResponse = try await pollFetcher(currentPage)
        guard pollGeneration == queryGeneration,
          apiService.isSessionUnchanged(from: sessionSnapshot)
        else { return }
        fetchedItems = nextPageResponse.list
      }

      if !allNewItems.isEmpty {
        guard pollGeneration == queryGeneration,
          apiService.isSessionUnchanged(from: sessionSnapshot)
        else { return }
        let knownIds = Set(prependedItems.map(\.id))
          .union(paginatorItems.map(\.id))
          .union(deletedIds)
        let acceptedItems = allNewItems.filter { !knownIds.contains($0.id) }
        if !acceptedItems.isEmpty {
          prependedItems.insert(contentsOf: acceptedItems, at: 0)
          rebuildItems()
          applyInsertionCursorShift(forInsertedCount: acceptedItems.count)
        }
      }
    } catch {
      print("[TransferHistoryDataManager] Polling failed: \(error.localizedDescription)")
    }
  }

  func removeItem(where predicate: (TransferHistory) -> Bool) {
    let ids = Set(items.filter(predicate).map(\.id))
    guard !ids.isEmpty else { return }
    deletedIds.formUnion(ids)
    prependedItems.removeAll(where: { ids.contains($0.id) })
    selectedIds.subtract(ids)
    rebuildItems()
    pendingDeletionShiftCount += ids.count
  }

  private func markDeleted(id: Int) {
    deletedIds.insert(id)
    prependedItems.removeAll(where: { $0.id == id })
    selectedIds.remove(id)
    rebuildItems()
  }

  private func resetDynamicState(clearDeletedIds: Bool) {
    prependedItems.removeAll()
    selectedIds.removeAll()
    isSelectionMode = false
    pendingInsertionShiftCount = 0
    pendingDeletionShiftCount = 0
    if clearDeletedIds {
      deletedIds.removeAll()
    }
    rebuildItems()
  }

  private func applyPendingDeletionCursorShiftBeforeLoadMore() {
    guard pendingDeletionShiftCount > 0 else { return }
    // 删除后列表前移：即使不足一页，也至少需要回退 1 页来补齐可能被跨页移动的条目。
    let rewindPages = Int(ceil(Double(pendingDeletionShiftCount) / Double(pageSize)))
    guard rewindPages > 0 else { return }
    paginator.rewindPageCursor(by: rewindPages)
    pendingDeletionShiftCount = 0
  }

  private func applyInsertionCursorShift(forInsertedCount count: Int) {
    guard count > 0 else { return }
    pendingInsertionShiftCount += count
    // 仅按整页推进，避免 1...pageSize-1 的新增导致跳页丢数据。
    let shiftPages = pendingInsertionShiftCount / pageSize
    guard shiftPages > 0 else { return }
    paginator.advancePageCursor(by: shiftPages)
    pendingInsertionShiftCount %= pageSize
  }

  private func rebuildItems() {
    // 常态快路径：无动态增量、无删除屏蔽时直接复用分页层。
    if prependedItems.isEmpty, deletedIds.isEmpty {
      items = paginatorItems
      syncSelectionToVisibleItems(items)
      return
    }

    // 仅有删除屏蔽时，走一次过滤即可。
    if prependedItems.isEmpty {
      let merged = paginatorItems.filter { !deletedIds.contains($0.id) }
      items = merged
      syncSelectionToVisibleItems(merged)
      return
    }

    var merged: [TransferHistory] = []
    merged.reserveCapacity(prependedItems.count + paginatorItems.count)

    if deletedIds.isEmpty {
      var seenIds = Set<Int>()
      seenIds.reserveCapacity(prependedItems.count)

      for item in prependedItems where seenIds.insert(item.id).inserted {
        merged.append(item)
      }

      for item in paginatorItems where seenIds.insert(item.id).inserted {
        merged.append(item)
      }
    } else {
      var seenIds = Set<Int>()
      seenIds.reserveCapacity(prependedItems.count + paginatorItems.count)

      for item in prependedItems {
        guard !deletedIds.contains(item.id), seenIds.insert(item.id).inserted else { continue }
        merged.append(item)
      }

      for item in paginatorItems {
        guard !deletedIds.contains(item.id), seenIds.insert(item.id).inserted else { continue }
        merged.append(item)
      }
    }

    items = merged
    syncSelectionToVisibleItems(merged)
  }

  private func syncSelectionToVisibleItems(_ visibleItems: [TransferHistory]) {
    // 无选择时直接返回，避免不必要的 Set 构建。
    guard !selectedIds.isEmpty else {
      if isSelectionMode {
        isSelectionMode = false
      }
      return
    }

    let visibleIds = Set(visibleItems.map(\.id))
    selectedIds.formIntersection(visibleIds)
    if selectedIds.isEmpty {
      isSelectionMode = false
    }
  }

  // MARK: - AI Reorganize

  func triggerAiRedo(
    for item: TransferHistory,
    sourceSession: APIServiceSessionSnapshot
  ) async {
    await triggerAiRedo(
      for: [item],
      useBatchEndpoint: false,
      sourceSession: sourceSession
    )
  }

  func triggerBatchAiRedo(
    for items: [TransferHistory],
    sourceSession: APIServiceSessionSnapshot
  ) async {
    await triggerAiRedo(
      for: items,
      useBatchEndpoint: true,
      sourceSession: sourceSession
    )
  }

  private func triggerAiRedo(
    for items: [TransferHistory],
    useBatchEndpoint: Bool,
    sourceSession: APIServiceSessionSnapshot
  ) async {
    errorMessage = nil
    mutationRetryMessage = nil
    guard apiService.isSessionUnchanged(from: sourceSession),
      apiService.canAccess(.manage)
    else { return }
    guard !isMutatingHistory else { return }
    var seenIds = Set<Int>()
    let pendingItems = items.filter {
      seenIds.insert($0.id).inserted && !aiRedoingIds.contains($0.id)
    }
    let pendingIds = pendingItems.map(\.id)
    guard !pendingIds.isEmpty else { return }
    guard isAiRedoEnabled else {
      errorMessage = "AI 助手未启用"
      return
    }

    isAiRedoing = true
    aiRedoProgressText = "正在确认整理记录..."
    let validation = await validateMutationTargets(
      pendingItems,
      sourceSession: sourceSession
    )
    guard validation == .valid else {
      mutationRetryMessage = await validationFailureMessage(for: validation)
      isAiRedoing = false
      return
    }
    for id in pendingIds {
      aiRedoingIds.insert(id)
    }
    aiRedoProgressText = "正在启动 AI 整理..."

    aiRedoTask?.cancel()
    aiRedoTask = Task { @MainActor in
      do {
        guard apiService.isSessionUnchanged(from: sourceSession) else {
          throw CancellationError()
        }
        let result: (progressKey: String, acceptedIds: [Int])
        if useBatchEndpoint {
          result = try await apiService.aiRedoTransferHistories(ids: pendingIds)
        } else {
          result = try await apiService.aiRedoTransferHistory(id: pendingIds[0])
        }
        guard apiService.isSessionUnchanged(from: sourceSession) else {
          throw CancellationError()
        }

        let acceptedIds = result.acceptedIds
        let rejectedIds = Set(pendingIds).subtracting(acceptedIds)
        for id in rejectedIds {
          self.aiRedoingIds.remove(id)
        }
        if useBatchEndpoint {
          self.selectedIds.subtract(acceptedIds)
          if self.selectedIds.isEmpty {
            self.isSelectionMode = false
          }
        }

        var terminalError: String?
        let stream = apiService.progressStream(progressKey: result.progressKey)
        for try await event in stream {
          if Task.isCancelled { break }
          if let text = event.text_i18n ?? event.text {
            self.aiRedoProgressText = text
          }
          if event.enable == false {
            if event.data?.success == false {
              terminalError =
                event.data?.error_i18n ?? event.data?.error ?? "AI 整理失败"
            }
            break
          }
          if event.type == "error" {
            terminalError = event.message_i18n ?? event.message ?? "AI 整理失败"
            break
          }
          if event.type == "done" {
            break
          }
        }
        guard apiService.isSessionUnchanged(from: sourceSession) else {
          throw CancellationError()
        }

        if !Task.isCancelled {
          for id in acceptedIds {
            self.aiRedoingIds.remove(id)
          }
          self.isAiRedoing = false
          await self.refresh()
          if let terminalError {
            self.errorMessage = terminalError
          }
        }
      } catch is CancellationError {
        for id in pendingIds {
          self.aiRedoingIds.remove(id)
        }
        self.isAiRedoing = !self.aiRedoingIds.isEmpty
        return
      } catch {
        if !Task.isCancelled {
          if case APIError.serverMessage(let message) = error {
            self.errorMessage = message
          } else {
            self.errorMessage = "AI 整理失败"
          }
          for id in pendingIds {
            self.aiRedoingIds.remove(id)
          }
          self.isAiRedoing = false
        }
      }
    }
  }
}
