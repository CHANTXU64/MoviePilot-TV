# MoviePilot-TV 从零全量代码审计报告

> 状态：最终。正文审查、独立复核、争议裁决与回溯队列均已闭合；覆盖审计代理与文档一致性审计代理已分别对当前五份持久化文档复核通过，阻断为 0。

## 1. 审计基线与范围

- 启动时间：2026-07-31 04:26:46 +08:00。
- 基线：detached HEAD `4a997919983566ec208e777acf7798a95e2f9e8f`；启动时工作树干净。
- 生产范围：启动时 `MoviePilot-TV/` App target 的 78 个 Swift 文件、25,280 行；78/78 均进入新台账。
- 测试证据：32 个测试 Swift 文件、19,814 行，只作既有覆盖与缺口证据，不计入生产审查单元。
- 上游证据：规定的两个同级相对目录启动时不存在；后续使用 clean Git 快照 Web `19710a5f0fe0d795a92de904bacd3193bd8c8432`（tag `v2.13.6`）与后端 `a0ee99aacc485259431ce5be10933559f4ceac42`（tag `v2.14.4`）做逐项静态合同核对。实际部署版本、远端最新性与运行配置未验证。
- 方法：主协调代理只维护规则与审计文档；源码、测试、必要上游及调用链判断均由只读子代理完成。Ponytail 只约束复用现有机制和最小修改面，不作为事实证据。
- 原静态审计阶段未修改产品源码、测试、配置或正式清单，也未运行构建、测试、Simulator/真机、Instruments或真实后端；后续用户授权的修复、验证与清单落实以各finding当前状态为准，未执行未经授权的Push/PR/合并。

## 2. 覆盖统计

| 指标 | 最终结果 |
| --- | --- |
| 生产 Swift 文件 | 78/78 已覆盖，遗漏 0 |
| 正文审查单元 | 140/140 主审完成 |
| 不同代理独立复核 | 140/140 完成 |
| 拆分文件级集成复核 | 16/16 完成；其中 14 正常闭环、I006/I016 共 2 项受限闭环并永久披露既往源码暴露 |
| 全局回溯组 | 10/10 完成 |
| 动态依赖/回溯索引 | 284/284 最终处置：276 已闭环、8 以明确未验证边界收口；开放队列 0 |
| 阻塞 | 0；运行与部署盲点按单项“未验证”保留，不冒充阻塞或通过 |
| 发现状态 | 已确认 204；降级 5；已驳回 20；未验证 17；合计 246 |
| 严重度分布（含驳回/未验证候选的账面等级） | P0 0；P1 43；P2 122；P3 81 |
| 兼容清单建议 | CHK 20 项：已确认 20，未验证 0 |

状态说明：`未验证` 是证据或产品合同边界已明确后的最终处置，不表示仍在队列中；`已驳回` 保留编号与理由，避免后续重复误报。

P1 处置复核（2026-08-11）：历史上确认过的 P1 共 44 项，其中 30 项已修复或完成用户授权范围内对齐，10 项由用户明确跳过/接受现状，4 项经当前目标版本与实现复核后重分类（F-069、F-076、F-188、F-189）；待裁决 P1 为 0。上表的 43 是当前逐项严重度标签总数，仍包含已修复项及驳回候选，不等于开放 P1 数量。

## 3. 已确认或降级发现

以下 209 项为当前已确认或降级项。为保留原始审计时间线，详情仍按首次最终报告的严重度分区编排，后续修复或重分类不跨区搬动；当前状态与严重度以每项摘要及上方总表为准。每项给出位置、触发、根因、用户影响、两级证据、跨端边界与最小方向；完整审计时间线仍保留在 `findings.md`。

### P0（0 项）

无。

### 原始 P1 处置区（45 项）

<details>
<summary>F-007 · P1 · 已确认 · 修复已完成 · 详情直订丢失 AniList/插件身份</summary>

- 审查单元与位置：M001-A→I008；Header/预热/跳转/POST 身份链
- 触发路径：详情媒体只有 AniList/插件 `source/media_id` 身份，或标题识别得到 TMDB X 后完整详情返回权威 TMDB Y，用户从 Header 订阅或跳转。
- 根因：`buildSubscribeRequest` 没有复用完整 `detail.apiMediaId`；预热、跳转和直订又共同使用 `recognized X ?? fullDetail Y`，没有以完整详情权威值优先仲裁。
- 用户影响：精简 POST 可能完全缺少主身份；X≠Y 时还会创建并立即暂停错误媒体的真实订阅。
- 证据：既有转换审查与I008整文件主审闭合四个创建入口及X≠Y序列；review_a001_h从当前HEAD独立确认P1；复用共享draft factory与纯TMDB仲裁，不扩POST schema
- 跨端结论：TV错误mutation已确认；后端精确接受契约未验证
- 最小修改方向 / 裁决：复用 `detail.apiMediaId`；可保持中间模型自洽，但不得擅自扩展既有精简 POST schema；补 source-only builder→编码测试。
- 修复状态：已完成（`bb0777262f8b976c41afac4f1a636424bb8e9dd6`）；完整传递 AniList/统一来源/legacy 身份并改为完整详情 TMDB 优先，2 条定向测试、Simulator 干净构建、381 条非后端兼容测试与独立复审通过。

</details>

<details>
<summary>F-019 · P1 · 已确认 · 修复已完成（`90b40b4`） · 登出/切服未失效共享图片 Cookie</summary>

- 审查单元与位置：B003→G06；`KingfisherCookies.swift` 与 API 会话转换
- 触发路径：后端 origin 写入会话 Cookie；用户登出、换账号或切到同 Cookie 域下另一服务后请求图片。
- 根因：modifier 每次从持久共享 Cookie 存储读取；会话转换只清 token/业务缓存，不删除旧 origin Cookie。
- 用户影响：旧 Cookie 可能继续授权图片代理、跨账号错误授权或使新请求异常。
- 证据：既有双审闭合 TV 生命周期；G06 两票结合当前后端资源 Cookie 签发/刷新链确认同主机换端口及账号转换风险；仅删除旧会话已知主机/path 下资源 Cookie并取消对应任务；不清系统全部 Cookie
- 跨端结论：条件性 P1；真实账号差异资源与触发频率未运行验证
- 最小修改方向 / 裁决：统一会话转换边界按已知会话 Cookie 及 domain/path/Secure/portList 清理，不笼统清空无关域。

</details>

<details>
<summary>F-020 · P1 · 已确认 · 修复已完成（`90b40b4`） · 受保护图片缓存和在途任务未按账号隔离</summary>

- 审查单元与位置：B003→I010；Kingfisher 全部调用者、缓存与 downloader
- 触发路径：账号 A 以 Cookie 请求受保护 URL；登出/换账号后 B 请求相同 URL，或旧下载仍在进行。
- 根因：Cookie/header 不进缓存键；下载按 URL 合并；KFImage 默认不随消失取消；登出不取消全局 downloader、不清或分区 Kingfisher cache。
- 用户影响：B 可能命中 A 图片、加入旧 Cookie 请求，或旧请求登出后完成并写缓存。
- 证据：既有双审确认隔离缺口；I010主审、独立复核与第三裁闭合cache/downloader/logout全链并升级条件P1；受保护资源使用opaque session namespace cache key并隔离/排空旧downloader；公共图继续共享
- 跨端结论：条件性P1；同URL不同账号实际字节/授权差异未运行验证
- 最小修改方向 / 裁决：只对受保护后端图片建立会话失效或分区，取消旧任务并处理内存/磁盘缓存；公共海报继续共享。

</details>

<details>
<summary>F-024 · P1 · 已确认 · 下载任务 fallback ID 不稳定并可能碰撞</summary>

- 审查单元与位置：M001-E→W017；`DownloadingInfo.id` 与轮询合并
- 触发路径：下载项缺少非空 hash 且fallback碰撞，或上游直接返回重复hash。
- 根因：fallback 使用可变展示字段且无分隔，合并端又用 `Dictionary(uniqueKeysWithValues:)` 假定唯一；全空UUID只造成每轮重建，不作为实际碰撞证据。
- 用户影响：三秒轮询删除重建对象与焦点漂移；碰撞项首次可同时进入数组，下一轮构造旧值字典时触发不可捕获的 precondition trap并终止 App。
- 证据：当前后端schema允许缺hash，内置下载器通常提供唯一hash但入口不校验；当前Web也以`hash ?? name`作为key并可能覆盖重复身份，但仅TV会在首次保留重复后于第二轮触发不可捕获Dictionary trap
- 跨端结论：条件性P1；普通身份抖动仍P3，异常hash频率未验证
- 最小修改方向 / 裁决：行身份采用规范化非空hash、否则规范化非空name；旧/新快照显式查重并失败关闭，hash/name均不可用时不生成UUID，不新增持久身份框架。
- 处理状态：用户考虑官方内置下载器通常提供稳定唯一hash、触发依赖异常/插件producer，决定跳过修复并接受该低频条件性风险。

</details>

<details>
<summary>F-027 · P1 · 已确认 · 修复已完成（`90b40b4`） · 旧会话延迟鉴权错误可修改新会话</summary>

- 审查单元与位置：B004→W015/W018-A/W020-C→I003/I010；APIService鉴权重放与session/permission owner
- 触发路径：会话 A 请求或自动登录在途，用户 logout/切换并安装会话 B，A 随后返回 401/403 或登录 200；A→B→A 时结构快照还可能恢复相等。
- 根因：请求创建时 baseURL/token 与登录 acquisition 均未绑定单调 owner；鉴权副作用、登录成功和分步持久化操作响应到达时的全局会话，结构值相等不能区分 ABA。
- 用户影响：旧响应可用 B 凭据重登，失败时清除 B；旧 endpoint/body 还可能被重放到新服务器/账号，成功旧 200 也可能安装混合用户快照。
- 证据：既有双审及I003闭合；I010补A订阅lookup后切B、后续DELETE读取当前单例凭据的跨会话链；单调session epoch加requiredPermission；多阶段lookup→mutation共用owner并在后续请求前复核
- 跨端结论：条件性P1；真实状态码/撤权频率与部署版本未验证
- 最小修改方向 / 裁决：请求、login acquisition/loginTask、用户快照安装、重试、持久化提交和 logout 全部绑定同一单调会话代际；会话已变则只结束旧请求，旧 owner 不得关闭新 loading/error。

</details>

<details>
<summary>F-047 · P1 · 已确认 · 用户决定跳过 · 取消文案无法表示 owner 与同季多记录影响</summary>

- 审查单元与位置：B007→V012-B/C→W013-B；全局/分季/Header 取消文案与删除接口
- 触发路径：同媒体同季存在不同group、不同用户或多条订阅。
- 根因：Home 有 username 但不显示；分季摘要按 season 只保留首条且丢 owner；部分路径直取消也无“单记录”证明。
- 用户影响：用户以单条文案执行跨用户/多记录删除，无法辨认 owner/命中数。
- 证据：当前后端已对所有媒体身份按season筛选，旧“非TMDB跨季删除”反例失效；TV只展示一条group而媒体级删除可命中同季多条，Web共享同一接口
- 跨端结论：条件性P1；同季多记录真实触发频率未验证
- 最小修改方向 / 裁决：当前Web共享媒体级删除行为；用户决定跳过，不做TV单端增强。

</details>

<details>
<summary>F-048 · P1 · 已确认 · 用户决定跳过 · 确认目标与执行目标未绑定</summary>

- 审查单元与位置：B007→V012-B/C→G02；取消确认准备与执行
- 触发路径：影响范围查询失败、连续点击乱序、确认期间订阅/fallback 目标变化。
- 根因：准备失败退回普通文案；确认后 deleteResolvedSubscription 又重新 lookup/解析，不绑定提示时目标。
- 用户影响：只确认“该媒体”却执行无 season 的批量删除，或删除不同目标。
- 证据：既有链确认TOCTOU；G02两名不同复核再次闭合替换记录/范围变化并升级条件性P1；准备阶段冻结精确ID/owner/scope/session；不一致即终止并重确认
- 跨端结论：条件性错误删除P1；远端变化频率未验证
- 最小修改方向 / 裁决：当前Web同样先确认、再读取当前媒体并执行媒体级删除；用户决定跳过，不做TV单端增强。

</details>

<details>
<summary>F-054 · P1 · 已确认 · 修复已完成（`58c7e81`） · Handler 丢弃 Bangumi 精确订阅 ID</summary>

- 审查单元与位置：B007 复核新增 / M001-F→G02；SubscriptionHandler Bangumi-only 取消
- 触发路径：Bangumi-only 电影已有订阅，lookup 返回 bangumi mediaId 与精确 subscription id，无 TMDB fallback。
- 根因：Handler 只保留 mediaId，始终媒体级删除；没有拒绝 bangumi 并回退 DELETE /subscribe/{id}。
- 用户影响：已知精确owner仍被降为集合式媒体删除；Bangumi-only可稳定漏删，异常legacy碰撞时还可能命中非目标记录。
- 证据：既有双审与全新G02 clean-room复核均对照Header精确ID fallback和当前后端分支闭合；lookup命中后直接复用精确ID DELETE；不扩订阅创建
- 跨端结论：`58c7e81`已保留共享模型身份；2026-08-11 当前工作树进一步补齐 lookup 局部 DTO 的 canonical/AniList 投影。取消仍使用最终响应身份并按 season 删除，原 Bangumi 路径不改。
- 最小修改方向 / 裁决：当前补丁只完成响应投影和点击项缓存回写；相关同季多记录范围仍由F-047承载。

</details>

<details>
<summary>F-062 · P1 · 已确认 · 修复已完成（`90b40b4`） · Keychain 删除失败后旧会话可在重启复活</summary>

- 审查单元与位置：S002→G06；`KeychainHelper.swift:87-100` 及 APIService 登出链
- 触发路径：已有持久 access token 的登出或 no-access 清理中，`SecItemDelete` 返回 success/not-found 之外的状态且旧 token 仍可读；UI 仍完成登出，随后进程重启。
- 根因：APIService 明知 access token 删除失败仍清内存、移除 fallback、发送 `.sessionDidLogout`，把“持久登出成功”作为既成事实；启动固定优先读取仍存在的 Keychain token。
- 用户影响：登出看似成功，但旧账号/token 可在重启后复活；用户名与密码也可能继续残留。
- 证据：既有双审闭合删除失败恢复；G06 两票确认登出成功表象后旧token重启复活的安全边界；删除失败写高权威logout tombstone/revision并重试；启动不得恢复被撤销代际
- 跨端结论：条件性 P1；真实 Security 失败频率未验证
- 最小修改方向 / 裁决：持久化一个优先于 Keychain 恢复的明确登出状态，或在 access token 删除失败时进入可见失败/重试状态；不得继续宣布持久登出完成。

</details>

<details>
<summary>F-063 · P1 · 已确认 · 修复已完成（`90b40b4`） · Keychain/UserDefaults 无明确权威导致旧或混合会话恢复</summary>

- 审查单元与位置：S002→G06；`KeychainHelper.swift:8-84` 及 APIService/SystemViewModel 持久化链
- 触发路径：Keychain 已有账号 A，登录账号 B 时一个或多个更新失败；B 写入 UserDefaults fallback，但旧 Keychain 项仍保留。
- 根因：四项会话凭据逐项提交，fallback 没有当前权威标记；Keychain 成功时不清旧 fallback，失败时旧 Keychain 又继续优先，`read` 还把 not-found 与临时 Security 错误都折叠为 nil。
- 用户影响：重启后回到旧账号、自动登录使用混合用户名/密码、旧权限快照覆盖新会话，并可能跨账号或跨服务器。
- 证据：既有双审闭合逐项持久化；G06 两票确认A token、B user/permissions与另一代凭据可组合恢复；四项复用同一session owner/revision，只接受同代记录
- 跨端结论：条件性 P1；离线混合窗口与真实 Security 失败频率未验证
- 最小修改方向 / 裁决：保留已接受的 fallback，但明确其权威性：Keychain 成功时清除对应 fallback，失败写入 fallback 后读取必须选择新值；四项会话仍需一致代际。

</details>

<details>
<summary>F-065 · P1 · 已确认 · 修复已完成（`90b40b4`） · 分季与剧集组缓存未按 session 隔离</summary>

- 审查单元与位置：M001-F→G02；APIService 三类分季缓存
- 触发路径：服务器/账号 A 拉取剧集组或分季后切换到 B，在缓存有效期内请求相同 TMDB/group ID；或 A 的旧请求在切换后返回。
- 根因：`episodeGroupsCache`、`mediaSeasonsCache`、`groupSeasonsCache` 的 key 只有相对 endpoint/group ID，不含发起时 session/baseURL，也不在会话变化时清理或做 generation 校验。
- 用户影响：B 会话可显示 A 的剧集组/分季，并保存新服务器不存在或语义不同的 `episode_group`。
- 证据：既有双审闭合cache污染；全新G02 clean-room复核闭合跨服payload链并升级P1；切会话清缓存且store前校验既有session generation；不建缓存框架
- 跨端结论：条件性跨会话错误mutation P1；跨服数据差异频率未验证
- 最小修改方向 / 裁决：用发起时不可变 session namespace 组成缓存 key，使旧请求只能回填旧 namespace；账号维度由 A001/I003 复核。

</details>

<details>
<summary>F-069 · P3 · 降级并转CHK-003 · 当前版本无未知可写字段缺口</summary>

- 审查单元与位置：M001-F→G02；Subscribe 编码与完整 PUT
- 触发路径：仅当未来后端新增TV尚未建模的公共可写订阅字段，用户再用TV修改另一字段并完整PUT时成立。
- 根因：TV为封闭强类型模型，Web会回传GET得到的动态表单；只有上游schema先变化、TV尚未同步时才分化。
- 用户影响：目标v2.15.1当前没有字段反例；未来版本才可能因无关编辑丢失新增字段。
- 证据：当前TV `CodingKeys`、目标后端公共写入schema及Web请求逐字段复核全部覆盖；F-199的`total_episode=nil`现成破坏已由`ce7afcc`修复。
- 跨端结论：不是当前缺陷或P1，仅保留未来版本条件性兼容风险。
- 最小修改方向 / 裁决：不改产品代码；并入CHK-003，每次官方Web/后端升级时再选择同步建模、正式round-trip或阻止不安全保存。

</details>

<details>
<summary>F-072 · P1 · 已确认 · 旧轮询结果可污染新查询或新会话</summary>

- 审查单元与位置：M001-H→G04；TransferHistoryViewModel 轮询/搜索/session
- 触发路径：十秒轮询请求挂起期间提交新搜索，或在两个仍有 manage 权限的会话/服务器间切换。
- 根因：`fetchLatest()` 无 query generation 或 session snapshot，也不被 `search(with:)` 取消；旧 fetcher 返回后直接写新 `prependedItems` 并按旧结果推进分页游标。
- 用户影响：当前搜索混入旧关键词/旧会话记录、分页跳页，用户还可能对错误记录执行删除或重新整理。
- 证据：既有双审确认；G04主审与独立复核再次闭合旧fetcher续接当前fetcher/游标并双票升P1；捕获query/session/generation/fetcher，恢复与每页提交前复核
- 跨端结论：纯TV跨查询/会话状态归属缺陷
- 最小修改方向 / 裁决：搜索/会话变更递增同一代际；轮询捕获 query 与 session，恢复后不一致则丢弃且不得调整游标。
- 整改状态：已修复（`e388e8b`）；Simulator clean build、本地436/436测试与最终独立复审通过，五个真实后端兼容套件未运行。

</details>

<details>
<summary>F-076 · P2 · 已确认 · 原跨owner P1链已闭合，剩余同会话陈旧结果</summary>

- 审查单元与位置：M001-J→V011-C→W006-B/I012→G01/G04；Manual/Search 资源与最佳结果状态
- 触发路径：查询 A 成功后清空关键词、B 请求失败、A 请求挂起时把输入改为 B，或会话变化后旧请求返回。
- 根因：空输入和失败不清旧 items，提交时 query/session 无 generation，旧响应仍可发布；没有用户可见错误状态。
- 用户影响：当前剩余是同一会话内A结果在B关键词或失败状态下继续显示；统一session/generation门禁已阻止旧账号结果进入新账号。
- 证据：手动媒体ID子项已由`44908c4`修复；当前复核确认空查询直接返回、资源新请求不清旧结果及fallback失败仍有同会话陈旧状态。
- 跨端结论：原跨owner错误动作P1链已闭合；剩余为P2。
- 最小修改方向 / 裁决：新查询接受时清理或标记旧结果，空关键词清列表，失败显示错误。
- 整改状态：手动媒体 ID 搜索子项已修复（`44908c4`）；按搜索先清旧结果，关键词变化后的旧响应不再回写，空输入与失败保持空态。Simulator clean build、本地437/437测试及独立复审通过，五个真实后端兼容套件未运行；聚合 Search/Resource 子项仍开放。

</details>

<details>
<summary>F-082 · P1 · 已确认 · 修复已完成（`d8198fc`） · `success:false` 载荷可被发布为成功</summary>

- 审查单元与位置：A001-A→G02；通用 ApiResponse 解码
- 触发路径：通用数据接口返回 HTTP 2xx、envelope `success:false`，同时带非 null data。
- 根因：ApiResponse 急切解码 data；兼容路径在检查 success 前直接返回 data，不兼容路径也可能先抛 data 解码错误，均无法优先呈现服务端失败。
- 用户影响：失败可被发布为空列表/空设置；订阅快照还会把空结果缓存 30 秒，首页、详情和分季短暂显示未订阅。
- 证据：既有双审闭合通用传播；全新G02 clean-room复核按当前envelope语义升级条件性P1；先拒绝显式failure，再解data；保留success缺失兼容边界
- 跨端结论：条件性错误状态/动作P1；真实失败envelope形状未验证
- 最小修改方向 / 裁决：先解 envelope 状态，显式失败立即抛本地化服务端错误，再解 data。
- 整改状态：已修复（`d8198fc`）；共享解包器先拒绝显式失败，错形 data 仅在目标解码失败后用既有 `JSONValue` 取本地化错误，正常成功路径仍只解码一次。公开 `fetchSettings()` 聚焦用例覆盖 `data:{}` 与 `data:[]`；依赖解析、Simulator clean build、本地串行 438/438 测试及独立复审通过，五个真实后端兼容套件未运行。

</details>

<details>
<summary>F-086 · P1 · 已确认 · 修复已完成（`90b40b4`） · 未规范化 baseURL 可生成双斜杠或无效 URL</summary>

- 审查单元与位置：A001-B→G02；APIService baseURL/request 构造与登录提交边界
- 触发路径：用户输入带尾斜杠或前后空白的服务器 URL。
- 根因：登录只检查非空，baseURL 原样持久化；请求再用字符串拼接 `/api/v1` 等路径。
- 用户影响：形成 `//api/v1/...` 或无效 URL，在严格路由/代理下登录、API、SSE、图片请求失败，错误地址还成为下次默认值。
- 证据：既有双审、G02纠偏及全新clean-room复核共同闭合失败登录前全局commit链；局部规范化candidate完成登录后再一次commit
- 跨端结论：条件性会话破坏P1；服务器双斜杠容忍度未验证
- 最小修改方向 / 裁决：在单一入口 trim、限定 http/https 与 host、拒绝 query/fragment、只规范化尾斜杠，并保留反向代理 path-prefix；持久化规范值供 API/SSE/图片共用。

</details>

<details>
<summary>F-095 · P1 · 已确认 · 修复已完成（`7b7130e`） · 客户端切换后旧行会向新客户端发送动作</summary>

- 审查单元与位置：A001-E→W017；下载客户端切换与旧行动作
- 触发路径：从下载客户端 A 切到 B，在 B 的任务列表完成前操作仍显示的 A 行。
- 根因：切换时旧 rows 保留且可操作，行不携带来源 client，所有动作读取当前 `selectedClient`；删除返回后的 client guard 只会确认本来就捕获的 B。
- 用户影响：A 的 hash 被发给 B；若两个下载器存在相同 hash，可能暂停、恢复甚至删除 B 的任务。
- 证据：A001-E双审闭合错client参数；W017双审确认B慢/失败时旧行持续、固定delete_file=true形成持久数据损失；行快照绑定downloader+task，loadedClient不等于selectedClient时禁旧行，mutation显式传复合目标
- 跨端结论：条件性P1；跨客户端同hash频率未验证
- 最小修改方向 / 裁决：列表绑定已加载的 client generation；切换时立即禁用旧行，动作冻结并校验行所属 client。
- 整改状态：已修复（`7b7130e`）；列表记录实际 `loadedClient`，选择不一致时禁用旧行，暂停/继续/删除显式携带并前后校验行所属客户端；同客户端轮询不重复发布 owner。聚焦 8/8、依赖解析、Simulator clean build、本地串行 439/439 测试及最终独立复审通过，五个真实后端兼容套件未运行。

</details>

<details>
<summary>F-098 · P1 · 已确认 · 用户决定保持现状 · AI 批量整理部分受理被静默当成普通完成</summary>

- 审查单元与位置：A001-F→I009/G09；AI批量整理accepted/terminal逐ID回执
- 触发路径：批量 AI 接口返回 `success:true` 和有效 `progress_key`，但 `history_ids` 是请求集合真子集或空数组。
- 根因：成功响应解码丢弃 `message/message_i18n`，accepted IDs 未去重或约束在 requested 集合内；VM 计算 rejectedIds 后只解除 busy，不显示部分/零受理，仍监听进度并刷新清空选择。
- 用户影响：部分项目未启动但没有提示；零受理也可表现为普通进度/完成，用户无法判断哪些记录需要重试。
- 证据：既有双审闭合partial accepted与terminal receipt缺口；G09两名代理确认当前后端整批agent结果且TV模型丢弃IDs/completed；后端提供逐IDreceipt；TV仅按真实receipt退休ID，合同不足时显示批次未知，EOF另归F-080
- 跨端结论：当前逐ID完成语义缺失已确认；部署/真实失败分布未验证
- 最小修改方向 / 裁决：用户决定保持当前整批错误通知与权威刷新，不在 TV 单端推断逐 ID 结果。

</details>

<details>
<summary>F-100 · P1 · 已确认 · 修复已完成（`0cfeb12`） · 同键旧订阅状态请求可覆盖较新强刷</summary>

- 审查单元与位置：A001-J→V012-A→G02；订阅状态同键请求与详情/预加载调用链
- 触发路径：同一 `media+season` 的旧 lookup A 在途；远端订阅状态发生变化；较新的强刷 B 先返回并缓存新值，随后 A 返回旧值。
- 根因：Bool 状态请求只有全局 `subscriptionCacheGeneration`，没有同 key 的 latest-request revision；A、B 属于同一 generation 时都能写缓存并向调用方返回。
- 用户影响：较新的 Header/详情状态可被旧结果逆转；旧值既覆盖缓存又直接返回给旧调用者并写回同一 `MediaPreloadTask.isSubscribed`。Bool 缓存 120 秒且访问续期，没有固定最大陈旧年龄；若回滚为 false，详情的主动刷新 guard 还可能不再触发。
- 证据：既有三票闭合乱序；全新G02 clean-room复核补动作反转后果并升级条件性P1；每key轻量revision，旧结果在store与return前失效；不建调度框架
- 跨端结论：条件性错误mutation P1；真实频率未验证
- 最小修改方向 / 裁决：复用已有 snapshot revision 模式，为规范化同 key 维护 latest revision/task；较新 force supersede 较旧普通 miss 和 force，旧响应在 store 与 return 前都校验，旧调用者复用或读取最新结果，不新增缓存框架。
- 修复状态：`0cfeb12`已按每个规范化key绑定request revision/owner，旧normal/force不能覆盖较新的force结果或缓存；乱序回归于2026-08-11定向复跑通过。

</details>

<details>
<summary>F-107 · P2 · 已确认（用户决定跳过剩余项） · 根登录转换的错误通知 owner 失配</summary>

- 审查单元与位置：V001→R001/R002/W020-C→G08；根登录转换与跨会话通知owner
- 已修复主触发：`90b40b4`使manager监听会话UI身份、在账号/服务器/权限身份切换时清除旧banner与计时，并把`show()`改为同步发布；登录失败后成功仍残留旧banner的原P1路径已闭合。
- 剩余触发路径：账号A的业务任务在途，切换到B后旧调用者才处理失败并再次调用全局`show()`。
- 用户影响：B页面可能短暂出现A操作失败提示；旧网络请求已有会话取消保护，本项不证明错误mutation。
- 证据：现有测试覆盖先show再切号立即隐藏、同账号token刷新保留通知；尚无“切号后旧调用者晚到show”回归。
- 跨端结论：剩余项为条件性TV提示归属问题，降为P2。
- 最小修改方向 / 裁决：用户决定跳过、不改；若以后处理，只需在相关异步业务调用者发布通知前复用既有operation/session owner。

</details>

<details>
<summary>F-120 · P2 · 降级（用户决定跳过） · 页面级 busy 状态没有动作目标</summary>

- 审查单元与位置：V006→V012-B→G10/G09；页面/Sheet mutation single-flight owner
- 触发路径：卡片 A 的订阅检查或取消尚未结束时，用户对同页卡片 B 执行动作；另有非电影分支未经过同一检查，可与既有操作交错恢复。
- 根因：页面共享 Bool 既没有 target/owner，也没有统一覆盖所有动作分支；它既会把 B 当成 A 的重复操作静默丢弃，也不能阻止绕过分支的晚到 Sheet、删除或错误发布。
- 用户影响：B 电影点击会无反馈丢失；B 非电影先导航后，A 的晚到 Sheet/错误仍可打断当前页面。A 的删除参数仍捕获 A，本项不声称删除了 B 或发生错误 mutation。
- 证据：卡片路径需A请求在途时再激活B，主要后果为B动作被丢弃或A迟到UI打断B；Reorganize需预览在途时再按开始整理，当前Web同样允许该交叉。
- 跨端结论：本项未证明错目标mutation；普通快速网络下触发窗口较短，批量或慢存储时更易触发，降为P2。
- 最小修改方向 / 裁决：用户决定跳过，不做TV单端增强；具体错对象风险继续由F-074/F-075/F-152/F-156承载。

</details>

<details>
<summary>F-124 · P1 · 已修复（`4a1a291`） · 菜单显示意图可在 Handler 中反转为相反 mutation</summary>

- 审查单元与位置：V006→I010→G02；订阅菜单标签/peek task 与 Handler fresh lookup/action
- 触发路径：单用户、单订阅记录下，菜单快照为 nil/旧 false 而后端已订阅，用户点击显示的“订阅”；或快照为旧 true 而记录已不存在。
- 根因：UI 决定并展示 add/cancel 意图后没有把该意图传给 Handler；Handler 点击后重新查询，并以新结果重新决定操作种类。
- 用户影响：前一种链把用户选择“订阅”反转成无确认DELETE，属于条件性错误删除P1；反向链会打开新订阅编辑而非执行用户看到的取消。
- 修复结果：菜单将生成标签时的同一订阅状态传给Handler；fresh lookup后统一校验session，mismatch只更新缓存并提示重新操作，绝不执行相反mutation；状态一致的取消继续走共用destructive确认。
- 验证：聚焦5/5、排除真实后端兼容套件的完整本地450/450通过；同一独立复审代理首轮指出的意图冻结与session guard缺口修正后最终PASS。
- 当前边界：原条件性错误删除P1已由`4a1a291`闭合；真实后端兼容套件未运行。

</details>

<details>
<summary>F-127 · P1 · 已确认（用户决定跳过） · 重置订阅无确认即执行会丢状态的 mutation</summary>

- 审查单元与位置：V008→G02；Home 重置订阅动作与后端 reset 字段
- 触发路径：用户在 Home 直接激活“重置订阅”。
- 根因：TV 立即创建 mutation Task，没有冻结目标后的确认；版本特定后端语义会设 `note=[]`、`lack_episode=total_episode`、`current_priority=nil`、`episode_priority={}`、`manual_total_episode=0` 并把状态恢复为 `R`，同版本 Web 有确认。
- 用户影响：一次误触可丢失订阅运行历史/优先级并重启处理；真实误触频率未运行验证。
- 证据：既有双审闭合字段范围；全新G02 clean-room复核对照当前后端与Web确认升级P1；复用现有alert并冻结ID/动作，确认后调用原API
- 跨端结论：条件性持久状态破坏P1；误触频率未验证
- 用户裁决：跳过修复，保持当前直接重置行为并接受误触风险。

</details>

<details>
<summary>F-130 · P1 · 已修复（`90b40b4`） · Explore 不消费已更新的权限快照</summary>

- 审查单元与位置：V009-C→V011-C→V012-A→W006-B/W020-A…F/R001/I006→G04；存活页面权限派生状态与currentUser发布
- 触发路径：以 discovery+subscribe 初始化并选分享来源；同一账号手动重登或 401 自动登录后发布 discovery=true、subscribe=false 的新 currentUser；Explore Tab 因 discovery 仍保留且 StateObject 身份不变，旧分享列表接近末尾触发 loadMore。反向 subscribe=false→true 也不会即时出现来源。
- 根因：Explore init 只订阅筛选字段，不观察 `apiService.$currentUser`；`applySources()` 只在 init/refreshSources 调用，权限 gate 又只在 Paginator 建立时检查，现有 fetcher 每页不复核。
- 用户影响：失权后旧分享来源/数据仍可见并继续请求；严格后端 403 还可能进入 makeRequest 自动重登/登出，若后端未二次 enforce 则新受限数据可继续 append。反向获得 subscribe 后来源也不会立即出现。
- 修复结果：`90b40b4`以`baseURL + user_id + permissions`组成统一UI identity并重建整个Tab子树；每次session转换递增epoch、取消旧URLSession/SSE/图片runtime并失效缓存，MediaPreloader按identity同步清空。Paginator与根MediaAction均拒绝旧session结果；同账号同权限换token只取消旧请求，不重建UI。
- 验证：当前官方后端登录Token强制`user_id: int`，`/user/current`由TV按必需`id`解码；会话、缓存、Paginator与根页面四组聚焦测试96/96通过，既有独立复审PASS。
- 当前边界：原跨profile数据/请求P1链已闭合；未单独在真实Apple TV复演焦点动画。

</details>

<details>
<summary>F-138 · P1 · 已修复（`ff4ea14`） · 共享 MediaInfo 身份碰撞并被去重丢弃</summary>

- 审查单元与位置：V010→V011-B/D→V012-A→G01/G04；共享 `MediaInfo.id`、缓存任务与 first-wins 去重
- 触发路径：同一来源、媒体类型与季中出现两条 `tmdb/imdb/tvdb/douban/bangumi/anilist/mediaid_prefix/media_id` 全为 nil、标题稳定非空白且不同的媒体；或该形态跨页出现。
- 根因：共享 `MediaInfo.id` 在全部实际结构身份为 nil时不含 title，两个不同记录得到相同身份；现有推荐/Search 等去重按该 ID first-wins。
- 用户影响：后一条不同媒体被静默丢弃；跨页连续碰撞还会消耗既有扫描上限，提前结束可见分页。
- 证据：既有三代理确认机制；G01纠偏与G04独立复核从中央ID到缓存/导航双票升P1；中央canonical identity一次修复，F-129/F-235保留各自回归
- 跨端结论：条件性共享身份P1；0/空串语义与上游频率仍冻结
- 最小修改方向 / 裁决：只在共享 `generateUniqueKey` 的“全部当前结构身份字段为 nil且 title 稳定非空白”分支加入 title fallback，并同步现有三个构造入口；不在推荐页另造身份/去重器，不顺带重定义 0、空串或空白 ID。
- 整改状态：`ff4ea14`已按上述边界修复；聚焦20/20、依赖解析、Simulator clean build、本地串行451/451测试及独立复审通过，五个真实后端兼容套件未运行。

</details>

<details>
<summary>F-146 · P1 · 已修复（`0cfeb12`） · 剧集组旧请求可覆盖新选择并生成混合订阅目标</summary>

- 审查单元与位置：V017→W013-B；SubscribeSeason剧集组请求/选择/入库与payload owner
- 触发路径：选择剧集组A且请求挂起，快速改选B；B先成功发布，A后成功返回。
- 根因：每次Picker变化创建未跟踪Task，ViewModel没有请求revision、输入快照或owner；返回后直接写`seasonInfos`，入库检查和订阅payload却重新读取当前`effectiveEpisodeGroup`。普通`isLoading`也无owner，先结束任务可清除另一任务的loading。
- 用户影响：可形成`Picker=B / seasonInfos=A / availability=B / payload=B`；用户点击屏幕所见A季，实际创建B group订阅。两次请求都成功、同一session且空缓存即可复现，并会立即产生错误远端mutation，故条件性P1。
- 证据：V017与W013-B双审均闭合A慢B快→A覆盖seasonInfos→按当前B查入库/生成payload的同session链；W013-B再次独立闭合错误远端mutation及旧error/loading覆盖
- 跨端结论：条件性P1；快速切组频率未验证
- 最小修改方向 / 裁决：复用项目现有局部revision/latest-owner，冻结本次group/context/session，在发布季、入库状态与清loading前统一校验；取消旧Task只作优化，不替代revision，不建新框架。
- 整改状态：`0cfeb12`已按上述latest-owner边界修复；A慢B快与旧订阅阶段两条定向回归均通过，当前本地串行451/451测试通过。

</details>

<details>
<summary>F-147 · P1 · 已确认 · 保存期间仍可取消或关闭并与远端 mutation 竞跑</summary>

- 审查单元与位置：V018→W014/W018-A；Sheet mutation期间取消/关闭生命周期
- 触发路径：单次PUT仍在途时点击取消；或PUT已成功但恢复/立即搜索仍在途时点击Close。
- 根因：`isSaving`只禁用保存按钮；独立取消、交互式关闭与PUT后出现的Close没有复用它。`isSaved=true`紧跟持久PUT成功本身是正确durable rollback边界，错误在于View把它当成整个保存任务已结束。
- 用户影响：现有订阅在用户选择取消修改并关闭后仍可完成PUT；新订阅的PUT可与`onDisappear`回滚DELETE竞跑。W014确定反例中PUT先成功并回调，已发出的DELETE随后成功，用户得到保存成功但远端记录最终不存在，故条件性P1。
- 证据：V018/W014双审维持P1；W018-A双审确认同机制传播但本段按P2；复用单一mutation phase、保存中禁关闭；整理逐项复核owner
- 跨端结论：全局条件性P1；W018本段P2，真实时延未验证
- 最小修改方向 / 裁决：直接复用`isSaving`禁用取消与交互式关闭，仅在`isSaved && !isSaving`开放Close；不得把`isSaved`推迟到后处理结束，以免恢复“保存成功但搜索失败后误删”的旧问题。
- 整改状态：Subscribe P1子项已由`a872737`修复；保存中禁用取消，系统返回当下同步冻结saving状态并跳过回滚，仅该返回路径最终保存成功时提示一次。聚焦27/27、排除真实后端兼容套件后的本地452/452测试和独立复审均通过；W018-A整理Sheet的P2传播仍开放。

</details>

<details>
<summary>F-148 · P1 · 已确认 · 临时订阅缺少 created/owner/session 回滚收据</summary>

