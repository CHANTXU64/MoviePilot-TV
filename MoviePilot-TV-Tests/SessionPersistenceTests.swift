import XCTest

@testable import MoviePilot_TV

@MainActor
extension SystemSessionBehaviorTests {
  func testStoredSessionRevisionMismatchFailsClosed() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    UserDefaults.standard.set(
      Data(#"{"revision":7,"storage":"userDefaults"}"#.utf8),
      forKey: "sessionMarker.v2"
    )
    UserDefaults.standard.set(
      #"{"revision":6,"baseURL":"https://stale.local","token":"stale-token","currentUser":null,"username":"stale","password":"stale","imageNamespace":"stale"}"#,
      forKey: "sessionRecord.v2"
    )

    let restoredService = APIService.testingInstance()

    XCTAssertNil(restoredService.token)
    XCTAssertNil(restoredService.currentUser)
    XCTAssertNil(restoredService.profileKey)
  }

  func testStoredSessionTombstoneBlocksLegacyCredentialResurrection() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    UserDefaults.standard.set(
      Data(#"{"revision":9,"storage":"tombstone"}"#.utf8),
      forKey: "sessionMarker.v2"
    )
    UserDefaults.standard.set("legacy-token", forKey: "accessToken")
    persistStoredCurrentUserJSON(
      #"{"access_token":"legacy-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true},"user_id":99,"user_name":"legacy","avatar":null}"#
    )

    let restoredService = APIService.testingInstance()

    XCTAssertNil(restoredService.token)
    XCTAssertNil(restoredService.currentUser)
    XCTAssertNil(restoredService.profileKey)
  }

  func testCorruptStoredSessionMarkerBlocksLegacyCredentialResurrection() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    UserDefaults.standard.set(Data("not-json".utf8), forKey: "sessionMarker.v2")
    UserDefaults.standard.set("legacy-token", forKey: "accessToken")
    persistStoredCurrentUserJSON(
      #"{"access_token":"legacy-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true},"user_id":99,"user_name":"legacy","avatar":null}"#
    )

    let restoredService = APIService.testingInstance()

    XCTAssertNil(restoredService.token)
    XCTAssertNil(restoredService.currentUser)
    XCTAssertNil(restoredService.profileKey)
  }

  func testLegacySessionMigrationClearsLegacyCredentialsAndCannotResurrect() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }

    UserDefaults.standard.removeObject(forKey: "sessionMarker.v2")
    UserDefaults.standard.removeObject(forKey: "sessionRecord.v2")
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "sessionRecord.v2")
    _ = KeychainHelper.shared.save(
      "legacy-token", service: "MoviePilot-TV", account: "accessToken")
    UserDefaults.standard.set("legacy-token", forKey: "accessToken")
    persistStoredCurrentUserJSON(
      #"{"access_token":"legacy-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true},"user_id":99,"user_name":"legacy","avatar":null}"#
    )
    _ = KeychainHelper.shared.save(
      "legacy-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save(
      "legacy-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("legacy-user", forKey: "username")
    UserDefaults.standard.set("legacy-password", forKey: "password")

    let migratedService = APIService.testingInstance()

    XCTAssertEqual(migratedService.token, "legacy-token")
    XCTAssertNotNil(UserDefaults.standard.data(forKey: "sessionMarker.v2"))
    for account in ["accessToken", "currentUser", "username", "password"] {
      XCTAssertNil(effectiveCredential(account: account))
    }

    UserDefaults.standard.removeObject(forKey: "sessionMarker.v2")
    let restoredAfterMarkerLoss = APIService.testingInstance()

    XCTAssertNil(restoredAfterMarkerLoss.token)
    XCTAssertNil(restoredAfterMarkerLoss.currentUser)
  }

  func testLegacyCredentialsWithoutTokenAreClearedInsteadOfReloggedIn() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }

    UserDefaults.standard.removeObject(forKey: "sessionMarker.v2")
    UserDefaults.standard.removeObject(forKey: "sessionRecord.v2")
    _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: "sessionRecord.v2")
    clearCredential(account: "accessToken")
    clearCredential(account: "currentUser")
    _ = KeychainHelper.shared.save("orphan-user", service: "MoviePilot-TV", account: "username")
    _ = KeychainHelper.shared.save("orphan-password", service: "MoviePilot-TV", account: "password")
    UserDefaults.standard.set("orphan-user", forKey: "username")
    UserDefaults.standard.set("orphan-password", forKey: "password")

    let restoredService = APIService.testingInstance()

    XCTAssertNil(restoredService.token)
    XCTAssertNil(restoredService.currentUser)
    XCTAssertNil(effectiveCredential(account: "username"))
    XCTAssertNil(effectiveCredential(account: "password"))
  }

  func testSuccessfulLoginRestoresCompleteUnifiedSessionRecord() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }

    await SessionRefreshURLProtocol.stub.reset()
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }
    let service = APIService.testingInstance()

    _ = try await service.login(
      username: "test-user",
      password: "test-password",
      serverURL: "https://session-refresh-tests.local"
    )
    let restoredService = APIService.testingInstance()

    XCTAssertEqual(restoredService.baseURL, "https://session-refresh-tests.local")
    XCTAssertEqual(restoredService.token, "fresh-token")
    XCTAssertEqual(restoredService.currentUser?.access_token, "fresh-token")
    XCTAssertEqual(restoredService.currentUser?.user_id, 1)
    XCTAssertEqual(restoredService.currentUser?.user_name, "test-user")
    XCTAssertEqual(restoredService.profileKey, "https://session-refresh-tests.local|user:1")
  }

  func testTokenOnlySessionFallsBackToPersistedSnapshotForProfilePreferences() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }

    clearCredential(account: "currentUser")
    persistStoredCurrentUserJSON(
      #"{"access_token":"snapshot-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true},"user_id":99,"user_name":"snapshot-user","avatar":null}"#
    )
    sharedService.replaceSessionForTesting(
      baseURL: "https://token-only.local",
      token: "snapshot-token",
      currentUser: nil
    )

    XCTAssertNil(sharedService.currentUser)
    XCTAssertEqual(sharedService.profileKey, "https://token-only.local|user:99")

    let preferenceKey = "defaultSearchSites_https://token-only.local|user:99"
    let oldValue = UserDefaults.standard.array(forKey: preferenceKey)
    defer { restoreUserDefaultsArray(oldValue, forKey: preferenceKey) }
    let viewModel = SystemViewModel()
    viewModel.defaultSearchSites = [3, 7]
    XCTAssertEqual(UserDefaults.standard.array(forKey: preferenceKey) as? [Int], [3, 7])
    XCTAssertEqual(SystemViewModel().defaultSearchSites, [3, 7])
  }

  func testTokenOnlySessionRejectsSnapshotWithMismatchedToken() {
    let sharedService = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: sharedService)
    defer { snapshot.restore(to: sharedService) }

    clearCredential(account: "currentUser")
    persistStoredCurrentUserJSON(
      #"{"access_token":"other-token","token_type":"bearer","super_user":false,"permissions":{"discovery":true},"user_id":98,"user_name":"other-user","avatar":null}"#
    )
    sharedService.replaceSessionForTesting(
      baseURL: "https://token-only.local",
      token: "current-token",
      currentUser: nil
    )

    XCTAssertNil(sharedService.currentUser)
    XCTAssertNil(sharedService.profileKey)
  }
}
