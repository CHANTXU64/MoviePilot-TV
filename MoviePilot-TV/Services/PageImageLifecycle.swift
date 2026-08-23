import Combine
import SwiftUI

enum PageImagePhase: Equatable {
  case active
  case adjacent
  case released
}

/// 页面图片的实际渲染资源。生命周期直接驱动 surface，不依赖隐藏的 SwiftUI 页面重算 body。
@MainActor
protocol PageImageResource: AnyObject {
  var hasLoadedPageImage: Bool { get }
  func setPageImagePermissions(contentAllowed: Bool, activePageAllowed: Bool)
}

/// NavigationStack 的图片展示状态；普通导航深度只改变 PageImagePhase，不改变该状态。
struct PageImageStackState: Equatable {
  let isInteractive: Bool
  let isForeground: Bool
  let releaseEpoch: UInt
}

@MainActor
protocol PageImageStackObserver: AnyObject {
  func pageImageStackStateDidChange(_ state: PageImageStackState)
}

private final class WeakPageImageStackObserver {
  weak var value: (any PageImageStackObserver)?

  init(_ value: any PageImageStackObserver) {
    self.value = value
  }
}

/// 一个可导航页面唯一的图片生命周期。页面只读取保留策略，不自行判断 Push 或 Pop。
@MainActor
final class PageImageLifecycle: ObservableObject {
  let id: UUID

  @Published private(set) var phase: PageImagePhase
  @Published private(set) var isStackForeground = false
  @Published private(set) var isRemoved = false
  @Published private(set) var stackReleaseEpoch: UInt = 0
  private(set) var isStackInteractive = false
  /// 页面强持有图片 slot 的请求描述；UIView 可以销毁，slot 仍能在 adjacent 时预热。
  private var imageResources: [String: any PageImageResource] = [:]
  private var stackObservers: [ObjectIdentifier: WeakPageImageStackObserver] = [:]

  init(id: UUID = UUID(), phase: PageImagePhase = .active) {
    self.id = id
    self.phase = phase
  }

  /// 海报墙和横向行在当前页、直接父页保留。
  var keepsContentImages: Bool {
    isStackForeground && phase != .released
  }

  /// 背景、人物头图和加载海报只在当前页保留。
  var keepsActivePageImages: Bool {
    isStackForeground && phase == .active
  }

  /// 只读调试快照：当前仍强持有解码图的注册 surface 数量。
  var loadedImageResourceCount: Int {
    imageResources.values.reduce(into: 0) { count, resource in
      if resource.hasLoadedPageImage {
        count += 1
      }
    }
  }

  var retainedImageResourceCount: Int {
    imageResources.count
  }

  func register(_ resource: any PageImageResource) {
    imageResources["object:\(ObjectIdentifier(resource))"] = resource
    resource.setPageImagePermissions(
      contentAllowed: keepsContentImages,
      activePageAllowed: keepsActivePageImages
    )
  }

  func unregister(_ resource: any PageImageResource) {
    imageResources.removeValue(forKey: "object:\(ObjectIdentifier(resource))")
  }

  func registerStackObserver(_ observer: any PageImageStackObserver) {
    stackObservers[ObjectIdentifier(observer)] = WeakPageImageStackObserver(observer)
    observer.pageImageStackStateDidChange(stackState)
  }

  func unregisterStackObserver(_ observer: any PageImageStackObserver) {
    stackObservers.removeValue(forKey: ObjectIdentifier(observer))
  }

  func retainedImageResource<Resource: PageImageResource>(
    for key: String,
    create: () -> Resource
  ) -> Resource {
    if let resource = imageResources[key] as? Resource {
      return resource
    }
    let resource = create()
    imageResources[key] = resource
    resource.setPageImagePermissions(
      contentAllowed: keepsContentImages,
      activePageAllowed: keepsActivePageImages
    )
    return resource
  }

  func discardRetainedImageResource(
    for key: String,
    matching resource: any PageImageResource
  ) {
    guard let retained = imageResources[key], retained === resource else { return }
    imageResources.removeValue(forKey: key)
  }

