import Foundation

/// 媒体库页「继续观看」行的派生显示与识别输入。数据来自 MoviePilot `/mediaserver/playing`：
/// 进度是后端的 `percent`（0…100），季集只写在副标题里，接口没有单独的季号集号字段。
nonisolated enum ContinueWatchingDisplay {
  /// 副标题开头的季集编号：Emby、Jellyfin、极空间等是「S2:5 - 集名」，Plex 是「S2:E5 - 集名」。
  /// 服务器没给编号时后端拼出来的是「SNone:None - 集名」，这里认不出就不显示季集。
  private static let episodeRegex = try? NSRegularExpression(
    pattern: #"^S(\d+):E?(\d+)"#, options: .caseInsensitive)

  /// 已播放进度（0…1）。后端没给、为 0 或不是有限数时不画进度条（同 Web 的 `percent > 0`）。
  static func progress(percent: Double?) -> Double? {
    guard let percent, percent.isFinite, percent > 0 else { return nil }
    return min(1, percent / 100)
  }

  /// 角标上的季集：「第 2 季第 5 集」「特别篇第 1 集」，与详情页「继续播放」按钮同一拼法。
  /// 电影没有季集；剧集副标题认不出编号时也不显示。
  static func episodeText(type: String?, subtitle: String?) -> String? {
    guard type == "电视剧", let regex = episodeRegex,
      let subtitle = trimmedNonEmpty([subtitle])
    else { return nil }
    let nsSubtitle = subtitle as NSString
    guard
      let match = regex.firstMatch(
        in: subtitle, options: [], range: NSRange(location: 0, length: nsSubtitle.length)),
      let season = Int(nsSubtitle.substring(with: match.range(at: 1))),
      let episode = Int(nsSubtitle.substring(with: match.range(at: 2)))
    else { return nil }
    return SeriesPlayAction.episodeText(season: season, episode: episode)
  }

  /// 按标题识别、搜索资源和字幕用的媒体信息。只有电影的副标题可能是年份：Emby、Jellyfin、Plex 等给
  /// `ProductionYear`，飞牛和绿联给的是「电影」「视频」这类类型名。不是年份就不传——否则严格匹配必然落空，
  /// 退回识别时还会把类型名拼进查询串。剧集的副标题是季集和集名（绿联是剧名），一律不当年份。
  static func mediaInfo(title: String, type: String?, subtitle: String?) -> MediaInfo {
    MediaInfo(title: title, type: type, year: type == "电影" ? year(subtitle) : nil)
  }

  /// 四位数字才算年份（后端给的是 `str(ProductionYear)`）。
  private static func year(_ subtitle: String?) -> String? {
    guard let value = trimmedNonEmpty([subtitle]), value.count == 4,
      value.allSatisfy({ $0.isASCII && $0.isNumber })
    else { return nil }
    return value
  }
}