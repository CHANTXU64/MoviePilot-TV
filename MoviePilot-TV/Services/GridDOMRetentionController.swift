import Combine
import SwiftUI

/// 海报墙卡片节点的尾部保留策略。图片是否解码由 `ImageLoadWindow` 独立决定。
@MainActor
final class GridDOMRetentionController: ObservableObject {
  private enum PendingTrim: Equatable {
    case focused(itemID: MediaInfo.ID, limit: Int)
    case returnedToTop(limit: Int)
  }

  @Published private(set) var retainedItemLimit: Int

  private(set) var listIdentity: GridListIdentity
  var listID: UUID { listIdentity.id }
  private let columnCount: Int
  private let rowsAfterFocusedRow: Int
  private let initialRowCount: Int
  private let stabilizationDelay: Duration

  private var itemIDs: [MediaInfo.ID]
  private var focusedItemID: MediaInfo.ID?
  private var pendingTrim: PendingTrim?
  private var trimTask: Task<Void, Never>?
  private var generation: UInt = 0
  private var scrollPhase: ScrollPhase = .idle
  private var adjustedOffsetY: CGFloat?
  private var observedEligibleScrollMovement = false
  private var ownsCurrentScrollSession = false
  private var preservesLimitForRestoredFocus = false
  private var isStackInteractive = false
  private var isViewActive = false

  init(
    listIdentity: GridListIdentity,
    itemIDs: [MediaInfo.ID],
    columnCount: Int,
    rowsAfterFocusedRow: Int = 3,
    stabilizationDelay: Duration = .milliseconds(300)
  ) {
    precondition(columnCount > 0)
    precondition(rowsAfterFocusedRow >= 0)
    self.listIdentity = listIdentity
    self.itemIDs = itemIDs
    self.columnCount = columnCount
    self.rowsAfterFocusedRow = rowsAfterFocusedRow
    self.initialRowCount = rowsAfterFocusedRow + 1
    self.stabilizationDelay = stabilizationDelay
    self.retainedItemLimit = (rowsAfterFocusedRow + 1) * columnCount
  }

  deinit {
    trimTask?.cancel()
  }

  func retainedItemCount(for itemCount: Int) -> Int {
    min(itemCount, retainedItemLimit)
  }

  /// View 首帧已拿到新 Paginator、控制器尚未来得及 reconcile 时，也只创建新列表顶部窗口。
  func retainedItemCount(
    for itemCount: Int,
    listIdentity requestedIdentity: GridListIdentity
  ) -> Int {
    min(itemCount, requestedIdentity == listIdentity ? retainedItemLimit : initialLimit)
  }

  /// Paginator 只在原数组尾部追加时保留当前上界；换源、重排或截断都视为新列表。
  @discardableResult
  func reconcile(
    listIdentity newIdentity: GridListIdentity,
    itemIDs newItemIDs: [MediaInfo.ID]
  ) -> Bool {
    guard newIdentity.generation >= listIdentity.generation else { return false }
    guard newIdentity.generation != listIdentity.generation || newIdentity.id == listIdentity.id
    else { return false }
    guard newIdentity != listIdentity || newItemIDs != itemIDs else { return true }

    let appendedByPaginator = newIdentity == listIdentity && isPaginatorAppend(newItemIDs)
    listIdentity = newIdentity
    itemIDs = newItemIDs

    guard !appendedByPaginator else { return true }

    invalidatePendingTrim()
    focusedItemID = nil
    adjustedOffsetY = nil
    observedEligibleScrollMovement = false
    ownsCurrentScrollSession = false
    preservesLimitForRestoredFocus = false
    setRetainedItemLimit(initialLimit)
    return true
  }

  /// 卡片/Slot 只可用更高内容代际接管控制器，或补充同代际的尾部追加。
  /// 同代际的截断、重排和等长替换只能由 View 的权威 onChange 写入。
  @discardableResult
  func reconcileEventSnapshot(
    listIdentity newIdentity: GridListIdentity,
    itemIDs newItemIDs: [MediaInfo.ID]
  ) -> Bool {
    guard newIdentity != listIdentity || newItemIDs != itemIDs else { return true }
    if newIdentity == listIdentity, !isPaginatorAppend(newItemIDs) {
      return false
    }
    return reconcile(listIdentity: newIdentity, itemIDs: newItemIDs)
  }

