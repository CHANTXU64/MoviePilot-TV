import Foundation

/// 第三方单集编号对应的 TMDB 默认顺序。使用时还要核对 MoviePilot 的单集 ID 与首播日期。
nonisolated struct ExternalEpisodePlacement: Codable, Equatable, Sendable {
  let season: Int
  let episode: Int
  let airDate: String

  var list: EpisodeListKey { EpisodeListKey(episodeGroup: nil, season: season) }
}

/// Fribb 提供 AniDB 分段的 TMDB/TVDB 季和集号偏移，AniZip 提供分段里的 TVDB 单集 ID。
/// 用整剧 ID 查询 AniZip 会漏掉后续分段，先从目录里找出全部对应的 AniDB ID。
@MainActor
final class ExternalEpisodeMapping {
  private static let catalogURL = URL(
    string: "https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-lists-reduced.json")!
  nonisolated private static let segmentsURL = URL(string: "https://api.ani.zip/mappings")!
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 2
    config.httpMaximumConnectionsPerHost = 4
    return URLSession(configuration: config)
  }()

  static let shared = ExternalEpisodeMapping(
    session: session, directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("ExternalEpisodeMappings-v1", isDirectory: true))

  private let session: URLSession
  private let directory: URL?
  private let catalog = CoalescingCache<URL, [Int: [CatalogRow]]>(
    ttl: 86_400, capacity: 1, renewsTTLOnAccess: false)
  private let shows = CoalescingCache<Int, ShowMapping>(
    ttl: 300, capacity: 16, renewsTTLOnAccess: false)

  init(session: URLSession, directory: URL? = nil) {
    self.session = session
    self.directory = directory
  }

  /// 会话索引等待的总预算。即使离页或超时，共用的查询也可以写好公开映射供下次使用。
  static let lookupBudget: Duration = .milliseconds(1_200)

  func placements(for tmdbID: Int) async throws -> [Int: ExternalEpisodePlacement] {
    let mapping = try await shows.value(
      for: tmdbID, acceptsCachedValue: { $0.expiresAt > Date() }, validate: { try Task.checkCancellation() }
    ) {
      let cacheURL = self.directory?.appendingPathComponent("show-\(tmdbID).json")
      if let cached = await Self.read(ShowMapping.self, from: cacheURL), cached.expiresAt > Date() {
        return cached
      }
      let rows = try await self.catalogRows(for: tmdbID)
      let mapping = try await Self.loadShow(rows, tmdbID: tmdbID, session: self.session)
      if !mapping.episodes.isEmpty {
        await Self.write(mapping, to: cacheURL)
      }
      return mapping
    }
    return mapping.episodes
  }

  private func catalogRows(for tmdbID: Int) async throws -> [CatalogRow] {
    let session = session
    let cacheURL = directory?.appendingPathComponent("catalog.json")
    let url = Self.catalogURL
    let rows = try await catalog.value(for: url, validate: { try Task.checkCancellation() }) {
      try await Self.loadCatalog(url: url, cacheURL: cacheURL, session: session)
    }
    return rows[tmdbID] ?? []
  }

  nonisolated private struct CatalogRow: Decodable, Sendable {
    struct IDs: Decodable { let tv: Int? }
    struct Numbering: Decodable {
      let tvdb: Int?
      let tmdb: Int?
    }

    let anidb_id: Int?
    let tvdb_id: Int?
    let themoviedb_id: IDs?
    let season: Numbering?
    let episode_offset: Numbering?
  }

  nonisolated private struct ShowMapping: Codable, Sendable {
    let expiresAt: Date
    let episodes: [Int: ExternalEpisodePlacement]
  }

  nonisolated private struct Segment: Decodable, Sendable {
    struct IDs: Decodable {
      let anidb_id: Int
      let thetvdb_id: Int
      let themoviedb_id: String
    }

    struct Episode: Decodable {
      let tvdbId: Int?
      let tvdbShowId: Int?
      let seasonNumber: Int?
      let episodeNumber: Int?
      let airDate: String?
    }

    let mappings: IDs
    let episodes: [String: Episode]
  }

  @concurrent
  private static func loadCatalog(url: URL, cacheURL: URL?, session: URLSession) async throws -> [Int: [CatalogRow]] {
    if let cacheURL,
      let values = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]),
      let modified = values.contentModificationDate, Date().timeIntervalSince(modified) < 86_400,
      let data = try? Data(contentsOf: cacheURL),
      let rows = try? JSONDecoder().decode([CatalogRow].self, from: data)
    {
      return catalogIndex(rows)
    }
    let data = try await fetch(url, using: session, limit: 4_000_000)
    let rows = try JSONDecoder().decode([CatalogRow].self, from: data)
    if let cacheURL {
      try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: cacheURL, options: .atomic)
    }
    return catalogIndex(rows)
  }

  nonisolated private static func catalogIndex(_ rows: [CatalogRow]) -> [Int: [CatalogRow]] {
    var index: [Int: [CatalogRow]] = [:]
    for row in rows {
      guard let tmdbID = row.themoviedb_id?.tv, tmdbID > 0, let aniDB = row.anidb_id, aniDB > 0,
        let tvdb = row.tvdb_id, tvdb > 0, (row.season?.tmdb ?? 0) > 0, (row.season?.tvdb ?? 0) > 0
      else { continue }
      index[tmdbID, default: []].append(row)
    }
    return index
  }

  @concurrent
  private static func loadShow(_ rows: [CatalogRow], tmdbID: Int, session: URLSession) async throws -> ShowMapping {
    let segments = Dictionary(grouping: rows, by: \.anidb_id)
    // 每个分段只发一次。超长作品可以继续使用其他匹配依据。
    guard segments.count <= 12 else { return ShowMapping(expiresAt: Date().addingTimeInterval(300), episodes: [:]) }
    let combined = try await withThrowingTaskGroup(of: [Int: [ExternalEpisodePlacement]].self) { group in
      for (id, rows) in segments {
        guard let id else { continue }
        group.addTask {
          let url = Self.segmentsURL.appending(queryItems: [URLQueryItem(name: "anidb_id", value: String(id))])
          let data: Data
          do {
            data = try await fetch(url, using: session, limit: 2_000_000)
          } catch FetchError.notFound {
            return [:]
          }
          let response = try JSONDecoder().decode(Segment.self, from: data)
          guard response.mappings.anidb_id == id, Int(response.mappings.themoviedb_id) == tmdbID else { return [:] }
          return placements(from: response, rows: rows)
        }
      }
      var merged: [Int: [ExternalEpisodePlacement]] = [:]
      for try await candidates in group { merged.merge(candidates) { $0 + $1 } }
      return merged
    }
    let episodes = combined.compactMapValues { candidates -> ExternalEpisodePlacement? in
      guard let first = candidates.first, candidates.allSatisfy({ $0 == first }) else { return nil }
      return first
    }
    return ShowMapping(expiresAt: Date().addingTimeInterval(episodes.isEmpty ? 300 : 604_800), episodes: episodes)
  }

  nonisolated private static func placements(from segment: Segment, rows: [CatalogRow]) -> [Int: [ExternalEpisodePlacement]] {
    var result: [Int: [ExternalEpisodePlacement]] = [:]
    for row in rows {
      guard row.tvdb_id == segment.mappings.thetvdb_id, let tmdbSeason = row.season?.tmdb,
        let tvdbSeason = row.season?.tvdb
      else { continue }
      for (number, episode) in segment.episodes {
        guard let number = Int(number), number > 0, let tvdbID = episode.tvdbId, tvdbID > 0,
          episode.tvdbShowId == row.tvdb_id, episode.seasonNumber == tvdbSeason, let airDate = episode.airDate
        else { continue }
        let (tvdbNumber, tvdbOverflow) = number.addingReportingOverflow(row.episode_offset?.tvdb ?? 0)
        let (tmdbNumber, tmdbOverflow) = number.addingReportingOverflow(row.episode_offset?.tmdb ?? 0)
        guard !tvdbOverflow, !tmdbOverflow, episode.episodeNumber == tvdbNumber, tmdbNumber > 0 else { continue }
        result[tvdbID, default: []].append(
          ExternalEpisodePlacement(season: tmdbSeason, episode: tmdbNumber, airDate: airDate))
      }
    }
    return result
  }

  nonisolated private enum FetchError: Error { case notFound, invalidResponse }

  @concurrent
  private static func fetch(_ url: URL, using session: URLSession, limit: Int) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 2)
    request.httpShouldHandleCookies = false
    request.setValue("MoviePilot-TV", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: request)
    if (response as? HTTPURLResponse)?.statusCode == 404 { throw FetchError.notFound }
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= limit else {
      throw FetchError.invalidResponse
    }
    return data
  }

  @concurrent
  private static func read<T: Decodable & Sendable>(_ type: T.Type, from url: URL?) async -> T? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  @concurrent
  private static func write(_ mapping: ShowMapping, to url: URL?) async {
    guard let url, let data = try? JSONEncoder().encode(mapping) else { return }
    let folder = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
    // 系统可以清掉整个缓存。平时也顺手淘汰过期的按剧文件，避免随浏览历史一直增长。
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) {
      for file in files where file.lastPathComponent.hasPrefix("show-") {
        if let date = try? file.resourceValues(forKeys: keys).contentModificationDate,
          Date().timeIntervalSince(date) > 604_800
        {
          try? FileManager.default.removeItem(at: file)
        }
      }
    }
  }
}
