# 订阅兼容契约与更新检查清单

本文档只记录 MoviePilot 后端或配套 Web 前端发生变化时，可能让 TV 端现有订阅路径产生运行错误、状态误判或错误操作的跨端契约。通用 API、下载、资源搜索、客户端并发实现和测试组织由 `.agents/prompts/frontend-update.md`、`.agents/ReviewPlan.md` 与测试代码负责，不在这里重复。

当前 TV 端声明的最低兼容 MoviePilot 版本为 `v2.15.6`。每次更新必须以后端目标标签及其 `FRONTEND_VERSION` 指定的 Web 版本为准，重新核对实际调用链；本文记录的既有行为不是对未来版本的永久假设。

## 使用原则

- 只记录“上游什么字段、端点或业务语义发生变化，会影响 TV 哪条已使用路径”。单纯的 session epoch、请求乱序、缓存 namespace、SwiftUI 身份和测试矩阵属于客户端正确性，不作为上游契约条目。
- 本清单只汇总历次已经发现的订阅风险，不是兼容审查的完整范围。每次更新仍须完整审阅目标后端及其配套 Web 的版本跨度、提交和 Diff，再逐项映射到 TV 已使用路径；不得因为清单条目未命中就提前结束审查。
- Web 的实际请求与用户结果是 TV 对齐依据。若 Web 与后端本身共享同一问题，记录为上游风险并跟随官方变化，不在 TV 端发明差异化接口或兜底。
- 测试用于证明已适配契约，不用于定义契约。不能因为兼容测试能够构造畸形数据，就把所有畸形输入都升级成后端更新要求。
- 具体版本结论必须现场核对，不能把旧审查中使用的后端、Web `HEAD` 或更高版本行为写成当前兼容基线。

## 订阅权限与快照

- 重新核对登录响应中 `permissions.subscribe` 的字段、真假值和 Web 入口判断；TV 只同步配套 Web 实际采用的订阅权限规则。
- 核对 `GET /subscribe/` 是否仍向普通用户返回本人订阅、向超级用户返回其可管理范围内的订阅，以及无 owner 旧记录的可见范围。
- `/subscribe/` 仍是首页、详情页和分季页的共享状态来源。若后端改为分页、筛选、增量同步或默认排除某些状态，必须同步重做 TV 快照和刷新逻辑。
- 持久订阅记录的业务 `id` 必须能稳定、唯一地定位编辑、搜索、暂停、重置和删除目标。若后端改变 ID 类型、可空性或唯一性，必须先适配 TV 模型和动作入口；不要把“过滤异常记录”当成长期契约。
- 普通用户与超级用户的订阅归属、更新和删除范围以目标版本后端与配套 Web 为准。客户端入口隐藏不能替代后端当前实际授权，也不能据此要求 TV 单独修补上游授权设计。

## 媒体身份与季号

- 订阅记录用于列表操作时，配套 Web 当前按完整 `media_source + media_id` → truthy 的 `tmdbid` / `doubanid` / `bangumiid` / `anilistid` → 遗留 `mediaid` 生成媒体键；用于把订阅快照匹配到当前详情/分季媒体时，则按 `media_source + media_id` → 遗留 `mediaid` → raw 专用 ID 逐级比较。两条调用链不能混成一套顺序。
- `MediaInfo` 的身份必须按目标版本 Web 的 `getMediaId()` 和后端响应 schema 现场核对。没有证据时，不得声称上游 `MediaInfo` 一定返回或支持遗留 `mediaid`。
- raw 数值 ID 的 `0` 和空字符串按 Web 的 JavaScript truthy 语义视为缺失并继续回退；负数在 Web 中仍为 truthy，除非目标版本正式改变规则，TV 不得单独把负数归一化为 `nil`。
- 遗留 `mediaid` 是后端返回的不透明媒体键；即使形如 `tmdb:0`，客户端也不能擅自拆解或改写。
- 新增订阅的精简请求继续只发送目标版本 Web/后端接受的专用 ID、`mediaid`、季号、洗版模式和剧集组。若结构化身份字段正式进入创建契约，需同时修改 TV 请求、状态匹配和取消目标。
- 分季来源中的 `season_number` 只有明确非负整数才能建立季身份；真实 `0` 表示 S00，缺失、`null` 或负值不能折叠成 S00。上游若改变季号值域或无效条目处理方式，需要重新评估 TV 分季列表和订阅目标。

## 媒体类型与订阅入口

- 只有 Web 明确识别为电视剧的媒体进入分季订阅流程；不能用 `canDirectlySubscribe == false` 反推“必然是电视剧”。
- 电影是否直接订阅、合集是否只进入合集页、未知或插件类型是隐藏还是允许直接订阅，都以目标版本 Web 的实际入口和后端可接受 payload 为准。
- 电视剧分季入口不能依赖辅助 TMDB ID 才显示；剧集组加载可以继续只在主身份为 TMDB 且存在有效 TMDB ID 时执行。
- Web 若改变类型名称、类型集合或直接订阅/分季路由，必须同时复核详情 Header、媒体卡片、预加载和分季页面，不能只改按钮文案。