  func setViewActive(_ isActive: Bool) {
    guard isViewActive != isActive else { return }
    isViewActive = isActive
    if !isActive {
      ownsCurrentScrollSession = false
      preservesLimitForRestoredFocus = true
      if case .returnedToTop = pendingTrim {
        schedulePendingTrimIfPossible()
      } else {
        invalidatePendingTrim()
        observedEligibleScrollMovement = false
      }
    } else if case .returnedToTop = pendingTrim {
      schedulePendingTrimIfPossible()
    }
  }

  /// Tab 失活会立即取消裁剪，但不会改变已经创建的节点上界。
  func setStackInteractive(_ isInteractive: Bool) {
    guard isStackInteractive != isInteractive else { return }
    isStackInteractive = isInteractive
    if !isInteractive {
      ownsCurrentScrollSession = false
      preservesLimitForRestoredFocus = true
      if case .returnedToTop = pendingTrim {
        schedulePendingTrimIfPossible()
      } else {
        invalidatePendingTrim()
        observedEligibleScrollMovement = false
      }
    } else if case .returnedToTop = pendingTrim {
      schedulePendingTrimIfPossible()
    }
  }

  @discardableResult
  func cardFocusChanged(
    listIdentity eventIdentity: GridListIdentity,
    itemID: MediaInfo.ID,
    itemIndex: Int? = nil,
    isFocused: Bool
  ) -> Bool {
    guard eventIdentity == listIdentity,
      let index = itemIndex ?? itemIDs.firstIndex(of: itemID),
      itemIDs.indices.contains(index),
      itemIDs[index] == itemID
    else {
      return false
    }

    if isFocused {
      cardFocused(itemID, itemIndex: index)
    } else {
      cardFocusEnded(itemID)
    }
    return true
  }

  func scrollPositionChanged(adjustedOffsetY newOffsetY: CGFloat) {
    let previousOffsetY = adjustedOffsetY
    if ownsCurrentScrollSession,
      let previousOffsetY,
      abs(newOffsetY - previousOffsetY) > 0.5
    {
      observedEligibleScrollMovement = true
    }

    // tvOS Focus Engine 把焦点交回 Tab 栏时，可能只报告几何位置直接回到顶部，
    // 不一定产生新的 scrolling/animating phase。只接受当前活跃页面内从非顶部
    // 跨到顶部的变化；Tab/详情恢复期间由 preservesLimitForRestoredFocus 拦截。
    if canTrim,
      !preservesLimitForRestoredFocus,
      let previousOffsetY,
      previousOffsetY > 1,
      newOffsetY <= 1
    {
      observedEligibleScrollMovement = true
    }
    adjustedOffsetY = newOffsetY

    if isAtTop {
      prepareReturnedToTopTrimIfNeeded()
    } else if case .returnedToTop = pendingTrim {
      invalidatePendingTrim()
    }
  }

  func scrollPhaseChanged(_ newPhase: ScrollPhase) {
    guard scrollPhase != newPhase else { return }
    let wasScrolling = scrollPhase.isScrolling
    scrollPhase = newPhase

    if newPhase.isScrolling {
      if case .focused = pendingTrim {
        cancelTrimTask()
      }
      if !wasScrolling {
        ownsCurrentScrollSession = canTrim
      }
      if ownsCurrentScrollSession {
        observedEligibleScrollMovement = true
      }
    } else if newPhase == .idle {
      if isAtTop {
        prepareReturnedToTopTrimIfNeeded()
      } else {
        schedulePendingTrimIfPossible()
      }
      ownsCurrentScrollSession = false
    }
  }

  private var initialLimit: Int {
    initialRowCount * columnCount
  }

