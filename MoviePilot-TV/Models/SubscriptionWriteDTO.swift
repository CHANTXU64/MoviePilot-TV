import Foundation

/// 订阅保存（PUT /subscribe/）的请求体。已登记的 MoviePilot 版本（v3.0.4 至 v3.1.0）订阅数据结构一致，
/// 后端只更新请求里出现的键：
/// - 解码时读到的键都回传：有值发值，值为 nil 发 null（表示清空）；没读到的键省略，表示不修改。
/// - 字符串原样发送，不 trim 正则、路径或识别词；下载器“默认”由编辑边界表达为 nil。
/// - 只发送用户可编辑的字段，不回写状态、计数、洗版运行优先级等后端维护字段，也不回写旧的 tmdbid / doubanid / mediaid。
/// id 用于定位 PUT 目标。
nonisolated struct SubscriptionWriteDTO: Encodable {
  private let subscription: Subscribe
  private typealias CodingKeys = Subscribe.CodingKeys

  init(_ subscription: Subscribe) {
    self.subscription = subscription
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let s = subscription
    try container.encodeIfPresent(s.id, forKey: .id)
    try encodeRequired(s.name, forKey: .name, to: &container)
    try encode(s.year, forKey: .year, to: &container)
    try encodeRequired(s.type, forKey: .type, to: &container)
    try encode(s.search_interval, forKey: .search_interval, to: &container)
    try encode(s.keyword, forKey: .keyword, to: &container)
    try encode(s.media_source, forKey: .media_source, to: &container)
    try encode(s.media_id, forKey: .media_id, to: &container)
    try encode(s.music_type, forKey: .music_type, to: &container)
    try encode(s.total_tracks, forKey: .total_tracks, to: &container)
    try encode(s.season, forKey: .season, to: &container)
    try encode(s.filter, forKey: .filter, to: &container)
    try encode(s.include, forKey: .include, to: &container)
    try encode(s.exclude, forKey: .exclude, to: &container)
    try encode(s.quality, forKey: .quality, to: &container)
    try encode(s.resolution, forKey: .resolution, to: &container)
    try encode(s.effect, forKey: .effect, to: &container)
    try encode(s.audio_quality, forKey: .audio_quality, to: &container)
    try encode(s.audio_format, forKey: .audio_format, to: &container)
    try encode(s.min_bitrate, forKey: .min_bitrate, to: &container)
    try encode(s.min_bit_depth, forKey: .min_bit_depth, to: &container)
    try encode(s.min_sample_rate, forKey: .min_sample_rate, to: &container)
    try encode(s.total_episode, forKey: .total_episode, to: &container)
    try encode(s.start_episode, forKey: .start_episode, to: &container)
    try encode(s.sites, forKey: .sites, to: &container)
    try encode(s.downloader, forKey: .downloader, to: &container)
    try encode(s.best_version, forKey: .best_version, to: &container)
    try encode(s.best_version_full, forKey: .best_version_full, to: &container)
    try encode(s.save_path, forKey: .save_path, to: &container)
    try encode(s.search_imdbid, forKey: .search_imdbid, to: &container)
    try encode(s.custom_words, forKey: .custom_words, to: &container)
    try encodeCategory(to: &container)
    try encode(s.filter_groups, forKey: .filter_groups, to: &container)
    try encode(s.episode_group, forKey: .episode_group, to: &container)
  }

  private func encode<Value: Encodable>(
    _ value: Value?,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if let value {
      try container.encode(value, forKey: key)
    } else if subscription.decodedKeys.contains(key) {
      try container.encodeNil(forKey: key)
    }
  }

  /// name / type 在模型里是非可选字符串，缺键或 null 解码为空串；空串按 nil 处理，不虚构空名称。
  private func encodeRequired(
    _ value: String,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    try encode(value.isEmpty ? nil : value, forKey: key, to: &container)
  }

  /// 未编辑时保留稳定 ID；编辑路径时省略旧 ID，避免后端用旧分类覆盖新路径。
  /// ID:null 会同时清空路径，因此路径编辑和清空都只发送路径键。
  private func encodeCategory(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
    if subscription.mediaCategoryWasEdited {
      let path = subscription.media_category
      try container.encode(path == "" ? nil : path, forKey: .media_category)
      return
    }
    if let categoryID = subscription.media_category_id, !categoryID.isEmpty {
      try container.encode(categoryID, forKey: .media_category_id)
    }
    try encode(subscription.media_category, forKey: .media_category, to: &container)
  }
}
