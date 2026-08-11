# 订阅兼容检查清单建议

本文件只记录对 `docs/subscription-compatibility-checklist.md` 的建议，不直接修改正式清单。

## 状态与编号

- 编号：`CHK-001`、`CHK-002`……
- 状态：`候选`、`已确认`、`已驳回`、`未验证`。
- 只收录以后同步 MoviePilot 后端或 Web 前端时可重复使用的契约和检查点；一次性 Bug、临时修复过程和纯实现细节不进入本表。

## 建议总表

| ID | 状态 | 动作 | 对应章节/条目 | 建议摘要 | 来源审查单元 | 独立复核 | 跨端证据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CHK-001 | 已确认 | 新增 | `TV 端更新时重点检查 / Models、SubscribeSeasonViewModel、SubscribeSeasonView` | 仅明确非负季号可建立身份；缺失/null/负值不得折叠为 S00 | M001-C/I001 / F-003 | verify_m001_c 与 I001 确认值得长期保留且无重复 | TV 安全不变量已确认；上游过滤/拒绝策略未验证 |
| CHK-002 | 已确认 | 删除错误现状声明 | `媒体 ID 归一化契约`、`TV 端更新时重点检查 / Models` | 当前Web/后端不支持仅legacy `mediaid`的`MediaInfo`；正式清单不得声称TV当前有此回退 | M001-A/M001-D/I001→当前Web/后端合同复核 / F-013 | Web v2.15.5类型、身份helper、四类入口及后端响应schema共同反证 | F-013驳回；不新增TV差异化兜底，用户决定跳过修复 |
| CHK-003 | 已确认 | 已落实到正式清单 | `TV 端更新时重点检查 / Models、APIService、CRUD 编辑` | 所有强类型载荷及GET→完整PUT/POST更新必须与当前后端可写schema逐字段对账；上游新增字段时明确选择建模、按契约保留原始值或阻止不安全更新，禁止静默丢字段，也禁止盲目回传系统/运行字段 | M001-D/I001/A001-J/A001-K/V018/G02→当前上游复核 / F-011/F-069 | 当前F-011确认已声明下载字段丢失；F-069补充完整对象更新的未来字段窗口；订阅当前可写字段已覆盖 | Web请求体、后端可写/排除字段与TV编码三端必须同时核对；未知extra仅在明确round-trip契约下保留 |
| CHK-004 | 已确认 | 更新 | `跨源详情页 Header 契约` | `canDirectlySubscribe == false` 不能推导为电视剧，只有明确电视剧进入分季 | M001-D / F-015 | verify_m001_d 确认三条入口及第三类缺口 | TV 二值分类缺陷已确认；上游类型集合/策略未验证 |
| CHK-005 | 已确认 | 新增/补强 | `用户权限契约风险`、`TV 端更新时重点检查 / APIService` | 请求、登录/重登、settings、mutation、profile异步、高层多await动作、子Paginator及长期根页route/focus/受限快照须绑定单调session epoch；重登重验权限，多阶段/批量动作共用owner | B004/M001-H/A001-B/A001-E/A001-K/V002-D/V005/V007/V009-C/V011-C/W006-B/W014/W015/W018-A/W020-A/C/F/R001 / F-027…F-029/F-113/F-123/F-130/F-193 | 既有双审及W018-A独立复核确认；W020与R001补强根设置/媒体状态传播 | TV会话/权限不变量、当前Fork/整理链与根页面传播已确认；后端业务权限契约待产品明确 |
| CHK-006 | 已确认 | 更新/合并 | 并入正式清单现有超级用户/多记录取消条目与 TV 更新检查 | 取消入口使用明确动作词/destructive语义；媒体级删除应说明owner/命中数/实际范围 | B007/I001/C014/W013-B / F-047/F-048/F-124 | 当前后端已对所有身份按season筛选，旧跨季证据失效；同季多记录范围仍存在但Web共享相同行为 | F-047/F-048由用户决定跳过，不做TV单端精确ID增强；F-124已由`4a1a291`落实冻结展示意图与destructive确认 |
| CHK-007 | 已确认 | 新增 | `订阅缓存与刷新契约`、`TV 端更新时重点检查 / APIService` | 三类分季/剧集组缓存须绑定发起时session namespace，切会话清理且旧请求不得回填新owner | M001-F/G02 / F-065 | 既有双审与G02 clean-room复核确认cache/in-flight跨服回填可进入订阅payload | TV缓存边界已确认；真实跨服数据差异频率未验证 |
| CHK-008 | 已确认 | 更新/合并 | 并入正式清单现有 Subscribe schema 与 TV Models 检查 | 持久订阅快照须有唯一正业务 ID，巡检不得跳过异常记录 | M001-F/I001 / F-068 | verify_m001_f_retry 与 I001 确认 ID/焦点/动作与巡检盲点 | TV ID 不变量已确认；坏记录策略未验证 |
| CHK-009 | 已确认 | 更新/合并 | 并入正式清单现有订阅分享、Models 与 APIService 检查 | 分享列表须有唯一正业务ID；GET→Fork保留当前schema的`bangumiid/anilistid/media_source/media_id`并投影全部主身份；未知extra不要求raw透传；确认页展示立即生效的非空keyword/custom_words | M001-I/I001/W015 / F-077/F-078/F-079/F-194 | 当前后端91ce365f与Web 7ea14bc9确认三项新增字段及Bangumi合同；W015双审确认两个关键规则 | 当前身份/Fork字段已确认；其他配置是否必显仍未验证 |
| CHK-010 | 已确认 | 更新 | `订阅缓存与刷新契约`、`TV 端更新时重点检查 / APIService` | 同键较新强刷后，旧 miss/force 不得写缓存或返回旧值，旧调用者复用最新结果 | A001-J/V004-A / F-100 | verify_a001_h 确认缓存与调用者双重回滚、详情 ready 后视图强刷与预加载普通检查的生产重叠、sliding TTL 及 snapshot revision 对照 | TV latest-wins 不变量已确认；TTL 产品选择与真实频率未验证 |
| CHK-011 | 已确认 | 更新/合并 | 并入正式清单现有 `search.py / chain/search.py / indexer` missingSites 条目 | 资源 SSE 按空行组帧并以换行拼接多条 data；仅明确成功终止可进入受限 missingSites 补偿 | A001-H / F-080/F-101 | verify_a001_h 确认 framing、终止与补偿边界并收窄为资源搜索 | TV parser/终止/补偿链已确认；当前 Web/后端 framing 与站点错误结构未验证 |
| CHK-012 | 已确认 | 新增 | `下载任务权限与身份契约`、`TV/后端更新重点检查` | list/start/stop/delete必须按token subject校验owner；任务身份与owner查找包含downloader，superuser/API Token例外显式化 | W016/W017 / F-192/F-095 | review_a001_j与review_a001_h独立确认TV无过滤、后端token-only端点、Web过滤及跨下载器hash边界 | 当前本地跨端授权缺陷已确认；部署版本与API Token产品策略未验证 |
| CHK-013 | 已确认 | 新增 | `订阅编辑三态与更新幂等契约`、`TV 端更新重点检查 / Models、SubscribeSheet` | total_episode保留null/0/正数及既有manual语义；未修改保存幂等，只有显式修改才改变人工语义 | W014 / F-199 | review_a001_j与review_a001_h独立确认长期价值、测试矩阵及与正式清单不重复 | TV/Web/当前后端链已闭合；真实NULL分布与部署版本未验证 |
| CHK-014 | 已确认 | 新增 | `订阅保存路径契约`、`TV 端更新重点检查 / SubscribeSheet` | nil表示自动；非空为API-ready本地/远程根或子路径，编辑器原样保留既有值并可清空 | W014 / F-200 | review_a001_j与review_a001_h独立确认路径值域、storage URI及与正式清单不重复 | TV/Web/当前后端路径与allowlist已闭合；真实远程目录频率未验证 |
| CHK-015 | 已确认 | 新增 | `下载删除数据范围与危险动作确认`、`TV/后端更新重点检查` | 删除任务与永久删除文件为两个显式动作；默认只删任务，永久删除单独确认不可撤销范围 | W017 / F-196 | review_a001_j与review_a001_h独立确认该合同不被CHK-006/012覆盖及适配器测试矩阵 | 当前TV/Web/后端危险默认已闭合；其他下载器与部署版本未验证 |
| CHK-016 | 已确认 | 已落实到正式清单 | `未完成下载状态可见与可恢复契约`、`TV/Web/后端更新重点检查` | 列表保留全部未完成paused/stopped等状态并排除已完成项；stop后轮询仍可见且可继续 | W017 / F-197 | review_a001_j与review_a001_h独立确认跨下载器状态×completed矩阵及长期价值 | 用户决定不做TV单端修复；正式清单跟踪MoviePilot官方后端/Web变化后同步对齐 |
| CHK-017 | 已确认 | 新增 | `Mutation 2xx 响应契约`、`TV 端更新重点检查 / APIService` | mutation仅接受端点声明的合法envelope；畸形、非对象或缺success的2xx失败关闭，空响应仅按显式no-content合同接受 | W017/G03 / F-083/F-245 | 下载与Fork不同decoder/端点分别获独立确认；须端点级声明且不能用全局空body fallback | TV fail-open生产链已确认；各端点空body/204及Fork成功envelope正式合同未验证 |
| CHK-018 | 已确认 | 新增 | `资源搜索站点权威域与默认语义`、`TV/Web/后端更新重点检查` | 搜索站点列表来自active searchable权威域；default/all/specific三态不得用同一空sentinel混淆 | W020-D / F-209/F-210 | review_a001_h建议保留，verify_a001_h第三裁决确认一条清单共同验收两个独立P2 | 当前TV、Web、后端本地快照已核对；执行模块细节、部署配置与远端最新性未验证 |
| CHK-019 | 已确认 | 新增/补强 | `媒体搜索来源请求与响应语义`、`TV/Web/后端更新重点检查` | source必须由后端声明允许值并真实执行；兼容测试断言provider/返回来源语义，不能只检查URL含query | W001/W012/W018-A/W020-D / F-189 | 既有多段确认参数被忽略；verify_a001_h第三裁决确认正式长期合同与测试价值 | 当前TV/后端本地快照已核对；实际启用来源、AniList值域与远端最新性未验证 |
| CHK-020 | 已确认 | 新增 | `服务端 manage 资源授权`、`TV/Web/后端更新重点检查` | manage-only UI对应的每个读取与mutation端点都必须由后端在返回/执行前校验active manage用户；客户端菜单/路由门禁不能代替资源授权 | G09 / F-246 | 两张独立源码票确认GET整理历史仅验token；全新clean-room窄裁确认必须独立于session epoch清单长期保留 | 当前本地TV/Web/后端链已核对；部署版本、API Token产品策略与真实低权限账号频率未验证 |

## 建议详情

### CHK-001：分季季号有效性

- 状态：已确认
- 建议内容：`TV 端只有在 season_number 为明确非负整数时，才可建立分季身份并参与焦点、状态索引及订阅/取消；缺失/null/负值不得用 0 代入或当作合法季，真实 0 才表示 S00。非法条目应过滤还是令整批失败，必须随目标 Web/后端契约核对。`
- 复用价值：后端版本、第三方来源或插件放宽季模型时，nil→S00 会直接改变订阅身份和删除目标。
- 相关测试/文件：`MediaInfoCollectionBehaviorTests`、`SubscribeSeasonContentViewTests`、`BackendCompatibilityTests` 的季入口、`APIService.getMediaSeasons/getGroupSeasons`、`SubscribeSeasonViewModel`、`SubscribeSeasonView`。
- 当前限制：独立复核已完成；上游字段保证以及过滤单条/拒绝整批策略未验证。

### CHK-002：`MediaInfo` legacy 身份现状声明

- 状态：已确认
- 建议内容：删除正式清单中“当前`MediaInfo`已回退legacy `mediaid`”的错误现状声明；当前Web/后端只支持结构化身份，不给TV新增差异化兜底。
- 当前证据：官方Web v2.15.5的`MediaInfo`类型与身份helper均不读取legacy字段，详情/搜索/下载/订阅入口现场生成`source:id`；当前后端响应schema也无该字段。
- 相关测试/文件：`Models.swift`、全部 MediaInfo 解码入口、`MediaInfoCollectionBehaviorTests`、`BackendCompatibilityTests`、I001。

### CHK-003：强类型载荷与完整对象更新保真

