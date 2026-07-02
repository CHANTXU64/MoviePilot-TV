# 订阅兼容契约与更新检查清单

本文档记录 TV 端订阅状态、媒体 ID、`episode_group`、跨源详情页 Header 订阅按钮、订阅缓存与刷新时机的跨端对齐点。以后同步 MoviePilot 后端或 MoviePilot Web 前端时，必须检查本文件列出的契约是否仍成立；如果不成立，需要同步评估 TV 端实现、测试和用户交互。

这不是完整兼容审查清单。常规接口、模型、图片、导航和 tvOS 行为仍要按正常流程检查；这里只列出订阅相关的重点风险，避免后续 MP 前后端更新时漏掉关键契约。

## 用户权限契约风险

MoviePilot 后端普通用户权限契约仍不稳定，后续版本可能有较大调整。当前不能把 `Token.super_user`、`permissions.discovery`、`permissions.search`、`permissions.subscribe`、`permissions.manage` 简单理解为所有接口的最终授权规则；真实后端仍可能对部分接口使用超管校验、内部业务校验，或返回 400/403 这类权限失败。

后续同步 MoviePilot 后端或 Web 前端时，必须重新确认：

- `Token.super_user` 和 `permissions` 字段的含义是否变化。
- `401`、`403`、`400` 的会话/权限语义必须对照后端代码确认，不要只按 HTTP 状态码推断是否应该刷新 token 或登出。当前 `app/core/security.py` 中无认证信息是 `401 Not authenticated`，缺少/错误用途/解码失败的 token 校验是 `403`（例如 `token校验不通过`）；`app/db/user_oper.py` 中用户不存在/未激活是 `403`，非超管是 `400 用户权限不足`。
- 登录响应里的 `permissions` 是否仍来自 `app/api/endpoints/login.py` 的 `user_or_message.permissions or {}`，并且仍是 Web/TV 功能入口过滤依据；不要把 `permissions.discovery` / `permissions.search` / `permissions.subscribe` / `permissions.manage` 直接推断成后端每个接口都会按同一权限项授权。
- 订阅相关接口是否真正与 `permissions.subscribe` 对齐。
- 订阅页面、详情页或分季页里夹带的媒体服务器状态接口是否仍只是普通 token 权限；当前 `/mediaserver/notexists` 这类“已入库/缺失”状态只影响展示，不是订阅主流程，TV 端应在 `permissions.subscribe == true` 时探测，且不得要求 `Token.super_user`。
- 对可选状态探测接口，即使 Web 端只是 `catch` 后忽略错误，TV 端也不能让 401/403 触发自动登出；这类 best-effort 探测应使用不会清理会话的请求路径，并补受限用户测试。
- 未执行、失败或无权限执行媒体服务器状态探测时，TV 分季页必须不显示入库状态徽章，不能把未知当成“已入库”；创建分季订阅时也不能因此默认开启 `best_version` 洗版。
- 普通用户在 Web 端能看到哪些入口，不能访问时 Web 是隐藏、禁用还是报错。
- TV 端是否仍应自动隐藏发现、搜索、状态、管理类入口；不要用笼统的“非超管权限不足”文案替代具体入口隐藏。
- Web 端 `filterMenusByPermission` / `hasPermission` 是否仍按原始权限对象判断 `permissions[key] === true`；TV 端的 `Token.canAccess(_:)`、入口隐藏和对应测试必须同步更新，不能只改其中一层。
- 四个单权限真实后端账号必须通过 `MOVIEPILOT_COMPAT_PERMISSION_BEHAVIOR_ACCOUNTS` / `MOVIEPILOT_COMPAT_PERMISSION_PASSWORDS` 只跑 `BackendCompatibilityPermissionBehaviorTests`；不要把它们放进普通 `MOVIEPILOT_COMPAT_ADDITIONAL_USERNAMES` 兼容矩阵里反复巡检 read-only / side-effect 接口。

