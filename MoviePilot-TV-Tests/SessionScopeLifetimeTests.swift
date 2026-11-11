import XCTest

@testable import MoviePilot_TV

@MainActor
final class SessionScopeLifetimeTests: XCTestCase {
  func testUnusedSessionResourcesReleaseWithoutExplicitLogout() {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }

    var references: [SessionResourceReferences] = []
    for _ in 0..<20 {
      let service = APIService.isolatedTestingInstance()
      references.append(SessionResourceReferences(service: service))
    }

    XCTAssertEqual(references.filter { $0.service != nil }.count, 0)
    XCTAssertTrue(references.allSatisfy { $0.scope == nil })
    XCTAssertTrue(references.allSatisfy { $0.preloader == nil })
    XCTAssertTrue(references.allSatisfy { $0.warmer == nil })
  }

  func testCachedPreloadTaskDoesNotKeepSessionAlive() {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }

    var service: APIService? = APIService.isolatedTestingInstance()
    let references = SessionResourceReferences(service: service!)
    let media = MediaInfo(title: "缓存生命周期", type: "collection", collection_id: 47)
    weak var task: MediaPreloadTask?
    task = service?.mediaPreloader.preload(for: media)
    XCTAssertNotNil(task)

    service = nil

    XCTAssertNil(references.service)
    XCTAssertNil(references.scope)
    XCTAssertNil(references.preloader)
    XCTAssertNil(references.warmer)
    XCTAssertNil(task)
  }

  func testCompletedTVPreloadAndSeasonModelReleaseWithSession() async throws {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionLifetimeURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionLifetimeURLProtocol.self) }

    var service: APIService? = APIService.isolatedTestingInstance()
    configure(service!)
    let references = SessionResourceReferences(service: service!)
    let media = MediaInfo(tmdb_id: 47, title: "分季生命周期", type: "电视剧")
    weak var task: MediaPreloadTask?
    task = service?.mediaPreloader.acquireNavigation(for: media, owner: UUID())
    try await waitUntil { task?.isSeasonDataLoaded == true && task?.isDetailReady == true }
    weak var seasonModel: SubscribeSeasonViewModel?
    seasonModel = task?.seasonViewModel
    XCTAssertEqual(seasonModel?.seasonInfos.first?.season_number, 1)
    XCTAssertEqual(seasonModel?.seasonSubscriptions[1]?.id, 4701)
    XCTAssertEqual(task?.fullDetail?.title, "分季生命周期")

    service = nil

    // 状态发布后，已完成的 async 任务还可能需要一次 executor 交接才能退休。
    try await waitUntil { references.service == nil }
    XCTAssertNil(references.scope)
    XCTAssertNil(references.preloader)
    XCTAssertNil(references.warmer)
    XCTAssertNil(task)
    XCTAssertNil(seasonModel)
  }

  func testRetainedScopeIsTornDownWhenServiceReleases() async throws {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    var service: APIService? = APIService.isolatedTestingInstance()
    configure(service!)
    weak var releasedService: APIService?
    releasedService = service
    let scope = service!.sessionScope
    let media = MediaInfo(title: "外部保留的作用域", type: "collection", collection_id: 48)
    _ = scope.mediaPreloader.preload(for: media)

    service = nil

    XCTAssertNil(releasedService)
    XCTAssertNil(scope.mediaPreloader.peekTask(for: media))
    guard releasedService == nil else { return }
    let url = try XCTUnwrap(URL(
      string: "https://session-lifetime.local/api/v1/system/cache/image?url=https%3A%2F%2Fimage.example%2Fa.jpg"
    ))
    let handle = await scope.imageWarmer.warm(
      url, baseURL: "https://session-lifetime.local", imageCacheEnabled: true
    )
    XCTAssertNil(handle)
    XCTAssertEqual(scope.imageWarmer.activeRequestCount, 0)
  }

  func testStandaloneWarmerDoesNotRetainService() async throws {
    let persistence = APIServicePersistenceSnapshot.capture()
    defer { persistence.restore() }
    var service: APIService? = APIService.isolatedTestingInstance()
    configure(service!)
    weak var releasedService: APIService?
    releasedService = service
    let warmer = MPImageWarmer(apiService: service!)

    service = nil

    XCTAssertNil(releasedService)
    guard releasedService == nil else { return }
    let url = try XCTUnwrap(URL(
      string: "https://session-lifetime.local/api/v1/system/cache/image?url=https%3A%2F%2Fimage.example%2Fa.jpg"
    ))
    let handle = await warmer.warm(url)
    XCTAssertNil(handle)
    XCTAssertEqual(warmer.activeRequestCount, 0)
  }

  private func configure(_ service: APIService) {
    let token = Token(
      access_token: "lifetime-fixture", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true, "subscribe": true], user_id: 47,
      user_name: "lifetime-fixture", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "https://session-lifetime.local", token: token.access_token, currentUser: token
    )
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "生命周期或加载状态未收敛")
  }
}

@MainActor
private final class SessionResourceReferences {
  weak var service: APIService?
  weak var scope: SessionScope?
  weak var preloader: MediaPreloader?
  weak var warmer: MPImageWarmer?

  init(service: APIService) {
    self.service = service
    scope = service.sessionScope
    preloader = service.mediaPreloader
    warmer = service.imageWarmer
  }
}

private final class SessionLifetimeURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let body: String
    switch url.path {
    case "/api/v1/media/47":
      body = """
        {"tmdb_id":47,"title":"分季生命周期","type":"电视剧",\
        "season_info":[{"season_number":1,"name":"第 1 季","episode_count":10}]}
        """
    case "/api/v1/media/groups/47", "/api/v1/mediaserver/notexists":
      body = "[]"
    case "/api/v1/subscribe", "/api/v1/subscribe/":
      body = """
        [{"id":4701,"name":"分季生命周期","type":"电视剧","season":1,"tmdbid":47}]
        """
    default:
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