- 状态：已确认
- 建议总则：对后端schema已声明、由上游生产且在当前业务链消费的字段，TV强类型解码再编码不得静默删除；F-011当前实例是`TorrentInfo.site_cookie/site_ua/site_proxy/site_downloader`。
- 完整更新检查：对任何“GET对象→用户编辑→完整PUT/POST对象”的接口，每次同步Web或后端版本时必须逐字段核对Web实际请求体、后端当前可写schema/排除字段、TV `CodingKeys`与最终编码body。后端新增可写字段时，必须明确采用以下之一：TV同步建模；按端点round-trip合同保存原始值并仅覆盖已编辑字段；或在适配前阻止可能破坏数据的更新。不得默认忽略后继续完整更新。
- 写入边界：原始值保留只针对端点明确允许回写的业务字段；后端派生字段、运行状态、owner、下载事实等必须遵守写入allowlist，不得为“兼容”而盲目全量透传。若后端支持PATCH/dirty-field更新，优先按正式合同只提交实际编辑字段；不得由TV自行假设PATCH语义。
- 原形边界：未知子键与嵌套原形只在实际API/插件合同证实需要透传时保留，不把清单扩大成所有模型通用raw-shadow或字节级保真框架。
- 最小验收：对完整对象更新至少覆盖“新增可写字段在无关编辑后仍保留”“后端排除的运行字段不会被回写”“absent/null/default不因TV重编码意外互换”三类聚焦合同；不要求为所有未知字段建立通用动态模型。
- 当前证据：2026-08-08 核对当前官方 Web/后端后，F-011 已确认前三个字段进入种子/字幕请求，`site_downloader`在`/download/add`且顶层下载器为空时参与选择；Web直接透传，TV确定丢失。A001-K/V016确认实际请求出口。
- 完整更新证据：当前订阅后端以明确的公共写入allowlist/exclude集合处理完整PUT，TV已覆盖当前全部可写字段；Web保存GET得到的动态对象。F-069当前不构成现行字段缺失，但它固定了升级检查：后端以后新增可写字段时，TV不得在未建模、未保留且未阻止更新的情况下继续完整PUT。
- G02复核边界：既有复核确认 `MediaInfo` 非nil typed字段会覆盖同名raw、nil typed保留raw，且已建模嵌套对象未知子键可能丢失；但当前官方核心未发现对 genre/country/season/person/share 未知子键的消费者，插件依赖仍未验证。数字词法、极端数值及通用嵌套原形不作为当前修复门槛。
- 相关测试/文件：`Models.swift`、`MediaInfoCollectionBehaviorTests`、`SubscribeSeasonContentViewTests`、AddDownload/API 请求体捕获。

### CHK-004：非电影类型订阅入口

- 状态：已确认
- 建议内容：`canDirectlySubscribe == false` 不能直接推导为电视剧；只有明确电视剧才能进入分季流程，其他类型应隐藏或禁用订阅入口。
- 当前证据：M001-D 主审与 verify_m001_d 独立复核已确认三条入口；I001 维持该边界。
- 相关测试/文件：`MediaContextMenu`、`SubscriptionHandler`、`MediaDetailView`、`PermissionBehaviorTests`、`MediaDetailViewHeaderActionTests`。

## 各审查单元适用性记录

