import Foundation
import UIKit
import XCTest

@testable import MoviePilot_TV

private struct BackendCompatibilityConfig {
  let baseURL: String
  let username: String
  let password: String
  let mediaServer: String?
  let requireMediaServer: Bool
  let requireLatestMedia: Bool
  let metadataQueries: [String]
  let recognitionTitles: [String]
  let resourceQueries: [String]
  let resourceMediaIDs: [String]
  let resourceSites: String?
  let requireResourceResults: Bool
  let checkSeasonAvailability: Bool
  let collectionIDs: [Int]
  let testResourceSearchStreams: Bool
  let enableSideEffects: Bool
  let testSubscriptionSearch: Bool
  let testSubscriptionUpdate: Bool
  let testSubscriptionPauseResume: Bool
  let testSubscriptionResetSearch: Bool
  let sideEffectSubscriptionLimit: Int
  let testManualReorganize: Bool
  let testAIReorganize: Bool
  let reorganizeHistoryLimit: Int
  let reorganizeConcurrentCount: Int

  static func loadOrSkip(file: StaticString = #filePath) throws -> BackendCompatibilityConfig {
    let values = loadEnvironment(file: file)

    guard
      let baseURL = values["MOVIEPILOT_COMPAT_BASE_URL"]?.nilIfBlank,
      let username = values["MOVIEPILOT_COMPAT_USERNAME"]?.nilIfBlank,
      let password = values["MOVIEPILOT_COMPAT_PASSWORD"]?.nilIfBlank
    else {
      throw XCTSkip(
        "Set MOVIEPILOT_COMPAT_BASE_URL, MOVIEPILOT_COMPAT_USERNAME and MOVIEPILOT_COMPAT_PASSWORD in .env.compatibility to run backend compatibility tests."
      )
    }

    var explicitQueries = values["MOVIEPILOT_COMPAT_METADATA_QUERIES"]?.listValue ?? []
    if explicitQueries.isEmpty, let query = values["MOVIEPILOT_COMPAT_METADATA_QUERY"]?.nilIfBlank {
      explicitQueries = [query]
    }

    let recognitionTitles =
      values["MOVIEPILOT_COMPAT_RECOGNITION_TITLES"]?.listValue
      ?? values["MOVIEPILOT_COMPAT_RECOGNITION_TITLE"]?.nilIfBlank.map { [$0] }
      ?? ["流浪地球.2023.2160p.WEB-DL.x265"]
    let resourceQueries =
      values["MOVIEPILOT_COMPAT_RESOURCE_QUERIES"]?.listValue
      ?? values["MOVIEPILOT_COMPAT_RESOURCE_QUERY"]?.nilIfBlank.map { [$0] }
      ?? []
    let resourceMediaIDs =
      values["MOVIEPILOT_COMPAT_RESOURCE_MEDIA_IDS"]?.listValue
      ?? values["MOVIEPILOT_COMPAT_RESOURCE_MEDIA_ID"]?.nilIfBlank.map { [$0] }
      ?? []
    let collectionIDs =
      values["MOVIEPILOT_COMPAT_COLLECTION_IDS"]?.intListValue
      ?? values["MOVIEPILOT_COMPAT_COLLECTION_ID"]?.intValue.map { [$0] }
      ?? []

    return BackendCompatibilityConfig(
      baseURL: baseURL.trimmingTrailingSlashes,
      username: username,
      password: password,
      mediaServer: values["MOVIEPILOT_COMPAT_MEDIA_SERVER"]?.nilIfBlank,
      requireMediaServer: values["MOVIEPILOT_COMPAT_REQUIRE_MEDIA_SERVER"]?.boolValue(
        fallback: false) ?? false,
      requireLatestMedia: values["MOVIEPILOT_COMPAT_REQUIRE_LATEST_MEDIA"]?.boolValue(
        fallback: false) ?? false,
      metadataQueries: explicitQueries,
      recognitionTitles: recognitionTitles,
      resourceQueries: resourceQueries,
      resourceMediaIDs: resourceMediaIDs,
      resourceSites: values["MOVIEPILOT_COMPAT_RESOURCE_SITES"]?.nilIfBlank,
      requireResourceResults: values["MOVIEPILOT_COMPAT_REQUIRE_RESOURCE_RESULTS"]?.boolValue(
        fallback: false) ?? false,
      checkSeasonAvailability: values["MOVIEPILOT_COMPAT_CHECK_SEASON_AVAILABILITY"]?.boolValue(
        fallback: false) ?? false,
      collectionIDs: collectionIDs,
      testResourceSearchStreams: values["MOVIEPILOT_COMPAT_TEST_RESOURCE_SEARCH_STREAMS"]?
        .boolValue(fallback: false) ?? false,
      enableSideEffects: values["MOVIEPILOT_COMPAT_ENABLE_SIDE_EFFECTS"]?.boolValue(
        fallback: true) ?? true,
      testSubscriptionSearch: values["MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_SEARCH"]?.boolValue(
        fallback: true) ?? true,
      testSubscriptionUpdate: values["MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_UPDATE"]?.boolValue(
        fallback: true) ?? true,
      testSubscriptionPauseResume: values["MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_PAUSE_RESUME"]?
        .boolValue(fallback: true) ?? true,
      testSubscriptionResetSearch: values["MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_RESET_SEARCH"]?
        .boolValue(fallback: true) ?? true,
      sideEffectSubscriptionLimit: values["MOVIEPILOT_COMPAT_SIDE_EFFECT_SUBSCRIPTION_LIMIT"]?
        .clampedIntValue(minimum: 1, maximum: 10) ?? 3,
      testManualReorganize: values["MOVIEPILOT_COMPAT_TEST_MANUAL_REORGANIZE"]?.boolValue(
        fallback: true) ?? true,
      testAIReorganize: values["MOVIEPILOT_COMPAT_TEST_AI_REORGANIZE"]?.boolValue(
        fallback: true) ?? true,
      reorganizeHistoryLimit: values["MOVIEPILOT_COMPAT_REORGANIZE_HISTORY_LIMIT"]?
        .clampedIntValue(minimum: 1, maximum: 10) ?? 2,
      reorganizeConcurrentCount: values["MOVIEPILOT_COMPAT_REORGANIZE_CONCURRENT_COUNT"]?
        .clampedIntValue(minimum: 1, maximum: 10) ?? 2
    )
  }

  private static func loadEnvironment(file: StaticString) -> [String: String] {
    let processEnvironment = ProcessInfo.processInfo.environment
    var values: [String: String] = [:]
    guard let repoRoot = findRepoRoot(from: "\(file)") else {
      return processEnvironment
    }

    let envFileName =
      processEnvironment["MOVIEPILOT_COMPAT_ENV_FILE"]?.nilIfBlank ?? ".env.compatibility"
    let envURL =
      envFileName.hasPrefix("/")
      ? URL(fileURLWithPath: envFileName)
      : repoRoot.appendingPathComponent(envFileName)

    if let contents = try? String(contentsOf: envURL, encoding: .utf8) {
      for rawLine in contents.components(separatedBy: .newlines) {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        if line.hasPrefix("export ") {
          line.removeFirst("export ".count)
        }
        guard let equalsIndex = line.firstIndex(of: "=") else { continue }

        let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(line[line.index(after: equalsIndex)...])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.strippingMatchingQuotes

        if !key.isEmpty {
          values[key] = value
        }
      }
    }

    for (key, value) in processEnvironment {
      values[key] = value
    }

    return values
  }

  private static func findRepoRoot(from filePath: String) -> URL? {
    var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()

    while url.path != "/" {
      let projectURL = url.appendingPathComponent("MoviePilot-TV.xcodeproj")
      if FileManager.default.fileExists(atPath: projectURL.path) {
        return url
      }
      url.deleteLastPathComponent()
    }

    return nil
  }
}

private struct BackendServiceSnapshot {
  let baseURL: String
  let token: String?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let usernameKeychain: String?
  let passwordKeychain: String?
  let usernameDefaults: String?
  let passwordDefaults: String?

