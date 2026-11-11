import XCTest

@testable import MoviePilot_TV

/// F-135：目录选项的取值边界。
///
/// 保存路径下拉框内建「自动」选项的 value 就是空串，而 `PickerOption.id` 直接取 `value`。
/// 因此空/纯空白的 `download_path` 必须在进入列表前被 trim 掉 —— 否则本地空目录会和「自动」
/// 撞成同一个 ID，远程空目录则会生成 `"qb:"` 这种并不存在的路径（提交后被后端拒绝）。
///
/// 同时覆盖并入本轮的 `storage` 可选化加固：后端 schema 是 `Optional[str]`，公开接口返回的
/// 又是未经校验的原始配置，该键可能缺失；保持非可选会让整个目录数组解码失败。
@MainActor
final class DirectoryOptionNormalizationTests: XCTestCase {

  // MARK: - Fixtures

  private func directory(
    name: String = "目录",
    storage: String? = "local",
    downloadPath: String?
  ) -> TransferDirectoryConf {
    TransferDirectoryConf(
      name: name,
      storage: storage,
      download_path: downloadPath,
      library_path: nil,
      library_storage: nil,
      transfer_type: "copy",
      scraping: nil,
      library_category_folder: nil,
      library_type_folder: nil
    )
  }

  private func addDownloadViewModel(
    _ directories: [TransferDirectoryConf]
  ) -> AddDownloadViewModel {
    let viewModel = AddDownloadViewModel(
      torrent: TorrentInfo(
        site: 1,
        site_name: "站点",
        site_order: nil,
        title: "测试资源",
        description: nil,
        enclosure: "https://example.com/test.torrent",
        page_url: nil,
        size: 1024,
        seeders: nil,
        peers: nil,
        pubdate: nil,
        uploadvolumefactor: 1,
        downloadvolumefactor: 1,
        pri_order: nil,
        labels: nil,
        volume_factor: nil
      )
    )
    viewModel.directories = directories
    return viewModel
  }

  private func subscribeViewModel(
    _ directories: [TransferDirectoryConf]
  ) -> SubscribeSheetViewModel {
    let viewModel = SubscribeSheetViewModel(
      subscribe: Subscribe(id: 1, name: "目录测试", type: "电影"))
    viewModel.directories = directories
    return viewModel
  }

  // MARK: - 添加下载：空/空白路径不得与「自动」撞车

  func testEmptyAndBlankPathsAreDroppedEntirely() {
    let viewModel = addDownloadViewModel([
      directory(name: "空串", storage: "local", downloadPath: ""),
      directory(name: "纯空白", storage: "local", downloadPath: "   "),
      directory(name: "远程空白", storage: "qbittorrent", downloadPath: " \n "),
      directory(name: "正常", storage: "local", downloadPath: "/downloads"),
    ])

    XCTAssertEqual(viewModel.targetDirectories, ["/downloads"])
    XCTAssertFalse(
      viewModel.targetDirectories.contains(""),
      "空串路径会与内建「自动」选项撞成同一个 ID")
    XCTAssertFalse(
      viewModel.targetDirectories.contains("qbittorrent:"),
      "远程空路径不得退化成只有存储前缀的伪路径")
  }

  /// 下拉框实际渲染的是「自动」+ `targetDirectories`，此处按同样方式组合后断言身份唯一 ——
  /// 这就是审计要求的「保留唯一自动项」，不需要额外占位，靠列表里不再出现空串达成。
  func testComposedPickerOptionsKeepUniqueIdentities() {
    let viewModel = addDownloadViewModel([
      directory(storage: "local", downloadPath: ""),
      directory(storage: "qbittorrent", downloadPath: "  "),
      directory(storage: "local", downloadPath: "/downloads"),
    ])

    let options = [PickerOption(title: "自动", value: "")]
      + viewModel.targetDirectories.map { PickerOption(title: $0, value: $0) }

    XCTAssertEqual(options.map(\.title), ["自动", "/downloads"])
    XCTAssertEqual(Set(options.map(\.id)).count, options.count, "Picker ID 必须唯一")
  }

  func testPathsAreTrimmedBeforeDeduplication() {
    let viewModel = addDownloadViewModel([
      directory(name: "带空白", storage: "local", downloadPath: " /downloads "),
      directory(name: "原样", storage: "local", downloadPath: "/downloads"),
    ])

    XCTAssertEqual(
      viewModel.targetDirectories, ["/downloads"],
      "先 trim 再去重，同一路径的带空白写法应合并为一项")
  }

  func testLocalAndRemotePathsWithSameSuffixStayDistinct() {
    let viewModel = addDownloadViewModel([
      directory(storage: "local", downloadPath: "/downloads"),
      directory(storage: "qbittorrent", downloadPath: "/downloads"),
      directory(storage: "local", downloadPath: "/downloads"),
    ])

    XCTAssertEqual(viewModel.targetDirectories, ["/downloads", "qbittorrent:/downloads"])
  }

  func testDeclarationOrderIsPreserved() {
    let viewModel = addDownloadViewModel([
      directory(storage: "qbittorrent", downloadPath: "/remote"),
      directory(storage: "local", downloadPath: "/local"),
    ])

    XCTAssertEqual(viewModel.targetDirectories, ["qbittorrent:/remote", "/local"])
  }

  // MARK: - 订阅：同一套规范化

  func testSubscribeSavePathOptionsTrimBlankAndDeduplicate() {
    let viewModel = subscribeViewModel([
      directory(name: "空白", storage: "local", downloadPath: "   "),
      directory(name: "带空白", storage: "local", downloadPath: " /downloads "),
      directory(name: "重复", storage: "local", downloadPath: "/downloads"),
      directory(name: "空串", storage: "local", downloadPath: ""),
      directory(name: "媒体库", storage: "qbittorrent", downloadPath: "/media"),
    ])

    XCTAssertEqual(viewModel.savePathOptions, ["/downloads", "/media"])
  }

  func testSubscribeSavePathOptionsDropsNilPaths() {
    let viewModel = subscribeViewModel([
      directory(name: "无路径", storage: "local", downloadPath: nil),
      directory(name: "正常", storage: "local", downloadPath: "/downloads"),
    ])

    XCTAssertEqual(viewModel.savePathOptions, ["/downloads"])
  }

  // MARK: - `storage` 可选化加固

  func testMissingStorageStillDecodesWholeDirectoryArray() throws {
    let json = Data(
      """
      [
        {"name":"缺 storage","download_path":"/downloads","transfer_type":"copy"},
        {"name":"正常","storage":"local","download_path":"/media","transfer_type":"copy"}
      ]
      """.utf8)

    let directories = try JSONDecoder().decode([TransferDirectoryConf].self, from: json)

    XCTAssertEqual(directories.count, 2, "一条缺 storage 不应拖垮整个数组")
    XCTAssertNil(directories[0].storage)
    XCTAssertEqual(directories[1].storage, "local")
  }

  func testNullStorageDecodesAsLocalDirectory() throws {
    let json = Data(
      """
      [{"name":"null storage","storage":null,"download_path":"/downloads","transfer_type":"copy"}]
      """.utf8)

    let directories = try JSONDecoder().decode([TransferDirectoryConf].self, from: json)
    let viewModel = addDownloadViewModel(directories)

    XCTAssertNil(directories.first?.storage)
    XCTAssertEqual(
      viewModel.targetDirectories, ["/downloads"],
      "storage 缺省即本地目录，不得生成 \":/downloads\"")
  }
}
