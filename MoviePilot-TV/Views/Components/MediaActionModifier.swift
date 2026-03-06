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
          Color.black.opacity(0.4).ignoresSafeArea()
          VStack(spacing: 28) {
            ProgressView()
              .scaleEffect(1.5)
            Text("正在识别媒体信息...")
              .font(.headline)
              .foregroundColor(.white)
          }
          .frame(width: 500, height: 230)
          .background(.ultraThinMaterial)
          .cornerRadius(36)
        }
      }
  }
}

extension View {
  func mediaActionAlerts() -> some View {
    modifier(MediaActionModifier())
  }
}