  fileprivate func update(
    phase: PageImagePhase,
    isStackForeground: Bool,
    isStackInteractive: Bool
  ) {
    let previousContentPermission = keepsContentImages
    let previousActivePermission = keepsActivePageImages
    let previousStackState = stackState
    let wasStackForeground = self.isStackForeground
    if self.phase != phase {
      self.phase = phase
    }
    if self.isStackForeground != isStackForeground {
      self.isStackForeground = isStackForeground
    }
    self.isStackInteractive = isStackInteractive
    if wasStackForeground, !isStackForeground {
      stackReleaseEpoch &+= 1
    }
    let newStackState = stackState
    if previousStackState != newStackState {
      notifyStackObservers(newStackState)
    }
    if previousContentPermission != keepsContentImages
      || previousActivePermission != keepsActivePageImages
    {
      updateImageResources()
    }
  }

  /// removed 是终态；保留移除前的挂载状态，避免 tvOS Pop 转场中的源画面突然变空。
  fileprivate func markRemoved() {
    guard !isRemoved else { return }
    isRemoved = true
  }

  /// Pop 动画结束后的终态。即使 SwiftUI 继续持有旧 destination，也会同步清空其图片 surface。
  fileprivate func finishRemoval() {
    update(phase: .released, isStackForeground: false, isStackInteractive: false)
    imageResources.removeAll()
  }

  private var stackState: PageImageStackState {
    PageImageStackState(
      isInteractive: isStackInteractive,
      isForeground: isStackForeground,
      releaseEpoch: stackReleaseEpoch
    )
  }

  private func updateImageResources() {
    let contentAllowed = keepsContentImages
    let activePageAllowed = keepsActivePageImages
    for resource in imageResources.values {
      resource.setPageImagePermissions(
        contentAllowed: contentAllowed,
        activePageAllowed: activePageAllowed
      )
    }
  }

  private func notifyStackObservers(_ state: PageImageStackState) {
    let deadIDs = stackObservers.compactMap { id, observer in
      observer.value == nil ? id : nil
    }
    for id in deadIDs {
      stackObservers.removeValue(forKey: id)
    }
    for observer in stackObservers.values {
      observer.value?.pageImageStackStateDidChange(state)
    }
  }
}

private struct PageImageLifecycleEnvironmentKey: EnvironmentKey {
  static let defaultValue: PageImageLifecycle? = nil
}

extension EnvironmentValues {
  var pageImageLifecycle: PageImageLifecycle? {
    get { self[PageImageLifecycleEnvironmentKey.self] }
    set { self[PageImageLifecycleEnvironmentKey.self] = newValue }
  }
}

enum ImageNavigationRoute: Hashable {
  case media(MediaInfo)
  case person(Person)
  case resourceSearch(ResourceSearchRequest)
  case subscribeSeason(SubscribeSeasonRequest)
}

struct ImageNavigationEntry: Identifiable, Hashable {
  let id: UUID
  let route: ImageNavigationRoute

  init(id: UUID = UUID(), route: ImageNavigationRoute) {
    self.id = id
    self.route = route
  }
}

struct ImageNavigationSourceToken: Equatable {
  fileprivate let stackID: UUID
  fileprivate let revision: UInt
  fileprivate let topEntryID: UUID?
}

/// 一个 NavigationStack 对应一个协调器。它同时拥有 typed route 和页面图片生命周期。
@MainActor
final class ImageNavigationCoordinator: ObservableObject {
  let id = UUID()
  let rootLifecycle = PageImageLifecycle()

  @Published var path = NavigationPath() {
    didSet {
      reconcilePathMutation()
    }
  }

  private var entries: [ImageNavigationEntry] = []
  private var lifecycles: [UUID: PageImageLifecycle] = [:]
  private var preloadTasks: [UUID: MediaPreloadTask] = [:]
  private var removedLifecycleCleanupTasks: [UUID: Task<Void, Never>] = [:]
  private var stackForegroundReleaseTask: Task<Void, Never>?
  private var isStackForeground = false
  @Published private(set) var isStackInteractive = false
  private var navigationRevision: UInt = 0
  private let mediaPreloader: MediaPreloader
  private let removedLifecycleRetention: Duration
  private let tabTransitionImageRetention: Duration
  private var cancellables = Set<AnyCancellable>()

