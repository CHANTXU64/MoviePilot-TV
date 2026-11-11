import Security
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TestIsolationTests: XCTestCase {
  func testHostUsesSeparateAppGroupAndKeychainAccessGroup() throws {
    let identifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
    XCTAssertEqual(identifier, "org.chantxu.MoviePilot-TV.Testing")
    let group = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "TopShelfAppGroupIdentifier") as? String)
    XCTAssertEqual(group, "group.\(identifier)")
    XCTAssertNotNil(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                   "MoviePilot TV Tests")
    let extensionURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
      .appendingPathComponent("MoviePilot-TV-TopShelf.appex")
    let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
    XCTAssertEqual(extensionBundle.bundleIdentifier, "\(identifier).TopShelf")
    XCTAssertEqual(TopShelfAppGroup.identifier(in: extensionBundle), group)
    let executable = try XCTUnwrap(extensionBundle.executableURL)
    let entitlements = try XCTUnwrap(
      TopShelfSigningMetadata.entitlements(in: Data(contentsOf: executable)))
    XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], [group])

    let account = "test-isolation-\(UUID().uuidString)"
    XCTAssertTrue(KeychainHelper.shared.save("fixture", service: "MoviePilot-TV", account: account))
    defer { _ = KeychainHelper.shared.delete(service: "MoviePilot-TV", account: account) }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "MoviePilot-TV",
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: true,
    ]
    var attributes: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
    let accessGroup = try XCTUnwrap((attributes as? [String: Any])?[kSecAttrAccessGroup as String] as? String)
    XCTAssertTrue(accessGroup.hasSuffix(".\(identifier)"))
  }

  func testSnapshotRestoresInMemoryPasswordForAutomaticRelogin() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(SessionRefreshURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(SessionRefreshURLProtocol.self) }
    await SessionRefreshURLProtocol.stub.reset()
    let service = APIService.isolatedTestingInstance()
    let persistence = service.persistenceSnapshotForTesting()
    let refreshKey = APIService.sessionRefreshAppVersionKey
    let refreshMarker = UserDefaults.standard.object(forKey: refreshKey)
    defer {
      service.restorePersistenceSnapshotForTesting(persistence)
      if let refreshMarker {
        UserDefaults.standard.set(refreshMarker, forKey: refreshKey)
      } else {
        UserDefaults.standard.removeObject(forKey: refreshKey)
      }
    }
    service.replaceSessionForTesting(
      baseURL: "https://session-refresh-tests.local", token: "old-token", currentUser: nil)
    // Deliberately do not persist these credentials: restoration must capture memory too.
    service.setStoredCredentialsForTesting(username: "test-user", password: "saved-password")
    let original = SystemSessionServiceSnapshot.capture(service: service)
    service.replaceSessionForTesting(baseURL: "https://other.local", token: nil, currentUser: nil)

    original.restore(to: service)
    let result = await service.refreshStoredSessionAfterAppUpdateIfNeeded(
      appVersion: "isolation-\(UUID().uuidString)")

    XCTAssertEqual(result, .refreshed)
    XCTAssertEqual(service.token, "fresh-token")
    let stored = service.persistenceSnapshotForTesting()
    XCTAssertEqual(stored.username, "test-user")
    XCTAssertEqual(stored.password, "saved-password")
  }
}
