import SwiftUI

struct MediaSubscriptionModifier: ViewModifier {
  @Binding var sheetSubscribe: Subscribe?
  @Binding var tvSubscribeRequest: SubscribeSeasonRequest?
  @Binding var showAlert: Bool
  let alertTitle: String
  let alertMessage: String
  @Binding var navigationPath: NavigationPath

  func body(content: Content) -> some View {
    content
      .sheet(item: $sheetSubscribe) { subscribe in
        SubscribeSheet(subscribe: subscribe, isNewSubscription: true)
          .onDisappear {
            // 订阅完成后，将订阅状态回写到预加载缓存（Issue 4: 自动同步机制）
            // 通过 mediaId 构建一个临时 MediaInfo 来查找对应的 preloadTask
            // 由于 SubscribeSheet dismiss 时可能已经成功订阅，直接标记为 true
            // 后续进入详情页时会通过 refreshSubscriptionStatus() 精确校准
            Task { @MainActor in
              // 就地构造 mediaId（与 MediaInfo.mediaId 构造逻辑一致：tmdb > douban > bangumi）
              // 不复用全局方法，因为不同场景的 mediaId 构造可能有细微差异
              let mediaId = subscribe.apiMediaId ?? ""
              if !mediaId.isEmpty,
                let task = MediaPreloader.shared.findTask(byMediaId: mediaId)
              {
                // 预设为已订阅（乐观更新），进入详情页后会精确校准
                task.isSubscribed = true
              }
            }
          }
      }
      .alert(alertTitle, isPresented: $showAlert) {
        Button("确定", role: .cancel) {}
      } message: {
        Text(alertMessage)
      }
      .onChange(of: tvSubscribeRequest) { _, newValue in
        if let request = newValue {
          navigationPath.append(request)
          tvSubscribeRequest = nil
        }
      }
  }
}

extension View {
  /// 添加媒体订阅相关的弹窗（使用 SubscriptionHandler）
  func mediaSubscriptionAlerts(
    using handler: SubscriptionHandler, navigationPath: Binding<NavigationPath>
  ) -> some View {
    modifier(
      MediaSubscriptionModifier(
        sheetSubscribe: Binding(
          get: { handler.sheetSubscribe },
          set: { handler.sheetSubscribe = $0 }
        ),
        tvSubscribeRequest: Binding(
          get: { handler.tvSubscribeRequest },
          set: { handler.tvSubscribeRequest = $0 }
        ),
        showAlert: Binding(
          get: { handler.showAlert },
          set: { handler.showAlert = $0 }
        ),
        alertTitle: handler.alertTitle,
        alertMessage: handler.alertMessage,
        navigationPath: navigationPath
      ))
  }
}
