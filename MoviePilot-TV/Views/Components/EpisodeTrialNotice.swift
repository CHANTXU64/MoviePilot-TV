import SwiftUI

extension View {
  /// 碰到本机试看订阅时的系统提示框，首页订阅卡、季订阅页和订阅面板共用。
  /// 已在取消时只说明进度、不再提供取消；能取消时按钮先执行 `cancel`，提示框随后自行关闭。
  func episodeTrialNotice(
    isPresented: Binding<Bool>, context: EpisodeTrialHoldNotice.Context, isCancelling: Bool, canCancel: Bool,
    cancel: @escaping () -> Void
  ) -> some View {
    alert(EpisodeTrialHoldNotice.title(isCancelling: isCancelling), isPresented: isPresented) {
      if canCancel, !isCancelling {
        Button(EpisodeTrialHoldNotice.cancelButtonTitle(for: context), role: .destructive) {
          cancel()
        }
      }
      Button(EpisodeTrialHoldNotice.backTitle, role: .cancel) {}
    } message: {
      Text(EpisodeTrialHoldNotice.message(for: context, isCancelling: isCancelling, canCancel: canCancel))
    }
  }
}
