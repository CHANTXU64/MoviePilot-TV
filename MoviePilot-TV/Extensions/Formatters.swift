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
  /// 将季集字符串 (如 "S01", "S01E01", "S01 E28-E32", "E01-E05") 格式化为中文 (如 "1季", "1季 1集", "1季 28-32集", "1-5集")
  func formattedSeasonEpisode() -> String {
    let pattern = "^(?:S(\\d+)(?:-S?(\\d+))?\\s*)?(?:E(\\d+)(?:-E?(\\d+))?)?$"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return self
    }

    let nsString = self as NSString
    let results = regex.matches(
      in: self, options: [], range: NSRange(location: 0, length: nsString.length))

    guard let match = results.first else {
      return self
    }

    var result = ""

    // 提取季
    let s1Range = match.range(at: 1)
    if s1Range.location != NSNotFound {
      let s1 = nsString.substring(with: s1Range)
      if let s1Num = Int(s1) {
        result += "\(s1Num)"

        let s2Range = match.range(at: 2)
        if s2Range.location != NSNotFound {
          let s2 = nsString.substring(with: s2Range)
          if let s2Num = Int(s2) {
            result += "-\(s2Num)"
          }
        }
        result += "季"
      }
    }

    // 提取集
    let e1Range = match.range(at: 3)
    if e1Range.location != NSNotFound {
      let e1 = nsString.substring(with: e1Range)
      if let e1Num = Int(e1) {
        if !result.isEmpty { result += " " }
        result += "\(e1Num)"

        let e2Range = match.range(at: 4)
        if e2Range.location != NSNotFound {
          let e2 = nsString.substring(with: e2Range)
          if let e2Num = Int(e2) {
            result += "-\(e2Num)"
          }
        }
        result += "集"
      }
    }
    return result.isEmpty ? self : result
  }

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
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
