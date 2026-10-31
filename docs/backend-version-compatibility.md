# MoviePilot 后端版本兼容维护

## 规则

- 兼容按**精确版本**登记，登记表是 `MoviePilot-TV/Models/BackendCompatibility.swift` 中的 `BackendCompatibilityRegistry.current`。
- 登记标准：对照官方源码（后端标签及其 `version.py` 指定的配套 Web 版本），确认 TV 实际调用的接口、返回字段、权限和订阅写回没有受影响，即可登记。**不要求真实后端实测**；真实后端兼容测试（`docs/backend-compatibility-tests.md`）只是可选的补充手段。
- 未登记的版本不推断为兼容。App 只在后端版本低于最早登记版本、落在登记版本之间但未登记、高于最新登记版本或读不出版本号时提示；用户确认后，同一服务器的同一后端版本不再提示，新增登记也不会让已确认的版本重新弹窗。
- 提示不展开完整登记表。中间未登记版本的标题为“兼容性尚未验证”，正文用“已兼容的版本：X...Y”简写比当前版本高的最近已验证版本和最新已验证版本，两者相同时只显示一次。较新或无法识别的版本用同样格式简写最早与最新登记版本；省略号不表示中间所有版本均已验证。提示正文不再附加“仍可继续使用”。
- 版本号只识别官方稳定版本：三段数字加可选的正整数热修复后缀，例如 `v3.0.10 < v3.0.10-1 < v3.1.0`。beta 等其他后缀按“无法识别”处理。
- 已知缺陷的功能、版本范围与文案集中在 `BackendCapabilities.knownDefects`，入口和操作 Handler 统一通过 `capability(for:backendVersion:)` 判断。已知不可用版本在入口置灰并显示原因；未知版本放行，点击复用不额外刷新全局配置。
- 旧的“后端版本|最低版本”确认记录在读取时迁移为版本 ID，升级 App 不会重复提示已经确认的同一版本。
- 不按版本复制接口或模型。只有某个功能在确定的版本范围内有已证实的上游缺陷时，才按版本阻止该功能，规则见 `.agents/engineering-invariants.md` 的“已知缺陷版本门禁”。新增取值或新能力的可用性门禁（如新整理方式 `reflink`）按 `>= 目标版本` 在入口显隐，读不出或低于目标版本时不展示，可解析且 `>=` 目标版本（含热修复和尚未登记的更新版本）仍展示；这类门禁不做接口复制，也不适用缺陷门禁的“未知放行”。只在某个版本起才成立的新功能、新入口或提示，按同一文档的“新行为版本限制”处理：已解析的更低版本不得走这条新行为。破坏性副作用确认在版本缺失或无法解析时仍提示。

## 已登记版本

