# MoviePilot-TV 全量代码审查计划 (Full Review Plan)

本计划涵盖项目所有 Swift 源码文件。为了在单文件审查模式下保持最佳的上下文连贯性，审查顺序已经过优化：**底层基建优先，上层业务按功能模块（ViewModel -> View 结对）推进。**

## 📅 审查进度表

### 1. 数据模型与核心扩展 (Models & Core Extensions)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `Models/Models.swift` | ✅ 已完成 | 1. ⚠️ **核心规范**: API 请求的媒体标识符**必须**使用 `apiMediaId` 计算属性 (`MediaInfo`/`Subscribe`模型提供)。严禁手动拼接。<br>2. 已提取 `isCollection` 存储属性，后续审查判断合集请直接复用此属性。<br>3. ⚠️ **注意**：`Models` 中的模型既包含 JSON 直接解析的字段，也包含 Swift 内部计算处理的属性。后续审查 AI 在遇到模型字段时，**务必先阅读 `Models` 中 Struct 的具体实施**，避免重复计算或误用。<br>4. ⚠️ **注意**：很多 `id` 字段可能是为了 SwiftUI 渲染稳定而拼接的 UUID。若后续业务逻辑需要使用原始 ID（对应 Vue 端的 ID 使用场景），**必须显式使用 `raw_id`**，绝对不可误用拼接后的 `id` 字段。<br>5. 已提取 `canDirectlySubscribe` 计算属性，用于判断是否可以直接订阅还是分季订阅。后续审查中如需此逻辑，直接复用，严禁自行重新实现。 |
| `Models/JobRegistry.swift` | ⏳ 待开始 | |
| `Extensions/Formatters.swift` | ✅ 已完成 | 1. 严禁在 View 内实例化 `Formatter` 防掉帧。格式化大小用 `Int64.formattedBytes()`，相对时间用 `String.toRelativeDateString()`。 |

### 2. 服务层 (Service Layer)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `Services/APIService.swift` | ✅ 已完成 | |
| `Services/KeychainHelper.swift` | ✅ 已完成 | |
| `Services/Logger.swift` | ✅ 已完成 | 全局静态调用: `Logger.verbose/debug/info/warning/error("message", metadata: ["key": "value"])` |
| `Services/StaffManager.swift` | ✅ 已完成 | 内部已实现全量去重与排序。后续在处理分页/LoadMore 业务时，ViewModel 直接传入全量合并后的数组即可，无需也**绝不要**在外部手动去重。 |
| `Services/Paginator.swift` | ⏳ 待开始 | |
| `Services/ParsedSeason.swift` | ✅ 已完成 | |
| `Services/TranslationHelper.swift` | ✅ 已完成 | |
| `Extensions/KingfisherCookies.swift`| ⏳ 待开始 | |

### 3. 全局状态处理器与工具 (Global State & Handlers)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/NotificationManager.swift`| ⏳ 待开始 | 全局 `ObservableObject`。在 `ViewModel` 中调用 `notificationManager.show(message: "Error Message", type: .error)` 来显示错误通知。 |
| `ViewModels/MediaPreloader.swift` | ⏳ 待开始 | |
| `ViewModels/MediaActionHandler.swift`| ⏳ 待开始 | |
| `ViewModels/SubscriptionHandler.swift`| ⏳ 待开始 | |

### 4. 通用基础 UI 组件 (Base UI Components & Modifiers)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `Views/Components/NotificationComponent.swift`| ⏳ 待开始 | |
| `Views/Components/EmptyDataView.swift` | ⏳ 待开始 | |
| `Views/Components/MediaCard.swift` | ⏳ 待开始 | |
| `Views/Components/PersonCard.swift` | ⏳ 待开始 | |
| `Views/Components/MediaGridView.swift` | ⏳ 待开始 | |
| `Views/Components/MediaContextMenu.swift`| ⏳ 待开始 | |
| `Views/Components/SheetStyles.swift` | ⏳ 待开始 | |
| `Views/Components/SheetTextField.swift`| ⏳ 待开始 | |
| `Views/Components/SheetPicker.swift` | ⏳ 待开始 | |
| `Views/Components/ShelfPicker.swift` | ⏳ 待开始 | |
| `Views/Components/MediaActionModifier.swift`| ⏳ 待开始 | |
| `Views/Components/SubscriptionModifier.swift`| ⏳ 待开始 | |
| `Views/Components/ActionRow.swift` | ⏳ 待开始 | |

### 5. 业务模块深度审查 (Feature-based Deep Dive: ViewModel -> View)

#### 5.1 登录模块 (Login)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/LoginViewModel.swift` | ⏳ 待开始 | |
| `Views/Pages/LoginView.swift` | ⏳ 待开始 | |

