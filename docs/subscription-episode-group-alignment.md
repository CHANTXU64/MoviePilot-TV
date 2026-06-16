# 分季订阅与剧集组对齐清单

本文档记录 TV 端分季订阅状态、取消订阅和 `episode_group` 的跨端对齐点。以后同步 MoviePilot 后端或 MoviePilot Web 前端时，优先检查本文件列出的契约是否仍成立；如果不成立，需要同步评估 TV 端实现和测试。

这不是完整兼容审查清单。常规接口、模型、图片、导航和 tvOS 行为仍要按正常流程检查；这里只列出分季订阅与剧集组相关的重点风险。

## 当前契约

- 同一媒体同一季只有一条订阅。
- `episode_group` 是订阅配置，不是订阅身份的一部分。
- 创建订阅时可以带 `episode_group`。
- 查询某媒体某季是否已订阅时，只按媒体和季判断，不按 `episode_group` 判断。
- 取消某媒体某季订阅时，后端媒体删除接口也是媒体和季语义，不按 `episode_group` 删除。
- TV 分季页展示的已订阅状态必须来自真实订阅记录上的 `episode_group`，不能来自当前 Picker 选择。
- TV 分季页取消已订阅季时，应优先按订阅 `id` 删除这条唯一订阅。

## 后端更新时重点检查

检查 `../MoviePilot` 中这些位置：

- `app/db/subscribe_oper.py`
  - `SubscribeOper.async_add` 是否仍用 `tmdbid` / `doubanid` + `season` 查重。
  - 如果查重条件新增 `episode_group`，说明后端开始支持同一媒体同一季多剧集组订阅，TV 分季状态模型需要重做。
- `app/db/models/subscribe.py`
  - `Subscribe.episode_group` 字段是否仍存在，类型和含义是否变化。
  - `Subscribe.async_exists` 是否仍不包含 `episode_group`。
  - `Subscribe.async_get_by_tmdbid` 是否仍按 `tmdbid + season` 返回订阅。
- `app/schemas/subscribe.py`
  - `Subscribe` schema 是否仍返回 `id`、`season`、`tmdbid`、`doubanid`、`bangumiid`、`episode_group`。
  - 如果字段改名、嵌套、分页或拆分，需要同步更新 TV 解码和快照缓存。
- `app/api/endpoints/subscribe.py`
  - `GET /subscribe/` 是否仍返回当前用户完整订阅列表。
  - `POST /subscribe/` 是否仍用 `episode_group` 创建或更新订阅配置。
  - `GET /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/media/{mediaid}` 是否新增了 `episode_group` 参数。
  - `DELETE /subscribe/{subscribe_id}` 是否仍按订阅 id 删除单条订阅。

如果后端开始支持“同一媒体同一季多个 `episode_group` 订阅”，不要只改 UI 文案。需要重新设计：

- 分季卡片是否显示多个订阅状态。
- 取消按钮取消哪一个剧集组。
- 当前 Picker 是否同时影响状态查询和取消。
- `/subscribe/` 快照如何索引为 `media + season + episode_group`。
- 首页、详情页、分季页和订阅编辑页如何同步这组状态。

## Web 前端更新时重点检查

检查 `../MoviePilot-Frontend` 中这些位置：

- `src/components/dialog/SubscribeSeasonDialog.vue`
  - 分季弹窗是否仍只把选择的 `seasons` 和 `episodeGroup` 用于创建订阅。
  - 是否新增了分季已订阅状态、取消订阅或按剧集组判断状态的 UI。
- 订阅卡片和详情页相关组件
  - 是否仍使用后端现有媒体级订阅状态。
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
- `MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift`
  - 分季订阅状态是否仍按 `media + season` 从 `/subscribe/` 快照映射。
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

完整验证仍按 `AGENTS.md` 执行依赖解析、Simulator build 和完整 test。涉及真实后端契约时，还应按 `docs/backend-compatibility-tests.md` 运行真实后端兼容测试。

重点保留或补充这些用例：

- 默认分组订阅第 1 季后，切到其他剧集组，第 1 季仍显示 `已订阅 · 默认剧集组`。
- 剧集组 A 订阅第 1 季后，切到默认或剧集组 B，第 1 季仍显示 `已订阅 · 剧集组 A`。
- 当前 Picker 的 `episode_group` 不参与已订阅身份判断。
- 已订阅卡片点击取消时，确认框显示真实剧名、季号和剧集组。
- 取消前如果订阅已被其他设备删除，本机刷新为未订阅，不继续发起错误取消。
- 几十或上百季电视剧只触发一次订阅列表快照请求，不重新逐季调用 `/subscribe/media/{mediaid}`。

## 需要立即重新设计的信号

看到下面任一变化，不要只做小修：

- 后端订阅唯一性加入 `episode_group`。
- 后端新增按 `episode_group` 查询或删除订阅的正式 API。
- `GET /subscribe/` 改成分页、筛选、按状态默认过滤或不再返回完整订阅。
- `episode_group` 从字符串改成对象、数组或其他结构。
- Web 分季弹窗开始支持同一季多个剧集组订阅状态。
- Web 分季弹窗开始提供按剧集组取消订阅。
- 订阅修改在后端变成局部 patch，并且 `episode_group` 更新不再触发现有订阅刷新事件。