如果后端新增更细的权限项、改名、调整返回结构，或把现有普通用户权限改成可访问更多/更少订阅能力，不能只改 UI 文案；需要同步更新 Token 解码、权限判断、真实后端兼容测试和订阅副作用测试。

## 当前契约

- 同一媒体同一季只有一条订阅。
- `episode_group` 是订阅配置，不是订阅身份的一部分。
- 创建订阅时可以带 `episode_group`。
- 查询某媒体某季是否已订阅时，只按媒体和季判断，不按 `episode_group` 判断。
- 取消某媒体某季订阅时，后端媒体删除接口也是媒体和季语义，不按 `episode_group` 删除。
- TV 分季页展示的已订阅状态必须来自真实订阅记录上的 `episode_group`，不能来自当前 Picker 选择。
- TV 分季页取消已订阅季时，应优先按订阅 `id` 删除这条唯一订阅。
- `/subscribe/` 快照是首页订阅列表、详情页订阅状态和分季订阅状态的共享数据源；几十或上百季电视剧不能退回逐季调用 `/subscribe/media/{mediaid}`。
- `POST /subscribe/` 创建订阅时必须保留 `mediaid` fallback；当 `tmdbid`、`doubanid`、`bangumiid` 不足以标识媒体时，后端仍可用 `mediaid` 识别来源。
- MoviePilot v2.14.0 起，`best_version` 和 `best_version_full` 的空值语义变为“使用后端默认订阅配置”。TV 端未明确选择普通/洗版/全集洗版时必须省略这两个字段，不能用 `0` 代替；显式发送 `0` 才表示普通订阅或关闭洗版。
- TV 分季页只有在已确认某季完整入库时，才显式发送 `best_version: 1` 和 `best_version_full: 1`，表示全集洗版；未知入库状态或仍有缺失集时应省略洗版字段，让后端应用默认配置。
- 订阅保存必须保留后端返回且 TV 不直接编辑的状态字段，例如复杂结构的 `note`、`episode_priority`、`vote`、`filter`、`username`、`current_priority` 和 `date`；派生进度字段 `completed_episode` 可以解码用于展示或兼容，但保存 payload 中不要回传它覆盖后端计算结果。

## 媒体 ID 归一化契约

TV 端、MoviePilot Web 前端和 MoviePilot 后端当前都把 `tmdbid: 0`、`bangumiid: 0` 和空字符串 ID 当成无效 ID。订阅身份归一化时必须先过滤这些无效值，再 fallback 到后端返回的 `mediaid` 或媒体详情上的 `mediaid_prefix + media_id`。

这条契约很容易因为 Swift、JavaScript 和 Python 的真假值差异出错：

- Swift 的 `if let tmdbid` 只判断是否为 `nil`，`0` 会通过。
- JavaScript 的 `if (tmdbid)` 会把 `0` 当成 false。
- Python 的 `if tmdbid` 也会把 `0` 当成 false。

因此 TV 端不能直接把“字段存在”当作“ID 有效”。这些值都应视为无效，并继续尝试 fallback：

- `tmdbid == nil` 或 `tmdbid <= 0`。
- `bangumiid == nil` 或 `bangumiid <= 0`。
- `doubanid == nil` 或 trim 后为空字符串。
- `mediaid` trim 后为空、缺少真实 id、或形如 `tmdb:0` / `bangumi:0`。

当前订阅快照匹配顺序应保持为：

1. 有效 `tmdbid` -> `tmdb:<id>`。
2. 有效 `doubanid` -> `douban:<id>`。
3. 有效 `bangumiid` -> `bangumi:<id>`。
4. 有效 `mediaid` fallback。

媒体详情本身也适用同样规则：如果详情 payload 里有 `tmdb_id: 0`，但同时有 `mediaid_prefix: "tmdb"` 和 `media_id: "12345"`，TV 端应得到 `tmdb:12345`，不能得到 `tmdb:0`。

