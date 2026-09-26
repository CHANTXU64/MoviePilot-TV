import Combine
import Foundation

nonisolated struct PendingTopShelfRoute: Identifiable, Equatable {
  let id: UUID
  let payload: TopShelfRoutePayload
  let media: MediaInfo
  let localPosterURL: URL?
  let cachedContent: TopShelfCachedContent?

  init?(
    id: UUID = UUID(), payload: TopShelfRoutePayload, localPosterURL: URL? = nil,
    cachedContent: TopShelfCachedContent? = nil
  ) {
    guard let media = TopShelfNavigationRouter.media(from: payload) else { return nil }
    self.id = id
    self.payload = payload
    self.media = media
    self.localPosterURL = localPosterURL
    self.cachedContent = cachedContent
  }

  @MainActor var navigationEntry: ImageNavigationEntry {
    ImageNavigationEntry(
      id: id,
      route: .media(media),
      loadingPosterURL: localPosterURL,
      presentationStyle: .direct,
      cachedContent: cachedContent
    )
  }
}

@MainActor
final class TopShelfNavigationRouter: ObservableObject {
  @Published private(set) var pendingRoute: PendingTopShelfRoute?
  private let store: TopShelfSharedStore?

  init(store: TopShelfSharedStore? = TopShelfSharedStore.appGroupStore()) {
    self.store = store
  }

  @discardableResult
  func handle(_ url: URL) -> Bool {
    guard let payload = TopShelfDeepLink.payload(from: url),
      let route = PendingTopShelfRoute(
        payload: payload,
        localPosterURL: store?.previewImageURL(for: payload, at: Date()),
        cachedContent: store?.cachedContent(for: payload, at: Date())
      )
    else { return false }
    pendingRoute = route
    return true
  }

  func consume(id: UUID) {
    guard pendingRoute?.id == id else { return }
    pendingRoute = nil
  }

  nonisolated static func media(from payload: TopShelfRoutePayload) -> MediaInfo? {
    let media = MediaInfo(
      tmdb_id: payload.tmdbID,
      douban_id: payload.doubanID,
      bangumi_id: payload.bangumiID,
      anilist_id: payload.anilistID,
      imdb_id: payload.imdbID,
      tvdb_id: payload.tvdbID,
      source: payload.source,
      mediaid_prefix: payload.mediaIDPrefix,
      media_id: payload.mediaID,
      title: payload.title,
      type: payload.type,
      year: payload.year,
      season: payload.season,
      poster_path: remotePosterPath(payload.posterPath),
      overview: payload.overview,
      vote_average: payload.voteAverage,
      collection_id: payload.collectionID
    )
    guard media.identity != nil || media.collection_id != nil else { return nil }
    return media
  }

  /// 深链不接受文件地址；本地海报只能由当前共享快照解析。
  nonisolated private static func remotePosterPath(_ path: String?) -> String? {
    guard let path, let url = URL(string: path) else { return nil }
    guard let scheme = url.scheme else { return path }
    return ["http", "https"].contains(scheme.lowercased()) ? path : nil
  }
}

nonisolated enum TopShelfNavigationDisposition: Equatable {
  case wait
  case preview
  case open
  case discard
}

nonisolated enum TopShelfNavigationPolicy {
  static func disposition(
    for route: PendingTopShelfRoute,
    isPreparingStartupSession: Bool,
    isLoggedIn: Bool,
    currentSessionID: String,
    visibleTabs: [ContentViewModel.Tab]
  ) -> TopShelfNavigationDisposition {
    guard isLoggedIn,
      route.payload.sessionID == currentSessionID
    else { return .discard }
    guard visibleTabs.contains(.recommend) else {
      return isPreparingStartupSession ? .wait : .discard
    }
    if isPreparingStartupSession { return .preview }
    return .open
  }
}