| 审查单元 | 主审适用性/结论 | 独立复核 | 最终动作 |
| --- | --- | --- | --- |
| M001-B | 适用；现有条目保持；F-001 是通用解码边缘，不新增建议 | 已闭环；同意主审 | 保持/无新增 |
| M001-C | 适用；现有条目保持；CHK-001 已确认 | 已闭环；I001 补充负季号边界 | 新增 CHK-001 |
| M001-A | 适用；F-006/F-007/F-008 已由现有 zero/fallback、统一身份和搜索刷新条目覆盖；F-012/F-013 已按最终状态收口 | 已闭环；同意主审并收窄 F-007 | 保持/无新增；相关条件性边界已在后续单元闭合 |
| B001 | 适用；运行时最低兼容版本与 README/正式清单/测试均为 v2.15.1；F-009/F-010 是通用版本逻辑，不新增 | 已闭环；同意主审 | 保持/无新增 |
| M001-D | 适用；F-011后经当前上游复核收窄为TorrentInfo字段丢失并补强CHK-003，F-013形成CHK-002，F-015形成CHK-004 | 已闭环 | CHK-002确认删除错误现状声明；CHK-003/004 已确认 |
| B002 | 条件适用；F-016/F-018/F-021 不属于订阅契约，F-017 涉及订阅/分享日期字段但上游时区契约缺失 | 已闭环 | 暂无 CHK；若上游确认字段时区规则再新增/更新 |
| B003 | 不适用；常规图片 Cookie/Kingfisher 会话隔离属于 G03/G06，不是订阅契约 | 已闭环；同意不适用 | 无清单动作 |
| M001-E | 条件适用；站点/下载器/目录进入订阅编辑，但 F-022…F-025/F-021/F-032 与现有订阅契约无新增关系 | 已闭环 | 保持/无新增 |
| M001-F | 适用；现有主身份、episode_group、取消与刷新条目保持；CHK-007/CHK-008 已确认，CHK-002后经当前合同确认删除错误现状声明 | 已闭环；独立复核完成 | CHK-002/007/008 已确认；其余保持 |
| M001-G | 条件适用；AddDownload `media_in` 的人物/头像嵌套原形仅在真实合同要求时由 CHK-003 覆盖，当前消费依赖未验证；F-064 与职位/头像展示属于 G07 通用模型边界 | 已闭环；独立复核完成 | 保持 CHK-003/无新增 |
| M001-H | 条件适用；权限/设置与资源入口沿用现有条目，F-070…F-072 是本地能力三态与转移生命周期问题 | 已闭环；独立复核完成 | 保持/无新增；F-027 settings 证据由 CHK-005 覆盖 |
| M001-I | 适用；分享权限、刷新、session、模型保真与跨源身份均命中正式清单；CHK-009 已确认 | 已闭环；独立复核完成 | CHK-009 补强；CHK-003/005 保持 |
| M001-J | 条件适用；媒体 ID/权限只作整理边界参照，F-073…F-076 是 G09/G01 本地状态与反馈问题 | 已闭环；独立复核完成 | 保持/无新增；F-027 会话证据由 CHK-005 覆盖 |
| M001-K | 条件适用；超管自定义规则权限沿用正式条目，F-080/F-081/F-061/F-085 属通用 SSE/过滤实现 | 已闭环；独立复核完成 | 保持/无新增 |
| A001-A | 适用；会话与分季缓存继续由 CHK-005/CHK-007 覆盖，F-082…F-084 是通用响应/图片实现问题 | 已闭环；独立复核完成 | 保持/无新增；CHK-005/CHK-007 获独立支持 |
| A001-B | 适用；强支持并补强 CHK-005/CHK-007，F-086…F-088 属本地 URL/错误/表单边界 | 已闭环；独立复核完成 | CHK-005 补强、CHK-007 保持；无新 CHK |
| A001-C | 适用；继续支持 CHK-005，F-087/F-088 已确认，F-089 经 G06 按当前后端 401 合同确认 P2 | 已闭环；独立复核完成 | CHK-005 保持/补强；无新 CHK |
| A001-D | 适用；支持 CHK-002/CHK-005，F-090 已确认但由正式清单现有 raw 0/有效 ID 条目覆盖 | 已闭环；独立复核完成 | CHK-002确认删除错误现状声明、CHK-005 保持；无新 CHK |
| A001-E | 适用；下载暂停/恢复/删除及 401/403 自动重登重放继续受 CHK-005 的 session epoch 约束；F-095 的同会话客户端代际是本地实现边界，不并入 CHK-005 | verify_a001_e 与 verify_f095 均已闭环 | CHK-005 仅补充跨会话下载 mutation 证据；无新 CHK |
| A001-F | 条件适用；F-098 是 AI 批量受理反馈，F-099 是本地手动媒体正 ID/fallback 边界，均不形成新的跨端订阅契约 | verify_a001_f 已闭环 | 保持现有媒体 ID 与 CHK-005 条目；无新 CHK |
| A001-G | 适用；F-096 由正式清单现有“可选状态探测不得自动登出”覆盖，F-027 跨会话响应由 CHK-005 覆盖；F-097 属本地轮询/焦点实现 | verify_a001_g 已闭环 | 保持现有条目与 CHK-005；无新 CHK |
| A001-H | 适用；涉及资源 SSE、权限、媒体 ID、API/Model 与后端升级；F-080/F-101 已确认，F-102/F-103 属 TV 实现边界不单列清单项 | 主审与独立复核均完成 | CHK-011 已确认，修订并合并既有 missingSites 条目；上游 framing/终止/补偿契约未验证 |
| A001-J | 高度适用；继续支持 CHK-001…010，并确认同键强刷 latest-wins 与完整对象升级门禁；F-067 等本地实现缺陷不进入清单 | 主审、独立复核与G02 clean-room末裁完成；当前合同复核将F-069降为未来兼容P3，F-100已由`0cfeb12`修复 | CHK-003已落实F-069未来字段验收；CHK-010保留F-100回归；CHK-002确认删除错误现状声明，F-079补强CHK-009 |
| A001-I | 部分适用；站点、目录、过滤规则进入订阅编辑，F-104 的完整媒体键路径边界补强既有媒体 ID 契约；人物 ID 属通用 API 实现边界 | 主审与独立复核均完成，F-104 确认条件性 P2 | 更新既有媒体 ID 条目并保持 CHK-005/公开及超管配置条目；无新 CHK |
| A001-K | 添加下载 mutation 与 `media_in` 载荷高度适用，F-105/F-106 属 G03 通用图片边界 | 主审与独立复核均完成；F-105 确认 P3、F-106 确认 P2 | 补强 CHK-003 的 AddDownload 出口及 CHK-005 的 add mutation；无新 CHK |
| S005 | 局部适用；正式清单已覆盖 CustomFilterRules 超管权限，非超管请求前返回且入口隐藏；规则语法、坏项与排序属于通用过滤实现 | 主审与独立复核均完成；F-060/F-061/F-081/F-085 维持，F-110 经下游确认 P2 | 保持现有“普通用户不得预取和应用自定义规则”条目；无新 CHK |
| V001 | 条件适用；取消失败继续复用现有错误通知，但通知生命周期属于 TV 呈现边界 | 主审与独立复核完成；F-107 原P1主触发已修复，剩余P2由用户决定跳过；F-108 未验证，H-012 已确认 | CHK-006 保持；成功静默、来源失效与通知去重不新增 CHK |
| V002-A | 条件适用；自动搜索设置只影响 TV 新订阅行为，F-109/F-111 是本地偏好隔离，既有会话/刷新问题由 CHK-005 覆盖 | 主审与独立复核完成；F-109/F-111 已确认 | 保持现有手动搜索刷新条目与 CHK-005；无新 CHK |
| V002-B | 条件适用；profile/Keychain/过滤选择属 TV 本地一致性，跨会话 relogin/logout 继续由 CHK-005 覆盖 | 主审与独立复核完成；F-109/F-111 已确认 | 保持 CHK-005 与既有普通用户规则权限条目；无新 CHK |
| V002-C | 条件适用；站点/规则权限前后双检查正确，F-112 属 TV 本地站点状态，异步 session 传播继续由 CHK-005 覆盖 | 主审与独立复核完成；F-112 已确认 | 保持 CHK-005、站点权限与普通用户规则权限条目；无新 CHK |
| V002-D | 条件适用；F-113 为本地 profile 会话归属，直接补强 CHK-005，F-109/F-111/F-112 不新增跨端条目 | 主审与独立复核完成；F-113 确认条件性 P2 | 补强 CHK-005 的 profile-scoped 异步归一化发布/返回；无新 CHK |
| V003 | 条件适用；站点请求前后 search 权限门正确，F-114 属本地 SwiftUI 观察，session ABA 继续由 CHK-005 覆盖 | 主审与独立复核完成；F-112 仅传播，F-114 已确认 | 保持站点权限条目与 CHK-005；无新 CHK |
| V004-A | 条件适用；详情预加载的订阅状态双写直接支持 CHK-010，F-115/F-116/F-117 属本地 ready/首帧/图片取消边界 | 主审与独立复核及后续G03纠偏完成；F-115/F-116 P2、F-117 P3，F-116可见时长仍待运行 | 补强 CHK-010 的生产调用证据；保持 CHK-005，无新 CHK |
| V004-B | 条件适用；全局预加载缓存直接传播 CHK-005/CHK-010，F-118/F-119 属本地 pin/alias 一致性 | 主审与独立复核及G03窄第三裁完成；F-118/F-119均确认P2，F-118端到端生命周期仍待运行 | 保持 CHK-005/CHK-010；无新 CHK |
| V005 | 条件适用；资源动作的默认站点与多阶段识别传播会话归属，F-122/F-123 属 TV 高层动作/错误语义 | 主审与独立复核完成；F-122 确认 P3，F-123 确认条件性 P2 | CHK-005 已补强：用户动作从按钮起点跨多次 await、全局 UI 写入及最终导航绑定单调 session epoch；无新 CHK |
| V006 | 条件适用；取消、刷新、分享身份与 mutation 传播现有条目，F-120/F-121 属本地 owner 状态；F-124 的取消分支仍受 CHK-006 | 多轮复核与G02末裁完成；F-120后续降P2且用户决定跳过，F-121 P2；F-124 P1已由`4a1a291`修复，聚焦5/5、完整本地450/450与独立复审PASS | 保持 CHK-005/CHK-006/CHK-009/CHK-010；不因已跳过的F-120新增CHK |
| V007 | 适用；首次登录直接建立/替换 session，既有会话、凭据、通知与异步 action finding 均在此传播 | 主审与独立复核完成；无新增 finding，F-089 最终确认 P2，F-123 仅传播 | CHK-005 已补强 login acquisition owner、单调 epoch 与 A→B→A；无新 CHK |
| V008 | 条件适用；Home 直接消费订阅、媒体服务器与 mutation 契约，F-125 涉版本特定 Plex link，F-126…F-128 属本地状态/确认/反馈 | 主审与独立复核完成；F-125/F-128 确认 P3、F-126 确认 P2；F-127 确认条件性 P1 后由用户决定跳过 | CHK-005 补充 Home 周期刷新/mutation/确认期间 owner；保持 CHK-006/CHK-008/CHK-010，无新 CHK |
| V009-B | 适用；Explore 分享投影/列表身份直接传播 F-077/F-078/CHK-009，F-129 属本地 Popular 去重与 SwiftUI ID 一致性 | 主审与独立复核完成；后续G01/G04将F-129升P2 | 保持 CHK-009 与现有分享 ID 条目；无新 CHK |
| V009-C | 适用；来源可见性/旧 Paginator 与权限变化直接命中现有权限/session 条目，F-130 属 TV 本地权限派生收敛 | 主审与独立复核完成；后续G04将F-130升P1并吸收F-244；`90b40b4`已用统一UI identity、runtime取消与缓存失效闭合，聚焦96/96和既有独立复审PASS | CHK-005 保持“权限发布后立即收敛当前来源/列表/Paginator”；统一根机制已落实，无新 CHK |
| V009-A | 条件适用；动态来源/插件过滤会话与权限传播现有条目，F-133…F-135 属条件性插件 UI/query/option 边界 | 主审与独立复核完成；F-133/F-134 未验证 P3，F-135 已确认 P3，F-088 条件扩展 | 保持 CHK-005 与现有插件来源/权限条目；固定 fixture 到位时重开 F-133/F-134，不新增 CHK |
| V009-D | 条件适用；内置来源筛选字典不改变订阅模型契约，F-131/F-132 属 TV locale 与请求状态 | 主审与独立复核完成；后续G05将F-131升条件P2，F-132维持P3，其余完整性通过 | 保持现有来源/筛选条目；无新 CHK |
| V009-E | 条件适用；Share/Popular/Custom 路径传播分享身份、session 与 query 契约，F-136 属默认产品行为 | 主审与独立复核完成；F-129/F-131/F-132 已确认，F-134/F-136 因部署 fixture/产品意图缺失转未验证 | 保持 CHK-005/CHK-009；固定证据到位时重开，无新 CHK |
| V009-F | 适用；分页/刷新/分享投影直接传播权限、session、响应与 CHK-009，插件/默认行为均已最终处置 | 主审与独立复核完成；无新编号，F-129/F-130 与 F-132 同根扩展确认，F-133/F-134/F-136 未验证，F-135 已确认 P3 | 保持 CHK-005/CHK-009；无新 CHK |
| V010 | 条件适用；推荐分页/session/身份/图片与动作直接传播既有条目，F-138/F-139 属共享身份与本地成功空恢复 | 主审与独立复核完成；后续G01/G04将F-138升条件P1、F-139升P2 | 保持 CHK-005/CHK-010；共享身份在既有模型边界、成功空以现有激活边沿收敛，不新增 CHK |
| V011-A | 条件适用；搜索声明传播权限、身份与结果消费，F-137 属本地评分带，权限 focus 风险转 V011-C | 主审、独立复核与G04 clean-room末裁完成；F-137升条件性P2，枚举/wrapper身份其余通过 | 保持 CHK-005；评分只做本地带宽修复，不新增评分 CHK |
| V011-B | 条件适用；最佳结果直接传播模型/分享/响应身份，F-140/F-141 属本地 query 规范化与年份词法 | 主审与独立复核完成；F-137/F-140/F-141 已确认，F-138 获 Search 独立生产链 | 保持 CHK-005；请求/评分共用 canonical query，不新增 CHK |
| V011-C | 适用；搜索编排直接消费权限/session/SSE/Paginator owner，F-035/F-039/F-076/F-080 等均为既有机制传播 | G04 clean-room末裁收窄显式cancel反证并将F-035/F-039升P2；权限热切换并入F-130 | CHK-005补Search session owner/aggregate cancel与A→B→A；保持CHK-011，页面离场产品语义待运行验证 |
| V011-D | 适用；四类 Paginator/分享投影直接传播 session、身份、错误、取消与 CHK-009，F-138/F-036 属共享 ID/processor 根因 | 主审与独立复核完成；F-036确认，F-138 title-only核心确认、collection_id机制成立但生产输入未验证 | 保持 CHK-005/CHK-009；固定上游合集 fixture 到位再收敛 collection_id，不新增 CHK |
| V011-E | 条件适用；自定义规则直接消费 profile/权限/session 与响应契约，规则 fail-open 已有正式条目 | 主审与独立复核完成；无新编号，F-081/F-085/F-082/F-109/F-111 等传播 | 保持 CHK-005 与自定义规则清单；无新 CHK |
| V011-F | 适用；共享真实请求直接传播 session owner、取消、空批终页与身份契约 | 主审、复核与第三代理裁决完成；F-142 确认条件性P2，F-034/F-039维持独立 | 保持 CHK-005；在现有 actor/Paginator 内按 task identity退休handle，不新增 CHK |
| V012-A | 适用；详情/预加载直接消费权限、session、缓存、图片和分页契约，F-100/F-130/F-138/F-139 为既有根因扩展 | 主审与独立复核完成；F-138 task/season/lifecycle alias成立，wrong fullDetail注入收窄未验证；后续G03将F-116/F-118均确认P2并保留运行边界 | CHK-005 补详情分季/站点 gate 热收敛，保持 CHK-007/CHK-010；运行项不新增 CHK |
| V012-B | 适用；详情 Header/取消直接消费订阅身份、取消范围、session、正 ID、缓存 latest-wins | 主审与独立复核完成；无新编号，F-006/F-007/F-047/F-048/F-049/F-100/F-119/F-120 等生产链闭合 | F-047/F-048与Web一致并由用户跳过；其余CHK-005/008/010及结果出口建议维持 |
| V012-C | 适用；取消确认/目标解析直接决定 CHK-006 的 owner/count/scope、模式与冻结时点 | 主审与独立复核完成；F-047/F-048确认，电影入口/电视剧统计/AniList fallback/测试入口错位 | F-047/F-048不做TV单端不可变intent增强；保持CHK-005/008/009 |
| V014 | 条件适用；合集详情直接传播 session、错误、成功空与共享身份，collection_id语义缺固定payload | 主审与独立复核完成；F-138 identity/inert-task与F-139成功空扩展成立，wrong-detail/part误路由维持未验证 | 保持 CHK-005；固定search/parts fixture到位再裁决collection_id，不新增CHK |
| V013 | 条件适用；人物详情直接传播session、分页/图片/响应身份，F-143/F-144属本地route owner与启动顺序 | 主审与独立复核完成；F-143/F-144均确认P2 | 保持CHK-005；人物route owner复用现有身份规范化，并发复用async let，不新增CHK |
| V015 | 适用；资源搜索直接消费 session、权限、SSE terminal/framing、过滤、query 与结果身份契约 | 主审与独立复核完成；无新编号，F-022/F-032/F-061/F-076/F-080/F-081/F-082/F-085/F-101/F-103/F-130 等获生产链 | 保持CHK-005/CHK-011；terminal/framing共享单点收敛；补偿合并须断言Context.id唯一，固定重叠fixture到位再重开身份finding |
| V016 | 适用；添加下载直接消费 mutation owner/session、原形透传、正ID、权限与错误契约，F-145属本地可逆选择 | 主审与独立复核完成；后续G05将F-145升P2；TorrentInfo四字段归F-011，其余并入F-027/F-076/F-087/F-099/F-120/F-130 | 保持CHK-003/CHK-005；空下载器复用现有默认option，不新增CHK或选择框架 |
| V017 | 适用；分季订阅直接消费媒体+季身份、cache/session、取消范围、订阅ID与mutation结果，F-146属本地group owner | 主审与独立复核完成；W013-B补强后F-146确认条件性P1，其余并入F-003/F-008/F-027/F-047/F-048/F-060/F-065/F-066/F-068/F-082/F-120；通用media原形仅留CHK-003未验证边界 | 保持CHK-003/005/006/007/008；group切换复用现有latest-owner，不新增CHK |
| V018 | 适用；订阅编辑直接消费身份、PUT/回滚、cache/session、ID、通知和保存owner，F-147/F-148属本地Sheet生命周期/created receipt | W014与G02末裁及当前合同复核闭合；F-069不再是当前P1，F-199已修复现成三态问题 | 保持CHK-003/005/008/010/013；上游新增可写字段时按正式合同处理，不预建动态raw模型 |
| V019 | 适用；状态页直接消费Dashboard envelope/session/权限，F-149属本地并发发布顺序，F-150属已知权限的View呈现 | 主审与独立复核完成；F-149确认P1，F-150/F-070确认P2；其余并入F-005/F-027/F-060/F-082/F-086/F-126 | 保持CHK-005；三卡复用单一快照与superuser gate，不新增CHK或加载/权限框架 |
| V020 | 条件适用；下载页直接消费任务身份、客户端owner、动作响应、session与错误反馈 | 主审与独立复核完成；无新编号，F-091…F-095、F-024/F-027/F-060/F-082/F-083均闭合，F-033/F-035/F-120不适用 | 保持CHK-005；复用现有generation/action target/error出口，不新增CHK |
| V021 | 适用；手动整理直接消费preview/submit/session/cache/身份/错误契约，F-151属本地预览与实际intent一致性 | 主审与独立复核完成；F-151确认P1但因当前官方Web v2共享同一行为由用户决定跳过TV单端修复，其余并入F-074/F-075/F-076/F-099/F-027/F-065/F-087/F-120；I015修正跨logID去重边界 | 保持CHK-005/007；不新增CHK；若未来上下游共同修复，再统一preview/submit intent规则 |
| V022-B | 适用；删除/选择直接消费历史身份、mutation/session、部分失败与Paginator shift，F-152/F-153属本地批次快照/分页协调 | 分段双审与I009/G09回溯闭合；F-152确认P1，F-153已驳回P3，其余并入F-027/F-036/F-060/F-072/F-087 | 保持CHK-005；冻结现有对象；分页shift算法不改，仅补回归测试，不新增CHK或批处理框架 |
| V022-A | 适用；分页/搜索直接消费Paginator、query/session owner、响应/身份与storage gate | 分段双审与I009回溯闭合；F-071升P2，F-072/F-033/F-035/F-036/F-060/F-082/F-144等传播闭合 | 保持CHK-005；复用Paginator cancel与局部revision/session epoch，不新增CHK或分页框架 |
| V022-C | 适用；轮询/结果合并直接消费Paginator游标、插入/删除shift、query/session、身份去重与后端分页排序 | 分段双审与I009/G09回溯闭合；F-154已驳回P3、F-155确认P2，稳定同秒排序登记F-232 P2；F-153/F-204边界拆分闭合 | 保持CHK-005；不改已驳回项算法，给后端追加id tie-breaker并补插入组合测试，不新增CHK、协调器或cursor框架 |
| V022-D | 适用；AI整理直接消费能力/权限、accepted集合、SSE terminal、session与选择owner | 分段双审与I009/G09回溯闭合；F-098/F-156均确认P1，F-080/F-075/F-203等terminal/partial outcome传播闭合 | 保持CHK-005；复用isMutatingHistory、动作快照与逐ID receipt，不新增CHK或AI任务框架 |
| V023 | 适用；根会话直接消费settings/version、currentUser权限、logout持久化与Tab归一化，F-157属本地检查终态 | 主审与独立复核完成；F-157/F-089均确认P2，F-027/F-028/F-062/F-063/F-130等闭合，首帧权限窗口维持未验证 | 保持CHK-005；失败/取消不占成功key并复用现有判定，不新增CHK或会话框架 |
| C001 | 适用；通用空态直接影响错误/成功空/权限呈现与tvOS focus，F-158属本地无action焦点节点 | 主审与独立复核完成；后续G05把F-158升P2并把稳定后果锚定DownloadTask主行，其他透明sink留运行边界；其余传播不变 | 保持既有清单；删除无action透明节点并复用现有Button/action，不新增CHK或focus框架 |
| C002 | 适用；全局通知直接承载错误episode、Sheet层级与可访问性，F-159属本地短暂反馈传达 | 主审与独立复核完成；F-159确认P3，F-107传播、F-108未验证、H-012/F-049/F-093/F-126边界闭合；计时竞态驳回 | 保持既有清单；复用NotificationManager逐次announcement，不新增CHK或通知框架 |
| C003 | 条件适用；ActionRow直接承载选择、动作、busy与tvOS focus/accessibility，F-160/F-161属本地组件运行边界 | 主审与独立复核完成；F-160/F-161均确认P2，F-156传播确认，F-108仍未验证，F-120不扩展 | 保持既有清单；复用原生Button/disabled/accessibilityAction，不新增CHK或交互框架 |
| C004 | 条件适用；共享Sheet样式承载反馈、disabled、旧系统focus修补与退出可达性，F-162…F-165均属本地UI边界 | 主审与独立复核完成；F-162/F-165确认P2，F-163/F-164维持未验证条件性P3，F-120/F-147传播闭合，F-156不适用 | 保持既有清单；复用换行、isEnabled、现有modifier与dismiss，不新增CHK或Sheet容器 |
| C005 | 条件适用；文本桥接直接承载编辑、disabled/focus与Sheet保存代际，F-166/F-167属旧系统本地桥接边界 | 主审、独立复核与F-167补充裁决完成；F-166驳回，F-167维持未验证P3，F-074/F-076/F-147传播确认，F-120边界闭合 | 保持既有清单；防御性转发isEnabled并删除两次托管根transform写入，不新增CHK或输入框框架 |
| C006 | 条件适用；单选组件直接承载当前值、选项身份、focus/accessibility与Sheet退出，F-168属本地选择表达 | 主审与独立复核完成；后续G05按丢title/结构化selected语义将F-168升P2，实际默认焦点仍未验证；其余传播不变 | 保持既有清单；优先原生Picker，否则复用title/selected/default-focus，不新增CHK或选择器框架 |
| C007 | 条件适用；货架选择器直接承载Recommend持久选择与focus/accessibility，F-169属本地选择表达 | 主审与独立复核完成；F-169确认P3，F-033/F-139传播闭合，F-158及Search/Explore专属条目不适用 | 保持既有清单；现有Button补条件isSelected trait，不新增CHK或货架/focus框架 |
| C008 | 适用；多选组件直接承载站点/规则组选项域、隐藏选择、提交/关闭与权限边界，F-170属本地可逆性 | 主审与独立复核完成；W014跨端补强后F-170升级确认P2，F-112/F-114/F-130/CHK-005传播闭合，F-163/F-165不适用 | 保持既有清单；显示并定向清域外值而不自动丢未知值，不新增CHK或多选框架 |
| C009-A | 条件适用；卡片徽章直接消费来源/类型/评分/订阅入库状态与图片配置，F-171属本地可访问性表达 | 主审与独立复核及后续G03纠偏完成；F-171升P2，F-019/F-020/F-026/F-084/F-105/F-106传播闭合，F-114不适用 | 保持既有清单；保留Canvas并在整卡owner补accessibilityValue，不新增CHK或卡片框架 |
| C009-B | 条件适用；卡片主体直接承载占位类型、图片处理、激活/focus与整卡可访问性，F-172/F-173属本地占位/性能边界 | 主审与独立复核完成；F-172确认P3、F-173维持未验证性能P3，整卡语义并入F-171，F-105/F-106/F-138等传播闭合 | 保持既有清单；中性glyph、删除重复resizing并补单一整卡语义owner，不新增CHK或卡片框架 |
| C009-C | 条件适用；详情包装直接承载转场frame owner、DetailCard身份/Equatable与图片配置，F-174属本地转场所有权 | 主审与独立复核及后续G03纠偏完成；F-174升P2，F-105/F-106/F-138/F-171传播闭合，F-123/F-172/F-173边界明确 | 保持既有清单；优先删除手工frame飞入并保留loadingPosterURL，必要时目标绑定一次性状态，不新增CHK或转场框架 |
| C010 | 条件适用；人物卡直接承载route身份、图片、整卡控制语义并暴露详情横向分页调用，F-175…F-177属本地交互/性能边界 | G04 clean-room末裁将F-176升P2；F-175 P2、F-177维持未验证性能P3，F-143等传播闭合 | 保持既有清单；原生Button、三处nil guard、resizing换downsampling，不新增CHK或人物/分页框架 |
| C011 | 条件适用；MoreCard直接承载分季“查看全部”控制语义与背景图片处理 | 主审与独立复核完成；无新编号，F-175/F-173/F-003传播闭合，F-033/F-035/F-036/F-138及C009特有条目不适用 | 保持既有清单；复用原生Button并随F-173验收处理链，不新增CHK或更多卡片框架 |
| C012 | 条件适用；最佳结果卡直接承载评分结果的可见/可访问名称、类型占位、图片与详情激活，F-178属本地投影边界 | 主审与独立复核完成；F-178确认条件性P3，F-076/F-172/F-174/F-177及搜索身份传播闭合；固定高度/完整overview仅留运行盲点 | 保持既有清单；评分与展示复用有序非空名称候选，不新增CHK、匹配或卡片框架 |
| C013 | 条件适用；共享网格直接承载四类Paginator的身份、图片、焦点/预载、菜单、激活与空态呈现 | 主审与独立复核完成；无新编号，ID-only Equatable/旧items闭包只留契约风险，F-033/F-035/F-019/F-020/F-026/F-084/F-105/F-106/F-129/F-130/F-138/F-139/F-171…F-174传播闭合 | 保持既有清单；身份/图片/转场沿原owner修复，必要时删除冗余Equatable/外层门槛，不新增CHK或网格协调器 |
| C015 | 条件适用；根MediaAction presenter直接承载TMDB识别busy/alert并跨Tab/Login发布全局状态 | 主审与独立复核完成；无新编号，F-090/F-122/F-123/CHK-005传播闭合，重叠识别owner反例归既有项，overlay focus/accessibility仅留运行盲点 | 保持既有清单；正ID、session epoch与局部action revision在现有Handler修复，不新增CHK或每Tab presenter |
| C014 | 适用；共享菜单直接承载订阅意图、取消动作语义、Fork/TMDB/资源/详情与身份/session/转场边界 | 主审与独立复核完成；无新编号，既有F-014/F-015/F-054/F-077/F-090/F-103/F-113/F-119…F-124/F-174传播闭合；无Fork presenter页保持payload契约未验证 | 更新CHK-006：取消使用明确动作词/destructive role，范围/目标继续冻结；不新增CHK或菜单框架 |
| C016 | 适用；订阅modifier/Handler直接承载6个页面owner、8菜单入口、编辑/分季/Fork呈现、缓存与通知边界 | 主审与独立复核完成；F-054当前实现已解决，F-047与Web一致并由用户跳过；其余F-077/F-119/F-120/F-124/F-121/F-159/CHK-005/006及Sheet下游传播闭合 | 保持CHK-005/006；复用现有正ID、局部revision/session epoch与小缓存线性alias更新，不新增CHK或订阅框架 |
| C017 | 条件适用；资源卡直接承载展示文本fallback、标签/筛选投影、季集格式化、焦点/下载动作与torrent-only可见性 | 主审与独立复核完成；后续G05将F-179升条件P2，F-018/F-022/F-032/F-058/F-175传播，F-017维持未验证，促销badge仅留契约盲点 | 保持既有清单；trim→空为nil投影供卡片/筛选共用，不新增CHK或资源展示模型 |
| C018-A | 适用；结果段直接承载严格解码后的资源、软过滤分区、季集选项排序、计数/卡片/空态与焦点重定向 | 主审与独立复核完成；无新编号，F-022/F-032/F-057/F-058/F-059/F-061/F-110/F-158传播闭合；onAppear首帧与同ID原位变化仅留盲点 | 保持既有清单；现有排序先固定isFilteredOut分区、torrent-only在卡片契约修复，不新增CHK或结果管线 |
| C018-C | 适用；筛选UI直接承载raw option身份、排序方向、季集选项、Sheet标题、多选禁用/移除与focus/accessibility | 主审与独立复核完成；无新编号，F-110/F-057/F-058/F-059/F-179/F-168/F-170传播闭合，F-061根在A段；F-163/F-165不适用 | 保持既有清单；canonical option三链共用、显示现有title并允许定向移除已选disabled值，不新增CHK或筛选框架 |
| C018-B | 条件适用；排序模型直接声明字段/方向合法组合并决定比较器合同 | 主审、独立复核与第三代理争议裁决完成；无新编号，F-110确认、F-061根在A段；Swift自5.8文档化stable且项目设6.0，相等项保序；CI精确Xcode小版本未锁 | 保持既有清单；default复用isAsc、分区在A段修复，不新增CHK或排序框架 |
| W002 | 适用；登录页直接承载服务器地址/凭据输入、手动会话获取、失败通知与根视图转换 | 主审与独立复核完成；无新编号，F-086/F-088/F-107/F-027/F-062/F-063/F-159传播闭合，F-029本View无新增触发、F-089最终确认P2、no-access顺序通过 | 保持CHK-005；共享URL/form/session/Keychain/通知根修，不新增CHK或登录协调器 |
| W003 | 适用；Home直接承载订阅/媒体库/TMDB资源动作、session通知、卡片身份图片/转场及服务器选择持久化 | 主审与独立复核完成；无新编号，相关既有finding与CHK-005传播闭合；后续G03确认F-118 P2，F-012/F-017边界不变，F-158不适用；当前486行全文件覆盖原范围 | 保持CHK-005/006；刷新、身份、session、反馈、图片与转场沿既有owner修复，不新增Home状态/通知/focus框架 |
| W001 | 条件适用；手动媒体搜索Sheet直接承载查询代际、结果/空态、身份选择、备用名/类型展示与内容内退出 | 主审与独立复核完成；无新编号，F-076/F-099/F-178/F-172/F-158/F-165传播闭合，F-177未验证；F-060/F-157/F-159等不适用，AddDownload media_in仅留契约边界 | 保持既有清单；最小query owner/持久错误/正ID fallback/共享名称投影和原生取消，不新增CHK或搜索/Sheet框架 |
| W004 | 适用；Explore页直接承载来源/权限热变、插件筛选、Popular/分享身份、分页、Fork与图片导航 | 主审与独立复核完成；无新编号，F-077/F-078/F-120/F-121/F-129/F-130/F-131/F-132/F-033/F-035/F-105/F-106/F-027/CHK-005传播闭合；F-133/F-134/F-136未验证，F-135已确认P3，F-039/F-158不适用 | 保持CHK-005/009；共享身份/权限tuple/年份/sort/Handler/Paginator根修，不新增CHK或Explore状态框架 |
| W005 | 适用；Recommend页直接承载货架/空态、媒体身份、分页恢复、生命周期session、订阅动作、卡片图片与选择/徽章语义 | 主审与独立复核完成；F-079后经当前官方schema确认P2；F-173及Fork presenter/合集route维持未验证，F-158不适用 | 保持CHK-005/006/009；复用现有closure/sheet/route，不新增推荐协调器 |
| W006-A | 适用；Search根页直接承载权限/模式/focus收敛、query提交、来源/站点Sheet、Fork presenter、根导航与共享搜索入口 | 主审与独立复核完成；无新编号，F-130/CHK-005/F-142/F-039/F-076/F-114/F-121/F-027/F-137/F-140/F-141/F-112/F-168传播闭合；键盘提交按显式双模式按钮契约不立项，F-169不适用 | 保持CHK-005；复用权限reconcile、共享task owner、query规范与现有Sheet标题/selected语义，不新增CHK或Search框架 |
| W006-B | 适用；聚合结果层直接呈现五类Paginator、bestResults、空态/error缺口、focus/scroll与导航 | 主审与独立复核完成；F-079后经当前官方schema确认P2；F-064维持未验证，F-139/F-158不适用 | CHK-005补最终guard前子Paginator发布；CHK-009覆盖分享身份，不新增结果状态机 |
| W006-C | 适用；media/person行直接承载分页、会话、身份、图片预加载、人物展示导航、菜单订阅与卡片可访问性 | 主审与独立复核完成；F-077/F-079分享身份传播闭合，F-064/F-173/F-177维持未验证，F-158/F-176不适用 | 保持CHK-005/009/006；身份沿共享投影修复，不新增行/卡片框架 |
| W006-D | 适用；最佳结果卡直接承载排名、身份、名称职位、类型图片、分享/人物导航、会话预加载、sourceFrame、菜单及原生Button语义 | 主审与独立复核完成；无新编号，相关既有finding传播闭合，F-064/F-177及双FocusState/VoiceOver/性能维持未验证，F-171/F-173/F-175不适用 | 保持CHK-005/006/009；复用名称/职位/类型投影、session owner与原生导航，不新增卡片/focus/预加载框架 |
| W007 | 适用；详情容器直接承载preload task、Loading/ready/failed终态、partial fallback、pin/cache、权限session、图片与sourceFrame | 分段三方及I013最终裁决闭合；F-180 P2；后续G03将F-116升确认P2并保留实际闪烁/焦点运行边界 | 保持CHK-005；失败提示/Retry复用Loading/failed-task owner，cache hit只删ready旁路，不新增详情状态机 |
| W008-A | 适用；详情主视图直接承载状态owner、首屏gate、Hero/Content焦点切换、生命周期、背景与权限session | 分段三方及I013最终裁决闭合；F-181保持未验证、条件影响校准P2，既有状态/session/lifecycle传播闭合 | 保持CHK-005；先做FocusState序号日志与真机验证，确认后分别监听现有绑定，不新增focus协调器或状态机 |
| W008-B | 适用；详情Header直接承载订阅状态刷新、scene/周期触发、直订/分季/取消、TMDB资源动作与权限session | 双审及I008/I013回溯闭合；F-182升P2，F-007/F-047…F-049/F-130与Header/session传播闭合 | 前台恢复无条件复用现有强刷，保留点击前状态一致性guard；不新增刷新框架或CHK |
| W008-C | 适用；Hero/详情内容直接承载标题元数据、演员投影、TMDB/资源动作、焦点滚动、图片转场与原生Button语义 | 分段三方及I013回溯闭合；F-183维持未验证P3，F-231确认P2，既有Hero/Header/详情传播闭合 | 保持CHK-005；TMDB动作复用局部Task/generation并随route取消，不新增导航协调器或action框架 |
| W008-D | 适用；详情分季/导演演员区直接承载季身份、订阅子链、剧集组、人物投影导航、Paginator focus、图片预取与卡片语义 | 主审与独立复核完成；无新编号，相关既有finding/CHK传播闭合；运行/外部频率与F-177性能维持未验证 | 保持CHK-001/003/005/006/007/008；共享owner根修，onSeasonTap/initialSeason仅按死链删除，不新增分季/人物框架 |
| W008-E | 条件适用；推荐/相似区直接承载Paginator错误空态、身份导航、图片预取、详情预载、卡片语义及合集route | 三代理与I013最终裁闭合；F-184合法正数合集条件P1，0/负数/parts仍未验证；后续G03将F-116升P2，F-033详情局部P3、F-231 P2不变 | 保持既有CHK；原样复用Search collection destination与shouldPreloadDetail，不新增导航/货架框架 |
| W009 | 条件适用；人物详情承载人物身份route、详情/作品请求、图片、生命周期session及focus/accessibility，但无新的长期后端/订阅契约 | 主审、独立复核与第三裁决完成；F-185确认P2，空action/focusable状态并入F-158，F-126/F-143/F-144等传播闭合 | 保持既有CHK；长简介用原生ScrollView，状态焦点复用真实动作，不新增人物阅读/focus框架或CHK |
| W013-C | 不适用；SeasonDetailSheet只读展示，不新增后端/订阅兼容契约 | 主审、独立复核与第三裁决完成；F-185传播，F-190/F-191确认P3，可访问关闭与具体布局形态留运行盲点 | 复用原生ScrollView、既有字符串归一化与明确360×540 frame，不新增CHK、阅读器或海报组件 |
| W013-B | 适用；分季页面直接触发创建、暂停与删除，并消费group/media/season/session/owner合同 | 双审及W014交叉裁决完成；F-047旧跨季证据失效、剩余范围与Web一致并由用户跳过；F-146/F-148维持条件性P1 | CHK-006记录当前取舍；临时订阅复用既有CHK-005/008的session/正ID边界并增加created/owner receipt验收，不新增事务框架或CHK |
| W014 | 适用；订阅编辑直接消费创建/保存/回滚、权限session、站点规则、null/default与save_path值域合同 | 多轮复核与G02末裁完成；F-147/F-148/F-199 P1，F-170/F-195/F-200 P2；advanced a11y未验证 | 补强CHK-005；CHK-013/014固定lossless三态编辑幂等与save_path值域 |
| W015 | 适用；Fork确认直接消费分享身份、载荷、写权限、通知与多阶段operation owner | 多轮复核完成；F-193原跨profile P1链由`90b40b4`闭合、同profile余项P2；F-194/F-121 P2 | 保持CHK-005的多阶段owner与CHK-009的keyword/custom_words提交前可见性；不扩张其他字段 |
| W016 | 适用；状态页直接消费Dashboard权限/session及Download/Transfer身份和mutation合同 | 双审、第三裁与G09交叉裁决完成；F-149确认P1，F-150/F-198确认P2，F-192/F-091传播；Transfer转W019 | 保持CHK-005并确认CHK-012；Dashboard复用单一快照/superuser gate，episode投影属本地显示不新增CHK |
| W017 | 适用；下载页直接消费任务身份、downloader owner、动作响应、删除范围、状态枚举、权限与session合同 | 双审完成；后续G05使F-024/F-095/F-196/F-197为P1，F-083/F-092/F-093/F-094为P2；F-091/F-192/CHK-012传播不变 | owner保持CHK-012；CHK-015删除数据范围、CHK-016未完成状态、CHK-017 mutation envelope继续确认；F-092/F-093不扩张为CHK |
| W018-A | 不适用；本段是手动整理表单，episode_group仅作整理识别配置，不调用订阅API/缓存/通知 | 双审与G09交叉裁决完成；F-188/F-189旧v2.14.4机制历史保留、目标v2.15.1已驳回；其余F-156/F-206等按各自当前裁决 | 不新增订阅CHK；补强CHK-005批量多POST逐项/最终回调owner，CHK-019继续跟踪官方source合同 |
| W018-B | 不适用；本段只读呈现手动整理预览并触发既有提交链，不调用订阅API/缓存 | 双审与G09 clean-room窄裁完成；F-073收窄后确认P2，F-074/F-151/F-158/F-162/F-165/F-185传播确认，F-151由用户按当前官方Web v2对齐决定跳过，F-075/F-168不适用 | 不新增订阅CHK；F-073是读预览嵌套响应合同，不扩展mutation CHK-017；intent/generation/session与logID provenance边界不变 |
| I015 | 不适用；Reorganize整文件集成不调用订阅CRUD，但直接消费目标目录、媒体类型、preview/submit与session合同 | 集成及独立复核完成；F-212/F-213确认P1，F-151/G09去重边界已修正且F-151由用户按当前官方Web v2对齐决定跳过，并确认F-027/F-065/F-074/F-075/F-147等传播 | 不新增CHK；目录复合身份和类型字段投影作为整理回归，session/cache继续复用CHK-005/007 |
| I016 | 条件适用；SystemView全文件直接消费settings/sites/rules、profile/session/权限、route/focus、错误四态、Sheet与辅助功能合同 | 受限第三裁与G06收口完成；F-106/F-240/F-111/F-112/F-089最终P2，F-208/F-242 P3、F-241未验证P3保持。三代理均曾主审W020分段，严格独立缺口永久披露 | 保持CHK-005/018/019；复用现有route/owner、四态、Reduce Motion环境值与原生控制，不新增System协调器或CHK |
| I011 | 不适用；TorrentsResult整文件集成不调用订阅CRUD，主要消费资源解码、软过滤、排序、筛选与本地可访问性合同 | 集成及第三裁完成；F-061升P2、F-175确认TorrentCard传播并升P2，其余F-032/F-057…059/F-110/F-168/F-179/F-186传播闭合 | 保持CHK-011；资源结果修复复用既有解析/展示/排序owner，不新增筛选框架、可访问性CHK或资源模型 |
| I012 | 适用；Search整文件集成直接消费查询/来源、资源SSE与fallback、Paginator、身份导航、session/权限、预载及卡片语义 | 集成与G04 clean-room末裁闭合；F-076原跨owner P1链已闭合、当前余项P2；F-035/F-039/F-137/F-103/F-036 P2，F-219驳回 | 保持CHK-005/009/011/018/019；复用query/session/generation与aggregate cancel，不新增搜索状态机 |
| I005 | 适用；MediaPreloader整文件集成直接消费媒体身份、详情/分季/订阅、session图片缓存、取消与跨入口route合同 | 集成及定向独立复核完成；F-221/F-115 P2、F-220驳回；后续G02/G03将F-118/F-119升P2，其他后裁边界按对应组记录 | 保持CHK-005/007/010；识别跳过落terminal、详情后season两阶段发布，复用现有owner/线性小缓存，不新增预载状态机或CHK |
| I006 | 条件适用；ExploreViewModel全文件直接消费动态source/profile/filter、Paginator、媒体identity与session/权限合同 | 受限三方裁决及G04 clean-room末裁闭合；F-233…F-236均P2，F-237驳回、F-238未验证；严格独立文件集成缺口永久披露 | 保持CHK-005/018/019；复用(source.id,path)、session epoch与现有filter parser，不新增Explore状态机 |
| G01 | 适用；搜索来源、默认站点、动态过滤、SSE/分页、身份/评分及Manual/整理入口形成循环依赖 | G04/G05/G06/G09及窄裁全部闭合；F-076当前P2，F-130/F-138/F-212沿各自后续裁决，F-244驳回，F-133/F-134未验证 | 保持五项CHK；复用query generation、session epoch、canonical identity与default/all/specific三态，不新增框架 |
| G02 | 适用；订阅身份、三类cache、确认/mutation、临时事务、刷新、Share/Fork与页面/卡片形成循环依赖 | 全新clean-room复核完成；后续当前态复核确认F-054已由`58c7e81`与现行后端合同解决；其余裁决维持 | 保持既有CHK；复用正ID、session epoch/revision、immutable intent/receipt、原生Button及字段级开放输入，不新增订阅协调框架 |
| G03 | 适用；详情身份/导航、图片/预载cache、卡片/焦点/动作、订阅状态与availability形成循环依赖 | 三票/窄第三裁闭合；F-245独立P2并补CHK-017，F-097/F-118/F-221均收敛P2；CHK-006旧非TMDB跨季证据失效，剩余重复/超管fan-out与Web一致并由用户跳过；CHK-005/007/009/010保持既有边界 | 保持其余CHK；复用正身份、session/cache owner、latest-wins、严格mutation envelope及原生Button，不新增详情/图片框架 |
| G04 | 适用；Paginator与七类页面直接消费session owner、错误/空态、identity、cursor与激活恢复合同 | 全新clean-room末裁完成；F-034/F-035/F-039/F-137/F-142/F-143/F-176/F-236均确认P2，F-244并入F-130，错号意见作废 | 保持CHK-005；复用现有generation/session token、canonical identity、Paginator refresh/error，不新增分页框架或CHK |
| G05 | 条件适用；资源SSE、过滤/排序、动态筛选、下载动作与站点/source合同跨TV及当前上游 | 主审与独立复核完成；主审错号CHK票作废，八项共同升级已落账；G09将F-102转未验证P3，F-133/F-134/F-238继续未验证，六项CHK精确边界已确认 | 保持六项既有CHK；复用现有SSE parser、normalized string、原生Picker/Button、严格decoder与三态owner，不新增过滤/下载框架或CHK |
| G06 | 适用；会话、权限、根状态、认证图片/配置缓存、错误owner与长期页面状态跨登录、Content、System及App形成循环依赖 | 主审与独立复核完成；F-030已修复；F-031当前三端复核降为条件性P3并由用户跳过；其余裁决维持 | 保持既有CHK；复用session epoch、cache namespace、profile/operation owner与现有错误出口，不新增会话框架或CHK |
| G09 | 适用；转移、整理、手工搜索、状态页与后端文件副作用共同消费session、身份、分页、mutation及服务端授权合同 | 主审、独立复核与clean-room替代裁决完成；F-153/F-154驳回，F-102未验证，F-073确认P2，F-246确认P1；其余等级与传播均已收口 | CHK-020新增已确认；其余复用CHK-005/007/017及现有intent、对象签名、稳定排序和逐ID回执，不新增协调器或平行CHK |
| G08 | 适用；全局通知跨登录根、session、Sheet与VoiceOver，且承载订阅/下载/整理等失败反馈 | 三方历史裁决及G02末裁闭合；F-107后续主触发已修复、剩余P2由用户决定跳过，F-148 P1，F-049/F-121/F-223 P2，F-108未验证P3、F-159 P3；H-012仅传播 | 保持CHK-005；会话owner复用单调epoch，operation scope用轻量notice ID；不新增通知队列或CHK |
| G07 | 条件适用；人物身份/source筛选、跨来源分页与Bangumi/Douban字段直接跨TV/Web/后端，职位/卡片其余为TV显示边界 | 三方裁决及G09后裁闭合；F-189旧合同结论对目标v2.15.1已驳回，其余F-143/F-036/F-227/F-226等维持当前裁决 | 保持CHK-019；后端source合同以后再变化时同步TV/Web，复用Person.id/imageURLs/原生Button，不新增人物/job/卡片框架或CHK |
| G10 | 条件适用；Sheet中的订阅/下载/整理/Fork mutation直接消费session与持久化合同，共享焦点/样式/长文本其余为TV呈现边界 | 主审及独立复核闭合；F-229确认P3、F-230确认P2，F-120/F-160/F-205升P2；F-148/F-027/F-193/F-076/F-185/F-158/F-162/F-168等传播闭合 | 保持CHK-005/006；mutation复用局部phase/session owner，呈现优先原生Button/ScrollView/UIFontMetrics；不新增Sheet/focus框架或CHK |
| I003 | 适用；APIService全文件直接承载登录/settings/session重放、订阅/分季缓存、mutation envelope、SSE与全部订阅CRUD | 集成及当前复核完成；F-027/F-065/F-082/F-086 P1，F-100已修复，F-069降为未来兼容P3；F-083/F-080/F-106 P2 | 保持CHK-003/005/007/010/017；API层epoch、strict envelope与逐字段完整更新门禁阻止错误副作用，不新增框架 |
| I007 | 适用；SearchViewModel全文件直接消费媒体source、资源SSE、五类Paginator、分享身份/评分、规则与session/权限 | 集成及定向独立复核完成；F-189对目标v2.15.1已驳回；F-076当前余项P2，其余F-225/F-130/F-033/F-034/F-080/F-081/F-085/F-137等维持当前裁决 | 保持CHK-005/009/011/018/019；两阶段分享揭示与评分修复复用既有owner/错误/来源合同，不新增搜索状态机、评分框架或CHK |
| I008 | 适用；MediaDetailViewModel全文件直接消费partial/full身份、详情派生加载、订阅/取消、权限session、错误与preload cache合同 | 集成及定向独立复核完成；F-007 P1、F-182 P2；后续G03窄第三裁确认F-118 ownerless pin根因P2且保留运行边界，其他映射不变 | 保持CHK-005/006/010；复用共享订阅draft factory、纯TMDB仲裁、不可变cancel intent、现有通知与permission epoch，不新增详情/订阅/缓存框架或CHK |
| I009 | 条件适用；TransferHistoryViewModel不调用订阅CRUD，但批量删除/AI/整理直接消费session、历史身份、分页/轮询、文件副作用与SSE终态合同 | 集成、定向独立复核及G09排序裁决完成；F-204条件P1、F-098 P1，F-071/F-155/F-205/F-232 P2，F-154驳回P3，其余并入F-027/F-072/F-033/F-080/F-075/F-156/F-203/F-153 | 保持CHK-005；复用session snapshot、Paginator refresh、逐ID receipt与稳定tie-breaker，不新增历史/批处理/cursor状态机或CHK |
| I010 | 条件适用；MediaCard全文件直接消费媒体身份/route、订阅/下载mutation、权限session、图片缓存、预载及卡片控制语义 | 三方裁决及后续G03纠偏闭合；F-020条件P1、F-171/F-174/F-239 P2，poster留F-123，其余传播不变 | 保持CHK-005/010；受保护图片复用opaque session namespace、Search复用PreloadDebouncer、卡片复用原生Button，不新增卡片/路由/缓存框架或CHK |
| I013 | 适用；MediaDetailView全文件直接消费route/identity、详情ready/error、订阅/取消、权限session、分页、焦点、缓存及Sheet合同 | 集成、定向复核与最终第三裁闭合；F-231 P2、F-184条件P1、F-180 P2、F-181未验证条件P2、F-033根P2/详情局部P3；后续G03将F-116升确认P2 | 保持CHK-005/006/010；route task、失败Retry、Focus监听与ready谓词均复用现有局部owner，不新增框架或CHK |
| I014 | 适用；SubscribeSeasonView全文件直接消费媒体/季/group身份、查询确认删除、临时订阅事务、session/权限、cache、Sheet与卡片合同 | 严格集成及定向复核闭合；F-012确认P2、F-243新增P2，API三缓存归F-065、Retry归F-148，MediaPreloader当前不成案，其余F/CHK传播闭合 | 保持CHK-005/006/007/010；复用共享identity、session epoch、created receipt、三类分季cache owner及现有前台刷新，不新增订阅协调器或CHK |
| I004 | 适用；SystemViewModel整文件集成直接消费profile、登录/settings、站点规则、权限session及搜索来源合同 | 集成闭合；无新编号，F-027/F-029/F-031/F-062/F-063/F-081/F-085…089/F-107/F-109/F-111…113/F-126/F-130/F-144/F-157/F-170/F-189/F-207/F-209/F-210等传播闭合 | 保持CHK-005/018/019；修复复用规范profile、单调epoch、四态与正式搜索域/source合同，不新增配置框架或CHK |
| W019 | 条件适用；转移历史不调用订阅API，但直接传播通用session/权限owner、分页错误与后端排序合同 | 双审及I009/G10回溯闭合；F-201/F-202/F-203/F-205 P2，F-204条件P1，F-232 P2，并补F-165/F-185等传播 | 保持CHK-005；复用权威refresh、逐ID receipt与后端稳定tie-breaker，不新增历史协调器或CHK |
| W020-A | 适用；System常驻根页直接消费currentUser/session、settings、sites/rules与权限派生route/focus合同 | 双审完成；无新编号，F-130/CHK-005、F-144/F-157、F-109/F-111/F-112及F-126/F-060传播闭合；F-113/F-035/F-029本段不直接 | 不新增CHK；两票补强CHK-005的长期根页route/focus/受限快照、整个加载epoch与权限tuple边沿 |
| W020-B | 适用；页面容器承载权限派生route、当前/退役页快照、Back/Menu、focus与session收敛 | 双审完成；F-130/CHK-005传播，F-208确认P3，F-161维持运行未验证，F-185补规则预览；空白非法route确定但Back恢复待运行 | 不新增CHK；继续复用CHK-005，Reduce Motion属本地可访问性验收 |
| W020-C | 适用；根页/连接页直接消费登录、currentUser、settings/backendVersion、站点规则与重登session合同 | 双审及F-216定向复核完成；F-207确认P3，F-216并入F-107并交叉F-089，其余session/权限/长文本传播闭合 | 不新增CHK；F-207复用现有loadSystemInfo，错误交接归F-107，既有session/权限合同继续由CHK-005覆盖 |
| W020-D | 适用；推荐、站点与媒体来源设置直接决定搜索域、default/all/specific、profile写入及session owner | 三代理完成；F-209/F-210为独立P2，F-214并入F-109，F-189传播；CHK-018/019已确认 | 新增CHK-018/019已确认：搜索站点权威域三态及媒体source真实执行语义；不新增平行条目 |
| W020-E | 适用；过滤规则页直接消费规则schema、选中ID、profile/session owner并决定后续硬/软过滤意图 | 三代理完成；F-211驳回并拆归F-126/F-081，F-215并入F-081并支持其P2；合法长名称视觉保持运行未验证 | 不新增CHK；规则身份/schema归F-081/G05，加载四态归F-126，跨owner复用CHK-005 |
| W020-F | 适用；路由/焦点辅助与规则预览直接消费权限页面域、session任务、规则规范化和Reduce Motion | 双审完成；无新编号，F-130/CHK-005、F-126、F-085、F-168、F-208传播；F-208维持P3，焦点/Back/a11y交I016 | 不新增CHK；session复用CHK-005，规则语义归F-085/G05，本地动画归F-208 |
| W020-G | 条件适用；路由/焦点类型与UIKit返回观察器直接影响退出结构身份、推荐task、window/Menu/Sheet与session owner | 三代理完成；F-217确认独立P3，F-130/CHK-005/F-208传播；StateObject保留使其不足P2，window/Menu/Sheet保持运行验证 | 不新增CHK；恒定modifier修复F-217，通用owner继续复用CHK-005 |
| W020-H | 条件适用；规则预览只消费成功解码且已选中的单条规则，并与matcher共享过滤语义 | 双审完成；无新编号，单值/区间与空白正则准确归F-085并升P2；F-081数组/缺ID链不在本段加权 | 不新增CHK；规则解析与matcher复用F-085/G05，F-081保持独立输入边界 |
| R002 | 适用；App入口持有全局通知owner并注入根视图，直接跨越登录、logout与认证失败原因交接 | 双审完成；无新编号，旧session通知并入F-107，Sheet层与VoiceOver分别维持F-108/F-159运行验证，App注入/初始化通过 | 保持CHK-005；按session撤销过期通知但保留显式一次性logout原因，不新增通知队列、scene框架或CHK |
| R001 | 适用；Content根直接决定启动准备、认证分支、Tab/权限、session/settings任务及全局媒体动作owner | 三代理完成；F-218确认独立条件性P3，F-106 settings出口与F-130/CHK-005异步owner交叉但不可互替；其余权限/通知/动作传播闭合 | 保持CHK-005；统一readiness实现可同时修复，但分别验收首次同步门、必要settings出口及A→B异步owner，不新增启动协调器或CHK |
| W010 | 条件适用；合集页承载collection route/value域、首屏与Paginator恢复、子项身份导航、图片、session/lifecycle及卡片语义 | 主审、独立复核与带污染披露的第三裁决完成；无新编号，合集route边界并入F-184，其余F-033/F-035/F-138/F-026等传播闭合 | 保持既有CHK；先固定推荐/parts payload，再复用共享collectionRouteID，不新增合集导航框架或CHK |
| W011 | 适用；资源结果页直接承载SSE终态、后端促销枚举、筛选排序、空态恢复、下载session与focus/accessibility | 主审、独立复核与第三裁决完成；后续G05将F-110/F-158升P2，F-186/F-187维持P2，F-080/F-022/F-147/F-027等传播闭合 | 保持CHK-005/011；促销枚举与空态重试为TV实现修复，不新增订阅兼容CHK或通用状态框架 |
| W012 | 条件适用；AddDownload Sheet直接承载下载身份/body/端点、手动来源搜索、配置Picker、副作用session及focus/accessibility | 主审、独立复核与目标版本重裁完成；F-188/F-189因v2.15.1已含`3b709b7`统一合同而驳回，F-135/F-011/F-027/F-120/F-147/F-145等按各自当前裁决 | 保持CHK-003/005/019；以后按当前官方端点合同同步，不按旧schema给TV加差异补丁 |
| W013-A | 适用；分季页面包装直接承载导航请求、StateObject owner、加载task/session缓存、入口类型与原生退出 | 主审、独立复核与第三裁决完成；无新编号，F-126升级P2并扩展取消门闩，F-144/F-065/F-015传播闭合；initialSeason/onSeasonTap仅死链清理 | 保持CHK-004/005/007；共享加载/cache/type owner根修，删除死参数，不新增分季导航或加载框架 |
| B004 | 适用；现有四权限、deny-by-default、根菜单与缓存失效条目保持；提出 CHK-005 | 已闭环 | CHK-005 已确认 |
| S004 | 条件适用；订阅分享 Paginator 创建时权限 gate 正确，F-026/F-032…F-036/F-039 是通用分页/图片/资源问题 | 已闭环 | 保持/无新增 |
| B006-A | 不适用；语言名称只影响详情展示，不改变订阅身份、缓存、刷新或权限 | 已闭环 | 无清单动作 |
| B005 | 不适用；职位翻译与排序属于 G07 人员展示，不改变订阅契约 | 已闭环 | 无清单动作 |
| B006-B | 不适用；国家地区显示仅影响详情元数据，不改变订阅契约 | 已闭环 | 无清单动作 |
| B006-C | 不适用；职位与类型翻译只影响人员/详情展示 | 已闭环 | 无清单动作 |
| B007 | 适用；episode_group/S00/媒体+季删除既有条目保持；提出 CHK-006 | 已闭环 | F-054当前实现已解决；F-047/F-048与Web共享相同行为并由用户决定跳过；CHK-006保留动作词与范围审查记录 |
| S006 | 不适用；人员合并、职位/头像排序只影响 G07 展示 | 已闭环 | 无清单动作 |
| I001 | 适用；Models 全文件集成确认 CHK-001…009 无重复技术结论并收窄合并边界 | 已闭环 | CHK-002经当前Web/后端合同确认删除错误现状声明；其余已确认项维持并按正式条目合并 |
| I002 | 不适用；TranslationHelper 文件级集成仅涉及本地化与人员/详情展示 | 已闭环 | 无清单动作 |
| S002 | 适用；现有权限会话归属、订阅缓存与 CHK-005 保持；F-062/F-063 是本地 Keychain 失败处理，不新增跨端契约 | 已闭环；独立复核同意 | 保持/无新增 |
| S003 | 不适用；资源 season_episode 排序不处理订阅 season_number 或身份 | 已闭环；独立复核同意不适用 | 无清单动作 |
| S001 | 不适用；日志基础设施不改变订阅身份、缓存、刷新、权限或删除契约 | 已闭环；独立复核同意不适用 | 无清单动作 |

