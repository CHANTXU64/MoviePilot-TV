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
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration()
    )
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "themoviedb")
    XCTAssertEqual(viewModel.selectedType, .tvs)
    XCTAssertEqual(viewModel.tmdbSortBy, "vote_average.desc")
    XCTAssertTrue(viewModel.buildApiPath().hasPrefix("discover/tmdb_tvs?"))
    XCTAssertTrue(viewModel.buildApiPath().contains("sort_by=vote_average.desc"))
    XCTAssertTrue(viewModel.buildApiPath().contains("vote_count=500"))
  }

  func testPluginDefaultContractChangeResetsToNewDefaults() async throws {
    var saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/old")))
    saved.pluginFilterValues = ["sort": .string("hot")]
    ExploreViewModel.saveDefaultConfiguration(saved)
    // 插件升级：filter_params 合同变化（新增 lang）。对齐 Web ExtraSourceView：
    // 合同变化时清空旧值、用新默认重建，废弃字段不再发送。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/new",
        "filter_params":{"sort":"new","lang":"zh"},"filter_ui":[]}]
      """)

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration()
    )
    // 首次来源加载完成前：不回退、保留保存值。
    XCTAssertEqual(viewModel.selectedSource.id, "custom:plug")
    XCTAssertEqual(viewModel.availableSources.first?.id, "custom:plug")
    XCTAssertEqual(viewModel.pluginFilterValues["sort"], .string("hot"))

    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "custom:plug")
    XCTAssertEqual(viewModel.selectedSource.descriptor?.api_path, "plugin/discover/new")
    XCTAssertEqual(viewModel.pluginFilterValues["sort"], .string("new"), "合同变化应重置为新默认")
    XCTAssertEqual(viewModel.pluginFilterValues["lang"], .string("zh"))
    XCTAssertTrue(viewModel.buildApiPath().hasPrefix("plugin/discover/new"))
    XCTAssertFalse(viewModel.buildApiPath().contains("sort=hot"), "废弃的保存值不得再发送")
    // 运行时解析不覆盖持久化默认。
    XCTAssertEqual(ExploreViewModel.storedDefaultConfiguration(), saved)
  }

  func testPluginDefaultContractUnchangedPreservesSavedValues() async throws {
    var saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/old")))
    saved.pluginFilterValues = ["sort": .string("hot")]
    ExploreViewModel.saveDefaultConfiguration(saved)
    // 仅 api_path 变化、filter_params 合同不变：保留用户保存值。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件探索","mediaid_prefix":"plug","api_path":"plugin/discover/new",
        "filter_params":{"sort":"new"},"filter_ui":[]}]
      """)

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration()
    )
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.descriptor?.api_path, "plugin/discover/new")
    XCTAssertEqual(viewModel.pluginFilterValues["sort"], .string("hot"), "合同不变应保留保存值")
  }

  func testPluginDefaultConfirmedAbsentFallsBackWithoutOverwritingStore() async throws {
    let saved = ExploreConfiguration(source: .custom(makeDescriptor(path: "plugin/discover/gone")))
    ExploreViewModel.saveDefaultConfiguration(saved)
    ExploreVisibilityURLProtocol.setSources("[]")

    let viewModel = ExploreViewModel(
      apiService: makeService(),
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration()
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
      configuration: ExploreViewModel.storedDefaultConfiguration() ?? ExploreConfiguration()
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
    // 首次刷新成功即消费默认（VM 内部）。
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.doubanSort, "R")

    // 标志已消费：会话内修改后再次刷新不得重置。
    viewModel.selectedType = .tvs
    await viewModel.refreshSources()
    XCTAssertEqual(viewModel.selectedSource.id, "douban")
    XCTAssertEqual(viewModel.selectedType, .tvs)
    XCTAssertFalse(UserDefaults.standard.bool(forKey: ExploreViewModel.defaultPendingKey))
  }

  func testNewPluginDefaultAppliesAfterRefreshOnTabEntry() async throws {
    // 探索页已打开，旧快照无新插件。
    ExploreVisibilityURLProtocol.setSources("[]")
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()
    XCTAssertEqual(browse.selectedSource.id, "themoviedb")

    // 后端安装新插件；用户在设置选它做默认并保存筛选。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"新插件","mediaid_prefix":"newplug","api_path":"plugin/discover/newplug",
        "filter_params":{"sort":"new"},"filter_ui":[]}]
      """)
    var saved = ExploreConfiguration(source: .custom(DiscoverSourceDescriptor(
      name: "新插件", mediaid_prefix: "newplug", api_path: "plugin/discover/newplug",
      filter_params: ["sort": .string("new")], filter_ui: [], depends: nil)))
    saved.pluginFilterValues = ["sort": .string("hot")]
    ExploreViewModel.saveDefaultConfiguration(saved)

    // 回到探索页：刷新来源成功后由 VM 内部消费默认，新插件应生效。
    await browse.refreshSources()
    XCTAssertEqual(browse.selectedSource.id, "custom:newplug")
    XCTAssertEqual(browse.pluginFilterValues["sort"], .string("hot"))
  }

  func testPendingDefaultRetainedOnSourceRefreshFailure() async throws {
    ExploreVisibilityURLProtocol.setSources("[]")
    let service = makeService()
    let browse = ExploreViewModel(apiService: service)
    await browse.refreshSources()

    // 安装新插件并设默认。
    let newPluginJSON = """
      [{"name":"新插件","mediaid_prefix":"newplug","api_path":"plugin/discover/newplug",
        "filter_params":{"sort":"new"},"filter_ui":[]}]
      """
    ExploreVisibilityURLProtocol.setSources(newPluginJSON)
    var saved = ExploreConfiguration(source: .custom(DiscoverSourceDescriptor(
      name: "新插件", mediaid_prefix: "newplug", api_path: "plugin/discover/newplug",
      filter_params: ["sort": .string("new")], filter_ui: [], depends: nil)))
    saved.pluginFilterValues = ["sort": .string("hot")]
    ExploreViewModel.saveDefaultConfiguration(saved)

    // 刷新失败：不得消费 pending，不得按旧快照回退丢失默认。
    ExploreVisibilityURLProtocol.setSources("[]", statusCode: 503)
    await browse.refreshSources()
    XCTAssertTrue(UserDefaults.standard.bool(forKey: ExploreViewModel.defaultPendingKey))
    XCTAssertNotEqual(browse.selectedSource.id, "custom:newplug")

    // 下次刷新成功：重新应用默认。
    ExploreVisibilityURLProtocol.setSources(newPluginJSON)
    await browse.refreshSources()
    XCTAssertEqual(browse.selectedSource.id, "custom:newplug")
    XCTAssertEqual(browse.pluginFilterValues["sort"], .string("hot"))
    XCTAssertFalse(UserDefaults.standard.bool(forKey: ExploreViewModel.defaultPendingKey))
  }

  func testDefaultDraftResetsDeprecatedFieldsOnContractChange() async throws {
    let old = DiscoverSourceDescriptor(
      name: "插件", mediaid_prefix: "plug", api_path: "plugin/discover/p",
      filter_params: ["sort": .string("new"), "category": .string("movie")], filter_ui: [], depends: nil)
    var saved = ExploreConfiguration(source: .custom(old))
    saved.pluginFilterValues = ["sort": .string("hot"), "category": .string("movie")]
    // 新版删除 category 字段。
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件","mediaid_prefix":"plug","api_path":"plugin/discover/p",
        "filter_params":{"sort":"new"},"filter_ui":[]}]
      """)
    let draft = ExploreViewModel(
      apiService: makeService(), configuration: saved, loadsResults: false, sourcePolicy: .defaultSettings)
    await draft.refreshSources()
    XCTAssertNil(draft.pluginFilterValues["category"], "编辑页合同变化应丢弃废弃字段")
    XCTAssertEqual(draft.pluginFilterValues["sort"], .string("new"))
    ExploreViewModel.saveDefaultConfiguration(draft.configuration)
    XCTAssertNil(ExploreViewModel.storedDefaultConfiguration()?.pluginFilterValues["category"])
  }

  func testTopShelfDraftKeepsLegacyMergeBehavior() async throws {
    let old = DiscoverSourceDescriptor(
      name: "插件", mediaid_prefix: "plug", api_path: "plugin/discover/p",
      filter_params: ["sort": .string("new"), "category": .string("movie")], filter_ui: [], depends: nil)
    var saved = ExploreConfiguration(source: .custom(old))
    saved.pluginFilterValues = ["sort": .string("hot"), "category": .string("movie")]
    ExploreVisibilityURLProtocol.setSources("""
      [{"name":"插件","mediaid_prefix":"plug","api_path":"plugin/discover/p",
        "filter_params":{"sort":"new"},"filter_ui":[]}]
      """)
    let draft = ExploreViewModel(
      apiService: makeService(), configuration: saved, loadsResults: false, sourcePolicy: .topShelf)
    await draft.refreshSources()
    XCTAssertEqual(draft.pluginFilterValues["category"], .string("movie"), "Top Shelf 保持原有合并行为")
    XCTAssertEqual(draft.pluginFilterValues["sort"], .string("hot"))
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
    let viewModel = ExploreViewModel(apiService: makeService(), configuration: saved)
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