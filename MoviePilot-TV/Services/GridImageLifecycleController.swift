import Combine
import SwiftUI

@MainActor
protocol GridImageDemandResource: AnyObject {
  func gridImageDemandPermissionDidChange()
}

/// 单张 Grid 图片所属的稳定列表位置。卡片节点通过环境把它传给 PageManagedImage。
struct GridImageDemandContext {
  let controller: GridImageLifecycleController
  let listIdentity: GridListIdentity
  let itemIDs: [MediaInfo.ID]?
  let itemID: MediaInfo.ID
  let itemIndex: Int

  init(
    controller: GridImageLifecycleController,
    listIdentity: GridListIdentity,
    itemIDs: [MediaInfo.ID]? = nil,
    itemID: MediaInfo.ID,
    itemIndex: Int
  ) {
    self.controller = controller
    self.listIdentity = listIdentity
    self.itemIDs = itemIDs
    self.itemID = itemID
    self.itemIndex = itemIndex
  }
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
    let listIdentity: GridListIdentity
    let itemIndex: Int

    init(
      value: any GridImageDemandResource,
      listIdentity: GridListIdentity,
      itemIndex: Int
    ) {
      self.value = value
      self.listIdentity = listIdentity
      self.itemIndex = itemIndex
    }
  }

  private struct PermissionSnapshot {
    let listIdentity: GridListIdentity
    let itemCount: Int
    let activation: Activation
  }

  private(set) var activation: Activation = .disarmed
  private(set) var listIdentity: GridListIdentity
  var listID: UUID { listIdentity.id }

  private var itemIDs: [MediaInfo.ID]
  private let columnCount: Int
  private weak var imageLifecycle: PageImageLifecycle?
  private var resources: [ObjectIdentifier: WeakResource] = [:]
  private(set) var observedStackReleaseEpoch: UInt = 0
  private var isStackInteractive = false
  private var isStackForeground = false

  init(
    listIdentity: GridListIdentity,
    itemIDs: [MediaInfo.ID],
    columnCount: Int,
    imageLifecycle: PageImageLifecycle
  ) {
    self.listIdentity = listIdentity
    self.itemIDs = itemIDs
    self.columnCount = columnCount
    self.imageLifecycle = imageLifecycle
    imageLifecycle.registerStackObserver(self)
  }

  isolated deinit {
    imageLifecycle?.unregisterStackObserver(self)
  }

  /// 同一 Paginator 的尾部追加保留窗口；新 listID 或非追加变化立即关闭旧窗口。
  @discardableResult
  func reconcile(
    listIdentity newIdentity: GridListIdentity,
    itemIDs newItemIDs: [MediaInfo.ID]
  ) -> Bool {
    let previousPermissions = permissionSnapshot
    guard newIdentity.generation >= listIdentity.generation else { return false }
    guard newIdentity.generation != listIdentity.generation || newIdentity.id == listIdentity.id
    else { return false }
    guard newIdentity == listIdentity else {
      listIdentity = newIdentity
      itemIDs = newItemIDs
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return true
    }

    let appendedByPaginator = isPaginatorAppend(newItemIDs)
    itemIDs = newItemIDs

    guard appendedByPaginator else {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return true
    }

    if activation == .disarmed {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return true
    }

    if case .armed(let itemID, let itemIndex) = activation,
      !isValid(itemID: itemID, itemIndex: itemIndex)
    {
      setActivation(restoredActivation, changedFrom: previousPermissions)
      return true
    }
    notifyResources(changedFrom: previousPermissions)
    return true
  }

  /// 卡片/Slot 的快照不是权威数据源：只允许更高内容代际，或同代际严格尾部追加。
  /// refresh 会先推进 generation，因此 refresh 前的旧卡片不能把清空后的列表重新写回。
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

  /// 只有当前列表中真实存在的卡片焦点才能激活或推进图片窗口。
  @discardableResult
  func cardFocusChanged(
    listIdentity eventIdentity: GridListIdentity,
    itemID: MediaInfo.ID,
    itemIndex: Int,
    isFocused: Bool
  ) -> Bool {
    guard eventIdentity == listIdentity, isValid(itemID: itemID, itemIndex: itemIndex) else {
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

  func allowsImages(listIdentity resourceIdentity: GridListIdentity, itemIndex: Int) -> Bool {
    allowsImages(
      listIdentity: resourceIdentity,
      itemIndex: itemIndex,
      snapshot: permissionSnapshot
    )
  }

  func register(
    _ resource: any GridImageDemandResource,
    listIdentity resourceIdentity: GridListIdentity,
    itemIndex: Int
  ) {
    resources[ObjectIdentifier(resource)] = WeakResource(
      value: resource,
      listIdentity: resourceIdentity,
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

  private func isPaginatorAppend(_ newItemIDs: [MediaInfo.ID]) -> Bool {
    newItemIDs.count >= itemIDs.count
      && newItemIDs.prefix(itemIDs.count).elementsEqual(itemIDs)
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
    PermissionSnapshot(
      listIdentity: listIdentity,
      itemCount: itemIDs.count,
      activation: activation
    )
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
        listIdentity: resource.listIdentity,
        itemIndex: resource.itemIndex,
        snapshot: previousPermissions
      )
      let isAllowed = allowsImages(
        listIdentity: resource.listIdentity,
        itemIndex: resource.itemIndex,
        snapshot: currentPermissions
      )
      if wasAllowed != isAllowed {
        resource.value?.gridImageDemandPermissionDidChange()
      }
    }
  }

  private func allowsImages(
    listIdentity resourceIdentity: GridListIdentity,
    itemIndex: Int,
    snapshot: PermissionSnapshot
  ) -> Bool {
    guard resourceIdentity == snapshot.listIdentity,
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
