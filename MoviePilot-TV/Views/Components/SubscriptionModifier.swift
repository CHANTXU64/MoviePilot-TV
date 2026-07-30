import SwiftUI

struct MediaSubscriptionModifier: ViewModifier {
  @Binding var sheetSubscribe: Subscribe?
  @Binding var tvSubscribeRequest: SubscribeSeasonRequest?
  @Binding var navigationPath: NavigationPath
  @ObservedObject var handler: SubscriptionHandler
  @EnvironmentObject private var notificationManager: NotificationManager

  func body(content: Content) -> some View {
    content
      .sheet(item: $sheetSubscribe) { subscribe in
        SubscribeSheet(
          subscribe: subscribe,
          isNewSubscription: handler.sheetIsNewSubscription,
          onSave: { saved in
            // 先按保存后的统一身份更新缓存；保存通知会继续校准活跃详情。
            Self.updatePreloadedSubscription(afterSaving: saved)
          }
        )
      }
      .onChange(of: tvSubscribeRequest) { _, newValue in
        if let request = newValue {
          navigationPath.append(request)
          tvSubscribeRequest = nil
        }
      }
      .onChange(of: handler.notificationSerial) { _, _ in
        guard !handler.notificationMessage.isEmpty else { return }
        notificationManager.show(message: handler.notificationMessage, type: handler.notificationType)
      }
  }

  @discardableResult
  static func updatePreloadedSubscription(afterSaving saved: Subscribe) -> Bool {
    guard let mediaId = saved.apiMediaId,
      let task = MediaPreloader.shared.findTask(byMediaId: mediaId)
    else {
      return false
    }
    task.isSubscribed = true
    return true
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
        navigationPath: navigationPath,
        handler: handler
      ))
  }
}
