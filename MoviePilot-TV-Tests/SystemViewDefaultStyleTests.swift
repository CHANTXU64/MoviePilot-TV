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

    XCTAssertTrue(source.contains("SystemView(isSelected: selectedTab == 5)"))
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

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let sourceURL = repositoryRoot.appendingPathComponent(path)
    return try String(contentsOf: sourceURL)
  }
}
