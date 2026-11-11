import Foundation

enum ImageLoadWindow {
  enum HorizontalCardKind {
    case media
    case person
    /// 单集剧照卡较宽，一屏只放 4 张。
    case episode
  }

  nonisolated static let mediaHorizontalRadius = 6
  nonisolated static let personHorizontalRadius = 8
  nonisolated static let episodeHorizontalRadius = 4
  nonisolated static let gridPinnedTopRowCount = 2
  nonisolated static let gridRowsBefore = 2
  nonisolated static let gridRowsAfter = 2

  nonisolated static func containsHorizontalItem(
    at index: Int,
    itemCount: Int,
    anchorIndex: Int?,
    cardKind: HorizontalCardKind,
    usesFocusWindow: Bool
  ) -> Bool {
    // 不按焦点窗口时，已挂载的卡片都保留图片。
    guard usesFocusWindow else { return (0..<itemCount).contains(index) }
    let radius: Int
    switch cardKind {
    case .media:
      radius = mediaHorizontalRadius
    case .person:
      radius = personHorizontalRadius
    case .episode:
      radius = episodeHorizontalRadius
    }
    return contains(
      index: index,
      itemCount: itemCount,
      anchorIndex: anchorIndex,
      itemsBefore: radius,
      itemsAfter: radius
    )
  }

  nonisolated static func containsGridItem(
    at index: Int,
    itemCount: Int,
    anchorIndex: Int?,
    columnCount: Int
  ) -> Bool {
    guard itemCount > 0, columnCount > 0, (0..<itemCount).contains(index) else { return false }
    if index < min(itemCount, gridPinnedTopRowCount * columnCount) {
      return true
    }
    let anchor = min(max(anchorIndex ?? 0, 0), itemCount - 1)
    let anchorRow = anchor / columnCount
    let firstRow = max(0, anchorRow - gridRowsBefore)
    let lastRow = anchorRow + gridRowsAfter
    return index >= firstRow * columnCount
      && index < min(itemCount, (lastRow + 1) * columnCount)
  }

  nonisolated private static func contains(
    index: Int,
    itemCount: Int,
    anchorIndex: Int?,
    itemsBefore: Int,
    itemsAfter: Int
  ) -> Bool {
    guard itemCount > 0, (0..<itemCount).contains(index) else { return false }
    let anchor = min(max(anchorIndex ?? 0, 0), itemCount - 1)
    return index >= max(0, anchor - itemsBefore)
      && index <= min(itemCount - 1, anchor + itemsAfter)
  }
}
