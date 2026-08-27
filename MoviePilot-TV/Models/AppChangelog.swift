import Foundation

nonisolated struct AppChangelogEntry: Identifiable, Equatable, Sendable {
  let version: String
  let releaseDate: String
  let compatibleMoviePilotVersion: String
  let highlights: [String]
  let updates: [String]
  let fixes: [String]
  let optimizations: [String]

  var id: String { version }
}

nonisolated enum AppChangelog {
  static let presentedVersionKey = "lastPresentedChangelogVersion"

  static let entries: [AppChangelogEntry] = [
    AppChangelogEntry(
      version: "v0.3.8",
      releaseDate: "2026-08-27",
      compatibleMoviePilotVersion: "v2.15.6",
      highlights: [
        "紧急修复详情页焦点卡死、无法操作且只能重启 App 恢复的严重问题。",
      ],
      updates: [],
      fixes: [
        "修复 App 从后台返回后，详情页焦点卡在顶部 Tab 栏、无法下移到内容区的问题。",
        "修复详情页上移到顶部 Tab 栏后无法再次下移的问题，恢复正常浏览操作。",
      ],
      optimizations: []
    ),
    AppChangelogEntry(
      version: "v0.3.7",
      releaseDate: "2026-08-26",
      compatibleMoviePilotVersion: "v2.15.6",
      highlights: [
        "降低 77% 内存占用，减少 MoviePilot-TV 或其他 App 因内存压力被系统终止的情况。",
        "优化登录状态处理，网络波动或服务异常时不再轻易退出登录。",
      ],
      updates: [],
      fixes: [
        "修复登录状态误判、凭据恢复、特殊字符密码、版本提醒及账号切换后的权限和旧会话残留问题。",
        "修复探索来源插件筛选与 MoviePilot Web 不一致，以及聚合搜索、资源搜索、站点过滤、资源排序和卡片显示异常。",
        "修复详情与人物页面焦点、加载失败提示、转场海报、背景图片、空白占位图及页面返回恢复异常。",
        "修复订阅状态与取消反馈、剧集组加载、下载器重试和暂停继续状态，以及批量整理反馈、选择和轮询漏项问题。",
        "修复首页与状态页空态、媒体库轮询、分页失败提示、接口错误解析、后台数据解码及多来源媒体身份兼容问题。",
      ],
      optimizations: []
    ),
    AppChangelogEntry(
      version: "v0.3.6",
      releaseDate: "2026-08-12",
      compatibleMoviePilotVersion: "v2.15.6",
      highlights: [
        "兼容 MoviePilot 后端 v2.15.6。",
        "探索页兼容 MoviePilot 探索来源插件。",
        "支持 AniList 媒体来源。",
        "聚合搜索支持选择媒体来源并设置默认来源。",
        "新增手动整理预览功能。",
        "新增版本更新历史与升级提示。",
      ],
      updates: [
        "探索页兼容 MoviePilot 动态探索来源插件，并支持插件自定义筛选项。",
        "支持 AniList 媒体来源，并贯通探索、聚合搜索、详情跳转、人物详情和来源标识。",
        "聚合搜索支持选择 TMDB、豆瓣、Bangumi 和 AniList，并可设置默认搜索来源。",
        "手动整理支持预览整理前后的文件名和路径。",
        "媒体卡片支持直接取消订阅，电影详情可显示入库状态。",
        "人物详情支持多来源图片与简介。",
        "设置页新增版本更新历史；版本升级后显示本次更新摘要。",
      ],
      fixes: [
        "修复多来源订阅身份、状态刷新、菜单操作及保存返回流程中的异常。",
        "修复资源搜索、手动搜索和页面切换时过期结果覆盖当前内容的问题。",
        "修复下载器切换、任务删除、转移历史批量操作及 AI 重整可能操作错误对象的问题。",
        "修复账号切换后旧请求、权限、图片及页面缓存可能残留的问题。",
      ],
      optimizations: [
        "优化资源流式搜索进度、错误提示和普通请求回退。",
        "增强稀疏接口数据、失败响应及多来源媒体身份的处理稳定性。",
      ]
    ),
    AppChangelogEntry(
      version: "v0.3.5",
      releaseDate: "2026-07-22",
      compatibleMoviePilotVersion: "v2.14.6",
      highlights: [
        "兼容 MoviePilot 后端 v2.14.6。",
        "TMDB 详情跳转支持预加载，并在加载期间延续来源海报。",
        "修复 TMDB 识别、订阅状态和搜索加载的重要异常。",
      ],
      updates: [
        "TMDB 详情跳转支持预加载，并在加载期间延续来源海报。"
      ],
      fixes: [
        "修复 TMDB 识别失败后详情页持续加载的问题。",
        "修复订阅分享丢失 Bangumi ID、订阅状态刷新及搜索加载状态异常。",
      ],
      optimizations: [
        "同步 MoviePilot v2.14.6 兼容基线。"
      ]
    ),
    AppChangelogEntry(
      version: "v0.3.4",
      releaseDate: "2026-07-16",
      compatibleMoviePilotVersion: "v2.14.4",
      highlights: [
        "兼容 MoviePilot 后端 v2.14.4。",
        "修复详情页、列表与弹窗的焦点和状态反馈问题。",
        "修复分季取消订阅与 MoviePilot 行为不一致的问题。",
      ],
      updates: [],
      fixes: [
        "修复详情页、列表与弹窗的焦点和状态反馈问题。",
        "修复分季取消订阅与 MoviePilot v2.14.4 行为不一致的问题。",
      ],
      optimizations: [
        "适配 MoviePilot v2.14.4。"
      ]
    ),
    AppChangelogEntry(
      version: "v0.3.3",
      releaseDate: "2026-07-02",
      compatibleMoviePilotVersion: "v2.14.0",
      highlights: [
        "兼容 MoviePilot 后端 v2.14.0。",
        "修复部分电视剧无分季信息或加载失败时无法继续订阅的问题。",
      ],
      updates: [
        "适配 MoviePilot v2.14.0。"
      ],
      fixes: [
        "修复部分电视剧详情页无分季信息时的显示异常。",
        "修复分季信息加载失败时无法进入分季订阅的问题。",
      ],
      optimizations: []
    ),
    AppChangelogEntry(
      version: "v0.3.2",
      releaseDate: "2026-07-01",
      compatibleMoviePilotVersion: "v2.13.14",
      highlights: [
        "兼容 MoviePilot 后端 v2.13.14。",
        "重新设计设置页面，并新增 Apple TV 自动续签脚本。",
        "修复权限、异步页面状态与订阅流程中的多项重要问题。",
      ],
      updates: [
        "重新设计设置页面 UI。",
        "适配 MoviePilot v2.13.14。",
        "新增 Apple TV 自动续签脚本。",
      ],
      fixes: [
        "对齐 MoviePilot Web 权限规则，非超级用户不再访问或显示仅限超级用户的功能。",
        "修复下载、搜索、资源搜索和订阅中的旧请求覆盖当前页面状态问题。",
        "修复分季订阅、取消订阅确认、订阅缓存刷新和订阅分享去重问题。",
        "修复部分合集识别、人物图片解析和图片代理地址兼容问题。",
      ],
      optimizations: [
        "增强订阅状态、媒体详情和异步刷新过程的稳定性。"
      ]
    ),
    AppChangelogEntry(
      version: "v0.3.1",
      releaseDate: "2026-05-29",
      compatibleMoviePilotVersion: "v2.13.2",
      highlights: [
        "兼容 MoviePilot 后端 v2.13.2。",
        "优化手动整理、资源搜索和订阅状态同步。",
        "修复图片代理、搜索结束时机与订阅状态异常。",
      ],
      updates: [
        "适配 MoviePilot v2.13.2。",
        "优化手动整理、资源搜索和订阅状态同步。",
      ],
      fixes: [
        "修复部分图片代理地址被截断的问题。",
        "修复搜索完成后可能过早结束的问题。",
        "修复部分场景订阅状态不同步的问题。",
      ],
      optimizations: []
    ),
    AppChangelogEntry(
      version: "v0.3.0",
      releaseDate: "2026-05-02",
      compatibleMoviePilotVersion: "v2.10.9",
      highlights: [
        "兼容 MoviePilot 后端 v2.10.9。",
        "新增搜索过滤、默认站点、SSE 流式搜索和首页卡片快捷操作。",
        "显著优化页面渲染、详情加载和图片预取性能。",
        "修复页面返回焦点重置及部分详情页白屏问题。",
      ],
      updates: [
        "搜索过滤功能大幅增强，支持硬过滤（排除）与软过滤（置尾）组合规则。",
        "支持配置默认资源搜索站点，并在全局搜索中应用。",
        "首页“最近添加”卡片增加长按菜单，支持快速跳转、查看详情及搜索资源。",
        "适配 MoviePilot v2.10.9 批量 AI 整理接口。",
        "系统设置页面增加连接信息显示，包含后端地址、当前用户及版本。",
        "适配 SSE 流式搜索，显著提升资源搜索的响应速度。",
        "增加账号状态检测与手动刷新功能。",
      ],
      fixes: [
        "修复页面返回时焦点重置、部分详情页因 API 空数据导致白屏等问题。"
      ],
      optimizations: [
        "优化 SwiftUI 渲染性能，提升 UI 操作与滚动流畅度。",
        "优化详情页加载过渡动画及数据预加载逻辑，减少进入页面的等待感。",
        "改进搜索匹配逻辑。",
        "实现分页图片预取策略，优化列表滚动时的图片加载体验。",
        "针对 tvOS 26.0 至 26.4 调整 Sheet 组件样式与兼容性。",
        "扩大添加下载弹窗尺寸及标题描述的显示行数。",
        "优化轮询刷新逻辑，确保应用从后台唤醒后正常触发数据更新。",
      ]
    ),
    AppChangelogEntry(
      version: "v0.2.0",
      releaseDate: "2026-03-14",
      compatibleMoviePilotVersion: "v2.9.13",
      highlights: [
        "新增订阅分享、整理历史与手动整理功能。",
        "首页媒体支持直接播放，发现页新增热门订阅推荐。",
        "重构系统状态页面并提升稳定性。",
      ],
      updates: [
        "新增订阅分享浏览、搜索与复用功能。",
        "新增整理历史浏览与手动整理功能。",
        "首页媒体卡片支持直接跳转播放。",
        "发现页新增热门订阅推荐。",
      ],
      fixes: [],
      optimizations: [
        "重构系统状态页面，优化数据模型和稳定性。",
        "增强 UI 交互。",
        "优化首页、订阅页的卡片显示，订阅卡片增加更新时间。",
      ]
    ),
    AppChangelogEntry(
      version: "v0.1.2",
      releaseDate: "2026-03-09",
      compatibleMoviePilotVersion: "v2.9.13",
      highlights: [
        "优化下载任务页交互和刷新性能。",
        "改进搜索结果布局与流行趋势展示。",
      ],
      updates: [
        "搜索页根据最佳结果数量动态调整展示行数。",
        "流行趋势支持在全部内容和榜单中显示。",
      ],
      fixes: [
        "修复提交按钮在加载状态下的显示问题。",
        "修复下载任务行的部分交互问题。",
        "优化部分语言名称的简体中文翻译。",
      ],
      optimizations: [
        "优化下载任务页的 UI 刷新性能。"
      ]
    ),
    AppChangelogEntry(
      version: "v0.1.1",
      releaseDate: "2026-03-08",
      compatibleMoviePilotVersion: "v2.9.13",
      highlights: [
        "兼容 MoviePilot 后端 v2.9.13。",
        "统一分页加载并增加接口缓存，提升列表和详情加载性能。",
        "修复合集分页、分季缓存及详情页加载问题。",
      ],
      updates: [],
      fixes: [
        "修复详情页加载不完整、内容跳动与闪烁问题。",
        "修复合集详情页只显示第一页的问题。",
        "修复分季信息缓存错误。",
      ],
      optimizations: [
        "引入通用分页加载器，统一推荐、探索、搜索、人物及合集页面的数据加载。",
        "增加接口缓存并优化分季和详情页加载体验。",
        "增强分页重置、任务取消和加载状态的稳定性。",
      ]
    ),
    AppChangelogEntry(
      version: "v0.1.0",
      releaseDate: "2026-03-06",
      compatibleMoviePilotVersion: "v2.9.7",
      highlights: [
        "首次发布 MoviePilot Apple TV 原生客户端。",
        "支持媒体浏览、搜索、详情、订阅与 Siri Remote 快捷操作。",
      ],
      updates: [
        "发布首个基于 SwiftUI 的 MoviePilot Apple TV 原生客户端。",
        "支持媒体库、推荐、探索、聚合搜索及媒体、人物和合集详情。",
        "支持媒体订阅、资源搜索与添加下载。",
        "支持 Siri Remote 海报长按快捷操作和持久化登录。",
      ],
      fixes: [],
      optimizations: [
        "针对电视大屏与 Siri Remote 交互设计原生界面和详情加载流程。"
      ]
    ),
  ]

  static var latest: AppChangelogEntry? { entries.first }

  static func entry(for appVersion: String) -> AppChangelogEntry? {
    entries.first { $0.version == AppVersionInfo.displayAppVersion(shortVersion: appVersion) }
  }

  static func pendingUpdate(
    appVersion: String,
    defaults: UserDefaults = .standard
  ) -> AppChangelogEntry? {
    guard let current = entry(for: appVersion) else { return nil }
    guard let presentedVersion = defaults.string(forKey: presentedVersionKey) else {
      return current
    }
    guard presentedVersion != current.version else { return nil }
    guard
      AppVersionInfo.compareMoviePilotVersion(current.version, to: presentedVersion)
        == .orderedDescending
    else {
      return nil
    }
    return current
  }

  static func markPresented(
    _ entry: AppChangelogEntry,
    defaults: UserDefaults = .standard
  ) {
    defaults.set(entry.version, forKey: presentedVersionKey)
  }

  static func updateNoticeMessage(for entry: AppChangelogEntry) -> String {
    let highlights = entry.highlights.map { "• \($0)" }.joined(separator: "\n")
    return "\(highlights)\n\n完整更新日志请前往“设置 > 版本更新历史”查看。"
  }
}
