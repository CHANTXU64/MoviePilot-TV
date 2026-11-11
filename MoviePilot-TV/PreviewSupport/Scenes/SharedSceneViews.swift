#if DEBUG
import SwiftUI

/// 预览场景通用容器：等启动会话准备完成后，用真实 `TabView` 打开指定 Tab。
///
/// 使用真实 `MainContentView` 而不是把页面单独抽出来渲染，保证 Tab 栏、可见性判断、
/// 全局设置、焦点与线上一致。
struct UIPreviewTabRootView: View {
  @StateObject private var viewModel: ContentViewModel
  private let tab: ContentViewModel.Tab

  init(tab: ContentViewModel.Tab) {
    let viewModel = ContentViewModel()
    viewModel.selectedTab = tab
    _viewModel = StateObject(wrappedValue: viewModel)
    self.tab = tab
  }

  var body: some View {
    MainContentView(viewModel: viewModel)
      .task {
        await viewModel.prepareStartupIfNeeded()
        viewModel.selectedTab = tab
      }
  }
}

/// 单页预览容器：不套完整 Tab 栏，用于无权限等需要单独渲染某个页面的场景。
struct UIPreviewPageHost<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      content
    }
    .withNotification()
  }
}

/// 顶部通知条场景容器：渲染真实页面（或指定背景），并在出现时让 `NotificationManager`
/// 显示一条通知。用于播放失败、登录失效、保存失败等全局提示类状态；默认时长很长，便于截图。
/// 通知条由目录根视图的 `withNotification()` 统一渲染。
struct UIPreviewBannerHost<Backdrop: View>: View {
  @EnvironmentObject private var notificationManager: NotificationManager

  private let type: NotificationType
  private let message: String
  private let duration: Double
  private let backdrop: Backdrop

  init(
    type: NotificationType,
    message: String,
    duration: Double = 600,
    @ViewBuilder backdrop: () -> Backdrop
  ) {
    self.type = type
    self.message = message
    self.duration = duration
    self.backdrop = backdrop()
  }

  var body: some View {
    backdrop
      .onAppear {
        notificationManager.show(message: message, type: type, duration: duration)
      }
  }
}

extension UIPreviewEnvironment {
  /// 在当前环境上覆盖若干接口行为。
  func with(behaviors: [String: UIPreviewBackend.Behavior]) -> UIPreviewEnvironment {
    var copy = self
    for (key, behavior) in behaviors {
      copy.behaviors[key] = behavior
    }
    return copy
  }
}

extension UIPreviewScene {
  /// 生成一个会先激活预览环境、再渲染真实页面的场景。
  @MainActor
  static func page<Content: View>(
    id: String,
    title: String,
    note: String,
    environment: UIPreviewEnvironment = .standard,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    @ViewBuilder content: @escaping @MainActor () -> Content
  ) -> UIPreviewScene {
    UIPreviewScene(id: id, title: title, note: note) {
      UIPreviewBackend.shared.activate(environment.with(behaviors: behaviors))
      return AnyView(content())
    }
  }
}
#endif
