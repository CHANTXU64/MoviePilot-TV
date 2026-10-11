import Foundation

/// 只传递过滤/排序需要的不可变值；完整 Context 仍由搜索 owner 持有。
nonisolated struct ResourceFilterInput: Sendable {
  let id: String
  let order: Int
  let content: String
  let hasTorrent: Bool
  let size: Int64
  let episodes: Int
  let seeders: Int
  let peers: Int
  let priority: Int
  let pubdate: String
  let fields: [String: String]

  @MainActor init(context: Context, id: String = "", order: Int = 0) {
    self.id = id
    self.order = order
    let torrent = context.torrent_info
    content = "\(torrent?.title ?? "") \(torrent?.description ?? "") \((torrent?.labels ?? []).joined(separator: " "))"
    hasTorrent = torrent != nil
    size = torrent?.size ?? 0
    episodes = max(context.meta_info?.total_episode ?? 1, 1)
    seeders = torrent?.seeders ?? 0
    peers = torrent?.peers ?? 0
    priority = torrent?.pri_order ?? 0
    pubdate = torrent?.pubdate ?? ""
    fields = ResourceResultSemantics.fields(context)
  }
}

nonisolated enum ResourceResultSemantics {
  @MainActor static func normalized(_ value: String?) -> String {
    MediaIdentifier.normalizedString(value) ?? "无"
  }

  @MainActor static func freeState(_ context: Context) -> String? {
    MediaIdentifier.normalizedString(context.torrent_info?.volume_factor)
  }

  @MainActor static func fields(_ context: Context) -> [String: String] {
    [
      "site": normalized(context.torrent_info?.site_name),
      "season": normalized(context.meta_info?.season_episode),
      "resolution": normalized(context.meta_info?.resource_pix),
      "videoCode": normalized(context.meta_info?.video_encode),
      "edition": normalized(context.meta_info?.edition),
      "releaseGroup": normalized(context.meta_info?.resource_team),
    ].merging(freeState(context).map { ["freeState": $0] } ?? [:]) { _, value in value }
  }

  static func matches(_ fields: [String: String], filters: [String: Set<String>]) -> Bool {
    filters.allSatisfy { key, values in
      switch key {
      case "site", "season", "resolution", "videoCode", "edition", "releaseGroup", "freeState":
        values.isEmpty || fields[key].map(values.contains) == true
      default: true
      }
    }
  }

  @MainActor static func sortedOptions(_ options: [String: [String]]) -> [String: [String]] {
    var sorted = options.mapValues { values in
      values.sorted { a, b in a == "无" ? false : b == "无" ? true : a < b }
    }
    if let seasons = sorted["season"] { sorted["season"] = ParsedSeason.sortSeasonOptions(seasons) }
    return sorted
  }

  static func dateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }

  static func before(_ lhs: ResourceFilterInput, softRejected leftSoft: Bool,
    _ rhs: ResourceFilterInput, softRejected rightSoft: Bool, sortField: String, sortType: String) -> Bool
  {
    if leftSoft != rightSoft { return !leftSoft }
    let a = lhs, b = rhs
    if sortType == "默认排序" { return a.order < b.order }
    let ascending = sortType == "升序"
    if sortField == "时间", a.pubdate != b.pubdate {
      return ascending ? a.pubdate < b.pubdate : a.pubdate > b.pubdate
    }
    let x: Int64, y: Int64
    switch sortField {
    case "大小": (x, y) = (a.size, b.size)
    case "做种": (x, y) = (Int64(a.seeders), Int64(b.seeders))
    case "下载": (x, y) = (Int64(a.peers), Int64(b.peers))
    case "时间": return a.order < b.order
    default: (x, y) = (Int64(a.priority), Int64(b.priority))
    }
    return x == y ? a.order < b.order : ascending ? x < y : x > y
  }
}
