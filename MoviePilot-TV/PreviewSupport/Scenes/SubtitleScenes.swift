#if DEBUG
import SwiftUI

/// 「字幕搜索」域预览场景：搜索中、候选、结果、失败、中断、已下载标记与下载面板。
@MainActor
enum UIPreviewScenesSubtitle {
  static var section: UIPreviewSection {
    UIPreviewSection(id: "subtitles", title: "字幕搜索", scenes: scenes)
  }

  private static var scenes: [UIPreviewScene] {
    searchScenes + failureScenes + downloadScenes
  }

  // MARK: - 搜索与结果

  private static var searchScenes: [UIPreviewScene] {
    [
      resultScene(
        id: "subtitle.searching",
        title: "字幕搜索 · 搜索中",
        note: "SSE 挂起，首屏保持通用的「正在搜索…」、不显示进度条，底部提供取消。",
        request: titleRequest,
        behaviors: [UIPreviewBehaviorKey.subtitleSearchStream: .hang]
      ),
      resultScene(
        id: "subtitle.searchingProgress",
        title: "字幕搜索 · 服务端进度",
        note: "标题搜索已收到两个站点进度事件：文案显示已完成 2 / 3 个请求，进度条约 60%，流仍未结束。",
        request: titleRequest,
        scenario: UIPreviewSubtitleScenario.progress
      ),
      resultScene(
        id: "subtitle.previewCandidates",
        title: "字幕搜索 · 候选可停止查看",
        note: "媒体精确搜索先收到 3 条站点候选、最终匹配尚未返回：显示已收到条数与「停止并查看」，确认后卡片标记「未完成匹配」。",
        request: mediaRequest,
        scenario: UIPreviewSubtitleScenario.previewCandidates
      ),
      resultScene(
        id: "subtitle.results",
        title: "字幕搜索 · 完整结果",
        note: "电影媒体搜索完成：5 条字幕卡片，含站点、语言、大小、发布时间与下载次数；电影结果没有季集标签，背景为电影剧照。",
        request: movieRequest
      ),
      resultScene(
        id: "subtitle.resultsMany",
        title: "字幕搜索 · 多行结果",
        note: "媒体精确搜索返回 12 条结果，页面背景为剧集 backdrop；用于滚动与焦点检查。",
        request: mediaRequest,
        scenario: UIPreviewSubtitleScenario.many
      ),
      resultScene(
        id: "subtitle.empty",
        title: "字幕搜索 · 无结果",
        note: "服务端 done 携带空列表：显示「未搜索到字幕」，没有失败说明和重新搜索按钮。",
        request: titleRequest,
        behaviors: [UIPreviewBehaviorKey.subtitleSearchStream: .empty]
      ),
      resultScene(
        id: "subtitle.titleSearch",
        title: "字幕搜索 · 按标题搜索",
        note: "Kind.title：页面标题就是关键词「夜航日志」，没有媒体背景图；完成 4 条结果。",
        request: keywordRequest,
        count: 4
      ),
      resultScene(
        id: "subtitle.mediaSearch",
        title: "字幕搜索 · 按媒体识别匹配",
        note: "Kind.media：标题为剧名并使用该媒体 backdrop；搜索停在「正在识别匹配 5 个候选字幕」的 98% 进度。",
        request: mediaRequest,
        scenario: UIPreviewSubtitleScenario.mediaFiltering
      ),
      downloadedRowScene,
      invalidatedScene,
      resultScene(
        id: "subtitle.noSearchPermission",
        title: "字幕搜索 · 无搜索权限",
        note: "预览账号没有 search 权限：页面只保留标题，不发起搜索也不显示空态；生产入口本身会按权限隐藏。",
        request: titleRequest,
        permissions: []
      ),
    ]
  }

  // MARK: - 失败与回退

  private static var failureScenes: [UIPreviewScene] {
    [
      resultScene(
        id: "subtitle.failedBusiness",
        title: "字幕搜索 · 服务端业务失败",
        note: "SSE 返回 error 事件，业务文案成为空态说明；页面提供「重新搜索」。",
        request: titleRequest,
        scenario: UIPreviewSubtitleScenario.businessError
      ),
      resultScene(
        id: "subtitle.failedIncompleteBatch",
        title: "字幕搜索 · 分块不完整",
        note: "最终分块乱序触发收集器校验；SSE 断流后普通请求回退也抛出 incompletePage，空态显示「本页结果未完整返回…」。",
        request: titleRequest,
        scenario: UIPreviewSubtitleScenario.invalidBatch,
        fallbackScenario: UIPreviewSubtitleFallbackScenario.incompleteBatch
      ),
      resultScene(
        id: "subtitle.failedNetwork",
        title: "字幕搜索 · 断流且回退失败",
        note: "SSE 以连接中断失败，普通请求回退再超时：失败空态显示网络错误文案，可重新搜索。",
        request: titleRequest,
        behaviors: [
          UIPreviewBehaviorKey.subtitleSearchStream: .error(.networkConnectionLost),
          UIPreviewBehaviorKey.subtitleSearchFallback: .error(.networkTimeout),
        ]
      ),
      resultScene(
        id: "subtitle.fallbackSuccess",
        title: "字幕搜索 · 断流回退成功",
        note: "SSE 连接中断后普通请求成功返回 5 条字幕，列表照常展示，验证回退路径。",
        request: titleRequest,
        behaviors: [UIPreviewBehaviorKey.subtitleSearchStream: .error(.networkConnectionLost)]
      ),
      resultScene(
        id: "subtitle.interrupted",
        title: "字幕搜索 · 已中断",
        note: "搜索流以取消错误结束（对应离开页面或停止搜索）：显示中断空态「未搜索到字幕」，可重新搜索。",
        request: titleRequest,
        scenario: UIPreviewSubtitleScenario.interrupted
      ),
    ]
  }

