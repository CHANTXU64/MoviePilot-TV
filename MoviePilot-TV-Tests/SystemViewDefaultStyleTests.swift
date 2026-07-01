import XCTest

final class SystemViewDefaultStyleTests: XCTestCase {
  func testSystemViewDoesNotUsePrivateSettingsImplementation() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("struct SystemView: View"))
    XCTAssertFalse(source.contains("TVSettingsView("))
    XCTAssertFalse(source.contains("PrivateTVSettings"))
    XCTAssertFalse(source.contains("TVSettingKit"))
    XCTAssertFalse(source.contains("_TSK"))
  }

  func testContentViewLabelsSystemTabAsSettings() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")

    XCTAssertTrue(
      source.contains(
        "SystemView(isSelected: selectedTab == .system)"
      )
    )
    XCTAssertTrue(source.contains("Label(\"设置\", systemImage: \"gear\")"))
    XCTAssertFalse(source.contains("Label(\"系统\", systemImage: \"gear\")"))
  }

  func testSystemViewKeepsConnectionAndAppInfoEntryPoints() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("\"连接与APP信息\""))
    XCTAssertTrue(source.contains("\"连接\""))
    XCTAssertTrue(source.contains("\"APP 信息\""))
    XCTAssertTrue(source.contains("\"MoviePilot TV APP\""))
    XCTAssertFalse(source.contains("\"连接与版本\""))
  }

  func testSubscriptionCompatibilityChecklistTracksPermissionContractRisk() throws {
    let source = try Self.source(at: "docs/subscription-compatibility-checklist.md")

    XCTAssertTrue(source.contains("用户权限契约风险"))
    XCTAssertTrue(source.contains("权限契约仍不稳定"))
    XCTAssertTrue(source.contains("Token.super_user"))
    XCTAssertTrue(source.contains("permissions.subscribe"))
    XCTAssertTrue(source.contains("/mediaserver/notexists"))
    XCTAssertTrue(source.contains("不得要求 `Token.super_user`"))
    XCTAssertTrue(source.contains("/dashboard/*"))
    XCTAssertTrue(source.contains("ViewModel 入口跳过"))
    XCTAssertTrue(source.contains("下载与整理等 manage 功能请求继续交给后端鉴权"))
    XCTAssertTrue(source.contains("CustomFilterRules"))
    XCTAssertTrue(source.contains("UserFilterRuleGroups"))
    XCTAssertTrue(source.contains("/system/setting/public/{key}"))
    XCTAssertTrue(source.contains("canAccess(.subscribe)"))
    XCTAssertTrue(source.contains("不显示入库状态徽章"))
    XCTAssertTrue(source.contains("best_version"))
    XCTAssertTrue(source.contains("不要只按 HTTP 状态码"))
    XCTAssertTrue(source.contains("app/core/security.py"))
    XCTAssertTrue(source.contains("app/db/user_oper.py"))
    XCTAssertTrue(source.contains("app/api/endpoints/login.py"))
    XCTAssertTrue(source.contains("token校验不通过"))
    XCTAssertTrue(source.contains("400 用户权限不足"))
  }

  func testSubscribeSeasonViewHidesAvailabilityBadgeWhenStatusTextIsNil() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift")

    XCTAssertTrue(source.contains("let bottomLeft = statusText.map"))
    XCTAssertTrue(source.contains("bottomLeftText: bottomLeft"))
  }

  func testSystemViewExitHandlersOnlyRunWhenSettingsTabIsActive() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(
      source.contains("SystemSettingsRootBackObserver(isEnabled: isSelected && isActive && page == .root)")
    )
    XCTAssertTrue(
      source.contains(".systemSettingsExitCommand(isEnabled: isSelected && isActive && page != .root")
    )
  }

  func testMissingPersistedFilterRuleDoesNotDisplayAsNoFilter() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("guard let ruleId else { return \"不过滤\" }"))
    XCTAssertTrue(
      source.contains("return viewModel.customFilterRules.first(where: { $0.id == ruleId })?.name ?? \"规则未加载\"")
    )
    XCTAssertFalse(source.contains("?.name ?? \"不过滤\""))
  }

  func testLogoutRequiresConfirmationAlert() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("@State private var showLogoutConfirmation = false"))
    XCTAssertTrue(source.contains("showLogoutConfirmation = true"))
    XCTAssertTrue(source.contains(".alert(\"退出登录\", isPresented: $showLogoutConfirmation)"))
    XCTAssertTrue(source.contains("Button(\"确认退出登录\", role: .destructive)"))
    XCTAssertTrue(source.contains("viewModel.logout()"))
    XCTAssertFalse(source.contains("APIService.shared.logout()"))
  }

  func testSettingsPreviewUsesGlassLogoAsset() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("Image(\"SettingsLogoGlass\")"))
    XCTAssertFalse(source.contains("Image(\"App Icon\")"))
  }

  func testPreviewKeepsSettingsListAtOriginalLeadingPosition() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")

    XCTAssertTrue(source.contains("private static let previewWidth: CGFloat = 600"))
    XCTAssertTrue(source.contains("private static let horizontalPadding: CGFloat = 240"))
    XCTAssertTrue(source.contains("private static let columnSpacing: CGFloat = 210"))
    XCTAssertFalse(source.contains("private static let columnSpacing: CGFloat = 270"))
  }

  func testSessionLogoutPreloaderCleanupUsesMainActorBridge() throws {
    let source = try Self.source(at: "MoviePilot-TV/ViewModels/MediaPreloader.swift")

    XCTAssertTrue(source.contains("Task { @MainActor [weak self] in"))
    XCTAssertTrue(source.contains("self?.clearAll()"))
  }

  func testContentViewNormalizesHiddenSelectedTabOnAppear() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/ContentView.swift")

    XCTAssertTrue(source.contains(".onAppear {"))
    XCTAssertTrue(
      source.contains(
        "selectedTab = ContentViewModel.resolvedSelectedTab(selectedTab, visibleTabs: viewModel.visibleTabs)"
      )
    )
  }

  func testMediaDetailHeaderFocusOnlyTargetsVisiblePermittedActions() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/MediaDetailView.swift")

    XCTAssertTrue(source.contains("@ObservedObject private var apiService = APIService.shared"))
    XCTAssertTrue(source.contains("private var canJumpToTMDB: Bool"))
    XCTAssertTrue(source.contains("private var preferredHeaderFocus: ButtonField?"))
    XCTAssertTrue(source.contains("if !hasAppeared, let preferredHeaderFocus"))
    XCTAssertFalse(source.contains(".defaultFocus($focusedButton, preferredHeaderFocus)"))
  }

  func testSystemViewModelRechecksPermissionBeforePublishingCustomRules() throws {
    let source = try Self.source(at: "MoviePilot-TV/ViewModels/SystemViewModel.swift")

    XCTAssertTrue(source.contains("let rules = try await APIService.shared.fetchCustomFilterRules()"))
    XCTAssertTrue(source.contains("guard APIService.shared.canRequestSuperUserEndpoints else {"))
    XCTAssertTrue(source.contains("customFilterRules = rules"))
  }

  func testSystemViewScopesLocalFeatureSettingsByPermission() throws {
    let viewSource = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")
    let viewModelSource = try Self.source(at: "MoviePilot-TV/ViewModels/SystemViewModel.swift")

    XCTAssertTrue(viewSource.contains("@ObservedObject private var apiService = APIService.shared"))
    XCTAssertTrue(viewSource.contains("private var canConfigureSubscriptions: Bool"))
    XCTAssertTrue(viewSource.contains("private var canConfigureSearch: Bool"))
    XCTAssertTrue(viewSource.contains("if canConfigureSubscriptions {"))
    XCTAssertTrue(viewSource.contains("if canConfigureSearch {"))
    XCTAssertTrue(viewModelSource.contains("guard APIService.shared.canAccess(.search) else {"))
  }

  func testRecommendBackendCompatibilityScansShelvesIndependently() throws {
    let source = try Self.source(at: "MoviePilot-TV-Tests/BackendCompatibilityTests.swift")

    XCTAssertTrue(source.contains("for shelf in RecommendViewModel.allShelves {"))
    XCTAssertTrue(source.contains("\"recommend shelf \\(shelf.title)\""))
    XCTAssertFalse(source.contains("\"recommend shelves\""))
  }

  func testFilterRuleGroupsCompatibilityProbeUsesSuperUserRequirement() throws {
    let source = try Self.source(at: "MoviePilot-TV-Tests/BackendCompatibilityTests.swift")
    let start = try XCTUnwrap(source.range(of: "\"filter-rule groups\""))
    let end = try XCTUnwrap(source.range(of: "\"custom filter rules\"", range: start.upperBound..<source.endIndex))
    let probe = String(source[start.lowerBound..<end.lowerBound])

    XCTAssertTrue(probe.contains("requirement: .superUser"))
    XCTAssertFalse(probe.contains("requirement: .permission(.subscribe)"))
  }

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let sourceURL = repositoryRoot.appendingPathComponent(path)
    return try String(contentsOf: sourceURL)
  }
}
