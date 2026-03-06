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

  if t == q { return 1000 } // 完全相等
  if t.hasPrefix(q) { return 500 - t.count } // 前缀匹配（标题越短权重越高）
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
  @Published var submittedQuery: String = "" // 记录点击搜索时的关键词，用于分页请求
  @Published var hasSearched: Bool = false
  @Published var resourceResults: [Context] = []
  @Published var mediaResults: [MediaInfo] = []
  @Published var collectionResults: [MediaInfo] = []
  @Published var personResults: [Person] = []

  var movieResults: [MediaInfo] {
    mediaResults.filter { $0.type == "电影" }
  }

  var tvResults: [MediaInfo] {
    mediaResults.filter { $0.type == "电视剧" }
  }

  @Published var bestResults: [BestResultItem] = []

  /// 核心逻辑：从所有搜索结果中筛选出“最佳匹配”项
  /// 规则：结合标题模糊匹配分值和媒体流行度 (Popularity)
  private func calculateBestResults(
    media: [MediaInfo],
    collections: [MediaInfo],
    persons: [Person]
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

  // 分页状态管理 - 每个类别独立，支持无限滚动
  @Published var mediaCurrentPage = 1
  @Published var mediaHasMore = true
  @Published var mediaIsLoadingMore = false
  private var mediaDetectedPageSize: Int?

  @Published var collectionCurrentPage = 1
  @Published var collectionHasMore = true
  @Published var collectionIsLoadingMore = false
  private var collectionDetectedPageSize: Int?

  @Published var personCurrentPage = 1
  @Published var personHasMore = true
  @Published var personIsLoadingMore = false
  private var personDetectedPageSize: Int?

  @Published var siteFilter = SiteFilterViewModel()

  private let apiService = APIService.shared
  private var mediaSeenKeys = Set<String>()
  private var collectionSeenKeys = Set<String>()

  /// 执行初始搜索：根据 searchType 决定是资源搜索还是聚合元数据搜索
  func autoSearch() async {
    guard !query.isEmpty else { return }
    isLoading = true
    hasSearched = false
    submittedQuery = query

    // 重置各类型的分页状态
    mediaCurrentPage = 1
    mediaHasMore = true
    mediaDetectedPageSize = nil
    collectionCurrentPage = 1
    collectionHasMore = true
    collectionDetectedPageSize = nil
    personCurrentPage = 1
    personHasMore = true
    personDetectedPageSize = nil

    // 清空上一次的搜索结果
    self.resourceResults = []
    self.mediaResults = []
    self.collectionResults = []
    self.personResults = []

    do {
      switch searchType {
      case .resource:
        // 资源搜索：查询站点种子信息
        let sitesStr = siteFilter.sitesString
        let results = try await apiService.searchResources(keyword: query, sites: sitesStr)
        self.resourceResults = results

      case .unified:
        // 聚合搜索：并发向后端请求媒体、合集、演职人员
        async let mediaTask = apiService.searchMedia(query: query, page: 1)
        async let collectionTask = apiService.searchCollection(query: query, page: 1)
        async let personTask = apiService.searchPerson(query: query, page: 1)

        let (media, collections, persons) = try await (mediaTask, collectionTask, personTask)
        
        // 元数据去重并保存
        mediaSeenKeys.removeAll()
        collectionSeenKeys.removeAll()
        self.mediaResults = MediaInfo.deduplicate(media, existingKeys: &mediaSeenKeys)
        self.collectionResults = MediaInfo.deduplicate(
          collections, existingKeys: &collectionSeenKeys)
        self.personResults = persons

        // 基于第一页的结果计算“最佳结果”，后续分页不再重新刷新此版块
        self.bestResults = calculateBestResults(
          media: self.mediaResults,
          collections: self.collectionResults,
          persons: self.personResults
        )

        // 自动检测分页大小，如果返回数量小于检测到的单页上限，则标记没有更多
        if media.isEmpty { mediaHasMore = false } else { mediaDetectedPageSize = media.count }
        if collections.isEmpty {
          collectionHasMore = false
        } else {
          collectionDetectedPageSize = collections.count
        }
        if persons.isEmpty { personHasMore = false } else { personDetectedPageSize = persons.count }
      }
    } catch {
      print("搜索请求失败: \(error)")
    }
    isLoading = false
    hasSearched = true
  }

  // MARK: - 分页加载逻辑 (Load More)

  func loadMoreMedia() async {
    guard !mediaIsLoadingMore, mediaHasMore, !submittedQuery.isEmpty else { return }

    mediaIsLoadingMore = true
    mediaCurrentPage += 1

    do {
      let results = try await apiService.searchMedia(query: submittedQuery, page: mediaCurrentPage)
      if results.isEmpty {
        mediaHasMore = false
      } else {
        if let pageSize = mediaDetectedPageSize, results.count < pageSize {
          mediaHasMore = false
        }
        // 使用 dedupKey 追加去重
        let newItems = MediaInfo.deduplicate(results, existingKeys: &mediaSeenKeys)
        mediaResults.append(contentsOf: newItems)
      }
    } catch {
      print("加载更多媒体失败: \(error)")
      mediaCurrentPage -= 1
    }

    mediaIsLoadingMore = false
  }

  func loadMoreCollections() async {
    guard !collectionIsLoadingMore, collectionHasMore, !submittedQuery.isEmpty else { return }

    collectionIsLoadingMore = true
    collectionCurrentPage += 1

    do {
      let results = try await apiService.searchCollection(
        query: submittedQuery, page: collectionCurrentPage)
      if results.isEmpty {
        collectionHasMore = false
      } else {
        if let pageSize = collectionDetectedPageSize, results.count < pageSize {
          collectionHasMore = false
        }
        let newItems = MediaInfo.deduplicate(results, existingKeys: &collectionSeenKeys)
        collectionResults.append(contentsOf: newItems)
      }
    } catch {
      print("加载更多系列失败: \(error)")
      collectionCurrentPage -= 1
    }

    collectionIsLoadingMore = false
  }

  func loadMorePersons() async {
    guard !personIsLoadingMore, personHasMore, !submittedQuery.isEmpty else { return }

    personIsLoadingMore = true
    personCurrentPage += 1

    do {
      let results = try await apiService.searchPerson(
        query: submittedQuery, page: personCurrentPage)
      if results.isEmpty {
        personHasMore = false
      } else {
        if let pageSize = personDetectedPageSize, results.count < pageSize {
          personHasMore = false
        }
        // 基于 person_id 手动去重
        let existingIds = Set(personResults.compactMap { $0.raw_id })
        let newItems = results.filter {
          $0.raw_id == nil || !existingIds.contains($0.raw_id!)
        }
        personResults.append(contentsOf: newItems)
      }
    } catch {
      print("加载更多人物失败: \(error)")
      personCurrentPage -= 1
    }

    personIsLoadingMore = false
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
