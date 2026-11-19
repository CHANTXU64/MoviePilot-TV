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

/// 订阅编辑、复用订阅这类"关闭即取消用户正在进行工作"的贵弹窗呈现计数。
/// Top Shelf 交接据此决定不强制关闭、等用户自然关完再跳转，避免打断订阅或 Fork。
/// 由弹窗自身 onAppear/onDisappear 注册，不依赖窗口扫描，后台未激活时也准确。
@MainActor
enum CostlyModalPresentation {
  private static var count = 0
  static var isPresenting: Bool { count > 0 }
  static func begin() { count += 1 }
  static func end() { count = max(0, count - 1) }
  /// 仅供测试隔离清理；生产不调用——呈现就绪机制的祖先链看不到子视图呈现的贵弹窗，
  /// 若据此 reset 会在面板仍开着时误清标记，导致 Top Shelf 提前交接关掉面板。
  static func reset() { count = 0 }
}

extension PresentationReadyAction {
  /// 同步查询当前 key window 是否有模态正在呈现（含关闭转场中）。递归扫描控制器树，
  /// 嵌套弹窗也能命中。只查 key window，避免把无关窗口的模态算进来误延迟冷启动交接；
  /// 后台未 key 时的贵弹窗由 CostlyModalPresentation 标记兜底。
  @MainActor static var isModalPresenting: Bool {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where window.isKeyWindow {
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
