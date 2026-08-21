import SwiftUI
import XCTest

@testable import MoviePilot_TV

@MainActor
final class TorrentCardDisplayNormalizationTests: XCTestCase {
  // MARK: - 主标题规范链

  func testDisplayTitleFallsBackWhenMediaTitleIsBlank() {
    let media = MediaInfo(title: "   ", type: "电影")
    let meta = makeMeta(name: "有效媒体名")
    let torrent = makeTorrent(title: "种子标题")

    XCTAssertEqual(
      TorrentCard.displayTitle(media: media, meta: meta, torrent: torrent),
      "有效媒体名"
    )
  }

  func testDisplayTitleFallsBackToTorrentTitleWhenMetaNameIsBlank() {
    let media = MediaInfo(title: "", type: "电影")
    let meta = makeMeta(name: "  ")
    let torrent = makeTorrent(title: " 种子标题 ")

    XCTAssertEqual(
      TorrentCard.displayTitle(media: media, meta: meta, torrent: torrent),
      "种子标题"
    )
  }

  func testDisplayTitleFallsBackToEmptyWhenAllBlank() {
    XCTAssertEqual(
      TorrentCard.displayTitle(
        media: nil,
        meta: makeMeta(name: ""),
        torrent: makeTorrent(title: " \n ")
      ),
      ""
    )
  }

  func testDisplayTitleKeepsTrimmedValidTitle() {
    let media = MediaInfo(title: " 真实的媒体名 ", type: "电影")

    XCTAssertEqual(
      TorrentCard.displayTitle(media: media, meta: nil, torrent: makeTorrent(title: "种子")),
      "真实的媒体名"
    )
  }

  // MARK: - 副标题规范链

  func testDescriptionFallsBackWhenSubtitleIsBlank() {
    let meta = makeMeta(name: "x", subtitle: "   ")
    let torrent = makeTorrent(title: "t", description: "有效种子描述")

    XCTAssertEqual(
      TorrentCard.descriptionText(meta: meta, torrent: torrent),
      "有效种子描述"
    )
  }

  func testDescriptionFallsBackWhenSubtitleIsEmptyString() {
    let meta = makeMeta(name: "x", subtitle: "")
    let torrent = makeTorrent(title: "t", description: "种子描述")

    XCTAssertEqual(TorrentCard.descriptionText(meta: meta, torrent: torrent), "种子描述")
  }

  func testDescriptionPrefersSubtitleWhenValid() {
    let meta = makeMeta(name: "x", subtitle: " 副标题 ")
    let torrent = makeTorrent(title: "t", description: "种子描述")

    XCTAssertEqual(TorrentCard.descriptionText(meta: meta, torrent: torrent), "副标题")
  }

  func testDescriptionIsNilWhenAllBlank() {
    let meta = makeMeta(name: "x", subtitle: "")
    let torrent = makeTorrent(title: "t", description: "   ")

    XCTAssertNil(TorrentCard.descriptionText(meta: meta, torrent: torrent))
  }

  // MARK: - 筛选选项规范化

  func testFilterOptionNormalizesBlankToNone() {
    XCTAssertEqual(TorrentsResultView<EmptyView>.normalizedFilterOption(nil), "无")
    XCTAssertEqual(TorrentsResultView<EmptyView>.normalizedFilterOption(""), "无")
    XCTAssertEqual(TorrentsResultView<EmptyView>.normalizedFilterOption("   "), "无")
  }

  func testFilterOptionTrimsAndKeepsValue() {
    XCTAssertEqual(TorrentsResultView<EmptyView>.normalizedFilterOption(" 1080p "), "1080p")
    XCTAssertEqual(TorrentsResultView<EmptyView>.normalizedFilterOption("HDR"), "HDR")
  }

  // MARK: - 促销筛选值

  func testFreeStateKeepsBackendVolumeFactorVerbatim() {
    XCTAssertEqual(
      TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "30%")),
      "30%"
    )
    XCTAssertEqual(
      TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "4X")),
      "4X"
    )
    XCTAssertEqual(
      TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "2X 50%")),
      "2X 50%"
    )
  }

  func testFreeStateTrimsWhitespace() {
    XCTAssertEqual(
      TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "  4X  ")),
      "4X"
    )
  }

  func testFreeStateIsNilWhenBlank() {
    XCTAssertNil(TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: nil)))
    XCTAssertNil(TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "")))
    XCTAssertNil(TorrentsResultView<EmptyView>.freeStateValue(makeContext(volumeFactor: "   ")))
  }

  // MARK: - 构造辅助

  private func makeContext(volumeFactor: String?) -> Context {
    Context(
      torrent_info: TorrentInfo(
        site: 1, site_name: "测试站点", site_order: 1, title: "t", description: nil,
        enclosure: "https://example.test/t", page_url: nil, size: 100,
        seeders: 1, peers: 1, pubdate: nil, uploadvolumefactor: 1, downloadvolumefactor: 1,
        pri_order: 1, labels: [], volume_factor: volumeFactor
      )
    )
  }

  private func makeMeta(name: String, subtitle: String? = nil) -> MetaInfo {
    MetaInfo(
      title: nil, year: nil, resource_team: nil, video_encode: nil, resource_pix: nil,
      name: name, season_episode: "", subtitle: subtitle, web_source: nil,
      edition: nil, total_season: nil, total_episode: nil
    )
  }

  private func makeTorrent(title: String, description: String? = nil) -> TorrentInfo {
    TorrentInfo(
      site: 1, site_name: "测试站点", site_order: 1, title: title, description: description,
      enclosure: "https://example.test/\(title)", page_url: nil, size: 100,
      seeders: 1, peers: 1, pubdate: nil, uploadvolumefactor: 1, downloadvolumefactor: 1,
      pri_order: 1, labels: [], volume_factor: nil
    )
  }
}
