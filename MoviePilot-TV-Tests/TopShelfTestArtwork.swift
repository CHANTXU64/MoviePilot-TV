import Foundation
import UIKit

/// 有效编码图片，覆盖真实降采样过程；不使用无法解码的占位字节。
enum TopShelfTestArtwork {
  static let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")!
  @MainActor
  static func landscapeData() -> Data {
    autoreleasepool {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      return UIGraphicsImageRenderer(size: CGSize(width: 3840, height: 2160), format: format).image
      { context in
        UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
      }.jpegData(compressionQuality: 0.9)!
    }
  }
}
