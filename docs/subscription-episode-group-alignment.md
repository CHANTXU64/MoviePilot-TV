# 分季订阅与剧集组对齐清单

本文档记录 TV 端分季订阅状态、取消订阅、`episode_group` 以及跨源详情页 Header 订阅按钮的跨端对齐点。以后同步 MoviePilot 后端或 MoviePilot Web 前端时，优先检查本文件列出的契约是否仍成立；如果不成立，需要同步评估 TV 端实现和测试。

这不是完整兼容审查清单。常规接口、模型、图片、导航和 tvOS 行为仍要按正常流程检查；这里只列出分季订阅与剧集组相关的重点风险。

## 当前契约

- 同一媒体同一季只有一条订阅。
- `episode_group` 是订阅配置，不是订阅身份的一部分。
- 创建订阅时可以带 `episode_group`。
- 查询某媒体某季是否已订阅时，只按媒体和季判断，不按 `episode_group` 判断。
- 取消某媒体某季订阅时，后端媒体删除接口也是媒体和季语义，不按 `episode_group` 删除。
- TV 分季页展示的已订阅状态必须来自真实订阅记录上的 `episode_group`，不能来自当前 Picker 选择。
- TV 分季页取消已订阅季时，应优先按订阅 `id` 删除这条唯一订阅。

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

MoviePilot Web 当前只有这些入口会在详情页顶部直接显示订阅/取消订阅按钮：

- 电影。
- 有 `douban_id` 的详情页。
- 有 `bangumi_id` 的详情页。

电视剧的 TMDB 详情页不走顶部一键订阅/取消订阅，而是展示 TMDB 分季数据和分季订阅入口。Douban 和 Bangumi 详情页本身没有 Web 意义上的 TMDB 分季列表，它们是整条目详情入口；只有 TMDB 数据源才提供可枚举的分季数据。

因此 TV 端当前保持这个行为：

- Douban/Bangumi 详情页可以通过预加载识别到的 TMDB ID 判断“已订阅”。
- 如果 Douban/Bangumi 详情页顶部取消订阅命中的是 TMDB 订阅，TV 端仍按后端/Web 的媒体级删除语义调用 `/subscribe/media/tmdb:<id>`，不额外发明按季拆分删除。
- 后端对 TMDB 且未传 `season` 的媒体级删除会删除该 TMDB 下全部订阅季。
- 因为这个场景通常只发生在 Douban/Bangumi 详情页顶部取消已经存在的多个 TMDB 分季订阅，TV 端只在确认弹窗里提示“会一并取消多个分季订阅”，不把取消路径改造成复杂的逐季选择流程。

如果以后 Web 或后端改变了上述前提，不能只改文案；需要重新确认 TV 端 Header 是否还应该通过 TMDB fallback 显示已订阅、是否还应该允许媒体级删除、以及是否需要给用户选择具体季。

## 后端更新时重点检查

检查 `../MoviePilot` 中这些位置：

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
  - 如果字段改名、嵌套、分页或拆分，需要同步更新 TV 解码和快照缓存。
- `app/api/endpoints/subscribe.py`
  - `GET /subscribe/` 是否仍返回当前用户完整订阅列表。
  - `GET /subscribe/` 返回的订阅快照中，`tmdbid: 0` / `bangumiid: 0` / 空 `doubanid` 是否仍只代表缺失 ID，而不是有效 ID。
  - `POST /subscribe/` 是否仍用 `episode_group` 创建或更新订阅配置。
  - `GET /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/media/tmdb:<id>` 在未传 `season` 时是否仍会删除全部季。
  - `DELETE /subscribe/{subscribe_id}` 是否仍按订阅 id 删除单条订阅。
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
  - 顶部订阅按钮条件是否仍是电影、Douban 或 Bangumi 详情。
  - TMDB 电视剧详情是否仍通过分季列表和分季订阅入口处理。
  - `getMediaId()` 是否仍把 `tmdb_id: 0` / `bangumi_id: 0` / 空 `douban_id` 当成无效值，并 fallback 到 `mediaid_prefix + media_id`。
  - `removeSubscribe` 是否仍使用 `/subscribe/media/{mediaid}`，并且未传 `season` 时保持媒体级取消语义。
  - 如果 Web 在 Douban/Bangumi 详情页新增“取消前展示会影响多个 TMDB 季”的提醒，TV 文案应同步。
- `src/components/cards/MediaCard.vue`
  - `getMediaId()` 是否仍使用 truthy 判断选择 `tmdb_id` / `douban_id` / `bangumi_id`，并在这些 ID 无效时 fallback 到 `mediaid_prefix + media_id`。
- `src/components/dialog/SubscribeSeasonDialog.vue`
  - 分季弹窗是否仍只把选择的 `seasons` 和 `episodeGroup` 用于创建订阅。
  - 创建分季订阅时传给后端的 `mediaid` 是否仍来自 Web 的 `getMediaId()` 规则。
  - 是否新增了分季已订阅状态、取消订阅或按剧集组判断状态的 UI。
- 订阅卡片和详情页相关组件
  - 是否仍使用后端现有媒体级订阅状态。
  - 订阅卡片上的 `getMediaId()` 是否仍把 `tmdbid: 0` / `bangumiid: 0` / 空 `doubanid` 当成无效值，并 fallback 到订阅记录的 `mediaid`。
  - 如果 Web 开始显示“已订阅 · 剧集组名”，TV 应对齐文案和交互。
