import Foundation
import SwiftDate
import SwiftUI

extension Int64 {
  private static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    // 前端 Vue (formatFileSize) 使用 1024 作为基数换算，此处严格保持一致
    formatter.countStyle = .binary
    // 允许显示从小到大的完整单位，避免小文件(如字幕、NFO)显示为 0 MB
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    return formatter
  }()

  /// 将字节数 (Bytes) 格式化为易读的字符串（如 KB, MB, GB, TB）
  /// 默认优先显示大单位，适用于文件大小展示。此方法已针对 SwiftUI 列表高频刷新优化。
  func formattedBytes() -> String {
    return Int64.byteFormatter.string(fromByteCount: self)
  }
}

extension String {
  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter
  }()

  /// 解析日期字符串并格式化为相对时间（如“3天前”），适用于 SwiftUI 列表高频刷新优化
  func toRelativeDateString() -> String {
    let CN_Region = Region(zone: Zones.asiaShanghai)
    if let time = Date(self, region: CN_Region) {
      return String.relativeDateFormatter.string(for: time) ?? self
    }
    return self
  }
}

// 用于条件修饰符的视图扩展
extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View
  {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
