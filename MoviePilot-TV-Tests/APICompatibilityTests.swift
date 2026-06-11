import XCTest

@testable import MoviePilot_TV

@MainActor
final class APICompatibilityTests: XCTestCase {
  func testPublicSystemSettingEndpointUsesV2137PublicPath() {
    XCTAssertEqual(
      APIService.publicSettingEndpoint(for: "Directories"),
      "/system/setting/public/Directories"
    )
    XCTAssertEqual(
      APIService.publicSettingEndpoint(for: "IndexerSites"),
      "/system/setting/public/IndexerSites"
    )
    XCTAssertEqual(
      APIService.publicSettingEndpoint(for: "Storages"),
      "/system/setting/public/Storages"
    )
  }

  func testSessionValidationUsesLoggedInUserPingEndpoint() {
    XCTAssertEqual(APIService.sessionValidationEndpoint, "/system/ping")
  }

  func testCurrentUserEndpointIsAvailableForPermissionRefresh() {
    XCTAssertEqual(APIService.currentUserEndpoint, "/user/current")
  }

  func testTokenDecodesDetailedPermissions() throws {
    let json = """
      {
        "access_token": "token-value",
        "token_type": "bearer",
        "super_user": false,
        "user_id": 7,
        "user_name": "living-room",
        "permissions": {
          "discovery": true,
          "search": true,
          "subscribe": false,
          "manage": false
        }
      }
      """

    let token = try JSONDecoder().decode(Token.self, from: Data(json.utf8))

    XCTAssertEqual(token.user_id, 7)
    XCTAssertEqual(token.permissions.discovery, true)
    XCTAssertEqual(token.permissions.search, true)
    XCTAssertEqual(token.permissions.subscribe, false)
    XCTAssertEqual(token.permissions.manage, false)
    XCTAssertEqual(token.permissions.allows(.search, isSuperUser: token.super_user?.value ?? false), true)
    XCTAssertEqual(token.permissions.allows(.subscribe, isSuperUser: token.super_user?.value ?? false), false)
    XCTAssertEqual(token.permissions.allows(.admin, isSuperUser: token.super_user?.value ?? false), false)
  }

  func testCurrentUserDecodesDetailedPermissions() throws {
    let json = """
      {
        "id": 7,
        "name": "living-room",
        "is_superuser": true,
        "permissions": {
          "discovery": true,
          "search": true,
          "subscribe": true,
          "manage": true
        }
      }
      """

    let user = try JSONDecoder().decode(CurrentUser.self, from: Data(json.utf8))

    XCTAssertEqual(user.id, 7)
    XCTAssertEqual(user.name, "living-room")
    XCTAssertEqual(user.is_superuser.value, true)
    XCTAssertEqual(user.permissions.manage, true)
    XCTAssertEqual(user.permissions.allows(.admin, isSuperUser: user.is_superuser.value), true)
  }
}
