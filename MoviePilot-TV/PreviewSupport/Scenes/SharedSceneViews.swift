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
