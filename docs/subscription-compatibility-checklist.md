# 订阅兼容契约与更新检查清单

本文档只记录 MoviePilot 后端或配套 Web 前端发生变化时，可能让 TV 端现有订阅路径产生运行错误、状态误判或错误操作的跨端契约。通用 API、下载、资源搜索和客户端并发/状态安全边界分别由 `.agents/prompts/frontend-update.md`、`.agents/engineering-invariants.md` 与测试代码负责，不在这里重复。

当前 TV 端最早维护 MoviePilot `v3.0.4`，兼容按精确版本登记，AI 对照官方源码确认 TV 实际用到的接口、字段和写回未受影响即可登记，规则见 [后端版本兼容维护](backend-version-compatibility.md)。每次更新必须以后端目标标签及其 `FRONTEND_VERSION` 指定的 Web 版本为准，重新核对实际调用链；本文记录的既有行为不是对未来版本的永久假设。

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

- MoviePilot v3.0.1 起，订阅与媒体详情的主身份是成对的 `media_source` + `media_id`。配套 Web 的 `getMediaSubscribeIdentity()` 只认这一对；`tmdbid` / `doubanid` / `bangumiid` / `anilistid` / `mediaid` 已从订阅 schema 删除，只作为 `MediaInfo` 的辅助输出。
- 媒体级查询和取消已改为 `GET|DELETE /subscribe/media/{media_id}?media_source=`，path 只放来源原生 ID，不再把 `tmdb:123` 整段放进 path。详情是 `GET /media/{media_id}?media_source=&type_name=`。
- `MediaInfo` JSON 的声明来源字段是 `media_source`；旧 `source` 仅作解码兼容。没有证据时，不得声称上游 `MediaInfo` 一定返回遗留 `mediaid` 或 `tmdbid` 作为主身份。
- raw 数值 ID 的 `0` 和空字符串按 Web 的 JavaScript truthy 语义视为缺失；`media_id=="0"` 在 v3 校验中非法。负数在 Web 中仍为 truthy，除非目标版本正式改变规则，TV 不得单独把负数归一化为 `nil`。
- 新增订阅的精简请求必须发送目标版本 Web 实际提交的 `media_source`、`media_id`、季号、洗版模式和剧集组。半对身份会被后端 422。
- MoviePilot v3.1.4 在 `RECOGNIZE_SOURCE` 为 TMDB 时，会尝试把非 TMDB 影视订阅转换为 TMDB 身份后创建；转换失败则保留原身份，未指定季号时可能采用转换结果中的正季号。不能假定创建请求的身份就是最终持久化身份。配套 Web 分季状态仍按原媒体身份精确匹配，因此转换后原来源页面可能不显示对应分季的订阅状态；这是当前 Web 共同限制，不在 TV 单端新增猜测匹配或扩大删除范围。后续若上游改变查询、分季匹配或取消目标，须一起复核。
- 分季来源中的 `season_number` 只有明确非负整数才能建立季身份；真实 `0` 表示 S00，缺失、`null` 或负值不能折叠成 S00。上游若改变季号值域或无效条目处理方式，需要重新评估 TV 分季列表和订阅目标。

## 媒体类型与订阅入口

- 只有 Web 明确识别为电视剧的媒体进入分季订阅流程；不能用 `canDirectlySubscribe == false` 反推“必然是电视剧”。
- 电影是否直接订阅、合集是否只进入合集页、未知或插件类型是隐藏还是允许直接订阅，都以目标版本 Web 的实际入口和后端可接受 payload 为准。
- 电视剧分季入口不能依赖辅助 TMDB ID 才显示；剧集组加载可以继续只在主身份为 TMDB 且存在有效 TMDB ID 时执行。
- Web 若改变类型名称、类型集合或直接订阅/分季路由，必须同时复核详情 Header、媒体卡片、预加载和分季页面，不能只改按钮文案。

## 创建与编辑

