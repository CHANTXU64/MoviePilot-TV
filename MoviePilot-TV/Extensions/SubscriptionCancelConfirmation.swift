import Foundation

enum SubscriptionCancelConfirmation {
  static let title = "取消订阅"
  static let confirmButtonTitle = "确认取消订阅"

  static func headerMessage(for media: MediaInfo) -> String {
    message(title: media.cleanedTitle ?? media.title ?? "")
  }

  static func message(for subscribe: Subscribe) -> String {
    let groupText = subscribe.type == "电视剧"
      ? episodeGroupDisplayName(subscribe.episode_group, episodeGroups: [])
      : nil

    return message(
      title: subscribe.name,
      season: subscribe.season,
      episodeGroupText: groupText
    )
  }

  static func message(
    title: String,
    season: Int? = nil,
    episodeGroupText: String? = nil
  ) -> String {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titleText = normalizedTitle.isEmpty ? "该媒体" : "《\(normalizedTitle)》"
    let baseText: String
    if let season {
      baseText = "是否取消\(titleText)\(seasonDisplayText(season))订阅？"
    } else {
      baseText = "是否取消\(titleText)订阅？"
    }

    guard let episodeGroupText else {
      return baseText
    }
    return "\(baseText)\n当前订阅使用：\(episodeGroupText)"
  }

  static func episodeGroupDisplayName(
    _ episodeGroup: String?,
    episodeGroups: [EpisodeGroup]
  ) -> String {
    guard let episodeGroup = normalizedEpisodeGroup(episodeGroup) else {
      return "默认剧集组"
    }
    if let group = episodeGroups.first(where: { $0.id == episodeGroup }) {
      return group.name
    }
    return "剧集组：\(episodeGroup)"
  }

  private static func normalizedEpisodeGroup(_ episodeGroup: String?) -> String? {
    guard let episodeGroup else { return nil }
    let trimmed = episodeGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func seasonDisplayText(_ season: Int) -> String {
    season == 0 ? "特别篇" : "第 \(season) 季"
  }
}
