import Combine
import Foundation
import TVServices
import UIKit

enum TopShelfSyncStatus: Equatable {
  case unavailable
  case disabled
  case waitingForSession
  case waitingForConfiguration
  case syncing
  case ready
  case failed(String)
}

private enum TopShelfPreparationError: Error {
  case emptyDetail
}

@MainActor
final class TopShelfManager: ObservableObject {
  typealias RecommendationFetcher = @MainActor (String) async throws -> [MediaInfo]
  typealias ImageFetcher = @MainActor (URL) async throws -> TopShelfImageResource
  typealias SourceFetcher = @MainActor () async throws -> [RecommendSourceDescriptor]
  typealias DetailFetcher = @MainActor (MediaInfo) async throws -> MediaInfo
  typealias CollectionFetcher = @MainActor (MediaInfo) async throws -> [MediaInfo]

  static let selectionDefaultsKey = "MP_TOP_SHELF_SELECTION"
  static let selectionDisabledDefaultsKey = "MP_TOP_SHELF_DISABLED"
  private static let explorationDefaultsKey = "MP_TOP_SHELF_EXPLORATION"
  static let maximumItems = TopShelfSnapshot.maximumItems

  @Published private(set) var selection: TopShelfSelection?
  @Published private(set) var status: TopShelfSyncStatus
  @Published private(set) var shelves = RecommendViewModel.allShelves

  var savedExploration: ExploreConfiguration? {
    if let exploration = selection?.exploration { return exploration }
    guard let data = defaults.data(forKey: Self.explorationDefaultsKey) else { return nil }
    return try? JSONDecoder().decode(ExploreConfiguration.self, from: data)
  }

  private let apiService: APIService
  private let store: TopShelfSharedStore?
  private let defaults: UserDefaults
  private let fetchRecommendations: RecommendationFetcher
  private let fetchSubscriptionShares: RecommendationFetcher
  private let fetchImage: ImageFetcher
  private let fetchSources: SourceFetcher
  private let fetchDetail: DetailFetcher
  private let fetchCollection: CollectionFetcher
  private let fetchBackgroundImage: ImageFetcher
  private let storeToken: @MainActor (String, String) -> Bool
  private let notifyChange: @MainActor () -> Void
  private let now: @MainActor () -> Date
  private var selectionRevision: UInt64 = 0
  private var isExplicitlyDisabled: Bool
  private var refreshTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()
  private var started = false
  private var isSynchronizationDeferred = false
  private var refreshPending = false
  private var sourceSessionID: String?

  init(
    apiService: APIService = .shared,
    store: TopShelfSharedStore? = TopShelfSharedStore.appGroupStore(),
    defaults: UserDefaults = .standard,
    fetchSources: SourceFetcher? = nil,
    fetchRecommendations: RecommendationFetcher? = nil,
    fetchSubscriptionShares: RecommendationFetcher? = nil,
    fetchDetail: DetailFetcher? = nil,
    fetchCollection: CollectionFetcher? = nil,
    fetchImage: ImageFetcher? = nil,
    fetchBackgroundImage: ImageFetcher? = nil,
    storeToken: @escaping @MainActor (String, String) -> Bool = { token, sessionID in
      TopShelfCredentials.save(token, sessionID: sessionID)
    },
    notifyChange: @escaping @MainActor () -> Void = {
      TVTopShelfContentProvider.topShelfContentDidChange()
    },
    now: @escaping @MainActor () -> Date = Date.init
  ) {
    self.apiService = apiService
    self.store = store
    self.defaults = defaults
    self.fetchSources =
      fetchSources ?? { [apiService] in
        try await apiService.fetchRecommendSources()
      }
    self.fetchRecommendations =
      fetchRecommendations ?? { [apiService] path in
        try await apiService.fetchRecommend(path: path, page: 1)
      }
    self.fetchSubscriptionShares = fetchSubscriptionShares ?? { [apiService] path in
      try await apiService.fetchSubscriptionShares(path: path, page: 1).map { share in
        share.toMediaInfo(includeShareMetadata: false)
      }
    }
    self.fetchDetail =
      fetchDetail ?? { [apiService] media in
        try await apiService.fetchMediaDetail(media: media)
      }
    self.fetchCollection =
      fetchCollection ?? { [apiService] media in
        guard let id = media.collection_id else { return [] }
        return try await apiService.fetchCollection(
          collectionId: id, page: 1, title: media.title ?? ""
        )
      }
    self.fetchImage =
      fetchImage ?? { [apiService] url in
        try await apiService.fetchTopShelfImageResource(at: url)
      }
    self.fetchBackgroundImage =
      fetchBackgroundImage ?? { [apiService] url in
        try await apiService.fetchTopShelfImageResource(at: url)
      }
    self.storeToken = storeToken
    self.notifyChange = notifyChange
    self.now = now

    let saved = Self.loadSelection(defaults: defaults)
    let isExplicitlyDisabled = defaults.bool(forKey: Self.selectionDisabledDefaultsKey)
    let initialSelection =
      isExplicitlyDisabled
      ? nil
      : TopShelfSelectionPolicy.resolve(
        saved: saved,
        shelves: RecommendViewModel.allShelves
      )
    self.isExplicitlyDisabled = isExplicitlyDisabled
    selection = initialSelection
    status =
      store == nil
      ? .unavailable : (initialSelection == nil ? .disabled : .waitingForSession)
  }

