import Foundation

/// MoviePilot v3.0.4、v3.0.10-1 与 v3.1.0 共用的公共订阅写入合同。
/// 这些标签的 app/schemas/subscribe.py 内容一致；显式列出可写字段，禁止回写运行事实。
/// id 是端点定位 PUT 目标所需的信封字段，不属于后端持久化的公共写入投影。
nonisolated struct SubscriptionWriteDTO: Encodable {
  private let subscription: Subscribe
  private typealias CodingKeys = Subscribe.CodingKeys

  init(_ subscription: Subscribe) {
    self.subscription = subscription
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(subscription.id, forKey: .id)
    try encodeDisplayString(subscription.name, forKey: .name, to: &container)
    try encodeString(subscription.year, forKey: .year, to: &container)
    try encodeDisplayString(subscription.type, forKey: .type, to: &container)
    try encodeValue(subscription.search_interval, forKey: .search_interval, to: &container)
    try encodeString(subscription.keyword, forKey: .keyword, to: &container)
    // 只提交 canonical 身份；旧 tmdbid / doubanid / mediaid 等字段不能进入公共写体。
    try encodeString(subscription.media_source, forKey: .media_source, to: &container)
    try encodeString(subscription.media_id, forKey: .media_id, to: &container)
    try encodeString(subscription.music_type, forKey: .music_type, to: &container)
    try encodeValue(subscription.total_tracks, forKey: .total_tracks, to: &container)
    try encodeValue(subscription.season, forKey: .season, to: &container)
    try encodeString(subscription.filter, forKey: .filter, to: &container)
    try encodeString(subscription.include, forKey: .include, to: &container)
    try encodeString(subscription.exclude, forKey: .exclude, to: &container)
    try encodeString(subscription.quality, forKey: .quality, to: &container)
    try encodeString(subscription.resolution, forKey: .resolution, to: &container)
    try encodeString(subscription.effect, forKey: .effect, to: &container)
    try encodeString(subscription.audio_quality, forKey: .audio_quality, to: &container)
    try encodeString(subscription.audio_format, forKey: .audio_format, to: &container)
    try encodeValue(subscription.min_bitrate, forKey: .min_bitrate, to: &container)
    try encodeValue(subscription.min_bit_depth, forKey: .min_bit_depth, to: &container)
    try encodeValue(subscription.min_sample_rate, forKey: .min_sample_rate, to: &container)
    try encodeValue(subscription.total_episode, forKey: .total_episode, to: &container)
    try encodeValue(subscription.start_episode, forKey: .start_episode, to: &container)
    try encodeArray(subscription.sites, forKey: .sites, to: &container)
    try encodeString(subscription.downloader, forKey: .downloader, to: &container)
    try encodeValue(subscription.best_version, forKey: .best_version, to: &container)
    try encodeValue(subscription.best_version_full, forKey: .best_version_full, to: &container)
    try encodeString(subscription.save_path, forKey: .save_path, to: &container)
    try encodeValue(subscription.search_imdbid, forKey: .search_imdbid, to: &container)
    try encodeString(subscription.custom_words, forKey: .custom_words, to: &container)
    try encodeCategory(to: &container)
    try encodeArray(subscription.filter_groups, forKey: .filter_groups, to: &container)
    try encodeString(subscription.episode_group, forKey: .episode_group, to: &container)
  }

  /// 缺键保持省略；已读到的 null 或构造后的显式 nil 赋值才编码为 null。
  private func includes(_ key: CodingKeys) -> Bool {
    subscription.writeFieldPresence.contains(key) || subscription.editedWriteFields.contains(key)
  }

  private func encodeValue<Value: Encodable>(
    _ value: Value?,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if let value {
      try container.encode(value, forKey: key)
    } else if includes(key) {
      try container.encodeNil(forKey: key)
    }
  }

  /// name/type 供既有 UI 使用非可选 String；稀疏响应的缺键/null 不应写成虚构的空串。
  private func encodeDisplayString(
    _ value: String,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    guard includes(key) else { return }
    if subscription.decodedNullWriteFields.contains(key)
      && !subscription.editedWriteFields.contains(key)
    {
      try container.encodeNil(forKey: key)
    } else {
      try container.encode(value, forKey: key)
    }
  }

  /// 编辑清空控件时空串表示 null；其余字符串逐字保留，不 trim 正则、路径或识别词。
  private func encodeString(
    _ value: String?,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if subscription.editedWriteFields.contains(key), value == "" {
      try container.encodeNil(forKey: key)
    } else {
      try encodeValue(value, forKey: key, to: &container)
    }
  }

  /// 未编辑的 null 保持 null；用户清空多选项（nil 或 []）按表单合同发送 []。
  private func encodeArray<Value: Encodable>(
    _ value: [Value]?,
    forKey key: CodingKeys,
    to container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    if value == nil, subscription.editedWriteFields.contains(key) {
      try container.encode([Value](), forKey: key)
    } else {
      try encodeValue(value, forKey: key, to: &container)
    }
  }

  private func encodeCategory(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
    let idWasEdited = subscription.editedWriteFields.contains(.media_category_id)
    let pathWasChanged = subscription.editedWriteFields.contains(.media_category)
      && (subscription.media_category != subscription.originalMediaCategory
        || subscription.media_category == nil || subscription.media_category == "")

    if idWasEdited {
      // 显式清空稳定 ID 的官方语义是同时清空路径。
      if subscription.media_category_id == nil || subscription.media_category_id == "" {
        try container.encodeNil(forKey: .media_category_id)
        try container.encodeNil(forKey: .media_category)
      } else {
        try encodeString(subscription.media_category_id, forKey: .media_category_id, to: &container)
        try encodeString(subscription.media_category, forKey: .media_category, to: &container)
      }
    } else if pathWasChanged {
      // 官方分类解析器优先 ID；携带旧 ID 会覆盖路径编辑，ID:null 又会清空新路径。
      // 仅发路径，让后端按路径解析新分类；path:null 同样能清除原来的稳定引用。
      try encodeString(subscription.media_category, forKey: .media_category, to: &container)
    } else if let categoryID = subscription.media_category_id, !categoryID.isEmpty {
      try container.encode(categoryID, forKey: .media_category_id)
      try encodeString(subscription.media_category, forKey: .media_category, to: &container)
    } else if let path = subscription.media_category, !path.isEmpty {
      // 旧记录可有路径但没有稳定 ID；不能回传 ID:null 导致后端意外清除该路径。
      try container.encode(path, forKey: .media_category)
    } else {
      try encodeString(subscription.media_category_id, forKey: .media_category_id, to: &container)
      try encodeString(subscription.media_category, forKey: .media_category, to: &container)
    }
  }
}
