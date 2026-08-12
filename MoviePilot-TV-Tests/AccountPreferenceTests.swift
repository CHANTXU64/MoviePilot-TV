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
}