  deinit {
    refreshTask?.cancel()
  }

  func start(refreshImmediately: Bool = true) {
    guard !started else { return }
    started = true

    apiService.$session
      .dropFirst()
      .sink { [weak self] state in
        self?.handleSessionChange(state, scheduleRefresh: true)
      }
      .store(in: &cancellables)

    // 会话启动/回前台的配置加载由 ContentViewModel 负责。配置成功发布后才同步，
    // 避免另起一份启动请求，以及用默认图片配置抢跑。
    apiService.$settings
      .dropFirst()
      .sink { [weak self] settings in self?.handleSettingsChange(settings) }
      .store(in: &cancellables)

    handleSessionChange(apiService.session, scheduleRefresh: refreshImmediately)
  }

  func select(_ newSelection: TopShelfSelection?) {
    applySelection(newSelection, explicitlyDisabled: newSelection == nil)
  }

  func setSynchronizationDeferred(_ deferred: Bool) {
    guard isSynchronizationDeferred != deferred else { return }
    isSynchronizationDeferred = deferred
    if deferred {
      if refreshTask != nil { refreshPending = true }
      refreshTask?.cancel()
      refreshTask = nil
    } else if refreshPending {
      scheduleRefresh()
    }
  }

  @discardableResult
  private func applySelection(
    _ newSelection: TopShelfSelection?,
    explicitlyDisabled: Bool,
    restartRefresh: Bool = true
  ) -> Bool {
    guard selection != newSelection || isExplicitlyDisabled != explicitlyDisabled else {
      return true
    }
    selection = newSelection
    isExplicitlyDisabled = explicitlyDisabled
    selectionRevision &+= 1
    persistSelection(newSelection, explicitlyDisabled: explicitlyDisabled)
    if restartRefresh {
      refreshTask?.cancel()
      refreshTask = nil
    }
    if let newSelection, let store, isSelectionPermitted(in: apiService.session),
      (try? store.loadState())?.activeSessionID == apiService.session.imageNamespace
    {
      do {
        try store.setSelection(newSelection, sessionID: apiService.session.imageNamespace)
      } catch {
        status = .failed("无法保存顶层推荐来源")
        Logger.error("[TopShelf] Failed to change selection: \(error)")
        return false
      }
    } else {
      guard stronglyInvalidate(for: apiService.session) else { return false }
    }
    updateRefreshConfiguration(for: apiService.session)
    if restartRefresh { scheduleRefresh() }
    return true
  }

