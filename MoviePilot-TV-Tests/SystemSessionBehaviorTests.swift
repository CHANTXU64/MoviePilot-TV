import XCTest

@testable import MoviePilot_TV

@MainActor
final class SystemSessionBehaviorTests: XCTestCase {
  func testAPIServiceLogoutClearsMediaPreloaderCache() async throws {
    let service = APIService.shared
    let snapshot = SystemSessionServiceSnapshot.capture(service: service)
    defer { snapshot.restore(to: service) }

    let preloader = MediaPreloader.shared
    preloader.clearAll()
    defer { preloader.clearAll() }

    let media = MediaInfo(title: "登出缓存清理", type: "collection", collection_id: 9_001)
    _ = preloader.preload(for: media)

    XCTAssertNotNil(preloader.peekTask(for: media))

    service.logout()

    try await waitUntil {
      preloader.peekTask(for: media) == nil
    }
  }

  func testReloginReturnsWithoutMutatingStateWhenRefreshIsAlreadyRunning() async {
    let viewModel = SystemViewModel()
    viewModel.isRefreshing = true
    viewModel.refreshMessage = "保持现有状态"

    await viewModel.relogin()

    XCTAssertTrue(viewModel.isRefreshing)
    XCTAssertEqual(viewModel.refreshMessage, "保持现有状态")
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    pollInterval: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: pollInterval)
    }

    XCTAssertTrue(condition())
  }
}

private struct SystemSessionServiceSnapshot {
  let baseURL: String
  let token: String?
  let tokenKeychain: String?
  let tokenDefaults: String?
  let settings: GlobalSettings?
  let useImageCache: Bool
  let usernameKeychain: String?
  let passwordKeychain: String?
  let usernameDefaults: String?
  let passwordDefaults: String?

  @MainActor
  static func capture(service: APIService) -> SystemSessionServiceSnapshot {
    SystemSessionServiceSnapshot(
      baseURL: service.baseURL,
      token: service.token,
      tokenKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "accessToken"),
      tokenDefaults: UserDefaults.standard.string(forKey: "accessToken"),
      settings: service.settings,
      useImageCache: service.useImageCache,
      usernameKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username"),
      passwordKeychain: KeychainHelper.shared.read(service: "MoviePilot-TV", account: "password"),
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
      account: "accessToken",
      keychainValue: tokenKeychain,
      defaultsValue: tokenDefaults
    )
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
