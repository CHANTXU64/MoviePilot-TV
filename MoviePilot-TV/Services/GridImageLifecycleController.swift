import Combine
import SwiftUI

@MainActor
protocol GridImageDemandResource: AnyObject {
  func gridImageDemandPermissionDidChange()
}

/// 单张 Grid 图片所属的稳定列表位置。卡片节点通过环境把它传给 PageManagedImage。
struct GridImageDemandContext {
  let controller: GridImageLifecycleController
  let listID: UUID
  let itemID: MediaInfo.ID
  let itemIndex: Int
}

private struct GridImageDemandContextEnvironmentKey: EnvironmentKey {
  static let defaultValue: GridImageDemandContext? = nil
}

extension EnvironmentValues {
  var gridImageDemandContext: GridImageDemandContext? {
    get { self[GridImageDemandContextEnvironmentKey.self] }
    set { self[GridImageDemandContextEnvironmentKey.self] = newValue }
  }
}

/// Grid 图片窗口的唯一状态机。DOM 上界由 GridDOMRetentionController 独立管理。
@MainActor
final class GridImageLifecycleController: ObservableObject, PageImageStackObserver {
  enum Activation: Equatable {
    case disarmed
    case visibleTop
    case armed(itemID: MediaInfo.ID, itemIndex: Int)
  }

  private final class WeakResource {
    weak var value: (any GridImageDemandResource)?
    let listID: UUID
    let itemIndex: Int

    init(value: any GridImageDemandResource, listID: UUID, itemIndex: Int) {
      self.value = value
      self.listID = listID
      self.itemIndex = itemIndex
    }
  }

  private struct PermissionSnapshot {
    let listID: UUID
    let itemCount: Int
    let activation: Activation
  }

  private(set) var activation: Activation = .disarmed
  private(set) var listID: UUID

  private var itemIDs: [MediaInfo.ID]
  private let columnCount: Int
  private weak var imageLifecycle: PageImageLifecycle?
  private var resources: [ObjectIdentifier: WeakResource] = [:]
  private(set) var observedStackReleaseEpoch: UInt = 0
  private var isStackInteractive = false
  private var isStackForeground = false

  init(
    listID: UUID,
    itemIDs: [MediaInfo.ID],
    columnCount: Int,
    imageLifecycle: PageImageLifecycle
  ) {
    self.listID = listID
    self.itemIDs = itemIDs
    self.columnCount = columnCount
    self.imageLifecycle = imageLifecycle
    imageLifecycle.registerStackObserver(self)
  }

  isolated deinit {
    imageLifecycle?.unregisterStackObserver(self)
  }

  /// 同一 Paginator 的尾部追加保留窗口；新 listID 或非追加变化立即关闭旧窗口。
  func reconcile(listID newListID: UUID, itemIDs newItemIDs: [MediaInfo.ID]) {
    let previousPermissions = permissionSnapshot
    guard newListID == listID else {
      listID = newListID
      itemIDs = newItemIDs
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return
    }

    let appendedByPaginator = newItemIDs.count >= itemIDs.count
      && newItemIDs.prefix(itemIDs.count).elementsEqual(itemIDs)
    itemIDs = newItemIDs

    guard appendedByPaginator else {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return
    }

    if activation == .disarmed {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return
    }

    if case .armed(let itemID, let itemIndex) = activation,
      !isValid(itemID: itemID, itemIndex: itemIndex)
    {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return
    }
    notifyResources(changedFrom: previousPermissions)
  }

  /// 只有当前列表中真实存在的卡片焦点才能激活或推进图片窗口。
  @discardableResult
  func cardFocusChanged(
    listID eventListID: UUID,
    itemID: MediaInfo.ID,
    itemIndex: Int,
    isFocused: Bool
  ) -> Bool {
    guard eventListID == listID, isValid(itemID: itemID, itemIndex: itemIndex) else {
      return false
    }
    guard isFocused else { return true }
    guard isStackInteractive,
      isStackForeground,
      imageLifecycle?.phase == .active
    else { return false }

    let newActivation = Activation.armed(itemID: itemID, itemIndex: itemIndex)
    if activation != newActivation {
      let previousPermissions = permissionSnapshot
      setActivation(newActivation, changedFrom: previousPermissions)
    }
    return true
  }

