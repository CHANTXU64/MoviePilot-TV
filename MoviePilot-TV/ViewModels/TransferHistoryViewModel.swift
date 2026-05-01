import Combine
import Foundation

@MainActor
class TransferHistoryViewModel: ObservableObject {
  // MARK: - Published Properties

  @Published var items: [TransferHistory] = []
  @Published var isFirstLoading: Bool = false
  @Published var isLoadingMore: Bool = false
  @Published var errorMessage: String?  // TODO
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

  // MARK: - Private State

  private var paginator: Paginator<TransferHistory>!
  private var fetcher: (Int) async throws -> TransferHistoryResponse
  private var cancellables = Set<AnyCancellable>()
  private let apiService = APIService.shared
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

  init() {
    // 使用局部变量 api 避免在初始化 dataManager 时捕获 self
    let pageSize = self.pageSize
    let api = APIService.shared
    self.fetcher = { page in
      try await api.fetchTransferHistory(
        page: page,
        count: pageSize,
        title: nil)
    }
    configurePaginator()
  }

  private func configurePaginator() {
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
    searchText = text
    let api = APIService.shared
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

  func refresh() async {
    errorMessage = nil
    isLoadingMore = false
    isFirstLoading = true
    defer {
      isFirstLoading = false
    }

    resetDynamicState(clearDeletedIds: true)
    await loadStorages()
    await paginator.refresh()
  }

  private func loadStorages() async {
    do {
      let storages = try await apiService.fetchStorages()
      var dict = [String: String]()
      for storage in storages {
        dict[storage.type] = storage.name
      }
      storageDict = dict
    } catch {
      print("[TransferHistoryViewModel] Failed to load storages: \(error.localizedDescription)")
    }
  }

  func loadMore(currentItemId: TransferHistory.ID) async {
    errorMessage = nil
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

  func deleteHistory(item: TransferHistory, deleteSource: Bool, deleteDest: Bool) async {
    errorMessage = nil
    do {
      let success = try await apiService.deleteTransferHistory(
        item: item,
        deleteSource: deleteSource,
        deleteDest: deleteDest)

      if success {
        markDeleted(id: item.id)
        pendingDeletionShiftCount += 1
      } else {
        let errorDescription = "删除失败 (id: \(item.id))，请检查后端日志。"
        print(errorDescription)
        errorMessage = errorDescription
      }
    } catch {
      handle(error: error)
    }
  }

  func toggleSelection(id: Int) {
    if selectedIds.contains(id) {
      selectedIds.remove(id)
    } else {
      selectedIds.insert(id)
    }
  }

  func selectAll() {
    selectedIds = Set(items.map { $0.id })
  }

  func deselectAll() {
    selectedIds.removeAll()
  }

  func deleteSelected(deleteSource: Bool, deleteDest: Bool) async {
    errorMessage = nil
    let idsToDelete = Array(selectedIds)
    var deletedCount = 0

    for id in idsToDelete {
      if let item = items.first(where: { $0.id == id }) {
        do {
          let success = try await apiService.deleteTransferHistory(
            item: item,
            deleteSource: deleteSource,
            deleteDest: deleteDest)

          if success {
            markDeleted(id: id)
            deletedCount += 1
          }
        } catch {
          print("Failed to delete history item \(id): \(error.localizedDescription)")
        }
      } else {
        selectedIds.remove(id)
      }
    }

    if deletedCount == 0 && !idsToDelete.isEmpty {
      errorMessage = "批量删除失败，请检查后端日志。"
    }

    pendingDeletionShiftCount += deletedCount

    if selectedIds.isEmpty {
      isSelectionMode = false
    }
  }

  // MARK: - Polling Helpers

  func fetchLatest() async {
    do {
      var allNewItems: [TransferHistory] = []
      var currentPage = 1
      let maxPagesToFetch = 5  // Safeguard to prevent infinite loops

      let firstPageResponse = try await fetcher(1)
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
        let nextPageResponse = try await fetcher(currentPage)
        fetchedItems = nextPageResponse.list
      }

      if !allNewItems.isEmpty {
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

  func triggerAiRedo(for ids: [Int]) async {
    let pendingIds = ids.filter { !aiRedoingIds.contains($0) }
    guard !pendingIds.isEmpty else { return }
    guard isAiRedoEnabled else {
      errorMessage = "AI 助手未启用"
      return
    }

    for id in pendingIds {
      aiRedoingIds.insert(id)
    }
    isAiRedoing = true
    aiRedoProgressText = "正在启动 AI 整理..."

    aiRedoTask?.cancel()
    aiRedoTask = Task { @MainActor in
      do {
        if let result = try await apiService.aiRedoTransferHistory(ids: pendingIds) {
          let acceptedIds = result.acceptedIds
          let rejectedIds = Set(pendingIds).subtracting(acceptedIds)
          for id in rejectedIds {
             self.aiRedoingIds.remove(id)
          }

          let stream = apiService.progressStream(progressKey: result.progressKey)
          for try await event in stream {
            if Task.isCancelled { break }
            if let text = event.text {
              self.aiRedoProgressText = text
            }
            if let enable = event.enable, !enable {
              if let success = event.data?.success, !success {
                print("AI整理失败: \(event.data?.error ?? "未知错误")")
              } else {
                print("AI整理成功")
              }
              break
            }
            if event.type == "done" || event.type == "error" {
              break
            }
          }

          if !Task.isCancelled {
            for id in acceptedIds {
              self.aiRedoingIds.remove(id)
            }
            self.isAiRedoing = false
            await self.refresh()
          }
        } else {
          for id in pendingIds {
            self.aiRedoingIds.remove(id)
          }
          self.isAiRedoing = false
        }
      } catch {
        print("AI Redo failed: \(error)")
        if !Task.isCancelled {
          for id in pendingIds {
            self.aiRedoingIds.remove(id)
          }
          self.isAiRedoing = false
        }
      }
    }
  }
}