后续 MP 更新时，如果后端开始把 `0` 赋予有效业务含义，或者 Web 改成显式发送/匹配 `tmdb:0`，这不是小修范围；需要同步修改 TV 端归一化规则、订阅快照匹配、取消确认统计和对应测试。

## 跨源详情页 Header 契约

MoviePilot Web v2.14.0 起，详情页订阅入口按媒体类型区分：

- 电影可以在详情页顶部直接订阅或取消。
- 所有电视剧，无论来自 TMDB、Douban 还是 Bangumi，都统一进入分季订阅流程。

因此 TV 端当前保持这个行为：

- `MediaInfo.canDirectlySubscribe` 只能对电影返回 `true`。
- 电视剧详情页顶部按钮只作为“分季订阅”入口，不直接创建整条目订阅，也不因为存在 `douban_id` 或 `bangumi_id` 改走一键订阅。
- 电视剧分季入口和预加载不能依赖 `tmdb_id != nil` 才显示或启动；Douban/Bangumi 详情也应能进入分季订阅流程。
- 剧集组数据仍只能在有 TMDB ID 时加载；缺少 TMDB ID 时不应阻断分季订阅入口本身。
- 分季页取消订阅仍优先按真实订阅 `id` 删除单条订阅，不把 Header 行为改造成媒体级批量删除。

如果以后 Web 或后端重新引入电视剧顶部直接订阅/取消，不能只改按钮文案；需要重新确认 TV 端是否应恢复媒体级删除、是否需要多季影响确认，以及分季页和 Header 的状态来源是否仍一致。

## 订阅缓存与刷新契约

订阅状态在 TV 端同时服务首页、详情页、分季页和预加载任务。后续改订阅相关逻辑时，必须保持这些刷新边界：

- `fetchSubscriptions(forceRefresh:)` 的普通读取可以复用短 TTL 快照；订阅快照缓存读取不续期，避免海报墙浏览不断延长旧订阅状态。
- `forceRefresh: true` 必须绕过旧缓存和旧 in-flight 请求；如果有更新的强刷请求开始，旧请求返回后不能覆盖新快照。
- `checkSubscription(media:season:)` 的 Bool 状态缓存只服务卡片、详情页 Header 和电影类轻量状态；分季页必须从 `/subscribe/` 快照映射，不能逐季查询。
- 保存、创建、删除、暂停/恢复、重置、手动搜索订阅、复用订阅成功后，必须同时清空订阅快照缓存和旧的 Bool 状态缓存。
- `baseURL`、token、登录会话变化时必须清空订阅缓存，避免跨服务器或跨账号污染。
- `.subscriptionDidUpdate`、页面回前台、取消前二次确认、详情页预加载完成后，都要强制刷新相关订阅状态。
- 手动“搜索订阅”也会改变远端订阅状态；成功后必须刷新首页订阅列表，并通知活跃详情页和分季页重新读取订阅状态。
- 活跃详情页持有的 `MediaPreloadTask` 收到订阅变更后需要刷新订阅状态；普通海报墙预加载缓存不要因为一次通知全量强刷，避免一次订阅操作触发大量请求。
- 取消前如果订阅已被其他设备删除，本机刷新为未订阅，不继续发起错误取消。

## 后端更新时重点检查

检查 `../MoviePilot` 中这些位置：

- `app/core/security.py`
  - `verify_token` / `__verify_token` 对无认证信息、缺少 token、token 用途不匹配、token 解码失败返回的状态码和 detail 是否变化。
  - 如果后端把普通功能权限不足也改成 `403`，需要同步重新评估 TV 端 `makeRequest` 的 401/403 会话处理策略和受限账号测试。
- `app/db/user_oper.py`
  - `get_current_active_user` / `get_current_active_user_async` 是否仍用 `403` 表示用户不存在或未激活。
  - `get_current_active_superuser` / `get_current_active_superuser_async` 是否仍用 `400 用户权限不足` 表示非超管。
