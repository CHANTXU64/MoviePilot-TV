import Combine
import Foundation
import SwiftUI

enum SearchType: String, CaseIterable, Identifiable {
  case unified = "聚合搜索"
  case resource = "资源搜索"
  var id: String { self.rawValue }
}

enum BestResultItem: Identifiable, Hashable {
  case media(MediaInfo)
  case person(Person)

  var id: String {
    switch self {
    case .media(let m): return "media-\(m.id)"
    case .person(let p): return "person-\(p.id)"
    }
  }
}

/// 模糊匹配分值计算：用于给搜索结果进行初级排序
/// 原理：全匹配最高，前缀匹配次之，包含匹配再次，最后是按顺序出现的字符匹配
private func fuzzyMatchScore(text: String?, query: String) -> Int {
  guard let t = text?.lowercased(), !query.isEmpty else { return -1 }
  let q = query.lowercased()

  if t == q { return 1000 }  // 完全相等
  if t.hasPrefix(q) { return 500 - t.count }  // 前缀匹配（标题越短权重越高）
  if t.contains(q) { return 100 - t.count }  // 包含匹配

  // 字符顺序匹配（如搜索 "hml" 匹配 "Hamilton"）
  var qIndex = q.startIndex
  for char in t {
    if char == q[qIndex] {
      qIndex = q.index(after: qIndex)
      if qIndex == q.endIndex {
        return 50 - t.count
      }
    }
  }
  return -1
}

@MainActor
class SearchViewModel: ObservableObject {
  @Published var query: String = ""
  @Published var submittedQuery: String = ""  // 记录点击搜索时的关键词，用于分页请求
  @Published var hasSearched: Bool = false

  // MARK: - Paginator 实例

  /// 电影搜索分页器（由 SharedMediaFetcher 代理）
  @Published private(set) var moviePaginator: Paginator<MediaInfo>?
  /// 电视剧搜索分页器（由 SharedMediaFetcher 代理）
  @Published private(set) var tvPaginator: Paginator<MediaInfo>?
  /// 系列/合集搜索分页器
  @Published private(set) var collectionPaginator: Paginator<MediaInfo>?
  /// 人物搜索分页器
  @Published private(set) var personPaginator: Paginator<Person>?
  /// 订阅分享搜索分页器
  @Published private(set) var subscriptionSharePaginator: Paginator<MediaInfo>?

  @Published var bestResults: [BestResultItem] = []

