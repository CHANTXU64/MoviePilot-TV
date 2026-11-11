import Observation

/// 按媒体加载可选编排。一次短暂故障自动重试，成功空列表也视为加载完成；
/// 仍失败时保留失败状态，由界面提供手动重试。
@MainActor
@Observable
final class EpisodeGroupCatalog {
  // 与分季模型一起释放时，避开 tvOS 18 的隔离析构回部署问题。
  nonisolated deinit {}

  let uiIdentity: String
  private var loadedGroups: [EpisodeGroup]?
  var groups: [EpisodeGroup] { loadedGroups ?? [] }
  private(set) var hasLoadFailed = false
  /// 手动重试时递增，界面把它放进加载任务的 id 以重新发起读取。
  private(set) var loadRequest = 0
  private(set) var seasonsByGroup: [String: [TmdbSeason]] = [:]

  init(apiService: APIService = .shared) {
    uiIdentity = apiService.uiIdentity
  }

  func loadSeasons(groupID: String, apiService: APIService, forceRefresh: Bool = false) async throws {
    guard apiService.uiIdentity == uiIdentity else { throw CancellationError() }
    let snapshot = apiService.sessionSnapshot()
    let seasons = try await apiService.getGroupSeasons(groupId: groupID, forceRefresh: forceRefresh)
    try Task.checkCancellation()
    guard apiService.isSessionUnchanged(from: snapshot) else { throw CancellationError() }
    seasonsByGroup[groupID] = seasons.sorted { ($0.season_number ?? 0) < ($1.season_number ?? 0) }
  }

  /// 会话变化或手动重试时变化，用作界面加载任务的 id。
  struct LoadKey: Equatable {
    let session: APIServiceSessionSnapshot
    let request: Int
  }

  func loadKey(session: APIServiceSessionSnapshot) -> LoadKey {
    LoadKey(session: session, request: loadRequest)
  }

  func retryLoad() {
    hasLoadFailed = false
    loadRequest &+= 1
  }

  func load(tmdbID: Int, apiService: APIService) async throws {
    guard apiService.uiIdentity == uiIdentity else { throw CancellationError() }
    let session = apiService.sessionSnapshot()

    func validate() throws {
      try Task.checkCancellation()
      guard apiService.isSessionUnchanged(from: session) else { throw CancellationError() }
    }

    for attempt in 0...1 {
      try validate()
      guard loadedGroups == nil else { return }
      do {
        let groups = try await apiService.fetchEpisodeGroups(tmdbId: tmdbID)
        try validate()
        loadedGroups = groups
        hasLoadFailed = false
        return
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try validate()
        guard loadedGroups == nil else { return }
        guard attempt == 0, Self.canRetry(error) else {
          Logger.error("加载剧集组失败: \(type(of: error))")
          hasLoadFailed = true
          return
        }
        try await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  private static func canRetry(_ error: Error) -> Bool {
    guard let error = error as? APIError else { return false }
    switch error {
    case .networkError, .gatewayStatus, .serverMessage: return true
    default: return false
    }
  }
}
