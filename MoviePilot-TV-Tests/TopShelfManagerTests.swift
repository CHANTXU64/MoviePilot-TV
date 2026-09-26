import UIKit
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TopShelfManagerTests: XCTestCase {
  func testPublishesAtMostSixFullyPreparedCards() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 820)
    let mediaItems = (1...12).map {
      media(id: $0, title: "卡片\($0)", poster: "https://images.local/\($0).jpg")
    }
    var preparedIDs: [Int] = []
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in mediaItems },
      fetchDetail: { item in
        preparedIDs.append(item.tmdb_id!)
        return item
      },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )
    await manager.refreshNow()
    let snapshot = try XCTUnwrap(try fixture.store.loadState()?.snapshot)
    XCTAssertEqual(snapshot.items.count, 6)
    XCTAssertEqual(preparedIDs, Array(1...6))
    for item in snapshot.items {
      let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: item.displayURL))
      let cache = try XCTUnwrap(fixture.store.cachedContent(for: payload, at: Date()))
      XCTAssertEqual(cache.detail.title, item.title)
      XCTAssertTrue(cache.backgroundURL.isFileURL)
    }
    XCTAssertEqual(fixture.store.presentation(at: Date())?.items.count, 6)
  }

  func testBackdropOnlyMediaCachesCardAndTwoKBackgroundWithoutOriginal() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 830)
    let image = TopShelfTestArtwork.landscapeData()
    let media = MediaInfo(
      tmdb_id: 830, title: "横图", type: "电影",
      backdrop_path: "https://images.local/original/backdrop.jpg")
    var requested: [URL] = []
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in [media] }, fetchDetail: { $0 },
      fetchImage: { _ in
        XCTFail("已有横图不下载竖版海报")
        throw TestManagerError.imageFailed
      },
      fetchBackgroundImage: { url in
        requested.append(url)
        return try TopShelfImageLoader.originalImage(from: image)
      }, notifyChange: {})
    await manager.refreshNow()
    let item = try XCTUnwrap(fixture.store.loadState()?.snapshot?.items.first)
    let payload = try XCTUnwrap(TopShelfDeepLink.payload(from: item.displayURL))
    let cache = try XCTUnwrap(fixture.store.cachedContent(for: payload, at: Date()))
    XCTAssertEqual(requested.map(\.absoluteString), ["https://images.local/original/backdrop.jpg"])
    XCTAssertFalse(cache.backgroundIsPoster)
    let background = try XCTUnwrap(UIImage(contentsOfFile: cache.backgroundURL.path)?.cgImage)
    XCTAssertEqual(background.width, 2560)
    XCTAssertEqual(background.height, 1440)
    let cachedFiles = try FileManager.default.contentsOfDirectory(
      at: cache.backgroundURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
    XCTAssertEqual(cachedFiles.count, 2, "只保存背景与横卡两份处理结果")
    for file in cachedFiles {
      XCTAssertNotEqual(try Data(contentsOf: file), image, "不额外保存下载的原图")
    }
    let card = try XCTUnwrap(
      UIImage(
        contentsOfFile: XCTUnwrap(fixture.store.imageURL(relativePath: item.imageRelativePath)).path
      )?.cgImage)
    XCTAssertLessThan(card.width, background.width)
    XCTAssertGreaterThan(card.width, card.height)
  }

  func testDetailFailureDoesNotPublishUnpreparedCard() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 821)
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        [self.media(id: 1, title: "未就绪", poster: "https://images.local/a.jpg")]
      },
      fetchDetail: { _ in throw TestManagerError.imageFailed },
      fetchImage: { _ in
        XCTFail("基础详情失败后不继续准备该卡片")
        throw TestManagerError.imageFailed
      },
      notifyChange: {}
    )
    await manager.refreshNow()
    XCTAssertNil(try fixture.store.loadState()?.snapshot)
  }

  func testSessionChangeDuringBackgroundPreparationCannotPublish() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 822)
    let gate = AsyncRecommendationGate()
    let item = MediaInfo(
      tmdb_id: 1, title: "第一会话", type: "电影", poster_path: "https://images.local/p.jpg",
      backdrop_path: "https://images.local/b.jpg"
    )
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in [item] },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      fetchBackgroundImage: { _ in
        _ = await gate.wait()
        return TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      }, notifyChange: {}
    )
    let sync = Task { await manager.refreshNow() }
    await gate.waitUntilStarted()
    service.logout()
    await gate.release([])
    await sync.value
    XCTAssertNil(try fixture.store.loadState()?.snapshot)
  }

  func testPartialImageFailurePublishesOnlyDisplayableItems() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 801)
    let first = media(id: 1, title: "第一部", poster: "https://images.local/1.jpg")
    let second = media(id: 2, title: "第二部", poster: "https://images.local/2.jpg")
    var notifications = 0
    let manager = TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in [first, second] },
      fetchDetail: { $0 },
      fetchImage: { url in
        if url.absoluteString.contains("/2.jpg") { throw TestManagerError.imageFailed }
        return TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: { notifications += 1 }
    )

    await manager.refreshNow()

    let state = try XCTUnwrap(try fixture.store.loadState())
    XCTAssertEqual(state.activeSessionID, service.session.imageNamespace)
    XCTAssertEqual(state.snapshot?.items.map(\.title), ["第一部"])
    XCTAssertEqual(notifications, 1)
    XCTAssertEqual(manager.status, .ready)
  }

  func testSessionChangeWhileFetchIsPendingDoesNotPublishOldOwner() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 802)
    let gate = AsyncRecommendationGate()
    let manager = TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in await gate.wait() },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )

    let task = Task { await manager.refreshNow() }
    await gate.waitUntilStarted()
    let replacement = token(userID: 803, token: "token-b")
    service.replaceSessionForTesting(
      baseURL: "https://manager-b.local",
      token: replacement.access_token,
      currentUser: replacement
    )
    await gate.release([media(id: 3, title: "旧账号", poster: "https://images.local/3.jpg")])
    await task.value

    XCTAssertNil(try fixture.store.loadState()?.snapshot)
  }

  func testAllImageFailuresKeepSameOwnerSameShelfPreviousSnapshot() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 804)
    let selection = TopShelfSelection(
      shelfID: "recommend/tmdb_trending",
      title: "流行趋势"
    )
    let oldItem = TopShelfSnapshotItem(
      identifier: "old",
      title: "旧快照",
      imageRelativePath: "images/old.jpg",
      displayURL: try TopShelfDeepLink.url(
        for: TopShelfRoutePayload(
          sessionID: service.session.imageNamespace,
          source: "themoviedb",
          mediaID: "9",
          mediaIDPrefix: nil,
          tmdbID: 9,
          doubanID: nil,
          bangumiID: nil,
          anilistID: nil,
          imdbID: nil,
          tvdbID: nil,
          title: "旧快照",
          type: "电影",
          year: nil,
          season: nil,
          posterPath: nil,
          collectionID: nil
        ))
    )
    let oldSnapshot = TopShelfSnapshot(
      sessionID: service.session.imageNamespace,
      selection: selection,
      generatedAt: Date(),
      items: [oldItem]
    )
    try fixture.store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: service.session.imageNamespace,
        selection: selection,
        snapshot: oldSnapshot
      ))

    let manager = TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        [self.media(id: 10, title: "新快照", poster: "https://images.local/10.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { _ in throw TestManagerError.imageFailed },
      notifyChange: {}
    )

    await manager.refreshNow()

    XCTAssertEqual(try fixture.store.loadState()?.snapshot, oldSnapshot)
    guard case .failed = manager.status else {
      return XCTFail("所有图片失败应发布失败状态")
    }
  }

  func testMissingIdentityAndPosterAreFilteredBeforeSnapshotPublication() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 805)
    let missingIdentity = MediaInfo(
      title: "没有身份",
      type: "电影",
      poster_path: "https://images.local/no-id.jpg"
    )
    let missingPoster = media(id: 12, title: "没有海报", poster: nil)
    let valid = media(id: 13, title: "可展示", poster: "https://images.local/13.jpg")
    let manager = TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in [missingIdentity, missingPoster, valid] },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )

    await manager.refreshNow()

    XCTAssertEqual(try fixture.store.loadState()?.snapshot?.items.map(\.title), ["可展示"])
  }

  func testExplicitDisablePersistsAcrossManagerRecreationAndReconciliation() throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 806)
    let manager = makeIdleManager(service: service, fixture: fixture)

    manager.select(nil)

    let restored = makeIdleManager(service: service, fixture: fixture)
    XCTAssertNil(restored.selection)
    XCTAssertEqual(restored.status, .disabled)

    restored.reconcileSelection(
      shelves: RecommendViewModel.allShelves
    )
    XCTAssertNil(restored.selection)
  }

  func testDisablingEveryInAppShelfDoesNotDisableOrChangeTopShelf() throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let selected = TopShelfSelection(shelfID: "recommend/tmdb_movies", title: "TMDB热门电影")
    fixture.defaults.set(
      try JSONEncoder().encode(selected), forKey: TopShelfManager.selectionDefaultsKey)
    let disabled = Dictionary(
      uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, false) })
    fixture.defaults.set(
      try JSONEncoder().encode(disabled), forKey: RecommendViewModel.localConfigKey)
    let manager = makeIdleManager(service: makeService(userID: 807), fixture: fixture)
    XCTAssertEqual(manager.selection, selected)
    manager.reconcileSelection(shelves: RecommendViewModel.allShelves)
    XCTAssertEqual(manager.selection, selected)
  }

  func testStartPreservesSameSessionSameShelfSnapshotBeforeRefresh() throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 808)
    let selection = TopShelfSelection(
      shelfID: TopShelfSelectionPolicy.defaultShelfID,
      title: "流行趋势"
    )
    let snapshot = TopShelfSnapshot(
      sessionID: service.session.imageNamespace,
      selection: selection,
      generatedAt: Date(),
      items: [
        TopShelfSnapshotItem(
          identifier: "themoviedb:808",
          title: "已有快照",
          imageRelativePath: "images/existing.jpg",
          displayURL: try TopShelfDeepLink.url(
            for: TopShelfRoutePayload(
              sessionID: service.session.imageNamespace,
              source: "themoviedb",
              mediaID: "808",
              mediaIDPrefix: nil,
              tmdbID: 808,
              doubanID: nil,
              bangumiID: nil,
              anilistID: nil,
              imdbID: nil,
              tvdbID: nil,
              title: "已有快照",
              type: "电影",
              year: nil,
              season: nil,
              posterPath: nil,
              collectionID: nil
            )
          )
        )
      ]
    )
    try fixture.store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: service.session.imageNamespace,
        selection: selection,
        snapshot: snapshot
      )
    )
    let manager = makeIdleManager(service: service, fixture: fixture)

    manager.start(refreshImmediately: false)

    XCTAssertEqual(try fixture.store.loadState()?.snapshot, snapshot)
  }

  func testLateFailureCannotRestoreSnapshotAfterSelectionIsDisabled() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 809)
    let gate = AsyncRecommendationGate()
    let manager = TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        _ = await gate.wait()
        throw TestManagerError.imageFailed
      },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )
    // Seed a valid prior snapshot without coupling the regression to image decoding.
    let selection = try XCTUnwrap(manager.selection)
    let previous = TopShelfSnapshot(
      sessionID: service.session.imageNamespace,
      selection: selection,
      generatedAt: Date(),
      items: []
    )
    try fixture.store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: service.session.imageNamespace,
        selection: selection,
        snapshot: previous
      )
    )

    let task = Task { await manager.refreshNow() }
    await gate.waitUntilStarted()
    manager.select(nil)
    await gate.release([])
    await task.value

    let state = try XCTUnwrap(try fixture.store.loadState())
    XCTAssertNil(state.activeSessionID)
    XCTAssertNil(state.snapshot)
    XCTAssertEqual(manager.status, .disabled)
  }

  func testStrongInvalidationWriteFailureNotifiesAndKeepsFailureStatus() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 810)
    let selection = TopShelfSelection(
      shelfID: TopShelfSelectionPolicy.defaultShelfID,
      title: "流行趋势"
    )
    try fixture.store.saveState(
      TopShelfSharedState(
        schemaVersion: TopShelfSharedState.currentSchemaVersion,
        activeSessionID: service.session.imageNamespace,
        selection: selection,
        snapshot: nil
      )
    )
    let failingStore = TopShelfSharedStore(
      containerURL: fixture.containerURL,
      writeData: { _, _ in throw TestManagerError.imageFailed }
    )
    var notifications = 0
    let manager = TopShelfManager(
      apiService: service,
      store: failingStore,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in [] },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: { notifications += 1 }
    )
    manager.start(refreshImmediately: false)

    manager.select(nil)
    await Task.yield()

    XCTAssertNil(try fixture.store.loadState())
    XCTAssertEqual(notifications, 1)
    XCTAssertEqual(manager.status, .failed("无法清除旧的顶层推荐"))

    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(notifications, 2, "配置重新加载后应重试强失效并再次通知系统")
    XCTAssertEqual(manager.status, .failed("无法清除旧的顶层推荐"))
  }

  func testLegacyTitleKeyConfigSelectsTrendingOnFirstManagerInitialization() throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    fixture.defaults.set(
      try JSONEncoder().encode(["流行趋势": true, "TMDB热门电影": false]),
      forKey: RecommendViewModel.localConfigKey
    )

    let manager = makeIdleManager(service: makeService(userID: 811), fixture: fixture)

    XCTAssertEqual(manager.selection?.shelfID, TopShelfSelectionPolicy.defaultShelfID)
  }

  func testWaitsForImageConfigurationAndThenPublishesAfterSettingsArrive() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 812)
    service.settings = nil
    var requests = 0
    let published = expectation(description: "配置就绪后发布")
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        requests += 1
        return [self.media(id: 12, title: "配置后同步", poster: "https://images.local/12.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { url in
        XCTAssertEqual(url.host, "manager-812.local")
        XCTAssertEqual(url.path, "/api/v1/system/cache/image")
        return TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {
        if (try? fixture.store.loadState()?.snapshot) != nil { published.fulfill() }
      }
    )
    manager.start(refreshImmediately: false)
    await manager.refreshNow()
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(manager.status, .waitingForConfiguration)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self, from: Data("{\"GLOBAL_IMAGE_CACHE\":true}".utf8)
    )
    await fulfillment(of: [published], timeout: 3)
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(manager.status, .ready)
  }

  func testAuthoritativeSourceRemovalPreservesSelectionWithoutOpeningSettings() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let selection = TopShelfSelection(shelfID: "plugin/removed", title: "旧榜单")
    fixture.defaults.set(
      try JSONEncoder().encode(selection), forKey: TopShelfManager.selectionDefaultsKey)
    let service = makeService(userID: 813)
    var requestedPaths: [String] = []
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { path in
        requestedPaths.append(path)
        return [self.media(id: 13, title: "新榜单", poster: "https://images.local/13.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )
    XCTAssertEqual(manager.selection, selection)
    await manager.refreshNow()
    XCTAssertEqual(requestedPaths, [selection.shelfID])
    XCTAssertEqual(manager.selection, selection)
    XCTAssertEqual(try fixture.store.loadState()?.snapshot?.selection, manager.selection)
    XCTAssertEqual(manager.status, .ready)
  }

  func testSourceFailurePreservesDynamicSelectionAndCanRecoverAfterImageFailure() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let selection = TopShelfSelection(shelfID: "plugin/custom", title: "自选")
    fixture.defaults.set(
      try JSONEncoder().encode(selection), forKey: TopShelfManager.selectionDefaultsKey)
    var failsImage = true
    let manager = TopShelfManager(
      apiService: makeService(userID: 814), store: fixture.store, defaults: fixture.defaults,
      fetchSources: { throw TestManagerError.imageFailed },
      fetchRecommendations: { path in
        XCTAssertEqual(path, selection.shelfID)
        return [self.media(id: 14, title: "仍可使用", poster: "https://images.local/14.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { _ in
        if failsImage { throw TestManagerError.imageFailed }
        return TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )
    await manager.refreshNow()
    XCTAssertEqual(manager.selection, selection)
    failsImage = false
    await manager.refreshNow()
    XCTAssertEqual(manager.status, .ready)
  }

  func testDirectNavigationDefersSynchronizationUntilReleased() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 815)
    var requests = 0
    let published = expectation(description: "直达完成后恢复同步")
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        requests += 1
        return [self.media(id: 15, title: "延后同步", poster: "https://images.local/15.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {
        if (try? fixture.store.loadState()?.snapshot) != nil { published.fulfill() }
      }
    )
    manager.setSynchronizationDeferred(true)
    manager.start()
    await manager.refreshNow()
    XCTAssertEqual(requests, 0)
    manager.setSynchronizationDeferred(false)
    await fulfillment(of: [published], timeout: 3)
    XCTAssertEqual(requests, 1)
  }

  func testDisabledTopShelfStillLoadsCatalogWithoutFetchingPosters() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    fixture.defaults.set(true, forKey: TopShelfManager.selectionDisabledDefaultsKey)
    let source = RecommendSourceDescriptor(name: "新来源", api_path: "plugin/new", type: "榜单")
    let manager = TopShelfManager(
      apiService: makeService(userID: 816), store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [source] },
      fetchRecommendations: { _ in
        XCTFail("关闭时不能请求海报列表")
        return []
      },
      fetchDetail: { $0 },
      fetchImage: { _ in throw TestManagerError.imageFailed },
      notifyChange: {}
    )
    await manager.refreshNow()
    XCTAssertTrue(manager.shelves.contains(where: { $0.id == source.api_path }))
    XCTAssertNil(manager.selection)
    XCTAssertEqual(manager.status, .disabled)
  }

  func testFirstSettingsPublicationEnablesExtensionRefreshAndLogoutDoesNotResaveOldToken()
    async throws
  {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 820)
    service.settings = nil
    var storedTokens: [String] = []
    let prepared = expectation(description: "首次配置加载后发布")
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        [self.media(id: 20, title: "已准备", poster: "http://images.local/20.jpg")]
      },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      storeToken: { token, _ in
        storedTokens.append(token)
        return true
      },
      notifyChange: { if (try? fixture.store.loadState()?.snapshot) != nil { prepared.fulfill() } })
    manager.start(refreshImmediately: false)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self, from: Data(#"{"GLOBAL_IMAGE_CACHE":true}"#.utf8))
    await fulfillment(of: [prepared], timeout: 2)
    let configuration = try XCTUnwrap(fixture.store.loadState()?.refreshConfiguration)
    XCTAssertEqual(configuration.sessionID, service.session.imageNamespace)
    XCTAssertTrue(configuration.useImageCache)
    storedTokens.removeAll()
    service.logout()
    XCTAssertTrue(storedTokens.isEmpty, "session 的 willSet 通知不能把旧 token 再保存回来")
    XCTAssertNil(try fixture.store.loadState()?.refreshConfiguration)
  }

  func testServerSwitchDoesNotPublishNewTokenWithPreviousServerSettings() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 821)
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from: Data(
        #"{"GLOBAL_IMAGE_CACHE":true,"BANGUMI_IMAGE_DOMAIN":"https://old-images.local"}"#.utf8))
    var storedTokens: [String] = []
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] }, fetchRecommendations: { _ in [] },
      storeToken: { token, _ in
        storedTokens.append(token)
        return true
      }, notifyChange: {})
    manager.start(refreshImmediately: false)
    await manager.refreshNow()
    XCTAssertNotNil(try fixture.store.loadState()?.refreshConfiguration)
    storedTokens.removeAll()
    let replacement = token(userID: 822, token: "new-token")
    service.replaceSessionForTesting(
      baseURL: "https://new-server.local", token: replacement.access_token, currentUser: replacement
    )
    await manager.refreshNow()
    XCTAssertNil(service.settings)
    XCTAssertTrue(storedTokens.isEmpty)
    XCTAssertNil(try fixture.store.loadState()?.refreshConfiguration)
  }

  func testChangingSourceKeepsOldBatchUntilNewBatchIsReadyAndDisableClearsImmediately() async throws
  {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 840)
    let next = TopShelfSelection(shelfID: "recommend/custom", title: "新来源")
    var failNext = true
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { path in
        if path == next.shelfID && failNext { throw TestManagerError.imageFailed }
        return [
          self.media(
            id: path == next.shelfID ? 2 : 1, title: path, poster: "http://image.local/a.jpg")
        ]
      }, fetchDetail: { $0 },
      fetchImage: { _ in try TopShelfImageLoader.originalImage(from: TopShelfTestArtwork.data) },
      storeToken: { _, _ in true }, notifyChange: {})
    await manager.refreshNow()
    let old = try XCTUnwrap(fixture.store.presentation(at: Date()))
    manager.select(next)
    XCTAssertEqual(try fixture.store.loadState()?.selection, next)
    XCTAssertEqual(fixture.store.presentation(at: Date()), old)
    await manager.refreshNow()
    XCTAssertEqual(fixture.store.presentation(at: Date()), old)
    failNext = false
    await manager.refreshNow()
    XCTAssertEqual(fixture.store.presentation(at: Date())?.title, next.title)
    XCTAssertEqual(fixture.store.presentation(at: Date())?.items.count, 1, "新来源不需要凑齐六张")
    manager.select(nil)
    XCTAssertNil(fixture.store.presentation(at: Date()))
  }

  func testIdenticalSettingsDoNotCancelPreparationOrReloadReadyBatchAndMissingImageRetries()
    async throws
  {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 841)
    let gate = AsyncRecommendationGate()
    let ready = expectation(description: "首批准备完成")
    var repaired: XCTestExpectation?
    let duplicate = expectation(description: "无变化不能再请求")
    duplicate.isInverted = true
    var requests = 0
    var expectRepair = false
    let item = media(id: 1, title: "准备完成", poster: "http://image.local/a.jpg")
    let second = media(id: 2, title: "另一张", poster: "http://image.local/b.jpg")
    let manager = TopShelfManager(
      apiService: service, store: fixture.store, defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in
        requests += 1
        if requests == 1 { return await gate.wait() }
        if !expectRepair { duplicate.fulfill() }
        return [item, second]
      }, fetchDetail: { $0 },
      fetchImage: { _ in try TopShelfImageLoader.originalImage(from: TopShelfTestArtwork.data) },
      storeToken: { _, _ in true },
      notifyChange: {
        guard (try? fixture.store.loadState()?.snapshot) != nil else { return }
        if expectRepair { repaired?.fulfill() } else { ready.fulfill() }
      })
    manager.start()
    await gate.waitUntilStarted()
    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    await gate.release([item, second])
    await fulfillment(of: [ready], timeout: 3)
    let previous = try fixture.store.loadState()
    service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    manager.setSynchronizationDeferred(true)
    manager.setSynchronizationDeferred(false)
    await fulfillment(of: [duplicate], timeout: 0.15)
    XCTAssertEqual(try fixture.store.loadState(), previous)
    expectRepair = true
    for resource in 0..<3 {
      let entry = try XCTUnwrap(fixture.store.loadState()?.snapshot?.items.first)
      let path = [
        entry.imageRelativePath, try XCTUnwrap(entry.detailRelativePath),
        try XCTUnwrap(entry.backgroundRelativePath),
      ][resource]
      repaired = expectation(description: "缺失资源重新准备：\(path)")
      let file = fixture.store.stateFileURL.deletingLastPathComponent().appendingPathComponent(path)
      try FileManager.default.removeItem(at: file)
      XCTAssertNotNil(fixture.store.presentation(at: Date()), "仍有可展示卡片也必须修复缺失资源")
      service.settings = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
      await fulfillment(of: [try XCTUnwrap(repaired)], timeout: 3)
      let snapshot = try XCTUnwrap(fixture.store.loadState()?.snapshot)
      XCTAssertTrue(fixture.store.hasPreparedResources(for: snapshot))
    }
    XCTAssertEqual(requests, 4)
    XCTAssertEqual(fixture.store.presentation(at: Date())?.items.count, 2)
  }

  func testFailedNewImageConfigurationRetriesAfterManagerRecreation() async throws {
    let fixture = try ManagerFixture()
    defer { fixture.cleanup() }
    let service = makeService(userID: 842)
    var fail = false
    let ready = expectation(description: "重建后重新准备新配置")
    var restored = false
    func makeManager() -> TopShelfManager {
      TopShelfManager(
        apiService: service, store: fixture.store, defaults: fixture.defaults,
        fetchSources: { [] },
        fetchRecommendations: { _ in
          if fail { throw TestManagerError.imageFailed }
          return [self.media(id: 1, title: "配置", poster: "http://image.local/a.jpg")]
        }, fetchDetail: { $0 },
        fetchImage: { _ in try TopShelfImageLoader.originalImage(from: TopShelfTestArtwork.data) },
        storeToken: { _, _ in true },
        notifyChange: {
          if restored,
            (try? fixture.store.loadState()?.snapshot?.refreshConfiguration?.useImageCache) == true
          {
            ready.fulfill()
          }
        })
    }
    var manager: TopShelfManager? = makeManager()
    await manager?.refreshNow()
    fail = true
    let settings = try JSONDecoder().decode(
      GlobalSettings.self, from: Data(#"{"GLOBAL_IMAGE_CACHE":true}"#.utf8))
    service.settings = settings
    await manager?.refreshNow()
    XCTAssertEqual(try fixture.store.loadState()?.refreshConfiguration?.useImageCache, true)
    XCTAssertEqual(
      try fixture.store.loadState()?.snapshot?.refreshConfiguration?.useImageCache, false)
    manager = nil
    fail = false
    restored = true
    manager = makeManager()
    manager?.start(refreshImmediately: false)
    service.settings = settings
    await fulfillment(of: [ready], timeout: 3)
    XCTAssertEqual(
      try fixture.store.loadState()?.snapshot?.refreshConfiguration?.useImageCache, true)
  }

  private func makeService(userID: Int) -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = token(userID: userID, token: "token-\(userID)")
    service.replaceSessionForTesting(
      baseURL: "https://manager-\(userID).local",
      token: user.access_token,
      currentUser: user
    )
    service.settings = try! JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    return service
  }

  private func makeIdleManager(
    service: APIService,
    fixture: ManagerFixture
  ) -> TopShelfManager {
    TopShelfManager(
      apiService: service,
      store: fixture.store,
      defaults: fixture.defaults,
      fetchSources: { [] },
      fetchRecommendations: { _ in [] },
      fetchDetail: { $0 },
      fetchImage: { _ in TopShelfImageResource(data: TopShelfTestArtwork.data, fileExtension: "gif")
      },
      notifyChange: {}
    )
  }

  private func token(userID: Int, token: String) -> Token {
    Token(
      access_token: token,
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_id: userID,
      user_name: "user-\(userID)",
      avatar: nil
    )
  }

  private func media(id: Int, title: String, poster: String?) -> MediaInfo {
    MediaInfo(
      tmdb_id: id,
      source: "themoviedb",
      title: title,
      type: "电影",
      poster_path: poster
    )
  }
}

