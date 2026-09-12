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
/// 原理：全匹配最高，前缀匹配次之，包含匹配再次，最后是按顺序出现的字符匹配。
/// 类别带宽互不重叠且长度罚分有上限，避免长标题的真实匹配被弱匹配挤出。
func fuzzyMatchScore(text: String?, query: String) -> Int {
  guard let t = text?.lowercased(), !query.isEmpty else { return -1 }
  let q = query.lowercased()

  if t == q { return 1000 }  // 完全相等
  if t.hasPrefix(q) { return 700 - min(t.count, 100) }  // 前缀匹配（标题越短权重越高，罚分封顶）
  if t.contains(q) { return 400 - min(t.count, 100) }  // 包含匹配

  // 字符顺序匹配（如搜索 "hml" 匹配 "Hamilton"），采用 fzf 风格加分
  return subsequenceMatchScore(text: t, query: q)
}

/// 顺序匹配打分：匹配字符越靠词首、越连续得分越高，间隔与长度惩罚有界。
/// 结果区间 [100, 299]，始终高于“不匹配(-1)”、低于“包含匹配”档。
private func subsequenceMatchScore(text: String, query: String) -> Int {
  var queryIndex = query.startIndex
  var previousMatchOffset: Int?
  var bonus = 0
  var gapPenalty = 0
  var offset = 0
  let chars = Array(text)

  for char in chars {
    if char == query[queryIndex] {
      // 词首加分：标题开头或前一个字符是分隔符/标点
      if offset == 0 || !chars[offset - 1].isLetterOrNumber {
        bonus += 24
      }
      if let previous = previousMatchOffset {
        let gap = offset - previous - 1
        if gap == 0 {
          bonus += 12  // 连续匹配
        } else {
          gapPenalty += min(gap * 3, 60)
        }
      }
      previousMatchOffset = offset
      queryIndex = query.index(after: queryIndex)
      if queryIndex == query.endIndex { break }
    }
    offset += 1
  }
  guard queryIndex == query.endIndex else { return -1 }
  return min(max(100 + bonus - gapPenalty - min(text.count, 99), 100), 299)
}

private extension Character {
  var isLetterOrNumber: Bool {
    isLetter || isNumber
  }
}

/// 热度加分：按来源热度口径归一化，避免不同来源量级混算。
/// - TMDB 热度指数（常见 0.5~1900）用 log10 基数 3；
/// - AniList 收藏数（常见数千~数十万）用 log10 基数 6；
/// - 其余来源无热度或口径不可比，返回 0。
func popularityBoost(source: String?, popularity: Double) -> Int {
  guard popularity > 0 else { return 0 }
  let base: Double
  switch source?.lowercased() {
  case "themoviedb": base = 3
  case "anilist": base = 6
  default: return 0
  }
  let normalized = min(log10(1 + popularity) / base, 1)
  return Int((normalized * 149).rounded())
}

@MainActor
class SearchViewModel: ObservableObject {
  @Published var query: String = ""
  @Published var submittedQuery: String = ""  // 记录点击搜索时的关键词，用于分页请求
  @Published var hasSearched: Bool = false
  @Published var mediaSearchSource: MediaSearchSource? {
    didSet {
      guard
        !isApplyingDefaultMediaSearchSource,
        mediaSearchSource != oldValue
      else { return }
      followsDefaultMediaSearchSource = false
    }
  }

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

