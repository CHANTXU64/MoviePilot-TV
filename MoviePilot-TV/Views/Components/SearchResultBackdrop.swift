import Kingfisher
import SwiftUI

/// 资源与字幕结果页沿用同一背景及页面图片生命周期。
struct SearchResultBackdrop: View {
  let url: URL?

  var body: some View {
    PageManagedImage(
      url: url,
      processor: BlurImageProcessor(blurRadius: 60)
        |> ResizingImageProcessor(
          referenceSize: UIScreen.main.bounds.size,
          mode: .aspectFill
        ),
      isEnabled: true,
      role: .activePage,
      participatesInPageLifecycle: true,
      skipsMemoryCache: true,
      fadeDuration: 0
    )
    .opacity(0.3)
    .ignoresSafeArea()
  }
}