#### 5.2 首页与探索模块 (Home & Explore)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/HomeViewModel.swift` | ⏳ 待开始 | |
| `Views/Pages/HomeView.swift` | ⏳ 待开始 | |
| `ViewModels/ExploreViewModel.swift` | ⏳ 待开始 | |
| `Views/Pages/ExploreView.swift` | ⏳ 待开始 | |

#### 5.3 发现与推荐模块 (Recommend)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/RecommendViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/RecommendView.swift` | ⏳ 待开始 | |

#### 5.4 搜索模块 (Search)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/SiteFilterViewModel.swift` | ⏳ 待开始 | |
| `Views/Components/SiteSelectionView.swift`| ⏳ 待开始 | |
| `ViewModels/SearchViewModel.swift` | ⏳ 待开始 | |
| `Views/Pages/SearchView.swift` | ⏳ 待开始 | |

#### 5.5 详情页模块 (Details)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/MediaDetailViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/MediaDetailContainerView.swift`| ⏳ 待开始 | |
| `Views/Pages/MediaDetailView.swift` | ⏳ 待开始 | |
| `ViewModels/PersonDetailViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/PersonDetailView.swift` | ⏳ 待开始 | |
| `ViewModels/CollectionDetailViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/CollectionDetailView.swift`| ⏳ 待开始 | |

#### 5.6 资源结果与下载模块 (Resources & Downloads)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `Views/Components/TorrentCard.swift` | ⏳ 待开始 | |
| `Views/Components/BestResultCard.swift`| ⏳ 待开始 | |
| `Views/Components/TorrentsResultView.swift`| ⏳ 待开始 | |
| `Views/Sheets/AddDownloadSheet.swift` | ⏳ 待开始 | |
| `Views/Sheets/MultiSelectionSheet.swift`| ⏳ 待开始 | |
| `ViewModels/ResourceResultViewModel.swift`| ⏳ 待开始 | |
| `ViewModels/AddDownloadViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/ResourceResultView.swift` | ⏳ 待开始 | |

#### 5.7 订阅模块 (Subscriptions)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/SubscribeSeasonViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/SubscribeSeasonView.swift`| ⏳ 待开始 | |
| `ViewModels/SubscribeSheetViewModel.swift`| ⏳ 待开始 | |
| `Views/Sheets/SubscribeSheet.swift` | ⏳ 待开始 | |

#### 5.8 系统与状态模块 (System & Status)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/StatusViewModel.swift` | ⏳ 待开始 | |
| `Views/Pages/StatusView.swift` | ⏳ 待开始 | |
| `ViewModels/SystemViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/SystemView.swift` | ⏳ 待开始 | |

#### 5.9 下载管理模块 (Download Management)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/DownloadTaskViewModel.swift`| ⏳ 待开始 | |
| `Views/Pages/DownloadTaskView.swift` | ⏳ 待开始 | |

#### 5.10 转移与整理模块 (Transfer & Reorganize)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/ReorganizeViewModel.swift`| ⏳ 待开始 | |
| `ViewModels/TransferHistoryViewModel.swift`| ⏳ 待开始 | |
| `Views/Sheets/ReorganizeSheet.swift`| ⏳ 待开始 | |
| `Views/Pages/TransferHistoryView.swift`| ⏳ 待开始 | |

### 6. 应用入口与根视图 (App Entry & Root View)
| 审查目标 (文件/组件) | 状态 | 核心副作用 / 关键注释 |
| :--- | :--- | :--- |
| `ViewModels/ContentViewModel.swift` | ⏳ 待开始 | |
| `Views/ContentView.swift` | ⏳ 待开始 | |
| `App/MoviePilot-TVApp.swift` | ⏳ 待开始 | |

## ⚠️ 全局副作用与依赖备注 (Side Effects & Dependencies)

- [ ] ⚠️ **架构差异**: Vue端的分季订阅有两处实现（详情页的轻量实现、分季订阅弹窗的重量级实现）。tvOS端已统一为单一实现（`SubscribeSeasonView`），其功能与Vue的`SubscribeSeasonDialog`对齐。因此，后续所有分季相关的API审查，**仅以 Vue 的 `SubscribeSeasonDialog.vue` 逻辑为准**，忽略 `MediaDetailView.vue` 中的旧实现。
- [ ] ⚠️ **日志规范**: 项目已引入全局 `Logger.swift`，**所有 Log 信息必须使用 `Logger` 等方法输出，严禁直接使用 `print()`**。
- [ ] ⚠️ **通知规范**: 项目已引入全局 `NotificationManager.swift` ，**该通知系统仅用于向用户报告操作失败或需要用户干预的错误状态**。对于操作成功的场景，**严禁**弹出通知，应保持静默，通过 UI 状态的自然变化（如按钮禁用、列表刷新）来提供正反馈。

---
*最后更新时间：2026-03-11*
