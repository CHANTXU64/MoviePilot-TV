import Foundation

/// 非 TMDB 来源到 TMDB 的共享映射（`GET /media/mapping`）。
///
/// 后端在未命中、未启用共享识别或查询失败时返回 `data: null`；解码后为 `nil`。
nonisolated struct MediaMapping: Codable, Equatable, Sendable {
  let media_source: String
  let media_id: String
  let type: String
  let season: Int?
  let tmdb_id: Int
  let tmdb_type: String
  let tmdb_season: Int?
}
