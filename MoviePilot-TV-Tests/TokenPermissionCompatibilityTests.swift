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
  }

  func testUnknownUserKeepsLegacySuperUserEndpointBehavior() {
    let token = Token(
      access_token: "token",
      token_type: "bearer",
      super_user: nil,
      permissions: nil,
      user_name: "legacy",
      avatar: nil
    )

    XCTAssertTrue(token.canRequestSuperUserEndpoints)
  }
}
