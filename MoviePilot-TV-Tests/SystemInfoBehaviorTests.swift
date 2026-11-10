import XCTest

@testable import MoviePilot_TV

@MainActor
extension SystemSessionBehaviorTests {
  func testLoadSystemInfoUsesPublicSettingsForNonManageUserWithoutRequestingSystemEnv()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = nonManageToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )
    clearCredential(account: "username")
    clearCredential(account: "password")

    let logoutNotifications = NotificationCounter()
    let observer = NotificationCenter.default.addObserver(
      forName: .sessionDidLogout,
      object: nil,
      queue: nil
    ) { _ in
      logoutNotifications.increment()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let viewModel = SystemViewModel(apiService: service)
    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    XCTAssertEqual(service.token, "limited-token")
    XCTAssertEqual(service.currentUser?.user_name, "limited")
    XCTAssertEqual(logoutNotifications.count(), 0)
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
  }

  func testLoadSystemInfoFetchesPublicBackendVersionForNonManageUserWhenCacheIsEmpty()
    async throws
  {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = nonManageToken()
    service.settings = nil
    clearCredential(account: "username")
    clearCredential(account: "password")

    let viewModel = SystemViewModel(apiService: service)
    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setSystemEnvStatusCode(403)

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
  }

  func testRecheckingBackendVersionAlsoUpdatesTheVersionRow() async throws {
    // 播放设置页按“重新检查”后，连接信息里的「MoviePilot 版本」也要显示新版本。
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = nonManageToken()
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.5")

    let viewModel = SystemViewModel(apiService: service)
    viewModel.backendVersion = "v3.2.5"

    await viewModel.recheckBackendVersion()

    XCTAssertEqual(service.settings?.BACKEND_VERSION, "v9.9.9")
    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    XCTAssertFalse(viewModel.isCheckingBackendVersion)
  }

  func testFailedBackendVersionRecheckIsShownAndCanBeRetried() async throws {
    // 后端升级后重新检查时请求失败：要和“版本确实过低”分开显示，按一下可以重试。
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    await SystemInfoURLProtocol.stub.setGlobalSettingsStatusCode(503)
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "limited-token"
    service.currentUserForTesting = nonManageToken()
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.5")
    let viewModel = SystemViewModel(apiService: service)

    await viewModel.recheckBackendVersion()
    XCTAssertTrue(viewModel.backendVersionCheckFailed)
    XCTAssertEqual(viewModel.playbackSettingRows, [.versionRequirement])

    await SystemInfoURLProtocol.stub.setGlobalSettingsStatusCode(200)
    await viewModel.recheckBackendVersion()
    XCTAssertFalse(viewModel.backendVersionCheckFailed)
    XCTAssertEqual(service.settings?.BACKEND_VERSION, "v9.9.9")
  }

  func testPlaybackSettingsFollowAutoPlayChangedInThePlayer() async throws {
    // 设置页停在「播放」子页，用户在播放界面工具栏改了自动播放，切回来要显示新值。
    let key = PlaybackPreferences.autoPlayNextEpisodeKey
    let saved = UserDefaults.standard.object(forKey: key) as? Bool
    defer {
      if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    PlaybackPreferences.setAutoPlaysNextEpisode(true)
    let viewModel = SystemViewModel(apiService: APIService.isolatedTestingInstance())
    XCTAssertTrue(viewModel.autoPlayNextEpisode)

    PlaybackPreferences.setAutoPlaysNextEpisode(false)
    for _ in 0..<200 where viewModel.autoPlayNextEpisode {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(viewModel.autoPlayNextEpisode)
  }

  func testAutomaticMemoryOptimizationFollowsPlaybackAvailableToCurrentSession() {
    let defaults = UserDefaults.standard
    let modeKey = MemoryOptimizationSettings.modeKey
    let playbackKey = PlaybackPreferences.inAppPlaybackKey
    let originalMode = defaults.object(forKey: modeKey)
    let originalPlayback = defaults.object(forKey: playbackKey)
    defer {
      defaults.set(originalMode, forKey: modeKey)
      defaults.set(originalPlayback, forKey: playbackKey)
    }

    let service = APIService.isolatedTestingInstance()
    service.currentUserForTesting = superUserToken()
    service.settings = GlobalSettings(BACKEND_VERSION: "v3.2.5")
    defaults.removeObject(forKey: playbackKey)
    let settings = MemoryOptimizationSettings(apiService: service)
    settings.mode = .automatic
    XCTAssertTrue(PlaybackPreferences.isInAppPlaybackEnabled)
    XCTAssertTrue(settings.automaticIsEnabled)
    XCTAssertTrue(settings.isEnabled)

    for version in [nil, "custom", "v3.2.6", "v3.2.6-1"] {
      service.settings = GlobalSettings(BACKEND_VERSION: version)
      XCTAssertEqual(settings.isEnabled, version == nil || version == "custom")
    }
    PlaybackPreferences.setInAppPlaybackEnabled(false)
    XCTAssertTrue(settings.isEnabled)
    PlaybackPreferences.setInAppPlaybackEnabled(true)
    XCTAssertFalse(settings.isEnabled)

    settings.mode = .enabled
    XCTAssertTrue(settings.isEnabled)
    settings.mode = .automatic
    service.currentUserForTesting = nonManageToken()
    XCTAssertTrue(settings.isEnabled)
    settings.mode = .disabled
    XCTAssertFalse(settings.isEnabled)
  }

  func testLoadSystemInfoUsesPublicBackendVersionForManageNonSuperuser() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "manage-token"
    service.currentUserForTesting = manageToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )

    let viewModel = SystemViewModel(apiService: service)
    await SystemInfoURLProtocol.stub.reset()

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v9.9.9")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertFalse(paths.contains("/api/v1/system/env"))
    XCTAssertTrue(paths.contains("/api/v1/system/global"))
    XCTAssertTrue(paths.contains("/api/v1/system/global/user"))
  }

  func testLoadSystemInfoUsesSystemEnvBackendVersionForSuperUser() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SystemInfoURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SystemInfoURLProtocol.self) }

    await SystemInfoURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    service.baseURLForTesting = "https://system-info-tests.local"
    service.tokenForTesting = "super-token"
    service.currentUserForTesting = superUserToken()
    service.settings = try JSONDecoder().decode(
      GlobalSettings.self,
      from:
        #"{"BACKEND_VERSION":"v2.13.13","FRONTEND_VERSION":"v2.13.15","TMDB_IMAGE_DOMAIN":"image.tmdb.org"}"#
        .data(using: .utf8)!
    )

    let viewModel = SystemViewModel(apiService: service)
    await SystemInfoURLProtocol.stub.reset()

    await viewModel.loadSystemInfo()

    XCTAssertEqual(viewModel.backendVersion, "v2.13.14")
    let paths = await SystemInfoURLProtocol.stub.requestPaths()
    XCTAssertTrue(paths.contains("/api/v1/system/env"))
  }

  private func nonManageToken() -> Token {
    Token(
      access_token: "limited-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true,
        "search": false,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "limited",
      avatar: nil
    )
  }

  private func manageToken() -> Token {
    Token(
      access_token: "manage-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": false,
        "search": false,
        "subscribe": false,
        "manage": true,
      ],
      user_name: "manager",
      avatar: nil
    )
  }

  private func superUserToken() -> Token {
    Token(
      access_token: "super-token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [
        "discovery": true,
        "search": true,
        "subscribe": true,
        "manage": true,
      ],
      user_name: "admin",
      avatar: nil
    )
  }
}
