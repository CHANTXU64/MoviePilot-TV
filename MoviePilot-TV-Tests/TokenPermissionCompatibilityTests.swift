import XCTest

@testable import MoviePilot_TV

@MainActor
final class TokenPermissionCompatibilityTests: XCTestCase {
  func testKnownStandardUserCannotRequestSuperUserEndpoints() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["manage": true],
      user_name: "ordinary",
      avatar: nil
    )

    XCTAssertFalse(token.canRequestSuperUserEndpoints)
  }

  func testStandardUserOnlyAccessesExplicitlyGrantedPermissions() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true,
        "search": true,
        "subscribe": false,
        "manage": false,
      ],
      user_name: "limited",
      avatar: nil
    )

    XCTAssertTrue(token.canAccess(.discovery))
    XCTAssertTrue(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
    XCTAssertFalse(token.canAccess(.admin))
  }

  func testStandardUserWithEmptyPermissionsCannotAccessFeaturePermissions() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [:],
      user_name: "test",
      avatar: nil
    )

    XCTAssertFalse(token.canAccess(.discovery))
    XCTAssertFalse(token.canAccess(.search))
    XCTAssertFalse(token.canAccess(.subscribe))
    XCTAssertFalse(token.canAccess(.manage))
    XCTAssertFalse(token.canAccess(.admin))
  }

  func testSuperUserCanRequestSuperUserEndpoints() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [:],
      user_name: "admin",
      avatar: nil
    )

    XCTAssertTrue(token.canRequestSuperUserEndpoints)
    XCTAssertTrue(token.canAccess(.discovery))
    XCTAssertTrue(token.canAccess(.search))
    XCTAssertTrue(token.canAccess(.subscribe))
    XCTAssertTrue(token.canAccess(.manage))
    XCTAssertTrue(token.canAccess(.admin))
  }

  func testUnknownPermissionPayloadKeepsFeatureAccessButNotAdminAccess() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: nil,
      permissions: nil,
      user_name: "legacy",
      avatar: nil
    )

    XCTAssertFalse(token.canRequestSuperUserEndpoints)
    XCTAssertTrue(token.canAccess(.discovery))
    XCTAssertTrue(token.canAccess(.search))
    XCTAssertTrue(token.canAccess(.subscribe))
    XCTAssertTrue(token.canAccess(.manage))
    XCTAssertFalse(token.canAccess(.admin))
  }

  func testSettingsConnectionEntryExplainsLimitedUserPermissions() {
    XCTAssertEqual(
      SystemViewModel.connectionEntryDescription(
        storageDescription: "已登录 (安全存储)",
        isLoggedIn: true,
        canRequestSuperUserEndpoints: false
      ),
      "当前用户权限不够，部分不可用功能已自动隐藏"
    )

    XCTAssertEqual(
      SystemViewModel.connectionEntryDescription(
        storageDescription: "已登录 (安全存储)",
        isLoggedIn: true,
        canRequestSuperUserEndpoints: true
      ),
      "已登录 (安全存储)"
    )

    XCTAssertEqual(
      SystemViewModel.connectionEntryDescription(
        storageDescription: "未登录",
        isLoggedIn: false,
        canRequestSuperUserEndpoints: false
      ),
      "未登录"
    )
  }

  func testContentTabsFollowGrantedPermissions() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["search": true],
      user_name: "searcher",
      avatar: nil
    )

    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: token),
      [.home, .search, .system]
    )
  }

  func testSuperUserSeesAllContentTabs() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: FlexibleBool(true),
      permissions: [:],
      user_name: "admin",
      avatar: nil
    )

    XCTAssertEqual(
      ContentViewModel.visibleTabs(for: token),
      [.home, .recommend, .explore, .search, .status, .system]
    )
  }
}