  @MainActor
  static func capture(service: APIService) -> BackendServiceSnapshot {
    BackendServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      settings: service.settings,
      useImageCache: service.useImageCache,
      usernameKeychain: KeychainHelper.shared.read(
        service: "MoviePilot-TV",
        account: "username"
      ),
      passwordKeychain: KeychainHelper.shared.read(
        service: "MoviePilot-TV",
        account: "password"
      ),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  @MainActor
  func restore(to service: APIService) {
    service.baseURL = baseURL
    service.token = token
    service.settings = settings
    service.useImageCache = useImageCache
    restoreCredential(
      account: "username",
      keychainValue: usernameKeychain,
      defaultsValue: usernameDefaults
    )
    restoreCredential(
      account: "password",
      keychainValue: passwordKeychain,
      defaultsValue: passwordDefaults
    )
  }

  @MainActor
  private func restoreCredential(account: String, keychainValue: String?, defaultsValue: String?) {
    if let keychainValue {
      _ = KeychainHelper.shared.save(keychainValue, service: "MoviePilot-TV", account: account)
    } else {
      _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account)
    }

    if let defaultsValue {
      UserDefaults.standard.set(defaultsValue, forKey: account)
    } else {
      UserDefaults.standard.removeObject(forKey: account)
    }
  }
}

private struct BackendImageCandidate: Sendable {
  let surface: String
  let record: String
  let field: String
  let rawURLString: String?
  let url: URL

  var label: String {
    "\(surface) -> \(record) -> \(field)"
  }
}

private struct BackendImageFetchResult: Sendable {
  let candidate: BackendImageCandidate
  let statusCode: Int?
  let contentType: String
  let data: Data?
  let bodyPreview: String?
  let errorDescription: String?

  var previewSuffix: String {
    bodyPreview.map { ", \($0)" } ?? ""
  }

  var isNonImagePayload: Bool {
    let lowercasedContentType = contentType.lowercased()
    if lowercasedContentType.contains("json") || lowercasedContentType.contains("text") {
      return true
    }
    if let data, String(decoding: data, as: UTF8.self) == "null" {
      return true
    }
    return false
  }
}

private struct BackendSubscriptionStatusPayload: Decodable {
  let id: Int?
}

private struct BackendResponseEnvelope<T: Decodable>: Decodable {
  let success: Bool?
  let data: T?
  let message: String?
}

private struct BackendActionResponse: Decodable {
  let success: Bool?
  let message: String?
}

private struct BackendManualTransferResult: Sendable {
  let label: String
  let success: Bool
  let message: String?
  let diagnostic: String
}

private struct BackendManualTransferRequest: Sendable {
  let label: String
  let url: URL
  let token: String?
  let body: Data
}

private struct BackendStreamProbeResult: Sendable {
  let eventCount: Int
  let itemCount: Int
  let sawTerminalEvent: Bool
  let errorMessage: String?
  let timedOut: Bool
}

private struct BackendSSEEventProbe: Decodable, Sendable {
  struct DataPayload: Decodable, Sendable {
    let success: Bool?
    let error: String?
  }

  struct ItemPayload: Decodable, Sendable {}

  let type: String?
  let enable: Bool?
  let items: [ItemPayload]?
  let message: String?
  let data: DataPayload?
}

private enum BackendCompatibilityProbeError: Error, CustomStringConvertible {
  case invalidURL(String)
  case nonHTTPResponse(String)
  case httpStatus(Int, String, Int, String)
  case backendFailure(String)
  case decoding(String, String)

  var description: String {
    switch self {
    case .invalidURL(let endpoint):
      return "Invalid URL: \(endpoint)"
    case .nonHTTPResponse(let endpoint):
      return "Non-HTTP response: \(endpoint)"
    case .httpStatus(let status, let contentType, let bytes, let body):
      return "HTTP \(status), content-type: \(contentType), bytes: \(bytes), body: \(body)"
    case .backendFailure(let message):
      return "Backend failure: \(message)"
    case .decoding(let error, let body):
      return "Decoding failed: \(error), body: \(body)"
    }
  }
}

@MainActor
private struct BackendCompatibilityCollector {
  private(set) var mediaByID: [String: MediaInfo] = [:]
  private(set) var peopleByID: [String: Person] = [:]
  private(set) var imageCandidates: [BackendImageCandidate] = []

  mutating func addMedia(_ media: [MediaInfo], surface: String) {
    for item in media {
      addMedia(item, surface: surface)
    }
  }

  mutating func addMedia(_ media: MediaInfo, surface: String) {
    mediaByID[media.id] = media
    let record = media.compatibilityTitle
    addImage(
      url: media.imageURLs.poster,
      rawURLString: media.poster_path?.replacingOccurrences(of: "original", with: "w500"),
      surface: surface,
      record: record,
      field: "poster"
    )
    addImage(
      url: media.imageURLs.backdrop,
      rawURLString: media.backdrop_path,
      surface: surface,
      record: record,
      field: "backdrop"
    )
    addPeople(media.directors ?? [], surface: "\(surface) directors for \(record)")
    addPeople(media.actors ?? [], surface: "\(surface) actors for \(record)")
  }

  mutating func addPeople(_ people: [Person], surface: String) {
    for person in people {
      addPerson(person, surface: surface)
    }
  }

  mutating func addPerson(_ person: Person, surface: String) {
    peopleByID[person.id] = person
    addImage(
      url: person.imageURLs.profile,
      rawURLString: person.compatibilityRawImageURL,
      surface: surface,
      record: person.compatibilityName,
      field: "profile"
    )
  }

  mutating func addSubscriptions(_ subscriptions: [Subscribe], surface: String) {
    for subscription in subscriptions {
      addImage(
        url: subscription.imageURLs.poster,
        rawURLString: subscription.poster,
        surface: surface,
        record: subscription.name,
        field: "poster"
      )
    }
  }

  mutating func addSubscriptionShares(_ shares: [SubscribeShare], surface: String) {
    for share in shares {
      let record = share.share_title ?? share.name ?? share.id
      addImage(
        url: share.imageURLs.poster,
        rawURLString: share.poster,
        surface: surface,
        record: record,
        field: "poster"
      )
      addMedia(share.toMediaInfo(), surface: "\(surface) as media")
    }
  }

  mutating func addLatestMedia(_ items: [MediaServerPlayItem], surface: String) {
    for item in items {
      addImage(
        url: item.imageURLs.image,
        rawURLString: item.image,
        surface: surface,
        record: item.title,
        field: "image"
      )
    }
  }

  mutating func addDownloading(_ items: [DownloadingInfo], surface: String) {
    for item in items {
      addImage(
        url: item.media?.imageURLs.image,
        rawURLString: item.media?.image,
        surface: surface,
        record: item.name ?? item.title ?? item.id,
        field: "media.image"
      )
    }
  }

  mutating func addSeasons(_ seasons: [TmdbSeason], surface: String) {
    for season in seasons {
      addImage(
        url: season.imageURLs.poster,
        rawURLString: season.compatibilityRawPosterURL,
        surface: surface,
        record: season.name ?? "season \(season.season_number ?? 0)",
        field: "poster"
      )
    }
  }

  mutating func addImage(
    url: URL?,
    rawURLString: String?,
    surface: String,
    record: String,
    field: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let rawURLString = rawURLString?.nilIfBlank
    guard let url else {
      return
    }
    imageCandidates.append(
      BackendImageCandidate(
        surface: surface,
        record: record,
        field: field,
        rawURLString: rawURLString,
        url: url
      ))
  }

  func derivedSearchQueries(limit: Int) -> [String] {
    var seen = Set<String>()
    var queries: [String] = []

    for media in mediaByID.values.sorted(by: { $0.compatibilityTitle < $1.compatibilityTitle }) {
      for candidate in [media.title, media.original_title, media.original_name] + (media.names ?? []) {
        guard let query = candidate?.nilIfBlank, seen.insert(query).inserted else { continue }
        queries.append(query)
        if queries.count == limit {
          return queries
        }
      }
    }

    return queries
  }
}