  // MARK: - 下载面板

  private static var downloadScenes: [UIPreviewScene] {
    let sample = UIPreviewFixtures.subtitlePreviewSample
    return [
      downloadScene(
        id: "subtitle.download.submitting",
        title: "字幕下载 · 提交中",
        note: "真实下载面板预填媒体 ID 后自动提交，下载接口挂起：主按钮显示「下载中」，设置不可编辑。",
        subtitle: sample,
        autoSubmit: true,
        behaviors: [UIPreviewBehaviorKey.detailDownloadSubtitle: .hang]
      ),
      downloadScene(
        id: "subtitle.download.failure",
        title: "字幕下载 · 提交失败",
        note: "自动提交后下载接口返回业务失败：错误文案显示在按钮上方，设置恢复可编辑，可再次提交。",
        subtitle: sample,
        autoSubmit: true,
        behaviors: [
          UIPreviewBehaviorKey.detailDownloadSubtitle:
            .error(.serverMessage("字幕下载失败，请稍后重试。"))
        ]
      ),
      downloadScene(
        id: "subtitle.download.directoryFailure",
        title: "字幕下载 · 目录加载失败",
        note: "保存路径目录接口失败：面板提示目录错误并提供「重试」，来源与媒体 ID 仍可编辑。",
        subtitle: sample,
        autoSubmit: false,
        behaviors: [
          UIPreviewBehaviorKey.detailDownloadDirectories:
            .error(.serverMessage("保存路径加载失败，请重试。"))
        ]
      ),
      downloadScene(
        id: "subtitle.download.noPermission",
        title: "字幕下载 · 无搜索权限",
        note: "没有 search 权限：设置全部禁用，面板提示「当前账号没有搜索权限，无法下载字幕。」，主按钮变为「关闭」。",
        subtitle: sample,
        autoSubmit: false,
        environment: .limited(permissions: [])
      ),
    ]
  }

  // MARK: - 特殊页面

  private static var downloadedRowScene: UIPreviewScene {
    let items = UIPreviewFixtures.subtitleResults(for: mediaRequest, count: 5)
    let downloaded = [items[0].enclosure, items[2].enclosure].compactMap { $0 }
    return UIPreviewScene.page(
      id: "subtitle.downloadedRow",
      title: "字幕搜索 · 已下载标记",
      note: "媒体搜索结果中第 1、3 条已记录为已下载，卡片出现「已下载」标签；列表仍由真实 SubtitleSearchSession 产出。"
    ) {
      UIPreviewSubtitleDownloadedPage(
        request: mediaRequest, downloadedEnclosures: downloaded)
    }
  }

  private static var invalidatedScene: UIPreviewScene {
    UIPreviewScene.page(
      id: "subtitle.invalidated",
      title: "字幕搜索 · 登录状态更新",
      note: "页面打开后预览会话被重新登录替换：搜索会话收到失效通知，显示「登录状态已更新…」且不可重新搜索。",
      behaviors: [UIPreviewBehaviorKey.subtitleSearchStream: .hang]
    ) {
      UIPreviewSubtitleInvalidatedPage(request: titleRequest)
    }
  }

  // MARK: - 请求

  private static var tvMedia: MediaInfo {
    UIPreviewFixtures.baseTVMedia(id: 90_201, title: "边境信号")
  }

  private static var movieMedia: MediaInfo {
    UIPreviewFixtures.movieMedia(id: 90_101, title: "荒原长路")
  }

  private static var titleRequest: SubtitleSearchRequest {
    SubtitleSearchRequest(
      kind: .title(keyword: "荒原长路"),
      sites: "1,3,7",
      displayTitle: "荒原长路",
      mediaInfo: nil
    )
  }

  private static var keywordRequest: SubtitleSearchRequest {
    SubtitleSearchRequest(
      kind: .title(keyword: "夜航日志"),
      sites: "1,3,7",
      displayTitle: "夜航日志",
      mediaInfo: nil
    )
  }

  private static var mediaRequest: SubtitleSearchRequest {
    let media = tvMedia
    return SubtitleSearchRequest(
      kind: .media(
        source: "themoviedb", mediaId: "90201", type: media.type, season: 1, episode: nil),
      sites: "1,3,7",
      displayTitle: media.title,
      mediaInfo: media
    )
  }