    // 尝试从搜索词中提取年份 (4位数字)，用于辅助匹配（如搜索 "流浪地球 2019"）。
    //
    // F-141：年份必须**跟前一个分隔符一起匹配**（空白或左括号），与后端
    // `StringUtils.get_keyword` 的 `[\s(]+(\d{4})[\s)]*` 同构。原先用裸 `(19|20)\d{2}`
    // 扫第一个四位串，`1917`、`2001: A Space Odyssey` 这类「数字片名」会被当成搜索年份：
    // 一是把 `1917 (2019)` 的年份认成 1917，使真正的 2019 版《1917》被判为年份不符而
    // 关掉回退、拿不到分；二是剥年份时只删数字、留下 `(2019)` 空壳当查询词。
    // 现在整段（含前导分隔符与尾随右括号）一起删，`1917 (2019)` 干净地还原成 `1917`。
    // 保留 `(19|20)` 前缀约束而不照搬后端的裸 `\d{4}`：年份只用于给候选补 `标题 + 年份`
    // 变体与放宽回退，把 `1234` 之类当成年份只会引入新的误判。
    let yearRegex = try? NSRegularExpression(pattern: "[\\s(]+((?:19|20)\\d{2})[\\s)]*")
    let nsQuery = submittedQuery as NSString
    let yearMatch = yearRegex?.firstMatch(
      in: submittedQuery, range: NSRange(location: 0, length: nsQuery.length))
    // 上式只有一个捕获组，匹配成功时 `range(at: 1)` 必然有效。
    let queryYear: String? = yearMatch.map { nsQuery.substring(with: $0.range(at: 1)) }

    // 当搜索词包含年份时，生成去掉年份的纯标题查询词
    // 用于双重匹配：既匹配完整搜索词，也匹配纯标题，取最高分
    // 这确保了即使结果缺少 year 字段（如合集），标题仍能获得合理匹配分
    //
    // F-141：剥完只剩空串时返回 nil（如查询词本就是 `(2019)`）。
    // 这一条**不改变可观测行为** —— 空串在 `fuzzyMatchScore` 里恒为 -1，
    // 进 `max` 会被原串分值盖掉。收在这里是为了让 `queryWithoutYear` 的含义
    // 是「可用的回退查询词」而不是「可能为空串」。
    let queryWithoutYear: String? = yearMatch.flatMap { match -> String? in
      let remainder = nsQuery.replacingCharacters(in: match.range, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return remainder.isEmpty ? nil : remainder
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

    var scoredItems: [(item: BestResultItem, score: Int, popularity: Double, boost: Int)] = []
    var candidateSources = Set<String>()

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
      let boost = popularityBoost(source: mediaItem.source, popularity: pop)

      // 过滤匹配度极低且无海报的结果，减少噪音
      if !(hasNoPoster && maxS < 50 && pop < 1) {
        if let source = mediaItem.source, !source.isEmpty { candidateSources.insert(source) }
        scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop, boost: boost))
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
      let boost = popularityBoost(source: mediaItem.source, popularity: pop)

      if !(hasNoPoster && maxS < 50 && pop < 1) {
        if let source = mediaItem.source, !source.isEmpty { candidateSources.insert(source) }
        scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop, boost: boost))
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
      // F-055：准入与实际渲染同源。原先读 TMDB 专属 `profile_path`，
      // 会把「有可渲染 avatar 但无 profile_path」的豆瓣等来源人物当成无图低质结果排除，
      // 而同一人仍会出现在下方人物行（卡片用 source-aware 判定能渲染出图）。
      let hasNoProfileImage = !personItem.hasUsableProfileImage
      let boost = popularityBoost(source: personItem.source, popularity: pop)

      if !(hasNoProfileImage && maxS < 50 && pop < 1) {
        if let source = personItem.source, !source.isEmpty { candidateSources.insert(source) }
        scoredItems.append((item: .person(personItem), score: maxS, popularity: pop, boost: boost))
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
      // 订阅分享无真实热度（复用次数与媒体热度口径不同），固定小值参与加权。
      let pop = 0.6
      let hasNoPoster = shareItem.poster_path == nil || shareItem.poster_path?.isEmpty == true
      let boost = popularityBoost(source: "themoviedb", popularity: pop)

      // 分享结果通常比较优质，放宽准入
      if !(hasNoPoster && maxS < 0) {
        scoredItems.append((item: .media(shareItem), score: maxS, popularity: pop, boost: boost))
      }
    }

    // 候选池出现多个媒体来源（订阅分享不计）时热度口径不可比，全部不计算热度。
    if candidateSources.count > 1 {
      scoredItems = scoredItems.map {
        (item: $0.item, score: $0.score, popularity: $0.popularity, boost: 0)
      }
    }