- MoviePilot v2.15.3 起，新增订阅和存在性查重已按媒体身份、季号与 `episode_group` 区分；同一媒体同一季可以存在不同剧集组的订阅。创建请求必须保留所选剧集组。
- MoviePilot Web v3.0.7 仍按媒体与 `season` 汇总已订阅状态，媒体级查询和取消传 `media_source`，仍没有传 `episode_group`；TV 跟随 Web 保持相同状态与操作范围，不擅自改成按剧集组取消。
- `best_version` / `best_version_full` 的省略值当前表示使用后端默认配置，显式 `0` 表示普通订阅或关闭洗版。目标版本若改变空值、默认值或数值语义，TV 创建 payload 必须同步。
- Web 快速新增当前发送精简配置；编辑当前先 GET 完整 `Subscribe`，再完整 PUT，并由后端裁剪不可写运行字段。订阅保存唯一走 `SubscriptionWriteDTO`：PUT 使用 `exclude_unset=True`，只更新请求里出现的键；编辑会话持有 original 与 draft，DTO 仅发送变化的可写字段；原样保存只发定位 ID，显式改为 nil 发 `null`，不依赖解码键或模型编辑标志。媒体身份变化时两个身份键一起提交。字符串原样发送，不 trim 正则、路径或识别词；下载器选“默认”时在编辑边界转换为 nil，发送 `downloader:null` 清除已有指定值，兼容较早登记版本会删去空字符串键的行为。只发用户可编辑字段（包括 `search_interval`、音质过滤等 GET 返回的值），不回写状态、计数、洗版运行优先级、owner 等后端维护字段。
- MoviePilot v3.1.1 将空字符串转为 `null` 的清空范围扩展到 `custom_words`、`keyword`、`save_path`、`episode_group`、`downloader` 和三个音质下限字段；原有筛选字段与搜索周期继续保留清空语义。配套 Web v3.1.2 的保存路径选择器清空时写回 `null`。TV 的差量 DTO 已按显式 `null` 清空，不需要改变编码；后续更新仍须核对省略与清空的区别。
- 类别（`media_category_id` + `media_category`）：有效稳定 ID 优先路径，ID 键为空会同时清空 ID 和路径。未编辑类别时省略两个类别字段，由后端保留原有稳定 ID；明确修改路径时省略旧 ID，只发新路径；清空类别时省略旧 ID，只发 `media_category:null`。仅路径写入由后端保存为兼容路径，不反向推断新的稳定 ID。历史订阅的 ID 为空或缺失时，修改路径仍只发送路径；详情只有稳定 ID 没有路径时，输入框显示为空；内容未改（含输入框确认时回写原文本）不得改动 ID，与 Web 一样保留原分类。每次 schema 更新都要逐字段对照 Web 请求体、后端公共可写/排除字段、TV `CodingKeys` 与最终编码，并从已有值验证原样保存、修改和清空的实际结果。
- `total_episode` 需要保留 `null`、`0`、正数三态及后端的人工集数语义。未修改保存不应把 `null` 变为 `0` 或意外切换人工模式；若后端默认值、更新逻辑或 Web 表单行为变化，TV 编码需同步。
- `save_path == nil` 当前表示自动目录；非空值是后端可直接消费的本地路径或带 storage 的远程 URI。编辑时保留既有合法值并允许清空；若目录接口、存储 URI 格式或后端允许范围变化，TV 选择器与请求值必须一起复核。
- 复用订阅（`/subscribe/fork`）只在 v3.0.1–v3.0.4 上事前禁止（上游响应声明缺陷，v3.0.5 修复）；版本读不出、无法识别或高于登记版本时照常允许。
- 订阅写入、状态修改、搜索、重置、删除和 Fork 是否成功，必须按各端点在目标版本声明的响应 envelope 判断，不能只用 HTTP 2xx 推断。只有端点明确改为 `204` 或无正文成功时，TV 才接受空响应。
- MoviePilot v3.0.1 配套 Web 对单条订阅搜索和重置使用 `POST /subscribe/search/{id}`、`POST /subscribe/reset/{id}`；后端仍保留 GET 作为废弃兼容入口。TV 跟随 Web 使用 POST。
- MoviePilot v3.1.1 至 v3.1.2-1 的暂停不撤销已接纳的搜索；v3.1.4 已改为在执行安全边界重读暂停状态，停止自动搜索和后续下载提交。显式手动或指定目标补搜仍可为暂停订阅搜索、下载，且不会仅因搜索恢复订阅。TV 继续分别调用搜索和状态接口，不能把暂停成功解释为同步撤销已提交的远端下载，也不能在手动补搜后自动恢复状态。
- MoviePilot v3.1.2-1 的影视补全搜索采用后端全局 `SubscribeSearchStrategy`（未设置时为 `smart`，另有 `full` 和 `single_page`；洗版固定全量），分页检查点保存在后端搜索任务中。TV 继续使用原搜索端点，成功响应表示任务已受理，不表示已翻完全部页面或已下载完成；不得把策略或检查点写入 `Subscribe` 编辑 DTO，暂停和刷新入口仍沿用上述合同。
- MoviePilot v3.1.4 将共享来源游标上限收紧为 20 页，并对自动订阅的普通 IMDb 精确查询增加持续不匹配早停；整季缺失保留完整收集屏障，让后页整季包参与择优。这些由后端管理，订阅搜索响应仍只表示受理；不要在 TV 写入页码预算或推断补全已完成。