### CHK-006：取消影响范围与不可变意图

- 状态：已确认
- 建议内容：取消入口必须以“取消订阅”等动作词明确告知 mutation，并为菜单/确认按钮使用 destructive role；不能用“已订阅”状态词替代动作语义。当入口不能证明只影响当前用户的一条记录时，确认必须显示可判定的 owner、命中数和删除范围，并冻结删除模式（精确订阅 ID 或严格 mediaId+season）、目标与范围；TMDB、Douban、Bangumi、AniList及不透明身份均不得丢失season。准备失败不得继续宽删除，确认后范围变化必须重新确认。`episode_group` 仍只用于展示。无确认直删只允许已证明单用户单记录的路径。
- 来源：B007/C014/W013-B / F-047/F-048/F-124。
- 相关文件/测试：SubscriptionCancelConfirmation、Home/MediaDetail/SubscribeSeason/SubscriptionHandler、API 删除契约及多用户/并发测试。
- 当前限制：G03窄第三裁对当前可读上游做了静态核对：后端`/Users/chantxu/code/MoviePilot`为`a0ee99aacc485259431ce5be10933559f4ceac42`，Web`/Users/chantxu/code/MoviePilot-Frontend`为`19710a5f0fe0d795a92de904bacd3193bd8c8432`，均为detached且相关文件与各自HEAD一致，但未证明对应发布tag或实际部署。当前后端中`tmdb:`仅在season非nil时按季过滤、nil会覆盖全部季且删除重复命中；`douban:`忽略season；`bangumi:`查找忽略season且通用mediaid删除可覆盖全部命中，legacy仅bangumiid路径还可能找不到；AniList/其他不透明mediaid同样忽略season；superuser路径还可跨owner fan-out。查找只返回首条，无法向确认层表达命中数/ID。当前Web共享媒体级删除接口，说明它也受同一上游缺口影响，不构成安全证明。修复必须落在上游精确删除契约并协调Web/TV迁移，不做TV单端差异化兜底；未运行测试/后端，实际部署版本与数据分布未验证。