  func reconcileSelection(
    shelves: [RecommendShelf]
  ) {
    guard !isExplicitlyDisabled else { return }
    let resolved = TopShelfSelectionPolicy.resolve(
      saved: selection,
      shelves: shelves
    )
    applySelection(resolved, explicitlyDisabled: false)
  }

  func refreshNow() async {
    guard !isSynchronizationDeferred else { return }
    guard apiService.token != nil, isSelectionPermitted(in: apiService.session) else {
      status = selection == nil ? .disabled : .waitingForSession
      return
    }
    guard let settings = apiService.settings else {
      status = selection == nil ? .disabled : .waitingForConfiguration
      return
    }

    let preparationConfiguration = refreshConfiguration(for: apiService.session, settings: settings)
    updateRefreshConfiguration(for: apiService.session)
    guard await refreshSources() else { return }
    guard let store else {
      status = .unavailable
      return
    }
    guard let selection else {
      status = .disabled
      return
    }

    let sessionSnapshot = apiService.sessionSnapshot()
    let sessionID = apiService.session.imageNamespace
    let revision = selectionRevision
    let previousState = try? store.loadState()
    do {
      try preparePublishedScope(
        store: store,
        previousState: previousState,
        sessionID: sessionID,
        selection: selection
      )
      updateRefreshConfiguration(for: apiService.session)
    } catch {
      status = .failed("无法更新顶层推荐共享状态")
      Logger.error("[TopShelf] Failed to prepare shared state: \(error)")
      return
    }

    let expectedPublication = try? store.loadState()
    status = .syncing
    do {
      let mediaItems = try await (selection.isSubscriptionShare
        ? fetchSubscriptionShares(selection.requestPath)
        : fetchRecommendations(selection.requestPath))
      try validateRefresh(
        sessionSnapshot, sessionID: sessionID, selection: selection, revision: revision)

      var snapshotItems: [TopShelfSnapshotItem] = []
      var seenIdentifiers = Set<String>()
      for media in mediaItems {
        if snapshotItems.count >= Self.maximumItems { break }
        let payload = Self.routePayload(for: media, sessionID: sessionID)
        guard let identifier = payload.cardIdentifier, seenIdentifiers.insert(identifier).inserted,
          media.identity != nil || media.collection_id != nil,
          let title = media.title?.trimmingCharacters(in: .whitespacesAndNewlines),
          !title.isEmpty
        else { continue }

        do {
          let detail: MediaInfo
          var collectionItems: [MediaInfo]?
          if media.collection_id != nil {
            detail = media
            collectionItems = try await fetchCollection(media)
          } else {
            detail = try await fetchDetail(media)
            guard MediaPreloadTask.hasDisplayableDetail(detail) else {
              throw TopShelfPreparationError.emptyDetail
            }
          }
          try validateRefresh(
            sessionSnapshot, sessionID: sessionID, selection: selection, revision: revision)

          let posterURL = apiService.getPosterImageUrlOriginal(
            posterPath: detail.poster_path ?? media.poster_path)
          let backdropURL =
            apiService.getBackdropImageUrl(detail) ?? apiService.getBackdropImageUrl(media)
          let images: (card: TopShelfImageResource, background: TopShelfImageResource)
          let backgroundURL: URL
          let backgroundIsPoster: Bool
          if let backdropURL {
            do {
              let original = try await fetchBackgroundImage(backdropURL)
              images = try await TopShelfImageLoader.prepareImages(from: original.data)
              backgroundURL = backdropURL
              backgroundIsPoster = false
            } catch is CancellationError { throw CancellationError() } catch {
              guard let posterURL else { throw error }
              let original = try await fetchImage(posterURL)
              images = try await TopShelfImageLoader.prepareImages(from: original.data)
              backgroundURL = posterURL
              backgroundIsPoster = true
            }
          } else {
            guard let posterURL else { continue }
            let original = try await fetchImage(posterURL)
            images = try await TopShelfImageLoader.prepareImages(from: original.data)
            backgroundURL = posterURL
            backgroundIsPoster = true
          }
          try validateRefresh(
            sessionSnapshot, sessionID: sessionID, selection: selection, revision: revision)
          let relativePath = try store.writeImage(
            images.card, cacheKey: "\(sessionID)|hdtv-card|\(backgroundURL.absoluteString)")
          let backgroundPath = try store.writeImage(
            images.background,
            cacheKey:
              "\(sessionID)|detail-\(Int(MediaDetailImageSizing.longEdgePixels))|\(backgroundURL.absoluteString)"
          )
          let detailPath = try store.writeDetailData(
            JSONEncoder().encode(
              TopShelfPreparedContent(detail: detail, collectionItems: collectionItems)),
            cacheKey: "\(sessionID)|\(media.id)"
          )
          let displayURL = try TopShelfDeepLink.url(for: payload)
          snapshotItems.append(
            TopShelfSnapshotItem(
              identifier: identifier,
              title: title,
              imageRelativePath: relativePath,
              displayURL: displayURL,
              detailRelativePath: detailPath,
              backgroundRelativePath: backgroundPath,
              backgroundIsPoster: backgroundIsPoster
            ))
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          Logger.warning("[TopShelf] Skipped unprepared item \(media.id): \(error)")
        }
      }

      try validateRefresh(
        sessionSnapshot, sessionID: sessionID, selection: selection, revision: revision)
      guard !snapshotItems.isEmpty else {
        status = .failed("没有可用于顶层推荐的海报")
        return
      }

      let snapshot = TopShelfSnapshot(
        sessionID: sessionID,
        selection: selection,
        generatedAt: now(),
        items: snapshotItems,
        refreshConfiguration: preparationConfiguration
      )
      guard let expectedPublication else { throw CancellationError() }
      try store.publish(snapshot, replacing: expectedPublication)
      let previousPaths = store.resourcePaths(for: previousState?.snapshot?.items ?? [])
      let retainedPaths = Set(store.resourcePaths(for: snapshot.items) + previousPaths)
      do {
        try store.pruneResources(
          keepingRelativePaths: retainedPaths,
          now: now(),
          gracePeriod: TopShelfSnapshot.imageCleanupGracePeriod
        )
      } catch {
        Logger.warning("[TopShelf] Failed to prune stale posters: \(error)")
      }
      notifyChange()
      status = .ready
    } catch is CancellationError {
      return
    } catch {
      // 解码等下游步骤可能在会话或设置已变化后才以普通 Error 返回；失败回退同样
      // 必须受冻结作用域约束，不能把捕获的旧快照重新发布到已撤销的 canonical state。
      guard
        (try? validateRefresh(
          sessionSnapshot, sessionID: sessionID, selection: selection, revision: revision
        )) != nil
      else { return }
      status = .failed("顶层推荐更新失败")
      Logger.error("[TopShelf] Sync failed: \(error)")
    }
  }

