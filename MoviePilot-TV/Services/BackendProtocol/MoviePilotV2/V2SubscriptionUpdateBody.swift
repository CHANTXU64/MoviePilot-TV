import Foundation

/// MoviePilot v2 的 `PUT /subscribe/` 是整条替换：后端把请求模型（含默认值）全量落库，
/// 请求里没出现的字段会被 `None`/`0`/`[]` 覆盖。v3 才改成只写请求中出现的字段。
///
/// 因此 v2 必须提交完整快照，而不是 `SubscriptionWriteDTO` 的稀疏变更；编辑里没动过的
/// 站点、保存路径、过滤组等才不会被清空。这里只列 v2 认识且允许公共写入的字段。
///
/// `includesStableClassificationID` 只给 `UnresolvedBackendEndpoints` 用：版本读不出时后端
/// 可能是 v3，v3.2.9 收到只有 `media_category` 路径的载荷会把 `media_category_id` 清空，
/// 因此补发已有的稳定 ID。v2 不认识这个键（pydantic 默认忽略未知字段），不会受影响。
nonisolated struct V2SubscriptionUpdateBody: Encodable {
  private typealias CodingKeys = Subscribe.CodingKeys
  let draft: Subscribe
  let includesStableClassificationID: Bool

  init(draft: Subscribe, includesStableClassificationID: Bool = false) {
    self.draft = draft
    self.includesStableClassificationID = includesStableClassificationID
  }

  func encode(to encoder: Encoder) throws {
    guard let id = draft.id, id > 0 else {
      throw EncodingError.invalidValue(
        draft.id as Any,
        .init(codingPath: encoder.codingPath, debugDescription: "订阅更新必须携带有效 ID。"))
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(draft.name, forKey: .name)
    try container.encode(draft.year, forKey: .year)
    try container.encode(draft.type, forKey: .type)
    try container.encode(draft.keyword, forKey: .keyword)
    try container.encode(draft.tmdbid, forKey: .tmdbid)
    try container.encode(draft.doubanid, forKey: .doubanid)
    try container.encode(draft.bangumiid, forKey: .bangumiid)
    try container.encode(draft.anilistid, forKey: .anilistid)
    try container.encode(draft.mediaid, forKey: .mediaid)
    try container.encode(draft.media_source, forKey: .media_source)
    try container.encode(draft.media_id, forKey: .media_id)
    try container.encode(draft.season, forKey: .season)
    try container.encode(draft.filter, forKey: .filter)
    try container.encode(draft.include, forKey: .include)
    try container.encode(draft.exclude, forKey: .exclude)
    try container.encode(draft.quality, forKey: .quality)
    try container.encode(draft.resolution, forKey: .resolution)
    try container.encode(draft.effect, forKey: .effect)
    try container.encode(draft.total_episode, forKey: .total_episode)
    try container.encode(draft.start_episode, forKey: .start_episode)
    try container.encode(draft.sites, forKey: .sites)
    try container.encode(draft.downloader, forKey: .downloader)
    try container.encode(draft.best_version, forKey: .best_version)
    try container.encode(draft.best_version_full, forKey: .best_version_full)
    try container.encode(draft.save_path, forKey: .save_path)
    try container.encode(draft.search_imdbid, forKey: .search_imdbid)
    try container.encode(draft.custom_words, forKey: .custom_words)
    try container.encode(draft.media_category, forKey: .media_category)
    if includesStableClassificationID, let categoryID = draft.media_category_id, !categoryID.isEmpty {
      try container.encode(categoryID, forKey: .media_category_id)
    }
    try container.encode(draft.filter_groups, forKey: .filter_groups)
    try container.encode(draft.episode_group, forKey: .episode_group)
  }
}