### CHK-005：权限快照与会话归属

- 状态：已确认
- 建议内容：`makeRequest`、自动重登、递归重试、`/user/current`、public/user settings 两段读取和全局发布、下载 add/stop/start/delete 等 mutation（含 `/download/` 与 `/download/add`），以及 profile-scoped 本地偏好的异步归一化、写回与返回必须绑定同一单调 session epoch 和发起时作用域；旧响应不得在新 baseURL/token/profile 上重放请求体、发布或返回结果、重登、登出或覆盖权限/settings/下载列表/本地偏好。权限变化后同步收敛根 Tab、自动预取、settings 与订阅缓存。同一会话内的下载客户端代际由 F-095 单独约束，不属于本条。
- V005 已确认补强：session owner 必须从用户按钮动作起点贯穿多次 await、后续新请求、全局 spinner/alert/poster 写入及最终 callback/导航；不能让每个请求各自捕获的新 session 把同一旧动作合法续接到新 profile。当前结构快照不足，单调 epoch 由本条统一要求提供。
- V007 已确认补强：首次/手动/自动登录 acquisition 自身须有 latest-attempt owner，并复用单调 epoch；结构相同的 snapshot 不能证明 A→B→A 未切换，旧登录成功不得在当前 baseURL 下覆盖 token/currentUser/分步凭据或提前关闭新尝试状态。
- V008 已确认补强：Home 周期刷新、通知强刷和 mutation 从按钮/确认意图起点捕获同一单调 epoch；每次 await 后、发布数组、写 selected-server 偏好、发通知/错误或执行冻结 reset 前复核 owner，A→B→A 不得因结构值恢复相等而放行。
- V009-C 已确认补强：权限 currentUser 成功发布后，派生来源、当前选择、已发布受限列表与 Paginator 必须同步收敛；失权立即取消/清空旧 owner，增权只补来源且不重置无关列表，每页请求仍复核当前权限。该 UI 收敛不能替代 F-027 的 session/鉴权副作用 owner。
- V011-C 已确认补强：Search 的可见模式、focus target、站点/媒体来源 profile、旧 Paginator/items/bestResults 与 SSE/fallback task 必须在权限或 session epoch 变化时一起归一化、取消并清理；Paginator 内部直接发布也须在写 items 前复核 owner，结构值相同的 A→B→A snapshot 不得放行。
- W014/W015 已确认补强：已打开Sheet及按钮起点后的每个mutation阶段都须复核同一session owner与发起动作的`requiredPermission`；401自动重登获得的新用户权限已撤销时，不得无条件重放旧Fork POST或继续后续GET/status/search。POST→GET→编辑器呈现共用一个operation owner，不能由各层重新捕获当前session把旧动作续接下去。
- W018-A 已确认补强：批量多POST从按钮起点冻结owner，必须在每个请求前及最终`onDone`前复核同一单调session epoch与`requiredPermission`；不能让循环中每次`makeRequest`读取当时会话，把A服旧history ID续接到另一个manage会话B。
- W020-A 已确认补强：权限门禁虽会重算，长期存活设置根页的route、pageOffsetDepth、focus、受限StateObject快照与加载任务仍须随同一owner收敛；失权退合法根并清受限状态，获权恰好补载一次，相同权限重复不得重置。整个`loadSystemInfo + loadSites`、共享settings发布及rules任务共用单调epoch；小型权限tuple只负责同session的合法路由/补载边沿。
- W020-C/F 已确认补强：login acquisition与手动刷新必须沿用同一单调owner，旧A登录成功不得覆盖logout或新登录B；`fetchSettings`在发布共享settings前即复核owner，调用方事后guard不算保护。权限/session变化还须同步作废非法System子route/focus，并在新owner补发被旧全局loading吞掉的rules加载。
- R001 补强：Content根token/scene任务、`loadGlobalSettings`和长期`MediaActionHandler`从启动动作起点绑定session epoch；`fetchSettings`两段读取及共享发布不可由调用方末尾guard补救，A公开设置+B用户设置不得混成全局配置。logout时旧媒体识别遮罩、alert与结果必须失效，不能覆盖Login或新账号。
- I006/I010 补强：Explore动态source refresh、source/Paginator发布、Search行延迟preload以及订阅lookup→后续mutation必须从调度/按钮起点绑定同一单调epoch；logout清理发生在旧producer登记前也不能让其随后以新会话重建全局任务。权限tuple只负责同session收敛，不能替代跨session owner。
- 来源：B004/V002-D/W014/W015 / F-027/F-028/F-029/F-113/F-193。
- 复用价值：后端权限调整、账号切换或 token 刷新时避免只更新 UI、Token 或缓存其中一层。
- 相关文件/测试：`UserPermissions.swift`、`APIService.swift`、`ContentViewModel`、`SystemViewModel`、`AddDownloadViewModel`、`DownloadTaskViewModel`、对应 View 与权限/会话/URLProtocol 行为测试。
- 当前限制：独立复核已完成；当前Fork端点未统一强制TV入口的subscribe业务权限已静态确认，但是否把该权限提升为服务端通用合同仍需产品协调；真实部署状态码与撤权频率未验证。

