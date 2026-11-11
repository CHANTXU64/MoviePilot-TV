import Foundation

nonisolated enum TopShelfSelectionPolicy {
  static let defaultShelfID = "recommend/tmdb_trending"

  static func resolve(
    saved: TopShelfSelection?,
    shelves: [RecommendShelf]
  ) -> TopShelfSelection? {
    if let saved {
      if saved.exploration != nil { return saved }
      if let current = shelves.first(where: { $0.id == saved.shelfID }) {
        return TopShelfSelection(shelfID: current.id, title: current.title)
      }

      return saved

    }

    return fallback(from: shelves)
  }

  static func options(
    saved: TopShelfSelection?,
    shelves: [RecommendShelf]
  ) -> [TopShelfSelection] {
    var options = shelves.map { shelf in
      TopShelfSelection(shelfID: shelf.id, title: shelf.title)
    }

    // 即使来源暂时不可用或已删除，也保留用户的选择。
    if let saved, saved.exploration == nil,
      !options.contains(where: { $0.shelfID == saved.shelfID })
    {
      options.insert(saved, at: 0)
    }
    return options
  }

  private static func fallback(from shelves: [RecommendShelf]) -> TopShelfSelection? {
    guard let shelf = shelves.first(where: { $0.id == defaultShelfID }) ?? shelves.first else {
      return nil
    }
    return TopShelfSelection(shelfID: shelf.id, title: shelf.title)
  }
}
