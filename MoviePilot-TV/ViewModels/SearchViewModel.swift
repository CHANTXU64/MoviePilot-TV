import Combine
import Foundation
import SwiftUI

enum SearchType: String, CaseIterable, Identifiable {
  case unified = "聚合搜索"
  case resource = "资源搜索"
  var id: String { self.rawValue }
}

nonisolated enum MetadataSearchKind: Sendable {
  case media
  case collection
  case person
}

nonisolated enum MediaSearchSource: String, CaseIterable, Identifiable, Hashable, Sendable {
  case themoviedb
  case douban
  case bangumi
  case anilist

  var id: String { rawValue }

  var title: String {
    switch self {
    case .themoviedb: "TMDB"
    case .douban: "豆瓣"
    case .bangumi: "Bangumi"
    case .anilist: "AniList"
    }
  }

  static func allowed(for kind: MetadataSearchKind) -> [MediaSearchSource] {
    switch kind {
    case .media: [.themoviedb, .douban, .bangumi, .anilist]
    case .collection: [.themoviedb]
    case .person: [.themoviedb, .douban]
    }
  }
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
  @Published var mediaSearchSource: MediaSearchSource?

  var mediaSourceButtonLabel: String {
    mediaSearchSource?.title ?? "默认"
  }

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

    // 当搜索词包含年份时，生成去掉年份的纯标题查询词
    // 用于双重匹配：既匹配完整搜索词，也匹配纯标题，取最高分
    // 这确保了即使结果缺少 year 字段（如合集），标题仍能获得合理匹配分
    let queryWithoutYear: String? = queryYear.map {
      submittedQuery.replacingOccurrences(of: $0, with: "")
        .trimmingCharacters(in: .whitespaces)
    }

    // 计算候选标题集合的最佳匹配分值
    // allowYearFallback: 仅在年份匹配或无年份时，才允许使用无年份搜索词进行回退匹配
    // 避免年份不匹配的媒体项通过回退获得虚假高分
    let query = submittedQuery
    let bestScore: (Set<String>, Bool) -> Int = { candidates, allowYearFallback in
      candidates.map { candidate in
        let s1 = fuzzyMatchScore(text: candidate, query: query)
        guard allowYearFallback, let qNoYear = queryWithoutYear else { return s1 }
        return max(s1, fuzzyMatchScore(text: candidate, query: qNoYear))
      }.max() ?? -1
    }

    var scoredItems: [(item: BestResultItem, score: Int, popularity: Double)] = []

    // 1. 处理媒体搜索结果 (电影/电视剧)
    for mediaItem in media {
      let titles =
        ([mediaItem.title, mediaItem.original_title, mediaItem.original_name]
        + (mediaItem.names ?? []))
        .compactMap { $0 }
        .filter { !$0.isEmpty }

      var candidates = titles
      let yearMatches: Bool = {
        guard let qYear = queryYear else { return true }
        guard let mYear = mediaItem.year else { return true }
        return mYear.contains(qYear)
      }()
      if let qYear = queryYear, let mYear = mediaItem.year, mYear.contains(qYear) {
        let withYear = titles.map { "\($0) \(qYear)" }
        candidates.append(contentsOf: withYear)
      }

      let maxS = bestScore(Set(candidates), yearMatches)
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
      let yearMatches: Bool = {
        guard let qYear = queryYear else { return true }
        guard let mYear = mediaItem.year else { return true }
        return mYear.contains(qYear)
      }()
      if let qYear = queryYear, let mYear = mediaItem.year, mYear.contains(qYear) {
        let withYear = titles.map { "\($0) \(qYear)" }
        candidates.append(contentsOf: withYear)
      }

      let maxS = bestScore(Set(candidates), yearMatches)
      let pop = mediaItem.popularity ?? 0
      let hasNoPoster = mediaItem.poster_path == nil || mediaItem.poster_path?.isEmpty == true

      if !(hasNoPoster && maxS < 50 && pop < 1) {
        scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop))
      }
    }

    // 3. 处理人物/演职员结果（人物无年份概念，始终允许回退）
    for personItem in persons {
      let candidates =
        ([personItem.name, personItem.latin_name, personItem.original_name]
        + (personItem.also_known_as ?? []))
        .compactMap { $0 }
        .filter { !$0.isEmpty }

      let maxS = bestScore(Set(candidates), true)
      let pop = personItem.popularity ?? 0
      let hasNoPoster = personItem.profile_path == nil || personItem.profile_path?.isEmpty == true

      if !(hasNoPoster && maxS < 50 && pop < 1) {
        scoredItems.append((item: .person(personItem), score: maxS, popularity: pop))
      }
    }

    // 4. 处理订阅分享结果（分享无年份概念，始终允许回退）
    for shareItem in shares {
      // share_title 已经映射到 title, count 映射到 popularity
      // comment 和 user 已经组合在 overview 中，这里暂不参与评分
      let titles = [shareItem.title, shareItem.original_title].compactMap { $0 }.filter {
        !$0.isEmpty
      }
      let maxS = bestScore(Set(titles), true)
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

  var availableSearchTypes: [SearchType] {
    SearchType.allCases.filter(canAccess)
  }

  @Published var resourceResults: [Context] = []
  @Published var appliedFilterRuleName: String?
  @Published var siteFilter: SiteFilterViewModel

  private let apiService: APIService
  private var cancellables = Set<AnyCancellable>()
  private var moviePaginatorCancellable: AnyCancellable?
  private var tvPaginatorCancellable: AnyCancellable?
  private var collectionPaginatorCancellable: AnyCancellable?
  private var personPaginatorCancellable: AnyCancellable?
  private var subscriptionSharePaginatorCancellable: AnyCancellable?

  private var sharedMediaFetcher: SharedMediaFetcher?
  private var searchStreamTask: Task<Void, Never>?
  private var searchGeneration: Int = 0
  private let searchStreamDoneCloseDelay: UInt64 = 1_500_000_000
  
  @Published var searchProgressText: String = ""
  @Published var searchProgress: Double = 0.0
  @Published var resourceErrorMessage: String?

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    self.siteFilter = SiteFilterViewModel(apiService: apiService)
    self.mediaSearchSource = SystemViewModel.currentDefaultMediaSearchSource(apiService: apiService)
    self.siteFilter.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  /// 执行初始搜索：根据 searchType 决定是资源搜索还是聚合元数据搜索
  func autoSearch() async {
    guard !query.isEmpty else { return }
    let currentSearchType = searchType
    guard canAccess(currentSearchType) else { return }
    searchGeneration += 1
    let currentSearchGeneration = searchGeneration
    let searchQuery = query
    let sessionSnapshot = apiService.sessionSnapshot()
    
    searchStreamTask?.cancel()
    
    isLoading = true
    hasSearched = false
    submittedQuery = searchQuery

    switch currentSearchType {
    case .resource:
      // 资源搜索：查询站点种子信息
      let sitesStr = siteFilter.sitesString
      searchProgressText = "正在搜索..."
      searchProgress = 0.0
      resourceErrorMessage = nil
      // 新搜索开始即清空旧结果，避免新搜索失败或响应在途时旧结果冒充新结果并可被操作。
      resourceResults = []
      
      searchStreamTask = Task { @MainActor in
        var accumulatedResults: [Context] = []
        var finalResultApplied = false
        // 只有收到端点认可的 done 才把结果按成功收尾发布；业务 error 与无终止 EOF 均不发布。
        var receivedDone = false
        defer {
          self.finishSearchIfCurrent(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType
          )
        }
        
        do {
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }

          let stream = apiService.searchTitleStream(keyword: searchQuery, sites: sitesStr)
          
          for try await event in stream {
            guard canPublishSearchResult(
              generation: currentSearchGeneration,
              sessionSnapshot: sessionSnapshot,
              searchType: currentSearchType)
            else { return }
            
            if let text = event.text_i18n ?? event.text {
              self.searchProgressText = text
            }
            if let value = event.value {
              self.searchProgress = value
            }
            
            event.applyResourceItems(
              to: &accumulatedResults,
              finalResultApplied: &finalResultApplied
            )
            
            if event.type == "error" {
              self.resourceErrorMessage =
                event.localizedMessage ?? "未找到相关资源"
              // 整次搜索失败：不发布已积累的部分结果。
              return
            }
            
            if event.type == "done" {
              receivedDone = true
              // 与 Web v2.13.2 保持一致：给后端搜索结果缓存写入留出收尾时间。
              try? await Task.sleep(nanoseconds: searchStreamDoneCloseDelay)
              guard canPublishSearchResult(
                generation: currentSearchGeneration,
                sessionSnapshot: sessionSnapshot,
                searchType: currentSearchType)
              else { return }
              break
            }
          }
          
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }
          // EOF 未收到 done 视为连接异常，不把部分结果按成功收尾发布。
          guard receivedDone else {
            throw URLError(.networkConnectionLost)
          }

          // 应用自定义过滤规则（规则内容非法时显式提示；拉取规则网络失败时放行不过滤）
          let filteredResults: [Context]
          do {
            filteredResults = try await self.applyCustomFilter(to: accumulatedResults)
          } catch let error as CustomFilterService.FilterError {
            guard canPublishSearchResult(
              generation: currentSearchGeneration,
              sessionSnapshot: sessionSnapshot,
              searchType: currentSearchType)
            else { return }
            self.resourceErrorMessage = error.localizedDescription
            return
          } catch {
            print("❌ [SearchVM] 加载过滤规则失败，放行不过滤: \(error)")
            filteredResults = accumulatedResults
          }
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }

          self.resourceResults = filteredResults
        } catch {
          print("Stream Search error: \(error)")
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }

          do {
            var fallbackResults = try await self.apiService.searchResources(
              keyword: searchQuery,
              sites: sitesStr
            )
            guard canPublishSearchResult(
              generation: currentSearchGeneration,
              sessionSnapshot: sessionSnapshot,
              searchType: currentSearchType)
            else { return }

            do {
              fallbackResults = try await self.applyCustomFilter(to: fallbackResults)
            } catch let error as CustomFilterService.FilterError {
              self.resourceErrorMessage = error.localizedDescription
              return
            } catch {
              print("❌ [SearchVM] 加载过滤规则失败，放行不过滤: \(error)")
            }
            guard canPublishSearchResult(
              generation: currentSearchGeneration,
              sessionSnapshot: sessionSnapshot,
              searchType: currentSearchType)
            else { return }

            self.resourceResults = fallbackResults
          } catch {
            print("Fallback Search error: \(error)")
            self.resourceErrorMessage = error.localizedDescription
          }
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }
        }
      }
      return

    case .unified:
      defer {
        finishSearchIfCurrent(
          generation: currentSearchGeneration,
          sessionSnapshot: sessionSnapshot,
          searchType: currentSearchType
        )
      }
      // 聚合搜索：新搜索开始即清空旧最佳结果，避免请求在途或失败时旧结果冒充新结果（与资源搜索分支对齐）。
      self.bestResults = []
      // 创建代理 Fetcher 和 Paginators
      setupPaginators(query: submittedQuery)

      guard let moviePag = moviePaginator,
        let tvPag = tvPaginator,
        let collectionPag = collectionPaginator,
        let personPag = personPaginator
      else { break }
      let sharePag = subscriptionSharePaginator

      // 并发刷新所有分页器
      let movieTask = Task { @MainActor in await moviePag.refresh() }
      let tvTask = Task { @MainActor in await tvPag.refresh() }
      let collectionTask = Task { @MainActor in await collectionPag.refresh() }
      let personTask = Task { @MainActor in await personPag.refresh() }
      let shareTask = sharePag.map { paginator in
        Task { @MainActor in await paginator.refresh() }
      }
      _ = await (
        movieTask.value, tvTask.value, collectionTask.value, personTask.value
      )
      await shareTask?.value
      guard canPublishSearchResult(
        generation: currentSearchGeneration,
        sessionSnapshot: sessionSnapshot,
        searchType: currentSearchType)
      else { return }

      // 基于第一页的结果计算"最佳结果"
      // 由于 media 是电影+电视剧的混合，我们需要把它们组合起来传递
      self.bestResults = calculateBestResults(
        media: moviePag.items + tvPag.items,
        collections: collectionPag.items,
        persons: personPag.items,
        shares: sharePag?.items ?? []
      )
    }
  }

  private func finishSearchIfCurrent(
    generation: Int,
    sessionSnapshot: APIServiceSessionSnapshot,
    searchType: SearchType
  ) {
    guard searchGeneration == generation else { return }
    isLoading = false
    searchStreamTask = nil
    hasSearched = !Task.isCancelled
      && apiService.isSessionUnchanged(from: sessionSnapshot)
      && self.searchType == searchType
      && canAccess(searchType)
  }

  private func canPublishSearchResult(
    generation: Int,
    sessionSnapshot: APIServiceSessionSnapshot,
    searchType: SearchType
  ) -> Bool {
    searchGeneration == generation
      && !Task.isCancelled
      && apiService.isSessionUnchanged(from: sessionSnapshot)
      && self.searchType == searchType
      && canAccess(searchType)
  }

  func normalizeSearchTypeForPermissions() {
    guard !canAccess(searchType), let firstAvailable = availableSearchTypes.first else { return }
    searchType = firstAvailable
  }

  private func canAccess(_ searchType: SearchType) -> Bool {
    switch searchType {
    case .unified:
      apiService.canAccess(.discovery)
    case .resource:
      apiService.canAccess(.search)
    }
  }

  // MARK: - Paginator 创建

  /// 为当前搜索词创建代理和各个 Paginator
  private func setupPaginators(query: String) {
    resetPaginators()

    let selectedSource = mediaSearchSource
    let fetcher = SharedMediaFetcher(
      query: query,
      source: selectedSource,
      apiService: apiService
    )
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
      imageURLsProvider: { item in
        [item.imageURLs.poster].compactMap(\.self)
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
      imageURLsProvider: { @MainActor item in
        [item.imageURLs.poster].compactMap { $0 }
      },
      onReset: { @MainActor in tvSeenKeys.removeAll() }
    )

    // --- Collection Paginator ---
    var collectionSeenKeys = Set<String>()
    let newCollectionPaginator = Paginator<MediaInfo>(
      threshold: 10,
      fetcher: { @MainActor [apiService] page in
        if let selectedSource,
          !MediaSearchSource.allowed(for: .collection).contains(selectedSource)
        {
          return []
        }
        return try await apiService.searchCollection(
          query: query,
          page: page,
          source: selectedSource
        )
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &collectionSeenKeys)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      imageURLsProvider: { @MainActor item in
        [item.imageURLs.poster].compactMap { $0 }
      },
      onReset: { @MainActor in
        collectionSeenKeys.removeAll()
      }
    )

    // --- Person Paginator ---
    var personSeenIDs = Set<String>()
    let newPersonPaginator = Paginator<Person>(
      threshold: 10,
      fetcher: { @MainActor [apiService] page in
        if let selectedSource,
          !MediaSearchSource.allowed(for: .person).contains(selectedSource)
        {
          return []
        }
        return try await apiService.searchPerson(
          query: query,
          page: page,
          source: selectedSource
        )
      },
      processor: { @MainActor currentItems, newItems in
        let uniqueNewItems = Person.deduplicate(newItems, existingIDs: &personSeenIDs)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      imageURLsProvider: { item in
        [item.imageURLs.profile].compactMap(\.self)
      },
      onReset: { @MainActor in personSeenIDs.removeAll() }
    )

    var newSubscriptionSharePaginator: Paginator<MediaInfo>?
    if apiService.canAccess(.subscribe) {
      var shareSeenKeys = Set<String>()
      newSubscriptionSharePaginator = Paginator<MediaInfo>(
        threshold: 10,
        fetcher: { @MainActor [apiService] page in
          let shareItems = try await apiService.searchSubscriptionShares(query: query, page: page)
          return shareItems.map { $0.toMediaInfo() }
        },
        processor: { @MainActor currentItems, newItems in
          let uniqueNewItems = MediaInfo.deduplicateSubscriptionShareMedia(
            newItems,
            existingKeys: &shareSeenKeys
          )
          if uniqueNewItems.isEmpty { return false }
          currentItems.append(contentsOf: uniqueNewItems)
          return true
        },
        imageURLsProvider: { item in
          [item.imageURLs.poster].compactMap(\.self)
        },
        onReset: { @MainActor in
          shareSeenKeys.removeAll()
        }
      )
    }

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
    subscriptionSharePaginatorCancellable = newSubscriptionSharePaginator?.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
  }

  private func resetPaginators() {
    moviePaginator?.cancel()
    tvPaginator?.cancel()
    collectionPaginator?.cancel()
    personPaginator?.cancel()
    subscriptionSharePaginator?.cancel()

    moviePaginatorCancellable?.cancel()
    tvPaginatorCancellable?.cancel()
    collectionPaginatorCancellable?.cancel()
    personPaginatorCancellable?.cancel()
    subscriptionSharePaginatorCancellable?.cancel()

    sharedMediaFetcher = nil
    moviePaginator = nil
    tvPaginator = nil
    collectionPaginator = nil
    personPaginator = nil
    subscriptionSharePaginator = nil
    moviePaginatorCancellable = nil
    tvPaginatorCancellable = nil
    collectionPaginatorCancellable = nil
    personPaginatorCancellable = nil
    subscriptionSharePaginatorCancellable = nil
  }

  func mapMediaToSubscribe(_ media: MediaInfo) -> Subscribe {
    return Subscribe(
      id: nil,
      name: media.title ?? "",
      year: media.year,
      type: media.type ?? "电影",
      season: media.season,
      poster: media.poster_path,
      state: "N",
      last_update: nil,
      tmdbid: media.tmdb_id,
      doubanid: media.douban_id,
      bangumiid: media.bangumi_id,
      anilistid: media.anilist_id,
      media_source: media.identity?.source,
      media_id: media.identity?.mediaId,
      best_version: nil,
      keyword: nil,
      total_episode: nil,
      start_episode: nil,
      lack_episode: nil,
      quality: nil,
      resolution: nil,
      effect: nil,
      include: nil,
      exclude: nil,
      sites: nil,
      downloader: nil,
      save_path: nil,
      filter_groups: nil,
      custom_words: nil,
      mediaid: media.apiMediaId
    )
  }

  // MARK: - 自定义过滤规则

  /// 应用自定义过滤规则
  private func applyCustomFilter(to contexts: [Context]) async throws -> [Context] {
    try await CustomFilterService.applyHardAndSoftFilter(
      to: contexts, using: apiService, caller: "SearchVM")
  }
}

// MARK: - 共享分页抓取代理

/// 负责统筹抓取 `searchMedia` API，并按需拆分给各自分页器
actor SharedMediaFetcher {
  private let query: String
  private let source: MediaSearchSource?
  private let apiService: APIService

  private var apiPage: Int = 0
  private var hasMore: Bool = true
  private var movieBuffer: [MediaInfo] = []
  private var tvBuffer: [MediaInfo] = []

  private var currentFetchTask: Task<Void, Error>?

  init(query: String, source: MediaSearchSource?, apiService: APIService) {
    self.query = query
    self.source = source
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
        async let fetchPage1 = apiService.searchMedia(query: query, page: 1, source: source)
        async let fetchPage2 = apiService.searchMedia(query: query, page: 2, source: source)

        let (page1Items, page2Items) = try await (fetchPage1, fetchPage2)
        let allItems = page1Items + page2Items

        self.appendAllItems(allItems)

        self.apiPage = 2
        if page1Items.isEmpty || page2Items.isEmpty {
          self.hasMore = false
        }
      } else {
        let newItems = try await apiService.searchMedia(
          query: query,
          page: localPage,
          source: source
        )

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
