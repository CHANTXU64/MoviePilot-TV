import XCTest

@testable import MoviePilot_TV

/// F-209：选「全部站点」（空选择）时显式发送全部启用站点 ID，不再发 nil 让后端回退「搜索站点范围」默认子集。
/// 具体选择保持原样；启用站点为空时降级为 nil（回退后端默认）。
/// F-210：availableSites 仅在拿到权威域（/site/）时用于裁剪选择；降级为订阅域（/site/rss）时不做交集，
/// 避免把用户已保存的合法站点永久删掉。
@MainActor
final class SiteFilterViewModelSitesStringTests: XCTestCase {
  private func makeSite(id: Int, isActive: Bool?) -> Site {
    Site(
      id: id,
      name: "站点\(id)",
      domain: nil,
      url: nil,
      downloader: nil,
      is_active: isActive.map(FlexibleBool.init)
    )
  }

  private func makeViewModel(available: [Site]) -> SiteFilterViewModel {
    let viewModel = SiteFilterViewModel(apiService: .shared)
    viewModel.availableSites = available
    return viewModel
  }

  func testEmptySelectionAllActiveReturnsAllActiveIDs() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 2, isActive: true),
      makeSite(id: 1, isActive: true),
    ])
    viewModel.selectedSites = []
    XCTAssertEqual(viewModel.sitesString, "1,2")
  }

  func testEmptySelectionFiltersOutInactiveSites() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: true),
      makeSite(id: 2, isActive: false),
      makeSite(id: 3, isActive: true),
    ])
    viewModel.selectedSites = []
    XCTAssertEqual(viewModel.sitesString, "1,3")
  }

  func testEmptySelectionNoActiveSitesReturnsNil() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: false),
      makeSite(id: 2, isActive: false),
    ])
    viewModel.selectedSites = []
    XCTAssertNil(viewModel.sitesString)
  }

  func testEmptySelectionEmptyAvailableSitesReturnsNil() {
    let viewModel = makeViewModel(available: [])
    viewModel.selectedSites = []
    XCTAssertNil(viewModel.sitesString)
  }

  func testNilIsActiveTreatedAsInactive() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: nil),
      makeSite(id: 2, isActive: true),
    ])
    viewModel.selectedSites = []
    XCTAssertEqual(viewModel.sitesString, "2")
  }

  func testConcreteSelectionReturnedUnchanged() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: true),
      makeSite(id: 2, isActive: true),
      makeSite(id: 3, isActive: true),
    ])
    viewModel.selectedSites = [2, 3]
    XCTAssertEqual(viewModel.sitesString, "2,3")
  }

  func testConcreteSelectionSortedRegardlessOfOrder() {
    let viewModel = makeViewModel(available: [makeSite(id: 1, isActive: true)])
    viewModel.selectedSites = [5, 2]
    XCTAssertEqual(viewModel.sitesString, "2,5")
  }

  // MARK: - 归一化守卫（F-210：降级订阅域不得裁剪已保存选择）

  func testAuthoritativeLoadClipsSelectionToAvailable() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: true),
      makeSite(id: 2, isActive: true),
    ])
    viewModel.hasLoadedSites = true
    viewModel.loadedSitesAuthoritative = true
    viewModel.selectedSites = [5, 1]
    viewModel.normalizeSelectedSites()
    XCTAssertEqual(viewModel.selectedSites, [1])
  }

  func testNonAuthoritativeLoadDoesNotClipSelection() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: true),
      makeSite(id: 2, isActive: true),
    ])
    viewModel.hasLoadedSites = true
    viewModel.loadedSitesAuthoritative = false
    viewModel.selectedSites = [5]
    viewModel.normalizeSelectedSites()
    XCTAssertEqual(viewModel.selectedSites, [5])
  }

  func testNotLoadedDoesNotClipSelection() {
    let viewModel = makeViewModel(available: [
      makeSite(id: 1, isActive: true),
      makeSite(id: 2, isActive: true),
    ])
    viewModel.hasLoadedSites = false
    viewModel.loadedSitesAuthoritative = false
    viewModel.selectedSites = [9]
    viewModel.normalizeSelectedSites()
    XCTAssertEqual(viewModel.selectedSites, [9])
  }
}
