# MoviePilot-TV 全量代码审查计划 (Full Review Plan)

本计划涵盖项目所有 Swift 源码文件。为了在单文件审查模式下保持最佳的上下文连贯性，审查顺序已经过优化：**底层基建优先，上层业务按功能模块（ViewModel -> View 结对）推进。**

## 📅 审查进度表

### 1. 数据模型与核心扩展 (Models & Core Extensions)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/Models/Models.swift` | ✅ 已完成 | 1. ⚠️ **核心规范**: API 请求的媒体标识符**必须**使用 `apiMediaId` 计算属性 (`MediaInfo`/`Subscribe`模型提供)。严禁手动拼接。<br>2. 已提取 `isCollection` 存储属性，后续审查判断合集请直接复用此属性。<br>3. ⚠️ **注意**：`Models` 中的模型既包含 JSON 直接解析的字段，也包含 Swift 内部计算处理的属性。后续审查 AI 在遇到模型字段时，**务必先阅读 `Models` 中 Struct 的具体实施**，避免重复计算或误用。<br>4. ⚠️ **注意**：很多 `id` 字段可能是为了 SwiftUI 渲染稳定而拼接的 UUID。若后续业务逻辑需要使用原始 ID（对应 Vue 端的 ID 使用场景），**必须显式使用 `raw_id`**，绝对不可误用拼接后的 `id` 字段。<br>5. 已提取 `canDirectlySubscribe` 计算属性，用于判断是否可以直接订阅还是分季订阅。后续审查中如需此逻辑，直接复用，严禁自行重新实现。 |
| `MoviePilot-TV/Models/JobRegistry.swift` | ✅ 已完成 | 提供全局常量 `jobTranslationMap` (多语言翻译) 和 `jobPriorityMap` (显示优先级)。 |
| `MoviePilot-TV/Extensions/Formatters.swift` | ✅ 已完成 | 1. 严禁在 View 内实例化 `Formatter` 防掉帧。格式化大小用 `Int64.formattedBytes()`，相对时间用 `String.toRelativeDateString()`。 |

### 2. 服务层 (Service Layer)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/Services/APIService.swift` | ✅ 已完成 | |
| `MoviePilot-TV/Services/KeychainHelper.swift` | ✅ 已完成 | |
| `MoviePilot-TV/Services/Logger.swift` | ✅ 已完成 | 全局静态调用: `Logger.verbose/debug/info/warning/error("message", metadata: ["key": "value"])` |
| `MoviePilot-TV/Services/StaffManager.swift` | ✅ 已完成 | 内部已实现全量去重与排序。后续在处理分页/LoadMore 业务时，ViewModel 直接传入全量合并后的数组即可，无需也**绝不要**在外部手动去重。 |
| `MoviePilot-TV/Services/Paginator.swift` | ✅ 已完成 | ⚠️ **错误状态处理**: 内部遇到异常将直接暴露给 `hasError` 和 `lastError`。如果达到最大连续错误次数则停止加载。**无需也绝不要**在外部 UI 层强行增加“点击重试”逻辑。由 ViewModel 观察并决定是否需要弹出错误 Toast 即可。 |
| `MoviePilot-TV/Services/ParsedSeason.swift` | ✅ 已完成 | |
| `MoviePilot-TV/Services/TranslationHelper.swift` | ✅ 已完成 | |
| `MoviePilot-TV/Services/CustomFilterService.swift` | ⏳ 待开始 | |

| `MoviePilot-TV/Extensions/KingfisherCookies.swift`| ⏳ 待开始 | |

### 3. 全局状态处理器与工具 (Global State & Handlers)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/NotificationManager.swift`| ⏳ 待开始 | 全局 `ObservableObject`。在 `ViewModel` 中调用 `notificationManager.show(message: "Error Message", type: .error)` 来显示错误通知。 |
| `MoviePilot-TV/ViewModels/MediaPreloader.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/MediaActionHandler.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/SubscriptionHandler.swift`| ⏳ 待开始 | |

### 4. 通用基础 UI 组件 (Base UI Components & Modifiers)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/Views/Components/NotificationComponent.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/EmptyDataView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/MediaCard.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/PersonCard.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/MediaGridView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/MediaContextMenu.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/SheetStyles.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/SheetTextField.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/SheetPicker.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/ShelfPicker.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/MediaActionModifier.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/SubscriptionModifier.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/ActionRow.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/MoreCard.swift` | ⏳ 待开始 | |


### 5. 业务模块深度审查 (Feature-based Deep Dive: ViewModel -> View)

#### 5.1 登录模块 (Login)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/LoginViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/LoginView.swift` | ⏳ 待开始 | |

#### 5.2 首页与探索模块 (Home & Explore)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/HomeViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/HomeView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/ExploreViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/ExploreView.swift` | ⏳ 待开始 | |

#### 5.3 发现与推荐模块 (Recommend)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/RecommendViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/RecommendView.swift` | ⏳ 待开始 | |

#### 5.4 搜索模块 (Search)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/SiteFilterViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/SearchViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/SearchView.swift` | ⏳ 待开始 | |

#### 5.5 详情页模块 (Details)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/MediaDetailViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/MediaDetailView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/PersonDetailViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/PersonDetailView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/CollectionDetailViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/CollectionDetailView.swift`| ⏳ 待开始 | |

#### 5.6 资源结果与下载模块 (Resources & Downloads)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/Views/Components/TorrentCard.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/BestResultCard.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Components/TorrentsResultView.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Sheets/MultiSelectionSheet.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/ResourceResultViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/AddDownloadViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/ResourceResultView.swift` | ⏳ 待开始 | |

#### 5.7 订阅模块 (Subscriptions)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Sheets/SubscribeSheet.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Sheets/ForkSubscribeSheet.swift` | ⏳ 待开始 | |


#### 5.8 系统与状态模块 (System & Status)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/StatusViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/StatusView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/SystemViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/SystemView.swift` | ⏳ 待开始 | |

#### 5.9 下载管理模块 (Download Management)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/DownloadTaskView.swift` | ⏳ 待开始 | |

#### 5.10 转移与整理模块 (Transfer & Reorganize)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/ReorganizeViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift`| ⏳ 待开始 | |
| `MoviePilot-TV/Views/Pages/TransferHistoryView.swift`| ⏳ 待开始 | |

### 6. 应用入口与根视图 (App Entry & Root View)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `MoviePilot-TV/ViewModels/ContentViewModel.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/Views/ContentView.swift` | ⏳ 待开始 | |
| `MoviePilot-TV/App/MoviePilot-TVApp.swift` | ⏳ 待开始 | |

## ⚠️ 全局副作用与依赖备注 (Side Effects & Dependencies)

- [ ] ⚠️ **架构差异**: Vue端的分季订阅有两处实现（详情页的轻量实现、分季订阅弹窗的重量级实现）。tvOS端已统一为单一实现（`SubscribeSeasonView`），其功能与Vue的`SubscribeSeasonDialog`对齐。因此，后续所有分季相关的API审查，**仅以 Vue 的 `SubscribeSeasonDialog.vue` 逻辑为准**，忽略 `MediaDetailView.vue` 中的旧实现。
- [ ] ⚠️ **日志规范**: 项目已引入全局 `Logger.swift`，**所有 Log 信息必须使用 `Logger` 等方法输出，严禁直接使用 `print()`**。
- [ ] ⚠️ **通知规范**: 项目已引入全局 `NotificationManager.swift` ，**该通知系统仅用于向用户报告操作失败或需要用户干预的错误状态**。对于操作成功的场景，**严禁**弹出通知，应保持静默，通过 UI 状态的自然变化（如按钮禁用、列表刷新）来提供正反馈。

---
*最后更新时间：2026-05-05*

---

## 从零全量审计：full-review-20260731-042646

> 本区块是独立于上方一期记录的新审计状态。上方所有“已完成”及技术注释只作为历史假设，本轮必须重新阅读、主审和独立复核，不能直接计为完成。

### 启动基线

| 项目 | 结果 |
| --- | --- |
| 启动时间 | 2026-07-31 04:26:46 +08:00 |
| 分支/HEAD | detached HEAD / `4a997919983566ec208e777acf7798a95e2f9e8f` |
| 启动时工作树 | 干净；无已修改或未跟踪生产 Swift |
| 生产范围 | 78 个 Swift 文件，25,280 行；全部位于 `MoviePilot-TV/` 且属于 App target |
| 测试证据范围 | 32 个 Swift 文件，19,814 行；不计作生产审查单元 |
| 旧计划差异 | 原有 74 个路径均有效；新增后未纳入的 4 个文件已补入本轮 |
| 新增后遗漏文件 | `SubscriptionCancelConfirmation.swift`、`AppVersionInfo.swift`、`UserPermissions.swift`、`ManualMediaSearchSheet.swift` |
| 上游可用性 | 启动时规定的同级目录不存在；后续确认 Web `/Users/chantxu/code/MoviePilot-Frontend` HEAD `19710a5f0fe0d795a92de904bacd3193bd8c8432`（tag `v2.13.6`）与后端 `/Users/chantxu/code/MoviePilot` HEAD `a0ee99aacc485259431ce5be10933559f4ceac42`（tag `v2.14.4`）为 clean Git 仓库并用于逐项静态核对；实际部署/运行仍未验证 |
| 详细台账 | `.agents/audits/full-review-20260731-042646/ledger.md` |
| 发现台账 | `.agents/audits/full-review-20260731-042646/findings.md` |
| 最终报告 | `.agents/audits/full-review-20260731-042646/final-report.md` |

两名启动代理独立枚举的 78 条生产路径逐项一致。本轮拆为 140 个正文审查单元；每个单元必须有主审及不同代理独立复核，另有 16 个拆分文件级集成复核。

### 本轮文件级状态表

状态只使用：`待审`、`主审中`、`待复核`、`复核中`、`待回溯`、`已闭环`、`阻塞`。分段文件的精确行区间、代理、发现和回溯关系以本轮 `ledger.md` 为准。

| 生产文件 | 主审 | 独立复核 | 文件级集成 | 回溯 | 最终状态 |
| --- | --- | --- | --- | --- | --- |
| `MoviePilot-TV/App/MoviePilot-TVApp.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Extensions/Formatters.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Extensions/KingfisherCookies.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Extensions/SubscriptionCancelConfirmation.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Models/AppVersionInfo.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Models/JobRegistry.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Models/Models.swift` | 已闭环 | 已闭环 | 已闭环 | 已闭环 | 已闭环 |
| `MoviePilot-TV/Models/UserPermissions.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Services/APIService.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Services/CustomFilterService.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Services/KeychainHelper.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Services/Logger.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Services/Paginator.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Services/ParsedSeason.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Services/StaffManager.swift` | 已闭环 | 已闭环 | — | 已闭环 | 已闭环 |
| `MoviePilot-TV/Services/TranslationHelper.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/AddDownloadViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/CollectionDetailViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/ContentViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/ExploreViewModel.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/HomeViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/LoginViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/MediaActionHandler.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/MediaDetailViewModel.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/MediaPreloader.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/NotificationManager.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/PersonDetailViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/RecommendViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/ReorganizeViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/ResourceResultViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SearchViewModel.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SiteFilterViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/StatusViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SubscriptionHandler.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/ViewModels/SystemViewModel.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Components/ActionRow.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/BestResultCard.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/EmptyDataView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/MediaActionModifier.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/MediaCard.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Components/MediaContextMenu.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/MediaGridView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/MoreCard.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/NotificationComponent.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/PersonCard.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/SheetPicker.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/SheetStyles.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/SheetTextField.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/ShelfPicker.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/SubscriptionModifier.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/TorrentCard.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Components/TorrentsResultView.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/ContentView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/CollectionDetailView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/DownloadTaskView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/ExploreView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/HomeView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/LoginView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/MediaDetailView.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/PersonDetailView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/RecommendView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/ResourceResultView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/SearchView.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/StatusView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/SystemView.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Pages/TransferHistoryView.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/ForkSubscribeSheet.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/ManualMediaSearchSheet.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/MultiSelectionSheet.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift` | 已闭环 | 已闭环 | 已闭环 | — | 已闭环 |
| `MoviePilot-TV/Views/Sheets/SubscribeSheet.swift` | 已闭环 | 已闭环 | — | — | 已闭环 |

### 当前分段状态索引