- 审查单元与位置：V018→W013-B→W014；SubscribeSheet临时订阅created/owner/session回滚收据
- 触发路径：新建订阅已POST/暂停/取详情成功但后续配置加载失败后Retry；加载期间关闭或POST返回前切session；或状态强刷后另一个客户端抢先创建同一订阅，使当前POST复用既有ID。
- 根因：唯一`onDisappear`挂在会被`isLoading`替换的VStack，而不是稳定Sheet根；准备Task无句柄，POST返回ID又在session guard后才接管。当前后端创建硬传`exist_ok=True`，重复时仍返回`success=true + 既有id`；TV API只保留ID、丢失created/reused disposition，并且全链没有单一created/owner/session rollback receipt。
- 用户影响：Retry可DELETE已创建ID又继续展示已删除记录；加载退出/session变化可遗留可运行远端订阅；重复创建复用ID时，Sheet会把用户已有订阅当成当前临时草稿无条件暂停，取消配置再删除它。超级用户陈旧/TOCTOU快照还可能命中全局既有行，均为持久远端状态破坏。
- 证据：V018双审闭合Retry/退出链；W013-B与W014不同代理闭合当前后端`exist_ok`复用ID合同；G02/G10稳定根关闭钩子、created ownership receipt、单一ID owner及恰好一次回滚矩阵
- 跨端结论：条件性P1；真实生命周期帧序、部署版本与触发频率未验证
- 最小修改方向 / 裁决：把关闭观察放到稳定Sheet根节点；创建响应必须保留created/reused与owner/session receipt，只有同session且确属本次created/draft的ID才能暂停或补偿删除；reused ID转既有编辑或提示状态变化，永不由本次取消回滚。复用一个准备Task句柄或简单epoch，晚到创建结果只处理一次。

</details>

<details>
<summary>F-149 · P1 · 已确认 · Dashboard并发请求按固定await顺序造成成功结果丢失和混合快照</summary>

- 审查单元与位置：V019→W016/G09；StatusViewModel三个Dashboard请求发布
- 触发路径：statistic/storage/downloader之一失败，而另一个或两个请求已成功。
- 根因：三个请求并发启动，却按statistic→storage→downloader顺序逐项await并立即赋值，共享一个`do/catch`；任一await抛错会跳过后续成功结果，之前已赋值结果又不回滚。
- 用户影响：例如旧`S0/R0/D0`下statistic发布`S1`、storage失败、downloader已成功`D1`，最终成为`S1/R0/D0`；首项失败则另外两项成功也全部丢弃。Status还把storage与downloader剩余空间/实时速度拼入同一卡片，失败持续时错误的新旧组合可无限期保留且没有stale提示；单纯分项失败子案为P2，跨会话发布放大后的最终等级见下文P1裁决。
- 证据：既有双审闭合分项失败混合快照；G09两名代理确认三请求无session owner及A→B发布链；局部收齐tuple、校验现有session snapshot后一次发布；失败保留上一完整快照并标stale/error
- 跨端结论：条件性跨会话运维数据污染已确认；真实切换/失败频率未验证
- 最小修改方向 / 裁决：若要求整组原子，先取得三个结果再统一赋值；若允许部分成功，则逐结果隔离错误并保留每个成功值。两种都直接复用现有`async let`和三项状态，不建加载框架。

</details>

<details>
<summary>F-151 · P1 · 已确认 · 用户决定跳过 · 预览去重投影碰撞可漏掉实际提交项</summary>

- 审查单元与位置：V021→W018-B/I015/G09；Reorganize预览条目去重与实际逐intent提交
- 触发路径：两个合法预览条目的source/target含`|`且字段边界不同，或source/target/success相同而title/message/season等其他字段不同。
- 根因：预览把`source|target|success`拼成未转义字符串作为去重key，既忽略完整item其他字段，也无法区分路径内分隔符。
- 用户影响：例如`source=/a|/b,target=/c`与`source=/a,target=/b|/c`均生成`/a|/b|/c|success`；预览Sheet和summary只显示/计数一项，但返回主Sheet后两个历史ID的prepared forms仍会各发一次后台整理，用户检查内容少于实际提交内容。
- 证据：既有双审闭合投影/跨logID丢provenance；G09两名代理确认当前测试反向固化“显示一次、提交多次”；删除TV二次去重，或让预览携带logID/intent索引并与submit使用同一规则
- 跨端结论：条件性破坏性预览失真已确认；真实碰撞分布未验证
- 最小修改方向 / 裁决：当前官方Web v2同样跨预览请求按`source/target/success`全局去重、正式提交仍逐logID执行；用户决定按Web对齐跳过，不做TV单端增强。若未来上下游共同处理，再统一preview/submit intent规则。

</details>

<details>
<summary>F-152 · P1 · 已确认 · 批删按实时列表重取目标可让确认集合静默缩水</summary>

- 审查单元与位置：V022-B→G09；TransferHistory批删确认目标快照
- 触发路径：选择ID 10、11并确认删除两条；第一条DELETE挂起时，在仍可用的搜索框提交另一查询并替换items。
- 根因：批次只冻结selectedIds，每次await后却从实时items重取对象；找不到目标时直接移出选择并continue，不记录失败。相同ID若在新查询/会话代表另一对象，还可能改用新body。
- 用户影响：第一条成功后，第二条可因新列表缺失而从未发DELETE，最终failures仍空；用户确认N条却只尝试部分且没有任何失败反馈。
- 证据：既有双审闭合列表变化链；G09两名代理结合F-204 SQLite同ID复用确认破坏性错目标；呈现alert时冻结对象签名数组，文案与action只消费该快照
- 跨端结论：条件性错误删除已确认；真实批删中变化频率未验证
- 最小修改方向 / 裁决：批次起点复用现有items与selectedIds冻结`[TransferHistory]`；无法解析的确认目标进入现有失败/重试出口，不建批处理框架。

</details>

<details>
<summary>F-156 · P1 · 已确认 · TransferHistory 旧动作只持有可复用 ID 并清新选择</summary>

- 审查单元与位置：V022-D→W018-A/G09；TransferHistory旧动作与选择状态owner
- 触发路径：同session/query选A启动批量AI；服务端全量受理A且SSE仍在运行时，用户在主行点选B；A随后终止。
- 根因：`isMutatingHistory`只禁用三个ActionDescriptor；ActionRow主Button/onTap与VM选择入口没有busy guard，overlay也未禁用根内容。旧动作收尾又对当前selectedIds处理并无条件refresh清空，而非只作用于动作启动快照。
- 用户影响：B并非A任务目标，却会在A终止后的refresh/reset中被清掉，用户只能重新选择；仅看同session新选择清除时是P3子案，G09闭合ID复用后的错对象mutation后，根finding最终为条件性P1。
- 证据：既有双审闭合迟到收尾清新选择；G09两名代理结合F-204确认后端按ID重查当前行的错对象mutation链；与F-152/F-204共用session/query和对象签名快照；不建任务框架
- 跨端结论：条件性错误删除/重整已确认；真实ID复用频率未验证
- 最小修改方向 / 裁决：直接复用`isMutatingHistory`冻结选择交互与VM入口；F-098另按动作快照在refresh后保留实际rejected/新选择，不建AI任务框架。

</details>

<details>
<summary>F-184 · P1 · 已确认 · 修复已完成（`e0f1122`） · `collection_id` 存在被直接当成合集 route 身份</summary>

- 审查单元与位置：W008-E→W010→I013/I010；合法正数`collection_id`合集route身份
- 触发路径：动态来源可正式返回合集；三根栈仍送入普通Container，inert preload永不ready/failed且每次重进必现
- 根因：动态来源可正式返回合集；三根栈仍送入普通Container，inert preload永不ready/failed且每次重进必现
- 用户影响：动态来源可正式返回合集；三根栈仍送入普通Container，inert preload永不ready/failed且每次重进必现
- 证据：I013第三裁确认条件P1；I010独立复核机制但建议P2，作为等级异议记录不重开既有裁决；原样复用Search合集分支与shouldPreloadDetail；不建route框架
- 跨端结论：条件性P1；0/负数、parts包装/递归仍未验证，程序限制污染永久披露
- 最小修改方向 / 裁决：复用现有机制做局部收敛；具体边界以发现台账为准。
- 修复状态：已完成（`e0f1122`）；四根导航与所有来源预载门禁已统一，依赖解析、Simulator clean build、本地487/487测试及独立复审通过。0/负数、parts包装/递归仍保留为未验证边界。

</details>

<details>
<summary>F-188 · P1 · 旧v2.14.4基线已确认；目标v2.15.1复核已驳回 · 高级媒体 ID 没有贯穿当前下载与整理端点</summary>

- 审查单元与位置：W012→W018-A/G09；下载/整理高级媒体ID端点合同
- 触发路径：AddDownload没有原始`media`，或Reorganize用户输入/搜索到合法正媒体ID，例如TMDB 550；Reorganize默认不复用历史识别。
- 根因：TV把当前后端使用的`tmdbid/doubanid`置nil，只发送`media_source/media_id`。`/download/add`只消费旧专用字段；当前manual transfer schema/端点也只有`tmdbid/doubanid`，整理链只有这两项存在时才进入显式识别并消费`episode_group`，generic字段在两条写链都失效。
- 用户影响：用户明确选择的精确身份完全失效，下载/整理继续自动识别，可能关联到另一媒体；Reorganize的TMDB剧集组也不会作用于该手动ID。合法正ID即可发生，不依赖F-099。
- 证据：既有双审闭合两条写链；G09两名代理对照当前后端schema确认统一字段被忽略且TV主动清空可消费legacy字段；按当前合同映射TMDB/豆瓣旧字段；未支持来源隐藏/解释
- 跨端结论：条件性错误下载/整理身份已确认；部署版本与误识别频率未验证
- 最小修改方向 / 裁决：两条写链都按当前合同映射TMDB正整数与规范豆瓣值；Bangumi/AniList在后端合同扩展前隐藏、禁用或明确说明。有原始media且选择完整结果时，以新MediaInfo替换media_in；不自造generic身份协议。
- 后续处置：原审计使用后端v2.14.4；`3b709b7`于2026-07-21已统一媒体来源身份流，并包含于v2.15.0/v2.15.1。对报告目标v2.15.1属于旧基线误报，不修改当前TV。

</details>

<details>
<summary>F-189 · P1 · 旧v2.14.4基线已确认；目标v2.15.1复核已驳回 · 手动媒体搜索把错来源 generic ID 当成目标来源</summary>

- 审查单元与位置：W001→W012/W018-A/W020-D/G09；手动媒体搜索来源owner
- 触发路径：请求豆瓣等指定来源；当前后端聚合返回另一来源条目，该条目缺目标来源原生ID但有generic`media_id`。
- 根因：当前后端端点没有source参数并聚合全部来源；TV相信无效query已过滤，既不检查`item.source`，取不到目标来源原生ID时还无条件回退generic ID，再与用户选择的来源重新组合。
- 用户影响：单次无竞态请求即可展示错来源项，并生成如`media_source=douban, media_id=42`而42实际属于TMDB。当前AddDownload和Reorganize远端影响都被F-188“generic字段不被后端消费”部分遮蔽；一旦按当前合同修复F-188，错来源正ID会立即成为真实写入输入，因此两项必须独立保留且不得重复计算同次当前损害。
- 证据：既有多段复核确认选择层；G09两名代理再次闭合当前后端无source参数、TV无客户端过滤与错误整理入口；先按当前Web规范化source过滤；长期由后端建立真实source合同
- 跨端结论：条件性错误媒体身份已确认；当前远端影响与F-188不重复计算
- 最小修改方向 / 裁决：按规范化后的`item.source == requestedSource`客户端过滤，再取该来源原生ID；generic fallback只有source/mediaid_prefix与目标一致时才允许。按当前Web对齐，不建搜索状态模型。
- 后续处置：与F-188同属旧后端快照结论；目标v2.15.1已包含`3b709b7`统一合同，因此驳回当前版本缺陷，不按旧schema做TV补丁。

</details>

<details>
<summary>F-192 · P1 · 已确认 · TV/Web对齐已完成（`b304b58`） · 下载任务缺少服务端 owner 授权</summary>

- 审查单元与位置：W016→W017；下载任务列表与mutation owner授权
- 触发路径：非superuser但具有manage权限的用户进入状态页，后端存在其他用户的下载任务。
- 根因：当前后端四个端点只验证token，不按token subject过滤列表或拒绝外部任务mutation；owner回填又仅按hash查下载历史而不含downloader。TV原样展示全部任务且模型不解码userid/downloader，也没有Web已有的普通用户owner过滤。
- 用户影响：manage-only用户可查看并暂停、继续或删除其他用户任务；这不是普通陈旧UI，而是跨用户未授权远端mutation。整理历史当前采用manage全局管理语义，不并入本项。
- 证据：review_a001_j与review_a001_h从状态页、TV/Web、当前后端独立闭合跨用户反例；后端按token subject过滤/鉴权并以downloader+task查owner；TV过滤仅展示防御
- 跨端结论：当前本地跨端缺陷已确认；部署版本、API Token策略与真实多用户频率未验证
- 最小修改方向 / 裁决：后端以token subject过滤列表，并在start/stop/delete再次校验任务owner；superuser保留全局访问，API Token按明确受信集成策略单列。owner查询使用`downloader + stable task id/hash`，不能只按hash。TV同步按当前用户过滤并解码owner作为展示防御，但不能冒充安全修复。
- 范围内处置：按用户决定只对齐Web；`b304b58`补`userid/username`普通用户展示过滤，superuser保持全量。聚焦9/9、依赖解析、Simulator clean build、本地488/488测试及独立复审通过。后端对象级owner授权缺口明确留在范围外。

</details>

<details>
<summary>F-193 · P2 · 已确认 · 原跨profile P1链已修复（`90b40b4`） · Fork同会话operation owner仍不完整</summary>

- 审查单元与位置：W015→G06；Fork POST→GET→编辑器operation owner
- 触发路径：当前剩余限于同一profile/session内，用户对A发起Fork后关闭或迅速对B操作，A/B完成与Sheet退场顺序逆转；POST成功而GET失败时也缺GET-only恢复。
- 根因：`90b40b4`已绑定来源profile/session并阻止跨账号/切服续接；同一profile内多个Fork仍共享一个呈现/错误状态槽。
- 用户影响：跨服务器同号ID打开错误账号订阅的P1后果已消除；同会话仍可能发生A迟到覆盖B、关闭后重新呈现、错误错位或重复POST恢复。
- 证据：跨profile回归`testForkedEditorDoesNotContinueUnderAnotherAccount`于2026-08-11定向复跑通过；当前Handler/Sheet复核确认剩余同会话竞争。
- 跨端结论：原条件性P1链已闭合；剩余为P2。
- 最小修改方向 / 裁决：若后续处理，只在现有Handler内增加同会话operation ID并保存POST receipt，GET失败只重试GET；不扩账号框架。

</details>

<details>
<summary>F-196 · P1 · 已确认 · TV提示已修复（`e47693a`） · 下载“删除任务”确认未披露会永久删除文件</summary>

- 审查单元与位置：W017；下载删除确认与实际文件范围
- 触发路径：用户对正确客户端、正确任务点击“删除”，在只写“确认删除?”/“删除”的系统确认中同意。
- 根因：TV请求不传`delete_file`；当前后端路由调用`remove_downloading`后沿用`remove_torrents(delete_file=true)`默认值，Transmission最终执行`delete_data=true`。UI没有展示将删除已下载文件、不可撤销、downloader或任务名。
- 用户影响：用户以为仅删除下载任务时会永久删除本地数据；即使session、owner、client和hash全部正确也成立，故是独立P1数据损失合同。
- 证据：W017主审与独立复核分别闭合TV→后端→下载器永久文件删除链，且与错client独立；默认仅删任务或显式传delete_file；若仍删数据须明确不可撤销文案、downloader与任务名
- 跨端结论：当前TV/Web/后端共享危险合同已确认；其他下载器行为与部署版本未验证
- 最小修改方向 / 裁决：优先由后端支持显式`delete_file`且默认只删任务，另设“删除任务及文件”；在当前行为改变前，TV至少明确“删除任务及已下载文件，此操作不可撤销”并展示downloader与任务名。不建确认框架。
- TV提示修复状态：`e47693a`按用户决定仅明确“将永久删除任务及已下载文件”，不修改接口与后端。该单行文案修改按用户要求未运行测试、未做子代理复审，暂存差异检查通过。

</details>

<details>
<summary>F-197 · P1 · 已确认 · 用户决定跳过并转长期Checklist · Transmission 暂停后任务从列表消失且无法继续</summary>

- 审查单元与位置：W017→G05；未完成下载暂停后的列表可恢复性
- 触发路径：Transmission中的未完成任务正在下载，用户点击暂停/stop并成功；下一轮列表刷新执行。
- 根因：当前后端“下载中”查询只要求`TorrentStatus.DOWNLOADING`；Transmission适配仅把`downloading/download_pending`纳入，不包含暂停后的`stopped`。TV和Web都每三秒用同一接口替换列表。
- 用户影响：暂停成功后该行从两端消失，用户失去继续/start按钮与hash上下文；只能离开客户端另行恢复。已完成任务也可能是stopped，故不能简单把所有stopped无条件加入。
- 证据：既有双审确认Transmission；G05主审与独立复核补齐qBittorrent/Transmission并均支持P1，rTorrent行为不同作为边界；后端列出所有未完成paused/stopped并归一状态，排除已完成项
- 跨端结论：条件性跨端P1；rTorrent与其他下载器矩阵、部署版本未验证
- 最小修改方向 / 裁决：后端列表纳入“未完成且paused/stopped”的任务并归一为paused，明确排除已完成stopped；TV/Web继续消费同一稳定状态，无需客户端补造隐藏缓存。
- 处置：不做TV单端修复；CHK-016已写入正式兼容清单，等待MoviePilot官方后端/Web改变列表合同后同步对齐。

</details>

<details>
<summary>F-199 · P1 · 已确认 · `total_episode=nil` 保存后变成 0 并关闭自动总集数刷新</summary>

- 审查单元与位置：W014→G02；Subscribe total_episode null保真
- 触发路径：已有电视剧订阅的`total_episode`为数据库NULL、`manual_total_episode=0`；用户只修改质量等无关字段并保存，没有编辑总集数。
- 根因：TV把nil显示成“0”但底层仍为nil，`encodeIfPresent`在PUT中省略该键；当前后端schema把省略字段默认成0并用完整`model_dump()`更新，比较`0 != None`后同时写0和`manual_total_episode=1`。Web会把响应中的null原样PUT，不触发该转换。
- 用户影响：一次无关保存永久改变订阅事实，并令后续元数据刷新、有效总集数计算和完成前刷新在人工标志为真时跳过，电视剧可能不再自动跟随新增集数。
- 证据：既有两票闭合跨端链；全新G02 clean-room复核纳入lossless edit根因并升级P1；dirty-field/raw overlay保留nil/absent，只有用户实际编辑才编码新值
- 跨端结论：条件性持久语义破坏P1；真实NULL分布与部署版本未验证
- 最小修改方向 / 裁决：复用F-069的原快照/dirty-field overlay，保留原nil/absent；只有用户实际编辑总集数才编码新值。后端可按`model_fields_set`区分省略与显式值，不建patch模型框架。

</details>

<details>
<summary>F-203 · P1 · 已确认 · 目标文件删除失败仍删除历史并返回成功</summary>

- 审查单元与位置：W019→G09；Transfer deletedest失败语义
- 触发路径：用户选择“删除记录和目标文件”，目标仍存在但后端实际删除失败。
- 根因：TV正确发送`deletedest=true`；当前HTTP端点调用目标`delete_media_file`后丢弃Bool，随后无条件删除历史并返回成功。源文件分支会检查Bool，同仓工具也以“存在且删除失败则保留历史并失败”为规则。
- 用户影响：目标文件仍在，UI却报告成功且历史/重试依据消失；若同时删源，还可能形成部分副作用。目标本来不存在时继续删除历史是合理正向边界。
- 证据：既有双审闭合端点/工具反例；G09两名代理确认当前后端稳定返回成功并令TV立即隐藏记录；后端检查目标删除结果，失败时保留历史并返回业务失败；TV不兜底
- 跨端结论：当前Web/TV共享破坏性后端缺陷；部署版本未验证
- 最小修改方向 / 裁决：后端复用现有工具规则：目标存在且删除失败时保留历史并返回失败，不存在视为已清理；不在TV增加差异化补偿。

</details>

<details>
<summary>F-204 · P1 · 已确认（TV修复已提交：81d42fb） · 增量轮询不对账外部删除或替换</summary>

- 审查单元与位置：W019→I009；Transfer轮询权威对账与SQLite同ID复用
- 触发路径：其他客户端删除本地可见记录，或后端以同source删除旧记录并创建新ID；TV页面/StateObject保持存活。
- 根因：`fetchLatest`遇到第一个已知ID即停止，只前插未知ID，从不删除服务端已缺失ID或替换同ID内容；页面重新激活又只在`items.isEmpty`时完整刷新。
- 用户影响：外部删除的旧行永久保留；`add_force`后新ID被插入但旧ID不移除，形成同源双记录并允许继续操作陈旧行。
- 证据：W019双审先闭合非权威列表；I009主审/定向独立复核闭合当前DB/端点完整破坏链；后端AUTOINCREMENT或row version原子校验；TV同ID比较指纹并异常回退refresh
- 跨端结论：条件性P1；PostgreSQL常规序列与非最大缺口不触发
- 最小修改方向 / 裁决：TV已按Web激活语义在每次进入Tab完成一次权威refresh，并在所有删除、AI、manual mutation前以全量记录比较指纹、绑定来源session；异常时整批拒绝并刷新提示，不建新协议或批处理框架。
- 整改状态与验证：TV修复已由`81d42fb`提交；聚焦58/58、依赖解析、Apple TV tvOS 26.5 Simulator clean build、排除五个真实后端套件后的本地串行479/479及第二名独立复审均通过。保留预检GET→mutation极短TOCTOU和全部可见指纹完全相同时客户端不可区分的边界。

</details>

<details>
<summary>F-212 · P1 · 已确认 · Reorganize 只按路径选择目录，可能改用另一存储</summary>

- 审查单元与位置：I015→G09；Reorganize目标目录复合身份
- 触发路径：配置同时存在`local + /library + move`与`rclone + /library + copy`；用户意图选择rclone项并立即预览或提交。
- 根因：TV按裸`library_path`做Set去重，选中后再`first(where:path)`取首条并以100ms debounce补写`target_storage`及目录默认值；当前后端却按`(library_storage,library_path)`筛选唯一目标。
- 用户影响：同一路径跨storage时，用户可被静默改回数组首项的另一存储、整理方式或默认值；立即操作还可捕获“新path + 旧storage/defaults”混合快照，落到错误目标合同。
- 证据：既有双审闭合数组顺序/混合tuple；G09两名代理确认当前后端复合身份与TV稳定丢storage选择；Picker身份直接使用规范(storage,path)并同步生成完整target tuple
- 跨端结论：条件性错误存储mutation已确认；真实目录分布未验证
- 最小修改方向 / 裁决：保留现有Picker，以规范化`(storage,path)`作为选项身份；冲突时标题显示目录名/存储，并同步一次生成完整target tuple，删除Set(path)、first(path)和依赖debounce补齐的路径。
- 处置状态与验证：用户要求严格对齐当前Web，决定跳过`(storage,path)`的TV单端增强；`a6cc428`已移除TV独有100ms窗口并同步生成现有path-first tuple。聚焦10/10、Simulator clean build、本地480/480及两次独立复审通过；原P1历史裁决保留但不再列为待处理项。

</details>

<details>
<summary>F-213 · P1 · 已确认 · 切换到电影后仍提交隐藏的电视剧字段</summary>

- 审查单元与位置：I015→G09；Reorganize媒体类型与隐藏剧集字段
- 触发路径：电视剧状态填写`episode_format`等剧集参数后切换为电影；剧集区从UI消失，用户提交整理。
- 根因：类型切换只清`episode_group`，`season/episode_detail/episode_format/episode_offset`继续编码；当前后端不按mtype隔离，仍构造EpisodeFormat并把模板作为硬过滤条件。
- 用户影响：电影文件不匹配旧模板时，后端可返回`success=true`但零项；TV据此调用`onDone`并关闭，用户看到成功流程却没有整理任何文件。强制电影反例确定，自动类型语义仍需产品明确。
- 证据：既有双审闭合明确电影/模板硬过滤链；G09两名代理确认全部剧集专属字段继续编码与后端消费；唯一intent构造按最终类型清除剧集专属字段；Auto由后端识别后门控
- 跨端结论：条件性错误文件整理已确认；episode_part公共字段边界保留
- 最小修改方向 / 裁决：在唯一intent构造处按可见媒体类型投影字段；电影intent省略电视剧专属值，Web同步修正，后端可拒绝矛盾载荷；自动类型先明确合同，不建媒体类型状态机。
- 处置状态：当前Web共享同一行为，用户决定跳过TV单端修复；原P1历史裁决保留但不再列为待处理项。

</details>

<details>
<summary>F-246 · P1 · 已确认 · 整理历史读取端点缺少 manage 授权</summary>

- 审查单元与位置：G09；整理历史读取端点服务端授权
- 触发路径：拥有有效JWT但`manage=false`的普通用户绕过客户端，直接请求`GET /api/v1/history/transfer?page=1&count=30`。
- 根因：TV与Web v2.15.1都已在客户端按manage隐藏/拦截入口；后端读取端点却只依赖裸`verify_token`，不查询active user或`permissions.manage`，并读取无用户过滤的全局TransferHistory表。
- 用户影响：低权限已认证主体可得到全部整理记录，包括完整源/目标路径、存储类型、嵌套文件项、下载器/hash、失败文本和媒体身份，暴露服务器文件拓扑与其他用户活动。
- 证据：G09主审与独立复核分别从TV/Web入口、当前后端依赖、全局表字段与测试缺口闭合；现有F-245已占号，顺延登记；后端复用现有active-manage依赖；TV不做安全兜底，Web路由门禁仅作UX
- 跨端结论：当前本地上游越权读取已确认；部署版本/API Token策略未验证
- 最小修改方向 / 裁决：仅在后端把GET端点的`Depends(verify_token)`替换为现有async active-manage依赖；TV与Web v2.15.1客户端门禁已经正确，无需修改。原报告关于Web直接路由仍可进入的支撑已纠正，但后端HTTP越权读取结论不受影响。
- 处置状态：用户以TV/Web v2.15.1已对齐为准，决定跳过TV单端处理；上游后端直调风险保留但不列入TV待处理队列。

</details>


### 原始 P2 处置区（115 项）

<details>
<summary>F-002 · P2 · 已确认 · 后台媒体解码穿透 MainActor 图片初始化</summary>

- 审查单元与位置：M001-C；`Models.swift:578-651`；嵌套根因在 `Person`/`SubscribeShare` 解码器
- 触发路径：后台解码的媒体响应含 `directors`、`actors` 或 `subscribeShare`。
- 根因：嵌套模型在 `init(from:)` 中读取 `@MainActor APIService.shared` 图片配置，与纯后台解码边界冲突。
- 用户影响：actor 运行时检查下可能中断解码；否则可能形成同一响应内图片配置快照不一致。不能静态宣称必然崩溃。
- 证据：M001-C 主审追踪后台入口、嵌套解码器、工程隔离设置与测试；verify_m001_c 独立确认静态隔离冲突并限定 Release/触发边界
- 跨端结论：TV 本地隔离风险已确认；实际携带字段及 Release 表现未验证
- 最小修改方向 / 裁决：保持嵌套解码为纯数据处理，在 MainActor 访问时或用已捕获配置生成图片 URL；补含人员/分享字段的 detached 解码检查。

</details>

<details>
<summary>F-003 · P2 · 已确认 · 负季号进入合法分季订阅身份</summary>

- 审查单元与位置：M001-C/I001→G02；分季订阅快照季号边界
- 触发路径：订阅快照有有效业务ID/媒体身份，但`season`为负数。
- 根因：summary会丢弃missing/null，却不校验非负；负值原样成为summary和字典key。真实S00的0值是合法输入。
- 用户影响：负季可进入状态与订阅/取消目标，和合法季集合形成错误身份；missing/null不会再伪装S00。
- 证据：G02主审提出限缩，rounda_g02_third按missing/null/negative/S00矩阵确认当前控制流；summary入口只拒绝负季号并保留0；不改S00
- 跨端结论：纯TV负季号不变量已确认；后端是否保证非负未验证
- 最小修改方向 / 裁决：只在summary failable init增加`season >= 0`，保留0；不为此改全局季模型。

</details>

<details>
<summary>F-011 · P2 · 已确认 · 修复已完成（`63767f9`） · 下载请求丢失站点凭据、UA、代理与下载器字段</summary>

- 审查单元与位置：M001-C/M001-D→V016/W012 当前合同复核；`TorrentInfo`、`AddDownloadRequest` 与 `APIService.addDownload`
- 修复状态：已完成（`63767f9`）；TorrentInfo补齐四个可选字段并由真实APIService两端点请求体回归锁定，独立复审、Simulator clean build及排除五个真实后端兼容套件后的390条本地测试通过。
- 触发路径：TV 解码官方搜索/RSS torrent 后添加下载；该资源依赖站点 Cookie、专用 UA、代理，或在 `/download/add` 未显式选顶层下载器而依赖站点下载器。
- 根因：TV `TorrentInfo` 未声明 `site_cookie/site_ua/site_proxy/site_downloader`，解码时忽略，编码到 `torrent_in` 时确定丢失；官方 Web 直接发送原 torrent 对象。
- 用户影响：私有站 HTTP torrent 可能认证失败，专用 UA/代理资源可能无法取得；自动字幕也可能缺同一组凭据。`site_downloader` 仅在 `/download/add` 且顶层下载器为空时影响选择。
- 证据：2026-08-08 核对当前官方后端 v2 HEAD `91ce365f` 与 Web v2 HEAD `7ea14bc9`；三名只读代理分别闭合 TV/后端、Web与窄裁决。后端生产四字段并在下载链消费，Web保留，TV确定丢失。
- 跨端结论：条件性下载失败已确认；磁力、缓存命中、无需认证/专用UA/代理或已显式选择下载器时不触发。通用MediaInfo嵌套raw与插件依赖未验证。
- 最小修改方向 / 裁决：只给 `TorrentInfo` 增加四个可选 Codable 字段，并补搜索 Context→`AddDownloadRequest`→捕获请求体的两端点回归；不建立通用 raw-payload 框架。

</details>

<details>
<summary>F-006 · P2 · 修复待提交 · Subscribe lookup 的 raw 数值 0 遮蔽合法 fallback</summary>

- 审查单元与位置：M001-A→G02；Subscribe lookup/取消identity
- 触发路径：lookup 返回 raw 数值 `tmdbid/bangumiid/anilistid: 0`，同时 legacy `mediaid` 是有效统一键。
- 根因：lookup 响应重建 identity 时曾直接接受 raw 数值 `0`，遮蔽合法 fallback。
- 用户影响：取消请求可能使用 `tmdb:0` 等错误键并漏命中真实订阅。
- 证据：2026-08-11 重新核对 Web v2.15.1：raw 数值 `0` 为 falsy，负数为 truthy；canonical/legacy 字符串 `"0"` 仍是有效非空字符串。此前“所有非正数都应过滤”的审计结论已纠偏。
- 跨端结论：当前工作树只让 lookup raw `0` 继续回退，保留 Web 接受负数与不透明 legacy 的语义；真实后端异常数据分布未验证。
- 最小修改方向 / 裁决：补齐 canonical/AniList 响应字段，raw 数值只跳过 `0`，并覆盖 0/负数/fallback 优先级矩阵；不引入正数限定。

</details>

<details>
<summary>F-008 · P2 · 已确认 · 修复已完成（`789e9a7`） · 订阅搜索后缓存失效未刷新已发布状态</summary>

- 审查单元与位置：M001-A→W015；`APIService.search/fork` 与 Home/Sheet/监听方
- 触发路径：手动或自动订阅搜索成功并改变远端订阅，页面仍持有旧 `@Published` 状态。
- 根因：成功出口只失效 API 缓存，不发布 `.subscriptionDidUpdate` 或强刷；缓存失效不会主动更新已有数组/任务。
- 用户影响：首页、详情预加载和分季状态要等轮询、重新激活或手动刷新；Fork 若随后编辑页被关闭也可能同类失步。
- 证据：M001-A双审闭合；W015双审确认Fork成功后GET失败/取消编辑均永不发通知；mutation成功出口恰好发布一次，不依赖后续GET/编辑保存
- 跨端结论：TV发布状态缺口已确认；后端完成时机未验证
- 最小修改方向 / 裁决：每个改变远端订阅的最终成功出口恰好发一次刷新事件；首页手动搜索还应立即强刷自身，不让通用缓存清理无条件发事件。
- 修复状态：已完成（`789e9a7`）；Home 搜索/状态/重置强刷自身并通知，保存、回滚 DELETE、分季 DELETE 与 Fork 在各自 mutation 成功出口恰好通知一次；独立复审、Simulator clean build 与 386 条非后端兼容测试通过。
- 保留边界：搜索成功仅表示后台任务已受理，立即强刷可能先读到未完成快照；Home 会因响应自身通知多做一次只读列表 GET，但不重复 mutation 或通知。

</details>

<details>
<summary>F-012 · P2 · 已确认 · 订阅导航截断主身份并反转兼容优先级</summary>

- 审查单元与位置：M001-A→I014当前合同复核；`Subscribe.navigationMediaInfo()`与Home详情入口
- 触发路径：普通订阅为canonical-only/AniList-only，或canonical、raw built-in、legacy身份互相冲突。
- 根因：转换漏`anilistid/media_source/media_id`，并让legacy拆分结果可能抢在raw built-in前；违反当前官方canonical→raw→legacy顺序。
- 用户影响：Home进入无身份或错误身份详情，后续资源、订阅检查/删除、分季匹配与保存继承错误owner。
- 证据：三路当前TV/Web/后端复核确认普通Subscribe七字段均是schema/DB/GET正式合同，canonical-only/AniList-only是支持路径；已修F-007下游builder完整但未修该入口投影。
- 跨端结论：TV投影/优先级缺陷已确认；canonical-only TMDB group raw限制与Web相同且从该入口稳定触发未确认，另留P3边界。
- 最小修改方向 / 裁决：只在该转换内按canonical→四raw→legacy解析一次，将最终身份写入`source/media_id`；保留过滤后的raw字段，不扩通用MediaInfo legacy模型。
- 修复状态：已完成（`58c7e81`）；独立复审、tvOS Simulator clean build 与显式排除五个后端兼容套件后的397条本地测试通过。

</details>

<details>
<summary>F-022 · P2 · 已确认 · 修复已完成（`06d9fe5`） · 单条资源缺字段可令整次搜索失败</summary>

- 审查单元与位置：M001-E；`Models.swift` 资源嵌套模型与 SSE/fallback
- 触发路径：任一资源缺/null/类型异常的 size、促销因子、MetaInfo name 或 season_episode。
- 根因：嵌套输入边界过严；一个对象失败终止 SSE，fallback 又严格解码整批。
- 用户影响：整次搜索退回同步后仍可能失败；不是崩溃。
- 证据：review_m001_e 闭合严格嵌套解码、SSE 终止和同步 fallback；verify_m001_e 独立确认当前流首错终止、fallback 同批再失败及测试盲点
- 跨端结论：当前后端 schema 允许相关字段为空；Web 不会因单项字段缺失拒绝整批
- 最小修改方向 / 裁决：只在输入边界宽容，内部显示、过滤和添加下载请求保持稳定，不批量 Optional 化。
- 修复状态：提交 `06d9fe5` 只在 `TorrentInfo`/`MetaInfo` 解码入口提供现有中性默认值，未扩散 Optional 或新增解码框架；SSE/fallback 稀疏同批与超范围大小回归已覆盖。最终独立复审通过，tvOS Simulator clean build 与本地测试 428/428 通过（明确跳过 5 个真实后端兼容套件）。

</details>

<details>
<summary>F-026 · P2 · 已确认 · 修复已完成（`90b40b4`） · Paginator 无认证预取可劫持后续 Cookie 请求</summary>

- 审查单元与位置：B003 复核新增 / S004→I010；`Paginator.swift:114-129` 与 12 个图片 provider
- 触发路径：Paginator 先预取受 Cookie 保护 URL，随后可见 KFImage 请求同一 URL。
- 根因：`ImagePrefetcher(urls:)` 未传 cookie modifier，却共享默认 downloader/cache；后续请求只按 URL 加入已有无 Cookie task。
- 用户影响：受保护图片失败；可解码的未授权占位还可能写入共享缓存，反向顺序也会混用认证任务。
- 证据：既有双审闭合；I010独立复核再次确认Search/MediaCard调用链仍使用无modifier预取；预取与显示复用同一认证选项；会话持久缓存隔离仍归F-020
- 跨端结论：TV 认证选项缺陷已确认；受保护 URL/竞态频率未验证
- 最小修改方向 / 裁决：预取与最终显示使用相同认证选项，不新增另一套图片客户端。

</details>

<details>
<summary>F-028 · P2 · 已驳回 · 静默校验不刷新权限快照</summary>

- 审查单元与位置：B004→R001；`validateTokenSilently` 与权限 UI/缓存
- 触发路径：token 有效但后端增加、移除或撤销权限。
- 根因：请求 `/user/current` 后丢弃响应，只有冷启动更新 currentUser。
- 用户影响：新入口不出现，已撤销入口/自动预取/缓存状态继续沿用旧权限。
- 证据：当前Web登录后只使用持久权限，前台/路由切换不请求current user；TV冷启动已有权威刷新，403静默校验与自动重登完整，`90b40b4`已闭合正式session发布后的UI/cache收敛
- 跨端结论：成功响应被丢弃的静态事实成立，但运行中权限热同步不是当前Web/TV合同要求
- 最小修改方向 / 裁决：建议驳回旧P2并保持现有token有效性校验；若未来明确要求热刷新，必须相同快照no-op且旧epoch不可发布，不能无条件推进会话。
- 处理状态：用户决定跳过；管理员运行中修改权限由重登/重启恢复，不新增权限热同步。

</details>

<details>
<summary>F-029 · P2 · 已确认 · 手动重登无权限时保留旧会话</summary>

- 审查单元与位置：B004；手动 relogin/no-access 分支
- 触发路径：旧会话有权限，手动刷新后登录接口返回新 Token 但无可访问功能。
- 根因：login 先抛 no-access 错误，既不安装新 Token，也不清理旧会话；手动入口只显示失败。
- 用户影响：旧 token、权限和入口继续保留，与冷启动同类场景主动登出不一致。
- 证据：review_b004 对比手动刷新与冷启动/App 更新出口；verify_b004 独立确认三个重登出口语义分裂
- 跨端结论：当前后端允许认证成功但显式无四类功能权限；Web不会提交这种候选身份，TV手动刷新现已清理原旧会话
- 最小修改方向 / 裁决：所有重登出口复用同一 no-access 会话裁决。
- 修复状态：已完成（`90b40b4`）；密码/网络失败仍保留旧会话，epoch保护阻止迟到旧候选影响新账号。空permissions的默认权限差异另归F-030核对。

