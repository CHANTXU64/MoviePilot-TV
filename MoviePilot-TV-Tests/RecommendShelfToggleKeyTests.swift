import XCTest

@testable import MoviePilot_TV

/// F-240 回归：推荐货架的开关配置必须以稳定 `shelf.id`（API 路径）为键，
/// 而不是可重复的 `shelf.title`。旧版本本地配置按 title 保存，读取时做一次性迁移。
@MainActor
final class RecommendShelfToggleKeyTests: XCTestCase {
  private static let configKey = "MP_RECOMMEND"

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: Self.configKey)
    super.tearDown()
  }

  private func seedLegacyConfig(_ config: [String: Bool]) {
    let data = try! JSONEncoder().encode(config)
    UserDefaults.standard.set(data, forKey: Self.configKey)
  }

  private func storedConfig() -> [String: Bool]? {
    guard let data = UserDefaults.standard.data(forKey: Self.configKey) else { return nil }
    return try? JSONDecoder().decode([String: Bool].self, from: data)
  }

  // MARK: 开关独立性

  /// 两条同名不同路径的货架，用 id 键配置后必须能独立开关。
  func testSameTitleDifferentPathShelvesToggleIndependently() {
    let a = RecommendShelf(id: "rec/a", title: "同名榜", category: .chart)
    let b = RecommendShelf(id: "rec/b", title: "同名榜", category: .chart)

    // 旧 title 键语义下无法表达这个配置：同名两行共享一个布尔值。
    let enabled = RecommendViewModel.enabledShelves(
      [a, b],
      enableConfig: ["rec/a": false, "rec/b": true]
    )

    XCTAssertEqual(enabled.map(\.id), ["rec/b"])
  }

  /// 同名两行分属同一分类时，visibility 也要跟随各自的 id 开关，而不是一损俱损。
  func testVisibleCategoriesFollowPerIDSameTitleToggles() {
    let a = RecommendShelf(id: "rec/a", title: "同名榜", category: .anime)
    let b = RecommendShelf(id: "rec/b", title: "同名榜", category: .anime)

    // A 关、B 开 → 分类仍可见。
    let withOneOn = RecommendViewModel.visibleCategories(
      shelves: [a, b],
      enableConfig: ["rec/a": false, "rec/b": true]
    )
    XCTAssertTrue(withOneOn.contains(.anime))

    // 两行都关 → 分类消失。
    let bothOff = RecommendViewModel.visibleCategories(
      shelves: [a, b],
      enableConfig: ["rec/a": false, "rec/b": false]
    )
    XCTAssertFalse(bothOff.contains(.anime))
  }

  // MARK: 旧 title 键配置迁移

  /// 旧版以 title 为键的本地配置，加载后一次性迁移到稳定 id，并保留原开关值。
  func testLegacyTitleKeyConfigMigratesToShelfIDPreservingValues() {
    seedLegacyConfig([
      "流行趋势": true,       // recommend/tmdb_trending
      "豆瓣Top250": false,   // recommend/douban_movie_top250
      "豆瓣热门剧集": true,   // recommend/douban_tv_hot
    ])
    defer { UserDefaults.standard.removeObject(forKey: Self.configKey) }

    let viewModel = RecommendViewModel(selectShelf: false)

    XCTAssertEqual(viewModel.enableConfig["recommend/tmdb_trending"], true)
    XCTAssertEqual(viewModel.enableConfig["recommend/douban_movie_top250"], false)
    XCTAssertEqual(viewModel.enableConfig["recommend/douban_tv_hot"], true)
    // 旧 title 键不再残留为配置键。
    XCTAssertNil(viewModel.enableConfig["流行趋势"])
    XCTAssertNil(viewModel.enableConfig["豆瓣Top250"])

    // 过滤结果跟随迁移后的 id 键。
    let enabledIDs = Set(viewModel.filteredShelves.map(\.id))
    XCTAssertTrue(enabledIDs.contains("recommend/tmdb_trending"))
    XCTAssertTrue(enabledIDs.contains("recommend/douban_tv_hot"))
    XCTAssertFalse(enabledIDs.contains("recommend/douban_movie_top250"))

    // 迁移结果已用 id 键回写落盘，避免每次启动重复迁移。
    let stored = storedConfig()
    XCTAssertEqual(stored?["recommend/douban_movie_top250"], false)
    XCTAssertNil(stored?["豆瓣Top250"])
  }

  // MARK: 迁移 helper 边界

  /// 迁移 helper 对唯一 title 改键、对共用同名 title 按旧共享值平铺、
  /// 对未知键与已是 id 的键原样保留。
  func testMigrateTitleKeysHandlesAmbiguousAndUnknown() {
    let a = RecommendShelf(id: "rec/a", title: "同名榜", category: .chart)
    let b = RecommendShelf(id: "rec/b", title: "同名榜", category: .chart)
    let c = RecommendShelf(id: "rec/c", title: "唯一榜", category: .chart)

    let migrated = RecommendViewModel.migrateTitleKeys(
      in: ["同名榜": false, "唯一榜": true, "ghost": false, "rec/a": true],
      shelves: [a, b, c]
    )

    // 已是 id 键的 rec/a 不被同名平铺覆盖，仍为 true；rec/b 继承共享值 false。
    XCTAssertEqual(migrated["rec/a"], true)
    XCTAssertEqual(migrated["rec/b"], false)
    // 唯一 title 改键到 rec/c。
    XCTAssertEqual(migrated["rec/c"], true)
    // 两个 title 键都被消费移除。
    XCTAssertNil(migrated["同名榜"])
    XCTAssertNil(migrated["唯一榜"])
    // 未知键原样保留，不做破坏性删除。
    XCTAssertEqual(migrated["ghost"], false)
  }

  // MARK: 视图接线守卫

  /// System 推荐开关必须按 shelf.id 读写配置（与 ForEach/焦点同一身份）。
  func testSystemToggleKeysByShelfID() throws {
    let source = try Self.source(at: "MoviePilot-TV/Views/Pages/SystemView.swift")
    XCTAssertTrue(source.contains("enableConfig[shelf.id]"))
    XCTAssertFalse(source.contains("enableConfig[shelf.title]"))
  }

  private static func source(at path: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
  }
}
