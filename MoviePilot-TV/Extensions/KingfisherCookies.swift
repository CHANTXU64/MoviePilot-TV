import Foundation
import Kingfisher

enum TransientDecodedImage {
  /// 全屏或过渡大图只在当前视图解码，不写入 Kingfisher 内存表。
  static let skipMemoryCache: KingfisherOptionsInfoItem = .memoryCacheExpiration(.expired)
}

@MainActor
extension KFImage {
  /// 公共图片继续共享 Kingfisher 默认缓存；后端受保护图片绑定当前会话的 downloader、Cookie 与 cache key。
  static func sessionImage(_ url: URL?) -> KFImage {
    guard let url else { return KFImage(source: nil) }
    let service = APIService.shared
    var image = KFImage(source: service.imageSource(for: url))
    if let downloader = service.imageDownloader(for: url) {
      image = image.downloader(downloader)
    }
    if let modifier = service.imageRequestModifier(for: url) {
      image = image.requestModifier(modifier)
    }
    return image
  }

  func skippingMemoryCache() -> Self {
    memoryCacheExpiration(.expired)
  }
}
