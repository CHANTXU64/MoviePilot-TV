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
        .page(
          id: "settings.backendVersionTooNew",
          title: "设置 · 后端版本较新告警",
          note: "后端 v3.3.0 高于已登记的最新兼容版本 v3.2.5，启动后弹出“MoviePilot 后端版本较新”告警；使用独立预览地址，避免和其它场景的“已确认”记录串用。",
          environment: UIPreviewEnvironment(
            token: UIPreviewFixtures.userToken(),
            baseURL: "http://moviepilot-ui-preview.local:3002",
            backendVersion: "v3.3.0"
          )
        ) {
          RealAppContentView()
        },
        .page(
          id: "settings.backendVersionUnavailable",
          title: "设置 · 后端版本无法确认告警",
          note: "全局设置没有返回 BACKEND_VERSION（真实环境对应 /system/settings 失败或字段缺失），启动告警显示“无法确认 MoviePilot 后端版本”与“未取得后端版本号”；使用独立预览地址。",
          environment: UIPreviewEnvironment(
            token: UIPreviewFixtures.userToken(),
            baseURL: "http://moviepilot-ui-preview.local:3003",
            backendVersion: nil
          )
        ) {
          RealAppContentView()
        },
        settingsScene(
          id: "settings.rootNoPermissions",
          title: "设置 · 根页面（无任何权限）",
          note: "普通用户且探索/搜索/订阅/管理权限都没有：根页只剩连接与 APP 信息，其它配置分节全部隐藏。",
          initialPage: .root,
          environment: UIPreviewEnvironment.limited(permissions: [])
        ),
        settingsScene(
          id: "settings.adminPageNoSuperuser",
          title: "设置 · 管理员子页（无超级管理员权限）",
          note: "非超级管理员直接进入硬过滤子页：canConfigureCustomFilters 为 false，子页内容整页隐藏；正常从根页进入时不会出现这个入口。",
          initialPage: .hardFilter,
          environment: UIPreviewEnvironment.limited(
            permissions: Set([.discovery, .search, .subscribe])
          )
        ),
        .page(
          id: "login.sessionExpiredBanner",
          title: "登录 · 登录失效提示（预览叠加）",
          note: "预览跳过 /user/current 校验，无法触发真实 401 失效流程；当前生产代码也没有全局“登录已失效”提示（401 会清空会话并回到登录页）。本场景在未登录根容器上叠加该文案的全局错误条，仅用于预览提示样式与位置，不代表现有行为。",
          environment: .loggedOut
        ) {
          UIPreviewBannerHost(type: .error, message: "登录已失效") {
            RealAppContentView()
          }
        },
        settingsScene(
          id: "settings.rootRulesLoading",
          title: "设置 · 根页面（过滤规则加载中）",
          note: "进入设置根页会拉取自定义过滤规则，“规则状态”行显示“正在加载”；硬过滤/软过滤入口此时已可见。",
          initialPage: .root,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .hang]
        ),
        settingsScene(
          id: "settings.rootRulesTimeout",
          title: "设置 · 根页面（过滤规则超时）",
          note: "规则接口超时：“规则状态”行显示“加载失败，点击重试”，按一下会重新请求；页面不展示具体错误类型。",
          initialPage: .root,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .error(.networkTimeout)]
        ),
        settingsScene(
          id: "settings.rootRulesUnauthorized",
          title: "设置 · 根页面（过滤规则未授权）",
          note: "规则接口返回 401：根页仍只显示“加载失败，点击重试”，不会因为鉴权失败退出设置页。",
          initialPage: .root,
          behaviors: [UIPreviewBehaviorKey.settingsCustomRules: .error(.unauthorized)]
        ),
        settingsScene(
          id: "settings.rootRulesServerMessage",
          title: "设置 · 根页面（过滤规则服务端报错）",
          note: "规则接口返回业务错误消息：根页同样只显示“加载失败，点击重试”，服务端消息不落 UI。",
          initialPage: .root,
          behaviors: [
            UIPreviewBehaviorKey.settingsCustomRules:
              .error(.serverMessage("自定义过滤规则配置损坏，请在后端设置中修复"))
          ]
        ),

        // MARK: 设置子页
        settingsScene(
          id: "settings.connection",
          title: "设置 · 连接与 APP 信息",
          note: "服务器地址、账号、后端版本、凭据存储方式和刷新登录入口；标准登录用户。",
          initialPage: .connection,
        ),
        settingsScene(
          id: "settings.connectionEnvFailure",
          title: "设置 · 连接（环境版本读取失败）",
          note: "/system/env 超时：连接页只记录日志，MoviePilot 版本回退到全局设置里的 v3.2.5，页面没有错误提示。",
          initialPage: .connection,
          behaviors: [UIPreviewBehaviorKey.settingsEnv: .error(.networkTimeout)]
        ),
        .page(
          id: "settings.connectionReloginTimeout",
          title: "设置 · 连接（刷新登录超时）",
          note: "刷新登录凭据失败时，连接页会在“最近状态”行显示“刷新失败: …”；预览无法自动按下刷新按钮，这里用全局错误条叠加同一文案。",
          environment: .standard
        ) {
          UIPreviewBannerHost(
            type: .error,
            message: "刷新失败: \(UIPreviewErrorKind.networkTimeout.makeError().localizedDescription)"
          ) {
            UIPreviewSettingsPage(page: .connection)
          }
        },
        .page(
          id: "settings.connectionReloginUnauthorized",
          title: "设置 · 连接（刷新登录失效）",
          note: "刷新凭据时口令已失效：真实页面在“最近状态”行显示“刷新失败: 登录已失效”，仍停留在连接页；这里用全局错误条叠加同一文案。",
          environment: .standard
        ) {
          UIPreviewBannerHost(type: .error, message: "刷新失败: 登录已失效") {
            UIPreviewSettingsPage(page: .connection)
          }
        },
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
        settingsScene(
          id: "settings.mediaSourceSelectionLoading",
          title: "设置 · 默认聚合搜索来源（加载中）",
          note: "来源目录请求挂起：页面先显示内置来源，没有任何加载指示；目录返回后才会替换成后端来源。",
          initialPage: .mediaSourceSelection,
          behaviors: [UIPreviewBehaviorKey.settingsMediaSources: .hang]
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
          id: "settings.siteSelectionTimeout",
          title: "设置 · 默认资源搜索站点（超时）",
          note: "权威站点域 /site/ 请求超时：页面只显示统一的“站点加载失败，请重试”，不区分超时类型。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .error(.networkTimeout)]
        ),
        settingsScene(
          id: "settings.siteSelectionDecoding",
          title: "设置 · 默认资源搜索站点（解析失败）",
          note: "站点响应解析失败：页面仍只显示“站点加载失败，请重试”，错误类型不落 UI。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .error(.decoding)]
        ),
        settingsScene(
          id: "settings.siteSelectionUnauthorized",
          title: "设置 · 默认资源搜索站点（未授权）",
          note: "站点接口返回 401：页面显示“站点加载失败，请重试”，不会在设置页跳转登录。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .error(.unauthorized)]
        ),
        settingsScene(
          id: "settings.siteSelectionGateway503",
          title: "设置 · 默认资源搜索站点（网关 503）",
          note: "网关返回 503：页面显示“站点加载失败，请重试”，按一下重新请求。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .error(.gateway(503))]
        ),
        settingsScene(
          id: "settings.siteSelectionHTTP500",
          title: "设置 · 默认资源搜索站点（HTTP 500）",
          note: "站点接口返回 HTTP 500：页面显示“站点加载失败，请重试”。",
          initialPage: .siteSelection,
          behaviors: [UIPreviewBehaviorKey.settingsSites: .error(.http(500))]
        ),
        settingsScene(
          id: "settings.siteSelectionServerMessage",
          title: "设置 · 默认资源搜索站点（服务端消息）",
          note: "站点接口返回业务错误消息：页面仍显示“站点加载失败，请重试”，服务端消息不落 UI。",
          initialPage: .siteSelection,
          behaviors: [
            UIPreviewBehaviorKey.settingsSites: .error(.serverMessage("站点服务暂时不可用"))
          ]
        ),
        settingsScene(
          id: "settings.siteSelectionSearchOnly",
          title: "设置 · 默认资源搜索站点（只有搜索权限）",
          note: "用户有 search 但没有 manage 权限：设置页仍可进入站点子页。生产会因无管理权限降级到 /site/rss，预览钩子固定返回权威域 fixture，列表内容不反映降级来源。",
          initialPage: .siteSelection,
          environment: UIPreviewEnvironment.limited(permissions: Set([.search])),
          behaviors: [UIPreviewBehaviorKey.settingsSites: .data]
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
        .page(
          id: "settings.invalidFilterRuleEffect",
          title: "设置 · 非法过滤规则的搜索反馈",
          note: "把硬过滤规则设为一条 include 非法正则的规则后发起资源搜索：过滤阶段抛出 FilterError，结果页显示“自定义过滤规则无效：正则表达式「[unclosed」无法编译”。离开场景会恢复原规则选择。",
          environment: invalidFilterRuleEnvironment
        ) {
          UIPreviewInvalidFilterRuleResult(request: invalidFilterRuleRequest)
        },

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
        loginScene(
          id: "login.missingPassword",
          title: "登录 · 缺密码（按钮禁用）",
          note: "服务器地址和用户名已填、密码为空：登录按钮禁用；客户端不会提示具体缺哪个字段。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "",
            reason: .missingCredentials
          )
        ),
        loginScene(
          id: "login.credentialsRejected",
          title: "登录 · 用户名或密码错误",
          note: "进入场景后自动提交，login 钩子抛 credentialsRejected：顶部通知显示“用户名或密码错误”，约 5 秒后消失；表单保留账号与密码，可再次聚焦登录重试。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "wrong-password",
            reason: .credentialsRejected
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.credentialsRejected))
        ),
        loginScene(
          id: "login.mfaRejected",
          title: "登录 · MFA 账号登录失败",
          note: "进入场景后自动提交，login 钩子抛 mfaUnsupported：顶部通知与红色说明同时显示“当前账号已开启 MFA，TV 端暂不支持，请关闭 MFA 后重试”。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.mfaUnsupported))
        ),
        loginScene(
          id: "login.unauthorized",
          title: "登录 · 登录接口 401",
          note: "进入场景后自动提交，login 钩子抛 unauthorized：顶部通知显示“登录失败: 登录已失效”，表单恢复可重试。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.unauthorized))
        ),
        loginScene(
          id: "login.timeout",
          title: "登录 · 请求超时",
          note: "进入场景后自动提交，login 钩子抛 networkTimeout：顶部通知显示“登录失败: <系统超时文案>”，表单恢复可重试。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.networkTimeout))
        ),
        loginScene(
          id: "login.offline",
          title: "登录 · 服务器不可达",
          note: "进入场景后自动提交，login 钩子抛 networkOffline：顶部通知显示“登录失败: <系统离线文案>”，表单恢复可重试。",
          draft: LoginDraft(
            serverURL: "http://192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.networkOffline))
        ),
        loginScene(
          id: "login.invalidServerURL",
          title: "登录 · 服务器地址无效",
          note: "服务器地址缺少 scheme，login 钩子抛 invalidURL：顶部通知显示“登录失败: 无效的请求地址”。真实环境在登录前归一化地址时就会失败；预览钩子不校验地址，错误由 behavior 注入。",
          draft: LoginDraft(
            serverURL: "192.168.1.5:3000",
            username: "preview-user",
            password: "preview-password",
            reason: .missingCredentials
          ),
          environment: loginEnvironment(autoSubmit: true, behavior: .error(.invalidURL))
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
        logScene(
          id: "log.timeoutFailure",
          title: "日志 · 读取超时",
          note: "读取超时同样映射为 LogStorageIssue.readFailed：橙色显示“部分日志读取失败，请重试。”，并提供“重新读取”。",
          behavior: .error(.networkTimeout)
        ),
        logScene(
          id: "log.http500Failure",
          title: "日志 · 读取 HTTP 500",
          note: "读取抛 HTTP 500：页面不展示状态码，只显示统一的“部分日志读取失败，请重试。”。",
          behavior: .error(.http(500))
        ),
        logScene(
          id: "log.decodingFailure",
          title: "日志 · 读取解析失败",
          note: "读取结果解析失败：仍映射为 readFailed，页面不区分解码错误与网络错误。",
          behavior: .error(.decoding)
        ),
        logScene(
          id: "log.levelFilteredEmpty",
          title: "日志 · 级别筛选为空",
          note: "fixture 只返回 INFO/DEBUG 记录；默认 WARN 筛选得到空列表，显示“没有符合条件的日志”，切到 DEBUG/INFO 可看到记录。",
          context: [UIPreviewContextKey.logOnlyInfo: "1"]
        ),
        logScene(
          id: "log.longMultilineRecord",
          title: "日志 · 超长多行记录",
          note: "默认 WARN 筛选下可见一条 error：卡片最多 6 行并截断超长请求行，选中后进入详情可查看完整多行堆栈。",
          context: [UIPreviewContextKey.logLongMessage: "1"]
        ),
        logScene(
          id: "log.maintenanceFailure",
          title: "日志 · 清理失败",
          note: "读取结果附带 maintenanceFailed：橙色显示“日志清理失败，请重试。”；页面没有手动清理按钮，错误条旁只有“重新读取”。",
          context: [UIPreviewContextKey.logMaintenanceFailure: "1"]
        ),
        logScene(
          id: "log.writeFailure",
          title: "日志 · 保存失败",
          note: "读取结果附带 writeFailed：橙色显示“日志保存失败，部分新日志可能未记录。”，已有记录继续展示。",
          context: [UIPreviewContextKey.logWriteFailure: "1"]
        ),
        logScene(
          id: "log.recordTooLarge",
          title: "日志 · 单条过大未保存",
          note: "读取结果附带 recordTooLarge：橙色显示“有日志超过单条大小限制，未保存。”，已有记录继续展示。",
          context: [UIPreviewContextKey.logRecordTooLarge: "1"]
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
    longList: Bool = false,
    context: [String: String] = [:]
  ) -> UIPreviewScene {
    var environment = UIPreviewEnvironment.standard
    environment.behaviors[UIPreviewBehaviorKey.logRecords] = behavior
    if longList {
      environment.context[UIPreviewContextKey.logLongList] = "1"
    }
    for (key, value) in context {
      environment.context[key] = value
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

  /// 非法过滤规则场景：规则 fixture 追加损坏规则，资源搜索在过滤阶段抛 FilterError。
  private static var invalidFilterRuleEnvironment: UIPreviewEnvironment {
    var environment = UIPreviewEnvironment.standard
    environment.context[UIPreviewContextKey.settingsInvalidRule] = "1"
    environment.behaviors[UIPreviewBehaviorKey.settingsCustomRules] = .data
    return environment
  }

  private static var invalidFilterRuleRequest: ResourceSearchRequest {
    let media = UIPreviewFixtures.baseTVMedia(id: 88_001, title: "边境信号")
    return ResourceSearchRequest(
      keyword: "tmdb:88001",
      type: media.type,
      area: nil,
      title: media.title,
      year: media.year,
      season: 1,
      mediaInfo: media,
      sites: nil
    )
  }
}

// MARK: - 场景容器

/// 直接渲染真实设置页，从指定子页开始（不经过设置根页滚动）。
private struct UIPreviewSettingsPage: View {
  let page: SystemSettingsPage

  var body: some View {
    ZStack {
      AppBackground()
      SystemView(isSelected: true, apiService: .shared, initialPage: page)
    }
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
      .background(AppBackground())
  }
}

/// 先写入“非法规则”选择，再驱动真实资源结果页；离开时恢复原来的硬过滤规则选择。
private struct UIPreviewInvalidFilterRuleResult: View {
  let request: ResourceSearchRequest

  @StateObject private var imageLifecycle = PageImageLifecycle()
  @State private var isSettingsReady = false
  @State private var previousHardRuleID: String?
  @State private var didOverrideHardRule = false

  var body: some View {
    ZStack {
      AppBackground()
      Group {
        if isSettingsReady {
          ResourceResultView(request: request, imageLifecycle: imageLifecycle)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      if !didOverrideHardRule {
        let viewModel = SystemViewModel(apiService: .shared)
        previousHardRuleID = viewModel.selectedHardFilterRuleId
        viewModel.selectedHardFilterRuleId = "rule-invalid-regex"
        didOverrideHardRule = true
      }
      // 资源搜索按后端版本选择分页/旧 SSE 协议；通用资源页可能来自其它场景，这里按当前环境重新读取。
      _ = try? await APIService.shared.fetchSettings()
      isSettingsReady = true
    }
    .onDisappear {
      guard didOverrideHardRule else { return }
      SystemViewModel(apiService: .shared).selectedHardFilterRuleId = previousHardRuleID
    }
  }
}
#endif
