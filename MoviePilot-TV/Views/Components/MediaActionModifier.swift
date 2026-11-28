import SwiftUI

struct MediaActionModifier: ViewModifier {
  @EnvironmentObject var handler: MediaActionHandler

  func body(content: Content) -> some View {
    content
      .alert("提示", isPresented: $handler.showTMDBNotFoundAlert) {
        Button("确定", role: .cancel) {}
      } message: {
        Text("未识别到此媒体的TMDB信息")
      }
      .overlay {
        if handler.isRecognizingTmdb {
          BlockingProgressOverlay(text: "正在识别媒体信息…")
        }
      }
  }
}

extension View {
  func mediaActionAlerts() -> some View {
    modifier(MediaActionModifier())
  }

  /// 默认详情入口的等待遮罩只挂在发起等待的导航栈上，不能由根视图全局显示。
  func mediaDetailPreparingOverlay(isPreparing: Bool) -> some View {
    overlay {
      if isPreparing {
        BlockingProgressOverlay(text: "正在识别媒体信息…")
      }
    }
  }
}