- 前端请求封装和缓存策略
  - `/api/v1/subscribe/` 是否仍不被长期缓存。
  - 如果 Web 增加订阅列表缓存、分页或增量同步，TV 的快照 TTL 和刷新时机需要复核。

如果 Web 改成按剧集组精确订阅/取消，但后端接口没有对应变化，应先确认 Web 是否只是 UI 层误导，不能让 TV 单独发明不同语义。

## TV 端更新时重点检查

检查本仓库这些位置：

- `MoviePilot-TV/Services/APIService.swift`
  - `fetchSubscriptions(forceRefresh:)` 是否仍能一次拉取订阅列表快照。
  - 创建、保存、删除、暂停、恢复、重置订阅成功后是否清空订阅快照缓存和旧的 Bool 状态缓存。
  - `checkSubscription(media:season:)` 可以继续服务电影、详情页或卡片场景，但分季页不要重新退回逐季调用。
  - `fetchSubscriptionLookup(media:season:)` 是否仍能从 lookup 响应解析出真实 `tmdbid` / `doubanid` / `bangumiid` 归属。
- `MoviePilot-TV/Models/Models.swift`
  - `MediaInfo.apiMediaId` 和 `Subscribe.apiMediaId` 是否仍共用同一套 ID 归一化规则。
  - `tmdbid: 0`、`bangumiid: 0` 和空白 `doubanid` 是否仍会 fallback 到有效 `mediaid`。
  - `tmdb:0` / `bangumi:0` 是否仍被视为无效 fallback，不参与订阅匹配。
  - 首页从订阅卡片进入详情页时，是否仍保留订阅记录里的 fallback `mediaid`，避免把 `tmdbid: 0 + mediaid` 重建成不可匹配的详情媒体。
- `MoviePilot-TV/ViewModels/MediaDetailViewModel.swift`
  - Douban/Bangumi Header 取消订阅如果命中 TMDB fallback，是否仍按媒体级删除。
  - 多个 TMDB 分季订阅受影响时，确认文案是否仍提示会一并取消。
  - 多季取消确认统计是否按归一化后的 `tmdb:<id>` 匹配订阅快照，而不是只比较原始 `tmdbid` 字段。
  - 确认文案查询失败时，是否回退到普通确认文案，而不是阻塞取消流程。
- `MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift`
  - 分季订阅状态是否仍按 `media + season` 从 `/subscribe/` 快照映射。
  - 分季订阅快照匹配是否使用统一 ID 归一化规则，避免 `tmdbid: 0` 或 `bangumiid: 0` 遮蔽有效 `mediaid`。
  - `selectedGroupId` 是否只影响新建订阅的 `episode_group`。
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
- Douban/Bangumi Header 取消订阅命中多个 TMDB 分季订阅时，确认框提示会一并取消多个季。
- 订阅快照里 `tmdbid: 0 + mediaid: "tmdb:<有效 ID>"` 时，分季页仍显示已订阅并能按订阅 `id` 取消。
- 订阅快照里 `bangumiid: 0 + mediaid: "tmdb:<有效 ID>"` 时，分季页仍能通过 fallback 匹配。
- 订阅快照里空白 `doubanid + mediaid: "tmdb:<有效 ID>"` 时，分季页仍能通过 fallback 匹配。
- 媒体详情 payload 里 `tmdb_id: 0` / 空白 `douban_id` / `bangumi_id: 0` 时，仍能 fallback 到 `mediaid_prefix + media_id`。
- Header 多季取消确认统计能包含 `tmdbid: 0 + mediaid: "tmdb:<有效 ID>"` 的订阅快照。
- 首页订阅卡片跳详情时，`Subscribe` 重建出的 `MediaInfo` 仍保留有效 fallback `mediaid`。
- 取消前如果订阅已被其他设备删除，本机刷新为未订阅，不继续发起错误取消。
- 几十或上百季电视剧只触发一次订阅列表快照请求，不重新逐季调用 `/subscribe/media/{mediaid}`。

## 需要立即重新设计的信号

看到下面任一变化，不要只做小修：

- 后端或 Web 开始把 `tmdbid: 0`、`bangumiid: 0` 或 `tmdb:0` 当成有效媒体身份。
- 后端订阅快照不再返回 `mediaid` fallback，或 `mediaid` 格式不再是 `<source>:<id>`。
- Web 的 `getMediaId()` 不再使用当前 fallback 顺序，或开始优先使用不同字段作为订阅身份。
- 后端订阅唯一性加入 `episode_group`。
- 后端新增按 `episode_group` 查询或删除订阅的正式 API。
- `GET /subscribe/` 改成分页、筛选、按状态默认过滤或不再返回完整订阅。
- `DELETE /subscribe/media/tmdb:<id>` 未传 `season` 时不再删除全部季，或新增了明确的批量取消确认契约。
- `episode_group` 从字符串改成对象、数组或其他结构。
- Web 分季弹窗开始支持同一季多个剧集组订阅状态。
- Web 分季弹窗开始提供按剧集组取消订阅。
- Web 详情页顶部订阅按钮开始覆盖 TMDB 电视剧详情，或 Douban/Bangumi 详情页开始正式展示 TMDB 分季列表。
- 订阅修改在后端变成局部 patch，并且 `episode_group` 更新不再触发现有订阅刷新事件。
