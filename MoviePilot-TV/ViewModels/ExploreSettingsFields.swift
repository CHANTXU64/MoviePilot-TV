import SwiftUI

/// 设置页使用探索页的选项与绑定，只改变呈现方式。
@MainActor
struct ExploreSettingsField: Identifiable {
  let id: String
  let title: String
  let kind: PluginFilterControl.Kind
  let options: [PluginFilterOption]
  let value: Binding<JSONValue>

  var summary: String {
    if kind == .multiChoice {
      let selected = value.wrappedValue.arrayValue ?? []
      if selected.isEmpty { return "全部" }
      return selected.map { item in
        options.first { $0.value == item }?.title ?? item.queryString ?? "默认"
      }.joined(separator: "、")
    }
    return options.first { $0.value == value.wrappedValue }?.title
      ?? value.wrappedValue.queryString.flatMap { $0.isEmpty ? nil : $0 } ?? "默认"
  }
}

extension ExploreViewModel {
  var settingsFields: [ExploreSettingsField] {
    func choice<T: Hashable>(
      _ id: String, _ title: String, _ keyPath: ReferenceWritableKeyPath<ExploreViewModel, T>,
      _ options: [(T, String)], encode: @escaping (T) -> JSONValue,
      decode: @escaping (JSONValue) -> T?
    ) -> ExploreSettingsField {
      ExploreSettingsField(
        id: id, title: title, kind: .choice,
        options: options.map { PluginFilterOption(value: encode($0.0), title: $0.1) },
        value: Binding(
          get: { encode(self[keyPath: keyPath]) },
          set: { if let value = decode($0) { self[keyPath: keyPath] = value } }))
    }
    func text(
      _ id: String, _ title: String, _ keyPath: ReferenceWritableKeyPath<ExploreViewModel, String>,
      _ options: [(key: String, value: String)], all: Bool = false
    ) -> ExploreSettingsField {
      choice(
        id, title, keyPath, (all ? [("", "全部")] : []) + options,
        encode: JSONValue.string, decode: { $0.stringValue })
    }
    func number(
      _ id: String, _ title: String, _ keyPath: ReferenceWritableKeyPath<ExploreViewModel, Int>,
      _ options: [(Int, String)]
    ) -> ExploreSettingsField {
      choice(
        id, title, keyPath, options, encode: JSONValue.int,
        decode: {
          if case .int(let value) = $0 { return value }
          return nil
        })
    }
    let ratings = [(0, "不限")] + (5...10).map { ($0, "\($0) 分以上") }
    let type = ExploreSettingsField(
      id: "type", title: "类型", kind: .choice,
      options: DiscoverMediaType.allCases.map {
        PluginFilterOption(value: .string($0.rawValue), title: $0.rawValue)
      },
      value: Binding(
        get: { .string(self.selectedType.rawValue) },
        set: {
          guard let raw = $0.stringValue, let type = DiscoverMediaType(rawValue: raw) else {
            return
          }
          self.selectedType = type
          self.onTypeChanged()
        }))
    switch selectedSource {
    case .themoviedb:
      return [
        type,
        text("sort", "排序", \.tmdbSortBy, currentSortDict),
        text("genre", "风格", \.tmdbGenre, currentGenreDict, all: true),
        text("language", "语言", \.tmdbLanguage, Self.tmdbLanguageDict, all: true),
        number("rating", "评分", \.tmdbVoteAverage, ratings),
        number(
          "votes", "评分人数", \.tmdbVoteCount,
          [10, 100, 500, 1_000, 5_000, 10_000].map { ($0, "\($0) 人以上") }),
      ]
    case .douban:
      return [
        type,
        text("sort", "排序", \.doubanSort, Self.doubanSortDict),
        text("genre", "风格", \.doubanCategory, Self.doubanCategoryDict, all: true),
        text("zone", "地区", \.doubanZone, Self.doubanZoneDict, all: true),
        text("year", "年代", \.doubanYear, Self.doubanYearDict, all: true),
      ]
    case .bangumi:
      return [
        text("category", "类别", \.bangumiCat, Self.bangumiCatDict, all: true),
        text("sort", "排序", \.bangumiSort, Self.bangumiSortDict),
        text("year", "年份", \.bangumiYear, Self.bangumiYearDict, all: true),
      ]
    case .anilist:
      return [
        text("sort", "排序", \.anilistSort, Self.anilistSortDict),
        text("format", "形式", \.anilistFormat, Self.anilistFormatDict, all: true),
        text("genre", "风格", \.anilistGenre, Self.anilistGenreDict, all: true),
        text("season", "季度", \.anilistSeason, Self.anilistSeasonDict, all: true),
        number("year", "年份", \.anilistYear, [(0, "全部")] + Self.anilistYearDict),
        text("status", "状态", \.anilistStatus, Self.anilistStatusDict, all: true),
        text("country", "地区", \.anilistCountry, Self.anilistCountryDict, all: true),
      ]
    case .popular:
      return [
        type,
        text("sort", "排序", \.popularSortBy, currentSortDict),
        text("genre", "风格", \.popularGenre, currentGenreDict, all: true),
        number("rating", "评分", \.popularMinRating, ratings),
      ]
    case .subscriptionShare:
      return [
        text("sort", "排序", \.shareSortBy, currentSortDict),
        text("genre", "风格", \.shareGenre, currentGenreDict, all: true),
        number("rating", "评分", \.shareMinRating, ratings),
      ]
    case .custom:
      return pluginFilterControls.filter { $0.isVisible(in: pluginFilterValues) }.map { control in
        ExploreSettingsField(
          id: control.field, title: control.label, kind: control.kind, options: control.options,
          value: Binding(
            get: { control.selectionValue(from: self.pluginFilterValues[control.field] ?? .null) },
            set: { self.setPluginFilter(control.field, value: control.storedValue(for: $0)) }))
      }
    }
  }
}
