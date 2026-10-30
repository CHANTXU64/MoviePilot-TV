import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
  nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
    guard let store = TopShelfSharedStore.appGroupStore() else {
      return nil
    }
    // 真机实测：先联网刷新再交出内容时，扩展会在交出前被系统收走，主屏退回静态图。
    // 这里只读本地缓存并立刻返回；缓存由主 App 打开时刷新。
    guard let presentation = store.presentation(at: Date()) else {
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
