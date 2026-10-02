import XCTest

@testable import MoviePilot_TV

@MainActor
final class BackendAPIContractTests: XCTestCase {
  func testV304LookupPreservesOriginalCrossSourceBoundary() {
    let contract = BackendAPIContract(profile: .v304)
    let tmdb = MediaInfo(tmdb_id: 42, title: "测试电影", year: "2026", type: "电影")
    let douban = MediaInfo(douban_id: "42", title: "测试电影", year: "2026", type: "电影")
    let noYear = MediaInfo(douban_id: "42", title: "测试电影", type: "电影")

    XCTAssertNil(contract.subscriptionLookupParameters(
      media: tmdb, season: nil, includeVideoMetadataFallback: true)["mtype"] ?? nil)
    XCTAssertEqual(contract.subscriptionLookupParameters(
      media: douban, season: nil, includeVideoMetadataFallback: true)["year"] ?? nil, "2026")
    XCTAssertNil(contract.subscriptionLookupParameters(
      media: noYear, season: nil, includeVideoMetadataFallback: true)["mtype"] ?? nil)
  }

  func testV30101LookupEnablesTMDBAndMissingYearFallback() {
    let contract = BackendAPIContract(profile: .v30101)
    let media = MediaInfo(tmdb_id: 42, title: "测试电影", type: "电影")
    let params = contract.subscriptionLookupParameters(
      media: media, season: nil, includeVideoMetadataFallback: true)
    XCTAssertEqual(params["mtype"] ?? nil, "电影")
    XCTAssertNil(params["year"] ?? nil)
  }

  func testDeletionLookupNeverEnablesMetadataFallbackForEitherProfile() {
    for profile in [BackendContractProfile.v304, .v30101] {
      let media = MediaInfo(douban_id: "42", title: "测试电影", year: "2026", type: "电影")
      let params = BackendAPIContract(profile: profile).subscriptionLookupParameters(
        media: media, season: 2, includeVideoMetadataFallback: false)
      XCTAssertEqual(params["season"] ?? nil, "2")
      XCTAssertNil(params["year"] ?? nil)
      XCTAssertNil(params["mtype"] ?? nil)
    }
  }

  func testProfileUsesCurrentSessionSettingsAndResetsWhenServerChanges() throws {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://contract-a.local"
    service.settings = try settings("v3.0.4")
    XCTAssertEqual(service.backendContractProfile, .v304)
    service.settings = try settings("v3.0.10-1")
    XCTAssertEqual(service.backendContractProfile, .v30101)
    service.settings = try settings("v3.0.7")
    XCTAssertEqual(service.backendContractProfile, .v304, "已知能力边界与精确版本验证分开判断")

    service.settings = try settings("v3.0.4")
    service.baseURLForTesting = "https://contract-b.local"
    XCTAssertNil(service.backendContractProfile)
  }

  func testV304ForkIsRejectedBeforeAnyRequest() async throws {
    let service = APIService.isolatedTestingInstance()
    service.baseURLForTesting = "https://contract-fork.local"
    service.settings = try settings("v3.0.4")
    let share = try JSONDecoder().decode(SubscribeShare.self, from: Data(
      #"{"id":1,"name":"测试分享","type":"电影","media_source":"themoviedb","media_id":"42"}"#.utf8))
    do {
      _ = try await service.forkSubscription(share: share)
      XCTFail("v3.0.4 必须在创建前阻止已知有副作用的失败接口")
    } catch let error as BackendCapabilityError {
      XCTAssertTrue(error.localizedDescription.contains("v3.0.4"))
      XCTAssertTrue(error.localizedDescription.contains("普通订阅与编辑仍可使用"))
    }
  }

  func testForkCapabilityBoundaryIsIndependentOfSparseRegistration() {
    XCTAssertNotNil(BackendAPIContract(profile: .v304, version: MoviePilotVersion("v3.0.4"))
      .subscriptionForkUnavailableReason)
    for version in ["v3.0.5", "v3.0.7", "v3.0.10", "v3.0.10-1", "v3.1.0"] {
      XCTAssertNil(BackendAPIContract(profile: .v304, version: MoviePilotVersion(version))
        .subscriptionForkUnavailableReason)
    }
  }

  private func settings(_ version: String) throws -> GlobalSettings {
    try JSONDecoder().decode(GlobalSettings.self, from: Data(
      "{\"BACKEND_VERSION\":\"\(version)\"}".utf8))
  }
}