</details>

<details>
<summary>F-030 · 条件性P1 · 已确认 · 非 Bool 权限项拖垮整个 Token</summary>

- 审查单元与位置：B004→G06；`UserPermissions.swift` permissions 解码
- 触发路径：任一已知或未来未知权限键为String/Int/null/object；当前官方Web正常保存的嵌套`permissions.features`已稳定满足该条件。
- 根因：字典原子解码；单项错误使 Token/CurrentUserResponse 全部失败，super_user override 无法到达。
- 用户影响：当前官方Web新建或编辑过的有效账号可在TV完整登录及`/user/current`恢复时直接解码失败，superuser也无法到达覆盖逻辑。
- 证据：官方Web正常持久化嵌套`features`对象；后端只声明泛型dict且create/update/login/current均不逐值规整；TV两个身份响应都用`[String: Bool]?`合成解码。
- 跨端结论：Web逐key严格判断，坏项不污染其余权限；TV会因一个object值丢掉完整身份，当前正常producer可达。
- 最小修改方向 / 裁决：单一权限JSON边界逐key读取；四个已知分类只接受原生Bool，未知顶层键忽略，不新增第二套权限架构。空/缺权限默认语义保持拆项。
- 修复状态：已完成（`ee5dcb4`）；登录Token、持久化恢复与`/user/current`共用同一解码语义，聚焦22/22、Simulator clean build、本地非兼容测试435/435及独立复审通过。

</details>

<details>
<summary>F-031 · 条件性P3 · 降级 · 纯空白 access token 被视为登录会话</summary>

- 审查单元与位置：B004→G06；token 登录/恢复/登录态判断
- 触发路径：登录响应或损坏持久化中的顶层active token是纯空白；空串已由`90b40b4`拒绝。
- 根因：剩余登录态与Authorization判断未trim纯空白；统一记录内空串currentUser token另为合法内部哨兵。
- 用户影响：进入已登录 UI 并展示缓存权限，但请求携带空 Bearer，随后零散失败/登出。
- 证据：既有双审闭合 login/恢复；G06 两票确认根UI、Bearer空值与tokenless权限快照组合链；写入、恢复、isLoggedIn与Authorization共用trim后非空不变量
- 跨端结论：当前官方后端PyJWT producer不产纯空白，Web也未增加空白校验；确定触发仅损坏存储或非官方兼容端，且不构成权限提升。
- 最小修改方向 / 裁决：降为条件性P3并由用户决定跳过；若未来官方路径可达，再只规范化顶层active token，保留内部tokenless currentUser哨兵。

</details>

<details>
<summary>F-032 · P2 · 已修复 · torrent-only 结果被静默空渲染</summary>

- 审查单元与位置：M001-E 复核新增 / S004 裁决；`Context.meta_info` 与 TorrentCard/TorrentsResultView
- 触发路径：合法 `torrent_info` 存在而 `meta_info` 缺失/null。
- 根因：模型允许部分结果，卡片却要求 meta+torrent；结果页只按原数组是否为空判断空态。
- 用户影响：计数非零且无空态，但卡片为 EmptyView；整批如此时显示空白网格且无法下载。
- 证据：verify_m001_e 以多个 torrent-only fixture 闭合非空计数→EmptyView 链；review_s004 独立确认模型合法、过滤保留、非零计数与卡片 EmptyView
- 跨端结论：当前 MP 官方标题/精确搜索的普通与流式链路都会创建 `MetaInfo`；schema 仍允许 `null`，Web 对异常结果保留卡片并用资源字段降级展示。
- 最小修改方向 / 裁决：按 Web 对齐；只要求 `torrent_info` 存在，元数据字段可选，标题按媒体名、识别名、资源标题依次兜底，不改后端契约。
- 修复状态：已完成。`TorrentCard` 已移除对 `meta_info` 的整体门禁，资源标题兜底到 `torrent.title`，季集、描述和标签按缺失字段分别隐藏。
- 验证：依赖解析、tvOS Simulator Debug 构建及串行测试均通过；当前官方搜索源码核对确认正常搜索链不会主动生成缺失 `meta_info`，本修复作为 Web 兼容防御保留。

</details>

<details>
<summary>F-033 · P2 · 已修复 · 分页错误状态无人消费且无保留列表恢复</summary>

- 审查单元与位置：S004；Paginator 错误状态与全部生产调用者
- 触发路径：首次加载失败，或任一页连续失败三次。
- 根因：内部不自动重试；达到上限后 hasMore=false，唯一恢复 refresh 会清列表；生产端无 hasError/lastError 消费者。
- 用户影响：首次错误被显示成“无数据/未找到”，后续页永久截断且用户不知情。
- 证据：review_s004 核对 13 实例、全部 View 与测试只手动重试；verify_s004 独立确认零消费者、错误上限与页面误空态
- 跨端结论：Web 会显示分页错误与重试入口；TV 按用户决定只在三次连续失败达到上限时统一通知，不增加按钮。
- 修复状态：已完成。`Paginator` 达到现有三次错误上限后发送全局事件，`NotificationManager` 显示“加载数据失败，请重试。”；前两次保持静默。
- 验证：依赖解析、tvOS Simulator Debug 完整构建及串行测试均通过，回归覆盖通知阈值与文案。

</details>

<details>
<summary>F-034 · P2 · 已确认 · 用户决定跳过 · 非终止空批被误判为终页</summary>

- 审查单元与位置：S004→V011-F；SharedMediaFetcher 与 Paginator 空页语义
- 触发路径：最多五轮只有另一媒体类型，更后页才有目标类型。
- 根因：fetchUntil 达扫描上限可在内部 hasMore=true 时返回空数组，Paginator 把所有空数组永久解释为终页。
- 用户影响：聚合搜索永久漏掉实际存在的电影或电视剧。
- 证据：review_s004 构造六页异类/第七页目标序列；verify_a001_h 从 actor 实现重走；verify_s004 独立确认 buffer/hasMore 与终页契约
- 跨端结论：TV 契约冲突已确认；后端混排分布未验证
- 最小修改方向 / 裁决：用户决定跳过；保留当前最多扫描六页的性能边界，接受极端混排下可能漏项。

</details>

<details>
<summary>F-035 · P2 · 已确认 · 用户决定跳过 · in-flight Task 强持有 Paginator</summary>

- 审查单元与位置：S004→V011-C→G04；Paginator/Search in-flight Task 生命周期
- 触发路径：fetcher 挂起时 owner 释放，但未显式 cancel。
- 根因：Task 弱捕获后立即强绑定 self，self 又持有 Task；请求完成前 deinit 无法先执行取消。
- 用户影响：页面消失后请求、处理与预取继续，长请求延长对象图生命周期。
- 证据：既有双审闭合强持有；全新G04 clean-room复核收窄为owner离场生命周期并升级P2；owner/session级显式取消共享搜索；不重写已有generation屏障
- 跨端结论：TV生命周期缺口已确认；push/切Tab/销毁的取消产品边界与驻留时长未运行验证
- 最小修改方向 / 裁决：用户决定跳过；接受慢请求离页后继续占用网络与内存，正常请求快速完成时通常无感。

</details>

<details>
<summary>F-036 · P2 · 已修复 · processor 漏掉页内重复 ID</summary>

- 审查单元与位置：S004→V011-D→G07；Search 人物与 TransferHistory processor
- 触发路径：同一页有重复 raw_id/id，或人物缺 raw_id 后生成相同 id。
- 根因：只从旧 items 建不可变 existingIds，过滤当前批次时不插入已接受 ID。
- 用户影响：ForEach 重复身份、焦点含糊，firstIndex 总指向首项并可能停止继续分页。
- 证据：既有processor复核闭合不可变seen；G07双审及第三裁确认合法跨source聚合与批内重复；使用最终`Person.id`可变seen并在reset清空；Paginator扫描另归F-034
- 修复：Search按包含来源的最终`Person.id`维护可变seen，并在Paginator reset时清空；Transfer过滤当前批次时同步写入seen。
- 验证：人物身份去重测试及同一Search人物Paginator刷新链路测试通过；依赖解析、tvOS Simulator Debug完整构建与串行全量测试均通过。

</details>

<details>
<summary>F-039 · P2 · 已确认 · 用户决定跳过 · 取消 Paginator 不会取消共享搜索真实请求</summary>

- 审查单元与位置：S004→V011-C→G04；`SearchViewModel.SharedMediaFetcher` 取消链
- 触发路径：旧聚合搜索挂起时发起新搜索、切换模式或离开页面。
- 根因：实际 API 调用在独立 Task 中；Paginator.cancel 只取消等待者，不取消该任务。单个waiter退出时保留共享请求是合理语义，但整个search session废弃时也没有aggregate cancel。
- 用户影响：旧查询继续占用网络/后端并与新查询重叠；结果会被 generation 丢弃，但扩大旧会话请求风险。
- 证据：既有双审闭合unstructured task；全新G04 clean-room复核收窄共享语义并升级P2；只在session owner失效时取消共享task；保留另一合法waiter
- 跨端结论：TV session级取消缺口已确认；真实慢请求量未验证
- 最小修改方向 / 裁决：用户决定跳过；旧结果已有generation屏障，接受慢请求继续占用资源，避免修改共享电影/电视剧请求的取消语义。

</details>

<details>
<summary>F-049 · P2 · 已修复 · Home/Header 取消业务失败静默</summary>

- 审查单元与位置：B007→V012-B→G08；Home/Header 取消结果
- 触发路径：缺订阅 id、远端已删、success:false、lookup/delete false。
- 根因：流程只返回 Bool 并丢弃 false；Home 显示确认前也未强刷。只有抛错才通知。
- 用户影响：弹窗关闭但订阅仍在或请求未发，无失败原因。
- 证据：既有双审闭合结果出口；G08 三方裁决确认 Home 稳定丢弃 false 并升级 P2；复用现有错误通知反馈业务拒绝；远端已删除且 UI 收敛时保持静默
- 修复：Home业务false或异常、Header删除失败且刷新后仍订阅时，统一通知“取消订阅失败，请重试”；远端已删除并收敛为未订阅时保持静默。
- 验证：Home业务失败、Header状态收敛及View通知接线回归通过；依赖解析、tvOS Simulator Debug完整构建与串行全量测试均通过。

</details>

<details>
<summary>F-061 · P2 · 已确认 · 软过滤置尾被结果页二次排序破坏</summary>

- 审查单元与位置：S003 复核新增 / M001-K→I011；`CustomFilterService.swift:24-67`、`TorrentsResultView.swift:248-291`
- 触发路径：软过滤未命中项的 `pri_order` 或当前排序值高于命中项；即使用户未改排序，结果页首次出现也会重排。
- 根因：服务先按“命中 + 未命中”置尾，结果页默认和后续排序均无条件重排整个数组，比较器忽略 `isFilteredOut`。
- 用户影响：本应置尾的灰色资源可重新出现在顶部，软过滤只剩视觉标记。
- 证据：既有双审确认机制；I011补默认策略覆盖，review_a001_j第三裁决按每次默认展示与错误策略升级P2；默认原样保留后端顺序；其他排序只在isFilteredOut分区内执行
- 跨端结论：纯TV内部排序策略冲突已确认
- 最小修改方向 / 裁决：在结果页排序中先按 `isFilteredOut` 分区，再应用用户选择的排序键；最终产品语义由 G05 单元复核。

</details>

<details>
<summary>F-064 · P2 · 已确认 · 混合类型头像对象可拖垮人物或媒体数组</summary>

- 审查单元与位置：M001-G；`Models.swift:2323-2337` 及 Person 解码入口
- 触发路径：可选 `avatar` 对象同时含有效 URL 与数值/null 元数据，如 `{"normal":"…","width":100}`；或 `normal` 为空但 `large` 有效。
- 根因：`PersonAvatar` 将整个对象解为同质 `[String:String]`，任一非字符串值令对象失败；随后用原始字符串 `??` 选择 URL，空白首选会遮蔽有效后备值。
- 用户影响：单个可选头像对象可令人物搜索、演员页、人物详情或含人员的媒体/资源批次整体失败；资源 SSE 可终止并在同步 fallback 再次失败；空首选会退化为占位图。
- 证据：review_m001_g 闭合 PersonAvatar、数组原子解码与 source-aware 图片传播链；verify_m001_g_retry 独立确认可选字段错误传播至人物/媒体/资源批次及空首选遮蔽
- 跨端结论：TV 失败机制已确认；当前后端 schema 已确认 avatar 允许 string/dict
- 最小修改方向 / 裁决：在 `PersonAvatar` 模型边界逐个解码已知 URL 键、忽略无关值并选择首个 trim 后非空字符串；无可用 URL 时将可选头像降级为 nil。
- 修复状态：已完成（`af67839`）；混合元数据与无可用头像回归已覆盖，独立复审通过，Simulator clean build 与本地测试 430/430 通过（跳过5个真实后端兼容套件）。

</details>

<details>
<summary>F-066 · P2 · 已确认 · 辅助或非正 raw TMDB ID 被当作主身份加载剧集组</summary>

- 审查单元与位置：M001-F；SubscribeSheetViewModel 剧集组加载资格
- 触发路径：主身份为 AniList、Douban 或插件但带辅助 `tmdbid`，或快照为非正 `tmdbid + 有效 mediaid`，用户打开订阅编辑页。
- 根因：编辑页只用 `type == "电视剧" && tmdbid != nil` 放行，没有复用 `Subscribe.identity`，也不过滤 0/负数。
- 用户影响：请求辅助媒体或 `/media/groups/0`，展示并可能保存不属于主订阅身份的剧集组；失败还可阻断编辑页。
- 证据：review_m001_f 对照 Subscribe.identity、分季正确入口与现有契约；verify_m001_f_retry 确认编辑页 gate 分裂，verify_a001_h 补充负数也可通过并进入 API
- 跨端结论：TV 内部主身份契约不一致
- 最小修改方向 / 裁决：复用统一身份判定，仅在主身份为 TMDB 且 raw TMDB ID 有效时加载。

</details>

<details>
<summary>F-067 · P2 · 已确认 · 可选剧集组失败阻断整个订阅编辑页</summary>

- 审查单元与位置：M001-F→G02；SubscribeSheetViewModel 配置加载
- 触发路径：站点、下载器和目录已成功，但可选剧集组请求失败。
- 根因：剧集组请求位于核心配置加载总 `do/catch` 内；任一失败都会清空全部选项并设置错误，保存按钮因此禁用。
- 用户影响：无法编辑与剧集组无关的站点、质量、路径等配置。
- 证据：既有双审确认机制；G02两名不同复核按当前HEAD再次闭合稳定阻断并升级P2；核心选项先发布，可选增强各自best-effort并保留原值
- 跨端结论：纯TV错误隔离P2；Web策略未验证
- 最小修改方向 / 裁决：核心选项发布后单独 best-effort 加载剧集组；失败只清剧集组选项并保留原始 `episode_group`。

</details>

<details>
<summary>F-068 · P2 · 已确认 · nil/0/重复业务 ID 可进入订阅快照</summary>

- 审查单元与位置：M001-F；Subscribe 快照与 Home/动作链
- 触发路径：`GET /subscribe/` 返回缺失/null、0、负数或重复 `id` 的记录。
- 根因：`Subscribe.id` 允许 nil 并直接充当 `Identifiable.ID`；快照入口不校验唯一正业务 ID，兼容巡检遇 nil 又直接跳过。
- 用户影响：SwiftUI 身份/焦点冲突，编辑、保存、搜索、暂停、重置和删除会因缺 ID 静默失败。
- 证据：review_m001_f 闭合 Optional Identifiable、ForEach、动作 guard 与巡检跳过链；verify_m001_f_retry 独立扩展确认 0/负数动作路径及兼容巡检盲点
- 跨端结论：TV 必需 ID 不变量已确认；当前后端保证未验证
- 最小修改方向 / 裁决：快照/详情边界要求唯一正 ID，草稿构造仍可保留 nil；巡检不得跳过缺失或重复 ID。

</details>

<details>
<summary>F-070 · P2 · 已确认 · 未知 AI 能力被当作已启用</summary>

- 审查单元与位置：M001-H→G09；GlobalSettings 与 Transfer AI 入口
- 触发路径：settings 未加载、用户设置端点 404/403，或合法响应省略 `AI_AGENT_ENABLE`。
- 根因：可选能力标志用 `!= false` 判断，nil/未知被当成已启用。
- 用户影响：显示并允许执行后端未声明可用的 AI 整理，最终才提示启动失败。
- 证据：既有双审闭合 nil settings/字段与入口分支；G09两名代理从当前后端/Web合同重新确认缺失/失败应按禁用；`== true`复用现有settings；补nil/失败/false/true矩阵
- 跨端结论：当前本地跨端语义已确认；部署版本未验证
- 最小修改方向 / 裁决：先确认产品契约；若未知应禁用，再最小改为 `== true` 并补 nil/false/true 与设置异步更新测试。

</details>

<details>
<summary>F-071 · P2 · 已确认 · 搜索后 owner 与 fetcher 形成强引用环</summary>

- 审查单元与位置：M001-H→I009；TransferHistoryViewModel 搜索 fetcher
- 触发路径：用户首次提交转移历史标题搜索。
- 根因：owner 强持有 `fetcher`，搜索写入的 escaping closure 又通过 `self.pageSize` 强持有 owner；初始化路径已用局部 pageSize 避免捕获。
- 用户影响：退出状态页或登出后 ViewModel、历史列表及关联对象不能释放。
- 证据：既有双审闭合环；I009主审与定向独立复核确认请求完成后仍永久存在；像init一样在闭包外冻结局部pageSize；不建生命周期框架
- 跨端结论：纯TV永久内存生命周期缺陷已确认
- 最小修改方向 / 裁决：与初始化路径相同，在闭包外复制 pageSize，不引入新抽象。

</details>

<details>
<summary>F-073 · P2 · 已确认 · 手动整理预览嵌套响应缺失时失败开放</summary>

- 审查单元与位置：M001-J→G09；ManualTransferPreview envelope/data/item 与统计/UI
- 触发路径：`success:true`但data缺失/null或item success缺失/null会被当成功预览
- 根因：`success:true`但data缺失/null或item success缺失/null会被当成功预览
- 用户影响：兼容或畸形producer可把未知结果显示为“整理后”，或用0/0/0空预览掩盖响应不完整；不会在预览阶段直接执行文件mutation，故为条件性P2而非P1。
- 证据：既有双审闭合fail-open；G09主审与clean-room第三裁逐矩阵确认成立分支，独立复核对envelope缺success的反证被吸收；endpoint局部要求data与每项Bool success，合法显式空仍成功
- 跨端结论：当前正式producer完整；畸形/兼容producer触发频率未验证
- 最小修改方向 / 裁决：只在`previewManualTransfer`要求`data != nil`，并把`ManualTransferPreviewItem.success`收紧为必填Bool；合法`summary=0/items=[]`继续成功。不改通用`ApiResponse`，不建新响应框架。

</details>

<details>
<summary>F-074 · P2 · 已确认 · 旧预览可在表单或会话变化后回写</summary>

- 审查单元与位置：M001-J→V021/W018-B；Reorganize预览operation owner
- 触发路径：表单 A 预览挂起时修改路径、媒体 ID、季集配置或切换会话，旧请求随后返回。
- 根因：表单变化只清当前 previewData，不取消请求或绑定表单/session 代际；旧任务仍发布并自动打开 Sheet。
- 用户影响：展示的是 A 的目标，但“开始整理”提交当前表单 B，安全确认步骤失真并可能把文件放到未预览目的地。
- 证据：模型/V021双审及W018-B双审闭合无revision/cancel、预览A→提交B与Web共享链；冻结forms/session/revision；编辑、新预览、提交、dismiss/session切换退休旧结果
- 跨端结论：当前Web/TV共享安全缺陷；运行时取消窗口未验证
- 最小修改方向 / 裁决：动作起点冻结forms、session与revision；编辑、新预览、提交开始、dismiss或session切换递增revision/取消旧任务，每次await及发布/开Sheet前复核。复用现有Task/状态，不新增协调器。

</details>

<details>
<summary>F-075 · P2 · 已确认 · 批量提交不保留逐 ID 受理状态</summary>

- 审查单元与位置：M001-J→W018-A；ReorganizeViewModel 批量后台整理
- 触发路径：批量整理前几条 background 请求成功受理，后续返回 false 或抛错。
- 根因：逐条提交不记录已受理/失败/未知 ID；异常 catch 会把前项成功后的批次描述为“整理没有开始”，失败后仍保留整批供无差别重试。
- 用户影响：用户会误以为没有任务启动并重试全部记录，已排队整理可能被重复提交。
- 证据：模型双审与W018-A双审确认success→false/throw、未发送与整批重试链；保留逐ID receipt并只重试失败/未发送项
- 跨端结论：TV 状态/反馈缺陷；后端幂等性未验证
- 最小修改方向 / 裁决：保留逐 ID 已受理/失败结果，明确报告部分成功，避免重试已受理 ID。

</details>

<details>
<summary>F-077 · P2 · 已确认 · 订阅分享投影丢失跨来源主身份</summary>

- 审查单元与位置：M001-I当前合同复核；`SubscribeShare.toMediaInfo()`与Explore/Search通用菜单入口
- 触发路径：Bangumi/AniList/canonical-only或canonical与辅助raw冲突的分享进入详情、资源、普通/分季订阅。
- 根因：当前Share schema已有`bangumiid/anilistid/media_source/media_id`；TV对Bangumi漏投影，对后三项模型和投影都缺，无法保持canonical→raw优先级。
- 用户影响：详情无身份或打开辅助TMDB而非声明主来源；资源与订阅动作继承错误owner。主点击Fork使用原Share对象，投影问题不影响该跳。
- 证据：后端91ce365f与Web 7ea14bc9合同、三路TV调用链和横向转换矩阵一致；未发现第三个同根转换遗漏。
- 跨端结论：条件性身份缺失/错路由已确认；真实单一来源/冲突记录频率未验证。
- 最小修改方向 / 裁决：补三个明确模型字段，在共享投影按canonical→raw保留Bangumi/AniList/统一身份；不在调用者补fallback、不建raw框架。
- 修复状态：已完成（`58c7e81`）；完整与不完整canonical、raw竞争和真实详情请求出口已有回归覆盖。

</details>

<details>
<summary>F-079 · P2 · 已确认 · 分享GET→Fork丢失当前schema的AniList与统一身份</summary>

- 审查单元与位置：M001-I当前合同复核；`SubscribeShare`解码与`APIService.forkSubscription`
- 触发路径：分享GET返回`anilistid`或`media_source/media_id`，TV解码后用户直接Fork。
- 根因：三字段均属当前后端Share GET/Fork schema与Web类型，但TV模型未声明；GET解码即丢失，Fork直接编码残缺模型。
- 用户影响：纯AniList/统一来源分享可Fork成缺主身份订阅；多身份记录可能丢canonical owner并回退辅助raw身份。
- 证据：后端91ce365f GET/Fork使用同一SubscribeShare schema，Web 7ea14bc9原对象直传；独立代理闭合TV出口。legacy`mediaid`与未知extra不在当前Share合同。
- 跨端结论：由未验证转确认P2；真实记录分布未验证，不影响静态合同确认。
- 最小修改方向 / 裁决：只补`anilistid/media_source/media_id`及CodingKeys/解码，供F-077投影复用；不保存raw payload。
- 修复状态：已完成（`58c7e81`）；官方GET数组解码到真实Fork请求体已有回归覆盖。

</details>

<details>
<summary>F-080 · P2 · 已确认 · SSE 未收到合法终止仍按普通成功收尾</summary>

- 审查单元与位置：M001-K→V011-C；Search/Resource/AI SSE 消费者
- 触发路径：HTTP 200 SSE 在 `done`、`error` 或 `enable == false` 前正常 EOF；或 ResourceResult 收到整体 error 且存在目标站点。
- 根因：三类消费者不持有“是否收到合法终止事件”的状态，循环自然结束和业务 error 会落入普通成功收尾。
- 用户影响：Search/ResourceResult 发布不完整或空结果；整体 error 仍可进入 missingSites 同步重试并遮住错误；AI 截断或 `done + data.success:false` 可清进行中状态并允许再次触发未确认完成的副作用。
- 证据：review_m001_k_retry 闭合 EOF、业务 error、missingSites 重试与 AI 进行中状态链；verify_m001_k 确认 AI；review_a001_h 独立确认 Search append+EOF/业务 error 仍发布
- 跨端结论：TV 生产与兼容测试终止语义冲突已确认；后端保证未验证
- 最小修改方向 / 裁决：共享最小终止分类；搜索无终止走既有 fallback，业务 error 不进 missing-site 重试，AI 未终止不得按成功清状态。

</details>

<details>
<summary>F-081 · P2 · 已确认 · 单条坏规则令整份配置失效并静默 fail-open</summary>

- 审查单元与位置：M001-K→S005/V015/W020-E；CustomRule数组/所选ID与坏identity fail-open
- 触发路径：规则数组任一未选中项缺 String `id/name`，或任一条件字段类型异常。
- 根因：`[CustomRule]` 原子解码；单项坏数据令整份配置失败，搜索调用者静默退化为未过滤结果，SystemViewModel 可保留旧规则列表。
- 用户影响：设置页仍显示旧的已选硬过滤规则，但实际资源搜索完全绕过硬/软过滤，仅输出控制台日志。
- 证据：既有链确认fail-open；W020-E第三裁决合并F-211缺ID与F-215坏identity，两票支持条件性P2；输入边界隔离坏项并校验规范非空唯一ID/name；已选缺失/歧义显式失败
- 跨端结论：条件性P2；真实异常规则与重复ID分布、长名布局未验证
- 最小修改方向 / 裁决：仅在配置输入边界隔离坏项并校验规范化后的 ID/name；用户明确接受已选规则缺失时继续静默不过滤，不新增错误 UI。
- 修复状态：已完成（`670cf86`）；完整身份矩阵、Simulator clean build与跳过真实后端兼容套件后的本地串行432/432测试及独立复审均通过。

</details>

<details>
<summary>F-083 · P2 · 已确认 · 下载动作解码混淆空 body 与不可解非空 body</summary>

- 审查单元与位置：A001-A→W017；下载动作 ActionResponse 解码
- 触发路径：暂停/恢复/删除返回仅 `message_i18n` 的失败对象，或非空但畸形的 HTTP 2xx body。
- 根因：首个 ActionResponse 全字段可选，普通对象已成功解码而本地化 ApiResponse 分支不可达；两次解码失败后又把零字节 body、畸形 JSON、null、数组和错类型都当 success。
- 用户影响：失败原因退化 Unknown；畸形响应可让 UI 错误翻转下载状态或移除仍存在任务。
- 证据：A001-A双审收窄fail-open分支；W017双审确认三个生产mutation直接信任结果且可移除仍存在任务；明确空body兼容单列；其他非空响应复用严格动作decoder失败关闭
- 跨端结论：TV fail-open已确认；空body正式契约未验证
- 最小修改方向 / 裁决：保留明确空 body 成功兼容；非空 body 用包含 `message_i18n` 的统一模型严格解码。

</details>

<details>
<summary>F-084 · P2 · 已确认 · 海报降尺寸会改写任意 URL 文本</summary>

- 审查单元与位置：A001-A→G06；海报 URL 降尺寸
- 触发路径：非 TMDB 海报 URL 的 host、path、query 或签名包含字符串 `original`。
- 根因：对完整 URL 全局执行 `original → w500`，而非只替换 TMDB `/t/p/original/` 路径段。
- 用户影响：插件/CDN/签名海报 URL 被改写并加载失败；后台和主线程构造路径都会触发。
- 证据：既有双审闭合两条生产路径；G06 两票核到当前上游允许第三方绝对海报URL且无TMDB路径段保证；只替换解析后精确 `/t/p/original/` 路径组件
- 跨端结论：TV稳定改写机制已确认；真实非TMDB命中频率未验证
- 最小修改方向 / 裁决：用单一共享 helper 基于 URL components 只改写精确 path 段 `/t/p/original/`，保留 host/query/fragment 原文。

</details>

<details>
<summary>F-085 · P2 · 已确认 · 规则预览、规范化与 matcher/后端失败语义分裂</summary>

- 审查单元与位置：M001-K→S005/V015/W020-F/H；CustomRule matcher/预览语义
- 触发路径：已选规则含 `seeders = " 5 "`、非法 include/exclude 正则、缺失/不可解析 pubdate、Web 提示允许的单值 size/范围 seeders，或其他空白/坏格式条件。
- 根因：模型注释、设置预览与 matcher 各自解释原始字符串，没有共享 canonical 解析/校验结果；各字段又混用 fail-open 与 fail-closed。
- 用户影响：硬过滤可能放过全部或清空全部资源，软过滤错误灰置；设置预览仍显示规则已配置。
- 证据：W020-H双审以当前TV/Web/backend闭合字段矩阵并将既有P3升级P2；先统一官方语法，再让预览与matcher消费同一canonical解析结果；非法值显式失败
- 跨端结论：条件性P2；真实规则分布、Rust路径与远端最新性未验证
- 最小修改方向 / 裁决：先确认目标后端版本，再让 matcher 与预览消费一次解析所得的 canonical rule；已选规则解析失败必须显式报告，不单方面按 Web 提示扩展 TV 语法。

</details>

<details>
<summary>F-087 · P2 · 已确认 · 空白首选错误字段遮蔽有效错误文本</summary>

- 审查单元与位置：A001-B/A001-C→V011-C→G02；APIService/Search 错误消息选择
- 触发路径：`message_i18n` 为全空白，而后续 `detail` 或 `message` 有有效文本。
- 根因：2xx `ApiResponse.localizedMessage` 与非 2xx selector 都在 trim 前选择首个“非空”字段，选中空白后才 trim，最终退化为状态码。
- 用户影响：用户只看到 HTTP 状态码，丢失可操作的服务端错误原因。
- 证据：既有API/Search双审与全新G02 clean-room复核确认各入口同根；逐项trim/filter后按现有优先级取首个有效文本
- 跨端结论：TV错误恢复信息缺口P2；真实payload频率未验证
- 最小修改方向 / 裁决：逐项 trim/filter 后再按本地化优先级选择首个有效文本。

</details>

<details>
<summary>F-088 · P2 · 已确认 · form/query 标量特殊字符未按目标解析规则编码</summary>

- 审查单元与位置：A001-B/C；V009-A/E 条件扩展；form/query 标量值编码
- 触发路径：用户名或密码含 `&`、`+`、`%`、空格等 form 特殊字符；或动态来源已有 `token=A%2BB`、筛选值为 `C++` 等字面加号。
- 根因：登录用 `URLComponents.query` 直接作为 form body；动态来源又把已有 percent-encoded query 解成 queryItems 后重序列化。两者都没有按最终 form-style decoder 语义保护标量值，字面 `+` 可被后端解释为空格。
- 用户影响：登录与自动重登稳定失败，甚至拆出额外表单参数；条件性动态来源可把 token/filter 值从 `+` 改为空格，导致鉴权或筛选失败。
- 证据：verify_a001_b/review_a001_c_retry2 确认登录 form；verify_a001_h 闭合动态 `%2B`/C++ query 链；review_a001_h 独立确认 query 机制但部署 fixture 未验证；V009-E 根因支持
- 跨端结论：TV 登录 P2 已确认；动态来源为条件性 P3传播
- 最小修改方向 / 裁决：使用同一个小型标量 percent-encoding 原语：登录构造 form-urlencoded body，动态来源在保留既有 `percentEncodedQuery` 的同时按 raw percent-encoded append 写入；覆盖特殊字符、非 ASCII 与 `%2B` 往返，不增加依赖。

</details>

<details>
<summary>F-089 · P2 · 已确认 · 登录拒绝被当成既有会话失效</summary>

- 审查单元与位置：A001-C→I016/G06；登录 401/403 错误分类
- 触发路径：登录端点用 401/403 表示凭据错误、禁用账号或其他登录拒绝，调用者采用默认 `preserveExistingSessionOnFailure:false`。
- 根因：获取凭据的 login 请求复用普通鉴权请求的“401/403 表示已有会话失效”分类；login 会先 logout 并抛 `.unauthorized`，服务端错误不经本地化错误选择。
- 用户影响：若后端使用 401/403，LoginView 会显示“登录已失效”而非真实凭据错误；System 手动刷新还可能清除既有会话。普通首次登录通常无旧会话，清理影响不能泛化。
- 证据：G06 两票核到当前后端凭据/MFA失败使用401并确认System默认不保留旧会话；403仍仅为条件分支；登录请求禁通用鉴权重放；401/MFA、403、网络失败与权威no-access分别裁决
- 跨端结论：当前401生产链已确认；login 403合同与真实刷新频率未验证
- 最小修改方向 / 裁决：登录端点禁用自动重登并直传服务端错误，旧会话是否清理由登录调用者显式裁决。

</details>

<details>
<summary>F-091 · P2 · 已确认 · 首次下载器列表失败后页面不再恢复</summary>

- 审查单元与位置：A001-E→W016/W017；下载器首次加载与轮询恢复
- 触发路径：页面首次 `fetchDownloadClients()` 遇到瞬时网络、鉴权或解码失败。
- 根因：失败后 `clients` 与 `selectedClient` 保持空；随后三秒循环只调用 `loadDownloads()`，而空客户端会立即返回，客户端列表不再重试。
- 用户影响：页面持续显示无下载器/无任务的假空状态，服务恢复后也不会自行恢复，必须离开并重新进入页面。
- 证据：A001-E双审闭合；W016/W017不同代理再次从页面/轮询与Web对照确认；失败时轮询复用initialLoad，成功空配置单独呈现
- 跨端结论：TV恢复缺口已确认；真实失败频率未验证
- 最小修改方向 / 裁决：在客户端为空且非已确认真实空列表时复用现有客户端加载入口，并区分错误与真实空态；不新增第二套轮询器。

</details>

<details>
<summary>F-092 · P2 · 已确认 · 下载动作完成后的 toggle 可反向覆盖轮询状态</summary>

- 审查单元与位置：A001-E→W017；下载动作与三秒轮询/快速重复
- 触发路径：暂停或恢复请求在途时，三秒轮询先发布服务器的新 `isDownloading` 状态，随后动作请求返回成功。
- 根因：动作成功后不是写目标状态，而是对当前对象执行 `isDownloading.toggle()`；当前值可能已被轮询改成正确服务端状态。
- 用户影响：本地按钮/图标被反向显示，直到下一次轮询才可能纠正；快速重复遥控操作、切换客户端或任务会放大错写窗口。
- 证据：A001-E双审闭合竞态；W017双审确认同一行可并发两次请求且错误状态可持续；单行串行、冻结目标状态，成功后赋目标值或刷新，禁止盲toggle
- 跨端结论：纯TV状态竞态已确认；真机连击频率未验证
- 最小修改方向 / 裁决：把动作绑定到不可变客户端、任务与目标状态，或让轮询成为状态唯一权威；请求期间阻止同一动作重复提交。

</details>

<details>
<summary>F-093 · P2 · 已确认 · 下载列表和动作错误全部静默</summary>

- 审查单元与位置：A001-E→W017；下载列表及动作错误/四态呈现
- 触发路径：下载器列表、任务轮询、暂停、恢复或删除任一路径失败。
- 根因：catch/失败响应仅直接 `print`，ViewModel 没有错误状态，也没有复用全局失败通知；View 只能观察列表和 loading。
- 用户影响：首次错误看起来像真实空列表，动作失败看起来像遥控器无响应，服务端消息被丢弃。
- 证据：A001-E双审闭合出口；W017双审确认页面无error/stale/retry且全部主动动作可无声失败；最小loading/empty/error/stale/data与可聚焦重试；主动动作复用现有错误通知
- 跨端结论：TV错误体验缺陷已确认；后端失败文案未验证
- 最小修改方向 / 裁决：复用现有 NotificationManager 或单一 VM 错误状态只报告失败，成功保持静默；同时经 Logger 取代直接 `print`。

</details>

<details>
<summary>F-094 · P2 · 已确认 · 空白下载 hash 可穿透到动作 URL</summary>

- 审查单元与位置：A001-E→G05；下载任务 hash 身份与动作路径
- 触发路径：任务 hash 为 nil、空字符串、全空白，或含 `/`、`?`、`#` 等 path delimiter，用户执行暂停、恢复或删除。
- 根因：模型接受全部形态且身份规则不一致，View 只检查 Optional，API 再把原字符串直接插入 URL path。
- 用户影响：nil 动作无反馈，空/空白请求错误路径，特殊字符会改变 path、query 或 fragment；同时与 F-024 的不稳定身份/碰撞风险相互放大。
- 证据：既有双审闭合 Optional gate/路径；G05两名代理确认当前后端仍允许optional hash且三个动作可接受空白值；与F-024共用规范化helper但保持独立：本项管动作可用性/路由，F-024管行身份/trap
- 跨端结论：TV 输入/路由边界已确认；异常hash分布与部署版本未验证
- 最小修改方向 / 裁决：在共享下载任务/动作边界要求 trim 后非空不可变 hash，并安全构造 path segment；若无可靠动作身份则禁用并显示失败原因。

</details>

<details>
<summary>F-096 · P2 · 已确认 · 可选入库状态探测可触发重登或登出</summary>

- 审查单元与位置：A001-G；媒体服务器可选入库状态探测
- 触发路径：订阅用户进入电影详情，best-effort `/mediaserver/exists` 返回 401/403。
- 根因：只用于徽章的辅助探测沿用 `makeRequest` 默认自动重登/登出，而同类 `/mediaserver/notexists` 已显式关闭两项破坏性副作用。
- 用户影响：可选“已入库”后缀探测即可用存储凭据重登、重放请求，或把仍可使用主功能的会话切回登录页。
- 证据：review_a001_g 闭合 best-effort 调用、makeRequest 默认参数与 `/notexists` 非破坏性对照；verify_a001_g 确认参数分裂与现有非破坏性探测规则
- 跨端结论：TV 会话副作用已确认；端点权限/状态码未验证
- 最小修改方向 / 裁决：仅在 `fetchMediaServerExists` 调用 `makeRequest` 时关闭自动重登与登出，错误继续降级为未知徽章状态。

</details>

<details>
<summary>F-097 · P2 · 已确认 · 媒体服务器轮询失败会清空旧卡片</summary>

- 审查单元与位置：A001-G→G03；首页媒体服务器轮询
- 触发路径：首页已有媒体服务器卡片，十秒轮询中某一服务器发生网络、HTTP、解码或取消错误。
- 根因：TaskGroup 的单服务器 catch 把失败转换成权威空数组，收集后再用新字典整体替换旧快照，无法区分成功空响应与失败。
- 用户影响：已展示卡片瞬间消失并显示“暂无最近内容”，当前焦点项被移除；恢复后焦点不保证回到原卡片。
- 证据：既有双审确认机制；G03两名纠偏/第三裁复核均按正确命题裁P2；仅成功结果覆盖对应服务器；失败保留旧值，成功空才清空
- 跨端结论：纯TV可逆数据误报P2；十秒自愈与真机焦点落点未验证
- 最小修改方向 / 裁决：轮询结果区分成功与失败；只有成功空响应清空，失败/取消保留该服务器上一快照，整批取消不发布。

</details>