## 订阅匹配与取消

- MoviePilot v3.0.4 起，`GET /subscribe/media/{media_id}` 在精确身份未命中时可以用 `title`、`year`、`mtype` 和可选 `season` 跨来源回退。v3.0.10-1 起，电影和电视剧不再排除 TMDB，也不再要求卡片必须带年份：先按规范标题、类型和季号取候选；卡片有年份时优先精确年份，其次匹配订阅年份为空的记录；卡片没有年份时只匹配年份也为空的订阅，不能串到已有明确年份的订阅。音乐仍只按精确身份查询。配套 Web 的状态检查和编辑定位会发送 `title`、`year`、`mtype`。TV 的读取与编辑入口必须发送相同元数据，避免把已有跨来源订阅误判为未订阅或重复创建。
- 上述元数据回退只属于 GET 查询合同。`DELETE /subscribe/media/{media_id}` 在 v3.0.7 仍按 `media_source`、原生 ID、可选 `season`/`music_type` 精确删除，而且没有命中时仍返回 `success:true`。因此媒体级删除目标不能直接复用一次跨来源 GET 的查询身份；应使用严格身份查询、已识别的真实 TMDB 身份，或明确的订阅业务 ID。
- 分季已订阅状态必须来自 `/subscribe/` 快照中的真实记录，并按目标 Web 的身份优先级匹配；较高优先级身份存在时，不相等后不能继续用辅助 ID 误匹配。
- TV 分季页展示的剧集组来自已订阅记录，不来自当前 Picker；Picker 只影响新建订阅 payload。
- 取消前的严格身份查询响应如果仍返回 canonical 身份、专用 ID 和遗留 `mediaid`，必须核对它们各自是“确认状态”还是“删除键”。当前 Web 的媒体级删除键来自当前媒体的 `getMediaId()`；TV 为避免 v3.0.4 跨来源 GET 回退产生空删除，只在严格身份查询或已识别的 TMDB 身份上使用媒体级删除，必要时按响应的订阅业务 ID 精确删除。
- 当前 Web 使用 `DELETE /subscribe/media/{media_id}?media_source=&season=` 进行媒体级取消，不按 `episode_group` 删除；TV 保持相同请求形式。这与后端已按剧集组区分查重/存在性的行为并不对称。
- `GET /subscribe/` 可能混入 `type=="音乐"`。音乐订阅不是 TV 现有影视路径的兼容必修项；TV 不得把音乐当电影直接订阅，也不得把音乐送进分季流程。传输历史则可能包含音乐项并进入既有整理入口：`from_history=true` 发送历史 `logid` 复用后端记录，`from_history=false` 按文件重新识别；本地回归覆盖两种模式，不新增音乐纠正 UI 或强制透传可选 `musicbrainz_release_id`。
- `DELETE /subscribe/{id}` 在目标不存在或无权限时改为 HTTP 404/403，不再返回 `success:true`。
- **已知上游风险（跟随 Web）**：媒体级删除会命中当前用户可管理范围内同媒体、同季的多条剧集组订阅。每次更新都要复核 Web 的确认信息、后端 owner/season 过滤和实际命中范围；官方若提供按剧集组或精确订阅 ID 删除、或返回命中范围，TV 再同步对齐，不单独发明不同语义。
- 若外部客户端已经删除或替换订阅，取消前的权威查询应决定是否继续。这里记录的是上游查询与删除契约，不把具体请求代际和按钮禁用实现写入本清单。

## 订阅分享与 Fork

