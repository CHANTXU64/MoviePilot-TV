import SwiftUI

/// 媒体详情加载占位视图（共享组件）
/// 用于 MediaDetailContainerView 的加载状态遮罩
private struct MediaLoadingView: View {
  let title: String?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 28) {
        ProgressView()
          .scaleEffect(1.5)
        if let title = title, !title.isEmpty {
          Text(title)
            .font(.headline)
            .foregroundColor(.white.opacity(0.7))
        }
        Text("正在加载详情...")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.5))
      }
    }
  }
}

/// 媒体详情的容器视图。
/// 负责从 MediaPreloader 获取预加载任务，管理加载状态，
/// 在 fullDetail 就绪后通过 updateDetail 刷新 MediaDetailView。
///
/// ⚠️ 焦点恢复关键设计：
/// MediaDetailView 从第一帧起就存在于视图树中（用 partialMedia 初始化），
/// Loading 视图叠加在上方仅通过 opacity 控制显隐。
/// 这保证了视图树结构永远不发生变化，tvOS Focus Engine 在导航返回时
/// 可以正确恢复源页面的焦点位置。
struct MediaDetailContainerView: View {
  let media: MediaInfo
  @Binding var navigationPath: NavigationPath

  /// 预加载任务：在 init 中立即获取/创建，确保首帧就有数据
  /// 非 Optional，消除 if let 条件分支导致的视图结构变化
  @State private var preloadTask: MediaPreloadTask

  init(media: MediaInfo, navigationPath: Binding<NavigationPath>) {
    self.media = media
    _navigationPath = navigationPath
    // 在 init 中立即获取预加载任务，避免首帧出现条件分支
    _preloadTask = State(wrappedValue: MediaPreloader.shared.preload(for: media))
  }

  var body: some View {
    // 直接传入 preloadTask（非 Optional，无条件分支）
    MediaDetailContainerContent(
      media: media,
      navigationPath: $navigationPath,
      preloadTask: preloadTask
    )
    .task(id: media.id) {
      // 确保当前任务被锁定，防止用户在子页面浏览时被最近最少使用算法 (LRU) 淘汰
      MediaPreloader.shared.pin(key: media.id)
    }
    .onDisappear {
      // 离开详情页后解除锁定，允许最近最少使用算法 (LRU) 正常淘汰
      MediaPreloader.shared.unpin(key: media.id)
    }
  }
}

/// 内部辅助视图：通过 @ObservedObject 监听 MediaPreloadTask 的 @Published 属性变化，驱动 UI 刷新
private struct MediaDetailContainerContent: View {
  let media: MediaInfo
  @Binding var navigationPath: NavigationPath
  @ObservedObject var preloadTask: MediaPreloadTask

  /// 数据是否就绪（加载成功或失败均算就绪）
  private var isReady: Bool {
    preloadTask.isDetailLoaded || preloadTask.isDetailFailed
  }

  var body: some View {
    // ⚠️ 焦点恢复核心设计：
    // MediaDetailView 无条件渲染（从第一帧就存在），用 partialMedia 初始化。
    // Loading 叠加在上方，仅通过 opacity 控制显隐。
    // 视图树结构永远不变，tvOS Focus Engine 可正确追踪和恢复焦点。
    let detail = preloadTask.fullDetail ?? media

    ZStack {
      // Detail 层 — 无条件渲染，从第一帧就存在于视图树中
      MediaDetailView(
        detail: detail,
        navigationPath: $navigationPath,
        preloadTask: preloadTask
      )

      // Loading 遮罩层 — 始终存在于视图树中，通过 opacity 控制显隐
      MediaLoadingView(title: media.title)
        .opacity(isReady ? 0 : 1)
        // 备忘：在 tvOS 上，全屏的透明视图有时会干扰 Focus Engine 对下方卡片的探测。
        // 若后续发现在详情页快速加载完成时下方按钮偶尔难以获取焦点，可考虑在此处加上 .scaleEffect(isReady ? 0 : 1)
        .allowsHitTesting(!isReady)  // 数据就绪后不拦截焦点事件
    }
    .animation(.easeInOut(duration: 0.3), value: isReady)
  }
}