- `app/api/endpoints/login.py`
  - 登录 token payload 是否仍返回 `permissions=user_or_message.permissions or {}`，且 Web/TV 仍以该对象作为功能入口可见性的来源。
- `app/api/endpoints/system.py`
  - `/system/env`、`GET /system/setting/{key}`、`POST /system/setting/{key}` 等端点实际依赖的是 active user 还是 active superuser；以 `Depends(...)` 为准，不能只看 summary 或注释里的“仅管理员”。
- `app/db/subscribe_oper.py`
  - `SubscribeOper.async_add` 是否仍用 `tmdbid` / `doubanid` + `season` 查重。
  - 如果查重条件新增 `episode_group`，说明后端开始支持同一媒体同一季多剧集组订阅，TV 分季状态模型需要重做。
- `app/db/models/subscribe.py`
  - `Subscribe.episode_group` 字段是否仍存在，类型和含义是否变化。
  - `Subscribe.async_exists` 是否仍不包含 `episode_group`。
  - `Subscribe.async_get_by_tmdbid` 是否仍按 `tmdbid + season` 返回订阅。
  - `Subscribe.async_get_by_tmdbid` 在未传 `season` 时是否仍返回该 TMDB 下全部订阅。
- `app/schemas/subscribe.py`
  - `Subscribe` schema 是否仍返回 `id`、`season`、`tmdbid`、`doubanid`、`bangumiid`、`episode_group`。
  - `Subscribe` schema 是否仍返回可 fallback 的 `mediaid`，并保持 `tmdb:<id>` / `douban:<id>` / `bangumi:<id>` 这类格式。
  - `Subscribe` schema 是否仍返回 `vote`、`filter`、`username`、`current_priority`、`date`、`note`、`episode_priority` 等保存时需要原样保留的状态字段。
  - `best_version` 和 `best_version_full` 是否仍是可空字段；如果后端再次改变空值和 `0` 的语义，TV 新建订阅 payload 必须重新评估。
  - 如果字段改名、嵌套、分页或拆分，需要同步更新 TV 解码和快照缓存。
- `app/api/endpoints/subscribe.py`
  - `GET /subscribe/` 是否仍返回当前用户完整订阅列表。
  - `GET /subscribe/` 返回的订阅快照中，`tmdbid: 0` / `bangumiid: 0` / 空 `doubanid` 是否仍只代表缺失 ID，而不是有效 ID。
  - `POST /subscribe/` 是否仍用 `episode_group` 和 `mediaid` 创建或更新订阅配置。
  - `POST /subscribe/` 是否仍把省略 `best_version` / `best_version_full` 理解为使用后端默认配置，把显式 `0` 理解为普通订阅或关闭洗版。
  - `GET /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/media/tmdb:<id>` 在未传 `season` 时是否仍会删除全部季。
  - `DELETE /subscribe/media/bangumi:<id>` 是否仍不是可用的媒体级删除目标。
  - `DELETE /subscribe/{subscribe_id}` 是否仍按订阅 id 删除单条订阅。
  - `GET /subscribe/search/{id}`、`POST /subscribe/fork`、`PUT /subscribe/status/{id}`、`GET /subscribe/reset/{id}` 成功后，是否仍可能改变订阅快照或状态字段。
- `app/core/context.py`
  - Douban/Bangumi 识别信息是否仍只是跨源识别上下文，不代表 Web 详情页开始提供 TMDB 分季列表。
  - 如果 Douban/Bangumi 详情开始正式携带 TMDB 分季数据，需要重新评估 TV 顶部取消订阅的交互。

如果后端开始支持“同一媒体同一季多个 `episode_group` 订阅”，不要只改 UI 文案。需要重新设计：