  private func isPaginatorAppend(_ newItemIDs: [MediaInfo.ID]) -> Bool {
    newItemIDs.count >= itemIDs.count
      && newItemIDs.prefix(itemIDs.count).elementsEqual(itemIDs)
  }

  private var canTrim: Bool {
    isViewActive && isStackInteractive
  }

  private var isAtTop: Bool {
    guard let adjustedOffsetY else { return false }
    return adjustedOffsetY <= 1
  }

  private func itemLimit(for index: Int) -> Int {
    let focusedRow = index / columnCount
    return (focusedRow + rowsAfterFocusedRow + 1) * columnCount
  }

  private func cardFocused(_ itemID: MediaInfo.ID, itemIndex index: Int) {
    let targetLimit = itemLimit(for: index)
    if targetLimit > retainedItemLimit {
      // 扩张只会补节点，必须独立于 Tab/转场锁立即执行，避免焦点走到 DOM 尾部后无路可走。
      setRetainedItemLimit(targetLimit)
    }

    guard canTrim else { return }

    invalidatePendingTrim()
    focusedItemID = itemID
    let shouldPreserveCurrentLimit = preservesLimitForRestoredFocus
    preservesLimitForRestoredFocus = false

    if targetLimit < retainedItemLimit && !shouldPreserveCurrentLimit {
      pendingTrim = .focused(itemID: itemID, limit: targetLimit)
      schedulePendingTrimIfPossible()
    }
  }

  private func cardFocusEnded(_ itemID: MediaInfo.ID) {
    guard focusedItemID == itemID else { return }
    focusedItemID = nil
    invalidatePendingTrim()

    // 返回键把焦点交给 Tab 栏时，最终裁剪由到顶几何和稳定延迟共同确认。
    if isAtTop {
      prepareReturnedToTopTrimIfNeeded()
    }
  }

  private func prepareReturnedToTopTrimIfNeeded() {
    guard canTrim, observedEligibleScrollMovement, isAtTop else { return }
    if let focusedItemID,
      let focusedIndex = itemIDs.firstIndex(of: focusedItemID),
      focusedIndex >= columnCount
    {
      return
    }

    let request = PendingTrim.returnedToTop(limit: initialLimit)
    if pendingTrim != request {
      invalidatePendingTrim()
      pendingTrim = request
    }
    schedulePendingTrimIfPossible()
  }

  private func schedulePendingTrimIfPossible() {
    guard let pendingTrim, trimTask == nil else { return }
    switch pendingTrim {
    case .focused:
      guard canTrim, scrollPhase == .idle else { return }
    case .returnedToTop:
      break
    }
    let scheduledGeneration = generation
    let delay = stabilizationDelay

    trimTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      self.trimTask = nil
      guard self.generation == scheduledGeneration else { return }
      self.commitPendingTrimIfValid()
    }
  }

  private func commitPendingTrimIfValid() {
    guard let pendingTrim else { return }

    switch pendingTrim {
    case .focused(let itemID, let limit):
      guard canTrim, scrollPhase == .idle else { return }
      guard focusedItemID == itemID, itemIDs.firstIndex(of: itemID) != nil else { return }
      setRetainedItemLimit(limit)

    case .returnedToTop(let limit):
      guard observedEligibleScrollMovement, isAtTop else { return }
      if let focusedItemID,
        let focusedIndex = itemIDs.firstIndex(of: focusedItemID),
        focusedIndex >= columnCount
      {
        return
      }
      setRetainedItemLimit(limit)
      observedEligibleScrollMovement = false
      ownsCurrentScrollSession = false
    }

    self.pendingTrim = nil
  }

  private func invalidatePendingTrim() {
    generation &+= 1
    pendingTrim = nil
    cancelTrimTask()
  }

  private func cancelTrimTask() {
    trimTask?.cancel()
    trimTask = nil
  }

  private func setRetainedItemLimit(_ newLimit: Int) {
    guard retainedItemLimit != newLimit else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      retainedItemLimit = newLimit
    }
  }
}