| 单元 | 状态 | 候选/备注 |
| --- | --- | --- |
| M001-A | 已闭环 | F-006已确认P2且已修复（`49b887e`+`f807692`）；F-007确认P1且已修复（`bb07772`）；F-008确认P2且已修复（`789e9a7`）；F-012按当前七字段合同确认投影缺失/优先级反转P2并已修复（`58c7e81`），canonical-only TMDB group另留未验证P3边界；F-013经当前Web/后端合同反证后驳回，用户决定跳过修复；H-001/H-004 已由 I001 修正闭环 |
| M001-B | 已闭环 | F-001（已确认/P3；跨端输入未验证）；H-003 已由 I001 全文件闭环 |
| M001-C | 已闭环 | F-002/F-003/F-005 已确认，F-003 由 I001 补充负季号边界，F-004 降级 P3；F-011 经当前上游三方复核收窄为条件性 P2并已修复（`63767f9`）；CHK-001 已确认 |
| M001-D | 已闭环 | F-011 收窄为 TorrentInfo 四个官方字段丢失的条件性 P2并已修复（`63767f9`），F-015确认P3并已修复（`f04f73f`），F-014经G02反证后驳回，F-004保持降级、F-013经当前Web/后端合同反证后驳回；CHK-002/003/004 已确认 |
| M001-E | 已闭环 | F-024当前Web/后端合同复核维持条件性P1且用户基于低频边界决定跳过；F-025已按服务器类型+分支标签+长度前缀稳定身份修复（`8050051`），clean build、433/433本地测试及最终独立复审通过；F-021维持P3，F-022/F-023已修复（`af67839`），F-032维持P2 |
| M001-F | 已闭环 | F-065条件P1；F-066/F-067/F-068 P2；当前v2.15.1复核把F-069降为未来版本条件P3并转CHK-003；CHK-007/CHK-008已确认 |
| M001-G | 已闭环 | F-064 已确认条件性 P2且已修复（`af67839`），F-056作为重复项并入F-050后驳回；其余关联发现边界维持，无新增发现 |
| M001-H | 已闭环 | G09交叉裁将F-070升确认P2；F-071维持P2；F-072维持P1且已修复（`e388e8b`），Simulator clean build、本地436/436测试与最终独立复审通过；支持F-001/F-021/F-027/F-036，F-013经当前合同反证后驳回 |
| M001-I | 已闭环 | F-077/F-079 按当前分享schema分别确认投影与Fork身份丢失P2并已修复（`58c7e81`），F-078确认P3；CHK-009已补强，扩展F-002/F-008/F-017/F-027分享链；嵌套分享对象不再计入收窄后的F-011 |
| M001-J | 已闭环 | G09 clean-room窄裁将F-073收窄后转确认P2且已修复（`e8cdaf7`）；F-074 用户按实际操作链复核后决定跳过（预览请求返回即弹 Sheet 抢焦点，同会话编辑窗口过窄，会话切换已有 isSessionUnchanged 防护）；F-075 用户按三端对照裁决仅修误导文案（Web 同样无逐 ID 受理/只重试失败机制且部分失败不刷新列表，后端 force 无幂等，不做 TV 单端增强），文案与回归测试已提交；F-076 资源搜索新请求开始即清空旧结果（`SearchViewModel.autoSearch` `.resource` 分支），聚合搜索子项已由`d361fe4`修复（unified 分支新请求开始清空 bestResults），空关键词点搜索与 Web 一致不改，定向 16/16 通过；F-077 已修复（`58c7e81`）等既有传播不变；扩展F-027下游证据不变 |
| M001-K | 已闭环 | F-080 已修复（`SearchViewModel`/`ResourceResultViewModel` 加 receivedDone 门禁：error 不发布、EOF 无 done 不发布、missingSites 补偿仅 done 后；后端单站点错误由 indexer 层吞掉不影响 done，2026-08-14 三端核对）；F-081 输入边界修复已完成（`670cf86`），验证及独立复审通过，已选规则缺失继续静默不过滤由用户裁为产品取舍；F-085 已修复（`7f9fd17`：matcher 与后端 `__match_rule` 全字段对齐，规则 ID 缺失全排除、非法值显式失败、拉取网络失败放行，独立代理逐项复审+55 项定向测试通过），F-061后续由I011升P2 |
| I001 | 已闭环 | 55 个顶层声明全部覆盖；无新增发现，维持既有裁决；四处仅 doc comment 跨账面边界 |
| A001-A | 已闭环 | G02末裁将F-082升条件P1（已由`d8198fc`修复）；F-083 已修复（2026-08-14：下载动作解码仅空 body 兼容成功，非空响应严格失败关闭并保留 message_i18n）；F-084 已修复（2026-08-14 用户裁决：保留 original→w500 替换，ImageURLs 加 posterFallback 原始 URL，MediaCard/BestResultCard/ForkSubscribeSheet 加载失败自动回退原始 URL）；F-030 已修复（`ee5dcb4`），其余传播闭合 |
| A001-B | 已闭环 | F-019/F-020/F-027/F-062/F-063及G02末裁F-086为条件P1；F-030/F-031/F-026/F-087/F-088 P2，缓存归CHK-007；F-088 已修复（共享 `encodeURIComponent` 原语并保留既有 `percentEncodedQuery`：登录 form body 与 `buildEndpoint`/`relativeBackendEndpoint`/`appendingQuery` 追加参数均按 form 语义编码，`+`→`%2B`、已有 `%2B` 往返不丢、非 ASCII 走 UTF-8，与 Web axios/FormData 字面值到后端解析一致；新增登录 body、搜索 query、`%2B` 往返定向测试，tvOS Simulator 构建通过，相关套件 39/39 通过） |
| A001-C | 已闭环 | G06核当前后端401后F-089 P2；G02末裁将F-087升P2，F-088 P2；F-087 已修复（统一 `trimmedNonEmpty` 选择器：逐项 trim 后按优先级取首个有效文本，覆盖 ApiResponse/非2xx/动作解码/AI重做/SSE 六类入口，空白首选不再遮蔽有效 detail/message）；F-089 已修复（`90b40b4` 候选登录重构闭合：login 401/403 直传服务端错误文本、不再抛 unauthorized/logout，System 手动刷新与 App 更新刷新失败均保留旧会话，`APIServiceSessionTransitionTests`/`SystemSessionBehaviorTests` 相关用例已覆盖），其他会话/响应传播闭合 |
| A001-D | 已闭环 | F-090 已确认条件性 P3；支持 F-005/F-009/F-013/F-027/F-031/F-060/F-064/F-076/F-077/F-078/F-082/F-084/F-086/F-087；F-090 已修复（`recognizeTmdbId` 四个成功出口统一复用 `validNumericIdentifier`，0/负数候选跳过继续查找正 ID，不再遮蔽正候选；`TmdbRecognitionPositiveIDTests` 4 个回归用例通过） |
| A001-E | 已闭环 | W017双审补强后F-024/F-095升P1，F-083/F-092/F-093升P2；后续G05将F-094升P2、F-197升条件P1。F-091维持P2，F-196 P1，扩展F-027/F-192/CHK-005/012；F-091/F-093 已修复（首次下载器列表加载失败后轮询复用 `loadClientsIfNeeded` 自动重试并区分错误/真实空态，成功空列表不再重复请求；clients/downloads 轮询连续失败超过 5 次发一次全局通知并重置、成功清零，暂停/启动/删除动作失败立即通知、成功静默，`DownloadTaskViewModel`/`DownloadTaskView` 实现，定向测试通过）；F-092 已修复（暂停/继续动作发起时冻结目标状态，成功后写目标值不再 toggle，单行 in-flight gate 在请求期间禁用按钮防重复提交，轮询 `onChange` 保持服务端权威同步，`DownloadTaskView` 实现，源码断言回归测试通过）；F-094 用户按三端对照裁决跳过（Web `DownloadingCard.vue` 同样不校验/不编码 hash，后端 `/download/{hashString}` 单段路由天然挡 `/` 与空段，`?`/`#` 截断 Web/TV 均存在，不做 TV 单端增强） |
| A001-F | 已闭环 | G09两票将F-098逐ID terminal receipt升P1、F-099正ID边界升P2；其余支持 F-027/F-033/F-036/F-060/F-071…F-076/F-080/F-082/F-086/F-087；F-099 已修复（手动选择原生数值 ID 先过正数过滤、无效回退 `media_id`；手工校验仅接受正数数字，0/000/负值无效；`MediaInfoCollectionBehaviorTests`/`ReorganizeViewModelTests` 更新并新增回归，定向与相关套件通过） |
| A001-G | 已闭环 | F-096 P2；后续G03窄第三裁将F-097升P2；支持F-001/F-023/F-025/F-027/F-060/F-082/F-086/F-087；F-096 用户裁决跳过（TV 自动重登为既定行为；`90b40b4` 会话重构后可选探测 401/403 仅触发自动重登、重登成功不重放原请求，重登失败登出与主请求同一路径，凭据失效时迟早发生，非探测额外误伤）；F-097 已修复（轮询结果区分成功与失败：失败/取消保留该服务器上一轮快照、只有成功空才清空，停用服务器随新列表移除，对齐 Web `MediaServerLatest.vue` 失败保留旧数据语义；`HomeViewModelMediaServerSnapshotTests` 新增 5 个回归用例覆盖失败/网络错误/取消/成功空/首次失败，定向与相关套件通过） |
| A001-H | 已闭环 | F-101 P3、F-103 P2确认；G05/G09按当前producer安全把F-102转未验证P3；CHK-011维持修订，传播边界补F-004/F-011/F-013 |
| A001-I | 已闭环 | F-104 已确认条件性 P2；相邻只并入 A001-D Douban recommendations，similar 与数字型 TMDB/Bangumi 分支不计已确认传播；无新增 finding |
| A001-J | 已闭环 | F-100条件P1已由`0cfeb12`按每key revision修复；F-069经当前v2.15.1合同复核降为未来版本条件P3并转CHK-003；CHK-010已确认，F-006范围收窄为模型负数与lookup非正数两路径 |
| A001-K | 已闭环 | F-105(P3)/F-106 已确认；I003双审补settings跨会话混合/吞取消并将F-106升P2，图片wrapper仍收窄为生产消费、冷启动/同会话热刷新，切服旧视图树未验证；CHK-003/CHK-005 已补强 |
| V001 | 已闭环 | 主审与独立复核已闭环；G08第三裁曾将F-107升P1，后续`90b40b4`修复主触发，剩余晚到show降P2且用户决定跳过；F-108维持未验证、条件性P3；H-012已确认，F-049升级P2，F-091/F-093仍须按错误episode避免轮询重复常驻通知 |
| B004 | 已闭环 | F-027/F-029已由`90b40b4`修复；F-028经当前三方合同复核后由用户裁为已驳回；F-030已按当前Web嵌套`permissions.features`合同修复（`ee5dcb4`），clean build、435/435本地测试及独立复审通过；F-031经当前三端合同复核降为条件性P3并由用户决定跳过；CHK-005继续承载重登requiredPermission、根状态与多阶段operation owner |
| B001 | 已闭环 | F-009/F-010 已确认 P3，已由 `4c69ec9` 合并修复；正式清单版本声明保持，无新增建议 |
| B002 | 已闭环 | F-016 驳回、F-017 未验证 P3，用户均决定跳过修复；F-018确认P3并已修复（`94f18f2`），F-021确认P3并已修复（`a0adaab`）；H-007 已修正 |
| B003 | 已闭环 | G06后F-019/F-020为条件P1、F-026为P2；Cookie/cache/in-flight三层边界闭合，订阅清单不适用 |
| S004 | 已闭环 | F-026/F-032/F-033/F-034/F-035/F-036/F-039均P2；G04 clean-room末裁将F-035/F-039收窄为owner/session取消并闭环 |
| S005 | 已闭环 | 主审与独立复核已闭环；F-060/F-061/F-081 维持，F-085 已修复（`7f9fd17`），F-017 未验证；下游F-110后经C018/W011确认并由G05升P2 |
| V002-A | 已闭环 | 主审/独立/G06闭合；F-109/F-111均P2，四类profile key、credential/currentUser身份分裂与迁移边界已登记 |
| V002-B | 已闭环 | 主审/独立/G06闭合；F-109/F-111均P2且根因/验收独立，既有会话/Keychain/规则发现传播完成 |
| V002-C | 已闭环 | 主审、独立复核与I016后裁已闭环；F-112确认P2，权威空、首次伪空、后续无stale/error标记及Search/详情继续发送旧ID的传播已闭合 |
| V002-D | 已闭环 | 主审与独立复核已闭环；F-113 确认条件性 P2，成功/错误/取消/撤权、三个调用者及 CHK-005 边界已闭合 |
| V003 | 已闭环 | 主审与独立复核已闭环；F-114 确认 P3 并收窄为父 UI 文案新鲜度，F-112 两条请求传播维持 |
| V004-A | 已闭环 | 主审与独立复核已闭环；I005补强后F-115升P2、F-117维持P3；后续G03纠偏以两张正确映射票将F-116升级确认P2，实际闪烁时长/焦点仍待运行；F-100传播闭合 |
| V004-B | 已闭环 | 主审与独立复核已闭环；F-119最终P2；后续G03窄第三裁确认F-118 ownerless pin根因P2，push/Tab/State端到端时序仍待运行 |
| V005 | 已闭环 | 主审与独立复核已闭环；F-122 确认 P3并收窄最终 error/cancel 误报，F-123 确认条件性 P2且独立于 F-027/F-113，既有传播维持 |
| V006 | 已闭环 | F-120后续按触发与跨端后果降P2且用户决定跳过；G02末裁将F-121升P2、F-124升条件P1；F-124已由`4a1a291`修复并通过聚焦5/5、完整本地450/450与独立复审；既有传播完成；F-079后经当前官方schema裁决确认P2 |
| V007 | 已闭环 | 主审/独立/G06闭合；无新增finding，F-027获login acquisition/ABA补强，F-089按当前后端401转确认P2，F-029无本入口新增触发、F-123仅传播 |
| V008 | 已闭环 | 主审、独立与后裁已闭环；F-125/F-128确认P3、F-126确认P2；F-127确认条件性P1后由用户决定跳过；11项既有finding与F-027/F-028/CHK-005传播完成；版本特定tag不冒充当前远端 |
| V009-A | 已闭环 | 主审、独立与G05后裁已闭环；F-133/F-134保持未验证P3，F-135以当前空目录生产链确认P3；F-088条件扩展与既有传播已收窄 |
| V009-B | 已闭环 | 主审与独立复核已闭环；ExploreContent为死代码；后续G01/G04双票将F-129升P2且保持独立于F-036，既有传播维持 |
| V009-C | 已闭环 | 主审与独立复核已闭环；后续G04双票将F-130升P1并吸收F-244子Paginator跨profile发布；`90b40b4`以统一session UI identity、runtime取消与缓存失效闭合，当前聚焦96/96通过，既有独立复审PASS |
| V009-D | 已闭环 | 主审与独立复核已闭环；后续G05将F-131升条件P2，F-132维持P3，21组筛选集合其余完整性通过 |
| V009-E | 已闭环 | 主审与独立复核已闭环；F-129/F-131/F-132 维持确认，F-134 无部署复合 fixture、F-136 无 TV 产品意图，均转未验证；F-088 扩展维持 |
| V009-F | 已闭环 | 主审与独立复核已闭环；无新编号，F-129/F-130 与 F-132 共有值扩展确认，传播会话/分页/分享/响应/query 发现；F-133/F-134/F-136 未验证，F-135 已确认 P3 |
| V010 | 已闭环 | 主审与独立复核已闭环；后续G01/G04双票将F-138升条件P1、F-139升P2；推荐分页/session/身份/图片/动作传播不变 |
| V011-A | 已闭环 | G04 clean-room末裁将F-137升条件P2；枚举/wrapper身份其余通过，权限翻转/focus归V011-C/I007 |
| V011-B | 已闭环 | 主审与独立复核已闭环；F-140/F-141 确认 P3，F-137 维持确认并补强 F-138；有限排序/去重/top-12 其余通过 |
| V011-C | 已闭环 | G04末裁将F-035/F-039升P2并明确显式cancel/new-search屏障有效；权限热切换并入F-130/CHK-005，页面离场语义保留运行验收 |
| V011-D | 已闭环 | 主审与独立复核已闭环；无新编号，F-036 最终 Person.id 去重确认，F-138 title-only核心确认、collection_id机制成立但生产输入未验证；其余传播闭合 |
| V011-E | 已闭环 | 主审与独立复核已闭环；无新编号，自定义规则 fail-open/坏配置并入 F-081/F-085，响应/profile/session 既有传播闭合 |
| V011-F | 已闭环 | 主审、独立复核与第三代理裁决均完成；F-142 确认为条件性 P2，完成 task handle 重放在扫描上限前制造非终止空批；F-034/F-039 保持独立 |
| V012-A | 已闭环 | 主审与 review_a001_j 独立复核完成；F-100/F-130/F-139详情扩展成立，F-138仅task/season/lifecycle alias成立，wrong fullDetail注入因有效ID guard收窄为未验证；后续G03将F-116/F-118均收敛确认P2并保留各自运行边界 |
| V012-B | 已闭环 | verify_a001_h 主审与 review_a001_h 独立复核完成；无新编号，确认 F-006/F-007/F-015/F-027/F-047…F-049/F-068/F-082/F-090/F-100/F-119/F-120 与 CHK-005/006/008/010；F-008/F-054 本段不复现 |
| V012-C | 已闭环 | 主审与 review_a001_j 独立复核完成；无新编号，F-047/F-048/CHK-006确认，补 AniList fallback漏计及电影入口/电视剧统计/测试入口三重错位；失败开放与执行重查未冻结维持 |
| V013 | 已闭环 | F-143 P2；F-144按吞取消晚启动后果维持P2，单纯串行性能为P3子边界；G04/G02 clean-room复核收口，其余传播闭合 |
| V014 | 已闭环 | 主审与 verify_a001_h 独立复核完成；无新编号，F-027/F-033/F-035/F-082/CHK-005直接适用，F-138 identity/inert-task与F-139成功空扩展成立；SwiftUI旧StateObject、wrong-fullDetail及part父ID误路由维持未验证 |
| V015 | 已闭环 | 主审与 verify_a001_h 独立复核完成；无新编号，F-022/F-032/F-061/F-076/F-080/F-081/F-082/F-085/F-101/F-103/F-027/F-123/F-130及CHK-005/011闭合；补偿重复ID仅留未验证合并验收 |
| V016 | 已闭环 | 主审与 review_a001_h 独立复核完成；后续G05将F-145升P2，确认选中下载器后同一Sheet不能恢复初始省略状态；其余既有传播维持，F-135条件链不升级 |
| V017 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；W013-B再次双审后F-146升级条件性P1，后由`0cfeb12`以剧集组+revision+session latest-owner修复；当前本地451/451测试通过 |
| V018 | 已闭环 | review_a001_j主审、verify_a001_h独立复核完成；W014补强后F-147/F-148均确认条件性P1；F-147的Subscribe竞跑已由`a872737`修复，F-147的整理Sheet提交中关闭P2已由`2ce68f8`修复；F-148 用户裁决跳过（created/owner/session 回滚收据主体已由`c61412a`/`a872737`修复，剩余 reused ID 误暂停/删除仅剩"查重一次网络往返"的 TOCTOU 窗口，本地查重与 POST 间无异步间隔，用户接受该残余风险，不做 TV 单端增强） |
| V019 | 已闭环 | 双审完成；G09两票按同权限跨session发布将F-149升P1，F-150维持P2，F-070由未知能力入口升确认P2；混合运维快照与伪空卡边界不变；F-149 已修复（`StatusViewModel.refreshAllData` 三个请求 `async let` 并发、收齐后校验同一 session 与 superuser 权限再一次性发布，分项失败整组保留上一完整快照不形成混合快照；修复随 `90b40b4` 会话重构落地，新增 `StatusDashboardSnapshotTests` 3 个回归用例覆盖分项失败保留快照/首载分项失败不发布/session 变化不发布，定向与相关套件 19/19 通过）；F-150 已修复（`StatusView` 非 superuser 时整组隐藏媒体库统计/存储空间/下载器三张 Dashboard 卡与顶部 Divider，保留下半部下载任务与整理历史；对齐 Web 非 superuser 不进入 `/dashboard` 的展示边界；`StatusViewModel` 暴露 `canRequestSuperUserEndpoints`，`StatusDashboardSnapshotTests` 新增 manage-only 用例断言不发请求且三项为空，定向与相关套件 20/20 通过） |
| V020 | 已闭环 | 原双审完成；W017页面双审补强F-024/F-083/F-092/F-093/F-095严重度并新增F-196/F-197，F-091/F-094/F-027/F-060/F-082与CHK-005/012传播；F-033/F-035/F-120仍有不适用反证 |
| V021 | 已闭环 | 双审与G09 clean-room窄裁完成；F-151条件P1，当前官方Web v2共享同一行为，用户决定按Web对齐跳过TV单端修复；F-120后续因Web同样允许preview/transfer交叉且未证明错目标mutation，降P2并由用户决定跳过；F-099/F-073 P2，F-074/F-075/F-076及既有session/cache传播闭合 |
| V022-A | 已闭环 | 分段双审与I009整文件复核完成；F-071升P2，F-072/F-033等传播闭合，坏单行/total/duplicate-only维持未验证 |
| V022-B | 已闭环 | 分段双审、I009与G09复核完成；F-152已由`fc0cefa`冻结完整对象并由ViewModel持有批删任务，定向1/1、整组10/10及本地458/458通过，补齐测试覆盖后同一独立复审者PASS；F-153经G09两票驳回为独立缺陷并仅留P3测试边界 |
| V022-C | 已闭环 | 分段双审、I009与G09复核完成；F-154经G09两票驳回并归F-232稳定排序测试，F-155/F-232维持P2；F-204历史裁决维持条件P1，TV修复已由`81d42fb`提交 |
| V022-D | 已闭环 | 分段双审、I009与G09复核完成；F-098/F-156升条件P1，F-070升P2；F-080/F-075/F-203等terminal/session/partial outcome传播闭合 |
| V023 | 已闭环 | 主审、独立与G06完成；F-157按不可恢复错误终态升P2，失败/取消占用检查key后同key成功被guard吞且前台固定不判定；其余会话传播闭合 |
| C001 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；后续G05把P2稳定后果收窄锚定到DownloadTask主行空Button，F-158升P2；其余透明sink真实落焦/VoiceOver频率仍留运行验证 |
| C002 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；F-159确认P3：5文件6处生产show均无主动announcement，同文案事件不能靠值变化监听；F-107独立、F-108仍未验证 |
| C003 | 已闭环 | 双审、G10与G09复核完成；F-160确认P2，F-161按静态透明Button/focus绑定升条件P2，实际Focus Engine/VoiceOver频率仍未验证；F-156传播随G09升条件P1 |
| C004 | 已闭环 | 双审与G10/G09复核完成；F-162/F-165升P2，F-163/F-164维持未验证条件性P3；F-165只陈述内容内退出/辅助可发现性，不声称无法退出 |
| C005 | 已闭环 | verify_a001_h 主审、review_a001_h 独立复核及verify_a001_h补充裁决完成；F-166驳回，F-167收敛为未验证P3：托管根transform契约违反确定、可见故障未验证 |
| C006 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；后续G05按丢title/结构化selected语义将F-168升P2；季100初始焦点与VoiceOver/checkmark播报仍未验证 |
| C007 | 已闭环 | review_a001_j 主审、verify_a001_h 独立复核完成；F-169确认P3，视觉overlay与焦点重定向不会生成持久选择语义；F-033/F-139传播闭合 |
| C008 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；W014双审补强当前后端默认站点回退/规则fail-open后F-170升级确认P2；修复须只让用户主动清域外值 |
| C009-A | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；后续G03两张正确映射票将F-171升P2，Canvas五类持久业务状态无替代；标题/页面上下文只限制影响，整卡owner交B |
| C009-B | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；F-172确认P3，F-173收敛未验证性能P3且限processed-cache冷缺失等路径；整卡语义并入F-171 |
| C009-C | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；后续G03两张正确映射票将F-174升P2，全仓单写/读/清静态槽无目标owner，A编辑→B无源详情冷Loading错误飞入链闭合 |
| C010 | 已闭环 | F-175 P2，G04末裁将F-176升P2；F-177收敛未验证性能P3，人物route/图片/预取/身份传播闭合 |
| C011 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-175/F-173/F-003传播确认，10/11季显示、SubscribeSeasonRequest三字段与四根导航destination通过 |
| C012 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；F-178确认条件性P3：评分备用名与卡片展示名分裂；F-076/F-172/F-174/F-177传播闭合，固定高度仅留运行盲点 |
| C013 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；无新编号，ID-only Equatable/旧items闭包在四owner缺原位替换且Paginator当前门槛兜底，既有分页/图片/身份/可访问性/转场传播闭合 |
| C014 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；无新编号，8生产入口与既有finding传播闭合；取消动作词/destructive补入F-124/CHK-006，无Fork presenter页仅留payload契约未验证 |
| C015 | 已闭环 | verify_a001_h 主审、review_a001_h 独立复核完成；无新编号，ContentView唯一根presenter、4入口与F-090/F-122/F-123/CHK-005传播闭合，overlay focus/accessibility仅留运行盲点 |
| C016 | 已闭环 | verify_a001_h 主审、review_a001_h 独立复核完成；无新编号，6个Handler/presenter、8入口与既有订阅/Fork/缓存/通知/Sheet传播闭合；F-048不适用直取消，F-049仍传播至Sheet回滚 |
| C017 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；后续G05将资源卡/筛选空白字符串分裂F-179升条件P2；促销badge仅留契约盲点，既有资源/解析/控制语义传播闭合 |
| C018-A | 已闭环 | review_a001_j 主审、review_a001_h 独立复核完成；无新编号，F-022/F-032/F-057/F-058/F-059/F-061/F-110/F-158传播闭合，onAppear首帧与同ID变化仅留盲点 |
| C018-B | 已闭环 | review_a001_j 主审、review_a001_h 独立复核及verify_a001_h第三裁决完成；无新编号，F-110确认、F-061根在A段；Swift自5.8文档化stable且项目设6.0，相等项保序，CI精确Xcode小版本未锁 |
| C018-C | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-110/F-057…F-059/F-179/F-168/F-170传播闭合，F-061根在A段，F-163/F-165有反证 |
| W001 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-076/F-099/F-178/F-172/F-158/F-165传播闭合，F-177未验证，AddDownload media_in分工仅留契约边界 |
| W002 | 已闭环 | review_a001_j 主审、review_a001_h 独立复核及G06后裁完成；无新编号，F-086/F-088/F-107/F-027/F-062/F-063/F-159传播闭合，F-029本View无新增触发、F-089最终确认P2，no-access首次登录顺序通过 |
| W003 | 已闭环 | review_a001_h 主审、review_a001_j 独立复核及遗漏项补裁决完成；无新编号，Home订阅/媒体库/TMDB资源/session通知/卡片既有传播闭合；后续G03确认F-118 P2，F-012/F-017边界不变，F-158不适用；当前全文件486行覆盖原范围，前三次失败输出均作废 |
| W004 | 已闭环 | verify_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-077/F-078/F-120/F-121/F-129…F-132/F-033/F-035/F-105/F-106/F-027/CHK-005传播闭合；F-133/F-134/F-136未验证，F-135已确认P3，F-039/F-158不适用 |
| W005 | 已闭环 | review_a001_j 主审、review_a001_h 独立复核完成；无新编号，推荐货架/空态、身份、分页恢复、生命周期session、订阅动作、卡片图片与可访问性既有finding传播闭合；F-079后经当前官方schema裁决确认P2，F-173及Fork presenter/合集route维持未验证，F-158不适用 |
| W006-A | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-130/CHK-005/F-142/F-039/F-076/F-114/F-121/F-027/F-137/F-140/F-141/F-112/F-168传播闭合，键盘提交按显式双模式按钮契约不立项，F-169不适用 |
| W006-B | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；无新编号，F-033/F-034/F-035/F-036/F-039/F-076/F-027/F-130/CHK-005/F-137/F-138/F-140/F-141/F-142/F-077/F-079/CHK-009/F-104/F-143/F-178传播闭合，F-064维持未验证，F-139/F-158不适用 |
| W006-C | 已闭环 | review_a001_j 主审、review_a001_h 独立复核完成；无新编号，分页会话、媒体/人物/分享身份、菜单订阅、人物展示导航、卡片可访问性与图片链既有finding传播闭合，F-079后经当前官方schema裁决确认P2；F-064/F-173/F-177维持未验证，F-158/F-176不适用 |
| W006-D | 已闭环 | review_a001_h 主审、review_a001_j 独立复核完成；无新编号，排名/身份/展示/类型图片、分享人物导航、会话预加载、sourceFrame与菜单既有finding传播闭合，F-064/F-177及双FocusState/VoiceOver/性能维持未验证，F-171/F-173/F-175不适用 |
| W007 | 已闭环 | 分段三方与I013最终第三裁完成；F-180升条件性P2；后续G03两票以确定的cache-hit揭示顺序将F-116升级确认P2，实际闪烁时长/焦点仍待运行；其余传播闭合 |
| W008-A | 已闭环 | 分段三方与I013最终第三裁完成；F-181保持未验证但条件后果校准为P2：Hero先false/Content后true静态缺口成立，真实tvOS事件顺序须Simulator/真机验证；既有状态/session/lifecycle传播闭合 |
| W008-B | 已闭环 | 分段双审及I008/I013回溯完成；F-182升P2，旧false/空分季无法发现远端新建订阅；F-007/F-047…F-049/F-130及Header/session传播闭合 |
| W008-C | 已闭环 | 分段三方及I013回溯完成；F-183维持未验证P3，新增F-231确认P2承载TMDB异步动作离开route后晚到；Hero/投影/图片转场等传播闭合 |
| W008-D | 已闭环 | 分段双审及I013回溯完成；无新编号，分季、剧集组、人物身份导航、分页、图片与卡片finding/CHK传播闭合；onSeasonTap/initialSeason仅为死链清理项 |
| W008-E | 已闭环 | 三代理链与I013最终第三裁完成；F-184对合法正数合集升条件性P1，后由`e0f1122`统一四根导航和所有来源预载门禁并通过487/487测试及独立复审；0/负数/parts仍未验证；后续G03将F-116升确认P2，F-033整体P2（本段局部后果较低）、F-231 P2等传播拆分不变，程序限制污染永久披露 |
| W009 | 已闭环 | review_a001_h主审、review_a001_j独立复核与verify_a001_h第三裁决完成；F-185确认P2：足够长合法biography在无ScrollView/分页/可移动焦点锚点的“完整简介”模态Sheet中必有不可达尾部。加载/无简介空action Button及空作品focusable Text并入F-158同根传播；人物详情失败并入F-126，F-143/F-144等传播闭合，F-176不适用 |
| W010 | 已闭环 | 主审、独立复核与verify_a001_h第三裁决完成；无新编号。`collection_id`存在即合集身份的route/value域问题并入F-184：0令TV/Web分路但无生产payload，负数双方共同缺gate，当前后端不主动给子项注入父ID且原始part字段未知。首屏错误/无重试归F-033、离页不取消归F-035、稀疏身份归F-138、预取Cookie归F-026等传播；首次body短暂空态未获第二票。第三裁决既往collection_id暴露永久披露 |
| W011 | 已闭环 | 主审、独立复核与verify_a001_h第三裁决完成；后续G05将F-110升P2，F-186/F-187维持P2。筛选零项焦点归F-158（后续G05 P2）、missingSites归F-080、null因子解码归F-022，AddDownload生命周期/session归F-147/F-027，其余传播闭合 |
| W012 | 已闭环 | 主审、独立复核与G09完成；F-188/F-189在当时后端v2.14.4快照按条件性错媒体mutation升P1，后续核对确认目标v2.15.1已包含2026-07-21的`3b709b7`统一身份合同，故两项对目标版本按旧基线误报驳回、不改TV。F-135维持确认P3；其余传播边界不变 |
| W013-A | 已闭环 | 主审、独立复核与review_a001_j第三裁决完成；无新编号。季卡主操作由测试锁定直订/取消，onSeasonTap/initialSeason无生产消费，仅死链清理。Tab保留NavigationStack时取消后hasLoaded锁死同owner重载扩展F-126并升级P2，吞取消晚启动扩展F-144；跨服缓存归F-065，非电影二分归F-015，包装其余通过 |
| W013-B | 已闭环 | 双审与W014交叉裁决完成；F-146确认条件性P1；F-047当前复核已撤销“非TMDB跨季删除”，剩余同季多group/多owner范围与Web行为一致，用户决定跳过；临时订阅退出/Retry及`exist_ok`复用既有ID后误暂停/删除统一并入F-148 created/owner/session receipt根因并确认条件性P1。group default恢复及owner/session/卡片传播闭合 |
| W013-C | 已闭环 | 主审、独立复核与review_a001_j第三裁决完成；长overview并入F-185，S00与空白name/date/overview登记F-190确认P3，width-only海报四态无法维持360×540登记F-191确认P3。无写操作owner；可访问关闭及实际海报形态维持运行盲点；两位复核代理既往源码暴露永久披露 |
| W014 | 已闭环 | F-147 Subscribe子项已由`a872737`修复；F-148条件P1已后续处置，F-199已由`ce7afcc`修复，F-170/F-195/F-200 P2；F-069经当前合同复核不再是现行缺陷并转CHK-003，CHK-013/014已确认，advanced a11y未验证 |
| W015 | 已闭环 | 双审与G06完成；F-193跨服同号ID的原条件P1链已由`90b40b4`闭合，当前仅剩同profile operation/presentation竞争P2；F-194 P2，F-027 P1/CHK-005及F-008/F-121/F-185/F-191传播闭合；F-164维持运行未验证 |
| W016 | 已闭环 | 双审、第三裁与G09完成，W017下载子链既往暴露已披露；F-149升P1，F-150维持P2，F-198升P2；F-192按用户确认范围由`b304b58`完成Web同款展示过滤，后端对象级授权风险明确留存范围外；Transfer转W019 |
| W017 | 已闭环 | 双审及清单复核完成；F-024/F-095 P1，F-083/F-092/F-093 P2；F-197经G05升条件P1后由用户决定跳过TV单端修复，CHK-016已落实到正式清单等待官方更新对齐。F-196由`e47693a`明确TV永久删除文案；F-192由`b304b58`对齐Web；其余CHK传播闭合 |
| W018-A | 已闭环 | 双审与G09完成且既往外围暴露已披露；F-188/F-189旧v2.14.4快照裁决后经目标v2.15.1复核驳回（已含`3b709b7`）；F-156升条件P1，F-147整体为条件P1（本段只补P2子后果）；F-206维持P2，F-075/F-074/F-162/F-168确认、F-163未验证、F-166驳回 |
| W018-B | 已闭环 | 双审与G09完成且既往源码/ledger暴露永久披露；clean-room窄裁将F-073收窄为data/item缺失fail-open并确认P2且已修复（`e8cdaf7`），F-151 P1且用户按当前官方Web v2对齐决定跳过，F-162/F-165 P2，其余intent/logID边界不变 |
| I011 | 已闭环 | 集成及第三裁完成；F-061按默认稳定覆盖后端策略与软过滤承诺升P2，TorrentCard并入F-175且按下载主入口升P2；F-032/F-057…059/F-110/F-168/F-179/F-186传播闭合，同ID更新由I012/F-219裁决 |
| I012 | 已闭环 | F-219驳回；F-076原跨owner P1链闭合、当前余项P2；F-103/F-036/F-035/F-039/F-137 P2；G04 clean-room窄裁全部闭合 |
| I005 | 已闭环 | review_a001_h完成MediaPreloader整文件集成，verify_a001_h定向独立复核；F-221 P2，F-220并入F-115后驳回且F-115升P2；后续I013/G02/G03裁决将F-180/F-118/F-119升P2、F-184升条件P1，F-117维持P3；其余传播校准 |
| I006 | 受限已闭环 | F-233/F-234/F-235/F-236 P2、F-237驳回、F-238未验证P3；G04末裁补F-236当前合同，严格独立文件集成限制不变 |
| G01 | 已闭环 | G06将F-109升P2，G09将F-212升条件P1，G04 clean-room末裁将F-137升P2；F-106/F-240/F-200等既有收口不变，错号意见未落账 |
| G02 | 已闭环 | 原逐号表压缩后遗失，未猜测恢复；全新clean-room代理从生产/测试/当时上游重审。后续当前态复核确认F-054已由`58c7e81`与现行后端合同解决；其余G02裁决维持，rawPayload合同按可表示结构/typed覆盖闭合 |
| G03 | 已闭环 | 三票/窄第三裁完成；F-245独立P2，F-116/F-097/F-118/F-171/F-174/F-221均收敛P2，F-219驳回，F-173/F-177运行未验证；CHK-006当前仅保留同季重复/超管fan-out范围不完整P1，非TMDB跨季子证据已由现行后端反证；CHK-017补Fork；既往源码暴露永久披露 |
| G04 | 已闭环 | 既有错号意见作废；全新clean-room代理逐项确认F-034/F-035/F-039/F-137/F-142/F-143/F-176/F-236均P2。F-035/F-039共享owner取消实现但保留独立回归；未运行验证 |
| G05 | 已闭环 | 主审错号CHK票作废；八项共同升级既已落账。G09进一步把F-102转未验证P3，F-133/F-134/F-238继续未验证，F-135维持P3；六项CHK保持当前精确边界，无新finding、无运行验证 |
| G06 | 已闭环 | F-019/F-062/F-063条件P1；F-193的历史跨profile P1链已由`90b40b4`闭合、余项P2；F-030/F-031/F-084/F-109/F-157/F-089 P2；后续G02末裁把F-087/F-121升P2，F-244并入F-130。既往源码暴露永久披露，未运行验证 |
| G09 | 已闭环 | 两票共同升级既有项、驳回F-153/F-154、转F-102未验证并新增F-246 P1；全新clean-room替代票将F-073收窄后确认P2，并确认F-246须新增CHK-020服务端manage资源授权。首个窄裁因读取ReviewPlan/ledger不计独立票，仅作补充；既往源码暴露永久披露，未运行验证 |
| G08 | 已闭环 | 历史裁决F-107/F-148 P1；后续F-107主触发已由`90b40b4`修复，剩余晚到show降P2且用户决定跳过。F-049/F-121/F-223 P2，F-108未验证P3、F-159 P3；G02末裁覆盖F-121旧P3，H-012仅传播；既往通知源码污染永久披露 |
| G07 | 已闭环 | 三方裁决完成：F-143/F-036/F-227/F-226确认P2，F-228确认P3；F-050合并F-056并维持P3，F-045/F-051/F-055维持P3，F-175维持P2；F-189旧v2.14.4链曾升条件P1，目标v2.15.1复核已驳回并转CHK-019升级边界；F-053当前无生产caller；内嵌人物窄化导演，Paginator另归F-034，最佳结果旧说法驳回，AniList插件/运行辅助功能保持未验证；三代理既往人物/Search源码污染永久披露 |
| G10 | 已闭环 | review_a001_h完成37文件主审，verify_a001_h独立复核23文件/6,270行；F-229确认P3、F-230确认P2，F-120/F-160/F-205升P2；Subscribe/session/Fork/manual-search/长文本分别归F-148/F-027/F-193/F-076/F-185，空Button/反馈/Picker归F-158/F-162/F-168，其余F-092/F-108/F-126/F-130/F-147/F-163/F-164/F-165等传播/运行边界闭合；两代理既往业务Sheet源码污染永久披露 |
| I003 | 已闭环 | APIService 2649/2649行集成及G02末裁完成；F-027/F-065/F-082/F-086 P1，F-100已由`0cfeb12`修复，F-069降为未来兼容P3；F-083/F-087/F-080/F-106 P2；malformed SSE当前fallback不重开 |
| I007 | 已闭环 | review_a001_j完成SearchViewModel 865/865行集成，verify_a001_h定向独立复核；F-225确认P2，F-224机制并入F-137/F-141后驳回重复编号；source/session/错误/扫描/SSE/规则/旧fallback/评分映射闭合，F-219继续驳回 |
| I008 | 已闭环 | review_a001_j完成MediaDetailViewModel全文件集成，review_a001_h定向独立复核；F-007升P1、F-182升P2；后续G03窄第三裁确认F-118 ownerless pin根因P2而保留端到端运行边界，F-047/F-048/F-049/F-130映射不变；两代理既往详情/订阅调用链污染永久披露 |
| I009 | 已闭环 | 整文件集成、定向复核与G09完成；F-098/F-156/F-204/F-203为P1，F-071/F-155/F-205/F-232为P2，F-153/F-154经两票驳回；F-204 TV修复已由`81d42fb`提交，F-027/F-072/F-033/F-080/F-075传播闭合，既往源码污染永久披露 |
| I010 | 已闭环 | review_a001_j整文件集成、verify_a001_h独立复核及review_a001_h第三裁完成；F-020升条件性P1、F-239确认P2；后续G03将F-171/F-174升P2，poster仍留F-123，F-124/F-027/F-026/F-175/F-184传播不变；既往源码暴露永久披露 |
| I013 | 已闭环 | verify_a001_h完成MediaDetailView 1113/1113行集成，review_a001_h定向复核，review_a001_j最终第三裁；F-231 P2、F-184条件P1、F-180 P2、F-181未验证条件P2、F-033根P2/详情局部P3；后续G03将F-116升确认P2；其余映射与既往源码暴露披露不变 |
| I014 | 已闭环 | review_a001_j严格整文件集成、review_a001_h定向独立复核完成；F-012当前P2由订阅导航投影缺失/身份优先级反转支撑，canonical-only TMDB group raw限制改记Web共享且用户路径未验证P3边界；F-243前台availability P2；其余传播不变，既往订阅/媒体调用链暴露永久披露 |
| I004 | 已闭环 | review_a001_j完成SystemViewModel整文件集成并披露全部V002独立复核及SystemView调用链污染；无新编号，手动重登/profile owner、站点规则四态、取消、共享settings与当前source/RSS合同均精确并入既有F/CHK，F-028/F-030不扩展 |
| I015 | 已闭环 | 整文件集成、独立复核与G09完成；F-212原目录复合身份条件P1保留历史裁决，但用户要求仅对齐Web：TV独有100ms延迟已由`a6cc428`修复，path-only共享边界决定跳过TV单端增强；F-213明确电影隐藏剧集字段的历史P1裁决保留，但当前Web共享同一行为，用户决定跳过TV单端修复；F-151同样由用户决定跳过；episode_part公共字段与Auto门控不变，不新增CHK |
| I016 | 受限已闭环 | G01/G06完成等级裁决：F-106 P2、F-240 P2、F-089按当前后端401转确认P2；F-111/F-112 P2、F-208/F-242 P3、F-241未验证P3及其余传播不变。三代理均曾主审W020分段，严格零暴露缺口永久披露 |
| W019 | 已闭环 | 双审、I009/G10/G09回溯完成；F-202 历史嵌套解码修复已完成（`670cf86`），验证及独立复审通过；F-152已由`fc0cefa`让弹窗文案/action共用完整对象快照并由ViewModel持有离页后继续的任务，完整门禁通过且补测后同一独立复审者PASS；F-203升P1后用户决定跳过本地后端修复，F-201/F-205维持P2，F-204历史裁决维持条件P1且TV修复已由`81d42fb`提交，F-232 P2；F-156当前态另行复核，F-153/F-154驳回，F-165/F-185传播闭合 |
| W020-A | 已闭环 | 双审完成且V002下游既往暴露已披露；无新编号，确认F-130/CHK-005常驻System收敛、F-144/F-157、F-109/F-111/F-112及F-126/F-060传播；F-113/F-035/F-029本段不直接，focus/a11y保持运行未验证 |
| W020-B | 已闭环 | 双审完成；F-208确认P3，F-130/CHK-005与F-185传播，F-161维持运行未验证；空白非法route确定，但Back/Menu投递与恢复/Focus结果不作静态保证，本段无手势滑动入口；披露W020-A既往边界及误显W020-C头20行未用于结论 |
| W020-C | 已闭环 | 双审及F-216定向复核完成；F-207确认P3。刷新401/403先logout后局部错误在新Login不可达的机制成立，但F-216重复编号并入扩展后的F-107根错误owner，状态码分类交叉F-089；旧登录/settings/身份/长文本等传播闭合 |
| W020-D | 已闭环 | 三代理完成；F-209“全部”nil→默认子集与F-210错误RSS候选域确认为两条独立P2。F-214机制成立但重复编号并入扩展后的F-109，当前Web本地优先缓存+后端per-user权威已核清；CHK-018/019确认，F-189目标版本已驳回、仅作source合同升级反例 |
| W020-E | 已闭环 | 三代理完成；F-211复合编号驳回：同ID当前B执行符合合同，陈旧A展示归F-126，成功响应缺所选ID静默不过滤归F-081。F-215坏identity并入F-081并促其升条件性P2，合法唯一长同前缀name只留tvOS布局/辅助运行风险；其余传播闭合 |
| W020-F | 已闭环 | 双审完成；无新编号，失权route/focus归F-130/CHK-005，加载/预览归F-126/F-085，初焦清除当前来源/规则归F-168。review_a001_h补充P2 Reduce Motion建议无新增静态后果且与既有票冲突，F-208维持P3；Back/VoiceOver交I016 |
| W020-G | 已闭环 | 三代理完成；F-217确认独立P3：条件Exit modifier在pop离场窗口改变结构身份并重启推荐task，但根StateObject保留、只读GET与无稳定主路径中断不足P2；恒定modifier修复与通用task owner互不替代。window/Menu/Sheet仍交I016运行验证 |
| W020-H | 已闭环 | 双审完成；无新编号。H只处理成功解码且已选中的单条规则，不给F-081数组/缺ID链加权；当前Web正常可达size单值/seeders区间及空白正则可令硬过滤全空或条件静默失效，准确归F-085并由P3升P2；G05回溯已关闭 |
| R001 | 已闭环 | 三代理确认F-218独立条件性P3：已存token时首次同步body先具备构造认证Tab/Home资格；F-106负责会话恢复后必要settings完成前撤门，F-130/CHK-005负责异步owner，三者不可互替。根MediaAction跨logout归F-130/CHK-005；真实认证帧/Home task待运行验证 |
| R002 | 已闭环 | 双审完成且review_a001_j披露R001时仅见第6/11行owner命中；无新编号，App级旧session通知跨logout/排队重排并入F-107，但须保留显式一次性logout原因交接；媒体handler归R001/F-130/CHK-005，Sheet层与VoiceOver归F-108/F-159运行验证，App注入/初始化通过 |
| F-142 裁决 | 已闭环 | review_a001_h 以双 waiter 状态机独立确认：共享 task 先令 apiPage 0→2，TV waiter 再次重放未退休完成 handle 使 2→2 并提前返回空批；条件性 P2 |
| B006-A | 已闭环 | F-037 未验证 P3；F-038 已确认 P3；H-006 本段无违反；B006-C/S006/I002 后续复核均已闭环 |
| B005 | 已闭环 | F-040/F-041/F-044/F-045 已确认 P3；H-006 数据源层成立 |
| B006-B | 已闭环 | F-042 未验证 P3；F-043 已确认 P3；共享空值展示边界但保持语言/国家标准分离 |
| B006-C | 已闭环 | F-040/F-041/F-044/F-046 已确认 P3；无新候选 |
| I002 | 已闭环 | TranslationHelper 全符号与跨段不变量通过；无新候选，H-006 已修正 |
| S001 | 已闭环 | F-060 已降级为 P3；无新增发现；H-008 已修正 |
| S002 | 已闭环 | G06两票将F-062/F-063升条件P1；access-token删除失败复活与多源混合恢复分别用logout tombstone/session revision和同代权威收敛，支持F-027/F-031 |
| S003 | 已闭环 | F-057/F-058/F-059 已确认 P3；F-061 转 G05 后续单元复核；F-018 边界保持 |
| B007 | 已闭环 | F-047/F-048与当前Web共享相同行为，用户决定跳过；F-054已由`58c7e81`身份保留与当前后端精确season合同解决；F-049 P2 |
| S006 | 已闭环 | F-050/F-051/F-052/F-053/F-055 已确认 P3；F-056并入F-050后驳回，G07下游已闭环；H-009 已修正 |