| 后端标签 | 官方提交 | 配套 Web | 说明 |
| --- | --- | --- | --- |
| v3.0.4 | e195cc164fc8ff869ffee0ea44a49c7ec475310c | v3.0.4 | 复用订阅接口有上游缺陷（v3.0.1–v3.0.4：订阅已创建，但响应校验失败），TV 在这些版本上禁止复用订阅 |
| v3.0.5 | ce3489ae75ff06119f076550f72df57e6f92a6bf | v3.0.5 | 上游修复复用订阅（提交 2e2a037） |
| v3.0.7 | e2e6ff0dc467fe13ceb9dba8e32573edbf352d86 | v3.0.7 | 新增 GitHub 授权，调整插件文件、设置脱敏和订阅刷新的季号回落；TV 调用的接口和返回格式不变 |
| v3.0.10 | 82eeef1681801da98e433bf3c0a9bf04147b8564 | v3.0.10 | 调整刮削剧集组、图片代理信任主机、网络测试、音乐整理判定和插件；TV 调用的接口和返回格式不变 |
| v3.0.10-1 | 0aa857173f77de31c7c8d9d2e12052d99f37bcc1 | v3.0.10 | 订阅查询的跨来源回退扩展到 TMDB 和无年份影视；TV 一直按 Web 附带标题和年份，请求不需改动 |
| v3.1.0 | 0a7368bce8d28f60ee795b38da0ac7a844c7e085 | v3.1.0 | 整理预览新增来源存储字段，TV 按存储区分路径相同的预览项；旧版本响应仍能解码 |
| v3.1.1 | 6ff7dd86a14c403b0e408f778aa3174e13e15ef1 | v3.1.2 | 修复订阅可选设置清空及暂停项已接纳搜索，公开存储与站点响应脱敏，增加种子链接续签和图片重试；TV 已有写回与读取可继续沿用 |
| v3.1.2 | d208e7b38a94f58ccfd4c88c4f134916da9a24b2 | v3.1.2 | 与 v3.1.2-1 的公开 API 和模型一致；TV 保留旧流式资源搜索，订阅、下载和整理沿用现有合同 |
| v3.1.2-1 | 161fabbf831135c6f5fb14fa9d4900bd0740eb6b | v3.1.2 | 新增订阅逐页补全与断点恢复、可选手动资源分页及目录别名，修复分页并发和 Jellyfin 合集查询；TV 原搜索模式、订阅操作和路径写入继续兼容 |
| v3.1.4 | 09f62ff87e196df9e39a6422f23c23860610d96a | v3.1.4 | 新增登录限流，调整订阅身份转换、暂停与补全搜索，修复下载凭据、空白目录及站点冷却；TV 现有接口继续沿用，跨来源订阅状态保留下述 Web 共同限制 |
| v3.1.6 | dd4d83a00933d21772709212dc24d1b80f0e48ad | v3.1.6 | 订阅进度与首次整包下载由后端调整，并新增活动与执行日志；TV 现有接口继续沿用，不登记 v3.1.5。官方标签后来从 `bc1cae80` 改到当前提交，差异只有插件市场快照和 Telegram 通知排版 |
| v3.1.7 | 1f7bddc8372d7ff63d10122efb2b0873b2bfd499 | v3.1.7 | 下载任务查询与启停改为要求管理权限，与 TV 现有入口一致；豆瓣短评影评、勋章和站点冷却不进入 TV 调用 |
| v3.1.8 | 015df3826503329f3b185847bd8a3e0b13c8559f | v3.1.8 | 修复热门订阅年份整数导致的 500，媒体服务器新增调用方可控查询投影；TV 现有接口继续沿用，整理 AI 接管与 reflink 见 v3.1.9 |
| v3.1.9 | 811503b709f6207ee12ce17fd3a1a113effee723 | v3.1.9 | 订阅分类写回修正（保留自定义文本分类）、整理 AI 接管与 replan、reflink 整理方式和订阅批次下载来源统计；TV 现有接口与写回继续兼容，整理面板按后端版本追加 reflink 选项，历史标签已识别。此前误记的 `50cfcbe` 是同一父提交上的另一份插件市场快照，不在标签历史上；当前标签相对它多了音乐双语艺名与标题别名匹配，插件市场快照也不同，TV 无对应入口 |
| v3.2.0 | 94b0681cfc62d2e6b6577594f9ad6ae1e6aa5478 | v3.2.0 | 订阅新增身份唯一约束（目标身份已被占用时拒绝修改并回滚、修改身份字段重置订阅进度、迁移不删除历史重复记录）、整理链路按文件大小与修改时间校验并转人工复核、下载与媒体服务器内部加固、新增小组件与 App Push；TV 现有接口、写回和成功响应继续兼容，无新增 TV 入口 |
| v3.2.1 | daa9212ba161d4573baf3744e2f13b99c2a90516 | v3.2.2 | 新增媒体状态批量查询与订阅日历窗口端点、插件文档入口和种子缓存分页，订阅与搜索性能调整，安全与存储内部加固；TV 已调用接口的参数、返回结构和写回均未变，新端点 TV 暂不调用（见下节） |
| v3.2.2 | c609abc782978eb81efe1da1dcf259bd3ff6e635 | v3.2.2 | 自动发现整理跳过已有持久任务、重放与旧整理结果兼容、站点重定向失败不再中止请求、插件 Release 镜像下载、Agent 执行账号与命令回执、AppPush 全量投递及依赖安全升级；标签于 2026-10-31 重指后追加订阅严格身份匹配、共享站点流控与频控错误、整理缺元数据安全结算、API 权限收紧与存储绑定校验、AppPush 正文/海报保留、插件市场默认列表刷新，Web 同步追加 7 个提交（含字幕筛选“中字/特效”）；TV 已调用接口的参数、返回结构和写回均未变，无新增 TV 入口（见下节） |

订阅数据结构（`app/schemas/subscribe.py`）在 v3.0.4 到 v3.1.0 之间一致。保存订阅的写回规则写在 `SubscriptionWriteDTO.swift` 的注释和 `docs/subscription-compatibility-checklist.md` 中。

v3.1.1 未新增订阅字段，扩展了可选设置空字符串的显式清空语义；TV 继续省略未修改字段，并以 `null` 明确清空。其配套 Web v3.1.2 增加手动资源搜索续页入口，但目标后端尚未返回该入口依赖的 `sources` 页状态，TV 继续使用原有搜索合同。

v3.1.2 与 v3.1.2-1 均精确登记为兼容，配套 Web 均为 v3.1.2。TV 在 v3.1.2 继续使用原流式搜索及 HTTP 回退；手动分页从 v3.1.2-1 起启用，每次继续搜索只加载下一页，音乐媒体搜索仍走旧协议。两版本之间的改动涉及手动搜索并发与预览、无服务端页码的站点结果切片、整理完成事件、Agent 依赖注入和 Telegram 日志，公开 API 与模型没有变化，不需要额外的 TV 接口适配。订阅补全策略和检查点由后端管理，不进入 TV 的订阅写回；下载仍可传已有路径或存储 URI。

### v3.1.4 核对范围与边界