- 分季卡片是否显示多个订阅状态。
- 取消按钮取消哪一个剧集组。
- 当前 Picker 是否同时影响状态查询和取消。
- `/subscribe/` 快照如何索引为 `media + season + episode_group`。
- 首页、详情页、分季页和订阅编辑页如何同步这组状态。

## Web 前端更新时重点检查

检查 `../MoviePilot-Frontend` 中这些位置：

- `src/views/discover/MediaDetailView.vue`
  - 顶部直接订阅/取消按钮是否仍只覆盖电影。
  - 所有电视剧是否仍通过分季列表和分季订阅入口处理，不因 Douban 或 Bangumi ID 改走直接订阅。
  - `getMediaId()` 是否仍把 `tmdb_id: 0` / `bangumi_id: 0` / 空 `douban_id` 当成无效值，并 fallback 到 `mediaid_prefix + media_id`。
  - 电影直接取消是否仍使用 `/subscribe/media/{mediaid}`，并且未传 `season` 时保持媒体级取消语义。
  - 如果 Web 重新让电视剧详情页顶部执行直接取消，TV 需要同步评估多季影响提示和删除语义。
- `src/components/cards/MediaCard.vue`
  - `getMediaId()` 是否仍使用 truthy 判断选择 `tmdb_id` / `douban_id` / `bangumi_id`，并在这些 ID 无效时 fallback 到 `mediaid_prefix + media_id`。
- `src/components/dialog/SubscribeSeasonDialog.vue`
  - 分季弹窗是否仍只把选择的 `seasons` 和 `episodeGroup` 用于创建订阅。
  - 创建分季订阅时传给后端的 `mediaid` 是否仍来自 Web 的 `getMediaId()` 规则。
  - 未选择普通/洗版/全集洗版时，是否仍省略 `best_version` / `best_version_full`，由后端默认配置决定。
  - 已完整入库季是否仍显式发送全集洗版字段。
  - 是否新增了分季已订阅状态、取消订阅或按剧集组判断状态的 UI。
- 订阅卡片和详情页相关组件
  - 是否仍使用后端现有媒体级订阅状态。
  - 订阅卡片上的 `getMediaId()` 是否仍把 `tmdbid: 0` / `bangumiid: 0` / 空 `doubanid` 当成无效值，并 fallback 到订阅记录的 `mediaid`。
  - 手动搜索、暂停/恢复、重置、编辑、复用订阅后，Web 是否立即重新拉取订阅列表或依赖后端返回的新状态。
  - 如果 Web 开始显示“已订阅 · 剧集组名”，TV 应对齐文案和交互。
- 前端请求封装和缓存策略
  - `/api/v1/subscribe/` 是否仍不被长期缓存。
  - 如果 Web 增加订阅列表缓存、分页、筛选或增量同步，TV 的快照 TTL、强刷和刷新入口需要复核。

如果 Web 改成按剧集组精确订阅/取消，但后端接口没有对应变化，应先确认 Web 是否只是 UI 层误导，不能让 TV 单独发明不同语义。

## TV 端更新时重点检查

检查本仓库这些位置：

