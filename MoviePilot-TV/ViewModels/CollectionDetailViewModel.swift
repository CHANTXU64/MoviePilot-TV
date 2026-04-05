import Combine
import Foundation

@MainActor
class CollectionDetailViewModel: ObservableObject {
  let paginator: Paginator<MediaInfo>
  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()

  init(collectionId: Int, title: String) {
    var seenKeys = Set<String>()

    self.paginator = Paginator<MediaInfo>(
      threshold: 12,
      fetcher: { @MainActor [apiService] page in
        try await apiService.fetchCollection(collectionId: collectionId, page: page, title: title)
      },
      processor: { @MainActor items, newItems in
        // 使用现有的去重逻辑
        let unique = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
        if !unique.isEmpty {
          items.append(contentsOf: unique)
          return true
        }
        return false
      },
      imageURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
      },
      onReset: { @MainActor in
        seenKeys.removeAll()  // 重置时清空 seenKeys
      }
    )

    self.paginator.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  private var hasLoaded = false

  func loadInitialData() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await paginator.refresh()
  }
}
