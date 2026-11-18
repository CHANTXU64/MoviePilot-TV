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
  private static let seasonPrefixRegex = try? NSRegularExpression(
    pattern: #"^S(\d+)(?:-S?(\d+))?\s*"#,
    options: .caseInsensitive)
  private static let episodeRangeRegex = try? NSRegularExpression(
    pattern: #"^E?(\d+)(?:-E?(\d+))?$"#,
    options: .caseInsensitive)

  /// 将季集字符串 (如 "S01", "S01E01", "S01 E28-E32", "E01-E05", "S01 E01-E03、E05")
  /// 格式化为中文 (如 "1季", "1季 1集", "1季 28-32集", "1-5集", "1季 1-3、5集")。
  /// 集号支持后端并列多区间（顿号或逗号分隔，见 MoviePilot `episode.format_ranges`）；
  /// 任一段认不出时整串原样返回，不改写后端原文。
  func formattedSeasonEpisode() -> String {
    guard let seasonRegex = String.seasonPrefixRegex,
      let episodeRegex = String.episodeRangeRegex
    else {
      return self
    }

    let nsString = self as NSString
    var seasonPart: String?
    var episodeText = self
    if let match = seasonRegex.firstMatch(
      in: self, options: [], range: NSRange(location: 0, length: nsString.length))
    {
      guard let start = Int(nsString.substring(with: match.range(at: 1))) else { return self }
      var text = "\(start)"
      let endRange = match.range(at: 2)
      if endRange.location != NSNotFound {
        guard let end = Int(nsString.substring(with: endRange)) else { return self }
        text += "-\(end)"
      }
      seasonPart = text + "季"
      episodeText = nsString.substring(from: match.range.length)
    }

    guard !episodeText.isEmpty else { return seasonPart ?? self }

    var segments: [String] = []
    for part in episodeText.split(
      omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "、" })
    {
      let token = String(part).trimmingCharacters(in: .whitespaces)
      let nsToken = token as NSString
      guard let match = episodeRegex.firstMatch(
        in: token, options: [], range: NSRange(location: 0, length: nsToken.length)),
        let start = Int(nsToken.substring(with: match.range(at: 1)))
      else {
        return self
      }
      var text = "\(start)"
      let endRange = match.range(at: 2)
      if endRange.location != NSNotFound {
        guard let end = Int(nsToken.substring(with: endRange)) else { return self }
        text += "-\(end)"
      }
      segments.append(text)
    }

    let episodePart = segments.joined(separator: "、") + "集"
    guard let seasonPart else { return episodePart }
    return seasonPart + " " + episodePart
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