  init(
    mediaPreloader: MediaPreloader = .shared,
    removedLifecycleRetention: Duration = PresentationTransitionRetention.duration,
    tabTransitionImageRetention: Duration = PresentationTransitionRetention.duration
  ) {
    self.mediaPreloader = mediaPreloader
    self.removedLifecycleRetention = removedLifecycleRetention
    self.tabTransitionImageRetention = tabTransitionImageRetention
    rootLifecycle.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  /// 测试及非 Tab 容器使用的立即切换入口。
  func setStackForeground(_ isForeground: Bool) {
    cancelStackForegroundRelease()
    updateStackInteraction(isForeground)
    applyStackForeground(isForeground)
  }

  /// Tab 切换先立即关闭导航交互，再等系统转场结束后释放图片；退后台则立即释放。
  func setStackPresentation(isSelected: Bool, scenePhase: ScenePhase) {
    let shouldBeInteractive = isSelected && scenePhase == .active
    updateStackInteraction(shouldBeInteractive)

    if shouldBeInteractive {
      cancelStackForegroundRelease()
      applyStackForeground(true)
    } else if scenePhase == .active {
      scheduleStackForegroundRelease()
    } else {
      cancelStackForegroundRelease()
      applyStackForeground(false)
    }
  }

  private func updateStackInteraction(_ isInteractive: Bool) {
    guard isStackInteractive != isInteractive else { return }
    isStackInteractive = isInteractive
    navigationRevision &+= 1
    reconcileLifecycles()
  }

  private func applyStackForeground(_ isForeground: Bool) {
    guard isStackForeground != isForeground else { return }
    isStackForeground = isForeground
    if !isForeground {
      finishRemovedLifecyclesImmediately()
    }
    reconcileLifecycles()
  }

  private func scheduleStackForegroundRelease() {
    guard isStackForeground, stackForegroundReleaseTask == nil else { return }
    let retention = tabTransitionImageRetention
    stackForegroundReleaseTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: retention)
      guard !Task.isCancelled, let self, !self.isStackInteractive else { return }
      self.stackForegroundReleaseTask = nil
      self.applyStackForeground(false)
    }
  }

  private func cancelStackForegroundRelease() {
    stackForegroundReleaseTask?.cancel()
    stackForegroundReleaseTask = nil
  }

  func sourceToken() -> ImageNavigationSourceToken {
    ImageNavigationSourceToken(
      stackID: id,
      revision: navigationRevision,
      topEntryID: entries.last?.id
    )
  }

  @discardableResult
  func push(_ media: MediaInfo) -> ImageNavigationEntry {
    push(.media(media))
  }

  @discardableResult
  func push(
    _ media: MediaInfo,
    ifCurrent source: ImageNavigationSourceToken
  ) -> ImageNavigationEntry? {
    guard isCurrent(source) else { return nil }
    return push(media)
  }

  @discardableResult
  func push(_ person: Person) -> ImageNavigationEntry {
    push(.person(person))
  }

  @discardableResult
  func push(_ request: ResourceSearchRequest) -> ImageNavigationEntry {
    push(.resourceSearch(request))
  }

  @discardableResult
  func push(
    _ request: ResourceSearchRequest,
    ifCurrent source: ImageNavigationSourceToken
  ) -> ImageNavigationEntry? {
    guard isCurrent(source) else { return nil }
    return push(request)
  }

  @discardableResult
  func push(_ request: SubscribeSeasonRequest) -> ImageNavigationEntry {
    push(.subscribeSeason(request))
  }

  func lifecycle(for entry: ImageNavigationEntry) -> PageImageLifecycle {
    if let lifecycle = lifecycles[entry.id] {
      return lifecycle
    }

    // SwiftUI 在 Pop 转场中可能再次求值已移除的 destination。
    let lifecycle = PageImageLifecycle(id: entry.id, phase: .released)
    lifecycle.update(
      phase: .released,
      isStackForeground: false,
      isStackInteractive: false
    )
    lifecycle.markRemoved()
    return lifecycle
  }

  /// destination 只能读取 Push 时取得的 task，禁止在 View init 中重新创建。
  func preloadTask(for entry: ImageNavigationEntry) -> MediaPreloadTask? {
    preloadTasks[entry.id]
  }

  private func push(_ route: ImageNavigationRoute) -> ImageNavigationEntry {
    let entry = ImageNavigationEntry(route: route)
    entries.append(entry)
    lifecycles[entry.id] = PageImageLifecycle(id: entry.id)

    if case .media(let media) = route, media.shouldPreloadDetail,
      let preloadTask = mediaPreloader.acquireNavigation(for: media, owner: entry.id)
    {
      preloadTasks[entry.id] = preloadTask
    }

    navigationRevision &+= 1
    path.append(entry)
    return entry
  }

  private func reconcilePathMutation() {
    guard path.count <= entries.count else {
      assertionFailure("导航路径只能通过 ImageNavigationCoordinator.push 修改")
      return
    }

    if path.count < entries.count {
      navigationRevision &+= 1
      let removedEntries = entries[path.count...]
      entries.removeLast(entries.count - path.count)

      for entry in removedEntries {
        let lifecycle = lifecycles[entry.id]
        lifecycle?.markRemoved()
        scheduleRemovedLifecycleCleanup(for: entry.id, lifecycle: lifecycle)
        if case .media(let media) = entry.route, media.shouldPreloadDetail {
          mediaPreloader.releaseNavigation(
            for: media,
            owner: entry.id,
            stackID: id,
            size: UIScreen.main.bounds.size
          )
        }
      }
    }

    reconcileLifecycles()
  }

  private func scheduleRemovedLifecycleCleanup(
    for id: UUID,
    lifecycle: PageImageLifecycle?
  ) {
    removedLifecycleCleanupTasks[id]?.cancel()
    let retention = removedLifecycleRetention
    removedLifecycleCleanupTasks[id] = Task { @MainActor [weak self, weak lifecycle] in
      try? await Task.sleep(for: retention)
      guard !Task.isCancelled, lifecycle?.isRemoved == true else { return }
      lifecycle?.finishRemoval()
      self?.lifecycles.removeValue(forKey: id)
      self?.preloadTasks.removeValue(forKey: id)
      self?.removedLifecycleCleanupTasks.removeValue(forKey: id)
    }
  }

  private func finishRemovedLifecyclesImmediately() {
    let removedIDs = lifecycles.compactMap { id, lifecycle in
      lifecycle.isRemoved ? id : nil
    }
    for id in removedIDs {
      removedLifecycleCleanupTasks[id]?.cancel()
      lifecycles[id]?.finishRemoval()
      lifecycles.removeValue(forKey: id)
      preloadTasks.removeValue(forKey: id)
      removedLifecycleCleanupTasks.removeValue(forKey: id)
    }
  }

  private func reconcileLifecycles() {
    let topIndex = entries.count
    rootLifecycle.update(
      phase: phase(for: 0, topIndex: topIndex),
      isStackForeground: isStackForeground,
      isStackInteractive: isStackInteractive
    )

    for (index, entry) in entries.enumerated() {
      let phase = phase(for: index + 1, topIndex: topIndex)
      lifecycles[entry.id]?.update(
        phase: phase,
        isStackForeground: isStackForeground,
        isStackInteractive: isStackInteractive
      )
      if case .media(let media) = entry.route,
        !isStackForeground || phase != .active
      {
        mediaPreloader.setHeroPresented(
          false,
          for: media,
          owner: entry.id,
          size: UIScreen.main.bounds.size
        )
      }
    }
  }

  private func phase(for index: Int, topIndex: Int) -> PageImagePhase {
    switch topIndex - index {
    case 0:
      return .active
    case 1:
      return .adjacent
    default:
      return .released
    }
  }

  private func isCurrent(_ source: ImageNavigationSourceToken) -> Bool {
    isStackInteractive
      && source.stackID == id
      && source.revision == navigationRevision
      && source.topEntryID == entries.last?.id
  }
}