### P1 最终处置复核（2026-08-11）

| 口径 | 数量 | 说明 |
| --- | ---: | --- |
| 历史确认 P1 | 44 | 正式P1区实际43项，加上后续升为条件P1但仍排在P2区的F-030 |
| 已修复或完成授权范围内对齐 | 30 | 包含F-100、F-193原跨profile链等；每项验证与范围见finding详情 |
| 用户明确跳过/接受现状 | 10 | 保留风险与Web对齐边界，不再进入待裁队列 |
| 当前合同/实现复核后重分类 | 4 | F-069、F-076、F-188、F-189 |
| 待裁决 P1 | 0 | P1审查与处置队列已清空；不等于所有历史P1都已修复 |

- F-069：目标v2.15.1的全部公共可写订阅字段均已被TV建模，现成`total_episode`问题又已由F-199修复；降为仅未来版本可触发的P3兼容风险，并入CHK-003。
- F-076：统一session/generation门禁已闭合跨账号/跨owner错误动作链；聚合Search/Resource同会话旧结果/错误残留已由`d361fe4`修复（unified 新搜索开始清空 bestResults，资源分支此前已清空 resourceResults）。
- F-100：`0cfeb12`已用每key revision闭合同键乱序覆盖，定向乱序回归于2026-08-11通过。
- F-193：`90b40b4`已闭合跨账号/切服后用新会话续接旧Fork ID的P1链；同一profile内并发Fork、关闭后迟到呈现与GET-only恢复仍为P2。

