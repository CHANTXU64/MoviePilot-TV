import Foundation

/// 用户在单集面板里确认过“就是这一集”的文件，存在本机（不同步到别的设备）。
/// 按 MoviePilot 地址、账号和媒体服务器分开：换了账号或服务器不沿用。每条记着确认时的文件路径，换了文件就不算
/// （见 `EpisodeMatchLoader.userConfirmed`）。
@MainActor
final class EpisodeConfirmationStore {
  static let shared = EpisodeConfirmationStore()

  private static let storageKey = "episodeUserConfirmations.v1"

  private let defaults: UserDefaults
  /// 最多记这么多条，超出时丢最早确认的。
  private let capacity: Int
  /// 命名空间 → 服务器条目 ID → 确认记录
  private var cache: [String: [String: EpisodeUserConfirmation]]?

  init(defaults: UserDefaults = .standard, capacity: Int = 5000) {
    self.defaults = defaults
    self.capacity = capacity
  }

  /// 命名空间：MoviePilot 地址、账号和 MoviePilot 里的媒体服务器名称。
  static func namespace(baseURL: String, userName: String?, server: String) -> String {
    [baseURL, userName ?? "", server].joined(separator: "\u{1F}")
  }

  func confirmations(in namespace: String) -> [String: EpisodeUserConfirmation] {
    load()[namespace] ?? [:]
  }

  func confirm(itemID: String, path: String?, tmdbEpisodeID: Int, in namespace: String, at date: Date = Date()) {
    var all = load()
    all[namespace, default: [:]][itemID] = EpisodeUserConfirmation(
      tmdbEpisodeID: tmdbEpisodeID, path: path, confirmedAt: date)
    let total = all.values.reduce(0) { $0 + $1.count }
    if total > capacity {
      let oldest = all.flatMap { space, entries in entries.map { (space, $0.key, $0.value.confirmedAt) } }
        .sorted { $0.2 < $1.2 }.prefix(total - capacity)
      for (space, item, _) in oldest { all[space]?[item] = nil }
    }
    save(all)
  }

  func forget(itemID: String, in namespace: String) {
    var all = load()
    guard all[namespace]?[itemID] != nil else { return }
    all[namespace]?[itemID] = nil
    if all[namespace]?.isEmpty == true { all[namespace] = nil }
    save(all)
  }

  private func load() -> [String: [String: EpisodeUserConfirmation]] {
    if let cache { return cache }
    let decoded = defaults.data(forKey: Self.storageKey).flatMap {
      try? JSONDecoder().decode([String: [String: EpisodeUserConfirmation]].self, from: $0)
    }
    cache = decoded ?? [:]
    return cache ?? [:]
  }

  private func save(_ all: [String: [String: EpisodeUserConfirmation]]) {
    cache = all
    do {
      defaults.set(try JSONEncoder().encode(all), forKey: Self.storageKey)
    } catch {
      Logger.warning("[Playback] 没能保存确认过的单集：\(error.localizedDescription)")
    }
  }
}