final class BackendCompatibilityReadOnlyTests: XCTestCase {
  @MainActor
  func testReadOnlySystemAndConfigurationCompatibility() async throws {
    try await withReadOnlyBackend { service, _ in
      _ = try await service.fetchSettings()
      _ = try await service.fetchSystemEnv()
      _ = try await service.fetchStatistic()
      let storage = try await service.fetchStorage()
      _ = try await service.fetchDownloaderInfo()
      _ = try await service.fetchSites()
      _ = try await service.fetchIndexerSites()
      _ = try await service.fetchFilterRuleGroups()
      _ = try await service.fetchCustomFilterRules()
      _ = try await service.fetchStorages()
      _ = try await service.fetchDirectories()
      _ = try await service.fetchDownloadClients()

      XCTAssertGreaterThanOrEqual(storage.total_storage, 0)
      XCTAssertGreaterThanOrEqual(storage.used_storage, 0)
    }
  }

  @MainActor
  func testReadOnlyOperationalStateCompatibility() async throws {
    try await withReadOnlyBackend { service, config in
      for title in config.recognitionTitles {
        do {
          _ = try await service.recognizeMedia(title: title)
        } catch {
          XCTFail("Failed to recognize read-only title sample \(title): \(error)")
        }

        let tmdbID = await service.recognizeTmdbId(title: title)
        XCTAssertGreaterThanOrEqual(
          tmdbID ?? 0,
          0,
          "TMDB recognition should return a non-negative ID or nil for \(title)"
        )
      }

      do {
        let history = try await service.fetchTransferHistory(page: 1, count: 20, title: nil)
        XCTAssertGreaterThanOrEqual(history.total, 0)
        XCTAssertLessThanOrEqual(history.list.count, 20)
      } catch {
        XCTFail("Failed to read transfer history: \(error)")
      }
    }
  }

  @MainActor
  func testReadOnlyResourceSearchCompatibility() async throws {
    try await withReadOnlyBackend { service, config in
      let titleQueries = uniqueStrings(config.resourceQueries)
      let mediaIDs = uniqueStrings(config.resourceMediaIDs)

      guard !titleQueries.isEmpty || !mediaIDs.isEmpty else {
        throw XCTSkip(
          "Set MOVIEPILOT_COMPAT_RESOURCE_QUERY or MOVIEPILOT_COMPAT_RESOURCE_MEDIA_ID to run read-only resource search compatibility checks."
        )
      }

      for query in titleQueries {
        do {
          let results = try await service.searchResources(keyword: query, sites: config.resourceSites)
          assertResourceSearchResults(
            results,
            label: "resource title search \(query)",
            requireResults: config.requireResourceResults
          )
        } catch {
          XCTFail("Failed to run read-only resource title search \(query): \(error)")
        }
      }

      for mediaID in mediaIDs {
        do {
          let results = try await service.searchResources(keyword: mediaID, sites: config.resourceSites)
          assertResourceSearchResults(
            results,
            label: "resource media-id search \(mediaID)",
            requireResults: config.requireResourceResults
          )
        } catch {
          XCTFail("Failed to run read-only resource media-id search \(mediaID): \(error)")
        }
      }

      if config.testResourceSearchStreams {
        await assertResourceSearchStreamsReadable(service: service, config: config)
      }
    }
  }

  @MainActor
  func testReadOnlyTVSurfaceCompatibilityAndImageRendering() async throws {
    try await withReadOnlyBackend { service, config in
      _ = try await service.fetchSettings()

      var collector = BackendCompatibilityCollector()

      await scanMediaServerLatest(service: service, config: config, collector: &collector)
      await scanSubscriptions(service: service, collector: &collector)
      await scanDownloading(service: service, collector: &collector)
      await scanRecommendShelves(service: service, collector: &collector)
      await scanExploreSurfaces(service: service, collector: &collector)
      await scanMetadataSearches(service: service, config: config, collector: &collector)
      await scanConfiguredCollectionDetails(service: service, config: config, collector: &collector)
      await scanMediaDetailSurfaces(service: service, collector: &collector)
      await scanSeasonAvailabilityStatus(service: service, config: config, collector: collector)
      await scanPersonDetailSurfaces(service: service, collector: &collector)

      await assertImagesRenderable(collector.imageCandidates, service: service)
    }
  }

  @MainActor
  private func scanMediaServerLatest(
    service: APIService,
    config: BackendCompatibilityConfig,
    collector: inout BackendCompatibilityCollector
  ) async {
    do {
      let servers = try await service.fetchMediaServers()
      let enabledServers = servers.filter { $0.enabled?.value ?? false }

      guard !enabledServers.isEmpty else {
        if config.requireMediaServer {
          XCTFail("No enabled media servers configured.")
        }
        return
      }

      let targetServers: [MediaServerConf]
      if let mediaServer = config.mediaServer {
        targetServers = enabledServers.filter { $0.name == mediaServer }
        XCTAssertFalse(
          targetServers.isEmpty,
          "Configured media server is not enabled: \(mediaServer)"
        )
      } else {
        targetServers = enabledServers
      }

      var checkedLatestItems = 0
      for server in targetServers {
        do {
          let latestItems = try await service.fetchMediaServerLatest(server: server.name)
          checkedLatestItems += latestItems.count
          collector.addLatestMedia(latestItems, surface: "home latest media server \(server.name)")
        } catch {
          XCTFail("Failed to read latest media from server \(server.name): \(error)")
        }
      }

      if checkedLatestItems == 0 && config.requireLatestMedia {
        XCTFail("Enabled media servers returned no latest media.")
      }
    } catch {
      XCTFail("Failed to scan media server latest surface: \(error)")
    }
  }

  @MainActor
  private func scanSubscriptions(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    do {
      let subscriptions = try await service.fetchSubscriptions()
      collector.addSubscriptions(subscriptions, surface: "subscriptions list")

      for subscription in subscriptions {
        guard let id = subscription.id else { continue }
        do {
          let detail = try await service.fetchSubscription(id: id)
          XCTAssertEqual(detail.id, id)
          collector.addSubscriptions([detail], surface: "subscription detail")
        } catch {
          XCTFail("Failed to read subscription detail \(id): \(error)")
        }
      }
    } catch {
      XCTFail("Failed to scan subscriptions surface: \(error)")
    }
  }

  @MainActor
  private func scanDownloading(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    do {
      let clients = try await service.fetchDownloadClients()
      for client in clients where client.enabled?.value ?? true {
        do {
          let items = try await service.fetchDownloading(clientName: client.name)
          collector.addDownloading(items, surface: "downloading \(client.name)")
        } catch {
          XCTFail("Failed to read downloading list for \(client.name): \(error)")
        }
      }
    } catch {
      XCTFail("Failed to scan downloading surface: \(error)")
    }
  }

  @MainActor
  private func scanRecommendShelves(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    for shelf in RecommendViewModel.allShelves {
      do {
        let items = try await service.fetchRecommend(path: shelf.id, page: 1)
        collector.addMedia(items, surface: "recommend shelf \(shelf.title)")
      } catch {
        XCTFail("Failed to read recommend shelf \(shelf.title) at \(shelf.id): \(error)")
      }
    }
  }

  @MainActor
  private func scanExploreSurfaces(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    let mediaPaths = [
      "discover/tmdb_movies?sort_by=popularity.desc",
      "discover/tmdb_tvs?sort_by=popularity.desc",
      "discover/douban_movies?sort=U",
      "discover/douban_tvs?sort=U",
      "discover/bangumi?type=2&sort=rank",
      "subscribe/popular?stype=电影&sort_type=count",
      "subscribe/popular?stype=电视剧&sort_type=count",
    ]

    for path in mediaPaths {
      do {
        let items = try await service.fetchRecommend(path: path, page: 1)
        collector.addMedia(items, surface: "explore \(path)")
      } catch {
        XCTFail("Failed to read explore surface \(path): \(error)")
      }
    }

    let sharePath = "subscribe/shares?stype=电视剧&sort_type=count"
    do {
      let shares = try await service.fetchSubscriptionShares(path: sharePath, page: 1)
      collector.addSubscriptionShares(shares, surface: "explore \(sharePath)")
    } catch {
      XCTFail("Failed to read subscription share surface \(sharePath): \(error)")
    }
  }