## 创建与编辑

- MoviePilot v2.15.3 起，新增订阅和存在性查重已按媒体身份、季号与 `episode_group` 区分；同一媒体同一季可以存在不同剧集组的订阅。创建请求必须保留所选剧集组。
- MoviePilot Web v2.15.6 仍按媒体与 `season` 汇总已订阅状态，媒体级查询和取消也没有传 `episode_group`；TV 跟随 Web 保持相同状态与操作范围，不擅自改成按剧集组取消。
- `best_version` / `best_version_full` 的省略值当前表示使用后端默认配置，显式 `0` 表示普通订阅或关闭洗版。目标版本若改变空值、默认值或数值语义，TV 创建 payload 必须同步。
- Web 快速新增当前发送精简配置；编辑当前先 GET 完整 `Subscribe`，再完整 PUT，并由后端裁剪不可写运行字段。每次 schema 更新都要逐字段对照 Web 请求体、后端公共可写/排除字段、TV `CodingKeys` 与最终编码，避免新可写字段在无关编辑后丢失，也不得盲目回传 owner、运行状态等不可写字段。
- `total_episode` 需要保留 `null`、`0`、正数三态及后端的人工集数语义。未修改保存不应把 `null` 变为 `0` 或意外切换人工模式；若后端默认值、更新逻辑或 Web 表单行为变化，TV 编码需同步。
- `save_path == nil` 当前表示自动目录；非空值是后端可直接消费的本地路径或带 storage 的远程 URI。编辑时保留既有合法值并允许清空；若目录接口、存储 URI 格式或后端允许范围变化，TV 选择器与请求值必须一起复核。
- 订阅写入、状态修改、搜索、重置、删除和 Fork 是否成功，必须按各端点在目标版本声明的响应 envelope 判断，不能只用 HTTP 2xx 推断。只有端点明确改为 `204` 或无正文成功时，TV 才接受空响应。

## 订阅匹配与取消

- 分季已订阅状态必须来自 `/subscribe/` 快照中的真实记录，并按目标 Web 的身份优先级匹配；较高优先级身份存在时，不相等后不能继续用辅助 ID 误匹配。
- TV 分季页展示的剧集组来自已订阅记录，不来自当前 Picker；Picker 只影响新建订阅 payload。
- 取消前的订阅查询响应如果仍返回 canonical 身份、专用 ID 和遗留 `mediaid`，必须核对它们各自是“确认状态”还是“删除键”。当前 Web 的删除键来自当前媒体的 `getMediaId()`；除非目标版本 Web/后端明确改变合同，lookup 只用于确认，不得让 TV 自行漂移成另一种删除目标。
- 当前 Web 使用 `DELETE /subscribe/media/{mediaid}` 并传 `season` 进行媒体级取消，不按 `episode_group` 删除；TV 保持相同请求形式。这与后端已按剧集组区分查重/存在性的行为并不对称。
- **已知上游风险（跟随 Web）**：媒体级删除会命中当前用户可管理范围内同媒体、同季的多条剧集组订阅。每次更新都要复核 Web 的确认信息、后端 owner/season 过滤和实际命中范围；官方若提供按剧集组或精确订阅 ID 删除、或返回命中范围，TV 再同步对齐，不单独发明不同语义。
- 若外部客户端已经删除或替换订阅，取消前的权威查询应决定是否继续。这里记录的是上游查询与删除契约，不把具体请求代际和按钮禁用实现写入本清单。

## 订阅分享与 Fork

- `GET /subscribe/shares` 返回的业务标识必须稳定且能定位 `POST /subscribe/fork` 的来源；若 ID 类型、字段名或唯一性变化，需同步 TV 列表身份和 Fork 请求。
- Share → Fork 当前需要保留后端 schema 中实际消费的 `tmdbid`、`doubanid`、`bangumiid`、`anilistid`、`media_source`、`media_id` 及订阅配置字段。字段新增、删除或改名时，按 Web 实际请求和后端消费逻辑更新 TV，不要求透传未声明的未知字段。
- Share 转为媒体展示时，主身份仍按 canonical 后再按专用 ID 的目标版本规则投影；辅助 ID 不能覆盖已声明的主身份。
- 确认页展示哪些配置属于产品交互，不作为后端更新契约；只有字段会影响用户确认后的实际写入且 Web 行为发生变化时，才评估 TV 是否跟进。

## 订阅缓存与刷新