### 历史假设重验表

这些条目只是在一期计划中存在的历史知识，不是本轮确认结论。相关单元的主审和复核必须分别验证“仍成立、已失效或需修正”。

| 历史编号 | 假设摘要 | 负责单元 | 状态 |
| --- | --- | --- | --- |
| H-001 | 已修正：统一媒体键端点复用 `identity/apiMediaId`，原生来源端点使用已验证 raw ID | M001-A/M001-D/I001 与相关调用单元 | 已闭环 |
| H-002 | 已失效（过宽）：合集布尔展示复用 `isCollection`，需要实际合集 ID 的导航直接校验 `collection_id` | M001-D 与相关调用单元 | 已闭环 |
| H-003 | 传输字段、raw 保真载荷、规范化包装值与 UI 派生状态分别判断；属性默认值不是缺键解码默认 | M001 全段与 I001 | 已闭环 |
| H-004 | 仅同时声明 UI `id` 与 raw 字段的模型区分二者；`Subscribe.id` 等仍是后端业务 ID | M001 与全部媒体调用单元 | 已闭环 |
| H-005 | 已失效（过宽）：`canDirectlySubscribe` 只表示电影可直订，false 不能推导为电视剧 | M001-D 与订阅/详情入口 | 已闭环 |
| H-006 | 已失效（过宽）：`prioritizedJobs` 是 canonical job/翻译/优先级唯一注册表，所有消费者须共享 canonical key；未知保真且 999，合并状态不存本地化文本 | B005/B006/S006/I002 | 已闭环 |
| H-007 | 已失效（过宽）：View 不直接创建 class Formatter；仅在单位、locale、时区与 nil 语义一致时复用 helper，固定解析器应复用 | B002 与全部 View | 已闭环 |
| H-008 | 已修正：所有生产诊断输出必须经 `Logger`；当前默认 handler 仅 Debug 输出，直接 `print()` 仍是待清理旁路 | S001 与全部生产单元 | 已闭环 |
| H-009 | 已失效（过宽）：StaffManager 只按实际输入以 Person.id 合并；actor 保序、crew 仅排序新增项，调用方须在截断前提供完整可展示候选 | S006/V012/W008 | 已闭环 |
| H-010 | 已失效（过宽）：Paginator 单点持有错误计数、停止与保留列表恢复；调用者须呈现错误并调用统一恢复入口，不复制计数/退避 | S004 与所有分页 ViewModel/View | 已闭环 |
| H-011 | 已失效（过宽）：TV 不需复刻 Web 重型对话框；仅对齐共享后端字段、身份、范围与副作用合同，呈现保持 tvOS 原生交互 | 订阅组 G02 | 已闭环 |
| H-012 | 全局通知只报告失败或需用户干预，成功保持静默 | 通知组 G08 | 已闭环 |

