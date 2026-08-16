import XCTest

@testable import MoviePilot_TV

@MainActor
extension SystemSessionBehaviorTests {
  func testAccountPreferencesUseStableBackendUserIDInsteadOfUsername() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let accountA = sessionToken(userId: 41, accessToken: "a-1", userName: "old-name")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountA.access_token,
      currentUser: accountA
    )
    let accountAKey = "defaultSearchSites_\(service.profileKey!)"
    let oldAccountAValue = UserDefaults.standard.array(forKey: accountAKey)
    let accountBKey = "defaultSearchSites_https://account.local|user:42"
    let oldAccountBValue = UserDefaults.standard.array(forKey: accountBKey)
    defer {
      restoreUserDefaultsArray(oldAccountAValue, forKey: accountAKey)
      restoreUserDefaultsArray(oldAccountBValue, forKey: accountBKey)
    }
    SystemViewModel().defaultSearchSites = [3, 7]

    let renamedAccountA = sessionToken(userId: 41, accessToken: "a-2", userName: "new-name")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: renamedAccountA.access_token,
      currentUser: renamedAccountA
    )
    XCTAssertEqual(SystemViewModel().defaultSearchSites, [3, 7])

    let accountB = sessionToken(userId: 42, accessToken: "b-1", userName: "old-name")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: accountB.access_token,
      currentUser: accountB
    )
    XCTAssertTrue(SystemViewModel().defaultSearchSites.isEmpty)
  }

  func testAccountPreferencesMigrateFromLegacyUsernameKey() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let account = sessionToken(userId: 41, accessToken: "a-1", userName: "old-name")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: account.access_token,
      currentUser: account
    )
    let legacyKey = "defaultSearchSites_https://account.local_old-name"
    let stableKey = "defaultSearchSites_\(service.profileKey!)"
    let oldLegacyValue = UserDefaults.standard.array(forKey: legacyKey)
    let oldStableValue = UserDefaults.standard.array(forKey: stableKey)
    defer {
      restoreUserDefaultsArray(oldLegacyValue, forKey: legacyKey)
      restoreUserDefaultsArray(oldStableValue, forKey: stableKey)
    }
    UserDefaults.standard.set([3, 7], forKey: legacyKey)
    UserDefaults.standard.removeObject(forKey: stableKey)

    XCTAssertEqual(SystemViewModel().defaultSearchSites, [3, 7])
    XCTAssertEqual(UserDefaults.standard.array(forKey: stableKey) as? [Int], [3, 7])
    XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
  }

  func testHomeMediaServerPreferenceMigratesIntoCurrentProfile() {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }
    let account = sessionToken(userId: 41, accessToken: "a-1", userName: "account-a")
    service.replaceSessionForTesting(
      baseURL: "https://account.local",
      token: account.access_token,
      currentUser: account
    )
    let legacyKey = "home.latestMedia.selectedServer.v1"
    let stableKey = "home.latestMedia.selectedServer.v2_\(service.profileKey!)"
    let oldLegacyValue = UserDefaults.standard.string(forKey: legacyKey)
    let oldStableValue = UserDefaults.standard.string(forKey: stableKey)
    defer {
      restoreUserDefaultsString(oldLegacyValue, forKey: legacyKey)
      restoreUserDefaultsString(oldStableValue, forKey: stableKey)
    }
    UserDefaults.standard.set("Emby-A", forKey: legacyKey)
    UserDefaults.standard.removeObject(forKey: stableKey)

    XCTAssertEqual(HomeViewModel(apiService: service).selectedLatestMediaServer, "Emby-A")
    XCTAssertEqual(UserDefaults.standard.string(forKey: stableKey), "Emby-A")
    XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
  }

  func testSystemViewModelSiteLoadSuccessEmptyClearsStaleDefaultSites() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SiteListURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SiteListURLProtocol.self) }

    SiteListURLProtocol.reset()
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    let service = APIService.isolatedTestingInstance()
    let account = sessionToken(userId: 11, accessToken: "site-user", userName: "site-user")
    service.replaceSessionForTesting(
      baseURL: "http://site-load-state.local",
      token: account.access_token,
      currentUser: account
    )
    let preferenceKey = "defaultSearchSites_\(service.profileKey!)"
    let oldValue = UserDefaults.standard.array(forKey: preferenceKey)
    defer { restoreUserDefaultsArray(oldValue, forKey: preferenceKey) }

    let viewModel = SystemViewModel(apiService: service)
    viewModel.defaultSearchSites = [1]
    XCTAssertEqual(viewModel.defaultSearchSites, [1])

    SiteListURLProtocol.sitesJSON = "[]"
    await viewModel.loadSites()

    XCTAssertTrue(viewModel.availableSites.isEmpty)
    XCTAssertTrue(viewModel.defaultSearchSites.isEmpty)
    XCTAssertNil(viewModel.siteLoadError)
  }

  func testSystemViewModelSiteLoadFailureKeepsSelectionAndReportsError() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SiteListURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SiteListURLProtocol.self) }

    SiteListURLProtocol.reset()
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    let service = APIService.isolatedTestingInstance()
    let account = sessionToken(userId: 11, accessToken: "site-user", userName: "site-user")
    service.replaceSessionForTesting(
      baseURL: "http://site-load-state.local",
      token: account.access_token,
      currentUser: account
    )
    let preferenceKey = "defaultSearchSites_\(service.profileKey!)"
    let oldValue = UserDefaults.standard.array(forKey: preferenceKey)
    defer { restoreUserDefaultsArray(oldValue, forKey: preferenceKey) }

    SiteListURLProtocol.sitesJSON =
      #"[{"id":1,"name":"站点A","domain":null,"url":null,"downloader":null,"is_active":true}]"#
    let viewModel = SystemViewModel(apiService: service)
    await viewModel.loadSites()
    XCTAssertEqual(viewModel.availableSites.map(\.id), [1])
    viewModel.defaultSearchSites = [1]

    SiteListURLProtocol.loadError = URLError(.badServerResponse)
    await viewModel.loadSites()

    XCTAssertEqual(viewModel.availableSites.map(\.id), [1])
    XCTAssertEqual(viewModel.defaultSearchSites, [1])
    XCTAssertNotNil(viewModel.siteLoadError)
  }

  func testSystemViewModelPreferenceWriteBeforeSiteLoadKeepsSelection() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    let service = APIService.isolatedTestingInstance()
    let account = sessionToken(userId: 11, accessToken: "site-user", userName: "site-user")
    service.replaceSessionForTesting(
      baseURL: "http://site-load-state.local",
      token: account.access_token,
      currentUser: account
    )
    let preferenceKey = "defaultSearchSites_\(service.profileKey!)"
    let oldValue = UserDefaults.standard.array(forKey: preferenceKey)
    defer { restoreUserDefaultsArray(oldValue, forKey: preferenceKey) }

    let viewModel = SystemViewModel(apiService: service)
    viewModel.defaultSearchSites = [1, 999]

    XCTAssertEqual(viewModel.defaultSearchSites, [1, 999])
  }

  func testSiteFilterViewModelSiteLoadSuccessEmptyClearsStaleSelection() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SiteListURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SiteListURLProtocol.self) }

    SiteListURLProtocol.reset()
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    let service = APIService.isolatedTestingInstance()
    let account = sessionToken(userId: 11, accessToken: "site-user", userName: "site-user")
    service.replaceSessionForTesting(
      baseURL: "http://site-load-state.local",
      token: account.access_token,
      currentUser: account
    )

    let viewModel = SiteFilterViewModel(apiService: service)
    viewModel.selectedSites = [1]
    SiteListURLProtocol.sitesJSON = "[]"
    await viewModel.loadSites()

    XCTAssertTrue(viewModel.availableSites.isEmpty)
    XCTAssertTrue(viewModel.selectedSites.isEmpty)
  }
}

private final class SiteListURLProtocol: URLProtocol {
  nonisolated(unsafe) static var sitesJSON: String = "[]"
  nonisolated(unsafe) static var loadError: Error?

  static func reset() {
    sitesJSON = "[]"
    loadError = nil
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.path == "/api/v1/site/rss"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    if let loadError = Self.loadError {
      client?.urlProtocol(self, didFailWithError: loadError)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.sitesJSON.data(using: .utf8)!)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
