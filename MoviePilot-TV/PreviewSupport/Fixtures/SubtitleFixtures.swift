#if DEBUG
import Foundation

/// 「字幕搜索」域的预览场景参数。
enum UIPreviewSubtitleContext {
  /// 事件序列变体，例如 `progress`、`previewCandidates`、`many`。
  static let scenario = "subtitle.scenario"
  /// SSE 失败后普通请求回退的结果；`incompleteBatch` 让回退也失败。
  static let fallbackScenario = "subtitle.fallbackScenario"
  /// 覆盖本次 fixture 的结果条数，用于展示多行或较少结果。
  static let resultCount = "subtitle.resultCount"
}

/// 字幕 SSE 的事件序列变体。
enum UIPreviewSubtitleScenario {
  /// 返回 12 条结果，检查多行滚动。
  static let many = "many"
  /// 只有服务端进度事件，搜索不结束。
  static let progress = "progress"
  /// 只有媒体候选，最终匹配没有返回。
  static let previewCandidates = "previewCandidates"
  /// 媒体搜索停在「识别匹配」的 98%。
  static let mediaFiltering = "mediaFiltering"
  /// 以 CancellationError 结束，对应离开页面或用户停止。
  static let interrupted = "interrupted"
  /// 服务端 error 事件。
  static let businessError = "businessError"
  /// 最终分块下标不连续，触发收集器校验。
  static let invalidBatch = "invalidBatch"
}

/// SSE 失败后普通请求回退的模拟结果。
enum UIPreviewSubtitleFallbackScenario {
  /// 回退同样返回分块不完整错误。
  static let incompleteBatch = "incompleteBatch"
}

extension UIPreviewBehaviorKey {
  /// 字幕搜索 SSE 流：挂起、空结果或指定错误。
  static let subtitleSearchStream = "subtitle.searchStream"
  /// SSE 中断后回退的普通字幕搜索。
  static let subtitleSearchFallback = "subtitle.searchFallback"
}

extension UIPreviewFixtures {
  // MARK: - SSE

  /// 字幕搜索 SSE。真实 `SubtitleSearchSession` 只消费事件，页面不感知预览。
  static func subtitleSearchStream(
    _ request: SubtitleSearchRequest
  ) -> AsyncThrowingStream<SubtitleSearchEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          try await emitSubtitleSearchEvents(request, to: continuation)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  // MARK: - 普通请求回退

  /// SSE 中断后 APIService 会改用普通请求，这里同样交给预览后端决定成功或失败。
  static func subtitleSearchResults(
    _ request: SubtitleSearchRequest
  ) async throws -> [SubtitleInfo] {
    try await UIPreviewBackend.shared.gate(UIPreviewBehaviorKey.subtitleSearchFallback)
    if UIPreviewBackend.shared.isEmpty(for: UIPreviewBehaviorKey.subtitleSearchFallback) {
      return []
    }
    let fallbackScenario = UIPreviewBackend.shared.context(
      UIPreviewSubtitleContext.fallbackScenario)
    if fallbackScenario == UIPreviewSubtitleFallbackScenario.incompleteBatch {
      throw ResourceSearchFailure.incompletePage
    }
    return subtitleResults(for: request, count: subtitleResultCount())
  }

  // MARK: - 结果数据

  /// 字幕结果页 fixture。标题搜索、媒体搜索和下载面板共用同一批字段形态，季集按请求补齐。
  static func subtitleResults(
    for request: SubtitleSearchRequest,
    count: Int = 5
  ) -> [SubtitleInfo] {
    let title = subtitleDisplayTitle(for: request)
    let seasonEpisodes = subtitleSeasonEpisodes(for: request, count: count)
    return (0..<count).map { index in
      let entry = subtitleFixtureEntries[index % subtitleFixtureEntries.count]
      let suffix = entry.suffix
      return SubtitleInfo(
        site: entry.site,
        site_name: entry.siteName,
        site_cookie: nil,
        site_ua: nil,
        site_proxy: nil,
        site_order: entry.site,
        title: "\(title).\(suffix)",
        description: "预览字幕：\(entry.siteName) 提供的 \(entry.language) 版本，文件与正片同名。",
        enclosure: "https://subtitle-\(entry.site).example/download/preview-\(index).ass",
        page_url: "https://subtitle-\(entry.site).example/detail/preview-\(index)",
        language: entry.language,
        language_icon: nil,
        size: entry.size,
        pubdate: entry.pubdate,
        date_elapsed: nil,
        grabs: entry.grabs,
        uploader: nil,
        report_url: nil,
        torrent_id: nil,
        subtitle_id: "preview-subtitle-\(index)",
        file_name: "\(title).\(suffix)",
        meta_info: nil,
        season_episode: seasonEpisodes[index],
        episode_list: nil
      )
    }
  }

