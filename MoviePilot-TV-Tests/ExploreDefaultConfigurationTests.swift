import XCTest

@testable import MoviePilot_TV

@MainActor
final class ExploreDefaultConfigurationTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Self.clearDefaults()
    ExploreVisibilityURLProtocol.reset()
    XCTAssertTrue(APIService.installURLProtocolForTesting(ExploreVisibilityURLProtocol.self))
  }

  override func tearDown() {
    APIService.removeURLProtocolForTesting(ExploreVisibilityURLProtocol.self)
    Self.clearDefaults()
    super.tearDown()
  }

  nonisolated private static func clearDefaults() {
    for key in [
      ExploreViewModel.visibilityDefaultsKey, ExploreViewModel.orderDefaultsKey,
      ExploreViewModel.defaultConfigurationKey, ExploreViewModel.defaultPendingKey,
    ] {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  func testDefaultConfigurationRoundTripsWithPluginValues() throws {
    var config = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/old")))
    config.pluginFilterValues = ["sort": .string("hot"), "tags": .array([.string("a"), .string("b")])]
    config.selectedType = .tvs
    ExploreViewModel.saveDefaultConfiguration(config)
    XCTAssertEqual(ExploreViewModel.storedDefaultConfiguration(), config)
  }

  func testColdStartRestoresBuiltInDefaultWithTypeAndSort() async throws {
    var config = ExploreConfiguration()
    config.selectedType = .tvs
    config.tmdbSortBy = "vote_average.desc"
    config.tmdbVoteCount = 500
    ExploreViewModel.saveDefaultConfiguration(config)

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration(),
      restoredDefault: true
    )
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")
    XCTAssertEqual(viewModel.selectedType, .tvs)
    XCTAssertEqual(viewModel.tmdbSortBy, "vote_average.desc")
    XCTAssertTrue(viewModel.buildApiPath().hasPrefix("discover/tmdb_tvs?"))
    XCTAssertTrue(viewModel.buildApiPath().contains("sort_by=vote_average.desc"))
    XCTAssertTrue(viewModel.buildApiPath().contains("vote_count=500"))
  }

  func testColdStartPluginDefaultResolvesToLatestDescriptorKeepingSavedValues() async throws {
    var saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/old")))
    saved.pluginFilterValues = ["sort": .string("hot")]
    ExploreViewModel.saveDefaultConfiguration(saved)
    // 插件升级：api_path 变更、默认参数新增 lang；用户保存的 sort 必须保留。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/new",
        "filter_params":{"sort":"new","lang":"zh"},"filter_ui":[]}]
      """)

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration(),
      restoredDefault: true
    )
    // 首次来源加载完成前：不回退、不丢筛选值。
    XCTAssertEqual(viewModel.selectedSource.id, "custom:plug")
    XCTAssertEqual(viewModel.availableSources.first?.id, "custom:plug")
    XCTAssertEqual(viewModel.pluginFilterValues["sort"], .string("hot"))

    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "custom:plug")
    XCTAssertEqual(viewModel.selectedSource.descriptor?.api_path, "plugin/discover/new")
    XCTAssertEqual(viewModel.pluginFilterValues["sort"], .string("hot"))
    XCTAssertEqual(viewModel.pluginFilterValues["lang"], .string("zh"))
    XCTAssertTrue(viewModel.buildApiPath().hasPrefix("plugin/discover/new"))
    // 运行时解析不覆盖持久化默认。
    XCTAssertEqual(ExploreViewModel.storedDefaultConfiguration(), saved)
  }

  func testPluginDefaultConfirmedAbsentFallsBackWithoutOverwritingStore() async throws {
    let saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/gone")))
    ExploreViewModel.saveDefaultConfiguration(saved)
    ExploreVisibilityURLProtocol.setSources("[]")

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration(),
      restoredDefault: true
    )
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")
    XCTAssertEqual(ExploreViewModel.storedDefaultConfiguration(), saved)
  }

  func testHiddenDefaultSourceFallsBackWithoutOverwritingStore() async throws {
    let saved = ExploreConfiguration(source: .douban)
    ExploreViewModel.saveDefaultConfiguration(saved)
    let settings = ExploreViewModel(apiService: makeService(), loadsResults: false, sourcePolicy: .contentSettings)
    settings.saveSourceVisibility(["douban": false])

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration(),
      restoredDefault: true
    )
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")
    XCTAssertEqual(ExploreViewModel.storedDefaultConfiguration(), saved)
  }

  func testPendingDefaultAppliesOnceOnTabEntry() async throws {
    var saved = ExploreConfiguration(source: .douban)
    saved.doubanSort = "R"
    ExploreViewModel.saveDefaultConfiguration(saved)

    let viewModel = ExploreViewModel(apiService: makeService())
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")

    viewModel.consumePendingDefaultIfNeeded()
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.doubanSort, "R")

    // 标志已消费：会话内修改后再次进入不得重置。
    viewModel.selectedType = .tvs
    viewModel.consumePendingDefaultIfNeeded()
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.selectedType, .tvs)
    XCTAssertFalse(UserDefaults.standard.bool(forKey: ExploreViewModel.defaultPendingKey))
  }

  func testDraftRestoreDoesNotWriteStorage() async throws {
    let draft = ExploreViewModel(apiService: makeService(), loadsResults: false, sourcePolicy: .defaultSettings)
    draft.restoreConfiguration(ExploreConfiguration(source: .anilist))
    XCTAssertNil(ExploreViewModel.storedDefaultConfiguration())
    XCTAssertFalse(UserDefaults.standard.bool(forKey: ExploreViewModel.defaultPendingKey))
  }

  func testRestoreConfigurationPreservesTypeAndSort() async throws {
    let viewModel = ExploreViewModel(apiService: makeService())
    await viewModel.refreshSources()
    var saved = ExploreConfiguration(source: .douban)
    saved.doubanSort = "R"
    saved.selectedType = .tvs
    viewModel.restoreConfiguration(saved)
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.doubanSort, "R")
    XCTAssertEqual(viewModel.selectedType, .tvs)
  }

  func testPendingDefaultPreservesTypeAndSort() async throws {
    var saved = ExploreConfiguration(source: .douban)
    saved.doubanSort = "R"
    saved.selectedType = .tvs
    ExploreViewModel.saveDefaultConfiguration(saved)
    let viewModel = ExploreViewModel(apiService: makeService())
    await viewModel.refreshSources()
    viewModel.consumePendingDefaultIfNeeded()
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.doubanSort, "R")
    XCTAssertEqual(viewModel.selectedType, .tvs)
  }

  func testManualSelectSourceResetsFilters() async throws {
    let viewModel = ExploreViewModel(apiService: makeService())
    await viewModel.refreshSources()
    viewModel.tmdbSortBy = "vote_average.desc"
    viewModel.selectSource(.douban)
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.doubanSort, "U", "手动切换来源应重置为新来源默认筛选")
  }

  func testHiddenPluginDefaultFallsBackBeforeFirstLoad() async throws {
    let saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/plug")))
    ExploreViewModel.saveDefaultConfiguration(saved)
    let settings = ExploreViewModel(apiService: makeService(), loadsResults: false, sourcePolicy: .contentSettings)
    settings.saveSourceVisibility(["custom:plug": false])
    // 不刷新来源（首次加载未完成）：已隐藏的插件默认不得保留，应回退第一个可用来源。
    let viewModel = ExploreViewModel(apiService: makeService(), configuration: saved, restoredDefault: true)
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")
    XCTAssertFalse(viewModel.availableSources.contains { $0.id == "custom:plug" })
  }

  /// 接线守卫：探索页手动切换来源必须经 selectSource，不得用 onChange(of: selectedSource)
  /// 触发重置（否则程序化恢复/解析默认会被重置）。View 挂载后的焦点/运行时仍须真机验收。
  func testExploreViewRoutesManualSourceChangeThroughSelectSourceInSource() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("MoviePilot-TV/Views/Pages/ExploreView.swift")
    let source = try String(contentsOf: url)
    XCTAssertTrue(source.contains("viewModel.selectSource"))
    XCTAssertFalse(source.contains(".onChange(of: viewModel.selectedSource)"))
  }

  private func makeDescriptor(path: String) -> DiscoverSourceDescriptor {
    DiscoverSourceDescriptor(
      name: "插件探索", mediaid_prefix: "plug", api_path: path,
      filter_params: ["sort": .string("new")], filter_ui: [], depends: nil
    )
  }

  private func makeService() -> APIService {
    let service = APIService.isolatedTestingInstance()
    let user = Token(
      access_token: "explore-default-test", token_type: "bearer", super_user: FlexibleBool(false),
      permissions: ["discovery": true], user_id: 504, user_name: "explore-default-test", avatar: nil
    )
    service.replaceSessionForTesting(
      baseURL: "http://explore-visibility.local", token: user.access_token, currentUser: user
    )
    return service
  }
}