  private func validateRefresh(
    _ snapshot: APIServiceSessionSnapshot,
    sessionID: String, selection: TopShelfSelection, revision: UInt64
  ) throws {
    try Task.checkCancellation()
    guard !isSynchronizationDeferred,
      apiService.isSessionUnchanged(from: snapshot),
      apiService.session.imageNamespace == sessionID,
      isSelectionPermitted(in: apiService.session), self.selection == selection,
      selectionRevision == revision
    else { throw CancellationError() }
  }

  private func handleSessionChange(
    _ state: APIServiceSessionState,
    scheduleRefresh shouldRefresh: Bool
  ) {
    refreshTask?.cancel()
    refreshTask = nil
    if sourceSessionID != state.imageNamespace {
      shelves = RecommendViewModel.allShelves
      sourceSessionID = state.imageNamespace
    }
    if !publishedScopeMatches(state), !stronglyInvalidate(for: state) {
      return
    }
    if shouldRefresh { scheduleRefresh() }
  }

  private func publishedScopeMatches(_ state: APIServiceSessionState) -> Bool {
    guard let store, let selection,
      state.token != nil,
      isSelectionPermitted(in: state),
      let published = try? store.loadState()
    else { return false }
    return published.activeSessionID == state.imageNamespace
      && published.selection == selection
  }