  private static var movieRequest: SubtitleSearchRequest {
    let media = movieMedia
    return SubtitleSearchRequest(
      kind: .media(
        source: "themoviedb", mediaId: "90101", type: media.type, season: nil,
        episode: nil),
      sites: "1,3,7",
      displayTitle: media.title,
      mediaInfo: media
    )
  }

  // MARK: - 场景构造

  private static func resultScene(
    id: String,
    title: String,
    note: String,
    request: SubtitleSearchRequest,
    count: Int? = nil,
    scenario: String? = nil,
    fallbackScenario: String? = nil,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    permissions: Set<UserPermissionKey>? = nil
  ) -> UIPreviewScene {
    var environment =
      permissions.map { UIPreviewEnvironment.limited(permissions: $0) } ?? .standard
    if let scenario {
      environment.context[UIPreviewSubtitleContext.scenario] = scenario
    }
    if let fallbackScenario {
      environment.context[UIPreviewSubtitleContext.fallbackScenario] = fallbackScenario
    }
    if let count {
      environment.context[UIPreviewSubtitleContext.resultCount] = String(count)
    }
    return UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: environment,
      behaviors: behaviors
    ) {
      UIPreviewSubtitleResultPage(request: request)
    }
  }

  private static func downloadScene(
    id: String,
    title: String,
    note: String,
    subtitle: SubtitleInfo,
    autoSubmit: Bool,
    behaviors: [String: UIPreviewBackend.Behavior] = [:],
    environment: UIPreviewEnvironment = .standard
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: environment,
      behaviors: behaviors
    ) {
      UIPreviewSubtitleDownloadPage(
        request: mediaRequest,
        subtitle: subtitle,
        autoSubmit: autoSubmit
      )
    }
  }
}

// MARK: - 场景根视图

@MainActor
private struct UIPreviewSubtitleResultPage: View {
  let request: SubtitleSearchRequest
  @StateObject private var imageLifecycle = PageImageLifecycle()

  var body: some View {
    UIPreviewPageHost {
      SubtitleResultView(request: request, imageLifecycle: imageLifecycle)
    }
  }
}

/// 用真实 `SubtitleResultsBody` 渲染结果，并在搜索前把部分条目登记为已下载。
@MainActor
private struct UIPreviewSubtitleDownloadedPage: View {
  @StateObject private var search: SubtitleSearchSession
  @StateObject private var imageLifecycle = PageImageLifecycle()
  private let downloadedEnclosures: [String]

  init(request: SubtitleSearchRequest, downloadedEnclosures: [String]) {
    _search = StateObject(wrappedValue: SubtitleSearchSession(request: request))
    self.downloadedEnclosures = downloadedEnclosures
  }

  var body: some View {
    UIPreviewPageHost {
      SubtitleResultsBody(search: search, imageLifecycle: imageLifecycle) {
        Text(search.request.navigationTitle)
          .font(.title2.bold())
          .foregroundColor(.secondary)
      }
    }
    .task {
      for enclosure in downloadedEnclosures {
        search.markDownloaded(enclosure: enclosure)
      }
      search.start()
    }
  }
}

/// 先正常开始搜索，再替换预览会话，触发真实的登录态失效分支。
@MainActor
private struct UIPreviewSubtitleInvalidatedPage: View {
  let request: SubtitleSearchRequest
  @StateObject private var imageLifecycle = PageImageLifecycle()

  var body: some View {
    UIPreviewPageHost {
      SubtitleResultView(request: request, imageLifecycle: imageLifecycle)
    }
    .task {
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      APIService.shared.installUIPreviewSession(
        token: UIPreviewFixtures.userToken(userName: "预览用户 · 已重新登录"),
        baseURL: UIPreviewEnvironment.defaultBaseURL
      )
    }
  }
}

/// 下载面板场景：真实 `SubtitleDownloadViewModel` + `SubtitleDownloadSheet`。
@MainActor
private struct UIPreviewSubtitleDownloadPage: View {
  @StateObject private var viewModel: SubtitleDownloadViewModel
  private let autoSubmit: Bool

  init(request: SubtitleSearchRequest, subtitle: SubtitleInfo, autoSubmit: Bool) {
    _viewModel = StateObject(
      wrappedValue: SubtitleDownloadViewModel(
        subtitle: subtitle,
        request: request,
        bindsCurrentMedia: true
      )
    )
    self.autoSubmit = autoSubmit
  }

  var body: some View {
    UIPreviewPageHost {
      SubtitleDownloadSheet(viewModel: viewModel)
        .background(Color(white: 0.08).ignoresSafeArea())
    }
    .task {
      guard autoSubmit else { return }
      // 等面板自己的目录加载先跑起来，再按用户确认的时机提交。
      try? await Task.sleep(for: .milliseconds(300))
      for _ in 0..<40 {
        if !viewModel.isLoadingDirectories, viewModel.canSubmit { break }
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard !Task.isCancelled, viewModel.canSubmit else { return }
      viewModel.submit()
    }
  }
}
#endif
