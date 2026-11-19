import SwiftUI
import UIKit
import XCTest

@testable import MoviePilot_TV

/// 整页加载态截图：ImageRenderer 不布局 LazyVStack，改用真实 UIWindow 托管 + drawHierarchy，
/// 让懒加载内容真正排版后整页快照。本环境无 Simulator GUI、无法注入按键，故用强制状态离屏整页渲染。
@MainActor
final class WindowSnapshotTests: XCTestCase {
  private var sessionSnapshot: SystemSessionServiceSnapshot?

  override func setUp() async throws {
    try await super.setUp()
    sessionSnapshot = SystemSessionServiceSnapshot.capture(service: APIService.shared)
    let account = Token(
      access_token: "window-snapshot",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true, "search": true, "subscribe": true, "manage": false, "admin": false,
      ],
      user_id: 1,
      user_name: "window-snapshot",
      avatar: nil
    )
    // 黑洞地址：TCP 连接挂起不返回，让页面自然停留在「加载中」，便于快照加载态。
    APIService.shared.replaceSessionForTesting(
      baseURL: "http://10.255.255.1:3000", token: account.access_token, currentUser: account)
  }

  override func tearDown() async throws {
    sessionSnapshot?.restore(to: APIService.shared)
    sessionSnapshot = nil
    try await super.tearDown()
  }

  private func hostAttach(_ view: some View, name: String,
                          size: CGSize = CGSize(width: 1920, height: 1080)) {
    let hosted =
      view
      .environmentObject(ImageNavigationCoordinator())
      .environmentObject(MediaActionHandler())
      .environmentObject(NotificationManager())
      .environment(\.colorScheme, .dark)
    let host = UIHostingController(rootView: AnyView(hosted))
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    let settled = expectation(description: "settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
    wait(for: [settled], timeout: 3)
    host.view.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
    let image = renderer.image { _ in
      host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
    window.isHidden = true
    guard let data = image.pngData() else {
      XCTFail("渲染失败：\(name)")
      return
    }
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func tvDetail() -> MediaInfo {
    MediaInfo(tmdb_id: 100_083, title: "指环王：力量之戒", type: "电视剧", year: "2022")
  }

  func testDetailFullPageEntryLoading() {
    let task = MediaPreloadTask(partialMedia: tvDetail(), apiService: nil)
    hostAttach(
      MediaDetailView(
        detail: tvDetail(), preloadTask: task, isContentReady: .constant(false),
        routeID: UUID(), imageLifecycle: PageImageLifecycle(), loadingPosterURL: nil,
        presentationStyle: .standard, allowsRequests: true, isEntryLoading: true
      ), name: "full-detail-entry")
  }

  func testDetailFullPageSeasonLoading() {
    let detail = tvDetail()
    let task = MediaPreloadTask(partialMedia: detail, apiService: nil)
    task.fullDetail = detail
    let season = SubscribeSeasonViewModel(mediaInfo: detail, apiService: APIService.shared)
    season.isLoading = true
    task.seasonViewModel = season
    task.isSeasonDataLoaded = false
    hostAttach(
      MediaDetailView(
        detail: detail, preloadTask: task, isContentReady: .constant(true),
        routeID: UUID(), imageLifecycle: PageImageLifecycle(), loadingPosterURL: nil,
        presentationStyle: .standard, allowsRequests: true, isEntryLoading: false
      ), name: "full-detail-season-loading")
  }

  func testDetailFullPageLoaded() throws {
    let detail = try JSONDecoder().decode(
      MediaInfo.self,
      from: Data(
        #"{"tmdb_id":100083,"title":"指环王：力量之戒","type":"电视剧","year":"2022","season_info":[{"season_number":1,"name":"第 1 季","episode_count":8}]}"#
          .utf8))
    let task = MediaPreloadTask(partialMedia: detail, apiService: nil)
    task.fullDetail = detail
    task.seasonViewModel = SubscribeSeasonViewModel(mediaInfo: detail, apiService: APIService.shared)
    task.isSeasonDataLoaded = true
    hostAttach(
      MediaDetailView(
        detail: detail, preloadTask: task, isContentReady: .constant(true),
        routeID: UUID(), imageLifecycle: PageImageLifecycle(), loadingPosterURL: nil,
        presentationStyle: .standard, allowsRequests: true, isEntryLoading: false
      ), name: "full-detail-loaded")
  }

  func testHomeLoading() {
    hostAttach(HomeView(viewModel: HomeViewModel()), name: "home-loading")
  }

  func testTransferFirstLoading() {
    let viewModel = TransferHistoryViewModel(apiService: APIService.shared)
    viewModel.isFirstLoading = true
    hostAttach(TransferHistoryView(viewModel: viewModel), name: "transfer-first-loading")
  }

  func testSubscribeSeasonLoading() {
    let season = SubscribeSeasonViewModel(mediaInfo: tvDetail(), apiService: APIService.shared)
    season.isLoading = true
    hostAttach(SubscribeSeasonContentView(viewModel: season), name: "subscribe-season-loading")
  }

  func testSheetButtonIdleAndLoading() {
    hostAttach(
      SheetActionButton(
        title: "订阅", systemImage: AppSymbol.subscribe, loadingTitle: "订阅中", isLoading: false
      ) {}.frame(width: 440), name: "sheet-button-idle", size: CGSize(width: 900, height: 200))
    hostAttach(
      SheetActionButton(
        title: "订阅", systemImage: AppSymbol.subscribe, loadingTitle: "订阅中", isLoading: true
      ) {}.frame(width: 440), name: "sheet-button-loading", size: CGSize(width: 900, height: 200))
  }

  func testRowLoadingTail() {
    hostAttach(RowLoadingTail(height: 384), name: "row-loading-tail",
               size: CGSize(width: 400, height: 500))
  }

  func testLoadingIconIdleAndLoading() {
    hostAttach(LoadingIcon(systemImage: AppSymbol.chooseSeasons, isLoading: false),
               name: "loading-icon-idle", size: CGSize(width: 200, height: 200))
    hostAttach(LoadingIcon(systemImage: AppSymbol.chooseSeasons, isLoading: true),
               name: "loading-icon-loading", size: CGSize(width: 200, height: 200))
  }

  func testShelfStatusCardStates() {
    let card = CGSize(width: 400, height: 225)
    let canvas = CGSize(width: 500, height: 320)
    hostAttach(ShelfStatusCard(status: .loading("正在加载剧集…"), size: card),
               name: "shelf-card-loading", size: canvas)
    hostAttach(ShelfStatusCard(status: .failed("剧集加载失败"), size: card),
               name: "shelf-card-failed", size: canvas)
    hostAttach(ShelfStatusCard(status: .empty("暂无分季信息"), size: card),
               name: "shelf-card-empty", size: canvas)
  }

  func testFirstLoadIndicator() {
    hostAttach(FirstLoadIndicator(), name: "first-load-indicator",
               size: CGSize(width: 900, height: 300))
  }
}