- `MoviePilot-TV/Services/APIService.swift`
  - 权限控制优先放在页面入口、按钮入口和自动预取根节点；`APIService` 不要批量伪造 `[]` / `false` / `nil`，真实调用应交给后端鉴权。
  - 修改 `makeRequest` 的 401/403 处理前，必须先按 `../MoviePilot` 后端代码确认这些状态码在当前版本的语义。当前不能只因 `403` 字面含义就把所有 403 改成非登出，也不能把 `400 用户权限不足` 当成需要刷新会话；只有后端确实把普通功能权限不足改成 403 时，才同步调整 TV 端受限请求策略和兼容测试。
  - Dashboard、下载管理、首页最近入库、整理历史等 Web 菜单入口按 `permissions.manage` 对齐；但真实后端仍按超管限制 `/dashboard/*`、`/system/setting/MediaServers` 和首页媒体服务器最近入库预取，非超管 TV 端应在 ViewModel 入口跳过这些后台请求，下载与整理等 manage 功能请求继续交给后端鉴权。
  - 搜索/订阅页面入口仍分别按 `permissions.search` / `permissions.subscribe` 控制；但 `CustomFilterRules`、`UserFilterRuleGroups` 当前没有可用 public 配置项，普通用户会收到 `400 用户权限不足`，TV 端只能在超管会话下预取并应用这些自定义规则。`Storages`、`Directories`、`IndexerSites` 这类已公开配置应改走 `/system/setting/public/{key}`。
  - 自动预取根节点包括首页订阅列表、详情/卡片预加载订阅状态、分季页订阅状态、聚合搜索里的订阅分享分页器、探索页“订阅分享”来源。无 `permissions.subscribe` 时这些入口不能发起 `/subscribe` 请求；按钮入口可以按权限提前返回，但 `APIService` 订阅方法不要再各自加一层假返回。
  - `Token.super_user == true` 时全部功能可见；普通用户只在 `permissions.<key> == true` 时获得对应功能，`permissions == nil` 或 `{}` 都不能按默认权限放行。这里对齐 Web 登录阶段用原始 `response.permissions` 过滤菜单的行为，不对齐登录后 store merge `DEFAULT_PERMISSIONS` 的持久化默认值；同步 Web 登录逻辑时必须复核这条规则。
  - `checkSeasonsNotExists(mediaInfo:)` 只能作为可选的媒体服务器状态查询；当前后端和 Web 只要求登录即可读取 `/mediaserver/notexists`，`APIService` 不要为它伪造空结果。TV 端如需避免隐藏的分季订阅 UI 自动预取，只能在对应 ViewModel 入口用 `canAccess(.subscribe)` 停掉这一条后台加载，并保证权限失败时返回空状态、保留订阅主流程、不能触发会话登出。
  - `fetchSubscriptions(forceRefresh:)` 是否仍能一次拉取订阅列表快照。
  - 订阅快照缓存是否仍是短 TTL，且读取不续期。
  - `forceRefresh: true` 是否仍绕过缓存和旧 in-flight 请求。
  - 创建、保存、删除、暂停、恢复、重置、搜索、复用订阅成功后是否清空订阅快照缓存和旧的 Bool 状态缓存。
  - `baseURL` 和 token 变化后是否清空订阅缓存。
  - `checkSubscription(media:season:)` 可以继续服务电影、详情页或卡片场景，但分季页不要重新退回逐季调用。
  - `fetchSubscriptionLookup(media:season:)` 是否仍能从 lookup 响应解析出真实 `tmdbid` / `doubanid` / `bangumiid` 归属。
- `MoviePilot-TV/Models/Models.swift`
  - `MediaInfo.apiMediaId` 和 `Subscribe.apiMediaId` 是否仍共用同一套 ID 归一化规则。
  - `MediaInfo.canDirectlySubscribe` 是否仍只允许电影直接订阅；所有电视剧应进入分季订阅。
  - `SubscribeRequest` 是否仍能省略 `best_version` / `best_version_full`，并保留 `mediaid` fallback。
  - `tmdbid: 0`、`bangumiid: 0` 和空白 `doubanid` 是否仍会 fallback 到有效 `mediaid`。
  - `tmdb:0` / `bangumi:0` 是否仍被视为无效 fallback，不参与订阅匹配。
  - `Subscribe` 解码/保存是否仍保留后端维护的 `note`、`episode_priority`、`vote`、`filter`、`username`、`current_priority`、`date` 等状态字段，且不把派生进度字段 `completed_episode` 回传给保存接口。
  - 首页从订阅卡片进入详情页时，是否仍保留订阅记录里的 fallback `mediaid`，避免把 `tmdbid: 0 + mediaid` 重建成不可匹配的详情媒体。
