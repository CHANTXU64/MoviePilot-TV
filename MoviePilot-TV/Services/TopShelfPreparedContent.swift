import Foundation

/// 仅主 App 解码的详情文件；扩展只读取快照里的卡片和图片路径。
nonisolated struct TopShelfPreparedContent: Codable {
  let detail: MediaInfo
  var collectionItems: [MediaInfo]? = nil
}

nonisolated struct TopShelfCachedContent: Hashable {
  let detail: MediaInfo
  let backgroundURL: URL
  let backgroundIsPoster: Bool
  var collectionItems: [MediaInfo]? = nil
}

extension TopShelfSharedStore {
  nonisolated func cachedContent(
    for payload: TopShelfRoutePayload, at date: Date
  ) -> TopShelfCachedContent? {
    guard let item = cachedItem(for: payload, at: date),
      let detailPath = item.detailRelativePath,
      let data = try? detailData(relativePath: detailPath),
      let content = try? JSONDecoder().decode(TopShelfPreparedContent.self, from: data),
      let backgroundPath = item.backgroundRelativePath,
      let backgroundURL = imageURL(relativePath: backgroundPath),
      FileManager.default.fileExists(atPath: backgroundURL.path)
    else { return nil }
    return TopShelfCachedContent(
      detail: content.detail,
      backgroundURL: backgroundURL,
      backgroundIsPoster: item.backgroundIsPoster ?? true,
      collectionItems: content.collectionItems
    )
  }
}