  @MainActor
  private func scanMetadataSearches(
    service: APIService,
    config: BackendCompatibilityConfig,
    collector: inout BackendCompatibilityCollector
  ) async {
    let queries = uniqueStrings(config.metadataQueries + collector.derivedSearchQueries(limit: 5))
    guard !queries.isEmpty else { return }

    for query in queries {
      for page in 1...2 {
        do {
          let items = try await service.searchMedia(query: query, page: page)
          collector.addMedia(items, surface: "metadata search \(query) page \(page)")
        } catch {
          XCTFail("Failed to read metadata search \(query) page \(page): \(error)")
        }
      }

      do {
        let collections = try await service.searchCollection(query: query, page: 1)
        collector.addMedia(collections, surface: "collection search \(query)")
        await scanCollectionDetails(
          service: service,
          collections: collections,
          collector: &collector
        )
      } catch {
        XCTFail("Failed to read collection search \(query): \(error)")
      }

      do {
        let people = try await service.searchPerson(query: query, page: 1)
        collector.addPeople(people, surface: "person search \(query)")
      } catch {
        XCTFail("Failed to read person search \(query): \(error)")
      }

      do {
        let shares = try await service.searchSubscriptionShares(query: query, page: 1)
        collector.addSubscriptionShares(shares, surface: "subscription share search \(query)")
      } catch {
        XCTFail("Failed to read subscription share search \(query): \(error)")
      }
    }
  }

  @MainActor
  private func scanConfiguredCollectionDetails(
    service: APIService,
    config: BackendCompatibilityConfig,
    collector: inout BackendCompatibilityCollector
  ) async {
    for collectionID in uniqueInts(config.collectionIDs).prefix(8) {
      do {
        let items = try await service.fetchCollection(
          collectionId: collectionID,
          page: 1,
          title: String(collectionID)
        )
        collector.addMedia(items, surface: "configured collection \(collectionID)")
      } catch {
        XCTFail("Failed to read configured collection \(collectionID): \(error)")
      }
    }
  }

  @MainActor
  private func scanCollectionDetails(
    service: APIService,
    collections: [MediaInfo],
    collector: inout BackendCompatibilityCollector
  ) async {
    var seenIDs = Set<Int>()
    let candidates = collections
      .compactMap { item -> (id: Int, title: String)? in
        guard let collectionID = item.collection_id, seenIDs.insert(collectionID).inserted else {
          return nil
        }
        return (collectionID, item.compatibilityTitle)
      }
      .prefix(8)

    for candidate in candidates {
      do {
        let items = try await service.fetchCollection(
          collectionId: candidate.id,
          page: 1,
          title: candidate.title
        )
        collector.addMedia(items, surface: "collection detail \(candidate.title)")
      } catch {
        XCTFail("Failed to read collection detail \(candidate.title): \(error)")
      }
    }
  }

  @MainActor
  private func scanMediaDetailSurfaces(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    let mediaForDetail = representativeMediaForDetail(from: Array(collector.mediaByID.values))

    for media in mediaForDetail {
      do {
        let detail = try await service.fetchMediaDetail(media: media)
        collector.addMedia(detail, surface: "media detail \(media.compatibilityTitle)")

        do {
          try await assertSubscriptionStatusReadable(service: service, media: detail)
          _ = try await service.checkSubscription(media: detail)
        } catch {
          XCTFail("Failed to read subscription status for \(detail.compatibilityTitle): \(error)")
        }

        do {
          let actors = try await service.fetchMediaActors(detail: detail, page: 1)
          collector.addPeople(actors, surface: "media actors \(detail.compatibilityTitle)")
        } catch {
          XCTFail("Failed to read actors for \(detail.compatibilityTitle): \(error)")
        }

        do {
          let recommendations = try await service.fetchMediaRecommendations(detail: detail, page: 1)
          collector.addMedia(
            recommendations,
            surface: "media recommendations \(detail.compatibilityTitle)"
          )
        } catch {
          XCTFail("Failed to read recommendations for \(detail.compatibilityTitle): \(error)")
        }

        do {
          let similar = try await service.fetchMediaSimilar(detail: detail, page: 1)
          collector.addMedia(similar, surface: "media similar \(detail.compatibilityTitle)")
        } catch {
          XCTFail("Failed to read similar media for \(detail.compatibilityTitle): \(error)")
        }

        if detail.type == "电视剧" {
          await scanSeasonSurfaces(service: service, media: detail, collector: &collector)
        }
      } catch {
        XCTFail("Failed to read media detail \(media.compatibilityTitle): \(error)")
      }
    }
  }

  @MainActor
  private func scanSeasonSurfaces(
    service: APIService,
    media: MediaInfo,
    collector: inout BackendCompatibilityCollector
  ) async {
    do {
      let seasons = try await service.getMediaSeasons(media: media)
      collector.addSeasons(seasons, surface: "media seasons \(media.compatibilityTitle)")
    } catch {
      XCTFail("Failed to read seasons for \(media.compatibilityTitle): \(error)")
    }

    guard let tmdbID = media.tmdb_id else { return }
    do {
      let groups = try await service.fetchEpisodeGroups(tmdbId: tmdbID)
      for group in groups {
        do {
          let seasons = try await service.getGroupSeasons(groupId: group.id)
          collector.addSeasons(
            seasons,
            surface: "episode group \(group.name) for \(media.compatibilityTitle)"
          )
        } catch {
          XCTFail("Failed to read group seasons \(group.name) for \(media.compatibilityTitle): \(error)")
        }
      }
    } catch {
      XCTFail("Failed to read episode groups for \(media.compatibilityTitle): \(error)")
    }
  }

  @MainActor
  private func scanSeasonAvailabilityStatus(
    service: APIService,
    config: BackendCompatibilityConfig,
    collector: BackendCompatibilityCollector
  ) async {
    guard config.checkSeasonAvailability else { return }

    let series = representativeMediaForDetail(from: Array(collector.mediaByID.values))
      .filter { $0.type == "电视剧" }
      .prefix(8)

    for media in series {
      do {
        let missingItems = try await service.checkSeasonsNotExists(mediaInfo: media)
        for item in missingItems {
          XCTAssertGreaterThanOrEqual(
            item.season,
            0,
            "Invalid season availability status for \(media.compatibilityTitle)"
          )
          XCTAssertGreaterThanOrEqual(
            item.total_episode,
            0,
            "Invalid total episode count for \(media.compatibilityTitle)"
          )
        }
      } catch {
        XCTFail("Failed to read season availability status for \(media.compatibilityTitle): \(error)")
      }
    }
  }

  @MainActor
  private func scanPersonDetailSurfaces(
    service: APIService,
    collector: inout BackendCompatibilityCollector
  ) async {
    let peopleForDetail = representativePeopleForDetail(from: Array(collector.peopleByID.values))

    for person in peopleForDetail {
      guard let personID = person.raw_id else { continue }
      do {
        let detail = try await service.fetchPersonDetail(personId: personID, source: person.source)
        collector.addPerson(detail, surface: "person detail \(person.compatibilityName)")
      } catch {
        let diagnostic = await readOnlyGETDiagnostic(
          service: service,
          path: "/\(personSourcePath(person.source))/person/\(personID)"
        )
        XCTFail(
          "Failed to read person detail \(person.compatibilityName): \(error). \(diagnostic)"
        )
      }

      do {
        let credits = try await service.fetchPersonCredits(
          personId: personID,
          source: person.source,
          page: 1
        )
        collector.addMedia(credits, surface: "person credits \(person.compatibilityName)")
      } catch {
        XCTFail("Failed to read person credits \(person.compatibilityName): \(error)")
      }
    }
  }

