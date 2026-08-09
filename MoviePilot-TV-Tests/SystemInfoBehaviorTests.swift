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
