import Foundation

enum ManualMediaSelection {
  static func displayTitle(for media: MediaInfo) -> String {
    let title = MediaIdentifier.normalizedString(media.title) ?? "未命名媒体"
    guard let year = MediaIdentifier.normalizedString(media.year) else { return title }
    return "\(title)（\(year)）"
  }

  static func mediaId(for media: MediaInfo, source: MediaSearchSource) -> String? {
    let nativeId: String? =
      switch source {
      case .themoviedb: MediaIdentifier.validNumericIdentifier(media.tmdb_id).map(String.init)
      case .douban: media.douban_id
      case .bangumi: MediaIdentifier.validNumericIdentifier(media.bangumi_id).map(String.init)
      case .anilist: MediaIdentifier.validNumericIdentifier(media.anilist_id).map(String.init)
      }
    for candidate in [nativeId, media.media_id] {
      let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
      if normalized?.isEmpty == false {
        return normalized
      }
    }
    return nil
  }

  static func typeName(for media: MediaInfo) -> String? {
    switch media.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "电影", "movie": "电影"
    case "电视剧", "tv", "series": "电视剧"
    default: nil
    }
  }
}