<details>
<summary>F-099 · P2 · 已确认 · 手动媒体选择接受 0 且负值遮蔽有效 fallback</summary>

- 审查单元与位置：A001-F→G09；手动媒体选择正 ID 边界
- 触发路径：TMDB/Bangumi/AniList 搜索结果的原生数值 ID 为 0/负数，同时 `media_id` 有有效 fallback；或用户手工输入 0。
- 根因：`ManualMediaSelection.mediaId` 只检查非空并优先原生数值 ID，没有复用正数校验；手工 `isValidManualMediaId` 只校验 ASCII 数字并明确接受 `"0"`。0 遮蔽 fallback 后继续提交，负值遮蔽后又被表单校验拒绝。
- 用户影响：0 可进入整理预览、后台整理和共享选择器的添加下载请求；负值让本有有效 fallback 的结果不可提交。
- 证据：既有双审闭合 native-first 选择与ASCII数字校验；G09两名代理对照当前后端truthy语义确认0等同未提供；复用现有正整数helper并在无效原生值后尝试规范fallback
- 跨端结论：TV与当前后端数值身份边界冲突已确认；部署频率未验证
- 最小修改方向 / 裁决：数值来源先过滤 `> 0`，无效继续尝试规范化 fallback；手工输入使用来源感知校验，不全局改写 MediaInfo 身份语义。

</details>

<details>
<summary>F-103 · P2 · 已确认 · 资源标题与媒体 ID 由宽正则猜路由</summary>

- 审查单元与位置：A001-H→I012；资源标题与媒体ID意图
- 触发路径：标题以字母加冒号开头（如 `Re:Zero`），或媒体缺少 `apiMediaId` 但仍进入资源搜索。
- 根因：`ResourceSearchRequest.keyword` 同时承载标题和媒体 ID，消费端用 `^[a-zA-Z]+:` 猜意图；builder 对缺身份媒体可直接写空字符串。
- 用户影响：合法标题误走媒体 ID 端点，或发送空关键词；同步路径也可能偏离注释所述 Web 行为。
- 证据：既有双审确认路由猜测；I012提出fallback漂移，review_a001_j以现有标题测试第三裁升级P2；入口冻结title/media-ID intent，Search fallback只走title路径
- 跨端结论：TV稳定搜索语义漂移已确认；后端真实结果差异未验证
- 最小修改方向 / 裁决：builder 先保证非空 ID 或标题，并用最小显式路由意图区分二者，不从任意标题文本反推。

</details>

<details>
<summary>F-104 · P2 · 已确认 · 动态媒体或人物 ID 未编码为单一路径段</summary>

- 审查单元与位置：A001-I；`APIService.swift:1885,1897,1912,1938-1943`，A001-D Douban recommendations `1431`
- 触发路径：完整媒体键、人物 `raw_id` 或 Douban 辅助 ID 含 `/`、`?`、`#`、`%` 等保留字符。
- 根因：不透明 ID 直接插入 URL path；`buildEndpoint` 会把 `?/#` 解释成 query/fragment，`/` 会形成额外路径段，而相邻搜索入口已使用单路径段编码。
- 用户影响：详情预载、人物详情、人物作品、Douban 演员列表或推荐请求可能命中错误路由、丢失 ID 后缀或直接失败。
- 证据：review_a001_i 闭合保留字符经 URL 构造改写 path/query/fragment 与详情/人物调用链；review_a001_h 独立确认模型允许不透明 String、同文件已有整段编码惯例，并收窄相邻传播范围
- 跨端结论：TV 路径构造缺口已确认、严重度条件性；上游 ID 字符集及后端 percent-decoding 未验证
- 最小修改方向 / 裁决：在 API 边界复用现有路径段编码器分别编码动态 ID；来源白名单保持原样，不在调用者重复处理。

</details>

<details>
<summary>F-106 · P2 · 已确认 · 预计算图片 URL 固化旧配置</summary>

- 审查单元与位置：A001-K→I003/I016/G01；settings事务与预计算图片URL配置生命周期
- 触发路径：冷启动内容请求早于 `fetchSettings()` 完成；回前台刷新改变 `GLOBAL_IMAGE_CACHE` 或 `TMDB_IMAGE_DOMAIN` 后，同一会话页面继续持有旧模型。
- 根因：settings 初始 nil、图片缓存初始关闭；多数模型把构造时生成的 URL 保存为 `let imageURLs`，配置变化后没有 revision、失效或重算；`TmdbSeason` 的按访问计算形成对照。
- 用户影响：现有卡片可能继续绕过图片缓存、使用默认 TMDB 域或请求旧服务器图片代理，直到数据重载。
- 证据：I003双审确认P2；I016出现P1/P2分歧后，G01第三裁按无敏感设置消费边界最终维持P2；settings每阶段绑定epoch并传播取消；会话变化清旧共享配置，生产图片包装按访问消费获胜值
- 跨端结论：TV配置/session生命周期缺口已确认；等级已裁定P2
- 最小修改方向 / 裁决：复用现有季海报模式，让真实生产消费的包装在访问时从原始字段和当前配置计算；不新建图片 revision/重建框架，也不为无生产消费的 wrapper 扩机制。

</details>

<details>
<summary>F-109 · P2 · 已确认 · profile 作用域偏好与权威配置 owner 不完整</summary>

- 审查单元与位置：V002-A/B→W020-A/D/G06；profile偏好作用域与权威配置owner
- 触发路径：profile A 使用 baseURL `https://host/mp_a`、username `b`；profile B 使用 baseURL `https://host/mp`、username `a_b`，二者都生成 `defaultSearchSites_https://host/mp_a_b`。
- 根因：`userDefaultsKey` 用 `"<prefix>_<baseURL>_<username>"` 直接表示二元组，分隔符也允许出现在两个分量中，因此编码非一一对应。
- 用户影响：两个合法服务器/账号配置可相互读取或覆盖默认站点、默认媒体来源及硬/软过滤规则；站点/规则加载还可反向清空共享键。
- 证据：既有多审闭合碰撞与推荐合同；G06 两票确认key读取使用凭据用户名而非currentUser且baseURL未规范化；canonical baseURL+权威currentUser组成版本化tuple；异步操作冻结同一key
- 跨端结论：跨profile污染机制已确认；真实多profile频率与远端最新性未验证
- 最小修改方向 / 裁决：共享 key builder 使用带版本、无歧义的 tuple，四个prefix一次迁移；推荐配置直接复用服务端当前用户合同，本地fallback也绑定规范profile。不要同时维护app-global与服务端两套权威值。

</details>

<details>
<summary>F-110 · P2 · 已确认 · 默认排序选择升序仍固定降序</summary>

- 审查单元与位置：S005→C018-B/W011→G05；`TorrentsResultView.swift:267,283-285,329-343,374-395`
- 触发路径：排序字段保持“默认”，用户把方向切换为“升序”。
- 根因：菜单始终暴露 `SortType` 且箭头显示升序，但 default 比较器固定执行 `pri_order >`，忽略 `isAsc`。
- 用户影响：界面显示升序，列表仍按高优先级降序。
- 证据：既有多审确认；G05主审与独立复核均再次闭合可选asc与固定desc的稳定反例并支持P2；比较器遵循方向，或隐藏默认字段方向控件；不与F-061合并
- 跨端结论：纯TV内部控制/比较器契约冲突
- 最小修改方向 / 裁决：默认比较器遵循方向；若产品规定默认只能降序，则在该字段隐藏方向选择，不新增排序抽象。

</details>

<details>
<summary>F-111 · P2 · 已确认 · token-only 会话把不同账号降成同一偏好身份</summary>

- 审查单元与位置：V002-A/B→W020-A/C→I016；token-only profile与连接身份
- 触发路径：同一服务器先后使用两个合法 token-only 账号，二者都没有保存的登录用户名；或 token-only 账号与真实用户名 `default` 共存。
- 根因：profile key 忽略已恢复的 `currentUser.user_name`，只读取保存的用户名；缺失时把所有账号统一降成字面量 `default`。
- 用户影响：即使改用无歧义 tuple 编码，两个被降级为同一用户名分量的账号仍会共享默认站点、默认来源及硬/软规则选择。
- 证据：既有双审确认机制；I016两代理以受支持token-only双账号隔离链确认升P2；profile与显示统一使用当前权威会话身份
- 跨端结论：纯TV身份缺陷；真实token-only多账号频率未验证
- 最小修改方向 / 裁决：profile 用户分量取当前权威会话身份；身份尚未恢复时延迟读取或使用已验证快照，不建立新 profile 仓库。

</details>

<details>
<summary>F-112 · P2 · 已确认 · 站点成功空不清旧选择且失败与空态不可区分</summary>

- 审查单元与位置：V002-C/D→W020-A/D→I016；站点权威空/失败/加载状态
- 触发路径：已保存默认站点 `{1}` 后，当前 profile 的 `/site/rss` 权威成功返回空数组；或首次/后续站点加载失败。
- 根因：本地归一化在 `availableSites.isEmpty` 时把空数组同时解释为“尚未加载/失败”，直接保留旧选择；ViewModel 又没有错误状态，因此成功空、失败与未加载共享同一表示。
- 用户影响：设置页可同时显示“1 个站点”和“暂无站点”，搜索仍把已失效 ID 发给后端；失败则伪装为空数据或继续把旧列表当当前数据。
- 证据：既有双审确认机制；I016两代理闭合成功空→旧ID请求链并升P2；成功空清选择，失败/取消与空分开并提供最小重试
- 跨端结论：纯TV状态缺陷；真实空站点频率未验证
- 最小修改方向 / 裁决：只有成功响应才按返回 ID 集合归一化，集合为空也清除旧选择；失败/取消与成功空分开，复用现有状态行提供最小错误和重试，不新建通用加载框架。

</details>

<details>
<summary>F-113 · P2 · 已确认 · 默认站点异步归一化跨 profile 写回或返回旧值</summary>

- 审查单元与位置：V002-D；`SystemViewModel.swift:385-400,444-450` 及资源搜索调用者
- 触发路径：profile A 读取默认站点并发起 `/site/rss`，网络等待期间切换到 B；A 随后成功、失败或取消。
- 根因：函数在 await 前只读取 A 的值/权限，请求后写回 helper 动态重算当前 B 的 key；通配 catch 又把失败、取消和未来 stale-session 错误都降成 A 的 storedSites。
- 用户影响：普通 200 可覆写/移除 B 的默认站点；成功或 catch 返回的 A 站点还可能进入仍存活的 Home/菜单导航，并由 B 会话发起资源搜索。持久写回不依赖旧导航是否存活。
- 证据：review_a001_h 闭合 A 读取→await→动态 B key 写回、catch 回退 A 与 B 会话请求传播；review_a001_j 独立确认成功/错误/取消/撤权、三个调用者与条件性 P2 严重度边界
- 跨端结论：纯 TV 会话归属缺陷已确认、严重度条件性；旧导航可见性与真实频率未运行验证
- 最小修改方向 / 裁决：复用现有 session snapshot，同时冻结发起时精确 profile key；成功、失败、取消在写回/返回前统一校验会话与权限，过期结果显式中止并让调用者停止导航，不把它映射为表示“全部站点”的 nil/空集。

</details>

<details>
<summary>F-115 · P2 · 已确认 · 详情 ready 判定与阶段屏障阻塞主流程</summary>

- 审查单元与位置：V004-A→I005；MediaPreloader详情ready与阶段屏障
- 触发路径：详情响应含空串/纯空白标题、空白 Douban ID 或非正 TMDB ID；反向路径为 title/tmdb/douban 全 nil 但 Bangumi、AniList 或插件身份有效。
- 根因：ready 只检查 `title/tmdb_id/douban_id != nil`，既不规范化值，也没有覆盖项目已支持的其他媒体身份。
- 用户影响：无效详情可提前解除遮罩并显示空标题/Unknown，图片与后续动作继续消费坏身份；某些替代身份详情反而被重试后判失败。
- 证据：V004双审闭合身份值域；I005集成与不同代理复核闭合`detail response→season`关键路径并升级P2；规范ready值；详情响应发布即启动season，图片/识别仅约束真实依赖者
- 跨端结论：TV详情ready/主流程阶段屏障已确认；真实延迟分布未验证
- 最小修改方向 / 裁决：增加一个私有纯判定，复用现有 normalizedString 与正数 ID 语义并覆盖已支持身份；不引入验证框架。

</details>

<details>
<summary>F-116 · P2 · 已确认 · 预加载命中时背景安装晚于遮罩解除</summary>

- 审查单元与位置：V004-A→V012-A→I013→G03；热缓存首帧内容与背景安装顺序
- 触发路径：详情从 MediaPreloader 缓存命中，Container 记录 `wasPreloaded = true`。
- 根因：`wasPreloaded`只凭主详情ready令容器立即可见，整体绕过`isContentReady`；背景URL初始仍为nil，actors/recommend/similar首行也要等待视图`.task`应用详情后才就绪。
- 用户影响：静态存在内容已显示而背景仍灰、辅助首行未安装的窗口；随后同步apply通常会自愈，是否形成可见闪烁或焦点回归尚无运行证据。
- 证据：G03两名纠偏复核按正确命题独立闭合热缓存Container→VM init→View task顺序，覆盖I013原运行未验证边界并升级P2；VM初始化同步安装已有full detail/background；不改F-115网络阶段图
- 跨端结论：纯TV首帧状态分裂已确认；实际闪烁时长/焦点影响未运行验证
- 最小修改方向 / 裁决：在 `MediaDetailViewModel` 初始化时同步安装传入 full detail 的背景，不走动画；复用单一URL解析逻辑，不改F-115的网络阶段图。

</details>

<details>
<summary>F-118 · P2 · 已确认 · pin 无 owner 且非 pop 的 onDisappear 也解除保护</summary>

- 审查单元与位置：V004-B→V012-A→G03；MediaPreloader pin owner与详情返回栈
- 触发路径：同 key 有多个详情 owner，或父详情 push 推荐/类似子详情、切 Tab 等使容器 `onDisappear`，随后有订阅通知或超过 30 个焦点预加载。
- 根因：`pinnedKeys` 是布尔 Set，无 owner/refcount；通用 onDisappear 不等于导航条目终止。返回只重新 pin key，不验证 manager cache 仍注册当前 View 的 `@State` task。
- 用户影响：静态可证明 pin 会提前失效；通知刷新可能先漏掉该 task，LRU 压力下还可能移除/取消。SwiftUI State/生命周期及真实可见后果未运行确认。
- 证据：G03两名不同复核确认ownerless语义、唯一生产调用与淘汰/刷新链；tvOS push/返回表现保留运行边界；复用稳定owner token/lease，最后owner释放才可淘汰；不建缓存框架
- 跨端结论：静态owner缺陷P2已确认；push onDisappear、30+ churn与返回卡死未运行验证
- 最小修改方向 / 裁决：pin 使用稳定 owner token/lease（或等价最小refcount）且同 owner 幂等，只在实际导航条目结束时释放；返回时校验 View task 与 manager 注册项一致，不新建缓存框架。

</details>

<details>
<summary>F-119 · P2 · 已确认 · canonical media alias 只回写任意一个缓存任务</summary>

- 审查单元与位置：V004-B→V012-B→G02；MediaPreloader cache aliases 与订阅回写
- 触发路径：cache 同时持有两个 `MediaInfo.id` 不同、但 `apiMediaId` 相同的富/简字段媒体对象，随后保存或取消该媒体订阅。
- 根因：cache 用 Web/UI 多字段去重键存储，`findTask(byMediaId:)` 却在 `Dictionary.values.first` 只返回一个 canonical alias；通知刷新又只覆盖 pinned 项。
- 用户影响：直接回写只更新一个 task，非 pinned alias 的右键菜单“订阅/已订阅”标签可陈旧；点击仍查询后端，不能夸大为必然错误 mutation。
- 证据：既有双审确认机制；G02两名不同复核确认fullDetail/非TMDB alias缺口并升级P2；线性扫描小缓存并更新全部已知canonical alias；不建alias registry
- 跨端结论：条件性TV状态错误P2；真实alias并存频率未验证
- 最小修改方向 / 裁决：保留现有 cache key，线性扫描当前小缓存并按精确 apiMediaId 或已识别 TMDB fallback 更新全部 alias；缓存通常受 30 项软上限约束但可超限，不重键、不加索引或缓存层。

</details>

<details>
<summary>F-121 · P2 · 已确认 · Fork 错误跨分享目标残留</summary>

- 审查单元与位置：V006→W015→G02；`SubscriptionHandler.forkErrorMessage` 与分享 Sheet 呈现链
- 触发路径：目标 A 的 Fork 失败后关闭 Sheet，在没有实际开始新 Fork 前打开目标 B 的分享 Sheet；或 A 的未结构化任务在 B 呈现后晚到。
- 根因：错误只在真正开始 Fork 时清除，既不随新分享 presentation 清空，也不绑定请求/目标 generation。
- 用户影响：B 的分享界面可立即显示 A 的错误；若旧任务晚到，错误还可能覆盖当前目标状态。
- 证据：既有多轮裁决闭合同步链；全新G02 clean-room复核确认operation owner缺口并升级P2；错误绑定operationID/shareID，新presentation清旧且拒绝迟到发布
- 跨端结论：TV跨目标错误归属P2；迟到调度频率未验证
- 最小修改方向 / 裁决：新目标 presentation 建立时清除旧错误，并用同一个小型 presentation/request revision 拒绝旧任务发布；不建立通用错误状态框架。

</details>

<details>
<summary>F-123 · P2 · 已确认 · 高层 TMDB action 未绑定发起会话</summary>

- 审查单元与位置：V005；高层 TMDB action、两阶段识别、默认站点与最终导航链
- 触发路径：profile A 发起 `/media/search` 并等待，期间切到 B；A 响应无匹配后，同一高层动作继续以当前 B baseURL/token 发起 `/media/recognize`，但载荷仍是 A 的标题。
- 根因：单个请求的 session snapshot 没有覆盖由按钮到多次 await、默认站点读取、全局状态写入和最终导航的整个用户动作；Handler 又跨登录根以 `StateObject` 存活。
- 用户影响：B 的凭据可被用于发送 A 发起的查询，达到条件性 P2；旧 spinner/alert/poster 残留按 P3，旧导航实际可见性未运行确认。
- 证据：review_a001_j 闭合 A search 等待→切 B→B recognize 的确定链及全局状态传播；review_a001_h 独立确认正常 A 空响应后 B 新请求链、与 F-027/F-113 的修复边界及 ResourceResult 快照过晚
- 跨端结论：条件性跨 profile P2 已确认；旧导航/海报可见性未运行验证
- 最小修改方向 / 裁决：由 CHK-005 统一提供/引入单调 session epoch，在按钮动作起点捕获它并加局部 action revision/owner；每次后续请求、权限判断、全局状态及 callback 前复核，过期显式中止；owner-aware defer 不得让旧任务关闭新 spinner。不新建动作框架。当前仓库只有结构快照，不能写成已有可复用 epoch。

</details>

<details>
<summary>F-126 · P2 · 已确认 · 加载失败或取消与成功空/旧快照终态混淆</summary>

- 审查单元与位置：V008→W013-A/W020-A/E/F→G02；多owner加载失败/取消与成功空或旧快照终态
- 触发路径：冷启动的媒体配置或订阅请求失败，或已有订阅快照后的周期刷新失败。
- 根因：错误只 catch/print，Home 没有对应的 failed/stale 状态；冷启动最终与成功空共用“暂无内容”，热订阅失败继续显示旧数组但无 stale/error/retry 标记，`hasLoaded` 又在请求前置 true，使失败/取消后的重新出现不能立即重试。
- 用户影响：用户无法区分“确实没有内容”与“加载失败”，也不知道旧订阅快照是否已过期；周期错误若改成全局 toast 还会违反 H-012 的 error-episode 去重边界。
- 证据：既有多审确认总根；G02两名不同复核要求按五条子链验收并维持总体P2，驳回“Home永久锁死”扩大；各owner分别保留最小success-empty/error/cancel/stale与现有retry；不建统一状态机
- 跨端结论：条件性P2；System部分恢复UI与真实失败时序未运行验证
- 最小修改方向 / 裁决：复用现有 loading，媒体区和订阅区各自保留最少 `hasSnapshot/loadFailed` 状态，不能用一个全局错误 Bool 混淆两块内容；成功空是有效快照，失败保留旧值并标 stale，取消不报失败，恢复成功立即清错。不引入通用加载状态框架。

</details>

<details>
<summary>F-129 · P2 · 已确认 · Popular 去重键与实际列表 ID 不一致</summary>

- 审查单元与位置：V009-B→V009-E/F→G01/G04；Explore Popular 去重 key 与 `MediaInfo.id`
- 触发路径：Popular 返回两条没有有效结构身份的媒体，例如 `tmdb_id=0`、其余身份相同但 title 分别为 A/B；或同一坏身份项跨页改名。
- 根因：自定义去重键跳过非正身份后回退到 title，因此把 A/B 当不同项；实际 `MediaInfo.id` 不含 title，两项最终拥有相同 `Identifiable.ID`。
- 用户影响：Paginator 会同时追加两个相同 SwiftUI ID 的卡片；焦点/预加载身份含糊，第二项的 `firstIndex` 可命中第一项并延迟或停止 loadMore。
- 证据：既有双审确认；G01纠偏与G04独立复核再次闭合A/B反例并双票升P2；与F-138共用中央identity修复但保留Popular回归
- 跨端结论：条件性TV列表身份缺陷；真实Popular坏身份频率未验证
- 最小修改方向 / 裁决：只把 `popularSubscriptionKey` 的“无有效结构身份”fallback 改为 `item.id`，不再用可变 title；保留现有 AniList 主身份+season 行为，不新增 ID 类型或索引。

</details>

<details>
<summary>F-131 · P2 · 已确认 · 非公历当前年被当成发现 API 年份</summary>

- 审查单元与位置：V009-D/E→G05；Douban/Bangumi/AniList 动态年份集合
- 触发路径：设备 `Calendar.current` 为 Buddhist 或 Japanese 等非 Gregorian，用户打开或选择年份筛选。
- 根因：三处直接用当前日历的 `.year` 生成 canonical API 年份，没有固定公历；显示值、Picker tag 与请求值共用该数字。
- 用户影响：公历 2026 在 Buddhist 下变成 2569并直传 `tags/year/season_year`；Japanese 下从 8 递减，Bangumi/AniList 还生成 0/负数。AniList 的动态 key 0 与 View 的“全部”.tag(0) 重复，显示“年份：0”却等同不发参数。
- 证据：既有三票闭合Picker→query；G05主审与独立复核均确认三条发现API稳定直传非公历年并支持P2；直接固定Gregorian calendar，不引入日期provider
- 跨端结论：条件性 TV locale/API 缺陷已确认；非公历实际配置未运行验证
- 最小修改方向 / 裁决：三处直接用 `Calendar(identifier: .gregorian)` 取得当前年；不引入日期 provider、筛选 schema 或新抽象。

</details>

<details>
<summary>F-137 · P2 · 已确认 · 模糊匹配长度罚分让不匹配项反超真实匹配</summary>

- 审查单元与位置：V011-A/B→G04；`fuzzyMatchScore` 类别带与 top-12
- 触发路径：查询 `ab`；真实候选标题为 `a`+50 个其他字符+`b`，无关候选标题为 `zz`，两者海报、popularity 与合法唯一身份相同；另有足量无关候选竞争 top-12。
- 根因：前缀、包含和顺序匹配均直接减去无上限的标题长度，类别分数带可被穿透；52 字符顺序匹配得到 `-2`，反而低于不匹配的 `-1`。
- 用户影响：真实匹配可排在无关结果之后；存在12个以上竞争候选时还会从“最佳结果”完全消失，属于明确搜索功能错误P2。
- 证据：既有三票闭合反例；全新G04 clean-room复核确认四类交叉与最终截断并升级P2；保持Int评分，仅为类别设置互不重叠带宽并clamp长度惩罚
- 跨端结论：条件性搜索结果缺失P2；真实长标题竞争频率未验证
- 最小修改方向 / 裁决：若独立复核确认，只给现有三类分数设置互不重叠的下限，例如前缀不低于 100、包含不低于 50、顺序不低于 0；不新建评分框架。

</details>

<details>
<summary>F-139 · P2 · 已确认 · 推荐成功空 shelf 无恢复入口</summary>

- 审查单元与位置：V010→V012-A→G01/G04；推荐/详情分页成功空终态与页面再激活
- 触发路径：当前 shelf 首次请求成功返回 `[]`，Paginator 与页面实例被 Tab 保留；稍后服务已有数据或空响应只是瞬时结果，用户离开并再次激活推荐 Tab但不切换 shelf。
- 根因：Paginator 对成功空正确进入 `hasMore=false`、`hasError=false` 的终态；推荐页激活只重载配置/来源，当前 shelf 的同一 Paginator 不刷新。
- 用户影响：空推荐页会一直保持到切换 shelf 或重建页面，且没有错误态/重试提示说明恢复方式。
- 证据：既有双审确认；G01纠偏与G04独立复核再次闭合retained激活链并双票升P2；仅在激活边沿对成功空terminal调用现有refresh
- 跨端结论：条件性恢复P2；真实tvOS实例保留与发生频率未运行验证
- 最小修改方向 / 裁决：复用仓内 `SystemView(isSelected:)` 的激活边沿模式，只在 false→true 且当前同 shelf 满足 `items.isEmpty && !isLoading && !hasError && !hasMore` 时调用现有 `Paginator.refresh()` 一次；非空、错误、加载中与切 shelf 不触发，不改 Paginator。

</details>

<details>
<summary>F-142 · P2 · 已确认 · 完成的共享搜索 task 未及时退休导致非终止空批</summary>

- 审查单元与位置：V011-F 复核/裁决；`SharedMediaFetcher.currentFetchTask` 合流/退休
- 触发路径：电影 waiter 创建页 1-2 的共享 task，电视剧 waiter 合流；页 1-2 只有电影、页 3 才有电视剧，且电视剧 continuation 在 task 已完成但创建者尚未取得 actor并执行外层 defer清理时先恢复。
- 根因：共享 task 只由创建者在 `await task.value` 返回后的调用者 `defer` 清空。另一 waiter 可看到“已完成但仍非 nil”的 handle，下一轮再次 await 同一已完成 task，API游标不推进，命中 `apiPage == pageBefore` 后 break并返回空 TV buffer。
- 用户影响：电视剧 Paginator 把内部 `hasMore == true` 时的空批当成永久终页，第3页及后续真实结果消失；普通重新搜索可恢复，但当前结果页已截断，故为条件性 P2。
- 证据：review_a001_j 闭合双 waiter恢复顺序与第3页目标类型反例；review_a001_h 独立状态机确认0→2后重放2→2、actor调度可达及F-034/F-039独立
- 跨端结论：条件性搜索截断已确认；真实调度频率未验证
- 最小修改方向 / 裁决：仍使用现有 actor和单一 Task，让实际共享任务的完成所有者在唤醒 waiter 前按 task identity 原子退休 handle；不增加协调器、owner/refcount或任务框架。

</details>

<details>
<summary>F-143 · P2 · 已确认 · 人物 route identity 未准入且展示身份与请求 owner 不统一</summary>

- 审查单元与位置：V013→G07；Person route准入与请求owner
- 触发路径：媒体详情的内嵌导演带raw ID但没有source，TV仍生成可点击卡片并进入人物页。
- 根因：当前后端对TMDB/Douban/Bangumi内嵌人物保留原始数组而不注入source；TV人物API又要求source并在网络请求前失败。当前演员卡来自独立`/credits`，该链会注入source，不能把演员一并夸大。
- 用户影响：导演详情稳定成为无请求的死页；当前Web的TMDB导演链接同样漏source，是共享上游route合同缺口。
- 证据：既有双审闭合无身份死页；G07三方以当前TV/Web/后端窄化为内嵌导演路径；后端人物生产边界补真实source；TV只可用父source兼容旧载荷，无法确认则禁用
- 跨端结论：TV及共享Web导演route缺口已确认；混合元数据来源未验证
- 最小修改方向 / 裁决：优先在后端各人物生产边界补真实source并让Web导演route传递；TV仅可用`person.source ?? fullDetail.source`兼容旧载荷，无法确认来源时禁用点击，不建人物框架。
- 修复状态：已完成（`40adb42`、`d2972b3`）。媒体详情内嵌职员缺失 `source` 时按父媒体来源投影，并兼容 AniList 内嵌 `avatar.large`；保留卡片交互，不通过禁用卡片掩盖空详情。
- 验证：补充人物来源/头像、AniList 演员与推荐 endpoint、TMDB 识别 source 固定回归；tvOS Simulator clean build 与串行本地测试 525 项通过、16 项跳过。真实后端用例因缺少 `.env.compatibility` 跳过。

</details>

<details>
<summary>F-144 · P2 · 已确认 · 多阶段首载吞取消后仍晚启动下一阶段</summary>

- 审查单元与位置：V013→W020-A→G02；串行首载与吞取消后晚启动下一阶段
- 触发路径：人物详情请求慢、超时或取消时进入人物页。
- 根因：`_ = await (loadDetails(), paginator.refresh())`没有创建Task或`async let`，两个async调用按表达式求值顺序执行；注释声称并行但作品刷新只能等详情完成。`loadDetails`又吞掉取消，页面任务取消后仍可能继续启动第二个请求。
- 用户影响：串行只会把总等待从并发的`max`退化为相加；P2的确定后果来自页面任务取消后仍晚启动本应停止的站点、分季或fallback请求。
- 证据：既有多审确认串行/晚启动；G02两名不同复核闭合取消后fallback确定请求并升级P2；复用async let；各catch先传播CancellationError并在fallback前检查取消
- 跨端结论：纯TV取消语义P2；真实慢请求频率未验证
- 最小修改方向 / 裁决：各catch先传播`CancellationError`，阶段之间检查取消；只有确认两项独立且产品需要降低首载延迟时才复用`async let`，不把并行化作为关闭取消缺陷的必要条件。

</details>

<details>
<summary>F-145 · P2 · 已确认 · 下载器选择无法恢复初始省略状态</summary>

- 审查单元与位置：V016→G05；AddDownload 下载器 Picker 与 Optional 请求字段
- 触发路径：打开添加下载Sheet时保留初始nil，随后选择任一下载器，又希望改回后端默认后提交。
- 根因：初始nil和Optional请求字段允许省略`downloader`，Binding也能把空字符串转回nil，但下载器options只有名称、没有空tag；共享SheetPicker只能选择options中的值。
- 用户影响：用户只能取消并重新打开Sheet才能撤回选择，当前表单内无法恢复最初的后端默认语义；不导致数据丢失，但会稳定改变最终请求owner选择。
- 证据：既有双审确认；G05主审与独立复核均闭合nil→选择→无法回nil、请求省略语义及仓内“自动”空项反证；在现有options前置“自动”空tag，复用Binding；不与F-168合并
- 跨端结论：TV表单可逆性缺陷已确认；具体默认文案未验证
- 最小修改方向 / 裁决：复用现有机制做局部收敛；具体边界以发现台账为准。

</details>

<details>
<summary>F-150 · P2 · 已确认 · manage-only 被展示三张 superuser-only 假空卡</summary>

- 审查单元与位置：V019→W016；manage-only状态页的superuser卡片可见性
- 触发路径：用户有`manage`但不是`super_user`，进入合法可见的状态页。
- 根因：Tab准入与VM正确区分manage/superuser并有意不请求Dashboard，但View忽略这个已知权限原因，把三项nil固定解释为“暂无媒体库统计/存储空间/下载器信息”。
- 用户影响：页面上半部稳定误导为服务器没有数据；不能隐藏整个Tab，因为下半部DownloadTask和TransferHistory对manage-only合法可用。
- 证据：V019双审闭合可达链；W016双审确认合法角色每次稳定看到三块系统性伪空态；复用canRequestSuperUserEndpoints隐藏三卡或显示一次权限说明，并保留下半页功能
- 跨端结论：跨端页面设计未验证
- 最小修改方向 / 裁决：直接复用现有`canRequestSuperUserEndpoints`，非superuser时隐藏三张Dashboard卡或显示一次明确权限说明；保留下载和转移区域，不新增权限模型。

</details>

<details>
<summary>F-155 · P2 · 已确认 · 第 6 页已请求却被轮询扫描上限丢弃</summary>

- 审查单元与位置：V022-C→I009；TransferHistory轮询多页扫描上限
- 触发路径：距离当前首个已知记录有101条以上新记录。
- 根因：第5个满页仍未遇已知项时，代码先把currentPage增至6并请求page6；响应写入临时值后，下一轮在循环顶端因`currentPage <= 5`为假退出，page6完全未处理，却仍提交前100条并推进Paginator。
- 用户影响：page1…5插入N1…N100，page6中的N101被丢弃，Paginator从page2推进到page7；下一轮page1首项N1已知即停止，loadMore又从page7开始，N101永久缺失。page6错误还会让前五页成功结果一并被catch丢弃。
- 证据：既有双审闭合页6丢弃；I009主审/独立复核确认前100项提交后下一轮无法恢复；扫描未找到已知边界时不提交前缀/推进游标，回退现有refresh
- 跨端结论：TV历史漏记录已确认；一次101+新增频率未验证
- 最小修改方向 / 裁决：扫描达到上限但尚未找到已知边界时不得提交不完整前缀或推进游标；优先回退复用现有Paginator顺序refresh/reset路径，单纯“不请求page6”不足以修复漏项。

</details>

<details>
<summary>F-157 · P2 · 已确认 · settings 失败被永久记作版本检查完成</summary>

- 审查单元与位置：V023→W020-A/W020-C/G06；settings加载与后端版本检查终态
- 触发路径：会话K冷启动`/system/global`瞬时失败或任务取消；网络恢复后应用进前台并成功加载settings。
- 根因：catch仍写`backendVersionCheckKey=K`并发布“无法确认后端版本”；前台刷新固定`checkBackendVersion=false`，成功只更新共享settings不清检查结论，同K后续true检查又被已检查guard挡掉。
- 用户影响：一次临时传输错误被不可逆地当作兼容性检查结论并展示“严重功能异常或数据丢失”警告；即使用户关闭弹窗，内部错误终态仍不收敛。
- 证据：既有多审闭合不可恢复状态机；G06 两票确认首次瞬时失败后前台固定不重判且无显式retry；只有有效版本/明确不兼容才写terminal key；unknown/failure保持可重试
- 跨端结论：稳定错误终态已确认；真实启动瞬时失败频率未验证
- 最小修改方向 / 裁决：transport失败/取消不标记成功检查，取消直接退出；前台成功在当前session key下复用既有版本判定并清旧警告。若保留失败提示，只做per-key失败episode去重，不建状态框架。

</details>

<details>
<summary>F-158 · P2 · 已确认 · 状态页生成无操作焦点目标</summary>

- 审查单元与位置：C001→W009/W011/W018-B/W019→G05；无操作焦点目标
- 触发路径：任一生产页面显示无action EmptyDataView；或人物详情进入加载、永久无简介、空作品状态。
- 根因：EmptyDataView固定插入透明1pt focusable节点；人物页又用`Button(action: {})`和单独focusable Text维持焦点。它们都把没有动作的状态伪装成可聚焦/可选择目标，没有真实激活结果。
- 用户影响：焦点或VoiceOver可命中无动作节点；透明节点表现为焦点消失，人物伪Button则表现为可按但无响应。加载态短暂是反证，永久无简介/空作品会稳定保留该语义。
- 证据：既有多审确认；G05两名代理将P2锚定在DownloadTask主行稳定可按但无动作，其他透明sink的实际落焦仍属运行边界；有主动作放入原生Button action；无主动作删除空Button/focus sink
- 跨端结论：Download主行静态P2；其他Focus Engine/VoiceOver命中频率未验证
- 最小修改方向 / 裁决：删除无action `else`节点；人物加载用非交互skeleton/ProgressView，无简介用静态状态文本，把默认焦点交给可操作简介或首个作品；确需重试的caller复用现有Button/action，不建focus或空态框架。

</details>

<details>
<summary>F-160 · P2 · 已确认 · ActionRow 空 Button 与 raw 手势语义分裂</summary>

- 审查单元与位置：C003→G10；ActionRow主Button与实际手势语义
- 触发路径：Download主行未传tap/longPress，或VoiceOver用户激活/长按Transfer主行。
- 根因：主控件原生Button action为空，真实选择和详情只挂两个simultaneousGesture；选择态只换图标，没有selected trait/value或命名详情动作，两手势也无显式互斥。
- 用户影响：Transfer的核心选择没有进入语义Button默认action，辅助功能激活可表现为“按下成功但未选择”；Download无主动作行仅为P3伪按钮传播。
- 证据：既有双审确认结构；G10主审/独立复核区分核心Transfer操作与无主动作Download行并确认P2；有tap时直接放入Button action并删重复TapGesture；无主操作改非Button
- 跨端结论：静态控制语义缺陷已确认；真实VoiceOver路由仍待运行
- 最小修改方向 / 裁决：有tap时直接用原生Button action；无主操作时用原生可聚焦内容；长按保留单一原生手势并补命名accessibilityAction与选择语义，不建交互框架。

</details>

<details>
<summary>F-161 · P2 · 已确认 · 透明隐藏 action 未退出 focus/accessibility 树</summary>

- 审查单元与位置：C003→W020-B/G09；非活动UI的focus/accessibility门禁
- 触发路径：焦点位于上一行右侧action列后向下移动，或VoiceOver遍历非活动行。
- 根因：所有右侧原生Button始终构建、布局并绑定focus，非活动行只对容器设opacity(0)，没有disabled或accessibilityHidden门禁。
- 用户影响：焦点或VoiceOver可能命中不可见按钮并触发突跳/不可见激活；也可能先命中后立即令行active并正常揭示，因此不能仅凭静态结构确认。
- 证据：既有双审确认静态结构；G09两名代理均评P2，其中一票保留Focus Engine条件边界；非活动时用原生disabled/hit-testing/accessibility门禁或按active构建；验证转换
- 跨端结论：静态控制树缺陷已确认；真实落焦/VoiceOver频率未验证
- 最小修改方向 / 裁决：非活动行对现有action容器原生disabled，必要时同步accessibilityHidden；主内容聚焦激活后再开放，不自建focus路由。

</details>

<details>
<summary>F-162 · P2 · 已确认 · Sheet 长错误被强制压成一行</summary>

- 审查单元与位置：C004→W018-B/W020-C/G09；Sheet与System静态行长反馈完整性
- 触发路径：后端返回较长错误，或Reorganize一次操作产生多项失败并以`；`拼接。
- 根因：共享反馈同时使用`lineLimit(1)`与`minimumScaleFactor(0.75)`，内容只会缩小后截断，无法纵向展开。
- 用户影响：用户看不全失败对象和原因，批量整理时尤其无法区分哪些项目需要处理；机制由字符串长度确定，真实长消息频率仍未验证。
- 证据：既有多段双审闭合；G09两名代理确认当前失败原因/路径稳定被限行且无展开；删除共享限制；允许完整换行并纳入现有ScrollView
- 跨端结论：条件性诊断信息不可达已确认；真实长文本频率未验证
- 最小修改方向 / 裁决：删除两项限制并允许纵向换行；只有布局仍不扩展时再加`fixedSize(horizontal:false, vertical:true)`，不改回全局通知。

