import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
  override func loadTopShelfContent(
    completionHandler: @escaping @Sendable ((any TVTopShelfContent)?) -> Void
  ) {
    Task {
      guard let store = TopShelfSharedStore.appGroupStore() else {
        completionHandler(nil)
        return
      }
      try? await TopShelfRefreshClient(store: store).refresh()
      completionHandler(Self.content(from: store))
    }
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