  /// 核心逻辑：从所有搜索结果中筛选出"最佳匹配"项
  /// 规则：结合标题模糊匹配分值和媒体流行度 (Popularity)
  private func calculateBestResults(
    media: [MediaInfo],
    collections: [MediaInfo],
    persons: [Person],
    shares: [MediaInfo]
  ) -> [BestResultItem] {
    guard !submittedQuery.isEmpty else { return [] }

    // 尝试从搜索词中提取年份 (4位数字)，用于辅助匹配（如搜索 "流浪地球 2019"）
    let yearRegex = try? NSRegularExpression(pattern: "(19|20)\\d{2}")
    let nsQuery = submittedQuery as NSString
    let queryYear: String? = {
      if let match = yearRegex?.firstMatch(
        in: submittedQuery, range: NSRange(location: 0, length: nsQuery.length))
      {
        return nsQuery.substring(with: match.range)
      }
      return nil
    }()

    var scoredItems: [(item: BestResultItem, score: Int, popularity: Double)] = []

    // 1. 处理媒体搜索结果 (电影/电视剧)
    for mediaItem in media {
      let titles =
        ([mediaItem.title, mediaItem.original_title, mediaItem.original_name]
        + (mediaItem.names ?? []))
        .compactMap { $0 }
        .filter { !$0.isEmpty }

      var candidates = titles
      if let qYear = queryYear, let mYear = mediaItem.year, mYear.contains(qYear) {
        let withYear = titles.map { "\($0) \(qYear)" }
        candidates.append(contentsOf: withYear)
      }

      let maxS =
        Set(candidates).map { fuzzyMatchScore(text: $0, query: submittedQuery) }.max() ?? -1
      let pop = mediaItem.popularity ?? 0
      let hasNoPoster = mediaItem.poster_path == nil || mediaItem.poster_path?.isEmpty == true

      // 过滤匹配度极低且无海报的结果，减少噪音
      if !(hasNoPoster && maxS < 50 && pop < 1) {
        scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop))
      }
    }

    // 2. 处理合集/系列结果
    for mediaItem in collections {
      let titles =
        ([mediaItem.cleanedTitle, mediaItem.cleanedOriginalTitle, mediaItem.cleanedOriginalName]
        + (mediaItem.cleanedNames ?? []))
        .compactMap { $0 }
        .filter { !$0.isEmpty }

      var candidates = titles
      if let qYear = queryYear, let mYear = mediaItem.year, mYear.contains(qYear) {
        let withYear = titles.map { "\($0) \(qYear)" }
        candidates.append(contentsOf: withYear)
      }

      let maxS =
        Set(candidates).map { fuzzyMatchScore(text: $0, query: submittedQuery) }.max() ?? -1
      let pop = mediaItem.popularity ?? 0
      let hasNoPoster = mediaItem.poster_path == nil || mediaItem.poster_path?.isEmpty == true

      if !(hasNoPoster && maxS < 50 && pop < 1) {
        scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop))
      }
    }

    // 3. 处理人物/演职员结果
    for personItem in persons {
      let candidates =
        ([personItem.name, personItem.latin_name, personItem.original_name]
        + (personItem.also_known_as ?? []))
        .compactMap { $0 }
        .filter { !$0.isEmpty }

      let maxS =
        Set(candidates).map { fuzzyMatchScore(text: $0, query: submittedQuery) }.max() ?? -1
      let pop = personItem.popularity ?? 0
      let hasNoPoster = personItem.profile_path == nil || personItem.profile_path?.isEmpty == true

      if !(hasNoPoster && maxS < 50 && pop < 1) {
        scoredItems.append((item: .person(personItem), score: maxS, popularity: pop))
      }
    }

    // 4. 处理订阅分享结果
    for shareItem in shares {
      // share_title 已经映射到 title, count 映射到 popularity
      // comment 和 user 已经组合在 overview 中，这里暂不参与评分
      let titles = [shareItem.title, shareItem.original_title].compactMap { $0 }.filter {
        !$0.isEmpty
      }
      let maxS = Set(titles).map { fuzzyMatchScore(text: $0, query: submittedQuery) }.max() ?? -1
      let pop = shareItem.popularity ?? 0  // 复用次数
      let hasNoPoster = shareItem.poster_path == nil || shareItem.poster_path?.isEmpty == true

      // 分享结果通常比较优质，放宽准入
      if !(hasNoPoster && maxS < 0) {
        scoredItems.append((item: .media(shareItem), score: maxS, popularity: pop))
      }
    }

    // 核心排序逻辑：优先按匹配分值倒序，分值相同时按热度 (Popularity) 倒序
    scoredItems.sort {
      if $0.score != $1.score {
        return $0.score > $1.score
      }
      return $0.popularity > $1.popularity
    }

    // 取前 12 个结果，并根据 ID 去重
    var uniqueItems: [BestResultItem] = []
    var seenIds = Set<String>()
    for entry in scoredItems {
      if !seenIds.contains(entry.item.id) {
        seenIds.insert(entry.item.id)
        uniqueItems.append(entry.item)
        if uniqueItems.count == 12 { break }
      }
    }

    return uniqueItems
  }

  @Published var isLoading = false
  @Published var searchType: SearchType = .unified

  @Published var resourceResults: [Context] = []
  @Published var siteFilter = SiteFilterViewModel()

  private let apiService = APIService.shared
  private var cancellables = Set<AnyCancellable>()
  private var moviePaginatorCancellable: AnyCancellable?
  private var tvPaginatorCancellable: AnyCancellable?
  private var collectionPaginatorCancellable: AnyCancellable?
  private var personPaginatorCancellable: AnyCancellable?
  private var subscriptionSharePaginatorCancellable: AnyCancellable?

  private var sharedMediaFetcher: SharedMediaFetcher?

  /// 执行初始搜索：根据 searchType 决定是资源搜索还是聚合元数据搜索
  func autoSearch() async {
    guard !query.isEmpty else { return }
    isLoading = true
    hasSearched = false
    submittedQuery = query

    do {
      switch searchType {
      case .resource:
        // 资源搜索：查询站点种子信息
        let sitesStr = siteFilter.sitesString
        let results = try await apiService.searchResources(keyword: query, sites: sitesStr)
        self.resourceResults = results

      case .unified:
        // 聚合搜索：创建代理 Fetcher 和 Paginators
        setupPaginators(query: submittedQuery)

        guard let moviePag = moviePaginator,
          let tvPag = tvPaginator,
          let collectionPag = collectionPaginator,
          let personPag = personPaginator,
          let sharePag = subscriptionSharePaginator
        else { break }

        // 并发刷新所有分页器
        let movieTask = Task { @MainActor in await moviePag.refresh() }
        let tvTask = Task { @MainActor in await tvPag.refresh() }
        let collectionTask = Task { @MainActor in await collectionPag.refresh() }
        let personTask = Task { @MainActor in await personPag.refresh() }
        let shareTask = Task { @MainActor in await sharePag.refresh() }
        _ = await (
          movieTask.value, tvTask.value, collectionTask.value, personTask.value, shareTask.value)

        // 基于第一页的结果计算"最佳结果"
        // 由于 media 是电影+电视剧的混合，我们需要把它们组合起来传递
        self.bestResults = calculateBestResults(
          media: moviePag.items + tvPag.items,
          collections: collectionPag.items,
          persons: personPag.items,
          shares: sharePag.items
        )
      }
    } catch {
      print("搜索请求失败: \(error)")
    }
    isLoading = false
    hasSearched = true
  }

  // MARK: - Paginator 创建

  /// 为当前搜索词创建代理和各个 Paginator
  private func setupPaginators(query: String) {
    let fetcher = SharedMediaFetcher(query: query, apiService: apiService)
    self.sharedMediaFetcher = fetcher

    // --- Movie Paginator ---
    var movieSeenKeys = Set<String>()
    let newMoviePaginator = Paginator<MediaInfo>(
      threshold: 7,
      fetcher: { @MainActor [fetcher] _ in
        try await fetcher.fetchMovies()
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &movieSeenKeys)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      onReset: { @MainActor in movieSeenKeys.removeAll() }
    )

    // --- TV Paginator ---
    var tvSeenKeys = Set<String>()
    let newTvPaginator = Paginator<MediaInfo>(
      threshold: 7,
      fetcher: { @MainActor [fetcher] _ in
        try await fetcher.fetchTVShows()
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &tvSeenKeys)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      onReset: { @MainActor in tvSeenKeys.removeAll() }
    )

    // --- Collection Paginator ---
    var collectionSeenKeys = Set<String>()
    let newCollectionPaginator = Paginator<MediaInfo>(
      threshold: 10,
      fetcher: { @MainActor [apiService] page in
        try await apiService.searchCollection(query: query, page: page)
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &collectionSeenKeys)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      onReset: { @MainActor in
        collectionSeenKeys.removeAll()
      }
    )

    // --- Person Paginator ---
    let newPersonPaginator = Paginator<Person>(
      threshold: 10,
      fetcher: { @MainActor [apiService] page in
        try await apiService.searchPerson(query: query, page: page)
      },
      processor: { @MainActor currentItems, newItems in
        // 基于 raw_id 去重
        let existingIds = Set(currentItems.compactMap { $0.raw_id })
        let uniqueNewItems = newItems.filter {
          $0.raw_id == nil || !existingIds.contains($0.raw_id!)
        }
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      }
    )

    // --- Subscription Share Paginator ---
    var shareSeenKeys = Set<String>()
    let newSubscriptionSharePaginator = Paginator<MediaInfo>(
      threshold: 10,
      fetcher: { @MainActor [apiService] page in
        // 获取原始数据
        let shareItems = try await apiService.searchSubscriptionShares(query: query, page: page)
        // 转换为 MediaInfo
        return shareItems.map { $0.toMediaInfo() }
      },
      processor: { @MainActor currentItems, newItems in
        // 使用 MediaInfo 的去重逻辑
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &shareSeenKeys)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      onReset: { @MainActor in
        shareSeenKeys.removeAll()
      }
    )

    // 设置 Paginator 实例
    self.moviePaginator = newMoviePaginator
    self.tvPaginator = newTvPaginator
    self.collectionPaginator = newCollectionPaginator
    self.personPaginator = newPersonPaginator
    self.subscriptionSharePaginator = newSubscriptionSharePaginator

    // 桥接：paginator 内部变化 → ViewModel.objectWillChange
    moviePaginatorCancellable = newMoviePaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
    tvPaginatorCancellable = newTvPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
    collectionPaginatorCancellable = newCollectionPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
    personPaginatorCancellable = newPersonPaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
    subscriptionSharePaginatorCancellable = newSubscriptionSharePaginator.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
  }

  func mapMediaToSubscribe(_ media: MediaInfo) -> Subscribe {
    return Subscribe(
      id: nil,
      name: media.title ?? "",
      year: media.year,
      type: media.type ?? "电影",
      keyword: nil,
      season: media.season,
      poster: media.poster_path,
      state: "N",
      last_update: nil,
      total_episode: nil,
      start_episode: nil,
      lack_episode: nil,
      tmdbid: media.tmdb_id,
      doubanid: media.douban_id,
      bangumiid: media.bangumi_id,
      quality: nil,
      resolution: nil,
      effect: nil,
      include: nil,
      exclude: nil,
      sites: nil,
      downloader: nil,
      save_path: nil,
      best_version: nil,
      filter_groups: nil,
      custom_words: nil
    )
  }
}

