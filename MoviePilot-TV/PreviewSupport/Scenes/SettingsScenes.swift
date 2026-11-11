#if DEBUG
import SwiftUI

/// 设置 / 登录 / 日志域的场景。
///
/// 设置子页直接渲染真实 `SystemView` 并指定 `initialPage`，
/// 登录页渲染真实 `LoginView`（Token、服务端地址、登录草稿全部由预览环境注入），
/// 日志页也走真实的设置页 `/ 日志` 子页，只把本地日志记录换成 fixture。
@MainActor
enum UIPreviewScenesSettings {
  static var section: UIPreviewSection {
    UIPreviewSection(
      id: "settings",
      title: "设置 / 登录 / 日志",
      scenes: [
        // MARK: 设置根页
        .page(
          id: "settings.root",
          title: "设置 · 根页面（管理员）",
          note: "全权限超级管理员：主屏、订阅、推荐、聚合搜索、播放、详情、性能、资源搜索、连接与 APP 信息全部可见。与“主框架”分区的 system.root 相同，便于在本分区自包含走查。"
        ) {
          UIPreviewTabRootView(tab: .system)
        },
        .page(
          id: "settings.rootLimited",
          title: "设置 · 根页面（普通用户）",
          note: "非管理员：主屏/推荐配置、自定义过滤与播放设置隐藏，保留订阅、资源搜索、详情、性能与连接信息。",
          environment: UIPreviewEnvironment.limited(
            permissions: Set([.discovery, .search, .subscribe]),
            superUser: false
          )
        ) {
          UIPreviewTabRootView(tab: .system)
        },
        .page(
          id: "settings.backendVersionWarning",
          title: "设置 · 后端版本不兼容告警",
          note: "后端 v3.0.0 低于最低兼容版本 v3.0.4，启动后弹出“继续使用”告警；告警出现在真实根容器上。使用独立预览地址，避免和其它场景的“已确认”记录串用。",
          environment: UIPreviewEnvironment(
            token: UIPreviewFixtures.userToken(),
            baseURL: "http://moviepilot-ui-preview.local:3001",
            backendVersion: "v3.0.0"
          )
        ) {
          RealAppContentView()
        },

        // MARK: 设置子页
        settingsScene(
          id: "settings.connection",
          title: "设置 · 连接与 APP 信息",
          note: "服务器地址、账号、后端版本、凭据存储方式和刷新登录入口；标准登录用户。",
          initialPage: .connection,
        ),
        settingsScene(
          id: "settings.changelog",
          title: "设置 · 版本更新历史",
          note: "APP 版本、后端兼容说明和本地更新记录；不请求接口。",
          initialPage: .changelog,
        ),
        settingsScene(
          id: "settings.memoryOptimization",
          title: "设置 · 内存优化",
          note: "内存优化档位选择，修改后立即写入本机偏好。",
          initialPage: .memoryOptimization,
        ),
        settingsScene(
          id: "settings.mediaSourceSelection",
          title: "设置 · 默认聚合搜索来源",
          note: "展示后端 /media/source 返回的来源目录与“默认”选项。",
          initialPage: .mediaSourceSelection,
          behaviors: [UIPreviewBehaviorKey.settingsMediaSources: .data]
        ),
        settingsScene(
          id: "settings.mediaSourceSelectionFallback",
          title: "设置 · 默认聚合搜索来源（接口失败）",
          note: "来源目录请求失败时只记录日志并静默回退到内置来源，页面没有错误提示；这也是空目录时的表现。",
          initialPage: .mediaSourceSelection,
          behaviors: [UIPreviewBehaviorKey.settingsMediaSources: .failure]
        ),

        // MARK: 站点选择
        settingsScene(
          id: "settings.siteSelection",
          title: "设置 · 默认资源搜索站点（有数据）",
          note: "权威站点域 /site/ 返回 3 个站点（含 1 个停用），停用站点仍可勾选但会在搜索时被过滤。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .data]
        ),
        settingsScene(
          id: "settings.siteSelectionEmpty",
          title: "设置 · 默认资源搜索站点（空）",
          note: "权威站点域 /site/ 返回空列表，页面显示“暂无站点”。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .empty]
        ),
        settingsScene(
          id: "settings.siteSelectionLoading",
          title: "设置 · 默认资源搜索站点（加载中）",
          note: "权威站点域 /site/ 挂起，页面一直显示“站点状态 正在加载”。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .hang]
        ),
        settingsScene(
          id: "settings.siteSelectionFailure",
          title: "设置 · 默认资源搜索站点（失败）",
          note: "权威站点域 /site/ 失败，页面显示红色“站点加载失败，请重试”，按一下可重试。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .failure]
        ),
        settingsScene(
          id: "settings.subtitleSiteSelection",
          title: "设置 · 默认字幕搜索站点",
          note: "字幕搜索站点与资源站点分开保存，这里复用同一批站点数据。",
          initialPage: .subtitleSiteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .data]
        ),

        // MARK: 过滤规则
        settingsScene(
          id: "settings.hardFilter",
          title: "设置 · 硬过滤规则（有数据）",
          note: "自定义规则列表 + “不过滤”选项；硬过滤在搜索时直接排除不匹配结果。",
          initialPage: .hardFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .data]
        ),
        settingsScene(
          id: "settings.hardFilterEmpty",
          title: "设置 · 硬过滤规则（空）",
          note: "规则接口返回空列表，子页只剩“不过滤”。加载/失败状态只在根页“过滤规则”行展示，子页本身没有状态提示。",
          initialPage: .hardFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .empty]
        ),
        settingsScene(
          id: "settings.hardFilterLoading",
          title: "设置 · 硬过滤规则（加载中）",
          note: "规则接口挂起：当前子页没有加载指示，预期只看到“不过滤”；根页“过滤规则”行才显示“正在加载”。",
          initialPage: .hardFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .hang]
        ),
        settingsScene(
          id: "settings.hardFilterFailure",
          title: "设置 · 硬过滤规则（失败）",
          note: "规则接口失败：子页本身不展示失败原因，预期只看到“不过滤”；根页“过滤规则”行才显示“加载失败，按一下重试”。",
          initialPage: .hardFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .failure]
        ),
        settingsScene(
          id: "settings.softFilter",
          title: "设置 · 软过滤规则（有数据）",
          note: "与硬过滤共用规则列表和选择逻辑；软过滤只降低匹配优先级，不排除结果。",
          initialPage: .softFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .data]
        ),
        settingsScene(
          id: "settings.softFilterEmpty",
          title: "设置 · 软过滤规则（空）",
          note: "规则接口返回空列表，子页只剩“不过滤”。",
          initialPage: .softFilter,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .empty]
        ),

        // MARK: 播放
        settingsScene(
          id: "settings.playback",
          title: "设置 · 播放（后端 v3.2.6）",
          note: "应用内播放从 v3.2.6 起开放：显示应用内播放、主屏点击播放、自动连播开关。该版本尚未登记到兼容表，本场景不经过启动告警。",
          initialPage: .playback,
          environment: .playback
        ),
        settingsScene(
          id: "settings.playbackVersionRequirement",
          title: "设置 · 播放（后端版本不足）",
          note: "后端 v3.2.5 低于应用内播放要求的 v3.2.6，只显示版本说明和“重新读取后端版本”按钮。",
          initialPage: .playback,
        ),

        // MARK: 推荐与主屏
        settingsScene(
          id: "settings.recommendation",
          title: "设置 · 推荐页显示内容",
          note: "推荐页货架开关；货架来自真实 /recommend/sources fixture。",
          initialPage: .recommendation,
        ),
        settingsScene(
          id: "settings.topShelfSelection",
          title: "设置 · 主屏显示内容",
          note: "主屏不显示 / 推荐 / 探索三种模式选择，选择结果写入 TopShelfManager 的共享偏好。",
          initialPage: .topShelfSelection,
        ),
        settingsScene(
          id: "settings.topShelfRecommendations",
          title: "设置 · 主屏推荐内容",
          note: "从推荐货架里选择主屏展示的内容；货架来自真实推荐来源 fixture。",
          initialPage: .topShelfRecommendations,
        ),
        settingsScene(
          id: "settings.topShelfExplore",
          title: "设置 · 主屏探索",
          note: "主屏使用探索结果时的配置入口，包含来源、类型和筛选摘要。",
          initialPage: .topShelfExplore,
        ),
        settingsScene(
          id: "settings.topShelfExploreSources",
          title: "设置 · 主屏探索数据源",
          note: "探索来源列表，来源来自真实 /discover/sources fixture。",
          initialPage: .topShelfExploreSources,
        ),
        settingsScene(
          id: "settings.topShelfExploreField",
          title: "设置 · 主屏探索筛选（类型）",
          note: "打开探索筛选子页（TMDB 来源的“类型”字段），展示选项与当前选择。",
          initialPage: .topShelfExploreField("type")
        ),

        // MARK: 登录
        loginScene(
          id: "login.emptyForm",
          title: "登录 · 空表单",
          note: "服务器地址、用户名、密码都为空，登录按钮禁用。",
          draft: LoginDraft(
            serverURL: "",
            username: "",
            password: "",
            reason: .missingServerURL
          )
        ),
        loginScene(
          id: "login.filled",
          title: "登录 · 表单已填写",
          note: "三个字段齐全，登录按钮可聚焦；按下登录会走预览 login 钩子并切回标准会话（页面本身不跳转）。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          )
        ),
        loginScene(
          id: "login.missingServerURL",
          title: "登录 · 缺服务器地址",
          note: "只缺服务器地址，登录按钮禁用；客户端不校验地址格式，非空但不可达的地址只会在真实请求时失败。",
          draft: LoginDraft(
            serverURL: "",
            username: "preview-user",
            password: "preview-password",
            reason: .missingServerURL
          )
        ),
        loginScene(
          id: "login.submitting",
          title: "登录 · 提交中",
          note: "进入场景后自动提交，login 接口挂起：按钮显示进度与“登录中”，保持可聚焦。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .hang)
        ),
        loginScene(
          id: "login.failed",
          title: "登录 · 登录失败",
          note: "进入场景后自动提交，login 接口失败：顶部错误通知显示约 5 秒；通知消失后表单恢复可再次提交。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "wrong-password",
            reason: .credentialsRejected
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .failure)
        ),
        loginScene(
          id: "login.mfaUnsupported",
          title: "登录 · MFA 不支持提示",
          note: "用登录草稿的 mfaUnsupported 原因展示红色说明；这是真实登录失败后回到登录页的状态。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .mfaUnsupported
          )
        ),

        // MARK: 日志
        logScene(
          id: "log.records",
          title: "日志 · 有记录",
          note: "默认筛选为 WARN + 今天：展示 error/warning 记录，含 metadata 的卡片可在日志详情中查看。"
        ),
        logScene(
          id: "log.empty",
          title: "日志 · 空",
          note: "记录接口返回空列表，页面显示“没有符合条件的日志”。",
          behavior: .empty
        ),
        logScene(
          id: "log.loading",
          title: "日志 · 加载中",
          note: "记录读取挂起，页面显示加载指示。",
          behavior: .hang
        ),
        logScene(
          id: "log.failure",
          title: "日志 · 读取失败",
          note: "读取失败映射为 LogStorageIssue.readFailed，页面显示橙色错误和“重新读取”。",
          behavior: .failure
        ),
        logScene(
          id: "log.longList",
          title: "日志 · 大量记录（滚动）",
          note: "36 条记录用于验证长列表滚动与焦点移动；当前 LogViewerView 没有“自动滚动/跟随最新”行为。",
          longList: true
        ),
      ]
    )
  }

  // MARK: - 场景构造

  private static func settingsScene(
    id: String,
    title: String,
    note: String,
    initialPage: SystemSettingsPage,
    environment: UIPreviewEnvironment = .standard,
    behaviors: [String: UIPreviewBackend.Behavior] = [:]
  ) -> UIPreviewScene {
    UIPreviewScene.page(
      id: id,
      title: title,
      note: note,
      environment: environment,
      behaviors: behaviors
    ) {
      UIPreviewSettingsPage(page: initialPage)
    }
  }

  private static func loginScene(
    id: String,
    title: String,
    note: String,
    draft: LoginDraft,
    environment: UIPreviewEnvironment = .loggedOut
  ) -> UIPreviewScene {
    UIPreviewScene.page(id: id, title: title, note: note, environment: environment) {
      UIPreviewLoginForm(draft: draft)
    }
  }

  private static func logScene(
    id: String,
    title: String,
    note: String,
    behavior: UIPreviewBackend.Behavior = .data,
    longList: Bool = false
  ) -> UIPreviewScene {
    var environment = UIPreviewEnvironment.standard
    environment.behaviors[UIPreviewBehaviorKey.logRecords] = behavior
    if longList {
      environment.context[UIPreviewContextKey.logLongList] = "1"
    }
    return UIPreviewScene.page(id: id, title: title, note: note, environment: environment) {
      UIPreviewSettingsPage(page: .logs)
    }
  }

  private static func loginEnvironment(
    autoSubmit: Bool,
    behavior: UIPreviewBackend.Behavior
  ) -> UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.loggedOut
    if autoSubmit {
      environment.context[UIPreviewContextKey.loginAutoSubmit] = "1"
      environment.behaviors[UIPreviewBehaviorKey.loginAccessToken] = behavior
    }
    return environment
  }
}

// MARK: - 场景容器

/// 直接渲染真实设置页，从指定子页开始（不经过设置根页滚动）。
private struct UIPreviewSettingsPage: View {
  let page: SystemSettingsPage

  var body: some View {
    SystemView(isSelected: true, apiService: .shared, initialPage: page)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// 登录表单：用 `LoginDraft` 预填真实 `LoginViewModel` 的初始值。
/// `LoginView` 目前的 ViewModel 不可注入，因此通过 APIService 的内存草稿初始化。
private struct UIPreviewLoginForm: View {
  init(draft: LoginDraft) {
    APIService.shared.loginDraft = draft
  }

  var body: some View {
    LoginView()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(white: 0.1))
  }
}
#endif