private enum TestManagerError: Error {
  case imageFailed
}

private actor AsyncRecommendationGate {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var resultWaiter: CheckedContinuation<[MediaInfo], Never>?
  private var bufferedResult: [MediaInfo]?

  func wait() async -> [MediaInfo] {
    started = true
    startWaiters.forEach { $0.resume() }
    startWaiters.removeAll()
    if let bufferedResult { return bufferedResult }
    return await withCheckedContinuation { resultWaiter = $0 }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release(_ result: [MediaInfo]) {
    if let resultWaiter {
      self.resultWaiter = nil
      resultWaiter.resume(returning: result)
    } else {
      bufferedResult = result
    }
  }
}

private struct ManagerFixture {
  let containerURL: URL
  let store: TopShelfSharedStore
  let defaults: UserDefaults
  private let suiteName: String

  init() throws {
    containerURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TopShelfManagerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    store = TopShelfSharedStore(containerURL: containerURL)
    suiteName = "TopShelfManagerTests-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(
      try JSONEncoder().encode(
        Dictionary(uniqueKeysWithValues: RecommendViewModel.allShelves.map { ($0.id, true) })
      ),
      forKey: RecommendViewModel.localConfigKey
    )
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: containerURL)
    defaults.removePersistentDomain(forName: suiteName)
  }
}