  @MainActor
  private func assertResourceSearchResults(
    _ results: [Context],
    label: String,
    requireResults: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    if requireResults {
      XCTAssertFalse(results.isEmpty, "Expected at least one result for \(label)", file: file, line: line)
    }

    for result in results.prefix(50) {
      XCTAssertTrue(
        result.media_info != nil || result.torrent_info != nil || result.meta_info != nil,
        "Resource result must include media_info, torrent_info, or meta_info for \(label)",
        file: file,
        line: line
      )

      if let torrent = result.torrent_info {
        XCTAssertGreaterThanOrEqual(
          torrent.size,
          0,
          "Torrent size must be non-negative for \(label)",
          file: file,
          line: line
        )
      }
    }
  }

  @MainActor
  private func assertResourceSearchStreamsReadable(
    service: APIService,
    config: BackendCompatibilityConfig
  ) async {
    let titleQueries = uniqueStrings(config.resourceQueries).prefix(3)
    let mediaIDs = uniqueStrings(config.resourceMediaIDs).prefix(3)

    for query in titleQueries {
      do {
        let url = try compatibilityAPIURL(
          service: service,
          path: "/search/title/stream",
          params: [
            "keyword": query,
            "sites": config.resourceSites,
          ])
        let result = await Self.probeSSEStream(url: url, token: service.token)
        assertSSEProbe(result, label: "resource title stream \(query)")
      } catch {
        XCTFail("Failed to build resource title stream request \(query): \(error)")
      }
    }

    for mediaID in mediaIDs {
      do {
        let url = try compatibilityAPIURL(
          service: service,
          path: "/search/media/\(mediaID)/stream",
          params: [
            "sites": config.resourceSites,
          ])
        let result = await Self.probeSSEStream(url: url, token: service.token)
        assertSSEProbe(result, label: "resource media stream \(mediaID)")
      } catch {
        XCTFail("Failed to build resource media stream request \(mediaID): \(error)")
      }
    }
  }

  private func assertSSEProbe(
    _ result: BackendStreamProbeResult,
    label: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertFalse(result.timedOut, "\(label) timed out before producing a terminal event", file: file, line: line)
    XCTAssertNil(result.errorMessage, "\(label) returned stream error: \(result.errorMessage ?? "")", file: file, line: line)
    XCTAssertGreaterThan(result.eventCount, 0, "\(label) produced no decodable SSE events", file: file, line: line)
    XCTAssertTrue(result.sawTerminalEvent, "\(label) produced events but no terminal SSE event", file: file, line: line)
  }

  @MainActor
  private func assertImagesRenderable(
    _ candidates: [BackendImageCandidate],
    service: APIService
  ) async {
    var seenURLs = Set<String>()
    var uniqueCandidates: [BackendImageCandidate] = []
    var checkedImages = 0

    for candidate in candidates {
      let urlString = candidate.url.absoluteString
      guard seenURLs.insert(urlString).inserted else { continue }

      assertProxyURLPreservesRawImage(candidate)
      uniqueCandidates.append(candidate)
    }

    var start = 0
    let batchSize = 12
    while start < uniqueCandidates.count {
      let end = Swift.min(start + batchSize, uniqueCandidates.count)
      let batch = Array(uniqueCandidates[start..<end])
      let results = await Self.fetchImageBatch(batch, token: service.token)

      for result in results {
        let candidate = result.candidate
        if let errorDescription = result.errorDescription {
          XCTFail("Failed to fetch/decode image for \(candidate.label): \(errorDescription)")
          continue
        }

        guard let statusCode = result.statusCode else {
          XCTFail("Image response is not HTTP for \(candidate.label)")
          continue
        }

        XCTAssertTrue(
          (200...299).contains(statusCode),
          "Image HTTP \(statusCode) for \(candidate.label), content-type: \(result.contentType)\(result.previewSuffix)"
        )

        guard let data = result.data, !data.isEmpty else {
          XCTFail("Image data is empty for \(candidate.label)")
          continue
        }

        if result.isNonImagePayload {
          XCTFail(
            "Image endpoint returned non-image payload for \(candidate.label), content-type: \(result.contentType), bytes: \(data.count)\(result.previewSuffix)"
          )
          continue
        }

        guard let image = UIImage(data: data) else {
          XCTFail(
            "tvOS cannot decode image for \(candidate.label), content-type: \(result.contentType), bytes: \(data.count)\(result.previewSuffix)"
          )
          continue
        }

        XCTAssertGreaterThan(image.size.width, 0, "Decoded image width is zero for \(candidate.label)")
        XCTAssertGreaterThan(image.size.height, 0, "Decoded image height is zero for \(candidate.label)")
        checkedImages += 1
      }

      start = end
    }

    print(
      "Backend compatibility checked \(checkedImages) tvOS-decodable images from \(uniqueCandidates.count) unique image URLs."
    )
  }

  private static func fetchImageBatch(
    _ candidates: [BackendImageCandidate],
    token: String?
  ) async -> [BackendImageFetchResult] {
    await withTaskGroup(of: BackendImageFetchResult.self) { group in
      for candidate in candidates {
        group.addTask {
          await fetchImage(candidate, token: token)
        }
      }

      var results: [BackendImageFetchResult] = []
      for await result in group {
        results.append(result)
      }
      return results
    }
  }

