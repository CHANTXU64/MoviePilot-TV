import SwiftUI
import Combine

@MainActor
class MediaActionHandler: ObservableObject {
  @Published var isRecognizingTmdb = false
  @Published var showTMDBNotFoundAlert = false

  func searchResourcesTarget(
    for item: MediaInfo, sites: String? = nil
  ) -> ResourceSearchRequest {
    return ResourceSearchRequest(
      keyword: item.apiMediaId ?? "",
      type: item.type,
      area: "title",
      title: item.title ?? "Unknown",
      year: item.year,
      season: item.season,
      mediaInfo: item,
      sites: sites
    )
  }

  func getTMDBJumpTarget(
    for item: MediaInfo, targetTmdbId: Int? = nil
  ) async -> MediaInfo? {
    var tmdbIdToUse: Int? = targetTmdbId ?? item.tmdb_id

    if tmdbIdToUse == nil && (item.douban_id != nil || item.bangumi_id != nil) {
      let queryTitle = item.year != nil ? "\(item.title ?? "") \(item.year!)" : (item.title ?? "")
      if !queryTitle.trimmingCharacters(in: .whitespaces).isEmpty {
        isRecognizingTmdb = true
        do {
          let recognizeResult = try await APIService.shared.recognizeMedia(title: queryTitle)
          tmdbIdToUse = recognizeResult.media_info?.tmdb_id
        } catch {
          print("Error recognizing tmdb_id: \(error)")
        }
        isRecognizingTmdb = false
      }
    }

    guard let tmdbId = tmdbIdToUse else {
      showTMDBNotFoundAlert = true
      return nil
    }

    return MediaInfo(
      tmdb_id: tmdbId,
      douban_id: nil,
      bangumi_id: nil,
      imdb_id: nil,
      tvdb_id: nil,
      source: "tmdb",
      mediaid_prefix: nil,
      media_id: nil,
      title: item.title,
      original_title: item.original_title,
      original_name: item.original_name,
      names: item.names,
      type: item.type,
      year: item.year,
      season: item.season,
      // 必须将图像路径设为 nil。
      // 此处创建的 MediaInfo 是一个用于导航的“部分对象”。
      // 如果保留旧的 poster/backdrop 路径，新页面在加载完成前会短暂显示旧页面的图像，导致闪烁。
      // 将其设为 nil 可确保新页面在获取到自己的完整详情前不显示任何背景。
      poster_path: nil,
      backdrop_path: nil,
      overview: item.overview,
      vote_average: item.vote_average,
      popularity: item.popularity,
      season_info: nil,  // 该信息将在 MediaDetailView 中获取
      collection_id: item.collection_id,
      directors: item.directors,
      actors: item.actors,
      episode_group: item.episode_group,
      runtime: item.runtime,
      release_date: item.release_date,
      original_language: item.original_language,
      production_countries: item.production_countries,
      genres: item.genres,
      category: item.category
    )
  }
}
