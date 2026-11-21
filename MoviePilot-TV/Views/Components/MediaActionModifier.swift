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
}