- `MoviePilot-TV/ViewModels/HomeViewModel.swift`
  - 首页订阅列表刷新是否能用 `forceRefresh: true` 绕过旧快照。
  - 手动搜索订阅成功后，是否刷新首页订阅列表并发送 `.subscriptionDidUpdate`。
  - 暂停/恢复、重置、删除订阅成功后，是否重新拉取最新订阅列表。
- `MoviePilot-TV/ViewModels/MediaDetailViewModel.swift`
  - 电视剧详情是否仍启用分季订阅入口，且不要求原始详情 payload 必须带 `tmdb_id`。
  - 电影直接订阅/取消后是否用 `forceRefresh: true` 刷新 Header 和相关订阅状态。
  - 如果保留历史媒体级取消路径，是否只在电影或明确兼容场景使用，不能让电视剧绕过分季订阅。
- `MoviePilot-TV/ViewModels/MediaPreloader.swift`
  - 详情页预加载完成后，是否刷新已有活跃详情页的订阅状态。
  - `.subscriptionDidUpdate` 是否只刷新被详情页 pin 住的活跃任务，避免海报墙缓存全量强刷。
- `MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift`
  - 分季订阅状态是否仍按 `media + season` 从 `/subscribe/` 快照映射。
  - 分季订阅快照匹配是否使用统一 ID 归一化规则，避免 `tmdbid: 0` 或 `bangumiid: 0` 遮蔽有效 `mediaid`。
  - `selectedGroupId` 是否只影响新建订阅的 `episode_group`。
  - 未明确选择洗版模式时是否省略 `best_version` / `best_version_full`；已完整入库季是否显式设置 `best_version: 1` 和 `best_version_full: 1`。
  - 已订阅状态显示是否来自订阅记录上的 `episode_group`。
  - 取消订阅前是否强制刷新订阅摘要。
  - 取消订阅是否优先使用订阅 `id`。
- `MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift`
  - 已订阅卡片是否显示真实订阅配置，例如 `已订阅 · 默认剧集组` 或 `已订阅 · 剧集组 A`。
  - 取消确认框是否明确剧名、季号和当前订阅使用的剧集组。
  - 页面回前台或收到 `.subscriptionDidUpdate` 后是否强制刷新订阅状态。
- 首页和详情页刷新入口
  - 首页编辑订阅剧集组后，相关页面是否能收到通知或重新拉取状态。
  - 其他设备修改订阅后，进入分季页、回到前台、取消前二次确认是否不会使用旧状态误删。

## 必跑测试

分季订阅逻辑改动后，至少运行：

```sh
xcodebuild test \
  -project "MoviePilot-TV.xcodeproj" \
  -scheme "MoviePilot-TV" \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  -only-testing:MoviePilot-TV-Tests/SubscribeSeasonContentViewTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation
```

如果改动涉及详情页 Header 的订阅/取消订阅行为，还应至少运行：

```sh
xcodebuild test \
  -project "MoviePilot-TV.xcodeproj" \
  -scheme "MoviePilot-TV" \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  -only-testing:MoviePilot-TV-Tests/MediaDetailViewHeaderActionTests \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation
```

完整验证仍按 `AGENTS.md` 执行依赖解析、Simulator build 和完整 test。涉及真实后端契约时，还应按 `docs/backend-compatibility-tests.md` 运行真实后端兼容测试。

重点保留或补充这些用例：

