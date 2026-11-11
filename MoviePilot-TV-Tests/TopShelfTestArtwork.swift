import Darwin
import Foundation
import UIKit

/// 有效编码图片，覆盖真实降采样过程；不使用无法解码的占位字节。
enum TopShelfTestArtwork {
  static let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")!
  static func resourceFiles(in container: URL) throws -> [String: Data] {
    let root = container.appendingPathComponent("Library/Caches/TopShelf")
    var files: [String: Data] = [:]
    for name in ["images", "details", "cards"] {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root.appendingPathComponent(name), includingPropertiesForKeys: [.isRegularFileKey])
      else { continue }
      for case let url as URL in enumerator {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
          continue
        }
        files[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
      }
    }
    return files
  }

  static func ageResources(in container: URL, by age: TimeInterval) throws {
    let root = container.appendingPathComponent("Library/Caches/TopShelf")
    for path in try resourceFiles(in: container).keys {
      try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-age)],
        ofItemAtPath: root.appendingPathComponent(path).path)
    }
  }

  static func heldFileLocks(in container: URL) throws -> [String] {
    let root = container.appendingPathComponent("Library/Caches/TopShelf")
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    var held: [String] = []
    for case let file as URL in files where file.pathExtension == "lock" {
      let fd = open(file.path, O_RDWR)
      guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
      defer { close(fd) }
      let result = flock(fd, LOCK_EX | LOCK_NB)
      if result == 0 {
        flock(fd, LOCK_UN)
      } else if errno == EWOULDBLOCK {
        held.append(file.lastPathComponent)
      } else {
        throw CocoaError(.fileReadUnknown)
      }
    }
    return held
  }

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
