import XCTest

@testable import MoviePilot_TV

@MainActor
final class CredentialPersistenceTests: XCTestCase {
  func testAccessTokenDoesNotPersistPlaintextFallbackWhenCredentialStoreSaveFails() throws {
    let service = APIService.shared
    let snapshot = CredentialServiceSnapshot.capture(service: service)
    let failingStore = FailingCredentialStore()
    let originalStore = service.replaceCredentialStoreForTesting(failingStore)
    defer {
      snapshot.restore(to: service, credentialStore: originalStore)
    }

    UserDefaults.standard.removeObject(forKey: "accessToken")
    service.token = nil

    service.token = "new-secure-token"

    XCTAssertEqual(
      failingStore.saveAttempts,
      [CredentialStoreSaveAttempt(service: "MoviePilot-TV", account: "accessToken", value: "new-secure-token")]
    )
    XCTAssertNil(
      UserDefaults.standard.string(forKey: "accessToken"),
      "Access tokens must not be persisted in UserDefaults when secure storage rejects the value."
    )
  }

  func testLoginCredentialsDoNotPersistPlaintextFallbackWhenCredentialStoreSaveFails() throws {
    let service = APIService.shared
    let snapshot = CredentialServiceSnapshot.capture(service: service)
    let failingStore = FailingCredentialStore()
    let originalStore = service.replaceCredentialStoreForTesting(failingStore)
    defer {
      snapshot.restore(to: service, credentialStore: originalStore)
    }

    UserDefaults.standard.removeObject(forKey: "username")
    UserDefaults.standard.removeObject(forKey: "password")

    service.setStoredCredentialsForTesting(username: "secure-user", password: "secure-password")

    XCTAssertEqual(
      failingStore.saveAttempts,
      [
        CredentialStoreSaveAttempt(
          service: "MoviePilot-TV", account: "username", value: "secure-user"),
        CredentialStoreSaveAttempt(
          service: "MoviePilot-TV", account: "password", value: "secure-password"),
      ]
    )
    XCTAssertNil(
      UserDefaults.standard.string(forKey: "username"),
      "Usernames must not be persisted in UserDefaults when secure storage rejects the value."
    )
    XCTAssertNil(
      UserDefaults.standard.string(forKey: "password"),
      "Passwords must not be persisted in UserDefaults when secure storage rejects the value."
    )
  }
}

@MainActor
private struct CredentialServiceSnapshot {
  let token: String?
  let tokenDefaults: String?
  let usernameDefaults: String?
  let passwordDefaults: String?

  static func capture(service: APIService) -> CredentialServiceSnapshot {
    CredentialServiceSnapshot(
      token: service.token,
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      usernameDefaults: UserDefaults.standard.string(forKey: "username"),
      passwordDefaults: UserDefaults.standard.string(forKey: "password")
    )
  }

  func restore(to service: APIService, credentialStore: CredentialStore) {
    service.token = token
    if let tokenDefaults {
      UserDefaults.standard.set(tokenDefaults, forKey: "accessToken")
    } else {
      UserDefaults.standard.removeObject(forKey: "accessToken")
    }
    if let usernameDefaults {
      UserDefaults.standard.set(usernameDefaults, forKey: "username")
    } else {
      UserDefaults.standard.removeObject(forKey: "username")
    }
    if let passwordDefaults {
      UserDefaults.standard.set(passwordDefaults, forKey: "password")
    } else {
      UserDefaults.standard.removeObject(forKey: "password")
    }
    service.replaceCredentialStoreForTesting(credentialStore)
  }
}

private final class FailingCredentialStore: CredentialStore {
  private(set) var saveAttempts: [CredentialStoreSaveAttempt] = []

  func save(_ value: String, service: String, account: String) -> Bool {
    saveAttempts.append(CredentialStoreSaveAttempt(service: service, account: account, value: value))
    return false
  }

  func read(service: String, account: String) -> String? {
    nil
  }

  func delete(service: String, account: String) -> Bool {
    true
  }
}

private struct CredentialStoreSaveAttempt: Equatable {
  let service: String
  let account: String
  let value: String
}