### CHK-007：分季与剧集组缓存的会话隔离

- 状态：已确认
- 建议内容：`episodeGroups`、`mediaSeasons`、`groupSeasons` 等分季缓存必须绑定请求发起时的 baseURL/session namespace；切服、换号或权限会话变化后，旧请求只能回填旧 namespace，不得写入新会话可见 key。
- 来源：M001-F / F-065。
- 复用价值：不同 MoviePilot 实例、账号或后端版本可对同一 TMDB/group ID 返回不同配置，升级或切服时相对路径 key 会造成跨会话污染。
- 相关文件/测试：`APIService.swift` 三类缓存、会话 generation、SubscribeSeason/SubscribeSheet/Reorganize 调用者及切服旧请求回填测试。
- 独立复核：verify_m001_f_retry 确认 session guard 和单纯 clear 均不能阻止旧 in-flight 回填；值得长期保留且不与现有条目重复。
- 当前限制：A001/I003/G02 已闭环统一缓存代际和账号维度；真实切服/换号期间旧请求回填时序未运行验证。

### CHK-008：订阅快照业务 ID 完整性

- 状态：已确认
- 建议内容：`GET /subscribe/` 进入 TV 快照的每条记录必须具有唯一正业务 `id`；草稿模型可以没有 ID，但列表/焦点/编辑/搜索/暂停/重置/删除入口不得接收 nil、0、负数或重复 ID，兼容巡检不得跳过异常记录。
- 来源：M001-F / F-068。
- 复用价值：订阅 schema 或聚合逻辑变化时，业务 ID 同时决定 SwiftUI 稳定身份和全部订阅动作目标。
- 相关文件/测试：`Subscribe`、APIService 订阅快照、Home/分季入口、BackendCompatibilityTests 及缺失/0/重复 ID fixture。
- 动作修正：补强现有 `Subscribe schema 返回 id` 条目，不新增平行规则。
- 独立复核：verify_m001_f_retry 确认 nil/0/负数/重复 ID 同时影响 SwiftUI 身份、焦点、动作和巡检，值得长期保留。
- 当前限制：A001-J/G02 已闭环；异常快照应拒绝整批还是过滤单条属于上游坏记录处置策略，仍未验证。

