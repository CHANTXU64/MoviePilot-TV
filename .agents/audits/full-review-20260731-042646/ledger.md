# MoviePilot-TV 从零全量代码审计台账

审计 ID：`full-review-20260731-042646`
启动时间：2026-07-31 04:26:46 +08:00
审计对象：启动时当前工作树，而不是仅审查 HEAD。

## 1. 启动基线

| 项目 | 结果 |
| --- | --- |
| 分支 | detached HEAD |
| HEAD | `4a997919983566ec208e777acf7798a95e2f9e8f` |
| 启动时工作树 | 干净 |
| 已修改/未跟踪生产 Swift | 无 |
| 生产 Swift | 78 个，25,280 行 |
| 测试 Swift | 32 个，19,814 行；只作证据，不作生产审查单元 |
| 预览专用/生成 Swift | 0 / 0 |
| 工程成员关系 | `MoviePilot-TV/` 下 78 个 Swift 均属于 App target |
| 旧 ReviewPlan | 74 个有效生产路径；旧完成状态不计入本轮 |
| 旧计划后新增 | `SubscriptionCancelConfirmation.swift`、`AppVersionInfo.swift`、`UserPermissions.swift`、`ManualMediaSearchSheet.swift` |
| Web 上游 | 启动时 `../MoviePilot-Frontend` 不存在；后续使用 clean 仓库 `/Users/chantxu/code/MoviePilot-Frontend` HEAD `19710a5f0fe0d795a92de904bacd3193bd8c8432`、tag `v2.13.6` 做逐项静态合同核对 |
| 后端上游 | 启动时 `../MoviePilot` 不存在；后续使用 clean 仓库 `/Users/chantxu/code/MoviePilot` HEAD `a0ee99aacc485259431ce5be10933559f4ceac42`、tag `v2.14.4` 做逐项静态合同核对 |

两名启动代理独立枚举结果逐路径一致，无需差异核对代理。正文计划为 140 个主审单元、140 次不同代理独立复核、16 次拆分文件集成复核、动态回溯及最终双重检查。

## 2. 状态规则

审查状态只使用：`待审`、`主审中`、`待复核`、`复核中`、`待回溯`、`已闭环`、`阻塞`。

- 普通单元只有完成主审与不同代理独立复核，且候选发现已获得状态，才能标为 `已闭环`。
- 拆分文件的所有分段闭环后，必须由未参与分段主审的代理完成文件级集成复核。
- 上游缺失不免除 TV 端审查；需要跨端证据的结论标为 `未验证`，不得从旧记录推定。
- 每批代理须报告除 `.agents/ReviewPlan.md` 与本审计目录之外的工作树变化；生产范围变化会重新打开受影响单元。

## 3. 跨文件组件组

| 组 | 范围 | 完成要求 |
| --- | --- | --- |
| G01 | 搜索来源与系统默认值 | `SearchViewModel`、`APIService`、`SystemViewModel`、AddDownload/Reorganize；闭环后做循环依赖集成复核 |
| G02 | 订阅身份、缓存与刷新 | Models/API 订阅段、取消确认、Handler/Modifier、订阅 VM/View/Sheet、Preloader、详情和首页入口 |
| G03 | 详情导航、预加载与动作 | Preloader、Action Handler/Modifier、Card/Grid/ContextMenu、详情容器/VM/View |
| G04 | 分页状态 | Paginator 与 Collection/Explore/MediaDetail/Person/Recommend/Search/Transfer ViewModel |
| G05 | 自定义过滤与资源结果 | CustomFilter、System、Search、ResourceResult、Torrent、AddDownload |
| G06 | 会话、权限与根状态 | UserPermissions、Keychain、API、Login、Content、System、App |
| G07 | 人员、职位与翻译 | JobRegistry、Translation、StaffManager、人物模型、详情 VM/View |
| G08 | 全局通知呈现 | NotificationManager/Component、根注入及页面/Sheet 调用者 |
| G09 | 转移与重新整理 | Models/API 对应段、Reorganize、ManualMediaSearch、Transfer、Status |
| G10 | Sheet 焦点与样式 | ActionRow、SheetStyles/TextField/Picker、MultiSelection 及业务 Sheet |

## 4. 全量审查单元

### 4.1 模型、扩展与基础服务

| 审查单元 | 范围/符号 | 依赖层级 | 主审代理 | 主审状态 | 复核代理 | 复核状态 | 发现编号 | 回溯依赖 | 最终状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B001 | `Models/AppVersionInfo.swift` 全文件 | L0 | verify_m001_b | 已闭环 | verify_b001 | 已闭环 | F-009/F-010 | G06 | 已闭环 |
| B002 | `Extensions/Formatters.swift` 全文件 | L0 | verify_b001 | 已闭环 | verify_b002 | 已闭环 | F-016…F-018/F-021 | G10 | 已闭环 |
| B003 | `Extensions/KingfisherCookies.swift` 全文件 | L0 | verify_m001_a | 已闭环 | verify_b003_retry | 已闭环 | F-019/F-020/F-026 | G03/G06 | 已闭环 |
| M001-A | `Models.swift:1-169`，通知、媒体身份与 ID 规则 | L0 | review_m001_a_retry | 已闭环 | verify_m001_a | 已闭环 | F-006…F-008/F-012/F-013 | G02/G06 | 已闭环 |
| M001-B | `Models.swift:170-415`，宽容标量、JSON、动态来源描述 | L0 | startup_plan_validation | 已闭环 | verify_m001_b | 已闭环 | F-001 | G01/G05/G06 | 已闭环 |
| M001-C | `Models.swift:416-654`，状态模型与媒体解码辅助类型 | L0 | review_m001_c | 已闭环 | verify_m001_c | 已闭环 | F-002…F-005/F-011 | G02/G03/G04/G06/G07 | 已闭环 |
| M001-D | `Models.swift:655-1213`，`MediaInfo` | L0 | review_m001_d | 已闭环 | verify_m001_d | 已闭环 | F-004/F-011/F-013…F-015 | G02/G03/G07 | 已闭环 |
| M001-E | `Models.swift:1214-1625`，下载、Torrent、站点、媒体服务器与存储 | L0 | review_m001_e | 已闭环 | verify_m001_e | 已闭环 | F-021…F-025/F-032；F-022/F-023已修复（`af67839`）；W017生产链令F-024升级条件性P1并重开身份/合并回溯 | G02/G03/G05/G06/G09 | 已闭环 |
| M001-F | `Models.swift:1626-2060`，过滤组、订阅请求、`Subscribe`、`EpisodeGroup` | L0 | review_m001_f | 已闭环 | verify_m001_f_retry | 已闭环 | F-065…F-069；支持 F-008/F-012/F-047/F-054 | G02/G05 | 已闭环 |
| M001-G | `Models.swift:2061-2351`，下载请求、人物、Bangumi 图片与头像 | L0 | review_m001_g | 已闭环 | verify_m001_g_retry | 已闭环 | F-064已修复（`af67839`）；支持 F-002/F-041/F-051/F-052/F-055/F-056；人物嵌套原形转CHK-003未验证边界，不再支撑收窄后的F-011 | G05/G07 | 已闭环 |
| M001-H | `Models.swift:2352-2479`，资源搜索、系统设置、转移历史与存储 | L0 | review_m001_h_retry | 已闭环 | verify_m001_h | 已闭环 | G09后F-070确认P2、F-071 P2；F-072 P1已修复（`e388e8b`），验证及最终独立复审通过；支持F-001/F-021/F-027/F-036，F-013经当前Web/后端合同反证后驳回 | G01/G05/G09 | 已闭环 |
| M001-I | `Models.swift:2480-2637`，`SubscribeShare` | L0 | review_m001_i | 已闭环 | verify_m001_i | 已闭环 | F-077/F-078/F-079；支持 F-002/F-008/F-017/F-027；嵌套分享对象不再计入收窄后的F-011 | G02 | 已闭环 |
| M001-J | `Models.swift:2638-2803`，重新整理与手动预览模型 | L0 | review_m001_j | 已闭环 | verify_m001_j | 已闭环 | F-073…F-076；F-076 手动媒体 ID 搜索子项已修复（`44908c4`）并通过本地437/437测试与独立复审，聚合子项仍开放；支持 F-027 | G09 | 已闭环 |
| M001-K | `Models.swift:2804-2868`，SSE 事件与自定义过滤规则 | L0 | review_m001_k_retry | 已闭环 | verify_m001_k | 已闭环 | F-080/F-081/F-085；F-081 输入边界修复已提交（`670cf86`），验证及独立复审通过，缺失选择静默不过滤由用户接受；支持 F-001/F-022/F-032/F-057…F-061 | G01/G05 | 已闭环 |
| B004 | `Models/UserPermissions.swift` 全文件 | L0 | review_b004 | 已闭环 | verify_b004 | 已闭环 | F-027/F-029已由`90b40b4`修复；F-028经当前合同复核和用户裁决后驳回；F-030已按当前Web正常producer合同修复（`ee5dcb4`），本地验证及独立复审通过；F-031降为条件性P3并由用户跳过；CHK-005传播闭合 | G02 | 已闭环 |
| B005 | `Models/JobRegistry.swift` 全文件 | L0 | review_b006_a | 已闭环 | verify_b005 | 已闭环 | F-040/F-041/F-044/F-045 | G07 | 已闭环 |
| B006-A | `TranslationHelper.swift:1-207`，语言翻译 | L0 | review_b006_a | 已闭环 | verify_b006_a_retry | 已闭环 | F-037/F-038 | G07 | 已闭环 |
| B006-B | `TranslationHelper.swift:208-470`，国家地区翻译 | L0 | review_b006_b_retry | 已闭环 | verify_b006_b | 已闭环 | F-042/F-043 | G07 | 已闭环 |
| B006-C | `TranslationHelper.swift:471-542`，职位与类型翻译 | L0 | verify_b005 | 已闭环 | verify_b006_c | 已闭环 | F-040/F-041/F-044/F-046 | G07 | 已闭环 |
| B007 | `Extensions/SubscriptionCancelConfirmation.swift` 全文件 | L0 | verify_b006_a_retry | 已闭环 | verify_b007 | 已闭环 | F-047/F-048条件P1；F-049 P2；F-054当前实现已解决 | G02/G08 | 已闭环 |
| S001 | `Services/Logger.swift` 全文件 | L1 | integrate_i002 | 已闭环 | verify_s001_resume | 已闭环 | F-060 | G06 | 已闭环 |
| S002 | `Services/KeychainHelper.swift` 全文件 | L1 | review_s002_resume | 已闭环 | verify_s002_fresh | 已闭环 | G06两票将F-062/F-063升条件P1；支持F-027/F-031 | — | 已闭环 |
| S003 | `Services/ParsedSeason.swift` 全文件 | L1 | verify_s006 | 已闭环 | verify_s003_resume | 已闭环 | F-057…F-059/F-061 | G05 | 已闭环 |
| A001-A | `APIService.swift:1-350`，错误、响应包装、URL/解码纯函数、`APICache` | L1 | review_a001_a | 已闭环 | verify_a001_a | 已闭环 | G02末裁将F-082升条件P1；F-083/F-084 P2；支持F-001/F-005/F-022/F-027/F-030/F-033/F-060/F-065 | G01 | 已闭环 |
| A001-B | `APIService.swift:351-926`，单例状态、订阅缓存、凭据、会话、请求构造 | L1 | review_a001_b | 已闭环 | verify_a001_b | 已闭环 | G06闭合F-019/F-062/F-063 P1、F-030/F-031 P2；其余会话/缓存传播不变 | G02 | 已闭环 |
| A001-C | `APIService.swift:927-1071`，通用解码、令牌校验与登录 | L1 | review_a001_c_retry2 | 已闭环 | verify_a001_c | 已闭环 | G06将F-089转确认P2；G02末裁将F-087升P2，F-088 P2及F-027…F-031/F-062/F-063传播闭合 | — | 已闭环 |
| A001-D | `APIService.swift:1072-1470`，系统、媒体搜索、发现、推荐、合集 | L1 | review_a001_d_retry | 已闭环 | verify_a001_d | 已闭环 | F-090；支持 F-005/F-009/F-013/F-027/F-031/F-060/F-064/F-076/F-077/F-078/F-082/F-084/F-086/F-087 | G01/G03/G06 | 已闭环 |
| A001-E | `APIService.swift:1471-1528`，下载器及下载任务动作 | L1 | review_a001_e | 已闭环 | verify_a001_e | 已闭环 | F-091…F-095；支持 F-021/F-024/F-027/F-060/F-082/F-083/F-086/F-087 | G05/G06/G08 | 已闭环 |
| A001-F | `APIService.swift:1529-1665`，转移历史、手动整理、存储 | L1 | review_a001_f | 已闭环 | verify_a001_f | 已闭环 | G09后F-098 P1、F-099 P2；支持F-027/F-033/F-036/F-060/F-071…F-076/F-080/F-082/F-086/F-087，新增F-246后端读取授权 | G01/G06/G09 | 已闭环 |
| A001-G | `APIService.swift:1666-1706`，媒体服务器 | L1 | review_a001_g | 已闭环 | verify_a001_g | 已闭环 | F-096/F-097；支持 F-001/F-023/F-025/F-027/F-060/F-082/F-086/F-087 | G03/G06 | 已闭环 |
| A001-H | `APIService.swift:1707-1856`，SSE 与资源搜索 | L1 | review_a001_h | 已闭环 | verify_a001_h | 已闭环 | F-101…F-103；传播 F-004/F-011/F-013/F-022/F-027/F-080/F-082/F-084/F-086/F-087 | G01/G03/G05/G06/G09 | 已闭环 |
| A001-I | `APIService.swift:1857-2006`，详情、人物、站点及规则配置 | L1 | review_a001_i | 已闭环 | review_a001_h | 已闭环 | F-104；传播 F-001/F-002/F-011/F-027/F-038/F-041/F-043/F-046/F-050…F-052/F-056/F-064/F-081/F-082/F-084/F-086/F-087/F-090 | G03/G05/G06/G07 | 已闭环 |
| A001-J | `APIService.swift:2007-2500`，季、订阅 CRUD、查找与缓存 | L1 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | F-100；传播 F-003/F-006/F-008/F-011…F-013/F-027/F-047…F-049/F-054/F-060/F-065…F-069/F-079/F-082/F-086/F-087/F-104 | G02 | 已闭环 |
| A001-K | `APIService.swift:2501-2649`，添加下载与图片 URL | L1 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | F-105/F-106；传播 F-011/F-027/F-084/F-086/F-087 | G03/G05/G06 | 已闭环 |
| S004 | `Services/Paginator.swift` 全文件 | L1 | review_s004 | 已闭环 | verify_s004 | 已闭环 | F-026/F-032…F-036/F-039 | G03/G04/G06 | 已闭环 |
| S005 | `Services/CustomFilterService.swift` 全文件 | L1 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-060/F-061/F-081/F-085；F-110 经下游闭环并确认 P2；F-017 未验证 | G05 | 已闭环 |
| S006 | `Services/StaffManager.swift` 全文件 | L1 | verify_b006_b | 已闭环 | verify_s006 | 已闭环 | F-040/F-041/F-045/F-050…F-053/F-055/F-056 | G07 | 已闭环 |

### 4.2 全局状态与业务 ViewModel