  static var subtitlePreviewSample: SubtitleInfo {
    subtitleResults(
      for: SubtitleSearchRequest(
        kind: .media(
          source: "themoviedb", mediaId: "90201", type: "电视剧", season: 1,
          episode: 1),
        sites: nil,
        displayTitle: "边境信号",
        mediaInfo: nil
      ),
      count: 1
    )[0]
  }

  // MARK: - 事件推进

  private static func emitSubtitleSearchEvents(
    _ request: SubtitleSearchRequest,
    to continuation: AsyncThrowingStream<SubtitleSearchEvent, Error>.Continuation
  ) async throws {
    let backend = UIPreviewBackend.shared
    try await backend.gate(UIPreviewBehaviorKey.subtitleSearchStream)
    let scenario = backend.context(UIPreviewSubtitleContext.scenario)

    if backend.isEmpty(for: UIPreviewBehaviorKey.subtitleSearchStream) {
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      yieldSubtitle(
        subtitleEvent(
          type: "done", text: "搜索完成，共 0 个字幕", value: 100, stage: "done",
          totalItems: 0),
        to: continuation)
      return
    }

    if scenario == UIPreviewSubtitleScenario.progress {
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleProgressText(for: request, completed: 1, total: 3),
          value: 30,
          stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleProgressText(for: request, completed: 2, total: 3),
          value: 60,
          stage: "searching"),
        to: continuation)
      try await holdSubtitleStream()
      return
    }
    if scenario == UIPreviewSubtitleScenario.mediaFiltering {
      let candidateCount = subtitleResults(
        for: request, count: subtitleResultCount()
      ).count
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      yieldSubtitle(
        subtitleProgressEvent(
          text: "正在识别匹配 \(candidateCount) 个候选字幕 ...",
          value: 98,
          stage: "filtering"),
        to: continuation)
      try await holdSubtitleStream()
      return
    }
    if scenario == UIPreviewSubtitleScenario.previewCandidates {
      try await emitSubtitleCandidatePreview(request, to: continuation)
      try await holdSubtitleStream()
      return
    }
    if scenario == UIPreviewSubtitleScenario.interrupted {
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      throw CancellationError()
    }
    if scenario == UIPreviewSubtitleScenario.businessError {
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      yieldSubtitle(
        subtitleEvent(
          type: "error", messageI18n: subtitleBusinessErrorMessage),
        to: continuation)
      return
    }
    if scenario == UIPreviewSubtitleScenario.invalidBatch {
      yieldSubtitle(
        subtitleProgressEvent(
          text: subtitleStartText(for: request), value: 0, stage: "searching"),
        to: continuation)
      try await pauseSubtitleFixture()
      let items = subtitleResults(for: request, count: 4)
      // 本应 batch_index 从 0 开始，这里从 1 开始，触发收集器的分块校验。
      yieldSubtitle(
        subtitleEvent(
          type: "replace",
          value: 100,
          items: Array(items.prefix(2)),
          stage: "filtered",
          replaceBatch: true,
          batchIndex: 1,
          batchCount: 2,
          totalItems: items.count),
        to: continuation)
      return
    }
    try await emitSubtitleCompletedEvents(request, to: continuation)
  }

  private static func emitSubtitleCompletedEvents(
    _ request: SubtitleSearchRequest,
    to continuation: AsyncThrowingStream<SubtitleSearchEvent, Error>.Continuation
  ) async throws {
    let items = subtitleResults(for: request, count: subtitleResultCount())
    yieldSubtitle(
      subtitleProgressEvent(
        text: subtitleStartText(for: request), value: 0, stage: "searching"),
      to: continuation)
    try await pauseSubtitleFixture()

    if case .title = request.kind {
      let chunks = subtitleChunks(items, count: 3)
      var received = 0
      for (index, chunk) in chunks.enumerated() {
        received += chunk.count
        yieldSubtitle(
          subtitleAppendEvent(
            from: request,
            chunk: chunk,
            completed: index + 1,
            total: chunks.count,
            received: received),
          to: continuation)
        try await pauseSubtitleFixture()
      }
    } else {
      try await emitSubtitleMediaCandidates(request, items: items, to: continuation)
    }

    try await pauseSubtitleFixture()
    yieldSubtitle(
      subtitleEvent(
        type: "done",
        text: "搜索完成，共 \(items.count) 个字幕",
        value: 100,
        items: items,
        stage: "done",
        totalItems: items.count),
      to: continuation)
  }

  private static func emitSubtitleMediaCandidates(
    _ request: SubtitleSearchRequest,
    items: [SubtitleInfo],
    to continuation: AsyncThrowingStream<SubtitleSearchEvent, Error>.Continuation
  ) async throws {
    let candidates = subtitleCandidateItems(
      for: request, count: max(3, min(6, items.count)))
    let chunks = subtitleChunks(candidates, count: 2)
    var received = 0
    for (index, chunk) in chunks.enumerated() {
      received += chunk.count
      yieldSubtitle(
        subtitleEvent(
          type: "append",
          text: subtitleProgressText(
            for: request, completed: index + 1, total: chunks.count),
          value: Double(index + 1) / Double(chunks.count) * 90,
          items: chunk,
          stage: "searching",
          totalItems: received),
        to: continuation)
      try await pauseSubtitleFixture()
    }
    yieldSubtitle(
      subtitleProgressEvent(
        text: "正在识别匹配 \(candidates.count) 个候选字幕 ...",
        value: 98,
        stage: "filtering"),
      to: continuation)
    try await pauseSubtitleFixture()
    yieldSubtitle(
      subtitleEvent(
        type: "replace",
        text: "识别匹配完成，共 \(items.count) 个字幕",
        value: 100,
        items: items,
        stage: "filtered",
        totalItems: items.count),
      to: continuation)
    try await pauseSubtitleFixture()
  }

  /// 媒体搜索的候选预览：只发 append，不发最终 replace。
  private static func emitSubtitleCandidatePreview(
    _ request: SubtitleSearchRequest,
    to continuation: AsyncThrowingStream<SubtitleSearchEvent, Error>.Continuation
  ) async throws {
    yieldSubtitle(
      subtitleProgressEvent(
        text: subtitleStartText(for: request), value: 0, stage: "searching"),
      to: continuation)
    try await pauseSubtitleFixture()
    let candidates = subtitleCandidateItems(for: request, count: 3)
    let chunks = subtitleChunks(candidates, count: 2)
    var received = 0
    for (index, chunk) in chunks.enumerated() {
      received += chunk.count
      yieldSubtitle(
        subtitleEvent(
          type: "append",
          text: subtitleProgressText(
            for: request, completed: index + 1, total: 3),
          value: Double(index + 1) / 3 * 90,
          items: chunk,
          stage: "searching",
          totalItems: received),
        to: continuation)
      try await pauseSubtitleFixture()
    }
  }

  // MARK: - 事件与数据工具

  private static func subtitleEvent(
    type: String?,
    text: String? = nil,
    value: Double? = nil,
    items: [SubtitleInfo]? = nil,
    message: String? = nil,
    messageI18n: String? = nil,
    stage: String? = nil,
    replaceBatch: Bool? = nil,
    batchIndex: Int? = nil,
    batchCount: Int? = nil,
    totalItems: Int? = nil
  ) -> SubtitleSearchEvent {
    SubtitleSearchEvent(
      type: type,
      text: text,
      text_i18n: nil,
      value: value,
      items: items,
      message: message,
      message_i18n: messageI18n,
      stage: stage,
      replace_batch: replaceBatch,
      batch_index: batchIndex,
      batch_count: batchCount,
      total_items: totalItems
    )
  }

  private static func subtitleProgressEvent(
    text: String,
    value: Double,
    stage: String
  ) -> SubtitleSearchEvent {
    subtitleEvent(type: "progress", text: text, value: value, stage: stage)
  }

  private static func subtitleAppendEvent(
    from request: SubtitleSearchRequest,
    chunk: [SubtitleInfo],
    completed: Int,
    total: Int,
    received: Int
  ) -> SubtitleSearchEvent {
    subtitleEvent(
      type: "append",
      text: subtitleProgressText(for: request, completed: completed, total: total),
      value: Double(completed) / Double(total) * 90,
      items: chunk,
      stage: "searching",
      totalItems: received
    )
  }

  private static func subtitleCandidateItems(
    for request: SubtitleSearchRequest,
    count: Int
  ) -> [SubtitleInfo] {
    subtitleResults(for: request, count: count).map { item in
      var candidate = item
      candidate.description = "站点返回的候选字幕，尚未完成季集匹配。"
      candidate.season_episode = nil
      return candidate
    }
  }

  private static func subtitleChunks(
    _ items: [SubtitleInfo],
    count: Int
  ) -> [[SubtitleInfo]] {
    guard !items.isEmpty, count > 0 else { return [] }
    let chunkSize = (items.count + count - 1) / count
    return stride(from: 0, to: items.count, by: chunkSize).map { start in
      Array(items[start..<min(start + chunkSize, items.count)])
    }
  }

  private static func subtitleSeasonEpisodes(
    for request: SubtitleSearchRequest,
    count: Int
  ) -> [String?] {
    guard case .media(_, _, let type, let season, let episode) = request.kind,
      type != "电影"
    else {
      return Array(repeating: nil, count: count)
    }
    let seasonNumber = max(season ?? 1, 1)
    if let episode {
      let value = subtitleSeasonEpisodeText(season: seasonNumber, episode: episode)
      return Array(repeating: value, count: count)
    }
    return (0..<count).map { index in
      subtitleSeasonEpisodeText(season: seasonNumber, episode: index + 1)
    }
  }

  /// 站点的季集字段使用 `S01E02` 这类格式，页面会再格式化成「1季 2集」。
  private static func subtitleSeasonEpisodeText(season: Int, episode: Int) -> String {
    let seasonText = season < 10 ? "0\(season)" : "\(season)"
    let episodeText = episode < 10 ? "0\(episode)" : "\(episode)"
    return "S\(seasonText)E\(episodeText)"
  }

  private static func subtitleDisplayTitle(for request: SubtitleSearchRequest) -> String {
    request.titleKeyword ?? request.displayTitle ?? request.navigationTitle
  }

  private static func subtitleStartText(for request: SubtitleSearchRequest) -> String {
    let siteCount: Int
    if let sites = request.sites {
      siteCount = sites
        .split(separator: ",")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .count
    } else {
      siteCount = 3
    }
    return "开始搜索字幕，共 \(max(siteCount, 1)) 个站点，1 页 ..."
  }

  private static func subtitleProgressText(
    for request: SubtitleSearchRequest,
    completed: Int,
    total: Int
  ) -> String {
    "正在搜索字幕\(subtitleDisplayTitle(for: request))，已完成 \(completed) / \(total) 个请求 ..."
  }

  private static func subtitleResultCount() -> Int {
    if let raw = UIPreviewBackend.shared.context(UIPreviewSubtitleContext.resultCount),
      let count = Int(raw), count > 0
    {
      return count
    }
    let scenario = UIPreviewBackend.shared.context(UIPreviewSubtitleContext.scenario)
    return scenario == UIPreviewSubtitleScenario.many ? 12 : 5
  }

  private static func yieldSubtitle(
    _ event: SubtitleSearchEvent,
    to continuation: AsyncThrowingStream<SubtitleSearchEvent, Error>.Continuation
  ) {
    _ = continuation.yield(event)
  }

  private static func pauseSubtitleFixture() async throws {
    try await Task.sleep(for: .milliseconds(140))
  }

  /// 保持流未结束，让「搜索中」状态稳定可看；离开场景时会随搜索任务取消。
  private static func holdSubtitleStream() async throws {
    try await Task.sleep(for: .seconds(3_600))
  }

  private static let subtitleBusinessErrorMessage = "字幕站点暂时不可用，请稍后重试。"

  private struct SubtitleFixtureEntry {
    let site: Int
    let siteName: String
    let language: String
    let size: Double?
    let grabs: Int?
    let pubdate: String
    let suffix: String
  }

  private static let subtitleFixtureEntries: [SubtitleFixtureEntry] = [
    SubtitleFixtureEntry(
      site: 1, siteName: "AlphaPT", language: "简体中文", size: 48_213, grabs: 42,
      pubdate: "2026-11-09 21:10:00",
      suffix: "2025.1080p.WEB-DL.简中.ass"),
    SubtitleFixtureEntry(
      site: 2, siteName: "BetaHD", language: "简体中文 / 英文", size: 128_400, grabs: 87,
      pubdate: "2026-11-08 18:30:00",
      suffix: "2025.2160p.WEB-DL.简英特效.ass"),
    SubtitleFixtureEntry(
      site: 3, siteName: "GammaPT", language: "繁体中文", size: 96_512, grabs: 16,
      pubdate: "2026-11-05 09:20:00",
      suffix: "2025.1080p.BluRay.繁中.ass"),
    SubtitleFixtureEntry(
      site: 4, siteName: "AlphaPT", language: "英文", size: 33_180, grabs: 9,
      pubdate: "2026-11-03 14:05:00",
      suffix: "2025.1080p.WEBRip.eng.srt"),
    SubtitleFixtureEntry(
      site: 5, siteName: "DeltaSub", language: "简英双语", size: 61_440, grabs: nil,
      pubdate: "2026-10-28 22:45:00",
      suffix: "2025.1080p.简英双语.ass"),
    SubtitleFixtureEntry(
      site: 6, siteName: "EchoPT", language: "日语", size: 27_800, grabs: nil,
      pubdate: "2026-10-21 11:00:00",
      suffix: "2025.1080p.WEB-DL.jp.srt"),
    SubtitleFixtureEntry(
      site: 7, siteName: "Foxtrot", language: "简体中文", size: nil, grabs: 31,
      pubdate: "2026-10-12 08:30:00",
      suffix: "2025.720p.WEB-DL.简中.srt"),
    SubtitleFixtureEntry(
      site: 8, siteName: "GolfSub", language: "繁体中文 / 英文", size: 74_240, grabs: 12,
      pubdate: "2026-09-30 19:15:00",
      suffix: "2025.2160p.WEB-DL.繁英.ass"),
  ]
}
#endif