  func allowsImages(listID resourceListID: UUID, itemIndex: Int) -> Bool {
    allowsImages(
      listID: resourceListID,
      itemIndex: itemIndex,
      snapshot: permissionSnapshot
    )
  }

  func register(
    _ resource: any GridImageDemandResource,
    listID resourceListID: UUID,
    itemIndex: Int
  ) {
    resources[ObjectIdentifier(resource)] = WeakResource(
      value: resource,
      listID: resourceListID,
      itemIndex: itemIndex
    )
    resource.gridImageDemandPermissionDidChange()
  }

  func unregister(_ resource: any GridImageDemandResource) {
    resources.removeValue(forKey: ObjectIdentifier(resource))
  }

  func pageImageStackStateDidChange(_ state: PageImageStackState) {
    let didRelease = state.releaseEpoch != observedStackReleaseEpoch
    observedStackReleaseEpoch = state.releaseEpoch
    isStackInteractive = state.isInteractive
    isStackForeground = state.isForeground

    if didRelease {
      disarm()
    } else {
      activateVisibleTopIfPossible()
    }
  }

  private func isValid(itemID: MediaInfo.ID, itemIndex: Int) -> Bool {
    itemIDs.indices.contains(itemIndex) && itemIDs[itemIndex] == itemID
  }

  private func disarm() {
    let previousPermissions = permissionSnapshot
    setActivation(.disarmed, changedFrom: previousPermissions)
  }

  private var restoredActivation: Activation {
    canShowVisibleTop ? .visibleTop : .disarmed
  }

  private var canShowVisibleTop: Bool {
    isStackInteractive && isStackForeground && !itemIDs.isEmpty
  }

  private func activateVisibleTopIfPossible() {
    guard activation == .disarmed, canShowVisibleTop else { return }
    let previousPermissions = permissionSnapshot
    setActivation(.visibleTop, changedFrom: previousPermissions)
  }

  private var permissionSnapshot: PermissionSnapshot {
    PermissionSnapshot(listID: listID, itemCount: itemIDs.count, activation: activation)
  }

  private func setActivation(
    _ newActivation: Activation,
    changedFrom previousPermissions: PermissionSnapshot
  ) {
    if activation != newActivation {
      activation = newActivation
    }
    notifyResources(changedFrom: previousPermissions)
  }

  private func notifyResources(changedFrom previousPermissions: PermissionSnapshot) {
    let currentPermissions = permissionSnapshot
    let deadIDs = resources.compactMap { id, resource in
      resource.value == nil ? id : nil
    }
    for id in deadIDs {
      resources.removeValue(forKey: id)
    }
    for resource in resources.values {
      let wasAllowed = allowsImages(
        listID: resource.listID,
        itemIndex: resource.itemIndex,
        snapshot: previousPermissions
      )
      let isAllowed = allowsImages(
        listID: resource.listID,
        itemIndex: resource.itemIndex,
        snapshot: currentPermissions
      )
      if wasAllowed != isAllowed {
        resource.value?.gridImageDemandPermissionDidChange()
      }
    }
  }

  private func allowsImages(
    listID resourceListID: UUID,
    itemIndex: Int,
    snapshot: PermissionSnapshot
  ) -> Bool {
    guard resourceListID == snapshot.listID,
      snapshot.itemCount > 0,
      (0..<snapshot.itemCount).contains(itemIndex)
    else { return false }

    switch snapshot.activation {
    case .disarmed:
      return false
    case .visibleTop:
      return itemIndex < min(
        snapshot.itemCount,
        ImageLoadWindow.gridPinnedTopRowCount * columnCount
      )
    case .armed(_, let anchorIndex):
      return ImageLoadWindow.containsGridItem(
        at: itemIndex,
        itemCount: snapshot.itemCount,
        anchorIndex: anchorIndex,
        columnCount: columnCount
      )
    }
  }
}
