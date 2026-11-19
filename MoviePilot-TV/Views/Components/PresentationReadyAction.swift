import SwiftUI

/// 根据实际窗口、模态和导航转场状态交接呈现，不用固定延时猜测动画完成。
struct PresentationReadyAction: UIViewControllerRepresentable {
  let isEnabled: Bool
  var requiresNavigationTop = false
  var cancelsEditing = false
  var contentFocusMatches = false
  var onContentFocus: (() -> Void)? = nil
  let action: () -> Void

  func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> Controller {
    Controller()
  }

  func updateUIViewController(
    _ controller: Controller, context: UIViewControllerRepresentableContext<Self>
  ) {
    controller.requiresNavigationTop = requiresNavigationTop
    controller.cancelsEditing = cancelsEditing
    controller.contentFocusMatches = contentFocusMatches
    controller.onContentFocus = onContentFocus
    controller.action = action
    controller.setEnabled(isEnabled)
  }

  static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
    controller.setEnabled(false)
    controller.action = nil
    controller.onContentFocus = nil
  }

  final class Controller: UIViewController {
    var requiresNavigationTop = false
    var cancelsEditing = false
    var contentFocusMatches = false
    var action: (() -> Void)?
    var onContentFocus: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var hasAppeared = false
    private weak var presentationWindow: UIWindow?
    var isCheckingPresentation: Bool { displayLink != nil }

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      hasAppeared = true
      presentationWindow = view.window
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      hasAppeared = false
    }

    func setEnabled(_ enabled: Bool) {
      if enabled, displayLink == nil {
        let link = CADisplayLink(target: FrameObserver(self), selector: #selector(FrameObserver.tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
      } else if !enabled {
        displayLink?.invalidate()
        displayLink = nil
      }
    }

    fileprivate func checkPresentation() {
      if let window = viewIfLoaded?.window { presentationWindow = window }
      guard let window = presentationWindow, !window.isHidden, window.isKeyWindow
      else { return }
      // 原生键盘可能暂时覆盖根 controller；先结束输入，才等待根页再次出现。
      if cancelsEditing { window.endEditing(true) }
      guard hasAppeared, let view = viewIfLoaded, !view.bounds.isEmpty,
        view.window === window
      else { return }
      var ancestor: UIViewController? = self
      var navigationTop: UIViewController?
      while let controller = ancestor {
        guard controller.presentedViewController == nil,
          controller.transitionCoordinator == nil,
          !controller.isBeingDismissed, !controller.isBeingPresented,
          controller.viewIfLoaded?.isHidden != true,
          (controller.viewIfLoaded?.alpha ?? 1) > 0
        else { return }
        if let navigation = controller as? UINavigationController {
          guard let top = navigation.topViewController,
            navigation.visibleViewController === top,
            top.viewIfLoaded?.window === window,
            view.isDescendant(of: top.view)
          else { return }
          navigationTop = top
        }
        ancestor = controller.parent
      }
      guard !requiresNavigationTop || navigationTop != nil else { return }
      if contentFocusMatches, let onContentFocus, let navigationTop,
        let focusedItem = UIFocusSystem.focusSystem(for: window)?.focusedItem,
        navigationTop.contains(focusedItem)
      {
        onContentFocus()
      } else {
        action?()
      }
    }

    // 显式非隔离析构。tvOS 18 的隔离析构回部署会在 TaskLocal 里释放未分配指针。
    nonisolated deinit { displayLink?.invalidate() }
  }

  private final class FrameObserver: NSObject {
    // 显式非隔离析构，避开 tvOS 18 的隔离析构回部署崩溃。
    nonisolated deinit {}

    weak var controller: Controller?
    init(_ controller: Controller) { self.controller = controller }
    @objc func tick() { controller?.checkPresentation() }
  }
}

private struct TopShelfPresentationKey: EnvironmentKey {
  static let defaultValue = TopShelfOpeningContext()
}

/// 订阅编辑、复用订阅这类"关闭即取消用户正在进行工作"的贵弹窗呈现登记。
/// Top Shelf 交接据此决定不强制关闭、等用户自然关完再跳转，避免打断订阅或 Fork。
/// 用弱引用绑定弹窗实例生命周期：令牌由弹窗视图 @State 持有，视图因会话失效/权限变化/
/// 树拆除被销毁时令牌释放、弱引用置空，即使 isPresented 注销回调未触发也不会残留登记
/// 卡死 Top Shelf；读取时清理已释放令牌。不依赖窗口扫描，后台未激活时也准确。
@MainActor
enum CostlyModalPresentation {
  private final class WeakOwner {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
  }
  private static var owners: [WeakOwner] = []
  static var isPresenting: Bool {
    owners.removeAll { $0.value == nil }
    return !owners.isEmpty
  }
  static func register(_ owner: AnyObject) {
    owners.removeAll { $0.value == nil || $0.value === owner }
    owners.append(WeakOwner(owner))
  }
  static func unregister(_ owner: AnyObject) {
    owners.removeAll { $0.value == nil || $0.value === owner }
  }
  /// 仅供测试隔离清理。
  static func reset() { owners.removeAll() }
}

/// 每个贵弹窗视图持有的身份令牌；视图销毁即释放，登记随之失效。
final class CostlyModalToken {}

extension PresentationReadyAction {
  /// 同步查询可见窗口是否有模态正在呈现（含关闭转场中）。递归扫描控制器树，嵌套弹窗也能命中。
  /// 用可见窗口（!isHidden）而非 key window：后台窗口非 key 但仍可见，安全弹窗也能命中；
  /// 隐藏的测试窗口被排除，避免误延迟冷启动交接。贵弹窗另由 CostlyModalPresentation 标记兜底。
  @MainActor static var isModalPresenting: Bool {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where !window.isHidden {
        if hasPresentedModal(window.rootViewController) { return true }
      }
    }
    return false
  }

  @MainActor private static func hasPresentedModal(_ controller: UIViewController?) -> Bool {
    guard let controller else { return false }
    if controller.presentedViewController != nil { return true }
    return controller.children.contains { hasPresentedModal($0) }
  }
}

struct TopShelfOpeningContext {
  var routeID: UUID?
  var blocksInteraction = false
  var didPresent: (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
  var topShelfPresentation: TopShelfOpeningContext {
    get { self[TopShelfPresentationKey.self] }
    set { self[TopShelfPresentationKey.self] = newValue }
  }
}
