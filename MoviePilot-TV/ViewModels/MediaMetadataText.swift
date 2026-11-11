import Foundation

/// 详情页 Hero 元数据行的显示文本组装。
///
/// F-038 / F-043 / F-046 同源：两个 builder 原先只判「来源字段/数组非空」就无条件
/// append，从不检查**产出的显示串是否为空**；空串与畸形元素会被原样拼进结果，
/// 最后由外层 `joined(separator: " · ")` 渲染成悬空分隔符
/// （`2024 · 中国 /  · 英语`）或一条空 `Text`。三条缺陷实际是同一处 bug 的三个出口，
/// 因此这里把「产出非空」作为统一准入判据，并在叶子层先 trim 再查表。
enum MediaMetadataText {
  /// 第一行：类型/分类 + 类型标签。
  static func primaryLine(for media: MediaInfo) -> [String] {
    var items: [String] = []

    // 分类优先于类型，两者都按显示值归一后再判空。
    if let head = displayValue(media.category) ?? displayValue(media.type) {
      items.append(head)
    }

    if let genres = media.genres, !genres.isEmpty {
      // `compactMap { $0.name }` 只丢 nil，空串不是 nil 会活下来；
      // 这里在翻译后再丢一次空，保证空类型不产出空的 ` · ` 段。
      let names = genres.compactMap { $0.name }
        .map { TranslationHelper.translateGenre(for: $0) }
        .compactMap(displayValue)
      if !names.isEmpty {
        items.append(names.joined(separator: " · "))
      }
    }

    return items
  }

  /// 第二行：上映日期/年份、时长、评分、国家、原语言。
  static func secondaryLine(for media: MediaInfo) -> [String] {
    var items: [String] = []

    // 年份与上映日期互斥，上映日期优先。
    if let releaseDate = displayValue(media.release_date) {
      items.append(releaseDate)
    } else if let year = displayValue(media.year) {
      items.append(year)
    }

    if let runtime = media.runtime {
      items.append("\(runtime) 分钟")
    }

    if let vote = media.vote_average, vote > 0 {
      items.append("评分 \(vote)")
    }

    if let countries = media.production_countries, !countries.isEmpty {
      // 畸形元素（null/数字/空对象）会解码成 (nil, nil) 并返回空串；
      // 判数组非空拦不住它，必须逐项归一后再决定是否拼接。
      let names = countries
        .map { TranslationHelper.countryName(for: $0) }
        .compactMap(displayValue)
      if !names.isEmpty {
        items.append(names.joined(separator: " / "))
      }
    }

    // 只判 non-nil 会让 `""`/`"  "` 穿透；归一后为空则不进入显示行。
    if let language = displayValue(media.original_language),
      let name = displayValue(TranslationHelper.languageName(for: language))
    {
      items.append(name)
    }

    return items
  }

  /// 显示值归一：清理空白与换行，空结果视为「无内容」。
  /// - Returns: 清理后的文本；全为空白时返回 nil，交由调用方丢弃。
  private static func displayValue(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