  private func isSelectionPermitted(in state: APIServiceSessionState) -> Bool {
    state.currentUser?.canAccess(.discovery) == true
      && (selection?.isSubscriptionShare != true || state.currentUser?.canAccess(.subscribe) == true)
  }

  @discardableResult
  private func stronglyInvalidate(for state: APIServiceSessionState) -> Bool {
    guard let store else {
      status = .unavailable
      return false
    }
    if let previous = (try? store.loadState())?.refreshConfiguration,
      previous.sessionID != state.imageNamespace || state.token == nil
        || !isSelectionPermitted(in: state) || selection == nil
    {
      TopShelfCredentials.delete(previous.sessionID)
    }
    let canDisplay =
      state.token != nil
      && isSelectionPermitted(in: state)
      && selection != nil
    let emptyState = TopShelfSharedState(
      schemaVersion: TopShelfSharedState.currentSchemaVersion,
      activeSessionID: canDisplay ? state.imageNamespace : nil,
      selection: selection,
      snapshot: nil
    )
    do {
      try store.invalidatePublishedState(emptyState)
      notifyChange()
      status =
        if selection == nil {
          .disabled
        } else {
          .waitingForSession
        }
      return true
    } catch {
      // invalidatePublishedState 可能已经成功移走 canonical state，只在写空状态时失败；
      // 无论失败发生在哪一步都请求系统重载，避免其继续缓存旧账号海报。
      notifyChange()
      status = .failed("无法清除旧的顶层推荐")
      Logger.error("[TopShelf] Failed to invalidate shared state: \(error)")
      return false
    }
  }

  private func scheduleRefresh() {
    guard started else { return }
    refreshPending = true
    guard !isSynchronizationDeferred else { return }
    refreshTask?.cancel()
    refreshPending = false
    refreshTask = Task { @MainActor [weak self] in
      await self?.refreshNow()
      if !Task.isCancelled { self?.refreshTask = nil }
    }
  }

  private func handleSettingsChange(_ settings: GlobalSettings?) {
    guard let settings else { return }
    guard let selection else {
      if case .failed = status { _ = stronglyInvalidate(for: apiService.session) }
      return
    }
    let configuration = refreshConfiguration(for: apiService.session, settings: settings)
    let state = try? store?.loadState()
    let preparedMatches =
      state?.snapshot?.selection == selection
      && state?.snapshot?.refreshConfiguration == configuration
      && state?.snapshot.map { store?.hasPreparedResources(for: $0) == true } == true
    if state?.refreshConfiguration != configuration || (refreshTask == nil && !preparedMatches) {
      scheduleRefresh()
    }
  }

  private func refreshConfiguration(
    for state: APIServiceSessionState, settings: GlobalSettings
  ) -> TopShelfRefreshConfiguration {
    TopShelfRefreshConfiguration(
      sessionID: state.imageNamespace, baseURL: state.baseURL,
      useImageCache: settings.GLOBAL_IMAGE_CACHE?.value == true,
      bangumiProxyEnabled: settings.BANGUMI_PROXY_ENABLE?.value == true,
      bangumiImageDomain: settings.BANGUMI_IMAGE_DOMAIN)
  }

  private func refreshSources() async -> Bool {
    if selection?.exploration != nil { return !Task.isCancelled }
    let snapshot = apiService.sessionSnapshot()
    let revision = selectionRevision
    do {
      let sources = try await fetchSources()
      guard !Task.isCancelled, !isSynchronizationDeferred,
        apiService.isSessionUnchanged(from: snapshot), revision == selectionRevision
      else { return false }
      shelves = RecommendViewModel.mergedShelves(extras: sources)
      sourceSessionID = apiService.session.imageNamespace
      if !isExplicitlyDisabled {
        let resolved = TopShelfSelectionPolicy.resolve(
          saved: selection,
          shelves: shelves
        )
        guard applySelection(resolved, explicitlyDisabled: false, restartRefresh: false) else {
          return false
        }
      }
      return true
    } catch is CancellationError {
      return false
    } catch {
      guard !Task.isCancelled, !isSynchronizationDeferred,
        apiService.isSessionUnchanged(from: snapshot), revision == selectionRevision
      else { return false }
      Logger.warning("[TopShelf] Recommendation sources unavailable: \(error)")
      return true
    }
  }

