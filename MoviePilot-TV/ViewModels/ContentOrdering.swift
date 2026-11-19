import Foundation

/// 推荐货架与探索来源共用的顺序合并。
/// 顺序只存稳定 id；已消失 id 的槽位在保存时钉在原索引，来源恢复后回到原位置。
nonisolated enum ContentOrdering {
  /// 渲染顺序：当前存在的 id 按存储顺序排列，未登记的新 id 按默认顺序追加。
  static func orderedVisibleIDs(stored: [String], current: [String]) -> [String] {
    let currentIDs = Set(current)
    var seen = Set<String>()
    var result = stored.filter { currentIDs.contains($0) && seen.insert($0).inserted }
    result.append(contentsOf: current.filter { seen.insert($0).inserted })
    return result
  }

  /// 保存顺序：消失 id 钉在存储数组的原槽位，可见 id 按新顺序填入其余槽位，
  /// 装不下的（含全新 id）追加末尾。
  static func persistOrder(stored: [String], reorderedVisible: [String]) -> [String] {
    let visibleIDs = Set(reorderedVisible)
    var remaining = reorderedVisible.makeIterator()
    var result: [String] = []
    for id in stored {
      if visibleIDs.contains(id) {
        if let next = remaining.next() {
          result.append(next)
        }
      } else {
        result.append(id)
      }
    }
    while let next = remaining.next() {
      result.append(next)
    }
    return result
  }
}