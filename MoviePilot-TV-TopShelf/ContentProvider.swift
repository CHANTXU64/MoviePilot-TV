import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
  nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
    guard let store = TopShelfSharedStore.appGroupStore() else {
      return nil
    }
    try? await TopShelfRefreshClient(store: store).refresh()
    return Self.content(from: store)
  }

  private static func content(from store: TopShelfSharedStore) -> (any TVTopShelfContent)? {
    guard let presentation = store.presentation(at: Date())
    else {
      return nil
    }

    let items = presentation.items.map { source in
      let item = TVTopShelfSectionedItem(identifier: source.identifier)
      item.title = source.title
      item.imageShape = TopShelfImageLoader.cardShape
      item.setImageURL(source.imageURL, for: [.screenScale1x, .screenScale2x])
      item.displayAction = TVTopShelfAction(url: source.displayURL)
      return item
    }
    guard !items.isEmpty else {
      return nil
    }

    let collection = TVTopShelfItemCollection(items: items)
    collection.title = presentation.title
    return TVTopShelfSectionedContent(sections: [collection])
  }
}