</details>

<details>
<summary>F-165 · P2 · 已确认 · 部分 Sheet 缺少明显的内容内退出方式</summary>

- 审查单元与位置：C004→W018-B/W019/W020-C/G09；Sheet内容内显式退出可发现性
- 触发路径：用户进入Fork但不想创建订阅，或打开整理预览后只想退出。
- 根因：Fork内容只有会触发mutation的主按钮，预览没有dismiss按钮；没有HIG要求的明显内容内退出方式。
- 用户影响：普通遥控器Back/系统escape通常仍可退出，但用户在主内容中找不到可发现的安全取消/关闭控件；不声称形成focus trap或无法退出。
- 证据：既有多段双审确认；G09两名代理从Manual/Preview/Transfer detail与辅助功能语义共同支持P2；各Sheet复用原生取消/关闭并更新反向源码测试
- 跨端结论：不声称focus trap；系统Back、VoiceOver escape实际表现未验证
- 最小修改方向 / 裁决：各自用现有dismiss添加原生“取消/关闭”Button，不抽象SheetContainer。

</details>

<details>
<summary>F-168 · P2 · 已确认 · SheetPicker 未把当前选择交给 focus/accessibility</summary>

- 审查单元与位置：C006→W020-E/F→G05；自建选择页上下文、选中语义与初始焦点
- 触发路径：任一Picker打开嵌套详情；最强反例为Subscribe指定季已选100，选项为“全部”加0...100。
- 根因：所有OS都使用Button→嵌套Sheet→Button列表；传入title完全未进入视图树，当前项只显示checkmark，没有selected trait或任何默认焦点偏好。
- 用户影响：详情确定缺少可见任务上下文与结构化选中语义；若VStack按首Button默认聚焦，用户还可能需移动101步回到当前季，但系统可能恢复/自动滚动焦点或朗读checkmark，该后果未验证。
- 证据：既有多审确认；G05主审与独立复核均确认title被丢弃、选中项无结构化语义并支持P2；显示既有title、给当前项isSelected并复用最小默认焦点
- 跨端结论：静态上下文/选中语义P2；真实初焦、VoiceOver播报与动态删除回退未验证
- 最小修改方向 / 裁决：优先评估可否恢复原生Picker；若保留嵌套实现，复用title作heading，为匹配行加selected语义及最小默认焦点；当前值不在options时保留raw，不建选择器框架。

</details>

<details>
<summary>F-170 · P2 · 已确认 · 选项域变化后隐藏的多选值无法移除</summary>

- 审查单元与位置：C008→W014/W020-D/E；选项域外已选值
- 触发路径：既有订阅包含后来停用的站点、被删除的规则组，或普通订阅用户打开含既有规则组的订阅。
- 根因：组件只为options生成Toggle，`selected - optionIDs`没有可见行或清除动作；Subscribe只加载active站点且普通用户不加载规则组，却不归一化已有sites/filter_groups，保存仍原样编码隐藏值。
- 用户影响：按钮只显示已选数量/旧名称，内层Sheet为空或缺项；确认、系统返回、切换可见项都不能移除隐藏配置，随后仍可保存。
- 证据：C008/W014双审闭合主链；W020-D/E补站点/规则传播；显示可移除不可用项；仅正确权威域成功后归一化且未经确认不删除
- 跨端结论：条件性P2；真实旧配置/域变化频率未验证
- 最小修改方向 / 裁决：当`selected - optionIDs`非空时显示最小可清除行或“清除不可用选择（N）”，只做集合减法；不自动与options求交、不清可见选择、不建多选框架。

</details>

<details>
<summary>F-171 · P2 · 已确认 · Canvas 徽章元数据没有可访问性替代</summary>

- 审查单元与位置：C009-A→I010→G03；MediaCard徽章元数据可访问性
- 触发路径：任一卡片显示上述徽章，VoiceOver用户浏览整卡。
- 根因：四类信息全部作为Canvas symbols绘制；Canvas不为单个绘制元素/symbol提供可访问性，目标段、全文件及调用页均无显式替代语义。
- 用户影响：首页订阅“新/阅/待/停”和完结/更新时间、分季评分/入库状态、混合搜索来源等唯一信息可能缺失；Canvas外标题仍可读、来源专属页可由上下文推断，只限制严重度而不能补回状态。
- 证据：既有双审与I010确认机制；G03两名纠偏复核再次独立闭合全部生产卡片owner并升级P2；先按F-175建立原生整卡owner，再拼实际可见徽章accessibilityValue
- 跨端结论：静态缺失已确认；VoiceOver焦点顺序/播报措辞未运行验证
- 最小修改方向 / 裁决：保留Canvas性能实现，在C009-B确认的现有整卡交互元素上把现有值拼成简短accessibilityValue；来源补简单可读名称，不建卡片/图片框架。

</details>

<details>
<summary>F-174 · P2 · 已确认 · 无 owner 的全局 sourceFrame 被另一详情消费</summary>

- 审查单元与位置：C009-C→W006-C→I010→G03；MediaCard详情转场源owner
- 触发路径：Home订阅卡A主点击先写frame但只开编辑Sheet；关闭后长按卡B选详情，B入口不写/清frame且未预加载。
- 根因：任何MediaCard主点击都先写全局sourceFrame再执行语义未知的action；静态槽没有目标、动作owner或代际，直到下一次详情Loading才读取并清除，四个NavigationStack还共享同一槽。
- 用户影响：B的海报/占位从A的位置错误飞入，产生短暂视觉误导；不会打开错详情或执行错mutation，因此为P3。
- 证据：G03两名纠偏复核独立闭合Search分享Sheet→后续详情生产链并升级P2；loadingPosterURL/session仍留F-123；只在实际详情push写目标绑定的一次性frame payload；不合并F-123/F-118
- 跨端结论：纯TV错误转场已确认；真实动作顺序与视觉持续时间未运行验证
- 最小修改方向 / 裁决：优先删除sourceFrame/FrameAnchor和手工位置飞入，复用现有NavigationStack转场与无源缩放fallback；若必须保留，只让实际详情push写目标绑定一次性状态，不建转场框架。

</details>

<details>
<summary>F-175 · P2 · 已确认 · 人物卡主操作没有建立整卡控制语义</summary>

- 审查单元与位置：C010→I011/I010；自定义卡片主操作可访问性
- 触发路径：VoiceOver用户浏览/激活人物卡；普通遥控器Select可工作。
- 根因：唯一主操作owner是海报raw `.focusable(true)+.onTapGesture`；人物姓名/职位及MediaCard标题/徽章位于兄弟节点，整卡没有原生Button、合并label、button trait或default accessibility action，下载卡也缺原生disabled控制语义。
- 用户影响：辅助技术可能拿不到人物姓名与主动作的单一控制语义；三处context menu均有原生“详情”是绕行反证，实际枚举/双击路由未验证。
- 证据：既有Person/Torrent三方裁P2；I010两代理确认MediaCard同根传播；三类卡复用原生Button与现有route/download gate，不建卡片框架
- 跨端结论：静态控制语义缺口已确认；VoiceOver/遥控实际表现待运行
- 最小修改方向 / 裁决：用原生Button承载现有整卡label/action并保留视觉/focus动画；按F-143对无规范route identity同步禁用/隐藏，不建卡片框架。

</details>

<details>
<summary>F-176 · P2 · 已确认 · 详情横向行失焦会无条件请求下一页</summary>

- 审查单元与位置：C010→G04；详情横向行焦点分页
- 触发路径：焦点从任一行移走或激活卡片push详情，optional FocusState从ID变nil且Paginator仍hasMore。
- 根因：三处将nil原样传入`loadMore`; Paginator在itemID为nil时跳过位置/threshold判断，直接进入加载序列。Search人物行先`if let newId`是正确对照。
- 用户影响：失焦/重复进出可在后台多取下一页，改变loading与模型驻留；在途请求或hasMore=false会阻止，是边界反证。
- 证据：既有双审闭合三处调用；全新G04 clean-room复核确认静态请求链并升级P2；三处调用前`guard let newId`；不改Paginator公共nil语义
- 跨端结论：静态功能缺口P2；tvOS nil频率、视觉与焦点后果未运行验证
- 最小修改方向 / 裁决：三处onChange在创建Task前`guard let newId else { return }`；不改Paginator nil API、不建分页协调器。

</details>

<details>
<summary>F-179 · P2 · 已确认 · 资源卡展示字符串未统一规范空白</summary>

- 审查单元与位置：C017→G05；资源卡/筛选展示字符串规范化
- 触发路径：资源能够完整解码且meta+torrent均存在，但任一可选展示字段为`""`或纯空白；同时可能存在有效后备标题/描述。
- 根因：同一资源展示边界混用nil-only fallback、未trim的`isEmpty`与非nil即渲染，未先把空串/纯空白规范为缺值；卡片与筛选又分别投影原始值。
- 用户影响：卡片可显示空标题/描述行、无文字胶囊或孤立分隔符，筛选还可把同一空白值列成独立不可辨识选项；下载目标本身不变，但正常筛选和结果识别可稳定受阻。
- 证据：既有双审闭合字段矩阵；G05主审与独立复核均确认卡片与筛选的稳定分裂并支持P2；复用现有trim→空为nil投影后再fallback/渲染/筛选；不建资源展示模型
- 跨端结论：条件性P2；真实上游空白字段频率未验证
- 最小修改方向 / 裁决：复用现有`MediaIdentifier.normalizedString`或等价一行trim→空为nil投影；主/副标题规范后再fallback，标签只对规范非空值创建，筛选options/matching/disabled三链使用同一规范值；不建资源展示模型。

</details>

<details>
<summary>F-180 · P2 · 已确认 · 详情加载失败被静默伪装成可用 partial 页面</summary>

- 审查单元与位置：W007→I013；详情失败终态呈现
- 触发路径：详情请求连续三次异常或连续返回无有效详情；`fullDetail`保持nil而`isDetailFailed=true`。
- 根因：容器无条件把`isDetailFailed`并入ready，立即隐藏Loading并显示`fullDetail ?? partialMedia`；应用完整详情的入口因nil直接返回，背景、演职员、推荐/相似等派生加载不启动，页面又没有失败文案或页内retry。
- 用户影响：用户看到看似已就绪但内容残缺、背景缺失的详情页，无法区分真实稀疏数据与加载失败；只有退出重进后新`preload(for:)`才会淘汰failed task并重建。
- 证据：既有三方闭合机制；review_a001_j第三裁确认主详情静默失败独立P2并保留Back重进反证；partial旁显示明确失败与原生Retry，复用failed-task重建
- 跨端结论：条件性P2；真实失败频率、partial丰富度及focus表现未验证
- 最小修改方向 / 裁决：保留partial fallback，在现有Loading owner显式显示失败，并让一次retry调用现有failed-task淘汰/重建路径；不新增详情状态机或loader coordinator。

</details>

<details>
<summary>F-182 · P2 · 已确认 · 前台恢复被旧负订阅状态阻止发现远端新增</summary>

- 审查单元与位置：W008-B→I008；详情前台及60秒订阅刷新
- 触发路径：电影本地`isSubscribed=false`或电视剧`subscribedSeasons`为空；页面存活期间Web、其他设备或后端新建订阅；TV回到前台。
- 根因：scene activation与周期入口共用“本地已有active订阅才刷新”的谓词，旧false/空直接跳过网络强刷；远端变更又不会发本机`.subscriptionDidUpdate`。
- 用户影响：电影Header继续显示“订阅”，分季卡继续显示未订阅且没有时间上界；首次点击虽先强刷出远端true，但新旧状态不一致后按设计静默终止旧意图，表现为一次无反馈点击。
- 证据：既有双审闭合false→true链；I008整文件主审确认无时间上界的核心CTA错误；review_a001_h独立确认P2；活跃可订阅详情复用现有强刷，不新增轮询框架
- 跨端结论：TV静态用户链已确认；真实跨设备频率与后台时序未验证
- 最小修改方向 / 裁决：当前打开且有订阅权限的详情在scene active和既有60秒周期都强刷，保留点击前状态一致性guard；只是放宽现有predicate，不新增轮询器或状态机。

</details>

<details>
<summary>F-185 · P2 · 已确认 · 人物与季详情 Sheet 无法到达长文本尾部</summary>

- 审查单元与位置：W009→W013-C→W015/W018-B/W019/W020-B；模态Sheet长文本/路径可达性
- 触发路径：人物返回足够长但合法的biography并打开“完整简介”，或季详情返回足够长的overview。
- 根因：Sheet只有固定宽度`VStack + Text`，没有纵向`ScrollView`、分页或可移动焦点锚点；模态期间父页面不可作为替代读取路径。
- 用户影响：正文超过tvOS可视高度后，超出部分没有遥控器或VoiceOver可达路径；人物“完整简介”和季详情都无法完整读取。
- 证据：既有多段双审确认；W020-B主审补五行规则预览且无展开/滚动入口；信息区使用原生ScrollView/完整换行，操作区固定并验证遥控器/VoiceOver
- 跨端结论：条件性触发；真实长度阈值未验证
- 最小修改方向 / 裁决：Header保留有限行预览并明确进入完整简介；Sheet仅用原生纵向`ScrollView`包裹正文，保留现有关闭结构，不建阅读器或滚动框架。

</details>

<details>
<summary>F-186 · P2 · 已确认 · 资源促销筛选压扁后端枚举</summary>

- 审查单元与位置：W011；资源促销筛选枚举
- 触发路径：资源使用当前后端支持的30%、70%、25%、75%、4X或2X 50%等非简化促销值，用户打开或应用促销筛选。
- 根因：TV不复用卡片已经展示的`volume_factor`，而是从上传/下载数值倍率重新推导；任意下载倍率小于1都压成“50%”，任意上传倍率大于1都压成“2x”，组合又被判断顺序丢失。
- 用户影响：卡片显示“30%”“4X”“2X 50%”时，筛选选项却显示/匹配为“50%”或“2x”；选择真实文案无法稳定筛出对应资源，并与Web按原始字段筛选的行为分裂。
- 证据：review_a001_j提出并核对当前上游；verify_a001_h无W011污染独立确认30/70/4X/2X 50%反例；删除重算helper，筛选直接复用现有`volume_factor`并覆盖完整枚举
- 跨端结论：当前本地上游快照已核对；远程最新性和真实频率未验证
- 最小修改方向 / 裁决：删除数值重算helper，筛选直接复用卡片/Web已使用的`volume_factor`；空值沿F-022输入边界单独处理，不建促销模型。

</details>

<details>
<summary>F-187 · P2 · 已确认 · 资源错误或成功空终态没有同页面重试</summary>

- 审查单元与位置：W011；资源空/错终态恢复
- 触发路径：资源搜索收到业务error且最终无结果、流与同步fallback均失败，或合法完成但返回空数组。
- 根因：三类终态都进入没有action的空态；ViewModel在请求开始即置`hasSearched=true`，完成后不复位，再次调用`search()`会被门闩直接拒绝。
- 用户影响：错误时虽可见描述、成功空时可见通用空态，但网络/条件变化后页面内没有任何恢复动作，只能退出目的地再进入；这是完整页面恢复阻断。
- 证据：review_a001_j提出错误/空无重试；verify_a001_h确认三类终态与现有根因均不能提供retry contract；复用EmptyDataView action，调用现有cancelSearch后重新search
- 跨端结论：用户只能退出重进；真实故障/空结果频率未验证
- 最小修改方向 / 裁决：复用`EmptyDataView(actionTitle:action:)`提供“重试”，动作调用现有`cancelSearch()`重置generation/门闩后再`search()`；不建错误状态或恢复框架。

</details>

<details>
<summary>F-194 · P2 · 已确认 · Fork 确认页隐藏立即持久化的关键搜索规则</summary>

- 审查单元与位置：W015；Fork最终确认字段完整性
- 触发路径：分享携带非空 `keyword` 或含多行规则的 `custom_words`，用户在 TV 确认页完成 Fork。
- 根因：TV 的请求模型保留并在 POST 时立即发送两字段，当前后端也立即持久化；确认页却只显示标题、备注等摘要，没有展示这些会直接改变后续搜索/识别行为的规则。当前 Web 已展示这两项。
- 用户影响：用户在最终写入前无法知道 Fork 后会启用哪些包含/排除关键词或自定义识别规则；这些不是进入编辑器后才产生的草稿，而是 POST 成功即生效的远端配置。
- 证据：W015双审对照TV编码、当前后端持久化与Web显示闭合多行规则反例；按Web最小边界只读展示非空keyword/custom_words并支持展开/滚动
- 跨端结论：两字段缺口已确认；其他过滤字段是否须展示未验证
- 最小修改方向 / 裁决：按已获跨端证据的最小集合，只读展示非空 `keyword` 与 `custom_words`；长/多行值允许展开或滚动，操作区保持固定可达。其余字段在产品契约确认前不新增。

</details>

<details>
<summary>F-195 · P2 · 已确认 · `custom_words` 多规则合同被降成单行编辑</summary>

- 审查单元与位置：W014；SubscribeSheet custom_words多行编辑合同
- 触发路径：用户需要创建或编辑两条以上自定义识别规则，例如以 LF 分隔的两行映射/过滤表达式。
- 根因：当前后端按 LF 拆分 `custom_words` 为多条规则，Web 使用多行 textarea；TV 却复用单行 `TextField/UITextField`，UIKit Return 又固定为 Done，无法输入第二行，也无法可靠审阅既有行边界。
- 用户影响：TV 不能创建后端已支持的多规则配置；编辑已有多行值时也缺少可理解的多行呈现。只修改其他字段时原始 String 会原样编码，因此不能夸大为“打开或保存必然损坏换行”。
- 证据：W014双审闭合SheetTextField/UITextField、Web VTextarea与后端split链；仅该字段复用tvOS多行编辑器并保留LF原值
- 跨端结论：编辑能力缺口已确认；既有LF聚焦后是否改写须运行验证
- 最小修改方向 / 裁决：仅为该字段使用 tvOS 兼容的多行编辑控件，保留 LF 原值与现有表单 owner；不把共享单行字段全部改造，也不引入表单框架。

</details>

<details>
<summary>F-198 · P2 · 已确认 · 不可获取的剧集统计被显示为 0</summary>

- 审查单元与位置：W016→G09；Status剧集统计nil展示
- 触发路径：所有已配置媒体服务都不提供剧集总数，例如当前UGREEN实现返回None，同时电影/电视剧数量正常可用。
- 根因：模型正确保留`episode_count: Int?`，View却用`?? 0`把nil投影为确切数字0；当前后端明确以None表示“所有服务均未提供”，Web显示“未获取”。
- 用户影响：同一响应在Web为“剧集 未获取”，TV为“剧集 0”，把未知误报为确定零。真实0与正数必须继续显示原值，请求整体失败的整卡空态不受影响。
- 证据：既有三票确认静态误报；G09两名代理按当前后端明确nil语义与跨端稳定差异共同支持P2；仅View层nil→“未获取”，0与正数原样
- 跨端结论：稳定运维统计误报已确认；部署组合与渲染未验证
- 最小修改方向 / 裁决：仅把该View值改成`episode_count.map(String.init) ?? "未获取"`；不改模型/API/后端，不建展示模型。

</details>

<details>
<summary>F-200 · P2 · 已确认 · 保存路径开放合同被封闭 Picker 限制</summary>

- 审查单元与位置：W014→G01纠偏；Subscribe save_path开放值域
- 触发路径：用户需要新建或编辑配置根目录下的合法子路径，或输入不在当前选项中的合法storage-qualified URI。
- 根因：当前合同允许配置下载根本身及其任意子路径，远程值须为`storage:/path`；Web combobox可手输。TV只有封闭Picker，没有新建/编辑任意String值的入口。
- 用户影响：合法自定义子路径或新URI无法在TV新建/修改，只能依赖管理员预先把完整值放进配置选项或离开TV处理。
- 证据：既有双审确认开放合同；G01按当前TV/Web再次核对并驳回“已有值必丢/已配置URI不可选”的扩大说法；复用现有文本输入直接绑定String，配置路径只作快捷建议
- 跨端结论：条件性P2；产品文案、真实远程目录与自定义子路径频率未验证
- 最小修改方向 / 裁决：复用现有`SheetTextField`直接绑定当前String，配置路径只保留为快捷建议；不改Subscribe模型/API，不建通用editable Picker。

</details>

<details>
<summary>F-201 · P2 · 已确认 · 失败历史的 `errmsg` 在 TV 内完全不可达</summary>

- 审查单元与位置：W019；Transfer失败原因可达性
- 触发路径：任一转移历史状态为失败且后端提供非空失败原因，用户查看行或长按详情。
- 根因：模型已经解码`errmsg`，但行只投影“失败”，详情也只重复状态，没有任何代码消费失败原因；当前Web在失败状态tooltip展示该字段，后端明确将其定义为失败原因。
- 用户影响：用户知道任务失败却无法知道原因，无法区分权限、路径、识别或存储错误，也无法据此采取恢复动作。成功记录没有原因是正向边界。
- 证据：verify_a001_h与review_a001_h双审对照TV模型/View、当前Web tooltip与后端语义闭合；仅在可滚动详情展示trim后非空errmsg，列表保持紧凑
- 跨端结论：真实长错误频率未验证
- 最小修改方向 / 裁决：仅在详情页展示trim后非空`errmsg`，列表保持紧凑；详情随F-185使用原生ScrollView，不建诊断框架。

</details>

<details>
<summary>F-202 · P2 · 已确认 · 合法稀疏 `FileItem` 可令整页历史解码失败</summary>

- 审查单元与位置：W019；Transfer嵌套FileItem解码
- 触发路径：一个响应页同时含正常历史和至少一条缺`name`、`path`或`type`等显示字段的合法稀疏历史JSON。
- 根因：TV把`FileItem.name/path/type`声明为必填String；当前后端schema允许相关字段缺失/空，历史表又原样持久化JSON并直接输出。`[TransferHistory]`整体解码使单条嵌套缺键拖垮整页。
- 用户影响：相邻正常历史也全部不可见，随后落入F-033的错误/空态缺口。当前正常写入常用完整`model_dump()`，只降低频率，不构成schema保证。
- 证据：双审核对后端原样JSON、仅path fixture及整页原子解码；危险边界为非null稀疏对象；仅历史响应DTO字段级宽容并降级显示，保留相邻好行
- 跨端结论：条件性P2；现存稀疏历史分布待验证
- 最小修改方向 / 裁决：历史DTO仅对可缺显示字段做宽容解码和中性降级，保留相邻好行；不把整个生产`FileItem`模型全面可空化，也不静默丢弃整条历史。
- 修复状态：已完成（`670cf86`）；完整、仅path、null与空对象同页回归均已覆盖，Simulator clean build与跳过真实后端兼容套件后的本地串行432/432测试及独立复审通过。

</details>

<details>
<summary>F-205 · P2 · 已确认 · Reorganize 刷新期间唯一焦点恢复调用被丢弃</summary>

- 审查单元与位置：W019→I009/G10；Reorganize关闭刷新焦点时序
- 触发路径：整理成功后父级refresh比Sheet dismiss慢；或提交期间按取消，后台Task继续成功并迟到调用父回调。
- 根因：子Sheet固定先`onDone()`启动刷新再`dismiss()`；父`onDismiss`在刷新中调用restore时被guard直接return，刷新完成只清标志、不补第二次恢复。提交Task又不受Sheet生命周期拥有。
- 用户影响：项目已有的“回到原历史行”恢复逻辑确定不再执行，保存的历史ID持续不消费，成功整理后导航上下文被稳定交给任意Focus Engine选择；具体最终落点仍需真机验证，但核心遥控上下文中断达到P2。
- 证据：既有双审闭合静态丢调用；I009主审与G10独立复核确认成功路径和保存ID长期未消费；refresh完成清标志后复用现有restore；提交中禁取消/管理Task生命周期
- 跨端结论：TV返回导航上下文缺陷已确认；真实Focus Engine落点未验证
- 最小修改方向 / 裁决：刷新完成清标志后调用现有`restoreHistoryFocus()`；提交期间禁用/拥有取消与Task生命周期，不引入通用焦点协调器。

</details>

<details>
<summary>F-206 · P2 · 已确认 · Reorganize 无法输入后端支持的自定义目标路径</summary>

- 审查单元与位置：W018-A；Reorganize自定义目标路径能力
- 触发路径：用户需要把整理结果写入未列入系统配置目录的合法自定义目标路径。
- 根因：TV只提供“自动 + 配置library_path”的闭合Picker，没有自定义输入；但ViewModel与现有测试已能保留未知路径，当前Web使用可自由输入combobox，后端也把任意`target_path`作为一等自定义路径分支处理。
- 用户影响：TV无法使用当前Web/后端已经支持的核心目的目录能力，只能改用自动/预设路径或离开TV；配置目录覆盖常见路径且不会直接损坏数据，故为P2而非P1。
- 证据：review_a001_h提出；review_a001_j独立闭合TV/VM测试/Web combobox/后端自定义路径分支；保留现有目录建议，仅该字段增加自定义输入并复用现有updateForm/编码
- 跨端结论：当前本地上游已核对；真实自定义路径频率与部署版本未验证
- 最小修改方向 / 裁决：保留现有目录建议，仅为该字段增加自定义文本入口并复用现有`updateForm`/编码路径；不开发通用Combobox框架。

</details>

<details>
<summary>F-209 · P2 · 已确认 · “全部站点”被编码成后端默认站点子集</summary>

- 审查单元与位置：W020-D；“全部站点”与后端默认集合合同
- 触发路径：活动搜索站点为`{1,2}`，后端`IndexerSites={1}`；用户在System明确选择“全部站点”后发起资源搜索。
- 根因：TV用空数组表示“全部”，SiteFilter再把空转换为`sites=nil`；当前后端对空sites的合同却是回退`IndexerSites`默认集合，不是枚举全部活动搜索站点。
- 用户影响：界面显示“全部”，请求稳定只搜索默认子集并静默漏掉站点2；当`IndexerSites`为空或恰好等于全部活动站点时无差异，因此保持条件性P2。
- 证据：三代理确认机制/P2；第三裁决证明正确候选域仍不能修复nil三态，独立于F-210；显式发送全部活动站点ID；若保留nil则UI准确命名“后端默认”
- 跨端结论：条件性P2；真实部署IndexerSites分布未验证
- 最小修改方向 / 裁决：选择“全部”时发送权威活动搜索站点的全部ID；若产品坚持发送nil，则把UI准确命名为“后端默认”，不新增站点选择模型。

</details>

<details>
<summary>F-210 · P2 · 已确认 · 资源搜索站点选择器使用了错误的 RSS 权威域</summary>

- 审查单元与位置：W020-D；资源搜索站点权威域
- 触发路径：活动搜索站点含RSS站点1和非RSS站点2，inactive站点3；`RssSites={1}`、`IndexerSites={1,2}`，用户已保存站点2或打开站点选择页。
- 根因：TV把订阅场景的`/site/rss`响应直接当资源搜索权威域且不筛`is_active`；当前后端配置RssSites时只返回RSS子集，未配置时又可返回含inactive的数据库全表。资源搜索真实域并不由RssSites定义。
- 用户影响：合法非RSS活动站点缺失，停用站点可被展示并产生空结果；非空响应后的自动求交还可能把已保存的合法站点2永久删除。集合碰巧全活动且RssSites为空时无差异。
- 证据：三代理确认机制/P2；第三裁决证明修正nil仍不能补回RSS域缺失项，独立于F-209；使用search权限可读的活动搜索站点合同，TV仍滤inactive且仅权威成功后归一化
- 跨端结论：条件性P2；实际indexer过滤模块与部署分布未验证
- 最小修改方向 / 裁决：提供或复用search权限可读、只含安全字段的活动搜索站点合同；TV仍防御性过滤inactive，且仅在正确权威域成功加载后归一化，同时遵守F-170的用户明确清除边界。

</details>

<details>
<summary>F-221 · P2 · 已确认 · 识别状态按 partial media 冻结后无法到达终态</summary>

- 审查单元与位置：I005→G03；识别终态冻结在partial media
- 触发路径：partial没有可识别主ID而跳过识别；full detail随后补出Douban/Bangumi/AniList等可识别身份但仍无TMDB目标。
- 根因：是否启动识别只在partial快照上判一次；跳过分支没有发布明确terminal state，full detail到达后也不按最终canonical media重新裁识别可用性。
- 用户影响：详情动作可同时处于“可识别、目标为空、识别未完成”，长期显示不可操作spinner且没有重试/无结果终态；是否达到条件须由固定payload确认。
- 证据：I005双审确认；G03窄第三裁逐个consumer收窄为Header单动作并再次确认P2；full detail后重评一次；执行/跳过/失败/取消均落terminal，不建状态机
- 跨端结论：纯TV识别终态P2已确认；实际插件payload频率未验证
- 最小修改方向 / 裁决：以最终canonical media驱动单一terminal state：running/succeeded/no-result/unavailable均明确落定；full detail补身份时按owner重新判断，预载与实际跳转复用同一最终key。

</details>

<details>
<summary>F-223 · P2 · 已确认 · 同操作重试成功不会撤销旧失败通知</summary>

- 审查单元与位置：G08；同操作成功不会撤销旧失败通知
- 触发路径：登录或订阅动作失败显示五秒错误，用户立即重试并成功；或A失败、B失败后A的迟到成功试图清理。
- 根因：manager只有新通知替换与自动隐藏，没有操作ID/scope dismiss；生产策略正确地不显示成功toast，却也没有在同一操作成功或新attempt时撤销对应旧错误。
- 用户影响：成功进入首页或完成动作后仍展示相反的旧失败；若用全局dismiss修补，旧A成功又可能误删更新的B错误。
- 证据：review_a001_h提出登录/Home反例，review_a001_j独立确认同session可达与A失败/B失败/A成功反向边界；轻量notification ID/operation scope；成功只撤销同owner旧错误，不新增成功toast或通知框架
- 跨端结论：纯TV通知operation owner缺陷已确认
- 最小修改方向 / 裁决：让现有`show`返回轻量notification ID或复用小型operation scope；新attempt/成功只撤销自身旧错误，成功继续静默，不建错误总线或通知框架。

</details>

<details>
<summary>F-225 · P2 · 已确认 · 可选订阅分享阻塞核心搜索结果揭示</summary>

- 审查单元与位置：I007；可选订阅分享阻塞核心搜索结果揭示
- 触发路径：媒体、合集、人物请求均已完成并有结果，可选订阅分享请求仍挂起或显著更慢。
- 根因：核心与可选分享任务虽并发启动，但搜索完成/揭示结果统一等待全部类别；视图不单独呈现分享行loading。
- 用户影响：用户已经可以消费的核心结果继续被全页加载态遮住，最慢可选请求决定整个搜索可用时间；真实延迟与超时上限待确认。
- 证据：review_a001_j整文件集成提出，verify_a001_h独立以share gate闭合全页spinner与两阶段发布边界；核心类别完成即显示，分享行独立加载；复用现有Paginator错误字段，不建搜索状态机
- 跨端结论：纯TV阶段屏障已确认；真实分享延迟分布未验证
- 最小修改方向 / 裁决：核心类别settled后立即显示现有结果，分享行独立使用已有loading/error字段；不新建搜索状态机或协调器。

</details>

<details>
<summary>F-226 · P2 · 已确认 · Bangumi人物 `career` 未进入 TV 展示投影</summary>

- 审查单元与位置：G07；Bangumi人物`career`展示投影
- 触发路径：Bangumi 人物 credits 返回非空 `career`，TV 解码并显示人物卡片或人物详情。
- 根因：当前后端明确写入并返回 `MediaPerson.career`，TV `Person` 没有对应字段/CodingKey，现有卡片职位投影也无消费入口；当前 Web `PersonCard` 会展示该数组。
- 用户影响：姓名与图片仍可显示，但角色副标题稳定丢失；同一声优多条career又不会由现有character merge保留，用户无法区分其作品职责。
- 证据：review_a001_h主审与review_a001_j独立复核闭合Bangumi credits、schema、TV模型/卡片及Web对照；解码career并纳入同人物合并，复用共享displayRole；relation无调用者不扩展
- 跨端结论：TV跨端字段投影缺陷已确认；真实载荷频率未验证
- 最小修改方向 / 裁决：解码`career`并纳入同人物合并，由共享display role投影按`job → career/roles/character`消费；`relation`当前无确认调用者，不为未来扩字段。

</details>

<details>
<summary>F-227 · P2 · 已修复 · 人物稀疏详情覆盖 seed 展示字段</summary>

- 审查单元与位置：G07→F-143拆分裁决；人物稀疏详情覆盖seed展示字段
- 触发路径：seed已有规范source/raw_id、姓名、头像与别名；详情端点返回空对象或只含少数字段的合法200，credits同时按seed返回作品。
- 根因：credits fetcher合理冻结seed owner，但详情成功后除少数字段外直接采用fullDetail可选值，nil/空值可覆盖seed展示及route字段。
- 用户影响：作品仍正常加载，头部却退成“未知”/无头像/无别名，公开person与请求owner分裂；不会把credits请求切到错人。
- 证据：G07双审确认，verify_a001_h第三裁按独立字段merge修复/fixture拆出；route owner保持seed；详情仅以有效更丰富字段覆盖，不做全对象替换
- 跨端结论：TV字段合并缺陷已确认；真实稀疏200频率未验证
- 最小修改方向 / 裁决：route identity始终保留seed；详情逐字段仅用规范非空/更丰富值覆盖，不做全对象盲替换，也不让credits跟随不可信回包。
- 修复状态：已完成（本次提交）。`PersonDetailViewModel`按字段合并详情，保留入口人物的身份和已有展示字段；seed已有头像/图片时优先复用，避免详情返回另一图片地址造成首屏闪烁。
- 验证：新增稀疏人物详情与头像地址变化回归测试；tvOS Simulator Debug clean build 通过，全量串行测试 527 项执行、16 项跳过、0 失败。
- 剩余验证：当前部署稀疏200频率、异步竞态与真实人物页面视觉闪烁仍需运行环境复测。

</details>

<details>
<summary>F-230 · P2 · 已确认（用户决定跳过） · 旧系统 SheetTextField 固定字体不消费辅助字号</summary>

- 审查单元与位置：G10；旧系统SheetTextField固定字体不随辅助字号
- 触发路径：目标系统运行兼容分支，用户使用更大内容尺寸或低视力辅助设置打开任一业务Sheet文本框。
- 根因：桥接固定`UIFont.systemFont(ofSize: 30)`与66高度，没有`UIFontMetrics`缩放或环境内容尺寸更新。
- 用户影响：输入文本不能随系统辅助字号放大，固定高度还可能在补缩放后裁切；正常字号与26.4+原生分支不受影响。
- 证据：review_a001_h全局主审与verify_a001_h独立复核确认目标分支、调用范围和系统性可访问性缺口；现有桥接用UIFontMetrics/自动调整并把66改最小高度；不建输入框框架
- 跨端结论：静态动态字体缺口已确认；最大字号裁切待运行
- 最小修改方向 / 裁决：在现有桥接用`UIFontMetrics`生成scalable font并按环境更新，保留当前白底/阴影；高度只做满足缩放后的最小约束，不建字体或输入框框架。
- 处置状态：仅影响过时的tvOS 26.0–26.3兼容分支；用户决定跳过，不再列为待处理项。

</details>

<details>
<summary>F-231 · P2 · 已确认 · 详情 TMDB 异步动作不属于当前 route</summary>

- 审查单元与位置：I013；详情TMDB异步动作缺route owner
- 触发路径：预载识别未给目标；用户点击TMDB并挂起识别请求，随后pop离开详情，再放行请求。
- 根因：按钮创建未保存、未取消、无route generation的Task；onDisappear只取消推荐/相似防抖，识别首段catch还可吞取消后继续fallback。
- 用户影响：成功旧任务会在用户已返回后向共享path追加新详情，失败则在无关页面显示旧“未识别”提示；同一session即可成立。
- 证据：verify_a001_h整文件集成与review_a001_h定向独立复核闭合pop、双激活、跨session晚到族；单一action Task随route取消，发布前校验generation/session；不建导航框架
- 跨端结论：纯TV动作owner缺陷已确认；真实慢请求/动画时序未验证
- 最小修改方向 / 裁决：保存单一TMDB action Task，route离场取消；每个await后同时检查cancellation与当前route owner再append/报警，fallback前传播取消。不建导航协调器。

</details>

<details>
<summary>F-232 · P2 · 已确认 · Transfer 历史 offset 分页缺少稳定同秒排序</summary>

- 审查单元与位置：I009；Transfer历史分页缺稳定同秒排序
- 触发路径：至少21条不同ID记录拥有同一秒`date`，用户连续请求相邻offset页；或同秒新旧记录进入`fetchLatest()`扫描。
- 根因：后端写入时间只精确到秒，分页仅按`date DESC`排序后直接`OFFSET/LIMIT`；同秒行没有全序，不同查询可采用不同但都合法的tie排列。
- 用户影响：相邻页可重复已见记录并永久遗漏另一段；TV按ID去重只能删除重复，不能补回漏项，整页均已知时还可提前置`hasMore=false`；轮询遇首个已知ID即停也会漏掉其后的新ID。
- 证据：review_a001_h定向复核提出，verify_a001_h第三裁核对TV/Web/后端四类查询并确认独立P2；四个分页分支统一date DESC,id DESC；补25条同秒跨页fixture，不引入游标框架
- 跨端结论：后端共享契约缺陷已确认；真实数据库计划与触发频率未运行验证
- 最小修改方向 / 裁决：四个分页查询统一追加`id DESC`作为tie-breaker；不引入cursor分页框架。

</details>

<details>
<summary>F-233 · P2 · 已确认 · 插件筛选运行值被 truthy 默认值强制覆盖</summary>

- 审查单元与位置：I006；插件筛选truthy默认覆盖显式falsey值
- 触发路径：插件给字段truthy默认；用户显式选择`.bool(false)`、`.int(0)`、空字符串或`.null`。
- 根因：运行更新把所有falsey输入重新替换成truthy默认，混淆“初始化默认”与“用户当前值”；初始化路径本已单独装载默认。
- 用户影响：开关无法关闭、数值无法设0、选择/文本无法清空，UI回弹且query继续发送默认值。
- 证据：review_a001_h受限集成提出，review_a001_j隔离审计材料定向复核确认四类值与初始化反证；默认只在source初始化应用；运行时原样保存用户值
- 跨端结论：TV状态owner缺陷已确认；真实插件字段频率未验证，程序限制披露
- 最小修改方向 / 裁决：删除运行更新中的truthy默认回填；默认只在source/profile初始化或明确reset时应用，不建筛选框架。

</details>

<details>
<summary>F-234 · P2 · 已确认 · 动态插件 profile 变化时保留失效旧筛选</summary>