对照官方后端 [v3.1.2-1 → v3.1.4](https://github.com/jxxghp/MoviePilot/compare/v3.1.2-1...v3.1.4) 及各标签 `version.py` 指定的 Web [v3.1.2 → v3.1.4](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.2...v3.1.4)。Web 基准提交为 `f3699b154df93a52445a5ef6130535bcf57f22cf`，目标提交为 `23220e062d6d23c08b8be63271ffac3f6a06a085`。本次只新增目标精确版本 v3.1.4，不推断 v3.1.3 或未登记热修复版本兼容。

- **认证**：连续密码登录失败新增 `429` 和 `Retry-After`，异常包装仍为 `success:false`、本地化 `message`、`data:null`。TV 现有处理会显示错误、保留会话与保存的凭据，自动续期沿用已有退避；没有新增按 `Retry-After` 倒计时的 UI。明确密码拒绝、MFA、`/user/current` 失效信号和权限字段未变，MFA 仍仅提示不支持。CORS 调整不改变原生客户端的认证请求。
- **订阅**：schema、公共可写字段、分享/Fork、完整列表、查询和删除范围未变。识别源配置为 TMDB 时，后端会尝试将豆瓣、Bangumi 等非 TMDB 影视订阅转换为 TMDB 身份；失败时沿用原身份。暂停会在安全边界停止自动搜索和后续下载提交，显式手动补搜仍可执行且不恢复订阅。TV 继续按订阅业务 ID 操作并强制刷新，不自行改写身份或运行状态。
- **上游共同限制**：配套 Web 的详情和卡片分季状态仍用当前媒体的 `media_source + media_id` 精确匹配 `/subscribe/`。身份转换后，从原来源页面进入时可能看不到对应分季的已订阅状态；媒体级查询的标题/年份回退也没有扩展为删除合同。TV 保留现有匹配与严格取消目标规则，不新增跨来源猜测。可从订阅列表按记录管理转换后的订阅；此登记不表示该上游限制已修复。
- **搜索与下载**：共享搜索游标上限从每来源 100 页收紧为 20 页，自动订阅的普通 IMDb 精确搜索可对持续不匹配的来源提前停止；整季缺失仍完整收集后参与择优。手动分页 API、SSE 终态及 `can_continue` 合同未变，TV 不自行判断服务端是否搜尽。Milkie 适配输出现有资源结构；下载补齐同源站点凭据、空白保存路径采用默认目录、限流冷却均由后端执行，下载列表身份和删除文件参数未变。
- **图片、媒体与整理**：Bangumi 日历封面改为 HTTPS，媒体类型额外接受英文别名，原中文值仍有效；图片代理及媒体服务器返回结构未变。未处理的整理执行异常转入既有人工复核状态，手动整理、预览和历史请求格式未变；TV 不新增后台复核管理入口。
- **可选 Web 功能**：订阅来源徽标、文件详情与排序、下载卡片和整理历史布局不属于运行兼容必修项；助手形象、歌词简化、插件及工作流管理也不进入本次 TV 适配。后续功能候选文件保持不变。

### v3.1.6 核对范围与边界

对照官方后端 [v3.1.4 → v3.1.6](https://github.com/jxxghp/MoviePilot/compare/v3.1.4...v3.1.6) 及各标签 `version.py` 指定的 Web [v3.1.4 → v3.1.6](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.4...v3.1.6)。Web 基准提交为 `71171ff2a5173cf6d188f747560a18a13d30f7e0`，目标提交为 `1190bb880ad49734c97364db4bdd381d98f7bfd7`。此前登记记录的 Web 提交 `23220e06` 是官方 v3.1.4 标签的父提交，中间只多了发布历史展示；本次审查已覆盖这段差异。只新增目标精确版本 v3.1.6，不推断 v3.1.5 或未登记热修复版本兼容。

- **认证**：`POST /login/access-token` 与 `/user/current` 未改。明确密码拒绝、MFA、token 失效和权限字段保持 v3.1.4 的信号；新增文案只用于订阅活动与日志的 404。MFA 仍仅提示不支持。
- **订阅**：`Subscribe` 公共字段、写回排除、分享/Fork、完整列表、媒体查询、删除、搜索和重置的请求与成功响应未变。检查已有媒体时，电视剧部分入库也会写回进度。尚无已有剧集的普通电视剧首次下载先尝试完整包，失败后再按集；站点流控按限流窗口退避。这些都在后端任务内完成，搜索响应仍只表示受理。新增的活动分页和执行日志不进入 TV 调用。
- **搜索、下载与整理**：手动资源搜索的 SSE、分页参数和 `can_continue` 未变。下载列表身份、删除文件参数和手动整理请求未变。电影整理历史在目标路径未知时不再当作全部版本，只影响 webhook 删除定位。成功通知聚合、音乐封面和本地封面开关不改变 TV 的历史列表或整理请求。
- **识别与图片**：名称识别失败时仍返回空的 `media_info`，并额外带上解析元数据。TV 只读取 `media_info`，成功判断与配套 Web 一致。非 TMDB 且识别源也不是 TMDB 时，后端不再用 TMDB 补图；Bangumi 等来源在已有 TMDB 辅助信息时补齐缺失的语言和国家。图片代理路径未变，TV 继续使用后端返回的图片地址。
- **媒体库与其他**：跨来源入库匹配要求标题和年份唯一对应。Jellyfin 变更限于 webhook 路径缓存。插件 ID 额外允许下划线。系统更新新增合并下载与一次重启，社区勋章和 LLM API Route 不进入 TV。`API_DOCS_ENABLE` 默认仍关闭。兼容测试要求文档端点可用，JSON 404 记为失败，不再跳过。

### v3.1.7 核对范围与边界

对照官方后端 [v3.1.6 → v3.1.7](https://github.com/jxxghp/MoviePilot/compare/v3.1.6...v3.1.7) 及各标签 `version.py` 指定的 Web [v3.1.6 → v3.1.7](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.6...v3.1.7)。Web 基准提交为 `1190bb880ad49734c97364db4bdd381d98f7bfd7`，目标提交为 `809631cd707ef34190df90efa83285d2dac96691`。只新增目标精确版本 v3.1.7，不推断未登记热修复版本兼容。

- **认证**：`POST /login/access-token` 的 401 文案、`X-MFA-Required` 和 `/user/current` 的失效路径未改。令牌缺少主体时按认证失败处理，正常登录令牌不受影响。MFA 仍仅提示不支持。英文文案只新增订阅分享参数不完整，不进入登录匹配表。
- **订阅**：`Subscribe` 公共字段、默认值、写回排除、分享/Fork、完整列表、媒体查询、删除、搜索和重置的请求与成功响应未变。洗版电视剧的新集改用普通过滤规则，发生在后端搜索任务内；`POST /subscribe/search/{id}` 仍只表示受理。分享参数不完整时返回 `success:false`，TV 不调用该分享写入。配套 Web 的订阅列表不再让洗版状态盖住暂停、待定和进度，TV 本来就按记录状态操作，不复制这套列表筛选。
- **热门订阅**：v3.1.7 的 `GET /subscribe/popular` 把共享统计里的 `year` 转成整数后写入 `MediaInfo.to_dict()`，响应模型 `year` 仍是可选字符串。FastAPI 校验失败，异常被收成 `500`、消息为「未知错误」。电影和电视剧、带或不带 `sort_type` 都会这样。配套 Web 的热门订阅页调用同一接口。这是后端缺陷，TV 不做单独转换。该缺陷已在 v3.1.8 的 `4f98486e` 中修复，从登记 v3.1.8 起不再出现。
- **下载**：`GET /download/`、开始、暂停和删除改为要求 `permissions.manage` 或超级用户。TV 这些入口已经只对管理权限开放。添加下载、字幕下载、下载器列表和保存路径仍是已登录用户。任务字段、状态默认值和删除参数未变。Transmission 排队状态只影响下载器内部过滤。
- **搜索、图片与媒体库**：手动资源搜索和字幕搜索的 SSE、分页参数与 `can_continue` 未变。站点长冷却在本轮达到 3 次、单次至少 10 分钟后跳过该来源，由后端执行。Emby 主图 URL 在有封面标签时追加 `tag` 查询参数；TV 继续使用返回的地址，并用与 `encodeURIComponent` 等价的编码交给图片代理。Plex 继续观看不再为缺字段逐条拉详情，响应结构未变。媒体识别、季信息和图片代理路径未变。
- **可选 Web 功能**：媒体详情在有豆瓣 ID 时展示短评和影评，接口为 `GET /douban/interests/{id}/{type}` 与 `GET /douban/reviews/{id}/{type}`。社区勋章增加后台刷新标记。这些不进入 TV 调用。`API_DOCS_ENABLE` 默认仍为关闭。兼容测试要求文档端点可用，JSON 404 记为失败，不再跳过。

### v3.1.8 核对范围与边界

对照官方后端 [v3.1.7 → v3.1.8](https://github.com/jxxghp/MoviePilot/compare/v3.1.7...v3.1.8) 及各标签 `version.py` 指定的 Web [v3.1.7 → v3.1.8](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.7...v3.1.8)。Web 基准提交为 `809631cd707ef34190df90efa83285d2dac96691`，目标提交为 `8a97f5c0a02d64a216dd7d04f7ca9b836c45cadf`。只新增目标精确版本 v3.1.8，不推断未登记热修复版本兼容。

- **订阅与热门订阅**：`GET /subscribe/popular` 把共享统计的 `year` 还原为字符串（`4f98486e`），v3.1.7 记录的 500 缺陷不再出现；Transmission 选集回退的同批修复只影响下载器内部。订阅 schema、公共可写字段、分享/Fork、搜索和重置的请求与响应未变。
- **媒体服务器**：新增调用方可控的查询投影（`MediaServerField`、`MediaServerQueryOptions`，`bf4ef421`），由调用方按内容组裁剪远端字段；`MediaServerPlayItem` 与 `/mediaserver/exists` 的 `data.item` 字段未变。`/latest|/playing|/library` 的失败仍是 502 并带明确文案（v3.1.5 起即如此），TV 按通用非 2xx 展示。未声明支持投影的插件媒体服务器会被降级回全字段查询。
- **其他**：文件管理器跳过本地列目录期间消失的子项、音乐歌词侧车 umask、自动整理同步本地封面、Agent 图资源归属集中管理。TV 不调用文件管理器和音乐整理入口，现有接口与返回格式未变。

### v3.1.9 核对范围与边界

对照官方后端 [v3.1.8 → v3.1.9](https://github.com/jxxghp/MoviePilot/compare/v3.1.8...v3.1.9) 及各标签 `version.py` 指定的 Web [v3.1.8 → v3.1.9](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.8...v3.1.9)。Web 基准提交为 `8a97f5c0a02d64a216dd7d04f7ca9b836c45cadf`，目标提交为 `795c975850289ac2e0146b18c05cf63541cb352a`。只新增目标精确版本 v3.1.9，不推断未登记热修复版本兼容。

- **订阅**：`0a429cd8` 把 `media_category` 和 `media_category_id` 加入可清空可选字段，并把“文本分类表单带回空稳定 ID、同时提交非空路径”按旧路径输入处理，避免分类规范化误判为清空。TV 的 `SubscriptionWriteDTO.encodeCategory` 在分类路径变化时只发送 `media_category` 并省略旧 `media_category_id`，路径未变时才按 ID 变化单独发送，不会出现“空 ID + 非空路径”组合，因此不触发该分支。TV 调用的订阅 schema、写回、分享/Fork、搜索和重置未变；`SubscriptionBatchStatus` 新增的 `downloads`/`download_counts` 只出现在 TV 不调用的批次与活动接口。共享 `Context` 增加可选 `subscription_download`（提交类型、全集洗版、新增和升级集数；非订阅下载为空）。Web 只在订阅活动/执行对话框里显示下载类型。TV 搜索和识别仍只解码 `media_info`、`torrent_info`、`meta_info`，不展示该字段；OpenAPI 基线已登记。
- **搜索与媒体**：SSE 事件字段、分页参数与 `can_continue` 未变；`9d534d19` 让完整包优先于初始分片返回，结果顺序由后端决定；`453a9568` 让声明的 TMDB 请求超时真正生效；字幕签名在“有 enclosure 但站点 ID 非整数”时直接报错，正常结果的站点 ID 必为整数；`4df028d4` 修正副标题中被否定的季集号识别。媒体识别与刮削字段未变。
- **媒体服务器**：`04e7cebb` 在 Emby 投影中请求生产年份；查询投影仍是新增可选能力，`MediaServerPlayItem` 与 `NotExistMediaInfo` 字段未变，`/mediaserver/exists` 无结果仍返回 `{}`，`/mediaserver/latest` 的卡片字段裁剪不影响 TV 已有键。
- **整理与下载**：`17a866f4` 恢复失败整理的 AI 接管；`/history/transfer/{id}/ai-redo` 在已有接管时返回 `success:false` 和原因，TV 按 success/message 展示；后端新增 `POST /history/transfer/{history_id}/replan`（保留原任务与证据、只允许无文件副作用的识别失败重规划），TV 不调用；`POST /history/transfer/{history_id}/cleanup-resolved` 在 v3.1.7 已存在，同样不调用。整理方式新增 `reflink`（`114c2ceb`、`8b5e5364`、`e3d32e49`），后端 `transfer_type` 仍是自由字符串；TV 按 `>= v3.1.9` 的版本门禁在整理面板追加“引用链接”（版本读不出或低于 v3.1.9 时不展示，避免旧后端预览通过、提交执行时才报“不支持的整理方式”），历史模式标签的 `reflink` 显示不做门禁。`4bf11c32` 在选集前后确认 Transmission 状态、`d57af797` 对零新增交付的重复种子退避，均在后台执行。
- **站点、图片与系统**：`842320a2`、`ec7e4acf`、`2c0f1ac9` 保留 MTorrent 角色名和可空分享率、按站点协议路由连通性检查，返回结构未变；`38d7ca3f` 图片跳转校验沿用已配置的非公网放行网段，局域网 Emby 图片更易成功；`ec922865` 系统更新要求镜像系统基线 `MIN_SYSTEM_BASELINE='2026-01-01'`，只影响 `/system/update*`，TV 无更新入口；`85af231b` 部署 secrets 只在部署层；`c85f9b26`、`75ee313f`、`14b9ea6d` 属 Agent/LLM 内部。
- **暂不跟进**：订阅活动/执行日志、整理人工复核队列页、插件版本历史、站点统计弹窗、四个刮削设置开关、音乐双语艺名与标题别名匹配（`5fc4f2ef`）、依赖/CI/发布流程，TV 均无对应入口或端点调用。

### v3.2.0 核对范围与边界

对照官方后端 [v3.1.9 → v3.2.0](https://github.com/jxxghp/MoviePilot/compare/v3.1.9...v3.2.0) 及各标签 `version.py` 指定的 Web [v3.1.9 → v3.2.0](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.1.9...v3.2.0)。Web 基准提交为 `795c975850289ac2e0146b18c05cf63541cb352a`，目标提交为 `32d881f0f863c309f3b99ad6866e3d5eb2bca689`。只新增目标精确版本 v3.2.0，不推断未登记热修复版本兼容。

- **订阅**：`951cdc5` 为 `subscribe` 新增派生的 `identity_key`（唯一索引 `uq_subscribe_identity_key`，迁移 `c9e2f6a04173_subscription_identity`；历史重复记录保留，键为 NULL，不删除数据）。目标身份已被占用时，`PUT /subscribe/` 返回 HTTP 200、`success:false` 和「目标媒体身份已有订阅，当前修改已取消」，事务回滚，不会部分写入；TV 编辑 Sheet 已按 `success`/`message` 展示，冲突仍由后端判定、不新增客户端预判。身份由 `type`、`media_source`+`media_id`、`season`、`episode_group`、`music_type` 组成，修改任一身份字段会重置订阅进度；这是 v3.2.0 起的副作用。TV 在编辑已有订阅且这些字段发生变化时，仅当后端版本可解析且 `>= v3.2.0`（含热修复和尚未登记的更新版本），或版本缺失、无法解析时，保存前才二次确认「进度与搜索状态将被清空」，确认后才提交。已解析且低于 v3.2.0 时直接保存。新建订阅不弹。`GET /subscribe/media/{media_id}` 仍未按 `episode_group` 过滤，与配套 Web 保持同一查询和删除范围。订阅公开 schema、公共可写字段、分享/Fork、搜索和重置未变。
- **搜索与媒体**：`bcbf79f` 让音乐媒体搜索按 `page*count` 作为上限、`/media/scrape` 返回 `success`/`message`、推荐结果按 `media_type` 过滤（过滤在 Agent 推荐路径，`/recommend/source` 只返回来源描述，TV 不调用被过滤的接口）；`tmdbapi._project_search_results` 不再按本地化标题二次过滤。TV 的资源搜索、媒体搜索和推荐来源请求未变。
- **下载与字幕**：`598d166` 的 `/download/subtitle` 只在站点与字幕 URL 同源时下发 `site_cookie`；qBittorrent 5.3、rTorrent/Transmission 修复和 `/download/` 列表、启停、删除参数未变。下载链的严格来源模式只供小组件使用，TV 普通列表行为不变。
- **整理与转移**：`transhandler.__assert_file_identity` 对本地存储要求大小和优先纳秒级的修改时间证据，缺少证据抛 `StorageQueryError`（转人工复核），证据不一致抛 `TransferExecutionConflictError`；TV 手动整理和历史重做经 `logid` 读取后端快照，v3.1.9 的本地适配器已写 `modify_time`。冲突或人工复核最终返回 `success:false` 和「整理任务已转入人工复核，请打开整理队列查看详情」，不是 500，TV 按 success/message 展示。`POST /transfer/tasks/{task_id}/manual-review/discard` 和既有复核端点 TV 不调用；批量还原补 `episode_group`、dashboard 采样重构不改变 TV 读取的响应结构。
- **媒体服务器与其他**：`last_played_date` 改用 `datetime.fromisoformat`、Emby 展开 `IndexNumber..IndexNumberEnd`、Plex 空摘要保护、缓存按 `server_identity` 隔离、`/mediaserver/notexists` 合并多服务器已确认剧集；TV 读取的字段未变，结果更准。新增 `Message.poster`、`NotificationConf.type`/App Push 渠道和 `/widget/*` 端点，TV 均无调用。登录与权限信号未变，`MIN_SYSTEM_BASELINE` 仍为 `2026-01-01`。
- **暂不跟进**：小组件端点与 `mpw_` 凭据、App Push 渠道与通知实例、消息海报图、整理人工复核队列与放弃端点、插件市场与站点统计等后台能力，TV 均无对应入口或端点调用。

### v3.2.1 核对范围与边界

对照官方后端 [v3.2.0 → v3.2.1](https://github.com/jxxghp/MoviePilot/compare/v3.2.0...v3.2.1) 及各标签 `version.py` 指定的 Web [v3.2.0 → v3.2.2](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.2.0...v3.2.2)。Web 基准提交为 `ba5883fc29f70202771d06b32b90c06851ca40d2`，登记当时的 v3.2.2 标签目标提交为 `3e92547ba85c7d4f9fb350a9ed14626812510840`（上游已于 2026-10-31 重指该标签，现行目标为 `7c695cf7`，差异与补充核对见下一节）。后端 `v3.2.1` 的 `FRONTEND_VERSION` 为 `v3.2.2`，与发布提交 `c30b861a3` 里的 `v3.2.1` 不同，这里以标签内 `version.py` 为准。只新增目标精确版本 v3.2.1，不推断未登记热修复版本兼容。

- **订阅**：`/subscribe/`（省略 `page`/`count` 仍返回完整快照）、`PUT /subscribe/` 的 `exclude_unset=True` 裁剪、`/subscribe/media/{media_id}` 的精确身份与标题年份回退、`/subscribe/{id}`、状态、搜索、重置、Fork 和 `/subscribe/shares` 的参数、owner 范围与响应 envelope 均未变；`app/schemas/subscribe.py` 与该次提交的数据库迁移没有变化，v3.2.0 的身份唯一约束和「修改身份字段重置进度」继续适用，TV 已有的 `>= v3.2.0` 确认门禁不受影响。新增 `GET /subscribe/calendar`（日期窗口不超过 93 天、分页最多 200 条，返回精简日历事件），TV 没有订阅日历页，不调用。`GET /subscribe/list` 的 API_TOKEN 校验从可空依赖改为必填依赖，TV 从不对该端点外发 `token` 查询参数。
- **搜索与媒体**：`/search/title/stream`、`/search/media/{media_id}/stream`、`/search/subtitle/*` 的事件字段与 `can_continue` 未变，`/search/recommend/*` 只是合并取状态、去掉 `check_only` 的缓存读取；`/media/status` 是新增的可选批量端点（最多 50 项，`media_source`/`media_id` 必须成对且不能为 `0`，只查本地库、不访问外部媒体服务器），TV 详情页仍用 `/mediaserver/exists` + `/subscribe/media/{media_id}`，是否切换到批量端点记在 `docs/frontend-update-todo.md`。`/recommend/source`、`/discover/*` 与 TMDB 组合接口未变。
- **下载、整理与站点**：`/download/*`、`/download/subtitle` 的字段与参数未变，TTG 签名下载链接识别（`is_expiring_download_url`）、115 嵌套目录变更检测、绿联海报墙 `null` 列表容错和下载临时文件不再触发未稳定告警都在后端内部执行，只会提高现有路径成功率。`app/chain/storage.py` 的严格查询新增 `FileItemQueryResult` 区分「已确认不存在」与「本提供方不支持」，`/history/transfer*`、`/transfer/*` 的响应结构未变，整理失败仍走 `success:false` + `message`。`/site/{id}/userdata` 新增可选 `latest_seeding_only`（默认 `false`，保持旧合同），TV 不传该参数。
- **系统、认证与其他**：登录限流、`/user/current`、MFA 提示、`/system/global`、`/system/env`、图片代理和权限信号未变，`MIN_SYSTEM_BASELINE` 仍为 `2026-01-01`；Redis 缓存键日志遮盖凭据、事件 handler 所有权释放、SQLite 凭据表访问校验和 nginx keepalive 都是部署侧加固。新增 `/plugin/readme/{plugin_id}`（插件文档入口）与插件市场快照同步，`torrents/cache` 新增可选分页、`title`/`site` 筛选和 `brief` 投影，TV 均无对应入口。
- **暂不跟进**：`POST /media/status` 批量状态、`/subscribe/calendar` 订阅日历、插件文档入口、种子缓存分页与筛选、站点做种明细投影、Agent 技能与 MCP 工具改动，TV 均无对应入口或端点调用。

### v3.2.2 核对范围与边界

对照官方后端 [v3.2.1 → v3.2.2](https://github.com/jxxghp/MoviePilot/compare/v3.2.1...v3.2.2) 及各标签 `version.py` 指定的 Web [v3.2.2 → v3.2.2](https://github.com/jxxghp/MoviePilot-Frontend/compare/v3.2.2...v3.2.2)（基准提交 `3e92547ba85c7d4f9fb350a9ed14626812510840`，目标提交 `7c695cf767a69349b8e8db7a7d5da5a100e804f9`）。上游在 v3.2.2 发布后强制重指了该标签：后端由 `f2857c35b2a6b10134a843dfa216560f1e0d3d2c` 改为 `c609abc782978eb81efe1da1dcf259bd3ff6e635`（共同父提交 `9aab7c0f4`，追加 12 个提交的修复与安全加固），Web 从 `3e92547b` 先线性追加 7 个提交到 `a533457e`，再追加 `1f574a4f`（#897）与 `7c695cf7`（#898）到现行标签；两个标签的 `FRONTEND_VERSION` 仍为 `v3.2.2`，本节按重指后的完整内容核对。#897 只在关于页展示 iOS 安装版本统计，#898 只让 Web/iOS 原生壳在目录请求失败后重试，并为 `media/source`、`system/module-catalog` 的客户端请求加 8 秒超时，都不改变 TV 使用的接口或字幕筛选。只新增目标精确版本 v3.2.2，不推断未登记热修复版本兼容。

- **订阅**：`/subscribe/`、`PUT /subscribe/` 的 `exclude_unset=True` 裁剪、`/subscribe/media/{media_id}`、`/subscribe/{id}`、状态、搜索、重置、Fork 与 `/subscribe/shares` 的参数、owner 范围、响应 envelope 与写回均未变，`app/schemas/subscribe.py` 和数据库迁移没有变化，v3.2.0 的身份唯一键与「修改身份字段重置进度」确认继续按原极性生效。`app/chain/subscribe/match.py` 改为严格核对候选自身的媒体身份与类型，冲突时直接拒绝，属于后端自动匹配策略，不改变 `/subscribe/search/{id}` 的请求与返回结构。`/subscribe/share/{id}` DELETE 与 `/subscribe/follow` 收紧为 manage 用户权限，TV 只调用 `/subscribe/shares` 与 `/subscribe/fork`，不涉及这两个端点。
- **搜索与媒体**：`/search/*`、`/media/*`、`/mediaserver/*`、`/recommend/*`、`/discover/*` 与图片代理未变；`app/runtime/rate.py`、`app/application/site/throttle.py` 新增的共享站点流控只在后端限制请求速率，搜索与下载的请求/响应结构不变，限流时仍按现有错误处理。`app/schemas/token.py` 只给令牌增加可选 `agent_channel`/`agent_channel_user`，普通登录、`/user/current` 和 TV 的凭据刷新不需要解析令牌载荷。
- **下载、整理与站点**：`/download/*`、`/history/transfer*`、`/transfer/manual` 的请求与响应结构未变。`app/chain/transfer/workflow.py` 新增的「自动发现整理跳过已有持久任务」按 `not (manual or preview or recovery_admission)` 排除手动整理、预览和历史重做，TV 这三条路径都在排除范围内；`app/application/transfer/jobs.py` 允许整理任务在 `task.meta` 为空时重放（`__get_meta_id`、`add_task` 的参数调整），只影响后端整理队列内部记录，TV 不调用 `/transfer/queue`。`586a4f595` 让元数据缺失的整理失败安全结算，`/history/transfer` 的字段和 `success:false` + `message` 失败语义不变，TV 的 `TransferHistory` 除 `id/status` 外均为可选解码。`6ca7b294a` 增加共享站点流控与频控错误原因。限流在下载链内消化：`download_torrent` 与 `_get_torrent_content` 接住 `RateLimitExceededException` 并收成错误字符串，`POST /download/` 与 `POST /download/add` 在 `download_single` 没有下载 ID 时仍返回原来的 `success: false` 与「任务添加失败」，不新增 HTTP 500，也不把限流原文返回给客户端。请求与响应结构未变，Web 与 TV 都只看到既有失败提示。站点 HTTP 适配器的 GET 改为逐跳跟随重定向，重定向缺少目标、目标无效、出现环路或超过跳数上限时只记录告警并返回空，不再抛错中断 CookieCloud 同步等批量流程；TV 读取的 `/site/`、`/site/rss` 响应结构未变。`/history/download` 的 DELETE 与 `/transfer/queue` 的 DELETE 收紧为 manage 用户权限，TV 均不调用。
- **系统、认证与其他**：登录、MFA 提示、`/system/global`、`/system/env`、`/system/progress`、图片代理和 `MIN_SYSTEM_BASELINE`（仍为 `2026-01-01`）未变；`914abf627`、`674c4aef6`、`80a76dee5` 收紧 `/message`、`/storage/*`、`/agent/*` 以及存储管理操作的权限并绑定目标，TV 不调用这些端点。`a9c992d9b`、`d8fbabaa6` 只保留 AppPush 通知的完整正文与海报，TV 没有 AppPush 通道；`c609abc78` 只刷新插件市场默认仓库列表（`PLUGIN_MARKET` 在 v3.2.1 已存在），`/system/global` 白名单投影与 `/system/setting/*` 结构不变；新增的 `PLUGIN_INSTALL_FROM_RELEASE`、`PLUGIN_RELEASE_TIMEOUT` 只出现在后端配置与插件市场安装路径，不通过 `/system/global` 外泄。
- **Web 配套**：`3e92547b..a533457e` 的 7 个提交已按当时范围核对。其中 `1da03170 feat(search): 字幕筛选支持中字与特效`（#890）把资源搜索字幕筛选从 `chineseSubtitle` 改名为 `subtitle`，选项由「中字」扩为「中字/特效」并支持多选；TV 没有该筛选维度，不影响运行，候选记录在 `docs/frontend-update-todo.md`。其余提交（浅色主题媒体卡片对比度、Web 系统更新按钮文案与忙碌态、AppPush 绑定重启保留、Web 原生壳搜索导航 sheet 清理、系统更新按钮避免重复状态文案、插件作者主页头像兼容）均为 Web 界面或后台能力，TV 无对应入口。其后的 #897、#898 见本节开头，不改变 TV 合同。
- **暂不跟进**：Agent 执行身份与回执、AppPush 全量投递与通知正文/海报、插件 Release 镜像安装、站点重定向加固、存储管理与 API 权限收紧、插件市场默认列表，TV 均无对应入口或端点调用；Web 的字幕筛选（中字/特效）与其余 Web 界面调整作为功能候选记录在 `docs/frontend-update-todo.md`。

## 跟进一个新版本

1. 取目标后端标签和它 `version.py` 里的配套 Web 版本，与上一个登记版本对比差异。
2. 判断差异是否影响 TV 实际用到的接口、字段和写回。没有影响，就在登记表里加上这个精确版本，并在上表补一行；有影响，先适配再登记。
3. 同步 README 的版本说明和 `SystemVersionInfoTests` 中的登记表断言，运行仓库的模拟器构建和测试。