### 本轮已确认共享知识

- `M001-B / F-001`：`FlexibleBool` 是 Bool/String/Int 的共享输入边界，字符串 token 应统一清理空白与换行，调用者只消费规范化后的 `value`，不得分别补丁。
- `M001-B / H-003`：`DiscoverSourceDescriptor.id`、`JSONValue` 查询/取值辅助属性是 Swift 计算值，`FlexibleBool.value`/`FlexibleString.value` 是包装器内部规范化值；I001 已完成 Models 全局闭环。
- `M001-C / H-003`：Codable 模型须区分后端传输字段、往返保真载荷与 Swift 派生属性；属性初始值不是缺键解码默认，后台解码不得读取 MainActor 配置，编码回传不得破坏需原样保留的载荷。
- `B001 / F-009/F-010`：提交 `4c69ec9` 已让后端版本判断复用“支持、过低、无法解析”三态，并要求移除可选 `v` 后的版本核心以数字开头，兼容巡检诊断同步区分无法解析；独立复审、Simulator clean build、14 条聚焦与 389 条非后端兼容测试通过。
- `M001-A / F-006/F-007`：API 媒体身份须复用对应模型的 `identity/apiMediaId`；订阅 lookup DTO 先过滤 raw 0/空值再回退不透明 legacy `mediaid`；F-007 已由 `bb07772` 完整传递 AniList/统一来源/legacy 身份并改为完整详情 TMDB 优先，定向测试、Simulator 构建、381 条非后端兼容测试与独立复审均通过。
- `M001-A / F-008`：缓存失效不等于已发布 UI 状态刷新；提交 `789e9a7` 已让 Home 搜索/状态/重置强刷自身并通知，保存、回滚 DELETE、分季 DELETE 与 Fork 在各自 mutation 最终成功出口恰好通知一次；独立复审、Simulator clean build 与 386 条非后端兼容测试通过。
- `M001-A/M001-I / F-012/F-077/F-079`：提交 `58c7e81` 已让订阅导航仅在 canonical 来源与 ID 成对有效时优先使用，否则按 TMDB/豆瓣/Bangumi/AniList/legacy 回退；分享模型与投影保留 Bangumi、AniList 和统一身份，GET→Fork 不再截断当前 schema 字段。独立复审、Simulator clean build 与显式排除五个后端兼容套件后的 397 条本地测试通过。
- `M001-A/M001-D / F-013/CHK-002`：当前官方Web v2.15.5的`MediaInfo`类型与身份helper均不读取legacy `mediaid`，路由/请求中的同名参数是由结构化身份现场生成；当前后端响应schema也不产生仅legacy身份的`MediaInfo`。F-013作为TV兼容缺陷驳回且用户决定跳过修复；CHK-002收口为删除正式清单中过时的“当前已回退”现状声明，本轮不改产品代码。
- `M001-A / H-004`：仅当模型同时声明合成 UI `id` 与 `raw_id` 时，业务/API 使用 `raw_id`；`Subscribe.id` 本身是后端业务 ID，不能一概替换。
- `M001-C/M001-D / F-011`：当前确认边界仅是 `TorrentInfo` 重编码会丢失官方生产并被下载链消费的 `site_cookie/site_ua/site_proxy/site_downloader`，已由`63767f9`补齐；通用 `MediaInfo` 嵌套 raw 保真仍属 CHK-003 未验证边界，不得借此建立通用 raw-shadow 框架。
- `M001-D / F-014`：来源选择须统一规范化空白及 `tmdb/themoviedb` 别名，不能用原始字符串的 `??` 代替。
- `M001-D / F-015/H-005`：`canDirectlySubscribe` 只能作为电影直订的正向谓词；进入分季流程必须另行确认明确电视剧。
- `B002 / H-007/F-018`：SwiftUI `body` 内避免反复创建 class Formatter 或固定解析器；只有单位、locale、时区和 nil 语义一致时才复用 helper，可选值不得先折叠为零再格式化。
- `B002 / F-021`：未知大小不显示大小信息，真实零值仍显示为`0 B`；修复提交 `a0adaab` 已覆盖下载任务统计、转移历史列表与详情三个出口，最终独立复审通过，tvOS Simulator clean build 与本地测试 427/427 通过（明确跳过 5 个真实后端兼容套件）。
- `B002 / F-017`：SwiftDate Region 只决定无时区输入的解释区域，显式 offset 必须保留；订阅更新时间、分享时间和资源发布时间在上游契约确认前不得视为同一种日期源。
- `B003 / F-019/F-020/F-026`：G06后Cookie生命周期与URL-only cache/in-flight分别为条件P1，未认证预取P2；受保护图片随会话隔离/失效，公共图继续共享，只按旧会话已知host/path清资源Cookie。
- `B003/B004/S002/M001-F/A001-B / F-019/F-020/F-026/F-027/F-062/F-063/F-065/F-086`：提交`90b40b4`已用原子session、epoch/profile/UI identity、私有Cookie vault、受保护图片namespace/downloader、revision/tombstone与候选登录一次commit闭合这些跨账号根因；最终独立暂存复审通过，tvOS Simulator会话/持久化聚焦测试8/8通过，真实后端兼容套件未运行。其他仅共享部分owner边界的finding不据此整体标记完成。
- `B003/S004 / F-026`：Paginator 图片预取必须与最终显示使用一致的认证 request option；这不能替代会话级 cache/in-flight 隔离。
- `S004 / F-033…F-036/H-010`：仅 provider 真实耗尽时空批才代表终页；Paginator 单点拥有错误/恢复语义，owner 显式取消在途分页，processor 按最终 ID 同时去重旧数组与当前批次。
- `B004/W015 / F-027/F-028/F-029/CHK-005`：鉴权请求、重登、用户快照、logout与原请求重试必须绑定单调session epoch；重登后还须重验发起动作requiredPermission，已打开Sheet和多阶段写链不得用新会话续接旧动作。
- `B004 / F-030/F-031`：G06两票将两项升P2；普通权限逐键只接受原生Bool true，畸形值拒绝该键但不得污染其他合法权限；外部access token必须非空白，tokenless快照只可与独立非空token配对。
- `B005 / F-040/F-041`：职位翻译与优先级必须共用同一 canonical key；未知职位保真并最低优先级，最终显示文本稳定去重。
- `B005/B006-C / F-044`：所有 Person.job 展示必须经过统一职位翻译边界；人物搜索不得直接显示 raw canonical job。
- `B007 / F-047/F-048/F-049`：取消确认须表达 owner、命中数、删除模式与范围并冻结不可变意图；业务失败使用现有错误通知，成功保持静默。
- `I002 / H-006`：`prioritizedJobs` 是 canonical job、翻译和优先级的唯一注册表；消费者先解析同一 canonical key，再排序/本地化，未知保真且 999，可复用合并状态不得存放本地化文本。
- `S006 / H-009/F-050…F-053`：人员调用方在截断前提供完整可展示候选；actor 合并保序，crew 只排序新增项，roles 逐项规范化取最高优先级，未用增量 API 不得承诺可安全自消费。
- `B006-A / F-038`：详情元数据统一 trim 并过滤空显示值；空白语言、日期、年份或国家名不得创建空 Text 或尾随分隔符。
- `M001-E / F-022/F-023/F-024/F-025`：搜索与最近媒体输入边界不得因单个坏项丢弃整批；F-022 已为资源嵌套模型的后端可空字段提供中性默认值，F-023 已将最近媒体缺失/null标题归一为空字符串并保留同批项目，修复提交 `af67839`，最终独立复审与本地 430/430 测试通过；轮询合并不得假定 fallback ID 唯一；下载和媒体服务器 UI ID 应优先不可变结构化业务键，动态大小、标题、link 与 UUID 不能承担稳定身份。
- `M001-E/S004 / F-032`：`Context` 的可选嵌套输入契约必须与资源卡片可展示条件一致；合法 torrent-only 项不得以非零计数进入结果页后静默渲染为空。
- `S003 / F-057/F-058/F-059`：`MetaInfo.season_episode` 的格式化与筛选排序必须共享同一 canonical 解析结果；范围终点参与排序，合法 S00/E00 与 invalid 分离，invalid 稳定置尾。
- `S001 / F-060/H-008`：所有生产诊断输出必须经 `Logger`；当前默认 handler 仅 Debug 输出，未来若启用 Release handler，须先对 URL、错误、账号和媒体值做隐私分级，禁止直接 `print()`。
- `S002 / F-062/F-063`：G06两票将两项升条件P1；UserDefaults明文fallback取舍不重开，但四项凭据须绑定同一session revision，access token删除失败以高权威logout tombstone阻止旧会话重启复活。
- `M001-G/S006 / F-055`：人物搜索最佳结果的头像准入必须复用最终 source-aware `imageURLs.profile`，不得用 TMDB 专属 `profile_path` 排除 Douban 等已有可渲染头像的人物。
- `M001-F/B007 / F-054`：当前实现已解决。`58c7e81`后Handler保留canonical/Bangumi/AniList/legacy身份，当前后端也按身份与season筛选；旧部署合同未验证，但不再作为当前P1开放。
- `M001-F/A001 / F-065`：分季与剧集组 cache/in-flight 必须绑定请求发起时的 session namespace，旧会话完成不得回填当前会话可见 key。
- `M001-F/A001-J/V018 / F-069/CHK-003`：目标v2.15.1的公共可写订阅字段已全部被TV建模，F-069不构成当前缺陷；后端以后新增可写字段时，必须同步核对Web完整表单、后端写入schema与TV `CodingKeys`，不得在未知字段未建模/未按正式合同保留时继续无提示完整PUT。
- `M001-F/V018 / F-066/F-067`：剧集组只允许明确 TMDB 主身份且正 raw TMDB ID；可选剧集组失败不得清空或阻断已成功加载的订阅核心配置。
- `M001-F/A001-J / F-068`：草稿可无 ID，但进入订阅快照、焦点和业务动作的记录必须具有唯一正业务 ID。
- `M001-G / F-064`：可选人物头像的格式错误不得拖垮 Person 或外层数组；已知 URL 键须宽容解码并选择首个 trim 后非空值；已由 `af67839` 修复，最终独立复审与本地 430/430 测试通过。
- `M001-G/S006 / F-056`：Hero 演员须在截断前按可展示非空姓名过滤，并允许后续完整结果补位。
- `M001-G / F-002/CHK-003`：Person 跨越后台嵌套解码与媒体回编码边界；解码不得读取 MainActor 全局配置。未修改嵌套载荷是否必须保留原形取决于实际 API/插件合同，当前不再作为 F-011 的已确认机制。
- `M001-H / F-072`：Transfer 的搜索、分页、轮询、存储加载及游标调整必须绑定同一 query generation 和发起时 session，旧结果不得写入新状态；`e388e8b`已让轮询固定启动时fetcher并在每次await后校验query/session代际。
- `M001-H / F-027`：`fetchSettings` 的 public/user 两段读取及全局 settings 发布必须属于同一 session；调用者返回后的 guard 不能替代发布点校验。
- `M001-H / F-071`：owner 保存的 escaping fetcher 不得反向强捕获 owner。
- `M001-J / F-074`：整理预览必须同时绑定不可变表单快照、请求代际和 session；失配响应不得发布或打开 Sheet。
- `M001-J / F-075`：批量手动整理必须保留逐 ID 的已受理、失败和未知结果，重试不得包含已确认受理项。
- `M001-J / F-076`：手动媒体 ID 搜索已由 `44908c4` 在提交时清空旧结果并拒绝关键词变化后的旧响应；聚合Search/Resource子项已由`d361fe4`修复（unified 新搜索开始清空 bestResults，请求在途/失败/会话变化不再残留旧结果，聚合结果只在完整刷新后覆盖）；统一session/generation门禁已闭合跨账号P1链；空查询保持与 Web 一致不改。
- `M001-I / F-077/F-078/F-079`：SubscribeShare 的 Fork 载荷与 `toMediaInfo()` UI投影是两个独立边界；当前schema要求保留`bangumiid/anilistid/media_source/media_id`，投影保留全部主身份，Fork不做未知raw透传；F-077/F-079 已由 `58c7e81` 修复；SwiftUI稳定ID不能代替唯一正后端分享ID。
- `M001-K/S003 / F-061`：软过滤的“未命中置尾”是结果页不变量；首次默认排序和后续用户排序均须先按 `isFilteredOut` 分区，再在各区应用排序键。
- `A001-A / F-082`：显式 `success:false` 必须先于可解码 data 判失败；`success` 缺失兼容与原始响应 fallback 应作为独立边界保留。已修复（`d8198fc`）：共享解包器先拒绝显式失败，错形 data 仅在目标解码失败后用既有 `JSONValue` 取服务端错误；聚焦测试、Simulator clean build、本地串行 438/438 测试及独立复审通过，五个真实后端兼容套件未运行。
- `A001-A / F-083`：下载动作只有契约确认的空 body 可兼容成功，非空不可解 body 不得 fail-open，首层响应须读取 `message_i18n`。
- `A001-A / F-084`：G06两票将其升P2；海报降尺寸只修改精确URL path段，并由主线程与后台媒体解码共用同一helper，第三方host/query/签名保持原文。
- `A001-A / F-027/F-065`：结构快照和页面 guard 不能替代单调 session epoch；共享 cache key 与旧请求回填须绑定发起时 namespace。
- `M001-K / F-080`：SSE 只有收到端点认可的明确成功终止才能成功收尾；业务 error、无终止 EOF 和取消必须分流，AI 的全部终止形态均须检查 `data.success`。
- `M001-K / F-081`：自定义规则输入边界须逐项隔离坏项并保证规范化后的 ID/name 非空唯一；实现已静默丢弃坏项并保留首个合法规则，用户明确接受已选规则缺失时继续静默不过滤且不新增错误 UI。
- `M001-K/S005 / F-085`：已修复（`7f9fd17`）：matcher 与后端 `__match_rule` 全字段对齐（include/exclude 任一匹配、空串视为未配置、空正则匹配一切、seeders/publish_time/size 解析与失败语义、pubdate 缺失/不可解析按 0 分钟、规则 ID 缺失硬过滤全排除软过滤全置灰）；规则内容非法显式报错，拉取规则网络失败放行；独立代理逐项复审通过，55 项定向测试通过。System 预览 trim 展示与 matcher 原始值的展示层差异保留。
- `A001-B / F-027`：请求、loginTask、递归重试、logout、currentUser/settings 发布必须绑定单调 session epoch；结构值相等不能防止 ABA。
- `A001-B / F-086`：baseURL 只在单一入口规范化并持久化，须保留反向代理 path-prefix；API/SSE/图片不能各自字符串拼接。
- `A001-C / F-087`：已修复（统一 `trimmedNonEmpty` 选择器）：服务端错误字段逐项 trim/filter 后按本地化优先级选择，空白首选值不再遮蔽后续有效 detail/message；与 Web `normalizeLocalizedMessage` 空串回退语义一致，纯空白为 TV 防御性回退。
- `A001-C / F-088`：登录与全部重登路径必须使用真正的 `application/x-www-form-urlencoded` 编码，`URLComponents.query/percentEncodedQuery` 不能直接充当通用表单编码器。
- `A001-D / F-090`：TMDB 识别、跳转和预加载只接受正 ID；0/负数不得遮蔽后续候选或完整详情正 ID，但不能借此无条件改写 MediaInfo 主身份的既有 Web-zero 语义。
- `A001-E/W017 / F-091/F-093`：下载器发现失败必须可恢复且不得伪装合法空；clients/list刷新须分loading/empty/error/stale/data并有重试，主动动作失败复用现有错误通知，成功保持静默。
- `A001-E / F-092/F-094`：下载动作须冻结非空有效 hash、客户端和目标状态；不得对可被轮询修改的当前状态 toggle，也不得把原始 hash 直接当 URL path。
- `A001-E / F-027/CHK-005`：下载读取与 stop/start/delete 必须绑定发起时单调 session epoch，旧会话不得在新 baseURL/token 上重放或发布结果；同会话客户端代际另由 F-095 约束。
- `A001-E / F-095`：下载列表发布与 mutation 必须绑定同一客户端代际；选择变化后旧客户端行立即不可操作，动作冻结并校验行所属客户端。已修复（`7b7130e`）：列表记录实际加载客户端，选择不一致时禁用旧行，暂停/继续/删除显式携带并前后校验行所属客户端；聚焦 8/8、Simulator clean build、本地串行 439/439 测试及最终独立复审通过，五个真实后端兼容套件未运行。
- `A001-F / F-098`：accepted 不等于 completed；当前合同只给整批结果，用户决定保持整批错误通知与权威刷新，不做 TV 单端逐 ID 推断。
- `A001-F / F-099`：手动媒体原生数值 ID 仅正值可覆盖规范化 fallback；0/负数不得遮蔽有效 fallback。
- `A001-G / F-096`：可选媒体服务器徽章探测不得触发自动重登或登出；失败保持未知并继续受 session 归属约束。
- `A001-G / F-097`：首页媒体服务器轮询须区分成功空、失败与取消；失败保留该服务器旧快照，取消不得发布。
- `A001-H / F-080/F-101`：SSE 按空行分帧并以换行拼接同一事件的多条 data；EOF 不等于成功，资源 missingSites 补偿只允许在端点明确成功终止后执行。
- `A001-H / F-102`：当前后端progress key仅含安全字符，特殊字符触发转未验证P3；若合同继续opaque，仍应在API边界按单一路径段编码一次。
- `A001-H / F-103`：资源 title/media-ID 意图由 builder 显式保存并保证值非空，API 不得从任意文本正则反推路由。
- `A001-I / F-104`：动态媒体键或人物不透明 ID 进入 URL path 时，由 API 边界整体编码为单一路径段；来源 token 保持固定白名单，调用者不得拆分、改写或重复转义。
- `A001-J / F-100`：同一规范化 media+season 的较新 force supersede 较旧普通 miss/force；`0cfeb12`已用同key request revision闭合旧响应写缓存/返回旧值，2026-08-11定向乱序回归通过。
- `A001-K / F-105`：可展示图片字符串只在共享 helper 中 trim、拒绝空白并按确认的 MoviePilot origin/path-prefix 绝对化，代理规则不得由模型或 View 复制。
- `A001-K / F-106`：真实生产模型图片包装须在访问时消费当前图片配置，不长期保存构造时的 baseURL/cache/TMDB 域快照；无生产消费的 wrapper 不扩展机制。
- `I001 / H-001/H-004`：统一媒体键端点复用模型 `identity/apiMediaId`，原生来源端点使用已验证 raw ID；只有同时声明 UI `id` 与 raw 字段的模型才区分二者，`Subscribe.id` 等仍是业务 ID。
- `I001 / H-003`：Models 的传输字段、raw 保真载荷、规范化包装值和 UI 派生状态必须分别判断；默认属性值不提供 Decodable 缺键默认。
- `I001 / F-002/CHK-003`：预计算外层图片 URL 不会自动纯化嵌套 Person/Share 后台解码；保留顶层 raw 也不会自动保留已建模嵌套原形，但后者的当前消费依赖仍未验证。
- `I001 / F-003/F-068/F-078`：进入季、订阅或分享持久快照的身份须满足对应有效性与唯一性；草稿可缺 ID，持久列表不可用 UUID 或可变展示字段冒充业务身份。
- `G09 / F-120/F-149`：mutation与Dashboard发布均复用现有operation/session snapshot；前者的目标/阶段必须单一归属，后者先收齐tuple且同session才一次发布。
- `G09 / F-151/F-152/F-156`：破坏性预览、确认和动作必须冻结intent/logID、对象签名及session/query；不得用实时选择或可复用Int ID替代动作owner。F-151作为当前官方Web v2与TV共享行为，已由用户决定跳过TV单端修复；F-152已由`fc0cefa`完成、通过458/458门禁及补测后的同一独立复审者PASS，F-156当前态另行复核。
- `G09 / F-153/F-154/F-232`：稳定排序前提下现有删除回退和插入余数算法未证实独立漏页，F-153/F-154驳回；分页正确性统一依赖`date DESC,id DESC`并保留组合测试。
- `G09 / F-161/F-162/F-165`：透明原生Button须退出focus/accessibility树，长反馈须有完整读取入口，业务Sheet须有内容内关闭；全部复用原生控件/现有ScrollView，不建UI框架。
- `G09 / F-188/F-189`：该结论对应审计时的后端v2.14.4快照；目标v2.15.1已包含2026-07-21的`3b709b7`统一媒体来源身份流，因此两项按旧基线误报驳回，当前TV保持统一字段合同，不回退legacy协议。
- `G09 / F-203`：目标文件删除结果是历史DELETE成功的前置条件；存在且删除失败时后端应保留历史并返回业务失败。TV/Web当前均依赖该后端回执，用户决定跳过本地后端修复，等待MoviePilot官方处理。
- `G09 / F-212/F-213`：两项历史验收分别要求目录使用`(storage,path)`复合身份、最终intent按媒体类型裁剪隐藏字段；用户本轮选择严格对齐当前Web，`a6cc428`只消除F-212的TV独有延迟，F-212复合身份增强与F-213隐藏字段裁剪均按决定跳过TV单端实现。
- `G09 / F-246/CHK-020`：TV与Web v2.15.1的manage入口已经对齐，用户决定跳过TV单端处理；后端整理历史GET的资源授权风险保留为上游范围外事实，CHK-020继续作为未来官方更新对齐项，独立于CHK-005的session owner。

