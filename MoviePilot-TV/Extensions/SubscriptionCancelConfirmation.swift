import Foundation

enum SubscriptionCancelConfirmation {
  static let title = "取消订阅"
  static let confirmButtonTitle = "确认取消订阅"
  static let failureMessage = "取消订阅失败，请重试"

  static func headerMessage(for media: MediaInfo) -> String {
    message(title: media.cleanedTitle ?? media.title ?? "")
  }

  /// 按片名找到、又分辨不出是不是同一部的订阅：不在这里取消。
  struct UnverifiedRecord: Error {}
  static let unverifiedRecordMessage = "这条订阅是按片名找到的，无法确认是同一部，请到订阅列表里取消。"

  /// 电影按 TMDB 目标冻结的订阅。目标只靠片名猜出、记录又不是按原来源找到的，
  /// 写出实际要取消的那条，请用户确认是同一部。片名相同、又缺年份时用户分辨不出，抛出 `UnverifiedRecord`。
  static func headerMessage(
    for media: MediaInfo,
    cancelling subscription: ExactMovieSubscription,
    isNameRecognized: Bool
  ) throws -> String {
    let base = headerMessage(for: media)
    guard isNameRecognized, !subscription.matchesOrigin else { return base }
    let title = trimmed(subscription.name)
    let year = trimmed(subscription.year)
    let sameTitle = [media.title, media.cleanedTitle].contains {
      trimmed($0).caseInsensitiveCompare(title) == .orderedSame
    }
    guard !title.isEmpty, !(sameTitle && (year.isEmpty || trimmed(media.year).isEmpty)) else {
      throw UnverifiedRecord()
    }
    let yearText = year.isEmpty ? "" : "（\(year)）"
    return "\(base)\n\n将取消的订阅是《\(title)》\(yearText)，是按片名找到的，请确认是同一部。"
  }

  private static func trimmed(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
      return EpisodeGroupDisplayFormatter.name(group.name)
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