// MARK: - 共享分页抓取代理

/// 负责统筹抓取 `searchMedia` API，并按需拆分给各自分页器
actor SharedMediaFetcher {
  private let query: String
  private let apiService: APIService

  private var apiPage: Int = 0
  private var hasMore: Bool = true
  private var movieBuffer: [MediaInfo] = []
  private var tvBuffer: [MediaInfo] = []

  private var currentFetchTask: Task<Void, Error>?

  init(query: String, apiService: APIService) {
    self.query = query
    self.apiService = apiService
  }

  func fetchMovies() async throws -> [MediaInfo] {
    try await fetchUntil(targetType: "电影")
  }

  func fetchTVShows() async throws -> [MediaInfo] {
    try await fetchUntil(targetType: "电视剧")
  }

  private func fetchUntil(targetType: String) async throws -> [MediaInfo] {
    let minTargetCount = 8
    var fetchCount = 0
    let maxFetchCount = 5  // 每次最多查 5 页，避免遇到极端数据时死锁

    while getBufferCount(for: targetType) < minTargetCount && hasMore && fetchCount < maxFetchCount
    {
      let currentPage = apiPage
      try await fetchNextApiPage()
      if apiPage > currentPage {
        fetchCount += 1
      } else {
        // 请求失败或者到底了
        break
      }
    }

    return extractAllFromBuffer(for: targetType)
  }

  private func getBufferCount(for type: String) -> Int {
    type == "电影" ? movieBuffer.count : tvBuffer.count
  }

  private func extractAllFromBuffer(for type: String) -> [MediaInfo] {
    if type == "电影" {
      let result = movieBuffer
      movieBuffer.removeAll()
      return result
    } else {
      let result = tvBuffer
      tvBuffer.removeAll()
      return result
    }
  }

  private func fetchNextApiPage() async throws {
    if let task = currentFetchTask {
      try await task.value
      return
    }

    let localPage = apiPage + 1
    let isInitialFetch = (apiPage == 0)

    let task = Task {
      if isInitialFetch {
        // 首次搜索时，并发获取前两页，大幅度提升混排首屏加载速度
        async let fetchPage1 = apiService.searchMedia(query: query, page: 1)
        async let fetchPage2 = apiService.searchMedia(query: query, page: 2)

        let (page1Items, page2Items) = try await (fetchPage1, fetchPage2)
        let allItems = page1Items + page2Items

        self.appendAllItems(allItems)

        self.apiPage = 2
        if page1Items.isEmpty || page2Items.isEmpty {
          self.hasMore = false
        }
      } else {
        let newItems = try await apiService.searchMedia(query: query, page: localPage)

        if newItems.isEmpty {
          self.hasMore = false
        } else {
          self.appendAllItems(newItems)
          self.apiPage = localPage
        }
      }
    }

    self.currentFetchTask = task
    defer { self.currentFetchTask = nil }
    try await task.value
  }

  private func appendAllItems(_ items: [MediaInfo]) {
    for item in items {
      if item.type == "电影" {
        self.movieBuffer.append(item)
      } else if item.type == "电视剧" {
        self.tvBuffer.append(item)
      }
    }
  }
}