### 本轮兼容清单建议索引

| ID | 状态 | 摘要 |
| --- | --- | --- |
| CHK-001 | 已确认 | 仅明确非负季号可建立 TV 分季身份；缺失/null/负值不得折叠为 S00，上游过滤/拒绝策略未验证 |
| CHK-002 | 已确认 | 当前Web/后端不支持仅legacy `mediaid`的`MediaInfo`；删除正式清单中过时的“当前已回退”现状声明，不给TV新增差异化兜底 |
| CHK-003 | 已确认 | 对后端已声明且当前生产链消费的字段，TV 强类型解码再编码不得静默丢失；通用嵌套原形仅在证实透传契约时保留 |
| CHK-004 | 已确认 | `canDirectlySubscribe == false` 不能直接推导为电视剧，只有明确电视剧进入分季 |
| CHK-005 | 已确认 | 请求、登录/settings/mutation/profile、高层action、子Paginator、延迟preload及长期根页route/focus/受限快照须绑定单调session epoch；重登重验权限，多阶段/批量动作共用owner；System整个加载epoch与权限tuple边沿已获两票 |
| CHK-006 | 已确认 | 取消入口须使用明确动作词与destructive语义；展示并冻结owner/命中数/精确记录或media+season范围，所有媒体身份都保留season；当前Web/后端共享非TMDB跨季删除须上游修约，不做TV单端兜底 |
| CHK-007 | 已确认 | 分季与剧集组缓存须绑定发起时 session namespace，旧会话响应不得回填新会话可见 key |
| CHK-008 | 已确认 | 补强现有订阅 ID 条目：持久快照须有唯一正业务 ID，巡检不得跳过异常记录 |
| CHK-009 | 已确认 | 分享列表须有唯一正业务ID，GET→Fork保留schema字段并投影全部主身份；最终确认页至少展示立即持久化的非空keyword/custom_words，其他字段待产品证据 |
| CHK-010 | 已确认 | 同键较新强刷后，旧 miss/force 不得写缓存或返回旧值，旧调用者复用最新结果；TTL 选择单独验证 |
| CHK-011 | 已确认 | 资源 SSE 按空行组帧并以换行拼接多条 data；仅明确成功终止可进入受限 missingSites 补偿，并合并既有条目 |
| CHK-012 | 已确认 | 下载list/start/stop/delete须按token subject校验owner，任务/owner身份包含downloader；superuser/API Token例外显式化，TV过滤不替代后端鉴权 |
| CHK-013 | 已确认 | 订阅total_episode保留null/0/正数及既有manual语义；GET→未修改PUT幂等，只有显式修改改变人工语义 |
| CHK-014 | 已确认 | save_path=nil表示自动，非空为API-ready本地/远程根或子路径；保留既有值、允许合法子路径并可清空 |
| CHK-015 | 已确认 | 删除任务与永久删除文件为两个显式动作；默认只删任务，永久删除单独确认不可撤销范围 |
| CHK-016 | 已确认 | 下载列表保留所有未完成paused/stopped等状态并排除已完成项；stop后轮询仍可见且可继续 |
| CHK-017 | 已确认 | mutation 2xx仅接受端点声明的合法envelope；畸形/非对象/缺success失败关闭，空响应仅按显式no-content合同接受 |
| CHK-018 | 已确认 | 资源搜索站点使用active searchable权威域并区分后端默认/全部/显式子集；第三裁确认共同长期验收F-209/F-210两条独立P2 |
| CHK-019 | 已确认 | 媒体搜索source须由后端声明并真实执行，测试断言provider/返回来源语义而非只看query；第三裁确认与正式清单不重复 |
| CHK-020 | 已确认 | manage-only资源的读取与mutation均须由后端校验active manage用户；客户端菜单/Tab/路由隐藏不是安全边界，低权限HTTP角色矩阵必须覆盖 |

### 最终回溯结论