  private static func fetchImage(
    _ candidate: BackendImageCandidate,
    token: String?
  ) async -> BackendImageFetchResult {
    do {
      var request = URLRequest(url: candidate.url)
      request.timeoutInterval = 15
      if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }

      let (data, response) = try await URLSession.shared.data(for: request)
      let httpResponse = response as? HTTPURLResponse
      return BackendImageFetchResult(
        candidate: candidate,
        statusCode: httpResponse?.statusCode,
        contentType: httpResponse?.contentTypeDescription ?? "unknown",
        data: data,
        bodyPreview: Self.responsePreview(from: data, contentType: httpResponse?.contentTypeDescription),
        errorDescription: nil
      )
    } catch {
      return BackendImageFetchResult(
        candidate: candidate,
        statusCode: nil,
        contentType: "unknown",
        data: nil,
        bodyPreview: nil,
        errorDescription: String(describing: error)
      )
    }
  }

  fileprivate static func probeSSEStream(
    url: URL,
    token: String?,
    timeoutSeconds: UInt64 = 45
  ) async -> BackendStreamProbeResult {
    await withTaskGroup(of: BackendStreamProbeResult.self) { group in
      group.addTask {
        await readSSEStream(url: url, token: token, maxEvents: 40)
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
        return BackendStreamProbeResult(
          eventCount: 0,
          itemCount: 0,
          sawTerminalEvent: false,
          errorMessage: nil,
          timedOut: true
        )
      }

      let result = await group.next()
        ?? BackendStreamProbeResult(
          eventCount: 0,
          itemCount: 0,
          sawTerminalEvent: false,
          errorMessage: "Stream probe finished without a result.",
          timedOut: false
        )
      group.cancelAll()
      return result
    }
  }

  private static func readSSEStream(
    url: URL,
    token: String?,
    maxEvents: Int
  ) async -> BackendStreamProbeResult {
    var eventCount = 0
    var itemCount = 0
    var sawTerminalEvent = false
    var streamError: String?

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 300
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
      if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }

      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return BackendStreamProbeResult(
          eventCount: eventCount,
          itemCount: itemCount,
          sawTerminalEvent: false,
          errorMessage: "SSE response is not HTTP.",
          timedOut: false
        )
      }
      guard httpResponse.statusCode == 200 else {
        return BackendStreamProbeResult(
          eventCount: eventCount,
          itemCount: itemCount,
          sawTerminalEvent: false,
          errorMessage: "HTTP \(httpResponse.statusCode), content-type: \(httpResponse.contentTypeDescription)",
          timedOut: false
        )
      }

      for try await line in bytes.lines {
        if Task.isCancelled { break }
        guard line.hasPrefix("data:") else { continue }

        let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard let data = jsonString.data(using: .utf8) else { continue }

        let event = try JSONDecoder().decode(BackendSSEEventProbe.self, from: data)
        eventCount += 1
        itemCount += event.items?.count ?? 0

        if event.type == "error" {
          streamError = event.message ?? event.data?.error ?? "Unknown SSE error event."
          sawTerminalEvent = true
          break
        }

        if event.type == "done" || event.enable == false {
          if let success = event.data?.success, success == false {
            streamError = event.data?.error ?? event.message ?? "SSE terminal event reported failure."
          }
          sawTerminalEvent = true
          break
        }

        if eventCount >= maxEvents {
          break
        }
      }

      return BackendStreamProbeResult(
        eventCount: eventCount,
        itemCount: itemCount,
        sawTerminalEvent: sawTerminalEvent,
        errorMessage: streamError,
        timedOut: false
      )
    } catch {
      return BackendStreamProbeResult(
        eventCount: eventCount,
        itemCount: itemCount,
        sawTerminalEvent: sawTerminalEvent,
        errorMessage: String(describing: error),
        timedOut: false
      )
    }
  }

  @MainActor
  private func readOnlyGETDiagnostic(
    service: APIService,
    path: String,
    params: [String: String?] = [:]
  ) async -> String {
    do {
      let url = try compatibilityAPIURL(service: service, path: path, params: params)
      var request = URLRequest(url: url)
      request.timeoutInterval = 15
      if let token = service.token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return "Diagnostic GET \(path) returned a non-HTTP response."
      }

      return
        "Diagnostic GET \(path) returned HTTP \(httpResponse.statusCode), content-type: \(httpResponse.contentTypeDescription), bytes: \(data.count), \(Self.responsePreview(from: data, contentType: httpResponse.contentTypeDescription))"
    } catch {
      return "Diagnostic GET \(path) failed: \(error)"
    }
  }

  private func personSourcePath(_ source: String?) -> String {
    var sourcePath = source ?? "tmdb"
    if sourcePath == "themoviedb" { sourcePath = "tmdb" }
    return sourcePath
  }

  @MainActor
  private func assertSubscriptionStatusReadable(
    service: APIService,
    media: MediaInfo,
    season: Int? = nil
  ) async throws {
    guard let mediaId = media.apiMediaId else { return }

    let url = try compatibilityAPIURL(
      service: service,
      path: "/subscribe/media/\(mediaId)",
      params: [
        "season": season.map(String.init),
        "title": media.title,
      ])
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    if let token = service.token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BackendCompatibilityProbeError.nonHTTPResponse(url.path)
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw BackendCompatibilityProbeError.httpStatus(
        httpResponse.statusCode,
        httpResponse.contentTypeDescription,
        data.count,
        Self.responseSnippet(from: data)
      )
    }

    try decodeSubscriptionStatusProbe(data)
  }

  @MainActor
  private func compatibilityAPIURL(
    service: APIService,
    path: String,
    params: [String: String?] = [:]
  ) throws -> URL {
    let endpoint = "\(service.baseURL)/api/v1\(path)"
    guard var components = URLComponents(string: endpoint) else {
      throw BackendCompatibilityProbeError.invalidURL(endpoint)
    }

    var queryItems = components.queryItems ?? []
    for (name, value) in params.sorted(by: { $0.key < $1.key }) {
      if let value {
        queryItems.append(URLQueryItem(name: name, value: value))
      }
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components.url else {
      throw BackendCompatibilityProbeError.invalidURL(endpoint)
    }
    return url
  }

  private func decodeSubscriptionStatusProbe(_ data: Data) throws {
    let decoder = JSONDecoder()
    if let envelope = try? decoder.decode(
      BackendResponseEnvelope<BackendSubscriptionStatusPayload>.self,
      from: data
    ) {
      if envelope.success == false {
        throw BackendCompatibilityProbeError.backendFailure(envelope.message ?? "Request failed")
      }
      if let message = envelope.message, !message.isEmpty, envelope.data == nil {
        throw BackendCompatibilityProbeError.backendFailure(message)
      }
      if envelope.data != nil {
        return
      }
    }

    do {
      _ = try decoder.decode(BackendSubscriptionStatusPayload.self, from: data)
    } catch {
      throw BackendCompatibilityProbeError.decoding(
        String(describing: error),
        Self.responseSnippet(from: data)
      )
    }
  }

  private static func responsePreview(from data: Data, contentType: String?) -> String {
    let prefixHex = data.prefix(16)
      .map { String(format: "%02x", $0) }
      .joined(separator: " ")
    let contentType = contentType?.lowercased() ?? ""

    guard contentType.contains("json") || contentType.contains("text") else {
      return "prefix-hex: \(prefixHex)"
    }

    return "prefix-hex: \(prefixHex), body: \(responseSnippet(from: data))"
  }

  private static func responseSnippet(from data: Data, maxLength: Int = 256) -> String {
    String(decoding: data.prefix(maxLength), as: UTF8.self)
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
  }

  @MainActor
  private func representativeMediaForDetail(from media: [MediaInfo]) -> [MediaInfo] {
    let sorted = media
      .filter { $0.apiMediaId != nil }
      .sorted { $0.compatibilityTitle < $1.compatibilityTitle }
    let maxDetailItems = 24
    var selected: [MediaInfo] = []
    var selectedIDs = Set<String>()
    var seenGroups = Set<String>()

    for item in sorted {
      let group = "\(item.apiMediaId?.split(separator: ":").first.map(String.init) ?? item.source ?? "unknown"):\(item.type ?? "unknown")"
      guard seenGroups.insert(group).inserted else { continue }
      selected.append(item)
      selectedIDs.insert(item.id)
      if selected.count >= maxDetailItems { return selected }
    }

    for item in sorted where !selectedIDs.contains(item.id) {
      selected.append(item)
      if selected.count >= maxDetailItems { break }
    }

    return selected
  }

  @MainActor
  private func representativePeopleForDetail(from people: [Person]) -> [Person] {
    let sorted = people
      .filter { $0.raw_id?.nilIfBlank != nil }
      .sorted { $0.compatibilityName < $1.compatibilityName }
    let maxPersonItems = 12
    var selected: [Person] = []
    var selectedIDs = Set<String>()
    var seenSources = Set<String>()

    for person in sorted {
      let source = person.source ?? "unknown"
      guard seenSources.insert(source).inserted else { continue }
      selected.append(person)
      selectedIDs.insert(person.id)
      if selected.count >= maxPersonItems { return selected }
    }

    for person in sorted where !selectedIDs.contains(person.id) {
      selected.append(person)
      if selected.count >= maxPersonItems { break }
    }

    return selected
  }

  private func assertProxyURLPreservesRawImage(
    _ candidate: BackendImageCandidate,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard
      let rawURLString = candidate.rawURLString,
      let components = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false)
    else {
      return
    }

    let proxyQueryName: String?
    switch components.path {
    case "/api/v1/system/img/0":
      proxyQueryName = "imgurl"
    case "/api/v1/system/cache/image":
      proxyQueryName = "url"
    default:
      proxyQueryName = nil
    }

    guard let proxyQueryName else { return }
    let queryItems = queryItemMap(from: components)

    XCTAssertNil(components.fragment, "Outer proxy URL must not have a fragment for \(candidate.label)", file: file, line: line)
    XCTAssertEqual(
      queryItems[proxyQueryName],
      rawURLString,
      "Outer proxy query must preserve the full raw image URL for \(candidate.label)",
      file: file,
      line: line
    )

    if rawURLString.contains("&") {
      XCTAssertTrue(
        candidate.url.absoluteString.contains("%26"),
        "Nested & must be percent-encoded in proxy URL for \(candidate.label)",
        file: file,
        line: line
      )
    }

    if rawURLString.contains("#") {
      XCTAssertTrue(
        candidate.url.absoluteString.contains("%23"),
        "Nested # must be percent-encoded in proxy URL for \(candidate.label)",
        file: file,
        line: line
      )
    }

    guard let rawComponents = URLComponents(string: rawURLString) else { return }
    for rawQueryItem in rawComponents.queryItems ?? [] {
      guard rawQueryItem.name != proxyQueryName else { continue }
      XCTAssertNil(
        queryItems[rawQueryItem.name],
        "Nested image query item leaked into outer proxy URL for \(candidate.label): \(rawQueryItem.name)",
        file: file,
        line: line
      )
    }
  }

  @MainActor
  private func withReadOnlyBackend(
    _ operation: @MainActor (APIService, BackendCompatibilityConfig) async throws -> Void
  ) async throws {
    let config = try BackendCompatibilityConfig.loadOrSkip()
    let service = APIService.shared
    let snapshot = BackendServiceSnapshot.capture(service: service)

    defer {
      snapshot.restore(to: service)
    }

    service.baseURL = config.baseURL
    service.token = nil

    _ = try await service.login(username: config.username, password: config.password)
    try await operation(service, config)
  }

  private func queryItemMap(from components: URLComponents) -> [String: String] {
    var result: [String: String] = [:]
    for item in components.queryItems ?? [] where result[item.name] == nil {
      result[item.name] = item.value ?? ""
    }
    return result
  }

  private func uniqueStrings(_ strings: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for string in strings {
      guard let value = string.nilIfBlank, seen.insert(value).inserted else { continue }
      result.append(value)
    }
    return result
  }

  private func uniqueInts(_ ints: [Int]) -> [Int] {
    var seen = Set<Int>()
    var result: [Int] = []
    for int in ints where seen.insert(int).inserted {
      result.append(int)
    }
    return result
  }
}