- 默认分组订阅第 1 季后，切到其他剧集组，第 1 季仍显示 `已订阅 · 默认剧集组`。
- 剧集组 A 订阅第 1 季后，切到默认或剧集组 B，第 1 季仍显示 `已订阅 · 剧集组 A`。
- 当前 Picker 的 `episode_group` 不参与已订阅身份判断。
- 已订阅卡片点击取消时，确认框显示真实剧名、季号和剧集组。
- 电影仍可直接订阅，电视剧即使有 TMDB、Douban 或 Bangumi ID 也不能直接订阅，必须进入分季订阅。
- 新建订阅未设置洗版模式时，payload 省略 `best_version` / `best_version_full`；显式 `0` 仍应保留。
- 已完整入库季创建分季订阅时，payload 同时包含 `best_version: 1` 和 `best_version_full: 1`。
- 部分缺失或未知入库状态的季创建订阅时，payload 省略洗版字段，由后端默认配置决定。
- 订阅快照里 `tmdbid: 0 + mediaid: "tmdb:<有效 ID>"` 时，分季页仍显示已订阅并能按订阅 `id` 取消。
- 订阅快照里 `bangumiid: 0 + mediaid: "tmdb:<有效 ID>"` 时，分季页仍能通过 fallback 匹配。
- 订阅快照里空白 `doubanid + mediaid: "tmdb:<有效 ID>"` 时，分季页仍能通过 fallback 匹配。
- 媒体详情 payload 里 `tmdb_id: 0` / 空白 `douban_id` / `bangumi_id: 0` 时，仍能 fallback 到 `mediaid_prefix + media_id`。
- 电视剧详情页和预加载不再因为原始 `tmdb_id == nil` 隐藏或跳过分季订阅入口；剧集组加载仍只在有 TMDB ID 时执行。
- 订阅编辑保存时保留 `note`、`episode_priority`、`vote`、`filter`、`username`、`current_priority`、`date`，但不回传 `completed_episode`。
- 首页订阅卡片跳详情时，`Subscribe` 重建出的 `MediaInfo` 仍保留有效 fallback `mediaid`。
- 取消前如果订阅已被其他设备删除，本机刷新为未订阅，不继续发起错误取消。
- 首页订阅列表通知刷新、页面回前台刷新、手动搜索订阅后的刷新都能绕过缓存。
- 并发强制刷新时，旧的订阅快照响应、错误或缓存写入不能覆盖更新后的快照。
- 几十或上百季电视剧只触发一次订阅列表快照请求，不重新逐季调用 `/subscribe/media/{mediaid}`。

## 需要立即重新设计的信号

看到下面任一变化，不要只做小修：

- 后端或 Web 开始把 `tmdbid: 0`、`bangumiid: 0` 或 `tmdb:0` 当成有效媒体身份。
- 后端订阅快照不再返回 `mediaid` fallback，或 `mediaid` 格式不再是 `<source>:<id>`。
- Web 的 `getMediaId()` 不再使用当前 fallback 顺序，或开始优先使用不同字段作为订阅身份。
- 后端订阅唯一性加入 `episode_group`。
- 后端新增按 `episode_group` 查询或删除订阅的正式 API。
- `GET /subscribe/` 改成分页、筛选、按状态默认过滤或不再返回完整订阅。
- `GET /subscribe/media/{mediaid}` 返回不再包含可解析的订阅归属 ID。
- `DELETE /subscribe/media/tmdb:<id>` 未传 `season` 时不再删除全部季，或新增了明确的批量取消确认契约。
- 后端正式支持或要求 `DELETE /subscribe/media/bangumi:<id>`，导致当前 fallback 到订阅 `id` 删除的策略需要重审。
- `episode_group` 从字符串改成对象、数组或其他结构。
- Web 分季弹窗开始支持同一季多个剧集组订阅状态。
- Web 分季弹窗开始提供按剧集组取消订阅。
- Web 详情页顶部订阅按钮重新开始覆盖电视剧，或 Douban/Bangumi 详情页开始使用不同于当前分季入口的订阅模型。
- 后端再次改变 `best_version` / `best_version_full` 的空值和 `0` 语义。
- 订阅列表缓存、分页或增量同步改成后端正式契约。
- 订阅修改在后端变成局部 patch，并且 `episode_group` 更新不再触发现有订阅刷新事件。
