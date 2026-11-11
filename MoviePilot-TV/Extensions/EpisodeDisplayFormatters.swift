import Foundation

enum SeasonDisplayFormatter {
  /// 季卡与详情 Sheet 共用季名规则，避免 S00、缺失和非法季号出现不同文案。
  static func name(seasonNumber: Int?, rawName: String?) -> String {
    guard let seasonNumber else { return "未知季" }

    switch seasonNumber {
    case 0:
      return nonEmpty(rawName).map(localizedLabel) ?? "特别篇"
    case let seasonNumber where seasonNumber > 0:
      return "第 \(seasonNumber) 季"
    default:
      return "未知季"
    }
  }

  /// 本地化通用季号，保留后面的篇章名称。
  static func localizedLabel(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.wholeMatch(of: #/(?:sp\s*[•·:：-]\s*)?specials/#.ignoresCase()) != nil {
      return "特别篇"
    }
    guard let match = trimmed.wholeMatch(of: #/(?:season|s)\s*([0-9]+)(?:\s*[-–—:：•·]\s*(.+))?/#.ignoresCase()),
      let number = Int(match.1)
    else { return title }
    let season = name(seasonNumber: number, rawName: nil)
    if let chapter = match.2 { return "\(season) · \(chapter)" }
    return season
  }

  /// 将可选文本统一裁剪空白；纯空白值按缺失处理。
  static func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func cardTitle(seasonNumber: Int?, rawName: String?, airDate: String?) -> String {
    var title = name(seasonNumber: seasonNumber, rawName: rawName)
    if let airDate = nonEmpty(airDate) {
      title += " · \(airDate.prefix(4))"
    }
    return title
  }
}

enum EpisodeGroupDisplayFormatter {
  /// 译名匹配完整组名，季号标签复用季名格式。
  static func name(_ name: String) -> String {
    let title = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    switch title.lowercased().replacingOccurrences(of: "’", with: "'") {
    case "": return "未命名剧集组"
    case "season", "seasons": return "季"
    case "separate seasons", "seperate seasons": return "分季编排"
    case "year split": return "年度分季"
    case "director's cut seasons": return "导演剪辑版"
    case "story arc", "story arcs": return "故事线"
    case "sagas": return "故事大篇章"
    case "original air date": return "首播日期"
    case "aired order": return "首播顺序"
    case "intended order": return "原定顺序"
    case "alternate order": return "替代顺序"
    // TMDB 简中词表里，类别 Absolute 的用词是「独立」。
    case "absolute": return "独立"
    case "dvd": return "DVD"
    case "dvd order": return "DVD 顺序"
    case "blu-ray", "bluray": return "蓝光版"
    case "blu-ray order", "bluray order": return "蓝光版顺序"
    case "digital": return "数字"
    case "digital order": return "数字发行顺序"
    case "production": return "制片"
    case "production order": return "制作顺序"
    case "tv": return "电视"
    case "tv order": return "电视播出顺序"
    default: return SeasonDisplayFormatter.localizedLabel(title)
    }
  }
}
