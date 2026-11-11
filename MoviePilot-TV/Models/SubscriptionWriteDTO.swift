import Foundation

/// PUT /subscribe/ 只更新请求中出现的字段。编辑会话提供原始值与草稿，未改字段省略，
/// 改为 nil 的字段发 null；正则、路径和识别词保留原值。后端维护字段不参与写入。
nonisolated struct SubscriptionWriteDTO: Encodable {
  let original: Subscribe
  let draft: Subscribe
  private typealias CodingKeys = Subscribe.CodingKeys

  func encode(to encoder: Encoder) throws {
    guard let id = original.id, id > 0, draft.id == id else {
      throw EncodingError.invalidValue(
        draft.id as Any,
        .init(
          codingPath: encoder.codingPath, debugDescription: "订阅编辑目标必须保持有效且一致。"))
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try encodeChange(original.name, draft.name, forKey: .name, to: &container)
    try encodeChange(original.year, draft.year, forKey: .year, to: &container)
    try encodeChange(original.type, draft.type, forKey: .type, to: &container)
    try encodeChange(
      original.search_interval, draft.search_interval, forKey: .search_interval, to: &container)
    try encodeChange(original.keyword, draft.keyword, forKey: .keyword, to: &container)
    try encodeChange(original.music_type, draft.music_type, forKey: .music_type, to: &container)
    try encodeChange(
      original.total_tracks, draft.total_tracks, forKey: .total_tracks, to: &container)
    try encodeChange(original.season, draft.season, forKey: .season, to: &container)
    try encodeChange(original.filter, draft.filter, forKey: .filter, to: &container)
    try encodeChange(original.include, draft.include, forKey: .include, to: &container)
    try encodeChange(original.exclude, draft.exclude, forKey: .exclude, to: &container)
    try encodeChange(original.quality, draft.quality, forKey: .quality, to: &container)
    try encodeChange(original.resolution, draft.resolution, forKey: .resolution, to: &container)
    try encodeChange(original.effect, draft.effect, forKey: .effect, to: &container)
    try encodeChange(
      original.audio_quality, draft.audio_quality, forKey: .audio_quality, to: &container)
    try encodeChange(
      original.audio_format, draft.audio_format, forKey: .audio_format, to: &container)
    try encodeChange(original.min_bitrate, draft.min_bitrate, forKey: .min_bitrate, to: &container)
    try encodeChange(
      original.min_bit_depth, draft.min_bit_depth, forKey: .min_bit_depth, to: &container)
    try encodeChange(
      original.min_sample_rate, draft.min_sample_rate, forKey: .min_sample_rate, to: &container)
    try encodeChange(
      original.total_episode, draft.total_episode, forKey: .total_episode, to: &container)
    try encodeChange(
      original.start_episode, draft.start_episode, forKey: .start_episode, to: &container)
    try encodeChange(original.sites, draft.sites, forKey: .sites, to: &container)
    try encodeChange(original.downloader, draft.downloader, forKey: .downloader, to: &container)
    try encodeChange(
      original.best_version, draft.best_version, forKey: .best_version, to: &container)
    try encodeChange(
      original.best_version_full, draft.best_version_full, forKey: .best_version_full,
      to: &container)
    try encodeChange(original.save_path, draft.save_path, forKey: .save_path, to: &container)
    try encodeChange(
      original.search_imdbid, draft.search_imdbid, forKey: .search_imdbid, to: &container)
    try encodeChange(
      original.custom_words, draft.custom_words, forKey: .custom_words, to: &container)
    try encodeChange(
      original.filter_groups, draft.filter_groups, forKey: .filter_groups, to: &container)
    try encodeChange(
      original.episode_group, draft.episode_group, forKey: .episode_group, to: &container)
    // 后端要求媒体身份的两个键共同出现，避免只改来源或 ID 形成半个身份。
    if original.media_source != draft.media_source || original.media_id != draft.media_id {
      try container.encode(draft.media_source, forKey: .media_source)
      try container.encode(draft.media_id, forKey: .media_id)
    }
    try encodeCategory(to: &container)
  }

  private func encodeChange<Value: Encodable & Equatable>(
    _ original: Value, _ draft: Value,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    guard original != draft else { return }
    try container.encode(draft, forKey: key)
  }

  private func encodeCategory(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
    if original.media_category != draft.media_category {
      // 分类 ID 优先于路径；路径修改必须省略旧 ID。ID:null 会同时清空路径。
      let path = draft.media_category
      try container.encode(path == "" ? nil : path, forKey: .media_category)
    } else {
      try encodeChange(
        original.media_category_id, draft.media_category_id,
        forKey: .media_category_id, to: &container)
    }
  }
}