### CHK-009：订阅分享 ID、身份与 Fork 载荷完整性

- 状态：已确认
- 动作修正：补强现有订阅模型/API 条目，不重复 CHK-005 的 session 规则。
- 建议内容：订阅分享列表进入TV后，每条记录必须具有唯一正分享业务ID；`GET /subscribe/shares`→`POST /subscribe/fork`须保留当前schema的`tmdbid/doubanid/bangumiid/anilistid/media_source/media_id`，转为`MediaInfo`时按canonical→raw优先级投影全部主身份。未知extra不要求raw透传，legacy`mediaid`不在当前Share合同。最终确认页至少展示会立即持久化的非空`keyword/custom_words`。
- 来源：M001-I/W015 / F-077/F-078/F-194，并扩展 F-027/F-079；嵌套分享对象已从收窄后的 F-011 排除。
- 复用价值：后端新增来源字段、调整分享 schema 或改变 Fork 对 payload 的依赖时，都会再次触发身份/配置丢失。
- 相关文件/测试：`SubscribeShare`、Explore/Search 分享分页、SubscriptionHandler/Fork sheet、本地 Fork body 捕获、分享 schema 只读巡检及跨源身份 fixture。
- 独立复核：verify_m001_i 确认身份边界值得长期保留；W015两名不同代理又对照当前TV/Web/后端，确认`keyword/custom_words`已经被POST立即持久化但TV确认页不可见，值得作为升级巡检的最小提交前可见性检查。
- 当前限制：分享ID、全部当前schema主身份、GET→Fork保留及两个关键规则的提交前可见性已确认；其他配置是否必须在确认页显示仍未验证。

### CHK-010：同键订阅状态强刷代际

- 状态：已确认
- 建议内容：`对同一规范化 media+season key，较新的 forceRefresh 开始后，仍在途的较旧普通 miss 或强刷响应均不得写入 Bool 缓存，也不得把旧值返回给调用者；旧调用者应复用或读取较新请求结果。全局 subscription generation 只处理 mutation/session 失效，不能替代同 key revision。Bool 缓存当前为 120 秒访问续期，订阅快照为 30 秒固定 TTL；若产品要求 Bool 状态存在最大陈旧上限，应另行关闭续期并补时钟测试。`
- 来源：A001-J/V004-A / F-100。
- 复用价值：订阅 mutation、并发页面刷新、切换详情和后端延迟变化都会重复触发同键响应乱序，单纯全局 generation 不能表达请求新旧。
- 相关文件/测试：`APIService.checkSubscription`、MediaPreloadTask、详情 ready 后的视图强刷、同 key 可控响应顺序测试、I003/G02。
- 独立复核：verify_a001_h 确认普通 miss→force 与 force→force 都须覆盖；验收同时断言旧/新调用者返回值和最终缓存，已在 force 前完成的 cache hit 不追溯 supersede。
- 当前限制：latest-wins 已确认；TTL/访问续期的产品选择、真实触发频率与真机表现未验证。

### CHK-011：资源 SSE 事件帧、终止与补偿边界

- 状态：已确认
- 建议内容：`资源搜索 SSE 应按空行划分事件，并以换行拼接同一事件的多条 data 后再解码。客户端只有收到该端点明确的成功终止，才可对未返回结果且无明确站点错误的站点执行一次同步补偿；整体 error、调用方取消或无成功终止的 EOF 均不得进入 missingSites 补偿。后端若提供带 site_id 的明确错误，应删除对应静默补偿。`
- 来源：A001-H / F-080/F-101。
- 复用价值：后端 framing、终止 token 与站点错误结构变化会重复影响 TV 资源流、同步 fallback 和升级巡检；该建议修订并合并既有 missingSites 条目，不创建平行条目。
- 相关文件/测试：`APIService.streamSSE`、`SearchStreamEvent`、`SearchViewModel`、`ResourceResultViewModel`、`BackendCompatibilityTests`、`ResourceResultViewModelTests`、`SearchViewModelTests` 及最小多 data/无终止/整体错误加显式站点 fixture。
- 独立复核：verify_a001_h 确认 TV framing、终止与补偿链；普通用户取消已有 Task/generation guard，因此“取消进入补偿”只保留为不变量，不记成已观察缺陷；AI 进度由 G09 单独处理。
- 当前限制：G05已静态确认当前本地后端正常producer为单行data并发送done、Web显式跟踪done；代理截断、合法多data producer、站点错误结构、Content-Type与实际部署仍未运行验证。