  private func preparePublishedScope(
    store: TopShelfSharedStore,
    previousState: TopShelfSharedState?,
    sessionID: String,
    selection: TopShelfSelection
  ) throws {
    if previousState?.activeSessionID == sessionID {
      if previousState?.selection != selection {
        try store.setSelection(selection, sessionID: sessionID)
      }
      return
    }
    let emptyState = TopShelfSharedState(
      schemaVersion: TopShelfSharedState.currentSchemaVersion,
      activeSessionID: sessionID,
      selection: selection,
      snapshot: nil
    )
    if previousState == nil {
      try store.saveState(emptyState)
    } else {
      try store.invalidatePublishedState(emptyState)
      notifyChange()
    }
  }

  private func updateRefreshConfiguration(for state: APIServiceSessionState) {
    guard let store else { return }
    let previous = (try? store.loadState())?.refreshConfiguration
    guard let token = state.token, isSelectionPermitted(in: state),
      selection != nil, let settings = apiService.settings
    else {
      if let previous { TopShelfCredentials.delete(previous.sessionID) }
      try? store.setRefreshConfiguration(nil)
      return
    }
    if let previous, previous.sessionID != state.imageNamespace {
      TopShelfCredentials.delete(previous.sessionID)
    }
    guard storeToken(token, state.imageNamespace) else {
      try? store.setRefreshConfiguration(nil)
      Logger.warning("[TopShelf] Shared credential unavailable; retaining prepared content")
      return
    }
    do {
      try store.setRefreshConfiguration(
        refreshConfiguration(for: state, settings: settings))
    } catch { Logger.warning("[TopShelf] Unable to configure extension refresh: \(error)") }
  }

  private func persistSelection(
    _ selection: TopShelfSelection?,
    explicitlyDisabled: Bool
  ) {
    if explicitlyDisabled {
      defaults.set(true, forKey: Self.selectionDisabledDefaultsKey)
    } else {
      defaults.removeObject(forKey: Self.selectionDisabledDefaultsKey)
    }
    if let selection, let data = try? JSONEncoder().encode(selection) {
      defaults.set(data, forKey: Self.selectionDefaultsKey)
      if let exploration = selection.exploration,
        let data = try? JSONEncoder().encode(exploration)
      {
        defaults.set(data, forKey: Self.explorationDefaultsKey)
      }
    } else {
      defaults.removeObject(forKey: Self.selectionDefaultsKey)
    }
  }

  private static func loadSelection(defaults: UserDefaults) -> TopShelfSelection? {
    guard let data = defaults.data(forKey: selectionDefaultsKey) else { return nil }
    return try? JSONDecoder().decode(TopShelfSelection.self, from: data)
  }

  private static func routePayload(
    for media: MediaInfo,
    sessionID: String
  ) -> TopShelfRoutePayload {
    TopShelfRoutePayload(
      sessionID: sessionID,
      source: media.source,
      mediaID: media.media_id,
      mediaIDPrefix: media.mediaid_prefix,
      tmdbID: media.tmdb_id,
      doubanID: media.douban_id,
      bangumiID: media.bangumi_id,
      anilistID: media.anilist_id,
      imdbID: media.imdb_id,
      tvdbID: media.tvdb_id,
      title: media.title,
      type: media.type,
      year: media.year,
      season: media.season,
      posterPath: media.poster_path,
      collectionID: media.collection_id,
      overview: media.overview,
      voteAverage: media.vote_average
    )
  }
}