- 审查单元与位置：I006；插件profile兼容只比较defaults
- 触发路径：D1选择`mode=cold`；D2保持相同source prefix与defaults，但删除该option或改变control kind/depends。
- 根因：保留判定只比较source与`filter_params`默认字典，不比较`filter_ui/options/depends`；新控件与旧值来自不同schema版本。
- 用户影响：Picker找不到旧tag后显示“默认”，底层值仍为cold且query继续发送已失效筛选，呈现与请求分裂。
- 证据：两代理完整复核descriptor保留、控件显示与query链；profile任一结构部分变化即回新defaults，或仅校验并清失效值
- 跨端结论：条件性TV动态schema缺陷；后端热更新保证未验证，程序限制披露
- 最小修改方向 / 裁决：仅当defaults、filter_ui与depends都相同才保留值；任一结构部分变化回新defaults。若要更精细，只用现有parser校验并清失效值。

</details>

<details>
<summary>F-235 · P2 · 已确认 · Explore 手写 source key 绕过统一身份规范化</summary>

- 审查单元与位置：I006；Explore source与Popular身份绕过规范化
- 触发路径：动态source返回`tmdb`/`TMDB`/带空白AniList；或Popular为同一ID/同季返回`tmdb`与`themoviedb`别名。
- 根因：source快照按原始区分大小写prefix去重；Popular又手写部分别名并拼入原始source，绕过已有canonical identity。
- 用户影响：同一逻辑来源出现两项；同一媒体保留重复卡片并以两个导航/预载身份继续传播。
- 证据：两代理确认已有MediaIdentifier canonical逻辑却被两处手写prefix/key绕过；source去重复用normalizeSource；Popular key复用canonical identity并保留season
- 跨端结论：条件性TV身份缺陷；真实非规范载荷频率未验证，程序限制披露
- 最小修改方向 / 裁决：source快照统一调用`MediaIdentifier.normalizeSource`；Popular优先复用`item.identity?.mediaKey`并只附加season，不再手写来源规范化。

</details>

<details>
<summary>F-236 · P2 · 已确认 · Explore Paginator 去重键丢失 source owner</summary>

- 审查单元与位置：I006→G04；Explore Paginator owner键只有path
- 触发路径：从source A切换到source B，两者最终path相同但fetch/processor或权限语义不同。
- 根因：publisher先投影为纯path再去重，source身份已丢；切换事件被吞，Paginator继续持有A语义。
- 用户影响：UI显示B但请求解码、去重或权限仍按A执行。普通两个custom source往往语义相同，仅内置/特殊source与custom path冲突时明显。
- 证据：既有双审确认机制；全新G04 clean-room复核补当前上游无path唯一合同并升级P2；publisher用现有(source.id,path) tuple去重，setup仍消费path
- 跨端结论：条件性TV owner缺陷P2；实际插件碰撞频率未验证，程序限制永久披露
- 最小修改方向 / 裁决：publisher输出现有`(selectedSource.id, path)`作为owner key，去重后仍把path交给原setup，不建owner类型或状态机。

</details>

<details>
<summary>F-239 · P2 · 已确认 · Search 延迟预载任务离页或切会话后仍执行</summary>

- 审查单元与位置：I010；Search行延迟预载缺离页与session owner
- 触发路径：行获得焦点后300ms内离开页面；或账号A调度后logout并登录B，再让旧sleep结束。
- 根因：两个Row各自保存unstructured Task但没有onDisappear取消，也没有捕获session snapshot；logout只清当时已登记的preload，而sleep中的producer尚未登记，随后会用当前APIService单例创建新任务。
- 用户影响：离场后仍产生无用网络/图片工作；跨会话时A的旧行可用B凭据请求A媒体并把结果发布到全局media-id cache，形成条件性错配与额外认证请求。
- 证据：review_a001_j整文件集成与verify_a001_h独立复核均闭合两类Row、logout清理先于迟到注册及现有Debouncer反例；复用现有PreloadDebouncer；离场取消并在调度/执行时复核session snapshot
- 跨端结论：条件性跨页面/会话P2已确认；真实300ms命中频率未运行验证
- 最小修改方向 / 裁决：复用仓内现有`PreloadDebouncer`，Row离场调用cancel；schedule与执行前复核同一session snapshot。不要新增第二个预载协调器。

</details>

<details>
<summary>F-240 · P2 · 已确认 · 动态推荐开关以可重复 title 作为配置 owner</summary>

- 审查单元与位置：I016→G01第三裁；动态推荐开关使用可重复title作为配置owner
- 触发路径：动态来源返回两条title相同但api_path不同的货架，或动态来源与内建货架同名。
- 根因：列表和ForEach按path区分两条来源，开关配置却按`shelf.title`寻址；同一业务对象在渲染与持久化层使用不同身份。
- 用户影响：两个独立Toggle共享一个值，切任一项会同时改变同名货架，用户无法表达“启用A、停用B”。
- 证据：I016两票确认机制；G01第三裁按当前生产链确认P2并保持与F-109独立；配置键复用稳定shelf.id/path，读取旧title仅作一次迁移fallback
- 跨端结论：纯TV配置owner已确认；真实同名来源频率未验证，程序限制披露
- 最小修改方向 / 裁决：开关键直接复用已用于渲染去重的稳定`shelf.id`/规范path；读取旧title键只作一次兼容fallback并写回新键，不建配置框架。

</details>

<details>
<summary>F-243 · P2 · 已确认 · SubscribeSeason 前台恢复不刷新分季 availability</summary>

- 审查单元与位置：I014；SubscribeSeason前台恢复与availability owner
- 触发路径：分季页已加载后进入后台，媒体库在后台由缺失变完整或相反；页面保持存活并回前台，用户在重新加载或切group前选择一季订阅。
- 根因：初载与group切换都会刷新availability，但scene active只强刷subscription；`seasonAvailability`没有进入前台刷新集合，后续`prepareSubscription`却直接用它决定`best_version`与`best_version_full`。
- 用户影响：旧availability不只造成badge陈旧，还会进入create→pause临时订阅mutation，使洗版/完整性字段与当前媒体库状态不一致。
- 证据：I014严格整文件集成提出，review_a001_h定向独立闭合后台媒体库变化→旧availability→create/pause链；scene active复用现有checkSeasonsStatus后再刷新subscription；不新增timer/协调器
- 跨端结论：条件性TV真实mutation；媒体库变化频率与运行时序未验证
- 最小修改方向 / 裁决：在现有scene-active Task中先复用`checkSeasonsStatus()`，再刷新subscription；沿用已有session/request owner，不新增timer、协调器或第二状态层。

</details>

<details>
<summary>F-245 · P2 · 已确认 · Fork 接受缺失 success 标志的 2xx 响应</summary>

- 审查单元与位置：G03；Fork mutation 2xx envelope
- 触发路径：Fork端点返回HTTP 2xx、正订阅ID，但envelope缺少`success`或其值为null；调用方随后按成功ID继续GET/presentation。
- 根因：内联 `ApiResponse<ForkResponse>` 成功判断使用 `success != false`；缺失/null会通过，且当前实现只要求ID存在、不要求正值。
- 用户影响：Fork Sheet按成功关闭，Search/Explore随后GET该ID并尝试打开编辑器；GET虽提供后续限制，却不能把含糊mutation acknowledgement变成明确成功。
- 证据：主审及两名不同纠偏复核均确认内联decoder、真实调用链与P2；它和F-083不是同decoder/端点/最小补丁，只共同关联CHK-017；仅`success == true`且ID为正时接受；不改下载decoder
- 跨端结论：TV fail-open分支已确认；当前后端Fork成功envelope合同未验证
- 最小修改方向 / 裁决：仅当`success == true`且ID为合法正值时接受，其他2xx失败关闭；只改Fork判断并补矩阵，不重构所有API响应。

</details>


### 原始 P3 处置区（52 项）

<details>
<summary>F-001 · P3 · 已确认 · `FlexibleBool` 带换行真值误降级</summary>

- 审查单元与位置：M001-B；`Models.swift:192-203`
- 触发路径：任一 `FlexibleBool` 字段收到 `"true\n"`、`"1\r\n"` 等带行尾的字符串。
- 根因：字符串只使用 `.whitespaces` 清理，两种真值比较与 `Int` 转换均失败后静默落入 `false`。
- 用户影响：可能隐藏管理员或功能入口、跳过启用的下载器/媒体服务器、漏加图片 Cookie，或误显示状态；不会造成权限提升。
- 证据：M001-B 主审完整追踪所有包装类型调用者及相关测试；verify_m001_b 独立复现解析分支、全量调用者和测试缺口；无新候选
- 跨端结论：TV 端缺陷已确认；上游是否产生该输入未验证
- 最小修改方向 / 裁决：若复核确认，将根因位置改为 `.whitespacesAndNewlines` 并补直接解码回归测试，不在调用者重复防御。

</details>

<details>
<summary>F-004 · P3 · 降级 · 完整原始 JSON 与强类型字段重复持有</summary>

- 审查单元与位置：M001-C；`Models.swift:612,614-616`，持有/编码在 `728,879,917,1000-1004`
- 触发路径：任何 `MediaInfo` 或 `[MediaInfo]` 解码，长分页和预加载缓存放大持有量。
- 根因：`rawPayload` 保存完整深层 JSON，同时所有已建模字段再次单独解码并长期持有。
- 用户影响：可能增加解码 CPU、常驻内存和 tvOS 淘汰/卡顿风险；实际幅度未验证。
- 证据：M001-C 主审确认唯一生产用途及分页/预加载持有路径；verify_m001_c 确认静态重复持有，但无真机量化，P2→P3
- 跨端结论：静态风险成立；实际性能影响须真机 Instruments
- 最小修改方向 / 裁决：先验证多态原始字段依赖，再只保留未建模/不透明字段；必须保留未知字段回归，并用真机 Allocations/RSS 定量。

</details>

<details>
<summary>F-005 · P3 · 已确认 · 状态模型默认值不能兜底缺键</summary>

- 审查单元与位置：M001-C；`Models.swift:416-450`，限 Statistic/DownloaderInfo 非可选字段
- 触发路径：Dashboard 或下载器响应缺失/null 任一非可选统计字段。
- 根因：属性 `= 0` 不会成为合成 `Decodable` 的缺键默认值。
- 用户影响：状态刷新失败，首次为空、后续保留旧值；顺序赋值可能形成跨卡片混合快照。
- 证据：M001-C 主审追踪 Dashboard 刷新和现有测试缺口；verify_m001_c 独立确认合成解码与顺序发布混合快照
- 跨端结论：官方 schema 是否保证字段齐全未验证
- 最小修改方向 / 裁决：若字段允许缺失，在模型边界 `decodeIfPresent ?? 0`；若必填，移除误导默认值并补严格契约测试。

</details>

<details>
<summary>F-009 · P3 · 已确认 · 修复已完成（`4c69ec9`） · 无法解析的版本被误报为过低</summary>

- 审查单元与位置：B001；`AppVersionInfo.swift:74-98`、`ContentViewModel.swift:193-201`
- 修复状态：已完成（`4c69ec9`）；启动提示与兼容巡检统一区分支持、过低、无法解析，独立复审及版本聚焦测试通过。
- 触发路径：后端返回非空但无法解析的版本，如 `v2.beta.14`、`release-2.15.1` 或整数溢出段。
- 根因：比较函数返回 nil，但警告模型用原始字符串非空且不等于中文“未知”作为另一套“已知”判断。
- 用户影响：启动弹窗把“无法判断”错误描述为“已确认版本过低”，误导升级或排查；不阻断功能。
- 证据：B001 主审闭合解析、警告分类与测试缺口；verify_b001 独立确认三态合流矛盾及测试诊断同类误述
- 跨端结论：TV 本地分类缺陷已确认；官方是否产生该格式未验证
- 最小修改方向 / 裁决：警告分类复用同一解析结果，明确区分支持、过低、无法确认。

</details>

<details>
<summary>F-010 · P3 · 已确认 · 修复已完成（`4c69ec9`） · 版本核心前置分隔符被接受</summary>

- 审查单元与位置：B001；`AppVersionInfo.swift:50-66`
- 修复状态：已完成（`4c69ec9`）；拒绝前置分隔符并保留合法 `v/V`、外围空白及版本后缀合同。
- 触发路径：`v-2.15.2`、`+2.15.2`、`v 2.15.2` 等版本。
- 根因：Swift `split(whereSeparator:)` 默认丢弃开头空片段，解析器未要求去掉可选 `v` 后以数字开始。
- 用户影响：可能错误通过兼容判断，或错误显示为已确认版本过低；仅影响警告。
- 证据：B001 主审核对 Swift split 语义与 malformed 测试意图；verify_b001 独立确认 split 丢空段与缺失边界测试
- 跨端结论：TV 解析缺陷已确认；官方格式未验证
- 最小修改方向 / 裁决：要求版本数字核心非空且从数字开始，补前置 `-`、`+`、空格拒绝用例。

</details>

<details>
<summary>F-015 · P3 · 已确认 · 修复已完成（`f04f73f`） · 非电影被误当成电视剧订阅</summary>

- 审查单元与位置：M001-D；`Models.swift:1199-1203` 及订阅调用者
- 修复状态：已完成（`f04f73f`）；合集入口已拒绝/隐藏，只有明确电视剧进入分季，其他允许类型直订。
- 触发路径：`type` 为合集或未知的非电影/非电视剧媒体。
- 根因：`canDirectlySubscribe` 只回答“是否电影”，调用者却把 false 直接解释为“进入分季流程”。
- 用户影响：右键菜单显示错误“分季订阅”；详情 Header 可出现点击无动作的按钮。
- 证据：review_m001_d 闭合合集/未知类型到无动作或错误分季入口；verify_m001_d 独立确认 handler/菜单/Header 三条路径
- 跨端结论：TV 二值分类缺陷已确认；上游类型集合/策略未验证
- 最小修改方向 / 裁决：进入分季流程时明确确认电视剧；其他类型隐藏或禁用订阅入口。

</details>

<details>
<summary>F-018 · P3 · 已确认 · 修复已完成（`94f18f2`） · 资源网格重复编译固定季集正则</summary>

- 审查单元与位置：B002；`Formatters.swift:24-32`、TorrentCard 网格调用链
- 修复状态：已完成（`94f18f2`）；固定正则改为单个静态实例，并补齐季、集、范围、大小写与无效输入回归矩阵。
- 触发路径：多个资源卡片渲染及筛选、排序、焦点、状态变化导致 body 重算。
- 根因：固定 pattern 与 `NSRegularExpression` 在 helper 每次调用时重新创建。
- 用户影响：增加主线程重绘开销；是否造成卡顿未量化。
- 证据：B002 主审确认唯一高频调用与无性能测试；verify_b002 以相邻静态正则模式确认重复工作并限制为低优先级
- 跨端结论：纯 TV 缺口；实际帧耗时未验证
- 最小修改方向 / 裁决：复用单个不可变正则或原生 Regex literal，并补最小季集输入测试；不缓存格式化结果。

</details>

<details>
<summary>F-021 · P3 · 已确认 · 修复已完成（`a0adaab`） · 未知大小被显示为真实零值</summary>

- 审查单元与位置：B002 复核新增 / M001-E；`DownloadTaskView.swift`、`TransferHistoryView.swift` 与可选大小模型
- 触发路径：`DownloadingInfo.size == nil`、`src_fileitem == nil` 或 `FileItem.size == nil`。
- 根因：调用者在格式化前把未知折叠为 0，或直接硬编码 `"0 B"`。
- 用户影响：未知大小被明确显示为零字节，不同入口还出现本地化零值与 `"0 B"` 两套文本。
- 证据：verify_b002 确认可选模型状态、调用者折叠和测试 fixture；review_m001_e 独立确认字段可选、缺失 fixture 与三个显示出口
- 跨端结论：TV 语义缺陷已确认；真实频率与 Web 占位未验证
- 最小修改方向 / 裁决：nil 显示“未知”或省略；只有非 nil 调用 `formattedBytes()`。
- 修复状态：提交 `a0adaab` 已覆盖三个出口：nil 时省略大小，真实零值仍显示为 `0 B`；最终独立复审通过，tvOS Simulator clean build 与本地测试 427/427 通过（明确跳过 5 个真实后端兼容套件）。

</details>

<details>
<summary>F-023 · P3 · 已确认 · 单项空标题令媒体服务器最新内容整批为空</summary>

- 审查单元与位置：M001-E；`MediaServerPlayItem.title` 与最近媒体整批解码
- 触发路径：最近媒体数组中任一项目缺失/null title。
- 根因：严格 String 解码使一项失败拖垮整批。
- 用户影响：首页该服务器最近内容显示为空。
- 证据：review_m001_e 闭合 API→Home 链及 fixture 缺口；verify_m001_e 独立确认数组原子解码与 Home 清空行为
- 跨端结论：TV 严格解码缺口已确认；当前后端 schema 已确认允许 title 为空
- 最小修改方向 / 裁决：仅在当前上游仍允许空标题时于解码边界提供中性内部标题。
- 修复状态：已完成（`af67839`）；缺失/null标题不再拖垮同批项目，独立复审通过，Simulator clean build 与本地测试 430/430 通过（跳过5个真实后端兼容套件）。

</details>

<details>
<summary>F-025 · P3 · 已确认 · 媒体服务器卡片 ID 依赖可变 link</summary>

- 审查单元与位置：M001-E；`MediaServerPlayItem.id` 与首页十秒刷新
- 触发路径：link 在轮询间变化，或 raw_id/link 缺失但 item_id/server_id 可用。
- 根因：即使存在稳定raw_id仍组合可变link；两者缺失时又忽略server_id/item_id并生成UUID。
- 用户影响：十秒刷新重建海报卡片并丢失焦点。
- 证据：当前Web有id时只用id；当前后端六个内置producer通常提供稳定原生id，但link可随host/playhost/token改变，schema全部字段仍可空
- 跨端结论：条件性P3；正常官方配置不变时通常不触发，第三方字段分布与真机焦点未验证
- 最小修改方向 / 裁决：规范非空raw_id优先；缺失时server_id+item_id、link、UUID依次兜底，不改Home轮询或新增身份架构。
- 修复状态：已完成（`8050051`）；按服务器类型作用域及raw→server/item→link→UUID优先级生成身份，分支标签与UTF-8长度前缀避免拼接碰撞，Simulator clean build与跳过真实后端兼容套件后的本地串行433/433测试及独立复审通过。

</details>

<details>
<summary>F-038 · P3 · 已确认 · 空白语言值穿透详情元数据</summary>

- 审查单元与位置：B006-A；TranslationHelper 与详情元数据拼接
- 触发路径：original_language 为 empty/空格/换行。
- 根因：模型接受任意非 nil 字符串，helper 原样回退，调用者只判 non-nil 就 append。
- 用户影响：尾随/空白分隔点，或创建空 Text 行。
- 证据：review_b006_a 闭合 decodeIfPresent→原样回退→append 链；verify_b006_a_retry 独立确认空 Text/尾随分隔及通用元数据范围
- 跨端结论：TV 展示不变量缺陷已确认；真实 payload 频率未验证
- 最小修改方向 / 裁决：元数据 builder 统一 trim/过滤空显示值，不只补语言分支；release_date/year/国家名一并回溯。

</details>

<details>
<summary>F-040 · P3 · 已确认 · 不同职位键翻译后重复显示</summary>

- 审查单元与位置：B005；JobRegistry/StaffManager/TranslationHelper
- 触发路径：同一人员同时携带两个 key，或重复记录分别携带。
- 根因：原始 key 阶段认为不同，翻译后都为“摄影”且不再去重。
- 用户影响：职员卡片显示“摄影/摄影”，未来职位分组也可能同名重复。
- 证据：review_b006_a 确认 Cinematography/Camera 同译与原 key 去重顺序；verify_b005 独立确认当前可见路径为职员卡片并收窄 Hero 边界
- 跨端结论：TV 显示缺陷已确认；真实 payload 组合未验证
- 最小修改方向 / 裁决：保留原始 key/优先级，在最终显示边界稳定去重；若产品要区分则改词表。

</details>

<details>
<summary>F-041 · P3 · 已确认 · 职位键变体绕过翻译与优先级</summary>

- 审查单元与位置：B005；Job key 到翻译/优先级链
- 触发路径：`director`、`Director\n` 或未登记同义别名。
- 根因：消费者仅 trim `.whitespaces`，没有共享 canonical key/alias。
- 用户影响：重要职位降为优先级 999 并显示原始文本，Hero 可能改选较低重要度职位。
- 证据：review_b006_a 闭合原样解码、精确查表与排序 999 路径；verify_b005 独立确认大小写/换行双重失配与 Hero 排序影响
- 跨端结论：TV 行为缺陷已确认；上游 canonical 词表未验证
- 最小修改方向 / 裁决：G07 单一 canonical job key 解析供翻译和优先级共用；未知保真并最低优先级。

</details>

<details>
<summary>F-043 · P3 · 已确认 · 空/畸形国家元素生成空白分隔符</summary>

- 审查单元与位置：B006-B；ProductionCountry 多态解码与详情拼接
- 触发路径：null/数字/布尔/数组/空对象，空白 code/name，或未知 code 无 name。
- 根因：不支持元素静默变 `(nil,nil)`，对象入口回退空串，View 仅判原数组非空就 map+joined。
- 用户影响：`2024 · `、空 Text 或 `中国 / `。
- 证据：review_b006_b_retry 闭合 nil模型→空显示→joined 链；verify_b006_b 独立确认叶子与内外分隔两层空值路径
- 跨端结论：TV 展示不变量缺陷已确认；真实 payload 未验证
- 最小修改方向 / 裁决：未知非空 code 保真；先在国家叶子层 trim/过滤再 `/` 连接，之后外层元数据再过滤并以 `·` 连接。

</details>

<details>
<summary>F-044 · P3 · 已确认 · 人物搜索绕过职位翻译</summary>

- 审查单元与位置：B005 复核新增 / B006-C；Search 人物行与 raw job
- 触发路径：搜索响应人物含 canonical `job`，如 Director。
- 根因：未经 StaffManager/TranslationHelper 处理，直接把 person.job 作为字幕。
- 用户影响：默认中文界面搜索显示英文 Director，而详情职员卡显示“导演”。
- 证据：verify_b005 独立确认 canonical Director 也会显示英文；verify_b005 后续 B006-C 主审重走 searchPerson→SearchView 旁路并支持
- 跨端结论：TV 旁路缺陷已确认；搜索响应 job 非空频率未验证
- 最小修改方向 / 裁决：人物职位展示走统一翻译边界，不在 View 手工词表。

</details>

<details>
<summary>F-045 · P3 · 已确认 · roles-only 职员跨展示不一致</summary>

- 审查单元与位置：B005 复核新增 / S006；StaffManager roles fallback 与 PersonCard
- 触发路径：Person 只有 roles，没有 job/character。
- 根因：getTopGroupedStaff 用 roles 兜底，processCrew 不投影 roles，卡片只读 job/character。
- 用户影响：Hero 显示职位，职员卡同一人无副标题。
- 证据：verify_b005 独立确认 Hero roles 兜底而 processCrew 不投影；verify_b006_b 作为 S006 主审确认触发边界与 PersonCard 旁路
- 跨端结论：TV 分支差异已确认；真实来源未验证
- 最小修改方向 / 裁决：在 StaffManager 统一 roles 到展示职位的投影，不在两个 View 分别补丁。

</details>

<details>
<summary>F-046 · P3 · 已确认 · 类型名未规范化且空结果进入详情元数据</summary>

- 审查单元与位置：B006-C；MediaGenre/translateGenre/详情元数据
- 触发路径：带空白/换行 canonical genre，或 null/数字/空对象/空名称元素。
- 根因：模型保留原字符串或宽容为空元素；翻译精确查表不 trim；View 只判数组非空就 joined/append。
- 用户影响：canonical 类型不翻译，空 Text、`电影 · ` 或尾随/重复分隔符。
- 证据：verify_b005 作为 B006-C 主审闭合多态解码、精确查表与 joined 链；verify_b006_c 独立确认 trim/filter 边界并收窄大小写/别名
- 跨端结论：TV 展示不变量缺陷已确认；真实输入频率未验证
- 最小修改方向 / 裁决：genre 叶子 `whitespacesAndNewlines` trim/filter，未知非空名称保真；内层 genre 和外层元数据均过滤空结果。

</details>

<details>
<summary>F-050 · P3 · 已确认 · Hero 演员先截断后去重</summary>

- 审查单元与位置：S006；MediaDetailViewModel Hero 演员截断
- 触发路径：前四条演员含同一 Person.id 多角色重复，后面还有不同演员。
- 根因：先 prefix(4) 再 processActors 去重；分页结果仅在 Hero 完全为空时替换。
- 用户影响：Hero 长期少于四名主演。
- 证据：verify_b006_b 闭合 prefix(4)→processActors 与分页替换条件；verify_s006 独立确认影响仅 Hero 并修正 W008-C 路由
- 跨端结论：TV 顺序缺陷已确认；真实重复分布未验证
- 最小修改方向 / 裁决：完整去重后取前四并保持服务端顺序。

</details>

<details>
<summary>F-051 · P3 · 已确认 · 头像排序与可渲染图片判定不一致</summary>

- 审查单元与位置：S006；StaffManager.hasAvatar 与 Person.imageURLs
- 触发路径：头像排序判定与实际可渲染图片不一致
- 根因：前者检查任意原始 profile_path/avatar/images 存在，后者按 source 严格选择可渲染 URL。
- 用户影响：最终只有占位图的人员可排在真正有头像人员之前。
- 证据：verify_b006_b 以 PersonDecoding 多组反例闭合；verify_s006 独立确认只影响 crew 新增项排序及 source-aware 反例
- 跨端结论：TV 排序规则缺陷已确认；真实来源组合未验证
- 最小修改方向 / 裁决：排序复用最终 `imageURLs.profile != nil` 判定。

</details>

<details>
<summary>F-052 · P3 · 已确认 · 多值 roles 整体降为未知优先级</summary>

- 审查单元与位置：S006；getTopGroupedStaff roles fallback
- 触发路径：roles `["Director","Writer"]` 且存在其他职位组。
- 根因：先 join 为 `Director/Writer` 再整体查 jobPriorityMap 得 999，翻译阶段却重新拆分。
- 用户影响：Producer 等次要职位可能压过包含 Director 的人员；空 roles 还造首尾 `/`。
- 证据：verify_b006_b 闭合 roles join→priority→translate split；verify_s006 修正为 roles fallback 两人反例并确认
- 跨端结论：TV 排序缺陷已确认；roles canonical 语义未验证
- 最小修改方向 / 裁决：roles 元素逐项规范化/过滤，取最小优先级后生成显示文本。

</details>

<details>
<summary>F-053 · P3 · 已确认 · mergeCrew 不能消费自身返回值</summary>

- 审查单元与位置：S006；mergeCrew 增量 API
- 触发路径：已翻译返回列表作为 existing，下一页同人再返回同一 raw job。
- 根因：canonical job 与显示文本复用同一字段，二次合并形成“导演/Director”再翻为“导演/导演”。
- 用户影响：未来启用 crew 分页后重复职位。
- 证据：verify_b006_b 构造 Director→导演/Director→导演/导演 链；verify_s006 独立确认条件性且当前无非空 existing 调用者
- 跨端结论：潜伏 API 缺陷已确认；当前无用户路径
- 最小修改方向 / 裁决：不用则删除增量语义；启用则 canonical/display 分离。

</details>

<details>
<summary>F-055 · P3 · 已确认 · 人物最佳结果使用 TMDB 专属头像准入</summary>

- 审查单元与位置：S006 复核新增 / M001-G；Search 最佳人物结果头像准入
- 触发路径：Douban 等来源有最终可渲染 avatar，但 profile_path nil，且其他评分不足。
- 根因：准入读取 TMDB 专属 `profile_path`，卡片实际使用 source-aware `imageURLs.profile`。
- 用户影响：有头像的人物被排除出最佳结果，但仍出现在人物行。
- 证据：verify_s006 以 Douban 有 avatar 无 profile_path 反例闭合；review_m001_g 独立重走 Douban 搜索、评分准入与卡片图片链
- 跨端结论：TV 跨来源准入差异已确认；Web 排名未验证
- 最小修改方向 / 裁决：准入复用最终图片可用性判定。

</details>

<details>
<summary>F-057 · P3 · 已确认 · 季集范围终点丢失或未校验</summary>

- 审查单元与位置：S003；ParsedSeason 范围解析/排序
- 触发路径：`S01-S12`、倒序集范围等。
- 根因：捕获第二季但从不读取；集范围不校验/规范化上下界。
- 用户影响：资源筛选范围项不按实际覆盖的最新季/集排序。
- 证据：verify_s006 作为 S003 主审构造季/集范围反例；verify_s003_resume 独立确认结束季捕获未消费及范围排序内部不一致
- 跨端结论：TV 排序行为可见；真实范围格式未验证
- 最小修改方向 / 裁决：明确范围语法并解析/校验终点，invalid 单独排序。

</details>

<details>
<summary>F-058 · P3 · 已确认 · 卡片与筛选排序季集语法不一致</summary>

- 审查单元与位置：S003；ParsedSeason 与 Formatters 两套语法
- 触发路径：E02、E01-E05、S01E01-10、S01-02。
- 根因：卡片支持无季号/省略第二标记，ParsedSeason 强制 S 开头且范围重复标记。
- 用户影响：能正确显示的值在筛选器落入无效零值组，顺序受 Set 迭代影响。
- 证据：verify_s006 对比两套正则及 Set 未指定顺序；verify_s003_resume 独立闭合两套正则与同一字段的显示/筛选链
- 跨端结论：TV 语法分裂已确认；上游格式未验证
- 最小修改方向 / 裁决：两处共享一个明确语法/解析结果，不重复维护不一致正则。

</details>

<details>
<summary>F-059 · P3 · 已确认 · 无效/溢出输入折叠为合法零值</summary>

- 审查单元与位置：S003；ParsedSeason invalid/overflow 状态
- 触发路径：`无`、超大季/集数、空白/附加文本等。
- 根因：无解析成功标志；失败字段继续为 0，集转换失败还会被当整季。
- 用户影响：畸形值与合法 S00E00 混组或排到具体集前。
- 证据：verify_s006 闭合 Int 安全失败与整季/无效分支；verify_s003_resume 独立确认无成功状态及零值多义性
- 跨端结论：TV 排序混淆已确认；真实畸形输入未验证
- 最小修改方向 / 裁决：显式 invalid 状态与稳定末尾排序，区分“没有 E”和“E 解析失败”。

</details>

<details>
<summary>F-060 · P3 · 降级 · 直接 `print` 绕过 Debug-only Logger</summary>

- 审查单元与位置：S001；Logger 与 15 个直接 print 生产文件
- 触发路径：Release 构建的鉴权、资源过滤、媒体服务器跳转或错误路径。
- 根因：默认 Logger 按设计只在 Debug 输出，但 80 个直接 `print` 绕过统一入口并在 Release 保留；无 bootstrap 本身不构成缺陷。
- 用户影响：Release 控制台可出现用户名、种子/媒体标题、过滤规则、服务器名、下载器 hash/client、媒体 ID、搜索词、后端消息和原始媒体服务器 URL；CustomFilter 逐条同步输出还有卡顿风险。
- 证据：integrate_i002 作为 S001 主审统计 35 Logger/80 print、确认个人数据与 bootstrap 缺失；verify_s001_resume 独立复算调用、Release 设置与实际输出值；无凭据泄漏证据，P2→P3
- 跨端结论：TV 本地旁路已确认；真实日志留存和凭据形态未验证
- 最小修改方向 / 裁决：复用现有 Logger 替换或删除直接 `print`，URL/error 复用现有 query 脱敏边界，并增加最小生产源码禁用 `print` 检查；不新增日志框架。

</details>

<details>
<summary>F-078 · P3 · 已确认 · 缺失/0/重复分享业务 ID 可破坏稳定身份</summary>

- 审查单元与位置：M001-I；SubscribeShare 列表身份
- 触发路径：`GET /subscribe/shares` 返回缺失、0、负数或重复分享 ID。
- 根因：raw_id 可选且不校验正值/唯一性；缺 ID 时用可变标题+用户，空值时随机 UUID，raw 0 则共享 `share:0`。
- 用户影响：不同分享被分页去重吞掉、SwiftUI 重复身份，或刷新后 ID 改变导致焦点跳动。
- 证据：review_m001_i 闭合 raw_id fallback、Paginator/ForEach 与兼容巡检盲点；verify_m001_i 独立确认列表丢项/焦点不稳，并驳回“Fork 错目标”的过宽影响
- 跨端结论：TV 稳定身份缺口已确认；分享 ID schema 未验证
- 最小修改方向 / 裁决：确认 schema 后，在分享快照边界要求唯一正业务 ID；非法记录采用明确过滤/拒绝策略，不以可变字段或 UUID 冒充持久身份。

</details>

<details>
<summary>F-090 · P3 · 已确认 · `tmdb_id == 0` 被当成有效识别结果</summary>

- 审查单元与位置：A001-D；TMDB 搜索/识别返回值
- 触发路径：`/media/search` 或 `/media/recognize` 返回 tmdb_id 为 0/负数，后续候选或 fullDetail 又有正 ID。
- 根因：四个成功出口只用 if-let，非法值立即返回；下游还用原始 `recognized ?? fullDetail`，未复用正 ID 校验。
- 用户影响：无效值遮蔽正候选并构造 `tmdb:0`/负数详情、预加载、订阅补查或新订阅预填。
- 证据：review_a001_d_retry 闭合四个成功出口、动作/预加载调用者与测试盲点；verify_a001_d 独立确认非法值立即返回并可遮蔽 fullDetail 正 ID
- 跨端结论：TV 正 ID 边界不一致已确认；真实输入未验证
- 最小修改方向 / 裁决：识别循环逐候选复用 validNumericIdentifier，非法值继续查找；下游候选先过滤再排序。不得顺带全局修改 MediaInfo identity 的既有 Web-zero 语义。

</details>

<details>
<summary>F-101 · P3 · 已确认 · SSE 多 data 行未按事件组帧</summary>

- 审查单元与位置：A001-H→V011-C；`APIService.streamSSE` 与 Search 等消费者
- 触发路径：服务端发送一个由多条 `data:` 行组成、以空行结束的合法 SSE 事件。
- 根因：生产解析器和兼容探针均按物理行立即 JSON 解码，没有按空行组帧并合并同一事件的 data 内容。
- 用户影响：资源流可误判 malformed 后进入 fallback；AI 进度监控可失败，而后台任务仍可能继续。
- 证据：review_a001_h 核对生产解析器、兼容探针、Search fallback 及全部单行桩；verify_a001_h 用独立 Foundation/JSON 探针确认逐行失败、换行拼接成功，且现有 fixture 全为单行
- 跨端结论：TV framing 缺口已确认；当前后端单行/heartbeat/Content-Type 契约未验证
- 最小修改方向 / 裁决：只在共享 `streamSSE` 中按空行组帧、合并 data 后解码一次，并让兼容探针复用同一规则。

</details>

<details>
<summary>F-105 · P3 · 已确认 · 相对图片值未规范化为绝对 URL</summary>

- 审查单元与位置：A001-K；`APIService.swift:166-200,2519-2552,2596-2600,2618-2647`
- 触发路径：海报、背景、订阅分享或人物字段返回 `/api/...`、`images/...`，或绝对 URL 前后带空白。
- 根因：共享 `displayImageURL` 不 trim；非 HTTP 字符串直接交给 `URL(string:)`，相对 URL 没有绑定后端 origin。
- 用户影响：媒体、订阅、下载或人物卡片显示占位图或加载失败。
- 证据：review_a001_j 对照生产 displayImageURL 与兼容 oracle，并追到媒体/订阅/下载/人物卡片；verify_a001_h 用独立 Foundation 探针确认相对 URL 保持无 host、空白绝对 URL 为 nil，并收窄 oracle 身份
- 跨端结论：TV 图片 URL 规范化缺口已确认；当前 Web/后端 origin 契约与真实频率未验证
- 最小修改方向 / 裁决：只在共享 `displayImageURL` trim、拒绝空白，并按确认后的 MoviePilot origin/path-prefix 语义绝对化，再执行既有代理规则；不在模型/View 分散处理。

</details>

<details>
<summary>F-114 · P3 · 已确认 · 父 ViewModel 未转发 SiteFilter 子对象变化</summary>

- 审查单元与位置：V003；`SearchViewModel.swift:270,658-668`、`MediaDetailViewModel.swift:40,122-133` 及对应 View
- 触发路径：首帧以默认选择 `{1}` 显示“1 个站点”，随后 SiteFilter 成功加载并把它解析为站点名；或加载后把失效 ID 归一化为空。
- 根因：两个父 ViewModel 以 `@Published` 固定持有子 `ObservableObject`，但父 View 只观察父对象；属性包装器不递归转发子对象事件，而两处现有 Paginator 桥接证明项目已依赖显式转发。
- 用户影响：按钮可继续显示初始计数或旧选择，直到焦点、Sheet 或其他父状态触发无关重绘；实际请求读取子对象当前 `sitesString`，因此本项收窄为 UI 新鲜度。
- 证据：verify_a001_h 闭合两个固定子对象、父 View 观察关系及 Paginator 已桥接反证；review_a001_h 独立确认成功非空即可触发，实际请求读取子对象当前值并收窄为 UI 新鲜度
- 跨端结论：纯 TV SwiftUI 观察缺陷已确认；无关重绘前实际可见时长未运行验证
- 最小修改方向 / 裁决：复用现有 Paginator 桥接模式，仅把固定 `siteFilter.objectWillChange` 转发给两个父 VM；不引入新状态框架。

</details>

<details>
<summary>F-117 · P3 · 已确认 · 取消早于图片 handle 安装时仍启动不可取消请求</summary>

- 审查单元与位置：V004-A；`MediaPreloader.swift:95,123-169` 图片预取取消链
- 触发路径：预取 timeout 的 group cancel、LRU 淘汰或 logout/显式 clearAll 在图片 child 已继承取消、但 Kingfisher DownloadTask handle 尚未安装时发生。
- 根因：取消 handler 先看到 nil handle 并恢复 continuation；operation 仍启动 retrieveImage 后才保存 handle，而方法/组已返回并把 handle 清空，取消状态与 handle 安装不原子。
- 用户影响：已取消的图片请求仍可下载并写共享缓存；注销时可能继续携带旧 Cookie，放大 F-019/F-020，但本项不依赖账号隔离问题成立。
- 证据：verify_a001_h 闭合已取消 child、onCancel 先恢复、operation 后启动请求与 handle 清空时序；review_a001_h 独立确认 Swift/Kingfisher 顺序、真实取消入口、缓存写入与取消后 ready 发布
- 跨端结论：TV 资源/生命周期缺陷已确认；真实竞态频率及注销传播未运行验证
- 最小修改方向 / 裁决：扩展现有锁盒同时保存 continuation、取消标记与 handle，operation 内二次检查，handle 安装时若已取消立即 cancel；ready 发布前再检查父 Task，不重构下载层。

</details>

<details>
<summary>F-122 · P3 · 已确认 · nullable TMDB 识别结果折叠失败、取消与无匹配</summary>

