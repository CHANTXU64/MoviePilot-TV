import SwiftUI
import XCTest

@testable import MoviePilot_TV

/// 离屏渲染加载态对比：本环境无 Simulator GUI、无法注入遥控器按键，详情页整体又是
/// LazyVStack（ImageRenderer 不布局懒加载内容），故只渲染非懒加载的按钮标签部分。
/// 「改动前」按旧代码原样复刻（长文案 + 静态 ellipsis 图标），「改动后」走真实标题函数 + LoadingIcon。
@MainActor
final class LoadingStateSnapshotTests: XCTestCase {
  private var sessionSnapshot: SystemSessionServiceSnapshot?

  override func setUp() async throws {
    try await super.setUp()
    sessionSnapshot = SystemSessionServiceSnapshot.capture(service: APIService.shared)
    let account = Token(
      access_token: "loading-snapshot",
      token_type: "bearer",
      super_user: FlexibleBool(false),
      permissions: [
        "discovery": true, "search": true, "subscribe": true, "manage": false, "admin": false,
      ],
      user_id: 1,
      user_name: "loading-snapshot",
      avatar: nil
    )
    APIService.shared.replaceSessionForTesting(
      baseURL: "http://loading-snapshot.local", token: account.access_token, currentUser: account)
  }

  override func tearDown() async throws {
    sessionSnapshot?.restore(to: APIService.shared)
    sessionSnapshot = nil
    try await super.tearDown()
  }

  private func attach(_ view: some View, name: String) {
    let hosted =
      view
      .environment(\.colorScheme, .dark)
      .frame(width: 900, height: 160, alignment: .leading)
      .padding(.leading, 40)
      .background(Color(white: 0.12))
    let renderer = ImageRenderer(content: hosted)
    renderer.proposedSize = ProposedViewSize(width: 900, height: 160)
    renderer.scale = 2
    guard let image = renderer.uiImage, let data = image.pngData() else {
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

  /// 改动后：真实标题函数，文案恒为「分季信息」，加载只换图标。
  /// 离屏渲染画不出动画转圈（ProgressView 会变成占位框），这里用静态转圈符号示意图标位；
  /// 真实 LoadingIcon 的「加载不撑高」由 testLoadingIconKeepsIconSlotSize 按尺寸断言保证。
  private func afterLabel(seasonWaiting: Bool, isEntryLoading: Bool) -> some View {
    let detail = tvDetail()
    let label = MediaDetailView.headerSubscribeButtonTitle(
      isSubscribed: false, detail: detail, isSeasonInformationUnavailable: false,
      hasSeasonLoadError: false, isSeasonLoading: seasonWaiting, isInLibrary: false)
    return Label {
      Text(label)
    } icon: {
      Image(systemName: seasonWaiting ? AppSymbol.checking : AppSymbol.chooseSeasons)
    }
    .foregroundColor(.primary)
    .opacity(isEntryLoading ? 0.35 : 1)
  }

  /// 改动前复刻：加载时文案变长「分季信息加载中」+ 静态 ellipsis 图标。
  private func beforeLabel(seasonLoading: Bool) -> some View {
    Label(
      seasonLoading ? "分季信息加载中" : "分季信息",
      systemImage: seasonLoading ? AppSymbol.loading : AppSymbol.chooseSeasons
    )
    .foregroundColor(.primary)
  }

  func testSubscribeButtonBeforeAfter() {
    attach(beforeLabel(seasonLoading: false), name: "before-entry")
    attach(beforeLabel(seasonLoading: true), name: "before-season")
    attach(afterLabel(seasonWaiting: true, isEntryLoading: true), name: "after-entry")
    attach(afterLabel(seasonWaiting: true, isEntryLoading: false), name: "after-season")
    attach(afterLabel(seasonWaiting: false, isEntryLoading: false), name: "after-loaded")
  }

  /// 加载中文案必须与就绪时一致（宽度不闪），且为「分季信息」。
  func testSeasonTitleStableWhileLoading() {
    let detail = tvDetail()
    let loading = MediaDetailView.headerSubscribeButtonTitle(
      isSubscribed: false, detail: detail, isSeasonInformationUnavailable: false,
      hasSeasonLoadError: false, isSeasonLoading: true, isInLibrary: false)
    let idle = MediaDetailView.headerSubscribeButtonTitle(
      isSubscribed: false, detail: detail, isSeasonInformationUnavailable: false,
      hasSeasonLoadError: false, isSeasonLoading: false, isInLibrary: false)
    XCTAssertEqual(loading, idle)
    XCTAssertEqual(loading, "分季信息")
  }

  func testSheetActionButtonIdleAndLoading() {
    attach(
      SheetActionButton(
        title: "订阅", systemImage: AppSymbol.subscribe, loadingTitle: "订阅中", isLoading: false
      ) {}.frame(width: 440), name: "sheet-button-idle")
    attach(
      SheetActionButton(
        title: "订阅", systemImage: AppSymbol.subscribe, loadingTitle: "订阅中", isLoading: true
      ) {}.frame(width: 440), name: "sheet-button-loading")
  }
}