    // 核心排序逻辑：按“匹配分值 + 热度加分”倒序，总分相同时按热度倒序
    scoredItems.sort {
      let lhsTotal = $0.score + $0.boost
      let rhsTotal = $1.score + $1.boost
      if lhsTotal != rhsTotal {
        return lhsTotal > rhsTotal
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

  /// F-044：把搜索人物的 `job` 投影成**当前语言的显示文本**。
  ///
  /// 详情页的职员走 `StaffManager.processCrew` 才翻译职位，而搜索结果这条链路
  /// 完全绕过它 —— `PersonCard` 与最佳结果卡片直接把 `person.job` 当副标题渲染，
  /// 于是中文界面下同一个人在人物行显示 "Director"、在详情页显示「导演」。
  /// 服务端返回的 job 即使是 canonical key 也会触发，与 F-041 的变体失配无关。
  ///
  /// `TranslationHelper.translateJobs` 对未登记的 key 原样返回且翻译后去重，
  /// 因此对已翻译值（如「导演」）重复投影是幂等的；这里仍显式跳过无变化的情况，
  /// 避免每次刷新都重建 Person 实例。
  private static func translatingJobForDisplay(_ person: Person) -> Person {
    guard let job = person.job, !job.isEmpty else { return person }
    let translated = TranslationHelper.translateJobs(jobString: job)
    guard !translated.isEmpty, translated != job else { return person }
    var projected = person
    projected.job = translated
    return projected
  }

  @Published var isLoading = false
  @Published var searchType: SearchType = .unified

  /// 等待“订阅分享”可选行首屏的最长时长（纳秒）。超过即先行收口核心结果；
  /// 不取消分享请求——它晚到返回只会补“订阅分享”行，不再回填已算好的最佳行。
  /// 默认 3 秒；测试可注入更短值以稳定覆盖超时路径。
  var subscriptionShareTimeoutNanoseconds: UInt64 = 3_000_000_000

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
  private var followsDefaultMediaSearchSource = true
  private var isApplyingDefaultMediaSearchSource = false
  
  @Published var searchProgressText: String = ""
  @Published var searchProgress: Double = 0.0
  @Published var resourceErrorMessage: String?

  init(apiService: APIService = .shared) {
    self.apiService = apiService
    self.siteFilter = SiteFilterViewModel(apiService: apiService)
    let defaultMediaSearchSource = SystemViewModel.currentDefaultMediaSearchSource(
      apiService: apiService
    )
    self.mediaSearchSource = defaultMediaSearchSource
    self.followsDefaultMediaSearchSource = true
    self.siteFilter.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .searchDefaultsDidChange)
      .compactMap { $0.object as? SearchDefaultsChange }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] change in
        guard let self, change.profileKey == self.apiService.profileKey else { return }
        guard self.followsDefaultMediaSearchSource else { return }
        if self.mediaSearchSource != change.defaultMediaSearchSource {
          self.isApplyingDefaultMediaSearchSource = true
          self.mediaSearchSource = change.defaultMediaSearchSource
          self.isApplyingDefaultMediaSearchSource = false
        }
      }
      .store(in: &cancellables)
  }

  /// 执行初始搜索：根据 searchType 决定是资源搜索还是聚合元数据搜索
  func autoSearch() async {
    // F-140：提交口先把搜索词规范化一次（去掉首尾空白与换行），之后**请求与本地评分
    // 共用这一个串**。
    //
    // 后端 `StringUtils.get_keyword` 自己会 `.strip()`，所以发出去的请求本来就是干净的；
    // 出问题的是 TV 自己的「最佳匹配」评分 —— 它读 `submittedQuery`，先前直接取用户原串。
    // 于是搜 `Hamilton` 时手滑多留一个尾随空格，精确标题在 `fuzzyMatchScore` 里拿到 `-1`
    // （低于任何模糊命中，会被 `Hamilton Musical` 这类带后缀的标题反超而掉到末位），
    // 若恰好又无海报且热度 < 1，还会被 `hasNoPoster && maxS < 50 && pop < 1` 整条淘汰。
    // 纯空白串也能绕过 `isEmpty` 守卫触发一次注定无果的全量搜索。
    //
    // 刻意不写回 `query`：搜索框保留用户输入原样，提交后就地改写文本更突兀。
    // 也刻意只去首尾、不压缩内部空白 —— 内部空白的匹配质量属于评分层的分档问题，
    // 不是「提交词身份」问题，动它会波及 `hasPrefix`/`contains` 的既有分档。
    let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !searchQuery.isEmpty else { return }
    let currentSearchType = searchType
    guard canAccess(currentSearchType) else { return }
    searchGeneration += 1
    let currentSearchGeneration = searchGeneration
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
            Logger.error("[SearchVM] 加载过滤规则失败，放行不过滤: \(error)")
            filteredResults = accumulatedResults
          }
          guard canPublishSearchResult(
            generation: currentSearchGeneration,
            sessionSnapshot: sessionSnapshot,
            searchType: currentSearchType)
          else { return }

          self.resourceResults = filteredResults
        } catch {
          Logger.error("Stream Search error: \(error)")
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
              Logger.error("[SearchVM] 加载过滤规则失败，放行不过滤: \(error)")
            }
            guard canPublishSearchResult(
              generation: currentSearchGeneration,
              sessionSnapshot: sessionSnapshot,
              searchType: currentSearchType)
            else { return }

            self.resourceResults = fallbackResults
          } catch {
            Logger.error("Fallback Search error: \(error)")
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
      // “订阅分享”是可选锦上添花：与核心分类并发刷新，晚到结果只填充“订阅分享”行。
      if let sharePag {
        Task { @MainActor in await sharePag.refresh() }
      }
      _ = await (
        movieTask.value, tvTask.value, collectionTask.value, personTask.value
      )
      // 核心四类完成后最多再等“订阅分享”超时窗口即先行收口；不取消分享请求。
      await waitForOptionalShareIfPresent(
        sharePag,
        timeoutNanoseconds: subscriptionShareTimeoutNanoseconds
      )
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

  /// 等待可选的“订阅分享”首屏完成，最多等 timeoutNanoseconds。分页器 isLoading 期间
  /// 表示其首屏请求仍在途；完成（成功或失败）即返回，其 items 已落位。超时放弃等待并
  /// 返回，分享刷新保持后台运行——晚到结果只驱动“订阅分享”行，不回填已算好的最佳行。
  /// 用轮询而非 task group：对 Task.value 的等待不可因组取消而中断，会让组作用域隐式等待挂起。
  private func waitForOptionalShareIfPresent(
    _ sharePaginator: Paginator<MediaInfo>?,
    timeoutNanoseconds: UInt64
  ) async {
    guard let sharePaginator else { return }
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while sharePaginator.isLoading || sharePaginator.isFirstLoading {
      if DispatchTime.now().uptimeNanoseconds >= deadline { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
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
      imageWarmURLsProvider: { item in
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
      imageWarmURLsProvider: { @MainActor item in
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
      imageWarmURLsProvider: { @MainActor item in
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
        // F-044：人物行与最佳结果卡片都直接读 `job` 当副标题，搜索链路此前没有任何
        // 翻译边界（详情页的职员才经 `StaffManager` 翻译）。在这里统一投影，
        // 避免在 `PersonCard` / 最佳结果卡片两处各打一次补丁。
        let uniqueNewItems = Person.deduplicate(
          newItems.map(Self.translatingJobForDisplay), existingIDs: &personSeenIDs)
        if uniqueNewItems.isEmpty { return false }
        currentItems.append(contentsOf: uniqueNewItems)
        return true
      },
      imageWarmURLsProvider: { item in
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
        imageWarmURLsProvider: { item in
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
  private var currentFetchTaskIdentity = 0

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

    currentFetchTaskIdentity += 1
    let identity = currentFetchTaskIdentity

    let task = Task {
      // 无论成功或失败，都在完成时按 identity 退休自己的句柄；
      // 保证唤醒任何等待者之前 currentFetchTask 已清空，避免合流方
      // 重复 await 已完成任务导致游标不推进。
      defer {
        if self.currentFetchTaskIdentity == identity {
          self.currentFetchTask = nil
        }
      }
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