| 审查单元 | 范围/符号 | 依赖层级 | 主审代理 | 主审状态 | 复核代理 | 复核状态 | 发现编号 | 回溯依赖 | 最终状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| V001 | `NotificationManager.swift` 全文件 | L2 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | F-107原P1主触发已修复，剩余P2由用户决定跳过；F-108 未验证；传播 F-049/F-060/F-091/F-093 | G08 | 已闭环 |
| V002-A | `SystemViewModel.swift:1-98`，系统与详情偏好 | L2 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G06后F-109/F-111均P2；profile与token-only身份边界及传播闭合 | — | 已闭环 |
| V002-B | `SystemViewModel.swift:99-243`，过滤选择、登录与 Keychain | L2 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G06后F-109/F-111/F-089均P2；会话/Keychain/规则传播闭合 | — | 已闭环 |
| V002-C | `SystemViewModel.swift:244-359`，系统、站点与规则加载 | L2 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-112 已确认；传播 F-027…F-031/F-060/F-063/F-081/F-082/F-085/F-086/F-109/F-111 | G01/G05/G06 | 已闭环 |
| V002-D | `SystemViewModel.swift:360-456`，静态读取、归一化与持久化 | L2 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-113 已确认；独立支持 F-111/F-112；传播 F-027/F-086/F-109/CHK-005 | G01/G05/G06 | 已闭环 |
| V003 | `SiteFilterViewModel.swift` 全文件 | L2 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | F-114 已确认；F-112 下游传播；支持 F-028/F-060/F-082/F-086/F-109/F-111/CHK-005 | G01/G05 | 已闭环 |
| V004-A | `MediaPreloader.swift:1-299`，`MediaPreloadTask` | L2 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 后续G03将F-116升确认P2；F-115 P2、F-117 P3；强支持F-100，传播身份/会话/图片发现 | G02/G03 | 已闭环 |
| V004-B | `MediaPreloader.swift:300-474`，全局缓存、Pin、刷新与 LRU | L2 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 后续G03将F-118确认P2；F-119 P2；支持F-004/F-008/F-019/F-020/F-027/F-100及F-115…F-117传播 | G02/G03 | 已闭环 |
| V005 | `MediaActionHandler.swift` 全文件 | L2 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | F-122 已确认 P3、F-123 已确认条件性 P2；确认传播 F-090/F-103/F-113/F-115 | G03/G06/G08 | 已闭环 |
| V006 | `SubscriptionHandler.swift` 全文件 | L2 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-120后续降P2且用户决定跳过；G02末裁将F-121升P2、F-124升条件P1；F-124已由`4a1a291`修复并通过聚焦5/5、完整本地450/450与独立复审；F-079后经当前官方schema裁决确认P2 | G02/G08 | 已闭环 |
| V007 | `LoginViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新增；G06将F-089转确认P2，F-027/F-062/F-063/F-086…F-088/F-107/F-113及F-123传播闭合 | — | 已闭环 |
| V008 | `HomeViewModel.swift` 全文件 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-125/F-128 P3、F-126 P2；G02末裁将F-127升条件P1，用户随后决定跳过修复；确认传播F-008/F-023/F-025/F-047/F-049/F-060/F-068/F-082/F-097/F-105/F-106 | G02/G03/G06/G08 | 已闭环 |
| V009-A | `ExploreViewModel.swift:1-180`，来源类型与插件过滤解析器 | L3 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | F-133/F-134 未验证待部署/I006，F-135 已确认 P3；F-088 动态来源 `+` 编码扩展；传播 F-027/F-028/F-077/F-078/F-082/CHK-005 | G01/G04/G05/G06 | 已闭环 |
| V009-B | `ExploreViewModel.swift:181-203`，内容包装与媒体类型 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G01/G04将F-129升P2；F-077/F-078/F-082/F-103传播不变，ExploreContent为死代码 | G01/G02/G04 | 已闭环 |
| V009-C | `ExploreViewModel.swift:204-311`，ViewModel 状态与初始化 | L3 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 后续G04将F-130升P1并吸收F-244；`90b40b4`已用统一UI identity、runtime取消与缓存失效闭合，聚焦96/96和既有独立复审PASS；F-027/F-028/F-033/F-035/F-082/F-086传播不变 | G01/G04/G06 | 已闭环 |
| V009-D | `ExploreViewModel.swift:312-560`，各来源筛选字典 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G05将F-131升条件P2，F-132维持P3；21组筛选集合完整性通过 | G01/G05 | 已闭环 |
| V009-E | `ExploreViewModel.swift:561-753`，派生筛选、路径与查询构建 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-134/F-136 未验证待部署/产品意图；确认 F-129/F-131/F-132；F-088 动态 query 扩展及既有传播 | G01/G04/G05/G06 | 已闭环 |
| V009-F | `ExploreViewModel.swift:754-957`，分页、加载、来源刷新与重置 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；确认 F-129/F-130 与 F-132 同根共有值扩展；传播 F-027/F-033/F-035/F-077/F-078/F-082/F-088/CHK-005；F-133/F-134/F-136 未验证，F-135 已确认 P3 | G01/G02/G04/G05/G06 | 已闭环 |
| V010 | `RecommendViewModel.swift` 全文件 | L3 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | 后续G01/G04将F-138升条件P1、F-139升P2；其余推荐分页/session/图片/动作传播不变 | G03/G04/G06 | 已闭环 |
| V011-A | `SearchViewModel.swift:1-78`，搜索类型、来源、结果类型与评分 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G04 clean-room末裁将F-137升条件P2；声明身份其余通过；传播F-001/F-014/F-015/F-032/F-055/F-064/F-077/F-078/F-082/F-090/F-103/F-109/F-111/F-114 | G01 | 已闭环 |
| V011-B | `SearchViewModel.swift:79-260`，最佳结果计算 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-140/F-141 确认 P3；独立确认 F-137、补强 F-138；传播 F-044/F-055/F-064/F-077/F-078/F-082/F-105/F-106，F-039 转 V011-F/I007 | G01 | 已闭环 |
| V011-C | `SearchViewModel.swift:261-511`，搜索编排、SSE、权限与代际控制 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；G04末裁将F-035/F-039升P2并收窄为owner/session取消；权限热切换并入F-130/CHK-005，旧结果/过期错误并入F-076 | G01/G04/G06 | 已闭环 |
| V011-D | `SearchViewModel.swift:512-731`，分页器构造、重置与订阅映射 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-138 title-only核心确认、collection_id同根扩展机制成立但生产输入未验证，F-036 最终 Person.id 去重确认；其余传播闭合 | G01/G02/G04 | 已闭环 |
| V011-E | `SearchViewModel.swift:732-748`，自定义过滤 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；过滤失败/坏规则/缺选择并入 F-081/F-085，传播 F-017/F-027/F-060/F-061/F-082/F-086/F-109/F-111/CHK-005 | G05 | 已闭环 |
| V011-F | `SearchViewModel.swift:749-865`，`SharedMediaFetcher` | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | F-142 经第三代理确认条件性 P2；直接确认 F-034/F-039，传播 F-027/F-033/F-035/F-082/F-086/F-088/F-138/CHK-005 | G01/G04 | 已闭环 |
| V012-A | `MediaDetailViewModel.swift:1-255`，详情、分页、背景与预加载 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-100/F-130/F-139扩展确认；F-138 task/season/lifecycle alias成立但wrong fullDetail注入收窄未验证；后续G03将F-116/F-118确认P2 | G03/G04/G07 | 已闭环 |
| V012-B | `MediaDetailViewModel.swift:256-395`，订阅状态与取消 | L3 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 无新编号；确认 F-006/F-007/F-015/F-027/F-047…F-049/F-068/F-082/F-090/F-100/F-119/F-120 与 CHK-005/006/008/010；F-008/F-054 本段未复现 | G02/G03 | 已闭环 |
| V012-C | `MediaDetailViewModel.swift:396-470`，取消确认与目标解析 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；确认 F-047/F-048/CHK-006：电影 Header、电视剧 warning、AniList fallback与测试入口错位，失败开放/执行重查/范围未冻结；其余传播闭合 | G02/G03 | 已闭环 |
| V013 | `PersonDetailViewModel.swift` 全文件 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | G04/G02末裁后F-143/F-144均确认P2：route准入/展示身份与请求owner不统一，以及取消后仍启动后一阶段；既有人物分页/图片/session/错误传播闭合 | G04/G07/G02 | 已闭环 |
| V014 | `CollectionDetailViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | verify_a001_h | 已闭环 | 无新编号；F-027/F-033/F-035/F-082/CHK-005直接适用；F-138 identity/inert-task与F-139成功空扩展成立，SwiftUI旧StateObject/wrong-fullDetail/part父ID条件链维持未验证 | G04 | 已闭环 |
| V015 | `ResourceResultViewModel.swift` 全文件 | L3 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | 无新编号；确认 F-022/F-032/F-060/F-061/F-076/F-080/F-081/F-082/F-085/F-086…F-088/F-101/F-103/F-027/F-123/F-130 与 CHK-005/011；F-033/F-039不适用，F-035窄传播，补偿重复ID仅留未验证 | G01/G05/G06 | 已闭环 |
| V016 | `AddDownloadViewModel.swift` 全文件 | L3 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 后续G05将F-145升P2；F-011收窄为TorrentInfo四个官方字段丢失的条件性P2，并补强F-027/F-076/F-087/F-099/F-120/F-130与CHK-003/005，F-135条件传播不升级 | G01/G05/G06 | 已闭环 |
| V017 | `SubscribeSeasonViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | W013-B补强后F-146升级确认条件性P1；确认传播F-003/F-008/F-027/F-047/F-048/F-060/F-065/F-066/F-068/F-082/F-108/F-120与CHK-003/005/006/007/008；通用media原形不再计入收窄后的F-011；F-033不适用、F-049/F-067不复现 | G02 | 已闭环 |
| V018 | `SubscribeSheetViewModel.swift` 全文件 | L3 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | F-147 Subscribe竞跑已由`a872737`修复；F-148条件P1仍开放；G02末裁以当前PUT合同将F-069转确认P1并与F-199共享lossless edit根 | W014、G02/G10 | 已闭环 |
| V019 | `StatusViewModel.swift` 全文件 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | G09后F-149 P1、F-150 P2、F-070 P2；传播F-005/F-027/F-060/F-082/F-086/F-126/CHK-005 | W016、G06/G09 | 已闭环 |
| V020 | `DownloadTaskViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | W017页面双审补强F-024/F-083/F-092/F-093/F-095严重度并新增F-196/F-197；F-091/F-094/F-027/F-060/F-082与CHK-005/012传播，F-033/F-035/F-120仍有不适用反证 | W017、G05/G06/G08 | 已闭环 |
| V021 | `ReorganizeViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-151 P1且因当前官方Web v2共享同一行为由用户决定跳过TV单端修复；F-099 P2；F-120后续因跨端一致且未证明错目标mutation降P2并由用户决定跳过；F-073经clean-room窄裁确认P2，F-074/F-075/F-076/F-027/F-065/F-087与CHK-005/007维持 | W017、G01/G09/G10 | 已闭环 |
| V022-A | `TransferHistoryViewModel.swift:1-201`，分页与搜索 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | I009回溯后F-071升P2；F-072/F-033/F-035/F-036/F-060/F-082/F-001/F-021/F-144与CHK-005传播闭合，坏单行/total/duplicate-only维持未验证 | G04/G09 | 已闭环 |
| V022-B | `TransferHistoryViewModel.swift:202-281`，删除与选择 | L3 | review_a001_h | 已闭环 | verify_a001_h | 已闭环 | G09后F-152升条件P1，F-153驳回并仅留P3测试；F-027/F-036/F-060/F-072/F-087与CHK-005传播闭合 | W018、I009、G09 | 已闭环 |
| V022-C | `TransferHistoryViewModel.swift:282-450`，轮询、游标与结果合并 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G09后F-154驳回、F-155/F-232维持P2；F-204历史裁决维持条件P1且TV修复已由`81d42fb`提交；其余传播闭合 | W018、I009、G04/G09 | 已闭环 |
| V022-D | `TransferHistoryViewModel.swift:451-551`，AI 重新整理 | L3 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | G09后F-098/F-156升条件P1、F-070升P2、F-203升P1；F-080/F-075/F-027/F-033/F-101传播闭合 | W018、I009、G09 | 已闭环 |
| V023 | `ContentViewModel.swift` 全文件 | L3 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G06将F-157升P2、F-089转确认P2；F-027/F-028/F-062/F-063/F-009/F-010/F-031/F-106/F-107/F-117/F-130/F-150传播闭合 | — | 已闭环 |

### 4.3 通用组件、Modifier 与 Sheet 基础

| 审查单元 | 范围/符号 | 依赖层级 | 主审代理 | 主审状态 | 复核代理 | 复核状态 | 发现编号 | 回溯依赖 | 最终状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C001 | `EmptyDataView.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G05将F-158升P2并把稳定后果锚定DownloadTask主行；其余透明sink保留运行边界，传播不变 | G05 | 已闭环 |
| C002 | `NotificationComponent.swift` 全文件 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-159确认P3；确认F-107传播、F-108未验证、H-012及F-049/F-093/F-126通知边界；旧计时关闭新通知竞态驳回 | G08 | 已闭环 |
| C003 | `ActionRow.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | G09后F-160/F-161均P2；F-156传播升P1，F-108及真实focus/VoiceOver仍未验证，F-092/F-094/F-095边界闭合 | G09/G10 | 已闭环 |
| C004 | `SheetStyles.swift` 全文件 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G09后F-162/F-165升P2，F-163/F-164维持未验证P3；F-120/F-147传播，loading/Toggle基础边界通过 | G10 | 已闭环 |
| C005 | `SheetTextField.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_h；verify_a001_h补充 | 已闭环 | F-166驳回；F-167维持未验证P3；确认F-074/F-076/F-147传播、F-120边界，16调用其余通过 | G10 | 已闭环 |
| C006 | `SheetPicker.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G05按丢title/结构化selected语义将F-168升P2，真实初焦仍未验证；其余传播边界不变 | G10/G05 | 已闭环 |
| C007 | `ShelfPicker.swift` 全文件 | L4 | review_a001_j | 已闭环 | verify_a001_h | 已闭环 | F-169确认P3；确认F-033/F-139直接传播、F-035/F-138边界，F-158及Search/Explore专属条目不适用；动态身份/focus其余通过或运行未验证 | W005、G02/G04 | 已闭环 |
| C008 | `MultiSelectionSheet.swift` 全文件 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | W014跨端补强后F-170升级确认P2；确认F-112/F-114/F-130/CHK-005传播，F-163/F-165不适用，F-168限title子边界，F-147/F-148不扩展 | G10 | 已闭环 |
| C009-A | `MediaCard.swift:1-227`，来源与徽章 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G03将F-171升P2；确认F-019/F-020/F-026/F-084/F-105/F-106传播，F-114不适用，F-138留后段/调用者裁决 | G03 | 已闭环 |
| C009-B | `MediaCard.swift:228-425`，卡片主体 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-172确认P3，F-173维持未验证性能P3；整卡语义并入F-171，确认F-105/F-106/F-138/F-019/F-020/F-026/F-084传播，F-114/F-158/F-169不适用 | G03 | 已闭环 |
| C009-C | `MediaCard.swift:426-494`，Frame、详情包装与转场状态 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G03将F-174升P2；确认F-105/F-106/F-138/F-171传播，F-114不适用，F-172/F-173归B，loadingPosterURL归F-123 | G03 | 已闭环 |
| C010 | `PersonCard.swift` 全文件 | L4 | review_a001_h | 已闭环 | verify_a001_h | 已闭环 | F-175 P2；G04末裁将F-176升P2，F-177维持未验证性能P3；确认F-143/F-104/F-064/F-105/F-106/F-019/F-020/F-026/F-036/F-044/F-045传播 | G07 | 已闭环 |
| C011 | `MoreCard.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；确认F-175/F-173/F-003传播，F-033/F-035/F-036/F-138及F-171/F-172/F-174不适用；唯一调用/导航/边界其余通过 | G02 | 已闭环 |
| C012 | `BestResultCard.swift` 全文件 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-178确认条件性P3；F-076/F-172/F-174/F-177及搜索评分/身份传播闭合，F-171/F-175不适用；固定高度/完整overview仅留运行盲点 | G01 | 已闭环 |
| C013 | `MediaGridView.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；ID-only Equatable/旧items闭包仅留契约风险，四owner无同ID原位替换且Paginator当前门槛兜底；F-033/F-035/F-019/F-020/F-026/F-084/F-105/F-106/F-129/F-130/F-138/F-139/F-171…F-174传播闭合 | G03 | 已闭环 |
| C014 | `MediaContextMenu.swift` 全文件 | L4 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；8生产入口及F-014/F-015/F-054/F-077/F-090/F-103/F-113/F-119…F-124/F-174传播闭合；F-124已由`4a1a291`冻结菜单展示意图并接入destructive确认，聚焦5/5、完整本地450/450与独立复审PASS；无Fork presenter页仅留payload契约未验证 | G02/G03 | 已闭环 |
| C015 | `MediaActionModifier.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 无新编号；唯一ContentView根presenter及4入口闭合，F-090/F-122/F-123/CHK-005传播确认；重叠识别busy/alert/poster/导航归既有owner根因，overlay focus/accessibility留运行盲点 | G03 | 已闭环 |
| C016 | `SubscriptionModifier.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_h | 已闭环 | 无新编号；6个Handler/presenter、8入口与F-054/F-077/F-119/F-120/F-124/F-047/F-121/F-159/CHK-005/CHK-006传播闭合；F-124已由`4a1a291`接入共用destructive确认，聚焦5/5、完整本地450/450与独立复审PASS；F-048不适用直取消，F-049不适用Handler但仍传播至SubscribeSheet回滚 | G02/G03/G08 | 已闭环 |
| C017 | `TorrentCard.swift` 全文件 | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G05将卡片/筛选空白字符串F-179升条件P2；促销badge留契约盲点，其他传播不变 | G05 | 已闭环 |
| C018-A | `TorrentsResultView.swift:1-312`，结果过滤 | L4 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 无新编号；F-022/F-032/F-057/F-058/F-059/F-061/F-110/F-158传播闭合，onAppear首帧与同ID原位变化仅留运行/合同盲点 | G05 | 已闭环 |
| C018-B | `TorrentsResultView.swift:313-347`，模型与排序 | L4 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 无新编号；F-110 default+asc合法可选却仍固定降序，F-061根在A段；Swift自5.8文档化stable且项目SWIFT_VERSION=6.0，相等项保序；CI未锁精确Xcode小版本，nil/0与混合日期仅留合同盲点 | G05 | 已闭环 |
| C018-C | `TorrentsResultView.swift:348-462`，筛选 UI | L4 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-110/F-057/F-058/F-059/F-179/F-168/F-170传播，F-061根在A段；F-163/F-165有反证，筛选身份/禁用移除/focus/accessibility边界闭合 | G05/G10 | 已闭环 |

### 4.4 业务 View 与 Sheet

| 审查单元 | 范围/符号 | 依赖层级 | 主审代理 | 主审状态 | 复核代理 | 复核状态 | 发现编号 | 回溯依赖 | 最终状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W001 | `ManualMediaSearchSheet.swift` 全文件 | L5 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-076/F-099/F-178/F-172/F-158/F-165传播，F-177维持未验证，F-060/F-157/F-159/F-171/F-175/F-174不适用；AddDownload media_in分工仅留契约边界 | G01/G09/G10 | 已闭环 |
| W002 | `LoginView.swift` 全文件 | L5 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 无新编号；F-086/F-088/F-107/F-027/F-062/F-063/F-159传播，F-029无本View新增触发，F-089最终确认P2；no-access首次登录顺序通过 | G06/G08 | 已闭环 |
| W003 | `HomeView.swift` 全文件（当前1-486，覆盖原1-428） | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；既有finding/CHK传播闭合；后续G03将F-118/F-171/F-174升确认P2，F-012/F-017边界不变，F-158不适用；失败线程三次输出均作废 | G02/G03/G06/G08 | 已闭环 |
| W004 | `ExploreView.swift` 全文件 | L5 | verify_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-077/F-078/F-120/F-121/F-129/F-130/F-131/F-132/F-033/F-035/F-105/F-106/F-027/CHK-005传播；F-133/F-134/F-136未验证，F-135已确认P3，F-039/F-158不适用 | G02/G03/G05 | 已闭环 |
| W005 | `RecommendView.swift` 全文件 | L5 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 无新编号；既有传播闭合；F-079后经当前官方schema裁决确认P2，F-173及Fork presenter/合集route生产可达性维持未验证，F-158不适用 | G02/G03/G04 | 已闭环 |
| W006-A | `SearchView.swift:1-299`，根页与来源 Sheet | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-130/CHK-005/F-142/F-039/F-076/F-114/F-121/F-027/F-137/F-140/F-141/F-112/F-168传播；键盘提交为显式双模式按钮契约不立项，F-169不适用 | G01/G03/G10 | 已闭环 |
| W006-B | `SearchView.swift:300-435`，聚合结果 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-077/F-079/CHK-009等既有传播闭合；F-064维持未验证，F-139/F-158不适用 | G01/G02/G03/G04/G06/G07 | 已闭环 |
| W006-C | `SearchView.swift:436-592`，媒体与人物行 | L5 | review_a001_j | 已闭环 | review_a001_h | 已闭环 | 无新编号；分享投影F-077与Fork字段F-079传播闭合；F-064/F-173/F-177维持未验证，F-158/F-176不适用 | G01/G02/G03/G04/G06/G07/G10 | 已闭环 |
| W006-D | `SearchView.swift:593-713`，最佳结果 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；F-137/F-140/F-141/F-036/F-078/F-138/F-178/F-044/F-045/F-172/F-019/F-020/F-084/F-105/F-106/F-174/F-035/F-027/CHK-005/F-077/CHK-009/F-103/F-120…F-124/CHK-006/F-104/F-143/F-144传播；F-064/F-177维持未验证，F-171/F-173/F-175不适用，双FocusState/VoiceOver保留运行盲点 | G01/G02/G03/G06/G07 | 已闭环 |
| W007 | `MediaDetailContainerView.swift` 全文件 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | I013最终裁F-180 P2；后续G03将F-116升确认P2并保留可见时长/焦点运行边界，其他传播闭合 | G03/G06/G10 | 已闭环 |
| W008-A | `MediaDetailView.swift:1-402`，状态、初始化、主视图与生命周期 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | I013最终裁F-181保持未验证、条件影响校准P2；F-114/F-100/F-130/CHK-005/F-027/F-035/F-115…F-119/F-138/F-139/F-176传播闭合 | G03/G06/G10 | 已闭环 |
| W008-B | `MediaDetailView.swift:403-587`，订阅、刷新与 Header 动作规则 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | I008/I013回溯后F-182升P2；F-007/F-015/F-047…F-049/F-130/F-147/F-148及CHK-004/005/006/010传播闭合 | G02/G03/G06/G10 | 已闭环 |
| W008-C | `MediaDetailView.swift:588-842`，Hero 与详情内容 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | F-183维持未验证P3，I013新增F-231确认P2；F-123/CHK-005及Hero/详情投影/图片转场传播闭合 | G01/G03/G06/G07/G10 | 已闭环 |
| W008-D | `MediaDetailView.swift:843-979`，分季、导演与演员 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 无新编号；分季、人物身份/导航、分页、图片与卡片既有F/CHK传播闭合；onSeasonTap/initialSeason为死链清理项 | G02/G03/G04/G07/G10 | 已闭环 |
| W008-E | `MediaDetailView.swift:980-1113`，推荐、相似媒体与加载 UI | L5 | review_a001_h | 已闭环 | review_a001_j＋verify_a001_h | 已闭环（程序限制披露） | F-184合法正数合集条件P1，0/负数/parts未验证；后续G03将F-116升P2，F-033详情局部P3、F-231 P2不变 | G03/G04/G10 | 已闭环 |
| W009 | `PersonDetailView.swift` 全文件 | L5 | review_a001_h | 已闭环 | review_a001_j＋verify_a001_h | 已闭环 | F-185经第三裁决确认P2：足够长的合法biography进入“完整简介”Sheet后无ScrollView/分页/可移动焦点锚点，末尾没有可达路径；短简介仅降低触发频率。加载/无简介空action Button及空作品focusable Text并入F-158同根传播，不另编号。详情失败并入F-126，F-143/F-144等route/request、分页图片session、卡片传播闭合，F-176不适用 | G02/G03/G04/G06/G07/G10 | 已闭环 |
| W010 | `CollectionDetailView.swift` 全文件 | L5 | review_a001_j | 已闭环 | review_a001_h＋verify_a001_h | 已闭环（第三裁决污染披露） | 无新编号；`collection_id`存在即合集身份的route/value域问题并入F-184：0令TV/Web分路但无生产payload，负数为双方共同缺gate，后端不主动给子项注入父ID且原始part字段未知。首屏错误/无重试归F-033、离页不取消归F-035、稀疏身份归F-138、预取Cookie归F-026、session/空态/卡片语义等传播；首次body短暂空态未获第二票 | G02/G03/G04/G06/G10 | 已闭环 |
| W011 | `ResourceResultView.swift` 全文件 | L5 | review_a001_h | 已闭环 | review_a001_j＋verify_a001_h | 已闭环 | 后续G05将F-110/F-158升P2；F-186/F-187维持P2，业务error后补搜归F-080，可空促销因子归F-022，下载关闭/session归F-147/F-027 | G01/G05/G06/G10 | 已闭环 |
| W012 | `AddDownloadSheet.swift` 全文件 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | G09将F-188/F-189升条件P1，F-135维持P3；F-011仅保留TorrentInfo官方字段丢失，通用media原形留在CHK-003未验证边界；提交owner/session归F-147/F-027/F-120，旧搜索归F-076，下载器默认归F-145 | G01/G05/G06/G10 | 已闭环 |
| W013-A | `SubscribeSeasonView.swift:1-31`，页面包装 | L5 | verify_a001_h | 已闭环 | review_a001_h＋review_a001_j | 已闭环 | 无新编号；第三裁决确认季卡主操作由测试锁定直订/取消，onSeasonTap/initialSeason无生产消费，仅死链清理。Tab保留NavigationStack时`.task`取消后hasLoaded锁死同owner重载并吞取消晚启动请求，分别扩展F-126为P2与F-144；跨服分季缓存归F-065，非电影二分归F-015，包装route/owner/退出其余通过 | G02 | 已闭环 |
| W013-B | `SubscribeSeasonView.swift:32-428`，内容与交互 | L5 | verify_a001_h | 已闭环 | review_a001_j＋review_a001_h | 已闭环 | F-146/F-047确认条件性P1；临时订阅退出/Retry与`exist_ok`复用既有ID后误暂停/删除统一并入F-148 created/owner/session receipt并确认条件性P1。group default恢复及权限/session/卡片传播闭合 | G02/G03 | 已闭环 |
| W013-C | `SubscribeSeasonView.swift:429-506`，详情 Sheet | L5 | review_a001_h | 已闭环 | verify_a001_h＋review_a001_j | 已闭环（既往源码暴露披露） | 长overview并入F-185；S00与空白name/date/overview登记F-190确认P3；第三裁决确认width-only海报四态无法维持360×540，登记F-191确认P3。无写操作owner；可访问关闭与具体海报形态维持运行盲点 | G02/G10 | 已闭环 |
| W014 | `SubscribeSheet.swift` 全文件 | L5 | review_a001_h | 已闭环 | verify_a001_h＋review_a001_j | 已闭环（既往源码暴露披露） | F-147 Subscribe子项已由`a872737`修复；F-148/F-199条件P1仍开放，F-170/F-195/F-200 P2；total_episode与save_path合同形成CHK-013/014 | G02/G10 | 已闭环 |
| W015 | `ForkSubscribeSheet.swift` 全文件 | L5 | verify_a001_h | 已闭环（既往源码暴露披露） | review_a001_j | 已闭环 | G06将F-193升条件P1，F-194 P2；F-027/CHK-005与F-008/F-121/F-185/F-191传播闭合，F-164未验证 | G02 | 已闭环 |
| W016 | `StatusView.swift` 全文件 | L5 | review_a001_j | 已闭环 | review_a001_h＋verify_a001_h | 已闭环（W017下载源码暴露披露） | G09后F-149 P1、F-150/F-198 P2；F-192/CHK-012维持P1，F-091传播，Transfer转W019 | G06/G09 | 已闭环 |
| W017 | `DownloadTaskView.swift` 全文件 | L5 | review_a001_h | 已闭环 | review_a001_j | 已闭环 | 后续G05使F-024/F-095/F-196/F-197为P1，F-083/F-092/F-093/F-094为P2；CHK-015/016/017与F-091/F-192/CHK-012传播闭合 | G05/G10 | 已闭环 |
| W018-A | `ReorganizeSheet.swift:1-380`，表单 | L5 | review_a001_h | 已闭环（既往局部暴露披露） | review_a001_j | 已闭环（外围入口/ledger暴露披露） | G09后F-188/F-189/F-156为P1，F-147本段P2、F-206 P2；F-075/F-074/F-162/F-168确认，F-163未验证、F-166驳回 | G01/G09/G10 | 已闭环 |
| W018-B | `ReorganizeSheet.swift:381-520`，预览 | L5 | review_a001_h | 已闭环（既往局部暴露披露） | review_a001_j | 已闭环（W018-A/ledger暴露披露） | G09后F-151 P1且用户按当前官方Web v2对齐决定跳过，F-162/F-165 P2；F-073经clean-room窄裁确认P2，F-074/F-158/F-185维持，intent/logID provenance边界不变 | G09/G10 | 已闭环 |
| W019 | `TransferHistoryView.swift` 全文件 | L5 | verify_a001_h | 已闭环 | review_a001_h | 已闭环（调用链/V022既往暴露披露） | F-202 修复已提交（`670cf86`），验证及独立复审通过；G09后F-203/F-204/F-152/F-156为P1，F-201/F-205/F-232为P2，F-153/F-154驳回；F-204 TV修复已由`81d42fb`提交；F-165/F-185及F-246读取授权传播闭合 | G08/G09/G10 | 已闭环 |
| W020-A | `SystemView.swift:1-113`，根状态与主体 | L5 | verify_a001_h | 已闭环 | review_a001_h | 已闭环（V002下游既往暴露披露） | 无新编号；F-130/CHK-005常驻根页、F-144/F-157、F-109/F-111/F-112及F-126/F-060传播获两票；F-113/F-035/F-029本段不直接 | G01/G06 | 已闭环 |
| W020-B | `SystemView.swift:114-195`，页面容器与滑动导航 | L5 | verify_a001_h | 已闭环（W020-A局部暴露披露） | review_a001_h | 已闭环（W020-A边界暴露；误显W020-C头20行未用于结论） | F-208确认P3；F-130/CHK-005与F-185传播，F-161维持运行未验证；空白非法route确定，Back/Focus运行未验证，无手势滑动入口 | G06/G10 | 已闭环 |
| W020-C | `SystemView.swift:196-388`，根页、连接页与 App 信息 | L5 | review_a001_j | 已闭环 | verify_a001_h | 已闭环（W020-A/B、I015及F-207标题暴露披露） | F-207确认P3；F-216机制定向确认但重复编号并入F-107，401/403分类交叉F-089；F-027/F-130/CHK-005、F-111/F-162等传播闭合 | G06/G10 | 已闭环 |
| W020-D | `SystemView.swift:389-465`，推荐、站点与媒体源 | L5 | review_a001_j | 已闭环（W020-C/相邻辅助暴露披露） | review_a001_h＋verify_a001_h | 已闭环（既往W020/I015与必要上游暴露披露） | 第三裁决确认F-209/F-210为两条独立P2；F-214重复编号驳回并入F-109；CHK-018/019确认，F-112/F-126/F-130/F-170/F-189等传播闭合 | G01/G05/G06 | 已闭环 |
| W020-E | `SystemView.swift:466-552`，过滤页与通用行 | L5 | review_a001_h | 已闭环（W020-A/B及误显W020-C头20行披露） | review_a001_j＋verify_a001_h | 已闭环（既往W020/I015及必要上游暴露披露） | 第三裁决驳回F-211复合项并拆归F-126/F-081；F-215坏identity并入F-081且促其升P2，合法长名留运行风险；其余传播闭合 | G01/G05/G10 | 已闭环 |
| W020-F | `SystemView.swift:553-793`，路由、焦点与规则预览辅助 | L5 | review_a001_j | 已闭环（W020-C/D及相邻辅助暴露披露） | review_a001_h | 已闭环（W020-A/B/D/E及F段符号命中披露） | 无新编号；F-130/CHK-005、F-126、F-085、F-168、F-208传播；补充P2建议无新后果，F-208维持P3；Back/VoiceOver运行项交I016 | G05/G06/G10 | 已闭环 |
| W020-G | `SystemView.swift:794-932`，路由/焦点类型与 UIKit 返回观察器 | L5 | review_a001_j | 已闭环（C/D/E/F及G相邻暴露披露） | verify_a001_h＋review_a001_h | 已闭环（既往W020/I015/R001及G边界暴露披露） | F-217第三裁决确认独立P3：结构重建/task重启确定但只读GET与StateObject保留不足P2；F-130/CHK-005/F-208传播，window/Menu/Sheet交I016 | G10 | 已闭环 |
| W020-H | `SystemView.swift:933-970`，`SystemFilterRulePreview` | L5 | review_a001_h | 已闭环（A/B/D/E/F既往暴露；D符号索引已显933行披露） | review_a001_j | 已闭环（C/D/E/F/G暴露披露） | 无新编号；双审确认单条规则解析/预览/matcher分裂准确归F-085并由P3升P2，F-081数组/缺ID不加权；本地化/VoiceOver留全局或运行边界 | G05 | 已闭环 |

### 4.5 应用入口与根集成

| 审查单元 | 范围/符号 | 依赖层级 | 主审代理 | 主审状态 | 复核代理 | 复核状态 | 发现编号 | 回溯依赖 | 最终状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R001 | `Views/ContentView.swift` 全文件 | L6 | review_a001_h | 已闭环（多下游View/System、Content调用链与R002前13行暴露披露） | review_a001_j＋verify_a001_h | 已闭环（多段调用链与第三裁决输入污染永久披露） | F-218第三裁决确认独立条件性P3；F-106出口settings窗口与F-130/CHK-005异步owner交叉但不可互替，权限归F-028、媒体handler归F-130/CHK-005 | G03/G06/G08 | 已闭环 |
| R002 | `App/MoviePilot-TVApp.swift` 全文件 | L7 | verify_a001_h | 已闭环（W020/I015及G中ContentView必要链暴露披露） | review_a001_j | 已闭环（R001 owner搜索仅暴露第6/11行命中） | 无新编号；App级通知跨logout/排队重排并入F-107且须保留当前logout原因交接；Sheet层归F-108、VoiceOver归F-159运行验证；媒体handler归R001/F-130/CHK-005 | G06/G08 | 已闭环 |

## 5. 拆分文件集成复核

集成复核代理不得参与该文件任一分段主审；它须检查跨段不变量、共享状态、编码/解码边界和遗漏符号。

| 集成任务 | 文件 | 前置分段 | 集成代理 | 状态 | 发现编号 | 回溯依赖 |
| --- | --- | --- | --- | --- | --- | --- |
| I001 | `Models.swift` | M001-A…K | integrate_i001 | 已闭环 | 无新增；维持既有裁决 | G01/G02/G03/G05/G06/G07/G09 |
| I002 | `TranslationHelper.swift` | B006-A…C | integrate_i002 | 已闭环 | — | G07 |
| I003 | `APIService.swift` | A001-A…K | verify_a001_h | 已闭环（曾独立复核A001-H/J/K及大量API调用链，永久披露） | G02末裁后F-027/F-065/F-069/F-082/F-086/F-100为P1；F-083/F-087/F-106/F-080 P2，settings/session、strict envelope与三缓存owner传播闭合；malformed SSE当前fallback | G01/G02/G03/G05/G06/G09 |
| I004 | `SystemViewModel.swift` | V002-A…D | review_a001_j | 已闭环（曾独立复核全部分段及SystemView调用链，永久披露） | 无新编号；F-027/F-029/F-031/F-060/F-062/F-063/F-081/F-085…089/F-107/F-109/F-111…113/F-126/F-130/F-144/F-157/F-170/F-189/F-207/F-209/F-210及CHK-005/018/019传播闭合 | G01/G05/G06 |
| I005 | `MediaPreloader.swift` | V004-A…B | review_a001_h | 已闭环（曾独立复核V004-A/B及大量详情调用链，永久披露） | F-221/F-115 P2、F-220驳回；后续I013/G02/G03将F-180/F-118/F-119升P2、F-184升条件P1，F-117维持P3；其余传播校准 | G02/G03 |
| I006 | `ExploreViewModel.swift` | V009-A…F | review_a001_h＋review_a001_j＋verify_a001_h | 受限已闭环（现有三代理均曾主审某分段，不能宣称严格独立） | F-233/F-234/F-235/F-236 P2、F-237驳回、F-238未验证P3；G04 clean-room末裁确认path无唯一合同，程序限制不变 | G01/G04/G05/G06 |
| I007 | `SearchViewModel.swift` | V011-A…F | review_a001_j | 已闭环（曾独立复核全部V011分段及I012定向链，永久披露） | F-225确认P2；F-224机制并入F-137/F-141后驳回重复编号。其余source/session/error/扫描/SSE/规则/旧fallback/长度评分分别并入F-189/F-130/F-033/F-034/F-080/F-081/F-085/F-076/F-137与CHK-005/019，F-219继续驳回 | G01/G02/G04/G05/G06 |
| I008 | `MediaDetailViewModel.swift` | V012-A…C | review_a001_j | 已闭环（既往详情/订阅调用链暴露永久披露） | F-007 P1、F-182 P2；后续G03窄第三裁确认F-118 ownerless pin根因P2且保留运行边界，F-047/F-048/F-049/F-130不变 | G02/G03/G04/G07 |
| I009 | `TransferHistoryViewModel.swift` | V022-A…D | review_a001_j | 已闭环（既往Transfer/Search/W019调用链暴露永久披露） | G09后F-098/F-156/F-203/F-204 P1，F-071/F-155/F-205/F-232 P2，F-153/F-154驳回；F-204 TV修复已由`81d42fb`提交；其余传播闭合 | G04/G09 |
| I010 | `MediaCard.swift` | C009-A…C | review_a001_j＋verify_a001_h＋review_a001_h | 已闭环（既往Search/详情/System卡片调用链暴露永久披露） | F-020条件P1、F-239 P2；后续G03将F-171/F-174升P2，poster/session仍留F-123，其余传播不变 | G03/G06 |
| I011 | `TorrentsResultView.swift` | C018-A…C | review_a001_h | 已闭环（曾独立复核C018-A/B，永久披露） | F-032/F-057…059/F-061/F-110/F-168/F-179/F-186传播；第三裁确认F-061与F-175升P2，同ID更新交I012/F-219驳回，底部焦点保持runtime-only | G05/G10 |
| I012 | `SearchView.swift` | W006-A…D | verify_a001_h | 已闭环（既往W020与Search/ViewModel/Content调用链暴露永久披露） | F-219驳回、F-103 P2；F-076 P1，G04 clean-room末裁将F-035/F-039/F-137升P2，其余传播不变 | G01/G03/G04/G07/G10 |
| I013 | `MediaDetailView.swift` | W008-A…E | verify_a001_h | 已闭环（既往详情页面/Sheet、I010及审计索引暴露永久披露） | F-231 P2、F-184条件P1、F-180 P2、F-181未验证条件P2、F-033根P2/详情局部P3；后续G03将F-116升确认P2 | G02/G03/G04/G07 |
| I014 | `SubscribeSeasonView.swift` | W013-A…C | review_a001_j＋review_a001_h | 已闭环（严格整文件集成＋受污染定向独立复核；既往订阅/媒体调用链暴露永久披露） | F-012当前P2由导航投影缺失/优先级反转支撑；group raw限制改留Web共享且用户路径未验证P3边界；F-243及其余传播不变 | G02/G03/G10 |
| I015 | `ReorganizeSheet.swift` | W018-A…B | verify_a001_h | 已闭环（ledger/W019调用链暴露披露；review_a001_h独立复核完成） | G09后F-151/F-212/F-213均条件P1；F-212的TV独有100ms差异已由`a6cc428`修复，复合身份因当前Web共享且用户要求仅对齐Web而跳过TV单端增强；F-151/F-213同样因当前Web共享由用户决定跳过TV单端修复；intent/logID provenance、episode_part公共字段与Auto门控边界不变 | G01/G09/G10 |
| I016 | `SystemView.swift` | W020-A…H | review_a001_h＋verify_a001_h＋rounda_g01_recheck＋rounda_g02_third | 受限已闭环（参与代理均有W020/G01或其他会话组暴露，不能宣称严格独立） | G06将F-089转确认P2；F-106/F-111/F-112/F-240 P2，F-208/F-242 P3，F-241未验证P3；其余传播不变 | G01/G05/G06/G10 |

## 6. 开放依赖 / 回溯队列

> 最终状态：本节保留历史回溯索引，但所有条目均已取得`已确认`、`降级`、`已驳回`或`未验证`的最终处置并归为`已闭环`；`未验证`表示边界已明确而证据不足，不是仍在排队。

| 来源单元 | 受影响单元 | 新证据 | 待回答问题 | 状态 |
| --- | --- | --- | --- | --- |
| 启动基线 | 所有涉及 API/Model/ViewModel/核心业务逻辑的单元 | 规定的同级相对目录仍不存在；后续代理确认Web `19710a5f…`/`v2.13.6` 与后端 `a0ee99aa…`/`v2.14.4` 为clean Git仓库并按具体合同逐项对照 | 当前源码合同已可核对；实际部署版本、远端最新性与运行配置仍在各F/CHK中逐项标未验证，不保留全局阻塞 | 已闭环 |
| M001-B / F-001 | A001、权限/系统/媒体服务器/整理/转移调用单元、I001 | 共享 `FlexibleBool` 对带行尾真值字符串误降级 | 各调用者是否仅受 fail-closed 影响；上游是否会产生字符串 Bool | 已闭环 |
| M001-C / F-002 | M001-G、M001-I、A001-C/I/K、V004-A、V012-A、I001/I003 | 后台 `MediaInfoJSON` 解码可进入嵌套图片 URL 初始化 | `Person`/`SubscribeShare` 是否跨越 MainActor，最小统一边界是什么 | 已闭环 |
| M001-C / F-003 | A001-J、V017、W013-B/C、I014 | `season_number` 缺失/null/负值可在身份与动作路径被折叠或当成合法季 | 上游契约与 UI/订阅身份应拒绝还是过滤非法季号 | 已闭环 |
| M001-C / F-004 | A001-C/D/I、V004-B、各媒体分页器、I001 | `rawPayload` 与强类型字段重复持有完整深层 JSON | 是否依赖原始多态字段；真机内存幅度是否达到缺陷阈值 | 已闭环 |
| M001-C / F-005 | A001-D、V019、W016 | 状态模型非可选属性默认值不提供缺键 Decodable 默认 | 官方响应是否保证字段齐全；UI 混合快照风险是否成立 | 已闭环 |
| M001-A / F-006 | A001-J、V012-B、I001、I003、G02 | lookup raw 0 可遮蔽有效 legacy `mediaid` fallback | 订阅 DTO 的 zero/fallback 与删除目标是否统一正确 | 已闭环 |
| M001-A / F-007 | V012-B、W008-B、V018、I008、I013、G02 | 详情 Header 直订 builder 未复用完整 `detail.apiMediaId` 身份 | AniList/插件 source-only 媒体是否丢失订阅身份 | 已闭环；修复完成 `bb07772` |
| M001-A / F-008 | A001-J、M001-I、V008、V018、V006、V004、W003、W013/W015、G02 | 搜索完成及 Fork 成功仅失效缓存，未驱动已发布页面状态刷新 | 手动/自动搜索、rollback 与 Fork 的最终成功出口是否恰好发布一次事件 | 已闭环；修复完成（`789e9a7`） |
| M001-A / F-012 | M001-F、W003、A001-J、I001；2026-08-08当前上游三方复核 | `Subscribe.navigationMediaInfo()` 漏`anilistid/media_source/media_id`，并把legacy身份放到raw built-in之前，违反canonical→raw→legacy顺序 | 当前普通Subscribe七字段均为schema/DB/GET正式合同；canonical-only与AniList-only均为支持路径 | 已闭环：条件性P2；修复完成（`58c7e81`） |
| M001-A / F-013 | M001-D、全部 MediaInfo 解码入口、I001；2026-08-08官方Web v2.15.5/后端当前合同复核 | 正式清单称 `MediaInfo` 回退 legacy `mediaid`，当前模型无该字段 | Web类型/helper与后端响应schema均不支持仅legacy `MediaInfo`；同名路由参数为现场生成的`source:id` | 已闭环：已驳回；用户决定跳过修复 |
| B001 / F-009 | V023、A001、V002/I004、R001、W020、G06 | 无法解析的非空版本被警告层归类为“版本过低” | 三态语义与唯一解析结果应如何共享 | 已闭环；修复完成（`4c69ec9`） |
| B001 / F-010 | V023、A001、版本测试与发布流程 | 前置分隔符被解析器接受为合法版本核心 | 官方版本格式与最小拒绝边界 | 已闭环；修复完成（`4c69ec9`） |
| M001-C / F-011 | M001-D、A001-K、V016、W012、CHK-003；2026-08-08 当前Web/后端三方复核 | TV `TorrentInfo` 未声明 `site_cookie/site_ua/site_proxy/site_downloader`，搜索结果重编码为 `torrent_in` 时确定丢失 | 前三项被当前下载/字幕链消费；`site_downloader`仅在`/download/add`且顶层下载器为空时生效；通用MediaInfo嵌套raw依赖仍未验证 | 已闭环：条件性P2；修复已完成（`63767f9`） |
| M001-D / F-014 | V004、C014、W007/W008、TMDB 预加载测试 | 空白 `mediaid_prefix` 遮蔽有效 `source`，身份与跳转判断分歧 | 输入是否出现；所有来源选择是否统一规范化 | 已闭环 |
| M001-D / F-015 | V006、C014、W008/W013-A、权限/Header测试 | `canDirectlySubscribe == false`被调用者当成“必为电视剧”，通用入口会把nil/合集/插件类型送入分季页 | 其他媒体类型隐藏/禁用订阅入口及共享route gate | 已闭环；修复已完成（`f04f73f`） |
| B002 / F-017 | W003、C017、W015、S005 | 无时区日期固定按上海解释且过滤层复制假设 | 三类日期源的正式时区契约及过滤影响 | 已闭环；用户决定跳过修复 |
| B002 / F-018 | C017、I011 | TorrentCard body 每次重新编译固定正则 | 真机帧耗时是否达到缺陷阈值 | 已闭环；修复已完成（`94f18f2`） |
| B002 / F-021 | M001-E/M001-H、W017、W019 | 可选大小在显示前被折叠为 0 或 `"0 B"` | nil 是否代表未知；所有大小调用者应采用何种占位 | 已闭环；修复完成（`a0adaab`） |
| B003 / F-019 | A001-B/C/K、V004、R001/R002、G03/G06 | G06两票结合当前后端HttpOnly资源Cookie确认登出/同主机换端口后旧授权可继续，升条件P1 | 仅按旧会话已知host/path清资源Cookie并取消对应任务；部署属性/频率未运行 | 已闭环；修复完成（`90b40b4`） |
| B003 / F-020 | V004/I005、根视图及所有受保护图片调用者、G03/G06 | G06两票再次确认URL-only缓存/下载不区分账号Cookie；I010三票已按条件性账号差异闭合P1 | opaque session namespace仅用于受保护图，公共图继续共享；真实差异留未验证 | 已闭环；修复完成（`90b40b4`） |
| B003 / F-026 | S004、12个分页provider及对应View、G03/G04/G06 | G06补Kingfisher 8.10.0同URL跨modifier复用SessionDataTask证据；无认证预取链确认P2 | 预取与显示复用同一cookie modifier；跨账号持久隔离另归F-020 | 已闭环；修复完成（`90b40b4`） |
| M001-E / F-022 | A001-H/K、V011/V015/V016、C017/C018/W011/I011、G05/I001 | 单条资源缺字段可终止SSE并令同步fallback再失败；当前后端schema明确两个促销因子可为null，而TV要求非可空Double | 边界宽容的最小范围及有效项+null因子同批回归 | 已闭环；修复完成（`06d9fe5`），最终独立复审与本地测试428/428通过 |
| M001-E / F-023 | A001-G、V008/W003、G06/I001 | 最近媒体单项缺/null title 可令整批失败 | 当前 schema 是否允许空标题；中性内部标题语义 | 已闭环；修复完成（`af67839`） |
| M001-E / F-024 | V020/W017、G04/G05/G10/I001/I003 | 当前Web/后端复核确认schema允许缺hash，内置下载器通常给唯一hash；Web也有重复key覆盖但仅TV首次保留重复后第二轮Dictionary trap确定终止App；UUID仅导致每轮重建，不作为实际碰撞证据 | hash优先、name兜底；显式检测旧/新快照重复并失败关闭，普通name抖动单独留P3 | 已闭环；用户决定跳过修复（低频异常边界） |
| M001-E / F-025 | V008/W003、G06/I001 | 当前Web有id时只用id；后端六个内置producer通常提供稳定原生id，link可随host/playhost/token变化；TV把id+link组合并忽略server_id/item_id fallback | 服务器类型作用域下按raw→server/item→link→UUID取值，并用分支标签与长度前缀避免拼接碰撞；不改Home轮询 | 已闭环；修复完成（`8050051`），验证及独立复审通过 |
| B004 / F-027 | A001-B/C/D、S002、V002/V023、W014/W015、R001/R002、G06 | G06两票确认旧401/403读取当前凭据/baseURL并跨session重放；W015 requiredPermission链维持P1 | 单调epoch+动作requiredPermission，重登后复核并限制同owner一次重放 | 已闭环；修复完成（`90b40b4`） |
| B004 / F-028 | A001-C、V023/R001、权限消费VM、G02/G06 | 当前Web同样不在前台/路由切换刷新权限；TV冷启动已有权威刷新，403静默校验/自动重登仍有效；90b40b4已闭合任何正式session发布后的UI/cache收敛 | 不把token有效性校验扩成低频权限热同步；用户接受管理员运行中改权限需重登/重启 | 已闭环；已驳回（用户决定跳过） |
| B004 / F-029 | A001-C、V002/W020、V007/W002、G06 | 当前`reloginStoredSession`仅在显式no-access且epoch未变时清理旧会话；密码/网络失败保留旧会话，迟到旧候选不能登出新账号 | 空permissions与Web默认权限差异另归F-030继续核对 | 已闭环；修复完成（`90b40b4`） |
| B004 / F-030 | M001-B、A001-C/I003、I001、G06 | 当前官方Web会正常写入嵌套`permissions.features`，后端泛型dict不校验并在login/current原样返回；TV原`[String: Bool]?`合成解码会令整个身份失败 | 单一权限JSON边界只读取四个已知Bool；未知/坏值忽略，空/缺权限默认语义保持拆项 | 已闭环；修复完成（`ee5dcb4`），clean build、435/435本地测试及独立复审通过 |
| B004 / F-031 | S002、A001-B/C、V023/R001、G06 | `90b40b4`已拒绝空串，剩余仅纯空白token；当前官方后端JWT producer不产生，Web同样未校验，确定触发仅损坏存储/非官方兼容端 | 不为低收益异常输入增加TV差异化硬化；保留内部tokenless currentUser哨兵 | 已闭环；降为条件性P3，用户决定跳过 |
| M001-E / F-032 | S004、A001-H、V011/V015、C017/C018、W006/W011、I001/I011、G05 | torrent-only Context 可解码但 TorrentCard 静默 EmptyView；当前 MP 官方搜索链正常结果会创建 MetaInfo，schema 仍允许 null | 按 Web 对齐：只要求 torrent_info，元数据字段按可选值降级，标题回退 torrent.title | 已闭环；修复完成 |
| S004 / F-033 | 全部分页 ViewModel/View、G04 | Paginator 错误状态无人消费，错误上限后无保留列表恢复 | 按用户裁决保留三次错误上限，达到上限后统一通知用户重试，不增加按钮 | 已闭环；修复完成 |
| S004 / F-034 | V011/Search、G04 | SharedMediaFetcher 非终止空批被 Paginator 当成终页 | 稀疏媒体类型分布与空数组终页契约 | 已闭环；用户决定跳过并接受极端漏项 |
| S004 / F-035 | 所有固定owner分页ViewModel/View、G04 | in-flight Task跨await强持有owner；显式cancel/新搜索屏障有效，但页面owner离场无对应取消 | owner/session级取消；push/Tab/销毁语义与真实驻留时长 | 已闭环；用户决定跳过并接受低频资源驻留 |
| S004 / F-036 | V011/Search、V022/Transfer、对应 View、G04 | processor 只去重旧 items，漏页内重复 ID | 最终人物身份与批内可变seen；reset清空持久seen | 已闭环；修复完成并通过回归与全量测试 |
| B006-A / F-037 | A001-I、V004-A、V012-A、W008-C、I001/I002/I008/I013、G07 | 有效语言标签未经规范化而退化为原码 | 上游格式、BCP 47/别名支持边界 | 已闭环 |
| B006-A / F-038 | M001-C/D、A001-I、W008-C、I001/I002/I013、G07 | 空白 original_language 进入详情元数据分隔串 | 共享规范化与空展示值过滤位置 | 已闭环 |
| S004 / F-039 | V011-C/D/F、I007、W006、G04/G06 | 单waiter取消合理不传递，但整个search session废弃后共享Task/URL请求/cursor仍继续 | aggregate session取消且不误伤另一合法waiter | 已闭环；用户决定跳过并接受旧请求资源占用 |
| B005 / F-040 | B006-C、S006、V012-A、C010、W008-D、I002/I008/I013、G07 | 不同 job key 翻译为同一显示文本后未去重 | 产品词义还是显示边界去重 | 已闭环 |
| B005 / F-041 | M001-G、A001-I、B006-C、S006、V012-A、I001/I002/I003/I008/I013、G07 | job 大小写/换行/别名同时绕过翻译与优先级 | canonical key 与上游词表 | 已闭环 |
| B006-B / F-042 | M001-C/D、A001-I、W008-C、I001/I002/I013、G07 | 国家对象/字符串形态没有统一 alpha-2 规范化 | 上游形态与 alpha-3/别名边界 | 已闭环 |
| B006-B / F-043 | M001-C/D、W008-C、I001/I002/I013、G07 | 空/畸形国家元素在详情元数据生成空白分隔符 | 多态解码与最终空值过滤 | 已闭环 |
| B005 / F-044 | B006-C、C010、W006-C、I002/I012、G07 | 人物搜索直接显示 raw job，绕过职位翻译 | 搜索响应是否携带 job；统一显示入口 | 已闭环 |
| B005 / F-045 | S006、C010、W006-C/W008-D、I002/I013、G07 | roles-only 职员 Hero 有职位、卡片无副标题 | roles 投影与跨展示一致性 | 已闭环 |
| B006-C / F-046 | M001-C/D、W008-C、I001/I002/I013、G07 | 类型名未规范化且空/畸形类型进入详情元数据 | genre 输入契约与统一元数据过滤 | 已闭环 |
| S006 / F-050 | V012-A/I008、W008-D/I013、G07 | Hero 演员先 prefix(4) 后去重，无法补足 | 完整去重后截断与真实重复分布 | 已闭环 |
| S006 / F-051 | M001-G、C010、W006-C/W008-D、I001/I002/I013、G07 | hasAvatar 原始字段判定与最终 imageURLs.profile 不一致 | 可渲染头像单一判定 | 已闭环 |
| S006 / F-052 | M001-G、B006-C、V012-A、I001/I002/I008、G07 | 多值 roles 先拼接再整体查优先级 999 | roles 元素规范化/最小优先级 | 已闭环 |
| S006 / F-053 | S006/I002/G07 | mergeCrew 非空 existing 不能安全消费自身已翻译返回值 | 未用增量 API 删除或 canonical/display 分离 | 已闭环 |
| S006 / F-055 | M001-G、V011-B、W006-D、I001/I007/I012、G07 | Search 最佳结果用 TMDB profile_path 而非 source-aware imageURLs | 跨来源人物头像准入与排名 | 已闭环 |
| S006 / F-056 | A001-I、V012-A、W008-C、I001/I003/I008/I013、G07 | Person 模型允许 nil/空 name，Hero 先截断且 View 不滤空串，模型到 UI 触发链已闭合 | 上游 name 契约与真实频率留作未验证；下游只核对回归覆盖 | 已闭环 |
| S003 / F-057 | M001-E、A001-H、C018-A/I011、G05 | 季/集范围终点未解析或校验 | 真实范围语法与实际覆盖顺序 | 已闭环 |
| S003 / F-058 | B002/F-018、C017/C018-A/I011、G05 | 卡片格式化与筛选排序支持的季集语法不一致 | 单一解析语法与上游格式 | 已闭环 |
| S003 / F-059 | M001-E、A001-H、C018-A/I011、G05 | 解析失败/Int 溢出静默折叠为合法零值 | invalid 状态与排序位置 | 已闭环 |
| S003 / F-061 | S005、C018-A/I011、V011/V015、G05 | CustomFilterService 的软过滤置尾会被结果页首次默认排序和后续排序覆盖 | 默认保留后端顺序，显式排序在正常/软过滤全局分区内执行 | 已闭环；修复完成并通过回归与全量测试 |
| S002 / F-062 | A001-B/C、V002-B、V007、V023、R001/R002、G06 | 两票确认删除失败后旧token重启复活，升条件P1 | 高权威logout tombstone/session revision先于Keychain恢复并重试删除 | 已闭环；修复完成（`90b40b4`） |
| S002 / F-063 | A001-B/C、V002-B、V007、V023、R001/R002、G06 | 两票确认四项独立来源可组合A token、B user/permissions与另一代credentials，升条件P1 | 四项记录绑定同一session revision且只接受同代 | 已闭环；修复完成（`90b40b4`） |
| M001-G / F-064 | A001-I、V012-A、V013、C010、W006/W008/W009、I001/I003/I008/I012/I013、G07 | 可选 PersonAvatar 将整个对象解为 `[String:String]`，混合类型可令整批失败，空首选可遮蔽有效后备 URL | 当前 avatar schema；混合类型/null/空首选应如何在模型边界降级且不丢整批 | 已闭环；修复完成（`af67839`） |
| M001-F / F-065 | A001-B/J、V017/V018/V021、W013/W014/W018、I003、G02/G06 | 三缓存无session/baseURL且旧请求可回填新会话，最终进入错误季/组订阅payload；末裁P1 | 复用session generation清理并在store前拒绝旧owner | 已闭环；修复完成（`90b40b4`） |
| M001-F / F-066 | V018/W014、A001-J、W013、G02 | 订阅编辑页用 `type + tmdbid != nil` 放行辅助或非正 raw TMDB ID，违背主身份边界 | 既有跨源订阅字段组合；所有剧集组入口是否统一复用主身份与正 ID 判定 | 已闭环 |
| M001-F / F-067 | V018/W014、A001-J、G02/G10 | 可选剧集组请求与核心配置共用总 do/catch，失败会清空选项并禁用保存 | 产品是否有意阻断无关编辑；best-effort 隔离与原 episode_group 保留 | 已闭环 |
| M001-F / F-068 | A001-J、V008/W003、V017/W013、BackendCompatibilityTests、G02/G06 | Subscribe 快照允许 nil/0/重复 id 进入 SwiftUI，而动作全部要求业务 ID | 上游 ID 保证；快照应拒绝整批还是过滤单条并报告 | 已闭环 |
| M001-F / F-069 | A001-J/I003、V018/W014、G02 | 封闭CodingKeys完整PUT折叠unknown/absent/null/default；当前后端全量update已有持久反例，末裁转确认P1 | 原快照/dirty-field overlay；与F-199共享lossless edit根 | 已闭环 |
| M001-H / F-070 | A001-D、V002/V019/V022/W016/W019、G01/G06/G09 | `AI_AGENT_ENABLE != false` 将 nil/未知当启用；G09两票以当前后端/Web的nil默认禁用合同升确认P2 | 复用现有settings并仅在显式true时开放；部署版本留未验证 | 已闭环 |
| M001-H / F-071 | V022-A/I009、W019、G09 | 搜索替换的 escaping fetcher 闭包通过 `self.pageSize` 与 owner 形成强引用环 | 模型到 owner 的 ARC 根因已确认；下游只补释放回归 | 已闭环 |
| M001-H / F-072 | V022-A/C/I009、W019、A001-F、G06/G09 | 十秒轮询无 query/session generation，旧响应可写新 prependedItems 并推进游标；G04主审与独立复核均确认稳定跨查询污染，升P1 | 延迟 page-1 后改查询/换会话时列表与游标如何隔离 | 已闭环 |
| M001-J / F-073 | A001-F、V021、W018-B、I001/I003/I015、G09 | 全新clean-room窄裁最终确认P2：envelope success缺失/null/false均失败关闭；仅`success:true + data缺失/null`及item success缺失/null会fail-open，data `{}`与item false不触发 | data必填与item success必填的最小严格解码；正式producer不产该形态、运行未验证 | 已闭环 |
| M001-J / F-074 | V021/W018、A001-F、G06/G09 | 预览请求无表单/session generation，旧响应可在表单或会话变化后重新发布并打开Sheet；G09保留P2 | 复用session/form snapshot与operation generation | 已闭环 |
| M001-J / F-075 | A001-F、V021、W018-A、G09 | 批量后台整理逐条提交但不记录逐ID受理/失败/未尝试状态；G09保留P2 | 保留顺序请求并累计逐IDreceipt，仅重试失败/未发送 | 已闭环 |
| M001-J / F-076 | W001、A001-D、V021、G01/G09 | 新查询开始、空输入、失败、取消或session失效时未统一清旧items，旧媒体可在新owner上下文被选中；G01纠偏与G04独立复核确认跨owner动作链并升P1，成功空会正确清空 | 手动媒体 ID 搜索子项已修复（`44908c4`）；聚合 Search/Resource 的失败、取消、session 与延迟查询仍开放 | 已闭环 |
| M001-I / F-077 | V006/V009/V011、C013/C014/C016、W004/W006/W015、V004/W007、I001/I006/I007/I010/I012、G02/G03 | SubscribeShare 已解码/编码 bangumiid，但 toMediaInfo 漏投影，通用预加载/详情/分季/资源动作丢主身份 | Bangumi-only 分享的 Fork 与长按详情两条分叉；统一投影边界 | 已闭环；修复完成（`58c7e81`） |
| M001-I / F-078 | A001-J、V009/V011、W004/W006/W015、C013、BackendCompatibilityTests、G02 | 分享 raw ID 可选且未校验正/唯一，fallback 使用可变标题/用户或 UUID，raw 0 共享同一 ID | 上游 ID schema；缺失/0/重复对分页去重、焦点与 Fork 目标的传播 | 已闭环 |
| M001-I / F-079 | A001-J、V006、W015、I001/I003、G02；2026-08-08当前Web/后端合同复核 | SubscribeShare未声明`anilistid/media_source/media_id`，GET解码后Fork与投影均丢失 | 三字段均属当前Share GET/Fork schema；legacy mediaid与未知extra不在合同，不做raw透传 | 已闭环：由未验证转确认P2；修复完成（`58c7e81`） |
| M001-K / F-080 | A001-H、V011-C、V015/W011、V022-C/D、I003/I007/I009、G01/G05/G09 | Search/Resource/AI三类SSE消费者不记录合法终止；G09主审P2、独立复核P1，单方升级不足，保留确认P2 | done/error/enable=false/EOF共享终止分类、业务error不得进missingSites及AI重复触发边界 | 已闭环 |
| M001-K / F-081 | A001-I、S005、V002/V011/V015、W020、I003、G01/G05 | `[CustomRule]` 原子解码，单条坏项令整份配置失败；调用者静默使用未过滤结果且设置页可保留旧规则；G05 主审P2、独立复核P1，单方升级不足，保留确认P2 | 坏项隔离与规范化后 ID/name 非空唯一已实现；用户接受已选规则缺失时静默不过滤 | 已闭环；修复完成（`670cf86`），验证及独立复审通过 |
| M001-K/S005 / F-085 | V002/W020、I003/I004/I016、G01/G05 | 规则预览、规范化、TV matcher 与后端失败语义分裂；G05双审确认P2 | 共享canonical解析/校验及已选规则错误提示；部署差异留未验证 | 已闭环 |
| A001-A / F-082 | A001-C/D/H/J、V002/V008/V011/V015/V017/V018、I003、G01/G02/G06 | `success:false`可解data先返回并发布/缓存，后续动作可继续；G02末裁条件性P1 | 已修复（`d8198fc`）：先判显式业务失败；错形data仅在目标解码失败后用既有JSONValue取本地化错误，保留success缺失及原始对象/数组兼容；聚焦测试、Simulator clean build、本地438/438测试与独立复审通过，5个真实后端兼容套件未运行 | 已闭环 |
| A001-A / F-083 | A001-E、V020/W017、I003、G05/G06 | G06主审与既有W017/I003确认非对象/畸形非空2xx被下载mutation当成功；当前官方JSON合同不降既有P2 | 非空响应复用strict decoder；空body只按端点显式合同接受 | 已闭环 |
| A001-A / F-084 | A001-D/I/K、V004、C009/C010/C017、I003/I005/I010、G03/G05/G06/G07 | G06两票确认上游允许第三方绝对URL且无TMDB路径保证，稳定改写host/query/签名，升P2 | 所有图片出口统一只改精确TMDB `/t/p/original/` 路径段 | 已闭环 |
| A001-B / F-086 | A001-C/D/H/I/J/K、V007/W002、V002/W020、R001/R002、I003、G01/G02/G06 | 原样baseURL产生双斜杠/无效URL，且失败认证前已污染旧会话；G02末裁条件性P1 | 局部candidate校验/认证成功后一次canonical commit | 已闭环；修复完成（`90b40b4`） |
| A001-B / F-087 | A001-C/D/E/F/H/I/J/K、所有API错误调用者、I003、G01/G02/G05/G06/G09 | trim前首选让空白message_i18n遮蔽有效detail；G02末裁升级P2 | 所有错误入口逐项trim/filter后取首值；频率未验证 | 已闭环 |
| A001-B / F-088 | A001-C、V007/W002、V009-A/E、SystemSessionBehaviorTests、I003/I006、G05/G06 | G06两票确认login form特殊字符边界，动态query由既有G05/I006闭合，维持P2 | 标准form percent encoder；query复用单一encoded append | 已闭环 |
| A001-C / F-089 | A001-B/C、V007/W002、V002/W020、V023/R001、I003、G06 | G06两票核当前后端凭据/MFA失败为401，System手动刷新默认先logout旧有效会话 | 转确认P2；登录禁通用鉴权重放，401/MFA、403、网络与no-access分流 | 已闭环 |
| A001-D / F-090 | V005/V004、W007、C014/C015、MediaDetailContainerView、TMDB 测试、I003、G03 | search/recognize 四个成功出口用 if-let 接受 tmdb_id 0，调用者不再做正值校验 | 0/负值候选、后续正 ID fallback与共享 validNumericIdentifier 边界 | 已闭环 |
| A001-E / F-091 | V020/W017、V001/G08、I003、G05/G08 | 首次下载器列表失败后轮询只刷新任务且空客户端直接返回，页面不再重试客户端 | 错误与真实空列表的区分、空客户端恢复入口及用户可见重试 | 已闭环 |
| A001-E / F-092 | V020/W017、I003、G05/G06 | W017双审确认轮询/旧响应可反写正确状态且无in-flight gate允许双击重复mutation，升级P2 | 单行串行、冻结目标状态，成功赋值或刷新，禁止盲toggle | 已闭环 |
| A001-E / F-093 | V020/W017、V001/G08、S001/F-060、I003、G05/G08 | W017双审确认clients/list/三动作全部错误仅print，假空/陈旧/无声失败覆盖完整页，升级P2 | loading/empty/error/stale/data、可聚焦重试、主动动作错误通知与成功静默 | 已闭环 |
| A001-E / F-094 | M001-E/F-024、V020/W017、I003、G05 | nil/空/全空白/分隔符hash在模型、UI gate与API path边界分裂；G05两票均认为原P3不足，取共同下界升P2；Dictionary trap归F-024 | 非空规范化path segment与上游hash合同；无可靠身份时禁动作并反馈 | 已闭环 |
| A001-E / F-095 | V020/W017、I003、G05/G06 | W017双审确认B慢/失败时A旧行仍可达，同hash可删除B任务及文件，升级条件性P1 | 已修复（`7b7130e`）：列表记录实际loadedClient，选择不一致即禁旧行；三种mutation显式携带并前后校验行所属客户端。聚焦8/8、Simulator clean build、本地439/439测试及最终独立复审通过，5个真实后端兼容套件未运行 | 已闭环 |
| A001-G / F-096 | V012-A/W008、A001-B/C、I003、G03/G06 | best-effort `/mediaserver/exists` 复用默认 401/403 自动重登/登出 | 与 `/notexists` 一致的非破坏性探测参数及旧响应 session 归属 | 已闭环 |
| A001-G / F-097 | V008/W003、F-023/F-025、G03/G06 | 单服务器轮询错误被转为空数组并整体替换旧媒体快照 | G03窄第三裁确认P2；成功空与失败/取消分流，焦点恢复仍属运行验证 | 已闭环 |
| A001-F / F-098 | V022-D/W019、M001-J/F-075、I003/I009、G09 | G09两票确认当前后端/TV只有整批结果、无逐IDterminal receipt，升条件P1 | 用户决定保持整批错误通知与权威刷新，不做TV单端逐ID推断 | 已闭环（用户保持现状） |
| A001-F / F-099 | W001/V021/V016、A001-D/F-090、I003、G01/G05/G09 | G09两票确认0等同后端未提供且负值遮蔽fallback，升条件P2 | 复用正ID helper，无效原生值继续尝试规范fallback | 已闭环 |
| S001 / F-060 | A001、S005、V008、V011、V015、V021、W001及全部直接 print 调用者 | 默认 Logger 按设计仅 Debug 输出，但 15 个文件的 80 个直接 print 在 Release 保留且绕过隐私边界 | 各调用者应删除还是改经 Logger；若未来启用 Release handler，哪些值须先脱敏分级 | 已闭环 |
| B007 / F-047 | M001-F、A001-J、V006/V008/V012-B/V017、W003/W008-B/W013、G02 | 当前后端已对所有身份按season筛选；剩余为同媒体同季多group/多owner时文案只展示一条，媒体级删除却可能命中多条 | 当前Web共享媒体级删除行为 | 已闭环；用户决定跳过 |
| B007 / F-048 | V012-B、W008-B、A001-J、I008/I013、G02 | Header 确认后重新解析目标，未冻结精确订阅ID | 当前Web同样确认后读取当前媒体再执行媒体级删除 | 已闭环；用户决定跳过 |
| B007 / F-049 | V008/V012-B、W003/W008-B、V001/G08、G02 | Home/Header Bool 业务失败静默 | 失败通知与远端已删除的静默收敛边界 | 已闭环；修复完成并通过回归与全量测试 |
| B007 / F-054 | V006、A001-J、M001-F、C014/C016、G02 | 历史问题：Handler丢精确订阅ID并对Bangumi-only改发集合式媒体删除 | `58c7e81`已保留canonical/Bangumi/AniList/legacy身份，当前后端按身份与season筛选 | 已闭环；当前实现已解决 |
| A001-J / F-100 | V004/V012-B、A001-J/I003、G02 | 同键旧normal/force可覆盖新强刷并反转add/cancel判断；末裁条件性P1 | 每key latest revision；旧结果store/return均失效 | 已闭环 |
| A001-H / F-101 | A001-H/I003、V011/V015/V022、BackendCompatibilityTests | 生产与兼容探针均逐物理行解码 SSE，未按空行组帧及合并多条 data | 当前后端 framing、注释/heartbeat 与共享最小事件组帧边界 | 已闭环 |
| A001-H / F-102 | A001-F/H、V022/I003、G05/G09 | 静态path拼接脆弱，但两轮复核确认当前producer仅安全字符 | 转未验证P3；保留path-segment硬化与部署fixture，不宣称当前生产触发 | 已闭环 |
| A001-H / F-103 | V005/V015、C014、W003/W008、G01/G03 | 标题和媒体 ID 共用 keyword，消费端以宽正则猜路由且 builder 可产空字符串 | Web 当前路由规则、无身份媒体入口与显式最小路由意图 | 已闭环 |
| A001-I / F-104 | M001/A001-D/I/J/K、V004/V012/V013、I003/G03/G07 | 动态媒体 ID、人物 raw ID、豆瓣辅助 ID 或 EpisodeGroup.id 直接插入 URL path，保留字符可改写路由 | 上游 ID 字符集、后端 percent-decoding 与共享单路径段编码边界 | 已闭环 |
| A001-K / F-105 | A001-K、模型图片包装、V004/V008/V012/V013、各卡片/View、I003/I005/G03 | 相对或带空白图片值未按 origin 解析为规范绝对 URL | 当前 Web/后端相对地址契约、字段来源语义与共享 displayImageURL 边界 | 已闭环 |
| A001-K / F-106 | Models图片预计算、V023/R001、V004、各持有旧模型页面、I003/I005/G03/G06 | I003/I016/G06多票确认settings两段跨session发布与预计算URL固化旧配置，最终P2 | 各await/发布绑定epoch；生产包装按访问消费当前配置 | 已闭环 |
| V001 / F-107 | V007/W002、R001/R002/W020-C、C002、G06/G08 | G06一票反对但另一票支持；既有G08三方曾确认App级旧session通知/排队show跨根并裁P1；后续主触发已修复 | 剩余仅切号完成后的旧调用者晚到show，降P2且用户决定跳过 | 已闭环 |
| V001 / F-108 | C002/R001、V017/W013、V022/W019、G08 | 根通知可能在独立 Sheet 下不可见却照常计时并过期 | tvOS 模态层级运行证据、延后消费或可见时计时边界 | 已闭环 |
| V002-A/B / F-109 | V002-B/D、V003/V011、W020、I004、G01/G05/G06 | G06两票确认tuple碰撞外还以credential username而非currentUser定owner，token-only/轮换可落错bucket，升P2 | canonical baseURL+权威currentUser版本tuple，异步写回冻结key | 已闭环 |
| S005 复核 / F-110 | C018-A/B/C、I011、G05/G10 | 默认排序字段选择升序时比较器仍固定按pri_order降序；G05两票确认稳定控制/比较器冲突并升P2 | 默认字段方向契约、菜单/箭头与排序行为最小回归 | 已闭环 |
| V002-A 复核 / F-111 | V002-B/D、V003/V011、W020、I004、G01/G05/G06 | G06两票确认合法token-only身份与credential username分裂；既有I016已升P2 | profile/display用currentUser，credentials只作重认证秘密 | 已闭环 |
| V002-C / F-112 | V002-D、V003、V011-C、W020-A/D/F、I004/I007/I016、G01/G05/G06 | G06两票确认站点成功空/失败/旧选择四态及旧ID继续发送，维持P2 | success-empty清选择；error/cancel/stale分流并提供现有retry | 已闭环 |
| V002-D / F-113 | V005、V007、V015、W003/W011、C014、R001、I004、G01/G05/G06 | G06两票确认A读→await→按B key写回/返回A值；等级冲突保留既有条件P2 | 冻结canonical profile key+session，失配不写不返回 | 已闭环 |
| V003 / F-114 | V011-C/D、V012-A、W006-A、W008-A/C、I007/I008/I012/I013、G01/G03 | 父 ViewModel 固定持有 SiteFilter 子 ObservableObject，却未转发其 objectWillChange | 两个父 VM 事件桥接、按钮文案刷新及无关重绘前状态 | 已闭环 |
| V004-A / F-115 | V005、V012-A、W007/W008、I005/I008、G02/G03 | 详情 ready 只看 title/tmdb/douban 是否 nil，放行空白/非正值且遗漏其他合法身份 | 共享身份有效性、无标题详情契约与 ready/重试/展示矩阵 | 已闭环 |
| V004-A / F-116 | V012-A、W008-A、I008、G03 | 预加载命中立即撤遮罩，但背景 URL 要等视图异步 task 才安装 | Simulator/真机首帧可见性、焦点与遮罩/同步灌入最小边界 | 已闭环 |
| V004-A / F-117 | V004-B、V023、R001/R002、I005、G03/G06 | 取消先于 Kingfisher handle 安装时，请求仍启动且失去取消能力 | 取消标记/handle 原子安装、注销 Cookie/URL-only 缓存传播与最小竞态测试 | 已闭环 |
| V004-B / F-118 | W003…W008、V012-A、I005/I008、G02/G03 | pin 无 owner/refcount，通用 onDisappear 在非 pop 场景也解除保护 | 根因经G03窄第三裁确认P2；push/Tab/State端到端时序与真机可见影响保留运行未验证 | 已闭环 |
| V004-B / F-119 | V006、C014/C016、I005/I010、G02 | cache 以 UI id 存多个 canonical alias，findTask 只任意回写一个 | 所有 canonical alias 同步、菜单标签收敛与 max30 线性扫描回归 | 已闭环 |
| V006 / F-120 | C014/C016、W004/W005/W006-C/D/W008-E/W009/W010、G02/G08/G09/G10 | 页面/Sheet无目标owner；卡片主要为动作丢失/迟到UI，Reorganize交叉与当前Web一致且本项未证明错目标mutation | 降P2；用户决定跳过，不做TV单端增强 | 已闭环 |
| V006 / F-121 | W015/W004/W006-A、C014、G02/G10 | Fork错误不绑定presentation/share/operation，A可污染B；末裁P2 | `(operationID,shareID,message)`与新presentation清理 | 已闭环 |
| V005 / F-122 | A001-D、W003、C014、W008、G08 | nullable TMDB 识别结果折叠无匹配、请求失败与取消，且 Home 标题回退仍触发不存在提示 | found/not-found/error/abort 分流及各入口独立呈现 | 已闭环 |
| V005 / F-123 | B004、V002-D、V007、V015、R001、W003/C014/W008、I003/I004、G06 | 高层 TMDB action 未绑定发起 session，后续请求、全局状态或导航可跨 profile | 按钮起点单调 epoch、重叠 action owner 与 A→B→A 回归 | 已闭环 |
| V006 / F-124 | V004-A/B、C013/C014/C016、V018/W014、各卡片页面、G02 | 显示“订阅”的意图可被fresh lookup反转成无确认DELETE；末裁条件性P1 | `4a1a291`已修复：冻结展示意图、lookup后统一校验session、mismatch只刷新提示、取消走destructive确认；聚焦5/5、完整本地450/450与独立复审PASS | 已闭环 |
| V008 / F-125 | A001-G、M001-E、W003、I003、G03/G06 | v2.15.1 Plex `/server/.../details?key=` 未被 TV 旧 `/media/...` 解析器识别 | 两种 URL 形状纯解析、machine/item identity 与 tvOS Plex 实机 scheme | 已闭环 |
| V008/W013-A / F-126 | W003、A001-G/A001-J、V001、G02/G06/G08 | Home把失败与成功空/旧快照共用状态；分季页又在成功前置hasLoaded，取消不复位使同owner重现无操作 | cold empty/hot stale、取消重现、只在完整成功锁门闩及现有retry恢复 | 已闭环 |
| V008 / F-127 | W003、A001-J、B007、G02/G08 | reset无确认即覆盖多项运行/优先级/人工字段；末裁条件性P1 | 用户决定跳过，保持当前直接重置行为 | 已闭环 |
| V008 / F-128 | W003、V001、G03/G08 | 不支持/非法媒体库链接及 openURL 拒绝只记录日志 | 能力隐藏、invalid/unsupported/rejected 返回值与用户反馈 | 已闭环 |
| V009-B / F-129 | V009-E/F、W004、I006、G01/G04 | Popular 无有效结构身份时按 title 去重，但 SwiftUI/Paginator 实际 ID 不含 title | fallback key 与 item.id 对齐、nil/0/跨页改名及最终 ID 唯一性 | 已闭环 |
| V009-A / F-133 | V009-E/F、W004、I006、G01/G05 | 插件 filter_ui 的 switch/multiple/custom item/dynamic 语义被 parser 静默删除或降为错误控件 | 固定真实 fixture、unsupported 可见提示与最小支持矩阵 | 未验证 |
| V009-A / F-134 | V009-E/F、A001-D、I003/I006、G01/G05 | 复合 filter 值被 JSON 化成单 query item，与 v2.15.1 Web Axios bracket 展开不同 | 数组/嵌套/null/空值/稳定顺序与标量显式限制 | 未验证 |
| V009-A/W012 / F-135 | W004、I006、G01/G04/G05 | 插件重复value及AddDownload空目录/内建自动都让option value同时作为ForEach ID与Picker tag；下载路径子项已确认，插件合法重复value缺当前生产fixture，保留确认P3及运行边界 | 插件JSONValue first-wins；目录trim后丢空再去重，保留唯一自动项 | 已闭环 |
| V009-C / F-130 | V009-F、W004、V023/R001、I003/I006、G01/G04/G06 | currentUser 权限已更新后，Explore 不重算来源或取消旧分享分页器 | `90b40b4`改由根级session UI identity重建全部Tab子树，并以epoch/runtime取消/缓存失效拒绝旧发布；聚焦96/96、既有独立复审PASS | 已闭环 |
| V009-D / F-131 | V009-E/F、W004、I006、G01/G05 | Douban/Bangumi/AniList用Calendar.current生成并直传API年份；G05两票支持升条件P2 | Gregorian当前年、三来源直传与AniList全部tag冲突；实际设备配置频率仍未验证 | 已闭环 |
| V009-D / F-132 | V009-E/F、W004、I006、G01/G05 | TMDB movie/tv 切换保留新 sort 字典不接受的独占 key | 双向独占 key 回落、共有 key 保留与 Picker/path 一致 | 已闭环 |
| V009-E / F-136 | V009-F、W004、I006、G01/G05 | Share 初始/切源默认 count，与 v2.15.1 Web 默认 time 相反 | TV 产品意图、两处 literal、首请求路径与默认 Picker 回归 | 未验证 |
| V011-A / F-137 | V011-B/C、W006-A、I007、G01/G04 | 无界长度罚分穿透四类评分带并改变最终top-12；G04末裁P2 | 类别互斥带宽、竞争项排序与top-12保留 | 已闭环 |
| V011-A / 权限 focus | V011-C、W006-A、I007、G01/G06 | 存活 SearchView 权限互换后可见按钮、旧 searchType、结果分支与 focus target 可能分裂 | 权限发布自动归一化、旧请求失效与 tvOS focus 可达性 | 已闭环 |
| V011-B / F-140 | V011-C、W006-A、I007、G01 | 搜索提交与本地最佳结果评分未共用规范化 query，尾随空白可让精确标题退化并被扩展标题反超 | 单次 trim 后请求/评分共用、纯空白不请求及换行边界 | 已闭环 |
| V011-B / F-141 | V011-C、W006-A、I007、G01 | TV 把首个任意 19xx/20xx 当年份，与目标后端年份边界不同，四位数字片名会误判 | 后端等价年份边界、`1917 2019`/括号/仅片名矩阵 | 已闭环 |
| V011-F / F-142 | I007、W006-A、G01/G04/G06 | 已完成共享 task 的 handle 仍非 nil，另一 waiter 可在下一轮重复 await；该轮游标2→2并返回非终止空批 | task完成时按 identity原子退休handle、双 waiter恢复顺序与第3页目标类型回归 | 已闭环 |
| V013 / F-143 | M001、W009、I001、G04/G07 | 纯name Person无route identity仍可进入死详情；详情可选字段覆盖公开person而credits继续使用入口owner | source/raw_id入口准入、共享route owner、展示字段fallback及string-person回归 | 已闭环 |
| V013 / F-144 | W009/W013-A、G02/G04/G07 | 人物详情吞取消后晚启动credits；分季剧集组catch吞CancellationError后继续启动季列表/状态阶段 | async let并发启动、各阶段先传播取消且不得晚启动、Paginator显式取消 | 已闭环 |
| V016 / F-145 | W015、C006、G05/G10 | 下载器初始nil可省略提交，选择非空项后同一Sheet无空tag恢复nil；G05两票升P2 | 复用默认空option、nil→非nil→nil与最终请求省略字段回归 | 已闭环 |
| V017 / F-146 | W013、G02 | 分组A慢响应可晚于分组B覆盖季度列表，而状态查询与提交又读取当前B，形成Picker=B、季度=A、可用性/载荷=B并创建错误远端订阅；组列表失败还可隐藏default恢复入口 | 分组请求owner、晚响应丢弃、default恢复及选择/季度/状态/提交同源回归 | 已闭环 |
| V018 / F-147 | W014、G02/G10 | durable PUT成功状态被View当成整个保存结束；W014双审闭合PUT先成功回调、已发DELETE后成功并永久删除订阅的P1反例 | 单一mutation phase约束取消/关闭、保留PUT durable边界并覆盖PUT/DELETE两种完成顺序 | 已闭环 |
| V018 / F-148 | W014、G02/G10 | loading分支可令Retry误删、退出/session变化遗留；当前后端`exist_ok=True`复用既有ID，TV丢失created/reused后又无条件暂停并可取消删除 | 稳定根生命周期、同session created/owner receipt、reused ID禁pause/delete及Retry/晚返回恰好一次处理矩阵 | 已闭环 |
| V019 / F-149 | W016、G06/G09 | G09两票确认混合快照外，同权限A响应可写入B会话，升P1 | 局部收集三结果、校验发起session后一次发布；失败保留完整旧快照并标stale/error | 已闭环 |
| V019 / F-150 | W016、G06 | W016双审确认全部合法manage-only用户每次进入都会稳定看到三块superuser伪空态，升级P2 | 复用现有superuser权限隐藏/说明三卡，并保留下载与转移功能回归 | 已闭环 |
| V021/I015 / F-151 | W017、G09/G10 | G09两票确认不同intent/logID可预览一次却仍执行多次文件mutation，升条件P1 | 当前官方Web v2共享同一行为；用户决定跳过TV单端修复，若未来上下游共同处理再统一preview/submit intent规则 | 已闭环 |
| V022-B / F-152 | W018、I009、G09 | alert文案/action读取实时选择；结合SQLite同ID复用可确认A却删除B，G09两票升条件P1 | 呈现alert时冻结对象签名数组，文案/action共用 | 已闭环 |
| V022-B / F-153 | V022-C、W018、I009、G04/G09 | G09两票证明稳定排序下删除回退足够补偿，原永久漏页反例不闭合 | 驳回独立编号；只补组合测试，排序归F-232、身份复用归F-204 | 已闭环 |
| V022-C / F-154 | W018、I009、G04/G09 | G09两票证明稳定排序下整页推进与余数重叠去重自洽 | 驳回独立编号；只补1/19/20/21项测试，不稳定排序归F-232 | 已闭环 |
| V022-C / F-155 | W018、I009、G04/G09 | 第5个满页未遇已知项时仍请求page6，但循环顶端因上限退出而完全丢弃响应；101st新项随后不可恢复 | 扫描不完整时不得提交前缀/推进游标，复用顺序Paginator路径并补101项回归 | 已闭环 |
| V022-D / F-156 | W018、I009、G09 | G09两票确认选择/删除/AI/整理只持可复用ID或实时选择，旧A动作可改变同ID新B，升条件P1 | 与F-152/F-204共用session/query和对象签名快照 | 已闭环 |
| V023 / F-157 | W001、G06 | G06两票确认失败/取消占terminal key后同session成功无收敛入口，升P2 | 仅有效版本/明确不兼容占key；unknown/failure可重试 | 已闭环 |
| C001 / F-158 | W003/W009/W011/W016/W018/W020、G05/G06/G07/G09 | 多类无action焦点目标成立；G05两票把稳定P2后果锚定DownloadTask主行空Button，其他透明sink保留运行边界 | 有主动作放入原生Button action；无主动作删除空节点并做tvOS/VoiceOver验证 | 已闭环 |
| C002 / F-159 | W001/W013/W018、V001、G08 | 五秒全局错误toast是多条链唯一反馈，但全仓无announcement，三条onChange producer show后立即清自身错误 | 每次accepted show逐次播报type+message，icon装饰并组合单一元素；同文案主动重试仍播报 | 已闭环 |
| C003 / F-160 | W018/W020、G09/G10 | 主控件为空Button而实际动作挂raw gesture；G10/G09确认P2 | 主选择进入原生Button action；无主动作改普通内容，长按保留独立语义 | 已闭环 |
| C003 / F-161 | W018/W020、G09/G10 | 非活动行Button只opacity(0)，仍构建/绑定focus；G09两票取共同下界升条件P2 | 原生disabled/hit-testing/accessibility门禁；真实落焦频率留运行验证 | 已闭环 |
| C004 / F-162 | W012/W014/W018-A、G09/G10 | 长错误/路径强制单/双行且无完整入口；G09两票升P2 | 删除限制并纳入现有ScrollView | 已闭环 |
| C004 / F-163 | C006/C008、W012/W014/W018-A、G10 | tvOS 26.0–26.3自定义Button/Toggle样式忽略isEnabled，禁用控件与启用未聚焦外观相同 | 现有样式读取Environment isEnabled并统一降低不可用态对比度；需目标OS视觉验证 | 未验证 |
| C004 / F-164 | W015、G10 | Fork唯一SheetActionButton所在根树未调用applySheetStyles，漏过仓内26.0–26.3修补 | Fork根容器补一次现有modifier；需目标OS原始渲染/焦点验证 | 未验证 |
| C004 / F-165 | W015/W018-B/W019、G09/G10 | 多个业务Sheet无内容内关闭且测试反向固化；G09两票升P2 | 复用dismiss加原生关闭/取消；保留系统Back但不声称focus trap | 已闭环 |
| C005 / F-166 | W018-A、G10 | tvOS 26.0–26.3桥接不转发isEnabled且强制canBecomeFocused，但唯一disabled在两个生产入口上恒false | 当前生产触发不可达，保留未来入口的防御性桥接测试即可 | 已闭环 |
| C005 / F-167 | G10 | 26.0–26.3任一SheetTextField聚焦时直接改UIViewRepresentable托管根UIView的transform，违反SwiftUI托管几何契约 | 同时删除scale/identity两次根transform写入，复用已有白底/阴影；需目标OS运行验证 | 未验证 |
| C006 / F-168 | W006-A/W012/W014/W018-A/C018-C、G01/G10/G05 | 自建详情丢title、当前项无结构化selected语义；G05两票升P2，默认焦点实际行为仍未验证 | 复用现有title作heading、匹配行selected语义及最小默认焦点；当前值缺席继续保留raw | 已闭环 |
| C007 / F-169 | W005、G02/G04 | ShelfChip私有isSelected只控制视觉overlay，Button/Text未暴露当前货架选择语义 | 现有Button一行添加条件isSelected trait，不加自定义label/value或focus框架 | 已闭环 |
| C008 / F-170 | W014、G02/G10 | W014双审确认unknown-only站点可回退默认站点、规则组可fail-open，域外值不可见不可清由P3升级P2 | 显示并清除`selected - optionIDs`或提供定向清除；默认保留未知值、不自动求交 | 已闭环 |
| C009-A / F-171 | C009-B/C013、各MediaCard调用页、G03/G08 | 类型/评分/订阅入库状态/来源全部以Canvas symbols绘制，Canvas不为单个元素提供可访问性且无替代语义 | 在单一整卡owner拼接简短accessibilityValue；保留Canvas，不建卡片/图片框架 | 已闭环 |
| C009-B / F-172 | C013、各MediaCard调用页、G03 | nil/空/未知typeText的缺图占位统一回退film，电视剧订阅状态文本和季卡均被误标电影 | 未知类型用中性photo/rectangle.portrait；保留movie/tv/collection映射 | 已闭环 |
| C009-B / F-173 | C013、各MediaCard调用页、G03 | Kingfisher先downsampling再append硬编码256×384 resizing，processed-cache冷缺失等路径多一次raster pass | 删除resizing，保留downsampling+SwiftUI aspectFill/clip；需真机Instruments裁决 | 未验证 |
| C009-C / F-174 | 各MediaCard/无源详情入口、G03 | 所有主点击先写无目标/动作owner的全局sourceFrame；非详情动作残留可被后续无源详情Loading消费 | 优先删除手工sourceFrame飞入并保留loadingPosterURL；若保留，仅实际详情push写目标绑定一次性状态 | 已闭环 |
| C010 / F-175 | C011/各人物卡调用页、G07/G08 | PersonCard海报raw focusable/onTap承载动作，姓名/job为兄弟且无Button/整卡label/trait/default action | 复用原生Button承载整卡label/action；route无效同步禁用/隐藏，MoreCard同根传播 | 已闭环 |
| C010 / F-176 | W008-D/W008-E、G04/G07 | 三处FocusState变nil绕过threshold，重复离行可逐页加载；G04末裁P2 | 三处onChange在Task前guard let newId；保留Paginator合法无参手动加载 | 已闭环 |
| C010 / F-177 | W008-D/W006-C、G03/G07 | PersonCard只用ResizingImageProcessor，冷处理先构造原图再重绘分页人物头像 | 按实际width/height改DownsamplingImageProcessor；需真机Instruments/像质验收 | 未验证 |
| C012 / F-178 | I007/W006-D/W001、G01 | 评分消费备用名称而Search/Manual卡片只展示主名称，最高分有效结果可为空标题或“未知” | 评分与展示共用现有有序非空名称候选，并验证Button可访问名称；仅修复触及共享MediaInfo/卡片/导航helper时再纳入G03 | 已闭环 |
| C017 / F-179 | C018-C/I011、G05/G10 | 资源卡与筛选空白字符串遮蔽fallback并生成空标签；G05两票升条件P2 | 复用现有trim→空为nil投影供卡片fallback/标签与筛选三链共用 | 已闭环 |
| W007 / F-180 | W008-A、G03/G06/G10 | 详情连续失败后容器把`isDetailFailed`并入ready，显示未完整初始化的partial页面且当前页无失败标识/retry | I013裁P2；在现有Loading owner显示失败并让一次retry复用failed-task重建，保留partial fallback | 已闭环 |
| W008-A / F-181 | W008-C/G03/G10 | 内容页切换只监听Hero FocusState并交叉采样Content，真实回调若Hero先false、Content后true会漏置`showContentPage` | I013裁未验证条件P2；真机/Simulator固定事件序，确认后分别监听两个现有FocusState | 已闭环 |
| W008-B / F-182 | G02/G06/I008/I013 | scene回active与周期轮询共用当前订阅真假gate，旧false无法发现远端false→true；首次Header点击只强刷并静默终止旧意图 | I008双审升P2；前台恢复无条件复用现有强刷并保留点击前状态一致性guard | 已闭环 |
| W008-C / F-183 | G03/G06/G10/I013 | TMDB按钮在创建Task前无同步reentry owner，两个调用可重复append且先完成者提前清共享busy | 维持未验证P3；双Select须运行确认，离开route后的单动作晚到另由F-231 P2承载 | 已闭环 |
| W008-E/W010/I013 / F-184 | W003/W004/W005、G03/G04 | 合法正数合集可由正式动态来源进入三根栈，误送普通Container后preload永不ready/failed；0/负数与parts递归仍无fixture | 最终裁条件P1；原样复用Search合集分支与shouldPreloadDetail，未验证子域不顺手扩展 | 已闭环 |
| W009 / F-185 | W013-C/W015、G07/G10 | 足够长的人物简介、季overview或Fork分享文本在静态/限行Sheet内不可完整读取，Fork还可把提交按钮推出可达区 | 有限预览保留；信息区用原生纵向ScrollView/限行，操作区固定并验证遥控器/VoiceOver到达末尾 | 已闭环 |
| W013-C / F-190 | G02/G10 | S00缺名在详情显示“第0季”而卡片显示“特别篇”；空白name/date/overview生成空标题、图标空行或空壳区域 | 复用现有trim→nil与S00/正季/缺季号单一显示回退，覆盖可选文本矩阵 | 已闭环 |
| W013-C / F-191 | W015、G10 | processor按360×540降采样但外层width-only；缺图/失败只剩无2:3固有高度的Rectangle，四态无法保证稳定几何 | 两个Sheet直接固定360×540，覆盖URL缺失/loading/失败/成功并验证右栏与焦点不位移 | 已闭环 |
| W016/W017 / F-192 | A001-E/V020、G05/G06 | manage-only可见并操作其他用户任务；当前后端list/start/stop/delete只验token，owner回填仅按hash且TV无过滤 | 后端subject过滤与mutation鉴权、downloader+task复合owner、TV展示防御及superuser/API Token矩阵 | 已闭环 |
| M001-E/W017 / F-024 | V020/I003、G04/G05/G10 | 缺hash fallback无分隔拼接/UUID可重复；首次重复进入数组后下一轮Dictionary trap确定终止App，升级条件性P1 | 规范化不可变身份并显式循环检测重复后失败关闭；普通抖动单独按P3验收 | 已闭环 |
| W017 / F-196 | A001-E/V020、G05/G10 | TV只确认“删除任务”，当前后端默认delete_file=true且Transmission delete_data=true，正确目标也会永久删文件 | 后端显式参数且默认只删任务；危险动作明确不可撤销范围、downloader与任务名 | 已闭环 |
| W017 / F-197 | A001-E/V020、G05/G08 | G05两票确认qBittorrent/Transmission暂停后下轮从TV/Web消失且无继续入口，升条件P1；rTorrent行为不同 | 后端纳入全部未完成paused/stopped并排除已完成项，统一跨下载器矩阵 | 已闭环 |
| W014 / F-195 | C005/G02/G10 | 后端按LF拆分多条custom_words且Web使用textarea，TV单行输入无法创建或可靠审阅第二条规则 | 仅该字段使用tvOS多行编辑器，保留LF原值并覆盖未编辑round-trip与两行提交 | 已闭环 |
| W015 / F-193 | C016/W004/W006-A、G02/G06/G10 | G06两票闭合A POST→切B→B同号GET→错误编辑器，升条件P1；原逆序/部分成功链不变 | `(id,shareID,frozenSession)` receipt贯穿POST/GET/呈现，GET失败只重试GET | 已闭环 |
| W015 / F-194 | M001-I/C016、G02/G10 | POST立即持久化keyword/custom_words，但最终确认页不展示，用户无法预见即将生效的搜索规则 | CHK-009最小补强为只读展示两个非空字段并支持长/多行可达；其他字段待产品证据 | 已闭环 |
| W014 / F-199 | M001-G/A001-J/V018、G02/G10 | nil/absent无关保存变0并置manual，永久关闭自动刷新；G02末裁条件性P1 | 复用F-069 dirty overlay，只在用户实际编辑时编码新值 | 已闭环 |
| W014 / F-200 | M001-H/A001-J/V018、G01/G02/G10 | 保存路径是开放String；已有任意值及配置中已有URI保真，但封闭Picker无法新增/编辑任意合法子路径或URI | G01纠偏确认P2并关闭扩大说法；复用现有文本输入，配置路径只作快捷建议 | 已闭环 |
| W016 / F-198 | M001-H/V019、G06/G09 | G09两票以当前后端明确nil语义与Web“未获取”确认稳定误报，升P2 | View层nil→未获取且保留0/正数，覆盖全nil/混合服务与渲染矩阵 | 已闭环 |
| W016 / Transfer下游 | W019/V022-A…C/I009、G04/G09/G10 | Paginator错误、权威对账、焦点、session、长详情与search闭包均已由W019/I009/G09映射闭合 | 分别归F-033/F-072/F-185/F-204/F-205/F-232等，不由W016重复编号 | 已闭环 |
| W018-A / F-188扩展 | V021/A001-F、G01/G05/G09 | G09两票确认显式正ID被当前manual transfer忽略并可错媒体整理，升条件P1；F-189选择owner独立 | TMDB/豆瓣映射当前专用字段；未支持Bangumi/AniList隐藏/解释 | 已闭环 |
| W018-A / F-147/F-156传播 | V021/W019、G06/G09/G10 | 双审确认提交中关闭仍发后续POST并迟到onDone；本段直接后果为P2，但F-147整体因PUT/DELETE竞跑为P1，F-156又经G09同ID复用错对象mutation升条件P1 | 单一mutation phase禁关闭/重入，每项与最终回调复核session；W019收口refresh/focus、新选择与ID owner | 已闭环 |
| W018-A / F-206 | M001-J/V021、G01/G09/G10 | 多审确认TV闭合Picker封死当前Web/后端一等支持的自定义target_path，维持P2 | 保留目录建议，仅该字段加自定义输入并复用updateForm/编码 | 已闭环 |
| W018-B/I015 / F-074/F-151/F-158/F-162/F-165/F-185 | V021/C001/C004/W009、G09/G10 | G09后F-151升P1、F-162/F-165升P2，其余维持；旧预览与provenance/滚动/关闭边界闭合 | 复用不可变intent+generation+session、跨intent provenance及原生滚动/关闭 | 已闭环 |
| W019 / F-201 | M001-H/V022、G09/G10 | 双审确认模型已解码errmsg但行/详情无读取；当前Web tooltip与后端字段明确为失败原因 | 详情随F-185展示trim后非空原因，覆盖空白/普通/超长文本 | 已闭环 |
| W019 / F-202 | M001-H/V022-A、I009/G09 | 双审确认非null稀疏FileItem合法输入可拖垮整页；缺/null整个嵌套对象本身可解 | 仅历史响应DTO字段级宽容，覆盖完整+{}+仅path+null并保留相邻好行 | 已闭环；修复完成（`670cf86`），验证及独立复审通过 |
| W019 / F-203 | A001-F/V022-B、G09 | G09两票确认HTTP deletedest丢弃目标删除Bool并仍删历史/返回成功，破坏性结果分裂升P1 | 后端检查目标删除失败并保留历史；TV不做单端存在性兜底 | 已闭环 |
| W019 / F-204 | V022-C/I009、G04/G09 | 双审确认外部删除/add_force新ID不会权威对账，旧行永久保留；Web激活完整刷新 | TV每次进入Tab完成权威refresh并失效旧poll；同ID放大另经I009升条件P1 | 已闭环；TV修复已提交（`81d42fb`） |
| W019/I009 / F-204同ID放大 | V022-C/I009/A001-F、G04/G09 | 默认SQLite且无autoincrement；add_force删最大ID再建可复用ID，TV保留旧A，按旧A确认DELETE/AI/manual会让后端重查并改变新B文件 | TV在首个mutation前全量比较完整指纹并绑定来源session，异常时整批拒绝/刷新；后端长期方向仍是永不复用ID或行版本原子校验 | 已闭环；TV修复已提交（`81d42fb`），479/479与独立复审通过 |
| W019 / F-205 | W018-A/V022、G09/G10 | 双审确认onDone先refresh后dismiss，onDismiss在refresh中丢唯一restore且完成不补 | I009主审与G10不同代理确认P2；refresh完成复用restore并覆盖单/批、目标保留/消失，真实焦点落点留运行 | 已闭环 |
| I009 / session、query与错误传播 | F-027/F-072/F-033/CHK-005 | 多请求循环切manage会话可跨服继续mutation；旧poll可污染新query，Paginator错误显示空/静默stale | I009双票维持F-027 P1、F-072/F-033 P2；后续G04将F-072升P1，F-033仍P2。复用session snapshot/list generation与现有handle(error:) | 已闭环 |
| I009 / 轮询位移与生命周期 | F-071/F-153/F-154/F-155/F-204/F-232 | 搜索retain、101项扫描、外部替换与同秒非全序成立；删除/插入游标独立反例经G09推翻 | F-071/F-155/F-232 P2、F-204历史裁决P1且TV修复已由`81d42fb`提交；F-153/F-154驳回并仅留组合测试 | 已闭环 |
| I009 / AI、整理与文件结果 | F-080/F-098/F-156/F-075/F-203 | accepted≠completed、无终态EOF、动作owner、部分成功与文件副作用结果 | G09后F-098/F-156/F-203 P1，F-080/F-075 P2；复用快照/逐IDreceipt/terminal flag | 已闭环 |
| I009 / F-232稳定排序 | V022-C/W019、G04/G09 | 后端秒级date仅按DESC做offset分页，同秒不同ID可跨页重复/遗漏；TV去重和遇已知早停不能补漏 | review_a001_h提出、verify_a001_h第三裁确认P2；四分页分支追加id DESC并补25条同秒跨页fixture，不建cursor框架 | 已闭环 |
| W020-C / F-207 | V002/V023/I016、G06/G10 | 双审确认手动重登成功只写反馈，不重跑System根信息加载或更新backendVersion，局部旧快照直到View重建 | 不建平行状态；获胜session重登后复用loadSystemInfo或消费权威settings/currentUser | 已闭环 |
| W020-C / F-216→F-107/F-089 | W002/C002/V023/R001、G06/G08/G10 | G06已将F-089转确认P2；刷新后错误跨根交接仍完整归F-107，F-216驳回重复编号 | App级一次性错误owner交接，登录分类分流 | 已闭环 |
| W020-B / F-208 | I016、G10 | 双审确认push/pop固定0.42s横移824pt、根页Back固定0.24s滚动，均未读取Reduce Motion；本段无手势滑动 | 原生环境值切换即时/淡化路径，清理等待跟随实际时长 | 已闭环 |
| W020-D / F-209 | V003/V011/I016、G01/G05 | 三代理确认“全部”空sentinel被后端解释为IndexerSites默认子集；正确候选域也不能修复nil三态；G05单方提议P1不足以推翻既有多票，保留确认P2 | 显式发送全部active IDs；若仍发nil则改名“后端默认”；覆盖default/all/specific与SSE/fallback | 已闭环 |
| W020-D / F-210 | A001-I/V002/V003/I016、G01/G05/G06 | 三代理确认TV以/site/rss作为搜索站点域且不滤inactive；修正sentinel也不能补非RSS active或删inactive，独立P2 | 提供search权限可读的active搜索站点合同；只在正确权威域成功后归一化 | 已闭环 |
| W020-E / F-211→F-126/F-081 | M001-K/S005/V015/I016、G05/G06 | 第三裁决：同ID当前B执行符合合同；失败仍展示A归四态，成功响应缺所选ID静默不过滤归F-081 | 设置页标stale/error；执行端区分未选择与已选不可用，驳回复合编号 | 已闭环 |
| W020-E / F-215→F-081 | M001-K/S005/C006/I016、G05/G10 | 第三裁决：重复/空白ID污染列表/focus/profile/first执行且后端通用入口可达，完整归F-081并促其升P2；合法长名只留运行风险 | 输入边界校验规范唯一identity；长名差异后缀做tvOS布局/辅助验证 | 已闭环 |
| I015 / F-212 | V021/A001-F、G01/G09 | G09两票确认path-only选择可把用户明确目录改到另一storage并执行mutation，升条件P1；当前Web同样path-only，用户要求仅消除TV独有100ms窗口 | `a6cc428`已让选择同步生成现有path-first tuple；规范(storage,path)增强按用户决定跳过TV单端实现 | 已闭环（按Web对齐处置完成） |
| I015 / F-213 | M001-J/V021/A001-F、G01/G05/G09 | G09两票确认明确电影仍提交并执行隐藏剧集字段，升条件P1；episode_part属公共字段；当前Web共享同一行为 | 用户决定跳过TV单端修复；若未来上下游共同处理，再让唯一intent按最终类型投影并由后端门控Auto | 已闭环（当前Web共享，用户决定跳过TV单端修复） |
| I011 / F-061严重度 | S003/M001-K/C018/W011、G05 | 第三裁确认默认展示稳定覆盖后端优先顺序，任意排序又破坏软过滤置尾承诺 | F-061升P2；默认保留后端顺序，显式排序只在命中/软过滤分区内执行 | 已闭环 |
| I011 / F-175传播 | C010/C018、G05/G07/G10 | 第三裁确认TorrentCard与PersonCard同为raw focusable/onTap主动作且无原生Button/disabled语义 | 并入F-175并升P2；资源下载卡使用原生Button并真机验收辅助功能 | 已闭环 |
| I012 / F-219 | W006/I011、G05/G10 | 第三裁确认两个生产调用者新搜索时先移除旧结果View，完成后以最新载荷新建实例，不存在原位同ID更新 | F-219驳回；仅未来新增原位刷新调用者时重开组件回归 | 已闭环 |
| I012 / F-076/F-036/F-035/F-039/F-103严重度 | V011/W006/I007、G01/G04/G06 | F-076 P1，F-036/F-103 P2；全新G04 clean-room末裁将F-035/F-039收窄后升P2 | 按各owner回溯；aggregate cancel不重写generation | 已闭环 |
| I005 / F-220 | V004/W007/W008、G03 | 双审确认season只依赖详情响应，却被可选识别和详情内图片等待联合屏障延迟启动，并稳定延长有订阅权限电视剧全屏Loading | 并入扩展后的F-115并升P2；F-220驳回重复编号，受控gate验证season提前启动 | 已闭环 |
| I005 / F-221 | V004/V005/W007/W008、G03 | 双审以custom partial→full补Douban/Bangumi/AniList无TMDB闭合finished不落定与缓存重进不自愈 | G03窄第三裁限于Header TMDB按钮并确认P2；跳过识别也落terminal并复用现有按需识别 | 已闭环 |
| I005 / 既有finding严重度 | V004/W007/W008、G02/G03/G06 | I005当时只确认F-115新增稳定P2后果；F-117取消窗口归F-019/F-020放大，F-184/F-180当时未升级 | F-115升P2；后续I013以新增整链证据将F-184合法正数合集升条件P1、F-180升P2，非I005单票结论 | 已闭环 |
| G08 / F-222→F-107 | V001/C002/R001/R002/W002/W003、F-027/F-107/CHK-005 | 三方确认App级manager无session owner，旧账号异步错误与已有banner可跨logout/切服/A→B；第三裁认定与根转换共享owner | F-222驳回重复编号并入F-107/CHK-005；历史P1主触发后续已修复，剩余晚到show降P2且用户决定跳过 | 已闭环 |
| G08 / F-223 | V001/C002/W002/W003、F-107/H-012 | 两票确认同session失败后快速成功没有scope dismiss，旧失败仍覆盖成功；A失败/B失败/A成功要求只清自身 | F-223确认P2；轻量ID/scope，成功保持静默 | 已闭环 |
| G08 / F-107/F-108/F-121/F-159/H-012 | V001/C002/C016/W015/R001/R002、F-049/F-148 | F-107主触发已修复、剩余P2由用户决定跳过；F-148 P1，F-049/F-121 P2；F-108未验证P3，F-159运行P3。G02末裁覆盖F-121旧P3 | H-012只传播；各运行边界保留明确验收 | 已闭环 |
| I003 / F-027/F-130/CHK-005 | A001-B/C/E/J、V023/R001/W002/W020、G06 | G06两票再次确认旧relogin撤销logout与A mutation跨服重放，维持F-027/F-130/CHK-005 P1 | API层冻结epoch/server/token/permission并限制同owner重放 | 已闭环 |
| I003 / F-065/F-083/F-080/F-106 | A001-A/B/E/H/J、V004/V020/W011/W017、CHK-007/010/017 | F-083/F-080/F-106 P2；G02末裁把三缓存F-065按跨会话错误payload升级P1；malformed SSE当前会fallback | 各owner回溯闭环；不建平行缓存/响应框架 | 已闭环 |
| I007 / F-224 | V011-B/W006-D、F-137/F-141、G01 | 双审确认明确查询年份下SubscribeShare仍以标题完全匹配进入统一最佳排序，错误年份可反超正确媒体 | 并入F-137评分不变量传播，F-141只管查询词法；F-224驳回重复编号 | 已闭环 |
| I007 / F-225 | V011-C/D/W006-B、F-033/F-144、G01/G04 | 双审确认可选分享任务最慢时核心媒体/合集/人物虽已发布仍被全页loading遮住；错误/部分成功另归F-033 | 确认P2；核心完成先揭示，分享generation安全地两阶段补发 | 已闭环 |
| I007 / 既有传播 | V011/W006/I003/I012、G01/G04/G05/G06 | source合同、子Paginator session发布、扫描上限、SSE终止、规则fail-open、旧fallback错误及长度评分均由独立复核确认命中既有编号；F-219继续驳回 | 各归既有owner，I007不再保留开放去重项 | 已闭环 |
| G07 / F-143/F-227/F-036/F-034人物identity | M001/V011/V013/W006/W008/W009、G03/G04 | 三方确认内嵌导演缺source稳定route失败、稀疏详情覆盖seed而credits沿旧owner、人物raw_id跨source误合并/批内漏去重；连续无新增扫描另归F-034 | F-143/F-036/F-227确认P2；F-034维持P2，演员当前credits带source，优先上游补source且TV旧版仅可用父媒体兼容 | 已闭环 |
| G07 / F-189/CHK-019人物source筛选 | A001/V011/W006、G01/G09 | 三方确认通用source合同错配；后续G09以错误媒体mutation链将F-189升条件P1 | 当前先过滤/移除无效能力；若保留须先建后端统一source合同，CHK-019不新增 | 已闭环 |
| G07 / F-045/F-050/F-051/F-055/F-056/F-178/F-228 | B005/B006/S006/V012/W006/W008/W009 | 三方确认Hero、Douban roles、两类头像与详情备用名各自投影边界；job canonical正常，mergeCrew非空existing当前不可达 | F-045/F-050/F-051/F-055维持P3，F-056驳回重复并入F-050，F-228独立确认P3；复用displayRole/imageURLs/alternateNames | 已闭环 |
| G07 / F-226 | M001/Bangumi/C010/W006/W009 | 三方确认当前后端正式返回Bangumi career、Web显示，TV不解码/合并且卡片无出口；relation无确认caller | F-226确认P2且仅限credits卡片；解码并合并career，复用现有displayRole，relation不扩展 | 已闭环 |
| G07 / F-175及反证 | C010/I011/W006/W008/W009 | 三方确认PersonCard/TorrentCard raw focusable/onTap同根，但静态不能证明遥控完全不可用；Search最佳结果不存在先截后去重 | F-175维持P2并拒绝P1；原生Button/disabled复用现有视觉，最佳结果旧说法驳回，VoiceOver/Select留运行验证 | 已闭环 |
| G10 / Sheet焦点与样式全局链 | C003/C004/C005/C017及全部业务Sheet、W013/W015/W018/W019/W020 | ActionRow、SheetStyles/TextField/Picker、MultiSelection与业务Sheet的焦点、控制语义、Exit、嵌套呈现、状态反馈、长文本及VoiceOver须全局收敛 | 双审闭合；F-229确认P3、F-230确认P2，既往多业务Sheet调用链污染永久披露 | 已闭环 |
| G10 / mutation与presentation映射 | W013/W015/W017/W018/W019、F-092/F-108/F-120/F-147/F-148/F-193/F-205 | mutation、Cancel、single-flight、嵌套Sheet及焦点恢复须复用既有operation/session owner | F-120后续降P2且用户决定跳过；G06将F-193升条件P1，F-148/F-027 P1、F-205 P2，F-108未验证P3 | 已闭环 |
| G10 / query/style/focus/text/permission映射 | C003/C004/C005/C017、W013/W018/W020、F-076/F-126/F-130/F-158/F-160/F-162…F-165/F-168/F-185/F-229/F-230 | query generation、disabled/empty、初始焦点、原生控制、长文本和权限快照须全局一致 | 后续G09将F-161/F-162/F-165升P2；F-158/F-160/F-168/F-230 P2，F-229 P3 | 已闭环 |
| I013 / F-184及既有详情传播 | W008-A…E、V012、G02/G03/G04/G07 | 合集永久Loading、临时订阅、Header身份、权限、焦点、错误、cache揭示、卡片与长文本须去重 | F-184条件P1、F-180/F-116 P2、F-181未验证条件P2、F-033根P2/详情局部P3；F-116后续升级来源为G03，程序限制披露不变 | 已闭环 |
| I013 / F-231 | W008-E、DetailNavigationSession、TMDB跳转调用链 | 页面弹出后未取消的TMDB异步任务仍可追加path或写alert，route owner可能已失效 | 双审确认P2；pop、双激活、跨session归同一action generation/owner，复用局部Task/cancel/session guard，不建导航框架 | 已闭环 |
| I008 / F-007 | M001/V004/V012/V018、G02/G03 | Header builder丢主来源身份且启发式TMDB优先完整详情权威值；Sheet出现即创建暂停订阅，错误/缺失身份可进入mutation | 双审确认P1；`bb07772` 已完整传递主来源身份、保留legacy并改为full TMDB优先，回归测试与独立复审通过 | 已闭环；修复完成 `bb07772` |
| I008 / F-047/F-048/F-049 | B007/V012/W008、CHK-006 | 警告读取失败仍开放普通确认；执行会重查target但不冻结/比对scope，DELETE false/throw又无反馈 | F-047保持跨季条件P1、Header局部证据P2；F-048/F-049维持P2，不可变intent与现有通知出口闭合 | 已闭环 |
| I008 / F-130/F-182/F-118 | V004/V012/W007/W008、CHK-005 | 加载中撤权可令season与辅助内容均不落ready；旧false gate无限不发现远端新增；ownerless pin根因与push/LRU运行链分离 | I008时F-130/F-182均P2；后续G04将跨页面F-130升P1，G03确认F-118根因P2；端到端生命周期与真机可见影响仍未验证 | 已闭环 |
| W020-D / F-214→F-109 | V010/W005/I016、G01/G06 | G06将F-109升P2；app-global与当前per-user权威错位仍由F-109完整承载，F-214重复驳回 | 服务端当前用户配置为权威，本地fallback按canonical profile隔离 | 已闭环 |
| W020-G / F-217 | W020-B/F/I016、G06/G10 | 三代理确认pop离场窗口的条件Exit结构分支会重建并重启推荐task；StateObject保留且只读GET，第三裁独立P3 | 恒定保留同一onExitCommand modifier类型，禁用传nil或action guard；root不安装no-op | 已闭环 |
| W020-H / F-085 | M001-K/S005/V015、G05 | 双审确认已成功解码规则的空白/非法正则、size单值、seeders区间等预览与执行相反；当前Web正常可达且可清空核心搜索 | 先统一官方语法，再让单一canonical解析结果驱动预览与matcher；F-085升P2，F-081不加权 | 已闭环 |
| R001 / F-028 | B004/V023、G06/G08 | 当前Web同样不做前台/路由权限热刷新，TV token校验/自动重登与正式session发布后的UI收敛已完整 | 保持现有静默token校验；管理员运行中改权限由重登/重启恢复 | 已闭环；已驳回（用户决定跳过） |
| R001 / F-218 | V023/R002、G06/G08 | 三代理确认已存token令初始isLoggedIn=true而准备态false，首个body先具备构造旧权限Tab/Home资格；与F-106 settings出口窗口不可互替 | 准备初值与待恢复token同步；必要settings完成或明确失败策略后统一清门，真机验证首帧/Home task | 已闭环 |
| W011 / F-186 | C017/C018-C、G05/G10 | TV从数值倍率重算促销并把30/70/25/75压成50、4X压成2x，筛选值与卡片、当前Web/后端`volume_factor`枚举分裂 | 删除重算helper，直接复用已显示的`volume_factor`，以后端完整枚举表驱动验证，不建促销模型 | 已闭环 |
| W011 / F-187 | V015/C001、G05/G10 | 资源业务error、transport失败或成功空均置hasSearched并进入无action空态；同页面再次search被门闩拒绝，只能退出重进 | 复用EmptyDataView action，调用现有cancelSearch重置后再search；分别覆盖三类终态与session隔离 | 已闭环 |
| W012 / F-188 | A001-K/W001、G01/G05/G06/G09 | G09两票确认高级正ID只填当前后端不消费字段，可错媒体下载/整理，升条件P1 | 映射TMDB/豆瓣旧字段；未支持来源隐藏/解释 | 已闭环 |
| W001/W012 / F-189 | W018-A、G01/G05/G09 | 当前后端忽略source且TV不按item.source过滤，异源ID可被解释为所选来源；G09升条件P1 | 客户端按规范化source过滤；长期建立真实后端source合同 | 已闭环 |
| V010/V011-D / F-138 | M001、V009-B/F、W005/W006、I006/I007、G01/G04 | 全 nil 身份 title-only 媒体共享 ID；共享 key 又遗漏 collection_id，合法合集也可碰撞；G01纠偏与G04独立复核确认稳定丢项后果，升P1 | 稳定 title fallback、collection_id 契约、跨页去重与最终 ID 唯一性 | 已闭环 |
| V010 / F-139 | W005、S004、G04/G08 | 推荐首批成功空后 Paginator 进入无错终态，页面再次激活不刷新当前 shelf；G01纠偏与G04独立复核确认稳定不可恢复空态，升P2 | 当前 shelf 成功空的一次性重试、非空/错误/切 shelf 不受扰动 | 已闭环 |
| I006 / F-233 | V009-C/E/F、W004、G05 | 已支持筛选控件运行更新把false/0/空串/null替换回truthy默认 | 默认只在初始化/reset应用，运行值原样保留并验证depends清理 | 已闭环 |
| I006 / F-234 | V009-A/C/E/F、W004、G01/G05 | 动态profile只按prefix/defaults判兼容，filter_ui/options/depends变化仍保留失效旧值 | schema替换时清失效值并让UI与query使用同一版本 | 已闭环 |
| I006 / F-235 | V009-B/F、W004、G01/G04 | Explore动态source和Popular手写key绕过共享MediaIdentifier规范化 | source别名/大小写/空白与同媒体同季身份统一去重 | 已闭环 |
| I006 / F-236 | V009-C/F、W004、G04/G06 | 同path不同source切换保留旧Paginator/items/seenKeys，且上游无path唯一合同；末裁P2 | 用现有source.id+path作为最小owner key并验证插件冲突 | 已闭环 |
| I006 / F-237 | V009-F、W004、G01/G04/G06 | 同session source refresh代码可逆序发布，但当前只有一个生产调度点 | 驳回独立编号；跨session归F-130/CHK-005，未来新增第二调用点再重开 | 已闭环 |
| I006 / F-238 | V009-E/F、W004、G01/G05 | api_path既有query与filter同名时生成重复键 | 三方确认构造但FastAPI/plugin首末值合同缺失，转最终未验证清单 | 已闭环 |
| I010 / F-239 | W006-C/D、V004/I005、G03/G06 | G06两票确认Search行300ms任务无离页/session owner且logout后可迟到注册，维持P2 | 复用PreloadDebouncer，离场取消并在调度/执行双检session epoch | 已闭环 |
| I014 / identity | M001-A/D、W013-B、G02；2026-08-08当前Web/后端复核 | canonical TMDB但raw `tmdb_id=nil`时group helper受限 | 静态限制成立，但Web相同且订阅入口通常经full detail补raw；从F-012主P2机制拆出为用户路径未验证P3边界 | 已闭环 |
| I014 / F-243 | W008-B、W013-A/B、G02/G03 | 前台仅刷新subscription而不刷新availability，旧best_version/full进入临时订阅 | 两票确认独立于F-182的P2状态owner/mutation后果，转G02/G03回溯 | 已闭环 |
| I014 / cache | M001-F、V004/I005、W013-A/B、G03 | 分季三缓存及MediaPreloader缺server/session namespace | API三缓存全归F-065；MediaPreloader有logout clear且无绕过清理生产路径，不归F-065/F-020且当前不成案 | 已闭环 |
| I014 / retry | V018、W013-B、G02/G10 | Retry切换form subtree触发onDisappear cleanup并可能删除prepared临时订阅 | 两票确认完整归F-148，稳定根生命周期与created/owner/session receipt同一修复 | 已闭环 |
| I016 / F-240 | W020-D、Recommend、G01/G05/G06 | 同名不同path货架分开渲染却共享title配置键 | G01第三裁确认P2；稳定owner使用shelf id/path，旧title只作一次迁移 | 已闭环 |
| I016 / F-241 | W020-G/H、G10 | App Info Sheet展示时底层root Menu observer仍启用且允许同时识别 | 两票确认静态前提但tvOS modal Menu投递缺失，转未验证P3 | 已闭环 |
| I016 / F-242 | W020-D/E、G10 | 站点/规则长名单行截断且preview不回显完整名称 | 两票确认视觉P3；推荐截断与VoiceOver扩大说法保留运行边界 | 已闭环 |
| I016 / 等级第三裁 | W020-A/C/D、I004、G01/G05/G06 | G06以当前后端401闭合F-089并取两票共同下界确认P2；F-106/F-240仍P2 | I016受限集成闭环；严格零暴露缺口永久披露 | 已闭环 |
| G01 / F-244 | V011/I007/W006、G01/G06 | 两票确认A→B不发新query时子Paginator items/resource error可早于父最终gate发布；G04第三票确认它与F-130同属会话/权限派生状态未收敛根因 | 并入F-130/CHK-005；F-244作为重复编号驳回 | 已闭环 |
| G01 / 首轮等级与合并 | G01全部开放F/CHK | G06将F-109升P2，G09将F-212升条件P1；G04 clean-room末裁将F-137升P2 | G01全部争议闭合；F-106/F-240/F-200等既有收口不变 | 已闭环 |
| G04 / 主审与独立复核 | G04全部开放F/CHK | 既有错号意见作废；全新clean-room代理逐项闭合F-034/F-035/F-039/F-137/F-142/F-143/F-176/F-236 | 八项均确认P2；F-035/F-039共享owner取消实现但保留独立回归 | 已闭环 |
| G05 / 主审与独立复核 | G05全部开放F/CHK | 错号CHK票作废；八项共同升级既已落账，G09把F-102转未验证P3 | F-133/F-134/F-238继续未验证、F-135 P3；六项CHK边界不变 | 已闭环 |
| G06 / 主审与独立复核 | G06全部开放F/CHK | 两票将F-019/F-062/F-063/F-193升P1，F-030/F-031/F-084/F-109/F-157/F-089升P2 | 后续G02末裁把F-087/F-121升P2；F-244并入F-130，其他既有裁决不变 | 已闭环 |
| G09 / 主审与独立复核 | G09全部开放F/CHK | 两票共同升级17项、驳回F-153/F-154、转F-102未验证并新增F-246 P1 | 全新clean-room第三裁确认F-073 P2与F-246/CHK-020；其余Finding/CHK按交集落账 | 已闭环 |
| G09 / F-246 | A001-F/V022/W019、当前Web/后端 | 普通已认证token可直接GET全局整理历史、路径与文件项；TV与Web v2.15.1客户端manage门禁已对齐，但不能形成服务端授权 | 用户决定按Web对齐跳过TV单端处理；上游后端风险与CHK-020保留 | 已闭环（TV/Web已对齐，用户决定跳过） |
| G02 / 首轮等级与范围 | G02全部开放F/CHK | 原主审/纠偏后由全新clean-room代理从生产链重审；F-014驳回，F-003/F-006/F-126等收窄，F-054/F-065/F-069/F-082/F-086/F-100/F-124/F-127/F-199升P1，F-087/F-121升P2 | G02全部争议闭合；F-120保留全局G09/G10已证P1，rawPayload合同按可表示结构/typed覆盖收窄 | 已闭环 |
| G03 / F-245 | A001-J/W015、CHK-017、G02/G03 | Fork 2xx带ID但success缺失/null时仍被接受并进入GET/编辑 | 三票确认独立F-245 P2；与F-083不同decoder/端点/最小补丁，只共同挂CHK-017 | 已闭环 |
| G03 / 首轮等级与映射 | G03全部开放F/CHK | 两轮纠偏与窄第三裁已排除错号/对象错位；F-097/F-118/F-221、F-245及CHK-006/017最终边界已落账 | G03组闭环；F-173/F-177作为运行未验证保留，不再作为开放队列 | 已闭环 |

原全局上游 `阻塞` 已因找到两个合法当前仓库而关闭；实际部署、远端最新性与运行配置仍须在最终报告按各 F/CHK 收敛为逐项 `未验证`，不得写成已运行确认。

## 7. 工作树漂移记录

| 检查批次 | 检查代理 | HEAD | 除 ReviewPlan/本审计目录外的变化 | 受影响单元 | 处理 |
| --- | --- | --- | --- | --- | --- |
| 启动 | 清单代理 + 计划校验代理 | `4a997919983566ec208e777acf7798a95e2f9e8f` | 无 | 无 | 基线冻结 |
| I001 | integrate_i001 | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | `Models.swift` 哈希稳定，无需重开 |
| A001-E | verify_a001_e | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | API/VM/View 目标哈希前后稳定，无需重开 |
| A001-G | review_a001_g | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 生产与测试范围无修改，无需重开 |
| A001-F | review_a001_f | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 生产与测试范围无修改、暂存区为空，无需重开 |
| A001-E/F-095 | verify_f095 | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 下载 API/VM/View 范围稳定，无需重开 |
| A001-G | verify_a001_g | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 生产与测试范围无修改，无需重开 |
| A001-F | verify_a001_f | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 生产与测试范围无修改，无需重开 |
| A001-H | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标与调用链范围稳定，无需重开 |
| A001-J | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标与调用链范围稳定，无需重开 |
| A001-I | review_a001_i | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标与调用链范围稳定，无需重开 |
| A001-H 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标、调用链与测试证据范围稳定，暂存区为空，无需重开 |
| A001-I 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标、调用链与测试证据范围稳定，无需重开 |
| A001-K | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标文件 hash 前后稳定、暂存区为空，无需重开 |
| A001-J 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 生产/测试源码无差异、暂存区为空，无需重开 |
| S005 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | 目标文件 hash 前后稳定、关联生产源码无差异，无需重开 |
| V001 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | NotificationManager blob 稳定、暂存区为空，无需重开 |
| A001-K 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | APIService/Models 与生产测试范围无差异、暂存区为空，无需重开 |
| V002-A | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel hash 稳定、目标/关联生产源码无差异，无需重开 |
| S005 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | CustomFilterService hash 稳定；并行审计文档漂移已重读，无需重开 |
| V001 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | NotificationManager 与关键生产/测试范围首尾 hash 稳定；审计文档漂移已重读，无需重开 |
| V002-A 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel 与生产/测试 Swift 聚合 hash 首尾稳定；并行审计文档漂移已重读，无需重开 |
| V002-B | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel 与 26 个主证据源码/测试文件 hash 首尾稳定；审计文档漂移已重读，无需重开 |
| V002-C | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel hash 首尾稳定、关联生产文件时间戳未变化；最新 V002 账本已重读，无需重开 |
| V003 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SiteFilterViewModel hash 首尾稳定；协调文档漂移已按最新相关条目重读，无需重开 |
| V002-B 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel、关键源码/测试及 Swift 聚合 hash 首尾稳定；审计文档漂移已重读，无需重开 |
| V002-D | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel、25 个生产/测试证据文件与 index hash 首尾稳定；审计文档漂移已重读，无需重开 |
| V002-C 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel、站点/搜索/详情/API 与测试证据 hash 采样稳定；审计文档漂移已重读，无需重开 |
| V004-A | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaPreloader 全文件与目标 1-299 hash 首尾稳定；规则及相关审计文档漂移已重读，无需重开 |
| V003 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SiteFilterViewModel、14 个核心源码/测试及 index hash 首尾稳定；最新审计条目已重读，无需重开 |
| V002-D 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SystemViewModel 与 API/Action/Home/Menu 关键 hash 首尾稳定；最新 F-113/CHK-005 文档已重读，无需重开 |
| V004-B | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaPreloader 全文件与目标 300-474 hash 首尾稳定；相关审计条目漂移已重读，无需重开 |
| V004-A 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaPreloader、目标 1-299、20 个核心证据文件及 index hash 首尾稳定；审计漂移已重读，无需重开 |
| V004-B 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaPreloader、目标 300-474、核心生产/测试聚合与 index hash 首尾稳定；审计文档稳定，无需重开 |
| V005 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaActionHandler SHA-256 `3bcbfc556320a0614ea597b96e5823e0146302632bb60547da4d68d30c9d26e4` 首尾稳定；生产/index 无修改，审计文档漂移已重读，无需重开 |
| V006 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscriptionHandler SHA-256 `e57a3d589a2bf6df902335aee7e3fb2c8557288b5ab36a4140423af9a454fcb6` 首尾稳定；生产/index 无修改，审计文档漂移已重读，无需重开 |
| V007 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | LoginViewModel 工作树/index blob `e48a19c9ce989672755d816a23623a7b06d39dc8`、SHA-256 `0035d0cef98529a0327aee0212140f96e80a065bca5988e1b91b5510af99d390` 首尾稳定；审计文档漂移已重读，无需重开 |
| V006 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscriptionHandler SHA-256 `e57a3d589a2bf6df902335aee7e3fb2c8557288b5ab36a4140423af9a454fcb6` 首尾稳定；目标/index 无修改，审计文档漂移已重读，无需重开 |
| V008 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | HomeViewModel SHA-256 `5222ac866b7542595d35b7847623be6f8330c8b8809e0f7ab0dd62ff7be411a2` 首尾稳定；目标 worktree/index 无修改，审计文档漂移已重读，无需重开 |
| V007 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | LoginViewModel SHA-256 `0035d0cef98529a0327aee0212140f96e80a065bca5988e1b91b5510af99d390`、blob `e48a19c9ce989672755d816a23623a7b06d39dc8` 首尾稳定；目标/index 无修改，无需重开 |
| V005 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaActionHandler SHA-256 `3bcbfc556320a0614ea597b96e5823e0146302632bb60547da4d68d30c9d26e4`、blob `b20b14745280e7441bd7f0308ff3679657d6296b` 首尾稳定；目标/index 无修改，审计文档漂移已重读，无需重开 |
| V008 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | HomeViewModel SHA-256 `5222ac866b7542595d35b7847623be6f8330c8b8809e0f7ab0dd62ff7be411a2`、blob `5fdf4e4bd4cc1d6e0e89eb779fa87f823f946292` 首尾稳定；目标/index 无修改，审计文档漂移已重读，无需重开 |
| V009-B | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `9ad5e99244960078ecaf56b7d9b53e58b8aa758f224fb372ef6b1b326948b777` 首尾稳定；目标/index 无修改，无需重开 |
| V009-A | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `25d89ee748d812a0f1789d70dbd68079c5f7d4bf8347c25a94cd44bd8fd3d123` 首尾稳定；目标/index 无修改，无需重开 |
| V009-C | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `dc767936974595119fab02b4139b2bb20333ca42284ca651898bf6e0c9c5fc32` 首尾稳定；目标/index 无修改，无需重开 |
| V009-D | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `9a6f9e9d8c2e21dcd1483c489b71573650a206a6063b650286873ee3a337b329` 首尾稳定；目标/index 无修改，无需重开 |
| V009-B 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `9ad5e99244960078ecaf56b7d9b53e58b8aa758f224fb372ef6b1b326948b777` 首尾稳定；目标/index 无修改，无需重开 |
| V009-E | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `411a5d9080d31af643c5355351f5f5dd66371b7bfa277b0948f4bbaf2706c10f` 首尾稳定；目标/index 无修改，无需重开 |
| V009-D 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `9a6f9e9d8c2e21dcd1483c489b71573650a206a6063b650286873ee3a337b329` 首尾稳定；目标/index 无修改，无需重开 |
| V009-A 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `25d89ee748d812a0f1789d70dbd68079c5f7d4bf8347c25a94cd44bd8fd3d123` 首尾稳定；目标/index 无修改，无需重开 |
| V009-E 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `411a5d9080d31af643c5355351f5f5dd66371b7bfa277b0948f4bbaf2706c10f` 首尾稳定；目标/index 无修改，无需重开 |
| V009-C 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `dc767936974595119fab02b4139b2bb20333ca42284ca651898bf6e0c9c5fc32` 首尾稳定；目标/index 无修改，无需重开 |
| V009-F | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标段 `599e944fc283e8b6f1387f56dc86af5e9f59ec968cfbf3fa30619959b40c5509` 首尾稳定；目标/index 无修改，无需重开 |
| V010 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | RecommendViewModel SHA-256 `2c8ada202fd5b9c026bcca198de611a12b3d2cab39cd266bd74f61050efb1d8e`、blob `2f6abba7d4252a0c29e4e19cbac641312be85a0c` 首尾稳定；目标/index 无修改，无需重开 |
| V011-A | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 全文件 SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、目标 1-78 `f7b91e36ad30fe2f509da1f4598974df0622351f36030dffa4b4f4a37d51c971`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V009-F 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ExploreViewModel 全文件 SHA-256 `9975034ad6375c0d408f56a72d8272a0d74f0d60f5e418d5af8f873d840675c0`、目标 754-957 `599e944fc283e8b6f1387f56dc86af5e9f59ec968cfbf3fa30619959b40c5509` 首尾稳定；目标/index 无修改，无需重开 |
| V011-B | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 全文件 SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、目标 79-260 `7729fb25c906d043f5ecae93056e8bbe31ed893d8a730e0012c679c5f223b40d`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V011-C | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 全文件 SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、目标 261-511 `2a4c9394d8719de952e938cd8549d08df9f531d357f8d73fd44f2a071c04ac3d`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V011-A/B 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 全文件 SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、1-78 `f7b91e36ad30fe2f509da1f4598974df0622351f36030dffa4b4f4a37d51c971`、79-260 `7729fb25c906d043f5ecae93056e8bbe31ed893d8a730e0012c679c5f223b40d`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V010 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | RecommendViewModel 267 行，SHA-256 `2c8ada202fd5b9c026bcca198de611a12b3d2cab39cd266bd74f61050efb1d8e`、blob `2f6abba7d4252a0c29e4e19cbac641312be85a0c` 首尾稳定；目标/index 无修改，无需重开 |
| V011-D | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 865 行，SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、512-731 `02ab32a9f6355cfd8a96e407cc11fd4d9b415988026d3cc0cb1708afb5f97316`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V011-C 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 全文件 SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、261-511 `2a4c9394d8719de952e938cd8549d08df9f531d357f8d73fd44f2a071c04ac3d`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V011-E/F | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel 865 行，SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、732-748 `9926f75ed3390798f53d6ca1ee5fa7f709ff0f9ad6f058eb0c0a21eaab8d9e0f`、749-865 `fd5410266cd575264d068cf340e75c086e62fbd213ca2c18a59a50c295f345ce`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V012-A | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaDetailViewModel 全文件 SHA-256 `10390a3c15ac41120522314e62e2be1e79eb96bca8eebd01bed70571162a5aea`、1-255 `dbf4f2d69c9b936cb3aa3f2e564d4303fd06d992a63aa0dc96cc85dcb8245e94`、blob `51ab759edbd91ac12e748bfee69d5d8a3e7f0cce` 首尾稳定；目标/index 无修改，无需重开 |
| V011-D 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、512-731 `02ab32a9f6355cfd8a96e407cc11fd4d9b415988026d3cc0cb1708afb5f97316`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V012-B | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaDetailViewModel 470 行，SHA-256 `10390a3c15ac41120522314e62e2be1e79eb96bca8eebd01bed70571162a5aea`、256-395 `6e132497a362c5d47828dbe98c1bcd445889df52e5df37d76309e3451e3abd98`、blob `51ab759edbd91ac12e748bfee69d5d8a3e7f0cce` 首尾稳定；目标/index 无修改，无需重开 |
| V012-C | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaDetailViewModel SHA-256 `10390a3c15ac41120522314e62e2be1e79eb96bca8eebd01bed70571162a5aea`、396-470 `9320e8fa41925b8b2da49e90f403cbfeb8e6b6b3a540dfb8498d8d0ec68677a3`、blob `51ab759edbd91ac12e748bfee69d5d8a3e7f0cce` 首尾稳定；目标/index 无修改，无需重开 |
| V011-E/F 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、732-748 `9926f75ed3390798f53d6ca1ee5fa7f709ff0f9ad6f058eb0c0a21eaab8d9e0f`、749-865 `fd5410266cd575264d068cf340e75c086e62fbd213ca2c18a59a50c295f345ce`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 首尾稳定；目标/index 无修改，无需重开 |
| V014 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | CollectionDetailViewModel 49 行，SHA-256 `9cb28674c1450491f46e9a7cef57ba73fb7520c7355d51a91e494c4d1049cd04`、blob `66be6f78236506cad58ac9443c436403d36f1c08` 首尾稳定；目标/index 无修改，无需重开 |
| V013 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | PersonDetailViewModel 118 行，SHA-256 `318095cf203c2c8a5f3c46247a8ab5665b19ff2aed923211d27ece868e4f29cc`、blob `be962049022924874c5fe06c22cc59c2ba004c93` 首尾稳定；目标/index 无修改，无需重开 |
| V015 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ResourceResultViewModel 263 行，SHA-256 `7ffb185d7be1411f6875eac368a25c054085a90c33ec4474f4e94d00eed65c44`、blob `4fc66b932f6a6c24c9a694c131d8e0c5d9cbeac3` 首尾稳定；目标 working-tree/index diff 均为空，无需重开 |
| F-142 裁决 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SearchViewModel SHA-256 `f10c1de8ee476916159bf9af4368e878e284136081624dacec4405f46c6573e9`、749-865 `fd5410266cd575264d068cf340e75c086e62fbd213ca2c18a59a50c295f345ce`、blob `f2d747af0f70591a9889f077126a1985f37764f3` 前后稳定；目标 staged/unstaged diff 均为空，无需重开 |
| V016 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | AddDownloadViewModel 133 行，worktree/index SHA-256 `92f88b4001561e689feacc7e9e51508c45c58fc078596d523b527d9e48f00cb1`、blob `e73f4ab371354d89bca59367b59360f49d218480` 前后稳定；目标 staged/unstaged diff 均为空，无需重开 |
| V012-A/C 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaDetailViewModel SHA-256 `10390a3c15ac41120522314e62e2be1e79eb96bca8eebd01bed70571162a5aea`、1-255 `dbf4f2d69c9b936cb3aa3f2e564d4303fd06d992a63aa0dc96cc85dcb8245e94`、396-470 `9320e8fa41925b8b2da49e90f403cbfeb8e6b6b3a540dfb8498d8d0ec68677a3`、blob `51ab759edbd91ac12e748bfee69d5d8a3e7f0cce` 前后稳定；目标 working-tree/index diff均为空，无需重开 |
| V012-B 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaDetailViewModel SHA-256 `10390a3c15ac41120522314e62e2be1e79eb96bca8eebd01bed70571162a5aea`、256-395 `6e132497a362c5d47828dbe98c1bcd445889df52e5df37d76309e3451e3abd98`、blob `51ab759edbd91ac12e748bfee69d5d8a3e7f0cce` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V014 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | CollectionDetailViewModel SHA-256/index `9cb28674c1450491f46e9a7cef57ba73fb7520c7355d51a91e494c4d1049cd04`、blob `66be6f78236506cad58ac9443c436403d36f1c08` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V013 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | PersonDetailViewModel SHA-256 `318095cf203c2c8a5f3c46247a8ab5665b19ff2aed923211d27ece868e4f29cc`、worktree/HEAD blob `be962049022924874c5fe06c22cc59c2ba004c93` 前后稳定；目标 working-tree/index diff均为空，无需重开 |
| V016 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | AddDownloadViewModel 133行，SHA-256 `92f88b4001561e689feacc7e9e51508c45c58fc078596d523b527d9e48f00cb1`、blob `e73f4ab371354d89bca59367b59360f49d218480` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V015 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ResourceResultViewModel 263行，worktree/index SHA-256 `7ffb185d7be1411f6875eac368a25c054085a90c33ec4474f4e94d00eed65c44`、blob `4fc66b932f6a6c24c9a694c131d8e0c5d9cbeac3` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V017 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscribeSeasonViewModel 393行，worktree/index SHA-256 `b2630fa6b1885a151e9ca4bf31720edca6eea723625c5a58c778f1a32dab5bd3`、blob `51685f16ebaf7f102ad890495e00d38323d7b3de` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V018 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscribeSheetViewModel 253行，SHA-256 `5a10c14de09a667585dda62fb0bf4ecfe3bd862216b7dc2b64b6264e4adea2cd`、blob `9336ca8c4ce0bd7f0d6cfae126aa815ba87a6b50` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V019 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | StatusViewModel 34行，SHA-256 `f6309c791f5367771cd53a8364e96ad3a6992321656ec4422d8975a0a76a5114`、HEAD/index/worktree blob `a297385bd4773e68a63f133b0d4003df4db6f9c9` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V020 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | DownloadTaskViewModel 128行，SHA-256 `6060a31af6f7c2798ee464d2b48afacdbb6b6c6f916611f954ca8dbd68474d74`、blob `58824103d9f66aa0c5ed330128bb5ef4a2a18e41` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V017 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscribeSeasonViewModel 393行，SHA-256 `b2630fa6b1885a151e9ca4bf31720edca6eea723625c5a58c778f1a32dab5bd3`、blob `51685f16ebaf7f102ad890495e00d38323d7b3de` 前后稳定；目标及直接生产/测试链 staged/unstaged diff均为空，无需重开 |
| V019 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | StatusViewModel 34行，SHA-256 `f6309c791f5367771cd53a8364e96ad3a6992321656ec4422d8975a0a76a5114`、blob `a297385bd4773e68a63f133b0d4003df4db6f9c9` 前后稳定；目标及StatusView/权限/API/模型/直接测试链 staged/unstaged diff均为空，无需重开 |
| V018 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SubscribeSheetViewModel 253行，SHA-256 `5a10c14de09a667585dda62fb0bf4ecfe3bd862216b7dc2b64b6264e4adea2cd`、blob `9336ca8c4ce0bd7f0d6cfae126aa815ba87a6b50`；SubscribeSheet 395行 SHA-256 `0c80e9cb3816463f9b52484472b54fabb0d670207766d30cba0454b89863789f`；生产目标 staged/unstaged diff均为空，无需重开 |
| V021 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ReorganizeViewModel 427行，SHA-256 `b612d36ff1d26dc20093ce899e6b037a8db63ed8ba2dd8fa057c53d20c53cde6`、worktree/index/HEAD blob `2403a65d66f81b8d2cbe200ca01946be684158c4` 前后稳定；目标 staged/unstaged diff均为空，无需重开 |
| V020 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | DownloadTaskViewModel 128行，SHA-256 `6060a31af6f7c2798ee464d2b48afacdbb6b6c6f916611f954ca8dbd68474d74`、blob `58824103d9f66aa0c5ed330128bb5ef4a2a18e41` 前后稳定；目标及直接生产/测试链 staged/unstaged diff均为空，无需重开 |
| V022-B | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、HEAD blob `449fa3ea`前缀稳定；目标 staged/unstaged diff均为空，无需重开 |
| V022-A | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、worktree/HEAD blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；Paginator/API/Models/View/直接测试生产指纹稳定，无需重开 |
| V021 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ReorganizeViewModel 427行，SHA-256 `b612d36ff1d26dc20093ce899e6b037a8db63ed8ba2dd8fa057c53d20c53cde6`、worktree/index/HEAD blob `2403a65d66f81b8d2cbe200ca01946be684158c4`前后稳定；直接生产/测试 staged/unstaged diff均为空，无需重开 |
| V022-C | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；调用链 staged/unstaged diff均为空，无需重开 |
| V022-D | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、451-551段SHA-256 `57d818a80484eb6a2f2244ddcbc385be7fd1e8ac394284656998e5e5647cb9c3`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定，无需重开 |
| V022-A 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；Paginator/API/Models/View/测试 staged/unstaged diff均为空，无需重开 |
| V022-B 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、202-281段SHA-256 `fb7b8aca56161c04fac29c7775a23031bfb423613a918cb87d383f1b9422cc60`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；直接链diff全空，无需重开 |
| V022-C 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel目标SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；Paginator/API/Models/View/测试链diff全空，无需重开 |
| V022-D 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | TransferHistoryViewModel SHA-256 `7c44d3e58f636597537b2d75056b15aee20948f6325fe5442c711742e484a0c0`、451-551段 `57d818a80484eb6a2f2244ddcbc385be7fd1e8ac394284656998e5e5647cb9c3`、blob `449fa3ea47d6f02bd75f2009a12365fa02147fb5`前后稳定；直接链diff全空，无需重开 |
| C001 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | EmptyDataView 58行，SHA-256 `f00d0118f9594d38330794358c35ae006764f6bb1bb01a45641990572fb2c575`、blob `f8e77994dff6f32f52f95479e60016cc6bc4dcae`前后稳定；5生产文件7调用点及测试链diff全空，无需重开 |
| C001 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | EmptyDataView 58行，SHA-256 `f00d0118f9594d38330794358c35ae006764f6bb1bb01a45641990572fb2c575`、blob `f8e77994dff6f32f52f95479e60016cc6bc4dcae`前后稳定；组件、5调用文件及测试链diff全空，无需重开 |
| C002 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | NotificationComponent SHA-256 `d642dc5e86222979eaca80a57f4359fc292f9ca718d21f7dde80bd0ab06f2ad7`、blob `ea1b5cb3f02a40cad3cfaa932f1422184a7b8b96`；NotificationManager SHA-256 `ee1aeae06e574737ff800e382e8b2cdcfe4f82522afc4aeb1364d5aa2e63e3ad`、blob `0f347963590e72a9345b2eb3ba5d56e8be6f5968`前后稳定，无需重开 |
| C002 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | NotificationComponent 45行、SHA-256 `d642dc5e86222979eaca80a57f4359fc292f9ca718d21f7dde80bd0ab06f2ad7`、blob `ea1b5cb3f02a40cad3cfaa932f1422184a7b8b96`；NotificationManager 64行、SHA-256 `ee1aeae06e574737ff800e382e8b2cdcfe4f82522afc4aeb1364d5aa2e63e3ad`、blob `0f347963590e72a9345b2eb3ba5d56e8be6f5968`前后稳定；5文件6个producer及根呈现/测试链diff全空，无需重开 |
| C003 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ActionRow 322行，SHA-256 `68543cc9fedbbe851c3a2fb6b01184600660b3067a66d2bf4c9474f0b883e189`、blob `a82c257927440db341496d385edfd3fee98bde6c`前后稳定；仅两处直接调用及生产/测试链diff全空，无需重开 |
| C003 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ActionRow 322行、SHA-256 `68543cc9fedbbe851c3a2fb6b01184600660b3067a66d2bf4c9474f0b883e189`、blob `a82c257927440db341496d385edfd3fee98bde6c`；两调用文件/ViewModel/测试链diff全空，无需重开 |
| C004 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetStyles SHA-256 `4bb1cda2cd39aa31c440334b0b0aa761b28c6600bddc7e1e2c4d1e88eb1dfa75`、blob `caf13d7b87c47cc6b6bacbf2458f6b0eeba5b421`前后稳定；目标及九个直接生产/测试链文件diff全空，无需重开 |
| C004 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetStyles 158行、SHA-256 `4bb1cda2cd39aa31c440334b0b0aa761b28c6600bddc7e1e2c4d1e88eb1dfa75`、blob `caf13d7b87c47cc6b6bacbf2458f6b0eeba5b421`前后稳定；7个直接调用文件、VM/呈现入口及测试链diff全空，无需重开 |
| C005 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetTextField 264行，SHA-256 `e836f28ae916fc2cad2a306f688aade02662097b50d56d03090c7dfcba8349ee`、blob `e454d73ad837c75f8220991c06db758f2e64641f`前后稳定；目标与16个生产调用/测试链diff全空，无需重开 |
| C005 复核 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetTextField 264行、SHA-256 `e836f28ae916fc2cad2a306f688aade02662097b50d56d03090c7dfcba8349ee`、blob `e454d73ad837c75f8220991c06db758f2e64641f`前后稳定；16调用、ViewModel/载荷/测试链diff全空，无需重开 |
| C006 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetPicker 87行、SHA-256 `c9264bc35fac88cfafafdd02d25382113cfc094e78f5e0a772d2a5eff233787f`、blob `60fa9c5875ab4e26a9a9fef2dc7e2724e12955ff`前后稳定；15调用及生产/测试链diff全空，无需重开 |
| C006 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetPicker 87行、SHA-256 `c9264bc35fac88cfafafdd02d25382113cfc094e78f5e0a772d2a5eff233787f`、blob `60fa9c5875ab4e26a9a9fef2dc7e2724e12955ff`前后稳定；3调用页、3 VM与4测试文件diff全空，无需重开 |
| C005 F-167补充复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | SheetTextField 264行、SHA-256 `e836f28ae916fc2cad2a306f688aade02662097b50d56d03090c7dfcba8349ee`、blob `e454d73ad837c75f8220991c06db758f2e64641f`前后稳定；四调用文件及测试链diff全空，无需重开 |
| C007 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ShelfPicker 79行、SHA-256 `cff08f6a1a725ec49437946939227b26bd777f2c262904476ffa15796d27f330`、blob `28faf7db043ae2ceff1c11b03cf7de50dc3875ae`前后稳定；唯一Recommend调用及生产/测试链diff全空，无需重开 |
| C007 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ShelfPicker 79行、SHA-256 `cff08f6a1a725ec49437946939227b26bd777f2c262904476ffa15796d27f330`、blob `28faf7db043ae2ceff1c11b03cf7de50dc3875ae`前后稳定；Recommend/VM/Grid/测试链diff全空，无需重开 |
| C008 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MultiSelectionSheet 79行、SHA-256 `c562d075e10b1d822f38a06606f51e1e99ef2fbb5e64dbe588c0c22294543aa9`、blob `84995c9462b6bd5de3210775162af46ed2e4c9e7`前后稳定；5调用及生产/测试链diff全空，无需重开 |
| C008 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MultiSelectionSheet 79行、SHA-256 `c562d075e10b1d822f38a06606f51e1e99ef2fbb5e64dbe588c0c22294543aa9`、blob `84995c9462b6bd5de3210775162af46ed2e4c9e7`前后稳定；5调用、Subscribe/SiteFilter VM、Models/API/测试链diff全空，无需重开 |
| C009-A | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标1-227 SHA-256 `70aace9dec393f2c67dcdccf3c63959501766b15ded5537b8726236032451373`，全文件494行、SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；7调用及生产/测试链diff全空，无需重开 |
| C009-A 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标1-227 SHA-256 `70aace9dec393f2c67dcdccf3c63959501766b15ded5537b8726236032451373`、段blob `bbe9c84e4237c047b023cb5fb47953b9077d9288`，全文件494行、SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；7调用及生产/测试链diff全空，无需重开 |
| C009-B | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标228-425 198行、SHA-256 `10b9abff53cf56cdabb477e992a417421aa42dd120c6a356a1b7f39b0adcb9fa`，全文件494行、SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；7调用及生产/测试链diff全空，无需重开 |
| C009-B 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标228-425 198行、SHA-256 `10b9abff53cf56cdabb477e992a417421aa42dd120c6a356a1b7f39b0adcb9fa`、段blob `e59f58d2fbb01c036cd36b9fe7455c36738860b8`，全文件494行、SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；依赖锁/调用/测试链diff全空，无需重开 |
| C009-C | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标426-494 69行、SHA-256 `f44084bbb0b6818a932259427914b7574702e03d033ab9701d328f8a37d364f7`，全文件494行、SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；生产/测试链diff全空，无需重开 |
| C009-C 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MediaCard目标426-494 69行、SHA-256 `f44084bbb0b6818a932259427914b7574702e03d033ab9701d328f8a37d364f7`、段blob `d0034239375fc07a3fa2b056cb93449ab6d88a23`，全文件SHA-256 `f47a724cb2c294d079b07d06391418e9716835423f5029ba58f5f977659220a6`、blob `faf03507f86a2e48b8d72d5c9075a698d72fe2db`前后稳定；生产/测试链diff全空，无需重开 |
| C010 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | PersonCard 83行、SHA-256 `11b96ada1a8ceccef2ab47246fc37a3435c51a59d0477455c6ef064f8ab32ec3`、blob `3bfa72490e6c22675ef69f51868db0defb58dc7e`前后稳定；3调用、Models/API/Paginator/测试链diff全空，无需重开 |
| C010 复核 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | PersonCard 83行、SHA-256 `11b96ada1a8ceccef2ab47246fc37a3435c51a59d0477455c6ef064f8ab32ec3`、blob `3bfa72490e6c22675ef69f51868db0defb58dc7e`前后稳定；3调用、MediaDetail/Search/Paginator/Kingfisher/测试链diff全空，无需重开 |
| C011 | verify_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MoreCard 80行、SHA-256 `24540e7369f2c1e109c855124d9fac06b881f983ec9ccb1adf43abc5ba4efa21`、blob `a7bd1a6ec47184b31b0467a0b13de9eae8ad5e90`前后稳定；唯一调用/导航/测试链diff全空，无需重开 |
| C011 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | MoreCard 80行、SHA-256 `24540e7369f2c1e109c855124d9fac06b881f983ec9ccb1adf43abc5ba4efa21`、blob `a7bd1a6ec47184b31b0467a0b13de9eae8ad5e90`前后稳定；唯一调用、导航owner、模型/测试链diff全空，无需重开 |
| V023 | review_a001_h | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ContentViewModel 250行，SHA-256 `7323a753527394eab324e93b306c994df2e311265f7cbb972059ffc18fb9c292`、blob `85e20dcbadbfaba98bfc283289ca0e06ddad624d`前后稳定；直接生产/测试链diff全空，无需重开 |
| V023 复核 | review_a001_j | `4a997919983566ec208e777acf7798a95e2f9e8f` | 仅授权审计文档变化 | 无生产单元 | ContentViewModel 250行，SHA-256 `7323a753527394eab324e93b306c994df2e311265f7cbb972059ffc18fb9c292`、blob `85e20dcbadbfaba98bfc283289ca0e06ddad624d`前后稳定；直接生产/测试链diff全空，无需重开 |

## 8. 批次日志

| 批次 | 内容 | 结果 |
| --- | --- | --- |
| S0 | 两个启动代理独立建立清单、工程入口与旧计划差异 | 78 个生产文件逐路径一致；台账已建立 |
| S1 | M001-A、M001-B、M001-C 并行主审 | M001-A/M001-B 已闭环；M001-C 待 F-011 回溯 |
| S2 | B001 主审与独立复核 | 已闭环；F-009/F-010 已确认 P3 |
| S3 | M001-D 主审、F-011 裁决与独立复核 | 已闭环；F-011后经2026-08-08当前上游复核收窄为条件性P2；F-014已驳回、F-015确认P3；F-013当时保持未验证，后经2026-08-08当前Web/后端合同反证驳回 |
| S4 | B002 主审与独立复核 | F-016 驳回、F-017 未验证且用户均决定跳过修复；F-018 确认 P3；F-021 待回溯 |
| S5 | B003 主审与独立复核 | F-019/F-020 已确认 P2；F-026 交 S004 裁决，B003 待回溯 |
| S6 | M001-E 主审、独立复核与 F-032 回溯 | 已闭环；F-021…F-025/F-032 均已确认 |
| S7 | B004 主审与独立复核 | F-027…F-031 已确认；CHK-005 已确认；G02/G06 待回溯 |
| S8 | S004 主审与独立复核 | F-026/F-032/F-033/F-034 已确认 P2，F-035/F-036 已确认 P3；F-039 待回溯 |
| S9 | B005 主审、独立复核与回溯 | F-040/F-041/F-044/F-045 已确认；已闭环 |
| S10 | B006-A 主审与独立复核 | F-037 未验证 P3；F-038 已确认 P3；分段已闭环 |
| S11 | B006-B 主审与独立复核 | F-042 未验证 P3；F-043 已确认 P3；分段已闭环 |
| S12 | B006-C 主审 | F-040/F-041 维持确认，F-044 已独立支持；F-046 进入复核 |
| S13 | B007 主审与独立复核 | F-047…F-049、CHK-006 已确认；F-054 待 Handler/API 回溯 |
| S14 | S006 主审与独立复核 | F-050…F-053 已确认；F-055/F-056 待回溯 |
| S15 | I002 TranslationHelper 文件级集成复核 | 已闭环；无新候选，既有八条发现边界维持 |
| S16 | S001 Logger 主审 | 主审完成，F-060 进入独立复核 |
| S17 | S002 KeychainHelper 主审 | 首个复用代理失败，review_s002_retry 从头主审中 |
| S18 | S003 ParsedSeason 主审 | 主审完成，F-057…F-059 进入独立复核 |
| S19 | S003 ParsedSeason 独立复核 | F-057/F-058/F-059 均确认 P3；S003 已闭环；复核新增 F-061 转 G05 后续单元验证 |
| S20 | S001 Logger 独立复核 | F-060 核心成立但降级为 P3；H-008 修正；S001 已闭环且无新增发现 |
| S21 | S002 KeychainHelper 主审重试 | 从头主审完成；新增 F-062/F-063 候选 P2；支持 F-027/F-031 回溯，转待独立复核 |
| S22 | S002 KeychainHelper 独立复核 | F-062/F-063 均确认 P2并收窄边界；S002 主审/复核完成，转 G06 待回溯 |
| S23 | M001-G 人物与下载请求模型主审 | 新增 F-064 候选 P2；F-055 获独立支持后确认 P3；F-056 继续等待 V012-A |
| S24 | M001-F 订阅模型主审 | 新增 F-065…F-069；F-054 获独立支持后确认 P2；提出 CHK-007/CHK-008 候选 |
| S26 | M001-F 独立复核重试 | F-065/F-066/F-067/F-068 确认，F-069 未验证；CHK-007/CHK-008 确认；单元转待回溯 |
| S27 | M001-G 独立复核重试 | F-064 确认条件性 P2，F-056 确认 P3；无新增发现，M001-G 已闭环 |
| S28 | M001-H 资源/系统/转移模型主审重试 | 新增 F-070/F-071/F-072 候选；补强 F-027 settings 发布链；转待独立复核 |
| S29 | M001-J 重新整理与手动预览模型主审 | 新增 F-073…F-076 候选；支持 F-027 在 G09 的下游传播；转待复核 |
| S30 | M001-H 独立复核 | F-071 确认 P3、F-072 确认 P2、F-070 转未验证 P3；settings 发布纳入 F-027；单元转待回溯 |
| S31 | M001-I SubscribeShare 主审 | 新增 F-077/F-078 候选；当时扩展 F-002/F-011/F-027 分享链并提出 CHK-009；2026-08-08窄裁决已将分享对象从F-011排除 |
| S32 | M001-J 独立复核 | F-074/F-075 确认 P2、F-076 确认 P3、F-073 转未验证 P3；单元转待回溯 |
| S33 | M001-I 独立复核 | F-077 确认并升条件性 P2，F-078 确认 P3，新增 F-079 未验证 P2；CHK-009 确认；单元转待回溯 |
| S35 | M001-K SSE/过滤规则主审重试 | 新增 F-080/F-081 候选；F-061 获独立支持后确认 P3；转待复核 |
| S36 | A001-A API 基础段主审 | 新增 F-082(P2)/F-083(P3)/F-084(P3) 候选；支持既有会话、缓存、解码和日志发现 |
| S37 | A001-A 独立复核 | F-082 确认 P2，F-083/F-084 确认 P3并收窄边界；无新增发现，单元转待回溯 |
| S38 | M001-K 独立复核 | F-080/F-081 确认；新增 F-085 候选 P3交 S005；Models A-K 分段主审/复核全部完成 |
| S39 | A001-B API 会话段主审 | 新增 F-086 候选 P3；强支持既有会话、持久化、图片和分季缓存发现；转待复核 |
| S41 | I001 Models.swift 整文件集成复核 | 55 个顶层声明完整覆盖，无新增代码发现；H-001/H-003/H-004 闭环，Models 文件转待跨组回溯 |
| S42 | A001-B 独立复核 | F-086 确认 P3；新增 F-087(P3)/F-088(P2)；CHK-005/007 维持并补强措辞，单元转待回溯 |
| S44 | A001-C 主审重试 | F-087/F-088 获独立支持后确认；新增 F-089 候选 P3；转待独立复核 |
| S45 | A001-D 系统/搜索/发现端点主审 | 新增 F-090 条件性 P3；支持 settings session、响应、图片和身份既有发现；转待复核 |
| S46 | A001-C 独立复核 | F-087/F-088 维持确认；F-089 转未验证 P3；单元转 G06/I003 待回溯 |
| S47 | A001-D 独立复核 | F-090 确认条件性 P3并扩展遮蔽后续正值边界；F-087 扩展 2xx selector；单元转待回溯 |
| S48 | A001-E 下载器及下载任务动作端点主审 | 新增 F-091(P2)、F-092/F-093/F-094(P3) 候选；支持 F-027/F-083/F-086/F-087，转独立复核 |
| S49 | A001-E 独立复核 | F-091(P2)、F-092/F-093/F-094(P3) 均确认；新增 F-095 条件性 P2候选，转窄范围独立复核；单元转待回溯 |
| S50 | A001-G 媒体服务器端点主审 | 新增 F-096(P2)/F-097(P3) 候选；确认既有媒体服务器、会话、响应与日志发现传播，转独立复核 |
| S51 | A001-F 转移历史、手动整理与存储端点主审 | 新增 F-098/F-099 条件性 P3候选；F-073 保持未验证，其余会话、转移、整理、响应与日志发现获支持，转独立复核 |
| S52 | F-095 窄范围独立复核 | 确认条件性 P2；与 F-092 根因独立，同会话客户端代际不并入 CHK-005，A001-E 维持待回溯 |
| S53 | A001-G 独立复核 | F-096(P2)/F-097(P3) 均确认；无新增发现，转下游与 I003 待回溯 |
| S54 | A001-F 独立复核 | F-098/F-099 条件性 P3 均确认，分别独立于 F-075/F-090；无新增发现，转下游与 I003 待回溯 |
| S55 | A001-J 季、订阅 CRUD、查找与缓存主审 | 新增 F-100(P2) 候选与 CHK-010 候选；补充身份、取消、缓存、刷新、会话与 schema 发现传播证据，转待独立复核 |
| S56 | A001-H SSE 与资源搜索主审 | 新增 F-101/F-102/F-103(P3) 候选与 CHK-011 候选；支持既有 SSE、资源、会话、响应、图片与过滤发现传播，转待独立复核 |
| S57 | A001-I 详情、人物、站点及规则配置主审 | 新增 F-104(条件性 P2) 候选；支持既有会话、后台解码、人物头像、规则、响应、图片与 ID 发现传播，转独立复核 |
| S58 | A001-H 独立复核 | F-101/F-102/F-103(P3) 均确认，F-102 收窄为路径/查询/片段及既有 percent-escape 触发；CHK-011 确认为修订并合并既有 missingSites 条目，单元转待回溯 |
| S59 | A001-I 独立复核 | F-104 确认为条件性 P2；相邻范围仅并入 A001-D Douban recommendations，similar 与数字型 TMDB/Bangumi 分支不计已确认传播；无新增 finding，单元转待回溯 |
| S60 | A001-K 添加下载与图片 URL 主审 | 新增 F-105/F-106(P3) 候选；确认添加下载是 F-011/F-027/F-087 出口并传播 F-084/F-086，支持 CHK-003/CHK-005，转待独立复核 |
| S61 | A001-J 独立复核 | F-100 确认为条件性 P2，CHK-010 确认；补 F-104 groupId 传播并将 F-006/F-066 收窄为非正 ID 边界，无新增 finding，单元转待回溯 |
| S62 | S005 CustomFilterService 主审 | 无新增 finding；支持 F-060/F-061/F-081，并作为不同代理将 F-085 修订跨端边界后确认 P3；单元自身转待独立复核 |
| S63 | V001 NotificationManager 主审 | 新增 F-107/F-108(P3) 候选；确认现有生产通知全为错误且成功静默，并补 F-049/F-091/F-093 的通知去重/呈现边界，转待独立复核 |
| S64 | A001-K 独立复核 | F-105/F-106(P3) 均确认；收窄真实生产 wrapper、冷启动/同会话热刷新与切服未验证边界，补强 CHK-003/CHK-005，单元转待回溯 |
| S65 | V002-A 系统与详情偏好主审 | 新增 F-109(P3) 候选，根因跨入 V002-B；其余为 F-008/F-027…F-029/F-031/F-062/F-063/F-086 与 CHK-005 传播，转待独立复核 |
| S66 | S005 独立复核 | F-060/F-061/F-081/F-085 均维持，F-017 未验证；新增下游 F-110(P3) 候选交 C018/I011，S005 转待回溯 |
| S67 | V001 独立复核 | F-107 确认 P3；F-108 收敛为未验证、条件性 P3，等待 tvOS Sheet 层级/计时运行证据；H-012 确认，V001 转待回溯 |
| S68 | V002-A 独立复核 | F-109 确认 P3，四类 profile 偏好与旧键迁移边界闭合；新增 token-only `default` 身份 F-111(P3) 候选交 V002-B/D/I004，V002-A 转待回溯 |
| S69 | V002-B 过滤选择、登录与 Keychain 主审 | 无新增确定 finding；完整支持 F-109、既有会话/规则传播与一次性迁移边界，token-only `default` 倾向并入 F-109，交不同代理复核裁决；转复核中 |
| S70 | V002-C 系统、站点与规则加载主审 | 新增 F-112(P3) 候选（代理提议号与既有 F-111 冲突，协调时顺延）；确认权限双检查正确并传播既有会话/规则/响应发现，转待独立复核 |
| S71 | V003 SiteFilterViewModel 主审 | 新增 F-114(P3) 候选；确认父 VM 未转发固定子 SiteFilter 的 objectWillChange，F-112 仅作两条请求链传播，转待独立复核 |
| S72 | V002-B 独立复核 | F-109 维持确认 P3；F-111 依编码前身份投影与独立修复/验收确认为单独 P3，非 F-109/F-063 合并项；无其他新增，单元转待回溯 |
| S73 | V002-D 静态读取、归一化与持久化主审 | 新增 F-113(条件性 P2) 候选；不同代理支持 F-111/F-112 确认 P3，并补 CHK-005 的 profile-scoped 本地异步结果边界；转待独立复核 |
| S75 | V002-C 独立复核 | F-112 确认 P3；位置补齐自赋值/实例 normalizer，失败语义收窄为首次伪空与后续无 stale/error 标记；无新增 finding，单元转待回溯 |
| S76 | V004-A MediaPreloadTask 主审 | 新增 F-115/F-117(P3) 候选，F-116 收敛为未验证条件性 P3；确认 F-100 双写生产触发并传播身份/会话/图片发现，转待独立复核 |
| S77 | V003 独立复核 | F-114 确认 P3，并收窄为父 UI 文案新鲜度、不宣称请求参数陈旧；F-112 两条请求传播维持，单元转待回溯 |
| S78 | V002-D 独立复核 | F-113 确认为条件性 P2；持久偏好污染为确定 P3，旧 action 在 B 会话继续导航/请求时达 P2；无新增 finding，单元转待回溯 |
| S80 | V004-B 全局缓存、Pin、刷新与 LRU 主审 | F-118 收敛为未验证条件性 P3；新增 F-119(P3) 候选，并传播缓存/会话/订阅乱序及 V004-A 发现，转待独立复核 |
| S81 | V004-A 独立复核 | F-115/F-117 确认 P3，F-116 维持未验证；F-117 收窄实际取消入口并补取消后不得发布 ready，单元转待回溯 |
| S82 | V004-B 独立复核 | F-119 确认 P3，F-118 维持未验证并补 ghost pin/all-pinned/软上限边界；无新增 finding，单元转待回溯 |
| S83 | V006 SubscriptionHandler 主审 | 新增 F-120/F-121(P3)、F-124(条件性 P2) 候选；确认 F-008/F-015/F-047/F-054/F-077/F-119 传播，F-079 仍未验证，转独立复核 |
| S84 | V005 MediaActionHandler 主审 | 新增 F-122(P3)、F-123(条件性 P2) 候选；确认 F-090/F-103/F-113/F-115 传播，并补强 CHK-005 的高层 action session 起点，转待独立复核 |
| S85 | V007 LoginViewModel 主审 | 无新增 finding；确认登录入口传播 F-027/F-062/F-063/F-086…F-088/F-107/F-113，F-089 维持未验证，F-029 无本入口新增触发，F-123 仅作切换入口传播，转待独立复核 |
| S86 | V006 SubscriptionHandler 独立复核 | F-120/F-121 确认 P3，F-124 确认条件性 P2；收窄 F-120 不构成错删、修正 F-121 与 F-048 的区分，既有传播维持，单元转待回溯 |
| S87 | V008 HomeViewModel 主审 | 新增 F-125…F-128(P3) 候选；确认 11 项既有 finding 传播并补 F-027/F-028/CHK-005 会话证据，目标版本只使用本地 v2.15.1 tag 静态参考，转待独立复核 |
| S88 | V007 LoginViewModel 独立复核 | 确认无新增 finding；旧自动登录 A→logout→手动登录 B→A 迟到 200 补强 F-027，CHK-005 确认 login acquisition owner/单调 epoch/A→B→A；单元转待回溯 |
| S89 | V005 MediaActionHandler 独立复核 | F-122 确认 P3并收窄为最终 error/cancel 误报，F-123 确认条件性 P2且独立于 F-027/F-113；F-090/F-103/F-113/F-115 传播维持，CHK-005 高层 action 起点补强确认，单元转待回溯 |
| S90 | V008 HomeViewModel 独立复核 | F-125…F-128 均确认 P3；F-126 收窄为配置/订阅 outcome 状态、F-127 修正 reset 字段语义、F-128 要求异步失败出口；既有传播与版本特定 tag 边界维持，单元转待回溯 |
| S91 | V009-B 内容包装与媒体类型主审 | 本段无新增正确性 finding，ExploreContent 为零使用清理项；新增跨段 F-129(条件性 P3) 候选交 V009-E/F，确认 F-077/F-078/F-082/F-103 在 Explore 传播，转待独立复核 |
| S92 | V009-A 来源类型与插件过滤解析器主审 | 新增 F-133/F-134/F-135(条件性 P3) 候选；动态来源 `+` 编码并入 F-088，确认来源/session/权限/分享/响应传播，转待独立复核 |
| S93 | V009-C ViewModel 状态与初始化主审 | 新增 F-130(条件性 P2) 候选；确认新权限已发布但来源/旧 Paginator 不收敛的生产链，并传播 F-027/F-028/F-033/F-035/F-082/F-086，转待独立复核 |
| S94 | V009-D 各来源筛选字典主审 | 新增 F-131(条件性 P3)、F-132(P3) 候选；21 组筛选集合的键/值/默认/顺序完整性通过，无既有 finding 新传播，转待独立复核 |
| S95 | V009-B 内容包装与媒体类型独立复核 | 确认本段无新增、ExploreContent 为死代码；F-129 确认条件性 P3且独立于 F-036，F-077/F-078/F-082/F-103 传播维持，单元转待回溯 |
| S96 | V009-E 派生筛选、路径与查询构建主审 | 新增 F-136(条件性 P3) 候选；确认 F-129/F-131/F-132 根因传播、支持 F-134，并扩展 F-088 字面 `+` query 链，转独立复核 |
| S97 | V009-D 各来源筛选字典独立复核 | F-131 确认条件性 P3、F-132 确认 P3；独立复算 21 组集合其余完整性通过，无新增传播，单元转待回溯 |
| S98 | V009-A 来源/插件解析独立复核 | F-133/F-134/F-135 机制与条件性链成立，但公开 fixture 未触发，三项维持候选待部署/I006；F-088 仅条件扩展，既有传播边界收窄，单元转待回溯 |
| S99 | V009-E 派生筛选、路径与查询构建独立复核 | F-129/F-131/F-132 维持确认；F-134 机制独立成立但无部署 fixture，F-136 只确认版本差异且缺 TV 产品意图，二者维持条件性候选；单元转待回溯 |
| S100 | V009-C ViewModel 状态与初始化独立复核 | F-130 确认条件性 P2并收窄为 discovery 保留、subscribe 单独变化路径；严格 deny 仅降低新数据影响，旧数据/请求/鉴权副作用维持，单元转待回溯 |
| S101 | V009-F 分页、加载、来源刷新与重置主审 | 无新编号；确认 F-129/F-130、补 F-132 合法共有筛选保留验收，并传播会话/分页/分享/响应/query 发现；F-133…F-136 维持候选，转待独立复核 |
| S102 | V010 RecommendViewModel 主审 | 新增 F-138/F-139(条件性 P3) 候选，分别为 title-only 身份碰撞丢记录与成功空 shelf 无重试；既有分页/session/身份/图片/动作发现完成传播，转待独立复核 |
| S103 | V011-A 搜索声明与评分主审 | 新增 F-137(条件性 P3) 候选：长标题罚分可令不匹配项反超并挤出 top-12；枚举/wrapper 身份其余通过，权限翻转/focus 跨段点转 V011-C/I007，单元待独立复核 |
| S104 | V011-B 最佳结果计算主审 | 新增 F-140/F-141(条件性 P3) 候选，分别为尾随空白评分分裂与四位数字片名误作年份；独立确认 F-137、补强 F-138，排序/去重其余边界通过，转待独立复核 |
| S105 | V009-F 分页、加载、来源刷新与重置独立复核 | 本段无新编号；F-129/F-130 维持确认、F-132 共有 genre/category/sort 同根扩展成立；F-133…F-136 因部署 fixture/产品意图缺失转未验证，单元转待回溯 |
| S106 | V011-C 搜索编排、SSE、权限与代际主审 | 无新编号；F-039 由独立生产证据确认 P3，权限热切换并入 F-130/CHK-005，资源旧结果/过期错误并入 F-076，并补强会话、生命周期、SSE 与错误消息既有发现，转待独立复核 |
| S107 | V011-A/B 搜索声明、评分与最佳结果独立复核 | 两段均完整闭合；F-137、F-140、F-141 确认 P3，F-138 获 Search 独立支持但仍等 V010 总体裁决；声明身份、有限排序/去重/top-12 其余通过，转待回溯 |
| S108 | V010 RecommendViewModel 独立复核 | F-138/F-139 均确认条件性 P3；F-138 限全结构 ID 为 nil且稳定非空 title 的共享身份 fallback，F-139 限 retained 同 shelf 成功空终态的激活边沿刷新；无新编号，单元转待回溯 |
| S109 | V011-D Paginator 构造、重置与订阅映射主审 | 无新编号；F-138 获三类 Search processor及 collection_id 漏入共享 key 证据，F-036 补最终 Person.id 可变 seen set边界；会话/错误/取消/分享/图片传播闭合，转待独立复核 |
| S110 | V011-C 搜索编排、SSE、权限与代际独立复核 | 无新编号；独立确认 F-039 P3、F-130/CHK-005 Search 权限热切换同根扩展与 F-076 fallback 双反例，SSE/生命周期/会话传播维持；focus 具体运行表现留未验证，单元转待回溯 |
| S111 | V011-E/F 自定义过滤与 SharedMediaFetcher 主审 | 两段均无新编号；E 将规则 fail-open/坏配置归 F-081/F-085并闭合 profile/session传播，F 直接确认 F-034/F-039及共享 actor、错误、身份、会话边界；分别转待独立复核 |
| S112 | V012-A 详情、分页、背景与预加载主审 | 无新编号；F-100 补 normal/force与force/force入口，F-130 补权限热变首屏/分季卡住，F-138 补错误 preload task灌详情，F-139补 retained详情成功空；F-116/F-118 维持未验证，转待独立复核 |
| S113 | V011-D Paginator 构造、重置与订阅映射独立复核 | 无新编号；F-036 最终 Person.id 可变 seen 边界完全确认，F-138 title-only核心维持确认、collection_id遗漏机制成立但生产输入因上游缺失留未验证；其余分页/权限/分享传播维持，单元转待回溯 |
| S114 | V012-B 订阅状态与取消主审 | 无新编号；取消意图/范围/session/失败/alias/busy与状态乱序分别并入 F-047/F-048/F-027/F-049/F-119/F-120/F-100，身份/正ID边界并入 F-006/F-007/F-068/F-090；F-008/F-054 未复现，转待独立复核 |
| S115 | V012-C 取消确认与目标解析主审 | 无新编号；生产仅电影 Header 进入而 warning 只统计电视剧，两个测试绕过生产入口，强补 F-047；准备失败/取消仍开放、确认后重查并未冻结模式/范围/session强补 F-048/CHK-006；Bangumi exact-ID 为正确对照，转待独立复核 |
| S116 | V011-E/F 自定义过滤与 SharedMediaFetcher 独立复核 | E 无新编号并转待回溯；F 维持 F-034/F-039等裁决，新增 F-142(条件性 P2)候选：完成task handle未及时退休可令另一waiter重复await、返回非终止空批，待第三代理独立裁决 |
| S117 | V014 CollectionDetailViewModel 主审 | 无新编号；F-033/F-035/F-027/CHK-005直接传播，F-139补retained合集成功空，F-138补合集碰撞、NavigationPath与inert preload alias条件链；part携父collection_id误路由因payload缺失留未编号未验证，转待独立复核 |
| S118 | V013 PersonDetailViewModel 主审 | 新增 F-143(P3)候选：人物route identity未准入/冻结，纯name进入死页且详情/credits身份可分裂；新增F-144(P3)候选：所谓并行首载实际串行；既有人物分页/图片/session/错误传播闭合，转待独立复核 |
| S119 | F-142 第三代理裁决、V015/V016 主审并行派发 | review_a001_h 独立裁决 F-142 actor重入/handle退休与 F-034/F-039独立性；review_a001_j 主审 V015；verify_a001_h 主审 V016；均只读且禁止派生、构建、真实后端与 Git 写操作 |
| S120 | V015 ResourceResultViewModel 主审、V012-A/C 复核派发 | V015 无新编号并转待独立复核；资源 SSE/过滤/状态/session/路由证据并入既有 F-022/F-032/F-060/F-061/F-076/F-080/F-081/F-082/F-085…F-088/F-101/F-103/F-109/F-111/F-112/F-113/F-123/F-130 与 CHK-005/011；review_a001_j 随后独立复核 V012-A/C |
| S121 | F-142 第三代理裁决 | review_a001_h 独立确认条件性 P2：共享 task 完成前已推进0→2，但 TV waiter第二轮重放尚未退休handle使2→2并提前返回非终止空批；页1/2各4电影、页3八电视剧反例成立，与F-034/F-039独立，V011-F转待回溯 |
| S122 | V012-B 订阅状态与取消独立复核派发 | review_a001_h 从生产/测试独立复核状态刷新、取消intent/owner/count/scope/session、失败、alias、busy与身份/正ID边界；主审为verify_a001_h，满足不同代理约束 |
| S123 | V016 AddDownloadViewModel 主审、V014复核派发 | V016 新增F-145(P3)候选：下载器选中后不能恢复初始省略状态；其余并入既有session/busy/原形/正ID/旧结果/错误/权限条目并转待复核。verify_a001_h 随后独立复核 V014 |
| S124 | V012-A/C 独立复核、V013复核派发 | A/C均无新编号并转待回溯；A确认F-100/F-130/F-139及F-138 task/season/lifecycle alias，驳回过宽wrong fullDetail注入并转未验证；C确认F-047/F-048/CHK-006并补AniList fallback漏计。review_a001_j随后独立复核V013 |
| S125 | V012-B 独立复核、V016复核派发 | V012-B无新编号，独立确认latest-wins、取消intent/session、失败反馈、身份/正ID、alias与busy既有根因并转待回溯；review_a001_h随后独立复核V016并裁决F-145 |
| S126 | V014 独立复核、V015复核派发 | V014无新编号并转待回溯；确认F-027/F-033/F-035/F-082、F-138 identity/inert-task与F-139成功空，收窄SwiftUI旧StateObject/wrong-fullDetail/part父ID为未验证。verify_a001_h随后独立复核V015 |
| S127 | V013/V016 独立复核、V017/V018主审派发 | V013确认F-143条件性P3与F-144 P3并转待回溯；V016确认F-145 P3并转待回溯。review_a001_h主审V017，review_a001_j主审V018，均只读且不得派生 |
| S128 | V015 独立复核、V019主审派发 | V015无新编号并转待回溯；既有SSE terminal/framing、严格解码、torrent-only、过滤、旧结果、session/权限与路由链闭合，补偿重复ID只补CHK-011未验证合并验收。verify_a001_h随后主审V019 |
| S129 | V017主审、V020主审派发 | V017新增F-146条件性P2候选：剧集组A/B乱序返回可形成Picker/季列表/入库状态/payload混合目标；其余并入既有季号、订阅事件、raw、session、取消、cache、ID与响应条目并转待复核。review_a001_h随后主审V020 |
| S130 | V018主审、V017独立复核派发 | V018新增F-147/F-148两个条件性P2候选：保存与取消/关闭竞跑，以及加载分支丢失唯一回滚钩子；其余并入既有身份、通知、session、失败、cache、ID、响应与busy条目。review_a001_j随后独立复核V017/F-146 |
| S131 | V019/V020主审、V018复核与V021主审派发 | V019新增F-149(P3)候选并转待复核；V020无新编号且F-091…F-095等闭合后转待复核。verify_a001_h独立复核V018，review_a001_h主审V021 |
| S132 | V017独立复核、V019独立复核派发 | V017确认F-146条件性P2：同session、冷cache且A/B均成功仍可形成Picker=B/季列表=A/availability与payload=B；转W013/G02待回溯。review_a001_j随后独立复核V019/F-149及manage-only空态候选 |
| S133 | V019独立复核、V020独立复核派发 | V019确认F-149(P3)：固定await顺序既破坏整组原子又丢失后项成功；新增F-150(P3)：manage-only合法使用状态页下半部时，上半部三张superuser-only卡被稳定误报“暂无”。转W016/G06/G09待回溯；review_a001_j随后独立复核V020 |
| S134 | V018独立复核、V022-A主审派发 | V018确认F-147/F-148条件性P2；修订F-147为durable `isSaved`本身正确但取消/关闭未受`isSaving`约束；F-148新增同session配置失败→Retry触发DELETE→跳过重建→展示已删除ID主反例。转W014/G02/G10待回溯；verify_a001_h随后主审V022-A |
| S135 | V021主审、V022-B主审派发 | V021新增F-151(P3)候选：合法路径可在未转义字符串投影中碰撞，预览/summary少项而prepared forms仍逐ID提交；其余归既有或未验证并转待复核。review_a001_h随后主审V022-B |
| S136 | V020独立复核、V021独立复核派发 | V020无新编号并转W017/G05/G06/G08待回溯；F-091…F-095及F-024/F-027/F-060/F-082/F-083/CHK-005重新闭合，F-033/F-035/F-120不适用。review_a001_j随后独立复核V021/F-151 |
| S137 | V022-B主审、V022-C主审派发 | V022-B新增F-152(P3)批删确认目标因实时items变化静默少发、F-153(P3)删除与在途loadMore错位永久漏边界记录候选；其余既有传播/不适用闭合并转待复核。review_a001_h随后主审V022-C |
| S138 | V022-A主审、V022-D主审派发 | V022-A无新编号并转待复核；F-071/F-072/F-033/F-035/F-036/F-060/F-082/F-144等获分页/搜索/storage/owner生产链，坏单行/total/duplicate-only维持未验证。verify_a001_h随后主审V022-D |
| S139 | V021独立复核、V022-A独立复核派发 | V021确认F-151(P3)：未转义三字段投影使预览Sheet少项/summary少计，而主Sheet仍按全部log ID提交；转W017/G09/G10待回溯。review_a001_j随后独立复核V022-A |
| S140 | V022-C主审、V023主审派发 | V022-C新增F-154(P3)插入余数跨loadMore重复累计跳页、F-155(P3)第6页已请求却被循环上限丢弃候选；F-153及既有轮询/owner传播闭合并转待复核。review_a001_h随后主审V023 |
| S141 | V022-D主审、V022-B独立复核派发 | V022-D新增F-156(P3)旧AI动作收尾清除运行中新选择候选；F-070维持未验证，F-098/F-102及terminal/session/error传播闭合并转待复核。verify_a001_h随后独立复核V022-B/F-152/F-153 |
| S142 | V022-A独立复核、V022-C独立复核派发 | V022-A无新编号并转G04/G09待回溯；F-071/F-072/F-033/F-035/F-036/F-060/F-082/F-144/CHK-005重新闭合，坏单行/total/duplicate-only维持未验证。review_a001_j随后独立复核V022-C/F-154/F-155 |
| S143 | V022-B独立复核、C001主审派发 | V022-B确认F-152/F-153(P3)并转W018/I009/G09待回溯；批删确认快照与删除/page2移位游标错位反例均独立闭合。verify_a001_h随后主审C001 |
| S144 | V022-C独立复核、V022-D独立复核派发 | V022-C确认F-154/F-155(P3)并转W018/I009/G04/G09待回溯；两条确定页序均无需并发/session/重复ID。review_a001_j随后独立复核V022-D/F-156 |
| S145 | V023主审、C002主审派发 | V023新增F-157(P3)settings失败/取消占用版本检查key且恢复成功不收敛候选；既有根会话/权限传播闭合、首帧权限窗口维持运行未验证并转待复核。review_a001_h随后主审C002 |
| S146 | V022-D独立复核、V023独立复核派发 | V022-D确认F-156(P3)并转W018/I009/G09待回溯；全量受理A、SSE中选择B、A收尾refresh清B链独立闭合。review_a001_j随后独立复核V023/F-157 |
| S147 | C001主审、C003主审派发 | C001新增F-158条件性P3候选：5个生产文件7处无action调用均生成透明可聚焦无动作节点；既有空态传播闭合并转待复核。verify_a001_h随后主审C003 |
| S148 | C002主审、C004主审派发 | C002新增F-159(P3)五秒全局错误toast无主动可访问性播报候选；既有通知边界闭合、旧计时关闭新通知竞态驳回并转待复核。review_a001_h随后主审C004 |
| S149 | V023独立复核、C001独立复核派发 | V023确认F-157(P3)并转W001/G06待回溯；失败/取消占用key、前台固定false及同key成功被guard吞的状态链独立闭合。review_a001_j随后独立复核C001/F-158 |
| S150 | C003主审、C005主审派发 | C003新增F-160/F-161两个未验证条件性P3；空Button/raw手势与opacity隐藏action的静态机制成立，实际Select/长按/focus/VoiceOver影响留运行验证；F-156传播确认。verify_a001_h随后主审C005 |
| S151 | C001独立复核、C002独立复核派发 | C001确认F-158条件性P3并转G05及调用页待回溯；5文件7调用计数、透明节点及传播边界独立闭合，真实落焦/VoiceOver频率留运行验证。review_a001_j随后独立复核C002/F-159 |
| S152 | C004主审、C003独立复核派发 | C004新增F-162确定机制P3候选及F-163/F-164/F-165三个条件/可达性P3候选；F-120/F-147传播闭合、F-156不适用。review_a001_h随后独立复核C003/F-160/F-161 |
| S153 | C002独立复核、C004独立复核派发 | C002确认F-159(P3)并转G08及调用页待回溯；5文件6个show、同文案事件、原生announcement与F-107/F-108边界独立闭合，旧计时关闭新通知竞态驳回。review_a001_j随后独立复核C004/F-162…F-165 |
| S154 | C005主审、C006主审派发 | C005新增F-166未验证条件性P3：旧系统UIViewRepresentable未转发isEnabled且强制canBecomeFocused，禁用指定集数是否仍可编辑/入payload待运行裁决；其余并入F-074/F-076/F-147/F-120。verify_a001_h随后主审C006 |
| S155 | C003独立复核、C005独立复核派发 | C003维持F-160/F-161为未验证条件性P3；空Button/raw手势及透明action门禁静态成立，顶层全宽Button/即时reveal等反证要求运行裁决；F-156传播确认。review_a001_h随后独立复核C005/F-166 |
| S156 | C004独立复核、C007主审派发 | C004确认F-162/F-165(P3)，F-163/F-164维持未验证条件性P3；长反馈截断与内容内退出可发现性闭合，旧系统disabled外观/Fork样式症状留运行裁决。review_a001_j随后主审C007 |
| S157 | C005独立复核、C008主审派发 | C005驳回F-166：唯一disabled在现有两个Reorganize历史入口上恒false，载荷链仅是未来条件；另新增F-167(P3)托管根UIView transform候选待不同代理。review_a001_h随后主审C008 |
| S158 | C006主审、C005补充复核派发 | C006新增F-168条件性P3候选：自建Picker详情丢title且当前项无selected语义/默认焦点；F-163/F-165/F-145/F-135/F-074/F-147传播闭合。verify_a001_h随后补充独立裁决C005/F-167 |
| S159 | C007主审、C006独立复核派发 | C007新增F-169(P3)候选：ShelfChip选择态只控制视觉overlay且未暴露isSelected语义；生产仅Recommend一处，F-033/F-139传播闭合。review_a001_j随后独立复核C006/F-168 |
| S160 | C005/F-167补充裁决、C007独立复核派发 | F-167收敛为未验证P3：两次根transform写入违反UIViewRepresentable托管几何契约且16个调用focus可达，但无可见故障证据；F-166维持驳回。verify_a001_h随后独立复核C007/F-169 |
| S161 | C007独立复核、C009-A主审派发 | C007确认F-169(P3)：私有isSelected只做视觉overlay，Button默认语义不会推断持久选择；焦点重定向只降低频率。F-033/F-139传播闭合。verify_a001_h随后主审C009-A |
| S162 | C006独立复核、C008独立复核派发 | C006确认F-168(P3)：所有详情丢title与结构化selected语义；季100从首项起焦/VoiceOver checkmark播报仍留运行未验证。review_a001_j随后独立复核C008/F-170 |
| S163 | C008主审、C009-B主审派发 | C008新增F-170条件性P3候选：选项域变化后已选旧站点/规则组不可见、不可移除且继续保存；F-112/F-114/F-130传播闭合，F-163/F-165不适用。review_a001_h随后主审C009-B |
| S164 | C009-A主审、C009-C主审派发 | C009-A新增F-171(P3)候选：四类徽章元数据全部进入Canvas且无可访问性替代；F-019/F-020/F-026/F-084/F-105/F-106传播闭合，跨段占位/身份移交B/C。verify_a001_h随后主审C009-C |
| S165 | C008独立复核、C009-A独立复核派发 | C008确认F-170(P3)：旧/无权站点规则组选项脱域后不可见、不可移除且继续PUT；保留未知值反证要求只提供主动清域外值。review_a001_j随后独立复核C009-A/F-171 |
| S166 | C009-B主审、C010主审派发 | C009-B新增F-172(P3)未知/nil类型缺图误用film候选、F-173未验证性能P3候选；整卡交互语义并入F-171，图片/身份传播闭合。review_a001_h随后主审C010 |
| S167 | C009-A独立复核、C009-B独立复核派发 | C009-A确认F-171(P3)：Canvas五类徽章字段无逐元素语义且7调用无替代；标题/页面上下文只降低严重度，整卡owner由B闭合。review_a001_j随后独立复核C009-B/F-172/F-173 |
| S168 | C009-C主审、C011主审派发 | C009-C新增F-174(P3)候选：无owner全局sourceFrame被非详情动作写入后，可由另一无来源详情Loading消费；影响限错误飞入动画。其余并入F-105/F-106/F-123/F-138/F-171。verify_a001_h随后主审C011 |
| S169 | C009-B独立复核、C009-C独立复核派发 | C009-B确认F-172(P3)，F-173维持未验证性能P3并收窄为processed-cache冷缺失/原图重处理路径；整卡语义维持F-171传播。review_a001_j随后独立复核C009-C/F-174 |
| S170 | C010主审、C012主审派发 | C010新增F-175/F-176(P3)与F-177未验证性能P3候选；人物卡语义、详情三行失焦翻页及人物图冷处理分别闭合，既有人物/图片传播完成。review_a001_h随后主审C012 |
| S171 | C011主审、C010独立复核派发 | C011无新编号；raw控制并入F-175、重复图片处理并入F-173、非法季号焦点冲突传播F-003，其余分页/导航边界通过。verify_a001_h随后独立复核C010/F-175…F-177 |
| S172 | C009-C独立复核、C011独立复核派发 | C009-C确认F-174(P3)：全仓单写/读/清全局frame无owner，A编辑→B无源详情冷Loading跨栈错误飞入闭合；首选删除手工frame且保留loadingPosterURL。review_a001_j随后独立复核C011 |
| S173 | C010独立复核、C013主审派发 | C010确认F-175/F-176(P3)，F-177维持未验证性能P3；人物卡控制语义、详情三行失焦翻页与Kingfisher冷处理边界独立闭合。verify_a001_h随后主审C013 |
| S174 | C011独立复核、C012独立复核派发 | C011无新编号并转待回溯；F-175/F-173/F-003传播及10/11季/导航字段边界独立闭合。review_a001_j随后独立复核C012/F-178与最佳结果全链 |
| S175 | C012双审、C013独立复核与C014主审派发 | C012确认F-178条件性P3：评分备用名与展示名投影分裂；F-076/F-172/F-174/F-177传播闭合，固定高度仅留运行盲点。review_a001_j随后独立复核C013，review_a001_h主审C014 |
| S176 | C013主审、C015主审派发 | C013主审无新编号；ID-only Equatable在现有四owner缺同ID原位更新链，旧闭包又受Paginator当前状态二次拦截，暂留组件契约风险；verify_a001_h随后主审C015 |
| S177 | C015主审、C016主审派发 | C015主审无新编号；ContentView唯一根presenter闭合，F-090/F-122/F-123/CHK-005传播成立，overlay底层focus只留运行盲点；verify_a001_h随后主审C016 |
| S178 | C014主审、C015独立复核派发 | C014主审无新编号；8生产入口和订阅/TMDB/资源/身份/session/转场既有finding传播闭合，即时删除语义并入F-124/F-047/CHK-006。review_a001_h随后独立复核C015 |
| S179 | C013独立复核、C014独立复核派发 | C013无新编号并转待回溯；ID-only Equatable与旧items闭包在四个append/first-wins owner中无原位替换，Paginator当前数组门槛兜底，既有分页/图片/身份/可访问性/转场传播闭合。review_a001_j随后独立复核C014 |
| S180 | C016主审、C017主审派发 | C016主审无新编号；6个Handler/presenter、8入口与订阅/Fork/缓存/通知/Sheet既有finding传播闭合，F-048/F-049本路径有反证。verify_a001_h随后主审C017 |
| S181 | C015独立复核、C016独立复核派发 | C015无新编号并转待回溯；唯一根presenter、4入口、F-090/F-122/F-123/CHK-005及重叠识别owner链独立闭合，overlay focus/accessibility仅留运行盲点。review_a001_h随后独立复核C016 |
| S182 | C014独立复核、C018-A主审派发 | C014无新编号并转待回溯；8入口与既有菜单/订阅/TMDB/资源/身份/session/转场传播独立闭合，取消动作词/destructive补入F-124/CHK-006，无Fork presenter页只留payload契约未验证。review_a001_j随后主审C018-A |
| S183 | C018-A主审、C018-B主审派发 | C018-A主审无新编号；F-022/F-032/F-057/F-058/F-059/F-061/F-110/F-158传播闭合，onAppear首帧与同ID原位变化仅留盲点。review_a001_j随后主审C018-B |
| S184 | C016独立复核、C018-A独立复核派发 | C016无新编号并转待回溯；6个Handler/presenter、8入口与订阅/Fork/缓存/通知/Sheet传播独立闭合，F-048不适用直取消，F-049仅不适用Handler而仍传播至Sheet回滚。review_a001_h随后独立复核C018-A |
| S185 | C017主审、C018-C主审派发 | C017保留未编号C017-N1条件性P3候选：可选展示字符串未统一规范空白；促销badge撤出并留跨字段契约盲点。既有资源解码/卡片/解析/控制语义传播闭合。verify_a001_h随后主审C018-C |
| S186 | C018-B主审、C017独立复核派发 | C018-B主审无新编号；F-110的default+asc合法组合与固定降序反例闭合，F-061根仍在A段，相等项/nil/混合日期只留合同盲点。review_a001_j随后独立复核C017/C017-N1 |
| S187 | C018-A独立复核、C018-B独立复核派发 | C018-A无新编号并转待回溯；F-022/F-032/F-057/F-058/F-059/F-061/F-110/F-158传播独立闭合，onAppear首帧与同ID变化维持盲点。review_a001_h随后独立复核C018-B |
| S188 | C017独立复核、F-179登记 | C017-N1经不同代理确认并登记F-179条件性P3：资源卡/筛选未统一规范可选展示字符串空白；标题/描述fallback、pubdate分隔符与多标签反例闭合，促销badge仍仅留契约盲点。C017转待回溯 |
| S189 | C018-B独立复核重试 | review_a001_h 首轮在最终报告前遇远端compact stream断连，未采纳未闭合内容；同一只读代理从头重做C018-B独立复核 |
| S190 | C018-C主审、独立复核派发 | C018-C主审无新编号；F-110/F-057…F-059/F-179/F-168/F-170传播闭合，F-061根仍在A段，F-163/F-165有反证。review_a001_j随后独立复核C018-C |
| S191 | W001主审派发 | verify_a001_h完成C018-C主审后转主审W001 ManualMediaSearchSheet，重点闭合F-076/F-099/F-060/F-157/F-159/F-178与搜索/选择/Sheet全链 |
| S192 | C018-C独立复核、W002主审派发 | C018-C无新编号并转待回溯；F-110/F-057…F-059/F-179/F-168/F-170传播独立闭合，F-061根在A段，F-163/F-165有反证。review_a001_j随后主审W002 LoginView |
| S193 | C018-B争议裁决 | 第三代理按当前Swift 6.4 SDK、项目SWIFT_VERSION=6.0、Apple文档与SE-0372确认stable保证自Swift 5.8适用；CI未锁精确Xcode小版本但不影响该保证。主审撤回旧版记忆，C018-B无新编号并转待回溯 |
| S194 | W002主审、W001独立复核派发 | W002主审无新编号；登录URL/form/会话/凭据/通知既有finding传播闭合。review_a001_j随后独立复核W001，但首轮在最终报告前stream断连，未采纳未闭合内容 |
| S195 | W002独立复核派发 | review_a001_h从头独立复核W002 LoginView，重点裁决URL/form、登录attempt/session、凭据、通知与no-access/401/403边界 |
| S196 | W001主审完成 | W001主审无新编号；F-076/F-099/F-178/F-172/F-158/F-165及未验证F-177传播闭合，AddDownload media_in分工只留上游契约边界；review_a001_j重试独立复核中 |
| S197 | W002独立复核、W003/W004主审派发 | W002无新编号并转待回溯；URL/form、session、Keychain、通知与no-access/401/403边界独立闭合。review_a001_h随后主审W003，verify_a001_h主审W004 |
| S198 | W001独立复核、W005主审派发 | W001无新编号并转待回溯；F-076/F-099/F-178/F-172/F-158/F-165及未验证F-177传播独立闭合，AddDownload media_in分工维持契约边界。review_a001_j随后主审W005 |
| S199 | W003主审、W006-A主审派发 | W003主审无新编号；Home数据/订阅/媒体库/TMDB/资源/session/通知/卡片既有finding传播闭合，F-012/F-017/F-118维持未验证，F-158不适用。review_a001_h随后主审W006-A |
| S200 | W004主审、W003独立复核派发 | W004主审无新编号；Explore来源/权限/身份/Fork/分页/图片既有finding传播闭合，F-133…F-136未验证，F-039/F-158不适用。verify_a001_h随后独立复核W003 |
| S201 | W005主审、W004独立复核派发 | W005主审无新编号；推荐货架/空态/身份/分页/订阅/卡片既有finding传播闭合，缺Fork presenter仅留payload契约未验证。review_a001_j随后独立复核W004 |
| S202 | W003独立复核重试 | verify_a001_h 首轮在最终报告前遇远端compact stream断连，未采纳未闭合内容；同一现有只读代理从头重做W003独立复核 |
| S203 | W004独立复核 | W004无新编号并转待回溯；Explore来源/权限/身份/Fork/分页/图片既有finding传播独立闭合，F-133…F-136未验证，F-039/F-158不适用 |
| S204 | W006-A主审、W006-B主审派发 | W006-A主审无新编号；Search根页权限/query/来源/Fork/共享搜索既有传播闭合，键盘提交按显式双模式按钮契约不立项，来源Sheet并入F-168。review_a001_h随后主审W006-B |
| S205 | W006-A独立复核派发 | review_a001_j从头独立复核Search根页/来源Sheet、权限/query/Fork/共享搜索传播及键盘提交双模式按钮契约 |
| S206 | W006-A独立复核 | W006-A无新编号并转待回溯；Search根页权限/query/来源/Fork/共享搜索既有传播独立闭合，键盘提交按显式双模式按钮契约不立项，来源Sheet同根补强F-168且F-169不适用 |
| S207 | W003第二次独立复核重试 | verify_a001_h 第二次仍在最终报告前遇远端compact stream断连，未采纳任何未闭合内容；同一现有只读代理第三次从头重做W003独立复核 |
| S208 | W006-C主审派发 | review_a001_j从头只读主审SearchView媒体/人物行的身份、展示、导航、focus/accessibility及既有finding传播 |
| S209 | W003第三次独立复核断连 | verify_a001_h 第三次仍在最终报告前遇远端compact stream断连，未采纳任何未闭合内容；停止原地重试，等待将W003改派给与主审不同的另一现有只读代理 |
| S210 | W005独立复核派发 | verify_a001_h停止W003原地重试后，改从零独立复核Recommend页货架/空态/身份/分页/订阅/Fork/卡片传播及payload可达边界 |
| S211 | W006-B主审 | W006-B无新编号并转待独立复核；聚合结果错误/空批/分页/权限session/query代际/身份去重/卡片与转场既有finding传播闭合，F-158仅相邻机制，F-139/F-176不适用 |
| S212 | W006-D主审派发 | review_a001_h从头只读主审SearchView最佳结果卡的身份、展示、导航、focus/accessibility、sourceFrame及既有finding传播 |
| S213 | W005独立复核断连 | verify_a001_h在Recommend最终报告前再次遇远端compact stream断连，未采纳任何未闭合内容；停止复用该失败线程，等待改派给与主审不同的另一现有只读代理 |
| S214 | W006-C主审 | W006-C无新编号并转待独立复核；media/person行的分页、身份、会话、图片、订阅动作、人物展示与无障碍既有finding传播闭合，F-064维持未验证，F-079无新增证据，F-158/F-176不适用 |
| S215 | W006-B独立复核派发 | review_a001_j从头独立复核SearchView聚合结果段三类结果/空态/loading/error、分页/focus、身份/最佳结果/navigation及权限/session/query代际传播 |
| S216 | W006-D主审 | W006-D无新编号并转待独立复核；最佳结果卡身份/展示/导航/sourceFrame与既有finding传播闭合，F-064/F-177维持未验证，F-171/F-175不适用，双FocusState/VoiceOver保留运行盲点 |
| S217 | W006-C独立复核派发 | review_a001_h从头独立复核SearchView media/person行的分页、身份、会话、图片预加载、人物展示、订阅动作、navigation及focus/accessibility传播 |
| S218 | W006-B独立复核 | W006-B无新编号并转待回溯；聚合结果错误/旧best与子Paginator混显、权限session/query代际、身份/分享/人物既有finding传播独立闭合，F-064维持未验证，F-139/F-158不适用 |
| S219 | W006-C独立复核 | W006-C无新编号并转待回溯；media/person行的分页会话、媒体/人物/分享身份、菜单订阅、人物展示导航、卡片可访问性与图片链既有finding传播独立闭合，F-158/F-176不适用 |
| S220 | W006-D独立复核派发 | review_a001_j从头独立复核SearchView最佳结果卡的身份、展示、图片类型、分享/人物导航、focus/accessibility、sourceFrame与预加载传播 |
| S221 | W005独立复核改派 | review_a001_h从头独立复核Recommend页货架/空态、身份、分页、订阅动作、Fork presenter/payload边界、卡片图片及focus/accessibility传播；失败线程输出保持作废 |
| S222 | W006-D独立复核 | W006-D无新编号并转待回溯；最佳结果卡排名、身份、展示、类型图片、分享/人物导航、会话预加载、sourceFrame与菜单既有finding传播独立闭合，双FocusState/VoiceOver/性能维持未验证 |
| S223 | W003独立复核改派 | review_a001_j接替失败线程，从头独立复核Home数据/订阅/媒体库/TMDB/资源/session/通知/卡片传播及F-012/F-017/F-118/F-158边界；前三次失败输出保持作废 |
| S224 | W005独立复核 | W005无新编号并转待回溯；推荐货架/空态、身份、分页恢复、生命周期session、订阅动作、卡片图片与可访问性既有finding传播独立闭合；Fork presenter/合集route因生产输入契约缺失维持未验证 |
| S225 | W007主审派发 | review_a001_h从头只读主审MediaDetailContainer详情状态/导航、loading/error/retry、预加载fallback、背景/sourceFrame、session权限及focus/accessibility传播 |
| S226 | W003独立复核 | W003无新编号；Home订阅/媒体库/TMDB资源/session通知/卡片既有传播独立闭合，F-012/F-017/F-118维持未验证，F-158不适用；当前全文件486行覆盖原范围，前三次失败输出保持作废 |
| S227 | W003遗漏项补裁决 | review_a001_j独立补确认F-023最近媒体单项title解码失败经Home发布空数组清卡、F-109媒体服务器选择key跨profile传播，W003转待回溯 |
| S228 | W007独立复核派发 | review_a001_j不参考主审中间候选，从头独立复核MediaDetailContainer详情状态、loading/error/retry、预加载fallback、sourceFrame、session权限及focus/accessibility传播 |
| S229 | W007主审 | W007建议一个条件性P3候选：三次详情失败后容器把失败计为ready，静默揭开partial详情且无错误文案/页内重试；既有详情有效性、pin/cache、session权限、图片与sourceFrame传播闭合，运行/输入边界维持未验证，待独立复核 |
| S230 | W008-A主审派发 | review_a001_h从头只读主审MediaDetailView状态初始化/权限session、首屏gate、task/onDisappear、背景focus/navigation与预加载传播 |
| S231 | W008-A主审 | W008-A建议一个条件性P3候选：内容页切换只监听Hero FocusState，Hero先false、Content后true时可能永不置showContentPage；静态顺序依赖成立但tvOS可见复现未验证。既有状态/权限session/生命周期/预加载finding传播闭合，待独立复核 |
| S232 | W008-B主审派发 | review_a001_h从头只读主审MediaDetailView订阅刷新、Header资源/TMDB/取消/分季动作、权限session owner、错误通知及focus/accessibility传播 |
| S233 | W007独立复核与争议 | review_a001_j独立确认失败态计入ready、无错误/retry及退出重进重建机制，但认为错误呈现是否必须属产品语义，拒绝新增finding；既有详情finding传播与三类未验证边界闭合，转verify_a001_h第三窄裁决 |
| S234 | W008-A独立复核派发 | review_a001_j不参考主审候选，从头独立复核MediaDetailView状态初始化、权限session、首屏gate、task/onDisappear、背景focus/navigation及预加载传播 |
| S235 | W007第三裁决与F-180登记 | verify_a001_h独立确认三次失败→isDetailFailed计入ready→fullDetail仍nil→partial页面无错误/retry→仅退出重进重建的完整链，裁决条件性P3并登记F-180；反证只限制严重度，W007转待回溯 |
| S236 | W008-B主审 | W008-B建议一个P3候选：scene回active与60秒轮询共用本地active订阅gate，电影本地false时无法发现远端新建订阅，Header保持“订阅”且首次点击只刷新无反馈；既有订阅/Header/session/focus传播闭合，待独立复核 |
| S237 | W008-C主审派发 | review_a001_h从头只读主审MediaDetailView Hero背景/标题元数据、content scroll/focus、详情数据投影、图片navigation及accessibility传播 |
| S238 | W008-A独立复核与额外裁决 | review_a001_j从源码确认Hero/Content FocusState事件顺序依赖且建议未验证条件性P3，但定位ReviewPlan时意外看到主审状态摘要；其余传播审查保留，候选交verify_a001_h在不读审计文档前提下第三窄裁决 |
| S239 | W008-B独立复核派发 | review_a001_j从头独立复核MediaDetailView订阅刷新、scene/周期触发、Header资源/TMDB/取消/分季动作、权限session owner、错误通知及focus/accessibility传播 |
| S240 | W008-A第三裁决与F-181登记 | verify_a001_h在不读审计文档前提下独立确认Hero/Content事件顺序依赖机制，但Apple未承诺两FocusState相对写回且焦点可能自动滚动；裁决登记F-181未验证条件性P3，不确认也不驳回，W008-A转待回溯 |
| S241 | W008-C主审 | W008-C无新编号并转待独立复核；Hero/Header/详情投影、TMDB资源动作、元数据/人物标题、图片转场与未验证F-181既有finding传播闭合，原生Button静态accessibility无新增缺陷 |
| S242 | W008-D主审派发 | review_a001_h从头只读主审MediaDetailView分季/导演演员数据投影、Paginator/loadMore/focus、身份navigation、图片预加载、订阅动作及accessibility传播 |
| S243 | W008-B独立复核与F-182登记 | review_a001_j独立确认本地false/空分季使scene与周期入口跳过远端false→true、Header或分季首次点击只刷新无反馈的完整链；两代理一致裁决条件性P3并登记F-182，既有前台强刷契约足够，不新增CHK |
| S244 | W008-C独立复核派发 | review_a001_j从头独立复核MediaDetailView Hero背景/标题元数据、content scroll/focus、详情数据投影、图片navigation及accessibility传播 |
| S245 | W008-C独立复核与额外裁决 | review_a001_j无新确认finding，独立确认F-050并提出TMDB按钮双Task可能重复append/提前清共享overlay的未验证P3候选；主审未提该项，转verify_a001_h在不读审计文档前提下第三窄裁决 |
| S246 | W008-D独立复核派发 | review_a001_j从头独立复核MediaDetailView分季/导演演员数据投影、Paginator/loadMore/focus、身份navigation、图片预加载、订阅动作及accessibility传播 |
| S247 | W008-D主审 | W008-D无新编号；分季身份/订阅子链、剧集组并发、演员分页生命周期、图片Cookie/URL、人物投影身份导航、卡片accessibility与性能既有finding传播闭合；onSeasonTap/initialSeason仅记Ponytail死链清理项，待独立复核 |
| S248 | W008-E主审派发 | review_a001_h从头只读主审MediaDetailView推荐/相似Paginator、loadMore/focus、身份navigation、图片预取、error/empty/loading、生命周期及accessibility传播 |
| S249 | W008-C第三裁决与F-183登记 | verify_a001_h在不读审计文档前提下独立确认TMDB双Task、共享busy提前清与重复append静态重入链，但tvOS第二次Select可达性无静态证据；裁决登记F-183未验证条件性P3，W008-C转待回溯 |
| S250 | W008-E主审 | W008-E无新编号；推荐/相似失焦分页、错误/成功空恢复、共享身份/预载task、图片Cookie/URL、详情预载菜单、卡片展示与转场既有finding传播闭合；合集route与运行/外部payload维持未验证，待独立复核 |
| S251 | W009主审派发 | review_a001_h从头只读主审PersonDetailView人物route/identity、详情请求/error恢复、作品分页/身份navigation、图片预取、session/lifecycle及focus/accessibility传播 |
| S252 | W008-D独立复核 | W008-D无新编号并转待回溯；分季身份/订阅子链、剧集组并发、演员分页生命周期、人物投影身份导航、图片Cookie/URL及卡片accessibility既有finding传播独立闭合，onSeasonTap/initialSeason仅留死链清理项 |
| S253 | W008-E独立复核派发 | review_a001_j从头独立复核MediaDetailView推荐/相似Paginator、loadMore/focus、身份navigation、图片预取、error/empty/loading、生命周期及accessibility传播 |
| S254 | W008-E复核轻微状态暴露与盲审 | review_a001_j完成源码结论后按finding号去重时意外看到一行W008-E索引；未读取正文/主审结论，但按最严格独立性不单独关单，改由verify_a001_h不读审计文档盲审全段及合集Loading候选 |
| S255 | W009候选归并修正 | review_a001_h撤回人物详情失败新编号建议：catch/print、冷失败与合法空/partial不可区分、hasLoaded前置阻断重试同根并入F-126；F-180的既有failed状态主动计ready与task重建机制仍独立 |
| S256 | W010主审派发 | review_a001_j从头只读主审CollectionDetailView合集route/identity、详情请求/error恢复、items分页/身份navigation、图片预取、session/lifecycle及focus/accessibility传播 |
| S257 | W008-E第三盲审污染 | verify_a001_h在已独立形成合集route/inert task主链后误把`.agents`纳入rg并读到多条审计命中，主动声明盲审失效；固定代理池无全新视角，要求其仅提交区分污染前后的普通技术报告，不把候选升级确认 |
| S258 | W009主审 | W009提出未编号条件性P3候选：完整简介Sheet无ScrollView/分页，长biography可能无可达余文；人物详情失败撤回新编号并入F-126，F-143/F-144及既有route/request/分页图片session/accessibility传播闭合，待独立复核 |
| S259 | W011主审派发 | review_a001_h从头只读主审ResourceResultView资源状态/error/empty/retry、筛选排序、卡片下载、身份session/lifecycle及focus/accessibility传播 |
| S260 | W008-E程序限制收口与F-184登记 | 三代理均形成合集route/inert task静态链；review_a001_j在源码结论后见单行索引、verify_a001_h在主链形成后误读多条审计命中，均永久披露且不算零暴露票。唯一缺口为生产推荐/相似payload是否含collection_id，登记F-184未验证条件性P2，W008-E转待回溯 |
| S261 | W010主审 | W010无新确认finding；提出collection_id=0跨端route分歧与首次body短暂空态两个未验证P3候选，既有分页错误/session/Cookie预取/menu/card/lifecycle传播闭合，正IDroute/Web/Backend分页与子导航通过，待独立复核 |
| S262 | W009独立复核派发 | review_a001_j从头独立复核PersonDetailView人物route/identity、详情请求/error恢复、作品分页/身份navigation、图片预取、session/lifecycle、长简介可达性及focus/accessibility传播 |
| S263 | W009独立复核与第三裁决 | review_a001_j确认长简介无ScrollView链但建议条件触发后P2，并把空action加载/无简介Button视为独立P3；与主审的未验证P3及并入F-158裁决分歧，转verify_a001_h第三窄裁决 |
| S264 | W011主审 | W011无新编号；建议F-110从候选升级已确认P3，default方向箭头变化但比较器永远pri_order降序的静态反例闭合；F-080补部分结果遮错，其他资源状态/SSE/筛选卡片下载/session/focus传播闭合 |
| S265 | W011独立复核派发 | review_a001_j从头独立复核ResourceResultView资源状态/error/empty/retry、筛选排序、卡片下载、身份session/lifecycle及focus/accessibility传播 |
| S266 | W012主审派发 | review_a001_h从头只读主审AddDownloadSheet状态/关闭、下载器目录原形选择、手动搜索身份、提交error/session owner及focus/accessibility传播 |
| S267 | W009第三裁决与F-185登记 | verify_a001_h声明此前误读不含W009/PersonDetail；裁决足够长biography在无ScrollView的模态Sheet内必有不可达尾部，登记F-185已确认P2。加载/无简介空action Button及空作品focusable Text并入F-158同根传播，W009转待回溯 |
| S268 | W012主审 | W012无新编号；提交中独立取消关闭而POST继续建议并入F-147，旧Sheet载荷跨session提交、权限热变、重入、下载器nil不可逆、手动搜索身份、Picker/错误反馈/focus/accessibility等既有finding传播闭合，待独立复核 |
| S269 | W010独立复核派发 | review_a001_h从头独立复核CollectionDetailView合集route/identity、详情错误/空/重试、items分页/子导航、图片预取、session/lifecycle及focus/accessibility |
| S270 | W011独立复核与F-110升级 | review_a001_j独立确认default排序方向控件改变而比较器忽略isAsc，F-110升级已确认P3；业务error后补搜归F-080、可空促销因子解码归F-022、下载关闭/session归F-147/F-027。促销枚举分裂、筛选后零项空白、错误/空态无重试边界转主审定向裁决 |
| S271 | W012独立复核派发 | review_a001_j从头独立复核AddDownloadSheet状态/关闭、下载器目录原形选择、手动搜索身份、提交/error/session owner、权限热变及focus/accessibility |
| S272 | W013-A主审 | verify_a001_h确认包装route/StateObject owner/原生退出及内容状态委托通过；initialSeason/onSeasonTap与W008-D既有死链清理结论一致。提出`.task`取消后hasLoaded不复位、取消可误报/吞掉并阻止同身份重载的条件性P2候选，待独立复核及F-126/F-035/F-144去重 |
| S273 | W011第三窄裁决派发 | verify_a001_h不读审计文档定向核对促销枚举分裂、筛选后零项空白、错误/空态无重试三个边界，并复核F-080/F-022/F-147/F-027归并是否充分 |
| S274 | W010独立复核 | review_a001_h确认首屏错误/无重试、离页不取消、稀疏身份、预取Cookie、session及空态/卡片语义均落既有根因；提出`collection_id`关系字段即route类型的更广条件性P2候选，首次body短暂空态未获支持 |
| S275 | W013-A独立复核派发 | review_a001_h从头独立复核SubscribeSeasonView包装route/StateObject owner、task取消/重现、会话生命周期、入口退出与错误空态委托 |
| S276 | W011第三裁决与F-186/F-187登记 | verify_a001_h无W011污染并核对本地当前Web/后端快照；确认促销重算压扁枚举为独立P2，资源错误/成功空无重试为独立P2，登记F-186/F-187。筛选零项焦点归F-158，missingSites归F-080，null因子解码归F-022，AddDownload生命周期/session归F-147/F-027，W011转待回溯 |
| S277 | W010第三裁决派发 | verify_a001_h带既往collection_id状态暴露披露，定向核对0/负ID、合集子项父ID、relation字段即route类型及与F-184/F-138边界；不冒充零暴露盲审 |
| S278 | W010第三裁决与F-184扩展 | verify_a001_h确认既往collection_id审计命中暴露且无法证明未见W010具体状态，永久不算零暴露票；技术裁决0的TV/Web分路成立但生产不可达，负数双方共同缺gate，当前后端不注入父ID且原始part未知。全部并入F-184共享合集route身份，W010转待回溯 |
| S279 | W012独立复核与第三裁决派发 | review_a001_j用当前Web/后端快照提出高级媒体ID未贯穿下载端点、手动搜索source未被后端消费、空路径重复/非法值三个待定边界；提交owner/session、旧搜索与下载器默认等既有传播闭合，转主审review_a001_h定向裁决 |
| S280 | W013-A独立复核与第三裁决派发 | review_a001_h确认取消后hasLoaded机制但建议P3，并把跨服分季缓存归共享cache namespace、非电影二分归共享订阅类型；其把initialSeason闭包存在解释为可达P2，与W008-D双审死链结论冲突，转review_a001_j按季卡真实action裁决 |
| S281 | W013-B主审派发 | verify_a001_h从头主审SubscribeSeasonView内容与交互的加载恢复、季/组身份选择、订阅副作用owner/session/权限、任务生命周期、Sheet/focus/scroll/accessibility |
| S282 | W013-A第三裁决与F-126升级 | review_a001_j确认季卡异步主操作从不调用onSeasonTap且测试锁定直订/取消，initialSeason为死链清理不立项；Tab保留NavigationStack提供同StateObject取消重现生产见证，hasLoaded取消锁死扩展F-126并升级P2，吞取消晚启动扩展F-144，W013-A转待回溯 |
| S283 | W013-B独立复核派发 | review_a001_j从头独立复核SubscribeSeasonView内容与交互的加载恢复、季/组身份选择、订阅副作用owner/session/权限、任务生命周期、Sheet/focus/scroll/accessibility |
| S284 | W012第三裁决与F-188/F-189/F-135 | review_a001_h核对当前Web/后端快照，确认无原media高级正ID未贯穿下载端点与手动搜索source错配为独立P2，登记F-188/F-189；空目录生产链令F-135升级确认P3。当时将原media分支并入F-011；2026-08-08窄裁决已把该分支移回CHK-003未验证边界。提交owner/session与下载器默认等既有传播闭合，W012转待回溯 |
| S285 | W013-C主审派发 | review_a001_h从头主审SubscribeSeasonView详情Sheet呈现关闭、季状态/订阅取消owner、错误反馈、focus/scroll/accessibility及动态布局 |
| S286 | W013-B主审 | verify_a001_h确认剧集组乱序/列表错误、临时订阅回滚、权限/session写动作与卡片语义分别落F-146/F-148/F-027/F-048/F-130/F-147/F-171；提出非TMDB按季取消在当前后端忽略season并删除全部季的共享缺陷，待独立复核与兼容边界裁决 |
| S287 | W013-C主审 | review_a001_h确认详情长overview无ScrollView建议扩展F-185；提出S00/nil/空白季名与卡片标题分裂P3候选，无海报高度维持运行未验证；延迟动作模态竞争与Sheet后toast分别归既有动作owner/F-108 |
| S288 | W013-C独立复核派发 | verify_a001_h从头独立复核SeasonDetailSheet呈现关闭、季详情/状态投影、动作owner、错误反馈、focus/scroll/accessibility及动态布局 |
| S289 | W014主审派发 | review_a001_h从头主审SubscribeSheet新建/编辑准备、临时创建/暂停/回滚、保存/取消/关闭、配置身份、session/权限、并发/错误及focus/scroll/accessibility；定向裁决`exist_ok`复用既有ID的created/ownership语义 |
| S290 | W013-B独立复核与风险升级 | review_a001_j独立确认group乱序错误订阅、group列表default恢复缺口、临时订阅退出遗留与当前非TMDB跨季删除；F-146/F-148/F-047升级条件性P1。既有ID误暂停/删除候选转W014裁决，W013-B保持候选裁决中 |
| S291 | W013-C独立复核与F-190登记 | verify_a001_h确认长overview并入F-185，S00与空白name/date/overview投影获第二票并登记F-190确认P3；无写操作owner，可访问关闭维持运行盲点。其在W013-B已读目标源码但未读主审结论，永久披露 |
| S292 | W013-C海报布局第三裁决派发 | review_a001_j只读定向裁决width-only海报容器在URL缺失/失败时是否已构成静态缺陷及P2/P3边界，并快速核对F-185/F-190；不扩展全文件重审 |
| S293 | W015主审派发 | verify_a001_h从头主审ForkSubscribeSheet新建/编辑/分享身份与payload、加载恢复、配置、保存/取消/关闭、远端副作用owner、session/权限、并发/通知及focus/scroll/accessibility/动态布局 |
| S294 | W013-C第三裁决与F-191登记 | review_a001_j确认width-only海报在缺图/失败时无法维持360×540静态成立但仅支持P3，登记F-191；同时确认F-185共享长文本根因与F-190展示归一化。其W013-B既往源码暴露永久披露，W013-C转待回溯 |
| S295 | W016主审派发 | review_a001_j从头主审StatusView权限呈现、三状态卡四态/刷新、下载/转移分区、并发owner/session、导航/通知及focus/scroll/accessibility/动态布局，并回溯部分成功混合快照与manage-only三卡边界 |
| S296 | W014定向裁决与W013-B闭环 | review_a001_h确认当前后端`exist_ok=True`重复创建返回既有ID且success，TV丢失created/reused后无条件暂停并可取消删除；与Retry误删/退出遗留统一并入F-148 created/owner/session receipt条件性P1，不新增重复编号。W013-B转待回溯，W014继续全文件主审 |
| S297 | W014主审 | review_a001_h完成SubscribeSheet全文件；破坏性生命周期归F-147/F-148，提出custom_words多行合同被单行输入降级P2候选，域外站点/规则归F-170并建议P2升级；保存路径、数值null/0、辅助功能保留未验证，转待独立复核 |
| S298 | W017主审派发 | review_a001_h从头主审DownloadTaskView客户端/任务/行owner、列表四态/轮询/分页、mutation确认反馈、session/权限、旧客户端/响应、进度投影及focus/scroll/accessibility/动态布局 |
| S299 | W015定向确认F-191传播 | verify_a001_h不读审计文档确认Fork的360×540 processor不构成布局约束，内外width-only且四态均无显式2:3槽位；具体形态依父提案/固有尺寸，维持F-191 P3并继续全文件主审 |
| S300 | W015主审 | verify_a001_h完成ForkSubscribeSheet；权限续登重放/通知/旧错误/长文本/海报/退出与样式分别映射F-027/CHK-005、F-008、F-121、F-185、F-191、F-165/F-164。提出Fork POST→GET→编辑器统一owner P2及确认页隐藏keyword/custom_words P2候选，转待独立复核；既往源码暴露永久披露 |
| S301 | W014独立复核派发 | verify_a001_h从源码独立复核SubscribeSheet全文件，定向裁custom_words多行合同、F-170严重度、F-147/F-148生命周期边界，以及保存路径、数值null/0与advanced a11y未验证项；此前目标源码暴露须永久披露 |
| S302 | W016主审 | review_a001_j确认manage-only可操作他人下载任务P1候选、F-149/F-150建议升P2、clients首次失败后永久伪空P2；session归CHK-005，Transfer错误/外删对账/焦点竞态转W019，下载重入/反馈转W017；转待独立复核 |
| S303 | W015独立复核派发 | review_a001_j从源码独立复核Fork确认字段、POST→GET→编辑器owner、权限续登重放、通知/旧错误/长文本/海报/样式/退出传播及最终操作语义；不得读取主审结论 |
| S304 | W017主审与F-192/CHK-012登记 | review_a001_h完成DownloadTaskView；与W016不同代理共同确认跨用户任务缺少后端owner授权，登记F-192 P1与CHK-012。F-091传播闭合；F-095/删除确认/F-024/F-094严重度、动作响应与Transmission暂停消失转待独立复核 |
| S305 | W016独立复核派发 | review_a001_h从源码独立复核StatusView三卡/下载/Transfer呈现、状态恢复、session与焦点，定向裁F-149/F-150升级及Transfer下游边界；其刚完成W017，下载子链既往源码暴露永久披露 |
| S306 | W015独立复核与F-193/F-194登记 | review_a001_j独立确认Fork POST→GET→编辑器缺统一owner及POST成功GET失败无恢复为F-193 P2，确认最终页隐藏立即持久化的keyword/custom_words为F-194 P2；F-027升P1并补CHK-005，F-008/F-121/F-185/F-191传播闭合，W015转待回溯 |
| S307 | W014独立复核与F-195/严重度更新 | verify_a001_h独立确认custom_words多行合同并登记F-195 P2；F-147升P1、F-170升P2，F-148维持P1。total_episode nil→0/manual与任意save_path两项和主审边界不同，转第三裁决；advanced a11y维持运行未验证，既往源码暴露永久披露 |
| S308 | W016独立复核与Transfer转交 | review_a001_h独立确认F-149/F-150均应升P2，F-192/F-091只作传播；Paginator错误恢复、外部删除/更新对账、Reorganize关闭刷新焦点、旧session、长详情与search闭包环转W019，下载源码既往暴露永久披露 |
| S309 | W016 episode_count定向复核派发 | verify_a001_h仅从源码/跨端独立裁`episode_count == nil`被显示0是否构成P2/P3/未验证；不扩展W016/W019其他边界 |
| S310 | W018-A主审派发 | review_a001_h完整主审ReorganizeSheet 1-380表单段，定向复核F-075/F-162/F-163/F-166/F-168/F-189以及mutation session、payload、部分成功、focus/关闭与可访问性；W018-B/I015留后续 |
| S311 | W016 episode_count第二票与F-198登记 | verify_a001_h独立确认当前后端None/Web“未获取”被TV折叠0的确定反例，但按只读单值误报评P3；提出代理评P2，故登记F-198候选并保留P2/P3争议，转第三裁决，不由主协调代理选择 |
| S312 | W017独立复核与风险升级 | review_a001_j完整复核：F-024/F-095升级P1，F-083/F-092/F-093升级P2，F-094校准维持P3；登记F-196 P1删除文件未披露与F-197 P2 Transmission暂停消失，F-091/F-192/CHK-012传播闭合。完整只读/污染声明已收，checklist评估另补 |
| S313 | W014争议第三裁决派发 | review_a001_j仅独立裁total_episode nil→0/manual与开放save_path两项P2/P3/未验证边界，披露W015既往目标源码暴露，不扩展W014其他问题 |
| S314 | W019主审派发 | verify_a001_h完整主审TransferHistoryView，独立闭合Paginator错误恢复、外部删除/更新对账、Reorganize关闭刷新焦点、旧session、长详情与search闭包环，并主动找遗漏 |
| S315 | W018-A主审 | review_a001_h完成Reorganize表单段；提出F-188扩展、F-147提交关闭传播和自定义target_path候选，确认F-075/F-162/F-168传播，F-163未验证、F-166驳回；披露W016既往局部暴露，转待独立复核 |
| S316 | W018-B主审派发 | review_a001_h继续完整主审381-520预览段，定向复核F-151/F-075/F-074/F-162/F-165/F-168及预览→提交一致性、scroll/focus/a11y |
| S317 | W014第三裁决与F-199/F-200登记 | review_a001_j独立确认total_episode nil→省略→后端0/manual关闭自动刷新为F-199 P2；确认save_path合法根/子路径与远程storage URI被TV封闭/降形为F-200 P2。W014争议清空，advanced a11y维持未验证 |
| S318 | F-198第三裁决与W014 checklist补充派发 | review_a001_j独立裁Status剧集nil→0的P2/P3，并基于已读W014链判断F-199/F-200是否值得新增长期subscription compatibility CHK及准确测试措辞 |
| S319 | F-198第三裁决与CHK-013/014候选 | review_a001_j确认UGREEN/后端全nil、Web未获取与TV 0反例，但影响限超管状态页单项只读统计，裁F-198确认P3；建议F-199/F-200分别形成独立长期三态编辑与save_path值域CHK，先登记候选待不同代理清单复核 |
| S320 | W018-A独立复核派发 | review_a001_j从源码完整复核Reorganize表单段，独立裁F-188/F-189、F-147、target_path候选及F-075/F-074/F-162/F-163/F-166/F-168/session/权限边界 |
| S321 | W019主审与F-201…F-205候选登记 | verify_a001_h完成TransferHistoryView；提出失败errmsg不可达、稀疏FileItem毒化整页、deletedest失败仍删历史三个P2及外部删除/替换陈旧、Reorganize刷新吞焦点两个P3候选；F-027/CHK-005、F-033/F-071/F-072/F-185等传播，转待独立复核 |
| S322 | W020-A主审派发 | verify_a001_h完整主审SystemView 1-113根状态与主体，定向复核profile/session/权限热变、任务owner、Tab/focus/overlay及F-109/F-111/F-112/F-113/F-130/F-157/CHK-005 |
| S323 | W018-B主审与清单复核闭合 | review_a001_h完成Reorganize预览段，确认F-074/F-151/F-158/F-162/F-165/F-185传播且无新编号；同时独立确认CHK-013/014，并与review_a001_j第二票共同确认W017新增CHK-015/016/017；通用G09建议待W018-B第二票 |
| S324 | W019独立复核派发 | review_a001_h完整独立复核TransferHistoryView及F-201…F-205；永久披露其W018-B时曾为Reorganize调用链局部查看该文件，不把候选当结论 |
| S325 | W018-A独立复核与F-206登记 | review_a001_j从源码/当前跨端链确认F-188扩展P2、F-189遮蔽边界、F-147本段P2及F-156/F-027等传播；以第二票确认自定义target_path为F-206 P2，W018-A转待回溯并补强CHK-005 |
| S326 | W018-B独立复核派发 | review_a001_j完整复核ReorganizeSheet 381-520；永久披露已读W018-A与ledger候选名，定向裁F-074/F-151/F-158/F-162/F-165/F-185、边界及通用G09清单价值 |
| S327 | W020-A主审与W020-B派发 | verify_a001_h完成SystemView 1-113，提出F-130/CHK-005常驻根页、F-144串行首载、F-157直接恢复及F-109/F-111/F-112等传播且无新编号；随后继续主审114-195并披露局部暴露 |
| S328 | W018-B独立复核闭合 | review_a001_j第二票确认F-074/F-151/F-158/F-162/F-165/F-185传播，无新finding/订阅CHK；通用G09不可变intent+generation+session与完整模型exact-dedup不变量获两票，W018两段完成 |
| S329 | W019独立复核闭合 | review_a001_h确认F-201…F-205及F-165/F-185传播；F-204基本项P3，SQLite同ID复用导致旧确认删新目标的条件性P1放大链转I009固定fixture裁决 |
| S330 | W020-A独立复核与W020-C主审派发 | review_a001_h从源码独立复核SystemView 1-113并披露V002既往下游暴露；review_a001_j主审196-388根页/连接/App信息，二者均不越界其他分段/I016 |
| S331 | W020-A独立复核闭合 | review_a001_h第二票确认无新编号并收窄：权限门禁会重算但缺收敛事件；F-157只确认同owner成功不清旧终态，不宣称必然同屏。F-130/CHK-005、F-144/F-157、F-109/F-111/F-112、F-126/F-060传播闭合 |
| S332 | W020-B独立复核派发 | review_a001_h完整复核SystemView 114-195，披露W020-A根route边界既往暴露；与verify_a001_h主审并行但不互读结论 |
| S333 | W020-C主审、F-207登记与W020-D派发 | review_a001_j完成根页/连接/App信息主审，登记重登成功后连接信息旧快照候选P3并闭合会话、版本、长文本与退出传播；随后继续主审389-465并披露相邻段暴露 |
| S334 | W020-B主审、F-208登记与I015派发 | verify_a001_h完成页面容器主审，登记未尊重Reduce Motion候选P3并传播F-130/F-161/F-185；随后对ReorganizeSheet整文件做跨段集成复核，不读取审计结论 |
| S335 | W020-B独立复核闭合与W020-E派发 | review_a001_h第二票确认F-208 P3，收窄F-130为空白非法route确定但Back/Menu投递与恢复待运行，F-161页面级传播维持未验证，并确认本段无手势滑动；永久披露误显W020-C头20行。随后主审466-552过滤页与通用行 |
| S336 | W020-D主审、F-209/F-210登记与W020-F派发 | review_a001_j闭合“全部”误映射IndexerSites默认子集与RSS域误作搜索站点集合两条条件性P2候选，并传播F-112/F-130/F-170/F-189等；推荐同名path保持未验证。随后主审553-793路由/焦点/规则预览辅助并披露相邻段暴露 |
| S337 | W020-E主审、F-211登记与W020-D独立复核派发 | review_a001_h完成过滤页/通用行主审，登记旧规则A展示与执行时二次拉取B/缺ID的P3候选，四态并入F-126，规则身份/跨owner/selected传播F-081/F-130/F-168；随后从头独立复核389-465站点/推荐/媒体来源 |
| S338 | I015整文件复核、F-212/F-213登记与W020-C独立复核派发 | verify_a001_h确认目标目录(storage,path)复合身份丢失与电影隐藏剧集字段仍执行两条P2候选；修正F-151/G09为request内exact-dedup且跨intent保留logID provenance，确认既有整理传播。随后从头独立复核196-388根页/连接/App信息 |
| S339 | W020-F主审闭合与W020-E独立复核派发 | review_a001_j确认无新编号，F-130/CHK-005、F-126、F-085、F-208传播，撤回Reduce Motion P2建议并维持F-208 P3；随后从头独立复核466-552过滤页，披露F段曾最小读取E的focus绑定 |
| S340 | W020-D独立复核、F-214登记与W020-F独立复核派发 | review_a001_h第二票确认F-209/F-210机制及P2但建议合并为单一搜索站点合同；新增全局推荐配置owner候选F-214并与主审Web证据冲突，转第三裁决；媒体source并入F-189、加载/session归既有项。随后从头复核553-793并披露F段符号命中 |
| S341 | W020-E独立复核、F-215登记与W020-G派发 | review_a001_j确认设置/执行两次GET但建议F-211拆归既有项；另提出CustomRule身份/可辨识标签条件性P2，与主审F-081/P3边界冲突，登记F-215并转第三裁决。随后主审794-932并披露既往C/D/E/F及最小G边界暴露 |
| S342 | W020-C独立复核、F-207确认/F-216登记与W020-D第三裁决派发 | verify_a001_h第二票确认F-207 P3；旧登录与settings发布归F-027/F-130/CHK-005，认证用户名与长文本归F-111/F-162；新增刷新鉴权失败错误交接F-216候选待不同代理复核。随后第三裁W020-D两条站点finding、推荐owner与CHK-018/019 |
| S343 | W020-F独立复核闭合与W020-H派发 | review_a001_h确认无新编号，失权route/focus归F-130/CHK-005，初焦清除来源/规则归F-168，规则加载/预览归F-126/F-085；其P2 Reduce Motion建议无新增静态后果，协调维持既有F-208 P3。随后主审933-970并披露D中933符号行暴露 |
| S344 | W020-H主审与R001派发 | review_a001_h确认不新建编号；空白/非法正则及size/seeders/publish_time边界会令预览与执行相反，建议归F-081并升P2，待独立复核。随后主审ContentView全文件并披露多下游调用链暴露 |
| S345 | W020-D第三裁决闭合 | verify_a001_h确认F-209/F-210应保持两条独立P2；裁F-214机制并入F-109，核清当前Web本地优先缓存+后端per-user权威；确认CHK-018/019长期保留，W020-D转待回溯 |
| S346 | W020-G主审、F-217登记与G/H双复核派发 | review_a001_j登记条件Exit modifier在pop离场窗口改变结构身份并重启推荐task候选P2，window级Menu/Sheet留I016；verify_a001_h从头复核G，review_a001_j随后从头复核H的F-081严重度与语义矩阵 |
| S347 | W020-G独立复核与第三裁决派发 | verify_a001_h第二票确认结构分支切换与推荐task重启，但因只读GET、顶层StateObject保留和静态后果有限，拒绝独立P2并建议合并或最多P3；F-217转review_a001_h第三裁决。window/Menu/Sheet继续I016运行项 |
| S348 | W020-H独立复核、F-085升级与F-216复核派发 | review_a001_j确认H只属于已解码单条规则解析/预览/matcher合同，不给F-081数组/缺ID链加权；当前Web正常可达size单值/seeders区间可清空搜索或静默失效，双审将F-085升P2。随后定向复核W020-C刷新鉴权失败错误交接 |
| S349 | R001主审、F-218登记与F-217第三裁决派发 | review_a001_h闭合ContentView全文件：权限热变归F-028，根settings/媒体handler归F-130/CHK-005，通知与辅助功能归既有项；新增已存会话准备门晚于认证首帧F-218候选P3。因已暴露R002前13行不转主审，随后第三裁F-217 |
| S350 | F-217第三裁决与I015独立复核派发 | review_a001_h确认条件Exit结构分支重建/推荐task重启，但根StateObject保留且只读GET不足P2；稳定modifier修复与通用task owner互不替代，裁独立P3，W020-G转待回溯。随后独立复核I015目录复合身份与电影隐藏字段两候选 |
| S351 | W020-E第三裁决与R002派发 | verify_a001_h裁F-211复合编号拆归F-126/F-081，同ID当前B执行符合合同；裁F-215坏identity完整并入F-081、合法长名留运行风险，并以缺ID/重复ID核心过滤后果支持F-081升P2。W020-E转待回溯，随后主审App入口R002 |
| S352 | F-216定向复核、并入F-107与R001独立复核派发 | review_a001_j确认刷新401/403先logout清凭据、System局部错误在新Login最终不可达，网络/500/成功边界明确；机制静态成立但根错误owner与F-107相同，F-216驳回并入，F-089只作分类交叉。随后从头独立复核ContentView与F-218 |
| S353 | R002主审闭合 | verify_a001_h确认App入口注入与初始化无新缺陷；App级NotificationManager跨logout与排队show重排并入F-107，媒体handler跨认证根归R001/F-130/CHK-005，toast VoiceOver继续归F-159运行验证；R002转待复核 |
| S354 | I015独立复核闭合 | review_a001_h独立确认F-212目录复合身份与100ms混合tuple、F-213明确电影隐藏剧集字段仍被后端执行，二者均保留P2；补充旧transfer_type残留、episode_part公共字段及Auto后端门控边界，转待回溯 |
| S355 | I012集成复核派发 | verify_a001_h在未参与W006任一分段主审的前提下，从头完整复核SearchView跨段共享状态、focus、权限/session、异步owner、身份导航、错误四态、辅助功能与遗漏符号；永久披露既往必要调用链暴露 |
| S356 | I011集成复核派发 | review_a001_h在未参与C018任一分段主审的前提下，从头完整复核TorrentsResultView跨段筛选/排序/soft-filter、option身份、季集解析、展示合同、focus与遗漏符号；永久披露既往A/B独立复核暴露 |
| S357 | R001独立复核与R002独立复核派发 | review_a001_j完整确认F-218静态入口及Home/settings时序，但建议并入既有启动/settings/session owner，和主审独立保留意见形成第三裁决；根MediaAction跨logout完整归F-130/CHK-005。随后从头独立复核App入口R002，披露此前仅见第6/11行owner命中 |
| S358 | R002双审闭合与I004集成派发 | review_a001_j完整确认App入口、单一NotificationManager owner与注入无新编号；旧session通知并入F-107，但logout不能全清而丢当前原因，Sheet与VoiceOver继续归F-108/F-159运行项。R002转待回溯，随后在未参与V002分段主审的前提下集成复核SystemViewModel |
| S359 | I011集成结果与I005派发 | review_a001_h完整复核TorrentsResultView，F-032/F-057…059/F-061/F-110/F-168/F-179/F-186传播闭合；提出F-061升P2与TorrentCard并入F-175两项待不同代理复核，同ID更新和底部焦点只列runtime。随后在未参与V004分段主审的前提下集成复核MediaPreloader |
| S360 | I012集成结果、F-219登记与F-218第三裁决派发 | verify_a001_h完整复核SearchView，新增同ID新载荷不重算派生状态F-219候选P2；其余旧资源、分页错误、会话、人物身份、任务、预载、fallback、硬过滤、豆瓣头像均并入既有编号，部分P2建议转第三裁严重度。随后第三裁R001/F-218独立编号与启动/settings owner边界 |
| S361 | I004集成闭合与I011/I012定向裁决派发 | review_a001_j完整复核SystemViewModel，无新编号；手动重登/profile owner、站点规则四态、取消、共享settings及当前source/RSS合同均精确并入既有F/CHK，F-028/F-030不扩展。随后集中第三裁F-219、F-076/F-036/F-035/F-039/F-103/F-061严重度及F-175 TorrentCard传播 |
| S362 | F-218第三裁决闭合与I003派发 | verify_a001_h确认首次同步body认证分支、会话后settings出口窗口与异步session owner三条边界互不替代，保留F-218条件性P3；真实认证帧/Home task仍待运行。R001转待回溯，随后在未参与A001任一分段主审的前提下集成复核APIService全文件 |
| S363 | I011/I012第三裁决闭合与I007派发 | review_a001_j驳回F-219当前生产缺陷；F-076/F-103/F-061升P2，F-175确认TorrentCard同根并升P2，F-036/F-035/F-039维持P3。I011/I012转待回溯，随后在未参与V011分段主审的前提下集成复核SearchViewModel |
| S364 | I005集成结果、F-220/F-221登记与G08派发 | review_a001_h完整复核MediaPreloader，新增跨阶段屏障F-220候选P2与partial识别终态F-221候选P1；其余归既有owner但多项严重度升级待不同代理裁决。随后全局回溯通知呈现G08 |
| S365 | 第三裁决与I005候选落账校验 | F-061/F-076/F-103/F-175升级、F-219驳回及F-220/F-221候选明细全部落账；同步校准F-012/F-019/F-047/F-048/F-146既有摘要与明细首行。findings保持221条摘要/221条详情，CHK保持19/19，摘要状态与等级无冲突，五份受控文档diff check通过 |
| S366 | G08全局回溯结果与待复核登记 | review_a001_h完成唯一App通知owner、六个show与Handler、Sheet/session/计时/VoiceOver全链；登记F-222/F-223候选，F-107/F-108/F-121/F-159/H-012冲突均保持待不同代理裁决，不以单票升级或驳回 |
| S367 | I003集成结果与核心定向复核派发 | verify_a001_h完成APIService 2649/2649行全符号集成；session epoch/401 mutation重放扩大F-027/F-130/CHK-005，三缓存归F-065、下载响应归F-083、settings归F-106、clean EOF归F-080，无新确认编号。review_a001_h随后定向复核核心新传播 |
| S368 | I007集成结果、F-224/F-225登记与定向复核派发 | review_a001_j完成SearchViewModel 865/865行全符号集成；分享年份与可选分享屏障登记候选，其余八项拆分后精确并入既有F/CHK，F-219继续驳回。verify_a001_h随后从当前HEAD定向复核两候选及全部映射 |
| S369 | I007定向复核闭合 | verify_a001_h确认F-225为独立P2阶段屏障；F-224机制成立但并入F-137/F-141后驳回重复编号。全失败/部分失败归F-033，source/session/扫描/SSE/规则/旧fallback/长评分映射均确认，F-219继续驳回；I007转已闭环 |
| S370 | I003定向复核闭合 | review_a001_h确认旧relogin/跨服mutation重放归F-027/F-130/CHK-005且P1，三缓存归F-065 P2、下载响应归F-083 P2、clean EOF归F-080 P2、settings混合/吞取消归F-106并升P2；malformed SSE当前fallback不重开。I003无新编号并转已闭环 |
| S371 | G07全局回溯派发 | review_a001_h从当前HEAD回溯人员/职位/翻译全部生产owner、Person route/详情/卡片、Search/MediaDetail传播及测试；不得读审计文档，既往人物/详情/翻译源码污染永久披露 |
| S372 | G08独立复核与第三裁队列 | review_a001_j确认F-223独立P2；F-222机制/P1获两票但编号与F-107等级冲突，F108 P1/P3、F121驳回/保留、F159 P1/P3亦转第三裁。show后清nil丢消息及旧计时关新通知两票驳回；Home false/rollback归F-049/F-148，H-012不新增 |
| S373 | I008集成派发 | review_a001_j在未参与V012分段主审的前提下完整集成MediaDetailViewModel，覆盖partial/full合并、详情派生加载、订阅normal/force、取消intent、身份/session/权限/错误/cache与直接调用测试；既往详情订阅调用链污染永久披露 |
| S374 | I005定向复核闭合 | verify_a001_h确认F-221独立P2；F-220并入F-115后驳回重复编号，F-115按有订阅权限电视剧全屏Loading稳定关键路径升P2。F-117/F-118/F-119/F-180/F-184维持，既有F/CHK传播边界校准；I005转已闭环 |
| S375 | G08第三裁派发 | verify_a001_h从当前HEAD裁F-222/F-107合并与P1/P2、F108静态等级、F121当前presentation清错、F159静态P1/P3及H-012漏报映射；既往V001/R002通知源码污染永久披露 |
| S376 | G08三方裁决闭合 | verify_a001_h裁F-222并入F-107/CHK-005且根finding升P1；F-108维持未验证P3、F-121/F-159维持确认P3，Home false使F-049升P2、rollback留F-148 P1；F-223维持P2，H-012只传播，两项旧竞态说法维持驳回。ReviewPlan、findings、checklist与ledger同步闭合 |
| S377 | I013集成派发 | verify_a001_h从当前HEAD完整复核MediaDetailView全文件、直接调用者与测试，覆盖partial/full揭示、身份/route/session/权限、订阅/取消/Sheet、分区状态、焦点/scene/task、图片缓存、空值/长文本/可访问性；不得读审计文档，既往详情页面调用链污染永久披露 |
| S378 | G07全局主审结果与待复核登记 | review_a001_h完成当前HEAD人员/职位/翻译全链；canonical identity分别映射F-143/F-036、source筛选映射F-189/CHK-019、Hero/职位/头像/备用名/卡片映射既有族并保留升级裁决；新增F-226 Bangumi career候选P2。最佳结果先截后去重驳回，AniList插件与运行辅助功能保持未验证 |
| S379 | G10全局回溯派发 | review_a001_h从当前HEAD完整回溯共享Sheet焦点/样式组件与全部生产业务Sheet，覆盖焦点/disabled/empty、原生控制、Exit/提交、嵌套呈现、loading/error/success、长文本与VoiceOver；不得读审计文档，既往多业务Sheet/详情调用链污染永久披露 |
| S380 | I008集成结果与待定向复核登记 | review_a001_j完成MediaDetailViewModel全文件集成，无新编号；Header身份映射F-007并建议P1，cancel warning/intent与错误映射F-047/F-048/F-049，动态撤权永久Loading映射F-130 P2，远端新增映射F-182并建议P2，pin返回栈映射F-118并建议条件P2。全部升级保持待不同代理裁 |
| S381 | G07独立复核派发 | review_a001_j从当前HEAD独立重走人员/职位/翻译全链，逐项裁内嵌人物route/详情merge、跨source去重、source筛选、Hero、job/display、Bangumi career、备用名/头像及PersonCard/TorrentCard控制语义；不得读审计文档，既往Search/详情/人物源码污染永久披露 |
| S382 | G10全局主审结果 | review_a001_h完成37个生产文件/12,981行Sheet焦点/样式全链；提出10组P1/P2候选，当前仅登记为待去重/独立复核，优先映射F-076/F-108/F-120/F-126/F-130/F-147/F-148/F-158/F-160/F-162…F-165/F-168/F-185/F-193/F-205，不按单票新增或升级 |
| S383 | I008定向复核派发 | review_a001_h从当前HEAD独立裁Header直订身份、cancel intent/错误映射、动态权限ready、远端新增刷新与pin返回栈；F-007/F-182/F-118升级冻结，既往详情/订阅源码污染永久披露 |
| S384 | G07独立复核结果与第三裁队列 | review_a001_j完成A-H当前TV/Web/后端重验；F-226确认P2，稀疏详情与详情别名登记F-227/F-228候选P2；F-143/F-036/F-045/F-050/F-051/F-055/F-056/F-175/F-189等级/拆分与既有裁决冲突，转第三裁；F-034维持P2，F-053当前不可达，最佳结果旧说法驳回 |
| S385 | I009集成派发 | review_a001_j从当前HEAD完整复核TransferHistoryViewModel、直接调用者/API/Models与测试，重点闭合分页/轮询/选择/AI整理/session、SQLite同ID复用删除放大、外部对账、Reorganize回调与焦点；不得读审计文档，既往Transfer/Search调用链污染永久披露 |
| S386 | G10候选去重登记 | review_a001_h的10组主审候选按既有owner去重；仅F-229 MultiSelection确认/Exit语义与F-230旧系统固定字体登记候选P2，其余传播与等级冻结，待不同代理独立复核 |
| S387 | I013集成结果与待定向复核登记 | verify_a001_h完成MediaDetailView 1113/1113行集成；F-231登记TMDB跳转晚到候选P2，其余12组证据精确映射既有详情/订阅/session/focus/error/cache/a11y/长文本finding；既往详情页面及审计索引污染永久披露 |
| S388 | G07第三裁派发 | verify_a001_h从当前HEAD第三裁双审冲突，覆盖内嵌人物source route、稀疏详情merge、跨source去重、source筛选、Hero/roles/image、别名、Person/TorrentCard与career；不得读审计文档，既往F-143/C010/Search暴露永久披露 |
| S389 | I008定向复核结果与闭环 | review_a001_h独立确认F-007升P1、F-182升P2，F-118静态机制维持未验证P3且P2用户影响留运行；Header target会重查但scope/intent未绑定，F-047局部P2不改跨季P1，F-048/F-049/F-130映射闭合；既往详情/Sheet调用链污染永久披露 |
| S390 | I013定向复核派发 | review_a001_h从当前HEAD独立裁F-231 route-owner晚到、合集永久Loading、Sheet创建遗留、动态权限ready及焦点/失败/cache/a11y/长文本映射；不得读审计文档，既往G10/I008详情与Sheet调用链污染永久披露 |
| S391 | G07第三裁结果与G10独立复核派发 | verify_a001_h按当前TV/Web/后端裁F-143/F-036/F-227/F-226 P2、F-228 P3，F-056并入F-050 P3，F-045/F-051/F-055 P3、F-175/F-189 P2；随后从当前HEAD独立复核G10，既往人物/Search/业务Sheet源码污染永久披露 |
| S392 | I009集成结果与I010派发 | review_a001_j完成TransferHistoryViewModel 551/551行集成，无新编号；F-204提条件P1，F-071/F-154/F-155/F-205/F-098提P2，其余映射F-027/F-072/F-033/F-080/F-075/F-156/F-203/F-153；随后完整集成MediaCard，既往Transfer/Search及卡片调用链污染永久披露 |
| S393 | I013定向结果与I009独立复核派发 | review_a001_h确认F-231 P2、F-148 P1/F-130 P2传播；F-184、F-181及F-180/F-116等级/拆分冲突转第三裁。随后独立裁I009 SQLite同ID、session、轮询位移、retain、AI/整理/file outcome；既往详情/Sheet/W019调用链污染永久披露 |
| S394 | G10独立裁决闭环 | verify_a001_h完成23文件/6,270行复核；F-229确认P3、F-230确认P2，F-120/F-160/F-205升P2；F-148/F-027/F-193/F-076/F-185/F-158/F-162/F-168等传播闭合，既往业务Sheet源码污染永久披露 |
| S395 | I009定向裁决与排序第三裁闭环 | review_a001_h确认F-204条件P1、F-071/F-154/F-155/F-098 P2及既有传播，并提出同秒非全序分页；verify_a001_h第三裁确认新增F-232 P2。I009/V022/W019回溯闭合，随后verify_a001_h独立复核I010 |
| S396 | I013最终第三裁闭环 | review_a001_j裁合法正数合集F-184条件P1、F-180 P2、F-181未验证条件P2、F-116未验证P3，F-033根P2但详情局部P3；三项result/readiness保持独立，0/负数/parts未验证，F-231与其余传播闭合 |
| S397 | I006程序限制集成与定向复核派发 | review_a001_h受限完整复核ExploreViewModel 957行与ExploreView 569行，提出1项P1、4项P2、2项P3候选；现有三代理均曾主审某V009分段，不能宣称严格独立，全部编号/等级冻结并交review_a001_j不同代理重验 |
| S398 | I016程序限制集成派发 | review_a001_h从当前HEAD完整重读SystemView 970行及直接链；现有三代理均曾主审某W020分段，不能宣称严格独立，禁止读审计文档并永久披露既往System调用链污染；候选编号/等级冻结待不同代理复核 |
| S399 | I006受限独立复核与第三裁派发 | review_a001_j完整重验并确认F-233…F-236及F-033/F-135传播，新增F-237刷新代际与F-238重复query合同争议；session/权限owner建议P1。因严格独立缺口永久存在，verify_a001_h仅第三裁F-130等级、F-237与F-238，不冒充零暴露集成票 |
| S400 | I010独立复核登记与第三裁队列 | verify_a001_h确认合集route、订阅反向mutation、全局转场owner、URL-only图片cache、MediaCard/Canvas a11y与Search延迟preload；新增F-239确认P2，F-124/F-027/F-026/F-171/F-175/F-184传播闭合。F-020升级与F-174组合边界冻结待不同代理第三裁 |
| S401 | I016受限整文件主审结果 | review_a001_h完整读取SystemView 970行与直接链，11组技术结论中8组映射既有F；F-106/F-111/F-112升级提案冻结，F-208重复P2意见无新后果不重开，登记F-240…F-242候选。因三代理均曾主审W020分段，等待不同代理受限整文件复核且永久不宣称严格独立 |
| S402 | I006第三裁与受限闭环 | verify_a001_h确认A→B混页、subscribe撤权旧source/Paginator归F-130并维持P2；F-237代码机制因当前仅一个生产调度点驳回；F-238重复api_path/filter query构造成立但服务端scalar优先级缺失，转未验证P3。F-233…F-236两票确认不被推翻，严格独立缺口永久披露 |
| S403 | I010第三裁与闭环 | review_a001_h裁F-020在同URL跨账号字节或授权不同条件下升P1；F-174维持P3且poster/session归F-123，不新增组合项；F-239确认P2，其余传播闭合 |
| S404 | I014严格整文件集成登记 | review_a001_j完整读取SubscribeSeasonView及直接链，满足未主审W013分段的严格集成资格；11组中8组直接映射既有F/CHK，dead接口不成案，TMDB fallback、前台availability、cache namespace与Retry边界交review_a001_h定向复核；既往订阅/媒体调用链暴露永久披露 |
| S405 | I016不同代理整文件复核登记 | verify_a001_h完整读取SystemView 970行及直接链；与主审共同令F-111/F-112升P2、F-208维持P3、F-241转未验证P3、F-242收窄后确认P3，F-089/F-106/F-240等级冲突冻结待第三裁。两代理既往W020分段暴露永久披露 |
| S406 | I014定向复核与闭环 | review_a001_h确认canonical-only TMDB group链归F-012并使其转确认P2，前台availability为独立F-243 P2；API三缓存归F-065、Retry归F-148，MediaPreloader因logout clear且无绕过生产路径当前不成案。I014严格集成闭合，既往W013暴露永久披露 |
| S407 | 全局回溯第一轮主审派发 | review_a001_h主审G01搜索来源与系统默认值，review_a001_j主审G02订阅身份/缓存/刷新，verify_a001_h主审G03详情导航/预载/动作；三代理均获中性F/CHK命题、禁止审计文档/写入/运行及上游缺失边界，完成后按G01→j、G02→verify、G03→h轮换独立复核 |
| S408 | G01首轮全局主审结果 | review_a001_h完成搜索/SSE、System/SiteFilter、Explore/Recommend、Manual/AddDownload/Reorganize循环链；新增F-244候选，撤回键盘提交候选，提出多项等级/合并修订并确认五项CHK仍不完整。全部单票修订冻结待review_a001_j独立复核，既往源码暴露永久披露 |
| S409 | G02首轮全局主审结果 | review_a001_j完成订阅身份/cache/session/mutation/刷新与页面循环链；无新候选，MediaCard归F-175/F-171、MediaPreloader当前不成案，F-012/F-243独立确认；F-014反证及多项等级/范围修订冻结待verify_a001_h独立复核，既往源码暴露永久披露 |
| S410 | G03首轮全局主审结果 | verify_a001_h完成详情身份/图片/预载、Card/Grid/ContextMenu、Detail/Season/Sheet循环链；新增F-245候选、F-219不重开。F-100只核snapshot且CHK-009/010对象错位，连同全部等级意见冻结待review_a001_h独立复核；既往源码暴露永久披露 |
| S411 | 全局回溯第一轮独立复核派发 | review_a001_j独立复核G01并第三裁I016的F-089/F-106/F-240；verify_a001_h独立复核G02；review_a001_h独立复核G03。三代理只获中性F/CHK命题与候选合并问题，不得读取首轮意见/审计文档、写入或运行；Ponytail仅约束最小修复复杂度，不作事实证据 |
| S412 | 中断恢复与Round A纠偏复核重派 | 恢复时确认findings为245条、CHK为19条且goal仍active；S411中G02/G03报告虽已返回但出现编号漂移，未将错误票落账。重新以三个无审计结论上下文的只读代理分别复核G01＋I016第三裁、G02争议、G03纠偏对象；继续禁止写入、运行、派生子代理及Git操作 |
| S413 | G03纠偏独立复核结果 | rounda_g03_recheck完整复核34个生产文件/16,042行及9个测试文件；确认F-245为独立P2且与F-083仅共同关联CHK-017，F-116/F-171/F-174获得新的有效升级票，F-219继续驳回。F-097/F-118/F-221与CHK-006仍有票间实质分歧，冻结待窄第三裁；性能项F-173/F-177继续保留运行未验证 |
| S414 | G03一致结论部分落账 | F-245三票确认独立P2并关闭专属队列，CHK-017补Fork传播；F-116/F-171/F-174依据两张按正确编号完成的纠偏票分别升确认P2/P2/P2。F-097/F-118/F-221/CHK-006继续冻结；findings摘要/详情全量一致性恢复为0冲突 |
| S415 | G02纠偏复核与一致部分落账 | verify_a001_h及rounda_g02_third的错号报告均经原命题纠偏；F-014驳回，F-048升条件P1，F-067/F-086/F-119/F-144升P2，F-126按五条owner子链收窄并维持P2，CHK-003补typed容器未知子键/原始类型边界。F-003/F-006/F-065/F-121/F-127/F-199/F-200等仍待窄裁，不以单票或错号关单 |
| S416 | G03窄第三裁与组闭环 | rounda_g02_third按正确编号复核F-097/F-118/F-221及CHK-006：三项均收敛P2；F-118仅确认ownerless pin根因，push/onDisappear/LRU真机链仍未验证；F-221限于Header TMDB按钮。当前后端/Web detached HEAD静态核对确认CHK-006对非TMDB、重复命中及superuser跨owner fan-out仍不完整P1；未运行测试或后端。G03全部争议关闭，错号主审意见未落账 |
| S417 | G01纠偏复核与I016部分第三裁 | rounda_g01_recheck按正确编号复核Search/SSE、System/Recommend、Explore identity、Torrent、Subscribe/Reorganize及现有测试/当前Web；F-106最终P2、F-240确认P2，F-200纠正为“已有任意值和已配置URI保真、仅缺新增编辑”，F-142/F-206/F-225/F-234/F-235维持。F-244两票确认机制/P1条件影响但合并边界待第三裁；其余等级/状态分歧冻结。F-089获当前后端401证据但P1/P2/P3冲突，转G06；未运行任何验证 |
| S418 | G03后裁状态残留清扫 | findings摘要/详情一致后，逐项清理ReviewPlan、ledger单元/集成矩阵与checklist适用性表中仍把F-116/F-118写作未验证P3、F-171/F-174写作P3、F-119写作P3的旧当前状态；统一标注其已被G02/G03后裁覆盖，并保留实际闪烁、push/LRU及VoiceOver等运行边界。历史S批次日志保留原裁决作为时间线，不改写历史 |
| S419 | G04主审/独立复核裁决落账 | G04两份复核交叉后，主审对F-076/F-204的错号意见作废；双票或跨组一致证据使F-072/F-076/F-130/F-138升P1、F-129/F-139升P2，F-244并入F-130/CHK-005后作为重复编号驳回。F-032/F-033/F-034/F-035/F-039/F-142/F-154/F-176/F-232/F-236单票等级提案与F-143上游owner合同、F-204 SQLite复用边界继续冻结；未运行任何验证 |
| S420 | 上游全局阻塞解除 | 启动时规定的两个同级相对目录仍缺失；后续G03/G04/G05代理已确认 `/Users/chantxu/code/MoviePilot-Frontend` 与 `/Users/chantxu/code/MoviePilot` 为合法当前Git仓库并用于逐项静态合同核对，因此开放队列不再保留全局阻塞。实际部署版本、远端最新性与运行配置仍由各F/CHK逐项标未验证，不提升为运行证据 |
| S421 | G05主审/独立复核裁决落账 | G05主审的CHK编号映射整体错误，相关CHK票作废；两名不同代理按精确finding标题共同支持F-094/F-110/F-131/F-145/F-158/F-168/F-179升P2及F-197升条件P1。F-032/F-080/F-081/F-101/F-188/F-209/F-210/F-213等仅有单票升级，维持既有等级；F-133/F-134/F-238继续未验证，F-135维持P3。F-102当前producer path-safe但状态边界留窄裁；未运行任何验证，既往G02/G03/G04源码暴露永久披露 |
| S422 | G05已裁回溯队列清扫 | 关闭F-024/F-032/F-061/F-081/F-085/F-092/F-093/F-095/F-135/F-175/F-186/F-187/F-192/F-196/F-209/F-211/F-215/F-233/F-234对应的重复或已裁队列行；F-032/F-081/F-209保留既有P2，F-135保留确认P3及插件运行边界。W020-H随F-085闭环；G05组仍只等待F-102由G09独立票收口 |
| S423 | G06主审/独立复核与组闭环 | 两名不同代理从当前会话/权限/根状态生产链闭合G06；F-019/F-062/F-063/F-193为条件P1，F-030/F-031/F-084/F-109/F-157/F-089为P2，F-244继续并入F-130。未运行验证、未写产品文件，既往G01或G02…G05源码暴露永久披露 |
| S424 | G09 clean-room替代裁决闭环 | 首个窄代理因读取ReviewPlan/ledger不计独立票；全新代理不读审计文档，从TV/Web/后端重审后把F-073收窄为`success:true+data缺失/null`及item success缺失/null的P2，并确认F-246服务端manage读取授权P1与独立CHK-020；G09组闭环 |
| S425 | G04 clean-room窄裁闭环 | 全新零源码暴露代理独立裁F-034/F-035/F-039/F-137/F-142/F-143/F-176/F-236均为P2；F-035/F-039收窄为owner/session级aggregate cancel且显式cancel/new-search屏障有效，F-143不扩大核心provider响应错配，G04/G01剩余队列归零 |
| S426 | G02 fresh clean-room重审闭环 | 原G02最终逐号表在上下文压缩后遗失，协调未猜测或转录不完整记忆，改由全新零源码暴露代理从生产/测试/当前上游重审。F-014驳回；F-054/F-065/F-069/F-082/F-086/F-100/F-124/F-127/F-199升P1，F-087/F-121升P2；F-120保留全局既有P1。rawPayload合同收窄为可表示结构/值、typed覆盖与非字节/数字词法保真；G02队列归零 |
| S427 | 完整最终报告生成与本地机械预检 | 从findings最终账本生成246个逐项详情、20项CHK与十类必需内容；摘要/详情/报告状态和P级零冲突，246条七字段完整，开放队列0。报告保持“终检稿”等待两名最终检查代理，不提前宣告完成 |
| S428 | 首轮最终双检未通过并修订 | 覆盖检查发现W020-G/H适用性漏项及W020-C～F阶段态；一致性检查补出旧F等级/未验证措辞、H-011/H-003、CHK-007/008限制及F-153/F-154驳回方向冲突。仅修订五份授权审计文档，未重开或自判技术结论 |
| S429 | 第二轮终检补漏并收口 | 覆盖检查先通过；一致性检查继续发现G06/G09适用性漏项、F-135共享知识旧态、F-215待裁措辞及B006-A历史等待语气。补齐后适用性166/166（140正文＋16集成＋10全局），当前态无候选、待裁或开放措辞 |
| S430 | 最终覆盖与一致性双检通过 | 覆盖代理确认78/78、140/140、16/16、10/10、284/284、246F、20CHK、报告十类内容与I006/I016永久披露全部一致；文档一致性代理确认166/166适用性、驳回/合并靶点和当前态零阻断。最终报告转为“最终” |
| S431 | P1最终处置与当前合同校准 | 主代理重新核对完整P1台账、当前TV实现及目标v2.15.1 Web/后端合同：历史确认P1共44项，30项已修复/完成范围内对齐、10项用户明确跳过、4项重分类，待裁0。F-069降为未来兼容P3并落实CHK-003；F-076跨owner链闭合、余项P2；F-100由`0cfeb12`修复；F-193跨profile链由`90b40b4`修复、余项P2。两条聚焦回归于2026-08-11通过；仅同步审计/清单文档，未改产品代码、未提交 |
| S432 | 审计后用户补充兼容修复登记 | 内嵌职员来源/头像、AniList详情演员与推荐、TMDB识别 provider 固定已由 `40adb42`、`d2972b3` 落实；新增回归与兼容契约测试，tvOS Simulator clean build及串行本地测试525项通过、16项跳过；真实后端因缺少`.env.compatibility`未运行。仅更新本审计目录文档，刻意不纳入代码提交 |
| S433 | F-227人物详情闪烁修复登记 | `PersonDetailViewModel`按字段合并稀疏详情，保留seed身份与已有展示字段，并优先复用seed头像/图片；新增稀疏详情及头像地址变化回归测试，tvOS Simulator Debug clean build及全量串行测试527项执行、16项跳过、0失败 |
| S434 | F-230旧系统辅助字号处置 | 用户确认tvOS 26.0–26.3已属过时版本，决定跳过旧兼容分支的固定字体/高度修复；保留历史P2结论，但不再列为待处理项 |
| S435 | F-032兼容修复登记 | 当前 MP 官方标题/精确搜索普通与流式链路均创建 MetaInfo；TV `TorrentCard` 已按 Web 对齐为 torrent-only 降级渲染，标题回退 `torrent.title`；依赖解析、tvOS Simulator Debug 构建及串行测试通过 |

## 9. 错误与重试

| 时间/批次 | 单元 | 错误 | 次数 | 处理 |
| --- | --- | --- | ---: | --- |
| S1 | M001-A | 首个主审代理在形成最终结构化结果前耗尽上下文 | 1 | 丢弃未闭合中间结论，改用全新窄上下文代理从头重审 |
| S5 | B003 | 首个独立复核代理在最终返回前耗尽上下文 | 1 | 不采纳未闭合裁决；新代理从头复核，并独立检查 Paginator ImagePrefetcher 入口 |
| S9 | B005 | 复用代理先补 F-032 后在 JobRegistry 最终结果前耗尽上下文 | 1 | 丢弃未形成的 B005 结论，改由 review_b006_a 从头主审 |
| S394 | findings等级同步 | 补丁中的严重度行上下文过短，误改F-001/F-078/F-101/F-156并留下8处摘要/详情不一致 | 1 | 立即由全量一致性脚本定位，按F标题精确恢复并归零；后续等级补丁必须把heading纳入同一hunk，未保留错误状态 |
| S11 | B006-B | 复用代理在国家地区分段最终结果前耗尽上下文 | 1 | 丢弃未形成结论，等待另一代理从头主审 |
| S10 | B006-A | 首个独立复核代理在最终报告前耗尽上下文 | 1 | 丢弃未闭合裁决，改用全新窄上下文代理复核 |
| S17 | S002 | 首个复用主审代理在最终报告前耗尽上下文 | 1 | 丢弃未闭合结论，改用全新窄上下文代理从头主审 |
| S25 | M001-F | 独立复核代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，改用全新窄上下文代理从头复核 |
| S25 | M001-G | 独立复核代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，改用全新窄上下文代理从头复核 |
| S25 | M001-H | 主审代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，改用全新窄上下文代理从头主审 |
| S34 | M001-K | 主审代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，改用全新窄上下文代理从头主审 |
| S40 | A001-C | 四个复用代理先后在最终报告前耗尽上下文 | 4 | 丢弃全部未闭合内容，继续切换到早期单文件复核线程从头主审 |
| S43 | A001-C | 全新窄上下文代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，重新创建全新代理从头主审 |
| S43 | A001-D | 主审代理在最终报告前服务连接中断 | 1 | 丢弃未闭合内容，重新创建全新代理从头主审 |
| S55 | 主协调文档更新 | 首次合并补丁引用了不存在的 checklist A001-J 既有行，第二次引用了不精确的工作树漂移行 | 2 | 两次均整体未应用；改为按文件使用当前精确锚点的小补丁 |
| S62 | 主协调文档更新 | 首次组合补丁在执行前出现 JavaScript 字符串语法错误；第二次 raw template 保留反斜杠导致锚点不匹配 | 2 | 两次均未修改文件；改用普通模板并按 ledger/findings/checklist/ReviewPlan 拆分小补丁成功应用 |
| S64 | 主协调文档更新 | A001-K 首次跨文件补丁及随后清单详情组合补丁均命中已漂移的 CHK-003 详情锚点 | 2 | 两次均整体未应用；先读取精确行，再拆成总表、CHK-003、CHK-005 三个小补丁成功应用 |
| S74 | 主协调文档更新 | V002-D/F-113 首次跨文件组合补丁未命中 checklist V002-A 精确行 | 1 | 整体未应用；读取当前行后改为按文件小补丁 |
| S79 | 主协调文档更新 | V002-D/F-113 第二次跨文件组合补丁引用了 ReviewPlan 尚不存在的 V004-B 预告行 | 1 | 整体未应用；改为分开更新 ledger/findings/checklist/ReviewPlan |
| S189 | C018-B | 独立复核代理在最终报告前远端compact stream断连 | 1 | 丢弃未闭合内容，由同一现有只读代理从头重做完整独立复核 |
| S194 | W001 | 独立复核代理在最终报告前远端stream断连 | 1 | 丢弃未闭合内容，等待同一现有只读代理从头重做完整独立复核 |
| S202/S207/S209 | W003 | 独立复核代理连续三次在最终报告前远端compact stream断连 | 3 | 三次均丢弃未闭合内容，停止原地重试，等待改派给与主审不同的另一现有只读代理从头复核 |
| S213 | W005 | 独立复核代理在最终报告前远端compact stream断连 | 1 | 丢弃未闭合内容，停止复用该失败线程，等待另一现有只读代理从头复核 |
| S254 | W008-E | 独立复核在完成源码结论后意外看到一行本单元审计索引 | 1 | 不以该报告单独关单；保留为辅助，由第三代理在不读审计文档前提下盲审全段 |
| S257 | W008-E | 第三盲审在形成合集主链后误把`.agents`纳入检索并读到多条审计命中 | 1 | 主动声明盲审失效；仅保留污染前形成的机制并提交普通报告，与首份先结论后单行暴露的复核共同作限定证据，候选不升级确认 |
| S365 | 主协调文档更新 | 首次明细等级组合补丁的四个通用锚点误命中F-001/F-067/F-084/F-108 | 1 | 立即通过逐段读取与摘要/明细脚本发现；按finding标题精确恢复四项并更新目标四项，随后完成全量一致性校验，错误状态未作为审计结论保留 |
| S389 | 主协调文档更新 | F-182详情等级补丁的通用严重度锚点误命中F-036 | 1 | 立即由摘要/详情一致性脚本发现；按finding标题精确恢复F-036 P3并更新F-182 P2，错误状态未作为审计结论保留 |
| S403 | I010闭环文档更新 | 首次组合补丁引用错误的F-123标题，整体未应用 | 1 | 读取精确heading后拆分小补丁；无错误状态落盘 |
| S405 | I016双审文档更新 | 首次摘要组合补丁中的F-242措辞与当前精确行不一致，整体未应用 | 1 | 重新读取精确摘要行后拆分小补丁；无错误状态落盘 |
| S414 | G03明细等级同步 | 首次明细补丁用通用状态/严重度锚点，误命中F-069/F-117/F-172/F-240并使目标F-116/F-171/F-174/F-245仍未同步，共产生10处摘要/详情不一致 | 1 | 全量一致性脚本立即定位；按8个finding标题精确恢复并归零，错误状态未作为审计裁决保留 |
| S423 | findings等级锚点修复 | 一次通用严重度补丁在当前目标外短暂改到F-033/F-073/F-101/F-114/F-162等明细并产生10处摘要/详情不一致 | 1 | 立即用全量摘要/详情脚本发现并按heading精确恢复；错误状态未进入任何裁决或最终计数 |
| S424/S425 | clean-room代理污染 | 首批G09/G04窄裁代理读取了ReviewPlan/ledger，违反本轮clean-room替代票边界 | 2 | 两份均不计独立票，只作补充；分别派全新代理仅读生产源码、现有测试和必要上游，从头重审后再落账 |
| S426 | G02最终表恢复 | 上下文压缩后只保留“已交付”状态，原逐号表正文不可恢复 | 1 | 不按编号猜测、也不借旧审计结论重建；派全新clean-room代理完整重审并永久披露替代原因 |
| S427 | 最终报告生成 | 首次从超长findings输出提取详情时单次块过大，只得到221/246项 | 1 | 在写入前由编号计数发现；改用250行分块读取后取得246/246并再做七字段与状态/P级全量核对，未保留不完整报告 |
| S427 | 最终一致性代理派发 | 新建最终文档一致性代理时达到活跃线程上限 | 1 | 复用已完成的G02代理仅做五份文档机械比较；永久披露其既往G02源码暴露，不把本轮作为clean-room技术票 |