- `GET /subscribe/shares` 返回的业务标识必须稳定且能定位 `POST /subscribe/fork` 的来源；若 ID 类型、字段名或唯一性变化，需同步 TV 列表身份和 Fork 请求。
- MoviePilot v3.0.5 将 `POST /subscribe/fork` 的 OpenAPI 响应模型修正为 `Response<IdData>`（上游提交 `2e2a037eb81d1b8f1fd1bcbf3bdf2c945429e776`），与端点一直返回新订阅 `data.id` 的实际行为一致。通用 `IdData` 为复用其他端点而声明成 `integer|string|null`，但 Fork 直接返回 `create_subscribe` 的整数 `sid`；TV 仍须同时验证显式 `success:true` 和正整数 ID，并将这项声明宽化保留为带证据的契约例外，不放宽现有 Fork 解码。
- Share → Fork 当前需要保留后端 schema 中实际消费的 `media_source`、`media_id` 及订阅配置字段。v3 已删除分享对象上的 `tmdbid`/`doubanid`/`bangumiid`/`anilistid`，并新增 `music_type`、`total_tracks`、音质过滤字段和 `media_category_id`。Fork 按 Web 把 GET 到的分享对象原样 POST；TV 必须解码并回传这些可写字段，不能在 Codable 往返中丢掉。字段再新增、删除或改名时，按 Web 实际请求和后端消费逻辑更新 TV，不要求透传未声明的未知字段。
- Share 转为媒体展示时，主身份仍按 canonical 后再按专用 ID 的目标版本规则投影；辅助 ID 不能覆盖已声明的主身份。
- 确认页展示哪些配置属于产品交互，不作为后端更新契约；只有字段会影响用户确认后的实际写入且 Web 行为发生变化时，才评估 TV 是否跟进。

## 订阅缓存与刷新

- 普通读取可以复用短期快照；用户主动进入页面、保存、创建、删除、暂停/恢复、重置、手动搜索或 Fork 成功后，必须仍能获得权威订阅状态。
- 分季页从一次 `/subscribe/` 快照映射状态，不能退回逐季查询。若 Web/后端把快照改成分页、增量、事件推送或新的默认过滤，必须同步重审 TV 的读取和刷新入口。
- 具体 `forceRefresh`、请求代际、账号切换清理和预加载通知实现属于 TV 客户端正确性，由代码、测试和 `.agents/engineering-invariants.md` 维护，不在这里展开。

## 后端更新时重点检查

检查目标 `MoviePilot` 标签中与 TV 现有订阅调用链直接相关的位置：

- `app/db/subscribe_oper.py`、`app/db/models/subscribe.py`
  - 普通用户/超级用户的数据范围、媒体+季查重、`episode_group`、season 和 owner 条件是否变化。
- `app/schemas/subscribe.py`
  - `id`、媒体身份、season、`episode_group`、`total_episode`、`save_path`、洗版字段及其他公共可写字段的类型、可空性和默认值是否变化。
  - 公共写入排除字段是否仍保护后端运行事实；Web 使用的可编辑字段是否仍允许写入。
- `app/api/endpoints/subscribe.py`
  - `/subscribe/` 快照、创建/更新、媒体查询、媒体级/精确删除、状态、搜索、重置及 Fork 的参数、owner 范围和响应 envelope 是否变化。`GET /subscribe/` 在省略 `page`/`count` 时仍应返回完整快照。
  - `PUT /subscribe/` 是否仍用 `exclude_unset=True` 裁剪公共写入字段；`SubscriptionWriteDTO` 按原始值与草稿差异提交（含 `search_interval`、音质过滤等）；`media_category_id` 与路径的优先级、空编号清空行为是否变化。
  - `GET|DELETE /subscribe/media/{media_id}?media_source=` 是否仍支持目标版本的各类身份，并统一应用 `season`；未传 season 时的范围是否变化。
  - GET 的影视元数据回退是否仍覆盖电影和电视剧的全部来源（含 TMDB），是否仍在精确身份未命中且有规范标题时回退，并按“精确年份优先、空年份次之；卡片无年份只匹配空年份”选择；音乐是否仍不回退。DELETE 是否仍不采用该回退。
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
- 只为实际变化的契约补聚焦回归测试。畸形数据矩阵、请求代际、会话切换和缓存竞态继续由对应单元测试与 `.agents/engineering-invariants.md` 管理，不在本清单逐项展开。
- 如果本次变化属于下载、资源搜索、SSE、通用权限或其他非订阅路径，更新 `.agents/prompts/frontend-update.md` 或相应专项文档，不继续扩张本文件。
