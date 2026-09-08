import XCTest

@testable import MoviePilot_TV

/// F-236 回归：Paginator 重建的去重键必须携带 source owner，
/// 否则"不同来源、拼出完全相同 API 路径"的切换会被 removeDuplicates 吞掉，
/// 旧 Paginator（捕获旧 source 语义）继续服务新选中来源。
@MainActor
final class ExploreViewModelPaginatorOwnerSwitchTests: XCTestCase {
  func testSameApiPathCustomSourceSwitchRebuildsPaginator() async throws {
    XCTAssertTrue(APIService.installURLProtocolForTesting(ExploreOwnerSwitchURLProtocol.self))
    defer { APIService.removeURLProtocolForTesting(ExploreOwnerSwitchURLProtocol.self) }

    let service = APIService.testingInstance()
    service.baseURLForTesting = "https://explore-switch-f236.local"
    service.currentUserForTesting = Token(
      access_token: "explore-token",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: ["discovery": true],
      user_id: nil,
      user_name: "explore-user",
      avatar: nil
    )
    XCTAssertTrue(service.canAccess(.discovery))

    // 两个自定义源：api_path 完全一致，仅 prefix/name 不同。
    let sharedPath = "plugin/discover/popular"
    let sourceA = DiscoverSource.custom(
      DiscoverSourceDescriptor(
        name: "源A", mediaid_prefix: "alpha", api_path: sharedPath,
        filter_params: [:], filter_ui: [], depends: nil
      )
    )
    let sourceB = DiscoverSource.custom(
      DiscoverSourceDescriptor(
        name: "源B", mediaid_prefix: "beta", api_path: sharedPath,
        filter_params: [:], filter_ui: [], depends: nil
      )
    )
    XCTAssertNotEqual(sourceA.id, sourceB.id)

    let viewModel = ExploreViewModel(apiService: service)

    // 前提：两源在空插件筛选下拼出同一条 API 路径。
    viewModel.selectedSource = sourceA
    let pathA = viewModel.buildApiPath()
    viewModel.selectedSource = sourceB
    let pathB = viewModel.buildApiPath()
    XCTAssertEqual(pathA, pathB, "回归前提：两源拼出的路径应完全一致")

    // 基线：源 A 建立第一个 Paginator。
    viewModel.selectedSource = sourceA
    try await waitUntil("切换源 A 后应创建首个 Paginator") {
      viewModel.paginator != nil
    }
    let firstPaginatorID = ObjectIdentifier(try XCTUnwrap(viewModel.paginator))

    // 切到路径相同的源 B：去重键若仅含路径会吞掉本次切换，
    // Paginator 保持 A 的旧实例；修复后键含 source owner，应重建新实例。
    viewModel.selectedSource = sourceB
    try await waitUntil("同路径源切换后应重建 Paginator（owner 键生效）") {
      guard let current = viewModel.paginator else { return false }
      return ObjectIdentifier(current) != firstPaginatorID
    }
  }

  private func waitUntil(
    _ message: String,
    timeout: TimeInterval = 2,
    condition: @MainActor @escaping () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail(message)
  }
}

/// 对 explore-switch-f236.local 的一切请求返回 HTTP 200 空列表，
/// 让 Paginator.refresh() 在不触网的前提下快速完成。
private final class ExploreOwnerSwitchURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "explore-switch-f236.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