- 下列条目保留审计发生时的依赖去向；其中“待/转回溯”只记录历史路由，不代表仍有开放队列。当前全部回溯、争议与依赖条目均已取得最终处置并闭环。
- 规定的两个上游相对目录仍缺失，但后续已定位并使用 Web `19710a5f…`/`v2.13.6` 与后端 `a0ee99aa…`/`v2.14.4` 的 clean Git 源码；不再保留全局阻塞，实际部署、远端最新性与运行配置按各 F/CHK 逐项标未验证。
- `S003/M001-K/S005 / F-061`：已确认 P2；默认和用户排序都须维持软过滤分区，C018-A/I011 已闭合实现边界与回归覆盖。
- `S002 / F-062/F-063`：G06两票均确认条件P1并已闭环；前者用logout tombstone阻止删除失败后恢复，后者给四项记录同一session revision，明文fallback产品取舍不扩张。
- `M001-G / F-064`：模型根因已确认并已修复（`af67839`）；后续 API/详情入口只需核对传播与错误呈现。
- `M001-F / F-065…F-069`：F-065为条件P1，F-066/F-067/F-068为P2；F-069经当前v2.15.1合同复核降为未来兼容P3并转CHK-003。三缓存owner、正TMDB、可选失败隔离与正唯一ID边界不变。
- `M001-H / F-070…F-072`：G09已将F-070升确认P2，F-071维持P2、F-072维持P1；统一代际与能力默认边界已闭合，单元只随G01/G06程序队列收尾。
- `M001-J / F-073…F-076`：clean-room窄裁确认F-073仅在`success:true + data缺失/null`与item success缺失/null两支fail-open，转确认P2；F-074/F-075 P2；F-076原跨owner P1链闭合，当前同会话余项P2。
- `M001-I / F-077…F-079`：F-077/F-078已确认；F-079经当前后端91ce365f与Web 7ea14bc9合同裁决，从未知raw风险收窄为`anilistid/media_source/media_id`三个已知字段丢失并确认P2；G02/A001/Fork/session/刷新链回溯已闭合。
- `M001-K/S005 / F-080/F-081/F-085`：三项均已确认；F-085 已修复（`7f9fd17`）并经独立代理逐项复审，目标部署后端路径/版本与正则方言差异仍留 V002/W020/I003/I004/I016/G01/G05 回溯。
- `A001-A / F-082…F-084`：三项均确认；G02末裁将F-082升条件P1，F-083/F-084 P2，API/下载/图片路径闭合。
- `A001-B / F-086…F-088`：G02末裁将F-086升条件P1、F-087升P2，F-088 P2；登录candidate commit、错误文本与form/query边界闭合；F-087 已修复（统一 `trimmedNonEmpty` 选择器）。
- `A001-C / F-089`：G06两票核到当前后端凭据/MFA失败为401并闭合System手动刷新清旧有效会话，转确认P2；403仍只作条件分支。
- `A001-D / F-090`：已确认条件性 P3；待动作、预加载、详情、订阅补查和 I003 回溯非法值传播。
- `A001-E/W017 / F-091…F-095`：F-091/P2、F-092/P2、F-093/P2、F-094/P2、F-095/P1均确认；F-094后裁来源为G05。client代际与动作目标不并入session CHK-005，行须绑定downloader+task并在切换时禁旧行。
- `M001-E/W017 / F-024`：升级确认条件性P1；无hash fallback碰撞首次可进入数组，下一轮`Dictionary(uniqueKeysWithValues:)`不可捕获trap。显式规范化身份与检测重复后失败关闭，转I001/I003/G04/G05/G10回溯。
- `W017 / F-196/F-197`：F-196的TV提示由`e47693a`明确为永久删除任务及已下载文件；F-197由用户决定跳过TV单端修复，CHK-016已进入正式兼容清单，等待MoviePilot官方后端/Web变化后同步对齐。
- `A001-G / F-096/F-097`：两项均已确认；转 V008/V012-A/W003/W008/G03/G06/I003 回溯可选探测会话副作用与轮询失败保留语义。
- `A001-F / F-098/F-099`：G09两票分别将逐ID terminal receipt升P1、正ID边界升P2；F-098用户决定保持现状，F-099继续独立于F-090，具体owner/调用者回溯已闭合。
- `A001-J / F-100`：原条件性P1已由`0cfeb12`修复；每key revision覆盖双调用者与最终缓存，2026-08-11定向乱序回归通过。TTL产品选择仍为独立边界。
- `A001-H / F-101…F-103`：F-101 P3、F-103 P2确认；F-102因当前producer安全转未验证P3，G05/G09已闭合状态边界。
- `A001-I/A001-J / F-104`：已确认条件性 P2；A001-D 仅回溯 Douban recommendations，A001-J 增补任意 EpisodeGroup.id；similar 与数字型 TMDB/Bangumi 分支不重开，转 I003/G03/G07 核对统一单段编码与用户可见失败。
- `A001-K / F-105`：已确认 P3；转 I003/I005/G03 回溯相对/空白图片值、MoviePilot origin/path-prefix 与共享 displayImageURL 最小边界。
- `A001-K/I003 / F-106`：已确认 P2；图片wrapper仍回溯启动/前台settings时序、生产模型存活与访问时重算，I003双审新增两阶段settings跨会话混合、吞取消与旧发布；切服旧树只保留未验证。
- `V001 / F-107`：原P1主触发已由`90b40b4`修复：会话UI身份切换会清旧banner/计时，`show()`同步发布；剩余仅旧业务调用者在切号完成后晚到show，影响为短暂提示错位，降P2且用户决定跳过不改。
- `V001 / F-108`：未验证、条件性 P3；静态触发与错误清空链成立，但 tvOS Sheet 是否遮挡根 overlay、五秒可见窗口及焦点必须运行验证；回溯 C002/R001/V017/W013/V022/W019/G08。
- `V001 / H-012`：已确认；成功操作保持静默，周期请求按生产者 error episode 去重并在恢复/会话变化时清 latch，用户主动操作每次失败仍须反馈，不做全局同文案去重。
- `V002-A/B / F-109`：G06两票升P2；profile偏好使用canonical baseURL与权威currentUser组成的版本化无歧义tuple，四个旧prefix同批一次迁移，异步操作冻结同一key；G01争议关闭。
- `V002-A/B / F-111`：已确认 P2；合法 token-only 会话恢复后必须使用与当前 token/session 绑定的权威用户名，身份未解析时延迟 profile 读写，不降为 `default`；legacy `default` key 不可无损判主，相关回溯已闭合。
- `V002-C/D / F-112`：已确认 P2；站点权威成功空必须清除旧选择，失败/取消须与成功空分流并提供现有入口的最小恢复；Search/详情继续发送旧ID的传播与相关回溯已闭合。
- `V002-D / F-113`：已确认条件性 P2；异步默认站点归一化须冻结发起时 session/profile key，成功、失败与取消的过期结果均显式中止，调用者不得继续导航；回溯 V005/V007/V015/W003/W011/C014/R001/I004/G01/G05/G06。
- `V003 / F-114`：已确认 P3；Search/MediaDetail 父 VM 固定持有 SiteFilter 子对象，须复用现有事件桥接让按钮及时刷新；仅影响 UI 新鲜度，回溯 V011/V012/W006/W008/I007/I008/I012/I013/G01/G03。
- `V004-A/I005 / F-115`：已确认 P2；详情ready复用规范化字符串、正ID与已支持身份；详情响应可用后立即启动season，图片/识别不得把有订阅权限电视剧全屏Loading串行延长，回溯I008/G02/G03。
- `V004-A / F-116`：已确认P2；G03两张正确映射票确认cache-hit先揭示内容、VM初始化未装背景、View task后补背景的确定顺序；实际闪烁时长、焦点与真机表现仍列运行未验证。
- `V004-A / F-117`：已确认 P3；图片预取取消标记与 Kingfisher handle 安装须原子，已取消 operation 不得随后启动、写缓存或发布 ready；回溯 V004-B/V023/R001/R002/I005/G03/G06。
- `V004-B / F-118`：已确认P2；G03窄第三裁确认无owner/refcount会令多owner提前解除保护，push/Tab/State、返回后通知刷新及LRU组合的端到端时序仍需运行验证。
- `V004-B / F-119`：已确认P2；G02全局裁确认精确ID/recognized-TMDB仍只覆盖部分alias，非pinned alias可长期显示旧订阅状态；保存/取消回写须线性扫描当前小缓存更新全部canonical alias，点击时fresh lookup只限制错误mutation。
- `V006 / F-120`：降P2且用户决定跳过；卡片共享busy主要造成异目标动作丢失/迟到UI，Reorganize preview/submit交叉与当前Web一致，本项未证明错目标mutation，具体破坏性风险仍由F-074/F-075/F-152/F-156承载。
- `V006 / F-121`：已确认P2；Fork错误不绑定presentation/share/operation，A可污染B。复用F-193 operation token并保留错误状态专属回归。
- `V005 / F-122`：已确认 P3；最终 error/cancel 与 no-match 共用 nil 并被误报不存在，Home 仍提交标题回退导航；首段失败但 fallback 成功不算用户缺陷，真 no-match 提示产品意图未验证。
- `V005 / F-123`：已确认条件性 P2；旧 A 动作可在切 B 后以 B 凭据发起后续识别请求，独立于 F-027/F-113；按钮起点到多 await/全局状态/导航已纳入 CHK-005，当前仓库需统一引入单调 epoch。
- `V007 / 会话传播`：无新增 finding；旧自动登录 A→logout→手动登录 B→A 迟到 200 可在 B baseURL 下覆盖 token/currentUser/四项凭据，归 F-027；login acquisition owner、单调 epoch 与 A→B→A 已纳入 CHK-005，F-107/F-113/F-123 只闭合传播入口。
- `V008 / F-125`：已确认 P3；本项目声明版本的本地 v2.15.1 tag 生成 Plex `/server/{machine}/details?key=`，TV 只解析旧 `/media/...` 后退化 generic scheme；只确认解析/身份丢失，tvOS Plex 精确 scheme 仍未验证。
- `V008/W013-A / F-126`：已确认P2；Home把失败与成功空/旧快照共用outcome，分季页又在成功前置hasLoaded并在取消后不复位，Tab保留同owner重现时自动重载被锁死。各owner只在完整成功后锁门闩，取消复位且不发布错误，保留现有retry，不建加载状态机。
- `V008 / F-127`：已确认条件P1；无确认reset覆盖多项运行/优先级/人工字段并恢复R。用户决定跳过修复，保持当前直接重置行为。
- `V008 / F-128`：已确认 P3；不支持/非法媒体库链接与异步 openURL 拒绝均只有日志、无用户反馈；修复须保留异步 callback/outcome，与 F-125 解析契约、F-060 日志治理独立。
- `V009-B / F-129`：已确认P2；G01/G04双票确认Popular按title保留A/B但最终SwiftUI ID相同并破坏focus/firstIndex/loadMore；与F-036独立，与F-138共用中央identity实现但保留专属回归。
- `V009-C / F-130`：已确认条件P1并由`90b40b4`闭合；账号、服务器或权限指纹变化会重建整个Tab子树并清预加载，所有session转换递增epoch、取消旧runtime，Paginator/根媒体动作拒绝旧结果；同账号同权限换token只取消旧请求而保留UI。当前官方后端登录与`/user/current`均提供强制正`user_id`，聚焦会话/缓存/分页/根页面测试96/96通过，既有独立复审PASS；F-244继续作为重复编号并入本项。
- `I006 / F-233…F-238`：受限集成与G04末裁闭合；F-233/F-234/F-235/F-236均P2、F-237驳回、F-238未验证P3。最终报告永久披露无法取得严格零暴露文件集成票。
- `V009-D/E / F-131`：已确认条件性 P2；G05两名代理再次确认Douban/Bangumi/AniList用非公历Calendar.current生成并直传年份；实际tvOS非公历配置频率仍未验证。
- `V009-D/E / F-132`：已确认 P3；TMDB movie/tv 类型切换保留另一类型独占 sort key，Picker 无匹配而请求继续携旧字段；只在新字典不含旧值时回落默认，保留共有字段。
- `V009-A/E/F / F-133…F-135`：F-133/F-134 未验证 P3，unsupported filter_ui 与复合 query 结构须待固定部署 fixture/契约到位再重开；F-135 已确认 P3，重复 option tag 与空目录生产链已闭合。均不引入通用 FormRender/query 框架。
- `V009-E/F / F-136`：转未验证 P3；TV Share 初始/切源默认 count，而本地 v2.15.1 Web 与测试默认 time，差异已确认但 TV 产品意图缺失；明确 Web 对齐时确认，明确 TV 热门特例时驳回。
- `V011-A/B / F-137`：已确认条件性P2；无界长度罚分穿透四类评分带并可把真实匹配挤出top-12；使用互不重叠带宽和clamp即可。
- `V011-A / 权限 focus`：不立本段 finding；存活 SearchView 权限互换后旧 searchType、可见按钮、结果 switch 与 focus target 可能分裂，已转 V011-C/W006-A/I007/G01/G06 闭合自动归一化和 tvOS focus 可达性。
- `V011-B / F-140`：已确认 P3；提交 query 与本地评分未共用 trim 后字符串，`Hamilton ` 可令精确标题不匹配、扩展标题反获前缀分，纯空白还会请求；转 V011-C/W006-A/I007/G01。
- `V011-B / F-141`：已确认 P3；TV 把查询中首个任意四位数字当年份，`1917 2019` 与目标 v2.15.1 后端 title/year 边界分裂，括号年份移除还残留 `()`；当前部署未验证，转 V011-C/W006-A/I007/G01。
- `V011-C / F-035/F-039`：均确认P2；显式cancel/new-search屏障有效，缺口收窄为owner离场与整次session废弃后没有aggregate cancel。单waiter取消不得误伤另一合法waiter。
- `V011-C / F-130/CHK-005`：Search 与 Explore 同根不观察已发布权限；存活 View 可保留旧模式、focus/profile 状态与受限 Paginator，结构 session snapshot 又不能识别 A→B→A，转 W006-A/I007/G01/G06 独立复核与运行验证。
- `V011-C / F-076`：Search 资源 fallback catch 先写错误后才 guard，且 B 双重失败不清 A 旧结果；与既有“新查询失败/过时仍暴露旧 items”根因、修复和回归相同，不另编号。
- `V011-D / F-138`：已确认 finding 的同根条件扩展；三类 Search processor 按共享 ID first-wins，共享 key 又遗漏 collection_id，合集碰撞机制成立；当前上游缺失，生产输入终态未验证，固定 fixture 到位后才决定把 collection_id 置于 title fallback 前。
- `V011-D / F-036`：已确认 finding 的生产补强；人物 processor 应按最终 `Person.id` 使用可变 seen set，覆盖同页、nil raw ID与不同 source 的同 raw ID，转 W006/I007/G01/G04。
- `V011-F / F-034`：已确认 P2；共享 actor 最多扫 API 1–6 页，第 7 页才出现目标类型时在内部 hasMore 仍真时返回空批并被 Paginator 永久判终页；转 I007/W006/G04。
- `V011-F / F-142`：已确认条件性 P2；共享 task 先把 apiPage 0→2，但 handle 只由创建者 continuation外层 defer清理，TV waiter可先恢复并在第二轮重放完成 handle，使该轮2→2并提前返回内部hasMore=true的空批。页1/2各4部电影、页3八部电视剧反例成立；与F-034扫描上限、F-039取消所有权独立，真实频率未运行验证。
- `V012-A / F-100`：原Preloader normal与详情force同键重叠反转动作判断链已由`0cfeb12`的revision/latest语义闭合。
- `V012-A / F-130/F-138/F-139`：独立复核确认权限热变令分季/首屏gate不收敛、共享ID碰撞造成task失败/取消/ready/pin与season fallback alias、retained推荐/相似成功空无恢复。原“全nil不同title把A fullDetail/背景/推荐灌入B”会被apiMediaId guard拦截，合法wrong-detail碰撞fixture缺失，正式收窄为未验证。
- `V012-B / 取消链`：无新编号；准备失败开放、执行重查、owner/count/scope未冻结归 F-047/F-048/CHK-006，业务 false/异常静默归 F-049，session/cancel owner归 F-027/CHK-005，重叠 busy/alias/latest-wins归 F-120/F-119/F-100。
- `V012-C / F-047/F-048/CHK-006`：独立复核确认生产只从电影 Header 进入、warning只统计电视剧且漏 AniList→TMDB fallback，测试又以电视剧直接调用 helper；准备失败/取消仍开放、确认后重查且未冻结模式/范围/session。用一次性不可变 cancel intent 收敛，不新建取消框架。
- `V014 / F-138/F-139`：合集详情无新编号；共享ID碰撞可继续污染NavigationPath并复用inert preload task，retained成功空无恢复；collection_id生产payload/普通part误路由语义缺固定fixture，保持未验证。
- `V013 / F-143`：已确认条件性P2；纯name Person可无条件进入死详情，credits已冻结入口A但详情nil回包可覆盖公开person，形成展示身份与请求owner不统一；不是两个请求都在await中漂移。复用身份规范化做route准入/owner，真实payload频率未验证，W009/M001/I001/G04/G07回溯已闭合。
- `V013 / F-144`：已确认P2；串行首载性能本身为P3子边界，P2来自System/Season/人物等宽catch吞取消后仍晚启下一阶段。先传播取消/阶段间检查，只有独立请求确需降延迟时再用`async let`。
- `W009 / F-185`：已确认P2；足够长合法biography在“完整简介”模态Sheet内没有ScrollView、分页或可移动焦点锚点，尾部无替代读取路径。Header保留有限行预览，Sheet只需原生纵向ScrollView，并验证遥控器/VoiceOver到达末尾，不建阅读框架。
- `W009/W013-C / F-185`：季详情的无上限overview与人物完整简介共享同一无ScrollView静态Sheet根因；原生纵向ScrollView统一覆盖，不新增阅读组件。
- `W013-C / F-190`：已确认P3；S00缺名在详情显示“第0季”而同页卡片显示“特别篇”，空白name/date/overview又产生空标题、图标空行或空壳区域。复用现有trim→nil与单一季名回退规则，不建显示模型。
- `W013-C/W015 / F-191`：已确认P3；360×540只用于图片processor，两个Sheet外层容器width-only，URL缺失/loading/失败/成功四态均无明确2:3槽位。直接固定360×540，不抽组件；具体塌缩/拉伸及焦点影响待运行验证。
- `W011 / F-186`：已确认P2；TV从数值倍率重算促销并把合法30/70/25/75压成50、4X压成2x，筛选值与卡片及当前Web/后端`volume_factor`枚举分裂。删除重算helper并复用现有原始字段，以完整枚举表驱动，不建促销模型。
- `W011 / F-187`：已确认P2；资源业务error、transport失败与成功空都会进入无action空态并由hasSearched阻止同页面重试。复用EmptyDataView action和现有cancelSearch→search即可，不建恢复状态机。
- `W012 / F-188`：历史v2.14.4快照条件性P1；目标v2.15.1已包含`3b709b7`统一合同，后续复核驳回为基线过旧误报，不改当前TV。
- `W001/W012 / F-189`：与F-188同属旧后端快照；目标v2.15.1已统一source/ID流，后续复核驳回，不做旧schema客户端过滤。
- `W008-E/W010/I013 / F-184`：合法正数合集条件性P1已由`e0f1122`修复；Home/Explore/Recommend/Search统一合集分流，所有来源共用预载门禁，487/487测试及独立复审通过。0/负数、parts包装/递归仍未验证。
- `V015 / 资源搜索链`：双审完成、无新编号；业务error、无终止EOF、`enable=false`与`done+success:false`闭合F-080/CHK-011，多`data:`闭合F-101；旧结果/权限/session/过滤/路由并入F-076/F-130/CHK-005/F-061/F-081/F-085/F-103。补偿append无去重且Context.id不含site机制成立，但缺重叠fixture/唯一性契约，只补CHK-011合并身份验收。
- `V016 / F-145`：已确认 P2；G05两名代理确认下载器初始nil可省略提交，但options无空值，选中后当前Sheet不能恢复省略状态。复用仓内“默认/自动”空option与现有Binding，不扩Picker框架。
- `V016 / 下载 mutation`：无其他新编号；跨会话提交/旧完成并入 F-027/CHK-005，重复 POST与旧defer清busy并入F-120，TorrentInfo四个官方字段丢失并入F-011，通用media原形留在CHK-003未验证边界，手动正ID与旧结果/错误/权限分别并入F-099/F-076/F-087/F-130。
- `V017/W013-B / F-146`：已确认条件性P1并由`0cfeb12`修复；每次加载冻结剧集组、revision与session，季列表、入库、订阅摘要、错误及loading只允许最新owner发布。A慢B快与旧订阅阶段两条定向回归均在当前本地451/451测试中通过。
- `V018/W014 / F-147`：Subscribe P1子项已由`a872737`修复；保存中禁用取消，系统返回当下同步冻结saving状态并跳过回滚，只有该返回路径最终保存成功才发一次全局成功提示；整理Sheet的提交中关闭P2已由`2ce68f8`修复（提交中禁用取消按钮，完成/失败后恢复），tvOS Simulator 构建及整理模块/兼容端点 60 项定向测试通过。
- `V018/W013-B/W014 / F-148`：已确认条件性P1；loading分支可令Retry误删、退出/session变化遗留；当前后端`exist_ok=True`重复创建又返回既有ID，TV丢失created/reused后无条件暂停并可在取消时删除。稳定根关闭观察与同session created/owner receipt统一收敛；reused ID永不由本次pause/delete。
- `W014 / F-195`：已确认P2；当前后端按LF拆分多条custom_words且Web使用textarea，TV单行输入无法创建/可靠审阅第二条规则。仅该字段使用tvOS多行控件并保留LF原值，不改全部文本字段。
- `W014 / F-170`：已确认P2；历史停用站点或删除/失权规则组脱离options后不可见、不可清且继续PUT，当前后端可回退默认站点或规则fail-open；只显示并允许主动清域外值，不自动求交。
- `W014 / F-199`：已确认条件性P1并由`ce7afcc`修复；现有订阅nil显式编码为null，新建nil仍省略，负数/空白/非法输入归一为nil，0与正数保留。依赖解析、Simulator clean build、490项本地测试及独立复审通过；F-069经当前v2.15.1合同复核后仅保留CHK-003未来升级边界。
- `W014 / F-200`：已确认条件性P2；已有任意值和配置中已有远程URI会显示并原样保存，缺口仅为封闭Picker无法新增/编辑任意合法子路径或URI。复用现有文本输入直接绑定String，配置路径仅作快捷建议。
- `W014 / CHK-013/014`：F-199三态编辑幂等已由`ce7afcc`及回归测试落实；F-200保存路径值域仍待处理。两项均保留为长期兼容回归边界。
- `W015 / F-193`：`90b40b4`已通过来源profile/session receipt闭合A POST后切B、再用B同号GET打开错误编辑器的条件P1链；当前只保留同一profile内operation/presentation竞争与GET-only恢复P2，不扩账号框架。
- `W015 / F-194/CHK-009`：已确认P2；POST立即持久化keyword/custom_words，但最终确认页不展示。最小只读显示这两个非空字段并支持长/多行可达，其他字段待产品证据。
- `W015 / 既有传播`：401续登后权限撤销仍重放写动作令F-027升级P1并补CHK-005；成功不发`.subscriptionDidUpdate`归F-008，旧错误归F-121，长文本归F-185，海报归F-191；F-164维持运行未验证。
- `W016 / F-149/F-150`：F-149因同权限跨session发布升P1，分项混合快照子案P2；F-150维持P2。分别复用session snapshot+一次发布与现有superuser gate。
- `W016/W017 / F-091`：已确认P2传播；首次clients失败后selectedClient为空，而3秒循环只调空client立即返回的loadDownloads，页面永久伪空直至ViewModel重建。失败轮询复用initialLoad，成功空配置单独呈现。
- `W016/W017 / F-192/CHK-012`：按用户确认范围由`b304b58`完成TV/Web对齐：普通用户仅展示`userid/username`属于当前账号的任务，superuser保持全量；聚焦9/9、依赖解析、Simulator clean build、本地488/488测试与独立复审通过。后端list/start/stop/delete对象级owner授权仍为明确接受的范围外风险。
- `W017 / F-024`：已确认条件性P1；缺hash fallback无分隔拼接/UUID可重复，首次重复进入数组后下一轮`Dictionary(uniqueKeysWithValues:)`确定终止App。规范化不可变身份并显式检测重复后失败关闭；普通身份抖动仍P3。
- `W017 / F-083/F-092/F-093/F-094/F-095`：F-083/F-092/F-093/F-094均P2，分别以严格非空动作解码、单行busy+目标赋值、错误/陈旧/重试及规范hash路由收敛；F-095因错client可删文件为P1。
- `W017 / F-196`：TV提示已由`e47693a`按用户决定修复为“将永久删除任务及已下载文件”；只改一行文案，不改接口/后端。按用户要求未运行测试、未做子代理复审，暂存范围检查通过。
- `W017 / F-197`：已确认条件P1但用户决定不修；当前TV/Web共享暂停后消失行为，不做TV本地缓存兜底。CHK-016已写入正式清单，官方后端返回paused/stopped、增加状态参数或Web新增恢复入口时同步对齐。
- `W016 / F-198`：已确认P2；当前后端明确nil为未获取且Web如此展示，TV稳定误报为0。仅View层nil→未获取，0/正数原样。
- `W016 / Transfer下游`：Paginator错误无呈现/重试、外部删除/更新不对账、Sheet dismiss/refresh焦点竞态、旧session、长详情与search闭包环转W019完整闭合；长详情优先归F-185，不在W016抢先编号。
- `B007/W013-B / F-047/CHK-006`：当前后端已对所有媒体身份按season筛选，旧“非TMDB跨季删除”证据失效；仍确认条件性P1：同媒体同季存在多group/多owner时，TV只展示一条却可能通过媒体级接口删除该季多条记录，Web共享同一接口。应冻结精确ID与实际owner/count/scope，不做TV单端宽删除兜底。
- `B007 / F-047/F-048`：当前Web同样先弹通用确认，再按当前媒体身份与season执行媒体级删除，没有冻结精确订阅ID；用户据此决定TV端跳过，不做单端额外增强。
- `V019/W016 / F-149`：已确认P1；除固定await混合快照外，同权限A响应可写入B会话。先收局部tuple，校验发起时session后一次发布。
- `V019/W016 / F-150`：已确认P2；manage-only合法使用下半页时，上半页三张superuser-only卡稳定误报“暂无”。复用现有权限gate隐藏整组或显示一次说明。
- `V010 / F-138`：已确认条件P1并由`ff4ea14`修复；无任何现有媒体ID时，共享`MediaInfo.id`追加trim后的标题兜底，有ID、0/空串及SubscribeShare快路径保持原语义。依赖解析、Simulator clean build、本地串行451/451测试及独立复审通过，五个真实后端兼容套件未运行。
- `V010 / F-139`：已确认条件P2；Recommend/详情/合集retained成功空后无恢复入口，复用现有激活边沿仅刷新成功空terminal。
- `V006/C014 / F-124`：已确认条件性P1并由`4a1a291`修复；菜单把生成标签的同一订阅状态传给Handler，fresh lookup后先校验session，mismatch只更新缓存并提示重新操作，不执行相反mutation；明确取消继续使用动作词/destructive role和CHK-006确认。聚焦5/5、排除真实后端兼容套件的完整本地450/450及同一独立复审代理最终PASS。
- `I010 / F-020/F-174/F-239及传播`：第三裁及后续G03纠偏闭合；F-020条件P1、F-174升P2且poster/session仍留F-123、F-239 P2，其余传播不变。
- `I014 / SubscribeSeason整文件`：严格集成与定向复核闭合；F-012当前P2由`Subscribe.navigationMediaInfo()`漏字段与身份优先级反转支撑；canonical-only TMDB group raw限制与Web相同且订阅入口通常会经完整详情补raw，改留用户路径未验证P3边界；F-243等其余传播不变。
- `I016 / System整文件`：G06完成最后等级裁决，F-089按当前后端401转确认P2；F-106/F-111/F-112/F-240 P2、F-208/F-242 P3、F-241未验证P3不变，受限集成闭环。严格零暴露票不可能取得并须永久披露。
- `G01 / 第一轮全局回溯`：纠偏及G04交叉裁后，F-244机制并入升级后的F-130/CHK-005并驳回重复编号；F-076/F-129/F-138/F-139等级已收口，其余分歧继续由G05/G06/窄裁处理。
- `G02 / 第一轮全局回溯`：主审完成；无新编号，F-175/F-171吸收MediaCard语义，MediaPreloader当前不成案。F-014当前代码反证及多项P级/范围修订与既有裁决冲突，全部等待不同代理复核，不先覆盖历史两票。
- `G03 / 第一轮全局回溯`：首轮对象错位意见已冻结并经纠偏/窄第三裁排除；最终F-245独立确认P2并与F-083仅共同挂CHK-017，F-219继续驳回，F-097/F-116/F-118/F-171/F-174/F-221均收敛P2，组已闭环。
- `S005/C018-B/W011 / F-110`：已确认P2；G05两名代理再次闭合default方向控件/箭头会切换但比较器忽略`isAsc`的稳定反例。比较器遵循现有方向，或若产品只允许默认顺序则隐藏方向控件；不建排序抽象。
- `M001-A / F-006（2026-08-11 Web v2.15.1 纠偏）`：官方 Web 对 raw 数值 ID 使用 JavaScript truthy 语义，`0` 跳过、负数保留；canonical/legacy 字符串 `"0"` 仍有效。当前工作树仅修正 lookup raw `0` 遮蔽 fallback，并补齐 canonical/AniList DTO，不再采用“所有非正数过滤”的错误方案。
- `I014 / 分季合并门禁`：`SeasonSubscriptionSummary` 已严格对齐 Web v2.15.1 的 canonical → legacy → raw TMDB/Douban/Bangumi/AniList 顺序；高优先级字段存在即返回比较结果，避免不匹配后再由辅助 ID 误标已订阅。
- `C016 / F-054 身份投影补全`：保留既有“操作前最后 lookup，并以响应身份取消”的设计，不改成当前卡片身份；成功后优先回写点击项缓存，再按响应身份 fallback 查找，避免 custom canonical 删除成功但菜单仍显示已订阅。
- `main 合并准备`：已由 `b0268d2` 合入 `origin/main@1b36042`，该提交现为当前分支祖先；README 同时保留 v2.15.1 兼容说明、IPA、社区 TestFlight 与 Xcode 安装方式。
- `最终验证`：依赖解析、Apple TV Simulator clean build 均通过；本地标准串行套件 512 项（15 skip）0 failure。当前实际 v2.15.3 后端/前端的全部兼容套件 78 项（0 skip）0 failure，其中只读巡检 8/8、副作用套件 7/7；`site_proxy`、`PersonAvatar` 与资源 SSE 认证探针均已按生产链修正。已核对 v2.15.1 后端源码基线 `7a5e565b15c5d7ca1a101a210c6fecc595ebf1f9`，但最终 tip 未另起精确 v2.15.1 实例重跑真实后端套件。
