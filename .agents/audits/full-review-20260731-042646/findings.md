# MoviePilot-TV 从零全量代码审计：发现台账

审计目录：`full-review-20260731-042646`
基线：detached HEAD `4a997919983566ec208e777acf7798a95e2f9e8f`，启动时工作树干净。
状态使用：`候选`、`已确认`、`已驳回`、`降级`、`未验证`、`已修复`、`用户决定跳过`、`部分修复`；处置细节以括号或分号附注，如 `已修复（`提交号`）`、`未验证；用户决定跳过修复`。

## 编号规则

- 正式候选按首次写入顺序分配 `F-001`、`F-002`……
- 没有文件位置、触发路径和可复核证据的事项只进入“待调查问题”，不分配正式发现编号。
- 主审结论只能是 `候选`；独立复核或争议裁决后才能改为其他状态。

## 发现总表

| ID | 状态 | 严重度 | 审查单元 | 位置 | 摘要 | 主审证据 | 复核/裁决证据 | 跨端结论 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F-001 | 已修复 | P3 | M001-B | `Models.swift:187-224` | `FlexibleBool` 不清理换行，带行尾的真值字符串静默解为 `false` | M001-B 主审完整追踪所有包装类型调用者及相关测试 | verify_m001_b 独立复现解析分支、全量调用者和测试缺口；无新候选 | TV 端缺陷已确认；修复后字符串分支改用 `.whitespacesAndNewlines`，带行尾真值不再误降级，用户批准 |
| F-002 | 已修复（`ff4ea14`） | P2 | M001-C | `Models.swift:578-651`；嵌套根因在 `Person`/`SubscribeShare` 解码器 | 后台媒体解码继续读取 MainActor 图片配置 | M001-C 主审追踪后台入口、嵌套解码器、工程隔离设置与测试 | verify_m001_c 独立确认静态隔离冲突并限定 Release/触发边界 | TV 本地隔离风险已确认；实际携带字段及 Release 表现未验证 |
| F-003 | 已修复（`0cfeb12`） | P2 | M001-C/I001→G02 | 分季订阅快照季号边界 | missing/null会被summary安全丢弃、S00合法；仅负季号仍进入字典、状态与订阅/取消目标 | G02主审提出限缩，rounda_g02_third按missing/null/negative/S00矩阵确认当前控制流 | summary入口只拒绝负季号并保留0；不改S00 | 纯TV负季号不变量已确认；后端是否保证非负未验证 |
| F-004 | 降级（用户决定跳过） | P3 | M001-C | `Models.swift:612,614-616`，持有/编码在 `728,879,917,1000-1004` | `rawPayload` 与强类型字段重复持有深层 JSON | M001-C 主审确认唯一生产用途及分页/预加载持有路径 | verify_m001_c 确认静态重复持有，但无真机量化，P2→P3 | 静态风险成立；无真机实测影响、rawPayload 承担 re-encode 保字段职责，用户决定跳过 |
| F-005 | 已修复 | P3 | M001-C | `Models.swift:433-487`，限 Statistic/DownloaderInfo 非可选字段 | 非可选字段的属性默认值不能容忍 Decodable 缺键/null | M001-C 主审追踪 Dashboard 刷新和现有测试缺口 | verify_m001_c 独立确认合成解码与顺序发布混合快照 | 已按模型边界 `decodeIfPresent ?? 0` 容缺；字段齐全时行为不变，用户批准 |
| F-006 | 已修复（`49b887e`+`f807692`） | P2 | M001-A→G02 | Subscribe lookup/取消identity | 2026-08-11 对照 Web v2.15.1 后收窄为 lookup 响应的 raw 数值 `0` 遮蔽合法 fallback；负数在 Web 中为 truthy，不是缺陷 | 已由 `49b887e`（truthyNumericIdentifier）+`f807692`（lookup 应用）修复：raw 数值只跳过 `0`、保留负数，再回退不透明 legacy 值 | 补 lookup 的 0/负数/fallback 矩阵；不引入“正数限定”差异 | Web v2.15.1 规则已确认；真实后端异常数据分布未验证 |
| F-007 | 已修复（`bb07772`） | P1 | M001-A→I008 | Header/预热/跳转/POST 身份链 | source-only 主身份会丢失，且启发式TMDB可覆盖完整详情权威ID并创建、暂停错误订阅 | 既有转换审查与I008整文件主审闭合四个创建入口及X≠Y序列 | review_a001_h从当前HEAD独立确认P1；复用共享draft factory与纯TMDB仲裁，不扩POST schema | 修复已完成：`bb07772`；当前后端/Web合同、构建、381条非后端兼容测试与独立复审通过 |
| F-008 | 已修复（`789e9a7`） | P2 | M001-A→W015 | `APIService.search/fork` 与 Home/Sheet/监听方 | 搜索/Fork 完成只清缓存，不刷新已发布状态 | M001-A双审闭合；W015双审确认Fork成功后GET失败/取消编辑均永不发通知 | mutation成功出口恰好发布一次，不依赖后续GET/编辑保存 | 修复已完成：`789e9a7`；独立复审、构建及386条非后端兼容测试通过 |
| F-009 | 已修复（`4c69ec9`） | P3 | B001 | `AppVersionInfo.swift:74-98`、`ContentViewModel.swift:193-201` | 无法解析的非空后端版本被误报为“版本过低” | B001 主审闭合解析、警告分类与测试缺口 | verify_b001 独立确认三态合流矛盾及测试诊断同类误述 | 修复完成：`4c69ec9`；三态提示及兼容巡检诊断已统一，官方是否产生畸形格式仍未验证 |
| F-010 | 已修复（`4c69ec9`） | P3 | B001 | `AppVersionInfo.swift:50-66` | 前置分隔符被当作合法版本核心 | B001 主审核对 Swift split 语义与 malformed 测试意图 | verify_b001 独立确认 split 丢空段与缺失边界测试 | 修复完成：`4c69ec9`；前置分隔符已拒绝并保留合法前后缀合同 |
| F-011 | 已修复（`63767f9`） | P2 | M001-C/M001-D→V016/W012 当前合同复核 | `Models.swift` TorrentInfo、`AddDownloadRequest`、`APIService.addDownload` | 搜索结果经TV强类型解码再编码时丢失四个官方TorrentInfo字段 | 当前官方Web直传对象；后端生产并消费`site_cookie/site_ua/site_proxy`，条件消费`site_downloader` | 三名只读代理分别闭合TV/后端、Web与窄裁决；当前官方v2 HEAD已核新鲜度 | 修复已完成（`63767f9`）；通用MediaInfo嵌套raw/插件依赖仍未验证 |
| F-012 | 已修复（`58c7e81`） | P2 | M001-A→I014当前合同复核 | `Subscribe.navigationMediaInfo()`及Home详情入口 | 漏AniList/统一身份，并让legacy错误抢在raw ID前，违反canonical→raw→legacy顺序 | 三路当前TV/Web/后端复核确认七字段正式合同、唯一生产调用方和下游详情/mutation传播 | 单点按规范优先级解析后写入source/media_id；不扩通用MediaInfo legacy字段 | 修复已完成：`58c7e81`；canonical-only TMDB group raw限制另为用户路径未验证P3边界 |
| F-013 | 已驳回；用户决定跳过修复 | P2 | M001-A/M001-D→当前Web/后端合同复核 | `MediaInfo` legacy `mediaid` 回退 | TV未解码legacy字段，但当前官方Web类型/helper与后端响应schema也不支持仅legacy `MediaInfo` | Web v2.15.5详情/搜索/下载/订阅入口均从结构化身份生成请求键；同名路由参数不是payload字段 | 不给TV新增差异化兜底；删除正式清单中过时现状声明 | 当前合同反证成立；用户决定跳过修复 |
| F-014 | 已驳回 | P3 | M001-D→G02 | 来源选择的空白prefix回退 | 当前规范化会trim并丢弃空白`mediaid_prefix`，随后继续采用有效`source`；原遮蔽链不再成立 | G02主审及两名不同纠偏复核均按当前HEAD确认反证，旧M001-D结论被覆盖 | 无生产修复；只补空白prefix＋有效source回归 | 当前TV缺陷驳回；上游来源优先级合同未验证 |
| F-015 | 已修复（`f04f73f`） | P3 | M001-D | `Models.swift:1199-1203` 及订阅调用者 | `canDirectlySubscribe == false` 被当作“必为电视剧” | review_m001_d 闭合合集/未知类型到无动作或错误分季入口 | verify_m001_d 独立确认 handler/菜单/Header 三条路径 | 修复已完成：`f04f73f`；当前 Web 合同、独立复审及 398 条本地测试主体通过 |
| F-016 | 已驳回 | P3 | B002 | `Formatters.swift:6-18` 及大小调用者 | ByteCountFormatter 的精度、零值和 locale 仍为系统自适应 | B002 主审核对 SDK 默认与 13 个调用表达式 | verify_b002 证明这是注释承诺范围内的 Apple 本地化取舍 | 用户决定跳过修复；仅在未来明确固定 Web 文案契约时重开 |
| F-017 | 未验证；用户决定跳过修复 | P3 | B002 | `Formatters.swift:79-90`、`CustomFilterService.swift:227-232` | 无时区日期固定按上海解释且过滤层重复假设 | B002 主审核对 SwiftDate 实现、调用者和 fixture | verify_b002 确认行为但无法判定源时区契约 | 用户决定跳过修复；三类字段时区及非上海部署未验证 |
| F-018 | 已修复（`94f18f2`） | P3 | B002 | `Formatters.swift:24-32`、TorrentCard 网格调用链 | 每次卡片渲染重新编译固定季集正则 | B002 主审确认唯一高频调用与无性能测试 | verify_b002 以相邻静态正则模式确认重复工作并限制为低优先级 | 修复已完成：`94f18f2`；独立复审、构建及399条非后端兼容测试通过 |
| F-019 | 已修复（`90b40b4`） | P1 | B003→G06 | `KingfisherCookies.swift` 与 API 会话转换 | 登出/切服未失效共享图片 Cookie | 既有双审闭合 TV 生命周期；G06 两票结合当前后端资源 Cookie 签发/刷新链确认同主机换端口及账号转换风险 | 仅删除旧会话已知主机/path 下资源 Cookie并取消对应任务；不清系统全部 Cookie | 修复已完成：`90b40b4`；最终独立复审通过，聚焦会话/持久化测试8/8通过 |
| F-020 | 已修复（`90b40b4`） | P1 | B003→I010 | Kingfisher 全部调用者、缓存与 downloader | URL-only hit/在途合并可绕过新账号Cookie鉴权并返回旧账号图片 | 既有双审确认隔离缺口；I010主审、独立复核与第三裁闭合cache/downloader/logout全链并升级条件P1 | 受保护资源使用opaque session namespace cache key并隔离/排空旧downloader；公共图继续共享 | 修复已完成：`90b40b4`；公共图继续共享，真实后端套件未运行 |
| F-021 | 已修复（`a0adaab`） | P3 | B002 复核新增 / M001-E | `DownloadTaskView.swift`、`TransferHistoryView.swift` 与可选大小模型 | 未知大小被显示成真实零值 | verify_b002 确认可选模型状态、调用者折叠和测试 fixture | review_m001_e 独立确认字段可选、缺失 fixture 与三个显示出口 | 修复已完成（`a0adaab`）；独立复审通过，Simulator clean build 与本地测试427/427通过（跳过5个真实后端兼容套件） |
| F-022 | 已修复（`06d9fe5`） | P2 | M001-E | `Models.swift` 资源嵌套模型与 SSE/fallback | 单条资源缺字段可令整个搜索失败 | review_m001_e 闭合严格嵌套解码、SSE 终止和同步 fallback | verify_m001_e 独立确认当前流首错终止、fallback 同批再失败及测试盲点 | 修复已完成（`06d9fe5`）；最终独立复审通过，Simulator clean build 与本地测试428/428通过（跳过5个真实后端兼容套件） |
| F-023 | 已修复（`af67839`） | P3 | M001-E | `MediaServerPlayItem.title` 与最近媒体整批解码 | 单项缺/null title 令服务器最新内容整批为空 | review_m001_e 闭合 API→Home 链及 fixture 缺口 | verify_m001_e 独立确认数组原子解码与 Home 清空行为 | 修复已完成（`af67839`）；当前后端允许 title 为空，独立复审通过，本地测试 430/430 通过 |
| F-024 | 用户决定跳过 | P1 | M001-E→W017 | `DownloadingInfo.id` 与轮询合并 | 缺hash时无分隔可变fallback可碰撞，重复ID下一轮触发不可捕获Dictionary trap；全空UUID只导致每轮重建 | 当前Web/后端复核确认schema允许缺hash、内置下载器通常给唯一hash；Web共享重复key覆盖但无TV必崩字典链 | hash优先、name兜底；显式循环检测旧/新快照重复并失败关闭，禁止trapping initializer | 用户基于低频异常边界决定跳过修复；普通name/UUID身份抖动仍P3 |
| F-025 | 已修复（`8050051`） | P3 | M001-E | `MediaServerPlayItem.id` 与首页十秒刷新 | 有稳定raw_id仍拼入可变link；稀疏响应又忽略server_id/item_id并生成UUID | 当前Web有id时只用id；后端六个内置producer通常提供稳定id，但link可随host/playhost/token变化 | 服务器类型作用域下按raw→server/item→link→UUID取值，分支标签+长度前缀防碰撞 | 修复完成（`8050051`），clean build、433/433本地测试及独立复审通过 |
| F-026 | 已修复（`90b40b4`） | P2 | B003 复核新增 / S004→I010 | `Paginator.swift:114-129` 与 12 个图片 provider | 无 Cookie 预取可劫持后续有 Cookie 图片请求 | 既有双审闭合；I010独立复核再次确认Search/MediaCard调用链仍使用无modifier预取 | 预取与显示复用同一认证选项；会话持久缓存隔离仍归F-020 | 修复已完成：`90b40b4`；预取与显示共用受保护资源选项 |
| F-027 | 已修复（`90b40b4`） | P1 | B004→W015/W018-A/W020-C→I003/I010 | APIService鉴权重放与session/permission owner | 旧会话可修改新会话；A mutation的401/403可读取B当前凭据/baseURL并把原body重放到B，旧login也可撤销logout或注销B | 既有双审及I003闭合；I010补A订阅lookup后切B、后续DELETE读取当前单例凭据的跨会话链 | 单调session epoch加requiredPermission；多阶段lookup→mutation共用owner并在后续请求前复核 | 修复已完成：`90b40b4`；请求不自动重放并绑定epoch/operation |
| F-028 | 已驳回；用户决定跳过修复 | P2 | B004→R001 | `validateTokenSilently` 与权限 UI/缓存 | 前台/Tab 校验丢弃最新权限快照 | 当前三方复核确认Web同样不做运行中权限热刷新，TV冷启动/403失效链完整，90b40b4已闭合正式发布后的UI/cache收敛 | 保持token有效性校验，不新增权限热同步 | 用户决定跳过；管理员运行中改权限由重登/重启恢复 |
| F-029 | 已修复（`90b40b4`） | P2 | B004 | 手动 relogin/no-access 分支 | 无功能权限响应时保留旧权限会话 | review_b004 对比手动刷新与冷启动/App 更新出口 | verify_b004 独立确认三个重登出口语义分裂 | 修复完成（`90b40b4`）；空permissions与Web默认权限差异另归F-030核对 |
| F-030 | 已修复（`ee5dcb4`） | 条件性P1 | B004→G06 | `UserPermissions.swift` permissions 解码 | 任一非 Bool 权限项令整个 Token 解码失败 | 当前官方Web正常保存嵌套`features`对象，后端泛型dict不校验并在login/current原样返回；TV会在权限判断前整批解码失败 | 单一共享边界只读取四个已知Bool；未知/坏值忽略，空/缺权限默认语义拆项 | 修复完成（`ee5dcb4`）；clean build、435/435本地测试及独立复审通过 |
| F-031 | 降级；用户决定跳过 | 条件性P3 | B004→G06 | token 登录/恢复/登录态判断 | 纯空白 access token 被视为已登录且可恢复权限 | `90b40b4`已拒绝空串；当前官方后端JWT producer不产纯空白，Web也未增加同类校验 | 不为损坏存储或非官方兼容端增加TV差异化硬化，保留内部tokenless currentUser哨兵 | 用户决定跳过；若未来官方producer可达再重开 |
| F-032 | 已修复 | P2 | M001-E 复核新增 / S004 裁决 | `Context.meta_info` 与 TorrentCard/TorrentsResultView | torrent-only 结果解码成功但静默空渲染 | verify_m001_e 以多个 torrent-only fixture 闭合非空计数→EmptyView 链 | review_s004 独立确认模型合法、过滤保留、非零计数与卡片 EmptyView | `TorrentCard` 已按 Web 降级渲染；当前 MP 官方搜索链正常生成 `MetaInfo`，保留该兼容防御 |
| F-033 | 已修复 | P2 | S004 | Paginator 错误状态与全部生产调用者 | 错误状态无人消费，错误上限后无保留列表恢复 | review_s004 核对 13 实例、全部 View 与测试只手动重试 | verify_s004 独立确认零消费者、错误上限与页面误空态 | 连续失败达到三次上限后统一通知用户重试；不增加重试按钮 |
| F-034 | 用户决定跳过 | P2 | S004→V011-F | SharedMediaFetcher 与 Paginator 空页语义 | 非终止空批被当成终页，稀疏媒体类型永久截断 | review_s004 构造六页异类/第七页目标序列；verify_a001_h 从 actor 实现重走 | verify_s004 独立确认 buffer/hasMore 与终页契约 | 保留最多扫描六页的边界，接受极端类型分布下可能漏项 |
| F-035 | 用户决定跳过 | P2 | S004→V011-C→G04 | Paginator/Search in-flight Task 生命周期 | Task跨await强持有owner且页面离场无owner级取消；显式cancel和新搜索的generation防旧发布本身有效 | 既有双审闭合强持有；全新G04 clean-room复核收窄为owner离场生命周期并升级P2 | owner/session级显式取消共享搜索；不重写已有generation屏障 | 用户接受慢请求离页后继续占用资源的低频影响，不再处理 |
| F-036 | 已修复 | P2 | S004→V011-D→G07 | Search 人物与 TransferHistory processor | 只去重旧 raw ID，漏同批最终 ID并可跨 source 误合并 | 既有processor复核闭合不可变seen；G07双审及第三裁确认合法跨source聚合与批内重复 | 使用最终`Person.id`可变seen并在reset清空；Transfer批内同步写入seen | 已补人物身份去重及同一Paginator刷新回归测试；完整验证通过 |
| F-037 | 未验证 | P3 | B006-A | `TranslationHelper.languageName` 与 original_language 展示链 | ISO/BCP 47 形态未经规范化而退化为原码 | review_b006_a 核对映射、唯一调用者、模型与标准标签边界 | verify_b006_a_retry 确认行为但函数只承诺 ISO 639-1，扩展契约缺失 | 上游字段格式及 BCP 47/别名要求未验证 |
| F-038 | 已修复 | P3 | B006-A | TranslationHelper 语言叶子与 `MediaMetadataText.secondaryLine` | 空白原语种进入详情分隔串 | review_b006_a 闭合 decodeIfPresent→原样回退→append 链 | verify_b006_a_retry 独立确认空 Text/尾随分隔及通用元数据范围 | TV 展示不变量缺陷已确认；真实 payload 频率未验证 |
| F-039 | 用户决定跳过 | P2 | S004→V011-C→G04 | `SearchViewModel.SharedMediaFetcher` 取消链 | 单waiter取消不应误伤共享请求，但整个search session废弃后仍没有aggregate cancel，底层请求、buffer与cursor继续 | 既有双审闭合unstructured task；全新G04 clean-room复核收窄共享语义并升级P2 | 不修改共享取消链，避免误伤仍有效的电影/电视剧waiter | 旧请求结果已有generation屏障；用户接受慢请求继续占用资源的影响 |
| F-040 | 已修复 | P3 | B005 | `TranslationHelper.swift:491-505`（显示边界去重） | 不同职位键翻译后产生重复职位文本 | review_b006_a 确认 Cinematography/Camera 同译与原 key 去重顺序 | verify_b005 独立确认当前可见路径为职员卡片并收窄 Hero 边界 | TV 显示缺陷已确认；修复为翻译后显示边界去重，`Cinematography/Camera` 收敛为「摄影」，用户批准 |
| F-041 | 已修复 | P3 | B005 | `JobRegistry.swift:113-149`（canonical 解析）、`StaffManager.swift:9-16`（优先级） | 职位键变体同时失去翻译和优先级 | review_b006_a 闭合原样解码、精确查表与排序 999 路径 | verify_b005 独立确认大小写/换行双重失配与 Hero 排序影响 | TV 行为缺陷已确认；修复为单一 canonical key 解析供翻译与优先级共用，未知 key 保真且保底 999，用户批准 |
| F-042 | 未验证 | P3 | B006-B | 国家映射/ProductionCountry/详情显示 | 非 canonical 国家码形态未经规范化 | review_b006_b_retry 核对 249 键、两个入口与多态解码 | verify_b006_b 确认 canonical alpha-2 全覆盖，宽容输入是否属契约无法判定 | 上游形态/alpha-3/别名要求未验证 |
| F-043 | 已修复 | P3 | B006-B | ProductionCountry 多态解码与 `MediaMetadataText.secondaryLine` | 空/畸形国家元素生成空白分隔符 | review_b006_b_retry 闭合 nil模型→空显示→joined 链 | verify_b006_b 独立确认叶子与内外分隔两层空值路径 | TV 展示不变量缺陷已确认；真实 payload 未验证 |
| F-044 | 已修复 | P3 | B005 复核新增 / B006-C | `SearchViewModel.swift:348-357`（投影）、`:794-801`（人物分页 processor） | 人物搜索直接展示原始 job，绕过统一翻译 | verify_b005 独立确认 canonical Director 也会显示英文 | verify_b005 后续 B006-C 主审重走 searchPerson→SearchView 旁路并支持 | TV 旁路缺陷已确认；修复在人物分页器 processor 统一投影，用户批准随组四修复 |
| F-045 | 已修复 | P3 | B005 复核新增 / S006 | `StaffManager.swift:126-141`（投影）、`:228-240`（分组） | roles-only 职员在 Hero 与卡片职位显示不一致 | verify_b005 独立确认 Hero roles 兜底而 processCrew 不投影 | verify_b006_b 作为 S006 主审确认触发边界与 PersonCard 旁路 | TV 分支差异已确认；修复在 StaffManager 边界统一投影 roles，job/character 均空时才回退，用户批准 |
| F-046 | 已修复 | P3 | B006-C | MediaGenre/translateGenre/`MediaMetadataText.primaryLine` | 类型名未规范化且空结果仍进入详情 | verify_b005 作为 B006-C 主审闭合多态解码、精确查表与 joined 链 | verify_b006_c 独立确认 trim/filter 边界并收窄大小写/别名 | TV 展示不变量缺陷已确认；真实输入频率未验证 |
| F-047 | 用户决定跳过 | P1 | B007→V012-B/C→W013-B | 全局/分季/Header 取消文案与删除接口 | 当前后端已对所有身份按season筛选；剩余为同媒体同季多group/多owner时文案只展示一条，媒体级删除却可能命中多条 | 当前TV、Web与后端调用链重新闭合；旧“非TMDB跨季删除”证据已失效 | 当前Web共享同一媒体级删除行为 | 用户决定跳过，不做TV单端增强 |
| F-048 | 用户决定跳过 | P1 | B007→V012-B/C→G02 | 取消确认准备与执行 | 确认后重新解析target且未冻结精确订阅ID | 当前Web同样先通用确认、再读取当前媒体并执行媒体级删除 | TV/Web行为一致 | 用户决定跳过，不做TV单端增强 |
| F-049 | 已修复 | P2 | B007→V012-B→G08 | Home/Header 取消结果 | DELETE false或异常被静默吞掉，Home 直接丢弃 Bool 返回 | 既有双审闭合结果出口；G08 三方裁决确认 Home 稳定丢弃 false 并升级 P2 | Home失败/异常与Header刷新后仍订阅统一通知；远端已删除且UI收敛时静默 | 已补业务失败、详情收敛与通知接线测试；完整验证通过 |
| F-050 | 已修复 | P3 | S006→G07（F-056 并入） | `MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:191-220`（`applyFullDetail` Hero 主演取样） | Hero 演员先截断再去重；无名氏白占名额，非空不足四人不补足 | 改为 G07 第三裁给的 `processActors` → 过滤 trim 后空名 → `prefix(4)`；过滤只落在 Hero 取样层、**不下沉 `mergeActors`**（货架口径经 verify_s006 确认不受影响）；尾部「完全为空才补」分支保持原样 | 定向 9/9；反向验证分两次单独还原：①退回「先 `prefix(4)` 再去重」→ 当时那版 6 条用例中 1 挂（重复项挤人）/ 5 过；②仅去掉空名过滤 → 9 条中 2 挂（nil 名与纯空白名各一）/ 7 过；全量 **991/991 通过、零失败**（982 + 9）。过程中修正一处用例缺陷：`testMergedDuplicateKeepsAllCharacters` 在新旧实现下同过（合并口径不随选取顺序变），已由阳性改标为阴性对照 | 🆕 后端 `actors` 取自 TMDB `credits.cast`，只按 `known_for_department == "Acting"` 过滤、**不去重**（`app/core/context.py:481-486`），TMDB cast 结构上允许同人多条不同 `character`；视图 `MoviePilot-TV/Views/Pages/MediaDetailView.swift:1037` 用 `compactMap { $0.name }`，无名者渲染为空档；Web 无 Hero 主演行可照抄；真实重复/无名分布仍未验证 |
| F-051 | 已修复 | P3 | S006 | `Models.swift:2286-2289`（`Person.hasUsableProfileImage`）、`StaffManager.swift:109-112` | 头像排序与可渲染图片判定不一致 | verify_b006_b 以 PersonDecoding 多组反例闭合；verify_s006 独立确认只影响 crew 新增项排序及 source-aware 反例 | G07 第三裁：直接复用现有 `imageURLs.profile != nil`，默认豆瓣头像与空 images 均为反例 | TV 排序规则缺陷已确认；真实来源组合未验证 |
| F-052 | 已修复 | P3 | S006 | `StaffManager.swift:9-16`（多值取最高优先级）、`:235` | 多值 roles 被拼成单一 key 后优先级 999 | verify_b006_b 闭合 roles join→priority→translate split | verify_s006 修正为 roles fallback 两人反例并确认 | TV 排序缺陷已确认；修复为多值按项规范化后取最高优先级，空 roles 不再造孤立 `/`，用户批准 |
| F-053 | 已修复 | P3 | S006 | `StaffManager.swift:45-141`、`TranslationHelper.swift:491-505` | 已翻译返回值不能安全作为下一批 existing | verify_b006_b 构造 Director→导演/Director→导演/导演 链 | verify_s006 独立确认条件性且当前无非空 existing 调用者 | 潜伏 API 缺陷已确认；修复为翻译后显示边界去重使回灌幂等，未启用增量语义仍保留，用户批准 |
| F-054 | 已修复（`58c7e81`） | P1 | B007 复核新增 / M001-F→G02 | SubscriptionHandler Bangumi-only 取消 | 历史实现会丢失精确身份并改走集合式媒体删除 | 当前TV `58c7e81`已保留canonical/Bangumi/AniList/legacy身份；当前后端按身份与season筛选 | 当前实现与上游合同重新核对 | 修复已完成；旧部署版本未验证 |
| F-055 | 已修复 | P3 | M001 | `SearchViewModel.swift:279`（最佳人物准入）、`Models.swift:2286-2289` | 人物最佳结果使用 TMDB 专属头像准入 | review_m001_g 独立确认人物搜索允许 Douban 且卡片与准入判据不同源 | G07 第三裁：与 F-051 共用 `imageURLs.profile` 事实来源但保持独立出口/fixture | TV 旁路缺陷已确认；Web 排名与真实跨来源人物分布未验证 |
| F-056 | 已修复（并入 F-050） | P3 | S006→G07→F-050 | Hero 演员姓名展示 | 不过滤 nil/空 name 且首四项后不补位的机制成立，但与F-050同属过滤/去重后再截断的取样顺序 | 既有双审确认；G07第三裁将重复、空名和补位合成一个Hero选人根因 | 并入F-050，不驳回机制；全量processActors后过滤空名再prefix(4) | 随 F-050 落地：Hero 取样层过滤 trim 后空名；定向 9/9 中 2 条覆盖本项（nil 名、纯空白名），反向验证仅去掉过滤即 2 挂；驳回的是**重复编号**、不是机制；真实无名人物分布仍未验证 |
| F-057 | 用户决定跳过 | P3 | S003 | ParsedSeason 范围解析/排序 | 范围终点丢失或未校验，排序不反映实际覆盖 | verify_s006 作为 S003 主审构造季/集范围反例 | verify_s003_resume 独立确认结束季捕获未消费及范围排序内部不一致 | 用户决定跳过：仅影响筛选下拉排序、筛选本身按原始字符串匹配仍正确，且真实范围格式未验证；另经比对 Web v2.15.6 `useTorrentFilter.ts` 为同源同缺陷，TV 修复无法与 Web 对齐 |
| F-058 | 用户决定跳过 | P3 | S003 | ParsedSeason 与 Formatters 两套语法 | 卡片支持的季集语法在筛选排序中被判无效 | verify_s006 对比两套正则及 Set 未指定顺序 | verify_s003_resume 独立闭合两套正则与同一字段的显示/筛选链 | 用户决定跳过：仅影响筛选下拉排序与无效组内顺序；Web 无第二套语法（卡片直显原始串），“对齐 Web”等于删掉卡片美化造成显示退化，故不对齐也不修 |
| F-059 | 部分修复 | P3 | S003 | `ParsedSeason.swift:43-60`（整季判定） | 解析失败和整数溢出静默折叠为合法零值 | verify_s006 闭合 Int 安全失败与整季/无效分支 | verify_s003_resume 独立确认无成功状态及零值多义性 | 用户批准只修「集号解析失败被冒充整季」这条唯一的归类错误；无成功标志/零值多义性等排序侧影响与 F-057/F-058 一并跳过；另注 Web 用 `parseInt` 不产生整季误标，该形态为 TV 独有 |
| F-060 | 已修复 | P3 | S001 | `Logger.swift:7-101`（非隔离化）、16 个生产文件的 67 处直接 `print` | 直接 `print` 绕过 Debug-only Logger | integrate_i002 作为 S001 主审统计 35 Logger/80 print、确认个人数据与 bootstrap 缺失 | verify_s001_resume 独立复算调用、Release 设置与实际输出值；无凭据泄漏证据，P2→P3 | 用户决定全部替换为 `Logger.*`；实测调用点 67 处/16 文件（原记 80 处/15 文件，差异为计数口径），新增源码级禁用 `print` 守卫测试 |
| F-061 | 已修复 | P2 | S003 复核新增 / M001-K→I011 | `CustomFilterService.swift:24-67`、`TorrentsResultView.swift:248-307` | 软过滤置尾及后端默认顺序被结果页重排破坏 | 既有双审确认机制；I011补默认策略覆盖，review_a001_j第三裁决按每次默认展示与错误策略升级P2 | 默认保留后端顺序；显式排序分别作用于正常/软过滤全局分区 | 已补默认与显式排序回归；完整验证通过 |
| F-062 | 已修复（`90b40b4`） | P1 | S002→G06 | `KeychainHelper.swift:87-100` 及 APIService 登出链 | access token 删除失败后旧会话可在重启复活 | 既有双审闭合删除失败恢复；G06 两票确认登出成功表象后旧token重启复活的安全边界 | 删除失败写高权威logout tombstone/revision并重试；启动不得恢复被撤销代际 | 修复已完成：`90b40b4`；tombstone先于旧记录清理且启动失败关闭 |
| F-063 | 已修复（`90b40b4`） | P1 | S002→G06 | `KeychainHelper.swift:8-84` 及 APIService/SystemViewModel 持久化链 | Keychain/UserDefaults 无明确权威导致旧或混合会话恢复 | 既有双审闭合逐项持久化；G06 两票确认A token、B user/permissions与另一代credentials可组合恢复 | 四项复用同一session owner/revision，只接受同代记录 | 修复已完成：`90b40b4`；单记录revision取代逐字段混读 |
| F-064 | 已修复（`af67839`） | P2 | M001-G | `Models.swift:2323-2337` 及 Person 解码入口 | 混合类型头像对象可拖垮人物或媒体数组 | review_m001_g 闭合 PersonAvatar、数组原子解码与 source-aware 图片传播链 | verify_m001_g_retry 独立确认可选字段错误传播至人物/媒体/资源批次及空首选遮蔽 | 修复已完成（`af67839`）；当前后端允许 string/dict 头像，独立复审通过，本地测试 430/430 通过 |
| F-065 | 已修复（`90b40b4`） | P1 | M001-F→G02 | APIService 三类分季缓存 | 三类缓存只按endpoint参数寻址且旧请求可跨baseURL/user回填，新会话可显示并保存错误季/组数据 | 既有双审闭合cache污染；全新G02 clean-room复核闭合跨服payload链并升级P1 | 切会话清缓存且store前校验既有session generation；不建缓存框架 | 修复已完成：`90b40b4`；会话transition清缓存且旧epoch禁止回填 |
| F-066 | 已修复 | P2 | M001-F | SubscribeSheetViewModel 剧集组加载资格 | 辅助或非正 raw TMDB ID 被当作主身份加载剧集组 | 当前Web明确跳过非TMDB主来源，后端接口只接受TMDB路径ID | 仅主身份TMDB且raw ID为正时加载，兼容旧无来源TMDB订阅 | 已补跨来源、旧数据与非正ID回归；完整验证通过 |
| F-067 | 已确认（用户决定跳过） | P2 | M001-F→G02 | SubscribeSheetViewModel 配置加载 | 可选filter/group请求与核心站点/下载器/目录共用失败域，任一可选失败会清空已成功核心选项并禁用保存 | 既有双审确认机制；G02两名不同复核按当前HEAD再次闭合稳定阻断并升级P2 | 订阅编辑配置按整体原子加载；不拆分为部分可编辑状态 | 当前行为符合整体加载策略，用户决定跳过 |
| F-068 | 已确认（用户决定跳过） | P2 | M001-F | Subscribe 快照与 Home/动作链 | nil/0/负数/重复业务 ID 可进入 SwiftUI 快照 | Web 同样直接依赖后端正数唯一主键；TV 不做差异化防御 | 保持当前模型与官方后端 ID 合同；不新增异常数据兜底 | 正常官方后端不触发，用户决定跳过 |
| F-069 | 降级；转入 CHK-003 后续兼容检查 | P3 | M001-F→G02→当前 v2.15.1 合同复核 | Subscribe 编码与完整 PUT | 当前TV已覆盖目标后端全部公共可写订阅字段，F-199的现成`total_episode`损坏链也已修复；只有未来后端新增TV未知可写字段时，固定模型完整PUT才可能丢值 | 当前TV `CodingKeys`、v2.15.1后端公共写入schema与Web完整表单逐字段复核；未找到当前字段反例 | 不改产品代码；并入CHK-003，官方Web/后端升级时逐字段复核后再决定建模、正式round-trip或阻止不安全保存 | 当前版本不构成缺陷；仅保留未来版本条件性兼容风险 |
| F-070 | 已修复 | P2 | M001-H→G09 | GlobalSettings 与 Transfer AI 入口 | 未知 AI 能力被当作已启用 | 当前 Web 与后端均只在显式 true 时开放 AI 能力 | 改为 `== true`，覆盖 settings 缺失、字段缺失、null、false、true | 回归通过，完整验证通过 |
| F-071 | 已修复 | P2 | M001-H→I009 | TransferHistoryViewModel 搜索 fetcher | 首次搜索后owner与fetcher形成永久强引用环，每次重进/搜索可无界保留整份历史对象图 | 释放回归在修复前失败，确认 `self → fetcher → self` | 像init一样在闭包外冻结局部pageSize；不建生命周期框架 | 修复后释放回归、完整构建和串行全量测试通过 |
| F-072 | 已修复（`e388e8b`） | P1 | M001-H→G04 | TransferHistoryViewModel 轮询/搜索/session | 旧轮询可污染新查询/会话、推进当前游标并让当前页继续操作旧记录 | 既有双审确认；G04主审与独立复核再次闭合旧fetcher续接当前fetcher/游标并双票升P1；整改已完成（`e388e8b`），验证及最终独立复审通过 | 捕获query/session/generation/fetcher，恢复与每页提交前复核 | 纯TV跨查询/会话状态归属缺陷 |
| F-073 | 已修复（`e8cdaf7`） | P2 | M001-J→G09 | ManualTransferPreview envelope/data/item 与统计/UI | `success:true`但data缺失/null或item success缺失/null会被当成功预览 | 既有双审闭合fail-open；G09主审与clean-room第三裁逐矩阵确认成立分支，独立复核对envelope缺success的反证被吸收 | 修复已完成（`e8cdaf7`）：`previewManualTransfer` 要求 `data != nil`，`ManualTransferPreviewItem.success` 收紧为必填 Bool，合法显式空仍成功 | 当前正式producer完整；畸形/兼容producer触发频率未验证 |
| F-074 | 用户决定跳过（2026-08-14） | P2 | M001-J→V021/W018-B | Reorganize预览operation owner | 旧预览可在表单/会话变化、提交开始或Sheet关闭后回写并打开 | 模型/V021双审及W018-B双审闭合无revision/cancel、预览A→提交B与Web共享链 | 冻结forms/session/revision；编辑、新预览、提交、dismiss/session切换退休旧结果 | 2026-08-14 用户按实际操作链复核：预览请求通常数百毫秒即返回并弹出预览 Sheet 抢占焦点，同会话表单编辑窗口过窄；会话切换已有 isSessionUnchanged 防护，决定跳过 |
| F-075 | 已修复（仅误导文案；2026-08-14 用户裁决） | P2 | M001-J→W018-A | ReorganizeViewModel 批量后台整理 | 批量提交不保留逐 ID 的已受理/失败/未知状态 | 模型双审与W018-A双审确认success→false/throw、未发送与整批重试链 | 2026-08-14 三端对照后用户裁决：Web 同样无逐 ID 受理/只重试失败机制且部分失败不刷新列表，后端 force 重整理无幂等，故不做 TV 单端“只重试失败项”增强；仅修误导文案 | TV 错误反馈缺陷；后端幂等性未验证 |
| F-076 | 已修复（资源搜索入口；2026-08-14） | P2 | M001-J→V011-C→W006-B/I012→G01/G04→当前实现复核 | Manual/Search 资源与最佳结果状态 | 统一session/generation门禁已阻断旧会话/旧owner结果进入新账号；同一会话内清空关键词、开始新搜索或搜索失败时，聚合Search/Resource仍可能保留旧结果或先发布过期错误 | 手动媒体ID子项已由`44908c4`修复；资源搜索新请求开始即清空旧结果已由本次修复（`SearchViewModel.autoSearch` `.resource` 分支）闭合，空关键词点搜索与 Web 一致（均直接不搜索）不改，聚合分支 bestResults 不扩展 | 新attempt按query/type/generation原子清退或发布结果与错误 | 原跨owner错误动作P1链已闭合；资源搜索同会话陈旧结果已修复，聚合 bestResults 旧值未列为独立修复目标 |
| F-077 | 已修复（`58c7e81`） | P2 | M001-I当前合同复核 | SubscribeShare.toMediaInfo | 分享投影丢Bangumi、AniList与统一来源主身份 | 当前Web/后端schema与三路TV调用链复核确认；Explore/Search右键详情、资源、订阅均消费投影 | 共享投影按canonical→raw保留全部当前schema身份；模型缺字段部分与F-079同一实现边界 | 修复已完成：`58c7e81`；真实单一来源记录频率未验证 |
| F-078 | 已修复 | P3 | M001-I | `Models.swift:1086-1097`（去重 key）、`:2934-2983`（身份构造与媒体标识兜底） | 缺失/0/负数/重复分享业务 ID 可破坏去重与焦点 | review_m001_i 闭合 raw_id fallback、Paginator/ForEach 与兼容巡检盲点 | verify_m001_i 独立确认列表丢项/焦点不稳，并驳回“Fork 错目标”的过宽影响 | 已修复：有效分享号收紧为正 ID（0/负数同缺失），缺 ID 改用媒体标识拼身份并舍弃可变的 `share_title`，全退化才退回随机身份；未采纳审计「拒绝非法记录」方向以免丢卡，亦未采纳「照 Web 不去重」因 TV 的 hasMore 收敛依赖该去重 |
| F-079 | 已修复（`58c7e81`） | P2 | M001-I当前合同复核 | SubscribeShare GET→Fork 编码 | TV模型缺当前schema的`anilistid/media_source/media_id`，GET解码后Fork确定丢失 | 后端91ce365f与Web 7ea14bc9确认三字段在GET/Fork合同；APIService直接编码原模型 | 只补三个明确字段；unknown extra与legacy mediaid不在Share合同，不做raw透传 | 修复已完成：`58c7e81`；真实记录分布未验证 |
| F-080 | 已修复（2026-08-17） | P2 | M001-K→V011-C/I009 | Search/Resource/Transfer AI SSE 消费者 | SSE 未收到合法终止或收到业务 error 仍可按成功收尾 | 既有双审闭合 EOF、业务 error、missingSites 与 AI 进行中状态链 | Search/Resource 业务 error 直接失败；clean EOF 无 done 丢弃部分结果并走普通 fallback；missingSites 仅 done 后；Transfer AI 无明确 terminal 显示可重试错误 | 后端终止保证与真实截断频率未验证 |
| F-081 | 已修复（`670cf86`） | P2 | M001-K→S005/V015/W020-E | CustomRule数组/所选ID与坏identity fail-open | 单坏项可拖垮整数组，已选ID缺失/重复可静默不过滤或first-match错规则，并破坏列表/focus/profile身份 | 既有链确认fail-open；W020-E第三裁决合并F-211缺ID与F-215坏identity，两票支持条件性P2 | 输入边界隔离坏项并校验规范非空唯一ID/name；用户接受已选缺失时静默不过滤 | 修复完成（`670cf86`），验证及独立复审通过；长名布局仍未验证 |
| F-082 | 已修复（`d8198fc`） | P1 | A001-A→G02 | 通用 ApiResponse 解码 | `success:false`会被可解data抢先发布并缓存，后续订阅/配置动作可基于业务失败载荷继续 | 既有双审闭合通用传播；全新G02 clean-room复核按当前envelope语义升级条件性P1 | 已修复（`d8198fc`）：先拒绝显式failure；错形data失败路径复用JSONValue取错误，保留success缺失兼容边界；438/438本地测试与独立复审通过 | 条件性错误状态/动作P1；真实失败envelope形状未验证 |
| F-083 | 已修复（2026-08-14） | P2 | A001-A→W017 | 下载动作 ActionResponse 解码 | 空body与非对象/畸形非空2xx混淆，异常响应被当成功并翻状态或移除任务 | A001-A双审收窄fail-open分支；W017双审确认三个生产mutation直接信任结果且可移除仍存在任务 | 已修复（2026-08-14）：`decodeActionResponseSync` 仅零字节空 body 兼容成功，非空响应一律复用严格 decoder 失败关闭并保留 message_i18n | TV fail-open已确认；空body正式契约未验证 |
| F-084 | 已修复（2026-08-17） | P2 | A001-A→G06 | 海报 URL 降尺寸 | 任意 URL 中的 `original` 都被全局替换为 `w500` | 既有双审闭合两条生产路径；G06 两票核到当前上游允许第三方绝对海报URL且无TMDB路径段保证 | 按用户裁决保留替换并回退原图；前序覆盖普通卡片，本轮补齐详情推荐/相似卡、海报背景与预载 | TV稳定改写机制已确认；真实非TMDB命中频率未验证 |
| F-085 | 已修复（`7f9fd17`） | P2 | M001-K→S005/V015/W020-F/H | CustomRule matcher/预览语义 | 已解码规则的预览、规范化与matcher/后端语义分裂；正常Web可达size单值/seeders区间可令硬过滤全空或条件静默失效 | W020-H双审以当前TV/Web/backend闭合字段矩阵并将既有P3升级P2 | 先统一官方语法，再让预览与matcher消费同一canonical解析结果；非法值显式失败 | 条件性P2；真实规则分布、Rust路径与远端最新性未验证 |
| F-086 | 已修复（`90b40b4`） | P1 | A001-B→G02 | APIService baseURL/request 构造与登录提交边界 | 未规范化候选可生成双斜杠/无效URL，且认证成功前写全局baseURL已清旧currentUser/cache并污染原会话 | 既有双审、G02纠偏及全新clean-room复核共同闭合失败登录前全局commit链 | 局部规范化candidate完成登录后再一次commit | 修复已完成：`90b40b4`；candidate认证成功且epoch未变后一次canonical commit |
| F-087 | 已修复 | P2 | A001-B/A001-C→V011-C→G02 | APIService/Search 错误消息选择 | 空白首选字段遮蔽后续有效detail/message，用户稳定失去可操作失败原因 | 既有API/Search双审与全新G02 clean-room复核确认各入口同根 | 逐项trim/filter后按现有优先级取首个有效文本 | TV错误恢复信息缺口P2；真实payload频率未验证 |
| F-088 | 已修复 | P2 | A001-B/C；V009-A/E 条件扩展 | form/query 标量值编码 | 合法特殊字符凭据及动态来源字面 `+` 未按目标解析规则编码 | verify_a001_b/review_a001_c_retry2 确认登录 form；verify_a001_h 闭合动态 `%2B`/C++ query 链 | review_a001_h 独立确认 query 机制但部署 fixture 未验证；V009-E 根因支持 | TV 登录 P2 已确认；动态来源为条件性 P3传播 |
| F-089 | 已修复（`90b40b4`） | P2 | A001-C→I016/G06 | 登录 401/403 错误分类 | 登录拒绝被当成既有会话失效，System手动刷新会清除旧有效会话 | G06 两票核到当前后端凭据/MFA失败使用401并确认System默认不保留旧会话；403仍仅为条件分支 | 登录请求禁通用鉴权重放；401/MFA、403、网络失败与权威no-access分别裁决 | 当前401生产链已确认；login 403合同与真实刷新频率未验证 |
| F-090 | 已修复 | P3 | A001-D | TMDB 搜索/识别返回值 | `tmdb_id <= 0` 被当成有效识别结果并遮蔽正候选 | review_a001_d_retry 闭合四个成功出口、动作/预加载调用者与测试盲点 | verify_a001_d 独立确认非法值立即返回并可遮蔽 fullDetail 正 ID | TV 正 ID 边界不一致已确认；真实输入未验证 |
| F-091 | 已修复 | P2 | A001-E→W016/W017 | 下载器首次加载与轮询恢复 | 首次下载器列表失败后页面不再重试客户端并永久显示假空 | A001-E双审闭合；W016/W017不同代理再次从页面/轮询与Web对照确认 | 失败时轮询复用initialLoad，成功空配置单独呈现 | TV恢复缺口已确认；真实失败频率未验证 |
| F-092 | 已修复 | P2 | A001-E→W017 | 下载动作与三秒轮询/快速重复 | 暂停/恢复成功后盲目toggle，可反向覆盖轮询正确状态；无in-flight gate又允许双击重复mutation | A001-E双审闭合竞态；W017双审确认同一行可并发两次请求且错误状态可持续 | 单行串行、冻结目标状态，成功后赋目标值或刷新，禁止盲toggle | 纯TV状态竞态已确认；真机连击频率未验证 |
| F-093 | 用户决定跳过（2026-08-27）；已实现部分保持 | P2 | A001-E→W017 | 下载列表及动作错误/状态呈现 | clients/list/start/stop/delete全部错误仅print，首次失败假空、刷新失败陈旧、mutation失败无反馈 | A001-E/W017双审闭合；2026-08-17 再与当前 Web 对照 | 下载器失败可见并自动恢复、连续轮询/主动动作失败通知；任务列表首次失败仍可能短暂假空，无独立 stale/error 四态 | 自动恢复语义与 Web 对齐；完整五态说法撤销。2026-08-27 用户决定跳过残余项 |
| F-094 | 用户决定跳过 | P2 | A001-E→G05 | 下载任务 hash 身份与动作路径 | nil/空/空白或 path delimiter hash 没有统一动作与路由边界 | 既有双审闭合 Optional gate/路径；G05两名代理确认当前后端仍允许optional hash且三个动作可接受空白值 | 与F-024共用规范化helper但保持独立：本项管动作可用性/路由，F-024管行身份/trap | TV 输入/路由边界已确认；异常hash分布与部署版本未验证 |
| F-095 | 已修复（`7b7130e`） | P1 | A001-E→W017 | 下载客户端切换与旧行动作 | 切到B后A旧行仍可达且动作读取当前B；同hash时可删除B任务及文件 | A001-E双审闭合错client参数；W017双审确认B慢/失败时旧行持续、固定delete_file=true形成持久数据损失 | 已修复（`7b7130e`）：列表绑定loadedClient，旧行禁用，三种mutation显式传并校验行客户端；439/439本地测试与独立复审通过 | 条件性P1；跨客户端同hash频率未验证 |
| F-096 | 用户决定跳过 | P2 | A001-G | 媒体服务器可选入库状态探测 | `/mediaserver/exists` 的辅助 401/403 可自动重登或登出整个会话 | review_a001_g 闭合 best-effort 调用、makeRequest 默认参数与 `/notexists` 非破坏性对照 | verify_a001_g 确认参数分裂与现有非破坏性探测规则 | TV 会话副作用已确认；端点权限/状态码未验证 |
| F-097 | 已修复 | P2 | A001-G→G03 | 首页媒体服务器轮询 | 单服务器轮询错误被转成空数组并整体覆盖旧快照，与成功空同态，卡片/焦点虚假消失直到后续轮询 | 既有双审确认机制；G03两名纠偏/第三裁复核均按正确命题裁P2 | 仅成功结果覆盖对应服务器；失败保留旧值，成功空才清空 | 纯TV可逆数据误报P2；十秒自愈与真机焦点落点未验证 |
| F-098 | 用户决定跳过（保持当前行为） | P1 | A001-F→I009/G09 | AI批量整理accepted/terminal逐ID回执 | accepted集合被提前移出选择，但后端/TV终态只有整批结果；失败或未知后无法安全恢复逐ID重试集合 | 既有双审闭合partial accepted与terminal receipt缺口；G09两名代理确认当前后端整批agent结果且TV模型丢弃IDs/completed | 保持当前整批错误通知与权威刷新，不做TV单端逐ID结果推断 | 当前逐ID完成语义缺失已确认；部署/真实失败分布未验证 |
| F-099 | 已修复 | P2 | A001-F→G09 | 手动媒体选择正 ID 边界 | 原生 0 可进入整理/下载，负值又遮蔽有效 fallback | 既有双审闭合 native-first 选择与ASCII数字校验；G09两名代理对照当前后端truthy语义确认0等同未提供 | 复用现有正整数helper并在无效原生值后尝试规范fallback | TV与当前后端数值身份边界冲突已确认；部署频率未验证 |
| F-100 | 已修复（`0cfeb12`） | P1 | A001-J→V012-A→G02 | 订阅状态同键请求与详情/预加载调用链 | 同键旧normal/force曾可覆盖较新强刷并反转菜单add/cancel判断 | `0cfeb12`已为每个规范化key绑定request revision/owner，旧响应不能覆盖较新的force结果或缓存；乱序回归测试通过 | 已按原最小方向完成，不再开放 | 修复已完成；真实网络触发频率不影响闭合结论 |
| F-101 | 已修复 | P3 | A001-H→V011-C | `SSEFramer.swift`（新增，组帧与字节切行）、`APIService.swift:2737-2766`、`BackendCompatibilityTests.swift:2689-2736` | SSE 逐物理行解码，未按事件边界组帧并合并多条 data | 新增 `SSEFramer` 并让生产解析器与兼容探针共用；两处均改为遍历**字节**而非 `.lines` | 定向 20/20；反向验证逐字复刻改动前代码 → 14 挂 / 6 条阴性对照通过；全量 **957/957 通过、零失败**（937 + 20），逐名比对无用例消失 | 🆕 `AsyncLineSequence` 会丢弃空行，事件边界只能在字节层拿到；当前后端全为单行 data，故触发条件目前不可达 |
| F-102 | 未验证 | P3 | A001-H→G05/G09 | `APIService.swift:1813-1814`、`decodeAiRedoResponse:1611-1614` | opaque progress_key 未按单一路径段编码 | 静态构造可被特殊字符改写；G05与G09复核均确认当前后端生成值只含字母、数字和下划线 | 保留path-segment编码硬化建议；先固定合同/部署fixture | 当前本地生产者路径安全；外部生产者、部署版本与opaque合同未验证 |
| F-103 | 用户决定跳过 | P2 | A001-H→I012 | 资源标题与媒体ID意图 | 标题与媒体ID共用keyword并由宽正则猜路由；Search stream标题失败后fallback可把同一输入改成ID搜索 | 既有双审确认路由猜测；I012提出fallback漂移，review_a001_j以现有标题测试第三裁升级P2 | 入口冻结title/media-ID intent，Search fallback只走title路径 | TV稳定搜索语义漂移已确认；后端真实结果差异未验证 |
| F-104 | 用户决定跳过 | P2 | A001-I | `APIService.swift:1885,1897,1912,1938-1943`，A001-D Douban recommendations `1431` | 动态媒体或人物不透明 ID 未编码为单一路径段 | review_a001_i 闭合保留字符经 URL 构造改写 path/query/fragment 与详情/人物调用链 | review_a001_h 独立确认模型允许不透明 String、同文件已有整段编码惯例，并收窄相邻传播范围 | TV 路径构造缺口已确认、严重度条件性；上游 ID 字符集及后端 percent-decoding 未验证 |
| F-105 | 用户决定跳过 | P3 | A001-K | `APIService.swift:166-200,2519-2552,2596-2600,2618-2647` | 相对路径及带空白图片值未规范化为可请求的绝对 URL | review_a001_j 对照生产 displayImageURL 与兼容 oracle，并追到媒体/订阅/下载/人物卡片 | verify_a001_h 用独立 Foundation 探针确认相对 URL 保持无 host、空白绝对 URL 为 nil，并收窄 oracle 身份 | TV 图片 URL 规范化缺口已确认；当前 Web/后端 origin 契约与真实频率未验证 |
| F-106 | 已修复（2026-08-17 补齐重绘） | P2 | A001-K→I003/I016/G01 | settings事务与图片URL配置生命周期 | settings 可跨阶段混合；旧模型与存活 SwiftUI 子树可继续使用旧baseURL/缓存/TMDB域 | I003双审确认P2；I016/G01完成等级裁决；本轮复核动态 getter 与 Equatable/观察链 | 前序改按访问计算；本轮以图片配置 identity 驱动主要页面、Grid/DetailCard Equatable 与详情背景重算 | 切服旧树真实可见时序仍未验证 |
| F-107 | 已确认（原 P1 主触发已修复；用户决定跳过剩余项） | P2 | V001→R001/R002/W020-C→G08 | 根登录转换与跨会话通知owner | 原“登录失败后成功仍残留旧banner”已修复；剩余仅旧业务任务在会话切换后晚到调用`show()`，可把A的失败提示显示到B | `90b40b4`已让manager监听会话UI身份、同步发布并在身份切换时清banner/计时；现有测试覆盖先show再切号，未覆盖切号后旧调用者晚到show | 不再修改；若以后处理，应只在异步业务调用者发布通知前校验既有operation/session owner | 剩余影响为短暂错误提示、无错误mutation，降为P2；用户决定跳过 |
| F-108 | 未验证 | P3 | V001 | `NotificationManager.swift:44-60`、根 presenter 与 Sheet 异步失败链 | 通知可能在独立 Sheet 下不可见却照常计时并过期 | review_a001_j 闭合 SubscribeSeason/Transfer 异步失败、根 presenter 与错误清空链 | verify_a001_h 确认静态触发链，但无法静态证明 tvOS Sheet 必然遮挡根 overlay | 条件性 TV 呈现问题；模态层级、焦点与五秒可见窗口待运行验证 |
| F-109 | 已修复（`90b40b4`） | P2 | V002-A/B→W020-A/D/G06 | profile偏好作用域与权威配置owner | 四类tuple key可碰撞；token-only/凭据轮换还会落入错误bucket，推荐开关又绕过当前per-user权威配置 | 既有多审闭合碰撞与推荐合同；G06 两票确认key读取使用凭据用户名而非currentUser且baseURL未规范化 | canonical baseURL+权威currentUser组成版本化tuple；异步操作冻结同一key | 跨profile污染机制已确认；真实多profile频率与远端最新性未验证 |
| F-110 | 已修复 | P2 | S005→C018-B/W011→G05 | `TorrentsResultView.swift:267,283-285,329-343,374-395` | 默认排序选择升序仍固定按pri_order降序 | 既有多审确认；G05主审与独立复核均再次闭合可选asc与固定desc的稳定反例并支持P2 | 比较器遵循方向，或隐藏默认字段方向控件；不与F-061合并 | 纯TV内部控制/比较器契约冲突 |
| F-111 | 已修复（`90b40b4`/`769c509`） | P2 | V002-A/B→W020-A/C→I016 | token-only profile与连接身份 | 无storedUsername的合法会话统一使用default，System连接页也忽略权威currentUser | 既有双审确认机制；I016两代理以受支持token-only双账号隔离链确认升P2 | `profileKey=baseURL\|user_id`；正常路径由 `/user/current` 恢复，恢复前或失败时只回退与当前 token 强校验匹配的快照 `user_id` | 匹配回退/不匹配拒绝两条测试覆盖；快照不取代新版会话或权限权威 |
| F-112 | 已修复 | P2 | V002-C/D→W020-A/D→I016 | 站点权威空/失败/加载状态 | 站点成功空不清旧选择，失败与当前可用数据不可区分；Search/详情还会继续发送旧ID | 既有双审确认机制；I016两代理闭合成功空→旧ID请求链并升P2 | 成功空清选择，失败/取消与空分开并提供最小重试 | 纯TV状态缺陷；真实空站点频率未验证 |
| F-113 | 用户决定跳过 | P2 | V002-D | `SystemViewModel.swift:385-400,444-450` 及资源搜索调用者 | 默认站点异步归一化可跨 profile 写回或返回旧 profile 值 | review_a001_h 闭合 A 读取→await→动态 B key 写回、catch 回退 A 与 B 会话请求传播 | review_a001_j 独立确认成功/错误/取消/撤权、三个调用者与条件性 P2 严重度边界 | 纯 TV 会话归属缺陷已确认、严重度条件性；旧导航可见性与真实频率未运行验证 |
| F-114 | 已修复 | P3 | V003 | `SearchViewModel.swift:270,658-668`、`MediaDetailViewModel.swift:40,122-133` 及对应 View | 父 ViewModel 未转发 SiteFilter 子对象变化，站点按钮可停留旧文案 | verify_a001_h 闭合两个固定子对象、父 View 观察关系及 Paginator 已桥接反证 | review_a001_h 独立确认成功非空即可触发，实际请求读取子对象当前值并收窄为 UI 新鲜度 | 纯 TV SwiftUI 观察缺陷已确认；无关重绘前实际可见时长未运行验证 |
| F-115 | 用户决定跳过 | P2 | V004-A→I005 | MediaPreloader详情ready与阶段屏障 | ready值域判定错误；详情响应已可启动season时仍等待识别和图片，稳定把有订阅权限电视剧的全屏Loading串行延长 | V004双审闭合身份值域；I005集成与不同代理复核闭合`detail response→season`关键路径并升级P2 | 规范ready值；详情响应发布即启动season，图片/识别仅约束真实依赖者 | TV详情ready/主流程阶段屏障已确认；真实延迟分布未验证 |
| F-116 | 已修复 | P2 | V004-A→V012-A→I013→G03 | 热缓存首帧内容与背景安装顺序 | Container凭wasPreloaded先揭示内容，但VM初始化不安装传入full detail的背景，首帧确定进入灰底后才由View task补齐 | G03两名纠偏复核按正确命题独立闭合热缓存Container→VM init→View task顺序，覆盖I013原运行未验证边界并升级P2 | VM初始化同步安装已有full detail/background；不改F-115网络阶段图 | 纯TV首帧状态分裂已确认；实际闪烁时长/焦点影响未运行验证 |
| F-117 | 用户决定跳过（暂时，待内存优化工作树） | P3 | V004-A | `MediaPreloader.swift:95,123-169` 图片预取取消链 | 取消早于 Kingfisher handle 安装时，请求仍启动且可继续发布 ready | verify_a001_h 闭合已取消 child、onCancel 先恢复、operation 后启动请求与 handle 清空时序 | review_a001_h 独立确认 Swift/Kingfisher 顺序、真实取消入口、缓存写入与取消后 ready 发布 | TV 资源/生命周期缺陷已确认；真实竞态频率及注销传播未运行验证 |
| F-118 | 用户决定跳过（暂时，待内存优化工作树） | P2 | V004-B→V012-A→G03 | MediaPreloader pin owner与详情返回栈 | ownerless Set使同key任一owner消失即释放全部保护；父详情暂时onDisappear后可被LRU移除并漏通知刷新 | G03两名不同复核确认ownerless语义、唯一生产调用与淘汰/刷新链；tvOS push/返回表现保留运行边界 | 复用稳定owner token/lease，最后owner释放才可淘汰；不建缓存框架 | 静态owner缺陷P2已确认；push onDisappear、30+ churn与返回卡死未运行验证 |
| F-119 | 用户决定跳过（暂时，待内存优化工作树） | P2 | V004-B→V012-B→G02 | MediaPreloader cache aliases 与订阅回写 | UI key与canonical media ID一对多；保存/取消只更新单task或有限TMDB alias，其他未pin alias可长期显示旧订阅状态 | 既有双审确认机制；G02两名不同复核确认fullDetail/非TMDB alias缺口并升级P2 | 线性扫描小缓存并更新全部已知canonical alias；不建alias registry | 条件性TV状态错误P2；真实alias并存频率未验证 |
| F-120 | 降级（用户决定跳过） | P2 | V006→V012-B→G10/G09 | 页面/Sheet mutation single-flight owner | 共享busy无target会令B卡片动作被丢弃或被A晚到提示打断；Reorganize预览与提交可交叉，但当前Web同样允许，且本项未证明错目标mutation | 既有双审闭合卡片owner与三个Sheet；后续按当前TV/Web触发与后果重裁 | 不做TV单端增强 | 普通快速网络下窗口较短；主要影响为动作无反馈或迟到UI，降P2并由用户决定跳过 |
| F-121 | 已修复 | P2 | V006→W015→G02 | `SubscriptionHandler.forkErrorMessage` 与分享 Sheet 呈现链 | 错误不绑定share presentation/operation，A的同步残留或迟到失败可稳定污染B的可恢复操作界面 | 既有多轮裁决闭合同步链；全新G02 clean-room复核确认operation owner缺口并升级P2 | 错误绑定operationID/shareID，新presentation清旧且拒绝迟到发布 | TV跨目标错误归属P2；迟到调度频率未验证 |
| F-122 | 已修复 | P3 | V005 | `APIService.recognizeTmdbId:2255-2263`、`MediaActionHandler.swift:37-73`、`HomeView.swift:277/295` | nullable 结果把最终无匹配、失败与取消统一呈现为未识别 | 闭合「首段失败 + 兜底成功但无可用 ID」的残留折叠；并把无匹配提示改为按调用方区分 | 两段 error/cancel 已 throws；本轮补齐首段失败暂存错误的最终抛出，且「搜索资源」不再弹提示 | 新增 7 条用例 + 两轮反向验证（2 挂/7 过、2 挂/3 过）；全量 964/964 通过、零失败；错误折叠与误弹窗均已闭合 |
| F-123 | 用户决定跳过（核心链已闭合，剩余低影响） | P2 | V005 | 高层 TMDB action、两阶段识别、默认站点与最终导航链 | 用户动作未绑定发起 session，后续请求可携 B 凭据发送 A 标题 | review_a001_j 闭合 A search 等待→切 B→B recognize 的确定链及全局状态传播 | review_a001_h 独立确认正常 A 空响应后 B 新请求链、与 F-027/F-113 的修复边界及 ResourceResult 快照过晚 | 条件性跨 profile P2 已确认；旧导航/海报可见性未运行验证 |
| F-124 | 已修复（`4a1a291`） | P1 | V006→I010→G02 | 订阅菜单标签/peek task 与 Handler fresh lookup/action | 菜单显示的add/cancel意图在fresh lookup后可反转，显示“订阅”的激活可直接执行无确认DELETE | `4a1a291`：菜单冻结展示意图，lookup后统一校验session，mismatch只刷新提示，取消走destructive确认 | 聚焦5/5、完整本地450/450通过；同一独立复审代理首轮问题修正后最终PASS | 原条件性错误删除P1已闭合；真实后端兼容套件未运行 |
| F-125 | 用户决定跳过 | P3 | V008 | Home Plex link 解析与 v2.15.1 版本快照 | `/server/{machine}/details?key=` 未被旧 `/media/...` 解析器识别，目标身份退化 | verify_a001_h 以本地 v2.15.1 tag 闭合后端生成、Web 解析与 TV fallback | review_a001_j 独立确认 latest/resume 链、Plex 无结构化 ID 时只能从 link 恢复身份，并限制第三方 scheme 结论 | 版本特定 TV 深链缺陷已确认；tvOS Plex 精确 scheme 未验证 |
| F-126 | 已修复 | P2 | V008→W013-A/W020-A/E/F→G02 | 多owner加载失败/取消与成功空或旧快照终态 | Home有10秒自愈但短时无stale标识；Season订阅/availability及System sites/rules各自把部分失败、取消、成功空或旧值混用，恢复入口不一致 | 既有多审确认总根；G02两名不同复核要求按五条子链验收并维持总体P2，驳回“Home永久锁死”扩大 | 各owner分别保留最小success-empty/error/cancel/stale与现有retry；不建统一状态机 | 条件性P2；System部分恢复UI与真实失败时序未运行验证 |
| F-127 | 用户决定跳过修复 | P1 | V008→G02 | Home 重置订阅动作与后端 reset 字段 | 无确认reset会立即覆盖note、缺集、优先级、人工标记与运行状态，远超普通重新搜索 | 既有双审闭合字段范围；全新G02 clean-room复核对照当前后端与Web确认升级P1 | 保持当前直接重置行为，不修改 | 条件性持久状态破坏P1；用户接受误触风险 |
| F-128 | 已修复 | P3 | V008 | Home 媒体库跳转、unsupported/invalid/openURL rejected 出口 | 用户点击失败只记录日志，无可见反馈 | 已知不支持类型隐藏动作入口；其余失败经 onFailure 出口复用 NotificationManager 提示 | HomeViewModelMediaServerLinkTests 12/12 通过；全量 636 测试仅既有 SSE 兼容失败 | 纯 TV 动作反馈缺陷已确认；第三方 App 能力未验证 |
| F-129 | 用户决定跳过（2026-08-16） | P2 | V009-B→V009-E/F→G01/G04 | Explore Popular 去重 key 与 `MediaInfo.id` | 无有效结构身份时title区分去重项，但实际SwiftUI ID不含title，形成重复ID与错误firstIndex/loadMore | 既有双审确认；G01纠偏与G04独立复核再次闭合A/B反例并双票升P2 | 与F-138共用中央identity修复但保留Popular回归 | 条件性TV列表身份缺陷；真实Popular坏身份频率未验证 |
| F-130 | 已修复（`90b40b4`） | P1 | V009-C→V011-C→V012-A→W006-B/W020-A…F/R001/I006→G04 | 存活页面权限派生状态与currentUser发布 | 来源/模式/route/focus/受限快照与child Paginator不随session/权限收敛，旧items/error可跨profile先于父gate发布 | `90b40b4`：统一session UI identity重建Tab子树，session转换取消旧runtime并清缓存，epoch拒绝旧发布 | 聚焦会话/缓存/分页/根页面测试96/96通过；既有独立复审PASS | 原TV跨profile根状态P1已闭合；真实Apple TV焦点视觉未单独复演 |
| F-131 | 已修复 | P2 | V009-D/E→G05 | Douban/Bangumi/AniList 动态年份集合 | `Calendar.current` 的非公历年被直接显示并发送为 API 年份 | 三处年份字典固定 `Calendar(identifier: .gregorian)`，不动筛选结构 | ExploreViewModelYearDictTests 4/4 通过；全量 640 测试仅既有 SSE 兼容失败 | 条件性 TV locale/API 缺陷已确认；非公历实际配置未运行验证 |
| F-132 | 已修复 | P3 | V009-D/E | TMDB movie/tv sort 字典与类型切换 | 独占 sort key 跨类型残留，Picker 无匹配却继续发请求 | onTypeChanged 按 Web 端成员归一化：非法独占 sort 回落 popularity.desc、共有 sort/genre 保留、Douban category 不再误清 | ExploreViewModelTypeSwitchTests 6/6 通过；全量 646 测试仅既有 SSE 兼容失败 | 纯 TV 状态一致性缺陷已确认；后端处理非法 key 未验证 |
| F-133 | 已修复 | P3 | V009-A/F | 插件 `filter_ui` parser 与 FilterPickersView | 未支持控件/多选/show/VRange 值形被静默删除或降级 | 官方插件仓库核实 tvdbdiscover/imdbsource 载荷；parser 已支持实际控件 | VRange 保留单选 UI，默认数组投影下限，选择后写回 `[selected,upperBound]`；其余控件沿既有实现 | slots/onXXX 无真实载荷，不引入通用 FormRender |
| F-134 | 已修复 | P3 | V009-A/E/F | 复合插件筛选值的 query serialization | 数组/对象被 JSON 化为单值，与 Web Axios bracket 形状不同 | IMDb `user_rating=[1,10]` 与后端 `user_rating[]` 确认合同；既有 flattener 已按 Axios 展开 | 本轮 VRange 选择写回合法数组后复用既有序列化，产生两个 `user_rating[]` | 后端契约仅对 IMDb 插件核实 |
| F-135 | 已修复 | P3 | V009-A/F→W012 | `ExploreViewModel.swift:243-262`（`collectOptions` first-wins 去重）、`AddDownloadViewModel.swift:40-58`、`SubscribeSheetViewModel.swift:74-83`、`Models.swift:1719-1731`（`storage` 可选化） | 重复value同时成为ForEach ID与Picker tag；空目录还与内建自动重复空ID或生成`storage:` | 插件按 `JSONValue` first-wins 去重（单遍展开后消重，父级/子级重复同样覆盖）；目录**先 trim、再丢空、最后去重**，使内建「自动」天然唯一；**不新增 option ID 层** | 定向 39/39；反向验证四处一并还原 → 8 挂 / 5 条阴性对照通过；全量 **977/977 通过、零失败**（964 + 13），逐名比对无用例消失 | 🆕 ①②Web 方向一致但**更不完整**（Web 三个弹窗只有一个 trim，本修复覆盖全部）；③ Web 无 option 收集中间层，属 TV 独有防线；`storage` 可选化为顺带加固，可达性未证实 |
| F-136 | 未验证 | P3 | V009-E/F | Share 默认排序状态与 v2.15.1 Web | TV 初始/切源均用 count，目标版本 Web 默认 time | verify_a001_h 闭合两处 literal、首路径与版本特定 Web/test | review_a001_j 两次独立确认版本差异，但 TV 产品默认意图缺失 | 条件性默认行为未验证；产品确认 Web 对齐或 TV 特例时收敛 |
| F-137 | 已修复 | P2 | V011-A/B→G04 | `fuzzyMatchScore` 类别带与 top-12 | 无界长度罚分穿透prefix/contains/subsequence/nonmatch分档并可把真实匹配挤出最终top-12 | 既有三票闭合反例；全新G04 clean-room复核确认四类交叉与最终截断并升级P2 | 保持Int评分，类别带宽互不重叠（全等1000/前缀700/包含400/顺序100-299）且长度罚分封顶；顺序匹配采用fzf风格词首/连续加分 | 条件性搜索结果缺失P2；真实长标题竞争频率未验证 |
| F-138 | 已确认 | P1 | V010→V011-B/D→V012-A→G01/G04 | 共享 `MediaInfo.id`、缓存任务与 first-wins 去重 | title-only/collection等对象可碰撞丢项，并把列表、导航、pin及preload task绑定到错误owner | 既有三代理确认机制；G01纠偏与G04独立复核从中央ID到缓存/导航双票升P1 | `ff4ea14`在无任何现有媒体ID时追加trim后的标题兜底，保留0/空串及分享快路径 | 依赖解析、Simulator clean build、本地451/451测试及独立复审通过；真实后端兼容套件未运行 |
| F-139 | 已修复（2026-08-21） | P2 | V010→V012-A→G01/G04 | 推荐/详情分页成功空终态与页面再激活 | retained shelf、详情或合集首批成功空后，再激活不刷新且无恢复入口 | 既有双审确认；G01纠偏与G04独立复核再次闭合retained激活链并双票升P2 | Recommend接入Tab选中边沿并调用现有成功空恢复；详情/合集保留既有恢复，不动Paginator状态机 | View接线测试、SuccessEmpty回归及相关定向47/47通过；真机可见表现未验证 |
| F-140 | 已修复 | P3 | V011-B | `SearchViewModel.swift:432-449`（`autoSearch` 提交口规范化） | 空白未统一规范化，精确标题可退化并被扩展标题反超 | 提交口 trim 首尾空白与换行后 `guard` 空串，请求与本地评分共用同一串；不写回 `query`、不压缩内部空白 | 定向 42/42；反向验证还原提交口 → 2 挂 / 阴性对照（内部空白保留）通过；全量 **982/982 通过、零失败**（977 + 5） | 🆕 逐字复现：exact `-1`（审计同）/ extended **684**（审计写 484，实测不符）；后端 `StringUtils.get_keyword` 确有 `.strip()`，缺陷仅存在于 TV 本地评分层；Web 无本地评分层故无此面 |
| F-141 | 已修复 | P3 | V011-B | `SearchViewModel.swift:170-200`（`calculateBestResults` 年份词法） | 首个任意四位数字片名被 TV 误作年份，括号移除又残留空壳 | 年份词法改为 `[\s(]+((?:19\|20)\d{2})[\s)]*`，与后端 `get_keyword` 同构：数字须紧跟分隔符；剥年份连前导分隔符与尾随右括号一起删 | 定向 42/42；反向验证还原词法 → 2 挂（`1917 2019` 精确项被整条淘汰、`流浪地球 (2019)` 只剩扩展项）；全量 **982/982 通过、零失败** | 🆕 保留 `(19\|20)` 前缀而不照搬后端裸 `\d{4}`（年份用于补 `标题+年份` 变体，放宽只会新增误判）；「剥完为空 → nil」纯属契约收敛，可观测行为不变 |
| F-142 | 已修复（2026-08-18） | P2 | V011-F 复核/裁决 | `SharedMediaFetcher.currentFetchTask` 合流/退休 | 完成 task 的 handle 未清，另一 waiter第二轮重放后返回非终止空批 | review_a001_j 闭合双 waiter恢复顺序与第3页目标类型反例 | review_a001_h 独立状态机确认0→2后重放2→2、actor调度可达及F-034/F-039独立 | 已修：task 内部按 identity 退休句柄；定向回归 1/1 通过 |
| F-143 | 已修复（`40adb42`/`d2972b3`） | P2 | V013→G07 | Person route准入与请求owner | 当前可点击的内嵌导演可缺source，人物API在发请求前即失败；稀疏成功回包另拆F-227 | 既有双审闭合无身份死页；G07三方以当前TV/Web/后端窄化为内嵌导演路径 | 后端人物生产边界补真实source；TV只可用父source兼容旧载荷，无法确认则禁用 | TV兼容修复已完成（`40adb42`、`d2972b3`）；真实后端混合元数据仍未验证 |
| F-144 | 部分修复（2026-08-18）；系统页用户决定不动 | P2 | V013→W020-A→G02 | 串行首载与吞取消后晚启动下一阶段 | 人物/Transfer/System串行加载外，TMDB识别search取消还会被宽catch吞掉并继续启动fallback请求 | 既有多审确认串行/晚启动；G02两名不同复核闭合取消后fallback确定请求并升级P2 | 复用async let；各catch先传播CancellationError并在fallback前检查取消 | 人物与TMDB识别已修；系统页按用户决定保留，loadInitialData维持串行 |
| F-145 | 已修复（2026-08-18） | P2 | V016→G05 | AddDownload 下载器 Picker 与 Optional 请求字段 | 选中下载器后无法在同一Sheet恢复初始省略状态 | 既有双审确认；G05主审与独立复核均闭合nil→选择→无法回nil、请求省略语义及仓内“自动”空项反证 | 在现有options前置“自动”空tag，复用Binding；不与F-168合并 | 已修：下载器 options 前置“自动”空项；定向回归 1/1 通过 |
| F-146 | 已修复（`0cfeb12`） | P1 | V017→W013-B | SubscribeSeason剧集组请求/选择/入库与payload owner | 旧group请求可覆盖新选择并把A季显示为B订阅目标，点击后产生错误远端订阅 | V017与W013-B双审均闭合A慢B快→A覆盖seasonInfos→按当前B查入库/生成payload的同session链 | `0cfeb12`冻结剧集组、revision与session并统一latest-owner发布 | 两条定向乱序回归及当前本地451/451测试通过 |
| F-147 | 部分修复；接受残余风险 | P1 | V018→W014/W018-A | Sheet mutation期间取消/关闭生命周期 | Subscribe可形成PUT/DELETE持久竞跑；整理关闭后仍发后续POST并迟到回调 | V018/W014双审维持P1；W018-A传播按P2 | Subscribe P1由`a872737`修复；整理只禁用显式取消按钮，系统关闭/任务owner/迟到回调未完整关闭 | 用户接受整理 P2 残余风险，本轮不改代码 |
| F-148 | 用户决定跳过 | P1 | V018→W013-B→W014 | SubscribeSheet临时订阅created/owner/session回滚收据 | loading替换唯一onDisappear钩子可误删/漏删；API又丢失created/reused区别，使既有订阅被无条件暂停并在取消时删除 | V018双审闭合Retry/退出链；W013-B与W014不同代理闭合当前后端`exist_ok`复用ID合同 | G02/G10稳定根关闭钩子、created ownership receipt、单一ID owner及恰好一次回滚矩阵 | 条件性P1；真实生命周期帧序、部署版本与触发频率未验证 |
| F-149 | 已修复 | P1 | V019→W016/G09 | StatusViewModel三个Dashboard请求发布 | 固定await顺序与单catch形成混合运维快照，且同权限A会话结果可写入B会话 | 既有双审闭合分项失败混合快照；G09两名代理确认三请求无session owner及A→B发布链 | 局部收齐tuple、校验现有session snapshot后一次发布；失败保留上一完整快照并标stale/error | 条件性跨会话运维数据污染已确认；真实切换/失败频率未验证 |
| F-150 | 已修复 | P2 | V019→W016 | manage-only状态页的superuser卡片可见性 | 已知无权查看被固定渲染为三张“暂无数据”卡 | V019双审闭合可达链；W016双审确认合法角色每次稳定看到三块系统性伪空态 | 复用canRequestSuperUserEndpoints隐藏三卡或显示一次权限说明，并保留下半页功能 | 跨端页面设计未验证 |
| F-151 | 用户决定跳过 | P1 | V021→W018-B/I015/G09 | Reorganize预览条目去重与实际逐intent提交 | 不同intent/logID解析为同一路径时预览只显示一次，实际仍执行多次文件mutation | 既有双审闭合投影/跨logID丢provenance；G09两名代理确认当前测试反向固化“显示一次、提交多次” | 删除TV二次去重，或让预览携带logID/intent索引并与submit使用同一规则 | 用户决定按当前官方Web v2共享行为跳过修复，不做TV单端增强；真实碰撞分布未验证 |
| F-152 | 已修复（`fc0cefa`） | P1 | V022-B→G09 | TransferHistory批删确认目标快照 | alert文案和action读取实时selectedIds/items，可在确认期间删除不同集合或同ID新记录 | 既有双审闭合列表变化链；G09两名代理结合F-204 SQLite同ID复用确认破坏性错目标 | 呈现alert时冻结对象签名数组，文案与action只消费该快照 | 条件性错误删除已确认；真实批删中变化频率未验证 |
| F-153 | 已驳回 | P3 | V022-B→G09 | TransferHistory删除与Paginator游标协调 | 稳定排序前提下删除回退是保守且可补偿的，未形成独立漏页缺陷 | 早期双审反例被G09两名代理按`ceil(deleted/pageSize)`与最多两页重复扫描重新推演反驳 | 不改算法；补删除+插入+loadMore集成测试，排序不稳定归F-232，ID复用归F-204 | 当前独立缺陷驳回；真实集成行为仍作P3测试缺口 |
| F-154 | 已驳回 | P3 | V022-C→I009/G09 | TransferHistory轮询插入余数与loadMore游标 | 稳定排序前提下整页推进、余数重叠去重的算术自洽，未形成独立跳页缺陷 | 早期双审反例被G09两名代理重新推演反驳；1/19/20/21项矩阵仍缺测试 | 不改算法；仅补插入组合测试，不稳定排序统一归F-232 | 当前独立缺陷驳回；高频真实交错保留P3测试边界 |
| F-155 | 已修复（2026-08-18） | P2 | V022-C→I009 | TransferHistory轮询多页扫描上限 | 第6页已请求成功却在处理前退出，101st新项被永久越过 | 既有双审闭合页6丢弃；I009主审/独立复核确认前100项提交后下一轮无法恢复 | 扫描未找到已知边界时不提交前缀/推进游标，回退现有refresh | 已修：扫满上限未遇边界时回退权威刷新；回归 22/22 通过 |
| F-156 | 已修复（2026-08-18） | P1 | V022-D→W018-A/G09 | TransferHistory旧动作与选择状态owner | 选择、删除、AI、整理只持有可复用Int ID；旧UI/alert可对同ID新记录执行破坏性动作 | 既有双审闭合迟到收尾清新选择；G09两名代理结合F-204确认后端按ID重查当前行的错对象mutation链 | 与F-152/F-204共用session/query和对象签名快照；不建任务框架 | 已修：核心交互/选择入口由`fc0cefa`冻结，整理Sheet迟到收尾改按intent id移除本次；回归 23/23 通过 |
| F-157 | 已修复（2026-08-21） | P2 | V023→W020-A/W020-C/G06 | settings加载与后端版本检查终态 | 失败/取消被永久记成检查完成；同owner恢复成功仍不清旧兼容警告 | 既有多审闭合不可恢复状态机；G06 两票确认首次瞬时失败后前台固定不重判且无显式retry | 只有有效版本/明确不兼容才写terminal key；unknown/failure保持可重试 | 已修：失败不占检查终态；前台成功只收敛仍存在的警告，不重建已关闭的同key低版本警告；相关定向47/47通过 |
| F-158 | 用户跳过（2026-08-20） | P2 | C001→W009/W011/W018-B/W019→G05 | 无操作焦点目标 | EmptyDataView无action、人物/整理空Button、资源重定向器及历史/下载空动作Button生成无操作焦点节点 | 既有多审确认；G05两名代理将P2锚定在DownloadTask主行稳定可按但无动作，其他透明sink的实际落焦仍属运行边界 | 有主动作放入原生Button action；无主动作删除空Button/focus sink | Download主行静态P2；其他Focus Engine/VoiceOver命中频率未验证 |
| F-159 | 用户跳过（2026-08-20） | P3 | C002 | 全局短暂错误通知的可访问性传达 | 五秒toast无主动announcement，唯一错误反馈可被VoiceOver用户错过 | review_a001_h主审与review_a001_j独立复核确认5文件6个生产show、根唯一presenter、全仓无announcement且tvOS17原生API可用 | G08及调用页回溯逐次type+message播报、同文案重发与单一元素语义 | 实际VoiceOver/盲文漏传频率未验证 |
| F-160 | 用户跳过（2026-08-20） | P2 | C003→G10 | ActionRow主Button与实际手势语义 | Transfer核心选择只挂simultaneous TapGesture，语义Button action为空；辅助功能默认激活可无动作 | 既有双审确认结构；G10主审/独立复核区分核心Transfer操作与无主动作Download行并确认P2 | 有tap时直接放入Button action并删重复TapGesture；无主操作改非Button | 静态控制语义缺陷已确认；真实VoiceOver路由仍待运行 |
| F-161 | 用户跳过（2026-08-20） | P2 | C003→W020-B/G09 | 非活动UI的focus/accessibility门禁 | ActionRow隐藏Button仅opacity(0)，仍保留原生Button、focus绑定与激活语义 | 既有双审确认静态结构；G09两名代理均评P2，其中一票保留Focus Engine条件边界 | 非活动时用原生disabled/hit-testing/accessibility门禁或按active构建；验证转换 | 静态控制树缺陷已确认；真实落焦/VoiceOver频率未验证 |
| F-162 | 已修复（2026-08-20） | P2 | C004→W018-B/W020-C/G09 | Sheet与System静态行长反馈完整性 | 共享反馈强制单行，整理预览限两行，长错误/路径没有完整读取入口 | 既有多段双审闭合；G09两名代理确认当前失败原因/路径稳定被限行且无展开 | 删除共享限制；允许完整换行并纳入现有ScrollView | 已修：共享反馈 lineLimit 1→3；整理预览行维持 2 行（用户指示保留）；tvOS Simulator 构建通过 |
| F-163 | 未验证 | P3 | C004 | 旧系统Sheet自定义样式的disabled外观 | 26.0–26.3样式不读isEnabled，禁用与启用未聚焦控件作者样式相同 | 双审确认Button/Toggle静态缺口及可达disabled实例，但标准交互门禁与系统外层视觉仍可能成立，MultiSelection另有opacity反例 | tvOS 26.0–26.3验证disabled视觉/focus；26.4+不受影响 | 条件性P3；运行外观未验证 |
| F-164 | 未验证 | P3 | C004 | Fork Sheet旧系统样式接入 | 唯一SheetActionButton所在根树漏用applySheetStyles | 双审确认Search/Explore两入口及父树均不传播该modifier，但漏接本身不能证明旧系统按钮确实错画/错焦 | tvOS 26.0–26.3验证Fork原始渲染/焦点后裁决 | 条件性P3；运行症状未验证 |
| F-165 | 用户降级（2026-08-20） | P3 | C004→W018-B/W019/W020-C/G09 | Sheet内容内显式退出可发现性 | 多个业务Sheet缺少内容内关闭/取消，当前源码测试还反向固化该结构 | 既有多段双审确认；G09两名代理从Manual/Preview/Transfer detail与辅助功能语义共同支持P2 | 各Sheet复用原生取消/关闭并更新反向源码测试 | 用户裁决：系统Back可退出，按P3暂缓，不修 |
| F-166 | 已驳回 | P3 | C005 | 旧系统SheetTextField的disabled传递 | 桥接未转发isEnabled，但当前生产入口无法令唯一disabled条件为true | review_a001_h独立枚举两个Reorganize入口均为非空历史logIds，isFromHistory分支无条件令isEpisodeDetailDisabled=false | 已闭环；未来新增非历史目录入口时重开桥接测试 | 潜在桥接债务不构成当前生产缺陷 |
| F-167 | 未验证 | P3 | C005 | UIViewRepresentable托管根视图几何 | 旧系统文本框聚焦直接修改SwiftUI托管根UIView的transform | review_a001_h发现、verify_a001_h独立确认managed root两次写入、26.0–26.3共16调用可达及官方契约违反 | 删除scale/identity两次写入；目标OS验证布局/焦点动画/更新冲突 | 可见用户故障未验证 |
| F-168 | 用户跳过（2026-08-20） | P2 | C006→W020-E/F→G05 | 自建选择页上下文、选中语义与初始焦点 | SheetPicker丢title且无selected语义；System来源/过滤页固定首焦清空项而非当前选择 | 既有多审确认；G05主审与独立复核均确认title被丢弃、选中项无结构化语义并支持P2 | 显示既有title、给当前项isSelected并复用最小默认焦点 | 静态上下文/选中语义P2；真实初焦、VoiceOver播报与动态删除回退未验证 |
| F-169 | 已修复 | P3 | C007 | `MoviePilot-TV/Views/Components/ShelfPicker.swift:74-76`（`ShelfChip.accessibilityTraits`）、`:90`（挂载点） | 当前货架只做视觉 overlay，Button 没有 isSelected trait/value | 修复依据：review_a001_j主审与verify_a001_h独立复核确认唯一 Recommend 调用、focus/selection 分离及默认 Button 仅有名称/动作语义抽 `accessibilityTraits` 属性（`isSelected ? .isSelected : []`）并挂在 Button 链尾；不加自定义 label/value，不引入 selection/focus 框架，名称仍由 `Text(title)` 提供 | 定向 6/6；反向验证分两层：①把属性置空 → 2 挂（选中项不带 trait、只加一个 trait 的断言）/ 2 阴性对照通过，接线守卫仍过；②只拆接线、保留属性 → 4 条行为测试全过 / 接线守卫 1 挂；全量 **997/997 通过、零失败**（991 + 6） | 🆕 两层测试各守一种失败模式（规则写对 vs 规则挂上），单测任一层都会漏掉另一种；Web `MediaRecommend.vue:369` 有 `aria-current` 可对照，但 TV 是遥控器焦点模型、焦点与持久选择可分离，故只加 trait 而未照抄；真实困惑频率/播报措辞仍未验证 |
| F-170 | 已修复（2026-08-20） | P2 | C008→W014/W020-D/E | 选项域外已选值 | 已选但不在options的站点/规则组不可见、不可移除；System还会自动归一化并删除合法或暂缺选择 | C008/W014双审闭合主链；W020-D/E补站点/规则传播 | 显示可移除不可用项；仅正确权威域成功后归一化且未经确认不删除 | 已修：MultiSelectionSheet 显示“清除不可用选择（N）”区，只做集合减法；回归 4/4 通过 |
| F-171 | 用户跳过（2026-08-20） | P2 | C009-A→I010→G03 | MediaCard徽章元数据可访问性 | 类型/评分、订阅/入库状态及来源均在Canvas symbols中且无替代语义，持久状态对辅助功能用户不可达 | 既有双审与I010确认机制；G03两名纠偏复核再次独立闭合全部生产卡片owner并升级P2 | 先按F-175建立原生整卡owner，再拼实际可见徽章accessibilityValue | 静态缺失已确认；VoiceOver焦点顺序/播报措辞未运行验证 |
| F-172 | 已确认 | P3 | C009-B→W006-D | 卡片缺图占位类型 | nil/空/未知typeText统一回退电影glyph；最佳合集卡还可显示原始类型文本 | 双审确认MediaCard生产链；W006-D双审补collection_id有效但nil/英文/系列类型仍导航合集却显示电影glyph | 各卡片/调用页/G03回溯中性glyph与统一displayTypeText测试 | 缺图/加载中触发频率未验证 |
| F-173 | 未验证 | P3 | C009-B | MediaCard图片处理链 | downsampling后再append硬编码resizing，冷处理路径多一次栅格化 | 双审确认锁定Kingfisher 8.10.0 processor追加/缓存key；processed-cache命中绕过处理、默认2:3同尺寸为反证 | 删除resizing后需真机Instruments与像素/缓存冷启动验收 | 条件性性能影响未验证 |
| F-174 | 用户跳过（2026-08-20） | P2 | C009-C→W006-C→I010→G03 | MediaCard详情转场源owner | 任意MediaCard主动作都会写无目标/动作owner的全局sourceFrame；分享/编辑等非详情动作遗留值可被后续无源详情消费 | G03两名纠偏复核独立闭合Search分享Sheet→后续详情生产链并升级P2；loadingPosterURL/session仍留F-123 | 只在实际详情push写目标绑定的一次性frame payload；不合并F-123/F-118 | 纯TV错误转场已确认；真实动作顺序与视觉持续时间未运行验证 |
| F-175 | 用户跳过（2026-08-20） | P2 | C010→I011/I010 | 自定义卡片主操作可访问性 | PersonCard、TorrentCard及MediaCard以raw focusable/onTap承载主动作，没有原生Button/disabled控制语义 | 既有Person/Torrent三方裁P2；I010两代理确认MediaCard同根传播 | 三类卡复用原生Button与现有route/download gate，不建卡片框架 | 静态控制语义缺口已确认；VoiceOver/遥控实际表现待运行 |
| F-176 | 已修复（2026-08-20） | P2 | C010→G04 | 详情横向行焦点分页 | 三个FocusState变nil都会绕过threshold调用强制loadMore，重复离行可逐页消耗到真实终页 | 既有双审闭合三处调用；全新G04 clean-room复核确认静态请求链并升级P2 | 三处调用前`guard let newId`；不改Paginator公共nil语义 | 已修：演员/推荐/相似三处 onChange 失焦 nil 直接 return；Paginator/TransferHistory 回归 47/47 通过 |
| F-177 | 未验证 | P3 | C010 | PersonCard图片处理 | 冷缓存人物图先构造原图再用ResizingImageProcessor重绘 | 双审确认Kingfisher 8.10.0数据/processor链与演员/搜索分页；cache命中/后台queue/近目标原图为反证 | resizing换downsampling后需真机Instruments/像质验收 | 条件性性能影响未验证 |
| F-178 | 已确认 | P3 | C012→W006-C | 搜索评分名与展示名投影 | 备用名称可获最高匹配分，但最佳卡与普通媒体/人物行只显示主名称而出现空标题或“未知” | C012双审闭合媒体original_title与人物latin_name反例；W006-C双审确认普通行同根传播 | 评分与展示共用现有有序非空名称候选；不建新匹配或卡片框架 | 条件性P3；真实备用名payload频率未验证 |
| F-179 | 已修复（2026-08-20） | P2 | C017→G05 | 资源卡/筛选展示字符串规范化 | 空串或纯空白值可遮蔽有效fallback、生成悬空分隔符或不可辨识标签 | 既有双审闭合字段矩阵；G05主审与独立复核均确认卡片与筛选的稳定分裂并支持P2 | 复用现有trim→空为nil投影后再fallback/渲染/筛选；不建资源展示模型 | 已修：卡片标题/描述/季集/标签与筛选三链统一trim→空为缺值；新增规范化测试10/10、排序回归4/4通过 |
| F-180 | 已修复（2026-08-20） | P2 | W007→I013 | 详情失败终态呈现 | 三次主详情失败被当成ready，静默揭开未完整初始化的partial页面且无当前页错误/重试 | 既有三方闭合机制；review_a001_j第三裁确认主详情静默失败独立P2并保留Back重进反证 | partial旁显示明确失败与原生Retry，复用failed-task重建 | 未做页内失败/Retry；失败终态改Logger记录并触发全局横幅“详情加载失败，请重试。”，静默呈现保留 |
| F-181 | 用户跳过（2026-08-20） | P2 | W008-A→I013 | Hero到内容页焦点切换 | 只监听Hero并即时采样Content，若Hero先false、Content后true会漏置showContentPage | 三代理确认静态交错；review_a001_j最终裁定事件顺序未证，若运行复现影响为P2 | 先记录Simulator/真机事件序；确认后分别监听两个现有FocusState | 未验证条件性P2；真实事件顺序和可见影响未验证 |
| F-182 | 用户跳过（2026-08-20） | P2 | W008-B→I008 | 详情前台及60秒订阅刷新 | scene/周期仍以本地active状态决定是否强刷，旧false/空分季可无限不发现远端新增且首次点击静默终止 | 既有双审闭合false→true链；I008整文件主审确认无时间上界的核心CTA错误 | review_a001_h独立确认P2；活跃可订阅详情复用现有强刷，不新增轮询框架 | TV静态用户链已确认；真实跨设备频率与后台时序未验证 |
| F-183 | 未验证 | P3 | W008-C | TMDB按钮动作重入 | 每次激活创建独立Task，双激活可重复append同一目标并让共享busy提前清除 | review_a001_j提出静态链；verify_a001_h不读审计文档第三裁决机制成立但tvOS第二次Select可达性无证据 | 先做双Select序号日志；确认后在Task前同步设置本地in-flight标志 | 条件性P3；真实输入窗口与导航表现未验证 |
| F-184 | 已修复（`e0f1122`） | P1 | W008-E→W010→I013/I010 | 合法正数`collection_id`合集route身份 | 动态来源可正式返回合集；三根栈仍送入普通Container，inert preload永不ready/failed且每次重进必现 | I013第三裁确认条件P1；I010独立复核机制但建议P2，作为等级异议记录不重开既有裁决 | `e0f1122`统一四根导航与来源无关的预载门禁，不建route框架 | Simulator clean build、487/487本地测试与独立复审通过；0/负数、parts包装/递归仍未验证 |
| F-185 | 用户跳过（2026-08-20） | P2 | W009→W013-C→W015/W018-B/W019/W020-B | 模态Sheet长文本/路径可达性 | 无上限正文、整理汇总、完整路径、未来errmsg或自定义规则摘要在固定viewport/限行中不可完整读取 | 既有多段双审确认；W020-B主审补五行规则预览且无展开/滚动入口 | 信息区使用原生ScrollView/完整换行，操作区固定并验证遥控器/VoiceOver | 条件性触发；真实长度阈值未验证 |
| F-186 | 已修复（2026-08-20） | P2 | W011 | 资源促销筛选枚举 | TV从数值倍率重算并压扁后端`volume_factor`，筛选值与卡片/Web分裂 | review_a001_j提出并核对当前上游；verify_a001_h无W011污染独立确认30/70/4X/2X 50%反例 | 删除重算helper，筛选直接复用现有`volume_factor`并覆盖完整枚举 | 已修：删除 getFreeState 重算，筛选三链直接用 volume_factor（空白视为无促销）；规范化测试 13/13、排序回归 4/4 通过 |
| F-187 | 用户跳过（2026-08-20） | P2 | W011 | 资源空/错终态恢复 | 业务error、transport失败或成功空均进入无action空态，hasSearched阻止同页面再次请求 | review_a001_j提出错误/空无重试；verify_a001_h确认三类终态与现有根因均不能提供retry contract | 复用EmptyDataView action，调用现有cancelSearch后重新search | 用户只能退出重进；真实故障/空结果频率未验证 |
| F-188 | 已驳回（旧v2.14.4基线历史机制保留） | P1 | W012→W018-A/G09 | 下载/整理高级媒体ID端点合同 | 旧后端只消费专用ID；`3b709b7`随后统一媒体来源身份合同 | 原审计使用后端v2.14.4；目标v2.15.1已包含2026-07-21提交`3b709b7`，并非报告后修复 | 当前TV按v2.15.1统一字段保持不变 | 对目标版本属于审计基线过旧误报；历史裁决仅保留作审计记录 |
| F-189 | 已驳回（旧v2.14.4基线历史机制保留） | P1 | W001→W012/W018-A/W020-D/G09 | 手动媒体搜索来源owner | 旧后端忽略source；`3b709b7`随后统一媒体来源身份合同 | 原审计使用后端v2.14.4；目标v2.15.1已包含2026-07-21提交`3b709b7`，并非报告后修复 | 当前TV按v2.15.1统一来源合同保持不变 | 对目标版本属于审计基线过旧误报；历史裁决仅保留作审计记录 |
| F-190 | 已确认 | P3 | W013-C | SeasonDetailSheet季名与可选文本投影 | S00缺名显示“第0季”而卡片显示“特别篇”；空白name/date/overview又生成空标题、图标空行或空壳区域 | review_a001_h主审与verify_a001_h独立复核闭合nil/空/纯空白输入及同页文案分裂 | 复用现有字符串trim→nil；S00/有效季/缺季号使用一套回退规则 | TV显示不变量缺陷已确认；真实空白payload频率未验证 |
| F-191 | 已确认 | P3 | W013-C→W015 | SeasonDetail/Fork Sheet海报容器几何 | processor按360×540降采样但外层只约束width；缺图/失败只剩无固有2:3高度的Rectangle，四态无法保证稳定海报尺寸 | W013-C第三裁决成案；W015主审独立确认Fork的URL缺失/loading/失败/成功四态同根 | 两个Sheet外层容器直接固定360×540；覆盖四态 | 静态布局契约缺陷已确认；实际塌缩/拉伸形态与焦点影响未验证 |
| F-192 | 已修复（`b304b58` 范围内处置；后端对象级授权风险范围外） | P1 | W016→W017 | 下载任务列表与mutation owner授权 | manage-only用户可看到并暂停/继续/删除其他用户任务，当前后端list/start/stop/delete只验token且owner回填只按hash | review_a001_j与review_a001_h闭合原跨用户反例；`b304b58`后独立复审确认TV普通用户展示过滤逐字对齐Web | `b304b58`仅补Web同款`userid/username`展示过滤；不修改后端 | 用户确认范围已完成；后端对象级授权缺口作为明确接受的范围外风险保留 |
| F-193 | 已修复（2026-08-28） | P2 | W015→G06→当前实现复核 | Fork POST→GET→编辑器operation owner | `90b40b4`已把POST结果绑定来源profile/session，切账号或切服后旧ID不能在新owner下继续GET或呈现；同一profile内A/B并发、关闭Sheet后的迟到结果及GET-only恢复仍共享单一状态槽 | 跨profile回归`testForkedEditorDoesNotContinueUnderAnotherAccount`通过；当前Handler/Sheet静态复核确认剩余同会话竞争 | 后续若处理，只在现有Handler内增加同会话operation owner与GET-only receipt，不扩账号框架 | 已修复（2026-08-28）：Handler 内 operationID+receipt，同分享 GET-only 重试不重复 POST，迟到发布按当前操作作废；4 条新回归 + 751/751 测试通过 |
| F-194 | 用户跳过（2026-08-20） | P2 | W015 | Fork最终确认字段完整性 | POST立即持久化keyword/custom_words，但TV确认页不展示，用户无法预见将生效的搜索/识别规则 | W015双审对照TV编码、当前后端持久化与Web显示闭合多行规则反例 | 按Web最小边界只读展示非空keyword/custom_words并支持展开/滚动 | 两字段缺口已确认；其他过滤字段是否须展示未验证 |
| F-195 | 用户跳过（2026-08-20） | P2 | W014 | SubscribeSheet custom_words多行编辑合同 | 后端按LF拆分多规则且Web使用textarea，TV单行TextField无法创建/可靠审阅第二条规则 | W014双审闭合SheetTextField/UITextField、Web VTextarea与后端split链 | 仅该字段复用tvOS多行编辑器并保留LF原值 | 编辑能力缺口已确认；既有LF聚焦后是否改写须运行验证 |
| F-196 | 已修复（`e47693a`） | P1 | W017 | 下载删除确认与实际文件范围 | UI原来只确认“删除任务”，当前后端默认delete_file=true并由Transmission执行delete_data=true | W017双审闭合永久文件删除链；用户确认保留现有TV确认、不改接口和后端 | `e47693a`将确认文案明确为“将永久删除任务及已下载文件” | 按用户要求仅改一行文案并直接提交，未运行测试、未做子代理复审；后端行为保持不变 |
| F-197 | 用户决定跳过 | P1 | W017→G05 | 未完成下载暂停后的列表可恢复性 | stop成功后qBittorrent/Transmission任务不再属于当前downloading查询，下一轮从TV/Web消失并失去继续入口 | 既有双审确认且当前TV/Web共享行为 | 不做TV单端缓存兜底；CHK-016已写入正式兼容清单 | 等待MoviePilot官方后端/Web更新后同步对齐；当前行为保持不变 |
| F-198 | 已修复（2026-08-21） | P2 | W016→G09 | Status剧集统计nil展示 | 后端None/Web“未获取”被TV折叠为确切0 | 既有三票确认静态误报；G09两名代理按当前后端明确nil语义与跨端稳定差异共同支持P2 | 仅View层nil→“未获取”，0与正数原样 | 已修：StatusView 的 nil 显示“未获取”，0/正数保持原值；投影测试 1/1 通过 |
| F-199 | 已修复（`ce7afcc`） | P1 | W014→G02 | Subscribe total_episode null保真 | 无编辑GET→PUT把nil/absent固化为0并令当前后端置`manual_total_episode=1`，永久关闭自动总集数刷新 | 既有两票与G02闭合跨端链；`ce7afcc`后独立复审确认null/省略/输入边界对齐 | 现有订阅nil显式编码null；新建nil仍省略，负数/空白/非法输入归一为nil | 修复完成；490项本地测试通过，F-069其余完整PUT保真边界仍开放 |
| F-200 | 用户决定跳过 | P2 | W014→G01纠偏 | Subscribe save_path开放值域 | 既有任意值和配置中已有URI可显示并原样保存，但封闭Picker无法新建或编辑任意合法子路径/URI | 既有双审确认开放合同；G01按当前TV/Web再次核对并驳回“已有值必丢/已配置URI不可选”的扩大说法 | 复用现有文本输入直接绑定String，配置路径只作快捷建议 | 条件性P2；用户决定跳过（2026-08-28），现状保持不变 |
| F-201 | 已修复（2026-08-28） | P2 | W019 | Transfer失败原因可达性 | 模型已解码errmsg，但列表与详情只显示“失败”，TV内没有任何读取路径 | verify_a001_h与review_a001_h双审对照TV模型/View、当前Web tooltip与后端语义闭合 | 仅在可滚动详情展示trim后非空errmsg，列表保持紧凑 | 已修复（2026-08-28）：行徽章旁展示 trim 后前 20 字符、详情页展示完整原因；8 条投影回归 + 759/759 测试通过 |
| F-202 | 已修复（`670cf86`） | P2 | W019 | Transfer嵌套FileItem解码 | TV把name/path/type设为必填，当前后端schema/历史JSON允许稀疏项，单坏行可毒化整页 | 双审核对后端原样JSON、仅path fixture及整页原子解码；危险边界为非null稀疏对象 | 仅历史响应DTO字段级宽容并降级显示，保留相邻好行 | 修复完成（`670cf86`），验证及独立复审通过 |
| F-203 | 用户决定跳过 | P1 | W019→G09 | Transfer deletedest失败语义 | 后端忽略目标文件删除Bool，仍删历史并返回成功，目标文件与可重试依据发生不可逆分裂 | 既有双审闭合端点/工具反例；v2.15.1与当前v2复核仍成立 | 不改TV/Web或本地后端，等待MoviePilot官方修复 | 当前Web/TV共享破坏性后端缺陷；现状保持不变 |
| F-204 | 已修复（`81d42fb`） | P1 | W019→I009 | Transfer轮询权威对账与SQLite同ID复用 | 默认SQLite删最大ID后add_force可复用ID；TV保留旧卡，DELETE/AI/manual按同ID重查新行并可删除/移动新文件 | W019双审先闭合非权威列表；I009主审/定向独立复核闭合当前DB/端点完整破坏链 | TV每次进入Tab权威刷新，mutation前全量比较指纹并绑定来源session，异常时整批拒绝且刷新；后端长期方向仍是AUTOINCREMENT或row version | 依赖解析、clean build、本地479/479与第二独立复审通过；保留GET→mutation TOCTOU及完全同指纹边界 |
| F-205 | 用户决定暂缓 | P2 | W019→I009/G10 | Reorganize关闭刷新焦点时序 | onDone先启动refresh再dismiss；onDismiss在refresh中丢弃唯一restore，完成后不补偿 | 既有双审闭合静态丢调用；I009主审与G10独立复核确认成功路径和保存ID长期未消费 | refresh完成清标志后复用现有restore；提交中禁取消/管理Task生命周期 | TV返回导航上下文缺陷已确认；用户暂缓（2026-08-28），后续可能修复 |
| F-206 | 用户决定跳过 | P2 | W018-A | Reorganize自定义目标路径能力 | TV只提供自动/配置目录闭合Picker，无法输入当前Web与后端一等支持的任意target_path | review_a001_h提出；review_a001_j独立闭合TV/VM测试/Web combobox/后端自定义路径分支 | 保留现有目录建议，仅该字段增加自定义输入并复用现有updateForm/编码 | 当前本地上游已核对；用户决定跳过（2026-08-28），现状保持不变 |
| F-207 | 已确认 | P3 | W020-C | 重登成功后的连接信息新鲜度 | 手动重登提示刷新成功，连接页仍显示旧/未知backendVersion等快照直到SystemView重建 | review_a001_j与verify_a001_h双审闭合单次根task、重登成功及局部版本无后续写入 | 获胜session epoch重登成功后复用现有loadSystemInfo或直接消费权威settings/currentUser | 纯TV新鲜度缺陷；真实重建/可见时序未验证 |
| F-208 | 已确认 | P3 | W020-B/F→I016 | System导航减少动态效果 | 页面push/pop固定执行0.42s、824pt横移，根页Back还固定0.24s滚动；均未读取accessibilityReduceMotion | 既有三审及I016两代理均确认同根并维持P3 | 读取原生Reduce Motion环境；开启时立即切换或淡化，并让清理等待跟随实际时长 | 真机体感与系统是否代抑制未验证 |
| F-209 | 已修复（2026-08-28） | P2 | W020-D | “全部站点”与后端默认集合合同 | TV把”全部”编码nil，当前后端却把nil解释为IndexerSites默认子集，稳定漏搜非默认活动站点 | 三代理确认机制/P2；第三裁决证明正确候选域仍不能修复nil三态，独立于F-210 | 显式发送全部活动站点ID；若保留nil则UI准确命名”后端默认” | 已修复（2026-08-28）：全部站点显式发送全部启用站点ID；TV 站点来源切换权威域 `/site/`（过滤 active），无 manage 或失败时降级 `/site/rss`，仅权威成功后归一化（防 F-210 破坏）；10 条投影回归 + 受影响类全过 + 真实后端兼容扩展权威域断言 1/1 通过 |
| F-210 | 已修复（2026-08-28） | P2 | W020-D | 资源搜索站点权威域 | TV用/site/rss作为搜索站点域且不滤inactive，可漏非RSS活动站点、展示停用项并持久删除合法偏好 | 三代理确认机制/P2；第三裁决证明修正nil仍不能补回RSS域缺失项，独立于F-209 | 使用search权限可读的活动搜索站点合同，TV仍滤inactive且仅权威成功后归一化 | 已修复（2026-08-28，部分覆盖）：TV 切换权威 `/site/` 域并滤 inactive、仅权威成功后归一化，覆盖主要破坏面；残留：search-only 无 manage 账号降级订阅域、search 权限可读接口未落地；部署分布未验证 |
| F-211 | 已驳回 | P3 | W020-E→F-126/F-081 | 过滤规则展示与执行快照一致性 | 同ID执行当前B符合现合同；失败仍展示A归加载四态，响应缺所选ID后静默不过滤归F-081 | verify_a001_h第三裁决按互不替代修复/测试拆分，驳回复合重复编号 | 设置页标stale/error；执行端对已选缺失ID显式失败，不强制消费旧A快照 | 机制分别保留在既有项；真实编辑/失败重叠频率未验证 |
| F-212 | 部分修复（`a6cc428`）；复合身份增强用户决定跳过 | P1 | I015→G09 | Reorganize目标目录复合身份 | TV/Web按library_path去重并first(path)，后端却以(storage,path)为目标键；同path跨storage可静默选错真实文件目标 | 既有双审闭合数组顺序/混合tuple；G09两名代理确认当前后端复合身份与TV稳定丢storage选择 | Picker身份直接使用规范(storage,path)并同步生成完整target tuple | 按Web对齐处置完成：`a6cc428`已移除TV独有100ms窗口；复合身份增强由用户决定跳过TV单端实现，原P1历史裁决保留 |
| F-213 | 用户决定跳过 | P1 | I015→G09 | Reorganize媒体类型与隐藏剧集字段 | 从电视剧切电影只清episode_group，旧episode_format等仍被后端执行并可改变真实整理结果 | 既有双审闭合明确电影/模板硬过滤链；G09两名代理确认全部剧集专属字段继续编码与后端消费 | 唯一intent构造按最终类型清除剧集专属字段；Auto由后端识别后门控 | 当前Web共享同一行为，用户决定跳过TV单端修复；原P1历史裁决与episode_part公共字段边界保留 |
| F-214 | 已驳回 | P3 | W020-D→F-109 | 推荐开关配置owner与跨端合同 | TV全局MP_RECOMMEND跨profile共享且绕过服务端per-user配置的机制成立，但修复/验收均属于F-109配置owner | verify_a001_h第三裁决核清Web本地优先缓存+后端per-user权威，裁独立编号合并 | 按F-109以服务端当前用户配置为权威；本地fallback使用规范profile tuple | 不是假问题，仅驳回重复编号；远端最新性未验证 |
| F-215 | 已驳回 | P2 | W020-E→F-081 | CustomRule选项身份与可辨识标签 | 重复/空白ID/name及first-match歧义成立但由F-081输入边界完整承载；合法唯一长同前缀name只留运行显示风险 | review_a001_j提出、verify_a001_h第三裁决确认坏identity并入F-081且支持其条件性P2 | F-081校验规范唯一身份；合法长名提供可辨识读取入口需tvOS运行验证 | 驳回重复编号；真实坏配置和长名裁切未验证 |
| F-216 | 已驳回 | P3 | W020-C→F-107/F-089 | 手动刷新鉴权失败的错误交接 | 401/403先logout再写System局部消息使新Login根拿不到原因，机制成立但由F-107根错误owner完整承载 | verify_a001_h提出、review_a001_j定向复核确认最终不可达并裁合并；状态码分类只交叉F-089 | F-107复用App级一次性错误owner跨根交接；F-089另裁401/403是否应logout/删凭据 | 驳回重复编号；真实状态码频率与短暂闪现未验证 |
| F-217 | 已确认 | P3 | W020-G | 条件Exit modifier改变离场页结构身份 | pop保留离场页0.43秒但isActive立即翻转，使同一页跨结构分支重建并重启推荐task | 三代理确认机制；第三裁决按只读GET、StateObject保留降P3，但稳定modifier修复独立于通用task owner | 恒定保留同一onExitCommand modifier类型，禁用时传nil或在action内guard；root不吞Exit | 纯TV P3；重复请求/自动重连与滚动/focus体感待运行 |
| F-218 | 已确认 | P3 | R001 | 已存会话启动准备门晚于认证首帧 | 初始isLoggedIn可为true但isPreparingStartupSession为false，首个body先构造旧权限Tab/Home任务，随后.task才打开准备遮罩 | 三代理确认静态入口；第三裁决确认其与F-106出口窗口、F-130/CHK-005异步owner均不可互替 | 初始化准备态与已存token同步，必要settings完成或明确失败策略后再统一清门 | 条件性P3已确认；真实认证帧/Home task启动待运行验证 |
| F-219 | 已驳回 | P2 | I012 | TorrentsResult同ID载荷更新不重算派生状态 | 组件机制成立，但当前两个生产调用在新搜索时先移除旧结果View，完成后以最新载荷新建实例，不存在原位更新路径 | verify_a001_h提出、review_a001_h反向、review_a001_j第三裁完整闭合两调用分支身份后驳回 | 仅未来新增原位刷新调用者时改纯派生或generation重算 | 驳回当前生产缺陷；保留未来组件回归边界 |
| F-220 | 已驳回 | P2 | I005→F-115 | MediaPreloader跨阶段串行屏障 | season只依赖详情响应，却必须等待识别及详情内图片阶段结束；有订阅权限电视剧因此稳定延长全屏Loading | review_a001_h集成提出，verify_a001_h独立闭合关键路径并裁其由扩展后的F-115完整承载 | 详情响应发布即启动season，图片/识别仅约束真实依赖者 | 驳回重复编号，不驳回机制；F-115升P2 |
| F-221 | 已修复（2026-09-05） | P2 | I005→G03 | 识别终态冻结在partial media | 合法custom partial初始跳过识别；full detail补Douban/Bangumi/AniList且无TMDB后不重评，Header TMDB按钮永久spinner/disabled | I005双审确认；G03窄第三裁逐个consumer收窄为Header单动作并再次确认P2 | full detail后重评一次；执行/跳过/失败/取消均落terminal，不建状态机 | 已修复（2026-09-05）：full detail 后按 canonical media 补一次识别并落定 finished；MediaPreloadPermissionTests 18/18 + 相关类全过 |
| F-222 | 已驳回 | P1 | G08→F-107/CHK-005 | 全局通知缺少会话owner | App级manager跨登录根存活，旧账号操作可在logout、切服或A→B后才发布错误，已有旧banner也不会随会话转换清退 | 两票确认机制；verify_a001_h第三裁确认与F-107共享manager/session transition根owner并合并 | F-107复用session/operation epoch，在show入队与发布双检并按owner reset，保留结构化当前logout原因 | 驳回重复编号而非机制；根finding F-107最终P1 |
| F-223 | 用户决定跳过 | P2 | G08 | 同操作成功不会撤销旧失败通知 | 失败banner显示后快速重试成功，成功策略保持静默且manager无scope dismiss，旧失败继续覆盖新成功状态；旧成功又不能误删更新错误 | review_a001_h提出登录/Home反例，review_a001_j独立确认同session可达与A失败/B失败/A成功反向边界 | 轻量notification ID/operation scope；成功只撤销同owner旧错误，不新增成功toast或通知框架 | 纯TV通知operation owner缺陷已确认 |
| F-224 | 已驳回 | P3 | I007→F-137/F-141 | 订阅分享最佳结果忽略明确查询年份 | 机制成立：错误年份分享可获标题完全匹配并按热度反超；但修复和验收属于同一`calculateBestResults`评分/年份不变量 | review_a001_j提出、verify_a001_h独立确认模型year与排序反例后裁合并既有评分族 | 分享评分复用媒体候选明确年份门；并入F-137传播，查询年份词法仍归F-141 | 驳回重复编号，不驳回机制；维持P3 |
| F-225 | 已修复 | P2 | I007 | 可选订阅分享阻塞核心搜索结果揭示 | 媒体/合集/人物已完成时，统一搜索仍等待可选分享请求才退出全页loading；全失败/部分失败的误空另归Paginator错误消费 | review_a001_j整文件集成提出，verify_a001_h独立以share gate闭合全页spinner与两阶段发布边界 | 核心类别完成即显示，分享行独立加载；复用现有Paginator错误字段，不建搜索状态机 | 纯TV阶段屏障已确认；真实分享延迟分布未验证 |
| F-226 | 用户决定跳过 | P2 | G07 | Bangumi人物`career`展示投影 | 当前后端正式返回人物career，Web显示而TV不解码/合并且卡片无出口，角色副标题稳定丢失 | review_a001_h主审与review_a001_j独立复核闭合Bangumi credits、schema、TV模型/卡片及Web对照 | 解码career并纳入同人物合并，复用共享displayRole；relation无调用者不扩展 | TV跨端字段投影缺陷已确认；真实载荷频率未验证 |
| F-227 | 已修复 | P2 | G07→F-143拆分裁决 | 人物稀疏详情覆盖seed展示字段 | 有效seed进入人物页后，空/稀疏200详情可把姓名、头像、别名与route字段覆盖为空，而credits仍沿seed owner | G07双审确认，verify_a001_h第三裁按独立字段merge修复/fixture拆出 | route owner保持seed；详情仅以有效更丰富字段覆盖，不做全对象替换 | TV字段合并修复已完成；真实稀疏200频率与视觉闪烁仍需复测 |
| F-228 | 已确认 | P3 | G07→F-178拆分裁决 | 人物详情备用名展示投影 | latin_name/also_known_as已解码并参与搜索，详情只显示name/original_name | G07双审确认TV/Web展示差异，verify_a001_h第三裁确认独立详情投影并下调P3 | 先按F-227保真，再用有序去空去重displayAlternateNames显示 | TV详情投影缺口已确认；真实别名频率与排版未验证 |
| F-229 | 已确认 | P3 | G10 | MultiSelection确认与Exit语义不一致 | Toggle即时写外部binding，“确认”只dismiss；Menu与确认同为完成但文案虚构提交边界 | review_a001_h主审与verify_a001_h独立复核闭合三类caller并排除数据丢失/越权写入 | 即时生效合同下仅改“完成”；产品要求取消时才加局部draft | TV交互文案缺口已确认；Menu产品预期未验证 |
| F-230 | 用户决定跳过 | P2 | G10 | 旧系统SheetTextField固定字体不随辅助字号 | tvOS26.0–26.3 UIKit桥接固定30pt/66高且不用UIFontMetrics，16个输入框不消费辅助字号 | review_a001_h全局主审与verify_a001_h独立复核确认目标分支、调用范围和系统性可访问性缺口 | 现有桥接用UIFontMetrics/自动调整并把66改最小高度；不建输入框框架 | 仅影响过时的tvOS 26.0–26.3兼容分支，用户决定跳过，不再列为待处理项 |
| F-231 | 用户决定跳过 | P2 | I013 | 详情TMDB异步动作缺route owner | 用户点击TMDB后pop，旧无句柄Task成功仍append共享NavigationPath，失败则在无关页面弹旧提示 | verify_a001_h整文件集成与review_a001_h定向独立复核闭合pop、双激活、跨session晚到族 | 单一action Task随route取消，发布前校验generation/session；不建导航框架 | 纯TV动作owner缺陷已确认；真实慢请求/动画时序未验证 |
| F-232 | 用户决定跳过 | P2 | I009 | Transfer历史分页缺稳定同秒排序 | 后端秒级date仅按DESC做offset分页；同秒不同ID可跨页重复/遗漏，TV去重与遇已知即停会固化漏项 | review_a001_h定向复核提出，verify_a001_h第三裁核对TV/Web/后端四类查询并确认独立P2 | 四个分页分支统一date DESC,id DESC；补25条同秒跨页fixture，不引入游标框架 | 后端共享契约缺陷已确认；真实数据库计划与触发频率未运行验证 |
| F-233 | 用户决定跳过 | P2 | I006 | 插件筛选truthy默认覆盖显式falsey值 | 用户明确选择false/0/空串/null后，运行更新又被truthy默认值替换，无法表达关闭/全部/零/清空 | review_a001_h受限集成提出，review_a001_j隔离审计材料定向复核确认四类值与初始化反证 | 默认只在source初始化应用；运行时原样保存用户值 | TV状态owner缺陷已确认；真实插件字段频率未验证，程序限制披露 |
| F-234 | 用户决定跳过 | P2 | I006 | 插件profile兼容只比较defaults | filter_ui/options/depends已变化但prefix/defaults相同会保留失效旧值；Picker显示“默认”而query仍发送旧值 | 两代理完整复核descriptor保留、控件显示与query链 | profile任一结构部分变化即回新defaults，或仅校验并清失效值 | 条件性TV动态schema缺陷；后端热更新保证未验证，程序限制披露 |
| F-235 | 用户决定跳过 | P2 | I006 | Explore source与Popular身份绕过规范化 | tmdb/themoviedb、大小写或空白别名可生成重复source与同媒体重复卡片 | 两代理确认已有MediaIdentifier canonical逻辑却被两处手写prefix/key绕过 | source去重复用normalizeSource；Popular key复用canonical identity并保留season | 条件性TV身份缺陷；真实非规范载荷频率未验证，程序限制披露 |
| F-236 | 已修复 | P2 | I006→G04 | Explore Paginator owner键只有path | 同path不同source/prefix切换被removeDuplicates吞掉，UI已属新source而Paginator/items/seenKeys仍由旧source拥有 | 既有双审确认机制；全新G04 clean-room复核补当前上游无path唯一合同并升级P2 | publisher用现有(source.id,path) tuple去重，setup仍消费path | 条件性TV owner缺陷P2；实际插件碰撞频率未验证，程序限制永久披露 |
| F-237 | 已驳回 | P3 | I006→F-130/CHK-005 | 动态source刷新缺请求代际 | 代码允许双refresh逆序，但当前同实例只有一个生产调度点，未闭合第二调用者 | verify_a001_h第三裁确认机制与单调用反证，裁不保留独立生产finding | 跨session由F-130/CHK-005阻断；未来新增第二调用点时再加局部revision | 驳回当前生产缺陷，不驳回组件脆弱点 |
| F-238 | 未验证 | P3 | I006 | api_path与筛选值同名时重复query | api_path已有mode=old、筛选追加mode=new会形成重复键，但服务端首/末值/拒绝合同未知 | 三代理确认构造；两代理均拒绝在未核FastAPI/plugin合同前确认用户影响 | 固定真实插件与服务端重复scalar解析合同后再决定是否定向覆盖 | TV构造成立；当前插件产出与服务端优先级未验证 |
| F-239 | 用户决定跳过 | P2 | I010 | Search行延迟预载缺离页与session owner | 行离场或A→B切会话后，300ms睡眠任务仍可用当前B凭据创建A媒体预载并回填全局cache | review_a001_j整文件集成与verify_a001_h独立复核均闭合两类Row、logout清理先于迟到注册及现有Debouncer反例 | 复用现有PreloadDebouncer；离场取消并在调度/执行时复核session snapshot | 条件性跨页面/会话P2已确认；真实300ms命中频率未运行验证 |
| F-240 | 已修复 | P2 | I016→G01第三裁 | 动态推荐开关使用可重复title作为配置owner | 同名不同path的两条货架分别渲染却共享enableConfig[title]，无法独立开启/关闭 | I016两票确认机制；G01第三裁按当前生产链确认P2并保持与F-109独立 | 配置键全程改用稳定shelf.id/path，migrateTitleKeys一次性迁移旧title键并回写 | 纯TV配置owner已确认；修复后渲染与配置统一以稳定id寻址，用户核实后端/Web后批准 |
| F-241 | 未验证 | P3 | I016 | App Info Sheet下root Menu observer仍启用 | 若modal与底层共享UIWindow，Menu关闭Sheet还会同时清底层焦点并滚顶 | I016两代理确认静态前提，但均不能证明tvOS modal下Menu投递 | Sheet/alert展示时禁底层observer/exit handler | 条件性TV焦点风险；需UI/真机证据，程序限制披露 |
| F-242 | 已确认 | P3 | I016 | System站点/规则长名称缺完整可辨识入口 | 站点/规则标题固定单行且preview不回显完整名称，同前缀项可视觉不可区分 | I016两代理确认站点/规则视觉链；推荐截断与VoiceOver扩大说法未确认 | preview显示完整名称或允许两行；不新建长文本组件 | 条件性TV视觉缺陷；推荐、具体阈值与VoiceOver待运行，程序限制披露 |
| F-243 | 已修复 | P2 | I014 | SubscribeSeason前台恢复与availability owner | 回前台只刷新subscription，不刷新season availability，旧best_version/full可进入临时订阅mutation | I014严格整文件集成提出，review_a001_h定向独立闭合后台媒体库变化→旧availability→create/pause链 | scenePhase active 先复用现有checkSeasonsStatus再刷新subscription；不新增timer/协调器 | 条件性TV真实mutation；修复后前台恢复重查可用性，用户澄清场景后批准 |
| F-244 | 已驳回 | P1 | G01→G04并入F-130/CHK-005 | Unified Search子状态与父级session gate | A→B不发新query时旧child items/error可早于父gate发布，机制成立但与F-130同一跨profile子发布owner | G01主审/纠偏确认；G04独立复核在F-130中再次闭合相同Search child链，根因/修复/验收相同 | 并入F-130：session变化统一cancel/reset并把epoch gate下沉到child发布 | 重复编号驳回，不驳回机制；普通新query有child generation保护 |
| F-245 | 已修复 | P2 | G03 | Fork mutation 2xx envelope | `forkSubscription`在`success == nil`且带任意ID时仍当成功，缺失成功标志的响应可关闭Sheet并进入GET/编辑链 | 主审及两名不同纠偏复核均确认内联decoder、真实调用链与P2；它和F-083不是同decoder/端点/最小补丁，只共同关联CHK-017 | 仅`success == true`且ID为正时接受；不改下载decoder | TV fail-open 与 Web/decodeStrict fail-closed 合同已核对；修复后仅 success==true 且 id>0 成功，用户核实后端/Web 后批准 |
| F-246 | 用户决定跳过 | P1 | G09 | 整理历史读取端点服务端授权 | 当前后端GET `/history/transfer`只验证token，低权限已认证用户可读取全局整理记录与文件路径 | G09主审与独立复核分别从TV/Web入口、当前后端依赖、全局表字段与测试缺口闭合；现有F-245已占号，顺延登记 | 后端复用现有active-manage依赖；TV不做安全兜底，Web路由门禁仅作UX | TV/Web v2.15.1已对齐manage门禁，用户决定跳过TV单端处理；上游后端风险保留 |

## 发现详情

### F-001：`FlexibleBool` 带换行真值误降级

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Models/Models.swift:187-224`
- 触发路径：任一 `FlexibleBool` 字段收到 `"true\n"`、`"1\r\n"` 等带行尾的字符串。
- 根因：字符串只使用 `.whitespaces` 清理，两种真值比较与 `Int` 转换均失败后静默落入 `false`。
- 用户影响：可能隐藏管理员或功能入口、跳过启用的下载器/媒体服务器、漏加图片 Cookie，或误显示状态；不会造成权限提升。
- 主审证据：`FlexibleBool` 进入 Token、下载器、站点、媒体服务器、Cookie、整理目录和转移结果；相关测试未覆盖带换行字符串。
- 跨端结论：TV 端缺陷已确认；上游是否产生该输入未验证，修复为防御性收敛。
- 最小方向：将根因位置改为 `.whitespacesAndNewlines` 并补直接解码回归测试，不在调用者重复防御。
- 独立复核：verify_m001_b 确认 Foundation 换行不属于 `.whitespaces`，`Int` 解析同样失败；维持 P3，无新增候选。
- 剩余未验证：官方后端是否会产生字符串 Bool，尤其是带换行输入；Web 端处理方式。
- 修复状态：Models.swift 字符串分支的 trim 由 `.whitespaces` 改为 `.whitespacesAndNewlines`；修复前后均为 fail-closed，方向只有把"真值被吞成 false"恢复为 true，无权限提升风险。
- 验证：新增 `MoviePilot-TV-Tests/FlexibleBoolDecodingTests.swift`，用 JSONSerialization 以合法 `\n`/`\r\n` 转义构造 payload，覆盖 `true/1/yes/on` 与 `false/0/no/off` 各带行尾的 8 例；修复版全绿，临时还原旧 `.whitespaces` 后同套测试失败，确认测试能捕获本缺陷。
- 处置状态：用户逐条过 P3 时先质疑"是否已修"，经 git blame/全仓核实未修后批准修复。

### F-002：后台媒体解码穿透 MainActor 图片初始化

- 状态：已修复（`ff4ea14`）
- 严重度：P2
- 位置：`MoviePilot-TV/Models/Models.swift:578-651`，根因调用在 `Person:2142-2212`、`SubscribeShare:2561-2605`；后台入口 `APIService.swift:967-1003`。
- 触发路径：后台解码的媒体响应含 `directors`、`actors` 或 `subscribeShare`。
- 根因：嵌套模型在 `init(from:)` 中读取 `@MainActor APIService.shared` 图片配置，与纯后台解码边界冲突。
- 用户影响：actor 运行时检查下可能中断解码；否则可能形成同一响应内图片配置快照不一致。不能静态宣称必然崩溃。
- 主审证据：工程启用默认 MainActor 与 complete strict concurrency；现有 detached 测试只覆盖 `TmdbSeason`，人员和分享测试均在 MainActor。
- 最小方向：保持嵌套解码为纯数据处理，在 MainActor 访问时或用已捕获配置生成图片 URL；补含人员/分享字段的 detached 解码检查。
- 独立复核：verify_m001_c 确认静态隔离冲突，维持 P2；Release trap 与实际响应携带字段仍未验证。

### F-003：负季号进入合法分季订阅身份

- 状态：已修复（`0cfeb12`）
- 严重度：P2
- 位置：`SubscribeSeasonViewModel.SeasonSubscriptionSummary`与分季订阅快照索引。
- 触发路径：订阅快照有有效业务ID/媒体身份，但`season`为负数。
- 根因：summary会丢弃missing/null，却不校验非负；负值原样成为summary和字典key。真实S00的0值是合法输入。
- 用户影响：负季可进入状态与订阅/取消目标，和合法季集合形成错误身份；missing/null不会再伪装S00。
- 主审证据：API 层不筛选季号，现有 fixture 均提供有效季号。
- 最小方向：只在summary failable init增加`season >= 0`，保留0；不为此改全局季模型。
- 独立复核：verify_m001_c 确认 nil→0 身份、焦点与动作链；I001 补充负季号同样未被过滤，维持 P2；过滤单条或拒绝整批仍待上游。
- V017 生产补强：分季排序继续把nil折叠为0，View动作也把缺失季号当S00；订阅摘要虽跳过nil，负季号仍进入入库、订阅与取消链，维持共享边界修复。
- G02全局限缩：review_a001_j主审提出当前summary已安全丢弃missing/null；rounda_g02_third按四态矩阵确认missing/null丢弃、S00保留、仅negative进入索引。旧nil→S00说法不再用于本finding，其他`TmdbSeason`空壳显示另归F-190边界。
- G02 clean-room 末裁：再次确认S00必须保留、负季号必须拒绝；missing/null当前会让整条TV快照项消失，其产品策略仍未验证，不把它重新写成S00缺陷。业务ID非正/重复另归F-068。

### F-004：完整原始 JSON 与强类型字段重复持有

- 状态：降级（用户决定跳过）
- 严重度：P3；由 P2 降级，性能影响未验证
- 位置：`MoviePilot-TV/Models/Models.swift:612,614-616,728,879,917,1000-1004`
- 触发路径：任何 `MediaInfo` 或 `[MediaInfo]` 解码，长分页和预加载缓存放大持有量。
- 根因：`rawPayload` 保存完整深层 JSON，同时所有已建模字段再次单独解码并长期持有。
- 用户影响：可能增加解码 CPU、常驻内存和 tvOS 淘汰/卡顿风险；实际幅度未验证。
- 主审证据：`rawPayload` 唯一生产用途是重新编码；测试只要求保留未知字段。
- 最小方向：先验证多态原始字段依赖，再只保留未建模/不透明字段；必须保留未知字段回归，并用真机 Allocations/RSS 定量。
- 独立复核：静态重复持有成立，但没有 Allocations/RSS/解码耗时或真机淘汰证据，P2 证据不足。
- 用户裁决：P3 逐条过时决定跳过——无真机实测影响；`rawPayload` 承担 re-encode 保未建模/插件字段的功能职责（`Models.swift:758`），冒然瘦身有丢插件契约风险；若未来真机 Instruments 量化出实际影响再重开。

### F-005：状态模型默认值不能兜底缺键

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Models/Models.swift:432-480`
- 触发路径：Dashboard 或下载器响应缺失/null 任一非可选统计字段。
- 根因：属性 `= 0` 不会成为合成 `Decodable` 的缺键默认值。
- 用户影响：状态刷新失败，首次为空、后续保留旧值；顺序赋值可能形成跨卡片混合快照。
- 主审证据：本地 stub 与真实后端巡检均未覆盖缺键/null。
- 最小方向：若字段允许缺失，在模型边界 `decodeIfPresent ?? 0`；若必填，移除误导默认值并补严格契约测试。
- 独立复核：范围缩窄为 `Statistic.movie_count/tv_count` 和 `DownloaderInfo` 五字段；顺序发布可形成部分新旧混合快照，维持 P3。
- V019 生产复核：Statistic与DownloaderInfo正由状态页三个并发请求直接消费；任一缺键解码错误会进入F-149的顺序丢值与F-126的假空/旧值呈现，但各根因保持独立。
- 剩余未验证：无下载器、下载器离线、旧版本响应契约。
- 修复状态：采用"字段允许缺失"分支——`Statistic` 与 `DownloaderInfo` 各补自定义 `init(from:)`，非可选数字字段一律 `decodeIfPresent(Int.self, forKey:) ?? 0`，`Statistic.episode_count` 保持可选；属性上的 `= 0` 保留为文档化默认。根因是 `StatusViewModel.refreshAllData` 用 `try await (stat, stor, down)` 三连取，单个统计字段缺键会整批抛错、令统计/存储/下载器三卡一起不刷新（非只坏一格），故在模型边界容缺是最小且贴合仓内既有宽容解码方向的改法。字段齐全时解码结果完全不变。
- 验证：新增 `MoviePilot-TV-Tests/StatusModelDecodingTests.swift`（直接模型解码矩阵：缺键/null/空对象/字段齐全，Statistic 与 DownloaderInfo 各一组）与 `StatusDashboardSnapshotTests` 两个端到端用例（stub 只回部分字段时整页仍发布、同批 storage/downloader 不被拖累；为此给 stub 增加 body 覆盖能力）。修复版 9 例全绿；临时 `git stash` 还原模型改动后，4 个新用例全败、既有 5 例不受影响，确认测试能捕获本缺陷。
- 处置状态：用户逐条过 P3 时经解释触发链（三连取整批失败）与修复方向后批准修。

### F-006：Subscribe lookup 的 raw 数值 0 遮蔽合法 fallback

- 状态：已修复（`49b887e`+`f807692`）
- 严重度：P2
- 位置：`APIService.fetchSubscriptionLookup` 的局部响应 DTO，以及 Header/通用取消调用链。
- 触发路径：lookup 响应返回 raw 数值 `tmdbid/bangumiid/anilistid: 0`，同时遗留 `mediaid` 是有效统一键。
- 根因：lookup 响应重建 `apiMediaId` 时曾直接接受 raw 数值 `0`，与 Web `SubscribeCard.getMediaId()` 的 JavaScript truthy 分支不一致，因而遮蔽 legacy fallback。
- 用户影响：取消请求可能错误使用 `tmdb:0` 等键，漏命中真实订阅。
- 2026-08-11 Web v2.15.1 纠偏：raw 数值 `0` 为 falsy，应继续回退；负数为 truthy，官方 Web 会保留，不能按 `<= 0` 统一改成 `nil`。canonical/legacy 字符串中的 `"0"` 仍是非空字符串，也不能按 raw 数字规则过滤。
- 当前修复：lookup 补齐 canonical 与 AniList 字段，raw 数值只跳过 `0`，保留负数，再回退不透明 legacy `mediaid`；已有模型行为不扩大修改。
- 验证边界：测试覆盖 raw 0 → legacy、raw -1 优先于 legacy、canonical/AniList 优先级；真实后端异常数据分布仍未验证。

### F-007：详情直订丢失 AniList/插件身份

- 状态：已修复（`bb07772`）
- 修复状态：已完成（`bb0777262f8b976c41afac4f1a636424bb8e9dd6`）
- 严重度：P1（由 P2 升级）
- 位置：`MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:269`、`Views/Pages/MediaDetailView.swift:564,681`、`Views/Pages/MediaDetailContainerView.swift:211`
- 触发路径：详情媒体只有 AniList/插件 `source/media_id` 身份，或标题识别得到 TMDB X 后完整详情返回权威 TMDB Y，用户从 Header 订阅或跳转。
- 根因：`buildSubscribeRequest` 没有复用完整 `detail.apiMediaId`；预热、跳转和直订又共同使用 `recognized X ?? fullDetail Y`，没有以完整详情权威值优先仲裁。
- 用户影响：精简 POST 可能完全缺少主身份；X≠Y 时还会创建并立即暂停错误媒体的真实订阅。
- 主审证据：`SubscriptionHandler`、`SearchViewModel`、`SubscribeSeasonViewModel` 同类转换均复用身份；只有详情 Header 旧路径漏传。
- 最小方向：复用 `detail.apiMediaId`；可保持中间模型自洽，但不得擅自扩展既有精简 POST schema；补 source-only builder→编码测试。
- 独立复核：verify_m001_a 早期确认 source-only 缺口并收窄修复边界，当时维持 P2。
- V018 生产补强：SubscribeSheet 新建请求同样没有从统一 identity/apiMediaId 补齐 `mediaid`；source-only/AniList 草稿可进入缺少主身份的 POST，沿用同一请求构造边界即可。
- I008双审裁决：review_a001_j整文件主审与review_a001_h当前HEAD定向独立复核均确认合法X≠Y及source-only路径；错误ID会进入真实创建并暂停，故升P1。最小修复只需一个共享订阅draft factory和纯`fullDetail.tmdb_id ?? recognized`仲裁，四个创建caller复用，不新增身份协调框架。
- 修复验证：请求现完整传递 `anilistid/media_source/media_id` 并保留 legacy `mediaid`，详情 TMDB 优先于预识别兜底；2 条定向测试、tvOS Simulator 干净构建、排除整套后端兼容测试后的 381 条本地测试及独立子代理复审均通过。

### F-008：订阅搜索后缓存失效未刷新已发布状态

- 状态：已修复（`789e9a7`）
- 修复状态：已完成（`789e9a7`）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/HomeViewModel.swift:220`、`Services/APIService.swift:2205`、`ViewModels/SubscribeSheetViewModel.swift:200`
- 触发路径：手动或自动订阅搜索成功并改变远端订阅，页面仍持有旧 `@Published` 状态。
- 根因：成功出口只失效 API 缓存，不发布 `.subscriptionDidUpdate` 或强刷；缓存失效不会主动更新已有数组/任务。
- 用户影响：首页、详情预加载和分季状态要等轮询、重新激活或手动刷新；Fork 若随后编辑页被关闭也可能同类失步。
- 主审证据：所有通知监听方和刷新间隔已闭合；历史曾有成功后强刷/通知，当前测试只验证下一次 fetch 与手工 post。
- 最小方向：每个改变远端订阅的最终成功出口恰好发一次刷新事件；首页手动搜索还应立即强刷自身，不让通用缓存清理无条件发事件。
- 独立复核：verify_m001_a 确认搜索回归并扩及保存后搜索与 Fork；维持 P2。
- V017 同根扩展：DELETE已经成功后若随后的强刷失败，流程不清本地旧状态、也不发`.subscriptionDidUpdate`，却向用户报告错误；远端成功事件被错误地绑定到后续GET成功，仍应在mutation最终成功出口恰好发布一次。
- V018 同根扩展：保存链在恢复/立即搜索前提前发通知，后续 mutation 没有最终通知；取消回滚 DELETE 也完全不发通知。mutation 终态而非中间步骤应拥有唯一发布点。
- W015传播：Fork POST 成功只失效缓存；后续GET失败或用户打开编辑器后直接取消修改时永不发送`.subscriptionDidUpdate`，已加载的Home/MediaPreloader持续保留未订阅状态。W015双审确认成功出口应恰好发布一次，不能依赖GET或可选编辑保存。
- 剩余未验证：搜索响应是否代表最终完成、Fork 何时可见。
- 修复验证：Home 搜索/状态/重置成功强刷自身并各通知一次；保存链、回滚 DELETE、分季 DELETE 与 Fork 各由真正 mutation 成功出口通知，不让后续 GET/编辑失败吞掉事件；8 条聚焦测试、相关 89 条测试、额外异常路径、Simulator clean build、排除后端兼容 suite 后的 386 条本地测试及独立复审均通过。
- 保留边界：后端搜索成功仅表示后台任务已受理，立即强刷可能先读到未完成快照；Home 直接强刷后还会响应自身通知，多一次只读列表 GET，但不重复 mutation 或通知，未为此新增来源过滤框架。

### F-009：无法解析的版本被误报为过低

- 状态：已修复（`4c69ec9`）
- 严重度：P3
- 修复状态：已完成（`4c69ec9`）
- 位置：`MoviePilot-TV/Models/AppVersionInfo.swift:74-98`、`ViewModels/ContentViewModel.swift:193-201`
- 触发路径：后端返回非空但无法解析的版本，如 `v2.beta.14`、`release-2.15.1` 或整数溢出段。
- 根因：比较函数返回 nil，但警告模型用原始字符串非空且不等于中文“未知”作为另一套“已知”判断。
- 用户影响：启动弹窗把“无法判断”错误描述为“已确认版本过低”，误导升级或排查；不阻断功能。
- 主审证据：现有 parser 测试已把此类输入判为 nil，警告测试只覆盖精确“未知”。
- 最小方向：警告分类复用同一解析结果，明确区分支持、过低、无法确认。
- 独立复核：verify_b001 确认 parser nil 与警告“已知”判断矛盾，维持 P3；兼容测试诊断也需区分无法解析。

### F-010：版本核心前置分隔符被接受

- 状态：已修复（`4c69ec9`）
- 严重度：P3
- 修复状态：已完成（`4c69ec9`）
- 位置：`MoviePilot-TV/Models/AppVersionInfo.swift:50-66`
- 触发路径：`v-2.15.2`、`+2.15.2`、`v 2.15.2` 等版本。
- 根因：Swift `split(whereSeparator:)` 默认丢弃开头空片段，解析器未要求去掉可选 `v` 后以数字开始。
- 用户影响：可能错误通过兼容判断，或错误显示为已确认版本过低；仅影响警告。
- 主审证据：当前 malformed 测试体现拒绝无效核心的意图，但没有前置分隔符用例。
- 最小方向：要求版本数字核心非空且从数字开始，补前置 `-`、`+`、空格拒绝用例。
- 独立复核：verify_b001 确认 Swift split 丢弃首个空段，维持 P3；现有合法 `-1` 后缀规则暂不改变。

### F-011：下载请求丢失站点凭据、UA、代理与下载器字段

- 状态：已修复（`63767f9`）
- 严重度：条件性 P2
- 修复状态：已完成（`63767f9`）；仅补四个可选 Codable 字段与两端点真实请求体回归，独立复审通过；聚焦1/1、Simulator clean build及排除五个真实后端兼容套件后的390/390本地测试通过。
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `TorrentInfo`/`AddDownloadRequest`，`MoviePilot-TV/Services/APIService.swift` 的 `addDownload`，调用者 `AddDownloadViewModel`
- 触发路径：TV 从官方搜索/RSS Context 解码 torrent 后，用户添加下载；该 torrent 依赖站点 Cookie、专用 UA、代理，或在 `/download/add` 未显式选择顶层下载器而依赖站点下载器。
- 根因：TV `TorrentInfo` 未声明 `site_cookie`、`site_ua`、`site_proxy`、`site_downloader`，解码时忽略，随后编码到 `torrent_in` 时确定丢失。官方 Web 的 AddDownloadDialog 直接发送原 torrent 对象。
- 用户影响：私有站 HTTP torrent 可能认证失败，要求专用 UA 或代理的站点可能无法获取种子；主下载成功后的自动字幕也可能因同样凭据缺失失败。`site_downloader` 仅在 `/download/add` 且顶层 `downloader` 为空时影响下载器选择。
- 当前上游证据：2026-08-08 核对官方后端 v2 HEAD `91ce365f` 与 Web v2 HEAD `7ea14bc9`。后端索引/RSS生产四字段；两个下载端点都消费前三项，`/download/add` 条件消费 `site_downloader`；Web 保留全部字段。
- 独立裁决：三名只读代理分别闭合 TV→后端、Web→后端与窄裁决，结论一致；`/download/` 会用顶层 `downloader`（包括 nil）覆盖 incoming `site_downloader`，该字段在此端点不形成额外故障。
- 反例边界：磁力链接、后端已缓存 torrent、无需认证/专用 UA/代理的站点、全局 UA 足够、或显式选择顶层下载器时不触发对应失败。
- 最小方向：只给 `TorrentInfo` 增加四个可选 Codable 字段，并补官方搜索 Context→`AddDownloadRequest`→捕获请求体的两端点回归；不建立通用 raw-payload 框架。
- 排除项：`genres`、`production_countries`、`season_info`、Person/Share 等嵌套表示变化仍可静态确认，但当前官方核心未发现消费者，动态插件依赖未验证，转为 CHK-003 的合同边界，不再作为 F-011 的已确认用户影响。其他 TV 未建模 torrent 字段也因未证明当前下载成功必需而保持未验证。

### F-012：订阅导航截断主身份并反转兼容优先级

- 状态：已修复（`58c7e81`）
- 修复状态：已完成（`58c7e81`）
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `Subscribe.navigationMediaInfo()`；唯一生产调用方为 Home 订阅卡详情入口，传播至详情、资源、订阅检查/删除和分季。
- 已确认事实：当前普通 Subscribe schema、数据库与 GET 均正式包含 `tmdbid/doubanid/bangumiid/anilistid/mediaid/media_source/media_id`。TV转换保留前三个raw字段，却漏`anilistid/media_source/media_id`；又把legacy `mediaid`拆进`mediaid_prefix/media_id`，使它可能抢在raw built-in ID之前。
- 身份合同：当前官方Web/后端顺序为canonical `media_source+media_id`→TMDB/豆瓣/Bangumi/AniList→legacy `mediaid`。TV转换后会出现canonical丢失、AniList丢失、canonical与raw冲突时选错raw、raw与legacy冲突时选错legacy。
- 用户影响：Home可进入无身份或错误身份详情；后续资源搜索、订阅状态/删除、分季匹配与再次保存继承同一错误身份。canonical-only和AniList-only均是当前后端支持的创建/持久化路径，不是未来假设。
- 当前复核：三路代理分别闭合Subscribe投影、全转换矩阵与当前Web/后端合同；已修F-007保证下游builder字段完整，但没有修这个入口投影。未发现第三个同根转换遗漏。
- 最小方向：仅在`navigationMediaInfo()`按canonical→四raw→legacy顺序调用一次现有解析器，把最终身份写入`source/media_id`，并保留经过正数/空白过滤的raw字段；不要同时写canonical和legacy两套声明槽位，不给通用MediaInfo新增legacy字段。
- 测试：canonical/raw/legacy冲突优先级、AniList-only、canonical-only、legacy-only，以及经真实`fetchMediaDetail`捕获`/media/{id}`出口。
- 分组子边界：`episodeGroupTMDBID`对canonical-only TMDB仍只读raw `tmdb_id`，静态限制成立；但Web相同且订阅入口通常经full detail补raw，从该入口稳定触发未确认，降为用户路径未验证P3边界，暂不并入本次修复。
- 排除：F-006非正ID、F-013通用MediaInfo legacy输入、F-078列表稳定ID、缓存/通知/取消均非同根。

### F-013：`MediaInfo` 无正式清单声称的 legacy `mediaid` 回退

- 状态：已驳回；用户决定跳过修复
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift:578-1213`
- 当前反证：官方Web v2.15.5的`MediaInfo`类型没有legacy `mediaid`，身份helper也不读取该字段；详情、资源搜索、下载与订阅均从`source/mediaid_prefix + media_id`或四类专属ID现场生成请求键。
- 关键边界：Web路由/API参数虽命名`mediaid`，但它是生成的`source:id`，不是`MediaInfo` payload字段；只有legacy字段的对象在Web同样无法工作。
- 后端证据：当前`MediaInfo.to_dict()`与响应schema固定输出结构化身份，不产生仅legacy身份对象。
- 裁决：F-013的兼容前提不成立，不给TV新增差异化兜底；CHK-002改为删除正式清单中过时现状声明。本轮不改产品代码。

### F-014：空白来源前缀遮蔽有效来源

- 状态：已驳回
- 严重度：P3
- 位置：`MoviePilot-TV/Models/Models.swift:1154-1169`
- 触发路径：`mediaid_prefix` 仅含空白，`source` 是有效 douban/bangumi/anilist，且没有对应专用 ID。
- 当前反证：当前来源选择会trim候选值，空白`mediaid_prefix`被丢弃后继续读取有效`source`；原“空白非nil遮蔽”控制流已不存在。
- 用户影响：原命题在当前HEAD不产生用户缺陷。
- 主审证据：现有测试只覆盖专用 AniList ID，没有空白前缀回退。
- 最小方向：不改生产代码；只补“空白prefix＋有效source”精确回归测试。
- 独立复核：verify_m001_d 确认全部 `canJumpToTMDB` 调用与 `ExploreViewModel.popularSubscriptionKey` 同类分歧，维持 P3。
- G02全局裁决：review_a001_j主审提出当前反证；verify_a001_h纠偏复核与rounda_g02_third分别从当前HEAD独立确认trim后fallback，三票覆盖旧M001-D控制流判断，裁驳回。
- 剩余未验证：上游对`mediaid_prefix`与`source`的正式优先级合同；不影响当前TV空白回退反证。

### F-015：非电影被误当成电视剧订阅

- 状态：已修复（`f04f73f`）
- 严重度：P3
- 修复状态：已完成（`f04f73f`）；合集入口已拒绝/隐藏，只有明确电视剧进入分季，其他允许类型直订。
- 位置：`MoviePilot-TV/Models/Models.swift:1199-1203`，调用者为 `MediaContextMenu`、`SubscriptionHandler`、`MediaDetailView`
- 触发路径：`type` 为合集或未知的非电影/非电视剧媒体。
- 根因：`canDirectlySubscribe` 只回答“是否电影”，调用者却把 false 直接解释为“进入分季流程”。
- 用户影响：右键菜单显示错误“分季订阅”；详情 Header 可出现点击无动作的按钮。
- 主审证据：当前测试仅覆盖电影和电视剧，已有模型测试支持合集类型。
- 最小方向：进入分季流程时明确确认电视剧；其他类型隐藏或禁用订阅入口。
- 独立复核：verify_m001_d 确认 handler、菜单和 Header 三条路径，维持 P3；只有明确电视剧才能进入分季。
- 剩余未验证：其他上游媒体类型集合及隐藏/禁用策略。

### F-016：大小格式输出仍由系统自适应

- 状态：已驳回
- 严重度：P3
- 处置：用户决定跳过修复。
- 位置：`MoviePilot-TV/Extensions/Formatters.swift:6-18` 及 Torrent/Status/Download/Transfer/AddDownload 调用者
- 触发路径：显示非整数 KB/MB、零值或在不同 locale 下显示大小。
- 根因：只设置 `.binary` 与单位集合；精度、零值自然语言和 locale 仍使用 ByteCountFormatter 默认。
- 用户影响：不同单位/locale 的小数位和零值文本不一致，DownloadTask 的 nil `"0 B"` 还可能与真实零值不同。
- 主审证据：tvOS SDK 默认与 13 个调用表达式已核对，无直接测试。
- 驳回理由：代码只承诺 1024 基数，`.binary` 已满足；自适应精度、自然语言零值与 locale 是 Apple 明确的本地化默认，且没有业务反向解析。
- 重开条件：产品或上游明确要求逐字符复刻固定 Web 输出。

### F-017：无时区日期被固定解释为上海时间

- 状态：未验证；用户决定跳过修复
- 严重度：P3
- 处置：用户决定跳过修复；保留未验证状态，不改变正式统计。
- 位置：`MoviePilot-TV/Extensions/Formatters.swift:79-90`、`Services/CustomFilterService.swift:227-232`
- 触发路径：无时区字符串实际属于 UTC、服务器自定义时区或站点本地时区。
- 根因：显示和过滤均硬编码 Asia/Shanghai；SwiftDate 的 Region 表示输入日期所属区域。
- 用户影响：更新时间/发布时间/分享时间偏移，过滤阈值也可能误判。
- 主审证据：测试 fixture 使用无时区格式，未覆盖服务器时区/offset；过滤层复制同一假设。
- 最小方向：确认各日期源契约后统一解析边界；带 offset 保留自身时区，无 offset 按已确认源时区解释。
- 独立复核：行为确认，但带 offset 输入已按自身 offset 解析；问题仅限无时区值，源时区契约缺失，无法判定 Bug。

### F-018：资源网格重复编译固定季集正则

- 状态：已修复（`94f18f2`）
- 严重度：P3
- 修复状态：已完成（`94f18f2`）；固定正则改为单个静态实例，并补齐季、集、范围、大小写与无效输入回归矩阵。
- 位置：`MoviePilot-TV/Extensions/Formatters.swift:24-32`、`TorrentCard.swift`、`TorrentsResultView.swift`
- 触发路径：多个资源卡片渲染及筛选、排序、焦点、状态变化导致 body 重算。
- 根因：固定 pattern 与 `NSRegularExpression` 在 helper 每次调用时重新创建。
- 用户影响：增加主线程重绘开销；是否造成卡顿未量化。
- 主审证据：唯一调用位于 LazyVGrid 卡片 body，无直接性能或边界测试。
- 最小方向：复用单个不可变正则或原生 Regex literal，并补最小季集输入测试；不缓存格式化结果。
- 独立复核：相邻 `ParsedSeason` 已使用静态正则，确认重复工作；维持低优先级 P3，提升需真机 Instruments。

### F-019：登出/切服未失效共享图片 Cookie

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1；G06 由 P2 升级
- 位置：`MoviePilot-TV/Extensions/KingfisherCookies.swift:7-16`、APIService 会话转换与登录路径
- 触发路径：后端 origin 写入会话 Cookie；用户登出、换账号或切到同 Cookie 域下另一服务后请求图片。
- 根因：modifier 每次从持久共享 Cookie 存储读取；会话转换只清 token/业务缓存，不删除旧 origin Cookie。
- 用户影响：旧 Cookie 可能继续授权图片代理、跨账号错误授权或使新请求异常。
- 范围：不同域不会任意互发；主要影响同 origin/domain 或同主机不同端口。
- 主审证据：全仓只有 Cookie 读取，无 delete/remove；API shared session 与 modifier 共用存储。
- 最小方向：统一会话转换边界按已知会话 Cookie 及 domain/path/Secure/portList 清理，不笼统清空无关域。
- 独立复核：verify_b003_retry 确认所有会话转换无清理并修正 scope 边界，维持 P2。
- G06联合裁决：rounda_g01_recheck与rounda_g02_third分别重读TV会话/图片链及当前后端；后端会签发HttpOnly资源Cookie，本地logout不通知后端，同hostname换端口又不形成Cookie隔离。两票均确认旧资源授权可跨登出/切服继续生效，故升条件性P1；修复只删除旧会话已知主机/path下MoviePilot资源Cookie并取消对应在途任务，不清系统全部Cookie。
- 剩余未验证：真实账号差异资源、部署Cookie属性与触发频率；未运行登录/图片请求。

### F-020：受保护图片缓存和在途任务未按账号隔离

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1（由 P2 升级）
- 位置：全部 cookieModifier 调用者、`MediaPreloader` 与 Kingfisher 8.10 cache/downloader
- 触发路径：账号 A 以 Cookie 请求受保护 URL；登出/换账号后 B 请求相同 URL，或旧下载仍在进行。
- 根因：Cookie/header 不进缓存键；下载按 URL 合并；KFImage 默认不随消失取消；登出不取消全局 downloader、不清或分区 Kingfisher cache。
- 用户影响：B 可能命中 A 图片、加入旧 Cookie 请求，或旧请求登出后完成并写缓存。
- 主审证据：精确 Kingfisher 8.10 源码与仓库无清理/自定义 cache key。
- 最小方向：只对受保护后端图片建立会话失效或分区，取消旧任务并处理内存/磁盘缓存；公共海报继续共享。
- 独立复核：verify_b003_retry 确认 URL-only cache/in-flight、磁盘默认存续及仓库无清理，维持 P2。
- I010等级裁决：review_a001_j与verify_a001_h分别确认认证Cookie只改网络请求、默认cache key仍为URL，logout不清Kingfisher且旧producer可回填；review_a001_h第三裁再从Kingfisher 8.10源码闭合hit绕过downloader认证、URL-only在途合并及memory/disk写入。若同一URL在A/B返回不同字节或B无权访问，B可直接得到A字节且不发生B鉴权，故升条件性P1；若后端证明全部相关URL跨账号公开且字节恒等，实际后果回落P2。
- 最小修复收窄：只给受保护资源使用不含token/Cookie明文的opaque session namespace cache key；新会话允许渲染前隔离或排空旧downloader并清旧memory/disk namespace。所有KFImage、retrieve与prefetch复用同一资源入口，公共海报继续共享，不建图片缓存框架。
- 剩余未验证：相同 URL 是否返回账号相关内容。

### F-021：未知大小被显示为真实零值

- 状态：已修复（`a0adaab`）
- 严重度：P3
- 位置：`MoviePilot-TV/Views/Pages/DownloadTaskView.swift:217`、`TransferHistoryView.swift:381,456` 与对应可选模型
- 触发路径：`DownloadingInfo.size == nil`、`src_fileitem == nil` 或 `FileItem.size == nil`。
- 根因：调用者在格式化前把未知折叠为 0，或直接硬编码 `"0 B"`。
- 用户影响：未知大小被明确显示为零字节，不同入口还出现本地化零值与 `"0 B"` 两套文本。
- 证据：模型字段显式可选，多个测试 fixture 允许 nil，但没有最终显示断言。
- 最小方向：nil 显示“未知”或省略；只有非 nil 调用 `formattedBytes()`。
- 独立验证：review_m001_e 确认 `DownloadingInfo.size`、`TransferHistory.src_fileitem` 与 `FileItem.size` 的可选语义及缺失 fixture，三个显示出口均把未知折叠为零；维持 P3。
- 剩余未验证：真实缺失频率与 Web 占位文案。
- 修复状态：已完成（`a0adaab`）；三个出口均在 nil 时省略大小，真实零值仍显示为 `0 B`；最终独立复审通过，tvOS Simulator clean build 与本地测试 427/427 通过（明确跳过 5 个真实后端兼容套件）。

### F-022：单条资源缺字段可令整次搜索失败

- 状态：已修复（`06d9fe5`）
- 严重度：P2
- 位置：`MoviePilot-TV/Models/Models.swift` 的 Torrent/MetaInfo 必填字段及 API SSE/fallback 解码
- 触发路径：任一资源缺/null/类型异常的 size、促销因子、MetaInfo name 或 season_episode。
- 根因：嵌套输入边界过严；一个对象失败终止 SSE，fallback 又严格解码整批。
- 用户影响：整次搜索退回同步后仍可能失败；不是崩溃。
- 主审证据：fixture 全部补齐字段，无“同批一条坏数据”用例。
- 最小方向：只在输入边界宽容，内部显示、过滤和添加下载请求保持稳定，不批量 Optional 化。
- 独立复核：verify_m001_e 确认 SSE 首个解码错误终止、fallback 对同一批再失败以及旧结果可能保留，维持 P2。
- V015 生产补强：review_a001_j 确认 ResourceResult 的 SSE 任一严格字段错误会终止流，同批同步 fallback 仍以同一模型整批解码并可再次失败；无须另立消费者 finding。
- W011 当前上游补强：verify_a001_h核对本地后端`TorrentInfo`两个促销因子均为Optional，而TV要求非可空Double；有效资源与任一null因子资源同批时，SSE事件及同步fallback均会整体解码失败，完整归本项，不新编号。
- 修复状态：已完成（`06d9fe5`）；只在 `TorrentInfo`/`MetaInfo` 解码入口将缺失、null或类型异常的大小、促销因子、名称与季集归一为现有中性默认值，未扩散 Optional 或新增解码框架；SSE 与普通 `[Context]` 同批稀疏数据及超范围大小回归已覆盖，最终独立复审通过，tvOS Simulator clean build 与本地测试 428/428 通过（明确跳过 5 个真实后端兼容套件）。

### F-023：单项空标题令媒体服务器最新内容整批为空

- 状态：已修复（`af67839`）
- 严重度：P3
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `MediaServerPlayItem.title`、`APIService.fetchMediaServerLatest`、`HomeViewModel`
- 触发路径：最近媒体数组中任一项目缺失/null title。
- 根因：严格 String 解码使一项失败拖垮整批。
- 用户影响：首页该服务器最近内容显示为空。
- 主审证据：现有 fixture 均有 title；旧证据可能过时。
- 最小方向：仅在当前上游仍允许空标题时于解码边界提供中性内部标题。
- 独立复核：verify_m001_e 确认单项失败拖垮数组并让 Home 替换为空，维持 P3；当前后端 schema 已确认允许 title 为空。
- 修复状态：已完成（`af67839`）；解码边界将缺失/null标题归一为空字符串并保留同批项目；独立复审通过，Simulator clean build 与本地测试 430/430 通过（跳过5个真实后端兼容套件）。

### F-024：下载任务 fallback ID 不稳定并可能碰撞

- 状态：用户决定跳过
- 严重度：条件性 P1；普通身份抖动为 P3
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `DownloadingInfo.id/update`、`DownloadTaskViewModel` 轮询合并
- 触发路径：下载项缺少非空 hash，且标题/大小变化或 fallback 字段碰撞。
- 根因：fallback 使用可变展示字段且无分隔；合并端用 `Dictionary(uniqueKeysWithValues:)` 假定唯一。全空生成 UUID 会造成每轮重建，但随机 UUID 碰撞不是有意义的崩溃证据。
- 用户影响：三秒轮询删除重建对象与焦点漂移；碰撞项首次可同时进入数组，下一轮构造旧值字典时触发不可捕获的 precondition trap并终止 App。
- 主审证据：测试均提供稳定 hash，没有无 hash、size 变化或碰撞用例。
- 最小方向：确认不可变业务身份；合并端不得假定输入永远唯一。
- 独立复核：verify_m001_e 确认首次重复可进入数组、下一轮字典构造可 trap；条件性 P2，普通身份抖动 P3。
- V020 生产复核：重复 fallback ID 可先进入当前数组，下一轮轮询才在 `Dictionary(uniqueKeysWithValues:)` 构造旧值字典时触发 trap；无需动作请求即可成立。
- W017双审升级：当前后端模型允许hash缺失；无分隔字段拼接可构造重复ID，完全重复输入也无需特殊字符。review_a001_h与review_a001_j确认首次保留重复、第二轮确定进程终止，故升级条件性P1。最小修复为规范化非空hash，并以显式循环检测重复后失败关闭，不能把`uniqueKeysWithValues`前置条件当服务端保证。
- 当前上游复核：官方后端 `7012e0e` 的schema仍允许hash缺失，qBittorrent/Transmission/rTorrent正常producer通常提供稳定唯一hash但入口不校验去重；官方Web `e6b26cc` 每三秒直接替换数组并用`hash ?? name`作为key，重复key可覆盖测量/DOM身份但不走TV第二轮必崩链。TV最小边界为hash优先、name兜底，旧/新快照显式查重并失败关闭，不新增持久身份框架。
- 用户裁决：考虑官方内置下载器通常提供稳定唯一hash、触发依赖异常/插件producer，决定跳过修复并接受该低频条件性风险。

### F-025：媒体服务器卡片 ID 依赖可变 link

- 状态：已修复（`8050051`）
- 严重度：P3
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `MediaServerPlayItem.id` 与 `HomeView`
- 触发路径：link 在轮询间变化，或 raw_id/link 缺失但 item_id/server_id 可用。
- 根因：ID 总组合 raw_id+link；缺失时忽略结构化业务键而生成 UUID。
- 用户影响：十秒刷新重建海报卡片并丢失焦点。
- 主审证据：业务跳转测试覆盖 item_id/server_id，但无连续解码 ID 稳定性。
- 最小方向：优先不可变 server/item 业务键，link 仅最后 fallback。
- 独立复核：verify_m001_e 确认十秒刷新与结构化键未参与 ID，维持 P3；link 稳定性未验证。
- 当前上游复核：官方Web `e6b26cc` 的最近媒体网格使用 `id || link || title`，有id时link变化不改卡片key；官方后端 `7012e0e` 的六个内置producer均通常提供媒体服务器原生id，link则可随host/playhost/token改变，schema四字段均可空。故正常配置不变时低频，但TV额外把导航link纳入身份的差异成立，维持条件性P3。
- 最小边界：仅调整两个现有initializer的身份优先级为规范非空raw_id；缺失时再用server_id+item_id、link、UUID，不改HomeView/HomeViewModel/API或新增身份架构。
- 修复状态：已完成（`8050051`）；按用户补充要求加入`emby/jellyfin/plex`等`server_type`作用域；两个initializer复用同一稳定ID函数，按raw→server/item→link→UUID取值，并以分支标签与UTF-8长度前缀消除连字符/Unicode拼接碰撞。聚焦5/5、Simulator clean build、跳过5个真实后端兼容套件后的本地串行433/433测试及最终独立复审均通过。

### F-026：Paginator 无认证预取可劫持后续 Cookie 请求

- 状态：已修复（`90b40b4`）
- 严重度：P2
- 位置：`MoviePilot-TV/Services/Paginator.swift:114-129` 与 12 个 `imageURLsProvider`
- 触发路径：Paginator 先预取受 Cookie 保护 URL，随后可见 KFImage 请求同一 URL。
- 根因：`ImagePrefetcher(urls:)` 未传 cookie modifier，却共享默认 downloader/cache；后续请求只按 URL 加入已有无 Cookie task。
- 用户影响：受保护图片失败；可解码的未授权占位还可能写入共享缓存，反向顺序也会混用认证任务。
- 证据：Kingfisher 8.10 initializer/manager/downloader 与 `[URL: SessionDataTask]` 合流链已闭合，应用测试无预取覆盖。
- 最小方向：预取与最终显示使用相同认证选项，不新增另一套图片客户端。
- 独立裁决：review_s004 从 Paginator、12 个 provider、显示组件和 Kingfisher 源码重新闭环，维持 P2；不替代 F-020 的跨会话隔离。
- I010传播：verify_a001_h在MediaCard/Search调用链再次确认Paginator仍直接构造无Cookie modifier的ImagePrefetcher；这是本项既有认证选项不一致，不把同一生产者另降为P3。登出后旧producer写URL-only cache的持久隔离后果仍归F-020。
- G06复核：rounda_g01_recheck定向核到锁定的Kingfisher 8.10.0同URL先查现有`SessionDataTask`并追加callback，确认跨modifier在途合并；rounda_g02_third只确认无认证预取并把依赖内部实现列为边界。精确依赖证据已由前票闭合，维持P2，不重复升级到F-020的跨账号持久隔离P1。

### F-027：旧会话延迟鉴权错误可修改新会话

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1
- 位置：APIService 请求/重登/logout 路径与 ContentView 静默验证入口
- 触发路径：会话 A 请求或自动登录在途，用户 logout/切换并安装会话 B，A 随后返回 401/403 或登录 200；A→B→A 时结构快照还可能恢复相等。
- 根因：请求创建时 baseURL/token 与登录 acquisition 均未绑定单调 owner；鉴权副作用、登录成功和分步持久化操作响应到达时的全局会话，结构值相等不能区分 ABA。
- 用户影响：旧响应可用 B 凭据重登，失败时清除 B；旧 endpoint/body 还可能被重放到新服务器/账号，成功旧 200 也可能安装混合用户快照。
- 主审证据：业务结果已有 session snapshot，鉴权副作用未使用；静默校验 Task 不可取消。
- 最小方向：请求、login acquisition/loginTask、用户快照安装、重试、持久化提交和 logout 全部绑定同一单调会话代际；会话已变则只结束旧请求，旧 owner 不得关闭新 loading/error。
- 独立复核：verify_b004 确认旧 401/403、旧 200、手动/自动重登与跨服 mutation 重放；V007 的 review_a001_h 主审与 review_a001_j 独立复核又闭合“旧自动登录 A→logout→手动登录 B→A 迟到 200”无需连续按键的生产链及 A→B→A ABA，维持 P2。
- V016 生产补强：添加下载Sheet持有A的torrent/media与A时加载的下载器/目录，却在提交时使用当前API会话；切B后可用B凭据提交A载荷，旧401/403还可沿共享重登路径重放mutation，A→B→A结构快照无法识别。成功callback与defer同样无owner，归CHK-005。
- V018/V020 传播：订阅保存/取消与下载轮询/动作都没有单调会话 owner；页面返回后的 snapshot guard 也阻止不了 API 层先写共享缓存或鉴权副作用，仍统一归 CHK-005/007，而不在各 VM 另造会话机制。
- V019 传播：状态刷新只在起点检查superuser，三个请求的发布前没有session/权限owner；superuser A在途切到manage-only B时，A的Dashboard可晚发布到B仍可见的状态页，直到下一轮才清空。
- V021 传播：批量preview/submit按ID逐次await且只保留结构session snapshot，循环中切服可把后续旧history ID发往新会话；A→B→A仍无法识别，继续归CHK-005。
- W018-A补强：review_a001_j独立确认submit没有session快照，每轮请求都读取当时baseURL/token，401/403递归重放也不复核原manage权限；A服批量ID可在切到另一个manage会话B后继续提交。批量多POST必须在每项前及最终`onDone`前复核同一单调session owner与requiredPermission。
- W015补强（双审确认并升级）：Fork请求前旧权限为true；401/403续登后同用户可只剩`search=true, subscribe=false`，通用请求层仍无条件重放原POST，而当前后端Fork只校验active user，真实写入订阅。修复除单调session epoch外还须携带`requiredPermission`并在续登后重验，后端写端点同步强制授权；错误远端mutation支持条件性P1。
- W020-C传播：verify_a001_h独立确认连接页手动重登在途时，logout或另一次登录B不会使旧A acquisition失效；A迟到成功仍可安装并持久化A的token/currentUser/凭据。该链复用单调login/session owner，不在System另建代际。
- I010传播：通用订阅菜单在A发起fresh lookup后切换到B，A响应命中订阅记录时，后续DELETE重新读取当前APIService单例的baseURL/token，可把A动作续接到B。单会话“订阅”标签反向删除归F-124 P2；只有跨会话的多阶段owner缺失归本项P1/CHK-005，二者不得互相替代。
- I016受限集成传播：System“刷新登录凭据”创建无句柄Task并捕获旧凭据；用户随后确认logout，旧login成功仍可重新安装token/currentUser并保存旧用户名密码，直接反转退出。该P1序列已由本项“旧login撤销logout”覆盖；刷新401是否不应清有效会话另归F-089，连接页新鲜度归F-207。
- I003集成与定向复核：verify_a001_h主审、review_a001_h独立确认A mutation等待期间切B后，A的401/403处理会读取B当前凭据、复用未按epoch/server/user键控的loginTask，并以B当前baseURL/token递归重放A的原method/body；旧自动登录失败还可logout当前B。该API层副作用不能由调用者发布guard修复，维持P1并要求每个请求冻结epoch/server/token、同owner最多重放一次。
- I009集成传播：review_a001_j确认Transfer批量删除、批量手动整理及AI POST→SSE多阶段链都在每次await后重新读取当前baseURL/token；manage会话A切到同权限B后可把A历史ID继续发往B并作用无关文件。完整归本项/CHK-005既有P1，每项请求前后及最终回调复核同一`APIServiceSessionSnapshot`与manage权限，不新增Transfer会话框架。

### F-028：静默校验不刷新权限快照

- 状态：已驳回；用户决定跳过修复
- 严重度：P2
- 位置：`APIService.validateTokenSilently`、ContentView 前台/Tab 入口
- 触发路径：token 有效但后端增加、移除或撤销权限。
- 根因：请求 `/user/current` 后丢弃响应，只有冷启动更新 currentUser。
- 用户影响：新入口不出现，已撤销入口/自动预取/缓存状态继续沿用旧权限。
- 主审证据：现有 current-user 更新路径可复用，但静默校验不触发 currentUser didSet、Tab 收敛或缓存失效。
- 最小方向：按 session identity 原子替换 currentUser；无可访问功能复用登录裁决。
- 独立复核：verify_b004 确认响应完全丢弃并影响根 Tab、预取与缓存，维持 P2；产品是否要求即时生效未验证。
- R001传播：review_a001_h确认ContentView在Tab稳定5秒与scene重新active时真实调用该校验；`visibleTabs`和隐藏选择回退本身正确，但因为响应被丢弃而永远收不到新权限。最小修复复用现有current-user恢复DTO/路径，并在发布前增加单调session owner，不能直接调用无guard恢复方法。
- I016受限集成确认：System整文件复核再次闭合`validateTokenSilently()`丢弃`/user/current`，导致运行中权限/用户资料不刷新；完全落在本项P2，不新增System编号。
- 当前合同复核：官方Web `e6b26cc` 登录后只消费持久权限，前台恢复/路由切换均不请求`/user/current`，403才退出；TV冷启动已有正式current-user刷新，`validateTokenSilently`只负责token失效检测。提交`90b40b4`已保证任何正式session快照发布后Tab、权限警告、缓存和根UI收敛，唯一未实现的是Web也没有的运行中权限热同步。该增强低频且无条件复用恢复helper会在每次Tab校验推进epoch、取消请求和清缓存，副作用超过收益，建议驳回旧P2、不改代码，待用户裁决。
- 用户裁决：管理员在用户运行TV端期间修改权限属于无需专门热同步的低频操作，接受通过重登/重启恢复，F-028驳回并跳过修复。

### F-029：手动重登无权限时保留旧会话

- 状态：已修复（`90b40b4`）
- 严重度：P2
- 修复状态：已完成（`90b40b4`）。设置页手动刷新走`reloginStoredSession`；仅显式无可访问功能且会话epoch未变时登出，密码/网络失败仍保留旧会话，迟到的旧账号候选不能登出新账号。空permissions与Web默认权限差异不并入本项。
- 位置：APIService login no-access 分支、SystemViewModel relogin
- 触发路径：旧会话有权限，手动刷新后登录接口返回新 Token 但无可访问功能。
- 根因：login 先抛 no-access 错误，既不安装新 Token，也不清理旧会话；手动入口只显示失败。
- 用户影响：旧 token、权限和入口继续保留，与冷启动同类场景主动登出不一致。
- 主审证据：App 更新刷新路径已对相同错误 logout，证明出口语义分裂。
- 最小方向：所有重登出口复用同一 no-access 会话裁决。
- 独立复核：verify_b004 确认手动、冷启动与 App 更新重登出口语义分裂，维持 P2。

### F-030：非 Bool 权限项拖垮整个 Token

- 状态：已修复（`ee5dcb4`）
- 严重度：条件性P1；当前官方正常producer证据在G06旧P2基础上升级
- 位置：`MoviePilot-TV/Models/UserPermissions.swift` 的 `[String: Bool]` 合成解码
- 触发路径：任一已知或未来未知权限键为 String/Int/null/object。
- 根因：字典原子解码；单项错误使 Token/CurrentUserResponse 全部失败，super_user override 无法到达。
- 用户影响：通过当前官方Web新建或编辑过的有效账号，只要权限中含正常的嵌套`features`对象，TV登录和`/user/current`恢复都可在权限判断前整批解码失败；superuser也不能绕过。
- 主审证据：JSON fixture 全为原生 Bool；unknown-key 测试只直接构造 Token。
- 最小方向：确认契约后逐键 fail-closed，错误/未知值不授予权限也不毁掉其他明确 Bool。
- 独立复核：verify_b004 确认未知键仍属于字典原子解码，维持 P3；当前 schema 保证未验证。
- G06联合裁决：rounda_g01_recheck建议P1，rounda_g02_third建议P2；两票均核到当前后端只声明泛型`dict`而未逐值保证Bool，Web又逐key以`=== true`失败关闭，不会让一个无关键值拖垮完整身份。取共同下界升P2；只在输入边界逐键接受原生Bool true，不引入truthy宽容或第二套权限模型。
- 当前复核补证：官方Web `UserAddEditDialog` 会把规范化后的嵌套`permissions.features`保存到后端；当前后端create/update不校验且login/current原样返回，因此object值已是正常生产路径，不再依赖异常fixture。F-030升级条件性P1并待用户裁决。
- 拆分边界：空、缺或部分permissions能够成功解码，但Web补legacy默认权限、TV全量fail-closed；这是独立默认语义问题，不并入F-030，也不借修复扩成feature级权限架构。
- 修复状态：已完成（`ee5dcb4`）。`Token`与`CurrentUserResponse`复用单一权限JSON边界，只保留四个已知原生Bool；嵌套`features`、未知键和坏值不再拖垮身份。聚焦22/22、Simulator clean build、排除五个真实后端兼容套件后的本地测试435/435通过；独立复审无P0-P3。

### F-031：空 access token 被视为登录会话

- 状态：降级；用户决定跳过
- 严重度：条件性P3
- 位置：Token 恢复、APIService 登录/持久化、ContentViewModel 登录态判断
- 触发路径：登录响应或独立持久化 token 是空字符串，同时 Token 有可访问权限。
- 根因：登录态只判断 token 非 nil，恢复也允许空 token；空字符串又是 tokenless 快照内部哨兵。
- 用户影响：进入已登录 UI 并展示缓存权限，但请求携带空 Bearer，随后零散失败/登出。
- 主审证据：login 不校验非空，currentOrStoredUser 优先非 nil currentUser；测试无空登录响应/空独立 token。
- 最小方向：所有外部/顶层 token 在登录、加载和安装边界统一拒绝空白；内部 tokenless 用户快照只可与独立非空 token 配对。
- 独立复核：verify_b004 扩展确认全空白 token 与内部哨兵冲突，维持 P3。
- G06联合裁决：rounda_g01_recheck建议P1，rounda_g02_third建议P2；两票均确认空白active token可驱动已登录根UI、发送空Bearer并与tokenless权限快照组合。取共同下界升P2；token写入、恢复、`isLoggedIn`和Authorization共用trim后非空判定即可。
- 当前复核修订：`90b40b4`已在统一记录、legacy恢复与持久化写入拒绝空串，剩余仅纯空白；当前官方后端所有正式producer都由PyJWT生成非空JWT，Web也不校验空白。确定触发收窄为损坏持久化或非官方兼容端，不构成权限提升，降为条件性P3。
- 处理状态：用户决定跳过；若未来官方producer、真实迁移数据或稳定复现证明纯空白可达，再重开顶层active token规范化，不能破坏统一记录内`currentUser.access_token == ""`的内部哨兵。

### F-032：torrent-only 结果被静默空渲染

- 状态：已修复
- 严重度：条件性 P2
- 位置：`Context.meta_info`、`TorrentCard.body`、`TorrentsResultView` 空态判断
- 触发路径：合法 `torrent_info` 存在而 `meta_info` 缺失/null。
- 根因：模型允许部分结果，卡片却要求 meta+torrent；结果页只按原数组是否为空判断空态。
- 用户影响：计数非零且无空态，但卡片为 EmptyView；整批如此时显示空白网格且无法下载。
- 证据：多个 Resource/Search/Permission fixture 为 torrent-only；BackendCompatibility 只要求三类嵌套至少一种。
- 最小方向：按 Web 对齐；只要求 `torrent_info` 存在，元数据字段按可选值分别展示，标题使用媒体名、识别名和 `torrent.title` 兜底。
- 独立裁决：review_s004 确认模型 decodeIfPresent、三组 torrent-only fixture、结果页保留/计数和卡片 EmptyView 链，维持条件性 P2。
- V015 生产补强：现有 ResourceResult fixture 正是 torrent-only，却只断言 ViewModel 数量；真实 `TorrentCard` 渲染仍会静默 `EmptyView`，确认测试盲点。
- 修复状态：`TorrentCard` 已移除 `meta_info` 整体门禁；缺少元数据时仍显示种子卡片并保留下载入口，缺失标签按字段隐藏。
- 跨端核对：当前 MP 官方标题/精确搜索普通与流式链路均会创建 `MetaInfo`；后端 schema 仍允许 `null`，Web 使用可选访问和种子字段兜底，因此本项保留为兼容防御而非当前官方搜索的常规触发。
- 验证：依赖解析、tvOS Simulator Debug 构建及串行测试均通过。

### F-033：分页错误状态无人消费且无保留列表恢复

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Services/Paginator.swift` 错误状态/上限及全部生产调用者
- 触发路径：首次加载失败，或任一页连续失败三次。
- 根因：内部不自动重试；达到上限后 hasMore=false，唯一恢复 refresh 会清列表；生产端无 hasError/lastError 消费者。
- 用户影响：首次错误被显示成“无数据/未找到”，后续页永久截断且用户不知情。
- 主审证据：测试直接调用 loadMore 重试，生产链无相同行为。
- 最小方向：Paginator 单点持有错误/恢复语义，调用者统一呈现并调用其恢复入口，不复制计数器。
- 独立复核：verify_s004 确认全部 13 个实例零错误消费者和页面误空态，维持 P2；H-010 需修正。
- V022-A 生产补强：TransferHistory的Combine桥只订阅items，完全不消费hasError/lastError；第一页失败被显示“没有数据”，后续页三次失败后静默永久截断，现有删除errorMessage也接不到分页错误。
- I009集成确认：review_a001_j从整文件确认refresh/loadMore等待Paginator后从不读取`hasError/lastError`；首屏500显示“没有数据”，分页500静默保留stale。复用现有`handle(error:)`消费Paginator错误即可，P2不变。
- I013第三裁校准：review_a001_j确认详情actors/recommend/similar三个辅助区的局部后果按P3，但F-033覆盖13个生产实例、Transfer首屏误空与分页永久截断，根finding维持P2；详情传播不与F-180主详情失败或F-116成功cache hit合并。
- I006传播：Explore首屏Paginator失败后View只按空items显示“暂无内容”且没有Retry；两份受限整文件复核均确认复用本项统一错误消费/恢复即可，不新增Explore错误状态。
- 用户裁决与修复：保留现有三次连续失败上限；达到上限时由 `Paginator` 发送单一全局事件，`NotificationManager` 显示“加载数据失败，请重试。”。前两次保持静默，不增加重试按钮或页面恢复状态。
- 验证：回归测试覆盖前两次不提示、第三次显示指定文案；依赖解析、tvOS Simulator Debug 完整构建及串行测试均通过。

### F-034：非终止空批被误判为终页

- 状态：用户决定跳过
- 严重度：条件性 P2
- 位置：`SearchViewModel.SharedMediaFetcher` 与 `Paginator` 空数组终止逻辑
- 触发路径：最多五轮只有另一媒体类型，更后页才有目标类型。
- 根因：fetchUntil 达扫描上限可在内部 hasMore=true 时返回空数组，Paginator 把所有空数组永久解释为终页。
- 用户影响：聚合搜索永久漏掉实际存在的电影或电视剧。
- 主审证据：构造页1-6电视剧、页7电影时电影 Paginator 关闭，后续 buffer 无法再取。
- 最小方向：SharedMediaFetcher 仍有后页时不得向 Paginator 返回终止空数组。
- 独立复核：verify_s004 重走 shared buffer/hasMore，确认终页契约冲突，维持条件性 P2。
- V011-F 生产补强：`maxFetchCount=5` 配合首轮并发两页最多扫描 API 1–6 页；若这六页只有另一类型、第 7 页才有目标，actor 在内部 `hasMore=true` 时仍返回 `[]`，Paginator 永久终止。真正后端空页会先置 hasMore=false并允许既有 buffer 排空，故不扩大边界。
- G04 clean-room 末裁：当前后端按source排序后分页，并不保证每页同时含电影/电视剧；因此第1–6页仅异类、第7页目标的反例符合合同。根修只在SharedMediaFetcher扫描到目标或真实总终页，不改Paginator空数组终页语义。
- 处置状态：用户决定跳过；保留当前最多扫描六页的性能边界，接受极端混排下某一媒体类型可能漏项，不再列为待处理问题。

### F-035：in-flight Task 强持有 Paginator

- 状态：用户决定跳过
- 严重度：P2
- 位置：`MoviePilot-TV/Services/Paginator.swift` Task 创建与 deinit
- 触发路径：fetcher 挂起时 owner 释放，但未显式 cancel。
- 根因：Task 弱捕获后立即强绑定 self，self 又持有 Task；请求完成前 deinit 无法先执行取消。
- 用户影响：页面消失后请求、处理与预取继续，长请求延长对象图生命周期。
- 主审证据：固定 owner 多无生命周期 cancel；现有 deinit 测试打开 gate 后等待完成，未断言 deallocation/cancellation。
- 最小方向：给整次 search owner/session 一个显式取消入口；保留已正确工作的 generation 防旧发布，不依赖 deinit 先发生。
- 既有独立复核：verify_s004 确认弱捕获立即强绑定并跨 await，现有 deinit 测试无法证明取消；当时按资源驻留评 P3。
- V011-C 同根扩展：SearchViewModel 强持有 `searchStreamTask`，Task 闭包又强捕获 self，且无 deinit/页面生命周期取消入口；静默 SSE 可让页面移除后对象与请求继续驻留，复用显式 owner 生命周期取消方向，不另编号。
- V022-A 同根扩展：搜索创建无句柄Task并强持有owner，View `.task`取消也不拥有Paginator内部Task；明确的永久环另归F-071，旧发布/query owner归F-072。
- G04 clean-room 末裁：显式`cancel()`与新搜索已有generation/取消屏障，旧结果不会写回；确定缺口收窄为owner离场没有对应屏障且底层任务/owner继续。因请求生命周期与页面owner确定脱节，升级P2；push详情、切Tab、销毁三种离场是否都应取消仍须产品/运行验收。
- 处置状态：用户决定跳过；接受慢请求或挂起请求在离页后继续占用网络、预取和对象内存，正常请求快速完成时通常无感，不再列为待处理问题。

### F-036：processor 漏掉页内重复 ID

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：`SearchViewModel` 人物 processor、`TransferHistoryViewModel` processor
- 触发路径：同一页有重复 raw_id/id，或人物缺 raw_id 后生成相同 id。
- 根因：只从旧 items 建不可变 existingIds，过滤当前批次时不插入已接受 ID。
- 用户影响：ForEach 重复身份、焦点含糊，firstIndex 总指向首项并可能停止继续分页。
- 主审证据：fixture 均唯一，Paginator 正确去重测试采用可变 seen set。
- 最小方向：仅修两处 processor，以可变 seen set 同时覆盖旧数组和当前批次。
- 独立复核：verify_s004 确认 Person/Transfer 最终 ID 边界及焦点/分页影响，维持条件性 P3。
- V011-D 补强：人物 processor 只用旧 `raw_id` 建不可变集合，除漏同页与 nil 重复外，还可把不同 source 的同 raw ID 跨页误合并；最小修复应以最终 `Person.id` 建可变 seen set并在接收当前批次时插入，不另编号。
- V022-A 生产复核：Transfer processor在旧列表为空时对同页`[id:7,id:7]`两项都放行，rebuild快路径又原样保留；ForEach/Focus与loadMore firstIndex直接消费重复ID。
- G07第三裁：verify_a001_h确认`Person.id`已是`source + raw_id`，Search却仅按raw_id对旧页去重且同批不更新seen；跨source合法同号会误删、批内重复会进入ForEach，升P2。修复为持久可变`seenPersonIDs`并在reset清空；连续无新增页停止仍独立归F-034。
- 修复：Search按包含来源的最终`Person.id`维护持久seen，并在Paginator reset时清空；Transfer在过滤当前批次时同步写入seen，避免同页重复身份。
- 验证：补充人物身份去重单元测试，以及复用同一个Search人物Paginator执行`refresh()`的链路测试；依赖解析、tvOS Simulator Debug完整构建与串行全量测试均通过。

### F-037：有效语言标识未经规范化

- 状态：未验证
- 严重度：P3
- 位置：`MoviePilot-TV/Services/TranslationHelper.swift:1-207,502-504` 与详情 original_language 链
- 触发路径：`EN`、` en `、`en-US`、`zh-Hant` 或历史别名。
- 根因：对原字符串做大小写敏感整串查表，无空白/大小写/主子标签/别名规范化。
- 用户影响：可识别语言显示原始代码，而非本地化名称。
- 主审证据：模型/API 原样传递，映射仅小写两位键和少数手工别名，无直接测试。
- 裁决：整串大小写敏感行为确认，但函数只声明 ISO 639-1，不能把完整 BCP 47/历史别名支持确认为既有契约。
- 最小方向：仅在上游契约确认后于 helper 单点 trim、大小写和主语言规范化；未知非空值保真。

### F-038：空白语言值穿透详情元数据

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/TranslationHelper.swift:506-521`（`languageName(for:)` 先 trim 再查表）、`MoviePilot-TV/ViewModels/MediaMetadataText.swift:35-72`（`secondaryLine` 按显示值归一后才 append）
- 触发路径：original_language 为 empty/空格/换行。
- 根因：模型接受任意非 nil 字符串，helper 原样回退，调用者只判 non-nil 就 append。
- 用户影响：尾随/空白分隔点，或创建空 Text 行。
- 主审证据：decodeIfPresent 不过滤空白，显示数组按元素数量判断。
- 最小方向：元数据 builder 统一 trim/过滤空显示值，不只补语言分支；release_date/year/国家名一并回溯。
- 独立复核：verify_b006_a_retry 确认空 Text 与尾随分隔，维持 P3。
- 修复状态：按“最小方向”在**元数据 builder 边界**统一归一，不只补语言分支 —— 新增 `MediaMetadataText`（`MoviePilot-TV/ViewModels/MediaMetadataText.swift`），把详情页两行元数据的组装从 `MediaDetailView` 的内联闭包中提取出来，所有元素都过 `displayValue(_:)`（trim `whitespacesAndNewlines`，空结果返回 nil 即丢弃）。`original_language`、`release_date`、`year`、`category`、`type` 五个标量字段全部回溯到同一判据；叶子层 `TranslationHelper.languageName(for:)` 同步改为先 trim 再查表（带空白的代码不再绕过词表），全空白输入返回空串交由 builder 丢弃。
- 验证：`MediaMetadataTextTests` 中 `testBlankOriginalLanguageProducesNoElement`（`""` / `"   "` / `"\n"` 三种载荷均不产出元素，两行皆空）、`testBlankReleaseDateFallsBackToYear`（空白上映日期回退年份，两者都空白时整行不渲染）、`testLanguageCodeIsTrimmedBeforeLookup`、`testHostilePayloadProducesNoDanglingSeparator`（端到端断言拼接后无前导/尾随/连续分隔符）。临时还原为修复前行为后 13 项失败、仅阳性对照 `testAllValidFieldsArePreserved` 通过，确认断言确实区分缺陷而非仅引用新 API。
- 处置状态：用户逐条过 P3 时经解释触发链（上游返回空串/空白 `original_language` → 只判 non-nil 就 append → 渲染空 Text 或尾随 `·`）与影响面后，批准随“组二”一并修复。
### F-039：取消 Paginator 不会取消共享搜索真实请求

- 状态：用户决定跳过
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/SearchViewModel.swift` 的 SharedMediaFetcher/currentFetchTask
- 触发路径：旧聚合搜索挂起时发起新搜索、切换模式或离开页面。
- 根因：实际 API 调用在独立 Task 中；Paginator.cancel 只取消等待者，不取消该任务。单个waiter退出时保留共享请求是合理语义，但整个search session废弃时也没有aggregate cancel。
- 用户影响：旧查询继续占用网络/后端并与新查询重叠；结果会被 generation 丢弃，但扩大旧会话请求风险。
- 证据：现有测试必须主动打开旧 gate 才结束，只验证不发布旧结果。
- 最小方向：仅在整次search session失效时取消共享fetch task并阻止cursor/buffer继续推进；取消单个waiter不得误伤另一合法waiter。
- 既有独立复核：review_a001_h 从 V011-C 独立确认新 unified 只 cancel 旧 Paginator 等待者，`SharedMediaFetcher.currentFetchTask` 继续；unified→resource 更不 reset 旧 Paginator。现有测试必须手动打开旧 gate 才结束旧请求，当时评P3。
- V011-C 单元复核：review_a001_j 再独立确认 unified→unified 的真实请求/后续扫描继续，以及 unified→resource 的旧 Paginator、hidden items 与请求全继续；跨会话发布仍归 F-027/CHK-005。
- G04 clean-room 末裁：确认底层URL请求、buffer与`apiPage`在session废弃后仍继续；以“单waiter取消不传递、session owner取消必须传递”的双测试边界升级P2，并与F-035共享owner级取消实现但保留独立回归。
- 处置状态：用户决定跳过；旧结果已有generation屏障不会发布，接受慢请求在会话失效后继续占用网络与后端资源，避免修改共享任务取消语义引入竞态。

### F-040：不同职位键翻译后重复显示

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/TranslationHelper.swift:491-505`（显示边界去重）、`StaffManager.swift:126-141`
- 触发路径：同一人员同时携带两个 key，或重复记录分别携带。
- 根因：原始 key 阶段认为不同，翻译后都为“摄影”且不再去重。
- 用户影响：职员卡片显示“摄影/摄影”，未来职位分组也可能同名重复。
- 主审证据：两个映射值一致，processCrew 保留两个原始 key 后逐项翻译。
- 最小方向：保留原始 key/优先级，在最终显示边界稳定去重；若产品要区分则改词表。
- 独立复核：verify_b005 确认 PersonCard 可见重复；当前 Hero 只取一组，不能夸大为 Hero 必现。真实组合/词义未验证。
- 修复状态：按“最小方向”取显示边界去重 —— `TranslationHelper.translateJobs` 先经 `canonicalJobKeys(from:)` 规范化，再对**翻译结果**去重。原始 key 阶段的去重（`mergeUniqueStrings`）保持不变，故优先级仍按各原始 key 独立计算，未被显示去重影响。同一去重同时闭合 F-053 的回灌叠加。
- 验证：`StaffJobNormalizationTests` 中 `testCinematographyAndCameraCollapseToSingleDisplayName`（单条记录含两 key）与 `testSamePersonWithBothCameraKeysAsSeparateRecordsCollapses`（两条记录合并）均断言显示为「摄影」。临时还原消费者改动后两例均失败，确认测试捕获本缺陷。
- 处置状态：用户逐条过 P3 时经解释触发链（职员行 PersonCard 读经 StaffManager 写回并翻译的 job 字段）与影响面后，批准随“组一”一并修复。

### F-041：职位键变体绕过翻译与优先级

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Models/JobRegistry.swift:113-149`（canonical 解析）、`StaffManager.swift:9-16`（优先级）、`TranslationHelper.swift:491-505`（翻译）
- 触发路径：`director`、`Director\n` 或未登记同义别名。
- 根因：消费者仅 trim `.whitespaces`，没有共享 canonical key/alias。
- 用户影响：重要职位降为优先级 999 并显示原始文本，Hero 可能改选较低重要度职位。
- 主审证据：Person.job 原样解码，翻译与优先级共同消费未经规范化字符串。
- 最小方向：G07 单一 canonical job key 解析供翻译和优先级共用；未知保真并最低优先级。
- 独立复核：verify_b005 确认大小写/换行同时绕过两张表并可改变 Hero 选择，维持 P3；别名映射与上游保证未验证。
- 修复状态：按“最小方向”在 `JobRegistry` 增加 `canonicalJobKey(for:)` / `canonicalJobKeys(from:)` 单一解析入口（清理 `whitespacesAndNewlines` → 精确匹配 → 大小写不敏感匹配 → 未知原样保真），翻译与优先级共同消费该入口。`getPriority` 改为对规范化后的 key 查表；`mergeUniqueStrings` 与分组拆分的 trim 从 `.whitespaces` 收敛为 `.whitespacesAndNewlines`。未登记别名仍保真显示、保底 999，不静默丢弃上游信息。
- 验证：`testJobKeyVariantsResolveToCanonicalKey` 覆盖大小写/换行/首尾空白/未知保真/全空白，`testJobKeyVariantsAreTranslated` 覆盖翻译侧，`testLowercaseDirectorOutranksProducerInHero` 覆盖 Hero 排序侧。临时还原消费者改动后后两例失败（`director` 显示原文且被 Producer 压过），确认修复必要。
- 处置状态：用户逐条过 P3 时经解释触发链（中文界面出现英文职位、导演被次要职位顶掉）与影响面后，批准随“组一”一并修复。
- 剩余未验证：上游是否真的产生大小写/换行变体；别名映射表仍为空，未登记别名只在显示层保真。

### F-042：国家码形态未统一规范化

- 状态：未验证
- 严重度：P3
- 位置：`TranslationHelper.countryName`、`ProductionCountry`、详情国家显示
- 触发路径：lowercase/带空白 alpha-2、字符串 `"US"`、alpha-3 `"USA"`。
- 根因：两个入口原串精确查表；字符串形态固定进 name，不再识别 code；对象入口不复用 canonicalizer。
- 用户影响：简体中文界面显示 US/USA/API 英文名而非“美国”。
- 主审证据：249 个 canonical alpha-2 键完整，但无国家解码/显示测试。
- 裁决：249 个 canonical alpha-2 全部正确覆盖；lowercase/空白/字符串 code/alpha-3 是否属于真实契约无法确认。
- 最小方向：仅在上游确认后，对 trim 后两位 ASCII 字母大写查表；不顺带加入 alpha-3、UK/XK/历史码。

### F-043：空/畸形国家元素生成空白分隔符

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/TranslationHelper.swift:538-546`（`countryName(for country:)`）、`MoviePilot-TV/ViewModels/MediaMetadataText.swift:53-62`（`secondaryLine` 国家段）
- 触发路径：null/数字/布尔/数组/空对象，空白 code/name，或未知 code 无 name。
- 根因：不支持元素静默变 `(nil,nil)`，对象入口回退空串，View 仅判原数组非空就 map+joined。
- 用户影响：`2024 · `、空 Text 或 `中国 / `。
- 最小方向：未知非空 code 保真；先在国家叶子层 trim/过滤再 `/` 连接，之后外层元数据再过滤并以 `·` 连接。
- 独立复核：verify_b006_b 确认 null/畸形元素被保留为 nil 模型并稳定产生尾随/空分隔，维持 P3。
- 修复状态：按“最小方向”两层一起改 —— 叶子层 `countryName(for country:)` 先对 `iso_3166_1` 与 `name` 分别 trim；查不到翻译时优先用名称，名称也缺失则**保留未知非空 code 原文**（此前一律回退空串，上游信息被静默丢弃）；两者都为空才返回空串。`countryName(for code:)` 同样先 trim 再查表。外层 `MediaMetadataText.secondaryLine` 不再只判原数组非空，而是逐项归一后丢弃空结果，数组里只剩畸形元素时整段不进入显示行。
- 验证：`testMalformedCountryElementsProduceNoElement`（`null` / `42` / `true` / `{}` / 空 code+name / 全空白 code+name 六种载荷均不产出元素）、`testMalformedCountryElementsAreDroppedButValidOneSurvives`（`[null, US, {"name":""}]` → `["美国"]`，无悬空分隔符）、`testUnknownNonEmptyCountryCodeIsPreserved`（`{"iso_3166_1":"ZZ","name":""}` → `"ZZ"`，保真而非丢弃）、`testCountryNameIsTrimmedBeforeLookup`、`testEnglishCountryNameIsTrimmed`。临时还原后上述断言全部失败、阳性对照仍通过。
- 处置状态：用户逐条过 P3 时经解释触发链（畸形元素解码成 `(nil,nil)` → 对象入口回退空串 → View 只判数组非空就 map+joined → `中国 / ` 这类尾随分隔）与影响面后，批准随“组二”一并修复。
### F-044：人物搜索绕过职位翻译

- 状态：已修复
- 严重度：P3
- 位置：Search 人物分页到 `SearchView` 人物行
- 触发路径：搜索响应人物含 canonical `job`，如 Director。
- 根因：未经 StaffManager/TranslationHelper 处理，直接把 person.job 作为字幕。
- 用户影响：默认中文界面搜索显示英文 Director，而详情职员卡显示“导演”。
- 证据：即使完全 canonical 也触发，区别于 F-041 的变体失配。
- 最小方向：人物职位展示走统一翻译边界，不在 View 手工词表。
- 独立支持：B006-C 主审重走 searchPerson→SearchView，确认 canonical Director 也直接显示英文，维持 P3。
- 剩余未验证：搜索响应 job 非空频率。
- 修复状态：按“最小方向”在人物分页器的 `processor` 统一投影，不在 `PersonCard` / 最佳结果卡片两处打补丁。`SearchViewModel.translatingJobForDisplay` 用 `TranslationHelper.translateJobs` 投影非空 `job`，结果为空或与原文相同时原样返回（`translateJobs` 对未登记 key 原样返回、翻译后去重，对已翻译值是幂等的，因此重复投影不会叠成「导演/导演」）。投影发生在 `Person.deduplicate` 之前，首屏与 loadMore 走同一条路径；人物行（`personPaginator.items`）与最佳结果卡片（`bestResults`）同源，一处修复覆盖两个出口。
- 验证：`testSearchPersonJobIsTranslatedForPersonRow`（canonical `Director` → 「导演」，人物行）、`testSearchPersonJobIsTranslatedForBestResultSubtitle`（最佳结果卡片副标题同为「导演」）、`testSearchPersonJobProjectionHandlesMultiJobAndMissingJob`（`Director/Writer` → 「导演/编剧」；无 `job` 的人物不被凭空造出职位、`character` 原样保留）、`testSearchPersonJobProjectionIsIdempotentForTranslatedValue`（已翻译值「导演」原样保留，阴性对照）。临时还原投影调用后前三条失败、幂等对照仍通过。
- 处置状态：用户逐条过 P3 时经解释触发链（搜索响应人物含 canonical `job` → 搜索链路完全绕过 `StaffManager.processCrew` 的翻译边界 → 两个 View 直接渲染 raw job）与影响面（中文界面人物行显示英文 `Director`，而详情页同一人显示「导演」）后，批准随“组四”修复。

### F-045：roles-only 职员跨展示不一致

- 状态：已确认
- 严重度：P3
- 位置：StaffManager Hero 分组、processCrew 与 PersonCard
- 触发路径：Person 只有 roles，没有 job/character。
- 根因：getTopGroupedStaff 用 roles 兜底，processCrew 不投影 roles，卡片只读 job/character。
- 用户影响：Hero 显示职位，职员卡同一人无副标题。
- 最小方向：在 StaffManager 统一 roles 到展示职位的投影，不在两个 View 分别补丁。
- 独立确认：S006 主审确认只有无有效 job 分组时 Hero 才用 roles，但 PersonCard 从不读 roles；维持 P3。
- G07阶段性升级建议：两代理从当前Douban链确认`roles`已解码且Hero可消费，但PersonCard稳定只读job/character，真实职员卡职责副标题丢失；当时建议P2。纯job canonical链正常、混合job/roles仅插件候选；下行第三裁已将最终等级定为P3。
- G07第三裁：verify_a001_h确认Douban `roles`投影缺口独立成立，但当前Web普通PersonCard同样只显示character，且真实“无character仅roles”比例未验证；维持P3，卡片subtitle只在job/character均空时回退去空去重roles。
- 剩余未验证：真实 Douban/Bangumi roles 形态与频率。
- 修复状态：按“最小方向”在 `StaffManager.mergeCrew` 的最终 map（`StaffManager.swift:126-141`）统一投影 —— 当 `job` 与 `character` **均无内容**时，把 `roles` 经 `translateJobs` 投影进 `job`，两个 View 不再各自打补丁。判据严格贴合第三裁表述，`character` 非空时不覆盖副标题。`getTopGroupedStaff` 的 roles 兜底分组同步改为逐项规范化后拼接（`StaffManager.swift:228-240`）。
- 验证：`testRolesOnlyCrewGetsJobProjectionForCardSubtitle` 断言 roles-only 职员经 `processCrew` 后 `job == "导演"`；`testCharacterSubtitleIsNotOverriddenByRoles` 作为阴性对照断言 `character` 非空时 `job` 仍为 nil。临时还原后前者失败、后者两侧均通过，确认投影生效且未越界。
- 处置状态：用户逐条过 P3 时经解释触发链（Hero 有职位、同人卡片空白）与影响面后，批准随“组一”一并修复。

### F-046：类型名未规范化且空结果进入详情元数据

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/TranslationHelper.swift:556-566`（`translateGenre(for:)`）、`MoviePilot-TV/ViewModels/MediaMetadataText.swift:20-29`（`primaryLine` 类型段）
- 触发路径：带空白/换行 canonical genre，或 null/数字/空对象/空名称元素。
- 根因：模型保留原字符串或宽容为空元素；翻译精确查表不 trim；View 只判数组非空就 joined/append。
- 用户影响：canonical 类型不翻译，空 Text、`电影 · ` 或尾随/重复分隔符。
- 主审证据：无 genre 翻译/最终显示测试。
- 最小方向：genre 叶子 `whitespacesAndNewlines` trim/filter，未知非空名称保真；内层 genre 和外层元数据均过滤空结果。
- 独立复核：verify_b006_c 确认 null/数字/空对象与带空白名称路径，维持 P3；大小写/别名/ID 回退未验证。
- 修复状态：按“最小方向”只动显示链，不改多态解码 —— `translateGenre(for:)` 先 trim `whitespacesAndNewlines` 再查表（带空白的 canonical 类型此前不翻译），全空白输入返回空串，未知非空名称 trim 后**保真**返回（不改大小写、不加别名回退，与独立复核收窄的范围一致）。内层 `MediaMetadataText.primaryLine` 在 `compactMap { $0.name }` 之后、翻译之后再丢一次空 —— 原写法只丢 nil，空串会活到 `joined(separator: " · ")`；外层同样按显示值归一。`category`/`type` 的判空也一并回溯（带空白不再穿透）。
- 验证：`testBlankAndMalformedGenreElementsProduceNoElement`（`[{"name":""}]` / 全空白 / `[null]` / `[42]` / `[{}]` / `[{"id":28}]` / `[""]` 七种载荷都只剩分类段）、`testWhitespacePaddedGenreIsTranslated`（`" Sci-Fi & Fantasy "` → `"科幻 & 奇幻"`）、`testUnknownGenreNameIsTrimmedButPreserved`、`testBlankCategoryFallsBackToType`、`testAllValidFieldsArePreserved`（阳性对照，多类型顺序与分隔符不变）。临时还原后除阳性对照外全部失败。
- 处置状态：用户逐条过 P3 时经解释触发链（带空白/空名称的 `genres` 元素 → 精确查表不 trim 且空串不是 nil → `电影 · ` 或空 Text）与影响面后，批准随“组二”一并修复。
### F-047：取消文案无法表示 owner 与批量影响

- 状态：用户决定跳过
- 严重度：条件性 P1；由条件性 P2 升级
- 位置：SubscriptionCancelConfirmation、Home/分季/Header/媒体卡片取消链
- 触发路径：超管快照中同媒体同季存在不同用户或多条订阅。
- 根因：Home 有 username 但不显示；分季摘要按 season 只保留首条且丢 owner；部分路径直取消也无“单记录”证明。
- 用户影响：用户以单条文案执行跨用户/多记录删除，无法辨认 owner/命中数。
- 最小方向：取消意图携带 owner、命中数和实际范围；直取消只用于已证明单用户单记录。
- 独立复核：verify_b007 确认 Home、分季、Header、Handler 的 owner/命中数缺口，维持条件性 P2。
- V012-B 补强：详情准备阶段只生成文案，`SubscriptionLookupResult` 无 owner/count/scope；读取失败仍开放通用确认。真正执行又重查并选择 ID级或媒体级删除，确认信息无法表达或冻结实际范围，维持本项/CHK-006。
- V012-C 生产补强（经独立复核）：Header 只对 `canDirectlySubscribe` 的电影开放取消链，但多季 warning 只统计 `type == 电视剧`；纯 TMDB电影跳过快照，Douban/Bangumi fallback也只统计电视剧，AniList虽可由Preloader识别TMDB fallback却被warning初始guard漏掉。重复电影订阅/不同owner/真实媒体级范围均不说明，甚至可提示同TMDB异类型记录；两个warning测试直接用电视剧调用helper，绕过生产入口，不能作为覆盖。
- V017 生产补强：超管快照同媒体同季可有多owner/多记录，分季摘要按season first-wins并丢username/count/scope，确认文案只显示一个group；维持CHK-006。
- 当前上游复核修订：当前后端已对TMDB/Douban/Bangumi/AniList/canonical/plugin身份统一应用`season`筛选，旧“非TMDB跨季删除”反例不再成立。剩余问题是同媒体同季可存在多group/多owner记录，而TV只展示首条group/不展示owner和命中数，媒体级删除仍可能命中该季多条；Web共享同一接口。最小方向收窄为冻结精确ID与owner/group/count/scope。
- I008集成映射：review_a001_j从整文件再次确认警告查询失败会退普通文案但仍开放破坏性确认，执行阶段再解析媒体级目标；范围未展示与上游宽删除后果继续由本项P1承载，不新增编号。
- I008定向复核校准：review_a001_h确认Header执行前会重查目标，缺口是确认时未冻结/重查scope并在读取失败时fail-open；Header局部静态后果裁P2，不推翻W013-B已确认的跨季宽删除使本项保持条件性P1。
- 当前用户裁决：当前Web共享媒体级删除和通用确认行为；TV端跳过，不做额外精确ID增强。

### F-048：确认目标与执行目标未绑定

- 状态：用户决定跳过
- 严重度：条件性 P1
- 位置：MediaDetailViewModel 警告准备、MediaDetailView 确认执行
- 触发路径：影响范围查询失败、连续点击乱序、确认期间订阅/fallback 目标变化。
- 根因：准备失败退回普通文案；确认后 deleteResolvedSubscription 又重新 lookup/解析，不绑定提示时目标。
- 用户影响：只确认“该媒体”却执行无 season 的批量删除，或删除不同目标。
- 最小方向：准备阶段生成不可变 cancel intent；无法确认宽删除范围则阻止，目标/owner/命中数变化需重新确认。
- 独立复核：verify_b007 扩展到分季确认后范围变化，维持条件性 P2。
- V012-B 补强：准备与执行之间 target/owner/命中数变化不会阻断删除；取消动作又无 session/action owner，A lookup 后切 B 可用 B 凭据 DELETE，`CancellationError` 还会被候选 catch 吞掉继续 fallback。session 部分归 F-027/CHK-005，本项继续约束冻结 intent。
- V012-C 补强：未找到目标、lookup/snapshot 错误或 `CancellationError` 都退回普通文案并继续展示 destructive alert；确认后完整重跑 lookup，删除模式/mediaId/exact ID/owner/count/range/session 可变化。连续准备 Task 也无 revision，晚到文案可覆盖；应一次生成小型不可变 cancel intent，失败/取消不开放，变化则重确认。
- V017 生产补强：Alert只保存季号；执行时重新强刷并仅检查仍有任一记录，不比较确认时ID/group/owner/count，随后执行媒体+季删除。冻结cancel intent仍是单点最小边界。
- I008双审校准：review_a001_j确认View只保存String/Bool；review_a001_h进一步反证“目标完全不重查”，执行确会重新lookup目标，但不会冻结或重新比对用户已确认的target/scope fingerprint，scope也不重读。准备失败阻止确认、变化后要求二次确认仍是最小修复，维持P2。
- G02全局裁决：verify_a001_h与rounda_g02_third分别确认确认后目标/session未冻结，且lookup与DELETE之间替换同键记录可让用户确认A却删除B；两张新票将错误删除后果升级条件性P1。单纯准备失败仍只按P2，不单独触发P1。
- 当前用户裁决：当前Web同样在确认后读取当前媒体并执行媒体级删除；TV端跳过，不做单端差异化修复。

### F-049：Home/Header 取消业务失败静默

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：HomeView/HomeViewModel、MediaDetailViewModel
- 触发路径：缺订阅 id、远端已删、success:false、lookup/delete false。
- 根因：流程只返回 Bool 并丢弃 false；Home 显示确认前也未强刷。只有抛错才通知。
- 用户影响：弹窗关闭但订阅仍在或请求未发，无失败原因。
- 最小方向：无法确认目标、删除被拒绝或刷新后仍存在时走现有错误通知；远端已删除且 UI 已收敛无需强报错，成功保持静默。
- 独立复核：verify_b007 确认 message/Bool 丢失并收窄边界；G08 第三裁从当前 HEAD 确认 Home 直接丢弃删除 Bool，业务拒绝会稳定无反馈，升级 P2。
- V012-B 补强：详情 DELETE 返回 false或抛错只打印，随后照常强刷；无法区分远端已不存在的可接受静默收敛与真实业务拒绝。复用 Handler 现有 `deleteSubscriptionResult` 和错误通知即可，不新增结果框架。
- G08 归并校准：SubscribeSheet 回滚忽略 DELETE `false`、异常只打印会留下真实已创建订阅，属于 F-148 的 P1 回滚持久遗留；本项只保留 Home/Header 的业务反馈丢失，避免重复计数。
- I008集成补强：review_a001_j确认Header点击前强刷失败直接return，取消`success:false`/throw只打印，页面已有SubscriptionHandler通知出口却未复用；查询失败、业务拒绝与异常统一走本项P2反馈，不另建错误框架。
- I008定向复核：review_a001_h确认DELETE业务false、throw及随后refresh失败均无用户反馈；复用现有result/message与通知出口即可，P2不变。
- 修复：Home取消返回false或抛错时统一通知“取消订阅失败，请重试”；Header让ViewModel返回最终收敛结果，仅在删除失败且刷新后仍订阅时通知，远端已由其他入口删除则保持静默。
- 验证：补充Home业务失败、Header失败后仍订阅及两个View通知接线测试；依赖解析、tvOS Simulator Debug完整构建与串行全量测试均通过。

### F-050：Hero 演员先截断后去重

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:191-220`（`applyFullDetail` 主演初值）
- 触发路径：前四条演员含同一 Person.id 多角色重复，后面还有不同演员；或前四条含 name 为 nil／trim 后为空的人。
- 根因：先 prefix(4) 再 processActors 去重；分页结果仅在 Hero 完全为空时替换。
- 用户影响：Hero 长期少于四名主演。
- 最小方向：完整去重后取前四并保持服务端顺序。
- 独立复核：verify_s006 确认影响仅 Hero、演员货架不受影响，并修正回溯为 W008-C；维持 P3。
- G07全局双审升级建议：两代理用`[A角色1,A角色2,B,C,D]`及空名构造确认先截断、后去重/滤名且分页只在全空时回填，稳定令Hero少人；建议F-050/F-056同一取样顺序族升P2。Search最佳结果先去重/过滤再限12，旧同类说法驳回；等级交第三裁。
- G07第三裁：verify_a001_h把重复、nil/空名与后续补位统一裁为本项Hero选人根因，维持P3；先全量`processActors`、过滤trim后空名，再`prefix(4)`。F-056作为重复编号驳回并入，不扩到Search。
- 修复：按 G07 第三裁的顺序落地 `processActors` → 过滤 trim 后空名 → `prefix(4)`。过滤只落在 Hero 取样这一层，不下沉到 `mergeActors` —— 演员货架是否收无名者属另一条口径，verify_s006 已确认货架不受本项影响。尾部「完全为空才补」分支保持原样：它只在 `heroTopActors` 彻底为空时兜底，此时过滤与否都不改变「这份数据本就没有可显示的主演」这一结论。
- 验证：定向 9/9。反向验证分两次单独还原 —— ①退回「先 `prefix(4)` 再去重」：当时那版 6 条用例中 1 挂（重复项挤人）/ 5 过；②仅去掉空名过滤：9 条中 2 挂（`["乙","丙","丁"]`、`["   ","乙","丙","丁"]`）/ 7 过。全过程修正一处用例缺陷：`testMergedDuplicateKeepsAllCharacters` 在新旧实现下同过（合并口径不随选取顺序变，旧实现取的前四条里重复项本就都在），它拦的是「用 Set 只留首条」这类错误修法而非本 bug，已由阳性改标为阴性对照。全量 **991/991 通过、零失败**（982 + 9）。
- 跨端结论：后端 `actors` 取自 TMDB `credits.cast`，只按 `known_for_department == "Acting"` 过滤、**不去重**（`app/core/context.py:481-486`），而 TMDB cast 结构上允许同一个人以不同 `character` 出现多条；视图 `MoviePilot-TV/Views/Pages/MediaDetailView.swift:1037` 用 `compactMap { $0.name }.joined(...)`，无名者渲染为空档却照样占名额。Web 无 Hero 主演行（演员经 `/credits/...` 页面展示），没有可对照面。
- 处置：用户逐条过 P3 时听完触发链与影响面后裁决「直接修吧」。真实重复分布与无名人物分布均未验证（未加真机日志统计频率）。

### F-051：头像排序与可渲染图片判定不一致

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/StaffManager.swift:109-112`（排序消费点，原 `hasAvatar` 已删除）、`MoviePilot-TV/Models/Models.swift:2286-2289`（`Person.hasUsableProfileImage`）
- 根因：前者检查任意原始 profile_path/avatar/images 存在，后者按 source 严格选择可渲染 URL。
- 用户影响：最终只有占位图的人员可排在真正有头像人员之前。
- 证据：TMDB 空 images、Douban 默认头像、Bangumi only-large、AniList only-avatar 等现有解码反例。
- 最小方向：排序复用最终 `imageURLs.profile != nil` 判定。
- 独立复核：verify_s006 确认 source-aware 图片反例和影响限于 crew 新增项同优先级排序，维持 P3。
- G07全局双审升级建议：当前统一`imageURLs.profile`已处理来源、默认豆瓣头像与Bangumi/AniList选择，但Staff排序仍看原始字段，Search最佳人物又只看TMDB `profile_path`；两代理建议F-051/F-055分别升P2并共用`hasUsableProfileImage`。实际排序/准入竞争频率仍未运行，交第三裁。
- G07第三裁：verify_a001_h确认Staff排序只需直接复用现有`person.imageURLs.profile != nil`，默认豆瓣头像与空images均为反例；影响限排序且分布未验证，维持P3。`mergeCrew(existing:非空)`当前无caller，不并入。
- 修复状态：按“最小方向”直接复用最终判定 —— 新增 `Person.hasUsableProfileImage`（`imageURLs.profile != nil`，与卡片渲染同一事实来源），排序消费点改用它，**同时删除** `StaffManager.hasAvatar`（全仓唯一调用点就是这处排序），避免第二份判据继续存在。影响面确认仅限 `mergeCrew` 新增项同优先级内部排序：人数、内容、去重、已有列表位置均不变。
- 验证：`PersonProfileImageAvailabilityTests` 中 `testCrewSortPrefersRenderableAvatarOverRawFieldPresence`（Bangumi 仅 large + 带 `profile_path` 的占位图人物，必须排在真有豆瓣头像的人之后）；叶子反例 `testBangumiOnlyLargeIsNotUsableEvenWithProfilePath` / `testDoubanDefaultAvatarIsNotUsableEvenWithProfilePath` / `testTMDBEmptyImagesIsNotUsable` / `testUnsupportedSourceIsNotUsableEvenWithAllRawFields`。临时把新判据换回修复前的原始字段逻辑后，上述 5 例失败；`testAnilistAvatarOnlyIsUsable`、`testDoubanAvatarIsUsableWithoutProfilePath` 与阴性对照 `testCrewSortKeepsJobPriorityDominantOverAvatar` 两侧均通过，确认修复未越过职位优先级。
- 处置状态：用户逐条过 P3 时经解释触发链（同职位新增职员、占位图被判成有头像）与影响面（仅排序、一处调用点）后，批准随“组三”一并修复。

### F-052：多值 roles 整体降为未知优先级

- 状态：已确认
- 严重度：P3
- 位置：StaffManager.getTopGroupedStaff roles fallback
- 触发路径：roles `["Director","Writer"]` 且存在其他职位组。
- 根因：先 join 为 `Director/Writer` 再整体查 jobPriorityMap 得 999，翻译阶段却重新拆分。
- 用户影响：Producer 等次要职位可能压过包含 Director 的人员；空 roles 还造首尾 `/`。
- 最小方向：roles 元素逐项规范化/过滤，取最小优先级后生成显示文本。
- 独立复核：verify_s006 以 roles-only Director/Writer 对 Producer 的 fallback 反例确认，维持 P3。
- 修复状态：按“最小方向”把 `getPriority` 改为先 `canonicalJobKeys(from:)` 拆分，再取各项优先级的**最小值**（`StaffManager.swift:9-16`），因此 `"Director/Writer"` 得 0 而非 999；`mergeCrew` 内的单批优先级同样收敛到该入口，去掉了此前的逐项 trim 后再查表。显示文本侧，roles 兜底标签改为逐项规范化后再 `/` 拼接（`StaffManager.swift:235`），`["", ""]` 不再生成孤立的 `/` 分组标签。
- 验证：`testRolesFallbackRanksByBestRolePriority` 以 roles-only 的 Director/Writer 对 Producer 反例断言 Hero 取「导演/编剧」；`testAllEmptyRolesProducesFallbackLabelNotStraySeparator` 断言空 roles 落到「职员」而非 `/`。临时还原后两例均失败，确认修复必要。
- 处置状态：用户逐条过 P3 时经解释触发链（Hero 把导演换成制片人）与影响面后，批准随“组一”一并修复。本组内唯一会产生**结果错误**（而非纯显示问题）的一条。

### F-053：mergeCrew 不能消费自身返回值

- 状态：已确认
- 严重度：条件性 P3
- 位置：StaffManager.mergeCrew(existing:newBatch:)
- 触发路径：已翻译返回列表作为 existing，下一页同人再返回同一 raw job。
- 根因：canonical job 与显示文本复用同一字段，二次合并形成“导演/Director”再翻为“导演/导演”。
- 用户影响：未来启用 crew 分页后重复职位。
- 当前边界：没有非空 existing 生产调用者。
- 最小方向：不用则删除增量语义；启用则 canonical/display 分离。
- 独立复核：verify_s006 确认条件性 P3；当前无非空 existing 生产调用者，修复时可优先删除未用增量语义。
- 修复状态：采用“翻译后显示边界去重”而非删除增量语义 —— `translateJobs` 对**翻译结果**去重，使「已翻译 existing + 原始 key」回灌后收敛回单一显示名。该选型保留 `mergeCrew(existing:newBatch:)` 的 Loadmore 增量 API 形状（未来 crew 分页仍可用），同时不需要把 `job` 拆成 canonical/display 两个字段。复核确认 `mergeCrew` 的非空 existing 调用者仍为空，故本修复对当前生产路径是行为中性的。
- 验证：`testMergeCrewIsIdempotentOverItsOwnOutput` 断言 `processCrew` 结果回灌同一原始 key 后 `job` 仍为「导演」；`testMergeCrewKeepsExistingPositionStable` 断言已翻译结果回灌不改变既有人员顺序与职位文本。临时还原后两例均失败（分别得「导演/导演」与「制片人/制片人」），确认修复必要。
- 处置状态：用户逐条过 P3 时经说明“当前无调用者、属潜伏 API 缺陷”后，批准随“组一”一并修复，未删除增量语义。

### F-054：Handler 丢弃 Bangumi 精确订阅 ID

- 状态：已修复（`58c7e81`）
- 严重度：条件性 P1
- 位置：SubscriptionHandler lookup/取消，对照 MediaDetailViewModel 正确分支
- 触发路径：Bangumi-only 电影已有订阅，lookup 返回 bangumi mediaId 与精确 subscription id，无 TMDB fallback。
- 根因：Handler 只保留 mediaId，始终媒体级删除；没有拒绝 bangumi 并回退 DELETE /subscribe/{id}。
- 用户影响：已知精确owner仍被降为集合式媒体删除；Bangumi-only可稳定漏删，异常legacy碰撞时还可能命中非目标记录。
- 证据：正式清单与 Header 测试已有正确 fallback，Handler 测试缺 Bangumi-only。
- 最小方向：共享“媒体级目标或精确订阅 ID”解析，不在各入口复制来源判断。
- 既有独立复核：review_m001_f 独立确认 `Subscribe`/lookup 保留精确 ID、Handler 丢弃它并始终走媒体级删除，而 Header 已有 Bangumi→订阅 ID 回退；当时按稳定漏删评P2。
- G02 clean-room 末裁：当前后端media删除无Bangumi专门分支，而精确ID DELETE已可用；因客户端主动丢失owner并改发集合式mutation，升级条件性P1。最小修复是lookup命中后直接DELETE精确ID。
- 当前实现复核：`58c7e81`已让共享模型和导航链保留身份，但 `fetchSubscriptionLookup` 的局部响应 DTO 仍曾漏掉 canonical/AniList 字段。2026-08-11 当前工作树补齐该投影，取消仍使用最后一次 lookup 的响应身份，并在成功后优先回写用户点击项缓存；原 Bangumi 路径和当前媒体级删除合同不改。待提交后再登记提交号。

### F-055：人物最佳结果使用 TMDB 专属头像准入

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/ViewModels/SearchViewModel.swift:279`（`calculateBestResults` 人物准入）、`MoviePilot-TV/Models/Models.swift:2286-2289`（`Person.hasUsableProfileImage`）
- 触发路径：Douban 等来源有最终可渲染 avatar，但 profile_path nil，且其他评分不足。
- 根因：准入读取 TMDB 专属 `profile_path`，卡片实际使用 source-aware `imageURLs.profile`。
- 用户影响：有头像的人物被排除出最佳结果，但仍出现在人物行。
- 最小方向：准入复用最终图片可用性判定。
- 独立复核：review_m001_g 独立确认人物搜索允许 Douban，现有 fixture 可形成有 avatar 但无 `profile_path` 的人物，而最佳结果与卡片使用不同图片准入；维持 P3。
- G07全局双审升级建议：两代理确认Douban有效avatar在当前生产搜索中会被本准入当作无图，低分时可被错误排除最佳结果；与F-051共享最终图片投影但用户出口/fixture独立，建议P2，交第三裁。
- G07第三裁：verify_a001_h确认Search绕过source-aware图片投影的静态反例，但当前Douban标题匹配通常会获得高分而绕过低分过滤，真实可见触发较弱；维持P3，与F-051共用`imageURLs.profile`事实来源但保持独立出口/fixture。
- 剩余未验证：Web 排名与真实跨来源人物分布。
- 修复状态：把准入判据从 TMDB 专属 `profile_path` 换成与 F-051 同一个 `Person.hasUsableProfileImage`。改动只影响准入布尔量，评分、热度加权、排序与来源混合判定均未触碰。按第三裁保留 P3 与原频率判断：真实触发需要「来源非 TMDB + 有可渲染头像 + `maxS < 50` + `pop < 1`」同时成立，豆瓣来源通常标题匹配分很高，实际很难撞上，本次修的是判据本身而非可见频率。
- 验证：`SearchViewModelTests.testBestResultsAdmitPersonWithSourceAwareAvatarButNoTMDBProfilePath` 走真实 `autoSearch()` 端到端路径（为此给既有 stub 增加 `setPersonResults(_:forQuery:)` 覆盖 `/media/search?type=person`），构造「查询词与人物名完全不匹配 + 热度不足」的最坏情形，断言有豆瓣头像的人物仍进入最佳结果。临时换回 `profile_path` 判据后该例失败，恢复后通过。
- 处置状态：用户逐条过 P3 时经解释触发链与影响面（并说明真实触发较弱）后，批准随“组三”一并修复。

### F-056：Hero 演员不滤空名且不补位

- 状态：已驳回
- 严重度：P3
- 位置：Person.name、MediaDetailViewModel Hero 演员、MediaDetailView join
- 触发路径：首四项包含 nil/空 name，后面有正常演员。
- 根因：只按数组非空，nil 渲染时丢弃、空字符串参与连接，分页完成后不补非空但不足列表。
- 用户影响：空“主演”或少于四人。
- 最小方向：按可展示非空姓名过滤/去重后截断，后续完整结果可补位。
- 独立复核：verify_m001_g_retry 从 `Person.name` 宽容模型、Hero 先截前四/只在全空时替换、View 仅 compactMap nil 不滤空串的完整链确认；维持 P3。
- G07全局双审升级建议：空名先占前四名额、后续有效演员不补位与F-050同一Hero取样顺序；两代理建议同升P2，Search最佳结果没有相同先截错误。是否升级交第三裁。
- G07第三裁：机制成立但与F-050共享同一过滤/去重后截断的修复与fixture，驳回重复编号并入F-050；不是假问题，严重度随根项维持P3。
- 剩余未验证：上游人物 name 是否强制非空及真实频率；V012-A 继续正常审查其他职责。

### F-057：季集范围终点丢失或未校验

- 状态：用户决定跳过
- 严重度：P3
- 位置：ParsedSeason 范围正则与排序字段
- 触发路径：`S01-S12`、倒序集范围等。
- 根因：捕获第二季但从不读取；集范围不校验/规范化上下界。
- 用户影响：资源筛选范围项不按实际覆盖的最新季/集排序。
- 最小方向：明确范围语法并解析/校验终点，invalid 单独排序。
- 独立复核：verify_s003_resume 确认正则已捕获结束季但初始化器未消费，且集范围使用结束集、季范围忽略结束季的内部意图不一致；维持 P3。
- 剩余未验证：真实格式与倒序合法性。
- 处置状态：用户逐条过 P3 时听完触发链与影响面后决定跳过。理由：只影响「季」筛选下拉的**选项位置**，点击筛选本身按原始字符串精确匹配（`TorrentsResultView.contextMatches`）仍正确；唯一的消费者就是该下拉的排序（`TorrentsResultView.swift:180`），全仓无第二处调用；审计本身也从未验证上游真会产出 `S01-S12` 这类范围格式。另经比对 Web v2.15.6（`~/code/MoviePilot-Frontend`，`useTorrentFilter.ts:109`），正则逐字相同、同样捕获第二季号却从不读取，「跟 Web 对齐」即维持现状，TV 侧修复反而是与 Web 分叉。

### F-058：卡片与筛选排序季集语法不一致

- 状态：用户决定跳过
- 严重度：P3
- 位置：ParsedSeason 正则，对照 Formatters.formattedSeasonEpisode
- 触发路径：E02、E01-E05、S01E01-10、S01-02。
- 根因：卡片支持无季号/省略第二标记，ParsedSeason 强制 S 开头且范围重复标记。
- 用户影响：能正确显示的值在筛选器落入无效零值组，顺序受 Set 迭代影响。
- 最小方向：两处共享一个明确语法/解析结果，不重复维护不一致正则。
- 独立复核：verify_s003_resume 从同一 `MetaInfo.season_episode` 的卡片显示与筛选排序链独立确认两套语法矛盾；维持 P3。
- 剩余未验证：上游是否产生这些格式。
- 处置状态：用户决定跳过。两套语法确实同时存在（卡片 `Formatters.formattedSeasonEpisode` 认 `E01-E05` / `S01-02 E03-04`，`ParsedSeason` 强制 `S` 开头且范围须重复 `E`/`S` 标记），但出口仍只是筛选下拉的排序位置：落进无效组的选项照样能选中并正确筛选，受影响的仅是该组内部顺序，而该顺序的不稳定源（TV 用 Swift `Set` 收集选项、每次进程哈希种子不同）也只在「本来就无意义的组内」可见。Web 侧没有这个问题（`TorrentCard.vue:177` 直接渲染原始 `season_episode`，不存在第二套正则），因此“对齐 Web”只能靠删掉卡片美化实现，属显示退化，用户决定不对齐、不修。

### F-059：无效/溢出输入折叠为合法零值

- 状态：部分修复
- 严重度：P3
- 位置：ParsedSeason 初始化与比较
- 触发路径：`无`、超大季/集数、空白/附加文本等。
- 根因：无解析成功标志；失败字段继续为 0，集转换失败还会被当整季。
- 用户影响：畸形值与合法 S00E00 混组或排到具体集前。
- 最小方向：显式 invalid 状态与稳定末尾排序，区分“没有 E”和“E 解析失败”。
- 独立复核：verify_s003_resume 确认正则匹配与各次 `Int` 转换未形成原子成功条件，合法 S00/E00、invalid 与溢出共享零值；维持 P3。
- 剩余未验证：真实畸形输入频率。
- 修复状态：只收紧三条同源 finding 中唯一的**归类错误**——初始化器的 `else` 分支把「没有 E 标记」与「有 E 标记但集号解析失败」合并处理，后者（如 `S01E99999999999999999999`，正则匹配成功但 `Int(_:)` 溢出返回 nil）会被标成 `isWholeSeason = true`，使一个具体集冒充整季混进整季组。改为先记录 `hasEpisodeMarker`，整季当且仅当**压根没有 E 标记**；畸形输入与「无」一样留在全 0 的无效组，既有排序位置不变。无解析成功标志、零值多义性等排序侧影响与 F-057/F-058 一并跳过。
- 附带发现：Web 用 JS `parseInt`，超长数字会算出一个巨大浮点数而非解析失败，因此不产生「整季」误标，该形态为 TV 独有（F-057 的同源正则在 Web 上就存在，本条不是）。
- 验证：新增 `ParsedSeasonTests`（9 例）——`testOverflowEpisodeIsNotClassifiedAsWholeSeason` 断言 `isWholeSeason == false`，`testOverflowEpisodeIsSortedAfterRealEpisodes` 断言畸形项排在真实集号之后；其余 7 例为阴性对照（`S01`/`S12` 仍为整季、正常集号与集范围排序不变、整季组仍整体靠前、「无」与空输入行为不变、单选项/空数组原样返回）。反向验证把该行还原为 `isWholeSeason = true`：2 失败 / 7 通过，失败的正是两条阳性断言，7 条阴性对照全部通过；随后恢复并复跑 9/9。
- 处置状态：用户听完三条同源 finding 的触发链与影响面后，指示「修那一行，其他跳过」。

### F-060：直接 `print` 绕过 Debug-only Logger

- 状态：已修复
- 严重度：P3；由候选 P2 降级
- 位置：`Logger.swift:22-43,92-102`、APIService/CustomFilter/Home 等 15 个直接 `print` 文件
- 触发路径：Release 构建的鉴权、资源过滤、媒体服务器跳转或错误路径。
- 根因：默认 Logger 按设计只在 Debug 输出，但 80 个直接 `print` 绕过统一入口并在 Release 保留；无 bootstrap 本身不构成缺陷。
- 用户影响：Release 控制台可出现用户名、种子/媒体标题、过滤规则、服务器名、下载器 hash/client、媒体 ID、搜索词、后端消息和原始媒体服务器 URL；CustomFilter 逐条同步输出还有卡顿风险。
- 证据：生产端共 35 个 Logger 调用与 15 个文件的 80 个直接 `print`；Release 设置无 `DEBUG`，发布工作流使用 Release；未发现直接输出 password、Bearer/access token、Authorization 或请求体。
- 最小方向：复用现有 Logger 替换或删除直接 `print`，URL/error 复用现有 query 脱敏边界，并增加最小生产源码禁用 `print` 检查；不新增日志框架。
- 独立复核：verify_s001_resume 独立复算全部调用点、App 启动、Release 设置、发布工作流与敏感值边界；核心成立，但无凭据泄漏证据，正式降级为 P3。
- V015 传播：review_a001_j 在 ResourceResult/CustomFilter 链直接确认五处 `print` 及逐资源标题日志；不改变既有 P3 和真实留存未验证边界。
- V019 传播：StatusViewModel统一catch仍直接`print`错误与取消；错误呈现缺失另归F-126。
- V020 传播：目标文件有8个直接`print`，只直接输出服务端message或error，未直接插值client/hash；错误文本自身是否携带这些值未验证。用户反馈缺失归F-093，Release日志治理仍归本项。
- W020-A传播：system info、sites与rules失败/取消仍直接`print`，同时缺少用户恢复状态归F-126；两代理确认只扩展既有Release日志治理，不升级P3。
- 剩余未验证：真机 Release stdout 的可见性/留存/性能，真实错误或媒体链接是否带秘密值；若证实凭据泄漏再升级。
- 修复状态：按“最小方向”把生产端**全部**直接 `print` 改为统一 `Logger.*` 入口，不新增日志框架。实测调用点为 **67 处、散在 16 个文件**（审计原记 80 处/15 文件，差异为计数口径：本次逐点提取并配平括号，排除了 `hasSameMutationFingerprint(` 这类子串误命中与 `Logger.swift` 自身被 `#if DEBUG` 门控的那个 `print`）。分级按原文本语义落位：错误/失败路径 → `Logger.error`，Keychain 清理失败与选中规则失效 → `Logger.warning`，加载成功计数 → `Logger.info`，取消路径与 CustomFilter 逐资源追踪 → `Logger.debug`；与级别重复的前导 emoji（❌/✅/⚠️/ℹ️/🔍）和 `DEBUG: ` 前缀一并去掉，改由 Logger 的级别前缀表达。
- 配套改动：`Logger` / `LogHandler` / `PrintLogHandler` / `Logger.Level` 显式标注 `nonisolated`，`handler` 标注 `nonisolated(unsafe)`。原因是本 target 设置了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，默认隔离下这些静态方法只能在 MainActor 调用，而 `HomeViewModel:129`、`MediaDetailViewModel:423` 等调用点位于 `nonisolated` 的 Task 闭包内，直接替换会编译失败；日志属横切关注点，本就应当可从任意隔离域调用。`bootstrap` 全仓无调用方，`handler` 只有默认值这一个实际写入点。
- 验证：新增 `NoDirectPrintInProductionTests`（源码级守卫）——经 `#filePath` 上溯定位仓库根后遍历 `MoviePilot-TV/**.swift`，用一个状态机把字符串字面量（含三引号多行串与 `#"..."#` 原始串）、`//` 行注释、`/* */` 块注释（支持嵌套）挖空后，按 `(?<![\w.])print\s*\(` 匹配，按文件名豁免 `Logger.swift`；定位失败时 `XCTSkip` 而非误报。**双向验证**：临时投放探针文件（同时含真实调用、注释里的调用、字符串里的 `print(` 文本、`fingerprintCheck(` 调用），守卫精确报出唯一真实调用所在行、对其余三种一律不报；探针已删除。
- 影响面说明：因 `PrintLogHandler` 整体位于 `#if DEBUG` 内，本次替换后这 67 处在 **Release 构建中完全不再执行**（闭包也不会被求值），即 Release 侧无任何输出或留存 —— 这是审计认可的设计取向（“无 bootstrap 本身不构成缺陷”），代价是 TestFlight/Release 构建也拿不到这些诊断信息；若日后需要 Release 可观测性，应改 `LogHandler` 实现（如 `os.Logger`）而非恢复 `print`。

### F-061：软过滤置尾被结果页二次排序破坏

- 状态：已修复
- 严重度：P2；由 P3 升级
- 位置：`MoviePilot-TV/Services/CustomFilterService.swift:24-67`、`MoviePilot-TV/Views/Components/TorrentsResultView.swift:248-291`
- 触发路径：软过滤未命中项的 `pri_order` 或当前排序值高于命中项；即使用户未改排序，结果页首次出现也会重排。
- 根因：服务先按“命中 + 未命中”置尾，结果页默认和后续排序均无条件重排整个数组，比较器忽略 `isFilteredOut`。
- 用户影响：本应置尾的灰色资源可重新出现在顶部，软过滤只剩视觉标记。
- 主审证据：verify_s003_resume 在 S003 独立复核中闭合 Resource/Search 两条入口；现有测试只覆盖硬过滤、权限和生命周期。
- 跨端结论：纯 TV 内部排序契约冲突。
- 最小方向：在结果页排序中先按 `isFilteredOut` 分区，再应用用户选择的排序键；最终产品语义由 G05 单元复核。
- 独立复核：review_m001_k_retry 确认 SystemView 文案明确承诺软过滤未命中项置尾，且首次默认排序已经破坏该承诺；维持 P3。
- S005 复核：review_a001_j 确认 System 文案没有为显式排序保留例外，默认和用户排序都必须维持软过滤分区；后续 C018/I011 只补实现与回归覆盖。
- V015 生产补强：CustomFilter 先发布命中/未命中分区，结果页随后立即对全数组重排；默认排序和用户排序均可重新把灰置项推到顶部。
- I011集成补强：review_a001_h完整复核确认默认排序还会覆盖后端已按TorrentsPriority/站点/上传量/做种数/季集生成的输入顺序，且任一显式排序都可能让高值软过滤项回到顶部；建议升P2。既有双审维持P3，故严重度须由不同代理裁决，机制与最小分区修复无争议。
- 第三裁决：review_a001_j确认结果页每次初始展示都会按TV默认键重排，所有显式排序也都绕过软过滤分区；这不是只在用户改排序后出现的轻微顺序偏差，而是稳定破坏设置页承诺的资源优先策略，故由P3升级P2。
- 修复：结果页先对所有站点资源按 `isFilteredOut` 做全局分区；默认保留后端顺序，显式排序分别在正常与软过滤分区内执行。
- 验证：补充默认顺序与显式大小排序回归；依赖解析、tvOS Simulator Debug完整构建和串行全量测试均通过。

### F-062：Keychain 删除失败后旧会话可在重启复活

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1；G06 由 P2 升级
- 位置：`MoviePilot-TV/Services/KeychainHelper.swift:87-100`；`MoviePilot-TV/Services/APIService.swift:386-405,546-557,584-607,630-635`
- 触发路径：已有持久 access token 的登出或 no-access 清理中，`SecItemDelete` 返回 success/not-found 之外的状态且旧 token 仍可读；UI 仍完成登出，随后进程重启。
- 根因：APIService 明知 access token 删除失败仍清内存、移除 fallback、发送 `.sessionDidLogout`，把“持久登出成功”作为既成事实；启动固定优先读取仍存在的 Keychain token。
- 用户影响：登出看似成功，但旧账号/token 可在重启后复活；用户名与密码也可能继续残留。
- 主审证据：删除失败不会移除 Keychain 项，所有清理路径忽略失败，初始化优先 Keychain；token-only 启动链可经 `/user/current` 恢复账号，现有测试仅覆盖成功删除。
- 跨端结论：纯 TV 本地会话安全缺陷，不依赖上游；真实 SecItem 失败频率未验证。
- 最小方向：持久化一个优先于 Keychain 恢复的明确登出状态，或在 access token 删除失败时进入可见失败/重试状态；不得继续宣布持久登出完成。
- 独立复核：verify_s002_fresh 确认 P2，并收窄为 access token 未清除才会复活会话；仅 currentUser/username/password 残留通常只是凭据残留。
- G06联合裁决：rounda_g01_recheck与rounda_g02_third均确认access token删除失败后，UI仍宣布登出而启动优先从Keychain恢复旧token；这是用户明确撤销会话后旧身份复活的安全边界，升条件性P1。最小面是在失败时写入高于Keychain恢复的logout tombstone/session revision并重试删除，不要求新凭据架构。
- 剩余未验证：真实 Security 失败频率，以及提示失败、后台重试或持久 tombstone 的最终产品交互。

### F-063：Keychain/UserDefaults 无明确权威导致旧或混合会话恢复

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1；G06 由 P2 升级
- 位置：`MoviePilot-TV/Services/KeychainHelper.swift:8-84`；`MoviePilot-TV/Services/APIService.swift:382-405,471-617,1030-1061`；`MoviePilot-TV/ViewModels/SystemViewModel.swift:145-252`
- 触发路径：Keychain 已有账号 A，登录账号 B 时一个或多个更新失败；B 写入 UserDefaults fallback，但旧 Keychain 项仍保留。
- 根因：四项会话凭据逐项提交，fallback 没有当前权威标记；Keychain 成功时不清旧 fallback，失败时旧 Keychain 又继续优先，`read` 还把 not-found 与临时 Security 错误都折叠为 nil。
- 用户影响：重启后回到旧账号、自动登录使用混合用户名/密码、旧权限快照覆盖新会话，并可能跨账号或跨服务器。
- 主审证据：`save` 失败保留旧值，四次写入没有整体结果；历史曾有可控失败替身，随恢复已接受 fallback 的决策一并删除；现有测试未覆盖全失败或单项分裂。
- 跨端结论：纯 TV 本地持久化一致性缺陷，不依赖上游。
- 最小方向：保留已接受的 fallback，但明确其权威性：Keychain 成功时清除对应 fallback，失败写入 fallback 后读取必须选择新值；四项会话仍需一致代际。
- 独立复核：verify_s002_fresh 独立确认反向陈旧 fallback、临时读取错误回退旧值及设置页只看 token 的误标，维持 P2；本发现不重复质疑明文 fallback 产品取舍。
- G06联合裁决：两名代理均重新闭合四项独立`Keychain ?? UserDefaults`读取可组合不同代际的token、currentUser/permissions与credentials；在线`/user/current`通常会修复，但离线/失败窗口可把A身份与B权限/凭据混成一个会话，故升条件性P1。最小面给现有四项复用同一session owner/revision，只接受同代记录。
- 剩余未验证：进程中断在四项写入之间的真实表现、Security 失败频率、离线窗口与设置页最终文案。

### F-064：混合类型头像对象可拖垮人物或媒体数组

- 状态：已修复（`af67839`）
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift:2323-2337`，传播点 `2195` 及人物/媒体数组解码入口。
- 触发路径：可选 `avatar` 对象同时含有效 URL 与数值/null 元数据，如 `{"normal":"…","width":100}`；或 `normal` 为空但 `large` 有效。
- 根因：`PersonAvatar` 将整个对象解为同质 `[String:String]`，任一非字符串值令对象失败；随后用原始字符串 `??` 选择 URL，空白首选会遮蔽有效后备值。
- 用户影响：单个可选头像对象可令人物搜索、演员页、人物详情或含人员的媒体/资源批次整体失败；资源 SSE 可终止并在同步 fallback 再次失败；空首选会退化为占位图。
- 主审证据：`Person.init` 不降级 avatar 解码错误，`[Person]`/`MediaInfoJSON` 为原子解码链；现有测试仅覆盖全字符串对象，相邻 `images` fixture 已出现数值 width/height。
- 跨端结论：TV 解码链可静态确认；当前后端 schema 已确认 avatar 允许 string/dict。
- 最小方向：在 `PersonAvatar` 模型边界逐个解码已知 URL 键、忽略无关值并选择首个 trim 后非空字符串；无可用 URL 时将可选头像降级为 nil。
- 独立复核：verify_m001_g_retry 确认 `decodeIfPresent(PersonAvatar.self)` 会传播非 null 类型错误至 Person/MediaInfo/Context 原子数组，并确认空 `normal` 遮蔽后备 URL；维持条件性 P2。
- 剩余未验证：真实混合/脏头像数据频率；A001-I/V013/各 View 后续只核对错误呈现和回归覆盖。
- 修复状态：已完成（`af67839`）；复用 `JSONValue` 只提取已知非空 URL，混合元数据与无可用头像均有回归；独立复审通过，Simulator clean build 与本地测试 430/430 通过（跳过5个真实后端兼容套件）。

### F-065：分季与剧集组缓存未按 session 隔离

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1
- 位置：`MoviePilot-TV/Services/APIService.swift:372-468,428-430,2007-2047`
- 触发路径：服务器/账号 A 拉取剧集组或分季后切换到 B，在缓存有效期内请求相同 TMDB/group ID；或 A 的旧请求在切换后返回。
- 根因：`episodeGroupsCache`、`mediaSeasonsCache`、`groupSeasonsCache` 的 key 只有相对 endpoint/group ID，不含发起时 session/baseURL，也不在会话变化时清理或做 generation 校验。
- 用户影响：B 会话可显示 A 的剧集组/分季，并保存新服务器不存在或语义不同的 `episode_group`。
- 主审证据：baseURL/token/currentUser 变化只失效订阅状态缓存，全仓无三类缓存清理；旧 in-flight 结果仍写相同 key，默认读缓存还会续期。
- 跨端结论：TV 本地缓存缺陷可静态闭合；不同服务器是否总返回相同数据未验证。
- 最小方向：用发起时不可变 session namespace 组成缓存 key，使旧请求只能回填旧 namespace；账号维度由 A001/I003 复核。
- 独立复核：verify_m001_f_retry 确认页面 session guard 不能阻止 API 先污染共享 cache，且仅在切换时 clear 也挡不住旧 in-flight 回填；当时按缓存展示评P2。
- V017 生产补强：分季页直接消费episodeGroups/mediaSeasons/groupSeasons三类endpoint-only缓存；页面快照不能阻止API在返回时先污染共享key，旧请求回填边界继续归CHK-007。
- V018 生产补强：订阅编辑页的 session guard 位于 API 返回之后，同样只能阻止 VM 发布，不能阻止共享剧集组缓存先被旧会话结果写入。
- V021 传播：手动整理的剧集组加载复用同一endpoint-only API cache，本地query key也不含session；旧请求写共享缓存与当前表单发布须一并纳入CHK-007。
- I003集成与定向复核：verify_a001_h与review_a001_h独立确认三缓存全程只有endpoint key、会话变化没有clear/generation，且命中会续期TTL；当前后端响应受服务器版本/插件/识别环境影响。最小key至少包含发起时baseURL/epoch，store前拒绝旧owner。
- I014定向闭合：SubscribeSeasonViewModel恰好消费episodeGroups/mediaSeasons/groupSeasons三条API且无第二层分季结果cache，页面发布guard挡不住API先写共享key，全部归本项。MediaPreloader完整task cache虽也只按MediaInfo.id寻址，但当前logout通知会clearAll且未找到无logout换session的生产路径；不并入F-065/F-020，也不另建finding，未来出现绕过清理的切服/换号入口再重开。
- G02 clean-room 末裁：旧服务器请求可在新baseURL/user下回填同键，随后进入剧集组选择和订阅payload；后果从跨会话展示扩大到错误远端订阅，升级条件性P1。复用现有session generation清理并在store前拒绝旧owner，不建新缓存层。
- 剩余未验证：认证维度是否影响响应、不同服务器/账号真实数据差异。

### F-066：辅助或非正 raw TMDB ID 被当作主身份加载剧集组

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift:154-161`；对照 `Models.swift:1965-1975`
- 触发路径：主身份为 AniList、Douban 或插件但带辅助 `tmdbid`，或快照为非正 `tmdbid + 有效 mediaid`，用户打开订阅编辑页。
- 根因：编辑页只用 `type == "电视剧" && tmdbid != nil` 放行，没有复用 `Subscribe.identity`，也不过滤 0/负数。
- 用户影响：请求辅助媒体或 `/media/groups/0`，展示并可能保存不属于主订阅身份的剧集组；失败还可阻断编辑页。
- 主审证据：正式清单和分季 ViewModel 均要求主身份 TMDB 且有效 raw ID，并已有拒绝辅助 TMDB 的测试；编辑页无对应测试。
- 跨端结论：TV 内部主身份契约不一致；真实字段组合未验证。
- 最小方向：复用统一身份判定，仅在主身份为 TMDB 且 raw TMDB ID 有效时加载。
- 独立复核：verify_m001_f_retry 确认编辑页与分季页主身份 gate 分裂，且影响既有订阅与新建准备两条路径；维持 P2。
- 范围补充：verify_a001_h 对照 A001-J API 与 `ReorganizeViewModel` 的 `> 0` 正确 gate，确认负数也能穿过订阅编辑页并发起剧集组请求。
- V017 边界补充：分季页正确拒绝AniList辅助TMDB与0，但使用truthy数值判定，负TMDB ID仍可请求`/media/groups/-1`；维持F-066正ID要求，不新增分季专用finding。
- V018 生产复核：编辑页唯一 gate 仍是 `tmdbid != nil`，未验证主身份且未要求正数；辅助 TMDB、0 与负数均沿同一路径进入剧集组请求。
- 剩余未验证：真实混合字段分布；V018/W014 仍需回溯测试入口。
- 当前跨端复核：Web编辑页明确跳过非TMDB主来源的辅助TMDB ID并有AniList回归；后端`/media/groups/{tmdbid}`只按TMDB电视剧识别，无法替客户端判断主来源。
- 修复：复用`Subscribe.identity`并要求正数raw TMDB ID；旧订阅未记录`media_source`时仍按合法TMDB ID加载。
- 验证：补充AniList辅助TMDB不请求、旧TMDB无来源仍请求、0/负数不请求三组回归；依赖解析、tvOS Simulator Debug完整构建和串行全量测试均通过。

### F-067：可选剧集组失败阻断整个订阅编辑页

- 状态：已确认（用户决定跳过）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift:135-167`、`MoviePilot-TV/Views/Sheets/SubscribeSheet.swift:297-303`
- 触发路径：站点、下载器和目录已成功，但可选剧集组请求失败。
- 根因：剧集组请求位于核心配置加载总 `do/catch` 内；任一失败都会清空全部选项并设置错误，保存按钮因此禁用。
- 用户影响：无法编辑与剧集组无关的站点、质量、路径等配置。
- 主审证据：分季页已有“剧集组失败不阻断主分季数据”测试；订阅编辑测试未覆盖可选剧集组失败。
- 跨端结论：虽然可选剧集组失败会阻断编辑，但订阅配置当前按整体原子加载处理。
- 最小方向 / 裁决：不拆分加载失败域，维持整体失败与重试；用户决定跳过。
- 独立复核：verify_m001_f_retry 确认核心配置成功后仍会因可选组失败被清空并禁用保存；用户确认订阅配置保持整体原子加载，决定跳过。
- V018 生产复核：核心配置与可选剧集组仍处于同一 `do/catch`，任一可选组错误都会把已经成功取得的站点、下载器和目录选项一起清空。
- G02全局裁决：verify_a001_h与rounda_g02_third均确认当前HEAD仍把可选filter/group与核心options置于同一失败域，稳定令无关配置也不可编辑；双票升级P2。经用户确认订阅配置保持整体原子加载，不拆分失败域。
- 处置：不做 TV 单端错误隔离增强；后续若产品明确要求部分可编辑，再另行评估。

### F-068：nil/0/重复业务 ID 可进入订阅快照

- 状态：已确认（用户决定跳过）
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift:1683-1689,1790-1793`、Home 快照/动作链及 BackendCompatibility 巡检。
- 触发路径：`GET /subscribe/` 返回缺失/null、0、负数或重复 `id` 的记录。
- 根因：`Subscribe.id` 允许 nil 并直接充当 `Identifiable.ID`；快照入口不校验唯一正业务 ID，兼容巡检遇 nil 又直接跳过。
- 用户影响：SwiftUI 身份/焦点冲突，编辑、保存、搜索、暂停、重置和删除会因缺 ID 静默失败。
- 主审证据：Home 直接 `ForEach(items)`，动作全部 guard ID；现有焦点测试只确认 nil 映射，巡检无法发现缺 ID schema 回归。
- 跨端结论：Web 同样直接依赖后端正数唯一主键；正常官方后端不触发此异常数据路径。
- 最小方向 / 裁决：不做 TV 单端异常数据兜底；用户决定跳过。
- 独立复核：verify_m001_f_retry 确认 nil/重复会破坏 SwiftUI 身份，0/负数仍可进入部分动作路径；因 Web 同样依赖后端 ID 合同，用户决定跳过。
- V017 生产补强：nil ID被分季摘要跳过，但0/负数与重复ID仍可被当作有效订阅/取消状态；本View以season作UI key，不直接增加重复SwiftUI ID，范围据此收窄。
- V018 生产补强：创建 POST 返回0/负数仍会继续 pause/fetch；随后详情响应又可用 nil、非正或不匹配 ID 覆盖本地草稿，保存/取消 owner 因而失去可靠业务键。
- 处置：不做 TV 单端异常数据兜底；后续若发现官方后端实际返回异常 ID，再重新评估。

### F-069：完整 PUT 可能清掉未知订阅字段

- 状态：降级；转入 CHK-003 后续兼容检查
- 严重度：P3（仅未来版本条件）
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `Subscribe.CodingKeys`、`MoviePilot-TV/Services/APIService.swift` 的完整订阅更新，以及目标 v2.15.1 后端公共写入 schema。
- 触发路径：仅当未来后端新增 TV 尚未建模的公共可写订阅字段，用户再用 TV 修改另一字段并完整 PUT 时成立。
- 根因：TV 使用封闭强类型模型；Web 会把 GET 得到的动态表单对象完整 PUT 回去。两端只有在上游 schema 新增字段而 TV 尚未同步时才产生保真差异。
- 用户影响：目标 v2.15.1 当前没有缺失字段反例；未来版本若先增加公共可写字段，TV 的无关编辑才可能把该字段折叠为默认值或丢失。
- 当前复核证据：逐字段核对 TV 模型、目标 v2.15.1 后端公共可写字段和 Web 编辑请求，TV 已覆盖当前全部公共可写字段；F-199 的 `total_episode=nil` 现成持久破坏已由 `ce7afcc` 单独修复。
- 跨端结论：不再作为当前缺陷或 P1；保留为官方 Web/后端升级时的条件性兼容风险。
- 处置方向：不改产品代码。由 CHK-003 约束每次上游升级逐字段核对；发现新增可写字段时，再选择同步建模、按正式 round-trip 合同保留原值，或在适配前阻止不安全保存。
- 既有独立复核：verify_m001_f_retry 已确认静态表示丢失，但当时因上游契约缺失暂列未验证P3。
- G02 clean-room 历史裁决：曾以F-199的现成反例将总根升级为条件性P1；当前复核已把F-199已修复的已知字段问题与未来unknown字段风险拆开，覆盖该旧当前态。

### F-070：未知 AI 能力被当作已启用

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Models/Models.swift:2394,2408-2412`；`MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:24-25,461-488`；`MoviePilot-TV/Views/Pages/TransferHistoryView.swift:243-269`
- 触发路径：settings 未加载、用户设置端点 404/403，或合法响应省略 `AI_AGENT_ENABLE`。
- 根因：可选能力标志用 `!= false` 判断，nil/未知被当成已启用。
- 用户影响：显示并允许执行后端未声明可用的 AI 整理，最终才提示启动失败。
- 主审证据：设置端点测试明确允许 `AI_AGENT_ENABLE == nil`，真实后端副作用 gate 却以 `?? false` 把 nil 判禁用；ViewModel 测试只覆盖 true。
- 跨端结论：当前 Web 与后端均只在显式 `true` 时开放 AI 能力。
- 修复：`isAiRedoEnabled` 改为 `== true`，设置或字段未知时不再显示 AI 整理入口。
- 独立复核：verify_m001_h 确认 nil 在现有端点测试中合法可达，但 `!= false` 自功能引入即存在，无法排除旧后端乐观兼容意图，故改为未验证 P3。
- G09交叉裁决：rounda_g03_recheck 与 rounda_g01_recheck 分别从当前后端禁用分支、Web `Boolean(undefined)` 与TV生产入口重新取证，均确认nil/加载失败时TV错误开放能力；旧后端乐观兼容假设被当前本地跨端合同覆盖，升为确认P2。
- 验证：覆盖整个 settings 缺失、字段缺失、字段 null、false、true；定向 XCTest 与完整工程验证通过。

### F-071：搜索后 owner 与 fetcher 形成强引用环

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：`MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:35,54-63,107-129`
- 触发路径：用户首次提交转移历史标题搜索。
- 根因：owner 强持有 `fetcher`，搜索写入的 escaping closure 又通过 `self.pageSize` 强持有 owner；初始化路径已用局部 pageSize 避免捕获。
- 用户影响：退出状态页或登出后 ViewModel、历史列表及关联对象不能释放。
- 主审证据：静态 `self → fetcher → self` 强引用环闭合，现有测试无 weak/deinit 断言。
- 跨端结论：纯 TV 生命周期缺陷。
- 最小方向：与初始化路径相同，在闭包外复制 pageSize，不引入新抽象。
- 独立复核：verify_m001_h 确认搜索 closure 强捕获 `self.pageSize`，Paginator 与 Combine 的弱捕获均不能打断 owner→fetcher→owner 环；维持 P3。
- V022-A 生产复核：任意首次搜索（包括纯空白规范化为nil）都会安装读取`self.pageSize`的新fetcher闭包；初始化路径已用局部pageSize展示最小正确做法。
- I009集成升级建议：review_a001_j确认首次搜索请求完成后`self → fetcher → self`仍永久存在，退出状态页/登出不会释放且每次重进搜索可再泄漏整份历史列表；建议由P3升P2。不同代理须裁稳定用户资源后果；最小修复仍只是闭包外冻结局部`pageSize`。
- I009定向裁决：review_a001_h确认请求完成后闭包仍永久形成`self → fetcher → self`，每次重进并搜索可无界保留VM/Paginator/历史数组；轮询Task会停是反证，不阻止资源后果升P2。修复只需像初始化路径一样在闭包外冻结局部`pageSize`。
- 修复：搜索闭包与初始化路径保持一致，在闭包外冻结局部 `pageSize`，不再捕获 ViewModel。
- 验证：新增搜索完成后的 weak 释放回归；修复前用例失败、修复后通过，依赖解析、tvOS Simulator Debug完整构建和串行全量测试均通过。
- 相邻检查：全部 Paginator、闭包属性、Combine sink 与持有 Task 的 owner 未发现新的请求结束后永久自环；既有在途任务保活边界仍按 F-035/F-039 裁决。

### F-072：旧轮询结果可污染新查询或新会话

- 状态：已修复（`e388e8b`）
- 严重度：P1
- 位置：`MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:107-129,284-335`；`MoviePilot-TV/Views/Pages/TransferHistoryView.swift:39-45,108-119`
- 触发路径：十秒轮询请求挂起期间提交新搜索，或在两个仍有 manage 权限的会话/服务器间切换。
- 根因：`fetchLatest()` 无 query generation 或 session snapshot，也不被 `search(with:)` 取消；旧 fetcher 返回后直接写新 `prependedItems` 并按旧结果推进分页游标。
- 用户影响：当前搜索混入旧关键词/旧会话记录、分页跳页，用户还可能对错误记录执行删除或重新整理。
- 主审证据：MainActor 在网络 await 可交错；搜索替换 fetcher/Paginator 后旧轮询恢复没有 query/session/generation 校验。
- 跨端结论：纯 TV 状态归属缺陷。
- 最小方向：搜索/会话变更递增同一代际；轮询捕获 query 与 session，恢复后不一致则丢弃且不得调整游标。
- 独立复核：verify_m001_h 确认旧 page 1 恢复后可继续使用已替换的新 fetcher取后续页，混合写入新 prependedItems，并在累计满页时推进/重启新 Paginator 游标；维持 P2。
- V022-A 生产补强：普通search/refresh/loadMore与loadStorages同样无query/session owner；旧refresh defer可提前清新loading，A storage可发布到manage会话B，manage→restricted在storage await后仍会继续历史refresh，旧loadMore也可跨session发布。
- I009集成确认：review_a001_j补齐旧查询gated poll在新搜索完成后prepend旧结果、外部删除无法对账及session切换传播；query/session/list generation仍是单一最小owner，P2不变。SQLite同ID破坏性放大另在F-204裁。
- G04全局裁决：rounda_g03_recheck主审与rounda_g02_third独立复核均确认旧轮询恢复后会读取当前items、继续调用当前fetcher并推进当前Paginator游标；当前页面可混入旧query/旧session记录并继续暴露删除/整理动作，双票升级P1。最小面仍是单一query/session/generation/fetcher owner，不并入F-130的一般页面收敛。
- 整改状态：已修复（`e388e8b`）。搜索递增query generation；轮询固定启动时fetcher，并在每次网络恢复及发布前同时校验query/session代际。Simulator clean build、本地436/436测试与最终独立复审通过；五个真实后端兼容套件未运行。
- 剩余未验证：真机页面切换频率；V022-C继续核对轮询、游标和删除shift集成。

### F-073：手动整理预览嵌套响应缺失时失败开放

- 状态：已修复（`e8cdaf7`）
- 严重度：条件性 P2；G09由未验证P3转确认
- 位置：`MoviePilot-TV/Services/APIService.swift:1633-1651`、`Models.swift:2763-2796`、`ReorganizeViewModel.swift:202-265`、`ReorganizeSheet.swift:335-485`
- 精确成立矩阵：envelope `success:true`且`data`缺失/null时，API以`.empty`返回；ViewModel得到零项成功数据，Sheet因`previewData != nil`打开空预览。单条item的`success`缺失/null时，模型解为nil，统计与UI只把`== false`当失败，因此把该项计成成功并按成功样式呈现。
- 明确反证：envelope `success`缺失/null/false均被`response.success == true`守卫失败关闭；`data:{}`因`summary/items`必填而解码失败；item `success:false`会生成失败项。旧命题不得再把这些分支写成fail-open。
- 用户影响：兼容或畸形producer可把未知结果显示为“整理后”，或用0/0/0空预览掩盖响应不完整；不会在预览阶段直接执行文件mutation，故为条件性P2而非P1。
- 当前上游：正式后端`Response.success`必填，当前手动整理producer始终传结构化data与Bool item success；但通用data仍可空且无preview专属schema。Web同样对缺失data静默空预览、对item nil按成功计数，因此这是跨端共享协议边界，不是TV单端兼容差异。
- 现有测试：已覆盖合法完整响应、envelope缺success抛错与显式失败项；未覆盖`success:true + data`缺失/null、item success缺失/null及合法显式空数据。
- 裁决过程：G09主审条件确认P2；第一独立票只按envelope mandatory success驳回，未覆盖data/item两支；不合规第三票读过ledger，仅作补充。全新clean-room替代票逐矩阵独立确认两条fail-open且建议P2，故取两张有效确认票转确认P2。
- 最小方向：只在`previewManualTransfer`要求`data != nil`，并把`ManualTransferPreviewItem.success`收紧为必填Bool；合法`summary=0/items=[]`继续成功。不改通用`ApiResponse`，不建新响应框架。
- 合并边界：不并F-074请求代际、F-075逐ID受理或F-151投影去重；它属于读预览的嵌套响应合同，不是执行mutation acknowledgement，故不扩展CHK-017。
- 剩余未验证：用户实际部署是否有兼容producer返回缺失字段；未运行响应矩阵。

### F-074：旧预览可在表单或会话变化后回写

- 状态：用户决定跳过（2026-08-14）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/ReorganizeViewModel.swift:78-92,201-266`；`MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift:335-365`
- 触发路径：表单 A 预览挂起时修改路径、媒体 ID、季集配置或切换会话，旧请求随后返回。
- 根因：表单变化只清当前 previewData，不取消请求或绑定表单/session 代际；旧任务仍发布并自动打开 Sheet。
- 用户影响：展示的是 A 的目标，但“开始整理”提交当前表单 B，安全确认步骤失真并可能把文件放到未预览目的地。
- 主审证据：请求前形成值快照，await 后无 generation/session 校验，所有控件在预览期间仍可编辑；测试无延迟竞态。
- 跨端结论：当前Web同样没有表单generation，preview loading也未与transfer互斥；这是Web/TV共享的安全确认缺陷，不能只做TV差异化兜底，并支持F-027在G09的传播。
- 最小方向：动作起点冻结forms、session与revision；编辑、新预览、提交开始、dismiss或session切换递增revision/取消旧任务，每次await及发布/开Sheet前复核。复用现有Task/状态，不新增协调器。
- 独立复核：verify_m001_j 确认控件可编辑且旧请求无代际；批量逐条 await 还可在切服后把旧 history ID 发往新会话并合并两个会话结果；维持 P2。
- V021 生产复核：表单变化仍只清`previewData`，未取消或递增owner；旧preview返回后照常发布并自动打开Sheet。提交读取当前表单，故确认A/提交B的安全边界仍直接成立。
- W018-A独立复核：review_a001_j从表单编辑、preview请求代际与session重新闭合旧结果发布，确认P2；提交载荷在循环起点冻结不修复预览A→提交B的确认失真。
- W018-B传播：review_a001_h确认两个动作只受各自loading门禁；预览在途仍可提交，提交开始或成功关闭不会退休旧预览，迟到A仍可发布/尝试开Sheet。预览与提交静态都复用`preparedSubmissionForms()`，载荷字段没有稳定分裂，缺陷是时间与operation owner。
- W018-B独立复核：review_a001_j确认状态不变时预览/提交除`preview/background`外使用同一builder；但两者分别重新取表单，没有共享不可变intent/fingerprint。编辑、100ms派生更新、提交开始、关闭或session切换均不退休旧代际，维持P2；当前Web同样缺generation并允许预览中提交。
- 剩余未验证：需补受控延迟表单/session 回归。

### F-075：批量提交不保留逐 ID 受理状态

- 状态：已修复（仅误导文案；2026-08-14 用户裁决）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/ReorganizeViewModel.swift:154-199,344-355`；`MoviePilot-TV/Services/APIService.swift:1623-1630`
- 触发路径：批量整理前几条 background 请求成功受理，后续返回 false 或抛错。
- 根因：逐条提交不记录已受理/失败/未知 ID；异常 catch 会把前项成功后的批次描述为“整理没有开始”，失败后仍保留整批供无差别重试。
- 用户影响：用户会误以为没有任务启动并重试全部记录，已排队整理可能被重复提交。
- 主审证据：后台请求成功即开始任务；循环只累计失败文案，异常直接跳出；测试无 true→false/throw 部分成功序列。
- 跨端结论：TV 错误反馈缺陷已见；后端幂等性和重复后果未验证。
- 最小方向：保留逐 ID 已受理/失败结果，明确报告部分成功，避免重试已受理 ID。
- 独立复核：verify_m001_j 确认显式 false 无消息时会说“部分文件没有开始”而非总称全部未开始，但前项已受理状态始终丢失且全量重试仍成立；维持 P2。
- V021 生产复核：`preparedSubmissionForms`冻结值表单避免提交中编辑改payload，但逐ID true→false/throw仍不保存已受理集合，异常后整批可再次提交；冻结表单不修复部分受理根因。
- W018-A独立复核：review_a001_j确认成功→business false/transport throw仍丢已受理、失败与未发送ID，整批保留会让重试重复已受理项；维持P2并补逐ID receipt矩阵。
- I009集成确认：review_a001_j从生产submit再次构造81成功、82失败后重试为`81,82,81,82`；复用现有`logIds`仅保留失败/未发送项即可，维持P2，不新增批处理状态机。
- 剩余未验证：后端幂等/去重与重复文件操作后果。

### F-076：空关键词、失败或过时请求继续暴露旧媒体结果

- 状态：已修复（资源搜索入口；2026-08-14）
- 严重度：P2；原跨owner P1链已由统一session/generation门禁闭合
- 位置：`MoviePilot-TV/Views/Sheets/ManualMediaSearchSheet.swift:43-55,97-125`；`MoviePilot-TV/ViewModels/ReorganizeViewModel.swift:290-295`
- 触发路径：查询 A 成功后清空关键词、B 请求失败、A 请求挂起时把输入改为 B，或会话变化后旧请求返回。
- 根因：空输入和失败不清旧 items，提交时 query/session 无 generation，旧响应仍可发布；没有用户可见错误状态。
- 用户影响：A 的结果在 B 的上下文继续显示，选择后会把错误媒体 ID 写进整理表单。
- 主审证据：catch 只记录 Logger，items 仅成功时替换；测试只覆盖成功端点和选择辅助。
- 跨端结论：当前剩余为纯 TV 同一会话陈旧结果/错误状态缺陷；旧会话结果进入新账号并继续动作的原P1链已闭合。
- 最小方向：新查询接受时清理或标记旧结果，空关键词清列表，失败显示错误。
- 独立复核：verify_m001_j 确认上述四条路径；B 成功返回空数组会正常清空，故标题收窄为空关键词/失败/过时请求；维持 P3。
- V021 生产复核：手动搜索链仍在空输入、失败和旧请求返回时保留/发布旧items；成功空会正确清空，维持现有收窄标题和单一query/session owner方向。
- V011-C 同根扩展：Search 资源 fallback 的 catch 在 generation/session/cancel guard 前写 `resourceErrorMessage`，A 的取消/错误可污染 B；B 流与 fallback 双重失败又不清 A 的 `resourceResults`，非空旧结果会遮住 B 错误。与本项共享“新查询失败/过时结果仍暴露旧 items”的根因、最小修复与回归，不另编号。
- V011-C 单元复核：review_a001_j 独立重现 A 成功→B 流/fallback 双失败仍显示 A，以及 A fallback 被 B 取消却先污染 B 错误两条路径；确认复用 ResourceResultViewModel 现有 guard 顺序即可，不新建状态机。
- V015 同根扩展：新搜索、取消及 SSE+fallback 双失败均不清既有 `results`，已显示的 A 资源可继续冒充 B；过期 fallback error 在写入前已有 guard，故不把 V011-C 的“旧错误污染”窄路径扩大到本单元。
- V016 同根扩展：添加下载内嵌手动搜索也没有query generation或session/permission前后校验；空关键词、失败、切服或撤权可保留并发布旧结果，继续复用现有清理/代际边界。
- W006-B 结果层扩展：A已有最佳结果后启动B，若B期间session失效，最终`hasSearched=false`但`bestResults`未清；结果段会重新显示A最佳卡，并可与已先发布的B子Paginator items混合。主审与独立复核均确认复用同一query/session owner即可，不另建结果状态机。
- I012集成补强：verify_a001_h确认A资源结果成功后，B的stream与fallback均失败只写error、不清A；结果非空又遮蔽错误，B关键词下仍展示并可下载A。空输入还会在取消/代际递增前返回。其建议升P2；既有双审维持P3，交第三代理只裁严重度，修复仍是按规范query/type/generation原子管理结果与错误。
- 第三裁决：review_a001_j确认A成功后提交B，B的stream与fallback双失败会让A结果在B关键词下重新成为可聚焦、可执行下载的主内容；错误对象仍可触发远端动作，故由P3升级P2。
- G10独立传播：verify_a001_h确认ManualMediaSearch还把初始prompt、成功空和失败空折叠为同一文案，空白按钮仍enabled；A成功→B失败保留A及A慢/B快晚覆盖继续由本项query/session generation完整承载，P2不变。
- G01/G04升级裁决：rounda_g01_recheck与rounda_g02_third分别按正确编号确认Manual/Resource/Search在失败、取消或session失效时保留旧可操作结果；正常成功空会赋空数组，不在本项。旧A结果可在B关键词或新会话下继续触发下载/整理，双票将稳定跨owner动作影响升级P1；新attempt必须在权限早退前清结果/错误并绑定generation/session。
- 整改状态：手动媒体 ID 搜索子项已修复（`44908c4`）；按搜索先清空旧结果，关键词在请求期间变化时丢弃旧响应，空输入与失败均保持空态；Simulator clean build、本地437/437测试及独立复审通过，五个真实后端兼容套件未运行。聚合 Search/Resource 的失败、取消、session 与过时代际子项仍开放。
- 当前复核：统一session/generation门禁已经阻止旧账号结果发布到新账号；但`SearchViewModel.autoSearch()`在空查询时直接返回，资源搜索启动时不清`resourceResults`，fallback失败出口仍可保留旧结果或先写错误。剩余严重度按同一会话可见陈旧结果校准为P2。
- 剩余未验证：同一会话下空关键词、失败与延迟查询的完整交互回归。

### F-077：订阅分享投影丢失跨来源主身份

- 状态：已修复（`58c7e81`）
- 修复状态：已完成（`58c7e81`）
- 严重度：条件性 P2；由 P3 升级
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `SubscribeShare` 与 `toMediaInfo()`；Explore/Search分享分页和通用菜单入口。
- 触发路径：Bangumi-only、AniList-only、canonical-only或canonical与辅助raw冲突的分享转为MediaInfo，再进入详情、资源搜索、普通/分季订阅。
- 根因：当前Share schema已有`bangumiid/anilistid/media_source/media_id`；TV对Bangumi只漏投影，对后三项则模型与投影都缺。`toMediaInfo()`只保留TMDB/豆瓣，无法遵守Web的canonical→raw优先级。
- 用户影响：投影后详情可无身份或打开辅助TMDB而非声明主来源；资源/订阅动作继承错误身份。分享卡主点击Fork使用原Share对象，投影问题本身不影响该跳，但后三字段的Fork丢失另由F-079确认。
- 当前证据：后端91ce365f与Web 7ea14bc9均声明/使用这些字段；三路TV核查闭合Explore/Search→ContextMenu→详情/资源/订阅链，未发现第三个同根转换遗漏。
- 最小方向：补齐Share三个明确字段，并在`toMediaInfo()`按canonical→raw投影Bangumi/AniList/统一身份；不在各调用者补fallback，不新增mapper或raw框架。
- 测试：Bangumi-only、AniList-only、canonical与TMDB冲突、自定义canonical，以及现有`share:<raw_id>`稳定键不变。
- 剩余未验证：真实分享服务中单一来源/冲突记录的频率。

### F-078：缺失/0/重复分享业务 ID 可破坏稳定身份

- 状态：已修复
- 严重度：条件性 P3
- 位置：`MoviePilot-TV/Models/Models.swift:1086-1097`（去重 key）、`:2934-2983`（身份构造与媒体标识兜底）；传播至 Explore/Search 去重与 SwiftUI ForEach。
- 触发路径：`GET /subscribe/shares` 返回缺失、0、负数或重复分享 ID。
- 根因：raw_id 可选且不校验正值/唯一性；缺 ID 时用可变标题+用户，空值时随机 UUID，raw 0 则共享 `share:0`。
- 用户影响：不同分享被分页去重吞掉、SwiftUI 重复身份，或刷新后 ID 改变导致焦点跳动。
- 主审证据：Dedup 测试只覆盖正且唯一 ID；兼容巡检用 ID 写字典但不断言正/唯一；模型接受缺失 ID。
- 跨端结论：分享 ID schema 是否强制唯一正值未验证。
- 最小方向：确认 schema 后，在分享快照边界要求唯一正业务 ID；非法记录采用明确过滤/拒绝策略，不以可变字段或 UUID 冒充持久身份。
- 独立复核：verify_m001_i 确认列表丢项与焦点不稳，但存活卡片仍携带自身原始 share，不能静态证明 Fork 了错误目标；维持条件性 P3并收窄影响。
- 修复状态：用户批准修复。改动收敛在 `MoviePilot-TV/Models/Models.swift` 两处。（1）`generateUniqueKey`（`:1086-1097`）把「有效分享号」从「非 nil」收紧为「**正**整数」—— `0` 与负数一律视为缺失。原实现 `raw_id.map(String.init) ?? share.id` 只认 nil，令所有 0 号分享共用 `share:0`，进而在 `deduplicateSubscriptionShareMedia` 里互相吞掉：两条不同分享只剩第一条，用户侧表现为列表平白少卡且无任何提示。（2）`SubscribeShare.id`（`:2934-2983`）重构身份构造并新增 `shareMediaIdentityComponent`：只有正业务 ID 才由业务 ID 决定身份（`Share-<id>`，不再把可变的 `share_title`/`share_user` 掺进正 ID 分支）；缺业务 ID 时对齐 Web `SubscribeShareView.vue` 的兜底 key 链，按 `media_id → tmdbid → doubanid → bangumiid → anilistid → name` 取首个非空媒体标识，再拼 `share_user`；连媒体标识都没有的退化输入才退回随机 UUID —— 宁可让该记录每次解码都算作新项（去重不生效、最多多一张重复卡），也不与别的记录撞成同一身份而被去重静默吞掉。
- 审计「剩余未验证」两项的复核结论：**分享 ID schema 已验证** —— `~/code/MoviePilot` 的 `app/schemas/subscribe.py:153-155` 声明 `id: Optional[int] = None`，即后端**设计上允许缺 ID**；列表代理 `MoviePilotServerHelper._handle_list_response`（`app/helper/server.py:336-342`）在 200 时直接 `return res.json()`，**逐条不做任何校验**。缺 ID 因此是契约内输入而非异常，这也是采用 fail-open 而非「拒绝非法记录」的直接依据。**非法 ID 的 Fork 后端语义已验证并驳回 F-078 的 Fork 分支** —— `app/api/endpoints/subscribe.py:715-733` 的 `/subscribe/fork` 先 `sub_dict.pop("id")` 再建订阅，订阅内容全部来自 name/year/type/keyword/媒体 ID/过滤规则等字段，ID 唯一的去处是建订阅成功后的 `async_sub_fork(share_id=sub.id)`（给中心服务器加「复用人次」），且该调用**返回值不参与任何判断**；`share_id=None` 时 URL 退化为 `/subscribe/fork/None`（垃圾请求，静默忽略），为 0 时给 0 号分享刷计数。故「复用了错误目标」在静态语义上不成立，ID 异常的真实后果仅为**中心服务器复用人次统计可能记错归属**，本机用户不可见。**真机焦点表现仍未验证**。
- 未采纳审计原「最小方向」的理由：其表述为「在分享快照边界要求唯一正业务 ID；非法记录采用明确过滤/拒绝策略」—— 在缺 ID 属契约内输入的前提下，这条等于**把后端合法返回的分享从列表里剔除**，正是本项用户影响中「列表丢项」本身。用户明确不接受丢卡，且经比对 Web 端同位置（`SubscribeShareView.vue:287-293`）为「`item.id || 媒体标识链-share_user`」的兜底公式、列表侧完全不去重（`:181` 原样 `concat`），故改采 fail-open 并让兜底公式与 Web 对齐。
- 未采纳用户「TV 也不去重、跟 Web 对齐」提议的理由：`Paginator.swift:242-243` 的注释（「用于跳过少量只包含已知项目的页面，继续向后寻找新内容」）与 `:283-284` 的 `if !hasNewContent && currentError == nil { hasMore = false }` 表明 TV 的 `hasMore` **收敛依赖 processor 的返回值**，而去重正是该返回值的来源。移除去重后 `processor` 只要该页非空即恒返回 true，`hasMore` 只能靠服务端空页收敛；一旦某页全为已知项（列表被插队后移）或服务端 `page` 参数失效，TV 会无限追加重复卡且永远翻不到底。Web 能不去重是因为它**没有 `hasMore` 状态**，终止条件在数据层（`currentData.length === 0`），其 key 只喂给虚拟滚动的行高缓存/ResizeObserver/行定位，没有删数据的权力。故保留去重机制、只修 key 公式。
- 验证：新增 7 条用例（0 号与负数不再互撞、缺 ID 落到媒体标识、标题变更后身份不变仍可跨页去重、正 ID 身份不受标题/分享人影响、退化输入不被去重吞掉、重复正 ID 的现状固化）。定向 `SubscriptionShareDedupTests` 10/10 通过。**反向验证**：保留新用例、把两处实现退回修复前，得 6 挂 / 4 过 —— 4 条通过者即阴性对照（`testDuplicatePositiveRawIdsStillCollapseToOneRecord` 固化「重复正 ID 仍会去重掉一条」的现状，既有 3 条正 ID 用例为回归对照）。全量套件 **937/937 通过、零失败**（930 + 新增 7），与上一轮日志逐名比对确认无用例消失。
- 残留未关闭：后端给出**重复正**业务 ID 时仍会去重掉一条 —— 这是「保留去重」的固有代价（Web 靠完全不去重规避），无唯一键可区分；中心服务器实际是否返回缺失/0/负数/重复 ID 在本地不可观测；真机 tvOS 焦点表现未验证。
- 剩余未验证：真机焦点表现；中心服务器实际 ID 分布。


### F-079：分享GET→Fork丢失当前schema的AniList与统一身份

- 状态：已修复（`58c7e81`）
- 修复状态：已完成（`58c7e81`）
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift` 的 `SubscribeShare.CodingKeys/init` 与 `MoviePilot-TV/Services/APIService.swift` 的 `forkSubscription`。
- 触发路径：当前分享GET返回`anilistid`或`media_source/media_id`，TV解码后用户直接Fork。
- 根因：三个字段均属当前后端Share GET/Fork schema与Web类型，但TV模型未声明；GET解码即丢失，Fork又直接编码该模型。
- 用户影响：纯AniList/统一来源分享可Fork成缺主身份订阅；多身份记录会失去声明的canonical owner并回退到辅助raw身份。
- 当前证据：后端91ce365f的GET/Fork使用同一SubscribeShare schema，Web 7ea14bc9原对象直传；独立代理核对数据库/endpoint与TV直接编码出口。legacy`mediaid`不在Share schema，unknown extra会被后端过滤。
- 最小方向：只给SubscribeShare补`anilistid/media_source/media_id`及CodingKeys/解码；不保存raw payload。模型字段同时供F-077投影复用。
- 测试：官方GET JSON解码→真实`forkSubscription`请求体，断言`id`及三字段完整；未知extra和legacy无需新增断言。
- 剩余未验证：当前部署实际单一来源分享记录分布；不影响静态合同确认。

### F-080：SSE 未收到合法终止仍按普通成功收尾

- 状态：已修复（2026-08-17 补齐 clean EOF fallback 与 AI terminal）
- 严重度：条件性 P2；纯资源展示分支单独为 P3
- 位置：`MoviePilot-TV/Services/APIService.swift:1748-1757`、Search/ResourceResult/Transfer AI SSE 消费链。
- 触发路径：HTTP 200 SSE 在 `done`、`error` 或 `enable == false` 前正常 EOF；或 ResourceResult 收到整体 error 且存在目标站点。
- 根因：三类消费者不持有“是否收到合法终止事件”的状态，循环自然结束和业务 error 会落入普通成功收尾。
- 用户影响：Search/ResourceResult 发布不完整或空结果；整体 error 仍可进入 missingSites 同步重试并遮住错误；AI 截断或 `done + data.success:false` 可清进行中状态并允许再次触发未确认完成的副作用。
- 主审证据：真实后端兼容测试明确要求 `sawTerminalEvent`，生产代码无同等检查；多个本地 stub 仅 append 后 EOF 并将缺终止固化为成功。
- 跨端结论：TV 生产/测试终止语义冲突已确认；后端是否总发终止事件未验证。
- 最小方向：共享最小终止分类；搜索无终止走既有 fallback，业务 error 不进 missing-site 重试，AI 未终止不得按成功清状态。
- 独立复核：verify_m001_k 确认本地 Search 桩将 append+EOF 固化为成功，而兼容/AI 探针要求终止；生产 AI 还漏检 done 分支的 data.success，维持条件性 P2。
- V011-C 补强：Search 业务 `error` 只 `break` 后仍过滤/发布累积结果，append 后自然 EOF 也成功；malformed JSON 现会 throw 并走 fallback，因此历史“decode 错误被吞”不再成立。合法多 `data:` 行仍归 F-101。
- V015 生产补强：ResourceResult 未保存 terminal 分类；业务 `error`、无终止 EOF、`enable == false` 与 `done + data.success:false` 均可继续进入站点补偿、过滤和发布，整体 error 还可能触发不应有的 missingSites 请求。
- W011 确定反例：指定目标站点且SSE首事件为业务error时，循环只break，随后仍计算missingSites并再次普通搜索；当前Web收到error后直接结束，不进入TV补偿阶段。业务error必须跳过成功后处理，成功流的缺站补偿仍保留。
- I003集成与定向复核：verify_a001_h与review_a001_h确认底层stream在clean EOF直接正常finish，Search/Resource两个consumer会发布累积结果；当前Web记录`receivedDone`并在缺done关闭时fallback。malformed data当前会throw并恰好进入普通fallback，驳回把历史畸形流结论继续算作当前缺陷；维持F-080 P2终止合同。
- I009集成传播：review_a001_j确认Transfer AI SSE在没有`enable=false/type=done/error`的clean EOF后仍按成功结束，取消分支又跳过进行中状态清理；复用局部`sawTerminalEvent`与现有终止分类，维持本项P2，不新增AI流框架。
- 修复记录：2026-08-14 的 `receivedDone` 门禁先关闭业务 `error` 发布部分结果与缺 `done` 成功收尾，但 clean EOF 只显示中断、没有按 Web 语义进入普通搜索 fallback，Transfer AI 仍会静默成功。2026-08-17 补齐：Search/ResourceResult 在 clean EOF 无 `done` 时抛传输中断并复用既有 `/search/title` fallback，业务 `error` 仍直接失败且不 fallback；Transfer 只把 `enable=false`、`type=error`、`type=done` 视为终态，无终态 EOF 显示“AI 整理连接中断，请重试。”。回归测试覆盖两个搜索消费者、权限 fixture 与 AI clean EOF。
- 剩余未验证：端点精确成功 token、后端终止保证和真实网络截断频率。

### F-081：单条坏规则令整份配置失效并静默 fail-open

- 状态：已修复（`670cf86`）
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Models/Models.swift:2848-2867`、`MoviePilot-TV/Services/APIService.swift:1998-2001` 及过滤调用者。
- 触发路径：规则数组任一未选中项缺 String `id/name`，或任一条件字段类型异常。
- 根因：`[CustomRule]` 原子解码；单项坏数据令整份配置失败，搜索调用者静默退化为未过滤结果，SystemViewModel 可保留旧规则列表。
- 用户影响：设置页仍显示旧的已选硬过滤规则，但实际资源搜索完全绕过硬/软过滤，仅输出控制台日志。
- 主审证据：fixture 全部合法，缺“有效规则+单坏项”、选中规则损坏与最终反馈测试。
- 跨端结论：TV fail-open 链可静态确认；上游规则完整性保证未验证。
- 最小方向：仅在配置输入边界隔离坏项；若坏项是已选规则，应明确报告不可用，不把所有字段批量 Optional 化。
- 独立复核：verify_m001_k 确认 Search/Resource catch 后直接返回原 contexts，System 失败后保留旧列表；空白/重复 ID 又被 ForEach/Focus/first(where:)直接消费，维持 P3。
- S005 复核：review_a001_j 补充合法响应中已选 ID 缺失也会在两个 `if let` 静默 no-op；System 成功加载时的清理不能保护用户未先打开设置页的搜索链。
- V015 生产补强：规则请求/解码失败、已选 ID 缺失及规则应用失败都直接保留未过滤资源；用户看不到硬过滤已失效。
- W020-E传播：review_a001_h主审确认空/重复`id/name`直接进入过滤页Button、ForEach身份与FocusState；重复ID造成列表/焦点歧义，空name形成无有效名称控件。当前正常Web/agent写入有校验，但后端通用setting写入口未逐项验证内部字典，legacy/raw配置仍可达；在fetch/解码信任边界一次校验，不能向每行散布guard。
- W020-E第三裁决升级：verify_a001_h确认设置与执行分别GET时，同ID更新为B而执行当前B符合现合同，陈旧A展示归F-126；但执行响应成功却缺所选ID时两个`if let`均跳过并原样返回全部结果，设置四态修复不能替代。重复ID还同时污染ForEach/focus/profile与`first`执行查找。review_a001_j与第三代理均支持这些条件性核心过滤后果达到P2，故本项升级；合法唯一长同前缀name仅保留未验证P3布局风险。
- 修复状态：已完成（`670cf86`）；输入边界逐项宽容解码，静默丢弃坏项、空白或重复的规范 ID/name，并保留首个合法规则；用户明确接受已选规则缺失时继续静默不过滤且不新增错误 UI。完整规则身份回归、Simulator clean build、本地串行 432/432 测试（跳过 5 个真实后端兼容套件）及最终独立复审均通过。
- 剩余未验证：目标上游规则完整性/ID 保证、真实异常频率；下游只补坏项策略和回归。

### F-082：`success:false` 载荷可被发布为成功

- 状态：已修复（`d8198fc`）
- 严重度：条件性 P1
- 位置：`MoviePilot-TV/Services/APIService.swift:203-234`
- 触发路径：通用数据接口返回 HTTP 2xx、envelope `success:false`，同时带非 null data。
- 根因：ApiResponse 急切解码 data；兼容路径在检查 success 前直接返回 data，不兼容路径也可能先抛 data 解码错误，均无法优先呈现服务端失败。
- 用户影响：失败可被发布为空列表/空设置；订阅快照还会把空结果缓存 30 秒，首页、详情和分季短暂显示未订阅。
- 主审证据：设置、搜索/发现、分季和订阅快照均走 helper；项目已有 `success:false + data:{}` 业务失败 fixture，但无通用 GET 同形测试。
- 跨端结论：TV 优先级根因可静态确认；哪些 GET 实际返回该形状未验证。
- 最小方向：先解 envelope 状态，显式失败立即抛本地化服务端错误，再解 data。
- 独立复核：verify_a001_a 用本地解码探针确认可解 data 会在 success 检查前返回，错形 data 又先转 decodingError；维持 P2。
- V015 传播：同步资源 fallback、站点列表和自定义规则均走该通用解码边界，`success:false + data` 可继续成为资源成功或成功空。
- V019 传播：statistic/storage/downloader三个Dashboard请求都走通用unwrap，失败envelope仍可作为成功卡片发布。
- V018/V020 传播：订阅编辑的选项/详情与下载器列表/轮询均走同一通用数据 helper；失败 envelope 可继续被发布为可保存配置或成功空下载状态。
- G02 clean-room 末裁：当前上游通用响应以`success/code`为业务裁决，data不得覆盖失败；错误订阅/配置状态又可继续驱动取消、保存等mutation，升级条件性P1。仅交换判断顺序并补冲突矩阵。
- 修复状态：已修复（`d8198fc`）；共享解包器先拒绝显式 `success:false`，目标类型因错形 data 解码失败时才复用既有 `JSONValue` 读取 envelope 并抛本地化服务端错误；正常成功路径仍只解码一次，未新增生产测试钩子或抽象。公开 `fetchSettings()` 聚焦用例覆盖 `data:{}` 与 `data:[]`，依赖解析、Simulator clean build、本地串行 438/438 测试（跳过 5 个真实后端兼容套件）及最终独立复审均通过。
- 剩余未验证：哪些当前 GET 返回此形状；修复仍须保留 success 缺失及原始对象/数组兼容。

### F-083：下载动作解码混淆空 body 与不可解非空 body

- 状态：已修复（2026-08-14）
- 严重度：P2
- 位置：`MoviePilot-TV/Services/APIService.swift:237-248`
- 触发路径：暂停/恢复/删除返回仅 `message_i18n` 的失败对象，或非空但畸形的 HTTP 2xx body。
- 根因：首个 ActionResponse 全字段可选，普通对象已成功解码而本地化 ApiResponse 分支不可达；两次解码失败后又把零字节 body、畸形 JSON、null、数组和错类型都当 success。
- 用户影响：失败原因退化 Unknown；畸形响应可让 UI 错误翻转下载状态或移除仍存在任务。
- 主审证据：三个调用者直接依赖 success；无动作响应体测试。`{"success":false,"message_i18n":"失败"}` 会返回 false 而非翻成功，但 message_i18n 丢失。
- 跨端结论：TV fail-open 机制可静态确认；下载接口真实空 body/本地化契约未验证。
- 最小方向：保留明确空 body 成功兼容；非空 body 用包含 `message_i18n` 的统一模型严格解码。
- 独立复核：verify_a001_a 确认翻成成功仅发生在两次解码都失败的响应，故收窄标题与影响；当时按轮询通常可纠正评为P3。
- V020 生产复核：暂停、恢复与删除都直接依赖这个宽松动作响应；空 body 兼容和非空畸形 body 的 fail-open 必须仍在共享解码边界区分。
- W017双审升级：数组、标量、纯文本或畸形非空2xx会被三个主动mutation当成功；暂停/恢复可错误翻状态，删除可直接移除仍存在任务且页面没有错误反馈。未知JSON对象可解成`success=false`是反证边界。生产后果不只是一帧展示，故升级P2；仅明确零字节/204成功兼容可保留，其他非空响应复用严格decoder失败关闭。
- I003集成与定向复核：verify_a001_h与review_a001_h确认start/stop/delete三端点当前backend均声明必填Bool的对象envelope，TV宽松decoder两次失败后的`true`没有兼容依据；空体、HTML、null、标量与错类型均须失败关闭，直接复用严格decoder/CHK-017，维持P2。
- 剩余未验证：当前成功是否确为零字节/204/null及正式本地化字段契约。

### F-084：海报降尺寸会改写任意 URL 文本

- 状态：已修复（2026-08-17 补齐详情路径）
- 严重度：P2；G06 由 P3 升级
- 位置：`MoviePilot-TV/Services/APIService.swift:265-274` 及复制逻辑 `2533-2543`
- 触发路径：非 TMDB 海报 URL 的 host、path、query 或签名包含字符串 `original`。
- 根因：对完整 URL 全局执行 `original → w500`，而非只替换 TMDB `/t/p/original/` 路径段。
- 用户影响：插件/CDN/签名海报 URL 被改写并加载失败；后台和主线程构造路径都会触发。
- 主审证据：动态来源支持任意绝对海报 URL；季海报已有精确 TMDB 路径段的正确模式；现有图片测试复制了过宽期望。
- 跨端结论：TV 改写机制可静态确认；真实上游 URL 频率未验证。
- 最小方向：用单一共享 helper 基于 URL components 只改写精确 path 段 `/t/p/original/`，保留 host/query/fragment 原文。
- 独立复核：verify_a001_a 确认 ImageProxy 与 BackendCompatibility 预期也复制了全局替换；相邻窄字符串替换仍不是完整修复，维持 P3。
- G06联合裁决：两票确认当前上游模型允许任意第三方绝对海报URL且没有“original只会出现在TMDB尺寸段”的合同；host/query/签名或普通文件名被稳定改写会直接造成图片不可用，升P2。最小修复只在URLComponents路径中替换精确`/t/p/original/`组件。
- 修复记录：用户裁决保留既有 `original → w500` 行为，以原始 URL 作失败回退。2026-08-14 仅覆盖 MediaCard、BestResultCard、ForkSubscribeSheet；2026-08-17 将同一 `posterFallback` 补到详情推荐/相似卡、无 backdrop 时的详情海报背景及 MediaPreloader 背景预取，主 URL 失败后只重试一次原图。backdrop 本身不伪造 poster fallback。
- 剩余未验证：真实非 TMDB URL 命中频率与目标Web的降采样范围。

### F-085：规则预览、规范化与 matcher/后端失败语义分裂

- 状态：已修复（`7f9fd17`）
- 严重度：P2
- 位置：`MoviePilot-TV/Models/Models.swift:2857-2862`、`MoviePilot-TV/Services/CustomFilterService.swift:81-224`、`MoviePilot-TV/Views/Pages/SystemView.swift:940-968`
- 触发路径：已选规则含 `seeders = " 5 "`、非法 include/exclude 正则、缺失/不可解析 pubdate、Web 提示允许的单值 size/范围 seeders，或其他空白/坏格式条件。
- 根因：模型注释、设置预览与 matcher 各自解释原始字符串，没有共享 canonical 解析/校验结果；各字段又混用 fail-open 与 fail-closed。
- 用户影响：硬过滤可能放过全部或清空全部资源，软过滤错误灰置；设置预览仍显示规则已配置。
- 证据：预览 trim 后把空白做种数显示为有效，Swift `Int/Double` 微探针和 matcher 却解析失败并跳过；非法 regex 被 `try?` 静默忽略；坏 pubdate 直接匹配；size 单值恒不匹配、seeders 范围被忽略，现有测试没有 matcher 语法矩阵。
- 跨端结论：TV 内部预览/matcher 分裂已确认。review_a001_h 只把公开 v2 当降级证据：Web 提示单值或范围且编辑端不校验；公开 Python/Rust 执行路径自身也有差异，不能据此把 size 单值写成 TV 独有偏差，更不能替代缺失的目标同级上游仓库。
- 最小方向：先确认目标后端版本，再让 matcher 与预览消费一次解析所得的 canonical rule；已选规则解析失败必须显式报告，不单方面按 Web 提示扩展 TV 语法。
- 独立复核：review_a001_h 完整核对 S005、两条搜索、设置预览、模型、测试及公开 v2 Web/Python/Rust；确认空白做种数在公开 Rust 会 trim 生效而 TV 跳过、非法 regex 与坏时间失败语义不同，维持 P3。
- S005 复核：review_a001_j 补充空白 exclude 可被预览隐藏却作为空白正则命中拼接内容、seeders 范围被 TV 忽略，并再次确认公开 v2 只能作降级证据。
- V015 生产补强：已选规则缺失、坏正则、空白或语法分裂在最终资源页仍静默 fail-open；沿用既有 canonical 规则输入边界，不为结果页另造语法层。
- W020-F传播：review_a001_j主审确认`SystemFilterRulePreview.normalized()`会trim include/exclude，而TV matcher、当前后端regex与当前Web保存均保留raw pattern；首尾空格或纯空白可被预览成另一语义甚至“无附加条件”。统一信任边界规范化或忠实呈现执行值即可同根关闭，不另编号。
- W020-H双审升级：review_a001_h与review_a001_j独立确认H只处理已成功解码且已按ID选中的单条规则，不给F-081数组/缺ID链加权。当前Web/模型明示并可保存size单值与seeders区间，generic后端写入口也不校验；TV却让size单值对正常torrent恒不匹配、seeders区间静默跳过。空格exclude还会被预览省略但执行匹配content固定空格并清空硬过滤结果。正常Web可达配置会让核心搜索全空或条件完全失效，故由P3升级P2。
- W020-H合同边界：当前Web、generic backend、Agent校验、Python matcher与TV各有不同语法；先决定size单值、比较符边界、seeders区间、非法/反向区间的官方合同，再用一个表驱动解析结果同时驱动预览与matcher，不由TV单端猜测。
- 剩余未验证：目标部署 Rust 开关/实际版本、Python/Rust 执行路径、正则方言高级差异及真实坏规则频率。

### F-086：未规范化 baseURL 可生成双斜杠或无效 URL

- 状态：已修复（`90b40b4`）
- 严重度：条件性 P1
- 位置：`MoviePilot-TV/Services/APIService.swift:372-379,795-800`，同类拼接位于 SSE/图片路径；入口 `LoginViewModel.swift:20-25`。
- 触发路径：用户输入带尾斜杠或前后空白的服务器 URL。
- 根因：登录只检查非空，baseURL 原样持久化；请求再用字符串拼接 `/api/v1` 等路径。
- 用户影响：形成 `//api/v1/...` 或无效 URL，在严格路由/代理下登录、API、SSE、图片请求失败，错误地址还成为下次默认值。
- 主审证据：全仓无 baseURL trim/canonicalization，测试只用无尾斜杠规范 URL。
- 跨端结论：TV 输入/构造边界可静态确认；目标服务器是否容忍双斜杠未验证。
- 最小方向：在单一入口 trim、限定 http/https 与 host、拒绝 query/fragment、只规范化尾斜杠，并保留反向代理 path-prefix；持久化规范值供 API/SSE/图片共用。
- 既有独立复核：verify_a001_b 确认尾斜杠生成双斜杠、空白解析失败、无 scheme/host 错解，而无尾斜杠 path-prefix 正常；最初仅按输入构造评P3。
- V019 传播：三个Dashboard请求均使用同一未规范化baseURL拼接，尾斜杠/空白可让整组状态刷新进入失败路径。
- G02既有全局裁决：verify_a001_h确认baseURL原样持久化/拼接；rounda_g02_third进一步确认Login在校验/认证成功前写全局baseURL并触发currentUser/cache副作用，当时升级P2。
- G02 clean-room 末裁：失败登录也已先污染原会话，且空白/尾斜杠candidate会在持久化后破坏旧owner；升级条件性P1。最小修复仍是局部candidate成功认证后一次commit。
- 剩余未验证：目标代理对双斜杠的容忍度。

### F-087：空白首选错误字段遮蔽有效错误文本

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Services/APIService.swift:46-48,827-837`
- 触发路径：`message_i18n` 为全空白，而后续 `detail` 或 `message` 有有效文本。
- 根因：2xx `ApiResponse.localizedMessage` 与非 2xx selector 都在 trim 前选择首个“非空”字段，选中空白后才 trim，最终退化为状态码。
- 用户影响：用户只看到 HTTP 状态码，丢失可操作的服务端错误原因。
- 主审证据：字段优先级和 trim 时序静态闭合。
- 跨端结论：TV 错误降级机制可见；真实 payload 频率未验证。
- 最小方向：逐项 trim/filter 后再按本地化优先级选择首个有效文本。
- 独立复核：review_a001_c_retry2 确认登录错误直接传播至 Login/System UI，而静默校验/恢复吞掉错误；根因仍是共享 trim 时序，维持 P3。
- V011-C 同根扩展：Search SSE 仍以 `message_i18n ?? message` 在 trim 前选值，空白本地化字段可遮蔽有效后备消息；复用逐项 trim/filter 的最小方向，不另编号。
- V016 同根扩展：添加下载严格动作解码器同样在trim前选择`message_i18n`，空白首选可遮蔽有效`message`，ViewModel最终只能显示通用失败。
- V021 同根扩展：整理preview/submit同样先选择空白`message_i18n`，后续合并或通用错误会遮蔽有效`message`；继续只修共享错误选择器。
- G02 clean-room 末裁：确认上游没有保证首字段非空白，且多个用户可恢复动作稳定退化为状态码/通用失败；升级P2。仍只需一个`trimmedNonEmpty`选择器。
- 剩余未验证：真实 payload 频率；I003 继续核对全部错误入口。

### F-088：form/query 标量特殊字符未按目标解析规则编码

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Services/APIService.swift:1035-1041`；Explore 动态来源 `appendingQuery/relativeBackendEndpoint`
- 触发路径：用户名或密码含 `&`、`+`、`%`、空格等 form 特殊字符；或动态来源已有 `token=A%2BB`、筛选值为 `C++` 等字面加号。
- 根因：登录用 `URLComponents.query` 直接作为 form body；动态来源又把已有 percent-encoded query 解成 queryItems 后重序列化。两者都没有按最终 form-style decoder 语义保护标量值，字面 `+` 可被后端解释为空格。
- 用户影响：登录与自动重登稳定失败，甚至拆出额外表单参数；条件性动态来源可把 token/filter 值从 `+` 改为空格，导致鉴权或筛选失败。
- 证据：两名代理的只读 Foundation 探针均得到未按 form 语义转义的 body；`&` 拆参数、`+` 变空格，即使 percentEncodedQuery 也不会把字面 `+` 编为 `%2B`。
- 跨端结论：TV 请求构造缺口可见；后端具体字段契约未验证。
- 最小方向：使用同一个小型标量 percent-encoding 原语：登录构造 form-urlencoded body，动态来源在保留既有 `percentEncodedQuery` 的同时按 raw percent-encoded append 写入；覆盖特殊字符、非 ASCII 与 `%2B` 往返，不增加依赖。
- 独立复核：review_a001_c_retry2 确认 Content-Type 正确，直接登录、手动刷新、App 更新重登和自动重登共用缺陷路径；维持 P2。
- V009 条件扩展：verify_a001_h 在 V009-A/E 闭合 `%2B → + → 后端空格` 与 `C++` 链；review_a001_h 独立确认版本特定 Axios 会发 `%2B`，但当前部署插件值/query decoder fixture 缺失，因此只作为条件性 P3传播，不改变本 finding 的 P2 主严重度，也不并入 F-134 的复合结构问题。
- 剩余未验证：后端具体字段/schema；本地 form body 捕获测试缺失。

### F-089：登录拒绝被当成既有会话失效

- 状态：已修复（`90b40b4`）
- 严重度：P2；G06 由未验证 P3 转确认
- 位置：`MoviePilot-TV/Services/APIService.swift:841-883,1044-1049`
- 触发路径：登录端点用 401/403 表示凭据错误、禁用账号或其他登录拒绝，调用者采用默认 `preserveExistingSessionOnFailure:false`。
- 根因：获取凭据的 login 请求复用普通鉴权请求的“401/403 表示已有会话失效”分类；login 会先 logout 并抛 `.unauthorized`，服务端错误不经本地化错误选择。
- 用户影响：若后端使用 401/403，LoginView 会显示“登录已失效”而非真实凭据错误；System 手动刷新还可能清除既有会话。普通首次登录通常无旧会话，清理影响不能泛化。
- 主审证据：静态分支闭合；现有 fixture 只覆盖 preserveExistingSessionOnFailure=true。
- 跨端结论：TV 分类链可静态确认；后端登录拒绝使用 400/401/403 的契约未验证。
- I016受限集成传播：System手动重登录未传`preserveExistingSessionOnFailure:true`，因此登录端点若以401拒绝刷新，会清掉仍有效旧token/凭据；该具体用户影响正是本项已记录的System分支，不因单票改为已确认。旧成功反转logout另归F-027 P1。
- I016独立复核与争议：verify_a001_h再次确认同一System分支并按“旧会话原本仍有效却被刷新失败破坏”建议条件性P2；当时因登录拒绝401/403上游合同未闭合而冻结为未验证P3；迟到200复活logout仍归F-027 P1。
- 最小方向：登录端点禁用自动重登并直传服务端错误，旧会话是否清理由登录调用者显式裁决。
- 独立复核：verify_a001_c 确认默认登录与 System 手动刷新走该分支，App 更新/自动重登使用 preserve=true；但正式清单只给一般受保护接口语义，无法证明登录端点状态码，故改为未验证 P3。
- G06联合裁决：rounda_g01_recheck与rounda_g02_third均核到当前后端凭据/MFA失败明确返回401；System手动`relogin()`又使用默认`preserveExistingSessionOnFailure:false`，因此刷新旧凭据失败会清除原本仍可用的旧会话。两票等级分别P1/P2，取共同下界确认为P2。登录200但no-access保留旧会话另归F-029，通用401/403跨session重放归F-027。
- 剩余未验证：login 403分支、真实手动刷新频率、部署版本及Web最终展示；当前401生产链已静态确认。

### F-090：`tmdb_id == 0` 被当成有效识别结果

- 状态：已修复
- 严重度：条件性 P3
- 位置：`MoviePilot-TV/Services/APIService.swift:1220-1222,1254-1256,1275-1277,1286-1288`
- 触发路径：`/media/search` 或 `/media/recognize` 返回 tmdb_id 为 0/负数，后续候选或 fullDetail 又有正 ID。
- 根因：四个成功出口只用 if-let，非法值立即返回；下游还用原始 `recognized ?? fullDetail`，未复用正 ID 校验。
- 用户影响：无效值遮蔽正候选并构造 `tmdb:0`/负数详情、预加载、订阅补查或新订阅预填。
- 主审证据：MediaActionHandler/详情预加载调用者不再校验正值；现有巡检用 `>= 0` 同时放过 nil 和 0。
- 跨端结论：TV 内部正 ID 边界不一致；真实后端是否用 0 表示缺失未验证。
- 最小方向：识别循环逐候选复用 validNumericIdentifier，非法值继续查找；下游候选先过滤再排序。不得顺带全局修改 MediaInfo identity 的既有 Web-zero 语义。
- 独立复核：verify_a001_d 确认 nil 会继续而 0/负数不会，且动作/预加载/详情均无二次校验；维持条件性 P3。
- 剩余未验证：真实后端是否返回 0/负数、候选排序与无效订阅 payload 处理。

### F-091：首次下载器列表失败后页面不再恢复

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:19-29,40`；`MoviePilot-TV/Views/Pages/DownloadTaskView.swift:55-76`
- 触发路径：页面首次 `fetchDownloadClients()` 遇到瞬时网络、鉴权或解码失败。
- 根因：失败后 `clients` 与 `selectedClient` 保持空；随后三秒循环只调用 `loadDownloads()`，而空客户端会立即返回，客户端列表不再重试。
- 用户影响：页面持续显示无下载器/无任务的假空状态，服务恢复后也不会自行恢复，必须离开并重新进入页面。
- 主审证据：review_a001_e 逐一追踪首次加载、轮询任务、空客户端 guard 与 View 空态；未发现运行期再次调用客户端加载的路径。
- 跨端结论：TV 本地恢复链可静态确认；真实失败频率和 Web 重试策略未验证。
- 最小方向：在客户端为空且非已确认真实空列表时复用现有客户端加载入口，并区分错误与真实空态；不新增第二套轮询器。
- 独立复核：verify_a001_e 确认本次页面生命周期没有再次获取客户端的入口；`success:false + data:[]` 还可经 F-082 折叠为同一假空路径，维持 P2。
- W016/W017传播：review_a001_j与review_a001_h分别从Status页分区和DownloadTask全文件重新闭合首次clients失败→selectedClient空→轮询只调空guard的loadDownloads→永久伪空，并核对Web至少在mount/keep-alive重读clients。无新编号，维持P2。
- 剩余未验证：真实空客户端是否应周期重读、最终重试节奏及 Web 行为。

### F-092：下载动作完成后的 toggle 可反向覆盖轮询状态

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Views/Pages/DownloadTaskView.swift:99-115,206-209`；`MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:77-107`
- 触发路径：暂停或恢复请求在途时，三秒轮询先发布服务器的新 `isDownloading` 状态，随后动作请求返回成功。
- 根因：动作成功后不是写目标状态，而是对当前对象执行 `isDownloading.toggle()`；当前值可能已被轮询改成正确服务端状态。
- 用户影响：本地按钮/图标被反向显示，直到下一次轮询才可能纠正；快速重复遥控操作、切换客户端或任务会放大错写窗口。
- 主审证据：review_a001_e 闭合 View 动作 Task、VM 网络 await、轮询发布与成功后当前对象写回的交错顺序；相关测试未覆盖受控延迟。
- 跨端结论：纯 TV 状态归属候选。
- 最小方向：把动作绑定到不可变客户端、任务与目标状态，或让轮询成为状态唯一权威；请求期间阻止同一动作重复提交。
- 独立复核：verify_a001_e 确认正确状态被 toggle 反写后，相同服务端状态不会再次触发 `onChange`，错误按钮可持续存在；快速双击也会二次翻转，维持 P3。删除与旧轮询还存在短暂重插窗口。
- W017双审升级：同一行没有in-flight gate，快速双击会并发发送两次相同mutation并toggle两次；轮询先发布正确服务端状态后，旧动作响应又可反写且相同后续值未必触发纠正。复用单行busy、冻结目标状态，成功后赋目标值或刷新；不建动作队列。按可持续错误控制状态与重复远端mutation升级P2。
- 剩余未验证：真机遥控连击与焦点视觉只需行为验收，不影响静态竞态成立。

### F-093：下载列表和动作错误全部静默

- 状态：用户决定跳过（2026-08-27）；已实现部分保持，残余维持现状
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:25-27,65-67,83-105,121-126`
- 触发路径：下载器列表、任务轮询、暂停、恢复或删除任一路径失败。
- 根因：catch/失败响应仅直接 `print`，ViewModel 没有错误状态，也没有复用全局失败通知；View 只能观察列表和 loading。
- 用户影响：首次错误看起来像真实空列表，动作失败看起来像遥控器无响应，服务端消息被丢弃。
- 主审证据：review_a001_e 检查五类错误出口及 DownloadTaskView 全部展示状态，未找到用户可见反馈；成功路径保持静默符合 H-012。
- 跨端结论：TV 本地错误体验候选；后端错误字段和 Web 展示未验证。
- 最小方向：复用现有 NotificationManager 或单一 VM 错误状态只报告失败，成功保持静默；同时经 Logger 取代直接 `print`。
- 独立复核：verify_a001_e 确认父级已有 NotificationManager、同类 Transfer 页面已复用，但下载页没有消费者；Logger 替换只能闭合 F-060，不能替代用户反馈，维持 P3。
- W017双审升级：clients、列表、start/stop/delete全部失败仅print；首次失败误作真实空，热刷新失败保留旧任务却无stale提示，主动mutation失败又像遥控器无响应，页面没有error/retry或辅助功能反馈。覆盖完整页面和全部任务控制，故升级P2；最小为loading/empty/error/stale/data分流、可聚焦重试与主动动作错误通知，成功继续静默。
- 当前处置：下载器列表首次失败后轮询会自动重试，下载器错误有可见提示；clients/downloads 连续失败超过 5 次通知一次，暂停/恢复/删除失败立即通知，成功保持静默。与当前 Web 核对后，Web 只保证首次成功前 Loading、成功空才空态、热刷新失败保留旧数据，动作失败仍仅 `console.error`，并不存在 error/stale/retry 四态；TV 的自动恢复语义与 Web 一致且主动动作反馈更强，但任务列表首次失败仍可能短暂显示“暂无任务”，旧数据也没有独立 stale 投影。因此不能写成完整 loading/empty/error/stale/data 已修复。
- 用户裁决（2026-08-27）：已实现的自动恢复与失败通知保持；残余“任务列表首次失败短暂假空”与“旧数据无独立 stale 投影”由用户决定跳过，不改代码。
- 剩余未验证：后端失败消息的真实形态，以及 TV 任务列表首次失败短暂空态的实际可见时长。

### F-094：空白下载 hash 可穿透到动作 URL

- 状态：用户决定跳过
- 严重度：P2（由 P3 升级）
- 位置：`MoviePilot-TV/Models/Models.swift:1263,1299,1323-1335`；`MoviePilot-TV/Views/Pages/DownloadTaskView.swift:100,198-203`；`MoviePilot-TV/Services/APIService.swift:1491,1502,1513-1517`
- 触发路径：任务 hash 为 nil、空字符串、全空白，或含 `/`、`?`、`#` 等 path delimiter，用户执行暂停、恢复或删除。
- 根因：模型接受全部形态且身份规则不一致，View 只检查 Optional，API 再把原字符串直接插入 URL path。
- 用户影响：nil 动作无反馈，空/空白请求错误路径，特殊字符会改变 path、query 或 fragment；同时与 F-024 的不稳定身份/碰撞风险相互放大。
- 主审证据：review_a001_e 闭合模型、View gate 与三个 API 动作出口；没有非空 trim 或 path-segment 编码边界，动作测试均缺失。
- 跨端结论：TV 边界分裂可静态确认；当前后端是否保证非空 hash 未验证。
- 最小方向：在共享下载任务/动作边界要求 trim 后非空不可变 hash，并安全构造 path segment；若无可靠动作身份则禁用并显示失败原因。
- 独立复核：verify_a001_e 用只读 URLComponents 探针确认空 hash 形成 `/download/stop/`、空白形成 `%20`、分隔符改变路由结构；F-024 管行身份/碰撞，F-094 管动作可用性/路由，裁决独立保留并维持 P3。
- W017编号校准：Dictionary trap继续归已包含该控制流的F-024并升级P1；本项只保留nil静默无动作、空/空白/分隔符形成无效或改形URL。当前合法下载器仍以torrent hash为正向边界，未闭合错目标、数据损失或确定核心中断，维持P3。
- G05后裁：主审与不同代理独立复核均确认当前后端模型仍允许optional hash，TV又会让空串/全空白穿过View gate进入三个动作URL；两票都认为原P3不足，虽分别建议P1/P2，协调取共同下界升P2。F-024继续独立承载行身份/trap，不合并编号。
- 剩余未验证：正式 hash 必填性、字符集与异常记录频率。

### F-095：客户端切换后旧行会向新客户端发送动作

- 状态：已修复（`7b7130e`）
- 严重度：条件性 P1
- 位置：`MoviePilot-TV/Views/Pages/DownloadTaskView.swift:20-29,40-51,99-115,198-203`；`MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:77-125`
- 触发路径：从下载客户端 A 切到 B，在 B 的任务列表完成前操作仍显示的 A 行。
- 根因：切换时旧 rows 保留且可操作，行不携带来源 client，所有动作读取当前 `selectedClient`；删除返回后的 client guard 只会确认本来就捕获的 B。
- 用户影响：A 的 hash 被发给 B；若两个下载器存在相同 hash，可能暂停、恢复甚至删除 B 的任务。
- 证据：verify_a001_e 独立复核 A001-E 时新增；现有测试只覆盖“先向 A 发请求、随后切 B”，未覆盖“先切 B、再操作旧 A 行”。
- 跨端结论：TV 错目标 mutation 机制可静态追踪；相同 hash 分布未验证。
- 最小方向：列表绑定已加载的 client generation；切换时立即禁用旧行，动作冻结并校验行所属 client。
- 独立复核：verify_f095 从客户端切换、旧行保留到 mutation 参数重新追踪，确认 A 的 hash 会发给当前 B，且同 hash 可暂停、恢复或删除 B 任务；F-092 是动作与轮询状态竞态，F-095 是列表与客户端代际错配，独立保留并维持条件性 P2。
- V020 生产复核：B加载失败时A旧行可无限期留在已选B下而非只存在短窗口；现有测试是“先向A发delete再切B”，顺序与真正反例“先切B再操作A行”相反，不能视为覆盖。
- W017双审升级：切到B后旧A行仍无downloader owner，动作在点击时读取当前B；B慢时存在常规窗口、B失败时无限保留。同hash时可对B暂停/继续/删除，而删除链还固定`delete_file=true`，能永久删除错误客户端数据，故升级条件性P1。行快照直接绑定`clientName`，`loadedClient != selectedClient`时禁用旧行，mutation显式接收`(clientName, hash)`即可。
- 修复状态：已修复（`7b7130e`）；ViewModel 记录实际发布列表的 `loadedClient`，与当前选择不一致时 UI 禁用旧行，暂停、继续、删除均由行显式传入客户端并在请求前后校验。重复轮询同一客户端不重复发布 owner。回归同时覆盖切换后 3 种动作零请求，以及删除已向 A 发出后切 B 的迟到响应；聚焦 8/8、依赖解析、Simulator clean build、本地串行 439/439 测试（跳过 5 个真实后端兼容套件）及最终独立复审均通过。
- 剩余未验证：同一 hash 跨客户端的实际频率及真机切换操作窗口。

### F-096：可选入库状态探测可触发重登或登出

- 状态：用户决定跳过
- 严重度：P2
- 位置：`MoviePilot-TV/Services/APIService.swift:1693-1704,795-883`；`MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:157-159,211-219`
- 触发路径：订阅用户进入电影详情，best-effort `/mediaserver/exists` 返回 401/403。
- 根因：只用于徽章的辅助探测沿用 `makeRequest` 默认自动重登/登出，而同类 `/mediaserver/notexists` 已显式关闭两项破坏性副作用。
- 用户影响：可选“已入库”后缀探测即可用存储凭据重登、重放请求，或把仍可使用主功能的会话切回登录页。
- 主审证据：review_a001_g 确认调用者 catch 后本就允许保持未知状态；正式检查清单和同类测试已固定可选探测 403 不登出的不变量，但 `/exists` 仅有 200/query 测试。
- 跨端结论：TV 参数分裂可见；当前端点权限和状态码频率未验证。
- 最小方向：仅在 `fetchMediaServerExists` 调用 `makeRequest` 时关闭自动重登与登出，错误继续降级为未知徽章状态。
- 独立复核：verify_a001_g 确认调用者本就允许失败降级为未知，而 `/notexists` 已显式关闭自动重登与登出；F-096 是可选探测参数缺口，F-027 继续约束旧响应会话归属，维持 P2。
- 剩余未验证：真实端点返回 401/403 的频率及 Web 端行为。

### F-097：媒体服务器轮询失败会清空旧卡片

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/HomeViewModel.swift:96-118,135-151`；`MoviePilot-TV/Views/Pages/HomeView.swift:189-211`
- 触发路径：首页已有媒体服务器卡片，十秒轮询中某一服务器发生网络、HTTP、解码或取消错误。
- 根因：TaskGroup 的单服务器 catch 把失败转换成权威空数组，收集后再用新字典整体替换旧快照，无法区分成功空响应与失败。
- 用户影响：已展示卡片瞬间消失并显示“暂无最近内容”，当前焦点项被移除；恢复后焦点不保证回到原卡片。
- 主审证据：review_a001_g 闭合 catch→空数组→整字典替换→ForEach/focus 链；F-023 的坏单项解码会命中，但普通网络错误独立存在。
- 跨端结论：纯 TV 轮询发布候选。
- 最小方向：轮询结果区分成功与失败；只有成功空响应清空，失败/取消保留该服务器上一快照，整批取消不发布。
- 独立复核：verify_a001_g 确认网络错误、解码错误与取消均被转换成权威空数组并整体发布；只有成功空响应应清空，失败保留该服务器旧快照，取消不发布，维持 P3。
- G03窄第三裁：rounda_g02_third再次按正确编号闭合“单服务器失败→空数组→整体覆盖旧快照”，确认旧卡片与焦点项会被移除；十秒轮询只能使后续成功时恢复，不能消除当前稳定错误/空态，最终校准为P2。
- 剩余未验证：真机焦点恢复落点。

### F-098：AI 批量整理部分受理被静默当成普通完成

- 状态：用户决定跳过（保持当前行为）
- 严重度：P1（由条件性 P3 经I009/G09升级）
- 位置：`MoviePilot-TV/Services/APIService.swift:1593`；`MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:461-535`；`MoviePilot-TV/Views/Pages/TransferHistoryView.swift:243`
- 触发路径：批量 AI 接口返回 `success:true` 和有效 `progress_key`，但 `history_ids` 是请求集合真子集或空数组。
- 根因：成功响应解码丢弃 `message/message_i18n`，accepted IDs 未去重或约束在 requested 集合内；VM 计算 rejectedIds 后只解除 busy，不显示部分/零受理，仍监听进度并刷新清空选择。
- 用户影响：部分项目未启动但没有提示；零受理也可表现为普通进度/完成，用户无法判断哪些记录需要重试。
- 主审证据：review_a001_f 闭合 decode→rejectedIds→progress→refresh 链；现有测试只覆盖单条 fallback 与批量全部接受，没有 partial/empty/foreign ID。
- 跨端结论：TV 已有 accepted/rejected 表示但反馈分支缺失；当前后端是否允许子集、消息是否解释拒绝原因未验证。
- 最小方向：返回规范化 accepted/rejected IDs 和 trim 后消息；accepted 只取请求交集并去重，子集/空集明确反馈，进度只覆盖实际受理项。
- 独立复核：verify_a001_f 确认 accepted IDs 未去重、未限制在请求集合内且零受理仍进入进度链；F-075 是手动逐项 mutation 丢失已受理状态，F-098 是 AI 批量响应规范化与反馈缺口，独立保留并维持条件性 P3。
- I009集成升级建议：review_a001_j确认VM在启动accepted后立即清选择，却只有后续SSE终态才能证明completed；业务失败、无终态EOF或取消均丢安全重试集合。与F-080终止合同、F-156新选择owner交叉但不互替，建议本项升P2；等级待不同代理裁。
- I009定向裁决：review_a001_h反证“accepted后立即结束busy”，当前仍保持`isAiRedoing`直到SSE终态；真正P2是终态只有聚合结果、无逐ID完成回执且失败后已移除选择，无法精确恢复。无终态EOF归F-080，运行中新选择归F-156；本项按terminal receipt边界升P2。
- G09交叉升级：两名代理独立确认当前后端把全部ID交给单一agent prompt且只返回整批success/failure，TV模型又丢弃`history_ids/completed`；用户不能知道哪条已实际执行，失败或重试可能再次处理已完成项。两票共同升P1；F-080继续只管合法终态，最小修复先由后端提供逐IDreceipt。
- 整改裁决：用户决定保持当前行为；SSE 终态有错误时显示通知，并继续整体刷新整理历史，不在 TV 单端推断逐 ID 结果。
- 剩余未验证：后端是否会返回子集、重复或外来 ID，以及消息字段的拒绝语义。

### F-099：手动媒体选择接受 0 且负值遮蔽有效 fallback

- 状态：已修复
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Views/Sheets/ManualMediaSearchSheet.swift:4-18`；`MoviePilot-TV/Models/Models.swift:132`；`MoviePilot-TV/ViewModels/ReorganizeViewModel.swift:290`；`MoviePilot-TV/Services/APIService.swift:1623`
- 触发路径：TMDB/Bangumi/AniList 搜索结果的原生数值 ID 为 0/负数，同时 `media_id` 有有效 fallback；或用户手工输入 0。
- 根因：`ManualMediaSelection.mediaId` 只检查非空并优先原生数值 ID，没有复用正数校验；手工 `isValidManualMediaId` 只校验 ASCII 数字并明确接受 `"0"`。0 遮蔽 fallback 后继续提交，负值遮蔽后又被表单校验拒绝。
- 用户影响：0 可进入整理预览、后台整理和共享选择器的添加下载请求；负值让本有有效 fallback 的结果不可提交。
- 主审证据：review_a001_f 确认现有测试锁定 0 为有效，Reorganize/API 测试只覆盖正 ID，AddDownload 同样直接发送选择结果。
- 跨端结论：TV 已有正数原生 ID helper 且订阅清单把 raw 0 视作缺失；手动整理/Web selector 是否把 0 当特殊值未验证。
- 最小方向：数值来源先过滤 `> 0`，无效继续尝试规范化 fallback；手工输入使用来源感知校验，不全局改写 MediaInfo 身份语义。
- 独立复核：verify_a001_f 确认 0 可通过手工数字校验，负数原生 ID 会先遮蔽有效 fallback 后再失败；F-090 是 API 搜索成功出口提前接受非法 TMDB ID，F-099 是手动选择优先级与提交校验分裂，独立保留并维持条件性 P3。
- V016 生产补强：添加下载手工校验接受`"0"`，原生负ID又先遮蔽有效fallback后被表单拒绝；应直接复用现有`MediaIdentifier.validNumericIdentifier`，不在此页另写校验器。
- V021 生产复核：Reorganize手工输入仍把`"0"`视为有效，搜索选择仍让0/负原生ID先遮蔽合法fallback；preview与background submit会直接消费该值。
- G09交叉升级：两名代理对照当前后端truthy身份语义确认`0/000`等同未提供，现有测试还反向固化TV接受0；该值可直接进入整理/下载提交，故升条件P2。最小只复用现有正整数helper，不改legacy opaque身份。
- 剩余未验证：真实搜索结果是否包含 0/负数及 Web selector 对 0 的产品语义。

### F-100：同键旧订阅状态请求可覆盖较新强刷

- 状态：已修复（`0cfeb12`）
- 严重度：条件性 P1
- 位置：`MoviePilot-TV/Services/APIService.swift:2314-2361`，对照快照请求代际 `2366-2496`
- 触发路径：同一 `media+season` 的旧 lookup A 在途；远端订阅状态发生变化；较新的强刷 B 先返回并缓存新值，随后 A 返回旧值。
- 根因：Bool 状态请求只有全局 `subscriptionCacheGeneration`，没有同 key 的 latest-request revision；A、B 属于同一 generation 时都能写缓存并向调用方返回。
- 用户影响：较新的 Header/详情状态可被旧结果逆转；旧值既覆盖缓存又直接返回给旧调用者并写回同一 `MediaPreloadTask.isSubscribed`。Bool 缓存 120 秒且访问续期，没有固定最大陈旧年龄；若回滚为 false，详情的主动刷新 guard 还可能不再触发。
- 主审证据：`checkSubscription` 在请求前后只比较 generation；相邻订阅快照路径已有 revision guard；现有测试只覆盖 generation 变化和取消，未覆盖同 generation 的乱序强刷。
- 跨端结论：纯 TV latest-wins 缺陷已确认，不依赖 Web 实现；需要响应跨越远端状态变化，因此严重度保留条件性。
- 最小方向：复用已有 snapshot revision 模式，为规范化同 key 维护 latest revision/task；较新 force supersede 较旧普通 miss 和 force，旧响应在 store 与 return 前都校验，旧调用者复用或读取最新结果，不新增缓存框架。
- 独立复核：verify_a001_h 确认全局 generation 只表达 mutation/session 失效，不能表达同 key 新旧；现有 snapshot 测试已证明“两个调用者与最终缓存都拿最新值”的可复用最小契约。
- V012-A 生产补强：Preloader 在 detail ready 后继续普通 `checkSubscription`，详情 `.task` 与 delayed-ready 路径又都可 force；布尔 guard 仅在 await 返回后写，两个 force 也能同时进入，确认 normal→force 与 force→force 的真实调用入口。最小修复仍复用同 key revision/latest 语义，不另编号。
- G02 clean-room 末裁：旧normal/force反写不仅造成展示回滚，还会反转F-124菜单的add/cancel判断并进入错误mutation；升级条件性P1。每key轻量revision足够，不引入通用请求调度器。
- 修复状态：已由 `0cfeb12` 完成。`APIService.checkSubscription` 为每个规范化 `media+season` key维护request revision/owner；较新的force开始后，旧normal/force响应不能再写缓存或返回为当前结果。
- 验证：`MediaDetailViewHeaderActionTests.testForcedSubscriptionStatusRefreshPreventsOlderResponseFromReplacingCache` 覆盖旧请求晚回时不会替换较新结果；2026-08-11 定向复跑通过。
- 保留边界：Bool TTL是否应关闭访问续期属于独立产品选择，不影响本finding已闭合。

### F-101：SSE 多 data 行未按事件组帧

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/Services/SSEFramer.swift`（新增）、`MoviePilot-TV/Services/APIService.swift:2737-2766`、`MoviePilot-TV-Tests/BackendCompatibilityTests.swift:2689-2736`
- 触发路径：服务端发送一个由多条 `data:` 行组成、以空行结束的合法 SSE 事件。
- 根因：生产解析器和兼容探针均按物理行立即 JSON 解码，没有按空行组帧并合并同一事件的 data 内容。
- 用户影响：资源流可误判 malformed 后进入 fallback；AI 进度监控可失败，而后台任务仍可能继续。
- 主审证据：全部本地 SSE 桩只生成单行 data，未覆盖多行事件；生产与兼容探针复制相同逐行解码方式。
- 跨端结论：标准 framing 风险可静态提出；当前后端是否承诺单行 JSON、heartbeat 与 Content-Type 未验证。
- 最小方向：只在共享 `streamSSE` 中按空行组帧、合并 data 后解码一次，并让兼容探针复用同一规则。
- 独立复核：verify_a001_h 用只读 Foundation/JSON 探针确认两条 data 分别解码失败、以 `\n` 拼接后成功；全部现有 SSE fixture 只覆盖单行 data。
- V011-C 传播：Search 的 malformed 分支会因此进入同步 fallback；当前 Search 测试桩仍全为单行 data，未覆盖合法多行事件。
- V015 生产补强：ResourceResult 消费同一逐物理行流；合法多 `data:` 事件被判 malformed 后误入同步 fallback，故修复仍只应落在共享 `streamSSE`。
- 剩余未验证：当前后端 framing、heartbeat/comment、单事件最大尺寸、Content-Type 与明确终止保证。

- 修复状态（🆕）：已修复。新增 `SSEFramer`（`nonisolated struct`，仅做事件组帧，不做 JSON 解码、不判定业务语义），生产解析器 `streamSSE` 与兼容探针 `readSSEStream` 共用同一条规则，不再各写一份逐行解码。
- 🆕 修复过程中发现的关键事实（本项根因比审计描述更深一层）：**`URLSession.AsyncBytes.lines`（`AsyncLineSequence`）会丢弃空行**。审计给的「最小方向」是在既有取行之上补一层累积，但这行不通 —— 空行即事件结束标志，`lines` 根本不把它交出来，故事件边界在取行阶段就已丢失：两个独立事件 `data: a\n\n data: b\n\n` 与一个多行事件 `data: a\n data: b\n\n` 经 `.lines` 之后都是 `["data: a", "data: b"]`，二者**不可区分**。已用本地真实 SSE 流复核（`Content-Type: text/event-stream`，三个单行事件 → `lines` 只取出 3 行，分隔空行全部消失）。
- 🆕 该事实的实践后果：在 `.lines` 之上补累积，非但修不好多行事件，反而会把原本正确的**连续单行事件**合并成一个非法载荷（`Unexpected character '{' after top-level value around line 2`）而导致全线报错 —— 本轮实测一度造成 7 个既有用例转挂（`BackendCompatibilityReadOnlyTests`、`BackendCompatibilitySideEffectTests`、`ResourceResultViewModelTests`、`SearchViewModelTests` 的 SSE 相关用例），随后改为字节层切行方才归零。可见「改动前逐行解码」对单行事件其实是**正确**的，真正的缺陷只在多行事件，而修它必须先能看见空行。
- 最终实现：`SSEFramer` 自己按字节切行（`consume(byte:)` 在 `0x0A` 处成行，再交给 `consume(line:)` 做协议层累积），生产端与探针均改为 `for try await byte in ...`。按 `0x0A` 切分对 UTF-8 安全（续字节均 ≥ 0x80），已加多字节用例（「流浪地球」）锁定。性能对照（1.3 MB / 401 事件，`-O`）：字节遍历 9.5 ms，`.lines` 15.9 ms，无回归。
- 与规范的唯一偏差（有意保留）：流结束时若仍有未以空行收尾的挂起事件，`flush()` **交付**它而不是按规范丢弃。改动前是「data 行一到即处理」，断线前最后一个事件（可能是 `done`）一直收得到；严格丢弃会静默降低容错。`flush()` 也会先补上停在半行上的残余内容。
- 验证（老三样）：① 定向 —— 新增 `SSEFramerTests` 20 条（协议层 12 条 + 字节层 8 条）全过，且此前转挂的 4 个 SSE 相关测试类 96/96 全过；② **反向验证** —— 把两个入口逐字复刻改动前代码（`String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)`、`flush()` 恒返回 nil），保留全部新用例 → **14 挂 / 6 过**，6 条通过者即阴性对照（`testSingleLineEventContentIsUnchanged` 内容不变、`testBlankLineWithoutPendingDataReturnsNil`、`testConsecutiveSingleLineEventsStaySeparateThroughByteStream`、`testMissingTrailingBlankLineStillYieldsSeparateEvents`、`testHeartbeatsAndCommentsProduceNoPayloads`、`testMultibyteCharactersSurviveByteSplitting`，均为「单行/内容/应忽略行」这类改动前后必须一致的行为）；③ 全量 **957/957 通过、零失败**（937 + 20），与 F-078 一轮的 937 逐名比对确认 **零用例消失**。
- 阴性对照的一处诚实说明：`testConsecutiveSingleLineEventsStaySeparateThroughByteStream` 在改动前的代码下**也通过** —— 这正印证了上面那条结论（旧码对单行事件本无错），本项修复的真实收益面只有合法的多行事件。
- 残留未关闭：当前后端 8 处 SSE 生产端（`app/api/endpoints/search.py:113-128` 的 `_sse_event`、`app/api/endpoints/system.py:788` 等）**全部**是 `f"data: {json.dumps(...)}\n\n"` 的单一物理行形态，故本项触发条件目前**不可达**，属前瞻性健壮性修复；另 heartbeat/comment 行、单事件最大尺寸、Content-Type 与明确终止保证仍未验证（探针已能正确忽略 `:` 注释行，并有对应用例）。

### F-102：opaque progress_key 未按路径段编码

- 状态：未验证
- 严重度：P3
- 位置：`MoviePilot-TV/Services/APIService.swift:1813-1814`、`decodeAiRedoResponse:1611-1614`
- 触发路径：后端返回包含 `/`、`?`、`#`，或形似既有 percent escape 的 `%xx` 的非空 progress key。
- 根因：启动响应只校验非空，`progressStream` 直接把 opaque key 插入 URL path。
- 用户影响：进度请求走错路由或丢失 key，TV 报失败并允许重复触发，而后台任务可能仍在运行。
- 主审证据：测试只使用 URL-safe 的固定 key；目标路径未复用已有 path-segment 编码辅助。
- 跨端结论：TV URL 构造缺口已确认；后端是否永久保证 UUID/URL-safe token 未验证。
- 最小方向：复用单一路径段编码 helper，编码失败立即返回现有 invalidURL，不新增 URL 层。
- 独立复核：verify_a001_h 的只读 URL 探针确认 `/ ? #` 改写路径、查询或片段，`%xx` 被提前解释；Foundation 会自动安全编码普通空格与裸 `%`，两者不再列为已确认触发。
- G05/G09限缩裁决：两轮主审/独立复核均确认当前本地后端只生成字母、数字和下划线，当前成功路径不会触发特殊字符；静态拼接脆弱点保留为P3合同风险，但在缺外部producer或不同部署fixture前转为未验证，不再宣称当前生产缺陷。
- 剩余未验证：后端 key 格式保证、percent-decoding 语义及编码斜杠能否作为单段路由参数。

### F-103：资源标题与媒体 ID 由宽正则猜路由

- 状态：用户决定跳过
- 严重度：P2；由 P3 升级
- 位置：`MoviePilot-TV/Models/Models.swift:2799-2801`、`MoviePilot-TV/Services/APIService.swift:1828-1847`、`ResourceResultViewModel` 与 `MediaActionHandler` builder
- 触发路径：标题以字母加冒号开头（如 `Re:Zero`），或媒体缺少 `apiMediaId` 但仍进入资源搜索。
- 根因：`ResourceSearchRequest.keyword` 同时承载标题和媒体 ID，消费端用 `^[a-zA-Z]+:` 猜意图；builder 对缺身份媒体可直接写空字符串。
- 用户影响：合法标题误走媒体 ID 端点，或发送空关键词；同步路径也可能偏离注释所述 Web 行为。
- 主审证据：SearchViewModel 的同形文本测试把它当标题，说明不同入口确有不同路由意图；本路径缺相应用例。
- 跨端结论：TV 内部路由分裂可见；Web 当前正则和插件来源格式未验证，若 Web 同样如此不得做 TV-only 兜底。
- 最小方向：builder 先保证非空 ID 或标题，并用最小显式路由意图区分二者，不从任意标题文本反推。
- 独立复核：verify_a001_h 闭合首页最近媒体识别失败后标题直达资源页的确定链；正则同时把 `Re:Zero` 与真实媒体键判为 ID，而通用搜索测试明确要求同形文本按标题处理。
- V015 生产补强：ResourceResult 直接消费该混合 keyword；`Re:Zero` 会误走媒体路由，缺少 `apiMediaId` 又可发送空 keyword，确认其为确定下游而非仅 builder 假设。
- I012集成与第三裁决：verify_a001_h补出Search stream标题请求失败后的fallback仍把同一文本交给猜路由入口；review_a001_j以`Alien: Romulus`和`anilist:154587`分别闭合“标题意图漂成媒体ID搜索”与“真实ID文本必须由入口意图区分”，确认错误fallback会稳定改变请求语义，故由P3升级P2。
- 剩余未验证：Web 当前规则、真实无身份媒体频率及后端空 keyword 行为。

### F-104：动态媒体或人物 ID 未编码为单一路径段

- 状态：用户决定跳过
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/Services/APIService.swift:1885,1897,1912,1938-1943`，A001-D Douban `fetchMediaRecommendations:1431`；对照既有路径段编码辅助 `120-124,1793-1798,1832-1837`
- 触发路径：完整媒体键、人物 `raw_id` 或 Douban 辅助 ID 含 `/`、`?`、`#`、`%` 等保留字符。
- 根因：不透明 ID 直接插入 URL path；`buildEndpoint` 会把 `?/#` 解释成 query/fragment，`/` 会形成额外路径段，而相邻搜索入口已使用单路径段编码。
- 用户影响：详情预载、人物详情、人物作品、Douban 演员列表或推荐请求可能命中错误路由、丢失 ID 后缀或直接失败。
- 主审证据：`MediaIdentifier.resolve/normalizedString` 接受任意非空来源和 ID；现有测试无保留字符用例；只读 Foundation 探针确认 path/query/fragment 被拆分。
- 跨端结论：TV 局部路径构造缺口已确认；真实触发频率仍取决于上游 ID 字符集和后端是否按 percent-decoded 单段路由，因此严重度保留条件性。
- 最小方向：在 API 边界复用现有路径段编码器分别编码动态 ID；来源白名单保持原样，不在调用者重复处理。
- 独立复核：review_a001_h 确认 `MediaIdentifier`、`Person.raw_id` 与 Douban auxiliary ID 都允许不透明 String，且同文件搜索入口已有整段编码惯例；相邻只并入 Douban recommendations。`fetchMediaSimilar` 与 TMDB/Bangumi 演员/推荐当前只消费 Int 型 ID，不计已确认传播。
- 传播补充：verify_a001_h 在 A001-J 确认 `getGroupSeasons(groupId:)` 对任意 `EpisodeGroup.id` 也直接插入路径；并入同一根因，局部影响按 P3 看待，不新建 finding。
- 剩余未验证：人物/插件/剧集组 ID 字符集、后端 percent-decoding 次数、保留字符真实频率；`fetchMediaActors` 的 type 空末段/值域只保留调查，不扩成 finding。

### F-105：相对图片值未规范化为绝对 URL

- 状态：用户决定跳过
- 严重度：P3
- 位置：`MoviePilot-TV/Services/APIService.swift:166-200,2519-2552,2596-2600,2618-2647`
- 触发路径：海报、背景、订阅分享或人物字段返回 `/api/...`、`images/...`，或绝对 URL 前后带空白。
- 根因：共享 `displayImageURL` 不 trim；非 HTTP 字符串直接交给 `URL(string:)`，相对 URL 没有绑定后端 origin。
- 用户影响：媒体、订阅、下载或人物卡片显示占位图或加载失败。
- 主审证据：`BackendCompatibilityTests.webDisplayImageURL` 明确先 trim，并以 `URL(string:relativeTo:)?.absoluteURL` 表达 MP Web 等价规则；生产 helper 与之不一致，目标包装方法把结果传播到多个模型和卡片。
- 跨端结论：TV 与本仓库兼容 oracle 的差异已确认；该 oracle 不是当前 Web 源码，后端真实相对地址频率与 origin/path-prefix 规则仍未验证。
- 最小方向：只在共享 `displayImageURL` trim、拒绝空白，并按确认后的 MoviePilot origin/path-prefix 语义绝对化，再执行既有代理规则；不在模型/View 分散处理。
- 独立复核：verify_a001_h 的 Foundation 探针确认 `/api/...` 与 `images/...` 保持无 scheme/host，相对 base 可绝对化，带首尾空白绝对 URL 为 nil；兼容 collector 的 nil 跳过还会漏检后者。
- 剩余未验证：当前 MP Web/后端 origin/path-prefix 规则、协议相对值及真实输入频率。

### F-106：预计算图片 URL 固化旧配置

- 状态：已修复
- 严重度：P2；由 P3 升级
- 位置：`MoviePilot-TV/Services/APIService.swift:2519-2647`、`Models.swift` 的主要图片包装、`ContentView.swift:10-89`、`ContentViewModel.swift:112-147`
- 触发路径：冷启动内容请求早于 `fetchSettings()` 完成；回前台刷新改变 `GLOBAL_IMAGE_CACHE` 或 `TMDB_IMAGE_DOMAIN` 后，同一会话页面继续持有旧模型。
- 根因：settings 初始 nil、图片缓存初始关闭；多数模型把构造时生成的 URL 保存为 `let imageURLs`，配置变化后没有 revision、失效或重算；`TmdbSeason` 的按访问计算形成对照。
- 用户影响：现有卡片可能继续绕过图片缓存、使用默认 TMDB 域或请求旧服务器图片代理，直到数据重载。
- 主审证据：review_a001_j 追踪启动准备时序、图片 helper 的当前全局配置读取、多个模型的 let 包装与 season 的动态计算差异。
- 跨端结论：纯 TV 配置生命周期缺口已确认；实际竞态命中率、旧模型存活时长及热更新产品要求未验证。
- 最小方向：复用现有季海报模式，让真实生产消费的包装在访问时从原始字段和当前配置计算；不新建图片 revision/重建框架，也不为无生产消费的 wrapper 扩机制。
- 独立复核：verify_a001_h 确认启动遮罩在等待 settings 前解除、回前台明确重拉 settings、六类生产模型保存 let URL 且全仓无配置 revision/$settings 消费者；两类 wrapper 和八个便利 API 无生产消费，不扩大修复面。
- I003集成与定向复核：verify_a001_h主审、review_a001_h独立确认`fetchSettings()`的public/user两阶段没有冻结会话：A public后可读取B token并请求B user配置，旧A user结果又可发布到B；内层catch还会吞取消后发布public设置。事后ViewModel guard挡不住`APIService.settings`先写，故合并同一配置生命周期并升级P2；每个await/发布绑定epoch，取消单独传播。
- I016等级冲突与第三裁：review_a001_h受限整文件集成再次确认A public+B user混合、共享settings无guard及B失败继续留A配置，并按跨服务器图片/识别等全局配置污染建议P1；verify_a001_h独立确认机制，但未发现已消费的敏感settings字段，按默认识别源、AI开关和图片域影响维持P2。rounda_g01_recheck第三裁再次闭合两段读取/统一snapshot缺口，确认独立finding但不把配置错配扩大为敏感数据泄露，最终维持P2并复用F-130的session机制。
- 剩余未验证：真实启动命中率、各页面旧模型存活时长、tvOS 17 强制禁用缓存表现；切服后旧视图树是否仍渲染只列未验证。
- 修复记录：MediaInfo/DownloadingMediaInfo/MediaServerPlayItem/Subscribe 的预计算 `let imageURLs` 改为 `@MainActor` 按访问计算（复用 TmdbSeason/Person 模式），init 不再访问 APIService；后台 MediaInfo 解码路径删除预计算与 `MediaImageURLConfig`/三个私有 helper；按工程 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` 补齐 `nonisolated struct`（MediaInfo/DownloadingMediaInfo/Subscribe，Subscribe.addRequest 同步标 `@MainActor`；MediaServerPlayItem 因成员 FlexibleString/FlexibleBool 的 Equatable conformance 为主 actor 隔离且解码本在主线程，保留默认隔离）；tvOS Simulator clean build 通过、无隔离诊断，全量测试 602 用例 16 skipped 2 failures（均为已知 SSE 时序失败），两轮子代理独立审查验收通过。
- 补充修复（2026-08-17）：动态 getter 本身不足以触发存活视图重绘，且 MediaGrid/DetailCard 的 `.equatable()` 只比较 item ID 会继续短路。新增只读 `imageConfigurationIdentity`（baseURL、实际 useImageCache、TMDB_IMAGE_DOMAIN），主要直接图片页面观察 APIService，Grid/DetailCard 将 identity 纳入 Equatable 比较；详情背景在 identity 变化时按同一原模型重算。未引入图片 revision 仓库。

### F-107：根登录转换的错误通知 owner 失配

- 状态：已确认（原 P1 主触发已修复；用户决定跳过剩余项）
- 严重度：剩余项 P2
- 位置：`MoviePilot-TV/ViewModels/NotificationManager.swift:37-62`、`LoginView.swift:29-32,47-51`、`LoginViewModel.swift:21-34`、`ContentView.swift:11-15,83-85`
- 已修复主触发：一次登录失败显示错误后，用户重试成功或切换账号/服务器时，manager会按会话UI身份取消计时并清除旧banner；`show()`同步发布也消除了“已切根但旧排队show才执行”的窗口。
- 剩余触发路径：账号A的业务异步任务仍在途，切换到账号B后旧调用者才处理取消/失败，并再次调用全局`show()`。
- 剩余根因：manager只能清理会话切换当时已经存在的通知，无法判断切换之后新到达的`show()`属于哪个旧业务operation；部分Home调用者仍未在发布通知前校验owner。
- 用户影响：B页面可能短暂出现A操作失败提示；旧请求本身受会话取消保护，本项不再证明错误删除、保存或其他mutation。
- 主审证据：token 成功发布切换 ContentView；manager 由 App StateObject 持有；Login 调用方忽略 login Bool，现有调用链没有 dismiss。
- 跨端结论：纯 TV 状态生命周期缺陷已确认，不依赖后端具体行为。
- 最小方向：复用 manager 增加主 Actor 同步 dismiss/reset，根转换时取消旧`DispatchWorkItem`并清空状态；旧session异步来源仍以现有epoch/owner在调用show前拦截，不增加成功通知或第二队列。
- 独立复核：verify_a001_h 确认 App 级 manager 跨 root 存活，Login 成功返回值未触发撤销，旧通知会保留至原计时结束；静态状态链足以确认。
- R001传播：review_a001_h确认同一App级manager也不会在logout/root切到Login时清理，旧账号toast可继续显示；Sheet遮挡与计时过期仍归F-108运行边界，不把层级推测写成确定事实。
- R002传播：verify_a001_h确认manager由App级`StateObject`持有且不监听logout、没有reset；`show()`即便已在主线程仍异步排队，故`show(A)→logout→queued show(A)`可在Login或新会话上首次出现，五秒隐藏任务也没有session owner。
- R002独立复核：review_a001_j完整确认App入口只有该manager的合法单一owner与注入，没有App自身异步/focus新根因；修复不能在logout时无条件清空全部消息，否则会再次丢掉W020-C需要跨根交接的当前失败原因。应按session owner撤销过期消息，同时允许显式一次性logout原因由Login消费。
- W020-C反向传播：verify_a001_h提出、review_a001_j定向确认手动刷新401/403时API先logout并清凭据，Content切到新Login后System catch才写唯一`refreshMessage`；Login只消费自身error且本路径不发全局通知，最终结构上必然拿不到原因。401/403短暂是否在旧页闪现不影响最终不可达。
- 合并边界：F-089只决定登录/刷新401与403是否应视为会话失效；即使合法登出，原因仍须跨根交接。根错误owner应在成功转换时撤销旧消息，在失败登出时携带当前原因供新Login一次性消费，不建立第二通知系统。
- G08回溯争议：review_a001_h确认producer把`newValue`按值交给`show`后再清nil不会丢掉本次消息，故拒绝这一狭义旧解释；同时主张跨session晚到show与同操作成功后的scope撤错分别保留F-222/F-223并把本项升P2。现有F-107已经明确包含两条机制，故编号合并与严重度交不同代理裁决，当前结论不变。
- G08独立复核：review_a001_j同样确认按值String不会因随后清nil丢失，并确认跨session banner/晚到show为P1；但其主张该session机制直接并入本项/CHK-005，而F-223同session operation scope独立P2。F-222编号与本项最终P1/P2须第三裁，当前P3暂不提前改写。
- G08第三裁：verify_a001_h从当前HEAD重新闭合“已有A banner→logout/切服→根切换后继续显示”和“A异步操作→A→B→旧show入队/发布到B”两条确定序列；裁F-222与本项共享App级manager/session transition根owner，不保留独立编号，并将根finding升级P1。最小修复复用CHK-005单调epoch，在`show`入队及真正发布两处校验，session变化时清旧banner/计时/队列；当前logout原因仍以结构化一次性消息交接。
- 后续修复与重裁：`90b40b4`已闭合已有banner跨根残留和旧排队show两条P1主路径；定向测试覆盖会话切换立即隐藏、同账号token刷新不误清。仍未覆盖“会话切换完成后，旧业务调用者才发起新的show”，该剩余项只造成短暂提示错位，降为P2，用户决定跳过不改。

### F-108：通知可能在 Sheet 下不可见却照常计时并过期

- 状态：未验证
- 严重度：条件性 P3
- 位置：`MoviePilot-TV/ViewModels/NotificationManager.swift:44-60`、`NotificationComponent.swift:25-36`、`ContentView.swift:106`，传播到 SubscribeSeason 与 TransferHistory 异步失败链
- 触发路径：父页面在 Sheet 打开期间因前台刷新、订阅事件或 AI SSE 失败调用全局通知；用户在 Sheet 内停留超过 5 秒。
- 根因：唯一 presenter 挂在根 ContentView，manager 不感知 presenter 可见性便立即开始计时，调用页随后又清空 VM error；系统 Sheet 是否遮挡该 overlay 待运行确认。
- 用户影响：若 Sheet 遮挡根 overlay，关闭 Sheet 时通知可能已经过期，失败无可见反馈。
- 主审证据：review_a001_j 闭合 SubscribeSeason Sheet 下刷新与 Transfer AI 期间详情 Sheet 两条静态链；现有测试只检查全局通知/Sheet 本地反馈的源码存在，不覆盖层级行为。
- 跨端结论：纯 TV 呈现层候选；真实层级与焦点表现必须运行验证。
- 最小方向：Sheet 自身动作继续复用现有本地 feedback；页面异步错误在 Sheet 打开时保留并延后呈现，暂不引入额外 UIWindow 或通知队列。
- 独立复核：verify_a001_h 确认两条生产触发、错误消费与五秒计时链成立，但静态代码不能证明 tvOS 系统 Sheet 层级、焦点及实际可见窗口，故不确认为缺陷。
- G08回溯补强：review_a001_h从当前HEAD收窄为SubscribeSheet尚未消失时父级订阅刷新失败、Fork先启动详情拉取再dismiss且快速失败两条并发入口；继续判runtime-only，但建议按唯一失败反馈提高至P1。因可见性仍须Simulator/真机确认，独立严重度裁决前维持未验证条件性P3。
- G08独立复核：review_a001_j确认Fork先启动后续Task再dismiss形成静态presentation窗口，但SwiftUI最终排队/拒绝/呈现只能运行确认；其维持P3并拒绝静态升P1。两票严重度冲突，第三裁前保持未验证条件性P3。
- G08第三裁：verify_a001_h确认Fork成功后父级先启动editor fetch、子Sheet随后dismiss，成功可能撞第二Sheet呈现，失败可能在根overlay计时；静态只能证明窗口，不能证明tvOS最终丢Sheet或完全看不到banner，故保留未验证条件性P3并驳回静态P1。运行验收须覆盖dismiss前/动画中/之后的成功与失败、唯一呈现、完整可读时间、warning及焦点；若复现，目标等级P2。
- 剩余未验证：tvOS Simulator 注入无副作用失败，验证 Sheet 打开期间的层级、五秒计时、主动关闭后的剩余可见时间与焦点表现。

### F-109：profile 作用域偏好与权威配置 owner 不完整

- 状态：已修复
- 严重度：P2；G06 由 P3 升级
- 位置：`MoviePilot-TV/ViewModels/SystemViewModel.swift:145-168`，V002-A 消费 `66-96`
- 触发路径：profile A 使用 baseURL `https://host/mp_a`、username `b`；profile B 使用 baseURL `https://host/mp`、username `a_b`，二者都生成 `defaultSearchSites_https://host/mp_a_b`。
- 根因：`userDefaultsKey` 用 `"<prefix>_<baseURL>_<username>"` 直接表示二元组，分隔符也允许出现在两个分量中，因此编码非一一对应。
- 用户影响：两个合法服务器/账号配置可相互读取或覆盖默认站点、默认媒体来源及硬/软过滤规则；站点/规则加载还可反向清空共享键。
- 主审证据：review_a001_h 闭合 key helper、V002-A 两项 getter/setter 与 Search/SiteFilter/System 消费链，并给出确定碰撞对。
- 与既有 finding 区分：F-063 是凭据存储权威/混合会话，F-086 是 baseURL 规范化；即使二者修复，tuple 编码歧义仍存在。
- 跨端结论：四类profile key碰撞是纯TV本地缺陷；推荐配置另有当前Web以同源localStorage作优先缓存、后端`/user/config/Recommend`按认证用户名持久化的服务端per-user合同。
- 最小方向：共享 key builder 使用带版本、无歧义的 tuple，四个prefix一次迁移；推荐配置直接复用服务端当前用户合同，本地fallback也绑定规范profile。不要同时维护app-global与服务端两套权威值。
- 独立复核：review_a001_j 确认全文件恰有四个 prefix、合法碰撞会跨默认站点/来源及硬软规则读写，并确认加载流程可反向改写；F-063/F-086 修复后根因仍独立成立。
- W020-A传播：verify_a001_h与review_a001_h确认System根任务的站点加载会通过默认站点自赋值归一化回写同一碰撞key，为设置页提供直接生产写入链；维持P3。
- W020-D第三裁决：verify_a001_h确认TV只读写app-global `MP_RECOMMEND`，不按服务器/账号隔离且不访问服务端配置；当前Web本地缓存也不完整，但会在缺值时读取并在保存时写回后端per-user配置。F-214机制成立但修复/验收与本项同为配置owner，独立编号驳回并入。
- G06联合裁决：两票确认四类key不仅有确定tuple碰撞，还从原始`baseURL + credential username`取owner而非权威`currentUser.user_name`；token-only、凭据轮换和空凭据会稳定落入错误/`default` bucket，baseURL别名再扩大污染，故升P2。异步写回仍由F-113另行约束。
- 剩余未验证：真实碰撞/多profile频率；已碰撞旧键无法从现存数据无损还原 owner，远端上游最新性未验证。
- 修复记录：`90b40b4` 统一会话权威时已将四类 profile key 迁移到 `userDefaultsKey` helper，key 为 `prefix_profileKey`（`profileKey = baseURL|user:user_id`，user_id 取权威 currentUser 稳定数字 ID），旧 `prefix_baseURL_username` 键仅一次性迁移后删除；原文 `_` 分隔碰撞对不再成立，W020-A 反向回写链随之消失。剩余旧碰撞键数据无法无损还原，按 finding 原结论接受。

### F-110：默认排序选择升序仍固定降序

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：`MoviePilot-TV/Views/Components/TorrentsResultView.swift:267,283-285,329-343,374-395`
- 触发路径：排序字段保持“默认”，用户把方向切换为“升序”。
- 根因：菜单始终暴露 `SortType` 且箭头显示升序，但 default 比较器固定执行 `pri_order >`，忽略 `isAsc`。
- 用户影响：界面显示升序，列表仍按高优先级降序。
- 与 F-061 区分：即使没有任何软过滤项也发生；F-061 是全数组排序破坏过滤分区，F-110 是默认字段忽略方向。
- 主审证据：review_a001_j 在 S005 复核中追到菜单、状态和比较器；C018-B已由不同代理闭合合法组合，W011的review_a001_h主审与review_a001_j独立复核再次确认静态反例；全仓无 TorrentsResultView/SortField/SortType 行为测试。
- 跨端结论：纯 TV 内部控制/比较器契约冲突，不依赖 Web/后端；W011复核补充当前Web默认卡片顺序也不能把TV“升序箭头但仍降序”解释为兼容行为。
- 最小方向：默认比较器遵循方向；若产品规定默认只能降序，则在该字段隐藏方向选择，不新增排序抽象。
- 独立复核：C018-B与W011均已有不同代理确认；回溯只需固定产品选择并覆盖default升/降两条最小排序行为。
- G05后裁：两名不同代理重新闭合`.default + .asc`为生产可选组合，而比较器稳定忽略`isAsc`；两票均建议P2，故升级。F-061仍只管软过滤分区，不能以同一排序文件合并。
- 修复记录：`SortType` 由升降二态扩展为“默认排序/升序/降序”三态，默认状态不再显示方向箭头；“默认排序”无论字段如何都保留后端原始顺序，仅调整软过滤分区；字段仍为“默认”但显式选择升序/降序时按 `pri_order` 应用方向（与 Web 列表视图 `sortData` 的 default 字段语义一致）。已补 default 字段升/降与任意字段默认排序的回归测试。

### F-111：token-only 会话把不同账号降成同一偏好身份

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：`MoviePilot-TV/ViewModels/SystemViewModel.swift:145-168`，传播到 token-only 会话恢复、四类 profile 偏好消费者
- 触发路径：同一服务器先后使用两个合法 token-only 账号，二者都没有保存的登录用户名；或 token-only 账号与真实用户名 `default` 共存。
- 根因：profile key 忽略已恢复的 `currentUser.user_name`，只读取保存的用户名；缺失时把所有账号统一降成字面量 `default`。
- 用户影响：即使改用无歧义 tuple 编码，两个被降级为同一用户名分量的账号仍会共享默认站点、默认来源及硬/软规则选择。
- 主审证据：review_a001_j 在 V002-A 复核中闭合正式 token-only 成功测试、current user 可恢复用户名及 storedUsername 不回填链。
- 相邻主审：review_a001_h 在 V002-B 完整主审中确认同一机制与四类偏好传播，但倾向视为 F-109 的身份组成扩展；是否独立仍待不同代理按根因与验收边界裁决。
- 与既有 finding 区分：F-109 是 tuple 编码碰撞，F-063 是存储权威/陈旧值；本候选在存储无陈旧且 tuple 已无歧义时仍可发生。
- 跨端结论：纯 TV profile 身份缺陷已确认；上游契约不影响本地隔离机制。
- 最小方向：profile 用户分量取当前权威会话身份；身份尚未恢复时延迟读取或使用已验证快照，不建立新 profile 仓库。
- 独立复核与裁决：review_a001_h 在 V002-B 主审中独立确认 token-only `default` 机制与四类传播；review_a001_j 的 V002-B 复核证明 F-109 修复后本项仍发生、F-111 修复后 F-109 仍发生，且两套验收互不替代，故协调裁定为独立 finding。
- W020-A传播：verify_a001_h与review_a001_h确认`loadSystemInfo`同样忽略已恢复的`currentUser.user_name`，使连接页显示“未知”或保存凭据中的旧用户名；这同时补强F-063的存储权威边界。
- W020-C独立复核：verify_a001_h确认连接页“登录用户”取手工输入/持久凭据而非已认证`currentUser.user_name`；Plex邮箱登录后服务端规范用户名是直接反例，继续归本项而不新建显示finding。
- I016最终等级：review_a001_h以同服token-only Alice/Bob依次写四类偏好、二者都落`default`的确定隔离链建议P2；verify_a001_h独立确认token-only是受支持且有测试的生产路径，并闭合四类配置跨账号共享，第二票同意P2。历史`default`键无法证明owner，迁移不得跨用户猜测。
- 剩余未验证：真实 token-only 多账号频率、字面用户名 `default` 的后端限制；legacy `default` key 的原 owner 已不可无损判定。
- 修复记录：`90b40b4` 已把四类 profile key 迁移到 `profileKey`（`baseURL|user:user_id`，user_id 取权威 currentUser），`/user/current` 恢复时映射 `id`→`user_id`，连接页用户名取权威 `currentUser.user_name`，原“无 storedUsername 落字面量 default 共享”链已消失。`769c509` 补足 token-only 会话在 `/user/current` 恢复完成前或恢复失败时 `profileKey` 为 nil 的窗口：仅当持久化 `currentUser` 快照经 `withRestoredAccessToken` 与当前 token 强校验匹配时，回退其 `user_id` 作为四类偏好的 profile 命名空间；token 不匹配则返回 nil，不会跨账号串号。该快照不写入当前 session，也不参与新版会话或权限判定。匹配回退与不匹配拒绝两条回归测试均已保留。

### F-112：站点成功空不清旧选择且失败与空态不可区分

- 状态：已修复
- 严重度：P2（由 P3 升级）
- 位置：`MoviePilot-TV/ViewModels/SystemViewModel.swift:62-78,291-315,437-442`、`SystemView.swift:105-107,421-426,774-785`，传播到 SiteFilter、Search 与 MediaDetail 的站点按钮和请求链
- 触发路径：已保存默认站点 `{1}` 后，当前 profile 的 `/site/rss` 权威成功返回空数组；或首次/后续站点加载失败。
- 根因：本地归一化在 `availableSites.isEmpty` 时把空数组同时解释为“尚未加载/失败”，直接保留旧选择；ViewModel 又没有错误状态，因此成功空、失败与未加载共享同一表示。
- 用户影响：设置页可同时显示“1 个站点”和“暂无站点”，搜索仍把已失效 ID 发给后端；失败则伪装为空数据或继续把旧列表当当前数据。
- 主审证据：verify_a001_h 闭合 `loadSites` 成功空→自赋值归一化→旧 ID 保留→System/SiteFilter/Search 请求链；异步静态 helper 对成功空却计算空交集，证明同仓语义不一致。
- 与既有 finding 区分：F-081 是规则解码/fail-open，F-060 是直接 print；本候选是站点权威空、失败和旧选择的状态建模冲突。
- 跨端结论：纯 TV 本地状态缺陷已确认；后端对无效 site ID 的处理不影响 UI/请求状态矛盾。
- 最小方向：只有成功响应才按返回 ID 集合归一化，集合为空也清除旧选择；失败/取消与成功空分开，复用现有状态行提供最小错误和重试，不新建通用加载框架。
- 独立复核：review_a001_j 从零确认 System 自赋值、SiteFilter、Search/MediaDetail 请求及空 Sheet 链；首次失败伪装成功空，后续失败保留旧列表但无 stale/error 标记。review_a001_h 又从静态 helper 反向确认权威成功空会清除旧值，维持 P3。
- W020-A传播：两代理确认System根任务先完整等待system info才启动sites；慢前项期间sites loading仍为false，站点页可先进入“暂无站点”伪空态，扩大本项窗口。该启动顺序归F-144，站点三态仍归本项。
- W020-D传播：review_a001_j主审确认站点设置页自身仍不区分尚未加载、首次失败与成功空，后续失败则无标识继续显示旧列表；页面没有独立重试，只能依赖整个System生命周期重跑。站点集合语义错误另登记F-209/F-210候选，不混入本项。
- I016最终等级：review_a001_h补足`/site/rss`成功空后System仍显示旧选中数、Search/MediaDetail继续发送旧站点ID；verify_a001_h独立闭合System与SiteFilter两条空成功路径及后续请求，第二票同意P2。失败/旧快照四态继续归F-126，权威域选择仍分别由F-209/F-210约束。
- 剩余未验证：真实无站点频率、后端接收无效 site ID 的行为及 tvOS 权限变化后的页面重建时序。
- 修复记录：`SystemViewModel` 增加 `hasLoadedSites` 与 `siteLoadError`：只有成功响应才按权威 ID 集归一化，成功空也清除旧默认站点；加载失败保留旧列表并给出错误状态行，站点设置页提供点击重试；取消不再清空旧列表。`SiteFilterViewModel` 同步按成功空清除 `selectedSites`（Search/详情不再发送旧站点 ID），未加载完成前的写入不被误清。已补成功空清选择、失败保留+错误、未加载写入保留、SiteFilter 成功空清选择四条回归测试。

### F-113：默认站点异步归一化跨 profile 写回或返回旧值

- 状态：用户决定跳过
- 严重度：条件性 P2
- 位置：`MoviePilot-TV/ViewModels/SystemViewModel.swift:385-400,444-450`，传播 `MediaActionHandler.swift:24-27`、`HomeView.swift:230-247`、`MediaContextMenu.swift:80-85`
- 触发路径：profile A 读取默认站点并发起 `/site/rss`，网络等待期间切换到 B；A 随后成功、失败或取消。
- 根因：函数在 await 前只读取 A 的值/权限，请求后写回 helper 动态重算当前 B 的 key；通配 catch 又把失败、取消和未来 stale-session 错误都降成 A 的 storedSites。
- 用户影响：普通 200 可覆写/移除 B 的默认站点；成功或 catch 返回的 A 站点还可能进入仍存活的 Home/菜单导航，并由 B 会话发起资源搜索。持久写回不依赖旧导航是否存活。
- 主审证据：review_a001_h 闭合 A 请求构造、B 动态 key 写回、成功/失败返回值及三个生产调用者；B 无搜索权限只阻止后续请求，不阻止此前偏好写回。
- 与既有 finding 区分：普通 200/网络错误即可触发，且 F-027 只让旧请求抛错时仍会被 catch 回退 A；无歧义 key、权威用户身份或 F-112 空态修复也不能消除 await 后所有权错误。
- 跨端结论：纯 TV 本地会话归属缺陷已确认，不依赖后端异常响应；严重度因切 profile 与旧任务存活频率而条件性。
- 最小方向：复用现有 session snapshot，同时冻结发起时精确 profile key；成功、失败、取消在写回/返回前统一校验会话与权限，过期结果显式中止并让调用者停止导航，不把它映射为表示“全部站点”的 nil/空集。
- 独立复核：review_a001_j 确认普通成功（交集变化/相等）、错误、取消、撤权及未来 stale-session error 均可泄露 A 值；MediaActionHandler/Home/MediaContextMenu 当前都无法表达中止，B 有 search 权限时会由 B 会话继续请求。
- 严重度裁决：跨 profile 持久偏好污染本身按 P3；旧 action 仍 append/回调且 B 有搜索权限时会用 A 站点发起 B 会话请求，故整体保留条件性 P2。
- 剩余未验证：logout 后旧 SwiftUI Task/导航树的实际存活时长、真实触发频率及用户可见搜索传播。
- 跳过依据（用户拍板）：`90b40b4` 后所有调用者（`HomeView`/`MediaActionHandler`/`MediaContextMenu`）在 await 前后均校验 `isSessionUnchanged`，跨 profile 写回与旧站点发起新会话搜索已被外层挡住；`catch is CancellationError { return [] }` 的取消分支在当前按钮无结构 Task 调用链下不可达（会话切换/401 重登均伴随 epoch 变化被外层拦截），实际影响已不存在，剩余仅为函数内部“中止=空集”的防御性语义问题，按用户决定跳过。

### F-114：父 ViewModel 未转发 SiteFilter 子对象变化

- 状态：已修复
- 严重度：P3
- 位置：`MoviePilot-TV/ViewModels/SearchViewModel.swift:270,658-668`、`MediaDetailViewModel.swift:40,122-133` 及对应 Search/MediaDetail View
- 触发路径：首帧以默认选择 `{1}` 显示“1 个站点”，随后 SiteFilter 成功加载并把它解析为站点名；或加载后把失效 ID 归一化为空。
- 根因：两个父 ViewModel 以 `@Published` 固定持有子 `ObservableObject`，但父 View 只观察父对象；属性包装器不递归转发子对象事件，而两处现有 Paginator 桥接证明项目已依赖显式转发。
- 用户影响：按钮可继续显示初始计数或旧选择，直到焦点、Sheet 或其他父状态触发无关重绘；实际请求读取子对象当前 `sitesString`，因此本项收窄为 UI 新鲜度。
- 主审证据：verify_a001_h 穷举 Search/MediaDetail 两条生产链、父 View 观察关系、SiteFilter 发布点与现有 Paginator `objectWillChange` 转发。
- 与既有 finding 区分：有效、非空、成功响应即可触发，不依赖 F-112 的空/失败语义；F-112 影响选择/请求状态，本项仅影响父 UI 更新通知。
- 跨端结论：纯 TV SwiftUI 观察缺陷已确认，不依赖 Web/后端契约。
- 最小方向：复用现有 Paginator 桥接模式，仅把固定 `siteFilter.objectWillChange` 转发给两个父 VM；不引入新状态框架。
- 独立复核：review_a001_h 确认两个父 VM 固定持有、父 View 仅观察父对象、Paginator 已桥接而 SiteFilter 未桥接；有效非空响应即可触发，搜索动作当场读取子对象当前值，故维持 UI 新鲜度 P3。
- 剩余未验证：无关父状态触发重绘前的实际可见时长与 tvOS 焦点行为。
- 修复记录：`SearchViewModel.init` 与 `MediaDetailViewModel.init` 各补一行 `siteFilter.objectWillChange` → 父 `objectWillChange` 转发（复用既有 Paginator 桥接模式，不引入新框架）；搜索页/详情页站点按钮随 `SiteFilter` 加载解析与选择变化即时刷新。已补两个父 VM 转发行为的回归测试。

### F-115：详情 ready 判定与阶段屏障阻塞主流程

- 状态：用户决定跳过
- 严重度：P2；由 P3 升级
- 位置：`MoviePilot-TV/ViewModels/MediaPreloader.swift:94`，传播到 MediaDetailContainer/MediaDetailViewModel/Header ready 链
- 触发路径：详情响应含空串/纯空白标题、空白 Douban ID 或非正 TMDB ID；反向路径为 title/tmdb/douban 全 nil 但 Bangumi、AniList 或插件身份有效。
- 根因：ready 只检查 `title/tmdb_id/douban_id != nil`，既不规范化值，也没有覆盖项目已支持的其他媒体身份。
- 用户影响：无效详情可提前解除遮罩并显示空标题/Unknown，图片与后续动作继续消费坏身份；某些替代身份详情反而被重试后判失败。
- 主审证据：verify_a001_h 闭合有效性分支、容器 ready 发布、Header/图片传播与现有测试只覆盖非空 title 的缺口。
- 与既有 finding 区分：F-014/F-077/F-090/F-104 是具体身份归一化/投影/编码缺陷；本项是预加载 ready 门对所有身份的共享判定不一致。
- 跨端结论：TV ready 判定缺陷已确认；仅有身份而无标题是否构成完整详情及真实 payload 频率因上游缺失未验证。
- 最小方向：增加一个私有纯判定，复用现有 normalizedString 与正数 ID 语义并覆盖已支持身份；不引入验证框架。
- 独立复核：review_a001_h 确认空白 title/douban、非正 tmdb 会误 ready，正 Bangumi/AniList 与规范化插件身份被漏判；修复须局限私有纯判定，保留非空标题可 ready，不能全局改 MediaInfo.identity/Web-zero 语义或顺带引入裸 IMDB/TVDB。
- I005阶段屏障扩展：review_a001_h集成提出、verify_a001_h独立确认详情HTTP已发布`fullDetail`后仍等待背景图，外层又等待无关识别，season因此只能在`max(识别,详情+图片)`后启动；有订阅权限电视剧的内容ready明确等待`isSeasonDataLoaded`，Container全屏遮罩随之稳定串行延长。详情响应即启动season，图片独立并行，取消后不得晚发布；该主流程后果将本项升级P2，F-220作为重复编号驳回。
- 跳过依据（用户拍板）：对后端 `app/api/endpoints/media.py` `/media/{mediaid}` 确认，识别失败返回全空 `schemas.MediaInfo()`（TV 端现有 ready 校验+重试规则正是防此场景且仍必要）；识别成功时各数据源（TMDB/豆瓣/Bangumi/AniList）必然带非空 title，后端不会返回空串标题或 0/负数 ID，也不会出现“全 nil 但 bangumi/anilist 有效”的载荷，故 ready 值域误判为纯静态理论问题、真实不可触发。阶段屏障部分用户按“背景图等待有设置开关”裁非问题，一并跳过。

### F-116：预加载命中时背景安装晚于遮罩解除

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/Views/MediaDetailContainerView.swift:269`、MediaDetailViewModel 初始背景与视图异步 apply 链
- 触发路径：详情从 MediaPreloader 缓存命中，Container 记录 `wasPreloaded = true`。
- 根因：`wasPreloaded`只凭主详情ready令容器立即可见，整体绕过`isContentReady`；背景URL初始仍为nil，actors/recommend/similar首行也要等待视图`.task`应用详情后才就绪。
- 用户影响：静态存在内容已显示而背景仍灰、辅助首行未安装的窗口；随后同步apply通常会自愈，是否形成可见闪烁或焦点回归尚无运行证据。
- 主审证据：verify_a001_h 闭合 wasPreloaded、遮罩透明度、背景初值与异步 apply 顺序。
- 跨端结论：纯 TV 首帧体验未验证，不依赖 Web/后端。
- 最小方向：在 `MediaDetailViewModel` 初始化时同步安装传入 full detail 的背景，不走动画；复用单一URL解析逻辑，不改F-115的网络阶段图。
- 验证要求：用固定cache-hit task延迟辅助首行，断言背景安装和`isContentReady`前不揭示；再以Simulator/真机记录可见闪烁与焦点。
- I013第三裁：review_a001_j确认成功cache hit旁路与F-180主失败、F-033辅助错误的触发源/修复/fixture均独立；随后apply通常自愈，不需用户操作，故维持未验证P3而不升P2。
- G03全局纠偏：review_a001_h与rounda_g03_recheck均按正确F-116命题独立确认Container首帧直接揭示、VM init不安装背景、View `.task` 后补背景的确定顺序；新证据覆盖I013仅按可见时长保留未验证的旧边界，升级确认P2。实际闪烁时长与焦点影响仍留运行验证。
- 修复记录：背景选择逻辑收敛到 `MediaInfo.ImageURLs.backgroundTarget`（backdrop 优先、无则 poster），`MediaDetailViewModel` init 同步安装传入详情的背景且不走动画，`setBackground()` 与 `MediaPreloader` 背景预取共用同一实现；`setBackground` 保留 0.8s 动画与仅变化才更新的保护。预加载命中首帧即有背景 URL，网络路径随后由 `applyFullDetail` 动画升级。已补 6 条回归测试（backdrop 优先 / poster 回退 / 无图 nil / 同值 apply 守卫 / http URL 走缓存代理的 backdrop 与 poster 分支）。验证：tvOS Simulator clean build 通过；`MediaDetailViewHeaderActionTests` 46/46 通过；全量 618 用例仅已知 SSE 时序用例 `testResourceSearchPublishesResultsWithSearchPermission` 2 断言失败，与本次改动无关。

### F-117：取消早于图片 handle 安装时仍启动不可取消请求

- 状态：用户决定跳过（暂时，待内存优化工作树）
- 严重度：P3
- 位置：`MoviePilot-TV/ViewModels/MediaPreloader.swift:95,123-169`
- 触发路径：预取 timeout 的 group cancel、LRU 淘汰或 logout/显式 clearAll 在图片 child 已继承取消、但 Kingfisher DownloadTask handle 尚未安装时发生。
- 根因：取消 handler 先看到 nil handle 并恢复 continuation；operation 仍启动 retrieveImage 后才保存 handle，而方法/组已返回并把 handle 清空，取消状态与 handle 安装不原子。
- 用户影响：已取消的图片请求仍可下载并写共享缓存；注销时可能继续携带旧 Cookie，放大 F-019/F-020，但本项不依赖账号隔离问题成立。
- 主审证据：verify_a001_h 闭合已取消 child 进入 cancellation handler、continuation exactly-once 与随后 operation/handle 清理时序；现有测试无 handle 安装前取消场景。
- 与既有 finding 区分：未证明一般 `nonisolated(unsafe)` 数据竞争；确定根因仅是取消状态与 handle 安装的原子性缺口。
- 跨端结论：纯 TV 资源/生命周期缺陷已确认；真实竞态频率与后端保护性未验证。
- 最小方向：扩展现有锁盒同时保存 continuation、取消标记与 handle，operation 内二次检查，handle 安装时若已取消立即 cancel；ready 发布前再检查父 Task，不重构下载层。
- 独立复核：review_a001_h 确认 Swift 已取消任务仍执行 operation、Kingfisher cache miss 会先启动网络后返回 handle并写共享 cache；`onDisappear/unpin`、卡片防抖与普通所有者释放不是取消入口，失败 task 替换通常也不命中图片阶段。另确认图片预取返回后缺父 Task 复查，外部持有者可观察取消后的 ready 发布，归入本项而不新建 finding。
- 跳过依据（用户拍板）：P3 低严重度；竞态窗口（handle 安装前被取消）极小且无运行证据，实际频率未验证；影响仅为已取消请求继续下载写共享缓存与登出时残余请求的资源浪费，无用户可见功能错误。账号隔离放大由已修复的 F-019/F-020（`90b40b4`）承载，本项不独立成立。用户在另一工作树开发内存优化，本项涉及代码（MediaPreloader 图片预取链）均有变更，暂时跳过、留待后续。

### F-118：pin 无 owner 且非 pop 的 onDisappear 也解除保护

- 状态：用户决定跳过（暂时，待内存优化工作树）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/MediaPreloader.swift:312-313,388-398`、`MediaDetailContainerView.swift:238-245` 与四个 Tab NavigationStack/详情继续 push 链
- 触发路径：同 key 有多个详情 owner，或父详情 push 推荐/类似子详情、切 Tab 等使容器 `onDisappear`，随后有订阅通知或超过 30 个焦点预加载。
- 根因：`pinnedKeys` 是布尔 Set，无 owner/refcount；通用 onDisappear 不等于导航条目终止。返回只重新 pin key，不验证 manager cache 仍注册当前 View 的 `@State` task。
- 用户影响：静态可证明 pin 会提前失效；通知刷新可能先漏掉该 task，LRU 压力下还可能移除/取消。SwiftUI State/生命周期及真实可见后果未运行确认。
- 主审证据：verify_a001_h 闭合唯一 pin/unpin 调用者、四 Tab/子详情导航、通知只刷 pinned 与 LRU 仅淘汰未 pin 的传播链。
- 独立复核：review_a001_h 确认多 owner 任一 unpin 会解除全局保护，返回只 re-pin 不校验 View `@State` task 与 manager cache identity；all-pinned 时新未 pin task 可自淘汰，ghost pin 时软上限可超过 30 且 unpin 不立即收缩。push/Tab 的实际 onDisappear/State 顺序仍不能静态确认。
- I008集成补强：review_a001_j给出父详情push子页→通用onDisappear解除pin→超过30项LRU取消A→返回只重加key、不把旧`@State` task重新注册cache的完整条件序列；但push是否触发该生命周期仍需运行实证，主审建议条件P2，当前保持未验证P3并交不同代理裁。
- I008定向复核裁决：review_a001_h独立确认unpin→LRU移除/cancel→再pin仅写Set、旧`@State` task又因`isStarted`不能重启的注册表分裂；但push/pop的onDisappear、State保留和30+ churn仍须运行，故静态缺陷保持P3，P2用户影响不以静态票升级。
- G03窄第三裁：rounda_g02_third确认`Set`式pin的无owner根因与多owner提前解除保护静态成立，且通知只刷新pinned、LRU只保护pinned；据两张当前正确映射票确认P2。push/onDisappear/返回/LRU组合是否在真实SwiftUI生命周期完整发生仍属于运行边界，不把该边界反向当作根因未确认。
- 跨端结论：纯 TV ownerless pin 根因已确认；端到端导航时序与可见后果未运行验证。
- 最小方向：pin 使用稳定 owner token/lease（或等价最小refcount）且同 owner 幂等，只在实际导航条目结束时释放；返回时校验 View task 与 manager 注册项一致，不新建缓存框架。
- 验证要求：V012-A 与真机/Simulator 覆盖 push/pop、Tab 切换、多 owner、返回后通知刷新、LRU 及焦点，不以静态生命周期猜测冒充用户影响。
- 跳过依据（用户拍板）：静态 ownerless pin 缺陷成立，但 push/pop、Tab 切换与 30+ LRU churn 的端到端时序无运行证据，真实可见后果（返回数据失效、通知漏刷）未在真机/Simulator 复现；修复需改四 Tab 导航链与详情生命周期。用户在另一工作树开发内存优化，本项涉及代码（MediaPreloader pin/淘汰与详情生命周期）均有变更，暂时跳过、留待后续。

### F-119：canonical media alias 只回写任意一个缓存任务

- 状态：用户决定跳过（暂时，待内存优化工作树）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/MediaPreloader.swift:308,342,402-415`、`Models.swift:1080-1152`、SubscriptionModifier/Handler 与 MediaContextMenu
- 触发路径：cache 同时持有两个 `MediaInfo.id` 不同、但 `apiMediaId` 相同的富/简字段媒体对象，随后保存或取消该媒体订阅。
- 根因：cache 用 Web/UI 多字段去重键存储，`findTask(byMediaId:)` 却在 `Dictionary.values.first` 只返回一个 canonical alias；通知刷新又只覆盖 pinned 项。
- 用户影响：直接回写只更新一个 task，非 pinned alias 的右键菜单“订阅/已订阅”标签可陈旧；点击仍查询后端，不能夸大为必然错误 mutation。
- 主审证据：verify_a001_h 以既有 `testStableMediaKeyUsesWebDedupFields` 的 AniList 富/简对象证明同 canonical ID 可有不同 UI id，并闭合保存/取消回写与菜单读取链。
- 与既有 finding 区分：F-008 是 mutation 根本不发刷新信号；本项即使存在通知，canonical alias 的即时回写仍不完整。
- 跨端结论：纯 TV 缓存一致性缺陷已确认；真实 alias 频率未验证。
- 最小方向：保留现有 cache key，线性扫描当前小缓存并按精确 apiMediaId 或已识别 TMDB fallback 更新全部 alias；缓存通常受 30 项软上限约束但可超限，不重键、不加索引或缓存层。
- 独立复核：review_a001_h 确认现有 rich/slim AniList 反例及生产中源 task 自动创建 TMDB target 的第二类 alias；保存与通用取消仅写一个，通知只刷 pinned，未 pin alias 的菜单按精确 item.id 继续读旧标签，维持 P3。
- V012-B 补强：详情成功刷新只写当前注入的 preload task，成功通知也只强刷 pinned tasks；相同 canonical ID 的未 pinned aliases 继续陈旧。保持当前小缓存线性更新全部 alias 的最小方向。
- G02全局裁决：verify_a001_h与rounda_g02_third均确认精确ID/recognized-TMDB只覆盖部分alias，fullDetail与非TMDB canonical alias仍可能存活并长期读旧订阅状态；双票升级P2，点击时fresh lookup只限制错误mutation、不修正稳定错误标签。
- 跳过依据（用户拍板）：非 pinned alias 菜单标签陈旧为条件性 P2，真实 alias 并存频率未验证；点击时仍 fresh lookup，不会造成错误 mutation。用户在另一工作树开发内存优化，本项涉及代码（MediaPreloader 缓存/alias 与订阅回写链）均有变更，暂时跳过、留待后续。

### F-120：页面级 busy 状态没有动作目标

- 状态：降级（用户决定跳过）
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/SubscriptionHandler.swift` 的 `isCheckingSubscription`、`isUnsubscribing` 及多卡片调用链
- 触发路径：卡片 A 的订阅检查或取消尚未结束时，用户对同页卡片 B 执行动作；另有非电影分支未经过同一检查，可与既有操作交错恢复。
- 根因：页面共享 Bool 既没有 target/owner，也没有统一覆盖所有动作分支；它既会把 B 当成 A 的重复操作静默丢弃，也不能阻止绕过分支的晚到 Sheet、删除或错误发布。
- 用户影响：B 电影点击会无反馈丢失；B 非电影先导航后，A 的晚到 Sheet/错误仍可打断当前页面。A 的删除参数仍捕获 A，本项不声称删除了 B 或发生错误 mutation。
- 与既有 finding 区分：F-047 约束取消范围文案，F-054 约束精确删除目标，本项只讨论并发动作属于哪张卡片。
- 最小方向：让现有 in-flight 状态携带不可变目标与局部 revision；同目标才去重，异目标采用一个明确的现有交互（取代或可见拒绝），恢复后核对 owner；不新增通用队列框架。
- 主审证据：verify_a001_h 闭合共享状态、不同媒体分支与晚到发布链。
- 独立复核：review_a001_j 从同页共享 Handler 独立确认 A 在途时 B 电影在 guard 静默返回，B 非电影绕过 busy 状态并可被 A 晚到发布打断；维持 P3并驳回“删错 B”的夸大。
- V012-B 同根扩展：详情 `isUnsubscribing` 也是无 owner Bool且方法无重入 guard；MainActor 在首个 await 后可重入，旧操作的 defer 可在新操作仍运行时把 busy 提前清 false。用现有 target+revision 收敛，不建队列。
- V016 同根扩展：`addDownload()`无`guard !isSubmitting`；两个Task可在首个await后并行POST，旧请求defer还可在新请求运行时提前清busy。方法入口复用现有Bool拒绝同目标重入即可。
- V018 同根扩展：`save()`没有入口重入 guard；重复保存可并行发出 mutation，旧请求的 defer 又可在新请求尚未结束时提前清 `isSaving`。单次保存与取消/关闭的竞态另归 F-147。
- V021 边界：preview/submit方法同样缺内部reentry/owner，但正常同按钮由loading禁用，未闭合新的独立错mutation；只把明确可达重入纳入现有target+revision验收，不新编号。
- G10双审升级：review_a001_h全局主审与verify_a001_h独立复核确认AddDownload/Subscribe方法内无single-flight guard，Reorganize preview与submit只各禁自身、可同时运行；重复POST、并发预览/提交覆盖状态及旧defer提前清新busy均为静态可达，升P2。Fork已有本地guard是反证，不并入。
- G09交叉升级：两名代理再次确认Reorganize预览与真实提交互不排斥、方法内也没有cross-operation owner，用户可在旧预览仍在途时启动文件mutation或重复提交；具体错对象由F-074/F-075/F-152/F-156承载，总括owner按条件性破坏性mutation升P1。修复只复用单一operation token与现有session/目标快照。
- 后续重裁：卡片路径需要A请求尚未返回时再移动焦点激活B，主要后果是B动作被丢弃或A的迟到Sheet/错误打断B，不会因此删除B；Reorganize路径需要预览仍在加载时再按开始整理，单条局域网请求窗口较短，批量或慢存储时更易触发，但当前Web同样允许preview/transfer交叉。本项自身未证明错文件或错订阅mutation，相关破坏性目标问题仍由F-074/F-075/F-152/F-156独立承载，因此降P2，用户决定跳过不改。

### F-121：Fork 错误跨分享目标残留

- 状态：已修复
- 严重度：P2
- 位置：`MoviePilot-TV/ViewModels/SubscriptionHandler.swift` 的 `forkErrorMessage` 与分享 Sheet 调用者
- 触发路径：目标 A 的 Fork 失败后关闭 Sheet，在没有实际开始新 Fork 前打开目标 B 的分享 Sheet；或 A 的未结构化任务在 B 呈现后晚到。
- 根因：错误只在真正开始 Fork 时清除，既不随新分享 presentation 清空，也不绑定请求/目标 generation。
- 用户影响：B 的分享界面可立即显示 A 的错误；若旧任务晚到，错误还可能覆盖当前目标状态。
- 与既有 finding 区分：F-048 实际约束确认目标与执行目标未绑定，不能用作本项对照；本项不同于 F-008 的成功刷新，也不同于 F-107/F-108 的全局通知生命周期/层级，只处理 Fork Sheet 失败状态的 presentation owner。
- 最小方向：新目标 presentation 建立时清除旧错误，并用同一个小型 presentation/request revision 拒绝旧任务发布；不建立通用错误状态框架。
- 主审证据：verify_a001_h 闭合 A 失败→dismiss→B 呈现的同步残留链；晚到任务的实际可见时序保持条件性。
- 既有独立复核：review_a001_j 独立确认 B Sheet 首帧读取同一 Handler 的旧错误，且错误只在真正开始新 Fork 时清除；无句柄任务晚到仍为条件链，当时维持P3。
- W015传播：双审再次确认A失败后关闭、B新Sheet尚未操作即显示A错误；A迟到失败污染B的并发部分与F-193共用operation owner，但本项保留错误状态回归。
- G08反向争议：review_a001_h认为当前HEAD的Fork业务失败/缺ID已抛错、Sheet改用内联反馈且重试前清旧错，因此主张驳回；但这些事实尚未直接否定既有双审的“A失败后关闭→B新Sheet首帧、尚未重试”同步残留链。交不同代理只核当前presentation建立时是否清错；裁决前保持已确认P3。
- G08独立复核：review_a001_j逐步确认A失败写错、关闭不清、B新Sheet复用同一handler并立即读旧错，只有真正点击B后才清；“重试前清错”不能反证presentation首帧，主张保留P3。因与G08主审直接冲突，交第三裁。
- G08第三裁：verify_a001_h确认当前HEAD仍可达“A失败写错→dismiss只清request→页面级handler存活→B新Sheet首帧直接读A错误→仅点击B后才清”的同步序列，当时保留P3。
- G02 clean-room 末裁：错误既不绑定share presentation、share ID，也不绑定operation；它会污染当前可恢复操作界面，升级P2。使用`(operationID,shareID,message)`即可，与F-193复用token而不合并用户反馈回归。
- 修复记录（用户拍板方案）：Fork 失败错误文案带上目标媒体标题（`share_title ?? name`，兜底"该订阅"），例如"暂时无法复用订阅《XXX》，请稍后重试。"。残留/迟到错误即使显示在新目标弹窗上也可直接识别来源，消除误导；未做 presentation 清旧/拒绝迟到的 operation owner 改造。已同步更新 2 条失败反馈测试断言。验证：tvOS Simulator build 通过；`PermissionGrantedBehaviorTests` 中两个反馈用例均通过（全套仅已知 SSE 时序用例失败）。

### F-122：nullable TMDB 识别结果折叠失败、取消与无匹配

- 状态：部分修复（error/no-match 仍有组合缺口）
- 严重度：P3
- 位置：`MoviePilot-TV/Services/APIService.swift:1160-1295`、`MoviePilot-TV/ViewModels/MediaActionHandler.swift:29-46`、`MoviePilot-TV/Views/Pages/HomeView.swift:231-246`
- 触发路径：两阶段识别发生请求/鉴权/解码失败或取消；或者确实没有匹配。Home 资源搜索还会把 nil 当成正常标题回退并继续导航。
- 根因：`recognizeTmdbId` 用一个 `Int?` 表示空标题、无匹配、类型不符、错误与取消，通配 catch 吞掉失败；Handler 又把所有 nil 无条件发布为全局“不存在”弹窗。
- 用户影响：最终网络/会话错误或取消被误报为媒体不存在；Home 随后仍提交标题回退导航，因此同一动作同时写 alert 与 navigation 状态。首段失败但 fallback 最终成功时用户获得有效 ID，本身不算用户缺陷。
- 与既有 finding 区分：F-103 是标题/媒体键路由意图丢失，本项是识别 outcome 与错误呈现丢失。
- 最小方向：复用 Swift `throws` 保留 error/cancel，让 nil 仅表示成功完成两阶段后的真正 no-match；若保留首段失败后继续 fallback，暂存首段错误，fallback 成功可返回 ID，fallback 也无结果时不得伪装 no-match。详情动作才按真 no-match 呈现不存在，Home 标题回退不强制发该弹窗。
- 主审证据：review_a001_j 闭合两个请求 catch、Handler 状态与 Home 回退调用链，并确认第一阶段失败、第二阶段成功目前也会被折叠。
- 独立复核：review_a001_h 独立确认两段 error/cancel 最终落 nil→Handler 统一“不存在”，Home 仍回退并导航；同时收窄首段失败但 fallback 成功不构成用户缺陷，维持 P3。Home 对真正无匹配是否仍需信息提示属于产品意图，不能由静态审计代定。
- 修复记录：`recognizeTmdbId` 改为 `async throws -> Int?`：失败/取消抛出（首段失败暂存、兜底也失败时抛首段原始错误，取消优先），nil 仅表示两阶段成功完成后的真正 no-match，会话变化按取消处理。`MediaActionHandler.getTMDBJumpTarget` 空标题直接返回不弹提示，网络/后端失败不再弹"媒体不存在"，仅真 no-match 弹；`MediaPreloader` 预加载识别用 `try?` 静默。已补 3 条回归测试（双段失败抛错不伪装 no-match / 首段失败兜底成功返回 ID / 双段无匹配仍返回 nil），现有 4 条识别测试与 2 处兼容测试同步 throws 签名。验证：tvOS Simulator build 通过；`TmdbRecognitionPositiveIDTests` 7/7、`APIServiceCompatibilityEndpointTests` 29/29；全量 621 用例仅已知 SSE 时序用例失败。
- 当前缺口：历史空白详情页修复（空详情响应重试）和识别结束转圈修复与本项 outcome 分流不是同一问题。 后端 `/media/search` 以 `[]`、`/media/recognize` 以空 Context 表示成功无匹配，请求异常通过非 2xx/抛错表达，Web 也用 try/catch 区分。**下列「首段失败 + 兜底无匹配」的组合缺口已于 2026-09-12 修复，见下方「本轮修复」。**后端 `/media/search` 以 `[]`、`/media/recognize` 以空 Context 表示成功无匹配，请求异常通过非 2xx/抛错表达，Web 也用 try/catch 区分。当前实现仍会在首段 `/media/search` 失败、fallback `/media/recognize` 200 但无匹配时返回 nil，把不完整查询误报成确定 no-match；本轮按用户要求只确认并记录，不修改代码。

- 🆕 本轮修复（2026-09-12，用户决定修）：**「首段 `/media/search` 失败 + 兜底 `/media/recognize` 200 但无可用 ID → 返回 nil」这一处残留折叠已闭合。** 原实现把首段错误存进 `firstStageError` 后继续兜底，但兜底「成功却给不出 ID」时会直接落到函数末尾 `Logger.info("识别失败")` + `return nil`，**把暂存的错误丢弃** —— 调用方据此断言「确定无匹配」并弹出「媒体不存在」，而实际上一次完整查询都没完成过（典型场景：Wi-Fi 切换 / DNS 抖动导致首段超时，兜底连通但认不出该片）。
- 修复实现（3 行）：在末尾 `return nil` 之前加 `if let firstStageError { throw firstStageError }` —— 只要首段失败过，就不允许把「查询没做完」伪装成「真无匹配」；抛出后由 `MediaActionHandler` 的 `catch` 分支按「识别失败」处理（`Logger.error` + 返回 nil，**不弹**误导提示）。真正的 no-match（两段都成功、都没有结果）仍返回 nil，不受影响。
- 有意不改的一处：兜底「识别出来了但**类型不符**」仍 `return nil`（视作拒绝该结果）。该分支基于一次**成功**的兜底查询，属合理的否定判定，不属于「查询没做完」。
- 验证：新增 2 条用例 —— `testSearchFailureThenFallbackNoMatchThrowsInsteadOfReturningNil`（首段 500 + 兜底空结果）、`testSearchFailureThenFallbackMissingIdThrowsInsteadOfReturningNil`（首段 500 + 兜底返回 0 号无效 ID）。定向 10/10；**反向验证**：撤掉这 3 行、保留全部用例 → **2 挂 / 7 过**，7 条阴性对照中含 `testBothStagesNoMatchStillReturnsNil`（真无匹配仍返回 nil）与 `testSearchFailureThenFallbackSuccessReturnsId`（首段失败但兜底成功仍返回 ID），二者在改动前后必须不变。全量 **959/959 通过、零失败**（957 + 2），逐名比对零用例消失。
- 🆕 同轮第二处修复（用户裁决「按 A 改」）：**Home「搜索资源」不再弹「未识别到此媒体的TMDB信息」。** 该按钮（`HomeView.swift:295`）在**真 no-match** 时本就会走 `else` 分支用标题兜底导航、动作照样完成，但因为它复用了为「TMDB详情页」写的 `getTMDBJumpTarget`，连带继承了 `showTMDBNotFoundAlert = true` 这一副作用，全局弹窗（`ContentView.swift:105` → `MediaActionModifier`）随之弹出 —— 同一动作**同时**产生 alert 与 navigation，用户被一个必须点「确定」的模态框拦在一个已经自愈完成的动作上。
- 该按钮起初看不出与被识别结果的关联，此处记录其真实依赖：`searchResourcesTarget` 用 `keyword: item.apiMediaId ?? ""` 构造请求，而 `apiMediaId` 取自 `identity.mediaKey`（形如 `tmdb:12345`）；HomeView 现造的 `info` 只带 title/type/year，故**必须**先识别出 TMDB ID 才能构造正常搜索请求，识别失败才退回标题搜索。即弹窗描述的事实无误，问题在于它拦得没有道理。
- 修复实现：`getTMDBJumpTarget` 增加 `notifyWhenUnrecognized: Bool = true` 形参，仅在 `true` 时置 alert；Home「搜索资源」传 `false`。**默认值保持 `true`**，另三个「TMDB详情页」入口（`HomeView.swift:277`、`MediaContextMenu.swift:47`、`MediaDetailView.swift:908`）行为不变 —— 用户以 TMDB 为目标时找不到就该告知。
- 验证：新增 `TMDBJumpAlertPolicyTests` 3 条（默认弹 / 传 false 不弹 / 已有 ID 不弹）与 `TMDBJumpAlertCallSiteTests` 2 条（源码守卫：Home「搜索资源」传 false 且「TMDB详情页」保持默认，另两个入口不得出现该参数）。定向 5/5；**反向验证**：同时撤掉形参开关与调用点传参、保留全部用例 → **2 挂 / 3 过**，3 条阴性对照为 `testUnrecognizedMediaNotifiesByDefault`、`testResolvedIdNeverNotifies`、`testOtherTMDBJumpEntryPointsKeepDefaultNotification`。行为用例走的是「标题经季数清洗后为空→不发网络请求」的早退路径，避免依赖 URLProtocol（`APIService.shared` 在 init 时复制配置，测试桩只对隔离实例生效）。全量 **964/964 通过、零失败**（959 + 5），逐名比对零用例消失。