- 审查单元与位置：V005；`APIService.recognizeTmdbId`、`MediaActionHandler` 及 Home 标题回退
- 触发路径：两阶段识别发生请求/鉴权/解码失败或取消；或者确实没有匹配。Home 资源搜索还会把 nil 当成正常标题回退并继续导航。
- 根因：`recognizeTmdbId` 用一个 `Int?` 表示空标题、无匹配、类型不符、错误与取消，通配 catch 吞掉失败；Handler 又把所有 nil 无条件发布为全局“不存在”弹窗。
- 用户影响：最终网络/会话错误或取消被误报为媒体不存在；Home 随后仍提交标题回退导航，因此同一动作同时写 alert 与 navigation 状态。首段失败但 fallback 最终成功时用户获得有效 ID，本身不算用户缺陷。
- 证据：review_a001_j 闭合两阶段识别、通配 catch、全局弹窗与标题回退继续导航；review_a001_h 独立确认最终 error/cancel→nil→不存在弹窗，并收窄首段失败但 fallback 成功不算用户缺陷
- 跨端结论：纯 TV 错误语义缺陷已确认；Home 真 no-match 提示产品意图未验证
- 最小修改方向 / 裁决：复用 Swift `throws` 保留 error/cancel，让 nil 仅表示成功完成两阶段后的真正 no-match；若保留首段失败后继续 fallback，暂存首段错误，fallback 成功可返回 ID，fallback 也无结果时不得伪装 no-match。详情动作才按真 no-match 呈现不存在，Home 标题回退不强制发该弹窗。

</details>

<details>
<summary>F-125 · P3 · 已确认 · v2.15.1 Plex 链接形状未被 Home 解析</summary>

- 审查单元与位置：V008；Home Plex link 解析与 v2.15.1 版本快照
- 触发路径：媒体服务器 latest 返回 `web/index.html#!/server/{machine}/details?key={item_id}&X-Plex-Token=...`，用户从 Home 打开该 Plex 卡片。
- 根因：TV 仅识别 fragment 首段为 `/media/...` 的旧形状；本项目声明版本的后端生成 `/server/.../details?key=`，同版本 Web 已专门解析该形状。
- 用户影响：TV 退化为无目标参数的 generic `plex://`，machine/item 身份在构造阶段已经丢失；不能据此宣称第三方 Plex App 最终一定无法打开或某个修正 scheme 一定可精确落点。
- 证据：verify_a001_h 以本地 v2.15.1 tag 闭合后端生成、Web 解析与 TV fallback；review_a001_j 独立确认 latest/resume 链、Plex 无结构化 ID 时只能从 link 恢复身份，并限制第三方 scheme 结论
- 跨端结论：版本特定 TV 深链缺陷已确认；tvOS Plex 精确 scheme 未验证
- 最小修改方向 / 裁决：在现有 URLComponents 分支同时兼容 `/server/{machine}/details?key=` 与旧 `/media/...`，提取 machine/item ID，规范化纯数字 key 与已含 `/library/metadata/` 的 key，并保留 generic fallback；先补纯 URL 构造测试，不新建 deep-link 层。

</details>

<details>
<summary>F-128 · P3 · 已确认 · 媒体库跳转失败只有日志而无用户反馈</summary>

- 审查单元与位置：V008；Home 媒体库跳转、unsupported/invalid/openURL rejected 出口
- 触发路径：Jellyfin、飞牛、绿联、极空间或未知服务器类型；链接非法；第三方 App 未安装或系统拒绝打开。
- 根因：调用者始终暴露并触发同一动作，但方法没有可消费的结果；unsupported、invalid 与 rejected 均只 return/print。
- 用户影响：用户点击看似可用的卡片或菜单后没有任何解释，无法区分未支持、数据坏或 App 缺失。
- 证据：verify_a001_h 闭合各服务器分支与调用者无返回值/错误出口；review_a001_j 独立确认主动作/菜单始终暴露及异步 openURL completion 无用户出口
- 跨端结论：纯 TV 动作反馈缺陷已确认；第三方 App 能力未验证
- 最小修改方向 / 裁决：能力静态已知时隐藏不支持动作；其余 invalid/unsupported 通过小型 outcome、系统 `openURL` 拒绝通过异步 completion/callback 返回同一失败出口，复用 NotificationManager 的用户触发错误反馈。不能只同步返回 Bool，也不建跳转框架。

</details>

<details>
<summary>F-132 · P3 · 已确认 · TMDB 类型切换保留另一类型独占排序键</summary>

- 审查单元与位置：V009-D/E；TMDB movie/tv sort 字典与类型切换
- 触发路径：电影选择 `release_date.desc/asc` 后切电视剧，或电视剧选择 `first_air_date.desc/asc` 后切电影。
- 根因：类型切换只清 genre，不校验 `tmdbSortBy` 是否仍属于新的 `currentSortDict`；Picker 已无匹配 tag，请求却继续携旧 key。
- 用户影响：UI 排序选择与实际状态不一致，且请求把电影独占字段发到 TV endpoint 或反向发送；后端拒绝、忽略或降级行为未验证。
- 证据：review_a001_h 闭合双向独占 key、onTypeChanged 与 buildApiPath 链；review_a001_j 独立确认纯 TV 状态分裂且独立于 F-110；verify_a001_h 从构建段确认双向路径及 Web normalization 参考
- 跨端结论：纯 TV 状态一致性缺陷已确认；后端处理非法 key 未验证
- 最小修改方向 / 裁决：仅在 TMDB 类型切换后检查新 sort 字典；现值不存在时回落现有 `popularity.desc`，保留 `popularity.*`/`vote_average.*` 等共有选择，非 TMDB 不改隐藏状态。

</details>

<details>
<summary>F-135 · P3 · 已确认 · 未规范化 option value 形成重复 Picker 身份</summary>

- 审查单元与位置：V009-A/F→W012；Picker option value/身份规范化
- 触发路径：插件两个标签共享JSON value；或公开Directories含`nil`之外的空/空白`download_path`。
- 根因：option value同时承担ForEach ID和Picker tag，却未在输入边界规范化/去重。AddDownload仅排除nil，本地空串与内建自动都生成`""`，远程空串生成`storage:`。
- 用户影响：SwiftUI diff、焦点和选择标签可不稳定；目录还会显示无效项并在提交时被后端拒绝。不会写入错误目录，故维持P3。
- 证据：插件链三代理确认机制；W012双审与当前Web/后端裁决确认空/空白download_path生产可达；插件first-wins去重；目录trim后丢空再去重并保留唯一自动项
- 跨端结论：条件性P3；真实插件重复value频率仍未验证
- 最小修改方向 / 裁决：插件在`collectOptions`按JSONValue first-wins；目录在生成URI前trim并丢空，再去重并保留唯一自动项。不新增option ID层。

</details>

<details>
<summary>F-140 · P3 · 已确认 · 尾随空白让精确搜索标题退化为不匹配</summary>

- 审查单元与位置：V011-B；搜索提交 query 与本地最佳结果评分
- 触发路径：用户提交 `Hamilton `；目标后端按 trim 后的 `Hamilton` 搜到结果，TV 用原始含尾随空格字符串对结果重新评分。
- 根因：搜索请求与本地最佳结果评分未复用一次性规范化后的同一字符串；TV 还会让纯空白进入后续搜索边界。
- 用户影响：精确标题 `Hamilton` 得 `-1`，`Hamilton Musical` 反因包含尾随空格而获前缀高分，最佳结果顺序错误并可能触发 top-12 淘汰。
- 证据：verify_a001_h 以 `Hamilton ` 闭合后端 trim→TV 原字符串评分→top-12 链；review_a001_j 独立复算 exact `-1`/extended `484`、换行与纯空白请求路径
- 跨端结论：搜索 canonical query 缺陷已确认；真实输入频率未验证
- 最小修改方向 / 裁决：若独立复核确认，在提交搜索时只做一次 `.whitespacesAndNewlines` 规范化，并让后端请求与本地评分共用；纯空白不发请求，不引入解析器。

</details>

<details>
<summary>F-141 · P3 · 已确认 · 四位数字片名被误当成搜索年份</summary>

- 审查单元与位置：V011-B；搜索年份提取与目标版本后端标题解析
- 触发路径：查询 `1917 2019`、`1917 (2019)` 或仅四位数字片名等年份边界输入。
- 根因：TV 取首个任意 `(19|20)\d{2}` 为年份；目标 v2.15.1 后端只把前有空白或左括号的四位数字识别为年份，因此 `1917 2019` 在后端是 title=`1917`/year=`2019`，TV 却先取 `1917` 为年份。
- 用户影响：正确结果 title=`1917`、year=`2019` 被判年份不符且禁止无年份回退，得到 `-1`；错误项可反超或将其挤出最佳 top-12，普通分类行仍可能显示。
- 证据：verify_a001_h 以 `1917 2019` 闭合后端 title/year 与 TV score 分裂；review_a001_j 独立复算数字片名、括号残留与版本特定词法边界
- 跨端结论：条件性搜索解析 P3已确认；当前部署未验证
- 最小修改方向 / 裁决：若独立复核确认，在 F-140 的同一规范化 query 上复用目标后端等价的年份边界；不把开头四位数字片名直接当年份，不新建通用 query parser。

</details>

<details>
<summary>F-159 · P3 · 已确认 · 五秒错误通知没有可访问性主动播报</summary>

- 审查单元与位置：C002；全局短暂错误通知的可访问性传达
- 触发路径：VoiceOver用户遇到登录、删除、订阅等错误，producer调用全局toast并清除自身error。
- 根因：toast仅插入Image+Text并五秒自动移除；全仓没有`AccessibilityNotification`/UIAccessibility announcement或等价主动播报，也未把装饰icon隐藏并将类型+消息组合成单一可访问元素。5个生产文件共有6个直接show；其中三条onChange producer会随即清自身错误，Home无持久错误，SubscriptionHandler只以serial保留事件性。
- 用户影响：即使不存在F-108的Sheet视觉遮挡，VoiceOver用户也可能完全错过唯一错误反馈；实际漏听频率未运行验证。
- 证据：review_a001_h主审与review_a001_j独立复核确认5文件6个生产show、根唯一presenter、全仓无announcement且tvOS17原生API可用；G08及调用页回溯逐次type+message播报、同文案重发与单一元素语义
- 跨端结论：实际VoiceOver/盲文漏传频率未验证
- 最小修改方向 / 裁决：在现有NotificationManager每次真正接受`show`时逐次发布“类型+消息”announcement；不能只监听message变化，否则同文案主动重试不播。icon设为装饰、通知组合单一元素，不抢焦点、不建通知框架。

</details>

<details>
<summary>F-169 · P3 · 已确认 · ShelfPicker 只视觉标记当前选择</summary>

- 审查单元与位置：C007；ShelfPicker持久选择的可访问性语义
- 触发路径：VoiceOver用户在Recommend货架chip间移动焦点，但尚未激活新货架。
- 根因：私有`isSelected`只控制视觉overlay；Button/Text提供名称和动作，却没有`.isSelected` trait或等价value，focus与持久selection是两种状态。
- 用户影响：用户能听到并激活货架名称，但不能可靠判断当前哪个货架正在驱动下方结果；视觉高亮和通常回到selected shelf是最强反例，故不升级P2。
- 证据：review_a001_j主审与verify_a001_h独立复核确认唯一Recommend调用、focus/selection分离及默认Button仅有名称/动作语义；W005/G02/G04回溯一行条件isSelected trait与VoiceOver验收
- 跨端结论：真实困惑频率/播报措辞未验证
- 最小修改方向 / 裁决：在现有Button上一行条件添加`.isSelected` trait，不加自定义label/value、selection或focus框架。

</details>

<details>
<summary>F-172 · P3 · 已确认 · 未知类型缺图时误显示电影图标</summary>

- 审查单元与位置：C009-B→W006-D；卡片缺图占位类型
- 触发路径：海报nil、加载中或失败，typeText为nil/空/未知/业务状态文本。
- 根因：`typeIconMap[typeText ?? ""] ?? "film"`把所有未知输入统一解释为电影。
- 用户影响：Home电视剧订阅把typeText传“新/阅/待/停”，季卡固定传nil；缺图/加载中仍显示电影glyph，误导内容类型。已知电影/电视剧/合集分别命中正确映射，是明确反证边界。
- 证据：双审确认MediaCard生产链；W006-D双审补collection_id有效但nil/英文/系列类型仍导航合集却显示电影glyph；各卡片/调用页/G03回溯中性glyph与统一displayTypeText测试
- 跨端结论：缺图/加载中触发频率未验证
- 最小修改方向 / 裁决：未知/nil使用中性`photo`或`rectangle.portrait`，保留三种已知映射，不新增占位组件/类型框架。

</details>

<details>
<summary>F-178 · P3 · 已确认 · 最佳结果评分候选名与卡片展示名分裂</summary>

- 审查单元与位置：C012→W006-C；搜索评分名与展示名投影
- 触发路径：媒体或人物只有备用名称非空；该备用名与规范短query精确匹配并使对象进入最佳结果。
- 根因：评分会消费媒体`original_title/original_name/names`与人物`latin_name/original_name/also_known_as`，卡片却只显示`media.cleanedTitle ?? ""`或`person.name ?? "未知"`；Manual展示同样只消费主title。
- 用户影响：结果身份与激活有效，但用户及VoiceOver无法从原生Button文字语义识别实际命中名称；subtitle、图片或来源可能提供旁证，故不升级严重度。
- 证据：C012双审闭合媒体original_title与人物latin_name反例；W006-C双审确认普通行同根传播；评分与展示共用现有有序非空名称候选；不建新匹配或卡片框架
- 跨端结论：条件性P3；真实备用名payload频率未验证
- 最小修改方向 / 裁决：让评分和展示复用同一组已规范化、去空白的有序名称候选并取首个非空值；Manual复用同一媒体名称投影，不新增匹配框架或卡片模型。

</details>

<details>
<summary>F-190 · P3 · 已确认 · 季详情名称与可选文本未统一归一化</summary>

- 审查单元与位置：W013-C；SeasonDetailSheet季名与可选文本投影
- 触发路径：真实S00的name为nil，或name/air_date/overview为可解码空串、纯空白或换行。
- 根因：季名只做nil coalescing，空白值不会回退；nil名称的S00又直接格式化成“第0季”。日期与overview仅检查Optional存在，不检查规范化后是否为空。
- 用户影响：同一页面的季卡把S00显示为“特别篇”，详情却显示“第0季”；空白名称会产生空标题，空白日期产生只有图标的行，空白简介保留无意义区域。
- 证据：review_a001_h主审与verify_a001_h独立复核闭合nil/空/纯空白输入及同页文案分裂；复用现有字符串trim→nil；S00/有效季/缺季号使用一套回退规则
- 跨端结论：TV显示不变量缺陷已确认；真实空白payload频率未验证
- 最小修改方向 / 裁决：复用现有字符串trim/空转nil；一套回退规则覆盖S00“特别篇”、有效正季号“第N季”、缺失/非法季号“未知季”，日期和overview仅在归一化非空后显示。不建季显示模型。

</details>

<details>
<summary>F-191 · P3 · 已确认 · 详情 Sheet 海报缺少稳定的 2:3 布局约束</summary>

- 审查单元与位置：W013-C→W015；SeasonDetail/Fork Sheet海报容器几何
- 触发路径：季海报与媒体回退海报均无有效URL，或图片加载最终失败。
- 根因：Kingfisher processor使用`360×540`只决定图像处理参考尺寸，不是SwiftUI外层几何约束；图片和`ZStack`只设置`width: 360`，失败/缺图后只剩没有固定540高度或2:3比例的`Rectangle`。
- 用户影响：缺图、loading、失败与成功四态不能保证保持相同海报占位，具体Sheet proposal可令占位塌缩、拉伸或在状态切换时跳变。当前证据只证明局部布局退化，未证明正文或操作不可达，故P3。
- 证据：W013-C第三裁决成案；W015主审独立确认Fork的URL缺失/loading/失败/成功四态同根；两个Sheet外层容器直接固定360×540；覆盖四态
- 跨端结论：静态布局契约缺陷已确认；实际塌缩/拉伸形态与焦点影响未验证
- 最小修改方向 / 裁决：直接给两个现有Sheet的海报外层容器`.frame(width: 360, height: 540)`，继续复用当前processor、clip和占位；不抽取新组件。

</details>

<details>
<summary>F-207 · P3 · 已确认 · 手动重登成功后连接信息仍停留在旧快照</summary>

- 审查单元与位置：W020-C；重登成功后的连接信息新鲜度
- 触发路径：首次系统信息加载失败/版本未知，或后端版本、服务地址、用户名随后变化；用户在连接页执行手动重登且收到成功反馈。
- 根因：System根`.task`只调用一次`loadSystemInfo`；手动重登成功只发布刷新反馈，没有再次加载`serverURL/username/backendVersion`，System局部状态也不观察Content的权威settings变化。
- 用户影响：页面明确说连接已刷新，却继续展示旧版本或“未知”等旧连接信息，直到`SystemView`重建；不会阻断已成功的登录，故主审建议P3。
- 证据：review_a001_j与verify_a001_h双审闭合单次根task、重登成功及局部版本无后续写入；获胜session epoch重登成功后复用现有loadSystemInfo或直接消费权威settings/currentUser
- 跨端结论：纯TV新鲜度缺陷；真实重建/可见时序未验证
- 最小修改方向 / 裁决：获胜session epoch的重登成功后复用现有`loadSystemInfo`，或让连接页直接消费已存在的权威settings/currentUser；不新增第二套连接状态。

</details>

<details>
<summary>F-208 · P3 · 已确认 · System 页面切换动画未尊重“减少动态效果”</summary>

- 审查单元与位置：W020-B/F→I016；System导航减少动态效果
- 触发路径：系统已开启“减少动态效果”，用户选择进入子页、按Menu/Back返回，或在根页执行Back滚动。
- 根因：push/pop无条件使用`withAnimation`执行0.42s、约824pt横向位移，延迟清理也按固定时长推进；根页Back另固定动画滚动0.24s。没有读取原生`accessibilityReduceMotion`环境值。
- 用户影响：明确请求减少运动的用户仍看到大幅横向移动；静态违反偏好成立，实际不适程度与真机渲染待验证。
- 证据：既有三审及I016两代理均确认同根并维持P3；读取原生Reduce Motion环境；开启时立即切换或淡化，并让清理等待跟随实际时长
- 跨端结论：真机体感与系统是否代抑制未验证
- 最小修改方向 / 裁决：读取`accessibilityReduceMotion`；开启时立即切换或使用非位移淡化，并让清理等待复用实际持续时间，不抽象动画协调器。

</details>

<details>
<summary>F-217 · P3 · 已确认 · 条件 Exit modifier 令离场子页重建并重启任务</summary>

- 审查单元与位置：W020-G；条件Exit modifier改变离场页结构身份
- 触发路径：用户从推荐设置页按Back；`route`先回root而`displayedRoute`继续保留旧页约0.43秒，旧页`isActive`立即由true变false。
- 根因：helper以`@ViewBuilder if/else`在带`onExitCommand`和裸`Self`两种结构分支间切换；同一ForEach ID不阻止modifier分支改变SwiftUI structural identity，旧页生命周期结束而新分支重新出现。
- 用户影响：离场推荐页的旧task被取消，新分支又无意义启动`refreshSources()`，随后页面删除再次取消；其他子页的滚动/focus子树也会重建，但后两项真实可见结果仍待运行。若重复请求只在取消前不产生状态/流量后果，严重度可下调。
- 证据：三代理确认机制；第三裁决按只读GET、StateObject保留降P3，但稳定modifier修复独立于通用task owner；恒定保留同一onExitCommand modifier类型，禁用时传nil或在action内guard；root不吞Exit
- 跨端结论：纯TV P3；重复请求/自动重连与滚动/focus体感待运行
- 最小修改方向 / 裁决：只按稳定页面角色决定是否安装modifier；非root子页恒定安装`onExitCommand`，把`isSelected && isActive`移入action guard，root保持不安装。不建导航或modifier框架。

</details>

<details>
<summary>F-218 · P3 · 已确认 · 已存会话启动时准备门晚于首个认证分支</summary>

- 审查单元与位置：R001；已存会话启动准备门晚于认证首帧
- 触发路径：本地已有非空token，应用冷启动；ViewModel初始即判为已登录，但准备态固定false。
- 根因：首个body先进入authenticated TabView分支，只有视图挂载后的`.task`调用恢复流程时才把`isPreparingStartupSession`设true。
- 用户影响：旧权限Tab子树与Home加载循环可在准备遮罩建立前被构造，旧权限警告也可能抢先呈现；静态顺序确定，但SwiftUI是否提交该中间帧或启动子task仍需运行/挂载测试，因此保持条件性P3。
- 证据：三代理确认静态入口；第三裁决确认其与F-106出口窗口、F-130/CHK-005异步owner均不可互替；初始化准备态与已存token同步，必要settings完成或明确失败策略后再统一清门
- 跨端结论：条件性P3已确认；真实认证帧/Home task启动待运行验证
- 最小修改方向 / 裁决：初始化准备态与“存在待恢复token”同步；在唯一恢复流程的成功、失败、取消出口统一清除。复用现有状态，不新增bootstrap coordinator。

</details>

<details>
<summary>F-228 · P3 · 已确认 · 人物详情未显示已解码备用名</summary>

- 审查单元与位置：G07→F-178拆分裁决；人物详情备用名展示投影
- 触发路径：人物具有非空`latin_name`或`also_known_as`，主名不同或本地用户需靠别名辨识。
- 根因：备用名已解码并参与Search匹配，但详情只显示name/original_name；F-227的稀疏覆盖还可先清掉seed别名。
- 用户影响：详情与搜索命中依据不一致，用户无法看到当前Web已展示的备用名；主名仍在时不阻断route。
- 证据：G07双审确认TV/Web展示差异，verify_a001_h第三裁确认独立详情投影并下调P3；先按F-227保真，再用有序去空去重displayAlternateNames显示
- 跨端结论：TV详情投影缺口已确认；真实别名频率与排版未验证
- 最小修改方向 / 裁决：先按F-227保真，再构造去空、去重、排除主名的有序`displayAlternateNames`；不新增人物展示框架。

</details>

<details>
<summary>F-229 · P3 · 已确认 · MultiSelection 的“确认”与 Menu/Exit 没有不同提交语义</summary>

- 审查单元与位置：G10；MultiSelection确认与Exit语义不一致
- 触发路径：用户在多选Sheet切换选项后，不点“确认”而按Menu/Exit关闭。
- 根因：Toggle立即修改外部binding，“确认”只执行dismiss；部分caller又在onDisappear无条件应用选择，使确认与系统退出没有事务差别。
- 用户影响：若文案让用户把Menu理解为取消，未确认选择仍被保留/提交；若产品本就采用即时生效，当前“确认”文案虚构了不存在的提交边界。
- 证据：review_a001_h主审与verify_a001_h独立复核闭合三类caller并排除数据丢失/越权写入；即时生效合同下仅改“完成”；产品要求取消时才加局部draft
- 跨端结论：TV交互文案缺口已确认；Menu产品预期未验证
- 最小修改方向 / 裁决：先定单一产品合同。即时生效则按钮改“完成”并明确Exit也是完成；确认提交则组件内保留局部draft，只在确认时写回。两种都不需新协调器。

</details>

<details>
<summary>F-242 · P3 · 已确认 · System 动态长名称没有完整可辨识入口</summary>

- 审查单元与位置：I016；System站点/规则长名称缺完整可辨识入口
- 触发路径：两项合法站点或规则长名称共享足够长前缀，差异只在单行可视尾部；用户聚焦其中一项。
- 根因：站点/规则title明确固定单行，preview只显示通用说明或规则条件，不回显完整名称；视觉层没有第二个可读入口。推荐Toggle没有显式lineLimit，不能静态泛化。
- 用户影响：纯视觉用户可能无法区分当前选择的是哪一站点/规则；原生Text/Toggle仍持有完整源字符串，不能静态扩大为VoiceOver不可达。
- 证据：I016两代理确认站点/规则视觉链；推荐截断与VoiceOver扩大说法未确认；preview显示完整名称或允许两行；不新建长文本组件
- 跨端结论：条件性TV视觉缺陷；推荐、具体阈值与VoiceOver待运行，程序限制披露
- 最小修改方向 / 裁决：聚焦动态项时在现有preview首行显示完整名称，或允许标题两行；不建长文本组件。

</details>

## 4. 已驳回候选

共 17 项。账面 P 级只保留原候选风险定位，不代表当前确认缺陷；每项的最终裁决用于防止重复误报。

<details>
<summary>F-013 · P2 · 已驳回 · `MediaInfo` 无正式清单声称的 legacy `mediaid` 回退</summary>

- 审查单元与位置：M001-A/M001-D→当前Web/后端合同复核；`Models.swift:578-1213`
- 触发路径：假设上游返回只有legacy `mediaid`、没有结构化身份的`MediaInfo`。
- 根因：原候选缺少上游合同；当前官方Web类型/helper与后端响应schema均不支持这种对象。
- 用户影响：原兼容前提不成立；给TV单独增加fallback反而形成跨端差异化兜底。
- 证据：Web v2.15.5详情、搜索、下载、订阅入口均从结构化身份生成请求键；路由/API同名`mediaid`参数不是payload字段。
- 跨端结论：当前TV缺陷驳回；正式清单中的旧现状声明应删除，用户决定跳过产品修复。
- 最小修改方向 / 裁决：不改产品代码，不新增legacy字段；仅把CHK-002收口为文档现状修订建议。

</details>

<details>
<summary>F-014 · P3 · 已驳回 · 空白来源前缀遮蔽有效来源</summary>

- 审查单元与位置：M001-D→G02；来源选择的空白prefix回退
- 触发路径：`mediaid_prefix` 仅含空白，`source` 是有效 douban/bangumi/anilist，且没有对应专用 ID。
- 根因：当前规范化会trim并丢弃空白`mediaid_prefix`，随后继续采用有效`source`；原遮蔽链不再成立
- 用户影响：原命题在当前HEAD不产生用户缺陷。
- 证据：G02主审及两名不同纠偏复核均按当前HEAD确认反证，旧M001-D结论被覆盖；无生产修复；只补空白prefix＋有效source回归
- 跨端结论：当前TV缺陷驳回；上游来源优先级合同未验证
- 最小修改方向 / 裁决：不改生产代码；只补“空白prefix＋有效source”精确回归测试。

</details>

<details>
<summary>F-016 · P3 · 已驳回 · 用户决定跳过修复 · 大小格式输出仍由系统自适应</summary>

- 审查单元与位置：B002；`Formatters.swift:6-18` 及大小调用者
- 处置：用户决定跳过修复。
- 触发路径：显示非整数 KB/MB、零值或在不同 locale 下显示大小。
- 根因：只设置 `.binary` 与单位集合；精度、零值自然语言和 locale 仍使用 ByteCountFormatter 默认。
- 用户影响：不同单位/locale 的小数位和零值文本不一致，DownloadTask 的 nil `"0 B"` 还可能与真实零值不同。
- 证据：B002 主审核对 SDK 默认与 13 个调用表达式；verify_b002 证明这是注释承诺范围内的 Apple 本地化取舍
- 跨端结论：仅在未来明确固定 Web 文案契约时重开
- 最小修改方向 / 裁决：代码只承诺 1024 基数，`.binary` 已满足；自适应精度、自然语言零值与 locale 是 Apple 明确的本地化默认，且没有业务反向解析。

</details>

<details>
<summary>F-056 · P3 · 已驳回 · Hero 演员不滤空名且不补位</summary>

- 审查单元与位置：S006→G07→F-050；Hero 演员姓名展示
- 触发路径：首四项包含 nil/空 name，后面有正常演员。
- 根因：只按数组非空，nil 渲染时丢弃、空字符串参与连接，分页完成后不补非空但不足列表。
- 用户影响：空“主演”或少于四人。
- 证据：既有双审确认；G07第三裁将重复、空名和补位合成一个Hero选人根因；并入F-050，不驳回机制；全量processActors后过滤空名再prefix(4)
- 跨端结论：驳回重复编号；真实人物分布未验证
- 最小修改方向 / 裁决：按可展示非空姓名过滤/去重后截断，后续完整结果可补位。

</details>

<details>
<summary>F-153 · P3 · 已驳回 · 删除与在途分页错位可永久漏掉边界记录</summary>

- 审查单元与位置：V022-B→G09；TransferHistory删除与Paginator游标协调
- 触发路径：已加载page1的1…20且page2 GET在途；随后删除ID20，服务端先处理DELETE再返回移位后的page2。
- 根因：删除与在途loadMore未协调；page2先发布22…41并把游标推进3，删除成功只让下一次loadMore回退到2，无法回到page1补已移位的ID21。批删还在整个循环末才累计shift，扩大窗口。
- 用户影响：回退后的page2全是已见重复，ID21可永久缺失；轮询在首个已知ID处停止也不能补回，只能等待完整refresh。
- 证据：早期双审反例被G09两名代理按`ceil(deleted/pageSize)`与最多两页重复扫描重新推演反驳；不改算法；补删除+插入+loadMore集成测试，排序不稳定归F-232，ID复用归F-204
- 跨端结论：当前独立缺陷驳回；真实集成行为仍作P3测试缺口
- 最小修改方向 / 裁决：不修改现有分页算法；仅补删除、插入与loadMore交错的集成回归测试。排序不稳定归F-232，同ID复用归F-204。

</details>

<details>
<summary>F-154 · P3 · 已驳回 · 插入余数跨已完成 loadMore 重复累计可跳页</summary>

- 审查单元与位置：V022-C→I009/G09；TransferHistory轮询插入余数与loadMore游标
- 触发路径：初始O1…O20/page2；轮询插N1；一次loadMore吸收移位重叠；随后轮询再插N2…N20。
- 根因：不足一页的pending余数在下一次实际loadMore已通过重复页扫描吸收后没有结算，后续新插入仍叠加旧余数；累计到20又错误advance一页。
- 用户影响：page2吸收O20并接收O21…O39后游标到3，但pending仍1；再插19条后游标被推到4，下次直接取O41…O60，O40永久遗漏，后续轮询在首个已知N20处停止。
- 证据：早期双审反例被G09两名代理重新推演反驳；1/19/20/21项矩阵仍缺测试；不改算法；仅补插入组合测试，不稳定排序统一归F-232
- 跨端结论：当前独立缺陷驳回；高频真实交错保留P3测试边界
- 最小修改方向 / 裁决：不修改现有分页算法；仅补1/19/20/21条插入组合与翻页交错测试。不稳定排序边界统一归F-232。

</details>

<details>
<summary>F-166 · P3 · 已驳回 · 旧系统 SheetTextField 可能绕过 disabled</summary>

- 审查单元与位置：C005；旧系统SheetTextField的disabled传递
- 触发路径：目录来源且没有episode_format，指定集数字段应禁用；用户在旧系统分支尝试聚焦和输入。
- 根因：桥接层没有把`context.environment.isEnabled`同步到`UITextField.isEnabled`，NoBlurTextField又无条件覆写`canBecomeFocused=true`。
- 用户影响：当前无生产影响；未来若新增非历史目录入口且父层未阻断，才可能让禁用字段可编辑并进入`episode_detail`。
- 证据：review_a001_h独立枚举两个Reorganize入口均为非空历史logIds，isFromHistory分支无条件令isEpisodeDetailDisabled=false；已闭环；未来新增非历史目录入口时重开桥接测试
- 跨端结论：潜在桥接债务不构成当前生产缺陷
- 最小修改方向 / 裁决：桥接源码债务与未来载荷链成立，但现有生产触发不可达，不能登记为当前缺陷。

</details>

<details>
<summary>F-211 · P3 · 已驳回 · 过滤页展示的旧规则与实际执行规则可能不是同一语义</summary>

- 审查单元与位置：W020-E→F-126/F-081；过滤规则展示与执行快照一致性
- 触发路径：页面已展示规则A；随后服务器把同一ID改成语义B或删除该ID，而设置页刷新失败/尚未刷新；用户继续选择可见旧行并发起资源搜索。
- 根因：设置页保留并允许操作旧`customFilterRules`快照，执行链却不消费该快照，而是重新拉取当前规则；同ID会应用新语义B，缺ID则静默不筛。界面没有revision/stale提示或重新确认边界。
- 用户影响：用户看到并选择A，实际可能执行B或完全不过滤，结果与可见意图静默分裂；需要规则变化与刷新时序前置，不含破坏性副作用，故主审建议P3。
- 证据：verify_a001_h第三裁决按互不替代修复/测试拆分，驳回复合重复编号；设置页标stale/error；执行端对已选缺失ID显式失败，不强制消费旧A快照
- 跨端结论：机制分别保留在既有项；真实编辑/失败重叠频率未验证
- 最小修改方向 / 裁决：复合编号拆归 F-126 与 F-081。

</details>

<details>
<summary>F-214 · P3 · 已驳回 · 推荐开关使用全局本地键，配置owner与跨端合同不清</summary>

- 审查单元与位置：W020-D→F-109；推荐开关配置owner与跨端合同
- 触发路径：同一台Apple TV切换两个账号或两个MoviePilot服务器；一方修改推荐来源开关后另一方进入推荐页。若Web/服务端已有该用户配置，TV在另一设备使用同一账号也构成反例。
- 根因：TV固定使用一个不含baseURL/username的本地键，且没有服务端推荐配置读写；不同owner共享值。动态来源又以可变title作为配置键，但同名path风险当前Web也可能共享，单独留合同验证。
- 用户影响：账号/服务器之间推荐偏好互相污染，TV与Web/另一台TV可能不同步；影响限推荐内容，不改变副作用数据，故建议P3。
- 证据：verify_a001_h第三裁决核清Web本地优先缓存+后端per-user权威，裁独立编号合并；按F-109以服务端当前用户配置为权威；本地fallback使用规范profile tuple
- 跨端结论：不是假问题，仅驳回重复编号；远端最新性未验证
- 最小修改方向 / 裁决：重复编号并入 F-109；机制保留。

</details>

<details>
<summary>F-215 · P2 · 已驳回 · 过滤规则选项缺少稳定且可辨识的身份合同</summary>

- 审查单元与位置：W020-E→F-081；CustomRule选项身份与可辨识标签
- 触发路径：响应含重复ID、null/missing ID/name、纯空白name、trim后重复name，或两个合法超长同前缀名称；用户在TV选择第二项。
- 根因：`rule.id`同时承担ForEach identity、hard/soft focus identity、profile持久化和执行`first(where:)` lookup；行只显示单行`name`且不显示稳定ID。当前Web拒绝完全空/完全重复，但不trim name；后端通用setting入口未校验CustomFilterRules identity。
- 用户影响：重复ID可令两行共享列表/焦点/selected状态，选择第二项仍执行首个匹配；空白或视觉等价名称可让用户无法辨识目标并选择错误规则。坏identity已裁入F-081的条件性P2边界；合法长名称只保留tvOS布局与辅助功能运行验证。
- 证据：review_a001_j提出、verify_a001_h第三裁决确认坏identity并入F-081且支持其条件性P2；F-081校验规范唯一身份；合法长名提供可辨识读取入口需tvOS运行验证
- 跨端结论：驳回重复编号；真实坏配置和长名裁切未验证
- 最小修改方向 / 裁决：坏identity并入 F-081；合法长名称保留运行未验证。

</details>

<details>
<summary>F-216 · P3 · 已驳回 · 手动刷新鉴权失败后错误没有交给登录页</summary>

- 审查单元与位置：W020-C→F-107/F-089；手动刷新鉴权失败的错误交接
- 触发路径：用户在连接页手动刷新；请求返回401/403，通用鉴权路径先logout并令根视图切回登录页，随后System局部状态才得到失败文案。
- 根因：刷新错误只写即将销毁或隐藏的System `refreshMessage`，会话切换没有把本次失败原因交给LoginView或仍可见的持久反馈owner。
- 用户影响：用户被送回登录页却看不到为何刷新失败，只观察到会话突然消失；若根切换延迟足够让局部消息出现则影响收窄，因此保持条件性P3。
- 证据：verify_a001_h提出、review_a001_j定向复核确认最终不可达并裁合并；状态码分类只交叉F-089；F-107复用App级一次性错误owner跨根交接；F-089另裁401/403是否应logout/删凭据
- 跨端结论：驳回重复编号；真实状态码频率与短暂闪现未验证
- 最小修改方向 / 裁决：并入 F-107；401/403 分类交叉 F-089。

</details>

<details>
<summary>F-219 · P2 · 已驳回 · 资源结果同 ID 更新不会刷新本地派生状态</summary>

- 审查单元与位置：I012；TorrentsResult同ID载荷更新不重算派生状态
- 触发路径：资源搜索A得到ID X且`seeders=1`；同一挂载页面再次搜索，返回仍为X但`seeders=10`、促销或meta已变化。
- 根因：外部`result`载荷变化但ID序列相等，`onChange`不触发，排序/筛选选项及卡片继续消费第一次复制的旧`Context`。
- 用户影响：用户看到陈旧做种数、促销标签和筛选/排序结果，可能据此选择下载；同ID本身仍指向同一资源时不直接等于错目标，严重度取决于生产重搜是否复用同一View身份。
- 证据：verify_a001_h提出、review_a001_h反向、review_a001_j第三裁完整闭合两调用分支身份后驳回；仅未来新增原位刷新调用者时改纯派生或generation重算
- 跨端结论：驳回当前生产缺陷；保留未来组件回归边界
- 最小修改方向 / 裁决：优先删除可由输入计算的长期本地副本，让展示数据从当前`result`和筛选选择派生；若性能证据要求缓存，仅使用现有明确搜索结果generation触发一次重算，不列举监听seeders等字段。

</details>

<details>
<summary>F-220 · P2 · 已驳回 · MediaPreloader 的跨阶段屏障延迟季度加载</summary>

- 审查单元与位置：I005→F-115；MediaPreloader跨阶段串行屏障
- 触发路径：详情接口快速返回且已足以请求季度；可选识别或背景图请求接近超时，页面readiness又等待季度settled。
- 根因：季度只依赖详情响应，却被`max(识别, 详情+图片)`联合屏障阻塞，随后才进入`max(季度, 订阅)`，把本可并行的关键路径串行化。
- 用户影响：详情主体已可用时，分季区域仍因无关识别/图片等待而延后开始，可能扩大首屏等待或季度spinner；真实可见时长取决于容器ready条件与网络。
- 证据：review_a001_h集成提出，verify_a001_h独立闭合关键路径并裁其由扩展后的F-115完整承载；详情响应发布即启动season，图片/识别仅约束真实依赖者
- 跨端结论：驳回重复编号，不驳回机制；F-115升P2
- 最小修改方向 / 裁决：详情响应发布后立即启动season；图片独立并行，仅订阅fallback/跳转等真实依赖者等待识别。不新增预载协调框架。

</details>

<details>
<summary>F-222 · P1 · 已驳回 · 全局通知缺少会话 owner，可跨账号发布</summary>

