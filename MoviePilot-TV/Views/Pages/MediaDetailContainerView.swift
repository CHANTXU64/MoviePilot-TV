import Kingfisher
import SwiftUI

/// 媒体详情加载占位视图（共享组件）
/// 用于 MediaDetailContainerView 的加载状态遮罩
/// 海报从源卡片位置飞入屏幕中央 + 标题/元数据/加载指示器
private struct MediaLoadingView: View {
  let title: String?
  let posterUrl: URL?
  let type: String?
  let year: String?
  let rating: Double?
  let overview: String?
  /// 如果数据已预加载完毕，跳过飞入动画
  let isAlreadyLoaded: Bool

  private let posterWidth: CGFloat = 460
  private let posterHeight: CGFloat = 690

  /// 海报相对于自然居中位置的偏移量
  @State private var animationOffset: CGSize = .zero
  /// 海报缩放比
  @State private var posterScale: CGFloat = 1.0
  /// 文本是否已显示
  @State private var textAppeared = false
  /// 防止重复触发动画
  @State private var hasAnimated = false

  /// 组合元数据文本（类型 · 年份）
  private var metadataString: String {
    var parts: [String] = []
    if let type = type, !type.isEmpty { parts.append(type) }
    if let year = year, !year.isEmpty { parts.append(year) }
    return parts.joined(separator: " · ")
  }

  private var ratingString: String? {
    guard let rating = rating, rating > 0 else { return nil }
    return String(format: "%.1f", rating)
  }

  var body: some View {
    ZStack {
      // 毛玻璃背景
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      VStack(spacing: 28) {
        Spacer()

        // 海报图片
        KFImage(posterUrl)
          .requestModifier(AnyModifier.cookieModifier)
          .loadDiskFileSynchronously()
          .fade(duration: 0)
          .placeholder {
            RoundedRectangle(cornerRadius: 20)
              .fill(Color(white: 0.12))
              .overlay(
                Image(systemName: "film")
                  .font(.largeTitle)
                  .foregroundStyle(.gray.opacity(0.5))
              )
          }
          .downsampling(size: CGSize(width: posterWidth, height: posterHeight))
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: posterWidth, height: posterHeight)
          .clipShape(RoundedRectangle(cornerRadius: 20))
          .shadow(color: .black.opacity(0.8), radius: 30, y: 15)
          .scaleEffect(posterScale)
          .offset(animationOffset)

        // 文本信息区
        VStack(spacing: 12) {
          if let title = title, !title.isEmpty {
            HStack(spacing: 12) {
              ProgressView()
                .tint(.primary)
              Text(title)
                .font(.title3.bold())
                .foregroundColor(.primary)
            }
          }

          HStack(spacing: 8) {
            if !metadataString.isEmpty {
              Text(metadataString)
            }

            if !metadataString.isEmpty && ratingString != nil {
              Text("·")
            }

            if let ratingString {
              Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
              Text(ratingString)
            }
          }
          .font(.caption)
          .opacity((metadataString.isEmpty && ratingString == nil) ? 0 : 1)

          if let overview = overview, !overview.isEmpty {
            Text(overview)
              .font(.caption)
          }
        }
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: 1500, alignment: .center)
        .transaction { transaction in
          transaction.disablesAnimations = true
        }
        .opacity(textAppeared ? 1.0 : 0)
        .offset(y: textAppeared ? 0 : 20)

        Spacer()
      }
    }
    .onAppear {
      guard !hasAnimated else { return }
      hasAnimated = true

      let source = MediaCardTransition.sourceFrame
      // 清除源 frame，防止预加载命中或后续入口复用脏数据
      MediaCardTransition.sourceFrame = .zero

      // 数据已预加载完毕，跳过所有动画
      guard !isAlreadyLoaded else {
        textAppeared = true
        return
      }

      if source != .zero {
        // 估算海报在 VStack 居中布局下的屏幕中心位置
        let screen = UIScreen.main.bounds
        let contentBlockHeight: CGFloat = posterHeight + 28 + 210
        let estimatedPosterCenterY = (screen.height - contentBlockHeight) / 2 + posterHeight / 2
        let estimatedPosterCenter = CGPoint(x: screen.midX, y: estimatedPosterCenterY)

        // ── Phase 1: 强制禁用所有动画，立即渲染到源卡片位置 ──
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
          animationOffset = CGSize(
            width: source.midX - estimatedPosterCenter.x,
            height: source.midY - estimatedPosterCenter.y
          )
          posterScale = source.width / posterWidth
        }

        // ── Phase 2: 等待渲染完成，再启动纯移动+放大动画 ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
            animationOffset = .zero
            posterScale = 1.0
          }
          // 文字在海报到达中央后渐入
          withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            textAppeared = true
          }
        }
      } else {
        // Fallback：无源位置（如从右键菜单进入），使用简单缩放动画
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
          posterScale = 0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
            posterScale = 1.0
          }
          withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            textAppeared = true
          }
        }
      }
    }
  }
}

/// 媒体详情的容器视图。
/// 负责从 MediaPreloader 获取预加载任务，管理加载状态，
/// 在 fullDetail 就绪后通过 applyFullDetail 刷新 MediaDetailView。
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

  /// 第二页首行内容是否已就绪（由 MediaDetailView 回写）
  @State private var isContentReady = false
  /// 记录首次出现时数据是否已预加载完毕（在 init 中设置，确保第一帧就生效）
  @State private var wasPreloaded: Bool
  /// 最短展示时间是否已过（防止加载太快导致动画闪烁）
  @State private var minTimeElapsed = false

  init(media: MediaInfo, navigationPath: Binding<NavigationPath>, preloadTask: MediaPreloadTask) {
    self.media = media
    _navigationPath = navigationPath
    self.preloadTask = preloadTask
    // 在 init 中判断，确保第一帧 isReady 就正确
    _wasPreloaded = State(initialValue: preloadTask.isDetailReady)
  }

  /// 数据是否就绪（加载成功或失败均算就绪，且首行内容已加载）
  /// 如果数据在进入时已预加载完毕，直接视为就绪
  private var isReady: Bool {
    wasPreloaded
      || ((preloadTask.isDetailReady && isContentReady) && minTimeElapsed)
      || preloadTask.isDetailFailed
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
        preloadTask: preloadTask,
        isContentReady: $isContentReady
      )
      // 加载未完成时隐藏详情，防止 NavigationStack 过渡动画透出内容
      .opacity(isReady ? 1 : 0)

      // Loading 遮罩层 — 始终存在于视图树中，通过 opacity 控制显隐
      MediaLoadingView(
        title: media.cleanedTitle ?? media.title,
        posterUrl: media.imageURLs.poster,
        type: media.type,
        year: media.year,
        rating: media.vote_average,
        overview: media.overview,
        isAlreadyLoaded: wasPreloaded
      )
      .opacity(isReady ? 0 : 1)
      // 备忘：在 tvOS 上，全屏的透明视图有时会干扰 Focus Engine 对下方卡片的探测。
      // 若后续发现在详情页快速加载完成时下方按钮偶尔难以获取焦点，可考虑在此处加上 .scaleEffect(isReady ? 0 : 1)
      .allowsHitTesting(!isReady)  // 数据就绪后不拦截焦点事件
    }
    .animation(.easeInOut(duration: 0.3), value: isReady)
    .onAppear {
      // 最短展示计时器（仅在需要加载时生效）
      if !wasPreloaded {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          withAnimation(.easeInOut(duration: 0.3)) {
            minTimeElapsed = true
          }
        }
      }
    }
  }
}