final class BackendCompatibilitySideEffectTests: XCTestCase {
  @MainActor
  func testSubscriptionSearchCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_SEARCH",
      isEnabled: { $0.testSubscriptionSearch }
    ) { service, config in
      let ids = try await recentSubscriptionIDs(service: service, limit: config.sideEffectSubscriptionLimit)
      guard !ids.isEmpty else {
        XCTFail("Subscription search side-effect test ran, but the backend has no subscriptions.")
        return
      }

      for id in ids {
        do {
          let success = try await service.searchSubscription(id: id)
          XCTAssertTrue(success, "Subscription search request was rejected for subscription \(id).")
        } catch {
          XCTFail("Failed to trigger subscription search \(id): \(error)")
        }
      }
    }
  }

  @MainActor
  func testSubscriptionUpdateCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_UPDATE",
      isEnabled: { $0.testSubscriptionUpdate }
    ) { service, config in
      let ids = try await recentSubscriptionIDs(service: service, limit: config.sideEffectSubscriptionLimit)
      guard !ids.isEmpty else {
        XCTFail("Subscription update side-effect test ran, but the backend has no subscriptions.")
        return
      }

      for id in ids {
        do {
          let detail = try await service.fetchSubscription(id: id)
          XCTAssertEqual(detail.id, id, "Subscription detail ID changed before unchanged update.")
          let success = try await service.saveSubscription(detail)
          XCTAssertTrue(success, "Unchanged subscription update was rejected for subscription \(id).")
        } catch {
          XCTFail("Failed to update subscription \(id) with its original parameters: \(error)")
        }
      }
    }
  }

  @MainActor
  func testSubscriptionPauseResumeCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_PAUSE_RESUME",
      isEnabled: { $0.testSubscriptionPauseResume }
    ) { service, config in
      let subscriptions = try await recentSubscriptions(
        service: service,
        limit: config.sideEffectSubscriptionLimit
      )
      let candidates = subscriptions.filter { subscription in
        subscription.id != nil && subscription.state == "R"
      }

      guard !candidates.isEmpty else {
        XCTFail(
          "Subscription pause/resume side-effect test ran, but no recent subscriptions were actively subscribing with state R."
        )
        return
      }

      for subscription in candidates {
        guard let id = subscription.id, let originalState = subscription.state else { continue }
        var needsRestore = false

        do {
          let toggleSuccess = try await service.updateSubscriptionStatus(id: id, state: "S")
          XCTAssertTrue(
            toggleSuccess,
            "Subscription pause R -> S was rejected for subscription \(id)."
          )
          needsRestore = toggleSuccess

          let restoreSuccess = try await service.updateSubscriptionStatus(id: id, state: originalState)
          needsRestore = false
          XCTAssertTrue(
            restoreSuccess,
            "Subscription status restore S -> \(originalState) was rejected for subscription \(id)."
          )
        } catch {
          if needsRestore {
            do {
              _ = try await service.updateSubscriptionStatus(id: id, state: originalState)
            } catch {
              XCTFail(
                "Failed to restore subscription \(id) to original state \(originalState): \(error)"
              )
            }
          }
          XCTFail(
            "Failed to pause active subscription \(id) and restore it to \(originalState): \(error)"
          )
        }
      }
    }
  }

  @MainActor
  func testSubscriptionResetThenSearchCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_SUBSCRIPTION_RESET_SEARCH",
      isEnabled: { $0.testSubscriptionResetSearch }
    ) { service, config in
      let ids = try await recentSubscriptionIDs(service: service, limit: config.sideEffectSubscriptionLimit)
      guard !ids.isEmpty else {
        XCTFail("Subscription reset/search side-effect test ran, but the backend has no subscriptions.")
        return
      }

      for id in ids {
        do {
          let resetSuccess = try await service.resetSubscription(id: id)
          XCTAssertTrue(resetSuccess, "Subscription reset request was rejected for subscription \(id).")

          let searchSuccess = try await service.searchSubscription(id: id)
          XCTAssertTrue(searchSuccess, "Subscription search after reset was rejected for subscription \(id).")
        } catch {
          XCTFail("Failed to reset and immediately search subscription \(id): \(error)")
        }
      }
    }
  }

  @MainActor
  func testManualReorganizeCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_MANUAL_REORGANIZE",
      isEnabled: { $0.testManualReorganize }
    ) { service, config in
      let histories = try await recentTransferHistories(
        service: service,
        limit: Swift.max(config.reorganizeHistoryLimit, config.reorganizeConcurrentCount)
      )
      guard !histories.isEmpty else {
        XCTFail("Manual reorganize side-effect test ran, but the backend has no transfer history.")
        return
      }

      let concurrentCount = Swift.min(config.reorganizeConcurrentCount, histories.count)
      let targets = Array(histories.prefix(concurrentCount))
      let requests = try targets.map { history in
        try manualTransferRequest(service: service, history: history)
      }

      let results = await Self.performManualTransfers(requests)
      for result in results {
        XCTAssertTrue(
          result.success,
          "Manual reorganize failed for \(result.label): \(result.diagnostic)"
        )
      }
    }
  }

  @MainActor
  func testAIReorganizeCompatibility() async throws {
    try await withSideEffectBackend(
      flagName: "MOVIEPILOT_COMPAT_TEST_AI_REORGANIZE",
      isEnabled: { $0.testAIReorganize }
    ) { service, config in
      let settings = try await service.fetchSettings()
      guard settings.AI_AGENT_ENABLE?.value ?? false else {
        throw XCTSkip("AI reorganize side-effect test ran, but the backend AI agent is disabled.")
      }

      let histories = try await recentTransferHistories(
        service: service,
        limit: config.reorganizeHistoryLimit
      )
      let ids = histories.map(\.id)
      guard !ids.isEmpty else {
        XCTFail("AI reorganize side-effect test ran, but the backend has no transfer history.")
        return
      }

      do {
        guard let result = try await service.aiRedoTransferHistory(ids: ids) else {
          XCTFail("AI reorganize did not return a progress key for history IDs \(ids).")
          return
        }

        XCTAssertFalse(result.progressKey.isEmpty, "AI reorganize returned an empty progress key.")
        XCTAssertFalse(result.acceptedIds.isEmpty, "AI reorganize accepted no history IDs.")

        let progressURL = try compatibilityAPIURL(
          service: service,
          path: "/system/progress/\(result.progressKey)"
        )
        let progress = await BackendCompatibilityReadOnlyTests.probeSSEStream(
          url: progressURL,
          token: service.token,
          timeoutSeconds: 60
        )
        XCTAssertFalse(progress.timedOut, "AI reorganize progress stream timed out.")
        XCTAssertGreaterThan(
          progress.eventCount,
          0,
          "AI reorganize progress stream produced no decodable events."
        )
        XCTAssertNil(
          progress.errorMessage,
          "AI reorganize progress stream reported error: \(progress.errorMessage ?? "")"
        )
      } catch {
        XCTFail("Failed to trigger AI reorganize for history IDs \(ids): \(error)")
      }
    }
  }

  @MainActor
  private func withSideEffectBackend(
    flagName: String,
    isEnabled: (BackendCompatibilityConfig) -> Bool,
    _ operation: @MainActor (APIService, BackendCompatibilityConfig) async throws -> Void
  ) async throws {
    let config = try BackendCompatibilityConfig.loadOrSkip()
    guard config.enableSideEffects else {
      throw XCTSkip(
        "Side-effect backend compatibility tests are disabled by MOVIEPILOT_COMPAT_ENABLE_SIDE_EFFECTS=false. Remove the false value or set it to true to run them."
      )
    }
    guard isEnabled(config) else {
      throw XCTSkip(
        "This side-effect backend compatibility test is disabled by \(flagName)=false. Remove the false value or set it to true to run it."
      )
    }

    let service = APIService.shared
    let snapshot = BackendServiceSnapshot.capture(service: service)

    defer {
      snapshot.restore(to: service)
    }

    service.baseURL = config.baseURL
    service.token = nil

    _ = try await service.login(username: config.username, password: config.password)
    try await operation(service, config)
  }

  @MainActor
  private func recentSubscriptionIDs(service: APIService, limit: Int) async throws -> [Int] {
    let subscriptions = try await recentSubscriptions(service: service, limit: limit)
    return Array(subscriptions.compactMap(\.id).prefix(limit))
  }

  @MainActor
  private func recentSubscriptions(service: APIService, limit: Int) async throws -> [Subscribe] {
    let subscriptions = try await service.fetchSubscriptions()
    return Array(subscriptions.prefix(limit))
  }

  @MainActor
  private func recentTransferHistories(service: APIService, limit: Int) async throws -> [TransferHistory] {
    let pageSize = Swift.max(limit, 20)
    let history = try await service.fetchTransferHistory(page: 1, count: pageSize, title: nil)
    return Array(history.list.prefix(limit))
  }

  @MainActor
  private func manualTransferRequest(
    service: APIService,
    history: TransferHistory
  ) throws -> BackendManualTransferRequest {
    let form = ReorganizeForm(
      fileitem: history.src_fileitem,
      logid: history.id,
      target_storage: history.dest_storage?.nilIfBlank ?? "local",
      transfer_type: "",
      target_path: "",
      min_filesize: 0,
      scrape: false,
      from_history: false
    )
    let body = try JSONEncoder().encode(form)
    let url = try compatibilityAPIURL(
      service: service,
      path: "/transfer/manual",
      params: ["background": "true"]
    )

    return BackendManualTransferRequest(
      label: "\(history.id) \(history.title ?? "")",
      url: url,
      token: service.token,
      body: body
    )
  }

  private static func performManualTransfers(
    _ requests: [BackendManualTransferRequest]
  ) async -> [BackendManualTransferResult] {
    await withTaskGroup(of: BackendManualTransferResult.self) { group in
      for request in requests {
        group.addTask {
          await performManualTransfer(request)
        }
      }

      var results: [BackendManualTransferResult] = []
      for await result in group {
        results.append(result)
      }
      return results
    }
  }

  private static func performManualTransfer(
    _ requestInfo: BackendManualTransferRequest
  ) async -> BackendManualTransferResult {
    do {
      var request = URLRequest(url: requestInfo.url)
      request.httpMethod = "POST"
      request.timeoutInterval = 60
      request.httpBody = requestInfo.body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let token = requestInfo.token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return BackendManualTransferResult(
          label: requestInfo.label,
          success: false,
          message: nil,
          diagnostic: "Non-HTTP response."
        )
      }

      let action = try? JSONDecoder().decode(BackendActionResponse.self, from: data)
      let success = (200...299).contains(httpResponse.statusCode) && (action?.success ?? true)
      return BackendManualTransferResult(
        label: requestInfo.label,
        success: success,
        message: action?.message,
        diagnostic:
          "HTTP \(httpResponse.statusCode), content-type: \(httpResponse.contentTypeDescription), bytes: \(data.count), message: \(action?.message ?? "n/a"), body: \(Self.responseSnippet(from: data))"
      )
    } catch {
      return BackendManualTransferResult(
        label: requestInfo.label,
        success: false,
        message: nil,
        diagnostic: String(describing: error)
      )
    }
  }

  @MainActor
  private func compatibilityAPIURL(
    service: APIService,
    path: String,
    params: [String: String?] = [:]
  ) throws -> URL {
    let endpoint = "\(service.baseURL)/api/v1\(path)"
    guard var components = URLComponents(string: endpoint) else {
      throw BackendCompatibilityProbeError.invalidURL(endpoint)
    }

    var queryItems = components.queryItems ?? []
    for (name, value) in params.sorted(by: { $0.key < $1.key }) {
      if let value {
        queryItems.append(URLQueryItem(name: name, value: value))
      }
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components.url else {
      throw BackendCompatibilityProbeError.invalidURL(endpoint)
    }
    return url
  }

  private static func responseSnippet(from data: Data, maxLength: Int = 256) -> String {
    String(decoding: data.prefix(maxLength), as: UTF8.self)
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
  }
}