- 审查单元与位置：G08→F-107/CHK-005；全局通知缺少会话owner
- 触发路径：账号A发起订阅动作，请求在途时logout、切服或重新登录B；A响应随后失败并调用全局`show`。已有A错误banner也可在根转换后继续显示剩余时间。
- 根因：manager按App生命周期存活，不监听token、baseURL、currentUser或logout；生产Task发布通知前又没有会话snapshot/epoch校验。
- 用户影响：Login或账号B页面展示账号A的失败消息，错误来源与当前会话错配；是否能进一步泄露敏感服务端文案取决于真实错误内容。
- 证据：两票确认机制；verify_a001_h第三裁确认与F-107共享manager/session transition根owner并合并；F-107复用session/operation epoch，在show入队与发布双检并按owner reset，保留结构化当前logout原因
- 跨端结论：驳回重复编号而非机制；根finding F-107最终P1
- 最小修改方向 / 裁决：复用现有`APIServiceSessionSnapshot`在authenticated操作发布前校验；manager主Actor化并提供按会话reset，logout/token/baseURL/user变化时取消计时和旧通知，同时允许当前logout原因一次性交给Login。无需通知队列或第二presenter。

</details>

<details>
<summary>F-224 · P3 · 已驳回 · 订阅分享最佳结果忽略明确查询年份</summary>

- 审查单元与位置：I007→F-137/F-141；订阅分享最佳结果忽略明确查询年份
- 触发路径：用户查询`Dune 2021`；候选同时包含正确年份媒体与标题同为`Dune`、年份为1984的订阅分享，后者热度更高。
- 根因：媒体候选会对明确查询年份做匹配门禁，分享候选却始终允许无年份回退并按标题完全匹配取得最高档分数，错误年份仍进入同一排序池。
- 用户影响：错误年份分享可成为首个最佳卡片并把用户带入错误分享/Fork目标；正确媒体仍留在普通分类行，故主审建议P3。
- 证据：review_a001_j提出、verify_a001_h独立确认模型year与排序反例后裁合并既有评分族；分享评分复用媒体候选明确年份门；并入F-137传播，查询年份词法仍归F-141
- 跨端结论：驳回重复编号，不驳回机制；维持P3
- 最小修改方向 / 裁决：分享候选复用媒体候选已有的明确年份匹配门槛；不新建评分器或改变普通分享行。

</details>

<details>
<summary>F-237 · P3 · 已驳回 · 动态 source 刷新缺少请求代际</summary>

- 审查单元与位置：I006→F-130/CHK-005；动态source刷新缺请求代际
- 触发路径：同一session连续触发R1、R2刷新；R2先完成发布新schema，R1随后完成。
- 根因：只有session边界，没有同session refresh generation；旧请求可覆盖新请求。
- 用户影响：若未来出现第二个同实例调用者，动态来源/筛选schema可回退；当前生产未闭合该入口。
- 证据：verify_a001_h第三裁确认机制与单调用反证，裁不保留独立生产finding；跨session由F-130/CHK-005阻断；未来新增第二调用点时再加局部revision
- 跨端结论：驳回当前生产缺陷，不驳回组件脆弱点
- 最小修改方向 / 裁决：驳回当前生产缺陷而非否认组件脆弱点；未来新增手动刷新/第二调度者时以局部revision重开。

</details>

<details>
<summary>F-244 · P1 · 已驳回 · Unified Search 子状态可早于父级 session gate 发布</summary>

- 审查单元与位置：G01→G04并入F-130/CHK-005；Unified Search子状态与父级session gate
- 触发路径：profile A发起慢Unified搜索，在子请求返回前切到同样拥有搜索权限的profile B；A的某个子Paginator或resource fallback先恢复。
- 根因：子Paginator会直接写入自身`items`，resource catch也会直接写错误；父ViewModel只在等待全部任务后才做最终session/generation gate，因此最终gate可能阻止bestResults/收尾却无法收回已进入B页面的A子状态。
- 用户影响：B当前Search页面可短暂或持续显示A查询结果/错误；是否含私有插件结果及持续时间决定P1/P2边界。
- 证据：G01主审/纠偏确认；G04独立复核在F-130中再次闭合相同Search child链，根因/修复/验收相同；并入F-130：session变化统一cancel/reset并把epoch gate下沉到child发布
- 跨端结论：重复编号驳回，不驳回机制；普通新query有child generation保护
- 最小修改方向 / 裁决：子fetch先返回局部结果，由父VM在同一epoch检查后提交；或把现有epoch gate下沉到每个子Paginator/error发布点，不建第二搜索状态机。

</details>

## 5. 必须进一步验证的项目

共 17 项。它们已完成静态审查与边界裁定，但必须依赖真机、Simulator、Instruments、真实后端、部署 fixture、正式上游合同或用户操作证据才能升级为确认或驳回。

<details>
<summary>F-017 · P3 · 未验证 · 用户决定跳过修复 · 无时区日期被固定解释为上海时间</summary>

- 审查单元与位置：B002；`Formatters.swift:79-90`、`CustomFilterService.swift:227-232`
- 处置：用户决定跳过修复；保留未验证状态，不改变正式统计。
- 触发路径：无时区字符串实际属于 UTC、服务器自定义时区或站点本地时区。
- 根因：显示和过滤均硬编码 Asia/Shanghai；SwiftDate 的 Region 表示输入日期所属区域。
- 用户影响：更新时间/发布时间/分享时间偏移，过滤阈值也可能误判。
- 证据：B002 主审核对 SwiftDate 实现、调用者和 fixture；verify_b002 确认行为但无法判定源时区契约
- 跨端结论：三类字段时区及非上海部署未验证
- 最小修改方向 / 裁决：确认各日期源契约后统一解析边界；带 offset 保留自身时区，无 offset 按已确认源时区解释。
- 必须补充的验证：三类字段时区及非上海部署未验证

</details>

<details>
<summary>F-037 · P3 · 未验证 · 有效语言标识未经规范化</summary>

- 审查单元与位置：B006-A；`TranslationHelper.languageName` 与 original_language 展示链
- 触发路径：`EN`、` en `、`en-US`、`zh-Hant` 或历史别名。
- 根因：对原字符串做大小写敏感整串查表，无空白/大小写/主子标签/别名规范化。
- 用户影响：可识别语言显示原始代码，而非本地化名称。
- 证据：review_b006_a 核对映射、唯一调用者、模型与标准标签边界；verify_b006_a_retry 确认行为但函数只承诺 ISO 639-1，扩展契约缺失
- 跨端结论：上游字段格式及 BCP 47/别名要求未验证
- 最小修改方向 / 裁决：仅在上游契约确认后于 helper 单点 trim、大小写和主语言规范化；未知非空值保真。
- 必须补充的验证：上游字段格式及 BCP 47/别名要求未验证

</details>

<details>
<summary>F-042 · P3 · 未验证 · 国家码形态未统一规范化</summary>

- 审查单元与位置：B006-B；国家映射/ProductionCountry/详情显示
- 触发路径：lowercase/带空白 alpha-2、字符串 `"US"`、alpha-3 `"USA"`。
- 根因：两个入口原串精确查表；字符串形态固定进 name，不再识别 code；对象入口不复用 canonicalizer。
- 用户影响：简体中文界面显示 US/USA/API 英文名而非“美国”。
- 证据：review_b006_b_retry 核对 249 键、两个入口与多态解码；verify_b006_b 确认 canonical alpha-2 全覆盖，宽容输入是否属契约无法判定
- 跨端结论：上游形态/alpha-3/别名要求未验证
- 最小修改方向 / 裁决：仅在上游确认后，对 trim 后两位 ASCII 字母大写查表；不顺带加入 alpha-3、UK/XK/历史码。
- 必须补充的验证：上游形态/alpha-3/别名要求未验证

</details>

<details>
<summary>F-102 · P3 · 未验证 · opaque progress_key 未按路径段编码</summary>

- 审查单元与位置：A001-H→G05/G09；`APIService.swift:1813-1814`、`decodeAiRedoResponse:1611-1614`
- 触发路径：后端返回包含 `/`、`?`、`#`，或形似既有 percent escape 的 `%xx` 的非空 progress key。
- 根因：启动响应只校验非空，`progressStream` 直接把 opaque key 插入 URL path。
- 用户影响：进度请求走错路由或丢失 key，TV 报失败并允许重复触发，而后台任务可能仍在运行。
- 证据：静态构造可被特殊字符改写；G05与G09复核均确认当前后端生成值只含字母、数字和下划线；保留path-segment编码硬化建议；先固定合同/部署fixture
- 跨端结论：当前本地生产者路径安全；外部生产者、部署版本与opaque合同未验证
- 最小修改方向 / 裁决：复用单一路径段编码 helper，编码失败立即返回现有 invalidURL，不新增 URL 层。
- 必须补充的验证：后端 key 格式保证、percent-decoding 语义及编码斜杠能否作为单段路由参数。

</details>

<details>
<summary>F-108 · P3 · 未验证 · 通知可能在 Sheet 下不可见却照常计时并过期</summary>

- 审查单元与位置：V001；`NotificationManager.swift:44-60`、根 presenter 与 Sheet 异步失败链
- 触发路径：父页面在 Sheet 打开期间因前台刷新、订阅事件或 AI SSE 失败调用全局通知；用户在 Sheet 内停留超过 5 秒。
- 根因：唯一 presenter 挂在根 ContentView，manager 不感知 presenter 可见性便立即开始计时，调用页随后又清空 VM error；系统 Sheet 是否遮挡该 overlay 待运行确认。
- 用户影响：若 Sheet 遮挡根 overlay，关闭 Sheet 时通知可能已经过期，失败无可见反馈。
- 证据：review_a001_j 闭合 SubscribeSeason/Transfer 异步失败、根 presenter 与错误清空链；verify_a001_h 确认静态触发链，但无法静态证明 tvOS Sheet 必然遮挡根 overlay
- 跨端结论：条件性 TV 呈现问题；模态层级、焦点与五秒可见窗口待运行验证
- 最小修改方向 / 裁决：Sheet 自身动作继续复用现有本地 feedback；页面异步错误在 Sheet 打开时保留并延后呈现，暂不引入额外 UIWindow 或通知队列。
- 必须补充的验证：tvOS Simulator 注入无副作用失败，验证 Sheet 打开期间的层级、五秒计时、主动关闭后的剩余可见时间与焦点表现。

</details>

<details>
<summary>F-133 · P3 · 未验证 · 插件筛选控件被静默删除或错误降级</summary>

- 审查单元与位置：V009-A/F；插件 `filter_ui` parser 与 FilterPickersView
- 触发路径：`/discover/source` 的插件 `filter_ui` 含 `VSwitch`、`VSelect(multiple: true)`、自定义 `item-title/item-value`、`show/v-show`、slot 或动态表达式。
- 根因：TV parser 只实现窄子集，却对未支持语义静默跳过或降为单选/自由文本，没有 unsupported 状态；现有测试还把“未知组件静默跳过”固定为预期。
- 用户影响：插件默认页仍可加载，但用户无法设置 Web 可设置的目标筛选，或向后端发送错误类型/含义的值。
- 证据：verify_a001_h 闭合 source→parser→controls→query 链与最小组件反例；review_a001_h/review_a001_j 独立确认机制，但公开 fixture 未触发且无部署载荷
- 跨端结论：条件性插件筛选未验证；固定真实 fixture 到位时重开
- 最小修改方向 / 裁决：不实现 Vuetify/FormRender 框架；先把未支持描述变成可见 unsupported 提示，只根据固定真实插件 fixture 增补确实需要的控件语义。
- 必须补充的验证：当前安装插件的真实 `filter_ui` 载荷与使用频率。

</details>

<details>
<summary>F-134 · P3 · 未验证 · 复合插件筛选值使用错误的查询形状</summary>

- 审查单元与位置：V009-A/E/F；复合插件筛选值的 query serialization
- 触发路径：插件筛选默认值或用户值为数组/嵌套对象，例如 `genre=["a","b"]`；即使 parser 没生成控件，复合默认值也能直接到达请求链。
- 根因：TV 把任意复合 JSON 值编码成一个 JSON 字符串 query item；目标 v2.15.1 Web 锁定的 Axios 1.9 默认按 `genre[]=a&genre[]=b` 与 bracket path 展开嵌套对象。
- 用户影响：插件可能忽略筛选、校验失败或返回与用户选择不符的列表。
- 证据：verify_a001_h 以数组默认值闭合 parser 外直达 query 与版本特定序列化差异；review_a001_h/review_a001_j 独立确认结构差异，但无复合部署 fixture/后端契约
- 跨端结论：条件性插件查询未验证；固定复合 fixture 到位时重开
- 最小修改方向 / 裁决：先取得固定插件 fixture；确需复合值时在现有边界加入小型、确定性的 Axios bracket flattener。若产品只支持标量，则显式拒绝复合值，不再静默 JSON 化；不引入通用参数框架。
- 必须补充的验证：当前插件后端的实际参数契约与复合值频率。

</details>

<details>
<summary>F-136 · P3 · 未验证 · 订阅分享默认排序与目标版本 Web 相反</summary>

- 审查单元与位置：V009-E/F；Share 默认排序状态与 v2.15.1 Web
- 触发路径：首次打开或重新切换到“订阅分享”，用户未主动选择排序。
- 根因：TV 两处都把默认设为 `count` 并发送 `sort_type=count`；本项目声明版本的本地 v2.15.1 Web tag 默认 `time`，其测试也断言首请求为 `sort_type=time`。Popular 才默认 `count`。
- 用户影响：同一默认入口在 TV 显示热度序、目标版本 Web 显示最新时间序，用户看到不同的首屏/分页顺序。
- 证据：verify_a001_h 闭合两处 literal、首路径与版本特定 Web/test；review_a001_j 两次独立确认版本差异，但 TV 产品默认意图缺失
- 跨端结论：条件性默认行为未验证；产品确认 Web 对齐或 TV 特例时收敛
- 最小修改方向 / 裁决：若复核确认没有 TV 产品差异意图，只改属性初值和切源重置两个 literal 为 `time`，补首路径断言；不改排序框架。
- 必须补充的验证：TV 是否有明确“默认热门”的产品选择；若有则驳回。

</details>

<details>
<summary>F-163 · P3 · 未验证 · 旧系统自定义样式不表达 disabled 状态</summary>

- 审查单元与位置：C004；旧系统Sheet自定义样式的disabled外观
- 触发路径：旧系统分支中某Sheet控件被`.disabled`，例如Reorganize媒体ID为空时的指定剧集。
- 根因：两个样式只读取focus/pressed，不读取Environment `isEnabled`；禁用控件在未聚焦时与启用控件使用相同外观。
- 用户影响：Focus Engine虽可能跳过控件，但用户看到的仍像可操作按钮，无法理解为何不能进入；具体视觉误导需旧系统运行确认。
- 证据：双审确认Button/Toggle静态缺口及可达disabled实例，但标准交互门禁与系统外层视觉仍可能成立，MultiSelection另有opacity反例；tvOS 26.0–26.3验证disabled视觉/focus；26.4+不受影响
- 跨端结论：条件性P3；运行外观未验证
- 最小修改方向 / 裁决：现有两个样式读取`isEnabled`并统一降低不可用态opacity/对比度，不改写disabled、不建状态框架。
- 必须补充的验证：tvOS 26.0–26.3实际禁用渲染和用户误判频率。

</details>

<details>
<summary>F-164 · P3 · 未验证 · Fork Sheet 漏用旧系统样式修补</summary>

- 审查单元与位置：C004；Fork Sheet旧系统样式接入
- 触发路径：tvOS 26.0–26.3从Search或Explore以Sheet打开Fork并聚焦唯一操作按钮。
- 根因：Fork使用共享SheetActionButton，但根节点没有调用仓内专用于旧系统的`applySheetStyles()`。
- 用户影响：唯一动作漏掉本项目保留的焦点/按压修补；具体原始渲染或焦点症状需目标OS运行确认。
- 证据：双审确认Search/Explore两入口及父树均不传播该modifier，但漏接本身不能证明旧系统按钮确实错画/错焦；tvOS 26.0–26.3验证Fork原始渲染/焦点后裁决
- 跨端结论：条件性P3；运行症状未验证
- 最小修改方向 / 裁决：只在Fork根容器补一次现有modifier，不让SheetActionButton自建样式体系。
- 必须补充的验证：tvOS 26.0–26.3实际渲染/焦点影响。

</details>

<details>
<summary>F-167 · P3 · 未验证 · 直接修改 SwiftUI 托管根 UIView 的 transform</summary>

- 审查单元与位置：C005；UIViewRepresentable托管根视图几何
- 触发路径：tvOS 26.0–26.3任一SheetTextField获得或失去焦点。
- 根因：桥接直接把UIViewRepresentable管理的根NoBlurTextField transform改为1.01缩放再恢复；SwiftUI官方契约控制托管UIView的center/bounds/frame/transform，直接修改结果未定义。
- 用户影响：可能出现布局、焦点动画或SwiftUI更新冲突，但当前没有可见故障证据，因此不能确认。
- 证据：review_a001_h发现、verify_a001_h独立确认managed root两次写入、26.0–26.3共16调用可达及官方契约违反；删除scale/identity两次写入；目标OS验证布局/焦点动画/更新冲突
- 跨端结论：可见用户故障未验证
- 最小修改方向 / 裁决：同时删除1.01缩放和失焦`.identity`两次根transform写入，保留已有白底和阴影焦点反馈，不建focus状态或包装层。
- 必须补充的验证：tvOS 26.0–26.3布局/焦点动画/更新冲突表现。

</details>

<details>
<summary>F-173 · P3 · 未验证 · 海报连续执行 downsampling 与 resizing</summary>

- 审查单元与位置：C009-B；MediaCard图片处理链
- 触发路径：任一生产MediaCard成功加载海报；当前7个构造点均使用默认256×384。
- 根因：锁定Kingfisher 8.10.0中downsampling设置DownsamplingImageProcessor，随后resizing以复合identifier append ResizingImageProcessor且无同尺寸短路；processed-cache冷缺失/原图回退重处理会再次绘制，cache命中则绕过。
- 用户影响：冷处理海报墙可能承担额外CPU/内存/滚动开销；默认2:3最终尺寸相同、缓存命中绕过且未运行真机Instruments，不能声称已有可见性能回归。
- 证据：双审确认锁定Kingfisher 8.10.0 processor追加/缓存key；processed-cache命中绕过处理、默认2:3同尺寸为反证；删除resizing后需真机Instruments与像素/缓存冷启动验收
- 跨端结论：条件性性能影响未验证
- 最小修改方向 / 裁决：删除resizing，保留downsampling、SwiftUI aspectFill与clip；不增加processor或图片框架。
- 必须补充的验证：真机CPU、内存、滚动帧率和图片质量差异。

</details>

<details>
<summary>F-177 · P3 · 未验证 · 人物卡冷处理先完整解码再缩放</summary>

- 审查单元与位置：C010；PersonCard图片处理
- 触发路径：演员或搜索人物分页LazyHStack首次显示新头像且processed-cache冷缺失/原图回退。
- 根因：仅使用ResizingImageProcessor，数据路径先默认完整解码再重绘；锁定Kingfisher源码建议缩小数据改用更省内存的DownsamplingImageProcessor。
- 用户影响：冷滚动可能增加CPU/峰值内存并影响帧率；缓存命中绕过且无真机Instruments，不能声称已有卡顿。
- 证据：双审确认Kingfisher 8.10.0数据/processor链与演员/搜索分页；cache命中/后台queue/近目标原图为反证；resizing换downsampling后需真机Instruments/像质验收
- 跨端结论：条件性性能影响未验证
- 最小修改方向 / 裁决：按实际width/height用DownsamplingImageProcessor替换resizing；不增加处理链或图片框架。
- 必须补充的验证：CPU、峰值内存、帧率、图像质量及真实头像尺寸分布。

</details>

<details>
<summary>F-181 · P2 · 未验证 · Hero 到内容页切换依赖两个 FocusState 的回调顺序</summary>

- 审查单元与位置：W008-A→I013；Hero到内容页焦点切换
- 触发路径：只监听Hero并即时采样Content，若Hero先false、Content后true会漏置showContentPage
- 根因：只监听Hero并即时采样Content，若Hero先false、Content后true会漏置showContentPage
- 用户影响：只监听Hero并即时采样Content，若Hero先false、Content后true会漏置showContentPage
- 证据：三代理确认静态交错；review_a001_j最终裁定事件顺序未证，若运行复现影响为P2；先记录Simulator/真机事件序；确认后分别监听两个现有FocusState
- 跨端结论：未验证条件性P2；真实事件顺序和可见影响未验证
- 最小修改方向 / 裁决：复用现有机制做局部收敛；具体边界以发现台账为准。
- 必须补充的验证：现有测试只静态检查Header可聚焦入口，没有tvOS Focus Engine事件顺序、快速首次下移、往返或缓存命中首帧覆盖。

</details>

<details>
<summary>F-183 · P3 · 未验证 · TMDB 按钮缺少同步重入边界</summary>

- 审查单元与位置：W008-C；TMDB按钮动作重入
- 触发路径：每次激活创建独立Task，双激活可重复append同一目标并让共享busy提前清除
- 根因：每次激活创建独立Task，双激活可重复append同一目标并让共享busy提前清除
- 用户影响：每次激活创建独立Task，双激活可重复append同一目标并让共享busy提前清除
- 证据：review_a001_j提出静态链；verify_a001_h不读审计文档第三裁决机制成立但tvOS第二次Select可达性无证据；先做双Select序号日志；确认后在Task前同步设置本地in-flight标志
- 跨端结论：条件性P3；真实输入窗口与导航表现未验证
- 最小修改方向 / 裁决：复用现有机制做局部收敛；具体边界以发现台账为准。
- 必须补充的验证：tvOS第二次Select可达窗口、识别overlay是否完全阻断输入及实际重复导航表现。

</details>

<details>
<summary>F-238 · P3 · 未验证 · 插件筛选同名 query 只追加不替换</summary>

- 审查单元与位置：I006；api_path与筛选值同名时重复query
- 触发路径：插件路径含`?mode=old`，同名筛选当前值为`mode=new`。
- 根因：合并直接追加，最终保留两个同名mode；覆盖优先级未在TV或契约中声明。
- 用户影响：后端若first-wins会继续使用old，若拒绝重复键则请求失败；若last-wins则当前行为无害。
- 证据：三代理确认构造；两代理均拒绝在未核FastAPI/plugin合同前确认用户影响；固定真实插件与服务端重复scalar解析合同后再决定是否定向覆盖
- 跨端结论：TV构造成立；当前插件产出与服务端优先级未验证
- 最小修改方向 / 裁决：先核当前插件/后端解析合同；确认筛选应覆盖时，仅移除被当前filter values覆盖的同名项，保留token等无关键，不建query框架。
- 必须补充的验证：当前插件是否生成同名键、服务端取首/末/拒绝及用户影响。

</details>

<details>
<summary>F-241 · P3 · 未验证 · App Info Sheet 展示时底层 root Menu observer 仍启用</summary>

- 审查单元与位置：I016；App Info Sheet下root Menu observer仍启用
- 触发路径：root聚焦App信息并打开Sheet，用户按Menu关闭；modal与底层若共享接收该UIWindow recognizer。
- 根因：observer启用条件不含`showAppInfo`，且显式允许simultaneous recognition；底层回调会清focusedItem并滚到顶部。
- 用户影响：Menu可能既关闭Sheet又改变底层焦点/滚动，破坏系统模态关闭后的焦点恢复。
- 证据：I016两代理确认静态前提，但均不能证明tvOS modal下Menu投递；Sheet/alert展示时禁底层observer/exit handler
- 跨端结论：条件性TV焦点风险；需UI/真机证据，程序限制披露
- 最小修改方向 / 裁决：App Info Sheet或logout alert展示时禁用底层observer/exit handler；普通root Menu行为不变。
- 必须补充的验证：系统Sheet/window press路由与真实Focus Engine恢复；程序限制永久披露。

</details>

### 横向运行验证包

- 真机 / tvOS Focus Engine / VoiceOver：焦点最终落点、Sheet遮挡与退出可发现性、Reduce Motion、动态字号、长文本滚动、通知朗读、双激活窗口。
- Instruments：图片双重 raster、人物头像 downsampling、rawPayload 深层重复持有、缓存与离场任务驻留；静态风险不得替代量化结论。
- 真实后端与部署 fixture：实际版本、插件 `filter_ui`/复合 query、媒体来源与ID形态、下载器状态、低权限账号、跨账号同URL资源、错误/空响应 envelope。
- 用户操作：快速切账号/切服、退出/重进、慢请求乱序、批量部分成功、删除/取消确认、遥控器重复激活与恢复焦点。

## 6. 未覆盖或阻塞范围

- 未覆盖生产文件：无。
- 未完成正文主审或独立复核：无。
- 未完成拆分文件级集成：无。I006 与 I016 因可用代理都曾接触其分段源码，无法取得严格零暴露票；两项均由受限整文件复核加后续 clean-room 全局裁决收口，方法限制已永久披露。
- 开放依赖、争议或回溯：无。
- 外部阻塞：无。启动时相对上游目录缺失已由其他 clean Git 快照解除；实际部署、远端最新性和运行配置仍是逐项未验证边界。
- 运行证据：本目标明确为只读静态审计，故没有构建、测试、Simulator、真机、Instruments或真实后端结果；本报告不会把“未运行”写成“通过”。
- 工作树漂移：审计期间只发生授权的 ReviewPlan 与本轮审计目录文档变化；生产源码与索引基线由审查批次持续核对，无需重开生产单元。

## 7. 建议修复顺序

本轮只给顺序，不执行修复。每批都先写直接回归，再按项目标准命令串行做 tvOS Simulator 构建/测试；涉及性能、焦点和辅助功能的批次还须补真机/Instruments验收。

1. 服务端授权与跨会话安全边界：先处理 F-246/CHK-020、F-027/CHK-005、F-019/F-020、F-062/F-063、F-065/F-082/F-086 等，统一复用 session epoch、request snapshot、tombstone 和现有权限依赖。
2. 破坏性 mutation、精确 owner 与 receipt：处理订阅取消/临时订阅/编辑/Fork/下载删除/Transfer ID复用相关 P1（CHK-006/012/013/014/015/016/017），先阻断错对象、错账号和不可逆数据损失。
3. 身份与缓存一致性：集中修正正ID、source owner、canonical alias、同键 latest-wins、缓存 session namespace；共享 helper 只在已有多调用者时抽取，避免新协调框架。
4. P2 主路径可恢复性：分页、搜索、Dashboard、错误/空/stale四态、取消传播、批量部分成功、站点/source合同、严格响应解码；优先复用现有 Paginator、NotificationManager、snapshot 与 decoder。
5. 可访问性与焦点 P2：把伪Button恢复为原生Button/disabled语义，长正文放入原生ScrollView，动态字体用平台能力；静态修复后做遥控器、VoiceOver、Reduce Motion 与最大字号真机验收。
6. P3 与性能项：在高等级回归稳定后处理文案/格式/低频显示一致性；性能候选必须先用 Instruments 建立基线，不按静态猜测扩改缓存或预载架构。

## 8. 已写入 ReviewPlan 的共享知识

- 会话与权限：请求、重登、settings、多阶段 mutation、长期根页与子Paginator统一绑定单调 session epoch/operation owner；客户端门禁不能代替服务端资源授权（CHK-005/020）。
- 身份：业务ID必须保持正值、来源owner与canonical alias一致；确认页冻结精确目标、范围和session，不在确认后重新解析。
- 缓存：分季/剧集组/订阅状态与图片缓存必须有session namespace；同键并发采用latest-wins，旧结果在返回与写入两处都失效（CHK-007/010）。
- Mutation响应：只接受端点声明的合法envelope；畸形、非对象或缺success的2xx失败关闭，空体只按明确no-content合同接受（CHK-017）。
- 订阅：取消保留owner/season/命中范围；临时创建保留created/reused receipt；编辑保存对null/0/正数和路径保持lossless、未修改幂等（CHK-006/013/014）。
- 下载与Transfer：列表/动作按token subject与downloader复合owner授权；永久删文件单独确认；未完成paused/stopped保持可见可恢复（CHK-012/015/016）。
- 搜索与来源：SSE按事件组帧；搜索站点使用active searchable权威域并区分default/all/specific；source必须由后端真实执行且响应owner可验证（CHK-011/018/019）。
- 呈现与辅助功能：优先原生Button、ScrollView、UIFontMetrics、Reduce Motion环境值和现有焦点恢复入口；运行行为不由静态审计代定。
- 所有历史假设、污染披露、受限集成、最终严重度和回溯去向均保留在 ReviewPlan；候选不进入共享知识，未验证不伪装成确认。

## 9. 兼容检查清单建议

- 已确认新增/补强：CHK-001、CHK-005、CHK-007、CHK-012～CHK-020，以及标为“新增/更新”的既有条目。
- 已确认更新/合并：CHK-003、CHK-004、CHK-006、CHK-008、CHK-009、CHK-010、CHK-011；具体并入章节见下表。
- 已确认删除错误现状声明：CHK-002；当前Web/后端不支持仅legacy `mediaid`的`MediaInfo`，不新增TV差异化兜底。本轮未修改正式清单。
- 已确认删除：无。
- 保持不变：各单元判定不适用或无新增的正式条目保持，不另造 CHK 编号。
- 后续已按用户裁决把CHK-003的未来可写字段升级门禁和CHK-016的下载暂停状态对齐条件落实到 `docs/subscription-compatibility-checklist.md`；其余仍为建议。

| ID | 状态 | 动作 | 对应章节 | 建议摘要 | 独立复核与跨端边界 |
| --- | --- | --- | --- | --- | --- |
| CHK-001 | 已确认 | 新增 | `TV 端更新时重点检查 / Models、SubscribeSeasonViewModel、SubscribeSeasonView` | 仅明确非负季号可建立身份；缺失/null/负值不得折叠为 S00 | verify_m001_c 与 I001 确认值得长期保留且无重复；TV 安全不变量已确认；上游过滤/拒绝策略未验证 |
| CHK-002 | 已确认 | 删除错误现状声明 | `媒体 ID 归一化契约`、`TV 端更新时重点检查 / Models` | 当前Web/后端不支持仅legacy `mediaid`的`MediaInfo`；正式清单不得声称TV当前有此回退 | Web v2.15.5类型/helper与后端响应schema共同反证；F-013驳回，用户决定跳过产品修复 |
| CHK-003 | 已确认 | 已落实到正式清单 | `TV 端更新时重点检查 / Models、APIService、完整对象更新` | 强类型GET→完整PUT/POST须逐字段对账；上游新增公共可写字段时，TV必须同步建模、按正式合同保留，或在适配前阻止不安全更新 | F-011当前字段缺失已修；F-069经v2.15.1复核确认当前订阅字段已全覆盖，仅保留未来升级门禁；不扩大为通用raw-shadow或盲目透传 |
| CHK-004 | 已确认 | 更新 | `跨源详情页 Header 契约` | `canDirectlySubscribe == false` 不能推导为电视剧，只有明确电视剧进入分季 | verify_m001_d 确认三条入口及第三类缺口；TV 二值分类缺陷已确认；上游类型集合/策略未验证 |
| CHK-005 | 已确认 | 新增/补强 | `用户权限契约风险`、`TV 端更新时重点检查 / APIService` | 请求、登录/重登、settings、mutation、profile异步、高层多await动作、子Paginator及长期根页route/focus/受限快照须绑定单调session epoch；重登重验权限，多阶段/批量动作共用owner | 既有双审及W018-A独立复核确认；W020与R001补强根设置/媒体状态传播；TV会话/权限不变量、当前Fork/整理链与根页面传播已确认；后端业务权限契约待产品明确 |
| CHK-006 | 已确认 | 更新/合并 | 并入正式清单现有超级用户/多记录取消条目与 TV 更新检查 | 取消入口使用明确动作词/destructive语义；展示并冻结owner/命中数/精确记录或media+season范围；非TMDB也必须保留season | verify_b007、I001、C014及W013-B双审确认不可变意图、菜单语义和当前后端跨季删除边界；当前Web/后端共享非TMDB忽略season缺陷；须修上游精确删除契约，不做TV单端兜底 |
| CHK-007 | 已确认 | 新增 | `订阅缓存与刷新契约`、`TV 端更新时重点检查 / APIService` | 三类分季/剧集组缓存须绑定发起时session namespace，切会话清理且旧请求不得回填新owner | 既有双审与G02 clean-room复核确认cache/in-flight跨服回填可进入订阅payload；TV缓存边界已确认；真实跨服数据差异频率未验证 |
| CHK-008 | 已确认 | 更新/合并 | 并入正式清单现有 Subscribe schema 与 TV Models 检查 | 持久订阅快照须有唯一正业务 ID，巡检不得跳过异常记录 | verify_m001_f_retry 与 I001 确认 ID/焦点/动作与巡检盲点；TV ID 不变量已确认；坏记录策略未验证 |
| CHK-009 | 已确认 | 更新/合并 | 并入正式清单现有订阅分享、Models 与 APIService 检查 | 分享列表须有唯一正业务ID；GET→Fork保留当前schema的`bangumiid/anilistid/media_source/media_id`并按canonical→raw投影全部主身份；未知extra不要求raw透传；确认页展示立即生效的非空keyword/custom_words | 后端91ce365f与Web 7ea14bc9确认当前字段合同，F-079由未验证转确认P2；其他配置是否必显仍未验证 |
| CHK-010 | 已确认 | 更新 | `订阅缓存与刷新契约`、`TV 端更新时重点检查 / APIService` | 同键较新强刷后，旧 miss/force 不得写缓存或返回旧值，旧调用者复用最新结果 | verify_a001_h 确认缓存与调用者双重回滚、详情 ready 后视图强刷与预加载普通检查的生产重叠、sliding TTL 及 snapshot revision 对照；TV latest-wins 不变量已确认；TTL 产品选择与真实频率未验证 |
| CHK-011 | 已确认 | 更新/合并 | 并入正式清单现有 `search.py / chain/search.py / indexer` missingSites 条目 | 资源 SSE 按空行组帧并以换行拼接多条 data；仅明确成功终止可进入受限 missingSites 补偿 | verify_a001_h 确认 framing、终止与补偿边界并收窄为资源搜索；TV parser/终止/补偿链已确认；当前 Web/后端 framing 与站点错误结构未验证 |
| CHK-012 | 已确认 | 新增 | `下载任务权限与身份契约`、`TV/后端更新重点检查` | list/start/stop/delete必须按token subject校验owner；任务身份与owner查找包含downloader，superuser/API Token例外显式化 | review_a001_j与review_a001_h独立确认TV无过滤、后端token-only端点、Web过滤及跨下载器hash边界；当前本地跨端授权缺陷已确认；部署版本与API Token产品策略未验证 |
| CHK-013 | 已确认 | 新增 | `订阅编辑三态与更新幂等契约`、`TV 端更新重点检查 / Models、SubscribeSheet` | total_episode保留null/0/正数及既有manual语义；未修改保存幂等，只有显式修改才改变人工语义 | review_a001_j与review_a001_h独立确认长期价值、测试矩阵及与正式清单不重复；TV/Web/当前后端链已闭合；真实NULL分布与部署版本未验证 |
| CHK-014 | 已确认 | 新增 | `订阅保存路径契约`、`TV 端更新重点检查 / SubscribeSheet` | nil表示自动；非空为API-ready本地/远程根或子路径，编辑器原样保留既有值并可清空 | review_a001_j与review_a001_h独立确认路径值域、storage URI及与正式清单不重复；TV/Web/当前后端路径与allowlist已闭合；真实远程目录频率未验证 |
| CHK-015 | 已确认 | 新增 | `下载删除数据范围与危险动作确认`、`TV/后端更新重点检查` | 删除任务与永久删除文件为两个显式动作；默认只删任务，永久删除单独确认不可撤销范围 | review_a001_j与review_a001_h独立确认该合同不被CHK-006/012覆盖及适配器测试矩阵；当前TV/Web/后端危险默认已闭合；其他下载器与部署版本未验证 |
| CHK-016 | 已确认 | 已落实到正式清单 | `未完成下载状态可见与可恢复契约`、`TV/Web/后端更新重点检查` | 列表保留全部未完成paused/stopped等状态并排除已完成项；stop后轮询仍可见且可继续 | 用户决定跳过TV单端修复；`docs/subscription-compatibility-checklist.md`已记录官方后端/Web变化后的同步对齐触发条件 |
| CHK-017 | 已确认 | 新增 | `Mutation 2xx 响应契约`、`TV 端更新重点检查 / APIService` | mutation仅接受端点声明的合法envelope；畸形、非对象或缺success的2xx失败关闭，空响应仅按显式no-content合同接受 | 下载与Fork不同decoder/端点分别获独立确认；须端点级声明且不能用全局空body fallback；TV fail-open生产链已确认；各端点空body/204及Fork成功envelope正式合同未验证 |
| CHK-018 | 已确认 | 新增 | `资源搜索站点权威域与默认语义`、`TV/Web/后端更新重点检查` | 搜索站点列表来自active searchable权威域；default/all/specific三态不得用同一空sentinel混淆 | review_a001_h建议保留，verify_a001_h第三裁决确认一条清单共同验收两个独立P2；当前TV、Web、后端本地快照已核对；执行模块细节、部署配置与远端最新性未验证 |
| CHK-019 | 已确认 | 新增/补强 | `媒体搜索来源请求与响应语义`、`TV/Web/后端更新重点检查` | source必须由后端声明允许值并真实执行；兼容测试断言provider/返回来源语义，不能只检查URL含query | 既有多段确认参数被忽略；verify_a001_h第三裁决确认正式长期合同与测试价值；当前TV/后端本地快照已核对；实际启用来源、AniList值域与远端最新性未验证 |
| CHK-020 | 已确认 | 新增 | `服务端 manage 资源授权`、`TV/Web/后端更新重点检查` | manage-only UI对应的每个读取与mutation端点都必须由后端在返回/执行前校验active manage用户；客户端菜单/路由门禁不能代替资源授权 | 两张独立源码票确认GET整理历史仅验token；全新clean-room窄裁确认必须独立于session epoch清单长期保留；当前本地TV/Web/后端链已核对；部署版本、API Token产品策略与真实低权限账号频率未验证 |

## 10. 结论

本轮静态审计已经把 78 个生产 Swift 文件拆成 140 个正文单元并完成不同代理独立复核，16 个拆分文件集成与 10 个全局回溯组均已收口。结合后续修复与当前目标版本复核，当前账面为 204 项已确认、5 项降级、20 项驳回、17 项未验证；没有 P0，没有开放裁决队列或全局阻塞。历史确认P1共44项，30项已修复/完成范围内对齐、10项明确跳过、4项重分类，待裁决为0。

两名最终检查代理已对当前五份持久化文档复核通过：覆盖、状态、等级、驳回/合并边界、兼容清单、受限披露与报告十类内容均一致，阻断为 0。本轮只完成静态审计及文档收口；所有运行、部署、真机、Instruments、真实后端和用户操作边界仍按对应“未验证”项保留，不冒充运行通过。

## 11. 审计后用户补充修复登记（2026-08-13）

本节记录审计收口后用户补充路径的兼容修复，不新增正式 `F-*` 编号：

- AniList 详情页补齐演员与推荐 endpoint，并在辅助内容身份中支持 `anilist_id` 回退。
- AniList 内嵌职员兼容 `avatar.large`，缺失人物 `source` 时沿父媒体来源投影；TMDB 搜索和 fallback 识别均显式固定 `source=themoviedb`。
- 代码与回归测试已提交为 `d2972b3`；本登记仅更新审计文档，未纳入该提交。真实后端兼容套件因缺少 `.env.compatibility` 未运行。