- 普通读取可以复用短期快照；用户主动进入页面、保存、创建、删除、暂停/恢复、重置、手动搜索或 Fork 成功后，必须仍能获得权威订阅状态。
- 分季页从一次 `/subscribe/` 快照映射状态，不能退回逐季查询。若 Web/后端把快照改成分页、增量、事件推送或新的默认过滤，必须同步重审 TV 的读取和刷新入口。
- 具体 `forceRefresh`、请求代际、账号切换清理和预加载通知实现属于 TV 客户端正确性，留在代码、测试和 ReviewPlan，不在这里展开。

## 后端更新时重点检查

检查目标 `MoviePilot` 标签中与 TV 现有订阅调用链直接相关的位置：

- `app/db/subscribe_oper.py`、`app/db/models/subscribe.py`
  - 普通用户/超级用户的数据范围、媒体+季查重、`episode_group`、season 和 owner 条件是否变化。
- `app/schemas/subscribe.py`
  - `id`、媒体身份、season、`episode_group`、`total_episode`、`save_path`、洗版字段及其他公共可写字段的类型、可空性和默认值是否变化。
  - 公共写入排除字段是否仍保护后端运行事实；Web 使用的可编辑字段是否仍允许写入。
- `app/api/endpoints/subscribe.py`
  - `/subscribe/` 快照、创建/更新、媒体查询、媒体级/精确删除、状态、搜索、重置及 Fork 的参数、owner 范围和响应 envelope 是否变化。
  - `DELETE /subscribe/media/{mediaid}` 是否仍支持目标版本的各类身份，并统一应用 `season`；未传 season 时的范围是否变化。
- 订阅分享和目录/存储相关 schema、端点
  - Share → Fork 实际消费字段、业务 ID，以及 `save_path` 可用值是否变化。

只记录能进入 TV 现有调用链的变化。服务端是否应增加新的权限校验属于上游安全/产品审查，不在本清单中替 MoviePilot 设计。

## Web 前端更新时重点检查

检查后端目标版本绑定的 `MoviePilot-Frontend` 标签：

- 详情页、媒体卡片与分季弹窗
  - `getMediaId()` 的字段顺序和 `0`/空值规则、媒体类型路由、创建和取消请求是否变化。
- 订阅列表与编辑弹窗
  - GET → PUT 的字段、`total_episode` 人工语义、`save_path`、洗版默认值、成功响应判断和保存后的刷新方式是否变化。
- 订阅分享与 Fork
  - Share schema、Fork 请求体、身份字段和响应 ID 是否变化。
- 缓存与状态刷新
  - Web 是否改为分页、筛选、增量同步或事件驱动；操作后是否仍重新获取权威订阅状态。

Web 若只是共享后端缺陷或根本不会发起对应请求，应记录为上游行为，不给 TV 增加差异化兜底。

## TV 端映射位置

上游契约变化时，至少映射到这些现有位置：

- `MoviePilot-TV/Models/Models.swift`：`MediaIdentifier`、`MediaInfo`、`Subscribe`、`SubscribeRequest`、`SubscribeShare`。
- `MoviePilot-TV/Services/APIService.swift`：订阅快照、创建/更新、查询、取消、状态、搜索、重置、Fork 与缓存失效。
- `MoviePilot-TV/ViewModels/HomeViewModel.swift`、`MediaDetailViewModel.swift`、`SubscribeSeasonViewModel.swift`、`MediaPreloader.swift`：状态来源与刷新入口。
- `MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift` 及订阅编辑/Fork Sheet：用户入口与目标版本 Web 行为。

## 需要重新设计的上游信号

看到下面任一变化，不要只改字段名或补一个测试：

- `/subscribe/` 不再返回完整快照，改为分页、筛选、增量同步或事件流。
- Web 开始按 `episode_group` 展示订阅状态，或后端新增按剧集组查询/删除的正式 API。
- 媒体身份优先级、raw `0`/负数规则、遗留 `mediaid` 格式或创建请求身份字段发生变化。
- season 值域变化，或 S00 不再由数值 `0` 表示。
- Web 改变电影/电视剧/合集/插件类型的订阅入口模型。
- 编辑从完整 PUT 改为 PATCH，公共可写/排除字段变化，或 `total_episode`、`save_path`、洗版字段的空值/default 语义变化。
- 媒体级删除的 owner、season 或命中范围变化，或官方改为精确订阅 ID 删除。
- Share/Fork 的业务 ID、身份字段、请求体或成功响应结构变化。

## 验证与文档边界

- 修改订阅契约后，按 `AGENTS.md` 运行标准 tvOS Simulator 构建和完整测试；涉及真实后端时，按 `docs/backend-compatibility-tests.md` 执行相应只读或显式副作用套件。
- 只为实际变化的契约补聚焦回归测试。畸形数据矩阵、请求代际、会话切换和缓存竞态继续由对应单元测试与 ReviewPlan 管理，不在本清单逐项展开。
- 如果本次变化属于下载、资源搜索、SSE、通用权限或其他非订阅路径，更新 `.agents/prompts/frontend-update.md` 或相应专项文档，不继续扩张本文件。