### CHK-012：下载任务 owner 授权与复合身份

- 状态：已确认
- 建议内容：`下载任务列表必须按当前token subject过滤，start/stop/delete须在服务端再次校验同一owner；superuser全局管理与API Token受信集成必须是显式、可测试的例外。任务和owner查找以downloader + stable task id/hash为最小复合身份，不得只按hash；TV行绑定响应中的downloader/owner并做展示过滤，但客户端过滤不能替代后端鉴权。`
- 来源：W016/W017 / F-192/F-095。
- 复用价值：新增下载器、调整manage权限、支持多用户或迁移下载历史时，token-only端点、hash-only owner回填和当前Picker反查客户端都会再次产生跨用户或错下载器mutation。
- 相关文件/测试：DownloadTaskView/DownloadTaskViewModel/DownloadingInfo、后端download endpoints与history oper、Web DownloadingListView；覆盖manager本人/外部任务、superuser、API Token、A/B同hash、切客户端失败/延迟及foreign mutation保持不变。
- 独立复核：review_a001_j与review_a001_h分别从Status页权限准入和DownloadTask完整行链确认；当前Web普通用户过滤是正向UI对照，当前后端缺服务端owner校验是安全根因。
- 当前限制：本地上游快照已核对但用户部署版本未验证；API Token是否应保留全局下载管理须由产品明确，不能由审计自行收紧。

### CHK-013：订阅总集数三态与编辑幂等

- 状态：已确认
- 建议内容：`订阅编辑必须保留 total_episode 的 null、0、正数三态及既有 manual_total_episode 语义。未修改的 null 保存后仍为 null，不得因省略或后端默认变成0或置manual；0/正数原样round-trip，manual语义只因用户显式修改总集数而变化。GET→未修改PUT必须幂等，非manual订阅的自动总集数与完成前刷新继续有效。`
- 来源：W014 / F-199。
- 复用价值：该合同同时约束Subscribe Codable、编辑payload、Web完整表单回传、后端schema默认/update及自动刷新链；未来optional/default/PATCH语义任一变化都可能复发。
- 相关文件/测试：`SubscribeModelCompatibilityTests`的显式null；`SubscribeSheetViewModelTests`覆盖null/0/positive×既有manual、GET→未改PUT→GET及显式nil→0、0→positive、positive→0；后端覆盖fields_set/update与refresh的manual 0/1分支。仅用单测/临时DB，禁止在个人真实后端运行副作用update。
- 独立复核：review_a001_j从F-199跨端链提出条目；review_a001_h独立确认当前正式清单无total_episode/manual_total_episode合同、长期价值成立且不能与save_path合并。
- 当前限制：真实NULL数据分布与部署版本未验证。

### CHK-014：订阅保存路径值域与存储 URI

- 状态：已确认
- 建议内容：`订阅 save_path=nil 表示自动目录；非空值必须为后端可直接消费的API-ready值，允许配置的本地根/子路径 /root[/child] 与远程storage-qualified根/子路径 <storage>:/root[/child]。编辑器原样保留既有合法/自定义值、允许新建或编辑合法子路径/URI并可清空为nil；配置选项中的远程URI必须原样保留，服务端继续拒绝越界和路径穿越。`
- 来源：W014 / F-200。
- 复用价值：目录配置、Web combobox、TV编辑器、订阅持久化、下载allowlist及实际订阅下载共享该值域；新增存储类型或路径格式时易再次漂移。
- 相关文件/测试：TV本地根/远程URI/合法子路径/既有值round-trip/清空自动与PUT body；后端download paths endpoint、save path allowlist根/子路径/远程URI/越界/穿越及订阅链隔离传参。不得触发个人真实下载。
- 独立复核：review_a001_j第三裁决确认应与三态合同拆分；review_a001_h独立确认当前正式清单无save_path/download/paths合同、storage URI与合法子路径需长期固定。
- G01纠偏：rounda_g01_recheck确认已有任意值会显示并在未触碰时原样保存、配置中已有远程URI可选；本条保留的是开放String值域、API-ready URI与新增/编辑能力，不再把当前实现扩大为已有值必丢或已配置URI必降级。
- 当前限制：真实远程目录和自定义子路径频率、产品文案与用户部署版本未验证。

### CHK-015：下载删除数据范围与危险动作确认

- 状态：已确认
- 建议内容：`删除下载任务与永久删除已下载文件必须是两个显式动作；请求显式携带 delete_file 或等价字段，省略或 false 只删除任务并保留数据。永久删除必须单独使用 destructive 确认，显示任务名、downloader、文件范围与不可撤销性。`
- 来源：W017 / F-196。
- 复用价值：新增下载器或调整默认参数时，UI“删除任务”与适配器delete_data=true的语义漂移会直接造成不可恢复的数据删除；CHK-006是订阅取消范围，CHK-012是owner鉴权，均不覆盖数据范围。
- 相关文件/测试：每个下载器适配器的omitted/false/true矩阵，TV/Web请求body与确认文案；只用临时/mock任务和文件，不碰个人下载数据。
- 独立复核：review_a001_j与review_a001_h分别从W017完整动作链和长期清单边界确认。
- 当前限制：其他下载器实际delete_file映射与用户部署版本未验证。

### CHK-016：未完成下载状态可见与可恢复

- 状态：已确认
- 落实状态：已写入正式`docs/subscription-compatibility-checklist.md`；F-197按用户决定跳过TV单端修复，等待MoviePilot官方后端或Web改变下载任务列表合同时同步对齐。
- 建议内容：`下载列表必须保留所有未完成的downloading/pending/paused/stopped任务，并排除所有已完成任务，即使其状态同为stopped；暂停或停止项在下一轮poll后仍可见且可继续。`
- 来源：W017 / F-197。
- 复用价值：下载器状态枚举与completed维度并非一一对应；只按少数字符串筛选会让可恢复任务从TV/Web共同消失。
- 相关文件/测试：各downloader状态×completed矩阵，以及stop→poll→仍在→start的只读fixture/临时任务流程。
- 独立复核：review_a001_j与review_a001_h独立确认该状态合同与CHK-012的owner身份合同不同，值得单列。
- 当前限制：G05已静态确认qBittorrent/Transmission暂停项会从当前查询消失，rTorrent实现不同；当前行为保持不变。以后官方返回paused/stopped、增加状态参数或Web恢复继续入口时，必须重开兼容检查。

### CHK-017：Mutation 2xx 响应失败关闭

- 状态：已确认
- 建议内容：`Mutation成功必须满足该端点声明的合法响应envelope；任意非空malformed、primitive/array、非对象或缺success的2xx都必须失败关闭。空白/空body或204只有端点显式声明no-content合同时才算成功，禁止全局fallback。`
- 来源：W017 / F-083；G03 / F-245。
- 复用价值：新增或调整mutation端点时，transport 2xx不能替代业务成功；通用fail-open会让TV乐观翻状态或删行，掩盖真实失败。
- 相关文件/测试：200 success true/false、missing success、malformed、primitive/array、空白/空body与204 allowed/disallowed矩阵，并断言UI不乐观翻状态或移除任务。
- 独立复核：review_a001_j与review_a001_h确认端点级no-content allowlist是最小边界，F-092/F-093仍只是TV本地动作owner/错误呈现，不另建CHK。
- G03传播：Fork使用独立的typed decoder，missing/null `success`加任意ID仍被接受；主审及两名纠偏复核确认F-245须保留独立finding，但由本CHK与F-083共同验收严格envelope，不能因共用清单而合并代码修复。
- 当前限制：各生产mutation端点的空body/204正式合同未验证。

### CHK-018：资源搜索站点权威域与 default/all/specific 三态

- 状态：已确认
- 建议内容：`资源搜索可选站点必须来自当前账号以search权限可读的active searchable权威集合，不得以RSS订阅站点、数据库全表或其他配置子集替代。选择状态明确区分“后端默认IndexerSites”“全部active searchable IDs”“显式子集”；default可省略参数，全部必须发送全部权威ID或准确命名为默认。只有权威域成功加载后才能归一化既有选择，inactive/未知值先显式提示并由用户确认清除。`
- 来源：W020-D / F-209/F-210，并传播F-112/F-170。
- 复用价值：RssSites、IndexerSites、站点active状态、权限端点或Web选择器任一变化都会重新造成“显示集合、持久集合、实际执行集合”漂移。
- 相关文件/测试：System/SiteFilter/Search站点设置与请求；后端active/inactive、`RssSites != IndexerSites`固定fixture；default/all/specific矩阵、search-only无manage用户、非RSS active保留及F-170未知值清除边界。只读或mock，不改真实配置。
- 独立复核：review_a001_h明确建议长期保留；verify_a001_h第三裁决确认F-209/F-210保持两条独立P2，但由本条共同验收。矩阵还须覆盖SSE/普通fallback、标题/ID搜索一致，以及search-only用户可读而不要求manage。
- 当前限制：真实部署站点集合分布、可用search权限安全描述符端点、远端上游最新性未验证。

### CHK-019：媒体搜索 source 参数必须具有真实执行语义

- 状态：已确认
- 建议内容：`当TV/Web暴露具体媒体搜索来源时，后端OpenAPI/路由必须声明source参数、允许值与默认值并在搜索链真实执行；客户端按同一规范来源校验返回项。兼容测试必须断言返回来源归属或后端捕获的真实执行参数，不能只断言URL带source。未支持来源不得出现在设置或选择器中。`
- 来源：W001/W012/W018-A/W020-D / F-189。
- 复用价值：媒体来源枚举、后端全局SEARCH_SOURCE、聚合搜索与高级ID写链变化会反复让“参数已发送”产生假兼容；F-188/F-189在旧v2.14.4合同下的误配机制仅作为升级反例保留，目标v2.15.1已驳回。
- 相关文件/测试：System默认媒体来源、ManualMediaSearch、SearchViewModel/SharedMediaFetcher、`/media/search` OpenAPI/endpoint与混合来源fixture；覆盖nil默认、每个允许值、AniList支持/拒绝及响应source owner。保持只读，不把真实后端搜索当副作用。
- 独立复核：review_a001_h提出长期合同；verify_a001_h第三裁决确认当前后端端点无source参数、现有TV/兼容测试只查query或不查返回owner会假通过。每个显式来源须断言provider实际调用或非空响应全部同owner，空结果不能充当成功证据。
- 当前限制：当前允许来源集合、AniList产品边界、远端上游最新性及正式清单去重未验证。

### CHK-020：服务端 manage 资源授权必须覆盖读取端点

- 状态：已确认
- 建议内容：`凡TV/Web仅向manage用户展示的资源页，后端对应读取与mutation端点都必须在查询、返回或执行前依赖当前active manage用户（显式API Key/API Token超管例外须单列）；无manage的有效JWT即使直接访问路由或API，也不得获得记录、总量、路径、FileItem、下载器/hash或执行结果。客户端菜单、Tab和路由隐藏只作UX，不是安全边界。`
- 来源：G09 / F-246。
- 复用价值：权限快照与session epoch只能约束客户端异步owner，无法阻止同一新鲜低权限会话直接访问漏挂dependency的端点；后端新增读接口或调整页面权限时极易再次只保护菜单而漏资源授权。
- 当前证据：TV按manage隐藏Status并在TransferHistoryViewModel请求前复核；Web菜单按manage隐藏，但`#/history`路由只要求登录；当前后端GET `/history/transfer`只依赖`verify_token`，而同资源DELETE/AI端点使用active-manage依赖。查询全局无owner过滤并通过`to_dict()`返回路径、嵌套FileItem、storage、downloader/hash等列。
- 相关测试/文件：把GET history endpoint加入后端manage dependency矩阵；以无manage JWT直接请求普通分页与`count=-1`均须拒绝且不含data，manage用户成功，显式API Key/API Token例外按产品合同测试；Web直接路由与TV低权限调用只作客户端防御测试。全为只读授权验证，不触发整理mutation。
- 独立复核：G09两名代理先独立确认P1；随后全新clean-room代理不读审计文档，从TV/Web/后端与现有授权测试重新确认这是独立服务端垂直授权问题，不能并入CHK-005会话/权限快照owner，也不能由客户端补丁关闭。
- 当前限制：用户实际部署版本、远端最新性、API Token映射策略及真实低权限账号使用频率未验证；未运行后端或HTTP测试。