private extension MediaInfo {
  @MainActor
  var compatibilityTitle: String {
    title ?? original_title ?? original_name ?? apiMediaId ?? id
  }
}

private extension Person {
  @MainActor
  var compatibilityName: String {
    name ?? latin_name ?? original_name ?? raw_id ?? id
  }

  @MainActor
  var compatibilityRawImageURL: String? {
    if let profilePath = profile_path, profilePath.hasPrefix("http") {
      return profilePath
    }

    if source == "themoviedb" || (source == nil && profile_path?.hasPrefix("/") == true) {
      guard let profilePath = profile_path else { return nil }
      let domain = APIService.shared.settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
      return "https://\(domain)/t/p/w600_and_h900_bestv2\(profilePath)"
    }

    if source == "douban" {
      switch avatar {
      case .object(let normal):
        return normal
      case .url(let link):
        return link
      case .none:
        return nil
      }
    }

    if source == "bangumi" {
      return images?.medium
    }

    return nil
  }
}

private extension TmdbSeason {
  @MainActor
  var compatibilityRawPosterURL: String? {
    guard let posterPath = poster_path?.nilIfBlank else { return nil }
    if posterPath.hasPrefix("http") {
      return posterPath
    }
    let domain = APIService.shared.settings?.TMDB_IMAGE_DOMAIN ?? "image.tmdb.org"
    return "https://\(domain)/t/p/w500\(posterPath)"
  }
}

private extension HTTPURLResponse {
  var contentTypeDescription: String {
    value(forHTTPHeaderField: "Content-Type") ?? "unknown"
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var trimmingTrailingSlashes: String {
    var value = self
    while value.count > 1, value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }

  var strippingMatchingQuotes: String {
    guard count >= 2 else { return self }
    if (hasPrefix("\"") && hasSuffix("\"")) || (hasPrefix("'") && hasSuffix("'")) {
      return String(dropFirst().dropLast())
    }
    return self
  }

  var listValue: [String]? {
    let items = split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return items.isEmpty ? nil : items
  }

  var intValue: Int? {
    Int(trimmingCharacters(in: .whitespacesAndNewlines))
  }

  var intListValue: [Int]? {
    let items = split(separator: ",")
      .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    return items.isEmpty ? nil : items
  }

  func clampedIntValue(minimum: Int, maximum: Int) -> Int? {
    guard let value = intValue else { return nil }
    return Swift.min(Swift.max(value, minimum), maximum)
  }

  func boolValue(fallback: Bool) -> Bool {
    switch trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "y", "on":
      return true
    case "0", "false", "no", "n", "off":
      return false
    default:
      return fallback
    }
  }
}
