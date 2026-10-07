import Foundation

@testable import MoviePilot_TV

/// 列表网络替身的 JSON 字段字典；生产 Subscribe 保持仅 Decodable，不能作为写入请求编码。
nonisolated enum SubscribeResponseFixture {
  static func data(for subscriptions: [Subscribe]) throws -> Data {
    let objects = try subscriptions.map { subscription -> [String: Any] in
      let fields: [String: Any?] = [
        "id": subscription.id,
        "name": subscription.name,
        "year": subscription.year,
        "type": subscription.type,
        "keyword": subscription.keyword,
        "season": subscription.season,
        "poster": subscription.poster,
        "backdrop": subscription.backdrop,
        "state": subscription.state,
        "last_update": subscription.last_update,
        "vote": subscription.vote,
        "total_episode": subscription.total_episode,
        "start_episode": subscription.start_episode,
        "lack_episode": subscription.lack_episode,
        "completed_episode": subscription.completed_episode,
        "tmdbid": subscription.tmdbid,
        "doubanid": subscription.doubanid,
        "bangumiid": subscription.bangumiid,
        "anilistid": subscription.anilistid,
        "media_source": subscription.media_source,
        "media_id": subscription.media_id,
        "quality": subscription.quality,
        "resolution": subscription.resolution,
        "effect": subscription.effect,
        "include": subscription.include,
        "exclude": subscription.exclude,
        "sites": subscription.sites,
        "downloader": subscription.downloader,
        "save_path": subscription.save_path,
        "best_version": subscription.best_version,
        "best_version_full": subscription.best_version_full,
        "current_priority": subscription.current_priority,
        "filter_groups": subscription.filter_groups,
        "custom_words": subscription.custom_words,
        "description": subscription.description,
        "filter": subscription.filter,
        "episode_group": subscription.episode_group,
        "search_imdbid": subscription.search_imdbid,
        "media_category": subscription.media_category,
        "mediaid": subscription.mediaid,
        "episode_priority": subscription.episode_priority,
        "username": subscription.username,
        "date": subscription.date,
        "search_interval": subscription.search_interval,
        "music_type": subscription.music_type,
        "total_tracks": subscription.total_tracks,
        "audio_quality": subscription.audio_quality,
        "audio_format": subscription.audio_format,
        "min_bitrate": subscription.min_bitrate,
        "min_bit_depth": subscription.min_bit_depth,
        "min_sample_rate": subscription.min_sample_rate,
        "media_category_id": subscription.media_category_id,

      ]
      var object = fields.compactMapValues { $0 }
      if let note = subscription.note {
        object["note"] = try JSONSerialization.jsonObject(
          with: JSONEncoder().encode(note), options: .fragmentsAllowed)
      }
      return object
    }
    return try JSONSerialization.data(withJSONObject: objects)
  }
}
