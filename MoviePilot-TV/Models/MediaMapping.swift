import Foundation

/// 非 TMDB 来源到 TMDB 的映射关系（`GET /media/mapping`、`POST /media/mapping/match`）。
///
/// 后端在未命中或未启用共享识别时返回 `data: null`；解码后为 `nil`。
nonisolated struct MediaMapping: Codable, Equatable, Sendable {
  let media_source: String
  let media_id: String
  let type: String
  let season: Int?
  let tmdb_id: Int
  let tmdb_type: String
  let tmdb_season: Int?
}
