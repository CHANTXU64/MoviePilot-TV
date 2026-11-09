enum EpisodeGroupPickerOptions {
  /// 只把明确为 0 季或 0 集的组选项移到末尾，两部分各自保留原顺序。
  static func make(_ groups: [EpisodeGroup], defaultSeasons: [TmdbSeason]?) -> [PickerOption<String>] {
    let defaultCounts = defaultGroupCounts(defaultSeasons)
    let entries = [MenuEntry(id: "", name: "默认", seasons: defaultCounts.seasons, episodes: defaultCounts.episodes)]
      + groups.map { MenuEntry(id: $0.id, name: $0.name, seasons: $0.group_count, episodes: $0.episode_count) }
    return (entries.filter { !$0.hasZeroCount } + entries.filter(\.hasZeroCount)).map(\.option)
  }

  private static func defaultGroupCounts(_ seasons: [TmdbSeason]?) -> (seasons: Int?, episodes: Int?) {
    guard let seasons, !seasons.isEmpty else { return (nil, nil) }
    let episodeCounts = seasons.compactMap(\.episode_count)
    let episodeCount = episodeCounts.count == seasons.count ? episodeCounts.reduce(0, +) : nil
    return (seasons.count, episodeCount)
  }

  private struct MenuEntry {
    let id: String
    let name: String
    let seasons: Int?
    let episodes: Int?

    var hasZeroCount: Bool { seasons == 0 || episodes == 0 }

    var option: PickerOption<String> {
      let counts = [seasons.map { "\($0) 季" }, episodes.map { "\($0) 集" }].compactMap { $0 }
      return PickerOption(
        title: EpisodeGroupDisplayFormatter.name(name), value: id,
        detail: counts.isEmpty ? nil : counts.joined(separator: " · ")
      )
    }
  }
}
